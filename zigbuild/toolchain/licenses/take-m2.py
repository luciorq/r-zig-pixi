#!/usr/bin/env python3
"""The m2 packages' licence texts, taken as README.md here says, for the
builds pixi.lock has (chore-review-consistency F21). Not part of any
build: run it by hand after a re-lock moved an m2 package, read the diff.

  python3 zigbuild/toolchain/licenses/take-m2.py pixi.lock <work dir> \\
      zigbuild/toolchain/licenses [m2-<name> ...]

For each package of FILES below: its .conda from the lock's URL, the
`.src.tar.zst` its rendered_recipe.yaml names (MSYS2's, else
conda-forge's mirror), checked against the recipe's sha256, and from the
upstream tarball inside it (m2-msys2-runtime: the archive's git clone, at
the PKGBUILD's tag) the files listed. Writes <out>/<package>/ with the
files, VERSION and ORIGIN; an ORIGIN that is there keeps its `note:`
lines. Downloads stay in <work dir> (gcc's source is about 100 MB).
Needs python3 with PyYAML, zstd, tar and git. It runs nothing that it
downloads."""
import hashlib, io, json, os, re, subprocess, sys, tarfile, urllib.request, zipfile

FILES = {
    "m2-bash": ["COPYING"], "m2-make": ["COPYING"], "m2-coreutils": ["COPYING"],
    "m2-sed": ["COPYING"], "m2-grep": ["COPYING"], "m2-gawk": ["COPYING"],
    "m2-which": ["COPYING"], "m2-findutils": ["COPYING"], "m2-patch": ["COPYING"],
    "m2-tar": ["COPYING"], "m2-gzip": ["COPYING"],
    "m2-msys2-runtime": ["winsup/CYGWIN_LICENSE", "winsup/COPYING", "winsup/COPYING.LIB",
                         "COPYING.NEWLIB", "COPYING.LIBGLOSS"],
    "m2-libintl": ["gettext-runtime/intl/COPYING.LIB", "COPYING"],
    "m2-libiconv": ["COPYING.LIB", "COPYING"],
    "m2-libpcre": ["LICENCE"],
    "m2-gmp": ["COPYING.LESSERv3", "COPYINGv2", "COPYINGv3", "COPYING"],
    "m2-mpfr": ["COPYING.LESSER", "COPYING"],
    "m2-libreadline": ["COPYING"],
    "m2-ncurses": ["COPYING"],
    "m2-gcc-libs": ["COPYING.RUNTIME", "COPYING3.LIB", "COPYING3", "COPYING.LIB", "COPYING"],
}

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def fetch(urls, dest, want=None):
    if os.path.exists(dest) and (want is None or sha256(dest) == want):
        return urls[0]
    last = None
    for u in urls:
        try:
            req = urllib.request.Request(u, headers={"User-Agent": "curl/8"})
            with urllib.request.urlopen(req, timeout=300) as r, open(dest + ".part", "wb") as f:
                for b in iter(lambda: r.read(1 << 20), b""):
                    f.write(b)
            os.replace(dest + ".part", dest)
            if want is not None and sha256(dest) != want:
                raise RuntimeError(f"{u}: sha256 {sha256(dest)}, not {want}")
            return u
        except Exception as e:  # try the mirror
            last = e
            print(f"   {u}: {e}", file=sys.stderr)
    raise RuntimeError(f"no source for {dest}: {last}")

def conda_info(conda_path):
    """index.json and rendered_recipe.yaml text of a .conda file."""
    z = zipfile.ZipFile(conda_path)
    name = [n for n in z.namelist() if n.startswith("info-") and n.endswith(".tar.zst")][0]
    raw = subprocess.run(["zstd", "-dc"], input=z.read(name), stdout=subprocess.PIPE, check=True).stdout
    t = tarfile.open(fileobj=io.BytesIO(raw))
    index = json.load(t.extractfile("info/index.json"))
    recipe = t.extractfile("info/recipe/rendered_recipe.yaml").read().decode()
    lic = [m.name for m in t.getmembers() if m.name.startswith("info/licenses/") and m.isfile()]
    return index, recipe, lic

def sources(recipe_text):
    """finalized_sources: [(urls, sha256)]."""
    import yaml
    out = []
    for e in yaml.safe_load(recipe_text)["finalized_sources"]:
        u = e["url"]
        out.append(([u] if isinstance(u, str) else list(u), e["sha256"]))
    return out

