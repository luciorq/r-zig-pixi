# r-zig-pixi

R, built as a conda package with the [Zig](https://ziglang.org) toolchain
(`zig cc`/`zig c++` in place of a system compiler) and driven end-to-end
through [pixi](https://pixi.sh). One dependency graph — pixi resolves
everything from conda-forge, Zig included — instead of a system compiler
toolchain plus a separate build system.

## Use cases

### Install R from the built conda packages

The packages target `linux-64`, `linux-aarch64`, `osx-64`, `osx-arm64`
and `win-64`, and are published to the `universe` channel on prefix.dev.
The channel is public: adding it is all it takes, with no login.
Publishing is paused until the next build-number bump: until then
universe has build 8's two packages, `r-zig-slim` and `r-zig-toolchain`
(which brings the compilers and build tools), and not yet
`r-zig-compilers` or `r-zig-build-tools`.

```bash
pixi init my-r-project
cd my-r-project
pixi workspace channel add https://prefix.dev/universe
pixi add r-zig-slim
pixi run Rscript -e 'R.version.string'
```

`r-zig-slim` is R alone: it runs R and installs packages that need no
compiling (R-only source packages and binary packages). On Windows it has
full's content (Tcl/Tk, JPEG, TIFF, NLS): R's Windows build has no
switches to leave them out. It carries rzig, the compiler front R's
Makeconf names; the compilers and the build tools are two groups, each a
package that pins the exact `r-zig-slim` build. To compile packages, add
r-zig-toolchain (r-zig-compilers and r-zig-build-tools):

```bash
pixi add r-zig-toolchain
```

- `r-zig-compilers` (zig 0.16, LLVM flang, OpenMP) alone installs
  packages that have no configure script and whose Makevars only sets
  variables. It also compiles such code at run time (`R CMD SHLIB`:
  Rcpp's `sourceCpp()`, inline, TMB, knitr's engines) with no make: R
  builds both with `rzig build`. Once pkgbuild or pak is installed,
  their compiler check passes too.
- `r-zig-build-tools` (make; on Windows also sh, the MSYS2 tools,
  pkg-config and the MinGW binutils) is for configure scripts, Makevars
  rules, Objective-C and `R CMD config` (rstan on macOS calls it).
  Installing pkgbuild, pak, devtools or the packages cpp11's
  `cpp_source()` requires from source needs it once: processx has
  Makevars rules, and ps and pak have configure scripts.
  r-zig-toolchain has both groups from the start.

Without a group, an install that needs it stops with a message naming the
package to add. In an environment used without activation (an IDE
pointed at `<env>/bin/R`), the build tools are not on `PATH`: activate
the environment (`pixi shell`, `conda activate`) or start R with
`pixi run`.

- If pak or pkgbuild says it could not find the tools, run
  `pkgbuild::check_build_tools(debug = TRUE)`: rzig's text names what to
  install. A pak session that checked before r-zig-compilers was
  installed keeps its answer: restart R.
- pak checks for a compiler before every source package, R-only ones
  too, so with `r-zig-slim` alone it installs no source package:
  `install.packages()` does.
- On Windows, Rtools is not needed: r-zig's build tools take its place.
  pkgbuild's "Rtools is required" warning, printed by
  `with_build_tools()` callers such as devtools, can be ignored.
- A TMB installed by an earlier r-zig build (universe's build 8 or before)
  keeps make, as it keeps a copy of R's own SHLIB code: reinstall it.
  TMB's `precompile()` speeds up only the recompiles of one model name:
  each new name compiles the precompiled library again (about 45 s on
  linux-64) and keeps one more object (about 4 MB) in zig's cache. Where
  the build tools are installed, `R_ZIG_PKG_BUILDER=make` restores make's
  reuse. TMB 1.9.25's default `precompile()` does not compile, with GCC as
  with zig; `precompile(all = FALSE)` does.

`R_ZIG_PKG_BUILDER=make` sends every `R CMD INSTALL` and `R CMD SHLIB`
to make (the build tools then are needed). Details:
`.github/devdocs/feat-shlib-rzig-build/PLAN.md`.

### Build the conda packages yourself

```bash
pixi run -e pkg conda-package
pixi run -e pkg conda-consume
```

`conda-package` produces the four packages,
`dist/conda/<platform>/r-zig-slim-*.conda`, `r-zig-compilers-*.conda`,
`r-zig-build-tools-*.conda` and `r-zig-toolchain-*.conda`, via
`rattler-build`, using this repo's own recipe (`recipe/recipe.yaml`), and
tests each one in a fresh environment of its own. Useful for testing a
change to the build before publishing, or for producing a package for a
platform not published upstream. Each run empties `dist/conda` first, so
the previous run's packages do not survive it. `conda-consume` then
installs them as a user does: a fresh pixi workspace from `dist/conda`,
with `r-zig-slim` alone and with each group in an environment of its
own, where it runs the recipe's tests through pixi's activation. CI runs
both on every `conda-package` leg, before the publish.

### Publish to your own channel

```bash
pixi run -e pkg conda-publish
```

Uploads the just-built packages for the current platform via
`rattler-build upload`. Each platform has its own task
(`[feature.pkg.target.<platform>.tasks]` in `pixi.toml`), so this is
typically run once per machine/OS as part of a release.

### Run R from source without packaging

For iterating on the build itself rather than consuming a package:

```bash
pixi run build         # zig build, no autoconf/make/gnuwin32
pixi run verify-tree   # static checks of the installed tree (Makeconf, rpaths, floors)
pixi run smoke         # quick sanity check
pixi run check         # R's own regression suite
pixi run toolchain     # the toolchain tree: the groups' files (OpenMP headers, make; Windows binutils)
pixi run contract      # CRAN packages compiled with the tree and the groups (Rcpp, data.table, minqa)
```

`build` installs `dist/<flavor>/R-<ver>-zig/`, the base that ships: R
and its libraries, with only rzig, the compiler front Makeconf names, in
`R_HOME/bin/toolchain`. `toolchain` copies the toolchain groups' files
from the environment into `dist/toolchain/R-<ver>-zig/`, each directory
with its `SOURCES` (package, version, sha256, where its source is) and
`LICENSES/`; one toolchain tree serves every flavor of the platform.
`contract` compiles packages in a copy of the installed tree with the
groups added, `build/compile-tree/<flavor>/R-<ver>-zig/`, as a user who
extracted all three archives has it (see Standalone archives). The
archives and their checks:

```bash
pixi run package-toolchain   # the two group archives (runs toolchain first)
pixi run verify-toolchain    # static checks of the toolchain tree (records, copies, closures)
pixi run verify-package      # the base archive, then the three scenarios with the group archives
```

Three variants are available as pixi environments: `default` (slim —
headless, no X11/tcltk/NLS), `full` (adds tcltk, readline, NLS, jpeg
and tiff devices), and `minimal` (smaller than slim: also no cairo/png,
ICU, OpenMP or libdeflate; linux/macOS only). `minimal` is the variant
the Python wheel wraps.

### Build with upstream zig

The environment's zig is conda-forge's build. R builds just as well with
upstream zig (the [ziglang.org](https://ziglang.org/download/) release,
which the PyPI [`ziglang`](https://pypi.org/project/ziglang/) package
is), and the project keeps both working; upstream zig is the reference.
`pixi run fetch-zig` downloads PyPI's `ziglang` 0.16.0 wheel for this
platform once (checksum-pinned; a wheel is a zip, so no Python is
involved), unpacks it under `build/zig-upstream/` and prints its zig's
path. The tasks that run zig, `build`, `check`, `rzig-test`, the
toolchain tree's `toolchain` and `toolchain-test`, and the two that
compile packages with the built tree (`contract`, `verify-package`),
take it from `ZIG_BIN`; the other checks look at the trees it built:

```bash
export ZIG_BIN="$(pixi run fetch-zig)"   # PowerShell: $env:ZIG_BIN = pixi run fetch-zig
pixi run build && pixi run package-toolchain && pixi run verify-tree && pixi run smoke && pixi run contract && pixi run verify-package
```

The build prints the zig it uses (`r-zig: zig = ...`); unset `ZIG_BIN`
to go back to the environment's. Each zig keeps its own cache in
`build/zig-cache/`, so switching between them never mixes their objects.
The conda package (`pixi run -e pkg conda-package`) always builds with
its recipe's zig, conda-forge's: rattler-build gives the recipe a clean
environment, without `ZIG_BIN`. `wheel-test` always compiles with the
`ziglang` it installs into its venv, which is upstream zig already.

### Build R as Python wheels

```bash
pixi run -e minimal build              # the installed tree, libraries vendored
pixi run -e minimal verify-tree        # its static checks
pixi run -e minimal package-toolchain  # the toolchain tree and its two group archives
pixi run -e minimal verify-package     # archive the tree, check the archives relocated
pixi run -e wheel wheel                # -> dist/wheel/{r_zig,r_zig_compilers,r_zig_build_tools,r_zig_toolchain}-4.6.1-*.whl
pixi run -e wheel wheel-test           # pip-install them into fresh venvs, a group at a time, and use them
```

`wheel` takes GNU make for `r-zig-build-tools` from the toolchain tree,
so it needs `pixi run -e minimal toolchain` first (`package-toolchain`
runs it, and `verify-package` needs the group archives it makes).

The four wheels split as the conda packages do, for Linux and macOS (no
Windows wheels yet). `r-zig` (import name `r_zig`) is the whole
relocatable `minimal` tree, rzig included, plus console scripts
`R`/`Rscript` and `r_zig.r_home()` for embedders such as rpy2; it
installs packages that need no compiling. To compile packages, add
r-zig-toolchain (r-zig-compilers and r-zig-build-tools). r-zig-compilers
brings the PyPI [`ziglang`](https://pypi.org/project/ziglang/) package
as the C/C++ compiler, so no system compiler is needed; alone, it
installs packages that have no configure script and whose Makevars only
sets variables, and compiles such code at run time (`R CMD SHLIB`:
Rcpp's `sourceCpp()`, inline, TMB) with no make. r-zig-build-tools
brings GNU make, for the rest: configure scripts, Makevars rules,
Objective-C, `R CMD config`, and installing pkgbuild, pak or devtools
from source once. None of the four is on PyPI yet: install them from
`dist/wheel`, ziglang first, so that pip needs no index for the rest:

```bash
pip install 'ziglang>=0.16.0,<0.16.1'
pip install --no-index --find-links dist/wheel r-zig-toolchain
```

ziglang is an upstream zig build, which links its own libc++ statically,
so compiled C++ packages need no C++ runtime (with conda-forge's zig,
which would link conda's shared libc++, rzig keeps it static). Linux
wheels are `manylinux2014` (glibc 2.17). PyPI has no Fortran compiler,
and the wheels have no OpenMP: packages with Fortran sources need LLVM
`flang` on PATH, and R's FC, rzig's `zig-fc`, stops with a message when
there is none. pip leaves ziglang installed when the groups are
uninstalled, and rzig still finds it; uninstall ziglang too for R alone.
Details: `.github/devdocs/feat-wheel-minimal/PLAN.md`.

### Standalone archives

R also comes as plain archives that need nothing installed first: no
conda, pixi or Python. Three kinds, `.tar.gz` (Windows `.zip`), each with
a `.sha256` beside it:

- **The base**, one per flavor and platform:
  `R-<ver>-<flavor>-<platform>.tar.gz`, for example
  `R-4.6.1-slim-linux-64.tar.gz`. R alone, with its libraries: it runs R
  and installs packages that need no compiling. Its
  `R_HOME/bin/toolchain` holds only rzig, the compiler front R's
  Makeconf names. Windows slim has full's content (Tcl/Tk, JPEG, TIFF,
  NLS): R's Windows build has no switches to leave them out.
- **The compilers group**, one per platform:
  `R-<ver>-<platform>-compilers.tar.gz`. For now it holds OpenMP's
  headers (Windows also `libomp.lib`), which the `minimal` flavor, built
  without OpenMP, leaves alone; zig and flang join it later. Until then
  rzig takes zig 0.16 from `ZIG_BIN` or `PATH` (PyPI's `ziglang` works,
  also as `python3 -m ziglang`) and LLVM `flang` from `PATH`.
- **The build-tools group**, one per platform:
  `R-<ver>-<platform>-build-tools.tar.gz`. GNU make on linux and macOS,
  which R puts first on its `PATH`; on Windows the MinGW binutils R's
  Makeconf names (nm, dlltool, as, strip, windres, objdump), with sh and
  make still taken from `PATH` (for example Rtools45's `usr/bin`).

Every archive has the same top directory, `R-<ver>-zig/`, and a group
archive's files sit under its `R_HOME/bin/toolchain/`, each directory
with `SOURCES` (the conda-forge package each file comes from, its
sha256, and where the package's source is) and `LICENSES/`. Extract the
ones you need into one directory; no file is in two of them:

```bash
sha256sum -c R-4.6.1-slim-linux-64.tar.gz.sha256
tar -xzf R-4.6.1-slim-linux-64.tar.gz           # R-4.6.1-zig/
tar -xzf R-4.6.1-linux-64-compilers.tar.gz      # + R-4.6.1-zig/lib/R/bin/toolchain/openmp/
tar -xzf R-4.6.1-linux-64-build-tools.tar.gz    # + R-4.6.1-zig/lib/R/bin/toolchain/usr/bin/make
R-4.6.1-zig/bin/Rscript -e 'R.version.string'
```

On Windows, `tar -xf` extracts the `.zip` files the same way, and R is
`R-4.6.1-zig\Library\lib\R\bin\x64\Rscript.exe`. Use one directory per
flavor: the bases share the top directory, and the groups serve every
flavor of their platform. When a compile misses a group, rzig's message
says which archive to extract or what to put on `PATH`.

`pixi run package` makes the base archive of the environment's flavor
and `pixi run package-toolchain` the group archives, in `dist/`; CI keeps
both for a week (see CI). No release publishes them yet.

### Older Linux HPC servers

The Linux build targets glibc 2.17 by default (both the R build itself
and the package-compilation toolchain it ships), so binaries — and any
CRAN package compiled against them — run on considerably older
distributions than the build machine, without a separate build variant.

## CI

Everything runs on GitHub-hosted runners: `toolchain` (the toolchain
groups, once per platform), `build` (ubuntu-latest,
ubuntu-24.04-arm, macos-latest, macos-15-intel × slim/full, plus the
linux openblas variants, minimal on all four, and windows-latest's one
variant; the same steps in the same order on every OS, on the installed
tree, which is the tree the standalone base archive packs), and
`conda-package` for all
five subdirs (linux-64, linux-aarch64, osx-arm64, osx-64, win-64), which
publishes to the `universe` channel on prefix.dev via OIDC trusted
publishing on every push to `main` while the repository variable
`CONDA_PUBLISH` is `true` (paused from 2026-10-19 until the next
build-number bump merges, with feat-standalone-toolchain's phase 7).
There is no self-hosted fleet — the former gamma/omicron/kappa runners
were decommissioned in September 2026 and fully removed on 2026-09-24.
Docs-only changes (`*.md`, `.github/devdocs/`) skip the workflow.

The full matrix above runs only on request: on a pull request labelled
`full-ci` and on a manual dispatch (`pixi run ci-trigger` for main, `gh
workflow run build.yaml --ref <branch>` for a branch). Every other pull
request push and every push to `main` runs the core tier: `default` on
all five platforms and `minimal` on linux-64 (6 legs). `conda-package`
also runs on every push to `main`, which publishes (with
`CONDA_PUBLISH`), and on a pull
request that changes `recipe/`, `pixi.toml`, `pixi.lock`, `build.zig`,
`zigbuild/`, `scripts/` or the workflows. See
`.github/devdocs/chore-ci-tiers/PLAN.md`.

The build legs of both tiers wait for the `toolchain` job
(`.github/workflows/toolchain.yaml`), five legs, one per platform. Each
runs the toolchain build's unit tests (`toolchain-test`), makes the
toolchain tree and its two group archives (`package-toolchain`), checks
the tree (`verify-toolchain`) and uploads the archives as the artifact
`toolchain-<OS>-<arch>` (for example `toolchain-Linux-X64`). Every build
leg downloads its platform's archives first and unpacks them
(`unpack-toolchain`), so `contract` compiles in the compile tree. The
packaging legs (`default` on all five platforms, `minimal`) run
`verify-package`: the base archive, then the three scenarios with the
downloaded group archives (the base alone, with the compilers group,
with the build-tools group). They upload the base archive as
`standalone-<env>-<runner>` (for example `standalone-default-macos-latest`).
The base archives are kept for 7 days, the group archives for 30, as
long as GitHub lets a run's failed legs be re-run (they download them
again); nothing publishes the archives yet. A platform whose `toolchain` leg fails fails only its own
build legs.

`upstream-zig` runs the same `build` steps (`.github/workflows/build-r.yaml`,
shared by both workflows) on `default` for ubuntu-latest, macos-latest
and windows-latest with upstream zig (`pixi run fetch-zig`), after a
`toolchain` job of its own built with upstream zig (its artifacts' names
end in `-upstream`). It is a release gate, not per-commit CI: it runs on
demand (`gh workflow run upstream-zig.yaml`), for `v*` tags, and on pull
requests labelled `upstream-zig`. Every commit already compiles packages
with upstream zig through the wheel tests, whose compiler is PyPI's
`ziglang`.

The whole matrix is gated behind one repo variable, an emergency kill
switch rather than a cost control (hosted runners are free for this
public repo):

```bash
gh variable set ENABLE_HOSTED_JOBS --body false  # pause all CI jobs
gh variable set ENABLE_HOSTED_JOBS --body true   # resume
```

No commit or workflow edit needed either way. Publishing has a switch
of its own, `CONDA_PUBLISH`: `conda-package` still builds and tests on
main without it, and uploads only with it set to `true`
(`gh variable set CONDA_PUBLISH --body true`).

## More detail

Build internals, platform-specific fixes, and the CI/publish pipeline are
tracked in `.github/devdocs/` (`PLAN.md`/`TODO.md` at the repo root point
at the current feature's docs).

