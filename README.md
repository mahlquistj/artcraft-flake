# artcraft-flake

A Nix flake that builds **ArtCraft** (https://github.com/storytold/artcraft) from
source for Linux: the `artcraft-native` crate, i.e. the pure-Rust egui desktop
client (no Tauri, no webview, no Node.js).

## Why build from source?

ArtCraft's GitHub releases only ship macOS and Windows binaries —
`ArtCraft_<ver>_universal.dmg`, `ArtCraft_universal.app.tar.gz`,
`ArtCraft_<ver>_x64-setup.exe`, `ArtCraft_<ver>_x64_en-US.msi` — and their CI
(`.github/workflows/artcraft-{macos,windows}-publish.yml`) publishes nothing for
Linux. There is no AppImage/deb/rpm/tar.xz to download, so a Linux package has
to compile the Rust workspace.

Two clients live in that workspace:

| Crate | What it is | Needs |
|---|---|---|
| `crates/desktop/artcraft` | the official Tauri app | Node 20+, npm, Nx, Vite, `cargo-tauri`, webkit2gtk |
| `artcraft-native` (**this flake**) | egui desktop app over the same API client crates | Rust + a few C libraries |

`artcraft-native` covers Create Image / Create Video / Create Audio, the feed,
library, lightbox, characters and sign-in. It is the practical way to get a
native ArtCraft binary on a NixOS desktop without a JavaScript toolchain.
Want the Tauri app instead? See "Packaging the Tauri app" below.

`artcraft-native` does not exist in any release tag (checked: `artcraft-v0.41.0`,
the newest at the time of writing), so `pins.nix` pins a commit on `main`.

## Layout

```
flake.nix            outputs: packages, overlay, nixosModules, homeModules, devShell, apps, checks
pins.nix             owner/repo/branch/rev/date/version/srcHash/cargoHash
pkg/artcraft.nix     rustPlatform.buildRustPackage derivation
pkg/desktopItem.nix  makeDesktopItem menu entry (NixOS side)
update.nix           `nix run .#update-pins` — re-resolves rev + hashes
modules/nixos.nix    programs.artcraft (NixOS)
modules/home-manager.nix  programs.artcraft (home-manager)
tests/nixos-eval.nix eval-only smoke test for the NixOS module
```

## Try it

```bash
nix run .#artcraft            # or: nix build .#artcraft && ./result/bin/artcraft
nix build .#artcraft          # result/bin/artcraft (also result/bin/artcraft-native)
nix flake check               # builds the package + menu entry, runs nixfmt --check
nix develop                   # cargo/clippy/rustc/rustfmt/rust-analyzer + native libs
```

The app has no CLI flags: it opens a window and signs you in. `--help` is passed
straight through to egui and ignored.

The build takes about a minute once the crates are vendored; the first fetch
downloads the whole workspace lockfile (Tauri and friends included), a few
hundred MB.

## Install it

**NixOS module** (`programs.artcraft.enable`):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    artcraft.url = "github:YOU/artcraft-flake";   # or "git+file:///home/maj/projects/artcraft-flake"
  };

  outputs = { nixpkgs, artcraft, ... }: {
    nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        artcraft.nixosModules.artcraft
        { programs.artcraft.enable = true; }
      ];
    };
  };
}
```

**home-manager module:**

```nix
{
  imports = [ artcraft.homeModules.artcraft ];
  programs.artcraft = {
    enable = true;
    desktopEntry = true;         # app-menu entry, default true
    # package = pkgs.artcraft;   # or your own derivation
  };
}
```

`programs.artcraft.enable` installs the package and a desktop entry. NixOS has no
`xdg.desktopEntries` option, so the NixOS module adds a `makeDesktopItem`
package to `environment.systemPackages`; the home-manager module uses
`xdg.desktopEntries` (and enables `xdg.enable` for you).

**Overlay**, if you just want `pkgs.artcraft`:

```nix
nixpkgs.overlays = [ artcraft.overlays.default ];
environment.systemPackages = [ pkgs.artcraft ];
```

**Ad-hoc, no config:**

```bash
nix profile install path:.#artcraft
```

## Updating the pins

```bash
nix run .#update-pins                                     # HEAD of pins.branch
ARTCRAFT_REF=artcraft-v0.42.0 nix run .#update-pins       # a tag that has the crate
ARTCRAFT_REV=<full-sha> nix run .#update-pins             # an exact commit
ARTCRAFT_DATE=2026-11-01 nix run .#update-pins            # skip the GitHub API lookup
```

`update-pins` never hand-computes a hash. It writes a deliberately wrong hash
into `pins.nix`, runs `nix build .#artcraft`, scrapes Nix's `got: sha256-…` line
from the fixed-output mismatch, and repeats for `srcHash` then `cargoHash`.
Finally it builds once more with the real hashes and only exits 0 if that
succeeds — so a rev that fails to compile is reported rather than silently
pinned. `pins.nix` is regenerated from shell variables, so its comments and
layout stay stable across runs.

## What the derivation does

- `cargoBuildFlags = [ "--package" "artcraft_native" ]` — the workspace's
  `default-members` is the Tauri app, so the package must be selected explicitly.
- `installPhase` picks the binary out of `target/<triple>/release/` (the cargo
  build hook passes `--target`) and installs upstream's app icons
  (`crates/desktop/artcraft/icons/`) into `$out/share/{artcraft,icons/hicolor}`.
- `doCheck = false` — plain `cargo test` would try to build the Tauri crate and
  the frontend; run the Rust tests in `nix develop` with
  `cargo test --package artcraft_native`.
- `makeWrapper` around the binary:
  - `LD_LIBRARY_PATH` gets the libs that the Rust bindings `dlopen` instead of
    linking: **libglvnd** (the `libGL.so.1`/`libEGL.so.1` dispatchers), Wayland,
    X11, xkbcommon, fontconfig, ALSA — plus `/run/opengl-driver/lib`, NixOS's
    OpenGL driver directory. Mesa is deliberately **not** on the path: in nixpkgs
    it only ships the vendor ICD, and a second mesa next to the system driver
    breaks context creation (see Troubleshooting).
  - `PATH` gets `ffmpeg`/`ffprobe` (in-app video playback shells out to them) and
    `xdg-open` (the `open` crate).
- `meta.mainProgram = "artcraft"`, so `nix run` and `lib.getExe` hit the wrapper.
  Both `artcraft` and `artcraft-native` exist in `$out/bin`.
- Release profile gets `LTO = "thin"` and `codegenunits = 16`; a full `lto = true`
  build costs several minutes for little gain on a GUI app.

## Sign-in and settings (upstream behaviour)

- Session: reused from the Tauri app's cookie jar
  (`<cache dir>/ai.artcraft.app/.cookies`), stored in
  `~/Artcraft/credentials/native_session.json`, or via "Sign in with browser" /
  username + password.
- API host: `~/Artcraft/settings/env_configs.json`.
- Diagnostics env vars: `ARTCRAFT_SCREENSHOT=/tmp/x.png`, `ARTCRAFT_PAGE`,
  `ARTCRAFT_SCREENSHOT_EXIT=1`.

## Caveats

- **`aarch64-linux` is unevaluated here.** `cargo vendor` pulls every target in
  `Cargo.lock` (we saw `windows-sys`, `wit-component`, ... in the vendor log), so
  `cargoHash` is host-independent in practice — but if `nix build .#artcraft`
  on aarch64 reports a different hash, run `nix run .#update-pins` there and
  compare.
- **First build is heavy.** Vendoring the workspace lockfile (Tauri, `sqlx`,
  `wreq` and other crates this build never compiles) is a few hundred MB.
- **Wayland decorations**: the app draws its own title bar
  (`with_decorations(false)`), so it behaves like a client-side-decorated window.
  Verified under niri (Wayland) and through XWayland.
- **GPU driver comes from your config.** This flake ships the GL *dispatchers*
  only; the actual driver must exist on the system (`hardware.graphics` +
  `enableDrivers` on NixOS, or the distro's mesa/nvidia packages elsewhere).
- The app is a network client: it does nothing useful without an ArtCraft
  account/API access.

## Troubleshooting

**`ERROR eframe::native::run: Exiting because of error: Found no glutin configs
matching the template: ... Error: not found`**

The binary found no usable `libEGL.so.1`/`libGL.so.1` dispatcher, or the
dispatcher and the vendor ICD disagree. Causes, in the order worth checking:

1. A stale build of this flake (before the libglvnd fix) that put nixpkgs' `mesa`
   on `LD_LIBRARY_PATH`. Rebuild/update the flake; the wrapper must contain
   `libglvnd`, not `mesa`.
2. No system OpenGL driver. The wrapper only supplies the dispatchers; the
   vendor library must come from your system: on NixOS `hardware.graphics.enable
   = true` (plus `services.xserver.videoDrivers = [ "nvidia" ];` for NVIDIA), so
   that `/run/opengl-driver/lib` exists and
   `/run/opengl-driver/share/glvnd/egl_vendor.d/*.json` points at it. On other
   distros the system mesa/nvidia packages provide the same thing.
3. Version skew between this flake's pinned nixpkgs and a much older/newer system
   driver. Debug with `LIBGL_DEBUG=verbose EGL_LOG_LEVEL=debug artcraft`.

To separate driver problems from packaging problems, try software rendering (it
still needs a working system mesa, but no kernel-mode GPU driver):

```bash
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe nix run .#artcraft
```

If your session looks fine but the app cannot connect to Wayland
(`NoWaylandLib`), it did not find `libwayland-client.so.0`; the wrapper provides
it, so that symptom means something stripped `LD_LIBRARY_PATH` (e.g. running the
unwrapped `bin/.artcraft-native-wrapped` directly). Always start
`bin/artcraft` (or `bin/artcraft-native`).

## Packaging the Tauri app instead

If you need the full official app (all pages, 3D scene tools), build
`crates/desktop/artcraft`: `buildNpmPackage`/`npmBuild` for `frontend/`, then
`rustPlatform.buildRustPackage` with `cargoBuildFlags = [ "--package" "artcraft" ]`,
`webkit2gtk_4_1`, `wrapGAppsHook3`, `cargo-tauri` and the `dist` folder the
Tauri config expects. Upstream's entry point is
`./script/artcraft/unix_dev.sh` (dev) and `_docs/dev_setup.md`.

## Wrapping the macOS app (not implemented)

macOS hosts can skip compiling: `fetchurl` the release asset
(`ArtCraft_<ver>_universal.app.tar.gz` or `..._universal.dmg`) with its
`sha256`, unpack it in a fixed-output derivation, move `ArtCraft.app` into
`$out/Applications`, and gate the package on `stdenv.hostPlatform.isDarwin`.
Since the bundle is already signed and notarised upstream, don't re-sign it; the
usual Gatekeeper/quarantine caveats apply to any download.

## License

`MIT` for this flake (see `LICENSE`). ArtCraft itself is dual-licensed
MIT/Apache-2.0 with third-party notices in its `NOTICE` file; the fonts it
bundles are under the SIL OFL.
