#!/usr/bin/env bash
# Install the built R into the workspace dist/ prefix.
. "$(dirname "$0")/env.sh"
require_not_windows

cd "$OBJ_DIR"
make install

bash "$ROOT/scripts/relocate.sh"

echo
echo "Installed to $PREFIX (self-contained; movable as a directory)"
echo "Run it with: $PREFIX/bin/R"
