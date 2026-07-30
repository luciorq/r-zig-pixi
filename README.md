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

```sh
pixi init my-r-project
cd my-r-project
pixi workspace channel add https://prefix.dev/universe
pixi add r-zig-slim
pixi run Rscript -e 'R.version.string'
```

Package compilation (`install.packages(...)`) works out of the box in the
installed environment — the Zig toolchain ships as a runtime dependency of
the package itself, so CRAN packages with C/C++/Fortran source compile
without any extra system setup.

### Build the conda package yourself

```sh
pixi run -e pkg conda-package
```

Produces `dist/conda/<platform>/r-zig-slim-*.conda` via `rattler-build`,
using this repo's own recipe (`recipe/recipe.yaml`). Useful for testing a
change to the build before publishing, or for producing a package for a
platform not published upstream.

### Publish to your own channel

```sh
pixi run -e pkg conda-publish
```

Uploads the just-built package for the current platform via
`rattler-build upload`. Each platform has its own task
(`[feature.pkg.target.<platform>.tasks]` in `pixi.toml`), so this is
typically run once per machine/OS as part of a release.

### Run R from source without packaging

For iterating on the build itself rather than consuming a package:

```sh
pixi run build   # zig build, no autoconf/make/gnuwin32
pixi run smoke   # quick sanity check
pixi run check   # R's own regression suite (linux/macOS)
```

Two variants are available as pixi environments: `default` (slim —
headless, no X11/tcltk/NLS) and `full` (adds tcltk, readline, NLS, jpeg
and tiff devices).

### Older Linux HPC servers

The Linux build targets glibc 2.17 by default (both the R build itself
and the package-compilation toolchain it ships), so binaries — and any
CRAN package compiled against them — run on considerably older
distributions than the build machine, without a separate build variant.

## Toggling the hosted-runner CI jobs

The GitHub-hosted matrix (`build`, `build-windows`, `build-legacy`,
`build-windows-legacy`) is gated behind a repo variable, off by default to
avoid burning Actions minutes — only `conda-package` (self-hosted) runs
unconditionally:

```sh
gh variable set ENABLE_HOSTED_JOBS --body true   # turn hosted jobs on
gh variable set ENABLE_HOSTED_JOBS --body false  # turn them back off
```

No commit or workflow edit needed either way.

## More detail

Build internals, platform-specific fixes, and the CI/publish pipeline are
tracked in `.github/devdocs/` (`PLAN.md`/`TODO.md` at the repo root point
at the current feature's docs).
