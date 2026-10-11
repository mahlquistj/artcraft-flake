# Generic builder for storytold's Craft suite "prebuilt Linux tarball" products.
#
# Input: `product` (metadata from ../products.nix) and `pins` (the generated
# pins.lock.json). The tarball already contains a correct FHS prefix
# (bin/, share/{applications,icons,metainfo,mime,doc}), so this builder only has
# to do two things to the ELF files:
#
#   1. point the interpreter at Nixpkgs' dynamic linker (upstream hard-codes
#      /lib64/ld-linux-x86-64.so.2, which on NixOS is nix-ld, not glibc);
#   2. wrap them with the libraries the binary dlopen()s at runtime — the exact
#      soname set the app's own library preflight looks for, plus libdbus (the
#      xdg-desktop-portal client) — and the commands it shells out to.
#
# Deliberately *not* done here: no strip, no hardening, no RPATH rewriting, no
# authored .desktop/icon/mime files. We ship upstream's bytes and upstream's
# desktop assets.

{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  makeWrapper,
  # Only to compare its version against the product's glibc symbol floor.
  glibc,
  # GL/Vulkan dispatchers. libglvnd, never mesa: nixpkgs' mesa ships the vendor
  # ICD (libGLX_mesa.so.0) but no libEGL.so.1, and putting it on LD_LIBRARY_PATH
  # next to the system driver is the exact bug that broke the ArtCraft package.
  libglvnd,
  vulkan-loader,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  libxext,
  libxkbcommon,
  # libdbus-1.so.3: the app talks to org.freedesktop.portal.{FileChooser,
  # Screenshot,Settings} through it, and rfd reports "Can't connect to a portal:
  # libdbus-1.so not found" when it is missing.
  dbus,
  fontconfig,
  freetype,
  alsa-lib,
  ffmpeg,
  xdg-utils,
  product,
  # pins.lock.json as an attrset, so `import ./pins.lock.json` (a JSON file)
  # would fail: the caller passes the decoded data.
  pins,
}:
let
  inherit (stdenv.hostPlatform) system;

  # NB: the `or` alternative needs parentheses — `x.y or throw "…"` parses as a
  # call of the selected value with the string as argument.
  pin =
    pins.${product.repo} or (throw ''
      craft-app: no pins for '${product.repo}'.
      Add it with:  nix run .#update -- ${product.repo}
    '');

  asset =
    pin.systems.${system} or (throw ''
      craft-app: pins.lock.json has no '${system}' asset for '${product.repo}'
      (pinned ${pin.tag}: ${builtins.concatStringsSep ", " (builtins.attrNames pin.systems)}).
      Refresh with: nix run .#update -- ${product.repo}
    '');

  glibcFloor = product.glibcFloorBySystem.${system} or product.glibcFloor;

  # Every binary in the tarball we are responsible for wrapping: the GUI plus
  # the headless CLI(s), which is how CI gets a display-free smoke test.
  bins = [ product.guiBin ] ++ product.cliBins;

  # Libraries the product dlopens, i.e. never link-time dependencies. The ten
  # sonames below are what the app's own startup preflight checks; everything
  # after that is a dlopen we found in the binary but the preflight trusts
  # implicitly (wayland-egl, dbus, fontconfig, freetype).
  runtimeLibs = [
    libglvnd
    vulkan-loader
    wayland
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
    libxext
    libxkbcommon
    dbus
    fontconfig
    freetype
  ]
  ++ lib.optionals product.needsAlsa [ alsa-lib ];

  runtimeBins =
    lib.optionals product.needsXdgUtils [ xdg-utils ] ++ lib.optionals product.needsFfmpeg [ ffmpeg ];

  # Platform/ABI checks. A mismatch makes the package `broken` (loud, but still
  # evaluable so `nix flake show` and cross-system CI keep working).
  unsupported =
    if !stdenv.hostPlatform.isLinux then
      "upstream publishes no Linux tarball for ${system}"
    else if stdenv.hostPlatform.libc != "glibc" then
      "these binaries are glibc-only (GLIBC_${glibcFloor} symbol versioned)"
    else if !(lib.versionAtLeast glibc.version glibcFloor) then
      "nixpkgs glibc ${glibc.version} is older than ${product.repo}'s floor ${glibcFloor}"
    else
      null;

  binList = builtins.concatStringsSep " " bins;
