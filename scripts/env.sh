# Shared environment for build scripts. Source this; do not execute it.
# Every tool referenced here comes from the pixi environment (conda-forge).
set -euo pipefail

ROOT="${PIXI_PROJECT_ROOT:?run scripts through 'pixi run <task>'}"
R_VERSION="${R_VERSION:?set in pixi.toml [activation.env]}"

# On Windows (msys bash) normalize C:\... to /c/... — GNU tar treats a
# colon in a path as a remote-host spec, and mixed separators confuse make.
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -u "$ROOT")"
fi

# Build variant: "slim" (default env) or "full" (pixi run -e full ...).
# Set through [feature.full-build.activation.env] in pixi.toml.
VARIANT="${R_BUILD_VARIANT:-slim}"

# BLAS flavor: "internal" (R's reference BLAS) or "openblas"
# (feature.openblas activation). Each flavor gets its own objdir/prefix.
BLAS="${R_BLAS:-internal}"
FLAVOR="$VARIANT"
[ "$BLAS" != internal ] && FLAVOR="$VARIANT-$BLAS"

BUILD_DIR="$ROOT/build"
SRC_DIR="$BUILD_DIR/R-$R_VERSION"
OBJ_DIR="$BUILD_DIR/obj-$R_VERSION-$FLAVOR"
# R_INSTALL_PREFIX override: the conda recipe installs into rattler's $PREFIX
PREFIX="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR}"
TOOLCHAIN="$ROOT/toolchain"
TARBALL="$BUILD_DIR/R-$R_VERSION.tar.gz"
CRAN_URL="https://cran.r-project.org/src/base/R-4/R-$R_VERSION.tar.gz"
CHECKSUM_FILE="$ROOT/scripts/checksums/R-$R_VERSION.sha256"

# Keep zig's compilation cache inside the workspace, not in $HOME.
export ZIG_GLOBAL_CACHE_DIR="$BUILD_DIR/zig-cache/global"
export ZIG_LOCAL_CACHE_DIR="$BUILD_DIR/zig-cache/local"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  *) OS=unknown ;;
esac

# macOS defaults to 256 open files; zig's linker opens every object of
# libR at once (~300+) and fails with ProcessFdQuotaExceeded without this.
ulimit -n 4096 2>/dev/null || true

# Windows R's tcltk .onLoad expects CRAN's bundled R_HOME/Tcl unless
# MY_TCLTK is set — point it at conda-forge's Tcl instead.
if [ "$OS" = windows ] && [ -n "${CONDA_PREFIX:-}" ]; then
  export MY_TCLTK=yes
  export TCL_LIBRARY="$CONDA_PREFIX/Library/lib/tcl8.6"
fi

# Hermetic PATH: only the pixi environment, plus /usr/bin:/bin as last
# resort for kernel-level needs (#!/bin/sh shebangs inside generated
# scripts resolve absolutely anyway). Keeps host tools like a user TeX
# or ~/.local/bin out of configure's sight.
if [ "$OS" != windows ] && [ -n "${CONDA_PREFIX:-}" ]; then
  # BUILD_PREFIX: in a rattler-build/conda-build run the compilers live
  # in a separate build env — keep it on PATH there.
  export PATH="$CONDA_PREFIX/bin${BUILD_PREFIX:+:$BUILD_PREFIX/bin}:/usr/bin:/bin"
fi

njobs() {
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4
}

# flang on linux-64/win-64, gfortran on osx-*/linux-aarch64 (see pixi.toml)
fortran_compiler() {
  if command -v flang >/dev/null 2>&1; then echo flang
  elif command -v flang-new >/dev/null 2>&1; then echo flang-new
  elif command -v gfortran >/dev/null 2>&1; then echo gfortran
  else
    echo "error: no Fortran compiler in the pixi environment" >&2
    return 1
  fi
}

require_not_windows() {
  if [ "$OS" = windows ]; then
    echo "R's autoconf build does not run on Windows yet; the gnuwin32 +" >&2
    echo "zig toolchain path is milestone 2 — see PLAN.md and TODO.md." >&2
    exit 1
  fi
}
