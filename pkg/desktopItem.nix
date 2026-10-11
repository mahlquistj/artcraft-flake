{
  lib,
  makeDesktopItem,
  package,
}:
makeDesktopItem {
  name = "artcraft";
  desktopName = "ArtCraft";
  genericName = "AI creation IDE";
  comment = "Compose AI images, video and audio in 2D and 3D scenes";
  exec = "${lib.getExe package} %U";
  # Icon shipped by the package itself (also installed into the hicolor theme).
  icon = "${package}/share/artcraft/artcraft.png";
  terminal = false;
  type = "Application";
  startupWMClass = "ArtCraft";
  categories = [
    "Graphics"
    "AudioVideo"
  ];
}
