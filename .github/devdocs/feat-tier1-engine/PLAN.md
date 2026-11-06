# feat-tier1-engine — rzig runs tier 1 itself

**Merged (2026-11-05, #36).** After the queue (#28 to #35) and the
`_9` publish. No bump: it ships with the next build number. K3 and K4
(the final test's findings) are fixed in it; COFF bigobj objects are
left (feat-standalone-toolchain TODO.md, "After `_9`").

**Status (2026-10-23).** Worktree `wt/feat-tier1-engine`, branch
feat-tier1-engine at main d11dee1. It carries the uncommitted queue: the
manifest PR, phases 4, SHLIB, 5, 6 and 7, and win-link-fixes. This layer
is on top. The Zig part, the harnesses and these records are done.
Round 1 tested it on gamma, kappa and omicron ("Tested"), and its
findings are fixed ("Round 1 fixes"). Round 2 tested the fixed tree on
gamma, kappa and omicron, with both zigs: all passed ("Tested"). CI and
the stress dispatch are still to run.
Not committed: the user commits. pixi.lock is main's, unchanged, sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96. No
dependency change and no build-number bump (decision 8).

The design work is in the cr27 scratch directory,
`/data/gamma/luciorq/workspaces/temp/r-zig-pixi/cr27/` (below: `cr27/`):
- `cr27/design/RECOMMENDATION.md`: the synthesis and the decisions;
- `cr27/design/{A-hardened,B-prebuilt,C-norunner,D-open}/`: the four
  prototypes, each with DESIGN.md, RESULTS.md and prototype.diff;
- `cr27/design/judge-goals` and `cr27/design/judge-robust`: two
  independent judge reruns;
- `cr27/plan/{PLAN,RESULTS}.md` and `cr27/g1-trust` to `g5-tests`: the
  verification of PR #27's review.

## Why

PR #27 (feat-shared-build-runner) shares one zig build runner for tier 1
across installs. The runner is 45 MB and costs 3 to 13 s per R and zig on
linux, and up to 25 s on Windows. A review of #27 confirmed a trusted
shared directory, runner growth, a sweep race and a weak writability probe
(the findings table below).

The runner gave tier 1 three things:
- a `-j` scheduler;
- an order: the Fortran chain, then the def, then the link;
- a copy into the prefix.

Its step cache never applied to tier 1. Every step in build_t1.zig had
`has_side_effects` and wrote outside zig build's cache (C DESIGN, g5
probe7). So rzig can do those three things itself, and tier 1 then needs
no `zig build` at all.

## The design (decision 1: C, "no runner")

- `zigbuild/tools/rzig/tier1.zig` (new) is the plan engine:
  - an `std.Io.Select` pool of at most `-j` children (`-j` from install.R,
    else the CPU count);
  - with more than one Fortran source, the Fortran compiles run one at a
    time in OBJECTS order (feat-shlib-rzig-build Cc3); C and C++ run
    beside them;
  - on Windows the .def is written in process (`def.run`), with no
    `rzig def` child and no command-line limit;
  - the link reads `@<root>/objects.rsp` (response.zig's `rspName` and
    `rspText`, moved from build_t1.zig);
  - after a successful link, the library is copied into `libs<R_ARCH>/`;
  - `rzig t1` is the same engine for tier 2.
- `pkgbuild.zig`: tier 1 calls tier1.zig. All runner code is deleted.
  `zigBuild` is tier 2 only.
- `zigbuild/rpkg/build_t1.zig` is deleted (345 lines). rpkg.zig's
  `addLibrary` builds the zig object with zig build, then runs one step,
  `rzig t1 --plan .. --object <zig .o> --c .. --cxx .. --out ..`.
- Graft 2 (cr27 D1 A): `cache.root` keeps the XDG_CACHE_HOME,
  LOCALAPPDATA (Windows), HOME order. The `/tmp/.cache/r-zig` fallback
  becomes `$ZIG_GLOBAL_CACHE_DIR/r-zig`, else `error.NoCacheHome`. Each
  caller warns and goes on. Not A's u+rwx owner check: with a read-only
  cache it drops `.fini_array` from every package (tinyc.so 3080 bytes,
  not 3648; judge-robust logs/probes/ro-A-up-*.log).
- Graft 3 (cr27 item 4, 9b): both renames in cache.zig's `make` accept
  that another job won (`catch |err| if (!ctx.isFile(p)) return err`).
- Decision 3: each compile and link command line goes to stdout before it
  runs, as make echoes its recipes.
- Decision 7: a fake compiler (`testdata/fake_cc.zig`) replaces the shell
  stand-ins, so the scheduler tests run on Windows too.

After C, tier 1 needs only `zig cc`, `zig c++` and flang from the user's
zig. That is the make path's contract, on every OS and architecture,
Windows on ARM included.

## Measurements

All numbers are wall seconds. **cf** is conda-forge zig 0.16.0, **up** is
upstream zig 0.16.0 (PyPI ziglang). **#27** is the unmodified tree,
**make** is `R_ZIG_PKG_BUILDER=make`. Modes: **cold** (every cache
empty, 1 run), **first** (zig's global cache warm, rzig's cache empty:
a new env, an R upgrade), **warm** (mean / min of 5).

From `cr27/design/judge-goals/results/r1.md` (432 runs, all rc 0):

| zig | measure | #27 | A | B | C | D | make |
|---|---|---|---|---|---|---|---|
| cf | tinyc first | 5.04 / 5.03 | 5.26 / 5.02 | 1.23 / 1.15 | 1.23 / 1.20 | 1.16 / 1.13 | 1.19 / 1.19 |
| cf | tinyc warm | 1.27 / 1.18 | 1.27 / 1.14 | 1.12 / 1.05 | 1.18 / 0.99 | 1.08 / 1.00 | 1.18 / 1.04 |
| cf | many (30 objects) warm | 1.79 / 1.65 | 1.70 / 1.59 | 1.45 / 1.36 | 1.57 / 1.38 | 1.50 / 1.33 | 3.52 / 3.25 |
| cf | quadprog warm | 2.75 / 2.55 | 2.56 / 2.41 | 2.62 / 2.41 | 2.52 / 2.30 | 2.51 / 2.41 | 2.71 / 2.58 |
| up | tinyc first | 3.07 / 3.00 | 3.10 / 3.07 | 1.04 / 1.03 | 0.94 / 0.94 | 0.96 / 0.96 | 0.97 / 0.97 |
| up | many warm | 1.45 / 1.24 | 1.37 / 1.13 | 1.20 / 1.07 | 1.22 / 1.06 | 1.21 / 1.11 | 2.01 / 1.78 |
| cf | rzig's cache after the runs | 46.8 MB | 46.8 MB | 0 | 0 | 0 | 0 |

The cold rows are dominated by zig building compiler_rt and libc++ under
host load. The judges warn against ranking on them.

Other measurements:
- **"first" mode, judge-robust** (`cr27/design/judge-robust/bench/summary.md`,
  384 runs): tinyc cf 5.29 s (#27) against 0.80 s (C); quadprog cf 6.37
  against 2.25.
- **Isolated warm `rzig build`** (`judge-robust/bench/micro.csv`): C is
  0.07 to 0.36 s faster than #27. The steady-state gain is small.
- **Concurrency** (judge-goals par.tsv, judge-robust par.txt): 4
  concurrent installs into separate libraries, cold and warm, both zigs,
  4/4 for every design.
- **Processes** (judge-goals trace.tsv, warm tinyc): execve 42 (#27)
  against 39 (C).
- **Read-only rzig cache** (judge-robust probes/rocache.txt): #27 7.6 to
  10.6 s per install, C 2.3 to 2.9 s.
- **Planted build_t1.zig in the cache** (judge-robust probes/plant.txt):
  #27 ran it; C ignored it.
- **Scheduler stress** (judge-robust stress.csv, judge-goals cstress.tsv):
  C 162 + 90 builds with 0 aborts after the lifetime fix (7 of 30 before).
- **kappa, win-64, up** (`cr27/design/C-norunner/RESULTS.md`): cold tinyc
  / many / quadprog / SHLIB 29.6 / 48.8 / 30.0 / 29.5 s for C against
  41.5 / 63.9 / 42.1 / 39.1 for #27; many with fresh sources 3.48 s
  against 4.79.
- **LOC:** the C prototype.diff was Zig +565 / -755. This PR against its
  base (`git diff --no-index --numstat`, every .zig file): +1,002 / -789
  as reviewed, +1,151 / -795 after round 1. The growth is tests,
  testdata/fake_cc.zig, test-bin and the echo. The harness edits delete
  or invert about 90 lines.

## The review findings under C

| # | finding (verified status) | under C plus the grafts |
|---|---|---|
| 1 | shared dir trusted, `/tmp/.cache/r-zig` fallback, a planted build_t1.zig or runner runs (CONFIRMED) | Gone for tier 1: no file in rzig's cache is compiled, read as code or run by `rzig build`. Residual, older than #27: dso_fini.o, cfguard.o, the archive copies and the libc++ mirror (g1 probe 6). Graft 2 removes the /tmp fallback. The follow-up PR removes dso_fini and cfguard from the cache |
| 2 | an in-place zig rebuild accumulates runners, +45 MB (CONFIRMED) | Gone: no runner, no key |
| 3 | zig's path in the key gives every env its own runner (PARTLY) | Gone: a new env, R upgrade or standalone tree pays 0 s and 0 MB |
| 4 | the sweep can delete a dir in use (CONFIRMED, g3 race-c) | Gone: no sweep. zig locks its own global cache |
| 5 | the writability probe checks only the top-level file (CONFIRMED) | Gone: tier 1 writes only in its build root |
| 6 | contract-test's XDG_CACHE_HOME moves other caches (PARTLY) | Unchanged. Record line below |
| 7 | build_t1.zig's dead addFileInput calls and overstated docs (PARTLY) | Gone with the file |
| 8 | `zig version` spawn and cache scan per install (both run; cost REFUTED) | Gone from `rzig build`. The dso_fini key spawn remains until the follow-up. SHLIB's check.zig spawn stays (decision 6) |
| 9a/9b/9c | writeWhole duplicate, Windows rename tolerance, test comparator | 9a: writeWhole is deleted. 9b: graft 3. 9c: in the deleted runner tests |
| 10 | pkg-parity's runner-object grep (CONFIRMED, test-only) | Gone: the checks are now "no build-runner-* entry" |

The cr27 fix plan (`cr27/plan/PLAN.md` items 1 to 8, decisions D1 to D7)
is superseded. Only item 1 (D1 A) and item 4's 9b part carry over.

## Decisions (user, 2026-10-23: every recommended option)

1. Design: **A**, C-norunner plus the grafts. B (a prebuilt runner) is
   the documented fallback.
2. PR shape: **A**, one PR, feat-tier1-engine: tier 1, tier 2, the
   deletions, the harnesses, grafts 2 and 3, full-ci.
3. Compile-command output: **A**, echo each compile and link command line
   as make does.
4. dso_fini.o and cfguard.o: **A**, a follow-up PR,
   feat-r-home-link-objects, prototyped and measured first.
5. rzig size: **A**, accept the growth in this PR and record the sizes
   (below).
6. check.zig's "a zig that is not R's" SHLIB gate: **A**, keep it. Its
   non-build_t1 reasons were not verified.
7. Scheduler tests on Windows: **A**, a fake-compiler test executable
   built in rzig's build.zig.
8. Release packaging: **A**, no build-number bump. It ships with the next
   planned bump.

## Records

- **Finding 6.** contract-test.sh sets XDG_CACHE_HOME to keep rzig's
  cache in the workspace. That also moves the XDG caches of the programs
  the installs run (R_user_dir, pkgcache). zig is not affected: env.sh
  exports ZIG_GLOBAL_CACHE_DIR. Nothing asserted reads those caches. The
  export stays, and its comment now says so.
- **F8 cost.** Under #27, `zig version` took 9 to 25 ms and the cache
  listing under 0.5 ms at 100 entries, against a 0.8 to 3.1 s warm
  install (cr27 g3). The SHLIB path spawned `zig version` twice in one
  process (check.zig and pkgbuild.zig, +25 ms). Under C, a package's
  `rzig build` spawns none of its own, and SHLIB keeps check.zig's one
  (decision 6). The dso_fini key still spawns one at link time.
- **A stale ZIG_LOCAL_CACHE_DIR hit.** Building rzig from two copies of
  the tree with one shared ZIG_LOCAL_CACHE_DIR and a relative
  `--build-file` reused the first tree's binary: the manifest lists the
  first tree's absolute paths (`cr27/design/A-hardened/RESULTS.md`, zlc/h).
  This affects developers and harnesses, not users. Give each tree its
  own local cache.
- **The scheduler lifetime rule.** The Select's group lives on the stack,
  and a task finishes after it queues its result. So `defer
  sel.cancelDiscard()` is required before tier1.zig returns. Without it a
  worker decremented a dead group's counter and std.Io.Threaded aborted:
  4 of 302 installs in cr27's first benchmark pass, 7 of 30 quadprog
  builds in the repro. The unit test that guards it is `compileAll:
  round after round of tasks that end at once`. Its tasks run no
  process: they return at once, the quickest tasks there are
  (compileAll takes the task function, runJob in a build). Without the
  line it aborted in 20 of 20 runs of the whole test binary at its
  default 30,000 rounds, and in 14 of 20 at 10,000 (gamma, both zigs;
  `t1e/fix-r1/logs/final-nodefer.txt`). On kappa, without the line, the
  whole test binary aborted in 12 of 15 default runs and in 5 of 5 at
  RZIG_TEST_STRESS=300000 (`t1e/test-kappa/RESULTS.md`, section 2). The
  rounds cost about 6 s on gamma, 2.4 s on kappa and 10.5 s on omicron.
  Its first form, a missing program in 9 rounds of 10, caught it in 1 of
  10 (`t1e/review1`). Keep the rule through the zig 0.17 Io port.
- **A failed spawn leaves a zombie (zig 0.16).** std.Io.Threaded's
  processSpawnPosix returns the child's exec error without waitpid on
  the forked pid (lib/std/Io/Threaded.zig, after `readIntFd`). The child
  stays a zombie until rzig exits. In a build a failed spawn ends the
  build (`cannot run <tool>`), so at most `-j` of them. The first form of
  the lifetime test spawned a missing program 3,600 times. On omicron,
  with RZIG_TEST_STRESS=5000 or under `ulimit -u 3000`, fork then hit
  the per-user process limit: 12 tests failed and 1 crashed
  (`t1e/test-omicron/round1/RESULTS.md`). The test now spawns nothing.
  In round 2 both cases passed on omicron with both zigs, 174/174
  (`t1e/test-omicron/RESULTS.md`, section 1).
- **Tier 2's -j.** `rzig t1` is one zig build step, so zig build's `-j`
  no longer holds its compiles. rzig build passes `-Djobs=<N>` with
  `-jN`; rpkg.zig's readPlan reads it, and addLibrary passes `-j N` to
  `rzig t1`. With no -j both use the CPU count, as zig build did. zig
  build refuses a -D option the root does not declare, so rzig and
  share/zig/rpkg must come from one build, as they do in every tree,
  conda package and wheel. Checked on gamma with both zigs: zighelloc
  with R_ZIG_JOBS=1 ran `rzig t1 ... -j 1`, with MAKEFLAGS=-j3 `-j 3`
  (`t1e/fix-r1/logs/func-*`). Round 2 saw the same on gamma, kappa,
  omicron and osx-64, with both zigs.
- **The rbuild contract.** A tier-2 package's rbuild sees `opts.plan` as
  rpkg.zig's Plan: name, srcdir, output, libs_dir, rzig, target,
  r_include, path, root, jobs. Before this PR it was build_t1.zig's
  Plan, with the compile and link words (cc, cxx, fc, f9x, link, libs,
  toolchain, sources, env, def, win_def). `rzig t1` reads those itself
  now. No fixture or known package reads them (grep). An rbuild that did
  no longer compiles.
- **The plan.zon coupling.** rpkg.zig reads plan.zon with its own
  10-field Plan (`ignore_unknown_fields`; round 1 added `jobs`); rzig
  reads it with pkgplan.Plan. A field rpkg.zig reads must keep its name
  and type in pkgplan.zig. pkgplan.zig's comment names the coupling.
- **The lost fallback.** A tree without `share/zig/rpkg/build_t1.zig` sent
  tier 1 to make (exit 3, Cc8). Tier 1 now needs no file there and simply
  builds. Tier 2 still needs build_t2.zig and rpkg.zig. parity-test.sh's
  tier-1 builds run in an R_HOME with no share/zig/rpkg.
- **The compile-echo format.** One line per compile, when it starts, and
  one for the link, before it runs, on stdout, each written in one write
  (Ctx.echo). Each word is shell-quoted only when it must be
  (shellwords.quote, as `--dry-run` prints). The in-process .def has no
  line. A compile reads
  `<R_HOME>/bin/toolchain/zig-cc <flags> -c tinyc.c -o <root>/obj/0/tinyc.o`;
  the link reads `... -o <root>/tinyc.so @<root>/objects.rsp <libs>`. make
  prints the same words, with Makeconf's spacing and quotes, `-o tinyc.o`,
  and the objects in place of `@objects.rsp`. A failure prints
  `<source> failed (<code>): <line>` or `the link failed (<code>): <line>`.
  A child that a signal ended prints `was killed by signal <n>` in place of
  `failed (<code>)` (the OOM killer's 9), and the code is 1. Only the
  first failure gets a line, as before. The quoting is POSIX shell's on
  Windows too, as `--dry-run`'s is: a line with an 8.3 name (`~`) is
  single-quoted, and it is not a cmd command line.
  Tier 2's `rzig t1` echoes too: its Run step has side effects, so zig
  build gives it the inherited stdio.
- **The harnesses tell the echo from make's.** verify-helpers.sh's
  `make_recipes` leaves out a line whose `-o` writes into rzig's build
  root (`<dir>/.rzig/...` or `<dir>/.rzig.<16 hex>/...`), the word in
  single quotes or not. make's objects go beside the sources. Without
  this, every "no recipe make echoed" check in pkg-parity.sh and
  verify-bundle.sh fails on the echo.
- **Windows: the compiles have no console.** tier1.zig spawns them with
  `create_no_window = true`, as Ctx's other spawns are, so that rzig run
  from R's GUI opens no console window per compile. zig build's Run
  steps and make's children shared rzig's console. So a Ctrl-C in a
  console R stops rzig, and the running compiles finish on their own,
  in the build root. UNVERIFIED on kappa: SSH gives no interactive
  console.
- **rzig's size per copy.** ReleaseSafe and stripped, R's default
  (`zig build --build-file zigbuild/tools/rzig/build.zig -Dtarget=<t>
  -Dr-version=4.6.1`), after round 1 (`t1e/fix-r1/logs/xbuild-*.log`).
  The #27 column is the PR #27 state (`t1e/impl-harness/sizes.log`,
  `t1e/impl-core/logs/cross.log`):

  | target | cf, this PR | up, this PR | #27 (cf) | per copy | copies | per tree |
  |---|---|---|---|---|---|---|
  | linux-64 (x86_64-linux-gnu.2.17) | 1,080,416 | 1,080,328 | 688,272 | +392,144 | 6 | +2.35 MB |
  | win-64 (x86_64-windows-gnu) | 1,351,168 | 1,351,168 | 974,848 | +376,320 | 10 | +3.76 MB |
  | aarch64-windows-gnu | 1,112,064 | 1,112,064 | 803,328 | +308,736 | 10 | +3.09 MB |
  | aarch64-macos (cross-built, no codesign) | 879,512 | 879,512 | 534,552 | +344,960 | | |
  | x86_64-macos (cross-built) | 1,010,816 | 1,010,816 | | | | |
  | aarch64-linux-gnu.2.17 | 871,064 | 870,960 | | | | |

  Round 2 measured the same bytes (`t1e/test-gamma/RESULTS.md`, section
  13; the last two rows are from there). The 6 rzig copies of gamma's
  real build are the cf linux-64 binary, 1,080,416 B. kappa's rzig.exe
  is 1,351,168 B with both zigs (`t1e/test-kappa/RESULTS.md`). R's build
  on omicron made rzig natively: 897,648 B on osx-arm64, 6 copies per
  tree, and 1,036,976 B on osx-64 under Rosetta
  (`t1e/test-omicron/RESULTS.md`, sections 4 and 5). These are not the
  cross-built macOS binaries of the table.

  The first record (+353,696 on linux-64) predates main's Ctx.warn fix:
  test-gamma measured 1,078,592 B after it
  (`t1e/test-gamma/RESULTS-round1.md`, section 12), and round 1 adds
  1,824 B. The cause of the growth is not analysed (decision 5).
- **The cache root.** zig resolves its own cache as
  ZIG_GLOBAL_CACHE_DIR, then `$XDG_CACHE_HOME/zig`, then `$HOME/.cache/zig`
  (LOCALAPPDATA on Windows). With none of these it stops with
  "AppDataDirUnavailable". rzig keeps its XDG, LOCALAPPDATA, HOME order,
  so no existing cache moves, and only its last fallback changes. Whenever
  zig can run, rzig's cache is in a place as private as zig's.
- **fake_cc and test-bin.** `testdata/fake_cc.zig` is a Zig program that
  rzig's build.zig builds for the tests' target and embeds. Each scheduler
  test writes it out as `cc` and `ld`. Its source lines drive it (`sleep`,
  `wait`, `need`, `make`, `alone`, `exit`, `kill`). It writes its
  arguments into the object, so a test sees the words a compile got (a
  flag with a space is one word, on Windows too). It counts concurrent
  compiles when it starts and after its lines: the -j test asserts a
  peak of exactly 3 at `-j 3`, three compiles that wait for each other
  and nine that sleep. `zig build --build-file zigbuild/tools/rzig/build.zig
  test-bin -Dtarget=<t>` installs `bin/rzig-test[.exe]` to copy to another
  host. The test-bin step, the `rzig t1` usage line and the
  `RZIG_TEST_STRESS` knob are additions beyond the prototype: the user
  keeps or drops them.
- **ZIG_LOCAL_CACHE_DIR.** Tier 1 no longer reads it. zig cc does: with
  it set, zig cc keeps its objects there instead of in the global cache
  (measured here with cf zig: `zig cc -c` wrote `o/` under
  ZIG_LOCAL_CACHE_DIR and nothing under ZIG_GLOBAL_CACHE_DIR). Tier 2's
  zig build takes it as `--cache-dir`, as before.

## Harness changes

Each edit deletes a runner assertion or turns it into "no build-runner-*
entry in rzig's cache, no `zig build` command in the trace".
- `zigbuild/tools/rzig/parity-test.sh`: the 6 runner checks become 3. The
  first tier-1 build checks the objects and library in the build root, no
  zig build in the trace, no build-runner-* and nothing of the package in
  rzig's cache. The second checks that rzig's cache is unchanged. The SHLIB
  real build checks no zig build and an unchanged rzig cache. The "another
  R's rpkg" check and the "missing build_t1.zig, 3" check are deleted. The
  check "Fortran modules in OBJECTS order at -j 8, five times" is kept.
- `scripts/pkg-parity.sh`: `runner_same`, `runner_dirs` and `objects_of`
  become `no_runner <what> [<log>]`. The ZIG_LOCAL_CACHE_DIR case checks
  zig cc's objects there and no zig build. The Ncpus = 2 case checks for
  no build-runner-*.
- `scripts/verify-bundle.sh`: pfC checks no zig build in the trace, and no
  pfC object in rzig's cache. Comments follow.
- `scripts/verify-helpers.sh`: `make_recipes` (above), and
  `rzig_cache_odd <cache>` (round 1). It prints each entry of rzig's
  cache that is not of rzig's own kinds (dso-fini-*, cfguard-*,
  archive-*, zig-lib-*), and `no dso-fini-*` (linux) or `no cfguard-*`
  (Windows) when that kind is missing. pkg-parity's `no_runner` and
  verify-bundle's pfC fail on any line. So the checks also show that
  rzig's cache is where they look: a check that only says "no
  build-runner-*" passes when the cache is elsewhere.
  Changed by feat-r-home-link-objects (2026-10-23): dso-fini-* and
  cfguard-* now count as odd, the "no dso-fini-*" and "no cfguard-*"
  lines are gone, and a second argument, a traced log, checks that
  RZIG_TRACE's `cache` line names the directory checked
  (`.github/devdocs/feat-r-home-link-objects/PLAN.md`, decision 5).
- `scripts/contract-test.sh`: the comment only.
- `scripts/verify-tree.sh`, `recipe/recipe.yaml`, `recipe/test-preflight.R`:
  build_t1.zig leaves the file lists. recipe.yaml and test-preflight.R
  check build_t2.zig in its place. No dependency changes.
- `stress/stress.R`, `stress/README.md`, `.github/workflows/stress.yaml`:
  `--no-shared-cache` and the `shared_cache` input are gone. stress.R now
  always unsets ZIG_LOCAL_CACHE_DIR, as a user's install has it. Its copy
  of rzig's cache root follows graft 2.
- The new stress case: the `tinyjobs` row (group g0, tag `local`) in
  `stress/packages.tsv`. stress.R writes 64 one-line C files and installs
  them 20 times at `-j 32` (the row's MAKEFLAGS and STRESS_REPEAT), a
  fresh copy each time, until the first failure. stress.yaml's default
  targets gain g0.

Remaining references to the runner, and why they stay:
- the new negative checks above ("no build-runner-*");
- tier1.zig's, pkgbuild.zig's and cache.zig's comments, which say what
  replaced the runner and the /tmp fallback;
- the history records in `.github/devdocs` (feat-shared-build-runner,
  feat-zig-pkg-build, fix-zig-pkg-build-review, the feat-standalone-toolchain
  phase records, feat-shlib-rzig-build, feat-win-link-fixes). Where one
  describes build_t1.zig or the runner as current, it now has a dated
  "superseded" line.

## Tested

### Round 1, the reviewed tree

The tree: `git diff` of the worktree's tracked files sha256
`da2bb0d06b2c37712b89fe8b3f90bf5998a702d63b06161bf07fa2852867b467`
(97 status entries); the untracked files' sha256s are in
`t1e/impl-harness/NOTES.md`. pixi.lock sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96, before
and after, on every host.

| leg | result | record |
|---|---|---|
| implementer, gamma | rzig unit tests 172/172 (cf, up); parity-test.sh 0 failed (cf, up); stress.R `tinyjobs` ok (cf); ReleaseSafe linux-64 and win-64 | `t1e/impl-core`, `t1e/impl-harness` |
| review1, gamma | 172/172 (cf, up); parity-test 0 failed; real installs of 7 packages, SHLIB and tier 2, both zigs; kappa 140 pass / 32 skip / 0 fail and omicron 172/172 with cross-built test-bins. 11 findings | `t1e/review1/RESULTS.md` |
| test-gamma, linux-64 | the chain (build, verify-tree, toolchain, verify-toolchain, package-toolchain, verify-package, compile-tree, pkg-parity, hermetic, contract; pkg-parity and contract with up too): all rc 0; rzig-test 172/172 and parity-test 0 failed, both zigs; 30 warm installs each of quadprog and many at -j16 per zig, 0 failures; tinyjobs ok, both zigs, 0 split trace lines; 4 concurrent installs 4/4; strace: 39 execve, 0 zig build | `t1e/test-gamma/RESULTS-round1.md` |
| test-kappa, win-64 | rzig-test 140 / 32 skipped / 0 failed (10 runs, 2 at RZIG_TEST_STRESS=5000; native with up and with cf); parity of tinyc, many, fmod, quadprog and SHLIB with both zigs: exports equal make's, no zig build, no `rzig def`; tier 2 zighello and zighelloc; 4 concurrent installs 4/4; graft 3's probes: 0 rename failures in 384,000 | `t1e/test-kappa/r1/RESULTS.md` |
| test-omicron, osx-arm64 and osx-64 | the first real macOS install of design C: the chain, rzig-test 172/172 (cf, up), pkg-parity (cf, up), package and verify-package, tier 1 and tier 2 checks, 60 warm installs at -j16; osx-64 under Rosetta (cf). Failed: rzig-test at RZIG_TEST_STRESS=5000 or under `ulimit -u 3000` (the zombie record above) | `t1e/test-omicron/round1/RESULTS.md` |

Every non-ok row of those legs, with its cause, is in its RESULTS.md.
The ones that are not expected failures or harness bugs: the omicron
zombie failure, and kappa's F1 (below). Both reviews' findings are
under "Round 1 fixes".

### Round 2, after the round 1 fixes

The tree: `git diff` sha256
`182b51172a74f8b6ebd5e19f16f95338bfb59d897335ddf8f2c9f64908de5a8a`
(97 status entries), the untracked files' list in
`t1e/fix-r1/logs/untracked-end.sha256` (91 files), whose own sha256
is `14745ece6af304cb90dd77b9d6ca635cbb3edef8cb8162efd605c373f1c2da08`.
pixi.lock unchanged, before and after, on every host. Every leg below
tested this tree. After round 2 only this record changed (records
only), until the K3 and K4 fixes (below).

| leg | result | record |
|---|---|---|
| fixer, gamma | `zig fmt --check` with both zigs; rzig-test 5 runs per zig (174/174, parity-test 0 failed); rzig and test-bin cross-built for 4 targets with both zigs (16 builds, rc 0); `bash -n` on the edited scripts; real installs of tinyc, many, quadprog, fmod, zighello, zighelloc and badc with both zigs | `t1e/fix-r1/NOTES.md` |
| test-gamma, linux-64 | the chain (build, verify-tree, toolchain, verify-toolchain, package-toolchain, verify-package, compile-tree, pkg-parity, hermetic, contract; pkg-parity and contract with up too): all rc 0, with `rzig_cache_odd` in pkg-parity and verify-package; rzig-test 174/174 and parity-test 0 failed, both zigs, and 3 more unit runs per zig; real installs of 7 packages on this tree and on #27's, both zigs; tier 2's `-j 1` and `-j 3`, both zigs; 30 warm installs each of quadprog and many at -j16 per zig, 0 failures; tinyjobs ok, both zigs, 0 split trace lines; 4 concurrent installs 4/4, and in 3 interleaved cold rounds 3.0 s (cf) and 2.0 s (up) faster than #27; strace: 39 execve, 0 zig build; the cache root; the benchmark; the sizes | `t1e/test-gamma/RESULTS.md` |
| test-kappa, win-64 | rzig-test 142 / 32 skipped / 0 failed (174; 5 default runs, 3 at RZIG_TEST_STRESS=300000, native `zig build test` with up and with cf), all 8 tier1 tests run; parity of tinyc, many, fmod, quadprog and SHLIB with both zigs: exports equal make's, no zig build, no `rzig def`, `rzig_cache_odd` 0 lines, `make_recipes` 0; the echo in R CMD check; tier 2's `-j 1` and `-j 3`, both zigs; 4 concurrent installs 4/4; 80 warm installs at -j16, 0 failures; graft 3's probes: 0 rename failures in 1,440,000 | `t1e/test-kappa/RESULTS.md` |
| test-omicron, osx-arm64 and osx-64 | rzig-test 174/174 with both zigs at the default, at RZIG_TEST_STRESS=5000 and under `ulimit -u 3000` (round 1's failure is fixed); the chain, pkg-parity (cf, up), package and verify-package; tier 1, the echo, tier 2 and its -j, 4 concurrent installs and warm stress at -j16, on the compile tree and on the extracted archives; osx-64 under Rosetta, cf and up: rzig-test 174/174, build, verify-tree, toolchain, compile-tree and the same tier 1 and tier 2 checks; 0 Falcon-like lines | `t1e/test-omicron/RESULTS.md` |

Every non-ok row of round 2, with its cause, is in its RESULTS.md: the
planned badc failure, zig's refusal with no cache directory, rspec.zig's
format and the dlamch.f warning (both older than this PR), R CMD check
NOTEs that #27 gives too, kappa's 32 Windows skips (the same set as
round 1), the no-defer probe, F1 in the probe, and tester harness bugs
fixed before use. None points at this PR's code.

Not run (UNVERIFIED):
- CI: the core tier, full-ci and the upstream-zig legs; the stress
  dispatch; rzig-test on GitHub's macOS and Windows runners.
- conda-forge zig in a full Windows R build (kappa ran the unit tests
  and the installs with it).
- The repo's pkg-parity.sh, verify-bundle, verify-tree and contract-test
  on Windows (kappa ran equivalent checks); pkg-parity, verify-package
  and contract on osx-64.
- R built with up zig on linux (every test after the build ran with
  both zigs).
- The NoCacheHome warning in a real install: zig refuses first; the
  unit tests cover it.
- The Windows console behaviour of `create_no_window`; a tier-1 path
  with spaces or non-ASCII characters through the echo and objects.rsp
  on Windows.
- Windows on ARM and linux-aarch64 at run time.
- The conda package, conda-consume and the wheel, end to end.
- shellcheck (not installed here).

## Round 1 fixes

- **The lifetime test** spawns nothing: the zombie record and the
  lifetime rule above.
- **The -j test** was vacuous: its compiles hardly overlapped (a peak of 2
  to 3 on 16 CPUs) and it asserted `peak <= 24`. It is now its own test,
  with a peak of exactly 3 at `-j 3`. The first test's `peak <= 5` is
  gone.
- **Tier 2's -j:** the record above.
- **The rbuild contract:** the record above, and rpkg.zig's Plan
  comment.
- **Signals:** `was killed by signal <n>` (the echo-format record).
- **Test gaps:** a test of the .def written in process (plan.def, a COFF
  object) and of a package's own `<pkg>-win.def`; fake_cc's argv; the
  rspName cases dropped in the move from build_t1.zig (a `'` the two do
  not share, Windows `../../Temp`, `./obj`), and rspText's exact line.
- **Text:** pkgbuild.zig's header (tier 1 runs no zig build) and its
  usage (--rpkg-dir and --cache-dir are tier 2's); pkgplan Opts.rzig
  (`rzig t1`, every OS); stress.R and stress/README.md (tier 1's failure
  line); this record's LOC and sizes.
- **Harness:** `rzig_cache_odd` and `make_recipes` (Harness changes).
- **RZIG_TRACE lines split by the echo:** fixed before round 1 (main
  session, `t1e/main-fix/NOTES.md`). Ctx.warn formats the whole line
  and writes it once, as Ctx.echo does; std.debug.print, which wrote 64
  bytes at a time, stays only as the fallback on out-of-memory. In the
  `tinyjobs` run before the fix, 6 `zig-cc: ` trace lines held an echo
  (`t1e/impl-harness/stress-out/logs/tinyjobs.log`). After it: 0, in
  tinyjobs with both zigs (test-gamma RESULTS-round1.md section 7), in kappa's parity logs
  with both zigs, and in omicron's installs.
- **Not changed:** kappa's F1. A reader can fail to open cfguard's
  object while another job renames over it (14 of 192,000 opens in a
  probe; 0 in 200 racing links). It is older than PR #27, and graft 3
  covers the renamer only. A follow-up, with feat-r-home-link-objects,
  which takes cfguard out of the cache.
- **Not changed:** stress.R's classifier. The `was killed by signal 9` line
  comes before R's `ERROR: compilation failed`, where first_error starts
  the failing text, so a resource pattern for it would not see it.

## Final test fixes (K3, K4)

The final queue test (2026-10-30, kappa, stress g1 g2) found two
defects in rzig, through mlpack. Both are fixed here. Evidence:
`final/followup-2-kappa` and `final/followup-3-kappa` (finding 1 in
each). The fix's logs: `queue2/k4/`.

- **K3, def.zig's section offset.** `(section - 1) * section_size` was
  u16 arithmetic. A symbol in section 1640 or above overflowed, and rzig
  panicked: 10 of mlpack's 67 objects (dbscan.o has 2,791 sections).
  main d11dee1 has it too. The offset is now usize. A bigobj object
  (more than 65,279 sections) is still not read: def.zig returns
  BadObject and the build fails (a note in def.zig's header).
- **K4, a crash read as "needs make".** This PR runs def.zig in rzig's
  own process. On Windows zig ends a panic with
  `RtlExitUserProcess(3)`, and 3 is rzig build's "needs make". So
  mlpack's panic made R run the make path, and its stress row read ok.
  crash.zig now ends a panic, and a fault zig's handler reports, with
  exit 70 on Windows; main.zig makes it the root's `panic` and `debug`.
  Elsewhere zig's SIGABRT stays, which R already reads as a failure.
  Not chosen: moving exit_needs_make (patch 0013, check.zig and the
  harnesses that read 3 would change, and R and rzig would have to agree
  on the new code), or running def as a child again (it covers def only).
- **Tests.** def.zig: a generated object of 65,279 sections, with
  symbols in sections 1, 1640 and 65,279. tier1.zig: testdata/crash.zig,
  built as rzig is, panics in a thread and writes to address 0. Each
  must end as a failure R reads as one (exit 70 on Windows, SIGABRT
  elsewhere), never 3. Both tests fail without the fixes (kappa: the K4
  test "expected 70, found 3"; the K3 test panics). The K4 test checks
  crash.zig on Windows only (elsewhere zig's own handling ends the same
  way), and it runs testdata/crash.zig's decls, not main.zig's:
  rzig-test's root is zig's test runner. So a comptime test in main.zig
  checks that its `panic` and `debug` are crash.zig's.
- **Tested.** The tree: `git diff` sha256
  `e088ecef9b0e1561473c5a40724f84a753b8bd9c9088445b06308dac1a1eaec6`
  (99 status entries); with feat-r-home-link-objects on top,
  `d03a6508c82bf970d8e300265765d3243a30b08ac7522af82256ae1659344341`
  (105). gamma: rzig-test 176/176 with both zigs, also at
  RZIG_TEST_STRESS=5000, parity-test 0 failed; rzig and its test-bin
  cross-built for x86_64 and aarch64 Windows with both zigs; `rzig def`
  and `rzig t1` (plan.def) on mlpack's 67 objects give nm's 17,819
  names. kappa: rzig-test 144 passed, 32 skipped, 0 failed, with both
  zigs. There `rzig def` on dbscan.o exits 0; with def.zig unfixed it
  exits 70 after the panic, and 3 with zig's default handling. omicron:
  the arm64 test-bin, 176/176. With feat-r-home-link-objects on top:
  172/172 on gamma (both zigs), 145 passed and 27 skipped on kappa, and
  gamma's chain (build to contract) and stress g0 ok.
- **Review fixes (2026-10-31).** After those tests, the review of K3 and
  K4 found three small things, all fixed here. def.zig added
  `1 + number_of_aux_symbols` in u8, which overflows at 255 aux records
  (a crafted object made rzig panic); it adds in usize now, with a test
  of one symbol and 255 aux records. main.zig has the comptime test
  above. crash.zig's comment names 134, SIGABRT's wait status with a
  core dump. The tree: `git diff` sha256
  `d879264e332025fe87d3f2a518303dcd0bbb22044259a2ac510c875563daaf97`
  (99 status entries); with feat-r-home-link-objects on top,
  `65896996aa05eb56d0af450039848c6b6f03b97732a1757367e6dde006ca50ba`
  (105). gamma: rzig-test 178/178 with both zigs, also at
  RZIG_TEST_STRESS=5000, parity-test 0 failed; with
  feat-r-home-link-objects, 174/174; rzig and its test-bin cross-built
  for x86_64 and aarch64 Windows and macOS with both zigs. Each fix
  undone fails a test: the aux test panics (`integer overflow`), and
  without main.zig's two decls the comptime test does not compile.
  kappa and omicron did not rerun: the change is one addition's type,
  a test and comments.

## Open

- The tests and CI that are UNVERIFIED (above).

## Follow-up: feat-r-home-link-objects

Decision 4 (A). A PR of its own, after this one, prototyped and measured
first.
- R's build.zig compiles `dso_fini.o` (linux) and `cfguard.o` (Windows)
  for R's target into R_HOME. rzig links them from there. Their
  `cache.compiled` entries and the `zig version` spawn of their key go.
- Expected: rzig's cache then holds only the archive copies and the libc++
  mirror, and no package build spawns `zig version`. UNVERIFIED: no
  prototype did it.
- Its tests: both zigs, an R built by cf and run with up and the other way
  round, and kappa for cfguard.
- Done (2026-10-23), uncommitted on top of this PR in
  wt/feat-r-home-link-objects: the objects sit beside rzig in
  R_HOME/bin/toolchain, with no cache fallback. Measured on gamma: a warm
  tinyc install runs 38 execve and no `zig version` (39 and 1 here), rzig's
  cache stays empty, and R CMD SHLIB keeps only check.zig's spawn
  (decision 6). `.github/devdocs/feat-r-home-link-objects/PLAN.md`.

## Sequencing

Branch feat-tier1-engine from main after the queue merges: the manifest
PR, then phases 4, SHLIB, 5, 6 and 7, then win-link-fixes. Its slot
against phase 8 is the user's. Before the merge: the core CI tier, then
the `full-ci` label (all 5 subdirs and the gated upstream-zig legs,
because tier 1 changes everywhere), and a stress dispatch read row by row.
