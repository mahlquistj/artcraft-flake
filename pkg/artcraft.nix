{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  # Linux native dependencies for the egui/glow + cpal + clipboard stack.
  alsa-lib,
  fontconfig,
  libx11,
  libxcursor,
  libxi,
  libxkbcommon,
  libxrandr,
  libxcb,
  mesa,
  wayland,
  # Runtime tools: in-app video playback shells out to ffmpeg/ffprobe, and the
  # `open` crate shells out to xdg-open.
  ffmpeg,
  xdg-utils,
  pins ? import ../pins.nix,
}:

let
  linuxLibs = [
    alsa-lib
    fontconfig
    libx11
    libxcursor
    libxi
    libxkbcommon
    libxrandr
    libxcb
    mesa
    wayland
  ];
in
rustPlatform.buildRustPackage {
  pname = "artcraft";
  version = "${pins.version}-unstable-${pins.date}";

  src = fetchFromGitHub {
    owner = pins.owner;
    repo = pins.repo;
    rev = pins.rev;
    hash = pins.srcHash;
  };

  cargoHash = pins.cargoHash;

  # The workspace's default member is the Tauri app (needs Node + webkit2gtk),
  # so select the pure-Rust crate explicitly.
  cargoBuildFlags = [
    "--package"
    "artcraft_native"
  ];

  # `cargo test` without `-p` would build the Tauri app; the native tests also
  # spawn UI fixtures. Opt in with `nix build .#artcraft.overrideAttrs ...` if
  # you need them.
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux linuxLibs;

  env.CARGO_PROFILE_RELEASE_LTO = "thin";
  env.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";

  # installPhase: cargoBuildFlags already produced the binary; `cargo install`
  # would rebuild it for the default workspace member.
  installPhase = ''
    runHook preInstall

    # cargoBuildHook builds with `--target $CARGO_BUILD_TARGET`, so the binary
    # lives under target/<rust-triple>/release/. Find it instead of guessing.
    binary="$(find target -type f -perm -u+x -name artcraft-native -path '*/release/*' | head -n1)"
    if [ -z "$binary" ]; then
      echo "error: artcraft-native binary not found under target/" >&2
      exit 1
    fi

    mkdir -p "$out/bin"
    install -Dm755 "$binary" "$out/bin/artcraft-native"

    # Window/taskbar icon for the desktop entry (the upstream Tauri app's icons).
    mkdir -p "$out/share/artcraft"
    install -m644 crates/desktop/artcraft/icons/icon.png "$out/share/artcraft/artcraft.png"
    install -Dm644 crates/desktop/artcraft/icons/128x128.png "$out/share/icons/hicolor/128x128/apps/artcraft.png"
    install -Dm644 crates/desktop/artcraft/icons/128x128@2x.png "$out/share/icons/hicolor/256x256/apps/artcraft.png"
    install -Dm644 crates/desktop/artcraft/icons/32x32.png "$out/share/icons/hicolor/32x32/apps/artcraft.png"
    runHook postInstall
  '';

  postFixup = ''
    # Wrapper: dlopen'd libs (wayland/X11 via rust bindings) plus the ffmpeg and
    # xdg-open executables the app shells out to.
    mv "$out/bin/artcraft-native" "$out/bin/.artcraft-native-wrapped"
    makeWrapper "$out/bin/.artcraft-native-wrapped" "$out/bin/artcraft-native" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath linuxLibs}" \
      --prefix PATH : "${
        lib.makeBinPath [
          ffmpeg
          xdg-utils
        ]
      }"
    ln -s "artcraft-native" "$out/bin/artcraft"
  '';

  meta = with lib; {
    description = "ArtCraft desktop app in pure Rust (egui UI over the ArtCraft API)";
    longDescription = ''
      ArtCraft is an IDE for interactive AI image and video creation. This
      package builds the `artcraft-native` crate: the egui desktop client with
      no Tauri, no webview and no JavaScript toolchain. ArtCraft's published
      GitHub releases only ship macOS and Windows installers, so Linux users
      need a source build.
    '';
    homepage = "https://github.com/${pins.owner}/${pins.repo}";
    downloadPage = "https://github.com/${pins.owner}/${pins.repo}/tree/${pins.rev}";
    changelog = "https://github.com/${pins.owner}/${pins.repo}/commits/${pins.rev}";
    license = with licenses; [
      mit
      asl20
    ];
    mainProgram = "artcraft";
    platforms = platforms.linux;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = [ ];
  };
}
