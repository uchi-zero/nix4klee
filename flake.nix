{
  description = "Nix flake for KLEE and its variants";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-legacy.url = "github:nixos/nixpkgs/25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-legacy,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        legacyPkgs = nixpkgs-legacy.legacyPackages.${system};
        llvm16 = legacyPkgs.llvmPackages_16;
      in {
        packages = {
          klee = pkgs.callPackage ./pkgs/klee.nix {
            llvmPackages = legacyPkgs.llvmPackages_16;
          };
          stdenv = llvm16.stdenv;
        };
      }
    );
}
