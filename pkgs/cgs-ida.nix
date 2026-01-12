{
  lib,
  stdenv,
  llvmPackages,
  fetchFromGitHub,
  cmake,
}:
stdenv.mkDerivation {
  pname = "cgs-ida";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "XMUsuny";
    repo = "cgs";
    rev = "master";
    sha256 = "sha256-bNyfHW1zQUmT/gPBRKRAPHdPKwvIvEQ99CSBa4LkggI=";
  };

  sourceRoot = "source/IDA";

  nativeBuildInputs = [cmake];

  buildInputs = [
    llvmPackages.llvm
    llvmPackages.clang
  ];

  cmakeFlags = [
    "-DLLVM_DIR=${llvmPackages.llvm.dev}/lib/cmake/llvm"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin

    cp libidapass.so $out/lib/

    cat > $out/bin/ida-pass << EOF
    #!/bin/sh
    exec ${llvmPackages.llvm}/bin/opt -load $out/lib/libidapass.so -ida "\$@"
    EOF
    chmod +x $out/bin/ida-pass

    runHook postInstall
  '';

  meta = {
    description = "Branch Dependency Analysis LLVM Pass for CGS";
    longDescription = ''
      IDA analyzes data dependency of variables in branching conditions.
      Usage: opt -load libidapass.so -ida <program.bc>
      Or: ida-pass <program.bc>
    '';
    homepage = "https://github.com/XMUsuny/cgs";
    license = lib.licenses.ncsa;
    platforms = ["x86_64-linux"];
  };
}
