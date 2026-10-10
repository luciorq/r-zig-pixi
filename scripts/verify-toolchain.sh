#!/usr/bin/env bash
# Static checks of the toolchain tree (feat-standalone-toolchain B30,
# point 3, B21), dist/toolchain/R-<ver>-zig: zig-toolchain.sh installs it
# (zigbuild/toolchain/build.zig), package-standalone.sh's toolchain mode
# archives it, one archive per group. Every file in it is a third-party
# file copied unchanged from a conda package, or that package's record:
#   - layout: group directories under R_HOME/bin/toolchain only (env.sh's
#     group_dirs), and no file directly in it;
#   - records: each directory has SOURCES, and a non-empty
#     LICENSES/<package>/ for each package SOURCES names, and no other;
#   - copies: every other file is the target of a `file:` line of
#     SOURCES, with the sha256 that line gives (the package's, from
#     conda-meta's paths_data), and every such target is there;
#   - build paths: SOURCES and LICENSES name none of the checkout, the
#     tree's own place, zig's caches, the env or $HOME (verify-tree.sh's
#     list). A copy that names one is listed, not failed: the copies are
#     conda's bytes, and conda-forge's macOS make names its build path,
#     /Users/runner/..., which is under $HOME on GitHub's macOS runners
#     (PHASE3 C18);
#   - closures: a copy loads only the system's libraries or files beside
#     it (B21; none of today's needs the base's runtime): linux, glibc's
#     libraries, at most GLIBC 2.28 (conda-forge's baseline: these run
#     only to compile; make needs 2.17), and rpaths relative to the file;
#     macOS, /usr/lib and /System, minos at most MACOS_MIN, rpaths
#     relative; Windows, every DLL a PE file imports beside it or the
#     system's;
#   - OpenMP (the compilers group, B22): openmp/include/omp.h; Windows
#     also openmp/lib/libomp.lib.
# Nothing here asks a copy to be stripped or changed: they are conda's
# binaries as conda ships them (C24). A separate script from
# verify-tree.sh, which checks the R trees (the base).
#
# Usage: verify-toolchain.sh [TREE]   (default: env.sh's TOOLCHAIN_PREFIX)
# Shared helpers (needed_of, rpaths_of, minos_over_floor, win_system_dll,
# path_forms, path_re, cannot_check): verify-helpers.sh.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

