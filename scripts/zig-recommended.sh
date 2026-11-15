#!/usr/bin/env bash
# R's recommended packages (feat-recommended-packages PLAN.md): the 15
# that R's source carries as tarballs, installed by their own zig build
# (zigbuild/recommended/build.zig) in the order of R's own makefile, into
# env.sh's RECOMMENDED_PREFIX, dist/recommended/<flavor>/R-<ver>-zig: a
# tree of its own, so the R tree (the base) stays as it is. The R that
# installs them is the compile tree's (compile-tree.sh: the R tree plus
# the toolchain groups), whose make Matrix's makefile rules need. The
# conda build (recipe/build.sh) sets R_RECOMMENDED_PREFIX to its prefix,
# the env, which then is the R tree too: there the recipe's outputs
# divide the files (r-zig-recommended).
#
# Arguments go to zig build: `test` runs the build's unit tests (pixi run
# recommended-test) and installs nothing.
. "$(dirname "$0")/env.sh"

"$ZIG" version > /dev/null 2>&1 ||
  { echo "error: cannot run zig '$ZIG' (ZIG_BIN=${ZIG_BIN:-}, else zig on PATH)" >&2; exit 1; }
echo "r-zig: zig = $ZIG ($("$ZIG" version))"

# This zig build's own cache: env.sh's local cache, as the toolchain
# build's, not zigbuild/recommended/.zig-cache in the checkout.
zcache="$ZIG_LOCAL_CACHE_DIR"
[ "$OS" = windows ] && zcache="$(cygpath -m "$zcache")"

if [ "${1:-}" = test ]; then
  exec "$ZIG" build --build-file "$ROOT/zigbuild/recommended/build.zig" --cache-dir "$zcache" "$@"
fi

if [ -n "${R_RECOMMENDED_PREFIX:-}" ]; then
  rtree="$PREFIX"
else
  rtree="$COMPILE_TREE"
  test -d "$rtree/$RH" ||
    { echo "error: no compile tree at $rtree: run 'pixi run compile-tree' first" >&2; exit 1; }
  # R CMD INSTALL adds to a library and removes nothing it no longer
  # installs: a dev run starts from no tree. Never the env (above).
  rm -rf "$RECOMMENDED_PREFIX"
fi
mkdir -p "$RECOMMENDED_PREFIX"

# rzig's caches as contract-test.sh has them: zig cc's objects in env.sh's
# global cache, rzig's own under the workspace's build/rzig-cache
# (cache.zig's root reads XDG_CACHE_HOME first), not under $HOME; no
# ZIG_LOCAL_CACHE_DIR in rzig's environment, which would be zig cc's
# cache instead (this build's own is --cache-dir above).
unset ZIG_LOCAL_CACHE_DIR
cache="$BUILD_DIR/rzig-cache"
if [ "$OS" = windows ]; then
  cache="$(cygpath -w "$cache")"
  RECOMMENDED_PREFIX="$(cygpath -m "$RECOMMENDED_PREFIX")"
  rtree="$(cygpath -m "$rtree")"
  SRC_DIR="$(cygpath -m "$SRC_DIR")"
fi
export XDG_CACHE_HOME="$cache"

"$ZIG" build --build-file "$ROOT/zigbuild/recommended/build.zig" --cache-dir "$zcache" \
  "-Dprefix=$RECOMMENDED_PREFIX" "-Dr=$rtree" "-Dsrc=$SRC_DIR" "$@"
echo "== recommended packages installed into $RECOMMENDED_PREFIX/$RH/library (R: $rtree)"
