#!/usr/bin/env bash
# Package-build parity (feat-zig-pkg-build PLAN.md, milestone 4 and the
# consolidation with phase 3, M3): R CMD INSTALL through `rzig build`
# (install.R's hook, patch 0013) must give what the make path gives.
#
# On the compile tree, env.sh's $COMPILE_TREE (the installed tree with the
# toolchain tree's openmp/ and build tools beside rzig, compile-tree.sh;
# `pixi run pkg-parity` makes it first), so that both paths see the same
# rzig environments (rzig counts openmp/ where it is: on the base alone
# every compile line would lack its -I), for cli (C), digest (C and C++),
# quadprog (Fortran), Rcpp (C++) and, on unix, minqa (C++ and Fortran,
# linked through SHLIB_CXXLD with FLIBS; its Makevars.win's $(shell) keeps
# it on make on Windows), fetched from CRAN once into
# build/pkg-parity-<flavor>/src:
#   - the zig path (`RZIG_TRACE=1`): the log says `rzig build: tier 1`
#     and holds no recipe make echoed (verify-helpers.sh's make_recipes);
#   - the make path (`R_ZIG_PKG_BUILDER=make`, also traced) builds the
#     same package into a second library, its log no `rzig build:` line
#     and make's echoed compiles;
#   - the two libraries' exported symbols are identical (nm; Windows:
#     objdump's export table);
#   - rzig received the same command lines on both paths: every compile
#     and the link, each line's words in order, the lines sorted, quotes
#     dropped, and each path cut to its file name while a flag's prefix
#     stays (`-I`, `-L`, `-Wl,-rpath,`, `--out-implib=`: an -I that became
#     an -L, or a dropped rpath, still shows) [tests-T7]. A path's
#     directory is not compared, so the zig path's compiles are also
#     asserted to name their source relative to src/, `-c <file>`, as
#     make's do: an absolute source would key zig's global cache per
#     install [tests-T1, tests-T7]. The known
#     differences are normalised away: on macOS the
#     `-Xlinker -install_name -Xlinker <pkg>.so` only rzig passes (make's
#     linker derives the same name from -o), on Windows the .def file's name (`tmp.def`
#     from nm | sed, `<pkg>.def` from `rzig def`), and the directories of
#     the paths (the zig path's objects and output are in its build root,
#     obj/<n>/ and <root>/<output>; Windows: rzig's
#     `--out-implib=<output>.rzig.lib`, absolute there) [tests-3];
#     the `ZIG_LIB_DIR=<mirror>` word rzig prints first where it gives
#     conda-forge's zig the libc++ mirror (every macOS env) is stripped,
#     and the make path's `--version` probes are left out;
#   - a smoke script loads and exercises the packages from each library
#     and prints the same values;
#   - the caches: tier 1 runs no zig build (tier1.zig), so rzig's cache
#     holds only its own kinds of entry, no build-runner-* and nothing of
#     an install's, and no dso-fini-* or cfguard-*: the links name R's
#     link object beside rzig instead (verify-helpers.sh's rzig_cache_odd
#     and link_object_named; feat-r-home-link-objects), and no tier-1 log
#     holds a zig build command (feat-tier1-engine); a kept build root
#     (RZIG_KEEP_ROOT=1) holds the plan, the objects and the library and
#     no zig build cache (N3); a second install of the cli tarball, which
#     R unpacks into a new directory each time as install.packages does,
#     adds as many entries to zig's global cache as make's second install
#     does: rzig build's compiles are keyed as make's are [tests-T1] (none
#     with zig 0.16; zig 0.17 keys a source by its absolute path), and its
#     time is printed against make's;
#     with ZIG_LOCAL_CACHE_DIR set, zig cc's objects are there, and the
#     build root still goes [preflight-PF-8]; two tier-1 packages
#     installed at once by install.packages(Ncpus = 2), from a cold rzig
#     cache, both build.
# Then R CMD SHLIB (feat-shlib-rzig-build: the same hook, rzig build's
# SHLIB mode), on the compile tree, for the shapes run-time compilation
# takes (pkgbuild's probe, Rcpp's sourceCpp, cpp11, TMB in process,
# Fortran, Fortran modules, argv's PKG_LIBS, an output in a subdirectory),
# each with the default builder and with R_ZIG_PKG_BUILDER=make, compared
# as the packages are; pkgload's compilation-database dry run (its
# injected quote goes to make -n; rzig's own dry run parses the same),
# R_ZIG_PKG_BUILDER=zig on a call that needs make, and two calls at once.
# Then the tier-2 fixture (.github/devdocs/feat-zig-pkg-build/proto/
# zighello, a zig package: `rzig build: tier 2`, `hello(21L)` is 42), its
# twin with a URL dependency in src/build.zig.zon (refused: tier 2 builds
# offline, N6; no build root left [preflight-PF-3]), zighello under a
# MAKEFLAGS assignment (tier 2 still: no make build to differ from) and
# with a foreign CC in a user Makevars (`src/build.zig cannot be built by
# make`, a failure, never the make path [preflight-PF-1]), the tier-3
# negative (cli with a `configure` script falls through to make; with
# R_ZIG_PKG_BUILDER=zig that is an error; rzig build is asked once), all
# on the compile tree; and,
# on the base alone ($PREFIX: rzig and nothing else in
# R_HOME/bin/toolchain), an install with no make on PATH (unix: a
# directory holding only sh, zig and flang; Windows: System32 plus a copy
# of flang, zig through ZIG_BIN) [tests-T10, phase3-P3-4]: the install
# preflight (patch 0009, `--rzig-check=package`) asks a tier-1 package
# for the compilers alone, and the hook builds it.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

case "$OS" in
  linux|macos|windows) ;;
  *) echo "pkg-parity: unsupported OS '$OS'" >&2; exit 1 ;;
esac
TREE="$COMPILE_TREE"
BASE="$PREFIX"
if command -v cygpath > /dev/null 2>&1; then TREE="$(cygpath -u "$TREE")"; BASE="$(cygpath -u "$BASE")"; fi
if [ "$OS" = windows ]; then
  RH_SUB=Library/lib/R; R_SUB=bin/x64/R.exe; RSCRIPT_SUB=bin/x64/Rscript.exe; SO=dll; LIBSUB=libs/x64
else
  RH_SUB=lib/R; R_SUB=bin/R; RSCRIPT_SUB=bin/Rscript; SO=so; LIBSUB=libs
fi
RH="$TREE/$RH_SUB"; R_EXE="$RH/$R_SUB"; RSCRIPT="$RH/$RSCRIPT_SUB"
BASE_RH="$BASE/$RH_SUB"; BASE_R_EXE="$BASE_RH/$R_SUB"
test -x "$R_EXE" || { echo "error: no R at $R_EXE; run 'pixi run compile-tree' first (pixi run pkg-parity does)" >&2; exit 1; }
test -x "$BASE_R_EXE" || { echo "error: no R at $BASE_R_EXE; run 'pixi run build' first" >&2; exit 1; }
for rh in "$RH" "$BASE_RH"; do
  test -x "$rh/bin/toolchain/rzig" || test -x "$rh/bin/toolchain/rzig.exe" || { echo "error: $rh/bin/toolchain has no rzig" >&2; exit 1; }
done
# the compile tree has the build tools, the base must not
if [ "$OS" != windows ]; then
  test -x "$RH/bin/toolchain/usr/bin/make" || { echo "error: $RH/bin/toolchain/usr/bin has no make: not a compile tree" >&2; exit 1; }
  test ! -e "$BASE_RH/bin/toolchain/usr" || { echo "error: $BASE_RH/bin/toolchain has usr/: not the base alone" >&2; exit 1; }
fi

PKGS="cli digest quadprog Rcpp"
[ "$OS" = windows ] || PKGS="$PKGS minqa"
WORK="$BUILD_DIR/pkg-parity-$FLAVOR"
SRC="$WORK/src"
ZIGHELLO="$ROOT/.github/devdocs/feat-zig-pkg-build/proto/zighello"
rm -rf "$WORK/lib-zig" "$WORK/lib-make" "$WORK/lib-nomake" "$WORK/logs" "$WORK/work" "$WORK/cache"
mkdir -p "$SRC" "$WORK/lib-zig" "$WORK/lib-make" "$WORK/lib-nomake" "$WORK/logs" "$WORK/work" "$WORK/cache"
cd "$WORK"

