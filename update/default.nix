# Rewrites pins.lock.json from GitHub's release checksums. No Nix build is
# involved: `SHA256SUMS.txt` gives base16 sha256 for every asset, `nix hash
# convert` turns it into SRI, and jq writes the lock file.
#
#   nix run .#update                         # products already in pins.lock.json
#   nix run .#update -- photocraft lightcraft # explicit products
#   nix run .#update -- --all                 # every packageable product
#   nix run .#update -- --dry-run             # show the diff, write nothing
#   nix run .#update -- --verify photocraft   # nix build afterwards
#
# Failure policy (PLAN §3.3): a missing asset for a supported system is a hard
# error that prints what the release *did* contain, because the launcher's
# `artcraft-launcher-*` prefix showed upstream does rename assets.
{
  writeShellApplication,
  nix,
  curl,
  jq,
  coreutils,
  gnugrep,
  gnused,
}:
writeShellApplication {
  name = "craft-update-pins";
  runtimeInputs = [
    nix
    curl
    jq
    coreutils
    gnugrep
    gnused
  ];

  text = ''
    usage() {
      printf '%s\n' \
        "Rewrites pins.lock.json from the Craft releases' SHA256SUMS.txt." \
        "" \
        "  nix run .#update                          # products already pinned" \
        "  nix run .#update -- photocraft lightcraft  # explicit products" \
        "  nix run .#update -- --all                 # every packageable product" \
        "  nix run .#update -- --dry-run             # show the diff, write nothing" \
        "  nix run .#update -- --verify photocraft   # nix build afterwards"
    }

    export NIX_CONFIG="experimental-features = nix-command flakes"

    ROOT="''${CRAFT_REPO_DIR:-$PWD}"
    PRODUCTS_FILE="''${CRAFT_PRODUCTS_FILE:-$ROOT/products.nix}"
    PINS_FILE="''${CRAFT_PINS_FILE:-$ROOT/pins.lock.json}"

    DRY_RUN=0
    VERIFY=0
    ALLOW_DOWNGRADE=0
    ALL=0
    TARGETS=()

    for arg in "$@"; do
      case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --verify) VERIFY=1 ;;
        --allow-downgrade) ALLOW_DOWNGRADE=1 ;;
        --all) ALL=1 ;;
        -h|--help)
          usage
          exit 0
          ;;
        --*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
        *) TARGETS+=("$arg") ;;
      esac
    done

    [[ -f "$PRODUCTS_FILE" ]] || { echo "error: no products.nix in $ROOT" >&2; exit 1; }
    if [[ ! -f "$PINS_FILE" ]]; then
      echo '{}' > "$PINS_FILE"
    fi

    # products.nix as data: repo -> metadata.
    PRODUCTS_JSON="$(nix eval --impure --raw --expr "builtins.toJSON (import $PRODUCTS_FILE)")"
    PINS_JSON="$(jq -S . "$PINS_FILE")"

    if [[ ''${#TARGETS[@]} -eq 0 ]]; then
      if [[ "$ALL" == 1 ]]; then
        mapfile -t TARGETS < <(
          jq -r 'to_entries[] | select(.value.packageable) | .key' <<< "$PRODUCTS_JSON"
        )
      else
        # Default: keep the pins we already ship fresh. Adopting a new product
        # is an explicit act (P0 ships photocraft only).
        mapfile -t TARGETS < <(jq -r 'keys[] | select(startswith("_") | not)' <<< "$PINS_JSON")
      fi
    fi

    [[ ''${#TARGETS[@]} -gt 0 ]] || { echo "error: nothing to do; pins.lock.json is empty" >&2; exit 1; }

    CHANGED=0
    NEW_PINS="$PINS_JSON"
    REPORT=()

    for name in "''${TARGETS[@]}"; do
      product="$(jq --arg n "$name" '.[$n] // empty' <<< "$PRODUCTS_JSON")"
      if [[ -z "$product" ]]; then
        echo "error: '$name' is not in products.nix" >&2
        exit 1
      fi
      packageable="$(jq -r '.packageable' <<< "$product")"
      if [[ "$packageable" != "true" ]]; then
        echo "error: '$name' is marked packageable = false:" >&2
        jq -r '"  " + (.skipReason // "no reason given")' <<< "$product" >&2
        exit 1
      fi

      owner="$(jq -r '.owner' <<< "$product")"
      repo="$(jq -r '.repo' <<< "$product")"
      prefix="$(jq -r '.assetPrefix' <<< "$product")"
      mapfile -t systems < <(jq -r '.systems[]' <<< "$product")
      api="https://api.github.com/repos/$owner/$repo"
      base="$owner/$repo"

      echo "==> $name"

      # Tag + date: the API is a convenience, releases.atom is the fallback so a
      # rate limit does not look like an upstream problem.
      latest="$(curl -fsSL "$api/releases/latest" 2>/dev/null || true)"
      tag="$(jq -r '.tag_name // empty' <<< "$latest" 2>/dev/null || true)"
      date="$(jq -r '.published_at // empty' <<< "$latest" 2>/dev/null || true)"
      if [[ -z "$tag" ]]; then
        echo "    (GitHub API unusable, falling back to releases.atom)"
        atom="$(curl -fsSL "https://github.com/$base/releases.atom")"
        tag="$(grep -m1 -oE 'releases/tag/[A-Za-z0-9._+-]+' <<< "$atom" | head -1 | sed 's#.*/##')"
        date="$(grep -m2 '<updated>' <<< "$atom" | tail -1 | sed -E 's#</?updated>##g' | tr -d ' ')"
      fi
      [[ -n "$tag" ]] || { echo "error: cannot resolve the latest release tag for $base" >&2; exit 1; }
      version="''${tag#v}"
      [[ -n "$date" ]] || { echo "error: cannot resolve the release date for $base $tag" >&2; exit 1; }
      date="''${date%%T*}"

      old_version="$(jq -r --arg n "$name" '.[$n].version // empty' <<< "$PINS_JSON")"
      if [[ -n "$old_version" && "$old_version" != "$version" ]]; then
        lower="$(printf '%s\n%s\n' "$old_version" "$version" | sort -V | head -1)"
        if [[ "$lower" == "$version" && "$ALLOW_DOWNGRADE" != 1 ]]; then
          echo "error: refusing to downgrade $name $old_version -> $version (use --allow-downgrade)" >&2
          exit 1
        fi
      fi
      echo "    tag $tag  version $version  date $date"

      sums="$(curl -fsSL "https://github.com/$base/releases/download/$tag/SHA256SUMS.txt")" \
        || { echo "error: $base $tag has no SHA256SUMS.txt" >&2; exit 1; }
      sums_lines="$(grep -cE '^[0-9a-f]{64}  ' <<< "$sums")"
      [[ "$sums_lines" -gt 0 ]] || { echo "error: SHA256SUMS.txt for $base $tag is empty or malformed" >&2; exit 1; }

      entry='{}'
      for system in "''${systems[@]}"; do
        arch="''${system%-linux}"
        asset="$prefix-$version-linux-$arch.tar.gz"
        line="$(grep -E "^[0-9a-f]{64}  $asset\$" <<< "$sums" || true)"
        if [[ -z "$line" ]]; then
          echo "error: $base $tag has no $asset" >&2
          echo "       linux tarballs in this release:" >&2
          grep -oE '[A-Za-z0-9._+-]*-linux-[A-Za-z0-9_]+\.tar\.gz' <<< "$sums" | sed 's/^/         /' >&2
          echo "       (SHA256SUMS.txt lists $sums_lines assets)" >&2
          exit 1
        fi
        base16="''${line%% *}"
        sri="$(nix hash convert --hash-algo sha256 --to sri "$base16")"
        url="https://github.com/$base/releases/download/$tag/$asset"
        entry="$(
          jq --arg s "$system" --arg arch "$arch" --arg name "$asset" --arg url "$url" \
            --arg sri "$sri" --arg b16 "$base16" --arg line "$line" \
            '.[$s] = { arch: $arch, name: $name, url: $url, sha256: $sri, sha256Base16: $b16, sumsLine: $line }' \
            <<< "$entry"
        )"
        echo "    $system  $sri"
      done

      candidate="$(
        jq -S -n --arg n "$name" --arg tag "$tag" --arg version "$version" --arg date "$date" \
          --arg sums "https://github.com/$base/releases/download/$tag/SHA256SUMS.txt" \
          --argjson entry "$entry" \
          '{ repo: $n, version: $version, tag: $tag, releaseDate: $date,
             checksumsUrl: $sums, systems: $entry }'
      )"
      # refreshedAt is only a "when did we last look" marker: keep the old one
      # unless something real changed, so a no-op run has an empty diff.
      old_stored="$(jq -S --arg n "$name" '.[$n] | del(.refreshedAt) // empty' <<< "$PINS_JSON")"
      stamp="$(jq --arg n "$name" -r '.[$n].refreshedAt // empty' <<< "$PINS_JSON")"
      if [[ "$candidate" != "$old_stored" || -z "$stamp" ]]; then
        stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      fi
      NEW_PINS="$(
        jq --arg n "$name" --argjson pin "$candidate" --arg now "$stamp" \
          '.[$n] = ($pin + { refreshedAt: $now })' <<< "$NEW_PINS"
      )"

      if [[ -z "$old_version" ]]; then
        REPORT+=("+ $name $version")
        CHANGED=1
      elif [[ "$old_version" != "$version" ]]; then
        REPORT+=("~ $name $old_version -> $version")
        CHANGED=1
      elif [[ "$candidate" != "$old_stored" ]]; then
        REPORT+=("= $name $version (checksums changed)")
        CHANGED=1
      else
        REPORT+=("  $name $version unchanged")
      fi
    done

    # Stable key order so a bump diffs on one line per field, not the whole file.
    NEW_PINS="$(jq -S . <<< "$NEW_PINS")"

    echo
    printf '%s\n' "''${REPORT[@]}"

    if [[ "$DRY_RUN" == 1 ]]; then
      echo
      echo "--- pins.lock.json (current)"
      echo "+++ pins.lock.json (proposed)"
      diff -u <(jq -S 'del(."._comment")' <<< "$PINS_JSON") <(
        jq -S 'del(."._comment")' <<< "$NEW_PINS"
      ) || true
      echo
      echo "dry run: nothing written"
      exit 0
    fi

    jq -S . <<< "$NEW_PINS" > "$PINS_FILE.tmp" && mv "$PINS_FILE.tmp" "$PINS_FILE"
    echo "wrote $PINS_FILE"

    if [[ "$VERIFY" == 1 ]]; then
      for name in "''${TARGETS[@]}"; do
        echo "==> building .#$name"
        (cd "$ROOT" && nix build --no-link ".#$name")
      done
    fi

    if [[ "$CHANGED" == 1 ]]; then
      echo
      echo "Commit it:  git add $(basename "$PINS_FILE") && git commit -m 'craft: update release pins'"
    fi
  '';
}
