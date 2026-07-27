#!/usr/bin/env bash
# Milestone 5 entry point: build R entirely with zig build (no autoconf, no
# make). Wraps `zig build` so the zig cache lands in the workspace and the
# prefix matches the layout the make-driven pipeline used.
. "$(dirname "$0")/env.sh"

if [ "$OS" != linux ] && [ "$OS" != macos ]; then
  echo "zig build path covers linux-64 and macOS so far (Windows is F6, in progress)" >&2
  exit 1
fi
# (macOS fd ulimit for zig's linker opening ~300 libR objects at once is
# already raised unconditionally by env.sh, sourced above.)

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"

# The Sys.which source patch from configure-r.sh must be present in the
# source tree for relocatable installs (see PLAN.md of feat-initial-setup).
sw="$SRC_DIR/src/library/base/R/unix/system.unix.R"
if [ -f "$sw" ] && ! grep -q 'bin/toolchain/which' "$sw"; then
  sed -i \
    's|which <- "@WHICH@"|which <- { w <- file.path(R.home(), "bin", "toolchain", "which"); if (file.exists(w)) w else "@WHICH@" }|' \
    "$sw"
fi

exec zig build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "$@"
