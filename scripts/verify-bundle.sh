#!/usr/bin/env bash
# The standalone archives as a user gets them, from a fresh directory and
# with the pixi/conda env off PATH: the flavor's base archive and the
# platform's two group archives (feat-standalone-toolchain B17, B36),
# extracted one after the other into one directory, with a scenario run
# after each extraction (PLAN.md's Verification; PHASE3 section 8, C2).
# The same adversarial check done by hand on omicron and kappa for every
# relocation fix this project has shipped, automated so CI catches a
# regression instead of relying on a human to re-run it. unix runs under
# env -i, HOME a fresh directory and PATH=/usr/bin:/bin unless a check
# says otherwise; Windows binaries derive R_HOME natively, and what must
# load from the tree alone runs with PATH = bin\x64 + System32.
#
# Before extracting, the archives' file lists (files and links: zip and
# tar store the directories every archive of a tree repeats, C6): the
# base holds the R tree as it is ($PREFIX; feat-no-host-paths F1.7), no
# compile-time OpenMP file (B22) and nothing in R_HOME/bin/toolchain but
# rzig and its link object (B19, B30; feat-r-home-link-objects; Windows'
# Tcl/Tk headers stay in R_HOME/Tcl/include, T1);
# each group archive holds only its own directories; no file is in two
# archives, so tar and `unzip -n` (which never stops to ask, C6) fill one
# directory without one archive overwriting another.
#   1. The base alone: R runs from the new place (unix: env -i) with the
#      flavor's capabilities, the vendored libraries loading from there;
#      R puts the build-tools group's usr/bin first on PATH (B25, C27);
#      rzig's check mode exits 127 for each group with what is missing
#      and the group's text (B26, B35); R CMD SHLIB stops with the
#      compilers' text, whose standalone line names the compilers archive
#      extracted here (groups.zig and env.sh agree on its extension, B17),
#      and of a Makevars rule with both groups' texts, the compilers'
#      first (feat-shlib-rzig-build); hermetic-check.sh's tier 0/1 on the
#      extracted tree, where the install preflight stops a compiled
#      package with the compilers' text; TLS trust with the shipped CA
#      bundle and nothing from the build env (unix).
#   2. + compilers: the group holds flang, TC/flang (phase 6, B9), and
#      nothing else reaches it: no .cfg anywhere in the extracted tree and
#      no flang on the check mode's PATH; rzig's check mode finds the
#      pass's zig (below) and TC/flang; the first C++ compile, a shared
#      library, and the first Fortran compile, a derived-type module
#      through R CMD SHLIB, timed with zig's cache as the pass has it;
#      every compiler runs the pass's zig and zig-fc TC/flang
#      (RZIG_PRINT_ARGV's first word, every OS), compiling with the
#      intrinsic modules path into TC/flang (physical, no `..`) and
#      linking through zig with TC/flang's runtime; #include "omp_lib.h"
#      through $FC -E; the derived-type module as a package through rzig
#      build; the
#      preflight's other branches (zig, no make, no flang;
#      feat-zig-pkg-build M4; Windows too [phase3-P3-9]): a C package
#      with no Makevars builds through `rzig build` (patch 0013) with no
#      make and no zig build (tier1.zig), leaves no build root and no
#      build-runner-* in rzig's cache under the run's HOME, and loads;
#      one whose Makevars has a rule stops with rzig's reason and the
#      build tools' text; unix also an
#      R-only package with a configure script, with "a configure script
#      R runs" and the same text, and a Fortran one with TC/flang's
#      driver moved aside and the compilers' text (C26, PHASE6 open
#      point N); R CMD SHLIB with no make, every OS
#      (feat-shlib-rzig-build, patch 0013's one hook): pkgbuild's probe,
#      Rcpp's sourceCpp, Fortran, cpp11's and TMB's shapes, the dry run
#      Rcpp's macOS OpenMP plugin parses and an OpenMP library build
#      through rzig build and load, and a Makevars rule stops with rzig's
#      reason and the build tools' text; the C compiler compiles for the
#      arch's baseline CPU, not this machine's, also when told
#      -mtune=native (LLVM IR's target-cpu); packages compiled with the
#      tree build and load.
#      unix, under env -i: C++, Fortran (with the env's flang and .cfg
#      first on PATH), and with no flang on PATH and no .cfg
#      USE_FC_TO_LINK, a configure that compiles, links and runs a
#      program with $FC and Fortran OpenMP; $(FLIBS) without flang (or
#      make), zig-fc with no flang (TC/flang's driver moved aside for
#      both), OpenMP (C, and Fortran with `use omp_lib`) with the
#      group's openmp/ where the base has libomp and openmp/ left alone
#      on minimal (B40; there `use omp_lib` compiles and its link
#      fails, B40's Fortran limit), decoy CONDA_PREFIX runs (the C++
#      and, where offered, the OpenMP shape):
#      each shape through R CMD SHLIB, make by R_ZIG_PKG_BUILDER=make (R
#      CMD SHLIB's default is rzig build since patch 0013's one hook,
#      feat-shlib-rzig-build), and as a package through R CMD INSTALL
#      (rzig build, asserted from its log), with the same checks on both
#      libraries, and on rzig build's objects, kept in its build root,
#      the macOS floor.
#      Windows, where make is a build tool: rzig's dry runs (-L from
#      where the tree now is, the group's openmp/, CONDA_PREFIX ignored,
#      zig-fc.exe's link with TC/flang's runtime and no -lc++), a
#      program compiled, linked and run with $FC alone, an OpenMP DLL
#      compiled and linked by gcc.exe alone, loaded
#      with only bin\x64 and System32 on PATH, and a package linking
#      -lsynchronization (Rust's std's import, D6) through rzig build,
#      loaded the same way.
#   3. + build-tools: R runs the group's tools. unix: make is
#      R_HOME/bin/toolchain/usr/bin/make (rzig's check mode, Sys.which,
#      and on linux the make strace saw run), and install.packages with
#      Ncpus = 2 builds two packages, a mixed run under the default
#      builder: btA (plain C) through rzig build, btLib (a static library
#      made by $(AR) and $(RANLIB): rzig, B43) through the group's make,
#      each asserted from its kept log. Windows: the group's usr/bin with
#      PATH = bin\x64 + System32 (R CMD's Rcmd_environ and the session's
#      Rprofile put it first; PHASE7 open point I): rzig's check mode
#      under R CMD names its make and sh, Sys.which("make") in a session
#      is its make.exe, every
#      tool Makeconf.win names is the group's binutils or rzig (B24,
#      B43), R CMD check's DLL check runs the group's objdump, a tools.mk
#      runs each of the binutils (C10, C11), CMake's ar and ranlib beside
#      CC are rzig, and the OpenMP C and Fortran packages (through R CMD
#      SHLIB, make by R_ZIG_PKG_BUILDER=make, and as packages through rzig
#      build [phase3-P3-1]), the static-library package, a package
#      whose configure.win compiles, links and runs a program with $FC,
#      a package with a .rc file (make) and a plain C one (rzig build)
#      build and load with only bin\x64 and System32 on PATH; LTO is recorded, not
#      checked (B43-2, C9), with a tier-1 twin that MAKEFLAGS' assignment
#      sends to make (N4); B39's tools through a configure.win, a
#      cleanup.win and a Makevars rule (btTools), pkg-config (0.29.2,
#      B43) through a configure.win and a .pc file under a path with a
#      space (btPc), R
#      CMD check's nm (UserNM, PHASE7 open point H), and, where Git for
#      Windows' MSYS is installed, the same with its usr\bin first on PATH
#      (with a configure.win that runs its diff and cygpath through TC's
#      sh) and after it (PHASE7 open point M, amendment Am4). Every OS, with no zig (TC/zig's binary moved
#      aside): a package with a configure script stops in the preflight
#      with the compilers' text, and with R_ZIG_NO_PREFLIGHT=1 gets past
#      it, runs its configure and fails in the compile (C26).
# Two passes (feat-standalone-toolchain phase 5; PHASE5 open points F, G,
# S): `verify-bundle.sh [toolchain|build]`. The toolchain pass, the
# default, is what a user of the archives gets: no ZIG_BIN and no zig
# cache variable, so rzig takes R_HOME/bin/toolchain/zig/zig (TC/zig,
# upstream zig, B4) and zig its default cache under the fresh HOME. Then,
# unless the build's zig (env.sh's $ZIG) is TC/zig's bytes (the upstream
# legs: fetch-zig's zig, the same wheel), the script runs itself again as
# the build pass: ZIG_BIN=$ZIG with env.sh's global cache, so that
# conda-forge's zig keeps its coverage on the default legs (the mixed
# case, then conda-forge's zig). The build pass skips the base alone and
# the no-zig check, which pass no zig and would test the same thing again
# (S). pass_zig is the zig the pass's assertions name. Both passes take
# flang from TC/flang (PHASE6 open point O): rzig has no flang override,
# and TC/flang holds the env's flang bytes (B9), so the build pass varies
# the zig only; the env's flang with its cfg keeps its coverage in
# contract, pkg-parity and the conda tests. pass_flang is TC/flang's
# driver as rzig names it.
# The static checks of the trees (Makeconf, the compilers are rzig, the CA
# bundle, rpaths, the glibc ceiling, the C++ runtime of R's binaries, the
# macOS floor and load commands, minimal's excluded libraries, Windows'
# Tcl/Tk and DLL closure; the groups' records and closures) read files,
# headers and load commands, which moving a tree does not change:
# verify-tree.sh and verify-toolchain.sh run them where the trees are
# built. Shared helpers: verify-helpers.sh (archive_files, tree_files,
# rzig_names, link_object, link_object_named, configure_marker,
# extract_archive, rpaths_of, needed_of, cxx_deps, minos_over_floor,
# cannot_check).
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

# The pass (above): toolchain, the default, or build.
pass="${1:-toolchain}"
case "$pass" in
  toolchain) pass_what="TC/zig" ;;
  build)
    [ -n "$ZIG" ] || { echo "error: the build pass needs the build's zig, and env.sh found none (ZIG_BIN, PATH)" >&2; exit 1; }
    # Named as rzig gets it (the Windows branch below passes cygpath -m's
    # C:/...): with ZIG_BIN unset, env.sh's $ZIG is PATH's MSYS spelling.
    pass_what="ZIG_BIN=$ZIG"
    [ "$OS" != windows ] || pass_what="ZIG_BIN=$(cygpath -m "$ZIG")" ;;
  *) echo "usage: verify-bundle.sh [toolchain|build]" >&2; exit 1 ;;
esac
echo "== the $pass pass: zig from $pass_what"
# zig's and flang's file names in TC/zig/ and TC/flang/bin/
exe=""
[ "$OS" != windows ] || exe=.exe

# The archives, in the order they are extracted: the base
# (package-standalone.sh, `pixi run package`), then the groups (`pixi run
# package-toolchain`; in CI the toolchain job's artifact, B31), each with
# the .sha256 written beside it.
base="$ROOT/dist/R-$R_VERSION-$FLAVOR-$PLAT.$ARCHIVE_EXT"
test -f "$base" || { echo "error: $base not found — run 'pixi run package' first" >&2; exit 1; }
archives=("$base")
for group in $TOOLCHAIN_GROUPS; do
  a="$ROOT/dist/R-$R_VERSION-$PLAT-$group.$(group_ext "$group")"
  test -f "$a" ||
    { echo "error: $a not found: run 'pixi run package-toolchain' (or download the toolchain job's artifact into dist/)" >&2; exit 1; }
  archives+=("$a")
done
for a in "${archives[@]}"; do
  (cd "$ROOT/dist" && sha256sum -c --quiet "${a##*/}.sha256") ||
    { echo "error: ${a##*/} does not match ${a##*/}.sha256" >&2; exit 1; }
done

VERIFY_DIR="$(mktemp -d)"
# flang_aside, flang_back: the no-flang checks of scenario 2 move
# TC/flang's driver out of the tree and back (PHASE6 open point N a, as
# scenario 3 moves TC/zig's binary aside): the driver is what rzig looks
# for (flang_rt.zig's flang), so without it the tree is one with no
# flang. The EXIT trap puts it back too, so it is back on every exit
# path, a failing check's included.
flang_aside() { mv "$TC/flang/bin/flang$exe" "$VERIFY_DIR/flang.aside"; }
flang_back() { [ ! -e "$VERIFY_DIR/flang.aside" ] || mv "$VERIFY_DIR/flang.aside" "$TC/flang/bin/flang$exe"; }
trap 'flang_back; rm -rf "$VERIFY_DIR"' EXIT
# The archives' top directory, R-<ver>-zig/ (feat-standalone-toolchain
# B36): package-standalone.sh archives only trees of that name.
BUNDLE_DIR="$VERIFY_DIR/$TOP"
lists="$VERIFY_DIR/lists"
mkdir -p "$lists"

# The file lists (C6), sorted alike for comm and uniq. The base is the R
# tree the build installed and the checks before packaging saw (F1.7):
# the same files and links, nothing added or left out.
tree="$PREFIX"
# Windows: an override may be C:\...; find wants /c/....
command -v cygpath > /dev/null 2>&1 && tree="$(cygpath -u "$tree")"
test -d "$tree/$RH" || { echo "error: no R tree at $tree; run 'pixi run build' first" >&2; exit 1; }
archive_files "$base" | LC_ALL=C sort > "$lists/base"
tree_files "$tree" | LC_ALL=C sort > "$lists/tree"
only_archive="$(LC_ALL=C comm -23 "$lists/base" "$lists/tree")"
only_tree="$(LC_ALL=C comm -13 "$lists/base" "$lists/tree")"
if [ -n "$only_archive$only_tree" ]; then
  echo "error: ${base##*/} does not hold the R tree $tree as it is (run 'pixi run package' again)" >&2
  [ -z "$only_archive" ] || { echo " only in the archive:"; printf '%s\n' "$only_archive" | sed 's/^/  /'; } >&2
  [ -z "$only_tree" ] || { echo " only in the tree:"; printf '%s\n' "$only_tree" | sed 's/^/  /'; } >&2
  exit 1
fi
# The base has no compile-time OpenMP file: omp.h and its siblings and
# Windows' libomp.lib are the compilers group's openmp/ (B22), and
# nothing else goes into the environment directories (unix <prefix>/include;
# Windows Library/include and Library/lib's import libraries). Tcl/Tk's
# headers in R_HOME/Tcl/include stay in the Windows base (T1). Its
# R_HOME/bin/toolchain holds rzig under its names, rzig's link object
# (linux, Windows; feat-r-home-link-objects) and no directory: the
# groups' directories are the toolchain tree's (B19, B30).
tc="$TOP/$RH/bin/toolchain"
tc_re="^${tc//./\\.}/"
if [ "$OS" = windows ]; then
  env_re="^${TOP//./\\.}/Library/(include/|lib/[^/]*\.lib\$)"
else
  env_re="^${TOP//./\\.}/include/"
fi
compile_time="$(grep -E "$env_re|/omp[^/]*\.h\$|/libomp\.lib\$" "$lists/base" || true)"
if [ -n "$compile_time" ]; then
  echo "error: ${base##*/} holds compile-time OpenMP or environment files, which are the compilers group's (feat-standalone-toolchain B22):" >&2
  printf '%s\n' "$compile_time" | sed 's/^/  /' >&2
  exit 1
fi
names=" $(rzig_names) $(link_object) "
not_rzig=""
while IFS= read -r m; do
  case "$names" in *" ${m#"$tc/"} "*) ;; *) not_rzig="$not_rzig ${m#"$tc/"}" ;; esac
done < <(grep -E "$tc_re" "$lists/base" || true)
if [ -n "$not_rzig" ]; then
  echo "error: ${base##*/} has more than rzig ($(rzig_names)) and its link object ($(link_object)) in $tc:$not_rzig (B19, B30: the groups' files are the toolchain tree's)" >&2
  exit 1
fi
lo_word=""
if [ -n "$(link_object)" ]; then
  grep -qxF "$tc/$(link_object)" "$lists/base" ||
    { echo "error: ${base##*/} has no $tc/$(link_object), the object rzig adds to links (feat-r-home-link-objects)" >&2; exit 1; }
  lo_word=" and its $(link_object)"
fi
# Each group archive holds only its group's directories (env.sh's
# group_dirs), as unpack-toolchain.sh requires, and no file is in two of
# the three archives.
group_lists=()
for group in $TOOLCHAIN_GROUPS; do
  a="$ROOT/dist/R-$R_VERSION-$PLAT-$group.$(group_ext "$group")"
  archive_files "$a" | LC_ALL=C sort > "$lists/$group"
  group_lists+=("$lists/$group")
  dirs_re="$(group_dirs "$group" | tr ' ' '|')"
  bad="$(grep -Ev "$tc_re($dirs_re)/" "$lists/$group" || true)"
  [ -z "$bad" ] ||
    { echo "error: ${a##*/} has members outside $tc/{${dirs_re//|/,}}/ (the $group group's directories):" >&2; printf '%s\n' "$bad" | sed 's/^/  /' >&2; exit 1; }
done
both="$(cat "$lists/base" "${group_lists[@]}" | LC_ALL=C sort | uniq -d)"
if [ -n "$both" ]; then
  echo "error: files in more than one archive (extracted into one directory, one archive would overwrite the other's):" >&2
  printf '%s\n' "$both" | sed 's/^/  /' >&2
  exit 1
fi
echo "== file lists: ${base##*/} is the R tree ($(wc -l < "$lists/base" | tr -d ' ') files and links), nothing compile-time in it and only rzig${lo_word} in $tc; $(for g in $TOOLCHAIN_GROUPS; do printf '%s %s, ' "$g" "$(wc -l < "$lists/$g" | tr -d ' ')"; done)each under its own directories; no file in two archives"

# extract <archive> <list>: into the one directory, then every member of
# the list is there (unzip -n skips a file that exists; the lists being
# disjoint, none should).
extract() {
  echo "== extracting ${1##*/} into $VERIFY_DIR"
  extract_archive "$1" "$VERIFY_DIR"
  tree_files "$BUNDLE_DIR" | LC_ALL=C sort > "$lists/extracted"
  local missing
  missing="$(LC_ALL=C comm -23 "$2" "$lists/extracted")"
  [ -z "$missing" ] ||
    { echo "error: not extracted from ${1##*/}:" >&2; printf '%s\n' "$missing" | sed 's/^/  /' >&2; exit 1; }
}

# The Fortran OpenMP packages both OSes build where Makeconf offers
# OpenMP (scenario 2 on unix, scenario 3 on Windows), in R-exts' two
# forms: fomp, $(SHLIB_OPENMP_FFLAGS) on the compile and
# $(SHLIB_OPENMP_CFLAGS) on the link, which the C compiler does; fompfc,
# USE_FC_TO_LINK with $(SHLIB_OPENMP_FFLAGS) on both, which zig-fc links.
# One fixed-form source: omp_get_max_threads() through `use omp_lib`, a
# num_threads(2) region counting its threads, and 1..100 summed in a
# parallel reduction. The count proves -fopenmp reached the compile:
# without it the directives are comments, `use omp_lib` still compiles
# and links, the region runs once and the sum is still 5050. FOMP_R loads
# both from the directory holding them and checks the results.
fomp_src() {
  local d
  for d in fomp fompfc; do
    mkdir -p "$1/$d"
    cat > "$1/$d/$d.f" <<'FORTRAN'
      subroutine fompn(n, t, s)
      use omp_lib
      integer n, t, s, i
      n = omp_get_max_threads()
      t = 0
!$omp parallel num_threads(2) reduction(+:t)
      t = t + 1
!$omp end parallel
      s = 0
!$omp parallel do reduction(+:s)
      do i = 1, 100
         s = s + i
      end do
!$omp end parallel do
      end
FORTRAN
  done
  printf '%s\n' 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$1/fomp/Makevars"
  printf '%s\n' 'USE_FC_TO_LINK =' 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_FFLAGS)' > "$1/fompfc/Makevars"
}
# fdt_src <dir>: the derived-type module scenario 2 builds (PLAN.md phase
# 6): m.f90, a module with a type and a function on it, and u.f90, fdtv,
# which uses it, builds the type and returns its area, 42. m.f90 is
# compiled first (u.f90 needs its .mod): R CMD SHLIB is given it first,
# and rzig build compiles a package's Fortran in OBJECTS order.
fdt_src() {
  mkdir -p "$1"
  cat > "$1/m.f90" <<'FORTRAN'
module m
  implicit none
  type :: pt
    real(8) :: x, y
  end type pt
contains
  pure function area(p) result(a)
    type(pt), intent(in) :: p
    real(8) :: a
    a = p%x * p%y
  end function area
end module m
FORTRAN
  cat > "$1/u.f90" <<'FORTRAN'
subroutine fdtv(v)
  use m
  implicit none
  real(8), intent(out) :: v
  type(pt) :: p
  p = pt(6d0, 7d0)
  v = area(p)
end subroutine fdtv
FORTRAN
}
# conftest_f <dir>: the program a configure script compiles, links and
# runs with $FC (PHASE6 open point P's shape): it prints ok.
conftest_f() {
  mkdir -p "$1"
  printf '%s\n' '      program t' "      print '(a)', 'ok'" '      end' > "$1/conftest.f"
}
FOMP_R='for (d in c("fomp", "fompfc")) {
  dyn.load(file.path(d, paste0(d, .Platform$dynlib.ext)))
  r <- .Fortran("fompn", n = 0L, t = 0L, s = 0L, PACKAGE = d)
  stopifnot(r$n >= 1L, r$t == 2L, r$s == 5050L)
  cat(d, ": omp_get_max_threads() =", r$n, "; a num_threads(2) region ran on", r$t, "threads\n")
}'

# mkpkg <dir> <name> <value> [lib]: a package whose f() returns <value>
# (an integer), from <name>_val() in src/val.c; with `lib`, in
# src/lib/val.c instead, which src/Makevars builds into the static library
# lib/libval.a with $(AR) and $(RANLIB) and links into the package's
# shared library, as packages with a bundled C library do. Outside src/'s
# own files the library's source is in no OBJECTS, so its symbol comes
# from the archive alone. AR and RANLIB are rzig on every OS (zig ar, zig
# ranlib; on Windows since B43: zig ar's archives linking there is B43's
# risk). One Makevars serves both OSes (R reads Makevars when a package
# has no Makevars.win).
mkpkg() {
  local d="$1/$2" v=val.c
  mkdir -p "$d/R" "$d/src"
  printf 'Package: %s\nVersion: 0.1\nTitle: Verify Bundle\nDescription: A package the bundle check builds.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$2" > "$d/DESCRIPTION"
  printf 'useDynLib(%s)\nexport(f)\n' "$2" > "$d/NAMESPACE"
  printf 'f <- function() .Call("%s_f", PACKAGE = "%s")\n' "$2" "$2" > "$d/R/f.R"
  printf '#include <Rinternals.h>\nint %s_val(void);\nSEXP %s_f(void) { return ScalarInteger(%s_val()); }\n' "$2" "$2" "$2" > "$d/src/f.c"
  if [ "${4:-}" = lib ]; then
    v=lib/val.c
    mkdir -p "$d/src/lib"
    printf 'PKG_LIBS = lib/libval.a\n$(SHLIB): lib/libval.a\nlib/libval.a: lib/val.o\n\t$(AR) cr $@ lib/val.o\n\t$(RANLIB) $@\n' > "$d/src/Makevars"
  fi
  printf 'int %s_val(void) { return %s; }\n' "$2" "$3" > "$d/src/$v"
}

# fcconf_pkg <dir>: the package fcconf, whose configure (and
# configure.win, the same script) checks R's Fortran compiler as
# autoconf's Fortran checks do (PLAN.md phase 6): R CMD config FC, then
# conftest.f compiled, linked and run with $FC (it must print ok), then
# linked again with -v (the FLIBS probe's call), then src/Makevars
# written. Its install log holds "fcconf: <FC> compiles, links and runs a
# program" when the configure ran; f() returns src/f.f90's 5.
fcconf_pkg() {
  local d="$1/fcconf" f
  mkdir -p "$d/R" "$d/src"
  printf 'Package: fcconf\nVersion: 0.1\nTitle: Verify Bundle\nDescription: A configure script that runs $FC.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$d/DESCRIPTION"
  printf 'useDynLib(fcconf)\nexport(f)\n' > "$d/NAMESPACE"
  printf 'f <- function() .Fortran("fcv", n = 0L, PACKAGE = "fcconf")$n\n' > "$d/R/f.R"
  printf '%s\n' 'subroutine fcv(n)' '  integer, intent(out) :: n' '  n = 5' 'end subroutine fcv' > "$d/src/f.f90"
  conftest_f "$d"
  for f in configure configure.win; do
    cat > "$d/$f" <<'CONFIGURE'
#!/bin/sh
case `uname -s` in MINGW*|MSYS*|CYGWIN*) x=.exe ;; *) x= ;; esac
FC=`"${R_HOME}/bin/R$x" CMD config FC | tr -d '\r'`
rm -f conftest$x
$FC -o conftest$x conftest.f || { echo "fcconf: $FC could not compile and link conftest.f"; exit 1; }
out=`./conftest$x | tr -d '\r'`
test "$out" = ok || { echo "fcconf: conftest$x printed '$out', not ok"; exit 1; }
$FC -v -o conftest$x conftest.f > conftest.log 2>&1 || { cat conftest.log; echo "fcconf: $FC -v -o conftest$x conftest.f failed"; exit 1; }
echo "fcconf: $FC compiles, links and runs a program"
rm -f conftest$x conftest.log
echo 'PKG_FCFLAGS = -O2' > src/Makevars
CONFIGURE
    chmod +x "$d/$f"
  done
}

# rzig's texts for a missing group, as it prints them (its name, zig-cc
# for gcc.exe too, then what is missing; then the group's first line:
# zigbuild/tools/rzig/check.zig and groups.zig, B35). starts_line <file>
# <text>: a line of the file starts with the text (CRs dropped).
no_zig_line="zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the environment's bin, PATH, python3 -m ziglang)"
no_flang_line="zig-cc: no flang (R_HOME/bin/toolchain/flang/bin, the environment's bin, PATH)"
no_make_line="zig-cc: no make on PATH"
compilers_head="Compiling needs the r-zig compilers for R $R_VERSION on $PLAT: "
build_tools_head="Building packages needs the r-zig build tools for R $R_VERSION on $PLAT: "
# The compilers text's standalone line names the archive this script
# extracts: groups.zig's archiveExt and env.sh's group_ext agree (B17,
# B35; PHASE6 open point L).
compilers_standalone="  standalone:  extract ${archives[1]##*/} where you extracted R ("
# 0009's own stop (pkgerrmsg), for compiled code and for a configure script
# R runs alike [tests-T11]
preflight_stop="ERROR: this package needs the r-zig toolchain (compiled code or a configure script), which is incomplete (see above)"
starts_line() { tr -d '\r' < "$1" | awk -v p="$2" 'index($0, p) == 1 { f = 1 } END { exit !f }'; }

