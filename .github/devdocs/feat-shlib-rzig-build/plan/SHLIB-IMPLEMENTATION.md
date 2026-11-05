# R CMD SHLIB through rzig build: implementation plan (amended)

This is the amender's plan of 2026-10-15. It starts from the planner's
plan of 2026-10-14 (`planner/SHLIB-IMPLEMENTATION.md`) and takes in the
verified points of the two critiques.

This was read-only work:
- nothing in the repo changed, and no git state changed;
- nothing was built or installed.

`CRITIQUE.md`, beside this file, records how each point was checked,
and why it was taken, changed or rejected.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." SHLIB routing keeps build 8, as phases 4, 5 and 6 do, and main
publishes nothing until the user sets the repository variable
`CONDA_PUBLISH` after feat-standalone-toolchain phase 7's bump merges
(its PLAN.md, B14's amendment). Where this plan says the PR bumps to 10,
or names `_9` as the build before it, read: the number stays 8, and
SHLIB routing publishes with phase 7's bump, at the number after
universe's newest (B14 a).

Tags:
- (Cc<n>): critique-code.md;
- (Cg<n>): critique-goals.md;
- (Am<n>): the amender's own checks (CRITIQUE.md).

Where an open point is undecided, the plan is written with its
recommended option (★) and names the point. The open points are in
section 10, "Open points (need the user)". They are relettered, and
CRITIQUE.md maps the planner's letters to these.

Citations:
- (SR §n): survey-r.md, R 4.6.1's `R CMD SHLIB` path.
- (SC §n): survey-callers.md, the callers and the probes.
- (SZ §n), and SZ's hazards H1 to H11: survey-rzig.md, rzig's side.
- (P): the planner's own reading, with file:line.

Sources:
- The worktree `wt/feat-shlib-rzig-build`: main d11dee1 plus phase 4's
  uncommitted changes, 42 files in `git diff --stat`.
  - The untracked files are `phase4/` (two files),
    `recipe/test-build-tools.R`, `recipe/test-compilers.R` and
    `scripts/conda-consume.sh`.
  - pixi.lock's sha256 is fbb64b7b…a68bb96, phase 4's and PR #27's
    tested lock.
  - Line numbers are the worktree's. When implementing, cite the
    function, not the line.
- R 4.6.1: the pristine CRAN tarball, and `shlibplan/surveyor-r/patched/`
  (the pristine tree plus this worktree's 0001 to 0013). "install.R:NNNN"
  is the patched tree.
- The callers: CRAN sources under `shlibplan/surveyor-callers/`
  (pkgbuild 1.4.8, pak 0.11.1, pkgdepends 0.9.1, Rcpp 1.1.2, cpp11
  0.5.5, inline 0.3.21, TMB 1.9.25, rstan 2.32.7, RcppParallel 6.2.1,
  nimble 1.4.3, pkgload 1.5.3).
- The records (`.github/devdocs/`):
  - feat-standalone-toolchain PLAN.md and TODO.md;
  - feat-zig-pkg-build PLAN.md;
  - fix-zig-pkg-build-review PLAN.md;
  - feat-shared-build-runner PLAN.md.
- The session's own record of 2026-10-14 in the user's auto-memory
  (`zig-pkg-build.md`), and the phase-4 baseline `wt/phase4-base.diff`
  (section 1).

Decision IDs are the records' own: B1-B44, M1-M8, N1-N7, I-*. This
plan's open points are letters (section 10).

## 0. What it delivers

**Why this work, and why now (Cg1; open point A).**
- In the records' numbering, phase 5 (zig in the compilers group)
  follows phase 4 (TODO.md:598). SHLIB routing is a "Later" item there
  (TODO.md:757-765; feat-zig-pkg-build N2).
- The session's record of 2026-10-14 says: "next item after phase 4 =
  route R CMD SHLIB through rzig build". That is the user's auto-memory,
  `zig-pkg-build.md`. The stacked worktree and the baseline were made for
  this work, and the user said "I can't commit yet. Start working on the
  next phase".
- So this plan takes SHLIB routing before phase 5. Open point A confirms
  it.
- Until phase 5, the standalone compilers archive has no zig
  (verify-bundle.sh:72-75). On that channel, "base + compilers" means the
  user's own zig (`ZIG_BIN`), as the tier-1 install does today.

**What base + compilers then does from scratch, with no make on any OS
(Cg7):**
- every `R CMD SHLIB` whose inputs are declarative: no Objective-C, no
  Makevars rules, conditionals, `$(shell)` or `include`;
- Rcpp's `sourceCpp`, `cppFunction` and `evalCpp`, including the macOS
  OpenMP plugin's `--dry-run` parse (C);
- inline's C, C++ and Fortran;
- `TMB::compile`, for a TMB installed by this R. TMB and RcppEigen are
  tier 1, and Matrix ships with R;
- knitr's c, cc and fortran engines;
- renv's optional `renv.c`;
- the compile in rstan's `stan_model`. On macOS its later
  `R CMD config CXX17` still needs the build tools (H).

**And where they are already installed:**
- pkgbuild's `has_compiler()` probe on every OS, and so
  `has_build_tools()` / `check_build_tools()`, pak's gate before each
  source build, remotes' `has_devel`, and compile_dll's probe for
  devtools, pkgload and odin (SC §1-§3);
- `cpp11::cpp_source`.

**Installing those callers from source needs the build tools once (Cg7,
Am1; open point K):**
- pkgbuild imports callr and processx. processx has Makevars rules
  (tools/px, supervisor, client), and ps and pak have configure scripts.
- `cpp_source` stops unless brio, callr, cli, decor, desc, glue, tibble
  and vctrs are installed (cpp11 R/source.R:69).
- So pkgbuild, pak, devtools, remotes' pkgbuild path and `cpp_source`
  come from an install with the build tools, or from r-zig-toolchain
  from the start.

**How:**
- `R CMD SHLIB` and `R CMD INSTALL` reach rzig build through **one hook**
  in `.shlib_internal`, before its make path (B (iii) ★; Cg3).
  - It runs for R CMD SHLIB's files, and for R CMD INSTALL's package,
    which run_shlib now names (`pkg =`).
  - One top-level helper, `.rzig_build`, holds every rule: the builder
    switch, rzig's arguments, the spawn, the jobs and the user Makevars
    (Cg4, Cc4).
  - `.shlib_internal`'s body passes R's parsed values only. TMB keeps a
    copy of that body, and it then follows later fixes.
  - Patch 0013 is regenerated as the one rzig-build patch. There is no
    0014.
- **SHLIB mode, `rzig build --shlib`:** rzig plans the call as
  `.shlib_internal` and make would, from:
  - the files R names, in argv order;
  - the output (`-o`, or the first file);
  - argv's other words, as make's command-line `PKG_LIBS`;
  - the working directory's Makevars (Windows: `.ucrt`, `.win`, then
    the plain file);
  - the site and user Makevars;
  - the environment (`PKG_*`, `CLINK_CPPFLAGS`, `USE_CXXnn`,
    `R_PKG_CXX_STD`).
- It runs the compiles and the link as zig build steps, with the shared
  tier-1 runner (build_t1.zig, `sharedRunner`). These are the steps that
  build tier-1 packages, with the same compilers.
- Fortran sources compile one after another, in OBJECTS order, as R's
  serial make does: a module's `.mod` must exist before its `use` (Cc3).
  This holds for tier-1 packages too.
- **Exit 3, "needs make", leaves the make path unchanged.** That is:
  - Objective-C;
  - a Makevars with rules, conditionals, `$(shell)` or `include`;
  - a ready `.o` with no source;
  - a `MAKEFLAGS` assignment;
  - a foreign compiler;
  - a shell metacharacter (SZ §4, §5);
  - a single quote in argv's linker words, which rewrites make's own
    command line, as pkgload's and RStudio's compilation databases do
    (Cg9, Cc2);
  - a damaged tree with no `share/zig/rpkg/build_t1.zig` (Cc8).
- **Who it reaches** (SR §1, SC §4):
  - `R CMD SHLIB` on every OS: unix through `bin/SHLIB`, Windows through
    `Rcmd.exe`;
  - TMB's in-process `tools:::.shlib_internal`, for a TMB installed by
    this R (SC §0 fact 4);
  - R's own callers: javareconf, and configure scripts that run SHLIB
    (J checks which do; Cg14);
  - R CMD INSTALL's run_shlib, as 0013's hook did.
- **What still needs the build tools:**
  - the call shapes that need make (above; nimble's `ifndef` Makevars,
    inline's Objective-C);
  - pkgload's compilation database. Its own `compilers()` runs make
    (Am2), and its injected dry run goes to make by the quote rule;
  - `R CMD config`, so rstan on macOS (H);
  - installing the callers above from source (K).
- **A call that needs make, with no make,** gets rzig's text and exit 127
  instead of sh's "make: not found" (open point F; SR §8). It reads
  "`<lib>` needs make: `<reason>`; no make on PATH", then the build-tools
  group's text. With no zig either, the compilers' text comes first:
  every missing group in one stop, as the install preflight (phase 4 H a;
  Cg5, Cc9).
- **`--dry-run`:**
  - R prints its own "make cmd is … make would use" text, which rstan
    parses (SC §4.4).
  - rzig then prints the compile lines it would run, in `make -n`'s
    form, which Rcpp's macOS OpenMP plugin parses (SC §4.1).
  - It prints the link the way `make -n` prints shlib.mk's recipe,
    inside `if test "z<objects>" != "z"; then … fi`. So a line that runs
    the linker never starts with the compiler (Cc2).
  - When rzig would not build the call, `make -n` runs as before (C).
- **`--clean` and `--preclean`** are ignored on the rzig path in both
  modes, as 0013 ignores them for packages (E (a) ★; Cg6). rzig neither
  writes nor reads objects beside the sources, so no stale object can be
  reused. On the make path they work as before.
- **The build root** for SHLIB mode is `.rzig.<16 hex>` under R's session
  temporary directory (`R_SESSION_TMPDIR`), else beside the output. It is
  unique per call (SZ H2), and gone after the call (M (b) ★; Cg15).
  Nothing is left beside the sources except the `.mod` files flang writes
  in the working directory, as under make (Cc3).
- **One switch:** `R_ZIG_PKG_BUILDER=auto|zig|make` governs both modes,
  read in `.rzig_build` only (G).
- **H8:** pkgplan's `P_FCFLAGS` follows R's literal
  `file.exists("Makevars")` test, for packages and SHLIB alike. That
  changes Windows tier-1 packages with a Makevars.win `PKG_FCFLAGS` and
  no Makevars, toward make (Cc10, Cg15).
- **Tests:**
  - rzig's unit and parity tests;
  - a SHLIB parity section in pkg-parity: make against rzig, the oracle,
    with non-vacuous assertions (Cc5);
  - a no-make `R CMD SHLIB` block in verify-bundle's scenario 2, and a
    base-alone check in scenario 1, on every OS;
  - contract-test's no-make callers: Rcpp, cpp11's SHLIB shape and pak;
  - test-compilers.R and test-preflight.R (conda) and wheel-test.sh
    (pip);
  - a g1 stress dispatch with trace, plus the configure rows that call
    SHLIB (J);
  - by-hand measurements: TMB first (step 0), the first probe's cost, pak
    on base alone, one real `cpp_source`.
- **Records, texts, number:**
  - the README's and the wheels' group texts;
  - the layered model's "What a user gets";
  - the build number per B14 (a): the one after universe's newest when
    this merges, so 10 when phase 4's `_9` is the newest (Cg10).

Not in this PR:
- `R CMD config` through rzig (H: a later PR; its Windows half goes with
  phase 7's rcmdfn.c).
- Objective-C, Makevars rules and the other tier-3 shapes. The tier rules
  are unchanged.
- symbols.rds (I), and the "using SDK" and "using C++NN" lines. Tier-1
  packages print none of them either (feat-zig-pkg-build "Not in M3";
  pkgbuild.zig:602-621).
- pkgbuild's Windows `has_rtools()` WARNING on base + compilers.
  Documented (H).
- Phases 5 to 8.

What changed since the decisions, and what it means here:
- **feat-zig-pkg-build N2** put `R CMD SHLIB` out of scope and listed it
  as a later item, with "give it a preflight" and "revisit 0010 for
  pkgbuild's probe" (its PLAN.md:1011-1044). This PR does the routing.
  Its exit 127 with every missing group's text (F) is the preflight's
  role. 0010 stays (H), because neither probe calls `R CMD config` on
  R 4.6.1 (section 4).
- **Its decision 2, "R gets one hook before `run_shlib`",** holds in
  spirit and moves: the one hook now sits in `.shlib_internal`, which
  run_shlib calls. The record amends the wording (section 9; Cg3).
- **The shared tier-1 runner (PR #27)** is compiled once per build_t1.zig
  content and zig, per machine, not per call. SHLIB mode reuses it, and
  pkgbuild's first probe after an upgrade pays one compile (SZ H5;
  risk 5).
- **Phase 4** puts rzig in the base on every channel, so the hook always
  finds it. Its "no rzig" branch is for a damaged tree only. Phase 4 is
  not committed yet (section 1).
- **pak probes before every source package, R-only included.**
  pkgdepends' `needscompilation` is a logical after resolution
  (resolution.R:787-788), and `!identical(<lgl>, "no")` is always TRUE
  (install-plan.R:516, 557, 592; SC §0 fact 2).
  - On base alone, the probe now fails with rzig's compilers text where
    it failed with "make: not found".
  - pak's own error ("Could not find tools necessary to compile a
    package") stops the plan either way.
  - This PR does not change base alone. It is checked by hand and
    recorded, and L is ready for the result (Cg12).

## 1. Sequencing and preconditions (Cg2)

**Phase 4 is not committed, and the user cannot commit it yet.** This
work goes ahead in `wt/feat-shlib-rzig-build` as it is: main d11dee1
plus phase 4's changes, uncommitted. It is separated from phase 4 by a
baseline that already exists (Am6).

- **The phase-4 baseline:**
  - `wt/phase4-base.diff`, sha256 d95a00ae…4fcb3 (`git diff` of the
    tracked files);
  - the 5 untracked phase-4 files (`phase4/` twice,
    `recipe/test-build-tools.R`, `recipe/test-compilers.R`,
    `scripts/conda-consume.sh`), whose sorted `sha256sum` list hashes to
    1270a566…b6c1e8.

  On 2026-10-15 both values were the same in this worktree and in the
  phase-4 worktree (`.claude/worktrees/feat-standalone-phase4`).
  - Before each step, recompute both in the phase-4 worktree.
  - When phase 4 moves (a review fix), apply its new delta here by hand,
    then rerun what it touches. Record the new baseline values.
- **The SHLIB delta** is this worktree against a scratch tree built
  from the baseline:
  - `git archive d11dee1 | tar -x` into
    `shlibplan/<role>/base-tree/`, then `patch -p1 <
    wt/phase4-base.diff`, then the 5 untracked files copied in;
  - then `diff -ruN base-tree <worktree>`, excluding `.git`, `build/`,
    `dist/`, `.pixi/` and the caches.

  No git writes, and no WIP commits: the user makes every commit
  (memory "no-git-commits"). No `git stash`: the stack is shared with
  other sessions.
- **No step waits for phase 4's commit.** Step 1 already changes
  phase-4 files (pkgbuild.zig, check.zig, parity-test.sh), so the
  baseline is what separates the two either way. The R patch (step 2)
  comes after step 1, which keeps 0013, the file most likely to
  conflict with a phase-4 review fix, for late. (Cg2's "wait" part is
  rejected: CRITIQUE.md.)
- **When the user commits phase 4** (branch feat-standalone-phase4), hand
  over these commands. The mixed reset moves this branch's HEAD and
  index to that commit and keeps the working tree:

      git -C /data/gamma/luciorq/workspaces/temp/r-zig-pixi/wt/feat-shlib-rzig-build reset <phase4-commit>
      git -C /data/gamma/luciorq/workspaces/temp/r-zig-pixi/wt/feat-shlib-rzig-build diff > /data/gamma/luciorq/workspaces/temp/r-zig-pixi/shlibplan/after-reset.diff
      git -C /data/gamma/luciorq/workspaces/temp/r-zig-pixi/wt/feat-shlib-rzig-build status --short

  - `after-reset.diff` must match the SHLIB delta file for file. If it
    does not, phase 4's commit differs from the baseline: bring that
    difference over first.
  - The SHLIB work's new untracked files show as `??`.
- **Its own PR,** with base feat-standalone-phase4 until phase 4 merges,
  then main. The repo merges with merge commits, so the stack survives
  the retarget.
- **Build number (B14 a; Cg10).** This PR changes r-zig-slim: patch
  0013, rzig (in the base since phase 4), and share/zig/rpkg's
  build_t1.zig. It bumps to the number after universe's newest on the
  five subdirs when it merges, so 10 once phase 4's `_9` is published.
  Check just before merging with
  `pixi run -e pkg conda-channel-list universe <subdir>`. (2026-10-19:
  no bump; the number stays 8, the note at the top.)
- **publish-preflight** on gamma, omicron and kappa before the long
  conda chains: disk, `pixi lock --check`, no gitignored inputs. No host
  uploads: CI publishes from main with OIDC.
- **Every host records three values** at the start and the end of its
  runs:
  - pixi.lock's sha256, which must not change (this PR changes no
    dependency of a pixi env);
  - the phase-4 baseline the tree holds: the two hashes above;
  - the code under test:
    `git diff -- . ':!.github/devdocs' | sha256sum`, plus the sorted
    `sha256sum` of the untracked files outside `.github/devdocs`.

  One owner per host: gamma owns the local build, dist and the records;
  omicron and kappa own theirs. No host writes the lock. Each host has
  its own scratch directory.
- **No CRAN binary for TMB here.** TMB's snapshot of `.shlib_internal`
  is the body of the R that installed it (SC §0 fact 4). TMB installed
  by `_9` keeps make until it is reinstalled with this build. The README
  and the record say so (risk 3).

## 2. Steps

Each step is a local checkpoint that leaves every named test green. CI
sees only the PR's final state. Before each step's tests, review the
diff skeptically when it is over about 200 lines: Windows paths,
quoting, `.dll` and `.def` names, argument forwarding, names dropped.
"Both zigs" means conda-forge's zig and upstream zig
(`ZIG_BIN=$(pixi run fetch-zig)`).

0. **The TMB measurement, before the open points go to the user** (Cg11,
   Cc7). By hand on gamma, with today's make path, in an R from main
   d11dee1 (the main checkout's compile tree or dist), in a scratch
   library:
   - install TMB (and RcppEigen), then `TMB::precompile()`;
   - record libTMB.cpp's compile seconds, and the size of the
     `libTMB.o` it leaves in TMB's `libs/`;
   - record one model compile with the precompiled library, and one
     without (`libtmb = FALSE`);
   - write the numbers into D: under D (a), each new model name pays
     libTMB.cpp's compile once, and adds about one `libTMB.o`'s size to
     zig's global cache, which zig never evicts.
1. **rzig: SHLIB mode** (open points C, E, F, M; H8; Cc3, Cc8, Cc11,
   Cg5, Cg9).
   - Changes (section 3):
     - pkgplan.zig: `Shlib`, `classifyShlib` (Objective-C; the
       single-quote rule), `makevarsIn`, and the plan's SHLIB branches;
       source lookup that accepts absolute paths; texts without `src/`;
       the C++-standard warning dropped as B says; H8; Windows BASE as
       winshlib.mk's;
     - pkgbuild.zig: `--shlib` and its flags, `runShlib`, the shared
       tail `zigBuild`, the root under `R_SESSION_TMPDIR`, `--dry-run`
       with make -n's link form, the missing-build_t1.zig exit 3, and
       the needs-make stop through `check.groupsFor`;
     - check.zig: `groupsFor`, public, which `packageIn` now calls;
       `buildToolsFound` stays private;
     - shellwords.zig: `quote`;
     - main.zig's usage text;
     - build_t1.zig: the input path for an absolute source, and the
       Fortran chain;
     - parity-test.sh's SHLIB cases.
   - R is unchanged, so no `R CMD SHLIB` reaches this mode yet.
   - Tests:
     - `pixi run rzig-test` with both zigs: unit and parity-test,
       including the SHLIB cases;
     - rzig and its unit tests cross-compiled with `--test-no-exec` for
       x86_64-windows-gnu, aarch64-macos and x86_64-macos;
     - `zig fmt --check`;
     - build_t1.zig, check.zig and pkgplan changed, so `pixi run build`
       (incremental: the patches are unchanged), `compile-tree`,
       `pkg-parity`, `verify-package` and `contract`. These show that
       tier-1 packages and the preflight are unchanged, and that the
       runner gets one new directory, keyed by build_t1.zig's new
       content.
2. **R: the one hook** (open points B, C, G, I).
   - Changes:
     - patch 0013 regenerated: the top-level `.rzig_build`;
       `.shlib_internal(args, pkg = NULL)`, its `files` vector and the
       hook before make and in the dry run; run_shlib's `pkg =
       pkg_name`; 0013's `rzig_build` closure removed; the patch_rpaths
       and allfiles hunks kept as they are.
   - Regenerate it in scratch, as phase 4 did: 0001 to 0012 applied,
     then 0013 edited and diffed. All 13 must apply to the pristine
     tarball with `patch -p1 -f -F0`, with no offset, fuzz or reject.
   - The tests that must stay green change in the same step:
     - verify-bundle's make SHLIB shapes (scenario 2 unix, Windows
       scenario 3) get `R_ZIG_PKG_BUILDER=make`, so they stay the make
       reference (N1);
     - contract-test.sh's evalCpp comment and report line.
   - pkg-parity's SHLIB parity section, the oracle for this step, comes
     with it (section 3).
   - The patch changed, so R's source is extracted again (zig-build.sh's
     stamp), and this is a full rebuild.
   - Tests:
     - default: `build`, `toolchain`, `verify-tree`, `smoke`,
       `compile-tree`, `contract`, `hermetic`, `pkg-parity` (with the
       SHLIB section), `package-toolchain`, `verify-package`;
     - `rzig-test dist/slim/R-4.6.1-zig` (smoke-test.sh);
     - minimal: `build`, `verify-tree`, `contract`, `verify-package`,
       `wheel`, `wheel-test`;
     - pkg-parity and contract also with upstream zig.
3. **The no-make callers** (open points D, F, J, K, L).
   - Changes:
     - verify-bundle: scenario 2's "R CMD SHLIB with no make" block on
       every OS, and scenario 1's base-alone SHLIB check;
     - test-compilers.R's SHLIB checks, and test-preflight.R's
       base-alone SHLIB check;
     - wheel-test.sh: the SHLIB checks for r-zig alone, with
       r-zig-compilers, and with r-zig-build-tools;
     - contract-test.sh's no-make block: Rcpp, cpp11's SHLIB shape
       through callr, and pak's probe and install, with cpp11, callr,
       processx and R6 added to its installs (Cc1);
     - stress/packages.tsv's Rcpp smoke (J).
   - Tests: `verify-package` (slim, minimal), `contract` (both zigs),
     `wheel-test`, `pixi run -e pkg conda-package` (four tests), then
     `conda-consume`.
   - By hand on gamma, recorded:
     - one real `cpp11::cpp_source(code = …)` with no make, after its
       Suggests are installed (Cc1);
     - the first probe after a fresh rzig cache (H5);
     - pak on base alone with an R-only package (SC §0 fact 2; L);
     - TMB on this build: models A, A again, then B, against step 0's
       numbers, and du of `$ZIG_GLOBAL_CACHE_DIR/o` before and after B
       (Cc7);
     - four `R CMD SHLIB` runs in one directory at once, through
       `parallel::mclapply`, with `RZIG_KEEP_ROOT=1`: four distinct
       roots (SZ H2; Cc12);
     - the grep for configure scripts that run SHLIB (J; Cg14).
4. **Texts, the number, stress's data.**
   - Changes:
     - README;
     - make-wheel.py's descriptions;
     - recipe.yaml: the number and its history entry;
     - pixi.toml's contract comment;
     - stress.yaml's `builder` description and stress/README.md;
     - the records (section 9).
   - Tests: `conda-package` and `conda-consume` (the number), `wheel`
     (the descriptions), and a YAML load of stress.yaml.
5. **Other hosts, CI, the dispatch, the records.**
   - omicron and kappa (section 6).
   - The PR gets the `full-ci` and `upstream-zig` labels: the patch and
     rzig changed.
   - The stress dispatch on the PR's branch (J).
   - The record's test results, with each host's three values.
   - Hand the user the commit and PR commands, with no trailer and no
     session link.

## 3. Per file: the exact change

### zigbuild/tools/rzig/pkgplan.zig (step 1)

- **Header (1-16):** a paragraph on SHLIB mode, `rzig build --shlib`
  (patch 0013's `.rzig_build`). It plans `R CMD SHLIB`'s call as
  `.shlib_internal` derives it. The inputs are the files R names, not a
  directory listing. There is no configure, src/Makefile or build.zig
  lookup, because make runs explicit `-f` files there. An Objective-C
  file, a ready `.o`, or a single quote in the linker words needs make.
- **`Shlib`, and `Options.shlib: ?Shlib = null`** (Options 73-98):

  ```zig
  /// R CMD SHLIB's call, as .shlib_internal parsed it (patch 0013).
  pub const Shlib = struct {
      /// argv's source and object files, in argv order, as given:
      /// relative to the working directory, or absolute (cpp11, TMB)
      files: []const []const u8,
      /// -o / --output as given, else the first file's stem + SHLIB_EXT
      /// (install.R:2836-2837), possibly with a directory
      output: []const u8,
      /// argv's other words, space-joined: make's command-line PKG_LIBS,
      /// which overrides a Makevars' (install.R:2996-2998)
      pkg_libs: ?[]const u8 = null,
  };
  ```

- **`makevarsIn(p, dir) ?[]const u8`:** classify's candidate loop
  (147-153) factored out: Windows `Makevars.ucrt`, `Makevars.win`, then
  `Makevars`; unix `Makevars` (install.R:2850, 2873).
  - `classify` calls it, with no change in behaviour.
  - `classifyShlib(p, dir, shlib)` returns:
    - `.make` with "an Objective-C source, `<f>`" for the first
      `.m`/`.mm`/`.M` in `files`;
    - `.make` with "a single quote in the linker words ('<pkg_libs>'):
      it changes make's own command line" when `pkg_libs` holds a `'`
      (Cg9, Cc2). R pastes these words raw into `PKG_LIBS='…'`
      (install.R:2996-2998), so a `'` closes R's quoting and passes
      words to make itself, as pkgload's and RStudio's
      `' --always-make … IGNORED='` do. A `"` stays inside R's quotes
      and is the recipe shell's, which shellwords mirrors. Files and the
      output go through `shQuote` (install.R:2849, 2946);
    - otherwise `.{ .tier = .makevars, .makevars = makevarsIn(dir) }`.
- **`plan()` in SHLIB mode** (`opts.shlib != null`):
  - **177-179:** `srcs` is `s.files`, not `listSources`. `with` takes
    each file's `langOf`; a `.o` adds no language (install.R:2807-2833).
  - **195:** no `R_PACKAGE_NAME`. make under SHLIB has only the
    environment's, which `importEnvironment` already brings (SZ H11).
  - **208 (Cc11):** "cannot read `<mv>`" names the file without `src/`
    in SHLIB mode.
  - **214:** `output` is `basename(s.output)`.
  - **216-220:** OBJECTS is each file's stem with its directory, plus
    `.o`, in argv order (R's `sub("\\.[[:alnum:]]*$", "", a)`,
    install.R:2807). As before, it is not set when the Makevars sets
    OBJECTS.
  - **229 (Cc11, Am7):** the "Unknown C++ standard … was ignored"
    warning goes in both modes under B (iii) ★. R's own parse runs
    first and gives it (install.R:2867, 2890). pkgplan warns only when
    its caller asks (`Options.warn_cxx_std`), which the preflight
    (`--rzig-check=package`, before R's parse) does. Under B (ii) only
    SHLIB mode leaves it unset.
  - **New, after the overrides:** `setCommandLine("PKG_LIBS", v)` when
    `s.pkg_libs` is set.
  - **274-275 (H8, both modes; Cc10):** `P_FCFLAGS` only when
    `isFile("<src_dir>/Makevars")`, and the chosen file has a line that
    starts, after spaces, with `PKG_FCFLAGS`. This is install.R:3002-3004:
    its `^\s*PKG_FCFLAGS` reads the chosen file's lines, but its
    `file.exists("Makevars")` is literal. `lineStarting` does not allow
    leading spaces, so this test is its own.
  - **288:** the Makevars' reason names the file as `Makevars` (or
    `Makevars.win`), not `src/...`, because it is in the working
    directory.
  - **316-326:** the source lookup accepts absolute paths. A candidate
    that `std.fs.path.isAbsolute` is tested as it is; anything else as
    `<src_dir>/<candidate>`.
    - The Source's `path` stays as R named it, and OBJECTS keeps
      `.SUFFIXES` order, as make does. So an argv `foo.cpp` with a stray
      `foo.c` beside it compiles `foo.c`, as make's suffix rule would. A
      unit test records this.
    - An object with no source gives "no source for `<o>` (a ready
      object: make links it)" in SHLIB mode, and today's text for
      packages.
  - **340:** `env` is empty in SHLIB mode. The steps inherit rzig's
    environment, as make's recipes do, including `CLINK_CPPFLAGS` and
    any `R_PACKAGE_NAME`.
  - **362-367 (macOS; Cc5, Cc14):** `-Wl,-install_name,<s.output as
    given>`. make links with `-o $(SHLIB)` as R passed it
    (`sourceCpp_2.so`, `src/model.so`), and zig's linker, the linker on
    both paths, records the `-o` path as given. The comment says "zig's
    linker", not ld64.
  - **370-373 (Windows; Cc13, Am4):** `name` is `basename(s.output)`
    with a trailing `.dll` removed, exactly winshlib.mk's
    `$(shell basename $(SHLIB) .dll)`. So `<BASE>-win.def` in the working
    directory is linked when it exists, else `def = true` (`rzig def`).
- **Unit tests,** on the modelled R_HOME:
  - "shlib: argv's files only": `foo.c` named, with an invalid `junk.c`
    and a `bar.cpp` in the directory. The sources are `foo.c` alone, the
    C link, and output `foo.so`.
  - "shlib: argv order, an output with a directory, macOS install
    name": `b.cpp a.c`, `-o sub/x.so`. OBJECTS is `b.o a.o`, the C++
    link, output `x.so`, and `-Wl,-install_name,sub/x.so` on macOS.
  - "shlib: absolute sources": `model.cpp` and `<abs>/libTMB.cpp`. The
    second Source's path is absolute, and its object is `<abs>/libTMB.o`.
  - "shlib: the working directory's Makevars":
    - `CXX_STD=CXX17` with `PKG_CPPFLAGS` gives the CXX17 overrides;
    - on Windows, `Makevars.win` wins over `Makevars`;
    - `OBJECTS =` drops the command line's OBJECTS;
    - a rule gives NeedsMake with "Makevars has a rule or target line".
  - "shlib: argv's PKG_LIBS overrides the Makevars'": a Makevars
    `PKG_LIBS = -lfoo` with pkg_libs `-lm` gives libs with `-lm` and
    without `-lfoo`.
  - "shlib: Objective-C and a ready object need make".
  - "shlib: a single quote in pkg_libs needs make; a double quote does
    not": pkgload's exact `' --always-make -I"/x" IGNORED='`, and
    `-L"/a b" -lfoo`.
  - "shlib: no R_PACKAGE_NAME; empty env".
  - "shlib: Windows `.def`": `x-win.def` in the directory, or `def`; an
    output `x.so` on Windows looks for `x.so-win.def`, as make does.
  - "shlib: a stray foo.c beside the named foo.cpp".
  - "P_FCFLAGS as R tests it": Windows with `Makevars.win` holding
    `PKG_FCFLAGS` and no `Makevars` gives none; with a `Makevars` too it
    is given; an indented line counts.

### zigbuild/rpkg/build_t1.zig (step 1)

- **compileAll (127):** the step's input is `s.path` itself when it is
  absolute, else `pathJoin(srcdir, s.path)`. `std.fs.path.join` joins
  naively, so an absolute `s.path` would name a file that does not exist
  (SZ §2, H4).
- **compileAll, the Fortran chain (Cc3):** when the plan has more than
  one Fortran source (`f` or `f9x`), each Fortran compile step depends on
  the previous Fortran step, in OBJECTS order (`step.dependOn`). C and
  C++ compiles stay parallel.
  - The comment says why: flang writes a module's `.mod` into the
    working directory, and a later `use` reads it there. R runs make with
    no `-j` (install.R:3025-3029, 3088), so make compiles OBJECTS in
    order, and zig build would otherwise run them at once. `.f` is
    included, since fixed form can hold a module too.
  - This holds for tier-1 packages as well, which had the same latent
    race. recipe.yaml's history says so.
- The comment at 105-115 adds: "a source outside srcdir (R CMD SHLIB's
  absolute paths: cpp11, TMB) is named as R named it; make names it so
  too".
- Its content keys the shared runner, so every R and zig gets one new
  `build-runner-<key>` directory. The old one goes after a week of
  disuse (feat-shared-build-runner's sweep).

### zigbuild/tools/rzig/pkgbuild.zig (step 1; open points C, E, F, M)

- **Header and usage (9-31, 45-52):** add

      rzig build --shlib --output <lib> [--pkg-libs <words>] [--use-lto yes|no] [--c-std NN]
                 [--debug] [-j N] [--dry-run] [--plan-only]
                 [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>] [--keep-root] -- <file>...

  - One paragraph: R CMD SHLIB's call from `.shlib_internal` (patch
    0013's `.rzig_build`), run in R's working directory.
  - One line on stability (Cc4): "TMB keeps an R's `.shlib_internal`
    body, and with it the arguments `.rzig_build` passes: flags are
    added, never removed or renamed".
  - There is no `--preclean` or `--clean` (E (a) ★; Cg6).
- **Args and parseArgs (54-116):**
  - new fields `shlib`, `output`, `pkg_libs`, `files`, `dry_run`;
  - after `--`, every word is a file;
  - with `--shlib`, any of `--pkg`, `--src`, `--out`, `--flat`,
    `--name`, `--linkingto`, `--cxx-std` or `--classify` is a usage
    error, exit 2, as is no `--output` or no file. Under `auto`,
    `.rzig_build` takes exit 2 as the make path (Cc4).
- **`Inputs.shlib: ?pkgplan.Shlib = null`** (211-224). `decide` calls
  `classifyShlib(in.src_dir, s)` in place of `classify` when it is set
  (226-256). check.zig's preflight never sets it.
- **`run` (271-469):** with `args.shlib`, `return runShlib(ctx, args)`.
  - The code after the plan moves into one function,
    `zigBuild(ctx, plan, tier, root, build_file, out, args, label)`:
    find_zig, `zigBuildDirs`, `reportCompilers`, the zig build command,
    the trace, the spawn and the exit.
  - `run` and `runShlib` both call it, so tier 1 stays one path.
  - **The missing build file (Cc8):** for tier 1, in both modes, a
    missing `R_HOME/share/zig/rpkg/build_t1.zig` gives "`<file>` is
    missing: R_HOME/share/zig/rpkg is not installed; make builds this"
    and exit 3. It is a damaged tree, as "no rzig" is.
  - Tier 2 keeps exit 1, since make cannot build it. A root that cannot
    be made, and a zig build that fails, stay 1.
- **`runShlib(ctx, args)`:**
  1. `r_home` as `run` finds it; `cwd = canonical(".")`; `out_abs` is
     the output joined to `cwd` unless absolute; `out_dir` is its
     dirname, created for a build as `run` creates `--out` (333-337),
     not for `--dry-run` or `--plan-only`; `name` is
     `stem(basename(output))`.
  2. `decide` with `.pkg_dir = cwd`, `.src_dir = cwd`, `.name = name`,
     `.shlib = .{ files, output, pkg_libs }`, use_lto, c_std, debug and
     rzig.
  3. `.make`: "`<output>` needs make: `<reason>`" on stderr (as
     `needsMake`, 717-720, with the output as given).
     - With `--dry-run` or `--plan-only`: exit 3.
     - Otherwise `check.groupsFor(ctx, output, reason, fortran)`, where
       `fortran` is any `f`/`f9x` file (Cg5, Cc9):
       - all there: exit 3, and R runs make;
       - a group missing: its line and text are printed, compilers first
         then the build tools, and the call exits with the code (127, or
         1 for a zig that is not R's). R returns that without running
         make (open point F).
  4. `--plan-only`: plan.zon on stdout, exit 0.
  5. `--dry-run`: `printCommands` on stdout, exit 0. It needs no zig and
     makes no build root (open point C).
  6. **The build root (M (b) ★; Cg15):** `<base>/` plus
     `cache.tempName(ctx, ".rzig", "")`, which is `.rzig.<16 hex>`,
     unique per call (SZ H2).
     - `<base>` is `R_SESSION_TMPDIR` when it is set to an existing
       directory, as every R sets it for its children (sysutils.c:2712;
       Am5); else `out_dir`.
     - A `defer` removes it on every return unless `--keep-root` or
       `RZIG_KEEP_ROOT`, as at 347-353.
     - A call killed with R alive leaves it in R's session directory,
       which R removes when it exits.
  7. plan.zon goes into it, then `zigBuild` runs with
     `R_HOME/share/zig/rpkg/build_t1.zig`, `--prefix <out_dir>`, and
     `libs_dir = ""`.
     - The trace line is `rzig build: R CMD SHLIB, tier 1, root <root>`.
     - It does not start with "rzig build: tier 1", so pkg-parity's and
       verify-bundle's package greps cannot take a configure script's
       SHLIB for the package's tier.
- **`printCommands(ctx, plan, output)` (Cc2):** one line per source, in
  plan order, then the link block. Each word goes through
  `shellwords.quote`. The objects are named as make names them,
  `<base>.o`. The link block is the wrapper make -n prints for
  shlib.mk's recipe, so no line that runs the linker starts with the
  compiler. A plain dry run then stays well-formed for pkgload-style
  filters, which keep lines that start with a compiler and expect one
  `-c` in each:

      <toolchain>/<tool> <flags...> -c <source> -o <object>
      if test "z<objects>" != "z"; then \
        [<rzig> def -o <BASE>.def <objects>; \]          (Windows, no <BASE>-win.def)
        echo <toolchain>/<link_driver> <link...> -o <output as given> [<BASE>-win.def | <BASE>.def] <objects...> <libs...>; \
        <toolchain>/<link_driver> <link...> -o <output as given> [<BASE>-win.def | <BASE>.def] <objects...> <libs...>; \
      fi

  Rcpp's macOS plugin reads only the first line after "make would use":
  the first compile line.
- **Unit tests:**
  - the arguments, including a usage error for `--shlib --pkg`;
  - the root name: under `R_SESSION_TMPDIR`, else beside the output;
    unique across two calls; gone after; kept with `RZIG_KEEP_ROOT`;
  - the `--dry-run` text, including a word that needs quoting, and the
    link block: applied to the output, pkgload's filter (lines starting
    with the compile tool) and `-c` extraction give equal counts;
  - with a needs-make plan:
    - an empty PATH and no zig gives 127, the compilers' text, then the
      line and the build-tools text;
    - an empty PATH with a zig stand-in gives 127 and the build-tools
      text alone;
    - a stand-in `make` and zig give 3;
  - a missing build_t1.zig gives 3 and the line.

### zigbuild/tools/rzig/check.zig (step 1; open point F)

- **`pub fn groupsFor(ctx, label, why: ?[]const u8, fortran: bool)
  !Result`** (Cg5, Cc9): the check `packageIn` makes today (291-317),
  taken out of it.
  - It checks the compilers (flang when `fortran`). When `why` is set,
    it also checks the build tools, with the line "`<label>` needs make:
    `<why>`; `<what>`".
  - Every missing group goes in one stop, compilers first (phase 4 H a).
  - It returns 0 with the found lines, 127 when a group is missing, and
    1 for a zig that is not R's.
- `packageIn` calls it, with no change in behaviour. Its unit tests are
  unchanged. It sets pkgplan's `warn_cxx_std`, so the preflight still
  prints "Unknown C++ standard" (pkgplan, 229).
- `Found` and `buildToolsFound` stay private.
- The header (1-60) adds: "`rzig build --shlib` (pkgbuild.zig) stops
  through `groupsFor` when a call needs make".

### zigbuild/tools/rzig/shellwords.zig (step 1)

- `pub fn quote(a, word) ![]const u8`: the word itself when it holds
  only `[A-Za-z0-9_@%+=:,./-]`, else single-quoted with `'\''`.
- Unit test: for sample words, `split(join(quote(w)))` gives back `w`.

### zigbuild/tools/rzig/main.zig (step 1)

- usage (137-144): `rzig build --shlib --output <lib> [options] -- <file>...`.

### zigbuild/tools/rzig/parity-test.sh (step 1)

These run the real binary with the real zig and the repo's rpkg, on
linux. A `sh_build` helper is added beside `pkg_build` (701-704). It
runs in `$W/sh/<n>` with `R_HOME=$rh` and `--rpkg-dir`, and with
`R_SESSION_TMPDIR=$W/sh/<n>.tmp` where a case checks the root.
- `--shlib --plan-only -- foo.c` beside an invalid `junk.c`: the plan
  names `foo.c` alone.
- A real build: `foo.so` is made. There is no `foo.o`, no `.rzig.*`
  beside it or in `R_SESSION_TMPDIR`, and no `junk` compile in the
  trace. The runner directory has no file added (`runner_files`, 833).
- An absolute source outside the directory builds.
- Two Fortran 9x sources, `use_m.f90` naming `mod_m.f90`'s module, given
  in that dependency order: builds at `-j 8`, five times in a row
  (Cc3).
- `--dry-run` with `PATH=$W/nothing` and no zig: exit 0, the first line
  `<tc>/zig-cc ... -c foo.c -o foo.o`, the link block, and no root.
- pkgload's injected word as `--pkg-libs`: exit 3, "a single quote in
  the linker words" (Cg9).
- No zig: 127, the compilers text, the root gone.
- A Makevars rule:
  - with no make and no zig on PATH: 127, "foo.so needs make: Makevars
    has a rule or target line", the compilers' text first and then
    `^Building packages needs the r-zig build tools for R ` (Cg5);
  - with zig but no make: the build-tools text alone;
  - with a make stub: 3.
- Two `rzig build --shlib` runs at once in one directory, with different
  outputs and `RZIG_KEEP_ROOT=1`: both exit 0, and there are two
  distinct roots, each with its own `plan.zon`, which the case then
  removes (H2; Cc12).
- A missing build_t1.zig (`--rpkg-dir` an empty directory): 3 and the
  line (Cc8).

### zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch (step 2; open points B, C, G, I)

The file keeps its name. It becomes the one rzig-build patch, with no
0014 (B (iii) ★; Cg3).

**Header:**

    R CMD INSTALL and R CMD SHLIB: build with rzig build (zig build alone)

    .shlib_internal asks R_HOME/bin/toolchain/rzig before its make path,
    for R CMD SHLIB's files and for R CMD INSTALL's package, which
    run_shlib names (pkg =): one hook. `rzig build` (a package: no
    src/Makefile, which install.R runs with make before it gets here, and
    its own src/build.zig, or no configure and a Makevars of assignments
    only [code-2]) or `rzig build --shlib` (the files named, the output,
    the other words as make's PKG_LIBS, the working directory's Makevars)
    derives from etc/Makeconf, the site and user Makevars and the
    environment what make would have run, and runs it as zig build steps
    that call the same compilers. Exit 3 means it needs make, and the
    make path runs unchanged; with no make on PATH rzig says so and names
    the missing groups (exit 127). A src/build.zig package that make
    cannot build fails, exit 1 [preflight-PF-1]. The top-level
    .rzig_build holds every rule: R_ZIG_PKG_BUILDER=auto|zig|make (zig:
    an error where make would run [preflight-PF-4]; make: never rzig),
    R_ZIG_JOBS else MAKEFLAGS' -j, the user Makevars R found as
    R_MAKEVARS_USER [code-5], and the spawn without a shell
    (.Internal(spawnWait()), patch 0012, on unix; system2() on Windows).
    .shlib_internal passes R's parsed values only: TMB keeps that body
    from the R that installed it, so .rzig_build's arguments are added,
    never removed or renamed, and a missing .rzig_build is the make path.
    --dry-run prints R's make command as before, then the commands rzig
    would run in make -n's form (Rcpp's macOS OpenMP plugin reads the
    first). --clean and --preclean act on the make path only: rzig keeps
    no object beside the sources. symbols.rds is not made on the rzig
    path. A child a signal ends reads as its raw wait status (sys-unix.c),
    so SIGQUIT reads as 3, make. patch_rpaths reads the OS from
    Sys.info() instead of `uname -a`. A src/build.zig alone counts as
    compiled code. The install preflight (patch 0009) decides the tier
    the same way, through `--rzig-check=package`.
    .github/devdocs/feat-zig-pkg-build/PLAN.md,
    .github/devdocs/feat-shlib-rzig-build/PLAN.md.

**Code** (install.R, patched lines):

- **The top-level helper,** in a hunk of its own after `makevars_site`
  (patched 3536) (Cg4, Cc4):

  ```r
  ## r-zig (patch 0013; feat-zig-pkg-build, feat-shlib-rzig-build): the
  ## native library through zig build alone, before .shlib_internal's make
  ## path: `rzig build` for R CMD INSTALL's package (`pkg`, from
  ## run_shlib), `rzig build --shlib` for R CMD SHLIB's files. NA: the make
  ## path (R_ZIG_PKG_BUILDER=make, no rzig, rzig's exit 3 = needs make, or
  ## 2 = usage under auto); otherwise the status .shlib_internal returns.
  ## Every rule lives here: TMB keeps .shlib_internal's body from the R
  ## that installed it (TMB.R:55), so arguments are added, with defaults,
  ## never removed or renamed. .github/devdocs/feat-shlib-rzig-build/PLAN.md.
  .rzig_build <- function(pkg = NULL, files = character(), output = "",
                          pkg_libs = character(), use_lto = NA, use_C = "",
                          debug = FALSE, dry_run = FALSE)
  {
      builder <- Sys.getenv("R_ZIG_PKG_BUILDER", "auto")
      if (builder == "make" || (is.null(pkg) && !length(files))) return(NA)
      zig_only <- builder == "zig" && !dry_run
      stop_zig <- function(msg) {
          message("ERROR: ", msg,
                  if (!is.null(pkg)) paste(" for package", sQuote(pkg)),
                  domain = NA)
          1L
      }
      windows <- .Platform$OS.type == "windows"
      rzig <- file.path(R.home(), "bin", "toolchain",
                        if (windows) "rzig.exe" else "rzig")
      ## no rzig: a damaged tree, since every channel ships it
      ## (feat-standalone-toolchain phase 4) [preflight-PF-4]
      if (!file.exists(rzig))
          return(if (zig_only)
                     stop_zig("R_ZIG_PKG_BUILDER is 'zig' and R_HOME/bin/toolchain has no rzig")
                 else NA)
      args <- if (is.null(pkg))
                  c("build", "--shlib", "--output", output,
                    if (length(pkg_libs))
                        c("--pkg-libs", paste(pkg_libs, collapse = " ")),
                    if (dry_run) "--dry-run")
              else c("build", "--pkg", "..", "--src", ".", "--out", ".",
                     "--flat", "--name", pkg)
      if (isTRUE(use_lto)) args <- c(args, "--use-lto", "yes")
      else if (isFALSE(use_lto)) args <- c(args, "--use-lto", "no")
      if (nzchar(use_C)) args <- c(args, "--c-std", as.character(use_C))
      if (windows && debug) args <- c(args, "--debug")
      jobs <- Sys.getenv("R_ZIG_JOBS")
      if (!nzchar(jobs))
          jobs <- regmatches(Sys.getenv("MAKEFLAGS"),
                             regexpr("(?<=-j)[0-9]+", Sys.getenv("MAKEFLAGS"),
                                     perl = TRUE))
      if (length(jobs) == 1L && grepl("^[0-9]+$", jobs))
          args <- c(args, "-j", jobs)
      if (is.null(pkg)) args <- c(args, "--", files)
      ## the user Makevars R found, which rzig then reads in place of its
      ## own lookup: R's `~` falls back to the passwd home when HOME is
      ## unset (unix), rzig's does not [code-5]. When R found none,
      ## neither does rzig. The caller's value comes back after.
      mu <- makevars_user()
      mu_was <- Sys.getenv("R_MAKEVARS_USER", NA_character_)
      if (length(mu)) Sys.setenv(R_MAKEVARS_USER = mu)
      on.exit(if (is.na(mu_was)) Sys.unsetenv("R_MAKEVARS_USER")
              else Sys.setenv(R_MAKEVARS_USER = mu_was))
      status <- if (windows) system2(rzig, shQuote(args))
                else .Internal(spawnWait(c(rzig, args), 0L))
      if (identical(status, 3L))
          return(if (zig_only)
                     stop_zig(paste(if (is.null(pkg)) "this shared object"
                                    else "this package",
                                    "needs make, and R_ZIG_PKG_BUILDER is 'zig'"))
                 else NA)
      if (identical(status, 2L) && !zig_only) return(NA)
      status
  }
  ```

  - **The texts:** I-PF4's text and "this package needs make, and
    R_ZIG_PKG_BUILDER is 'zig'" keep their wording, which
    pkg-parity.sh:400 and the tests grep.
  - In package mode they now print through `message()` with
    pkgerrmsg's " for package '<pkg>'" suffix, and run_shlib's existing
    "ERROR: compilation failed for package" follows them (Cg3's check).
  - Package mode has no dry run, since R CMD INSTALL has none.
- **`.shlib_internal`'s signature (2665):**
  `.shlib_internal <- function(args, pkg = NULL)`, with a comment:
  "r-zig: `pkg`, R CMD INSTALL's package from run_shlib, for rzig
  build's package mode (patch 0013, .rzig_build)".
- **2741:** `files <- character()` beside `objs`.
- **The argument loop (2839):**

  ```r
              if (nzchar(nobj)) {
                  objs <- c(objs, nobj)
                  files <- c(files, a) # r-zig: the file as named (patch 0013)
              }
              else pkg_libs <- c(pkg_libs, a)
  ```

- **After `cmd` (3025-3026), and the dry run (3027-3031):**

  ```r
      ## r-zig (patch 0013): rzig build first (.rzig_build); NA is the make
      ## path below. This body passes R's parsed values only: TMB keeps a
      ## copy of it, and the rules are .rzig_build's, in the R that runs.
      rzig_first <- function(dry)
          if (exists(".rzig_build", mode = "function"))
              .rzig_build(pkg = pkg, files = files, output = shlib,
                          pkg_libs = pkg_libs, use_lto = use_lto,
                          use_C = use_C, debug = WINDOWS && debug,
                          dry_run = dry)
          else NA
      if (dry_run) {
          cat("make cmd is\n  ", cmd, "\n\nmake would use\n", sep = "")
          if (!identical(rzig_first(TRUE), 0L)) system(paste(cmd, "-n"))
          res <- 0
      } else {
          res <- rzig_first(FALSE)
          if (!is.na(res)) return(res)
          ## first report versions of involved compilers
          ...                        # unchanged
  ```

  - A dry run never cleans, as make's never does. `--preclean` and
    `--clean` reach only the make path below (E).
  - In package mode, `.shlib_internal`'s parse now runs before rzig.
    R's "specified C++NN" message and its C++98 / "CXXnn is not
    defined" stops come first for tier-1 packages, as on the make path.
    That is a log difference from `_9`, toward make (Am7).
- **run_shlib (759-786):** 0013's `zig <- rzig_build(...)` lines and the
  `rzig_build` closure go. The call becomes
  `if (.shlib_internal(args, pkg = pkg_name) == 0L) {`, with the
  comment "r-zig: rzig build decides for the package first (patch 0013,
  .rzig_build)". Its existing branch then runs `shlib_install`, as for
  make.
- **`.SHLIB` (2658-2663) is unchanged.** `.shlib_internal(commandArgs(TRUE))`
  takes `pkg = NULL`. TMB's one-argument call (TMB.R:1472) does too.
- **Kept as they are:** the patch_rpaths hunk (`Sys.info()`) and the
  allfiles hunk (`build.zig`).
- **Under B (ii) instead:** run_shlib keeps a `rzig_build` closure that
  calls `.rzig_build(pkg = pkg_name, …)` and runs `shlib_install` on 0.
  Its make fallback calls `.shlib_internal(args, rzig = FALSE)`, a second
  argument that keeps the hook from asking again (SZ H1). The helper is
  the same.

### scripts/pkg-parity.sh (step 2): SHLIB parity

A section after "tier 1", on the compile tree, where make runs:
"`R CMD SHLIB`: through rzig build and through make".

**The shapes.** Each runs in its own fresh directory, twice:
`RZIG_TRACE=1` with the default builder, then `RZIG_TRACE=1
R_ZIG_PKG_BUILDER=make`. Output names use `$SO` (`.dll` on Windows;
Cc13).

| shape | call | from |
|---|---|---|
| probe | `R CMD SHLIB foo.c` beside an invalid `junk.c` and an old `x.cpp` | pkgbuild's has_compiler (SC §1.1) |
| sourceCpp | `CLINK_CPPFLAGS='-I"<dir>/inc"'`, `R CMD SHLIB -o 'sourceCpp_1.$SO' file1.cpp` | Rcpp (SC §4.1) |
| cpp11 | `<d>/src/Makevars` = `CXX_STD=CXX11` and `PKG_CPPFLAGS=-I'<d>/inc'`; `R CMD SHLIB <abs>/a.cpp <abs>/cpp11.cpp --output=pkg.$SO` from `<d>/src` | cpp11 (SC §4.2) |
| TMB | `Rscript -e 'stopifnot(tools:::.shlib_internal(c("model.cpp", "<abs other dir>/lib.cpp")) == 0)'` with `R_MAKEVARS_USER` = `PKG_CPPFLAGS=-I"<dir>" -DLIB_UNLOAD=R_unload_model` and `PKG_LIBS=$(SHLIB_OPENMP_CXXFLAGS)` (where Makeconf has it) | TMB (SC §4.5) |
| Fortran | `R CMD SHLIB -o fs.$SO fs.f`, then with a Makevars `USE_FC_TO_LINK =` | inline, knitr |
| Fortran modules | `R CMD SHLIB -o fm.$SO mod_m.f90 use_m.f90`, with `MAKEFLAGS=-j8` for the rzig run | Cc3 |
| PKG_LIBS | a Makevars `PKG_LIBS = -lnosuchlib`, `R CMD SHLIB p.c -lm` | argv's PKG_LIBS overrides the Makevars' |

**Each shape asserts (Cc5):**
- the rzig run's log has `rzig build: R CMD SHLIB, tier 1`, and no
  recipe make echoed (`make_recipes`);
- the make run's log has no `rzig build:` line, and `make_recipes` is
  not empty;
- `argv_of` gives at least two lines on each path, and they are
  identical. The TMB shape's absolute `-c` operand is expected on both
  paths, so `abs_sources` skips SHLIB logs;
- the exports are identical (nm; Windows objdump);
- each library loads and its function returns the value;
- the rzig run leaves no object and no `.rzig.*` beside the sources.
  Its root was in that R's session directory, which goes with that R;
  parity-test checks the root itself.

**More cases:**
- **pkgload's compilation database (Cc2, Cg9):** on a tier-1 `src/`, in
  R, pkgload's exact call:

      R CMD SHLIB --dry-run -o pkg.$SO "' --always-make <-I flags> IGNORED='" <files>

  - With the default builder, the log has "needs make: a single quote in
    the linker words" and the output is `make -n`'s, identical to the
    run with `R_ZIG_PKG_BUILDER=make`.
  - Then pkgload's filter and `-c` extraction (compilation-db.R:116-131,
    199-207, re-implemented in the test, with the compilers from
    `make … print-compilers`) give equal counts.
  - Then a plain `--dry-run` with no injected word, on the rzig path:
    the same filter and extraction give equal counts. The link block's
    lines do not start with the compiler.
