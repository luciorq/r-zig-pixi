#!/usr/bin/env bash
# Checks of the recommended packages' tree (zig-recommended.sh; env.sh's
# RECOMMENDED_PREFIX), what r-zig-recommended and the standalone
# recommended archive ship, against the flavor's R tree, the base it is
# installed over (feat-recommended-packages PLAN.md):
#   - it holds R_HOME/library/<pkg>/ for R's 15 recommended packages and
#     nothing else (no lock directory, no build root);
#   - every library a package binary needs is the base's (R_HOME/lib or
#     <prefix>/lib on unix, R_HOME/bin/x64 on Windows) or the system's;
#     linux: a bare name, no glibc above 2.17; macOS: install names and
#     dependencies relative or the system's, minos at or below MACOS_MIN;
#     no shared C++ runtime;
#   - every rpath is relative to its file;
#   - no file names the checkout, the env, zig's or rzig's caches, the
#     compile tree, the tree's own place or $HOME, R's compressed files
#     read uncompressed as verify-tree.sh reads them, except the saved
#     namespace information (uncompress-r-objects.R's *.rdx.namespace),
#     which holds the install directory and which R never loads;
#   - recipe/test-recommended.R passes with the base's R and the tree's
#     library first in R_LIBS.
#
# Usage: verify-recommended.sh [TREE]   (default: RECOMMENDED_PREFIX)
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

TREE="${1:-$RECOMMENDED_PREFIX}"
BASE="$PREFIX"
if command -v cygpath > /dev/null 2>&1; then
  TREE="$(cygpath -u "$TREE")"
  BASE="$(cygpath -u "$BASE")"
fi
LIB="$TREE/$RH/library"
test -d "$LIB" || { echo "error: no library at $LIB: run 'pixi run recommended' first" >&2; exit 1; }
test -d "$BASE/$RH" || { echo "error: no R tree at $BASE: run 'pixi run build' first" >&2; exit 1; }
TREE="$(cd "$TREE" && pwd)"; LIB="$TREE/$RH/library"
echo "== verifying the recommended packages in $TREE over $BASE ($OS/$FLAVOR)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
r_path() { if [ "$OS" = windows ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
if [ "$OS" = windows ]; then rscript="$BASE/$RH/bin/x64/Rscript.exe"; else rscript="$BASE/$RH/bin/Rscript"; fi

# Layout: the 15 names, as R itself lists them, and nothing beside them.
want="$("$rscript" --vanilla -e 'cat(tools:::.get_standard_package_names()$recommended, sep = "\n")' | tr -d '\r')"
[ "$(printf '%s\n' "$want" | grep -c .)" = 15 ] || { echo "error: R names $(printf '%s\n' "$want" | grep -c .) recommended packages, not 15" >&2; exit 1; }
have="$(cd "$LIB" && ls -A)"
if [ "$(printf '%s\n' "$have" | sort)" != "$(printf '%s\n' "$want" | sort)" ]; then
  echo "error: $LIB holds: $(echo $have); R's recommended packages are: $(echo $want)" >&2
  exit 1
fi
odd="$(cd "$TREE" && find . ! -type d | grep -v "^\./$RH/library/" || true)"
[ -z "$odd" ] || { echo "error: files outside $RH/library:"$'\n'"$odd" >&2; exit 1; }
odd="$(cd "$LIB" && find . -name '00LOCK*' -o -name '.rzig*' -o -name '*.o')"
[ -z "$odd" ] || { echo "error: build leftovers in the library ($(printf '%s\n' "$odd" | wc -l | tr -d ' ')):"$'\n'"$(printf '%s\n' "$odd" | sed -n 1,5p)" >&2; exit 1; }
echo "== layout verified: $RH/library holds R's 15 recommended packages only"

# The package binaries.
bin_list="$WORK/bins.txt"
case "$OS" in
  linux) find "$LIB" -type f -name '*.so' > "$bin_list" ;;
  macos) find "$LIB" -type f \( -name '*.so' -o -name '*.dylib' \) > "$bin_list" ;;
  windows) find "$LIB" -type f -iname '*.dll' > "$bin_list" ;;
esac
n_bins="$(grep -c . "$bin_list" || true)"
[ "$n_bins" -gt 0 ] || { echo "error: no package binary under $LIB" >&2; exit 1; }

