#!/usr/bin/env bash
# The toolchain tree (feat-standalone-toolchain B30): the toolchain
# groups' third-party files from this env, each directory with SOURCES and
# LICENSES/, installed by their own zig build
# (zigbuild/toolchain/build.zig, PHASE3 open point A (a)) into env.sh's
# TOOLCHAIN_PREFIX, dist/toolchain/R-<ver>-zig (B36). Needs no R source.
# One tree per platform serves every flavor; package-standalone.sh's
# toolchain mode archives its groups (B17).
#
# Arguments go to zig build: `test` runs the build's unit tests (pixi run
# toolchain-test) and installs nothing.
. "$(dirname "$0")/env.sh"

"$ZIG" version > /dev/null 2>&1 ||
  { echo "error: cannot run zig '$ZIG' (ZIG_BIN=${ZIG_BIN:-}, else zig on PATH)" >&2; exit 1; }
echo "r-zig: zig = $ZIG ($("$ZIG" version))"

# zig's install never removes a file it no longer installs, so a plain
# install starts from no tree. Only env.sh's own tree: R_TOOLCHAIN_PREFIX
# may name the conda env (recipe/build.sh), which is never removed.
if [ "${1:-}" != test ] && [ -z "${R_TOOLCHAIN_PREFIX:-}" ]; then
  rm -rf "$TOOLCHAIN_PREFIX"
fi
"$ZIG" build --build-file "$ROOT/zigbuild/toolchain/build.zig" --prefix "$TOOLCHAIN_PREFIX" "$@"
