"""r-zig binary repository: load packages in R embedded in a Python process.

    python3 -I repo/embed-test.py <R_HOME> <library> [<package>...]

What rpy2 does, with ctypes alone: libR.so of <R_HOME> (a conda env's
lib/R, or the r-zig wheel's r_zig/R/lib/R) is loaded into this Python,
which may be any Python (the host's /usr/bin/python3 is the case that
matters: no rpath of its own into R's env), R is started with
Rf_initEmbeddedR, and each package (default: every row of
packages.tsv) is loaded from <library> with its row's smoke. Nothing in the environment helps: no
LD_LIBRARY_PATH, no R_LIBS. The binaries must find the libraries they
need themselves (b14-l5 U5, F6). Prints each library from
outside glibc the process mapped, and exits 1 when a package does not
load or its smoke fails.
"""

import csv
import ctypes
import os
import sys

if len(sys.argv) < 3:
    sys.exit(__doc__)
if "LD_LIBRARY_PATH" in os.environ:
    sys.exit("embed-test: run it without LD_LIBRARY_PATH")
rhome, lib = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "packages.tsv"), newline="") as f:
    rows = {r["package"]: r["smoke"] for r in csv.DictReader((x for x in f if not x.startswith("#")), delimiter="\t", quoting=csv.QUOTE_NONE)}
pkgs = sys.argv[3:] or list(rows)

os.environ["R_HOME"] = rhome
R = ctypes.CDLL(os.path.join(rhome, "lib", "libR.so"), mode=ctypes.RTLD_GLOBAL)
argv = (ctypes.c_char_p * 4)(b"R", b"--quiet", b"--no-save", b"--no-echo")
R.Rf_initEmbeddedR(4, argv)
R.R_ParseEvalString.restype = ctypes.c_void_p
R.R_ParseEvalString.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
env = ctypes.c_void_p.in_dll(R, "R_GlobalEnv").value


def r_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


# Errors are caught in R; a failure sets the exit status R quits with.
code = ".libPaths(c(%s, .libPaths())); bad <- 0L\n" % r_str(lib)
for p in pkgs:
    smoke = rows.get(p, "TRUE")
    code += (
        "r <- tryCatch({ loadNamespace(%s); v <- eval(str2lang(%s), globalenv()); "
        "if (isTRUE(v)) 'ok' else 'smoke not TRUE' }, error = function(e) paste('ERROR:', conditionMessage(e)))\n"
        "if (r != 'ok') bad <- bad + 1L\n"
        "cat(sprintf('EMBED %%-12s %%s\\n', %s, r))\n" % (r_str(p), r_str(smoke), r_str(p))
    )
code += (
    "m <- unique(sub('^\\\\S+\\\\s+\\\\S+\\\\s+\\\\S+\\\\s+\\\\S+\\\\s+\\\\S+\\\\s+', '', "
    "grep('\\\\.so', readLines('/proc/self/maps'), value = TRUE)))\n"
    "m <- m[!grepl('^(ld-linux|libc|libm|libdl|libpthread|librt|libutil|libresolv|libmvec)[.-]', basename(m)) & !startsWith(m, R.home())]\n"
    "cat(sprintf('MAPPED %%s\\n', sort(m)), sep = '')\n"
    "cat(sprintf('%%d of %%d packages ok\\n', length(%s) - bad, length(%s)))\n"
    "q(status = as.integer(bad > 0L), save = 'no')\n"
) % (("c(" + ", ".join(r_str(p) for p in pkgs) + ")",) * 2)
# one expression per call (R_ParseEvalString's rule)
for expr in code.strip().split("\n"):
    R.R_ParseEvalString(("{ " + expr + " }").encode(), env)