# --- Scenario 1: the base alone ---------------------------------------------
extract "$base" "$lists/base"
echo "== scenario 1: the base alone"
RHD="$BUNDLE_DIR/$RH"           # R_HOME
TC="$RHD/bin/toolchain"         # rzig, and the groups' directories once extracted
# HOME for every env -i run: a fresh directory, so that no ~/.R/Makevars
# and no user library of this machine's reach a compile, and rzig's cache
# (its libc++ mirror, its compiled helper objects) starts empty, as a new
# user's does.
home="$VERIFY_DIR/home"
mkdir -p "$home/tmp"
if [ "$OS" = windows ]; then
  R_BINDIR="$RHD/bin/x64"
  R_BIN="$R_BINDIR/Rscript.exe"
  R_EXE="$R_BINDIR/R.exe"
  RSCRIPT="$R_BIN"
  SO=dll
  cc="$TC/gcc.exe"
  fc="$TC/zig-fc.exe"
  sysdir="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")"
  sys32="$sysdir/System32"
  w() { cygpath -w "$1"; }
  # What Windows itself needs (hermetic-check.sh's set), and cmd.exe for R
  # CMD's commands. Paths in Windows' form: these go to native programs.
  base_env=(SYSTEMROOT="$(w "$sysdir")" WINDIR="$(w "$sysdir")" COMSPEC="$(w "$sys32/cmd.exe")"
    PATHEXT=".COM;.EXE;.BAT;.CMD" USERPROFILE="$(w "$home")" HOME="$(w "$home")" LOCALAPPDATA="$(w "$home")"
    TMPDIR="$(w "$home/tmp")" TMP="$(w "$home/tmp")" TEMP="$(w "$home/tmp")")
  zig_bin="${ZIG:+$(cygpath -m "$ZIG")}"
  # (no ZIG_LOCAL_CACHE_DIR: see unix's below)
  zig_env=(ZIG_BIN="$zig_bin" ZIG_GLOBAL_CACHE_DIR="$(cygpath -m "$ZIG_GLOBAL_CACHE_DIR")")
else
  R_BINDIR="$BUNDLE_DIR/bin"
  R_BIN="$R_BINDIR/R"
  RSCRIPT="$R_BINDIR/Rscript"
  SO=so
  cc="$TC/zig-cc"
  fc="$TC/zig-fc"
  base_env=(HOME="$home" TMPDIR="${TMPDIR:-/tmp}")
  # zig in the build pass: env.sh's $ZIG, the one the build used (ZIG_BIN,
  # else the env's), passed on as ZIG_BIN, which env -i drops (rzig would
  # then take TC/zig's), with the global cache env.sh keeps for that zig.
  # Not its
  # ZIG_LOCAL_CACHE_DIR: zig cc would take that as its cache, and the
  # installs here are to use the one a user's install gets [phase3-P3-6]:
  # zig cc's objects in the global cache, each install's objects and
  # library in its build root, gone with it (tier 1 runs no zig build).
  zig_bin="$ZIG"
  zig_env=(ZIG_BIN="$zig_bin" ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR")
fi
# The toolchain pass passes no zig variable (open point G): rzig finds
# TC/zig's zig (find_zig: <rzig dir>/zig/zig after ZIG_BIN), and zig keeps
# its cache where a new user's is, under the fresh HOME (unix
# $home/.cache/zig; Windows LOCALAPPDATA, $home/zig), never env.sh's,
# which is keyed to the build's zig (the 2026-10-04 cache mix).
[ "$pass" = build ] || zig_env=()
test -x "$R_BIN" || { echo "error: $R_BIN missing from the extracted base" >&2; exit 1; }

if [ "$pass" = toolchain ]; then
  # minimal (the wheel profile) has no cairo/png by design — assert that
  # instead, so a graphics stack creeping back in fails here too.
  if [ "$VARIANT" = minimal ]; then
    CHECK_CAPS='stopifnot(!capabilities("cairo"), !capabilities("png"), !capabilities("ICU"))'
  else
    CHECK_CAPS='stopifnot(capabilities("cairo"), capabilities("png"))'
  fi
  # tcltk (unix full): Tcl starts with the script library the tree ships,
  # not the build env's that the vendored libtcl names, and `clock`, which
  # needs the msgcat module, works. Under env -i there is no DISPLAY, so Tk
  # stays down (a warning) and only Tcl is tested. (Windows: verify-tree.sh
  # checks R_HOME/Tcl's files, hermetic-check.sh loads tcltk from it with an
  # empty environment, and check's tcltk examples use it.)
  CHECK_TCLTK=""
  if [ "$OS" != windows ]; then
    CHECK_TCLTK="
if (capabilities('tcltk')) {
  suppressWarnings(library(tcltk))
  lib <- normalizePath(tcltk::tclvalue(tcltk::.Tcl('info library')))
  stopifnot(startsWith(lib, normalizePath(file.path(R.home(), '..'))),
            tcltk::tclvalue(tcltk::.Tcl('clock format 0 -gmt 1 -format %Y')) == '1970')
  cat('tcltk OK:', lib, '\n')
}"
  fi
  CHECK_R="
stopifnot(max(abs(solve(matrix(c(2,0,0,2),2,2)) - matrix(c(.5,0,0,.5),2,2))) < 1e-9)
$CHECK_CAPS
$CHECK_TCLTK
cat('bundle OK\n')
"
  if [ "$OS" = windows ]; then
    "$R_BIN" --vanilla -e "$CHECK_R"
  else
    env -i "${base_env[@]}" PATH=/usr/bin:/bin "$R_BIN" --vanilla --no-echo -e "$CHECK_R"
  fi
  echo "== standalone base verified relocatable ($OS/$FLAVOR)"

  # The build tools first on PATH at run time (B25, C27), with the base
  # alone, where the directory does not exist yet (harmless: the host's make,
  # if any, comes next). unix: etc/Renviron's line, which R reads at start
  # and bin/Rcmd sources (patch 0008), so PATH starts with
  # <R_HOME>/bin/toolchain/usr/bin in R and under R CMD. Windows: under R
  # CMD, Rcmd_environ's line, whose default R's reader expands only as a
  # whole ${...} term (hence R_ZIG_TOOLS_PATH): the entries after bin\x64,
  # which R CMD puts first, are the expanded paths, with no ${ left, the
  # group's usr/bin, then R_HOME/../../usr/bin (a conda env's MSYS dir;
  # here none: PHASE7 F2 b), or R_CUSTOM_TOOLS_PATH's value when that is
  # set (R's installer line).
  if [ "$OS" = windows ]; then
    cat > "$VERIFY_DIR/path.R" <<'RCODE'
p <- strsplit(Sys.getenv("PATH"), ";", fixed = TRUE)[[1L]]
slash <- function(x) tolower(chartr("\\", "/", x))
i <- match(TRUE, endsWith(slash(p), "/bin/x64"))
custom <- Sys.getenv("R_CUSTOM_TOOLS_PATH")
want <- if (nzchar(custom)) custom else paste0(R.home(), c("/bin/toolchain/usr/bin", "/../../usr/bin"))
got <- if (is.na(i)) "" else p[i + seq_along(want)]
if (anyNA(got) || any(grepl("${", got, fixed = TRUE)) || any(slash(got) != slash(want)))
    stop("the PATH entries after bin/x64 are '", paste(got, collapse = ";"), "', not '",
         paste(want, collapse = ";"), "'; PATH: ", Sys.getenv("PATH"))
cat("the PATH entries after bin/x64:", got, "\n")
RCODE
    # In an R session, base's Rprofile (patch 0014; PHASE7 open point I,
    # amendment Am4, F2 b): the first entries, R_HOME/bin/toolchain/usr/bin
    # and R_HOME's grandparent's usr/bin, spelled without "..", which R's
    # own command search rejects, or R_CUSTOM_TOOLS_PATH's value; one set
    # to empty is unset, as R CMD reads it. --vanilla skips the site and
    # user profiles, not base's.
    cat > "$VERIFY_DIR/session-path.R" <<'RCODE'
p <- strsplit(Sys.getenv("PATH"), ";", fixed = TRUE)[[1L]]
slash <- function(x) tolower(chartr("\\", "/", x))
custom <- Sys.getenv("R_CUSTOM_TOOLS_PATH")
want <- if (nzchar(custom)) custom else
    c(file.path(R.home(), "bin", "toolchain", "usr", "bin"), file.path(dirname(dirname(R.home())), "usr", "bin"))
got <- p[seq_along(want)]
if (anyNA(got) || any(slash(got) != slash(want)))
    stop("the session's first PATH entries are '", paste(got, collapse = ";"), "', not '",
         paste(want, collapse = ";"), "'; PATH: ", Sys.getenv("PATH"))
cat("the session's first PATH entries:", got,
    if (is.na(Sys.getenv("R_CUSTOM_TOOLS_PATH", NA))) "" else paste0("(R_CUSTOM_TOOLS_PATH='", custom, "')"), "\n")
RCODE
    for custom in unset "" "C:/r-zig-custom-tools"; do
      custom_env=()
      [ "$custom" = unset ] || custom_env=(R_CUSTOM_TOOLS_PATH="$custom")
      (cd "$VERIFY_DIR" && env -i "${base_env[@]}" "${custom_env[@]}" PATH="$R_BINDIR:$sys32" \
        "$R_EXE" CMD Rscript.exe --vanilla path.R) ||
        { echo "error: under R CMD, the PATH entries after bin\\x64 are not ${custom_env[*]:-R_HOME/bin/toolchain/usr/bin and R_HOME/../../usr/bin, expanded} (etc/Rcmd_environ, B25)" >&2; exit 1; }
      (cd "$VERIFY_DIR" && env -i "${base_env[@]}" "${custom_env[@]}" PATH="$R_BINDIR:$sys32" \
        "$RSCRIPT" --vanilla session-path.R) ||
        { echo "error: in an R session, the first PATH entries are not ${custom_env[*]:-R_HOME/bin/toolchain/usr/bin and R_HOME's grandparent's usr/bin} (base's Rprofile, patch 0014)" >&2; exit 1; }
    done
    echo "== R CMD's PATH: bin\\x64, then R_HOME/bin/toolchain/usr/bin and R_HOME/../../usr/bin (or R_CUSTOM_TOOLS_PATH; empty is unset); an R session's starts with the same two, the second without .."
  else
    tools_dir="$(cd "$RHD" && pwd -P)/bin/toolchain/usr/bin"
    in_r="$(env -i "${base_env[@]}" PATH=/usr/bin:/bin "$R_BIN" --vanilla --no-echo -e 'cat(Sys.getenv("PATH"))')"
    in_cmd="$(env -i "${base_env[@]}" PATH=/usr/bin:/bin "$R_BIN" CMD sh -c 'echo "$PATH"')"
    for p in "R:$in_r" "R CMD:$in_cmd"; do
      case "${p#*:}" in
        "$tools_dir:"*) ;;
        *) echo "error: PATH in ${p%%:*} is ${p#*:}, which does not start with $tools_dir (etc/Renviron, B25)" >&2; exit 1 ;;
      esac
    done
    echo "== PATH in R and under R CMD starts with R_HOME/bin/toolchain/usr/bin"
  fi

  # rzig's check mode with no group (B26, B35), the texts the install
  # preflight and R CMD config show: exit 127 for the compilers (no
  # ZIG_BIN, no zig/ in the toolchain, none in the tree's bin or on PATH)
  # and for the build tools (no make on PATH: unix the tree's bin, Windows
  # bin\x64 and System32), as a compile that finds no zig, after a line
  # saying what is missing and the group's text. A zig of the host's own in
  # /usr/bin or /bin, or a python3 there with ziglang, is one rzig rightly
  # finds: the compilers' check is then skipped with a note.
  if [ "$OS" = windows ]; then
    zig_path="$R_BINDIR:$sys32"; make_path="$R_BINDIR:$sys32"
  else
    zig_path=/usr/bin:/bin; make_path="$BUNDLE_DIR/bin"
  fi
  host_zig=""
  if [ "$OS" != windows ]; then
    for z in /usr/bin/zig /bin/zig /usr/bin/x86_64-w64-mingw32-zig /bin/x86_64-w64-mingw32-zig; do
      if [ -x "$z" ]; then host_zig="$z"; fi
    done
    if [ -z "$host_zig" ] && env -i "${base_env[@]}" PATH=/usr/bin:/bin python3 -c 'import ziglang' > /dev/null 2>&1; then
      host_zig="python3 -m ziglang"
    fi
  fi
  checked=""
  for chk in --rzig-check --rzig-check=build-tools; do
    if [ "$chk" = --rzig-check ]; then
      p="$zig_path"; what="$no_zig_line"; group_head="$compilers_head"
    else
      p="$make_path"; what="$no_make_line"; group_head="$build_tools_head"
    fi
    if [ "$chk" = --rzig-check ] && [ -n "$host_zig" ]; then
      echo "   note: ${cc##*/} $chk skipped: this host's $host_zig is on PATH=$p"
      continue
    fi
    rc=0
    env -i "${base_env[@]}" PATH="$p" "$cc" "$chk" > "$VERIFY_DIR/check.log" 2>&1 || rc=$?
    if [ "$rc" != 127 ] || ! starts_line "$VERIFY_DIR/check.log" "$what" ||
       ! starts_line "$VERIFY_DIR/check.log" "$group_head"; then
      cat "$VERIFY_DIR/check.log" >&2
      echo "error: ${cc##*/} $chk with the base alone (PATH=$p): exit $rc, not 127 with '$what' and '$group_head...'" >&2
      exit 1
    fi
    checked="$checked $chk"
  done
  [ -z "$checked" ] || echo "== check mode with the base alone: ${cc##*/}$checked exit 127, each with what is missing and its group's text"

  # R CMD SHLIB with the base alone (feat-shlib-rzig-build Cg5, Cg13): R
  # asks rzig build first (patch 0013's one hook), which stops with the
  # compilers' text, the text pkgbuild's check_build_tools(debug = TRUE)
  # shows for its probe, and builds nothing; with a Makevars rule as well,
  # both groups' texts in one stop, the compilers' first, then rzig's
  # reason and the build tools'. No zig and no make: unix the tree's bin
  # alone on PATH, Windows bin\x64 and System32 (no ZIG_BIN either way).
  s1="$VERIFY_DIR/shlib-base"
  mkdir -p "$s1/probe" "$s1/rule"
  printf 'void foo(int *bar) { *bar = 1; }\n' > "$s1/probe/foo.c"
  printf 'void x(int *n) { *n = 1; }\n' > "$s1/rule/x.c"
  printf '%s\n' 'all: $(SHLIB) extra' 'extra:' '	@echo extra' > "$s1/rule/Makevars"
  if [ "$OS" = windows ]; then s1_r="$R_EXE"; s1_path="$R_BINDIR:$sys32"; else s1_r="$R_BIN"; s1_path="$BUNDLE_DIR/bin"; fi
  for d in probe rule; do
    rc=0; why=""; bt=""
    src=foo.c; [ "$d" = probe ] || src=x.c
    (cd "$s1/$d" && env -i "${base_env[@]}" PATH="$s1_path" "$s1_r" CMD SHLIB "$src") > "$s1/$d.log" 2>&1 || rc=$?
    comp="$(tr -d '\r' < "$s1/$d.log" | grep -n -m1 -F "$compilers_head" | cut -d: -f1 || true)"
    bad=""
    [ "$rc" != 0 ] && [ -n "$comp" ] || bad=1
    starts_line "$s1/$d.log" "$compilers_standalone" || bad=1
    [ -z "$(cd "$s1/$d" && ls ./*.o ./*."$SO" 2> /dev/null)" ] || bad=1
    if [ "$d" = rule ]; then
      why="$(tr -d '\r' < "$s1/$d.log" | grep -n -m1 -F "x.$SO needs make: Makevars has a rule or target line" | cut -d: -f1 || true)"
      bt="$(tr -d '\r' < "$s1/$d.log" | grep -n -m1 -F "$build_tools_head" | cut -d: -f1 || true)"
      { [ -n "$why" ] && [ -n "$bt" ] && [ -n "$comp" ] && [ "$comp" -lt "$why" ] && [ "$why" -lt "$bt" ]; } || bad=1
    fi
    if [ -n "$bad" ]; then
      cat "$s1/$d.log" >&2
      want="the compilers' text naming ${archives[1]##*/}"
      [ "$d" = probe ] || want="the compilers' text naming ${archives[1]##*/}, rzig's reason and the build tools' text, in that order"
      echo "error: R CMD SHLIB $src with the base alone (PATH=$s1_path): exit $rc, or not $want, or something built" >&2
      exit 1
    fi
  done
  echo "== R CMD SHLIB with the base alone: stops with the compilers' text (naming ${archives[1]##*/}), nothing built; with a Makevars rule, the compilers' text, rzig's reason and the build tools' text, in that order"

  # TLS trust (unix): the bundle must verify HTTPS without the build env's
  # trust anchors. conda-forge's libcurl/OpenSSL carry $CONDA/ssl compiled
  # in, which exists on this machine only, so "HTTPS works here" proves
  # nothing on its own. scripts/tls-check.R (shared with wheel-test.sh)
  # checks the wiring and makes real requests; here, where strace can
  # trace, the requests must also read no CA file from the build env. The
  # trace only counts when the requests ran: curl opens its CA file after
  # connecting, so an offline run would pass it vacuously. Windows uses
  # Schannel (the Windows store) and needs none of this.
  if [ "$OS" != windows ]; then
    tls_r="$(cd "$(dirname "$0")" && pwd)/tls-check.R"
    tls_out="$VERIFY_DIR/tls-check.out"
    run_tls() {
      env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$@" "$R_BIN" --vanilla --no-echo -f "$tls_r"
    }
    build_env="${CONDA_PREFIX:-}"
    strace_bin=""
    if [ "$OS" = linux ] && [ -n "$build_env" ]; then
      # `?`: skip syscalls this architecture lacks (aarch64 has no open(2)).
      # Preflight: where ptrace is blocked (containers, Yama) the trace is
      # skipped locally rather than failing a good bundle (cannot_check).
      if ! command -v strace > /dev/null 2>&1; then
        cannot_check "strace unavailable; build-env CA check skipped"
      elif strace -f -qq -e 'trace=?openat,?open' -o /dev/null /bin/true 2> /dev/null; then
        strace_bin="$(command -v strace)"
      else
        cannot_check "strace cannot trace here; build-env CA check skipped"
      fi
    fi
    if [ -n "$strace_bin" ]; then
      trace="$VERIFY_DIR/tls-trace.txt"
      run_tls "$strace_bin" -f -qq -e 'trace=?openat,?open' -o "$trace" | tee "$tls_out"
    else
      run_tls | tee "$tls_out"
    fi
    if grep -q '^TLS: requests OK' "$tls_out"; then
      if [ -n "$strace_bin" ]; then
        opened="$(grep -oE "\"$build_env/[^\"]*\"" "$trace" | tr -d '"' | sort -u || true)"
        opened_ca="$(printf '%s\n' "$opened" | grep -E 'cacert|ca-bundle|cert\.pem|/certs(/|$)' || true)"
        if [ -n "$opened_ca" ]; then
          echo "error: HTTPS read trust anchors from the build env:" >&2
          printf '  %s\n' $opened_ca >&2
          exit 1
        fi
        other="$(printf '%s\n' "$opened" | grep -v '^$' | tr '\n' ' ' || true)"
        [ -z "$other" ] || echo "   note: still opened from the build env (missing elsewhere, harmless): $other"
      fi
      echo "== TLS trust verified${strace_bin:+ (no CA file read from the build env)}"
    else
      echo "== TLS trust: wiring checked; requests skipped (offline)"
    fi
  fi

  # hermetic-check.sh's tier 0/1 on the extracted base (R_INSTALL_PREFIX
  # makes it env.sh's prefix): R-only packages one at a time and with
  # Ncpus = 2, a binary package, the install preflight stopping a compiled
  # package with rzig's compilers text, unix R CMD config CC with the
  # build tools' text, Windows tcltk from R_HOME/Tcl, no temp leftovers,
  # linux under strace. It works on a copy of the base as extracted, rzig
  # included (B26).
  R_INSTALL_PREFIX="$BUNDLE_DIR" bash "$(dirname "$0")/hermetic-check.sh"
else
  echo "   note: scenario 1 (the base alone) runs in the toolchain pass only: it passes no zig (PHASE5 open point S)"
fi

# --- Scenario 2: base + compilers -------------------------------------------
extract "${archives[1]}" "$lists/compilers"
echo "== scenario 2: base + compilers"
mk="$RHD/etc/Makeconf"
[ "$OS" != windows ] || mk="$RHD/etc/x64/Makeconf"
# The PATH of the check mode and of the compiles below that need nothing
# but the compilers: unix /usr/bin:/bin, Windows bin\x64 and System32.
if [ "$OS" = windows ]; then chk_path="$R_BINDIR:$sys32"; else chk_path=/usr/bin:/bin; fi

# flang: the compilers group's, TC/flang (feat-standalone-toolchain phase
# 6, B9), in both passes (PHASE6 open point O). pass_flang is its driver
# as rzig names it, as pass_zig below: unix its own path with symlinks
# resolved (macOS' /var is /private/var); Windows the long form with `/`,
# compared case-insensitively. tc_phys is TC spelled the same way, for
# the paths rzig derives from flang's (the intrinsic modules, the
# runtime: Cc3).
test -x "$TC/flang/bin/flang$exe" ||
  { echo "error: ${archives[1]##*/} has no flang/bin/flang$exe: the compilers group holds flang since phase 6 (B9; pixi run toolchain, package-toolchain)" >&2; exit 1; }
if [ "$OS" = windows ]; then
  tc_phys="$(cygpath -m -l "$TC")"
else
  tc_phys="$(cd "$TC" && pwd -P)"
fi
pass_flang="$tc_phys/flang/bin/flang$exe"
# Nothing reaches TC/flang but zig-fc's own flags: no .cfg anywhere in the
# extracted tree (flang reads one beside its driver, and the toolchain
# build copies none, B9), and no flang on the check mode's PATH. A host's
# own flang in /usr/bin is noted: the RZIG_PRINT_ARGV checks below still
# show which flang runs.
cfgs="$(find "$BUNDLE_DIR" -name '*.cfg')"
[ -z "$cfgs" ] ||
  { echo "error: .cfg files in the extracted tree (flang would read one beside its driver; TC/flang has none, B9):" >&2; printf '%s\n' "$cfgs" | sed 's/^/  /' >&2; exit 1; }
host_flang="$(PATH="$chk_path"; command -v flang 2> /dev/null || true)"
if [ -n "$host_flang" ]; then
  echo "   note: this host has a flang on PATH=$chk_path, $host_flang: zig-fc must still run TC/flang's (checked below)"
  echo "== TC/flang: $pass_flang; no .cfg in the extracted tree"
else
  echo "== TC/flang: $pass_flang; no .cfg in the extracted tree, no flang on PATH=$chk_path"
fi

# pass_zig, the zig the pass's compiles run and its assertions name: in
# the toolchain pass the compilers group's, as rzig spells it (unix: its
# own path with symlinks resolved, main.zig's selfExe, so macOS' /var is
# /private/var; Windows: the long form, as the check line shows it, with
# `/`: windows-latest's TEMP is an 8.3 path); in the build pass $ZIG.
if [ "$pass" = build ]; then
  pass_zig="$zig_bin"
else
  test -x "$TC/zig/zig$exe" ||
    { echo "error: ${archives[1]##*/} has no zig/zig$exe: the compilers group holds zig since phase 5 (B4; pixi run toolchain, package-toolchain)" >&2; exit 1; }
  if [ "$OS" = windows ]; then
    pass_zig="$(cygpath -m -l "$TC")/zig/zig.exe"
  else
    pass_zig="$(cd "$TC/zig" && pwd -P)/zig"
  fi
fi
# The build pass follows unless the build's zig is TC/zig's bytes (the
# upstream legs: fetch-zig's zig, the same wheel): nothing more to test.
# Decided here, while TC/zig/zig is in place (scenario 3 moves it aside
# for a while) (Cc4).
build_pass=""
if [ "$pass" = toolchain ] && [ -n "$ZIG" ] && ! cmp -s "$ZIG" "$TC/zig/zig$exe"; then build_pass=1; fi

# rzig's check mode with the compilers there: the pass's zig (TC/zig's,
# or ZIG_BIN's in the build pass), exit 0, and the line names it (Windows:
# with `/` only, check.zig's display; PHASE5 open point Q); zig-fc's
# names TC/flang's driver too, with no flang on PATH.
if [ -n "$pass_zig" ]; then
  out="$(env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$cc" --rzig-check | tr -d '\r')" ||
    { echo "error: ${cc##*/} --rzig-check failed with zig from $pass_what" >&2; exit 1; }
  printf '%s\n' "$out" | grep -qiF -- " at $pass_zig" ||
    { printf '%s\n' "$out" >&2; echo "error: ${cc##*/} --rzig-check does not name the $pass pass's zig, $pass_zig" >&2; exit 1; }
  echo "   $out"
  out="$(env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$fc" --rzig-check | tr -d '\r')" ||
    { echo "error: ${fc##*/} --rzig-check failed with zig from $pass_what and TC/flang" >&2; exit 1; }
  printf '%s\n' "$out" | grep -qiF -- "flang at $pass_flang" ||
    { printf '%s\n' "$out" >&2; echo "error: ${fc##*/} --rzig-check does not name TC/flang's driver, $pass_flang" >&2; exit 1; }
  echo "   $out"
  echo "== check mode with the compilers: exit 0, zig from $pass_what, flang from TC/flang"
fi

# The first C++ compile (PHASE5 open point G, (Cc11)): a shared library
# from <iostream>, <string> and <vector>, by the bundle's C++ compiler
# (unix zig-cxx, Windows g++.exe) with nothing but the compilers on PATH,
# timed. In the toolchain pass zig's cache is a new user's, empty: the
# time is what a user waits once (zig builds libc++ into its cache, with
# its header warnings), the measurement TODO asks for; in the build pass
# it is env.sh's, for comparison: warm only if an earlier task compiled
# C++ there (contract, pkg-parity), which a fresh checkout's chain may
# not have (omicron, phase 5 step 6). No shared C++ runtime: zig links
# libc++ statically.
if [ -n "$pass_zig" ]; then
  cx="$VERIFY_DIR/first-cxx"
  mkdir -p "$cx"
  cat > "$cx/x.cpp" <<'CPP'
