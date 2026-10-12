# Helpers shared by verify-tree.sh, verify-toolchain.sh, verify-bundle.sh,
# hermetic-check.sh, unpack-toolchain.sh and vendor-libs.sh (whose Windows
# walk copies what needed_of names, the imports verify-tree.sh then
# checks, and which removes what vendored_files names, the files
# verify-tree.sh counts as conda's). Source this after env.sh (which sets
# OS and holds MACOS_MIN, macho_minos and version_gt); do not execute it.
# Each reads what a binary needs and where it looks for it from the file
# itself: patchelf on linux, otool on macOS, binutils' objdump on Windows.

# An archive's members that are files or links, one per line, as stored
# (R-<ver>-zig/...): not its directories, which every archive of a tree
# repeats (zip stores them as members of their own). The lists of archives
# extracted into one directory compare on these (PHASE3 C6), in
# unpack-toolchain.sh and verify-bundle.sh.
archive_files() {
  case "$1" in
    *.zip) unzip -Z1 "$1" ;;
    *) tar -tzf "$1" ;;
  esac | awk '!/\/$/'
}

# A tree's files and links as archive_files lists an archive made of it
# from its parent (package-standalone.sh): its own name, then the path in
# it (R-<ver>-zig/...), one per line, no directories. verify-bundle.sh
# holds the base archive's list to the R tree's.
tree_files() {
  (cd "$1/.." && find "$(basename "$1")" ! -type d)
}

# The names rzig is installed under in R_HOME/bin/toolchain (build.zig's
# installRzig) on this OS, one line: the names Makeconf runs it by, and
# nothing else is there (feat-standalone-toolchain B19, B30). Windows:
# gcc.exe and g++.exe (CC, CXX), zig-fc.exe (FC), zig-ar.exe and
# zig-ranlib.exe (AR, RANLIB) and the LTO block's gcc-ar.exe and
# gcc-ranlib.exe (B43), and ar.exe and ranlib.exe (what CMake finds
# beside CC); no extensionless zig-cc or zig-cxx, since the compile
# preflight and R CMD config run gcc.exe's check mode (B26 a).
rzig_names() {
  if [ "$OS" = windows ]; then
    echo "gcc.exe g++.exe zig-fc.exe zig-ar.exe zig-ranlib.exe gcc-ar.exe gcc-ranlib.exe ar.exe ranlib.exe"
  else
    echo "zig-cc zig-cxx zig-fc zig-ar zig-ranlib"
  fi
}

# A configure script in package directory $1 (unix configure, Windows
# configure.win) that leaves the file configure-ran there with a shell
# builtin, so that it starts no program: scenario 3 (verify-bundle.sh)
# tells from it whether the install preflight (patch 0009) stopped a
# package before its configure ran (B26, C26). That is the one place
# where R CMD config passes, so configure could run: without the build
# tools R CMD config (patch 0010) fails first, wherever the preflight
# sits.
configure_marker() {
  local f
  for f in configure configure.win; do
    printf '#!/bin/sh\n: > configure-ran\n' > "$1/$f"
    chmod +x "$1/$f"
  done
}

# Extract archive $1 into directory $2. unzip -n: an archive extracted
# beside another never overwrites its files, and never stops to ask
# (unzip's overwrite prompt waits on stdin, which hangs a CI leg; C6).
extract_archive() {
  case "$1" in
    *.zip) unzip -q -n "$1" -d "$2" ;;
    *) tar -xzf "$1" -C "$2" ;;
  esac
}

# Each directory named, as it is set and resolved (Windows: also C:/...,
# and with long and short, 8.3, names), one per line: what a build path in
# a file may look like (verify-tree.sh's and verify-toolchain.sh's scans).
path_forms() {
  local d
  for d in "$@"; do
    [ -n "$d" ] || continue
    printf '%s\n' "$d"
    if [ -d "$d" ]; then (cd "$d" && pwd -P); fi
    if [ "$OS" = windows ]; then
      cygpath -m "$d"
      if [ -d "$d" ]; then cygpath -m -l "$d"; cygpath -m -s "$d"; fi
    fi
  done
}

