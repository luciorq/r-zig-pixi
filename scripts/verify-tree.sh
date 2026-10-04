#!/usr/bin/env bash
# Static checks of the installed R tree, the tree that ships
# (feat-no-host-paths PLAN.md, F1, F1.6 and F1.7). `zig build` installs
# it into dist/R-<ver>-<flavor>-zig (Windows: its Library/ layout) with
# the runtime data it needs from the env (build.zig's installEnvRuntime),
# zig-build.sh then vendors the env's shared libraries into it
# (vendor-libs.sh), and package-standalone.sh only archives it. CI runs
# this right after the build, before smoke, contract, check and hermetic,
# so a tree that names the build machine fails at once.
#
# Usage: verify-tree.sh [TREE]   (default: zig-build.sh's prefix)
#
# Everything here reads files, headers and load commands, so the answer
# does not depend on where the tree sits:
#   - the compilers Makeconf names are rzig (one binary, no scripts);
#   - Makeconf names no build path and has no rpath; CPPFLAGS and LDFLAGS
#     are empty; FLIBS is the bare -lflang_rt.runtime; FC is zig-fc;
#   - where Makeconf offers OpenMP (a tree that is not a conda env, not
#     minimal): omp.h and libomp where rzig and the loader find them
#     (Windows: Library/include/omp.h, Library/lib/libomp.lib and
#     R_HOME/bin/x64/libomp.dll; unix: include/omp.h and lib/libomp);
#   - Windows (a tree that is not a conda env): the Tcl/Tk runtime is in
#     R_HOME/Tcl (with Tcl's modules), and every DLL a PE file in the tree
#     imports is in the tree (its own directory, R_HOME/bin/x64, or
#     R_HOME/Tcl/bin for the Tcl/Tk DLLs) or the system's;
#   - unix (a tree that is not a conda env): etc/ca-bundle.crt holds
#     certificates and etc/Renviron names it in R_ZIG_CA_BUNDLE; with
#     tcltk (full), Tcl/Tk's script libraries and Tcl's modules are in
#     <prefix>/lib and etc/Renviron points TCL_LIBRARY there;
#   - minimal: no binary of R's own links a library the profile excludes;
#   - linux: no ELF needs a glibc above the floor (2.17; toolchain helpers
#     conda-forge's 2.28);
#   - unix: every rpath is relative to its file; none of R's own binaries
#     needs a shared C++ runtime; linux: every DT_NEEDED is a bare name;
#   - macOS: every Mach-O at or below MACOS_MIN; install names relative,
#     dependencies relative or the system's, and only what conda has no
#     copy of from the SDK's /usr/lib.
# verify-bundle.sh (pixi task verify-package, after package) keeps what
# only a moved, environment-free copy can show: the archive extracts, R
# runs from the new place under env -i, TLS trust with the shipped CA
# bundle, and packages compiled with the relocated tree build and load
# under env -i (C++, Fortran, USE_FC_TO_LINK, FLIBS without flang,
# OpenMP, decoy CONDA_PREFIX runs, zig-fc with no flang; Windows: rzig's
# dry runs, and OpenMP C and Fortran packages built with the tree alone
# and loaded with only bin\x64 and System32 on PATH). The archive is
# this tree as it is, so the checks here run once, here. (What runs in
# between leaves the tree as it was: smoke and check only run it,
# contract installs into build/testlib-*, hermetic works on a copy.)
# Shared helpers (rpaths_of, needed_of, cxx_deps, minos_over_floor,
# win_system_dll): verify-helpers.sh; MACOS_MIN, macho_minos, version_gt:
# env.sh.
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

# What a tree that is not a conda env carries from the env: the runtime
# data build.zig installs (installEnvRuntime) and the shared libraries
# vendor-libs.sh copies. A conda env (<tree>/conda-meta, the conda build's
# prefix) has both from its own packages, and gets neither.
conda_tree=""
if [ -d "$TREE/conda-meta" ]; then conda_tree=1; fi

