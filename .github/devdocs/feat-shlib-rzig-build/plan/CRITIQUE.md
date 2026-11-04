# The critiques, verified: SHLIB-IMPLEMENTATION.md

Role: amender. Read-only, 2026-10-15. Nothing in the repo changed, no
git state changed, nothing was built, installed or run. Each point of
`critique-code.md` (Cc1 to Cc14) and `critique-goals.md` (Cg1 to Cg16)
was checked against the code before it went into the amended plan,
`critic/SHLIB-IMPLEMENTATION.md`. The amender's own findings, made while
checking, are Am1 to Am8.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." SHLIB routing keeps build 8, as phases 4, 5 and 6 do, and main
publishes nothing until the user sets the repository variable
`CONDA_PUBLISH` after feat-standalone-toolchain phase 7's bump merges
(its PLAN.md, B14's amendment). Where this critique says the PR bumps to 10,
or names `_9` as the build before it, read: the number stays 8, and
SHLIB routing publishes with phase 7's bump, at the number after
universe's newest (B14 a).

Sources read:
- the planner's plan, `planner/SHLIB-IMPLEMENTATION.md`;
- the worktree `wt/feat-shlib-rzig-build`: pkgplan.zig, pkgbuild.zig,
  check.zig, shellwords.zig, build_t1.zig, patch 0013, pkg-parity.sh,
  contract-test.sh, verify-bundle.sh, build.zig:3691, subst.txt, and the
  records (feat-standalone-toolchain PLAN.md and TODO.md,
  feat-zig-pkg-build PLAN.md);
- R 4.6.1, patched (`surveyor-r/patched/`): install.R, shlib.mk,
  winshlib.mk, src/scripts/SHLIB, sys-unix.c, sysutils.c;
- the callers (`surveyor-callers/`): cpp11, pkgload, pkgbuild,
  pkgdepends, Rcpp, TMB, processx (in pak);
- the session's own record in the user's auto-memory
  (`memory/zig-pkg-build.md`, entry of 2026-10-14);
- `wt/phase4-base.diff` and both worktrees' `git diff` and untracked
  files, read-only.

Verdicts:
- **Accepted:** the evidence holds and the amendment is taken as
  proposed.
- **Accepted, changed:** the evidence holds; the amendment taken differs,
  for the reason given.
- **Partly accepted:** part of the evidence or of the amendment holds.
- **Rejected:** with the reason.

No point was rejected outright. Two were taken only in part (Cg1, Cc8).
Several were merged where both critics found the same thing.

## Summary

The open-point letters are the amended plan's (section 10). The
planner's letters are mapped at the end of this file.

| id | critic's severity | verdict | in the amended plan |
|---|---|---|---|
| Cc1 | high | accepted | contract-test.sh; section 6, by hand |
| Cc2 | medium | accepted, changed (with Cg9) | pkgbuild.zig `printCommands`; pkgplan's quote rule; pkg-parity; section 5; C |
| Cc3 | medium | accepted, changed (wider) | build_t1.zig; parity-test; pkg-parity; recipe history |
| Cc4 | medium | accepted, changed (with Cg4) | patch 0013's `.rzig_build`; risks; records; B |
| Cc5 | medium | accepted | pkg-parity; risk 11 |
| Cc6 | medium | accepted | contract-test.sh |
| Cc7 | low-medium | accepted | step 0; README; D |
| Cc8 | low-medium | partly accepted | pkgbuild.zig's shared tail; README (with Cg13) |
| Cc9 | low | accepted (merged into Cg5) | check.zig `groupsFor`; F |
| Cc10 | low | accepted (with Cg15) | pkg-parity on kappa; recipe history |
| Cc11 | low | accepted, changed (wider, Am7) | pkgplan.zig |
| Cc12 | low | accepted | parity-test; pkg-parity |
| Cc13 | low | accepted, changed (Am4) | verify-bundle; test texts; pkgplan's BASE |
| Cc14 | low | accepted | risks 3, 5, 11; README; patch header |
| Cg1 | high | partly accepted | section 0; A |
| Cg2 | high | accepted, changed | section 1 |
| Cg3 | high | accepted | B (iii) ★; patch 0013 |
| Cg4 | medium | accepted, changed (with Cc4) | patch 0013's `.rzig_build` |
| Cg5 | medium | accepted (with Cc9) | check.zig; tests; F |
| Cg6 | medium | accepted | E (a) ★; `shlibClean` dropped |
| Cg7 | medium-high | accepted | section 0; "What a user gets"; README; K |
| Cg8 | low-medium | accepted, changed | H; README; TODO |
| Cg9 | low-medium | accepted, changed (narrowed) | pkgplan's quote rule; C |
| Cg10 | low-medium | accepted | the planner's I dropped; section 1 |
| Cg11 | low-medium | accepted | step 0; D |
| Cg12 | low-medium | accepted | L |
| Cg13 | low | accepted (with Cc8) | README; test-preflight.R, wheel-test, verify-bundle scenario 1 |
| Cg14 | low | accepted, changed | J |
| Cg15 | low | accepted | M; H8 lines (with Cc10) |
| Cg16 | low | accepted | section 6 "not tested"; groups.zig note |

## critique-code.md

### Cc1 (high): contract's `cpp11::cpp_source` fails on cpp11's Suggests

- **Checked:** cpp11's DESCRIPTION has no Imports; brio, callr, cli,
  decor, desc, glue, tibble and vctrs are Suggests. contract.R calls
  `install.packages(pkgs, ...)` with the default `dependencies = NA`
  (contract-test.sh:82-90), which skips Suggests.
- **Stronger than the critic said (Am1):** `cpp_source` stops at its
  first line, `stop_unless_installed(c("brio", "callr", "cli", "decor",
  "desc", "glue", "tibble", "vctrs"))` (cpp11 R/source.R:69), before
  `brio::write_lines` (:86). desc is in the list too.
- **Verdict: accepted, option (b).** contract keeps cpp_source's exact
  SHLIB call through `callr::rcmd("SHLIB", ...)` (source.R:131-143) and
  drops cpp_source itself. One real `cpp_source` runs by hand on gamma
  and is recorded.

### Cc2 (medium): rzig's dry-run link line breaks pkgload's compilation database

- **Checked:**
  - pkgload's `build_commands` (compilation-db.R:162-210) passes
    `' --always-make <flags> IGNORED='` as one argv word. On unix,
    bin/SHLIB's unquoted `$@` splits it into `'`, `--always-make`, the
    flags and `IGNORED='` (src/scripts/SHLIB). install.R puts each into
    `pkg_libs` (no source extension; install.R:2839-2840), and `p1()`
    joins them back into the same text. Windows passes the word whole,
    with the same `p1()` result.
  - shellwords.zig reads `'...'` as one quoted word, with no
    metacharacter outside it, so rzig would accept the call and answer
    the dry run.
  - pkgload keeps lines that start with a `print-compilers` value.
    `SHLIB_LD = $(CC)` (subst.txt:315), so rzig's link line starts with
    zig-cc and is kept. `build_files_from_commands` (:116-131) then
    aborts, and `load_all` swallows it (load.R:289-293,
    `catch_and_warn`).
  - shlib.mk's link recipe starts `@if test "z$(OBJECTS)" != "z"`
    (shlib.mk:9-13), so `make -n`'s link lines do not start with a
    compiler.
- **Verdict: accepted, changed.** Both fixes are taken:
  - Cg9's rule, narrowed to a single quote (see Cg9), sends pkgload's and
    RStudio's injected dry run to make. That is the only way the
    injection keeps its meaning: it rewrites make's own command line
    (`PKG_LIBS='' --always-make ... IGNORED=''`), which rzig cannot
    reproduce.
  - `printCommands` prints the link in make -n's wrapper form, as Cc2
    proposes, for any other parser of a plain dry run.
  - pkg-parity gets both cases (section 3).
  - Section 5's pkgload row now says why it needs the build tools:
    pkgload's own `compilers()` runs make (Am2), and its dry run goes to
    make by the quote rule.

### Cc3 (medium): Fortran 9x modules compile in argv order under make, in parallel under zig build

- **Checked:** build_t1.zig's `compileAll` (116-134) makes independent
  Run steps. `.shlib_internal` runs make with no `-j` (install.R:3025-3029,
  3088). pkgplan.zig and build_t1.zig have no `.mod` or `-J` handling.
- **Verdict: accepted, changed (wider):**
  - The chain covers every Fortran source, `.f` too, since fixed-form
    source can hold a module.
  - It is in build_t1.zig, so tier-1 packages get it as well. Under a
    serial make, a tier-1 package with modules and no rule lines relied
    on OBJECTS order too.
  - The chain is taken over "exit 3 for two Fortran 9x sources": the
    chain keeps those calls off make.
  - "Nothing is left beside the sources" now says: except the `.mod`
    files flang writes in the working directory, as under make.

### Cc4 (medium): TMB's snapshot freezes the hook's code and rzig's CLI

- **Checked:** TMB.R:55 binds `.shlib_internal` when TMB is installed,
  and TMB.R:1472 calls it. The closure's environment is the tools
  namespace, resolved when the call is made. pkgbuild.zig returns 2 for
  usage errors (`parseArgs`, `run`).
- **Verdict: accepted, changed (with Cg4).** Under B (iii) ★ the body
  `.shlib_internal` keeps holds only R's parsed values and one call,
  guarded by `exists(".rzig_build", mode = "function")`. The top-level
  `.rzig_build` composes rzig's arguments and holds every rule. Exit 2 is
  the make path under `auto`. The record names the stable interface:
  `.rzig_build`'s argument names, and `rzig build`'s flags. Both are only
  ever added to.

### Cc5 (medium): pkg-parity's SHLIB parity can pass vacuously

- **Checked:** for packages, pkg-parity asserts `[ "$a" -gt 1 ]` and a
  non-empty `make_recipes` (pkg-parity.sh:223, 231-232). `argv_of` drops
  `-Wl,-install_name,...` (:155). pkgplan.zig:362-366 says only that make's
  relative `-o` is recorded. The linker is zig's on both paths.
- **Verdict: accepted.** Each SHLIB shape asserts at least two argv lines
  on both paths and recipes on the make path. On macOS the `-o sub/x.so`
  shape compares `otool -D`. The ld64 wording goes.

### Cc6 (medium): contract's macOS OpenMP-plugin case links `-fopenmp` on minimal

- **Checked:** zig-cxx's `--version` names neither Apple clang nor
  Homebrew clang, so `.openmpPluginDarwin` returns `-fopenmp` for both
  flags (Rcpp Attributes.R:577-631). minimal has no OpenMP.
- **Verdict: accepted.** The parse is tested on its own through
  `Rcpp:::.openmpPluginDarwin()`, which fails with a subscript error when
  nothing follows "make would use". The compile runs only where
  Makeconf's `SHLIB_OPENMP_CXXFLAGS` is non-empty.

### Cc7 (low-medium): TMB's precompile adds a zig cache object per model name

- **Checked:** TMB's `ppflags` carry `-DLIB_UNLOAD=R_unload_<lib>` and
  `-DTMB_LIB_INIT=R_init_<lib>` (TMB.R:1422-1432). They apply to every
  file, the precompiled `libTMB*.cpp` included, which `#undef`s them
  (TMB.R:1552-1556). zig cc keys its cache on the flags.
- **Verdict: accepted.** Step 0 measures both the seconds and the size
  per new model name. The README carries both, with the
  `R_ZIG_PKG_BUILDER=make` workaround.

### Cc8 (low-medium): rzig's own setup failures never reach make

- **Checked:** pkgbuild.zig returns 1 for a missing `build_t1.zig`
  (`run`'s `if (!ctx.isFile(build_file))`), for a root it cannot make,
  and for any zig build failure. pkgbuild hides SHLIB's output
  (compiler.R:51-59, `show = debug`).
- **Verdict: partly accepted:**
  - A missing `R_HOME/share/zig/rpkg/build_t1.zig` exits 3 with a line,
    in both modes, since it is one shared tail. It is a damaged tree, as
    is "no rzig". Tier 2 keeps 1, since make cannot build it.
  - A root rzig cannot create, and a zig build that fails, stay 1. These
    are real failures, and taking make for them would hide a broken
    runner behind a different builder.
  - The probe-hiding note is merged with Cg13.

### Cc9 (low): the SHLIB stop names only the build tools

- **Checked:** check.zig's `packageIn` (291-317) reports the compilers'
  text and then the build tools'. The plan's `runShlib` checked only
  `buildToolsFound`.
- **Verdict: accepted, merged into Cg5** (one function, `groupsFor`).

### Cc10 (low): H8 changes how Windows tier-1 packages build

- **Checked:** pkgplan.zig:274 tests only the chosen Makevars. R tests
  `file.exists("Makevars")` literally (install.R:3002-3004).
- **Verdict: accepted, merged with Cg15.** A kappa pkg-parity package
  case (an `.f90` source, a Makevars.win with `PKG_FCFLAGS`, no
  Makevars), and a line in recipe.yaml's history and in the record.

### Cc11 (low): SHLIB mode's texts say `src/`, and a warning prints twice

- **Checked:** pkgplan.zig warns "src/<mv>: Unknown C++ standard" and
  stops with "cannot read src/<mv>". install.R warns for the same line
  (2867, 2890).
- **Verdict: accepted, changed (wider, Am7).** Under B (iii) ★,
  `.shlib_internal`'s own parse runs before rzig in package mode too. So
  R gives the warning in both modes, and pkgplan drops it. The preflight
  is the one place that still prints it (it runs before R's parse).
  Under B (ii) it is dropped in SHLIB mode only.

### Cc12 (low): the concurrency tests do not prove distinct roots

- **Checked:** with a warm runner a call takes about 0.2 s
  (feat-shared-build-runner "Measurements"), so two calls need not
  overlap.
- **Verdict: accepted.** Both runs use `RZIG_KEEP_ROOT=1`. The test
  asserts two distinct roots, each with its own `plan.zon`, then removes
  them.

### Cc13 (low): test texts that fail on some OS

- **Checked:** bin/R sets R_HOME through `cd -P` (build.zig:3691).
  Windows output names are `.dll`. winshlib.mk's `BASE = $(shell
  basename $(SHLIB) .dll)` (winshlib.mk:8).
- **Verdict: accepted, changed (Am4).** The dry-run prefix comes from
  `"$R_BIN" RHOME`, and names use `$SO` and `.Platform$dynlib.ext`.
  rzig strips a trailing `.dll` exactly as winshlib.mk does, rather than
  taking the stem and noting the difference.

### Cc14 (low): claims to correct

- **Verdict: accepted:**
  - Risk 3 is scoped to the 21 callers the survey unpacked.
  - processx is tier 3 itself (Makevars rules,
    pak/src/library/processx/src/Makevars).
  - The ld64 wording goes (Cc5).
  - spawnWait passes a signal-killed child's raw status (sys-unix.c:688),
    so SIGQUIT reads as 3. One line in the patch header.
  - An unwritable rzig cache makes `sharedRunner` return null, and each
    call compiles the runner in its root. This goes in risk 5.

### The critic's "checked and correct" list

The amended plan relies on these:
- spawnWait's integer status;
- R's stdout flushing before the child's output;
- Rcpp writing a real `.cpp` before its dry run;
- make's command-line precedence;
- `.SUFFIXES` order;
- H8's reading of R;
- nimble staying on make;
- pak's worker probe;
- SIGINT forwarding.

## critique-goals.md

### Cg1 (high): the records' next phase is phase 5

- **Checked:**
  - The records' order holds. TODO.md has phase 5 at 598, and SHLIB
    routing is a "Later" item (757-765). feat-zig-pkg-build lists it as
    a later item (1034-1044).
  - The standalone compilers archive has no zig until phase 5
    (verify-bundle.sh:72-75).
  - But the session's own record, in the user's auto-memory
    (`zig-pkg-build.md`, 2026-10-14), says: "next item after phase 4 =
    route R CMD SHLIB through rzig build … Phase 4 is UNCOMMITTED … so
    this work is STACKED". The worktree `wt/feat-shlib-rzig-build` and
    the baseline `wt/phase4-base.diff` were made for it. The computed
    task names the same work.
- **Verdict: partly accepted.**
  - Section 0 now cites that record and states that this work departs
    from the records' phase numbering. It also states the standalone
    consequence: until phase 5, base + compilers there means the user's
    own zig (`ZIG_BIN`), as the tier-1 install does today.
  - The confirming menu stays, as A, first. Its ★ is (a), SHLIB routing
    now, and phase 5 after it, not the critic's (b). The work is
    planned, its worktree exists, and neither piece depends on the
    other.

### Cg2 (high): the plan assumes phase 4 is committed

- **Checked:**
  - The worktree's `git diff` sha256 is d95a00ae…4fcb3. That equals
    `wt/phase4-base.diff` and the phase-4 worktree's `git diff`.
  - The 5 untracked phase-4 files hash to 1270a566…b6c1e8 in both
    worktrees.
  - pixi.lock's sha256 is fbb64b7b…68bb96.
  - The SHLIB plan touches 15 files that phase 4 changed.
- **Verdict: accepted, changed:**
  - Section 1 is rewritten for the user's condition. It uses the
    baseline that already exists rather than a new one. Each host records
    three values: the lock, the baseline, and the code under test.
  - The handover after the user's commit is a mixed `git reset`, which
    keeps the working tree. A `cmp` against a SHLIB delta computed
    against the baseline tree checks it.
- **Rejected part:** "steps 2 and 4 wait until phase 4 is committed".
  Step 1 already changes phase-4 files (pkgbuild.zig, check.zig,
  parity-test.sh), so waiting buys no separation that the baseline does
  not give. It would also block the work on a commit the user cannot
  make yet. The R patch stays after step 1, which keeps the files most
  likely to conflict for late.

### Cg3 (high): two hooks and a flag, against "one hook"

- **Checked:** feat-zig-pkg-build decision 2 says "R gets one hook
  before `run_shlib`" (its PLAN.md:47-48). "What must remain on the R
  side" (214-216) says the same and puts shlib-clean on R's side. The
  plan's reason for A (a) does not hold: B (a) regenerates 0013 anyway.
- **Checked further:** whether one hook in `.shlib_internal` can carry
  0013's package mode. Everything rzig_build passes comes into
  `.shlib_internal` through run_shlib's arguments: `--use-LTO`,
  `--use-C17`…, `--debug`, `-o`. The stop texts need pkgerrmsg's
  " for package" suffix. The helper gives it with `message()` and returns
  1, after which run_shlib's existing `pkgerrmsg("compilation failed")`
  follows. pkg-parity.sh:400 greps a substring, so it still matches.
- **Verdict: accepted. B (iii) ★:** one hook in `.shlib_internal`, two
  modes, one top-level helper. 0013 is regenerated as the one rzig-build
  patch, and there is no 0014. The rejected timing part is the same as
  for Cg2.

### Cg4 (medium): the builder policy written three times, frozen into TMB

- **Checked:** 0013's `rzig_build` and the plan's `rzig_shlib` hold the
  same `R_ZIG_PKG_BUILDER` branches and texts. check.zig reads the
  variable too (`forced_make`, :253).
- **Verdict: accepted, changed.** One helper, `.rzig_build`, owns the
  whole policy and also composes rzig's arguments (Cc4). check.zig's
  `forced_make` stays: it is the preflight's own reading, before R's hook
  runs.

### Cg5 (medium): SHLIB's 127 names one group

- **Checked:** check.zig `packageIn` (291-317) and phase 4 H (a)
  (PLAN.md:3966-3969).
- **Verdict: accepted (with Cc9).** check.zig gets one public function,
  `groupsFor(ctx, label, why, fortran)`, which `packageIn` and SHLIB mode
  call. `buildToolsFound` stays private. The test sets add the
  no-zig-and-no-make case.

### Cg6 (medium): `--clean`/`--preclean` in SHLIB mode only

- **Checked:** 0013's args carry no `shargs`. Rcpp's
  `rebuild = TRUE` passes `--preclean` (Attributes.R:142). inline runs
  `--dry-run --preclean` (cfunction.R:306). pkgbuild's compile_dll passes
  `--preclean` to INSTALL (compile-dll.R:84). rzig neither writes nor
  reads `$(OBJECTS)` beside the sources, so the flags' purpose (no stale
  object reused) holds by construction.
- **Verdict: accepted. E (a) ★:** both modes ignore them on the rzig
  path. `shlibClean`, the two flags and their four test cases go.

### Cg7 (medium-high): the headline overstates base + compilers

- **Checked:**
  - pkgbuild's Imports are callr, cli, desc, processx and R6.
  - processx's src/Makevars has rules (tools/px, supervisor, client).
  - ps and pak have configure scripts.
  - cpp_source requires callr (and more: Am1).
- **Verdict: accepted.** Section 0 and "What a user gets" lead with what
  base + compilers does from scratch, and K is added.

### Cg8 (low-medium): G leaves two per-OS differences; its reason should change

- **Checked:**
  - pkgbuild's `with_build_tools` and `local_build_tools` call
    `has_rtools()` (build-tools.R:75-115). The "WARNING: Rtools is
    required" text is at rtools.R:217-223.
  - B11's option (c), "Require Rtools45", is the rejected one
    (feat-standalone-toolchain PLAN.md:1109-1111).
  - Also on Windows R ≥ 4.3, `has_build_tools` prints its own Rtools
    WARNING whenever the probe fails (build-tools.R:43-53; Am3).
- **Verdict: accepted, changed.**
  - H keeps ★ (a) with Cg7's reason.
  - The README line is softer than the critic's: "Rtools is not needed;
    the build tools take its place; pkgbuild's 'Rtools is required'
    warning can be ignored". The critic's "do not install it … can
    clash" asserts phase 7's msys-2.0.dll item, which no host has tested
    (TODO.md phase 7: "The same with Rtools or Git for Windows also on
    PATH").
  - The TODO note on `R CMD config` before configure scripts is taken.

### Cg9 (low-medium): pkgload's dry run changes builder

- **Checked:** as Cc2. R pastes the other words raw into
  `PKG_LIBS='<words>'` (install.R:2996-2998). Files and `-o` go through
  `shQuote` (install.R:2849, 2946). A double quote inside the single
  quotes is the recipe shell's, which shellwords mirrors.
- **Verdict: accepted, changed (narrowed).** A single quote in argv's
  linker words sends the call to make (exit 3, with the reason). A double
  quote does not, since rzig reproduces it. This is a correctness rule
  inside C, not a separate menu: rzig cannot model a changed make command
  line.

### Cg10 (low-medium): the planner's I re-asks B14 (a) and B37 (a)

- **Checked:** B14 (a), "no bump is no longer possible" (PLAN.md:1196-1199,
  4994). B37 (a) (PLAN.md:821).
- **Verdict: accepted.** The menu goes. The number is the one after
  universe's newest when this merges: 10 if `_9` is the newest.

### Cg11 (low-medium): D asks before the cost is measured

- **Verdict: accepted.** Step 0 measures on gamma with today's make
  path, before the menus go to the user:
  - libTMB.cpp's compile seconds and its object's size;
  - a model compile with the precompiled library and without it.

  D states the cost.

### Cg12 (low-medium): pak on base alone, a menu ready

- **Checked:** pkgdepends turns `needscompilation` into a logical
  (resolution.R:787-788) and tests `!identical(<lgl>, "no")`
  (install-plan.R:516, 557, 592). That is always TRUE, so
  `build_setup_binary`'s `check_build_tools` (pkgbuild build.R:237-240)
  runs before every source build.
- **Verdict: accepted. L is added**, answered with the by-hand check's
  result.

### Cg13 (low): pak and pkgbuild hide rzig's group text

- **Checked:** compiler.R:51-59 (`show = debug`, `stderr = "2>&1"`), and
  build-tools.R:61-66's message.
- **Verdict: accepted (with Cc8).**
  - The README line is added.
  - The text pkgbuild's debug mode would show is asserted where the
    compilers are missing: `R CMD SHLIB foo.c` on base alone, in
    test-preflight.R (conda), wheel-test's r-zig-alone scenario (pip) and
    verify-bundle's scenario 1 (standalone). No pkgbuild is needed for
    that.

### Cg14 (low): configure scripts that run `R CMD SHLIB` change builder

- **Verdict: accepted, changed.**
  - First a grep: the configure scripts (configure, configure.win,
    configure.ucrt, tools/*.R) of stress/packages.tsv's compiled rows,
    from their CRAN tarballs, for `SHLIB`.
  - J's dispatch adds the groups of the rows that hit (g3 and g4 if
    any are there).
  - The grep is cheap, and it says which rows matter before five runners
    are spent.

### Cg15 (low): the root beside the output, and H8 riding along

- **Checked:** R sets `R_SESSION_TMPDIR` in its environment for every
  child (sysutils.c:2712-2730; Am5).
- **Verdict: accepted. M is added**, with ★ (b): SHLIB mode's root goes
  under `R_SESSION_TMPDIR`, else beside the output. H8 gets its own lines
  (with Cc10).

### Cg16 (low): unknowns not listed

- **Verdict: accepted.**
  - RStudio's own build-tools checks go into "not tested". Its
    `buildtools.check` hook is called by pkgbuild only when the probe
    fails (build-tools.R:39-41; Am3), and the probe now passes on base +
    compilers.
  - groups.zig's "Building packages …" wording for a SHLIB stop is
    recorded as accepted (B35: one text per group).

## The amender's own findings

- **Am1:** `cpp_source` stops before anything else unless brio, callr,
  cli, decor, desc, glue, tibble and vctrs are installed (cpp11
  R/source.R:69). This confirms Cc1 and widens the "needs the build tools
  to install" list (K).
- **Am2:** pkgload's `compilers()` runs `make … print-compilers` itself,
  through `pkgbuild::with_build_tools(processx::run("make", ...))`
  (compilation-db.R:213-243). Its compilation database needs make
  whatever SHLIB does.
- **Am3:** on Windows with R ≥ 4.3, `has_build_tools()` prints
  "WARNING: Rtools is required…" whenever `has_compiler()` is FALSE
  (build-tools.R:43-53). Base alone on Windows gets it at each probe;
  base + compilers no longer does after this PR. RStudio's
  `options(buildtools.check)` hook runs only when the probe fails
  (:39-41).
- **Am4:** winshlib.mk's `BASE` strips only a trailing `.dll`. rzig does
  the same, so it matches exactly, also for an output named without
  `.dll`.
- **Am5:** every R sets `R_SESSION_TMPDIR` for its children (sysutils.c),
  and removes that directory when it exits. That makes M's option (b)
  possible.
- **Am6:** the phase-4 baseline already exists (`wt/phase4-base.diff`)
  and matches both worktrees today. Section 1 uses it.
- **Am7:** under one hook, `.shlib_internal`'s parse runs before rzig for
  packages too. So R's "specified C++NN" message and its "C++98 … CXXnn
  is not defined" stops now come first for tier-1 packages, as on the
  make path. That is a log difference from `_9`'s tier-1 installs, toward
  make. It is recorded, and pkg-parity does not compare those lines.
- **Am8:** the plan's builder-zig pkg-parity case used Objective-C, which
  R does not build on Windows. The case uses a Makevars rule on every OS,
  and Objective-C stays a unit test.

## The open points: planner's letters to the amended plan's

| planner | amended | change |
|---|---|---|
| — | A | new (Cg1): which work is next |
| A and B | B | merged (Cg3); ★ (iii), one hook |
| C | C | the quote rule and the link form inside (Cc2, Cg9) |
| D | D | measured in step 0 first (Cg11, Cc7) |
| — (in D) | E | new (Cg6): `--clean`/`--preclean` |
| E | F | the stop names every missing group (Cg5, Cc9) |
| F | G | unchanged; policy in `.rzig_build` (Cg4) |
| G | H | Cg8's reason and README line |
| H | I | unchanged |
| I | — | dropped (Cg10): B14 (a) decides |
| J | J | grep first, then the rows that hit (Cg14) |
| — | K | new (Cg7) |
| — | L | new (Cg12) |
| — | M | new (Cg15) |
