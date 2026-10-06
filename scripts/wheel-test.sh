#!/usr/bin/env bash
# Install the r-zig wheels the way a pip user would and use them with the
# pixi env out of the picture: fresh venv, PATH scrubbed to the venv +
# /usr/bin:/bin, no CONDA_PREFIX. Checks, in order:
#   - r-zig alone (no ziglang, no make): the R/Rscript console scripts and
#     `python -m r_zig` run R, the minimal capability profile, TLS, and
#     R CMD INSTALL of a package with compiled code stops with the compile
#     preflight naming r-zig-toolchain (phase T of feat-no-host-paths)
#   - then r-zig-toolchain (which brings ziglang and GNU make):
#   - zig-fc (FC) is shipped, and with no flang it stops with exit 127 and
#     a message naming flang's remedy, not the toolchain hint (the toolchain
#     is installed by then), feat-no-host-paths F3c
#   - R CMD INSTALL of a small package with C and C++ sources that calls
#     BLAS through CRAN's usual `$(BLAS_LIBS) $(FLIBS)` — compiled by the
#     PyPI ziglang package and built by the bundled GNU make, three times:
#     through the console script (ZIG_BIN from `import ziglang`) and
#     through the bundled bin/R directly with ZIG_BIN unset (the path an
#     embedder such as rpy2 takes: Renviron.site finds ziglang next door),
#     and once more with ZIG_BIN pointing nowhere (python3 -m ziglang)
#   - the compilers (rzig) ignore CONDA_PREFIX, and honour R_ZIG_EXTRA_ENV
#     (an env's header, -L and rpath), feat-no-host-paths F3b
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
# the trust anchors itself (build.zig's installEnvRuntime,
# zigbuild/patches/). Same
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

echo "== zig-fc: shipped, and with no flang it stops naming flang"
# FC is the toolchain's zig-fc (feat-no-host-paths F3c), shipped like
# zig-cc. Neither wheel brings a Fortran compiler, so here a Fortran
# compile stops at once: exit 127, with a message naming LLVM flang as the
# remedy. Not R_ZIG_TOOLCHAIN_HINT (etc/Renviron, which R CMD applies):
# its "pip install r-zig-toolchain" is already done once zig-fc exists.
# C packages build as before.
tc="$r_home/bin/toolchain"
cmp -s "$tc/zig-fc" "$tc/zig-cc" || { echo "error: $tc/zig-fc is missing or not the same rzig as zig-cc" >&2; exit 1; }
if [ -x /usr/bin/flang ] || [ -x /bin/flang ]; then
  echo "note: this machine has a flang in /usr/bin; zig-fc's no-flang message not exercised"
else
  printf '      end\n' > "$T/nofc.f"
  rc=0
  (cd "$T" && run "$r_home/bin/R" CMD toolchain/zig-fc -c nofc.f -o nofc.o) > "$T/nofc.log" 2>&1 || rc=$?
  if [ "$rc" != 127 ] || ! grep '^zig-fc: no flang on PATH' "$T/nofc.log" | grep -qF "install LLVM flang" ||
    grep -qF "pip install r-zig-toolchain" "$T/nofc.log"; then
    cat "$T/nofc.log" >&2; echo "error: zig-fc with no flang: exit $rc, or no message naming LLVM flang (or one still naming the installed toolchain)" >&2; exit 1
  fi
  echo "ok: exit 127: $(cat "$T/nofc.log")"
fi

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

