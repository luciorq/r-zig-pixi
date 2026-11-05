#!/usr/bin/env bash
# Install the r-zig wheels the way a pip user would and use them with the
# pixi env out of the picture: fresh venv, no CONDA_PREFIX, and PATH
# scrubbed to the venv + /usr/bin:/bin (`run`), or to the venv alone
# (`run_venv`) where a host make or zig would stand in for a group the
# venv does not have (R itself needs no more: hermetic-check.sh). Four
# wheels, the base and a package per toolchain group, added one at a time
# (feat-standalone-toolchain B29 a; phase 4):
#   - r-zig alone (no ziglang, no make): the R/Rscript console scripts and
#     `python -m r_zig` run R, the minimal capability profile, rzig in
#     R_HOME/bin/toolchain with no group's files (B19), TLS; then
#     recipe/test-preflight.R, r-zig-slim's own test, with this R (PHASE4
#     Cg10): an R-only package installs, and a compiled one stops in the
#     preflight with `zig-cc: no zig (` and the compilers group's text,
#     whose pip line names r-zig-compilers, and R CMD SHLIB stops with that
#     text too, and of a Makevars rule with both groups' texts
#     (feat-shlib-rzig-build). It narrows PATH to R's bin itself, so no
#     host zig, and no python3 with ziglang, is reachable
#   - + r-zig-compilers (which brings ziglang, and no make): zig-fc with no
#     flang stops with exit 127 and the compilers group's text, whose pip
#     line says PyPI has no Fortran compiler (B35; PHASE4 Cg3); R CMD
#     INSTALL of a small package with C and C++ sources that calls BLAS
#     through CRAN's usual `$(BLAS_LIBS) $(FLIBS)`, compiled by the PyPI
#     ziglang package through `rzig build` (feat-zig-pkg-build's patch
#     0013; RZIG_TRACE=1, and the log must say `rzig build: tier 1`),
#     through the console script (ZIG_BIN from `import ziglang`) with no
#     make on PATH, and with ZIG_BIN pointing nowhere (python3 -m
#     ziglang); its C++ runtime is static; the compilers (rzig) ignore
#     CONDA_PREFIX and honour R_ZIG_EXTRA_ENV (an env's header, -L and
#     rpath), feat-no-host-paths F3b; a package whose Makevars has a rule
#     (a static library through $(AR)) needs make, and stops in the
#     preflight naming r-zig-build-tools; R CMD SHLIB with no make
#     (feat-shlib-rzig-build, patch 0013's one hook): pkgbuild's probe
#     shape and a C++ file build through rzig build and load (no shared
#     C++ runtime), and a Makevars rule stops with rzig's reason, "no make
#     on PATH" and the build tools' pip line, building nothing
#   - + r-zig-build-tools: make is its R_HOME/bin/toolchain/usr/bin/make,
#     which etc/Renviron puts first on PATH, and MAKE is plain `make`
#     (B23, B25); the Makevars-rule package builds with it, the
#     Makevars-rule R CMD SHLIB too (rzig build's reason, then make's
#     echoed compile), and so does
#     the C/C++ package through the bundled bin/R with ZIG_BIN unset (the
#     path an embedder such as rpy2 takes: Renviron.site finds ziglang
#     next door) and R_ZIG_PKG_BUILDER=make
#   - + r-zig-toolchain: it resolves from the installed groups, and it and
#     r-zig-compilers hold no file outside their .dist-info; in a second
#     venv, r-zig-toolchain from dist/wheel with no index brings the other
#     three, and that R's make is its own (PHASE4 Cc5)
#   - uninstalling the three groups leaves r-zig whole: rzig's names and
#     nothing else under R_HOME/bin/toolchain, and a C package still
#     builds, since ziglang stays; with ziglang uninstalled too,
#     recipe/test-preflight.R again (PHASE4 Cc6)
# None of the four names is on PyPI (PHASE4 Cc14): the group wheels are
# installed by file, and pip asks no index for the r-zig they require,
# which is installed by then; the second venv uses --no-index. pip
# fetches ziglang (~100 MB) from PyPI, so this needs network; point
# PIP_FIND_LINKS at a directory holding the ziglang wheel to avoid that.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

