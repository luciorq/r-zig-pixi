# r-zig-pixi — Building R with a Single, Hermetic, Cross-Platform Toolchain

## Goal

Build R from source on Linux, macOS, and Windows with **one build design**,
using **only tools installed from conda-forge through pixi**. A machine with
nothing but `pixi` on it must be able to run:

```sh
pixi run build && pixi run smoke
```

Explicit non-goals: binary compatibility with CRAN/Rtools builds, quartz/aqua
support on macOS, X11 support anywhere (see "feature parity" below).

## Architecture decisions

### 1. Toolchain: zig everywhere, flang/gfortran for Fortran

| Role | linux-64 | win-64 | osx-64 / osx-arm64 | linux-aarch64 |
|------|----------|--------|--------------------|---------------|
| C    | `zig cc` | `zig cc` | `zig cc` | `zig cc` |
| C++  | `zig c++` | `zig c++` | `zig c++` | `zig c++` |
| Fortran | `flang` (LLVM 22) | `flang` (LLVM 22) | `gfortran` (explicit pkg) | `gfortran` (explicit pkg) |
| ar/ranlib | `zig ar` / `zig ranlib` | same | same | same |

- Zig has no Fortran frontend, so Fortran comes from conda-forge. LLVM flang is
  preferred (same LLVM backend and target conventions as `zig cc`); conda-forge
  only ships it for linux-64 and win-64 today, so macOS and linux-aarch64 use an
  explicitly pinned `gfortran` package — *not* the `compilers`/`c-compiler`
  metapackages, which would drag in a full GCC/Clang C toolchain.
- Revisit when conda-forge ships flang for osx-* (tracked in TODO.md).

### 2. Toolchain shims (`toolchain/zig-cc`, `zig-cxx`, `zig-ar`, `zig-ranlib`)

Autoconf and R's `Makeconf` want single-word compiler commands. The shims also
carry one load-bearing flag: **`-fno-sanitize=undefined`** — `zig cc` enables
UBSan in trap mode by default, and R's numeric code contains benign undefined
behavior that would otherwise die with SIGILL at runtime.

Because these shim paths get recorded into `etc/Makeconf`, every R *package*
compiled by this R later inherits the zig toolchain automatically. Makeconf is
the distribution mechanism for the toolchain — no `~/.R/Makevars` hijacking.

### 3. Feature parity = lowest common denominator, chosen deliberately

The same `capabilities()` profile on all three OSes:

- **X11: off everywhere** (`--with-x=no`). Windows and modern macOS have no X11;
  keeping it on Linux would break parity.
- **Graphics: cairo everywhere** (`--with-cairo --with-libpng`). Cairo works
  headless on all platforms. Quartz is dropped on macOS (`--without-aqua`),
  which also removes the Apple-SDK dependency.
- **BLAS/LAPACK: R's internal reference implementation** for v1 — zero external
  ABI risk. An `openblas` pixi feature is a later milestone.
- **Timezones: `--with-internal-tzcode`** + conda-forge `tzdata`, identical
  behavior on all platforms instead of trusting the OS zoneinfo.
- `--enable-R-shlib` (libR.so), `--without-recommended-packages`,
  `--disable-java`.

### 4. Two build variants: slim (default) and full — never more

`capabilities()` is baked at compile time, so capability choices are build
variants, not dependency toggles. To keep the variant matrix sane there are
exactly two, mapped to pixi environments (separate objdirs and prefixes,
`obj-<ver>-slim` / `obj-<ver>-full`):

- **slim (default env)** — the headless profile: cairo+png graphics, ICU,
  pcre2, libcurl, compression stack, internal BLAS, R shlib. No X11/quartz/
  tcltk/readline/NLS/jpeg/tiff. This is where R runs in practice (servers,
  CI, containers, IDE-server backends).
- **full (`pixi run -e full …`)** — slim plus tcltk (conda-forge tk via
  `--with-tcl-config`/`--with-tk-config`), readline+ncurses for the
  interactive console, NLS/gettext translations, jpeg+tiff devices.

What slim deliberately keeps: ICU, iconv, long double, libcurl, pcre2 —
anything whose removal would silently *change results or break package
installation* rather than just shrink the build. Slim must be smaller,
never differently-numbered.

Note: there is no configure-level way to trim R's legacy C API surface —
that's compiled unconditionally and every CRAN package assumes it. API
trimming is a milestone-5 (`build.zig`) ambition, not a configure flag.

### 5. Portable userland

- Build scripts are bash, but bash itself comes from conda-forge (`bash` on
  Unix, `m2-bash` on Windows). Orchestration entry points are pixi tasks, which
  are already cross-platform.
- Coreutils are the Rust uutils (`uutils-coreutils`) on linux-64/osx/win-64;
  GNU `coreutils` on linux-aarch64 where uutils isn't packaged. sed/grep/gawk/
  tar/gzip/curl all from conda-forge.
