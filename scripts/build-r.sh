#!/usr/bin/env bash
# Build R with make from the pixi environment.
. "$(dirname "$0")/env.sh"
require_not_windows

cd "$OBJ_DIR"
make -j"$(njobs)"
echo
echo "Build finished: $OBJ_DIR/bin/R"
