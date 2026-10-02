#!/usr/bin/env bash
# Copy the conda-env libraries R's binaries need into <prefix>/lib, so the
# installed tree runs on its own (feat-no-host-paths PLAN.md, F1.3: the
# tree zig build installs is the tree that ships, and every check runs on
# it). R's binaries find these through the relative rpaths build.zig
# writes (relRPaths: R_HOME/lib and <prefix>/lib), and conda-forge's
# libraries carry rpaths of their own ($ORIGIN/. on linux, @loader_path/
# on macOS), so this is a plain copy: no patchelf, and on macOS no
# install_name_tool, except for the rare conda library that names another
# by the env's absolute path (below).
#
# A no-op when the prefix is the env itself (the conda build: the
# libraries are already in <prefix>/lib, as run dependencies). Windows'
# DLLs are copied by package-standalone.sh. Idempotent: zig-build.sh runs
# it after every build, package-standalone.sh again.
#
# Expects R_INSTALL_PREFIX (zig-build.sh and zig-package.sh export it).
. "$(dirname "$0")/env.sh"

CONDA="${CONDA_PREFIX:?}"
[ "$OS" = windows ] && exit 0
test -d "$R_HOME_DIR" || { echo "vendor-libs: no R at $R_HOME_DIR" >&2; exit 1; }
if [ "$(cd "$PREFIX" && pwd -P)" = "$(cd "$CONDA" && pwd -P)" ]; then
  exit 0
fi
mkdir -p "$PREFIX/lib"

# Every binary under <prefix>/lib: R_HOME (ELF or Mach-O magic, not name
# patterns: the tools in bin/toolchain count too, e.g. minimal's make) and
# what an earlier run vendored, then a fixed-point walk over the libraries
# copied by this one.
case "$OS" in
  linux) magic=$'\x7fELF' ;;
  macos) magic=$'\xcf\xfa\xed\xfe' ;;
esac
bins=()
while IFS= read -r f; do
  head -c4 "$f" 2>/dev/null | LC_ALL=C grep -q "$magic" && bins+=("$f")
done < <(find "$PREFIX/lib" -type f)

# Conda libraries a binary needs. linux: ldd with the env's lib dir on the
# search path (R's own rpaths are relative and the copies may not exist
# yet), keeping what resolves into the env. macOS: conda-forge's dylibs
# are named @rpath/<name> and live in <env>/lib; a few name a dependency
# by the env's absolute path instead (ncurses re-exports libtinfo so),
# which conda's prefix replacement rewrites at install time.
deps() {
  if [ "$OS" = linux ]; then
    LD_LIBRARY_PATH="$CONDA/lib" ldd "$1" 2>/dev/null | awk -v p="$CONDA/" 'index($3, p) == 1 {print $3}'
  else
    otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' |
      while IFS= read -r dep; do
        case "$dep" in
          @rpath/*) name="${dep#@rpath/}" ;;
          "$CONDA"/lib/*) name="${dep#"$CONDA"/lib/}" ;;
          *) continue ;;
        esac
        [ -f "$CONDA/lib/$name" ] && echo "$CONDA/lib/$name"
      done
  fi
}

n=0
i=0
while [ "$i" -lt "${#bins[@]}" ]; do
  f="${bins[$i]}"
  i=$((i + 1))
  while IFS= read -r dep; do
    base="${dep##*/}"
    [ -e "$PREFIX/lib/$base" ] && continue
    cp -L "$dep" "$PREFIX/lib/$base"
    chmod u+w "$PREFIX/lib/$base"
    # minimal (the wheel's tree): conda-forge's libraries ship with full
    # DWARF (libstdc++.so.6: 24 MiB, about 2 without); R's own binaries
    # are already built stripped for minimal (build.zig newCMod).
    if [ "$VARIANT" = minimal ] && [ "$OS" = linux ]; then
      strip --strip-debug "$PREFIX/lib/$base"
    fi
    bins+=("$PREFIX/lib/$base")
    n=$((n + 1))
  done < <(deps "$f")
done
echo "== vendored $n conda libraries into $PREFIX/lib"

# openblas flavour: Makeconf's BLAS_LIBS is a bare -lopenblas, which needs
# the unversioned link name beside the vendored copy (binaries reference,
# and so vendoring copies, only libopenblas.so.0 / libopenblas.0.dylib).
# A package linked through it records the soname, which libR already has
# loaded.
if [ "$BLAS" = openblas ]; then
  case "$OS" in
    linux) v=libopenblas.so.0;    l=libopenblas.so ;;
    macos) v=libopenblas.0.dylib; l=libopenblas.dylib ;;
  esac
  if [ -e "$PREFIX/lib/$v" ] && [ ! -e "$PREFIX/lib/$l" ]; then
    ln -s "$v" "$PREFIX/lib/$l"
  fi
fi

# macOS: an absolute reference into the env would load from this machine's
# env, or nowhere once the tree moves (the full variant's libR ->
# libreadline -> libncurses -> libtinfo, found 2026-10-01 by
# verify-bundle.sh's load-command check). Point it at the vendored copy
# beside it and re-sign: install_name_tool invalidates the signature.
if [ "$OS" = macos ]; then
  for f in "$PREFIX"/lib/*.dylib; do
    abs="$(otool -L "$f" | tail -n +2 | awk -v p="$CONDA/lib/" 'index($1, p) == 1 {print $1}')"
    [ -n "$abs" ] || continue
    for d in $abs; do
      install_name_tool -change "$d" "@loader_path/${d##*/}" "$f" 2>/dev/null
    done
    codesign --force --sign - "$f" 2>/dev/null
    echo "== ${f##*/}: env paths now @loader_path ($(echo $abs | tr ' ' ','))"
  done
fi