# OpenMP for packages (build.zig installOpenMP, vendor-libs.sh), wherever
# Makeconf offers it (SHLIB_OPENMP_CFLAGS non-empty: every variant but
# minimal): llvm-openmp's omp.h in the environment's include/, where rzig
# looks (and finding it is what makes rzig add -lomp to a -fopenmp link),
# and libomp where links and the loader find it. Windows: libomp.lib in
# Library/lib, and libomp.dll in R_HOME/bin/x64 beside R's executables
# (vendor-libs.sh copies it there because the tree has libomp.lib); R
# itself has no OpenMP there (upstream's choice), so nothing in the tree
# imports it and the DLL closure check below would not notice it
# missing. unix: libR links libomp, which vendor-libs.sh copies into
# lib/. (That a package builds with these alone and loads:
# verify-bundle.sh.)
if [ -z "$conda_tree" ] && grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
  case "$OS" in
    windows) omp_files="Library/include/omp.h Library/lib/libomp.lib $rh/bin/x64/libomp.dll" ;;
    linux) omp_files="include/omp.h lib/libomp.so" ;;
    macos) omp_files="include/omp.h lib/libomp.dylib" ;;
  esac
  bad=""
  for f in $omp_files; do
    [ -s "$TREE/$f" ] || bad="$bad $f"
  done
  if [ -n "$bad" ]; then
    echo "error: Makeconf offers OpenMP (SHLIB_OPENMP_CFLAGS), but the tree lacks:$bad" >&2
    exit 1
  fi
  echo "== OpenMP for packages verified: ${omp_files// /, }"
fi

