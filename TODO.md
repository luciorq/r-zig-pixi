# TODO

## Milestone 1 — Linux build (linux-64)

- [x] pixi manifest solving for all 5 platforms (linux-64, linux-aarch64,
      osx-64, osx-arm64, win-64)
- [x] zig / flang / bash / make / coreutils all resolving from `.pixi/envs`
- [x] Fetch + checksum-pin R source from CRAN with pixi-provided curl/tar
- [x] `pixi run configure` clean with zig-cc/zig-cxx/flang
      (fixes: flang-rt is a separate conda package; FLIBS passed explicitly
      because autoconf mis-parses flang's verbose link output; expat +
      xorg-xorgproto needed to satisfy cairo's pkg-config chain)
- [x] `pixi run build` produces working `bin/R`
      (fixes: shims inject -Wl,-soname for lib*.so — lld records literal
      paths in DT_NEEDED otherwise; unzip needed for zoneinfo install)
- [x] `pixi run smoke` passes (LAPACK/BLAS/fft via flang, pcre2, iconv,
      compression; capabilities: cairo/tcltk/png/jpeg/tiff/ICU/NLS TRUE,
      X11/aqua FALSE by design)
- [x] `pixi run install` into dist/, installed R runs standalone
- [x] Two-variant design: slim (default env, headless: no tcltk/readline/
      NLS/jpeg/tiff) and full (`-e full`); separate objdirs/prefixes;
      smoke test asserts each variant's exact capability profile
- [x] `pixi run check` (R's own regression suite) green for both variants
      (2026-07-16: rc=0 for slim and full, reference-output comparisons OK)
- [x] Compile real CRAN source packages against this R: Rcpp and data.table
      build, load, and pass functional tests; Rcpp::evalCpp works, proving
      the Makeconf zig-toolchain contract end-to-end (runtime C++ compile).
      data.table is single-threaded for now (no OpenMP with zig cc — parked)
- [x] CI: `.github/workflows/build.yml` — linux (slim+full: build/smoke/check),
      macOS (experimental, non-gating), Windows (env solve only). Activates
      on first push to GitHub

## Milestone 2 — macOS (osx-64, osx-arm64)

- [x] Environment installs from the same lockfile on real hardware
      (omicron, macOS 26.4 arm64, bare machine + pixi)
- [x] configure + full C/Fortran compile pass with zig cc + gfortran;
      FLIBS resolved into the pixi env (lib/gcc/arm64-apple-darwin)
- [x] Fix: raise `ulimit -n` in env.sh — macOS's 256-fd default breaks
      zig's linker on libR.dylib (ProcessFdQuotaExceeded, ~300 objects)
- [x] Slim build completes and smoke test passes on omicron (osx-arm64,
      zig cc Mach-O linking + gfortran numerics all green)
- [x] Portability fixes from omicron: no backslash escapes in `R -e`
      smoke code (Apple /bin/sh xpg_echo eats one level); long.double
      not asserted (arm64 macOS: long double == double, matches CRAN)
- [x] Full-variant build + smoke on omicron
- [x] Contract test (Rcpp evalCpp + data.table) passes on omicron
- [x] **gfortran 15.2 miscompiles complex LAPACK at -O2 on arm64-darwin**:
      zgesdd returns wrong U/V with info=0 (silent wrong numbers; caught by
      `make check` lapack.R). Isolated with a pure-Fortran driver — not a
      zig/ABI issue. Workaround: FFLAGS/FCFLAGS capped at -O1 for
      gfortran-on-Darwin in configure-r.sh.
- [x] **Milestone 2 complete** (2026-07-17): clean-slate re-validation on
      omicron green across the board — slim and full: build, smoke,
      `make check`, and contract test all rc=0 on osx-arm64.
- [ ] Narrow the gfortran bug to a specific -O2 optimization (try
      -O2 -fno-tree-vectorize etc.), report upstream to GCC/conda-forge
- [ ] Check whether linux-aarch64 (also gfortran) has the same problem —
      run `make check` there before trusting it
- [ ] Confirm `-single_module` configure warning is benign with zig's linker
- [ ] Confirm cairo-only graphics (quartz intentionally dropped) and tk
      from conda-forge work headless
- [ ] Swap gfortran → flang when conda-forge ships flang for osx-*

## Milestone 3 — Windows (win-64)

- [x] **R 4.6.1 builds and passes smoke test on Windows 11** (kappa,
      2026-07-17): gnuwin32 driven by zig cc (MinGW target) for C/C++ and
      conda-forge MinGW gfortran for Fortran; numerics green;
      png/jpeg/tiff/tcltk/NLS/ICU/libcurl TRUE
- [x] ABI decision: dropped flang on win-64 (conda-forge's targets MSVC);
      conda-forge now ships MinGW gfortran (`gcc_impl_win-64`) — one
      GNU/MinGW ABI across the whole Windows toolchain, validated by a
      mixed zig+gfortran ABI test before wiring the build
- [x] gnuwin32 driven via `scripts/build-gnuwin32.sh`: msys make
      (m2-make), gcc/g++ shim names for zig, prefixed binutils exposed
      unprefixed, windres wrapped with a native preprocessor,
      LOCAL_SOFT → conda Library tree, TCL_VERSION=86t patch
- [x] zig shims grew a GNU-ld emulation layer for Windows links:
      lib<n>.dll.a and lib<n>.lib search (zig misses both — report
      upstream), -mwindows implied GDI libs, gfortran private libdir
- [x] Same pixi tasks work on Windows (fetch/build/smoke; configure no-ops)
- [x] cairo device wired (USE_CAIRO + conda cairo/fontconfig; values must
      be quoted in MkRules.local — gnuwin32 passes them unquoted to a
      sub-make); capabilities("cairo") TRUE on Windows
- [x] Contract test passes on Windows: Rcpp evalCpp, data.table, minqa
      (Rcpp dep + package Fortran). Makeconf's hardcoded SHLIB_OPENMP
      flags blanked (zig has no OpenMP runtime; matches unix behavior)
- [ ] Parity caveats to resolve: jpeg/tiff/tcltk forced on (gnuwin32 has
      no off-switches → slim==full on Windows today); NLS on
- [x] **`make check` green on Windows** (2026-07-17): complex LAPACK
      passes at gfortran -O3 on x86_64-MinGW — the arm64-darwin
      miscompilation does NOT reproduce here. Two environmental fixes:
      MY_TCLTK + TCL_LIBRARY exported for conda Tcl (env.sh), and
      tests/Makefile.win's hardcoded eval-etc-2.R (needs recommended
      pkg Matrix) patched out in check-r.sh
- [ ] Report upstream to zig: MinGW -l search misses lib<n>.dll.a
- [ ] `make distribution` / installer story; `pixi run install` on Windows

## OpenMP (completed 2026-07-17)

- [x] **OpenMP working on all three OSes**: zig cc performs -fopenmp
      codegen natively; the shims supply what it lacks (omp.h include
      path + libomp link) from conda-forge `llvm-openmp`. Verified via
      data.table getDTthreads: linux 8, windows 6, macOS 5 threads.
      R core also built with OpenMP (SHLIB_OPENMP_CFLAGS=-fopenmp in
      Makeconf on unix; gnuwin32 Makeconf restored to -fopenmp).
      Contract test asserts `"OpenMP version"` appears in
      `getDTthreads(verbose=TRUE)` output, machine-independent (NOT
      `getDTthreads() > 1` — that broke CI on small runners, since
      data.table defaults to 50% of cores = 1 on a 2-core box).
- [x] **Fix (2026-07-17): macOS "duplicate linked dylib" on data.table
      install.** `data.table`'s own `configure` autoprobes OpenMP and
      bakes a literal `-lomp` into its `PKG_LIBS` on macOS, on top of
      R's `-fopenmp` in `SHLIB_OPENMP_CFLAGS` — `zig-cc`/`zig-cxx` were
      unconditionally adding *their own* `-lomp` whenever `-fopenmp`
      appeared, so `libomp.dylib` got two `LC_LOAD_DYLIB` entries and
      newer macOS `dyld` refused to `dlopen` it (CI failure: `unable to
      load shared object ... duplicate linked dylib '@rpath/libomp.dylib'`,
      only after Rcpp/minqa had already installed fine). Fixed by having
      both shims skip their OpenMP-link injection when `-lomp` (or
      `libomp.lib` on Windows) is already present in the caller's args —
      `$CONDA/lib` is already on the link line via Makeconf's LDFLAGS, so
      the caller's own `-lomp` still resolves. Verified end-to-end on
      omicron (osx-arm64): Rcpp + data.table + minqa contract test green,
      `data.table is using 5 threads`. See PLAN.md's Known risks.

## Milestone 4 — Distribution & ecosystem

- [x] `openblas` pixi feature (2026-07-17): `openblas`/`full-openblas`
      environments; R_BLAS activation var → configure --with-blas/-lapack
      -lopenblas; separate objdirs per BLAS flavor; smoke asserts the
      linked BLAS both ways (openblas variant → libopenblas, default →
      libRblas); validated on linux-64 (build/smoke/contract green,
      CI job added). Windows/gnuwin32 BLAS switch still TODO; macOS
      openblas variant unvalidated (expect it to just work)
- [ ] Recommended packages (`--with-recommended-packages`) once base is stable
- [x] Relocatable + conda-packageable installs (2026-07-17, refactored
      into scripts/stage.sh + scripts/package-standalone.sh, one prefix
      layout serves both distribution modes — see PLAN.md §6):
      - stage.sh (shared, both OSes/both packaging modes): dual $ORIGIN
        rpaths (R_HOME/lib AND prefix/lib — conda env supplies the
        latter, standalone bundle vendors into it), launchers derive
        R_HOME from their own location, Rscript CLI emulated via the R
        launcher (binary hard-embeds build path, ignores env R_HOME),
        R's generated bin/R's SED=/R_SHARE_DIR=/R_INCLUDE_DIR=/R_DOC_DIR=
        rederived (R_SHARE_DIR is load-bearing for R CMD SHLIB/INSTALL),
        same fix generalized across bin/libtool + bin/javareconf (baked
        sed/grep/nm/dd/realpath paths), Makeconf rewritten to
        $(R_HOME)-relative shims, Windows Tcl→R_HOME/Tcl layout
      - **base::Sys.which() fix**: configure bakes an absolute `which`
        path as a literal string CONSTANT compiled into base.rdb — no
        text file to sed. Root cause chain: utils's .onLoad ->
        .osVersion() -> Sys.which("uname") fails on a moved tree ->
        entire utils/stats load fails -> misleading "could not find
        function rnorm" with nothing which-related in the error. Fixed
        by patching R's actual source (system.unix.R) in
        configure-r.sh to a dynamic R.home()-relative expression with
        graceful fallback, + stage.sh unconditionally bundles `which`.
      - package-standalone.sh (linux + windows): vendors conda-lib deps
        via ELF-magic dependency walk (broadened from name-pattern
        matching so newly-bundled tools' own deps get caught too),
        fontconfig data, Tcl runtime (Windows), emits
        R-<ver>-<flavor>-<platform>.{tar.gz,zip} + sha256
      - Verified adversarially on BOTH platforms, multiple rounds:
        extracted bundle run from a moved path with the original tree
        deleted and a scrubbed env — numerics, cairo PNG, Rscript (all
        calling forms), R CMD SHLIB compiling+linking+loading a fresh
        package, library(utils)/stats, tcltk (Windows)
      - Documented, deliberately unfixed: running the bundle needs
        nothing; compiling NEW packages needs `zig` on PATH (the one
        external tool contract — never vendor the compiler itself)
      - TODO: headers for compiling against bundled libs aren't shipped
        (packages needing e.g. zlib.h still want zig + an env, or system
        headers)
- [x] **macOS staging (2026-07-18)**: `install_name_tool` +
      mandatory ad-hoc codesigning, verified end-to-end on omicron
      (osx-arm64) at the same adversarial standard as linux/windows —
      moved tree, original deleted, `PATH=/usr/bin:/bin` only. Mach-O
      detection via 64-bit-LE magic `cffaedfe` (parallel to the ELF-magic
      scan). Three real bugs, all macOS-specific:
      - `stage.sh`'s `etc/ldpaths` rewrite only ever wrote
        `LD_LIBRARY_PATH`, which dyld ignores completely — silently broke
        every macOS launch. `bin/exec/R`'s dep on libR.dylib/libRblas.dylib
        is a bare name (R never sets `-install_name` on them), resolved
        only via `DYLD_FALLBACK_LIBRARY_PATH` (what R's own stock ldpaths
        uses on Darwin); conda-forge's own dylibs use `@rpath/<name>` IDs
        instead and need real `LC_RPATH` entries. Fixed: `ldpaths` now
        branches by OS, and `install_name_tool -add_rpath
        @loader_path/<rel>` adds the dual R_HOME/lib + prefix/lib entries
        (mirroring Linux's dual $ORIGIN) on every Mach-O file.
      - `install_name_tool` invalidates the code signature; arm64 macOS
        won't execute an unsigned binary. Fixed: `codesign --force --sign
        -` (ad hoc) after every `install_name_tool` call, both in
        stage.sh and package-standalone.sh's vendored copies.
      - `readlink -f` doesn't exist on BSD/macOS — switched every
        launcher to a portable symlink-following loop. That surfaced a
        second bug: macOS's system bash (3.2.57, frozen pre-GPLv3)
        misparses a `case` with an empty first branch when forced onto
        one line inside `$(...)` (exactly the shape of the `R_HOME_DIR=`
        sed replacement) — fixed with the POSIX-optional leading `(` on
        each case pattern (`(/*)` not `/*)`). Only reproduced by running
        the actual staged launcher as a file on real hardware; a trivial
        `bash -c` repro needed the exact same nested-`$()` shape.
      - Also hit (not macOS-specific, but found here): an objdir whose
        Sys.which source patch had silently gone stale — see PLAN.md's
        Known risks for the `configure-r.sh`/`fetch-r.sh` staleness gap.
- [~] conda-forge-style package via rattler-build (recipe/recipe.yaml +
      recipe/build.sh, linux-64 first): the recipe reuses the exact
      same configure/build/install/stage scripts, pointed at rattler's
      isolated prefix. Two real bugs found and fixed by testing (not
      guessing) against rattler-build's isolated test env:
      - `run:` deps must be the ACTUAL `ldd` closure of bin/exec/R +
        libR.so, not a guess from pixi.toml's direct deps — a dev pixi
        env masks missing run: deps (everything's already on
        LD_LIBRARY_PATH); only the isolated test env catches it. Fixed:
        added zstd, libiconv, libstdcxx, libgcc (transitively pulled at
        build time, invisible until packaged+tested standalone).
      - Same Sys.which()/base.rdb bug as above, independently confirmed
        via this pathway (conda's own build_env/host_env split tears
        down the build-time absolute paths before the test/install env
        runs, so it surfaces here even faster than in a standalone
        bundle test).
      **Green as of 2026-07-17**: r-zig-slim-4.6.1-hb0f4dca_0.conda built
      and passed its test (installed from declared run: deps only, no
      vendoring — numerics + cairo/ICU/libcurl capabilities all work).
- [x] **macOS conda recipe (2026-07-22)**: `recipe/recipe.yaml` extended
      with `if: linux`/`if: osx`/`if: linux64` selectors (rattler-build
      recipe v1 conditional syntax) rather than a second recipe file —
      `recipe/build.sh` needed zero changes, it already just calls the
      OS-aware pixi scripts. Platform split: flang/flang-rt_linux-64 +
      patchelf + xorg-xorgproto + zstd/libiconv/libstdcxx/libgcc on
      linux; gfortran (build+host+run, provides the Fortran runtime) +
      libiconv on osx. Rendered locally for both `linux-64` and
      `osx-arm64` via `rattler-build build --render-only` before ever
      touching hardware, to catch selector-syntax mistakes for free.
      Built for real on omicron: `r-zig-slim-4.6.1-h60d57d3_0.conda`
      (27.67 MiB). rattler-build's post-build overlinking lint flagged
      several dylibs (libquadmath, libgfortran, libharfbuzz, libintl,
      libgraphite2, libffi, libpixman, libfribidi, libzstd) as linked but
      not explicitly in `run:` — unlike the linux `run:` gap (genuinely
      missing deps, only caught by testing), here `rattler-build test`
      against the isolated test env (only the declared run: set
      installed) printed `conda R OK` and passed cleanly: the `gfortran`/
      `cairo`/`pango`/`fontconfig`/`glib` run deps already transitively
      pull in every flagged library via their own metapackage chains.
      Verified empirically rather than added defensively — no explicit
      deps added for warnings that don't manifest as real failures.
- [x] **Windows conda recipe (2026-07-23)**: same `recipe/recipe.yaml`
      extended with `if: win`/`if: unix` selectors (gfortran instead of
      flang/patchelf; m2-* + uutils-coreutils build-only tooling;
      libjpeg-turbo/libtiff/tk/gettext in host+run since gnuwin32 has no
      capability off-switches, same as pixi.toml's win-64 target).
      `install-r.sh`'s existing Windows branch (copies bin/etc/include/
      library/modules/share/doc into the prefix layout, since gnuwin32
      has no `make install`) meant `recipe/build.sh` needed zero changes
      here either. Built for real on kappa:
      `r-zig-slim-4.6.1-h9490d1a_0.conda` (29.99 MiB), `rattler-build
      test` passed ("conda R OK").
      **Real bug found and fixed**: `unicode/ucal.h` not found compiling
      `src/extra/tzone/registryTZ.c`. Root cause: gnuwin32's
      `src/gnuwin32/MkRules` defaults `USE_ICU ?= YES`, and
      `tzone/Makefile.win` only adds `-I"$(ICU_PATH)"/include` when
      `USE_ICU` is defined — but `scripts/build-gnuwin32.sh`'s generated
      `MkRules.local` never set `ICU_PATH`, so the flag was always
      empty/missing even though conda-forge's `icu` package genuinely
      installs `unicode/ucal.h` under `Library/include/unicode/`. Fixed
      by adding `ICU_PATH = $LOCAL_SOFT` to `MkRules.local` (same pattern
      as the existing `CAIRO_CPPFLAGS`/`TCL_HOME` entries). This bug
      predates this session but was masked on kappa's long-lived,
      incrementally-cached build dir (registryTZ.o compiled once,
      correctly or not, ages ago, and never needed recompiling since) —
      rattler-build's always-fresh isolated work dir forced a genuine
      from-scratch compile and exposed it immediately. **Lesson**: an
      incrementally-built dev objdir is not a substitute for a clean
      build when validating a build script's correctness — the two can
      silently diverge for a long time.
      **False lead, for the record**: `set -x` traces initially looked
      like `$PREFIX` was corrupted to the literal string `%PREFIX%`
      inside `build.sh` on Windows, while every manual replay of the
      exact same generated `.bat` file showed a correct value — this was
      rattler-build's own **log redaction** (it cosmetically replaces
      the real prefix path with `%PREFIX%` in captured log text for
      readability) with the value ITSELF always fine underneath; a raw
      `od -c` byte-dump of `$PREFIX` proved this conclusively. Several
      workaround attempts (a custom `bld.bat`, explicit prefix
      passthrough, a `CONDA_DEFAULT_ENV`-based fallback in `build.sh`)
      were all built and tested against this phantom before the byte
      dump revealed it wasn't real; all reverted once the actual bug
      (`ICU_PATH`) was found and fixed. See PLAN.md's Known risks.
- [x] **Recipe test coverage upgrade (2026-07-23)**: the conda recipe's
      `tests:` script was a stripped-down subset of `scripts/smoke-
      test.sh` (only `solve()` + 3 capability flags) — caught when asked
      directly whether the *full* smoke test had been run against the
      Windows conda package (it hadn't). Upgraded to mirror
      smoke-test.sh's actual assertions (`qr()`/`fft()` round-trips,
      pcre2 regex, zlib compression round-trip, full slim capability
      profile including the FALSE assertions for tcltk/jpeg/tiff/NLS)
      via the same `if: win/else` selector already used for the test
      script — Windows keeps smoke-test.sh's own relaxed windows-only
      assertion set (no slim-specific FALSE checks), matching its
      documented lack of capability off-switches. Rebuilt and re-tested
      for real on all three platforms (not just rendered): linux-64
      locally, osx-arm64 on omicron, win-64 on kappa — all pass.
      `rattler-build test` runs whatever test was baked into the
      artifact at *build* time, not the current recipe.yaml, so
      validating a test-script change always requires a full rebuild,
      not just a re-test of an existing artifact.
- [x] **CI parity fix (2026-07-23)**: `.github/workflows/build.yml` had
      macOS marked `experimental: true`/`continue-on-error: true` with a
      comment claiming it was "not yet validated" — stale since Milestone
      2 completed 2026-07-17. Neither macOS nor Windows ran `pixi run
      check` (regression suite) at all. Fixed: macOS folded into the main
      matrix (gates the build like linux now), Windows's
      `continue-on-error` removed, `check` added to both. Deliberately
      NOT added in this pass (flagged, not forgotten): CI still never
      exercises `pixi run package` (standalone bundles) or the conda
      recipes on any platform — all of that validation happened manually
      on omicron/kappa/locally, not in CI.
- [ ] Publish to a real channel (prefix.dev or anaconda.org) once verified
- [ ] Reproducibility: SOURCE_DATE_EPOCH, compare two builds bit-for-bit

## Milestone 5 — build.zig end state

- [ ] Inventory of configure decisions from milestones 1–3 (the spec)
- [ ] Prototype `build.zig` compiling src/main + src/nmath as a static lib
- [ ] Feature flags in `zig build` mirroring pixi features
- [ ] Replace gnuwin32 + autoconf with the single build graph

## Parked / open questions

- linux-aarch64: no flang on conda-forge → gfortran; no uutils → GNU coreutils.
  Revisit both as conda-forge catches up.
- uutils-coreutils 0.9.0 is old (2022); if a GNU-ism bites during `make`,
  switch unix targets to GNU `coreutils` and note it here.
- Docs (`make docs`) need texinfo/TeX — deliberately out of scope for now;
  add `texinfo` from conda-forge later if manuals are wanted.
- zig version pinned at 0.16.*; bump deliberately and re-run `check`.