# one wheel of each name for this R (make-wheel.py), r-zig's first
shopt -s nullglob
wheels=()
for n in r_zig r_zig_compilers r_zig_build_tools r_zig_toolchain; do
  w=("$ROOT"/dist/wheel/"$n"-"$R_VERSION"-*.whl)
  [ "${#w[@]}" = 1 ] || { echo "error: expected exactly one $n-$R_VERSION wheel in dist/wheel, found ${#w[@]} — run 'pixi run -e wheel wheel'" >&2; exit 1; }
  wheels+=("${w[0]}")
done
wheel="${wheels[0]}" cc_wheel="${wheels[1]}" bt_wheel="${wheels[2]}" tc_wheel="${wheels[3]}"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
echo "== installing $(basename "$wheel") alone into a fresh venv"
python -m venv "$T/venv"
pip_() { "$T/venv/bin/python" -m pip --disable-pip-version-check "$@"; }
listed() { pip_ list 2>/dev/null | grep -iE '^(r-zig[a-z-]*|ziglang) ' || true; }
pip_ install --quiet "$wheel"
listed
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

mkdir -p "$T/home" "$T/lib1" "$T/lib2" "$T/lib3" "$T/lib6" "$T/lib7"
run_with() {
  local path="$1"; shift
  env -i HOME="$T/home" PATH="$path" TMPDIR="${TMPDIR:-/tmp}" LANG=C.UTF-8 "$@"
}
run() { run_with "$T/venv/bin:/usr/bin:/bin" "$@"; }
run_venv() { run_with "$T/venv/bin" "$@"; }

echo "== console scripts"
run R --version | head -1
run python -m r_zig --version | head -1
run python -c 'import r_zig; print("r_home:", r_zig.r_home()); print("zig_bin:", r_zig.zig_bin())'
r_home="$(run python -c 'import r_zig; print(r_zig.r_home())')"
tc="$r_home/bin/toolchain"

echo "== capability profile, and rzig in the base (inside the installed wheel)"
run Rscript -e '
  caps <- capabilities()
  stopifnot(!caps[["cairo"]], !caps[["png"]], !caps[["ICU"]], caps[["libcurl"]], caps[["iconv"]])
  stopifnot(grepl("/r_zig/R/lib/R$", R.home()))
  tc <- file.path(R.home(), "bin", "toolchain")
  stopifnot(file.exists(file.path(tc, c("zig-cc", "rzig"))), !dir.exists(file.path(tc, "usr")))
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

echo "== r-zig alone: r-zig-slim's own test (recipe/test-preflight.R)"
run Rscript "$ROOT/recipe/test-preflight.R"

echo "== + $(basename "$cc_wheel") (+ ziglang from PyPI)"
pip_ install --quiet "$cc_wheel"
listed
pip_ show ziglang > /dev/null 2>&1 || { echo "error: r-zig-compilers did not bring ziglang" >&2; exit 1; }
[ ! -e "$tc/usr" ] || { echo "error: r-zig-compilers brought $tc/usr" >&2; exit 1; }

echo "== zig-fc: the base's, and with no flang it stops naming flang"
# FC is zig-fc (feat-no-host-paths F3c), rzig like zig-cc. No wheel brings
# a Fortran compiler, so a Fortran compile stops at once: exit 127, with
# rzig's text for the compilers group (feat-standalone-toolchain B35, the
# same on every channel): its pip line says PyPI has no Fortran compiler
# (PHASE4 Cg3; B29 a: pip still has none), and its standalone line names
# the compilers archive, which holds flang since phase 6 ("flang and the
# OpenMP files"). With the venv's bin alone on PATH no host flang is
# reachable. C packages build as before.
cmp -s "$tc/zig-fc" "$tc/zig-cc" || { echo "error: $tc/zig-fc is missing or not the same rzig as zig-cc" >&2; exit 1; }
printf '      end\n' > "$T/nofc.f"
rc=0
(cd "$T" && run_venv "$r_home/bin/R" CMD toolchain/zig-fc -c nofc.f -o nofc.o) > "$T/nofc.log" 2>&1 || rc=$?
if [ "$rc" != 127 ] || ! grep -q '^zig-fc: no flang (' "$T/nofc.log" || ! grep -qF "flang and the OpenMP files" "$T/nofc.log" ||
  ! grep -qF "pip install r-zig-compilers (zig only: PyPI has no Fortran compiler)" "$T/nofc.log"; then
  cat "$T/nofc.log" >&2; echo "error: zig-fc with no flang: exit $rc, or not the compilers group's text (flang and the OpenMP files; pip: no Fortran compiler)" >&2; exit 1
fi
echo "ok: exit 127: $(head -1 "$T/nofc.log")"

