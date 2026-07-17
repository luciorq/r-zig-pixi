#!/usr/bin/env bash
# Stage the installed R tree in $PREFIX: normalize every internal
# reference so the SAME tree works both as a conda package (deps come
# from the enclosing env's $PREFIX/lib) and as a standalone bundle
# (deps vendored into <bundle>/lib by package-standalone.sh).
#
#   1. dual-entry $ORIGIN rpaths: R_HOME/lib AND <prefix>/lib
#   2. launchers derive R_HOME from their own location (bin/R trampoline,
#      Rscript CLI emulated — its binary hard-embeds the build path)
#   3. etc/ldpaths reduced to R_HOME/lib
#   4. zig shims bundled; Makeconf rewritten to $(R_HOME)-relative
#
# Linux implemented; macOS staging is TODO (install_name_tool + codesign).
. "$(dirname "$0")/env.sh"

R_HOME_DIR="$PREFIX/lib/R"
test -d "$R_HOME_DIR" || { echo "error: $R_HOME_DIR missing — run 'pixi run install' first" >&2; exit 1; }
CONDA="${CONDA_PREFIX:?}"

echo "== staging $PREFIX"

if [ "$OS" = windows ]; then
  # Windows binaries derive R_HOME from their own location natively —
  # no launcher or rpath work. Stage the Makeconf + shims only.
  mkdir -p "$R_HOME_DIR/bin/toolchain"
  cp "$TOOLCHAIN"/zig-* "$R_HOME_DIR/bin/toolchain/"
  mkc="$R_HOME_DIR/etc/x64/Makeconf"
  if [ -f "$mkc" ]; then
    # bundled Tcl location (package-standalone vendors it there);
    # falls back gracefully when running inside the pixi env
    sed -i "s|^TCL_HOME *=.*|TCL_HOME = \$(R_HOME)/Tcl|" "$mkc"
  fi
  echo "== staging complete (windows)"
  exit 0
fi

# --- launchers (all unix) -------------------------------------------------
for launcher in "$R_HOME_DIR/bin/R"; do
  [ -f "$launcher" ] || continue
  sed -i 's|^R_HOME_DIR=.*|R_HOME_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." \&\& pwd)  # patched: relocatable|' "$launcher"
  # configure also bakes R_SHARE_DIR/R_INCLUDE_DIR/R_DOC_DIR as literal
  # absolute paths (NOT derived from R_HOME_DIR above) — these feed
  # `R CMD SHLIB`/INSTALL's search for share/make/*.mk, so a stale value
  # breaks package compilation the moment the tree moves. Rederive them.
  sed -i \
    -e 's|^R_SHARE_DIR=.*|R_SHARE_DIR="${R_HOME_DIR}/share"|' \
    -e 's|^R_INCLUDE_DIR=.*|R_INCLUDE_DIR="${R_HOME_DIR}/include"|' \
    -e 's|^R_DOC_DIR=.*|R_DOC_DIR="${R_HOME_DIR}/doc"|' \
    "$launcher"
done
cat > "$PREFIX/bin/R" << 'EOF'
#!/bin/sh
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# standalone bundles carry fontconfig config; harmless if absent
if [ -d "$here/../etc/fonts" ]; then
  FONTCONFIG_PATH="$here/../etc/fonts"; export FONTCONFIG_PATH
fi
exec "$here/../lib/R/bin/R" "$@"
EOF
chmod +x "$PREFIX/bin/R"

for rs in "$PREFIX/bin/Rscript" "$R_HOME_DIR/bin/Rscript"; do
  cat > "$rs" << 'EOF'
#!/bin/bash
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
case "$here" in
  */lib/R/bin) R_HOME="${here%/bin}" ;;
  *)           R_HOME="$(cd "$here/../lib/R" && pwd)" ;;
esac
export R_HOME
prefix="$(cd "$R_HOME/../.." && pwd)"
if [ -d "$prefix/etc/fonts" ]; then
  FONTCONFIG_PATH="$prefix/etc/fonts"; export FONTCONFIG_PATH
