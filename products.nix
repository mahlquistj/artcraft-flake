# Product metadata for the Craft suite (storytold's "*craft" apps).
#
# Pure data: no `lib`, no package references, so both the Nix build and the
# shell update script can read it
# (`nix eval --impure --raw --expr 'builtins.toJSON (import ./products.nix)'`).
#
# What lives here is *stable* metadata: upstream identity, asset naming, which
# binaries the tarball ships, and what the wrapper has to provide. Volatile data
# (version, tag, URL, hashes) lives in pins.lock.json, which `nix run .#update`
# rewrites. Every product is `defaults // { … }`, so a new app is only its
# differences.
#
# Field notes:
#   assetPrefix    the file stem of the release asset; craft-launcher ships
#                  `artcraft-launcher-*` (legacy name) while the repo is
#                  `craft-launcher`.
#   systems        Linux architectures upstream publishes a `.tar.gz` for.
#                  riscv64 is tarball-only (no AppImage/deb/rpm/flatpak).
#   packageable    false = we deliberately do not build a package for it;
#                  `skipReason` explains why (surfaced in `nix eval` and CI).
#   glibcFloor     upstream's `GLIBC_*` symbol floor. riscv64 assets need 2.39.
#   needsAlsa      the binary has DT_NEEDED libasound.so.2, i.e. it *links* ALSA
#                  rather than dlopening it: without it on LD_LIBRARY_PATH the
#                  loader refuses to start the process. Verified per product with
#                  `sh/tests/wrapper-audit.sh`, not guessed.
#   needsXdgUtils  puts `xdg-open` (the `open` crate's backend) on PATH.
#                  Every product references xdg-open. Note xdg-utils drags a
#                  ~180 MB closure (perl, file, shared-mime-info, glib), which is
#                  why it is a flag rather than unconditional.
#   needsFfmpeg    the app shells out to ffmpeg/ffprobe. Verified: **no product
#                  references either binary** (they bundle their own codecs), so
#                  the flag is off everywhere and kept only for future releases.
#   verified       what this flake actually measured on the pinned release:
#                  `atVersion` = readelf/strings audit done on that version,
#                  `runtime`    = the GUI was launched on this machine.
let
  defaults = {
    owner = "storytold";
    appId = null;
    guiBin = null;
    cliBins = [ ];
    summary = "";
    description = "";
    license = "asl20"; # upstream is dual MIT/Apache-2.0; asl20 + the note in share/doc
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    glibcFloor = "2.35";
    glibcFloorBySystem = {
      riscv64-linux = "2.39";
    };
    needsAlsa = false;
    needsXdgUtils = true;
    needsFfmpeg = false;
    packageable = true;
    skipReason = null;
    notes = "";
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  app =
    name: description: summary:
    defaults
    // {
      inherit name summary description;
      repo = name;
      appId = "ai.storyteller.${name}";
      assetPrefix = name;
      guiBin = name;
      cliBins = [ "${name}-cli" ];
      verified.atVersion = "audited";
    };
