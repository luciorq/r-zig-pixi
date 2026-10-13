#!/usr/bin/env bash
# Install the r-zig wheels the way a pip user would and use them with the
# pixi env out of the picture: fresh venv, PATH scrubbed to the venv +
# /usr/bin:/bin, no CONDA_PREFIX. Checks, in order:
#   - r-zig alone (no ziglang, no make): the R/Rscript console scripts and
#     `python -m r_zig` run R, the minimal capability profile, TLS, and
#     R CMD INSTALL of a package with compiled code stops with the compile
#     preflight naming r-zig-toolchain (phase T of feat-no-host-paths)
#   - then r-zig-toolchain (which brings ziglang and GNU make):
#   - make is the toolchain's R_HOME/bin/toolchain/usr/bin/make, which
#     etc/Renviron puts first on PATH, and MAKE is plain `make`
#     (feat-standalone-toolchain B23, B25)
#   - zig-fc (FC) is shipped, and with no flang it stops with exit 127 and
#     the compilers group's text, which says pip brings no Fortran, not the
#     toolchain hint (the toolchain is installed by then), feat-no-host-paths
#     F3c and feat-standalone-toolchain B35
#   - R CMD INSTALL of a small package with C and C++ sources that calls
#     BLAS through CRAN's usual `$(BLAS_LIBS) $(FLIBS)` — compiled by the
#     PyPI ziglang package, three times: through the console script
#     (ZIG_BIN from `import ziglang`; RZIG_TRACE=1, and the log must say
#     `rzig build: tier 1`: R CMD INSTALL builds this shape through
#     `rzig build`, feat-zig-pkg-build's patch 0013, here for the first
#     time under PyPI's ziglang), through the bundled bin/R directly with
#     ZIG_BIN unset (the path an embedder such as rpy2 takes:
#     Renviron.site finds ziglang next door) and R_ZIG_PKG_BUILDER=make,
#     so the bundled GNU make builds it once, and once more with ZIG_BIN
#     pointing nowhere (python3 -m ziglang); then a package whose Makevars
#     has a rule (a static library through $(AR)), which needs make, built
#     by the bundled make
#   - the compilers (rzig) ignore CONDA_PREFIX, and honour R_ZIG_EXTRA_ENV
#     (an env's header, -L and rpath), feat-no-host-paths F3b
#   - uninstalling r-zig-toolchain removes only R_HOME/bin/toolchain's files
# pip fetches ziglang (~100 MB) from PyPI, so this needs network; point
# PIP_FIND_LINKS at a directory holding the ziglang wheel to avoid that.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

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
# 0009's stop for a package that needs the toolchain [tests-T11], with its
# hint (R_ZIG_TOOLCHAIN_HINT)
grep -F "needs the r-zig toolchain (compiled code or a configure script), which is not installed: " "$T/preflight.out" | grep -F "pip install r-zig-toolchain" ||
  { cat "$T/preflight.out" >&2; echo "error: no preflight message naming r-zig-toolchain" >&2; exit 1; }

echo "== installing $(basename "$tc_wheel") (+ ziglang from PyPI)"
pip_ install --quiet "$tc_wheel"
pip_ list 2>/dev/null | grep -iE '^(r-zig|r-zig-toolchain|ziglang) '
# GNU make is the build-tools group's usr/bin/make, found on PATH: R reads
# etc/Renviron's PATH line, which puts R_HOME/bin/toolchain/usr/bin first
# (ahead of a host make, such as Apple's 3.81 in /usr/bin), and MAKE stays
# `make` (feat-standalone-toolchain B23, B25).
run Rscript -e '
  mk <- Sys.which("make")
  stopifnot(nzchar(mk), file.exists(mk), grepl("bin/toolchain/usr/bin/make$", mk),
            identical(Sys.getenv("MAKE"), "make"))
  cat("make =", mk, "\n")
'

echo "== zig-fc: shipped, and with no flang it stops naming flang"
# FC is the toolchain's zig-fc (feat-no-host-paths F3c), shipped like
# zig-cc. Neither wheel brings a Fortran compiler, so here a Fortran
# compile stops at once: exit 127, with rzig's text for the compilers group
# (feat-standalone-toolchain B35, the same on every channel): its pip line
# says the wheels bring no Fortran, its standalone line names LLVM flang on
# PATH. Not R_ZIG_TOOLCHAIN_HINT (etc/Renviron, which R CMD applies; rzig
# does not read it): its "pip install r-zig-toolchain (same Python
# environment as r-zig)" is already done once zig-fc exists. C packages
# build as before.
tc="$r_home/bin/toolchain"
cmp -s "$tc/zig-fc" "$tc/zig-cc" || { echo "error: $tc/zig-fc is missing or not the same rzig as zig-cc" >&2; exit 1; }
if [ -x /usr/bin/flang ] || [ -x /bin/flang ]; then
  echo "note: this machine has a flang in /usr/bin; zig-fc's no-flang message not exercised"
