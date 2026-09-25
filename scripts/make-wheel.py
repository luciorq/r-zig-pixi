#!/usr/bin/env python3
"""Assemble the r-zig wheel from the minimal variant's standalone tree.

Input is what `pixi run -e minimal package` leaves in
dist/R-<ver>-minimal-zig: staged by stage.sh (location-independent
launchers, $ORIGIN/@loader_path rpaths, zig shims + GNU make in
lib/R/bin/toolchain) and made standalone by package-standalone.sh (conda
libraries vendored into lib/, build-env flags stripped from Makeconf).
That tree already runs from anywhere, so the wheel is that tree under
`r_zig/R/` plus the small `r_zig` Python package (python/r_zig/), console
scripts `R`/`Rscript`, and a dependency on PyPI `ziglang` as the compiler
for install.packages(). No build backend: a wheel is a zip with a
.dist-info directory (PEP 427), written here with the stdlib only.

The platform tag is computed from the binaries, not assumed: on Linux the
highest GLIBC_x.y symbol version any ELF file references (manylinux_x_y;
the zig build targets 2.17, which is also manylinux2014), on macOS the
highest LC_BUILD_VERSION/LC_VERSION_MIN_MACOSX minimum any Mach-O file
declares. Python-independent (`py3-none`): nothing here links libpython.

Usage (from the `wheel` pixi env, which sets R_VERSION/R_BUILD_VARIANT):
    pixi run -e wheel wheel [--prefix DIR] [--out-dir DIR] [--build-tag N]
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
    wheel on any other machine. Anything else (a recorded source path in
    tools/misc/top.txt, strings in binaries) is reported, not fatal.
    """
    fatal, other = [], []
    for rel, data in files:
        if not any(n in data for n in needles):
            continue
        runtime = b"\0" not in data[:8192] and rel.startswith(("lib/R/etc/", "bin/", "lib/R/bin/"))
        # Comment lines don't count: Makeconf's header records the whole
        # configure command line, build paths included, and nothing reads it.
        if runtime and any(
            any(n in line for n in needles)
            for line in data.splitlines()
            if not line.lstrip().startswith(b"#")
        ):
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
    # ziglang lives elsewhere this names a missing file and the zig shims
    # fall back to PATH, then `python3 -m ziglang`.
    add = (
        "## r-zig wheel: compile packages with the PyPI ziglang package\n"
        "## installed next to this one (see r_zig/__init__.py).\n"
        "R_ZIG_ZIGLANG=${R_HOME}/../../../../ziglang/zig\n"
        "ZIG_BIN=${ZIG_BIN-${R_ZIG_ZIGLANG}}\n"
    ).encode()
    return (existing.rstrip(b"\n") + b"\n\n" + add) if existing else add


def metadata(version: str, r_version: str) -> str:
    description = f"""\
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

`install.packages()` compiles C/C++ packages with the PyPI
[`ziglang`](https://pypi.org/project/ziglang/) package (a dependency), and
GNU make is bundled, so no system compiler is needed. Packages with Fortran
sources need a Fortran compiler, which neither this wheel nor ziglang
provides.

The minimal profile has no cairo/png/svg devices (`pdf()` and
`postscript()` work), no ICU (collation uses the C library), no OpenMP
(nothing to clash with the OpenMP runtimes other wheels load), no
X11/tcltk/readline/NLS, and R's internal reference BLAS/LAPACK. Linux
wheels need glibc 2.17 or newer.
"""
    return (
        "Metadata-Version: 2.1\n"
        f"Name: {DIST_NAME}\n"
        f"Version: {version}\n"
        f"Summary: R {r_version} built with zig (minimal profile), relocatable, with ziglang as its compiler\n"
        "Home-page: https://github.com/luciorq/r-zig-pixi\n"
        "License: GPL-2.0-only OR GPL-3.0-only\n"
        "Classifier: Programming Language :: R\n"
        "Classifier: License :: OSI Approved :: GNU General Public License v2 (GPLv2)\n"
        "Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)\n"
        "Classifier: Operating System :: POSIX :: Linux\n"
        "Classifier: Operating System :: MacOS\n"
        "Requires-Python: >=3.8\n"
        f"Requires-Dist: {ZIGLANG_REQUIREMENT}\n"
        "Description-Content-Type: text/markdown\n"
        "\n" + description
    )


