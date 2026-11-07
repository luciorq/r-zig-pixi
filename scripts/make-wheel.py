#!/usr/bin/env python3
"""Assemble the r-zig wheels from the minimal variant's standalone tree.

Input is the tree `pixi run -e minimal build` leaves in
dist/minimal/R-<ver>-zig, the same tree the standalone archive packs
(feat-no-host-paths F1.7): installed by zig build (location-independent
launchers, $ORIGIN/@loader_path rpaths, rzig in lib/R/bin/toolchain, a
Makeconf that names no build path, the env's CA bundle in ssl/ named in
etc/Renviron) with the conda libraries it needs vendored into lib/ by
zig-build.sh (vendor-libs.sh), and the records of those (share/licenses:
SOURCES and each package's licence texts, B33 a), which r-zig's
dist-info/licenses also holds beside R's COPYING (PHASE8 open point E a).
GNU make is not in it: it is the
build-tools group's, in the toolchain tree `pixi run -e minimal
toolchain` leaves in dist/toolchain/R-<ver>-zig, as
lib/R/bin/toolchain/usr/bin/make with its SOURCES and LICENSES/
(feat-standalone-toolchain B23, B30), where etc/Renviron's PATH line
finds it (B25).
That tree already runs from anywhere, so a wheel is that tree under
`r_zig/R/` plus the small `r_zig` Python package (python/r_zig/) and the
console scripts `R`/`Rscript`. Four wheels come out of it, the base and
a package per toolchain group, as on conda (feat-standalone-toolchain
B29 a; phase 4):
- `r-zig`, the base: R, with rzig under each of its names in
  R_HOME/bin/toolchain, as in the base archive and r-zig-slim (B19). It
  installs packages that need no compiling; a package that does stops in
  the preflight with rzig's text, which names the group's wheel (B35).
- `r-zig-compilers`: no files; it requires PyPI `ziglang`, the C/C++
  compiler rzig runs. PyPI has no Fortran compiler, and the wheel's R
  offers no OpenMP, so the toolchain tree's openmp/ is in no wheel.
- `r-zig-build-tools`: the toolchain tree's usr/ (GNU make, its SOURCES
  and LICENSES/), under make's licence (PHASE4 open point E a).
- `r-zig-toolchain`: no files; it requires both groups.
Each group requires exactly this `r-zig` (PHASE4 open point A a), as
conda's exact pins do (B28): r-zig-build-tools writes into `r_zig/R/`,
and without its R would leave a partial tree. The wheels install into the
same `r_zig/` directory without sharing a file, so each one's RECORD owns
only its own. No build backend: a wheel is a zip with a .dist-info
directory (PEP 427), written here with the stdlib only; a wheel with no
files is its .dist-info alone.

The platform tag is computed from the binaries, not assumed: on Linux the
highest GLIBC_x.y symbol version any ELF file references (manylinux_x_y;
the zig build targets 2.17, which is also manylinux2014), on macOS the
highest LC_BUILD_VERSION/LC_VERSION_MIN_MACOSX minimum any Mach-O file
declares. One tag set, from r-zig's and r-zig-build-tools' files
together, for all four wheels (B29): make alone would tag an older macOS
than R. Python-independent (`py3-none`): nothing here links libpython.

Usage (from the `wheel` pixi env, which sets R_VERSION/R_BUILD_VARIANT):
    pixi run -e wheel wheel [--prefix DIR] [--toolchain-prefix DIR]
                            [--out-dir DIR] [--build-tag N]
"""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import io
import os
import platform
import re
import stat
import struct
import sys
import time
import zipfile

