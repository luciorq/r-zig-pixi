# Brief: an on-demand "stress" suite of hard-to-build R packages for r-zig

## Who you are working for, and the rules

- Repository: r-zig-pixi (R 4.6.1 built with Zig 0.16 under pixi). Main branch of work:
  `feat-no-host-paths`. Plan of record: `.github/devdocs/feat-no-host-paths/PLAN.md`.
  Read "Tiers", "Simplicity review and phase F" (F1–F3c, F1.6), and the F1.5/F3b records first.
- **Never `git commit`, `git push` or open PRs.** The user does all of that. When something is
  ready, hand over the exact `git add …` / `git commit -m …` / `git push` commands.
- Work in a **git worktree** on a new branch (suggested: `feat-stress-suite`) so the main tree
  stays clean. Don't touch the regular CI legs or the contract test.
- The guiding principle is simplicity: one build path, as little OS- or shell-specific trickery as
  possible, one unified toolchain. Prefer one small entry script plus a data file over many
  per-OS scripts.
- Test hosts, for testing only, over SSH: `omicron` (macOS arm64; can run osx-64 under Rosetta)
  and `kappa` (Windows 11). See the user's auto-memory "Test servers" for key loading and
  gotchas (cmd's `%VAR%` parse-time expansion; omicron's flaky link means you run long jobs
  with `nohup` and push big files with `rsync --partial`). Delete every scratch dir and file you
  create on those hosts when done.