- The zig compile cache lives in `build/zig-cache/` inside the workspace, not
  in `$HOME` — nothing leaks onto or from the host.

### 6. Distribution: one prefix layout, two dependency providers

Two distribution modes were required: a standalone downloadable bundle
(tarball/zip) and a conda-forge-style package installable via pixi/conda.
Rather than build two separate trees, both consume the **same staged
prefix layout** — the only difference is *who supplies the runtime shared
libraries*.

- **Layout**: `<prefix>/lib/R` is R_HOME on every OS (matches conda-forge's
  own `r-base` convention); `<prefix>/bin/R` and `Rscript` are thin
  location-deriving trampolines.
- **`scripts/stage.sh`** (shared, runs after every `make install`):
  normalizes the tree so it's *correct* under either provider —
  dual-entry `$ORIGIN` rpaths (`R_HOME/lib` **and** `<prefix>/lib`; a
  conda env supplies the latter via the solver, a standalone bundle
  vendors into it), location-independent launchers, and every generated
  script's build-time-absolute tool paths rewritten to `$(R_HOME)`- or
  `$R_HOME`-relative bundled copies (see the `stage.sh` gotchas below —
  this turned out to be a deep rabbit hole).
- **`scripts/package-standalone.sh`**: the standalone-only step — walks
  the real dependency closure (ELF-magic scan + `ldd`, not name-pattern
  guessing) and vendors every conda-lib dependency into `<prefix>/lib`,
  plus runtime data the libs need (fontconfig config, Tcl's script trees
  on Windows). Emits `R-<ver>-<flavor>-<platform>.{tar.gz,zip}` + sha256.
- **`recipe/recipe.yaml`** (rattler-build): the conda-package-only step —
  *no vendoring*; instead declares `host:`/`run:` dependencies so the
  conda solver supplies the same libraries a standalone bundle would
  carry physically. Critically, `run:` must be **the actual linked
  closure** (derived from `ldd` on the real build output), not a guess
  from `pixi.toml`'s direct dependency list — see gotchas below.
  `recipe/build.sh` is a thin adapter that calls the *exact same*
  `configure-r.sh`/`build-r.sh`/`install-r.sh`/`stage.sh` scripts the
  pixi tasks use, with `R_INSTALL_PREFIX`/`CONDA_PREFIX` pointed at
  rattler's isolated prefix — the recipe is a consumer of the build
  scripts, never a fork of the build logic.
- **Deliberately not vendored in either mode**: the `zig` compiler
  itself. Running the built R needs nothing; *compiling new packages*
  needs `zig` on PATH. That is the one external-tool contract, chosen to
  avoid ever bundling a compiler into a runtime artifact.

**Two build-time-absolute-path bugs turned out to be the hard part**, both
found only by deleting the original build tree and running a moved copy
under a scrubbed environment (this class of bug is invisible if you only
test inside the same pixi env you built in):

1. R's generated `bin/R` bakes `SED=`, `R_SHARE_DIR=`, `R_INCLUDE_DIR=`,
   `R_DOC_DIR=` as literal absolute build-time paths (only `R_HOME_DIR`
   itself is computed dynamically by upstream R). `R_SHARE_DIR` is
   load-bearing for `R CMD SHLIB`/`INSTALL` (locates `share/make/*.mk`) —
   miss it and package compilation fails on a moved tree. Same disease in
   `bin/libtool`/`bin/javareconf` (baked `sed`/`grep`/`nm`/`dd`/`realpath`
   paths). Fix: a generic sweep in `stage.sh` rewrites every baked
   `$CONDA_PREFIX/bin/<tool>` reference under `bin/`+`etc/` to a bundled
   copy in `R_HOME/bin/toolchain/`, then bundles whatever tools got
   referenced (broadening `package-standalone.sh`'s dependency walk from
   name-pattern matching to real ELF-magic detection so the *bundled
   tools'* own conda-lib deps, e.g. `nm` needing libzstd/libpcre2, get
   vendored too).
2. **Harder**: `base::Sys.which()` bakes configure's absolute `which`
   path as a literal R string CONSTANT, compiled into `base.rdb` — not a
   text file, unfixable by sed after the build. Root cause chain: `utils`'s
   `.onLoad` → `.osVersion()` → `Sys.which("uname")` fails on a moved
   tree → **the entire utils/stats load fails** → every downstream error
   looks like "could not find function rnorm", nothing about `which`.
   Fix required patching R's actual *source* before configure/build
   (`configure-r.sh` patches `system.unix.R` to a dynamic,
   `R.home()`-relative expression with a graceful fallback), plus
   unconditionally bundling a `which` binary in `stage.sh`. Lesson: not
   every baked build-time path lives in a grep-able text file — R's
   lazy-loaded package data hides them too, and when a fix looks
   "impossible" via sed, check whether it's actually compiled in and
   patch the source instead.

