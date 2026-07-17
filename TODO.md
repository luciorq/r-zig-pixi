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

- [x] Both pixi environments solve and install on real Windows 11 (kappa,
      bare machine + pixi); zig and flang binaries run from the env
- [ ] ABI decision forced: conda-forge's win-64 flang targets
      **x86_64-pc-windows-msvc**, not MinGW — either drive it with
      `--target=x86_64-pc-windows-gnu` (runtime libs are MSVC-built, may
      not work) or accept an MSVC-ABI R (breaks MinGW assumption below)
- [ ] R's autoconf build does not run on Windows; drive `src/gnuwin32`
      Makefiles instead with:
      - `zig cc -target x86_64-windows-gnu` as the MinGW-compatible CC
      - conda-forge `flang` for Fortran
      - `m2-bash`/`m2-*` for the shell layer, conda-forge `make`
- [ ] Decide UCRT vs MSVCRT explicitly (UCRT; matches modern R ≥ 4.2 design)
- [ ] Untangle Rtools assumptions hardcoded in `src/gnuwin32/MkRules.*`
- [ ] Wire the same pixi tasks (`configure`/`build` dispatch per-OS in scripts)

## Milestone 4 — Distribution & ecosystem

- [ ] `openblas` pixi feature (external BLAS/LAPACK instead of R-internal)
- [ ] Recommended packages (`--with-recommended-packages`) once base is stable
- [ ] Relocatable installs: Makeconf currently records absolute workspace
      paths to the zig shims; replace with `$(R_HOME)`-relative discovery
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
