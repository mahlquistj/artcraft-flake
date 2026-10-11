# Source pins for the ArtCraft build. Rewritten by: nix run .#update-pins
#
# Why a commit on main and not a release tag?
#   The GitHub releases ship only macOS (.dmg / .app.tar.gz) and Windows
#   (.exe / .msi) assets, and no release tag contains the artcraft-native
#   crate, so we pin a commit on the default branch.
{
  owner = "storytold";
  repo = "artcraft";
  branch = "main";
  rev = "28a39a0de4a2fc2eccc237df2046c24245bd12ab";
  date = "2026-10-10";
  version = "0.1.0";
  srcHash = "sha256-Fg6Sa9qT8x+qMBQO0xCQz9cMJhgc/DNpUjB3C9Xd8Ws=";
  cargoHash = "sha256-QTgowWIqVM9KAWhxVs5HUnkcl9AGrnOiOvLRs4NTCUk=";
}
