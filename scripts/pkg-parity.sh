#!/usr/bin/env bash
# Package-build parity (feat-zig-pkg-build PLAN.md, milestone 4): R CMD
# INSTALL through `rzig build` (install.R's hook, patch 0013) must give
# what the make path gives, on the installed tree of this build.
#
# For cli (C), digest (C and C++), quadprog (Fortran) and Rcpp (C++),
# fetched from CRAN once into build/pkg-parity-<flavor>/src:
#   - the zig path (`RZIG_TRACE=1`): the log says `rzig build: tier 1`
#     and has no make output;
#   - the make path (`R_ZIG_PKG_BUILDER=make`, also traced) builds the
#     same package into a second library;
#   - the two libraries' exported symbols are identical (nm; Windows:
#     objdump's export table);
#   - rzig received the same command lines on both paths: every compile
#     and the link, compared as sorted sets of words (paths by basename,
#     quotes dropped). The known differences are normalised away: on
#     macOS the `-Wl,-install_name,<pkg>.so` only rzig passes (make's
#     linker derives the same name from -o), on Windows the .def file's
#     name (`tmp.def` from nm | sed, `<pkg>.def` from `rzig def`);
#   - a smoke script loads and exercises the packages from each library
#     and prints the same values.
# Then the tier-2 fixture (.github/devdocs/feat-zig-pkg-build/proto/
# zighello, a zig package: `rzig build: tier 2`, `hello(21L)` is 42), the
# tier-3 negative (cli with a `configure` script falls through to make;
# with R_ZIG_PKG_BUILDER=zig that is an error), and an install with no
# make or sh on PATH (unix: a directory holding only sh, zig and flang;
# Windows: System32 plus a copy of flang, zig through ZIG_BIN).
. "$(dirname "$0")/env.sh"

case "$OS" in
  linux|macos|windows) ;;
  *) echo "pkg-parity: unsupported OS '$OS'" >&2; exit 1 ;;
esac
TREE="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
if [ "$OS" = windows ]; then
  RH="$TREE/Library/lib/R"; R_EXE="$RH/bin/x64/R.exe"; RSCRIPT="$RH/bin/x64/Rscript.exe"; SO=dll; LIBSUB=libs/x64
else
  RH="$TREE/lib/R"; R_EXE="$RH/bin/R"; RSCRIPT="$RH/bin/Rscript"; SO=so; LIBSUB=libs
fi
test -x "$R_EXE" || { echo "error: no R at $R_EXE; run 'pixi run build' first" >&2; exit 1; }
test -x "$RH/bin/toolchain/rzig" || test -x "$RH/bin/toolchain/rzig.exe" || { echo "error: $RH/bin/toolchain has no rzig" >&2; exit 1; }

PKGS="cli digest quadprog Rcpp"
WORK="$BUILD_DIR/pkg-parity-$FLAVOR"
SRC="$WORK/src"
ZIGHELLO="$ROOT/.github/devdocs/feat-zig-pkg-build/proto/zighello"
rm -rf "$WORK/lib-zig" "$WORK/lib-make" "$WORK/lib-nomake" "$WORK/logs" "$WORK/work"
mkdir -p "$SRC" "$WORK/lib-zig" "$WORK/lib-make" "$WORK/lib-nomake" "$WORK/logs" "$WORK/work"
cd "$WORK"

