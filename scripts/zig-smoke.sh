#!/usr/bin/env bash
# Run smoke-test.sh against the zig-built prefix. Mirrors zig-build.sh's
# own prefix derivation so callers (CI, `pixi run zig-smoke`) don't need
# to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

if [ "$OS" != linux ] && [ "$OS" != macos ]; then
  echo "zig build path covers linux-64 and macOS so far (Windows is F6, in progress)" >&2
  exit 1
fi

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
export R_TEST_R_BIN="$PREFIX_ZIG/lib/R/bin/R"
exec bash "$(dirname "$0")/smoke-test.sh"
