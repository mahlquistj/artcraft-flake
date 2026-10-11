# NixOS module for the Craft app suite: `programs.<app>.enable = true;` for each
# published product (plus `programs.crafts.enable = [ … ]` as a list). Options
# and the enabled-set logic live in ./craft-options.nix; this file is the NixOS
# half of the installation.
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

  # Both outputs are listed on purpose: the system profile links only the default
  # output of a multi-output package, so without `package.desktop` nothing would
  # land in /run/current-system/sw/share/applications.
  installPackages = lib.flatten (map craft.packagesOf enabled);
in
{
  options.programs = craft.productOptions // {
    crafts = craft.suiteOption;
  };

  config = lib.mkMerge [
    (craft.suiteEnable config.programs)

    {
      environment.systemPackages = installPackages;
      assertions = craft.unsupportedAssertions enabled;
    }

    # The apps start fine without a portal and fail only when the user presses
    # Open, so this warns instead of silently enabling a system service.
    (lib.mkIf anyEnabled {
      warnings = lib.optionals (!config.xdg.portal.enable) [
        (
          craft.portalWarning enabled
          + ''
            On NixOS that means
              xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-gtk ]; };
          ''
        )
      ];
    })
  ];
}
