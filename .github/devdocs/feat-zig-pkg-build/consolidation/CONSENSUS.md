# Agreed plan: feat-zig-pkg-build after phase 3

Decided by the user on 2026-10-12: every recommendation below, and the
zig-pkg-build session implements it in its worktree (N7 a); the phase 3
session reviews the result before anything is committed or pushed.

Inputs: the zig-pkg-build session's overview
(`.claude/worktrees/feat-zig-pkg-build/.github/devdocs/feat-zig-pkg-build/CONSOLIDATION.md`,
branch 8ce3f77) and the phase 3 session's read-only review of it against
main e1ce179: three angles (builder coverage, preflight facts, channels),
every finding checked by an adversarial verifier (34 confirmed, 1
refuted), then this plan checked by a completeness critic and an
accuracy critic. Each finding, with file:line evidence and the
verifier's full note, is in `FINDINGS.md` beside this file; the ids in
brackets point there. Items with no id come from the accepted overview
(its section 4) or from a decision below.

## Decisions

| id | decision |
|---|---|
| M1 | (a') `--rzig-check=package`, deciding as the hook decides (section B) |
| M2 | (a) `rzig` / `rzig.exe` is one more name of the binary |
| M3 | (a') parity on the compile tree; the base only for the no-make installs (section F) |
| M4 | (a') scenario 2 asserts the tier-1 install with RZIG_TRACE=1; pfM is the Makevars-rule package; a configure-only package must stop in the preflight (section G) |
| M5 | (a) the records go in this branch's PR (section H) |
| M6 | (a') one stress dispatch after the push, with `trace` and `builder` inputs (section G) |
| M7 | (a) 0010 unchanged; its stated reason corrected (fact 1) |
| M8 | (a) merge origin/main, no rebase |
| N1 | (a) every install-based test asserts its builder, and each package shape keeps one make run |
| N2 | (a) the build-tools scope is written as in section H; routing R CMD SHLIB through rzig is a later item |
| N3 | (a) a per-install zig-build cache, removed with the install (section D) |
| N4 | (a) a variable assignment in MAKEFLAGS makes the package need make, with that reason (section C) |
| N5 | (a) no build-number bump in this PR; phase 4's bump (8 to 9) publishes both |
| N6 | (a) tier 2 means vendored or path dependencies only (section E) |
| N7 | (a) the zig-pkg-build session implements; the phase 3 session reviews before the commit and push |
| R1 | (a) CONSOLIDATION.md is not committed: its decisions and the corrected facts go into PLAN.md, and it is deleted like HANDOFF.md |
| R2 | (a) this file and FINDINGS.md are copied into `.github/devdocs/feat-zig-pkg-build/consolidation/` in the PR, and PLAN.md cites them by finding id |

## Facts that change the overview

Verified against the code, except where marked "inferred".

1. **R CMD config** [preflight-F1, F6, coverage-C8, channels-C10].
   install.R calls `R CMD config` on unix (a vapply over CC, CFLAGS,
   CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC, FCFLAGS before `./configure`;
   pristine CRAN install.R 1324-1329, merged tree 1405-1410) and
   `Rcmd config` on Windows (configure.win or configure.ucrt; pristine
   1290-1292, merged 1371-1373), both only for a configure script R
   runs. Tier 1 never has one; tiers 0 and 2 can. 0010 stays as is: install.R
   reaches it only through a configure script R runs (tier 0, 2 or 3),
   and users, pkgbuild and pak call it directly.
2. **A classify()-only check is not enough** [coverage-C6, preflight-F3,
   channels-C6]. Makevars with rules (verify-bundle's mkpkg `lib`
   variant, test-toolchain's rzigar) classify as `makevars` and become
   make only in plan(), whose reason is "src/Makevars has a rule or
   target line: '<line>'" (pkgplan.zig:271). `rzig build --classify`
   alone (M1 b) would let them skip the build-tools check and fail later
   with `make: not found`.
3. **Configure scripts in tiers 0 and 2** [preflight-F2]. Such a package
   needs the build-tools group for its configure (unix: make, which
   R CMD config needs and 0010 checks; Windows: sh, make and the
   binutils), and today main's 0009 also asks it for the compilers.
   Gating on the tier alone loses both stops before configure.
4. **Cross-tree argv differs** [channels-C1]. rzig adds TC/openmp (B40)
   in the compile tree and not on the base, so argv compared across the
   two trees differs on every leg but minimal.
5. **Tier-3 checks on the base fail on Windows** [channels-C2]: the
   preflight stops them with the build-tools text before the hook runs.
6. **macOS trace lines** [channels-C3] (inferred, never run). With
   conda-forge zig on macOS, rzig's trace line is
   `zig-cc: ZIG_LIB_DIR=<mirror> <zig> cc ...` (the libc++ mirror);
   pkg-parity's argv_of drops such lines, so on the macOS legs with
   conda-forge zig it sees none and fails. Upstream-zig legs have no
   mirror.
7. **Builders change silently** [coverage-C2..C5, C9, channels-C4].
   With 0013's default `auto` these move to rzig build: contract's Rcpp
   and quadprog (every OS) and minqa (unix; its Makevars.win's
   `$(shell ...)` keeps it on make on Windows), plus pak's embedded cli,
   lpSolve, pkgcache and yaml; the conda recipe's rzigc, rzigz, rzigf
   (unix) and rzigfl; wheel-test's packages (the wheel's make then
   builds nothing); scenario 3's btA. Their assertions still hold; the
   make path they were written for is no longer exercised. Scenario 2
   is the reverse: its R CMD SHLIB checks stay on make, while R CMD
   INSTALL of the same tier-1 shapes now takes rzig build, which none of
   them checks.
8. **R CMD SHLIB never reaches 0013's hook** [coverage-C1, channels-C8].
   Run-time compilation (Rcpp's sourceCpp/cppFunction/evalCpp,
   cpp11::cpp_source, inline, rstan, TMB) still needs make, and so does
   pkgbuild's has_compiler probe (R CMD SHLIB), which pak runs before
   every compiled package (pkgdepends make_build_process -> pkgbuild
   build_setup_binary -> check_build_tools): on base + compilers pak
   installs no compiled package, tier 1 included. remotes and devtools
   were not checked.
9. **The zig-build cache grows without bound** [channels-C5]. The Run
   steps hash the whole environment (R_SESSION_TMPDIR differs per
   session), so every install adds entries under
   `~/.cache/r-zig/zig-build` and nothing removes them. On linux,
   CRAN-style R CMD check (_R_CHECK_THINGS_IN_OTHER_DIRS_; check.R
   472-490 snapshots ~/.cache recursively) would note files there
   (inferred). zig 0.16 compiles the build runner into `--cache-dir`,
   with the Run outputs (measured): a fresh cache dir rebuilds it in
   about 3.1 s with a warm global cache (6.6 s cold), 33 MB, linux-64.
10. **MAKEFLAGS** [coverage-C7]. `MAKEFLAGS='LTO_OPT=-flto'` or
    `CFLAGS=...` change make's flags and not rzig build's. Under
    install.packages(Ncpus > 1), R CMD INSTALL runs inside make's recipe
    and MAKEFLAGS is `k -j2 --jobserver-auth=fifo:...` (measured, GNU
    make 4.4.1): those are options, not assignments; make puts
    command-line assignments after ` -- `.
11. **RZIG_TRACE and stress** [channels-C7, coverage-C10, C11].
    `rzig build: tier N` is printed only with RZIG_TRACE=1. Stress runs
    skip 0009 altogether (stress.R sets R_MAKEVARS_USER to an empty
    file), so a stress table measures the hook's tiers, not the
    preflight. Only ubuntu-latest has a make reference (dispatch
    38251125721 on 548da1a, tree, targets g3 g4). A dispatch needs the
    branch on GitHub, so stress comes after the push.
12. **Records** [coverage-C13, preflight-F8, channels-C11, C14]. The
    worktree has two untracked records (HANDOFF.md, CONSOLIDATION.md);
    HANDOFF.md must be folded into PLAN.md before it is deleted. The hook
    is in 0013's @@ -683 hunk only (746 is patch_rpaths); pfC has two .c
    files; the compile tree's PATH line is a unix fact in phase 3
    (Windows from phase 7); M3 (c) fails on Windows in the preflight, not
    in the link; pkg-parity.sh's prefix line is :34.

## Implementation checklist

### A. The merge (M8, M2)
- [ ] In the worktree: `git merge --no-commit origin/main` (e1ce179).
      Conflicts [accuracy critic; overview section 4]: main.zig and
      pixi.toml keep both sides (pixi.toml: `pkg-parity` gets
      `depends-on = ["compile-tree"]`); build.zig takes main's two
      installRzig lists plus `rzig.exe` (Windows) and `rzig` (unix),
      without the branch's zig-cc/zig-cxx on Windows; verify-tree.sh takes
      main's side (`tc_names="$(rzig_names)"`); `rzig` and `rzig.exe` go
      into rzig_names() in scripts/verify-helpers.sh.
- [ ] The find_zig fix in pkgbuild.zig (unwrap `!?Zig`; no zig:
      `groups.report(ctx, groups.no_zig, .compilers)`, exit 127; pass
      `zig.argv`), and build_t1.zig's cc/cxx/fc defaults per OS
      (overview section 4, accepted with M8).

### B. The preflight (M1 a', M7 a)
- [ ] check.zig: `--rzig-check=package`, run with the package dir as cwd,
      using ONE function shared with pkgbuild (classify, then plan, with
      the hook's inputs) [coverage-C6, preflight-F3]:
  - use_C reaches it as `R_ZIG_C_STD`, and whether R will run a
    configure script as `R_ZIG_CONFIGURE=1` (use_configure, and
    `configure`, or `configure.win`/`configure.ucrt` on Windows); 0009
    sets both with Sys.setenv right before the call and unsets them
    after (system2's `env` is not supported on Windows) [preflight-F2,
    F4];
  - CLINK_CPPFLAGS is not computed in the preflight (install.R sets it
    after); the gap is recorded: it differs from the hook only for an
    apostrophe or `$` in a LinkingTo path, where make fails too; the
    makevars_user() skip stays, recorded as a known gap [preflight-F4];
  - with `R_ZIG_CONFIGURE=1`: the compilers (flang by today's top-level
    either-case match) and the build tools whatever the tier, reason "a
    configure script R runs" [preflight-F2];
  - otherwise: the compilers for tiers 1-3, flang when plan().sources
    has f or f9x (tiers 1-2) or by today's top-level match (tier 3)
    [preflight-F5]; the build tools when the tier is make, the failing
    line giving rzig's own reason as classify()/plan() word it ("a
    configure script", "src/Makefile", "src/Makevars has a rule or
    target line: '<line>'", "MAKEFLAGS sets NAME", ...) before the group
    text [preflight-F3];
  - `R_ZIG_PKG_BUILDER=make` forces make; `R_ZIG_NO_PREFLIGHT` unchanged.
- [ ] 0009: one `system2(<CC's path: 0009's existing `rzig` variable,
      zig-cc or gcc.exe>, "--rzig-check=package", stdout = FALSE)`, not
      the new `rzig` name, which hermetic-check's strace allowlist does
      not admit [coverage-C12]; the rzig-missing branch and
      R_ZIG_TOOLCHAIN_HINT stay.
- [ ] 0013 regenerated on the new 0009; when CC's binary exists but the
      `rzig` name does not, it stops with a clear line instead of
      falling back to make silently [preflight-F7].
- [ ] 0010 unchanged.

### C. MAKEFLAGS (N4)
- [ ] pkgplan: a variable assignment in MAKEFLAGS (a word after GNU make's
      ` -- `, or a word matching `^[A-Za-z_][A-Za-z0-9_]*=`) gives needs
      make ("MAKEFLAGS sets NAME"); option words (`k`, `-j2`,
      `--jobserver-auth=...`) do not, and `-j` keeps working. Unit tests:
      `k -j2 --jobserver-auth=fifo:/tmp/x` plans tier 1;
      `k -j2 --jobserver-auth=fifo:/tmp/x -- LTO_OPT=-flto` needs make
      [coverage-C7].
- [ ] A tier-1 twin of the LTO record (Windows scenario 3, mkpkg without
      `lib`) asserts `needs make` with "MAKEFLAGS sets LTO_OPT" in its log
      and records make's result.

### D. The cache (N3)
- [ ] Every tier: `--cache-dir <build root>/zig-cache`, removed with the
      build root, so nothing per install outlives it. The shared part is
      zig's global cache (std, compiler_rt, libc++, keyed by target,
      bounded). The build runner is rebuilt per install (fact 9: about
      3.1 s warm, 33 MB transient); the stress table records the
      per-install time. A shared runner for tier 1 (build_t1.zig's root
      is fixed in R_HOME) would need build_t1's Run steps to write into
      the build root instead of cache outputs: a later item, only if the
      stress time asks for it [channels-C5].
- [ ] A check (pkg-parity or scenario 2): after an install,
      `<cache root>/zig-build` does not exist, and a second install of the
      same package leaves the number of entries under zig's global
      cache's o/ unchanged.
- [ ] rzig build honours ZIG_LOCAL_CACHE_DIR, when set, as the place for
      its per-install cache (stress.R points it at the run directory)
      [coverage-C11].

### E. Tier 2 (N6)
- [ ] rzig build reads src/build.zig.zon: a dependency with `.url` fails
      the install (exit 1, not 3, since make would compile src/ and ignore
      build.zig) with "src/build.zig.zon: dependency <name> is a URL;
      tier 2 builds offline, vendor it as a .path dependency". zig build
      gets `--system <build root>/no-packages` (an empty dir), so a
      transitive URL dependency cannot fetch either (zig 0.16's switch,
      which also enables system integrations: check it changes nothing
      for the rpkg roots). pkg-parity's tier-2 block adds a zighello copy
      whose build.zig.zon has one URL dependency and asserts that line
      [channels-C13].

### F. pkg-parity (M3 a')
- [ ] zig-vs-make parity (exports, argv, smoke), tier 2 and the tier-3
      checks (fall-through, `R_ZIG_PKG_BUILDER=zig` refusal) on
      `$COMPILE_TREE`; the base (`$PREFIX`) only for the no-make
      `env -i` installs, with no argv comparison [channels-C1, C2].
- [ ] argv_of strips a leading `ZIG_LIB_DIR=<word> ` instead of dropping
      the line [channels-C3].
- [ ] minqa joins PKGS after Rcpp (LinkingTo and Imports Rcpp), on unix
      only (tier 3 on Windows); smoke.R gains a minqa line (bobyqa) and
      its unload loop includes it [coverage-C5].

### G. Tests and coverage (M4 a', N1, M6 a')
- [ ] verify-bundle scenario 2 (unix, base + compilers, no make): pfC
      installs and loads, with RZIG_TRACE=1 and `rzig build: tier 1` in
      its log; pfM, the Makevars-rule package (mkpkg `lib`), stops with
      "src/Makevars has a rule or target line: '$(SHLIB): lib/libval.a'"
      and the build-tools text; a configure-only package (R-only or
      zighello, plus configure_marker) stops through preflight_stops with
      the build-tools text and 0009's ERROR line (`$preflight_stop`),
      which is what tells the preflight's stop from 0010's later
      R CMD config failure (the marker cannot, verify-bundle.sh
      532-536); pfF unchanged [coverage-C6, preflight-F2, channels-C7].
- [ ] scenario 2's SHLIB fixtures also become packages installed under
      the default builder (RZIG_TRACE=1, `rzig build: tier 1`), with the
      same rpath, NEEDED, static libc++, minos, static flang runtime,
      USE_FC_TO_LINK, FLIBS-without-flang, libomp and CONDA_PREFIX
      checks on lib/<pkg>/libs/*; the R CMD SHLIB runs stay (the make
      and run-time paths); likewise Windows scenario 3's OpenMP packages
      [coverage-C2].
- [ ] scenario 3: btA stays on the default builder as a deliberate mixed
      run; RZIG_TRACE=1 and kept outputs, asserting btA `rzig build:
      tier 1` and btLib `needs make`; header and messages say so
      [coverage-C9].
- [ ] contract: Sys.setenv(RZIG_TRACE = 1) and keep_outputs = TRUE;
      assert `rzig build: tier 1` for Rcpp and quadprog (every OS) and
      minqa (unix), and `needs make` for data.table, ps and pak (and
      minqa on Windows); the comments in contract-test.sh and pixi.toml
      say which builder each uses [channels-C4, coverage-C5].
- [ ] recipe/test-toolchain.R: rzigc, rzigz and rzigfl (and rzigf on
      unix) also with `R_ZIG_PKG_BUILDER=make` into a second library;
      one default install asserts its builder with RZIG_TRACE=1
      [coverage-C4].
- [ ] wheel-test.sh: one install with `R_ZIG_PKG_BUILDER=make`; a tier-3
      package (a Makevars rule) built with the wheel's make; the
      console-script install with RZIG_TRACE=1 and `rzig build: tier 1`
      (the first rzig build under PyPI's ziglang); the header says which
      installs take which builder [coverage-C3, channels-C4].
- [ ] smoke-test.sh part 2: RZIG_TRACE=1 [coverage-C13].
- [ ] stress, prepared before the push: stress.yaml inputs `trace`
      (bool) and `builder` (auto|make); stress.R's toolchain pattern
      gains rzig build's failure lines only: `rzig build: (zig build
      failed|no zig to build with|cannot |waiting for zig build)|R_HOME/share/zig/rpkg
      is not installed` [coverage-C11; accuracy critic]; the notes of the
      switching rows in packages.tsv (Rcpp, lme4, mlpack, fst, geos) say
      they build through rzig build [coverage-C11].

### H. Records (M5, N2, N5, R1, R2)
- [ ] This branch's PLAN.md: "Consolidation with phase 3" with these
      decisions and the corrected facts 1-12; HANDOFF.md's content
      folded in before HANDOFF.md is deleted; CONSOLIDATION.md not
      committed (R1); this file and FINDINGS.md copied into
      `.github/devdocs/feat-zig-pkg-build/consolidation/` (R2). Cite
      install.R by the pristine CRAN numbers plus the merged tree's,
      other files by the merged tree's line numbers [preflight-F8,
      channels-C14].
- [ ] feat-standalone-toolchain PLAN.md, a note under the phase 3
      records, and TODO.md items:
  - the build-tools group is needed by: packages that need make (tier
    3); any package whose configure script R runs (tier 0 or 2 can have
    one); R CMD SHLIB, so run-time compilation (Rcpp's
    sourceCpp/cppFunction/evalCpp, cpp11::cpp_source, inline, rstan,
    TMB) and pkgbuild's has_compiler probe, through which pak refuses
    every compiled package, tier 1 included, before R CMD INSTALL;
    R CMD config's direct callers (users, pkgbuild); R CMD check's
    objdump; on Windows, cleanup.ucrt/cleanup.win under --clean or
    --preclean (without sh only a warning: the cleanup is skipped)
    [coverage-C1, channels-C8, preflight-F7; accuracy critic];
  - phase 7 (Windows usr/bin) and B24 are re-scoped from the stress
    table; until it exists the note says so;
  - later items: route R CMD SHLIB through rzig build (it would also
    clear pak's probe), or give it a preflight; revisit 0010 for
    pkgbuild's probe; a shared tier-1 build runner if the stress time
    asks for it (D);
  - verify-bundle scenario 2's new assertions;
  - no build-number bump in this PR; phase 4's bump (8 to 9) publishes
    both [channels-C9].

### I. Tests, review, commit, stress
- [ ] linux-64: `pixi run toolchain`, `pixi run build`, `pixi run
      rzig-test` (and with `ZIG_BIN="$(pixi run fetch-zig)"`), `pixi run
      verify-tree`, `pixi run compile-tree`, `pixi run pkg-parity`,
      `pixi run contract`, `pixi run hermetic`, `pixi run
      package-toolchain`, `pixi run verify-package`; `pixi run -e minimal
      build`, `pixi run -e minimal toolchain`, `pixi run -e minimal
      verify-package`; `pixi run -e wheel wheel`, `pixi run -e wheel
      wheel-test`; `pixi run -e pkg conda-package`.
- [ ] omicron (osx-arm64, pixi env): pkg-parity and verify-package,
      which first show the macOS trace fix [channels-C3].
- [ ] kappa (win-64): pkg-parity, verify-package, conda-package.
- [ ] The phase 3 session reviews the uncommitted merge in the worktree
      against phase 3 (N7). Then the user makes one merge commit (M8),
      pushes and opens the PR with `full-ci`.
- [ ] After the push, when CI is green: one stress dispatch on the branch
      with oses = the five runners, distribution tree (universe still has
      build 8, without rzig build [channels-C9]), packages g3 g4,
      trace = true, builder = auto. Its table goes into PLAN.md in a
      follow-up commit on the same PR: rows by tier per OS; rows whose
      smoke compiles at run time (Rcpp, rstan: R CMD SHLIB, still make);
      time and changed results against 548da1a on ubuntu-latest only (no
      make-reference dispatches for the other OSes); then phase 7 and
      B24's re-scope (H). The phase 3 session reviews that commit too
      [channels-C7, coverage-C1, C10, C11].