# Each library a binary needs, and where it comes from.
base_has() {
  local d
  for d in "$BASE/$RH/lib" "$BASE/lib" "$BASE/$RH/bin/x64"; do
    [ -e "$d/$1" ] && return 0
  done
  return 1
}
bad=""; seen=""
while IFS= read -r f; do
  rel="${f#"$LIB"/}"
  # macOS: a library's own install name, first in needed_of's list: a
  # bare or relative name, as verify-tree.sh allows
  id=""
  if [ "$OS" = macos ]; then
    id="$(otool -D "$f" 2>/dev/null | tail -n +2)"
    case "$id" in ""|@rpath/*|@loader_path/*|[!/]*) ;; *) bad="$bad
  $rel: install name $id" ;; esac
  fi
  for dep in $(needed_of "$f" | tr -d '\r'); do
    [ -n "$id" ] && [ "$dep" = "$id" ] && continue
    case "$OS" in
      linux)
        case "$dep" in
          */*) bad="$bad
  $rel: $dep (a path)"; continue ;;
          libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*) ;;
          *) base_has "$dep" || bad="$bad
  $rel: $dep (not in the base)" ;;
        esac ;;
      macos)
        case "$dep" in
          @rpath/*|@loader_path/*) base_has "${dep##*/}" || bad="$bad
  $rel: $dep (not in the base)" ;;
          /usr/lib/*|/System/Library/*) ;;
          *) bad="$bad
  $rel: $dep" ;;
        esac ;;
      windows)
        base_has "$dep" || win_system_dll "$dep" || bad="$bad
  $rel: $dep (not in the base or System32)" ;;
    esac
    seen="$seen
$dep"
  done
  hit="$(cxx_deps "$f")"
  [ -z "$hit" ] || bad="$bad
  $rel: a shared C++ runtime ($hit)"
  if [ "$OS" != windows ]; then
    for rp in $(rpaths_of "$f"); do
      case "$rp" in '$ORIGIN'|'$ORIGIN/'*|@loader_path|@loader_path/*) ;; *) bad="$bad
  $rel: rpath $rp" ;; esac
    done
  fi
  if [ "$OS" = macos ] && m="$(minos_over_floor "$f")"; then bad="$bad
  $rel: minos $m above $MACOS_MIN"; fi
  if [ "$OS" = linux ] && command -v objdump > /dev/null 2>&1; then
    ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
    if [ -n "$ceil" ] && [ "$(printf '%s\n' "$ceil" 2.17 | sort -V | tail -1)" != 2.17 ]; then bad="$bad
  $rel: needs GLIBC_$ceil"; fi
  fi
done < "$bin_list"
if [ -n "$bad" ]; then
  echo "error: package binaries:$bad" >&2
  exit 1
fi
echo "== binaries verified: $n_bins, each library the base's or the system's, rpaths relative; they need:$(printf '%s\n' "$seen" | sort -u | tr '\n' ' ')"

# No build path, in the files and in R's compressed files' objects.
conda_dir="${CONDA_PREFIX:-}"
command -v cygpath > /dev/null 2>&1 && [ -n "$conda_dir" ] && conda_dir="$(cygpath -u "$conda_dir")"
dirs=("$ROOT" "$TREE" "$BUILD_DIR" "$COMPILE_TREE" "${ZIG_GLOBAL_CACHE_DIR:-}" "$conda_dir")
case "${HOME:-}" in /*/[!/]*) dirs+=("$HOME") ;; esac
if [ "$OS" = windows ] && [ -n "${USERPROFILE:-}" ]; then dirs+=("$(cygpath -u "$USERPROFILE")"); fi
re="$(path_forms "${dirs[@]}" | path_re)"
icase=()
[ "$OS" = windows ] && icase=(-i)
ser="$WORK/serialized"
"$rscript" --vanilla "$(r_path "$ROOT/scripts/uncompress-r-objects.R")" "$(r_path "$LIB")" "$(r_path "$ser")" ||
  { echo "error: the base's R could not read the packages' lazy-load databases and .rds files" >&2; exit 1; }
named="$( { grep -rlaE "${icase[@]}" -e "$re" "$LIB" || true; grep -rlaE "${icase[@]}" -e "$re" "$ser" 2> /dev/null || true; } )"
offenders=""; n_ns=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.rdx.namespace) n_ns=$((n_ns + 1)); continue ;; esac
  offenders="$offenders
  ${f#"$WORK"/}: $(grep -aoE "${icase[@]}" -e "($re)[^[:space:][:cntrl:]\"'<>]*" "$f" | sed -n 1p | cut -c1-200)"
done <<< "$named"
if [ -n "$offenders" ]; then
  echo "error: files that name a build path:$offenders" >&2
  exit 1
fi
echo "== no build path: $(find "$LIB" -type f | wc -l | tr -d ' ') files, $(find "$ser" -type f | wc -l | tr -d ' ') uncompressed R objects ($n_ns packages' saved namespace information names their install directory; R never loads it)"

# The packages at work, with the base's R.
(cd "$WORK" && R_LIBS="$(r_path "$LIB")" R_LIBS_USER=NULL R_LIBS_SITE=NULL R_ENVIRON_USER="$(r_path "$WORK/none")" R_PROFILE_USER="$(r_path "$WORK/none")" \
  "$rscript" "$(r_path "$ROOT/recipe/test-recommended.R")") ||
  { echo "error: recipe/test-recommended.R failed against $LIB" >&2; exit 1; }
echo "== recommended packages verified ($OS/$FLAVOR)"