DIST_NAME = "r-zig"
IMPORT_NAME = "r_zig"
# the groups' wheels, and the one that installs both (B29 a)
COMPILERS_DIST = "r-zig-compilers"
BUILD_TOOLS_DIST = "r-zig-build-tools"
TOOLCHAIN_DIST = "r-zig-toolchain"
TOOLCHAIN_PREFIX = "lib/R/bin/toolchain/"  # inside both trees; rzig's names in the R tree's
# What r-zig-build-tools takes from the toolchain tree: the build-tools
# group's usr/ (GNU make, its SOURCES and LICENSES/).
TOOLCHAIN_USR = TOOLCHAIN_PREFIX + "usr/"
# The licence each wheel states (PHASE4 open point E a): R's own, but
# GNU make's for r-zig-build-tools, whose only program is make (its
# usr/SOURCES says the same).
R_LICENSE = "GPL-2.0-only OR GPL-3.0-only"
MAKE_LICENSE = "GPL-3.0-or-later"
LICENSE_CLASSIFIERS = {
    R_LICENSE: ["GNU General Public License v2 (GPLv2)", "GNU General Public License v3 (GPLv3)"],
    MAKE_LICENSE: ["GNU General Public License v3 or later (GPLv3+)"],
}
# The runtime compiler. Keep in step with pixi.toml's `zig = "0.16.*"`:
# zig is pinned by exact version across this project family (consolidation
# PLAN.md, convention 2); `<0.16.1` still admits ziglang's `.postN`
# repackagings of the same zig release.
ZIGLANG_REQUIREMENT = "ziglang>=0.16.0,<0.16.1"
# Absolute build-prefix paths in here can't be relocated and are useless
# to a wheel (libR.pc: embedding R through pkg-config).
EXCLUDE_DIRS = ("lib/pkgconfig",)

