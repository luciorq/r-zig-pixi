#!/usr/bin/env python3
"""The Windows half of the wheel test (scripts/wheel-test.sh is unix's).

Installs the four r-zig wheels for win-64 or win-arm64 (make-wheel.py,
b13-env-ci L2) the way a pip user would, into fresh venvs, and uses them
with the pixi env out of the picture: every R command runs with a
reduced environment (SYSTEMROOT, WINDIR, the temp, home and
LOCALAPPDATA dirs) and
PATH = the venv's Scripts plus System32 and Windows, so no host or env
make, sh or zig is reachable. The scenarios follow wheel-test.sh's, one
wheel at a time:
  - r-zig alone (no ziglang): the R/Rscript console scripts and
    `python -m r_zig` run R; R_HOME is r_zig/R/lib/R; the minimal
    profile (no ICU; libcurl, iconv); rzig under its Windows names in
    R_HOME/bin/toolchain, no usr/; an HTTPS request through R's libcurl
    (a certificate error fails, an offline host skips); then recipe/test-preflight.R,
    r-zig-slim's own test, with this R;
  - + r-zig-compilers (brings ziglang, no make): R CMD INSTALL of a C and
    C++ package that calls BLAS goes through `rzig build` (RZIG_TRACE=1:
    `rzig build: tier 1`), loads, and a C++ exception reaches R as an
    error; a package with a Makevars rule stops in the preflight naming
    r-zig-build-tools and installs nothing;
  - + r-zig-build-tools: make is R_HOME/bin/toolchain/usr/bin/make.exe
    (Rcmd_environ's PATH); the Makevars-rule package builds with it, and
    the C/C++ package through R_HOME/bin/R.exe with ZIG_BIN unset
    (Renviron.site finds ziglang next door) and R_ZIG_PKG_BUILDER=make;
  - + r-zig-toolchain: r-zig-compilers and r-zig-toolchain hold their
    .dist-info alone; a second venv gets all four from dist/wheel with
    no index (ziglang first, from PyPI);
  - uninstalling the three groups leaves R_HOME/bin/toolchain with
    rzig's names and its link object alone, and the C package still
    builds (ziglang stays); with ziglang uninstalled too,
    recipe/test-preflight.R again.
pip fetches ziglang from PyPI, so this needs network (PIP_FIND_LINKS
works as for wheel-test.sh). Run as `pixi run -e wheel wheel-test` on
Windows.
"""

from __future__ import annotations

import glob
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap

