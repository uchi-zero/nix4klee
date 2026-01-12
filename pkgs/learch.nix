{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:
let
  pythonEnv = python3.withPackages (ps: with ps; [
    numpy
    torch
    tqdm
    scikit-learn
    pandas
    termcolor
    tabulate
  ]);
in
stdenv.mkDerivation {
  pname = "learch";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "eth-sri";
    repo = "learch";
    rev = "master";
    sha256 = "sha256-aAhcptmRNxVasyHaIQ3Jbw2s9RYgmqFTTL7K53LgwnM=";
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/learch
    mkdir -p $out/bin
    mkdir -p $out/share/doc/learch

    # Copy the learch Python code
    cp -r learch/* $out/lib/learch/

    # Copy documentation
    cp README.md $out/share/doc/learch/
    cp -r learch/benchmarks/README.md $out/share/doc/learch/benchmarks.md 2>/dev/null || true
    cp -r learch/train/README.md $out/share/doc/learch/train.md 2>/dev/null || true
    cp -r learch/eval/README.md $out/share/doc/learch/eval.md 2>/dev/null || true

    # Create a shell wrapper that sets up the environment
    makeWrapper ${pythonEnv}/bin/python $out/bin/learch-python \
      --prefix PYTHONPATH : "$out/lib/learch"

    # Create helper script for running learch modules
    cat > $out/bin/learch-run << 'EOF'
#!/bin/sh
export PYTHONPATH="$LEARCH_LIB:$PYTHONPATH"
exec python "$@"
EOF
    chmod +x $out/bin/learch-run
    substituteInPlace $out/bin/learch-run \
      --replace '$LEARCH_LIB' "$out/lib/learch" \
      --replace 'python' "${pythonEnv}/bin/python"

    runHook postInstall
  '';

  meta = {
    description = "LEARCH: Learning-based Strategies for Path Exploration in Symbolic Execution (ML components)";
    longDescription = ''
      LEARCH is a learning-based state selection strategy for symbolic execution.
      It can achieve significantly more coverage and detects more security violations
      than existing manual heuristics. From CCS '21.

      This package provides the Python ML components for training and evaluation.

      NOTE: The full LEARCH system requires a modified KLEE built with LLVM 6.
      Due to LLVM API incompatibilities, the KLEE component should be built using
      the provided Dockerfile:

        docker build -t learch https://github.com/eth-sri/learch.git
        docker run -it learch

      Components provided:
      - learch-python: Python interpreter with LEARCH in PYTHONPATH
      - learch-run: Helper script to run LEARCH modules
      - Python libraries for model training and evaluation

      Usage:
        learch-python -c "from model import *; print('LEARCH loaded')"
        learch-run your_script.py
    '';
    homepage = "https://github.com/eth-sri/learch";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
