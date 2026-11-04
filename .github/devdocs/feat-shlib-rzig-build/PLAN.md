# feat-shlib-rzig-build — R CMD SHLIB through rzig build

**Status (2026-10-15).** Worktree `wt/feat-shlib-rzig-build`, branch
feat-shlib-rzig-build, stacked on feat-standalone-toolchain phase 4,
which is not committed yet: main d11dee1, plus phase 4's changes (the
baseline, "Sequencing"), plus this work. Steps 0 to 4 of the plan
(plan/SHLIB-IMPLEMENTATION.md, section 2) are done, and so are the
fixes for a review's eight findings ("Review fixes") and for the first
host round's six ("Host fixes, round 1"). Tested on linux-64 (gamma),
osx-arm64 (omicron) and win-64 (kappa), each with conda-forge's and
upstream zig ("Tested"). Left for after the push (step 5, the user's):
CI with the `full-ci` and `upstream-zig` labels, and the stress
dispatch (J). Not committed: the user commits. pixi.lock is main's,
unchanged, sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96.
Build number 8: no bump, the user's decision of 2026-10-19
(feat-standalone-toolchain PLAN.md, B14's amendment). It was 10 (B14 a:
the one after phase 4's 9); SHLIB routing now publishes with the bump
that comes with phase 7's merge, and main does not publish until then
(build.yaml's `CONDA_PUBLISH`).

The plan, amended from two critiques, is plan/SHLIB-IMPLEMENTATION.md,
and plan/CRITIQUE.md records how each critique point was checked (as
phase 4's are in feat-standalone-toolchain/phase4/). The plan copy
carries two dated amendments from the review (r-1: Cc4 item 4 and risk
15); the rest is the plan as implemented, with the departures listed
under "What changed". Tags: (Cc<n>), (Cg<n>) and (Am<n>) are
CRITIQUE.md's; the letters A to M are the plan's open points (its
section 10), answered below.

## Why

- feat-zig-pkg-build N2 put `R CMD SHLIB` out of scope, with "route
  `R CMD SHLIB` through rzig build (it would also clear pak's probe), or
  give it a preflight" as a later item (its PLAN.md, "What the
  build-tools group is for").
- Until now every run-time compile went through make: Rcpp's
  `sourceCpp()`, `cppFunction()` and `evalCpp()`, inline, TMB, knitr's
  engines, and pkgbuild's `has_compiler()` probe, which pak runs before
  every source package. So on base + compilers, with no make, pak
  installed no compiled package, tier 1 included (feat-zig-pkg-build
  fact 8).
- The session's record of 2026-10-14 named this as the next item after
  phase 4, and the user asked to start the next phase while phase 4
  waits for its commit. It is taken before phase 5 (zig in the compilers
  group), the records' next phase (A; feat-standalone-toolchain
  TODO.md).

## Decisions (the user, 2026-10-14/15: "Follow with the recommended")

Every open point of the plan's section 10 takes its recommended option:

| point | answer |
|---|---|
| A | (a) SHLIB routing now, stacked on uncommitted phase 4, then phase 5 |
| B | (iii) one hook in `.shlib_internal` with two modes: run_shlib names the package (`pkg =`), the top-level `.rzig_build` holds every rule; 0013 regenerated as the one rzig-build patch, no 0014 |
| C | (a) `--dry-run`: R's "make cmd is … make would use" text, then rzig's compile lines and its link in `make -n`'s `if test … fi` form; rzig's exit 3 gives `make -n` as before, including pkgload's and RStudio's injected single quote |
| D | (a) objects in the build root, every source compiled each call, zig's cache serving what is unchanged; each new TMB model name compiles libTMB.cpp again (measured: "Measurements") |
| E | (a) `--clean` and `--preclean` act on the make path only |
| F | (a) a call that needs make, with no make: rzig checks as the install preflight (`check.groupsFor`), names every missing group in one stop, compilers first, with the reason, and exits 127 |
| G | (a) one switch, `R_ZIG_PKG_BUILDER=auto\|zig\|make`, for both modes, read in `.rzig_build` only |
| H | (a) no change to 0010 (`R CMD config`) or to Windows `has_rtools()`; the README says so, and TODO.md gets `R CMD config` through rzig |
| I | (a) no symbols.rds on the rzig path, as for tier-1 packages |
| J | (a) a dispatch with trace on the PR's branch: g1, Rcpp's smoke with `showOutput = TRUE`, plus the groups of the rows whose configure scripts run SHLIB (the grep found g2's RcppParallel) |
| K | (a) document it: pkgbuild, pak, devtools and cpp_source's dependencies install from source with the build tools once |
| L | (a) document it: pak needs r-zig-compilers even for R-only source packages, and `install.packages()` is the base-alone path. No upstream report (the user's standing rule) |
| M | (b) SHLIB mode's build root under `R_SESSION_TMPDIR`, else beside the output; a kept one beside the output ("Review fixes", code-1); package mode unchanged; on Windows, whose R sets no `R_SESSION_TMPDIR`, `.rzig_build` names `tempdir()` for the call ("Host fixes, round 1") |

feat-zig-pkg-build's decision 2, "R gets one hook before `run_shlib`",
holds in spirit: the one hook now sits in `.shlib_internal`, which
run_shlib calls (a dated note there).

## What it delivers

- **base + compilers, no make, on every OS:** every `R CMD SHLIB` whose
  inputs are declarative (no Objective-C, no Makevars rules,
  conditionals, `$(shell)` or `include`): Rcpp's `sourceCpp()`,
  `cppFunction()` and `evalCpp()` (and the macOS OpenMP plugin's
  `--dry-run` parse), inline's C, C++ and Fortran, `TMB::compile` for a
  TMB installed by this build, knitr's engines, renv's `renv.c`, rstan's
  `stan_model` compile. Where they are installed: pkgbuild's
  `has_compiler()`, so `check_build_tools()`, pak's gate, remotes'
  `has_devel`, devtools' compile_dll, and `cpp11::cpp_source`.
- **Still the build tools:** the shapes that need make (exit 3: the plan's
  section 0 list, plus a single quote in argv's linker words, a ready
  `.o` with no source, and a damaged tree with no
  `share/zig/rpkg/build_t1.zig`); pkgload's compilation database;
  `R CMD config` (rstan on macOS, H); installing pkgbuild, pak, devtools
  and cpp_source's dependencies from source (K: processx has Makevars
  rules, ps and pak have configure scripts).
- **Differences from make** (risk 1): no `.o` beside the sources (`.mod`
  files stay, as under make); the "using … compiler" lines go to stdout;
  no "using C++NN" or "using SDK" lines; no make echo of the compiles;
  compiler warnings under zig build's step headings; the library is
  relinked on every call. `R_ZIG_PKG_BUILDER=make` restores make where
  the build tools are installed.

## Sequencing (stacked on phase 4)

- The phase-4 baseline: `wt/phase4-base.diff`, sha256
  d95a00aeb1ccfc9d87d1ee4e633bb7676a471d6d557004260d64b54f4a74fcb3 (the
  tracked files), and phase 4's 5 untracked files, whose sorted
  `sha256sum` list hashes to
  1270a566469542d13e2d410672298bf416195d01e4e56bc7094adcb3a9b6c1e8 in
  the phase-4 worktree. Both held before and after every step. This
  work changes one of those untracked files (recipe/test-compilers.R,
  step 3), so the hash in this worktree differs from the phase-4
  worktree's.
- The SHLIB delta is this worktree against a scratch tree built from
  the baseline (`git archive d11dee1`, the diff applied, the untracked
  files copied in).
- When the user commits phase 4: a mixed reset of this branch to that
  commit keeps the working tree; `git diff` must then match the SHLIB
  delta file for file (the plan's section 1 has the commands).
- Its own PR, with base feat-standalone-phase4 until phase 4 merges,
  then main.

## What changed

**rzig (zigbuild/tools/rzig/), step 1:**
- pkgplan.zig: `Shlib`, `Options.shlib` and `Options.warn_cxx_std`;
  `makevarsIn` (factored out of `classify`, unchanged behaviour);
  `classifyShlib` (an Objective-C file, or a single quote in the linker
  words, needs make: Cg9, Cc2); `plan()` in SHLIB mode: argv's files in
  place of the directory listing, no `R_PACKAGE_NAME`, Makevars texts
  without `src/` (Cc11), output = the basename with `SHLIB` = the output
  as given, OBJECTS in argv order with directories, a command-line
  `PKG_LIBS`, the macOS install name = the `-o` path as given (Cc5),
  as `-Xlinker -install_name -Xlinker <output>` ("Review fixes"),
  Windows BASE = `basename $(SHLIB) .dll` (Am4). Source lookup accepts
  absolute paths and keeps `.SUFFIXES` order. H8 in both modes: the
  literal `file.exists("Makevars")` test for `P_FCFLAGS`. The
  "Unknown C++ standard" warning only where `warn_cxx_std` is set (the
  install preflight; R prints its own in the hook's path). A toolchain
  check for every language the plan compiles.
- pkgbuild.zig: `--shlib`, `--output`, `--pkg-libs`, `--dry-run` and
  `-- <file>...`; usage exit 2 for mixed modes; `runShlib` (decide, the
  needs-make stop through `check.groupsFor`, `--plan-only`, `--dry-run`
  with `printCommands` in `make -n`'s form, every word
  `shellwords.quote`d, the compilers check (`check.shlibCompilers`,
  "Review fixes"), the root `.rzig.<16 hex>` under `R_SESSION_TMPDIR`
  else beside the output, removed unless kept, a kept one beside the
  output); the shared tail `zigBuild` for both modes; `missingRoot`: no
  build_t1.zig is exit 3 in both modes (Cc8).
- check.zig: `pub fn groupsFor`, taken out of `packageIn`, which calls
  it unchanged; `shlibCompilers`, the compilers check with its own
  answer for a zig that is not R's ("Review fixes").
- shellwords.zig: `pub fn quote`, with a round-trip test.
- main.zig: the usage line.
- parity-test.sh: 12 SHLIB cases (an `shtree` R_HOME whose Makeconf has
  no LIBR).

**rpkg (zigbuild/rpkg/build_t1.zig), step 1:** an absolute source is its
own file input; with more than one Fortran source, each Fortran compile
depends on the one before it, in OBJECTS order (Cc3), for tier-1
packages too. Without the chain, 3 of 5 module builds at `-j 8` failed
("Cannot parse module file for module 'mod_m'"); with it, 0 of 5
(`shlib/fix/fchk/`: run.sh, summary.log, nochain.out.1-5 and
chain.out.1-5; each run with no `.mod` left and a fresh rzig cache, so
no Fortran compile came from zig build's cache).

**R, patch 0013, step 2:** regenerated as the one rzig-build patch (B
iii). The top-level `.rzig_build(pkg, files, output, pkg_libs, use_lto,
use_C, debug, dry_run)` holds every rule (the builder switch, rzig's
arguments, the jobs, the user Makevars, the spawn); `.shlib_internal(args,
pkg = NULL)` builds a `files` vector in its argument loop and asks
`.rzig_build` before its make path and in the dry run; run_shlib calls
`.shlib_internal(args, pkg = pkg_name)`; 0013's `rzig_build` closure is
gone; the patch_rpaths and allfiles hunks are kept (the allfiles
comment names `.rzig_build`). Three changes from the plan's text:
`flush(stdout())` before the spawn (spawnWait does not flush, as
system() does, and Rcpp's macOS OpenMP parse reads the order); a
`message()` text that printed `character(0)` in SHLIB mode
(`if (!is.null(pkg)) … else ""`); `--c-std` only when `use_C` is not NA
and not empty. After the review, a fourth: no `identical(status, 2L)`
make fallback (r-1, "Review fixes"). All 13 patches apply to the pristine tarball with
`patch -p1 -f -F0`, no offset, fuzz or reject.

**Tests:**
- pkg-parity.sh (step 2): a SHLIB section after tier 1. Each shape
  (probe, sourcecpp, cpp11, tmb in process, fortran, fclink, fmod at
  `MAKEFLAGS=-j8`, pkglibs, subdir; macOS also `otool -D`) runs with the
  default builder and with `R_ZIG_PKG_BUILDER=make`: the trace line, no
  make recipe on the rzig run and some on the make run, identical
  `argv_of` (at least 2 lines each), identical non-empty exports, the
  library loads, nothing beside the sources; the shared runner reused.
  Also pkgload's injected dry run (rzig declines, stdout identical to
  make's, 19 of 19 compiles extracted), the plain dry run through rzig
  (19), `R_ZIG_PKG_BUILDER=zig` on a rule, two calls at once, Windows'
  H8 package, and tier 3 asking rzig once.
- verify-bundle.sh: the make SHLIB shapes (scenario 2 unix, Windows
  scenario 3) take `R_ZIG_PKG_BUILDER=make`, the make reference (step
  2); scenario 1's base-alone SHLIB check and scenario 2's "R CMD SHLIB
  with no make" block on every OS (step 3): probe, sourceCpp with
  `check_minos` on the kept root's object, Fortran, cpp11, TMB in
  process, `--dry-run`, OpenMP where Makeconf has it, and the rule stop.
- contract-test.sh: the evalCpp report line (step 2); a no-make program
  on the base tree with cpp11, callr, processx and R6 added to the
  installs (step 3): Rcpp's cppFunction (with a C++ exception) and
  evalCpp, the macOS OpenMP plugin's parse, cpp11's SHLIB call through
  callr, pkgbuild's `check_build_tools()`, Windows' `has_rtools(debug =
  TRUE)` printed, and a pak local install.
- recipe/test-compilers.R and test-preflight.R (step 3): the conda
  packages' SHLIB checks, with and without the compilers.
- wheel-test.sh (step 3): r-zig alone, + r-zig-compilers (PyPI
  ziglang, no make), + r-zig-build-tools (the rule through the wheel's
  make).

**Texts and data, step 4:** README.md (the group bullets, the checks,
pak, Windows' Rtools, TMB; the wheel paragraph); make-wheel.py's
descriptions of r-zig, r-zig-compilers and r-zig-build-tools;
pixi.toml's contract comment; recipe.yaml's number (9 → 10) and its
history line (2026-10-19: back to 8, with one "8 stays" line for phases
4 to 6); stress.yaml's `builder` description and stress/README.md;
stress/packages.tsv: Rcpp's smoke calls `cppFunction(…, showOutput =
TRUE)` (step 3), and the Rcpp and rstan notes.

## Review fixes (2026-10-15)

A review of steps 0 to 4 confirmed eight findings; each is fixed at its
root (the code cites the tag, `[shlib-<id>]`):
- **code-1:** a kept SHLIB root (`--keep-root`, `RZIG_KEEP_ROOT=1`) was
  in R's session directory, which R CMD SHLIB's own R removes when it
  exits, so the "kept in" path was gone. A kept root now goes beside the
  output; a removed one stays in the session directory (M b). The tests
  that read a kept root (pkg-parity's two calls at once, verify-bundle's
  sourceCpp shape) look there, and verify-bundle's shape now runs `R CMD
  SHLIB` itself.
- **code-3:** the macOS install name went as `-Wl,-install_name,<output>`,
  which the driver splits at a comma in R CMD SHLIB's output path
  (`a,b/x.so`: "unsupported linker arg: b/x.so", `shlib/fix/instname.log`).
  It is now `-Xlinker -install_name -Xlinker <output>`; pkg-parity's
  argv normalisation follows.
- **r-1:** `.rzig_build` took exit 2 as "usage, use make", and an rzig
  that Ctrl-C ends reads as 2 (R's raw wait status, sys-unix.c), so an
  interrupted build ran make (package mode too, where phase 4 failed).
  Only 3 is make now; 0013's header and risk 15 name SIGINT beside
  SIGQUIT.
- **r-2:** R CMD SHLIB has no install preflight, so a zig that is not
  R's (say a global 0.17) failed in build_t1.zig's compile where make,
  with zig-cc, built. `rzig build --shlib` now makes the compilers check
  before the build root (`check.shlibCompilers`): a missing zig or
  flang is 127 with the compilers group's text; a zig that is not R's
  is 3 when the build tools are there (R's make path, as before), else
  1 with the line and the compilers group's text. `R_ZIG_NO_PREFLIGHT`
  skips the version comparison, as for the preflight.
- **tests-1:** no test checked that a root beside the output is removed:
  parity-test's `no_root` now takes the output's directory (case 8),
  case 12 checks after each build, and the unit test no longer leaves
  `RZIG_KEEP_ROOT` set over its beside-the-output loop.
- **tests-2:** pkg-parity's Windows "two roots" could not fail (two R,
  two session directories); with code-1 both kept roots are beside the
  outputs in one directory, and the check asserts one parent and two
  names. The step-3 concurrency measurement is reworded ("Measurements").
- **tests-4:** contract's main evalCpp line said "with no make" on the
  compile tree, which has make on PATH; it now says what it shows, and
  points at the no-make program.
- **tests-5:** the two unlogged claims are measured: GCC 13 rejects TMB's
  `precompile(all = TRUE)` as zig does
  (`shlib/step0/all-true-check/gcc.log`), and the Fortran chain's 3 of 5
  and 0 of 5 (`shlib/fix/fchk/`).

## Host fixes, round 1 (2026-10-15)

The first round on omicron and kappa (`shlib/omicron/`, `shlib/kappa/`)
found six things; each was confirmed in the code and fixed at its root.
No upstream report (L).
- **macOS `a.o`:** `zig cc --version` and `zig c++ --version` write an
  empty `a.o` in the working directory on macOS (conda-forge's zig and
  upstream 0.16.0; linux's and flang write none). rzig build's "using C
  compiler" line (pkgbuild.zig's `reportCompilers`) left it beside R CMD
  SHLIB's sources, R's `make compilers` did too, and Rcpp's macOS OpenMP
  plugin in its caller's directory; on make's path it stood for a
  source named `a.c` or `a.cpp` (pkg-parity's cpp11 make run: "failed to
  parse TBD file: NotLibStub ... src/a.o"; old behaviour on main's make
  path too). rzig's driver (compiler.zig `argv`) adds `-c` to a macOS
  call with `--version` and no compile-only flag: zig prints the same
  text and writes nothing (omicron: `-o x`, `-fsyntax-only`, `-x c` still
  write one; `-v`, `-dumpversion`, `-print-*`, `-###` never do). "Nothing
  left beside the sources but .mod" (M b, risk 1) now holds on macOS.
- **Windows `R_SESSION_TMPDIR`:** Windows R never sets it
  (src/main/sysutils.c sets it `#ifndef Win32`), so every Windows SHLIB
  root went beside the output, removed after a normal run but left by a
  killed one. 0013's `.rzig_build` sets it to `tempdir()` on Windows for
  rzig's call, the directory unix R names to every child, and restores
  the caller's value; pkgbuild.zig's `sessionDir` comment says so.
- **Windows "Exit code was 127":** R's Windows `system()` reads exit 127
  as a failed launch (src/gnuwin32/run.h `NOLAUNCH`) and warns after
  rzig's own text (no zig; needs make, no make). `.rzig_build` muffles
  that one warning, its translated text, so a launch that really failed
  keeps its own ("'...' not found").
- **contract, Windows no-make program:** Rscript crashed (0xC0000005)
  at exit after `pak:::remote()`: cli's exit-time stop of its tick
  thread `strcmp()`s `getenv("PROCESSOR_ARCHITECTURE")` unchecked (cli
  3.6.6, src/thread.c), and `env -i` had dropped the variable, which
  Windows always sets. contract-test.sh's Windows `nm_env` passes it.
- **pkg-parity, Windows pkgload:** the compiler list came from `R RHOME`
  (backslashes), the `make -n` lines from forward slashes, so 0 of 19
  lines were kept; `tr '\\' /` as verify-bundle does (pkgload's
  `R.home()` has forward slashes).
- **verify-package, Windows Fortran SHLIB with no make:** the copied
  `flang.exe`'s `-print-resource-dir` is the copy's, holding no
  `libflang_rt.runtime.a`, so rzig dropped `-lflang_rt.runtime`
  (flang_rt.zig) and `fs.f`'s I/O was undefined at the link.
  verify-bundle.sh copies the runtime archive where the copy looks.

## The stable interface (Cc4)

A TMB installed by this build keeps this build's `.shlib_internal` body
(TMB.R copies it at install), which calls `.rzig_build` by name with R's
parsed values. So:
- `.rzig_build`'s arguments (`pkg`, `files`, `output`, `pkg_libs`,
  `use_lto`, `use_C`, `debug`, `dry_run`) and `rzig build --shlib`'s
  flags (`--output`, `--pkg-libs`, `--use-lto`, `--c-std`, `--debug`,
  `-j`, `--dry-run`, `--plan-only`, `--` files) are added to, never
  removed or renamed;
- a missing `.rzig_build` is the make path: a changed interface
  degrades to make, it does not fail. rzig's usage exit 2 is a failure,
  as every status but 0 and 3 is: an rzig that Ctrl-C ends reads as 2
  too, and make must not start then ("Review fixes", r-1). rzig and
  `.rzig_build` come from the same R, so a usage error is a bug, not an
  older snapshot's interface.

A TMB installed by an r-zig build without SHLIB routing (universe's
build 8 or earlier: SHLIB routing first publishes with phase 7's bump)
keeps the pristine body, and so make, until it is reinstalled (risk 3;
the README says so).

## Measurements (gamma, linux-64, 2026-10-15)

16 cores, conda-forge zig 0.16.0 (clang 21.1.8) unless stated. Cache
growth is `du -sb` of `$ZIG_GLOBAL_CACHE_DIR/o`. Data:
`shlib/step0/tmb-step0.tsv` and `shlib/step3/step3-measurements.tsv` in
the session's scratch.

**TMB 1.9.25, step 0 (make, today's path, serial make, `-O2`):**

| what | s | cache |
|---|---|---|
| libTMB.cpp for a new model name, zig's libc++ already cached | 40.1 | +4.0 MB |
| libTMB.cpp again, same model name (a zig cache hit) + relink | 0.4 | +0 |
| a model with the precompiled library (make reuses libTMB.o) | 6.3 | +0.3 MB |
| a model without it (`libtmb = FALSE`) | 24.2 | +1.9 MB |
| the first compile on a fresh zig cache (libTMB.cpp + model + link) | 61.5 | +11.9 MB, of which ~7.6 MB is zig's one-time libc++ |

libTMB.o is 4.2 MB. TMB's default `precompile()` (`all = TRUE`) does
not compile with TMB 1.9.25 + RcppEigen 0.3.4.0.2: `invertSparseMatrix`
is undeclared at density.hpp:904, because TMB.hpp includes
precompile.hpp before its `using tmbutils::invertSparseMatrix`. zig
c++ and GCC 13 (Ubuntu's /usr/bin/g++ 13.3, the same flags) both reject
it, so it is TMB's, not r-zig's (`shlib/step0/all-true-check/zig.log`
and `gcc.log`). Every measurement uses `precompile(all = FALSE)`. No
upstream report (L).

**TMB on this build, step 3 (rzig build, parallel zig build):** 5 of 5
compiles show `rzig build: R CMD SHLIB, tier 1`, even with make on PATH;
no `.o` beside the models, no libTMB.o in TMB's `libs/`; both fits match
step 0.

| what | s | cache |
|---|---|---|
| zig's libc++ warmed first (a small C++ file) | 13.2 | +7.6 MB |
| model A, first (libTMB.cpp with A's flags + A + link) | 41.6 | +4.3 MB |
| A again | 0.5 | +0 |
| B, a new model name | 45.4 | +4.3 MB (11.9 → 16.2 MB) |
| B again | 0.5 | +0 |

So under D (a) each new model name costs about 45 s and about 4 MB of
zig cache on linux-64, where make reused one libTMB.o (6.3 s). Edits to
one model name stay at a zig cache hit.

**The first probe** (`pkgbuild::has_compiler()`), risk 5:

| case | conda-forge zig | upstream zig |
|---|---|---|
| rzig's build-runner removed, zig's cache warm | 4.2 s | 2.5 s |
| warm | 0.5 s | 0.4 s |
| fresh rzig and zig caches | 10.6 s | 7.8 s |

**Concurrency (SZ H2, Cc12):** four `R CMD SHLIB` at once in one
directory (`parallel::mclapply`, `RZIG_KEEP_ROOT=1`): all exit 0, all
load, four distinct roots, 0.45 s, nothing beside the sources. Those
roots were in four child R's session directories, distinct by
construction, so that run shows only that the calls do not collide
("Review fixes", tests-2). Unique roots in one directory are shown by
parity-test's case 11 (two calls at once, kept roots beside the
outputs), pkg-parity's unix case (`mclapply` in one R) and its Windows
case (two `R CMD SHLIB`, kept roots beside the outputs).

**One real `cpp11::cpp_source(code = …)`** (Cc1) on the base tree under
`env -i`, PATH holding only sh and flang, zig through `ZIG_BIN`, its
Suggests installed with the build tools: OK in 2.3 s, through rzig
build.

**pak on base alone (L):** pak's probe is FALSE (with `debug = TRUE`
it shows rzig's compilers text); `pak::local_install()` of an R-only
package stops with "Could not find tools necessary to compile a
package", and `install.packages()` installs it. Confirmed: pak needs
r-zig-compilers even for R-only source packages.
- `pak::local_install(dependencies = FALSE)` needs no network: it works
  with `http(s)_proxy` at a closed port (pak warns "Failed to update
  system requirement mappings"). `unshare -n` is not permitted on gamma.
- With dpkg-query off PATH on Ubuntu, pak's worker spun at 100% CPU and
  never returned (pkgdepends' system-package lookup; seen three times);
  `PKG_SYSREQS_LOOKUP_SYSTEM=false` avoids it, and contract's no-make
  program sets it. Upstream behaviour, no report.
- pak's install runs `R CMD build`, which runs `cp` on unix (Windows
  uses `file.copy`), so contract's no-make PATH holds sh, cp and flang.

**J's grep (Cg14)** of the configure scripts in the 37 compiled rows'
CRAN tarballs: RcppArmadillo (g1, configure.ac's OpenMP probes) and
RcppParallel (g2, tools/config/configure.R, its macOS probe) run
`R CMD SHLIB`; qs2 and stringi only name SHLIB variables. The dispatch
groups: g1 and g2.

## Tested

### linux-64 (gamma)

Each step's tests passed on the step's final code. The three values
(the plan's section 1):

| step | lock | phase-4 baseline (tracked / untracked in the phase-4 worktree) | code under test (`git diff -- . ':!.github/devdocs'` / untracked outside devdocs) |
|---|---|---|---|
| 0 | fbb64b7b…a68bb96 | d95a00ae…4fcb3 / 1270a566…b6c1e8 | the baseline (no repo file changed) |
| 1 | the same | the same | f529f459…252d13 / 412a6890…67b5cf |
| 2 | the same | the same | a835d7d4…9246fa / 412a6890…67b5cf |
| 3 | the same | the same | 84cd8873…e3d2c0 / bd57b336…9b245a |
| 4 | the same | the same | 9dcc6046…dc5d83 / bd57b336…9b245a |
| review fixes | the same | the same | 785efb15…637233 / bd57b336…9b245a |
| host fixes, round 1 (the final code) | the same | the same | 03ae7cc1…ee803e / bd57b336…9b245a |

The final code's files last changed at 05:49 on 2026-10-15, before the
second host round started on omicron (06:22) and kappa (06:24), so both
hosts' round 2 ran that code (synced from this worktree).

- **Step 0:** R from this worktree (`build`, `toolchain`,
  `compile-tree`); the TMB measurement above.
- **Step 1:** `rzig-test` with both zigs (unit and parity-test,
  including the 12 SHLIB cases); rzig and its tests cross-compiled with
  `--test-no-exec` for x86_64-windows-gnu, aarch64-macos and
  x86_64-macos; `zig fmt --check`; `build` (161 s), `compile-tree`,
  `pkg-parity` (192 s), `verify-package` (199 s), `contract` (114 s).
  By hand: rzig's `--dry-run` gives exactly the shell-split words of a
  real `R CMD SHLIB --dry-run` (`make -n`).
- **Step 2:** default chain `build`, `toolchain`, `verify-tree`,
  `smoke`, `compile-tree`, `pkg-parity` (with the SHLIB section),
  `contract`, `hermetic`, `package-toolchain`, `verify-package`;
  `rzig-test dist/slim/R-4.6.1-zig`; minimal `build`, `verify-tree`,
  `contract`, `verify-package`, `wheel`, `wheel-test`; `pkg-parity`
  and `contract` with upstream zig. All exit 0.
- **Step 3:** `verify-package` (slim, minimal), `contract` (both zigs,
  minimal too), `wheel`, `wheel-test`, `pixi run -e pkg conda-package`
  (the four packages' tests), `conda-consume`. All exit 0. The by-hand
  checks above.
- **Step 4:** `wheel` (11 s; the METADATA of r-zig, r-zig-compilers
  and r-zig-build-tools carries the new texts), `wheel-test` (62 s),
  `pixi run -e pkg conda-package` (286 s; the four packages are `_10`,
  built locally as `_10` before the 2026-10-19 decision, the PR keeps
  8, and their recipe tests pass, test-compilers.R's and
  test-preflight.R's SHLIB lines included), `conda-consume` (32 s), a
  YAML load of stress.yaml, and stress/packages.tsv read as stress.R
  reads it (40 rows, the Rcpp and rstan smokes parse). All exit 0.
- **Review fixes** ("Review fixes"; logs in the session's
  `shlib/fix/`): `rzig-test` with both zigs (151 unit tests; parity-test
  0 failed, its 13 SHLIB cases with the new 13th, a zig that is not
  R's); rzig and its tests cross-compiled for x86_64-windows-gnu,
  aarch64-macos and x86_64-macos with both zigs; `zig fmt --check`,
  `bash -n`; all 13 patches applied to the pristine tarball with
  `patch -p1 -f -F0`, no offset, fuzz or reject. Then `build`,
  `toolchain`, `verify-tree`, `smoke`, `compile-tree`, `pkg-parity`,
  `contract`, `package-toolchain`, `verify-package`, `rzig-test
  dist/slim/R-4.6.1-zig`, `pkg-parity` and `contract` with upstream zig,
  minimal `build`, `verify-tree`, `contract`, `verify-package`, `wheel`,
  `wheel-test`, `pixi run -e pkg conda-package` and `conda-consume`: all
  exit 0. By hand on the compile tree (`shlib/fix/manual.log`): SIGINT
  to R while zig build ran gives exit 1 and no make path (r-1); with
  `~/.pixi/bin/zig` 0.17 first on PATH, `R CMD SHLIB foo.c` says "needs
  make: … is zig 0.17.0, not R's zig 0.16" and builds through make, and
  with `MAKE` naming no make exits 1 with the compilers group's text
  (r-2); `RZIG_KEEP_ROOT=1 R CMD SHLIB` leaves the root beside foo.so,
  and a failing compile's "kept in" path exists (code-1). zig cc for
  aarch64-macos records `a,b/x.so` as the install name through
  `-Xlinker`, and refuses `-Wl,-install_name,a,b/x.so` ("unsupported
  linker arg: b/x.so"; code-3, `shlib/fix/instname.log`).
- **Host fixes, round 1** (logs in the session's `shlib/rfix1/logs/`):
  `bash -n` on the three scripts; `rzig-test` with both zigs (151 of
  151); all 13 patches applied to the pristine tarball with `patch -p1
  -f -F0`, no offset, fuzz or reject, after re-deriving the old 0013
  byte for byte first. Then `build` (160 s), `toolchain`, `verify-tree`,
  `smoke`, `compile-tree`, `pkg-parity` (135 s), `contract` (104 s),
  `package-toolchain`, `verify-package` (206 s), `rzig-test
  dist/slim/R-4.6.1-zig`, `pkg-parity` (118 s) and `contract` (93 s)
  with upstream zig, minimal `build`, `verify-tree`, `contract`,
  `verify-package`, `wheel`, `wheel-test`, `pixi run -e pkg
  conda-package` (284 s) and `conda-consume`: all exit 0. On linux the
  Windows branches of `.rzig_build` are dead code; the hosts test them.

### osx-arm64 (omicron)

The plan's section 6 chain, in a copy of this worktree at
`~/rz-shlib` (removed after round 2). Logs and scripts in the
session's `shlib/omicron/` (round 2 in `r2/`, round 1 in `r2/round1/`).

- **Round 1** (the review-fixes code): `rzig-test` with both zigs (151
  of 151), `build`, `toolchain`, `verify-tree`, `compile-tree`,
  `contract` (its no-make program in full: Rcpp, the OpenMP plugin's
  parse and compile, cpp11's SHLIB call through callr, pak's probe and
  a pak install of a C package), `package-toolchain`, minimal `build`,
  `toolchain` and `contract`, `wheel`, `wheel-test`, `pixi run -e pkg
  conda-package` (four osx-arm64 `_10` files, built locally as `_10`
  before the 2026-10-19 decision; the PR keeps 8) and `conda-consume`
  passed. `pkg-parity`, `verify-package` and minimal `verify-package`
  failed on one cause, the macOS `a.o` ("Host fixes, round 1"). The
  tester's fix, rzig's driver adding `-c` to a version query, made the
  whole chain pass in the tester's copy; a first attempt (the report's
  queries run in the build root) left make's path and the plugin's
  `a.o`, and was not taken.
- **Round 2** (the final code), 2026-10-15 06:22 to 06:48: `rzig-test`
  with both zigs (151 of 151), `build` (102 s), `toolchain`,
  `verify-tree`, `compile-tree`, `contract` (106 s), `pkg-parity` (151
  s: every SHLIB shape, the subdir install name `sub/sd.so` through
  `-Xlinker` on both paths, pkgload's dry run, the caches, tier 2 and
  3, the no-make base install), `package-toolchain`, `verify-package`
  (182 s; `check_minos` on the kept root's object), minimal `build`,
  `toolchain`, `verify-package` and `contract` (the OpenMP plugin's
  parse without its compile, Cc6), `wheel`, `wheel-test` (306 s),
  `conda-package` (243 s) and `conda-consume`: all exit 0. No `a.o`
  anywhere in the copy outside build/, `.zig-cache` and `.pixi`.
- **By hand:** `Rcpp::cppFunction` with no make on PATH (base tree,
  `env -i`); the line after "make would use" in `R CMD SHLIB --dry-run`
  is rzig's zig-cxx compile, the link in `make -n`'s `if test … fi`
  form, and `.openmpPluginDarwin()` gives `PKG_CXXFLAGS = -fopenmp`;
  on the compile tree `cppFunction(plugins = "openmp")` with omp.h
  built through rzig build and ran 3 threads; a `#pragma message`
  source prints its text through `R CMD SHLIB` and leaves only pm.so.
- **zig's cache and warnings:** zig cc prints no warning when its cache
  serves the object, so a `#pragma message` text appears only on a
  cache miss. make's path with zig cc does the same (round 2's
  `makecmp.sh`, R_ZIG_PKG_BUILDER=make: printed on the first compile,
  not the second), so this is not new with rzig build. RcppParallel's
  probe pragma fires only below deployment target 10.13; this build
  targets 13.0. The by-hand check uses a text new to every run.
- **Timings, tier 1 on the compile tree, rzig build against make:** cli
  14 s (with the build runner) against 7 s, digest 3 against 4, quadprog
  3 against 3, Rcpp 3 against 3, minqa 7 against 7; cli's second
  install 5 s (make 7 s).

### win-64 (kappa)

The plan's section 6 chain in `C:\Users\admin\rz-shlib` (removed after
round 2), pixi 0.82.0, Windows 11 22621. Logs in the session's
`shlib/kappa/` (round 2's scripts in `r2/`).

- **Round 1** (the review-fixes code): `rzig-test` with both zigs (121
  of 151 pass, 30 skip: phase 4's 28 plus the two SHLIB tests that use
  shell-script stand-ins; parity-test.sh is linux only), `build` (all
  13 patches with no offset or fuzz), `toolchain`, `verify-tree`,
  `compile-tree`, `hermetic`, `package-toolchain`, `pixi run -e pkg
  conda-package` and `conda-consume` passed. `contract`, `pkg-parity`
  and `verify-package` failed, each on a test-script setup bug ("Host
  fixes, round 1": cli's `PROCESSOR_ARCHITECTURE`, pkgload's backslash
  R_HOME, the copied flang's runtime directory); each passed with its
  fix in the tester's copy. Two findings outside the tests: no
  `R_SESSION_TMPDIR` on Windows, and the "Exit code was 127" warning,
  both fixed in 0013.
- **By hand, round 1:** on the base tree under `env -i`, PATH
  `bin\x64` and System32 only, no Rtools variables:
  `pkgbuild::has_compiler(debug = TRUE)` TRUE, 11.9 s cold (a fresh
  rzig cache, the build runner compiled) and 0.52 s warm;
  `check_build_tools()` "Your system is ready to build packages!";
  `Rcpp::cppFunction` with a C++ exception thrown and caught, through
  `rzig build: R CMD SHLIB, tier 1`. `has_rtools()` was TRUE only
  because kappa's registry still names C:/rtools44 and C:/rtools45,
  which no longer exist; `R CMD config CC` with no sh says "'sh' is not
  recognized" and exits 1, so pkgbuild's `cc_path` is empty (H: 0010
  unchanged, the TODO.md item stands). Under RZIG_TRACE=1, zig build's
  step trees print "failed command:" headings for steps that only wrote
  to stderr (risk 1's wording).
- **Timings, tier 1 on the compile tree, rzig build against make:** cli
  43 s (with the build runner) against 21 s, digest 12 against 7,
  quadprog 5 against 4, Rcpp 9 against 11; cli's second install 20 s
  (make 26 s).
- **Round 2** (the final code), 2026-10-15 06:24 to 07:11 (kappa's
  time), from a fresh copy (build/ removed, since 0013 changed): `pixi
  lock --check`, `rzig-test` with both zigs (121 of 151, 30 skip),
  `build` (about 7.5 min; all 13 patches with no offset or fuzz),
  `toolchain`, `verify-tree`, `compile-tree`, `contract` (its no-make
  program in full: Rcpp with a C++ exception and evalCpp, cpp11's SHLIB
  call through callr, pak's probe in its worker, pak's install of a C
  package; no crash at exit), `pkg-parity` (every SHLIB shape against
  make, pkgload's injected dry run 19 of 19 and rzig's plain dry run
  the same 19, `R_ZIG_PKG_BUILDER=zig`, two calls at once with two
  kept roots in one directory, H8, the caches, tier 2 and 3, the
  no-make base install), `hermetic`, `package-toolchain`,
  `verify-package` (scenario 1's SHLIB stops in order; scenario 2's
  no-make block: probe, sourceCpp, Fortran with the runtime archive
  beside the flang copy, cpp11, TMB, `--dry-run`, OpenMP; scenario 3's
  make shapes), `pixi run -e pkg conda-package` (about 12 min; the
  recipe tests' SHLIB lines) and `conda-consume`: all exit 0. pixi.lock
  fbb64b7b…a68bb96 at the start and the end. No "Exit code was 127" in
  contract's or the conda logs. Logs: the session's
  `shlib/kappa/r2/logs/`.
- **By hand, round 2** (`shlib/kappa/r2/byhand.sh`, `byhand.log`,
  `s6.log`; base tree under `env -i`, PATH `bin\x64` and System32, zig
  through `ZIG_BIN`): `R CMD SHLIB foo.c`'s root is
  `<TMPDIR>/Rtmp*/.rzig.<16 hex>`, the inner R's `tempdir()` (M b on
  Windows), and nothing is left beside the source or in TMPDIR; with a
  TMPDIR holding spaces R takes its 8.3 name and the root is
  `…\TMPSPA~1\Rtmp*\.rzig.*`, the DLL builds and loads; in process,
  `tools:::.shlib_internal` leaves an unset `R_SESSION_TMPDIR` unset and
  gives a caller's value back; with no zig, rzig's compilers text and
  no "Exit code was 127"; a Makevars rule with no make, rzig's reason,
  "no make on PATH" and the build tools' text, no 127 warning.
  `pkgbuild::has_compiler(debug = TRUE)` TRUE in 0.82 s and again in
  0.71 s after `cache_reset()`, `has_build_tools()` and
  `check_build_tools()` TRUE ("Your system is ready to build
  packages!"), `R CMD config CC` empty (no sh: H), `has_rtools()` TRUE
  from the stale registry entries, `Rcpp::cppFunction` with a C++
  exception through `rzig build: R CMD SHLIB, tier 1` (the `rzig def`
  step under the link in the trace).

### CI

Not run yet (step 5, after the user's push): the PR gets `full-ci` and
`upstream-zig` (the patch and rzig changed), so the full matrix runs
with both zigs, and conda-package's five legs (the recipe tests carry
test-compilers.R's and test-preflight.R's SHLIB lines). What only CI
adds: linux-aarch64 and osx-64 (no host here), and every leg's
verify-package and contract SHLIB checks from a clean runner. The
dispatch (J):

    gh workflow run stress.yaml --ref feat-shlib-rzig-build -f packages='g1 g2' -f trace=true -f shared_cache=false

on the five runners. What it must show, against main d11dee1's run
38569895172: Rcpp's smoke log carries `rzig build: R CMD SHLIB, tier 1`
(its `cppFunction(…, showOutput = TRUE)`); rstan's row passes (its
`stan_model` compile through rzig build; on macOS its `R CMD config
CXX17` still needs the build tools, H); RcppArmadillo's and
RcppParallel's configure-time `R CMD SHLIB` probes give the same
builders and results as main's run; no row that passed on main fails.
Then TODO.md's g1 dispatch item is ticked. (The build number is not
checked: open decision 2 is answered, no bump.)

## Not tested

- RStudio's own build-tools checks (Rtools on Windows, the Command Line
  Tools on macOS) beyond pkgbuild's hook (Cg16).
- The macOS `/usr/bin/make` shim on a Mac without the Command Line
  Tools (TODO.md's item).
- `R_ZIG_PKG_BUILDER=zig` with no rzig in the tree (a damaged tree):
  `.rzig_build`'s branch for it is not exercised.
- CRAN as a whole was not searched for other packages that copy
  `tools:::.shlib_internal` as TMB does; of the 21 callers surveyed,
  only TMB does (risk 3).
- linux-aarch64 and osx-64 by hand: no host here; CI covers them.
- Other `env -i` Windows environments that load cli (pkg-parity's
  `NOMAKE_ENV`, verify-bundle's `base_env`) do not pass
  `PROCESSOR_ARCHITECTURE`; none calls `pak:::remote` today, so they
  are left as they are (kappa round 1).
- A real Windows machine without the stale Rtools registry entries
  kappa still has: `has_rtools()`'s answer there is the README's text
  (H), not a measurement.

## Open decisions (for the user)

1. pak's dpkg-query spin (Measurements, "pak on base alone"):
   - (a) ★ record it here only: it was seen only with a PATH stripped
     of dpkg-query, which no user environment has;
   - (b) also a README line: set `PKG_SYSREQS_LOOKUP_SYSTEM=false` when
     pak hangs on a restricted PATH.
2. The build number at merge (B14 a):
   - (a) ★ keep 10 and check universe's newest just before the merge
     (`pixi run -e pkg conda-channel-list universe <subdir>`); if it is
     not phase 4's `_9`, take the one after it, in recipe.yaml and in
     the `_10` notes of feat-zig-pkg-build/PLAN.md and TODO.md;
   - (b) change it now, before CI, to a number picked today.

   Answered by the user, 2026-10-19, with neither: "do not bump conda
   package build version in the previous PRs. the next build bump is
   going to be after phase 7 is merged." The number stays 8; phase 7's
   bump takes the number after universe's newest (B14 a) and publishes
   SHLIB routing with phases 4 to 7.

## Follow-ups (not on this branch)

In feat-standalone-toolchain TODO.md:
- `R CMD config` through rzig (unix src/scripts/config; Windows with
  phase 7's rcmdfn.c): rstan on macOS and pkgbuild's Windows
  `has_rtools()` (H).
- TMB's precompile across model names (D), if users ask.
- The build root of R CMD INSTALL's package mode under
  `R_SESSION_TMPDIR` too (M c), if a killed install's `src/.rzig` is
  seen.
- To look at, from omicron's round 1: a `zig-lib-<n>` directory
  appeared in the real `~/.cache/r-zig` during minimal `verify-package`
  (05:18), so some step in it may run rzig with the user's cache rather
  than the test's. Not traced; harmless (a zig lib cache), left in
  place.
- With K and L at (a), nothing more: the binary repository
  (feat-no-host-paths, "Our own repository first") would ship pkgbuild
  and pak prebuilt.

## Files

- rzig (zigbuild/tools/rzig/): pkgplan.zig, pkgbuild.zig, check.zig,
  shellwords.zig, main.zig, compiler.zig (macOS `--version`, host fixes
  round 1), parity-test.sh.
- rpkg (zigbuild/rpkg/): build_t1.zig.
- R: zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch.
- Tests: scripts/pkg-parity.sh, verify-bundle.sh, contract-test.sh,
  wheel-test.sh; recipe/test-compilers.R, test-preflight.R.
- Texts: README.md, scripts/make-wheel.py, pixi.toml (a comment),
  recipe/recipe.yaml (the number), .github/workflows/stress.yaml (a
  description), stress/README.md, stress/packages.tsv.
- Records: this file, plan/SHLIB-IMPLEMENTATION.md and
  plan/CRITIQUE.md; feat-zig-pkg-build/PLAN.md (decision 2, "What must remain on the
  R side", N2, fact 8, "What the build-tools group is for");
  feat-standalone-toolchain PLAN.md ("What a user gets") and TODO.md;
  fix-zig-pkg-build-review/PLAN.md and feat-shared-build-runner/PLAN.md
  (their follow-ups).

## How to rerun

    pixi run rzig-test                                   # unit tests and parity-test's SHLIB cases
    ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test     # the same with upstream zig
    pixi run pkg-parity                                  # SHLIB parity: rzig against make, shape by shape
    pixi run contract                                    # + the no-make program: Rcpp, cpp11's SHLIB call, pak
    pixi run verify-package                              # scenario 1's and 2's SHLIB checks
    RZIG_TRACE=1 R CMD SHLIB -o x.so x.c                 # the trace: rzig build: R CMD SHLIB, tier 1, root ...
    RZIG_KEEP_ROOT=1 R CMD SHLIB -o x.so x.c             # the build root kept beside x.so: .rzig.<16 hex>
    R_ZIG_PKG_BUILDER=make R CMD SHLIB -o x.so x.c       # the make path
    gh workflow run stress.yaml --ref feat-shlib-rzig-build -f packages='g1 g2' -f trace=true -f shared_cache=false
