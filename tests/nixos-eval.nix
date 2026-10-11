# Eval-only smoke test for the NixOS modules (ArtCraft plus the generated Craft
# suite module). It does not build the system.
#
#   nix eval --impure -f tests/nixos-eval.nix craftPackages        # what the module installs
#   nix eval --impure -f tests/nixos-eval.nix expect               # the assertions as data
#   nix eval --impure -f tests/nixos-eval.nix warnings             # portal reminder, if any
#
# `specialArgs.pkgs` is deliberately *not* used: the module must work in the
# normal flake-input setup (`nixpkgs.pkgs = …`), and passing specialArgs.pkgs
# silently disables nixpkgs.overlays/config, which would hide real problems.
let
  flake = builtins.getFlake (toString ./..);
  lib = flake.inputs.nixpkgs.lib;
  system = "x86_64-linux";

  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    overlays = [ flake.overlays.default ];
  };

  # Products the flake publishes for this system: recognised by the builder's
  # passthru marker, so update/artcraft/craft-suite are not mistaken for apps.
  craftPackagesOfFlake = lib.filterAttrs (
    _n: p: p.passthru.desktopAssets or false
  ) flake.packages.${system};

  craftNames = builtins.attrNames craftPackagesOfFlake;

  # Every product on through the convenience list, then two deliberate overrides:
  # one app off (cadcraft) and one desktop entry off (photocraft). If the list's
  # mkDefault were stronger than user config, these would be merge conflicts
  # rather than wins.
  sys = lib.nixosSystem {
    inherit system;
    modules = [
      { nixpkgs.pkgs = pkgs; }
      flake.nixosModules.artcraft
      flake.nixosModules.crafts
      {
        networking.hostName = "craft-test";
        fileSystems."/".device = "/dev/sda1";
        fileSystems."/".fsType = "ext4";
        boot.loader.grub.device = "/dev/sda";

        programs.artcraft.enable = true;
        programs.crafts.enable = craftNames;
        programs.photocraft.enableDesktopEntry = false;
        programs.cadcraft.enable = false;

        # Flip to false to watch the xdg-desktop-portal reminder fire.
        xdg.portal.enable = true;
      }
    ];
  };

  installed = map (p: baseNameOf p.outPath) (
    lib.filter (
      p: (p.passthru.desktopAssets or false) || lib.hasSuffix "-desktop" p.outPath
    ) sys.config.environment.systemPackages
  );

  # Store basenames are <hash>-<name>-<version>[-desktop], so match on the
  # name *after* a dash rather than a prefix.
  has = name: lib.any (n: lib.hasInfix "-${name}-" n) installed;
  hasDesktop = name: lib.any (n: lib.hasInfix "-${name}-" n && lib.hasSuffix "-desktop" n) installed;
in
{
  inherit installed;
  inherit (sys.config) warnings;
  assertionsHold = lib.all (a: a.assertion) sys.config.assertions;

  # What this harness claims about the module, as evaluable booleans:
  #   nix eval --impure -f tests/nixos-eval.nix expect.<key>
  expect = {
    published = craftNames;
    artcraftInstalled = lib.any (n: lib.hasInfix "-artcraft-0" n) (
      map baseNameOf (map (p: p.outPath) sys.config.environment.systemPackages)
    );
    filmcraftBinary = has "filmcraft";
    filmcraftDesktop = hasDesktop "filmcraft";
    photocraftBinary = has "photocraft";
    photocraftDesktopOff = !(hasDesktop "photocraft");
    cadcraftOff = !(has "cadcraft");
    noWarnings = sys.config.warnings == [ ];
  };
}
