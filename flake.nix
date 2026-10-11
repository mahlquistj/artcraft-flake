{
  description = "ArtCraft desktop app (pure-Rust egui client) packaged for Linux as a Nix flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # x86_64-linux is what this flake is built and run on; aarch64-linux is
      # evaluated (see `nix flake show`/checks) but not exercised here.
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
      nixFiles = nixpkgs.lib.fileset.unions [
        ./flake.nix
        ./pins.nix
        ./update.nix
        ./pkg
        ./modules
        ./tests
      ];
    in
    {
      # Adds `artcraft` to any package set, for installing through an overlay
      # (home-manager, NixOS `nixpkgs.overlays`, dev shells, ...).
      overlays.default = final: prev: { artcraft = final.callPackage ./pkg/artcraft.nix { }; };

      # NixOS: `programs.artcraft.enable = true;`
      nixosModules.artcraft = import ./modules/nixos.nix;
      nixosModules.default = self.nixosModules.artcraft;

      # home-manager: `programs.artcraft.enable = true;`
      homeModules.artcraft = import ./modules/home-manager.nix;
      homeModules.default = self.homeModules.artcraft;

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

      apps = forAllSystems (
        system:
        let
          artcraftApp = {
            type = "app";
            program = "${self.packages.${system}.artcraft}/bin/artcraft";
            meta = {
              description = "Run the ArtCraft desktop app";
              mainProgram = "artcraft";
            };
          };
        in
        {
          default = artcraftApp;
          artcraft = artcraftApp;
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
              echo "ArtCraft dev shell (upstream source pinned in pins.nix)."
              echo "Fetch the source:  nix build --no-link --print-out-paths .#artcraft.src"
              echo "Build:             cargo build --release --package artcraft_native"
              echo "Test:              cargo test --package artcraft_native"
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          package = pkgs.artcraft;
          desktopItem = pkgs.callPackage ./pkg/desktopItem.nix { package = pkgs.artcraft; };
          nixfmt = pkgs.runCommand "artcraft-flake-nixfmt" {
            nativeBuildInputs = [ pkgs.nixfmt ];
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = nixFiles;
            };
          } "nixfmt --check $src && touch $out";
        }
      );
    };
}
