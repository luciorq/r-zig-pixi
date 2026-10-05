#!/usr/bin/env bash
# Copy the conda-env shared libraries R's binaries need into the installed
# tree, so it runs on its own (feat-no-host-paths PLAN.md, F1.3 and F1.7:
# the tree zig build installs is the tree that ships, on every OS, and
# every check runs on it). zig-build.sh runs this after every build, and
# before it on a tree an earlier build left (see there); the rest the tree
# needs from the env (the CA bundle, fontconfig's configuration, Tcl/Tk's
# script libraries, and on Windows Tcl/Tk's DLLs) build.zig installs
# itself (installEnvRuntime). Each run first
# removes what an earlier one copied, then copies what the binaries in the
# tree need now, from the env as it is now (below).
#   - unix: into <prefix>/lib. R's binaries find these through the
#     relative rpaths build.zig writes (relRPaths: R_HOME/lib and
#     <prefix>/lib), and conda-forge's libraries carry rpaths of their own
#     ($ORIGIN/. on linux, @loader_path/ on macOS), so this is a plain
#     copy: no patchelf, and on macOS no install_name_tool, except for the
#     rare conda library that names another by the env's absolute path
#     (below).
#   - Windows: conda's Library/bin DLLs into R_HOME/bin/x64, the directory
#     of Rscript.exe and R.exe, where the loader looks first for every DLL
#     the process loads (R.dll's, the modules', packages'), libomp.dll
#     included, which only packages import (below).
#
# A no-op when the prefix is the env itself (the conda build: the
# libraries are already there, as run dependencies).
#
# Expects R_INSTALL_PREFIX (zig-build.sh passes it).
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

CONDA="${CONDA_PREFIX:?}"
# (zig-build.sh's run before the first build: nothing to vendor into yet)
if [ ! -d "$R_HOME_DIR" ]; then
  echo "== vendor-libs: no R at $R_HOME_DIR yet, nothing to do"
  exit 0
fi
# The conda build installs into the env (recipe/build.sh points both
# R_INSTALL_PREFIX and CONDA_PREFIX at rattler's $PREFIX). The same test
# as build.zig's prefix_is_env, on resolved paths. Windows: MSYS bash may
# be handed C:\..., C:/... or /c/..., with 8.3 short names, and NTFS
# ignores case, so the long Windows form (cygpath -m -l), lower-cased, is
# compared there.
resolved() {
  local d
  d="$(cd "$1" && pwd -P)" || return 1
  if [ "$OS" = windows ]; then
    cygpath -m -l "$d" | tr '[:upper:]' '[:lower:]'
  else
    echo "$d"
  fi
}
if [ "$(resolved "$PREFIX")" = "$(resolved "$CONDA")" ]; then
  exit 0
fi

# What an earlier run copied comes out first: every file directly in the
# destination whose name the env also has (vendored_files, verify-helpers.sh,
# the rule verify-tree.sh also uses to tell conda's files from R's own:
# unix <prefix>/lib, where the build itself installs only directories;
# Windows the DLLs in R_HOME/bin/x64, where the build installs only R's
# own, R.dll, Rblas.dll and the rest, none with a namesake in conda's
# Library/bin). The env's file may have changed since (pixi update), and a
# copy kept because its name is there would ship the old one, and load it
# wherever the tree's copy comes before the env's; and a library the tree
# no longer needs would ship on (package and the wheel archive the tree as
# it is). A library the env no longer has at all (a soname bump, e.g.
# ICU's) is not recognised here and stays; nothing needs it, removing the
# tree drops it, and verify-tree.sh names it if it names the env.
n_old=0
while IFS= read -r f; do
  rm -f "$f"
  n_old=$((n_old + 1))
done < <(vendored_files "$PREFIX" "$CONDA")
[ "$n_old" = 0 ] || echo "== removed $n_old libraries an earlier run vendored"

# Windows: every PE file in the tree (R's own, the toolchain's, and the
# Tcl DLLs build.zig installs into R_HOME/Tcl/bin: tcl86t.dll needs
# zlib1.dll) and, where packages get OpenMP, libomp.dll (below), then a
# fixed-point walk over the DLLs copied by this run.
# The Tcl DLLs stay only in Tcl/bin, CRAN's layout: a copy in bin/x64
# wins the search order but then looks for init.tcl relative to itself
# and fails. (needed_of: verify-helpers.sh, the imports verify-tree.sh
# checks.)
if [ "$OS" = windows ]; then
  BIN="$R_HOME_DIR/bin/x64"
  CLIB="$CONDA/Library/bin"
  mkdir -p "$BIN"
  mapfile -t pes < <(find "$PREFIX" -type f \( -name '*.dll' -o -name '*.exe' \))
  n=0
  i=0
  # libomp.dll, for packages: R itself has no OpenMP on Windows, so no PE
  # file in the tree imports it, but a package linked against the
  # libomp.lib build.zig installs (installOpenMP, wherever Makeconf
  # offers packages OpenMP) does, and the loader finds it here. The walk
  # takes its own imports, as it does every copy's.
  if [ -f "$PREFIX/Library/lib/libomp.lib" ] && [ ! -f "$BIN/libomp.dll" ]; then
    cp "$CLIB/libomp.dll" "$BIN/libomp.dll"
    pes+=("$BIN/libomp.dll")
    n=$((n + 1))
  fi
  while [ "$i" -lt "${#pes[@]}" ]; do
    f="${pes[$i]}"
    i=$((i + 1))
    while read -r dep; do
      case "$dep" in tcl86t.dll|tk86t.dll) continue ;; esac
      if [ -f "$CLIB/$dep" ] && [ ! -f "$BIN/$dep" ]; then
        cp "$CLIB/$dep" "$BIN/$dep"
        pes+=("$BIN/$dep")
        n=$((n + 1))
      fi
    done < <(needed_of "$f")
  done
  echo "== vendored $n conda DLLs into $BIN"
  exit 0
fi
mkdir -p "$PREFIX/lib"

# Every binary under <prefix>/lib: R_HOME (ELF or Mach-O magic, not name
# patterns: the tools in bin/toolchain count too, e.g. minimal's make),
# then a fixed-point walk over the libraries copied by this run.
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