TREE="${1:-$TOOLCHAIN_PREFIX}"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
tc="$RH/bin/toolchain"
test -d "$TREE/$tc" || { echo "error: no toolchain tree at $TREE ($tc missing): run 'pixi run toolchain' first" >&2; exit 1; }
TREE="$(cd "$TREE" && pwd)"
echo "== verifying the toolchain tree $TREE ($OS)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Layout: every file in a group directory of R_HOME/bin/toolchain.
known=" "
for g in $TOOLCHAIN_GROUPS; do known="$known$(group_dirs "$g") "; done
find "$TREE" ! -type d > "$WORK/all.txt"
bad=""
while IFS= read -r f; do
  rel="${f#"$TREE"/}"
  d="${rel#"$tc"/}"; d="${d%%/*}"
  case "$rel" in
    "$tc"/*/*) case "$known" in *" $d "*) continue ;; esac ;;
  esac
  bad="$bad
  $rel"
done < "$WORK/all.txt"
if [ -n "$bad" ]; then
  echo "error: files outside the group directories ($(echo $known | tr ' ' ,) under $tc):$bad" >&2
  exit 1
fi
dirs=()
for d in $known; do
  if [ -d "$TREE/$tc/$d" ]; then dirs+=("$d"); fi
done
[ "${#dirs[@]}" -gt 0 ] || { echo "error: no group directory in $TREE/$tc" >&2; exit 1; }
echo "== layout verified: $(wc -l < "$WORK/all.txt" | tr -d ' ') files, all in $tc/{$(echo "${dirs[@]}" | tr ' ' ,)}"

# Records and copies, per directory.
bad=""
: > "$WORK/copies.txt"
n_pkgs=0
for d in "${dirs[@]}"; do
  D="$TREE/$tc/$d"
  if [ ! -f "$D/SOURCES" ]; then
    bad="$bad
  $d/SOURCES (missing)"
    continue
  fi
  pkgs="$(sed -n 's/^package: //p' "$D/SOURCES" | tr -d '\r')"
  for p in $pkgs; do
    n_pkgs=$((n_pkgs + 1))
    [ -n "$(find "$D/LICENSES/$p" ! -type d 2> /dev/null | head -1)" ] || bad="$bad
  $d/LICENSES/$p/ (missing or empty)"
  done
  for l in "$D"/LICENSES/*; do
    [ -e "$l" ] || continue
    grep -qxF -- "${l##*/}" <<< "$pkgs" || bad="$bad
  $d/LICENSES/${l##*/}/ (no package of SOURCES)"
  done
  # file: <path in the package> -> <path here> <sha256>
  tr -d '\r' < "$D/SOURCES" | awk -v d="$d" '
    $1 != "file:" { next }
    NF != 5 || $3 != "->" || length($5) != 64 || $5 ~ /[^0-9a-f]/ { print "BAD " d "/SOURCES:" NR ": " $0; next }
    { print $4, $5 }' > "$WORK/files.txt"
  while read -r to sum; do
    if [ "$to" = BAD ]; then bad="$bad
  $sum (not a file line)"; continue; fi
    if [ ! -f "$D/$to" ]; then bad="$bad
  $d/$to (in SOURCES, missing)"; continue; fi
    got="$(sha256sum < "$D/$to" | cut -d' ' -f1)"
    [ "$got" = "$sum" ] || bad="$bad
  $d/$to (sha256 $got, SOURCES says $sum)"
  done < "$WORK/files.txt"
  while IFS= read -r f; do
    rel="${f#"$D"/}"
    case "$rel" in SOURCES|LICENSES/*) continue ;; esac
    printf '%s\n' "$f" >> "$WORK/copies.txt"
    awk -v r="$rel" '$1 == r { f = 1 } END { exit !f }' "$WORK/files.txt" || bad="$bad
  $d/$rel (no file line in SOURCES)"
  done < <(find "$D" ! -type d)
done
if [ -n "$bad" ]; then
  echo "error: the toolchain tree's records (SOURCES, LICENSES) and copies:$bad" >&2
  exit 1
fi
n_copies="$(wc -l < "$WORK/copies.txt" | tr -d ' ')"
echo "== records verified: $n_copies copies, each a file line of its directory's SOURCES with the package's sha256; $n_pkgs packages, each with its LICENSES/"

# Build paths, as verify-tree.sh looks for them: the checkout (zig's
# caches are in it, as env.sh keeps them), zig's caches wherever they are,
# the env, the tree's own place and $HOME, as set and resolved, with
# either separator (doubled too) and on Windows in any case.
conda_dir="${CONDA_PREFIX:?run through pixi: the env the tree was copied from is CONDA_PREFIX}"
command -v cygpath > /dev/null 2>&1 && conda_dir="$(cygpath -u "$conda_dir")"
build_dirs=("$ROOT" "${PIXI_PROJECT_ROOT:-}" "${ZIG_GLOBAL_CACHE_DIR:-}" "${ZIG_LOCAL_CACHE_DIR:-}" "$conda_dir" "$TREE")
home_dirs=()
case "${HOME:-}" in
  /*/[!/]*) home_dirs+=("$HOME") ;;
  *) echo "   note: \$HOME (${HOME:-unset}) is too short to look for" ;;
