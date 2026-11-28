# r-zig binary package repository (linux)

A CRAN-like repository of R packages compiled by r-zig, for linux-64 and
linux-aarch64: `install.packages()` gets binaries, so an R with no
compilers (`r-zig-slim` alone, the standalone archive, the wheel)
installs them in seconds. It holds a curated set, `packages.tsv`, and
their hard dependencies; anything else comes from CRAN as source.
Design: `.github/devdocs/b13-design/PLAN.md` (L5); this implementation:
`.github/devdocs/b14-l5/PLAN.md`.

**Experimental.** Every choice here (the layout and URL, the ABI key,
the builder, the bundled libraries, the publish workflow) is to be
reviewed again in a later build (the user's decision U3, 2026-11-26).
Expect the URL or the key to change.

## Use it

Put the repository before CRAN. In R, or in `~/.Rprofile`:

```r
local({
  key <- sprintf("linux-%s-rzig1", R.version$arch)   # rzig1: the ABI epoch
  rxy <- sub("^([0-9]+\\.[0-9]+).*", "\\1", getRversion())
  options(repos = c(
    RZIG = sprintf("https://github.com/luciorq/r-zig-pixi/releases/download/repo/%s/%s", key, rxy),
    CRAN = "https://cloud.r-project.org"))
})
install.packages("data.table")
```

- The packages install as `type = "source"` (R on linux has no binary
  type); R CMD INSTALL sees that they are built and copies them, with no
  compiler. A package or version the repository does not have comes from
  CRAN as source and compiles (r-zig-toolchain then is needed). When CRAN
  has a newer version than the repository, R takes CRAN's.
- Libraries outside R: a binary carries the shared libraries it links
  that R does not load itself, in `<pkg>/libs/` beside its .so (xml2:
  libxml2.so.16 and ICU's libicuuc/libicudata; data.table: libomp.so),
  and finds them through its only rpath, `$ORIGIN`. So it loads with no
  environment variable and no extra conda package in R from any conda
  env, in the r-zig wheel's R in a plain venv, and in R embedded in a
  Python from outside any env (ctypes, as rpy2 does), also on a host
  without those libraries (b14-l5 F24-F28, F38). Where a library of that name is
  already in the process (libomp in an R with OpenMP; another package's
  libxml2), the loader uses that one, so there is never a second copy.
  PACKAGES' `RZig-Bundled` lists them with their conda packages;
  `<pkg>/rzig-bundled/SOURCES` and `LICENSES/` record where each comes
  from and its licence.
- The r-zig wheel's R creates its per-user library (`R_LIBS_USER`:
  `$XDG_DATA_HOME`, else `~/.local/share`, then
  `R/<platform>-zig/<x.y>`, e.g. `R/linux-64-zig/4.6` or
  `R/linux-aarch64-zig/4.6`; r-zig's patch 0001) at its first start, so
  `install.packages()` installs there and every later session finds the
  packages. rpy2 installs and finds the wheel's R with no setup, also
  from a venv that is not activated, in two commands: `pip install
  r-zig`, then `pip install rpy2`, wherever rpy2 would find no other R.
  The wheel's `site-packages/r_zig.pth` acts on two imports only, and
  only when `R_HOME` is unset (or is the wheel's R) and the first `R` on
  `PATH` is missing or an r-zig `R` (b14-l5 D25-D27):
  - setuptools imported in an rpy2 source tree (pip builds
    rpy2-rinterface from source on linux: PyPI has no linux wheel of it):
    unless `RPY2_CFFI_MODE` is set, `RPY2_CFFI_MODE=ABI`, so the build
    needs no R and no compiler and gives a pure-Python wheel;
  - rpy2 imported: `R_HOME` is the wheel's R and `RPY2_CFFI_MODE`
    defaults to `ABI`, so rpy2 opens the wheel's libR even with a
    compiled module from elsewhere.

  With another R on `PATH` (a system R, a conda env's R) or `R_HOME` set
  to it, rpy2 builds and runs against that R as it does without r-zig
  (API mode where a compiler is present); activate the venv or set
  `R_HOME` to the wheel's R to choose the wheel's. A process that imports
  neither keeps its environment, so an R it starts never warns about
  `R_HOME`. Limits: `pip install r-zig rpy2` in one command works only
  once pip's cache holds rpy2-rinterface's wheel (pip builds rpy2 before
  it installs r-zig); front ends that build in their own new venv (uv,
  `pip --use-feature=venv-isolation`) need the venv activated, which
  puts the wheel's `R` on `PATH`; rpy2 on the wheel's R runs in ABI mode,
  and the ABI build has no `_bufferprotocol` module, so
  `memoryview()` of an R vector needs numpy; the ABI wheel stays in
  pip's cache and a later `pip install rpy2` on a host that has gained
  another R and a compiler reuses it (ABI there too) until
  `pip cache remove rpy2_rinterface`; an rpy2 checkout installed or
  built in that venv gets ABI mode too unless `RPY2_CFFI_MODE` is set.
  Tested on linux x86_64 only.
- Integrity: each binary's SHA256 is in PACKAGES, and each has a build
  provenance attestation: `gh attestation verify <file> -R luciorq/r-zig-pixi`.

## Layout and the ABI key

```
repo/linux-<arch>-rzig<abi>/<R x.y>/src/contrib/
    <pkg>_<version>.tar.gz   installed packages, tarred as R CMD INSTALL --build does
    PACKAGES PACKAGES.gz PACKAGES.rds
```

`repo/linux-<arch>-rzig<abi>/<R x.y>` is the repository root, and with
`/src/contrib` the GitHub Release tag its files are assets of. The key
is what a binary is valid for: R's x.y, the platform, and r-zig's ABI
epoch (`abi` in build-repo.R), which bumps when binaries built before
cannot load or behave the same in a new r-zig build (libR's ABI, the C++
standard library, the OpenMP runtime, the glibc floor). The r-zig build
that made a binary is PACKAGES' `RZig-Build`; a new build with the same
epoch keeps the repository.

## Build it

The workflow `.github/workflows/repo.yaml` builds both platforms with a
published build, tests each, and uploads to the releases only behind
its publish gate (its header). By hand, on linux:

```bash
pixi exec -c https://prefix.dev/universe -c conda-forge \
  -s 'r-zig-slim==4.6.2=*_14' -s 'r-zig-toolchain==4.6.2=*_14' -s libxml2-devel -- \
  Rscript repo/build-repo.R out
pixi exec -c https://prefix.dev/universe -c conda-forge \
  -s 'r-zig-slim==4.6.2=*_14' -- \
  Rscript repo/install-test.R out/repo/linux-x86_64-rzig1/4.6 out/test-lib
```

`build-repo.R` builds with `R_ZIG_ENV_RPATH=origin`, so the binaries
carry no rpath into the build env, only `$ORIGIN` (rzig honours it from
build 14; with an earlier build every compiled package fails its rpath
check), then copies the libraries they need from the build env's lib/
into each package. It writes `out/build.tsv` (seconds, size, result per
package) and `out/logs/`.

Add a package: a row in `packages.tsv` with a smoke expression; if it
links a library outside R's env, its `-devel` package in the workflow's
build specs (the builder bundles the run-time library). Prefer a
package's bundled static copy where it has one (the `env` column, as
fs's `USE_BUNDLED_LIBUV=1`): the binary is then smaller.

Rebuild when CRAN has a new version of a package, when a LinkingTo
dependency changes (Rcpp, cpp11: their headers are compiled in), when a
bundled library's SONAME changes in conda-forge (or it has a security
fix), or after an epoch bump (a
new repository) or a new R x.y (a new path).
