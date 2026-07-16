#!/usr/bin/env bash
# Remove build outputs. Keeps the downloaded tarball and zig cache;
# use 'rm -rf build dist' for a full scrub.
. "$(dirname "$0")/env.sh"

rm -rf "$OBJ_DIR" "$SRC_DIR" "$PREFIX"
echo "Removed $OBJ_DIR, $SRC_DIR, $PREFIX"
