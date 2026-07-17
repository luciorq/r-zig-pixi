#!/usr/bin/env bash
# Run R's own regression test suite (make check).
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # gnuwin32 runs the suite from the source tree
  MSYS_MAKE="$(command -v /usr/bin/make || command -v make)"
  # tests/Makefile.win hardcodes eval-etc-2.R, which requires the
  # recommended package Matrix; the unix makefile includes it only when
  # recommended packages were built. We don't build them — drop it.
  sed -i 's|^test-src-sloppy-b = eval-etc-2.R|test-src-sloppy-b =|' \
    "$SRC_DIR/tests/Makefile.win"
  cd "$SRC_DIR/src/gnuwin32"
  exec "$MSYS_MAKE" check
fi

cd "$OBJ_DIR"
make check
