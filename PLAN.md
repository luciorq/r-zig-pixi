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
  scripts, never a fork of the build logic. **One `recipe.yaml` covers
  linux-64 and osx-arm64** via rattler-build's recipe-v1 `if: linux` /
  `if: osx` / `if: linux64` selectors on individual dependency list
  entries (flang vs. gfortran, patchelf vs. n/a, etc.) — `build.sh` needs
  no OS branching since it only calls already-OS-aware scripts.
  `rattler-build build --render-only --target-platform <plat>` renders
  and validates the selector logic without touching hardware, worth
  running before every real build on a new platform.
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

**macOS staging (`install_name_tool` + mandatory ad-hoc codesigning),
2026-07-18**: `stage.sh`/`package-standalone.sh` now implement the same
dual-provider relocation scheme for osx-arm64 as Linux, and it passed the
identical adversarial test (move the built tree, delete the original,
scrub `PATH` to `/usr/bin:/bin`, exercise numerics/cairo/`Rscript`/
`R CMD SHLIB`) on real hardware (omicron). Mach-O detection uses the
64-bit-LE magic `cffaedfe` (mirroring the ELF-magic scan already used for
Linux) instead of name patterns. Three macOS-specific bugs, none of them
present on Linux:

1. **dyld ignores `LD_LIBRARY_PATH` entirely.** `stage.sh`'s `etc/ldpaths`
   rewrite only ever wrote `LD_LIBRARY_PATH` (the Linux/generic-Unix
   variable) — silently breaking every macOS launch, since `bin/exec/R`'s
   dependency on `libR.dylib`/`libRblas.dylib` is a *bare* name (no
   `@rpath/` prefix, because R's own build never sets `-install_name` on
   them) and bare names resolve only through
   `DYLD_FALLBACK_LIBRARY_PATH` — R's own stock `ldpaths` sets exactly
   that on Darwin. `stage.sh` now branches by OS and writes the correct
   variable. conda-forge's *own* dylibs, by contrast, all use
   `@rpath/<name>` IDs (confirmed via `otool -D`/`-L` on `libgfortran`,
   `libomp`, `libicuuc`), so *they* need real `LC_RPATH` entries — added
   via `install_name_tool -add_rpath @loader_path/<rel>` mirroring
   Linux's dual `$ORIGIN` scheme, on every Mach-O file found under
   `R_HOME` and `<prefix>/bin`.
2. **`install_name_tool` invalidates the code signature, and arm64 macOS
   refuses to execute an unsigned binary.** Every file `stage.sh` or
   `package-standalone.sh` touches with `install_name_tool` is re-signed
   ad hoc (`codesign --force --sign -`) immediately after — this is the
   "mandatory arm64 codesigning" TODO from earlier milestones, now done.
   No Developer ID/notarization involved (not needed for a self-built,
   non-App-Store CLI tool) — ad hoc is the same level conda-forge's own
   unsigned dylibs already carry.
3. **`readlink -f` doesn't exist on BSD/macOS** (only GNU's `readlink`
   has `-f`), so every relocatable launcher (`bin/R` trampoline, both
   `Rscript` wrappers, R's own patched `bin/R`) switched to a portable
   POSIX symlink-resolution loop (`readlink` one hop at a time + `cd -P`).
   This surfaced a second, gnarlier bug on top: macOS's *system* `bash`
   (3.2.57, frozen since ~2007 to avoid GPLv3) misparses a `case`
   statement with an empty first branch when the whole construct is
   forced onto one line inside a `$(...)` command substitution — exactly
   what the `R_HOME_DIR=` sed replacement does. Fix: use the
   POSIX-optional leading `(` on each case pattern (`(/*)` not `/*)`),
   which sidesteps the parser bug and is valid everywhere. Only found by
   executing the *staged launcher itself* as a file on real hardware —
   trivial standalone repros of the same case statement via `bash -c`
   with a short string did not reproduce it (had to match the exact
   forced-one-line/nested-`$()` shape to trigger).

Also hit, orthogonal to macOS specifically: an objdir whose
`Sys.which()` source patch (see bug 2 below) was never actually applied —
`fetch-r.sh` had at some point re-extracted a clean source tree over an
already-patched checkout, and `configure-r.sh`'s
`[ -f "$OBJ_DIR/Makeconf" ]` early-return means a re-run skips reapplying
source patches even when the source reverted underneath it. `print(Sys.which)`
on the built R showed the raw build-time absolute path baked in — the
tell. Not fixed generally (would need patch-application to be tracked
independent of the configure-already-ran guard); noted as a known risk
below since it can silently ship a broken build after any operation that
touches the source tree post-configure.

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
5. **[DONE on all 3 OSes] Distribution**: relocatable standalone bundles
   (`pixi run package`) share one staged prefix layout across
   Linux/macOS/Windows (see §6 above) — macOS staging landed 2026-07-18
   (`install_name_tool` + mandatory ad-hoc codesigning), adversarially
   verified on real arm64 hardware to the same standard as
   Linux/Windows. Conda packaging (rattler-build) via a single
   selector-conditioned `recipe.yaml` (no per-OS fork): linux-64
   (`r-zig-slim`, 2026-07-17), osx-arm64 (2026-07-22), and win-64
   (2026-07-23) all built and passed their isolated test envs — the
   win-64 pass uncovered a real, previously-masked `ICU_PATH` bug in
   `build-gnuwin32.sh` (see TODO.md and Known risks).
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
  run numerics + `R CMD SHLIB` + `library(utils)`) — now verified on all
  three OSes (2026-07-18 for macOS) — rather than assuming the existing
  `stage.sh` patches still cover everything.
