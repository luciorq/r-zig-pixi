#!/usr/bin/env bash
# Install the r-zig wheel the way a pip user would and use it with the
# pixi env out of the picture: fresh venv, PATH scrubbed to the venv +
# /usr/bin:/bin, no CONDA_PREFIX. Checks, in order:
#   - the R/Rscript console scripts and `python -m r_zig` run R
#   - the minimal capability profile, from inside the installed wheel
#   - R CMD INSTALL of a small package with C and C++ sources that calls
#     BLAS through CRAN's usual `$(BLAS_LIBS) $(FLIBS)` — compiled by the
#     PyPI ziglang package and built by the bundled GNU make, three times:
#     through the console script (ZIG_BIN from `import ziglang`) and
#     through the bundled bin/R directly with ZIG_BIN unset (the path an
#     embedder such as rpy2 takes: Renviron.site finds ziglang next door),
#     and once more with ZIG_BIN pointing nowhere (python3 -m ziglang)
# pip fetches ziglang (~100 MB) from PyPI, so this needs network; point
# PIP_FIND_LINKS at a directory holding the ziglang wheel to avoid that.
. "$(dirname "$0")/env.sh"

shopt -s nullglob
wheels=("$ROOT"/dist/wheel/r_zig-"$R_VERSION"-*.whl)
[ "${#wheels[@]}" = 1 ] || { echo "error: expected exactly one r_zig-$R_VERSION wheel in dist/wheel, found ${#wheels[@]} — run 'pixi run -e wheel wheel'" >&2; exit 1; }
wheel="${wheels[0]}"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
echo "== installing $(basename "$wheel") (+ ziglang from PyPI) into a fresh venv"
python -m venv "$T/venv"
"$T/venv/bin/python" -m pip install --quiet --disable-pip-version-check "$wheel"
"$T/venv/bin/python" -m pip list --disable-pip-version-check 2>/dev/null | grep -iE '^(r-zig|ziglang) '

# The package: C (registration + a BLAS ddot call) and C++ (via .Call).
P="$T/src/rzigwheeltest"
mkdir -p "$P/R" "$P/src"
cat > "$P/DESCRIPTION" << 'EOF'
Package: rzigwheeltest
Version: 0.1
Title: r-zig Wheel Contract Test
Description: Compiled-code smoke test for the r-zig wheel.
License: GPL-2
Authors@R: person("r-zig-pixi", role = c("aut", "cre"), email = "noreply@example.com")
EOF
cat > "$P/NAMESPACE" << 'EOF'
useDynLib(rzigwheeltest, .registration = TRUE)
export(dot, cxx_sum)
EOF
cat > "$P/R/fns.R" << 'EOF'
dot <- function(x, y) .Call(C_dot, as.double(x), as.double(y))
cxx_sum <- function(x) .Call(C_cxx_sum, as.double(x))
EOF
cat > "$P/src/dot.c" << 'EOF'
#include <R.h>
#include <Rinternals.h>
#include <R_ext/BLAS.h>
#include <R_ext/Rdynload.h>

SEXP cxx_sum(SEXP x);

static SEXP dot(SEXP x, SEXP y) {
    int n = LENGTH(x), one = 1;
    return ScalarReal(F77_CALL(ddot)(&n, REAL(x), &one, REAL(y), &one));
}

static const R_CallMethodDef calls[] = {
    {"C_dot", (DL_FUNC) &dot, 2},
    {"C_cxx_sum", (DL_FUNC) &cxx_sum, 1},
    {NULL, NULL, 0}
};

void R_init_rzigwheeltest(DllInfo *dll) {
    R_registerRoutines(dll, NULL, calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
EOF
cat > "$P/src/sum.cpp" << 'EOF'
#include <numeric>
#include <vector>
#include <Rinternals.h>

extern "C" SEXP cxx_sum(SEXP x) {
    std::vector<double> v(REAL(x), REAL(x) + LENGTH(x));
    return Rf_ScalarReal(std::accumulate(v.begin(), v.end(), 0.0));
}
EOF
echo 'PKG_LIBS = $(BLAS_LIBS) $(FLIBS)' > "$P/src/Makevars"

mkdir -p "$T/home" "$T/lib1" "$T/lib2"
run() {
  env -i HOME="$T/home" PATH="$T/venv/bin:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" LANG=C.UTF-8 "$@"
}

echo "== console scripts"
run R --version | head -1
run python -m r_zig --version | head -1
run python -c 'import r_zig; print("r_home:", r_zig.r_home()); print("zig_bin:", r_zig.zig_bin())'
r_home="$(run python -c 'import r_zig; print(r_zig.r_home())')"

echo "== capability profile + toolchain wiring (inside the installed wheel)"
run Rscript -e '
  caps <- capabilities()
  stopifnot(!caps[["cairo"]], !caps[["png"]], !caps[["ICU"]], caps[["libcurl"]], caps[["iconv"]])
  stopifnot(grepl("/r_zig/R/lib/R$", R.home()))
  mk <- Sys.getenv("MAKE")
  stopifnot(file.exists(mk), grepl("bin/toolchain/make$", mk))
  cat("MAKE =", mk, "\n")
  set.seed(1); m <- matrix(rnorm(64), 8)
  stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
  cat("profile OK\n")
'

echo "== R CMD INSTALL via the console script (ZIG_BIN from import ziglang)"
run R CMD INSTALL --preclean -l "$T/lib1" "$P"
run Rscript -e "
  library(rzigwheeltest, lib.loc = '$T/lib1')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('compiled package OK (console script)\n')
"

echo "== R CMD INSTALL via bundled bin/R, ZIG_BIN unset (Renviron.site -> sibling ziglang)"
run "$r_home/bin/R" CMD INSTALL --preclean -l "$T/lib2" "$P"
run "$r_home/bin/Rscript" -e "
  stopifnot(nzchar(Sys.getenv('ZIG_BIN')), file.exists(Sys.getenv('ZIG_BIN')))
  cat('ZIG_BIN =', normalizePath(Sys.getenv('ZIG_BIN')), '\n')
  library(rzigwheeltest, lib.loc = '$T/lib2')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('compiled package OK (bundled bin/R)\n')
"
echo "== R CMD INSTALL with ZIG_BIN pointing nowhere and no zig on PATH (python3 -m ziglang)"
mkdir -p "$T/lib3"
run ZIG_BIN=/nonexistent/zig "$r_home/bin/R" CMD INSTALL --preclean -l "$T/lib3" "$P"
run "$r_home/bin/Rscript" -e "
  library(rzigwheeltest, lib.loc = '$T/lib3')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('compiled package OK (python3 -m ziglang fallback)\n')
"
echo "== wheel test passed ($(basename "$wheel"))"