ROOT = os.environ.get("PIXI_PROJECT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R_VERSION = os.environ.get("R_VERSION") or sys.exit("wheel-test-windows: R_VERSION not set: run through `pixi run -e wheel wheel-test`")
RZIG_NAMES = ["gcc.exe", "g++.exe", "zig-fc.exe", "zig-ar.exe", "zig-ranlib.exe", "gcc-ar.exe", "gcc-ranlib.exe",
              "ar.exe", "ranlib.exe", "nm.exe", "objdump.exe", "strip.exe", "dlltool.exe", "windres.exe", "as.exe",
              "rzig.exe"]


def die(msg: str, log: str | None = None) -> None:
    if log:
        sys.stderr.write(log + "\n")
    sys.exit(f"error: {msg}")


def step(msg: str) -> None:
    print(f"== {msg}", flush=True)


def wheel_of(name: str) -> str:
    found = glob.glob(os.path.join(ROOT, "dist", "wheel", f"{name}-{R_VERSION}-*-win_*.whl"))
    if len(found) != 1:
        die(f"expected exactly one {name}-{R_VERSION} Windows wheel in dist/wheel, found {len(found)}: run `pixi run -e wheel wheel`")
    return found[0]


T = tempfile.mkdtemp(prefix="wheel-test-")
HOME = os.path.join(T, "home")
TMP = os.path.join(T, "tmp")
LOCALAPPDATA = os.path.join(HOME, "AppData", "Local")
for d in (HOME, TMP, LOCALAPPDATA):
    os.makedirs(d)
SYSROOT = os.environ.get("SYSTEMROOT", r"C:\Windows")


def venv_scripts(venv: str) -> str:
    return os.path.join(venv, "Scripts")


def base_env(venv: str, **extra: str) -> dict[str, str]:
    """The reduced environment: no CONDA_PREFIX, no pixi PATH."""
    env = {
        # LOCALAPPDATA: zig's global cache directory (every Windows user
        # has one; hermetic-check.sh keeps it too)
        "SYSTEMROOT": SYSROOT, "WINDIR": SYSROOT, "USERPROFILE": HOME, "HOME": HOME, "LOCALAPPDATA": LOCALAPPDATA,
        "TEMP": TMP, "TMP": TMP, "TMPDIR": TMP, "LANG": "C.UTF-8",
        "PATH": os.pathsep.join([venv_scripts(venv), os.path.join(SYSROOT, "System32"), SYSROOT]),
    }
    env.update(extra)
    return env


def run(venv: str, args: list[str], ok: bool = True, cwd: str | None = None, **extra: str) -> tuple[int, str]:
    """args[0] is a console script of the venv or a path; output is
    returned (stdout and stderr together)."""
    exe = args[0]
    if not os.path.isabs(exe):
        cand = [os.path.join(venv_scripts(venv), exe + ext) for ext in (".exe", "")]
        exe = next((c for c in cand if os.path.isfile(c)), exe)
    p = subprocess.run([exe, *args[1:]], env=base_env(venv, **extra), cwd=cwd,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    if ok and p.returncode != 0:
        die(f"{' '.join(args)} exited {p.returncode}", p.stdout)
    return p.returncode, p.stdout


def rscript(venv: str, code: str, **extra: str) -> str:
    f = os.path.join(T, "snippet.R")
    with open(f, "w", encoding="utf-8") as fh:
        fh.write(textwrap.dedent(code))
    _, out = run(venv, ["Rscript", f], **extra)
    print(out.rstrip())
    return out


def pip(venv: str, *args: str) -> str:
    p = subprocess.run([os.path.join(venv_scripts(venv), "python.exe"), "-m", "pip", "--disable-pip-version-check", *args],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    if p.returncode != 0:
        die(f"pip {' '.join(args)} exited {p.returncode}", p.stdout)
    return p.stdout


def installed(venv: str, name: str) -> bool:
    return subprocess.run([os.path.join(venv_scripts(venv), "python.exe"), "-m", "pip", "show", name],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def rpath(p: str) -> str:
    """A path as R reads it in a string literal."""
    return p.replace("\\", "/")


def main() -> None:
    wheel, cc_wheel, bt_wheel, tc_wheel = (wheel_of(n) for n in ("r_zig", "r_zig_compilers", "r_zig_build_tools", "r_zig_toolchain"))
    venv = os.path.join(T, "venv")
    step(f"installing {os.path.basename(wheel)} alone into a fresh venv")
    subprocess.run([sys.executable, "-m", "venv", venv], check=True)
    pip(venv, "install", "--quiet", wheel)
    if installed(venv, "ziglang"):
        die("r-zig alone pulled in ziglang")

    # the test packages (wheel-test.sh's): C + C++ with BLAS; a Makevars
    # rule (a static library through $(AR)); C alone
    P = os.path.join(T, "src", "rzigwheeltest")
    write(os.path.join(P, "DESCRIPTION"), "Package: rzigwheeltest\nVersion: 0.1\nTitle: r-zig Wheel Contract Test\n"
          "Description: Compiled-code smoke test for the r-zig wheel.\nLicense: GPL-2\n"
          'Authors@R: person("r-zig-pixi", role = c("aut", "cre"), email = "noreply@example.com")\n')
    write(os.path.join(P, "NAMESPACE"), "useDynLib(rzigwheeltest, .registration = TRUE)\nexport(dot, cxx_sum, cxx_throw)\n")
    write(os.path.join(P, "R", "fns.R"), "dot <- function(x, y) .Call(C_dot, as.double(x), as.double(y))\n"
          "cxx_sum <- function(x) .Call(C_cxx_sum, as.double(x))\ncxx_throw <- function(x) .Call(C_cxx_throw, as.character(x))\n")
    write(os.path.join(P, "src", "dot.c"), textwrap.dedent("""\
        #include <R.h>
        #include <Rinternals.h>
        #include <R_ext/BLAS.h>
        #include <R_ext/Rdynload.h>
        SEXP cxx_sum(SEXP x);
        SEXP cxx_throw(SEXP x);
        static SEXP dot(SEXP x, SEXP y) {
            int n = LENGTH(x), one = 1;
            return ScalarReal(F77_CALL(ddot)(&n, REAL(x), &one, REAL(y), &one));
        }
        static const R_CallMethodDef calls[] = {
            {"C_dot", (DL_FUNC) &dot, 2}, {"C_cxx_sum", (DL_FUNC) &cxx_sum, 1},
            {"C_cxx_throw", (DL_FUNC) &cxx_throw, 1}, {NULL, NULL, 0}
        };
        void R_init_rzigwheeltest(DllInfo *dll) {
            R_registerRoutines(dll, NULL, calls, NULL, NULL);
            R_useDynamicSymbols(dll, FALSE);
        }
        """))
    write(os.path.join(P, "src", "sum.cpp"), textwrap.dedent("""\
        #include <cstdio>
        #include <numeric>
        #include <stdexcept>
        #include <string>
        #include <vector>
        #include <Rinternals.h>
        extern "C" SEXP cxx_sum(SEXP x) {
            std::vector<double> v(REAL(x), REAL(x) + LENGTH(x));
            return Rf_ScalarReal(std::accumulate(v.begin(), v.end(), 0.0));
        }
        static void thrower(const std::string &s) { throw std::runtime_error("cxx: " + s); }
        extern "C" SEXP cxx_throw(SEXP x) {
            char msg[256] = "";
            try { thrower(CHAR(STRING_ELT(x, 0))); } catch (const std::exception &e) { std::snprintf(msg, sizeof msg, "%s", e.what()); }
            Rf_error("%s", msg);
            return R_NilValue;
        }
        """))
    write(os.path.join(P, "src", "Makevars.win"), "PKG_LIBS = $(BLAS_LIBS) $(FLIBS)\n")
    A = os.path.join(T, "src", "rzigwheelar")
    write(os.path.join(A, "DESCRIPTION"), "Package: rzigwheelar\nVersion: 0.1\nTitle: Test\nDescription: Test package.\n"
          "License: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n")
    write(os.path.join(A, "NAMESPACE"), "useDynLib(rzigwheelar)\nexport(f)\n")
    write(os.path.join(A, "R", "f.R"), 'f <- function() .Call("rzigwheelar_f")\n')
    write(os.path.join(A, "src", "f.c"), "#include <Rinternals.h>\nint rzigwheelar_foo(void);\n"
          "SEXP rzigwheelar_f(void) { return ScalarInteger(rzigwheelar_foo()); }\n")
    write(os.path.join(A, "src", "foo", "foo.c"), "int rzigwheelar_foo(void) { return 42; }\n")
    write(os.path.join(A, "src", "Makevars.win"), "PKG_LIBS = foo/libfoo.a\n$(SHLIB): foo/libfoo.a\nfoo/libfoo.a: foo/foo.o\n"
          "\t$(AR) cr $@ foo/foo.o\n\t$(RANLIB) $@\n")
    PC = os.path.join(T, "src", "rzigwheelc")
    write(os.path.join(PC, "DESCRIPTION"), "Package: rzigwheelc\nVersion: 0.1\nTitle: r-zig Wheel C Test\nDescription: C only.\n"
          'License: GPL-2\nAuthors@R: person("r-zig-pixi", role = c("aut", "cre"), email = "noreply@example.com")\n')
    write(os.path.join(PC, "NAMESPACE"), "useDynLib(rzigwheelc, .registration = TRUE)\nexport(twice)\n")
    write(os.path.join(PC, "R", "fns.R"), "twice <- function(x) .Call(C_twice, as.double(x))\n")
    write(os.path.join(PC, "src", "twice.c"), "#include <R.h>\n#include <Rinternals.h>\n#include <R_ext/Rdynload.h>\n"
          "static SEXP twice(SEXP x) { return ScalarReal(2 * REAL(x)[0]); }\n"
          'static const R_CallMethodDef calls[] = {{"C_twice", (DL_FUNC) &twice, 1}, {NULL, NULL, 0}};\n'
          "void R_init_rzigwheelc(DllInfo *dll) { R_registerRoutines(dll, NULL, calls, NULL, NULL); R_useDynamicSymbols(dll, FALSE); }\n")
    libs = {n: os.path.join(T, n) for n in ("lib1", "lib2", "lib6", "lib7")}
    for d in libs.values():
        os.makedirs(d)

    step("console scripts")
    print(run(venv, ["R", "--version"])[1].splitlines()[0])
    print(run(venv, ["python", "-m", "r_zig", "--version"])[1].splitlines()[0])
    r_home = run(venv, ["python", "-c", "import r_zig; print(r_zig.r_home())"])[1].strip()
    tc = os.path.join(r_home, "bin", "toolchain")
    print("r_home:", r_home)

    step("capability profile, and rzig in the base")
    rscript(venv, f"""
        caps <- capabilities()
        stopifnot(!caps[["cairo"]], !caps[["ICU"]], caps[["libcurl"]], caps[["iconv"]])
        stopifnot(grepl("/r_zig/R/lib/R$", R.home()))
        tc <- file.path(R.home(), "bin", "toolchain")
        stopifnot(file.exists(file.path(tc, c({", ".join(repr(n) for n in RZIG_NAMES)}))), !dir.exists(file.path(tc, "usr")))
        set.seed(1); m <- matrix(rnorm(64), 8)
        stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
        cat("profile OK\\n")
    """)

    step("TLS: an HTTPS request through R's libcurl (no CA bundle in the Windows tree)")
    rscript(venv, """
        r <- tryCatch({ curlGetHeaders("https://cloud.r-project.org/", timeout = 20L); "ok" },
                      error = function(e) conditionMessage(e))
        if (identical(r, "ok")) cat("TLS: requests OK\\n") else
          if (grepl("certificate|SSL|schannel", r, ignore.case = TRUE)) stop("TLS: ", r) else cat("TLS: skipped (offline?):", r, "\\n")
    """)

    step("r-zig alone: r-zig-slim's own test (recipe/test-preflight.R)")
    print(run(venv, ["Rscript", os.path.join(ROOT, "recipe", "test-preflight.R")])[1].rstrip())

    step(f"+ {os.path.basename(cc_wheel)} (+ ziglang from PyPI)")
    pip(venv, "install", "--quiet", cc_wheel)
    if not installed(venv, "ziglang"):
        die("r-zig-compilers did not bring ziglang")
    if os.path.exists(os.path.join(tc, "usr")):
        die(f"r-zig-compilers brought {tc}\\usr")

    step("R CMD INSTALL via the console script (ZIG_BIN from import ziglang), no make on PATH: rzig build")
    _, log = run(venv, ["R", "CMD", "INSTALL", "--preclean", "-l", libs["lib1"], P], RZIG_TRACE="1")
    if "rzig build: tier 1" not in log:
        die("the console-script install did not build through rzig build (no 'rzig build: tier 1' in its log)", log)
    rscript(venv, f"""
        library(rzigwheeltest, lib.loc = '{rpath(libs["lib1"])}')
        stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55)
        e <- tryCatch(cxx_throw('boom'), error = conditionMessage)
        stopifnot(identical(e, 'cxx: boom'))
        cat('compiled package OK (console script; a C++ exception caught)\\n')
    """)

    step("a package that needs make (a Makevars rule), with no build tools: the preflight stops")
    rc, log = run(venv, ["R", "CMD", "INSTALL", "-l", libs["lib6"], A], ok=False)
    if rc == 0:
        die("the Makevars-rule package installed with no make", log)
    # rzig's pip line: `pip install r-zig-build-tools` once groups.zig
    # knows the Windows wheels; until then "no wheels for Windows"
    # (b13-env-ci PLAN.md, Needs from other topics)
    pip_line = "pip install r-zig-build-tools" in log
    if ("rzigwheelar needs make" not in log or "r-zig-build-tools" not in log
            or not (pip_line or "pip:         no wheels for Windows" in log)
            or os.path.exists(os.path.join(libs["lib6"], "rzigwheelar"))):
        die("the Makevars-rule package did not stop in the preflight naming r-zig-build-tools", log)
    print("ok: stops naming r-zig-build-tools" + ("" if pip_line else " (note: rzig's pip line still says no wheels for Windows)"))

    step(f"+ {os.path.basename(bt_wheel)}")
    pip(venv, "install", "--quiet", bt_wheel)
    rscript(venv, """
        mk <- Sys.which("make")
        stopifnot(nzchar(mk), file.exists(mk),
                  endsWith(tolower(normalizePath(mk, winslash = "/")), "/bin/toolchain/usr/bin/make.exe"))
        cat("make =", mk, "\\n")
    """)

    step("the Makevars-rule package, built by the wheel's make")
    _, log = run(venv, ["R", "CMD", "INSTALL", "-l", libs["lib6"], A], RZIG_TRACE="1")
    if "rzig build: rzigwheelar needs make" not in log:
        die("the Makevars-rule package did not go to make with rzig build's reason", log)
    rscript(venv, f"library(rzigwheelar, lib.loc = '{rpath(libs['lib6'])}'); stopifnot(f() == 42L); cat('needs-make package OK\\n')")

    step("R CMD INSTALL via R_HOME/bin/R.exe, ZIG_BIN unset (Renviron.site -> sibling ziglang), R_ZIG_PKG_BUILDER=make")
    _, log = run(venv, [os.path.join(r_home, "bin", "R.exe"), "CMD", "INSTALL", "--preclean", "-l", libs["lib2"], P],
                 R_ZIG_PKG_BUILDER="make", RZIG_TRACE="1")
    if "rzig build:" in log:
        die("R_ZIG_PKG_BUILDER=make still ran rzig build", log)
    _, out = run(venv, [os.path.join(r_home, "bin", "Rscript.exe"), "-e",
                        "stopifnot(nzchar(Sys.getenv('ZIG_BIN')), file.exists(Sys.getenv('ZIG_BIN'))); "
                        f"library(rzigwheeltest, lib.loc = '{rpath(libs['lib2'])}'); "
                        "stopifnot(dot(1:3, 4:6) == 32, cxx_sum(1:10) == 55); "
                        "cat('ZIG_BIN =', normalizePath(Sys.getenv('ZIG_BIN')), '\\ncompiled package OK (R_HOME/bin/R.exe)\\n')"])
    print(out.rstrip())

    step(f"+ {os.path.basename(tc_wheel)}: resolves from the installed groups")
    pip(venv, "install", "--quiet", tc_wheel)
    for d in ("r-zig-compilers", "r-zig-toolchain"):
        di = f"{d.replace('-', '_')}-{R_VERSION}.dist-info/"
        files = pip(venv, "show", "-f", d).split("Files:", 1)[1].split()
        other = [f for f in files if not f.replace("\\", "/").startswith(di)]
        if f"{di}METADATA" not in [f.replace("\\", "/") for f in files] or other:
            die(f"{d}'s files are not its {di} alone: {other}")
    print("ok: r-zig-compilers and r-zig-toolchain hold their .dist-info alone")

    step("a second venv: r-zig-toolchain from dist/wheel, no index, brings the other three")
    venv2 = os.path.join(T, "venv2")
    subprocess.run([sys.executable, "-m", "venv", venv2], check=True)
    zv = [line.split(": ", 1)[1] for line in pip(venv, "show", "ziglang").splitlines() if line.startswith("Version: ")][0]
    pip(venv2, "install", "--quiet", f"ziglang=={zv}")
    pip(venv2, "install", "--quiet", "--no-index", "--find-links", os.path.join(ROOT, "dist", "wheel"), f"r-zig-toolchain=={R_VERSION}")
    for n in ("r-zig", "r-zig-compilers", "r-zig-build-tools", "r-zig-toolchain", "ziglang"):
        if not installed(venv2, n):
            die(f"the second venv has no {n}")
    rscript(venv2, """
        mk <- Sys.which("make")
        stopifnot(nzchar(mk), identical(normalizePath(mk), normalizePath(file.path(R.home(), "bin", "toolchain", "usr", "bin", "make.exe"))))
        cat("second venv: make =", mk, "\\n")
    """)

    step("uninstalling the three group wheels leaves r-zig whole")
    pip(venv, "uninstall", "--quiet", "-y", "r-zig-toolchain", "r-zig-build-tools", "r-zig-compilers")
    left = sorted(os.path.relpath(os.path.join(dp, f), tc).replace("\\", "/") for dp, _, fs in os.walk(tc) for f in fs)
    link_object = [f for f in ("cfguard.o", "clear_cache.o") if f in left]
    if left != sorted(RZIG_NAMES + link_object) or len(link_object) != 1:
        die(f"R_HOME/bin/toolchain after uninstalling the groups holds {left}, not rzig's names and one link object")
    _, log = run(venv, [os.path.join(r_home, "bin", "R.exe"), "CMD", "INSTALL", "-l", libs["lib7"], PC], RZIG_TRACE="1")
    if "rzig build: tier 1" not in log:
        die("with the groups uninstalled, the C package did not build through rzig build", log)
    rscript(venv, f"library(rzigwheelc, lib.loc = '{rpath(libs['lib7'])}'); stopifnot(twice(21) == 42); "
                  "cat('r-zig without the groups OK; ziglang still compiles\\n')")

    step("and with ziglang uninstalled too: r-zig alone again (recipe/test-preflight.R)")
    pip(venv, "uninstall", "--quiet", "-y", "ziglang")
    print(run(venv, ["Rscript", os.path.join(ROOT, "recipe", "test-preflight.R")])[1].rstrip())
    step(f"wheel test passed ({', '.join(os.path.basename(w) for w in (wheel, cc_wheel, bt_wheel, tc_wheel))})")


if __name__ == "__main__":
    if os.name != "nt":
        sys.exit("wheel-test-windows: Windows only (scripts/wheel-test.sh is the unix test)")
    try:
        main()
    finally:
        shutil.rmtree(T, ignore_errors=True)
