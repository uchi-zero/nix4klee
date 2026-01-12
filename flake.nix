{
  description = "Nix flake for KLEE and its variants (including CGS)";

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
    {
      overlays.default = final: prev: {
        # LLVM 16 for standard KLEE
        llvmPackages_klee = nixpkgs-legacy.legacyPackages.${prev.system}.llvmPackages_16;

        # LLVM 13 for CGS (compatible with LLVM 11 API, avoids glibc mismatch)
        llvmPackages_cgs = nixpkgs-legacy.legacyPackages.${prev.system}.llvmPackages_13;

        # Standard KLEE
        klee = final.callPackage ./pkgs/klee.nix {
          llvmPackages = final.llvmPackages_klee;
        };

        # CGS packages
        cgs-klee-uclibc = final.callPackage ./pkgs/cgs-klee-uclibc.nix {
          llvmPackages = final.llvmPackages_cgs;
        };

        cgs-ida = final.callPackage ./pkgs/cgs-ida.nix {
          llvmPackages = final.llvmPackages_cgs;
        };

        cgs-klee = final.callPackage ./pkgs/cgs-klee.nix {
          llvmPackages = final.llvmPackages_cgs;
          kleeuClibc = final.cgs-klee-uclibc;
        };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        };
      in {
        packages = {
          default = pkgs.klee;
          klee = pkgs.klee;
          # CGS packages
          cgs-klee = pkgs.cgs-klee;
          cgs-ida = pkgs.cgs-ida;
          cgs-klee-uclibc = pkgs.cgs-klee-uclibc;
        };

        # Development shell for CGS
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cgs-klee
            cgs-ida
            llvmPackages_cgs.llvm
            llvmPackages_cgs.clang
            python3
            python3Packages.tabulate
            cmake
            gnumake
            z3
            stp
          ];

          shellHook = ''
            echo "CGS Development Environment"
            echo "============================"
            echo "KLEE: $(klee --version 2>&1 | head -1)"
            echo "IDA Pass: $cgs-ida/lib/libidapass.so"
            echo ""
            echo "Set these environment variables for CGS:"
            echo "  export SOURCE_DIR=\$PWD"
            echo "  export SANDBOX_DIR=/tmp"
            echo "  export OUTPUT_DIR=\$PWD/results"
          '';
        };
      }
    );
}