else
  printf '      end\n' > "$T/nofc.f"
  rc=0
  (cd "$T" && run "$r_home/bin/R" CMD toolchain/zig-fc -c nofc.f -o nofc.o) > "$T/nofc.log" 2>&1 || rc=$?
  if [ "$rc" != 127 ] || ! grep -q '^zig-fc: no flang (' "$T/nofc.log" ||
    ! grep -qF "LLVM flang on PATH" "$T/nofc.log" || ! grep -qF "pip install r-zig-toolchain (no Fortran)" "$T/nofc.log" ||
    grep -qF "same Python environment as r-zig" "$T/nofc.log"; then
    cat "$T/nofc.log" >&2; echo "error: zig-fc with no flang: exit $rc, or not the compilers group's text (LLVM flang on PATH; pip: no Fortran), or the toolchain hint" >&2; exit 1
  fi
  echo "ok: exit 127: $(cat "$T/nofc.log")"
fi

echo "== R CMD INSTALL via the console script (ZIG_BIN from import ziglang): rzig build"
run RZIG_TRACE=1 R CMD INSTALL --preclean -l "$T/lib1" "$P" > "$T/install1.log" 2>&1 || { cat "$T/install1.log" >&2; exit 1; }
grep -q 'rzig build: tier 1' "$T/install1.log" || { cat "$T/install1.log" >&2; echo "error: the console-script install did not build through rzig build (no 'rzig build: tier 1' in its log)" >&2; exit 1; }
# rzig's commands (the two compiles and the link), not its self and
# environment lines [tests-T10]
echo "ok: rzig build: tier 1 ($(grep -E '^zig-(cc|cxx|fc): ' "$T/install1.log" | grep -c -v -E '^zig-(cc|cxx|fc): (self|environment) ') rzig commands under PyPI ziglang)"
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

echo "== R CMD INSTALL via bundled bin/R, ZIG_BIN unset (Renviron.site -> sibling ziglang), through the bundled make (R_ZIG_PKG_BUILDER=make)"
run R_ZIG_PKG_BUILDER=make RZIG_TRACE=1 "$r_home/bin/R" CMD INSTALL --preclean -l "$T/lib2" "$P" > "$T/install2.log" 2>&1 || { cat "$T/install2.log" >&2; exit 1; }
if grep -q 'rzig build:' "$T/install2.log"; then cat "$T/install2.log" >&2; echo "error: R_ZIG_PKG_BUILDER=make still ran rzig build" >&2; exit 1; fi
# make's echoed compiles: the toolchain's compilers by their path, which
# rzig's own trace lines (`zig-cc: self <path>`) do not start with [tests-T6]
[ -n "$(make_recipes "$T/install2.log")" ] || { cat "$T/install2.log" >&2; echo "error: no compile make echoed in the make path's log" >&2; exit 1; }
echo "ok: the make path built it"
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
echo "== a package that needs make (a Makevars rule: a static library through \$(AR)), built by the bundled make"
A="$T/src/rzigwheelar"
mkdir -p "$A/R" "$A/src/foo" "$T/lib6"
printf 'Package: rzigwheelar\nVersion: 0.1\nTitle: Test\nDescription: Test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$A/DESCRIPTION"
printf 'useDynLib(rzigwheelar)\nexport(f)\n' > "$A/NAMESPACE"
echo 'f <- function() .Call("rzigwheelar_f")' > "$A/R/f.R"
printf '#include <Rinternals.h>\nint rzigwheelar_foo(void);\nSEXP rzigwheelar_f(void) { return ScalarInteger(rzigwheelar_foo()); }\n' > "$A/src/f.c"
echo 'int rzigwheelar_foo(void) { return 42; }' > "$A/src/foo/foo.c"
printf 'PKG_LIBS = foo/libfoo.a\n$(SHLIB): foo/libfoo.a\nfoo/libfoo.a: foo/foo.o\n\t$(AR) cr $@ foo/foo.o\n\t$(RANLIB) $@\n' > "$A/src/Makevars"
run RZIG_TRACE=1 R CMD INSTALL -l "$T/lib6" "$A" > "$T/install6.log" 2>&1 || { cat "$T/install6.log" >&2; exit 1; }
grep -q 'rzig build: rzigwheelar needs make: src/Makevars has a rule or target line' "$T/install6.log" || { cat "$T/install6.log" >&2; echo "error: the Makevars-rule package did not go to make with rzig build's reason" >&2; exit 1; }
run Rscript -e "library(rzigwheelar, lib.loc = '$T/lib6'); stopifnot(f() == 42L); cat('needs-make package built by the wheel\'s make OK\n')"

echo "== uninstalling r-zig-toolchain leaves r-zig whole"
pip_ uninstall --quiet -y r-zig-toolchain
# No file of it is left under R_HOME/bin/toolchain, rzig's or usr/'s; pip
# may leave the empty directories (C32).
left="$(find "$r_home/bin/toolchain" ! -type d 2>/dev/null || true)"
[ -z "$left" ] || { printf '%s\n' "$left" >&2; echo "error: files left under R_HOME/bin/toolchain after uninstalling r-zig-toolchain" >&2; exit 1; }
run Rscript -e '
  stopifnot(!file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
  stopifnot(file.exists(file.path(R.home(), "etc", "Makeconf")))
  cat("r-zig without the toolchain OK\n")
'
echo "== wheel test passed ($(basename "$wheel"), $(basename "$tc_wheel"))"
