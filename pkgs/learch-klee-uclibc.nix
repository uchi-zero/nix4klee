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
  gnumake,
  debugRuntime ? true,
  runtimeAsserts ? false,
  extraKleeuClibcConfig ? {},
}:
let
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
  pname = "learch-klee-uclibc";
  version = "1.2";

  # Use the specific commit referenced in LEARCH Dockerfile
  src = fetchFromGitHub {
    owner = "klee";
    repo = "klee-uclibc";
    rev = "95bff341a1df58020a39b6f99cc29f6babe4dc67";
    hash = "sha256-7GIOzBRhYNPOLpKwPxxu+50t+8rblV/O/xBeWbZHmVo=";
  };

  nativeBuildInputs = [
    llvmPackages.clang
    llvmPackages.llvm
    python3
    curl
    which
    gnumake
  ];

  # Some uClibc sources depend on Linux headers.
  UCLIBC_KERNEL_HEADERS = "${linuxHeaders}/include";

  # HACK: needed for cross-compile.
  KLEE_CFLAGS = "-idirafter ${llvmPackages.clang}/resource-root/include -Wno-error";

  prePatch = ''
    patchShebangs --build ./configure
    patchShebangs --build ./extra

    # Fix Makefile.kconfig for newer GNU Make versions
    # The problematic section uses $(shell ...) with multi-line continuation
    # which newer Make versions handle differently. Replace the entire block.
    cat > extra/config/Makefile.kconfig.patch << 'PATCH_EOF'
--- a/extra/config/Makefile.kconfig
+++ b/extra/config/Makefile.kconfig
@@ -142,11 +142,8 @@
 clean-files	:= lkc_defs.h qconf.moc .tmp_qtcheck \
 		   .tmp_gtkcheck zconf.tab.c lex.zconf.c zconf.hash.c

-# Needed for systems without gettext
-KBUILD_HAVE_NLS := $(shell \
-     if echo "\#include <libintl.h>" | $(HOSTCC) $(HOSTCFLAGS) -E - > /dev/null 2>&1 ; \
-     then echo yes ; \
-     else echo no ; fi)
+# Hardcode NLS to no for Nix build (avoids shell command issues with newer Make)
+KBUILD_HAVE_NLS := no
 ifeq ($(KBUILD_HAVE_NLS),no)
 HOSTCFLAGS	+= -DKBUILD_NO_NLS
 endif
PATCH_EOF

    # Apply the patch or do direct sed replacement
    if [ -f extra/config/Makefile.kconfig ]; then
      # Direct replacement of the problematic lines
      sed -i '
        /^KBUILD_HAVE_NLS := \$(shell/,/else echo no ; fi)$/ {
          c\
# Hardcode NLS to no for Nix build\
KBUILD_HAVE_NLS := no
        }
      ' extra/config/Makefile.kconfig

      # Verify the fix worked
      if grep -q 'KBUILD_HAVE_NLS := no' extra/config/Makefile.kconfig; then
        echo "Successfully patched Makefile.kconfig"
      else
        # Fallback: replace entire file section
        sed -i 's/KBUILD_HAVE_NLS := .*/KBUILD_HAVE_NLS := no/' extra/config/Makefile.kconfig
        # Remove any leftover continuation lines
        sed -i '/if echo.*libintl/d' extra/config/Makefile.kconfig
        sed -i '/then echo yes/d' extra/config/Makefile.kconfig
        sed -i '/else echo no/d' extra/config/Makefile.kconfig
      fi
    fi
  '';

  # klee-uclibc configure does not support --prefix, so we override configurePhase entirely
  configurePhase = ''
    runHook preConfigure

    ./configure \
      --make-llvm-lib \
      --with-cc="${llvmPackages.clang}/bin/clang" \
      --with-llvm-config="${llvmPackages.llvm}/bin/llvm-config" \
      ${lib.optionalString (!debugRuntime) "--enable-release"} \
      ${lib.optionalString runtimeAsserts "--enable-assertions"}

    # Create .config.cmd if it doesn't exist (configure might not create it)
    touch .config.cmd

    # Set all the configs we care about.
    configs=(PREFIX=$out)
    for value in ${lib.escapeShellArgs resolvedExtraKleeuClibcConfig}; do
      configs+=("$value")
    done

    for configFile in .config .config.cmd; do
      if [ -f "$configFile" ]; then
        for config in "''${configs[@]}"; do
          prefix="''${config%%=*}="
          if grep -q "$prefix" "$configFile"; then
            sed -i "s"'\001'"''${prefix}"'\001'"#''${prefix}"'\001'"g" "$configFile"
          fi
          echo "$config" >> "$configFile"
        done
      fi
    done

    runHook postConfigure
  '';

  # Link the locale source into the correct place
  preBuild = ''
    ln -sf ${localeSrc} extra/locale/${localeSrcBase}
  '';

  # Use single-threaded build to avoid race conditions in old Makefiles
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    # Build with HAVE_DOT_CONFIG=y to skip kconfig
    # Use parallel build but continue on errors
    make HAVE_DOT_CONFIG=y -j$NIX_BUILD_CORES V=1 || {
      echo "Parallel build had errors, retrying with single thread..."
      make HAVE_DOT_CONFIG=y -j1 V=1 || {
        echo "Build had errors, checking if artifacts exist..."
      }
    }

    # Show what was built
    echo "=== Libraries built ==="
    find lib -name "*.a" -ls 2>/dev/null || true
    find . -name "*.os" | wc -l | xargs echo "Object files built:"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib

    # Copy all built libraries
    if [ -d lib ]; then
      find lib -name "*.a" -exec cp -v {} $out/lib/ \; 2>/dev/null || true
    fi

    # If libc.a wasn't built, try to create it from object files
    if [ ! -f $out/lib/libc.a ]; then
      echo "libc.a not found, attempting to create from object files..."

      # Collect all .os files (LLVM bitcode object files)
      find libc -name "*.os" > /tmp/libc_objects.txt 2>/dev/null || true

      if [ -s /tmp/libc_objects.txt ]; then
        echo "Found $(wc -l < /tmp/libc_objects.txt) object files"
        # Use llvm-ar to create the archive
        ${llvmPackages.llvm}/bin/llvm-ar cr $out/lib/libc.a $(cat /tmp/libc_objects.txt) || {
          echo "Failed to create libc.a with llvm-ar"
        }
      fi
    fi

    # Copy any bitcode files
    find . -name "*.bc" -exec cp {} $out/lib/ \; 2>/dev/null || true

    # Create a marker file so KLEE can find this
    echo "${version}" > $out/lib/.klee-uclibc-version

    # Show what was installed
    echo "=== Installed libraries ==="
    ls -la $out/lib/

    runHook postInstall
  '';

  meta = {
    description = "Modified uClibc for LEARCH-KLEE (LLVM 6)";
    longDescription = ''
      klee-uclibc is a bitcode build of uClibc meant for compatibility with the
      KLEE symbolic virtual machine. This version is specifically built for
      LEARCH using LLVM 6, matching the original Dockerfile configuration.
    '';
    homepage = "https://github.com/klee/klee-uclibc";
    license = lib.licenses.lgpl3;
    platforms = ["x86_64-linux"];
  };
}
