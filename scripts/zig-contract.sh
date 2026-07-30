#!/usr/bin/env bash
# Run contract-test.sh against the zig-built prefix. Mirrors zig-build.sh's
# own prefix derivation so callers (CI, `pixi run zig-contract`) don't need
# to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
if [ "$OS" = windows ]; then
  export R_TEST_R_BIN="$PREFIX_ZIG/Library/lib/R/bin/x64/Rscript.exe"
else
  export R_TEST_R_BIN="$PREFIX_ZIG/lib/R/bin/Rscript"
fi
exec bash "$(dirname "$0")/contract-test.sh"
