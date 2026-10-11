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
      description = "Whether to install an ArtCraft entry in the application menu.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # home-manager's desktop entries live under the xdg base store.
    xdg.enable = lib.mkIf cfg.desktopEntry true;

    xdg.desktopEntries = lib.mkIf cfg.desktopEntry {
      artcraft = {
        name = "ArtCraft";
        genericName = "AI creation IDE";
        comment = "Compose AI images, video and audio in 2D and 3D scenes";
        exec = "${lib.getExe cfg.package} %U";
        icon = "${cfg.package}/share/artcraft/artcraft.png";
        terminal = false;
        type = "Application";
        startupWMClass = "ArtCraft";
        categories = [
          "Graphics"
          "AudioVideo"
        ];
      };
    };
  };
}
