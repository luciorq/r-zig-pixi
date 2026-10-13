# Findings: review of CONSOLIDATION.md against phase 3

Read-only review (2026-10-12) by the phase 3 session of the zig-pkg-build overview (branch 8ce3f77 against main e1ce179), in three angles (coverage, preflight, channels); each finding checked by an adversarial verifier that tried to refute it. 34 confirmed, 1 refuted. Every point can be re-checked at its cited file:line.

## channels-C1 (blocker)

- Claim or gap: M3(a): zig-path installs on the base ($PREFIX) and the make reference on $COMPILE_TREE; 'Exports, argv and smoke compare across the two trees (same R, same rzig)'.
- Evidence: rzig's environment list adds <TC>/openmp only when the directory exists and the base has libomp (environment.zig:89-100, 117-127). envFlags then adds -I<env>/include on every compile on unix, and on Windows `-idirafter <dir>/include` plus -L<dir>/lib on links (compiler.zig:293-318). compile-tree.sh:40-51 requires openmp/ in the compile tree wherever the base has libomp (slim, full, openblas). RZIG_TRACE prints the argv rzig runs, environment flags included (main.zig:213-219). argv_of reduces every path to its basename and compares whole lines (pkg-parity.sh:81-87). So each compile-tree line has one extra `include` word (Windows also `-idirafter include` and `lib`) that the base line lacks.
- Consequence: pkg-parity's argv cmp fails ('rzig's command lines differ') on every leg except minimal: the core-tier default legs on all five platforms and the full and openblas legs. CI breaks once M3(a) is implemented as written.
- Suggestion: Compare like with like. Run the zig-vs-make parity (exports, argv, smoke), tier 2 and tier 3 on one tree, the compile tree. Keep only the no-make `env -i` install(s) on the base, optionally all four packages there without an argv comparison. Rewrite M3(a) accordingly.

Verifier:

I could not refute it. The code on main e1ce179 and on the branch 8ce3f77 supports every step, and the branch does not change environment.zig or envFlags (its only compiler.zig change makes linux_target pub).

1. environment.zig:89-100 and 117-128: list() adds <rzig dir>/openmp right after R's own environment, but only when that directory exists and the base has the libomp runtime (lib/libomp.so or .dylib, Windows lib/R/bin/x64/libomp.dll). The base's R_HOME/bin/toolchain holds only rzig (compile-tree.sh:13-14, B19/B30). compile-tree.sh:46-51 and 59-64 copy openmp/ into the compile tree and stop if it is missing wherever the base has libomp. verify-tree.sh:425-429 requires that runtime in every flavor whose Makeconf offers OpenMP (all but minimal), and build.zig:1297-1301 says the same for Windows. So rzig counts openmp/ on the compile tree and finds nothing on the base.

2. compiler.zig:293-318 (envFlags, called at compiler.zig:70): for each environment whose include/ exists it adds -I<dir>/include (Windows: -idirafter <dir>/include, since windows_headers_always = true), on links too, plus -L<dir>/lib where lib/ exists. On unix openmp/ holds only include/ (zigbuild/toolchain/build.zig:78); on Windows it also holds lib/libomp.lib (line 90).

3. main.zig:213-219: RZIG_TRACE prints the argv rzig actually runs (shellCommand(argv) after compiler.argv, so envFlags included), not the argv it received.

4. On the zig path, pkgplan.zig:308 takes tools from <R_HOME>/bin/toolchain of the running R, and pkgbuild.zig:197 uses rzig's own self_exe. So a base install's compiles see no openmp/, and make on the compile tree goes through the compile tree's zig-cc, which does.

5. pkg-parity.sh:81-87 cuts each path to its basename (-I/.../openmp/include becomes `include`) and compares sorted whole lines with cmp (line 127). Nothing in the normalisation removes the extra word. So every compile line from the compile tree has one more `include` word (Windows: `-idirafter include`, and `lib` on links), and cmp fails with "rzig's command lines differ".

6. The branch's build-r.yaml:100 runs pkg-parity on every leg with no `if`, including the default slim/Windows legs, where the base has libomp. Only minimal escapes.

CONSOLIDATION.md never mentions this difference: M3(a) asserts "same R, same rzig" without noting that rzig's flags depend on its sibling openmp/. So implementing M3(a) as written would break CI on every leg except minimal. I made no scratch copies.

## channels-C2 (blocker)

- Claim or gap: M3(a): 'the tier-3 refusal ... run on the base ($PREFIX)'.
- Evidence: On Windows, check.zig's buildTools requires <TC>/binutils/{nm,dlltool,as,windres,strip,objdump}.exe (check.zig:107-133). The base's TC holds rzig alone (verify-bundle.sh:140-148; compile-tree.sh:13-18). A package with configure.win is tier 3, so the preflight runs --rzig-check=build-tools before configure: today's 0009 does this for every src/ package, and M1(a) does it for tier 'make'. pkg-parity.sh:171-176 expects neg-auto to install through make with the 'rzig build: cli needs make' line, and neg-zig to fail with the R_ZIG_PKG_BUILDER message.
- Consequence: On windows-latest (core tier) both tier-3 assertions fail. The preflight stops the install with the build-tools text ('no .../binutils/nm.exe') before the hook runs. On unix the base passes only because the pixi env's make is on PATH.
- Suggestion: Run the tier-3 checks (fall-through and R_ZIG_PKG_BUILDER=zig refusal) on the compile tree, since they exercise the make path. If a tier-3 stop on the base is wanted, assert the build-tools text there, as M4's pfM does in verify-bundle.

Verifier:

The finding holds against main e1ce179 and the branch at 8ce3f77. (1) CONSOLIDATION.md's M3(a) puts "the tier-3 refusal" (pkg-parity's neg-zig) on the base ($PREFIX), which the same text says has no binutils/. (2) On main, check.zig:109-135 buildTools on Windows checks make, then sh, then <TC>/binutils/{nm,dlltool,as,windres,strip,objdump}.exe. With any of those missing it exits 127 and prints the build-tools group's text. (3) The base TC holds only rzig_names() (env.sh, verify-helpers.sh). verify-tree.sh:127-140 and verify-bundle.sh:140-146 enforce that, and the Windows base gets no binutils/ (only a conda tree may have it). (4) Patch 0009 on main runs --rzig-check=build-tools for every package with src/, before configure. M1(a) keeps that check for tier 'make', with no exception for R_ZIG_PKG_BUILDER=zig (only =make is mentioned, and it forces make). pkgplan.zig:132-133 classifies a configure.win package as tier make. (5) pkg-parity.sh sets R_MAKEVARS_USER to a file that does not exist, so makevars_user() returns empty and the preflight runs. Nothing sets R_ZIG_NO_PREFLIGHT. (6) The refusal message 'needs make, and R_ZIG_PKG_BUILDER is 'zig'' comes from 0013's rzig_build() inside run_shlib, after configure. On the Windows base the preflight stops first with the build-tools text, so the grep at pkg-parity.sh:176 fails. neg-auto at :171-173 would fail the same way if run on the base, though M3(a) may class it as a make reference for the compile tree. (7) pkg-parity runs on every build-r leg (branch build-r.yaml:99-100), and windows-latest/default is in the core build matrix (build.yaml). (8) On unix the base passes because the Renviron PATH prepend of bin/toolchain/usr/bin is harmless when the directory is missing. MAKE stays 'make', so the pixi env's make passes the check. At least the tier-3 refusal assertion fails on the core Windows leg under M3(a) with M1(a), so the finding is real.

## channels-C3 (blocker)

- Claim or gap: Interface 8: 'RZIG_TRACE line format unchanged on main; nothing' to adapt. Step 3 expects the first macOS runs of pkg-parity in CI.
- Evidence: With conda-forge zig, rzig applies the libc++ mirror for cc/cxx/fc on non-Windows whenever <zig lib>/../../lib has libc++ (main.zig:207; libcxx_mirror.zig:30-43, 108-113). It then prints `zig-cc: ZIG_LIB_DIR='…' <zig> cc …` as one trace line (main.zig:218). pixi.lock's default env has libcxx 21.1.8 on osx-arm64 and osx-64 (none on linux-64). argv_of drops every line containing `ZIG_LIB_DIR=` (pkg-parity.sh:83), and pkg-parity then requires more than one line (pkg-parity.sh:125-126). The M5 omicron driver normalised without dropping those lines (proto/hosts/m5-omicron.sh:12). pkg-parity itself has run on linux only (HANDOFF.md:35).
- Consequence: Inferred, never run: on macos-latest and macos-15-intel with conda zig, every compile and link line is dropped, so `a` is 0 and pkg-parity fails 'no rzig command lines in the zig path's log' for cli, the first package. The macOS core-tier legs fail. Upstream-zig macOS legs are unaffected (no mirror).
- Suggestion: In argv_of, strip a leading `ZIG_LIB_DIR=<word> ` prefix (sed) instead of dropping the line, and record the macOS format in PLAN/HANDOFF item 8. Run pkg-parity on omicron (pixi env) before pushing.

Verifier:

I could not refute the finding. It holds in main e1ce179 and in branch 8ce3f77, and the merge changes nothing relevant: main does not touch pkg-parity.sh, and both trees print the trace line the same way.

How the failure happens on the macOS conda legs:
1. Mirror applied: main.zig:207 calls libcxx_mirror.apply for cc/cxx/fc on every OS except Windows. The mirror is used when zigLibDir finds <bin>/../lib/zig/std/std.zig (the conda layout) and sharedLibcxx finds libc++.1.dylib in <lib_dir>/../../lib (libcxx_mirror.zig:30-43, 47-58, 108-113).
2. pixi.lock's default env has libcxx-21.1.8 on osx-arm64 and osx-64, and none on linux-64.
3. rzig picks the conda zig in both trees: the base has no zig/ group, and compile-tree.sh deliberately leaves zig/ and flang/ out ("dev compiles keep the zig that built R"). With ZIG_BIN unset, find_zig falls through to the pixi env's zig on PATH. env.sh's comment says so too ("a dev tree has no zig in either").
4. The trace line then reads `zig-cc: ZIG_LIB_DIR=<mirror> <zig> cc ...` as one line (main.zig:218 on main, 214 on the branch).
5. argv_of keeps lines that start with `zig-cc: ` and then drops any line containing `ZIG_LIB_DIR=` (pkg-parity.sh:83). For cli, which is C only, every compile and link line is dropped, so `a` is 0 and the check `[ "$a" -gt 1 ]` fails (pkg-parity.sh:125-126).

Recorded evidence that this already happens on macOS: m5-omicron.log, in history at aff0f4c, shows link lines as `zig-cc: zig zig cc -fno-sanitize=...`. omicron ran with conda zig from the default env. The first `zig` is the `ZIG_LIB_DIR=<...>/lib/zig` word reduced to its last path part by m5-omicron.sh:12's sed, which kept those lines.

Other points:
- pkg-parity has only passed on linux; HANDOFF says "linux pass 1m07; macOS/Windows legs run first in CI".
- The core tier runs macos-latest and macos-15-intel with the default env (build.yaml), and CONSOLIDATION section 6 step 3 expects their first pkg-parity runs.
- Interface 8's "nothing" to adapt is therefore wrong. The format is indeed unchanged on main, but the existing filter already breaks every macOS conda leg.
- Under M3 (a) the zig-path installs run on the base, so the failure happens whichever tree is chosen.
- The upstream-zig legs are not affected: PyPI ziglang has no lib/zig layout beside its binary, so no mirror is applied.

## coverage-C1 (major)

- Claim or gap: Section 5 (CONSOLIDATION.md:199-206): "The build-tools group is needed only by tier-3 packages: configure scripts, src/Makefile*, Makevars with rules or $(shell), and R CMD check's objdump". Phase 7 and B24 would then be rescoped to "for packages that need make".
- Evidence: Verified: R CMD SHLIB never reaches 0013's hook. .SHLIB calls .shlib_internal and therefore make (R-4.6.1 install.R:2537-2541). rzig_build is called only from run_shlib (0013 hunk @@ -683). Run-time compilation goes through R CMD SHLIB: Rcpp's sourceCpp, cppFunction and evalCpp (Rcpp/R/Attributes.R:140 `"CMD", "SHLIB"`) and rstan's model build (rstan/R/makefile_op.R:22). Tests that depend on this: contract-test.sh:70 evalCpp; the stress smokes for Rcpp (cppFunction) and rstan (stan_model) in stress/packages.tsv; the verify-bundle SHLIB blocks.
- Consequence: The scope statement and the group's first-line text would be wrong. After the merge, a base + compilers user can install Rcpp, which is tier 1 (measured: --plan-only exits 0), but evalCpp or cppFunction then fail with make missing, and no group text names it, since R CMD SHLIB runs no preflight. Phase 7 and B24 would be measured and scoped against the wrong set.
- Suggestion: State the scope as "tier-3 packages and R CMD SHLIB (run-time compilation: Rcpp attributes, inline, rstan, TMB)". Put it in the M5 records. Optionally record a later item to route R CMD SHLIB through rzig build or give it a preflight. Have the M6 table list the rows whose smoke compiles at run time (Rcpp, rstan).

Verifier:

I could not refute the finding. Each part holds against main e1ce179 and branch 8ce3f77.

1. The doc's claim. CONSOLIDATION.md:199-206 says the build-tools group is "needed only by tier-3 packages", lists configure, src/Makefile*, Makevars rules or $(shell), and R CMD check's objdump, and rescopes phase 7 and B24 to "for packages that need make". The doc never mentions R CMD SHLIB or run-time compilation (grep finds no SHLIB, sourceCpp, cppFunction, evalCpp or stan).

2. R CMD SHLIB still needs make. In pristine R 4.6.1 install.R (from build/R-4.6.1.tar.gz), .SHLIB at 2537-2541 calls .shlib_internal at 2544. That function builds `cmd <- paste(MAKE, ...)` and runs make (with `-n` even under --dry-run). None of patches 0001-0013 on either tree touches .shlib_internal or .SHLIB:
   - 0009's only hunk is at install.R 1273.
   - 0013 calls rzig_build() only from run_shlib (hunk @@ -683), inside the INSTALL path.
   - rzig has no make alias (rzig_names(): zig-cc, zig-cxx, zig-fc, zig-ar, zig-ranlib).

   So R CMD SHLIB gets neither the zig path nor a preflight.

3. Run-time compilation goes through R CMD SHLIB.
   - Rcpp 1.1.2 R/Attributes.R:140 builds `args <- c("CMD", "SHLIB", ...)` for sourceCpp, which cppFunction and evalCpp use.
   - rstan 2.32.7's cxxfunctionplus wraps inline::cxxfunction, which runs R CMD SHLIB. It also calls pkgbuild::has_build_tools, which reaches 0010's build-tools check through R CMD config. makefile_op.R:22 runs `CMD SHLIB --dry-run`, which runs make -n.

4. Rcpp is tier 1. Its src/Makevars is only `PKG_CPPFLAGS = -I../inst/include/`, and there is no configure script. The branch's PLAN.md records "Rcpp | tier 1" several times (lines 468, 553, 582). So once 0009's build-tools check is gated on tier, a base + compilers user can install Rcpp, but evalCpp or cppFunction then hit make with no preflight text.

5. The tests the finding cites exist:
   - contract-test.sh:70 runs evalCpp.
   - stress/packages.tsv:62 has the Rcpp cppFunction smoke and :66 the rstan stan_model smoke.
   - verify-bundle.sh:404/448/468/508/532 have the R CMD SHLIB blocks.

   Contract and stress run in the compile tree, where etc/Renviron puts make on PATH, so they would not expose the gap. Under M6 (b), a base-only run would see the Rcpp and rstan smokes fail for this reason.

6. Main's own standalone PLAN.md:272 lists R CMD SHLIB under "2 Compile" as a build-tools consumer. Rescoping to "for packages that need make" would drop it.

Section 5 also omits R CMD config, but M7 covers that separately. The R CMD SHLIB omission is real and not covered anywhere in the doc.

The scratch directory /data/gamma/luciorq/workspaces/temp/r-zig-pixi/consreview/verifier-C1 has been deleted.

## coverage-C2 (major)

