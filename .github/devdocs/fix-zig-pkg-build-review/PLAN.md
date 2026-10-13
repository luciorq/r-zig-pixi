# fix-zig-pkg-build-review — PR #25's review, fixed in one follow-up PR

**Status (2026-10-13).** Branch fix-zig-pkg-build-review, from main
07e12c0 (PR #25, feat-zig-pkg-build, merged). Every item of the review
is done; a second, adversarial review of the fixes found nine more,
also done ("The fixes' own review"). Tested on linux-64 (both zigs),
osx-arm64 (omicron) and win-64 (kappa): every task passed, see
"Tested". Not committed: the user commits. pixi.lock is main's,
unchanged, sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96. CI is
still to run: the PR is to get the `full-ci` and `upstream-zig` labels
(menu 3). No build-number bump: feat-zig-pkg-build's N5 stands, and
phase 4's bump publishes both packages (feat-standalone-toolchain
TODO.md, phase 4). Two choices are left to the user ("Open
decisions").

## Why

PR #25 (feat-zig-pkg-build: `R CMD INSTALL` through `rzig build`, tiers
0 to 3, patches 0012 and 0013, `--rzig-check=package`, pkg-parity, on
top of phase 3's PR #24) was to be reviewed by the phase 3 session
before its commit and push (its N7). The commits came first, and the PR
merged (07e12c0, 2026-10-13 10:07Z) about a minute after the review was
asked for; feat-zig-pkg-build's PLAN.md, "Consolidation with phase 3",
records the sequence [records-REC-5]. The review then ran on the merged
state. The user, 2026-10-13: "I have merged PR #25 by mistake without
waiting for the review, let's put everything on a single follow up PR
based on the new main branch that already have PR #25 merged."

The user's decisions (2026-10-13): everything in this one PR, and
option (a) of each of the review summary's six menus:

1. Windows scenario 3's OpenMP packages are also built as packages
   through rzig build (A2).
2. The global cache key is fixed (sources named relative to src/), with
   a test that installs a tarball twice (A1).
3. The PR gets the `upstream-zig` label (C3; nothing to code).
4. NM_FILTER as CRAN's: build.zig substitutes upstream's
   (`| $(SED) -e '/[.]refptr[.]/d' -e '/[.]weak[.]/d'`, as R's
   src/gnuwin32/fixed/Makefile writes it into etc/Makeconf) into
   Makeconf.win, and `rzig def` stops exporting `.refptr.` and `.weak.`
   names, so both paths match CRAN (C2).
5. A tier-2 package whose plan needs make fails, exit 1, with a clear
   line, instead of going to make (C1).
6. The later items, C4 to C7, in this same PR.

The plan PR #25 implemented, for background: feat-zig-pkg-build's
`consolidation/CONSENSUS.md`.

## The review

`review/` beside this file holds REVIEW-SUMMARY.md and REVIEW.md,
byte-identical copies of the phase 3 session's review (as
feat-zig-pkg-build's `consolidation/` holds its CONSENSUS.md and
FINDINGS.md, its R2). It read 5416d8d (the merge 47e8436, the Windows
test fix 45892fb and the stress follow-up 5416d8d) from five angles,
and an adversarial verifier checked every finding: 51 confirmed, 3
refuted (tests-T9, records-REC-13, stress-S7; nothing done for them).
An id names its angle: phase3-P3-n (phase 3's interfaces), preflight-PF-n
(the preflight and the hook), tests-Tn, records-REC-n and stress-Sn.
REVIEW-SUMMARY.md groups them as A1-A4 (code, meant for before the
merge), B1-B9 (the stress follow-up and the records) and C1-C7 (later
items); REVIEW.md has each finding with its file:line evidence at
5416d8d, the fix and the verifier's note. Code comments and the records
cite the ids in brackets. The second review's ids (code-2 to code-6,
tests-SIGPIPE-1, tests-T7-source-operand, coverage-1, coverage-3) exist
only in this file.

## Interfaces fixed up front

Every part of the work used these exact texts:

- I-T11, 0009's two stops [tests-T11]: "this package needs the r-zig
  toolchain (compiled code or a configure script), which is incomplete
  (see above)", and "this package needs the r-zig toolchain (compiled
  code or a configure script), which is not installed: <hint>" (the
  R_ZIG_TOOLCHAIN_HINT as before). An R-only package with a configure
  script stops there too, which "has compiled code" got wrong.
- I-C1, a tier-2 package whose plan needs make [preflight-PF-1]: `rzig
  build` (the hook, and `--classify`) and `--rzig-check=package` print
  "<pkg>: src/build.zig cannot be built by make: <reason>" and exit 1
  (not 3, not 127). The MAKEFLAGS assignment check does not apply to
  tier 2: there is no make build to differ from.