echo "== R CMD INSTALL via the console script (ZIG_BIN from import ziglang), no make on PATH: rzig build"
run_venv RZIG_TRACE=1 R CMD INSTALL --preclean -l "$T/lib1" "$P" > "$T/install1.log" 2>&1 || { cat "$T/install1.log" >&2; exit 1; }
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

echo "== R CMD INSTALL with ZIG_BIN pointing nowhere and no zig on PATH (python3 -m ziglang): rzig build"
run_venv ZIG_BIN=/nonexistent/zig RZIG_TRACE=1 "$r_home/bin/R" CMD INSTALL --preclean -l "$T/lib3" "$P" > "$T/install3.log" 2>&1 || { cat "$T/install3.log" >&2; exit 1; }
grep -q 'rzig build: tier 1' "$T/install3.log" || { cat "$T/install3.log" >&2; echo "error: the python3 -m ziglang install did not build through rzig build (no 'rzig build: tier 1' in its log)" >&2; exit 1; }
run "$r_home/bin/Rscript" -e "
  library(rzigwheeltest, lib.loc = '$T/lib3')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('compiled package OK (python3 -m ziglang fallback)\n')
"

echo "== a package that needs make (a Makevars rule: a static library through \$(AR)), with no build tools: the preflight stops"
A="$T/src/rzigwheelar"
mkdir -p "$A/R" "$A/src/foo" "$T/lib6"
printf 'Package: rzigwheelar\nVersion: 0.1\nTitle: Test\nDescription: Test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' > "$A/DESCRIPTION"
printf 'useDynLib(rzigwheelar)\nexport(f)\n' > "$A/NAMESPACE"
echo 'f <- function() .Call("rzigwheelar_f")' > "$A/R/f.R"
printf '#include <Rinternals.h>\nint rzigwheelar_foo(void);\nSEXP rzigwheelar_f(void) { return ScalarInteger(rzigwheelar_foo()); }\n' > "$A/src/f.c"
echo 'int rzigwheelar_foo(void) { return 42; }' > "$A/src/foo/foo.c"
printf 'PKG_LIBS = foo/libfoo.a\n$(SHLIB): foo/libfoo.a\nfoo/libfoo.a: foo/foo.o\n\t$(AR) cr $@ foo/foo.o\n\t$(RANLIB) $@\n' > "$A/src/Makevars"
if run_venv R CMD INSTALL -l "$T/lib6" "$A" > "$T/install6.log" 2>&1; then
  cat "$T/install6.log" >&2; echo "error: the Makevars-rule package installed with no make" >&2; exit 1
fi
# rzig's reason, the build-tools group's text with its pip line, and
# 0009's stop [tests-T11]; nothing installed
if ! grep -qF 'rzigwheelar needs make: src/Makevars has a rule or target line' "$T/install6.log" ||
  ! grep -qF '  pip:         pip install r-zig-build-tools' "$T/install6.log" ||
  ! grep -qF 'which is incomplete (see above)' "$T/install6.log" || [ -e "$T/lib6/rzigwheelar" ]; then
  cat "$T/install6.log" >&2; echo "error: the Makevars-rule package did not stop in the preflight naming r-zig-build-tools" >&2; exit 1
fi
echo "ok: stops naming r-zig-build-tools"

# R CMD SHLIB with no make (feat-shlib-rzig-build): R builds the call
# through rzig build (patch 0013's one hook), compiled by the PyPI
# ziglang: pkgbuild's probe (foo.c beside an invalid junk.c) and a C++
# file, which loads with no shared C++ runtime; a Makevars rule stops with
# rzig's reason, "no make on PATH" and the build tools' pip line, and
# builds nothing.
echo "== R CMD SHLIB with no make on PATH: rzig build"
S="$T/shlib"
mkdir -p "$S/probe" "$S/cx" "$S/rule"
printf 'void foo(int *bar) { *bar = 1; }\n' > "$S/probe/foo.c"
printf 'this is not C (\n' > "$S/probe/junk.c"
printf '%s\n' '#include <string>' '#include <R.h>' '#include <Rinternals.h>' \
  'extern "C" SEXP cx(void) { std::string s("r-zig"); return ScalarInteger((int) s.size()); }' > "$S/cx/cx.cpp"
