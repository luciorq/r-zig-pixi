#!/usr/bin/env bash
# Static checks of the installed R tree, the tree that ships
# (feat-no-host-paths PLAN.md, F1, F1.6 and F1.7). `zig build` installs
# it into dist/<flavor>/R-<ver>-zig (Windows: its Library/ layout) with
# the runtime data it needs from the env (build.zig's installEnvRuntime),
# zig-build.sh then vendors the env's shared libraries into it
# (vendor-libs.sh), and package-standalone.sh only archives it. CI runs
# this right after the build, before smoke, contract, check and hermetic,
# so a tree that names the build machine fails at once.
#
# Usage: verify-tree.sh [TREE]   (default: zig-build.sh's prefix)
#
# Everything here reads files, headers and load commands (the tree's own
# Rscript reads its compressed files), so the answer does not depend on
# where the tree sits:
#   - R_HOME/bin/toolchain holds rzig and nothing else, under the names
#     Makeconf and the compile preflight use (one binary, no scripts):
#     the groups' files are the toolchain tree's (feat-standalone-toolchain
#     B19, B30; verify-toolchain.sh), a conda env's win-64 binutils/
#     excepted (B41);
#   - Makeconf names no build path and has no rpath; CPPFLAGS and LDFLAGS
#     are empty; FLIBS is the bare -lflang_rt.runtime; FC is zig-fc;
#   - Windows (every tree): CRAN's layout, Makeconf's R_ARCH is /x64 and
#     its NM_FILTER CRAN's, and R_HOME/bin has R.exe and Rscript.exe;
#   - the build tools (every tree): R puts the build-tools group's usr/bin
#     first on PATH (unix: etc/Renviron, and MAKE is make; Windows:
#     etc/Rcmd_environ; B25), and Windows' Makeconf runs ar and ranlib as
#     rzig, names each binutils tool by its path under
#     R_HOME/bin/toolchain/binutils/ and pkg-config bare (B24, B43);
#   - every OS (a tree that is not a conda env): no file of R's own names
#     the build machine's checkout, the tree's own place, zig's caches,
#     the env or $HOME, R's lazy-load databases and .rds files read
#     uncompressed; the vendored conda libraries that name one are
#     listed, and so are build.zig's verbatim copies of env files that
#     name only $HOME's path (conda-forge's build path);
#   - OpenMP (a tree that is not a conda env): no compile-time file
#     (omp.h, libomp.lib), which is the compilers group's (B22); where
#     Makeconf offers OpenMP, the runtime where the loader finds it (unix
#     lib/libomp; Windows R_HOME/bin/x64/libomp.dll), which makes rzig
#     count the group's openmp/ (B40); where it does not (minimal), no
#     runtime, so rzig leaves openmp/ alone;
#   - Windows (a tree that is not a conda env): the Tcl/Tk runtime is in
#     R_HOME/Tcl (with Tcl's modules), Makeconf's TCL_VERSION names its
#     DLLs (tcl86t, tk86t), Tcl/Tk's headers (tcl.h, tk.h) are in
#     R_HOME/Tcl/include, and every DLL a PE file in the tree imports is
#     in the tree (its own directory, R_HOME/bin/x64, or R_HOME/Tcl/bin
#     for the Tcl/Tk DLLs) or the system's;
#   - macOS (every tree): etc/r-zig.cmake, a CMake toolchain file that
#     leaves out Homebrew's, Fink's and MacPorts' prefixes, and
#     etc/Renviron makes it CMAKE_TOOLCHAIN_FILE's default;
#   - unix (a tree that is not a conda env): etc/ca-bundle.crt holds
#     certificates and etc/Renviron names it in R_ZIG_CA_BUNDLE; with
#     tcltk (full), Tcl/Tk's script libraries and Tcl's modules are in
#     <prefix>/lib and etc/Renviron points TCL_LIBRARY there;
#   - x86_64 (every OS): no binary of R's own has a VEX or EVEX
#     instruction (AVX, AVX2, FMA, AVX-512, on any register width): R is
#     compiled for the baseline CPU, not the build machine's;
#   - minimal: no binary of R's own links a library the profile excludes;
#   - linux: no ELF needs a glibc above the floor, 2.17;
#   - unix: every rpath is relative to its file; none of R's own binaries
#     needs a shared C++ runtime; linux: every DT_NEEDED is a bare name;
#   - macOS: every Mach-O at or below MACOS_MIN; install names relative,
#     dependencies relative or the system's, and only what conda has no
#     copy of from the SDK's /usr/lib.
# verify-bundle.sh (pixi task verify-package, after package) keeps what
# only a moved, environment-free copy can show, with this tree's archive
# and the two group archives extracted into one directory, a scenario
# after each (the base alone, with the compilers, with the build tools):
# R runs from the new place under env -i, TLS trust with the shipped CA
# bundle, the CPU its C compiler compiles for (the arch's baseline, every
# OS), and packages compiled with the relocated tree build and load
# under env -i (C++, Fortran, USE_FC_TO_LINK, FLIBS without flang,
# OpenMP, decoy CONDA_PREFIX runs, zig-fc with no flang; Windows: rzig's
# dry runs, the binutils Makeconf names, and OpenMP C and Fortran
# packages loaded with only bin\x64 and System32 on PATH). The archive is
# this tree as it is, so the checks here run once, here. (What runs in
# between leaves the tree as it was: smoke and check only run it,
# contract compiles with a copy, the compile tree (compile-tree.sh), and
# installs into build/testlib-*, pkg-parity runs the base's R in place
# for its no-make install, into its own library, writing nothing under
# $PREFIX [phase3-P3-5, coverage-3], hermetic works on a copy.)
# Shared helpers (rpaths_of, needed_of, cxx_deps, minos_over_floor,
# win_system_dll): verify-helpers.sh; MACOS_MIN, macho_minos, version_gt:
# env.sh.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