# A path as R.exe wants it on Windows (msys converts most arguments, not
# all); unchanged elsewhere.
wpath() { if [ "$OS" = windows ]; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
# Nothing of the caller's selects a path, a compiler or a cache
# (ZIG_LOCAL_CACHE_DIR would be zig cc's and tier 2's cache): rzig's own
# cache is here under $WORK/cache, emptied above, where the checks below
# can see it.
unset R_ZIG_PKG_BUILDER MAKEFLAGS ZIG_LOCAL_CACHE_DIR
export R_MAKEVARS_USER="$(wpath "$WORK/no-such-makevars")"
export RZIG_TRACE=1
export XDG_CACHE_HOME="$(wpath "$WORK/cache")"
RZIG_CACHE="$WORK/cache/r-zig"

fail() { echo "error: $*" >&2; exit 1; }
# `R CMD INSTALL -l <lib> <pkg>` with the log in logs/<name>.log; prints
# the seconds taken; returns R's status.
install_pkg() { # lib pkgpath logname [extra args]
  local lib="$1" pkg="$2" log="$3"; shift 3
  local s e rc=0
  s=$(date +%s)
  "$R_EXE" CMD INSTALL "$@" -l "$(wpath "$lib")" "$(wpath "$pkg")" > "$WORK/logs/$log.log" 2>&1 || rc=$?
  e=$(date +%s); echo "$((e - s))"
  return $rc
}
# The exported symbols of a shared library, sorted.
exports_of() {
  case "$OS" in
    linux) nm -D --defined-only "$1" | awk '{print $3}' ;;
    macos) nm -gU "$1" | awk '{print $3}' ;;
    windows) llvm-objdump -p "$1" | awk '/^ Ordinal +RVA +Name$/ {f=1; next} f && NF == 0 {exit} f {print $NF}' ;;
  esac | LC_ALL=C sort
}
# rzig's command lines from a traced install log, normalised (see the
# header) and sorted: its self, environment and cache lines and a
# `--version` word (the make path's compiler probes; a
# -Wl,--version-script= stays) left out; a path keeps its flag's prefix
# (-I, -L, -Wl,<words>, and --<option>=, also after -Wl,) and its file
# name, its directory dropped whatever it is: the source operand's is
# checked by abs_sources below [tests-T7].
argv_of() {
  tr -d '\r' < "$1" \
    | grep -E '^(zig-cc|zig-cxx|zig-fc): ' \
    | grep -v -E -- '^zig-(cc|cxx|fc): (self|environment|cache) |(^| )--version( |$)' \
    | sed -E 's/^(zig-(cc|cxx|fc): )ZIG_LIB_DIR=[^ ]+ /\1/' \
    | tr -d "'\"" \
    | sed -E 's#(^| )(-[IL]|-Wl,([^ ,]*,)*(--?[A-Za-z-]+=)?|--?[A-Za-z-]+=)?[^ ]*[\\/]([^\\/ ]+)#\1\2\5#g; s/ -Xlinker -install_name -Xlinker [^ ]+//; s/[^ ]*\.def( |$)/X.def\1/' \
    | LC_ALL=C sort
}
# The zig path's compiles in traced install log $1 that name their source
# by an absolute path (`-c /...`, Windows `-c C:...`), one per line: none,
# as make names it from src/ [tests-T1, tests-T7]. (grep reads to the
# end, no -q: pipefail [tests-SIGPIPE-1].)
abs_sources() {
  tr -d '\r' < "$1" | grep -E '^zig-(cc|cxx|fc): ' | grep -E -- " -c ['\"]?(/|[A-Za-z]:)" || true
}
# Entries in zig's global cache's o/ (the objects zig cc keeps), a count.
global_entries() { ls "$ZIG_GLOBAL_CACHE_DIR/o" 2> /dev/null | wc -l | tr -d ' '; }
# no_runner <what> [<traced log>]: tier 1 runs no zig build (tier1.zig):
# rzig's cache holds its own kinds of entry alone (rzig_cache_odd: no
# build-runner-*, nothing of an install's, no link object; with the log,
# the cache rzig traced is $RZIG_CACHE), the log no zig build command
# (feat-tier1-engine), and its link names R's link object
# (link_object_named; feat-r-home-link-objects).
no_runner() {
  local odd
  odd="$(rzig_cache_odd "$RZIG_CACHE" "${2:-}")"
  [ -z "$odd" ] || fail "$1: rzig's cache ($RZIG_CACHE): $(printf '%s' "$odd" | tr '\n' ' ')(tier 1 runs no zig build; an install's files belong in its build root; the link objects are R_HOME/bin/toolchain's; rzig's trace names its cache)"
  [ -z "${2:-}" ] || ! grep -q -- ' build --build-file ' "$2" || fail "$1: tier 1 ran zig build ($2)"
  [ -z "${2:-}" ] || link_object_named "$2" || fail "$1: no traced link names R_HOME/bin/toolchain/$(link_object) ($2)"
}

# --- the fixtures, from CRAN once -------------------------------------------
have_all=1
for p in $PKGS; do ls "$SRC/${p}_"*.tar.gz > /dev/null 2>&1 || have_all=0; done
if [ "$have_all" = 0 ]; then
  echo "== fetching $PKGS from CRAN into $SRC"
  PKG_PARITY_SRC="$(wpath "$SRC")" PKG_PARITY_PKGS="$PKGS" "$RSCRIPT" --vanilla -e '
    pkgs <- strsplit(Sys.getenv("PKG_PARITY_PKGS"), " ")[[1]]; dest <- Sys.getenv("PKG_PARITY_SRC")
    options(timeout = 300)
    for (attempt in 1:3) {
      got <- tryCatch(download.packages(pkgs, destdir = dest, repos = "https://cloud.r-project.org", type = "source", quiet = TRUE),
                      error = function(e) { message("download: ", conditionMessage(e)); NULL })
      if (!is.null(got) && nrow(got) == length(pkgs)) break
      if (attempt == 3) stop("could not download ", paste(pkgs, collapse = " "), " from CRAN")
      Sys.sleep(20)
    }' || fail "fetching the fixtures failed"
fi
tarball_of() { ls "$SRC/${1}_"*.tar.gz | head -1; }

# --- tier 1: both paths, compared, on the compile tree ----------------------
echo "== tier 1: R CMD INSTALL through rzig build, and through make ($OS/$FLAVOR, the compile tree)"
for p in $PKGS; do
  t="$(tarball_of "$p")"
  tz=$(install_pkg "$WORK/lib-zig" "$t" "$p-zig") || { tail -20 "$WORK/logs/$p-zig.log" >&2; fail "$p: the zig path failed"; }
  grep -q "rzig build: tier 1" "$WORK/logs/$p-zig.log" || fail "$p: the zig path did not report 'rzig build: tier 1' (logs/$p-zig.log)"
  [ -z "$(make_recipes "$WORK/logs/$p-zig.log")" ] || fail "$p: a recipe make echoed in the zig path's log"
  grep -q '^using C compiler\|^using C++ compiler\|^using Fortran compiler' "$WORK/logs/$p-zig.log" || fail "$p: no 'using ... compiler' line in the zig path's log"
  no_runner "$p" "$WORK/logs/$p-zig.log"
  tm=$(R_ZIG_PKG_BUILDER=make install_pkg "$WORK/lib-make" "$t" "$p-make") || { tail -20 "$WORK/logs/$p-make.log" >&2; fail "$p: the make path failed"; }
  grep -q "rzig build:" "$WORK/logs/$p-make.log" && fail "$p: R_ZIG_PKG_BUILDER=make still ran rzig build"
  [ -n "$(make_recipes "$WORK/logs/$p-make.log")" ] || fail "$p: no compile make echoed in the make path's log"
  z="$WORK/lib-zig/$p/$LIBSUB/$p.$SO"; m="$WORK/lib-make/$p/$LIBSUB/$p.$SO"
  test -f "$z" || fail "$p: no $z"; test -f "$m" || fail "$p: no $m"
  exports_of "$z" > "$WORK/logs/$p-exports-zig"; exports_of "$m" > "$WORK/logs/$p-exports-make"
  n=$(wc -l < "$WORK/logs/$p-exports-zig" | tr -d ' ')
  [ "$n" -gt 0 ] || fail "$p: no exported symbol read from $z"
  cmp -s "$WORK/logs/$p-exports-zig" "$WORK/logs/$p-exports-make" || { diff "$WORK/logs/$p-exports-zig" "$WORK/logs/$p-exports-make" | head -20 >&2; fail "$p: the exported symbols differ between the zig and the make build"; }
  argv_of "$WORK/logs/$p-zig.log" > "$WORK/logs/$p-argv-zig"; argv_of "$WORK/logs/$p-make.log" > "$WORK/logs/$p-argv-make"
  a=$(wc -l < "$WORK/logs/$p-argv-zig" | tr -d ' ')
  [ "$a" -gt 1 ] || fail "$p: no rzig command lines in the zig path's log (RZIG_TRACE)"
  cmp -s "$WORK/logs/$p-argv-zig" "$WORK/logs/$p-argv-make" || { diff "$WORK/logs/$p-argv-zig" "$WORK/logs/$p-argv-make" | head -20 >&2; fail "$p: rzig's command lines differ between the zig and the make path"; }
  [ -z "$(abs_sources "$WORK/logs/$p-zig.log")" ] || { abs_sources "$WORK/logs/$p-zig.log" | head -3 >&2; fail "$p: rzig build compiled a source by its absolute path (logs/$p-zig.log): compiles must name it relative to src/, as make does"; }
  printf '   %-9s zig %3ss, make %3ss: %s exports and %s rzig command lines identical\n' "$p" "$tz" "$tm" "$n" "$a"
  [ "$p" != cli ] || cli_make=$tm