# Windows has no rpaths, glibc or Mach-O: the binary checks further down
# are unix. Its own: the Tcl/Tk runtime and the DLL closure.
if [ "$OS" = windows ]; then
  if [ -z "$conda_tree" ]; then
    # Tcl/Tk where tcltk's .onLoad loads it (CRAN's layout): the DLLs in
    # Tcl/bin, through library.dynam's DLLpath, and only there (a copy in
    # bin/x64 wins the search order, then looks for init.tcl relative to
    # itself and fails); the script libraries in Tcl/lib (TCLLIBPATH), and
    # Tcl's modules in Tcl/lib/tcl8 (msgcat, which `clock` needs).
    bad=""
    for f in Tcl/bin/tcl86t.dll Tcl/bin/tk86t.dll Tcl/lib/tcl8.6/init.tcl Tcl/lib/tk8.6/tk.tcl; do
      [ -s "$TREE/$rh/$f" ] || bad="$bad $f(missing)"
    done
    [ -n "$(find "$TREE/$rh/Tcl/lib/tcl8" -name 'msgcat-*.tm' 2>/dev/null)" ] || bad="$bad Tcl/lib/tcl8/*/msgcat-*.tm(missing)"
    for f in tcl86t.dll tk86t.dll; do
      [ ! -e "$TREE/$rh/bin/x64/$f" ] || bad="$bad bin/x64/$f(misplaced)"
    done
    if [ -n "$bad" ]; then
      echo "error: the Tcl/Tk runtime in $rh/Tcl:$bad" >&2
      exit 1
    fi
    echo "== Tcl/Tk runtime verified: $rh/Tcl/bin/{tcl86t,tk86t}.dll (none in bin/x64), $(find "$TREE/$rh/Tcl/lib" -type f | wc -l | tr -d ' ') files in Tcl/lib"

    # The DLL closure: every DLL a PE file in the tree imports is found in
    # the tree, where the loader looks for it (the file's own directory;
    # R_HOME/bin/x64, the directory of R's executables, where vendor-libs.sh
    # copies conda's DLLs; R_HOME/Tcl/bin for the Tcl/Tk DLLs), or is the
    # system's (System32, or an API set). A conda DLL missing here would
    # load from the build machine's PATH in every check that has the env
    # on PATH, and fail only on a user's machine.
    pe_list="$WORK/pe-list.txt"
    find "$TREE" -type f \( -name '*.dll' -o -name '*.exe' \) > "$pe_list"
    n_pe="$(wc -l < "$pe_list" | tr -d ' ')"
    [ "$n_pe" -gt 0 ] || { echo "error: no DLL or EXE files found under $TREE" >&2; exit 1; }
    bad=""
    : > "$WORK/in-tree.txt"; : > "$WORK/system.txt"
    while IFS= read -r f; do
      pe_dir="${f%/*}"
      for dep in $(needed_of "$f"); do
        case "$dep" in
          tcl86t.dll|tk86t.dll) where="$TREE/$rh/Tcl/bin" ;;
          *) where="$TREE/$rh/bin/x64" ;;
        esac
        if [ -f "$pe_dir/$dep" ] || [ -f "$where/$dep" ]; then
          echo "$dep" >> "$WORK/in-tree.txt"
        elif win_system_dll "$dep"; then
          echo "$dep" >> "$WORK/system.txt"
        else
          bad="$bad
  ${f#$TREE/}: $dep"
        fi
      done
    done < "$pe_list"
    if [ -n "$bad" ]; then
      echo "error: DLLs imported but not in the tree (vendor-libs.sh copies conda's into $rh/bin/x64) nor the system's:$bad" >&2
      exit 1
    fi
    echo "== DLL closure verified: $n_pe PE files; $(sort -fu "$WORK/in-tree.txt" | wc -l | tr -d ' ') DLLs they import are in the tree, $(sort -fu "$WORK/system.txt" | wc -l | tr -d ' ') the system's"
  fi
  echo "== installed tree verified ($OS/$FLAVOR)"
  exit 0
fi

# TLS trust (build.zig's installEnvRuntime): a tree that is not a conda env
# ships the env's Mozilla bundle as etc/ca-bundle.crt, and etc/Renviron
# names it in R_ZIG_CA_BUNDLE, the patched libcurl.c's last fallback
# (zigbuild/patches/); without either, HTTPS fails on any other machine.
# (HTTPS with it: verify-bundle.sh, on the extracted archive.)
if [ -z "$conda_tree" ]; then
  ca="lib/R/etc/ca-bundle.crt"
  n_ca="$(grep -c 'BEGIN CERTIFICATE' "$TREE/$ca" 2>/dev/null || true)"
  if [ "${n_ca:-0}" -eq 0 ]; then
    echo "error: $ca is missing or holds no certificates" >&2
    exit 1
  fi
  if ! grep -qxF 'R_ZIG_CA_BUNDLE=${R_HOME}/etc/ca-bundle.crt' "$TREE/lib/R/etc/Renviron"; then
    echo "error: lib/R/etc/Renviron does not set R_ZIG_CA_BUNDLE=\${R_HOME}/etc/ca-bundle.crt" >&2
    exit 1
  fi
  echo "== CA bundle verified: $ca ($n_ca certificates), named by R_ZIG_CA_BUNDLE in etc/Renviron"

  # tcltk (full): the vendored libtcl names only the build env's script
  # library, so the tree carries Tcl's and Tk's, and Tcl's modules, in
  # lib/ (Tk's and the modules are found beside Tcl's), and etc/Renviron
  # points TCL_LIBRARY at it (build.zig's installEnvRuntime).
  if [ -n "$(find "$TREE/lib/R/library/tcltk/libs" -name 'tcltk.*' 2>/dev/null)" ]; then
    bad=""
    for f in lib/tcl8.6/init.tcl lib/tk8.6/tk.tcl; do
      [ -s "$TREE/$f" ] || bad="$bad $f(missing)"
    done
    [ -n "$(find "$TREE/lib/tcl8" -name 'msgcat-*.tm' 2>/dev/null)" ] || bad="$bad lib/tcl8/*/msgcat-*.tm(missing)"
    grep -qxF 'R_ZIG_TCL_LIBRARY=${R_HOME}/../tcl8.6' "$TREE/lib/R/etc/Renviron" &&
      grep -qxF 'TCL_LIBRARY=${TCL_LIBRARY-${R_ZIG_TCL_LIBRARY}}' "$TREE/lib/R/etc/Renviron" ||
      bad="$bad etc/Renviron(no TCL_LIBRARY)"
    if [ -n "$bad" ]; then
      echo "error: tcltk's Tcl/Tk scripts:$bad" >&2
      exit 1
    fi
    echo "== Tcl/Tk scripts verified: lib/{tcl8.6,tk8.6,tcl8}, TCL_LIBRARY in etc/Renviron"
  fi
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

# linux: every DT_NEEDED is a bare name, found through those rpaths. lld
# records the path it was given for a library with no DT_SONAME (zig gives
# it the env's absolute one): conda-forge's libtcl and libtk have none,
# which build.zig works around for tcltk.so. Such an entry names the build
# machine, and vendor-libs.sh's walk does not see it. (macOS: the load
# command check below.)
if [ "$OS" = linux ]; then
  bad=""
  while IFS= read -r f; do
    for dep in $(needed_of "$f"); do
      case "$dep" in */*) bad="$bad
  ${f#$TREE/}: $dep" ;; esac
    done
  done < "$bin_list"
  if [ -n "$bad" ]; then
    echo "error: libraries named by path in DT_NEEDED:$bad" >&2
    exit 1
  fi
  echo "== DT_NEEDED verified: $n_bins binaries, every entry a bare name"
fi

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
