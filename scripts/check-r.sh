#!/usr/bin/env bash
# Run R's own regression test suite (make check).
. "$(dirname "$0")/env.sh"
require_not_windows

cd "$OBJ_DIR"
make check
