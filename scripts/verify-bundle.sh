#!/usr/bin/env bash
# Extract the packaged standalone bundle to a fresh location and run it
# with the pixi/conda env off PATH — the same adversarial check done
# manually on omicron/kappa for every relocation fix this project has
# shipped, automated so CI catches a regression instead of relying on a
# human to re-run it. Windows binaries derive R_HOME natively (no PATH
# tricks needed there, per stage.sh); unix binaries get a scrubbed PATH
# to prove they need nothing from the environment that built them.
. "$(dirname "$0")/env.sh"

case "$OS" in
  linux)
    case "$(uname -m)" in
      x86_64) plat=linux-64 ;;
      aarch64) plat=linux-aarch64 ;;
      *) plat="linux-$(uname -m)" ;;
    esac
    ext=tar.gz
    ;;
  macos)
    case "$(uname -m)" in
      arm64) plat=osx-arm64 ;;
      x86_64) plat=osx-64 ;;
      *) plat="osx-$(uname -m)" ;;
    esac
    ext=tar.gz
    ;;
  windows)
    plat=win-64
    ext=zip
    ;;
esac

artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.$ext"
test -f "$artifact" || { echo "error: $artifact not found — run 'pixi run package' first" >&2; exit 1; }

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
echo "== extracting $artifact to $VERIFY_DIR"
if [ "$ext" = zip ]; then
  unzip -q "$artifact" -d "$VERIFY_DIR"
else
  tar -xzf "$artifact" -C "$VERIFY_DIR"
fi
BUNDLE_DIR="$VERIFY_DIR/R-$R_VERSION-$FLAVOR"

CHECK_R='
stopifnot(max(abs(solve(matrix(c(2,0,0,2),2,2)) - matrix(c(.5,0,0,.5),2,2))) < 1e-9)
stopifnot(capabilities("cairo"), capabilities("png"))
cat("bundle OK\n")
'

if [ "$OS" = windows ]; then
  R_BIN="$BUNDLE_DIR/Library/lib/R/bin/x64/Rscript.exe"
  test -x "$R_BIN" || { echo "error: $R_BIN missing from extracted bundle" >&2; exit 1; }
  "$R_BIN" --vanilla -e "$CHECK_R"
else
  R_BIN="$BUNDLE_DIR/bin/R"
  test -x "$R_BIN" || { echo "error: $R_BIN missing from extracted bundle" >&2; exit 1; }
  env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
    "$R_BIN" --vanilla --no-echo -e "$CHECK_R"
fi
echo "== standalone bundle verified relocatable ($OS/$FLAVOR)"
