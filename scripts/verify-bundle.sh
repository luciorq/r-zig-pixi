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
# Same $PREFIX-basename derivation as package-standalone.sh's own
# prefix_base fix — the archive's top-level directory name matches
# whatever $PREFIX actually was at package time (zig-built prefixes carry
# a "-zig" suffix), not a hardcoded "R-$R_VERSION-$FLAVOR" (found via a
# real verify-bundle run against a zig-built prefix on kappa: extraction
# succeeded but the hardcoded BUNDLE_DIR guess didn't exist).
BUNDLE_DIR="$VERIFY_DIR/$(basename "$PREFIX")"

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

# Old-server guarantee (Linux only): fail if any shipped ELF requires glibc
# newer than the 2.17 floor build.zig/toolchain pin. This is the check side
# of the floor — a zig update or stray flag that raises the requirement
# should die here, not on a customer's CentOS 7 box.
if [ "$OS" = linux ]; then
  GLIBC_FLOOR="2.17"
  worst=""
  worst_file=""
  while IFS= read -r f; do
    ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1)
    [ -z "$ceil" ] && continue
    if [ "$(printf '%s\n' "$ceil" "$GLIBC_FLOOR" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]; then
      echo "error: $f requires GLIBC_$ceil > floor $GLIBC_FLOOR" >&2
      exit 1
    fi
    if [ -z "$worst" ] || [ "$(printf '%s\n' "$ceil" "$worst" | sort -V | tail -1)" = "$ceil" ]; then
      worst="$ceil"; worst_file="$f"
    fi
  done < <(find "$BUNDLE_DIR" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "7f 45 4c 46"' _ {} \; -print)
  echo "== glibc ceiling verified: worst $worst ($worst_file) <= floor $GLIBC_FLOOR"
fi
