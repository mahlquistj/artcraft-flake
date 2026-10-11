# Shared half of the Craft modules: the option declarations and the enabled-set
# computation, identical for NixOS and home-manager. Only the *installation*
# differs (environment.systemPackages vs home.packages), which each module does
# itself.
#
# Used as `import ./craft-options.nix { inherit lib pkgs; }` — it reads
# products.nix and pins.lock.json from the flake source, so a module works with
# or without the flake's overlay applied to the package set.
#
# Rule this file exists to enforce: **option keys must not depend on `pkgs`.**
# A NixOS module gets `pkgs` from `_module.args`, which is a *config* value
# (`nixpkgs.pkgs`), so forcing it while building the option namespace recurses.
# Defaults may reference pkgs — those thunks are forced at merge time — hence
# `names` below comes from products.nix + pins.lock.json only.
{ lib, pkgs }:
let
  products = import ../products.nix;
  pins = builtins.fromJSON (builtins.readFile ../pins.lock.json);

  # Published here = packageable and pinned at all. A product pinned only for
  # other systems still gets options; its default package then fails with the
  # builder's "pins.lock.json has no <system> asset" message, which beats a
  # silently missing option.
  names = lib.attrNames (
    lib.filterAttrs (
      _n: product: product.packageable && builtins.hasAttr "systems" (pins.${product.repo} or { })
    ) products
  );

  system = pkgs.stdenv.hostPlatform.system;

  craftPackagesFor = import ../pkgs/craft-suite.nix { inherit lib; } {
    inherit products pins;
  };

  # The same derivations the overlay publishes, computed directly so a module
  # without our overlay still works.
  generatedFor =
    sys:
    craftPackagesFor {
      pkgs = pkgs;
      system = sys;
    };

  optionFor =
    name:
    let
      product = products.${name};
    in
    {
      enable = lib.mkEnableOption product.description;

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.${name} or (generatedFor system).${name};
        defaultText = lib.literalExpression "pkgs.${name}";
        description = "The ${name} derivation to use.";
      };

      enableDesktopEntry = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to install ${name}'s menu integration: the `.desktop` entry,
          hicolor icons, mime types and AppStream metainfo. These are upstream's
          files, shipped in the release tarball and exposed as the package's
          `desktop` output — set this to `false` to keep the binary (and its
          CLI) off the application menu.
        '';
      };
    };

  enabledFor =
    programs:
    lib.filter (e: e.cfg.enable) (
      map (name: {
        inherit name;
        cfg = programs.${name};
        product = products.${name};
      }) names
    );
in
{
  inherit
    products
    pins
    names
    system
    enabledFor
    generatedFor
    ;

  # programs.<app>.{enable,package,enableDesktopEntry} for every pinned product.
  productOptions = lib.genAttrs names optionFor;

  # programs.crafts.enable = [ "photocraft" "filmcraft" ]; — a convenience list
  # that turns the individual modules on. Unknown or unpinned names are a type
  # error, not a silent no-op.
  suiteOption = {
    enable = lib.mkOption {
      type = with lib.types; listOf (enum names);
      default = [ ];
      example = [
        "photocraft"
        "filmcraft"
      ];
      description = ''
        List of Craft apps to enable. Equivalent to setting
        {option}`programs.<app>.enable` for each one; the names are the products
        this flake pins, so a typo is an evaluation error rather than a silent
        skip.
      '';
    };
  };

  # `programs.crafts.enable = [ … ]` turns those apps on. Keys come from the
  # static product list: deriving config attribute *names* from another config
  # value makes the module system's definition push-down recurse. mkDefault so an
  # explicit `programs.<app>.enable = false` still wins.
  suiteEnable = programs: {
    programs = lib.genAttrs names (name: {
      enable = lib.mkIf (lib.elem name programs.crafts.enable) (lib.mkDefault true);
    });
  };

  # Each enabled product's packages: the binary output, plus the desktop output
  # when asked for. Neither module relies on multi-output handling in buildEnv —
  # NixOS's system profile and home-manager's user environment both link only the
  # default output, so `desktop` has to be its own entry.
  packagesOf =
    entry:
    [ entry.cfg.package ] ++ lib.optionals entry.cfg.enableDesktopEntry [ entry.cfg.package.desktop ];

  # Portal reminder, phrased per system by the caller (NixOS has a portal
  # *service*, home-manager's xdg.portal only writes per-user config).
  portalWarning = enabled: ''
    The Craft apps (${lib.concatMapStringsSep ", " (e: e.name) enabled}) open files,
    save documents and pick colours through xdg-desktop-portal (they embed an rfd
    portal client and need libdbus, which the wrapper provides). Without a running
    portal the apps start normally but Open/Save dialogs and the colour picker
    fail at click time.
  '';

  # Products whose builder refused the platform (glibc floor, non-Linux). The
  # message is the builder's own reason, so there is exactly one source of truth
  # about why a release will not run here.
  unsupportedAssertions =
    enabled:
    map (entry: {
      assertion = entry.cfg.package.passthru.unsupportedReason or null == null;
      message = ''
        programs.${entry.name}.enable: the pinned ${entry.product.repo} release
        ${entry.cfg.package.passthru.tag or "?"} will not run on ${system} —
        ${entry.cfg.package.passthru.unsupportedReason}. Use a nixpkgs with a
        newer glibc (this product needs >= ${entry.cfg.package.passthru.glibcFloor})
        or disable the module.
      '';
    }) enabled;
}
