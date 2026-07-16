#!/usr/bin/env bash
# Download and extract the R source tarball from CRAN, verifying its checksum.
. "$(dirname "$0")/env.sh"

if [ -f "$SRC_DIR/configure" ]; then
  echo "R $R_VERSION source already present at $SRC_DIR"
  exit 0
fi

mkdir -p "$BUILD_DIR"

if [ ! -f "$TARBALL" ]; then
  echo "Downloading R $R_VERSION from $CRAN_URL"
  curl -fL --retry 3 -o "$TARBALL.part" "$CRAN_URL"
  mv "$TARBALL.part" "$TARBALL"
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
  if [ -f "$CHECKSUM_FILE" ]; then
    expected="$(cut -d' ' -f1 <"$CHECKSUM_FILE")"
    if [ "$actual" != "$expected" ]; then
      echo "error: checksum mismatch for $TARBALL" >&2
      echo "  expected: $expected" >&2
      echo "  actual:   $actual" >&2
      exit 1
    fi
    echo "Checksum OK"
  else
    mkdir -p "$(dirname "$CHECKSUM_FILE")"
    printf '%s  R-%s.tar.gz\n' "$actual" "$R_VERSION" >"$CHECKSUM_FILE"
    echo "Pinned new checksum in $CHECKSUM_FILE — commit this file."
  fi
else
  echo "warning: sha256sum not found; skipping checksum verification" >&2
fi

echo "Extracting to $SRC_DIR"
tar -xzf "$TARBALL" -C "$BUILD_DIR"
test -f "$SRC_DIR/configure"
echo "Done."
