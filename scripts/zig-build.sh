#!/usr/bin/env bash
# Milestone 5 entry point: build R entirely with zig build (no autoconf, no
# make). Wraps `zig build` so the zig cache lands in the workspace and the
# prefix matches the layout the make-driven pipeline used.
. "$(dirname "$0")/env.sh"

# (macOS fd ulimit for zig's linker opening ~300 libR objects at once is
# already raised unconditionally by env.sh, sourced above.)

# On Windows, conda-forge's own `zig` is only ever installed as
# Library/bin/zig.cmd|.bat — native cmd.exe/PowerShell resolve those via
# PATHEXT automatically, but MSYS bash (what this script runs under) does
# not, so a bare `zig` fails with "command not found" even though it's on
# PATH. Same fallback toolchain/zig-cc already uses for the same reason.
ZIG="${ZIG_BIN:-$(command -v zig || command -v x86_64-w64-mingw32-zig)}"

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"

# --- R source patches (feat-no-host-paths PLAN.md, phase F2) ---------------
# zigbuild/patches/R-<version>/*.patch, one file per concern, each saying
# what it changes and why. They change code the build compiles (libR, the
# internet module, base/tools/utils' .rdb files) and the bin/R and R CMD
# templates, so they go in before zig build: in order, with no fuzz, to a
# pristine source. The stamp records what the tree carries: empty after
# extraction (fetch-r.sh, recipe/build.sh), the series' sha256 list once
# applied. Anything else, no stamp included (a tree patched in place by an
# older zig-build.sh, an interrupted run, another series), is extracted
# again from the tarball first, so a changed patch never meets an old one.
# GNU patch comes with the env: conda-forge's patch, m2-patch on Windows.
patches="$ROOT/zigbuild/patches/R-$R_VERSION"
stamp="$SRC_DIR/.r-zig-patches"
series="$(cd "$patches" && sha256sum *.patch)"
applied="$(cat "$stamp" 2>/dev/null || echo none)"
if [ "$applied" != "$series" ]; then
  if [ -n "$applied" ]; then
    echo "r-zig: $SRC_DIR does not carry this patch series; extracting it again"
    rm -rf "$SRC_DIR"
    bash "$(dirname "$0")/fetch-r.sh"
  fi
  # no stamp while applying: an interrupted run extracts again next time
  rm -f "$stamp"
  for p in "$patches"/*.patch; do
    patch -p1 -f -F0 --no-backup-if-mismatch -d "$SRC_DIR" -i "$p" ||
      { echo "error: ${p##*/} did not apply to $SRC_DIR" >&2; exit 1; }
  done
  printf '%s\n' "$series" > "$stamp"
fi

# libc++ is linked statically, everywhere (decided 2026-09-30): R itself
# (libR, bin/exec/R, the modules) and, through toolchain/zig-cc|zig-cxx,
# every package compiled with it. Upstream zig does that on its own;
# conda-forge's zig links a shared libc++ whenever one sits in
# <zig lib dir>/../../lib (feedstock patch Lld.zig-prefer-shared-libcxx),
# which a macOS conda env always has. A ZIG_LIB_DIR mirror without it
# beside defeats the probe (flang-pixi handoff section 6). zig build's
# cache is not keyed on the probe's result, so a warm cache would hand
# back the shared-libc++ links: the mirror build gets its own local cache.
zl="${ZIG_LIB_DIR:-}"
[ -z "$zl" ] && [ -f "${ZIG%/*}/../lib/zig/std/std.zig" ] && zl="${ZIG%/*}/../lib/zig"
if [ -n "$zl" ]; then
  shared_cxx=""
  for e in libc++.1.dylib libc++.dylib libc++.so.1 libc++.so libc++.dll.a; do
    [ -e "$zl/../../lib/$e" ] && shared_cxx="$zl/../../lib/$e" && break
  done
  if [ -n "$shared_cxx" ] && [ "$OS" = windows ]; then
    # MSYS's ln -s copies, so no mirror here; no win-64 env has one today.
    echo "error: $shared_cxx would make zig link a shared libc++; remove the libcxx package from this env" >&2
    exit 1
  elif [ -n "$shared_cxx" ]; then
    zl="$(cd "$zl" && pwd -P)"
    mirror="$BUILD_DIR/zig-lib-static"
    rm -rf "$mirror"
    mkdir -p "$mirror/lib/zig"
    for e in "$zl"/*; do ln -s "$e" "$mirror/lib/zig/"; done
    export ZIG_LIB_DIR="$mirror/lib/zig"
    export ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR-static-libcxx"
    echo "r-zig: static libc++ (zig lib dir mirrored from $zl)"
  fi
fi

# The compile preflight's hint for a tree without the toolchain package:
# the conda build names r-zig-toolchain (recipe/recipe.yaml sets
# R_ZIG_CONDA_BUILD); the wheel sets its own; otherwise R's generic message.
hint=()
if [ -n "${R_ZIG_CONDA_BUILD:-}" ]; then
  hint=("-Dtoolchain-hint=add the r-zig-toolchain package to this environment (pixi add r-zig-toolchain, or conda install r-zig-toolchain)")
fi
"$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "${hint[@]}" "$@"

# The installed tree runs on its own (F1.3): R's rpaths are relative
# (build.zig relRPaths), so the env's libraries it needs go into
# <prefix>/lib. A no-op for the conda build, whose prefix is the env.
R_INSTALL_PREFIX="$PREFIX_ZIG" bash "$(dirname "$0")/vendor-libs.sh"
