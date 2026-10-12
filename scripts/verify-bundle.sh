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
# rzig (B19, B30; Windows' Tcl/Tk headers stay in R_HOME/Tcl/include, T1);
# each group archive holds only its own directories; no file is in two
# archives, so tar and `unzip -n` (which never stops to ask, C6) fill one
# directory without one archive overwriting another.
#   1. The base alone: R runs from the new place (unix: env -i) with the
#      flavor's capabilities, the vendored libraries loading from there;
#      R puts the build-tools group's usr/bin first on PATH (B25, C27);
#      rzig's check mode exits 127 for each group with what is missing
#      and the group's text (B26, B35); hermetic-check.sh's tier 0/1 on
#      the extracted tree, where the install preflight stops a compiled
#      package with the compilers' text; TLS trust with the shipped CA
#      bundle and nothing from the build env (unix).
#   2. + compilers: rzig's check mode finds zig and flang; unix, the
#      preflight's other branches (zig from ZIG_BIN, no make, no flang;
#      feat-zig-pkg-build M4): a C package with no Makevars builds
#      through `rzig build` (patch 0013) with no make and loads; one
#      whose Makevars has a rule stops with rzig's reason and the build
#      tools' text, an R-only package with a configure script with "a
#      configure script R runs" and the same text, a Fortran one with no
#      flang and the compilers' text (C26); the C compiler compiles for
#      the arch's baseline CPU, not this machine's, also when told
#      -mtune=native (LLVM IR's target-cpu); packages compiled with the
#      tree build and load. unix, under env -i: C++, Fortran,
#      USE_FC_TO_LINK, $(FLIBS) without flang, zig-fc with no flang,
#      OpenMP (C, and Fortran with `use omp_lib`) with the group's
#      openmp/ where the base has libomp and openmp/ left alone on
#      minimal (B40), decoy CONDA_PREFIX runs: each shape through R CMD
#      SHLIB (make, the run-time compile path) and as a package through
#      R CMD INSTALL (rzig build, asserted from its log), with the same
#      checks on both libraries.
#      Windows, where make is a build tool: rzig's dry runs (-L from
#      where the tree now is, the group's openmp/, CONDA_PREFIX ignored),
#      and an OpenMP DLL compiled and linked by gcc.exe alone, loaded
#      with only bin\x64 and System32 on PATH.
#   3. + build-tools: R runs the group's tools. unix: make is
#      R_HOME/bin/toolchain/usr/bin/make (rzig's check mode, Sys.which,
#      and on linux the make strace saw run), and install.packages with
#      Ncpus = 2 builds two packages, a mixed run under the default
#      builder: btA (plain C) through rzig build, btLib (a static library
#      made by $(AR) and $(RANLIB): rzig, B43) through the group's make,
#      each asserted from its kept log. Windows: every
#      tool Makeconf.win names is the group's binutils or rzig (B24,
#      B43), R CMD check's DLL check runs the group's objdump, a tools.mk
#      runs each of the binutils (C10, C11), CMake's ar and ranlib beside
#      CC are rzig, and the OpenMP C and Fortran packages (through R CMD
#      SHLIB, make, and as packages through rzig build), the
#      static-library package and a package with a .rc file (make) and a
#      plain C one (rzig build) build and load with only bin\x64 and
#      System32 on PATH; LTO is recorded, not checked (B43-2, C9), with
#      a tier-1 twin that MAKEFLAGS' assignment sends to make (N4). Every
#      OS, with no ZIG_BIN (no zig: phase 5):
#      a package with a configure script stops in the preflight with the
#      compilers' text, and with R_ZIG_NO_PREFLIGHT=1 gets past it, runs
#      its configure and fails in the compile (C26).
# What phase 3 leaves to later phases (PLAN.md): the compilers group has
# no zig (phase 5) and no flang (phase 6), so scenario 2 takes zig from
# ZIG_BIN=$ZIG and flang from the env; Windows' build-tools group has no
# usr/bin (phase 7), so scenario 3 takes sh and make from the env's
# Library/usr/bin.
# The static checks of the trees (Makeconf, the compilers are rzig, the CA
# bundle, rpaths, the glibc ceiling, the C++ runtime of R's binaries, the
# macOS floor and load commands, minimal's excluded libraries, Windows'
# Tcl/Tk and DLL closure; the groups' records and closures) read files,
# headers and load commands, which moving a tree does not change:
# verify-tree.sh and verify-toolchain.sh run them where the trees are
# built. Shared helpers: verify-helpers.sh (archive_files, tree_files,
# rzig_names, configure_marker, extract_archive, rpaths_of, needed_of,
# cxx_deps, minos_over_floor, cannot_check).
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

# The archives, in the order they are extracted: the base
# (package-standalone.sh, `pixi run package`), then the groups (`pixi run
# package-toolchain`; in CI the toolchain job's artifact, B31), each with
# the .sha256 written beside it.
base="$ROOT/dist/R-$R_VERSION-$FLAVOR-$PLAT.$ARCHIVE_EXT"
test -f "$base" || { echo "error: $base not found — run 'pixi run package' first" >&2; exit 1; }
archives=("$base")
for group in $TOOLCHAIN_GROUPS; do
  a="$ROOT/dist/R-$R_VERSION-$PLAT-$group.$ARCHIVE_EXT"
  test -f "$a" ||
    { echo "error: $a not found: run 'pixi run package-toolchain' (or download the toolchain job's artifact into dist/)" >&2; exit 1; }
  archives+=("$a")
