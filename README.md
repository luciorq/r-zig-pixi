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

Package compilation (`install.packages(...)`) works out of the box in the
installed environment — the Zig toolchain ships as a runtime dependency of
the package itself, so CRAN packages with C/C++/Fortran source compile
without any extra system setup.

### Build the conda package yourself

```bash
pixi run -e pkg conda-package
```

Produces `dist/conda/<platform>/r-zig-slim-*.conda` via `rattler-build`,
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

## CI

Everything runs on GitHub-hosted runners: `build` (ubuntu-latest,
ubuntu-24.04-arm, macos-latest, macos-15-intel × slim/full, plus the
linux openblas variants), `build-windows`, and `conda-package` for all
five subdirs (linux-64, linux-aarch64, osx-arm64, osx-64, win-64), which
publishes to the `universe` channel on prefix.dev via OIDC trusted
publishing on every push to `main`. There is no self-hosted fleet — the
former gamma/omicron/kappa runners were decommissioned in September 2026
and fully removed on 2026-09-24. Docs-only changes (`*.md`,
`.github/devdocs/`) skip the workflow.

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