done

cat > "$WORK/work/smoke.R" <<'EOF'
lib <- commandArgs(TRUE)[1]
.libPaths(c(lib, .libPaths()))
pkgs <- strsplit(commandArgs(TRUE)[2], " ")[[1]]
chk <- function(name, expr) { v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e))); cat(sprintf("%-12s %s\n", name, paste(format(v), collapse = " "))) }
library(cli); chk("cli", nchar(cli::rule()) > 10); chk("cli-md5", cli::hash_md5("abc"))
library(digest); chk("digest", digest::digest("abc", algo = "sha256", serialize = FALSE))
library(quadprog); chk("quadprog", quadprog::solve.QP(diag(2), c(1, 1), diag(2), c(0, 0))$solution)
library(Rcpp); chk("Rcpp-reg", length(getDLLRegisteredRoutines("Rcpp")$.Call) > 10)
if ("minqa" %in% pkgs) { library(minqa); chk("minqa", round(minqa::bobyqa(c(1, 1), function(x) sum((x - 3)^2))$par, 3)) }
for (p in rev(pkgs)) { chk(paste0("dll-", p), basename(getLoadedDLLs()[[p]][["path"]])); unloadNamespace(p) }
cat("unloaded all\n")
EOF
for l in zig make; do
  "$RSCRIPT" --vanilla "$WORK/work/smoke.R" "$(wpath "$WORK/lib-$l")" "$PKGS" > "$WORK/logs/smoke-$l.out" 2>&1 || { cat "$WORK/logs/smoke-$l.out" >&2; fail "the smoke script failed on lib-$l"; }
  grep -q "ERROR" "$WORK/logs/smoke-$l.out" && { cat "$WORK/logs/smoke-$l.out" >&2; fail "an error in the smoke output of lib-$l"; }
  grep -q "^unloaded all" "$WORK/logs/smoke-$l.out" || fail "the smoke script did not run to the end on lib-$l"
done
cmp -s "$WORK/logs/smoke-zig.out" "$WORK/logs/smoke-make.out" || { diff "$WORK/logs/smoke-zig.out" "$WORK/logs/smoke-make.out" >&2; fail "the smoke outputs differ between the two libraries"; }
echo "   smoke: $(grep -c . "$WORK/logs/smoke-zig.out") lines identical on both libraries"

