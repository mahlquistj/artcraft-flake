{
  writeShellApplication,
  nix,
  git,
  curl,
  jq,
  coreutils,
  gnugrep,
  gnused,
}:
let
  pins = import ./pins.nix;
in
writeShellApplication {
  name = "artcraft-update-pins";
  runtimeInputs = [
    nix
    git
    curl
    jq
    coreutils
    gnugrep
    gnused
  ];

  # Rewrites pins.nix: rev, date, version, srcHash, cargoHash.
  #
  # Hashes are never computed by hand. Nix's fixed-output fetches fail with
  # "specified: <fake> / got: <real>", so each stage runs `nix build .#artcraft`
  # with a deliberately wrong hash and scrapes the real one out of the error.
  # pins.nix is regenerated from shell variables after every stage.
  #
  # Usage, from the flake checkout:
  #   nix run .#update-pins                            # HEAD of pins.branch (main)
  #   ARTCRAFT_REF=artcraft-v0.41.0 nix run .#update-pins
  #   ARTCRAFT_REV=<full-sha> nix run .#update-pins
  #   nix run .#update-pins -- /path/to/this/checkout
  #
  # Exit status 0 means the resulting pins build cleanly. Non-zero leaves
  # pins.nix pointing at an unverified rev: `git checkout pins.nix` to back out.
  text = ''
    OWNER="${pins.owner}"
    REPO="${pins.repo}"
    REPO_URL="https://github.com/$OWNER/$REPO"
    API="https://api.github.com/repos/$OWNER/$REPO"
    FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    # Flakes must work even when the user has them disabled globally.
    export NIX_CONFIG="experimental-features = nix-command flakes"

    cd "''${1:-$PWD}"
    if [[ ! -f pins.nix || ! -f flake.nix ]]; then
      echo "error: run this inside the artcraft-flake checkout (need pins.nix + flake.nix)" >&2
      exit 1
    fi

    # Values we cannot always recompute: keep whatever is pinned now.
    PINS_JSON="$(nix eval --impure --raw --expr 'builtins.toJSON (import ./pins.nix)')"
    BRANCH="$(jq -r '.branch' <<< "$PINS_JSON")"
    VERSION="$(jq -r '.version' <<< "$PINS_JSON")"
    CARGO_HASH="$(jq -r '.cargoHash' <<< "$PINS_JSON")"

    REV="''${ARTCRAFT_REV:-}"
    REF="''${ARTCRAFT_REF:-}"
    DATE="''${ARTCRAFT_DATE:-}"
    SRC_HASH="$FAKE_HASH"
    BUILD_LOG=""
    BUILD_RC=0
    BUILD_GOT=""

    write_pins() {
      {
        printf '# Source pins for the ArtCraft build. Rewritten by: nix run .#update-pins\n'
        printf '#\n'
        printf '# Why a commit on main and not a release tag?\n'
        printf '#   The GitHub releases ship only macOS (.dmg / .app.tar.gz) and Windows\n'
        printf '#   (.exe / .msi) assets, and no release tag contains the artcraft-native\n'
        printf '#   crate, so we pin a commit on the default branch.\n'
        printf '{\n'
        printf '  owner = "%s";\n' "$OWNER"
        printf '  repo = "%s";\n' "$REPO"
        printf '  branch = "%s";\n' "$BRANCH"
        printf '  rev = "%s";\n' "$REV"
        printf '  date = "%s";\n' "$DATE"
        printf '  version = "%s";\n' "$VERSION"
        printf '  srcHash = "%s";\n' "$SRC_HASH"
        printf '  cargoHash = "%s";\n' "$CARGO_HASH"
        printf '}\n'
      } > pins.nix
    }

    # Build with the pins on disk. Sets BUILD_RC, BUILD_LOG and BUILD_GOT (the
    # "got: sha256-..." hash of a mismatched fixed-output fetch, when applicable).
    attempt_build() {
      if BUILD_LOG="$(nix build --no-link .#artcraft 2>&1)"; then
        BUILD_RC=0
      else
        BUILD_RC=1
      fi
      BUILD_GOT="$(printf '%s' "$BUILD_LOG" \
        | grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' \
        | tail -1 | sed -E 's/got:[[:space:]]*//')"
    }

    # Handle one fetch stage: force a wrong hash, take the real one from nix.
    # $1 = variable name to update, $2 = human label.
    resolve_hash() {
      local -n target="$1"
      local label="$2"
      write_pins
      attempt_build
      if [[ "$BUILD_RC" -eq 0 ]]; then
        echo "    ($label: pinned hash still matches)"
      elif [[ -z "$BUILD_GOT" ]]; then
        echo "error: the build failed before reporting a $label hash:" >&2
        printf '%s\n' "$BUILD_LOG" >&2
        exit 1
      else
        target="$BUILD_GOT"
        write_pins
        echo "    $label = $target"
      fi
    }

    echo "==> resolving upstream rev"
    if [[ -z "$REV" ]]; then
      REF="''${REF:-$BRANCH}"
      REV="$(git ls-remote "$REPO_URL" "refs/heads/$REF" "refs/tags/$REF" | cut -f1 | head -1)"
      if [[ ! "$REV" =~ ^[0-9a-f]{40}$ ]]; then
        echo "error: could not resolve a full commit sha from '$REF'" >&2
        exit 1
      fi
      echo "    ref = $REF"
    fi
    if [[ ! "$REV" =~ ^[0-9a-f]{40}$ ]]; then
      echo "error: ARTCRAFT_REV must be a full 40-char commit sha, got: $REV" >&2
      exit 1
    fi

    if [[ -z "$DATE" ]]; then
      DATE="$(curl -fsSL "$API/commits/$REV" | jq -r '.commit.committer.date // empty' | cut -dT -f1)"
      [[ -n "$DATE" ]] || DATE="$(date -u +%Y-%m-%d)"
    fi
    echo "    rev  = $REV"
    echo "    date = $DATE"

    # Crate version straight from the pinned commit (no store round-trip needed).
    NEW_VERSION="$(curl -fsSL "https://raw.githubusercontent.com/$OWNER/$REPO/$REV/artcraft-native/Cargo.toml" \
      | grep -m1 -E '^version' | tr -d '"' | sed -E 's/version[[:space:]]*=[[:space:]]*//')"
    if [[ -n "$NEW_VERSION" ]]; then
      VERSION="$NEW_VERSION"
      echo "    version = $VERSION"
    else
      echo "    warning: cannot read artcraft-native/Cargo.toml; keeping version $VERSION" >&2
    fi

    echo "==> stage 1: srcHash"
    SRC_HASH="$FAKE_HASH"
    resolve_hash SRC_HASH srcHash

    echo "==> stage 2: cargoHash (vendors the workspace lockfile)"
    CARGO_HASH="$FAKE_HASH"
    resolve_hash CARGO_HASH cargoHash

    echo "==> verifying: nix build .#artcraft"
    if ! nix build --no-link .#artcraft; then
      echo "error: the build failed at rev $REV; pins.nix still points at it." >&2
      echo "       Back out with 'git checkout pins.nix', or re-run as" >&2
      echo "         ARTCRAFT_REV=<sha> nix run .#update-pins" >&2
      exit 1
    fi

    echo "==> pins.nix now reads:"
    grep -E '^  (branch|rev|date|version|srcHash|cargoHash) =' pins.nix
    echo
    echo "Commit it:  git add pins.nix && git commit -m 'artcraft: update to $DATE'"
  '';
}
