#!/usr/bin/env bash
# Smoke test for rzig on linux (feat-no-host-paths phase F3): real compiles
# through the real zig.
#
#   zigbuild/tools/rzig/smoke-test.sh [R-prefix]
#
# 1. Copies of rzig named zig-cc, zig-cxx, zig-ar and zig-ranlib build a C
#    and a C++ shared library, a static archive and a program using all
#    three, which must run. The libraries must carry their SONAME, link no
#    shared libc++ and need glibc 2.17 at most. The same commands through
#    the bash shims in toolchain/ must produce byte-identical files.
# 2. With an R prefix (an installed tree such as dist/R-4.6.1-slim-zig,
#    whose bin/toolchain is rzig since F3a): small C, C++, Fortran and
#    OpenMP packages install from source and load, and with
#    RZIG_SMOKE_CRAN=1 also CRAN's Rcpp, data.table and quadprog.
#
# Needs zig on PATH (or ZIG); for 2. also flang and make: run it inside the
# pixi env the tree was built in.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
shims=$(cd "$here/../../../toolchain" && pwd)
ZIG=${ZIG:-$(command -v zig)}
T=$(mktemp -d "${TMPDIR:-/tmp}/rzig-smoke.XXXXXX")
trap 'rm -rf "$T"' EXIT

# (zig's local cache out of the source tree, which the recipe copies)
"$ZIG" build --build-file "$here/build.zig" --cache-dir "${ZIG_LOCAL_CACHE_DIR:-$T/zig-cache}" --prefix "$T/build"
mkdir -p "$T/rzig" "$T/bash"
for n in zig-cc zig-cxx zig-ar zig-ranlib; do
  cp "$T/build/bin/rzig" "$T/rzig/$n"
  ln -s "$shims/$n" "$T/bash/$n"
done

# --- 1. libraries and a program ---------------------------------------------------
mkdir -p "$T/src"
cat > "$T/src/hello.c" << 'EOF'
int hello(void) { return 42; }
EOF
cat > "$T/src/greet.cpp" << 'EOF'
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>
extern "C" int greet(int n) {
  try {
    if (n < 0) throw std::runtime_error("negative");
    std::vector<int> v(n);
    std::iota(v.begin(), v.end(), 1);
    return std::accumulate(v.begin(), v.end(), 0);
  } catch (const std::exception &e) {
    return -static_cast<int>(std::string(e.what()).size());
  }
}
EOF
cat > "$T/src/twice.c" << 'EOF'
int twice(int x) { return 2 * x; }
EOF
cat > "$T/src/main.c" << 'EOF'
#include <stdio.h>
int hello(void); int greet(int); int twice(int);
int main(void) { printf("%d %d %d %d\n", hello(), greet(10), greet(-1), twice(21)); return 0; }
EOF

# Same directory for both, so the command lines are the same strings.
for kind in bash rzig; do
  rm -rf "$T/work"; mkdir "$T/work"
  (
    cd "$T/work"
    export ZIG_BIN="$ZIG"
    t=$T/$kind
    "$t/zig-cc" -O2 -fpic -c ../src/hello.c -o hello.o
    "$t/zig-cc" -shared -o libhello.so hello.o
    "$t/zig-cxx" -O2 -fpic -c ../src/greet.cpp -o greet.o
    "$t/zig-cxx" -shared -o libgreet.so greet.o
    "$t/zig-cc" -O2 -c ../src/twice.c -o twice.o
    "$t/zig-ar" rcs libtwice.a twice.o
    "$t/zig-ranlib" libtwice.a
    "$t/zig-cc" -o main ../src/main.c -L. -lhello -lgreet -ltwice
    out=$(LD_LIBRARY_PATH=. ./main)
    [ "$out" = "42 55 -8 42" ] || { echo "error: $kind: main printed '$out'" >&2; exit 1; }
  )
  mv "$T/work" "$T/out-$kind"
done
echo "ok: C and C++ shared libraries, archive and program built through rzig; the program runs"