#include <iostream>
#include <string>
#include <vector>
extern "C" int rzig_len(const char *s)
{
    std::vector<std::string> v{std::string(s)};
    if (v[0].empty()) std::cerr << "empty\n";
    return (int) v[0].size();
}
CPP
  if [ "$OS" = windows ]; then
    cx_cc="$TC/g++.exe"; cx_flags=(-shared -o x.dll); cx_lib=x.dll
  else
    cx_cc="$TC/zig-cxx"; cx_flags=(-shared -fPIC -o x.so); cx_lib=x.so
  fi
  if [ "$pass" = build ]; then
    cx_cache="$ZIG_GLOBAL_CACHE_DIR"; cx_which="env.sh's cache, for comparison"
  elif [ "$OS" = windows ]; then
    cx_cache="$home/zig"; cx_which="an empty cache, \$HOME's LOCALAPPDATA"
  else
    cx_cache="$home/.cache/zig"; cx_which="an empty cache, \$HOME/.cache/zig"
  fi
  t0=$SECONDS
  (cd "$cx" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$cx_cc" "${cx_flags[@]}" x.cpp) > "$cx/log" 2>&1 ||
    { cat "$cx/log" >&2; echo "error: the bundle's ${cx_cc##*/} could not build a C++ shared library (zig from $pass_what)" >&2; exit 1; }
  cx_s=$((SECONDS - t0))
  test -d "$cx_cache" ||
    { echo "error: after the first C++ compile, zig's cache is not at $cx_cache (a zig cache variable reached the $pass pass?)" >&2; exit 1; }
  if [ "$OS" = windows ]; then
    cx_dep="$(needed_of "$cx/$cx_lib" | grep -iE '^(libc\+\+|libstdc\+\+-6)\.dll$' || true)"
  else
    cx_dep="$(cxx_deps "$cx/$cx_lib")"
  fi
  [ -z "$cx_dep" ] || { echo "error: $cx_lib, the first C++ compile, needs a shared C++ runtime: $cx_dep" >&2; exit 1; }
  # sizes from ls, not du: du counts blocks, which a compressing
  # filesystem shrinks
  cx_mb="$(find "$cx_cache" -type f -exec ls -ln {} + | awk '{ s += $5 } END { printf "%d", s / 1048576 }')"
  cx_warn="$(grep -c 'warning:' "$cx/log" || true)"
  echo "== the first C++ compile (the $pass pass, $cx_which): $cx_s s, zig's cache $cx_mb MB, $cx_warn warning lines; no shared C++ runtime"

  # The zig the compilers run, every OS (Cg4): rzig takes ZIG_BIN only
  # when it names a zig from the compile's own directory, and otherwise
  # quietly looks further (TC/zig's, the tree's bin/, then PATH's), so the
  # command's first word, after the ZIG_LIB_DIR= line rzig prints first
  # where it gives conda-forge's zig the libc++ mirror (every macOS env),
  # must be the pass's zig. Windows: rzig joins TC/zig's as
  # <TC>/zig\zig.exe, hence `\` to `/`, and NTFS ignores case (open
  # point Q). A dry run: no zig runs.
  rz="$(cd "$cx" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" RZIG_PRINT_ARGV=1 "$cc" -c a.c |
    tr -d '\r' | grep -v '^ZIG_LIB_DIR=' | sed -n 1p | tr '\\' /)" || true
  printf '%s\n' "$rz" | grep -qixF -- "$pass_zig" ||
    { echo "error: the bundle's ${cc##*/} runs '$rz', not the $pass pass's zig $pass_zig" >&2; exit 1; }
  echo "== the bundle's compilers run the $pass pass's zig, $pass_zig"
fi

# The first Fortran compile (feat-standalone-toolchain phase 6, the
# measurement PLAN.md asks for): R CMD SHLIB of the derived-type module
# (fdt_src) through rzig build with no make (patch 0013's one hook; PATH
# unix the tree's bin alone, Windows bin\x64 and System32: no flang on
# it), in a HOME of its own, so that, in the toolchain pass, zig's cache
# is empty: what a user waits for
# a first Fortran library (the first C++ compile filled the other HOME's
# caches). In the build pass zig's cache is env.sh's: for comparison.
# The same call again gives the warm time; the library loads and
# returns the area.
if [ -n "$pass_zig" ]; then
  fx="$VERIFY_DIR/first-fortran"
  fhome="$VERIFY_DIR/fhome"
  mkdir -p "$fhome"
  fdt_src "$fx"
  conftest_f "$fx"
  if [ "$OS" = windows ]; then
    fx_r="$R_EXE"; fx_path="$R_BINDIR:$sys32"; fx_load=(PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla)
    fx_home=(USERPROFILE="$(w "$fhome")" HOME="$(w "$fhome")" LOCALAPPDATA="$(w "$fhome")"); fx_cache="$fhome/zig"
  else
    fx_r="$R_BIN"; fx_path="$BUNDLE_DIR/bin"; fx_load=(PATH=/usr/bin:/bin "$R_BIN" --vanilla --no-echo)
    fx_home=(HOME="$fhome"); fx_cache="$fhome/.cache/zig"
  fi
  fx_first=""; fx_warm=""
  for run in first warm; do
    rm -f "$fx/fmod.$SO" "$fx"/*.mod
    t0=$SECONDS
    (cd "$fx" && env -i "${base_env[@]}" "${fx_home[@]}" "${zig_env[@]}" PATH="$fx_path" RZIG_TRACE=1 \
      "$fx_r" CMD SHLIB -o "fmod.$SO" m.f90 u.f90) > "$fx/$run.log" 2>&1 ||
      { cat "$fx/$run.log" >&2; echo "error: R CMD SHLIB of a derived-type module (m.f90, u.f90; the $run call) failed with TC/flang, zig from $pass_what and no make" >&2; exit 1; }
    if [ "$run" = first ]; then fx_first=$((SECONDS - t0)); else fx_warm=$((SECONDS - t0)); fi
    starts_line "$fx/$run.log" "rzig build: R CMD SHLIB, tier 1" ||
      { cat "$fx/$run.log" >&2; echo "error: R CMD SHLIB of the derived-type module did not build through rzig build (no 'rzig build: R CMD SHLIB, tier 1')" >&2; exit 1; }
  done
  (cd "$fx" && env -i "${base_env[@]}" "${fx_load[@]}" -e "dyn.load('fmod.$SO'); stopifnot(.Fortran('fdtv', v = 0)\$v == 42)") ||
    { echo "error: fmod.$SO (the derived-type module through R CMD SHLIB) did not load or return 42" >&2; exit 1; }
  if [ "$pass" = toolchain ]; then
    test -d "$fx_cache" ||
      { echo "error: after the first Fortran compile, zig's cache is not at $fx_cache (a zig cache variable reached the toolchain pass?)" >&2; exit 1; }
    fx_which="an empty cache, zig's cache then $(find "$fx_cache" -type f -exec ls -ln {} + | awk '{ s += $5 } END { printf "%d", s / 1048576 }') MB"
  else
    fx_which="env.sh's cache, for comparison"
  fi
  echo "== the first Fortran compile (TC/flang, zig from $pass_what, $fx_which): $fx_first s, warm $fx_warm s; R CMD SHLIB of a derived-type module through rzig build, no make, loads (42)"

  # zig-fc's command lines (RZIG_PRINT_ARGV, a dry run; PATH as the check
  # mode's), every OS. A compile is TC/flang's driver with
  # -fintrinsic-modules-path at TC/flang's module directory, a physical
  # path with no `..` (Cc3: flang_rt.zig's modulesDir; omicron's TMPDIR
  # is /private/var/... physically). A program's link is two blocks:
  # TC/flang compiling the source, a line `&&`, then the pass's zig
  # linking with TC/flang's static runtime (decision E: every link
  # through zig). The ZIG_LIB_DIR= line rzig prints before zig's block
  # where it mirrors conda-forge zig's libc++ (macOS) is skipped wherever
  # it stands (Cc6). Windows: `\` read as `/` and every path compared in
  # lower case (NTFS ignores case; open point Q). lc_win <text>: that
  # case rule for a path compared with fc_argv's lines.
  lc_win() { if [ "$OS" = windows ]; then printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'; else printf '%s\n' "$1"; fi; }
  fc_argv() {
    (cd "$fx" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" RZIG_PRINT_ARGV=1 "$fc" "$@") |
      tr -d '\r' | grep -v '^ZIG_LIB_DIR=' | tr '\\' / | { if [ "$OS" = windows ]; then tr '[:upper:]' '[:lower:]'; else cat; fi; }
  }
  lc_flang="$(lc_win "$pass_flang")"; lc_zig="$(lc_win "$pass_zig")"; lc_tc="$(lc_win "$tc_phys")"
  argv="$(fc_argv -c m.f90 -o m.o)" || true
  first="$(printf '%s\n' "$argv" | sed -n 1p)"
  [ "$first" = "$lc_flang" ] ||
    { printf '%s\n' "$argv" >&2; echo "error: zig-fc -c m.f90 runs '$first', not TC/flang's driver $pass_flang" >&2; exit 1; }
  mods="$(printf '%s\n' "$argv" | grep -A1 -xF -- -fintrinsic-modules-path | sed -n 2p)"
  mods_dir="$mods"; [ "$OS" != windows ] || [ -z "$mods" ] || mods_dir="$(cygpath -u "$mods")"
  case "$mods" in
    *..*) mods_ok="" ;;
    "$lc_tc/flang/lib/clang/"*/finclude/flang/*) mods_ok=1 ;;
    *) mods_ok="" ;;
  esac
  [ -n "$mods_ok" ] && test -d "$mods_dir" ||
    { printf '%s\n' "$argv" >&2; echo "error: zig-fc -c m.f90's -fintrinsic-modules-path is '$mods', not a directory under $tc_phys/flang/lib/clang/<major>/finclude/flang/ with no '..' (Cc3)" >&2; exit 1; }
  argv="$(fc_argv -o "conftest$exe" conftest.f)" || true
  b1="$(printf '%s\n' "$argv" | awk '$0 == "&&" { exit } { print }')"
  b2="$(printf '%s\n' "$argv" | awk 'f { print } $0 == "&&" { f = 1 }')"
  rt=""
  while IFS= read -r l; do
    case "$l" in "$lc_tc/flang/lib/clang/"*/lib/*/libflang_rt.runtime.a) rt="$l" ;; esac
  done <<< "$b2"
  if [ "$(printf '%s\n' "$argv" | grep -cxF '&&')" != 1 ] || [ "$(printf '%s\n' "$b1" | sed -n 1p)" != "$lc_flang" ] ||
     ! printf '%s\n' "$b1" | grep -qxF -- -c || [ "$(printf '%s\n' "$b2" | sed -n 1p)" != "$lc_zig" ] || [ -z "$rt" ]; then
    printf '%s\n' "$argv" >&2
    echo "error: zig-fc -o conftest$exe conftest.f is not TC/flang compiling (-c), '&&', then the $pass pass's zig $pass_zig linking with TC/flang's lib/clang/<major>/lib/<dir>/libflang_rt.runtime.a (decision E)" >&2
    exit 1
  fi
  echo "== zig-fc's commands: TC/flang compiles with -fintrinsic-modules-path ${mods#"$lc_tc/"} (physical, no '..'); a program is TC/flang's compile, then the $pass pass's zig linking ${rt#"$lc_tc/"}"

  # omp_lib.h (Cc9): a cpp #include "omp_lib.h" in a .F source is
  # expanded by $FC -E from TC/flang's module directory, the one the flag
  # names (on macOS the bare driver's default has none, CP2); a Fortran
  # INCLUDE 'omp_lib.h', which flang's -E leaves in place for the
  # compile (phase 6 step 3's measurement), compiles. Every flavor:
  # omp_lib.h is in the one module directory (B40's Fortran limit, U).
  printf '%s\n' '      subroutine ic(n)' '      implicit none' '#include "omp_lib.h"' '      integer n' '      n = omp_get_max_threads()' '      end' > "$fx/inc_cpp.F"
  printf '%s\n' 'subroutine io(n)' '  implicit none' "  include 'omp_lib.h'" '  integer, intent(out) :: n' '  n = omp_get_max_threads()' 'end subroutine io' > "$fx/inc_omp.f90"
  (cd "$fx" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$fc" -E inc_cpp.F > inc_cpp.i 2> inc.log &&
    env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$fc" -c inc_omp.f90 -o inc_omp.o >> inc.log 2>&1) ||
    { cat "$fx/inc.log" >&2; echo "error: \$FC -E of a #include \"omp_lib.h\" source, or \$FC -c of an INCLUDE 'omp_lib.h' one, failed" >&2; exit 1; }
  inc="$(tr -d '\r' < "$fx/inc_cpp.i" | sed -n 's/^#line "\(.*omp_lib\.h\)".*/\1/p' | sed -n 1p | tr -s '\\' /)"
  [ "$(lc_win "$inc")" = "$mods/omp_lib.h" ] ||
    { echo "error: \$FC -E expanded #include \"omp_lib.h\" from '${inc:-(nowhere)}', not from $mods/omp_lib.h (Cc9)" >&2; exit 1; }
  echo "== omp_lib.h: \$FC -E expands #include \"omp_lib.h\" from TC/flang's module directory; INCLUDE 'omp_lib.h' compiles"

  # The derived-type module as a package, fdt: src/m.f90 and src/u.f90
  # (fdt_src) and src/init.c registering fdtv, no Makevars, so R CMD
  # INSTALL builds it through rzig build's tier 1 with no make
  # (RZIG_TRACE=1: `rzig build: tier 1`), m.f90's .mod before u.f90; it
  # loads with nothing but the tree and returns the area. PATH as above.
  fd="$VERIFY_DIR/fdt"
  fdt_src "$fd/fdt/src"
  mkdir -p "$fd/fdt/R" "$fd/lib"
  printf 'Package: fdt\nVersion: 0.1\nTitle: Verify Bundle\nDescription: A Fortran module with a derived type, through rzig build.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$fd/fdt/DESCRIPTION"
  printf 'useDynLib(fdt)\nexport(f)\n' > "$fd/fdt/NAMESPACE"
  printf 'f <- function() .Fortran("fdtv", v = 0, PACKAGE = "fdt")$v\n' > "$fd/fdt/R/f.R"
  printf '%s\n' '#include <R.h>' '#include <R_ext/Rdynload.h>' 'void F77_NAME(fdtv)(double *v);' \
    'static const R_FortranMethodDef fdt_f[] = {{"fdtv", (DL_FUNC) &F77_NAME(fdtv), 1, NULL}, {NULL, NULL, 0, NULL}};' \
    'void R_init_fdt(DllInfo *dll) { R_registerRoutines(dll, NULL, NULL, fdt_f, NULL); R_useDynamicSymbols(dll, FALSE); }' > "$fd/fdt/src/init.c"
  (cd "$fd" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$fx_path" RZIG_TRACE=1 \
    "$fx_r" CMD INSTALL -l lib fdt) > "$fd/install.log" 2>&1 ||
    { cat "$fd/install.log" >&2; echo "error: fdt (a derived-type module, two Fortran files and a C init) did not install with TC/flang and no make" >&2; exit 1; }
  starts_line "$fd/install.log" "rzig build: tier 1" ||
    { cat "$fd/install.log" >&2; echo "error: fdt did not build through rzig build (no 'rzig build: tier 1' line)" >&2; exit 1; }
  (cd "$fd" && env -i "${base_env[@]}" "${fx_load[@]}" \
    -e 'stopifnot(getExportedValue(loadNamespace("fdt", lib.loc = "lib"), "f")() == 42)') ||
    { echo "error: fdt, built through rzig build, did not load or return 42" >&2; exit 1; }
  echo "== the derived-type module as a package: fdt builds through rzig build (tier 1, no make), loads and returns 42"
fi

# The install preflight's other branches (B26, C26; feat-zig-pkg-build
# M4): the pass's zig, and no make (the build-tools group is not
# extracted yet) and no flang on PATH: unix the tree's bin alone, Windows
# bin\x64 and System32 [phase3-P3-9]. The preflight (patch 0009, rzig's
# --rzig-check=package) decides as `rzig build` decides in install.R's
# hook (patch 0013): a package with C code and no Makevars (pfC) passes
# the compilers' check, needs no make, and the hook builds it through
# rzig build (RZIG_TRACE=1: `rzig build: tier 1`, no recipe make echoed)
# with the caches a user's install has (zig_env has no
# ZIG_LOCAL_CACHE_DIR) [phase3-P3-6]: no zig build (tier1.zig), so no
# build-runner-* in rzig's cache under this HOME, and nothing of pfC
# there; its build root goes with the install, and it loads; one whose
# Makevars has a rule (pfM, mkpkg's lib: a static library through $(AR))
# needs make and stops at the build tools' check with rzig's reason and
# their text. unix also: one with a
# Fortran source, src/a.f (pfF), stops at the compilers' with no flang
# (TC/flang's driver moved aside, open point N) and their text; an
# R-only package with a configure script (pfG,
# configure_marker) stops at the build tools' with "a configure script R
# runs", its configure not run. The preflight's own ERROR line tells its
# stop from the one install.R's R CMD config (patch 0010) would make
# later, before the configure (that call needs make too), which the
# marker alone could not.
# None but pfC installs. (Scenario 3 runs the preflight with no zig.)
if [ -n "$pass_zig" ]; then
  pf="$VERIFY_DIR/preflight"
  # the R that installs (R CMD INSTALL) and its PATH; the R that loads
  # pfC, with its PATH
  if [ "$OS" = windows ]; then
    pf_r="$R_EXE"; pf_path="$R_BINDIR:$sys32"; pf_load=(PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla)
  else
    pf_r="$R_BIN"; pf_path="$BUNDLE_DIR/bin"; pf_load=(PATH=/usr/bin:/bin "$R_BIN" --vanilla --no-echo)
  fi
  mkpkg "$pf/pk" pfC 1
  mkpkg "$pf/pk" pfM 3 lib
  if [ "$OS" != windows ]; then
    mkpkg "$pf/pk" pfF 2
    printf '      subroutine pff\n      end\n' > "$pf/pk/pfF/src/a.f"
    mkdir -p "$pf/pk/pfG/R"
    printf 'Package: pfG\nVersion: 0.1\nTitle: Verify Bundle\nDescription: R only, with a configure script.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$pf/pk/pfG/DESCRIPTION"
    echo 'export(g)' > "$pf/pk/pfG/NAMESPACE"
    echo 'g <- function() 7L' > "$pf/pk/pfG/R/g.R"
    configure_marker "$pf/pk/pfG"
  fi
  mkdir -p "$pf/lib"
  # preflight_stops <package> <what is missing> <the group's first line>
  preflight_stops() {
    local rc=0
    (cd "$pf" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$pf_path" \
      "$pf_r" CMD INSTALL -l lib "pk/$1") > "$pf/$1.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ] || [ -e "$pf/lib/$1" ] || [ -e "$pf/pk/$1/configure-ran" ] ||
       ! starts_line "$pf/$1.log" "$2" || ! starts_line "$pf/$1.log" "$3" ||
       ! starts_line "$pf/$1.log" "$preflight_stop"; then
      cat "$pf/$1.log" >&2
      echo "error: the install preflight did not stop $1 with '$2' and '$3...' (exit $rc)" >&2
      exit 1
    fi
  }
  preflight_stops pfM "zig-cc: pfM needs make: src/Makevars has a rule or target line: '\$(SHLIB): lib/libval.a'; no make on PATH" "$build_tools_head"
  if [ "$OS" != windows ]; then
    flang_aside
    preflight_stops pfF "$no_flang_line" "$compilers_head"
    flang_back
    preflight_stops pfG "zig-cc: pfG needs make: a configure script R runs; no make on PATH" "$build_tools_head"
  fi
  (cd "$pf" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$pf_path" RZIG_TRACE=1 \
    "$pf_r" CMD INSTALL -l lib pk/pfC) > "$pf/pfC.log" 2>&1 ||
    { cat "$pf/pfC.log" >&2; echo "error: pfC (C, no Makevars) did not install with the compilers and no make" >&2; exit 1; }
  starts_line "$pf/pfC.log" "rzig build: tier 1" ||
    { cat "$pf/pfC.log" >&2; echo "error: pfC did not build through rzig build (no 'rzig build: tier 1' line)" >&2; exit 1; }
  if [ -n "$(make_recipes "$pf/pfC.log")" ]; then
    cat "$pf/pfC.log" >&2; echo "error: a recipe make echoed in pfC's install log" >&2; exit 1
  fi
  # no zig build command in the trace (grep reads to the end, no -q:
  # grep -q's early exit could kill tr with SIGPIPE and fail the
  # pipeline, pipefail [tests-SIGPIPE-1]), the link naming R's link
  # object beside rzig (link_object_named; feat-r-home-link-objects), and
  # in this HOME's rzig cache, the one rzig's trace names, its own kinds
  # of entry alone, no link object (rzig_cache_odd), and none of pfC's
  # objects (f.o, val.o) or its library
  if tr -d '\r' < "$pf/pfC.log" | grep -E -- ' build --build-file ' > /dev/null; then
    cat "$pf/pfC.log" >&2; echo "error: pfC's install ran zig build: tier 1 runs none" >&2; exit 1
  fi
  link_object_named "$pf/pfC.log" ||
    { cat "$pf/pfC.log" >&2; echo "error: pfC's traced link does not name R_HOME/bin/toolchain/$(link_object)" >&2; exit 1; }
  if [ "$OS" = windows ]; then pf_cache="$home/r-zig"; else pf_cache="$home/.cache/r-zig"; fi
  pf_odd="$(rzig_cache_odd "$pf_cache" "$pf/pfC.log")"
  [ -z "$pf_odd" ] ||
    { echo "error: after pfC's install, rzig's cache $pf_cache: $(printf '%s' "$pf_odd" | tr '\n' ' ')(tier 1 runs no zig build; a cache line: rzig's trace names another cache)" >&2; exit 1; }
  [ -z "$(find "$pf_cache" -name f.o -o -name val.o -o -name pfC.so -o -name pfC.dll 2> /dev/null)" ] ||
    { echo "error: after pfC's install, rzig's cache $pf_cache has pfC's objects or library: they belong in its build root" >&2; exit 1; }
  test ! -e "$pf/pk/pfC/src/.rzig" ||
    { echo "error: pfC's install left its build root, $pf/pk/pfC/src/.rzig" >&2; exit 1; }
  (cd "$pf" && env -i "${base_env[@]}" \
    "${pf_load[@]}" -e 'stopifnot(getExportedValue(loadNamespace("pfC", lib.loc = "lib"), "f")() == 1L)') ||
    { echo "error: pfC, built through rzig build, did not load" >&2; exit 1; }
  if [ "$OS" = windows ]; then
    echo "== the install preflight with zig and no build tools (PATH = bin\\x64 + System32): a C package builds through rzig build (no zig build, no build root left) and loads; a Makevars-rule package stops with rzig's reason and the build tools' text"
  else
    echo "== the install preflight with zig and no build tools: a C package builds through rzig build (no zig build, no build root left) and loads; a Makevars-rule package stops with rzig's reason and the build tools' text, an R-only package with a configure script with 'a configure script R runs' and that text (its configure not run), a Fortran one with no flang (TC/flang's driver moved aside) and the compilers' text"
  fi
fi

# A library's objects and the library itself at or below the macOS floor
# (every OS calls it; it checks only on macOS): zig stamps the link, so
# only the objects show a compiler that ignored it (flang defaults to the
# host SDK's version).
check_minos() {
  [ "$OS" = macos ] || return 0
  for f in "$@"; do
    if m="$(minos_over_floor "$f")"; then
      echo "error: ${f##*/} minos $m > $MACOS_MIN" >&2
      exit 1
    fi
  done
}

# R CMD SHLIB with no make (feat-shlib-rzig-build), every OS: the
# run-time compiles of Rcpp, cpp11, TMB, inline and knitr, and pkgbuild's
# compiler probe, which R CMD SHLIB now builds through rzig build (patch
# 0013's one hook in .shlib_internal; rzig build --shlib), with the
# pass's zig and the build tools not extracted: PATH unix the tree's bin
# alone, Windows bin\x64 and System32; Fortran's flang is TC/flang's,
# which zig-fc finds beside it (phase 6).
# RZIG_TRACE=1: each log says `rzig build: R CMD SHLIB, tier
# 1` and holds no recipe make echoed. The shapes: pkgbuild's probe (foo.c
# beside an invalid junk.c, no -o), Rcpp's sourceCpp (-o
# sourceCpp_1.<ext>, a header through CLINK_CPPFLAGS; RZIG_KEEP_ROOT=1
# keeps its build root beside the output, out of R's session directory,
# which R CMD SHLIB's R removes when it exits [shlib-code-1], to read its
# object from, and then it is removed), inline's Fortran, cpp11's
# cpp_source (a Makevars in the working directory, absolute sources,
# --output=), TMB's compile (in process, its library's source in another
# directory, the flags in a user Makevars), the dry run Rcpp's macOS
# OpenMP plugin parses, an OpenMP library where Makeconf offers OpenMP,
# and a Makevars rule, which needs make: rzig's reason, "no make on
# PATH" and the build tools' text, nothing built. Each library loads with
# nothing but the tree on PATH; none leaves an object or a build root
# (.rzig.*) beside its sources.
if [ -n "$pass_zig" ]; then
  sn="$VERIFY_DIR/shlib-nomake"
  mkdir -p "$sn"
  if [ "$OS" = windows ]; then
    sn_r="$R_EXE"; sn_path="$R_BINDIR:$sys32"; sn_load=(PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla)
    # a path R reads: C:/... on Windows
    mp() { cygpath -m "$1"; }
  else
    sn_r="$R_BIN"; sn_path="$BUNDLE_DIR/bin"; sn_load=(PATH=/usr/bin:/bin "$R_BIN" --vanilla --no-echo)
    mp() { printf '%s\n' "$1"; }
  fi
  # sn_run <dir> <log> [VAR=value...] -- <program and arguments>: in
  # <dir>, under env -i with the variables above, traced
  sn_run() {
    local d="$1" log="$2" vars=()
    shift 2
    while [ "$1" != -- ]; do vars+=("$1"); shift; done
    shift
    (cd "$d" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$sn_path" RZIG_TRACE=1 "${vars[@]}" "$@") > "$log" 2>&1
  }
  # sn_built <name> <log> <dir>: the call went through rzig build, no
  # recipe make echoed, and nothing beside the sources in <dir>
  sn_built() {
    starts_line "$2" "rzig build: R CMD SHLIB, tier 1" ||
      { cat "$2" >&2; echo "error: R CMD SHLIB ($1) with no make did not build through rzig build (no 'rzig build: R CMD SHLIB, tier 1')" >&2; exit 1; }
    if [ -n "$(make_recipes "$2")" ]; then cat "$2" >&2; echo "error: a recipe make echoed in R CMD SHLIB's log ($1)" >&2; exit 1; fi
    local left
    left="$(cd "$3" && find . -name '*.o' -o -name '.rzig*' | head -3)"
    [ -z "$left" ] || { echo "error: R CMD SHLIB ($1) left $left beside its sources in $3" >&2; exit 1; }
  }
  # sn_loads <name> <dir> <R expression>: TRUE once the library loads
  sn_loads() {
    (cd "$2" && env -i "${base_env[@]}" "${sn_load[@]}" -e "stopifnot(isTRUE($3))") ||
      { echo "error: R CMD SHLIB's library ($1, through rzig build with no make) did not load or return its value" >&2; exit 1; }
  }
  sn_shapes="probe"

  # pkgbuild's has_compiler(): R CMD SHLIB foo.c in a directory with
  # other sources, which rzig build must leave alone
  mkdir -p "$sn/probe"
  printf 'void foo(int *bar) { *bar = 1; }\n' > "$sn/probe/foo.c"
  printf 'this is not C (\n' > "$sn/probe/junk.c"
  sn_run "$sn/probe" "$sn/probe.log" -- "$sn_r" CMD SHLIB foo.c ||
    { cat "$sn/probe.log" >&2; echo "error: R CMD SHLIB foo.c (pkgbuild's probe) failed with the compilers and no make" >&2; exit 1; }
  sn_built probe "$sn/probe.log" "$sn/probe"
  if grep -q 'junk\.c' "$sn/probe.log"; then cat "$sn/probe.log" >&2; echo "error: R CMD SHLIB foo.c compiled junk.c" >&2; exit 1; fi
  sn_loads probe "$sn/probe" "{dyn.load('foo.$SO'); .C('foo', 0L)[[1]] == 1L}"

  # Rcpp's sourceCpp: C++ (an exception thrown and caught: the static
  # C++ runtime), a header from CLINK_CPPFLAGS; no rpath and no shared
  # C++ runtime (unix), the macOS floor on the library and on its object
  mkdir -p "$sn/cxx/inc"
  printf '#define RZIG_RP_LEN 6\n' > "$sn/cxx/inc/rzigrp.h"
  cat > "$sn/cxx/rp.cpp" <<'CPP'
#include <R.h>
#include <Rinternals.h>
#include <stdexcept>
#include <string>
#include <rzigrp.h>
extern "C" SEXP rp(void)
{
    std::string s("r-zig");
    try { throw std::runtime_error("!"); } catch (const std::exception &e) { s += e.what(); }
    return ScalarInteger(s.size() == RZIG_RP_LEN ? (int) s.size() : -1);
}
CPP
  sn_run "$sn/cxx" "$sn/cxx.log" RZIG_KEEP_ROOT=1 CLINK_CPPFLAGS="-I\"$(mp "$sn/cxx/inc")\"" -- "$sn_r" CMD SHLIB -o "sourceCpp_1.$SO" rp.cpp ||
    { cat "$sn/cxx.log" >&2; echo "error: the sourceCpp shape (C++, CLINK_CPPFLAGS) failed with the compilers and no make" >&2; exit 1; }
  kept=("$sn/cxx"/.rzig.*)
  [ "${#kept[@]}" = 1 ] && cp "${kept[0]}/obj/0/rp.o" "$sn/kept-rp.o" ||
    { echo "error: the sourceCpp shape kept no single build root with obj/0/rp.o beside its output (RZIG_KEEP_ROOT=1): ${kept[*]}" >&2; exit 1; }
  rm -rf "${kept[0]}"
  sn_built sourceCpp "$sn/cxx.log" "$sn/cxx"
  if [ "$OS" != windows ]; then
    so_rp="$(rpaths_of "$sn/cxx/sourceCpp_1.$SO" | tr '\n' ' ')"
    cxx_dep="$(cxx_deps "$sn/cxx/sourceCpp_1.$SO")"
    [ -z "$so_rp$cxx_dep" ] || { echo "error: sourceCpp_1.$SO records rpaths ($so_rp) or needs a shared C++ runtime ($cxx_dep)" >&2; exit 1; }
  fi
  check_minos "$sn/cxx/sourceCpp_1.$SO" "$sn/kept-rp.o"
  sn_loads sourceCpp "$sn/cxx" "{dyn.load('sourceCpp_1.$SO'); .Call('rp') == 6L}"
  sn_shapes="$sn_shapes, sourceCpp"

  # inline's and knitr's Fortran, where FLIBS names the static flang
  # runtime (every flavor's Makeconf), with TC/flang and no flang on PATH
  if grep -q '^FLIBS = .*flang_rt' "$mk"; then
    mkdir -p "$sn/fortran"
    cat > "$sn/fortran/fs.f" <<'FORTRAN'
      subroutine fsum(n, x, s)
      integer n, i
      double precision x(n), s
      s = 0d0
      do 10 i = 1, n
         s = s + x(i)
   10 continue
      end
      subroutine fw(n, r)
      integer n, r
      character(len=12) buf
      write(buf,'(i0)') n
      read(buf,'(i12)') r
      end
FORTRAN
    sn_run "$sn/fortran" "$sn/fortran.log" -- "$sn_r" CMD SHLIB -o "fs.$SO" fs.f ||
      { cat "$sn/fortran.log" >&2; echo "error: R CMD SHLIB of a Fortran file failed with the compilers (TC/flang) and no make" >&2; exit 1; }
    sn_built fortran "$sn/fortran.log" "$sn/fortran"
    f_dep="$(needed_of "$sn/fortran/fs.$SO" | grep flang_rt || true)"
    [ -z "$f_dep" ] || { echo "error: fs.$SO (R CMD SHLIB through rzig build) needs a shared flang runtime: $f_dep" >&2; exit 1; }
    sn_loads fortran "$sn/fortran" "{dyn.load('fs.$SO'); .Fortran('fsum', 3L, c(1, 2, 3), s = 0)\$s == 6 && .Fortran('fw', 42L, r = 0L)\$r == 42L}"
    sn_shapes="$sn_shapes, Fortran"
  fi

  # cpp11's cpp_source: a Makevars in the working directory, absolute
  # sources, --output=
  mkdir -p "$sn/cpp11/inc" "$sn/cpp11/src"
  printf 'inline int c11v() { return 11; }\n' > "$sn/cpp11/inc/rzigc11.h"
  printf '%s\n' 'CXX_STD = CXX11' "PKG_CPPFLAGS = -I'$(mp "$sn/cpp11/inc")'" > "$sn/cpp11/src/Makevars"
  printf '%s\n' '#include <rzigc11.h>' 'int c11a() { return c11v(); }' > "$sn/cpp11/src/a.cpp"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' 'int c11a();' 'extern "C" SEXP c11(void) { return ScalarInteger(c11a() + 1); }' > "$sn/cpp11/src/cpp11.cpp"
  sn_run "$sn/cpp11/src" "$sn/cpp11.log" -- "$sn_r" CMD SHLIB "$(mp "$sn/cpp11/src/a.cpp")" "$(mp "$sn/cpp11/src/cpp11.cpp")" "--output=pkg.$SO" ||
    { cat "$sn/cpp11.log" >&2; echo "error: the cpp11 shape (absolute sources, --output=, a Makevars) failed with the compilers and no make" >&2; exit 1; }
  sn_built cpp11 "$sn/cpp11.log" "$sn/cpp11"
  sn_loads cpp11 "$sn/cpp11/src" "{dyn.load('pkg.$SO'); .Call('c11') == 12L}"
  sn_shapes="$sn_shapes, cpp11"

  # TMB's compile(): .shlib_internal in process, its precompiled
  # library's source in another directory, the flags in a user Makevars;
  # nothing written beside that source
  mkdir -p "$sn/tmb/inc" "$sn/tmb/tmblib" "$sn/tmb/model"
  printf '#define RZIG_TMB 5\n' > "$sn/tmb/inc/rzigtmb.h"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' '#include <R_ext/Rdynload.h>' '#include <rzigtmb.h>' \
    'int tmb_lib(void) { return RZIG_TMB; }' 'extern "C" void LIB_UNLOAD(DllInfo *dll) { (void) dll; }' > "$sn/tmb/tmblib/lib.cpp"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' 'int tmb_lib(void);' 'extern "C" SEXP tmbv(void) { return ScalarInteger(2 * tmb_lib()); }' > "$sn/tmb/model/model.cpp"
  printf '%s\n' "PKG_CPPFLAGS = -I\"$(mp "$sn/tmb/inc")\" -DLIB_UNLOAD=R_unload_model" 'PKG_LIBS = $(SHLIB_OPENMP_CXXFLAGS)' > "$sn/tmb/Makevars.user"
  sn_run "$sn/tmb/model" "$sn/tmb.log" R_MAKEVARS_USER="$(mp "$sn/tmb/Makevars.user")" -- "$RSCRIPT" --vanilla -e \
    "stopifnot(tools:::.shlib_internal(c('model.cpp', '$(mp "$sn/tmb/tmblib/lib.cpp")')) == 0L)" ||
    { cat "$sn/tmb.log" >&2; echo "error: the TMB shape (.shlib_internal in process, a source in another directory) failed with the compilers and no make" >&2; exit 1; }
  sn_built TMB "$sn/tmb.log" "$sn/tmb"
  sn_loads TMB "$sn/tmb/model" "{dyn.load('model.$SO'); .Call('tmbv') == 10L && is.loaded('R_unload_model')}"
  sn_shapes="$sn_shapes, TMB"

  # The dry run: R's own "make would use", then rzig's compile line, which
  # Rcpp's macOS OpenMP plugin reads its compiler from: Makeconf's C++
  # compiler, R_HOME/bin/toolchain/zig-cxx (Windows g++.exe, with /),
  # where R_HOME is what R RHOME prints (bin/R's physical path, cd -P);
  # nothing built
  mkdir -p "$sn/dry"
  cp "$sn/cxx/rp.cpp" "$sn/dry/"
  sn_run "$sn/dry" "$sn/dry.log" -- "$sn_r" CMD SHLIB --dry-run rp.cpp ||
    { cat "$sn/dry.log" >&2; echo "error: R CMD SHLIB --dry-run failed with the compilers and no make" >&2; exit 1; }
  if [ "$OS" = windows ]; then
    rh="$(env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$R_EXE" RHOME | tr -d '\r' | tr '\\' '/')"; cxx_name=g++
  else
    rh="$(env -i "${base_env[@]}" PATH=/usr/bin:/bin "$R_BIN" RHOME)"; cxx_name=zig-cxx
  fi
  after="$(tr -d '\r' < "$sn/dry.log" | awk 'f == 1 { print; f = 2 } /^make would use/ && !f { f = 1 }' | tr '\\' '/')"
  dry_bad() { cat "$sn/dry.log" >&2; echo "error: R CMD SHLIB --dry-run's line after 'make would use' is '$after', which does not start with $rh/bin/toolchain/$cxx_name (Rcpp's macOS OpenMP plugin reads its compiler there)${1:+: $1}" >&2; exit 1; }
  if [ "$OS" = windows ]; then
    # Windows: rzig names the compiler by R_HOME as R hands it over, which
    # may hold 8.3 short names (RUNNER~1), so shellwords.quote single-quotes
    # it, and the file is g++.exe. Compare the compiler word, unquoted: its
    # directory with same_dir (long form, case ignored), its name exactly,
    # with or without .exe.
    case "$after" in
      \'*) dry_cc="${after#\'}"; dry_cc="${dry_cc%%\'*}" ;;
      *) dry_cc="${after%% *}" ;;
    esac
    dry_name="$(printf '%s' "${dry_cc##*/}" | tr '[:upper:]' '[:lower:]')"
    case "$dry_name" in
      "$cxx_name" | "$cxx_name.exe") ;;
      *) dry_bad "the compiler is '$dry_name', not $cxx_name or $cxx_name.exe" ;;
    esac
    same_dir "${dry_cc%/*}" "$rh/bin/toolchain" || dry_bad "'${dry_cc%/*}' is not $rh/bin/toolchain"
  else
    case "$after" in
      "$rh/bin/toolchain/$cxx_name "*) ;;
      *) dry_bad ;;
    esac
  fi
  [ -z "$(cd "$sn/dry" && find . -name '*.o' -o -name "*.$SO" -o -name '.rzig*')" ] ||
    { echo "error: R CMD SHLIB --dry-run built something in $sn/dry" >&2; exit 1; }
  sn_shapes="$sn_shapes, --dry-run"

  # OpenMP, where Makeconf offers it: $(SHLIB_OPENMP_CFLAGS) on the
  # compile and the link, the library links libomp, and a num_threads(2)
  # region runs on two threads
  if grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    mkdir -p "$sn/omp"
    printf '%s\n' '#include <omp.h>' 'void omp2(int *t) {' '  int n = 0;' '#pragma omp parallel num_threads(2) reduction(+:n)' '  n += 1;' '  *t = n + 0 * omp_get_max_threads();' '}' > "$sn/omp/omp2.c"
    printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$sn/omp/Makevars"
    sn_run "$sn/omp" "$sn/omp.log" -- "$sn_r" CMD SHLIB omp2.c ||
      { cat "$sn/omp.log" >&2; echo "error: an OpenMP library (SHLIB_OPENMP_CFLAGS) failed with the compilers and no make" >&2; exit 1; }
    sn_built OpenMP "$sn/omp.log" "$sn/omp"
    needed_of "$sn/omp/omp2.$SO" | grep -qi 'libomp\.' || { needed_of "$sn/omp/omp2.$SO" >&2; echo "error: omp2.$SO (R CMD SHLIB through rzig build) does not link libomp" >&2; exit 1; }
    sn_loads OpenMP "$sn/omp" "{dyn.load('omp2.$SO'); .C('omp2', t = 0L)\$t == 2L}"
    sn_shapes="$sn_shapes, OpenMP"
  fi

  # A Makevars rule needs make: rzig's reason, no make on PATH and the
  # build tools' text (feat-shlib-rzig-build F a); nothing built
  mkdir -p "$sn/rule"
  printf 'void x(int *n) { *n = 1; }\n' > "$sn/rule/x.c"
  printf '%s\n' 'all: $(SHLIB) extra' 'extra:' '	@echo extra' > "$sn/rule/Makevars"
  rc=0
  sn_run "$sn/rule" "$sn/rule.log" -- "$sn_r" CMD SHLIB x.c || rc=$?
  if [ "$rc" = 0 ] || ! grep -qF "x.$SO needs make: Makevars has a rule or target line" "$sn/rule.log" ||
     ! grep -qF "no make on PATH" "$sn/rule.log" || ! starts_line "$sn/rule.log" "$build_tools_head" ||
     [ -n "$(cd "$sn/rule" && find . -name '*.o' -o -name "*.$SO")" ]; then
    cat "$sn/rule.log" >&2
    echo "error: R CMD SHLIB of a Makevars rule with no make: exit $rc, or not rzig's reason, 'no make on PATH' and the build tools' text, or something built" >&2
    exit 1
  fi
  echo "== R CMD SHLIB with the compilers and no make (rzig build): $sn_shapes build, load and leave nothing beside their sources; a Makevars rule stops with rzig's reason and the build tools' text"
