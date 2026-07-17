#!/usr/bin/env bash
# Configure R against the pixi environment with the zig toolchain.
# Two profiles (see pixi.toml):
#   slim (default): headless — cairo+png, ICU, pcre2, libcurl, compression,
#                   internal BLAS/LAPACK, R shlib. No X11/quartz/tcltk/
#                   readline/NLS/jpeg/tiff, no recommended packages.
#   full:           slim plus tcltk, readline, NLS, jpeg+tiff devices.
# X11/quartz are off in both — cairo is the graphics engine on all OSes.
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  echo "Windows: no autoconf step — gnuwin32 configures via MkRules.local (build-gnuwin32.sh)"
  exit 0
fi

if [ -f "$OBJ_DIR/Makeconf" ]; then
  echo "Already configured at $OBJ_DIR (run 'pixi run clean' to reconfigure)"
  exit 0
fi
echo "Configuring R $R_VERSION, variant: $VARIANT"

FC="$(fortran_compiler)"
CONDA="${CONDA_PREFIX:?pixi should set CONDA_PREFIX}"

# gfortran 15.2 miscompiles R's complex LAPACK (cmplx.f/zgesdd) at -O2 on
# arm64 macOS: SVD returns wrong U/V with info=0 (silent!). Verified on
# real hardware 2026-07-17; results are correct at -O1. Cap Fortran
# optimization with gfortran on Darwin until narrowed to a specific flag.
FOPT="-O2"
if [ "$OS" = macos ] && [ "$FC" = gfortran ]; then
  FOPT="-O1"
fi

# autoconf's AC_FC_LIBRARY_LDFLAGS mangles flang's verbose link output
# (emits a bogus '-lflang_rt.runtime:' with a trailing colon), so give
# configure the Fortran runtime libs explicitly when FC is flang.
FLIBS_ARGS=()
case "$FC" in
  flang*)
    rt=""
    for f in "$CONDA"/lib/clang/*/lib/*/libflang_rt.runtime.a; do
      [ -f "$f" ] && rt="$f" && break
    done
    if [ -z "$rt" ]; then
      echo "error: libflang_rt.runtime not found under $CONDA/lib/clang — is flang-rt installed?" >&2
      exit 1
    fi
    FLIBS_ARGS+=("FLIBS=-L$(dirname "$rt") -lflang_rt.runtime -lm")
    ;;
esac

# Per-variant configure flags. Capabilities are compile-time, so slim
# and full are distinct configure runs in distinct objdirs.
VARIANT_ARGS=()
case "$VARIANT" in
  slim)
    VARIANT_ARGS+=(
      --without-tcltk
      --without-readline
      --disable-nls
      --without-jpeglib
      --without-libtiff
    )
    ;;
  full)
    if [ ! -f "$CONDA/lib/tclConfig.sh" ] || [ ! -f "$CONDA/lib/tkConfig.sh" ]; then
      echo "error: full variant needs tk in the environment — run with 'pixi run -e full ...'" >&2
      exit 1
    fi
    VARIANT_ARGS+=(
      "--with-tcl-config=$CONDA/lib/tclConfig.sh"
      "--with-tk-config=$CONDA/lib/tkConfig.sh"
      --with-readline
      --enable-nls
      --with-jpeglib
      --with-libtiff
    )
    ;;
  *)
    echo "error: unknown R_BUILD_VARIANT '$VARIANT' (expected slim or full)" >&2
    exit 1
    ;;
esac

mkdir -p "$OBJ_DIR"
cd "$OBJ_DIR"

"$SRC_DIR/configure" \
  --prefix="$PREFIX" \
  --enable-R-shlib \
  --with-x=no \
  --without-aqua \
  --with-cairo \
  --with-libpng \
  --with-internal-tzcode \
  --without-recommended-packages \
  --disable-java \
  "${VARIANT_ARGS[@]}" \
  CC="$TOOLCHAIN/zig-cc" \
  CXX="$TOOLCHAIN/zig-cxx" \
  FC="$FC" \
  AR="$TOOLCHAIN/zig-ar" \
  RANLIB="$TOOLCHAIN/zig-ranlib" \
  CFLAGS="-O2" \
  CXXFLAGS="-O2" \
  FFLAGS="$FOPT" \
  FCFLAGS="$FOPT" \
  CPPFLAGS="-I$CONDA/include" \
  LDFLAGS="-L$CONDA/lib -Wl,-rpath,$CONDA/lib" \
  "${FLIBS_ARGS[@]}"

echo
echo "Configured. Capability summary:"
sed -n '/R is now configured/,$p' config.log 2>/dev/null || true
