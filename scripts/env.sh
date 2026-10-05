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

# Build variant: "slim" (default env), "full" (pixi run -e full ...) or
# "minimal" (pixi run -e minimal ..., the r-zig wheel's profile). Set
# through the features' activation.env in pixi.toml.
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
# The bash compiler shims, for configure-only.sh's capture (gen-subst.sh
# turns this path into @ZR_TOOLCHAIN@). What gets installed is rzig
# (zigbuild/tools/rzig/), which parity-test.sh holds to these.
TOOLCHAIN="$ROOT/toolchain"
TARBALL="$BUILD_DIR/R-$R_VERSION.tar.gz"
CRAN_URL="https://cran.r-project.org/src/base/R-4/R-$R_VERSION.tar.gz"
CHECKSUM_FILE="$ROOT/scripts/checksums/R-$R_VERSION.sha256"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  *) OS=unknown ;;
esac

# R_HOME is <prefix>/lib/R on unix. On Windows this MUST NOT be "lib/R":
# NTFS is case-insensitive, and a real conda/pixi env already has a
# top-level "Lib" (capital L, Python's stdlib) by the time R installs —
# "mkdir -p $PREFIX/lib/R" silently resolves into that SAME directory,
# dumping R's entire tree inside Python's site-packages and leaving it
# nowhere PATH-visible (found via a real `pixi add`-installed env; never
# reproduced by this project's own dist/ test runs, which have no
# pre-existing Python Lib to collide with). "Library/" is the standard
# conda-forge convention for non-Python Windows packages and doesn't
# collide with anything.
if [ "$OS" = windows ]; then
  R_HOME_DIR="$PREFIX/Library/lib/R"
else
  R_HOME_DIR="$PREFIX/lib/R"
fi

# macOS defaults to 256 open files; zig's linker opens every object of
# libR at once (~300+) and fails with ProcessFdQuotaExceeded without this.
ulimit -n 4096 2>/dev/null || true

# Hermetic PATH: only the pixi environment, plus /usr/bin:/bin as last
# resort for kernel-level needs (#!/bin/sh shebangs inside generated
# scripts resolve absolutely anyway). Keeps host tools like a user TeX
# or ~/.local/bin out of configure's sight.
if [ "$OS" != windows ] && [ -n "${CONDA_PREFIX:-}" ]; then
  # BUILD_PREFIX: in a rattler-build/conda-build run the compilers live
  # in a separate build env — keep it on PATH there.
  export PATH="$CONDA_PREFIX/bin${BUILD_PREFIX:+:$BUILD_PREFIX/bin}:/usr/bin:/bin"
fi

# The zig the scripts run (zig-build.sh, rzig's test.sh, verify-bundle's
# compiles), found as rzig finds it (zigbuild/tools/rzig/find_zig.zig):
# ZIG_BIN, else zig on PATH, the env's (conda-forge's). R builds with
# conda-forge's zig and with upstream zig, the ziglang.org release, which
# PyPI's ziglang is (feat-no-host-paths F4): with ZIG_BIN=<its path>
# (`pixi run fetch-zig` prints one) the pipeline tasks that run zig
# (build, check, rzig-test, contract, verify-package) build, compile and
# test with it. Not conda-package, whose rattler-build gives the recipe a
# clean environment and so its build env's zig, nor wheel-test, which
# compiles with the venv's ziglang. On win-64 conda-forge's real binary is
# x86_64-w64-mingw32-zig: its `zig` is a .bat, which MSYS bash cannot run.
# Empty with no zig at all (scripts that run none still work).
#
# Always an absolute path, so that it names the same zig from every
# directory: rzig resolves ZIG_BIN from its working directory, which R
# CMD and verify-bundle's compiles change, and quietly takes PATH's zig,
# the env's, when it finds nothing there. So a bare name in ZIG_BIN is
# looked up on PATH, a relative path is taken from here (the project
# root, where pixi runs tasks), a ZIG_BIN that does not run stops here,
# and ZIG_BIN is exported as the result (C:/... on Windows, as fetch-zig
# prints it), the file that builds R and keys its caches below.
if [ -n "${ZIG_BIN:-}" ]; then
  case "$ZIG_BIN" in
    */*|*\\*) ZIG="$ZIG_BIN" ;;
    *) ZIG="$(command -v "$ZIG_BIN" || true)" ;;
  esac
else
  ZIG="$(command -v zig || command -v x86_64-w64-mingw32-zig || true)"
fi
case "$ZIG" in
  ''|/*|[A-Za-z]:[/\\]*) ;;
  *) ZIG="$PWD/${ZIG#./}" ;;
esac
if [ -n "${ZIG_BIN:-}" ]; then
  if ! "$ZIG" version > /dev/null 2>&1; then
    echo "error: ZIG_BIN=$ZIG_BIN names no zig that runs (from $PWD)" >&2
    exit 1
  fi
  if command -v cygpath > /dev/null 2>&1; then ZIG="$(cygpath -m "$ZIG")"; fi
  export ZIG_BIN="$ZIG"
fi

# zig's caches: inside the workspace, not in $HOME, and one per zig. zig's
# cache knows zig's version, not which build of it, so conda-forge's
# 0.16.0 and upstream's 0.16.0 handed each other their objects (2026-10-04:
# one checkout gave a tree of upstream's LLD over conda clang's cached C
# objects). The key is the zig binary's cksum (CRC and size), cheap and
# portable: another build of zig at the same path, as a pixi update
# installs, gets caches of its own too.
zig_key="$({ cksum < "$ZIG"; } 2>/dev/null | tr ' ' -)" || zig_key=""
export ZIG_GLOBAL_CACHE_DIR="$BUILD_DIR/zig-cache/zig-${zig_key:-none}/global"
export ZIG_LOCAL_CACHE_DIR="$BUILD_DIR/zig-cache/zig-${zig_key:-none}/local"

njobs() {
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4
}

# macOS deployment target: build.zig's macos_min, the shims'
# "<arch>-native.13.0". The checks assert every Mach-O is at or below it.
MACOS_MIN=13.0
# A Mach-O file's minos (LC_BUILD_VERSION; LC_VERSION_MIN_MACOSX on old
# files), empty when it has neither.
macho_minos() {
  otool -l "$1" 2>/dev/null | awk '
    /cmd LC_BUILD_VERSION/      { b = 1; next }
    /cmd LC_VERSION_MIN_MACOSX/ { v = 1; next }
    b && $1 == "minos"   { print $2; exit }
    v && $1 == "version" { print $2; exit }'
}
# True when version $1 is above $2 (MAJOR.MINOR[.PATCH]), without sort -V.
version_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 1 }'
}

# flang where the env provides it (flang-pixi's flang-zig on every
# platform, see pixi.toml), else gfortran. Same probe order as build.zig's
# FortranCompiler selection.
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
