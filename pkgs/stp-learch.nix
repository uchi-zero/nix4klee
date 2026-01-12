{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  boost,
  bison,
  flex,
  perl,
  python3,
  minisat,
  zlib,
}:

stdenv.mkDerivation {
  pname = "stp-learch";
  version = "2.3.3-learch";

  # Use the specific commit referenced in LEARCH Dockerfile
  src = fetchFromGitHub {
    owner = "stp";
    repo = "stp";
    rev = "7a3fd493ae6f0a524f853946308f4f3c3ddcbe76";
    sha256 = "sha256-B+HQF4TJPkYrpodE4qo4JHvlu+a5HTJf1AFyXTnZ4vk=";
  };

  nativeBuildInputs = [
    cmake
    bison
    flex
    perl
    python3
  ];

  buildInputs = [
    boost
    minisat
    zlib
  ];

  cmakeFlags = [
    "-DENABLE_PYTHON_INTERFACE=OFF"
    "-DENABLE_TESTING=OFF"
    "-DBUILD_SHARED_LIBS=ON"
    "-DNOCRYPTOMINISAT=ON"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  # Fix for modern compilers
  prePatch = ''
    # Fix CMake minimum version
    sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    # Fix missing headers for modern C++
    find . -name "*.cpp" -o -name "*.h" | while read f; do
      if grep -q "uint32_t\|uint64_t" "$f" && ! grep -q "#include <cstdint>" "$f"; then
        sed -i '1i #include <cstdint>' "$f" 2>/dev/null || true
      fi
    done

    # Fix deprecated C++ constructs
    substituteInPlace lib/Sat/MinisatCore.h \
      --replace "throw()" "noexcept" || true
    substituteInPlace lib/Sat/CryptoMinisat5.h \
      --replace "throw()" "noexcept" || true
  '';

  enableParallelBuilding = true;

  meta = {
    description = "STP constraint solver (LEARCH version)";
    longDescription = ''
      STP (Simple Theorem Prover) is an efficient decision procedure for the
      theory of fixed-width bitvectors and arrays. This is the specific version
      required by LEARCH (commit 7a3fd493ae6f0a524f853946308f4f3c3ddcbe76).
    '';
    homepage = "https://github.com/stp/stp";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
