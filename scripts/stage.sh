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
# The directory of a path is "${_s%/*}" rather than `dirname` (phase A3:
# starting R runs no external programs besides readlink for symlinks).
for launcher in "$R_HOME_DIR/bin/R"; do
  [ -f "$launcher" ] || continue
  sed -i 's|^R_HOME_DIR=.*|R_HOME_DIR=$(_s="$0"; while [ -h "$_s" ]; do case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac; _d=$(cd -P "${_d:-/}" \&\& pwd); _s=$(readlink "$_s"); case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac; done; case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac; cd -P "${_d:-/}/.." \&\& pwd)  # patched: relocatable|' "$launcher"
  # configure also bakes R_SHARE_DIR/R_INCLUDE_DIR/R_DOC_DIR as literal
  # absolute paths (NOT derived from R_HOME_DIR above) — these feed
  # `R CMD SHLIB`/INSTALL's search for share/make/*.mk, so a stale value
  # breaks package compilation the moment the tree moves. Rederive them.
  sed -i \
    -e 's|^R_SHARE_DIR=.*|R_SHARE_DIR="${R_HOME_DIR}/share"|' \
    -e 's|^R_INCLUDE_DIR=.*|R_INCLUDE_DIR="${R_HOME_DIR}/include"|' \
    -e 's|^R_DOC_DIR=.*|R_DOC_DIR="${R_HOME_DIR}/doc"|' \
    "$launcher"
  # Drop R's lib64 multilib probe (`if test "${R_HOME_DIR}" = "<configure
  # prefix>/lib/R"; then ... fi`, which runs `uname -m`). Once R_HOME_DIR
  # is self-derived it can only match on the build machine itself, so it
  # is dead code whose one effect is carrying build paths into every tree
  # (make-wheel.py refuses those in run-time files).
  sed -i '/^if test "\${R_HOME_DIR}" = "/,/^fi$/d' "$launcher"
done
cat > "$PREFIX/bin/R" << 'EOF'
#!/bin/sh
_s="$0"
while [ -h "$_s" ]; do
  case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac
  _d="$(cd -P "${_d:-/}" && pwd)"
  _s="$(readlink "$_s")"
  case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac
done
case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac
here="$(cd -P "${_d:-/}" && pwd)"
# standalone bundles carry fontconfig config; harmless if absent
if [ -d "$here/../etc/fonts" ]; then
  FONTCONFIG_PATH="$here/../etc/fonts"; export FONTCONFIG_PATH
fi
exec "$here/../lib/R/bin/R" "$@"
EOF
chmod +x "$PREFIX/bin/R"

# Rscript: emulated in POSIX sh (the real one embeds the build path).
# Arguments are rebuilt in "$@" itself, POSIX sh having no arrays: each
# original argument is shifted off the front and its translation appended
# at the end, so after the loop "$@" holds only the translations. As
# Rscript does, with -e the first non-option starts the script's
# arguments; without -e it is the file.
for rs in "$PREFIX/bin/Rscript" "$R_HOME_DIR/bin/Rscript"; do
  cat > "$rs" << 'EOF'
#!/bin/sh
_s="$0"
while [ -h "$_s" ]; do
  case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac
  _d="$(cd -P "${_d:-/}" && pwd)"
  _s="$(readlink "$_s")"
  case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac
done
case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac
here="$(cd -P "${_d:-/}" && pwd)"
case "$here" in
  */lib/R/bin) R_HOME="${here%/bin}" ;;
  *)           R_HOME="$(cd "$here/../lib/R" && pwd)" ;;
esac
export R_HOME
prefix="$(cd "$R_HOME/../.." && pwd)"
if [ -d "$prefix/etc/fonts" ]; then
  FONTCONFIG_PATH="$prefix/etc/fonts"; export FONTCONFIG_PATH
fi
if [ $# -eq 0 ]; then
  echo "Usage: Rscript [options] file [args]" >&2
  echo "   or: Rscript [options] -e expr [-e expr2 ...] [args]" >&2
  exit 1
fi
n=$#
set -- "$@" --no-echo --no-restore
opts=yes; expr=no
while [ "$n" -gt 0 ]; do
  a="$1"; shift; n=$((n - 1))
  if [ "$opts" = no ]; then
    set -- "$@" "$a"
    continue
  fi
  case "$a" in
    -e)
      [ "$n" -gt 0 ] || { echo "Rscript: -e requires an expression" >&2; exit 1; }
      set -- "$@" -e "$1"; shift; n=$((n - 1)); expr=yes ;;
    --default-packages=*) R_DEFAULT_PACKAGES="${a#*=}"; export R_DEFAULT_PACKAGES ;;
    --version) exec "$R_HOME/bin/R" --version ;;
    -*) set -- "$@" "$a" ;;
    *)
      opts=no
      if [ "$expr" = yes ]; then set -- "$@" --args "$a"
      else set -- "$@" -f "$a"; [ "$n" -gt 0 ] && set -- "$@" --args
      fi ;;
  esac
