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

    # NB: no `xdg.enable` here — home-manager's desktop-entries module keys off
    # `xdg.desktopEntries != { }`, and overriding xdg.enable could clash with a
    # value set elsewhere in the user's config.
    xdg.desktopEntries = lib.mkIf cfg.desktopEntry {
      artcraft = {
        name = "ArtCraft";
        genericName = "AI creation IDE";
        comment = "Compose AI images, video and audio in 2D and 3D scenes";
        exec = "${lib.getExe cfg.package} %U";
        icon = "${cfg.package}/share/artcraft/artcraft.png";
        terminal = false;
        type = "Application";
        categories = [
          "Graphics"
          "AudioVideo"
        ];
        # home-manager's `xdg.desktopEntries` has no `startupWMClass` option (that
        # one only exists on nixpkgs' makeDesktopItem), so the key goes in through
        # the free-form `settings` attrset.
        settings.StartupWMClass = "ArtCraft";
      };
    };
  };
}