TREE="${1:-$PREFIX}"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
rh="$RH"
test -d "$TREE/$rh" || { echo "error: no R tree at $TREE ($rh missing): run 'pixi run build' first" >&2; exit 1; }
TREE="$(cd "$TREE" && pwd)"
echo "== verifying the installed tree $TREE ($OS/$FLAVOR)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# What a tree that is not a conda env carries from the env: the runtime
# data build.zig installs (installEnvRuntime) and the shared libraries
# vendor-libs.sh copies. A conda env (<tree>/conda-meta, the conda build's
# prefix) has both from its own packages, and gets neither. On win-64 it
# also has the build-tools group's binutils/ in R_HOME/bin/toolchain,
# r-zig-toolchain's copies (feat-standalone-toolchain B41).
conda_tree=""
if [ -d "$TREE/conda-meta" ]; then conda_tree=1; fi

# The compilers Makeconf names are rzig (feat-no-host-paths F3), one
# binary under every name: compiling runs no shell script of ours. FC is
# rzig's zig-fc (F3c). Windows: AR and RANLIB are rzig's zig-ar.exe and
# zig-ranlib.exe, the LTO block's gcc-ar and gcc-ranlib its gcc-ar.exe
# and gcc-ranlib.exe (B43), and CMake's ar and ranlib, which it looks for
# beside CC, its ar.exe and ranlib.exe. The names: rzig_names
# (verify-helpers.sh), which verify-bundle.sh holds the base archive to.
tc_dir="$rh/bin/toolchain"
tc_names="$(rzig_names)"
for t in $tc_names; do
  f="$TREE/$tc_dir/$t"
  if [ ! -f "$f" ] || [ "$(head -c2 "$f")" = '#!' ] || ! cmp -s "$f" "$TREE/$tc_dir/${tc_names%% *}"; then
    echo "error: $tc_dir/$t is missing, a script, or not the same rzig as the rest" >&2
    exit 1
  fi
done
# And nothing else is there (B19, B30): the toolchain groups' files
# (openmp/, usr/, binutils/) are the toolchain tree's (zig-toolchain.sh,
# verify-toolchain.sh), whose archives a user extracts beside this tree's.
# A conda env is the exception: on win-64 r-zig-toolchain carries
# binutils/ here (B41). zig's install never removes a file, so a tree
# built before phase 3 still has the files that left it (PHASE3 C25).
bad=""
while IFS= read -r f; do
  n="${f##*/}"
  if [ -d "$f" ]; then
    if [ -n "$conda_tree" ] && [ "$OS" = windows ] && [ "$n" = binutils ]; then continue; fi
    bad="$bad $n/"
  else
    case " $tc_names " in *" $n "*) ;; *) bad="$bad $n" ;; esac
  fi