- **Asked once (H1):** the tier-3 check's cli with a `configure`
  installs through make. Its traced log has "cli needs make: a
  configure script" once, and no `rzig build: R CMD SHLIB` line. Under
  B (iii) this holds by construction, and the case keeps it so.
- **`R_ZIG_PKG_BUILDER=zig` (Am8):** a Makevars-rule `R CMD SHLIB x.c`,
  on every OS, exits non-zero. The output has "x.$SO needs make:
  Makevars has a rule or target line" and "ERROR: this shared object
  needs make, and R_ZIG_PKG_BUILDER is 'zig'". Nothing is built.
- **Concurrency (H2; Cc12):** two `R CMD SHLIB` runs started together in
  one directory, `-o a.$SO a.c` and `-o b.$SO b.c`, with
  `RZIG_KEEP_ROOT=1`. Both are 0, both load, and there are two distinct
  `.rzig.*` roots, each with a `plan.zon`. The case then removes them.
- **macOS (Cc5):** `argv_of`'s known difference
  `-Wl,-install_name,<pkg>.so` becomes `<output>`. The `-o sub/x.so`
  case compares `otool -D` of both libraries, since `argv_of` drops the
  install name.
- **Windows (kappa), H8 (Cc10):** a package (not SHLIB) with an `.f90`
  source and a Makevars.win holding `PKG_FCFLAGS`, and no Makevars,
  installs through both paths with identical command lines. Before H8,
  the rzig path had `P_FCFLAGS`.

