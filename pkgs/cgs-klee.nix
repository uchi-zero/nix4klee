{
  lib,
  stdenv,
  llvmPackages,
  fetchFromGitHub,
  cmake,
  python3,
  z3,
  stp,
  cryptominisat,
  gperftools,
  sqlite,
  gtest,
  lit,
  kleeuClibc,
  debug ? false,
  includeDebugInfo ? true,
  asserts ? true,
  debugRuntime ? true,
  runtimeAsserts ? false,
}: let
  kleePython = python3.withPackages (ps: with ps; [tabulate]);


in
  stdenv.mkDerivation {
    pname = "cgs-klee";
    version = "2.3-cgs";

    src = fetchFromGitHub {
      owner = "XMUsuny";
      repo = "cgs";
      rev = "master";
      # Run: nix-prefetch-url --unpack https://github.com/XMUsuny/cgs/archive/refs/heads/master.tar.gz
      sha256 = "sha256-bNyfHW1zQUmT/gPBRKRAPHdPKwvIvEQ99CSBa4LkggI=";
    };

    sourceRoot = "source/klee";

    nativeBuildInputs = [cmake];

    buildInputs = [
      llvmPackages.llvm
      cryptominisat
      gperftools
      sqlite
      stp
      z3
    ];

    nativeCheckInputs = [
      gtest
      kleePython
      (lit.override {python = kleePython;})
    ];

    cmakeBuildType =
      if debug
      then "Debug"
      else if !debug && includeDebugInfo
      then "RelWithDebInfo"
      else "MinSizeRel";

    cmakeFlags = let
      onOff = val:
        if val
        then "ON"
        else "OFF";
    in [
      "-DKLEE_RUNTIME_BUILD_TYPE=${
        if debugRuntime
        then "Debug"
        else "Release"
      }"
      "-DLLVMCC=${llvmPackages.clang}/bin/clang"
      "-DLLVMCXX=${llvmPackages.clang}/bin/clang++"
      "-DKLEE_ENABLE_TIMESTAMP=${onOff false}"
      "-DKLEE_UCLIBC_PATH=${kleeuClibc}"
      "-DENABLE_KLEE_ASSERTS=${onOff asserts}"
      "-DENABLE_POSIX_RUNTIME=${onOff true}"
      "-DENABLE_UNIT_TESTS=${onOff false}"
      "-DENABLE_SYSTEM_TESTS=${onOff false}"
      "-DGTEST_SRC_DIR=${gtest.src}"
      "-DGTEST_INCLUDE_DIR=${gtest.src}/googletest/include"
      "-Wno-dev"
    ];

    # Fix missing cstdint include for std::uint64_t
    NIX_CXXFLAGS_COMPILE = "-include cstdint";

    prePatch = ''
      patchShebangs --build .

      # Add missing #include <cstdint> to all headers that use uint64_t/uint32_t
      # GCC 13+ requires explicit includes
      find include -name "*.h" -exec grep -l 'uint64_t\|uint32_t' {} \; | while read f; do
        if ! grep -q '#include <cstdint>' "$f"; then
          sed -i '/#define.*_H/a #include <cstdint>' "$f"
        fi
      done

      # Also fix source files that use std::uint64_t/uint32_t
      find lib tools -name "*.cpp" -exec grep -l 'std::uint64_t\|std::uint32_t' {} \; | while read f; do
        if ! grep -q '#include <cstdint>' "$f"; then
          sed -i '1i #include <cstdint>' "$f"
        fi
      done
    '';

    hardeningDisable = ["fortify"];

    enableParallelBuilding = true;
    doCheck = false;

    passthru = {
      uclibc = kleeuClibc;
    };

    meta = {
      mainProgram = "klee";
      description = "CGS-modified KLEE for Concrete Constraint Guided Symbolic Execution";
      longDescription = ''
        KLEE with CGS (Concrete Constraint Guided Searcher), a dependency-based
        path prioritization method that guides symbolic execution towards
        covering more concrete branches. From ICSE '24.

        Searchers: cgs, dfs, bfs, random-state, random-path, nurs:*
      '';
      homepage = "https://github.com/XMUsuny/cgs";
      license = lib.licenses.ncsa;
      platforms = ["x86_64-linux"];
    };
  }