done
exec "$R_HOME/bin/R" "$@"
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

# R's generated files (etc/Renviron, etc/Makeconf, bin/javareconf, ...)
# bake in absolute build-time paths to tools like sed/nm/tar/unzip/zip/
# gzip/bzip2/realpath (autoconf @SED@ etc. substitution), which only exist
# in the pixi env the build ran in. Phase A5 (feat-no-host-paths): they
# become bare names, looked up on PATH when used, and nothing is vendored
# for them. What R needs to run and to install packages without compiling
# no longer reaches them: tar and unzip are R's own (Renviron below), and
# bin/R uses no sed (zig-build.sh's R.sh.in patch). The rest is compiling
# (tier 2: the toolchain's) or R CMD check/build (tier 3: optional).

# minimal (the tree the r-zig wheel wraps): bundle GNU make as well and
# make it R's default MAKE. A conda env gets make from the package's run
# dependencies and a dev machine usually has one; a pip-installed wheel
# has neither guarantee (python:*-slim images ship no make), and R CMD
# INSTALL needs it for any package with compiled code. conda-forge's make
# links libc only, at GLIBC_2.17. Renviron expands a nested default only
# when it is a whole ${...} term, hence the helper variable. Guarded so a
# re-stage of the same tree doesn't stack a second copy of the lines.
if [ "$VARIANT" = minimal ]; then
  cp "$(command -v make)" "$R_HOME_DIR/bin/toolchain/make"
  if ! grep -q '^R_ZIG_MAKE=' "$R_HOME_DIR/etc/Renviron"; then
    sed -i 's|^MAKE=.*|R_ZIG_MAKE=${R_HOME}/bin/toolchain/make\nMAKE=${MAKE-${R_ZIG_MAKE}}|' "$R_HOME_DIR/etc/Renviron"
  fi
fi

mapfile -t baked_files < <(grep -rlF "$CONDA/bin/" "$R_HOME_DIR/bin" "$R_HOME_DIR/etc" 2>/dev/null)
for f in "${baked_files[@]}"; do
  sed -i "s|$CONDA/bin/||g" "$f"
done

# etc/Renviron (phase A4): untar() and unzip() use R's internal code, so
# installing a package without compiling runs no tar or unzip. The rest
# are optional tools found on PATH when used, not the capture machine's
# paths (it recorded /usr/bin/open as the Linux browser, /usr/bin/less,
# /usr/bin/texi2dvi on some runners and none on others). The browser and
# PDF viewer are the desktop's opener. ${X-default} keeps a value the
# user sets in the environment, as upstream's Renviron does.
case "$OS" in macos) opener=open ;; *) opener=xdg-open ;; esac
sed -i \
  -e "s|^TAR=.*|TAR=\${TAR-'internal'}|" \
  -e "s|^R_UNZIPCMD=.*|R_UNZIPCMD=\${R_UNZIPCMD-'internal'}|" \
  -e "s|^PAGER=.*|PAGER=\${PAGER-'less'}|" \
  -e "s|^R_BROWSER=.*|R_BROWSER=\${R_BROWSER-'$opener'}|" \
  -e "s|^R_PDFVIEWER=.*|R_PDFVIEWER=\${R_PDFVIEWER-'$opener'}|" \
  -e "s|^R_PRINTCMD=.*|R_PRINTCMD=\${R_PRINTCMD-'lpr'}|" \
  -e "s|^R_TEXI2DVICMD=.*|R_TEXI2DVICMD=\${R_TEXI2DVICMD-\${TEXI2DVI-'texi2dvi'}}|" \
  "$R_HOME_DIR/etc/Renviron"
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
    # Replace, as patchelf --set-rpath does on linux: zig records the
    # build env's lib dir (absolute) and the zig-cache dirs of sibling
    # artifacts (relative, build/zig-cache/...) on every link; both are
    # build-machine paths (build.zig's fixRpath leaves macOS to this loop).
    otool -l "$f" | awk '/cmd LC_RPATH/ {r = 1} r && / path / {sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r = 0}' |
      while IFS= read -r rp; do
        case "$rp" in @loader_path/*) ;; *) install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true ;; esac
      done
    install_name_tool -add_rpath "@loader_path/$rel_rlib" "$f" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path/$rel_plib" "$f" 2>/dev/null || true
    codesign --force --sign - "$f" 2>/dev/null || true
  done
  echo "   dual @loader_path rpaths set + ad-hoc codesigned (R_HOME/lib + prefix/lib)"
else
  echo "   rpath staging not implemented for $OS"
fi

echo "== staging complete"
