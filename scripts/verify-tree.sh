#!/usr/bin/env bash
# Static checks of the installed R tree, the tree that ships
# (feat-no-host-paths PLAN.md, F1 and F1.6). `zig build` installs it into
# dist/R-<ver>-<flavor>-zig (Windows: its Library/ layout), zig-build.sh
# vendors the env's libraries into it, and package-standalone.sh archives
# it. CI runs this right after the build, before smoke, contract, check
# and hermetic, so a tree that names the build machine fails at once.
#
# Usage: verify-tree.sh [TREE]   (default: zig-build.sh's prefix)
#
# Everything here reads files, headers and load commands, so the answer
# does not depend on where the tree sits:
#   - the compilers Makeconf names are rzig (one binary, no scripts);
#   - Makeconf names no build path and has no rpath; CPPFLAGS and LDFLAGS
#     are empty; FLIBS is the bare -lflang_rt.runtime; FC is zig-fc;
#   - minimal: no binary of R's own links a library the profile excludes;
#   - linux: no ELF needs a glibc above the floor (2.17; toolchain helpers
#     conda-forge's 2.28);
#   - unix: every rpath is relative to its file; none of R's own binaries
#     needs a shared C++ runtime;
#   - macOS: every Mach-O at or below MACOS_MIN; install names relative,
#     dependencies relative or the system's, and only what conda has no
#     copy of from the SDK's /usr/lib.
# verify-bundle.sh (pixi task verify-package, after package) keeps what
# only a moved, environment-free copy can show: the archive extracts, R
# runs from the new place under env -i, TLS trust with the shipped CA
# bundle, and packages compiled with the relocated tree build and load
# under env -i (C++, Fortran, USE_FC_TO_LINK, FLIBS without flang,
# OpenMP, decoy CONDA_PREFIX runs, zig-fc with no flang; Windows: rzig's
# dry runs). The archive is this tree plus what package-standalone.sh
# adds (fontconfig's configuration, the CA bundle; vendor-libs.sh again,
# a no-op on a tree zig-build.sh vendored; on Windows the DLLs and Tcl),
# none of which the checks here read; so they run once, here. (What runs
# in between leaves the tree as it was: smoke and check only run it,
# contract installs into build/testlib-*, hermetic works on a copy.)
# Shared helpers (rpaths_of, needed_of, cxx_deps, minos_over_floor):
# verify-helpers.sh; MACOS_MIN, macho_minos, version_gt: env.sh.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

TREE="${1:-${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}}"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
if [ "$OS" = windows ]; then rh="Library/lib/R"; else rh="lib/R"; fi
test -d "$TREE/$rh" || { echo "error: no R tree at $TREE ($rh missing): run 'pixi run build' first" >&2; exit 1; }
TREE="$(cd "$TREE" && pwd)"
echo "== verifying the installed tree $TREE ($OS/$FLAVOR)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The compilers Makeconf names are rzig (feat-no-host-paths F3), one
# binary under every name: compiling runs no shell script of ours. FC is
# rzig's zig-fc (F3c).
if [ "$OS" = windows ]; then
  tc_dir="$rh/bin/toolchain"; tc_names="gcc.exe g++.exe zig-fc.exe zig-cc zig-cxx"
else
  tc_dir="$rh/bin/toolchain"; tc_names="zig-cc zig-cxx zig-fc zig-ar zig-ranlib"
fi
for t in $tc_names; do
  f="$TREE/$tc_dir/$t"
  if [ ! -f "$f" ] || [ "$(head -c2 "$f")" = '#!' ] || ! cmp -s "$f" "$TREE/$tc_dir/${tc_names%% *}"; then
    echo "error: $tc_dir/$t is missing, a script, or not the same rzig as the rest" >&2
    exit 1
  fi
done
echo "== compilers verified: $tc_dir/{${tc_names// /,}} are rzig"

