{
  description = ''
    Nix flake for KLEE and its variants (including LEARCH)

    LEARCH is a learning-based state selection strategy for symbolic execution
    from CCS '21. This flake provides:

    - Standard KLEE (built with LLVM 16)
    - LEARCH Python ML components (model training and evaluation)
    - LEARCH-KLEE components (LLVM 6 based, with compatibility notes)

    NOTE: LEARCH-KLEE requires LLVM 6 which comes from nixpkgs-20.09.
    Due to glibc version conflicts between old and new nixpkgs, the
    learch-klee binary may have runtime issues. For full LEARCH functionality,
    we recommend using Docker:

      docker build -t learch https://github.com/eth-sri/learch.git
      docker run -it learch

    The Python ML components (learch package) work standalone and can be used
    for model training and evaluation with any KLEE that outputs compatible
    feature data.
  '';

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-legacy.url = "github:nixos/nixpkgs/25.05";
    # Use nixpkgs 20.09 for LLVM 6 support (required by LEARCH-KLEE)
    nixpkgs-llvm6.url = "github:nixos/nixpkgs/nixos-20.09";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-legacy,
    nixpkgs-llvm6,
    flake-utils,
  }:
    {
      overlays.default = final: prev: {
        # LLVM 16 for standard KLEE
        llvmPackages_klee = nixpkgs-legacy.legacyPackages.${prev.system}.llvmPackages_16;

        # LLVM 6 from legacy nixpkgs for LEARCH-KLEE
        # WARNING: Using packages from different nixpkgs versions can cause
        # glibc version conflicts at runtime
        llvmPackages_6 = nixpkgs-llvm6.legacyPackages.${prev.system}.llvmPackages_6;

        # Standard KLEE (fully functional)
        klee = final.callPackage ./pkgs/klee.nix {
          llvmPackages = final.llvmPackages_klee;
        };

        # LEARCH Python ML components (fully functional)
        # Includes model training, evaluation scripts, and pre-trained models
        learch = final.callPackage ./pkgs/learch.nix {};

        # STP solver for LEARCH (specific version from Dockerfile)
        stp-learch = final.callPackage ./pkgs/stp-learch.nix {};

        # LEARCH klee-uclibc (with LLVM 6)
        # Builds successfully, produces LLVM bitcode libraries
        learch-klee-uclibc = final.callPackage ./pkgs/learch-klee-uclibc.nix {
          llvmPackages = final.llvmPackages_6;
        };

        # LEARCH-modified KLEE (with LLVM 6)
        # WARNING: May have runtime glibc conflicts due to mixing nixpkgs versions
        # Use Docker for production LEARCH-KLEE usage
        learch-klee = final.callPackage ./pkgs/learch-klee.nix {
          llvmPackages = final.llvmPackages_6;
          kleeuClibc = final.learch-klee-uclibc;
          stp = final.stp-learch;
        };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
          config.allowUnfree = true;
        };
      in {
        packages = {
          default = pkgs.klee;
          klee = pkgs.klee;
          # LEARCH Python ML components (recommended)
          learch = pkgs.learch;
          # LEARCH-KLEE components (may have runtime issues)
          learch-klee-uclibc = pkgs.learch-klee-uclibc;
          learch-klee = pkgs.learch-klee;
          stp-learch = pkgs.stp-learch;
        };

        # Development shell for LEARCH (Python ML components only)
        # This is the recommended way to use LEARCH for training/evaluation
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            klee
            learch
            python3
            python3Packages.numpy
            python3Packages.torch
            python3Packages.tqdm
            python3Packages.scikit-learn
            python3Packages.pandas
            python3Packages.termcolor
            python3Packages.tabulate
          ];

          shellHook = ''
            echo "KLEE + LEARCH Development Environment"
            echo "======================================"
            echo ""
            echo "Standard KLEE available at: $(which klee 2>/dev/null || echo 'not found')"
            echo ""
            echo "LEARCH Python modules available via:"
            echo "  learch-python -c 'from model import *'"
            echo "  learch-run your_script.py"
            echo ""
            echo "Training a model:"
            echo "  cd \$(learch-python -c 'import os; print(os.path.dirname(__file__))')/train"
            echo "  python3 ../model.py --features data/all_features.npy --model feedforward"
            echo ""
            echo "For full LEARCH-KLEE with LLVM 6, use Docker:"
            echo "  docker build -t learch https://github.com/eth-sri/learch.git"
          '';

          LLVM_COMPILER = "clang";
          PYTHONPATH = "${pkgs.learch}/lib/learch";
        };

        devShells.learch = pkgs.mkShell {
          buildInputs = with pkgs; [
            learch
            python3
            python3Packages.numpy
            python3Packages.torch
            python3Packages.tqdm
            python3Packages.scikit-learn
            python3Packages.pandas
            python3Packages.termcolor
            python3Packages.tabulate
          ];

          shellHook = ''
            echo "LEARCH Development Environment (Python ML components)"
            echo "======================================================"
            echo ""
            echo "Python LEARCH modules available via:"
            echo "  learch-python -c 'from model import *'"
            echo ""
            echo "Pre-trained models are in:"
            echo "  ${pkgs.learch}/lib/learch/train/trained/"
            echo ""
            echo "For full LEARCH-KLEE with LLVM 6, use Docker:"
            echo "  docker build -t learch https://github.com/eth-sri/learch.git"
          '';

          PYTHONPATH = "${pkgs.learch}/lib/learch";
        };

        # Development shell for LEARCH-KLEE (experimental - may have runtime issues)
        devShells.learch-klee = pkgs.mkShell {
          buildInputs = with pkgs; [
            learch-klee
            learch
            python3
            python3Packages.numpy
            python3Packages.torch
            python3Packages.tqdm
            python3Packages.scikit-learn
            python3Packages.pandas
            python3Packages.termcolor
            python3Packages.tabulate
          ];

          shellHook = ''
            echo "LEARCH-KLEE Development Environment (EXPERIMENTAL)"
            echo "==================================================="
            echo ""
            echo "WARNING: LEARCH-KLEE is built with LLVM 6 from nixpkgs-20.09"
            echo "which may cause glibc version conflicts at runtime."
            echo ""
            echo "For production use, we recommend Docker:"
            echo "  docker build -t learch https://github.com/eth-sri/learch.git"
            echo "  docker run -it learch"
            echo ""
            echo "Environment variables set:"
            echo "  LLVM_COMPILER=clang"
            echo "  PYTHONPATH includes LEARCH modules"
          '';

          LLVM_COMPILER = "clang";
          PYTHONPATH = "${pkgs.learch}/lib/learch";
        };
      }
    );
}
