{
  lib,
  stdenv,
  llvmPackages,
  fetchurl,
  fetchFromGitHub,
  linuxHeaders,
  python3,
  curl,
  which,
  debugRuntime ? true,
  runtimeAsserts ? false,
  extraKleeuClibcConfig ? {},
}: let
  localeSrcBase = "uClibc-locale-030818.tgz";
  localeSrc = fetchurl {
    url = "http://www.uclibc.org/downloads/${localeSrcBase}";
    sha256 = "xDYr4xijjxjZjcz0YtItlbq5LwVUi7k/ZSmP6a+uvVc=";
  };
  resolvedExtraKleeuClibcConfig = lib.mapAttrsToList (name: value: "${name}=${value}") (
    extraKleeuClibcConfig
    // {
      "UCLIBC_DOWNLOAD_PREGENERATED_LOCALE_DATA" = "n";
      "RUNTIME_PREFIX" = "/";
      "DEVEL_PREFIX" = "/";
    }
  );
in
  stdenv.mkDerivation rec {
    pname = "cgs-klee-uclibc";
    version = "1.4";

    src = fetchFromGitHub {
      owner = "klee";
      repo = "klee-uclibc";
      rev = "klee_uclibc_v${version}";
      hash = "sha256-sogQK5Ed0k5tf4rrYwCKT4YRKyEovgT25p0BhGvJ1ok=";
    };

    nativeBuildInputs = [
      llvmPackages.clang
      llvmPackages.llvm
      python3
      curl
      which
    ];

    UCLIBC_KERNEL_HEADERS = "${linuxHeaders}/include";
    KLEE_CFLAGS = "-idirafter ${llvmPackages.clang}/resource-root/include";

    prePatch = ''
      patchShebangs --build ./configure
      patchShebangs --build ./extra
    '';

    configurePhase = ''
      ./configure \
        --make-llvm-lib \
        --with-cc="${llvmPackages.clang}/bin/clang" \
        --with-llvm-config="${llvmPackages.llvm.dev}/bin/llvm-config" \
        ${lib.optionalString (!debugRuntime) "--enable-release"} \
        ${lib.optionalString runtimeAsserts "--enable-assertions"}

      configs=(PREFIX=$out)
      for value in ${lib.escapeShellArgs resolvedExtraKleeuClibcConfig}; do
        configs+=("$value")
      done

      for configFile in .config .config.cmd; do
        for config in "''${configs[@]}"; do
          prefix="''${config%%=*}="
          if grep -q "$prefix" "$configFile"; then
            sed -i "s"'\001'"''${prefix}"'\001'"#''${prefix}"'\001'"g" "$configFile"
          fi
          echo "$config" >> "$configFile"
        done
      done
    '';

    preBuild = ''
      ln -sf ${localeSrc} extra/locale/${localeSrcBase}
    '';

    makeFlags = ["HAVE_DOT_CONFIG=y"];
    enableParallelBuilding = true;

    meta = {
      description = "Modified uClibc for CGS-KLEE (LLVM 11)";
      homepage = "https://github.com/klee/klee-uclibc";
      license = lib.licenses.lgpl3;
    };
  }
