{
  lib,
  stdenv,
  llvmPackages,
  fetchFromGitHub,
  cmake,
  python3,
  z3,
  stp,
  gperftools,
  sqlite,
  gtest,
  kleeuClibc,
  debug ? false,
  includeDebugInfo ? true,
  asserts ? true,
  debugRuntime ? true,
  runtimeAsserts ? false,
}:
let
  kleePython = python3.withPackages (ps: with ps; [tabulate]);
  pythonInclude = "${python3}/include/python${python3.pythonVersion}";
  pythonLib = "${python3}/lib/libpython${python3.pythonVersion}.so";
in
stdenv.mkDerivation {
  pname = "learch-klee";
  version = "2.1-learch";

  src = fetchFromGitHub {
    owner = "eth-sri";
    repo = "learch";
    rev = "master";
    sha256 = "sha256-aAhcptmRNxVasyHaIQ3Jbw2s9RYgmqFTTL7K53LgwnM=";
  };

  sourceRoot = "source/klee";

  nativeBuildInputs = [cmake];

  buildInputs = [
    llvmPackages.llvm
    gperftools
    sqlite
    stp
    z3
    python3
  ];

  nativeCheckInputs = [
    gtest
    kleePython
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
    "-DLLVM_CONFIG_BINARY=${llvmPackages.llvm}/bin/llvm-config"
    "-DKLEE_ENABLE_TIMESTAMP=${onOff false}"
    "-DKLEE_UCLIBC_PATH=${kleeuClibc}"
    "-DENABLE_KLEE_ASSERTS=${onOff asserts}"
    "-DENABLE_POSIX_RUNTIME=${onOff true}"
    "-DENABLE_KLEE_UCLIBC=${onOff true}"
    "-DENABLE_UNIT_TESTS=${onOff false}"
    "-DENABLE_SYSTEM_TESTS=${onOff false}"
    "-DENABLE_SOLVER_STP=${onOff true}"
    "-DENABLE_SOLVER_Z3=${onOff false}"
    "-DGTEST_SRC_DIR=${gtest.src}"
    "-DGTEST_INCLUDE_DIR=${gtest.src}/googletest/include"
    # Python bindings for LEARCH
    "-DLIB_PYTHON=${pythonLib}"
    "-DPYTHON_INCLUDE_DIRS=${pythonInclude}"
  ];

  prePatch = ''
    patchShebangs --build .

    # Fix CMake minimum version for newer CMake
    sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    # Remove OLD cmake_policy settings that are no longer supported
    # CMP0054 and others can't be set to OLD in newer CMake
    sed -i '/cmake_policy.*SET.*CMP00.*OLD/d' CMakeLists.txt
    sed -i '/cmake_policy.*SET.*CMP0054.*OLD/d' CMakeLists.txt
    sed -i '/cmake_policy.*SET.*CMP0053.*OLD/d' CMakeLists.txt

    # Also fix any cmake_policy that tries to set to OLD
    find . -name "CMakeLists.txt" -exec sed -i '/cmake_policy.*OLD/d' {} \;

    # Fix runtime build - the O0OPT variable with spaces causes make invocation problems
    # For LLVM 6, we don't need the -Xclang -disable-O0-optnone flags
    # Replace the ExternalProject_Add_Step to use a simpler invocation without env
    sed -i '/ExternalProject_Add_Step(BuildKLEERuntimes RuntimeBuild/,/^)/c\
ExternalProject_Add_Step(BuildKLEERuntimes RuntimeBuild\
  COMMAND ''${MAKE_BINARY} -f Makefile.cmake.bitcode "O0OPT=-O0" all\
  ALWAYS ''${EXTERNAL_PROJECT_BUILD_ALWAYS_ARG}\
  WORKING_DIRECTORY "''${CMAKE_CURRENT_BINARY_DIR}"\
  ''${EXTERNAL_PROJECT_ADD_STEP_USES_TERMINAL_ARG}\
)' runtime/CMakeLists.txt || true

    # Fix missing #include <cstdint> for modern GCC (GCC 13+)
    # These headers use uint64_t/uint32_t without including the header
    find include -name "*.h" -type f | while read f; do
      if grep -q 'uint64_t\|uint32_t\|uint8_t\|uint16_t' "$f"; then
        if ! grep -q '#include <cstdint>' "$f"; then
          sed -i '1i #include <cstdint>' "$f"
        fi
      fi
    done

    # Also fix source files
    find lib tools -name "*.cpp" -type f | while read f; do
      if grep -q 'uint64_t\|uint32_t\|uint8_t\|uint16_t' "$f"; then
        if ! grep -q '#include <cstdint>' "$f"; then
          sed -i '1i #include <cstdint>' "$f"
        fi
      fi
    done

    # Ensure we use the right Python
    sed -i 's/find_package(PythonInterp REQUIRED)/find_package(PythonInterp 3 REQUIRED)/' CMakeLists.txt || true
  '';

  # Silence various warnings during the compilation of fortified bitcode.
  # Also add Python include path for LEARCH searcher
  env.NIX_CFLAGS_COMPILE = toString [
    "-Wno-macro-redefined"
    "-Wno-deprecated-declarations"
    "-I${pythonInclude}"
  ];

  hardeningDisable = ["fortify"];

  enableParallelBuilding = true;
  doCheck = false;

  postInstall = ''
    # Create wrapper script that sets up PYTHONPATH for LEARCH
    mkdir -p $out/share/learch
    cat > $out/share/learch/setup-env.sh << 'EOF'
#!/bin/sh
export LLVM_COMPILER=clang
export PATH="$KLEE_BIN:$PATH"
EOF
    substituteInPlace $out/share/learch/setup-env.sh \
      --replace '$KLEE_BIN' "$out/bin"
  '';

  passthru = {
    uclibc = kleeuClibc;
  };

  meta = {
    mainProgram = "klee";
    description = "LEARCH-modified KLEE for learning-based path exploration";
    longDescription = ''
      KLEE with LEARCH (Learning to Explore Paths for Symbolic Execution),
      a learning-based state selection strategy that uses machine learning
      to achieve better coverage. From CCS '21.

      This version is built with LLVM 6 to match the original LEARCH
      implementation from eth-sri/learch.

      Features:
      - ML-based path selection
      - Python bindings for training
      - Improved coverage over manual heuristics

      Usage with trained models:
        klee --search=feedforward --model-path=/path/to/model.pt program.bc
    '';
    homepage = "https://github.com/eth-sri/learch";
    license = lib.licenses.ncsa;
    platforms = ["x86_64-linux"];
  };
}
