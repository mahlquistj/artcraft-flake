# The Craft app suite as a Nix flake: prebuilt binary apps driven by
# pkgs/craft-app + products.nix + pins.lock.json, plus ArtCraft, which has no
# Linux release assets and therefore stays a source build (pkgs/artcraft.nix).
{
  description = "Craft app suite (PhotoCraft, FilmCraft, …) and ArtCraft, packaged for Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux is what this flake is built and run on; aarch64-linux is
      # evaluated (see `nix flake show`/checks) but not exercised here.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Every architecture upstream publishes Linux tarballs for. Used by the
      # eval-only check, so a riscv64 pin break is caught on an x86_64 builder.
      craftSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
      ];

      forAllSystems = lib.genAttrs supportedSystems;

      products = import ./products.nix;
      pins = builtins.fromJSON (builtins.readFile ./pins.lock.json);
      craftPackagesFor = import ./pkgs/craft-suite.nix { inherit lib; } {
        inherit products pins;
      };

      # Package sets without the flake's own overlay: the Craft packages do not
      # depend on anything the overlay adds, so generating them here (instead of via
      # `final`) avoids the stdenv recursion while producing identical derivations.
      barePkgs = system: import nixpkgs { inherit system; };

      craftOf =
        system:
        craftPackagesFor {
          pkgs = barePkgs system;
          inherit system;
        };

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

      suiteOf =
        system:
        let
          pkgs = pkgsFor system;
          # Both outputs: the runnable binaries and upstream's menu integration.
          paths = lib.flatten (
            map (p: [
              p.out
              p.desktop
            ]) (lib.attrValues (craftOf system))
          );
        in
        if paths == [ ] then
          null
        else
          pkgs.symlinkJoin {
            name = "craft-suite";
            inherit paths;
          };

      nixFiles = lib.fileset.unions [
        ./flake.nix
        ./pins.nix
        ./products.nix
        ./pkgs
        ./update
        ./modules
        ./tests
      ];

      appFor = p: {
        type = "app";
        program = lib.getExe p;
        meta = {
          inherit (p.meta) description;
          mainProgram = p.meta.mainProgram;
        };
      };

      artcraftApp =
        system:
        appFor (pkgsFor system).artcraft
        // {
          meta.description = "Run the ArtCraft desktop app";
        };
    in
    {
      # The data the packages are generated from, re-usable by other flakes and CI:
      #   nix eval --json .#products | jq 'keys'
      inherit products pins;

      # Adds `artcraft` plus every pinned Craft app to any package set, for
      # installing through an overlay (home-manager, NixOS `nixpkgs.overlays`, ...).
      overlays.default =
        final: prev:
        {
          artcraft = final.callPackage ./pkgs/artcraft.nix { };
        }
        // craftPackagesFor {
          pkgs = prev;
          system = prev.stdenv.hostPlatform.system;
        };

      # NixOS: `programs.artcraft.enable = true;` (the source build).
      nixosModules.artcraft = import ./modules/nixos.nix;

      # NixOS: `programs.<app>.enable` per Craft app, plus
      # `programs.crafts.enable = [ … ]` and the xdg-desktop-portal warning.
      nixosModules.crafts = import ./modules/crafts.nix;

      # Both, for `imports = [ craft.nixosModules.default ];`. A module *list* is
      # itself a valid module: the module system flattens `imports`, while
      # lib.mkMerge refuses to merge module lists ("cannot append list").
      nixosModules.default = [
        self.nixosModules.artcraft
        self.nixosModules.crafts
      ];

      # home-manager: `programs.artcraft.enable = true;`
      homeModules.artcraft = import ./modules/home-manager.nix;
      # home-manager: the same generated `programs.<app>` API as NixOS.
      homeModules.crafts = import ./modules/crafts-home-manager.nix;

      # Both, as above.
      homeModules.default = [
        self.homeModules.artcraft
        self.homeModules.crafts
      ];

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          suite = suiteOf system;
        in
        (craftOf system)
        // lib.optionalAttrs (suite != null) { craft-suite = suite; }
        // {
          artcraft = pkgs.artcraft;
          # `default` stays the source build: `nix build .` pulling in every Craft
          # app would be a gigabyte of prebuilt ELFs, so craft-suite is opt-in.
          default = pkgs.artcraft;

          # Rewrites pins.nix (rev, date, version, srcHash, cargoHash) and
          # verifies the build. Usage: nix run .#update-pins
          update-pins = pkgs.callPackage ./update/artcraft-pins.nix { };

          # Rewrites pins.lock.json from the releases' SHA256SUMS.txt, no builds.
          # Usage: nix run .#update [product…] [-- --dry-run|--all|--verify|--all]
          update = pkgs.callPackage ./update/default.nix { };
        }
      );

      apps = forAllSystems (
        system:
        lib.mapAttrs (lib.const appFor) (craftOf system)
        // {
          default = artcraftApp system;
          artcraft = artcraftApp system;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.cargo
              pkgs.clippy
              pkgs.rustc
              pkgs.rustfmt
              pkgs.rust-analyzer
            ];
            # ALSA, X11, Wayland, Mesa, ffmpeg... that the crate links against.
            inputsFrom = [ pkgs.artcraft ];
            shellHook = ''
              echo "Craft flake dev shell (ArtCraft source build, pinned in pins.nix)."
              echo "Fetch the source:  nix build --no-link --print-out-paths .#artcraft.src"
              echo "Bump ArtCraft:     nix run .#update-pins"
              echo "Bump the suite:    nix run .#update -- --dry-run"
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          craft = craftOf system;
          # Upstream's .desktop and AppStream, validated rather than authored: the
          # metainfo test also proves the shipped <release version> matches the pin.
          assetChecks = lib.mapAttrs' (
            name: p:
            lib.nameValuePair "desktop-assets-${name}" (
              pkgs.linkFarmFromDrvs "craft-desktop-assets-${name}" [
                p.passthru.tests.desktopEntry
                p.passthru.tests.metainfo
              ]
            )
          ) craft;

          # Display-free loader test: every <app>-cli in the closure must answer
          # --version. This is what a builder without a GPU can actually verify.
          smokes = lib.mapAttrs' (
            name: p:
            lib.nameValuePair "smoke-${name}" (
              pkgs.runCommand "craft-smoke-${name}"
                {
                  nativeBuildInputs = [
                    p
                    pkgs.patchelf
                  ];
                  meta.timeout = 300;
                }
                ''
                  # Display-free loader test: every headless CLI must answer
                  # --version. That proves the interpreter is repointed and the
                  # wrapper's LD_LIBRARY_PATH resolves, on any builder.
                  for b in ${lib.concatStringsSep " " p.passthru.product.cliBins}; do
                    echo "$b --version ->" "$($b --version)"
                  done

                  # The GUI binary is only checked, not run: it needs a Wayland or
                  # X11 session. Its interpreter must point into the store, which is
                  # the one thing a builder can verify about it.
                  gui="$(command -v ${p.passthru.product.guiBin})"
                  grep -q 'LD_LIBRARY_PATH' "$gui" || {
                    echo "error: $gui does not set LD_LIBRARY_PATH" >&2
                    exit 1
                  }
                  # The wrapper execs .<name>-wrapped: that ELF is the only
                  # thing we actually modify, so verify its interpreter.
                  real="$(dirname "$gui")/.$(basename "$gui")-wrapped"
                  interp="$(patchelf --print-interpreter "$real")"
                  case "$interp" in
                    /nix/store/*) echo "$real interpreter: $interp" ;;
                    *) echo "error: $real still has interpreter $interp" >&2; exit 1 ;;
                  esac
                  touch "$out"
                ''
            )
          ) (lib.filterAttrs (_n: p: p.passthru.product.cliBins != [ ]) craft);
        in
        {
          package = pkgs.artcraft;
          desktopItem = pkgs.callPackage ./pkgs/desktopItem.nix { package = pkgs.artcraft; };
          nixfmt = pkgs.runCommand "artcraft-flake-nixfmt" {
            nativeBuildInputs = [ pkgs.nixfmt ];
            src = lib.fileset.toSource {
              root = ./.;
              fileset = nixFiles;
            };
          } "nixfmt --check $src && touch $out";

          prebuilt-eval = pkgs.callPackage ./tests/prebuilt-eval.nix {
            inherit products pins;
            systems = craftSystems;
            craftDrvFor =
              sys:
              craftPackagesFor {
                pkgs = barePkgs sys;
                system = sys;
              };
          };

          # Generated NixOS module: does programs.crafts.enable actually install
          # every product's out + desktop output, and does the portal reminder
          # stay quiet when a portal is configured?
          nixos-crafts-module = pkgs.callPackage ./tests/nixos-module-check.nix {
            # nixosSystem lives on the flake input lib, not on pkgs.lib.
            lib = nixpkgs.lib;
            craftPackages = craft;
            module = self.nixosModules.crafts;
          };
        }
        // smokes
        // assetChecks
      );
    };
}
