# Product metadata for the Craft suite (storytold's "*craft" apps).
#
# Pure data: no `lib`, no package references, so both the Nix build and the
# shell update script can read it (`nix eval --raw --expr 'builtins.toJSON (import ./products.nix)'`).
#
# What lives here is *stable* metadata: upstream identity, asset naming, which
# binaries the tarball ships, and which runtime libraries/commands the wrapper
# has to provide. Volatile data (version, tag, URL, hashes) lives in
# pins.lock.json, which `nix run .#update` rewrites.
#
# Field notes:
#   assetPrefix    the file stem of the release asset; craft-launcher ships
#                  `artcraft-launcher-*` (legacy name) while the repo is
#                  `craft-launcher`.
#   systems        Linux architectures upstream publishes a `.tar.gz` for.
#                  riscv64 is tarball-only (no AppImage/deb/rpm/flatpak).
#   packageable    false = we deliberately do not build a package for it;
#                  `skipReason` explains why (surfaced in `nix eval` and CI).
#   needsAlsa / needsFfmpeg / needsXdgUtils
#                  wrapper inputs, to be *verified* per product in P1 by
#                  reading the binary's NEEDED + strings. Values below are the
#                  current best reading; only photocraft is verified.
#                  needsXdgUtils puts `xdg-open` (the `open` crate's backend)
#                  on PATH — xdg-utils drags a ~180 MB closure (perl, file,
#                  shared-mime-info, glib), which is why it is a flag rather
#                  than unconditional.
#   glibcFloor     upstream's `GLIBC_*` symbol floor. riscv64 assets need 2.39.
{
  photocraft = {
    owner = "storytold";
    repo = "photocraft";
    appId = "ai.storyteller.photocraft";
    assetPrefix = "photocraft";
    guiBin = "photocraft";
    cliBins = [ "photocraft-cli" ];
    summary = "Edit photos and layered PSD documents";
    description = "PhotoCraft: an open-source, clean-room reimplementation of Adobe Photoshop in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      # 2026-10-11, v0.7.0: tarball layout, app id, NEEDED list, GLIBC floor and
      # the lib-preflight soname set were all read off the real assets.
      atVersion = "0.7.0";
      runtime = true;
    };
  };

  lightcraft = {
    owner = "storytold";
    repo = "lightcraft";
    appId = "ai.storyteller.lightcraft";
    assetPrefix = "lightcraft";
    guiBin = "lightcraft";
    cliBins = [ "lightcraft-cli" ];
    summary = "Edit raw photos";
    description = "LightCraft: an open-source, clean-room reimplementation of Adobe Lightroom in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  filmcraft = {
    owner = "storytold";
    repo = "filmcraft";
    appId = "ai.storyteller.filmcraft";
    assetPrefix = "filmcraft";
    guiBin = "filmcraft";
    cliBins = [ "filmcraft-cli" ];
    summary = "Edit video";
    description = "FilmCraft: an open-source, clean-room reimplementation of Adobe Premiere Pro in pure Rust";
    license = "asl20";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    glibcFloor = "2.35";
    glibcFloorBySystem = {
      riscv64-linux = "2.39";
    };
    # Audio playback + codec transcoding; both to be confirmed from the binary.
    needsAlsa = true;
    needsFfmpeg = true;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  soundcraft = {
    owner = "storytold";
    repo = "soundcraft";
    appId = "ai.storyteller.soundcraft";
    assetPrefix = "soundcraft";
    guiBin = "soundcraft";
    cliBins = [ "soundcraft-cli" ];
    summary = "Record and mix audio";
    description = "SoundCraft: an open-source, clean-room reimplementation of Avid Pro Tools in pure Rust";
    license = "asl20";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    glibcFloor = "2.35";
    glibcFloorBySystem = {
      riscv64-linux = "2.39";
    };
    needsAlsa = true;
    needsFfmpeg = true;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  vectorcraft = {
    owner = "storytold";
    repo = "vectorcraft";
    appId = "ai.storyteller.vectorcraft";
    assetPrefix = "vectorcraft";
    guiBin = "vectorcraft";
    cliBins = [ "vectorcraft-cli" ];
    summary = "Draw vector graphics";
    description = "VectorCraft: an open-source, clean-room reimplementation of Adobe Illustrator in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  pdfcraft = {
    owner = "storytold";
    repo = "pdfcraft";
    appId = "ai.storyteller.pdfcraft";
    assetPrefix = "pdfcraft";
    guiBin = "pdfcraft";
    cliBins = [ "pdfcraft-cli" ];
    summary = "Read, annotate and export PDF documents";
    description = "PdfCraft: an open-source, clean-room reimplementation of Adobe Acrobat in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    # The only product that also ships standalone per-arch `<app>-cli-*`
    # tarballs; we ignore them because the GUI tarball already contains
    # bin/pdfcraft-cli. Recorded here so P1 does not "discover" it again.
    extraCliAssets = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  wordcraft = {
    owner = "storytold";
    repo = "wordcraft";
    appId = "ai.storyteller.wordcraft";
    assetPrefix = "wordcraft";
    guiBin = "wordcraft";
    cliBins = [ "wordcraft-cli" ];
    summary = "Write and format documents";
    description = "WordCraft: an open-source, clean-room reimplementation of Microsoft Word in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  gridcraft = {
    owner = "storytold";
    repo = "gridcraft";
    appId = "ai.storyteller.gridcraft";
    assetPrefix = "gridcraft";
    guiBin = "gridcraft";
    cliBins = [ "gridcraft-cli" ];
    summary = "Work with spreadsheets";
    description = "GridCraft: an open-source, clean-room spreadsheet (Microsoft Excel-style) in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  deckcraft = {
    owner = "storytold";
    repo = "deckcraft";
    appId = "ai.storyteller.deckcraft";
    assetPrefix = "deckcraft";
    guiBin = "deckcraft";
    cliBins = [ "deckcraft-cli" ];
    summary = "Make presentations";
    description = "DeckCraft: an open-source, clean-room reimplementation of Microsoft PowerPoint in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  cadcraft = {
    owner = "storytold";
    repo = "cadcraft";
    appId = "ai.storyteller.cadcraft";
    assetPrefix = "cadcraft";
    guiBin = "cadcraft";
    cliBins = [ "cadcraft-cli" ];
    summary = "Draft and design in 2D";
    description = "CADCraft: computer-aided design and drafting, an open-source clean-room AutoCAD-style app in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  designcraft = {
    owner = "storytold";
    repo = "designcraft";
    appId = "ai.storyteller.designcraft";
    assetPrefix = "designcraft";
    guiBin = "designcraft";
    cliBins = [ "designcraft-cli" ];
    summary = "Design interfaces";
    description = "DesignCraft: an open-source, clean-room UI design tool in pure Rust";
    license = "asl20";
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
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  effectcraft = {
    owner = "storytold";
    repo = "effectcraft";
    appId = "ai.storyteller.effectcraft";
    assetPrefix = "effectcraft";
    guiBin = "effectcraft";
    cliBins = [ "effectcraft-cli" ];
    summary = "Compose motion graphics and visual effects";
    description = "EffectCraft: an open-source, clean-room motion graphics and effects tool in pure Rust";
    license = "asl20";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    glibcFloor = "2.35";
    glibcFloorBySystem = {
      riscv64-linux = "2.39";
    };
    needsAlsa = true;
    needsFfmpeg = true;
    needsXdgUtils = true;
    packageable = true;
    skipReason = null;
    verified = {
      atVersion = null;
      runtime = false;
    };
  };

  # ArtCraft Launcher: browses and *installs/updates* Craft apps into user
  # state, and shells out to flatpak/apt/dnf/zypper. That is the one part of the
  # suite Nix must not hand over, so it is metadata-only until P3 decides
  # otherwise (see PLAN.md §4 P3, §5.3).
  craft-launcher = {
    owner = "storytold";
    repo = "craft-launcher";
    appId = null;
    assetPrefix = "artcraft-launcher";
    guiBin = null;
    cliBins = [ ];
    summary = "Browse, install and update the Craft apps";
    description = "ArtCraft Launcher: browse, install and update the Craft app suite";
    license = "asl20";
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    glibcFloor = "2.35";
    glibcFloorBySystem = { };
    needsAlsa = false;
    needsFfmpeg = false;
    needsXdgUtils = true;
    packageable = false;
    skipReason = "Self-updates apps into ~/.local/share and calls flatpak/apt/dnf/zypper; conflicts with a Nix-managed install. Revisit in P3.";
    verified = {
      atVersion = null;
      runtime = false;
    };
  };
}
