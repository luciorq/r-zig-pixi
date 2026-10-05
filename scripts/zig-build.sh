#!/usr/bin/env bash
# Milestone 5 entry point: build R entirely with zig build (no autoconf, no
# make). Wraps `zig build` so the zig cache lands in the workspace and the
# prefix matches the layout the make-driven pipeline used.
. "$(dirname "$0")/env.sh"

# (macOS fd ulimit for zig's linker opening ~300 libR objects at once is
# already raised unconditionally by env.sh, sourced above.)

# The zig that builds R: env.sh's $ZIG, ZIG_BIN or else the env's
# (conda-forge's or upstream, feat-no-host-paths F4), with the caches
# env.sh keeps for it. Printed, with its version and lib dir, as build.zig
# prints the Fortran compiler, so a build log always says which it was.
"$ZIG" version > /dev/null 2>&1 ||
  { echo "error: cannot run zig '$ZIG' (ZIG_BIN=${ZIG_BIN:-}, else zig on PATH)" >&2; exit 1; }
zig_lib="$("$ZIG" env | sed -n 's/^ *\.lib_dir = "\(.*\)",$/\1/p' | sed 's/\\\\/\\/g')"
echo "r-zig: zig = $ZIG ($("$ZIG" version); lib dir $zig_lib)"

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

# libc++ is linked statically, everywhere (decided 2026-09-30), also with
# conda-forge's zig, which links a shared one when it finds one beside
# its lib dir: build.zig gives R's links a mirror of that lib dir
# (staticLibcxxLibDir), rzig does the same for packages, one
# implementation for both (zigbuild/tools/rzig/libcxx_mirror.zig; F4).

# The conda build (recipe/recipe.yaml sets R_ZIG_CONDA_BUILD): the compile
# preflight's hint names r-zig-toolchain (the wheel sets its own; otherwise
# R's generic message). Nothing else depends on this flag: rzig decides a
# conda env's rpath where it runs (F3b), and what a standalone tree takes
# from the env (build.zig's installEnvRuntime, vendor-libs.sh) is left out
# because the prefix is the env, not because of the flag.
conda=()
if [ -n "${R_ZIG_CONDA_BUILD:-}" ]; then
  conda=("-Dtoolchain-hint=add the r-zig-toolchain package to this environment (pixi add r-zig-toolchain, or conda install r-zig-toolchain)")
fi

# The installed tree runs on its own, and is the tree that ships (F1.3,
# F1.7): the env's shared libraries it needs go into it, <prefix>/lib on
# unix (R's rpaths are relative, build.zig relRPaths), R_HOME/bin/x64 on
# Windows (vendor-libs.sh). After the build, for what it built; and
# before it on a tree an earlier build left, because the build runs R
# from the tree (the bootstrap, check) and a copy in the tree comes
# before the env's library (Windows: bin/x64 before PATH; macOS: the
# rpath before the fallback path): after a `pixi update` it would be the
# env's old one. A no-op for the conda build, whose prefix is the env.
R_INSTALL_PREFIX="$PREFIX_ZIG" bash "$(dirname "$0")/vendor-libs.sh"
"$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "${conda[@]}" "$@"
R_INSTALL_PREFIX="$PREFIX_ZIG" bash "$(dirname "$0")/vendor-libs.sh"
