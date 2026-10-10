#!/usr/bin/env bash
# Run contract-test.sh against the installed tree, env.sh's prefix
# (dist/<flavor>/R-<ver>-zig), so that callers (CI, `pixi run contract`)
# need not know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  export R_TEST_R_BIN="$R_HOME_DIR/bin/x64/Rscript.exe"
else
  export R_TEST_R_BIN="$R_HOME_DIR/bin/Rscript"
fi
exec bash "$(dirname "$0")/contract-test.sh"
