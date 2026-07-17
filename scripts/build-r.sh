#!/usr/bin/env bash
# Build R with make from the pixi environment.
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  exec bash "$(dirname "$0")/build-gnuwin32.sh"
fi

cd "$OBJ_DIR"
make -j"$(njobs)"
echo
echo "Build finished: $OBJ_DIR/bin/R"
