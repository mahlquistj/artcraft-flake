# home-manager module for the Craft app suite: `programs.<app>.enable = true;`
# per published product, plus the `programs.crafts.enable = [ … ]` list. It
# shares ./craft-options.nix with the NixOS module so both expose one API.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  craft = import ./craft-options.nix { inherit lib pkgs; };

  enabled = craft.enabledFor config.programs;
  anyEnabled = enabled != [ ];

  # home-manager's buildEnv of home.packages links only the default output, so
  # the desktop output has to be a package of its own for the menu entry to
  # appear under <profile>/share/applications (which NixOS puts on XDG_DATA_DIRS).
  installPackages = lib.flatten (map craft.packagesOf enabled);
in
{
  options.programs = craft.productOptions // {
    crafts = craft.suiteOption;
  };

  config = lib.mkMerge [
    (craft.suiteEnable config.programs)

    {
      home.packages = installPackages;
      assertions = craft.unsupportedAssertions enabled;
    }

    (lib.mkIf anyEnabled {
      warnings = lib.optionals (!config.xdg.portal.enable) [
        (
          craft.portalWarning enabled
          + ''
            home-manager's xdg.portal.enable writes only the per-user portal
            configuration; the portal service itself belongs to the system (on
            NixOS: xdg.portal.enable = true).
          ''
        )
      ];
    })
  ];
}
