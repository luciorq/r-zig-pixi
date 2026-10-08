# r-zig-pixi

R, built as a conda package with the [Zig](https://ziglang.org) toolchain
(`zig cc`/`zig c++` in place of a system compiler) and driven end-to-end
through [pixi](https://pixi.sh). One dependency graph — pixi resolves
everything from conda-forge, Zig included — instead of a system compiler
toolchain plus a separate build system.

## Use cases

### Install R from the built conda package

The package (`r-zig-slim`) targets `linux-64`, `osx-64`, `osx-arm64`, and
`win-64`, publishing to the `universe` channel on prefix.dev (currently
private — requires `rattler-build auth login prefix.dev` access):

```bash
pixi init my-r-project
cd my-r-project
pixi workspace channel add https://prefix.dev/universe
pixi add r-zig-slim
pixi run Rscript -e 'R.version.string'
```

`r-zig-slim` is R alone: it runs R and installs packages that need no
compiling (R-only source packages and binary packages). To compile CRAN
packages with C/C++/Fortran sources, add the toolchain, which brings zig,
flang, make (and on Windows the POSIX userland) and pins the exact
`r-zig-slim` build:

```bash
pixi add r-zig-toolchain
```

Without it, installing a package with compiled code stops with a message
naming `r-zig-toolchain`.

### Build the conda package yourself

```bash
pixi run -e pkg conda-package
```

Produces `dist/conda/<platform>/r-zig-slim-*.conda` and
`r-zig-toolchain-*.conda` via `rattler-build`,
using this repo's own recipe (`recipe/recipe.yaml`). Useful for testing a
change to the build before publishing, or for producing a package for a
platform not published upstream.

### Publish to your own channel

```bash
pixi run -e pkg conda-publish
```

Uploads the just-built package for the current platform via
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
path. The tasks that run zig, `build`, `check`, `rzig-test` and the two
that compile packages with the built tree (`contract`, `verify-package`),
take it from `ZIG_BIN`; the other checks look at the tree it built:

```bash
export ZIG_BIN="$(pixi run fetch-zig)"   # PowerShell: $env:ZIG_BIN = pixi run fetch-zig
pixi run build && pixi run verify-tree && pixi run smoke && pixi run contract && pixi run verify-package
```

The build prints the zig it uses (`r-zig: zig = ...`); unset `ZIG_BIN`
to go back to the environment's. Each zig keeps its own cache in
`build/zig-cache/`, so switching between them never mixes their objects.
The conda package (`pixi run -e pkg conda-package`) always builds with
its recipe's zig, conda-forge's: rattler-build gives the recipe a clean
environment, without `ZIG_BIN`. `wheel-test` always compiles with the
`ziglang` it installs into its venv, which is upstream zig already.

### Build R as a Python wheel

```bash
pixi run -e minimal build            # the installed tree, libraries vendored
pixi run -e minimal verify-tree      # its static checks
pixi run -e minimal verify-package   # archive it, check the archive relocated
pixi run -e wheel wheel              # -> dist/wheel/r_zig-4.6.1-*.whl and r_zig_toolchain-4.6.1-*.whl
pixi run -e wheel wheel-test         # pip-install them into a fresh venv and use them
```

The wheel (`r-zig`, import name `r_zig`) is the whole relocatable
`minimal` tree plus console scripts `R`/`Rscript` and `r_zig.r_home()` for
embedders such as rpy2; it installs packages that need no compiling. For
packages with C/C++ code, `pip install r-zig-toolchain` adds the compiler
front (rzig) and GNU make, with the PyPI
[`ziglang`](https://pypi.org/project/ziglang/) package as the compiler, so
no system compiler is needed.
ziglang is an upstream zig build, which links its own libc++ statically,
so compiled C++ packages need no C++ runtime (with conda-forge's zig,
which would link conda's shared libc++, rzig keeps it static). Linux
wheels are `manylinux2014` (glibc 2.17). Packages with Fortran sources need
a Fortran compiler, which neither the wheel nor ziglang provides: R's FC,
the toolchain's `zig-fc`, runs an LLVM `flang` found on PATH and stops
with a message when there is none.
Details: `.github/devdocs/feat-wheel-minimal/PLAN.md`.

### Older Linux HPC servers

The Linux build targets glibc 2.17 by default (both the R build itself
and the package-compilation toolchain it ships), so binaries — and any
CRAN package compiled against them — run on considerably older
distributions than the build machine, without a separate build variant.

## CI

Everything runs on GitHub-hosted runners: `build` (ubuntu-latest,
ubuntu-24.04-arm, macos-latest, macos-15-intel × slim/full, plus the
linux openblas variants, minimal on all four, and windows-latest's one
variant; the same steps in the same order on every OS, on the installed
tree, which is the tree the standalone archive packs), and
`conda-package` for all
five subdirs (linux-64, linux-aarch64, osx-arm64, osx-64, win-64), which
publishes to the `universe` channel on prefix.dev via OIDC trusted
publishing on every push to `main`. There is no self-hosted fleet — the
former gamma/omicron/kappa runners were decommissioned in September 2026
and fully removed on 2026-09-24. Docs-only changes (`*.md`,
`.github/devdocs/`) skip the workflow.

The full matrix above runs only on request: on a pull request labelled
`full-ci` and on a manual dispatch (`pixi run ci-trigger` for main, `gh
workflow run build.yaml --ref <branch>` for a branch). Every other pull
request push and every push to `main` runs the core tier: `default` on
all five platforms and `minimal` on linux-64 (6 legs). `conda-package`
also runs on every push to `main`, which publishes, and on a pull
request that changes `recipe/`, `pixi.toml`, `pixi.lock`, `build.zig`,
`zigbuild/`, `scripts/` or the workflows. See
`.github/devdocs/chore-ci-tiers/PLAN.md`.

`upstream-zig` runs the same `build` steps (`.github/workflows/build-r.yaml`,
shared by both workflows) on `default` for ubuntu-latest, macos-latest
and windows-latest with upstream zig (`pixi run fetch-zig`). It is a
release gate, not per-commit CI: it runs on demand (`gh workflow run
upstream-zig.yaml`), for `v*` tags, and on pull requests labelled
`upstream-zig`. Every commit already compiles packages with upstream
zig through the wheel tests, whose compiler is PyPI's `ziglang`.

The whole matrix is gated behind one repo variable, an emergency kill
switch rather than a cost control (hosted runners are free for this
public repo):

```bash
gh variable set ENABLE_HOSTED_JOBS --body false  # pause all CI jobs
gh variable set ENABLE_HOSTED_JOBS --body true   # resume
```

No commit or workflow edit needed either way.

## More detail

Build internals, platform-specific fixes, and the CI/publish pipeline are
tracked in `.github/devdocs/` (`PLAN.md`/`TODO.md` at the repo root point
at the current feature's docs).