o=$T/out-rzig
readelf -d "$o/libhello.so" | grep -q 'SONAME.*\[libhello.so\]' || { echo "error: libhello.so has no SONAME" >&2; exit 1; }
readelf -d "$o/libgreet.so" | grep -q 'SONAME.*\[libgreet.so\]' || { echo "error: libgreet.so has no SONAME" >&2; exit 1; }
if readelf -d "$o/libgreet.so" | grep -E 'NEEDED.*(libc\+\+|libstdc\+\+)'; then
  echo "error: libgreet.so links a shared C++ runtime" >&2; exit 1
fi
glibc=$(objdump -T "$o/libgreet.so" "$o/main" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 || :)
case "$glibc" in GLIBC_2.1[0-7]|GLIBC_2.[0-9]|GLIBC_2.[0-9].*|GLIBC_2.1[0-7].*|"") ;; *) echo "error: needs $glibc" >&2; exit 1 ;; esac
echo "ok: SONAMEs set, no shared libc++, glibc floor ${glibc:-none} (<= 2.17)"
for f in hello.o libhello.so greet.o libgreet.so twice.o libtwice.a main; do
  cmp "$T/out-bash/$f" "$o/$f" || { echo "error: $f differs between the bash shims and rzig" >&2; exit 1; }
done
echo "ok: every file byte-identical to the bash shims' build"

# --- 2. R packages through an installed tree's own rzig -----------------------------
[ $# -ge 1 ] || exit 0
tc=$1/lib/R/bin/toolchain
for n in zig-cc zig-cxx zig-ar zig-ranlib; do
  [ "$(head -c4 "$tc/$n")" = $'\x7fELF' ] || { echo "error: $tc/$n is not rzig" >&2; exit 1; }
done
echo "== $tc: zig-cc zig-cxx zig-ar zig-ranlib are rzig"
R=$1/bin/R

mkpkg() { # mkpkg NAME: DESCRIPTION, NAMESPACE; sources added by the caller
  mkdir -p "$T/pkgs/$1/R" "$T/pkgs/$1/src"
  printf 'Package: %s\nVersion: 0.1\nTitle: rzig smoke\nDescription: rzig smoke test.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$1" > "$T/pkgs/$1/DESCRIPTION"
  printf 'useDynLib(%s)\nexportPattern(".")\n' "$1" > "$T/pkgs/$1/NAMESPACE"
}
mkpkg rzc
cat > "$T/pkgs/rzc/src/c.c" << 'EOF'
#include <Rinternals.h>
SEXP rzc_hello(void) { return Rf_ScalarInteger(42); }
EOF
echo 'hello <- function() .Call("rzc_hello", PACKAGE = "rzc")' > "$T/pkgs/rzc/R/f.R"
mkpkg rzcxx
cat > "$T/pkgs/rzcxx/src/cxx.cpp" << 'EOF'
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>
#include <Rinternals.h>
extern "C" SEXP rzcxx_sum(SEXP x) {
  std::vector<double> v(REAL(x), REAL(x) + Rf_xlength(x));
  try {
    if (v.empty()) throw std::runtime_error("empty");
  } catch (const std::exception &e) {
    return Rf_mkString(e.what());
  }
  return Rf_ScalarReal(std::accumulate(v.begin(), v.end(), 0.0));
}
EOF
echo 'csum <- function(x) .Call("rzcxx_sum", as.double(x), PACKAGE = "rzcxx")' > "$T/pkgs/rzcxx/R/f.R"
mkpkg rzf
cat > "$T/pkgs/rzf/src/dbl.f90" << 'EOF'
subroutine dbl(n, x)
  integer, intent(in) :: n
  double precision, intent(inout) :: x(n)
  double precision, allocatable :: t(:)
  character(len=12) :: buf
  allocate(t(n))
  t = 2d0 * x
  x = t
  deallocate(t)
  write(buf, '(i0)') n  ! the flang runtime's formatted I/O
end subroutine
EOF
echo 'dbl <- function(x) .Fortran("dbl", length(x), x = as.double(x), PACKAGE = "rzf")$x' > "$T/pkgs/rzf/R/f.R"
mkpkg rzomp
cat > "$T/pkgs/rzomp/src/omp.c" << 'EOF'
#ifdef _OPENMP
#include <omp.h>  /* before R's headers, whose `match` macro breaks it */
#endif
#include <Rinternals.h>
SEXP rzomp_threads(void) {
  int n = 0;
#ifdef _OPENMP
#pragma omp parallel
  {
#pragma omp single
    n = omp_get_num_threads();
  }
#endif
  return Rf_ScalarInteger(n);
}
EOF
printf 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)\nPKG_LIBS = $(SHLIB_OPENMP_CFLAGS)\n' > "$T/pkgs/rzomp/src/Makevars"
echo 'threads <- function() .Call("rzomp_threads", PACKAGE = "rzomp")' > "$T/pkgs/rzomp/R/f.R"

