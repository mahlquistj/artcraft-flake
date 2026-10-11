# artcraft-flake

[Nix flake](https://nixos.wiki/wiki/Flakes) that builds **ArtCraft**
(<https://github.com/storytold/artcraft>) from source for Linux.

## Why a source build?

ArtCraft's GitHub releases ship only macOS (`.dmg`, `.app.tar.gz`) and Windows
(`.exe`, `.msi`) installers — there are no Linux binaries, and CI only publishes
those two platforms. Upstream also says Linux is supported when building from
source (`_docs/dev_setup.md`).

The full app is a Tauri + React/Vite/Nx desktop client. This flake instead builds
`artcraft-native`, the upstream **pure-Rust egui client** (no Tauri, no webview,
no Node.js):

| | |
|---|---|
| Upstream crate | `artcraft-native` (`artcraft_native`, binary `artcraft-native`) |
| What it supports | Create Image / Video / Audio, feed, library, lightbox, characters, sign-in |
| What it does **not** need | Node, npm, Nx, Vite, `cargo-tauri`, webkit2gtk |
| Not in this flake | The Tauri app (`crates/desktop/artcraft`) — needs the JS toolchain |

`artcraft-native` exists only on `main`, not in any release tag, so the flake pins
a **commit on `main`** instead of a tag.

## Layout

```
flake.nix               outputs: packages, overlay, nixosModules, homeModules, devShell, apps
pins.nix                rev / date / version / srcHash / cargoHash  <- the only file you edit to bump
pkg/artcraft.nix        rustPlatform.buildRustPackage derivation
update.nix              nix run .#update-pins: re-resolves all of the above
modules/nixos.nix       programs.artcraft NixOS module
modules/home-manager.nix programs.artcraft home-manager module
```

## Use it

Run it once, no install:

```bash
nix run .#artcraft
```

Install it into your profile (ad-hoc):

```bash
nix profile install path:$PWD#artcraft   # or git+https://your-host/artcraft-flake
```

Pin the source in another flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    artcraft.url = "git+file:///home/maj/projects/artcraft-flake"; # or your GitHub URL
  };

  outputs = { nixpkgs, artcraft, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        artcraft.nixosModules.artcraft
        { nixpkgs.overlays = [ artcraft.overlays.default ]; programs.artcraft.enable = true; }
      ];
    };
  };
}
```

Just the package, via the overlay:

```nix
{
  nixpkgs.overlays = [ artcraft.overlays.default ];
  environment.systemPackages = [ pkgs.artcraft ];   # NixOS
  # home.packages             = [ pkgs.artcraft ];  # home-manager
}
```

### NixOS / home-manager module

```nix
programs.artcraft = {
  enable = true;
  # package = pkgs.artcraft;      # defaults to the flake's package
  desktopEntry = true;            # app-menu entry (default)
};
```

Installs the package, adds an `ArtCraft` desktop entry, and puts
`share/artcraft/artcraft.png` on disk for the icon.

### First launch / credentials

Per upstream's `artcraft-native/README.md`:

- Sign-in: username + password, **"Sign in with browser"** (device code), or the
  app imports an existing session from the Tauri app's cookie jar
  (`<cache dir>/ai.artcraft.app/.cookies`).
- Its own credentials: `~/Artcraft/credentials/native_session.json`
- API host overrides: `~/Artcraft/settings/env_configs.json`

## Bumping the version

```bash
nix run .#update-pins                      # track HEAD of pins.branch (main)
ARTCRAFT_REF=artcraft-v0.41.0 nix run .#update-pins   # a tag, if it contains artcraft-native
ARTCRAFT_REV=<full-sha> nix run .#update-pins
```

The script resolves the rev, then lets Nix compute the hashes by running each
fetch stage with a deliberately wrong hash and scraping the `got: sha256-…` line.
It writes `rev`, `date`, `version`, `srcHash`, `cargoHash` into `pins.nix`
(`sed` on those exact lines — don't reformat them), then verifies with a full
`nix build .#artcraft` before reporting success.

Keep the three fetches cached if you re-run often:

```bash
nix build .#artcraft          # vendored crates + build artifacts land in the store
```

## Notes / caveats

- `cargoHash` covers `cargo vendor` of the **whole workspace lockfile**, including
  the Tauri and `sqlx`/`wreq` dependencies that this build never compiles. First
  fetch is a few hundred MB.
- `doCheck = false`: the workspace's default member is the Tauri app, so a bare
  `cargo test` would try to build it. Run native tests in `nix develop`:
  `cargo test --package artcraft_native`.
- Runtime: needs OpenGL (Mesa / your GPU driver) and an X11 or Wayland session.
  In-app video playback additionally uses the `ffmpeg`/`ffprobe` put on `PATH` by
  the wrapper, and "open in browser" uses `xdg-open` (also wrapped).
- `LD_LIBRARY_PATH` is set by the wrapper for libraries that the Rust bindings
  `dlopen` rather than link (Wayland, X11, Mesa).
- The `open` crate needs `xdg-open`; the wrapper adds `xdg-utils` to `PATH`.
- macOS: not packaged here — upstream's `.dmg` / `ArtCraft_universal.app.tar.gz`
  assets are the way to go. Adding them as a fixed-output derivation on
  `aarch64-darwin`/`x86_64-darwin` is straightforward if you want it.

## Development

```bash
nix develop            # cargo, clippy, rustc, rustfmt, rust-analyzer + native libs
nix flake check        # builds .#artcraft and runs nixfmt --check
nix build .#artcraft
```