done
for a in "${archives[@]}"; do
  (cd "$ROOT/dist" && sha256sum -c --quiet "${a##*/}.sha256") ||
    { echo "error: ${a##*/} does not match ${a##*/}.sha256" >&2; exit 1; }
done

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
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
# R_HOME/bin/toolchain holds rzig under its names and no directory: the
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
names=" $(rzig_names) "
not_rzig=""
while IFS= read -r m; do
  case "$names" in *" ${m#"$tc/"} "*) ;; *) not_rzig="$not_rzig ${m#"$tc/"}" ;; esac
done < <(grep -E "$tc_re" "$lists/base" || true)
if [ -n "$not_rzig" ]; then
  echo "error: ${base##*/} has more than rzig ($(rzig_names)) in $tc:$not_rzig (B19, B30: the groups' files are the toolchain tree's)" >&2
  exit 1
fi
# Each group archive holds only its group's directories (env.sh's
# group_dirs), as unpack-toolchain.sh requires, and no file is in two of
# the three archives.
group_lists=()
for group in $TOOLCHAIN_GROUPS; do
  a="$ROOT/dist/R-$R_VERSION-$PLAT-$group.$ARCHIVE_EXT"
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
echo "== file lists: ${base##*/} is the R tree ($(wc -l < "$lists/base" | tr -d ' ') files and links), nothing compile-time in it and only rzig in $tc; $(for g in $TOOLCHAIN_GROUPS; do printf '%s %s, ' "$g" "$(wc -l < "$lists/$g" | tr -d ' ')"; done)each under its own directories; no file in two archives"

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

# rzig's texts for a missing group, as it prints them (its name, zig-cc
# for gcc.exe too, then what is missing; then the group's first line:
# zigbuild/tools/rzig/check.zig and groups.zig, B35). starts_line <file>
# <text>: a line of the file starts with the text (CRs dropped).
no_zig_line="zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the environment's bin, PATH, python3 -m ziglang)"
no_flang_line="zig-cc: no flang (R_HOME/bin/toolchain/flang/bin, the environment's bin, PATH)"
no_make_line="zig-cc: no make on PATH"
compilers_head="Compiling needs the r-zig compilers for R $R_VERSION on $PLAT: "
build_tools_head="Building packages needs the r-zig build tools for R $R_VERSION on $PLAT: "
preflight_stop="ERROR: this package has compiled code, and the r-zig toolchain is incomplete (see above)"
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
  zig_env=(ZIG_BIN="$zig_bin" ZIG_GLOBAL_CACHE_DIR="$(cygpath -m "$ZIG_GLOBAL_CACHE_DIR")" ZIG_LOCAL_CACHE_DIR="$(cygpath -m "$ZIG_LOCAL_CACHE_DIR")")
