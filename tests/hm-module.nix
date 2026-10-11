# Test harness for the home-manager module. Evaluates it against a real
# home-manager source (no build of the app itself) and exposes the desktop entry
# that home-manager generates from `programs.artcraft`.
#
#   nix eval --impure -f tests/hm-module.nix options          # merged option values
#   nix build --impure --no-link -f tests/hm-module.nix hmEntry \
#     && cat $(result)/share/applications/artcraft.desktop    # generated file
#
# Override the inputs if the defaults are stale:
#   nix eval --impure -f tests/hm-module.nix options --argstr homeManager "<flake ref>"
{
  artcraftFlake ? "path:/home/maj/projects/artcraft-flake",
  homeManager ? "path:/nix/store/ajsk5n30javg5iz3x0ygl7n07cw1z5cl-source",
}:
let
  ac = builtins.getFlake artcraftFlake;
  hm = builtins.getFlake homeManager;
  pkgs = import hm.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ ac.overlays.default ];
  };
  ev = hm.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ac.homeModules.artcraft
      (_: {
        home.username = "maj";
        home.homeDirectory = "/home/maj";
        home.stateVersion = "26.11";
        programs.home-manager.enable = true;
        programs.artcraft.enable = true;
      })
    ];
  };

  entry = ev.config.xdg.desktopEntries.artcraft;

  # home-manager turns each xdg.desktopEntries attr into a makeDesktopItem
  # package in home.packages; find that one.
  hmEntry = builtins.head (
    builtins.filter (p: pkgs.lib.hasSuffix "-artcraft.desktop" p.outPath) ev.config.home.packages
  );
in
{
  inherit hmEntry;
  options = {
    exe = entry.exec;
    icon = entry.icon;
    settings = entry.settings;
    categories = entry.categories;
    xdgEnable = ev.config.xdg.enable;
    appInstalled = builtins.any (p: (p.pname or "") == "artcraft") ev.config.home.packages;
  };
}