(cd "$S/probe" && run_venv RZIG_TRACE=1 R CMD SHLIB foo.c) > "$S/probe.log" 2>&1 || { cat "$S/probe.log" >&2; echo "error: R CMD SHLIB foo.c failed with r-zig-compilers and no make" >&2; exit 1; }
(cd "$S/cx" && run_venv RZIG_TRACE=1 R CMD SHLIB -o cx.so cx.cpp) > "$S/cx.log" 2>&1 || { cat "$S/cx.log" >&2; echo "error: R CMD SHLIB -o cx.so cx.cpp failed with r-zig-compilers and no make" >&2; exit 1; }
for l in probe cx; do
  grep -q 'rzig build: R CMD SHLIB, tier 1' "$S/$l.log" || { cat "$S/$l.log" >&2; echo "error: R CMD SHLIB ($l) did not build through rzig build" >&2; exit 1; }
done
[ ! -e "$S/probe/foo.o" ] && [ ! -e "$S/cx/cx.o" ] || { echo "error: R CMD SHLIB through rzig build left an object beside its sources" >&2; exit 1; }
run Rscript -e "
  dyn.load('$S/probe/foo.so'); dyn.load('$S/cx/cx.so')
  stopifnot(.C('foo', 0L)[[1]] == 1L, .Call('cx') == 5L)
  cat('R CMD SHLIB libraries load\n')
"
if command -v readelf > /dev/null 2>&1; then cxx="$(readelf -d "$S/cx/cx.so" | grep -E 'NEEDED.*lib(c\+\+|stdc\+\+)' || true)"
else cxx="$(otool -L "$S/cx/cx.so" | tail -n +2 | grep -E 'lib(c\+\+|stdc\+\+)' || true)"; fi
[ -z "$cxx" ] || { echo "error: cx.so (R CMD SHLIB through rzig build) needs a shared C++ runtime: $cxx" >&2; exit 1; }
printf 'void x(int *n) { *n = 1; }\n' > "$S/rule/x.c"
printf '%s\n' 'all: $(SHLIB) extra' 'extra:' '	@echo extra' > "$S/rule/Makevars"
if (cd "$S/rule" && run_venv R CMD SHLIB x.c) > "$S/rule.log" 2>&1; then
  cat "$S/rule.log" >&2; echo "error: R CMD SHLIB of a Makevars rule succeeded with no make" >&2; exit 1
fi
if ! grep -qF 'x.so needs make: Makevars has a rule or target line' "$S/rule.log" || ! grep -qF 'no make on PATH' "$S/rule.log" ||
  ! grep -qF '  pip:         pip install r-zig-build-tools; r-zig-toolchain installs every group' "$S/rule.log" ||
  [ -e "$S/rule/x.so" ] || [ -e "$S/rule/x.o" ]; then
  cat "$S/rule.log" >&2; echo "error: R CMD SHLIB of a Makevars rule did not stop with rzig's reason and the build tools' pip line, or built something" >&2; exit 1
fi
echo "ok: foo.c and a C++ file build through rzig build and load (static C++ runtime); a Makevars rule stops naming r-zig-build-tools"

echo "== + $(basename "$bt_wheel")"
pip_ install --quiet "$bt_wheel"
listed
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

echo "== the Makevars-rule package, built by the wheel's make"
run RZIG_TRACE=1 R CMD INSTALL -l "$T/lib6" "$A" > "$T/install6.log" 2>&1 || { cat "$T/install6.log" >&2; exit 1; }
grep -q 'rzig build: rzigwheelar needs make: src/Makevars has a rule or target line' "$T/install6.log" || { cat "$T/install6.log" >&2; echo "error: the Makevars-rule package did not go to make with rzig build's reason" >&2; exit 1; }
run Rscript -e "library(rzigwheelar, lib.loc = '$T/lib6'); stopifnot(f() == 42L); cat('needs-make package built by the wheel\'s make OK\n')"

echo "== R CMD SHLIB of the Makevars rule, built by the wheel's make"
# rzig build declines it (exit 3, its reason in the trace), and R runs
# make, which echoes its compile
(cd "$S/rule" && run RZIG_TRACE=1 R CMD SHLIB x.c) > "$S/rule-make.log" 2>&1 || { cat "$S/rule-make.log" >&2; exit 1; }
grep -q 'rzig build: x.so needs make: Makevars has a rule or target line' "$S/rule-make.log" &&
  [ -n "$(make_recipes "$S/rule-make.log")" ] && [ -f "$S/rule/x.so" ] ||
  { cat "$S/rule-make.log" >&2; echo "error: R CMD SHLIB of the Makevars rule did not go to the wheel's make with rzig build's reason" >&2; exit 1; }