esac
if [ "$OS" = windows ] && [ -n "${USERPROFILE:-}" ]; then home_dirs+=("$(cygpath -u "$USERPROFILE")"); fi
re="$(path_forms "${build_dirs[@]}" "${home_dirs[@]}" | path_re)"
icase=()
[ "$OS" = windows ] && icase=(-i)
first_match() {
  grep -aoE "${icase[@]}" -e "($re)[^[:space:][:cntrl:]\"'<>]{0,72}" "$1" | head -1 || true
}
bad=""
while IFS= read -r f; do
  bad="$bad
  ${f#"$TREE"/}: $(first_match "$f")"
done < <(find "$TREE/$tc" -type f \( -name SOURCES -o -path '*/LICENSES/*' \) -exec grep -laE "${icase[@]}" -e "$re" {} +)
if [ -n "$bad" ]; then
  echo "error: SOURCES or LICENSES name the build machine (the checkout, zig's caches, the env, the tree or \$HOME), first match each:$bad" >&2
  exit 1
fi
named=""
n_named=0
while IFS= read -r f; do
  if grep -qaE "${icase[@]}" -e "$re" "$f"; then
    named="$named
     ${f#"$TREE"/}: $(first_match "$f")"
    n_named=$((n_named + 1))
  fi
done < "$WORK/copies.txt"
echo "== build paths verified: SOURCES and LICENSES name none of the checkout, zig's caches, the env, the tree or \$HOME"
if [ "$n_named" -gt 0 ]; then
  echo "   conda's copies that name one of them, as conda ships them: $n_named$named"
fi

# Closures and floors of the copies that are binaries.
bad=""
n_bin=0
case "$OS" in
  linux)
    if ! command -v objdump > /dev/null 2>&1; then
      cannot_check "objdump unavailable; the toolchain's glibc ceiling not checked"
    fi
    GLIBC_TOOLS_CEILING="2.28"
    worst=""
    while IFS= read -r f; do
      head -c4 "$f" | od -An -tx1 | grep -q "7f 45 4c 46" || continue
      n_bin=$((n_bin + 1))
      rel="${f#"$TREE"/}"
      for dep in $(needed_of "$f"); do
        case "$dep" in
          libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libutil.so.1|libresolv.so.2|ld-linux*.so.[12]) ;;
          *) bad="$bad
  $rel: needs $dep (not glibc's)" ;;
        esac
      done
      for rp in $(rpaths_of "$f"); do
        case "$rp" in '$ORIGIN'|'$ORIGIN/'*) ;; *) bad="$bad
  $rel: rpath $rp" ;; esac
      done
      if command -v objdump > /dev/null 2>&1; then
        ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
        if [ -n "$ceil" ]; then
          if [ "$(printf '%s\n' "$ceil" "$GLIBC_TOOLS_CEILING" | sort -V | tail -1)" != "$GLIBC_TOOLS_CEILING" ]; then
            bad="$bad
  $rel: needs GLIBC_$ceil > $GLIBC_TOOLS_CEILING"
          fi
          if [ -z "$worst" ] || [ "$(printf '%s\n' "$ceil" "$worst" | sort -V | tail -1)" = "$ceil" ]; then worst="$ceil"; fi
        fi
      fi
    done < "$WORK/copies.txt"
    what="$n_bin ELF files: DT_NEEDED glibc's only, rpaths relative, GLIBC at most ${worst:-?} (ceiling $GLIBC_TOOLS_CEILING)"
    ;;
  macos)
    while IFS= read -r f; do
      head -c4 "$f" | od -An -tx1 | grep -q "cf fa ed fe" || continue
      n_bin=$((n_bin + 1))
      rel="${f#"$TREE"/}"
      if m="$(minos_over_floor "$f")"; then bad="$bad
  $rel: minos $m > $MACOS_MIN"; fi
      id="$(otool -D "$f" 2>/dev/null | tail -n +2)"
      for dep in $(needed_of "$f"); do
        [ "$dep" = "$id" ] && continue
        case "$dep" in /usr/lib/*|/System/Library/*) ;; *) bad="$bad
  $rel: loads $dep (not the system's)" ;; esac
      done
      for rp in $(rpaths_of "$f"); do
        case "$rp" in @loader_path|@loader_path/*) ;; *) bad="$bad
  $rel: rpath $rp" ;; esac
      done
    done < "$WORK/copies.txt"
    what="$n_bin Mach-O files: dependencies the system's, minos <= $MACOS_MIN, rpaths relative"
    ;;
  windows)
    while IFS= read -r f; do
      case "$f" in *.[Ee][Xx][Ee]|*.[Dd][Ll][Ll]) ;; *) continue ;; esac
      n_bin=$((n_bin + 1))
      for dep in $(needed_of "$f"); do
        [ -f "${f%/*}/$dep" ] || win_system_dll "$dep" || bad="$bad
  ${f#"$TREE"/}: imports $dep (neither beside it nor the system's)"
      done
    done < "$WORK/copies.txt"
    what="$n_bin PE files: every DLL they import beside them or the system's"
    ;;
esac
if [ -n "$bad" ]; then
  echo "error: the toolchain's binaries load or need what the tree does not hold:$bad" >&2
  exit 1
fi
echo "== closures verified: $what"

# OpenMP's compile files, where rzig looks for them (B22, B40).
omp="openmp/include/omp.h"
[ "$OS" = windows ] && omp="$omp openmp/lib/libomp.lib"
for f in $omp; do
  [ -s "$TREE/$tc/$f" ] || { echo "error: $tc/$f is missing (the compilers group's OpenMP)" >&2; exit 1; }
done
echo "== OpenMP verified: $omp (in $tc)"
echo "== toolchain tree verified ($OS)"
