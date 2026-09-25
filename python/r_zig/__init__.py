"""R, built with zig by r-zig-pixi, as an installable wheel.

The wheel carries a complete, relocatable R installation — the "minimal"
build profile: no cairo/png devices, no ICU, no OpenMP, no X11/tcltk —
under ``r_zig/R``. The ``R`` and ``Rscript`` console scripts run it, and
``r_home()``/``environ()`` hand it to embedders such as rpy2.

Packages with C/C++ code compile with the PyPI ``ziglang`` package, a
dependency of this wheel: R's Makeconf names small zig shims
(``R_HOME/bin/toolchain/zig-cc`` and friends), which exec ``$ZIG_BIN``.
The console scripts and ``environ()`` set ``ZIG_BIN`` from the importable
``ziglang``. When R is started some other way, ``R_HOME/etc/Renviron.site``
points it at a ``ziglang`` installed in the same site-packages directory.
GNU make is bundled. Packages with Fortran sources need a Fortran compiler,
which neither this wheel nor ziglang provides.
"""

from __future__ import annotations

import os
import sys

__all__ = ["R_VERSION", "prefix", "r_home", "zig_bin", "environ", "main", "main_rscript"]

# Filled in by scripts/make-wheel.py when the wheel is assembled.
R_VERSION = "@R_VERSION@"
__version__ = "@WHEEL_VERSION@"

_HERE = os.path.dirname(os.path.abspath(__file__))


def prefix() -> str:
    """The installation prefix: ``bin/R``, ``bin/Rscript``, ``lib/``."""
    return os.path.join(_HERE, "R")


def r_home() -> str:
    """R_HOME of the bundled R (what ``R.home()`` reports)."""
    return os.path.join(_HERE, "R", "lib", "R")


def zig_bin() -> str | None:
    """Path of the zig binary shipped by the ``ziglang`` package, if importable."""
    try:
        import ziglang
    except ImportError:
        return None
    exe = os.path.join(os.path.dirname(ziglang.__file__), "zig.exe" if os.name == "nt" else "zig")
    return exe if os.path.isfile(exe) else None


def environ(base: dict[str, str] | None = None) -> dict[str, str]:
    """A copy of ``base`` (default: ``os.environ``) set up to run this R.

    Sets ``R_HOME`` (what embedders like rpy2 read) and, unless already
    set, ``ZIG_BIN`` (what R's compiler shims exec).
    """
    env = dict(os.environ if base is None else base)
    env["R_HOME"] = r_home()
    if not env.get("ZIG_BIN"):
        zig = zig_bin()
        if zig:
            env["ZIG_BIN"] = zig
    return env


def _exec(name: str, args: list[str]) -> None:
    if os.name == "nt":
        raise SystemExit("r-zig: this wheel's R build is unix-only")
    exe = os.path.join(prefix(), "bin", name)
    env = environ()
    # bin/R derives R_HOME from its own location and warns ("ignoring
    # environment value of R_HOME") whenever the environment disagrees —
    # e.g. a system R's R_HOME left in the shell. Let it derive.
    del env["R_HOME"]
    os.execve(exe, [exe, *args], env)


def main(argv: list[str] | None = None) -> None:
    """Console script ``R`` (and ``python -m r_zig``)."""
    _exec("R", sys.argv[1:] if argv is None else argv)


def main_rscript(argv: list[str] | None = None) -> None:
    """Console script ``Rscript``."""
    _exec("Rscript", sys.argv[1:] if argv is None else argv)
