#!/usr/bin/env bash
# L6 on linux: R in one pixi env (r-zig-slim from universe, this branch's
# rzig copied over R_HOME/bin/toolchain's names), the toolchain in another
# (zig, flang-zig, flang-rt-zig, libstdcxx-devel, make), named by
# R_ZIG_TOOLCHAIN_ENV. PATH holds R's env's bin and the host's /usr/bin
# and /bin only: no zig, flang or make on it.
#   bash l6.sh <R env root> <toolchain env root> <rzig binary> <work dir>
set -u
R_ENV=$1; TC_ENV=$2; RZIG=$3; W=$4
TC="$R_ENV/lib/R/bin/toolchain"
for n in rzig zig-cc zig-cxx zig-fc zig-ar zig-ranlib; do [ -e "$TC/$n" ] && cp "$RZIG" "$TC/$n"; done
mkdir -p "$W/lib" && cd "$W"
export PATH="$R_ENV/bin:/usr/bin:/bin" ZIG_GLOBAL_CACHE_DIR="$W/zig-cache" ZIG_LOCAL_CACHE_DIR="$W/zig-cache" XDG_CACHE_HOME="$W/cache"
unset ZIG_BIN R_ZIG_EXTRA_ENV CONDA_PREFIX
probe() { echo "PROBE $1: $2"; }
mk() { # name, file, code, [Makevars line]
  mkdir -p "$1/src" "$1/R"
  printf 'Package: %s\nVersion: 0.1\nTitle: t\nDescription: t.\nLicense: MIT\nAuthor: t\nMaintainer: t <t@t.t>\n' "$1" > "$1/DESCRIPTION"
  printf 'useDynLib(%s, .registration = TRUE)\n' "$1" > "$1/NAMESPACE"
  printf '%s\n' "$3" > "$1/src/$2"
  [ -n "${4:-}" ] && printf '%s\n' "$4" > "$1/src/Makevars"
}
mk l6c a.c '#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
SEXP c_one(void) { return Rf_ScalarInteger(1); }
static const R_CallMethodDef m[] = {{"c_one", (DL_FUNC) &c_one, 0}, {NULL, NULL, 0}};
void R_init_l6c(DllInfo *d) { R_registerRoutines(d, NULL, m, NULL, NULL); }'
mk l6cxx a.cpp '#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <string>
#include <stdexcept>
extern "C" SEXP cxx_two(void) { try { throw std::runtime_error(std::string("two")); } catch (const std::exception& e) { return Rf_mkString(e.what()); } }
static const R_CallMethodDef m[] = {{"cxx_two", (DL_FUNC) &cxx_two, 0}, {NULL, NULL, 0}};
extern "C" void R_init_l6cxx(DllInfo *d) { R_registerRoutines(d, NULL, m, NULL, NULL); }'
mk l6f f.f90 'subroutine three(x) bind(c, name="three")
  use iso_c_binding
  real(c_double), intent(out) :: x
  x = 3d0
end subroutine'
printf '#include <R.h>\n#include <R_ext/Rdynload.h>\nvoid three(double *);\nstatic const R_CMethodDef m[] = {{"three", (DL_FUNC) &three, 1}, {NULL, NULL, 0}};\nvoid R_init_l6f(DllInfo *d) { R_registerRoutines(d, m, NULL, NULL, NULL); }\n' > l6f/src/init.c
for mode in none tcenv; do
  if [ $mode = tcenv ]; then export R_ZIG_TOOLCHAIN_ENV="$TC_ENV"; else unset R_ZIG_TOOLCHAIN_ENV; fi
  "$TC/zig-cc" --rzig-check > check-$mode.log 2>&1; probe "check-compilers-$mode" "exit $? $(head -1 check-$mode.log)"
  "$TC/zig-cc" --rzig-check=fortran > checkf-$mode.log 2>&1; probe "check-fortran-$mode" "exit $? $(head -1 checkf-$mode.log)"
  "$TC/zig-cc" --rzig-check=build-tools > checkb-$mode.log 2>&1; probe "check-build-tools-$mode" "exit $? $(head -1 checkb-$mode.log)"
  for p in l6c l6cxx l6f; do
    rm -rf "lib/$p"
    if RZIG_TRACE=1 R CMD INSTALL --no-test-load -l lib $p > inst-$p-$mode.log 2>&1 &&
       out=$(Rscript -e ".libPaths('lib'); library($p); r <- switch('$p', l6c = .Call('c_one', PACKAGE = 'l6c'), l6cxx = .Call('cxx_two', PACKAGE = 'l6cxx'), l6f = .C('three', x = 0, PACKAGE = 'l6f')\$x); cat(r)" 2>&1); then
      probe "$p-$mode" "ok: $out; zig: $(grep -m1 -o "[^ ']*/bin/zig c[c+]*" inst-$p-$mode.log)$( [ $p = l6f ] && echo "; flang: $(grep -m1 -o "[^ ']*/flang " inst-$p-$mode.log)")"
    else
      probe "$p-$mode" "FAIL: $(grep -m2 -E 'no zig|no flang|error' inst-$p-$mode.log | tr '\n' ' ')"
    fi
  done
done
