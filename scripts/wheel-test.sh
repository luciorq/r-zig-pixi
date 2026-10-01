#!/usr/bin/env bash
# Install the r-zig wheels the way a pip user would and use them with the
# pixi env out of the picture: fresh venv, PATH scrubbed to the venv +
# /usr/bin:/bin, no CONDA_PREFIX. Checks, in order:
#   - r-zig alone (no ziglang, no make): the R/Rscript console scripts and
#     `python -m r_zig` run R, the minimal capability profile, TLS, and
#     R CMD INSTALL of a package with compiled code stops with the compile
#     preflight naming r-zig-toolchain (phase T of feat-no-host-paths)
#   - then r-zig-toolchain (which brings ziglang and GNU make):
#   - R CMD INSTALL of a small package with C and C++ sources that calls
#     BLAS through CRAN's usual `$(BLAS_LIBS) $(FLIBS)` — compiled by the
#     PyPI ziglang package and built by the bundled GNU make, three times:
#     through the console script (ZIG_BIN from `import ziglang`) and
#     through the bundled bin/R directly with ZIG_BIN unset (the path an
#     embedder such as rpy2 takes: Renviron.site finds ziglang next door),
#     and once more with ZIG_BIN pointing nowhere (python3 -m ziglang)
#   - uninstalling r-zig-toolchain removes only R_HOME/bin/toolchain
# pip fetches ziglang (~100 MB) from PyPI, so this needs network; point
# PIP_FIND_LINKS at a directory holding the ziglang wheel to avoid that.
. "$(dirname "$0")/env.sh"

shopt -s nullglob
wheels=("$ROOT"/dist/wheel/r_zig-"$R_VERSION"-*.whl)
[ "${#wheels[@]}" = 1 ] || { echo "error: expected exactly one r_zig-$R_VERSION wheel in dist/wheel, found ${#wheels[@]} — run 'pixi run -e wheel wheel'" >&2; exit 1; }
wheel="${wheels[0]}"
tc_wheels=("$ROOT"/dist/wheel/r_zig_toolchain-"$R_VERSION"-*.whl)
[ "${#tc_wheels[@]}" = 1 ] || { echo "error: expected exactly one r_zig_toolchain-$R_VERSION wheel in dist/wheel, found ${#tc_wheels[@]}" >&2; exit 1; }
tc_wheel="${tc_wheels[0]}"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
echo "== installing $(basename "$wheel") alone into a fresh venv"
python -m venv "$T/venv"
pip_() { "$T/venv/bin/python" -m pip --disable-pip-version-check "$@"; }
pip_ install --quiet "$wheel"
pip_ list 2>/dev/null | grep -iE '^(r-zig|r-zig-toolchain|ziglang) '
if pip_ show ziglang > /dev/null 2>&1; then
  echo "error: r-zig alone pulled in ziglang" >&2; exit 1
fi

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
  stopifnot(!file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
  set.seed(1); m <- matrix(rnorm(64), 8)
  stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
  cat("profile OK\n")
'

echo "== TLS trust (CA bundle shipped in the wheel, also under --vanilla)"
# conda-forge's libcurl/OpenSSL in the wheel carry the build env's CA path
# compiled in; the wheel ships etc/ca-bundle.crt and R's libcurl.c picks
# the trust anchors itself (package-standalone.sh, zig-build.sh). Same
# check as verify-bundle.sh: scripts/tls-check.R.
run Rscript --vanilla "$(cd "$(dirname "$0")" && pwd)/tls-check.R"

echo "== r-zig alone: compiled code stops with the preflight"
mkdir -p "$T/lib0"
if run R CMD INSTALL -l "$T/lib0" "$P" > "$T/preflight.out" 2>&1; then
  cat "$T/preflight.out" >&2; echo "error: R CMD INSTALL compiled without the toolchain" >&2; exit 1
fi
grep -F "r-zig toolchain is not installed" "$T/preflight.out" | grep -F "pip install r-zig-toolchain" ||
  { cat "$T/preflight.out" >&2; echo "error: no preflight message naming r-zig-toolchain" >&2; exit 1; }

echo "== installing $(basename "$tc_wheel") (+ ziglang from PyPI)"
pip_ install --quiet "$tc_wheel"
pip_ list 2>/dev/null | grep -iE '^(r-zig|r-zig-toolchain|ziglang) '
run Rscript -e '
  mk <- Sys.getenv("MAKE")
  stopifnot(file.exists(mk), grepl("bin/toolchain/make$", mk))
  cat("MAKE =", mk, "\n")
'

echo "== R CMD INSTALL via the console script (ZIG_BIN from import ziglang)"
run R CMD INSTALL --preclean -l "$T/lib1" "$P"
run Rscript -e "
  library(rzigwheeltest, lib.loc = '$T/lib1')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('compiled package OK (console script)\n')
"

# The wheel compiles with PyPI ziglang, an upstream zig build, which links
# its own libc++ statically, so C++ packages carry no C++ runtime
# dependency. conda-forge's zig is patched to link a shared libc++ when
# one sits beside its install (always the case in a macOS conda env), so
# a zig from a conda env on PATH would bring that dependency back.
so="$T/lib1/rzigwheeltest/libs/rzigwheeltest.so"
if command -v readelf > /dev/null 2>&1; then
  cxx_deps="$(readelf -d "$so" | grep -E 'NEEDED.*lib(c\+\+|stdc\+\+)' || true)"
elif command -v otool > /dev/null 2>&1; then
  cxx_deps="$(otool -L "$so" | tail -n +2 | grep -E 'lib(c\+\+|stdc\+\+)' || true)"
else
  cxx_deps="unchecked"
fi
case "$cxx_deps" in
  "") echo "== C++ runtime: static (no shared libc++/libstdc++ dependency)" ;;
  unchecked) echo "note: neither readelf nor otool found; C++ runtime linkage not checked" ;;
  *) echo "error: the C++ test package depends on a shared C++ runtime:" >&2
     echo "$cxx_deps" >&2; exit 1 ;;
esac

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
echo "== uninstalling r-zig-toolchain leaves r-zig whole"
pip_ uninstall --quiet -y r-zig-toolchain
run Rscript -e '
  stopifnot(!file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
  stopifnot(file.exists(file.path(R.home(), "etc", "Makeconf")))
  cat("r-zig without the toolchain OK\n")
'
echo "== wheel test passed ($(basename "$wheel"), $(basename "$tc_wheel"))"