echo "ok: rzig build's reason, then make built it"

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

echo "== + $(basename "$tc_wheel"): resolves from the installed groups"
pip_ install --quiet "$tc_wheel"
listed
# The two wheels of requirements alone hold no file outside their
# .dist-info. pip lists that directory's own files (METADATA, RECORD,
# INSTALLER, ...) under Files:, so "no file" cannot be the test (PHASE4
# Cc6).
for d in r-zig-compilers r-zig-toolchain; do
  di="$(printf '%s' "$d" | tr - _)-$R_VERSION.dist-info/"
  files="$(pip_ show -f "$d" | sed -n '/^Files:/,$p' | sed -e 1d -e 's/^ *//')"
  other="$(printf '%s\n' "$files" | awk -v p="$di" 'index($0, p) != 1')"
  if ! printf '%s\n' "$files" | grep -qxF "${di}METADATA" || [ -n "$other" ]; then
    printf '%s\n' "$files" >&2; echo "error: $d's files are not its $di alone" >&2; exit 1
  fi
done
echo "ok: r-zig-compilers and r-zig-toolchain hold their .dist-info alone"

echo "== a second venv: r-zig-toolchain from dist/wheel, no index, brings the other three"
python -m venv "$T/venv2"
pip2_() { "$T/venv2/bin/python" -m pip --disable-pip-version-check "$@"; }
# ziglang first (PyPI or PIP_FIND_LINKS: the version the first venv
# solved); then no index at all, so no name can come from PyPI, where
# none of the four is registered (PHASE4 Cc14)
pip2_ install --quiet "ziglang==$(pip_ show ziglang | sed -n 's/^Version: //p')"
pip2_ install --quiet --no-index --find-links "$ROOT/dist/wheel" "r-zig-toolchain==$R_VERSION"
for n in r-zig r-zig-compilers r-zig-build-tools r-zig-toolchain ziglang; do
  pip2_ show "$n" > /dev/null 2>&1 || { echo "error: the second venv has no $n" >&2; exit 1; }
done
# its R's make is its own usr/bin/make, not a host make (PHASE4 Cc5)
run_with "$T/venv2/bin:/usr/bin:/bin" Rscript -e '
  mk <- Sys.which("make")
  stopifnot(nzchar(mk), identical(normalizePath(mk), normalizePath(file.path(R.home("bin"), "toolchain", "usr", "bin", "make"))))
  cat("second venv: make =", mk, "\n")
'

echo "== uninstalling the three group wheels leaves r-zig whole"
pip_ uninstall --quiet -y r-zig-toolchain r-zig-build-tools r-zig-compilers
# R_HOME/bin/toolchain keeps the base's files, rzig under each of its
# names (verify-helpers.sh), and nothing under usr/; pip may leave the
# empty directories (C32).
left="$(cd "$tc" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')"
want="$(printf '%s\n' $(rzig_names) | LC_ALL=C sort | tr '\n' ' ')"
[ "$left" = "$want" ] || { echo "error: R_HOME/bin/toolchain after uninstalling the groups holds '$left', not rzig's names '$want'" >&2; exit 1; }
# ziglang stays (pip removes no dependency), and Renviron.site's ZIG_BIN
# finds it next door: a package that needs no make still compiles
run_venv RZIG_TRACE=1 "$r_home/bin/R" CMD INSTALL -l "$T/lib7" "$P" > "$T/install7.log" 2>&1 || { cat "$T/install7.log" >&2; exit 1; }
grep -q 'rzig build: tier 1' "$T/install7.log" || { cat "$T/install7.log" >&2; echo "error: with the groups uninstalled, the C/C++ package did not build through rzig build" >&2; exit 1; }
run Rscript -e "
  stopifnot(file.exists(file.path(R.home('etc'), 'Makeconf')))
  library(rzigwheeltest, lib.loc = '$T/lib7')
  stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
  cat('r-zig without the groups OK; ziglang still compiles\n')
"

echo "== and with ziglang uninstalled too: r-zig alone again (recipe/test-preflight.R)"
pip_ uninstall --quiet -y ziglang
run Rscript "$ROOT/recipe/test-preflight.R"
echo "== wheel test passed ($(basename "$wheel"), $(basename "$cc_wheel"), $(basename "$bt_wheel"), $(basename "$tc_wheel"))"
