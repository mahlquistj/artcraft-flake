# Turns products.nix + pins.lock.json into package attributes for one package
# set. Shared by the flake outputs, the overlay and the eval test, so there is a
# single definition of "which Craft apps does this flake publish here".
#
# `system` is an argument rather than `pkgs.stdenv.hostPlatform.system` on
# purpose: reading stdenv out of `final` inside an overlay recurses (nixpkgs'
# stdenv booter touches the whole set), and the answer is fixed per flake anyway.
#
# A product is published when it is marked packageable *and* pins.lock.json has
# an asset for that system; that keeps riscv64/aarch64 pins eval-only until
# somebody builds on them.
{ lib }:
{ products, pins }:
{ pkgs, system }:
let
  pinFor = repo: pins.${repo} or { systems = { }; };

  published = lib.filterAttrs (
    _name: product: product.packageable && builtins.hasAttr system (pinFor product.repo).systems
  ) products;
in
lib.mapAttrs' (
  _name: product:
  lib.nameValuePair product.repo (
    pkgs.callPackage ./craft-app {
      inherit product pins;
    }
  )
) published