### scripts/verify-bundle.sh (steps 2, 3; open point F)

**Step 2: the make references stay make.**
- Scenario 2's unix SHLIB runs (871, 923, 949, 1003, 1066-1070, 1110,
  1157-1162) and Windows scenario 3's (1516) get `R_ZIG_PKG_BUILDER=make`
  in their `env -i` lists. They stay the make reference beside the
  shape's package through rzig build (N1). Their echo lines keep
  "(R CMD SHLIB, make)".
- Header 43-51 and 66-68: those runs are make "by R_ZIG_PKG_BUILDER=make;
  R CMD SHLIB's default is rzig build since patch 0013's one hook, tested
  with no make below".

**Step 3, scenario 1 (base alone; Cg5, Cg13):**
- `R CMD SHLIB foo.c` exits non-zero with `$compilers_head`, the text
  pkgbuild's `check_build_tools(debug = TRUE)` shows. Nothing is built.
- A Makevars-rule call exits non-zero with the compilers' text first,
  then "x.$SO needs make: …" and `$build_tools_head`.

**Step 3, scenario 2: "R CMD SHLIB with no make"**, a new block, on every
OS, after pfC.

The environment:
- PATH: unix `$BUNDLE_DIR/bin`; Windows `$R_BINDIR:$sys32`.
- zig through `zig_env` (the user's zig until phase 5).
- For the Fortran shape, a directory holding flang alone: unix a
  symlink; Windows copies of `flang.exe`, `flang-new.exe` and their two
  `.cfg`, as pkg-parity's no-make case has them.
- `RZIG_TRACE=1`, and `RZIG_KEEP_ROOT=1` where the objects are checked.

| case | asserts |
|---|---|
| probe: `foo.c` beside `junk.c`, no `-o` | `foo.$SO` loads and `.C("foo", 0L)[[1]] == 1L` (Windows: the DLL exports `foo`); no `foo.o`; no `.rzig.*` left; the log has `rzig build: R CMD SHLIB, tier 1`, and no `junk` |
| C++: `CLINK_CPPFLAGS`, `-o sourceCpp_1.$SO rp.cpp` | no rpath (`rpaths_of`), no shared C++ runtime (`cxx_deps`), `check_minos` on the library and on the kept root's `obj/0/rp.o`, loads, `.Call("rp") == 6L` |
| Fortran: `-o fs.$SO fs.f` (flang directory) | the static flang runtime, loads |
| cpp11 shape (as pkg-parity) | loads |
| TMB shape (in process, as pkg-parity) | status 0, loads, no `lib.o` written beside `lib.cpp` |
| `--dry-run rp.cpp` | exit 0; the line after `make would use` starts with `<R_HOME>/bin/toolchain/zig-cxx` (Windows `g++.exe`), where `<R_HOME>` is `"$R_BIN" RHOME`, which is the physical path (bin/R's `cd -P`), compared with `/` on Windows (Cc13); nothing built |
| OpenMP (Makeconf offers `SHLIB_OPENMP_CFLAGS`): a Makevars with `PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)` and `PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)` | links libomp, loads, two threads |
| needs make: a Makevars `all: $(SHLIB) extra` with a rule | non-zero exit; `x.$SO needs make: Makevars has a rule or target line`, `no make on PATH`, `$build_tools_head`; nothing built |

The planner's `-c` case is gone (E; Cg6).

### scripts/contract-test.sh (steps 2, 3)

- **Header (11-14) and the report line (207):** "Rcpp's evalCpp compiles
  at run time through R CMD SHLIB, which rzig build builds (patch 0013),
  with no make".
- **Packages (82):** add cpp11, callr, processx and R6. They install with
  the build tools, as ps and pak do, for the step-3 block. cpp11's
  Suggests are not added (Cc1).
- **Step 3: a no-make program,** run with the environment pkg-parity's
  no-make case uses: `env -i`; PATH a directory holding `sh` and flang
  (Windows: System32 and the flang copies); zig through `ZIG_BIN`; and
  `R_LIBS` the test library. It runs:
  - `Rcpp::cppFunction('int f(int x) { if (x < 0) throw std::range_error("neg"); return x; }')`:
    `f(2L) == 2L`, and the exception is caught as a try-error. Also
    `Rcpp::evalCpp("2 + 2") == 4`.
  - **On macOS (Cc6):** `p <- Rcpp:::.openmpPluginDarwin()` with no
    error, and `p$env$PKG_CXXFLAGS == "-fopenmp"`. This runs
    `R CMD SHLIB --dry-run` and `<cxx> --version` only. With no make it
    would fail with a subscript error if nothing followed "make would
    use". Only where Makeconf's `SHLIB_OPENMP_CXXFLAGS` is non-empty
    (not minimal) does it also run
    `Rcpp::cppFunction('int g() { return 1; }', plugins = "openmp")()`.
  - **cpp11's SHLIB call, without its code generator (Cc1):** in a
    temporary `<d>/src`:
    - a Makevars of `CXX_STD = CXX11` and
      `PKG_CPPFLAGS = -I'<cpp11>/include'`;
    - a `code.cpp` using `cpp11::` with a hand-written `extern "C"`
      registration;
    - `callr::rcmd("SHLIB", c(<abs>/code.cpp, "--output=pkg.$SO"), wd = <d>/src)`,
      which is cpp_source's own call (cpp11 source.R:131-143);
    - then `dyn.load` and `.Call`.
  - pak's own probe in its worker:
    `stopifnot(isTRUE(pak:::remote(function() pkgbuild::check_build_tools())))`.
  - `pak::local_install("<tier-1 fixture: src/one.c, no Makevars>",
    lib = <temp lib>, dependencies = FALSE, ask = FALSE)`, then loading
    it. Whether a local install with no dependencies reaches the network
    is checked by hand first (section 6). contract already downloads
    from CRAN.
  - On Windows: `pak:::remote(function() pkgbuild::has_rtools(debug =
    TRUE))`, printed and not asserted (open point H).
- No make on PATH is the evidence that rzig built each one. `sourceCpp`
  keeps SHLIB's output to itself (feat-zig-pkg-build PLAN.md:1188-1192).

### recipe/test-compilers.R and recipe/test-preflight.R (step 3)

test-compilers.R covers r-zig-slim + r-zig-compilers, with the shared
header's narrowed PATH and no make. After the packages:
- **The probe:** `foo.c` beside `junk.c` in a fresh directory, through
  `run_to(<R>, c("CMD", "SHLIB", "foo.c"))` (Windows `Rcmd.exe`). Then
  `dyn.load` and `.C`. There is no `foo.o`. Names use
  `.Platform$dynlib.ext` (Cc13).
- **C++:** `-o sourceCpp_1<ext>`, with `CLINK_CPPFLAGS` set through
  `Sys.setenv` and unset after. It loads.
- **Fortran:** `-o fs<ext> fs.f`, with the env's flang. It loads.
- **The cpp11 shape:** a working-directory Makevars and two absolute
  sources. It loads.
- **A Makevars rule** stops, nothing is built, and the output has:
  - "x<ext> needs make: Makevars has a rule or target line";
  - `^Building packages needs the r-zig build tools for R `;
  - "pixi add r-zig-build-tools (or conda install r-zig-build-tools)";
  - and not "is installed in R's environment".
- Each prints a "compilers: … R CMD SHLIB …: OK" line.
- The header (1-6) says that `R CMD SHLIB` of such code needs no make.

test-preflight.R covers r-zig-slim alone (Cg5, Cg13):
- `R CMD SHLIB foo.c` stops with the compilers group's text: the text
  pkgbuild's `check_build_tools(debug = TRUE)` shows.
- A Makevars-rule call stops with the compilers' text first, then the
  needs-make line and the build tools' text.

### scripts/wheel-test.sh (step 3)

- **r-zig alone:** the two base-alone SHLIB checks of test-preflight.R,
  with the pip lines (Cg5, Cg13).
- **"+ r-zig-compilers"** (no make, `run_venv`, after the console-script
  install):
  - `R CMD SHLIB foo.c` (the probe shape) and `-o cx.so cx.cpp`, through
    PyPI's ziglang. Both load. The C++ one has no shared C++ runtime.
  - A Makevars-rule SHLIB stops with "x.so needs make: Makevars has a
    rule or target line", "no make on PATH" and the build-tools group's
    pip line, "pip install r-zig-build-tools; r-zig-toolchain installs
    every group" (groups.zig, phase 4's H a). Nothing is built.
- **"+ r-zig-build-tools":** the same Makevars-rule SHLIB builds with the
  wheel's make (rzig's exit 3, then make). Its log shows make's echoed
  compile (`make_recipes`).
- Header (17-31) as above.

### stress/packages.tsv, stress/README.md, .github/workflows/stress.yaml (step 4; open point J)

- **packages.tsv:62 (Rcpp):**
  - The smoke becomes
    `{f <- Rcpp::cppFunction('…', showOutput = TRUE); …}`, so the smoke
    log carries R CMD SHLIB's output, and under `--trace` rzig's
    `rzig build: R CMD SHLIB, tier 1` line.
  - The note's "cppFunction compiles at run time through R CMD SHLIB,
    make" becomes "…, rzig build (patch 0013)".
- **packages.tsv:66 (rstan):** the note says its compile goes through
  rzig build, and that on macOS `R CMD config CXX17` follows (open
  point H).
- **stress.yaml's `builder` description (50)** and the README's builder
  line: "R CMD INSTALL and R CMD SHLIB build through rzig build where
  the call qualifies (patch 0013); make: the make path for every package
  and shared object".

### README.md, scripts/make-wheel.py, pixi.toml (step 4)

- **README.md:36-43,** the group bullets (Cg7, Cg8, Cg13, Cc7, Cc14):
  - "`r-zig-compilers` … alone installs packages that have no configure
    script and whose Makevars only sets variables. It also compiles such
    code at run time (`R CMD SHLIB`: Rcpp's `sourceCpp()`, inline, TMB,
    knitr's engines) with no make: R builds them with `rzig build`. Once
    pkgbuild or pak is installed, their compiler check passes too."
  - "`r-zig-build-tools` … is for configure scripts, Makevars rules,
    Objective-C and `R CMD config` (rstan on macOS calls it). Installing
    pkgbuild, pak, devtools or cpp11's `cpp_source()` dependencies from
    source needs it once: processx has Makevars rules, and ps and pak
    have configure scripts. r-zig-toolchain has both groups from the
    start."
  - "If pak or pkgbuild says it could not find the tools, run
    `pkgbuild::check_build_tools(debug = TRUE)`: rzig's text names what
    to install."
  - On Windows: "Rtools is not needed: r-zig's build tools take its
    place. pkgbuild's 'Rtools is required' warning, printed by
    `with_build_tools()` callers such as devtools, can be ignored (open
    point H)."
  - "TMB installed by an earlier build keeps make until it is
    reinstalled. TMB's `precompile()` speeds up only recompiles of one
    model name: each new name compiles the precompiled library again
    (about <step 0's seconds> s) and keeps one more object (about
    <size>) in zig's cache. Where the build tools are installed,
    `R_ZIG_PKG_BUILDER=make` restores make's reuse."
  - "A pak session that probed before r-zig-compilers was installed
    keeps its answer: restart R."
- **README.md:160-172:** the wheel paragraph says the same in the pip
  terms.
- **make-wheel.py:307-312 and 342-350:** the r-zig-compilers and
  r-zig-build-tools descriptions say the same.
- **pixi.toml:94:** "Rcpp's evalCpp through R CMD SHLIB, rzig build".

### recipe/recipe.yaml (step 4)

- The number per B14 (a), with a history entry (Cg10, Cg15, Cc3, Cc10):
  "<n-1> → <n>: R CMD SHLIB through rzig build, one hook with R CMD
  INSTALL (patch 0013; feat-shlib-rzig-build): run-time compilation and
  pkgbuild's compiler check, and so pak, need no make where the code
  needs none. rzig gains `rzig build --shlib`. share/zig/rpkg's
  build_t1.zig takes absolute sources and compiles Fortran in OBJECTS
  order (modules), for packages too. Windows tier-1 packages pass
  `P_FCFLAGS` only with a plain Makevars, as R does (H8)."
- Nothing else. The test list is unchanged, since test-compilers.R and
  test-preflight.R already run.

### Files that need no change (checked)

- **groups.zig:** the build-tools text is reused as it is. Its first
  line says "Building packages …" also for a SHLIB call. That is
  accepted and recorded, since B35's text is one per group (Cg16).
- **The 0009 preflight:** it runs for INSTALL only, through
  `--rzig-check=package`, whose behaviour `groupsFor` keeps.
- **0010:** see open point H.
- **0012:** `spawnWait` is used as it is.
- **build.zig, installRzig, verify-tree.sh:** build_t1.zig is installed
  as before.
- **find_zig.zig, cache.zig:** `tempName` and `root` are reused.
- **makefile.zig:** it imports the environment with make's precedence
  (command line, then files, then environment). So plugin values with
  `$(LAPACK_LIBS)`-style references expand as make expands them, and
  renv's Windows `BINPREF=""` loses to Makeconf's `BINPREF =` (SC §3,
  §5; feat-zig-pkg-build M2's table).
- **hermetic-check.sh, smoke-test.sh:** no `R CMD SHLIB`
  (`git grep 'CMD SHLIB'`, P).
- **The phase 4 copies in `phase4/`,** feat-zig-pkg-build's
  `consolidation/` and fix-zig-pkg-build-review's `review/` are agreed
  copies, left as they are.

## 4. The probes per OS, and 0010

| OS | probe (who) | what runs | today, base + compilers | after |
|---|---|---|---|---|
| linux, macOS | `has_compiler()` through `has_build_tools()` / `check_build_tools()`: pak before every source build (SC §2), pkgbuild::build, compile_dll (devtools, pkgload, odin), remotes | `R CMD SHLIB foo.c` in `tempdir()`, then `dyn.load` and `.C` (pkgbuild compiler.R:41-70, P) | make: not found; FALSE; pak stops the whole plan | rzig build --shlib; TRUE |
| Windows, R ≥ 4.3 | the same `has_compiler()` (build-tools.R:31-37) | `Rcmd.exe SHLIB foo.c` | winshlib.mk needs make, sh, nm and sed; FALSE, and pkgbuild's own "WARNING: Rtools is required" (build-tools.R:43-53; Am3) | rzig, with `rzig def` exporting `foo`; TRUE, no warning |
| every OS, colour terminals | `has_compiler_colored_diagnostics()`, uncached (SC §1.2) | the same, under a user Makevars `CFLAGS += -fdiagnostics-color=always` | FALSE (only the flag is dropped) | rzig reads the `+=` line (makefile.zig) |
| Windows | `has_rtools()`, after the gate, in `with_build_tools` / `local_build_tools` / `rcmd_build_tools` (not pak: pkgdepends skips it for R ≥ 4.3) | `RTOOLS45_HOME/usr/bin`; else `Rcmd config CC` (`sh config.sh`, then 0010, then make); else `ls` and `gcc` on PATH; else the registry, then "WARNING: Rtools is required…" (rtools.R:24-226, P) | WARNING on each call, not cached | unchanged (open point H) |
| remotes, standalone | `has_devel()`: `R CMD SHLIB file<hex>.c` (SC §3) | | a warning | passes |
| base alone, every OS | the same `has_compiler()` | rzig: 127 and the compilers' text, hidden unless `debug = TRUE` (compiler.R:51-59) | FALSE ("make: not found") | FALSE, with rzig's text under `debug = TRUE` (Cg13) |

- **pkgbuild's on.exit order** (compiler.R:41-70, P): `foo.c` is written
  anew each time, and the DLL is unloaded after. So make relinked every
  probe too, and rzig's relink costs nothing extra there (H7 does not
  apply).
- **pak's options cannot skip the probe** (SC §0 fact 3). On base +
  compilers it now passes, so pak installs tier 0 to 2 packages with no
  make, once pak is installed (K).
- **RStudio's `options(buildtools.check)` hook** is called by pkgbuild
  only when the probe fails (build-tools.R:28, 39-41; Am3). So on base +
  compilers it is no longer reached through pkgbuild. RStudio's own
  checks are not surveyed (section 6, "not tested"; Cg16).
- **0010 and `R CMD config`:**
  - On unix, pkgbuild and pak never call `R CMD config` (SC §7).
  - On Windows, `has_rtools()` calls it, and `Rcmd config` runs
    `sh config.sh` before 0010 is reached (rcmdfn.c:532-533, SR §10).
  - rstan on macOS runs `R CMD config CXX17` after every `stan_model()`
    compile. With no build tools, 0010 exits 127 with nothing on stdout,
    and rstan stops with "missing value where TRUE/FALSE needed" after a
    compile that succeeded (SC §7; rstan cxxfunplus.R:186, misc.R:1645).
  - So 0010 does not gate the probes. Open point H keeps it here and
    schedules `R CMD config` through rzig.
- **macOS without the Command Line Tools:** `/usr/bin/make` is an xcrun
  shim that prompts and fails (SC §1.5, unverified). A SHLIB call with
  declarative inputs no longer runs make, so it no longer meets the shim.

## 5. The callers after this PR

| caller | entry | on base + compilers, no make | needs the build tools for |
|---|---|---|---|
| pkgbuild has_compiler / check_build_tools | `R CMD SHLIB foo.c` | passes | installing pkgbuild from source: callr → processx (Makevars rules), ps (configure) (Cc14; K) |
| pak | the probe, then `R CMD INSTALL --build` (0013) | tier 0-2 packages install | pak's own install (configure), tier-3 packages, and on base alone even R-only packages (L) |
| Rcpp sourceCpp / cppFunction / evalCpp | `system2(R, CMD SHLIB -o … [deps] file.cpp)` | builds; the macOS OpenMP plugin's dry run parses rzig's first line (C) | a plugin whose flags hold `$(shell)` or metacharacters (rzig refuses them) |
| cpp11 cpp_source | `callr::rcmd("SHLIB", abs files, --output=)` with a working-directory Makevars | builds | installing callr/processx/ps, and its Suggests brio, decor, desc, glue, tibble, vctrs and cli, which it requires (source.R:69; Cc1, Am1) |
| inline cfunction / cxxfunction | `R CMD SHLIB file.<ext>` in `tempdir()` | C, C++, Fortran build | Objective-C (.m, .mm) |
| TMB compile | in-process `.shlib_internal(c(model.cpp, <TMB>/libs/libTMB.cpp))` | builds, for a TMB installed by this build; precompile's reuse holds within one model name only (D) | TMB installed by `_9` or earlier (its snapshot) |
| rstan stan_model | inline's cxxfunction with plugin "rstan" | the compile builds (the dispatch checks, J) | macOS's `R CMD config CXX17` afterwards (H); installing rstan's configure-script dependencies (RcppParallel) |
| StanHeaders stanFunction | Rcpp's cppFunction under `withr::with_makevars` | builds | — |
| knitr c/cc/fortran engines | `R CMD SHLIB <tmp>.<ext>` from PATH's R | builds | — |
| renv's ext | `R CMD SHLIB renv.c` during renv's install | builds (failure was already ignored) | — |
| nimble | a Makevars with `ifndef`, `.o` includes | — | always (make by design, SC §5) |
| pkgload's compilation database | `--dry-run` with an injected `' --always-make … IGNORED='`, after `make … print-compilers` | — | always: its `compilers()` runs make (compilation-db.R:213-243; Am2), and its dry run goes to make by the quote rule (Cc2, Cg9) |
| RcppParallel's configure probe (macOS) | `R CMD SHLIB probe.cpp`, grepping a `#pragma message` (configure.R:9-41, P) | the pragma's text reaches the output through zig build's step stderr, which build_t1.zig's steps pipe and the build runner prints (build_t1.zig:91-95; build_runner.zig:1381-1388) (checked on omicron) | its configure script itself |
| R's javareconf | `R CMD SHLIB conftest.c` | the compile builds | sh (it is a script) |
| configure scripts that run SHLIB | `R CMD SHLIB` inside a tier-3 install | rzig build, where the probe's inputs qualify | the configure script itself; which rows do it, J's grep (Cg14) |

## 6. Tests per OS and CI

### What each scenario proves

| scenario | standalone (verify-bundle) | conda (recipe test, consume) | pip (wheel-test) | the compile tree (pkg-parity, contract) |
|---|---|---|---|---|
| base alone | scenario 1: SHLIB stops with the compilers' text; a rule call names both groups | test-preflight.R: the same | r-zig alone: the same | parity-test: no zig and no make, both texts |
| base + compilers, no make | scenario 2's new block: probe, C++, Fortran, cpp11 and TMB shapes, dry run, OpenMP, the needs-make stop (Windows too) | test-compilers.R: probe, C++, Fortran, cpp11 shape, the stop naming r-zig-build-tools | + r-zig-compilers: probe, C++ under PyPI ziglang, the stop naming the pip package | contract's no-make program: Rcpp (and the macOS plugin's parse), cpp11's SHLIB call, pak's probe and a pak install |
| with the build tools | scenario 2's and 3's make SHLIB shapes, now `R_ZIG_PKG_BUILDER=make` | test-toolchain.R unchanged | + r-zig-build-tools: the Makevars-rule SHLIB through make | pkg-parity's SHLIB parity: identical command lines and exports for seven shapes, non-vacuous; pkgload's database; H1; builder zig; concurrency; macOS install name; kappa's H8 package |
| rzig itself | — | — | — | rzig-test: unit and parity-test SHLIB cases, both zigs |

### By hand on gamma, recorded

- **TMB:** step 0 before the menus go out (make path), then step 3 on
  this build (Cc7, Cg11).
- **One real `cpp11::cpp_source(code = …)`** with no make on PATH, after
  installing its Suggests with the build tools (Cc1).
- **The first probe** after `rm -rf ~/.cache/r-zig/build-runner-*`:
  `pkgbuild::has_compiler(debug = TRUE)` timed cold and warm, with both
  zigs. feat-shared-build-runner's runner compile is 3.6 s and 1.9 s on
  linux-64.
- **pak on base alone,** with r-zig-slim only:
  - `pak::local_install()` of an R-only package. Does pak stop at the
    probe (SC §0 fact 2)? The answer goes into L.
  - Record the output in the README's terms.
  - This also settles whether a local install with
    `dependencies = FALSE` needs the network: run it with the network
    cut (`unshare -n`, or no proxy).
- **Concurrency (Cc12):** `parallel::mclapply(1:4, function(i)
  system2(R, c("CMD", "SHLIB", "-o", sprintf("m%d.so", i),
  sprintf("m%d.c", i))))` in one directory, with `RZIG_KEEP_ROOT=1`.
  All are 0, all load, and there are four distinct roots.
- **J's grep (Cg14):** the configure scripts of stress/packages.tsv's
  compiled rows, from their CRAN tarballs, for `SHLIB`.

### Per host

| host | runs |
|---|---|
| gamma (linux-64) | steps 0-4; `rzig-test`, `pkg-parity` and `contract` with both zigs; the default and minimal chains; `wheel`, `wheel-test`; `conda-package` and `conda-consume`; the by-hand checks above |
| omicron (osx-arm64) | `rzig-test` (both zigs); `build` → `verify-package`; `pkg-parity` (`otool -D` for an `-o` holding a directory); `contract` (the OpenMP plugin's parse, with no make); `R CMD SHLIB` of a source with a `#pragma message`, whose text must be in the output (RcppParallel's configure probe, section 5); minimal `build`, `verify-package` and `contract` (the parse without the OpenMP compile, Cc6); `wheel`, `wheel-test`; `conda-package`, `conda-consume` |
| kappa (win-64) | `rzig-test` (both zigs); `build` → `verify-package` (the Windows no-make block: `rzig def`'s exports, the Fortran copies, `.dll` names); `pkg-parity` (SHLIB parity against winshlib.mk's make path; the H8 package, Cc10); `contract` (pak's probe; `has_rtools(debug = TRUE)` printed for open point H, and whether `R CMD config CC`'s trailing space resolves, SC §9); `conda-package`, `conda-consume` |
| CI, the PR | the core tier; conda-package's five legs (path filter: recipe/, zigbuild/, scripts/); then `full-ci` (wheel-test on the four unix minimal legs) and `upstream-zig` (the patch and rzig changed); the dispatch (J): `gh workflow run stress.yaml --ref feat-shlib-rzig-build -f packages='g1 <groups of the rows J's grep found>' -f trace=true -f shared_cache=false` on the five runners, reading the Rcpp smoke log's `rzig build: R CMD SHLIB` line, rstan's result and those rows' builders against main d11dee1's run 38569895172 |
| CI, main after merge | the publish of the new number (four files per subdir) |

### Not tested (recorded)

- RStudio's own build-tools checks (Rtools on Windows, the Command Line
  Tools on macOS) beyond pkgbuild's hook (Cg16).
- The macOS `/usr/bin/make` shim on a Mac without the Command Line
  Tools (TODO's item).
- pak's own binary builds against this R (K (c), if chosen).

## 7. Risks

1. **Every `R CMD SHLIB` caller changes builder.** These are the
   recorded differences from make (SZ §6):
   - no `.o` beside the sources (`.mod` files stay, as under make; Cc3);
   - the "using … compiler" lines go to stdout (rzig's
     `reportCompilers`) where R's `message()` used stderr;
   - no "using C++NN" or "using SDK" lines;
   - no make echo of the compile lines;
   - compiler warnings appear under zig build's step headings;
   - the library is relinked on every call.

   pkg-parity's SHLIB parity is the oracle on every OS.
   `R_ZIG_PKG_BUILDER=make` restores make wherever the build tools are
   installed.
2. **TMB's precompile** (open point D a). libTMB.cpp carries each
   model's `-DLIB_UNLOAD=R_unload_<model>` and
   `-DTMB_LIB_INIT=R_init_<model>` (TMB.R:1422-1432, P). So zig's cache
   misses for every new model name, where make reused one `libTMB.o` for
   all of them.
   - Each miss also keeps one more object in zig's global cache, which
     zig never evicts, and prints TMB's "Running TMB precompilation"
     pragma again (Cc7).
   - Step 0 measures the seconds and the size. The README states both.
   - Within one model's edit loop, zig's cache serves it.
3. **TMB installed before this build** keeps the pristine-body
   `.shlib_internal` it captured, and so make (SC §0 fact 4). The README
   says to reinstall TMB. Of the 21 callers the survey unpacked, no other
   captures tools' internals (SC §4; `git grep shlib_internal`, P). CRAN
   as a whole was not searched (Cc14).
4. **The snapshot interface (Cc4).** A TMB installed by this build keeps
   this build's `.shlib_internal` body, which calls `.rzig_build` by
   name with R's parsed values.
   - A later R must keep `.rzig_build`'s argument names, and rzig's
     `--shlib` flags: add, never remove or rename. The record says so.
   - `.rzig_build` missing is the make path. A changed interface
     degrades to make; it does not fail. (Amended after review, r-1:
     rzig's usage exit 2 is a failure, not make, since an rzig that
     Ctrl-C ends reads as 2; PLAN.md, "Review fixes".)
5. **The first call after an install or upgrade** compiles the shared
   runner:
   - linux-64: 3.6 s and 1.9 s;
   - osx-arm64: 5.2 s and 4.5 s;
   - win-64: 10.7 s and 8.2 s

   (conda-forge and upstream zig; feat-shared-build-runner
   PLAN.md:213-218). This is once per machine, not per R session. pak's
   first probe pays it. Where rzig's cache cannot be written (`HOME`
   unset or read-only), `sharedRunner` returns null, and every call
   compiles the runner in its root, so each `cppFunction` or probe pays
   it (pkgbuild.zig `zigBuildDirs`; Cc14).
6. **build_t1.zig's change** gives every R and zig one new runner
   directory (19 to 45 MB). The old one goes after a week.
7. **A call killed while its R lives** leaves `.rzig.<hex>` in R's session
   directory, which R removes when it exits (M b). If R is killed too, it
   stays there, as R's own temporary files do. Outside R (by hand) it is
   beside the output. The name is unique, so the next call is not
   affected.
8. **Plugins and Makevars that rzig refuses** go to make. With no make,
   they stop with F's text naming the reason: `$(shell)`, conditionals,
   a shell metacharacter after expansion, or a single quote in argv's
   linker words.
   - rstan's and RcppArmadillo's plugin values hold none, as far as the
     surveys read: quotes, `-include`, `-Wl,-rpath,'…'` and
     `$(LAPACK_LIBS)` references (SC §4.1, §4.4).
   - The dispatch is the check (J).
9. **pak's worker caches a FALSE probe** until it restarts (SC §2,
   inferred). A user who adds r-zig-compilers to a running session
   restarts R. Recorded in the README.
10. **The base-alone pak limitation** (SC §0 fact 2) is not changed
    here, only its message. The by-hand check records it (L).
11. **The macOS install name with a directory** (`-o src/model.so`) is
    `src/model.so` on both paths: zig's linker records the `-o` path as
    given. A dyld lookup by install name would differ from a flat name,
    but R loads by path. pkg-parity on omicron compares `otool -D` (Cc5).
12. **Windows `has_rtools()` keeps warning** on base + compilers (H).
13. **Configure scripts that run `R CMD SHLIB`** now get rzig build
    inside tier-3 installs. J's grep names the rows, and the dispatch
    compares their results with main's run (Cg14).
14. **The probe hides rzig's text** (compiler.R:51-59). pak and pkgbuild
    users see only "Could not find tools necessary to compile a
    package". The README points to `check_build_tools(debug = TRUE)`
    (Cc8, Cg13).
15. **A child a signal ends** reads as its raw wait status (sys-unix.c:688).
    An rzig ended by SIGQUIT reads as 3, and make runs. This is
    negligible, and noted in the patch header (Cc14). Ctrl-C's SIGINT,
    which R forwards to rzig, reads as 2: `.rzig_build` no longer takes
    2 as make, so an interrupted build fails (review r-1; PLAN.md,
    "Review fixes").
16. **The log of a tier-1 install changes** under B (iii): R's
    "specified C++NN" line now appears, as on the make path (Am7).

## 8. Overlap with other pending work

- **Phase 4.** This work is stacked on it, uncommitted (section 1):
  - it changes 0013 again (one hook) and the recipe's number;
  - phase 4's records stay as they are;
  - a phase-4 review fix is re-applied here against the baseline, then
    what it touches is rerun.
- **Phase 5** (zig in the compilers group) follows this work in this
  plan's order (A). Until then the standalone tests take zig from
  `ZIG_BIN` (Cg1). The two share verify-bundle.sh and the records, so
  they are not run in parallel worktrees.
- **Phase 7** (Windows usr/bin): its item "`R CMD config` without the
  build tools fails with one clear message" (TODO.md) is where
  `R CMD config` through rzig goes on Windows (H). Its "Rtools or Git for
  Windows also on PATH" item is why the README does not advise against
  installing Rtools yet (Cg8).
- **B24's dlltool/as follow-up PR:** no file in common.
- **The zig 0.17 wave (B18):** rzig's new code and build_t1.zig compile
  on 0.16. The wave rebuilds the runner anyway.
- **TODO "Later":**
  - "Depend less on make": this PR does its SHLIB half. `R CMD config`
    is left (H).
  - "A stress dispatch of g1 with trace": this PR's (J).
  - "Tier 2's own compile flags": no overlap.

## 9. Records (steps 4, 5) and the stale references to fix

**New: `.github/devdocs/feat-shlib-rzig-build/PLAN.md`.** It holds:
- why: the user's request and the session's record (A), N2's later item,
  and the departure from the phase order;
- the answers to section 10;
- what changed, per file;
- **the stable interface (Cc4):** `.rzig_build`'s arguments and
  `rzig build --shlib`'s flags are added to, never removed or renamed,
  because TMB keeps `.shlib_internal`'s body;
- the measurements: TMB (step 0 and step 3), the first probe,
  concurrency, the real `cpp_source`, pak on base alone, J's grep;
- the tests per host, with each host's three values (section 1);
- CI and the dispatch;
- what is not tested (section 6);
- the open decisions left;
- this plan and its CRITIQUE.md, copied beside it as phase 4's were
  copied into `phase4/`.

**feat-zig-pkg-build PLAN.md:**
- **Decision 2 (47-48) (Cg3):** a dated note after it, without rewriting
  the decision: "(2026-10: the one hook moved into `.shlib_internal`,
  which run_shlib calls, so that R CMD SHLIB uses it too:
  feat-shlib-rzig-build)". "What must remain on the R side" (214-216)
  gets the same note.
- N2 (717) and fact 8 (783-790) each get a note: "(R CMD SHLIB routed by
  feat-shlib-rzig-build, `_<n>`)".
- "What the build-tools group is for" (1011-1044) is a current
  statement, so it is updated in place with a bracketed date:
  - `R CMD SHLIB` and pkgbuild's probe leave the list, except for the
    shapes that need make;
  - installing pkgbuild, pak and their dependencies from source joins
    it (K);
  - `R CMD config`'s callers stay;
  - "Later items" drops the routing and keeps "revisit 0010" as H's item.

**feat-standalone-toolchain PLAN.md:**
- "What a user gets" rows 272-273 (Cg7):
  - "2 Compile, compilers alone" becomes "`src/` and run-time compiles
    (`R CMD SHLIB`) that `rzig build` builds: no configure script R runs,
    a Makevars that only sets variables, no Objective-C; pkgbuild's
    probe, so pak, once they are installed (installing them from source
    needs the build tools once); not `R CMD config`";
  - the next row: "`configure`, Makevars rules, `R CMD config`, and
    installing pkgbuild, pak and their dependencies from source".
- The phase 3 and phase 4 records (2601-2602 and others) are history and
  are left as they are.

**TODO.md:**
- **The phase order (Cg1):** one line before "Phase 5": "Taken before
  phase 5: R CMD SHLIB through rzig build (feat-shlib-rzig-build, its
  PLAN.md), from 'Later'".
- "Later", "Depend less on make" (757-781): "R CMD SHLIB is done by
  feat-shlib-rzig-build (`_<n>`). Left: `R CMD config` through rzig
  (unix src/scripts/config; Windows with phase 7). That would serve
  rstan on macOS and pkgbuild's Windows `has_rtools()` (H), and would
  also free the `R CMD config` run before a configure script for tier 0
  and 2 packages on unix (feat-zig-pkg-build fact 3) (Cg8)."
- The g1 dispatch item (797-802): ticked with this PR's run.
- New "Later" items:
  - "TMB's precompile across models (D), if users ask";
  - "the build root of R CMD INSTALL's package mode under
    R_SESSION_TMPDIR too, as SHLIB mode's (M c), if a killed install's
    src/.rzig is seen";
  - and the K or L follow-up, whichever the user chooses.

**fix-zig-pkg-build-review PLAN.md "Follow-ups" (502-503) and
feat-shared-build-runner PLAN.md "Follow-ups" (453-454):** "Route R CMD
SHLIB…": done in feat-shlib-rzig-build; 0010: H.

**Stale texts** (found by `git grep 'CMD SHLIB'`, P):
- README.md:42-43, 170;
- make-wheel.py:312, 348;
- pixi.toml:94;
- contract-test.sh:12-14, 207;
- verify-bundle.sh:43-51, 66-68;
- packages.tsv:62.

All are changed in steps 2 to 4. Texts written earlier in this work that
say "patch 0014" say "patch 0013" (B iii).

## 10. Open points (need the user)

Each is a menu. ★ marks the recommendation, and the plan above is
written with it. CRITIQUE.md maps these letters to the planner's.

**A. Which work is next (Cg1).**
- (a) ★ R CMD SHLIB through rzig build now, stacked on uncommitted phase
  4 (this plan), then phase 5.
- (b) Phase 5 (zig in the compilers group) now, the records' order, and
  this plan after it.
- (c) Both at once in two worktrees. They share verify-bundle.sh and the
  records.
- Reason for (a): the session's record of 2026-10-14 names it as next
  after phase 4, its stacked worktree exists, and it does not depend on
  phase 5.

**B. The R hook (was the planner's A and B; Cg3, Cg4, Cc4).**
- (i) Two hooks, 0013 untouched: a self-contained 0014 in
  `.shlib_internal` with the spawn code copied, and `rzig = FALSE` from
  run_shlib. A TODO merges them later.
- (ii) Two hooks and one helper: 0013's `rzig_build` stays in run_shlib,
  `.shlib_internal` gets a second hook, run_shlib's make fallback passes
  `rzig = FALSE`, and both call `.rzig_build`.
- (iii) ★ One hook in `.shlib_internal`, with two modes: run_shlib names
  the package (`pkg =`), and `.rzig_build` holds every rule. 0013 is
  regenerated as the one patch, with no 0014.
- Reason for (iii): one hook as feat-zig-pkg-build decided, no flag,
  "asked once" by construction, and TMB's snapshot holds no rules.

**C. `--dry-run` (Cc2, Cg9).**
- (a) ★ R prints its "make cmd is … make would use" text, then rzig's
  compile lines and its link in make -n's `if test … fi` form. rzig's
  exit 3 gives `make -n` as today, including for pkgload's and
  RStudio's injected single quote.
- (b) The dry run stays make's. Without make, Rcpp's macOS OpenMP plugin
  fails with an uncaught subscript error.
- Reason for (a): the one parsing caller (Rcpp) reads rzig's first line,
  and every compilation-database tool keeps make's exact output.

**D. Objects and reuse: TMB's precompile (SZ H3, H7; Cg11, Cc7).** Step
0's numbers go here before this is answered.
- (a) ★ As tier 1: objects in the build root, every source compiled
  each call, and zig's cache serving what is unchanged. Each new TMB
  model name compiles libTMB.cpp again (<s> s) and keeps one more object
  (<MB>) in zig's cache.
- (b) As make: objects where make writes them, reused by mtime, with
  link-only objects in build_t1.zig.
- (c) As (a), but a source outside the working directory (TMB's
  libTMB.cpp) sends the call to make, so TMB's precompile users need the
  build tools.
- Reason for (a): one build path with tier 1 and no make semantics in
  rzig. The cost falls on one opt-in TMB feature, and it is measured.

**E. `--clean` and `--preclean` on the rzig path (Cg6).**
- (a) ★ Ignored in both modes, as 0013 does for packages. They act on
  the make path only.
- (b) rzig removes make's leftovers (`$(OBJECTS)`, symbols.rds, `.libs`,
  `_libs`) in both modes.
- Reason for (a): rzig never writes or reads objects beside the sources,
  so the flags' purpose holds by construction, with less code.

**F. A call that needs make, with no make (Cg5, Cc9).**
- (a) ★ rzig checks as the install preflight does (`groupsFor`). It
  names every missing group in one stop, compilers first, with the
  reason ("`<lib>` needs make: `<reason>`"), and exits 127 without
  running make.
- (b) Always exit 3: make fails as today ("make: not found").
- Reason for (a): B26 and B35 (rzig names what to install), the same as
  phase 4's H (a), at no R cost.

**G. `R_ZIG_PKG_BUILDER` for SHLIB.**
- (a) ★ One variable for both modes, read in `.rzig_build` only.
- (b) A separate `R_ZIG_SHLIB_BUILDER`.
- Reason for (a): one knob, and the make legs (pkg-parity, verify-bundle,
  stress) want make for everything.

**H. `R CMD config` (0010) and Windows `has_rtools()` (Cg8).**
- (a) ★ Neither changes in this PR. The README records rstan on macOS
  and pkgbuild's Windows warning, with "Rtools is not needed". TODO
  gets `R CMD config` through rzig.
- (b) unix `rzig config` in this PR: rstan works on macOS on base +
  compilers.
- (c) Windows only: the base sets an `RTOOLS45_HOME` default in
  etc/Renviron.
- Reason for (a): neither gates pak or the probe on R 4.6.1, and both
  callers' packages need the build tools to install today anyway (K).

**I. symbols.rds (`_R_SHLIB_BUILD_OBJECTS_SYMBOL_TABLES_`).**
- (a) ★ Not made on the rzig path, as for tier-1 packages.
- (b) R skips the hook when the variable is true, and make makes it.
- (c) rzig writes it from each object's symbol table.
- Reason for (a): consistent with tier 1; only R CMD check reads it.

**J. Stress evidence for run-time compiles (Cg14).**
- (a) ★ A dispatch with `trace = true` on the PR's branch: g1, with
  Rcpp's smoke calling `cppFunction(…, showOutput = TRUE)`, plus the
  groups of the rows whose configure scripts run SHLIB (grep first).
- (b) g1 alone, with the smokes unchanged: only their results.
- Reason for (a): N1 asks every install-based test to assert its
  builder, and the grep keeps the dispatch to the rows that matter.

**K. What base + compilers delivers, and installing pkgbuild/pak (Cg7).**
- (a) ★ Document it: README, wheels and "What a user gets" say that
  pkgbuild, pak, devtools and cpp_source's dependencies install from
  source with the build tools once.
- (b) As (a), and tie it to our own binary repository
  (feat-no-host-paths "Our own repository first"; r-zig-packages), which
  would ship them prebuilt.
- (c) As (a), and check by hand whether pak's own binary builds load in
  this R on linux-64; recommend them in the README if they do.
- Reason for (a): it is true today on every channel, and (b) and (c)
  can follow without changing this PR.

**L. pak on base alone, if the by-hand check confirms that it probes
before R-only packages (Cg12).**
- (a) ★ Document it: pak needs r-zig-compilers even for R-only source
  packages, and `install.packages()` is the base-alone path.
- (b) As (a), and report it to r-lib/pkgdepends (the logical
  `needscompilation` against `"no"`).
- (c) As (a), and add nothing else; revisit with our binary repository.
- Reason for (a): it costs nothing and tells users the working path.
  Filing upstream is the user's call.

**M. Where SHLIB mode's build root goes (Cg15).**
- (a) Beside the output, `<out_dir>/.rzig.<hex>`, as tier 1 uses
  `<out>/.rzig`.
- (b) ★ Under `R_SESSION_TMPDIR` (every R sets it for its children),
  else beside the output. Package mode is unchanged.
- (c) As (b), for package mode too.
- Reason for (b): a killed call leaves nothing in the user's directory
  (no stray `.rzig.*` in a project's `git status`), and R removes the
  directory itself.

(The planner's I, the build number, is dropped: B14 (a) decides it
(Cg10).)
