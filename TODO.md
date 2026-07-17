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
- [x] Relocatable installs (2026-07-17, linux): `pixi run install` now
      produces a self-contained dist/ tree via scripts/relocate.sh —
      conda libs bundled into R_HOME/lib (ldd walk), $ORIGIN rpaths
      (patchelf), launchers derive R_HOME from their own location,
      Rscript CLI emulated via the R launcher (the binary hard-embeds
      its build path and ignores env R_HOME), etc/ldpaths reduced,
      zig shims bundled + Makeconf rewritten to $(R_HOME)-relative.
      Verified: moved copy runs numerics + cairo png + R CMD SHLIB with
      a scrubbed environment and the original tree deleted. TODO:
      macOS (install_name_tool) and Windows equivalents; headers for
      compiling against bundled libs are NOT shipped (packages needing
      e.g. zlib headers still want an env)
- [ ] Install recommended + test compiling a real CRAN package (Rcpp,
      data.table) against this R — proves the Makeconf-as-toolchain-contract
- [ ] Package the result as a conda package / pixi-installable artifact
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
