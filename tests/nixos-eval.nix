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
      # The documented entry point (artcraft + crafts in one module), imported the
      # way a config does rather than passed bare.
      { imports = [ flake.nixosModules.default ]; }
      {
        networking.hostName = "craft-test";
        fileSystems."/".device = "/dev/sda1";
        fileSystems."/".fsType = "ext4";
        boot.loader.grub.device = "/dev/sda";

        programs.artcraft.enable = true;
        programs.crafts.enable = craftNames;
        programs.photocraft.enableDesktopEntry = false;
        programs.cadcraft.enable = false;

        # With a backend, or nixpkgs' own portal assertion fails once something
        # forces config.assertions (which expect.assertionsHold now does).
        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };
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

  # In the let, not in the result set: `expect = { x = x; }` would be a
  # self-reference and a sibling attribute is not lexical scope in Nix.
  allAssertionsHold = lib.all (a: a.assertion) sys.config.assertions;
in
{
  inherit installed;
  inherit (sys.config) warnings;
  assertionsHold = allAssertionsHold;

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
    # Every assertion holds, ours and nixpkgs' (this is what a rebuild forces).
    assertions = allAssertionsHold;
    # Only *our* portal reminder must be absent; nixpkgs adds its own advice about
    # portal backends, so a bare "no warnings at all" claim is not the contract.
    craftWarningAbsent =
      !lib.any (
        w: lib.hasInfix "xdg-desktop-portal" w && lib.hasInfix "The Craft apps" w
      ) sys.config.warnings;
  };
}
