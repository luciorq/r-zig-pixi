#!/usr/bin/env bash
# Run R's real `configure` against the pixi environment — nothing else.
# The sole reason this exists is to produce a config.status for
# gen-subst.sh to replay (see that script's own header comment and
# PLAN.md's "Regenerating the vendored config" section). It does NOT
# drive a full legacy build the way the old (Milestone 7-retired)
# scripts/configure-r.sh + scripts/build-r.sh pair did — this project's
# actual build path is `zig build` (scripts/zig-build.sh), which already
# independently owns and applies the two R-source patches
# (Sys.which/bin/toolchain/which and R_LIBS_USER_default's XDG/
# LOCALAPPDATA scheme — see zig-build.sh's own comments) that the old
# configure-r.sh also used to carry a duplicate copy of for the legacy
# path's benefit. Only one script should own those patches now that the
# legacy path is gone, so this one deliberately does not re-apply them.
. "$(dirname "$0")/../../scripts/env.sh"

if [ "$OS" = windows ]; then
  echo "Windows: no autoconf step — gnuwin32 has no config.status/S-table" >&2
  echo "to replay; gen-subst.sh already refuses Windows for the same reason." >&2
  exit 0
fi

if [ -f "$OBJ_DIR/Makeconf" ]; then
  echo "Already configured at $OBJ_DIR (run 'pixi run clean' to reconfigure)"
  exit 0
fi
echo "Configuring R $R_VERSION, variant: $VARIANT (configure-only, for gen-subst.sh)"

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
    # macOS: the flang driver locates the SDK via SDKROOT (falling back to
    # xcrun); without it every *link* it performs dies with "ld: library
    # 'System' not found". R itself never links with flang (packages go
    # through the zig-cc shim + FLIBS), but configure's Fortran probes do
    # — the OpenMP one in particular — and a failed link there captured
    # SHLIB_OPENMP_FFLAGS/R_OPENMP_FFLAGS/OPENMP_FCFLAGS as empty on the
    # first flang-zig osx-arm64 capture (2026-09-19), silently dropping
    # Fortran OpenMP for every user package on that platform. flang-pixi's
    # own CI sets SDKROOT for the same reason (FLANG_PIXI_HANDOFF.md §2).
    if [ "$OS" = macos ] && [ -z "${SDKROOT:-}" ] && command -v xcrun >/dev/null 2>&1; then
      SDKROOT="$(xcrun --show-sdk-path 2>/dev/null || true)"
      [ -n "$SDKROOT" ] && export SDKROOT && echo "SDKROOT=$SDKROOT (for flang's configure-time links)"
    fi
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

# BLAS/LAPACK: internal reference implementation by default; conda-forge
# openblas (which bundles LAPACK) when the openblas feature is active.
BLAS_ARGS=()
if [ "$BLAS" = openblas ]; then
  BLAS_ARGS+=("--with-blas=-lopenblas" "--with-lapack=-lopenblas")
fi

mkdir -p "$OBJ_DIR"
cd "$OBJ_DIR"

# GitHub's macos-15-intel runner image returns "unknown" from `uname -p`,
# and R's bundled config.guess defaults an unknown Darwin processor to
# powerpc — a real gen-config CI run detected build/host as
# powerpc64-apple-darwin24.6.0 on a genuine x86_64 runner, silently
# poisoning R_PLATFORM in every generated config header. Pass an explicit
# --build (from `uname -m`, mapping Darwin's "arm64" to config.guess's
# canonical "aarch64") only when the misdetection would happen; healthy
# machines keep using config.guess untouched.
BUILD_ARGS=()
if [ "$OS" = macos ] && [ "$(uname -p)" = unknown ]; then
  case "$(uname -m)" in
    x86_64) BUILD_ARGS+=("--build=x86_64-apple-darwin$(uname -r)") ;;
    arm64) BUILD_ARGS+=("--build=aarch64-apple-darwin$(uname -r)") ;;
  esac
  echo "note: uname -p is 'unknown' — overriding ${BUILD_ARGS[0]:-nothing} (config.guess would misdetect powerpc)"
fi

# OBJC/OBJCXX: without an explicit OBJC=, autoconf falls back to a bare
# PATH search and finds Xcode's real gcc/clang instead of our zig-cc shim
# (OBJCXX happens to end up right anyway, since autoconf's own default for
# it reuses $CXX — but that's not documented/guaranteed behavior, so set
# both explicitly). See F7.8 in feat-zig-build/TODO.md for the real
# failure (pak's bundled `ps` package) this was found from.
"$SRC_DIR/configure" \
  --prefix="$PREFIX" \
  "${BUILD_ARGS[@]}" \
  "${BLAS_ARGS[@]}" \
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
  OBJC="$TOOLCHAIN/zig-cc" \
  OBJCXX="$TOOLCHAIN/zig-cxx" \
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
echo "Configured (configure-only — no R source patches applied, no build run)."
echo "next: pixi run bash zigbuild/tools/gen-subst.sh"
