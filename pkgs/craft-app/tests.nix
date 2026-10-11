# Validation of the *upstream* desktop assets carried by the `desktop` output.
#
# This flake does not author .desktop or AppStream files, so the test is not
# "is our entry well-formed" but "did upstream ship something usable, and does
# its AppStream still describe the version we pinned". Both run offline: the
# network is only reached by `appstreamcli`'s URL check, which `--no-net` turns
# off (without it every product fails on https://getartcraft.com URLs).
{
  lib,
  runCommand,
  desktop-file-utils,
  appstream,
  gnugrep,
  coreutils,
  package,
  product,
  pins,
}:
let
  desktop = package.desktop;
  pin = pins.${product.repo};
in
{
  # Exit status of desktop-file-validate is the contract: 0 = no errors. Upstream
  # emits hints on two products (cadcraft's Categories, effectcraft's two main
  # categories), which are theirs to fix and not reasons to fail a Nix build.
  desktopEntry =
    runCommand "${product.repo}-desktop-entry-validate"
      {
        nativeBuildInputs = [
          desktop-file-utils
          gnugrep
        ];
      }
      ''
        found=0
        for f in ${desktop}/share/applications/*.desktop; do
          if [ ! -e "$f" ]; then
            echo "no desktop entry in the desktop output" >&2
            exit 1
          fi
          echo "== $(basename "$f")"
          desktop-file-validate "$f" || exit 1
          # The entry must launch the binary this package provides, and its icon id
          # must exist in the same output, or the menu shows a question mark.
          grep -q '^Exec=${product.guiBin}' "$f" || {
            echo "error: Exec does not start ${product.guiBin} (the package puts it on PATH)" >&2
            exit 1
          }
          icon="$(grep -m1 '^Icon=' "$f" | cut -d= -f2)"
          if [ -n "''${icon:-}" ] && [ "''${icon#*/}" = "$icon" ]; then
            ls ${desktop}/share/icons/hicolor/*/apps/"$icon".* >/dev/null 2>&1 || {
              echo "error: themed icon '$icon' is not shipped in the desktop output" >&2
              exit 1
            }
          fi
          found=$((found + 1))
        done
        [ "$found" -gt 0 ] || { echo "error: no .desktop files validated" >&2; exit 1; }
        echo "$found desktop entry/entries valid"
        touch "$out"
      '';

  # AppStream: schema-valid *and* the <release version> inside the tarball has to
  # equal the version pins.lock.json claims, i.e. upstream's own metadata agrees
  # with what we downloaded. A mismatch means the asset and the tag diverged.
  metainfo =
    runCommand "${product.repo}-metainfo-validate"
      {
        nativeBuildInputs = [
          appstream
          gnugrep
          coreutils
        ];
      }
      ''
        found=0
        for x in ${desktop}/share/metainfo/*.metainfo.xml; do
          if [ ! -e "$x" ]; then
            echo "no metainfo file in the desktop output" >&2
            exit 1
          fi
          echo "== $(basename "$x")"
          appstreamcli validate --no-net "$x" || exit 1
          grep -q '<release version="${pin.version}"' "$x" || {
            echo "error: ${product.repo} ${pin.tag} ships AppStream releases for a different version:" >&2
            grep -o '<release version="[^"]*"[^/>]*' "$x" >&2
            exit 1
          }
          id="$(grep -m1 -o '<id>[^<]*</id>' "$x" | sed 's#</\?id>##g')"
          if [ "$id" != "${product.appId}" ]; then
            echo "error: metainfo id '$id' is not the product's app id '${product.appId}'" >&2
            exit 1
          fi
          found=$((found + 1))
        done
        [ "$found" -gt 0 ] || { echo "error: no metainfo files validated" >&2; exit 1; }
        echo "$found metainfo file(s) valid for ${pin.version}"
        touch "$out"
      '';
}
