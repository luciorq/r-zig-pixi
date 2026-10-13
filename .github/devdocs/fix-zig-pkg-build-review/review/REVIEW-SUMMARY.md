# PR #25 review: summary

2026-10-13, the phase 3 session, read-only, of PR #25 at 5416d8d
(47e8436 merge + 45892fb + the stress follow-up 5416d8d). Five angles,
every finding checked by an adversarial verifier: 51 confirmed, 3
refuted. Full text with evidence and verifier notes: REVIEW.md beside
this file (ids in brackets).

Most of the merge is right: the phase 3 interfaces hold (rzig_names with
rzig/rzig.exe and no extensionless names on Windows; share/zig/rpkg in
the base; the toolchain tree, compile-tree and task graph; stress.yaml's
C3 and C4; build-r.yaml's order; recipe build 8 and its selectors;
make-wheel.py), the preflight and hook follow CONSENSUS B (one decide()
shared by check and hook, R_ZIG_C_STD/R_ZIG_CONFIGURE around one
system2 to CC's path, MAKEFLAGS options vs assignments, tier-2 URL
refusal with --system, per-install --cache-dir), and CI 38305799627 is
green with the new assertions actually running.

## A. Code, before merge

- A1 [tests-T1, records-REC-2] The global zig cache grows per tarball
  install: build_t1.zig:83 passes an absolute source path
  (`plan.srcdir/s.path`, a new R.INSTALL dir each install), so zig cc
  keys a new object entry per source per install; make passes `-c
  one.c` and reuses its entries. Measured: cli +26 entries per install
  through rzig build, 0 through make. Fix: pass `s.path` relative to the
  cwd (already srcdir) plus addFileInput; pkg-parity installs the cli
  tarball twice (or two copies in different dirs) and asserts the o/
  count unchanged (fails today); correct PLAN's N3 and Measurements.
- A2 [phase3-P3-1, records-REC-1, tests-T3] Checklist G's "likewise
  Windows scenario 3's OpenMP packages" is not done (only R CMD SHLIB),
  while verify-bundle.sh:62-63 says they are also built as packages
  through rzig build. Menu 1.
- A3 [tests-T2] recipe/test-toolchain.R make_ref's builder check is
  hollow: RZIG_TRACE is unset before each make_ref, so "no `rzig build:`
  line" holds whichever builder ran. Set RZIG_TRACE=1 inside make_ref
  (on.exit unset) or assert a positive make marker
  (`^\S*bin/toolchain/(zig-c|gcc|g\+\+)`); assert rzigar's
  `rzig build: rzigar needs make: `.
- A4 [phase3-P3-2, preflight-PF-6] Comments still describe phase 3's
  two-step 0009: check.zig:1-10 and 50-51 (exit 2 cases of package()),
  main.zig:27-29, fortran.zig:44-45.

## B. The stress follow-up and the records, before merge

- B1 [stress-S1, records-REC-4] The shared tier-1 runner item is closed
  on data that cannot decide it: the dispatch shared one cache
  (stress.R points ZIG_LOCAL_CACHE_DIR at the run dir), so the
  per-install runner cost was never measured. Reopen it in TODO.md and
  in PLAN's later items; record fact 9's estimate (about +3.1 s per
  tier-1 install on linux-64) and decide with a dispatch that leaves
  ZIG_LOCAL_CACHE_DIR unset.
- B2 [stress-S2] "no tool to move" (feat-standalone-toolchain
  PLAN.md:2614, feat-zig-pkg-build PLAN.md:896-897) contradicts the
  open B24 item (dlltool with as moves in its follow-up PR). Say "the
  stress table adds no evidence on B24; the dlltool/as follow-up
  stands", and qualify TODO.md:289-290: calls were looked for in make's
  echoed recipes only (binutils calls are not traced; configure.win and
  @-recipes are silent; R CMD check not run).
- B3 [stress-S3] The per-tool counts behind the phase 7 re-scope are
  partly a grep artifact: use recipe-level evidence (winshlib.mk's
  def/link recipe: nm, sed, basename, rm in every make row; configure.win
  scripts: sh; pkg-config in at least 9 rows by their messages; cmake in
  Rhdf5lib only).
- B4 [stress-S6, records-REC-9] "no row's smoke compiled at run time"
  is vacuous: g3 g4 have no compiling smoke, so R CMD SHLIB and
  run-time compilation were not exercised. Say so in the record and in
  "Not measured"; a g1 dispatch (Rcpp, rstan) with trace is a later
  item.
- B5 [stress-S8] Labels: "Makevars rule (src/Makevars, .win or .ucrt)
  (9)"; the status sentence lists configure scripts, Makevars rules and
  (Windows) $(shell), conditionals and include.
- B6 [records-REC-12, tests-T5] packages.tsv notes contradict the table:
  fst (fstcore through make), geos (libgeos make on Windows), lme4
  (nloptr make on unix, tier 1 on Windows); the g1 rows' notes come from
  a linux classify, not a dispatch.
- B7 [stress-S4, S5, phase3-P3-8] Timing wording: on ubuntu-latest the
  tier-1 rows (sys aside, which carries the runner compile) ran at about
  the same ratio to 548da1a as the make rows (0.67 vs 0.65): no
  measurable builder difference with a shared cache, runner variance
  explains the rest; the runner compile 5-15 s (about 37 s on
  macos-15-intel), inferred from sys with a cold global cache.
