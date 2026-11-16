# Test harness for the home-manager modules: evaluates them against a real
# home-manager source (no activation, no build of the apps themselves) and
# exposes what each module installs.
#
#   nix eval --impure -f tests/hm-module.nix options             # ArtCraft desktop entry values
#   nix eval --impure -f tests/hm-module.nix craftInstalled      # Craft store paths
#   nix eval --impure -f tests/hm-module.nix craftExpect         # the claims, as booleans
#   OUT=$(nix build --impure --no-link --print-out-paths -f tests/hm-module.nix hmEntry)
#   cat "$OUT/share/applications/artcraft.desktop"
#
#   nix eval --impure -f tests/hm-module.nix options --arg homeManager '"github:nix-community/home-manager?ref=release-25.11"'
{
  artcraftFlake ? "path:${toString ./..}",
  homeManager ? "github:nix-community/home-manager",
}:
let
  ac = builtins.getFlake artcraftFlake;
  hm = builtins.getFlake homeManager;

  # hm.lib is home-manager's module helper set (it only carries
  # homeManagerConfiguration), not a nixpkgs lib: filter with pkgs.lib instead.
  lib = pkgs.lib;

  # HM's own nixpkgs input, so the harness is self-contained (it must not depend
  # on which nixpkgs the caller happens to have in scope).
  pkgs = import hm.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ ac.overlays.default ];
  };

  # Simulate a consumer whose nixpkgs already contains an unrelated
  # package named soundcraft, without applying the ArtCraft overlay.
  collisionPkgs = import hm.inputs.nixpkgs {
    system = "x86_64-linux";

    overlays = [
      (_final: prev: {
        soundcraft = prev.runCommand "soundcraft-collision" { } ''
          mkdir -p $out
        '';
      })
    ];
  };

  collisionEv = hm.lib.homeManagerConfiguration {
    pkgs = collisionPkgs;

    modules = [
      ac.homeModules.crafts

      {
        home.username = "tester";
        home.homeDirectory = "/home/tester";
        home.stateVersion = "26.11";

        programs.soundcraft.enable = true;
      }
    ];
  };

  collisionPackage = collisionEv.config.programs.soundcraft.package;

  craftNames = builtins.attrNames (
    lib.filterAttrs (_n: p: p.passthru.desktopAssets or false) ac.packages.x86_64-linux
  );

  ev = hm.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      # The documented shape, and the one that broke in the field: a
      # list-valued `homeModules.default` becomes a nested list inside `modules`
      # and nixpkgs refuses it. Importing the individual modules here would hide
      # that again.
      ac.homeModules.default
      (_: {
        home.username = "maj";
        home.homeDirectory = "/home/maj";
        home.stateVersion = "26.11";
        programs.home-manager.enable = true;

        programs.artcraft.enable = true;

        # Everything on via the list, then two overrides that must win over the
        # list's mkDefault: cadcraft off, photocraft's menu entry off.
        programs.crafts.enable = craftNames;
        programs.cadcraft.enable = false;
        programs.photocraft.enableDesktopEntry = false;

        # HM's xdg.portal writes per-user config only; with it unset our
        # reminder should fire, which is what craftExpect.portalWarn checks.
      })
    ];
  };

  entry = ev.config.xdg.desktopEntries.artcraft;

  # home-manager turns each xdg.desktopEntries attr into a makeDesktopItem
  # package in home.packages; find that one.
  hmEntry = builtins.head (
    builtins.filter (p: lib.hasSuffix "-artcraft.desktop" p.outPath) ev.config.home.packages
  );

  installed = map (p: baseNameOf p.outPath) (
    lib.filter (
      p: (p.passthru.desktopAssets or false) || lib.hasSuffix "-desktop" p.outPath
    ) ev.config.home.packages
  );

  # Forced: home-manager runs its own `assertions` at activation time, exactly as
  # NixOS does at toplevel, and package listings never touch them.
  assertionsHold = lib.all (a: a.assertion) (ev.config.assertions or [ ]);

  has = name: lib.any (n: lib.hasInfix "-${name}-" n) installed;
  hasDesktop = name: lib.any (n: lib.hasInfix "-${name}-" n && lib.hasSuffix "-desktop" n) installed;
in
{
  inherit
    hmEntry
    installed
    craftNames
    assertionsHold
    ;

  options = {
    exe = entry.exec;
    icon = entry.icon;
    settings = entry.settings;
    categories = entry.categories;
    xdgEnable = ev.config.xdg.enable;
    appInstalled = builtins.any (p: (p.pname or "") == "artcraft") ev.config.home.packages;
  };

  # The claims this harness makes about the generated module, all evaluable:
  #   nix eval --impure -f tests/hm-module.nix --json craftExpect
  craftExpect = {
    published = craftNames;
    filmcraftBinary = has "filmcraft";
    filmcraftDesktop = hasDesktop "filmcraft";
    photocraftBinary = has "photocraft";
    photocraftDesktopOff = !(hasDesktop "photocraft");
    cadcraftOff = !(has "cadcraft");
    # 11 apps on (12 minus cadcraft) → 11 binary outputs, plus 10 desktop
    # outputs (photocraft's is off) = 21 store paths in the user environment.
    installedCount = builtins.length installed == 21;
    # The portal reminder fires because xdg.portal.enable is left false here.
    portalWarn = lib.any (
      w: lib.hasInfix "xdg-desktop-portal" w && lib.hasInfix "The Craft apps" w
    ) ev.config.warnings;

    soundcraftCollision = {
      correctPackage = collisionPackage.passthru.desktopAssets or false;

      desktopOutput = builtins.elem "desktop" collisionPackage.outputs;

      desktopInstalled = lib.any (
        p: p.outPath == collisionPackage.desktop.outPath
      ) collisionEv.config.home.packages;
    };

    # Home-manager evaluates these at activation; nothing else in this harness
    # would, so a bad assertion here is a broken user config in the field.
    assertions = assertionsHold;
  };
}