done < <(find "$TREE/$tc_dir" -mindepth 1 -maxdepth 1)
if [ -n "$bad" ]; then
  echo "error: $tc_dir holds more than rzig:$bad (the toolchain groups' files are the toolchain tree's now, and zig's install removes no file, so a tree built before phase 3 keeps them): remove the tree and build again" >&2
  exit 1
fi
echo "== compilers verified: $tc_dir/{${tc_names// /,}} are rzig, and nothing else is there"

# rzig build's zig build roots (feat-zig-pkg-build), beside the compilers
for f in build_t1.zig build_t2.zig rpkg.zig; do
  if [ ! -f "$TREE/$rh/share/zig/rpkg/$f" ]; then
    echo "error: $rh/share/zig/rpkg/$f is missing" >&2
    exit 1
  fi
done
echo "== rzig build roots verified: $rh/share/zig/rpkg/{build_t1.zig,build_t2.zig,rpkg.zig}"

# Makeconf names no build path (feat-no-host-paths F1.5): build.zig writes
# the environment as $(R_HOME)/../.., FLIBS as -lflang_rt.runtime and no
# rpath, and nothing edits the file afterwards. Comment lines count.
# CPPFLAGS and LDFLAGS are empty (F3b): the compilers, rzig, add the
# environment's -I and -L (and a conda env's rpath) themselves. FC is
# rzig's zig-fc (F3c), which runs the flang rzig finds (the toolchain's
# flang/, the environment's bin, PATH).
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

# A file's line, compared whole with its CR dropped: R's Windows files
# have CRLF ends, and so does a checkout with autocrlf (C20). (Not grep
# -q, which may exit before tr has written everything, and tr's SIGPIPE
# would then fail the pipeline, pipefail.)
has_line() { tr -d '\r' < "$1" | grep -xF -- "$2" > /dev/null; }

# Windows: CRAN's layout, which packages build against (stress round 1).
# Makeconf's R_ARCH is /x64, so $(R_HOME)/bin$(R_ARCH)/Rterm.exe and
# lib$(R_ARCH) name the arch directories. R_HOME/bin has R.exe and
# Rscript.exe (build.zig's winRfe: they start bin/x64's), which packages
# run as ${R_HOME}/bin/R and ${R_HOME}/bin/Rscript. Makeconf's NM_FILTER
# is CRAN's, which gnuwin32's fixed/Makefile writes and build.zig
# substitutes: winshlib.mk's .def then leaves out the compiler's
# .refptr. and .weak. names, so a package DLL exports what CRAN's does
# (PR #25 review records-REC-3).
if [ "$OS" = windows ]; then
  bad=""
  grep -Eq '^R_ARCH = /x64 *'$'\r''?$' "$mk" || bad="$bad R_ARCH-not-/x64"
  has_line "$mk" "NM_FILTER = | \$(SED) -e '/[.]refptr[.]/d' -e '/[.]weak[.]/d'" || bad="$bad NM_FILTER-not-CRAN"
  for f in R.exe Rscript.exe; do
    [ "$(head -c2 "$TREE/$rh/bin/$f" 2>/dev/null)" = MZ ] || bad="$bad bin/$f(missing, or no PE file)"
  done
  if [ -n "$bad" ]; then
    echo "error: $rh lacks CRAN's layout:$bad" >&2
    exit 1
  fi
  echo "== CRAN's layout verified: Makeconf's R_ARCH = /x64 and NM_FILTER, $rh/bin/{R,Rscript}.exe"
fi

