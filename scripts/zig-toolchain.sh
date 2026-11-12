#!/usr/bin/env bash
# The toolchain tree (feat-standalone-toolchain B30): the toolchain
# groups' third-party files from this env, each directory with SOURCES and
# LICENSES/, installed by their own zig build
# (zigbuild/toolchain/build.zig, PHASE3 open point A (a)) into env.sh's
# TOOLCHAIN_PREFIX, dist/toolchain/R-<ver>-zig (B36). Needs no R source.
# One tree per platform serves every flavor; package-standalone.sh's
# toolchain mode archives its groups (B17). The compilers group's zig/ is
# upstream zig, PyPI's ziglang wheel as fetch-zig.sh pins and unpacks it
# (B4, phase 5), whose directory this passes to the build as
# -Dziglang=<dir>; the other directories come from the env.
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

# The compilers group's zig/ (B4, phase 5): PyPI's ziglang wheel as
# fetch-zig pins and unpacks it, whose directory the build reads. Not for
# the unit tests, and not when the prefix is the env (the conda build,
# recipe/build.sh): conda keeps conda-forge's zig (B30) and its build
# reaches no PyPI. build.zig decides what is installed (prefix_is_env,
# the same test by real path as same_dir here, PHASE5 open point J); this
# only decides whether to download, so the two must agree.
ziglang=()
if [ "${1:-}" != test ] && ! same_dir "$TOOLCHAIN_PREFIX" "${CONDA_PREFIX:-}"; then
  zig_path="$(bash "$ROOT/scripts/fetch-zig.sh")"
  ziglang=("-Dziglang=$(dirname "$(dirname "$zig_path")")")
  echo "r-zig: the toolchain's zig/ from ${ziglang[0]#-Dziglang=}"
fi
# -Dprefix: the same directory as --prefix, which zig 0.17's configure step
# does not see (the maker installs there); the build reads the env's
# records for it and compares it with the env (prefix_is_env).
"$ZIG" build --build-file "$ROOT/zigbuild/toolchain/build.zig" --prefix "$TOOLCHAIN_PREFIX" "-Dprefix=$TOOLCHAIN_PREFIX" "${ziglang[@]}" "$@"