fi

# The CPU packages are compiled for, every OS: the baseline of this
# machine's arch, not its own CPU. rzig passes -mcpu=baseline
# (zigbuild/tools/rzig/compiler.zig), so a package compiled here also
# loads on an older CPU of the same arch (a CI-built binary package, a
# cluster's compute nodes); without it Windows compiled for the machine's
# own (kappa: "skylake"). The bundle's C compiler compiles a C file to
# LLVM IR, whose target-cpu must be what the same zig gives with
# -mcpu=baseline and no target: x86-64 on linux and Windows x86_64,
# generic on linux aarch64, apple-m1 on macOS arm64, core2 on macOS
# x86_64 (also under Rosetta). The same zig: the pass's, which the
# compiler runs (asserted above). All three compiles under one env -i
# (Cc3): the build's shell exports env.sh's caches, keyed to the build's
# zig, which TC/zig must never write into (the 2026-10-04 cache mix).
# Once more with -mtune=native, which a Makevars may pass as a portable
# tuning flag: zig would take it as the CPU, so rzig drops it (dropTune).
# (verify-tree.sh checks R's own x86_64 binaries for AVX instructions.)
if [ -n "$pass_zig" ]; then
  cpu_dir="$VERIFY_DIR/cpu"
  mkdir -p "$cpu_dir"
  printf '%s\n' 'double dot(const double *x, const double *y, int n)' \
    '{ double s = 0; for (int i = 0; i < n; i++) s += x[i] * y[i]; return s; }' > "$cpu_dir/cpu.c"
  # the distinct target-cpu values of an IR file, one line
  target_cpu() { { grep -o '"target-cpu"="[^"]*"' "$1" || true; } | sed 's/^"target-cpu"=//' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
  cpu_env=(env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path")
  (cd "$cpu_dir" && "${cpu_env[@]}" "$pass_zig" cc -mcpu=baseline -O2 -S -emit-llvm cpu.c -o want.ll &&
    "${cpu_env[@]}" "$cc" -O2 -S -emit-llvm cpu.c -o got.ll &&
    "${cpu_env[@]}" "$cc" -O2 -mtune=native -S -emit-llvm cpu.c -o tune.ll) > "$cpu_dir/log" 2>&1 ||
    { cat "$cpu_dir/log" >&2; echo "error: compiling a C file to LLVM IR (zig cc -mcpu=baseline, or the bundle's ${cc##*/}) failed" >&2; exit 1; }
  want="$(target_cpu "$cpu_dir/want.ll")"; got="$(target_cpu "$cpu_dir/got.ll")"; tune="$(target_cpu "$cpu_dir/tune.ll")"
  if [ -z "$want" ] || [ "$got" != "$want" ]; then
    echo "error: the bundle's ${cc##*/} compiles for target-cpu ${got:-(none)}, not this arch's baseline ${want:-(none)} (zig cc -mcpu=baseline): packages compiled here would need this machine's CPU" >&2
    exit 1
  fi
  if [ "$tune" != "$want" ]; then
    echo "error: with -mtune=native the bundle's ${cc##*/} compiles for target-cpu ${tune:-(none)}, not $want: zig takes -mtune as the CPU, and the compiler passed it on, so a package's portable -mtune=native would need this machine's CPU" >&2
    exit 1
  fi
  echo "== packages compile for the baseline CPU: the bundle's ${cc##*/} gives target-cpu $got, as zig cc -mcpu=baseline does ($(uname -m)), and with -mtune=native too"
else
  echo "== baseline CPU check skipped (no zig: ZIG_BIN unset, none on PATH)"
fi

# Windows: what rzig (gcc.exe) adds for the environment it is installed in
# (F3b): -L<prefix>/Library/lib on a link, no rpath, and nothing from a
# CONDA_PREFIX it is not installed in; and the compilers group's openmp/
# (-idirafter its include/, -L its lib/ with libomp.lib) where the base
# has libomp.dll, which it has wherever Makeconf offers OpenMP
# (vendor-libs.sh; B40). Dry runs; then one OpenMP DLL compiled and
# linked by gcc.exe directly, since make is a build tool here.
# (unix: the compiled-package checks below)
if [ "$OS" = windows ]; then
  # (poisoned: the OpenMP builds of scenario 3 use it as CONDA_PREFIX too)
  decoy="$VERIFY_DIR/decoy"
  mkdir -p "$decoy/Library/include" "$decoy/Library/lib"
  printf '#error decoy CONDA_PREFIX\n' > "$decoy/Library/include/omp.h"; printf 'junk' > "$decoy/Library/lib/libomp.lib"
  argv="$(CONDA_PREFIX="$(cygpath -w "$decoy")" RZIG_PRINT_ARGV=1 "$cc" -shared -fopenmp -o x.dll a.o)"
  if ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$TOP/Library/lib\$" ||
     printf '%s\n' "$argv" | grep -qi -- 'rpath\|decoy'; then
    printf '%s\n' "$argv" >&2
    echo "error: gcc.exe's environment flags: no -L<prefix>/Library/lib, or an rpath, or CONDA_PREFIX's" >&2
    exit 1
  fi
  echo "== compilers' environment verified (dry run): -L<prefix>/Library/lib, no rpath, CONDA_PREFIX ignored"
  if grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    if ! printf '%s\n' "$argv" | grep -A1 -xF -- -idirafter | grep -qi -- "/$TOP/Library/lib/R/bin/toolchain/openmp/include\$" ||
       ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$TOP/Library/lib/R/bin/toolchain/openmp/lib\$"; then
      printf '%s\n' "$argv" >&2
      echo "error: a -fopenmp link through gcc.exe lacks the compilers group's openmp/ (-idirafter .../toolchain/openmp/include, -L .../toolchain/openmp/lib), which rzig counts where the base has bin/x64/libomp.dll (B40)" >&2
      exit 1
    fi
    echo "== OpenMP from the compilers group (dry run): -idirafter and -L into R_HOME/bin/toolchain/openmp"
  fi
  # zig-fc.exe (F3c): a shared link of objects (USE_FC_TO_LINK) goes
  # through zig as gcc.exe's does, with TC/flang's static runtime and no
  # -lc++ (flang-rt-zig 10's runtime needs no C++ runtime,
  # feat-standalone-toolchain phase 6, open point K).
  argv="$(RZIG_PRINT_ARGV=1 "$fc" -shared -o x.dll a.o | tr -d '\r' | tr '\\' /)"
  if ! printf '%s\n' "$argv" | grep -qiF -- "$tc_phys/flang/lib/clang/" ||
     ! printf '%s\n' "$argv" | grep -qi -- '/libflang_rt\.runtime\.a$' ||
     printf '%s\n' "$argv" | grep -qxF -- '-lc++' ||
     ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$TOP/Library/lib\$"; then
    printf '%s\n' "$argv" >&2
    echo "error: zig-fc.exe's shared link lacks TC/flang's static runtime ($tc_phys/flang/lib/clang/.../libflang_rt.runtime.a) or -L<prefix>/Library/lib, or has -lc++" >&2
    exit 1
  fi
  echo "== zig-fc.exe verified (dry run): a shared link goes through zig with TC/flang's static runtime, no -lc++"

  # A program with $FC alone, as a configure script makes one (PLAN.md
  # phase 6; scenario 3 installs fcconf, whose configure.win does it with
  # the build tools): conftest.f compiled by TC/flang, linked by the
  # pass's zig and run, printing ok, then linked again with -v, with only
  # bin\x64 and System32 on PATH.
  if [ -n "$pass_zig" ]; then
    fw="$VERIFY_DIR/fc-direct"
    conftest_f "$fw"
    (cd "$fw" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$R_BINDIR:$sys32" "$fc" -o conftest.exe conftest.f &&
      env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" ./conftest.exe > out &&
      env -i "${base_env[@]}" "${zig_env[@]}" PATH="$R_BINDIR:$sys32" "$fc" -v -o conftest.exe conftest.f) > "$fw/log" 2>&1 &&
      [ "$(tr -d '\r' < "$fw/out")" = ok ] ||
      { cat "$fw/log" >&2; echo "error: zig-fc.exe -o conftest.exe conftest.f, the program's run (it must print ok), or the link with -v failed with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== a program with \$FC alone: zig-fc.exe compiles (TC/flang), links (zig) and the program runs, with PATH = bin\\x64 + System32; -v links too"
  fi

  # An OpenMP DLL from gcc.exe alone, no make (a build tool): omp.h from
  # the group's openmp/include, the link against its openmp/lib/libomp.lib
  # (PE resolves every symbol at link time), so the DLL imports
  # libomp.dll, which then loads from the base's bin\x64 in an R whose
  # environment holds only what Windows needs and whose PATH is bin\x64
  # and System32 (hermetic-check.sh's scenario). Nothing else on PATH:
  # the pass's zig, CONDA_PREFIX the poisoned decoy.
  if [ -n "$pass_zig" ] && grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    od="$VERIFY_DIR/omp-direct"
    mkdir -p "$od"
    printf '%s\n' '#include <omp.h>' '__declspec(dllexport) void ompd(int *n) { *n = omp_get_max_threads(); }' > "$od/ompd.c"
    printf '%s\n' 'dyn.load("ompd.dll")' 'n <- .C("ompd", n = 0L)$n' 'stopifnot(n >= 1L)' 'cat("ompd: omp_get_max_threads() =", n, "\n")' > "$od/load.R"
    (cd "$od" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$R_BINDIR:$sys32" \
        "$cc" -O2 -fopenmp -c ompd.c -o ompd.o &&
      env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$R_BINDIR:$sys32" \
        "$cc" -shared -fopenmp -o ompd.dll ompd.o) > "$od/log" 2>&1 ||
      { cat "$od/log" >&2; echo "error: gcc.exe could not compile and link an OpenMP DLL with the base and the compilers group" >&2; exit 1; }
    needed_of "$od/ompd.dll" | grep -qix 'libomp\.dll' || { needed_of "$od/ompd.dll" >&2; echo "error: ompd.dll does not import libomp.dll" >&2; exit 1; }
    (cd "$od" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla load.R) ||
      { echo "error: ompd.dll did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== an OpenMP DLL from gcc.exe alone: omp.h and libomp.lib from the compilers group, libomp.dll from bin\\x64 at load"
  fi

  # -lsynchronization (D6): Rust's std links WaitOnAddress and
  # WakeByAddress* from it, and upstream zig has no import library of that
  # name; rzig links the API set's, which both zigs have (windows.zig). A
  # package (mkpkg's shape) whose src/sync.c calls WakeByAddressSingle and
  # whose Makevars.win is PKG_LIBS = -lsynchronization alone (no rule, so
  # rzig build's tier 1, no make), installed and loaded with PATH = bin\x64
  # and System32; in both passes, so each zig links it.
  if [ -n "$pass_zig" ]; then
    sy="$VERIFY_DIR/syncw"
    mkpkg "$sy/pk" syncw 0
    rm "$sy/pk/syncw/src/val.c"
    printf '%s\n' '#include <windows.h>' 'int syncw_val(void) { LONG x = 8; WakeByAddressSingle(&x); return (int) x; }' > "$sy/pk/syncw/src/sync.c"
    printf '%s\n' 'PKG_LIBS = -lsynchronization' > "$sy/pk/syncw/src/Makevars.win"
    mkdir -p "$sy/lib"
    (cd "$sy" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$R_BINDIR:$sys32" RZIG_TRACE=1 \
      "$R_EXE" CMD INSTALL -l lib pk/syncw) > "$sy/install.log" 2>&1 ||
      { cat "$sy/install.log" >&2; echo "error: syncw (PKG_LIBS = -lsynchronization) did not install with the compilers and no make (zig from $pass_what)" >&2; exit 1; }
    starts_line "$sy/install.log" "rzig build: tier 1" ||
      { cat "$sy/install.log" >&2; echo "error: syncw did not build through rzig build (no 'rzig build: tier 1' line)" >&2; exit 1; }
    sy_dll="$(find "$sy/lib/syncw/libs" -name syncw.dll | head -1)"
    needed_of "$sy_dll" | grep -qix 'api-ms-win-core-synch-l1-2-0\.dll' ||
      { needed_of "$sy_dll" >&2; echo "error: syncw.dll does not import api-ms-win-core-synch-l1-2-0.dll (-lsynchronization)" >&2; exit 1; }
    (cd "$sy" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla \
      -e 'stopifnot(getExportedValue(loadNamespace("syncw", lib.loc = "lib"), "f")() == 8L)') ||
      { echo "error: syncw (-lsynchronization) did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== -lsynchronization: syncw builds through rzig build (tier 1, zig from $pass_what), imports the API set and loads with PATH = bin\\x64 + System32"
  fi
fi

# Packages compiled with the relocated tree (unix). A package compiled
# with this tree (C++, so libc++ is involved on macOS) must record no
# rpath at all, and still load: libR and the libraries it needs are
# already in the process. rzig makes that so (on macOS its
# deployment-target triple records no rpath for -L directories), and adds
# an rpath only into a conda env, which this tree is not
# (zigbuild/tools/rzig/environment.zig). That every rpath of the tree's
# own binaries is relative is verify-tree.sh's. Skipped without zig, as on
# a user machine.
if [ "$OS" != windows ]; then
  # What a compile needs under env -i, as on a user machine: the pass's
  # zig (TC/zig's, or ZIG_BIN's through zig_env), TC/flang (phase 6), and
  # make from PATH, its own directory (the env's bin). Every env -i that
  # compiles takes $pkg_path and zig_env. The env's make, not the build-tools group's, which is
  # not extracted yet: PLAN.md's Verification has scenario 2 use the
  # host's make from /usr/bin, and any make that is not the group's
  # stands in for it (PHASE3 C17); the env's is on every machine this
  # runs on, where a host may have none (CI's containers) or Apple's 3.81
  # (omicron). Scenario 3 checks the group's.
  pkg_path="$(dirname "$(command -v make 2>/dev/null || echo /nonexistent/make)"):/usr/bin:/bin"
  if [ -n "$pass_zig" ] && [ -x "$pass_zig" ]; then
    pkg_dir="$VERIFY_DIR/shlib"
    mkdir -p "$pkg_dir"
    # The compiles below run with $pkg_path, whose first entry is the
    # env's bin, where conda-forge's zig is (every leg's default env, the
    # upstream legs' too), and the env's flang with its flang.cfg, so the
    # toolchain pass's compiles have a zig and a flang on PATH that are
    # not the pass's. The dry runs above, under /usr/bin:/bin, cannot see
    # that; these, under $pkg_path, check that the compiles below still
    # run the pass's zig (find_zig's order: ZIG_BIN, then TC/zig, before
    # PATH; B4) and TC/flang (flang_rt.zig's order: TC/flang before
    # PATH): each command's first word, after the ZIG_LIB_DIR= line.
    rz="$(cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" RZIG_PRINT_ARGV=1 \
      "$cc" -c a.c | grep -v '^ZIG_LIB_DIR=' | sed -n 1p)" || true
    [ "$rz" = "$pass_zig" ] ||
      { echo "error: with the env's bin on PATH (conda-forge's zig there), the bundle's ${cc##*/} runs '$rz', not the $pass pass's zig $pass_zig" >&2; exit 1; }
    rf="$(cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" RZIG_PRINT_ARGV=1 \
      "$fc" -c a.f90 | grep -v '^ZIG_LIB_DIR=' | sed -n 1p)" || true
    [ "$rf" = "$pass_flang" ] ||
      { echo "error: with the env's bin on PATH (its flang there), the bundle's ${fc##*/} runs '$rf', not TC/flang's $pass_flang" >&2; exit 1; }
    echo "== with the env's bin on PATH too, the bundle's compilers run the $pass pass's zig and TC/flang"
    # The Fortran builds after the first (fl, fcconf, fomp, fompfc) run
    # with no flang on PATH and no .cfg (PLAN.md phase 6): $fc_path holds
    # the env's make alone, linked, then /usr/bin:/bin, as cf's below.
    # fs keeps $pkg_path: a real build with the env's flang and its .cfg
    # first on PATH, which TC/flang must win over (rf above).
    mkdir -p "$pkg_dir/nofl/bin"
    ln -sf "$(command -v make)" "$pkg_dir/nofl/bin/make"
    fc_path="$pkg_dir/nofl/bin:/usr/bin:/bin"

    # Each shape below is built twice: through R CMD SHLIB, which is make
    # here by R_ZIG_PKG_BUILDER=make, the make reference (R CMD SHLIB's
    # default, the path run-time compilation takes: Rcpp's sourceCpp,
    # inline, is rzig build since patch 0013's one hook,
    # feat-shlib-rzig-build), and as a package through R CMD INSTALL,
    # which builds these shapes through rzig build (patch 0013, the
    # default builder; feat-zig-pkg-build N1), with the same checks on
    # both libraries. shape_pkg <name> <source>... [-- <Makevars
    # line>...] makes the package (useDynLib, no R code) under
    # $shapes/<name>, installs it with the SHLIB runs' env -i
    # (PATH $shape_path, $pkg_path unless set; shape_env adds variables)
    # plus RZIG_TRACE=1, requires `rzig build: tier 1` in its log and no
    # recipe make echoed, and sets shape_so to its library. RZIG_KEEP_ROOT=1
    # keeps rzig build's build root, src/.rzig, whose obj/ holds the
    # objects it compiled (and no zig build cache: tier 1 runs no zig
    # build, tier1.zig): each source's object is
    # there and at or below the macOS floor, which only the objects show
    # for a compiler that ignored it (the SHLIB runs check theirs)
    # [tests-T8]; then the root goes, as rzig build removes it.
    # shape_load <name> <R code> loads the installed package with
    # PATH=/usr/bin:/bin.
    shapes="$pkg_dir/pkgs"
    mkdir -p "$shapes/lib"
    shape_path=""
    shape_env=()
    shape_pkg() {
      local name="$1" d="$shapes/$1" f o objs=""; shift
      rm -rf "$d"; mkdir -p "$d/src"
      printf 'Package: %s\nVersion: 0.1\nTitle: Verify Bundle\nDescription: A shape R CMD INSTALL builds through rzig build.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$name" > "$d/DESCRIPTION"
      printf 'useDynLib(%s)\n' "$name" > "$d/NAMESPACE"
      while [ $# -gt 0 ] && [ "$1" != -- ]; do
        cp "$1" "$d/src/"; f="${1##*/}"; objs="$objs ${f%.*}.o"; shift
      done
      if [ "${1:-}" = -- ]; then shift; printf '%s\n' "$@" > "$d/src/Makevars"; fi
      (cd "$shapes" && env -i "${base_env[@]}" PATH="${shape_path:-$pkg_path}" "${zig_env[@]}" "${shape_env[@]}" RZIG_TRACE=1 RZIG_KEEP_ROOT=1 \
        "$R_BIN" CMD INSTALL -l lib "$name") > "$shapes/$name.log" 2>&1 ||
        { cat "$shapes/$name.log" >&2; echo "error: R CMD INSTALL of $name (a shape through rzig build) failed" >&2; exit 1; }
      starts_line "$shapes/$name.log" "rzig build: tier 1" ||
        { cat "$shapes/$name.log" >&2; echo "error: R CMD INSTALL of $name did not build through rzig build (no 'rzig build: tier 1')" >&2; exit 1; }
      if [ -n "$(make_recipes "$shapes/$name.log")" ]; then
        cat "$shapes/$name.log" >&2; echo "error: a recipe make echoed in $name's install log" >&2; exit 1
      fi
      test ! -e "$d/src/.rzig/zig-cache" || { echo "error: $name's build root has a zig build cache, $d/src/.rzig/zig-cache: tier 1 runs no zig build" >&2; exit 1; }
      for f in $objs; do
        o="$(find "$d/src/.rzig/obj" -name "$f" 2> /dev/null | head -1 || true)"
        [ -n "$o" ] || { echo "error: no $f in $name's build root, $d/src/.rzig/obj (RZIG_KEEP_ROOT=1)" >&2; exit 1; }
        check_minos "$o"
      done
      rm -rf "$d/src/.rzig"
      shape_so="$shapes/lib/$name/libs/$name.so"
      test -f "$shape_so" || { echo "error: no $shape_so after the install of $name" >&2; exit 1; }
    }
    shape_load() {
      (cd "$shapes" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$R_BIN" --vanilla --no-echo -e "loadNamespace('$1', lib.loc = 'lib'); $2") ||
        { echo "error: $1, built through rzig build, did not load or run" >&2; exit 1; }
    }
    cat > "$pkg_dir/rp.cpp" <<'CPP'
#include <R.h>
#include <Rinternals.h>
#include <stdexcept>
#include <string>
extern "C" SEXP rp(void)
{
    std::string s("r-zig");
    try { throw std::runtime_error("!"); } catch (const std::exception &e) { s += e.what(); }
    return ScalarInteger((int) s.size());
}
CPP
    (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
      "$R_BIN" CMD SHLIB -o rp.so rp.cpp > shlib.log 2>&1) || { cat "$pkg_dir/shlib.log" >&2; echo "error: R CMD SHLIB failed with the bundle" >&2; exit 1; }
    pkg_rp="$(rpaths_of "$pkg_dir/rp.so" | tr '\n' ' ')"
    if [ -n "$pkg_rp" ]; then
      echo "error: a package compiled with the bundle records rpaths: $pkg_rp" >&2
      exit 1
    fi
    # zig's own libc++ is static, and rzig keeps it so where conda-forge
    # zig would pick a shared one (zigbuild/tools/rzig/libcxx_mirror.zig).
    check_minos "$pkg_dir/rp.o" "$pkg_dir/rp.so"
    cxx_dep="$(cxx_deps "$pkg_dir/rp.so")"
    if [ -n "$cxx_dep" ]; then
      echo "error: a C++ package compiled with the bundle needs a shared C++ runtime: $cxx_dep" >&2
      exit 1
    fi
    (cd "$pkg_dir" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
      "$R_BIN" --vanilla --no-echo -e 'dyn.load("rp.so"); stopifnot(.Call("rp") == 6L)')
    echo "== compiled package verified: no rpath, static libc++, loads (C++; R CMD SHLIB, make)"
    shape_pkg rp "$pkg_dir/rp.cpp"
    pkg_rp="$(rpaths_of "$shape_so" | tr '\n' ' ')"
    [ -z "$pkg_rp" ] || { echo "error: the rp package built through rzig build records rpaths: $pkg_rp" >&2; exit 1; }
    check_minos "$shape_so"
    cxx_dep="$(cxx_deps "$shape_so")"
    [ -z "$cxx_dep" ] || { echo "error: the rp package built through rzig build needs a shared C++ runtime: $cxx_dep" >&2; exit 1; }
    shape_load rp 'stopifnot(.Call("rp", PACKAGE = "rp") == 6L)'
    echo "== compiled package verified: no rpath, static libc++, loads (C++; R CMD INSTALL, rzig build)"

    # Fortran: FLIBS names the static flang runtime (build.zig), so a
    # Fortran package needs no shared runtime and no rpath into the build
    # env. Checked here, on the relocated tree, because the contract suite
    # runs before staging, while libR still carries build-env rpaths that
    # hid the shared runtime once (2026-09-30, macOS slim). A Makeconf
    # whose FLIBS names no flang runtime skips it.
    if grep -q '^FLIBS = .*flang_rt' "$mk"; then
      # fw needs the runtime (internal formatted I/O: _FortranAio*), so a
      # dropped -lflang_rt.runtime fails the dyn.load; fsum alone would not.
      cat > "$pkg_dir/fs.f" <<'FORTRAN'
      subroutine fsum(n, x, s)
      integer n, i
      double precision x(n), s
      s = 0d0
      do 10 i = 1, n
         s = s + x(i)
   10 continue
      end
      subroutine fw(n, r)
      integer n, r
      character(len=12) buf
      write(buf,'(i0)') n
      read(buf,'(i12)') r
      end
FORTRAN
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
        "$R_BIN" CMD SHLIB -o fs.so fs.f > fshlib.log 2>&1) || { cat "$pkg_dir/fshlib.log" >&2; echo "error: R CMD SHLIB of a Fortran file failed with the bundle" >&2; exit 1; }
      check_minos "$pkg_dir/fs.o" "$pkg_dir/fs.so"
      f_dep="$(needed_of "$pkg_dir/fs.so" | grep flang_rt || true)"
      if [ -n "$f_dep" ]; then
        echo "error: a Fortran package compiled with the bundle needs a shared flang runtime: $f_dep" >&2
        exit 1
      fi
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("fs.so"); stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0)$s == 6, .Fortran("fw", 42L, r = 0L)$r == 42L)')
      echo "== compiled package verified: static flang runtime, loads (Fortran; R CMD SHLIB, make)"
      shape_pkg fs "$pkg_dir/fs.f"
      check_minos "$shape_so"
      f_dep="$(needed_of "$shape_so" | grep flang_rt || true)"
      [ -z "$f_dep" ] || { echo "error: the fs package built through rzig build needs a shared flang runtime: $f_dep" >&2; exit 1; }
      shape_load fs 'stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0, PACKAGE = "fs")$s == 6, .Fortran("fw", 42L, r = 0L, PACKAGE = "fs")$r == 42L)'
      echo "== compiled package verified: static flang runtime, loads (Fortran; R CMD INSTALL, rzig build)"

      # USE_FC_TO_LINK (F3c): R links with SHLIB_FCLD = $(FC), rzig's
      # zig-fc, and takes $(FLIBS) off the line. zig-fc links objects
      # through zig, as zig-cc does, with TC/flang's static runtime
      # (flang's own driver: "cannot find -lflang_rt.runtime"): no
      # shared runtime, no rpath, the macOS floor, and it loads.
      mkdir -p "$pkg_dir/fl"
      cp "$pkg_dir/fs.f" "$pkg_dir/fl/fl.f"
      echo 'USE_FC_TO_LINK =' > "$pkg_dir/fl/Makevars"
      (cd "$pkg_dir/fl" && env -i "${base_env[@]}" PATH="$fc_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
        "$R_BIN" CMD SHLIB -o fl.so fl.f > shlib.log 2>&1) || { cat "$pkg_dir/fl/shlib.log" >&2; echo "error: a USE_FC_TO_LINK Fortran package failed to link with the bundle" >&2; exit 1; }
      grep -Eq 'toolchain/zig-fc (-shared|-dynamiclib) .*-o fl\.so' "$pkg_dir/fl/shlib.log" || { cat "$pkg_dir/fl/shlib.log" >&2; echo "error: the USE_FC_TO_LINK link did not run zig-fc" >&2; exit 1; }
      check_minos "$pkg_dir/fl/fl.o" "$pkg_dir/fl/fl.so"
      f_dep="$(needed_of "$pkg_dir/fl/fl.so" | grep flang_rt || true)"
      fl_rp="$(rpaths_of "$pkg_dir/fl/fl.so" | tr '\n' ' ')"
      if [ -n "$f_dep" ] || [ -n "$fl_rp" ]; then
        echo "error: the USE_FC_TO_LINK package needs a shared flang runtime ($f_dep) or records rpaths ($fl_rp)" >&2
        exit 1
      fi
      (cd "$pkg_dir/fl" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("fl.so"); stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0)$s == 6, .Fortran("fw", 42L, r = 0L)$r == 42L)')
      echo "== compiled package verified: USE_FC_TO_LINK links through zig-fc, static flang runtime, no rpath, loads (Fortran; R CMD SHLIB, make)"
      shape_path="$fc_path"
      shape_pkg fl "$pkg_dir/fl/fl.f" -- 'USE_FC_TO_LINK ='
      shape_path=""
      # the link rzig ran (RZIG_TRACE: `zig-fc: <zig> cc ... -o <out>/fl.so`)
      grep -Eq '^zig-fc: .* -o [^ ]*fl\.so' "$shapes/fl.log" || { cat "$shapes/fl.log" >&2; echo "error: the USE_FC_TO_LINK package's link through rzig build did not run zig-fc" >&2; exit 1; }
      check_minos "$shape_so"
      f_dep="$(needed_of "$shape_so" | grep flang_rt || true)"
      fl_rp="$(rpaths_of "$shape_so" | tr '\n' ' ')"
      if [ -n "$f_dep" ] || [ -n "$fl_rp" ]; then
        echo "error: the fl package built through rzig build needs a shared flang runtime ($f_dep) or records rpaths ($fl_rp)" >&2
        exit 1
      fi
      shape_load fl 'stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0, PACKAGE = "fl")$s == 6, .Fortran("fw", 42L, r = 0L, PACKAGE = "fl")$r == 42L)'
      echo "== compiled package verified: USE_FC_TO_LINK links through zig-fc, static flang runtime, no rpath, loads (Fortran; R CMD INSTALL, rzig build)"
    fi

    # A configure script that runs $FC as autoconf's Fortran checks do
    # (fcconf_pkg: compile, link and run a program, then link with -v),
    # in a package R CMD INSTALL builds with the env's make (a configure
    # script R runs needs make); it loads with nothing but the tree.
    fcconf_pkg "$shapes"
    (cd "$shapes" && env -i "${base_env[@]}" PATH="$fc_path" "${zig_env[@]}" \
      "$R_BIN" CMD INSTALL -l lib fcconf) > "$shapes/fcconf.log" 2>&1 ||
      { cat "$shapes/fcconf.log" >&2; echo "error: fcconf (a configure script that compiles, links and runs a program with \$FC) did not install" >&2; exit 1; }
    grep -q '^fcconf: .*/zig-fc compiles, links and runs a program$' "$shapes/fcconf.log" ||
      { cat "$shapes/fcconf.log" >&2; echo "error: fcconf's configure did not say that \$FC compiles, links and runs a program" >&2; exit 1; }
    shape_load fcconf 'stopifnot(getExportedValue(asNamespace("fcconf"), "f")() == 5L)'
    echo "== a configure script with \$FC: fcconf's configure compiles, links and runs a program with zig-fc (TC/flang, zig), links with -v; the package installs and loads"

    # The no-flang checks below move TC/flang's driver aside (open point
    # N a) and put it back after them.
    flang_aside

    # FC names zig-fc whether or not a flang is installed: with none (not
    # in the toolchain's flang/, the tree's bin or PATH), a Fortran compile
    # stops at once with exit 127 and the compilers group's text, which
    # names flang (feat-standalone-toolchain B35; rzig never reads
    # R_ZIG_TOOLCHAIN_HINT). A host's own flang in /usr/bin or /bin is one
    # rzig rightly finds: then this is skipped.
    if ! [ -x /usr/bin/flang ] && ! [ -x /bin/flang ]; then
      printf '      end\n' > "$pkg_dir/nofc.f"
      rc=0
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$fc" -c nofc.f -o nofc.o > nofc.log 2>&1) || rc=$?
      if [ "$rc" != 127 ] || ! grep -q '^zig-fc: no flang (' "$pkg_dir/nofc.log" ||
        ! grep -q '^Compiling needs the r-zig compilers for R ' "$pkg_dir/nofc.log"; then
        cat "$pkg_dir/nofc.log" >&2
        echo "error: zig-fc with no flang: exit $rc, or not the compilers group's text naming flang" >&2
        exit 1
      fi
      echo "== zig-fc with no flang: exit 127, '$(head -1 "$pkg_dir/nofc.log")'"
    fi

    # $(FLIBS) on a C package's link (CRAN's usual PKG_LIBS = $(LAPACK_LIBS)
    # $(BLAS_LIBS) $(FLIBS)) with no flang (TC/flang's driver aside, none
    # on PATH), as with the wheel: the
    # compilers (rzig) drop -lflang_rt.runtime: nothing was compiled by flang.
    # PATH: the env's make alone (above: the group's comes in scenario 3), no flang.
    mkdir -p "$pkg_dir/cf/bin"
    ln -sf "$(command -v make)" "$pkg_dir/cf/bin/make"
    printf '%s\n' '#include <R.h>' 'void cfl(int *n) { *n = 7; }' > "$pkg_dir/cf/cf.c"
    printf '%s\n' 'PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)' > "$pkg_dir/cf/Makevars"
    (cd "$pkg_dir/cf" && env -i "${base_env[@]}" PATH="$pkg_dir/cf/bin:/usr/bin:/bin" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
      "$R_BIN" CMD SHLIB -o cf.so cf.c > shlib.log 2>&1) || { cat "$pkg_dir/cf/shlib.log" >&2; echo "error: a C package using \$(FLIBS) failed to link with no flang on PATH" >&2; exit 1; }
    (cd "$pkg_dir/cf" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
      "$R_BIN" --vanilla --no-echo -e 'dyn.load("cf.so"); stopifnot(.C("cfl", n = 0L)$n == 7L)')
    echo "== compiled package verified: \$(FLIBS) links with no Fortran compiler (C; R CMD SHLIB, make)"
    # as a package: no flang and no make on PATH at all, the tree's bin
    # alone, as pfC's install (/usr/bin has the host's make on most
    # machines) [phase3-P3-3]
    shape_path="$BUNDLE_DIR/bin"
    shape_pkg cf "$pkg_dir/cf/cf.c" -- 'PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)'
    shape_path=""
    shape_load cf 'stopifnot(.C("cfl", n = 0L, PACKAGE = "cf")$n == 7L)'
    echo "== compiled package verified: \$(FLIBS) links with no Fortran compiler (C; R CMD INSTALL, rzig build, PATH the tree's bin alone: no flang, no make)"
    flang_back

    # OpenMP's compile-time files are the compilers group's openmp/
    # (feat-standalone-toolchain B22), which rzig counts as one more
    # environment where the base has the libomp runtime it is for (B40):
    # where Makeconf offers OpenMP (slim, full), every compile gets
    # -I<R_HOME>/bin/toolchain/openmp/include, at rzig's own resolved
    # path. minimal has no libomp, so openmp/ is there but never used: no
    # -I into it, and a flagless #include <omp.h> (data.table's probe)
    # finds no header, as minimal's empty SHLIB_OPENMP_* say, rather than
    # one whose -lomp link would fail.
    omp_inc="$(cd "$TC" && pwd -P)/openmp/include"
    [ -f "$omp_inc/omp.h" ] || { echo "error: no omp.h in $omp_inc: the compilers archive holds openmp/ (B22)" >&2; exit 1; }
    argv="$(cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" RZIG_PRINT_ARGV=1 "$cc" -fopenmp -c a.c)"
    if grep -q '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
      printf '%s\n' "$argv" | grep -qxF -- "-I$omp_inc" ||
        { printf '%s\n' "$argv" >&2; echo "error: a -fopenmp compile lacks -I$omp_inc, the compilers group's OpenMP headers (B40: the base has libomp)" >&2; exit 1; }
      echo "== OpenMP headers from the compilers group: -I<R_HOME>/bin/toolchain/openmp/include"
    else
      if printf '%s\n' "$argv" | grep -q 'toolchain/openmp'; then
        printf '%s\n' "$argv" >&2
        echo "error: $FLAVOR offers no OpenMP, but a -fopenmp compile gets the compilers group's openmp/ (B40: only with the base's libomp)" >&2
        exit 1
      fi
      printf '%s\n' '#include <omp.h>' 'int ompprobe(void) { return 0; }' > "$pkg_dir/nomp.c"
      if (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" "$cc" -c nomp.c -o nomp.o) > "$pkg_dir/nomp.log" 2>&1; then
        echo "error: $FLAVOR offers no OpenMP, but a flagless #include <omp.h> compiled (B40)" >&2
        exit 1
      fi
      grep -q 'omp\.h' "$pkg_dir/nomp.log" ||
        { cat "$pkg_dir/nomp.log" >&2; echo "error: the flagless #include <omp.h> failed, but not for want of omp.h" >&2; exit 1; }
      echo "== $FLAVOR: the compilers group's openmp/ is there and unused (B40): no -I into it, a flagless #include <omp.h> finds no header"
    fi

    # OpenMP (slim, full): omp.h from the compilers group's openmp/ and the
    # base's vendored libomp, no rpath, nothing from the build env.
    # Makeconf's CPPFLAGS and LDFLAGS are empty (F3b), so these build only
    # through the -I and -L rzig adds. Three ways packages ask: R's
    # SHLIB_OPENMP_CFLAGS, data.table's configure probe (omp.h included
    # with no OpenMP flag), and PKG_LIBS = -lomp with no -fopenmp at all
    # (libomp found through rzig's -L alone). Each package must link
    # libomp itself: libR has it loaded already and a shared link may leave
    # symbols undefined (macOS Makeconf: -undefined dynamic_lookup), so one
    # whose -lomp went missing would still load.
    if grep -q '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
      mkdir -p "$pkg_dir/omp" "$pkg_dir/lomp"
      printf '%s\n' '#include <omp.h>' '#include <R.h>' 'void ompn(int *n) { *n = omp_get_max_threads(); }' > "$pkg_dir/omp/omp.c"
      printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$pkg_dir/omp/Makevars"
      printf '%s\n' '#include <omp.h>' 'int ompprobe(void) { return 0; }' > "$pkg_dir/omp/probe.c"
      printf '%s\n' 'extern int omp_get_max_threads(void);' 'void lompn(int *n) { *n = omp_get_max_threads(); }' > "$pkg_dir/lomp/lomp.c"
      printf '%s\n' 'PKG_LIBS = -lomp' > "$pkg_dir/lomp/Makevars"
      (cd "$pkg_dir/omp" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
        "$R_BIN" CMD SHLIB -o omp.so omp.c > shlib.log 2>&1 && rm Makevars &&
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
        "$R_BIN" CMD SHLIB -o probe.so probe.c >> shlib.log 2>&1 && cd "$pkg_dir/lomp" &&
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
        "$R_BIN" CMD SHLIB -o lomp.so lomp.c >> "$pkg_dir/omp/shlib.log" 2>&1) || { cat "$pkg_dir/omp/shlib.log" >&2; echo "error: an OpenMP package failed to build with the bundle" >&2; exit 1; }
      check_minos "$pkg_dir/omp/omp.so" "$pkg_dir/lomp/lomp.so"
      omp_rp="$(rpaths_of "$pkg_dir/omp/omp.so" | tr '\n' ' ')$(rpaths_of "$pkg_dir/lomp/lomp.so" | tr '\n' ' ')"
      if [ -n "$omp_rp" ]; then
        echo "error: an OpenMP package compiled with the bundle records rpaths: $omp_rp" >&2
        exit 1
      fi
      for so in "$pkg_dir/omp/omp.so" "$pkg_dir/lomp/lomp.so"; do
        needed_of "$so" | grep -q 'libomp\.' || { needed_of "$so" >&2; echo "error: ${so##*/} does not link libomp" >&2; exit 1; }
      done
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("omp/omp.so"); dyn.load("lomp/lomp.so"); stopifnot(.C("ompn", n = 0L)$n >= 1L, .C("lompn", n = 0L)$n >= 1L)')
      echo "== compiled package verified: OpenMP from the compilers group's omp.h and the base's libomp through rzig's -I/-L (SHLIB_OPENMP_CFLAGS, a flagless omp.h probe, PKG_LIBS = -lomp), links libomp, no rpath, loads (R CMD SHLIB, make)"
      shape_pkg omp "$pkg_dir/omp/omp.c" -- 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)'
      omp_pkg_so="$shape_so"
      shape_pkg lomp "$pkg_dir/lomp/lomp.c" -- 'PKG_LIBS = -lomp'
      check_minos "$omp_pkg_so" "$shape_so"
      omp_rp="$(rpaths_of "$omp_pkg_so" | tr '\n' ' ')$(rpaths_of "$shape_so" | tr '\n' ' ')"
      [ -z "$omp_rp" ] || { echo "error: an OpenMP package built through rzig build records rpaths: $omp_rp" >&2; exit 1; }
      for so in "$omp_pkg_so" "$shape_so"; do
        needed_of "$so" | grep -q 'libomp\.' || { needed_of "$so" >&2; echo "error: ${so##*/} (rzig build) does not link libomp" >&2; exit 1; }
      done
      shape_load omp 'loadNamespace("lomp", lib.loc = "lib"); stopifnot(.C("ompn", n = 0L, PACKAGE = "omp")$n >= 1L, .C("lompn", n = 0L, PACKAGE = "lomp")$n >= 1L)'
      echo "== compiled package verified: OpenMP (SHLIB_OPENMP_CFLAGS, PKG_LIBS = -lomp) links libomp, no rpath, loads (R CMD INSTALL, rzig build)"
    fi

    # Fortran OpenMP, wherever Makeconf offers it (slim, full): `use
    # omp_lib` compiles against TC/flang's omp_lib.mod (flang-rt-zig's,
    # LLVM 23, the release of the llvm-openmp pixi.toml pins; zig-fc's
    # modules flag), and the package links the tree's libomp through rzig, as the C
    # one does (and, as there, must record it itself). R-exts' two forms:
    # $(SHLIB_OPENMP_FFLAGS) on the compile and $(SHLIB_OPENMP_CFLAGS) on
    # the link, which the C compiler does (fomp); and USE_FC_TO_LINK with
    # $(SHLIB_OPENMP_FFLAGS) on both, zig-fc linking (fompfc). FOMP_R
    # checks that a parallel region ran on two of libomp's threads; the
    # load runs with /usr/bin:/bin.
    # Where Makeconf offers none (minimal, B40), B40's Fortran limit
    # instead (PHASE6 open point U, Cg1): omp_lib.mod is in TC/flang's one
    # module directory, so `use omp_lib` compiles, and a program's link
    # with -fopenmp fails on an undefined omp_ or __kmpc_ symbol, there
    # being no libomp in the base (no new rzig message: the link's own
    # error is the record).
    if grep -q '^SHLIB_OPENMP_FFLAGS = *-' "$mk"; then
      fomp_src "$pkg_dir"
      for d in fomp fompfc; do
        (cd "$pkg_dir/$d" && env -i "${base_env[@]}" PATH="$fc_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make \
          "$R_BIN" CMD SHLIB -o "$d.so" "$d.f" > shlib.log 2>&1) || { cat "$pkg_dir/$d/shlib.log" >&2; echo "error: the Fortran OpenMP package $d failed to build with the bundle" >&2; exit 1; }
        check_minos "$pkg_dir/$d/$d.o" "$pkg_dir/$d/$d.so"
        f_dep="$(needed_of "$pkg_dir/$d/$d.so" | grep flang_rt || true)"
        d_rp="$(rpaths_of "$pkg_dir/$d/$d.so" | tr '\n' ' ')"
        if [ -n "$f_dep" ] || [ -n "$d_rp" ]; then
          echo "error: the Fortran OpenMP package $d needs a shared flang runtime ($f_dep) or records rpaths ($d_rp)" >&2
          exit 1
        fi
        needed_of "$pkg_dir/$d/$d.so" | grep -q 'libomp\.' || { needed_of "$pkg_dir/$d/$d.so" >&2; echo "error: the Fortran OpenMP package $d does not link libomp" >&2; exit 1; }
      done
      grep -Eq 'toolchain/zig-fc (-shared|-dynamiclib) .*-o fompfc\.so' "$pkg_dir/fompfc/shlib.log" || { cat "$pkg_dir/fompfc/shlib.log" >&2; echo "error: the USE_FC_TO_LINK link of fompfc did not run zig-fc" >&2; exit 1; }
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
        "$R_BIN" --vanilla --no-echo -e "$FOMP_R")
      echo "== compiled package verified: Fortran OpenMP (use omp_lib, a parallel region on two threads; SHLIB_OPENMP_FFLAGS, linked by the C compiler and by zig-fc) links the tree's libomp, no rpath, loads (R CMD SHLIB, make)"
      shape_path="$fc_path"
      shape_pkg fomp "$pkg_dir/fomp/fomp.f" -- 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)'
      fomp_pkg_so="$shape_so"
      shape_pkg fompfc "$pkg_dir/fompfc/fompfc.f" -- 'USE_FC_TO_LINK =' 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_FFLAGS)'
      shape_path=""
      grep -Eq '^zig-fc: .* -o [^ ]*fompfc\.so' "$shapes/fompfc.log" || { cat "$shapes/fompfc.log" >&2; echo "error: the USE_FC_TO_LINK link of the fompfc package through rzig build did not run zig-fc" >&2; exit 1; }
      for so in "$fomp_pkg_so" "$shape_so"; do
        check_minos "$so"
        f_dep="$(needed_of "$so" | grep flang_rt || true)"
        d_rp="$(rpaths_of "$so" | tr '\n' ' ')"
        if [ -n "$f_dep" ] || [ -n "$d_rp" ]; then
          echo "error: the Fortran OpenMP package ${so##*/} (rzig build) needs a shared flang runtime ($f_dep) or records rpaths ($d_rp)" >&2
          exit 1
        fi
        needed_of "$so" | grep -q 'libomp\.' || { needed_of "$so" >&2; echo "error: the Fortran OpenMP package ${so##*/} (rzig build) does not link libomp" >&2; exit 1; }
      done
      shape_load fomp 'loadNamespace("fompfc", lib.loc = "lib"); for (d in c("fomp", "fompfc")) { r <- .Fortran("fompn", n = 0L, t = 0L, s = 0L, PACKAGE = d); stopifnot(r$n >= 1L, r$t == 2L, r$s == 5050L); cat(d, ": omp_get_max_threads() =", r$n, "; a num_threads(2) region ran on", r$t, "threads\n") }'
      echo "== compiled package verified: Fortran OpenMP, linked by the C compiler and by zig-fc, links the tree's libomp, no rpath, loads (R CMD INSTALL, rzig build)"
    else
      printf '%s\n' 'program ompf' '  use omp_lib' '  implicit none' '  print *, omp_get_max_threads()' 'end program ompf' > "$pkg_dir/ompf.f90"
      (cd "$pkg_dir" && env -i "${base_env[@]}" "${zig_env[@]}" PATH=/usr/bin:/bin "$fc" -fopenmp -c ompf.f90 -o ompf.o) > "$pkg_dir/ompf.log" 2>&1 ||
        { cat "$pkg_dir/ompf.log" >&2; echo "error: $FLAVOR: \$FC -fopenmp -c of a 'use omp_lib' program failed: omp_lib.mod is in TC/flang's module directory on every flavor (B40, open point U)" >&2; exit 1; }
      rc=0
      (cd "$pkg_dir" && env -i "${base_env[@]}" "${zig_env[@]}" PATH=/usr/bin:/bin "$fc" -fopenmp -o ompf ompf.f90) > "$pkg_dir/ompf.log" 2>&1 || rc=$?
      if [ "$rc" = 0 ] || ! grep -Eq 'undefined.*(omp_|__kmpc_)' "$pkg_dir/ompf.log"; then
        cat "$pkg_dir/ompf.log" >&2
        echo "error: $FLAVOR offers no OpenMP, but \$FC -fopenmp -o ompf ompf.f90 (use omp_lib) exited $rc without naming an undefined omp_ or __kmpc_ symbol (B40's Fortran limit, open point U)" >&2
        exit 1
      fi
      echo "== B40's Fortran limit: use omp_lib compiles, the link fails without libomp (as decided): $(grep -Em1 'undefined.*(omp_|__kmpc_)' "$pkg_dir/ompf.log")"
    fi

    # rzig never reads CONDA_PREFIX (F3b): an activated env R is not
    # installed in adds nothing. Two decoys: the env this check runs in
    # (real headers and libraries, a conda-meta) and a poisoned one
    # (#error in omp.h and zlib.h, junk libraries). The C++ package, and the
    # OpenMP one where the tree has OpenMP, rebuild with each as
    # CONDA_PREFIX, through make and through rzig build (the OpenMP one
    # includes omp.h, so an -I into the decoy fails its compile)
    # [tests-T8]: no rpath, and rzig's command lines name neither.
    decoy="$VERIFY_DIR/decoy"
    mkdir -p "$decoy/conda-meta" "$decoy/include" "$decoy/lib"
    printf '#error decoy CONDA_PREFIX\n' > "$decoy/include/omp.h"; cp "$decoy/include/omp.h" "$decoy/include/zlib.h"
    printf 'junk' > "$decoy/lib/libomp.so"; cp "$decoy/lib/libomp.so" "$decoy/lib/libz.so"
    for cpfx in "$decoy" ${CONDA_PREFIX:+"$CONDA_PREFIX"}; do
      rm -f "$pkg_dir/rp.so" "$pkg_dir/rp.o" "$pkg_dir/omp/omp.so" "$pkg_dir/omp/omp.o"
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make CONDA_PREFIX="$cpfx" \
        "$R_BIN" CMD SHLIB -o rp.so rp.cpp > decoy.log 2>&1) || { cat "$pkg_dir/decoy.log" >&2; echo "error: R CMD SHLIB failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
      sos="$pkg_dir/rp.so"
      if [ -f "$pkg_dir/omp/omp.c" ]; then
        printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$pkg_dir/omp/Makevars"
        (cd "$pkg_dir/omp" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make CONDA_PREFIX="$cpfx" \
          "$R_BIN" CMD SHLIB -o omp.so omp.c > decoy.log 2>&1) || { cat "$pkg_dir/omp/decoy.log" >&2; echo "error: the OpenMP package failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
        sos="$sos $pkg_dir/omp/omp.so"
      fi
      # the C++ package, and the OpenMP one, through rzig build as well
      shape_env=(CONDA_PREFIX="$cpfx")
      shape_pkg rp "$pkg_dir/rp.cpp"
      sos="$sos $shape_so"
      if [ -f "$pkg_dir/omp/omp.c" ]; then
        shape_pkg omp "$pkg_dir/omp/omp.c" -- 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)'
        sos="$sos $shape_so"
      fi
      shape_env=()
      for so in $sos; do
        so_rp="$(rpaths_of "$so" | tr '\n' ' ')"
        [ -z "$so_rp" ] || { echo "error: ${so##*/} built with CONDA_PREFIX=$cpfx records rpaths: $so_rp" >&2; exit 1; }
      done
      # (zig itself, and its lib dir, may live in the build env)
      argv="$(cd "$pkg_dir" && for a in "-fopenmp -c a.c" "-shared -fopenmp -o x.so a.o -lz" "-o conftest conftest.c -lz"; do
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" CONDA_PREFIX="$cpfx" RZIG_PRINT_ARGV=1 "$cc" $a; done |
        grep -vxF -- "$pass_zig" | grep -v '^ZIG_LIB_DIR=')"
      if printf '%s\n' "$argv" | grep -F -- "$cpfx"; then
        echo "error: rzig's command lines name CONDA_PREFIX=$cpfx" >&2; exit 1
      fi
      printf '%s\n' "$argv" | grep -qxF -- "-L$(cd "$BUNDLE_DIR" && pwd -P)/lib" || { printf '%s\n' "$argv" >&2; echo "error: rzig's link lines lack the tree's -L" >&2; exit 1; }
    done
    echo "== CONDA_PREFIX ignored: the C++ package and, where offered, the OpenMP one (each through make and through rzig build) build with a poisoned and with the build env as CONDA_PREFIX, no rpath, and rzig's command lines name neither"
  else
    echo "== compiled-package checks skipped (no zig: ZIG_BIN unset, none on PATH)"
  fi