# The build tools (feat-standalone-toolchain B24, B25, B43), every tree:
# the conda packages carry the same files (B41). R puts the build-tools
# group's usr/bin first on PATH, where a missing directory is harmless
# (B25 a): unix etc/Renviron prepends it (R reads the file at startup,
# and bin/Rcmd sources it and exports what it sets, patch 0008), and MAKE
# is make for every flavor; Windows etc/Rcmd_environ through R's own
# installer line, with that directory in Rtools' place by a helper
# variable (Renviron.c expands a default only when it is a whole ${...}
# term). Windows' Makeconf runs ar and ranlib as rzig, in its LTO block
# too (gcc-ar, gcc-ranlib; its gcc-nm names a file that does not ship,
# B43-2), names each of conda-forge's binutils by its path under
# R_HOME/bin/toolchain/binutils/, the build-tools group's directory
# (objdump without .exe, which R CMD check adds: sotools.R), and
# none through BINPREF (the template sets NM twice, and make takes the
# last), and pkg-config bare, found on PATH (B43-3); Rcmd_environ's RC,
# for CMake, is the same windres. The lines are the vendored
# Makeconf.win's and build.zig's (rcmdEnviron, finalRenviron), as PHASE3
# sections 5 and 6 give them, each compared whole with its CR dropped
# (has_line, above).
bad=""
if [ "$OS" = windows ]; then
  bu='$(R_HOME)/bin/toolchain/binutils'
  for l in 'AR = $(BINPREF)zig-ar.exe' 'RANLIB = $(BINPREF)zig-ranlib.exe' \
    "NM = $bu/nm.exe" "DLLTOOL = $bu/dlltool.exe --as $bu/as.exe \$(DT_ARCH)" \
    "RESCOMP = $bu/windres.exe --preprocessor=\$(BINPREF)gcc.exe --preprocessor-arg=-E --preprocessor-arg=-xc --preprocessor-arg=-DRC_INVOKED \$(RC_ARCH)" \
    "OBJDUMP = $bu/objdump" "STRIP_SHARED_LIB = $bu/strip.exe --strip-unneeded" \
    "STRIP_STATIC_LIB = $bu/strip.exe --strip-debug" 'PKG_CONFIG = pkg-config' \
    '  AR = $(BINPREF)gcc-ar' '  NM = $(BINPREF)gcc-nm' '  RANLIB = $(BINPREF)gcc-ranlib'; do
    has_line "$mk" "$l" || bad="$bad
  ${mk#$TREE/} lacks: $l"
  done
  grep -E '\$\(BINPREF\)(\$\(LLVMPREF\))?(pkg-config|dlltool|as|nm|windres|objdump|strip|ar|ranlib)([^a-z]|$)' "$mk" |
    tr -d '\r' > "$WORK/binpref.txt" || true
  while IFS= read -r l; do
    bad="$bad
  ${mk#$TREE/} names a tool through BINPREF: $l"
  done < "$WORK/binpref.txt"
  for l in 'R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin' \
    'PATH="${R_CUSTOM_TOOLS_PATH:-${R_ZIG_TOOLS_PATH}};${PATH}/"' \
    'R_ZIG_RC=${R_HOME}/bin/toolchain/binutils/windres.exe'; do
    has_line "$TREE/$rh/etc/Rcmd_environ" "$l" || bad="$bad
  $rh/etc/Rcmd_environ lacks: $l"
  done
else
  for l in 'PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}' "MAKE=\${MAKE-'make'}"; do
    has_line "$TREE/$rh/etc/Renviron" "$l" || bad="$bad
  $rh/etc/Renviron lacks: $l"
  done
fi
if [ -n "$bad" ]; then
  echo "error: the build tools' lines are not build.zig's:$bad" >&2
  exit 1
fi
if [ "$OS" = windows ]; then
  echo "== build tools verified: Makeconf's AR and RANLIB are rzig, its binutils in \$(R_HOME)/bin/toolchain/binutils/, PKG_CONFIG = pkg-config; etc/Rcmd_environ puts bin/toolchain/usr/bin first on PATH"
else
  echo "== build tools verified: etc/Renviron puts bin/toolchain/usr/bin first on PATH, MAKE=\${MAKE-'make'}"
fi

# No path of the build machine in any file of R's own (feat-no-host-paths
# PLAN.md, Goal 1), in a tree that is not a conda env: the checkout (R's
# source, the build dir and, as env.sh keeps them, zig's caches are in
# it), the tree's own place (the install prefix, when it is not in the
# checkout), zig's caches wherever they are, the env R was built in
# (CONDA_PREFIX), and $HOME; each as it is set and resolved, matched with
# either separator (doubled too), and on Windows also in its drive form
# (C:/... or C:\..., beside MSYS' /c/...) and in any case. CI's paths
# (/home/runner/work/..., D:\a\...) are just more of these. build.zig
# keeps them out of R's files: -ffile-prefix-map for __FILE__ and the
# debug info (filePathFlags), no tools/misc/top.txt, fontconfig's
# configuration without the env's directories (installFontconfig),
# relative paths in the base packages' Rd objects and code databases
# (build.zig's bootstrap). Files are read as bytes, binaries' strings
# included; R's compressed ones (the lazy-load databases, .rds files) as
# the objects they hold, which the tree's R writes out uncompressed. Not
# R's own, and listed, not failed:
#   - what vendor-libs.sh vendored from the env, recognised as it
#     recognises it (vendored_files, verify-helpers.sh). conda's
#     libraries carry their env's path compiled in (conda's prefix
#     replacement: libcurl's CA file, OpenSSL's directory, fontconfig's
#     configuration, Tcl's script library, ...); they are conda's
#     binaries, not patched, and R overrides the defaults that matter
#     (R_ZIG_CA_BUNDLE, FONTCONFIG_PATH, TCL_LIBRARY).
#   - a file build.zig copies from the env as it is (fontconfig's conf.d,
#     Tcl/Tk's script libraries; Windows' Tcl/Tk DLLs), recognised by its
#     bytes (an env file's, under any name), that names $HOME's path and
#     nothing else here: conda-forge's own build path, which is under
#     $HOME when the build machine's user has the name of conda-forge's
#     builder (GitHub's macOS runners run as runner, and conda-forge's
#     macOS make names /Users/runner/miniforge3/conda-bld/...). Such a
#     copy that names the checkout, zig's caches or the env fails: the
#     tree uses these files as they are, so the path would leave the
#     machine with them (fonts.conf's did, before installFontconfig
#     rewrote it). minimal's make, the OpenMP headers and Windows'
#     binutils left the R tree in phase 3: they are the toolchain tree's
#     (feat-standalone-toolchain B22, B23, B24), and verify-toolchain.sh
#     lists its copies that name a build path the same way (C18).
# A library directly in <prefix>/lib that the env no longer has (unix;
# the build installs only directories there) was left by an earlier
# vendor-libs.sh run (a soname bump); it fails, named as such.
if [ -z "$conda_tree" ]; then
  conda_dir="${CONDA_PREFIX:?run through pixi: the env R was built in is CONDA_PREFIX}"
  command -v cygpath > /dev/null 2>&1 && conda_dir="$(cygpath -u "$conda_dir")"
  build_dirs=("$ROOT" "${PIXI_PROJECT_ROOT:-}" "$TREE" "${ZIG_GLOBAL_CACHE_DIR:-}" "${ZIG_LOCAL_CACHE_DIR:-}" "$conda_dir")
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
  # Each directory in its forms, as one regex (path_forms, path_re:
  # verify-helpers.sh).
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
  # R's compressed files (the lazy-load databases, .rds files), as the
  # objects they hold: the tree's R writes each one out uncompressed
  # under $WORK/serialized (uncompress-r-objects.R), and the same search
  # reads those. (Windows: R takes C:/... paths.)
  r_path() { if [ "$OS" = windows ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
  if [ "$OS" = windows ]; then rscript="$TREE/$rh/bin/x64/Rscript.exe"; else rscript="$TREE/$rh/bin/Rscript"; fi
  ser="$WORK/serialized"
  R_DONT_USE_TK=1 "$rscript" --vanilla "$(r_path "$(cd "$(dirname "$0")" && pwd)/uncompress-r-objects.R")" "$(r_path "$TREE/$rh")" "$(r_path "$ser")" ||
    { echo "error: the tree's R could not read its lazy-load databases and .rds files" >&2; exit 1; }
  n_ser="$(find "$ser" -type f | wc -l | tr -d ' ')"
  grep -rlaE "${icase[@]}" -e "$re" "$ser" > "$WORK/named-serialized.txt" || true
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
  while IFS= read -r f; do
    offenders="$offenders
  $rh/${f#"$ser"/} (its objects, uncompressed): $(first_match "$f" "$re")"
    n_bad=$((n_bad + 1))
  done < "$WORK/named-serialized.txt"
  if [ -n "$offenders" ]; then
    echo "error: $n_bad files name the build machine (the checkout, the tree's own place, zig's caches, the env or \$HOME), R's own unless marked, first match each:$offenders" >&2
    exit 1
  fi
  n_vendored_named="$(echo $vendored_named | wc -w | tr -d ' ')"
  echo "== build paths verified: no file of R's own names the checkout, the tree's own place, zig's caches, the env or \$HOME ($((n_all - n_vendored)) files besides vendor-libs.sh's, $n_ser of them read uncompressed; $n_paths distinct paths, either separator)"
  echo "   $n_vendored files vendored from the env, $n_vendored_named of them naming one of those paths, compiled in by conda:${vendored_named:- none}"
  if [ "$n_copies" -gt 0 ]; then
    echo "   build.zig's verbatim copies of env files that name only \$HOME's path, conda-forge's build path: $n_copies$copies_named"
  fi
fi

# OpenMP for packages (feat-standalone-toolchain B22, B40), in a tree that
# is not a conda env (there conda-forge's llvm-openmp brings headers and
# runtime in one package, B41). The compile-time files, llvm-openmp's
# omp.h (Windows: and libomp.lib), are the compilers group's openmp/, and
# none is in the base: rzig looks for omp.h in its environment's include/
# and would turn OpenMP on without the group. Where Makeconf offers OpenMP
# (SHLIB_OPENMP_CFLAGS non-empty: every variant but minimal), the base has
# the libomp runtime where the loader finds it, which is also what makes
# rzig count the group's openmp/ (B40): unix, libR links libomp, which
# vendor-libs.sh copies into lib/; Windows, libomp.dll in R_HOME/bin/x64
# beside R's executables, which vendor-libs.sh copies there because
# Makeconf offers OpenMP. R itself has no OpenMP on Windows (upstream's
# choice), so nothing in the tree imports it and the DLL closure check
# below would not notice it missing. Where Makeconf offers none
# (minimal), the base has no runtime, so rzig leaves openmp/ alone and a
# configure script's flagless omp.h probe finds no header. (That a package
# builds with the base and the group, and loads: verify-bundle.sh.)
if [ -z "$conda_tree" ]; then
  case "$OS" in
    windows) omp_runtime="$rh/bin/x64/libomp.dll" ;;
    linux) omp_runtime="lib/libomp.so" ;;
    macos) omp_runtime="lib/libomp.dylib" ;;
  esac
  bad=""
  for f in "$TREE"/include/omp*.h "$TREE"/Library/include/omp*.h "$TREE"/Library/lib/libomp.lib; do
    if [ -e "$f" ]; then bad="$bad ${f#"$TREE"/}(the compilers group's)"; fi
  done
  if grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    [ -s "$TREE/$omp_runtime" ] || bad="$bad $omp_runtime(missing, and Makeconf offers OpenMP)"
    omp_ok="$omp_runtime, as Makeconf offers OpenMP"
  else
    [ ! -e "$TREE/$omp_runtime" ] || bad="$bad $omp_runtime(Makeconf offers no OpenMP, and rzig would count openmp/)"
    omp_ok="no runtime, as Makeconf offers no OpenMP"
  fi
  if [ -n "$bad" ]; then
    echo "error: OpenMP in the base:$bad" >&2
    exit 1
  fi
  echo "== OpenMP for packages verified: $omp_ok; no omp.h or libomp.lib (the compilers group's openmp/)"
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
# in the toolchain directory only rzig is R's own, not a conda env's
# win-64 binutils/, B41). conda-forge's binaries are built for its own
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
      case "$f" in "$TREE/$tc_dir"/*) cmp -s "$f" "$rzig_file" || continue ;; esac
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
    # Makeconf's TCL_VERSION names those DLLs: packages that link Tcl/Tk
    # (tkrplot) take TCLTK_LIBS, -L$(TCL_HOME)/bin -ltcl$(TCL_VERSION)
    # -ltk$(TCL_VERSION).
    tclv="$(sed -n 's/^TCL_VERSION = *\([^[:space:]]*\).*/\1/p' "$mk")"
    for f in "tcl$tclv.dll" "tk$tclv.dll"; do
      [ -f "$TREE/$rh/Tcl/bin/$f" ] || bad="$bad TCL_VERSION=$tclv:Tcl/bin/$f(missing)"
    done
    # With Tcl/bin come the headers, in Tcl/include, where TCLTK_CPPFLAGS
    # (-I "$(TCL_HOME)/include") and packages' Makevars.win look: without
    # them a package that compiles against Tcl/Tk (tkrplot) stops at
    # tk.h (feat-standalone-toolchain PLAN.md, T1).
    for f in Tcl/include/tcl.h Tcl/include/tk.h; do
      [ -s "$TREE/$rh/$f" ] || bad="$bad $f(missing)"
    done
    if [ -n "$bad" ]; then
      echo "error: Tcl/Tk in $rh/Tcl:$bad" >&2
      exit 1
    fi
    echo "== Tcl/Tk verified: $rh/Tcl/bin/{tcl86t,tk86t}.dll (none in bin/x64), Makeconf's TCL_VERSION = $tclv, $(find "$TREE/$rh/Tcl/lib" -type f | wc -l | tr -d ' ') files in Tcl/lib, $(find "$TREE/$rh/Tcl/include" -type f | wc -l | tr -d ' ') headers in Tcl/include"

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

# macOS, every tree (the conda build's too): CMake's toolchain file
# (build.zig's macos_cmake_toolchain). Without it CMake searches Homebrew's
# prefix before the environment's whatever PATH says, and packages link
# the host's libraries (stress round 2, H2). etc/Renviron makes it
# CMAKE_TOOLCHAIN_FILE's default.
if [ "$OS" = macos ]; then
  bad=""
  grep -q '^set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH .*/opt/homebrew' "$TREE/$rh/etc/r-zig.cmake" 2>/dev/null ||
    bad="$bad etc/r-zig.cmake(missing, or no CMAKE_SYSTEM_IGNORE_PREFIX_PATH)"
  grep -qxF 'R_ZIG_CMAKE_TOOLCHAIN_FILE=${R_HOME}/etc/r-zig.cmake' "$TREE/$rh/etc/Renviron" &&
    grep -qxF 'CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE-${R_ZIG_CMAKE_TOOLCHAIN_FILE}}' "$TREE/$rh/etc/Renviron" ||
    bad="$bad etc/Renviron(no CMAKE_TOOLCHAIN_FILE)"
  if [ -n "$bad" ]; then
    echo "error: CMake's toolchain file:$bad" >&2
    exit 1
  fi
  echo "== CMake's toolchain file verified: etc/r-zig.cmake, CMAKE_TOOLCHAIN_FILE's default in etc/Renviron"
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
# number: R's own binaries, the vendored libraries in lib/ and rzig in
# lib/R/bin/toolchain. The list is collected first, then checked: an
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
# newer than the floor build.zig's target pin promises, 2.17, anywhere in
# the tree. This is the check side of the floor — a zig update or stray
# flag that raises the requirement should die here, not on a customer's
# old box.
#
# Until phase 3, lib/R/bin/toolchain had a tier of its own, conda-forge's
# linux baseline 2.28, for the env's tools build.zig copied there, which
# run only to compile (minimal's GNU make, which needs 2.17; until phase
# A5, 5f23127, coreutils' `realpath` too, which needed 2.28). It holds
# rzig alone now, built for R's own target and so at the floor
# (feat-standalone-toolchain B19); make is the toolchain tree's, and
# verify-toolchain.sh keeps the 2.28 tier for it.
# objdump: conda-forge's binutils (pixi.toml).
if [ "$OS" = linux ] && ! command -v objdump > /dev/null 2>&1; then
  cannot_check "objdump unavailable; glibc ceiling not checked"
elif [ "$OS" = linux ]; then
  GLIBC_FLOOR="2.17"
  worst=""; worst_file=""; failed=0
  while IFS= read -r f; do
    # `|| true`: an ELF with no versioned glibc imports makes grep exit 1,
    # and env.sh's pipefail + set -e would silently kill the whole script
    # on that assignment (latent in the first version of this check too).
    ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
    [ -z "$ceil" ] && continue
    if [ "$(printf '%s\n' "$ceil" "$GLIBC_FLOOR" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]; then
      echo "error: $f requires GLIBC_$ceil > $GLIBC_FLOOR" >&2
      failed=1
    fi
    if [ -z "$worst" ] || [ "$(printf '%s\n' "$ceil" "$worst" | sort -V | tail -1)" = "$ceil" ]; then
      worst="$ceil"; worst_file="${f#$TREE/}"
    fi
  done < "$bin_list"
  [ "$failed" = 0 ] || exit 1
  if [ -z "$worst" ]; then
    cannot_check "objdump -T read no glibc version from any ELF file; glibc ceiling not checked"
  else
    echo "== glibc ceiling verified: worst $worst ($worst_file) <= floor $GLIBC_FLOOR, every ELF file of the tree"
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
