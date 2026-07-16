#!/usr/bin/env bash
# Install the built R into the workspace dist/ prefix.
. "$(dirname "$0")/env.sh"
require_not_windows

cd "$OBJ_DIR"
make install
echo
echo "Installed to $PREFIX"
echo "Run it with: $PREFIX/bin/R"
