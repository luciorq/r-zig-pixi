#!/usr/bin/env bash
# The standalone archives (feat-standalone-toolchain B17), each with its
# .sha256 and the top directory every archive has, R-<ver>-zig/ (B1,
# B36), so that they extract into one directory. Only archives: every
# file is one an installed tree has, which the checks saw there.
#
# Usage: package-standalone.sh [base|toolchain]
#   base (default; pixi run package): the installed R tree in $PREFIX,
#     the tree that ships (feat-no-host-paths PLAN.md, F1 and F1.7), as
#     dist/R-<ver>-<flavor>-<platform>.tar.gz (Windows: .zip).
#   toolchain (pixi run package-toolchain): the toolchain tree in
#     $TOOLCHAIN_PREFIX (zig-toolchain.sh, B30), one archive per group,
#     dist/R-<ver>-<platform>-<group>.<ext>, with the group's directories
#     under R_HOME/bin/toolchain (env.sh's group_dirs). <ext> is env.sh's
#     group_ext: .tar.xz for the compilers on every platform (PHASE6 open
#     point L), .tar.gz (Windows: .zip) for build-tools. No flavor in the
#     name: one toolchain serves every flavor of the platform.
# Nothing is added to the R tree here, on any OS: zig build installs it
# with the runtime data it needs from the env (build.zig's
# installEnvRuntime: the CA bundle, fontconfig's configuration, Windows'
# Tcl/Tk), and zig-build.sh runs vendor-libs.sh after every build to copy
# the env's shared libraries into it. So the checks that run on the
# installed tree before this (verify-tree, smoke, check, hermetic) saw
# exactly what is archived; contract compiles with a copy of it with the
# toolchain groups added, the compile tree (compile-tree.sh, PHASE3 open
# point B). vendor-libs.sh is not run again here: one place does it, and
# the pixi task `package` depends on `build`, which runs it. Likewise the
# toolchain tree is archived as zig-toolchain.sh installed it
# (`package-toolchain` depends on `toolchain`), which verify-toolchain.sh
# checks.
. "$(dirname "$0")/env.sh"

mode="${1:-base}"
case "$mode" in
  base) tree="$PREFIX"; what="R tree"; build_task=build ;;
  toolchain) tree="$TOOLCHAIN_PREFIX"; what="toolchain tree"; build_task=toolchain ;;
  *) echo "usage: package-standalone.sh [base|toolchain]" >&2; exit 2 ;;
esac
# Windows: an override may be C:\...; basename and dirname want /c/... form.
command -v cygpath > /dev/null 2>&1 && tree="$(cygpath -u "$tree")"
test -d "$tree/$RH" || { echo "error: no $what at $tree; run 'pixi run $build_task' first" >&2; exit 1; }
# A tree is archived from its parent, so its own name is the archive's top
# directory: env.sh's prefixes have it (dist/<flavor>/R-<ver>-zig,
# dist/toolchain/R-<ver>-zig), an R_INSTALL_PREFIX or R_TOOLCHAIN_PREFIX
# of another name does not.
[ "$(basename "$tree")" = "$TOP" ] ||
  { echo "error: $tree is not named $TOP, the archives' top directory (B36): install the tree into a directory of that name" >&2; exit 1; }
parent="$(cd "$tree/.." && pwd)"
mkdir -p "$ROOT/dist"

# archive <file> <member>...: the members (paths relative to $parent) as
# one archive, plus its sha256, named by its basename in the checksum line
# (sha256sum -c next to it).
archive() {
  local artifact="$1"
  shift
  echo "== creating $artifact"
  rm -f "$artifact" "$artifact.sha256"
  if [ "${artifact##*.}" = zip ]; then
    (cd "$parent" && zip -qr "$artifact" "$@")
  elif [ "${artifact##*.}" = xz ]; then
    # one level for every platform; -T0: as many threads as xz finds
    # cores and memory for (PHASE6 risk 7)
    tar -cf - -C "$parent" "$@" | xz -9 -T0 > "$artifact"
  else
    tar -czf "$artifact" -C "$parent" "$@"
  fi
  (cd "$ROOT/dist" && sha256sum "${artifact##*/}") > "$artifact.sha256"
  # the file's size in bytes, which B13's measurements record: du gives
  # the space on disk, which a compressing filesystem shrinks (512 for a
  # 95 MB .tar.xz on gamma); tr drops the spaces BSD wc puts before it
  echo "== done: $(wc -c < "$artifact" | tr -d ' ') bytes $(cat "$artifact.sha256")"
}

if [ "$mode" = base ]; then
  archive "$ROOT/dist/R-$R_VERSION-$FLAVOR-$PLAT.$ARCHIVE_EXT" "$TOP"
  exit 0
fi

# The toolchain tree holds only group directories under
# R_HOME/bin/toolchain, so the group archives together hold all of it: a
# file anywhere else would be in no archive. A group with no directory
# would make an archive with nothing in it.
tc="$RH/bin/toolchain"
known=()
for group in $TOOLCHAIN_GROUPS; do
  for d in $(group_dirs "$group"); do known+=(-path "$tree/$tc/$d" -o); done
done
outside="$(find "$tree" \( "${known[@]}" -false \) -prune -o ! -type d -print)"
if [ -n "$outside" ]; then
  echo "error: files of the toolchain tree outside every group directory ($(for g in $TOOLCHAIN_GROUPS; do group_dirs "$g"; done | tr '\n' ' ')under $tc), which no archive would hold:" >&2
  while IFS= read -r f; do echo "  ${f#"$tree"/}"; done <<< "$outside" >&2
  exit 1
fi
# A group's members: its directories the tree has, as archive paths.
group_members() {
  local d
  for d in $(group_dirs "$1"); do
    if [ -d "$tree/$tc/$d" ]; then echo "$TOP/$tc/$d"; fi
  done
}
for group in $TOOLCHAIN_GROUPS; do
  [ -n "$(group_members "$group")" ] ||
    { echo "error: the toolchain tree $tree has no directory of the $group group ($(group_dirs "$group") under $tc)" >&2; exit 1; }
done
for group in $TOOLCHAIN_GROUPS; do
  archive "$ROOT/dist/R-$R_VERSION-$PLAT-$group.$(group_ext "$group")" $(group_members "$group")
done
