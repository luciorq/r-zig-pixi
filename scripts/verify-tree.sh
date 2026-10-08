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
#   - every OS (a tree that is not a conda env): no file of R's own names
#     the build machine's checkout, zig's caches, the env or $HOME; the
#     vendored conda libraries that name one are listed, and so are
#     build.zig's verbatim copies of env files that name only $HOME's
#     path (conda-forge's build path);
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
#   - x86_64 (every OS): no binary of R's own has a VEX or EVEX
#     instruction (AVX, AVX2, FMA, AVX-512, on any register width): R is
#     compiled for the baseline CPU, not the build machine's;
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
# bundle, the CPU its C compiler compiles for (the arch's baseline, every
# OS), and packages compiled with the relocated tree build and load
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

# No path of the build machine in any file of R's own (feat-no-host-paths
# PLAN.md, Goal 1), in a tree that is not a conda env: the checkout (R's
# source, the build dir and, as env.sh keeps them, zig's caches are in
# it), zig's caches wherever they are, the env R was built in
# (CONDA_PREFIX), and $HOME; each as it is set and resolved, matched with
# either separator (doubled too), and on Windows also in its drive form
# (C:/... or C:\..., beside MSYS' /c/...) and in any case. CI's paths
# (/home/runner/work/..., D:\a\...) are just more of these. build.zig
# keeps them out of R's files: -ffile-prefix-map for __FILE__ and the
# debug info (filePathFlags), no tools/misc/top.txt, fontconfig's
# configuration without the env's directories (installFontconfig). Files
# are read as bytes, binaries' strings included; compressed ones (R's
# lazy-load databases, .rds files) are not looked into. Not R's own, and
# listed, not failed:
#   - what vendor-libs.sh vendored from the env, recognised as it
#     recognises it (vendored_files, verify-helpers.sh). conda's
#     libraries carry their env's path compiled in (conda's prefix
#     replacement: libcurl's CA file, OpenSSL's directory, fontconfig's
#     configuration, Tcl's script library, ...); they are conda's
#     binaries, not patched, and R overrides the defaults that matter
#     (R_ZIG_CA_BUNDLE, FONTCONFIG_PATH, TCL_LIBRARY).
#   - a file build.zig copies from the env as it is (minimal's make, the
#     OpenMP headers, fontconfig's conf.d, Tcl/Tk's script libraries;
#     Windows' binutils and Tcl/Tk DLLs), recognised by its bytes (an env
#     file's, under any name), that names $HOME's path and nothing else
#     here: conda-forge's own build path, which is under $HOME when the
#     build machine's user has the name of conda-forge's builder
#     (minimal's make on macOS names /Users/runner/miniforge3/conda-bld/
#     ..., and GitHub's macOS runners run as runner). Such a copy that
#     names the checkout, zig's caches or the env fails: the tree uses
#     these files as they are, so the path would leave the machine with
#     them (fonts.conf's did, before installFontconfig rewrote it).
# A library directly in <prefix>/lib that the env no longer has (unix;
# the build installs only directories there) was left by an earlier
# vendor-libs.sh run (a soname bump); it fails, named as such.
if [ -z "$conda_tree" ]; then
  conda_dir="${CONDA_PREFIX:?run through pixi: the env R was built in is CONDA_PREFIX}"
  command -v cygpath > /dev/null 2>&1 && conda_dir="$(cygpath -u "$conda_dir")"
  build_dirs=("$ROOT" "${PIXI_PROJECT_ROOT:-}" "${ZIG_GLOBAL_CACHE_DIR:-}" "${ZIG_LOCAL_CACHE_DIR:-}" "$conda_dir")
  # $HOME, when it names a directory of its own (/home/<user>,
  # /Users/<user>, /c/Users/<user>): "/" or "/root" would also match what
  # names no build machine.
  home_dirs=()
  case "${HOME:-}" in
    /*/[!/]*) home_dirs+=("$HOME") ;;
    *) echo "   note: \$HOME (${HOME:-unset}) is too short to look for" ;;
  esac
  # Windows: MSYS' HOME need not be the user's profile directory.
  if [ "$OS" = windows ] && [ -n "${USERPROFILE:-}" ]; then home_dirs+=("$(cygpath -u "$USERPROFILE")"); fi
  # Each directory as it is set and resolved (Windows: also C:/..., and
  # with long names).
  path_forms() {
    local d
    for d in "$@"; do
      [ -n "$d" ] || continue
      printf '%s\n' "$d"
      if [ -d "$d" ]; then (cd "$d" && pwd -P); fi
      if [ "$OS" = windows ]; then
        cygpath -m "$d"
        if [ -d "$d" ]; then cygpath -m -l "$d"; fi
      fi
    done
  }
  # One ERE for the paths on stdin: trailing separators dropped, each
  # separator either one, once or more (a newline stands in while the
  # regex characters are escaped), duplicates once. More than once: a
  # Windows binary can hold a path with every backslash doubled (the
  # conda package's R.dll built in CI on 2026-09-25 named its work dir
  # 84 times as D:\\a\\..., and no other way).
  path_re() {
    local f r re=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      r="$(printf '%s' "$f" | sed -e 's#[/\\]*$##' -e 's#[/\\]#\n#g' -e 's#[][*.^$+?(){}|]#\\&#g' -e 's#\n#[/\\\\]+#g')"
      if [ -n "$r" ]; then re="${re:+$re|}$r"; fi
    done < <(sort -u)
    printf '%s\n' "$re"
  }
  re="$(path_forms "${build_dirs[@]}" "${home_dirs[@]}" | path_re)"
  re_build="$(path_forms "${build_dirs[@]}" | path_re)"
  n_paths="$(path_forms "${build_dirs[@]}" "${home_dirs[@]}" | sort -u | grep -c .)"
  icase=()
  [ "$OS" = windows ] && icase=(-i)
  # The first match in file $1 of ERE $2, with what follows it.
  first_match() {
    grep -aoE "${icase[@]}" -e "($2)[^[:space:][:cntrl:]\"'<>]{0,72}" "$1" | head -1 || true
  }
  # The env file (relative to the env) whose bytes file $1 has, among the
  # env's files of its size; fails when there is none.
  env_copy_of() {
    local size g
    size="$(wc -c < "$1" | tr -d ' ')"
    while IFS= read -r g; do
      if cmp -s "$1" "$g"; then
        printf '%s\n' "${g#"$conda_dir"/}"
        return 0
      fi
    done < <(find "$conda_dir" -type f -size "${size}c" 2> /dev/null)
    return 1
  }
  vendored_files "$TREE" "$conda_dir" > "$WORK/vendored.txt"
  n_vendored=0
  while IFS= read -r f; do
    [ -L "$f" ] || n_vendored=$((n_vendored + 1))
  done < "$WORK/vendored.txt"
  n_all="$(find "$TREE" -type f | wc -l | tr -d ' ')"
  grep -rlaE "${icase[@]}" -e "$re" "$TREE" > "$WORK/named.txt" || true
  offenders=""; n_bad=0; vendored_named=""; copies_named=""; n_copies=0
  while IFS= read -r f; do
    rel="${f#"$TREE"/}"
    if grep -qxF -- "$f" "$WORK/vendored.txt"; then
      vendored_named="$vendored_named $rel"
      continue
    fi
    what=""
    if [ "$OS" != windows ] && [ "${f%/*}" = "$TREE/lib" ]; then
      what=" (not R's: a library an earlier vendor-libs.sh run copied, which the env no longer has; remove it, or build a fresh tree)"
    elif src="$(env_copy_of "$f")"; then
      if ! grep -qaE "${icase[@]}" -e "$re_build" "$f"; then
        copies_named="$copies_named
     $rel ($src): $(first_match "$f" "$re")"
        n_copies=$((n_copies + 1))
        continue
      fi
      what=" (build.zig's copy of the env's $src, as it is)"
    elif [ "$OS" = windows ] && [ "${f%/*}" = "$TREE/$rh/bin/x64" ]; then
      what=" (R's own DLL, or one an earlier vendor-libs.sh run copied that the env no longer has: then remove it)"
    fi
    offenders="$offenders
  $rel$what: $(first_match "$f" "$re")"
    n_bad=$((n_bad + 1))
  done < "$WORK/named.txt"
  if [ -n "$offenders" ]; then
    echo "error: $n_bad files name the build machine (the checkout, zig's caches, the env or \$HOME), R's own unless marked, first match each:$offenders" >&2
    exit 1
  fi
  n_vendored_named="$(echo $vendored_named | wc -w | tr -d ' ')"
  echo "== build paths verified: no file of R's own names the checkout, zig's caches, the env or \$HOME ($((n_all - n_vendored)) files besides vendor-libs.sh's; $n_paths distinct paths, either separator)"
  echo "   $n_vendored files vendored from the env, $n_vendored_named of them naming one of those paths, compiled in by conda:${vendored_named:- none}"
  if [ "$n_copies" -gt 0 ]; then
    echo "   build.zig's verbatim copies of env files that name only \$HOME's path, conda-forge's build path: $n_copies$copies_named"
  fi
fi

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

# The baseline CPU (x86_64): R's own binaries are compiled for their
# arch's baseline (build.zig's cpu_model = .baseline), so they run on any
# CPU of the arch, not only on ones like the build machine's. The x86-64
# baseline (SSE2) has no VEX- or EVEX-encoded instruction, the encodings
# of AVX, AVX2, FMA, F16C and AVX-512 at every register width (FMA on
# %xmm included), whose mnemonics all start with v; the base ISA's only
# such mnemonics, verr and verw, are not counted. One in R's own code is
# the build machine's CPU leaking in (an object compiled with
# -mcpu=native, a -march in some flags). Not caught: the extensions that
# keep the legacy encoding (SSE3 to SSE4.2, POPCNT, LZCNT, BMI1/2,
# MOVBE): one of those alone, with no AVX next to it, passes. What CPU
# the toolchain compiles for is verify-bundle.sh's check (the LLVM IR's
# target-cpu, every arch); this one is the backstop on what shipped.
# R's own: every binary under R_HOME but the conda libraries
# vendor-libs.sh copied there (vendored_files: Windows' bin/x64) and the
# env files build.zig copies as they are (Windows' Tcl/Tk in R_HOME/Tcl;
# in the toolchain directory only rzig is R's own, not Windows' binutils
# nor minimal's make). conda-forge's binaries are built for its own
# baseline, and some carry AVX2 code behind a run-time CPU check
# (libdeflate, libcrypto), so they are not counted. objdump: on Windows
# the env's x86_64-w64-mingw32-objdump; on macOS /usr/bin/objdump, which
# is llvm-objdump, from the Command Line Tools the SDK needs anyway; on
# linux the env's, conda-forge's binutils (pixi.toml). Without one the
# check fails, everywhere, saying so. aarch64: the check does not apply.
case "$(uname -m)" in
  x86_64|amd64)
    if [ "$OS" = windows ]; then objdump_cmd=x86_64-w64-mingw32-objdump; else objdump_cmd=objdump; fi
    if ! command -v "$objdump_cmd" > /dev/null 2>&1; then
      echo "error: no $objdump_cmd on PATH for the baseline CPU check" >&2
      exit 1
    fi
    rzig_file="$TREE/$tc_dir/${tc_names%% *}"
    : > "$WORK/vendored-r.txt"
    if [ -z "$conda_tree" ]; then cp "$WORK/vendored.txt" "$WORK/vendored-r.txt"; fi
    case "$OS" in
      windows) find "$TREE/$rh" -path "$TREE/$rh/Tcl" -prune -o -type f \( -iname '*.dll' -o -iname '*.exe' \) -print ;;
      linux) find "$TREE/$rh" -type f \( -name '*.so*' -o -perm -u+x \) \
        -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "7f 45 4c 46"' _ {} \; -print ;;
      macos) find "$TREE/$rh" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) \
        -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "cf fa ed fe"' _ {} \; -print ;;
    esac > "$WORK/r-bins-all.txt"
    : > "$WORK/r-bins.txt"
    while IFS= read -r f; do
      if [ "${f%/*}" = "$TREE/$tc_dir" ] && ! cmp -s "$f" "$rzig_file"; then continue; fi
      if grep -qxF -- "$f" "$WORK/vendored-r.txt"; then continue; fi
      printf '%s\n' "$f" >> "$WORK/r-bins.txt"
    done < "$WORK/r-bins-all.txt"
    n_rb="$(wc -l < "$WORK/r-bins.txt" | tr -d ' ')"
    [ "$n_rb" -gt 0 ] || { echo "error: no binaries of R's own found under $TREE/$rh" >&2; exit 1; }
    # objdump -d --no-show-raw-insn's instruction lines, GNU's and llvm's:
    # "<hex address>:", blanks, the instruction (binutils may put a {vex}
    # or {evex} pseudo-prefix first). Counts: VEX/EVEX instructions, and
    # instructions naming a %ymm, a %zmm register.
    vex_counts() {
      "$objdump_cmd" -d --no-show-raw-insn "$1" | awk '
        !sub(/^[[:space:]]*[0-9a-f]+:[[:space:]]+/, "") { next }
        { sub(/^[{][a-z0-9]+[}][[:space:]]+/, "") }
        /^v[a-z]/ && !/^ver[rw][[:space:]]/ { v++ }
        /%ymm/ { y++ }
        /%zmm/ { z++ }
        END { print v + 0, y + 0, z + 0 }'
    }
    bad=""; n_vex=0; n_ymm=0; n_zmm=0
    while IFS= read -r f; do
      vyz="$(vex_counts "$f")" || { echo "error: $objdump_cmd cannot disassemble ${f#$TREE/}" >&2; exit 1; }
      read -r v y z <<< "$vyz"
      n_vex=$((n_vex + v)); n_ymm=$((n_ymm + y)); n_zmm=$((n_zmm + z))
      if [ "$v" -gt 0 ] || [ "$y" -gt 0 ] || [ "$z" -gt 0 ]; then bad="$bad
  ${f#$TREE/}: $v VEX/EVEX instructions, $y on %ymm, $z on %zmm"; fi
    done < "$WORK/r-bins.txt"
    if [ -n "$bad" ]; then
      echo "error: R's own binaries use AVX-class instructions, beyond the x86-64 baseline (an object compiled for the build machine's CPU):$bad" >&2
      exit 1
    fi
    n_conda=$(($(wc -l < "$WORK/r-bins-all.txt") - n_rb))
    echo "== baseline CPU verified: $n_rb binaries of R's own under R_HOME, $n_vex VEX/EVEX instructions (AVX, FMA, AVX-512), $n_ymm on %ymm, $n_zmm on %zmm ($objdump_cmd -d; $n_conda conda binaries there not counted)"
    ;;
  *) echo "== baseline CPU: the VEX/EVEX check is x86_64's; on $(uname -m) it does not apply" ;;
esac

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
# 2.17 floor — and does. lib/R/bin/toolchain holds what build.zig
# installs for compiling packages: rzig under the compiler names (built
# for R's own target, so at the floor) and, in minimal, conda-forge's
# GNU make (4.4.1 needs GLIBC_2.17 on linux-64). conda-forge's linux
# baseline is glibc 2.28, and these only run when compiling, which
# needs zig anyway, so the toolchain is bounded at that baseline instead
# — anything above *that* still trips (a host tool leaking in,
# conda-forge moving to 2.34). (The 2.28 case was coreutils' `realpath`,
# one of the nm/realpath/sed/... helpers stage.sh copied there until
# phase A5, 5f23127.)
# objdump: conda-forge's binutils (pixi.toml).
if [ "$OS" = linux ] && ! command -v objdump > /dev/null 2>&1; then
  cannot_check "objdump unavailable; glibc ceiling not checked"
elif [ "$OS" = linux ]; then
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
  if [ -z "$worst" ]; then
    cannot_check "objdump -T read no glibc version from any runtime file; glibc ceiling not checked"
  else
    echo "== glibc ceiling verified: runtime worst $worst ($worst_file) <= floor $GLIBC_FLOOR; $tools_over toolchain helper(s) above the floor, all <= $GLIBC_TOOLS_CEILING"
  fi
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
