#!/usr/bin/env bash
# Run contract-test.sh against the compile tree, env.sh's COMPILE_TREE
# (build/compile-tree/<flavor>/R-<ver>-zig), so that callers (CI, `pixi
# run contract`) need not know $FLAVOR to find it. It is the flavor's
# installed tree with the toolchain tree's openmp/ and build tools beside
# rzig (compile-tree.sh, PHASE3 open point B); `pixi run contract` makes
# it first.
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  export R_TEST_R_BIN="$COMPILE_TREE/$RH/bin/x64/Rscript.exe"
else
  export R_TEST_R_BIN="$COMPILE_TREE/$RH/bin/Rscript"
fi
exec bash "$(dirname "$0")/contract-test.sh"
