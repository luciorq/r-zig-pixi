"""rpy2 finds this R when it would find no other (b14-l5 D25-D27; experimental).

rpy2 looks for R through ``R_HOME``, then ``R RHOME`` from an ``R`` on
``PATH``, then (Windows) the registry (``rpy2.situation.get_r_home``),
both when it runs and when pip builds rpy2-rinterface from its source
package (PyPI has no linux wheel of it). From the python of a venv that
is not activated it finds no ``R`` of this wheel, and with no other R it
stops: ``r_home is None`` at run time, ``sys.exit`` in the build.

``r_zig.pth``, which the wheel puts in site-packages, imports this
module at every start of that Python. It adds a meta path finder that
finds nothing and acts on two imports only, each once, and only where
rpy2 would see no R or this wheel's R: ``R_HOME`` unset or this R, and
with ``R_HOME`` unset the first ``R`` on ``PATH`` missing or an r-zig
``R`` (on Windows also no R in the registry). Where rpy2 would find
another R (a system R, a conda env's R on ``PATH``, an ``R_HOME`` set
to it), it does nothing, so rpy2 builds and runs as it would without
r-zig (D27):

- ``rpy2``: sets ``R_HOME`` to this R unless set and, unless set,
  ``RPY2_CFFI_MODE=ABI``, so rpy2 opens this R's libR whatever mode its
  compiled module was built in (D25, D26).
- ``setuptools``, when the current directory is an rpy2 source tree (pip
  and other build front ends run the build backend there) and
  ``RPY2_CFFI_MODE`` is unset: ``RPY2_CFFI_MODE=ABI``, so rpy2's build
  needs no R and gives a ``py3-none-any`` wheel with no path in it
  (D26). ``R_HOME`` is not set.

The R lookup runs only on those two imports, never at start. The
finder removes itself once both have fired. A process that imports
neither keeps its environment untouched, so another R started from it
never sees an ``R_HOME`` it did not ask for.
"""

from __future__ import annotations

import os
import sys

from . import prefix, r_home

# rpy2's cffi build script, relative to the source tree: rpy2-rinterface
# 3.6's source package, then rpy2 3.5's single package
_BUILD = (
    os.path.join("src", "rpy2", "rinterface_lib", "_rinterface_cffi_build.py"),
    os.path.join("rpy2", "rinterface_lib", "_rinterface_cffi_build.py"),
)


def _is_r_zig(path: str) -> bool:
    """``path`` is an R of r-zig: a file under a ``r_zig/R`` tree, or a
    console script that runs ``r_zig`` (the ``R`` pip and uv write: a
    text script on unix, a launcher with the script appended on Windows)."""
    real = os.path.realpath(path)
    if real.startswith(os.path.realpath(prefix()) + os.sep):
        return True
    try:
        with open(real, "rb") as f:
            head = f.read(8192)
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 8192))
            tail = f.read()
    except OSError:
        return False
    return b"r_zig" in head or b"r_zig" in tail


def _registry_r() -> bool:
    """An R installed with its Windows installer (rpy2's last resort)."""
    try:
        import winreg
    except ImportError:
        return False
    for root in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        try:
            with winreg.OpenKeyEx(root, "Software\\R-core\\R") as key:
                if winreg.QueryInfoKey(key)[0] > 0:
                    return True
        except OSError:
            pass
    return False


def _no_other_r() -> bool:
    """rpy2 would find no R, or an R of r-zig (D27)."""
    home = os.environ.get("R_HOME")
    if home:
        return os.path.realpath(home) == os.path.realpath(r_home())
    import shutil  # here, not at start (F40 start cost)

    found = shutil.which("R")
    if found:
        return _is_r_zig(found)
    return not (os.name == "nt" and _registry_r())


class _Rpy2Finder:
    _pending = {"rpy2", "setuptools"}

    @classmethod
    def find_spec(cls, name, path=None, target=None):
        if name in cls._pending:
            cls._pending.discard(name)
            if not cls._pending:
                try:
                    sys.meta_path.remove(cls)
                except ValueError:
                    pass
            env = os.environ
            if name == "rpy2":
                if _no_other_r():
                    if not env.get("R_HOME"):
                        env["R_HOME"] = r_home()
                    if not env.get("RPY2_CFFI_MODE"):
                        env["RPY2_CFFI_MODE"] = "ABI"
            elif not env.get("RPY2_CFFI_MODE") and any(map(os.path.isfile, _BUILD)) and _no_other_r():
                env["RPY2_CFFI_MODE"] = "ABI"
        return None


# one finder per process, also if this module is loaded again
if _Rpy2Finder not in sys.meta_path:
    sys.meta_path.insert(0, _Rpy2Finder)
