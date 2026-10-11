# PLAN: packaging the whole Craft App suite

Status: **P0 + P1 + P2 done, auto-merging pin bumps shipped** on 2026-10-11 — see §8 (what P0 shipped, and where it
differs from the sketch), §9 (the binary audit that corrected the wrapper
metadata) and §10 (P2: generated modules, asset validation, CI). Everything under
"Verified" was measured here (NixOS 26.11, x86_64-linux, niri/Wayland, AMD
Navi 48) on 2026-10-11.

Goal: one flake that installs any app in storytold's "Craft" suite, with the same
pin/update discipline we already use for ArtCraft.

---

## 1. Verified landscape

12 "classic" crafting apps + a launcher, **all separate repos**, all Apache-2.0
(dual MIT/Apache-2.0), all publishing Linux binaries:

| Repo | Latest | What it is (upstream's words) |
|---|---|---|
| `photocraft` | v0.7.0 | clean-room Photoshop |
| `lightcraft` | v0.6.0 | clean-room Lightroom |
| `filmcraft` | v0.6.0 | clean-room Premiere Pro |
| `soundcraft` | v0.5.0 | clean-room Pro Tools |
| `vectorcraft` | v0.9.0 | clean-room Illustrator |
| `pdfcraft` | v0.6.0 | clean-room Acrobat |
| `wordcraft` | v0.5.0 | clean-room Word |
| `gridcraft` | v0.5.0 | clean-room Excel |
| `deckcraft` | v0.5.0 | clean-room PowerPoint |
| `cadcraft` | v0.5.0 | clean-room CAD/drafting |
| `designcraft` | v0.6.0 | (design/figma-ish) |
| `effectcraft` | v0.8.0 | (AE-ish effects) |
| `craft-launcher` | v0.2.0 | ArtCraft Launcher: browse/install/update the suite |
| `artcraft` | v0.41.0 (Tauri-only) | the AI creation IDE — **the odd one out** |
| `craft-libs`, `craft-fonts` | no releases | shared Rust libs / fonts, build inputs only |

Asset matrix (every app; checked per release):

```
<app>-<ver>-linux-x86_64.{tar.gz,AppImage,deb,rpm,flatpak}   (+ .AppImage.zsync)
<app>-<ver>-linux-aarch64.{tar.gz,AppImage,deb,rpm,flatpak}
<app>-<ver>-linux-riscv64.tar.gz            # tarball only, glibc 2.39+
<app>-<ver>-freebsd-x86_64.tar.gz
<app>-<ver>-macos-universal.dmg
<app>-<ver>-windows-{x64,x86,arm64}{.msi,-portable.zip}
<app>-cli-<ver>-<platform>…                 # separate CLI artefacts
SHA256SUMS.txt                              # every asset, base16 sha256
```

Exceptions: `craft-launcher` prefixes its assets `artcraft-launcher-` (legacy
name), has no riscv64 and no `-cli`; `pdfcraft` also ships a riscv64 *cli* tarball.

### The Linux tarball is already an Nix-friendly prefix

`photocraft-0.7.0-linux-x86_64.tar.gz` (76 MB, 144 MB unpacked, 49 entries):

```
bin/photocraft                      # GUI, 88 MB, stripped
bin/photocraft-cli                  # headless CLI: convert/info/run/mcp
share/applications/ai.storyteller.photocraft.desktop   # complete: Exec, Icon,
                                                    # StartupWMClass, MimeType, Keywords
share/icons/hicolor/{16,24,32,48,64,128,256,512}x…/apps/ai.storyteller.photocraft.png
share/icons/hicolor/scalable/apps/ai.storyteller.photocraft.svg
share/metainfo/ai.storyteller.photocraft.metainfo.xml
share/mime/packages/ai.storyteller.photocraft.xml
share/doc/photocraft/{LICENSE-APACHE,LICENSE-MIT,OFL-*.txt,README.md}
```

So we do **not** author `.desktop` files, icons, mime types or AppStream for these
apps — upstream ships them, correctly, with the `ai.storyteller.<app>` app id. That
is a much better situation than ArtCraft (where we hand-rolled the entry).

### The binaries need exactly one patch and one environment

```
$ readelf -d bin/photocraft | grep NEEDED
libgcc_s.so.1  libm.so.6  libc.so.6  ld-linux-x86-64.so.2      # nothing else
$ readelf -l ... | grep interpreter
[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]  # → patchelf
$ strings -a bin/photocraft | grep GLIBC_ | sort -Vu | tail -1
GLIBC_2.35                                                    # floor; x86_64/aarch64
```

Everything graphical is `dlopen`ed: `libEGL.so.1`/`libGL.so.1`,
`libvulkan.so.1`, `libwayland-client.so.0`, `libwayland-egl.so.1`,
`libxkbcommon.so.0`, `libxkbcommon-x11.so.0`, `libX11.so.6`, `libX11-xcb.so.1`,
`libxcb.so.1`, `libXcursor.so.1`, `libXi.so.6`. Upstream's own FreeBSD dependency
line says the same:
`libxkbcommon wayland libX11 libXcursor libXrandr libXi libxcb mesa-libs
vulkan-loader gtk3 fontconfig freetype2 alsa-lib`.

These apps are **wgpu** apps (Vulkan-first, GL/EGL fallback), so `vulkan-loader`
plus the system Vulkan ICD matters more than `libglvnd`.

### The app checks for those libraries itself

`strings` on the binary reveals a preflight that names the sonames *and* the
distro package names, plus an escape hatch:

```
libwayland-client.so.0 … libxkbcommon.so.0 … libvulkan.so.1 … libEGL.so.1 …
libX11.so.6 libX11-xcb.so.1 libxcb.so.1 libXcursor.so.1 libXi.so.6 libxkbcommon-x11.so.0
LD_LIBRARY_PATH  /sbin/ldconfig -p   → “libs found in cache”
( Set PHOTOCRAFT_SKIP_LIB_CHECK=1 to start anyway. )
--safe-gpu: CPU renderer for this launch
PHOTOCRAFT_NATIVE_WAYLAND, PHOTOCRAFT_CPU_CANVAS, PHOTOCRAFT_GPU_STARTUP_FAILURE
```

NixOS has no `/sbin/ldconfig` and nothing in the ld.so cache, so the check can
only pass through `LD_LIBRARY_PATH` — which is exactly what the wrapper supplies,
with precisely that soname list. That is the spec for our runtime closure; if a
product's build prints the “missing libraries … start anyway” dialog, the wrapper
list is wrong, not the system.

### Two more runtime requirements the strings reveal

- **File dialogs and colour picking go through xdg-desktop-portal**: the binary
  embeds `rfd-0.17.2/src/backend/xdg_desktop_portal/…`,
  `org.freedesktop.portal.FileChooser`, `org.freedesktop.portal.Screenshot`,
  `org.freedesktop.portal.Settings`. So on NixOS these apps want
  `xdg.portal.enable = true` (+ a portal implementation) or file open/save will
  fail. A `gtk3` fallback exists (upstream's FreeBSD list includes it).
- **Theme detection reads gsettings**: `org.gnome.desktop.interface`,
  `/usr/bin/gsettings` → without `gsettings-desktop-schemas` in the environment
  the app cannot see dark/light preference. P2 must check whether it degrades
  quietly, and if not, put `gsettings-desktop-schemas` on
  `XDG_DATA_DIRS`/`GSETTINGS_SCHEMAS_PATH` in the wrapper.

### Spike result (proves the approach)

Patched only the interpreter, then ran it on this box:

```sh
LD_LIBRARY_PATH="$(makeLibraryPath [libglvnd vulkan-loader wayland libx11 libxcb \
  libxkbcommon fontconfig freetype alsa-lib libxrandr libxi libxcursor libxext]):/run/opengl-driver/lib"
photocraft            # → window opens, log shows:
                      #   gpu canvas: target Bgra8Unorm, max texture 16384, 16F canvas
                      #   WARNING: radv is not a conformant Vulkan implementation, testing use only.
                      #   tablet pressure: not available on this display server (Some(Wayland))
photocraft-cli --version   # → photocraft-cli 0.7.0 (792616159, 2026-10-11), exit 0
```

And the checksum pipeline is exact, with no Nix build involved:

```sh
nix hash convert --hash-algo sha256 --to sri \
  641f831252fd31b43ee1a12e572d7442e5652c2e5bf623de085741c370f0c91d
# → sha256-ZB+DElL9MbQ+4aEuVy10QuVlLC5b9iPeCFdBw3DwyR0=   (matches the download)
```

---

## 2. Strategy: prebuilt binaries, not source

**Decision: primary packaging = the Linux `.tar.gz`, patched and wrapped.**
Reasons:

1. Upstream builds and signs these for 4 OSes / 3 Linux arches; a Nix source build
   cannot match that matrix and duplicates their CI.
2. Update cost drops from "vendor ~hundreds of MB and compile" to "curl a 20-line
   checksum file". ArtCraft's `update-pins` needs 2 hash-mismatch builds per bump;
   these need **zero builds** — `SHA256SUMS.txt` + `nix hash convert`.
3. The tarball already contains desktop/mime/metainfo assets in FHS layout.
4. They are early-alpha and move fast (photocraft 0.1.1 → 0.7.0 in eight days,
   2026-10-03 → 2026-10-11), so cheap bumps matter more than reproducibility
   purity; each app also ships its own AppStream `<release version date>` inside
   the tarball.
5. Bonus: upstream ships a headless `<app>-cli` with an MCP server
   (`photocraft-cli convert|info|run|mcp`), so a Nix install is immediately
   scriptable/agent-drivable — and `--version` gives CI a loader test that needs
   no display.

Costs/risks of binary packaging, all mitigable:
- `sourceProvenance = binaryNativeCode` → no rebuild from source, no
  `nixpkgs`-mainline eligibility (fine for a personal flake).
- Trust: hashes come from the same GitHub release as the binary (GitHub TLS,
  unsigned artefacts) — same trust level everyone gets, and we keep hashes in git.
  No cosign/Sigstore/attestation is published; a later phase could record GitHub
  artifact attestations if they add them.
- glibc floor 2.35 (2.39 on riscv64): assert `stdenv.hostPlatform.libc == "glibc"`
  and that nixpkgs' glibc ≥ 2.35, else `meta.broken`.
- Upstream may rename assets (launcher already inconsistent) → the update script
  must *fail loudly* on missing assets, never silently skip.

**Keep ArtCraft as a source build** (no Linux artefacts exist). Its egui
`artcraft-native` crate stays our only compiled package; add the Tauri app only if
someone actually asks. Later, if we want a source path for the other apps, add a
`withSource = true` variant per product — they share `craft-libs`, so one
`buildRustPackage` template would serve all of them.

---

## 3. Repository shape

Turn this flake into a **craft suite flake** (name stays `artcraft-flake` for
compatibility; add a `craft` alias set). Data-driven, one builder, N products.

```
flake.nix                    outputs generated from products.nix
products.nix                 attrset: productName → metadata (no hashes)
pins.lock.json               GENERATED: version/tag/date + per-system sha256
pkgs/craft-app/default.nix   generic prebuilt builder (fetchurl→patchelf→wrap)
pkgs/craft-app/mkWrapper.sh  the LD_LIBRARY_PATH/PATH story, shared
pkgs/artcraft.nix            unchanged: source build (artcraft-native)
pkgs/desktopItem.nix         used only by the ArtCraft module
update/default.nix           `nix run .#update [product…]` — parses SHA256SUMS.txt
modules/crafts.nix           programs.<name>.enable, generated per product
modules/home-manager.nix     programs.artcraft (source build; hand-written today)
modules/nixos.nix            ditto
tests/prebuilt-eval.nix      eval harness: every product × every supported system
tests/hm-module.nix          exists already
tests/nixos-eval.nix         exists already
```

### 3.1 Product metadata (`products.nix`)

```nix
{
  photocraft = {
    owner = "storytold";
    repo = "photocraft";
    appId = "ai.storyteller.photocraft";
    guiBin = "photocraft";
    cliBin = "photocraft-cli";            # null for craft-launcher
    assetName = "photocraft";             # "artcraft-launcher" for craft-launcher
    systems = [ "x86_64-linux" "aarch64-linux" "riscv64-linux" ];
    needsVulkan = true;                   # wgpu apps; false for the launcher only if proven
    needsAlsa = true;                     # soundcraft/filmcraft certainly, others unknown
    glibcFloor = "2.35";                  # "2.39" for riscv64 assets
    license = lib.licenses.asl20;         # dual MIT/ASL; pick asl20 + note
    description = "PhotoCraft: a clean-room reimplementation of Adobe Photoshop";
    # desktop/mime/metainfo/icons all come from the tarball:
    shipDesktopAssets = true;
  };
  # …11 more…
}
```

### 3.2 Generic builder (`pkgs/craft-app`)

Sketch (not final code — argument names, `sourceRoot` and the phase split need a
real build to settle):
```nix
{ lib, stdenv, fetchurl, patchelf, makeWrapper, writeText
 , libglvnd, vulkan-loader, wayland, libx11, libxcb, libxkbcommon, libxkbcommon_x11
 , fontconfig, freetype, alsa-lib, gtk3, xorg, xdg-utils, ffmpeg ? null
 , pipewire ? null, product, pins }:
let
  asset = pins.${product.repo}.systems.${stdenv.hostPlatform.system};
  # runtime libs that the binary dlopen()s (never link-time deps)
  runtimeLibs = [ libglvnd vulkan-loader wayland libx11 libxcb libxkbcommon
                  libxkbcommon_x11 fontconfig freetype ]
    ++ lib.optionals product.needsAlsa [ alsa-lib ]
    ++ lib.optionals (product.gui && gtk3 != null) [ gtk3 ];
in stdenv.mkDerivation {
  pname = product.repo;
  version = pins.${product.repo}.version;
  src = fetchurl { url = asset.url; sha256 = asset.sha256; };  # from SHA256SUMS.txt
  nativeBuildInputs = [ patchelf makeWrapper ];
  phases = [ "unpackPhase" "patchPhase" "installPhase" "fixupPhase" ];
  sourceRoot = "${product.assetName}-${asset.tag}-linux-${stdenv.hostPlatform.parsed.cpu.name}";

  # Prebuilt ELF: no hardening, no strip, no RPATH rewriting surprises.
  hardeningDisable = [ "all" ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp -r bin/* "$out/bin/"
    # share/{applications,icons,metainfo,mime,doc} ship ready-made
    cp -r share "$out/share"
    runHook postInstall
  '';

  postFixup = ''
    for b in ${builtins.concatStringsSep " " product.bins}; do
      [ -f "$out/bin/$b" ] || continue
      # glibc 2.35+ binaries on a 2.44 host: only the interpreter needs fixing.
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$out/bin/$b"
    done
    for b in ${builtins.concatStringsSep " " product.bins}; do
      [ -f "$out/bin/$b" ] || continue
      mv "$out/bin/$b" "$out/bin/.$b-wrapped"
      makeWrapper "$out/bin/.$b-wrapped" "$out/bin/$b" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib" \
        --prefix PATH : "${lib.makeBinPath ([ xdg-utils ] ++ lib.optional (ffmpeg != null) ffmpeg)}" \
        --set PHOTOCRAFT_NO_DESKTOP_INTEGRATION 1     # per-product name; see risks
    done
  '';

  meta = { mainProgram = product.guiBin; platforms = …; };
}
```

Design notes / non-negotiables:

- **libglvnd, never mesa, on `LD_LIBRARY_PATH`** — the exact bug that broke the
  ArtCraft package (nixpkgs' mesa has no `libEGL.so.1`). Same for these.
- `/run/opengl-driver/lib` last, so the *system* ICD/driver wins over anything in
  the store; `/run/opengl-driver` also carries the Vulkan ICD + JSON, so
  `VK_ICD_FILENAMES`/`XDG_DATA_DIRS` need no tinkering on NixOS.
- Keep the two binaries: GUI (`photocraft`) and headless CLI (`photocraft-cli`),
  which is how we get cheap CI smoke tests.
- Install upstream's `share/` verbatim (desktop + hicolor + scalable svg +
  metainfo + mime). Validate with `freedesktop.desktop-file-utils`/`appstream-glib`
  in `passthru.tests` instead of inventing our own entries.
- `hardeningDisable = [ "all" ]` and no `strip`: we must not touch upstream
  signatures/binaries beyond the interpreter.

### 3.3 Pin/update story (`nix run .#update`)

Per product: `curl` the release listing → tag; `curl SHA256SUMS.txt` → base16;
`nix hash convert --to sri`; write `pins.lock.json`. No Nix builds, so it is fast
and it can update all 13 products in one run.

```
nix run .#update                       # all products, latest releases
nix run .#update -- photocraft         # one product
nix run .#update -- --dry-run          # print the diff only
ARTCRAFT_PINS_FILE=pins.lock.json …    # CI reuse
```

Hard requirements for the script (learned from the launcher's naming):
- resolve `<app>-<ver>-linux-<arch>.tar.gz` by exact pattern; **error** if any
  supported system is missing, listing what the release did contain;
- treat the `SHA256SUMS.txt` line count as a sanity check;
- refuse to downgrade unless `--allow-downgrade`;
- store `version`, `tag`, `releaseDate`, `url`, `sha256` per system so failures are
  debuggable without network access.

### 3.4 Flake surface

```nix
packages.<system>.{photocraft, lightcraft, …, artcraft, default = craft-suite}
packages.<system>.craft-suite             # symlinkJoin of all enabled apps
packages.<system>.update                  # the script
apps.<system>.<name>                      # nix run .#photocraft
overlays.default                          # adds all products + artcraft
nixosModules.crafts / homeModules.crafts  # programs.<name>.enable per product
devShells.<system>.default                # for artcraft's source build
checks.<system>.{build-artcraft, desktopItem, nixfmt, prebuilt-eval, smoke-*}
```

Module API, per product (mirrors what we already ship for ArtCraft):

```nix
programs.photocraft = {
  enable = true;
  package = null;            # default: the flake's prebuilt build
  enableDesktopEntry = true; # upstream ships it; option only gates installation
};
programs.crafts.enable = [ "photocraft" "lightcraft" "filmcraft" ];  # convenience list
```

Both modules must stay on the *home-manager-safe* form: `settings.StartupWMClass`
rather than `startupWMClass` (the bug we already hit), and no forced `xdg.enable`.

---

## 4. Phases

**P0 — foundation (½–1 day)**
`products.nix`, `pins.lock.json`, `pkgs/craft-app`, `update/` script; wire
`photocraft` only.
*Accept:* `nix run .#photocraft` opens a window on niri; `photocraft-cli
--version` runs; `nix flake check` green; `nix run .#update -- --dry-run`
reproduces the committed pins; `git diff` after a bump shows only
`pins.lock.json`.

**P1 — the other 11 apps + launcher (1 day, mostly mechanical)**
*Accept:* every product's GUI launches on Wayland **and** under
`WAYLAND_DISPLAY= ` (XWayland); every CLI answers `--version`; per-product
runtime-lib list is minimal (no mesa, no leftover guesses); `update` handles all
products including the `artcraft-launcher-` prefix; riscv64 and aarch64 hashes
recorded (eval-only CI until we can build there).

**P2 — correctness + integration (1 day)**
- validate upstream `.desktop`/metainfo in `passthru.tests`;
- assert glibc floor and emit a clear message on unsupported platforms;
- NixOS + home-manager modules generated from `products.nix`;
  extend `tests/{nixos,hm}-eval.nix` to loop over products;
- real smoke tests in CI where possible (`--version`, `--help`) — headless, so
  they run on any builder.

**P3 — launcher + suite UX (½ day, needs a decision, see §5)**
`craft-launcher` (ArtCraft Launcher) *self-updates apps into user state*, which
fights Nix. Options: (a) package it and document that it must not install apps
(check whether it honours an env var / has an "installed apps" discovery path),
(b) skip it, (c) ship it as read-only metadata browser. Investigate first.

**P4 — optional extras**
- macOS via the `.dmg` (`fetchurl` + `dmg` → `cp -R` .app, `undmg`-style), gated
  on darwin systems, with a note that we do not re-sign upstream's bundle;
- source-build variants (`withSource`) for the apps that have public repos and
  `craft-libs`-based workspaces, if reproducibility becomes a priority;
- Flatpak-side-by-side: nothing to do, just document;
- submit to nixpkgs? Blocked by `binaryNativeCode` unless upstream adds
  reproducible source builds — park it.

---

## 5. Open decisions (need your call)

1. **Repo layout:** extend this flake (recommended; shared wrapper logic) or one
   flake per app? Extension means one `pins.lock.json` + one update script.
2. **Which apps first?** I'd do photocraft → filmcraft/soundcraft (they need
   ALSA/Vulkan + ffmpeg, so they stress the wrapper) → the rest.
3. **Launcher:** package ArtCraft Launcher (self-update conflict) or skip? It also
   shells out to `flatpak`/`apt`/`dnf`/`zypper` per its README, so a Nix-native
   install path would need upstream cooperation.
4. **Portal dependency:** should the NixOS module assert/remind about
   `xdg.portal.enable`, or silently add nothing? File dialogs are broken without
   a portal implementation.
5. **Version granularity:** pin *latest release* per product (simple, fast) or let
   users override a single product's version (needs per-product pins)?
6. **ffmpeg/PipeWire:** `filmcraft`/`soundcraft` almost certainly shell out to
   ffmpeg for codecs. Add a per-product `runtimeBins` list, defaulting ffmpeg onto
   `PATH` for filmcraft/soundcraft/effectcraft after checking their `strings`.

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Store mesa on `LD_LIBRARY_PATH` → `NoGlutinConfigs`/Vulkan init failure | libglvnd + vulkan-loader only; `/run/opengl-driver` appended last; regression test that runs the app headless with `WGPU_BACKEND=vulkan` |
| Asset renaming / per-product quirks (launcher prefix, riscv tarball-only) | exact-pattern resolver + hard failure listing available assets; `pins.lock.json` records URLs so breaks are obvious in diffs |
| glibc floor (2.35 / 2.39 riscv) | assert in the builder with an actionable message |
| Upstream self-update writes to `~/.local/share` (desktop integration, launcher installs) | set `PHOTOCRAFT_NO_DESKTOP_INTEGRATION=1` (per-product var, confirm for each) and don't package the launcher's install path; document |
| Binary-only provenance | record upstream `SHA256SUMS` line verbatim in pins; keep `meta.sourceProvenance = binaryNativeCode` honest |
| Store size: each app is ~80-145 MB unpacked, and there are 13 of them | document it; users pick products, and `craft-suite` is opt-in, not the default |
| Wayland drag-and-drop missing in winit 0.30 (photocraft README) | document; `WAYLAND_DISPLAY= ` fallback already works (verified) |
| Apps we package get stale silently | scheduled `update-pins.yml`: `nix run .#update -- --all` -> PR -> auto-merge (squash) once the `flake check` job passes; `--fail-on-change` stays for a manual freshness-only check |
| Upstream trademarks/brand clause (pdfcraft README) | keep upstream's `share/doc` licences + brand notes untouched; don't re-host icons ourselves |
| Upstream's own lib preflight rejects the closure (see §1) | satisfy it via `LD_LIBRARY_PATH` (the wrapper does); `PHOTOCRAFT_SKIP_LIB_CHECK=1` exists as an escape hatch but treat needing it as a bug in our wrapper |
| GitHub API rate limits while bumping 13 products | resolve tags/URLs from `releases.atom` + `releases/expanded_assets/<tag>` + the `<appId>.metainfo.xml` `<release date=…>` inside the tarball; the API is only a convenience |

---

## 7. Definition of done for the plan

P0 + P1 green ⇒ the flake installs any Craft app with
`programs.<app>.enable = true`, bumps with one no-build command, and every
product's desktop entry, icon and mime types come from upstream rather than from
us. At that point ArtCraft's hand-rolled desktop entry is the only bespoke piece
left, which is exactly what it should be (it is the only source build).

---

## 8. P0 outcome (2026-10-11)

Decisions taken before writing code: extend **this** flake (data-driven, shared
wrapper, one pins file, one update command); P0 = **photocraft end-to-end**;
pins are **latest-release-only** (a user who needs an older build overrides
`package`); **craft-launcher is not packaged** (kept in `products.nix` with
`packageable = false` and its reason, so the decision is visible in `nix eval`).

Shipped: `products.nix`, `pins.lock.json`, `pkgs/craft-app/default.nix`,
`pkgs/craft-suite.nix`, `update/default.nix` (`nix run .#update`),
`tests/prebuilt-eval.nix`, generated flake surface (`packages.<name>`,
`apps.<name>`, `craft-suite`, overlay, `checks.smoke-*`, `checks.prebuilt-eval`),
`pkg/` → `pkgs/`, `update.nix` → `update/artcraft-pins.nix`.

Acceptance, as measured: `nix build .#photocraft` builds; the GUI opens under
niri **and** with `WAYLAND_DISPLAY` unset (XWayland) with no library-preflight
complaint; `photocraft-cli --version`/`--help` work; `nix flake check` passes;
`nix run .#update -- --dry-run` reproduces the committed pins with an empty diff;
upstream's `.desktop` passes `desktop-file-validate` unmodified.

Where the implementation differs from §3, and why:

- **`libdbus` is in the runtime closure.** The preflight does not check it, but
  the embedded rfd 0.17.2 portal client `dlopen`s `libdbus-1.so.3` and fails with
  "Can't connect to a portal: libdbus-1.so not found" → without it, Open/Save and
  the colour picker are dead. §1's list was incomplete in exactly this way.
- **`PHOTOCRAFT_NO_DESKTOP_INTEGRATION` does not exist.** It was a guess in the
  §3.2 sketch. The real env surface (from `strings`) is
  `PHOTOCRAFT_SKIP_LIB_CHECK`, `PHOTOCRAFT_NATIVE_WAYLAND`, `PHOTOCRAFT_CPU_CANVAS`,
  `PHOTOCRAFT_GPU_STARTUP_FAILURE`, `PHOTOCRAFT_CONFIG_DIR`, `PHOTOCRAFT_NO_SYSTEM_FONTS`,
  `PHOTOCRAFT_AUTOMATION_{READ,WRITE}_ROOT`, `PHOTOCRAFT_CONTROL_{PORT,TOKEN}`.
  No self-update code paths showed up in photocraft, so the §6 risk row is
  launcher-specific only (and we do not package the launcher).
- **We set neither `PHOTOCRAFT_SKIP_LIB_CHECK` nor any override**: the wrapper is
  expected to satisfy the preflight, and needing the escape hatch is a bug here.
- **`dontPatchELF = true`** in addition to `dontStrip`/`hardeningDisable`:
  stdenv's patchelf setup hook would otherwise run `--shrink-rpath` over both
  ELFs. `patchelf --set-interpreter` in `postFixup` is the only byte change
  (binary grows ~5 KB for the longer interpreter path; verified the tail of the
  file is byte-identical to upstream).
- **`nixpkgs` renamed `xorg.libX11` → `libx11`, `libxcb`, `libxcursor`, `libxi`,
  `libxrandr`, `libxext`** (deprecated aliases print eval warnings); the builder
  uses the new names. `libxkbcommon` ships `libxkbcommon-x11.so.0` in the same
  output, so no separate attribute.
- **`pkgs/craft-app/mkWrapper.sh` was not needed**: the wrapper is two
  `makeWrapper` calls in `postFixup`, generated from the product metadata; a
  shared shell file would only hide the closure list.
- **`nix build .` (default) stays the ArtCraft source build**, not `craft-suite`:
  thirteen products × ~100 MB makes `nix build .` a gigabyte. `.#craft-suite` is
  the explicit opt-in.
- **`nix run .#update` defaults to the products already pinned**, `--all` adopts
  everything packageable. That keeps "keep my pins fresh" and "adopt a new app"
  distinct, which the P0/P1 split needs.
- **Gotcha for later Nix in this repo**: `x.y or throw "…"` parses as *calling*
  `x.y` with the string; wrap it as `x.y or (throw "…")`.
- **This box runs nix-ld** (`/lib64/ld-linux-x86-64.so.2` → nix-ld 2.0.6), so the
  §1 spike's unpatched binary "worked" for the wrong reason. Store-built packages
  are unaffected (interpreter points at store glibc), but any future *unpackaged*
  experiment here needs a non-nix-ld host to be meaningful.
- **`checks.smoke-<app>`** runs `<app>-cli --version` (display-free, so it works
  in a sandboxed builder) and asserts the GUI wrapper sets `LD_LIBRARY_PATH` and
  that the ELF behind it has a store interpreter.

Not done (next phases): P1's other eleven apps + per-product runtime-lib
minimisation, P2's generated `programs.<app>` modules and metainfo validation
(`appstream-glib` in nixpkgs ships no `appstream-util` binary any more — use
`pkgs.appstream` or `validate-files`), P3 launcher investigation.
- **Closure reality vs §6's estimate.** A photocraft package closure is **375 MB**
  (150 MB of upstream ELFs + glibc 36 MB + the *xdg-utils* chain: perl 58 MB,
  file, shared-mime-info, glib, ~180 MB total). `needsXdgUtils` is therefore a
  per-product flag (default true, because the `open` crate shells out to
  `xdg-open`) so P1 can weigh dropping it, and `craft-suite` stays opt-in.

---

## 9. P1 outcome (2026-10-11): all twelve products, metadata corrected by audit

`nix run .#update -- --all` adopted the other eleven products; all twelve build,
`nix flake check` runs twelve `smoke-<app>` checks (`<app>-cli --version` plus the
wrapper/interpreter assertions) and the eval-only `prebuilt-eval` across
x86_64/aarch64/riscv64. Upstream's twelve `.desktop` files pass
`desktop-file-validate` unmodified, so P2 has nothing to fix there.

`tests/wrapper-audit.sh` (new) prints, per product: `readelf -d` NEEDED, the
sonames the binary dlopens, ALSA/PipeWire hits, external commands, the
`<APP>_*` env surface and the shipped desktop entry. That replaced §5.6's guesses:

- **ALSA is DT_NEEDED, not dlopened**, and only in **deckcraft, effectcraft,
  filmcraft, soundcraft**. `needsAlsa` now means exactly that; the wrapper's
  `LD_LIBRARY_PATH` is what satisfies a link-time dep on a foreign binary.
- **No product references ffmpeg or ffprobe** (§5.6 assumed three). `needsFfmpeg`
  is off everywhere; the flag stays for future releases. ArtCraft's source build
  remains the only package that shells out to ffmpeg.
- **Every product references `xdg-open`**, so `needsXdgUtils` is on for all — and
  that single flag is what makes a closure 375 MB instead of ~150 MB (perl, file,
  shared-mime-info and glib arrive with xdg-utils). If store size ever matters,
  the cheap win is a lighter `xdg-open` than xdg-utils, not dropping the libs.
- **`<APP>_SKIP_LIB_CHECK` exists only in photocraft**; the other eleven have no
  preflight escape hatch. Irrelevant to us (the closure satisfies the loader) but
  it means §1's "the app checks for those libraries itself" is photocraft-specific.
- **A missing `libvulkan.so.1` string is not evidence of a GL-only app.** pdfcraft
  has no such string yet its log says `renderer: wgpu; adapter: … (Vulkan)`, so
  vulkan-loader stays in the base closure for all twelve; libxrender was added for
  pdfcraft's `libXrender.so.1` dlopen.
- **filmcraft hardware decode**: dlopens `libva.so.2`/`libva-drm.so.2` (+ NVIDIA
  NVDEC/encode). Absent, it logs "no VA-API hardware decoding" and software
  decodes — graceful. Fix is system-side (`hardware.graphics.extraPackages`
  putting libva + the VA-API driver in `/run/opengl-driver/lib`), *not* store
  libva next to the system driver: that is the mesa/libglvnd skew in
  README/Troubleshooting.
- Runtime launches: **soundcraft** (ALSA device opens at 48 kHz), **filmcraft**
  (VA-API/NVDEC degrade as above), **pdfcraft** (RADV Vulkan adapter) — i.e. the
  three products whose binaries differ materially from photocraft's. Per the
  agreed scope, the other eight stay build + CLI verified.

`products.nix` became `defaults // { … }` per product with a `notes` field (now in
each package's `meta.longDescription`) and `verified = { atVersion, runtime; }`, so
"what did you actually measure, on which version" is machine-readable.

Next (P2): generated `modules/crafts.nix` (`programs.<app>.enable` per product,
portal reminder), metainfo validation in `passthru.tests` — `appstream-glib` in
this nixpkgs ships no CLI any more, use `pkgs.appstream` (`appstreamcli`) — and a
weekly `nix run .#update -- --dry-run` CI job. **Done in the follow-up to P2: see §11.**

---

## 10. P2 outcome (2026-10-11): modules, validated assets, CI

Decisions taken first: **two outputs** so `enableDesktopEntry` can actually gate
the menu entry, **`mkWarnings`** for the portal dependency (§5.4 — warn, never
mutate a service the user did not ask for), and **both GitHub Actions
workflows**.

Shipped: `pkgs/craft-app/tests.nix`, `modules/craft-options.nix`,
`modules/crafts.nix`, `modules/crafts-home-manager.nix`,
`tests/nixos-module-check.nix`, rewritten `tests/{nixos-eval,hm-module}.nix`,
`checks.<system>.{desktop-assets-<app>,nixos-crafts-module}`,
`update --fail-on-change`, `.github/workflows/{ci,update-pins}.yml`, and
`nixosModules.{crafts,default}` / `homeModules.{crafts,default}`.

API (both systems, one declaration source):

```nix
programs.<app> = { enable; package; enableDesktopEntry; };   # per product
programs.crafts.enable = [ "photocraft" "filmcraft" ];       # list sugar
```

The list is a `mkDefault`, so an explicit `programs.cadcraft.enable = false`
still wins — and both eval harnesses assert exactly that (cadcraft absent,
photocraft's `desktop` output absent, the other ten with theirs: 21 store paths
in a home environment, 22 + ArtCraft in a system environment).

Things P2 measured or forced, that the sketch did not anticipate:

- **Option keys must not depend on `pkgs`.** Deriving the *names* of
  `programs.<app>` from the system's pin table (via `pkgs.stdenv`) means forcing
  `_module.args.pkgs` — a **config** value — while building the option namespace:
  `nixosSystem` then recurses ("querying `_module.args` instead, requiring
  `config`"). Defaults may use `pkgs` because those thunks are forced at merge
  time, so `names` now comes from products.nix + pins.lock.json alone, and a
  product pinned only for other systems fails later with the builder's own
  "no `<system>` asset" message.
- **`imports` cannot contain a list.** `nixosModules.default = [ m1 m2 ]` looks
  harmless and is not: a config writing `imports = [ flake.nixosModules.default ]`
  nests a list inside a list, and nixpkgs rejects it outright ("Module imports
  can't be nested lists. Perhaps you meant to remove one level of lists?") — a
  real user hit this after updating the flake input. `lib.mkMerge` cannot help
  either ("cannot append list"), and a module *function* cannot be combined by
  attribute. Shipped form:
  `nixosModules.default = { imports = [ self.nixosModules.artcraft self.nixosModules.crafts ]; }`
  — an attrset module that imports the two.
- **The coverage gap that let it ship.** `checks.nixos-crafts-module` passed the
  module *unwrapped* (`modules = [ m ]`), so the nested-list form was never
  exercised, and nothing forced `config.assertions` — which `system.build.toplevel`
  evaluates on every real rebuild. Both are now part of the check: it imports the
  way a config does (`{ imports = [ module ]; }`, with `module =
  nixosModules.default`, so ArtCraft's module rides along), and it evaluates
  `lib.all (a: a.assertion) config.assertions`. The home-manager harness imports
  `homeModules.default` for the same reason. Lesson for this flake: a check must
  evaluate the *documented entry point*, not the convenient internal shape.
- **A config attrset built from another config value recurses.**
  `programs = genAttrs config.programs.crafts.enable (…)` deadlocks the definition
  push-down; the working form is static keys from the product list with
  `mkIf (elem name …)` inside.
- **Upstream assets validate, with one caveat each.** `desktop-file-validate`:
  12/12 clean (cadcraft and effectcraft emit non-fatal *hints* about
  `Categories`). `appstreamcli validate`: 8/12 "fail" with exactly one warning —
  `URL was not found on the server`, a **live network fetch** — so the test uses
  `--no-net`, after which 12/12 pass. Which is also why the validation belongs in
  a derivation, not in a manual checklist.
- **`pkgs.appstream-glib` no longer ships a CLI** in this nixpkgs (outputs are
  `out/dev/man/installedTests`); `pkgs.appstream` provides `appstreamcli`.
- **The metainfo file is a second, independent version oracle.** Its
  `<release version=… date=…>` matched `pins.lock.json` for all twelve products,
  so the test compares them: a tag/asset mismatch now fails a build instead of
  shipping silently mislabelled AppStream.
- **NixOS's `system.stateVersion`/`nixpkgs.pkgs` shape matters for the check**:
  `checks.nixos-crafts-module` evaluates a real `nixosSystem` with
  `nixpkgs.pkgs = pkgs` (not `specialArgs.pkgs`, which silently disables
  `nixpkgs.overlays`), then asserts the installed set is exactly out+desktop per
  product before linking those paths — so it also *builds* what the module
  installs.

Next: **P3** — decide what to do about `craft-launcher` (investigate whether it
has a read-only/discovery mode before packaging it), and **P4** — the optional
extras (macOS `.dmg`, `withSource` variants). §5.5 (per-product version
overrides) stays closed: latest-release-only was chosen.

---

## 11. Follow-up: unattended pin bumps (§6's stale-pin row, closed)

Requested behaviour: Mondays 06:00 UTC → update pins → if anything moved, open a
PR → auto-merge once the tests pass. Decisions taken first: **fail if the bump
token is missing** (rather than degrade to a PR with no gating CI), **squash**
(generated file, per-week history has no value), **one reused branch**
(`craft/update-pins`) so a red week does not pile up competing PRs.

Flow of `update-pins.yml`: require `CRAFT_BUMP_TOKEN` → `nix run .#update -- --all`
→ `git diff --quiet -- pins.lock.json` (nothing moved → open nothing) → commit to
the branch and push (force-with-lease if the branch exists) → `gh pr create`, or
reuse the open PR with a comment carrying the fresh diff → `gh pr merge --auto
--squash`.

The GitHub-side facts that shaped it (all from current docs, checked rather than
assumed):

- A PR opened with `GITHUB_TOKEN` now yields `pull_request` runs in an
  **approval-required** state — auto-merge would wait for a human click forever.
  Hence the fine-grained PAT for *authoring only*; the push still uses the job's
  own token, so the commit stays attributed to the bot.
- Checks only satisfy required status checks when the run was triggered by
  `push`/`pull_request`/`pull_request_target` — a `workflow_run` or
  `workflow_dispatch` check does **not** gate a merge. So there is no value in a
  "watcher" workflow; the gate has to be a real `pull_request` run of `ci.yml`.
- `gh pr merge --auto` fails immediately when a required check is already red,
  which is the loud behaviour we want, and is idempotent, so re-arming a PR whose
  auto-merge was disabled by a later push is free.
- Consequently `main` must require the check by **name**, so the `ci.yml` job is
  named `flake check` and README lists the three settings (auto-merge + squash,
  required check, repository secret). Without a required check, auto-merge has
  nothing to wait for and could land a red bump.

Local rehearsal (`/tmp/rehearse.sh`, throwaway): local bare remote + a `gh` stub
emulating `--jq`. Run 1 (pins move, no PR) → plain push, PR created, auto-merge
armed; run 2 (pins move again, PR still open) → force-with-lease, PR reused,
comment + body update, re-armed; run 3 (nothing moved) → `changed=false`, no
commit, no PR. It found three things, none in the workflow: a `${{ … }}` written
unquoted into YAML came out mangled, a multi-line quoted shell argument put text
at column 0 and terminated the `run: |` block scalar, and my stub ignored
`--jq`. The first two are exactly what `checks.<system>.workflows` now catches,
and it did: it failed the build on the invalid YAML before I ever pushed.
