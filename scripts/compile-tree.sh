#!/usr/bin/env bash
# The compile tree (PHASE3 open point B (a)), env.sh's COMPILE_TREE,
# build/compile-tree/<flavor>/R-<ver>-zig: a fresh copy of the flavor's R
# tree ($PREFIX) with the toolchain tree's group directories in its
# R_HOME/bin/toolchain, every one but zig/ and flang/ (C12): in phase 3
# openmp/, and unix usr/ or Windows binutils/. contract and stress compile
# packages with it (their pixi tasks depend on compile-tree), as a user
# who extracted the base and both group archives into one directory does.
#
# Why a copy: the R tree is the base alone, rzig the only file in its
# R_HOME/bin/toolchain (feat-standalone-toolchain B19, B30), and Windows'
# Makeconf names the build-tools group's binutils by their path under
# R_HOME (B24, B41). With the R tree alone a package's DLL links there
# without $(NM), which winshlib.mk pipes into sed, and passes: contract
# would prove nothing (C11). With openmp/, rzig's B40 rule runs on every
# leg: it counts openmp/ where the base has the libomp runtime (slim,
# full) and leaves it alone on minimal (C12). zig/ and flang/ (phases 5
# and 6) stay out, so dev compiles keep the zig that built R and the
# env's flang (B30). The R tree and the toolchain tree are only read:
# verify-tree, hermetic and package see the base, verify-toolchain and
# package-toolchain the groups.
. "$(dirname "$0")/env.sh"

# Windows: an override may be C:\...; cp and the messages want /c/....
if command -v cygpath > /dev/null 2>&1; then
  PREFIX="$(cygpath -u "$PREFIX")"
  TOOLCHAIN_PREFIX="$(cygpath -u "$TOOLCHAIN_PREFIX")"
fi
test -d "$PREFIX/$RH" || { echo "error: no R tree at $PREFIX ($RH missing): run 'pixi run build' first" >&2; exit 1; }
groups="$TOOLCHAIN_PREFIX/$RH/bin/toolchain"
tools=""
for d in $(group_dirs build-tools); do
  if [ -d "$groups/$d" ]; then tools=1; fi
done
[ -n "$tools" ] ||
  { echo "error: no build-tools directory ($(group_dirs build-tools | tr ' ' ,)) in $groups: run 'pixi run toolchain' (or 'pixi run unpack-toolchain')" >&2; exit 1; }

rm -rf "$COMPILE_TREE"
mkdir -p "$(dirname "$COMPILE_TREE")"
# cp -a (macOS: -pPR): links stay links, modes stay. The tree resolved
# first, so a prefix that is a link is copied, not the link.
cp -a "$(cd "$PREFIX" && pwd -P)" "$COMPILE_TREE"
copied=""
for g in $TOOLCHAIN_GROUPS; do
  for d in $(group_dirs "$g"); do
    case "$d" in zig|flang) continue ;; esac
    [ -d "$groups/$d" ] || continue
    cp -a "$groups/$d" "$COMPILE_TREE/$RH/bin/toolchain/"
    copied="$copied $d/"
  done
done
echo "== compile tree $COMPILE_TREE: $PREFIX, and$copied from $groups"
