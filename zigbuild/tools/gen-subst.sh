#!/usr/bin/env bash
# Regenerate zigbuild/config/<plat>/subst.txt from a real config.status.
#
# build.zig replays configure's whole substitution table instead of hand-
# maintaining a variable list (see FINALIZATION.md F2.5). This script is
# the reproducible half of that: it dumps config.status's S["VAR"]="value"
# array, joins the awk-style backslash-newline continuation lines config.
# status wraps long values in (a naive `grep '^S\['` silently truncates
# those — e.g. R_LD_LIBRARY_PATH's ".../x86_64-unknown-linux-" + "gnu"),
# and swaps the six machine-specific absolute paths for @ZR_*@ placeholders
# so the vendored file works from any worktree/machine — build.zig's
# loadSubstTable() resolves them back at `zig build` time from the
# *current* env (CONDA_PREFIX, source tree, prefix, toolchain, project
# root), not the one config.status happened to run in.
#
# Usage: pixi run bash zigbuild/tools/gen-subst.sh [slim|full|...]
# Requires a real configure run first: `pixi run configure` (writes
# build/obj-<ver>-<flavor>/config.status).
. "$(dirname "$0")/../../scripts/env.sh"

CONFIG_STATUS="$OBJ_DIR/config.status"
test -f "$CONFIG_STATUS" || {
  echo "error: $CONFIG_STATUS not found — run 'pixi run configure' first" >&2
  exit 1
}

case "$(uname -m)" in
  x86_64) ARCH=x86_64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) ARCH="$(uname -m)" ;;
esac
case "$OS" in
  linux) PLAT="linux-$ARCH" ;;
  macos) PLAT="osx-$ARCH" ;;
  *) echo "error: unsupported OS '$OS' for subst.txt generation" >&2; exit 1 ;;
esac
OUT_DIR="$ROOT/zigbuild/config/$PLAT"
mkdir -p "$OUT_DIR"

# 1. Extract S["VAR"]="value" entries, joining continuation lines. A
#    continued entry ends its physical line in `"\` and the next physical
#    line starts with `"`; loop until a line ends in a bare `"`.
awk '
  /^S\["/ {
    full = $0
    while (full ~ /"\\$/) {
      if ((getline nxt) <= 0) break
      sub(/"\\$/, "", full)
      sub(/^"/, "", nxt)
      full = full nxt
    }
    print full
    next
  }
' "$CONFIG_STATUS" \
  | sed \
      -e "s|$CONDA_PREFIX|@ZR_CONDA@|g" \
      -e "s|$OBJ_DIR|@ZR_OBJ@|g" \
      -e "s|$SRC_DIR|@ZR_SRC@|g" \
      -e "s|$PREFIX|@ZR_PREFIX@|g" \
      -e "s|$TOOLCHAIN|@ZR_TOOLCHAIN@|g" \
      -e "s|$ROOT|@ZR_ROOT@|g" \
  > "$OUT_DIR/subst.txt"

echo "wrote $OUT_DIR/subst.txt ($(wc -l < "$OUT_DIR/subst.txt") entries)"
echo "next: copy config.h/Rconfig.h and bump GENERATED_FROM — see PLAN.md"
