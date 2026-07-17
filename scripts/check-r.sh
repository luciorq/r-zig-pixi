#!/usr/bin/env bash
# Run R's own regression test suite (make check).
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # gnuwin32 runs the suite from the source tree
  MSYS_MAKE="$(command -v /usr/bin/make || command -v make)"
  cd "$SRC_DIR/src/gnuwin32"
  exec "$MSYS_MAKE" check
fi

cd "$OBJ_DIR"
make check
