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
      Contract test now asserts getDTthreads() > 1 on every platform.

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
      - TODO: macOS (install_name_tool + codesign — signing is mandatory
        on arm64, not optional); headers for compiling against bundled
        libs aren't shipped (packages needing e.g. zlib.h still want zig
        + an env, or system headers)
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
- [ ] macOS conda recipe + standalone package (once macOS staging exists)
- [ ] Windows conda recipe (gnuwin32 has no `make install`; recipe/build.sh
      would need the same install-r.sh Windows branch)
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