fi

# btMany (feat-win-link-fixes item 1): a package of 300 C sources with
# 96-character names, one that sums their functions and mkpkg's f.c (302
# objects), through rzig
# build (tier 1, no make), on every OS. Its objects' absolute names make
# more than 32,767 characters, where a Windows command line ends: `rzig
# def` and the link named them all and stopped with NameTooLong before
# (libgeos with its unix Makevars, about 390 objects). Now the link reads
# them from the build root's objects.rsp (tier1.zig), itself over 32,767
# bytes, and the .def is written in process (def.zig), with no command
# line. Kept root (RZIG_KEEP_ROOT=1): objects.rsp and the objects' names
# measured; f() is the sum, 44850, and each of the 300 functions is in
# the library's exports (on Windows the .def named them).
if [ -n "$pass_zig" ]; then
  bm="$VERIFY_DIR/btmany"
  rm -rf "$bm"; mkdir -p "$bm/lib"
  mkpkg "$bm/pk" btMany 0
  bms="$bm/pk/btMany/src"
  rm "$bms/val.c"
  {
    for i in $(seq 0 299); do printf 'int m%03d(void);\n' "$i"; done
    printf 'int btMany_val(void) { return 0'
    for i in $(seq 0 299); do printf ' + m%03d()' "$i"; done
    printf '; }\n'
  } > "$bms/sum.c"
  for i in $(seq 0 299); do
    printf 'int m%03d(void) { return %d; }\n' "$i" "$i" > "$bms/$(printf 'm%03d' "$i")_a_long_source_file_name_standing_in_for_a_vendored_library_with_many_objects_in_deep_dirs.c"
  done
  if [ "$OS" = windows ]; then
    (cd "$bm" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$R_BINDIR:$sys32" RZIG_TRACE=1 RZIG_KEEP_ROOT=1 \
      "$R_EXE" CMD INSTALL -l lib pk/btMany) > "$bm/install.log" 2>&1
  else
    (cd "$bm" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" RZIG_TRACE=1 RZIG_KEEP_ROOT=1 \
      "$R_BIN" CMD INSTALL -l lib pk/btMany) > "$bm/install.log" 2>&1
  fi || { tail -40 "$bm/install.log" >&2; echo "error: btMany (300 objects) did not install through rzig build (zig from $pass_what)" >&2; exit 1; }
  starts_line "$bm/install.log" "rzig build: tier 1" ||
    { tail -40 "$bm/install.log" >&2; echo "error: btMany did not build through rzig build (no 'rzig build: tier 1' line)" >&2; exit 1; }
  bm_rsp="$bms/.rzig/objects.rsp"
  [ -f "$bm_rsp" ] || { echo "error: btMany's build root has no objects.rsp ($bm_rsp, RZIG_KEEP_ROOT=1)" >&2; exit 1; }
  bm_lines="$(grep -c . "$bm_rsp")"
  bm_bytes="$(wc -c < "$bm_rsp" | tr -d ' ')"
  bm_abs="$(find "$bms/.rzig/obj" -name '*.o' | { if [ "$OS" = windows ]; then cygpath -m -f -; else cat; fi; } | awk '{ s += length($0) + 1 } END { print s + 0 }')"
  [ "$bm_lines" = 302 ] && [ "$bm_bytes" -gt 32767 ] && [ "$bm_abs" -gt 32767 ] ||
    { echo "error: btMany: objects.rsp has $bm_lines lines and $bm_bytes bytes, the objects' absolute names $bm_abs characters (want 302 lines, both over 32,767)" >&2; exit 1; }
  (cd "$bm" && env -i "${base_env[@]}" PATH="$(if [ "$OS" = windows ]; then echo "$R_BINDIR:$sys32"; else echo /usr/bin:/bin; fi)" "$RSCRIPT" --vanilla -e '
    ns <- loadNamespace("btMany", lib.loc = "lib")
    stopifnot(getExportedValue(ns, "f")() == 44850L,
              all(vapply(sprintf("m%03d", 0:299), is.loaded, NA, PACKAGE = "btMany")))') ||
    { echo "error: btMany did not load, f() is not 44850, or a function is not exported" >&2; exit 1; }
  rm -rf "$bms/.rzig"
  echo "== btMany: 302 objects through rzig build (tier 1, zig from $pass_what), named in objects.rsp ($bm_bytes bytes; their absolute names, the command line before, $bm_abs characters); f() = 44850, the 300 functions exported"
fi

# --- Scenario 3: base + compilers + build-tools -----------------------------
extract "${archives[2]}" "$lists/build-tools"
echo "== scenario 3: base + compilers + build-tools"

# The packages built here, from a local repository, under the default
# builder (a deliberate mixed run, feat-zig-pkg-build N1): btA (plain C)
# builds through rzig build (patch 0013), btLib (a static library through
# $(AR) and $(RANLIB), mkpkg's `lib`: a Makevars rule) through the group's
# make, and on Windows btRc, whose OBJECTS hold a .rc file compiled by
# Makeconf's %.o: %.rc rule ($(RESCOMP), the group's windres.exe with
# rzig's gcc.exe as its preprocessor; B24), through make too; each
# asserted from its kept install log (keep_outputs, RZIG_TRACE=1). A
# repository, not repos = NULL: install.packages installs local paths one
# at a time and never reads Ncpus, while from a repository Ncpus = 2 has it
# write a Makefile and run `make -k -j 2` (the make R_HOME/bin/toolchain's
# group provides, on unix), whose recipes run R CMD INSTALL, which runs
# make again for each package that needs it. bt-load.R loads each in an R
# whose PATH has nothing else (unix /usr/bin:/bin; Windows bin\x64 and
# System32).
bt="$VERIFY_DIR/bt"
bt_pkgs="btA btLib"
[ "$OS" != windows ] || bt_pkgs="$bt_pkgs btRc"
mkpkg "$bt/pk" btA 1
mkpkg "$bt/pk" btLib 42 lib
if [ "$OS" = windows ]; then
  mkpkg "$bt/pk" btRc 3
  printf '%s\n' '#include <windows.h>' '1 VERSIONINFO' 'FILEVERSION 0,1,0,0' 'PRODUCTVERSION 0,1,0,0' \
    'FILEOS VOS__WINDOWS32' 'FILETYPE VFT_DLL' 'BEGIN' '  BLOCK "StringFileInfo"' '  BEGIN' '    BLOCK "040904b0"' \
    '    BEGIN' '      VALUE "ProductName", "r-zig\0"' '    END' '  END' 'END' > "$bt/pk/btRc/src/res.rc"
  printf '%s\n' 'OBJECTS = f.o val.o res.o' > "$bt/pk/btRc/src/Makevars.win"
fi
mkdir -p "$bt/repo/src/contrib" "$bt/lib"
for p in $bt_pkgs; do
  tar -czf "$bt/repo/src/contrib/${p}_0.1.tar.gz" -C "$bt/pk" "$p"
  printf 'Package: %s\nVersion: 0.1\n\n' "$p" >> "$bt/repo/src/contrib/PACKAGES"
done
cat > "$bt/bt.R" <<'RCODE'
## verify-bundle.sh, scenario 3: the make R runs is the build-tools
## group's (Sys.which; on unix also its --version, the version its SOURCES
## records, the first argument; on Windows the session finds it through
## base's Rprofile, patch 0014, and verify-toolchain.sh checks its
## version, PHASE7 amendment Am10); then the packages, two at a time.
windows <- .Platform$OS.type == "windows"
make <- Sys.which("make")
group <- file.path(R.home(), "bin", "toolchain", "usr", "bin", if (windows) "make.exe" else "make")
same <- function(a, b) if (windows) tolower(normalizePath(a, "/")) == tolower(normalizePath(b, "/")) else normalizePath(a) == normalizePath(b)
if (!nzchar(make) || !same(make, group))
    stop("Sys.which(\"make\") is '", make, "', not the build-tools group's ", group)
if (!windows) {
    v <- system2("make", "--version", stdout = TRUE)[1L]
    want <- paste("GNU Make", commandArgs(trailingOnly = TRUE)[1L])
    if (!identical(v, want)) stop("make --version says '", v, "', not '", want, "'")
    cat("make:", make, "-", v, "\n")
} else cat("make:", make, "\n")
pkgs <- c("btA", "btLib", if (windows) "btRc")
lib <- normalizePath("lib", "/")
install.packages(pkgs, lib = lib, repos = paste0("file:", normalizePath("repo", "/")),
                 type = "source", Ncpus = 2L, keep_outputs = TRUE)
miss <- setdiff(pkgs, rownames(installed.packages(lib.loc = lib)))
if (length(miss)) stop("not installed: ", paste(miss, collapse = ", "))
## the builder each took (RZIG_TRACE=1 in the environment): btA rzig
## build, the others make, with rzig build's reason
builder <- function(p) {
    log <- readLines(paste0(p, ".out"), warn = FALSE)
    if (any(grepl("rzig build: tier 1", log, fixed = TRUE))) "rzig build"
    else if (any(grepl(paste0("rzig build: ", p, " needs make: "), log, fixed = TRUE))) "make"
    else "unknown"
}
want <- c(btA = "rzig build", btLib = "make", if (windows) c(btRc = "make"))
got <- vapply(names(want), builder, "")
if (!identical(got, want)) stop("builders: ", paste(names(got), got, sep = " = ", collapse = ", "),
                                "; wanted ", paste(names(want), want, sep = " = ", collapse = ", "))
cat("installed with Ncpus = 2:", pkgs, "(", paste(names(got), got, sep = " = ", collapse = ", "), ")\n")
RCODE
cat > "$bt/bt-load.R" <<'RCODE'
lib <- normalizePath("lib", "/")
want <- c(btA = 1L, btLib = 42L, if (.Platform$OS.type == "windows") c(btRc = 3L))
for (p in names(want)) {
    got <- getExportedValue(loadNamespace(p, lib.loc = lib), "f")()
    if (!identical(got, want[[p]])) stop(p, "::f() is ", got, ", not ", want[[p]])
}
cat("loaded:", names(want), "\n")
RCODE

if [ "$OS" != windows ]; then
  # The group's make, at R_HOME/bin/toolchain/usr/bin/make (B23), which
  # etc/Renviron puts first on PATH (B25): rzig's check mode under R CMD
  # finds it there, ahead of any make in /usr/bin (Apple's 3.81 on
  # omicron).
  tc_make="$(cd "$TC" && pwd -P)/usr/bin/make"
  out="$(cd "$VERIFY_DIR" && env -i "${base_env[@]}" PATH=/usr/bin:/bin "$R_BIN" CMD "$cc" --rzig-check=build-tools)" ||
    { echo "error: R CMD ${cc##*/} --rzig-check=build-tools failed with the build-tools group extracted" >&2; exit 1; }
  case "$out" in
    *"build-tools ok: make at $tc_make"*) echo "   $out" ;;
    *) echo "error: R CMD ${cc##*/} --rzig-check=build-tools says '$out', not make at $tc_make" >&2; exit 1 ;;
  esac
  # The version SOURCES records for make (zigbuild/toolchain/build.zig),
  # which make --version must say.
  make_version="$(awk '$1 == "package:" { p = $2 } p == "make" && $1 == "version:" { print $2; exit }' "$TC/usr/SOURCES")"
  [ -n "$make_version" ] || { echo "error: $TC/usr/SOURCES records no version for make" >&2; exit 1; }
  if [ -n "$pass_zig" ] && [ -x "$pass_zig" ]; then
    # On linux, where strace can trace, every make that ran is the
    # group's: no other make answered for it (cannot_check in CI).
    strace_bin=""
    if [ "$OS" = linux ]; then
      if command -v strace > /dev/null 2>&1 && strace -f -qq -e trace=execve -o /dev/null /bin/true 2> /dev/null; then
        strace_bin="$(command -v strace)"
      else
        cannot_check "strace unavailable or cannot trace; which make ran is not checked"
      fi
    fi
    run_bt() {
      (cd "$bt" && "$@" env -i "${base_env[@]}" PATH=/usr/bin:/bin "${zig_env[@]}" RZIG_TRACE=1 \
        "$RSCRIPT" --vanilla bt.R "$make_version") > "$bt/bt.log" 2>&1 ||
        { cat "$bt/bt.log" >&2; echo "error: the packages ($bt_pkgs) did not build (btA through rzig build, btLib through the build-tools group's make)" >&2; exit 1; }
    }
    if [ -n "$strace_bin" ]; then
      run_bt "$strace_bin" -f -qq -e trace=execve -o "$bt/execve.tr"
      # Successful execs only (a failed one is a PATH probe).
      ran="$(grep 'execve(' "$bt/execve.tr" | grep -v '= -1' | grep -o 'execve("[^"]*"' |
        sed 's/^execve("//; s/"$//' | grep -E '/g?make$' | sort -u || true)"
      if [ "$ran" != "$tc_make" ]; then
        echo "error: the make that ran: ${ran:-(none)}; only the build-tools group's $tc_make may" >&2
        exit 1
      fi
    else
      run_bt
    fi
    { grep -E '^(make|installed with)' "$bt/bt.log" || true; } | sed 's/^/   /'
    (cd "$bt" && env -i "${base_env[@]}" PATH=/usr/bin:/bin "$RSCRIPT" --vanilla bt-load.R) ||
      { echo "error: the packages ($bt_pkgs) did not load" >&2; exit 1; }
    echo "== packages built under the default builder, install.packages with Ncpus = 2 through the group's make (GNU Make $make_version${strace_bin:+, the only make that ran}): btA through rzig build, btLib (a static library through \$(AR) and \$(RANLIB): rzig) through make, each from its log; load"
  else
    echo "== package builds skipped (no zig: ZIG_BIN unset, none on PATH)"
  fi
else
  # Windows. sh, make and the rest: the group's usr/bin (phase 7), which
  # R CMD (Rcmd_environ) and an R session (base's Rprofile, patch 0014)
  # put first on PATH: PATH here is bin\x64 and System32 alone, so no
  # tool of the env's (its MSYS, binutils, zig, pkg-config) can stand in
  # for the group's; zig is the pass's (TC/zig's, or ZIG_BIN's in the
  # build pass).
  usr_bin="$TC/usr/bin"
  for t in make sh; do
    [ -f "$usr_bin/$t.exe" ] || { echo "error: no $t.exe in $usr_bin (the build-tools group's usr/bin)" >&2; exit 1; }
  done
  bt_path="$R_BINDIR:$sys32"
  mk_m="$(cygpath -m "$mk")"
  tc_m="$(cygpath -m -l "$TC")"
  lower() { tr '[:upper:]' '[:lower:]'; }
  # Whether rzig's check line ("make at <path>; sh at <path>; binutils at
  # <dir>") names each tool where it should: bt_names <line> <name>=<path>...
  # rzig prints a tool found on PATH in the form R put on PATH, with 8.3
  # short names (RUNNER~1) and .exe, and one beside it in the long form,
  # so a tool compares by its directory (same_dir: long form, case
  # ignored) and its file name, with or without .exe; a directory
  # (binutils) by same_dir alone. Prints what does not match.
  bt_names() {
    local line="$1" item name want got gb wb; shift
    for item in "$@"; do
      name="${item%%=*}"; want="${item#*=}"
      case "$line" in
        *"$name at "*) got="${line#*"$name at "}"; got="${got%%;*}" ;;
        *) echo "no '$name at'"; return 1 ;;
      esac
      if [ -d "$want" ]; then
        same_dir "$got" "$want" || { echo "$name at '$got', not $want"; return 1; }
      else
        gb="$(printf '%s' "${got##*/}" | lower)"; gb="${gb%.exe}"
        wb="$(printf '%s' "${want##*/}" | lower)"; wb="${wb%.exe}"
        [ "$gb" = "$wb" ] && same_dir "${got%/*}" "${want%/*}" ||
          { echo "$name at '$got', not $want"; return 1; }
      fi
    done
  }

  # Every tool path Makeconf.win names under R_HOME/bin/toolchain is a
  # file (B24, B43): make expands each variable Makeconf sets ($(info), no
  # shell), once as Makeconf is read and once with LTO_OPT=-flto on make's
  # command line, which turns on its LTO block (C9). The LTO block's
  # gcc-nm alone names no file: none ships (B43-2). OBJDUMP names objdump
  # without .exe, the file R CMD check takes it for (sotools.R).
  mv="$VERIFY_DIR/makeconf"
  mkdir -p "$mv"
  sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*[:+?]*=.*/\1/p' "$mk" | LC_ALL=C sort -u |
    while IFS= read -r v; do printf '$(info %s=$(%s))\n' "$v" "$v"; done > "$mv/vars.mk"
  printf 'all: ;@:\n' >> "$mv/vars.mk"
  for lto in "" LTO_OPT=-flto; do
    (cd "$mv" && env -i "${base_env[@]}" PATH="$bt_path" "$R_EXE" CMD make -f "$mk_m" -f vars.mk ${lto:+"$lto"} all) > "$mv/vars${lto:+-lto}.out" 2>&1 ||
      { cat "$mv/vars${lto:+-lto}.out" >&2; echo "error: R CMD make could not read $mk${lto:+ with $lto}" >&2; exit 1; }
  done
  missing=""; tools=""
  for f in vars.out vars-lto.out; do
    while IFS= read -r p; do
      case "$p" in */) continue ;; esac   # BINPREF itself: the directory
      u="$(cygpath -u "$p")"
      case "$u" in */binutils/objdump) u="$u.exe" ;; esac
      if [ -f "$u" ]; then
        case " $tools " in *" ${p##*/toolchain/} "*) ;; *) tools="$tools ${p##*/toolchain/}" ;; esac
      elif [ "$f" = vars.out ]; then
        missing="$missing $p"
      elif [ "${p##*/}" != gcc-nm ]; then
        missing="$missing $p (LTO_OPT=-flto)"
      fi
    done < <(tr -d '\r' < "$mv/$f" | grep -oE '[^ "=]*/bin/toolchain/[^ "]*' | LC_ALL=C sort -u)
  done
  if [ -n "$missing" ]; then
    echo "error: Makeconf names tools that are not files:$missing" >&2
    exit 1
  fi
  echo "== Makeconf's tools are files:$tools (and the LTO block's gcc-nm, which does not ship: B43-2)"

  # R CMD config AR, NM and OBJDUMP (R CMD check reads OBJDUMP through it)
  # name those files: rzig's zig-ar.exe, the group's nm.exe and objdump,
  # which is objdump.exe as R CMD check finds it: R CMD config's value
  # with .exe added (sotools.R, read_symbols_from_dll).
  for v in AR:zig-ar.exe NM:binutils/nm.exe OBJDUMP:binutils/objdump; do
    val="$(cd "$VERIFY_DIR" && env -i "${base_env[@]}" PATH="$bt_path" "$R_EXE" CMD config "${v%%:*}" | tr -d '\r' | sed 's/[[:space:]]*$//')" ||
      { echo "error: R CMD config ${v%%:*} failed" >&2; exit 1; }
    ext=""; [ "${v%%:*}" != OBJDUMP ] || ext=.exe
    if [ -z "$val" ] || [ ! -f "$(cygpath -u "$val$ext")" ] ||
       [ "$(cygpath -m -l "$val$ext" | lower)" != "$(printf '%s\n' "$tc_m/${v#*:}$ext" | lower)" ]; then
      echo "error: R CMD config ${v%%:*} is '$val', not $tc_m/${v#*:}" >&2
      exit 1
    fi
  done
  echo "== R CMD config AR, NM, OBJDUMP: R_HOME/bin/toolchain/{zig-ar.exe,binutils/nm.exe,binutils/objdump}"

  # R CMD check's compiled-code check reads a DLL's imports as sotools.R
  # does: tools:::read_symbols_from_dll runs R CMD config OBJDUMP when
  # its .exe is a file, else objdump.exe from PATH, which has none here.
  # It must take the group's and read R.dll's imports with it.
  cat > "$VERIFY_DIR/sotools.R" <<'RCODE'
s <- tools:::read_symbols_from_dll(file.path(R.home("bin"), "R.dll"))
od <- get0("DLL_nm", envir = tools:::read_symbols_from_dll_state, inherits = FALSE)
long <- function(p) tolower(normalizePath(p, "/", mustWork = FALSE))
want <- long(file.path(R.home(), "bin", "toolchain", "binutils", "objdump.exe"))
if (is.null(od) || !length(s) || long(paste0(od, ".exe")) != want)
    stop("read_symbols_from_dll read ", length(s), " symbols of R.dll with '", format(od), "', not ", want)
cat("   R CMD check's objdump:", od, "-", length(s), "symbols R.dll imports\n")
RCODE
  (cd "$VERIFY_DIR" && env -i "${base_env[@]}" PATH="$bt_path" "$RSCRIPT" --vanilla sotools.R) ||
    { echo "error: R CMD check's DLL check (tools:::read_symbols_from_dll) does not run R CMD config OBJDUMP" >&2; exit 1; }

  # The binutils load with nothing beside them but the system: PATH is
  # System32 alone, and nm.exe finds its DLLs (zstd.dll, vcruntime140.dll)
  # in its own directory (verify-toolchain.sh checks the closure).
  nm_out="$(env -i "${base_env[@]}" PATH="$sys32" "$TC/binutils/nm.exe" --version | tr -d '\r')" ||
    { echo "error: binutils/nm.exe --version failed with PATH = System32" >&2; exit 1; }
  case "${nm_out%%$'\n'*}" in
    "GNU nm"*) echo "== binutils/nm.exe runs with PATH = System32: ${nm_out%%$'\n'*}" ;;
    *) echo "error: binutils/nm.exe --version says '${nm_out%%$'\n'*}'" >&2; exit 1 ;;
  esac

  # rzig's check mode under R CMD names what R runs: make and sh from PATH,
  # and the binutils beside rzig (B24). The full path (C5): R CMD runs a
  # command it does not know from PATH, where R_HOME/bin/toolchain is
  # not. It goes into cmd.exe's line unquoted (rcmdfn.c), hence the short
  # form, which has no spaces.
  out="$(cd "$VERIFY_DIR" && env -i "${base_env[@]}" PATH="$bt_path" \
    "$R_EXE" CMD "$(cygpath -w -s "$cc")" --rzig-check=build-tools | tr -d '\r')" ||
    { echo "error: R CMD gcc.exe --rzig-check=build-tools failed with the build-tools group extracted" >&2; exit 1; }
  bad="$(bt_names "$out" make="$tc_m/usr/bin/make" sh="$tc_m/usr/bin/sh" binutils="$tc_m/binutils")" ||
    { echo "error: R CMD gcc.exe --rzig-check=build-tools says '$out': $bad" >&2; exit 1; }
  echo "   $out"

  # Each of Makeconf.win's binutils, as R's makefiles run them (C10, C11):
  # a tools.mk read after Makeconf by `R CMD make`. $(NM) on an object
  # prints its symbol (a missing nm would pass silently in a package's
  # link: winshlib.mk pipes it into sed); Makeconf's lib%.dll.a rule runs
  # $(DLLTOOL) with its --as; its %.a rule $(AR) crs, then $(RANLIB) and
  # $(STRIP_STATIC_LIB) on the archive; its %.o: %.rc rule $(RESCOMP) -i
  # r.rc -o r.o; $(OBJDUMP) -p on R.dll. (R CMD INSTALL --strip reads
  # R_STRIP_SHARED_LIB, not Makeconf's STRIP_SHARED_LIB, and R runs
  # DLLTOOL only through that rule: nothing else here would.)
  if [ -n "$pass_zig" ]; then
    tw="$VERIFY_DIR/tools"
    mkdir -p "$tw"
    printf '%s\n' 'int tools_sym(void) { return 7; }' > "$tw/t.c"
    printf '%s\n' 'LIBRARY x.dll' 'EXPORTS' 'tools_sym' > "$tw/x.def"
    cp "$bt/pk/btRc/src/res.rc" "$tw/r.rc"
    {
      printf 'all: nm.ok dll.ok lib.ok rc.ok objdump.ok\n'
      printf 'nm.ok: t.o\n\t$(NM) t.o > nm.out\n\tgrep -q " T tools_sym" nm.out\n\ttouch $@\n'
      printf 'dll.ok: libx.dll.a\n\t$(NM) libx.dll.a > dll.out\n\tgrep -q "__imp_tools_sym" dll.out\n\ttouch $@\n'
      printf 'libt.a: t.o\n'
      printf 'lib.ok: libt.a\n\t$(RANLIB) libt.a\n\t$(STRIP_STATIC_LIB) libt.a\n\t$(NM) libt.a > lib.out\n\tgrep -q " T tools_sym" lib.out\n\ttouch $@\n'
      printf 'rc.ok: r.o\n\t$(OBJDUMP) -h r.o > rc.out\n\tgrep -q "rsrc" rc.out\n\ttouch $@\n'
      printf 'objdump.ok:\n\t$(OBJDUMP) -p "$(R_HOME)/bin/x64/R.dll" > objdump.out\n\tgrep -q "DLL Name:" objdump.out\n\ttouch $@\n'
    } > "$tw/tools.mk"
    (cd "$tw" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$bt_path" \
      "$R_EXE" CMD make -f "$mk_m" -f tools.mk all) > "$tw/log" 2>&1 ||
      { cat "$tw/log" >&2; echo "error: Makeconf's binutils (tools.mk: \$(NM), \$(DLLTOOL) --as, \$(AR), \$(RANLIB), \$(STRIP_STATIC_LIB), \$(RESCOMP), \$(OBJDUMP)) did not all run" >&2; exit 1; }
    echo "== Makeconf's binutils run as R's makefiles run them: \$(NM) finds a symbol, \$(DLLTOOL) --as makes an import library, \$(AR) crs, \$(RANLIB), \$(STRIP_STATIC_LIB), \$(RESCOMP) -i r.rc, \$(OBJDUMP) -p"

    # CMake's archiver (CMakeFindBinUtils): for a GNU-like compiler it
    # looks for ar and ranlib in the C compiler's directory before PATH,
    # and packages hand it R CMD config CC, rzig's gcc.exe. rzig is ar.exe
    # and ranlib.exe there too, so a static library CMake builds has an
    # archiver with none on PATH: they make one as CMake runs them (qc,
    # then ranlib), with PATH = System32.
    (cd "$tw" && cmp -s "$TC/ar.exe" "$cc" && cmp -s "$TC/ranlib.exe" "$cc" &&
      env -i "${base_env[@]}" "${zig_env[@]}" PATH="$sys32" "$TC/ar.exe" qc libcm.a t.o &&
      env -i "${base_env[@]}" "${zig_env[@]}" PATH="$sys32" "$TC/ranlib.exe" libcm.a &&
      "$TC/binutils/nm.exe" libcm.a > cm.out && grep -q " T tools_sym" cm.out) > "$tw/cmake-ar.log" 2>&1 ||
      { cat "$tw/cmake-ar.log" >&2; echo "error: CMake's archiver: rzig's ar.exe and ranlib.exe beside gcc.exe did not make a static library with PATH = System32" >&2; exit 1; }
    echo "== CMake's archiver beside CC: ar.exe and ranlib.exe are rzig, and make a static library with PATH = System32"
  fi

  # OpenMP for packages, with the groups: R itself has no OpenMP on
  # Windows (upstream's choice), but etc/x64/Makeconf offers
  # SHLIB_OPENMP_*FLAGS, so the compilers group carries llvm-openmp's
  # omp.h and libomp.lib (TC/openmp/, B22) and the base libomp.dll
  # (R_HOME/bin/x64, vendor-libs.sh's), which makes rzig count openmp/
  # (B40). The ways packages ask that unix checks in scenario 2: a C
  # package with $(SHLIB_OPENMP_CFLAGS) on the compile and the link, a
  # flagless omp.h probe (data.table's configure), PKG_LIBS = -lomp alone
  # (rzig's windows.libs resolves it to openmp/lib/libomp.lib), and where
  # Makeconf offers Fortran OpenMP the fomp/fompfc packages (`use
  # omp_lib`, TC/flang's omp_lib.mod). They build through make with no
  # environment but the tree's: R_ZIG_EXTRA_ENV unset and the poisoned
  # decoy as CONDA_PREFIX; PATH as above (no flang on it: zig-fc runs
  # TC/flang). Each but the probe must import
  # libomp.dll (PE resolves every symbol at link time, so that is
  # openmp/lib/libomp.lib). Then they load in an R whose environment holds
  # only what Windows needs and whose PATH is bin\x64 and System32
  # (hermetic-check.sh's scenario), so libomp.dll comes from the base.
  if [ -n "$pass_zig" ] && grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    ow="$VERIFY_DIR/omp-win"
    mkdir -p "$ow/omp" "$ow/probe" "$ow/lomp"
    printf '%s\n' '#include <omp.h>' '#include <R.h>' 'void ompn(int *n) { *n = omp_get_max_threads(); }' > "$ow/omp/omp.c"
    printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$ow/omp/Makevars"
    printf '%s\n' '#include <omp.h>' 'int ompprobe(void) { return 0; }' > "$ow/probe/probe.c"
    printf '%s\n' 'extern int omp_get_max_threads(void);' 'void lompn(int *n) { *n = omp_get_max_threads(); }' > "$ow/lomp/lomp.c"
    printf '%s\n' 'PKG_LIBS = -lomp' > "$ow/lomp/Makevars"
    printf '%s\n' 'dyn.load("omp/omp.dll"); dyn.load("lomp/lomp.dll")' 'n <- c(.C("ompn", n = 0L)$n, .C("lompn", n = 0L)$n)' 'stopifnot(n >= 1L)' 'cat("omp, lomp: omp_get_max_threads() =", n, "\n")' > "$ow/load.R"
    pkgs="omp lomp"
    if grep -Eq '^SHLIB_OPENMP_FFLAGS = *-' "$mk"; then
      fomp_src "$ow"
      printf '%s\n' "$FOMP_R" >> "$ow/load.R"
      pkgs="omp lomp fomp fompfc"
    fi
    for d in probe $pkgs; do
      src="$d.c"
      [ -f "$ow/$d/$src" ] || src="$d.f"
      (cd "$ow/$d" && env -i "${base_env[@]}" "${zig_env[@]}" R_ZIG_PKG_BUILDER=make CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" \
        "$R_EXE" CMD SHLIB -o "$d.dll" "$src" > shlib.log 2>&1) || { cat "$ow/$d/shlib.log" >&2; echo "error: the OpenMP package $d failed to build with the base and the groups" >&2; exit 1; }
      [ "$d" = probe ] && continue
      needed_of "$ow/$d/$d.dll" | grep -qix 'libomp\.dll' || { needed_of "$ow/$d/$d.dll" >&2; echo "error: $d.dll does not import libomp.dll" >&2; exit 1; }
    done
    if [ -f "$ow/fompfc/shlib.log" ] && ! grep -Eq 'toolchain/zig-fc(\.exe)? -shared .*-o fompfc\.dll' "$ow/fompfc/shlib.log"; then
      cat "$ow/fompfc/shlib.log" >&2; echo "error: the USE_FC_TO_LINK link of fompfc did not run zig-fc" >&2; exit 1
    fi
    # No import library beside a DLL: zig writes one for each, which rzig
    # names and deletes after the link (windows.implib), as GNU ld writes
    # none. In a package's src/ R CMD build would pack it and R CMD check
    # warn (guard_dispatch.lib, kappa's round 1).
    left="$(cd "$ow" && ls -- */*.lib 2> /dev/null || :)"
    [ -z "$left" ] || { echo "error: the links left import libraries beside the DLLs: $left" >&2; exit 1; }
    (cd "$ow" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla load.R) ||
      { echo "error: the OpenMP packages ($pkgs) did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== compiled packages verified: OpenMP with the groups (probe $pkgs: omp.h, libomp.lib from openmp/; libomp.dll from bin\\x64 at load; no import library left beside a DLL; R CMD SHLIB, make)"

    # The same shapes as packages, which R CMD INSTALL builds through rzig
    # build (tier 1, a Makevars of assignments; patch 0013, the default
    # builder), the path a user's install of such a package takes here
    # [phase3-P3-1, records-REC-1, tests-T3]: DESCRIPTION, useDynLib and
    # the same Makevars, built with the environment and PATH of the SHLIB
    # builds above, RZIG_TRACE=1. Each log says `rzig build: tier 1` and
    # holds no recipe make echoed, fompfc's link is zig-fc's
    # (USE_FC_TO_LINK), each DLL imports libomp.dll (SHLIB_OPENMP_*FLAGS
    # and -lomp resolved by rzig, `rzig def` on the -fopenmp objects), no
    # import library and no build root is left, and they load and run with
    # PATH = bin\x64 + System32.
    owp="$ow/pkgs"
    mkdir -p "$owp/lib"
    cat > "$owp/load.R" <<'RCODE'
lib <- normalizePath("lib", "/")
pkgs <- commandArgs(trailingOnly = TRUE)
for (p in pkgs) loadNamespace(p, lib.loc = lib)
n <- c(.C("ompn", n = 0L, PACKAGE = "omp")$n, .C("lompn", n = 0L, PACKAGE = "lomp")$n)
stopifnot(n >= 1L)
for (d in intersect(c("fomp", "fompfc"), pkgs)) {
    r <- .Fortran("fompn", n = 0L, t = 0L, s = 0L, PACKAGE = d)
    stopifnot(r$n >= 1L, r$t == 2L, r$s == 5050L)
}
cat("packages", pkgs, "loaded: omp_get_max_threads() =", n, "\n")
RCODE
    for d in $pkgs; do
      mkdir -p "$owp/$d/src"
      printf 'Package: %s\nVersion: 0.1\nTitle: Verify Bundle\nDescription: An OpenMP shape R CMD INSTALL builds through rzig build.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$d" > "$owp/$d/DESCRIPTION"
      printf 'useDynLib(%s)\n' "$d" > "$owp/$d/NAMESPACE"
      src="$d.c"
      [ -f "$ow/$d/$src" ] || src="$d.f"
      cp "$ow/$d/$src" "$ow/$d/Makevars" "$owp/$d/src/"
      (cd "$owp" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" RZIG_TRACE=1 \
        "$R_EXE" CMD INSTALL -l lib "$d") > "$owp/$d.log" 2>&1 ||
        { cat "$owp/$d.log" >&2; echo "error: R CMD INSTALL of the OpenMP package $d failed with the base and the groups" >&2; exit 1; }
      starts_line "$owp/$d.log" "rzig build: tier 1" ||
        { cat "$owp/$d.log" >&2; echo "error: the OpenMP package $d did not build through rzig build (no 'rzig build: tier 1')" >&2; exit 1; }
      if [ -n "$(make_recipes "$owp/$d.log")" ]; then
        cat "$owp/$d.log" >&2; echo "error: a recipe make echoed in the OpenMP package $d's install log" >&2; exit 1
      fi
      # (grep reads to the end, no -q [tests-SIGPIPE-1])
      if [ "$d" = fompfc ] && ! tr -d '\r' < "$owp/$d.log" | grep -E '^zig-fc: .* -o [^ ]*fompfc\.dll' > /dev/null; then
        cat "$owp/$d.log" >&2; echo "error: the USE_FC_TO_LINK link of the fompfc package through rzig build did not run zig-fc" >&2; exit 1
      fi
      dll="$(find "$owp/lib/$d/libs" -name "$d.dll" 2> /dev/null | head -1 || true)"
      [ -n "$dll" ] || { echo "error: no $d.dll under $owp/lib/$d/libs after its install" >&2; exit 1; }
      needed_of "$dll" | grep -qix 'libomp\.dll' || { needed_of "$dll" >&2; echo "error: the $d package's DLL (rzig build) does not import libomp.dll" >&2; exit 1; }
      left="$(find "$owp/$d/src" "$owp/lib/$d" -name '*.lib' 2> /dev/null || true)"
      [ -z "$left" ] || { echo "error: the $d package's install left import libraries: $left" >&2; exit 1; }
      test ! -e "$owp/$d/src/.rzig" || { echo "error: the $d package's install left its build root, $owp/$d/src/.rzig" >&2; exit 1; }
    done
    # $pkgs: one argument per package
    # shellcheck disable=SC2086
    (cd "$owp" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla load.R $pkgs) ||
      { echo "error: the OpenMP packages ($pkgs) built through rzig build did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== compiled packages verified: OpenMP with the groups ($pkgs: tier 1, each DLL imports libomp.dll, no import library or build root left, loads with PATH = bin\\x64 + System32; R CMD INSTALL, rzig build)"
  fi

  if [ -n "$pass_zig" ]; then
    (cd "$bt" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" RZIG_TRACE=1 \
      "$RSCRIPT" --vanilla bt.R) > "$bt/bt.log" 2>&1 ||
      { cat "$bt/bt.log" >&2; echo "error: the packages ($bt_pkgs) did not build with the base and the groups (btA through rzig build, btLib and btRc through make)" >&2; exit 1; }
    (cd "$bt" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla bt-load.R) ||
      { echo "error: the packages ($bt_pkgs) did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    rc_dll="$(find "$bt/lib/btRc/libs" -name btRc.dll | head -1)"
    "$TC/binutils/objdump.exe" -h "$rc_dll" | grep -q 'rsrc' ||
      { echo "error: btRc.dll has no .rsrc section: its .rc file did not reach the link" >&2; exit 1; }
    echo "== packages built under the default builder, install.packages with Ncpus = 2: btA through rzig build, btLib and btRc through make (a static library through rzig's zig-ar.exe and zig-ranlib.exe; a .rc file through \$(RESCOMP), its resources in btRc.dll), each from its log; load with PATH = bin\\x64 + System32"

    # fcconf (fcconf_pkg): a configure.win that compiles, links and runs a
    # program with $FC (zig-fc.exe: TC/flang, zig) and links with -v,
    # run by the build tools' sh, then make builds the package; it loads
    # with PATH = bin\x64 + System32.
    fcw="$VERIFY_DIR/fcconf"
    fcconf_pkg "$fcw"
    mkdir -p "$fcw/lib"
    (cd "$fcw" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" \
      "$R_EXE" CMD INSTALL -l lib fcconf) > "$fcw/install.log" 2>&1 ||
      { cat "$fcw/install.log" >&2; echo "error: fcconf (a configure.win that compiles, links and runs a program with \$FC) did not install with the base and the groups" >&2; exit 1; }
    # (grep reads to the end, no -q [tests-SIGPIPE-1])
    tr -d '\r' < "$fcw/install.log" | grep '^fcconf: .*/zig-fc compiles, links and runs a program$' > /dev/null ||
      { cat "$fcw/install.log" >&2; echo "error: fcconf's configure.win did not say that \$FC compiles, links and runs a program" >&2; exit 1; }
    (cd "$fcw" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla \
      -e 'stopifnot(getExportedValue(loadNamespace("fcconf", lib.loc = "lib"), "f")() == 5L)') ||
      { echo "error: fcconf did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    echo "== a configure.win with \$FC: fcconf's compiles, links and runs a program with zig-fc.exe (TC/flang, zig), links with -v; the package installs and loads with PATH = bin\\x64 + System32"

    # LTO, recorded, not checked (B43-2, C9). Makeconf.win's LTO block
    # (AR, NM and RANLIB as gcc-ar, gcc-nm and gcc-ranlib) is read only
    # when LTO_OPT is non-empty as Makeconf is read, which a package's
    # Makevars, read first, cannot make so: a command-line variable can,
    # here MAKEFLAGS in R CMD INSTALL's environment. ltodef ships
    # ltodef-win.def and a static library (gcc-ar and gcc-ranlib: rzig);
    # ltonodef the same without the .def, so winshlib.mk runs the gcc-nm
    # that does not ship, whose failure its pipe into sed hides: tmp.def
    # gets no symbols, and lld's MinGW auto-export exports everything.
    # What happens goes into PLAN.md's record.
    lt="$VERIFY_DIR/lto"
    mkpkg "$lt/pk" ltodef 42 lib
    printf '%s\n' 'LIBRARY ltodef.dll' 'EXPORTS' ' ltodef_f' > "$lt/pk/ltodef/src/ltodef-win.def"
    mkpkg "$lt/pk" ltonodef 42 lib
    # the tier-1 twin (no Makevars; feat-zig-pkg-build N4): a variable set in
    # MAKEFLAGS sends it to make, with that reason, so make's LTO build is
    # what runs; checked, then recorded like the others
    mkpkg "$lt/pk" ltotier1 42
    mkdir -p "$lt/lib"
    cat > "$lt/lto-load.R" <<'RCODE'
p <- commandArgs(trailingOnly = TRUE)[1L]
cat(tryCatch(paste("loads, f() =", getExportedValue(loadNamespace(p, lib.loc = normalizePath("lib", "/")), "f")()),
             error = function(e) paste("does not load:", conditionMessage(e))), "\n", sep = "")
RCODE
    echo "== LTO record (B43-2; recorded, not checked): MAKEFLAGS='LTO_OPT=-flto' in R CMD INSTALL's environment"
    for p in ltodef ltonodef ltotier1; do
      rc=0
      (cd "$lt" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" \
        MAKEFLAGS='LTO_OPT=-flto' RZIG_TRACE=1 "$R_EXE" CMD INSTALL -l lib "pk/$p") > "$lt/$p.log" 2>&1 || rc=$?
      if [ "$p" = ltotier1 ] && ! grep -q 'rzig build: ltotier1 needs make: MAKEFLAGS sets LTO_OPT' "$lt/$p.log"; then
        cat "$lt/$p.log" >&2
        echo "error: with MAKEFLAGS='LTO_OPT=-flto' the tier-1 package did not go to make with the reason 'MAKEFLAGS sets LTO_OPT'" >&2
        exit 1
      fi
      r="install exit $rc"
      if grep -q 'gcc-ar' "$lt/$p.log" && grep -q 'gcc-ranlib' "$lt/$p.log"; then
        r="$r, gcc-ar and gcc-ranlib ran"
      else
        r="$r, gcc-ar or gcc-ranlib did not run"
      fi
      if [ "$p" = ltonodef ]; then
        if grep -qi 'gcc-nm' "$lt/$p.log"; then r="$r, the missing gcc-nm named in its log"; else r="$r, gcc-nm not named in its log"; fi
      fi
      if [ "$rc" = 0 ]; then
        r="$r; $(cd "$lt" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla lto-load.R "$p" 2>&1 | tr -d '\r' || true)"
      fi
      case "$p" in
        ltodef) echo "   ltodef (ltodef-win.def, a static library): $r" ;;
        ltonodef) echo "   ltonodef (no .def, a static library): $r" ;;
        *) echo "   ltotier1 (no Makevars; MAKEFLAGS sets LTO_OPT, so make, not rzig build): $r" ;;
      esac
    done

    # btTools (B39; PHASE7 step 4): a configure.win that runs, through the
    # group's sh, the tools R's makefiles and configure scripts call
    # (coreutils, sed, grep, gawk, awk, expr, find and xargs, which, and
    # patch -p0 with a two-line diff: feat-win-link-fixes item 4), each
    # step checked, and writes src/Makevars.win with the count as
    # BTTOOLS and a rule of its own, so make builds it; its cleanup.win
    # (find | xargs rm, which R CMD INSTALL --preclean runs first) removes
    # a stale object. f() returns the count; it loads with PATH = bin\x64
    # + System32.
    tools_pkg() {
      local d="$1/btTools"
      mkpkg "$1" btTools 0
      printf '%s\n' 'int btTools_val(void) { return BTTOOLS; }' > "$d/src/val.c"
      : > "$d/src/stale.o"
      cat > "$d/configure.win" <<'CONFIGURE'
#!/bin/sh
n=0
ok() { n=`expr $n + 1`; }
no() { echo "btTools: configure.win: $1 failed"; exit 1; }
test "`echo 'a b c' | awk '{ print $2 }'`" = b && ok || no awk
test "`echo 'a b c' | gawk '{ print $3 }'`" = c && ok || no gawk
test "`printf 'l1\nl2\n' | sed -n 2p`" = l2 && ok || no sed
echo abc | grep -E 'a.c' > /dev/null && ok || no grep
test "`expr 2 + 3`" = 5 && ok || no expr
test "`echo abc | tr a-c A-C`" = ABC && ok || no tr
test "`printf 'b\na\n' | sort | head -n 1`" = a && ok || no sort/head
test "`printf 'a\na\nb\n' | uniq | wc -l | tr -d ' '`" = 2 && ok || no uniq/wc
test "`echo a:b | cut -d: -f2`" = b && ok || no cut
test "`printf '1\n2\n3\n' | tail -n 1`" = 3 && ok || no tail
test "`basename src/f.c .c`" = f && ok || no basename
test "`dirname src/f.c`" = src && ok || no dirname
uname -s > /dev/null && ok || no uname
t=`mktemp` && test -f "$t" && rm -f "$t" && ok || no mktemp
mkdir -p tt/a/b && ok || no mkdir
cat DESCRIPTION > tt/a/b/d && cp tt/a/b/d tt/c && mv tt/c tt/e && ok || no cat/cp/mv
ln -s d tt/a/b/l && test -f tt/a/b/l && ok || no ln
chmod +x tt/e && touch tt/t && ls tt > /dev/null && ok || no chmod/touch/ls
test "`find . -name '*.c' | xargs grep -l BTTOOLS | wc -l | tr -d ' '`" = 1 && ok || no find/xargs
which sh > /dev/null && ok || no which
printf '%s\n' x > /dev/null && env > /dev/null && ok || no printf/env
printf 'a\n' > tt/pf && printf -- '--- tt/pf\n+++ tt/pf\n@@ -1 +1 @@\n-a\n+b\n' | patch -p0 > /dev/null && test "`cat tt/pf`" = b && ok || no patch
rm -rf tt
echo "btTools: configure.win: all tools ran ($n steps)"
printf 'PKG_CPPFLAGS = -DBTTOOLS=%s\nall: $(SHLIB) stamp\nstamp: ; @touch $@ && rm -f $@\n' "$n" > src/Makevars.win
CONFIGURE
      cat > "$d/cleanup.win" <<'CLEANUP'
#!/bin/sh
find src -name '*.o' | xargs rm -f
rm -f src/Makevars.win
echo "btTools: cleanup.win ran"
CLEANUP
      chmod +x "$d/configure.win" "$d/cleanup.win"
    }
    # btPc (PHASE7 amendment Am9, less its pkgconf parts: user decision D0
    # a): a configure.win that asks the group's pkg-config (0.29.2, B43)
    # about btpc.pc, under a directory whose name has a space: --libs has
    # the public libraries (0.29.2 adds the private ones too, without
    # --static: printed, not asserted; PHASE7 KN d), --static the private
    # too, the prefix is the .pc file's (Windows' prefix redefinition),
    # --cflags escapes the space; the package compiles with those --cflags
    # through make and sh and f() returns BTPC, 7.
    pc_dir="$VERIFY_DIR/pc dir"
    mkdir -p "$pc_dir/lib/pkgconfig" "$pc_dir/include"
    printf '%s\n' '#define BTPC_HEADER 1' > "$pc_dir/include/btpc.h"
    printf '%s\n' 'prefix=/nonexistent' 'Name: btpc' 'Description: verify-bundle' 'Version: 1.0' \
      'Libs: -lbtpc_pub' 'Libs.private: -lbtpc_priv' 'Cflags: -I${prefix}/include -DBTPC=7' > "$pc_dir/lib/pkgconfig/btpc.pc"
    pc_pkg() {
      local d="$1/btPc"
      mkpkg "$1" btPc 0
      printf '%s\n' '#include <btpc.h>' 'int btPc_val(void) { return BTPC_HEADER ? BTPC : 0; }' > "$d/src/val.c"
      cat > "$d/configure.win" <<'CONFIGURE'
#!/bin/sh
libs=`pkg-config --libs btpc | tr -d '\r'` || { echo "btPc: pkg-config --libs btpc failed"; exit 1; }
echo "btPc: pkg-config --libs: $libs"
case " $libs " in *" -lbtpc_pub "*) ;; *) echo "btPc: --libs has no -lbtpc_pub"; exit 1 ;; esac
slibs=`pkg-config --static --libs btpc | tr -d '\r'`
echo "btPc: pkg-config --static --libs: $slibs"
case " $slibs " in *" -lbtpc_priv "*) ;; *) echo "btPc: --static --libs has no -lbtpc_priv"; exit 1 ;; esac
echo "btPc: prefix: `pkg-config --variable=prefix btpc | tr -d '\r'`"
cflags=`pkg-config --cflags btpc | tr -d '\r'`
echo "btPc: pkg-config --cflags: $cflags"
echo "btPc: pkg-config answers"
printf 'PKG_CPPFLAGS = %s\n' "$cflags" > src/Makevars.win
CONFIGURE
      chmod +x "$d/configure.win"
    }
    # The two installs, with PATH $1 and the extra environment after it.
    # Their logs: $2/btTools.log, $2/btPc.log.
    tools_pc_install() {
      local p="$1" wd="$2"; shift 2
      rm -rf "$wd"; mkdir -p "$wd/lib"
      tools_pkg "$wd"
      pc_pkg "$wd"
      (cd "$wd" && env -i "${base_env[@]}" "${zig_env[@]}" "$@" PATH="$p" RZIG_TRACE=1 \
        "$R_EXE" CMD INSTALL --preclean -l lib btTools) > "$wd/btTools.log" 2>&1 ||
        { cat "$wd/btTools.log" >&2; echo "error: btTools (B39's tools through a configure.win, a cleanup.win and a Makevars rule) did not install" >&2; exit 1; }
      tr -d '\r' < "$wd/btTools.log" | grep -q '^btTools: cleanup.win ran$' && test ! -e "$wd/btTools/src/stale.o" ||
        { cat "$wd/btTools.log" >&2; echo "error: btTools' cleanup.win did not run under --preclean (src/stale.o left)" >&2; exit 1; }
      n="$(tr -d '\r' < "$wd/btTools.log" | sed -n 's/^btTools: configure.win: all tools ran (\([0-9]*\) steps)$/\1/p')"
      [ -n "$n" ] || { cat "$wd/btTools.log" >&2; echo "error: btTools' configure.win did not say that all tools ran" >&2; exit 1; }
      grep -q 'rzig build: btTools needs make: ' "$wd/btTools.log" ||
        { cat "$wd/btTools.log" >&2; echo "error: btTools did not go to make (its Makevars rule)" >&2; exit 1; }
      (cd "$wd" && env -i "${base_env[@]}" "${zig_env[@]}" "$@" PATH="$p" PKG_CONFIG_PATH="$(w "$pc_dir/lib/pkgconfig")" RZIG_TRACE=1 \
        "$R_EXE" CMD INSTALL -l lib btPc) > "$wd/btPc.log" 2>&1 ||
        { cat "$wd/btPc.log" >&2; echo "error: btPc (pkg-config through a configure.win, a .pc file under a path with a space) did not install" >&2; exit 1; }
      tr -d '\r' < "$wd/btPc.log" | grep -q '^btPc: pkg-config answers$' ||
        { cat "$wd/btPc.log" >&2; echo "error: btPc's configure.win did not get its answers from pkg-config" >&2; exit 1; }
      # (pkg-config escapes the space here too: compared without the \)
      pfx="$(tr -d '\r' < "$wd/btPc.log" | sed -n 's/^btPc: prefix: //p' | tr -d '\\' | tr '[:upper:]' '[:lower:]')"
      [ "$pfx" = "$(cygpath -m "$pc_dir" | tr '[:upper:]' '[:lower:]')" ] ||
        { cat "$wd/btPc.log" >&2; echo "error: pkg-config's prefix for btpc is '$pfx', not the .pc file's, $(cygpath -m "$pc_dir")" >&2; exit 1; }
      tr -d '\r' < "$wd/btPc.log" | grep -qF 'pc\ dir/include' ||
        { cat "$wd/btPc.log" >&2; echo "error: pkg-config --cflags did not escape the space in '$pc_dir'" >&2; exit 1; }
      (cd "$wd" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla \
        -e "stopifnot(getExportedValue(loadNamespace('btTools', lib.loc = 'lib'), 'f')() == $n, getExportedValue(loadNamespace('btPc', lib.loc = 'lib'), 'f')() == 7L)") ||
        { echo "error: btTools (f() == $n) or btPc (f() == 7) did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    }
    tools_pc_install "$bt_path" "$VERIFY_DIR/tools-pc"
    echo "== B39's tools: btTools' configure.win ran $n steps through the group's sh (awk, gawk, sed, grep, expr, tr, sort, uniq, cut, head, tail, basename, dirname, uname, mktemp, mkdir, cat, cp, mv, ln, chmod, touch, ls, find | xargs, which, printf, env, patch -p0), its cleanup.win under --preclean, its Makevars rule through make; loads, f() = $n"
    echo "   btPc: $(tr -d '\r' < "$VERIFY_DIR/tools-pc/btPc.log" | grep '^btPc: pkg-config --\(libs\|static\|cflags\)' | sed 's/^btPc: //' | tr '\n' ';')"
    echo "== pkg-config (the group's, 0.29.2): btPc's configure.win under a path with a space: the public libraries, the private ones with --static, the prefix the .pc file's, --cflags escaped and compiled through make and sh; loads, f() = 7"

    # R CMD check's nm (PHASE7 open point H a): sotools.R reads an object's
    # symbols with UserNM, else an nm on PATH, which has none: under R
    # CMD, Rcmd_environ's UserNM is the group's binutils/nm.exe, and it
    # reads tools.mk's t.o; one set by the user is kept.
    cat > "$tw/nm.R" <<'RCODE'
want <- commandArgs(trailingOnly = TRUE)[1L]
nm <- Sys.getenv("UserNM")
if (want == "group") {
    want <- file.path(R.home(), "bin", "toolchain", "binutils", "nm.exe")
    if (tolower(normalizePath(nm, "/", mustWork = FALSE)) != tolower(normalizePath(want, "/")))
        stop("UserNM is '", nm, "', not ", want)
    s <- tools:::read_symbols_from_object_file("t.o")
    if (!any(s[, "name"] == "tools_sym")) stop("read_symbols_from_object_file(t.o) found no tools_sym")
    cat("   R CMD check's nm: UserNM =", nm, "-", nrow(s), "symbols of t.o\n")
} else if (nm != want) stop("UserNM is '", nm, "', not the user's ", want)
RCODE
    (cd "$tw" && env -i "${base_env[@]}" PATH="$bt_path" "$R_EXE" CMD Rscript.exe --vanilla nm.R group) ||
      { echo "error: under R CMD, UserNM is not the group's binutils/nm.exe, or R CMD check's symbol table of an object is not read with it" >&2; exit 1; }
    (cd "$tw" && env -i "${base_env[@]}" UserNM=C:/r-zig-user/nm.exe PATH="$bt_path" "$R_EXE" CMD Rscript.exe --vanilla nm.R C:/r-zig-user/nm.exe) ||
      { echo "error: under R CMD, a UserNM the user set is not kept (Rcmd_environ's \${UserNM-...})" >&2; exit 1; }
    echo "== R CMD check's nm: UserNM is binutils/nm.exe under R CMD (a user's is kept), and tools:::read_symbols_from_object_file reads t.o with it"

    # The clash with Git for Windows' MSYS (PHASE7 open point M a,
    # amendment Am4), where it is installed (every windows-latest image):
    # its usr\bin first on the caller's PATH, with Git Bash's
    # MSYSTEM=MINGW64, then after System32. For every name the group has,
    # R CMD and the session put the group's usr/bin first whatever the
    # caller's order, so Sys.which and the check mode name the group's;
    # Git first, the packages build again, and btMix's configure.win runs
    # Git's own diff and cygpath through the group's sh: two msys-2.0.dll
    # in one process tree (PHASE7 risk 1).
    git_usr="/c/Program Files/Git/usr/bin"
    if [ -f "$git_usr/msys-2.0.dll" ]; then
      cat > "$tw/which.R" <<'RCODE'
tc <- tolower(normalizePath(file.path(R.home(), "bin", "toolchain", "usr", "bin"), "/"))
for (n in c("sh", "make", "sed", "pkg-config")) {
    w <- Sys.which(n)
    if (!nzchar(w) || tolower(dirname(normalizePath(w, "/"))) != tc)
        stop(commandArgs(trailingOnly = TRUE)[1L], ": Sys.which(\"", n, "\") is '", w, "', not in ", tc)
}
RCODE
      mixw="$VERIFY_DIR/mix"
      mkpkg "$mixw/pk" btMix 9
      cat > "$mixw/pk/btMix/configure.win" <<'CONFIGURE'
#!/bin/sh
printf 'a\n' > m1; printf 'b\n' > m2
d=`diff m1 m2 | tr -d '\r' | tr '\n' ' '`
echo "btMix: diff: $d"
case "$d" in *"< a"*"> b"*) ;; *) echo "btMix: diff did not compare the files"; exit 1 ;; esac
echo "btMix: which diff: `which diff`; cygpath -m /: `cygpath -m / | tr -d '\r'`; uname -s: `uname -s`"
rm -f m1 m2
CONFIGURE
      chmod +x "$mixw/pk/btMix/configure.win"
      mkdir -p "$mixw/lib"
      git_ver="$(env -i "${base_env[@]}" PATH="$git_usr:$sys32" "$git_usr/uname.exe" -r 2>&1 | tr -d '\r' || true)"
      for order in first after; do
        if [ "$order" = first ]; then cp="$git_usr:$R_BINDIR:$sys32"; mix_env=(MSYSTEM=MINGW64); else cp="$R_BINDIR:$sys32:$git_usr"; mix_env=(); fi
        (cd "$tw" && env -i "${base_env[@]}" "${mix_env[@]}" PATH="$cp" "$R_EXE" CMD Rscript.exe --vanilla which.R "Git $order, under R CMD") &&
          (cd "$tw" && env -i "${base_env[@]}" "${mix_env[@]}" PATH="$cp" "$RSCRIPT" --vanilla which.R "Git $order, in a session") ||
          { echo "error: with Git for Windows' usr\\bin $order on PATH, sh, make, sed or pkg-config is not the group's" >&2; exit 1; }
        out="$(cd "$VERIFY_DIR" && env -i "${base_env[@]}" "${mix_env[@]}" PATH="$cp" \
          "$R_EXE" CMD "$(cygpath -w -s "$cc")" --rzig-check=build-tools | tr -d '\r')" ||
          { echo "error: R CMD gcc.exe --rzig-check=build-tools failed with Git for Windows' usr\\bin $order on PATH" >&2; exit 1; }
        bad="$(bt_names "$out" make="$tc_m/usr/bin/make" sh="$tc_m/usr/bin/sh")" ||
          { echo "error: with Git for Windows' usr\\bin $order on PATH, the check says '$out': $bad" >&2; exit 1; }
        [ "$order" = first ] || continue
        s0=$SECONDS
        (cd "$bt" && rm -rf lib && mkdir lib && env -i "${base_env[@]}" "${zig_env[@]}" "${mix_env[@]}" PATH="$cp" RZIG_TRACE=1 \
          "$RSCRIPT" --vanilla bt.R) > "$bt/bt-git.log" 2>&1 ||
          { cat "$bt/bt-git.log" >&2; echo "error: with Git for Windows' usr\\bin first on PATH, the packages ($bt_pkgs) did not build" >&2; exit 1; }
        tools_pc_install "$cp" "$VERIFY_DIR/tools-pc-git" "${mix_env[@]}"
        (cd "$fcw" && rm -rf lib && mkdir lib && env -i "${base_env[@]}" "${zig_env[@]}" "${mix_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$cp" \
          "$R_EXE" CMD INSTALL -l lib fcconf) > "$fcw/install-git.log" 2>&1 ||
          { cat "$fcw/install-git.log" >&2; echo "error: with Git for Windows' usr\\bin first on PATH, fcconf did not install" >&2; exit 1; }
        (cd "$mixw" && env -i "${base_env[@]}" "${zig_env[@]}" "${mix_env[@]}" PATH="$cp" \
          "$R_EXE" CMD INSTALL -l lib pk/btMix) > "$mixw/install.log" 2>&1 ||
          { cat "$mixw/install.log" >&2; echo "error: btMix (Git's diff and cygpath from the group's sh) did not install" >&2; exit 1; }
        if grep -qiE 'cygheap|fork: retry|\*\*\* fatal error' "$bt/bt-git.log" "$VERIFY_DIR"/tools-pc-git/*.log "$fcw/install-git.log" "$mixw/install.log"; then
          grep -iE 'cygheap|fork: retry|\*\*\* fatal error' "$bt/bt-git.log" "$VERIFY_DIR"/tools-pc-git/*.log "$fcw/install-git.log" "$mixw/install.log" >&2
          echo "error: with Git for Windows' usr\\bin first on PATH, MSYS failed (two msys-2.0.dll in one process tree)" >&2; exit 1
        fi
        mix="$(tr -d '\r' < "$mixw/install.log" | grep '^btMix: which diff' | sed 's/^btMix: //')"
        uname_s="$(cd "$VERIFY_DIR" && env -i "${base_env[@]}" "${mix_env[@]}" PATH="$cp" "$R_EXE" CMD sh -c "uname -s" | tr -d '\r' || true)"
        echo "   Git first (MSYSTEM=MINGW64), $((SECONDS - s0)) s: btA, btLib, btRc, btTools, btPc, fcconf and btMix built and installed; R CMD sh's uname -s: $uname_s; btMix: $mix"
      done
      echo "== the clash with Git for Windows' MSYS (its msys-2.0.dll $git_ver): first (MSYSTEM=MINGW64) and after on PATH, Sys.which (R CMD and session) and the check name the group's sh, make, sed and pkg-config; Git first, the packages build, Git's diff and cygpath run from the group's sh, no MSYS failure"
    else
      cannot_check "no Git for Windows MSYS ($git_usr/msys-2.0.dll): the clash (PHASE7 open point M) is not checked"
    fi
  else
    echo "== package builds skipped (no zig: ZIG_BIN unset, none on PATH)"
  fi
fi

# The install preflight and R_ZIG_NO_PREFLIGHT (B26, C26), every OS: with
# both groups and no zig, a package with C code and a configure script stops in
# the preflight with the compilers' text, its configure not run; with
# R_ZIG_NO_PREFLIGHT=1 it gets past the preflight, its configure runs and
# leaves its marker, and the compile then fails with rzig's no-zig line.
# Here, not with the base alone: the install runs R CMD config before
# configure (for CC and the other variables), and R CMD config needs the
# build tools (patch 0010; on Windows the binutils too). PATH: unix
# /usr/bin:/bin, the group's make first (etc/Renviron); Windows as for the
# builds above. A zig of the host's own (scenario 1) would let the compile
# through: then this is skipped with a note. The compilers group brings
# zig since phase 5: without its binary, rzig sees what a user with R and
# the build tools only sees (find_zig tests only <rzig dir>/zig/zig). The
# binary alone, out of R_HOME and back after (Cc8, PHASE5 open point E): a
# rename of the 19.5k-file directory fails on NTFS while anything
# (Defender) holds a handle under it. In the toolchain pass only: it passes
# no zig, so the build pass would test the same thing (open point S).
if [ "$pass" != toolchain ]; then
  echo "   note: the preflight with no zig runs in the toolchain pass only: it passes no zig (PHASE5 open point S)"
elif [ -n "$host_zig" ]; then
  echo "   note: the preflight and R_ZIG_NO_PREFLIGHT not checked: this host's $host_zig is on PATH"
else
  mv "$TC/zig/zig$exe" "$VERIFY_DIR/zig.aside"
  np="$VERIFY_DIR/nopre"
  mkpkg "$np/pk" nopre 5
  configure_marker "$np/pk/nopre"
  mkdir -p "$np/lib"
  if [ "$OS" = windows ]; then np_r="$R_EXE"; np_path="$bt_path"; else np_r="$R_BIN"; np_path=/usr/bin:/bin; fi
  for skip in "" 1; do
    rc=0
    (cd "$np" && env -i "${base_env[@]}" ${skip:+R_ZIG_NO_PREFLIGHT=1} PATH="$np_path" \
      "$np_r" CMD INSTALL -l lib pk/nopre) > "$np/install$skip.log" 2>&1 || rc=$?
    ran=""; [ ! -e "$np/pk/nopre/configure-ran" ] || ran=1
    if [ -z "$skip" ]; then
      if [ "$rc" = 0 ] || [ -n "$ran" ] || ! starts_line "$np/install.log" "$no_zig_line" ||
         ! starts_line "$np/install.log" "$compilers_head" || ! starts_line "$np/install.log" "$preflight_stop"; then
        cat "$np/install.log" >&2
        echo "error: with no zig, the install preflight did not stop nopre before its configure with the compilers' text (exit $rc)" >&2
        exit 1
      fi
    elif [ "$rc" = 0 ] || [ -z "$ran" ] || [ -e "$np/lib/nopre" ] ||
         starts_line "$np/install1.log" "$preflight_stop" || ! starts_line "$np/install1.log" "$no_zig_line"; then
      cat "$np/install1.log" >&2
      echo "error: with R_ZIG_NO_PREFLIGHT=1 and no zig, nopre's install did not get past the preflight, run its configure and fail in the compile with '$no_zig_line' (exit $rc)" >&2
      exit 1
    fi
  done
  mv "$VERIFY_DIR/zig.aside" "$TC/zig/zig$exe"
  echo "== the install preflight with no zig (TC/zig/zig$exe moved aside): a package stops before its configure with the compilers' text; with R_ZIG_NO_PREFLIGHT=1 its configure runs and the compile fails with no zig"
fi

# The build pass (feat-standalone-toolchain phase 5, PHASE5 open point F):
# the same archives with the build's zig, ZIG_BIN=$ZIG, so that
# conda-forge's zig keeps its package coverage on the default legs. This
# pass's directory goes first, so the two never take TMPDIR's space at
# once, and the build pass's result is the script's: the log's last
# "verified" line is the last pass that ran (Cc4).
scenarios="the base alone, + compilers, + build-tools"
[ "$pass" = toolchain ] || scenarios="+ compilers, + build-tools (the base alone in the toolchain pass)"
echo "== standalone archives verified ($OS/$FLAVOR, the $pass pass: zig from $pass_what, $SECONDS s): $scenarios"
if [ -n "$build_pass" ]; then
  rm -rf "$VERIFY_DIR"; trap - EXIT
  exec bash "$0" build
elif [ "$pass" = toolchain ] && [ -n "$ZIG" ]; then
  echo "   note: the build's zig is TC/zig's bytes ($ZIG): no build pass"
fi