# A path as R.exe wants it on Windows (msys converts most arguments, not
# all); unchanged elsewhere.
wpath() { if [ "$OS" = windows ]; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
# Nothing of the caller's selects a path or a compiler.
unset R_ZIG_PKG_BUILDER MAKEFLAGS
export R_MAKEVARS_USER="$(wpath "$WORK/no-such-makevars")"
export RZIG_TRACE=1

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
# header) and sorted.
argv_of() {
  grep -E '^(zig-cc|zig-cxx|zig-fc): ' "$1" \
    | grep -v -E -- '--version|^zig-(cc|cxx|fc): (self|environment) |ZIG_LIB_DIR=' \
    | tr -d "'\"" \
    | sed -E 's#[^ ]*[\\/]([^\\/ ]+)#\1#g; s/ -Wl,-install_name,[^ ]+//; s/[^ ]*\.def( |$)/X.def\1/' \
    | LC_ALL=C sort
}
make_lines() { grep -c -E '^make(\[[0-9]+\])?[: ]' "$1" || true; }

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

# --- tier 1: both paths, compared ---------------------------------------------
echo "== tier 1: R CMD INSTALL through rzig build, and through make ($OS/$FLAVOR)"
for p in $PKGS; do
  t="$(tarball_of "$p")"
  tz=$(install_pkg "$WORK/lib-zig" "$t" "$p-zig") || { tail -20 "$WORK/logs/$p-zig.log" >&2; fail "$p: the zig path failed"; }
  grep -q "rzig build: tier 1" "$WORK/logs/$p-zig.log" || fail "$p: the zig path did not report 'rzig build: tier 1' (logs/$p-zig.log)"
  [ "$(make_lines "$WORK/logs/$p-zig.log")" = 0 ] || fail "$p: make output in the zig path's log"
  grep -q '^using C compiler\|^using C++ compiler\|^using Fortran compiler' "$WORK/logs/$p-zig.log" || fail "$p: no 'using ... compiler' line in the zig path's log"
  tm=$(R_ZIG_PKG_BUILDER=make install_pkg "$WORK/lib-make" "$t" "$p-make") || { tail -20 "$WORK/logs/$p-make.log" >&2; fail "$p: the make path failed"; }
  grep -q "rzig build:" "$WORK/logs/$p-make.log" && fail "$p: R_ZIG_PKG_BUILDER=make still ran rzig build"
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
  printf '   %-9s zig %3ss, make %3ss: %s exports and %s rzig command lines identical\n' "$p" "$tz" "$tm" "$n" "$a"
done

cat > "$WORK/work/smoke.R" <<'EOF'
lib <- commandArgs(TRUE)[1]
.libPaths(c(lib, .libPaths()))
chk <- function(name, expr) { v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e))); cat(sprintf("%-12s %s\n", name, paste(format(v), collapse = " "))) }
library(cli); chk("cli", nchar(cli::rule()) > 10); chk("cli-md5", cli::hash_md5("abc"))
library(digest); chk("digest", digest::digest("abc", algo = "sha256", serialize = FALSE))
library(quadprog); chk("quadprog", quadprog::solve.QP(diag(2), c(1, 1), diag(2), c(0, 0))$solution)
library(Rcpp); chk("Rcpp-reg", length(getDLLRegisteredRoutines("Rcpp")$.Call) > 10)
for (p in c("cli", "digest", "quadprog", "Rcpp")) { chk(paste0("dll-", p), basename(getLoadedDLLs()[[p]][["path"]])); unloadNamespace(p) }
cat("unloaded all\n")
EOF
for l in zig make; do
  "$RSCRIPT" --vanilla "$WORK/work/smoke.R" "$(wpath "$WORK/lib-$l")" > "$WORK/logs/smoke-$l.out" 2>&1 || { cat "$WORK/logs/smoke-$l.out" >&2; fail "the smoke script failed on lib-$l"; }
  grep -q "ERROR" "$WORK/logs/smoke-$l.out" && { cat "$WORK/logs/smoke-$l.out" >&2; fail "an error in the smoke output of lib-$l"; }
  grep -q "^unloaded all" "$WORK/logs/smoke-$l.out" || fail "the smoke script did not run to the end on lib-$l"
done
cmp -s "$WORK/logs/smoke-zig.out" "$WORK/logs/smoke-make.out" || { diff "$WORK/logs/smoke-zig.out" "$WORK/logs/smoke-make.out" >&2; fail "the smoke outputs differ between the two libraries"; }
echo "   smoke: $(grep -c . "$WORK/logs/smoke-zig.out") lines identical on both libraries"

