#!/usr/bin/env bash
# Run R's real `configure` against the pixi environment — nothing else.
# The sole reason this exists is to produce a config.status for
# gen-subst.sh to replay (see that script's own header comment and
# PLAN.md's "Regenerating the vendored config" section). It does NOT
# drive a full legacy build the way the old (Milestone 7-retired)
# scripts/configure-r.sh + scripts/build-r.sh pair did — this project's
# actual build path is `zig build` (scripts/zig-build.sh), which owns and
# applies the R-source patch series (zigbuild/patches/R-<version>/) that
# the old configure-r.sh also used to carry a duplicate copy of (two of
# them, back then) for the legacy path's benefit. Only one script should
# own those patches now that the legacy path is gone, so this one
# deliberately does not apply them.
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

# Autoconf "precious" variables: configure reads each one from the
# environment, records it in config_opts/R_CONFIG_ARGS and uses it, so
# whatever the capturing machine exports ends up in the vendored config
# and in every installed etc/Makeconf. JAVA_HOME did exactly that
# (GitHub's runners export a hostedtoolcache JDK path, which reached
# Makeconf, javaconf and ldpaths); R_PAPERSIZE, PKG_CONFIG_PATH, LIBS,
# TAR, BLAS_LIBS and the rest would too. Unset every variable configure
# --help lists as influential, before this script sets its own (FC is
# one of them): what configure needs is passed on its command line below,
# and shell variables set after the unset are not exported. R_SHELL is
# pinned there: left unset it becomes configure's own $SHELL, /bin/bash on
# Linux and /bin/sh on macOS, and it is bin/R's shebang. bin/R is POSIX sh
# (see zigbuild/patches/, bin-r-no-sed), as upstream R already runs it on
# macOS.
mapfile -t precious < <("$SRC_DIR/configure" --help | awk '
  /^Some influential environment variables:/ { on = 1; next }
  /^Use these variables/ { on = 0 }
  on && /^  [A-Za-z_][A-Za-z0-9_]*/ { print $1 }')
test "${#precious[@]}" -gt 20 || { echo "error: could not read configure's precious variables" >&2; exit 1; }
for v in "${precious[@]}"; do unset "$v"; done

# flang (flang-pixi's flang-zig), the only Fortran compiler; env.sh stops
# with an error when the env has none.
FC="$(fortran_compiler)"
CONDA="${CONDA_PREFIX:?pixi should set CONDA_PREFIX}"
FOPT="-O2"

# autoconf's AC_FC_LIBRARY_LDFLAGS mangles flang's verbose link output
# (emits a bogus '-lflang_rt.runtime:' with a trailing colon), so give
# configure the Fortran runtime libs explicitly.
rt=""
for f in "$CONDA"/lib/clang/*/lib/*/libflang_rt.runtime.a; do
  [ -f "$f" ] && rt="$f" && break
done
if [ -z "$rt" ]; then
  echo "error: libflang_rt.runtime not found under $CONDA/lib/clang — is flang-rt installed?" >&2
  exit 1
fi
FLIBS_ARGS=("FLIBS=-L$(dirname "$rt") -lflang_rt.runtime -lm")
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

# Per-variant configure flags. Capabilities are compile-time, so slim,
# full and minimal are distinct configure runs in distinct objdirs.
# GRAPHICS_ARGS sits where --with-cairo/--with-libpng always sat in the
# configure line below, so slim/full captures stay byte-identical.
GRAPHICS_ARGS=(--with-cairo --with-libpng)
VARIANT_ARGS=()
case "$VARIANT" in
  minimal)
    # The Python-wheel profile (pixi.toml's [feature.minimal]): everything
    # optional is switched off explicitly, not left to "not found" —
    # the toolchain's closure puts icu (conda-forge zig's LLVM, through
    # libxml2) and llvm-openmp (flang-rt-zig) in the env, and configure
    # would happily use them. OpenMP is off because an embedded R shares
    # its process with whatever libgomp/libomp the Python side has loaded.
    GRAPHICS_ARGS=(--without-cairo --without-libpng)
    VARIANT_ARGS+=(
      --without-tcltk
      --without-readline
      --disable-nls
      --without-jpeglib
      --without-libtiff
      --without-ICU
      --disable-openmp
      --without-libdeflate-compression
    )
    ;;
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
    echo "error: unknown R_BUILD_VARIANT '$VARIANT' (expected slim, full or minimal)" >&2
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

# macOS: always pass --build, without a Darwin version. config.guess
# appends the capturing machine's kernel release (`uname -r`), which then
# lands in R_PLATFORM/R_OS: R.version$platform, and every package's
# `Built:` field, said aarch64-apple-darwin25.6.0 for minimal and
# darwin25.4.0 for slim/full on the same platform, depending on which
# runner captured them. Every Darwin-version case in R's configure.ac and
# libtool.m4 matches only macOS 10.x (darwin1*, darwin5-9, darwin1[0-8]),
# so a version-less darwin takes the same branches as darwin24/25 did.
# Also covers GitHub's macos-15-intel image, whose `uname -p` says
# "unknown", which config.guess turned into powerpc64-apple-darwin24.6.0
# on a genuine x86_64 runner. Darwin's "arm64" is config.guess's
# canonical "aarch64".
BUILD_ARGS=()
if [ "$OS" = macos ]; then
  case "$(uname -m)" in
    x86_64) BUILD_ARGS+=("--build=x86_64-apple-darwin") ;;
    arm64) BUILD_ARGS+=("--build=aarch64-apple-darwin") ;;
    *) echo "error: unexpected macOS machine '$(uname -m)'" >&2; exit 1 ;;
  esac
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
  "${GRAPHICS_ARGS[@]}" \
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
  R_SHELL=/bin/sh \
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
