#!/usr/bin/env bash
# Stage the installed R tree in $PREFIX: normalize every internal
# reference so the SAME tree works both as a conda package (deps come
# from the enclosing env's $PREFIX/lib) and as a standalone bundle
# (deps vendored into <bundle>/lib by package-standalone.sh).
#
#   1. dual-entry rpaths: R_HOME/lib AND <prefix>/lib ($ORIGIN on linux,
#      @loader_path on macOS, plus mandatory ad-hoc re-codesigning there)
#   2. launchers derive R_HOME from their own location (bin/R trampoline,
#      Rscript CLI emulated — its binary hard-embeds the build path)
#   3. etc/ldpaths reduced to R_HOME/lib
#   4. zig shims bundled; Makeconf rewritten to $(R_HOME)-relative
#
# Linux and macOS implemented (patchelf / install_name_tool+codesign).
. "$(dirname "$0")/env.sh"

test -d "$R_HOME_DIR" || { echo "error: $R_HOME_DIR missing — run 'pixi run install' first" >&2; exit 1; }
CONDA="${CONDA_PREFIX:?}"

echo "== staging $PREFIX"

if [ "$OS" = windows ]; then
  # Windows binaries derive R_HOME from their own location natively —
  # no rpath work needed. Stage the Makeconf + shims, then expose R on
  # PATH: a conda/pixi env's activation only ever adds <env>,
  # <env>\Library\{bin,mingw-w64\bin,usr\bin}, <env>\Scripts, <env>\bin —
  # never <env>\Library\lib\R\bin\x64 — so without a shim here, `R`/
  # `Rscript` are simply not found after installing this package into a
  # real env, even though the binaries exist (found via a real `pixi
  # add`-installed env, not this project's own dist/ test runs).
  mkdir -p "$R_HOME_DIR/bin/toolchain"
  cp "$TOOLCHAIN"/zig-* "$R_HOME_DIR/bin/toolchain/"
  mkc="$R_HOME_DIR/etc/x64/Makeconf"
  if [ -f "$mkc" ]; then
    # bundled Tcl location (package-standalone vendors it there);
    # falls back gracefully when running inside the pixi env
    sed -i "s|^TCL_HOME *=.*|TCL_HOME = \$(R_HOME)/Tcl|" "$mkc"
  fi
  mkdir -p "$PREFIX/Library/bin"
  for exe in R Rscript; do
    cat > "$PREFIX/Library/bin/$exe.bat" << EOF
@echo off
"%~dp0..\\lib\\R\\bin\\x64\\$exe.exe" %*
EOF
  done
  echo "   R/Rscript shims added to Library/bin (PATH-visible after activation)"
  echo "== staging complete (windows)"
  exit 0
fi

# --- launchers (all unix) -------------------------------------------------
# Resolve $0 to its real directory without `readlink -f`: BSD/macOS
# readlink has no -f flag, only GNU's does (and we can't assume a
# relocated bundle has GNU coreutils on PATH). This loop-based idiom
# (follow one -h/symlink hop at a time via plain `readlink`, POSIX on
# both GNU and BSD) works identically everywhere. The case patterns
# below use the POSIX-optional leading "(" (e.g. "(/*)" not "/*)") —
# macOS's system bash (3.2.57, frozen pre-GPLv3) misparses a `case`
# with an empty first branch when the whole thing is forced onto one
# line inside a $(...) substitution (exactly what this sed replacement
# does); found by running the staged launcher on real hardware outside
# the pixi env, not by inspection. The parenthesized form sidesteps it
# and is valid on every POSIX shell, so it's harmless everywhere else.
for launcher in "$R_HOME_DIR/bin/R"; do
  [ -f "$launcher" ] || continue
  sed -i 's|^R_HOME_DIR=.*|R_HOME_DIR=$(_s="$0"; while [ -h "$_s" ]; do _d=$(cd -P "$(dirname "$_s")" \&\& pwd); _s=$(readlink "$_s"); case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac; done; cd -P "$(dirname "$_s")/.." \&\& pwd)  # patched: relocatable|' "$launcher"
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
_s="$0"
while [ -h "$_s" ]; do
  _d="$(cd -P "$(dirname "$_s")" && pwd)"
  _s="$(readlink "$_s")"
  case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac
done
here="$(cd -P "$(dirname "$_s")" && pwd)"
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
_s="$0"
while [ -h "$_s" ]; do
  _d="$(cd -P "$(dirname "$_s")" && pwd)"
  _s="$(readlink "$_s")"
  case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac
done
here="$(cd -P "$(dirname "$_s")" && pwd)"
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
# dyld ignores LD_LIBRARY_PATH entirely — macOS needs
# DYLD_FALLBACK_LIBRARY_PATH (what R's own stock ldpaths uses on Darwin;
# found by running the staged bundle for real: bin/exec/R's bare
# "libR.dylib" dependency resolves through this fallback-path mechanism,
# so writing only LD_LIBRARY_PATH here silently broke every macOS launch).
if [ "$OS" = macos ]; then
  cat > "$R_HOME_DIR/etc/ldpaths" << 'EOF'
: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
if [ -z "${DYLD_FALLBACK_LIBRARY_PATH}" ]; then
  DYLD_FALLBACK_LIBRARY_PATH="${R_LD_LIBRARY_PATH}"
else
  DYLD_FALLBACK_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${DYLD_FALLBACK_LIBRARY_PATH}"
fi
export DYLD_FALLBACK_LIBRARY_PATH
EOF
else
  cat > "$R_HOME_DIR/etc/ldpaths" << 'EOF'
: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
LD_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
EOF
fi
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

# --- rpaths (linux / macos) ------------------------------------------------
if [ "$OS" = linux ]; then
  find "$R_HOME_DIR" "$PREFIX/bin" -type f | while read -r f; do
    head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
    d="$(dirname "$f")"
    rel_rlib="$(realpath --relative-to="$d" "$R_HOME_DIR/lib")"
    rel_plib="$(realpath --relative-to="$d" "$PREFIX/lib")"
    patchelf --set-rpath "\$ORIGIN/$rel_rlib:\$ORIGIN/$rel_plib" "$f" 2>/dev/null || true
  done
  echo "   dual \$ORIGIN rpaths set (R_HOME/lib + prefix/lib)"
elif [ "$OS" = macos ]; then
  # conda-forge's macOS dylibs record their deps as @rpath/<name> (never
  # an absolute path), so — unlike libR.dylib/libRblas.dylib, which are
  # bare names resolved through etc/ldpaths' DYLD_FALLBACK_LIBRARY_PATH —
  # they need an actual LC_RPATH to resolve. Add @loader_path-relative
  # entries mirroring Linux's dual $ORIGIN scheme (R_HOME/lib for the
  # conda-package case, prefix/lib for package-standalone.sh's vendored
  # copies), on every Mach-O file (dyld's rpath search is cumulative up
  # the load chain, but staying uniform matches the ELF loop above and
  # doesn't rely on that subtlety). install_name_tool invalidates any
  # existing code signature — arm64 macOS refuses to exec an unsigned
  # binary, so re-sign ad-hoc (`-`) after patching, matching the level of
  # signing conda-forge's own unsigned/ad-hoc-signed dylibs already carry.
  find "$R_HOME_DIR" "$PREFIX/bin" -type f | while read -r f; do
    head -c4 "$f" 2>/dev/null | grep -q $'\xcf\xfa\xed\xfe' || continue
    d="$(dirname "$f")"
    rel_rlib="$(realpath --relative-to="$d" "$R_HOME_DIR/lib")"
    rel_plib="$(realpath --relative-to="$d" "$PREFIX/lib")"
    install_name_tool -add_rpath "@loader_path/$rel_rlib" "$f" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path/$rel_plib" "$f" 2>/dev/null || true
    codesign --force --sign - "$f" 2>/dev/null || true
  done
  echo "   dual @loader_path rpaths set + ad-hoc codesigned (R_HOME/lib + prefix/lib)"
else
  echo "   rpath staging not implemented for $OS"
fi

echo "== staging complete"