else
  R_BINDIR="$BUNDLE_DIR/bin"
  R_BIN="$R_BINDIR/R"
  RSCRIPT="$R_BINDIR/Rscript"
  cc="$TC/zig-cc"
  fc="$TC/zig-fc"
  base_env=(HOME="$home" TMPDIR="${TMPDIR:-/tmp}")
  # zig: env.sh's $ZIG, the one the build used (ZIG_BIN, else the env's),
  # passed on as ZIG_BIN, which env -i drops (rzig would then take the
  # env's zig from PATH and test conda-forge's zig after an upstream zig's
  # build), with the caches env.sh keeps for that zig.
  zig_bin="$ZIG"
  zig_env=(ZIG_BIN="$zig_bin" ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR")
fi
test -x "$R_BIN" || { echo "error: $R_BIN missing from the extracted base" >&2; exit 1; }

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
# whole ${...} term (hence R_ZIG_TOOLS_PATH): the entry after bin\x64,
# which R CMD puts first, is the expanded path, with no ${ left, or
# R_CUSTOM_TOOLS_PATH's value when that is set (R's installer line).
if [ "$OS" = windows ]; then
  cat > "$VERIFY_DIR/path.R" <<'RCODE'
p <- strsplit(Sys.getenv("PATH"), ";", fixed = TRUE)[[1L]]
slash <- function(x) tolower(chartr("\\", "/", x))
i <- match(TRUE, endsWith(slash(p), "/bin/x64"))
got <- if (is.na(i) || i == length(p)) "" else p[[i + 1L]]
custom <- Sys.getenv("R_CUSTOM_TOOLS_PATH")
want <- if (nzchar(custom)) custom else paste0(R.home(), "/bin/toolchain/usr/bin")
if (grepl("${", got, fixed = TRUE) || slash(got) != slash(want))
    stop("the PATH entry after bin/x64 is '", got, "', not '", want, "'; PATH: ", Sys.getenv("PATH"))
cat("the PATH entry after bin/x64:", got, "\n")
RCODE
  for custom in "" "C:/r-zig-custom-tools"; do
    custom_env=()
    [ -z "$custom" ] || custom_env=(R_CUSTOM_TOOLS_PATH="$custom")
    (cd "$VERIFY_DIR" && env -i "${base_env[@]}" "${custom_env[@]}" PATH="$R_BINDIR:$sys32" \
      "$R_EXE" CMD Rscript.exe --vanilla path.R) ||
      { echo "error: under R CMD, the PATH entry after bin\\x64 is not ${custom:-R_HOME/bin/toolchain/usr/bin, expanded} (etc/Rcmd_environ, B25)" >&2; exit 1; }
  done
  echo "== R CMD's PATH: bin\\x64, then R_HOME/bin/toolchain/usr/bin (or R_CUSTOM_TOOLS_PATH)"
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

# --- Scenario 2: base + compilers -------------------------------------------
extract "${archives[1]}" "$lists/compilers"
echo "== scenario 2: base + compilers"
# flang: the env's (phase 6 puts it in the compilers group); its directory
# decides whether the Fortran checks run.
fc_dir="$(dirname "$(command -v flang 2>/dev/null || echo /nonexistent/flang)")"
mk="$RHD/etc/Makeconf"
[ "$OS" != windows ] || mk="$RHD/etc/x64/Makeconf"

# rzig's check mode with the compilers there: zig from ZIG_BIN=$ZIG (phase
# 5 puts one in the group), exit 0, and the line names it; zig-fc's, with
# the env's flang on PATH, names that flang too.
if [ -n "$ZIG" ]; then
  if [ "$OS" = windows ]; then chk_path="$R_BINDIR:$sys32"; else chk_path=/usr/bin:/bin; fi
  out="$(env -i "${base_env[@]}" "${zig_env[@]}" PATH="$chk_path" "$cc" --rzig-check | tr -d '\r')" ||
    { echo "error: ${cc##*/} --rzig-check failed with ZIG_BIN=$zig_bin" >&2; exit 1; }
  printf '%s\n' "$out" | grep -qiF -- " at $zig_bin" ||
    { printf '%s\n' "$out" >&2; echo "error: ${cc##*/} --rzig-check does not name ZIG_BIN's zig, $zig_bin" >&2; exit 1; }
  echo "   $out"
  checked="zig from ZIG_BIN"
  if [ -x "$fc_dir/flang" ]; then
    fc_shown="$fc_dir/flang"
    [ "$OS" != windows ] || fc_shown="$(cygpath -m "$fc_dir")/flang"
    out="$(env -i "${base_env[@]}" "${zig_env[@]}" PATH="$fc_dir:$chk_path" "$fc" --rzig-check | tr -d '\r')" ||
      { echo "error: ${fc##*/} --rzig-check failed with ZIG_BIN=$zig_bin and $fc_dir on PATH" >&2; exit 1; }
    printf '%s\n' "$out" | grep -qiF -- "flang at $fc_shown" ||
      { printf '%s\n' "$out" >&2; echo "error: ${fc##*/} --rzig-check does not name the flang on PATH, $fc_shown" >&2; exit 1; }
    echo "   $out"
    checked="$checked, flang from PATH"
  fi
  echo "== check mode with the compilers: exit 0, $checked"
fi

# The install preflight's other branches (B26, C26; feat-zig-pkg-build
# M4), unix: zig from ZIG_BIN=$ZIG, PATH the tree's bin alone, so no make
# (the build-tools group is not extracted yet) and no flang. The preflight
# (patch 0009, rzig's --rzig-check=package) decides as `rzig build`
# decides in install.R's hook (patch 0013): a package with C code and no
# Makevars (pfC) passes the compilers' check, needs no make, and the hook
# builds it through rzig build (RZIG_TRACE=1: `rzig build: tier 1`, no
# make output), and it loads; one whose Makevars has a rule (pfM, mkpkg's
# lib: a static library through $(AR)) needs make and stops at the build
# tools' check with rzig's reason and their text; one with a Fortran
# source, src/a.f (pfF), stops at the compilers' with no flang and their
# text; an R-only package with a configure script (pfG, configure_marker)
# stops at the build tools' with "a configure script R runs", its
# configure not run. The preflight's own ERROR line tells its stop from
# the one install.R's R CMD config (patch 0010) would make later, before
# the configure (that call needs make too), which the marker alone could
# not. None of the last three installs. (Windows: scenario 3 runs the
# preflight with no zig.)
if [ "$OS" != windows ] && [ -n "$ZIG" ]; then
  pf="$VERIFY_DIR/preflight"
  mkpkg "$pf/pk" pfC 1
  mkpkg "$pf/pk" pfM 3 lib
  mkpkg "$pf/pk" pfF 2
  printf '      subroutine pff\n      end\n' > "$pf/pk/pfF/src/a.f"
  mkdir -p "$pf/pk/pfG/R"
  printf 'Package: pfG\nVersion: 0.1\nTitle: Verify Bundle\nDescription: R only, with a configure script.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$pf/pk/pfG/DESCRIPTION"
  echo 'export(g)' > "$pf/pk/pfG/NAMESPACE"
  echo 'g <- function() 7L' > "$pf/pk/pfG/R/g.R"
  configure_marker "$pf/pk/pfG"
  mkdir -p "$pf/lib"
  # preflight_stops <package> <what is missing> <the group's first line>
  preflight_stops() {
    local rc=0
    (cd "$pf" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$BUNDLE_DIR/bin" \
      "$R_BIN" CMD INSTALL -l lib "pk/$1") > "$pf/$1.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ] || [ -e "$pf/lib/$1" ] || [ -e "$pf/pk/$1/configure-ran" ] ||
       ! starts_line "$pf/$1.log" "$2" || ! starts_line "$pf/$1.log" "$3" ||
       ! starts_line "$pf/$1.log" "$preflight_stop"; then
      cat "$pf/$1.log" >&2
      echo "error: the install preflight did not stop $1 with '$2' and '$3...' (exit $rc)" >&2
      exit 1
    fi
  }
  preflight_stops pfM "zig-cc: pfM needs make: src/Makevars has a rule or target line: '\$(SHLIB): lib/libval.a'; no make on PATH" "$build_tools_head"
  preflight_stops pfF "$no_flang_line" "$compilers_head"
  preflight_stops pfG "zig-cc: pfG needs make: a configure script R runs; no make on PATH" "$build_tools_head"
  (cd "$pf" && env -i "${base_env[@]}" "${zig_env[@]}" PATH="$BUNDLE_DIR/bin" RZIG_TRACE=1 \
    "$R_BIN" CMD INSTALL -l lib pk/pfC) > "$pf/pfC.log" 2>&1 ||
    { cat "$pf/pfC.log" >&2; echo "error: pfC (C, no Makevars) did not install with the compilers and no make" >&2; exit 1; }
  starts_line "$pf/pfC.log" "rzig build: tier 1" ||
    { cat "$pf/pfC.log" >&2; echo "error: pfC did not build through rzig build (no 'rzig build: tier 1' line)" >&2; exit 1; }
  if grep -Eq '^make(\[[0-9]+\])?[: ]' "$pf/pfC.log"; then
    cat "$pf/pfC.log" >&2; echo "error: make output in pfC's install log" >&2; exit 1
  fi
  (cd "$pf" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
    "$R_BIN" --vanilla --no-echo -e 'stopifnot(getExportedValue(loadNamespace("pfC", lib.loc = "lib"), "f")() == 1L)') ||
    { echo "error: pfC, built through rzig build, did not load" >&2; exit 1; }
  echo "== the install preflight with zig and no build tools: a C package builds through rzig build and loads; a Makevars-rule package stops with rzig's reason and the build tools' text, an R-only package with a configure script with 'a configure script R runs' and that text (its configure not run), a Fortran one with no flang and the compilers' text"
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
# x86_64 (also under Rosetta). The same zig: env.sh's $ZIG, which the
# compiler finds as env.sh did (ZIG_BIN, exported absolute, else PATH's:
# the bundle has no toolchain zig/ and no zig in its bin/, which rzig
# would try first).
# Once more with -mtune=native, which a Makevars may pass as a portable
# tuning flag: zig would take it as the CPU, so rzig drops it (dropTune).
# (verify-tree.sh checks R's own x86_64 binaries for AVX instructions.)
if [ -n "$ZIG" ]; then
  cpu_dir="$VERIFY_DIR/cpu"
  mkdir -p "$cpu_dir"
  printf '%s\n' 'double dot(const double *x, const double *y, int n)' \
    '{ double s = 0; for (int i = 0; i < n; i++) s += x[i] * y[i]; return s; }' > "$cpu_dir/cpu.c"
  # the distinct target-cpu values of an IR file, one line
  target_cpu() { { grep -o '"target-cpu"="[^"]*"' "$1" || true; } | sed 's/^"target-cpu"=//' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
  (cd "$cpu_dir" && "$ZIG" cc -mcpu=baseline -O2 -S -emit-llvm cpu.c -o want.ll &&
    "$cc" -O2 -S -emit-llvm cpu.c -o got.ll &&
    "$cc" -O2 -mtune=native -S -emit-llvm cpu.c -o tune.ll) > "$cpu_dir/log" 2>&1 ||
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
  # through zig as gcc.exe's does, with the static runtime of the flang on
  # PATH and libc++ appended.
  if command -v flang > /dev/null 2>&1; then
    argv="$(RZIG_PRINT_ARGV=1 "$fc" -shared -o x.dll a.o)"
    if ! printf '%s\n' "$argv" | grep -qi -- '/libflang_rt\.runtime\.a$' ||
       ! printf '%s\n' "$argv" | grep -qxF -- '-lc++' ||
       ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$TOP/Library/lib\$"; then
      printf '%s\n' "$argv" >&2
      echo "error: zig-fc.exe's shared link lacks the static flang runtime, -lc++ or -L<prefix>/Library/lib" >&2
      exit 1
    fi
    echo "== zig-fc.exe verified (dry run): a shared link goes through zig with the static flang runtime and -lc++"
  fi

  # An OpenMP DLL from gcc.exe alone, no make (a build tool): omp.h from
  # the group's openmp/include, the link against its openmp/lib/libomp.lib
  # (PE resolves every symbol at link time), so the DLL imports
  # libomp.dll, which then loads from the base's bin\x64 in an R whose
  # environment holds only what Windows needs and whose PATH is bin\x64
  # and System32 (hermetic-check.sh's scenario). Nothing else on PATH:
  # zig from ZIG_BIN, CONDA_PREFIX the poisoned decoy.
  if [ -n "$ZIG" ] && grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
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
  # A package's objects and .so at or below the floor too: zig stamps the
  # link, so only the objects show a compiler that ignored it (flang
  # defaults to the host SDK's version).
  check_minos() {
    [ "$OS" = macos ] || return 0
    for f in "$@"; do
      if m="$(minos_over_floor "$f")"; then
        echo "error: ${f##*/} minos $m > $MACOS_MIN" >&2
        exit 1
      fi
    done
  }

  # What a compile needs under env -i, as on a user machine: zig through
  # zig_env, make and flang from PATH, their own directories (the env's
  # bin); flang's decides whether the Fortran checks run. Every env -i
  # that compiles takes $pkg_path and zig_env. The env's make, not the
  # build-tools group's, which is not extracted yet: PLAN.md's
  # Verification has scenario 2 use the host's make from /usr/bin, and any
  # make that is not the group's stands in for it (PHASE3 C17); the env's
  # is on every machine this runs on, where a host may have none (CI's
  # containers) or Apple's 3.81 (omicron). Scenario 3 checks the group's.
  pkg_path="$(dirname "$(command -v make 2>/dev/null || echo /nonexistent/make)"):$fc_dir:/usr/bin:/bin"
  if [ -n "$ZIG" ] && [ -x "$ZIG" ]; then
    pkg_dir="$VERIFY_DIR/shlib"
    mkdir -p "$pkg_dir"
    # rzig takes ZIG_BIN only when it names a zig from the compile's own
    # directory, and otherwise quietly looks further (the toolchain's zig/,
    # the tree's bin/, then PATH's, the env's). env.sh makes
    # $ZIG absolute; this checks that the compiles below do run it: the
    # command's first word, after the ZIG_LIB_DIR= line rzig prints first
    # where it gives conda-forge's zig the libc++ mirror (every macOS env).
    rz="$(cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" RZIG_PRINT_ARGV=1 \
      "$cc" -c a.c | grep -v '^ZIG_LIB_DIR=' | sed -n 1p)"
    [ "$rz" = "$ZIG" ] || { echo "error: the bundle's zig-cc runs '$rz', not the build's zig $ZIG" >&2; exit 1; }
    echo "== the bundle's compilers run the build's zig, $ZIG"

    # Each shape below is built twice: through R CMD SHLIB, which is make
    # (and the path run-time compilation takes: Rcpp's sourceCpp, inline),
    # and as a package through R CMD INSTALL, which builds these shapes
    # through rzig build (patch 0013, the default builder; feat-zig-pkg-build
    # N1), with the same checks on both libraries. shape_pkg <name>
    # <source>... [-- <Makevars line>...] makes the package (useDynLib, no R
    # code) under $shapes/<name>, installs it with the SHLIB runs' env -i
    # (PATH $shape_path, $pkg_path unless set; shape_env adds variables)
    # plus RZIG_TRACE=1, requires `rzig build: tier 1` in its log and no
    # make output, and sets shape_so to its library; shape_load <name>
    # <R code> loads the installed package with PATH=/usr/bin:/bin.
    shapes="$pkg_dir/pkgs"
    mkdir -p "$shapes/lib"
    shape_path=""
    shape_env=()
    shape_pkg() {
      local name="$1" d="$shapes/$1"; shift
      rm -rf "$d"; mkdir -p "$d/src"
      printf 'Package: %s\nVersion: 0.1\nTitle: Verify Bundle\nDescription: A shape R CMD INSTALL builds through rzig build.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$name" > "$d/DESCRIPTION"
      printf 'useDynLib(%s)\n' "$name" > "$d/NAMESPACE"
      while [ $# -gt 0 ] && [ "$1" != -- ]; do cp "$1" "$d/src/"; shift; done
      if [ "${1:-}" = -- ]; then shift; printf '%s\n' "$@" > "$d/src/Makevars"; fi
      (cd "$shapes" && env -i "${base_env[@]}" PATH="${shape_path:-$pkg_path}" "${zig_env[@]}" "${shape_env[@]}" RZIG_TRACE=1 \
        "$R_BIN" CMD INSTALL -l lib "$name") > "$shapes/$name.log" 2>&1 ||
        { cat "$shapes/$name.log" >&2; echo "error: R CMD INSTALL of $name (a shape through rzig build) failed" >&2; exit 1; }
      starts_line "$shapes/$name.log" "rzig build: tier 1" ||
        { cat "$shapes/$name.log" >&2; echo "error: R CMD INSTALL of $name did not build through rzig build (no 'rzig build: tier 1')" >&2; exit 1; }
      if grep -Eq '^make(\[[0-9]+\])?[: ]' "$shapes/$name.log"; then
        cat "$shapes/$name.log" >&2; echo "error: make output in $name's install log" >&2; exit 1
      fi
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
    (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
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
    # hid the shared runtime once (2026-09-30, macOS slim). minimal empties
    # FLIBS (no Fortran compiler with the wheel), so it is skipped there.
    if grep -q '^FLIBS = .*flang_rt' "$mk" && [ -x "$fc_dir/flang" ]; then
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
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
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
      # through zig, as zig-cc does, with the static runtime of the flang on
      # PATH (flang's own driver: "cannot find -lflang_rt.runtime"): no
      # shared runtime, no rpath, the macOS floor, and it loads.
      mkdir -p "$pkg_dir/fl"
      cp "$pkg_dir/fs.f" "$pkg_dir/fl/fl.f"
      echo 'USE_FC_TO_LINK =' > "$pkg_dir/fl/Makevars"
      (cd "$pkg_dir/fl" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
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
      shape_pkg fl "$pkg_dir/fl/fl.f" -- 'USE_FC_TO_LINK ='
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

    # FC names zig-fc whether or not a flang is installed: with none (not
    # in the toolchain's flang/, the tree's bin or PATH), a Fortran compile
    # stops at once with exit 127 and the compilers group's text, which
    # names flang (feat-standalone-toolchain B35; rzig never reads
    # R_ZIG_TOOLCHAIN_HINT).
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
    # $(BLAS_LIBS) $(FLIBS)) with no flang on PATH, as with the wheel: the
    # compilers (rzig) drop -lflang_rt.runtime: nothing was compiled by flang.
    # PATH: the env's make alone (above: the group's comes in scenario 3), no flang.
    mkdir -p "$pkg_dir/cf/bin"
    ln -sf "$(command -v make)" "$pkg_dir/cf/bin/make"
    printf '%s\n' '#include <R.h>' 'void cfl(int *n) { *n = 7; }' > "$pkg_dir/cf/cf.c"
    printf '%s\n' 'PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)' > "$pkg_dir/cf/Makevars"
    (cd "$pkg_dir/cf" && env -i "${base_env[@]}" PATH="$pkg_dir/cf/bin:/usr/bin:/bin" "${zig_env[@]}" \
      "$R_BIN" CMD SHLIB -o cf.so cf.c > shlib.log 2>&1) || { cat "$pkg_dir/cf/shlib.log" >&2; echo "error: a C package using \$(FLIBS) failed to link with no flang on PATH" >&2; exit 1; }
    (cd "$pkg_dir/cf" && env -i "${base_env[@]}" PATH=/usr/bin:/bin \
      "$R_BIN" --vanilla --no-echo -e 'dyn.load("cf.so"); stopifnot(.C("cfl", n = 0L)$n == 7L)')
    echo "== compiled package verified: \$(FLIBS) links with no Fortran compiler (C; R CMD SHLIB, make)"
    # as a package: no make and no flang on PATH at all
    shape_path="/usr/bin:/bin"
    shape_pkg cf "$pkg_dir/cf/cf.c" -- 'PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)'
    shape_path=""
    shape_load cf 'stopifnot(.C("cfl", n = 0L, PACKAGE = "cf")$n == 7L)'
    echo "== compiled package verified: \$(FLIBS) links with no Fortran compiler (C; R CMD INSTALL, rzig build, no make on PATH)"

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
      (cd "$pkg_dir/omp" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
        "$R_BIN" CMD SHLIB -o omp.so omp.c > shlib.log 2>&1 && rm Makevars &&
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
        "$R_BIN" CMD SHLIB -o probe.so probe.c >> shlib.log 2>&1 && cd "$pkg_dir/lomp" &&
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
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
    # omp_lib` compiles against the omp_lib.mod of the flang on PATH
    # (flang-rt-zig's, LLVM 23, the release of the llvm-openmp pixi.toml
    # pins), and the package links the tree's libomp through rzig, as the C
    # one does (and, as there, must record it itself). R-exts' two forms:
    # $(SHLIB_OPENMP_FFLAGS) on the compile and $(SHLIB_OPENMP_CFLAGS) on
    # the link, which the C compiler does (fomp); and USE_FC_TO_LINK with
    # $(SHLIB_OPENMP_FFLAGS) on both, zig-fc linking (fompfc). FOMP_R
    # checks that a parallel region ran on two of libomp's threads. flang
    # is on PATH for the compile only: the load runs with /usr/bin:/bin.
    if grep -q '^SHLIB_OPENMP_FFLAGS = *-' "$mk" && [ -x "$fc_dir/flang" ]; then
      fomp_src "$pkg_dir"
      for d in fomp fompfc; do
        (cd "$pkg_dir/$d" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" \
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
      shape_pkg fomp "$pkg_dir/fomp/fomp.f" -- 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)'
      fomp_pkg_so="$shape_so"
      shape_pkg fompfc "$pkg_dir/fompfc/fompfc.f" -- 'USE_FC_TO_LINK =' 'PKG_FFLAGS = $(SHLIB_OPENMP_FFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_FFLAGS)'
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
    fi

    # rzig never reads CONDA_PREFIX (F3b): an activated env R is not
    # installed in adds nothing. Two decoys: the env this check runs in
    # (real headers and libraries, a conda-meta) and a poisoned one
    # (#error in omp.h and zlib.h, junk libraries). The C++ package, and the
    # OpenMP one where the tree has OpenMP, rebuild with each as
    # CONDA_PREFIX: no rpath, and rzig's command lines name neither.
    decoy="$VERIFY_DIR/decoy"
    mkdir -p "$decoy/conda-meta" "$decoy/include" "$decoy/lib"
    printf '#error decoy CONDA_PREFIX\n' > "$decoy/include/omp.h"; cp "$decoy/include/omp.h" "$decoy/include/zlib.h"
    printf 'junk' > "$decoy/lib/libomp.so"; cp "$decoy/lib/libomp.so" "$decoy/lib/libz.so"
    for cpfx in "$decoy" ${CONDA_PREFIX:+"$CONDA_PREFIX"}; do
      rm -f "$pkg_dir/rp.so" "$pkg_dir/rp.o" "$pkg_dir/omp/omp.so" "$pkg_dir/omp/omp.o"
      (cd "$pkg_dir" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" CONDA_PREFIX="$cpfx" \
        "$R_BIN" CMD SHLIB -o rp.so rp.cpp > decoy.log 2>&1) || { cat "$pkg_dir/decoy.log" >&2; echo "error: R CMD SHLIB failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
      sos="$pkg_dir/rp.so"
      if [ -f "$pkg_dir/omp/omp.c" ]; then
        printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$pkg_dir/omp/Makevars"
        (cd "$pkg_dir/omp" && env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" CONDA_PREFIX="$cpfx" \
          "$R_BIN" CMD SHLIB -o omp.so omp.c > decoy.log 2>&1) || { cat "$pkg_dir/omp/decoy.log" >&2; echo "error: the OpenMP package failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
        sos="$sos $pkg_dir/omp/omp.so"
      fi
      # the C++ package through rzig build as well, with the decoy
      shape_env=(CONDA_PREFIX="$cpfx")
      shape_pkg rp "$pkg_dir/rp.cpp"
      shape_env=()
      sos="$sos $shape_so"
      for so in $sos; do
        so_rp="$(rpaths_of "$so" | tr '\n' ' ')"
        [ -z "$so_rp" ] || { echo "error: ${so##*/} built with CONDA_PREFIX=$cpfx records rpaths: $so_rp" >&2; exit 1; }
      done
      # (zig itself, and its lib dir, may live in the build env)
      argv="$(cd "$pkg_dir" && for a in "-fopenmp -c a.c" "-shared -fopenmp -o x.so a.o -lz" "-o conftest conftest.c -lz"; do
        env -i "${base_env[@]}" PATH="$pkg_path" "${zig_env[@]}" CONDA_PREFIX="$cpfx" RZIG_PRINT_ARGV=1 "$cc" $a; done |
        grep -vxF -- "$ZIG" | grep -v '^ZIG_LIB_DIR=')"
      if printf '%s\n' "$argv" | grep -F -- "$cpfx"; then
        echo "error: rzig's command lines name CONDA_PREFIX=$cpfx" >&2; exit 1
      fi
      printf '%s\n' "$argv" | grep -qxF -- "-L$(cd "$BUNDLE_DIR" && pwd -P)/lib" || { printf '%s\n' "$argv" >&2; echo "error: rzig's link lines lack the tree's -L" >&2; exit 1; }
    done
    echo "== CONDA_PREFIX ignored: the C++ package (through make and through rzig build; and the OpenMP one, where offered) builds with a poisoned and with the build env as CONDA_PREFIX, no rpath, and rzig's command lines name neither"
  else
    echo "== compiled-package checks skipped (no zig: ZIG_BIN unset, none on PATH)"
  fi
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
## verify-bundle.sh, scenario 3: on unix the make R runs is the build-tools
## group's (Sys.which, and its --version: the version its SOURCES records,
## the first argument); then the packages, two at a time.
windows <- .Platform$OS.type == "windows"
if (!windows) {
    make <- Sys.which("make")
    group <- file.path(R.home(), "bin", "toolchain", "usr", "bin", "make")
    if (!nzchar(make) || normalizePath(make) != normalizePath(group))
        stop("Sys.which(\"make\") is '", make, "', not the build-tools group's ", group)
    v <- system2("make", "--version", stdout = TRUE)[1L]
    want <- paste("GNU Make", commandArgs(trailingOnly = TRUE)[1L])
    if (!identical(v, want)) stop("make --version says '", v, "', not '", want, "'")
    cat("make:", make, "-", v, "\n")
}
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
  if [ -n "$ZIG" ] && [ -x "$ZIG" ]; then
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
  # Windows. sh and make: the env's Library/usr/bin (m2-bash, m2-make)
  # until the group has its usr/bin (phase 7). Library/bin is not on PATH,
  # so none of the env's other tools (its binutils, zig, pkg-config) can
  # stand in for what Makeconf.win names; zig comes from ZIG_BIN.
  [ -n "${CONDA_PREFIX:-}" ] ||
    { echo "error: CONDA_PREFIX is not set: run this through pixi (scenario 3 takes sh and make from the env's Library/usr/bin until phase 7)" >&2; exit 1; }
  usr_bin="$(cygpath -u "$CONDA_PREFIX")/Library/usr/bin"
  for t in make sh; do
    [ -x "$usr_bin/$t" ] || { echo "error: no $t in $usr_bin (m2-make, m2-bash)" >&2; exit 1; }
  done
  bt_path="$R_BINDIR:$usr_bin:$sys32"
  mk_m="$(cygpath -m "$mk")"
  tc_m="$(cygpath -m -l "$TC")"
  lower() { tr '[:upper:]' '[:lower:]'; }

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
  usr_m="$(cygpath -m -l "$usr_bin")"
  for want in "make at $usr_m/make" "sh at $usr_m/sh" "binutils at $tc_m/binutils"; do
    printf '%s\n' "$out" | grep -qiF -- "$want" ||
      { echo "error: R CMD gcc.exe --rzig-check=build-tools says '$out', which lacks '$want'" >&2; exit 1; }
  done
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
  if [ -n "$ZIG" ]; then
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
  # omp_lib`). They build through make with no environment but the
  # tree's: R_ZIG_EXTRA_ENV unset and the poisoned decoy as CONDA_PREFIX;
  # PATH as above, and for fomp and fompfc flang's own directory last
  # (the env's Library/bin until phase 6 puts flang in the group; last, so
  # that its tools come after everything else, and Makeconf.win names
  # each binutils tool by its path). Each but the probe must import
  # libomp.dll (PE resolves every symbol at link time, so that is
  # openmp/lib/libomp.lib). Then they load in an R whose environment holds
  # only what Windows needs and whose PATH is bin\x64 and System32
  # (hermetic-check.sh's scenario), so libomp.dll comes from the base.
  if [ -n "$ZIG" ] && grep -Eq '^SHLIB_OPENMP_CFLAGS = *-' "$mk"; then
    ow="$VERIFY_DIR/omp-win"
    mkdir -p "$ow/omp" "$ow/probe" "$ow/lomp"
    printf '%s\n' '#include <omp.h>' '#include <R.h>' 'void ompn(int *n) { *n = omp_get_max_threads(); }' > "$ow/omp/omp.c"
    printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$ow/omp/Makevars"
    printf '%s\n' '#include <omp.h>' 'int ompprobe(void) { return 0; }' > "$ow/probe/probe.c"
    printf '%s\n' 'extern int omp_get_max_threads(void);' 'void lompn(int *n) { *n = omp_get_max_threads(); }' > "$ow/lomp/lomp.c"
    printf '%s\n' 'PKG_LIBS = -lomp' > "$ow/lomp/Makevars"
    printf '%s\n' 'dyn.load("omp/omp.dll"); dyn.load("lomp/lomp.dll")' 'n <- c(.C("ompn", n = 0L)$n, .C("lompn", n = 0L)$n)' 'stopifnot(n >= 1L)' 'cat("omp, lomp: omp_get_max_threads() =", n, "\n")' > "$ow/load.R"
    pkgs="omp lomp"
    if grep -Eq '^SHLIB_OPENMP_FFLAGS = *-' "$mk" && [ -x "$fc_dir/flang" ]; then
      fomp_src "$ow"
      printf '%s\n' "$FOMP_R" >> "$ow/load.R"
      pkgs="omp lomp fomp fompfc"
    fi
    for d in probe $pkgs; do
      src="$d.c"; p="$bt_path"
      if [ ! -f "$ow/$d/$src" ]; then src="$d.f"; p="$bt_path:$fc_dir"; fi
      (cd "$ow/$d" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$p" \
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
    echo "== compiled packages verified: OpenMP with the groups (probe $pkgs: omp.h, libomp.lib from openmp/; libomp.dll from bin\\x64 at load; no import library left beside a DLL)"
  fi

  if [ -n "$ZIG" ]; then
    (cd "$bt" && env -i "${base_env[@]}" "${zig_env[@]}" CONDA_PREFIX="$(cygpath -w "$decoy")" PATH="$bt_path" RZIG_TRACE=1 \
      "$RSCRIPT" --vanilla bt.R) > "$bt/bt.log" 2>&1 ||
      { cat "$bt/bt.log" >&2; echo "error: the packages ($bt_pkgs) did not build with the base and the groups (btA through rzig build, btLib and btRc through make)" >&2; exit 1; }
    (cd "$bt" && env -i "${base_env[@]}" PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla bt-load.R) ||
      { echo "error: the packages ($bt_pkgs) did not load with PATH = bin\\x64 + System32" >&2; exit 1; }
    rc_dll="$(find "$bt/lib/btRc/libs" -name btRc.dll | head -1)"
    "$TC/binutils/objdump.exe" -h "$rc_dll" | grep -q 'rsrc' ||
      { echo "error: btRc.dll has no .rsrc section: its .rc file did not reach the link" >&2; exit 1; }
    echo "== packages built under the default builder, install.packages with Ncpus = 2: btA through rzig build, btLib and btRc through make (a static library through rzig's zig-ar.exe and zig-ranlib.exe; a .rc file through \$(RESCOMP), its resources in btRc.dll), each from its log; load with PATH = bin\\x64 + System32"

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
  else
    echo "== package builds skipped (no zig: ZIG_BIN unset, none on PATH)"
  fi
fi

# The install preflight and R_ZIG_NO_PREFLIGHT (B26, C26), every OS: with
# both groups and no zig (ZIG_BIN unset; the compilers group has none
# until phase 5), a package with C code and a configure script stops in
# the preflight with the compilers' text, its configure not run; with
# R_ZIG_NO_PREFLIGHT=1 it gets past the preflight, its configure runs and
# leaves its marker, and the compile then fails with rzig's no-zig line.
# Here, not with the base alone: the install runs R CMD config before
# configure (for CC and the other variables), and R CMD config needs the
# build tools (patch 0010; on Windows the binutils too). PATH: unix
# /usr/bin:/bin, the group's make first (etc/Renviron); Windows as for the
# builds above. A zig of the host's own (scenario 1) would let the compile
# through: then this is skipped with a note.
if [ -n "$host_zig" ]; then
  echo "   note: the preflight and R_ZIG_NO_PREFLIGHT not checked: this host's $host_zig is on PATH"
else
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
  echo "== the install preflight with no zig: a package stops before its configure with the compilers' text; with R_ZIG_NO_PREFLIGHT=1 its configure runs and the compile fails with no zig"
fi
echo "== standalone archives verified ($OS/$FLAVOR): the base alone, + compilers, + build-tools"
