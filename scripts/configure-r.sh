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

# BLAS/LAPACK: internal reference implementation by default; conda-forge
# openblas (which bundles LAPACK) when the openblas feature is active.
BLAS_ARGS=()
if [ "$BLAS" = openblas ]; then
  BLAS_ARGS+=("--with-blas=-lopenblas" "--with-lapack=-lopenblas")
fi

# base::Sys.which() bakes configure's absolute path to `which` as a
# literal string constant, compiled into base's serialized R data
# (base.rdb) — unlike shell scripts this can't be sed-patched after the
# fact. It's load-bearing: utils's .onLoad -> .osVersion() -> Sys.which
# ("uname") fails hard the moment the tree moves (breaks EVERY package
# load, not just Sys.which callers). Patch the source to prefer a
# bundled `which` (stage.sh bundles one into R_HOME/bin/toolchain),
# falling back to whatever configure finds — idempotent.
sw="$SRC_DIR/src/library/base/R/unix/system.unix.R"
if [ -f "$sw" ] && ! grep -q 'bin/toolchain/which' "$sw"; then
  sed -i \
    's|which <- "@WHICH@"|which <- { w <- file.path(R.home(), "bin", "toolchain", "which"); if (file.exists(w)) w else "@WHICH@" }|' \
    "$sw"
fi

# R_LIBS_USER_default() (library.R): same "compiled into base.rdb" patch
# as scripts/zig-build.sh applies — kept in sync here so the legacy
# fallback path behaves identically. See zig-build.sh's own comment for
# the full rationale (XDG base dir spec on unix, LOCALAPPDATA unchanged
# on Windows).
lu="$SRC_DIR/src/library/base/R/library.R"
if [ -f "$lu" ] && ! grep -q '"win-64-zig"' "$lu"; then
  r_libs_user_repl=$(cat <<'RCODE'
    R_LIBS_USER_default <- function() {
        home <- normalizePath("~", mustWork = FALSE)  # possibly /nonexistent
        ## FIXME: could re-use v from "above".
        x.y <- paste(R.version$major, sep=".",
                     strsplit(R.version$minor, ".", fixed=TRUE)[[1L]][1L])
        if(.Platform$OS.type == "windows" && s["machine"] == "x86-64")
            file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-64-zig", x.y)
        else if (.Platform$OS.type == "windows") # including aarch64
            file.path(Sys.getenv("LOCALAPPDATA"), "R",
                      paste0("win-", s["machine"], "-zig"), x.y)
        else {
            xdg <- Sys.getenv("XDG_DATA_HOME")
            data_home <- if (nzchar(xdg)) xdg else file.path(home, ".local", "share")
            plat <- if (s["sysname"] == "Darwin")
                        paste0("osx-", if (s["machine"] == "arm64") "arm64" else "64", "-zig")
                    else if (s["sysname"] == "Linux") "linux-64-zig"
                    else paste0(R.version$platform, "-zig")
            file.path(data_home, "R", plat, x.y)
        }
    }
RCODE
  )
  awk -v repl="$r_libs_user_repl" '
    BEGIN { in_block=0 }
    /R_LIBS_USER_default <- function\(\) \{/ { print repl; in_block=1; next }
    in_block && /^    \}$/ { in_block=0; next }
    in_block { next }
    { print }
  ' "$lu" > "$lu.tmp" && mv "$lu.tmp" "$lu"
fi

mkdir -p "$OBJ_DIR"
cd "$OBJ_DIR"

# OBJC/OBJCXX: without an explicit OBJC=, autoconf falls back to a bare
# PATH search and finds Xcode's real gcc/clang instead of our zig-cc shim
# (OBJCXX happens to end up right anyway, since autoconf's own default for
# it reuses $CXX — but that's not documented/guaranteed behavior, so set
# both explicitly). Found via a real compile failure: pak's bundled `ps`
# package has genuine Objective-C source (arch/macos/apps.m, using AppKit
# for GUI-app enumeration) that was silently being compiled as plain C by
# whatever real "gcc" was on PATH in the vendored subst.txt's OBJC value —
# harmless to CC/CXX themselves (which correctly pointed at zig-cc/zig-cxx
# already), but this variable never got the same treatment.
"$SRC_DIR/configure" \
  --prefix="$PREFIX" \
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
echo "Configured. Capability summary:"
sed -n '/R is now configured/,$p' config.log 2>/dev/null || true
