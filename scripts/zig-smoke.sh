#!/usr/bin/env bash
# Run smoke-test.sh against the installed tree, env.sh's prefix
# (dist/<flavor>/R-<ver>-zig), so that callers (CI, `pixi run smoke`)
# need not know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # R_HOME is <prefix>/Library/lib/R on Windows (NTFS case-collision with
  # Python's Lib — see env.sh); Rscript.exe lives at bin/x64/ under that,
  # matching gnuwin32's own layout (F6.0: no bin/R front script on
  # Windows — R.dll's front-end is a compiled Rscript.exe, not a shell
  # wrapper, and F6.0 also drops the R.exe/Rcmd.exe dispatchers).
  export R_TEST_R_BIN="$R_HOME_DIR/bin/x64/Rscript.exe"
else
  export R_TEST_R_BIN="$R_HOME_DIR/bin/R"
fi
exec bash "$(dirname "$0")/smoke-test.sh"
