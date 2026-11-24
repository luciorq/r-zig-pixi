# M-14: embed r-zig's libR through rpy2, compile and run a C++ (Rcpp)
# function, throw across the boundary. argv[1] = "host-first" loads the
# host's libstdc++.so.6 before R (what a Python that already imported a
# C++ extension has done), else nothing is preloaded.
# Env: PROBE_LIB, a library with Rcpp installed.
import ctypes
import os
import sys

if len(sys.argv) > 1 and sys.argv[1] == "host-first":
    ctypes.CDLL("libstdc++.so.6", mode=ctypes.RTLD_GLOBAL)


def loaded():
    with open("/proc/self/maps") as f:
        return sorted({l.split()[-1] for l in f if "libstdc++" in l or "libgcc_s" in l})


print("preloaded:", loaded())
import rpy2.robjects as ro  # noqa: E402

print("rpy2 R:", ro.r("R.version.string")[0], "| R_HOME", ro.r("R.home()")[0])
print("after R init:", loaded())
ro.r(f'.libPaths(c("{os.environ["PROBE_LIB"]}", .libPaths()))')
ok = True
for name, code, want in [
    ("rcpp-compile", 'Rcpp::cppFunction("int dbl(int x) { if (x < 0) Rcpp::stop(\\"negative: %d\\", x); return 2 * x; }"); dbl(21L)', "42"),
    ("rcpp-stop", 'tryCatch(dbl(-1L), error = function(e) conditionMessage(e))', "negative: -1"),
]:
    try:
        got = str(ro.r(code)[0])
        res = "ok" if want in got else f"FAIL got {got!r}"
    except Exception as e:  # rpy2 raises RRuntimeError with R's message
        res = f"FAIL {type(e).__name__}: {e}"
    ok = ok and res == "ok"
    print(f"PROBE rpy2-{name}: {res}")
print("at end:", loaded())
sys.exit(0 if ok else 1)
