# Eval-time contract test for the generated NixOS module, wired into
# `nix flake check` as checks.<system>.nixos-crafts-module.
#
# It builds no system: it evaluates a nixosSystem that enables every published
# product, asserts that the module put exactly the expected store paths into
# `environment.systemPackages` — one binary output plus one desktop output per
# app — and then links those paths, so the check also *builds* what the module
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

  sys = lib.nixosSystem {
    inherit system;
    modules = [
      { nixpkgs.pkgs = pkgs; }
      module
      {
        # A portal is what the module warns about; enabling it keeps this check
        # about the packages, not about the reminder.
        xdg.portal.enable = true;
        programs.crafts.enable = names;
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

  problems = lib.filter (s: s != "") [
    (lib.optionalString (builtins.length installed != expected) ''
      expected ${toString expected} store paths (out + desktop for each of
      ${toString (builtins.length names)} products), got ${toString (builtins.length installed)}.
    '')
    (lib.optionalString (missingPairs != [ ]) ''
      no desktop output installed for: ${lib.concatStringsSep ", " missingPairs}.
    '')
    (
      # Our module's refusal is the assertion that matters; a full nixosSystem
      # carries hundreds of nixpkgs assertions and this config sets none of the
      # options they want, so ask the packages themselves instead of scanning
      # assertion text.
      lib.optionalString (lib.any (n: craftPackages.${n}.meta.broken or false) names) ''
        the builder marks at least one product broken on ${system} (glibc floor).
      ''
    )
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
  ];
in
if problems == [ ] then
  pkgs.linkFarmFromDrvs "craft-nixos-module-check" installed
else
  throw ''
    craft NixOS module check failed:
    ${lib.concatStringsSep "\n" problems}
  ''
