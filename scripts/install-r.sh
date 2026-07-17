#!/usr/bin/env bash
# Install the built R into the workspace dist/ prefix (conda-style
# layout: <prefix>/lib/R is R_HOME on every OS).
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # gnuwin32 has no `make install`; the built source tree IS the R home.
  # Copy the runtime subtrees into the prefix layout.
  R_HOME_DIR="$PREFIX/lib/R"
  mkdir -p "$R_HOME_DIR"
  for d in bin etc include library modules share doc; do
    [ -d "$SRC_DIR/$d" ] && cp -a "$SRC_DIR/$d" "$R_HOME_DIR/"
  done
  cp -a "$SRC_DIR/COPYING" "$SRC_DIR/VERSION" "$R_HOME_DIR/" 2>/dev/null || true
  bash "$ROOT/scripts/stage.sh"
  echo
  echo "Installed and staged at $PREFIX"
  echo "Run it with: $PREFIX/lib/R/bin/x64/R.exe"
  exit 0
fi

cd "$OBJ_DIR"
make install

bash "$ROOT/scripts/stage.sh"

echo
echo "Installed and staged at $PREFIX"
echo "Run it with: $PREFIX/bin/R   (works inside the pixi env)"
echo "For a self-contained bundle: pixi run package"
