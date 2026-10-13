# Review of PR #25 (feat-zig-pkg-build, 5416d8d) against phase 3 and the agreed plan

2026-10-13, read-only, by the phase 3 session. Five angles (phase 3 interfaces, preflight and hook, tests and coverage, records, the stress follow-up); every finding checked by an adversarial verifier: 51 confirmed, 3 refuted. Severity and "when" are the verifier's. Findings that repeat each other are kept (they cite different places); the summary in REVIEW-SUMMARY.md groups them.

## phase3-P3-1 (major, before-merge)

- File: scripts/verify-bundle.sh:62-63 (claim); 1425-1459 (code)
- Problem: Verified. The scenario 3 header says Windows builds the OpenMP C and Fortran packages 'through R CMD SHLIB, make, and as packages through rzig build'. The Windows OpenMP block only runs R CMD SHLIB (1444). Checklist G in CONSENSUS.md (consolidation/CONSENSUS.md:245, 'likewise Windows scenario 3's OpenMP packages', coverage-C2) asked for these packages and the PR does not have them. Nothing in CI builds an OpenMP package through rzig build on Windows. This is the path R CMD INSTALL now takes for these tier-1 shapes there: SHLIB_OPENMP_*FLAGS, -lomp mapped to openmp/lib/libomp.lib, `rzig def` together with -fopenmp, and zig-fc linking with OpenMP.
- Evidence: verify-bundle.sh:1440-1446 loops over probe/omp/lomp/fomp/fompfc with `R CMD SHLIB` only. No `CMD INSTALL` or shape_pkg call exists in the Windows branch (grep: every shape_pkg is at 824-1099, inside the unix block). contract's data.table goes through make (contract-test.sh:81-82). pkg-parity's cli/digest/quadprog/Rcpp have no OpenMP. In stress run 38317654371 the Windows tier-1 logs contain zero '-fopenmp' (grep -c over the 17 tier-1 logs). kappa's record (PR PLAN.md:1001) mentions only 'the OpenMP DLLs', which are SHLIB.
- Fix: In the Windows OpenMP block, also install omp, lomp and (where offered) fomp and fompfc as packages: DESCRIPTION, useDynLib, the same Makevars. Use the same env -i, decoy CONDA_PREFIX and bt_path, plus RZIG_TRACE=1. Assert 'rzig build: tier 1', that the DLL imports libomp.dll, that no .lib is left, and that it loads with PATH = bin\x64 + System32. Otherwise correct lines 62-63 and add a TODO item that marks the gap as open.

Verifier:

I tried to refute this and could not. Every claim holds against 5416d8d.

1. **The header overclaims, and this PR wrote it.** `git diff e1ce179 5416d8d -- scripts/verify-bundle.sh` adds header lines 62-63: "the OpenMP C and Fortran packages (through R CMD SHLIB, make, and as packages through rzig build)". The Windows OpenMP block (scripts/verify-bundle.sh:1425-1459, dir omp-win) builds probe, omp, lomp and, where Makeconf offers it, fomp/fompfc with `R CMD SHLIB` only (line 1444). It then checks for the libomp.dll import, that no .lib is left, and that they load. It has no DESCRIPTION, no `CMD INSTALL`, no RZIG_TRACE and no `rzig build: tier 1` assertion. Every `shape_pkg` call (lines 824-1099) is inside the `[ "$OS" != windows ]` block. The other `CMD INSTALL` calls on the Windows side are bt.R (btA, btLib, btRc: no OpenMP), the LTO packages and nopre. The diff adds no Windows OpenMP install.

2. **The agreed plan asked for it.** CONSENSUS.md checklist G (the PR's copy is identical to consreview/) says the SHLIB fixtures also become packages under the default builder, "likewise Windows scenario 3's OpenMP packages [coverage-C2]". The PR's own record does not cover the Windows part:
   - PLAN.md's verify-bundle (G) entry (around lines 808-823) lists only the unix shapes plus btA/btLib/btRc and ltotier1.
   - Item 7 ("Builders changed silently", coverage-C2..C5) says nothing about Windows OpenMP.
   - kappa's row (PLAN.md:1001) says only "the OpenMP DLLs", which are the SHLIB ones.
   - No TODO item marks the gap as deferred.

3. **Nothing else covers it on Windows.**
   - contract-test.sh expects data.table = make.
   - pkg-parity's cli/digest/quadprog/Rcpp, test-toolchain.R and wheel-test.sh have no OpenMP.
   - In stress 38317654371 all 17 Windows tier-1 logs have `rzig build: tier 1` and zero `-fopenmp`. The only Windows log with `-fopenmp` is fstcore, which goes to make ("Makevars.ucrt has an include").

**Why major:** `R CMD INSTALL` now builds tier-1 OpenMP packages on Windows through rzig build by default. That path combines SHLIB_OPENMP_*FLAGS from Makeconf.win, -lomp resolving to openmp/lib/libomp.lib, `rzig def` on -fopenmp objects, and the zig-fc OpenMP link, and it has no evidence on any Windows run. kappa's first pkg-parity runs found Windows-only rzig build bugs (def.zig dropping .refptr names, the --out-implib cut), so this gap matters. The script's header also tells readers this coverage exists.

**Before merge:** at minimum correct lines 62-63 and record the gap as an open TODO item. Better, add the package installs the finding describes and run them on kappa or in CI.

## records-REC-1 (major, before-merge)

- File: scripts/verify-bundle.sh:62
- Problem: Checklist G is not done: CONSENSUS asked for 'likewise Windows scenario 3's OpenMP packages' to be built as packages through rzig build too. Windows OpenMP through rzig build is still untested anywhere, yet the verify-bundle header says those packages are built 'as packages through rzig build'.
- Evidence: Verified. consolidation/CONSENSUS.md:245 asks for it. The header at verify-bundle.sh:62-63 claims 'the OpenMP C and Fortran packages (through R CMD SHLIB, make, and as packages through rzig build)'. The Windows OpenMP block (verify-bundle.sh:1404-1459) still only runs `R CMD SHLIB -o $d.dll` for probe, omp, lomp, fomp and fompfc. In the PR diff, shape_pkg/rzig-build twins exist only in the unix scenario 2 hunks (@@ -904 and @@ -934). No other test fills the gap: pkg-parity's Windows set is cli, digest, quadprog and Rcpp (pkg-parity.sh:78-79); contract's OpenMP package data.table goes to make (configure); no -fopenmp appears in any Windows tier-1 stress log (fst, geos, Rcpp, vctrs, cli, gmp, nloptr, wk, lattice, bit64). PLAN.md:1001 (kappa) reports only 'the OpenMP DLLs', the SHLIB path, and nothing records the gap.
- Fix: Add shape_pkg-style package twins for omp, lomp, fomp and fompfc in Windows scenario 3. Each should install with RZIG_TRACE=1, assert 'rzig build: tier 1', check that the DLL imports libomp.dll, and load with PATH = bin\x64 + System32. Until then, change the header to say SHLIB only and add a TODO item.

Verifier:

I could not refute the finding. Every part of it checks out against the code and data at 5416d8d.

1. **The plan asked for it.** In the consolidation CONSENSUS.md, line 245 (checklist G, coverage-C2) ends with "likewise Windows scenario 3's OpenMP packages". FINDINGS.md:112 asks for the same: "Add the same to Windows scenario 3's OpenMP packages."

2. **The header claims it is done.** This PR added the text at verify-bundle.sh:62-63: "the OpenMP C and Fortran packages (through R CMD SHLIB, make, and as packages through rzig build)". It is in diff hunk @@ -45,15 +52,20 @@. On main e1ce179 the line only said "the OpenMP C and Fortran packages".

3. **The Windows code does not do it.** The Windows OpenMP block (verify-bundle.sh:1405-1460) loops over probe, omp, lomp, fomp and fompfc. Each one only runs `R CMD SHLIB -o $d.dll`, then dyn.loads the DLLs. `shape_pkg` (line 771) is defined inside the unix-only scenario 2 block, so it never runs on Windows. Its OpenMP twins exist only at lines 1017-1027 and 1058-1073, both unix. The bt.R install on Windows covers btA, btLib and btRc, none of which uses OpenMP.

4. **No other test covers it.**
   - pkg-parity.sh:78-79: the Windows packages are cli, digest, quadprog and Rcpp.
   - recipe/test-toolchain.R and contract-test.sh: no OpenMP package goes through rzig build.
   - Stress run 38317654371 on windows-latest: none of the 17 tier-1 logs has `-fopenmp`, `-lomp` or `libomp`. The only "openmp" text in them is the `-idirafter .../openmp/include` that every compile gets. The only Windows log with `-fopenmp` is fstcore.log, and fstcore goes through make.

5. **The records do not flag the gap.**
   - The PR's PLAN.md G item (lines 808-823) lists the shapes that became `shape_pkg` packages without saying they are unix-only.
   - The kappa row at PLAN.md:1001 says only "the OpenMP DLLs".
   - The PR adds no TODO item for it.

**Severity.** No defect has been shown, so this is a coverage gap plus a false header claim. I still rate it major for three reasons:
- It is an agreed checklist item that was not done.
- The PR makes rzig build the default builder, and Windows OpenMP through it (-fopenmp, and -lomp resolved to openmp/lib/libomp.lib by rzig) is now an untested path.
- The header and the record tell the reader this is covered.

The cheapest fix before merge is to correct the header and add a TODO item; the full fix is the Windows twins.

## tests-T1 (major, before-merge)

- File: zigbuild/rpkg/build_t1.zig:83 (cause); scripts/pkg-parity.sh:199-211 (test); scripts/pkg-parity.sh:126 (argv normalisation); .github/devdocs/feat-zig-pkg-build/PLAN.md:177-180, 976-980
- Problem: rzig build leaves one entry per compiled source in zig's global cache on every install from a tarball, which is the normal path: install.packages and R CMD INSTALL pkg.tar.gz unpack into a fresh R.INSTALL directory each time. The reason: compileAll passes the absolute source path (`-c /tmp/RtmpX/R.INSTALLy/<pkg>/src/one.c`), and zig cc keys its object cache on that path. make passes `-c one.c` from src/, so its entries are reused. Fact 9's unbounded growth has therefore moved from ~/.cache/r-zig/zig-build to ZIG_GLOBAL_CACHE_DIR (~/.cache/zig by default). pkg-parity's cache check installs twice from the same unpacked directory, the one case where the paths coincide, so it passes. argv_of reduces every path to its basename, so the parity check cannot see absolute against relative either. The records say nothing per install outlives the install and that the global cache is the bounded shared part (CONSENSUS D: 'keyed by target, bounded').
- Evidence: Verified by experiment, scratch only, with the worktree's compile tree build/compile-tree/slim (read-only), env -i, ZIG_GLOBAL_CACHE_DIR in scratch. (1) rzigc (one.c, two.cpp) from a tarball, 3 installs through rzig build: global o/ went 117 -> 119 -> 121 -> 123. 2 installs with R_ZIG_PKG_BUILDER=make: 123 -> 123. (2) cli_3.6.6.tar.gz from build/pkg-parity-slim/src, 3 installs through rzig build: 151 -> 177 -> 203 (+26 each, one per source, about 174 KB per install). Through make: +26 once, then 0, 0. (3) A traced compile line: `zig-cc: .../zig cc ... -c $S/RtmpEYfVAw/R.INSTALL11bc273678ed1c/rzigc/src/one.c -o .../src/.rzig/zig-cache/o/<h>/one.o`; make's log has `zig-cc ... -c one.c`. build_t1.zig:79 already sets cwd to srcdir, and :83 still passes `plan.srcdir/s.path`. CI's same-directory check stayed equal (268, 257, 1575) only because the paths matched. PLAN.md:298-302 had noted that the zig build path's absolute paths do not share entries, but not the per-install consequence. Inferred: __FILE__ and debug paths also differ between the two builders.
- Fix: In compileAll, pass `s.path` relative to the cwd that is already srcdir (addArg(s.path) plus addFileInput for the dependency), so the keys match make's. In pkg-parity, install the cli tarball twice, or two copies in different directories, and assert the o/ count is unchanged on the second install. That test fails today and passes after the fix. Correct PLAN.md (N3 paragraph and Measurements) and CONSENSUS D's 'bounded' accordingly.

Verifier:

The finding is real. I checked it against the code and reproduced it in scratch.

**Code.** At zigbuild/rpkg/build_t1.zig:79 the run's cwd is already srcdir, but :83 still calls `run.addFileArg(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, s.path }) })`. That passes zig cc an absolute source path. install.R unpacks every tarball into a new tempfile("R.INSTALL") directory, so that path changes on every install.

**Reproduction.** Setup: the worktree's compile tree build/compile-tree/slim, `env -i`, ZIG_GLOBAL_CACHE_DIR and TMPDIR in scratch, conda zig 0.16, and a two-source package (one.c, two.cpp) installed from its tarball.
- Through rzig build, 3 installs: the global o/ count went 0 -> 115 -> 117 -> 119, two entries per install, one per source.
- Then R_ZIG_PKG_BUILDER=make, 2 installs: 119 -> 121 -> 121. make's entries are reused after the first install.
- In the traced lines, rzig build runs `zig cc ... -c $TMP/RtmpX/R.INSTALLy/rzigc/src/one.c -o .../src/.rzig/zig-cache/o/<h>/one.o`, while make runs `-c one.c -o one.o`.

**The cause is the source path, not the -o path.** I ran zig cc by hand on identical a.c files:
- A relative `-c a.c` from two different cwds, each with a different absolute -o, gave one entry.
- An absolute `-c /…/d3/src/a.c` added a new entry.
- An absolute path to the d1 file, which was already cached through the relative path, added another.

So the proposed fix (pass `s.path` relative, since cwd is already srcdir) would make the keys match make's.

**Test gap.** scripts/pkg-parity.sh:199-211 installs twice from the same unpacked directory, the one case where the paths coincide. CONSENSUS D's check says "a second install of the same package", which is weaker than a tarball install. Separately, argv_of (:126) cuts every path to its basename, so the parity comparison cannot see absolute against relative paths either.

**Already known but not addressed.** FINDINGS.md:405 and :410 had already recorded that the zig path grows zig's global cache on tarball installs, "because Run steps pass absolute source paths". Neither the consensus nor the PR deals with it. The PR's records still say nothing per install outlives the install and that the global cache is the bounded shared part (feat-zig-pkg-build PLAN.md:177-180, :976-980; CONSENSUS D "keyed by target, bounded"). PLAN.md:298-302 notes that absolute paths do not share entries, but treats that as mattering only for benchmarks.

**Severity: major, before merge.**
- Under the default builder (auto), install.packages and R CMD INSTALL of a tier-1 tarball are the normal path. Every reinstall or update adds a full set of objects to ~/.cache/zig, which nothing prunes; for cli that is 26 entries per install. It also never hits the cache, while make reuses objects for unchanged sources.
- This is the unbounded growth of fact 9, moved from rzig's zig-build cache to zig's global cache. N3 was meant to remove it, and the PR's test and records say it is removed.
- It is a disk and time regression, not a wrong build. But the fix is a one-line change plus a tarball-twice assertion in pkg-parity, so it belongs in this PR.
- A further, unverified consequence: __FILE__ and debug paths will also differ between the two builders.

## tests-T3 (major, before-merge)

- File: scripts/verify-bundle.sh:1425-1459 (Windows OpenMP block); header 62-64
- Problem: Checklist G2 required that, as for unix scenario 2's shapes, 'likewise Windows scenario 3's OpenMP packages' be installed as packages under the default builder (coverage-C2). They are still built only through R CMD SHLIB (make). No Windows test anywhere builds an OpenMP package through rzig build, yet the header says they build 'through R CMD SHLIB, make, and as packages through rzig build'. Nothing in PLAN.md or TODO.md records the gap.
- Evidence: Verified: the omp-win loop runs only `"$R_EXE" CMD SHLIB -o "$d.dll" "$src"` (:1440-1442). There is no shape_pkg or R CMD INSTALL in the Windows branch apart from bt.R and the LTO record. CI windows-latest/default prints only '== compiled packages verified: OpenMP with the groups (probe omp lomp fomp fompfc: ...)', and no '(R CMD INSTALL, rzig build)' line. pkg-parity's packages (cli, digest, quadprog, Rcpp) and contract's data.table (make) have no OpenMP through rzig build on Windows. FINDINGS coverage-C2's suggestion ends 'Add the same to Windows scenario 3's OpenMP packages.'
- Fix: Install omp, lomp, fomp and fompfc as packages (useDynLib, Makevars as for SHLIB) with RZIG_TRACE=1 and the decoy CONDA_PREFIX. Assert 'rzig build: tier 1', the libomp.dll import, no .lib left in src/, and the load with PATH = bin\x64 + System32. Or correct the header and add a TODO.md item.

Verifier:

I could not refute this finding. It holds at 5416d8d.

1. **The header claims coverage the test doesn't have.** The PR rewrote the scenario 3 header (scripts/verify-bundle.sh:60-62) to say Windows builds the OpenMP C and Fortran packages "through R CMD SHLIB, make, and as packages through rzig build". The Windows OpenMP block (if SHLIB_OPENMP_CFLAGS ... omp-win, :1425-1459) still only runs `"$R_EXE" CMD SHLIB -o "$d.dll" "$src"` for probe, omp, lomp, fomp and fompfc. The PR diff does not touch this block. Its only Windows install changes are RZIG_TRACE=1 on bt.R and the ltotier1 LTO twin. The unix `shape_pkg` helper exists only inside the `[ "$OS" != windows ]` scenario 2 block.

2. **CI confirms it.** The windows-latest / default job (115000747326) of run 38305799627 prints only "== compiled packages verified: OpenMP with the groups (probe omp lomp fomp fompfc: ...)". It prints no "(R CMD INSTALL, rzig build)" line. The only Windows installs that go through rzig build are:
   - btA
   - pkg-parity's cli, digest, quadprog and Rcpp
   - contract's Rcpp and quadprog
   - pak's embedded cli, lpSolve, pkgcache and yaml

   None of them uses OpenMP. Contract's data.table, which prints the OpenMP version, builds through make.

3. **The stress run doesn't cover it either.** In stress 38317654371 on windows-latest, the only log with -fopenmp is fstcore, and it is make (Makevars.ucrt include). No Windows row builds OpenMP, or USE_FC_TO_LINK / Fortran OpenMP, through rzig build.

4. **The agreed plan asked for it.** CONSENSUS.md checklist G (the PR's copy under consolidation/ is byte-identical) says scenario 2's SHLIB fixtures also become packages, "likewise Windows scenario 3's OpenMP packages [coverage-C2]". FINDINGS coverage-C2 ends "Add the same to Windows scenario 3's OpenMP packages."

5. **The gap isn't recorded.** The PR's PLAN.md consolidation record lists only the scenario 2 (unix) shapes as packages and then says "The header says so." The feat-standalone-toolchain PLAN.md and TODO.md changes say nothing about Windows OpenMP through rzig build.

Severity: these shapes are tier 1, so with the default builder (`auto`) real Windows installs of such packages go through rzig build. That path has never been exercised on Windows for -fopenmp, -lomp, Fortran OpenMP or the USE_FC_TO_LINK zig-fc link. Meanwhile a test header claims it is verified, and an agreed checklist item was dropped without a record.

The product risk is moderate, not high: the OpenMP flags and -lomp are resolved by rzig's compiler driver, which both paths share, and pkg-parity shows identical argv on Windows for four packages. Either fix is cheap and belongs before merge:
- Add package installs of omp, lomp, fomp and fompfc to the Windows block, asserting "rzig build: tier 1", the libomp.dll import, no .lib left, and the load with only bin\x64 and System32 on PATH.
- Or correct the header and record the gap in TODO.md.

## preflight-PF-1 (major, later)

- File: zigbuild/tools/rzig/pkgbuild.zig:222, 270 (also pkgplan.zig:175; 0013 patch lines 78-82, 117)
- Problem: A tier-2 package (src/build.zig) whose plan() hits NeedsMake exits 3, and install.R then takes the make path, which ignores build.zig. Causes include a MAKEFLAGS assignment (N4), a foreign CC from a site or user Makevars (for example ccache), or an unreadable Makeconf. N6's own reasoning says such a case must be exit 1, not 3, because 'make would compile src/ and ignore build.zig'. The PR applies that only to URL dependencies. The preflight also gives the wrong advice: it asks for the build tools, and make cannot build the package.
- Evidence: Verified. decide maps plan's NeedsMake to .tier = .make with .class.tier still .zig (pkgbuild.zig:222), and run() returns needsMake, exit 3, for every .make (pkgbuild.zig:270). 0013 turns exit 3 into NA, so run_shlib calls make, and its allfiles hunk (patch line 117) sends a build.zig-only package there with no sources. In scratch, `rzig build --pkg .. --src . --out . --flat` on a build.zig-only package exited 3 with 'MAKEFLAGS sets X' under MAKEFLAGS='-- X=1', and with 'CC = gcc is not a compiler of R's toolchain' under R_MAKEVARS_USER holding CC = gcc. A real R CMD INSTALL of zighello, using the worktree's compile-tree R into a scratch library with MAKEFLAGS='-- X=1', printed 'rzig build: zighello needs make: MAKEFLAGS sets X'. make then built nothing, and the install failed with "shared object 'zighello.so' not found". `--zig-check=package` for the same case says 'needs make: MAKEFLAGS sets X; no make on PATH' and names the build-tools group. Inferred: with C sources beside build.zig, make would build a partial library.
- Fix: In pkgbuild.run, when d.class.tier == .zig and d.tier == .make, print '<pkg>: src/build.zig cannot be built by make: <reason>' and return 1, as for a URL dependency. In check.zig package(), stop with that line for the same condition instead of asking for the build tools. Optionally skip the MAKEFLAGS check for class.tier == .zig, since there is no make build to differ from. Add a pkg-parity case: zighello with MAKEFLAGS='-- X=1' fails with that line.

Verifier:

I could not refute it. The code and my reruns both confirm it.

Code: in the worktree's zigbuild/tools/rzig/pkgbuild.zig:222, decide() maps plan()'s error.NeedsMake to .tier = .make while class.tier stays .zig. At :270, run() returns needsMake(), which is exit 3 (:537-539), for every .make. Nothing checks class.tier there. The only tier-2 exit-1 path is the URL check in build.zig.zon (:318-323), whose comment gives N6's reason: "exit 1, not 3: make would compile src/ and ignore build.zig".

pkgplan.plan() applies the same NeedsMake causes to tier .zig as to tier 1: the MAKEFLAGS assignment (pkgplan.zig:175), the unreadable Makeconf, and the toolLine/toolName foreign-driver check for CC (need_c is forced true for class.tier == .zig at :330).

Patch 0013 lines 78-82 turn exit 3 into NA, so run_shlib takes the make path. Lines 116-118 send a build.zig-only package there with srcs empty. check.zig package() (:240-247) treats d.tier == .make the same for tier 2: "needs make: <reason>; <missing>" with the build_tools group. So the preflight asks for make, and make cannot build this package.

Reruns: worktree compile tree build/compile-tree/slim, fresh zighello copies in my scratch dir, which I have deleted.
- No MAKEFLAGS: tier 2, DONE.
- MAKEFLAGS='-- X=1': "rzig build: zighello needs make: MAKEFLAGS sets X". make built nothing, and the install failed with "shared object 'zighello.so' not found".
- R_MAKEVARS_USER with CC = ccache $(R_HOME)/bin/toolchain/zig-cc: "needs make: CC = ccache is not a compiler of R's toolchain". Same late failure.
- The finding's "inferred" case also holds, and it is worse. With an extra.c beside build.zig and MAKEFLAGS='-- X=1', make compiled only extra.c into zighello.so. The install exited 0 and printed DONE. The library exports only extra_fn and lacks the zig C_hello symbol, so the install looks good and hello() will fail when called.

PLAN.md and CONSENSUS (N4/N6) do not list this as a known gap. N4 never considered tier 2.

Severity major: a ccache line in ~/.R/Makevars or a MAKEFLAGS assignment breaks every tier-2 install, and a mixed package installs with no error and a partial library.

Timing later:
- Tier 2 is new. Only the zighello prototype uses it, and no CRAN package has src/build.zig.
- Per N5, nothing from this PR is published until phase 4's build bump.
- The fix is small: in pkgbuild.run and check.zig, class.tier == .zig with tier .make should return 1 with a clear "src/build.zig cannot be built by make: <reason>" line, plus a pkg-parity case.

One small slip in the finding: the flag is --rzig-check=package, not --zig-check.

## records-REC-2 (major, later)

- File: scripts/pkg-parity.sh:199
- Problem: N3's claim that 'nothing per install outlives it' is false for tarball installs, which is how install.packages installs. On the rzig build path, zig's global cache gains one o/ entry per compiled source on every tarball install, because build_t1 passes absolute source paths that change per R session. The make path stays flat. pkg-parity's cache check installs from a fixed directory, so it cannot catch this.
- Evidence: Verified by measurement in scratch with the worktree's compile tree, a scratch ZIG_GLOBAL_CACHE_DIR and a 2-source C package (scratch since deleted): (1) three tarball installs through rzig build left global o/ at 30, then 32, then 34; (2) two installs from a directory left it at 36 and 36; (3) three tarball installs with R_ZIG_PKG_BUILDER=make left it at 38, 38, 38. Cause: build_t1.zig:83 passes `b.pathJoin(plan.srcdir, s.path)`, an absolute path, and srcdir is under R_SESSION_TMPDIR. FINDINGS channels-C5's verifier had already measured this ('zig cc's global cache also gained 1 entry per install ... larger than claimed'). CONSENSUS D (consolidation/CONSENSUS.md:191) nonetheless called the global cache 'keyed by target, bounded'. The PR repeats it: pkg-parity.sh:35-39 and :199-211 (the check is 'cli twice from one directory'), PLAN.md:728-730 ('Per install now (N3)') and :976-980.
- Fix: Record that the global cache still grows by one entry per source per tarball install on the zig path. Make the pkg-parity check install the same tarball twice, which should fail today. Add a TODO item: pass sources relative to srcdir through setCwd, as make does, or otherwise key them stably, then assert flat growth.

Verifier:

I could not refute it. I reproduced the numbers exactly, and the code and records match what the finding cites.

Measurement: I ran it in scratch, now deleted. I used the worktree compile tree build/compile-tree/slim/R-4.6.1-zig, its own zig 0.16, and scratch values for ZIG_GLOBAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR. The package was a 2-source C package. zig's global cache o/ count went like this:
- Three tarball installs on the default (rzig build) path: 30, 32, 34.
- Two installs from a directory: 36, 36.
- Three tarball installs with R_ZIG_PKG_BUILDER=make: 38, 38, 38. That log shows `zig-cc ... -c a.c -o a.o` run by make.

I ran one more tarball install with RZIG_TRACE=1. It showed `rzig build: tier 1, root .../tmp/RtmpdFIarZ/R.INSTALL123d3f7e937b2f/tpk/src/.rzig`, and zig-cc got `-c /data/.../RtmpdFIarZ/R.INSTALL.../tpk/src/a.c`. The two new global o/ entries held exactly a.o and b.o.

Cause: build_t1.zig:83 does `run.addFileArg(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, s.path }) })`, which is an absolute path under the per-session R.INSTALL tempdir. zig cc's cache keys an absolute source path whole. A relative `-c a.c` with that cwd is keyed relative to the cwd, so make's entries are reused. pkgbuild.zig:362-369 moves only the zig build --cache-dir into the build root. Nothing sends zig cc's object cache there, so it stays in the global cache.

Records:
- CONSENSUS.md section D (consolidation copy :191) says "nothing per install outlives it" and calls the global cache "keyed by target, bounded".
- The PR repeats this in pkg-parity.sh:35-39 and in its section header at :199 ("the caches: nothing per install outlives it").
- The check at :201-211 installs cli twice from one fixed directory, $WORK/work/again/cli, so it cannot see the tarball case.
- PLAN.md:728-730 says "Per install now (N3)", and :976-980 reports "cli twice from one directory: ... unchanged (270 entries)".
- FINDINGS channels-C5's verifier had already reported "zig cc's global cache also gained 1 entry per install, because Run steps pass absolute source paths".
- PLAN.md:298-302 (from M1) notes that zig cc's cache is keyed by source path, but says this "only matters for benchmarks".
- Nothing in PLAN.md or TODO.md records the per-install growth or plans a fix.

Severity: major. N3 was adopted to stop exactly this kind of unbounded per-install cache growth, and channels-C5 was rated major. A real part of that growth is still there for install.packages, the usual way users install. The records say it is fixed, and the PR's own check is set up so it cannot catch it. This is a disk regression compared with make, not a functional break. Each reinstall of the same sources adds about the size of the package's objects, roughly 0.2-1 MB for cli, digest or Rcpp, and far more for large C++ packages.

When: later. Nothing ships until phase 4 (N5, no build-number bump). Correcting the records, adding a TODO item and switching the check to a tarball are cheap docs and test edits that could go in with this PR. The code fix, passing sources relative to srcdir as make does, can follow afterwards.

## phase3-P3-2 (minor, before-merge)

- File: zigbuild/tools/rzig/check.zig:2-8, 50-51, 200-206
- Problem: Verified. The check-mode header still describes the old 0009, which ran the compilers or fortran check and then build-tools. The exit-code paragraph names exit 2 only for an unknown --rzig-check value. package() also returns 2 when R_HOME is unset or a path will not resolve. In the second case the only line is pkgbuild's 'zig-cc: build: <path>: <err>' (pkgbuild.zig:114), and 0009 then reports 'the r-zig toolchain is incomplete (see above)'. The groups.zig:4-7 header also omits that `rzig build` prints the compilers text (pkgbuild.zig:377).
- Evidence: check.zig:3-6 is byte-identical to main's (git show e1ce179:zigbuild/tools/rzig/check.zig). check.zig:203, 205 and 206 each return `.{ .code = 2 }`.
- Fix: Rewrite lines 2-8 to say 0009 runs --rzig-check=package. Add package()'s exit 2 cases to the exit-code paragraph. Word the canonical() failure under check mode without the 'build:' prefix. Add rzig build to groups.zig's list of places that print a group's text.

Verifier:

The finding holds against the code at 5416d8d. These are comment and wording problems only; no behaviour is wrong.

1. **Stale header, check.zig:2-8.** The paragraph still says 0009 runs the compilers check (or fortran when src/'s top level has Fortran) and then the build tools. It matches main's header and main's 0009, which looped over `--rzig-check` or `--rzig-check=fortran`, then `--rzig-check=build-tools`. The PR's 0009 makes one call instead: `system2(rzig, "--rzig-check=package", stdout = FALSE)` with R_ZIG_CONFIGURE and R_ZIG_C_STD set. In that mode the build tools are checked only for make or a configure script, and Fortran comes from the plan for tiers 1 and 2. So lines 2-8 now contradict the header's own new `--rzig-check=package` entry (lines 22-39) and the patch's own description.

2. **Exit-code paragraph.** It ends "Any other `--rzig-check=` value: a usage line and exit 2 (main.zig)." It does not mention that package() also returns 2:
   - line 203: R_HOME is unset (a warning line is printed);
   - line 205: R_HOME will not resolve;
   - line 206: the working directory will not resolve.
   In the two canonical() cases the only line printed is pkgbuild.zig:114's `<name>: build: <path>: <err>`. 0009 then stops with "the r-zig toolchain is incomplete (see above)", and the "build:" prefix is misleading there. In practice R sets R_HOME and the package directory exists, so these paths are rare edge cases.

3. **groups.zig:4-7.** The file is unchanged by the PR. It lists where a group's text is printed (a compile with no zig, zig-fc with no flang, check mode) but not `rzig build`, which pkgbuild.zig:377 adds with `groups.report(ctx, groups.no_zig, .compilers)`. This one is the weakest of the three, since "a compile finds no zig" could be read to cover it.

4. **Not in the finding.** main.zig:27's header still says `--rzig-check[=fortran|build-tools]`, while the usage text at main.zig:135 lists `package`. This is the same kind of drift.

Severity is minor because nothing behaves wrongly. I would still fix it before merge: it is a comment-only change in files the PR already edits, and the stale paragraph misstates what the PR's own preflight does.

## preflight-PF-6 (minor, before-merge)

- File: zigbuild/tools/rzig/check.zig:1-10 (also main.zig:27-29, fortran.zig:44-45)
- Problem: Code headers still describe phase 3's two-step 0009. check.zig:3-6 says 'The install preflight (patch 0009: the compilers, or fortran when src/'s top level has Fortran sources ... then the build tools ...)'. main.zig:27-29 lists `--rzig-check[=fortran|build-tools]` as what 'the install preflight and R CMD config call'. fortran.zig:44-45 says 'unless the preflight's `--rzig-check=fortran` showed it first'. 0009 now makes one `--rzig-check=package` call.
- Evidence: Verified: 0009 patch line 78 is the only check call, `system2(rzig, "--rzig-check=package", stdout = FALSE)`, and the check.zig header's own `--rzig-check=package` entry (22-39) contradicts its first paragraph.
- Fix: Reword the three comments: the preflight calls `--rzig-check=package` (compilers, flang by the rules in check.zig, build tools when make or a configure script R runs is involved), and R CMD config calls `=build-tools`.

Verifier:

I tried to refute this and couldn't: all three comments are stale at 5416d8d.

Patch 0009 changed between the two commits:
- At e1ce179 it looped over `--rzig-check` or `--rzig-check=fortran`, then `--rzig-check=build-tools`.
- At 5416d8d it makes one call, `system2(rzig, "--rzig-check=package", stdout = FALSE)` (patch line 78).

check.zig:
- The PR's diff hunk starts at line 19, so the opening paragraph (lines 1-10) is phase 3's text, unchanged. It still says the preflight checks "the compilers, or fortran when src/'s top level has Fortran sources ... then the build tools".
- That no longer matches `package()` in check.zig. For tiers 1 and 2 it decides flang from the plan's sources, not only from src/'s top level. It checks the build tools only for tier 3 (needs make) or when R_ZIG_CONFIGURE=1, not always.
- The `=package` entry the PR added in the same header (lines 22-39) says the same thing, so the header now contradicts itself.

main.zig:
- The PR updated the usage string (line 135) and the error message (line 207) to include `package`.
- But header line 27 still says `--rzig-check[=fortran|build-tools]` is "what the install preflight and R CMD config call". The preflight now calls `=package`.

fortran.zig:
- fortran.zig is not in the PR diff. Lines 44-45 still say "unless the preflight's `--rzig-check=fortran` showed it first". The preflight no longer passes `=fortran`, although `package()` does reach the same flang check through `compilers(ctx, true)`.

The PR's PLAN.md doesn't list these as known or deferred.

Behaviour is not affected; this is documentation only, so the severity is minor. I'd still fix it before merge: it is a three-comment edit, and in this project the code headers are the primary documentation. Leaving them as they are leaves check.zig's header contradicting itself, introduced next to lines this PR edited.

## records-REC-12 (minor, before-merge)

- File: stress/packages.tsv:49
- Problem: The packages.tsv notes written before the push (checklist G) are contradicted by the stress table that followed, and the follow-up commit did not correct them.
- Evidence: Verified with tiers.tsv. :49 (fst) says 'builds through rzig build (tier 1; fstcore too)', but fstcore is make on every leg ('a configure script' on unix; 'src/Makevars.ucrt has an include' on Windows). :50 (geos) says '(tier 1; libgeos too)', but libgeos is make on Windows ('$(SHLIB): $(STATLIB)'). :64 (lme4) says 'nloptr and Matrix through make', but nloptr is tier 1 on Windows.
- Fix: fst: 'fstcore through make'. geos: 'libgeos too on unix; make on Windows'. lme4: 'nloptr through make on unix, tier 1 on Windows'.

Verifier:

The finding holds. I checked it against the worktree at 5416d8d and against stress dispatch 38317654371's tiers.tsv and tiers-intel.tsv.

- **fst (line 49).** The note says "builds through rzig build (tier 1; fstcore too)". fst is tier 1 on all five legs, but fstcore is make on every leg: "a configure script" on ubuntu-latest, ubuntu-24.04-arm, macos-latest and macos-15-intel, and "src/Makevars.ucrt has an include" on windows-latest. The pre-push evidence already said so: FINDINGS.md:577 records fstcore exiting 3 (configure) under `rzig build --classify`. So the note was wrong when it was written, not just made stale by the stress run.
- **geos (line 50).** The note says "(tier 1; libgeos too)". libgeos is tier 1 on the four unix legs, but on Windows it is make ("src/Makevars.win has a rule or target line: '$(SHLIB): $(STATLIB)'").
- **lme4 (line 64).** The note says "nloptr and Matrix through make" without naming an OS, while the same note does name one for "minqa on unix". Matrix is make on every leg, but nloptr is tier 1 on windows-latest.

The PR's own PLAN.md stress section states all three facts correctly: the table of make reasons lists fstcore, libgeos and nloptr, and the text says "gmp, gsl and nloptr are tier 1 there ... askpass and libgeos go to make". Even so, 5416d8d changed only the three devdocs files and left stress/packages.tsv as it was at 47e8436. The PR therefore adds wrong statements to the per-row record and leaves them uncorrected.

**Impact.** It is documentation only, so the severity is minor. The note column is free text, so nothing the suite runs or checks changes. These three notes are new text in this PR (checklist G), and fixing them is a three-cell, [skip ci] text edit. Fixing them in this PR keeps known-false notes out of main and avoids a separate follow-up, so I would do it before merge rather than later.

## records-REC-4 (minor, before-merge)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:628
- Problem: Two problems with the shared tier-1 build-runner item. (1) It is closed on a timing claim the PR's own table contradicts. (2) The dispatch could not measure the per-install cache cost. CONSENSUS D's 'the stress table records the per-install time' is not done, and TODO.md states the conclusion without the caveat PLAN.md gives.
- Evidence: Verified. TODO.md:626-631 says '(they do not, 2026-10-12: every tier-1 row through rzig build took as long as or less than the 548da1a make reference ... 5 to 15 s)'. PLAN.md:1086 says the same, but its table (:1066) has sys at 0.10 min on ubuntu against the reference's 0.02, and every macos-15-intel row is above the reference (cli 0.52 vs 0.14). The runner compile in sys is 0.27 min (16 s) on macos-latest and 0.65 min (39 s) on macos-15-intel, not '5 to 15 s' (:1142). stress.R:303 sets ZIG_LOCAL_CACHE_DIR to one run-wide zig-cache, so the runner compiled once per leg (PLAN.md:1025-1027). PLAN.md:1145-1146 itself says 'Not measured by this dispatch: ... the per-install cache's cost (the run shared one cache)', yet :1096 says 'No time asks for a shared runner'. Minor: :1088's 'make rows by 25 to 40%' is 18-39% from report.json (curl 0.82, wk 0.85).
- Fix: Reword PLAN.md:1086, :1096 and :1140-1146 and TODO.md:626-631. The only per-install cost measured is linux-64 quadprog's about 3 to 4 s (PLAN.md:976-978). The stress run shared one cache, so it says nothing about the per-install cost. Keep the shared-runner item open until a dispatch without ZIG_LOCAL_CACHE_DIR, or with a per-install cache, is measured. Fix the 5 to 15 s and 25 to 40% figures.

Verifier:

The main point of the finding holds against the code and the data. Some of its details do not.

What holds:
1. The stress run shared one build cache. stress/stress.R:303 points ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR at one run-wide zig-cache, and pkgbuild.zig:369 uses that variable ahead of its per-install default. So the build runner compiled once per leg, which is close to how a shared runner would behave. The tier-1 times therefore leave out exactly the cost the shared-runner question is about. PLAN.md:1144-1146 admits this ("Not measured by this dispatch: ... the per-install cache's cost (the run shared one cache)").
2. CONSENSUS.md section D promised that "the stress table records the per-install time". That was not delivered, because the same section's other item (stress.R uses the run directory as the cache) rules it out.
3. Despite that, TODO.md:626-631 (added in this PR's diff) closes the condition "only if the stress table's times ask for it" with "they do not", citing the shared-cache times. PLAN.md:1096 and :1140-1143 conclude the same.
4. The tier-1 rows only match or beat make because the cache was shared. The 3 s warm cost from linux-64 is 0.05 min. Added to ubuntu's tier-1 rows, it makes most of them slower than the 548da1a make reference, for example bit 0.11 vs 0.07, geos 0.11 vs 0.08, wk 0.16 vs 0.13 and magrittr 0.07 vs 0.02.
5. "Every tier-1 row ... took as long as or less than" the reference is literally false for sys on ubuntu (0.10 vs 0.02). The text half-explains this as the runner compile.
6. The PR's own host measurements contradict the "about 3 s" figure outside linux. PLAN.md:1000-1001 shows rzig build slower than make by about 6-10 s on omicron (quadprog 9/3, digest 17/7) and 11-20 s on kappa (quadprog 15/4, digest 18/6, Rcpp 29/9). Yet :1141-1143 uses only the linux 3 s.

What does not hold:
- Comparing macos-15-intel rows with the reference is a misreading. PLAN.md:1018-1019 and :1095 limit the make comparison to linux x86_64 and read intel only against its own make rows.
- wk is a tier-1 row, not a make row, so it does not belong in the "25 to 40%" check. The make rows run from 14% to 40%, with the large ones at 31-40%.
- macos-latest's 0.27 min is the whole sys install. With the package's own compile taken out, the runner compile is about 14 s there.
- "5 to 15 s" fits four of five legs (about 5, 14, 14 and 11 s). Only intel (about 34 s) is outside it.

Severity: these are records only, with no effect on runtime. But the record treats a decision condition as answered when it was not, against an agreed consensus item. The wording fix is cheap and belongs in this PR's own records, so fix it before merge. Keep the shared-runner item open, or state that its per-install cost was not measured and give the per-OS overheads from PLAN.md:1000-1001.

## stress-S1 (minor, before-merge)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:625-631 (also feat-zig-pkg-build/PLAN.md:1140-1144 and 896-899; feat-standalone-toolchain/PLAN.md:2614)
- Problem: The plan item for a shared tier-1 build runner is closed ('they do not', 'not asked for', 'no shared runner needed'), and the item was dropped from PLAN's 'Later items' (the 897-899 list no longer has it, which CONSENSUS H requires). The data used comes from a run that already shared one cache, so it never measured the cost this item is about. The figures that do exist point the other way.
- Evidence: VERIFIED: stress/stress.R:303 sets ZIG_LOCAL_CACHE_DIR (and ZIG_GLOBAL_CACHE_DIR) to one run-wide zig-cache, so the runner compiled once per leg. PLAN:1027 and 1146 say so themselves ('the per-install cost ... not measured'). The figure 'about 3 s warm' is fact 9 (3.1 s warm, 6.6 s cold, linux-64; CONSENSUS fact 9). Add 3.1 s (0.052 min) to each ubuntu tier-1 time: 14 of 16 tier-1 rows then take longer than the 548da1a make reference (glue 0.02 -> ~0.07 vs 0.02, cli 0.09 -> ~0.14 vs 0.14, bit 0.06 -> ~0.11 vs 0.07); only libgeos and vctrs do not. 'below every row's make time but the smallest' (PLAN:1143-1144) is false: 5 of the 16 tier-1 rows (sys, askpass, base64enc, glue, magrittr) take 0.02 min (1.2 s) for the whole make install, which is less than 3 s, and the right comparison is the added cost anyway. INFERRED: on arm, macOS and Windows the sys-row excess (0.21 to 0.27 min vs 0.10 on ubuntu) suggests the per-install cost is 2-3x the linux figure.
- Fix: Reopen the item and restore it to PLAN's 'Later items'. Say the per-install runner cost was not measured by stress, which shared one cache. Record the fact-9 estimate (+3.1 s per tier-1 install on linux-64, about the whole make install time of the small rows). Decide with a dispatch that leaves ZIG_LOCAL_CACHE_DIR unset (e.g. a stress.R flag) on the five runners, or a local per-install timing loop. Drop 'no shared runner needed' from feat-standalone-toolchain/PLAN.md:2614 and feat-zig-pkg-build/PLAN.md:897.

Verifier:

The finding holds on its main points; one sub-claim is overstated.

What I confirmed:
- **The stress run shared one cache.** stress.R:303 sets ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR to the run's zig-cache. pkgbuild.zig:369 reads that variable (`args.cache_dir orelse ZIG_LOCAL_CACHE_DIR orelse <root>/zig-cache`). The sys log shows `--cache-dir .../build/stress/run/zig-cache`. So the build runner was compiled once per leg. In the default setup (N3) it is compiled again for every tier-1 install. Fact 9 puts that at 3.1 s warm and 6.6 s cold on linux-64.
- **PLAN admits it in the same paragraph.** feat-zig-pkg-build/PLAN.md:1146-1147 says "Not measured by this dispatch: ... the per-install cache's cost (the run shared one cache)". Yet the same paragraph (and the 5416d8d TODO.md:628-632, PLAN:893-899 and feat-standalone-toolchain/PLAN.md:2614) concludes "not asked for" / "they do not" / "no shared runner needed".
- **The item was dropped from PLAN's Later items.** CONSENSUS H lists it there as conditional, and 5416d8d removed it. CONSENSUS D also said "the stress table records the per-install time", which this run could not do.
- **The arithmetic checks out.** I recomputed from report.json. Adding 0.052 min to each ubuntu tier-1 row makes 14 of 16 rows slower than the 548da1a make reference. Only libgeos and vctrs stay faster.
- **One "every row" claim is already false without the added cost.** PLAN:1102 and the TODO say every tier-1 row through rzig build "took as long as or less than" the make reference. sys took 0.10 min against 0.02.
- **The comparison likely flatters rzig build.** PLAN itself says the ubuntu leg ran make rows 25-40% faster than the reference, so the measured parity is runner variance. A 3 s cost added to installs of 1-4 s is large in relative terms.

What does not hold:
- The claim that "below every row's make time but the smallest" is false is a misreading. "The smallest" can mean the five 0.02-min rows, and 0.05 min is below every other reference time (0.07 and up). The finding is right, though, that this compares against the wrong baseline.
- The 2-3x higher cost on arm, macOS and Windows is only inferred from the cold sys excess.

Severity and timing: no code or behaviour is wrong. The problem is the record, which closes a consensus-conditional item on a measurement its own text says was not taken. The parent TODO item is still open and still names the shared runner, so I rate it minor rather than major. It should be fixed before merge: it is a cheap text fix in the commit that makes the claim, and CONSENSUS I requires that commit to be reviewed. No scratch files were created.

## stress-S2 (minor, before-merge)

- File: .github/devdocs/feat-standalone-toolchain/PLAN.md:2614 (also feat-zig-pkg-build/PLAN.md:896-897; TODO.md:289-290)
- Problem: Both status sentences say 'no tool to move'. That contradicts the open B24 item: dlltool passed the routing check and moves in the dlltool/as follow-up PR (TODO.md:280-288; PLAN:1139-1140 says so correctly). The underlying claim, 'no Windows make row called dlltool, windres, objdump or strip', rests only on calls being absent from echoed output, which cannot show they were not made.
- Evidence: VERIFIED: TODO.md:285-288 says 'Open until the dlltool/as follow-up PR'. dlltool, windres, objdump and strip are not rzig names (scripts/verify-helpers.sh:40-46), so RZIG_TRACE never prints them. They would show only if make echoed the recipe. winshlib.mk's link recipe is '@'-silent (nm, sed, basename, rm all run unseen). configure.win scripts' commands are not echoed. 6 of the 29 Windows make rows (ragg, hdf5r, ncdf4, RPostgres, s2, igraph) failed before finishing, so their later steps were never seen. objdump is called only by R CMD check, which stress never runs, so its absence is guaranteed by construction. INFERRED: the table is evidence neither for nor against moving any tool.
- Fix: Replace 'no tool to move' with 'the stress table adds no evidence on B24; the dlltool/as follow-up PR stands' in both PLANs. In TODO.md:289-290, qualify the line as '...in make's echoed recipes (binutils calls are not traced; configure.win and @-recipes are silent; R CMD check not run)'.

Verifier:

Partly refuted, mostly confirmed, and the confirmed part is stronger than the finding says.

Refuted: the claim that "no tool to move" contradicts B24.
- In PLAN.md:2614 (feat-standalone-toolchain) and feat-zig-pkg-build/PLAN.md:896-897, the phrase sits in a parenthetical that lists what the stress table showed. It does not describe B24's state.
- The detailed section says "B24: the table names no further tool to move; the dlltool/as follow-up PR stands" (feat-zig-pkg-build/PLAN.md:1139-1140).
- TODO.md:288-290 keeps B24 open ("Open until the dlltool/as follow-up PR") and says the table "adds" no tool.
- The PLAN summaries are terse, but they do not contradict B24.

Confirmed: the evidence claim. TODO.md:289-290 says "no Windows make row called dlltool, windres, objdump or strip", TODO.md:569 repeats it, and PLAN.md:1124 says the same. The method (PLAN.md:1120-1121) only reads make's echoed recipes and rzig's trace lines. The project's own code and records show windres was called:
- build.zig:2539-2540 writes `R_ZIG_RC=${R_HOME}/bin/toolchain/binutils/windres.exe` and `RC=${RC-${R_ZIG_RC}}` into Windows Rcmd_environ.
- CMake treats a Clang mingw compiler like GNU (cmake-4.4 Platform/Windows-Clang.cmake else-branch, then Windows-GNU.cmake:162-167), so it calls `enable_language(RC)` and takes the `RC` environment variable.
- RcppParallel 6.2.1 builds its bundled oneTBB with CMake on Windows. `src/tbb/src/{tbb,tbbmalloc,tbbmalloc_proxy}/CMakeLists.txt` add .rc sources under WIN32.
- RcppParallel's install.libs.R captures CMake's output (`system2(..., stdout=TRUE, stderr=TRUE)`) and prints it only on failure. The `tbb` rule in its Makevars is @-silent.
- RcppParallel is a configure.win make row, and it finished DONE in run 38317654371 (stress-38317654371/windows-latest/logs/RcppParallel.log shows only "*** building tbb").
- The repo's own records agree. packages.tsv:56 records the 2026-10-08 Windows failure as "windres is not on PATH", and the round-2 fix as "CMake, windres through RC". stress/results/2026-10-08-round2.md:506 says "windres through `RC`. That covers RcppParallel's TBB with its `.rc` file".

So a Windows make row in this dispatch almost certainly ran binutils/windres.exe three times, unseen. The same blind spot makes the "cmake in 2 rows (biocmake, Rhdf5lib)" count at PLAN.md:1122-1123 miss RcppParallel's CMake build. The finding's other points also hold:
- winshlib.mk's link recipe is @-silent.
- configure.win output is not echoed.
- Six of the 29 Windows make rows failed: ragg, hdf5r, ncdf4, RPostgres, s2 and igraph.
- objdump is only called by R CMD check, which stress.R never runs.

Severity is minor: this is a records-only error and no decision changes. Nothing leaves the group, windres stays in binutils/ with RC pointing at it, and the dlltool/as and windres-front PRs still stand. Fix it before merge because the text change is cheap and the follow-up needs it right:
- Change TODO.md:289-290, TODO.md:569 and PLAN.md:1120-1124 to say that binutils calls are not traced and CMake, configure.win and @-recipes run unseen.
- Note that RcppParallel's TBB build calls windres through Rcmd_environ's RC. This is evidence for the windres front, not against it.
- Add RcppParallel to the cmake rows.
- The two PLAN summaries can keep "no further tool to move" as their wording.

## stress-S3 (minor, before-merge)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1119-1125 (used at 1135-1136; TODO.md:567-569)
- Problem: The list of tools the Windows rows ran is partly a grep artifact. The phase 7 re-scope cites these counts as its evidence for keeping sed, coreutils and pkg-config.
- Evidence: VERIFIED by grep of windows-latest/logs: (a) 'sed in 5 (stringi, igraph, ragg, s2, Rhdf5lib)'. No log contains a sed command; every match is the substring 'sed ' inside 'used ', 'unused ', 'passed ' or 'biased ' (compiler warnings such as 'set but not used', and cmake's 'were not used'). (b) 'cmake in 2 (biocmake, Rhdf5lib)'. biocmake.log is 14 lines with no cmake call; the match is the package name. Only Rhdf5lib ran cmake ('Building for: MSYS Makefiles'). (c) 'cp/mkdir/rm in 5'. Only 'rm -f'/'rm -Rf' appear (askpass, filelock, units, ncdf4, Matrix); there is no cp or mkdir. (d) 'pkg-config in 2 (s2, igraph)' undercounts. pkg-config results are also printed by ragg, textshaping, systemfonts, xml2, openssl and RPostgres ('using ... from Rtools'), and ncdf4's 'debug' library comes from netcdf.pc. (e) TODO.md:567-568 says 'the make rows ran ... cmake (Rhdf5lib)', but Rhdf5lib is not one of the 29 make rows. The conclusions still hold for another reason: winshlib.mk's silent link recipe runs nm, sed (twice), basename, echo and rm in every completed Windows make row.
- Fix: Rewrite the paragraph and the TODO clause using recipe-level evidence: winshlib.mk's def/link recipe (nm, sed, basename, rm) in every make row; configure.win scripts (sh); pkg-config in at least 9 rows (by their messages); cmake in Rhdf5lib only (its configure, which drives make through CMake's Makefiles generator); rm echoed in 5 rows. Drop the sed, cmake and cp/mkdir counts.

Verifier:

I checked each part against the logs in stress-38317654371/windows-latest/logs (install logs only). All five parts hold.

(a) No log contains `sed` as a word. All five files that match the substring 'sed ' (ragg, s2, igraph, Rhdf5lib, stringi) match only inside compiler warnings: 'set but not used', 'unused parameter', 'passed as a const pointer', cmake's 'variables were not used', and s2's '-labsl_exponential_biased'.

(b) biocmake.log has 14 lines and no cmake call. The only match is the package name. Only Rhdf5lib ran cmake: its log shows '-- Building for: MSYS Makefiles'.

(c) No log contains a cp or mkdir command. The only echoed rm commands ('rm -f' or 'rm -Rf') are in askpass, units, filelock, ncdf4 and Matrix.

(d) The pkg-config count of 2 is too low. Six packages have Makevars.win files (copies in stress/kappa/srcpeek) that call `$(shell $(PKG_CONFIG) --libs ...)` and print 'using ... from Rtools' when pkg-config returns libraries: ragg, textshaping, systemfonts, xml2, openssl and RPostgres. Their logs print that message. ncdf4's Makevars.ucrt calls `pkg-config --libs netcdf libcurl`, which is where '-ldebug' in its failing link line comes from.

(e) In tiers.tsv, Rhdf5lib's Windows tier is '-': it has a configure.win and no src/. So it is not one of the 29 make rows that TODO.md:567-568 credits with 'cmake (Rhdf5lib)'.

The paragraph says its counts come from the logs (PLAN.md:1119-1125). It names sed as an observed tool even though no log shows a sed call. It also says 'coreutils (the cp/mkdir/rm recipes)' (PLAN.md:1135), but no log shows cp or mkdir.

The conclusions still hold for another reason. In R 4.6.1, share/make/winshlib.mk's silent $(SHLIB) recipe runs `$(shell basename ...)`, `echo`, `$(NM) | $(SED) -n ... | $(SED) $(ADDQU)` and `$(RM) tmp.def`. So the phase 7 re-scope is still right to keep sed, coreutils, nm and pkg-config.

The defect is false evidence in the decision record. It does not change any code or decision, so I rate it minor rather than major. Because these lines are new in the PR (git diff e1ce179 5416d8d), they are cheap to fix in a docs-only edit before merge, rather than landing a wrong record on main that phase 7 cites.

## stress-S6 (minor, before-merge)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1027-1029 (and the 'Not measured' list at 1144-1146)
- Problem: 'no row's smoke compiled at run time' is true but vacuous: the g3 g4 selection has no row whose smoke compiles. The run therefore never exercised R CMD SHLIB or run-time compilation, which is in the agreed scope, and which CONSENSUS checklist I asked the table to report ('rows whose smoke compiles at run time (Rcpp, rstan ...)'). The record does not say this.
- Evidence: VERIFIED: stress/packages.tsv gives the compiling smokes (Rcpp's cppFunction, rstan's stan_model) to g1 rows. In this run Rcpp is only a dependency and its smoke is TRUE (ubuntu-latest/smoke/Rcpp.R: 'res <- local(TRUE)'). The dispatch ran TARGETS 'g3 g4'.
- Fix: Reword: 'g3 g4 have no smoke that compiles; R CMD SHLIB (run-time compilation, pkgbuild's probe) was not exercised'. Add it to the 'Not measured' list. Later, run a g1 dispatch (Rcpp, rstan) with trace.

Verifier:

I could not refute the core claim; the code and data back it.
- **Run inputs:** the dispatch ran `--trace g3 g4` (ubuntu-latest `report.json` info.args).
- **No g3 or g4 smoke compiles:** every smoke in `stress/packages.tsv` for g3 and g4 is a plain call such as `curl_version`, `stri_info`, `geos_version` or `nloptr`. The smokes that compile (`Rcpp::cppFunction`, `rstan::stan_model`) are on g1 rows.
- **Rcpp ran only as a dependency:** its smoke file is `res <- local(TRUE)` (`stress-38317654371/ubuntu-latest/smoke/Rcpp.R`, the same on every leg). No file under `smoke/` contains cppFunction, sourceCpp, evalCpp or stan_model.

So PLAN.md 1027-1029, "no `*-smoke.log` holds an rzig trace line, so no row's smoke compiled at run time", is true only because of how the rows were chosen, and the record does not say so. CONSENSUS checklist I asked the table to report "rows whose smoke compiles at run time (Rcpp, rstan: R CMD SHLIB, still make)". The 'Not measured by this dispatch' list at 1144-1146 names `builder = make`, the preflight and the per-install cache cost, but not run-time compilation.

**Where the finding overstates:**
- "Never exercised R CMD SHLIB" is too broad. The 29-30 make rows per leg went through `run_shlib` and `.shlib_internal`, the same Makeconf/shlib.mk make path that R CMD SHLIB uses. What was never invoked is the R CMD SHLIB command itself: run-time compilation and pkgbuild's probe.
- The PR does not change that path. Patch 0013's hook sits only in install.R's `run_shlib`.
- Other tests in the PR cover it: `contract-test.sh`'s `evalCpp` and `verify-bundle.sh` scenario 2's R CMD SHLIB checks. PLAN.md records `contract` passing with `evalCpp`.

The gap is the accuracy of the record, not missing coverage of anything this PR changed. Severity is minor. The fix should go in before merge because it is cheap and this doc commit exists to fill in checklist I, which the phase 3 session reviews. Suggested fix:
- Reword the sentence to: "g3 g4 have no smoke that compiles at run time (Rcpp ran only as a dependency, smoke TRUE), so the R CMD SHLIB command (run-time compilation, pkgbuild's probe) was not exercised by this dispatch; contract's evalCpp and verify-bundle scenario 2 cover it."
- Add it to the 'Not measured' list.
- A g1 dispatch with trace can come later.

## stress-S8 (minor, before-merge)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1105 (TODO.md:566; feat-standalone-toolchain/PLAN.md:2613)
- Problem: The reason labels are imprecise. Four of the nine Windows rule rows are src/Makevars, not .win/.ucrt. The status sentence says the make rows are 'for configure scripts and Makevars rules' and leaves out 8 of the 29 Windows make rows.
- Evidence: VERIFIED from the Windows 'needs make' lines: jsonlite, Matrix, rlang and timechange give 'src/Makevars has a rule or target line'. askpass, filelock, libgeos and zip give Makevars.win; units gives Makevars.ucrt. So 'the six above (.win or .ucrt)' is wrong for four of them. On Windows, $(shell) (5), conditionals (2) and include (1) account for 8 make rows.
- Fix: Label the class 'Makevars rule (src/Makevars, .win or .ucrt) (9)'. In feat-standalone-toolchain/PLAN.md:2613 say '... configure scripts, Makevars rules and (Windows) $(shell), conditionals and include'.

Verifier:

The finding is real. I checked it against 5416d8d and the stress data, and every cited line is new in the PR (e1ce179..5416d8d).

1. **PLAN.md:1105.** The row reads "windows | Makevars.win/.ucrt has a rule or target line (9) | the six above (`.win` or `.ucrt`), askpass, libgeos, units (`.ucrt`)". The Windows logs show something else:
   - jsonlite, Matrix, rlang and timechange print "needs make: src/Makevars has a rule or target line". These packages have no Makevars.win, so R uses src/Makevars on Windows.
   - Only filelock and zip of the "six above" give Makevars.win, along with askpass and libgeos. units gives Makevars.ucrt.
   - So the parenthetical is wrong for 4 of the 6, and the row label is wrong for 4 of the 9. The count of 9 is right.

2. **feat-standalone-toolchain/TODO.md:566** says "9 Makevars.win/.ucrt rules". It has the same mislabel.

3. **feat-standalone-toolchain/PLAN.md:2613** says "the rest through make for configure scripts and Makevars rules". That is complete for unix (30 = 24 configure + 6 rules). On Windows the 29 make rows are 12 configure.win + 9 rules + 5 `$(shell)` + 2 conditionals + 1 include. So the sentence leaves out 8 Windows rows: qs2, ragg, stringfish, systemfonts, textshaping, gert, ncdf4 and fstcore.

I counted these from tiers.tsv (all 29 Windows rows) and confirmed the label in the raw windows-latest/logs/{jsonlite,rlang,zip}.log.

Severity is minor because only the wording is wrong. The tier counts and the conclusions still hold: the four src/Makevars rows need make on Windows either way, and the list of tools that stay in the group does not change. Fixing it before merge is cheap (three wording edits in the PR's own records) and keeps a factual error out of the durable record. The suggested fix is correct.

## tests-T2 (minor, before-merge)

- File: recipe/test-toolchain.R:58-60, 67-73 (make_ref); also 195 (rzigar)
- Problem: make_ref's only builder assertion, no 'rzig build:' line in the log, runs with RZIG_TRACE unset: line 60 unsets it before every make_ref call. A tier-1 install through rzig build prints no 'rzig build:' line without RZIG_TRACE. So the check passes whether or not R_ZIG_PKG_BUILDER=make takes effect, and the 'through make too' runs for rzigc, rzigz, rzigf and rzigfl are not asserted. PLAN.md:835-836 and :999 record them as asserted. rzigar's builder (Makevars rule, make) is not asserted either, although its 'needs make' line prints without trace.
- Evidence: Verified by experiment: R CMD INSTALL of an rzigc copy through the default builder with no RZIG_TRACE gave 0 lines matching 'rzig build:' (exit 0). The make-path log also had 0. pkgbuild.zig prints the tier line only under RZIG_TRACE (:390-397); needsMake (:537-540) prints always. The make-path log does contain make's echoed recipes, `<R_HOME>/bin/toolchain/zig-cc -std=gnu23 ... -c one.c -o one.o`, which an rzig build log does not.
- Fix: Set RZIG_TRACE=1 inside make_ref, with on.exit unset, so the negative check means something. Or assert a positive make marker: `any(grepl("^\\S*bin/toolchain/(zig-c|gcc|g\\+\\+)", log))`. Add `stopifnot(any(grepl("rzig build: rzigar needs make: ", log)))` for rzigar, via install_log.

Verifier:

The main claim holds against the code and in a rerun. At 5416d8d, recipe/test-toolchain.R:58-60 sets RZIG_TRACE=1 for rzigc's first install only and unsets it at :60. make_ref (:67-73) then checks only `!any(grepl("rzig build:", log))`. In pkgbuild.zig, a successful tier-1 run prints its lines ("tier N, root ..." and the zig build command, :390-397) only under RZIG_TRACE. needsMake (:537-540) and the error paths print without it. So for rzigc, rzigz, rzigf and rzigfl the negative check passes whether R_ZIG_PKG_BUILDER=make takes effect or not.

I reran it in a scratch lib against the worktree's build/compile-tree/slim R (cache dirs in scratch, scratch since deleted). For rzigc, the default builder without trace gave 0 'rzig build:' lines, RZIG_TRACE=1 gave 2 ('tier 1, root ...' and the zig build command), and R_ZIG_PKG_BUILDER=make gave 0. All three exited 0. Only the make log had make's echoed `.../bin/toolchain/zig-cc -std=gnu23 ... -c one.c -o one.o` lines.

The PR's own similar checks trace the make leg: pkg-parity.sh exports RZIG_TRACE=1 (:96) before its :164 grep, and wheel-test.sh:270 passes RZIG_TRACE=1 with R_ZIG_PKG_BUILDER=make. test-toolchain.R is the outlier. PLAN.md:999 reads "asserts ... rzigc, rzigz, rzigf, rzigfl through make too", and the kappa row says "test-toolchain.R's builder assertions pass", so the record overclaims.

I rate it minor, not major:
- The make-reference installs really run and are load-tested.
- The switch itself is a one-line `if (builder == "make") return(NA)` in patch 0013, and pkg-parity.sh and wheel-test.sh already check it under trace.

What remains is a check that can never fail plus an overclaiming record. The fix is one line (RZIG_TRACE=1 inside make_ref with on.exit, or a positive grep for a make-echoed toolchain line). The project explicitly treats checks that pass trivially as defects (PLAN records one in contract-test), so fix it before merge.

The rzigar part of the finding does not hold as a defect. rzigar builds and loads with 42 from foo/libfoo.a, which only its Makevars rule's $(AR)/$(RANLIB) recipe produces. A Makevars with rules is not tier 1, and a tier-1 link without that archive would fail. So its builder is asserted by function, and the test only says rzigar takes make; it doesn't claim to assert it.

## tests-T5 (minor, before-merge)

- File: stress/packages.tsv:49 (fst), 50 (geos), 64 (lme4)
- Problem: Three of the new builder notes contradict the stress table this PR records. fst says 'fstcore too', but fstcore needs make on every OS. geos says 'libgeos too', but libgeos is make on Windows. lme4 says 'nloptr and Matrix through make', but nloptr is tier 1 on Windows. Also, lme4 and mlpack are g1 rows, which dispatch 38317654371 (g3 g4) did not run: their notes rest only on FINDINGS coverage-C11's linux --classify.
- Evidence: Verified from the stress-38317654371 tiers.tsv and tiers-intel.tsv. fstcore is 'make: a configure script' on ubuntu-latest, ubuntu-24.04-arm, macos-latest and macos-15-intel, and 'make: src/Makevars.ucrt has an include' on windows-latest. libgeos is 1 on unix and 'make: src/Makevars.win has a rule or target line: $(SHLIB): $(STATLIB)' on windows. nloptr is 1 on windows-latest. PLAN.md's own table (:1076, :1084, :1108) agrees with tiers.tsv.
- Fix: fst: 'fst through rzig build (tier 1); fstcore through make (configure; Makevars.ucrt include on Windows)'. geos: 'libgeos too on unix; make on Windows (Makevars.win rule)'. lme4: 'nloptr through make on unix (configure), tier 1 on Windows'. Note that the g1 rows are from the linux classify, not a dispatch.

Verifier:

The finding holds against the code and the data. The notes were added in 47e8436 and not changed when 5416d8d recorded the stress results. At 5416d8d, stress/packages.tsv says: line 49 (fst) "tier 1; fstcore too", line 50 (geos) "tier 1; libgeos too", and line 64 (lme4) "...minqa on unix...; nloptr and Matrix through make".

The raw install logs of dispatch 38317654371, not just the extracted tiers.tsv, contradict all three:
- fstcore prints "rzig build: fstcore needs make: a configure script" on ubuntu-latest and macos-latest, and "needs make: src/Makevars.ucrt has an include" on windows-latest. tiers.tsv and tiers-intel.tsv agree for ubuntu-24.04-arm and macos-15-intel, so fstcore is make on all five legs.
- libgeos prints "needs make: src/Makevars.win has a rule or target line: '$(SHLIB): $(STATLIB)'" on Windows. It is tier 1 on unix.
- nloptr prints "tier 1, root .../nloptr/src/.rzig" on Windows.

The PR's own PLAN.md agrees with the logs:
- libgeos is "make 3.05" on Windows.
- nloptr is "0.04 (tier 1)" on Windows.
- fstcore is in both the unix configure list and the Windows include list.
- One line says "Windows differs from unix in five rows: gmp, gsl and nloptr are tier 1 there...".

The fst note is wrong even against FINDINGS coverage-C11, the evidence it was based on. That section says "fstcore, nloptr and RcppArmadillo exit 3 (configure)" in the linux classify.

The g1 part also holds. The dispatch ran "packages g3 g4" (PLAN.md:1017). lme4, mlpack, RcppEigen, minqa, nlme and MASS do not appear in tiers.tsv; only Rcpp and lattice do, as dependencies. So the lme4 and mlpack notes rest only on the linux --classify in FINDINGS.

I lower the severity from major to minor. The notes column is free text that stress.R does not use as data: it reads the file with read.delim, and the README header describes the column as documentation. The error changes no build, test or expectation. It is still an error this PR introduced, it contradicts the PR's own stress record, and the fix is a one-line edit per row. That makes before-merge the right time to fix it. I created no scratch files.

## phase3-P3-10 (minor, later)

- File: .github/workflows/upstream-zig.yaml:43-44, 64-65, 76-82
- Problem: Inferred risk: these runs never happened. The upstream-zig legs never ran on PR #25: runs 38302765022 and 38305799647 were skipped, and the PR's only label is full-ci. Phase 3's PR #24 ran them before its merge (38247190926, success). After this merge, build-r.yaml runs pkg-parity, contract and verify-package through rzig build on those legs. Several paths have never run under upstream zig in CI: the `zig build` of the share/zig/rpkg roots on Windows (no wheel exists there), tier 2 with --system, and pkg-parity's argv comparison.
- Evidence: `gh run list --workflow upstream-zig.yaml` shows only skipped runs for feat-zig-pkg-build. `gh pr view 25 --json labels` returns full-ci only. The user's both-zigs rule treats upstream as the reference.
- Fix: Add the `upstream-zig` label to PR #25 and wait for the five upstream legs before merging. If that stays a release-only gate, record that it was not run in PLAN.md's CI line.

Verifier:

The facts hold, with one overstatement, and the risk is still only inferred.

What I confirmed:
- `gh run list --workflow upstream-zig.yaml` shows that both runs on feat-zig-pkg-build were skipped: 38302765022 and 38302764314 on 47e8436, and 38305799647 on 45892fb.
- Since PR #24's 38247190926 (success on 548da1a), there has been no successful or dispatched upstream run. The only later non-skipped run is 38276959389 on 7af9c22, which was cancelled. No run has happened on main since the merge either.
- PR #25's only label is full-ci.
- upstream-zig.yaml calls build-r.yaml, and the PR adds the pkg-parity step there. Patch 0013 sends R CMD INSTALL through `rzig build` by default.
- The PR's own tests ran upstream zig only for rzig-test on linux-64 (unit tests plus parity-test). The kappa and omicron chains used conda-forge zig.
- So under upstream zig, three things have never run anywhere: rzig build on Windows (share/zig/rpkg roots, `rzig def`), tier 2 with `--system`, and pkg-parity's argv comparison.
- FINDINGS.md:176 even assumed "the gated upstream legs run pkg-parity with the PyPI ziglang binary". Without the label, they never did.

The overstatement: unix tier 1 is not uncovered. wheel-test asserts `rzig build: tier 1` under PyPI ziglang, which is byte-identical to upstream zig. In run 38305799627, the wheel step passed on all four unix minimal legs. The finding's list leaves unix tier 1 out, so the gap is mainly Windows, tier 2 and pkg-parity.

Why minor and later rather than before-merge:
- The workflow and the user's both-zigs/ci-tiers decisions make upstream-zig a gate on release tags, on dispatch or on a label, not a check on every PR. Several earlier PRs that changed rzig merged without it.
- I found no concrete mechanism that would break. Tier 1 is Run steps that call the toolchain compilers, which the wheel already runs under upstream zig. The conda-only libc++ mirror (`ZIG_LIB_DIR`) is absent under upstream zig.
- PR #25 is already merged (main 07e12c0), so "label before merging" no longer applies.

Remaining action: run `gh workflow run upstream-zig.yaml` on main before the phase-4 build bump or publish, and add a line to PLAN.md's CI record saying the upstream legs were not run on PR #25.

## phase3-P3-3 (minor, later)

- File: scripts/verify-bundle.sh:943, 948
- Problem: Verified. The cf package is installed with shape_path=/usr/bin:/bin, and the comment and message say 'no make (and no flang) on PATH at all'. /usr/bin/make exists on the GitHub ubuntu and macOS runners and on gamma (/usr/bin/make checked here). The check still holds because 'rzig build: tier 1' is asserted, but the message records something that did not happen.
- Evidence: verify-bundle.sh:943 `# as a package: no make and no flang on PATH at all`, :944 `shape_path="/usr/bin:/bin"`, :948 echo '... no make on PATH)'. `ls /usr/bin/make` succeeds on this host.
- Fix: Say 'no flang on PATH'. To actually prove 'no make', give shape_path a directory without make, such as "$BUNDLE_DIR/bin", as pfC uses.

Verifier:

Holds against the code at 5416d8d, and the PR introduced the lines (git diff e1ce179 5416d8d adds them). In scripts/verify-bundle.sh, line 943 says "# as a package: no make and no flang on PATH at all", line 944 sets shape_path="/usr/bin:/bin", and shape_pkg (line 778) runs R CMD INSTALL with PATH="${shape_path:-$pkg_path}", so this install's PATH is exactly /usr/bin:/bin. The block is unix-only (inside `if [ "$OS" != windows ]`, line 718). /usr/bin/make and /bin/make both exist on gamma (checked with ls). /usr/bin/make is also standard on the GitHub ubuntu images and is the Xcode shim on macOS. In CI run 38305799627 the line "== compiled package verified: $(FLIBS) links with no Fortran compiler (C; R CMD INSTALL, rzig build, no make on PATH)" is printed on ubuntu-latest, ubuntu-24.04-arm, macos-latest and macos-15-intel. So that message, and the "no make" part of the comment, describe a condition that did not hold. The "no flang" part is accurate (no /usr/bin/flang*). The test is still valid: shape_pkg requires the 'rzig build: tier 1' line and rejects make output in the log. So make was never used. The test just does not prove that make was missing. This is wording only, with no effect on correctness. The pfC preflight block (PATH="$BUNDLE_DIR/bin") is the test that really proves "no make". The fix is to reword (say "no flang on PATH") or set shape_path to a directory without make.

## phase3-P3-4 (minor, later)

- File: pixi.toml:87-89, 99; scripts/pkg-parity.sh:46, 253
- Problem: Verified. The contract comment says 'data.table, pak and ps through make', but contract-test.sh asserts pak = 'mixed' (82). pkg-parity's comments say 'no make or sh on PATH', but on unix the restricted PATH holds a symlink to sh (pkg-parity.sh:268, and the header's own line 47).
- Evidence: contract-test.sh:81-82 `want <- c(..., pak = "mixed", ps = "make")`. pkg-parity.sh:268 `ln -s "$(command -v sh)" "$NOMAKE/sh"`.
- Fix: Change pak to mixed (its embedded cli, lpSolve, pkgcache and yaml go through rzig build, keyring and zip through make). Say 'no make on PATH (unix: sh, zig, flang only; Windows: System32 and flang)'.

Verifier:

Both mismatches hold at 5416d8d, and this PR introduced both comments.

(1) pixi.toml:87-89 says "data.table, pak and ps through make". contract-test.sh asserts pak = "mixed" at lines 97-98, not the 81-82 the finding cites. Its own header (lines 8-11) and the comment at lines 87-89 say pak's embedded cli, lpSolve, pkgcache and yaml go through rzig build, and keyring and zip go through make. The contract job is green in run 38305799627, so "mixed" is the real outcome and the pixi.toml comment is wrong.

(2) Three places say "no sh on PATH": pixi.toml:99 and pkg-parity.sh:46 ("an install with no make or sh on PATH") and the section banner at pkg-parity.sh:253 ("no make, no sh"). On unix the restricted PATH does hold sh: line 268 runs `ln -s "$(command -v sh)" "$NOMAKE/sh"`, and the very next header line (47) says "a directory holding only sh, zig and flang". The claim is only true on Windows, where PATH is the copied flang plus System32.

Only comments are affected, and no test or behavior changes. The suggested fix is correct: make pak "mixed" and reword to "no make on PATH". Minor; it can wait, or ride along with any other touch-up before merge.

## phase3-P3-5 (minor, later)

- File: scripts/compile-tree.sh:6-8, 22-24; pixi.toml:159
- Problem: Verified. Phase 3's records name contract and stress as the compile tree's users, and say only verify-tree, hermetic and package read the R tree. pkg-parity is now a third compile-tree consumer (pixi.toml:101), and it runs the base R ($PREFIX) in place for its no-make install (pkg-parity.sh:58, 274), not on a copy as hermetic-check does.
- Evidence: compile-tree.sh:7 'contract and stress compile packages with it'. compile-tree.sh:22-24 'The R tree and the toolchain tree are only read: verify-tree, hermetic and package see the base'. pkg-parity.sh:274 `env -i ... "$BASE_R_EXE" CMD INSTALL`.
- Fix: Add pkg-parity to both comments, and say that it installs into its own library with the base's R in place, writing nothing under $PREFIX.

Verifier:

This is real, but it is only stale comments. At 5416d8d, pixi.toml:101 makes pkg-parity depend on compile-tree, and pkg-parity.sh:57 sets TREE="$COMPILE_TREE", so pkg-parity is now a third user of the compile tree. The PR never touched scripts/compile-tree.sh: it is absent from `git diff --stat e1ce179 5416d8d`. So the phase 3 lists of the compile tree's users still name only contract and stress:
- compile-tree.sh:6-8, "contract and stress compile packages with it (their pixi tasks depend on compile-tree)". This is now incomplete, because pkg-parity's task depends on compile-tree too.
- pixi.toml:159, the same wording.
- The same two-name list also appears in env.sh:85-86 and pixi.toml:38. The finding does not cite these, and they should get the same fix.

compile-tree.sh:22-24 lists verify-tree, hermetic and package as the users that see the base. pkg-parity is now also one, and it depends on the base being the base alone: pkg-parity.sh:75 checks that $BASE_RH/bin/toolchain has no usr/. Its no-make install runs the base R in place (pkg-parity.sh:58, 66, 274: `env -i ... "$BASE_R_EXE" CMD INSTALL -l lib-nomake`). It does not work on a copy, as hermetic does.

The finding over-reads one point. In "The R tree and the toolchain tree are only read", the word "only" means the trees are read and never written. It does not mean that only the three listed tasks read them. The list of users is still missing pkg-parity, so the finding stands.

As far as I can tell, nothing pkg-parity runs writes under $PREFIX:
- It installs into $WORK/lib-nomake.
- HOME, TMPDIR and LOCALAPPDATA point at $WORK/work.
- ZIG_GLOBAL_CACHE_DIR is env.sh's cache.
So the "leaves the tree as it was" claim in verify-tree.sh:77-83 still holds, although that comment also leaves pkg-parity out of its list. In build-r.yaml, pkg-parity runs between verify-tree and verify-package.

The code is correct. The gap is incomplete enumerations in the comments, so this is minor and can wait until after the merge: add pkg-parity to compile-tree.sh:6-8 and 22-24, pixi.toml:38 and 159, and env.sh:85-86.

## phase3-P3-6 (minor, later)

- File: scripts/verify-bundle.sh:302, 315 (with zigbuild/tools/rzig/pkgbuild.zig:369, scripts/env.sh:176)
- Problem: The code path is verified; the cache growth is inferred. env.sh exports ZIG_LOCAL_CACHE_DIR (the dev tree's build/zig-cache/zig-<key>/local), and verify-bundle's zig_env passes it into every env -i install. contract-test.sh inherits it from env.sh. rzig build takes it as its --cache-dir, so the relocated-bundle scenarios 2 and 3 and contract never exercise the per-install cache a user gets by default (N3). Only pkg-parity unsets it (pkg-parity.sh:94). Each such install also adds Run entries that are never reused (fact 9) to the dev tree's local cache.
- Evidence: pkgbuild.zig:369 `args.cache_dir orelse ctx.getenv("ZIG_LOCAL_CACHE_DIR") orelse <root>/zig-cache`. verify-bundle.sh:315 `zig_env=(... ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR")`.
- Fix: Leave ZIG_LOCAL_CACHE_DIR out of zig_env, which only rzig build reads now, or unset it for the R CMD INSTALL runs, so the scenarios test the user's default. Optionally assert that no build root is left after pfC.

Verifier:

I could not refute it. The finding holds against the code at 5416d8d and against the worktree's on-disk cache.

**Code path**
- `scripts/env.sh:176` exports `ZIG_LOCAL_CACHE_DIR=$BUILD_DIR/zig-cache/zig-<key>/local`.
- `verify-bundle.sh` sources `env.sh` at line 86. Its `zig_env` at lines 302 and 315 passes that variable into every `env -i` run. Every `R CMD INSTALL` that goes through rzig build uses `zig_env`: pfC at 572/585, the shapes at 778, the C++/Fortran/FLIBS/OpenMP blocks at 806-1043, and Windows scenario 3 at 1386-1500.
- `contract` runs `zig-contract.sh`, which sources `env.sh` and execs `contract-test.sh`, so R inherits the variable there too.
- `pkgbuild.zig:369` reads `args.cache_dir orelse ZIG_LOCAL_CACHE_DIR orelse <root>/zig-cache`, where `root` is `<out>/.rzig` (line 296). So in scenarios 2/3 and in contract, the user's default per-install cache (N3) is never used.
- Only `pkg-parity.sh:94` unsets the variable. `stress.R:303` and `test-toolchain.R:18` set it on purpose.

**Growth**
The worktree's `build/zig-cache/zig-2588079272-305049256/local/o` has rzig-build outputs written since 2026-10-11. There are two entries each of `pfC.so`, `Rcpp.so`, `quadprog.so`, `minqa.so`, `yaml.so`, `pkgcache.so` and `lpSolve.so` (the verify-bundle and contract tier-1 packages), plus six of `rp.so`. That is one new entry per run, never reused, which matches fact 9. The directory is 826 MB, though most of that is R's own build.

**Why only minor / later**
- The default path is tested elsewhere. `pkg-parity` runs on every CI leg (`build-r.yaml:122-123`) with the variable unset, on the compile tree and in an `env -i` install on the base. It checks that no `zig-build` dir and no build root are left behind, and that the global cache count does not change.
- Cache placement depends only on the build root inside the package's `src/`, not on `R_HOME`. So the relocated bundle adds little coverage.
- The growth only affects the developer's `build/` (CI runners are ephemeral), never a user's machine.

**Correction to the suggested fix**
"Which only rzig build reads now" is not accurate. `zig cc`, which rzig calls in its compile mode and inside the Run steps, also reads `ZIG_LOCAL_CACHE_DIR`. Dropping the variable from `zig_env` would move those objects into the keyed global cache. That is harmless, but it is not a no-op.

## phase3-P3-7 (minor, later)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:600-604
- Problem: Verified. The N5 record lists r-zig-slim's changes as 'patches 0012, 0013, share/zig/rpkg' and r-zig-toolchain's as 'the rzig name'. It leaves out the rewritten 0009 (slim) and rzig's new modes (--rzig-check=package, build, def). It also leaves out the coupling these create: a new r-zig-slim with an old r-zig-toolchain stops every compiled install. The old rzig answers --rzig-check=package with exit 2, and 0013 refuses a TC that has CC but no 'rzig'. The exact pin is on the build string `_8`, which N5 keeps unchanged for different content.
- Evidence: 0009 runs `system2(rzig, "--rzig-check=package")` (patch lines 77-80). Main's check.parse returns error.UnknownCheck for 'package', which main.zig maps to exit 2. 0013's rzig_build calls pkgerrmsg('... older than this R'). recipe.yaml:151 is 'number: 8'.
- Fix: Name all four changes and add one line: phase 4 must bump both packages together, and until then no channel may mix a locally built `_8` with universe's `_8`.

Verifier:

The finding holds against the code and the record at 5416d8d, though it is narrower than stated.

**The TODO text.** Lines 600-604 of feat-standalone-toolchain/TODO.md say the PR changes r-zig-slim "(patches 0012, 0013, share/zig/rpkg)" and r-zig-toolchain "(the rzig name)".
- The PR also rewrites 0009, which is in r-zig-slim: 96 lines change in 0009-install-compile-preflight.patch.
- "The rzig name" is narrower than FINDINGS.md:468's "(rzig)". The rzig binary itself changed: check.zig, def.zig, makefile.zig, pkgbuild.zig, pkgplan.zig and main.zig all gain new modes.
- The PR's own PLAN.md (lines 789-798) does record the 0009 rewrite and 0013's "older than this R" stop. So only the TODO summary and the N5 row are incomplete, not the whole record.

**The coupling.** It is real in the code:
- The new 0009 (lines 59-82) runs `system2(<TC>/zig-cc|gcc.exe, "--rzig-check=package")` for every package with src/ (or a configure script R runs). It calls pkgerrmsg on any non-zero status. Only a user Makevars or R_ZIG_NO_PREFLIGHT skips it.
- Universe's build 8 rzig does not know that check. Build 8 was published from 888faa6, and d51bf3a, which added check.zig, is an ancestor of it.
- In that rzig, check.parse only knows fortran and build-tools, so "package" returns error.UnknownCheck. main.zig then prints the usage text and returns 2.
- So a new r-zig-slim with universe's r-zig-toolchain _8 stops every compiled install. If the preflight is skipped, 0013 stops instead: "has zig-cc but not rzig: the r-zig toolchain is older than this R".
- Nothing stops the solver from making this mix. r-zig-toolchain pins r-zig-slim with `pin_subpackage(exact=True)` (recipe.yaml:469), and the build number stays at 8 (recipe.yaml:151). A local _8 and universe's _8 therefore carry the same build string unless the variant hash differs.

**How likely the mix is.** It is unlikely in practice. conda-package builds both outputs together. The consume test (build.yaml:306) and stress.R:220 list the local channel first. With strict priority, both packages then come from the local channel. CI run 38305799627 passed conda-package on all five platforms.

**The proposed fix.** Its first half is automatic: the recipe has one `number` for both outputs, so phase 4's bump already moves both. The useful part is the documentation fix:
- name 0009 and rzig's new modes in the TODO line;
- add a one-line warning not to mix a locally built _8 with universe's _8 before phase 4.

That makes it a minor, docs-only item that can wait until later.

## phase3-P3-8 (minor, later)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:628-631 (and feat-zig-pkg-build PLAN.md:1086)
- Problem: Verified. The phase 3 TODO says 'every tier-1 row through rzig build took as long as or less than the 548da1a make reference'. sys is a tier-1 row and took 0.10 min against the reference's 0.02 (the build-runner compile). The TODO also drops the PLAN's caveat that the cross-run comparison is runner variance: make rows were 25 to 40% faster too.
- Evidence: PLAN.md:1066 row 'sys | 0.02 | 0.10 |'. ref-548da1a/report.json shows sys at 0.02 min and ubuntu-latest/report.json shows 0.10 (read here).
- Fix: Say 'every tier-1 row but sys, which carries the one runner compile per cache', and keep the 'indicative only, runner variance' caveat in the TODO item.

Verifier:

I checked this against the data and could not refute it. In ref-548da1a/report.json, sys took 0.02 min. In ubuntu-latest/report.json it took 0.1 min. sys is a tier-1 row: tiers.tsv marks it 1, and its log shows "rzig build: tier 1" with the build_t1.zig runner. So the statement in feat-zig-pkg-build/PLAN.md:1086 ("Every row through rzig build took as long as or less than the reference's make build") is contradicted by the sys row of the table above it (line 1066: 0.02 against 0.10). The same goes for feat-standalone-toolchain/TODO.md:628-631 ("every tier-1 row through rzig build took as long as or less than the 548da1a make reference"). Two things soften the error. The TODO, in the same sentence, does say "the runner compile shows once per cache in sys, 5 to 15 s". PLAN.md:1090 also explains the sys case in the next sentence. Even so, the claim as written is literally wrong for sys. The TODO also drops PLAN.md's caveat (lines 1087-1090) that the cross-run comparison is only indicative because of runner variance: on this run the make rows were also 25 to 40% faster. This is a wording error in the records only. The conclusion that no shared runner is needed still holds, and no code or behavior is affected. It is minor and can be fixed later.

## phase3-P3-9 (minor, later)

- File: scripts/verify-bundle.sh:557 (with TODO.md:553-575, 632-634)
- Problem: Verified gap. Scenario 2's new assertions run on unix only: the tier-1 install with the compilers alone, and the needs-make and configure stops. Yet the phase 3 TODO calls them 'the gate for the group's scope', and the phase 7 / B24 re-scope they gate is about Windows' build-tools group (sh, make, binutils). On Windows, base + compilers through the archives has no install assertion. The only no-make Windows install is pkg-parity's, on $PREFIX rather than the extracted archives.
- Evidence: verify-bundle.sh:557 `if [ "$OS" != windows ] && [ -n "$ZIG" ]; then`. Windows scenario 2 (verify-bundle.sh:47-50 header) has dry runs and an OpenMP DLL linked by gcc.exe only. pkg-parity.sh:260-266 runs its Windows no-make install from BASE=$PREFIX.
- Fix: Add Windows scenario 2 branches: pfC installs through rzig build with PATH = bin\x64 + System32 (+ flang, ZIG_BIN), and pfM stops with rzig's reason and the Windows build-tools head. Otherwise say in TODO.md that the gate is unix-only and that Windows rests on pkg-parity.

Verifier:

The finding holds; I could not refute it. In 5416d8d, verify-bundle.sh:557 wraps the new scenario 2 block in `if [ "$OS" != windows ] && [ -n "$ZIG" ]`. That block is the pfC tier-1 install through rzig build with no make, plus the pfM, pfG and pfF preflight stops, so none of it runs on Windows. On Windows, scenario 2 only does gcc.exe dry runs and builds one OpenMP DLL with gcc.exe directly, with no R CMD INSTALL. Scenario 3 on Windows does build btA through rzig build, but with bt_path = bin\x64 + the env's Library/usr/bin (make, sh) + System32, so make is on PATH and that run is not a no-make install. The Windows no-make install that does exist is in pkg-parity.sh. It is set up at lines 255-266 and runs at line 274 with BASE_R_EXE from BASE=$PREFIX, not on the extracted archives. It is also positive only. I found no Windows integration test that the preflight stops a package needing make (a Makevars rule or a configure script R runs) with rzig's reason and the build-tools text. parity-test.sh covers that check mode on linux only. The records go further than the tests. The TODO.md "Later" item (lines 620-635) begins "Windows needs sh/make for now" and calls scenario 2's new assertions "the gate for the group's scope". The new note in feat-standalone-toolchain PLAN.md (about lines 2604-2606) says tier 0-2 installs "need it no more" and cites scenario 2, without saying unix. Meanwhile the phase 7 re-scope item (TODO.md lines 553-575) is about Windows' build-tools group. Severity is minor. CONSENSUS.md section G explicitly scoped scenario 2 to "(unix, base + compilers, no make)", so the PR does what was agreed. Each factor is also covered separately on Windows: no-make on $PREFIX by pkg-parity, the relocated rzig-build install with make on PATH by scenario 3. The gap is a mismatch between the records and the tests plus a missing Windows relocated no-make/negative-stop assertion, not a defect in shipped behavior. It can wait: either add a Windows scenario 2 branch (natural during phase 7) or add "unix only; Windows rests on pkg-parity on $PREFIX" to TODO.md and PLAN.md.

## preflight-PF-2 (minor, later)

- File: zigbuild/tools/rzig/pkgbuild.zig:146 (Ctx.zig:55-57; merged install.R 3464-3495)
- Problem: On unix, makevarsUser treats R_MAKEVARS_USER set to the empty string as unset and falls back to ~/.R/Makevars. R's makevars_user() treats set-but-empty as 'no user Makevars' and does not fall back. When R_MAKEVARS_USER is empty, R runs the preflight (it sees no user Makevars), but both the preflight's decide and the hook load a ~/.R/Makevars that make never reads. A flags-only file silently changes rzig build's flags against make's. A foreign CC sends a tier-1 package to make and makes the preflight ask for the build tools.
- Evidence: Verified in scratch. With HOME holding .R/Makevars 'CFLAGS = -O0 -DFROM_USER_MAKEVARS' and R_MAKEVARS_USER=, `rzig build --plan-only` contains FROM_USER_MAKEVARS. With CC = gcc there, `--classify` printed 'make' and the hook exited 3. The compile-tree Rscript with the same environment printed character(0) for tools:::makevars_user(). Cause: R uses Sys.getenv('R_MAKEVARS_USER', NA) and file.exists(''), while rzig uses Ctx.getenv, where empty means null. Windows cannot hold an empty variable, so this is unix-only. Inferred, not run: on Windows rzig expands ~ from HOME before R_USER, while R uses R_USER (preflight-F4). This is not in PLAN.md's 'Known differences' (862-877).
- Fix: Read R_MAKEVARS_USER with ctx.env.get: if it is set at all, use that file when it is non-empty and exists, else no user Makevars. Add a unit test. Record the Windows R_USER/HOME order in 'Known differences', or follow R's order (R_USER first).

Verifier:

I could not refute it. I checked the code and ran it.

**Code.** pkgbuild.zig:146 reads `ctx.getenv("R_MAKEVARS_USER")`. Ctx.zig:55-58 turns an empty value into null, so rzig falls through to HOME/.R/Makevars. R's makevars_user() in the merged install.R (3464-3495) uses `Sys.getenv("R_MAKEVARS_USER", NA_character_)`. An empty value is not NA, and file.exists("") is FALSE, so R returns character(0). R's own NEWS.3.Rd (7610-7618) documents this: R_MAKEVARS_USER/SITE "can be used to suppress the use of the default files by setting an empty value (where possible) or a non-existent path". The comment at pkgbuild.zig:141 says it follows makevars_user(), but for this case it does not. pkgbuild.zig is new in PR #25 (absent at e1ce179), and PLAN.md's "Known differences" (862-877) does not list this.

**Runs** (scratch, deleted). I used the compile tree build/compile-tree/slim; its rzig binary postdates 453baafe, which last changed these lines. HOME/.R/Makevars held `CFLAGS = -O0 -DFROM_USER_MAKEVARS`.
- `rzig build --plan-only` included FROM_USER_MAKEVARS when R_MAKEVARS_USER was empty or unset. It did not when the variable was /dev/null or a path that does not exist.
- The compile tree's Rscript with R_MAKEVARS_USER= printed character(0) for tools:::makevars_user() and "" for Sys.getenv(..., NA).
- End to end: foo.c had `#error` under FROM_USER_MAKEVARS, and I ran `R CMD INSTALL` with R_MAKEVARS_USER=. On the default path (rzig build through patch 0013's hook), zig-cc ran with `-O0 -DFROM_USER_MAKEVARS` and the install failed. With R_ZIG_PKG_BUILDER=make the same install compiled with -O2 and no user flags, and succeeded.

So the zig path applies a user Makevars that R and make leave out. The preflight is skipped only when `!length(makevars_user())` is FALSE. Here R sees no user Makevars, so the preflight runs, and its decide() also reads ~/.R/Makevars. A foreign CC there therefore gives a tier of make and asks for the build tools. I did not check the Windows R_USER/HOME order; the finding marks it as inferred.

**Severity: minor, later.** It needs a unix user who has a ~/.R/Makevars and suppresses it with an empty R_MAKEVARS_USER. Nothing in this repo does that: stress.R uses an existing empty file, pkg-parity and m5 use a path that does not exist, and the recipe tests unset the variable. So CI and default installs are not affected. When it does trigger, the zig path silently builds with different flags, or the preflight asks for the build tools for a package that does not need them. The fix is one line: read R_MAKEVARS_USER with ctx.env.get, so that a set but empty value means no user Makevars, and add a unit test. R_MAKEVARS_SITE at pkgbuild.zig:137 has the same empty-value pattern, since R's makevars_site() uses NA there too.

One side effect: the end-to-end run wrote entries to the global zig cache at ~/.local/share/zig/zig-cache. That is outside both trees.

## preflight-PF-3 (minor, later)

- File: zigbuild/tools/rzig/pkgbuild.zig:296-300, 326-330, 376-379 (cleanup only at 415)
- Problem: The build root <out>/.rzig (src/.rzig under install.R) is created and filled before several early returns that skip the deleteTree at line 415. These include the tier-2 URL refusal (exit 1), no zig (127), copy, write and relative-path failures, and spawn or wait failures. An `R CMD INSTALL <dir>` that fails this way leaves src/.rzig/{build.zig,build_t1.zig,rpkg.zig,plan.zon} in the user's source tree, which R CMD build or check would later pick up as a hidden directory. This is behavioural, but its effect is cosmetic.
- Evidence: Verified. In scratch, a zighello copy with a .url dependency in src/build.zig.zon, run as `rzig build --pkg .. --src . --out . --flat`, exited 1 with the URL line and left src/.rzig with those four files. pkg-parity's zigurl block (pkg-parity.sh:229-237) asserts the refusal but not that the root is gone. The zighello block (226) does check it, but only on success.
- Fix: Once root is created, register the cleanup with defer (honouring keep and RZIG_KEEP_ROOT), so that every return path removes it. Add `test ! -e "$WORK/work/zigurl/src/.rzig"` to pkg-parity's zigurl block.

Verifier:

I could not refute it. In zigbuild/tools/rzig/pkgbuild.zig at 5416d8d, root (<out>/.rzig) is created at line 297 and plan.zon is written at 305. For tier 2, build.zig, build_t1.zig and rpkg.zig are copied in at 316. After that come the URL refusal (326-330, return 1), the relative-path, write and build-file failures (333-360), the no-zig exit (376-379, return 127) and the spawn and wait failures (398-405). Every one of these returns before the only deleteTree(root), at line 415.

Under install.R, patch 0013 runs `rzig build --pkg .. --src . --out . --flat` from src/, so root is the package's own src/.rzig. The install preflight (check.zig's --rzig-check=package, through decide()) never looks at build.zig.zon, so a tier-2 package with a .url dependency passes the preflight and reaches this refusal.

I reproduced it in scratch with the worktree's built rzig (dist/slim/R-4.6.1-zig/lib/R/bin/toolchain/rzig) on a zighello copy carrying the pkg-parity zigurl manifest. It exited 1 with the URL line and left src/.rzig/{build.zig, build_t1.zig, plan.zon, rpkg.zig}.

R's build.R exclusions do not cover it: .hidden_file_exclusions, get_exclude_patterns and cleanup_pkg only remove *.o, *.so, .libs and _libs. So a later R CMD build of that directory would ship src/.rzig, and R CMD check would raise the hidden-directory NOTE. This also goes against the design comment at lines 362-365 ("an install leaves nothing behind").

pkg-parity.sh does not catch it. It checks for a leftover root only after successful installs (lines 210 and 225), and the zigurl block (229-237) does not check it at all.

Why it is minor and can wait: the leak only touches in-place directory installs, since a tarball install unpacks to a temp dir. The no-zig and spawn paths are mostly unreachable under install because the preflight already checks the compilers. A later successful rzig build in the same directory removes the root. No built artifact or test result is affected.

The proposed fix is sound: a defer or errdefer cleanup after root is created that respects --keep-root and RZIG_KEEP_ROOT, plus `test ! -e src/.rzig` in the zigurl block.

## preflight-PF-4 (minor, later)

- File: zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch:61 (merged install.R ~716)
- Problem: With R_ZIG_PKG_BUILDER=zig and no rzig name and no CC binary in R_HOME/bin/toolchain, rzig_build returns NA and the make path runs. The hook's own comment (patch lines 36-38) says that zig means never make, an error instead.
- Evidence: Verified by reading. `if (!file.exists(rzig)) { ...; if (file.exists(cc)) pkgerrmsg(...); return(NA) }` does not look at `builder`. Only the exit-3 branch (patch lines 78-81) honours 'zig'. This is reachable with R_ZIG_NO_PREFLIGHT or a user Makevars on an R without the toolchain package. It is a parity or bisect mode, so the impact is small.
- Fix: Before `return(NA)`, add `if (builder == "zig") pkgerrmsg("R_ZIG_PKG_BUILDER is 'zig' and R_HOME/bin/toolchain has no rzig", pkg_name)`.

Verifier:

The finding holds. I checked it in 0013 at 5416d8d and in the patched install.R at build/R-4.6.1/src/library/tools/R/install.R:697-741. When rzig is missing, `if (!file.exists(rzig)) { cc <- ...; if (file.exists(cc)) pkgerrmsg(...); return(NA) }` never reads `builder`. Only the exit-3 branch (patch lines 78-81) checks for 'zig'. So with R_ZIG_PKG_BUILDER=zig, no rzig and no zig-cc/gcc.exe, run_shlib takes the make path. The hook's own comment (patch lines 39-40) says "zig (never make: an error instead)".

It only happens when patch 0009's preflight is skipped. The preflight runs when there is no user Makevars and R_ZIG_NO_PREFLIGHT is unset, and with no zig-cc it stops first with "the r-zig toolchain is not installed". So the case needs R without its toolchain package, plus either a user Makevars or R_ZIG_NO_PREFLIGHT, plus a builder value meant only for parity and bisect runs. In tests, pkg-parity, wheel-test and the stress runs grep for the `rzig build:` lines, so a silent make run would show up there.

Two things limit the finding:
1. The documented contract is narrower than that comment. The patch header and PLAN.md:455 say "zig: a tier-3 package is an error naming it". With no rzig, no tier is ever decided, so the documented contract is not clearly broken. Only the inline comment is.
2. The suggested one-line fix still would not make "never make" true. Packages with src/Makefile (unix, install.R:1577-1600) or src/Makefile.ucrt/.win (Windows, ~1498) never call run_shlib. They go to make directly even with R_ZIG_PKG_BUILDER=zig, and check.zig:210 only acts on 'make'. So "never make" is not an invariant anywhere.

Better fixes: reword the comment to say the hook refuses a package it would hand to make (or add the finding's pkgerrmsg too), and decide separately whether builder=zig should also refuse src/Makefile packages. Severity is minor and it can wait. No scratch files were created.

## preflight-PF-5 (minor, later)

- File: zigbuild/tools/rzig/check.zig:224-233
- Problem: The flang rule for tier 2 follows plan().sources. These are the top-level lower-case .f/.f9x files from the default OBJECTS, and tier 2 never compiles them: rpkg.addLibrary takes only c_sources and cxx_sources (zigbuild/rpkg/rpkg.zig) and replaces the plan's sources. So a zig package with a stray top-level .f is stopped for 'no flang'. Separately, with R_ZIG_CONFIGURE=1 a tier-2 package uses plan sources, while CONSENSUS B says a package with a configure script uses 'flang by today's top-level either-case match'. A top-level .F is then not asked for, and the deviation is not recorded. The tier-3 top-level path (topLevelFortran) has no test: parity-test pf and verify-bundle pfF are tier 1, and pfM has no Fortran.
- Evidence: Verified in scratch with the PR's rzig and a copy of the compile tree's Makeconf. A tier-2 package with src/x.f gave 'zig-cc: no flang (...)', exit 127. A tier-2 package with src/x.F and R_ZIG_CONFIGURE=1 gave 'package ok: tz tier 2 (rzig build) (a configure script R runs); compilers ok ...; build-tools ok ...' with no flang asked. A tier-3 package (Makevars rule) with top-level x.F asked for flang: the code is right, but untested.
- Fix: Pick one rule and record it. Either use no flang for tier 2 (it cannot compile Fortran) or keep the plan-sources rule as the documented choice. Either implement CONSENSUS's top-level match when R_ZIG_CONFIGURE=1, or note the deviation in PLAN.md 'Known differences'. Add a parity-test case: a Makevars-rule package with a top-level .F and no flang gives exit 127 and 'no flang'.

Verifier:

I could not refute it. All three parts hold against the code at 5416d8d. I tested in scratch with the worktree's compile-tree rzig (built after check.zig's last change) and copies of its etc/Makeconf, share/make, include and share/zig/rpkg. The scratch is deleted.

(1) Tier 2 is stopped by a stray .f. check.zig 224-233 picks flang from d.plan.sources for both .makevars and .zig. pkgplan.plan() lists every top-level lower-case .f/.f90/.f95 file as a source and adds FLIBS to SHLIB_LIBADD. rpkg.addLibrary (zigbuild/rpkg/rpkg.zig 53-80) replaces sub.sources with c_sources and cxx_sources only, so tier 2 never compiles Fortran. In scratch, a tier-2 package with src/x.f and no flang got 'zig-cc: no flang (...)', exit 127, from --rzig-check=package. The same package (a real rbuild with hello.zig) built with `rzig build --pkg . --out` and no flang on PATH: exit 0, libs/tz2.so produced. The plan's link carried -lflang_rt.runtime, and flang_rt.resolve dropped it. So the preflight stops a package the hook builds.
- This rule is the one CONSENSUS B wrote ("plan().sources has f or f9x (tiers 1-2)"), and PLAN.md 768-770 records it. The PR followed the plan; the plan is stricter than tier 2 needs.

(2) The configure deviation is real but has no practical effect. With R_ZIG_CONFIGURE=1, the fortran switch still uses the tier rule, while CONSENSUS B says top-level either-case match. 0009 sets R_ZIG_CONFIGURE from configure / configure.win / configure.ucrt, and classify() sends those packages to tier make unless src/build.zig exists. So only tier 2 with a configure script is affected. In scratch, tier 2 with x.F, a configure script and R_ZIG_CONFIGURE=1 printed 'package ok: tzF tier 2 (rzig build) (a configure script R runs); compilers ok ...; build-tools ok ...' with no flang asked. It does not matter in practice because tier 2 cannot compile .F either. PLAN.md's description matches the code, but neither it nor 'Known differences' says this departs from CONSENSUS.

(3) The test gap is real. topLevelFortran is reached only for .make, .r_only and R_ZIG_PKG_BUILDER=make. The parity-test.sh 'pf' case and verify-bundle's pfF are tier 1 (plan sources), and pfM, p2 and the configure cases have no Fortran. check.zig has no unit test of package(). The code itself is right: in scratch a Makevars-rule package with top-level x.F and make on PATH got 'no flang', exit 127.

Severity is minor, for later:
- It is a false stop only for tier-2 (zig build.zig) packages that carry stray top-level Fortran, which this project's own format makes rare.
- The configure part is a missing note in the record, with no effect on behavior.
- The missing test covers a path that works today.

## preflight-PF-7 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:774-775, 704, 862-877 (also 0009 patch line 30, check.zig:36-39)
- Problem: Records wording. (a) PLAN.md:774-775 says '--rzig-check=package ... Unit tests and ten parity-test.sh cases'. There is no zig unit test of check.package or pkgbuild.decide: check.zig's tests stop at parse(), and pkgbuild.zig tests only urlDependency and arguments. Coverage is the ten parity-test cases (linux CI only) plus verify-bundle. (b) The 0009 header (line 30) and check.zig:36-39 say 'Two inputs differ from the hook's'. PLAN.md 'Known differences' lists use_LTO and Windows' --debug as well, and PF-2 adds a third edge. (c) Fact 5, PLAN.md:704, ends 'On the compile tree too.', which reads as if tier-3 checks also fail on the compile tree. They pass there: pkg-parity's tier-3 block runs on $COMPILE_TREE and passed on kappa. (d) 0009's ERROR line 'this package has compiled code, and the r-zig toolchain is incomplete' is now also printed for an R-only package with a configure script (pfG, verify-bundle.sh:584). This is pre-existing text.
- Evidence: Verified by reading. The `^test` lines in check.zig, pkgbuild.zig and pkgplan.zig were listed with grep. The parity-test cases are at parity-test.sh:690-715.
- Fix: (a) Say 'ten parity-test.sh cases (real binary, linux)'. (b) Say 'four inputs differ' or list them. (c) Say 'so pkg-parity runs the tier-3 checks on the compile tree'. (d) Optionally reword the ERROR line to 'compiled code or a configure script', and update verify-bundle's $preflight_stop to match.

Verifier:

Each part checks out against the code at 5416d8d, but these are wording problems in the records only. Nothing changes how the code runs.

(a) Holds. check.zig's only test that touches `package` is one `expectEqual` line in `test parse` (check.zig:278). No test runs check.package. pkgbuild.zig has two tests, `urlDependency` and `arguments`, and neither calls decide. The tier logic does have unit tests in pkgplan.zig (the "tiers: ..." test at :732), so "Unit tests" is loose rather than false. The package check itself is covered by the ten parity-test.sh cases (I counted ten at :690-715). Nine of them only run when a real zig is present.

(b) Holds. The 0009 header (line 30) and check.zig's doc comment both say two inputs differ: CLINK_CPPFLAGS and the user-Makevars skip. check.package calls decide with r_home, pkg_dir, src_dir, name, c_std and rzig only. use_lto and debug are left at their defaults, while the hook passes --use-lto and, on Windows, --debug (0013:65-68). PLAN.md's "Known differences" lists use_LTO and Windows' --debug as well, so the code text and the PLAN disagree.

(c) Holds as ambiguous wording. Fact 5 ends "On the compile tree too." after "Tier-3 checks on the base fail on Windows". That can be read as "they fail there too", which is wrong. pkg-parity.sh sets TREE=$COMPILE_TREE and runs the tier-3 block (:239-251) on it. The windows-latest/default job in run 38305799627 passed. Fact 4 has the clearer form: "so pkg-parity compares both paths on the compile tree".

(d) Pre-existing, not from this PR. On main at e1ce179, 0009 already gates on configure scripts and prints the same "this package has compiled code, and the r-zig toolchain is incomplete" text. Rewording it is optional.

Severity is minor and timing is later. None of this affects how anything runs. Fixing (b) means editing the 0009 patch file, and changing that file would likely set off rebuilds in CI just for a comment. These fit better in the phase-4 records pass than as a reason to hold the merge.

## preflight-PF-8 (minor, later)

- File: zigbuild/tools/rzig/parity-test.sh:654-715 (also pkg-parity.sh:94, 229-237)
- Problem: Test gaps in the preflight and hook area: (1) Windows' --rzig-check=package build-tools branch has no test. That covers the reason line ending in 'no sh on PATH' or 'no .../binutils/nm.exe' and a configure.win or configure.ucrt classification. parity-test's RZIG_OS=windows cases cover only =build-tools. (2) The ZIG_LOCAL_CACHE_DIR branch (pkgbuild.zig:369) is never asserted: pkg-parity unsets it, and verify-bundle, contract (env.sh:176) and test-toolchain.R set it but never check where the cache went. (3) The build root after a refusal (PF-3) is not checked. (4) The tier-3 top-level Fortran path is not tested (PF-5).
- Evidence: Verified by grep. No package case uses RZIG_OS=windows in parity-test.sh. ZIG_LOCAL_CACHE_DIR appears in tests only as an environment setting (env.sh:176, verify-bundle.sh:302/315, recipe/test-toolchain.R:18) or an unset (pkg-parity.sh:94).
- Fix: Add a parity-test case: RZIG_OS=windows, a package with configure.win and no binutils gives 127 with '<pkg> needs make: a configure.win script ...' (or 'a configure script R runs' with R_ZIG_CONFIGURE=1). Add one pkg-parity install with ZIG_LOCAL_CACHE_DIR=$WORK/zlc that asserts the cache appears there and no src/.rzig remains. Add the PF-3 and PF-5 assertions.

Verifier:

I checked all four gaps against 5416d8d and each one holds. One detail in (1) is overstated.

(1) The package check (check.zig:200-249) has no unit test. check.zig's tests reach `.package` only through `parse`. The ten package cases in parity-test.sh (lines 654-715) all run without RZIG_OS, so none of them takes the Windows branch. RZIG_OS=windows appears only in the two `=build-tools` cases. The Windows failing line, "<pkg> needs make: <why>; no sh on PATH" or "; no .../binutils/nm.exe", is never asserted. The overstated detail: pkg-parity.sh:242-246 does test the configure.win classification on Windows, through the hook ("rzig build: cli needs make: a configure.win script"). On the compile tree that install also takes the preflight's passing branch with R_ZIG_CONFIGURE=1. Only configure.ucrt is untested.

The risk is small. The failing line is put together by code shared with unix, which parity-test covers through p2 and the configure case. The Windows `what` strings come from buildToolsFound, which the build-tools unit and parity tests cover.

(2) pkgbuild.zig:369 is `args.cache_dir orelse ZIG_LOCAL_CACHE_DIR orelse <root>/zig-cache`. pkg-parity.sh:94 unsets the variable, so only the default branch is asserted, through no_zig_build_left and the src/.rzig check. env.sh:176, verify-bundle.sh:302/315, test-toolchain.R:18 and stress.R:303 all set it. None of them checks where zig-build went.

(3) The zigurl refusal at pkg-parity.sh:229-237 checks the error line and that zig build did not run. It never checks src/.rzig. In the code, pkgbuild.zig:296 creates `<out>/.rzig` (the hook passes `--out .`, so this is src/.rzig). The URL refusal at :328 returns 1 before the deleteTree at :415. The no-zig 127 return does the same. An assertion here would fail today, so this gap hides the PF-3 behaviour.

(4) For tier 3, check.zig:232 calls topLevelFortran. No parity-test case, unit test or pkg-parity row runs a tier-3 package with top-level Fortran: the tier-3 fixture is cli, which is C, and pf is tier 1. If the check missed such a file, the build would stop later at zig-fc with the same group text, so the impact is small.

These are real test-coverage gaps. None of them breaks behaviour on its own. PF-3's leftover build root is its own finding. Severity is minor and the fix can come later, for example in the next pkg-parity or parity-test change.

## records-REC-10 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:704
- Problem: Small wording and citation errors in the facts and the test-results table.
- Evidence: Verified. (1) Fact 5 ends 'On the compile tree too.' (:704), which reads as if the tier-3 checks also fail on the compile tree on Windows; they pass there (pkg-parity windows-latest/default succeeded in 38305799627). (2) Fact 8 (:721-722) gives only pristine 2537; CONSENSUS H asks for the merged number too, which is 2640 (scratch patch apply). (3) Fact 9 (:729-730) attributes 'two new o/ entries per install' to 'fact 9 in CONSENSUS.md'; that measurement is in FINDINGS channels-C5's verifier note, and CONSENSUS fact 9 does not give it. (4) The omicron row (:1000) reads 'Rcpp, minqa 10/7 (19)': Rcpp's numbers are missing.
- Fix: Reword fact 5 ('so they run on the compile tree, where they pass'). Add 'merged 2640'. Cite FINDINGS channels-C5. Fill in Rcpp's omicron numbers.

Verifier:

I could not refute any of the four points. All were checked against 5416d8d's .github/devdocs/feat-zig-pkg-build/PLAN.md.

(1) Line 704: fact 5 ends with "On the compile tree too." The natural reading is that the tier-3 checks fail on the compile tree as well. They don't. pkg-parity.sh:43-45 and :241-250 run the tier-3 negatives (neg-auto, neg-zig) on the compile tree, which has binutils/. In run 38305799627, the windows-latest / default job's "Package parity (rzig build against make)" step succeeded. At best the sentence is ambiguous, and it reads as wrong.

(2) Lines 721-722: fact 8 gives only "pristine 2537". CONSENSUS H, the PLAN's own note at :670 and fact 1's style (pristine plus merged) all call for the merged number too. Pristine `.SHLIB <- function()` is at 2537 in the tarball. In scratch I applied the install.R hunks of 0005, 0009 and 0013 from zigbuild/patches/R-4.6.1, and it moves to 2640. The worktree's build/R-4.6.1 also has it at 2640. So "merged 2640" is missing.

(3) Lines 729-730: "two new o/ entries per install, never reused (fact 9 in CONSENSUS.md)". CONSENSUS fact 9 says only that every install adds entries and nothing removes them. The committed copy is identical to the consreview one. The "2 new entries per install" measurement is in FINDINGS channels-C5's verifier note (zig-build/o went 4, 6, 8). The [channels-C5] tag on that line already points to the right finding; only the parenthetical is off.

(4) Line 1000: the omicron row reads "Rcpp, minqa 10/7 (19)". On unix, pkg-parity.sh:78-79 runs cli digest quadprog Rcpp minqa. In the linux table at :974, minqa is the package with 19 rzig command lines, while Rcpp has 7. So "10/7 (19)" are minqa's numbers, and Rcpp's are missing. The kappa row gives Rcpp its own entry, "Rcpp 29/9 (744, 7)".

These are record wording and citation errors only. They have no effect on code, tests or CI, so minor, and they can be fixed later in a docs touch-up. Scratch at pr25review/verifier-REC10 was deleted.

## records-REC-11 (minor, later)

- File: zigbuild/tools/rzig/check.zig:225
- Problem: This departs from CONSENSUS B and is not recorded. With R_ZIG_CONFIGURE=1, CONSENSUS asks for flang by the top-level either-case match. The code uses the plan's sources for a tier-2 package that also has a configure script.
- Evidence: Verified. consolidation/CONSENSUS.md:155-156 says 'with R_ZIG_CONFIGURE=1: the compilers (flang by today's top-level either-case match)'. check.zig:224-233 keys the Fortran choice on the tier only (.makevars/.zig use plan.sources, .make/.r_only use topLevelFortran), whatever `configure` is. PLAN.md:767-771 and the 0009 header describe the code, not the plan, and note no deviation. This is an edge case (tier 2 plus configure plus Fortran).
- Fix: Either use topLevelFortran whenever `configure` is set, as agreed, or record the deviation and its reason under 'Known differences'.

Verifier:

The finding holds, though the gap is narrower than it reads. CONSENSUS.md:155-156 (the same text as the copy at 5416d8d) says that with R_ZIG_CONFIGURE=1, flang is chosen by the top-level either-case match "whatever the tier". check.zig:224-233 at 5416d8d chooses Fortran by tier alone: .makevars and .zig use plan.sources, while .make and .r_only use topLevelFortran. The `configure` variable is never consulted there. Nothing records this as a departure. The "Known differences between the preflight and the hook" list (PLAN.md:862-877) has four items and none of them covers it. PLAN.md:767-771, the 0009 header and check.zig's doc comment describe what the code does and do not call it a deviation.

How far it reaches: tier 1 plus configure cannot happen. pkgplan.classify sends any configure that R runs (configure on unix, configure.ucrt or configure.win on Windows, the same files 0009's configure_runs tests) to tier .make, so topLevelFortran is used there. Tier 0 plus configure gives false either way. The one reachable case is tier 2, because classify checks src/build.zig before configure. For a tier-.zig package, plan() reads no Makevars and builds OBJECTS from listSources, so plan.sources holds the top-level sources. langOf matches only lowercase .f/.f90/.f95. So the code differs from CONSENSUS only for a tier-2 package that has a configure script R runs and only uppercase .F/.F90/.F95 Fortran at src/'s top level. In that case the preflight skips the flang check, and any failure comes later at zig-fc with the same group text. The code's choice fits F5's reasoning for tiers 1-2, but it is still an unrecorded departure from the agreed text. No CRAN package has src/build.zig, so this is minor and can wait: either record it under Known differences or use topLevelFortran whenever `configure` is set.

## records-REC-14 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/consolidation/FINDINGS.md:1
- Problem: The committed copies cite line numbers in files that were never committed (CONSOLIDATION.md:<n>, HANDOFF.md:<n>, branch 8ce3f77's worktree), so a reader of the repo cannot check those citations.
- Evidence: Verified. FINDINGS.md has 54 references to CONSOLIDATION/HANDOFF (e.g. :44 'HANDOFF.md:35', :70 'CONSOLIDATION.md:199-206', :181 'HANDOFF.md:105-109'). CONSENSUS.md:8 points to `.claude/worktrees/.../CONSOLIDATION.md`. Both files are deleted (R1). PLAN.md:633 notes only that CONSOLIDATION.md is not committed.
- Fix: Add one sentence to PLAN.md:633-641: the copies cite CONSOLIDATION.md and HANDOFF.md as they were in the worktree at 8ce3f77; neither was committed (R1); their content is folded into this section.

Verifier:

The finding holds. At 5416d8d, the committed consolidation/FINDINGS.md has 54 lines that cite CONSOLIDATION.md or HANDOFF.md by line number. I checked the examples it gives: :44 cites HANDOFF.md:35, :70 cites CONSOLIDATION.md:199-206 and :181 cites HANDOFF.md:105-109. consolidation/CONSENSUS.md:8 points to the worktree path of CONSOLIDATION.md. Neither file is in any ref: `git log --all --diff-filter=A` finds only the unrelated FLANG_PIXI_HANDOFF.md. Neither file is in the worktree now either, so a reader of the repo cannot check those citations. FINDINGS.md:3 makes this worse because it says "Every point can be re-checked at its cited file:line", and for these 54 lines that is no longer true. Two small corrections to the finding. First, PLAN.md does say more than the finding allows: :633 says CONSOLIDATION.md was "not committed: R1", and the R1 row at :665 says HANDOFF.md was "folded in below and deleted" (the sections at :901 and :950 are marked "from HANDOFF.md"). Still, nothing says HANDOFF.md was never committed, so a reader may look for it in the history and find nothing. Nothing explains the dangling line citations either. Second, the citations to code at "branch 8ce3f77" can be checked: 8ce3f77 is an ancestor of 5416d8d, and `git show 8ce3f77:scripts/pkg-parity.sh` line 83 matches. Only the citations to the two untracked records are lost. This is a records-only nit with no effect on the code or CI. A one-sentence note in PLAN.md's consolidation section, or a header in the copies, would fix it, so it can wait until after the merge.

## records-REC-3 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:848
- Problem: The def.zig rationale misstates R. Upstream R does filter .refptr and .weak names out of the make path's .def: MkRules.rules sets the NM_FILTER default and fixed/Makefile writes it into the installed etc/x64/Makeconf. r-zig's Makeconf.win:59 is the template line without that substitution, so phase 3's make path differs from CRAN's R. rzig def was changed to match that deviation, so DLLs built by r-zig on either path now export the .refptr.* and .weak.* stubs that CRAN builds do not.
- Evidence: Verified in the pristine 4.6.1 tarball: src/gnuwin32/MkRules.rules:113 has `NM_FILTER ?= | $(SED) -e '/[.]refptr[.]/d' -e '/[.]weak[.]/d'`; src/gnuwin32/fixed/Makefile:48 has `-e "s@NM_FILTER =@NM_FILTER = $(NM_FILTER)@"` applied to etc/Makeconf; fixed/etc/Makeconf:59 has `NM_FILTER =`; MkRules.dist:96 is only the commented override. At e1ce179, the only NM_FILTER outside docs is zigbuild/config/win-x86_64-full/Makeconf.win:59 `NM_FILTER =`. PLAN.md:850-857 says the filter applies 'only through NM_FILTER, which phase 3's Makeconf.win leaves empty (R's MkRules.dist comments the filter out too)' and that rzig def now keeps `.refptr.<name>` and `.weak.<name>.default.*`. Stale text too: PLAN.md:600 (M5) says 'On a host with Rtools' sed, make's DLL exports the 185', against :1001's 195 make exports on kappa.
- Fix: Correct the record. Then decide, as a menu for the user: (a) put upstream's NM_FILTER into Makeconf.win and revert def.zig's dot-name export, so both paths match CRAN; or (b) keep the divergence and record it as deliberate, with the reason. Fix or annotate PLAN.md:600.

Verifier:

I tried to refute this and couldn't. The facts in the finding are right, but I rate it lower than major.

Checked against the pristine R-4.6.1 tarball (build/R-4.6.1.tar.gz):
- src/gnuwin32/MkRules.rules:113 sets the default: `NM_FILTER ?= | $(SED) -e '/[.]refptr[.]/d' -e '/[.]weak[.]/d'`.
- src/gnuwin32/fixed/Makefile:48 writes that value into the installed etc/x64/Makeconf (`s@NM_FILTER =@NM_FILTER = $(NM_FILTER)@`).
- MkRules.dist:96 is a commented line, but the comment above it says "this is the default". It documents the default; it doesn't switch the filter off.
- share/make/winshlib.mk:22 applies $(NM_FILTER) when it builds tmp.def.
- So CRAN's installed Makeconf filters these names out, and CRAN-built DLLs don't export `.refptr.*` or `.weak.*`.

Checked in r-zig at 5416d8d:
- zigbuild/config/win-x86_64-full/Makeconf.win:59 is the unsubstituted template line `NM_FILTER =`. The file is the vendored fixed/etc/Makeconf; it still has @SYMPAT@, @R_ARCH@ and the other placeholders.
- build.zig installWindowsCompilerContract (around lines 1779-1870) copies fixed/Makefile's substitutions (SYMPAT, R_ARCH, OPENMP, IMPDIR, COMPILED_BY, LDFLAGS, FC, FLIBS) but never NM_FILTER.
- `git log -S NM_FILTER` shows only 174c952, the initial vendoring, and no record anywhere chose this on purpose.
- The empty filter is therefore an accidental gap against CRAN, not a recorded decision.

The finding's claims about the records hold:
- PLAN.md:850-854 says winshlib.mk filters these names only through NM_FILTER, "which phase 3's Makeconf.win leaves empty (R's MkRules.dist comments the filter out too)". The parenthetical misstates upstream R.
- def.zig:11-19 now deliberately keeps `.refptr.<name>` and `.weak.<name>.default.*`, and its unit fixture checks both.
- PLAN.md:600 (M5, kappa) says "On a host with Rtools' sed, make's DLL exports the 185". That would be true with CRAN's filter, but for this tree :1001 measured 195 make exports on kappa. Line 600 is stale and has no note.

Why minor and not major:
- The make-path gap is not new in this PR; it is already on main at e1ce179. PR #25 extends it to the zig path, on purpose, so the two paths match.
- Nothing failed. The kappa runs (cli, digest, Rcpp, smoke) load and give the same values.
- The extra exports could only matter to code that links against a package DLL's import library, which is rare. A DLL's exports are per-module, so this doesn't affect .Call lookup.

What is wrong now is the record, and it shapes a later choice: (a) put CRAN's NM_FILTER into Makeconf.win and revert def.zig's dot-name exports, or (b) keep the gap and record it as deliberate, with the reason. Correct the record and put that choice to the user; neither has to block the merge.

## records-REC-5 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:642
- Problem: N7's pre-commit review by the phase 3 session is described as still to come, and nothing records that it happened. The PR merged before this review of the committed state finished, and before CONSENSUS I's review of the stress follow-up commit.
- Evidence: Verified. PLAN.md:642-644 says 'the phase 3 session reviews the uncommitted result before the merge commit and the push (N7)'; :664 says the same in the N7 row; no other PLAN.md line mentions the review. CONSENSUS.md:317 and :328 require the review before the commit, and of the follow-up commit. gh: PR #25 state MERGED at 2026-10-13T10:07:21Z (07e12c0), with 47e8436, 45892fb and 5416d8d already pushed before that.
- Fix: Add a dated line to the consolidation section: when the N7 review took place (after the commit and push), which commits it covered, and where its findings are recorded. Then update :642-644.

Verifier:

The finding holds. I checked the text, the PR metadata and both sessions' transcripts.

**What the record says.** In the worktree, `.github/devdocs/feat-zig-pkg-build/PLAN.md` lines 642-644 read: "this session implemented them in the worktree; the phase 3 session reviews the uncommitted result before the merge commit and the push (N7)". Line 664 is the N7 row: "the phase 3 session reviews before the commit and push". A grep of PLAN.md for "review" or "N7" finds only these lines and :633, which is about the earlier review of CONSOLIDATION.md. Nothing records that the N7 review took place, was skipped, or what it found. The same text is now on main through 07e12c0.

**What the plan required.** `CONSENSUS.md` I (:317-320) requires the phase 3 session to review the uncommitted merge before the user commits and pushes. :328-329 add that "The phase 3 session reviews that commit too", meaning the stress follow-up. `MESSAGE.md` says the same.

**What actually happened.**
- `gh pr view 25`: state MERGED, mergedAt 2026-10-13T10:07:21Z. The merge commit 07e12c0 was committed 2026-10-12T20:10:07Z, 45892fb at 20:40:46Z and 5416d8d at 2026-10-13T10:04:02Z.
- The phase 3 session's transcript (bfe0ee08) has no user or peer message between 2026-10-12T17:41Z (the critics finishing) and 2026-10-13T10:06:06Z. So no pre-commit review of the uncommitted merge took place.
- The review request that arrived at 10:06:06Z already described PR #25 as "merged against phase 3". The "merged" was the branch merge 47e8436, already committed and pushed. The same request called the stress follow-up "uncommitted", but 5416d8d had been committed two minutes earlier. The PR merged 75 seconds after the request arrived.
- The pkg-build session (16d6d504) shows the user pushing for CI at 20:16Z, saying "When everything is green, I will start the stress and then we can communicate with the other session". That is a deviation from N7 chosen by the user, and the record never notes it.

**Severity and timing.** The committed record states that a review gate ran before the commit and push. It did not run, and the actual sequence goes unrecorded. This is records accuracy only and affects no code or behaviour, so it is minor. The PR is already merged, so the fix can only come later: a dated line in the consolidation section stating that the N7 review happened after the commit, push and merge, which commits it covered and where its findings are.

## records-REC-6 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:892
- Problem: The N2 scope statement contradicts itself. It says tier 0 to 2 installs do not need the build tools right after saying that tier 0 or 2 packages with a configure script R runs do. The feat-standalone-toolchain paragraph and TODO repeat the contradiction, and also drop parts of CONSENSUS H's scope.
- Evidence: Verified. PLAN.md:883-885 says 'any package whose configure script R runs (tier 0 or 2 can have one ...)'; :892-893 says 'Not needed by tier 0 to 2 installs through R CMD INSTALL and install.packages()'. feat-standalone-toolchain PLAN.md:2603-2604 says 'tier 0 to 2 installs through R CMD INSTALL and install.packages need it no more'. TODO.md:556-557 says 'tier 0 to 2 packages (no configure, ...)'. PLAN.md:2602 and TODO.md:562 give only 'cleanup.win under --clean', where CONSENSUS H has cleanup.ucrt/cleanup.win under --clean or --preclean, and they drop PLAN.md:890's '(Windows)' on R CMD check's objdump. The tier-3 list at PLAN.md:881-883 also omits an Objective-C source and an include (stress: fstcore 'Makevars.ucrt has an include').
- Fix: Say 'not needed by tier 0 to 2 installs without a configure script R runs', in all three places. Restore cleanup.ucrt and --preclean and the Windows qualifier on objdump. Add Objective-C and include to the tier-3 reasons.

Verifier:

The finding holds against the code and the records at 5416d8d. It is a wording problem in the records, not a code bug.

1. PLAN.md:884 says "any package whose configure script R runs (tier 0 or 2 can have one ...)" needs the group. PLAN.md:892-893 then says, with no qualifier, "Not needed by tier 0 to 2 installs through `R CMD INSTALL` and install.packages()". The code agrees with the first sentence:
   - In pkgplan.zig classify, the no-`src/` check (r_only) and the `src/build.zig` check (zig) come before the configure check. Its own test, "z/configure + z/src/build.zig -> Tier.zig", shows that a tier 2 package with a configure script stays tier 2.
   - In check.zig:223 and :242-247, when `R_ZIG_CONFIGURE` is set, every tier needs the build tools ("a configure script R runs").
   - So the last sentence is false for tier 0 and tier 2 packages with a configure script. Only an implied "otherwise" reading rescues it.

2. feat-standalone-toolchain PLAN.md has the same pattern. Line 2593 says "whatever the tier: tier 0 and 2 packages can have one", and lines 2603-2604 then say "tier 0 to 2 installs ... need it no more".

3. TODO.md:556-557 glosses tier 0 to 2 as "(no configure, ...)", which is wrong about the tiers.

4. The feat-standalone-toolchain note drops part of the scope that CONSENSUS H prescribes for it. CONSENSUS H (lines 292-293) reads "cleanup.ucrt/cleanup.win under --clean or --preclean". PLAN.md:2602 and TODO.md:562 say only "cleanup.win under `--clean`". R's install.R run_clean (lines 611-617) runs `sh ./cleanup.ucrt` first, and run_clean also runs on `--preclean` (line 1193). The fuller wording is the correct one.

5. The tier 3 list at PLAN.md:881-883 leaves out an Objective-C source and an include. The code sends both to make: pkgplan.zig classify gives "an Objective-C source", and makefile.zig:166 gives "an include". The stress data confirm the include case (tiers.tsv: windows-latest fstcore, "src/Makevars.ucrt has an include"), and PLAN.md:1108 lists it too.

6. One sub-point is weak. CONSENSUS H itself has no "(Windows)" on objdump, so dropping it is a loss of precision, not a departure from the agreed text.

Severity is minor and it can wait. Each record states the configure qualifier nearby, so a careful reader gets the right scope. No code, test or CI behaviour is affected; the fix is wording in three records.

## records-REC-7 (minor, later)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:600
- Problem: The N5 note (phase 4's bump publishes both packages) sits under Phase 9's build-number item, not Phase 4's, where the bump is made. It also leaves 0009 out of what changed in r-zig-slim.
- Evidence: Verified. TODO.md:600-604 (Phase 9) says 'feat-zig-pkg-build's PR changes r-zig-slim (patches 0012, 0013, share/zig/rpkg) ... phase 4's bump to 9 publishes both'. Phase 4's build-number item is TODO.md:450-452 ('build 8 is on universe, so 9 unless another PR bumps first'). The PR also rewrote 0009-install-compile-preflight.patch (diff stat: 96 lines).
- Fix: Move or copy the note to TODO.md:450-452 and add 0009 to the list.

Verifier:

The finding holds only in part. The 0009 omission is real. At 5416d8d, TODO.md:600-604 (Phase 9) says the PR "changes r-zig-slim (patches 0012, 0013, share/zig/rpkg)". But `git diff e1ce179 5416d8d` shows that 0009-install-compile-preflight.patch was substantially rewritten (+/-96 lines). The patch now sets R_ZIG_CONFIGURE/R_ZIG_C_STD and runs `--rzig-check=package` in place of the old fortran/build-tools checks. Its target is src/library/tools/R/install.R, which ships in r-zig-slim; recipe.yaml excludes only lib/R/bin/toolchain/** from slim. The list was copied from FINDINGS.md:468 (C9), which was written before M1 a' rewrote 0009, so it is stale. The placement complaint is weak. Phase 9's item is where B14 (a)'s test ("a bump only if a package changed since the last bump") is applied, so a note there is defensible. CONSENSUS.md H asks for the note in "TODO.md items" without naming a phase. Phase 4's item at TODO.md:450-452 ("build 8 is on universe, so 9 unless another PR bumps first") stays correct because this PR does not bump, and phase 4 bumps either way. Nothing is lost or wrong in the publish path: phase 4's bump still publishes everything. PLAN.md:2585-2617 already records that 0009 changed and that there is no bump. So the only defect is an incomplete parenthetical in a records note. It is minor, can be fixed later or in a touch-up, and does not block the merge.

## records-REC-8 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1105
- Problem: Some wording and figures in the stress record's Windows reasons and tool counts do not match the artifacts. The same text is repeated in TODO.md.
- Evidence: Verified against tiers.tsv and the windows-latest logs. (1) :1105 says 'the six above (.win or .ucrt)', but on Windows jsonlite, Matrix, rlang and timechange stop on plain 'src/Makevars has a rule' (tiers.tsv). Only filelock and zip are .win, and units is .ucrt. TODO.md:566 says '9 Makevars.win/.ucrt rules'. (2) :1121-1122 says 'sed in 5 (stringi, igraph, ragg, s2, Rhdf5lib)', but `grep -lw sed` finds no windows-latest log with a sed call; the ar (12), ranlib (2), pkg-config (s2, igraph) and cp/mkdir/rm (5) counts do check out. The source of the sed count is not stated, and the text says 'from their logs'. (3) :1134-1139 puts 'the binutils ... nm ... dlltool/windres' under 'Phase 7's Windows usr/bin', but those live in TC/binutils/ (phase 3, B24), not usr/bin.
- Fix: Write '9 Makevars rules (.win, .ucrt or plain Makevars)'. Give the source of the sed count (e.g. the packages' configure.win and Makevars.win), or drop it. Separate usr/bin's contents from binutils/.

Verifier:

Two of the three points hold against the data. The third is a wording ambiguity, not a clear error.

(1) Confirmed. In stress-38317654371/tiers.tsv, four of the Windows rows are classified on plain Makevars: jsonlite, Matrix, rlang and timechange all read "make: src/Makevars has a rule or target line". Only filelock and zip are on Makevars.win, and units is on Makevars.ucrt. rzig's pkgplan.zig:137 tries Makevars.ucrt, then Makevars.win, then Makevars. A reason naming src/Makevars therefore means the package has no .win or .ucrt file. So two things in PLAN.md:1105 are wrong for 4 of the 9 rows: the heading "Makevars.win/.ucrt has a rule" and "the six above (`.win` or `.ucrt`)". feat-standalone-toolchain/TODO.md:566 repeats the error as "9 Makevars.win/.ucrt rules". The count of 9 is correct.

(2) Confirmed. No windows-latest log in the run contains a sed call. I searched with GNU grep at /usr/bin/grep, both `-lw sed` and a pattern for sed as a command; neither found one. A case-sensitive substring search for "sed" hits exactly igraph, ragg, Rhdf5lib, s2, stringi and stringi-bundled. Those hits come from "unused", "based", "parsed", "biased" and "closed_set". Dropping the stringi-bundled duplicate leaves the five packages the record lists under "sed in 5". The count therefore looks like a substring false positive, but the text says it comes "from their logs". The other counts match the logs: zig-ar in 12 rows, ranlib in 2 (Matrix, Rhdf5lib), pkg-config in 2 (s2, igraph), cmake in 2 (biocmake, Rhdf5lib), cp/mkdir/rm in 5 (askpass, filelock, Matrix, ncdf4, units), and no dlltool, windres, objdump or strip. The conclusion that sed stays is still right on other grounds: winshlib.mk's silent nm|sed def step produces s2's tmp.def. Only the evidence is wrong.

(3) Weak. Phase 7 is titled "Windows build tools: usr/bin", and B24 and phase 3 put the binutils in TC/binutils/. But the sentence says "with the binutils ... as phase 3 step 6 left them". That can fairly be read as "alongside, where phase 3 left them". The TODO.md version says "stay in the group", which is correct.

The errors are confined to the records. No code or decision depends on them, so this is minor and can be fixed later.

## records-REC-9 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1027
- Problem: The record concludes that 'no row's smoke compiled at run time' without saying that this dispatch could not exercise the run-time compile path. CONSENSUS I asked the table to cover the rows whose smoke compiles at run time (Rcpp, rstan).
- Evidence: Verified. In the g3 g4 run Rcpp is a dependency, not a target. Its smoke is just TRUE: windows and ubuntu logs/Rcpp-smoke.log hold 'stress: loaded / [1] TRUE / stress: smoke ok'. rstan (g1) was not installed. CONSENSUS.md checklist I lists 'rows whose smoke compiles at run time (Rcpp, rstan: R CMD SHLIB, still make)'.
- Fix: Say that the run-time compile rows (Rcpp's cppFunction, rstan) were not in this dispatch, and that the R CMD SHLIB run-time path is covered by contract's evalCpp and verify-bundle's SHLIB shapes. Optionally add a g1 dispatch item.

Verifier:

Checked against the code and data, and the finding holds. PLAN.md:1027-1029 (5416d8d) says "Smoke steps: no *-smoke.log holds an rzig trace line, so no row's smoke compiled at run time." That sentence is literally true. The trace check is also sound: stress.R:314 sets RZIG_TRACE=1 for the whole process, so the smoke child processes inherit it, and grep finds no 'rzig' line in any *-smoke.log. But the result is empty by construction. In stress/packages.tsv, the only rows whose smoke compiles at run time are Rcpp (cppFunction) and rstan (stan_model), and both are in group g1, so neither was a target of the g3 g4 dispatch. Rcpp was installed only as a dependency. stress.R:479 then uses the smoke "TRUE": the Rcpp.R smoke file runs local(TRUE), and every leg's Rcpp-smoke.log shows loaded / [1] TRUE / smoke ok. rstan has no logs at all. CONSENSUS.md checklist I (line 325) explicitly asks the table to cover "rows whose smoke compiles at run time (Rcpp, rstan: R CMD SHLIB, still make)". The record's closing "Not measured by this dispatch" list names builder=make, the preflight and the per-install cache cost, but not the run-time compile path. So a reader can take the sentence as a check that ran, when the dispatch could not exercise that path. Mitigating: the record states elsewhere (PLAN.md:722, :885) that R CMD SHLIB run-time compilation still goes through make, and the plan itself paired g3 g4 with g1 rows. The finding is still right that the stress section should say so. Docs only, with no effect on code or CI, so it is minor and can be fixed later: add the run-time path to the "Not measured" sentence, point to contract's evalCpp and verify-bundle's SHLIB runs as the coverage, and optionally add a g1 dispatch item.

## stress-S10 (minor, later)

- File: .github/devdocs/feat-standalone-toolchain/TODO.md:561-562 (also feat-standalone-toolchain/PLAN.md:2603)
- Problem: The scope text in the re-scope item narrows the agreed Windows cleanup case. It says 'cleanup.win under --clean', but CONSENSUS H (and feat-zig-pkg-build/PLAN.md:890-892) says 'cleanup.ucrt/cleanup.win under --clean or --preclean'. This came in with 47e8436, not 5416d8d, but it sits in the item 5416d8d extends.
- Evidence: VERIFIED: CONSENSUS.md section H: 'on Windows, cleanup.ucrt/cleanup.win under --clean or --preclean (without sh only a warning: the cleanup is skipped)'.
- Fix: Use the agreed wording: 'cleanup.ucrt/cleanup.win under --clean or --preclean'.

Verifier:

The finding holds against the code and the data. At 5416d8d, feat-standalone-toolchain/TODO.md:561-562 says "`R CMD check`'s objdump and cleanup.win under `--clean`". PLAN.md:2602-2603 says "on Windows by cleanup.win under `--clean`". Neither mentions cleanup.ucrt or --preclean.

The agreed text says more. CONSENSUS.md:292-293 (checklist H) reads "on Windows, cleanup.ucrt/cleanup.win under --clean or --preclean (without sh only a warning: the cleanup is skipped)". The PR's own feat-zig-pkg-build/PLAN.md:890-891 has the same full wording.

R's source backs the agreed version. In build/R-4.6.1/src/library/tools/R/install.R, run_clean() (576-620) runs `sh ./cleanup.ucrt` first and falls back to `sh ./cleanup.win` only when there is no cleanup.ucrt. R calls run_clean() both at line 1193 (`if (preclean) run_clean()`) and at line 1939 (`if (clean) run_clean()`). So the shortened text leaves out both the name R tries first and one of the two flags that need sh.

On where the text came from: neither line exists at e1ce179, and both are present at 47e8436, 45892fb and 5416d8d, so the merge commit 47e8436 introduced them. 5416d8d only extended the TODO item that contains them.

The problem is docs only: the wording narrows the group's scope in a TODO/PLAN note. No code or test path depends on it. The fix is the one-phrase change the finding suggests. That makes it minor, and it can wait.

## stress-S4 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1086-1087 (TODO.md:628-629)
- Problem: 'Every row through rzig build took as long as or less than the reference's make build' is false as worded. TODO.md repeats it without the ubuntu-only scope or the caveat that runner variance explains the gap.
- Evidence: VERIFIED from report.json: sys took 0.10 min against 0.02 in the reference (the PLAN's own table, PLAN:1066). TODO.md:628 does not limit the claim to ubuntu-latest. On the other legs many tier-1 rows were slower than the reference (vctrs 0.29, 0.85 and 0.25 against 0.22), which is cross-runner and not comparable. The make rows ran at 0.65x the reference (11.94 vs 18.43 min summed; per-row 0.50-0.86, not '25 to 40%') and the tier-1 rows at 0.67x (4.04 vs 6.02). After runner variance, the data show no builder difference either way.
- Fix: Say: 'on ubuntu-latest the tier-1 rows (sys aside) ran at about the same ratio to the 548da1a reference as the make rows (0.67 vs 0.65): no measurable builder difference with a shared cache'. Copy that into TODO.md:628-629.

Verifier:

I could not refute it. I checked the sentence against the per-leg report.json files and tiers.tsv/tiers-intel.tsv, comparing each leg to ref-548da1a/report.json. PLAN.md:1086-1087 says "Every row through rzig build took as long as or less than the reference's make build". That is false as written. sys is a tier-1 row and was slower than the 0.02 reference on every leg: ubuntu 0.10, arm 0.25, macos 0.27, intel 0.65, windows 0.21. The PLAN's own table at line 1066 shows this, and line 1090 mentions it, but only after the blanket claim. The sentence also does not limit itself to ubuntu-latest. On the other legs many tier-1 rows were slower than the reference. On macos-latest 12 of 16 were slower, including vctrs 0.29, wk 0.21 and geos 0.13. On windows 8 were slower (vctrs 0.25, cli 0.17, Rcpp 0.22). On intel all 16 were slower. TODO.md:628-629 repeats the claim as "every tier-1 row" with no ubuntu scope and no runner-variance caveat. The finding's figures check out. On ubuntu the tier-1 rows summed to 4.04 against 6.02 (0.67x). The make rows summed to 11.94 against 18.43 (0.65x), counting stringi:bundled and the failed magick row. Per make row the ratio was 0.50 (filelock) to 0.86 (zip, ncdf4), not the PLAN's "25 to 40%" faster. Every leg gives about the same ratio for tier-1 rows as for make rows (arm 0.82 vs 0.79, macos 0.98 vs 0.93, intel 2.31 vs 2.49), so the data show no measurable builder difference either way. Two things soften this. The PLAN paragraph does say "it is runner variance, not the builder", and the decision built on it still holds: the runner overhead is one 5-15 s sys compile, so nothing calls for a shared runner. So this is a wording error in the records, not a wrong decision. PR #25 is already merged (2026-10-13T10:07Z, head 5416d8d; main is at 07e12c0 with the same text), so before-merge no longer applies. The fix is a later doc edit to PLAN.md:1086-1088 and TODO.md:628-629. They should say: on ubuntu-latest, the tier-1 rows other than sys ran at about the same ratio to the reference as the make rows (0.67 vs 0.65), so there is no measurable builder difference; sys pays the one-time runner compile.

## stress-S5 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1142 (TODO.md:630)
- Problem: 'one runner compile per cache (sys), 5 to 15 s' leaves out macos-15-intel, and it is a figure derived with a cold global cache, not a measurement of the runner compile.
- Evidence: VERIFIED: sys took 0.10, 0.25, 0.27, 0.65 and 0.21 min on ubuntu, arm, macos, intel and windows (6, 15, 16, 39 and 13 s; about 5 to 37 s above the reference's 0.02). stress.R:303 also points ZIG_GLOBAL_CACHE_DIR at the fresh run directory, so the sys excess includes a cold global cache. INFERRED: the runner compile is the main part of that excess.
- Fix: Say '5 to 15 s (about 37 s on macos-15-intel), inferred from the sys row with a cold global cache'.

Verifier:

Only half of the finding holds.

The part that holds is the missing macos-15-intel leg. The sys minutes in each leg's report.json are 0.10, 0.25, 0.27, 0.65 and 0.21 (ubuntu, arm, macos, intel, windows); the reference has 0.02. That is 6, 15, 16, 39 and 13 s. Taking away the reference's 1.2 s gives about 5, 14, 15, 38 and 11 s. Comparing against a warm tier-1 row in the same leg instead (askpass, or base64enc on Windows) gives 5, 14, 14, 32 and 11 s. Either way "5 to 15 s" covers four legs. Intel is 32 to 38 s and falls outside it. PLAN.md:1141-1142 and TODO.md:630 state the range with no exception for intel. Only PLAN.md has the context nearby: the table with 0.65, and the note that intel is "two to four times slower ... read against its own make rows". TODO.md has none of that.

The part that does not hold is the cold global cache. stress.R:303 does point ZIG_GLOBAL_CACHE_DIR at the run's zig-cache, and 548da1a:stress/stress.R:301 does the same. But the plan installs packages in order, one at a time, and curl comes before sys on every leg and in the reference (report.json order: curl, sys, askpass). curl's log shows zig-cc compiling and linking curl.so or curl.dll into that same cache. So the global cache was already warm when sys ran, in both runs. What is cold at sys is only zig build's own runner and its host-native artifacts, which is the "one runner compile per cache" the text describes. The suggested wording "with a cold global cache" would therefore put a wrong statement into the record.

The decision does not change. Intel's roughly 38 s is still small next to that leg's make rows (gmp 66 s, nloptr 124 s), so a shared runner is still not needed.

A better fix: "5 to 15 s on four legs, about 35 s on macos-15-intel (a 2 to 4 times slower runner), inferred from sys against the reference and the next warm tier-1 row." Do not add "cold global cache". It is minor and docs-only, and cheap to fold into any docs touch-up before merge, but it does not need to block the merge.

## stress-S9 (minor, later)

- File: .github/devdocs/feat-zig-pkg-build/PLAN.md:1023-1025, 1129-1131
- Problem: Rhdf5lib is left out of the '46 compiled rows', yet it compiles HDF5 (C) with make, through its configure script and CMake's Makefile generator. So the rows that need the build-tools group are 31 of 47 on unix and 30 of 47 on Windows, not 30 and 29 of 46.
- Evidence: VERIFIED: ubuntu-latest/logs/Rhdf5lib.log has 3,224 lines of zig-cc compiles and CMake/make output ('[ 44%] Built target sz-static-objects'). The Windows log shows 'Building for: MSYS Makefiles' and 'Built target' lines. Neither log has a '** libs' phase, so there is no rzig line. INFERRED: the make it runs is the group's make on the narrowed PATH.
- Fix: Note that Rhdf5lib needs sh, make and cmake through its configure script (a 'configure script R runs', agreed scope), and count it among the rows that need the group.

Verifier:

The finding holds against the data. I could not refute it.

**Data.** Rhdf5lib 2.0.0's `configure` and `configure.win` are `#!/bin/sh` scripts. They run `tools/libaec_setup.R` and `tools/hdf5_setup.R`, which call `biocmake::configure()` and then `cmake --build`. biocmake 1.4.0's `configure.R` (line 141, `make=TRUE` by default) sets `CMAKE_MAKE_PROGRAM` from `R CMD config MAKE`, which is the group's make. Under patch 0010, `R CMD config` itself needs the build tools.

**Logs.**
- `ubuntu-latest/logs/Rhdf5lib.log` has 3224 lines, 365 zig-cc invocations, and Makefile-generator progress such as `[ 44%] Built target sz-static-objects`.
- `windows-latest/logs/Rhdf5lib.log` shows `-- Building for: MSYS Makefiles`, `make[2]: *** ... Error 1`, and `ERROR: configuration failed`.
- No log has a `** libs` phase, so `tiers.tsv` marks the row `-`.

So Rhdf5lib compiles HDF5 in C through sh, `R CMD config` and make.

**Doc counts.** PLAN.md calls 46 rows "compiled" in three places: line 895, lines 1129-1132 ("30 of its 46 compiled rows need make on unix and 29 on Windows", "16 to 17 of 46"), and the same wording in `feat-standalone-toolchain/TODO.md:565` and `PLAN.md:2612`. Those counts leave out Rhdf5lib, and the 14 "no native library" rows group it with the R-only packages. Counting rows that need the group, the numbers are 31 of 47 on unix and 30 of 47 on Windows.

**Why it is only minor and can wait.**
- The doc does name Rhdf5lib's cmake build: line 1024, line 1055, line 1122 (sed and cmake) and line 1138 (cmake extras).
- TODO.md's scope sentence ("configure scripts R runs", "`R CMD config`'s direct callers") already covers it in kind.
- The conclusion ("the build-tools group stays required on every OS", phase 7 keeps sh, make and sed) is unchanged; this row only strengthens it.

It is a wording and count precision fix in the records, not a code or decision defect.

## tests-T10 (minor, later)

- File: scripts/pkg-parity.sh:46-48; pixi.toml:99; scripts/verify-bundle.sh:943, 948; scripts/wheel-test.sh:192; .github/devdocs/feat-zig-pkg-build/PLAN.md:998
- Problem: Four wording errors. (1) pkg-parity's header and pixi.toml say the base install has 'no make or sh on PATH', but on unix the directory holds sh (pkg-parity.sh:268; CI prints 'PATH = flang sh zig'). (2) verify-bundle's cf shape claims 'no make ... on PATH at all' with PATH=/usr/bin:/bin, which has make on GitHub's ubuntu and macOS images (inferred from the runner images). (3) wheel-test's '9 rzig command lines' counts rzig's self and environment trace lines: it is 3 commands (dot.c, sum.cpp, the link). (4) PLAN.md repeats the 9.
- Evidence: pkg-parity.sh:268 `ln -s "$(command -v sh)" "$NOMAKE/sh"`. The CI summary line reads 'installed on the base ... with PATH = flang sh zig'. wheel-test.sh:192 counts `grep -c '^zig-c[^:]*: '`, which includes 'self' and 'environment' lines. The package has src/dot.c and src/sum.cpp (:75, :99).
- Fix: Say 'no make (unix: sh, zig and flang only)'. Say 'no make from the env or the toolchain (the host's /usr/bin may have one)', or use a PATH without /usr/bin as pfC does. Count only command lines (exclude self and environment) or say 'trace lines'.

Verifier:

I could not refute any of the four parts. Each one holds at 5416d8d, and the PR's diff adds each line.

(1) No make or sh. pkg-parity.sh:46 and pixi.toml:99 say "no make or sh on PATH". On unix, pkg-parity.sh:268 links sh into $NOMAKE, and PATH="$NOMAKE". The header's own parenthetical, "a directory holding only sh, zig and flang", contradicts its first clause. The CI job logs of run 38305799627 (ubuntu-latest default and minimal, macos-latest default) print "quadprog: installed on the base ... with PATH = flang sh zig".

(2) cf shape. verify-bundle.sh:943 says "as a package: no make and no flang on PATH at all", and :948 prints "no make on PATH". The install runs through shape_pkg with shape_path="/usr/bin:/bin" (shape_pkg passes PATH="${shape_path:-$pkg_path}"). verify-bundle runs directly on the hosted runners: build-r.yaml's verify-package step has no container. GitHub's ubuntu and macOS images ship /usr/bin/make. I took that from the images, not from a log line, but the script assumes it too: its comment at :735-736 has scenario 2 use "the host's make from /usr/bin". The build-tools check at :409 uses make_path="$BUNDLE_DIR/bin" rather than /usr/bin:/bin to keep host make out, and pfC uses "the tree's bin alone, so no make". So the cf shape shows "make not used" (it asserts no make output), not "make absent". The no-make cases that are really tested are pfC and pkg-parity's nomake install.

(3) wheel-test.sh:192. `grep -c '^zig-c[^:]*: '` counts every trace line. main.zig:247-252 prints a "self" line, one "environment" line per environment, and then the command, all through ctx.warn with the "zig-cc: " prefix. The stress logs show this (e.g. stress-38317654371/ubuntu-latest/logs/glue.log lines 13-17), and the --version probe is not traced. The wheel package has src/dot.c and src/sum.cpp. It is minimal, so there is no openmp/ env, and run() uses env -i, so there is no R_ZIG_EXTRA_ENV. That gives 3 invocations (two compiles and the link) of 3 lines each: 9 lines, 3 commands. The CI log line "ok: rzig build: tier 1 (9 rzig command lines under PyPI ziglang)" therefore overstates the count. It also conflicts with pkg-parity's "rzig command lines": its argv_of drops the self and environment lines.

(4) PLAN.md:998 repeats "(9 rzig command lines)".

All four are wording or log-text errors. No check gives a wrong pass or fail, so this is minor and can wait until after merge.

## tests-T11 (minor, later)

- File: zigbuild/patches/R-4.6.1/0009-install-compile-preflight.patch:81 (and the not-installed branch); scripts/verify-bundle.sh:272, 584
- Problem: 0009's stop reads 'this package has compiled code, and the r-zig toolchain is incomplete' even for an R-only package stopped for its configure script. That is pfG's case, and scenario 2 pins this text for it. The not-installed branch says the same for configure-only packages.
- Evidence: check.zig package() stops pfG with 'pfG needs make: a configure script R runs; no make on PATH', and then 0009 prints the 'has compiled code' ERROR, which preflight_stops requires for pfG (:570-584).
- Fix: Reword it, for example 'this package needs the r-zig toolchain (compiled code or a configure script), which is incomplete (see above)', and update $preflight_stop.

Verifier:

The finding holds against the code at 5416d8d and against CI. In zigbuild/patches/R-4.6.1/0009-install-compile-preflight.patch, the preflight runs when `configure_runs` is true even with no src/. That condition is `((install_libs && src non-empty) || configure_runs)` at lines 55-57. Both of its stops still say "this package has compiled code": line 64 when rzig is not installed, and line 81 when the toolchain is incomplete.

Running check.zig's package() for an R-only package with a configure script fails with "<pkg> needs make: a configure script R runs; no make on PATH" (check.zig:244). So for pfG the user sees that reason line, and right after it R's own ERROR claiming the package has compiled code, which is false. The patch header itself says the toolchain is needed for "compiled code (src/) or a configure script R runs".

The PR adds pfG, which does not exist in main e1ce179. In scripts/verify-bundle.sh, pfG is an R-only package with configure_marker (lines 563-567), and preflight_stops requires $preflight_stop (line 272, "ERROR: this package has compiled code, ...") for it (lines 570-584). So the test pins the inaccurate text. CI run 38305799627 passes this scenario on all legs, which confirms the text really is printed for pfG.

Two points on scope:
- The wording itself already existed in phase 3 (main had the same two pkgerrmsg strings and the configure_runs path), so PR #25 did not introduce it.
- What PR #25 does add is the contradicting reason line just before it, and a test that locks the text in.

This is wording only. The stop happens at the right point, before configure runs, and its "see above" text names the right group, so nothing breaks. Rewording both messages and $preflight_stop (plus the PLAN.md quote at feat-standalone-toolchain/PLAN.md:3223) can wait until after merge.

## tests-T12 (minor, later)

- File: zigbuild/tools/rzig/smoke-test.sh:225-231; stress/stress.R:336-342
- Problem: Two smaller gaps. (1) rzig's smoke-test.sh part 2, which G7 changed to RZIG_TRACE=1, runs in no pixi task or workflow, and PLAN.md's test-results table records no run after the change, so the edit is unverified (inferred). (2) stress.R's report info does not record R_ZIG_PKG_BUILDER. A builder=make reference dispatch (the M6 input) cannot be told from auto in report.json or report.md, except by the missing tier lines when traced.
- Evidence: grep finds smoke-test.sh referenced only in its own usage line and in docs. The PLAN.md:986-1001 rows list rzig-test, pkg-parity, contract, verify-package, wheel-test and conda-package, not rzig's smoke-test. stress.R's info list (:336-342) has args, zig, cc and so on, but no builder.
- Fix: Run smoke-test.sh part 2 once on linux and record it, or wire it into rzig-test. Add `builder = Sys.getenv("R_ZIG_PKG_BUILDER", "auto")` to stress.R's info and to report.md's header.

Verifier:

Both factual claims hold, but the risk in part (1) does not.

Part (1): at 5416d8d, zigbuild/tools/rzig/smoke-test.sh is named only by its own usage line and by docs. pixi.toml's `smoke` task runs scripts/zig-smoke.sh, which calls scripts/smoke-test.sh, a different script. No workflow runs rzig's script. The checklist I table in PLAN.md (lines 986-1001) has no row for it. PLAN.md:841 describes the G7 edit but records no run of it. So the records gap is real.

The edit itself works. I ran part 2 in scratch, against the worktree's build/compile-tree/slim/R-4.6.1-zig, inside `pixi run --frozen -e default`. TMPDIR, XDG_CACHE_HOME and ZIG_LOCAL_CACHE_DIR all pointed at scratch. It finished with rc=0:
- Part 1 passed: byte-identical to the shims, SONAME and glibc floor checks, clean unload.
- The `rzig build: tier 1, root ...` lines and the zig-cc/zig-cxx trace lines were displayed for rzc, rzcxx and rzf.
- `OpenMP threads: 2`.
- `ok: rzc, rzcxx, rzomp, rzf built through rzig load and run`.
- `ok: no package links a shared C++ or Fortran runtime`.

The worktree's git status stayed clean, and I deleted the scratch. So part (1) is a missing test-results row, not a defect.

Part (2): stress.R's `info` list (about lines 336-342) has no builder field. report.md's header has none either. stress.yaml (lines 49-50 and 131-132) passes `builder` only as the R_ZIG_PKG_BUILDER env var. It is not added to `args`, unlike `--trace`. The artifact name is `stress-<os>-<dist>`, with no builder in it. The downloaded report.json for run 38317654371 has these info keys: date, r, os, arch, dist, channel, r_zig, r_home, libraries_env, commit, jobs, path, zig, cc, sysdeps_missing, tsv, out, rzig_cache, rzig_cache_removed, args, minutes, finished, error. None is a builder, and report.md never mentions it.

Two things make this smaller than stated:
- The finding calls a builder=make dispatch "the M6 input". The M6 make reference actually used was phase 3's run 38251125721 on 548da1a, which predates rzig build, so this PR's comparison is not ambiguous.
- For a dispatch, GitHub's run inputs still record the builder.

The gap matters only for future builder=make dispatches compared from their artifacts alone, and for local `stress.R` runs with the env var set. That is report metadata, not correctness, so it can wait.

## tests-T4 (minor, later)

- File: stress/stress.R:172 (toolchain pattern); 168-205 (pattern order, classify)
- Problem: The toolchain class now matches 'rzig build: zig build failed'. rzig build prints that line after every failed compile, and toolchain is tested before sysdep, with 'package' only as the fallback. So any tier-1 row that fails to compile is labelled toolchain: a missing system header (sysdep under make) and a plain package bug (package under make) alike. A stress table would then blame the toolchain for failures that are not its own, and the label would differ between builders.
- Evidence: Verified by running stress.R's patterns and classify() (lines 168-176 and 202-205) with the compile tree's Rscript. Missing header plus 'rzig build: zig build failed (1)' gives toolchain. The same header with 'make: *** [a.o] Error 1' gives sysdep. An undeclared identifier plus 'rzig build: zig build failed (1)' gives toolchain. No row of dispatch 38317654371 has the line (grep over every leg's logs), so no table is wrong today.
- Fix: Drop 'zig build failed' from the toolchain alternative and keep rzig build's own failures ('no zig', 'cannot ', 'waiting for zig build', rpkg not installed). The compiler's error lines that zig build echoes then classify the row as on make. Alternatively, test it only after sysdep, as a last class before 'package'.

Verifier:

I could not refute the finding. In pkgbuild.zig (lines 405-414 at 5416d8d), `rzig build: zig build failed (N)` is printed for any nonzero exit of zig build. In tier 1, each compile is a Run step that calls zig-cc (build_t1.zig:77), so a source error makes zig build fail, and the line is printed after the compiler's diagnostics. first_error() starts its text at the first strong error line, such as `fatal error: 'x.h' file not found`, and runs to the end of the log, so the text includes that rzig build line. classify() tests toolchain (stress.R:172) before sysdep and before the fallback 'package'.

I re-ran the classifier code taken from 5416d8d's stress.R on synthetic logs:
- missing header, rzig build path: toolchain
- same header, make path: sysdep
- undeclared identifier, rzig build path: toolchain
- same identifier, make path: package
- with 'zig build failed' removed from the alternative: the two rzig build cases become sysdep and package

The design records anticipated this. FINDINGS.md:582 warned that each compile failure ends with 'rzig build: zig build failed'. CONSENSUS.md G still kept that alternative in the agreed pattern, so the PR follows the plan, but the defect is in the code.

Why the severity is lower than "major":
- README.md:198/228 says the class is the runner's guess and a person makes the final call; first_error still shows the real compiler line.
- No log in dispatch 38317654371 contains the line (I grepped every leg; 81 rows report a tier), so no table published today is wrong.
- The cost is triage noise and different labels between builders. Correctness is not affected.

A fix can wait until after the merge: drop 'zig build failed' from the toolchain alternative, or test it after sysdep.

## tests-T6 (minor, later)

- File: scripts/pkg-parity.sh:129, 160, 221; scripts/verify-bundle.sh:590, 783; scripts/wheel-test.sh:272
- Problem: The 'no make output' checks look for `^make(\[[0-9]+\])?[: ]`, which a successful R make build never prints: R's make echoes recipes as `<R_HOME>/bin/toolchain/zig-cc ...`. These checks therefore cannot fail. The tier-1 line assertion carries the test, so it is not hollow overall, but this check proves nothing. Similarly, wheel-test's positive make check matches 'toolchain/zig-cc', which also appears in rzig's traced 'self' line; the check is saved only by the traced negative at :271.
- Evidence: Verified by experiment: a make-path install (R_ZIG_PKG_BUILDER=make) of an rzigc copy had 0 lines matching the regex. Its compile lines start with `/…/lib/R/bin/toolchain/zig-cc -std=gnu23 ...` and `/…/zig-cxx ...`.
- Fix: Assert there is no echoed recipe: `grep -Eq '^[^ ]*/bin/toolchain/(zig-cc|zig-cxx|zig-fc|gcc|g\+\+)'`, after `tr -d '\r'` on Windows. In wheel-test, use the same anchored pattern as the positive check.

Verifier:

The finding holds against both the code and the stress data. In scripts/pkg-parity.sh:129, `make_lines` greps for `^make(\[[0-9]+\])?[: ]`. It is used at :160 (tier 1) and :221 (zighello). verify-bundle.sh:590 (pfC) and :783 (shape_pkg) use the same regex. GNU make does not prefix echoed recipes with `make:`. I checked the phase-3 make reference logs (ref-548da1a/logs, all built by make). In 59 of the 60 package logs no line matches; the one exception is Matrix, through its recursive `make[1]: Entering directory`. cli's make log, for example, starts each compile with `/…/lib/R/bin/toolchain/zig-cc -std=gnu23 …`. The PR's own stress run (38317654371) shows the same on Windows. Packages built by make there (jsonlite, askpass, rlang, curl and others) have no matching lines; the only Windows matches are recursion (Matrix) and failures (`make: *** … Error` in hdf5r, igraph and Rhdf5lib). So for the flat tier-1 fixtures, a make build that succeeds would pass this check; it fails only on recursion or a make error, which would fail the install anyway. At verify-bundle.sh:590 the check is fully redundant: PATH is $BUNDLE_DIR/bin with no make, so make cannot run there. The rzig-build path is still enforced by the `rzig build: tier 1` assertion on every one of these paths (:159, :587, :779), so the tests are not hollow overall. I also checked the wheel-test.sh:272 aside. main.zig:250 prints `zig-cc: self <self_exe>`, and the stress logs show that path ends in `bin/toolchain/zig-cc` or `g++.exe`. So the 'toolchain/zig-cc' alternative matches rzig's trace lines no matter what invoked rzig. Only the `rzig build:` negative at :271 makes that positive check meaningful. I tested the suggested fix regex `^[^ ]*/bin/toolchain/(zig-cc|zig-cxx|zig-fc|gcc|g\+\+)`, after `tr -d '\r'`. It matches 0 lines in every tier-1 zig-path log on all five runners; zig build's echoes start with `failed command: cd …`, so they do not match. It matches 27 lines in the make reference cli.log and 4 to 29 lines in the Windows logs of packages built by make (gcc.exe recipes). The fix is therefore sound. This is a test-quality weakness, not a functional defect, so it is minor and can wait.

## tests-T7 (minor, later)

- File: scripts/pkg-parity.sh:121-127 (argv_of); header 21-23
- Problem: argv_of's basename normalisation also drops the option of attached-path flags. `-I/x/include` and `-L/x/include` both become `include`, and `-Wl,-rpath,/x/lib` becomes `lib`, so an -I/-L or rpath mix-up between the two paths would compare equal. The source operand's absolute-against-relative difference is hidden too (T1). `grep -v -- '--version'` would also drop any line carrying `-Wl,--version-script=`. The header says the lines are 'compared as sorted sets of words', but the code sorts lines and keeps word order.
- Evidence: Verified: running the sed pipeline from :124-126 on 'zig-cc: /z/zig cc -I/r/lib/R/include ...' and on '... -L/r/lib/R/include ...' gives the identical 'zig-cc: zig cc include -DNDEBUG -c a.c -o a.o'. A -Wl,-rpath,/r/lib word becomes 'lib'.
- Fix: Keep the prefix, e.g. `s#(^| )(-[IL]|-Wl,([^ ,]*,)*|--?[A-Za-z-]+=)?[^ ]*[\\/]([^\\/ ]+)#\1\2\4#g`, and normalise only the -o operand and cache paths. Filter `--version` only as a whole word. Fix the header wording.

Verifier:

The finding holds; I could not refute it. pkg-parity.sh at 5416d8d was added by this PR (aff0f4c, 47e8436). At lines 121-127, argv_of runs `s#[^ ]*[\\/]([^\\/ ]+)#\1#g` after the `--opt=` rule, and that cuts every slash-bearing word down to its last component, flag included. I ran the pipeline exactly as written on synthetic lines. `-I/r/lib/R/include` and `-L/r/lib/R/include` both become `include`. `-Wl,-rpath,/r/lib` and `-L/r/lib` both become `lib`, so two link lines that differ only in the order of -L and rpath compare equal. A `-Wl,--version-script=` line is removed outright by `grep -v -E -- '--version|...'`.

The PR's own local run shows the same loss on real data (build/pkg-parity-slim/logs/minqa-argv-zig). The compared minqa link line ends `-lm lib -lR lib lib lib include include`, but the raw make log has three different -L dirs, one -Wl,-rpath and two -I there. So the comparison cannot tell -L from rpath from -I. The `--version` filter is needed, because the make logs carry `zig-fc: flang --version` and `zig-cxx ... --version` probes that the zig logs lack. But it matches by substring, not as a whole word. The header (lines 21-23) says lines are 'compared as sorted sets of words'. The code sorts lines and keeps word order, so that wording is wrong too.

Why minor and later: the realistic regressions are a missing -I or -L, and those change the word count. An -I/-L swap would break the compile. The export-table check and the smoke check also catch real build breakage. What slips through is a narrow case, such as a dropped rpath next to a duplicated -L, so this weakens the test's evidence and is not a product bug. None of the current fixtures uses a version script.

The proposed fix regex works in GNU sed. On `-I/r/lib/R/include -L/r/lib/R/include -Wl,-rpath,/r/lib -L/r/lib --out-implib=/a/b.lib /abs/src/a.c` it gives `-Iinclude -Linclude -Wl,-rpath,lib -Llib --out-implib=b.lib a.c`.

## tests-T8 (minor, later)

- File: scripts/verify-bundle.sh:827, 870, 900, 1020, 1063 (check_minos on the .so only); 719-721; 1099; .github/devdocs/feat-zig-pkg-build/PLAN.md:812-818
- Problem: Two of G2's checks are weaker on the rzig-build shapes than on SHLIB. (1) The macOS floor is checked only on the installed .so. The file's own comment says zig stamps the link, so only the objects show a compiler that ignored the floor, which is flang's case. The check therefore cannot fail for rzig build's Fortran objects, because the build root holding them is deleted. (2) The CONDA_PREFIX decoy goes through rzig build only for rp. rp.cpp includes neither poisoned header (omp.h, zlib.h), and the OpenMP decoy rebuild is SHLIB only. PLAN.md nonetheless lists 'the CONDA_PREFIX decoys' among the shapes installed through rzig build.
- Evidence: Verified by reading. check_minos receives $shape_so or $so only. :719-721: 'zig stamps the link, so only the objects show a compiler that ignored it (flang defaults to the host SDK's version)'. The decoy loop :1083-1110 calls shape_pkg only for rp. pkgbuild.zig removes <out>/.rzig unless RZIG_KEEP_ROOT is set.
- Fix: In shape_pkg, set RZIG_KEEP_ROOT=1, run check_minos on "$d"/src/.rzig/zig-cache/o/*/*.o, then remove .rzig. Add `shape_pkg omp` with the decoy CONDA_PREFIX inside the loop where the tree has OpenMP. Correct the PLAN.md sentence.

Verifier:

The finding's core holds against 5416d8d, but one part of its reasoning is wrong and so is its fix path.

(1) Holds. For the rzig-build shapes, check_minos only ever gets the installed .so: shape_so at :827 (rp), :870 (fs), :900 (fl), :1020 (omp, lomp) and :1063 (fomp, fompfc). The SHLIB runs also check the objects (fs.o at :860, fl.o at :887, fomp/fompfc .o at :1045). The comment at :719-721 says only the objects show a flang that ignored the floor. So no check in this file can catch an rzig-build Fortran object above minos 13.0.

The cause the finding gives is wrong, though. The build root is not what holds the objects. zig_env passes ZIG_LOCAL_CACHE_DIR (:315), and env.sh:176 always exports it. pkgbuild.zig takes that as cache_dir ahead of <root>/zig-cache. So the objects survive in $BUILD_DIR/zig-cache/.../local/o/; nothing checks them. The suggested fix (RZIG_KEEP_ROOT plus a glob over $d/src/.rzig/zig-cache/o/*/*.o) would match nothing.

The practical risk is low. build_t1.zig compiles through the same zig-fc as make, and the plan passes it the words make would. zig-fc puts -mmacosx-version-min=13.0 before the caller's words unconditionally (fortran.zig:66). The SHLIB objects check that injection. pkg-parity.sh asserts identical traced zig-fc command lines between rzig build and make for quadprog and minqa (Fortran). The agreed checklist G also put the checks "on lib/<pkg>/libs/*", so the .so-only minos check matches the plan.

(2) Holds. In the decoy loop (:1086-1113), shape_pkg runs only for rp (:1099). rp.cpp includes R.h, Rinternals.h, stdexcept and string, none of the poisoned omp.h or zlib.h. The OpenMP decoy rebuild (:1091-1095) is R CMD SHLIB only. Through rzig build, the decoy can therefore catch an rpath leak (the rpaths_of check) but not an -I leak.

This is mitigated elsewhere: recipe/test-toolchain.R:135-142 installs rzigz (#include <zlib.h>) with the poisoned decoy under the default builder. environment.zig:38 documents that CONDA_PREFIX is never read. The echo at :1115 and the comment at :1076-1081 describe the coverage correctly.

The PR record does not. PLAN.md:812-818 lists "the CONDA_PREFIX decoys" among the R CMD SHLIB shapes that are "also a package installed through rzig build", which is untrue for the OpenMP decoy. Checklist G's "same ... CONDA_PREFIX checks" is only partly met for omp.

Overall: a real but minor gap in test strength plus a doc overstatement, safe to fix later. A correct fix would check the objects in $ZIG_LOCAL_CACHE_DIR (or in a per-shape cache directory). It would also add `shape_pkg omp ...` with shape_env=(CONDA_PREFIX=$cpfx) in the loop where Makeconf offers OpenMP, and reword PLAN.md:816. I created no scratch files.

## Refuted

### tests-T9

Claim: no_zig_build_left only asserts absence. If rzig's cache root moved, for example XDG_CACHE_HOME stopped reaching rzig, the guard would pass vacuously.

The premise is literally true: no_zig_build_left (scripts/pkg-parity.sh:132-134) only runs `test ! -e "$RZIG_CACHE/zig-build"`. But the guard is not vacuous with the code and data as they are.

1. The anchor is correct today. The script exports XDG_CACHE_HOME="$(wpath "$WORK/cache")" (line 97). cache.zig root() reads XDG_CACHE_HOME first, so rzig's root is "$WORK/cache/r-zig", which matches RZIG_CACHE (line 98). The data agrees: the worktree's own run left build/pkg-parity-slim/cache/r-zig/dso-fini-bfafa80f07eda1929880f72420e61921, so rzig's cache lands exactly where the guard looks.

2. The regression the guard exists for is pre-N3 code. At aff0f4c, pkgbuild.zig:292 set cache_dir to "<cache.root(ctx)>/zig-build". Reintroducing it would resolve through the same cache.root(), which by point 1 is $RZIG_CACHE. For the guard to pass vacuously, two separate hypothetical regressions would have to land together: the build cache moving back under cache.root, and XDG_CACHE_HOME no longer reaching rzig under R CMD INSTALL. Nothing in the PR makes the second one likely. This is a speculative hardening idea, not a defect in the PR.

3. The proposed fix would not work everywhere. upstream-zig.yaml runs pkg-parity through build-r.yaml with zig: upstream on macOS. There rzig may never create $RZIG_CACHE:
   - the libc++ mirror does nothing for upstream zig (libcxx_mirror.zig);
   - dso_fini is Linux-only;
   - cfguard is Windows-only.
   So an unconditional `test -d "$RZIG_CACHE"` could fail a correct build. Only the Linux-only dso-fini variant of the fix would be safe.

Since the guard is anchored correctly today and the failure needs stacked hypotheticals, this does not hold as a real finding.

### records-REC-13

Claim: Phase 3's status text is stale after this PR: 'Next: PR #24 merges; then feat-zig-pkg-build ... 0009's build-tools check is gated on its tier'. Fact 3 refined this: the check is not gated on the tier alone, because a configure script R runs also needs the build tools. The phase 7 re-scope TODO item also stays unchecked though its content records the result.

The main claim, that phase 3's status is stale, does not hold up as a defect. The facts are right: at 5416d8d, PLAN.md:2564-2580 still says "Status (2026-10-12) ... Next: PR #24 merges; then feat-zig-pkg-build ... 0009's build-tools check is gated on its tier; then phase 4", and the PR leaves those lines alone. But this PLAN.md never rewrites dated status paragraphs.
- The top status (line 3, 2026-10-08) still says "Implementation may start ... #15 merges".
- Phase 2's status (line 2162, 2026-10-09) still says "implemented and tested, not committed ... Still to do: ... CI, then the commit", even though phase 2 was merged long ago.
- Phase 3's own PR (#24, e1ce179) wrote "Next: PR #24 merges", which was a forward-looking line from the start.
- TODO.md phase 9 has an open item, "This PLAN.md: status and records with dates and test results", so the status refresh is planned for later.
- CONSENSUS.md checklist H asked for "a note under the phase 3 records". The PR added that note: a dated paragraph, "feat-zig-pkg-build consolidated (2026-10-12)", at :2583, right after the status. It states the refinement outright ("R_ZIG_CONFIGURE=1 ... whatever the tier: tier 0 and 2 packages can have one").
- The phrase "gated on its tier" sits inside the clause that credits the user's order (a) of 2026-10-11, so it reads as a quote of that decision, not as a current claim.

Anyone reading in order meets the update right after it, so nothing misleads.

The second part is accurate but cosmetic. TODO.md:553 "- [ ] Re-scope from feat-zig-pkg-build's stress table" was added unchecked by this PR. Its 5416d8d follow-up records the outcome ("nothing leaves it on the table's evidence; cmake stays the extras candidate"), as does the PR's PLAN.md "Re-scope of phase 7 and B24" (:1127). The file usually marks finished items [x] with a date, so this one could be ticked. It is a missing checkbox in a record, with no effect on code, CI or decisions. It also sits among phase 7's open items, so it can reasonably be read as an input that phase 7 acts on. Given that the headline claim is ruled out by the document's own practice and what is left is a cosmetic checkbox, I am marking this not real. If you want to fix it anyway, tick TODO.md:553 with the date 2026-10-12. That is a later nit, not something to block the merge.

### stress-S7

Claim: The phase 7 re-scope and the status sentence repeat the stress results without stress's own limits. These records are what phase 7 will be planned from.

Most of the facts in the finding are correct, but the defect it claims does not hold up. There are four reasons.

1. The source record already states the limits the finding says are missing. The PR's feat-zig-pkg-build/PLAN.md section "Stress dispatch (M6, 2026-10-12)" opens at lines 1015-1017 with "packages g3 g4; distribution tree; trace = true; builder = auto", and says the make reference covers ubuntu-latest only. At about 1131-1134 it says the 16-17 of 46 tier-1 share reflects that selection and is not a measurement of CRAN. At 1144-1146 it lists what was not measured: the preflight ("fact 11: stress runs skip 0009") and the per-install cache cost ("the run shared one cache"). So the finding's claim that the record "omits g3 g4, tree-only" is false.

2. Both summaries point to that section by name, and their wording already scopes the numbers. TODO.md:562-572 says "(...; feat-zig-pkg-build's PLAN.md, "Stress dispatch")", "of the suite's 46 compiled rows" and "nothing leaves it on the table's evidence". The status sentence at feat-standalone-toolchain/PLAN.md:2610-2614 says "the table in feat-zig-pkg-build's PLAN.md, "Stress dispatch"".

3. Nothing in the two summaries is false, and no phase 7 or B24 decision depends on the limits they leave out. Both conclusions are conservative: sh, make, coreutils, sed, pkg-config and nm stay in the group, nothing leaves it, and no tool moves. The caveats (g3 g4 only, the group on PATH, 0009 skipped, one shared cache) could only argue for keeping more, which is already the outcome. The SHLIB, R CMD config direct callers, check objdump and --clean items are not presented as stress results. The TODO item lists them as reasons the group stays. The claim that tier 0-2 installs build with no sh or make is a design statement, not a stress result. On Windows it is still untested, and the next TODO item already plans that test: verify-bundle scenario 3 on Windows with PATH = bin\x64 + System32.

4. The shared cache is effectively disclosed where it matters. The "Depend less on make" item says the runner compiles "once per cache" and gives the per-install cost (about 3 s warm) separately.

The facts I could verify: 0009 is skipped (stress.R:297 sets R_MAKEVARS_USER to an empty file; CONSENSUS fact 11). The dispatch was g3 g4 on the tree distribution. The libraries env's make was on PATH (stress.R:327-334). One zig-cache was shared (stress.R:303). Adding the proposed clause would be a small wording improvement, not a before-merge defect. I created no scratch files.

## Checked and fine

### phase3

- Verified: build.zig:2589-2601 installRzig adds only 'rzig.exe' (Windows) and 'rzig' (unix) to main's two lists. There is no extensionless zig-cc/zig-cxx on Windows. share/zig/rpkg/{build_t1,build_t2,rpkg}.zig are installed under R_HOME, and the install step hangs off b.getInstallStep() (build.zig:532-533)
- Verified: rzig_names() (scripts/verify-helpers.sh:40-46) lists rzig.exe and rzig. verify-tree.sh:112-141 still holds TC to exactly those names, byte-identical, with the conda win-64 binutils/ exception. verify-bundle.sh:152-160 builds the base-archive 'only rzig in TC' check from rzig_names(), so the new name passes. The base == R tree list check (verify-bundle.sh:120-133) also covers share/zig/rpkg, which lives in the R tree. verify-tree.sh:143-150 asserts the rpkg roots
- Verified: the toolchain tree is untouched. No change to zigbuild/toolchain/, verify-toolchain.sh, package-standalone.sh, unpack-toolchain.sh, env.sh or toolchain.yaml (git diff --stat e1ce179 5416d8d). SOURCES and LICENSES are unchanged, and the group archives hold no rzig
- Verified: compile-tree.sh is unchanged. pixi.toml:101 has pkg-parity depends-on compile-tree. contract (pixi.toml:93), stress (653/656) and verify-package (132) depend on what they depended on before
- Verified: patch 0009 still calls CC's name (zig-cc, or gcc.exe on Windows) with --rzig-check=package, never 'rzig'. hermetic-check.sh is unchanged and its strace allowlist (215-221) only needs zig-cc. The base-alone preflight still stops with the compilers text (exit 127 from compilers() inside package()). Patch 0010 is unchanged
- Verified: groups.zig is unchanged, so the group heads match the strings verify-bundle asserts (verify-bundle.sh:251-256). package() fails through fail(.build_tools, 127) with '<pkg> needs make: <reason>; <what>'. A zig version mismatch still exits 1 through compilers(). Windows paths in the buildToolsFound lines still go through display()
- Verified: verify-bundle scenario 2 on unix: pfC asserts 'rzig build: tier 1', no make output, and that it loads. pfM and pfG stop with rzig's reason, the build-tools head and 0009's ERROR line, and pfG's configure does not run. pfF is unchanged. The unix SHLIB shapes are also installed as packages with the same rpath/NEEDED/libc++/minos/flang_rt/libomp checks (shape_pkg, 760-1073). Scenario 3 asserts btA = rzig build and btLib (Windows: btRc too) = make from the keep_outputs logs. The Windows LTO twin ltotier1 asserts 'MAKEFLAGS sets LTO_OPT'. The nopre/R_ZIG_NO_PREFLIGHT block still holds (nopre has a configure script, so it is tier 3)
- Verified: stress.yaml keeps the C3 toolchain job (65-76) and C4's '!cancelled()' (83). trace and builder only add env and args to the Stress step (131-138)
- Verified: build-r.yaml order is toolchain artifact (65), unpack-toolchain (70), verify-tree (107), contract (116), pkg-parity (122), check, hermetic (131), verify-package (148)
- Verified: recipe/recipe.yaml:151 is still 'number: 8' (N5). r-zig-slim excludes only lib/R/bin/toolchain/** and Library/lib/R/bin/toolchain/** (332-335), so share/zig/rpkg is in slim. r-zig-toolchain takes bin/toolchain/** (463-465), which includes rzig/rzig.exe. recipe/test-preflight.R still holds for slim alone
- Verified: make-wheel.py is unchanged and still correct. Its stray check (417-420) compares data with zig-cc, and rzig is the same binary. The toolchain wheel takes everything under lib/R/bin/toolchain (rzig included), and share/zig/rpkg goes into r-zig. wheel-test.sh asserts tier 1 under PyPI ziglang, runs a make-path install and a needs-make package, and checks the uninstall
- Verified: CI run 38305799627 on 45892fb is green on every job, including all five conda-package legs and verify-package on the default and minimal legs of every OS. The conda-package path filter (build.yaml:223, zigbuild/) covers zigbuild/rpkg
- Verified: the stress tier counts in TODO.md (17 tier 1 and 29 make on Windows, 16 and 30 on unix) match tiers.tsv for all five runners

### preflight

- Patch series: patches 0001 to 0013 from 5416d8d apply in order to a scratch copy of the pristine R-4.6.1 tarball with no offset and no fuzz. This is verified and matches PLAN.md's claim 'applies with no offset'. The cited install.R lines are right: Rcmd config is at pristine 1292 and merged 1392, R CMD config at pristine 1327 and merged 1427, Sys.setenv(CLINK_CPPFLAGS) at pristine 1391 and merged 1491.
- One shared function: check.zig:214 (package) and pkgbuild.zig:246 (run) both call pkgbuild.decide (pkgbuild.zig:196-226). It runs classify and then plan, and maps plan's NeedsMake to .make with plan's reason. The preflight's cwd is the package directory (install.R setwd(pkg) at merged 344), so src_dir resolves to the same <pkg>/src the hook gets from `--src .`. R_PKG_CXX_STD is set before the preflight (merged 402), so both runs see it.
- 0009 (patch lines 52-82; merged install.R 1345-1376): R_ZIG_CONFIGURE and R_ZIG_C_STD are set with Sys.setenv right before one system2(<CC's path: zig-cc / gcc.exe>, '--rzig-check=package', stdout = FALSE) and unset right after. The same code runs on Windows, where system2 pastes env= into the command line, so the Sys.setenv route is the right one. Nothing is left set for later packages of a multi-package install, because any failure exits through pkgerrmsg after the unset. A scratch run showed R_ZIG_C_STD reaching plan's CCnn check: 17 gives tier 1, 11 gives 'C11 standard requested but CC11 is not defined'.
- With R_ZIG_CONFIGURE=1, the compilers and then the build tools are checked whatever the tier (check.zig:223, 234-248). This is asserted by parity-test.sh:699-701 and 710-711 and by verify-bundle pfG (verify-bundle.sh:584).
- Flang rules: tiers 1-2 use plan().sources (check.zig:225-231); a scratch Makevars `OBJECTS = a.o sub/b.o` with sub/b.f asked for flang, and an unlisted vendor/x.f did not. Tier 3 and r_only use the top-level match on either case (check.zig:185-196, 232); a scratch Makevars-rule package with a top-level x.F asked for flang.
- Reason line: '<pkg> needs make: <reason>; no make on PATH' followed by the build-tools group text (check.zig:247). Exact text is asserted at parity-test.sh:695-711 and verify-bundle.sh:582-584. The CI log of run 38305799627 (ubuntu-latest/default) shows all ten --rzig-check=package cases 'ok' (not skipped: test.sh passes ZIG, so real_zig is set) and the scenario 2 preflight line.
- R_ZIG_PKG_BUILDER=make forces make in the check (check.zig:210-212, reason 'R_ZIG_PKG_BUILDER=make') and skips rzig in the hook (0013 patch line 46). R_ZIG_NO_PREFLIGHT is unchanged (0009 nzchar skip; check.zig:114). The rzig-missing branch and the R_ZIG_TOOLCHAIN_HINT text are unchanged from phase 3 (diff of 0009).
- 0013 (patch lines 50-61; merged install.R 703-716): when CC's binary exists and rzig does not, the install stops with 'the r-zig toolchain is older than this R'. Exit 3 maps to NA and the make path. On Windows identical(status, 3L) holds because the Windows system2 returns ScalarInteger (sys-win32.c:382). On unix spawnWait returns WEXITSTATUS (0012).
- MAKEFLAGS (N4): pkgplan.zig:420-446 treats option words (k, -j2, --jobserver-auth=...) as tier 1, and a NAME=value word or any word after ' -- ' as needing make. This is unit-tested at pkgplan.zig:448-456 and 773-784 and parity-test.sh:705-709, and confirmed by a scratch check ('MAKEFLAGS sets X').
- Tier 2 offline (N6): a URL dependency is refused with exit 1 before zig runs (pkgbuild.zig:321-331), and zig build gets `--system <root>/no-packages` (pkgbuild.zig:370-374, 388). A scratch zig 0.16 test shows nested .path dependencies still resolve under --system, so the error message's advice ('vendor it as a .path dependency') holds.
- N3 cache: --cache-dir defaults to <root>/zig-cache, which is removed with the root on success and on zig build failure (pkgbuild.zig:369, 411-416). ZIG_LOCAL_CACHE_DIR is honoured when set, and empty counts as unset (Ctx.zig:55-57). pkg-parity's global-cache count check (pkg-parity.sh:200-211) is a real check, not a vacuous one.
- 0010 is unchanged (empty diff). M7's corrected reason is in PLAN.md fact 1 (lines 674-686). The feat-standalone-toolchain PLAN.md paragraph about the preflight and the build-tools scope matches the code.

### tests

- pkg-parity F1 (M3 a'): parity, tier 2, the URL refusal and tier 3 run on $COMPILE_TREE (scripts/pkg-parity.sh:57,65). The base ($PREFIX) is used only for the env -i no-make install, which asserts `rzig build: tier 1` and the .so, with no argv comparison (:254-278). RZIG_TRACE=1 is exported (:96), so the make-path negative (:164) is meaningful. Verified in CI 38305799627 on all 15 legs (5 OSes).
- argv_of F2: strips `ZIG_LIB_DIR=<word> ` instead of dropping the line (pkg-parity.sh:124). The macOS legs (macos-latest, macos-15-intel; default, minimal, full) print cli 27, digest 20, quadprog 6, Rcpp 7 and minqa 19 rzig lines identical, the same counts as linux, so channels-C3 is fixed (verified, CI).
- minqa F3: joins PKGS after Rcpp on unix only (pkg-parity.sh:78-79). smoke.R has a bobyqa line and its unload loop covers minqa (:187-188). CI unix legs print 12 smoke lines, Windows 10 (verified).
- Tier-2 URL refusal (E/F): pkg-parity.sh:229-237 asserts the exact rzig line and the absence of the tier-2 line. CI prints 'zigurl: a URL dependency ... refused before zig runs' on all 15 legs. zighello's `--system` is asserted from the traced command (:220) (verified).
- Cache checks (D/F) as written are not vacuous: global o/ counts are 257 (macOS), 268 (linux) and 1575 (Windows), unchanged on the second same-directory install. The zig-build guard looks where rzig looks: cache.zig:23 honours XDG_CACHE_HOME on every OS. The same-directory design is a separate problem (finding T1).
- verify-bundle scenario 2 G1: pfC runs with RZIG_TRACE=1 and starts_line 'rzig build: tier 1', with PATH=$BUNDLE_DIR/bin, so there is no make (verify-bundle.sh:585-595). pfM's text matches what check.zig composes from pkgplan's reason: `<pkg> needs make: <reason>; <missing>`, check.zig package(); pkgplan.zig:758 tests the reason format (:582). pfG is R-only plus configure_marker and asserts 0009's ERROR line ($preflight_stop), configure-ran absent and lib absent (:570-584). The CI unix default and minimal legs print the preflight summary line (verified).
- verify-bundle G2 (unix): every R CMD SHLIB shape is also installed through shape_pkg with RZIG_TRACE=1, the tier-1 line asserted (:774-794). The rpath, NEEDED, libc++ and libomp checks run on lib/<pkg>/libs/<pkg>.so. CI prints the '(R CMD INSTALL, rzig build)' lines for C++, Fortran, USE_FC_TO_LINK, FLIBS, OpenMP C and Fortran OpenMP, the last two on the slim legs (verified).
- verify-bundle G3: bt.R asserts btA = rzig build and btLib (Windows: btRc too) = make from keep_outputs logs, with RZIG_TRACE=1 on unix (:1230) and Windows (:1463). Under install.packages(Ncpus = 2), make's jobserver MAKEFLAGS is in effect, so this also covers N4's option words in a real recipe. ltotier1 asserts 'MAKEFLAGS sets LTO_OPT' (:1500-1506). CI: unix 'btA = rzig build, btLib = make'; on Windows ltotier1 goes to make, exit 0, and loads (verified).
- contract G4: RZIG_TRACE=1 (contract-test.sh:201). keep_outputs logs, and builder_of/want assert Rcpp, quadprog and unix minqa = rzig build; data.table, ps and Windows minqa = make; pak = mixed (:91-104). pak = mixed departs from the plan's 'pak needs make' and is justified: pak has no src/ and its configure installs the embedded packages. The R program now goes through a file, with an end marker checked (:199-202). CI prints the expected builders line on all 15 legs (verified).
- wheel-test G6: the console-script install has RZIG_TRACE=1 and asserts tier 1 (wheel-test.sh:190-192). The bin/R install uses R_ZIG_PKG_BUILDER=make with RZIG_TRACE=1, so its 'no rzig build:' check is decisive (:270-273). rzigwheelar asserts the Makevars-rule 'needs make' reason and loads (:289-300). It ran on the four unix minimal legs (verified).
- stress G8 inputs: stress.yaml has `trace` (bool) mapped to --trace and `builder` (auto|make) mapped to R_ZIG_PKG_BUILDER. stress.R's new alternatives do not match rzig's trace lines ('tier 1, root', the zig build command), so traced successes are not reclassified.
- N1 make runs per shape: pkg-parity keeps a make run for cli, digest, quadprog, Rcpp and minqa; scenario 2 keeps every R CMD SHLIB run; wheel-test keeps one make install; scenario 3 has btLib and btRc. The recipe's make runs exist but are not asserted (finding T2).
- CI 38305799627: no 'skipped' line for the compiled-package or package-build blocks on any leg; recipe test-toolchain.R printed its rzig build and make lines on all five conda-package legs; parity-test's ten --rzig-check=package cases ran on the linux legs (the script runs only there).

### records

- STATE: PR #25 is no longer open. gh shows it merged at 2026-10-13T10:07:21Z as 07e12c0 (parents e1ce179 and 5416d8d; same tree as 5416d8d). Every 'before-merge' below therefore means the next commit on main.
- R1 holds. CONSOLIDATION.md and HANDOFF.md were never committed: git log --all on both paths is empty and the worktree is clean. PLAN.md:633 and :665 say so. HANDOFF.md's content could not be compared with what was folded in, because no copy of it survives. PLAN.md:901-961 covers the HANDOFF items FINDINGS cites (the kappa make-path failures, the cache, the trace format).
- R2 holds. consolidation/CONSENSUS.md and FINDINGS.md are byte-identical to /data/gamma/.../consreview/{CONSENSUS,FINDINGS}.md (diff empty), and PLAN.md cites them by finding id.
- The decisions table (PLAN.md:648-666) matches CONSENSUS.md M1-M8, N1-N7, R1 and R2 in substance. The rewordings are faithful, e.g. M4 'an R-only package with a configure script' and M6 adding the follow-up commit, which is CONSENSUS checklist I.
- install.R line numbers checked by applying 0001-0013 to the pristine 4.6.1 tarball in scratch (no offset or fuzz, as PLAN.md:797 says). Pristine 1324-1329 with the call at 1327 becomes merged 1427. Windows pristine 1290-1292 becomes merged 1392. CLINK_CPPFLAGS is at merged 1491. .SHLIB is at pristine 2537. The ev list and the 'skip any already set' filter match fact 1.
- Phase 3 facts in PLAN.md are correct: classify order (pkgplan.zig:129-133: r_only and zig before configure); rzig_names and installRzig with rzig/rzig.exe (verify-helpers.sh, build.zig:2590-2591); no extensionless zig-cc/zig-cxx on Windows (B26 a); find_zig.find returning !?Zig with check.zig:106 and pkgbuild.zig:376 as the only other callers; Makeconf.win's NM_FILTER empty at line 59; B43-3 is pkg-config; R CMD check's objdump is Windows-only (B43); 0013's hunks at 683, 746 and 1544; 0010 untouched; recipe build number still 8 (recipe.yaml:151, N5).
- check.zig's package mode matches PLAN.md:767-775: decided through pkgbuild.decide; R_ZIG_CONFIGURE and R_ZIG_C_STD set and unset around one system2 to CC's path in 0009; the reason before the group text; the ten parity-test.sh cases (counted); the makeflagsAssignment unit tests including CONSENSUS C's two cases (pkgplan.zig:448-455). The 0013 'older than this R' stop is present.
- CI run 38305799627 on 45892fb succeeded. Every leg ran rzig tests, contract and pkg-parity, and the packaging legs ran verify-package. ubuntu-latest's log matches the records: 119/119 tests and 91 identical. pkg-parity times on CI match the measurements table. Run 38302765293 on 47e8436 failed in windows-latest 'rzig tests' with testutil.zig:59 'Permissions has no member fromMode', as PLAN.md:1003-1010 says. upstream-zig was skipped (gated). rzig build under PyPI ziglang still ran in CI through wheel-test on the four minimal legs.
- The stress dispatch 38317654371 ran on 45892fb with targets g3 g4, TRACE true and builder auto on five runners (from the job env). The per-leg table at PLAN.md:1034-1041 matches report.json and tiers*.tsv: minutes, jobs, ok and failed counts, 0 unexpected, 16/30/14 rows (17/29/14 on Windows). Also checked: the 24 configure plus 6 rule rows on unix, the 12/9/5/2/1 split on Windows, the identical unix legs, the 14 rows with no native library, the nine non-ok rows with their first errors, gsl's 31 compiles, every tier-1 row time, and the ar (12), ranlib (2), pkg-config (s2, igraph) and cp/mkdir/rm (5) counts.
- The stress.R pattern uses 'rzig build: ... no zig ...' rather than CONSENSUS's 'no zig to build with'. This is a correct fix: groups.zig:130's no_zig text is 'no zig (ZIG_BIN, ...)'. stress.R:303 already pointed ZIG_LOCAL_CACHE_DIR run-wide, as PLAN.md:1025-1027 says.
- The feat-standalone-toolchain PLAN.md paragraph (2583-2617) and the TODO items cover each CONSENSUS H point: the scope, the phase 7 and B24 re-scope, the later items (SHLIB routing, 0010 and pkgbuild's probe, the shared runner), scenario 2's assertions, and N5.

### stress

- PR #25 is already MERGED (2026-10-13T10:07:21Z, merge commit 07e12c0). The main checkout HEAD is 07e12c0, so the file:line references in 5416d8d are the same on main. Any 'before-merge' item below now needs a follow-up docs commit on main.
- Run 38317654371 (gh run view): workflow_dispatch on 45892fb, conclusion success, 5 toolchain jobs and 5 tree jobs. The job env shows TARGETS 'g3 g4', TRACE true, R_ZIG_PKG_BUILDER auto and SKIP empty. Reference 38251125721: 548da1a, ubuntu-latest only, TARGETS g3 g4, no TRACE. CI run 38305799627 on 45892fb: build-r, 26 jobs, green.
- I recomputed tiers from the raw install logs, not from tiers.tsv, by finding each row's own 'rzig build:' line. Every leg has 60 rows (23 targets, 37 dependencies). The four unix legs each have 16 tier 1, 30 make and 14 with no line. Windows has 17 tier 1, 29 make and 14 with no line. ref-548da1a has no rzig line in any of its 60 logs. This matches tiers.tsv, tiers-intel.tsv and the PLAN per-leg table (feat-zig-pkg-build/PLAN.md:1034-1041).
- Make reasons on unix: 24 configure scripts plus 6 src/Makevars rules (filelock, jsonlite, Matrix, rlang, timechange, zip). The list is the same on all four unix legs, and macos-15-intel's tiers equal macos-latest's. Windows: 12 configure.win, 9 rules, 5 $(shell), 2 conditionals (gert ifneq, ncdf4 .ucrt ifeq) and 1 include (fstcore .ucrt). The 5 Windows/unix tier differences (gmp, gsl and nloptr tier 1 on Windows; askpass and libgeos make) are correct. The 14 rows with no native library are the same everywhere.
- The per-leg table's minutes, jobs, target/dependency counts and 0 unexpected match each leg's report.md header and report.json. The non-ok rows and their first errors (magick on both linux legs; ragg, hdf5r, ncdf4, gsl, RPostgres, s2, igraph and Rhdf5lib on Windows) match report.json, and every one is expected.
- gsl on Windows: tier 1, 31 compiles plus one link line with -lgslcblas, installed to libs/x64, then 'LoadLibrary failure: The specified procedure could not be found'. This matches the 2026-10-08 finding U3 (stress/results/2026-10-08.md:289-293). The MKL import-library cause is inferred from that same signature; it was not re-checked by inspecting symbols.
- All 19 rows x 6 columns of the tier-1 time table (PLAN:1064-1084) match report.json. s2 4.27/1.94, igraph 5.52/1.58 and stringi:bundled 8.45/3.11 are correct. The measured macos-15-intel/macos-latest ratio is 1.67 to 4.19 (the PLAN says two to four).
- No *-smoke.log on any of the five legs has a zig-cc, rzig or SHLIB line (true as stated; see finding S6 for why this is vacuous).
- No Windows install log has the string dlltool, windres, objdump or strip (true as a statement about echoed output; see finding S2).
- feat-zig-pkg-build/PLAN.md:1139-1140 is right: 'the table names no further tool to move; the dlltool/as follow-up PR stands'. The wrong wording is only in the two summary sentences (S2).
- The re-scope keeps the agreed N2 scope list (TODO.md:556-562: tier 3, configure scripts R runs, R CMD SHLIB with pkgbuild's probe and pak, R CMD config's direct callers, R CMD check's objdump, cleanup under --clean). 'nothing leaves it on the table's evidence' (TODO.md:571) matches CONSENSUS H. No scope item was dropped, apart from the cleanup.ucrt/--preclean wording in S10.
- PLAN:1144-1146 does list the preflight (fact 11; stress.R:297 sets R_MAKEVARS_USER) and the per-install cache cost as not measured. The problem is that the conclusions drawn elsewhere ignore that list (S1, S7).
