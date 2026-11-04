# Critique of the phase 4 plan (planner, 2026-10-13), merged

This merges two critiques of planner/PHASE4-IMPLEMENTATION.md:
- critique-code.md (Cc1-Cc19): the plan against main and the tools;
- critique-goals.md (Cg1-Cg18): decisions and goals.

Amender's review, 2026-10-13. Read-only: nothing in the repo changed, and
nothing was built or installed. Every point was checked against the code
before it was accepted. "Verified" below says how. A point that did not
hold, or held only in part, says why.

**Note (2026-10-19).** The user decided that phase 4 does not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 4 keeps 8 (as do SHLIB routing and phases 5 and 6), and
main publishes nothing until the user sets the repository variable
`CONDA_PUBLISH` after phase 7's bump merges (build.yaml's publish step;
PLAN.md's B14 amendment). Where this critique says phase 4 bumps to 9 or
publishes `_9`, read: phase 4 keeps 8, and its files publish with phase
7's bump, at the number after universe's newest (B14 a). Its test
procedures with `_9` hold for that number.

Sources:
- main at ea7e6ee, the checkout /home/luciorq/projects/r-zig-pixi:
  - recipe/;
  - zigbuild/tools/rzig/: check.zig, groups.zig, find_zig.zig,
    environment.zig, main.zig, Ctx.zig, pkgbuild.zig, flang_rt.zig;
  - patches 0009, 0010 and 0013;
  - scripts/: wheel-test.sh, verify-bundle.sh, hermetic-check.sh,
    env.sh, make-wheel.py;
  - stress/stress.R and stress/README.md;
  - pixi.toml, .github/workflows/build.yaml, README.md;
  - zigbuild/config/*/subst.txt;
  - feat-standalone-toolchain PLAN.md and TODO.md;
  - fix-zig-pkg-build-review PLAN.md and feat-zig-pkg-build PLAN.md.
- R 4.6.1's sources in build/R-4.6.1: install.R, sys-unix.c, shlib.mk
  and scripts/config.
- The surveys, and the survey scratch: rattler-build's testing docs, and
  the CI logs.
- Reads made for this review:
  - CI run states (gh). build-r 38467545177: completed, success.
  - Stress dispatch 38467907779's four finished reports, downloaded to
    critic/stress/.
  - api.anaconda.org's zig: 0.17.0 on the main label.
  - PyPI's JSON for the four names: 404 each.
  - The lock's m2-bash package (critic/m2/): `Library/usr/bin/sh.exe` is
    in it.

The amended plan is PHASE4-IMPLEMENTATION.md beside this file. It keeps
the planner's structure and most of its content. Every amended item
carries its critique number.

## Verdict

The planner's plan applies phase 4's decisions faithfully. It has:
- four packages per channel with exact pins;
- B41's two exceptions, E2 and D7;
- B35's writers removed, together with the dead `R_ZIG_CONDA_BUILD`;
- B39/B11's interim win-64 set;
- the end of N5's coupling, because rzig ships in every base.

The core holds against the code: the recipe shape, the hint writers and
readers, groups.zig's change and the "no change" files.

Three points would break a test as written (Cc1-Cc3). Four more needed a
step-level fix (Cc4-Cc7). The goals critique found three places where
`_9`'s texts would send users the wrong way (Cg1-Cg3). It found choices
the plan made without asking the user: the hint's scope, 0009's exit 1,
win-64's native make, test-toolchain.R's PATH and the consume step's
cost. It also found records the plan missed.

All 37 points hold against the code, five of them in part (Cc8, Cc16,
Cc19, Cg8, Cg12). None was rejected outright. Four new open points come
from them (H, I, J, K), and so does a fifth (L, the README). Two of the
planner's open points change (B's ★ moves; E covers both channels), and
D now carries the dispatch's numbers.

The amender's own checks add four corrections (A1-A4), the largest being
that the stress dispatch is the `--no-shared-cache` run.

## 1. Critique (code): Cc1-Cc19

1. **Cc1 (breaks): test-build-tools.R's `R CMD config CC` "ends in
   toolchain/zig-cc".**
   - Verified: every unix subst.txt:256 has
     `S["CC"]="@ZR_TOOLCHAIN@/zig-cc -std=gnu23"` (all 12 configs).
     Makeconf.win:128 has `CC = $(BINPREF)$(CCBASE).exe $(M_ARCH)`.
   - **Accepted.**
   - Changed: test-build-tools.R compares the first word's directory and
     name, as test-toolchain.R:271 does for FC.
2. **Cc2 (breaks): a 127 through `system2(stdout = TRUE)`.**
   - Verified: sys-unix.c:1012 turns 127 under intern into "error in
     running command". 0009's own comment says the same.
   - **Accepted.**
   - Changed: the shared test header defines `run_to()` (output through a
     file). Section 3 states the rule once, for every check that expects
     127 in all four tests.
3. **Cc3 (breaks, win-64): backslash vs rzig's forward slash.**
   - Verified: check.zig's `display()` (287) rewrites `\` to `/` on
     Windows, for make, sh, flang and binutils. test-toolchain.R:101/116
     already uses `winslash = "/"` and `tolower`.
   - **Accepted.**
   - Changed: the header gets `shown()` and `same_path()`, used for every
     path comparison. PATH keeps Windows' own form.
4. **Cc4 (missing): the tests unset too few caller variables.**
   - Verified: each variable's effect is in the code:
     - `R_ZIG_NO_PREFLIGHT`: 0009's condition;
     - `R_ZIG_PKG_BUILDER=make`: 0013 and check.zig's `forced_make`;
     - `MAKEFLAGS`: 0013's header;
     - `RZIG_TRACE` and `ZIG_LOCAL_CACHE_DIR`.
   - **Accepted, and extended (A3).**
     - The plan's `Sys.unsetenv("R_MAKEVARS_USER")` is itself a hole.
     - install.R's `makevars_user()` (3380-3405) then falls back to
       `~/.R/Makevars*`, which would skip 0009 on a host that has one.
     - Naming a file that does not exist means "none" both to R and to
       rzig (pkgbuild.zig:159, tested at 651).
     - test-preflight.R and test-toolchain.R have the same hole today.
   - Changed: one shared header for all four recipe tests (section 3).
5. **Cc5 (missing): the second venv's `nzchar(Sys.which("make"))` proves
   nothing.**
   - Verified: wheel-test's `run` PATH has /usr/bin, and its existing
     check (159-164) asserts the path.
   - **Accepted.**
   - Changed: the second venv asserts `bin/toolchain/usr/bin/make$` and
     the four names in `pip list`, through its own `pip2_`.
6. **Cc6 (missing): three wheel-test details.**
   - Verified:
     - pip lists dist-info files under "Files:".
     - wheel-test.sh:290's install prints to the terminal.
     - The final base-alone run needs a PATH without /usr/bin.
   - **Accepted.**
   - Changed:
     - the dist-info-only assertion;
     - `$T/install3.log`;
     - the final run is test-preflight.R, whose own PATH has no /usr/bin
       (with Cg10).
7. **Cc7 (missing): the upgrade test's commands on kappa.**
   - Verified against the repo's own pattern: env.sh:155's `cygpath -m`.
     MSYS converts POSIX paths in arguments but not in variables. A
     drive path needs `file:///`. The cmd-over-SSH gotcha is the user's
     own record.
   - **Accepted.**
   - Changed: section 7 writes the kappa form out: Git Bash, `cygpath -m`
     for every cache variable and `$CH`, `CH_URL="file:///$CH"`, run as
     `bash <file>`. The record names the form that ran.
8. **Cc8 (design): assert `no zig` in test-preflight.R; the /usr/bin/zig
   skip is dead.**
   - Verified: find_zig.zig's order is ZIG_BIN, `TC/zig`, R's own bin
     (environment.own), PATH, then python3 with ziglang. None is
     reachable with PATH narrowed to the env, on conda and in the wheel.
     PLAN.md's phase 4 step asks for "no zig" too.
   - **Accepted, with a correction.** On Windows too the line starts
     `zig-cc: `: main.zig's `Tool.fromName` maps `gcc` to `.cc`, whose
     `shimName` is "zig-cc". So the assertion is `zig-cc: no zig (` on
     every OS, not "the gcc name's prefix".
   - Changed: test-preflight.R asserts it. The skip goes, and risk 9 is
     reworded.
9. **Cc9 (missing): nothing catches a hint writer that comes back.**
   - Verified: build.zig writes to etc/Renviron (finalRenviron,
     3837-3839) on unix, and to etc/Renviron.site (installEnvRuntime,
     3153-3155) on Windows.
   - **Accepted.**
   - Changed: test-preflight.R checks that no `hint:` line follows the
     first stop, and that neither file has the line (both files on every
     OS, whichever exists).
10. **Cc10 (missing): Windows' plain Fortran package in test-compilers.R
    has never run in a conda test.**
    - Verified: test-toolchain.R:255 limits FLIBS to `!windows`, and
      Windows FLIBS is `-lflang_rt.runtime -lc++`.
    - **Accepted, (b) chosen.** contract-test.sh's quadprog (pure
      Fortran, FLIBS, rzig build) already runs on windows-latest, so the
      path works. The conda version adds coverage. The libc++ cost is
      shared through Cc11.
    - Changed: the plain package on every OS, and the libc++ wording.
11. **Cc11 (design): the consume step repeats three cold zig caches.**
    - Verified: test-toolchain.R:17-19 puts the cache in `tempdir()`.
      rattler-build's test env inherits the caller's variables (SC §3).
    - **Accepted.** Decided now, not "if slow" (with Cg8).
    - Changed:
      - The tests read `R_ZIG_TEST_ZIG_CACHE`.
      - conda-package sets it in deno_task_shell's `NAME=value` form
        (`$PIXI_PROJECT_ROOT/build/conda-test-zig-cache`, no OS branch).
      - conda-consume.sh uses the same directory.
      - A hand run keeps its own cache.
      - The PR records each conda leg's time.
12. **Cc12 (design): `package_contents` tests.**
    - Verified: rattler-build's testing docs (surveyor-conda/
      rb-testing.md: `files: exists / not_exists`, `strict`), with the
      lock's rattler-build 0.76.1.
    - **Accepted (merged with Cg12), without `strict`.** Whether the
      packaged test file counts in the checked list is unverified, and
      `not_exists` holds either way.
    - One more fix: `exists` passes when a glob matches one file, so the
      six binutils are six entries, not one `{a,b}` glob.
    - Changed: a check per output (section 3). test-build-tools.R drops
      the existence checks and keeps the content checks.
13. **Cc13 (design): r-zig-slim could constrain zig.**
    - Verified: rzig finds the env's zig first (find_zig.zig, B34), and
      check.zig:128-131 stops another major.minor. conda-forge's main
      label has 0.17.0 (read here).
    - **Accepted as open point K (merged with Cg14), ★ (a).**
14. **Cc14 (design): unregistered names resolved through PyPI.**
    - Verified: all four names return 404 on PyPI today.
    - **Accepted.**
    - Changed:
      - The second venv installs ziglang first, then `--no-index`.
      - In the first venv, pip queries no index for `r-zig`, which is
        already installed.
      - README: the same two commands.
      - Reserving the names goes to TODO with B12. It is not a phase 4
        decision.
15. **Cc15 (design): open point E covers only the wheel.**
    - Verified: recipe.yaml:533-536's top-level `GPL-2.0-or-later` is
      inherited by every output, including win-64's binutils copies.
    - **Accepted, merged with Cg13 into E.**
16. **Cc16 (missing): check that m2-bash ships `sh.exe`.**
    - **Answered now.** The lock's m2-bash (5.2.037.2 hc364b38_6),
      downloaded and listed, ships `Library/usr/bin/bash.exe` and
      `sh.exe`.
    - So no step-1 check is needed. test-build-tools.R's
      `--rzig-check=build-tools` (`onPath(ctx, "sh")`) checks it on every
      fresh solve.
17. **Cc17 (wording): the no-inherit question is not answered "yes".**
    - Verified: TODO.md:447-448, and the plan's choice of `inherit` +
      `files: []`.
    - **Accepted.**
    - Changed: section 11's wording.
18. **Cc18 (wording): test-compilers.R cannot show B34's order.**
    - Verified: with PATH = `env_bin`, the two are the same directory.
      The order is already rzig-test's: find_zig.zig:159 and
      flang_rt.zig:151.
    - **Accepted.** The claim is dropped, not given a decoy.
19. **Cc19 (wording): stale texts.**
    - Verified:
      - stress/README.md:227 names "which is not installed";
      - README.md:12-15 lists four platforms;
      - the plan's section 6 row says unix only, but R.bat adds nothing
        to PATH (SC §6).
    - **Accepted in part.** feat-zig-pkg-build's N5 (708) and the
      review's PLAN.md:13-14 already say that phase 4's bump publishes
      them. They need only a closing "published as `_9`" note after the
      publish.
    - Changed: stress/README.md (section 3), README, section 6's row and
      section 7.

Checked and correct (no change), as critique-code.md lists:
- the recipe line numbers;
- the empty outputs;
- the coverage of binutils/;
- the writers to delete;
- 0009's R, 0010's status and 0013's hunk order;
- the wheels;
- the exit codes;
- conda-forge's MSVC zig;
- the unused-file checks;
- universe's contents.

## 2. Critique (goals): Cg1-Cg18

1. **Cg1: one group named per attempt; rzig never names
   r-zig-toolchain.**
   - Verified: check.zig:269-270 returns at the first failing group.
     packageIn's flow is compilers, then build tools only on success.
     N2's counts are in feat-zig-pkg-build PLAN.md.
   - **Accepted as open point H, ★ (a).** B35 decides one text per
     group, not one group per stop.
   - Changed:
     - check.zig's packageIn reports both groups on a 127 when the
       package needs both;
     - groups.zig's lines end "; r-zig-toolchain installs every group";
     - test-preflight.R gets a configure-script package that expects
       both texts.
   - Checked that no script asserts a single text: hermetic-check,
     verify-bundle and parity-test grep for presence only.
2. **Cg2: an unactivated env is told to install the r-zig-build-tools it
   has.**
   - Verified:
     - check.zig's buildToolsFound looks on PATH only;
     - environment.own gives `<root>` (unix) or `<root>/Library`
       (Windows);
     - B34's note keeps make PATH's.
   - **Accepted as open point I, ★ (a).**
   - Changed: check.zig's missing line names the installed tool. A unit
     test and a test-build-tools.R check (PATH emptied) cover it. B34's
     note still holds: only the message changes.
3. **Cg3: pip tells an r-zig-compilers user to install r-zig-compilers
   for Fortran.**
   - Verified: groups.zig:104 has "(no Fortran)".
   - **Accepted.** The line becomes "pip install r-zig-compilers (zig
     only: PyPI has no Fortran compiler)", and wheel-test's grep follows.
4. **Cg4: the hint prints after an exit 1 too.**
   - Verified: after code-6's "the r-zig toolchain is complete" (exit 1),
     a site's "install the toolchain" contradicts it.
   - **Accepted.** The hint shows on 127 only. Open point B's ★ moves to
     (b): 0009 only, as C8 decided, with no shell added to 0010.
5. **Cg5: 0009's exit 1 vs 127 is neither folded in nor recorded.**
   - Verified: fix-zig-pkg-build-review PLAN.md:475-490 sends its
     follow-ups to TODO.md, and `grep 127` of TODO.md finds no such item.
   - **Accepted as open point J, ★ (a)** (fold in: the block is
     rewritten and the patches regenerated anyway).
   - Changed:
     - 0009's code;
     - I-T11's third text;
     - stress.R:207's classifier;
     - stress/README.md;
     - TODO's item under (b).
6. **Cg6: open point D leaves out that `_9` is users' first rzig
   build.**
   - **Accepted.** D now says so and carries the dispatch's numbers:
     four of five legs, read here.
   - The ★ stays (a). The per-install floor is bounded (4-14 s on the
     runners) and matches TODO's estimate. `_9` is what publishes phase
     3 and PR #25/#26.
   - See A1: the dispatch is the `--no-shared-cache` one.
7. **Cg7: win-64 depends on a native make that does nothing.**
   - Verified: recipe.yaml:518 lists `make >=4.4` for every OS. B28 (a)
     lists it for unix. SC §5 says m2-make comes first.
   - **Accepted.**
   - Changed: `if: unix`, recorded in the phase 4 record. Phase 7
     chooses per B11.
8. **Cg8: the consume step's OS branch, its deferred cost and the hosts'
   copies.**
   - Verified: build.yaml:299-308.
   - **Accepted, in a different shape.**
     - One script, `scripts/conda-consume.sh`, and a pkg task, run on
       every leg and on every host.
     - It writes one pixi manifest with three environments (no `pixi
       add/remove` sequence), using stress.R's nested-pixi precedent
       (`--manifest-path`, PIXI_* unset, stress.R:255-269).
     - Its one Windows line is env.sh:155's existing `cygpath -m`
       pattern.
     - Bare `Rscript` under `pixi run` is R.bat on win-64, so that check
       needs no branch.
   - **Departure from Cg8:** it runs all three tests, test-compilers'
     compiles included, because the zig cache is the recipe tests'
     (Cc11), which keeps them cheap.
   - Not adopted: a separate `--rzig-check=fortran` line. Inline R
     through `pixi run` needs quoting through two shells.
   - Conda's group removal is not tested: the upgrade test covers the
     files that move.
9. **Cg9: test-toolchain.R keeps the caller's PATH.**
   - Verified: unix make paths need only make and sh's builtins
     (shlib.mk's link rule, config.mk's `print`). R runs with its bin
     alone (hermetic-check). otool and readelf can be resolved before
     narrowing.
   - **Accepted.**
   - Changed: test-toolchain.R uses the shared header's
     `narrow(usr_bin = TRUE)`. Risk 1 is rewritten. A unix failure from
     a host tool is a finding to record under B25, not a reason to
     widen PATH past the env.
10. **Cg10: wheel-test writes the base-alone scenario again.**
    - Verified: test-preflight.R's `env_bin` resolves to `r_zig/R/bin`
      in the wheel, and every assertion holds there, since one text has
      every channel's line.
    - **Accepted.** wheel-test runs recipe/test-preflight.R for r-zig
      alone, and again after `pip uninstall ziglang`.
11. **Cg11: the /usr/bin/zig skip is dead.** The same point as Cc8, and
    **accepted** there.
12. **Cg12: declarative package checks.** **Accepted in part** (see
    Cc12):
    - `strict` is not used for the empty outputs: the test file's place
      in the checked list is unverified.
    - test-preflight.R keeps its three file assertions, because
      wheel-test runs it for the wheel (Cg10).
13. **Cg13: licences differ on conda too.** **Accepted, merged with Cc15**
    into E. ★ (a): the third-party licence on the packages that hold
    third-party files, and R's own `GPL-2.0-only OR GPL-3.0-only` for the
    base on both channels.
14. **Cg14: B18's trigger fired.**
    - Verified: zig 0.17.0 is on conda-forge's main label (read here).
      PyPI has no 0.17 win_amd64 (SP §8).
    - **Accepted.** Section 0 and the PR text say phase 4 stays on 0.16
      per B18. Open point K, and TODO's zig 0.17 wave line.
15. **Cg15: records missing.**
    - Verified: PLAN.md's section 5 table ("(today r-zig-toolchain)"),
      "Where PyPI differs" (make-wheel.py:229-241) and "What a user
      gets".
    - **Accepted.** Section 11 adds:
      - those fixes;
      - a base + compilers row;
      - TODO "Later": CC_VER/FC_VER from build.zig;
      - J's item under (b).
    - The "no zig departure" record is moot: Cc8 asserts the line, as
      PLAN.md's step asks.
16. **Cg16: one recommendation, worded once.** **Accepted.** The same
    sentence goes in r-zig-slim's description, the r-zig wheel's,
    `__init__.py` and the README.
17. **Cg17: README's platforms and "currently private".**
    - **Accepted.** Five platforms (with Cc19).
    - "Public" is open point L, ★ (a): the repodata reads without
      credentials, and the README's own install lines depend on that.
18. **Cg18: record E2's widening.** **Accepted.** Section 4's notes and
    the phase 4 record.

The goals critique's table of answered decisions (B14 ... feat-zig-pkg-build
N2) was re-read against PLAN.md's B28, B33, B34, B35 and phase 4 step. It
holds, with the exceptions it names: Cg7 for B28, Cg1/Cg3 for B35's
texts, and Cg15 for D7's drift.

## 3. Amender's checks (A1-A4)

1. **A1: the stress dispatch is the `--no-shared-cache` run.**
   - The planner called 38467907779 "the shared_cache run". Its
     report.json gives `args: --out=build/stress/run --trace
     --no-shared-cache g3 g4` and `shared_cache: false` on all four
     finished legs.
   - That is the dispatch TODO.md's "Depend less on make" asks for to
     decide the runner. Its numbers are in open point D.
2. **A2: the precondition is met.** build-r 38467545177 (ea7e6ee on
   main) is completed with success. Section 1 no longer says "after
   ea7e6ee's CI is green".
3. **A3: `R_MAKEVARS_USER`.** See Cc4. Unsetting it is not "no user
   Makevars". This affects today's two tests as well as the new ones.
4. **A4: Cc16 is settled by reading the package** (critic/m2/).

## 4. Open points

The amended plan's section 12 holds the menus.
- A, C, F, G: as the planner had them; the critiques agree.
- B: changed, ★ (b).
- D: the dispatch's numbers; ★ (a).
- E: both channels; ★ (a).
- H, I, J, K, L: new, each ★ (a).