- I-PF5, flang [preflight-PF-5, records-REC-11]: tier 2 never (rpkg
  compiles C and C++ only); with `R_ZIG_CONFIGURE=1`, src/'s top level
  in either case, whatever the tier, as CONSENSUS B agreed; tier 1 by
  the plan's sources and tier 3 by the top-level match, as before. For
  tier 2 this departs from CONSENSUS B ("plan().sources has f or f9x
  (tiers 1-2)"), and feat-zig-pkg-build's "Known differences" says so.
- I-PF4, patch 0013 [preflight-PF-4]: `R_ZIG_PKG_BUILDER=zig` with no
  rzig in R_HOME/bin/toolchain stops: "R_ZIG_PKG_BUILDER is 'zig' and
  R_HOME/bin/toolchain has no rzig".
- I-B1, the stress cache [stress-S1, records-REC-4]: stress.R
  `--no-shared-cache` leaves ZIG_LOCAL_CACHE_DIR unset, so each install
  through rzig build has its own cache and compiles its build runner;
  stress.yaml's boolean input `shared_cache` (default true) passes it;
  report.md and report.json record it, and R_ZIG_PKG_BUILDER [tests-T12].

## What changed

### A: code meant for PR #25

- **A1 [tests-T1, records-REC-2], the global cache key (menu 2).** zig
  cc keys its object cache, zig's global cache, on the source path as
  it is given. build_t1.zig passed the absolute path, under install.R's
  new R.INSTALL directory, so every tarball install (install.packages'
  way) added one entry per source, never reused: cli, 26 per install.
  make passes `-c one.c` from src/ and reuses its entries. compileAll
  now passes the source relative to the run's cwd, already src/
  (`addArg(s.path)`), with the file as the step's input
  (`addFileInput`); the link passes a package's `-win.def` the same way.
  rpkg.zig and build_t2.zig compile through it, so tier 2 has the fix
  too. pkg-parity installs cli's tarball twice and fails if the global
  cache's `o/` count changes; it also asserts that no traced compile
  names an absolute source ("The fixes' own review",
  tests-T7-source-operand). The records' "nothing per install outlives
  it" is corrected in feat-zig-pkg-build's PLAN.md (N3, fact 9,
  Measurements); its N3 correction also says CONSENSUS D's "keyed by
  target, bounded" was wrong until this fix, and leaves the
  `consolidation/` copy as it was agreed (R2), as `review/` here is
  left byte-identical.
- **A2 [phase3-P3-1, records-REC-1, tests-T3], Windows OpenMP packages
  (menu 1).** verify-bundle's Windows scenario 3 also installs omp, lomp
  and, where Makeconf offers them, fomp and fompfc through `R CMD
  INSTALL`: a DESCRIPTION, useDynLib and the same Makevars, under
  `env -i` with the decoy CONDA_PREFIX, scenario 3's PATH (bin\x64,
  the build tools, System32; flang too for Fortran) and RZIG_TRACE=1.
  Each asserts `rzig build: tier 1`, no recipe make echoed, zig-fc's
  link for fompfc, the libomp.dll import, no import library in src/ or
  the installed package, no src/.rzig left, and loads and runs with
  PATH = bin\x64 + System32. The script's header claim is now true.
- **A3 [tests-T2], test-toolchain.R's make references.** make_ref sets
  RZIG_TRACE=1 with R_ZIG_PKG_BUILDER=make (both unset on exit), needs
  no `rzig build:` line, and needs a compile make echoed
  (`^[^ ]*/bin/toolchain/(zig-cc|zig-cxx|zig-fc|gcc|g\+\+)`). rzigar
  installs through install_log and asserts `rzig build: rzigar needs
  make: `.
- **A4 [phase3-P3-2, preflight-PF-6], stale headers.** check.zig's
  header describes 0009's one `--rzig-check=package` call (R CMD config
  calls `=build-tools`), package()'s exit 2 cases (R_HOME unset, R_HOME
  or the working directory not resolvable) and the new exit 1;
  canonical()'s failure line lost its `build:` prefix. main.zig's
  header (with `rzig build` and `rzig def`), fortran.zig's and
  groups.zig's list of the places that print a group's text (now with
  `rzig build`) likewise. check.zig and 0009's header say "four inputs
  differ" [preflight-PF-7].

### B: the stress follow-up and the records

Each as REVIEW.md's entry asks; the records changed are
feat-zig-pkg-build's PLAN.md and feat-standalone-toolchain's PLAN.md and
TODO.md.