- **A `configure-r.sh` source patch (Sys.which) can go stale silently.**
  Found while testing macOS staging: an objdir's compiled `Sys.which` still
  had the raw build-time absolute path baked in, even though
  `configure-r.sh`'s patch to `system.unix.R` was present and correct in
  the repo — the *source checkout* had reverted to unpatched (most likely
  `fetch-r.sh` re-extracted a clean tarball over it at some point), and
  `configure-r.sh`'s `[ -f "$OBJ_DIR/Makeconf" ]` early-return means a
  later `pixi run configure` silently skips reapplying source patches
  once an objdir exists, regardless of the source tree's actual state.
  `print(Sys.which)` on the built R is the tell (shows the literal path
  instead of the dynamic `R.home()`-relative expression). Not fixed
  generally — patch application isn't tracked independently of "did
  configure already run" — so if `Sys.which`/`utils`/`stats` loading ever
  breaks mysteriously on an existing objdir, check this before assuming
  it's a new bug.
- Conda recipe `run:` dependencies must be derived from the actual `ldd`
  closure of the built binaries, never guessed from `pixi.toml`. A dev pixi
  env masks missing `run:` deps completely (everything's already on
  `LD_LIBRARY_PATH`); only rattler-build's isolated test env — which
  installs *just* the declared `run:` set — exposes the gap.
- [FIXED 2026-07-17] CRAN packages can autoprobe OpenMP themselves (not just
  read R's `SHLIB_OPENMP_CFLAGS`). `data.table`'s own `configure` bakes a
  literal `-lomp` into its `PKG_LIBS` on macOS, and the `zig-cc`/`zig-cxx`
  shims used to unconditionally add their own `-lomp` whenever `-fopenmp`
  appeared — the resulting double `LC_LOAD_DYLIB` for `libomp.dylib` makes
  newer macOS `dyld` refuse to `dlopen` ("duplicate linked dylib"), breaking
  package installs even though the object files link without error. Shims
  now scan for an existing `-lomp`/`libomp.lib` before injecting their own;
  verified on omicron (osx-arm64) contract test. General lesson: any
  toolchain shim that reacts to a flag (`-fopenmp`) rather than to "did the
  caller already handle this" can double up when the caller is smarter than
  expected — same class of bug as the `Sys.which`/`base.rdb` one above.
- [FIXED 2026-07-23] `USE_ICU ?= YES` is gnuwin32's own default
  (`src/gnuwin32/MkRules`), and `src/extra/tzone/Makefile.win` only adds
  `-I"$(ICU_PATH)"/include` to find `unicode/ucal.h` when `ICU_PATH` is
  set — `scripts/build-gnuwin32.sh` never set it, even though
  conda-forge's `icu` package genuinely ships that header under
  `Library/include/unicode/`. Fixed by adding `ICU_PATH = $LOCAL_SOFT` to
  the generated `MkRules.local`, same pattern as the existing
  `CAIRO_CPPFLAGS`/`TCL_HOME` entries. This is a general lesson, not
  Windows-specific: **a long-lived, incrementally-built dev objdir can
  silently diverge from a clean build's correctness** — kappa's regular
  pixi build dir had presumably compiled `registryTZ.o` successfully (or
  at least once) long enough ago that later `make` runs never needed to
  recompile it, masking this bug through every previous "make check
  green on Windows" milestone; only rattler-build's always-fresh isolated
  work dir forced a true from-scratch compile and exposed it immediately.
  Any script whose correctness was last verified against a persistent
  build directory should be re-verified against a clean one before being
  trusted.
- **rattler-build cosmetically redacts the real prefix path in captured
  build logs**, replacing it with the literal string `%PREFIX%` for
  readability — this looks *exactly* like a real corrupted/unexpanded
  environment variable in a `set -x` trace and cost significant
  diagnostic time on the Windows conda recipe (2026-07-23) before a raw
  `od -c` byte-dump of `$PREFIX` proved the underlying value was correct
  the entire time. When a traced variable looks wrong, check its actual
  bytes before trusting the log text, especially under rattler-build.
