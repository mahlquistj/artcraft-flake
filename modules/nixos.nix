{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.artcraft;
  # Works with or without the flake's overlay applied to the package set.
  defaultPackage = pkgs.artcraft or (pkgs.callPackage ../pkg/artcraft.nix { });
in
{
  options.programs.artcraft = {
    enable = lib.mkEnableOption "ArtCraft, the desktop IDE for AI image/video/audio creation";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "pkgs.artcraft";
      description = "The artcraft derivation to use.";
    };

    desktopEntry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to add an ArtCraft entry to the application menu.";
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS has no `xdg.desktopEntries` option (that one is home-manager's), so
    # the menu entry ships as its own package.
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals cfg.desktopEntry [
      (pkgs.callPackage ../pkg/desktopItem.nix { package = cfg.package; })
    ];
  };
}
