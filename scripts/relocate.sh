#!/usr/bin/env bash
# Make the installed R in $PREFIX self-contained and relocatable:
#   1. bundle every conda-env shared library the install depends on into
#      R_HOME/lib (found by walking ldd over all ELF objects)
#   2. rewrite all RUNPATHs to $ORIGIN-relative paths with patchelf
#   3. make the bin/R launchers derive R_HOME from their own location
#   4. rewrite etc/ldpaths and bundle the zig shims + Makeconf paths so
#      package compilation works wherever the tree lands (zig itself
#      must still be on PATH — it is the single external tool contract)
# Linux only for now; macOS (install_name_tool) and Windows are TODO.
. "$(dirname "$0")/env.sh"

if [ "$OS" != linux ]; then
  echo "relocate: only implemented for Linux so far — skipping" >&2
  exit 0
fi

R_HOME_DIR="$PREFIX/lib/R"
test -d "$R_HOME_DIR" || { echo "error: $R_HOME_DIR missing — run 'pixi run install' first" >&2; exit 1; }
CONDA="${CONDA_PREFIX:?}"

echo "== relocating $PREFIX"

# --- 1. bundle conda libs -------------------------------------------------
# Collect every ELF in the install, walk ldd, copy anything living in the
# pixi env into R_HOME/lib. ldd output is transitively complete.
mapfile -t elfs < <(find "$R_HOME_DIR" -type f \( -name '*.so' -o -path '*/bin/exec/*' \) )
n_copied=0
changed=1
while [ "$changed" = 1 ]; do
  changed=0
  for f in "${elfs[@]}"; do
    while read -r dep; do
      base="$(basename "$dep")"
      if [ ! -f "$R_HOME_DIR/lib/$base" ]; then
        cp -L "$dep" "$R_HOME_DIR/lib/$base"
        n_copied=$((n_copied + 1))
        elfs+=("$R_HOME_DIR/lib/$base")
        changed=1
      fi
    done < <(ldd "$f" 2>/dev/null | awk -v p="$CONDA" '$3 ~ "^"p {print $3}')
  done
done
echo "   bundled $n_copied conda libraries into lib/R/lib"

# --- 2. $ORIGIN rpaths ----------------------------------------------------
find "$R_HOME_DIR" "$PREFIX/bin" -type f | while read -r f; do
  head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
  rel="$(realpath --relative-to="$(dirname "$f")" "$R_HOME_DIR/lib")"
  patchelf --set-rpath "\$ORIGIN/$rel" "$f" 2>/dev/null || true
done
echo "   rewrote RUNPATHs to \$ORIGIN-relative"

# --- 3. dynamic R_HOME in launchers --------------------------------------
for launcher in "$PREFIX/bin/R" "$R_HOME_DIR/bin/R"; do
  [ -f "$launcher" ] || continue
  sed -i 's|^R_HOME_DIR=.*|R_HOME_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." \&\& pwd)  # patched: relocatable|' "$launcher"
done
# $PREFIX/bin/R sits in bin/, R_HOME is lib/R — its own dirname/.. is wrong;
# regenerate it as a trampoline to the real launcher instead.
cat > "$PREFIX/bin/R" << 'EOF'
#!/bin/sh
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$here/../lib/R/bin/R" "$@"
EOF
chmod +x "$PREFIX/bin/R"
# The Rscript binary embeds a compiled-in R_HOME, ignores the env var,
# and exits if that path is gone — fatal after relocation. Emulate its
# CLI through the R launcher, which resolves R_HOME from its location.
for rs in "$PREFIX/bin/Rscript" "$R_HOME_DIR/bin/Rscript"; do
  cat > "$rs" << 'EOF'
#!/bin/bash
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
case "$here" in
  */lib/R/bin) R_HOME="${here%/bin}" ;;
  *)           R_HOME="$(cd "$here/../lib/R" && pwd)" ;;
esac
export R_HOME
ropts=(--no-echo --no-restore)
while (( $# )); do
  case "$1" in
    -e)                 ropts+=(-e "$2"); shift 2 ;;
    --default-packages=*) export R_DEFAULT_PACKAGES="${1#*=}"; shift ;;
    --version)          exec "$R_HOME/bin/R" --version ;;
    -*)                 ropts+=("$1"); shift ;;
    *)                  ropts+=(-f "$1"); shift; break ;;
  esac
done
if (( $# )); then
  exec "$R_HOME/bin/R" "${ropts[@]}" --args "$@"
fi
exec "$R_HOME/bin/R" "${ropts[@]}"
EOF
  chmod +x "$rs"
done
echo "   launchers made location-independent"

# --- 4. ldpaths, shims, Makeconf ------------------------------------------
# etc/ldpaths prepends absolute env paths to LD_LIBRARY_PATH — bundled
# libs make that unnecessary; reduce it to R_HOME/lib only.
cat > "$R_HOME_DIR/etc/ldpaths" << 'EOF'
: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
LD_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
EOF
# Bundle the toolchain shims and point Makeconf at them via $(R_HOME);
# strip absolute -I/-L/rpath flags that referenced the build-time env.
mkdir -p "$R_HOME_DIR/bin/toolchain"
cp "$TOOLCHAIN"/zig-* "$R_HOME_DIR/bin/toolchain/"
mkc="$R_HOME_DIR/etc/Makeconf"
sed -i \
  -e "s|$TOOLCHAIN/|\$(R_HOME)/bin/toolchain/|g" \
  -e "s|-I$CONDA/include||g" \
  -e "s|-L$CONDA/lib||g" \
  -e "s|-Wl,-rpath,$CONDA/lib||g" \
  "$mkc"
echo "   Makeconf uses \$(R_HOME)-relative shims"

echo "== relocation complete: $PREFIX is self-contained"
