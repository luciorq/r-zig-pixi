#!/usr/bin/env bash
# Milestone 5 entry point: build R entirely with zig build (no autoconf, no
# make). Wraps `zig build` so the zig cache lands in the workspace and the
# prefix matches the layout the make-driven pipeline used.
. "$(dirname "$0")/env.sh"

if [ "$OS" != linux ]; then
  echo "zig build path is linux-64 only so far (milestone 5, in progress)" >&2
  exit 1
fi

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