# One ERE for the paths on stdin: trailing separators dropped, each
# separator either one, once or more (a newline stands in while the regex
# characters are escaped), duplicates once. More than once: a Windows
# binary can hold a path with every backslash doubled (the conda package's
# R.dll built in CI on 2026-09-25 named its work dir 84 times as
# D:\\a\\..., and no other way).
path_re() {
  local f r re=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    r="$(printf '%s' "$f" | sed -e 's#[/\\]*$##' -e 's#[/\\]#\n#g' -e 's#[][*.^$+?(){}|]#\\&#g' -e 's#\n#[/\\\\]+#g')"
    if [ -n "$r" ]; then re="${re:+$re|}$r"; fi
  done < <(sort -u)
  printf '%s\n' "$re"
}

# The files vendor-libs.sh vendored from the env $2 into the tree at
# prefix $1, one path per line, recognised by name, the one rule both
# scripts use: unix, every file or link directly in <prefix>/lib (the
# build installs only directories there) whose name the env's lib/ has;
# Windows, every DLL in R_HOME/bin/x64 (<prefix>/Library/lib/R/bin/x64,
# beside R's own DLLs, none of which has a namesake in the env) whose name
# the env's Library/bin has. A library the env no longer has (a soname
# bump, after a `pixi update`) is not recognised, and stays in the tree
# until the tree is removed.
vendored_files() {
  local f
  if [ "$OS" = windows ]; then
    for f in "$1"/Library/lib/R/bin/x64/*.dll; do
      [ -f "$f" ] && [ -f "$2/Library/bin/${f##*/}" ] && printf '%s\n' "$f"
    done
  else
    for f in "$1"/lib/*; do
      [ -d "$f" ] && continue
      { [ -e "$2/lib/${f##*/}" ] || [ -L "$2/lib/${f##*/}" ]; } && printf '%s\n' "$f"
    done
  fi
  return 0
}

# The libraries a binary names, one per line: DT_NEEDED on linux; on macOS
# its LC_*_DYLIB entries (a dylib's own install name first); on Windows the
# DLLs its import table names. Empty when the file cannot be read.
needed_of() {
  case "$OS" in
    linux) patchelf --print-needed "$1" 2>/dev/null || true ;;
    macos) otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' || true ;;
    windows) x86_64-w64-mingw32-objdump -p "$1" 2>/dev/null | awk '/DLL Name:/ {print $3}' || true ;;
  esac
}

# Windows: succeeds when DLL $1 is the system's: an API set name
# (api-ms-win-*, ext-ms-*, resolved by the loader, no file of that name) or
# a file in System32. (MSYS file tests ignore case, as the loader does.)
if [ "$OS" = windows ]; then
  WIN_SYSTEM32="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")/System32"
fi
win_system_dll() {
  case "$1" in [Aa][Pp][Ii]-[Mm][Ss]-[Ww][Ii][Nn]-*|[Ee][Xx][Tt]-[Mm][Ss]-*) return 0 ;; esac
  [ -f "$WIN_SYSTEM32/$1" ]
}

# Where it looks for them: its RUNPATH/RPATH entries (ELF) or LC_RPATH
# paths (Mach-O), one per line.
rpaths_of() {
  if [ "$OS" = linux ]; then
    patchelf --print-rpath "$1" 2>/dev/null | tr ':' '\n' | grep -v '^$' || true
  else
    otool -l "$1" | awk '/cmd LC_RPATH/ {r = 1} r && / path / {sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r = 0}'
  fi
}

# A shared C++ runtime among the libraries it names (libc++, libstdc++);
# empty when there is none. libc++ is static everywhere (decided
# 2026-09-30), in R's own binaries and in packages compiled with rzig.
cxx_deps() {
  if [ "$OS" = linux ]; then
    needed_of "$1" | grep -E '^lib(c\+\+|stdc\+\+)\.so' || true
  else
    needed_of "$1" | grep -E '(^|/)lib(c\+\+|stdc\+\+)[.0-9]*\.dylib$' || true
  fi
}

# macOS: succeeds, printing the file's minos ("none" when it has none),
# when a Mach-O file is above the MACOS_MIN floor or carries no minos at
# all; fails when it is at or below the floor.
minos_over_floor() {
  local m
  m="$(macho_minos "$1")"
  if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then
    echo "${m:-none}"
    return 0
  fi
  return 1
}

# A check this machine cannot run (its tool is missing or does not work):
# an error in CI, where every tool is there (GitHub Actions sets
# CI=true), a note locally, where the script goes on with what it can.
cannot_check() {
  if [ "${CI:-}" = true ]; then
    echo "error: $1 (CI: every check must run)" >&2
    exit 1
  fi
  echo "   note: $1 (an error in CI)"
}