- Claim or gap: Section 3 lists only pfC, hermetic-check, nopre and the recipe tests as the tests that change. It does not cover verify-bundle scenario 2's compiled-package block, which exists to prove a package compiled with the relocated bundle is right.
- Evidence: Verified: every check in the unix block uses R CMD SHLIB (verify-bundle.sh:729-730 C++, 773-774 Fortran, 793-794 USE_FC_TO_LINK, 835-836 $(FLIBS) with no flang, 890-895 OpenMP C/probe/-lomp, 923-924 Fortran OpenMP fomp/fompfc, 952-958 CONDA_PREFIX decoys), and so does Windows scenario 3's OpenMP block (:1286-1287). All of them stay on make. Every one of these shapes is tier 1 under pkgplan (classify, pkgplan.zig:127-144; plan ok measured for USE_FC_TO_LINK, FLIBS and Fortran OpenMP fixtures). So R CMD INSTALL of the same shapes now takes rzig build.
- Consequence: Coverage is lost silently. None of these properties is checked any more on the path R CMD INSTALL actually takes for these shapes: no rpath, static libc++, the macOS floor on objects and .so, the static flang runtime, USE_FC_TO_LINK linking through zig-fc, FLIBS without flang, libomp NEEDED and load, CONDA_PREFIX ignored. On the relocated bundle under env -i, the only rzig build runs left are pfC under M4(a) (plain C) and btA (plain C). pkg-parity compares argv on the dev tree, inside the pixi env, with cli, digest, quadprog and Rcpp: no OpenMP and no USE_FC_TO_LINK.
- Suggestion: Turn the SHLIB fixtures into packages (DESCRIPTION, NAMESPACE useDynLib) and also R CMD INSTALL each one under the default builder, with RZIG_TRACE=1. Assert `rzig build: tier 1` and run the same rpaths_of, needed_of, cxx_deps, check_minos and load checks on lib/<pkg>/libs/*.so. Keep the R CMD SHLIB runs, which are the make path and the run-time compile path (C1). Alternatively, loop the INSTALL variant over R_ZIG_PKG_BUILDER in zig and make. Add the same to Windows scenario 3's OpenMP packages.

Verifier:

The finding's core holds against the code, but one part of its consequence goes too far.

**What holds**

1. CONSOLIDATION.md never mentions R CMD SHLIB, OpenMP or USE_FC_TO_LINK. Section 3 and row 7 deal only with pfC, pfF, hermetic-check, nopre and the recipe tests.
2. Every compiled-package check in scenario 2 on main (e1ce179) uses R CMD SHLIB: verify-bundle.sh:730 (rp.cpp), :774 (fs.f), :794 (fl, USE_FC_TO_LINK), :836 (cf, $(FLIBS)), :891-895 (omp/probe/lomp), :924 (fomp/fompfc), :953/:958 (CONDA_PREFIX decoys). Windows scenario 3's OpenMP block (:1287) also uses SHLIB.
3. On main, SHLIB was a faithful stand-in for INSTALL. R CMD SHLIB (`.SHLIB`) and R CMD INSTALL's `run_shlib` both call `.shlib_internal` (build/R-4.6.1 install.R:690-705 and :2556-2563).
4. After the merge they split. Patch 0013 puts `rzig_build()` only inside `run_shlib`, so SHLIB stays on make while INSTALL of the same shapes goes to pkgplan's own derivation of the build.
5. Every one of those fixtures is tier 1:
   - `classify` (pkgplan.zig:125-144) finds no configure, no Makefile and no ObjC.
   - All their Makevars are plain assignments, including fomp_src's (:216-217).
   - `USE_FC_TO_LINK =` is detected by `lineStarting` (:215, :477).
6. In CI, no test runs an OpenMP package (C or Fortran) through rzig build on any tree:
   - pkg-parity covers only cli, digest, quadprog and Rcpp.
   - contract's data.table has a configure script, so it is tier 3 and stays on make.
   - rzig's smoke-test.sh does install an OpenMP package (rzomp), but no task or workflow runs that script.
   - pkgplan's unit tests have no OpenMP case.
7. The macOS floor and the static libc++ check are not done on INSTALL output anywhere. On the relocated bundle under env -i, plain C would be the only shape built through rzig build.

**What is overstated**

"None of these properties is checked any more on the path R CMD INSTALL actually takes" is false as written. recipe/test-toolchain.R, which the doc lists as unchanged, installs its packages with install.packages, so after the merge they go through rzig build:
- rzigfl (USE_FC_TO_LINK) links and loads, and readelf finds no flang_rt on linux. It does not check that zig-fc ran the link; pkgplan's unit test at :679 covers that plan.
- rzigf (Fortran through FLIBS) loads.
- rzigz is built with a poisoned CONDA_PREFIX and its rpath must be exactly the env's lib.

Also, pkg-parity's identical-argv check carries the compiler driver's properties over for the C++ and Fortran+FLIBS shapes, but only on the dev tree.

**Net**

The doc misses that the merge silently moves the shapes the bundle verification was built for off the path it tests. It also misses that nothing on the rzig build path covers OpenMP, the macOS floor or static libc++, or anything beyond plain C on the relocated bundle. Calling this "major" is arguable, but the gap is real.

## coverage-C3 (major)

- Claim or gap: Not in the document: wheel-test.sh changes builder, and the wheel's GNU make stops being exercised.
- Evidence: Verified: rzigwheeltest is dot.c + sum.cpp with `PKG_LIBS = $(BLAS_LIBS) $(FLIBS)` (wheel-test.sh:69-103), and rzigwheelz is z.c with `PKG_LIBS = -lz` (:250-251). Both are tier 1 (measured: --plan-only exits 0 for the same layout). That covers all five installs at :184, :226, :252, :262 and :272. The header says these are "built by the bundled GNU make, three times" (:17-23). After the merge the only make check left is Sys.which (:150-155).
- Consequence: Nothing in the wheel test runs a build with the toolchain wheel's make (B23) any more, so a broken usr/bin/make in the wheel would pass CI. The test also becomes, unannounced, the first run of rzig build under PyPI ziglang, including `python3 -m ziglang` as the zig that `zig build` runs (:270-277). That path is not exercised by pkg-parity (pixi env) and is unverified (inference).
- Suggestion: Run one install with R_ZIG_PKG_BUILDER=make, for example the bundled bin/R run at :262. Add a tier-3 package (mkpkg-style Makevars with a rule) so make builds something real from the wheel. Run the console-script install with RZIG_TRACE=1 and grep `rzig build: tier 1`. Update the header.

Verifier:

The finding holds. I could not refute it, checked against main e1ce179 and branch 8ce3f77 as they would merge.

1. **The merge leaves scripts/wheel-test.sh unchanged.** I compared the `git merge-tree` result (6ea8ae5) with main's file and they are identical. Its header (lines 17-23) still says the package is "built by the bundled GNU make, three times".

2. **The hook will run in the wheel.** Patch 0013 (`zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch`) runs `rzig build` before the make path. It does this whenever `R_ZIG_PKG_BUILDER` is not `make` (the default is `auto`) and `R_HOME/bin/toolchain/rzig` exists. After the merge, `installRzig` adds `rzig` to the unix name list; the conflict hunk resolves that way under the document's recommended M2 (a). `scripts/make-wheel.py` puts everything under `lib/R/bin/toolchain/` into the r-zig-toolchain wheel and keeps file modes. `share/zig/rpkg` goes into the r-zig wheel. `run()` uses `env -i`, so `R_ZIG_PKG_BUILDER` cannot leak into the test, and nothing in the tree sets it.

3. **Both test packages are tier 1.** I ran the branch's built rzig (`.claude/worktrees/feat-zig-pkg-build/dist/R-4.6.1-slim-zig/lib/R/bin/toolchain/rzig`) on scratch copies of the two layouts:
   - rzigwheeltest: dot.c, sum.cpp and `PKG_LIBS = $(BLAS_LIBS) $(FLIBS)`.
   - rzigwheelz: z.c and `PKG_LIBS = -lz`.

   `--classify` printed `makevars` for both, and `--plan-only` exited 0 with full plans. The tree was slim, not minimal, but the Makeconf structure is the same (compilers under `$(R_HOME)/bin/toolchain`).

   So all five installs (lines 184, 226, 252, 262, 272) go through `rzig build`. If `rzig build` fails with anything other than exit 3, 0013 returns an error and does not fall back to make. `--preclean` does not reach make either: `run_clean` only runs `make clean` when `src/Makefile` exists, and the `shlib-clean` step inside `.shlib_internal` is skipped.

4. **No record of the branch mentions the wheel.** Grepping CONSOLIDATION.md, PLAN.md and HANDOFF.md for "wheel" finds nothing. The local test list in section 6 of CONSOLIDATION.md does not include wheel-test either.

Three points are overstated, but none of them refutes the finding:
- **The wheel test still checks make in one more place.** Until M1 (a) is adopted, 0009's `--rzig-check=build-tools` still runs on every compiled install. It only locates make (`check.zig` `buildTools`) and never runs it, so it does not exercise make any more than `Sys.which` does.
- **"Would pass CI" applies only to breakage specific to the wheel.** verify-bundle.sh still builds with the build-tools group's make, through `R CMD SHLIB` and the `make -k -j 2` Makefile run. That is the same make binary, packaged differently.
- **This is not the first run of `rzig build` under PyPI's zig.** The gated upstream legs run pkg-parity with the PyPI ziglang binary through `fetch-zig`. Only the `import ziglang` / `python3 -m ziglang` lookup is new to the wheel test.

## coverage-C4 (major)

- Claim or gap: CONSOLIDATION.md:101-102: "recipe/test-preflight.R, recipe/test-toolchain.R: they look for CC's name; unchanged."
- Evidence: Verified: test-toolchain.R:7-8 (CC's name) is indeed unchanged. But four of its five installs become tier 1 and switch to rzig build: rzigc (:25-40, one.c + two.cpp, no Makevars), rzigz (:102-106, PKG_LIBS = -lz), rzigf (:207-213, unix only, s.f with no Makevars) and rzigfl (:222, `USE_FC_TO_LINK =`). Only rzigar (:148-159, Makevars with rules) stays on make. The conda r-zig-toolchain declares make and, on Windows, m2-make as run deps (recipe.yaml:466-505). HANDOFF.md:105-109 records that kappa's make path failed for C++ and Fortran packages (SHLIB_CXXLD and FCLIBS_XTRA quoting).
- Consequence: The assertions still hold (the rpath check at :110-133 and readelf at :224-227 now test rzig build's link). But in the conda package's own test, make no longer builds the C++ link, the Fortran link with FLIBS, or USE_FC_TO_LINK. Those are exactly the make-path shapes that broke on Windows before, and they are what every tier-3 package with C++ or Fortran still uses.
- Suggestion: Repeat rzigc and rzigfl (and rzigf on unix) with R_ZIG_PKG_BUILDER=make into a second library, which is a few seconds each. Or set it for the existing installs and add one default-builder install with RZIG_TRACE. Correct section 3's line.

Verifier:

The finding holds against main e1ce179 and branch 8ce3f77 as they would merge. I checked each point in the code.

1. **The branch does not touch the recipe tests.** `git diff --stat b490bdf..8ce3f77` shows no `recipe/` file, and `test-toolchain.R` never sets `R_ZIG_PKG_BUILDER`. Patch 0013 therefore uses its default, `auto`. In that mode `rzig_build()` runs whenever `R_HOME/bin/toolchain/rzig` exists. It falls back to make only on exit 3 and treats any other non-zero exit as an error. The branch's installRzig adds `rzig` / `rzig.exe` to `bin/toolchain`, which M2(a) keeps. That directory is the `r-zig-toolchain` package's content (`recipe.yaml:463-465`). `share/zig/rpkg` lands in `r-zig-slim`. So both are present in that package's test env.

2. **Four of the five installs plan as tier 1.** I read `pkgplan.zig` `classify()` and `plan()`:
   - `rzigc` (`test-toolchain.R:25-40`): `one.c` + `two.cpp`, no Makevars, so tier 1 with a C++ link (`SHLIB_CXXLD`).
   - `rzigz` (`:102-106`): Makevars is `PKG_LIBS = -lz`, assignments only.
   - `rzigf` (`:207-213`, unix only): `s.f` with `$(FLIBS) $(FCLIBS_XTRA)` added to `SHLIB_LIBADD`.
   - `rzigfl` (`:222`): `USE_FC_TO_LINK =` takes the `SHLIB_FCLD` branch.

   Main's Makeconf names `$(R_HOME)/bin/toolchain/zig-cc`, `zig-cxx` and `zig-fc` (`build.zig:583,1837`; `dist` Makeconf lines 16, 31, 63), so `toolName()` accepts all three compilers. No NeedsMake path applies. `rzigar` (`:148-159`) has rule lines, and `makefile.zig:195` fails a rule in makevars mode, so it alone stays on make. R 4.6.1's `install.R` calls `run_shlib` for packages without a Makevars too (lines 1520-1540), so the hook covers `rzigc`.

3. **Make stays a run dependency.** `r-zig-toolchain` declares `make >=4.4`, plus `m2-make` on Windows (`recipe.yaml` around 466-518).

4. **The HANDOFF record says what the finding cites.** `HANDOFF.md:105-109` records that kappa's make path failed for C++ and Fortran packages (`SHLIB_CXXLD` and `FCLIBS_XTRA` quoting).

5. **The coverage gap is real.** After the merge, the conda package's own test exercises make only for the archive-rule package. pkg-parity still runs `R_ZIG_PKG_BUILDER=make` references for Rcpp and quadprog on the dist tree in CI. But it has no `USE_FC_TO_LINK` package, and it does not cover the conda package.

**Verdict on CONSOLIDATION.md:101-102.** The line sits in section 3, "Tests that change", and calls the recipe tests "unchanged". That holds for their assertions but not for what they exercise, so the line is incomplete as the finding says.

All citations match, with one exception: the recipe.yaml range (466-505) is slightly off and should end near 518. Whether the gap counts as "major" is a judgment call, but every factual claim holds. I created no scratch files.

## coverage-C5 (major)

- Claim or gap: Not in the document: contract-test.sh changes builder for three of its six packages, and its make-path coverage for mixed C++/Fortran goes away on unix.
- Evidence: Verified by --classify/--plan-only on the CRAN sources: Rcpp (src/Makevars of assignments), minqa (unix Makevars is comments only; minqa.cpp plus 18 .f) and quadprog are tier 1. On Windows, Rcpp and quadprog are tier 1, minqa's Makevars.win uses $(shell ...) (tier 3) and data.table's Makevars.win has an `all:` rule. data.table, pak and ps have configure scripts (tier 3). pak's embedded cli, lpSolve, pkgcache and yaml are tier 1. The comments at contract-test.sh:97-105 ("R CMD SHLIB compiles every file with $(FC) ... links through SHLIB_LD") and pixi.toml:87-90 describe make. pkg-parity's PKGS are cli, digest, quadprog and Rcpp (pkg-parity.sh:44), not minqa.
- Consequence: The assertions hold if rzig build works. But on unix, a C++ + Fortran package linked through SHLIB_CXXLD with FLIBS goes through make in no CI gate any more (RcppArmadillo has that shape, but it is only in stress, which is not a gate). Users' tier-3 C++/Fortran packages rely on that path.
- Suggestion: Add minqa to pkg-parity's PKGS, which compares both builders on the same package. Update the contract comments ("through rzig build on unix for Rcpp, minqa, quadprog; make for data.table, pak, ps"), or run contract once with R_ZIG_PKG_BUILDER=make on one leg.

Verifier:

I could not refute the finding. It holds against main e1ce179 and the branch 8ce3f77.

1. **The document is silent.** CONSOLIDATION.md mentions contract only for M3 (which tree pkg-parity uses), the pixi.toml conflict, the build-r.yaml step order and the step 6 sequence. Section 3, "Tests that change", lists only verify-bundle scenarios 2 and 3, hermetic-check and the recipe tests. Neither PLAN.md nor HANDOFF.md says that contract changes builder.

2. **Contract's assertions still pass, but three of its six packages change builder on unix.**
   - The branch does not touch scripts/contract-test.sh (it is not in `git diff b490bdf 8ce3f77`).
   - Patch 0013's `rzig_build()` runs before make in `run_shlib` whenever R_HOME/bin/toolchain/rzig exists. The default is `R_ZIG_PKG_BUILDER=auto`, and nothing in pixi.toml, the workflows or the scripts sets it. After the merge (M2 a), the compile tree copies PREFIX, so rzig is present.
   - I ran the branch's built rzig (worktree dist, `--classify` and `--plan-only`) on scratch copies of the CRAN sources. Rcpp 1.1.2, minqa 1.2.8 and quadprog 1.5-8 all classify as `makevars` (tier 1) and plan successfully.
   - minqa's plan has `link_driver = "zig-cxx"` with minqa.cpp and the .f sources. There are 17 .f files, not 18, which does not change the claim. Its unix Makevars is only comments, and its Makevars.win uses `$(shell ...)`, so on Windows it stays on make.
   - data.table, ps and pak (fetched from CRAN) all have a configure script, so they are tier 3.
   - The comments at contract-test.sh:97-105 and pixi.toml:87-90 describe the make path.

3. **No CI gate covers the unix make path for mixed C++/Fortran any more.**
   - pkg-parity's `PKGS="cli digest quadprog Rcpp"` (pkg-parity.sh:44) does not include minqa.
   - verify-bundle's R CMD SHLIB fixtures are C++ only or Fortran only.
   - Its scenario 3 bt packages are C, recipe/test-toolchain.R's packages are C+C++ or Fortran only, and hermetic-check uses C or no src/.
   - stress.yaml says it is "a diagnostic, never a gate", dispatch only. That is where the RcppArmadillo row lives (configure, so make).
   - Only Windows legs still build minqa through make.

The finding's consequence and its suggestions (add minqa to PKGS, fix the comments, or run one contract leg with `R_ZIG_PKG_BUILDER=make`) follow from these facts. Scratch at consreview/verifier-C5 was deleted.

## coverage-C6 (major)

- Claim or gap: M1(a): rzig "classifies the package with pkgplan.zig (the same code the hook uses)" and runs build-tools only when the tier is make, with reasons such as "Makevars: a rule at line N". M1(b): `rzig build --classify` "prints r_only, makevars, zig or make", and the build-tools check is added only for `make`.
- Evidence: Verified: classify() never reads the Makevars (pkgplan.zig:127-144). Rules, $(shell), conditionals and foreign compilers are only found in plan() (:270-277, :297-303, :399-406). Measured with the branch's `rzig build --classify` over 125 CRAN sources: Matrix, rlang, jsonlite, processx, zip, utf8, timechange, StanHeaders, rstan, filelock and QuickJSR print `makevars`, while --plan-only exits 3. A Makevars with a rule (btLib's) prints `makevars` too. classify() also returns r_only when src/ is absent, before it looks for configure (:129 is checked before :132-133). Measured: a package with configure and no src/ prints r_only. Rhdf5lib (a stress row: configure and configure.win, no src/) is one. 0009's condition explicitly covers configure-without-src. In addition, the preflight runs before install.R sets CLINK_CPPFLAGS (scratch-merged install.R: preflight at line 1322, Sys.setenv(CLINK_CPPFLAGS) at 1472), and without the hook's --c-std, so plan()'s "C<nn> standard requested but CC<nn> is not defined" result (pkgplan.zig:288-291) can differ between preflight and hook.
- Consequence: M1(b) as written, and M1(a) if implemented with classify() alone, skip the build-tools check for rule-Makevars and configure-only packages. On base + compilers those then fail inside make or configure with a raw `make: not found`, not the group text. M4(a)'s proposed pfM (a Makevars with a rule) would fail CI against such an implementation. The "same code the hook uses" claim also hides the difference in inputs.
- Suggestion: Specify --rzig-check=package as: configure/configure.win/ucrt present means tier 3, checked before the src/ test (as 0009's condition does); then plan(), not only classify(), with the hook's --c-std (use_C) passed. Drop or correct M1(b)'s --classify description. Add a configure-only package (no src/) next to pfM in scenario 2's no-build-tools checks.

Verifier:

I tried to refute the finding and could not. Its core holds against the branch code at 8ce3f77 and main at e1ce179.

1. **`classify()` never reads the Makevars.** In pkgplan.zig:127-144 it only checks file existence, in this order: src/ is a directory (:129, before anything else), build.zig, configure / configure.ucrt / configure.win (:132-133), Makefile*, Objective-C sources, and whether a Makevars file exists. Rules, conditionals, `$(shell)` and foreign compilers are only caught in `plan()`: the Makevars load at :270-273 ("a rule or target line", makefile.zig:195), OBJECTS at :297-303, and `toolName` at :399-406.

2. **`--classify` prints `classify()` alone** (pkgbuild.zig:180-187). I ran the branch's built rzig (worktree dist/R-4.6.1-slim-zig) on scratch packages:
   - A C package whose Makevars has a rule printed `makevars`, while `--plan-only` exited 3 with "src/Makevars has a rule or target line".
   - A package with configure and no src/ printed `r_only`.
   - Rhdf5lib 2.0.0 from the stress cache printed `r_only`. Its tarball has configure and configure.win and no src/; its configure builds HDF5 through cmake and make.

3. **0009 on main checks more cases.** Its condition covers configure (or configure.win / configure.ucrt) without src/. It runs `--rzig-check=build-tools` for all such packages, Rhdf5lib included.

4. **Nothing catches this later.** 0013's hook just falls through to the make path on exit 3 and runs no build-tools check. So if the preflight skips that check for a rule-Makevars package, the failure is a raw make error, not the group text. For a configure-only package, the failure is inside configure (Windows needs sh, which is in the build-tools group; Rhdf5lib's cmake needs make).

What this means for the consolidation doc's menus:
- **M1(b) is described wrongly.** Gating build-tools on `--classify` == make misses rule-Makevars and configure-only packages. The doc lists only cosmetic costs for it.
- **M1(a) has the same gap.** It says it classifies "with pkgplan.zig (the same code the hook uses)" and that "a configure script is tier 3 either way". Both are false for configure without src/, which `classify()` returns as `r_only` before it looks for configure. The "Makevars: a rule at line N" reason it promises can only come from `plan()`, which M1(a) does not name.

Line positions are confirmed by a scratch-patched install.R (CRAN tarball + 0005 + 0009 + 0013): the preflight is at line 1322 and `Sys.setenv(CLINK_CPPFLAGS)` at 1472.

The finding's last point, the "C<nn> standard requested but CC<nn> is not defined" divergence, is weak in practice. Makeconf defines CC17, CC23, CC90 and CC99, and `use_C` is already set from DESCRIPTION (install.R:426-430) before the preflight runs. That does not change the main result. I deleted my scratch directory.

## coverage-C7 (major)

- Claim or gap: 0013's header says it "derives from etc/Makeconf and the Makevars the compile and link lines make would have run". The design treats the LTO record as make-only.
- Evidence: Verified: neither makefile.zig nor pkgplan.zig reads MAKEFLAGS. grep finds MAKEFLAGS only in 0013's -j regex and pkgbuild's -j use. GNU make takes `VAR=value` words in MAKEFLAGS as command-line variables, and verify-bundle's LTO record depends on that (verify-bundle.sh:1316-1343, MAKEFLAGS='LTO_OPT=-flto'). Its packages ltodef and ltonodef are rule-Makevars (tier 3), so the record never sees a tier-1 package.
- Consequence: A tier-1 package installed with MAKEFLAGS='LTO_OPT=-flto' (or CFLAGS=..., or any variable) gets make's flags with make and different flags with rzig build. Nothing reports it, and no test would catch it.
- Suggestion: Have pkgplan read MAKEFLAGS: treat each `NAME=value` word as setCommandLine, or return NeedsMake ("MAKEFLAGS sets NAME") when one is present. Add a tier-1 twin to the LTO record (mkpkg without `lib`) so both builders are recorded.

Verifier:

The finding holds against main e1ce179 and the branch at 8ce3f77. (1) The 0013 header says, word for word, that rzig build "derives from etc/Makeconf and the Makevars the compile and link lines make would have run". (2) Nothing in the branch's rzig reads MAKEFLAGS (zigbuild/tools/rzig/pkgplan.zig, makefile.zig, pkgbuild.zig). Main's rzig doesn't either; its only MAKEFLAGS is 0010's `MAKEFLAGS=` for R CMD config. pkgplan.zig:172 calls `e.importEnvironment(ctx.env)`, which brings in MAKEFLAGS only as an ordinary environment variable. The only command-line variables are the ones pkgplan sets itself with setCommandLine (install.R's overrides: SHLIB, OBJECTS, CXX*, LTO/LTO_FC from --use-lto, and so on). The 0013 hook takes only the `-j` number out of MAKEFLAGS. (3) I tested with GNU make 4.3: MAKEFLAGS='LTO_OPT=-flto' turns on an `ifneq "$(LTO_OPT)" ""` block, and MAKEFLAGS='CFLAGS=-O0' (with or without -j2) overrides a file assignment, so make treats them as command-line variables. In R 4.6.1, install.R and .shlib_internal leave MAKEFLAGS alone; only check.R clears it, for vignette builds. (4) On Windows, zigbuild/config/win-x86_64-full/Makeconf.win:217-219 sets `LTO =` and `LTO_OPT =`, and its block at line 286 (`ifneq "$(LTO_OPT)" ""`, `LTO = $(LTO_OPT)`) puts -flto into CFLAGS and the others. So a tier-1 package built through make with MAKEFLAGS='LTO_OPT=-flto' compiles with -flto, and the same package through rzig build does not. A CFLAGS=... word differs between the two builders on every OS. (5) main's scripts/verify-bundle.sh:1316-1360 is the LTO record and uses MAKEFLAGS='LTO_OPT=-flto'. Its packages come from `mkpkg ... lib` (line 236ff), whose Makevars has rules, so they are tier 3 and the record never runs a tier-1 package through rzig build. scripts/pkg-parity.sh:56 runs `unset R_ZIG_PKG_BUILDER MAKEFLAGS`, PLAN.md and HANDOFF.md mention no such gap, and CONSOLIDATION.md says nothing about MAKEFLAGS or the LTO record. So nothing reports the difference and no test covers it. One small inaccuracy in the evidence that doesn't change the conclusion: pkgbuild.zig does not use MAKEFLAGS; its -j comes from the argument 0013 passes.

## preflight-F1 (major)

- Claim or gap: CONSOLIDATION.md:23 says install.R on unix never runs `R CMD config` itself (only the Windows configure.win branch does, install.R 1356), so 0010 is untouched by tiers. M7(a) (:77-78) says tiers 0 to 2 never meet it. Section 2's order (:39) says configure runs for tier 3 only, and M1(a) (:61-62) says a configure script is tier 3 either way.
- Evidence: Pristine install.R:1307 and 1324-1329 run `R CMD config` on unix through vapply/system2(stdout = TRUE) whenever use_configure is set and an executable ./configure exists (main-patched 1342 and 1359-1364). '1356' is the branch's own numbering for the Windows call; the branch's unix call is at 1391. pkgplan.classify returns r_only at pkgplan.zig:129 and zig at :130, before the configure test at :132-133. The test at pkgplan.zig:697-699 asserts that build.zig plus configure gives Tier.zig, and branch PLAN.md:75 says tier 2 'wins over Makevars and configure'. The document's own vocabulary line (:12-14) puts configure in tier 3, which contradicts the classifier it proposes to reuse.
- Consequence: The facts used to justify M7(a), the 0009/0013 ordering and M1(a)'s agreement argument are wrong. Tiers 0 and 2, as pkgplan classifies them, do meet R CMD config (and the configure script) whenever R runs a configure.
- Suggestion: Rewrite row 4 and M7(a). install.R calls R CMD config (unix) or Rcmd config (Windows) only for a configure script R runs, and then for each unset CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and FCFLAGS. Tier 1 never has one; tiers 0 and 2 can. Fix the vocabulary to say that src/build.zig wins over configure in rzig, while R still runs the configure.

Verifier:

I could not refute the finding; it matches the code. Pristine install.R from build/R-4.6.1.tar.gz has `if (use_configure)` at line 1277, at the top level of do_install_source and not gated on src/. Its unix branch tests `file_test("-x", "configure")` at 1307. At 1324-1329 it runs `system2(file.path(R.home("bin"), "R"), c("CMD", "config", x), stdout = TRUE)` inside vapply for each unset CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and FCFLAGS. I applied each tree's patch series to scratch copies. On main the test is at 1342 and the call at 1362. On the branch the Windows `Rcmd config` call is at 1356 (the line CONSOLIDATION.md:23 cites) and the unix `R CMD config` call is at 1391. So the claim at CONSOLIDATION.md:23 that "install.R on unix never runs `R CMD config` itself" is false. Main's 0010 (src/scripts/config) runs `zig-cc --rzig-check=build-tools` and exits non-zero without make, so every install where R runs configure on unix reaches the build-tools check. pkgplan.zig confirms that tiers 0 and 2 can have a configure script. classify returns r_only when there is no src/ (:129) and zig when src/build.zig exists (:130), both before the configure test (:132-133). The test at :697-699 asserts that build.zig plus configure gives Tier.zig, and branch PLAN.md:73-75 defines tier 0 as "no src/" and tier 2 as winning "over Makevars and configure". This makes M7(a)'s "tiers 0 to 2 never meet it" (:77-78) wrong under pkgplan's classification, which M1(a) proposes to reuse. It also makes section 2's "configure (tier 3 only)" (:39) and M1(a)'s "a configure script is tier 3 either way" (:61-62) wrong. The concrete failure under the proposed gating: a tier-2 package with build.zig and configure, or a no-src package with configure, on base plus compilers with no make. M1(a) skips its build-tools check, R runs configure, install.R's R CMD config call hits 0010 and fails, and the install errors in vapply or in configure instead of at the preflight. The line numbers in the finding are accurate to within one line (main's call is at 1362, inside its cited 1359-1364 range).

## preflight-F2 (major)

- Claim or gap: M1(a) runs the build-tools check only when the tier is `make`, and R's use_configure is not consulted.
- Evidence: Today 0009's condition includes `use_configure && <R-run configure>` (main install.R:1281-1286), so main checks the compilers and the build tools for these packages. Under (a), a package with no src/ plus configure classifies r_only, and a package with src/build.zig plus configure classifies zig (pkgplan.zig:129-130), so neither gets the build-tools check. install.R then runs R CMD config (main 1359-1364), and 0010 makes rzig exit 127. R turns that into 'error in running command' (sys-unix.c:1012-1017), after rzig's text and without 0009's ERROR line. On Windows, Rcmd config needs sh (rcmdfn.c:532-533), and so does `sh configure.win` (main 1325-1333). These runtime messages are inferred from the code, not run. No test covers either case: zighello has no configure, and scenario 3's nopre is tier make.
- Consequence: A regression against main for tier-0 and tier-2 packages with a configure script on base + compilers: the install fails deep with R's own error instead of the clean stop before configure. CI stays green, so the coverage loss is silent.
- Suggestion: Keep the R-side trigger in 0009: also run `--rzig-check=build-tools` when `use_configure && <the configure R runs>`, the expression already at install.R:1283-1285. That is exact, including under --no-configure. Alternatively, have `--rzig-check=package` treat an R-run configure as needing the build tools whatever the tier; that over-asks only under --no-configure. Keep main's compilers check for tier 0 + configure. Add a fixture, zighello (or an R-only package) plus configure_marker on base + compilers, that must stop with the build-tools text and leave configure not run.

Verifier:

I could not refute the finding. I checked it against main e1ce179 and branch 8ce3f77 by applying both patch sets to the CRAN R-4.6.1 install.R in a scratch copy, which I have since deleted.

1. **Classification.** The doc says M1(a) classifies with pkgplan.zig's `classify`, the same code the hook uses (pkgbuild.zig:180). That function returns early:
   - `.r_only` when src/ is missing (pkgplan.zig:129);
   - `.zig` when src/build.zig exists (pkgplan.zig:130);
   - only after both of those does it test configure, configure.ucrt or configure.win (pkgplan.zig:131-133).
   So a package with no src/ and a configure script is tier 0, and one with src/build.zig and a configure script is tier 2. Under "build-tools check only when the tier is make", neither gets the build-tools check. The doc's reason at CONSOLIDATION.md:60-62, "a configure script is tier 3 either way", is false for both cases.

2. **Main checks these packages today.** 0009's condition (patched install.R:1281-1286) includes `use_configure && file.exists("configure")`, or configure.win / configure.ucrt on Windows. Main therefore runs `--rzig-check` and then `--rzig-check=build-tools`, and stops through `pkgerrmsg` with the 0009 ERROR line.

3. **Install.R on unix does run R CMD config before configure.** It sits inside the `file_test("-x","configure")` branch (patched 1359-1364; the same code is in pristine install.R:1327).
   - The doc says the opposite at CONSOLIDATION.md:23 ("install.R on unix never runs R CMD config itself"). Main's own scripts/verify-bundle.sh:533 and 1369-1371 say R CMD config runs before configure and needs the build tools.
   - 0010 makes R CMD config exit with the check's status, which is 127 when make is missing (check.zig:121). R's bin/R and Rcmd pass that status on through `exec`.
   - `system2(..., stdout=TRUE)` with status 127 hits `cmdError` "error in running command" (sys-unix.c:1012-1017). That is an R error, not the 0009 ERROR line. rzig's group text still shows, because stderr is not captured.
   - On Windows, Rcmd config runs `sh config.sh` (rcmdfn.c:532-533), and install.R then runs `sh configure.win`.

4. **No test covers these cases.**
   - zighello has only DESCRIPTION, NAMESPACE, R/ and src/{build.zig, hello.zig}, with no configure.
   - Scenario 3's nopre is `mkpkg` (src/f.c) plus `configure_marker`, so it is tier make.
   - Scenario 2 uses pfC and pfF, neither of which has a configure script.

**One caveat on the consequence.** On unix, configure still does not run, because R CMD config fails first. What is lost is the clean preflight stop, the 0009 ERROR line and the deliberate order, not the "before configure" property itself. The user still sees rzig's build-tools text, followed by R's generic error. This affects how severe the finding is, not whether it is real.

## preflight-F3 (major)

- Claim or gap: M1(a) 'classifies the package with pkgplan.zig (the same code the hook uses)', and its failing line names reasons such as 'Makevars: a rule at line N'. M1(b) 'calls `rzig build --classify`' and adds the build-tools check only for `make`.
- Evidence: classify() (pkgplan.zig:127-144) looks only at src/, build.zig, configure, src/Makefile* and Objective-C. Every Makevars-level tier-3 reason is raised only in plan(): rules, include, conditionals, $(shell), shell metacharacters, a foreign compiler (including from a site or user Makevars), OBJECTS without a source, an undefined CXXnn or CCnn, C++98, and an unreadable Makeconf (pkgplan.zig:229, 270-281, 284-291, 297, 303, 365, 370, 406). The test at pkgplan.zig:714-729 asserts that classify gives `.makevars` for each of these and only plan() returns NeedsMake. `--classify` prints classify() alone (pkgbuild.zig:179-187). The hook runs plan() (pkgbuild.zig:198-214) and exits 3, which sends install.R to the make path. The reason text 'Makevars: a rule at line N' does not exist; plan() says "src/Makevars has a rule or target line: '<line>'" (pkgplan.zig:715).
- Consequence: If (a) is built as worded, or if (b) is chosen, every Makevars-level tier-3 package passes the preflight without the build tools and then fails in make with 'make: not found'. One example is verify-bundle's own mkpkg `lib` variant, whose Makevars has a `$(SHLIB): lib/libval.a` rule (verify-bundle.sh:244-248). This is exactly the deep failure 0009 exists to prevent, and (b)'s menu entry does not mention the hole.
- Suggestion: Specify that `--rzig-check=package` runs classify() then plan(), sharing one function with pkgbuild.run, so that the preflight tier and the hook tier come from the same code path. Make M4(a)'s pfM the Makevars-rule variant (`mkpkg ... lib`) rather than a configure, so that a classify-only implementation fails the test. State (b)'s gap in its menu entry, and quote the real reason text.

Verifier:

I could not refute the finding. It holds against the branch at 8ce3f77 and main at e1ce179.

(1) classify() in pkgplan.zig:127-144 only returns tier `make` for four cases: a configure script, src/Makefile*, an Objective-C source, or src/build.zig (which gives `zig`). Every other Makevars package is `.makevars`.

(2) Each Makevars-level tier-3 reason comes only from plan(). These are the rule/conditional/$(shell)/metacharacter errors from makefile.zig via pkgplan.zig:271, the Makeconf read at 158/275, C++98 at 229, an undefined CXXnn/CCnn at 286/290, OBJECTS at 297/303, and a foreign compiler at 406.

(3) The unit test at pkgplan.zig:714-729 asserts that classify gives Tier.makevars for each bad Makevars and that only plan() returns NeedsMake. The real text is "src/Makevars has a rule or target line: '...'".

(4) The string "a rule at line" appears nowhere on the branch except in CONSOLIDATION.md.

(5) pkgbuild.zig:183-186: `--classify` prints class.tier straight after classify() and returns before plan() runs.

(6) Patch 0013's rzig_build() treats exit 3 as NA, so run_shlib falls through to make.

(7) mkpkg's `lib` variant in verify-bundle.sh:244-248 writes a Makevars with `$(SHLIB): lib/libval.a` and an archive rule. classify gives `makevars` for it, and plan() rejects it.

So M1(b) as written (build-tools check only when `--classify` prints `make`) lets this kind of package through the preflight without make. It then fails in the make path, which is the deep failure 0009 exists to prevent. The (b) entry in the document does not mention this gap.

M1(a) is ambiguous rather than flatly wrong. The vocabulary and section 5 count "rules, $(shell)" as tier 3, which suggests the author meant plan() to be included. But the text says "classifies ... with pkgplan.zig" and "the tier is `make`", which is the name of classify()'s enum value, and it quotes a reason string that does not exist. Built literally, it would have the same hole. M4(a) also allows "(or a configure script)" for pfM, and a classify-only build would pass that test.

## channels-C4 (major)

- Claim or gap: Section 3: 'exactly one assertion flips: scenario 2's pfC. hermetic-check and the recipe tests do not move.'
- Evidence: With the default R_ZIG_PKG_BUILDER=auto, every tier-1 package in existing tests now builds through rzig build and not make. contract-test.sh:47-60 (Rcpp, quadprog and minqa are tier 1; data.table, pak and ps have configure). recipe/test-toolchain.R (rzigc :25-40, rzigz :102-106, rzigf :210, rzigfl :222 are tier 1; only rzigar :148-159 still uses make). wheel-test.sh:17-23 says the package is 'built by the bundled GNU make, three times', but rzigwheeltest (`PKG_LIBS = $(BLAS_LIBS) $(FLIBS)`, :103) is tier 1. verify-bundle scenario 3's btA (mkpkg with no Makevars, :998) is tier 1 while its message says 'packages built through the group's make' (:1092, Windows :1309). None of these tests asserts which path ran.
- Consequence: Coverage is silently lost. Make-path builds of tier-1 packages are no longer exercised by contract, by the conda recipe test, or by the wheel test, where the bundled make now builds nothing and is only checked through Sys.which (wheel-test.sh:150-155). The remaining make coverage is pkg-parity's four reference packages and the tier-3 rows. The tests' stated claims become partly vacuous.
- Suggestion: List these tests in section 3. For each one, either assert the path (RZIG_TRACE=1 plus a grep for `rzig build: tier 1`, or `needs make`), or keep a make leg with R_ZIG_PKG_BUILDER=make or a tier-3 fixture: for example a wheel-test package whose Makevars has a rule, and a scenario-3 btA under R_ZIG_PKG_BUILDER=make. Fix the claim texts in wheel-test.sh and verify-bundle.sh.

Verifier:

The finding holds against the code. I tried to refute each part and could not.

**The hook runs by default.**
- Patch 0013 sets `builder <- Sys.getenv("R_ZIG_PKG_BUILDER", "auto")` and calls `rzig_build()` at the top of `run_shlib`. It returns before the make path whenever rzig exists and exits with something other than 3.
- After the merge rzig exists in every tree, because the doc's M2 adds it to `rzig_names()` and installRzig.
- Nothing sets `R_ZIG_PKG_BUILDER` outside pkg-parity.sh and the proto host scripts. `git grep` finds no use on main and none in pixi.toml.
- pkgbuild.zig has no fallback for "make is on PATH". It returns exit 3 only when classify or plan says NeedsMake.

**The cited packages are tier 1.**
- **contract-test.sh:** pkg-parity.sh:113 asserts `rzig build: tier 1` for Rcpp and quadprog. minqa's src/Makevars holds only a comment, so it classifies as tier 1. data.table and ps have a `configure` (I checked the cached tarballs).
- **recipe/test-toolchain.R:** rzigc (:25-40, no Makevars), rzigz (`PKG_LIBS = -lz`), rzigf (no Makevars) and rzigfl (`USE_FC_TO_LINK =`, which pkgplan.zig:215 handles as tier 1) are all tier 1. Only rzigar, whose Makevars has rules (:148-159), is tier 3.
- **wheel-test.sh:** rzigwheeltest's Makevars is `PKG_LIBS = $(BLAS_LIBS) $(FLIBS)` (:103), so it is tier 1. Its header (:17-23) says the package is "built by the bundled GNU make, three times".
- **Make in the wheel test:** after the merge make does not run there at all. Even `--preclean` no longer reaches make, because install.R:606 defers the clean to SHLIB `--preclean`, which only the make path that the hook now skips would run. The only remaining check on make is Sys.which (:150-155).
- **verify-bundle scenario 3:** btA (:998) has one .c file and no Makevars, so it is tier 1. The success messages at :1092 and :1309 still say the packages were built through make. btLib and btRc stay tier 3.

**Nothing asserts which path ran.**
- None of these tests checks the build path. Scenario 3's strace check (:1079-1085) only checks that whichever make ran was the group's. install.packages with Ncpus=2 and btLib still run that make, so the check passes either way.

**Conclusion.** No assertion flips in these tests, but their coverage changes silently and their stated claims become partly false. CONSOLIDATION.md section 3 says the recipe tests "do not move" and never mentions contract, wheel-test or btA. So a section titled "Tests that change, and what to assert instead" misses real coverage loss.

I made no scratch files.

## channels-C5 (major)

- Claim or gap: Not covered by any menu: the zig-build cache (${XDG_CACHE_HOME:-~/.cache}/r-zig/zig-build, %LOCALAPPDATA%\r-zig\zig-build) is treated as a speed-up (HANDOFF.md:113-115); `rzig cache prune` is only a future name (M2).
- Evidence: All compile and link outputs are Run-step outputs in --cache-dir (build_t1.zig:73-81, 95; pkgbuild.zig:292-304), and nothing removes them. plan.env is never empty (pkgplan.zig:318). applyEnv therefore calls setEnvironmentVariable, which clones the whole process environment (zig std Run.zig:584-598), and the cache key hashes that map and the cwd (Run.zig:805-811, 921-924). R exports R_SESSION_TMPDIR, unique per session (R sysutils.c:2712), and tarball installs extract under it, so srcdir changes every time. Every R CMD INSTALL therefore writes new entries and never reuses old ones. M5 recorded '~/.cache/r-zig 65 MB after the run' on omicron for about 10 installs (PLAN.md, M5 omicron). No check notices: hermetic-check checks only TMPDIR (hermetic-check.sh:233-237), verify-bundle's HOME is a temp directory, and test-toolchain.R moves XDG_CACHE_HOME into its temp directory (:14-19).
- Consequence: On every channel (conda, wheel, standalone) users' caches grow without bound: every compiled package's objects and library are kept again on each install or upgrade. That is a disk regression compared with make, which keeps nothing. On linux, R CMD check with _R_CHECK_THINGS_IN_OTHER_DIRS_ (CRAN's incoming setting) snapshots ~/.cache recursively (R check.R:468-490, 8173-8200) and would add a NOTE for every compiled package (inferred). Stress runs accumulate the objects of every tier-1 row during the run.
- Suggestion: Add a menu. Options: a per-install --cache-dir under the build root, removed with it, possibly with a shared build-runner cache; or rzig build deleting its o/<hash> outputs after the install copy; or a clean env for the Run steps (clearEnvironment plus R_PACKAGE_NAME/CLINK_CPPFLAGS) with a size cap or prune. Add a check, for example in pkg-parity or scenario 2, that a second install of the same package leaves the cache size unchanged.

Verifier:

I could not refute it. The code and a scratch test both confirm it, apart from one small overstatement.

Code checks (branch 8ce3f77; the files involved have no merge conflicts against e1ce179):
- `build_t1.zig:61-95`: every compile and the link are Run steps with `addOutputFileArg`, `setCwd(srcdir)` and `applyEnv`.
- `pkgplan.zig:318`: `plan.env` is always set to `R_PACKAGE_NAME` and `CLINK_CPPFLAGS`, so it is never empty.
- zig 0.16 `Run.zig`: `setEnvironmentVariable` clones the whole process environment (`getEnvMapInternal`, about lines 584-598). `make()` hashes every key and value of that map (about 805-811) and the cwd (about 921-924).
- R's `sysutils.c:2712` sets `R_SESSION_TMPDIR` with `setenv` once per session on unix. Patch 0012 starts rzig with `execvp`, so the variable reaches zig build.
- `install.R` unpacks tarballs into `tempfile("R.INSTALL")`, so the source directory changes on every tarball install.
- Patch 0013 passes no `--cache-dir`. pkgbuild.zig:292 falls back to `<cache root>/zig-build` and only deletes `.rzig` and the tier-2 `src/.zig-cache` (:326, :331). Nothing removes `o/<digest>`.
- None of M1-M8 deals with cache growth. `rzig cache prune` appears only as a future subcommand name (M2; PLAN.md:169, :433).
- The cited checks are as described: `hermetic-check.sh:233-237` looks only at `$WORK/tmp`, verify-bundle sets `HOME` to a fresh directory, and `test-toolchain.R` points `XDG_CACHE_HOME` at its temp directory. `pkg-parity` has no cache check.

Scratch test, using the existing dist `R-4.6.1-slim-zig` with `XDG_CACHE_HOME` and `ZIG_GLOBAL_CACHE_DIR` in scratch (scratch is now deleted). A tiny one-file C package:
- Installed 3 times from its tarball on the default (zig) path: `zig-build/o` went 4, 6, 8. That is 2 new entries per install (the object and the library). zig cc's global cache also gained 1 entry per install, because Run steps pass absolute source paths.
- Installed twice from its directory: `zig-build/o` still grew by 2 each time (the environment differs per session), though the global cache entry was reused.
- Installed 3 times with `R_ZIG_PKG_BUILDER=make`: neither cache grew after the first install, because zig cc keys on the relative `-c a.c`.
- The user's real `~/.cache/r-zig/zig-build` already holds 143 MB in 468 `o/` entries.

The overstatement: make does not keep nothing. zig cc caches its objects in `~/.cache/zig`, but it reuses them, so make's cache stays flat. The disk regression is real, and is larger than claimed, since the zig path also grows zig's global cache for tarball installs. The `R CMD check` NOTE consequence is the finding's own inference and was not tested.

## channels-C6 (major)

- Claim or gap: M1(a): '--rzig-check=package classifies the package with pkgplan.zig ... its failing line names the reason ("a configure script", "src/Makefile", "Makevars: a rule at line N")'. M1(b): '`rzig build --classify` (exists: prints r_only, makevars, zig or make)'.
- Evidence: Planner.classify checks only src/build.zig, configure, src/Makefile and Objective-C (pkgplan.zig:127-144). A Makevars with a rule or $(shell) still gets `.makevars`; the rule is found only in plan() (pkgplan.zig:271; test cases at :715-716). `--classify` prints classify()'s tier (pkgbuild.zig:179-187).
- Consequence: Under (b), and under a classify-only (a), a package whose Makevars has rules (verify-bundle's btLib, test-toolchain's rzigar, M4's proposed pfM) skips the build-tools check on base plus compilers and then fails deep in make with 'make: not found'. That loses phase 3's early stop and the reason line M4(a) asserts. A full plan in the check needs Makeconf evaluation, Makevars site/user, R_ARCH and use_C, which the hook passes differently (0013), so 'about 40 lines' is optimistic.
- Suggestion: Specify that the check runs classify() and then plan() with the same inputs the hook uses: share one function between pkgbuild and check.zig. Note that (b)'s --classify is insufficient. Add pfM with a Makevars rule as the M4 test that proves this.

Verifier:

The finding holds against the code. Branch 8ce3f77, /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/tools/rzig/pkgplan.zig:127-144: Planner.classify() returns tier .make only in these cases: src/build.zig is absent and there is a configure (or configure.ucrt/.win) script, a src/Makefile (or Makefile.ucrt/.win), or an Objective-C source. Any Makevars, whatever it holds, returns .makevars. Rules are found later. plan() loads the Makevars at pkgplan.zig:271 and makefile.zig:195 fails with "a rule or target line". $(shell ...) and backtick metacharacters fail only when expanded or word-split inside plan(). The branch's own test confirms this. pkgplan.zig:712-728 asserts that for "all: $(SHLIB)" and "PKG_LIBS = $(shell ...)", classify() gives Tier.makevars and only plan() gives error.NeedsMake. pkgbuild.zig:179-187 shows that `rzig build --classify` prints classify()'s tier before plan() ever runs. So M1(b)'s 0009, which adds the build-tools check only when the output is `make`, skips that check for a Makevars with a rule. The same happens under M1(a) if it only classifies, which is what its wording says ("classifies the package with pkgplan.zig", "about 40 lines"). Patch 0013 then gets exit 3 from `rzig build`, returns NA, and falls through to R's make path. On base plus compilers there is no make, and the old late failure is back: phase 3's 0009 (main, zigbuild/patches/R-4.6.1/0009) exists to stop that before configure or make. The document contradicts itself here. Its vocabulary line and section 5 say Makevars with rules or $(shell) are tier 3 and need the build tools. M1(a) promises the reason line "Makevars: a rule at line N", which classify() never produces; plan() produces something different ("src/Makevars has a rule or target line: '...'", with no line number). M4(a) plans a pfM "with a Makevars that has a rule" that must stop with the build-tools text, and that test would fail under classify-only gating. Detecting $(shell) and metacharacters needs plan()'s full evaluation: Makeconf, R_ARCH, site and user Makevars, and the --c-std and use_LTO inputs that 0013 passes. A load of the Makevars alone in makevars mode would catch rules and conditionals, though, so "full plan required" somewhat overstates the minimum. That does not change the verdict. Two details are only illustrative: btLib and rzigar run in full-toolchain scenarios where make is present, so they show the shape of the problem rather than a test that flips. Main e1ce179 has no pkgplan.zig and no package mode in check.zig, so the merge changes none of this. No scratch files were created.

## channels-C7 (major)

- Claim or gap: M4(a): pfC's 'log says `rzig build: tier 1`'. M6(a): 'each install log says `rzig build: tier N` or `needs make: <reason>`', 'every OS leg', 'time against the 548da1a run', and 'R_ZIG_PKG_BUILDER=make reproduces the reference'.
- Evidence: The `rzig build: tier N` line is printed only under RZIG_TRACE (pkgbuild.zig:306-313); `needs make` is unconditional (pkgbuild.zig:359-361). Scenario 2's env -i passes only base_env, zig_env and PATH (verify-bundle.sh:546-547). stress.yaml's Stress step passes no --trace and has no input for RZIG_TRACE or R_ZIG_PKG_BUILDER (stress.yaml:118-127). stress.R sets RZIG_TRACE only with --trace (stress.R:312). The only make reference run is ubuntu-latest, tree, targets g3+g4 (feat-standalone-toolchain PLAN.md:3729-3737).
- Consequence: M4(a)'s assertion fails unless RZIG_TRACE=1 is added to the env -i run. M6's table cannot be produced from a plain dispatch: tiers 1 and 2 can only be inferred (no `needs make` line; `using zig:`), and macOS and Windows have no make reference to time against, nor any way to dispatch one.
- Suggestion: Add RZIG_TRACE=1 to scenario 2's install. Add stress.yaml inputs, for example trace (bool) and builder (auto|make), passed as --trace and an env var. Limit M6(a)'s comparison to the rows and OS the 548da1a reference covers, or plan the make-reference dispatches for the other OS.

Verifier:

I could not refute the finding. Every cited point holds at main e1ce179 and branch 8ce3f77. The branch changes none of verify-bundle.sh, stress.yaml or stress.R, so the merged state is the same.

1. The tier line is printed only under trace. In pkgbuild.zig:306-313 the line "tier {s}, root {s}" is inside `if (isSet(ctx, "RZIG_TRACE"))`. With ctx.name = "rzig build" (pkgbuild.zig:160) it comes out as `rzig build: tier 1, root ...`, and only when RZIG_TRACE is set. needsMake (pkgbuild.zig:359-361) warns "<name> needs make: <reason>" every time. No other output names tier 1 or tier 2. Without trace the log has only "using C compiler" lines, plus "using zig" for tier 2. The branch's own scripts/pkg-parity.sh relies on this: it says "the zig path (`RZIG_TRACE=1`): the log says `rzig build: tier 1`" and does `export RZIG_TRACE=1` at line 58.

2. M4(a) as written would fail. Scenario 2's preflight_stops runs `env -i "${base_env[@]}" "${zig_env[@]}" PATH="$BUNDLE_DIR/bin"` (verify-bundle.sh:546-547 on main). base_env has HOME/TMPDIR (Windows: SYSTEMROOT etc.) and zig_env has ZIG_BIN and the zig cache dirs. Nothing sets RZIG_TRACE, so an assertion on `rzig build: tier 1` cannot match. CONSOLIDATION.md never says RZIG_TRACE is needed; row 8 even says "RZIG_TRACE line format: unchanged on main, nothing".

3. M6(a) and section 5 don't hold for a plain dispatch. stress.yaml's Stress step (main, lines 118-127) passes only --out, --conda and --skip plus the targets. It has no --trace, no RZIG_TRACE and no R_ZIG_PKG_BUILDER input. stress.R sets RZIG_TRACE only with --trace (line 312). So a default dispatch's logs don't contain `rzig build: tier N`, and tiers 1 and 2 can only be inferred: no "needs make" line, and "using zig" for tier 2. The claim that R_ZIG_PKG_BUILDER=make reproduces the reference works locally, because stress.R inherits the environment. A CI dispatch has no way to set it.

4. The 548da1a reference covers one leg only. The only stress run on 548da1a is dispatch 38251125721: ubuntu-latest, tree, targets g3 and g4 (feat-standalone-toolchain PLAN.md:3729-3737). M6(a) asks for "every OS leg ... time against the 548da1a run", but macOS and Windows have no make reference at that commit.

The overall consequence is somewhat overstated: an M6 tier table can still be built by inference. But each concrete claim in the finding holds against the code, and the document's stated assertions and premises are wrong as written. No scratch files were created.

## channels-C8 (major)

- Claim or gap: Section 5: 'The build-tools group is needed only by tier-3 packages: configure scripts, src/Makefile*, Makevars with rules or $(shell), and R CMD check's objdump'. Phase 7 and B24 then become 'for packages that need make'.
- Evidence: 0013 hooks only run_shlib inside .install_packages (pristine install.R:691). `R CMD SHLIB` is tools:::.SHLIB (pristine install.R:2537), which always runs make (:2904); scenario 2's SHLIB builds take make from PATH (verify-bundle.sh:694-702, 729-730). 0010's own description says pkgbuild and pak call `R CMD config` to detect a compiler, and M7(a) keeps the build-tools requirement there.
- Consequence: Users of R CMD SHLIB still need the build-tools group even for trivial code: Rcpp::sourceCpp, cpp11::cpp_source, inline, TMB::compile, and pkgbuild's compiler probe used by devtools/remotes/pak. Inferred: pak/remotes users on base plus compilers are refused before any tier-1 install. A phase-7/B24 scope statement written from section 5 would understate who needs the group.
- Suggestion: Add 'R CMD SHLIB (sourceCpp, inline, TMB, pkgbuild/pak compiler probes)' to section 5's list. Record the pak/pkgbuild interaction with M7 (a) as a known limit or a later item.

Verifier:

The finding holds. I checked it against the code on main (e1ce179) and on the branch (8ce3f77), and I could not refute it.

1. Patch 0013 on the branch changes only `run_shlib` inside `.install_packages`. Its hunks are at install.R 683 and 746, plus the `allfiles` change at 1521. In the pristine R 4.6.1 install.R from the CRAN tarball, `.SHLIB` (line 2537) calls `.shlib_internal`, which sets MAKE (from `Sys.getenv("MAKE")` on unix, `"make"` on Windows; lines 2593 and 2600). It then always runs `system(paste(MAKE, ...))`: line 2904 builds that command, line 2912 runs the compilers probe, and `system()` goes through sh. No patch on main (0005/0009/0010) or on the branch (0012/0013) touches `.shlib_internal`, and the branch's records never route `R CMD SHLIB` through `rzig build`.

2. The build-tools group in main's groups.zig is unix make, plus sh, make and the binutils on Windows. So `R CMD SHLIB` needs that group, or a make found on PATH, which the group text accepts. Scenario 2 in verify-bundle.sh confirms this. Lines 694-702 put the env's make on `pkg_path` for its SHLIB compiles. Lines 729-730 then run `R CMD SHLIB` with that PATH.

3. Main's 0010 keeps `--rzig-check=build-tools` in `R CMD config`. The patch's own description says "pkgbuild and pak call it to detect a compiler". M7 (a) keeps it unchanged.

4. Main's feat-standalone-toolchain PLAN.md, in the "What a user gets" table at line 272, lists `R CMD SHLIB` and `R CMD config` under Compile, which needs the build-tools archive. CONSOLIDATION.md section 5 (lines 199-204) says the group is needed "only by tier-3 packages: configure scripts, `src/Makefile*`, Makevars with rules or `$(shell)`, and `R CMD check`'s objdump". That list goes beyond packages, since it includes objdump, yet it leaves out `R CMD SHLIB` and `R CMD config`. It then re-scopes phase 7 and B24 to "for packages that need make". That wording would drop the SHLIB and config users the standalone plan already names: Rcpp::sourceCpp, inline, TMB, and pkgbuild's compiler probe.

The cited line numbers match: install.R 691, 2537 and 2904; verify-bundle.sh 694-702 and 729-730. One part is only inferred and I did not verify it against those packages' code: that pak or remotes refuse before a tier-1 install. The core claim, that section 5's scope statement is incomplete, holds without it.

## channels-C9 (major)

- Claim or gap: Section 6 and M5 list the merge's adaptations and records, with no recipe build number.
- Evidence: The recipe policy is to bump manually in any PR that should republish, with `--skip-existing` as the safety net (recipe.yaml:84-89; pixi.toml:559). B14 (a): 'bump in phase 4's PR and in each later PR that changes a package' (feat-standalone-toolchain TODO.md:56-57). Phase 3 changed no package and did not bump (TODO.md:372-373), so main is still `number: 8` (recipe.yaml:151) and universe has build 8 (PLAN.md:3738-3740). This branch changes r-zig-slim (0012, 0013, share/zig/rpkg) and r-zig-toolchain (rzig).
- Consequence: Without a decision, the channel keeps build 8 (skip-existing). Conda users never get rzig build, and stress `--conda=universe` tests the old packages. Phase 4's TODO assumes '9 unless another PR bumps first' (TODO.md:448-450), so the order between the two PRs matters.
- Suggestion: Add a menu item or M5 entry: bump 8→9 in this PR with a recipe comment, and update phase 4's TODO to the next number; or explicitly defer to phase 4's bump and say so in both records.

Verifier:

The finding holds against main e1ce179 and branch 8ce3f77.

**The omission is real.** CONSOLIDATION.md never mentions a build number, a bump, a publish or `--skip-existing`. Section 6 step 1 and the M5 menu (records), lines 227-249, list every adaptation and record and leave the number out. The branch's own PLAN.md and HANDOFF.md do not discuss it either (a grep for bump, build number, publish, universe and r-zig-slim finds nothing relevant).

**The numbers are as cited.**
- The branch leaves recipe.yaml alone: it is still `number: 7` at both b490bdf and 8ce3f77.
- main is at `number: 8` (recipe/recipe.yaml:151). The merge therefore yields 8.
- feat-standalone-toolchain PLAN.md:3738-3740 records that universe already holds build 8 for both packages on all five subdirs.

**Without a bump, nothing publishes.**
- The policy at recipe.yaml:82-88 is to bump by hand in any PR that should republish, with `--skip-existing` as the safety net.
- `conda-publish` uploads with `--skip-existing` (pixi.toml:559 and following).
- The publish step runs on every push to main (.github/workflows/build.yaml:310-312).
- So a merge left at 8 is silently skipped. This is the same trap that kept the gfortran builds on the channel (the 1→2 bump comment in recipe.yaml).
- stress.R's `--conda=universe` (stress/README.md:61) would keep testing the old build 8.

**The branch changes both packages.**
- build.zig installRzig adds `rzig`/`rzig.exe` to lib/R/bin/toolchain, which goes to r-zig-toolchain.
- The same step installs `share/zig/rpkg/*.zig` into R_HOME. That path is outside `lib/R/bin/toolchain/**`, so it goes to r-zig-slim.
- Patches 0012 and 0013 change R itself, which is r-zig-slim.

**The cross-record dependency is as cited.**
- B14 (a) says "bump in phase 4's PR and in each later PR that changes a package" (TODO.md:56-57).
- Phase 4's TODO (TODO.md:448-450) and PLAN.md:1169 and 3797 say "9 unless another PR bumps first". So which PR bumps first does matter.
- PLAN.md:2578 sets the order: PR #24, then feat-zig-pkg-build, then phase 4. This branch's PR therefore merges before phase 4, while the number is still open.

**What softens it (affects severity, not truth).**
- Under B14 (a) a PR that merges before phase 4 is not strictly required to bump.
- Phase 3 set a precedent of deferring to phase 4's bump: TODO.md:372-373 says "no bump", and PLAN.md:3738-3740 says phase 3's files publish nothing until phase 4's bump.
- If nothing is done, phase 4's bump to 9 eventually publishes everything.
- So "conda users never get rzig build" is overstated: they get it at phase 4.

Even so, the consolidation document's stated job is to collect the open choices of both sides in one place, and this one is missing: bump in this PR, or explicitly defer to phase 4 and record that in both records. The omission is real; "major" may be generous.

## coverage-C8 (minor)

- Claim or gap: CONSOLIDATION.md:23 and M7(a) (:76-79): "install.R on unix never runs `R CMD config` itself (only the Windows configure.win branch does, install.R 1356)". M1(c) (:69-72): a configure package "would run its configure and stop only afterwards".
- Evidence: Verified: the unix branch of R-4.6.1 install.R runs `R CMD config` for CC, CFLAGS, CXX, ... before ./configure (CRAN tarball install.R:1307-1330, `c("CMD", "config", x)` at 1327; line 1362 after main's patches). The Windows branch does it at main-patched 1327. verify-bundle.sh:529-535 and hermetic-check.sh:107-111 rely on the unix call ("the install's R CMD config (patch 0010) fails before a configure would run").
- Consequence: The conclusion still holds: R CMD config runs only for configure scripts, which are tier 3, so 0010 does not depend on tiers. But the stated reason is wrong. Under M1(c), a configure package on unix would stop at that R CMD config call (an error from vapply with 0010's text), not after its configure.
- Suggestion: Reword: "install.R runs R CMD config only for a configure script, on both OSes (unix: before ./configure; Windows: configure.win/ucrt), so tiers 0-2 never reach it." Adjust M1(c)'s rationale.

Verifier:

The finding holds. I couldn't refute it. In the CRAN R-4.6.1 tarball, install.R's unix `use_configure` branch runs `R CMD config` for CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and FCFLAGS before `./configure`, through `system2(file.path(R.home("bin"), "R"), c("CMD", "config", x), stdout = TRUE)` inside `vapply(..., "")`. That call is at pristine line 1327; the Windows configure.win/ucrt branch is at 1292. After main's install.R patches (0005, 0009) the lines are 1362 (unix) and 1327 (Windows), matching the finding. After the branch's patches (0005, 0009, 0013) they are 1391 (unix) and 1356 (Windows). So CONSOLIDATION.md:23 cites only the Windows call at 1356 and misses the unix call at 1391. None of 0005, 0009, 0012 or 0013 touches the unix configure block. 0013's late hunk at 1521 only changes `allfiles` for build.zig. So the doc's sentence "install.R on unix never runs R CMD config itself" (line 23, and M7(a) "install.R on unix never calls it") is false against the code as it would merge. Patch 0010 runs `zig-cc --rzig-check=build-tools > /dev/null || exit` in src/scripts/config on unix, so when the build tools are missing, stdout is empty and the status is non-zero. `system2` then returns character(0), and `vapply` stops with "values must be length 1", with 0010's text on stderr, before `./configure`. That happens unless all eight variables are already set in the environment. Main's own tests rely on this exact behavior: scripts/verify-bundle.sh:532-535 and scripts/hermetic-check.sh:107-111 both say "the install's R CMD config (patch 0010) fails before a configure would run". So M1(c)'s rationale at CONSOLIDATION.md:69-71 ("a configure package would run its configure and stop only afterwards") is also wrong for unix: R CMD config would stop it before configure. Windows' configure.win branch also calls Rcmd config before `sh configure.win`. The doc's conclusion, M7(a) keeping 0010, still stands, since only packages with a configure script (tier 3) reach that call. So the finding's minor severity and its suggested rewording are accurate. Scratch was used and then deleted: /data/gamma/luciorq/workspaces/temp/r-zig-pixi/consreview/verifier-C8.

## coverage-C9 (minor)

- Claim or gap: Scenario 3 is not listed among the tests that change. Its header and messages say the packages are built through make.
- Evidence: Verified: btA (mkpkg with no Makevars, verify-bundle.sh:998) is tier 1 on unix and Windows. Measured: --plan-only exits 0. btLib and btRc stay on make (see confirmed claims). verify-bundle.sh:46-49 says "install.packages with Ncpus = 2 builds two packages through it". The echoes at :1092 and :1314 list btA among the packages "built through make".
- Consequence: The assertions hold (install, load, strace's make set). But the test now builds one package through make on unix (two on Windows), and its text claims more. It also mixes builders inside one install.packages(Ncpus = 2) run without checking that it does.
- Suggestion: Keep btA on the default builder as a deliberate mixed-mode check. Add RZIG_TRACE=1 to run_bt's environment and keep_outputs = TRUE in bt.R, then assert that btA.out says `rzig build: tier 1` and btLib.out says `needs make`. Fix the header and echo text, and list it in section 3.

Verifier:

The finding holds; I could not refute it. The branch does not touch scripts/verify-bundle.sh (git diff b490bdf 8ce3f77 shows no change), so the merged file is main's.

1. btA reaches the new hook. Main's scenario 3 builds btA with mkpkg at :998: plain C, no Makevars. In R 4.6.1's install.R, a package with no src/Makefile goes to run_shlib (unix around line 1540, Windows around line 1470). Patch 0013 puts rzig_build() first in run_shlib, and R_ZIG_PKG_BUILDER defaults to auto.

2. btA is tier 1 and the other two need make. pkgplan.zig classify() puts a package with no configure, no Makefile and no ObjC source in tier makevars (makevars null) on both OSes. I ran the branch's built rzig (worktree dist/R-4.6.1-slim-zig) on scratch copies made with the same mkpkg:
   - btA: `--classify` printed `makevars`; `--plan-only` exited 0.
   - btLib: `--plan-only` exited 3 with "needs make: src/Makevars has a rule or target line: '$(SHLIB): lib/libval.a'".
   - btRc (not run, read from the code): its Makevars.win `OBJECTS = f.o val.o res.o` would hit "no source for res.o", because source_exts has no .rc (pkgplan.zig:438). So it stays on make on Windows.

3. The text no longer matches. After the merge, one package builds through make on unix and two on Windows. The text that says otherwise:
   - The header at :47-48 ("builds two packages through it").
   - The comment at :984-994, which says the recipes run R CMD INSTALL, "which runs make again for each package".
   - The echoes at :1092 and :1314, which list $bt_pkgs, btA included, as "built through make".

4. CONSOLIDATION.md does not cover it. Section 3 mentions scenario 3 only for `nopre` (:1371-1400), and calls it unchanged. Row 7 says the only flip is pfC. Nothing in the document mentions btA, the bt packages or Ncpus.

5. The assertions still pass. bt.R only checks that the packages install. bt-load.R checks that they load. The strace check needs every make that ran to be the group's, and that is still true: install.packages' top-level make and btLib's make both are. So the defect is stale text and an unchecked mix of builders, not a failing test, which fits severity minor.

## coverage-C10 (minor)

- Claim or gap: M4(a): pfC's "log says `rzig build: tier 1`". M6: "each install log says `rzig build: tier N` or `needs make: <reason>`". M6(b): a base-only run shows tier-3 rows "stop with the reason line". "R_ZIG_PKG_BUILDER=make reproduces the reference".
- Evidence: Verified: the tier line is printed only under RZIG_TRACE (pkgbuild.zig:306-313). The needs-make line is printed always (:359-361), and tier-0 packages never call rzig. preflight_stops' env has no RZIG_TRACE (verify-bundle.sh:546-547). stress.yaml passes no --trace (stress.yaml:124-129; stress.R:313 sets RZIG_TRACE only with --trace) and has no input for R_ZIG_PKG_BUILDER. stress.R:294-295 sets R_MAKEVARS_USER to an existing empty file, and makevars_user() returns an existing R_MAKEVARS_USER (install.R:3361ff), so 0009's `!length(makevars_user())` skips the preflight in every stress run.
- Consequence: M4(a) as written would fail unless RZIG_TRACE is set. M6(a)'s rows-by-tier table cannot be read off a default dispatch: tier must be inferred from the needs-make lines plus src/. In M6(b), tier-3 rows fail in configure or make with raw errors, not the preflight reason. A make reference in CI needs a workflow change.
- Suggestion: Set RZIG_TRACE=1 in pfC's environment. Add `trace` and `builder` inputs to stress.yaml, or define tier from needs-make plus no-src. Drop M6(b)'s expectation, or run it without the empty R_MAKEVARS_USER.

Verifier:

I could not refute the finding. Its claims hold on main e1ce179 and on branch 8ce3f77.

(1) The tier line only appears when RZIG_TRACE is set. In zigbuild/tools/rzig/pkgbuild.zig:306-313 (branch), `ctx.warn("tier {s}, root {s}"...)` sits inside `if (isSet(ctx, "RZIG_TRACE"))`. pkgbuild.zig:160 sets ctx.name to "rzig build", so the traced line reads "rzig build: tier 1, root ...". The needs-make line is always printed (needsMake, :359-361). Tier 0 never reaches rzig: patch 0013 calls rzig_build only from run_shlib. src/Makefile packages bypass run_shlib, so they never print the needs-make line either. The branch's own records and pkg-parity.sh:58 export RZIG_TRACE=1 before grepping "rzig build: tier 1", which confirms the line needs the trace.

(2) Scenario 2 cannot show the line. preflight_stops in scripts/verify-bundle.sh:545-547 (main) runs `env -i "${base_env[@]}" "${zig_env[@]}" PATH=...`. base_env and zig_env (:286-303) hold only HOME/TMPDIR/ZIG_BIN/cache dirs (SYSTEMROOT etc. on Windows), with no RZIG_TRACE. So M4(a)'s "its log says `rzig build: tier 1`" fails unless the test adds RZIG_TRACE=1, and the doc does not say to.

(3) A default stress dispatch gives no tier lines. stress.yaml:124-129 builds args from --out, --conda and --skip only, with no --trace and no builder input. stress.R:312 sets RZIG_TRACE only under --trace (the finding cites :313, off by one). Nothing in pixi.toml, env.sh or the workflows sets it. So "each install log says `rzig build: tier N` or `needs make: <reason>`" is false for M6(a): tier 0-2 rows print no tier line.

(4) The preflight never runs under stress. stress.R:291 creates an empty file and :294-295 sets R_MAKEVARS_USER to it. makevars_user() in R 4.6.1's install.R (CRAN tarball :3361ff) returns R_MAKEVARS_USER whenever that file exists. 0009's condition `!length(makevars_user())` is therefore FALSE for every stress install, and run() does not override that variable. So M6(b)'s tier-3 rows cannot "stop with the reason line" from the preflight. Configure and src/Makefile rows fail with raw configure or make errors. Only Makevars-with-rules rows print the hook's needs-make line, and then go on to make.

The weakest part is "R_ZIG_PKG_BUILDER=make reproduces the reference". It holds for local runs, because stress.R inherits the caller's environment. For CI it is right only that the workflow has no input for it. The finding's core (points 1-4) is confirmed, and its minor severity fits. Scratch dir deleted.

## coverage-C11 (minor)

- Claim or gap: M6: a stress dispatch "with the default R_ZIG_PKG_BUILDER=auto" compared against the 548da1a make run.
- Evidence: Verified by classifying the cached stress sources on linux. Targets that switch to rzig build: Rcpp, lme4, mlpack, fst, geos (with dependency libgeos, the bundled GEOS C++). Dependencies that switch include minqa, nlme, MASS, lattice, RcppEigen, cli, glue, vctrs and KernSmooth. Windows differs: lme4's Makevars.win is tier 1, minqa's ($(shell)) is tier 3. rzig build passes `--cache-dir <rzig cache>/zig-build` (pkgbuild.zig:292, 304), which overrides the ZIG_LOCAL_CACHE_DIR that stress.R:297-300 sets "in the run directory, whatever the caller set". stress.R:515-517 removes only top-level entries the run added. The toolchain classifier pattern (stress.R:170) matches `rzig: `, but rzig build's lines start `rzig build: ` (Ctx.zig:80-86; pkgbuild.zig:160). Inference: since Run-step keys hash the full environment (Run.zig:805-808) and R exports a per-session R_SESSION_TMPDIR (src/main/sysutils.c:2712), zig-build entries are never reused across installs.
- Consequence: The rows' expect values and notes describe the make path. rzig build's own failures (zig build failed, rpkg missing, no zig) are classed by other patterns or as `package`. Objects of tier-1 rows land outside the run directory, and on machines where zig-build already exists they accumulate without cleanup.
- Suggestion: Add `rzig build: ` to the toolchain pattern. Pass --cache-dir from ZIG_LOCAL_CACHE_DIR when it is set, or have stress set it. Note the switching rows in the M6 table. Consider excluding volatile variables (R_SESSION_TMPDIR, R_INSTALL_PKG) from the Run-step environment.

Verifier:

I could not refute it. Every part checks out against main e1ce179 and branch 8ce3f77. The branch does not touch stress/, so a merge keeps main's stress.R.
(1) Builder switch. I ran the branch-built rzig (dist/R-4.6.1-slim-zig/lib/R/bin/toolchain/rzig) as `build --classify` and `--plan-only` on the cached stress tarballs on linux. Rcpp, lme4, mlpack, fst, geos, libgeos, minqa, nlme, MASS, lattice, RcppEigen, cli, glue, vctrs and KernSmooth all plan as tier 1, with exit 0. fstcore, nloptr and RcppArmadillo exit 3 (configure). Matrix exits 3 (a rule line). On Windows, lme4's Makevars.win has assignments only (its $(shell) line is commented out), while minqa's has a live `PKG_LIBS = $(shell ...Rscript.exe...)`.
(2) Classifier. On main, the toolchain pattern in stress.R (line 170) contains `rzig: `. rzig build sets ctx.name = "rzig build" (pkgbuild.zig:160), and Ctx.warn prints "{name}: ...", so lines start with `rzig build: ` and do not match. These include "zig build failed", "no zig to build with" and "R_HOME/share/zig/rpkg is not installed". The fallback class is `package`.
(3) Cache. pkgbuild.zig:292 defaults --cache-dir to <cache.root>/zig-build, and line 304 always passes it. In zig 0.16, src/main.zig:4964 and 5054 show that --cache-dir overrides ZIG_LOCAL_CACHE_DIR. That variable is the one stress.R:297-301 points at the run directory. The Run-step outputs of build_t1.zig (addOutputFileArg) therefore land in rzig's cache, outside the run directory. stress.R:515-516 removes only top-level entries that are new, so a zig-build directory that already existed keeps growing.
(4) Cache key. plan.env always holds R_PACKAGE_NAME and CLINK_CPPFLAGS (pkgplan.zig:318). applyEnv then calls setEnvironmentVariable, which clones the build graph's full environ_map (build_runner.zig:88 builds it from the process environment), and Run.zig:805-808 hashes every entry. R exports R_SESSION_TMPDIR (sysutils.c:2712) and R_INSTALL_PKG (install.R:628). So the keys change with every install.
(5) Coverage. CONSOLIDATION.md M6 and the paragraph before it mention none of this: no harness change, no cache placement, no switching rows.
Two caveats, neither of which refutes the finding. First, adding `rzig build: ` to the toolchain pattern would also class ordinary compile failures as toolchain, because each one ends with "rzig build: zig build failed". Second, the rows' expect value "ok" applies to either builder; only the notes are history from make runs.

## coverage-C12 (minor)

- Claim or gap: M1(b)'s listed costs are two binary names, the Fortran regex staying in R, and no reason line.
- Evidence: Verified: hermetic-check.sh's strace allowlist (:213-222) admits /bin/sh, R's launchers and `$T/lib/R/bin/toolchain/zig-cc` only. Under (b), 0009 would exec `$T/lib/R/bin/toolchain/rzig` for hermeticSrc before the compilers check stops it.
- Consequence: M1(b) would also fail the linux hermetic leg (strace) until the allowlist adds rzig. This is not stated.
- Suggestion: Add it to (b)'s costs. No change is needed under (a).

Verifier:

I could not refute the finding. It holds against the code as it would merge, provided (b) asks for the tier before the compilers check, which is how the doc describes (b).

1. **The costs are quoted correctly.** CONSOLIDATION.md M1(b) lists three costs: "two binary names in 0009 (CC's for the checks, `rzig` for the tier)", "the Fortran regex stays in R" and "the stop line cannot say why make is needed". Nothing else is listed.
2. **The doc says hermetic-check does not change.** Its interface table, row 7, says "hermetic-check and the recipe tests do not move". Section 3 says hermeticSrc is "unchanged" because the compilers check stops it first. Neither statement depends on the M1 choice.
3. **The allowlist does not admit rzig.** In `/home/luciorq/projects/r-zig-pixi/scripts/hermetic-check.sh:213-222` the strace execve case list admits /bin/sh, R's launchers, `$T/lib/R/bin/toolchain/zig-cc` and env. Anything else lands in `bad`, and the script exits 1. The branch does not touch this file, and a read-only `git merge-tree` of 8ce3f77 with e1ce179 keeps the same list. The linux CI hermetic step runs it with strace from the pixi env, and a missing strace fails in CI.
4. **The exec under (b).** 0009 builds its path as `file.path(R.home(), "bin", "toolchain", ...)`. R.home() is `$T/lib/R`, as the existing zig-cc entry shows. Under (b) plus M2(a), rzig is in the base, so the tier call execs `$T/lib/R/bin/toolchain/rzig` through /bin/sh.
5. **The order.** (b) "keeps its two-step loop, adding `--rzig-check=build-tools` only for `make`". The loop's list of checks needs the tier before it runs, so the classify call comes before the compilers check. hermeticSrc meets every condition for the preflight: src/one.c, no user Makevars, no R_ZIG_NO_PREFLIGHT, and R_ZIG_PKG_BUILDER unset under `env -i`. The exec succeeds whatever rzig then does, so strace records it.
6. **Under (a) nothing changes.** `--rzig-check=package` runs under CC's name, zig-cc, which is already allowed. 0013's hook calls rzig by name, but hermeticSrc never gets that far.

**The one weakness:** a (b) written to ask for the tier only after the compilers check passes would not hit the allowlist. That order is not the natural reading of the doc's wording. Taken as written, (b) has a cost the doc does not list: the linux hermetic leg fails until `$T/lib/R/bin/toolchain/rzig` is added to the allowlist.

I made no edits, ran no git writes or builds, and created no scratch files.

## coverage-C13 (minor)

- Claim or gap: CONSOLIDATION.md:6-7: "the worktree is clean, nothing to commit before the merge". Section 4 says HANDOFF is folded in and removed in the merge commit.
- Evidence: Verified: `git status --short` in the worktree shows `?? .github/devdocs/feat-zig-pkg-build/CONSOLIDATION.md` and `?? .github/devdocs/feat-zig-pkg-build/HANDOFF.md` (both untracked at 8ce3f77). zigbuild/tools/rzig/smoke-test.sh:223-227 (manual) installs rzc, rzcxx, rzomp and rzf, all tier 1. Its `grep -h 'zig-c' install-*.log` display relies on make's echoed command lines, which rzig build does not print without RZIG_TRACE.
- Consequence: This is a records inaccuracy, and a display line that goes empty in a manual script. No assertion is affected.
- Suggestion: Say "two untracked records (HANDOFF.md, this file)". Set RZIG_TRACE=1 in smoke-test.sh part 2, or note that it now runs rzig build.

Verifier:

I could not refute either half of the finding, and the second half is worse than it says.

1. Records claim. CONSOLIDATION.md lines 5-7 say "the worktree is clean, nothing to commit before the merge". At 8ce3f77, `git status --short` in the worktree shows `?? .github/devdocs/feat-zig-pkg-build/HANDOFF.md` and `?? .../CONSOLIDATION.md`. HANDOFF.md is not gitignored (`git check-ignore` returns 1) and was never committed on any ref. It was written on 2026-10-10, before CONSOLIDATION.md (2026-10-12), and CONSOLIDATION cites it in table row 8 and in M2. The plan in section 4 (fold HANDOFF into PLAN.md and remove it in the merge commit) does hold together. Still, "the worktree is clean" is literally false. This part is a minor records inaccuracy, as the finding says.

2. smoke-test.sh. The four packages rzc, rzcxx, rzomp and rzf (lines 222-227) have no configure, no src/Makefile and no Objective-C. rzomp's Makevars is assignments only. `pkgplan.zig` `classify` (lines 127-144) therefore returns tier `.makevars` (tier 1) for all four. Patch 0013 defaults R_ZIG_PKG_BUILDER to auto, so these installs now go through `rzig build`, not make.

With RZIG_TRACE unset, `pkgbuild.zig` `run` and `reportCompilers` print only lines like "using C compiler: 'clang version ...'". PLAN.md:470 records that every zig-path log has "no make output". The passing 0009 preflight's stdout is suppressed (`stdout = FALSE`). Makeconf's `CC = $(R_HOME)/bin/toolchain/zig-cc` reached the log only through make's echoed command lines. So `grep -h 'zig-c'` at line 228 finds nothing.

The finding's consequence understates this. The script runs under `set -euo pipefail` (line 26). A grep with no match exits 1, so the pipeline `grep | sed | head` fails and the script exits silently with rc=1 at line 228. I reproduced this in a scratch dir with the same pipeline: "reached" was never printed and rc was 1. So part 2 does not just show an empty display line: it aborts before the load/run checks and the readelf runtime check. The script is manual (not in any workflow or pixi task). It is still a real defect after the merge: main's diff to smoke-test.sh only changes a comment.

The suggested fixes (RZIG_TRACE=1, or a note that part 2 now runs rzig build) are reasonable. Making the grep non-fatal (`|| true`) or asserting on "using C compiler" would also work. I suggest raising the severity of the smoke-test half.

The scratch dir has been deleted.

## preflight-F4 (minor)

- Claim or gap: The preflight can decide the same tier as the hook, because it is the same code run with the package dir as cwd.
- Evidence: CLINK_CPPFLAGS is set only at main install.R:1426, after the preflight. It is never unset, so in a multi-package R CMD INSTALL it is stale from the previous package. pkgplan reads it (pkgplan.zig:183), and shellwords rejects metacharacters in it (pkgplan.zig:369-371). use_C is known before the preflight (install.R:425-430, or the --use-Cnn arguments), but check mode accepts exactly one argument (main.zig:171), so the CCnn check (pkgplan.zig:288-291) cannot run in the preflight. 0009's `!length(makevars_user())` skip (main install.R:1286) stays under (a), so any ~/.R/Makevars, even one with flags only, disables both checks. Yet plan() loads the user Makevars the same way the hook does (pkgbuild.zig:141-157 and 209, pkgplan.zig:281, test at :730-738). R's makevars_user() (main install.R:3397ff) and pkgbuild's version differ in two edges: unix `~/.R/Makevars-` when R_PLATFORM is unset, and Windows `~`, which R takes from R_USER while pkgbuild tries HOME first. The R_USER point is inferred from R's documented behaviour.
- Consequence: Narrow mismatches: a LinkingTo path with a shell metacharacter, or an undefined CCnn, gives tier 1 in the preflight and make in the hook. The user-Makevars skip throws away a decision rzig could now make precisely.
- Suggestion: Pass use_C through the environment (for example, 0009 sets R_ZIG_C_STD) or let check mode take arguments. Either compute CLINK_CPPFLAGS before the preflight or record the gap. Consider dropping the makevars_user() skip: let the package check load the user Makevars, skip the compilers check when CC is not R's toolchain, and require the build tools.

Verifier:

The finding holds, though it is narrower than its wording says. I checked it against main's patched install.R, made by applying 0005, 0009 and 0013 to the CRAN install.R in a scratch copy (now deleted), and against the branch's rzig sources.

(1) CLINK_CPPFLAGS. Its only Sys.setenv is at main install.R:1426, after the 0009 preflight at 1276-1311, and nothing ever unsets it. The 0013 hook passes no --linkingto, so plan() takes the value from the environment (pkgplan.zig:183). The preflight therefore plans with the variable unset or left over from the previous package, while the hook plans with the current package's value.

A scratch zig test of shellwords.split showed what this changes. The suggested trigger, a shell metacharacter in a LinkingTo path, is mostly wrong: install.R puts each path inside single quotes, so characters like & ; ( ) inside it pass. An apostrophe in the path (for example /home/o'brien/...) does fail: shellwords refuses it as "an unclosed single quote", so the hook decides make while the preflight decides tier 1. A $ in the path probably does the same through makefile.zig expansion, which I only read and did not test. Make fails on such paths too, so the visible effect is a different error message.

(2) use_C. It is set before the preflight (install.R:425-430 and the --use-Cnn arguments at 2273-2279). Check mode runs only when there is exactly one argument (main.zig:171, `caller.len == 1`), and M1(a) is a single `system2(rzig, "--rzig-check=package")`. The hook does pass `--c-std` (0013). So the CCnn check (pkgplan.zig:288-291) and the CC=$(CCnn) override run only in the hook. In practice this matters only with a Makevars.site that changes CC or empties a CCnn. Every Makeconf here defines CC17, CC23, CC90 and CC99 as the toolchain zig-cc, and no Makevars.site ships. A package's own Makevars cannot override them because Makeconf is read after it, and a user Makevars skips the preflight anyway. So this case is real but contrived.

(3) The user-Makevars skip. The `!length(makevars_user())` condition is at main install.R:1286, and the CONSOLIDATION doc says the condition stays under (a). Any user Makevars file therefore skips the whole preflight. plan() already loads the user Makevars (pkgplan.zig:281, pkgbuild.zig:141-157 and 209), and the test at pkgplan.zig:733-738 shows it deciding make for one. This part is a design point, not a tier mismatch.

(4) makevars_user differences. The `~/.R/Makevars-` difference is real in the code, but it cannot happen under R: etc/Renviron always sets R_PLATFORM. The Windows R_USER/HOME difference is plausible but untested.

The doc's premise that R and rzig agree because pkgplan.zig is the same code as the hook does not hold: the preflight gets different inputs. Minor severity is right.

## preflight-F5 (minor)

- Claim or gap: Under M1(a), flang is checked when 'the classification's sources include Fortran (`listSources`, the same files R's OBJECTS rule compiles)', and 0009's `[.]([fF]|[fF]9[05])$` regex goes away.
- Evidence: classify() returns no sources; plan() has them. listSources looks at src/'s top-level files only (pkgplan.zig:113-125), which matches only R's default OBJECTS. A Makevars OBJECTS that names sub/x.o is accepted by plan() (pkgplan.zig:296-304; the test at :640-650 uses sub/b.cc), so Fortran in a subdirectory is missed by listSources but is present in plan().sources. 0009 deliberately matches either case of the f (main install.R:1305; PLAN.md:3184-3185). R's default rules never compile .F (the srcs pattern at pristine install.R:1420 and 1503, and Makeconf's .SUFFIXES), so dropping .F is right for tiers 1-2. In tier 3, though, .F is built by the package's own rules.
- Consequence: Tier-1 packages that build Fortran from a subdirectory pass the flang check and stop later at zig-fc. Tier-3 packages with top-level .F files lose the up-front flang check they have today. In both cases the text is the same, but it comes later.
- Suggestion: For tiers 1-2, check flang when plan().sources contains f or f9x. For tier 3, keep today's top-level either-case match. Correct the wording 'the same files R's OBJECTS rule compiles'.

Verifier:

I tried to refute this finding and could not; it holds on main e1ce179 and on the branch at 8ce3f77. Nothing in the merge touches pkgplan.zig, and main's 0009 is the one that applies after the merge.

What I checked:
(1) CONSOLIDATION.md lines 49-51 say what the finding quotes. The flang check runs when "the classification's sources include Fortran (`listSources`, the same files R's OBJECTS rule compiles)", and 0009's `[.]([fF]|[fF]9[05])$` regex goes away.
(2) The `Classification` struct (pkgplan.zig) has only `tier`, `reason` and `makevars`. It has no sources.
(3) `listSources` (pkgplan.zig:113-125) iterates the top level of src/ only, skipping directories. It keeps a name only if `langOf` or `isObjC` matches. `langOf` (:440-446) is case-sensitive: `.c`, `.cc`, `.cpp`, `.f`, `.f90`, `.f95`. So `.F`, `.F90` and `.F95` are never listed.
(4) `plan()` resolves Makevars OBJECTS through `source_exts` relative to src_dir (:296-304). The test at :640-650 shows `OBJECTS = a.o sub/b.o` being accepted, with sources[1].path == "sub/b.cc". So `sub/x.f` would be in plan().sources and missed by listSources.
(5) Main's 0009 really does match either case: `dir("src", pattern = "[.]([fF]|[fF]9[05])$")`. PLAN.md:3183-3184 records "(either case of the f)".
(6) R's default rules never compile `.F`. Pristine install.R lines 1420 and 1503 use `\.([cfmM]|cc|cpp|f90|f95|mm)$`. Makeconf.in:187 (`.SUFFIXES: .c .cc .cpp .d .f .f90 .f95 .m .mm .M .o`) and the project's Makeconf.win:316 have no `.F`. So `.F` gets built only by a package's own rules, which makes the package tier 3.

As written, M1(a) therefore drops the up-front flang check for tier-3 packages whose top-level Fortran is `.F` only. Today's 0009 catches those. Such a package would now get past the preflight (and run configure, if it has one) and only then stop at zig-fc with the no-flang text. CONSOLIDATION.md says nothing about this.

The subdirectory case is the same as today. 0009's header documents top-level-only as deliberate, so that unused vendored Fortran does not ask for flang. Still, the doc's "the same files R's OBJECTS rule compiles" is inexact: 0009 itself says "default OBJECTS rule", and a Makevars OBJECTS can name subdirectory files that plan() compiles.

The suggestion is sound. M1(a)'s reason "Makevars: a rule at line N" can only come from plan()'s Makevars evaluation (makefile.zig error.Unsupported), not from classify(). So the preflight already has to run plan() for Makevars packages, and plan().sources is available at no extra cost. For tier 2 (build.zig), plan().sources is only an approximation, but that does not undo the finding.

Severity "minor" fits: the error text is the same, it just arrives later.

I wrote no scratch files under consreview/. The one temporary file I made in the session scratchpad (an extracted pristine install.R) has been deleted.

## preflight-F6 (minor)

- Claim or gap: M7(a): keep 0010 because 'it serves configure scripts, which are tier 3, and users at the prompt; install.R on unix never calls it'.
- Evidence: The outcome is right (see confirmed claims: config:195-199, rcmdfn.c:532-533). The rationale is wrong (F1). install.R calls R CMD config for any package whose configure R runs: tier 0, tier 2 or tier 3 under pkgplan.
- Consequence: As worded, M7 implies that tier gating can ignore R CMD config. That hides F2.
- Suggestion: Reword M7(a): R CMD config is reached by install.R only through an R-run configure script, of any tier. The preflight covers that case with F2's trigger. Keep 0010 and hermetic-check's direct-call assertion unchanged.

Verifier:

I could not refute the finding; it holds against the code. Both parts of M7(a)'s rationale (CONSOLIDATION.md lines 74-79, repeated in interface row 4) are false.

(1) The claim that install.R on unix never calls R CMD config is wrong. I checked install.R from the pristine R 4.6.1 CRAN tarball, unpatched at lines 1306-1330 and again with patches 0005 and 0009 from main and 0013 from the branch applied (line ~1408). In its unix configure branch, install.R itself runs `system2(file.path(R.home("bin"), "R"), c("CMD", "config", x), stdout = TRUE)`. It does this inside a vapply, before `./configure`, for each of CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and FCFLAGS that is not already set in the environment. The guard is `use_configure && file_test("-x", "configure")`, and it does not depend on src/. The Windows configure.win branch (~1373) is a second caller, not the only one. No patch removes the unix call.

(2) The claim that configure scripts are tier 3 is wrong under pkgplan. In the branch's pkgplan.zig:127-133, `classify` returns `.r_only` when there is no src/ and `.zig` when src/build.zig exists, before it looks for a configure script. The test at pkgplan.zig:697-699 asserts a package with a configure script and src/build.zig is `Tier.zig`. So a configure package R runs can be tier 0, 2 or 3; tier 1 cannot have one.

Main's 0010 (src/scripts/config) runs `zig-cc --rzig-check=build-tools > /dev/null || exit` before any variable query. config also evaluates Makeconf through make in any case. Under M1(a)'s gating, a tier-0 or tier-2 package with a configure script would skip the build-tools check. Then install.R's own R CMD config call would fail when make is missing, and with empty stdout the vapply errors.

So tiers 0 to 2 can reach 0010, and the finding's rewording is justified. The finding's 'install.R calls R CMD config for any package whose configure R runs' is accurate. The only nuance: variables already set in the environment are skipped.

Files checked:
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/.github/devdocs/feat-zig-pkg-build/CONSOLIDATION.md
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/tools/rzig/pkgplan.zig
- /home/luciorq/projects/r-zig-pixi/zigbuild/patches/R-4.6.1/0009-install-compile-preflight.patch
- /home/luciorq/projects/r-zig-pixi/zigbuild/patches/R-4.6.1/0010-config-make-check.patch
- install.R from /home/luciorq/projects/r-zig-pixi/build/R-4.6.1.tar.gz

The scratch directory has been deleted.

## preflight-F7 (minor)

- Claim or gap: The document does not state when a package that passes M1(a) as tier 1 (no build-tools check) still needs make or sh.
- Evidence: These are all the conditions found, assuming F3 is fixed. (1) 0013 is bypassed: `if (!file.exists(rzig)) return(NA)` (merged install.R:703) sends the build to make whenever R_HOME/bin/toolchain/rzig[.exe] is absent, while the preflight runs under CC's name. That covers any tree without M2(a)'s name. R_ZIG_PKG_BUILDER=make is covered, because (a) forces the tier to make. (2) The hook's plan() differs from the preflight's because of different inputs (F4). (3) On Windows, --clean or --preclean with cleanup.ucrt or cleanup.win runs `sh ./cleanup.*` (main install.R:613-617, run_clean called at 1193 and 1956). The classifier ignores cleanup (pkgplan.zig:709-712), and a failure is only a warning. Unix `./cleanup` uses /bin/sh, which is not a toolchain group tool. Some paths can never reach a tier-1 package: run_clean's make clean runs only with src/Makefile* (install.R:595-605), which is tier 3, and R CMD config runs only with a configure, which is tier 3 for packages with src/. Type: Frontend packages run configure and make (install.R:1028-1042) before the preflight and outside the tiers.
- Consequence: The make fallback of item (1) is silent and lands in 'make: not found'. Item (3) silently skips cleanup on base + compilers on Windows.
- Suggestion: In 0013, when CC's binary exists but `rzig` does not, stop with a clear line instead of falling back to make, or have `--rzig-check=package` check for the name. Note the Windows cleanup.* case in M1 and in the phase 7 scope statement.

Verifier:

The finding holds as a minor gap in the document, though only part of its evidence survives. Checked against a scratch install.R built from the CRAN 4.6.1 tarball with main's 0005 and 0009 and the branch's 0013, applied in order with patch -p1 -f -F0 (every hunk applied; 0013's third hunk at offset 17).

What holds:
(1) Windows cleanup. run_clean (merged install.R:612-617) runs `system("sh ./cleanup.ucrt")` or `system("sh ./cleanup.win")` on Windows. It is called for --preclean (merged 1239) and --clean (merged 2004). Those are main's 613-617, 1193 and 1956, so the cited lines are correct for main.
(2) The classifier ignores cleanup on purpose. pkgplan.zig classify() looks only at build.zig, configure(.ucrt/.win), Makefile(.ucrt/.win), Objective-C and Makevars. Its test at pkgplan.zig:709-712 says "cleanup does not make a package tier 3".
(3) sh on Windows comes only from the build-tools group: env.sh group_dirs puts build-tools at "usr binutils". So a tier-1 Windows package with cleanup.win, installed with --clean or --preclean on base + compilers, needs sh.
(4) Frontend packages run configure and make (merged 1074-1090) before the preflight.

CONSOLIDATION.md never mentions cleanup, --clean or Frontend. Section 5 says outright that "the build-tools group is needed only by tier-3 packages". That statement is too broad.

What is weaker or wrong:
- Item (1), the bypass: the hook's `if (!file.exists(rzig)) return(NA)` (merged install.R:703) does fall back to make. But installRzig installs every name together (build.zig:2585-2596). Under M2(a) every merged tree has `rzig`. Under M2(b), 0013 itself moves to CC's name. So no tree from either menu choice has CC's binary without `rzig`, and the "make: not found" outcome does not arise in practice.
- "Silently" is wrong. On Windows, a system() whose command cannot be launched warns "'sh' not found" (sys-win32.c, the NOLAUNCH branch), and install.R then warns "running 'cleanup.win' failed". The install goes on with warnings, not silently.
- Item (2) belongs to F4, not to this finding.
- The cleanup case needs a package with cleanup.win or cleanup.ucrt but no configure.win, configure.ucrt or Makefile.win, plus an explicit --clean or --preclean. That is narrow, which fits the minor severity.

Scratch copy deleted.

## preflight-F8 (minor)

- Claim or gap: Citations and state in the record: 'install.R 1356' (:23); '0013's hunks at 683 and 746' (:23); 'pfC (one `.c`, no Makevars)' (:88-89); 'the worktree is clean, nothing to commit before the merge' (:6-7); 'the HANDOFF file folded in and removed' in the merge commit (:156-157).
- Evidence: 1356 is the branch's numbering, while the document says it checked against main. On main the Windows call is at 1325-1327 and the unix call at 1359-1364; after the merge they are at 1371-1373 and 1406-1408. In 0013 the hook is only in the 683 hunk; the 746 hunk is patch_rpaths' change from uname to Sys.info. mkpkg writes both src/f.c and src/val.c (verify-bundle.sh:243 and 249). `git status` in the worktree shows HANDOFF.md and CONSOLIDATION.md untracked, and HANDOFF.md has no history (`git log -- HANDOFF.md` is empty).
- Consequence: Readers who check the line numbers against main will not find them. Because HANDOFF.md is untracked, the merge commit cannot 'remove' it, so its content is lost unless it is folded into PLAN.md first.
- Suggestion: Cite main's line numbers. Say that the hook is in the 683 hunk. Say 'two .c files'. Say that the worktree has untracked HANDOFF.md and CONSOLIDATION.md, and fold HANDOFF.md's content into PLAN.md before deleting it.

Verifier:

I could not refute the finding. Four of its five points hold against the code. I checked the line numbers by extracting install.R from build/R-4.6.1.tar.gz and applying the patches in scratch, which I then deleted.

(1) The Windows Rcmd.exe "config" call is at 1325-1327 with main's 0005+0009. It is at 1356 only with the branch's own, shorter 0009 (+0013), and the worktree's build/R-4.6.1 install.R also has it at 1356. With main's 0009 plus the branch's 0013 (the merged result) it is at 1371-1373. So the document's "install.R 1356" uses branch numbering. That is in the same table row as "0009's one hunk at install.R 1273 (36 lines)", which is main's 0009.

(2) In 0013 the rzig_build hook and the run_shlib call are both in the @@ -683 hunk. The @@ -746 hunk only replaces `uname -a` with Sys.info() in patch_rpaths. There is also a third hunk, @@ -1521, which makes a src/build.zig count as a native build.

(3) mkpkg in scripts/verify-bundle.sh writes src/f.c (line 243) and src/val.c (line 249), so pfC has two .c files, not one. It has no Makevars because the lib argument is not passed.

(4) `git status` in the worktree shows .github/devdocs/feat-zig-pkg-build/HANDOFF.md and CONSOLIDATION.md as untracked. `git log -- HANDOFF.md` is empty, so "the worktree is clean" is literally false.

Two small caveats:
- The finding gives the merged unix call as 1406-1408; it actually spans 1405-1410. This does not change the point.
- The finding's stated consequence is overstated. The document already says HANDOFF is "folded in and removed", so its content would not be lost. Only the wording is wrong: a merge commit cannot record removing an untracked file.

Separately, the document claims "install.R on unix never runs R CMD config itself". That is wrong. The unix configure branch calls `R CMD config` for CC, CFLAGS and the other configure variables, at lines 1359-1364 on main. That is a more substantive error than the line numbers, and it bears on whether 0010 is touched by tiers.

## channels-C10 (minor)

- Claim or gap: Section 1 row 4 and M7(a): 'install.R on unix never runs `R CMD config` itself (only the Windows configure.win branch does, install.R 1356)'.
- Evidence: Pristine install.R:1310-1335, the unix branch for an executable `configure`, runs `system2(file.path(R.home("bin"), "R"), c("CMD", "config", x))` for CC, CFLAGS and the rest (:1327). The Windows branch is :1290-1292. hermetic-check.sh:107-111 and verify-bundle.sh:1368-1370 already say that the install runs R CMD config before configure.
- Consequence: The premise is wrong. The conclusion still holds: only packages with a configure script meet 0010, and those are tier 3.
- Suggestion: Reword: 'install.R runs R CMD config only for a configure script (unix and Windows), i.e. tier 3, so 0010 is untouched by tiers'.

Verifier:

Confirmed against the code; I could not refute the finding. In the pristine CRAN install.R (extracted from build/R-4.6.1.tar.gz), the non-Windows branch of `if (use_configure)` runs `system2(file.path(R.home("bin"), "R"), c("CMD", "config", x), stdout = TRUE)` at :1327 whenever `file_test("-x", "configure")` is true. It does this for CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and FCFLAGS. The Windows branch calls Rcmd.exe config at :1292. I applied the install.R hunks of main's 0005 and 0009 and the branch's 0013 to a scratch copy, and none of them touches that region. The unix call is still there, at 1408 after all three patches (1362 with main's patches only); the Windows call is at 1373 (1327). So CONSOLIDATION.md is wrong in two places. Section 1 row 4 says "install.R on unix never runs `R CMD config` itself (only the Windows configure.win branch does, install.R 1356)", and M7(a) says "install.R on unix never calls it". Main's own scripts already describe the correct behaviour: scripts/hermetic-check.sh:107-111 says "the install's R CMD config (patch 0010) fails before a configure would run", and scripts/verify-bundle.sh:1368-1370 says "the install runs R CMD config before configure (for CC and the other variables)". The finding's assessment of impact also holds. On both OSes the call happens only for packages with a configure script, which are tier 3, so tiers 0-2 never reach 0010 and the M7(a) conclusion stands. Only the stated premise and the line citation need rewording. The scratch copy under consreview/verifier-C10 has been deleted.

## channels-C11 (minor)

- Claim or gap: M3: 'the compile tree cannot host the no-make check at all: its etc/Renviron puts bin/toolchain/usr/bin first on PATH'. M3(c): 'Fails on Windows (no binutils/ in the base for the make path's $(NM))'.
- Evidence: Windows R reads etc/Rcmd_environ (build.zig:2533-2536, R_ZIG_TOOLS_PATH), not the Renviron PATH line (build.zig:3790-3803: unix only). Windows' build-tools group has no usr/bin until phase 7 (verify-bundle.sh:62-64; compile-tree.sh:5-6). compile-tree.sh:16-18 (C11) records that without binutils a DLL 'links there without $(NM), which winshlib.mk pipes into sed, and passes', consistent with winshlib.mk's `$(NM) $(OBJECTS) | $(SED) …` recipe.
- Consequence: The 'cannot host' reason holds on unix only in phase 3. (c)'s stated mechanism is wrong: the link passes vacuously. (c) does fail on Windows, but in 0009's build-tools check (check.zig:107-133).
- Suggestion: Scope the Renviron sentence to unix (Windows: from phase 7). Give (c)'s failure as the preflight's build-tools stop, and the vacuous NM-less link otherwise.

Verifier:

I could not refute either part. Both hold against main e1ce179 and the branch at 8ce3f77. The branch does not touch Rcmd_environ, Renviron or the toolchain groups, so the merged tree behaves the same way.

Part 1: the Renviron sentence is true only on unix in phase 3.
- On unix, build.zig:3864-3866 (finalRenviron) does write `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`, and the compile tree there has usr/bin/make.
- Windows R never reads etc/Renviron. In R 4.6.1, process_system_Renviron is called only from src/unix/system.c:337. src/gnuwin32/system.c calls only the site and user Renviron. build.zig:3790-3803 also says "unix only".
- On Windows the PATH line comes from etc/Rcmd_environ (rcmdEnviron, build.zig:2533-2536), via R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin. In phase 3 that directory does not exist. The Windows build-tools group is binutils/ only: zigbuild/toolchain/build.zig:13-22 and windows_dirs, verify-bundle.sh:62-64, and env.sh group_dirs (copied by compile-tree.sh). Rtools' PATH line in R's Rcmd_environ is a commented INSTALLER-BUILD line.
- So on Windows in phase 3 the compile tree adds no make. pkg-parity's Windows no-make step (env -i, PATH=$NOMAKE:System32) would find no make there. "Cannot host the no-make check at all" is therefore false on Windows until phase 7.

Part 2: (c) does fail on Windows, but at 0009's preflight, not in make.
- 0009 on main runs `--rzig-check=build-tools` for every compiled package. Under M1(a), R_ZIG_PKG_BUILDER=make forces tier make, so the check still runs for the make references.
- pkg-parity does not set R_ZIG_NO_PREFLIGHT. Its R_MAKEVARS_USER names a file that does not exist, so makevars_user() is empty and the preflight runs.
- On Windows, check.zig buildTools (lines 107-133) looks for binutils/*.exe beside rzig and exits 127. The base has no binutils/, so make is never reached.
- If the preflight were skipped, winshlib.mk's `$(NM) $(OBJECTS) | $(SED) ... >> tmp.def` pipeline exits with sed's status. A missing $(R_HOME)/bin/toolchain/binutils/nm.exe (Makeconf.win:95,226) would then not stop the link. compile-tree.sh:16-18 (C11) records exactly that: the link "passes".
- So M3's "make's Windows link needs binutils/nm.exe" and (c)'s "for the make path's $(NM)" describe a failure point that does not happen.

Weak spot: the preflight's own stop message names binutils/nm.exe first. That makes (c)'s parenthetical close in wording, even though the failure happens at a different point.

Impact: both issues are minor. The recommendation M3(a) is unaffected, because it already runs the no-make check on the base.

I created no scratch files.

## channels-C13 (minor)

- Claim or gap: Tier 2 under the hermetic channels (implicit).
- Evidence: pkgbuild runs `zig build --build-file … --cache-dir … --prefix … -Dplan=…` with no offline or --system flag (pkgbuild.zig:302-305). The tier-2 root names the package's src/ as a path dependency (pkgbuild.zig:267-278). Inferred: zig's package manager also resolves that package's own build.zig.zon dependencies, fetching URLs into the global cache.
- Consequence: Inferred, not run: a tier-2 package with remote dependencies would download at install time, and fail offline or under env -i. No check covers it (zighello has none).
- Suggestion: Decide and record: either refuse URL dependencies (tier 2 means vendored or path-only) and pass zig's offline/--system option, or document the network access.

Verifier:

I couldn't refute it. The code matches the claim, and a scratch run confirmed the part the finding only inferred.

What the code does on the branch at 8ce3f77:
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/tools/rzig/pkgbuild.zig lines 267-278 write the tier-2 root build.zig.zon with `.pkg = .{ .path = "<rel src>" }`.
- Line 302 runs `zig build --build-file … --cache-dir … --prefix … -Dplan=…`, adding only `-jN`. There is no `--system` flag and no `ZIG_GLOBAL_CACHE_DIR` override.
- The classifier (pkgplan.zig:130) only checks that `src/build.zig` exists. Nothing reads or limits a `src/build.zig.zon` or its URL dependencies.
- main e1ce179 has no pkgbuild.zig. The merge's semantic fix (find_zig unwrap) does not touch this either.

The scratch test used zig 0.16.0 from .pixi/envs/default, with its own cache dirs:
- I built a root shaped exactly like rzig's (path dependency `pkg`) and pointed it at a src/ whose build.zig.zon has one URL dependency on an unreachable host.
- `zig build` failed with `build.zig.zon:6:29: error: unable to connect to server: ConnectionRefused`. Zig resolves the path dependency's own manifest and tries to download its URL dependencies at install time, so the install fails offline.
- `zig build --help` lists `--system [pkgdir]  Disable package fetching`. The option the suggestion relies on exists.

Coverage: the zighello fixture (proto/zighello/src) has no build.zig.zon, so pkg-parity never exercises this. CONSOLIDATION.md, HANDOFF.md and PLAN.md never mention network access, fetching, URL dependencies or `--system` for tier 2. So the gap is real and not recorded. Minor severity fits, since today's only tier-2 fixture has no dependencies. Scratch dir deleted.

## channels-C14 (minor)

- Claim or gap: Citations in sections 1 and 3.
- Evidence: 'scripts/pkg-parity.sh:6' is a comment line; the tree path is at pkg-parity.sh:34. Section 3 says pfC is 'one .c', but mkpkg writes src/f.c and src/val.c (verify-bundle.sh:236-249).
- Consequence: Wording only.
- Suggestion: Fix the line number and the file count.

Verifier:

I could not refute either part of the finding; both hold against the code as it is now. (1) CONSOLIDATION.md line 21 says "`scripts/pkg-parity.sh:6` still builds `dist/R-$R_VERSION-$FLAVOR-zig`". At 8ce3f77, line 6 of scripts/pkg-parity.sh is a header comment ("# For cli (C), digest (C and C++), quadprog (Fortran) and Rcpp (C++),"). The tree path is on line 34: TREE="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}". The file exists only on the branch (it is absent on main), so merging does not change its line numbers. (2) Section 3 (CONSOLIDATION.md line 88) calls pfC "one `.c`, no Makevars". In main e1ce179, scripts/verify-bundle.sh:236-249 shows that mkpkg always writes src/f.c (the .Call wrapper) and src/val.c (v=val.c unless `lib` is given). Scenario 2 calls `mkpkg "$pf/pk" pfC 1` without `lib` (line 539), so pfC has two .c files: src/f.c and src/val.c. "No Makevars" is correct. The branch does not change verify-bundle.sh (git diff b490bdf..8ce3f77 touches only pkg-parity.sh among these files). Both errors are wording-level, so the finding's "minor / wording only" severity is right.

## Refuted

### channels-C12

Claim: Hermetic coverage of the branch's goal ('R CMD INSTALL with nothing but zig'; HANDOFF.md:11-20).

Not real as stated. The narrow fact holds: no check traces execve during a tier-1 install. But the stated consequence and the example are wrong, one piece of evidence is false, and the gap is a deferral the branch already records.

What holds:
- main's scripts/hermetic-check.sh (lines 149-160, unchanged by the branch) runs the base with no ZIG_BIN and PATH set to the tree's bin, so hermeticSrc stops in the preflight. The strace run never has zig.
- In scripts/pkg-parity.sh (lines 179-200), the no-make proof is a restricted PATH with no trace.
- In main's scripts/verify-bundle.sh, scenario 2 (lines 524-546) is untraced. The strace in scenario 3 only filters for make, with grep -E '/g?make$'.

What does not hold:
1. "pfC would be the first env -i run of rzig build with a fresh HOME" is false. pkg-parity.sh:197 already runs `env -i HOME="$WORK/work" PATH="$NOMAKE"`, and line 48 re-creates $WORK/work on every run. So rzig build's cache, $HOME/.cache/r-zig/zig-build (cache.zig root), starts empty. PLAN.md M4 records this: "quadprog with flang sh zig on PATH 12 s (a fresh HOME, so the build runner compiles again)".
2. "Nothing asserts on linux that a tier-1 install starts no make, sed, nm or uname" overstates the gap. pkg-parity's no-make install requires quadprog (C and Fortran) to install and test-load with PATH holding only sh, zig and flang. So none of those tools can be started by name. Line 114 also requires zero make lines in the zig path's log.
3. The example fails against the code. A fallback through R's system() in install.R goes through /bin/sh with PATH=$NOMAKE, so a tool in /usr/bin cannot be found by name. If the call's failure is fatal, pkg-parity fails. If install.R ignores the failure, the tool never ran. The proposed strace would not see that case either, because hermetic-check's filter (`grep -v '= -1'`) drops failed execs. A trace adds only one thing: catching a tool started by its absolute path. Nothing in the tier-1 path does that. 0013 replaces `uname -a` with Sys.info(), 0002 makes Sys.which scan PATH in-process, and the installed etc/Renviron has no /usr or /bin paths.
4. The branch's PLAN.md ("Not in M4") records the trace as a deliberate deferral: "the restricted PATH is the check ... A traced variant can join hermetic-check.sh when bin/R no longer needs sh". This does not come from the consolidation with phase 3. The proposed allowlist is also incomplete: it leaves out R's launchers, flang and its child processes, and the test-load R.

What remains is an optional extra test for absolute-path execs. Nothing shows a defect.

Files read:
- /home/luciorq/projects/r-zig-pixi/scripts/hermetic-check.sh (main)
- /home/luciorq/projects/r-zig-pixi/scripts/verify-bundle.sh (main, lines 270-310, 484-546, 990-1092)
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/scripts/pkg-parity.sh
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/tools/rzig/pkgbuild.zig (lines 285-330)
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/tools/rzig/cache.zig
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch
- /home/luciorq/projects/r-zig-pixi/.claude/worktrees/feat-zig-pkg-build/.github/devdocs/feat-zig-pkg-build/{PLAN.md,CONSOLIDATION.md,HANDOFF.md}

## Claims of CONSOLIDATION.md confirmed

### coverage

- Exactly one existing assertion inverts (scenario 2's pfC), as long as rzig build succeeds wherever make did. I checked every R CMD INSTALL and install.packages assertion on main (verify-bundle.sh, contract-test.sh, hermetic-check.sh, recipe/test-*.R, wheel-test.sh, stress.R). None of them greps make's echoed command lines. They assert install success, load, rpath/NEEDED/minos or preflight texts, and all of those carry over to rzig build. What does change is the builder and the coverage, not the pass/fail of the assertions (see the findings).
- pfC flips: mkpkg pfC (src/f.c and src/val.c, no Makevars; verify-bundle.sh:236-251, 539) is tier 1. Measured: the branch's `rzig build --classify` prints makevars and --plan-only exits 0 for the same layout. Main's 0009 runs --rzig-check=build-tools for every package with src/ (zigbuild/patches/R-4.6.1/0009-install-compile-preflight.patch, the loop over c(... "--rzig-check=build-tools")).
- pfF still stops at the compilers check with no flang. 0009's loop runs --rzig-check=fortran before build-tools (0009 patch, the chk loop), and src/a.f is at src/'s top level (verify-bundle.sh:541).
- hermetic-check.sh is unchanged. hermeticA/B have no src/, so run_shlib and the hook never run. hermeticSrc (hermetic-check.sh:105-106) stops in 0009 with the compilers text before run_shlib, since HERMETIC_ENV has no ZIG_BIN and PATH is $T/bin (:94). The strace allowlist (:213-222) sees only zig-cc, and that stays true under M1(a). The R CMD config CC check (:161-171) is 0010 and does not depend on tiers.
- Scenario 3's nopre is unchanged on every OS. configure_marker writes both configure and configure.win (verify-helpers.sh:54-60). pkgplan classify returns .make for configure, or configure.win/ucrt on Windows (pkgplan.zig:132-133). pkgbuild returns exit 3 at pkgbuild.zig:193, before find_zig at :293. So with R_ZIG_NO_PREFLIGHT=1 the make path compiles and prints the `zig-cc: no zig` line that verify-bundle.sh:1393 expects.
- R CMD SHLIB does not go through 0013's hook. In R-4.6.1, .SHLIB calls .shlib_internal directly (install.R:2537-2541 in the CRAN tarball). 0013's rzig_build is defined inside do_install_source and called only from run_shlib (0013 hunk @@ -683: `zig <- rzig_build(...)` at the top of run_shlib). So every R CMD SHLIB check stays on make: verify-bundle.sh:729-730, 773-774, 793-794, 835-836, 890-895, 923-924, 952-958 (unix scenario 2) and :1286-1287 (Windows scenario 3 OpenMP). So does Rcpp's evalCpp in contract-test.sh:70, which goes through R CMD SHLIB at Rcpp/R/Attributes.R:140.
- btLib, recipe's rzigar and the LTO record's ltodef/ltonodef (mkpkg ... lib: a Makevars with rules, verify-bundle.sh:246) stay on make. classify says makevars, then plan() rejects the rule line (pkgplan.zig:270-273; unit test pkgplan.zig:714-729). Measured: --plan-only exits 3 with "src/Makevars has a rule or target line: '$(SHLIB): lib/libval.a'".
- btRc stays on make on Windows. OBJECTS = f.o val.o res.o (verify-bundle.sh:1005), and pkgplan has no source suffix for res.o (source_exts .c .cc .cpp .f .f90 .f95, pkgplan.zig:438), so plan() gives "no source for res.o" and NeedsMake (pkgplan.zig:296-303). Its .rsrc assertion (verify-bundle.sh:1310-1312) still tests $(RESCOMP) through make.
- The strace check in scenario 3 ("the only make that ran is the group's", verify-bundle.sh:1074-1085) still holds. install.packages(Ncpus = 2) keeps its outer `make -k -j 2` whenever make is on PATH (0006, packages2.R hunk), and btLib's per-package make is still the group's. btA builds without make.
- The LTO record packages stay tier 3. The 0013 hook only takes -j digits from MAKEFLAGS (`(?<=-j)[0-9]+`), so MAKEFLAGS='LTO_OPT=-flto' (verify-bundle.sh:1340) gives no -j. ltodef/ltonodef fall back to make because of their rules.
- recipe/test-preflight.R is unchanged. r-zig-slim excludes lib/R/bin/toolchain/** (recipe.yaml:331-335), so rzig, and a future rzig/rzig.exe, ship in r-zig-toolchain (recipe.yaml:463-465). With no zig-cc, 0009 stops rzigsrc with the 'not installed' text before the hook. rzigronly has no src/. recipe/test-win.R installs nothing.
- Packaging needs no change for the new name. make-wheel.py moves everything under lib/R/bin/toolchain/ into the toolchain wheel (make-wheel.py:59, 434-435), and the stray check accepts any file whose content is rzig's (:417-418). share/zig/rpkg stays in the base wheel and in r-zig-slim.
- The decoy and R_ZIG_EXTRA_ENV reinstalls are not cache-vacuous under rzig build. build_t1.zig:61-66 calls setEnvironmentVariable on every Run step, because pkgplan always writes R_PACKAGE_NAME and CLINK_CPPFLAGS (pkgplan.zig:318). That clones the whole environment (zig 0.16 std/Build/Step/Run.zig:589), and Run.zig:805-808 hashes it into the step's cache key. So CONDA_PREFIX=decoy (wheel-test.sh:226, test-toolchain.R:106, verify-bundle.sh:1300) forces a real recompile.
- pkgplan supports what the tier-1 test packages use: C++ (link through SHLIB_CXXLD, pkgplan.zig:227-243), .f and .f90 with FLIBS added (:249-251), USE_FC_TO_LINK (:215, :244-248; test :679-686), and OpenMP as plain $(SHLIB_OPENMP_*) variables. Measured: --plan-only exits 0 for rzigfl (USE_FC_TO_LINK =), the wheel package (dot.c + sum.cpp, PKG_LIBS = $(BLAS_LIBS) $(FLIBS)) and fompfc (USE_FC_TO_LINK + SHLIB_OPENMP_FFLAGS).
- The order after the merge is as the doc says. Applying main's 0005-0010 plus the branch's 0013 to a scratch copy of the tarball's install.R gives: the preflight (line 1322), then configure (1358), then the run_shlib calls (Windows 1533/1550, unix 1605-1622), and inside run_shlib, rzig_build (736). 0013 applied with hunk 3 at offset 17 and no fuzz.
- pak's F7.7 regression case keeps its make path. The quoted -DMBEDTLS_CONFIG_FILE='"zip_mbedtls_config.h"' is in pak's embedded zip (pak/src/library/zip/src/Makevars:5), which has rules, so it is tier 3. keyring, curl, ps, pkgdepends, tsitter and tstoml have configure scripts (tier 3). Only cli, lpSolve, pkgcache and yaml become tier 1.
- The data.table OpenMP proof in contract-test.sh:84-94 stays on make: configure on unix, and on Windows its Makevars.win has an `all: $(SHLIB)` rule with mv.

### preflight

- Settled (1): the phase 3 implementer is right and the document is wrong. Pristine R 4.6.1 install.R has exactly two install-time config calls, both inside `if (use_configure)` (pristine 1277). Windows: `system2(Rcmd.exe, c("config", x), stdout = TRUE)` at 1290-1292, when configure.ucrt or configure.win exists (1279-1280). Unix: `vapply(ev1, function(x) system2(R, c("CMD","config",x), stdout = TRUE), "")` at 1324-1329, inside `file_test("-x","configure")` (1307). It runs for each of CC CFLAGS CXX CXXFLAGS CPPFLAGS LDFLAGS FC FCFLAGS not already set in the environment, or CCnn/CnnFLAGS under use_C. In main's patched numbering these are 1325-1327 and 1342/1359-1364, after 0009 at 1276-1311. After the merge with 0013 they are 1371-1373 and 1406-1408. No other library code calls config during an install: tools/R/sotools.R:27 is R CMD check's Windows DLL-symbol reader. Verified by reading the code.
- Tier 0-2 installs with no configure script that R runs never reach R CMD config, on unix or Windows (same two call sites). Tier 1 can never have one, because pkgplan.zig:132-133 classifies an R-run configure as make. Verified.
- 0009 on main is one hunk at install.R 1273 that adds 36 lines (patch header @@ -1273,6 +1273,42 @@). It runs with the package dir as cwd, before `if (use_configure)` (main-patched install.R:1281-1312).
- 0010 runs `--rzig-check=build-tools` before R CMD config evaluates Makeconf (main-patched src/scripts/config:184-193). On unix, its exit 127 under system2(stdout = TRUE) becomes R's error 'error in running command' (src/unix/sys-unix.c:1012-1017), which matches PLAN.md:3254-3258 and 3271.
- `rzig build --classify` exists and prints the Tier enum (r_only, makevars, zig, make): pkgbuild.zig:184-187, pkgplan.zig:27.
- The configure-script lists agree. Classifier: configure.ucrt and configure.win on Windows, configure on unix (pkgplan.zig:132). 0009: main install.R:1283-1285. R itself: pristine 1279-1280 and 1307. On Windows R only warns about a plain configure (pristine 1299-1304), and the classifier and 0009 both ignore it there.
- The Makefile and Makevars lists agree with R. Makefile: pkgplan.zig:134 against main install.R:1433 (Windows Makefile.ucrt/.win) and 1512 (unix src/Makefile). Makevars: pkgplan.zig:137 (Windows .ucrt, .win, then Makevars) against .shlib_internal at main install.R:2765-2788.
- Under --no-configure, for a package with src/ and no build.zig: neither 0013 nor classify() looks at use_configure, both say make (pkgplan.zig:133), and the make path then needs the build tools. So for those packages R and rzig do agree, as M1(a) says.
- The preflight can see Makeconf and the R environment plan() needs. R_ARCH is exported before Rcmd on unix (src/scripts/R.sh.in:157) and set by Rcmd.exe (gnuwin32/front-ends/rcmdfn.c:430-436) and by install.R:205 on Windows. pkgplan falls back to the same values (pkgplan.zig:154, pkgbuild.zig:177). R_HOME is exported (install.R:204 on Windows; pkgbuild.zig:166 needs it). R_PKG_CXX_STD is set at install.R:402, before the preflight. etc$(R_ARCH)/Makeconf is part of the base.
- Section 3 on hermetic-check holds. hermeticSrc has src/one.c and no configure (hermetic-check.sh:105-111), so the compilers check still stops it first. Its `R CMD config CC` assertion is a direct call (hermetic-check.sh:161-171) and does not go through install.R.
- Scenario 3's nopre has src/ plus configure (verify-bundle.sh:1381-1384), so it is tier make under the classifier and stays unchanged. pfC has no Makevars and no configure, so it is tier 1 and flips. pfF has a top-level src/a.f, so it still stops at the compilers check with flang.
- The phase 3 statement that install.R runs R CMD config before configure, so with the base alone the install stops first (PLAN.md:3277-3283, verify-bundle.sh:1366-1368), is correct for packages with an R-run configure, which is the only context it was written for.
- M7(a)'s outcome is right. On unix, R CMD config evaluates every variable through make (main-patched src/scripts/config:195-199). On Windows, Rcmd config runs `sh config.sh` (rcmdfn.c:532-533). So without the build tools R CMD config cannot produce values whatever 0010 checks, and (b) gains nothing for any tier.

### channels

- Merged CI order (verified with a read-only `git merge-tree --write-tree 8ce3f77 e1ce179` = a7e5661): build-r.yaml auto-merges. The branch's `pkg-parity` step lands after `contract` and before `check` (main build-r.yaml:116-119 plus the branch hunk). Download-artifact and unpack-toolchain (main build-r.yaml:65-71) have no `if`, so every leg has the toolchain tree: default, minimal, full, openblas and the upstream-zig legs. The compile tree exists before pkg-parity on every leg because `contract` depends on `compile-tree` (main pixi.toml:91).
- Exactly four files conflict (merge-tree: build.zig, pixi.toml, scripts/verify-tree.sh, zigbuild/tools/rzig/main.zig). compiler.zig and build-r.yaml auto-merge. Main still has `linux_target` at compiler.zig:238.
- On main, rzig_names() (scripts/verify-helpers.sh:38-44) is the single list that verify-tree.sh:113-141 and verify-bundle.sh:140-148 read. Adding `rzig`/`rzig.exe` there covers both. Nothing runs every name: scenario 1 runs only CC's check mode (verify-bundle.sh:408-426), and verify-tree only compares bytes with the first name (verify-tree.sh:114-120).
- installRzig installs every name as a copy (build.zig:2591-2593, addInstallFileWithDir). So `rzig` has the same bytes as zig-cc and passes make-wheel.py's stray guard (make-wheel.py:412-420). `rzig` lands in the r-zig-toolchain wheel through the TOOLCHAIN_PREFIX split (make-wheel.py:434-436), and share/zig/rpkg lands in the r-zig wheel. rzig is about 600 KB (the worktree dist), so one more copy costs little.
- conda (recipe.yaml): r-zig-slim excludes lib/R/bin/toolchain/** (recipe.yaml:332-335), so it gets share/zig/rpkg. r-zig-toolchain takes TC/** (recipe.yaml:463-465), so it gets `rzig`. The exact pin_subpackage (recipe.yaml:468-469) keeps the two in step.
- With r-zig-slim alone, 0009 stops a compiled package with 'the r-zig toolchain is not installed' before 0013's hook is reached (0009 patch; recipe/test-preflight.R:32-39). Only under R_ZIG_NO_PREFLIGHT or a user Makevars does the hook see no rzig and return NA, which leads to make: today's behaviour.
- Where `rzig build` gets zig in phase 3 (find_zig.zig:1-54). The compile tree has no zig/ (compile-tree.sh:61), so CI uses env.sh's exported absolute ZIG_BIN. verify-bundle scenario 2 passes ZIG_BIN in zig_env (verify-bundle.sh:296-302). pkg-parity's unix no-make run symlinks zig into the PATH directory (pkg-parity.sh:191), and its Windows run passes ZIG_BIN (pkg-parity.sh:189). The wheel uses Renviron.site's ZIG_BIN or `python3 -m ziglang` (make-wheel.py:241-254). Standalone users need zig on PATH or ZIG_BIN until phase 5.
- M3's Renviron claim holds on unix. finalRenviron appends `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}` in every flavor (build.zig:3855-3867), and the unix compile tree contains usr/ (compile-tree.sh:5-6, 59-65). So make is always reachable there and the no-make proof would be vacuous.
- Strace: hermetic-check's execve allowlist (hermetic-check.sh:213-221) is never reached by zig build, because the tree has no zig and the compilers check stops hermeticSrc first (hermetic-check.sh:149-160). M1(a) keeps CC's name, which is allowlisted at line 218. verify-bundle scenario 3's trace only filters `/g?make$` execs (verify-bundle.sh:1077-1086), so execs of zig and of the build runner (o/<hash>/build) do not trip it.
- Section 3: scenario 2's pfC/pfF (verify-bundle.sh:532-560) are the only assertions that flip. hermeticSrc (hermetic-check.sh:149-171) and scenario 3's nopre (verify-bundle.sh:1362-1400) stay as they are: with R_ZIG_NO_PREFLIGHT=1 the hook classifies nopre as needing make (configure), so the make path's `zig-cc: no zig` line still appears.
- The cache location is as stated: cache.root is XDG_CACHE_HOME, then on Windows LOCALAPPDATA, then HOME/.cache, then /tmp/.cache (cache.zig:22-29), and pkgbuild.zig:292 adds /zig-build.
- pkg-parity on the branch still builds the pre-phase-3 dist path, as the document says (the actual line is pkg-parity.sh:34, not :6).
