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

# The Sys.which source patch from configure-r.sh must be present in the
# source tree for relocatable installs (see PLAN.md of feat-initial-setup).
sw="$SRC_DIR/src/library/base/R/unix/system.unix.R"
if [ -f "$sw" ] && ! grep -q 'bin/toolchain/which' "$sw"; then
  sed -i \
    's|which <- "@WHICH@"|which <- { w <- file.path(R.home(), "bin", "toolchain", "which"); if (file.exists(w)) w else "@WHICH@" }|' \
    "$sw"
fi

exec "$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "$@"