- Document everything you learn (a record in the brief's folder or in PLAN.md, as the user prefers).

## Goal

An **opt-in, on-demand** test that compiles known hard-to-build CRAN/Bioconductor packages with
r-zig's toolchain and reports, per package × OS × distribution, whether each builds and loads.
It must never gate regular commits or CI. It's a diagnostic and a stress test.

## What r-zig is today (what you are testing)

- The compilers are **rzig**, one static Zig binary, installed in `R_HOME/bin/toolchain` as
  `zig-cc`, `zig-cxx`, `zig-fc`, `zig-ar`, `zig-ranlib` (Windows also `gcc.exe`/`g++.exe`).
  Makeconf names only `$(R_HOME)/bin/toolchain/...`. Makeconf's CPPFLAGS/LDFLAGS are **empty**.
  rzig adds the environment's `-I`/`-L` itself (Windows: `-idirafter`), and on a conda env an
  rpath. It uses R's own environment (from its own location) plus an optional
  `R_ZIG_EXTRA_ENV=<env root>`, and it **never reads CONDA_PREFIX**.
- C++ links a **static libc++** (LLVM's), everywhere. The flang runtime is linked statically.
  macOS deployment target is 13.0, and Linux's glibc floor is 2.17.
- Distributions: the dev/standalone tree (`pixi run build` → `dist/R-4.6.1-<variant>-zig`), the
  conda packages (`r-zig-slim` + `r-zig-toolchain`, built by `pixi run -e pkg conda-package`), and
  the wheels (minimal variant only, no Fortran).
- Diagnostics: `RZIG_TRACE=1` prints rzig's own path, the environments it chose and the final zig
  command. `RZIG_PRINT_ARGV=1` prints the command without running it. Use
  `R CMD config --no-user-files …` to read Makeconf without the user's Makevars.

## The package list (start here; adjust with evidence)

Keep the list in a data file (e.g. `stress/packages.tsv`) with these columns: package, group,
OSes, system deps (conda names), extra env vars, timeout, expected status and a note.

1. **Heavy pure C++ (compiler, memory and time stress):** duckdb; StanHeaders + rstan; lme4
   (RcppEigen); one RcppArmadillo-heavy package.
2. **C++ across a library boundary (the C++ ABI risk):**
   - geospatial: **sf, terra, lwgeom** (GDAL/GEOS/PROJ), and **gdalraster** if useful;
   - **arrow**: default prebuilt libarrow, and from source with `LIBARROW_BINARY=false`
     (needs cmake);
   - RcppParallel (TBB);
   - protolite (protobuf);
   - optionally V8.
3. **C libraries from the environment (checks rzig's env rule, no ABI risk):**
   curl, xml2, openssl, magick, gert (libgit2), units (udunits2), ragg, systemfonts and
   textshaping (freetype/harfbuzz/fribidi), hdf5r, ncdf4, gsl, Rmpfr (MPFR/GMP), RPostgres
   (libpq), and the geos R package (GEOS C API).
4. **Own build systems and bundled third-party code:** nloptr (cmake via `R CMD config CC/CXX`),
   s2 (bundled abseil), igraph, stringi (bundled or system ICU), qs2/fst (zstd), and Bioconductor's
   Rhdf5lib.

Expectations, all **untested** and to be confirmed or refuted:

- groups 1 and 3: mostly green on Linux and macOS;
- Windows: rougher (rwinlib or Rtools-specific downloads; big-object issues such as duckdb's
  `-Wa,-mbig-obj`);
- group 2: the most likely failures. On Linux conda-forge's C++ libraries (GDAL, arrow, TBB,
  protobuf) are built with **libstdc++**, while r-zig's packages use **static libc++**. On macOS,
  conda's are built against a *shared* libc++, a second runtime.

Classify each failure as one of:
- toolchain bug (fix it in rzig);
- C++ ABI mismatch;
- missing system dependency;
- network or upstream (e.g. GitHub `blob/…?raw=true` URLs that returned 503 transiently on
  2026-10-02);
- package-specific.

## Deliverables
1. **One entry point**, e.g. `pixi run -e stress stress [pkg ...]`, with a `stress` pixi
   environment or feature that provides the system deps (conda-forge: gdal, geos, proj, udunits2,
   cmake, tbb-devel, libprotobuf, libgit2, imagemagick, hdf5, netcdf, gsl, mpfr, gmp, libpq, …).
   The script:
   - installs each package from source (`type = "source"`) into a fresh library, with a
     per-package timeout and log;
   - loads the package and runs one tiny smoke call;
   - records status, time and the first error line.
   It runs against:
   - **the dev/standalone tree**, with `R_ZIG_EXTRA_ENV` pointing at the stress env;
   - **a conda env** with `r-zig-slim` + `r-zig-toolchain` (from the local `dist/conda` channel
     or prefix.dev `universe`) plus the system deps. This is the realistic target for the
     geospatial stack.
2. **A report**: Markdown plus JSON per run (package × OS × distribution → status, minutes,
   classification, log path). In CI, also write it to `$GITHUB_STEP_SUMMARY` and upload logs as
   artifacts.
3. **A manual CI workflow** (`.github/workflows/stress.yaml`, `workflow_dispatch` only), with
   inputs for:
   - OSes (ubuntu-latest, ubuntu-24.04-arm, macos-latest, macos-15-intel, windows-latest);
   - the package list or group;
   - the distribution (tree or conda).
   Rules for the workflow:
   - generous timeouts;
   - `fail-fast: false`;
   - it never runs on push or PR;
   - it reuses `pixi run build` (or `conda-package`) to produce the R it tests.
4. **Documentation**: what it is, how to run it locally and in CI, how to read the report, and
   the first round's results with a short analysis of each failure.

## Separate repo or worktree?

**Recommendation:** start as a worktree branch inside r-zig-pixi, because it needs the build and
packaging tasks. Keep everything under one `stress/` folder plus one workflow file. Design the
entry script so it only needs "an R with r-zig's toolchain plus an environment of system libs",
so the suite can later move to its own repository that consumes **published** artifacts:

- conda packages from prefix.dev `universe`;
- the wheel;
- the standalone archive.

Note that build 4 of r-zig-slim/r-zig-toolchain is not published yet (the channel has build 3,
which predates rzig). A separate repo makes sense only once the rzig builds are published.

## Known gotchas

- omicron has CRAN's R installed, so always install from source there; CRAN macOS binaries load
  CRAN's libR and crash.
- omicron runs CrowdStrike Falcon. rzig is re-signed with `codesign` at build time for that
  reason. If an unsigned helper binary vanishes, that's the cause.
- On Windows, R starts programs by 8.3 short paths (rzig handles it); MSYS process spawning on
  windows-latest has hung builds before, so use per-package timeouts. GitHub `blob/…?raw=true`
  downloads (pak's embedded zip, rwinlib) have returned 503 transiently, so add retries.
- CRAN mirror hiccups happen: retry downloads with bounded attempts.
- Don't put apostrophes inside single-quoted `R -e '…'` programs in shell scripts.
- Hosted runners have limited RAM and CPU. duckdb and rstan are long, so limit parallel builds.
- `R CMD config` reads the user's Makevars; use `--no-user-files` when checking Makeconf values.

## First milestone

Run groups 1–4 on linux-64 against the dev tree, write the report, and classify every failure.
Then do the same on omicron (osx-arm64), and then on kappa (win-64). Stop and summarise for the
user before attempting any toolchain changes (for example, a libstdc++ mode for C++ boundary
packages). That's a design decision for the user.

