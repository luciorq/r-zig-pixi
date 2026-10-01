#!/usr/bin/env bash
# Copy the conda-env libraries R's binaries need into <prefix>/lib, so the
# installed tree runs on its own (feat-no-host-paths PLAN.md, F1.3: the
# tree zig build installs is the tree that ships, and every check runs on
# it). R's binaries find these through the relative rpaths build.zig
# writes (relRPaths: R_HOME/lib and <prefix>/lib), and conda-forge's
# libraries carry rpaths of their own ($ORIGIN/. on linux, @loader_path/
# on macOS), so this is a plain copy: no patchelf, no install_name_tool,
# no re-signing.
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

# Every binary under R_HOME (ELF or Mach-O magic, not name patterns: the
# tools in bin/toolchain count too, e.g. minimal's make), then a fixed-point
# walk over the libraries copied so far.
case "$OS" in
  linux) magic=$'\x7fELF' ;;
  macos) magic=$'\xcf\xfa\xed\xfe' ;;
esac
bins=()
while IFS= read -r f; do
  head -c4 "$f" 2>/dev/null | LC_ALL=C grep -q "$magic" && bins+=("$f")
done < <(find "$R_HOME_DIR" -type f)

# Conda libraries a binary needs. linux: ldd with the env's lib dir on the
# search path (R's own rpaths are relative and the copies may not exist
# yet), keeping what resolves into the env. macOS: conda-forge's dylibs
# are named @rpath/<name> and live in <env>/lib.
deps() {
  if [ "$OS" = linux ]; then
    LD_LIBRARY_PATH="$CONDA/lib" ldd "$1" 2>/dev/null | awk -v p="$CONDA/" 'index($3, p) == 1 {print $3}'
  else
    otool -L "$1" 2>/dev/null | awk '/@rpath\// {sub(/^@rpath\//, "", $1); print $1}' |
      while IFS= read -r name; do
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
