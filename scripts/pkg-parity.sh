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
#     `-Wl,-install_name,<pkg>.so` only rzig passes (make's linker derives
#     the same name from -o), on Windows the .def file's name (`tmp.def`
#     from nm | sed, `<pkg>.def` from `rzig def`), and the directories of
#     the paths (the zig path's objects and output are in its build root,
#     obj/<n>/ and <root>/<output>; Windows: rzig's
#     `--out-implib=<output>.rzig.lib`, absolute there) [tests-3];
#     the `ZIG_LIB_DIR=<mirror>` word rzig prints first where it gives
#     conda-forge's zig the libc++ mirror (every macOS env) is stripped,
#     and the make path's `--version` probes are left out;
#   - a smoke script loads and exercises the packages from each library
#     and prints the same values;
#   - the caches: every tier-1 install shares one zig build cache,
#     build-runner-<key> in rzig's cache, which holds build_t1.zig's copy
#     and its build runner alone (pkgbuild.zig's sharedRunner; stress
#     dispatch 38467907779): the first install compiles it, every later
#     one leaves it as it was, no object or library of an install in it;
#     a kept build root (RZIG_KEEP_ROOT=1) holds the plan, the objects and
#     the library and no zig build cache (N3); a second install of the
#     cli tarball, which R unpacks into a new directory each time as
#     install.packages does, adds no entry to zig's global cache: rzig
#     build's compiles are keyed as make's are [tests-T1], and its time
#     is printed against make's;
#     with ZIG_LOCAL_CACHE_DIR set, rzig build's cache is there, and the
#     build root still goes [preflight-PF-8]; two tier-1 packages
#     installed at once by install.packages(Ncpus = 2), from a cold rzig
#     cache, both build, with one build runner between them.
# Then the tier-2 fixture (.github/devdocs/feat-zig-pkg-build/proto/
# zighello, a zig package: `rzig build: tier 2`, `hello(21L)` is 42), its
# twin with a URL dependency in src/build.zig.zon (refused: tier 2 builds
# offline, N6; no build root left [preflight-PF-3]), zighello under a
# MAKEFLAGS assignment (tier 2 still: no make build to differ from) and
# with a foreign CC in a user Makevars (`src/build.zig cannot be built by
# make`, a failure, never the make path [preflight-PF-1]), the tier-3
# negative (cli with a `configure` script falls through to make; with
# R_ZIG_PKG_BUILDER=zig that is an error), all on the compile tree; and,
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
# Nothing of the caller's selects a path, a compiler or a cache: rzig
# build's cache is its default, the build runner's directory in rzig's
# own cache (ZIG_LOCAL_CACHE_DIR would name another place), here under
# $WORK/cache, emptied above, where the checks below can see it.
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
    windows) x86_64-w64-mingw32-objdump -p "$1" | awk '/\[Ordinal\/Name Pointer\] Table/ {f=1; next} f && NF == 0 {exit} f {print $NF}' ;;
  esac | LC_ALL=C sort
}
# rzig's command lines from a traced install log, normalised (see the
# header) and sorted: its self and environment lines and a `--version`
# word (the make path's compiler probes; a -Wl,--version-script= stays)
# left out; a path keeps its flag's prefix (-I, -L, -Wl,<words>, and
# --<option>=, also after -Wl,) and its file name, its directory dropped
# whatever it is: the source operand's is checked by abs_sources below
# [tests-T7].
argv_of() {
  tr -d '\r' < "$1" \
    | grep -E '^(zig-cc|zig-cxx|zig-fc): ' \
    | grep -v -E -- '^zig-(cc|cxx|fc): (self|environment) |(^| )--version( |$)' \
    | sed -E 's/^(zig-(cc|cxx|fc): )ZIG_LIB_DIR=[^ ]+ /\1/' \
    | tr -d "'\"" \
    | sed -E 's#(^| )(-[IL]|-Wl,([^ ,]*,)*(--?[A-Za-z-]+=)?|--?[A-Za-z-]+=)?[^ ]*[\\/]([^\\/ ]+)#\1\2\5#g; s/ -Wl,-install_name,[^ ]+//; s/[^ ]*\.def( |$)/X.def\1/' \
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
# rzig build's zig build cache for tier 1 (pkgbuild.zig's sharedRunner):
# build-runner-<key of build_t1.zig's content and the zig> in rzig's
# cache, one per R's build_t1.zig and zig.
runner_dirs() { ls -d "$RZIG_CACHE"/build-runner-* 2> /dev/null || true; }
# runner_same <what>: one such directory, holding the files the first
# tier-1 install left there (logs/runner-first, which this makes): the
# runner was reused, and the install added nothing of its own. The first
# install's library and objects (its sources' names) are not among them:
# they are written in the build root.
runner_same() {
  local o
  [ "$(runner_dirs | wc -l | tr -d ' ')" = 1 ] || fail "$1: not one build-runner directory in rzig's cache ($RZIG_CACHE): '$(runner_dirs | tr '\n' ' ')'"
  (cd "$(runner_dirs)" && find . -type f | LC_ALL=C sort) > "$WORK/logs/runner-now"
  if [ ! -f "$WORK/logs/runner-first" ]; then
    for o in "$p.$SO" $(objects_of "$p"); do
      if grep -q "/$o\$" "$WORK/logs/runner-now"; then fail "$1: $o is in rzig build's shared cache ($(runner_dirs)): an install's objects and library belong in its build root"; fi
    done
    cp "$WORK/logs/runner-now" "$WORK/logs/runner-first"
  fi
  cmp -s "$WORK/logs/runner-first" "$WORK/logs/runner-now" ||
    { diff "$WORK/logs/runner-first" "$WORK/logs/runner-now" | head -10 >&2; fail "$1: the install changed rzig build's shared cache ($(runner_dirs)): the runner must be reused, nothing of an install added"; }
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
# The objects make would name for a package's top-level sources in src/.
objects_of() { tar -tzf "$(tarball_of "$1")" | sed -n -E "s#^$1/src/([^/]+)\.(c|cc|cpp|f|f90|f95)\$#\1.o#p"; }

# --- tier 1: both paths, compared, on the compile tree ----------------------
echo "== tier 1: R CMD INSTALL through rzig build, and through make ($OS/$FLAVOR, the compile tree)"
for p in $PKGS; do
  t="$(tarball_of "$p")"
  tz=$(install_pkg "$WORK/lib-zig" "$t" "$p-zig") || { tail -20 "$WORK/logs/$p-zig.log" >&2; fail "$p: the zig path failed"; }
  grep -q "rzig build: tier 1" "$WORK/logs/$p-zig.log" || fail "$p: the zig path did not report 'rzig build: tier 1' (logs/$p-zig.log)"
  [ -z "$(make_recipes "$WORK/logs/$p-zig.log")" ] || fail "$p: a recipe make echoed in the zig path's log"
  grep -q '^using C compiler\|^using C++ compiler\|^using Fortran compiler' "$WORK/logs/$p-zig.log" || fail "$p: no 'using ... compiler' line in the zig path's log"
  # the first install compiles the build runner, the others reuse it
  if [ -f "$WORK/logs/runner-first" ]; then runner=""; else runner=" (and the build runner)"; fi
  runner_same "$p"
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
  printf '   %-9s zig %3ss%s, make %3ss: %s exports and %s rzig command lines identical\n' "$p" "$tz" "$runner" "$tm" "$n" "$a"
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

# --- the caches: nothing per install outlives it ----------------------------
echo "== caches: one build runner for every tier-1 install; a kept build root; a second install of a tarball adds nothing to zig's global cache; ZIG_LOCAL_CACHE_DIR; two installs at once"
# From the tarball, as install.packages installs: R unpacks it into a new
# R.INSTALL directory each time, so a compile keyed on the source's
# absolute path would add one entry per source per install, which make's
# `-c <file>` from src/ does not [tests-T1].
rm -rf "$WORK/work/lib-again"; mkdir -p "$WORK/work/lib-again"
install_pkg "$WORK/work/lib-again" "$(tarball_of cli)" "again-1" > /dev/null || { tail -20 "$WORK/logs/again-1.log" >&2; fail "cli (its tarball) failed to install"; }
g1=$(global_entries)
t2=$(install_pkg "$WORK/work/lib-again" "$(tarball_of cli)" "again-2") || { tail -20 "$WORK/logs/again-2.log" >&2; fail "cli (its tarball, again) failed to install"; }
g2=$(global_entries)
grep -q "rzig build: tier 1" "$WORK/logs/again-2.log" || fail "the second install of cli did not go through rzig build"
[ "$g1" = "$g2" ] || fail "a second install of the cli tarball added $((g2 - g1)) entries to zig's global cache ($ZIG_GLOBAL_CACHE_DIR/o: $g1, then $g2): rzig build's compiles must be keyed as make's, by the source's path relative to src/"
runner_same "cli's tarball, twice"
# and why: each compile named its source relative to src/ (the count holds
# only while R's temp dir has no build.zig above it, where zig cc would
# cache in that directory's .zig-cache instead) [tests-T1, tests-T7]
[ -z "$(abs_sources "$WORK/logs/again-2.log")" ] || { abs_sources "$WORK/logs/again-2.log" | head -3 >&2; fail "rzig build compiled a source by its absolute path (logs/again-2.log): compiles must name it relative to src/, as make does"; }
echo "   cli's tarball twice: $g1 entries in zig's global cache before and after, every source named relative to src/, the build runner reused; the second install ${t2}s (make ${cli_make}s)"
# A kept build root holds what the install's steps wrote, the plan, the
# objects (obj/) and the library, and no zig build cache: that is the
# build runner's, shared (pkgbuild.zig's sharedRunner).
rm -rf "$WORK/work/kept"; mkdir -p "$WORK/work/kept"
tar -xzf "$(tarball_of digest)" -C "$WORK/work/kept"
RZIG_KEEP_ROOT=1 install_pkg "$WORK/work/lib-again" "$WORK/work/kept/digest" "kept" > /dev/null || { tail -20 "$WORK/logs/kept.log" >&2; fail "digest (from its directory, RZIG_KEEP_ROOT=1) failed to install"; }
kr="$WORK/work/kept/digest/src/.rzig"
test -f "$kr/plan.zon" && test -f "$kr/digest.$SO" || fail "digest's kept build root ($kr) lacks plan.zon or digest.$SO"
[ -n "$(find "$kr/obj" -name '*.o' 2> /dev/null)" ] || fail "no object in digest's kept build root ($kr/obj)"
test ! -e "$kr/zig-cache" || fail "digest's kept build root has a zig build cache ($kr/zig-cache): tier 1's is the shared build runner's"
runner_same "digest (its build root kept)"
rm -rf "$WORK/work/kept"
echo "   digest's kept build root: plan.zon, obj/, digest.$SO and no zig-cache; the build runner reused"
# ZIG_LOCAL_CACHE_DIR, when set, is rzig build's --cache-dir in place of
# its default (tier 1: the build runner's directory in rzig's cache;
# pkgbuild.zig's zigBuildDirs), and the root still goes with the install:
# from a directory, where the root is the package's src/.rzig
# [preflight-PF-8, tests-3].
rm -rf "$WORK/work/again" "$WORK/work/zlc"; mkdir -p "$WORK/work/again"
tar -xzf "$(tarball_of cli)" -C "$WORK/work/again"
ZIG_LOCAL_CACHE_DIR="$(wpath "$WORK/work/zlc")" install_pkg "$WORK/work/lib-again" "$WORK/work/again/cli" "again-zlc" > /dev/null || { tail -20 "$WORK/logs/again-zlc.log" >&2; fail "cli (from its directory, ZIG_LOCAL_CACHE_DIR set) failed to install"; }
grep -q "rzig build: tier 1" "$WORK/logs/again-zlc.log" || fail "cli with ZIG_LOCAL_CACHE_DIR set did not go through rzig build"
# the file itself, not `tr | grep -q`: grep -q stops at its match, and
# tr's SIGPIPE on the rest of a 64 KiB log fails the pipeline (pipefail);
# the match ends in a space, so a CR does not matter [tests-SIGPIPE-1]
grep -q -E -- '--cache-dir [^ ]*zlc( |$)' "$WORK/logs/again-zlc.log" || fail "with ZIG_LOCAL_CACHE_DIR set, zig build did not run with --cache-dir <it> (logs/again-zlc.log)"
[ -n "$(ls "$WORK/work/zlc/o" 2> /dev/null)" ] || fail "with ZIG_LOCAL_CACHE_DIR=$WORK/work/zlc, nothing of rzig build's cache is there"
test ! -e "$WORK/work/again/cli/src/.rzig" || fail "the build root was left in cli's src/ (ZIG_LOCAL_CACHE_DIR set)"
runner_same "cli with ZIG_LOCAL_CACHE_DIR"
echo "   cli with ZIG_LOCAL_CACHE_DIR: rzig build's cache there, no build root left in src/"
# Two tier-1 packages at once from a cold rzig cache, as install.packages
# installs them with Ncpus = 2 (make -j2 over R CMD INSTALL; the build
# tools' make first on PATH, as R CMD has it): the first zig build to need
# the build runner compiles it, holding zig's lock on its manifest, and
# the other waits and takes it. "begin installing" is the parallel path's
# make echoing its targets.
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
# ls fails with no such directory: guarded, so that fail says so under
# set -e and pipefail [tests-2]
n=$( (ls -d "$WORK/work/cache-par/r-zig"/build-runner-* 2> /dev/null || true) | wc -l | tr -d ' ')
[ "$n" = 1 ] || fail "two installs at once from a cold rzig cache left $n build-runner directories, not one"
echo "   cli and digest at once (install.packages, Ncpus = 2) from a cold rzig cache: both built, one build runner, $((e - s))s"

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
# tier 2 keeps its zig build cache in the build root: its runner imports
# the package's build.zig from this install's path, new every install
runner_same zighello
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
test -f "$WORK/work/lib-neg/cli/$LIBSUB/cli.$SO" || fail "tier 3: make did not build cli"
rm -rf "$WORK/work/lib-neg"; mkdir -p "$WORK/work/lib-neg"
if R_ZIG_PKG_BUILDER=zig install_pkg "$WORK/work/lib-neg" "$WORK/work/neg/cli" "neg-zig" --no-test-load > /dev/null; then fail "tier 3: R_ZIG_PKG_BUILDER=zig installed a package that needs make"; fi
grep -q "needs make, and R_ZIG_PKG_BUILDER is 'zig'" "$WORK/logs/neg-zig.log" || { tail -5 "$WORK/logs/neg-zig.log" >&2; fail "tier 3: R_ZIG_PKG_BUILDER=zig failed without the expected message"; }
echo "   configure: falls through to make under auto, refused under zig"

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

echo "== pkg-parity verified ($OS/$FLAVOR): $PKGS through rzig build match make on the compile tree; tier 2 (its URL refusal, MAKEFLAGS, a plan that needs make), tier 3, the caches and the no-make install on the base behave"
