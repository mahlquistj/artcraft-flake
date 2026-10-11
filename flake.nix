{
  description = "ArtCraft desktop app (pure-Rust egui client) packaged for Linux as a Nix flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      allNixFiles = nixpkgs.lib.fileset.unions [
        ./flake.nix
        ./pins.nix
        ./update.nix
        ./pkg
        ./modules
        ./tests
      ];
    in
    {
      # Adds `artcraft` (and the app's menu entry helper) to any package set, so
      # the app can be installed with an overlay instead of `nix run`.
      overlays.default = final: prev: {
        artcraft = final.callPackage ./pkg/artcraft.nix { };
        artcraft-desktop-item = final.callPackage ./pkg/desktopItem.nix {
          package = final.artcraft;
        };
      };

      nixosModules.artcraft = import ./modules/nixos.nix;
      nixosModules.default = self.nixosModules.artcraft;

      homeModules.artcraft = import ./modules/home-manager.nix;
      homeManagerModules.artcraft = self.homeModules.artcraft;
      homeManagerModules.default = self.homeModules.artcraft;

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          artcraft = pkgs.artcraft;
          default = pkgs.artcraft;

          # Rewrites pins.nix (rev, date, version, srcHash, cargoHash) and
          # verifies the build. Usage: nix run .#update-pins
          update-pins = pkgs.callPackage ./update.nix { };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.artcraft}/bin/artcraft";
        };
        artcraft = self.apps.${system}.default;
      });

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
              echo "ArtCraft dev shell (upstream source pinned in pins.nix)."
              echo "Fetch the source:  nix build --no-link --print-out-paths .#artcraft.src"
              echo "Build:             cargo build --release --package artcraft_native"
              echo "Test:              cargo test --package artcraft_native"
            '';
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          package = pkgs.artcraft;
          desktopItem = pkgs.artcraft-desktop-item;
          nixfmt = pkgs.runCommand "artcraft-flake-nixfmt" {
            nativeBuildInputs = [ pkgs.nixfmt ];
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = allNixFiles;
            };
          } "nixfmt --check $src && touch $out";
        }
      );
    };
}