ROOT = os.environ.get("PIXI_PROJECT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def die(msg: str) -> None:
    sys.exit(f"make-wheel: error: {msg}")


# --------------------------------------------------------------------------
# platform tag
# --------------------------------------------------------------------------

ELF_MAGIC = b"\x7fELF"
MACHO_MAGIC_64 = b"\xcf\xfa\xed\xfe"  # MH_MAGIC_64, little-endian (arm64/x86_64)
GLIBC_RE = re.compile(rb"GLIBC_(\d+)\.(\d+)(?:\.\d+)?")
LC_VERSION_MIN_MACOSX = 0x24
LC_BUILD_VERSION = 0x32


SHT_GNU_VERNEED = 0x6FFFFFFE


def glibc_requirement(data: bytes) -> tuple[int, int] | None:
    """Highest GLIBC_x.y symbol version an ELF file needs.

    Read from the version-needs section (.gnu.version_r) — what `objdump
    -T` and auditwheel look at. Not a regex over the whole file: binutils'
    own nm carries "GLIBC_2.36" as plain data (its DT_RELR handling), which
    would claim a glibc 2.36 floor for a tool that needs 2.14. Only
    little-endian ELF64 (x86_64, aarch64) is parsed; anything else, or a
    file without section headers, falls back to that regex, which can only
    over-state the requirement.
    """
    if data[4:6] == b"\x02\x01":  # ELFCLASS64, ELFDATA2LSB
        shoff = struct.unpack_from("<Q", data, 0x28)[0]
        shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
        if shoff and shnum and shoff + shnum * shentsize <= len(data):
            sections = [struct.unpack_from("<IIQQQQII", data, shoff + i * shentsize) for i in range(shnum)]
            versions = []
            for _name, sh_type, _flags, _addr, off, _size, link, count in sections:
                if sh_type != SHT_GNU_VERNEED:
                    continue
                stroff = sections[link][4]
                vn = off
                for _ in range(count):  # sh_info = number of Verneed entries
                    _ver, cnt, _file, aux, nxt = struct.unpack_from("<HHIII", data, vn)
                    va = vn + aux
                    for _ in range(cnt):
                        _hash, _flg, _other, name, vnxt = struct.unpack_from("<IHHII", data, va)
                        end = data.index(b"\0", stroff + name)
                        m = GLIBC_RE.fullmatch(data[stroff + name:end])
                        if m:
                            versions.append((int(m.group(1)), int(m.group(2))))
                        va += vnxt
                    vn += nxt
            return max(versions) if versions else None
    versions = [(int(a), int(b)) for a, b in GLIBC_RE.findall(data)]
    return max(versions) if versions else None


def macos_min_version(data: bytes) -> tuple[int, int] | None:
    """Deployment target of a thin 64-bit Mach-O file, from its load commands."""
    if len(data) < 32:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32  # sizeof(mach_header_64)
    found = None
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_BUILD_VERSION:
            ver = struct.unpack_from("<I", data, off + 12)[0]  # platform, then minos
        elif cmd == LC_VERSION_MIN_MACOSX:
            ver = struct.unpack_from("<I", data, off + 8)[0]
        else:
            ver = None
        if ver is not None:
            v = (ver >> 16, (ver >> 8) & 0xFF)
            found = v if found is None else max(found, v)
        if size == 0:
            break
        off += size
    return found


def platform_tags(files: list[tuple[str, bytes]]) -> list[str]:
    system, machine = platform.system(), platform.machine()
    if system == "Linux":
        arch = {"amd64": "x86_64", "arm64": "aarch64"}.get(machine, machine)
        need, worst = (2, 5), None
        for rel, data in files:
            if data[:4] == ELF_MAGIC:
                v = glibc_requirement(data)
                if v and v > need:
                    need, worst = v, rel
        print(f"make-wheel: highest glibc requirement GLIBC_{need[0]}.{need[1]} ({worst})")
        tags = [f"manylinux_{need[0]}_{need[1]}_{arch}"]
        # PEP 600 aliases for the legacy names pip < 20.3 still looks for
        legacy = {(2, 17): "manylinux2014", (2, 12): "manylinux2010", (2, 5): "manylinux1"}
        if need in legacy:
            tags.append(f"{legacy[need]}_{arch}")
        return tags
    if system == "Darwin":
        arch = {"aarch64": "arm64"}.get(machine, machine)
        need, worst = (10, 9), None
        for rel, data in files:
            if data[:4] == MACHO_MAGIC_64:
                v = macos_min_version(data)
                if v and v > need:
                    need, worst = v, rel
        print(f"make-wheel: highest macOS deployment target {need[0]}.{need[1]} ({worst})")
        major, minor = need
        # pip only generates macosx_<N>_0 tags for macOS 11+: a 12.3 minimum
        # can't be expressed exactly, so round up to the next major rather
        # than claim 12.0 works.
        if major >= 11 and minor > 0:
            major, minor = major + 1, 0
        return [f"macosx_{major}_{minor}_{arch}"]
    die(f"no wheel platform tag for {system} (the minimal build is linux/macOS only)")
    return []


# --------------------------------------------------------------------------
# wheel contents
# --------------------------------------------------------------------------


def collect_tree(prefix: str) -> list[tuple[str, str]]:
    """(relative path, absolute path) for every file under prefix, sorted."""
    out = []
    for dirpath, dirnames, filenames in os.walk(prefix):
        rel_dir = os.path.relpath(dirpath, prefix).replace(os.sep, "/")
        dirnames[:] = sorted(d for d in dirnames if (d if rel_dir == "." else f"{rel_dir}/{d}") not in EXCLUDE_DIRS)
        for name in filenames:
            rel = name if rel_dir == "." else f"{rel_dir}/{name}"
            out.append((rel, os.path.join(dirpath, name)))
    return sorted(out)


def leak_scan(files: list[tuple[str, bytes]], needles: list[bytes]) -> None:
    """Fail on build-machine paths in the files R reads at run time.

    etc/ (Makeconf, Renviron, ldpaths) and the bin/ scripts are what R
    and R CMD INSTALL actually interpret: a build path there breaks the
    wheel on any other machine. Anything else (strings in binaries, such
    as the vendored conda libraries' compiled-in env paths) is reported,
    not fatal; verify-tree.sh checks R's own files byte for byte. The
    toolchain tree's files are scanned too: its SOURCES and LICENSES/ are
    text under lib/R/bin/, so a build path there is fatal, as in
    verify-toolchain.sh; make's strings are only reported (C18).
    """
    fatal, other = [], []
    for rel, data in files:
        if not any(n in data for n in needles):
            continue
        runtime = b"\0" not in data[:8192] and rel.startswith(("lib/R/etc/", "bin/", "lib/R/bin/"))
        # Comment lines count too: build.zig writes Makeconf's configure
        # line without build paths as well (feat-no-host-paths F1.5).
        if runtime:
            fatal.append(rel)
        else:
            other.append(rel)
    if other:
        shown = ", ".join(other[:8]) + (f", ... ({len(other)} total)" if len(other) > 8 else "")
        print(f"make-wheel: note: build paths only in comments, binaries' strings or non-run-time files: {shown}")
    if fatal:
        die("build-machine paths in run-time files (not a packaged tree?): " + ", ".join(fatal))


def renviron_site(existing: bytes | None) -> bytes:
    # R_HOME is <site-packages>/r_zig/R/lib/R; ziglang installs its binary
    # as <site-packages>/ziglang/zig. Renviron expands a nested default
    # only when it is a whole ${...} term, hence the helper variable. When
    # ziglang lives elsewhere this names a missing file and rzig looks
    # further (zigbuild/tools/rzig/find_zig.zig): PATH, then
    # `python3 -m ziglang` when that python3 has ziglang.
    add = (
        "## r-zig wheel: compile packages with the PyPI ziglang package\n"
        "## installed next to this one (see r_zig/__init__.py).\n"
        "R_ZIG_ZIGLANG=${R_HOME}/../../../../ziglang/zig\n"
        "ZIG_BIN=${ZIG_BIN-${R_ZIG_ZIGLANG}}\n"
    ).encode()
    return (existing.rstrip(b"\n") + b"\n\n" + add) if existing else add


# The four wheels' descriptions. Each says the one recommendation the
# conda packages and the README give (PHASE4 Cg16), and that PyPI has no
# Fortran compiler (B29).
DESCRIPTIONS = {
    DIST_NAME: """\
# r-zig

R {r_version} as a Python wheel: a complete, relocatable R built from
source with the [Zig](https://ziglang.org) toolchain by
[r-zig-pixi](https://github.com/luciorq/r-zig-pixi), in its *minimal*
profile.

```sh
pip install r-zig
R --version
Rscript -e 'sessionInfo()'
python -c 'import r_zig; print(r_zig.r_home())'   # R_HOME, e.g. for rpy2
```

`install.packages()` installs packages that need no compiling with this
wheel alone. It carries rzig, the compiler front R's Makeconf names; the
compiler and the build tools come in their own wheels. To compile
packages, add r-zig-toolchain (r-zig-compilers and r-zig-build-tools):

```sh
pip install r-zig-toolchain
```

r-zig-compilers brings the PyPI [`ziglang`](https://pypi.org/project/ziglang/)
package as the C/C++ compiler, so no system compiler is needed; alone, it
installs packages that have no configure script and no make rules, and
compiles such code at run time (`R CMD SHLIB`: Rcpp's `sourceCpp()`,
inline, TMB) with no make. r-zig-build-tools brings GNU make, for the
rest: configure scripts, Makevars rules, Objective-C, `R CMD config`, and
installing pkgbuild, pak or devtools from source once.
Without a group, an install that needs it stops and names the wheel to
add. PyPI has no Fortran compiler: packages with Fortran sources need
LLVM flang on PATH.

The minimal profile has no cairo/png/svg devices (`pdf()` and
`postscript()` work), no ICU (collation uses the C library), no OpenMP
(nothing to clash with the OpenMP runtimes other wheels load), no
X11/tcltk/readline/NLS, and R's internal reference BLAS/LAPACK. Linux
wheels need glibc 2.17 or newer.
""",
    COMPILERS_DIST: """\
# r-zig-compilers

The compilers for the [`r-zig`](https://pypi.org/project/r-zig/) wheel
(R {r_version}): it requires the PyPI
[`ziglang`](https://pypi.org/project/ziglang/) package, which rzig, the
compiler front in r-zig's R_HOME/bin/toolchain, runs as the C/C++
compiler, and exactly the `r-zig` it was built with. It holds no files.

With it, `install.packages()` compiles packages that have no configure
script and no make rules, and `R CMD SHLIB` compiles such code at run
time (Rcpp's `sourceCpp()`, inline, TMB) with no make; once pkgbuild or
pak is installed, their compiler check passes too. To compile packages,
add r-zig-toolchain (r-zig-compilers and r-zig-build-tools):

```sh
pip install r-zig-toolchain
```

PyPI has no Fortran compiler: packages with Fortran sources need LLVM
flang on PATH.
""",
    BUILD_TOOLS_DIST: """\
# r-zig-build-tools

The build tools for the [`r-zig`](https://pypi.org/project/r-zig/) wheel
(R {r_version}): GNU make, which R runs for configure scripts, Makevars
rules, Objective-C and `R CMD config`. Installing pkgbuild, pak or
devtools from source needs it once: processx has Makevars rules, and ps
and pak have configure scripts. It requires exactly the `r-zig` it was
built with. To compile packages, add r-zig-toolchain (r-zig-compilers
and r-zig-build-tools):

```sh
pip install r-zig-toolchain
```

GNU make is conda-forge's build of it, unchanged, in
R_HOME/bin/toolchain/usr/bin, which r-zig's etc/Renviron puts first on
PATH: `usr/SOURCES` names its package and where its source is, and
`usr/LICENSES/` holds its licence, the GPL version 3 or later.
""",
    TOOLCHAIN_DIST: """\
# r-zig-toolchain

Everything the [`r-zig`](https://pypi.org/project/r-zig/) wheel (R
{r_version}) needs to compile packages: r-zig-compilers (the PyPI
[`ziglang`](https://pypi.org/project/ziglang/) package as the C/C++
compiler) and r-zig-build-tools (GNU make). It holds no files.

```sh
pip install r-zig-toolchain
```

PyPI has no Fortran compiler: packages with Fortran sources need LLVM
flang on PATH.
""",
}


def metadata(dist: str, version: str, r_version: str) -> str:
    """A wheel's METADATA, from one table for the four (B29 a): its
    summary, licence (PHASE4 open point E a) and requirements, each group
    on exactly this r-zig and r-zig-toolchain on exactly both groups
    (PHASE4 open point A a)."""
    summary, license_, requires = {
        DIST_NAME: (f"R {r_version} built with zig (minimal profile), relocatable", R_LICENSE, []),
        COMPILERS_DIST: (f"The r-zig compilers for R {r_version}: zig, from the PyPI ziglang package",
                         R_LICENSE, [f"{DIST_NAME}=={version}", ZIGLANG_REQUIREMENT]),
        BUILD_TOOLS_DIST: (f"The r-zig build tools for R {r_version}: GNU make", MAKE_LICENSE, [f"{DIST_NAME}=={version}"]),
        TOOLCHAIN_DIST: (f"The r-zig toolchain for R {r_version}: r-zig-compilers and r-zig-build-tools",
                         R_LICENSE, [f"{COMPILERS_DIST}=={version}", f"{BUILD_TOOLS_DIST}=={version}"]),
    }[dist]
    return (
        "Metadata-Version: 2.1\n"
        f"Name: {dist}\n"
        f"Version: {version}\n"
        f"Summary: {summary}\n"
        "Home-page: https://github.com/luciorq/r-zig-pixi\n"
        f"License: {license_}\n"
        "Classifier: Programming Language :: R\n"
        + "".join(f"Classifier: License :: OSI Approved :: {c}\n" for c in LICENSE_CLASSIFIERS[license_])
        + "Classifier: Operating System :: POSIX :: Linux\n"
        "Classifier: Operating System :: MacOS\n"
        "Requires-Python: >=3.8\n"
        + "".join(f"Requires-Dist: {r}\n" for r in requires)
        + "Description-Content-Type: text/markdown\n"
        "\n" + DESCRIPTIONS[dist].replace("{r_version}", r_version)
    )


def record_hash(data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    return f"sha256={digest}"


def main() -> None:
    r_version = os.environ.get("R_VERSION") or die("R_VERSION not set — run through `pixi run -e wheel wheel`")
    variant = os.environ.get("R_BUILD_VARIANT", "slim")

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--prefix", default=os.path.join(ROOT, "dist", variant, f"R-{r_version}-zig"),
                    help="installed R tree, as zig-build.sh leaves it (default: %(default)s)")
    ap.add_argument("--toolchain-prefix", default=os.path.join(ROOT, "dist", "toolchain", f"R-{r_version}-zig"),
                    help="toolchain tree, as zig-toolchain.sh leaves it (default: %(default)s)")
    ap.add_argument("--out-dir", default=os.path.join(ROOT, "dist", "wheel"))
    ap.add_argument("--version", default=r_version, help="wheel version (default: the R version)")
    ap.add_argument("--build-tag", default="", help="wheel build tag, e.g. 1 (PEP 427)")
    ap.add_argument("--any-variant", action="store_true",
                    help="allow a non-minimal tree (it would carry OpenMP and the whole graphics stack)")
    args = ap.parse_args()

    prefix = os.path.abspath(args.prefix)
    tc_prefix = os.path.abspath(args.toolchain_prefix)
    if variant != "minimal" and not args.any_variant:
        die(f"R_BUILD_VARIANT is {variant!r}; the wheel wraps the minimal variant (--any-variant to override)")
    if not os.path.isfile(os.path.join(prefix, "lib", "R", "bin", "exec", "R")):
        die(f"no R build at {prefix} — run `pixi run -e minimal build` first")
    # rzig, under CC's name and under the name install.R's hook runs it by
    # (patch 0013): the base's (B19)
    for name in ("zig-cc", "rzig"):
        if not os.path.isfile(os.path.join(prefix, "lib", "R", "bin", "toolchain", name)):
            die(f"{prefix} has no R_HOME/bin/toolchain/{name} — run `pixi run -e minimal build` first")
    if not any(re.search(r"\.(so(\.\d+)*|dylib)$", f) for f in os.listdir(os.path.join(prefix, "lib"))):
        die(f"no vendored libraries in {prefix}/lib — run `pixi run -e minimal build` first")
    with open(os.path.join(prefix, "lib", "R", "etc", "Renviron"), "rb") as f:
        has_ca = b"\nR_ZIG_CA_BUNDLE=" in b"\n" + f.read()
    if not (has_ca and os.path.isfile(os.path.join(prefix, "ssl", "cacert.pem"))):
        die(f"{prefix} has no CA bundle (ssl/cacert.pem, R_ZIG_CA_BUNDLE) — run `pixi run -e minimal build` first")
    if not os.path.isfile(os.path.join(prefix, "share", "licenses", "SOURCES")):
        die(f"{prefix} has no records (share/licenses/SOURCES) — run `pixi run -e minimal build` first")
    if not os.path.isfile(os.path.join(tc_prefix, "lib", "R", "bin", "toolchain", "usr", "bin", "make")):
        die(f"no GNU make in the toolchain tree {tc_prefix} — run `pixi run -e minimal toolchain` first")
    if args.build_tag and not args.build_tag[0].isdigit():
        die("--build-tag must start with a digit (PEP 427)")

    base = f"{IMPORT_NAME}/R/"
    tree = collect_tree(prefix)
    print(f"make-wheel: {len(tree)} files from {prefix}")
    tc_tree = [(rel, path) for rel, path in collect_tree(tc_prefix) if rel.startswith(TOOLCHAIN_USR)]
    print(f"make-wheel: {len(tc_tree)} files from {tc_prefix}/{TOOLCHAIN_USR}")
    files: list[tuple[str, bytes]] = []  # (path inside the trees, content)
    modes: dict[str, int] = {}
    for rel, path in tree + tc_tree:
        if os.path.islink(path):
            print(f"make-wheel: note: dereferencing symlink {rel} (wheels cannot hold symlinks)")
        with open(path, "rb") as f:
            files.append((rel, f.read()))
        modes[rel] = stat.S_IMODE(os.stat(path).st_mode)

    # The R tree's R_HOME/bin/toolchain holds rzig only, under each of its
    # names (feat-standalone-toolchain B19, B30), and on linux rzig's link
    # object, dso_fini.o (rzig's build.zig, linkObject;
    # feat-r-home-link-objects): anything else there is a leftover of an
    # older build, since zig's install never removes a file, and would
    # ship in r-zig (a usr/ there, beside the toolchain tree's in
    # r-zig-build-tools). The R tree's files come first in `files`.
    rzig = dict(files)[TOOLCHAIN_PREFIX + "zig-cc"]
    link_object = TOOLCHAIN_PREFIX + "dso_fini.o" if platform.system() == "Linux" else None
    if link_object and link_object not in dict(files[:len(tree)]):
        die(f"{prefix} has no R_HOME/bin/toolchain/dso_fini.o, rzig's link object — run `pixi run -e minimal build` first")
    stray = [r for r, d in files[:len(tree)] if r.startswith(TOOLCHAIN_PREFIX) and d != rzig and r != link_object]
    if stray:
        die(f"not rzig in {prefix}'s R_HOME/bin/toolchain: {', '.join(stray)} — remove {prefix} and run `pixi run -e minimal build` again")

    needles = [ROOT.encode()]
    if os.environ.get("CONDA_PREFIX"):
        needles.append(os.environ["CONDA_PREFIX"].encode())
    leak_scan(files, needles)

    renv = "lib/R/etc/Renviron.site"
    existing = dict(files).get(renv)
    files = [(r, d) for r, d in files if r != renv] + [(renv, renviron_site(existing))]
    modes.setdefault(renv, 0o644)

    # r-zig-build-tools' files: the toolchain tree's usr/. Everything else,
    # rzig under each of its names included, is r-zig's (B19, B29 a).
    bt_files = [(r, d) for r, d in files if r.startswith(TOOLCHAIN_USR)]
    files = [(r, d) for r, d in files if not r.startswith(TOOLCHAIN_USR)]
    make_copying = dict(bt_files).get(TOOLCHAIN_USR + "LICENSES/make/COPYING")
    if make_copying is None:
        die(f"no {TOOLCHAIN_USR}LICENSES/make/COPYING in {tc_prefix} — run `pixi run -e minimal toolchain` first")

    tags = platform_tags(files + bt_files)
    build = f"-{args.build_tag}" if args.build_tag else ""

    pkg_dir = os.path.join(ROOT, "python", IMPORT_NAME)
    entries: list[tuple[str, bytes, int]] = []
    for name in sorted(os.listdir(pkg_dir)):
        if name.endswith(".py"):
            with open(os.path.join(pkg_dir, name), "rb") as f:
                src = f.read().replace(b"@R_VERSION@", r_version.encode()).replace(b"@WHEEL_VERSION@", args.version.encode())
            entries.append((f"{IMPORT_NAME}/{name}", src, 0o644))
    entries += [(base + rel, data, modes[rel]) for rel, data in sorted(files)]

    with open(os.path.join(prefix, "lib", "R", "COPYING"), "rb") as f:
        copying = f.read()
    # r-zig's licences: R's COPYING, and the tree's records, SOURCES and
    # each vendored package's texts, at their place under share/licenses
    # (B33 a; PHASE8 open point E a). No License-File lines: METADATA is
    # version 2.1, and License-File is 2.4's.
    records = [(rel[len("share/licenses/"):], data) for rel, data in files if rel.startswith("share/licenses/")]
    entry_points = f"[console_scripts]\nR = {IMPORT_NAME}:main\nRscript = {IMPORT_NAME}:main_rscript\n"
    write_wheel(args, DIST_NAME, tags, build, entries, metadata(DIST_NAME, args.version, r_version), entry_points,
                [("COPYING", copying)] + records)

    # the build tools under make's licence, and two wheels of
    # requirements alone (E a; B29 a)
    bt_entries = [(base + rel, data, modes[rel]) for rel, data in sorted(bt_files)]
    write_wheel(args, BUILD_TOOLS_DIST, tags, build, bt_entries,
                metadata(BUILD_TOOLS_DIST, args.version, r_version), None, [("COPYING", make_copying)])
    for dist in (COMPILERS_DIST, TOOLCHAIN_DIST):
        write_wheel(args, dist, tags, build, [], metadata(dist, args.version, r_version), None, [("COPYING", copying)])


def write_wheel(args: argparse.Namespace, dist: str, tags: list[str], build: str,
                entries: list[tuple[str, bytes, int]], meta: str,
                entry_points: str | None, licenses: list[tuple[str, bytes]]) -> None:
    """Write dist's wheel; `licenses` are its dist-info licences, (path
    under licenses/, content). No entries: a wheel of its .dist-info
    alone."""
    name = dist.replace("-", "_")  # the wheel file's and the dist-info's name (PEP 427)
    plat = ".".join(tags)
    dist_info = f"{name}-{args.version}.dist-info"
    wheel_name = f"{name}-{args.version}{build}-py3-none-{plat}.whl"
    wheel_meta = "Wheel-Version: 1.0\nGenerator: r-zig-pixi scripts/make-wheel.py\nRoot-Is-Purelib: false\n"
    wheel_meta += "".join(f"Tag: py3-none-{t}\n" for t in tags)
    if args.build_tag:
        wheel_meta += f"Build: {args.build_tag}\n"
    entries = entries + [
        (f"{dist_info}/METADATA", meta.encode(), 0o644),
        (f"{dist_info}/WHEEL", wheel_meta.encode(), 0o644),
    ] + [(f"{dist_info}/licenses/{rel}", data, 0o644) for rel, data in licenses]
    if entry_points:
        entries.append((f"{dist_info}/entry_points.txt", entry_points.encode(), 0o644))

    # Reproducible when SOURCE_DATE_EPOCH is set (as build.zig honours it).
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", time.time()))
    date_time = time.gmtime(max(epoch, 315532800))[:6]  # zip can't go before 1980

    os.makedirs(args.out_dir, exist_ok=True)
    out = os.path.join(args.out_dir, wheel_name)
    record = io.StringIO()
    writer = csv.writer(record, lineterminator="\n")
    with zipfile.ZipFile(out + ".part", "w") as zf:
        for arcname, data, mode in entries:
            info = zipfile.ZipInfo(arcname, date_time)
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, data, compresslevel=9)
            writer.writerow([arcname, record_hash(data), len(data)])
        writer.writerow([f"{dist_info}/RECORD", "", ""])
        info = zipfile.ZipInfo(f"{dist_info}/RECORD", date_time)
        info.external_attr = (stat.S_IFREG | 0o644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, record.getvalue())
    os.replace(out + ".part", out)

    size = os.path.getsize(out)
    raw = sum(len(d) for _, d, _ in entries)
    print(f"make-wheel: wrote {out}")
    print(f"make-wheel: {len(entries)} files, {raw / 2**20:.1f} MiB unpacked, {size / 2**20:.1f} MiB wheel")
    if size > 100 * 2**20:
        print("make-wheel: warning: over PyPI's default 100 MiB per-file limit")

if __name__ == "__main__":
    main()