- B8 [stress-S9] Rhdf5lib compiles HDF5 through its configure and
  CMake's Makefiles: the rows needing the group are 31 of 47 (unix) and
  30 of 47 (Windows).
- B9 [records-REC-6, stress-S10] Scope wording: "not needed by tier 0-2
  installs without a configure script R runs" (three places);
  "cleanup.ucrt/cleanup.win under --clean or --preclean"; objdump's
  Windows qualifier; Objective-C and include among the tier-3 reasons.

## C. Later items (follow-up PR; record them in TODO.md)

- C1 [preflight-PF-1, major] A tier-2 package whose plan() needs make
  (a MAKEFLAGS assignment, a foreign CC from a site or user Makevars, an
  unreadable Makeconf) exits 3 and goes to make, which ignores build.zig
  (measured: zighello with MAKEFLAGS='-- X=1' fails with "shared object
  not found"); the preflight asks for the build tools, which cannot help.
  Exit 1 with "src/build.zig cannot be built by make: <reason>" in both.
  Menu 5.
- C2 [records-REC-3] NM_FILTER: CRAN's installed Makeconf filters
  `.refptr.`/`.weak.` names out of the make path's .def (MkRules.rules
  NM_FILTER default, fixed/Makefile substitution); r-zig's Makeconf.win
  has the unsubstituted `NM_FILTER =` since the initial vendoring, and
  rzig def was made to match that gap, so r-zig DLLs export stubs CRAN's
  do not. Menu 4.
- C3 [phase3-P3-10] The upstream-zig legs never ran on PR #25 (only
  full-ci): rzig build on Windows under upstream zig, tier 2 with
  --system and pkg-parity's argv comparison have not run with upstream
  zig anywhere. Menu 3.
- C4 [phase3-P3-9] Scenario 2's new assertions are unix-only; Windows
  base + compilers has no install assertion through the archives.
- C5 tests: [tests-T6] the "no make output" greps cannot fail (R's make
  echoes recipes, not "make:"): assert no echoed recipe instead;
  [tests-T7] argv_of's basename normalisation hides -I/-L and rpath
  mix-ups; [tests-T8] minos checked on the .so only (objects are in the
  deleted build root), the decoy not on an OpenMP shape; [tests-T4]
  stress.R's toolchain pattern matches "zig build failed", so a tier-1
  row's sysdep or package failure is classed toolchain; [tests-T11]
  0009's stop says "has compiled code" for a configure-only package;
  [tests-T12] smoke-test.sh part 2 runs in no task; stress.R's report
  does not record R_ZIG_PKG_BUILDER; [tests-T10, phase3-P3-3, P3-4]
  wording ("no make or sh", cf's "no make on PATH" with /usr/bin, pak is
  mixed).
- C6 preflight and hook: [preflight-PF-2] an empty R_MAKEVARS_USER
  falls back to ~/.R/Makevars in rzig but not in R; [PF-3] src/.rzig is
  left behind on early returns (use defer); [PF-4] R_ZIG_PKG_BUILDER=zig
  with no rzig silently uses make; [PF-5, records-REC-11] the flang rule
  for tier 2 and under R_ZIG_CONFIGURE departs from CONSENSUS B without
  a record; [PF-8] no test of Windows' package-check build-tools branch
  or of ZIG_LOCAL_CACHE_DIR; [phase3-P3-6] verify-bundle and contract
  pass ZIG_LOCAL_CACHE_DIR, so they never exercise the per-install
  cache a user gets.
- C7 records: [records-REC-5] record when the N7 review happened (after
  the push) and what it covered; [phase3-P3-7, records-REC-7] N5: name
  all changes (0009 too) and the coupling (a new r-zig-slim with an old
  r-zig-toolchain stops every compiled install: phase 4 bumps both
  together, and no channel mixes a local _8 with universe's _8); put the
  note under phase 4's bump; [records-REC-10, REC-14, PF-7, phase3-P3-5]
  wording, citations of uncommitted files, compile-tree consumers.

## Menus for the user (recommended first)

1. Windows OpenMP packages through rzig build (A2): (a) add the package
   twins before merge, as the agreed checklist says; (b) correct the
   header, add a TODO item, do it later.
2. The global cache key (A1): (a) fix before merge, with the tarball
   test; (b) record it and fix later.
3. The upstream-zig legs (C3): (a) add the `upstream-zig` label to PR
   #25 and wait for its legs before merging; (b) record "not run" and
   leave it to the release gate.
4. NM_FILTER (C2): (a) a follow-up PR right after #25 substitutes
   upstream's NM_FILTER into Makeconf.win (as fixed/Makefile does) and
   drops rzig def's .refptr/.weak exports, so both paths match CRAN; (b)
   keep the divergence and record it as deliberate.
5. Tier 2 that needs make (C1): (a) in the follow-up PR with C4-C7;
   (b) before merge.
6. The later items C1, C4-C7: (a) one follow-up "zig-pkg-build
   hardening" PR after #25 merges; (b) separate small PRs.
