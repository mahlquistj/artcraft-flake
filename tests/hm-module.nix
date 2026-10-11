# Test harness for the home-manager module. Evaluates it against a real
# home-manager source (no build of the app itself) and exposes the desktop entry
# that home-manager generates from `programs.artcraft`.
#
#   nix eval --impure -f tests/hm-module.nix options          # merged option values
#   OUT=$(nix build --impure --no-link --print-out-paths -f tests/hm-module.nix hmEntry)
#   cat "$OUT/share/applications/artcraft.desktop"            # generated file
#
#   nix eval --impure -f tests/hm-module.nix options --arg homeManager '"github:nix-community/home-manager?ref=release-25.11"'
{
  artcraftFlake ? "path:${toString ./..}",
  homeManager ? "github:nix-community/home-manager",
}:
let
  ac = builtins.getFlake artcraftFlake;
  hm = builtins.getFlake homeManager;
  # HM's own nixpkgs input, so the harness is self-contained (it must not depend
  # on which nixpkgs the caller happens to have in scope).
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