echo "== CONDA_PREFIX ignored by the compilers (rzig, feat-no-host-paths F3b)"
# An activated env R is not installed in adds nothing: with a poisoned
# conda env as CONDA_PREFIX (#error in zlib.h and omp.h, junk libraries),
# rzig's command lines name only r_zig/R, and the package built that way
# records no rpath.
decoy="$T/decoy"
mkdir -p "$decoy/conda-meta" "$decoy/include" "$decoy/lib"
printf '#error decoy CONDA_PREFIX\n' > "$decoy/include/zlib.h"; cp "$decoy/include/zlib.h" "$decoy/include/omp.h"
printf 'junk' > "$decoy/lib/libz.so"; cp "$decoy/lib/libz.so" "$decoy/lib/libomp.so"
own="$(cd "$r_home/../.." && pwd -P)"
argv="$(run CONDA_PREFIX="$decoy" RZIG_PRINT_ARGV=1 "$r_home/bin/toolchain/zig-cc" -shared -fopenmp -o x.so x.o -lz)"
if printf '%s\n' "$argv" | grep -F "$decoy" || ! printf '%s\n' "$argv" | grep -qxF -- "-L$own/lib" || printf '%s\n' "$argv" | grep -q -- -rpath; then
  printf '%s\n' "$argv" >&2; echo "error: rzig's link line: CONDA_PREFIX named, -L$own/lib missing, or an rpath" >&2; exit 1
fi
mkdir -p "$T/lib4"
run CONDA_PREFIX="$decoy" R CMD INSTALL --preclean -l "$T/lib4" "$P" > "$T/decoy.log" 2>&1 || { cat "$T/decoy.log" >&2; exit 1; }
rpath_of() {
  if command -v readelf > /dev/null 2>&1; then readelf -d "$1" | sed -n 's/.*(R\(UN\)\{0,1\}PATH).*\[\(.*\)\]/\2/p'
  elif command -v otool > /dev/null 2>&1; then otool -l "$1" | awk '/cmd LC_RPATH/ {r = 1} r && / path / {print $2; r = 0}'
  fi
}
rp="$(rpath_of "$T/lib4/rzigwheeltest/libs/rzigwheeltest.so")"
[ -z "$rp" ] || { echo "error: a package built with CONDA_PREFIX set records an rpath: $rp" >&2; exit 1; }
echo "ok: rzig names only $own; no rpath"

# R_ZIG_EXTRA_ENV: a standalone R compiling against an env of libraries.
# A package using an env header and library builds, links through the env's
# -L and loads through its rpath (the env is a conda env). The env R was
# built in (it has zlib's header), when there is one.
xenv=""
for e in "$ROOT/.pixi/envs/minimal" "$ROOT/.pixi/envs/default"; do
  [ -f "$e/include/zlib.h" ] && [ -d "$e/conda-meta" ] && { xenv="$(cd "$e" && pwd -P)"; break; }
done
if [ -n "$xenv" ]; then
  Z="$T/src/rzigwheelz"
  mkdir -p "$Z/R" "$Z/src" "$T/lib5"
  printf 'Package: rzigwheelz\nVersion: 0.1\nTitle: Test\nDescription: Test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$Z/DESCRIPTION"
  printf 'useDynLib(rzigwheelz)\nexport(zv)\n' > "$Z/NAMESPACE"
  echo 'zv <- function() .Call("rzigwheelz_zv")' > "$Z/R/f.R"
  printf '#include <zlib.h>\n#include <Rinternals.h>\nSEXP rzigwheelz_zv(void) { return Rf_mkString(zlibVersion()); }\n' > "$Z/src/z.c"
  echo 'PKG_LIBS = -lz' > "$Z/src/Makevars"
  run R_ZIG_EXTRA_ENV="$xenv" CONDA_PREFIX="$decoy" R CMD INSTALL -l "$T/lib5" "$Z" > "$T/xenv.log" 2>&1 || { cat "$T/xenv.log" >&2; exit 1; }
  rp="$(rpath_of "$T/lib5/rzigwheelz/libs/rzigwheelz.so")"
  [ "$rp" = "$xenv/lib" ] || { echo "error: rzigwheelz.so's rpath is '$rp', not $xenv/lib" >&2; exit 1; }
  run Rscript -e "library(rzigwheelz, lib.loc = '$T/lib5'); cat('zlib', zv(), '\n')"
  echo "ok: R_ZIG_EXTRA_ENV=$xenv: header, -L and rpath from it"
else
  echo "note: no pixi env with zlib.h next to this checkout; R_ZIG_EXTRA_ENV not exercised"
fi

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
