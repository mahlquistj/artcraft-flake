# Eval-only regression test for the prebuilt Craft packages.
#
# Every product is evaluated for every architecture upstream publishes Linux
# tarballs for (including riscv64, which nothing on this machine can build) and
# the invariants that products.nix, pins.lock.json and pkgs/craft-app must agree
# on are checked at *eval* time — no network, no download, no store.
#
#   nix build .#checks.x86_64-linux.prebuilt-eval     # green == coherent
#   nix eval --raw .#prebuilt-eval-table             # the validated table
#   nix eval --raw .#prebuilt-eval-pins              # pins.lock.json as JSON
#
# A violation is a `throw`: it cannot be missed by skipping the build, and CI
# sees the message rather than a test binary's exit code.
{
  lib,
  runCommand,
  products,
  pins,
  systems,
  craftDrvFor,
}:
let
  inherit (lib)
    concatStringsSep
    filter
    flatten
    hasInfix
    hasPrefix
    mapAttrsToList
    optionalString
    ;

  # `_comment`/`_upstream` keys in pins.lock.json are prose for humans, not pins.
  publishedPins = lib.filterAttrs (n: _v: !hasPrefix "_" n) pins;

  # One row per (system, published product), carrying both the derivation's
  # view and the pin's view so the checks below can compare them.
  rows = flatten (
    map (
      system:
      mapAttrsToList (
        name: drv:
        let
          pin = publishedPins.${name};
          asset = pin.systems.${system};
        in
        (builtins.removeAttrs drv.passthru [
          "product"
          "pins"
          "asset"
          "runtimeLibs"
          "runtimeBins"
        ])
        // {
          inherit system name drv;
          version = drv.version;
          mainProgram = drv.meta.mainProgram;
          platforms = drv.meta.platforms;
          provenance = drv.meta.sourceProvenance;
          broken = drv.meta.broken or false;
          license = drv.meta.license.spdxId or "unknown";
          inherit asset;
        }
      ) (craftDrvFor system)
    ) systems
  );

  describe = r: "${r.name}/${r.system}";

  rowProblems =
    r:
    let
      product = products.${r.name};
      expectAsset = "${product.assetPrefix}-${r.version}-linux-${r.asset.arch}.tar.gz";
    in
    filter (s: s != "") [
      (optionalString (
        !(lib.elem r.system product.systems)
      ) "${describe r}: products.nix does not list this system")
      (optionalString (
        !product.packageable
      ) "${describe r}: products.nix says not packageable, yet a package is published")
      (optionalString (
        r.tag != "v${r.version}"
      ) "${describe r}: tag ${r.tag} disagrees with version ${r.version}")
      (optionalString (
        r.asset.name != expectAsset
      ) "${describe r}: pinned asset '${r.asset.name}' is not the expected '${expectAsset}")
      (optionalString (
        !(hasInfix r.asset.name r.asset.url)
      ) "${describe r}: the pinned URL does not contain the asset name")
      (optionalString (
        !(hasInfix r.tag r.asset.url)
      ) "${describe r}: the pinned URL does not contain the tag ${r.tag}")
      (optionalString (
        !(hasPrefix "sha256-" r.asset.sha256)
      ) "${describe r}: sha256 '${r.asset.sha256}' is not an SRI hash")
      (optionalString (
        !(hasInfix r.asset.name r.asset.sumsLine)
      ) "${describe r}: upstream's SHA256SUMS line does not mention ${r.asset.name}")
      (optionalString (
        !(lib.elem r.mainProgram r.allPrograms)
      ) "${describe r}: mainProgram '${r.mainProgram}' is not a binary of the tarball")
      (optionalString (
        !(lib.elem r.system r.platforms)
      ) "${describe r}: meta.platforms excludes the system we publish it for")
      (optionalString (
        r.provenance != [ lib.sourceTypes.binaryNativeCode ]
      ) "${describe r}: sourceProvenance must be binaryNativeCode (these are upstream ELF files)")
      (optionalString r.broken "${describe r}: the builder marks this broken (needs glibc >= ${r.glibcFloor})")
    ];

  pinProblems = flatten (
    mapAttrsToList (
      name: pin:
      filter (s: s != "") [
        (optionalString (!(products ? ${name})) "pins.lock.json has '${name}', products.nix does not")
        (optionalString (
          (products ? ${name})
          && pin.systems != { }
          &&
            builtins.length (filter (s: !lib.elem s products.${name}.systems) (builtins.attrNames pin.systems))
            > 0
        ) "pins.lock.json '${name}' has systems products.nix does not list")
      ]
    ) publishedPins
  );

  problems = flatten (map rowProblems rows) ++ pinProblems;

  table = concatStringsSep "\n" (
    map (
      r: "${r.system}\t${r.name}\t${r.version}\t${r.asset.arch}\t${r.asset.name}\t${r.asset.sha256}"
    ) rows
  );
in
if problems != [ ] then
  throw ''
    craft prebuilt-eval found ${builtins.toString (builtins.length problems)} problem(s):
    ${concatStringsSep "\n" problems}
  ''
else
  runCommand "craft-prebuilt-eval"
    {
      rows = table;
      passAsFile = [ "rows" ];
      meta = {
        description = "Eval-only consistency check: products.nix vs pins.lock.json vs pkgs/craft-app";
        platforms = systems;
      };
    }
    ''
      mkdir -p "$out/bin"
      install -m644 "$rowsPath" "$out/rows.tsv"
      printf '#!/bin/sh\necho "craft prebuilt-eval: %s product/system rows consistent"\n' \
        '${builtins.toString (builtins.length rows)}' > "$out/bin/check"
      chmod +x "$out/bin/check"
      "$out/bin/check"
    ''
