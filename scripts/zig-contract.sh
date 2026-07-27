#!/usr/bin/env bash
# Run contract-test.sh against the zig-built prefix. Mirrors zig-build.sh's
# own prefix derivation so callers (CI, `pixi run zig-contract`) don't need
# to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

if [ "$OS" != linux ]; then
  echo "zig build path is linux-64 only so far (milestone 5, in progress)" >&2
  exit 1
fi

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
export R_TEST_R_BIN="$PREFIX_ZIG/lib/R/bin/Rscript"
exec bash "$(dirname "$0")/contract-test.sh"
