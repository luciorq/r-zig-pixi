#!/usr/bin/env bash
# Remove build outputs: the flavor's objects, R's source, its R tree and
# its compile tree (compile-tree.sh; PHASE3 C36). Keeps the downloaded
# tarball, zig's cache and the toolchain tree, which every flavor shares;
# use 'rm -rf build dist' for a full scrub.
. "$(dirname "$0")/env.sh"

rm -rf "$OBJ_DIR" "$SRC_DIR" "$PREFIX" "$COMPILE_TREE"
echo "Removed $OBJ_DIR, $SRC_DIR, $PREFIX, $COMPILE_TREE"
