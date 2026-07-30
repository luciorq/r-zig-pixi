#!/usr/bin/env bash
# Run smoke-test.sh against the zig-built prefix. Mirrors zig-build.sh's
# own prefix derivation so callers (CI, `pixi run zig-smoke`) don't need
# to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
if [ "$OS" = windows ]; then
  # R_HOME is <prefix>/Library/lib/R on Windows (NTFS case-collision with
  # Python's Lib — see env.sh); Rscript.exe lives at bin/x64/ under that,
  # matching gnuwin32's own layout (F6.0: no bin/R front script on
  # Windows — R.dll's front-end is a compiled Rscript.exe, not a shell
  # wrapper, and F6.0 also drops the R.exe/Rcmd.exe dispatchers).
  export R_TEST_R_BIN="$PREFIX_ZIG/Library/lib/R/bin/x64/Rscript.exe"
else
  export R_TEST_R_BIN="$PREFIX_ZIG/lib/R/bin/R"
fi
exec bash "$(dirname "$0")/smoke-test.sh"
