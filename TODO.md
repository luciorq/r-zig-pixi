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
- [ ] `pixi run check` (R's own regression suite) green
- [ ] CI: GitHub Actions job for linux-64 starting from bare runner + pixi

## Milestone 2 — macOS (osx-64, osx-arm64)

- [ ] Validate scripts on real macOS hardware (nothing here is macOS-tested yet)
- [ ] Confirm `zig cc` links Mach-O with `-Wl,-rpath` as written, or add
      per-OS LDFLAGS branch in `scripts/configure-r.sh`
- [ ] Confirm gfortran (explicit conda-forge pkg) FLIBS detection under
      configure; watch for `-lgfortran` resolving into the pixi env, not
      a host toolchain
- [ ] Confirm cairo-only graphics (quartz intentionally dropped) and tk
      from conda-forge work headless
- [ ] Swap gfortran → flang when conda-forge ships flang for osx-*

## Milestone 3 — Windows (win-64)

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