# --- R CMD SHLIB: through rzig build and through make -----------------------
# R CMD SHLIB's call reaches rzig build through the same hook as R CMD
# INSTALL's package (patch 0013's .rzig_build in .shlib_internal;
# feat-shlib-rzig-build). Each shape is what a caller runs at run time:
# pkgbuild's compiler probe, Rcpp's sourceCpp, cpp11's cpp_source, TMB's
# in-process .shlib_internal with its precompiled library, inline's and
# knitr's Fortran, a Fortran module used by a second file (rzig compiles
# Fortran in OBJECTS order, Cc3) and argv's linker words over a Makevars'
# PKG_LIBS. Each runs in a fresh directory twice, traced: with the
# default builder and with R_ZIG_PKG_BUILDER=make. The rzig run's log
# says `rzig build: R CMD SHLIB, tier 1` with no recipe make echoed, the
# make run's no `rzig build:` line and make's compiles; rzig received the
# same command lines on both paths (argv_of; the TMB shape's absolute -c
# operand is there on both, so abs_sources does not apply); the exports
# are identical; each library loads and returns its value; and the rzig
# run left no object and no build root (.rzig.*) beside the sources: its
# root was in that R's session directory, gone with it (parity-test.sh
# checks the root itself) (Cc5).
echo "== R CMD SHLIB: through rzig build and through make ($OS/$FLAVOR, the compile tree)"
SH="$WORK/work/shlib"; rm -rf "$SH"; mkdir -p "$SH"
# A path R reads, with forward slashes on Windows (C:/...); unchanged
# elsewhere.
mpath() { if [ "$OS" = windows ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
# The shapes: sh_<shape> <dir> writes the fixture into <dir> and runs the
# call there; R_ZIG_PKG_BUILDER and MAKEFLAGS come from sh_pair.
sh_probe() { # pkgbuild's has_compiler(): foo.c beside other sources
  printf 'void foo(int *bar) { *bar = 1; }\n' > "$1/foo.c"
  printf 'this is not C (\n' > "$1/junk.c"
  printf 'int x_old;\n' > "$1/x.cpp"
  (cd "$1" && "$R_EXE" CMD SHLIB foo.c)
}
sh_sourcecpp() { # Rcpp's sourceCpp: -o, LinkingTo through CLINK_CPPFLAGS
  mkdir -p "$1/inc"; printf '#define RZIG_SC 6\n' > "$1/inc/rzigsc.h"
  printf '%s\n' '#include <vector>' '#include <R.h>' '#include <Rinternals.h>' '#include <rzigsc.h>' \
    'extern "C" SEXP sc(void) { std::vector<int> v(RZIG_SC, 1); int n = 0; for (int x : v) n += x; return ScalarInteger(n); }' > "$1/file1.cpp"
  (cd "$1" && CLINK_CPPFLAGS="-I\"$(mpath "$1/inc")\"" "$R_EXE" CMD SHLIB -o "sourceCpp_1.$SO" file1.cpp)
}
sh_cpp11() { # cpp11's cpp_source: absolute sources, --output=, src/Makevars
  mkdir -p "$1/inc" "$1/src"; printf 'inline int c11v() { return 11; }\n' > "$1/inc/rzigc11.h"
  printf '%s\n' 'CXX_STD = CXX11' "PKG_CPPFLAGS = -I'$(mpath "$1/inc")'" > "$1/src/Makevars"
  printf '%s\n' '#include <rzigc11.h>' 'int c11a() { return c11v(); }' > "$1/src/a.cpp"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' 'int c11a();' 'extern "C" SEXP c11(void) { return ScalarInteger(c11a() + 1); }' > "$1/src/cpp11.cpp"
  (cd "$1/src" && "$R_EXE" CMD SHLIB "$(mpath "$1/src/a.cpp")" "$(mpath "$1/src/cpp11.cpp")" "--output=pkg.$SO")
}
sh_tmb() { # TMB's compile(): in process, its library's source elsewhere,
  # the flags in a user Makevars (TMB.R)
  mkdir -p "$1/inc" "$1/tmblib" "$1/model"; printf '#define RZIG_TMB 5\n' > "$1/inc/rzigtmb.h"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' '#include <R_ext/Rdynload.h>' '#include <rzigtmb.h>' \
    'int tmb_lib(void) { return RZIG_TMB; }' 'extern "C" void LIB_UNLOAD(DllInfo *dll) { (void) dll; }' > "$1/tmblib/lib.cpp"
  printf '%s\n' '#include <R.h>' '#include <Rinternals.h>' 'int tmb_lib(void);' 'extern "C" SEXP tmbv(void) { return ScalarInteger(2 * tmb_lib()); }' > "$1/model/model.cpp"
  printf '%s\n' "PKG_CPPFLAGS = -I\"$(mpath "$1/inc")\" -DLIB_UNLOAD=R_unload_model" 'PKG_LIBS = $(SHLIB_OPENMP_CXXFLAGS)' > "$1/Makevars.user"
  (cd "$1/model" && R_MAKEVARS_USER="$(wpath "$1/Makevars.user")" "$RSCRIPT" --vanilla -e \
    "stopifnot(tools:::.shlib_internal(c('model.cpp', '$(mpath "$1/tmblib/lib.cpp")')) == 0)")
}
fs_src() { printf '%s\n' '      subroutine fs(n)' '      integer n' '      n = 42' '      end' > "$1"; }
sh_fortran() { # inline's and knitr's Fortran
  fs_src "$1/fs.f"
  (cd "$1" && "$R_EXE" CMD SHLIB -o "fs.$SO" fs.f)
}
sh_fclink() { # the same, linked by the Fortran compiler
  fs_src "$1/fs.f"; printf 'USE_FC_TO_LINK =\n' > "$1/Makevars"
  (cd "$1" && "$R_EXE" CMD SHLIB -o "fs.$SO" fs.f)
}
sh_fmod() { # a module, then its user: OBJECTS order (Cc3)
  printf '%s\n' 'module m' '  implicit none' '  integer, parameter :: seven = 7' 'end module m' > "$1/mod_m.f90"
  printf '%s\n' 'subroutine fmv(n)' '  use m' '  integer :: n' '  n = seven' 'end subroutine fmv' > "$1/use_m.f90"
  (cd "$1" && "$R_EXE" CMD SHLIB -o "fm.$SO" mod_m.f90 use_m.f90)
}
sh_pkglibs() { # argv's linker words are make's command-line PKG_LIBS
  printf 'PKG_LIBS = -lnosuchlib\n' > "$1/Makevars"
  printf '%s\n' '#include <math.h>' 'void pv(double *x) { *x = sqrt(*x); }' > "$1/p.c"
  (cd "$1" && "$R_EXE" CMD SHLIB p.c -lm)
}
sh_subdir() { # an output in a subdirectory (TMB's src/model.so): macOS
  # compares the install names, which argv_of drops (Cc5)
  mkdir -p "$1/sub"; printf 'void sd(int *x) { *x = 3; }\n' > "$1/sd.c"
  (cd "$1" && "$R_EXE" CMD SHLIB -o "sub/sd.$SO" sd.c)
}
# sh_pair <shape> <library, relative to its directory> <R expression,
# TRUE when the loaded library works>
sh_pair() {
  local shape="$1" out="$2" expr="$3" b d log n a lz lm v left
  for b in zig make; do
    d="$SH/$shape-$b"; log="$WORK/logs/shlib-$shape-$b.log"
    rm -rf "$d"; mkdir -p "$d"
    (if [ "$b" = make ]; then export R_ZIG_PKG_BUILDER=make; elif [ "$shape" = fmod ]; then export MAKEFLAGS=-j8; fi
     "sh_$shape" "$d") > "$log" 2>&1 || { tail -30 "$log" >&2; fail "R CMD SHLIB, $shape: the $b run failed (logs/shlib-$shape-$b.log)"; }
    test -f "$d/$out" || fail "R CMD SHLIB, $shape: the $b run made no $out"
    v=$("$RSCRIPT" --vanilla -e "dyn.load('$(mpath "$d/$out")'); cat(isTRUE($expr), '\n')" 2>&1 | tail -1 | tr -d ' \r')
    [ "$v" = TRUE ] || fail "R CMD SHLIB, $shape: the $b run's $out did not load or return its value ($v)"
  done
  lz="$WORK/logs/shlib-$shape-zig.log"; lm="$WORK/logs/shlib-$shape-make.log"
  grep -q "rzig build: R CMD SHLIB, tier 1" "$lz" || { tail -20 "$lz" >&2; fail "R CMD SHLIB, $shape: the default builder did not report 'rzig build: R CMD SHLIB, tier 1' (logs/shlib-$shape-zig.log)"; }
  [ -z "$(make_recipes "$lz")" ] || fail "R CMD SHLIB, $shape: a recipe make echoed in the rzig run's log"
  if grep -q "rzig build:" "$lm"; then fail "R CMD SHLIB, $shape: R_ZIG_PKG_BUILDER=make still ran rzig build"; fi
  [ -n "$(make_recipes "$lm")" ] || fail "R CMD SHLIB, $shape: no compile make echoed in the make run's log"
  argv_of "$lz" > "$WORK/logs/shlib-$shape-argv-zig"; argv_of "$lm" > "$WORK/logs/shlib-$shape-argv-make"
  a=$(wc -l < "$WORK/logs/shlib-$shape-argv-zig" | tr -d ' ')
  [ "$a" -gt 1 ] && [ "$(wc -l < "$WORK/logs/shlib-$shape-argv-make" | tr -d ' ')" -gt 1 ] || fail "R CMD SHLIB, $shape: fewer than two rzig command lines in a run's log (RZIG_TRACE)"
  cmp -s "$WORK/logs/shlib-$shape-argv-zig" "$WORK/logs/shlib-$shape-argv-make" || { diff "$WORK/logs/shlib-$shape-argv-zig" "$WORK/logs/shlib-$shape-argv-make" | head -20 >&2; fail "R CMD SHLIB, $shape: rzig's command lines differ between rzig build and make"; }
  exports_of "$SH/$shape-zig/$out" > "$WORK/logs/shlib-$shape-exports-zig"; exports_of "$SH/$shape-make/$out" > "$WORK/logs/shlib-$shape-exports-make"
  n=$(wc -l < "$WORK/logs/shlib-$shape-exports-zig" | tr -d ' ')
  [ "$n" -gt 0 ] || fail "R CMD SHLIB, $shape: no exported symbol read from the rzig run's $out"
  cmp -s "$WORK/logs/shlib-$shape-exports-zig" "$WORK/logs/shlib-$shape-exports-make" || { diff "$WORK/logs/shlib-$shape-exports-zig" "$WORK/logs/shlib-$shape-exports-make" | head -20 >&2; fail "R CMD SHLIB, $shape: the exported symbols differ between rzig build and make"; }
  left="$(cd "$SH/$shape-zig" && find . -name '*.o' -o -name '.rzig*' | head -3)"
  [ -z "$left" ] || fail "R CMD SHLIB, $shape: the rzig run left $left beside the sources"
  printf '   %-10s %s exports and %s rzig command lines identical, loads on both paths, nothing left beside the sources\n' "$shape" "$n" "$a"
}
sh_pair probe "foo.$SO" '.C("foo", 0L)[[1]] == 1L'
sh_pair sourcecpp "sourceCpp_1.$SO" '.Call("sc") == 6L'
sh_pair cpp11 "src/pkg.$SO" '.Call("c11") == 12L'
sh_pair tmb "model/model.$SO" '.Call("tmbv") == 10L && is.loaded("R_unload_model")'
test -z "$(find "$SH/tmb-zig/tmblib" -name '*.o')" || fail "R CMD SHLIB, tmb: the rzig run wrote an object beside lib.cpp"
sh_pair fortran "fs.$SO" '.Fortran("fs", n = 0L)$n == 42L'
sh_pair fclink "fs.$SO" '.Fortran("fs", n = 0L)$n == 42L'
grep -Eq 'zig-fc: .* (-shared|-dynamiclib) ' "$WORK/logs/shlib-fclink-zig.log" || fail "R CMD SHLIB, fclink: the USE_FC_TO_LINK link did not run zig-fc on the rzig path"
sh_pair fmod "fm.$SO" '.Fortran("fmv", n = 0L)$n == 7L'
sh_pair pkglibs "p.$SO" '.C("pv", 4)[[1]] == 2'
sh_pair subdir "sub/sd.$SO" '.C("sd", 0L)[[1]] == 3L'
if [ "$OS" = macos ]; then
  iz="$(otool -D "$SH/subdir-zig/sub/sd.$SO" | sed -n 2p)"; im="$(otool -D "$SH/subdir-make/sub/sd.$SO" | sed -n 2p)"
  [ -n "$iz" ] && [ "$iz" = "$im" ] || fail "R CMD SHLIB, subdir: the install names differ: rzig build '$iz', make '$im'"
  echo "   subdir: the install name is '$iz' on both paths"
fi
no_runner "R CMD SHLIB" "$WORK/logs/shlib-probe-zig.log"

# pkgload's compilation database (Cg9, Cc2): its dry run with a single
# quote injected into make's command line (compilation-db.R), on a tier-1
# src/. rzig build declines it (the quote rewrites make's own command
# line), so the output is make -n's, as with R_ZIG_PKG_BUILDER=make; and
# pkgload's filter (lines that start with a compiler, the compilers' first
# words from make's print-compilers) and its -c extraction agree, there
# and on rzig's own dry run with nothing injected, whose link block (make
# -n's form of shlib.mk's recipe) has no line that starts with a compiler.
pl="$SH/pkgload"; rm -rf "$pl"; mkdir -p "$pl/inc"; tar -xzf "$(tarball_of digest)" -C "$pl"
pls="$pl/digest/src"
nsrc=$(cd "$pls" && ls *.c *.cpp 2> /dev/null | wc -l | tr -d ' ')
plfiles=(); for f in $(cd "$pls" && ls *.c *.cpp 2> /dev/null); do plfiles+=("$(mpath "$pls/$f")"); done
lt="-I\"$(mpath "$pl/inc")\""
printf '%s\n' 'print-compilers:' '	@echo $(CC)' '	@echo $(CXX)' '	@echo $(CXX14)' '	@echo $(CXX17)' '	@echo $(CXX20)' '	@echo $(CXX23)' '	@echo $(FC)' '	@echo $(OBJC)' > "$pl/print-var.mk"
mk="$RH/bin/toolchain/usr/bin/make"; [ -x "$mk" ] || mk="$(command -v make)"
if [ "$OS" = windows ]; then mconf="$RH/etc/x64/Makeconf"; else mconf="$RH/etc/Makeconf"; fi
# with the variables pkgload sets "just in case": Makeconf includes
# $(R_SHARE_DIR)/make/vars.mk. Its R.home() has forward slashes on
# Windows, R RHOME backslashes, which no make -n line starts with
# (feat-shlib-rzig-build round 1, kappa)
plrh="$("$R_EXE" RHOME | tr -d '\r' | tr '\\' /)"
# which make, and whether it starts at all from this shell (windows-11-arm
# run 43344258167: this make segfaulted here, while R's own make calls in
# the contract worked)
if [ "$OS" = windows ]; then
  echo "   pkgload: make is $mk"
  "$mk" --version 2>&1 | head -1 | sed 's/^/   pkgload: /' || echo "   pkgload: make --version failed ($?)"
fi
R_HOME="$plrh" R_INCLUDE_DIR="$plrh/include" R_SHARE_DIR="$plrh/share" "$mk" -s -f "$mconf" -f "$pl/print-var.mk" print-compilers | awk 'NF {print $1}' | sort -u > "$WORK/logs/shlib-pkgload-compilers"
[ -s "$WORK/logs/shlib-pkgload-compilers" ] || fail "pkgload: make print-compilers printed no compiler"
# pkgload's two steps on a dry run's output: the lines kept, then those of
# them with a `-c <source>`; prints both counts
pl_counts() {
  tr -d '\r' < "$1" | awk -v f="$WORK/logs/shlib-pkgload-compilers" -v q="'" '
    BEGIN { while ((getline c < f) > 0) cs[c] = 1; re = "-c +[" q "\"]?[^ ]+[.](cc|cpp|f90|f95|mm|[cfmM])" }
    { for (c in cs) if (index($0, c) == 1) { k++; if ($0 ~ re) e++; break } }
    END { print k + 0, e + 0 }'
}
for b in zig make; do
  (cd "$pls" && if [ "$b" = make ]; then export R_ZIG_PKG_BUILDER=make; fi
   CLINK_CPPFLAGS="$lt" "$R_EXE" CMD SHLIB --dry-run -o "digest.$SO" "' --always-make $lt IGNORED='" "${plfiles[@]}") \
    > "$WORK/logs/shlib-pkgload-$b.out" 2> "$WORK/logs/shlib-pkgload-$b.err" || { cat "$WORK/logs/shlib-pkgload-$b.err" >&2; fail "pkgload: the injected dry run failed ($b)"; }
done
grep -q "needs make: a single quote in the linker words" "$WORK/logs/shlib-pkgload-zig.err" || { cat "$WORK/logs/shlib-pkgload-zig.err" >&2; fail "pkgload: rzig build did not decline the injected single quote"; }
cmp -s "$WORK/logs/shlib-pkgload-zig.out" "$WORK/logs/shlib-pkgload-make.out" || { diff "$WORK/logs/shlib-pkgload-zig.out" "$WORK/logs/shlib-pkgload-make.out" | head -20 >&2; fail "pkgload: the injected dry run's output differs from make's"; }
(cd "$pls" && "$R_EXE" CMD SHLIB --dry-run -o "digest.$SO" "${plfiles[@]}") > "$WORK/logs/shlib-pkgload-plain.out" 2> "$WORK/logs/shlib-pkgload-plain.err" ||
  { cat "$WORK/logs/shlib-pkgload-plain.err" >&2; fail "pkgload: the plain dry run failed"; }
if grep -q "needs make" "$WORK/logs/shlib-pkgload-plain.err"; then cat "$WORK/logs/shlib-pkgload-plain.err" >&2; fail "pkgload: rzig build declined the plain dry run"; fi
grep -q '^if test "z' "$WORK/logs/shlib-pkgload-plain.out" || fail "pkgload: the plain dry run has no link block in make -n's form (rzig's printCommands)"
ci="$(pl_counts "$WORK/logs/shlib-pkgload-make.out")"; cp="$(pl_counts "$WORK/logs/shlib-pkgload-plain.out")"
[ "$ci" = "$nsrc $nsrc" ] || fail "pkgload: on make -n's output (injected), the filter and -c extraction give '$ci', not $nsrc $nsrc"
[ "$cp" = "$nsrc $nsrc" ] || fail "pkgload: on rzig's dry run, the filter and -c extraction give '$cp', not $nsrc $nsrc"
test -z "$(cd "$pls" && find . -name '*.o' -o -name "*.$SO" -o -name '.rzig*')" || fail "pkgload: a dry run built something in digest/src"
echo "   pkgload: the injected dry run is make -n's ($nsrc compiles kept and extracted), rzig's plain dry run gives the same $nsrc"

# R_ZIG_PKG_BUILDER=zig (Am8): a call that needs make is an error, and
# nothing is built.
zd="$SH/builder-zig"; rm -rf "$zd"; mkdir -p "$zd"
printf 'void x(int *n) { *n = 1; }\n' > "$zd/x.c"
printf '%s\n' 'all: $(SHLIB) extra' 'extra:' '	@echo extra' > "$zd/Makevars"
if (cd "$zd" && R_ZIG_PKG_BUILDER=zig "$R_EXE" CMD SHLIB x.c) > "$WORK/logs/shlib-builder-zig.log" 2>&1; then fail "R_ZIG_PKG_BUILDER=zig: R CMD SHLIB of a Makevars with a rule succeeded"; fi
grep -q "x.$SO needs make: Makevars has a rule or target line" "$WORK/logs/shlib-builder-zig.log" &&
  tr -d '\r' < "$WORK/logs/shlib-builder-zig.log" | grep -x "ERROR: this shared object needs make, and R_ZIG_PKG_BUILDER is 'zig'" > /dev/null ||
  { cat "$WORK/logs/shlib-builder-zig.log" >&2; fail "R_ZIG_PKG_BUILDER=zig: R CMD SHLIB failed without rzig's reason and R's error (logs/shlib-builder-zig.log)"; }
test ! -e "$zd/x.$SO" && test ! -e "$zd/x.o" || fail "R_ZIG_PKG_BUILDER=zig: something was built in $zd"
echo "   R_ZIG_PKG_BUILDER=zig: a Makevars rule is an error, with rzig's reason, nothing built"

# Two calls at once in one directory, RZIG_KEEP_ROOT=1 (SZ H2, Cc12): each
# has its own build root. A kept root is beside the output, outside R's
# session directory, which R CMD SHLIB's R removes when it exits
# [shlib-code-1], so both roots are in this one directory, where only
# their unique names keep them apart [shlib-tests-2]. unix: forked in one
# R (parallel::mclapply over .shlib_internal, as TMB calls it); Windows
# (no fork): two R CMD SHLIB at once, whose traces name the two roots.
cc="$SH/concurrent"; rm -rf "$cc"; mkdir -p "$cc"
printf 'void ca(int *n) { *n = 1; }\n' > "$cc/a.c"; printf 'void cb(int *n) { *n = 2; }\n' > "$cc/b.c"
if [ "$OS" = windows ]; then
  (cd "$cc" && RZIG_KEEP_ROOT=1 "$R_EXE" CMD SHLIB -o "a.$SO" a.c > "$WORK/logs/shlib-conc-a.log" 2>&1) & ca=$!
  (cd "$cc" && RZIG_KEEP_ROOT=1 "$R_EXE" CMD SHLIB -o "b.$SO" b.c > "$WORK/logs/shlib-conc-b.log" 2>&1) & cb=$!
  wait "$ca" && wait "$cb" || fail "two R CMD SHLIB at once: one failed (logs/shlib-conc-a.log, -b.log)"
  r1="$(tr -d '\r' < "$WORK/logs/shlib-conc-a.log" | sed -n 's/^rzig build: R CMD SHLIB, tier 1, root //p')"
  r2="$(tr -d '\r' < "$WORK/logs/shlib-conc-b.log" | sed -n 's/^rzig build: R CMD SHLIB, tier 1, root //p')"
  [ -n "$r1" ] && [ -n "$r2" ] && [ "${r1%/*}" = "${r2%/*}" ] && [ "${r1##*/}" != "${r2##*/}" ] &&
    [ -f "$r1/plan.zon" ] && [ -f "$r2/plan.zon" ] || fail "two R CMD SHLIB at once: not two build roots in one directory ('$r1', '$r2')"
  rm -rf "$r1" "$r2"
else
  (cd "$cc" && RZIG_KEEP_ROOT=1 "$RSCRIPT" --vanilla -e '
    st <- unlist(parallel::mclapply(c("a", "b"), function(n) tools:::.shlib_internal(c("-o", paste0(n, ".so"), paste0(n, ".c"))), mc.cores = 2))
    roots <- list.files(".", pattern = "^[.]rzig[.][0-9a-f]{16}$", all.files = TRUE, full.names = TRUE)
    cat("status", st, "roots", length(roots), "plans", sum(file.exists(file.path(roots, "plan.zon"))), "\n")
    stopifnot(identical(st, c(0L, 0L)), length(roots) == 2L, all(file.exists(file.path(roots, "plan.zon"))))
    unlink(roots, recursive = TRUE)') > "$WORK/logs/shlib-conc.log" 2>&1 ||
    { tail -20 "$WORK/logs/shlib-conc.log" >&2; fail "two .shlib_internal at once (mclapply): not both built with a root each (logs/shlib-conc.log)"; }
fi
v=$("$RSCRIPT" --vanilla -e "dyn.load('$(mpath "$cc/a.$SO")'); dyn.load('$(mpath "$cc/b.$SO")'); cat(.C('ca', 0L)[[1]] + .C('cb', 0L)[[1]], '\n')" 2>&1 | tail -1 | tr -d ' \r')
[ "$v" = 3 ] || fail "two R CMD SHLIB at once: the libraries did not load or return their values ($v)"
test -z "$(cd "$cc" && find . -name '*.o' -o -name '.rzig*')" || fail "two R CMD SHLIB at once: objects or a build root left beside the sources"
echo "   two calls at once in one directory: both built and load, two build roots"
# Windows, H8 (Cc10): a package whose Makevars.win sets PKG_FCFLAGS, and
# no file named Makevars. R passes P_FCFLAGS='$(PKG_FCFLAGS)' only when
# "Makevars" exists (.shlib_internal's literal test), so make compiles the
# .f90 without it; rzig build follows the same test, and both paths' command
# lines are identical.
if [ "$OS" = windows ]; then
  h8="$SH/h8/rzigh8"; rm -rf "$SH/h8"; mkdir -p "$h8/src" "$SH/h8/lib-zig" "$SH/h8/lib-make"
  printf 'Package: rzigh8\nVersion: 0.1\nTitle: H8\nDescription: PKG_FCFLAGS in Makevars.win alone.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$h8/DESCRIPTION"
  printf 'useDynLib(rzigh8)\n' > "$h8/NAMESPACE"
  printf '%s\n' 'subroutine h8v(n)' '  integer :: n' '  n = 8' 'end subroutine h8v' > "$h8/src/h8.f90"
  printf 'PKG_FCFLAGS = -fimplicit-none\n' > "$h8/src/Makevars.win"
  install_pkg "$SH/h8/lib-zig" "$h8" "h8-zig" > /dev/null || { tail -20 "$WORK/logs/h8-zig.log" >&2; fail "H8: rzigh8 failed through rzig build"; }
  R_ZIG_PKG_BUILDER=make install_pkg "$SH/h8/lib-make" "$h8" "h8-make" > /dev/null || { tail -20 "$WORK/logs/h8-make.log" >&2; fail "H8: rzigh8 failed through make"; }
  grep -q "rzig build: tier 1" "$WORK/logs/h8-zig.log" || fail "H8: rzigh8 did not build through rzig build (logs/h8-zig.log)"
  argv_of "$WORK/logs/h8-zig.log" > "$WORK/logs/h8-argv-zig"; argv_of "$WORK/logs/h8-make.log" > "$WORK/logs/h8-argv-make"
  [ "$(wc -l < "$WORK/logs/h8-argv-zig" | tr -d ' ')" -gt 1 ] || fail "H8: no rzig command lines in the rzig build log"
  cmp -s "$WORK/logs/h8-argv-zig" "$WORK/logs/h8-argv-make" || { diff "$WORK/logs/h8-argv-zig" "$WORK/logs/h8-argv-make" | head -20 >&2; fail "H8: the command lines differ between rzig build and make"; }
  if grep -q -- "-fimplicit-none" "$WORK/logs/h8-argv-zig"; then fail "H8: rzig build passed Makevars.win's PKG_FCFLAGS with no Makevars"; fi
  echo "   H8: Makevars.win's PKG_FCFLAGS with no Makevars, the same command lines on both paths"
fi

# --- the caches: nothing per install outlives it ----------------------------
echo "== caches: no build runner for tier 1; a kept build root; a second install of a tarball keys zig's global cache as make's does; ZIG_LOCAL_CACHE_DIR; two installs at once"
# From the tarball, as install.packages installs: R unpacks it into a new
# R.INSTALL directory each time. rzig build names each source relative to
# src/, as make's `-c <file>` does [tests-T1], so the two paths key zig's
# global cache alike: a second install adds as many entries through rzig
# build as through make. With zig 0.16 that was none (its cache keyed a
# source by its path relative to the working directory); zig 0.17 keys it
# by its absolute path, whatever the command line says, so both paths
# recompile into new entries (feat-zig-017).
rm -rf "$WORK/work/lib-again"; mkdir -p "$WORK/work/lib-again"
install_pkg "$WORK/work/lib-again" "$(tarball_of cli)" "again-1" > /dev/null || { tail -20 "$WORK/logs/again-1.log" >&2; fail "cli (its tarball) failed to install"; }
g1=$(global_entries)
t2=$(install_pkg "$WORK/work/lib-again" "$(tarball_of cli)" "again-2") || { tail -20 "$WORK/logs/again-2.log" >&2; fail "cli (its tarball, again) failed to install"; }
g2=$(global_entries)
grep -q "rzig build: tier 1" "$WORK/logs/again-2.log" || fail "the second install of cli did not go through rzig build"
rm -rf "$WORK/work/lib-again-make"; mkdir -p "$WORK/work/lib-again-make"
R_ZIG_PKG_BUILDER=make install_pkg "$WORK/work/lib-again-make" "$(tarball_of cli)" "again-make-1" > /dev/null || { tail -20 "$WORK/logs/again-make-1.log" >&2; fail "cli (its tarball, make) failed to install"; }
m1=$(global_entries)
R_ZIG_PKG_BUILDER=make install_pkg "$WORK/work/lib-again-make" "$(tarball_of cli)" "again-make-2" > /dev/null || { tail -20 "$WORK/logs/again-make-2.log" >&2; fail "cli (its tarball, make, again) failed to install"; }
m2=$(global_entries)
[ $((g2 - g1)) = $((m2 - m1)) ] || fail "a second install of the cli tarball added $((g2 - g1)) entries to zig's global cache through rzig build and $((m2 - m1)) through make ($ZIG_GLOBAL_CACHE_DIR/o): rzig build's compiles must be keyed as make's, by the source's path relative to src/"
no_runner "cli's tarball, twice" "$WORK/logs/again-2.log"
# and why: each compile named its source relative to src/ (the count holds
# only while R's temp dir has no build.zig above it, where zig cc would
# cache in that directory's .zig-cache instead) [tests-T1, tests-T7]
[ -z "$(abs_sources "$WORK/logs/again-2.log")" ] || { abs_sources "$WORK/logs/again-2.log" | head -3 >&2; fail "rzig build compiled a source by its absolute path (logs/again-2.log): compiles must name it relative to src/, as make does"; }
echo "   cli's tarball twice: $((g2 - g1)) new entries in zig's global cache through rzig build, $((m2 - m1)) through make, every source named relative to src/; the second install ${t2}s (make ${cli_make}s)"
# A kept build root holds what the install wrote, the plan, the objects
# (obj/) and the library, and no zig build cache: tier 1 runs no zig
# build (tier1.zig).
rm -rf "$WORK/work/kept"; mkdir -p "$WORK/work/kept"
tar -xzf "$(tarball_of digest)" -C "$WORK/work/kept"
RZIG_KEEP_ROOT=1 install_pkg "$WORK/work/lib-again" "$WORK/work/kept/digest" "kept" > /dev/null || { tail -20 "$WORK/logs/kept.log" >&2; fail "digest (from its directory, RZIG_KEEP_ROOT=1) failed to install"; }
kr="$WORK/work/kept/digest/src/.rzig"
test -f "$kr/plan.zon" && test -f "$kr/digest.$SO" || fail "digest's kept build root ($kr) lacks plan.zon or digest.$SO"
[ -n "$(find "$kr/obj" -name '*.o' 2> /dev/null)" ] || fail "no object in digest's kept build root ($kr/obj)"
test ! -e "$kr/zig-cache" || fail "digest's kept build root has a zig build cache ($kr/zig-cache): tier 1 runs no zig build"
no_runner "digest (its build root kept)" "$WORK/logs/kept.log"
rm -rf "$WORK/work/kept"
echo "   digest's kept build root: plan.zon, obj/, digest.$SO and no zig-cache"
# ZIG_LOCAL_CACHE_DIR, when set, is zig cc's cache (and tier 2's zig
# build cache): tier 1 runs no zig build, and the root still goes with the
# install: from a directory, where the root is the package's src/.rzig
# [preflight-PF-8, tests-3].
rm -rf "$WORK/work/again" "$WORK/work/zlc"; mkdir -p "$WORK/work/again"
tar -xzf "$(tarball_of cli)" -C "$WORK/work/again"
ZIG_LOCAL_CACHE_DIR="$(wpath "$WORK/work/zlc")" install_pkg "$WORK/work/lib-again" "$WORK/work/again/cli" "again-zlc" > /dev/null || { tail -20 "$WORK/logs/again-zlc.log" >&2; fail "cli (from its directory, ZIG_LOCAL_CACHE_DIR set) failed to install"; }
grep -q "rzig build: tier 1" "$WORK/logs/again-zlc.log" || fail "cli with ZIG_LOCAL_CACHE_DIR set did not go through rzig build"
[ -n "$(ls "$WORK/work/zlc/o" 2> /dev/null)" ] || fail "with ZIG_LOCAL_CACHE_DIR=$WORK/work/zlc, no object of zig cc's is there"
test ! -e "$WORK/work/again/cli/src/.rzig" || fail "the build root was left in cli's src/ (ZIG_LOCAL_CACHE_DIR set)"
no_runner "cli with ZIG_LOCAL_CACHE_DIR" "$WORK/logs/again-zlc.log"
echo "   cli with ZIG_LOCAL_CACHE_DIR: zig cc's objects there, no zig build, no build root left in src/"
# Two tier-1 packages at once from a cold rzig cache, as install.packages
# installs them with Ncpus = 2 (make -j2 over R CMD INSTALL; the build
# tools' make first on PATH, as R CMD has it): each runs its own plan, and
# they share only zig's global cache, which zig locks itself. "begin
# installing" is the parallel path's make echoing its targets.
rm -rf "$WORK/work/repo" "$WORK/work/lib-par" "$WORK/work/cache-par" "$WORK/logs/par"
mkdir -p "$WORK/work/repo" "$WORK/work/lib-par" "$WORK/logs/par"
cp "$(tarball_of cli)" "$(tarball_of digest)" "$WORK/work/repo/"
s=$(date +%s)
PATH="$RH/bin/toolchain/usr/bin:$PATH" XDG_CACHE_HOME="$(wpath "$WORK/work/cache-par")" PKG_PARITY_REPO="$(wpath "$WORK/work/repo")" \
  PKG_PARITY_LIB="$(wpath "$WORK/work/lib-par")" PKG_PARITY_OUT="$(wpath "$WORK/logs/par")" "$RSCRIPT" --vanilla -e '
    repo <- normalizePath(Sys.getenv("PKG_PARITY_REPO"), "/")
    tools::write_PACKAGES(repo, type = "source")
    install.packages(c("cli", "digest"), lib = Sys.getenv("PKG_PARITY_LIB"), contriburl = paste0("file:///", sub("^/", "", repo)),
                     type = "source", Ncpus = 2, keep_outputs = Sys.getenv("PKG_PARITY_OUT"))' > "$WORK/logs/par.log" 2>&1 ||
  { tail -20 "$WORK/logs/par.log" >&2; fail "install.packages(c('cli', 'digest'), Ncpus = 2) failed"; }
e=$(date +%s)
grep -q "begin installing package" "$WORK/logs/par.log" || { tail -20 "$WORK/logs/par.log" >&2; fail "install.packages(Ncpus = 2) did not install in parallel (no make's 'begin installing package' in logs/par.log)"; }
for q in cli digest; do
  test -f "$WORK/work/lib-par/$q/$LIBSUB/$q.$SO" || { tail -20 "$WORK/logs/par/$q.out" >&2 || true; fail "$q, installed with Ncpus = 2 from a cold rzig cache, has no $q.$SO"; }
  grep -q "rzig build: tier 1" "$WORK/logs/par/$q.out" || fail "$q, installed with Ncpus = 2, did not go through rzig build (logs/par/$q.out)"
done
[ -z "$(ls -d "$WORK/work/cache-par/r-zig"/build-runner-* 2> /dev/null)" ] || fail "two installs at once from a cold rzig cache left a build-runner directory"
echo "   cli and digest at once (install.packages, Ncpus = 2) from a cold rzig cache: both built, $((e - s))s"

# --- tier 2: a zig package --------------------------------------------------
echo "== tier 2: zighello"
test -f "$ZIGHELLO/src/build.zig" || fail "no tier-2 fixture at $ZIGHELLO"
rm -rf "$WORK/work/zighello"; cp -R "$ZIGHELLO" "$WORK/work/zighello"
tz=$(install_pkg "$WORK/lib-zig" "$WORK/work/zighello" "zighello") || { tail -30 "$WORK/logs/zighello.log" >&2; fail "zighello failed to install"; }
grep -q "rzig build: tier 2" "$WORK/logs/zighello.log" || fail "zighello: no 'rzig build: tier 2' in the log"
grep -q "^using zig: " "$WORK/logs/zighello.log" || fail "zighello: no 'using zig:' line in the log"
grep -q -- '--system ' "$WORK/logs/zighello.log" || fail "zighello: zig build did not run with --system (tier 2 builds offline)"
[ -z "$(make_recipes "$WORK/logs/zighello.log")" ] || fail "zighello: a recipe make echoed in the log"
v=$("$RSCRIPT" --vanilla -e '.libPaths(c(commandArgs(TRUE)[1], .libPaths())); library(zighello); cat(hello(21L), "\n"); unloadNamespace("zighello")' "$(wpath "$WORK/lib-zig")" 2>&1 | tail -1 | tr -d ' \r')
[ "$v" = 42 ] || fail "zighello: hello(21L) printed '$v', not 42"
exports_of "$WORK/lib-zig/zighello/$LIBSUB/zighello.$SO" | grep -q "R_init_zighello" || fail "zighello: R_init_zighello is not exported"
test -e "$WORK/work/zighello/src/.rzig" && fail "zighello: the build root was left in src/"
test -e "$WORK/work/zighello/src/.zig-cache" && fail "zighello: a .zig-cache was left in src/"
# tier 2 keeps its zig build cache in the build root (its runner imports
# the package's build.zig from this install's path, new every install),
# none in rzig's cache
no_runner zighello
echo "   zighello: tier 2, ${tz}s with the test load, hello(21L) = 42, R_init_zighello exported, zig build with --system"
# a URL dependency in the package's own manifest: refused before zig runs
rm -rf "$WORK/work/zigurl"; cp -R "$ZIGHELLO" "$WORK/work/zigurl"
sed -i.bak 's/^Package: zighello/Package: zigurl/' "$WORK/work/zigurl/DESCRIPTION" && rm -f "$WORK/work/zigurl/DESCRIPTION.bak"
printf '.{\n    .name = .zigurl,\n    .version = "0.0.0",\n    .fingerprint = 0x9d6b4e2f1c3a5b70,\n    .dependencies = .{\n        .remote = .{\n            .url = "https://example.invalid/remote.tar.gz",\n            .hash = "N-V-__8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",\n        },\n    },\n    .paths = .{""},\n}\n' > "$WORK/work/zigurl/src/build.zig.zon"
rm -rf "$WORK/work/lib-url"; mkdir -p "$WORK/work/lib-url"
if install_pkg "$WORK/work/lib-url" "$WORK/work/zigurl" "zigurl" > /dev/null; then fail "tier 2: a package whose build.zig.zon fetches a URL installed"; fi
grep -q "src/build.zig.zon: dependency remote is a URL; tier 2 builds offline, vendor it as a .path dependency" "$WORK/logs/zigurl.log" || { tail -10 "$WORK/logs/zigurl.log" >&2; fail "tier 2: the URL dependency was not refused with the expected line (logs/zigurl.log)"; }
grep -q "rzig build: tier 2" "$WORK/logs/zigurl.log" && fail "tier 2: zig build ran for the package with a URL dependency"
# the build root, made before the refusal, goes too [preflight-PF-3]
test ! -e "$WORK/work/zigurl/src/.rzig" && test ! -e "$WORK/work/zigurl/src/.zig-cache" || fail "zigurl: the refusal left a build root (src/.rzig) or a .zig-cache in src/"
echo "   zigurl: a URL dependency in src/build.zig.zon is refused before zig runs, no build root left"
# A tier-2 package has no make build: a MAKEFLAGS assignment, which sends
# a tier-1 package to make (its build would differ), leaves it on zig
# build; a plan that needs make (here a foreign CC from a user Makevars:
# ccache) fails with rzig's line, exit 1, instead of a make path that
# ignores build.zig (I-C1) [preflight-PF-1]. A user Makevars skips the
# preflight (patch 0009), so this is the hook's decision.
rm -rf "$WORK/work/zigmf" "$WORK/work/lib-zigmf"; cp -R "$ZIGHELLO" "$WORK/work/zigmf"; mkdir -p "$WORK/work/lib-zigmf"
MAKEFLAGS='-- X=1' install_pkg "$WORK/work/lib-zigmf" "$WORK/work/zigmf" "zighello-makeflags" > /dev/null || { tail -20 "$WORK/logs/zighello-makeflags.log" >&2; fail "zighello under MAKEFLAGS='-- X=1' failed to install (tier 2 has no make build to differ from)"; }
grep -q "rzig build: tier 2" "$WORK/logs/zighello-makeflags.log" || fail "zighello under MAKEFLAGS='-- X=1' did not build through rzig build: tier 2"
rm -rf "$WORK/work/zigcc" "$WORK/work/lib-zigcc"; cp -R "$ZIGHELLO" "$WORK/work/zigcc"; mkdir -p "$WORK/work/lib-zigcc"
printf 'CC = ccache cc\n' > "$WORK/work/ccache-makevars"
if R_MAKEVARS_USER="$(wpath "$WORK/work/ccache-makevars")" install_pkg "$WORK/work/lib-zigcc" "$WORK/work/zigcc" "zighello-ccache" > /dev/null; then
  fail "zighello with CC = ccache in the user Makevars installed: tier 2 cannot be built by make"
fi
grep -q "zighello: src/build.zig cannot be built by make: CC = ccache is not a compiler of R's toolchain" "$WORK/logs/zighello-ccache.log" ||
  { tail -10 "$WORK/logs/zighello-ccache.log" >&2; fail "zighello with CC = ccache did not fail with 'zighello: src/build.zig cannot be built by make: CC = ccache ...' (logs/zighello-ccache.log)"; }
if grep -q "zighello needs make: " "$WORK/logs/zighello-ccache.log" || [ -n "$(make_recipes "$WORK/logs/zighello-ccache.log")" ]; then
  fail "zighello with CC = ccache went to the make path (rzig build's exit 3), not a failure"
fi
test ! -e "$WORK/work/zigcc/src/.rzig" || fail "zighello with CC = ccache: a build root was left in src/"
echo "   zighello: tier 2 under MAKEFLAGS='-- X=1'; with CC = ccache in the user Makevars, 'src/build.zig cannot be built by make', no make path"

# --- tier 3: falls through to make, or is refused ---------------------------
echo "== tier 3: a configure script"
rm -rf "$WORK/work/neg"; mkdir -p "$WORK/work/neg"; tar -xzf "$(tarball_of cli)" -C "$WORK/work/neg"
if [ "$OS" = windows ]; then cfg=configure.win; else cfg=configure; fi
printf '#!/bin/sh\nexit 0\n' > "$WORK/work/neg/cli/$cfg"; chmod +x "$WORK/work/neg/cli/$cfg"
rm -rf "$WORK/work/lib-neg"; mkdir -p "$WORK/work/lib-neg"
install_pkg "$WORK/work/lib-neg" "$WORK/work/neg/cli" "neg-auto" --no-test-load > /dev/null || { tail -20 "$WORK/logs/neg-auto.log" >&2; fail "tier 3: the fall-through to make failed"; }
grep -q "rzig build: cli needs make: a $cfg script" "$WORK/logs/neg-auto.log" || fail "tier 3: the log does not say why rzig build declined (logs/neg-auto.log)"
# asked once (SZ H1): the one hook in .shlib_internal asks for the package,
# and the make path that follows does not ask again for R CMD SHLIB's files
[ "$(grep -c "rzig build: cli needs make: " "$WORK/logs/neg-auto.log")" = 1 ] || fail "tier 3: rzig build was asked more than once for cli (logs/neg-auto.log)"
if grep -q "rzig build: R CMD SHLIB" "$WORK/logs/neg-auto.log"; then fail "tier 3: rzig build's SHLIB mode ran for cli's make path (logs/neg-auto.log)"; fi
test -f "$WORK/work/lib-neg/cli/$LIBSUB/cli.$SO" || fail "tier 3: make did not build cli"
rm -rf "$WORK/work/lib-neg"; mkdir -p "$WORK/work/lib-neg"
if R_ZIG_PKG_BUILDER=zig install_pkg "$WORK/work/lib-neg" "$WORK/work/neg/cli" "neg-zig" --no-test-load > /dev/null; then fail "tier 3: R_ZIG_PKG_BUILDER=zig installed a package that needs make"; fi
grep -q "needs make, and R_ZIG_PKG_BUILDER is 'zig'" "$WORK/logs/neg-zig.log" || { tail -5 "$WORK/logs/neg-zig.log" >&2; fail "tier 3: R_ZIG_PKG_BUILDER=zig failed without the expected message"; }
echo "   configure: falls through to make under auto, rzig build asked once, refused under zig"

# --- the base alone, no make (unix: sh, zig and flang only) -----------------
echo "== the base alone ($BASE_RH), no make on PATH"
NOMAKE="$WORK/work/nomake-bin"; rm -rf "$NOMAKE"; mkdir -p "$NOMAKE"
# env.sh's $ZIG: ZIG_BIN, else the env's zig (win-64: x86_64-w64-mingw32-zig.exe)
zig_bin="${ZIG:-}"
test -n "$zig_bin" || fail "no zig to put on the restricted PATH (ZIG_BIN or PATH)"
pkg=quadprog
if [ "$OS" = windows ]; then
  fl="$(command -v flang.exe || command -v flang || true)"
  if [ -n "$fl" ]; then for f in flang.exe flang-new.exe flang.cfg flang-compile.cfg; do [ -f "$(dirname "$fl")/$f" ] && cp "$(dirname "$fl")/$f" "$NOMAKE/"; done; else pkg=cli; fi
  sysdir="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")"
  # zig's own cache needs a home too (LOCALAPPDATA, else "unable to resolve
  # zig cache directory"); its global cache is env.sh's, as the runs above
  NOMAKE_ENV=(SYSTEMROOT="$SYSTEMROOT" WINDIR="${WINDIR:-$SYSTEMROOT}" HOME="$(wpath "$WORK/work")" LOCALAPPDATA="$(wpath "$WORK/work")" TMPDIR="$(wpath "$WORK/work")" TMP="$(wpath "$WORK/work")" TEMP="$(wpath "$WORK/work")" PATH="$NOMAKE:$sysdir/System32" ZIG_BIN="$(wpath "$zig_bin")" ZIG_GLOBAL_CACHE_DIR="$(cygpath -m "$ZIG_GLOBAL_CACHE_DIR")" R_MAKEVARS_USER="$R_MAKEVARS_USER" RZIG_TRACE=1)
else
  ln -s "$(command -v sh)" "$NOMAKE/sh"; ln -s "$zig_bin" "$NOMAKE/zig"
  fl="$(command -v flang || command -v flang-new || true)"
  if [ -n "$fl" ]; then ln -s "$fl" "$NOMAKE/flang"; else pkg=cli; fi
  NOMAKE_ENV=(HOME="$WORK/work" TMPDIR="$WORK/work" PATH="$NOMAKE" ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" R_MAKEVARS_USER="$R_MAKEVARS_USER" RZIG_TRACE=1)
fi
s=$(date +%s)
env -i "${NOMAKE_ENV[@]}" "$BASE_R_EXE" CMD INSTALL -l "$(wpath "$WORK/lib-nomake")" "$(wpath "$(tarball_of $pkg)")" > "$WORK/logs/nomake-$pkg.log" 2>&1 || { tail -20 "$WORK/logs/nomake-$pkg.log" >&2; fail "$pkg did not install on the base with only $(ls "$NOMAKE" | tr '\n' ' ')on PATH"; }
e=$(date +%s)
grep -q "rzig build: tier 1" "$WORK/logs/nomake-$pkg.log" || fail "$pkg on the base: no 'rzig build: tier 1' in the log"
test -f "$WORK/lib-nomake/$pkg/$LIBSUB/$pkg.$SO" || fail "no $pkg.$SO from the no-make install"
echo "   $pkg: installed on the base in $((e - s))s with PATH = $(ls "$NOMAKE" | tr '\n' ' ')$([ "$OS" = windows ] && echo '+ System32 (zig through ZIG_BIN)')"

echo "== pkg-parity verified ($OS/$FLAVOR): $PKGS through rzig build match make on the compile tree; R CMD SHLIB's shapes through rzig build match make, pkgload's dry run, R_ZIG_PKG_BUILDER=zig and two calls at once; tier 2 (its URL refusal, MAKEFLAGS, a plan that needs make), tier 3, the caches and the no-make install on the base behave"