# Makeconf names no build path (feat-no-host-paths F1.5): build.zig writes
# the environment as $(R_HOME)/../.., FLIBS as -lflang_rt.runtime and no
# rpath, and nothing edits the file afterwards. Comment lines count.
# CPPFLAGS and LDFLAGS are empty (F3b): the compilers, rzig, add the
# environment's -I and -L (and a conda env's rpath) themselves. FC is
# rzig's zig-fc (F3c), which runs the flang on PATH.
if [ "$OS" = windows ]; then mk="$TREE/$rh/etc/x64/Makeconf"; else mk="$TREE/$rh/etc/Makeconf"; fi
bad=""
# Windows: ROOT and TREE are env.sh's /c/... form; PIXI_PROJECT_ROOT is the
# native one, and a leak is written C:\... or C:/... (any drive-letter
# case). The tree's own place counts too (it may sit outside ROOT).
own=("$TREE" "$(cd "$TREE" && pwd -P)")
[ "$OS" = windows ] && own+=("$(cygpath -w "$TREE")")
for p in "$ROOT" "${PIXI_PROJECT_ROOT:-}" "${CONDA_PREFIX:-}" "${own[@]}"; do
  [ -n "$p" ] || continue
  for q in "$p" "$(printf '%s' "$p" | tr '\\' /)"; do
    case "$bad " in *" $q "*) continue ;; esac   # (named once)
    if grep -qiF -- "$q" "$mk"; then bad="$bad $q"; fi
  done
done
if grep -q -- '-rpath' "$mk"; then bad="$bad -rpath"; fi
grep -q '^FLIBS = .*-lflang_rt\.runtime' "$mk" || bad="$bad FLIBS"
# (on Windows inside the template's USE_LLVM else branch, indented)
grep -Eq '^ *FC = \$\(R_HOME\)/bin/toolchain/zig-fc *'$'\r''?$' "$mk" || bad="$bad FC-not-zig-fc"
for v in CPPFLAGS LDFLAGS; do
  # (the x64 Makeconf has CRLF line ends)
  grep -Eq "^$v = *"$'\r'"?\$" "$mk" || bad="$bad $v-not-empty"
  if [ "$OS" != windows ] && grep -Eq "'$v=" "$mk"; then bad="$bad $v-in-configure-line"; fi
done
if [ -n "$bad" ]; then
  echo "error: ${mk#$TREE/} names build paths or lacks the relative forms:$bad" >&2
  exit 1
fi
echo "== Makeconf verified: no build path, no rpath, CPPFLAGS and LDFLAGS empty, FLIBS = -lflang_rt.runtime, FC = zig-fc"

# Windows has no rpaths, glibc or Mach-O: the binary checks below are unix.
# (Its DLLs are vendored by package-standalone.sh; verify-bundle.sh and
# the hermetic check run R from that tree.)
if [ "$OS" = windows ]; then
  echo "== installed tree verified ($OS/$FLAVOR)"
  exit 0
fi

# minimal: the point of the profile is what R does NOT link. No binary
# of R's own (libR, modules, base-package .so, bin/exec/R) may name a
# library from the graphics/ICU/OpenMP/libdeflate stacks. That is the
# part the configure profile controls; what third-party libraries drag
# in is reported, not failed: conda-forge's libcurl >= 8.21 links
# libpsl, which links ICU (and so libstdc++), on every platform — see
# pixi.toml's [feature.minimal] for the size cost and the pin that would
# avoid it.
if [ "$VARIANT" = minimal ]; then
  excluded_re='lib(cairo|pango|harfbuzz|fontconfig|freetype|glib|gobject|gio|pixman|png|jpeg|tiff|X11|xcb|icu|omp|iomp|gomp|deflate)'
  r_bins="$WORK/r-bins.txt"
  find "$TREE/lib/R" -path "$TREE/lib/R/bin/toolchain" -prune -o \
    -type f \( -name '*.so' -o -name '*.dylib' -o -path '*/bin/exec/R' \) -print > "$r_bins"
  bad=""
  while IFS= read -r f; do
    hit="$(needed_of "$f" | grep -E "(^|/)$excluded_re" || true)"
    [ -z "$hit" ] || bad="$bad ${f#$TREE/}->$(echo $hit | tr ' ' ',')"
  done < "$r_bins"
  if [ -n "$bad" ]; then
    echo "error: minimal R links libraries its profile excludes:$bad" >&2
    exit 1
  fi
  echo "== minimal profile verified: $(wc -l < "$r_bins" | tr -d ' ') R binaries, none links graphics/ICU/OpenMP/libdeflate"
  transitive="$(ls "$TREE/lib" | grep -E "^$excluded_re" | tr '\n' ' ' || true)"
  [ -z "$transitive" ] || echo "   note: vendored as dependencies of third-party libs (not of R): $transitive"
