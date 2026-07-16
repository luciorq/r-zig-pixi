#!/usr/bin/env bash
# Configure R against the pixi environment with the zig toolchain.
# Design: one maximal build — X11 off everywhere (parity with Windows/macOS),
# cairo graphics everywhere, tcltk from conda-forge tk, internal BLAS/LAPACK,
# internal tzcode, no Java, no recommended packages (installed separately later).
. "$(dirname "$0")/env.sh"
require_not_windows

if [ -f "$OBJ_DIR/Makeconf" ]; then
  echo "Already configured at $OBJ_DIR (run 'pixi run clean' to reconfigure)"
  exit 0
fi

FC="$(fortran_compiler)"
CONDA="${CONDA_PREFIX:?pixi should set CONDA_PREFIX}"

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

TCLTK_ARGS=()
if [ -f "$CONDA/lib/tclConfig.sh" ] && [ -f "$CONDA/lib/tkConfig.sh" ]; then
  TCLTK_ARGS+=("--with-tcl-config=$CONDA/lib/tclConfig.sh")
  TCLTK_ARGS+=("--with-tk-config=$CONDA/lib/tkConfig.sh")
else
  TCLTK_ARGS+=("--without-tcltk")
fi

mkdir -p "$OBJ_DIR"
cd "$OBJ_DIR"

"$SRC_DIR/configure" \
  --prefix="$PREFIX" \
  --enable-R-shlib \
  --with-x=no \
  --without-aqua \
  --with-cairo \
  --with-libpng --with-jpeglib --with-libtiff \
  --with-internal-tzcode \
  --without-recommended-packages \
  --disable-java \
  "${TCLTK_ARGS[@]}" \
  CC="$TOOLCHAIN/zig-cc" \
  CXX="$TOOLCHAIN/zig-cxx" \
  FC="$FC" \
  AR="$TOOLCHAIN/zig-ar" \
  RANLIB="$TOOLCHAIN/zig-ranlib" \
  CFLAGS="-O2" \
  CXXFLAGS="-O2" \
  FFLAGS="-O2" \
  FCFLAGS="-O2" \
  CPPFLAGS="-I$CONDA/include" \
  LDFLAGS="-L$CONDA/lib -Wl,-rpath,$CONDA/lib" \
  "${FLIBS_ARGS[@]}"

echo
echo "Configured. Capability summary:"
sed -n '/R is now configured/,$p' config.log 2>/dev/null || true
