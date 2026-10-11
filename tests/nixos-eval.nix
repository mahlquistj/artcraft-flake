# Eval-only smoke test for the NixOS module:
#   nix eval -f tests/nixos-eval.nix config.system.build.toplevel.drvPath --impure
# (does not build the system).
let
  flake = builtins.getFlake (toString ./..);
  nixpkgsLib = flake.inputs.nixpkgs.lib;
  pkgs = import flake.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ flake.overlays.default ];
  };
in
nixpkgsLib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.artcraft
    {
      networking.hostName = "artcraft-test";
      fileSystems."/".device = "/dev/sda1";
      fileSystems."/".fsType = "ext4";
      boot.loader.grub.device = "/dev/sda";
      programs.artcraft.enable = true;
    }
  ];
}
