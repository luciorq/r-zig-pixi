#!/usr/bin/env bash
# Regenerate zigbuild/config/<plat>-<variant>/subst.txt from a real
# config.status.
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
# Usage: pixi run bash zigbuild/tools/gen-subst.sh
#        pixi run -e full bash zigbuild/tools/gen-subst.sh
# Requires a real configure run first for the same variant/env
# (`pixi run configure` / `pixi run -e full configure`), which writes
# build/obj-<ver>-<flavor>/config.status — env.sh's VARIANT/OBJ_DIR
# already reflect which pixi environment this runs under.
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
OUT_DIR="$ROOT/zigbuild/config/$PLAT-$VARIANT"
mkdir -p "$OUT_DIR"

# 1. Extract S["VAR"]="value" entries, joining continuation lines. A
#    continued entry ends its physical line in `"\` and the next physical
#    line starts with `"`; loop until a line ends in a bare `"`.
#
#    The last two sed expressions drop every conda cross-toolchain
#    *sysroot* directory (`<conda>/<triple>/sysroot/{lib64,usr/lib64,...}`)
#    from the captured values — both as `-L` link flags (FLIBS,
#    FLIBS_IN_SO, FCLIBS) and as `:`-separated runtime entries
#    (R_LD_LIBRARY_PATH). On gfortran platforms (linux-aarch64 today)
#    autoconf's AC_FC_LIBRARY_LDFLAGS copies gfortran's implicit search
#    dirs verbatim, and conda-forge's sysroot package ships a complete
#    glibc runtime there (lib64/libc.so.6, ld-linux-*.so, libm.so.6, from
#    the CentOS-era sysroot). R's etc/ldpaths exports R_LD_LIBRARY_PATH
#    into LD_LIBRARY_PATH, so with those entries kept every R process
#    loaded the sysroot's libc.so.6 under the host's ld.so and died in
#    startup — the "SIGILL/SIGSEGV at 'R bootstrap: tools sysdata'"
#    failure on ubuntu-24.04-arm. Those dirs are only meaningful to gcc's
#    own --sysroot link step; zig cc brings its own libc, and libgfortran
#    lives in the retained lib/gcc/<triple>/<ver> entry, so dropping them
#    loses nothing at link time either. linux-64 (flang) never had them.
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
      -e 's| -L[^ "]*/sysroot/[^ "]*||g' \
      -e 's|:[^:"]*/sysroot/[^:"]*||g' \
  > "$OUT_DIR/subst.txt"

echo "wrote $OUT_DIR/subst.txt ($(wc -l < "$OUT_DIR/subst.txt") entries)"

# Stage the other three files of a complete vendored config dir from the
# same objdir, so one run of this script produces the whole thing (used
# to be a manual "next: copy config.h/Rconfig.h and bump GENERATED_FROM"
# step — folding it in here keeps R_VERSION/OBJ_DIR ownership in env.sh,
# the single source of truth, instead of every caller re-deriving them;
# gen-config.yaml's CI staging step hardcoded "4.6.1" twice before this).
#
# Rconfig.h is NOT configure-generated (only config.h is, via
# AC_CONFIG_HEADERS) — a plain `make` derives it from config.h with
# tools/GETCONFIG (src/include/Makefile.in's own rule, a grep-and-echo
# script reading ./config.h from cwd). A configure-only objdir has no
# Rconfig.h to copy (found via a real gen-config CI failure: `cp: cannot
# stat .../Rconfig.h`), so run GETCONFIG here exactly as make would.
cp "$OBJ_DIR/src/include/config.h" "$OUT_DIR/config.h"
(cd "$OBJ_DIR/src/include" && sh "$SRC_DIR/tools/GETCONFIG" > "$OUT_DIR/Rconfig.h")
echo "$R_VERSION" > "$OUT_DIR/GENERATED_FROM"
echo "staged config.h + Rconfig.h + GENERATED_FROM ($R_VERSION) into $OUT_DIR"