# --- tier 2: a zig package --------------------------------------------------
echo "== tier 2: zighello"
test -f "$ZIGHELLO/src/build.zig" || fail "no tier-2 fixture at $ZIGHELLO"
rm -rf "$WORK/work/zighello"; cp -R "$ZIGHELLO" "$WORK/work/zighello"
tz=$(install_pkg "$WORK/lib-zig" "$WORK/work/zighello" "zighello") || { tail -30 "$WORK/logs/zighello.log" >&2; fail "zighello failed to install"; }
grep -q "rzig build: tier 2" "$WORK/logs/zighello.log" || fail "zighello: no 'rzig build: tier 2' in the log"
grep -q "^using zig: " "$WORK/logs/zighello.log" || fail "zighello: no 'using zig:' line in the log"
[ "$(make_lines "$WORK/logs/zighello.log")" = 0 ] || fail "zighello: make output in the log"
v=$("$RSCRIPT" --vanilla -e '.libPaths(c(commandArgs(TRUE)[1], .libPaths())); library(zighello); cat(hello(21L), "\n"); unloadNamespace("zighello")' "$(wpath "$WORK/lib-zig")" 2>&1 | tail -1 | tr -d ' \r')
[ "$v" = 42 ] || fail "zighello: hello(21L) printed '$v', not 42"
exports_of "$WORK/lib-zig/zighello/$LIBSUB/zighello.$SO" | grep -q "R_init_zighello" || fail "zighello: R_init_zighello is not exported"
test -e "$WORK/work/zighello/src/.rzig" && fail "zighello: the build root was left in src/"
test -e "$WORK/work/zighello/src/.zig-cache" && fail "zighello: a .zig-cache was left in src/"
echo "   zighello: tier 2, ${tz}s with the test load, hello(21L) = 42, R_init_zighello exported"

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

# --- no make, no sh ----------------------------------------------------------
echo "== no make on PATH"
NOMAKE="$WORK/work/nomake-bin"; rm -rf "$NOMAKE"; mkdir -p "$NOMAKE"
zig_bin="${ZIG_BIN:-$(command -v zig || true)}"
test -n "$zig_bin" || fail "no zig to put on the restricted PATH (ZIG_BIN or PATH)"
pkg=quadprog
if [ "$OS" = windows ]; then
  fl="$(command -v flang.exe || command -v flang || true)"
  if [ -n "$fl" ]; then for f in flang.exe flang-new.exe flang.cfg flang-compile.cfg; do [ -f "$(dirname "$fl")/$f" ] && cp "$(dirname "$fl")/$f" "$NOMAKE/"; done; else pkg=cli; fi
  sysdir="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")"
  NOMAKE_ENV=(SYSTEMROOT="$SYSTEMROOT" WINDIR="${WINDIR:-$SYSTEMROOT}" HOME="$(wpath "$WORK/work")" TMPDIR="$(wpath "$WORK/work")" PATH="$NOMAKE:$sysdir/System32" ZIG_BIN="$(wpath "$zig_bin")" R_MAKEVARS_USER="$R_MAKEVARS_USER")
else
  ln -s "$(command -v sh)" "$NOMAKE/sh"; ln -s "$zig_bin" "$NOMAKE/zig"
  fl="$(command -v flang || command -v flang-new || true)"
  if [ -n "$fl" ]; then ln -s "$fl" "$NOMAKE/flang"; else pkg=cli; fi
  NOMAKE_ENV=(HOME="$WORK/work" TMPDIR="$WORK/work" PATH="$NOMAKE" R_MAKEVARS_USER="$R_MAKEVARS_USER")
fi
s=$(date +%s)
env -i "${NOMAKE_ENV[@]}" "$R_EXE" CMD INSTALL -l "$(wpath "$WORK/lib-nomake")" "$(wpath "$(tarball_of $pkg)")" > "$WORK/logs/nomake-$pkg.log" 2>&1 || { tail -20 "$WORK/logs/nomake-$pkg.log" >&2; fail "$pkg did not install with only $(ls "$NOMAKE" | tr '\n' ' ')on PATH"; }
e=$(date +%s)
test -f "$WORK/lib-nomake/$pkg/$LIBSUB/$pkg.$SO" || fail "no $pkg.$SO from the no-make install"
echo "   $pkg: installed in $((e - s))s with PATH = $(ls "$NOMAKE" | tr '\n' ' ')$([ "$OS" = windows ] && echo '+ System32 (zig through ZIG_BIN)')"

echo "== pkg-parity verified ($OS/$FLAVOR): $PKGS through rzig build match make; tier 2, tier 3 and the no-make install behave"