fi

# Every ELF (linux) or 64-bit Mach-O (macOS) file in the tree, by magic
# number: R's own binaries, the vendored libraries in lib/ and the tools
# in lib/R/bin/toolchain. The list is collected first, then checked: an
# `exit 1` inside a `while read < <(find ...)` loop fires the EXIT trap's
# rm -rf while find is still walking (the first CI failure of the glibc
# check was a screenful of that noise after the real error line).
bin_list="$WORK/bin-list.txt"
if [ "$OS" = linux ]; then
  find "$TREE" -type f \( -name '*.so*' -o -perm -u+x \) \
    -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "7f 45 4c 46"' _ {} \; -print > "$bin_list"
else
  find "$TREE" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) \
    -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "cf fa ed fe"' _ {} \; -print > "$bin_list"
fi
n_bins="$(wc -l < "$bin_list" | tr -d ' ')"
[ "$n_bins" -gt 0 ] || { echo "error: no binaries found under $TREE" >&2; exit 1; }

# Old-server guarantee (Linux only): fail if any shipped ELF requires glibc
# newer than the floor build.zig's target pin promises. This is the check
# side of the floor — a zig update or stray flag that raises the
# requirement should die here, not on a customer's old box.
#
# Two tiers, learned from the first hosted-CI run of this check
# (2026-09-19): everything R needs to *run* (R itself, its modules and
# package .so files, every vendored library under lib/) must stay at the
# 2.17 floor — and does. The compile-time helper tools build.zig installs
# into lib/R/bin/toolchain (nm/realpath/sed/... for bin/libtool and
# javareconf) come from conda-forge, whose linux baseline is glibc 2.28
# now: coreutils' `realpath` needs GLIBC_2.28, nothing else did. Those
# tools only run when compiling packages or reconfiguring Java, which
# already requires a development machine with zig on PATH, so they are
# bounded at conda-forge's own baseline instead — anything above *that*
# still trips (a host tool leaking in, conda-forge moving to 2.34).
if [ "$OS" = linux ]; then
  GLIBC_FLOOR="2.17"          # runtime artifacts: R + vendored libs
  GLIBC_TOOLS_CEILING="2.28"  # lib/R/bin/toolchain helpers (conda-forge baseline)
  worst=""; worst_file=""; tools_over=0; failed=0
  while IFS= read -r f; do
    # `|| true`: an ELF with no versioned glibc imports makes grep exit 1,
    # and env.sh's pipefail + set -e would silently kill the whole script
    # on that assignment (latent in the first version of this check too).
    ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
    [ -z "$ceil" ] && continue
    case "$f" in
      "$TREE"/lib/R/bin/toolchain/*) limit="$GLIBC_TOOLS_CEILING"; tier="toolchain helper" ;;
      *) limit="$GLIBC_FLOOR"; tier="runtime" ;;
    esac
    if [ "$(printf '%s\n' "$ceil" "$limit" | sort -V | tail -1)" != "$limit" ]; then
      echo "error: $f ($tier) requires GLIBC_$ceil > $limit" >&2
      failed=1
    elif [ "$tier" = "toolchain helper" ] && [ "$(printf '%s\n' "$ceil" "$GLIBC_FLOOR" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]; then
      echo "note: ${f#$TREE/} (toolchain helper, compile-time only) requires GLIBC_$ceil > runtime floor $GLIBC_FLOOR"
      tools_over=$((tools_over + 1))
    fi
    if [ "$tier" = runtime ] && { [ -z "$worst" ] || [ "$(printf '%s\n' "$ceil" "$worst" | sort -V | tail -1)" = "$ceil" ]; }; then
      worst="$ceil"; worst_file="${f#$TREE/}"
    fi
  done < "$bin_list"
  [ "$failed" = 0 ] || exit 1
  echo "== glibc ceiling verified: runtime worst $worst ($worst_file) <= floor $GLIBC_FLOOR; $tools_over toolchain helper(s) above the floor, all <= $GLIBC_TOOLS_CEILING"
fi

# No build-machine rpaths. Every RUNPATH/LC_RPATH entry in the tree must be
# relative to the file ($ORIGIN, @loader_path): zig records the build
# env's lib dir and zig-cache dirs unless told not to, which build.zig
# does (relRPaths, linkSibling). (That a package compiled with the tree
# records none, and loads, is verify-bundle.sh's: it compiles with the
# relocated copy.)
bad=""
while IFS= read -r f; do
  for rp in $(rpaths_of "$f"); do
    case "$rp" in '$ORIGIN'|'$ORIGIN/'*|@loader_path|@loader_path/*) ;; *) bad="$bad
  ${f#$TREE/}: $rp" ;; esac
  done
done < "$bin_list"
if [ -n "$bad" ]; then
  echo "error: build-machine rpaths in the tree:$bad" >&2
  exit 1
fi
echo "== rpaths verified: $n_bins binaries, all relative"

# Static libc++ everywhere (decided 2026-09-30): none of R's own
# binaries may depend on a shared C++ runtime. The vendored conda
# libraries in lib/ may (ICU links libc++ on macOS, libstdc++ on linux);
# they are not ours to build.
bad=""
n_r=0
while IFS= read -r f; do
  case "$f" in "$TREE"/lib/R/bin/toolchain/*) continue ;; "$TREE"/lib/R/*) ;; *) continue ;; esac
  n_r=$((n_r + 1))
  hit="$(cxx_deps "$f")"
  [ -z "$hit" ] || bad="$bad ${f#$TREE/}->$(echo $hit | tr ' ' ',')"
done < "$bin_list"
if [ -n "$bad" ]; then
  echo "error: R binaries depend on a shared C++ runtime:$bad" >&2
  exit 1
fi
echo "== C++ runtime verified: $n_r R binaries, none needs a shared libc++/libstdc++"

# macOS deployment target: every Mach-O in the tree at or below
# MACOS_MIN (build.zig's macos_min; conda's vendored libraries are
# lower). A native target would stamp the build machine's version.
# Then the load commands: install names relative (packages copy libR's
# into their own load commands), dependencies relative or the system's,
# and R's own binaries take from the SDK's /usr/lib only what conda has
# no copy of: build.zig adds the SDK's lib dir last, and ahead of
# conda's it would bind -lz/-liconv/-lcurl to the SDK's older stubs.
if [ "$OS" = macos ]; then
  bad=""
  while IFS= read -r f; do
    if m="$(minos_over_floor "$f")"; then bad="$bad ${f#$TREE/}=$m"; fi
  done < "$bin_list"
  if [ -n "$bad" ]; then
    echo "error: Mach-O files above the macOS $MACOS_MIN floor:$bad" >&2
    exit 1
  fi
  echo "== macOS floor verified: $n_bins Mach-O files, minos <= $MACOS_MIN"
  bad=""
  while IFS= read -r f; do
    id="$(otool -D "$f" 2>/dev/null | tail -n +2)"
    case "$id" in ""|@rpath/*|@loader_path/*|@executable_path/*|[!/]*) ;; *) bad="$bad ${f#$TREE/}:id=$id" ;; esac
    for dep in $(needed_of "$f"); do
      [ "$dep" = "$id" ] && continue
      case "$dep" in @rpath/*|@loader_path/*|@executable_path/*|/usr/lib/*|/System/Library/*) ;; *) bad="$bad ${f#$TREE/}:$dep" ;; esac
      case "$f" in "$TREE"/lib/R/bin/toolchain/*) ;; "$TREE"/lib/R/*)
        case "$dep" in /usr/lib/libSystem.B.dylib|/usr/lib/libresolv.9.dylib|/usr/lib/libobjc.A.dylib) ;; /usr/lib/*) bad="$bad ${f#$TREE/}:$dep(SDK)" ;; esac ;;
      esac
    done
  done < "$bin_list"
  [ "$(otool -D "$TREE/lib/R/lib/libR.dylib" | tail -n +2)" = "@rpath/libR.dylib" ] || bad="$bad lib/R/lib/libR.dylib:id"
  if [ -n "$bad" ]; then
    echo "error: install names or load commands:$bad" >&2
    exit 1
  fi
  echo "== load commands verified: relative install names, no build-machine or SDK-stub dependencies"
fi

echo "== installed tree verified ($OS/$FLAVOR)"