| item | what the records say now, and where |
|---|---|
| B1 [stress-S1, records-REC-4] | The shared tier-1 build runner is open again: TODO.md "Depend less on make", and the later items of feat-zig-pkg-build's scope statement (N2) and re-scope. The dispatch shared one zig build cache (stress.R pointed ZIG_LOCAL_CACHE_DIR at its run), so it never measured the per-install runner cost. Recorded: fact 9's about +3.1 s per tier-1 install on linux-64, this PR's 2 to 2.9 s (conda-forge zig) and 1.1 to 1.3 s (upstream zig) ("Measurements"), and the consolidation's host figures (6 to 10 s on omicron, 11 to 20 s on kappa). Decided by a dispatch with `shared_cache = false` (I-B1) |
| B2 [stress-S2] | Both PLANs: "the stress table adds no evidence on B24; the dlltool/as follow-up PR stands", no "no tool to move". TODO.md's B24 item: no dlltool, windres, objdump or strip in make's echoed recipes, which shows little (binutils calls are not traced, configure.win and `@`-recipes run silently, R CMD check did not run), and RcppParallel's TBB build ran windres through Rcmd_environ's `RC`, unseen |
| B3 [stress-S3, records-REC-8] | The tools the Windows make rows ran, from the recipes and the packages' messages, not word counts: winshlib.mk's silent def and link recipe (nm, sed twice, basename, echo, rm) in every make row; the configure.win scripts under sh; pkg-config in at least 9 rows; rzig's AR/RANLIB in 12 and 2; rm echoed in 5; cmake in Rhdf5lib and RcppParallel. The old counts (sed in 5, cmake in biocmake, cp/mkdir) matched words such as "used" and a package's name. The binutils stay in TC/binutils/, not usr/bin |
| B4 [stress-S6, records-REC-9] | g3 g4 have no smoke that compiles at run time (Rcpp only a dependency, its smoke `TRUE`), so the `R CMD SHLIB` command (run-time compilation, pkgbuild's probe) was not exercised; contract's evalCpp and verify-bundle's SHLIB shapes cover it. In the "Not measured" list; a g1 dispatch with trace is a TODO.md item. Found here: a smoke log would not show it anyway (a local `stress.R --trace Rcpp` compiled and ran cppFunction, and its smoke log has no rzig line: sourceCpp keeps R CMD SHLIB's output) |
| B5 [stress-S8] | "a Makevars rule (src/Makevars, .win or .ucrt) (9)", with jsonlite, Matrix, rlang and timechange on plain src/Makevars; the status sentence names configure scripts, Makevars rules and (Windows) `$(shell)`, conditionals and an include |
| B6 [records-REC-12, tests-T5] | stress/packages.tsv: fst (fstcore through make: configure, Makevars.ucrt's include on Windows), geos (libgeos make on Windows), lme4 (Matrix make; nloptr make on unix, tier 1 on Windows); the g1 rows' notes say they come from a linux `rzig build --classify`, not a dispatch |
| B7 [stress-S4, S5, phase3-P3-8] | On ubuntu-latest the tier-1 rows ran at about the same ratio to the 548da1a make reference as the make rows (0.67 against 0.65): no measurable builder difference with a shared cache; runner variance explains the rest. sys carries the one runner compile per cache: 5 to 15 s on four legs, about 35 s on macos-15-intel, inferred from sys against the reference and the next warm tier-1 row (not "a cold global cache": curl warmed it first) |
| B8 [stress-S9] | Rhdf5lib compiles HDF5 through its configure script, CMake and make: the rows needing the group are 31 of 47 on unix and 30 of 47 on Windows |
| B9 [records-REC-6, stress-S10] | "not needed by tier 0 to 2 installs without a configure script R runs", in all three records; cleanup.ucrt/cleanup.win under `--clean` or `--preclean`; R CMD check's objdump (Windows); an Objective-C source and an `include` among the tier-3 reasons |

### C: the later items (menu 6)

- **C1 [preflight-PF-1], a tier-2 package whose plan needs make (menu
  5).** It went to make, which ignores build.zig: the install failed
  late ("shared object not found"), or, with a C file beside build.zig,
  installed a partial library with no error. pkgbuild.zig's
  `buildZigNeedsMake` gives I-C1's line and exit 1 in the hook, in
  `--classify` [coverage-1] and in the preflight; pkgplan.zig skips the
  MAKEFLAGS check for tier 2. A tier-1 package with the same reason
  still exits 3. Tests: unit (pkgbuild, check, pkgplan), parity-test
  cases for the check and `rzig build`, and pkg-parity: zighello under
  `MAKEFLAGS='-- X=1'` builds as tier 2, and with `CC = ccache cc` in a
  user Makevars fails with the line, no "needs make" line, no recipe
  make echoed and no src/.rzig left.
- **C2 [records-REC-3], NM_FILTER (menu 4).** CRAN's installed Makeconf
  filters `.refptr.` and `.weak.` names out of the make path's .def
  (MkRules.rules:113 sets the default, fixed/Makefile:48 writes it,
  winshlib.mk applies it); this tree's Makeconf.win kept the vendored
  template's empty `NM_FILTER =` since 174c952, and the consolidation
  made `rzig def` match that gap. Now Makeconf.win's line is
  `NM_FILTER = @NM_FILTER@` (the token form the file uses for R_ARCH,
  FLIBS and IMPDIR), build.zig's installWindowsCompilerContract
  substitutes CRAN's value, def.zig drops every name containing
  `.refptr.` or `.weak.` (its unit fixture: 5 names), and verify-tree
  asserts Makeconf's line on Windows. feat-zig-pkg-build's def.zig
  rationale and M5's "185" are corrected.
- **C3 [phase3-P3-10], upstream zig (menu 3).** The upstream-zig legs
  never ran on PR #25 (only `full-ci`). This PR is to get the
  `upstream-zig` label. Ahead of CI, kappa and omicron ran rzig build,
  tier 2 with `--system` and pkg-parity's argv comparison under upstream
  zig ("Tested").
- **C4 [phase3-P3-9], scenario 2 on Windows.** pfC installs through
  rzig build with PATH = bin\x64 + System32 and zig through ZIG_BIN: its
  own per-install cache, no build root left, loaded. pfM stops with
  rzig's reason ("pfM needs make: src/Makevars has a rule or target
  line: '$(SHLIB): lib/libval.a'; no make on PATH"), the build tools'
  text and 0009's stop. pfF and pfG stay unix-only. No flang on that
  PATH, unlike the review's suggested fix: pfC is C only, as on unix,
  and the env's Library/bin would bring its other tools in.
- **C5, tests.**
  - [tests-T6] verify-helpers.sh `make_recipes`: a make path's log is
    told by the compiles make echoed (`tr -d '\r'`, then
    `^[^ ]*/bin/toolchain/(zig-cc|zig-cxx|zig-fc|gcc|g\+\+)`), not by a
    `^make` line no successful build prints. pkg-parity, verify-bundle
    and wheel-test use it, the make paths positively.
  - [tests-T7] argv_of drops CRs, filters `--version` only as a word,
    and keeps each path's flag prefix (`-I`, `-L`, `-Wl,...`, `--opt=`)
    with its file name; on the existing linux logs it gives the same
    sets as before.
  - [tests-T8] shape_pkg installs with RZIG_KEEP_ROOT=1 and checks the
    macOS floor on each object in the kept build root, then removes it;
    the decoy loop installs the OpenMP shape through rzig build too.
  - [tests-T4] stress.R's toolchain pattern no longer matches `rzig
    build: zig build failed`, which follows every failed compile: a
    missing header classes as sysdep, a package error as package.
  - [tests-T11] I-T11 in 0009, verify-bundle's `$preflight_stop`,
    test-preflight.R, wheel-test.sh and stress.R's classifier (both
    wordings).
  - [tests-T12] `pixi run rzig-test <R-prefix>` runs smoke-test.sh
    (part 2: packages through that tree's R CMD INSTALL, rzig build) on
    linux after the unit and parity tests; stress's report records the
    builder (I-B1).
  - [tests-T10, phase3-P3-3, P3-4] wording: pkg-parity's no-make PATH
    ("no make on PATH (unix: sh, zig and flang only)"); verify-bundle's
    cf shape installs with the tree's bin alone, so "no make on PATH"
    holds; wheel-test counts rzig's commands (3), not its trace lines
    (9); pixi.toml's contract line (pak mixed).
- **C6, the preflight and the hook.**
  - [preflight-PF-2] `R_MAKEVARS_USER` and `R_MAKEVARS_SITE` set but
    empty mean no file, as R's `Sys.getenv(, NA)` reads them. `~` on
    Windows follows R_ExpandFileName: R_USER, then HOME, then
    HOMEDRIVE and HOMEPATH; unix uses HOME (and see code-5 below).
  - [preflight-PF-3] once the build root exists, a `defer` removes it on
    every return, unless `--keep-root` or RZIG_KEEP_ROOT: the URL
    refusal, no zig and the failures in between no longer leave
    src/.rzig in a package's source tree.
  - [preflight-PF-4] I-PF4 in 0013's no-rzig branch. Its comment no
    longer says "zig (never make)": zig is an error where the hook would
    hand the package to make; a src/Makefile package never reaches the
    hook.
  - [preflight-PF-5, records-REC-11] I-PF5 in check.zig, recorded in
    feat-zig-pkg-build's "Known differences" as a departure from
    CONSENSUS B for tier 2.
  - [preflight-PF-8] parity-test cases with `RZIG_OS=windows` and no
    binutils: configure.win, configure.ucrt and `R_ZIG_CONFIGURE=1`
    stop with exit 127 and the exact line; a tier-3 top-level `.F` asks
    for flang; pkg-parity's URL refusal leaves no root; one cli install
    with ZIG_LOCAL_CACHE_DIR set puts its cache there.
  - [phase3-P3-6] verify-bundle's zig_env no longer passes
    ZIG_LOCAL_CACHE_DIR and contract-test.sh unsets it, so their
    installs use the per-install cache a user's install gets; pfC
    asserts `--cache-dir <...>/.rzig/zig-cache` and no root left.
- **C7, the records.** [records-REC-5] the N7 record; [phase3-P3-7,
  records-REC-7] N5's note under phase 4's bump in TODO.md, naming 0009
  and rzig's new modes and the coupling (a new r-zig-slim with an older
  r-zig-toolchain stops every compiled install; no channel mixes a
  locally built `_8` with universe's `_8`); [records-REC-10] fact 5
  (the tier-3 checks pass on the compile tree), "merged 2640" (2664
  with this PR's patches: feat-zig-pkg-build's facts say so), fact 9
  cites FINDINGS' channels-C5, and omicron's Rcpp numbers are marked
  not recorded (no log of them survives); [records-REC-14] the
  consolidation copies' line citations of CONSOLIDATION.md and
  HANDOFF.md, never committed; [preflight-PF-7] ten parity-test cases
  (real binary, linux), four inputs differ, fact 5; [phase3-P3-5] the
  compile tree's users name pkg-parity (compile-tree.sh, env.sh,
  pixi.toml, verify-tree.sh [coverage-3]); [phase3-P3-8] TODO.md's
  timing; [records-REC-3] the def.zig rationale (C2).

## The fixes' own review

An adversarial verifier read the fixes on this branch (2026-10-13) and
confirmed nine more findings; all are fixed, and the linux-64 chain ran
again after them:

| id | finding | fix |
|---|---|---|
| code-2 | classify put src/build.zig before src/Makefile, but install.R runs a src/Makefile (Windows: Makefile.ucrt, then Makefile.win) with make and never reaches the hook, so the preflight skipped the build tools | a Makefile wins over build.zig (tier 3, reason `src/Makefile`); build.zig still wins over configure and the Makevars; a configure script is still reported first. Unit cases (a plain Makefile is ignored on Windows) and a `--classify` parity case; the tier wording in pkgplan.zig, 0013 and feat-zig-pkg-build's tier table |
| code-3 | a stray `.m` in a tier-2 package ended in "no source for x.o", now exit 1 | tier 2 skips an object with no C, C++ or Fortran source instead of needing make; unit case: build.zig + bridge.m + a.c plans a.c |
| code-4 | rpkg.zig said Makevars' PKG_CPPFLAGS and PKG_CFLAGS apply to `c_sources`; tier 2 never reads src/Makevars | the comment, and feat-zig-pkg-build's tier table and step 5, say so; an optional `cflags` in LibraryOptions is a TODO.md item, for when a package needs it |
| code-5 | unix `~` with HOME unset or empty: R falls back to the passwd home, rzig found no user Makevars | 0013's hook passes R's makevars_user() as `R_MAKEVARS_USER` when it names a file, and restores the caller's value after (not set to empty when R finds none: Windows cannot hold an empty variable, and rzig's lookup then finds none either) |
| code-6 | a C1 stop in the preflight is followed by 0009's "incomplete (see above)", which is wrong there | the least disruptive option, I-T11 and I-C1 unchanged: the preflight adds "<pkg>: the r-zig toolchain is complete: change what the line above names"; stress.R classes such a row `package` and starts its failing text at rzig's line ("Open decisions") |
| tests-SIGPIPE-1 | `tr -d '\r' < log \| grep -q` under pipefail can fail when grep exits first (pkg-parity's ZIG_LOCAL_CACHE_DIR check, two in verify-bundle) | grep the file, or let grep read to the end (`> /dev/null`) |
| tests-T7-source-operand | argv_of cuts every path to its file name, so an absolute `-c` operand (A1) compares equal | pkg-parity's `abs_sources`: no traced zig-path compile names an absolute source, for each tier-1 package and the tarball's second install |
| coverage-1 | `rzig build --classify` printed `make`, exit 0, for a C1 package | I-C1's line and exit 1, nothing on stdout; unit and parity cases |
| coverage-3 | verify-tree.sh's list of what leaves the tree as it was omitted pkg-parity | named |

## Measurements

### zig's global cache, a tarball installed again (A1)

cli_3.6.6's tarball installed three times, each into a fresh library,
with a fresh zig global cache per builder; `o/` entries after each
install. linux-64 (gamma), the compile tree:

| | main 07e12c0 | this PR | this PR, upstream zig |
|---|---|---|---|
| rzig build | 54, 80, 106 | 54, 54, 54 | 54, 54, 54 |
| make | 52, 52, 52 | 52, 52, 52 | 52, 52, 52 |

Traced compiles: main passed `-c /.../R.INSTALLxxxx/cli/src/vtparse_table.c`,
this PR passes `-c ansi.c -o <root>/zig-cache/o/<h>/ansi.o`, and make
`-c ansi.c -o ansi.o`. The same experiment on omicron (osx-arm64, a
copy of the compile tree per variant): main's build_t1.zig 28, 54, 80
(26 absolute `-c /...` compiles per install, ansi.o in 3 entries), this
PR's 28, 28, 28 (ansi.o in one), so pkg-parity's new check fails on the
old code there too. pkg-parity's tarball twice, before and after the
second install: linux 489 (upstream zig 168), omicron 479 (205), kappa
1837 (1730).

### Per-install time

linux-64, zig's global cache warm, each install with its own fresh
per-install cache (the default, ZIG_LOCAL_CACHE_DIR unset), so each
install through rzig build compiles its build runner (N3); seconds per
install, three installs (cli: the second and third):

| package | rzig build, main | rzig build, this PR | make | upstream zig: rzig build / make |
|---|---|---|---|---|
| quadprog | 5.4, 5.6, 5.6 | 5.4, 5.4, 5.3 | 2.5 | 3.6-3.7 / 2.4 |
| digest | 6.8, 6.4, 6.5 | 5.7, 5.5, 5.6 | 3.3 | 3.6-3.7 / 2.3-2.4 |
| cli | 11.0, 11.3 | 10.4, 10.6 | 8.5 | 8.4-8.6 / 7.4 |

So the runner costs 2 to 2.9 s per tier-1 install with conda-forge's
zig and 1.1 to 1.3 s with upstream's (fact 9's estimate was 3.1 s).
digest and cli install faster than on main: their C objects now come
from zig's global cache, as make's do. On kappa's pkg-parity
(conda-forge zig) rzig build took 1.5 to 3 times make's time (cli 30
against 18 s, digest 17 against 6, Rcpp 19 against 9), as in the
consolidation's runs. Not measured: the stress runners (a dispatch with
`shared_cache = false`, TODO.md).

### NM_FILTER (C2, kappa)

The installed etc/x64/Makeconf:59 reads `NM_FILTER = | $(SED) -e
'/[.]refptr[.]/d' -e '/[.]weak[.]/d'`. No `.refptr.` or `.weak.` name
is exported by either builder for cli, digest, Rcpp or quadprog, under
both zigs: cli exports 186 names (195 in the consolidation's kappa run,
9 of them `.refptr.` stubs), Rcpp 738 (744). A two-file OpenMP package
whose objects carry `.refptr.shared_var` and
`.weak.weak_fn.default.exported_fn` (nm shows them) exports exactly
exported_fn, nmfn and shared_var from both builders, imports libomp.dll,
and `nmfn()` gives 3 on each.

## Tested

Every host: pixi.lock sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96,
unchanged before and after, every task `--locked`; the slim (default)
environment and conda-forge zig 0.16.0 unless named; upstream zig is
PyPI's ziglang 0.16.0 from `pixi run fetch-zig`, as ZIG_BIN. The hosts
ran the tracked diff with sha256
daa491ba0a97b2d13b0b37b8996a3a025b873e52584cb9d457616e6c9f91bb13
(`git diff | sha256sum`, 35 files) plus `review/`; afterwards only the
records changed, and `review/` moved here from feat-zig-pkg-build/.
Logs: zpb-review/{linux,fix,kappa,omicron}/ under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/.

### linux-64 (gamma)

A first chain before the fixes' own review (zpb-review/linux/), then
the same again after it (zpb-review/fix/, chain.status ALL DONE;
toolchain-test and actionlint in the first only):

| what | result |
|---|---|
| `rzig-test`, conda-forge and upstream zig | 126/126 unit tests; parity-test 108 identical, 59 identical but for rzig's own -L, object or import library, 34 deliberate, 0 failed, with the new `--rzig-check=package`, `--classify` and Makefile cases |
| `rzig-test dist/slim/R-4.6.1-zig` | the same, then smoke-test.sh part 2: rzc, rzcxx, rzomp, rzf through rzig build (`rzig build: tier 1`), loaded [tests-T12] |
| `toolchain-test`; slim: `build` (a fresh R source; the 13 patches apply with no fuzz), `toolchain`, `verify-tree`, `verify-toolchain`, `smoke`, `compile-tree`, `contract`, `hermetic`, `package-toolchain`, `verify-package` | pass. verify-package: pfC through rzig build with its per-install cache and no root left; pfM, pfF and pfG stop with the I-T11 text; the shapes' objects checked in the kept root; cf with the tree's bin alone; the decoy CONDA_PREFIX on the OpenMP shape through rzig build |
| `pkg-parity`, both zigs | pass: cli, digest, quadprog, Rcpp and minqa give identical exports (185, 127, 6, 642, 187) and rzig command lines (27, 20, 6, 7, 19); no absolute source; the tarball twice adds nothing; ZIG_LOCAL_CACHE_DIR; zighello tier 2 under `MAKEFLAGS='-- X=1'`, the ccache user Makevars' I-C1 failure; the URL refusal leaves no root; tier 3; quadprog on the base with no make |
| minimal: `build`, `toolchain`, `verify-tree`, `contract`, `package-toolchain`, `verify-package` | pass |
| wheel: `wheel`, `wheel-test` | pass: the console-script install through rzig build under PyPI ziglang (3 rzig commands), the 0009 "not installed" text with the pip hint, the bundled bin/R install through make (make's echoed compiles) |
| pkg: `conda-package` (output in scratch) | pass: r-zig-slim and r-zig-toolchain 4.6.1 build 8; test-toolchain.R's make runs asserted from their traced logs, rzigar's "needs make", test-preflight.R's I-T11 text |
| `stress.R --trace --no-shared-cache Rcpp`, local, the compile tree | ok: `--cache-dir <build root>/zig-cache`; report.md "Builder auto (R_ZIG_PKG_BUILDER); zig build cache per install (--no-shared-cache)", report.json `builder` and `shared_cache` |
| actionlint; shellcheck `-S warning` on the changed scripts; `bash -n`; `zig fmt --check`; R parses stress.R and the recipe tests; the patch series on the pristine tarball | no output; no new warning; clean; no offset or fuzz |

### osx-arm64 (omicron, macOS 26.4.1)

rsync of the worktree to a scratch copy, 2026-10-13. Pass: `rzig-test`
(126/126, both zigs), `toolchain-test`, `build` (111 s, flang-zig),
`toolchain`, `verify-tree` (63 Mach-O files at minos 13.0 or lower),
`compile-tree`, `contract` (quadprog and Rcpp through rzig build, ps
"needs make: a configure script"; compiles name their source relative
to src/), `pkg-parity`, `package-toolchain`, `verify-package`.
pkg-parity: identical exports and command lines for cli, digest,
quadprog, Rcpp and minqa (Rcpp 228 exports, 7 lines); rzig's
`ZIG_LIB_DIR=<mirror>` prefix on 27 zig-path and 28 make-path lines
(the extra one the filtered `--version` probe) is stripped, none left
in the argv files, and BSD sed gives the same as GNU sed; the
ZIG_LOCAL_CACHE_DIR, tier 2, URL, MAKEFLAGS and ccache (I-C1) cases;
quadprog on the base with PATH = flang, sh, zig. verify-package: pfC
with the per-install cache, the I-T11 stops, the shapes' objects in the
kept root against the macOS floor (T8), the OpenMP decoy through rzig
build. With upstream zig (R rebuilt with it): `build`, `compile-tree`,
`pkg-parity` pass, no ZIG_LIB_DIR prefix, the cache flat at 205.

### win-64 (kappa, Windows 11 22621)

tar copy of the worktree (its manifest the same at the end). Pass with
conda-forge zig: `rzig-test` (99 passed, 27 skipped), `toolchain-test`,
`build` (6 min 50 s), `toolchain`, `verify-tree` ("CRAN's layout
verified: Makeconf's R_ARCH = /x64 and NM_FILTER"), `verify-toolchain`,
`compile-tree`, `contract` (Rcpp, quadprog: rzig build; data.table,
minqa, ps: make; pak mixed, keyring "needs make: a configure.win
script"), `pkg-parity`, `hermetic`, `package-toolchain`,
`verify-package`, `conda-package` (10 min 47 s; both tests pass, with
the make paths asserted and the I-T11 "not installed" text). With
upstream zig: `rzig-test`, `build` (5 min 51 s), `verify-tree`,
`contract`, `pkg-parity`, `verify-package`, then `build` again with
conda-forge zig.
- pkg-parity: cli 186 exports / 27 command lines, digest 129/20,
  quadprog 2/6, Rcpp 738/7, identical on both builders; the tarball
  twice adds nothing; ZIG_LOCAL_CACHE_DIR; zighello tier 2
  (`hello(21L)` = 42) with `--system`; the URL refusal leaves no root;
  MAKEFLAGS and ccache as I-C1 says; tier 3 to make; quadprog on the
  base with flang and System32 only.
- verify-package: scenario 2's pfC and pfM on Windows (C4), and
  scenario 3's omp, lomp, fomp and fompfc as tier-1 packages (A2), each
  importing libomp.dll and loaded with PATH = bin\x64 + System32.
- Probes: I-C1 through the preflight (CC = ccache in R_MAKEVARS_SITE):
  rzig's two lines, then 0009's I-T11 stop, nothing installed, no make
  path; the same through the hook with R_ZIG_NO_PREFLIGHT=1; `rzig
  build` and `--rzig-check=package` exit 1 and leave no src/.rzig; a
  MAKEFLAGS assignment on tier 2 installs. I-PF4: a copy of the base
  with an empty bin/toolchain, `R_ZIG_PKG_BUILDER=zig` and
  R_ZIG_NO_PREFLIGHT=1 stops with "ERROR: R_ZIG_PKG_BUILDER is 'zig'
  and R_HOME/bin/toolchain has no rzig for package 'pf4'". NM_FILTER:
  "Measurements".

The hosts' scratch copies (omicron ~/rz-zpb, kappa
C:\Users\admin\rz-zpb and rz-zpb-env) were removed after the round.

### CI

To come on the PR, with the `full-ci` and `upstream-zig` labels: the
five platforms' full tier and the five upstream-zig legs, the first
upstream-zig run of rzig build, tier 2 and pkg-parity in CI.

## Not tested

- code-5's passwd-home case end to end: it needs a file in the real
  ~/.R, outside the worktree. pkg-parity's R_MAKEVARS_USER cases pass
  with the change, and kappa's installs ran through it.
- smoke-test.sh part 2 in CI: `rzig-test` gets no R prefix there (it
  runs before R is built); it ran here on linux-64 only.
- linux-aarch64 and osx-64 on a host (CI's legs).
- A stress dispatch on the five runners (the shared runner decision and
  the g1 run-time compiles, TODO.md).

## Open decisions (for the user)

1. The stop for a tier-2 package that make cannot build, in the
   preflight (code-6). Today: rzig's "<pkg>: src/build.zig cannot be
   built by make: <reason>", then "<pkg>: the r-zig toolchain is
   complete: change what the line above names", then 0009's fixed
   I-T11 stop "...which is incomplete (see above)", which still reads
   as a contradiction (kappa's tester said so too). No CRAN package has
   src/build.zig.
   - (a) ★ Keep it for this PR (tested on three hosts); 0009 telling
     exit 1 from 127 becomes a later item.
   - (b) Drop the extra line: rzig's line, then 0009's stop, as PR #25
     had it.
   - (c) Now: 0009 stops with its own text when the check exits 1
     ("this package cannot be built (see above)"), a change to I-T11,
     the patch series and every host's chain.
2. The review's copy in the repository (`review/`, about 214 KB).
   - (a) ★ Commit it, as feat-zig-pkg-build's `consolidation/` (R2), so
     the [id] citations in code and records can be checked.
   - (b) Leave it out; the ids then point to the review summary only.

## Follow-ups (not on this branch)

In feat-standalone-toolchain TODO.md unless named:

- The shared tier-1 build runner: a stress dispatch with
  `shared_cache = false` on the five runners decides it [stress-S1,
  records-REC-4].
- A g1 dispatch with trace (Rcpp's cppFunction, rstan's stan_model):
  run-time compilation; the smoke's result is the evidence [stress-S6].
- Tier 2's own compile flags (an optional `cflags` in rpkg's
  LibraryOptions), when a zig package needs them [code-4].
- Route `R CMD SHLIB` through rzig build, or give it a preflight;
  revisit 0010 for pkgbuild's probe (as before).
- With open decision 1 at (a): 0009 tells the check's exit 1 (a package
  that cannot be built) from 127 (the toolchain incomplete) and words
  its stop for each.
- Not recorded elsewhere, small: omicron's tester notes that argv_of
  keeps `-I` and `-L` but not `-F`, so rzig's fixed
  `-F<SDK>/System/Library/Frameworks` compares as `Frameworks` on both
  paths (`(-[IL]|` to `(-[ILF]|` in pkg-parity.sh, untested);
  `R_ZIG_PKG_BUILDER=zig` does not refuse a src/Makefile package, which
  install.R sends to make without asking the hook (PF-4's verifier);
  0009's header does not mention code-6's extra line (check.zig's
  does); `rzig def` and Makeconf.win's NM_FILTER should stay in step if
  either changes.

## Files

- rzig (zigbuild/tools/rzig/): check.zig, pkgbuild.zig, pkgplan.zig,
  def.zig, main.zig, fortran.zig, groups.zig; parity-test.sh,
  smoke-test.sh, test.sh.
- rpkg (zigbuild/rpkg/): build_t1.zig, rpkg.zig.
- R's patches (zigbuild/patches/R-4.6.1/): 0009, 0013, regenerated
  against the pristine tarball (no offset or fuzz).
- Windows Makeconf: zigbuild/config/win-x86_64-full/Makeconf.win;
  build.zig (NM_FILTER).
- Tests: scripts/pkg-parity.sh, verify-bundle.sh, verify-helpers.sh,
  verify-tree.sh, wheel-test.sh, contract-test.sh; recipe/test-toolchain.R,
  test-preflight.R.
- Comments only: scripts/compile-tree.sh, env.sh; pixi.toml;
  recipe/recipe.yaml.
- stress: stress.R, README.md, packages.tsv; .github/workflows/stress.yaml.
- Records: this file and `review/`; feat-zig-pkg-build/PLAN.md;
  feat-standalone-toolchain/PLAN.md and TODO.md.

## How to rerun

    pixi run rzig-test                          # unit tests, parity-test (linux)
    ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test   # the same with upstream zig
    pixi run rzig-test dist/slim/R-4.6.1-zig    # also smoke-test.sh on that tree (linux)
    pixi run pkg-parity                         # the tarball twice, I-C1, ZIG_LOCAL_CACHE_DIR, the base with no make
    pixi run verify-package                     # scenario 2 (Windows too), scenario 3's OpenMP packages
    Rscript stress/stress.R --trace --no-shared-cache Rcpp   # with the compile tree's R; per-install cache
    gh workflow run stress.yaml -f packages='g3 g4' -f trace=true -f shared_cache=false