fi
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

# --- ldpaths, shims, Makeconf ---------------------------------------------
cat > "$R_HOME_DIR/etc/ldpaths" << 'EOF'
: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
LD_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
EOF
mkdir -p "$R_HOME_DIR/bin/toolchain"
cp "$TOOLCHAIN"/zig-* "$R_HOME_DIR/bin/toolchain/"

# R's generated scripts (bin/R, bin/libtool, bin/javareconf, ...) bake in
# absolute build-time paths to tools like sed/grep/nm/dd/realpath
# (autoconf @SED@ etc. substitution). Those paths only exist in the SAME
# pixi env the build ran in — breaks for a conda package (build_env is
# torn down before the run/test env) and for a standalone bundle moved
# to a machine without this pixi env. Bundle every referenced tool and
# rewrite the reference:
#   - bin/R itself self-computes R_HOME_DIR before SED= (see above), so
#     it gets a direct rewrite to that shell variable.
#   - every other generated script runs as a child of R (R CMD ..., R
#     CMD SHLIB, etc.), which always exports R_HOME first — rewrite
#     those to $R_HOME (the env var), no self-computation needed.
cp "$(command -v sed)" "$R_HOME_DIR/bin/toolchain/sed"
sed -i 's|^SED=.*|SED="$R_HOME_DIR/bin/toolchain/sed"|' "$R_HOME_DIR/bin/R"

# base::Sys.which() looks for this exact path (see configure-r.sh patch
# to system.unix.R) — not discoverable by the text-sweep below since the
# reference lives in compiled R data (base.rdb), not a script.
command -v which >/dev/null 2>&1 && cp "$(command -v which)" "$R_HOME_DIR/bin/toolchain/which"

mapfile -t baked_files < <(grep -rlF "$CONDA/bin/" "$R_HOME_DIR/bin" "$R_HOME_DIR/etc" 2>/dev/null | grep -v '^'"$R_HOME_DIR/bin/R"'$')
for f in "${baked_files[@]}"; do
  sed -i "s|$CONDA/bin/|\$R_HOME/bin/toolchain/|g" "$f"
done
mapfile -t refd_tools < <(grep -rhoE '\$(R_HOME|R_HOME_DIR)/bin/toolchain/[A-Za-z0-9_.+-]+' \
  "$R_HOME_DIR/bin" "$R_HOME_DIR/etc" 2>/dev/null | sed 's|.*/||' | sort -u)
for t in "${refd_tools[@]}"; do
  [ -f "$R_HOME_DIR/bin/toolchain/$t" ] && continue
  src="$(command -v "$t" 2>/dev/null)" || continue
  cp "$src" "$R_HOME_DIR/bin/toolchain/$t"
done
echo "   bundled tools: $(ls "$R_HOME_DIR/bin/toolchain")"

mkc="$R_HOME_DIR/etc/Makeconf"
# NB: the absolute -I/-L/rpath env flags stay — inside a conda env they
# are correct (and conda's prefix replacement rewrites them on install);
# package-standalone.sh strips them for the bundled artifact.
sed -i "s|$TOOLCHAIN/|\$(R_HOME)/bin/toolchain/|g" "$mkc"
echo "   Makeconf uses \$(R_HOME)-relative shims"

# --- rpaths (linux) -------------------------------------------------------
if [ "$OS" = linux ]; then
  find "$R_HOME_DIR" "$PREFIX/bin" -type f | while read -r f; do
    head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
    d="$(dirname "$f")"
    rel_rlib="$(realpath --relative-to="$d" "$R_HOME_DIR/lib")"
    rel_plib="$(realpath --relative-to="$d" "$PREFIX/lib")"
    patchelf --set-rpath "\$ORIGIN/$rel_rlib:\$ORIGIN/$rel_plib" "$f" 2>/dev/null || true
  done
  echo "   dual \$ORIGIN rpaths set (R_HOME/lib + prefix/lib)"
else
  echo "   rpath staging not implemented for $OS yet (TODO: install_name_tool)"
fi

echo "== staging complete"