def record_hash(data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    return f"sha256={digest}"


def main() -> None:
    r_version = os.environ.get("R_VERSION") or die("R_VERSION not set — run through `pixi run -e wheel wheel`")
    variant = os.environ.get("R_BUILD_VARIANT", "slim")

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--prefix", default=os.path.join(ROOT, "dist", f"R-{r_version}-{variant}-zig"),
                    help="staged + packaged R tree (default: %(default)s)")
    ap.add_argument("--out-dir", default=os.path.join(ROOT, "dist", "wheel"))
    ap.add_argument("--version", default=r_version, help="wheel version (default: the R version)")
    ap.add_argument("--build-tag", default="", help="wheel build tag, e.g. 1 (PEP 427)")
    ap.add_argument("--any-variant", action="store_true",
                    help="allow a non-minimal tree (it would carry OpenMP and the whole graphics stack)")
    args = ap.parse_args()

    prefix = os.path.abspath(args.prefix)
    if variant != "minimal" and not args.any_variant:
        die(f"R_BUILD_VARIANT is {variant!r}; the wheel wraps the minimal variant (--any-variant to override)")
    if not os.path.isfile(os.path.join(prefix, "lib", "R", "bin", "exec", "R")):
        die(f"no R build at {prefix} — run `pixi run -e minimal package` first")
    if not os.path.isfile(os.path.join(prefix, "lib", "R", "bin", "toolchain", "zig-cc")):
        die(f"{prefix} is not staged — run `pixi run -e minimal package` (stage.sh) first")
    if not any(re.search(r"\.(so(\.\d+)*|dylib)$", f) for f in os.listdir(os.path.join(prefix, "lib"))):
        die(f"no vendored libraries in {prefix}/lib — run `pixi run -e minimal package` first")
    if args.build_tag and not args.build_tag[0].isdigit():
        die("--build-tag must start with a digit (PEP 427)")

    base = f"{IMPORT_NAME}/R/"
    tree = collect_tree(prefix)
    print(f"make-wheel: {len(tree)} files from {prefix}")
    files: list[tuple[str, bytes]] = []  # (path inside prefix, content)
    modes: dict[str, int] = {}
    for rel, path in tree:
        if os.path.islink(path):
            print(f"make-wheel: note: dereferencing symlink {rel} (wheels cannot hold symlinks)")
        with open(path, "rb") as f:
            files.append((rel, f.read()))
        modes[rel] = stat.S_IMODE(os.stat(path).st_mode)

    needles = [ROOT.encode()]
    if os.environ.get("CONDA_PREFIX"):
        needles.append(os.environ["CONDA_PREFIX"].encode())
    leak_scan(files, needles)

    renv = "lib/R/etc/Renviron.site"
    existing = dict(files).get(renv)
    files = [(r, d) for r, d in files if r != renv] + [(renv, renviron_site(existing))]
    modes.setdefault(renv, 0o644)

    tags = platform_tags(files)
    plat = ".".join(tags)
    build = f"-{args.build_tag}" if args.build_tag else ""
    dist_info = f"{IMPORT_NAME}-{args.version}.dist-info"
    wheel_name = f"{IMPORT_NAME}-{args.version}{build}-py3-none-{plat}.whl"

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
    wheel_meta = "Wheel-Version: 1.0\nGenerator: r-zig-pixi scripts/make-wheel.py\nRoot-Is-Purelib: false\n"
    wheel_meta += "".join(f"Tag: py3-none-{t}\n" for t in tags)
    if args.build_tag:
        wheel_meta += f"Build: {args.build_tag}\n"
    entries += [
        (f"{dist_info}/METADATA", metadata(args.version, r_version).encode(), 0o644),
        (f"{dist_info}/WHEEL", wheel_meta.encode(), 0o644),
        (f"{dist_info}/entry_points.txt",
         f"[console_scripts]\nR = {IMPORT_NAME}:main\nRscript = {IMPORT_NAME}:main_rscript\n".encode(), 0o644),
        (f"{dist_info}/licenses/COPYING", copying, 0o644),
    ]

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
