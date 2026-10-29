# Eval-time contract test for the generated NixOS module, wired into
# `nix flake check` as checks.<system>.nixos-crafts-module.
#
# It builds no system, but it evaluates the two things a real rebuild evaluates
# and a package listing does not: the module *import shape* a user writes, and
# `config.assertions`. Both were blind spots once:
#
#   - `nixosModules.default` was a list, so `imports = [ …default ]` became a
#     nested list and nixpkgs rejected it ("Module imports can't be nested
#     lists"). Passing the module the way a config does is therefore the point.
#   - nothing forced `config.assertions`, which `system.build.toplevel` does on
#     every real build, so a bad assertion in our module would have shipped.
#
# Then it asserts that the module put exactly the expected store paths into
# `environment.systemPackages` — one binary output plus one desktop output per
# app — and links those paths, so the check also *builds* what the module
# installs. A module that silently installs nothing (bad filter, missing option,
# mkDefault losing) fails here instead of on someone's `nixos-rebuild`.
{
  lib,
  pkgs,
  craftPackages,
  module,
}:
let
  names = builtins.attrNames craftPackages;
  system = pkgs.stdenv.hostPlatform.system;

  # Reproduce a name collision in the consumer's package set.
  collisionPkgs = pkgs.extend (
    _final: prev: {
      soundcraft = prev.runCommand "unrelated-soundcraft" { } ''
        mkdir -p $out
      '';
    }
  );

  collisionSys = lib.nixosSystem {
    inherit system;

    modules = [
      { nixpkgs.pkgs = collisionPkgs; }
      { imports = [ module ]; }

      {
        programs.soundcraft.enable = true;
        system.stateVersion = "26.11";
      }
    ];
  };

  collisionPackage = collisionSys.config.programs.soundcraft.package;

  collisionDesktopInstalled = lib.any (
    p: p.outPath == collisionPackage.desktop.outPath
  ) collisionSys.config.environment.systemPackages;

  sys = lib.nixosSystem {
    inherit system;
    modules = [
      { nixpkgs.pkgs = pkgs; }
      # The documented usage, not the bare module.
      { imports = [ module ]; }
      {
        # A portal is what the module warns about; configuring one properly keeps
        # this check about the packages. (Properly = with a backend: nixpkgs
        # asserts when enable is true and extraPortals is empty, and this check
        # forces config.assertions, so the first run of it caught exactly that.)
        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };

        programs.crafts.enable = names;

        # Enough of a real system that config.assertions is about *our* module and
        # not about nixpkgs' "you configured no bootloader/filesystem" assertions —
        # forcing assertions is pointless if the config cannot pass them.
        system.stateVersion = "26.11";
        networking.hostName = "craft-check";
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub.device = "/dev/vda";
      }
    ];
  };

  isCraftPackage = p: (p.passthru.desktopAssets or false) || lib.hasSuffix "-desktop" p.outPath;

  installed = builtins.filter isCraftPackage sys.config.environment.systemPackages;
  basenames = map (p: baseNameOf p.outPath) installed;

  # Every product contributes its binary and its desktop output: none of them
  # turns enableDesktopEntry off here, so the count is exactly 2 × products.
  expected = 2 * builtins.length names;

  # A desktop output is named <hash>-<product>-<version>-desktop, so match the
  # product *inside* the name.
  missingPairs = lib.filter (
    n: !lib.any (b: lib.hasInfix "-${n}-" b && lib.hasSuffix "-desktop" b) basenames
  ) names;

  # Forced on purpose (this is the line that evaluates every assertion, ours and
  # nixpkgs').
  assertionsHold = lib.all (a: a.assertion) sys.config.assertions;

  problems = lib.filter (s: s != "") [
    (lib.optionalString (builtins.length installed != expected) ''
      expected ${toString expected} store paths (out + desktop for each of
      ${toString (builtins.length names)} products), got ${toString (builtins.length installed)}.
    '')
    (lib.optionalString (missingPairs != [ ]) ''
      no desktop output installed for: ${lib.concatStringsSep ", " missingPairs}.
    '')
    (lib.optionalString (lib.any (n: craftPackages.${n}.meta.broken or false) names) ''
      the builder marks at least one product broken on ${system} (glibc floor).
    '')
    (lib.optionalString (!assertionsHold) ''
      some config.assertion does not hold on ${system}.
    '')
    (
      # The reminder must not fire when a portal is configured; if it does, the
      # warning condition is wrong.
      lib.optionalString
        (lib.any (
          w: lib.hasInfix "xdg-desktop-portal" w && lib.hasInfix "The Craft apps" w
        ) sys.config.warnings)
        ''
          the Craft portal warning fired although xdg.portal.enable = true.
        ''
    )
    (lib.optionalString
      (
        !(collisionPackage.passthru.desktopAssets or false)
        || !(builtins.elem "desktop" collisionPackage.outputs)
        || !collisionDesktopInstalled
      )
      ''
        SoundCraft package-name collision: the module selected an
        unrelated pkgs.soundcraft or failed to install its desktop output.
      ''
    )
  ];
in
if problems == [ ] then
  pkgs.linkFarmFromDrvs "craft-nixos-module-check" installed
else
  throw ''
    craft NixOS module check failed:
    ${lib.concatStringsSep "\n" problems}
  ''
