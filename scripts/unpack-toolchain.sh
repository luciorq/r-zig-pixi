#!/usr/bin/env bash
# The toolchain tree again, $TOOLCHAIN_PREFIX (dist/toolchain/R-<ver>-zig,
# B36), from the group archives package-standalone.sh made
# (dist/R-<ver>-<platform>-<group>.<ext>, B17): in CI, the toolchain
# job's artifact, built once per platform (B31). Each archive's sha256 is
# checked, and its members must lie under its own group's directories, so
# the archives fill the tree without touching each other. Then the tree is
# removed (env.sh's own only, as zig-toolchain.sh does) and both archives
# are extracted into its parent.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"
# Windows: an override may be C:\...; basename and dirname want /c/... form.
command -v cygpath > /dev/null 2>&1 && TOOLCHAIN_PREFIX="$(cygpath -u "$TOOLCHAIN_PREFIX")"

[ "$(basename "$TOOLCHAIN_PREFIX")" = "$TOP" ] ||
  { echo "error: $TOOLCHAIN_PREFIX is not named $TOP, the archives' top directory (B36)" >&2; exit 1; }
tc="$TOP/$RH/bin/toolchain"
archives=()
for group in $TOOLCHAIN_GROUPS; do
  a="$ROOT/dist/R-$R_VERSION-$PLAT-$group.$ARCHIVE_EXT"
  test -f "$a" ||
    { echo "error: $a not found: run 'pixi run package-toolchain' (or download the toolchain job's artifact into dist/)" >&2; exit 1; }
  (cd "$ROOT/dist" && sha256sum -c --quiet "${a##*/}.sha256") ||
    { echo "error: ${a##*/} does not match ${a##*/}.sha256" >&2; exit 1; }
  dirs_re="$(group_dirs "$group" | tr ' ' '|')"
  bad="$(archive_files "$a" | grep -Ev "^${tc//./\\.}/($dirs_re)/" || true)"
  [ -z "$bad" ] ||
    { echo "error: ${a##*/} has members outside $tc/{${dirs_re//|/,}}/ (the $group group's directories):" >&2; echo "$bad" | sed 's/^/  /' >&2; exit 1; }
  archives+=("$a")
done

if [ -z "${R_TOOLCHAIN_PREFIX:-}" ]; then rm -rf "$TOOLCHAIN_PREFIX"; fi
parent="$(dirname "$TOOLCHAIN_PREFIX")"
mkdir -p "$parent"
for a in "${archives[@]}"; do
  echo "== extracting ${a##*/} into $parent"
  extract_archive "$a" "$parent"
done
echo "== toolchain tree $TOOLCHAIN_PREFIX: $(find "$TOOLCHAIN_PREFIX" ! -type d | wc -l | tr -d ' ') files"