mkdir -p "$T/lib"
pkgs="rzc rzcxx rzomp"
grep -q '^FLIBS = .*flang_rt' "$1/lib/R/etc/Makeconf" && command -v flang > /dev/null && pkgs="$pkgs rzf"
for p in $pkgs; do
  "$R" CMD INSTALL -l "$T/lib" "$T/pkgs/$p" > "$T/install-$p.log" 2>&1 || { cat "$T/install-$p.log"; exit 1; }
done
grep -h 'zig-c' "$T"/install-*.log | sed 's/^/   /' | head -8
OMP_NUM_THREADS=2 R_SMOKE_LIB="$T/lib" R_SMOKE_PKGS="$pkgs" "$R" --vanilla -s -e '
  lib <- Sys.getenv("R_SMOKE_LIB")
  pkgs <- strsplit(Sys.getenv("R_SMOKE_PKGS"), " ")[[1]]
  for (p in pkgs) library(p, lib.loc = lib, character.only = TRUE)
  stopifnot(hello() == 42L, csum(1:4) == 10, identical(csum(numeric()), "empty"))
  if ("rzf" %in% pkgs) stopifnot(identical(dbl(c(1, 2.5)), c(2, 5)))
  mk <- readLines(file.path(R.home("etc"), "Makeconf"))
  omp <- any(grepl("^SHLIB_OPENMP_CFLAGS *=.*-fopenmp", mk))
  cat("OpenMP threads:", threads(), "\n")
  if (omp) stopifnot(threads() == 2L)
  cat("ok:", paste(pkgs, collapse = ", "), "built through rzig load and run\n")
' 2>&1 || { echo "error: R package checks failed" >&2; exit 1; }
for so in "$T"/lib/*/libs/*.so; do
  if readelf -d "$so" | grep -E 'NEEDED.*(libc\+\+|libstdc\+\+|flang_rt)'; then
    echo "error: $so links a shared C++ or Fortran runtime" >&2; exit 1
  fi
done
echo "ok: no package links a shared C++ or Fortran runtime"

if [ "${RZIG_SMOKE_CRAN:-}" = 1 ]; then
  R_SMOKE_LIB="$T/lib" "$R" --vanilla -s -e '
    lib <- Sys.getenv("R_SMOKE_LIB"); options(timeout = 300)
    pkgs <- c("Rcpp", "data.table", "quadprog")
    install.packages(pkgs, repos = "https://cloud.r-project.org", lib = lib, type = "source", Ncpus = 4, quiet = TRUE)
    stopifnot(all(pkgs %in% rownames(installed.packages(lib.loc = lib))))
    .libPaths(lib); library(Rcpp); library(data.table); library(quadprog)
    stopifnot(evalCpp("2 + 2") == 4)
    dt <- data.table(g = rep(1:3, 4), x = 1:12)
    stopifnot(identical(dt[, sum(x), by = g][[2]], c(22L, 26L, 30L)))
    sol <- solve.QP(diag(2), c(1, 1), matrix(0, 2, 0), numeric())$solution
    stopifnot(isTRUE(all.equal(sol, c(1, 1))))
    cat("ok: CRAN Rcpp, data.table, quadprog from source through rzig\n")
  ' 2>&1 | grep -v '^\(trying\|Content\|downloaded\|=\+$\)' || { echo "error: CRAN checks failed" >&2; exit 1; }
fi