in
{
  photocraft =
    app "photocraft"
      "PhotoCraft: an open-source, clean-room reimplementation of Adobe Photoshop in pure Rust"
      "Edit photos and layered PSD documents"
    // {
      notes = ''
        The only product with the library preflight wired to an escape hatch
        (PHOTOCRAFT_SKIP_LIB_CHECK=1) and with the distro package-name hint table
        in its strings. Verified end to end: Wayland + XWayland launch, CLI,
        desktop-file-validate clean.
      '';
      verified = {
        atVersion = "0.7.0";
        runtime = true;
      };
    };

  lightcraft =
    app "lightcraft"
      "LightCraft: an open-source, clean-room reimplementation of Adobe Lightroom in pure Rust"
      "Edit raw photos"
    // {
      notes = ''
        Extra env surface for external assets/models (LIGHTCRAFT_DEVICE_ROOTS,
        LIGHTCRAFT_FACE_MODELS, LIGHTCRAFT_SAM3_*, LIGHTCRAFT_GPU_BACKEND), i.e.
        it can download models at runtime — nothing for us to package, but worth
        knowing before trusting it offline.
      '';
      verified = {
        atVersion = "0.6.0";
        runtime = false;
      };
    };

  filmcraft =
    app "filmcraft"
      "FilmCraft: an open-source, clean-room reimplementation of Adobe Premiere Pro in pure Rust"
      "Edit video"
    // {
      needsAlsa = true;
      notes = ''
        dlopens libva.so.2 / libva-drm.so.2 (and libnvcuvid.so.1,
        libnvidia-encode.so.1) for hardware video decode. Verified at runtime:
        when those are absent it logs "no VA-API hardware decoding" and carries
        on with software decode, so it is graceful — and do NOT add nixpkgs libva
        to the closure (that is the store-vs-system driver skew that broke
        ArtCraft's GL). On NixOS put libva and the AMD VA-API driver in
        `hardware.graphics.extraPackages` so they land in /run/opengl-driver/lib,
        which the wrapper already appends.
      '';
      verified = {
        atVersion = "0.6.0";
        runtime = true;
      };
    };

  soundcraft =
    app "soundcraft"
      "SoundCraft: an open-source, clean-room reimplementation of Avid Pro Tools in pure Rust"
      "Record and mix audio"
    // {
      needsAlsa = true;
      verified = {
        atVersion = "0.5.0";
        runtime = true;
      };
    };

  vectorcraft =
    app "vectorcraft"
      "VectorCraft: an open-source, clean-room reimplementation of Adobe Illustrator in pure Rust"
      "Draw vector graphics"
    // {
      notes = "Mentions inkscape. Runs on Vulkan through wgpu (verified in its log) even though no libvulkan.so.1 string shows up in the binary — which is why vulkan-loader stays in the closure for every product.";
      verified = {
        atVersion = "0.9.0";
        runtime = false;
      };
    };

  pdfcraft =
    app "pdfcraft" "PdfCraft: an open-source, clean-room reimplementation of Adobe Acrobat in pure Rust"
      "Read, annotate and export PDF documents"
    // {
      notes = ''
        Also dlopens libGL.so.1 and libXrender.so.1 (both in the closure) and it
        is the only product that also ships standalone
        `<app>-cli-<ver>-linux-<arch>.tar.gz` assets — ignored, because the GUI
        tarball already contains bin/pdfcraft-cli. PDFCRAFT_RENDERER /
        PDFCRAFT_MODELS select the renderer and models; its log confirms it
        renders wgpu on Vulkan, so a missing libvulkan string elsewhere is not
        evidence of a GL-only app.
      '';
      verified = {
        atVersion = "0.6.0";
        runtime = true;
      };
    };

  wordcraft =
    app "wordcraft"
      "WordCraft: an open-source, clean-room reimplementation of Microsoft Word in pure Rust"
      "Write and format documents"
    // {
      verified = {
        atVersion = "0.5.0";
        runtime = false;
      };
    };

  gridcraft =
    app "gridcraft"
      "GridCraft: an open-source, clean-room spreadsheet (Microsoft Excel-style) in pure Rust"
      "Work with spreadsheets"
    // {
      verified = {
        atVersion = "0.5.0";
        runtime = false;
      };
    };

  deckcraft =
    app "deckcraft"
      "DeckCraft: an open-source, clean-room reimplementation of Microsoft PowerPoint in pure Rust"
      "Make presentations"
    // {
      # DT_NEEDED libasound.so.2 despite being the slideshow app: it plays audio.
      needsAlsa = true;
      notes = "DECKCRAFT_NO_AUDIO exists as an opt-out; ALSA is still linked at load time.";
      verified = {
        atVersion = "0.5.0";
        runtime = false;
      };
    };

  cadcraft =
    app "cadcraft"
      "CADCraft: computer-aided design and drafting, an open-source clean-room AutoCAD-style app in pure Rust"
      "Draft and design in 2D"
    // {
      verified = {
        atVersion = "0.5.0";
        runtime = false;
      };
    };

  designcraft =
    app "designcraft" "DesignCraft: an open-source, clean-room UI design tool in pure Rust"
      "Design interfaces"
    // {
      notes = "Upstream repo has no description; summary taken from its metainfo.";
      verified = {
        atVersion = "0.6.0";
        runtime = false;
      };
    };

  figcraft =
    app "figcraft"
      "FigCraft: an open-source, clean-room interface design and prototyping tool in pure Rust"
      "Design and prototype user interfaces"
    // {
      notes = ''
        Native interface design and prototyping (frames, auto layout, components,
        prototyping, SVG/PNG export) rendered through wgpu on Vulkan. It is also a
        collaboration client: it dials a `figcraft-server` for shared sessions and
        a plugin registry and honours FIGCRAFT_CA_FILE for a custom CA bundle.
        That server is a separate release asset, not part of the GUI tarball, and
        is not packaged here. References xdg-open through the webbrowser crate; no
        ALSA/PipeWire string (not a DT_NEEDED-libasound product).
      '';
      verified = {
        atVersion = "0.6.0";
        runtime = false;
      };
    };

  effectcraft =
    app "effectcraft"
      "EffectCraft: an open-source, clean-room motion graphics and effects tool in pure Rust"
      "Compose motion graphics and visual effects"
    // {
      needsAlsa = true;
      notes = "Composites on Vulkan via wgpu (verified). No ffmpeg/ffprobe reference at all; mentions pipewire. EFFECTCRAFT_FONT_DIRS / EFFECTCRAFT_CJK_LOCALE exist.";
      verified = {
        atVersion = "0.8.0";
        runtime = false;
      };
    };

  # ArtCraft Launcher: browses and *installs/updates* Craft apps into user
  # state, and shells out to flatpak/apt/dnf/zypper. That is the one part of the
  # suite Nix must not hand over, so it is metadata-only until P3 decides
  # otherwise (see PLAN.md §4 P3, §5.3).
  craft-launcher = defaults // {
    repo = "craft-launcher";
    appId = null;
    assetPrefix = "artcraft-launcher";
    guiBin = null;
    cliBins = [ ];
    summary = "Browse, install and update the Craft apps";
    description = "ArtCraft Launcher: browse, install and update the Craft app suite";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    needsXdgUtils = false;
    packageable = false;
    skipReason = "Self-updates apps into ~/.local/share and calls flatpak/apt/dnf/zypper; conflicts with a Nix-managed install. Revisit in P3.";
    notes = "Assets are prefixed artcraft-launcher-, no riscv64 tarball, no -cli binary.";
  };
}