in
stdenv.mkDerivation (finalAttrs: {
  pname = product.repo;
  inherit (pin) version;

  src = fetchurl {
    url = asset.url;
    hash = asset.sha256;
  };

  # The tarball unpacks into <asset-name-without-extension>/ (verified for every
  # product); use that as the source root instead of guessing.
  sourceRoot = lib.removeSuffix ".tar.gz" asset.name;

  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];

  dontConfigure = true;
  dontBuild = true;
  doInstallCheck = false;
  # Upstream ships stripped, signed-by-nothing-but-its-hash binaries. The only
  # byte we change is the ELF interpreter (postFixup), so no stripping and no
  # patchelf --shrink-rpath pass over 90 MB of production code.
  dontStrip = true;
  dontPatchELF = true;
  hardeningDisable = [ "all" ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    # cp (not install -m755) keeps upstream's own modes; the ELFs are already
    # +x and share/ is all data.
    cp --no-preserve=ownership bin/* "$out/bin/"
    chmod +x "$out/bin"/*

    # Desktop entry, hicolor icons + scalable svg, AppStream metainfo, mime
    # types and the licence/OFL/README set all ship ready-made upstream, with
    # the ai.storyteller.<app> id. We install them verbatim.
    cp --no-preserve=ownership -r share "$out/"

    runHook postInstall
  '';

  postFixup = ''
    for b in ${binList}; do
      if [ ! -f "$out/bin/$b" ]; then
        echo "craft-app: $b is missing from the ${product.repo} tarball" >&2
        echo "           upstream changed its asset layout" >&2
        exit 1
      fi
      patchelf --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" "$out/bin/$b"
    done

    for b in ${binList}; do
      mv "$out/bin/$b" "$out/bin/.$b-wrapped"
      # LD_LIBRARY_PATH order matters: the store closure first (it is what the
      # app's preflight scans with dlopen), the system's OpenGL/Vulkan driver
      # directory last so the *host* ICD and vendor libs win.
      makeWrapper "$out/bin/.$b-wrapped" "$out/bin/$b" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib" \
        --prefix PATH : "${lib.makeBinPath runtimeBins}"
    done
  '';

  passthru = {
    inherit
      product
      pins
      asset
      runtimeLibs
      runtimeBins
      glibcFloor
      ;
    upstreamChecksums = asset.sumsLine;
    inherit (pin) tag releaseDate;
    # Every file the package exposes as a command, for tests and modules.
    allPrograms = bins;
  };

  meta = {
    inherit (product) description;
    longDescription = ''
      Prebuilt Linux binary package of ${product.repo}, taken from the GitHub
      release ${pin.tag} (${pin.releaseDate}) and wrapped for NixOS: the ELF
      interpreter is repointed at nixpkgs' dynamic linker, and the wrapper puts
      the libraries the binary dlopen()s on LD_LIBRARY_PATH (the same soname
      list the app checks for itself at startup).

      Desktop entry, icons, mime types and AppStream metainfo come from
      upstream's tarball, not from this flake.

      File and colour dialogs go through xdg-desktop-portal, so a NixOS system
      installing this should set xdg.portal.enable = true.
    '';
    mainProgram = product.guiBin;
    homepage = "https://github.com/${product.owner}/${product.repo}";
    downloadPage = "https://github.com/${product.owner}/${product.repo}/releases/tag/${pin.tag}";
    changelog = "https://github.com/${product.owner}/${product.repo}/releases";
    license = lib.licenses.${product.license};
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = product.systems;
    broken = unsupported != null;
    # The glibc/GL preflight and the portal dependency make this a desktop app:
    # headless use is the <app>-cli binary only.
    mainProgramIsGui = true;
    maintainers = [ ];
  };
})
