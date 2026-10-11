#!/bin/sh
# Static wrapper audit for every pinned Craft product: what the binary really
# links, dlopens and shells out to, so products.nix can carry a *minimal*
# per-product runtime list instead of guesses (PLAN §4 P1 acceptance).
set -u
cd "$(dirname "$0")/.."
export NIX_CONFIG="experimental-features = nix-command flakes"

products=$(nix eval --impure --raw --expr 'let j = builtins.fromJSON (builtins.readFile ./pins.lock.json); in builtins.concatStringsSep " " (builtins.attrNames j)')
for p in $products; do
  case "$p" in _*) continue ;; esac
  out=$(nix build --no-link --print-out-paths ".#$p" 2>/dev/null | tail -1)
  gui="$out/bin/.$p-wrapped"
  [ -f "$gui" ] || gui=$(ls "$out/bin"/.*-wrapped 2>/dev/null | head -1)
  echo "### $p"
  echo "  bins: $(ls "$out/bin" | grep -v '^\.' | tr '\n' ' ')"
  echo "  NEEDED: $(readelf -d "$gui" 2>/dev/null | grep NEEDED | grep -oE '\[lib[^]]*\]' | tr -d '[]' | tr '\n' ' ')"
  s=$(strings -a "$gui" 2>/dev/null)
  echo "  dlopen sonames: $(grep -ohE 'lib[A-Za-z0-9_.+-]*\.so(\.[0-9]+)*' <<<"$s" | sort -u | grep -vE '^libc|^libm|^libgcc|^ld-linux' | tr '\n' ' ')"
  echo "  audio stack: $(grep -ohiE 'libasound[a-z0-9._-]*|pipewire|libpulse[a-z0-9._-]*|alsa' <<<"$s" | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')"
  echo "  codec cmds: $(grep -ohE '\b(ffmpeg|ffprobe|magick|gs|inkscape|soffice|libreoffice|unzip|flatpak|zypper|dnf|apt)\b' <<<"$s" | sort -u | tr '\n' ' ')"
  P=$(printf '%s' "$p" | tr 'a-z' 'A-Z')
  echo "  app env: $(grep -ohE "${P}_[A-Z0-9_]+|${P}SKIP[A-Z_]*" <<<"$s" | sort -u | tr '\n' ' ')"
  echo "  desktop: $(ls "$out/share/applications" 2>/dev/null | tr '\n' ' ')"
done