def main():
    lock, work, outdir = sys.argv[1:4]
    only = sys.argv[4:]
    locktext = open(lock).read()
    for pkg, files in FILES.items():
        if only and pkg not in only:
            continue
        m = re.search(r"https://conda\.anaconda\.org/conda-forge/noarch/(" + re.escape(pkg) + r"-[^/\s]*\.conda)", locktext)
        if not m:
            raise SystemExit(f"{pkg}: not in {lock}")
        conda_url = m.group(0)
        w = os.path.join(work, pkg); os.makedirs(w, exist_ok=True)
        conda_path = os.path.join(w, "pkg.conda")
        fetch([conda_url.replace("!", "%21")], conda_path)
        index, recipe, shipped = conda_info(conda_path)
        version, build, license_ = index["version"], index["build"], index["license"]
        srcs = [s for s in sources(recipe) if any(".src.tar" in u for u in s[0])]
        if len(srcs) != 1:
            raise SystemExit(f"{pkg}: {len(srcs)} source archives in its recipe")
        urls, want = srcs[0]
        src_path = os.path.join(w, os.path.basename(urls[0]))
        fetch(urls, src_path, want)
        ex = os.path.join(w, "src"); os.makedirs(ex, exist_ok=True)
        if not os.listdir(ex):
            p1 = subprocess.Popen(["zstd", "-dc", src_path], stdout=subprocess.PIPE)
            subprocess.run(["tar", "-x", "--no-same-owner", "-C", ex], stdin=p1.stdout, check=True)
            if p1.wait() != 0:
                raise SystemExit(f"{pkg}: zstd failed")
        top = os.listdir(ex)
        if len(top) != 1:
            raise SystemExit(f"{pkg}: {top} at the archive's top")
        base = os.path.join(ex, top[0])
        dest = os.path.join(outdir, pkg)
        lines = [f"package: {pkg} {version} {build}", f"license: {license_} (conda-meta)",
                 f"source: {urls[0]} sha256:{want}", f"mirror: {urls[1]}" if len(urls) > 1 else None]
        lines = [l for l in lines if l]
        if pkg == "m2-msys2-runtime":
            gd = os.path.join(base, "msys2-runtime")
            pk = open(os.path.join(base, "PKGBUILD")).read()
            pv = re.search(r"^pkgver=(\S+)", pk, re.M).group(1)
            tag = f"cygwin-{pv}"
            commit = subprocess.run(["git", "--git-dir", gd, "rev-parse", f"{tag}^{{commit}}"], stdout=subprocess.PIPE, check=True, text=True).stdout.strip()
            got = {}
            for f in files:
                got[f] = subprocess.run(["git", "--git-dir", gd, "show", f"{tag}:{f}"], stdout=subprocess.PIPE, check=True).stdout
            where = lambda f: f"{top[0]}/msys2-runtime (git, tag {tag}, {commit}):{f}"
        else:
            tarballs = [f for f in os.listdir(base) if re.search(r"\.(tar\.(gz|xz|bz2|lz|zst)|tgz)$", f)]
            if len(tarballs) != 1:
                raise SystemExit(f"{pkg}: upstream tarballs {tarballs} in {base}")
            tb = os.path.join(base, tarballs[0])
            names = subprocess.run(["tar", "-tf", tb], stdout=subprocess.PIPE, check=True, text=True).stdout.split("\n")
            tdir = names[0].split("/")[0]
            got = {}
            for f in files:
                member = f"{tdir}/{f}"
                if member not in names:
                    raise SystemExit(f"{pkg}: no {member} in {tarballs[0]}")
                got[f] = subprocess.run(["tar", "-xOf", tb, member], stdout=subprocess.PIPE, check=True).stdout
                if len(got[f]) < 200:
                    raise SystemExit(f"{pkg}: {member} is {len(got[f])} bytes (a link?)")
            where = lambda f: f"{top[0]}/{tarballs[0]}:{tdir}/{f}"
        # the old directory's notes stay (they are about the software, not the build)
        notes = []
        old = os.path.join(dest, "ORIGIN")
        if os.path.exists(old):
            notes = [l.rstrip("\n") for l in open(old) if l.startswith("note:")]
        for f in files:
            p = os.path.join(dest, f); os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(got[f])
            lines.append(f"file: {f} {hashlib.sha256(got[f]).hexdigest()} <- {where(f)}")
        lines += notes
        open(os.path.join(dest, "VERSION"), "w").write(f"{version} {build}\n")
        open(os.path.join(dest, "ORIGIN"), "w").write("\n".join(lines) + "\n")
        print(f"{pkg} {version} {build}: {len(files)} file(s); the package ships {shipped}")

main()