### 7. Source provenance

R source comes from CRAN as a release tarball, pinned by version in
`pixi.toml` (`R_VERSION`) and by sha256 in `scripts/checksums/` (pinned on
first fetch, then enforced).

## Layout

```
pixi.toml              # platforms, toolchain deps, features, tasks
toolchain/zig-*        # compiler shims recorded into R's Makeconf
scripts/env.sh         # shared paths/helpers, sourced by all scripts
scripts/*.sh           # fetch / configure / build / smoke / check / install / clean
scripts/stage.sh       # post-install normalization (both distribution modes)
scripts/package-standalone.sh  # vendoring + tarball/zip artifact
recipe/                # rattler-build conda recipe (consumes the same scripts)
scripts/checksums/     # pinned source tarball hashes
build/                 # (gitignored) source tree, out-of-tree objdir, zig cache
dist/                  # (gitignored) install prefix, packaged artifacts
```

Build is out-of-tree (`build/obj-<ver>` vs `build/R-<ver>`), so the source tree
stays pristine and a reconfigure is just deleting the objdir.

## Milestones

1. **[DONE] Linux (linux-64)**: full configure + make + smoke test +
   `make check` with zig cc + flang. Proves the toolchain design
   end-to-end.
2. **[DONE 2026-07-17] macOS (osx-64/osx-arm64)**: build/smoke/check/
   contract all green on real arm64 hardware (gfortran instead of
   flang). Uncovered a real gfortran miscompilation, not a zig/ABI
   issue (see TODO.md).
3. **[DONE 2026-07-17] Windows (win-64)**: R builds and passes smoke +
   `make check` + contract test on Windows 11 via `src/gnuwin32` driven
   by `scripts/build-gnuwin32.sh`: zig cc (MinGW target) for C/C++,
   conda-forge MinGW gfortran for Fortran, m2-* msys userland,
   LOCAL_SOFT pointed at the conda Library tree, cairo device wired.
   The zig shims carry a GNU-ld emulation layer for Windows (lib*.dll.a
   / lib*.lib search, -mwindows implied libs, gfortran libdir). Known
   gap: slim==full on Windows (gnuwin32 has no capability off-switches).
4. **[DONE]** R regression suite (`pixi run check`) green on all three
   platforms; OpenMP working everywhere via conda-forge `llvm-openmp`;
   `openblas` pixi feature for external BLAS/LAPACK (linux validated).
5. **[DONE, linux+windows] Distribution**: relocatable standalone
   bundles (`pixi run package`) and a conda-forge-style package (see
   §6 above) sharing one staged prefix layout — `r-zig-slim` built and
   passed rattler-build's isolated test env on linux-64 (2026-07-17).
   macOS staging (`install_name_tool` + mandatory arm64 codesigning),
   and both distribution modes on macOS/Windows conda packaging, still
   open.
6. **Long term**: replace autoconf/gnuwin32 with a single `build.zig`, turning
   configure flags into `zig build` options — the true "one build system" end
   state. The dependency/flag inventory produced by milestones 1–3 is the spec.

## Known risks / open questions

- zig 0.16 is young; `zig cc` flag-compat regressions are possible. The version
  is pinned in pixi.toml; bumps should be deliberate.
- flang's Fortran runtime (`libflang_rt`) must be linkable by `zig cc` (lld) at
  final link; R's configure derives FLIBS from `flang -v` output.
- gfortran-on-macOS mixes a GNU Fortran runtime with an LLVM C toolchain;
  works (CRAN does clang + gfortran) but keep an eye on `-lgfortran` paths.
- uutils-coreutils is a young reimplementation; if R's Makefiles hit a missing
  GNU flag, the fallback is conda-forge GNU `coreutils` (still not the host's).
- No X11 means `capabilities("X11")` is FALSE forever by design; interactive
  graphics go through cairo devices (png/svg/pdf) and whatever tk provides.
- Build-time-absolute paths hide in more places than shell scripts: R's own
  `configure` bakes several (`SED`, `R_SHARE_DIR`, and — worst — `Sys.which`'s
  default, compiled into `base.rdb` where no text editor can reach it). Any
  future R version bump should re-run the full moved-tree adversarial test
  (extract bundle to a new path, delete the original, scrub the environment,
  run numerics + `R CMD SHLIB` + `library(utils)`) rather than assuming the
  existing `stage.sh` patches still cover everything.
- Conda recipe `run:` dependencies must be derived from the actual `ldd`
  closure of the built binaries, never guessed from `pixi.toml`. A dev pixi
  env masks missing `run:` deps completely (everything's already on
  `LD_LIBRARY_PATH`); only rattler-build's isolated test env — which
  installs *just* the declared `run:` set — exposes the gap.
