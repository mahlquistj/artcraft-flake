# Local guard for the GitHub workflows, wired in as `checks.<system>.workflows`.
#
# The first CI run died on `cachix/install-nix-action@V31` — a tag that does not
# exist (upstream's are lowercase: v31.11.1). Nothing in `nix flake check` looks at
# YAML, so that class of mistake only surfaced after a push. This makes it local:
#
#   1. every workflow parses as YAML and declares `jobs:`,
#   2. every `uses:` step is pinned to a full 40-char commit SHA, so a moving tag
#      or a mistyped version cannot silently reach CI,
#   3. there is at least one workflow, so renaming .github/ does not disable the
#      check by accident.
#
# Deliberately text-based (`grep`), not parser-based: `on:` is a YAML 1.1 boolean
# in some parsers (PyYAML resolves it to `true`), which would make a `.on.schedule`
# lookup quietly return nothing. `uses:` lines have no such problem.
{
  runCommand,
  yq,
  gnugrep,
  coreutils,
  gawk,
  src,
}:
runCommand "craft-workflows-check"
  {
    nativeBuildInputs = [
      yq
      gnugrep
      gawk
      coreutils
    ];
    inherit src;
  }
  ''
    set -eu
    fail=0
    found=0

    for f in "$src"/workflows/*.yml; do
      [ -e "$f" ] || continue
      found=$((found + 1))
      echo "== $(basename "$f")"

      if ! yq -e '.' "$f" >/dev/null 2>&1; then
        echo "   error: $f is not valid YAML" >&2
        fail=1
        continue
      fi

      grep -q '^jobs:' "$f" || {
        echo "   error: $f has no top-level jobs: key" >&2
        fail=1
      }

      # Every uses: ref must be owner/repo@<40 hex> (or a local ./ action).
      grep -E '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' "$f" \
        | sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]#.*$//' \
        | while IFS= read -r ref; do
            case "$ref" in
              ./*)
                echo "   local action: $ref"
                continue
                ;;
            esac
            path="''${ref%%@*}"
            rev="''${ref#*@}"
            if [ "$path" = "$ref" ]; then
              echo "   error: '$ref' has no @ref" >&2
              exit 1
            fi
            if ! printf '%s' "$rev" | grep -Eq '^[0-9a-f]{40}$'; then
              echo "   error: '$ref' is not a full commit sha" >&2
              echo "          resolve one with:" >&2
              echo "          curl -s https://api.github.com/repos/$path/git/ref/tags/<tag> | jq -r .object.sha" >&2
              exit 1
            fi
            echo "   pinned: $path @ $rev"
          done || fail=1
    done

    [ "$found" -gt 0 ] || { echo "error: no workflows found under $src" >&2; exit 1; }
    [ "$fail" -eq 0 ] || { echo "workflow check failed" >&2; exit 1; }
    echo "$found workflow file(s) valid, all uses: refs pinned to commit shas"
    touch "$out"
  ''
