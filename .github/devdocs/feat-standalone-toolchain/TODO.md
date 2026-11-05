# TODO — feat-standalone-toolchain

PLAN.md (same directory) has the layered model, the facts, the options
and the reasons; the IDs below are its decision IDs (B1-B44).

**The decisions are answered (2026-10-08). Implementation may start per
B37 (a): #15 merges with phases 0-1 and these docs once its checks pass
(after the re-lock PR is on main), then one PR per phase.** The re-lock
PR and #14 continue as planned.

Every phase: implement in a worktree, review, test on linux-64 here,
omicron (osx-arm64, osx-64 under Rosetta) and kappa (win-64), then CI.
From phase 3 on, every phase runs verify-bundle's three scenarios (base
alone; base + compilers; base + compilers + build-tools) on every OS.
The user makes the commits (hand over the commands); docs-only commits
get `[skip ci]`.

## Decisions (all answered)

Answered (2026-10-07):
- [x] B1 = (a): one top directory for all archives
- [x] B2 = (a): `ZIG_BIN` → rzig's own `zig/` → PATH → `python3 -m ziglang`;
      flang from rzig's `flang/` then PATH; output a no-zig message that
      explicitly names the toolchain
- [x] B19 = (a): rzig in the base (standalone base archive, r-zig-slim,
      r_zig wheel)
- [x] B20 ≈ (a): the group design (compilers: `zig/`, `flang/`,
      `openmp/`; minimal build tools: unix make, Windows `usr/bin/` and
      `binutils/`; optional extras later); point 3 also settles a
      `LICENSES/` and `SOURCES` per group directory
- [x] B21 = (a): external runtime libraries stay with the base
- [x] B22 = (a): OpenMP compile files in the compilers group

Done, moot or merged: B16 (done: phase 1, 9bbce0b; omicron, kappa and
CI's macOS and Windows jobs still to pass), B3 (one toolchain per
platform; leftover in B31), B5 (→ B30), B8 (→ B20; B9, B29 and B44
remain), B10 (→ B22; B40 and B41 remain), B15 (→ B26).

Answered (2026-10-08). The user: "all ★ execpt:" B11, B24, B42, B43,
B44 (and the related items below); the full reply, verbatim, is in
PLAN.md, "The answers of 2026-10-08".
- [x] B4 = (a): PyPI's ziglang wheel as fetch-zig.sh pins it
- [x] B6 = (a): upstream zig builds the released standalone R, once a
      release job exists
- [x] B7 = (a): unix make is conda-forge's 4.4.1 from the build env
- [x] B9 = (a): flang's compile set copied from the build env, SOURCES
      from conda-meta
- [x] B11, the user's own: "Get all tools from conda-forge, look for m2-*
      variant of pacakges if needed." Every Windows `usr/bin` tool comes
      from a conda-forge package, a native win-64 build first, an `m2-*`
      package where there is none; the standalone group copies them
      into `TC/usr/bin/` with their DLL closure, conda's
      r-zig-build-tools depends on them; no busybox-w32 prototype
- [x] B12 = (a): CI artifacts now, release job later
- [x] B13 = (a): gzip/zip now; measure after phase 6
- [x] B14 = (a): bump in phase 4's PR and in each later PR that changes
      a package. Amended by the user, 2026-10-19: no bump in phases 4,
      SHLIB routing, 5 and 6; the next bump comes with phase 7's merge,
      to the number after universe's newest (PLAN.md's B14)
- [x] B17 = (a): base `R-<ver>-<flavor>-<plat>`, groups
      `R-<ver>-<plat>-<group>`
- [x] B18 = (a): upstream leads on the gated legs, conda waits for
      conda-forge's main label
- [x] B23 = (a): `TC/usr/bin/make`
- [x] B24, the user's own: "conda-forge copies `binutils/` for now, but
      keeping rzig routing for what is possible." conda-forge's MinGW
      binutils stay in `TC/binutils/`; ar and ranlib go through rzig now
      (B43); phase 3 checks dlltool, windres, strip, nm and as and moves
      each one rzig can serve
- [x] B25 = (a): R puts `TC/usr/bin` first on PATH, MAKE stays `make`
- [x] B26 = (a): rzig's check mode for every group, called by patches
      0009 and 0010
- [x] B27 = (a): conda's prefix paths (CA bundle to
      `<top>/ssl/cacert.pem`, Windows fonts to `<top>/Library/etc/fonts`)
- [x] B28 = (a): r-zig-slim + r-zig-compilers + r-zig-build-tools +
      r-zig-toolchain metapackage, one recipe
- [x] B29 = (a): r-zig + r-zig-compilers + r-zig-build-tools +
      r-zig-toolchain, no Fortran on PyPI
- [x] B30 = (a): a toolchain tree per platform; R trees hold the base
- [x] B31 = (a): a `toolchain` job per subdir; packaging legs run the
      three scenarios
- [x] B32 = (a): the check mode fails on another major.minor
- [x] B33 = (a): base runtime licences in this plan (phase 8)
- [x] B34 = (a): R's own environment's `bin/` after `zig/` (`flang/`),
      before PATH
- [x] B35 = (a): one text built into rzig, the same on every channel
- [x] B36 = (a): `R-<ver>-zig/`, dev trees under `dist/<flavor>/` and
      `dist/toolchain/`
- [x] B37 = (a): #15 merges with phases 0-1 and these docs, then one PR
      per phase
- [x] B38 = (a): compilers, build-tools
- [x] B39 = (a): sh, make, coreutils, sed, grep, gawk, which, findutils;
      pkg-config joins through B43
- [x] B40 = (a): OpenMP only when the base has the libomp runtime
- [x] B41 = (a): omp.h with the base and the win-64 binutils copies,
      accepted and recorded
- [x] B42 = (a), with the user's note: "keep "slim" everywhere and
      document that it has full's content (But keep notes that we want
      to work on that and make slim really slim, but later)." "slim" on
      every channel, documented that Windows slim has full's content;
      make Windows slim really slim later (Later)
- [x] B43, the user's own: "rzig answers to `gcc-ar`/`gcc-ranlib`, and
      Windows `AR`/`RANLIB` also go through rzig as on unix. `gcc-nm`,
      `pkg-config` and `objdump` can come from conda-forge, but we need
      to reaccess after the stress suite decide what is really needed
      and what zig cc/rzig already covers." rzig gains the two names;
      Windows AR/RANLIB go through rzig as on unix (`zig-ar`,
      `zig-ranlib`; B43-1 a); objdump (in `binutils/`) and pkg-config
      (in `usr/bin/`, named bare in Makeconf.win; B43-3 a) come from
      conda-forge; gcc-nm: "Ship from conda-forge if really needed"
      (B43-2, 2026-10-08), so none now; reassess them after the stress
      suite
- [x] B44, the user's own: "fortran through flang should succeed, we can
      work the flang-zig project to fit our needs." Fortran must pass on
      every OS; a phase 6 failure is fixed with flang-pixi; no OS ships
      without `TC/flang/`

Related items of the 2026-10-07 menu, answered 2026-10-08:
- [x] D6 = (b), the user: "b - rzig deals with the import library, do
      not report anything yet." rzig provides the `-lsynchronization`
      import library for upstream zig on Windows; no upstream report. An
      rzig change: feat-no-host-paths' proposed rzig follow-up PR (ii),
      at the latest phase 5
- [x] A2' ("A2: Do not file any report"): the atexit report is not
      filed; build.zig's workaround stays, through the 0.17 port
- [x] D7 = (a): CC_VER/FC_VER refreshed with phase 4's bump (phase 4
      keeps build 8 since 2026-10-19; they publish with phase 7's bump)
- [x] D12 = (a): rattler-build >= 0.76 with warnings as errors
      (feat-no-host-paths' proposed follow-up PR (i), or phase 4)
- [x] D14 = (a): the toolchain in its own env stays later
- [x] D15 = (a): the stress suite starts now, in parallel; it decides
      the extras and reassesses B39 and B43
- [x] E2 = (a): zstd declared with phase 4's bump (r-zig-slim; win-64
      r-zig-build-tools; phase 4 keeps build 8 since 2026-10-19)
- [x] C1 = (a), C2 = (a), C3 = (a): Windows minimal (no ICU, cairo,
      Tcl/Tk, OpenMP) and a Windows wheel without compile support, after
      phase 7
- [x] R1 = (a): the re-lock is its own PR

Not part of this plan (feat-no-host-paths PLAN.md and
chore-lock-and-ci-refresh PLAN.md record them): D1 (b: "Strip Linux
debug info"), D2 (a: "Keep `flang`"), D3 (b: "b - Fix it."), D4 (a),
D5 (a), D8-D11 (a), D13 (a), E3 (a), E4 (a).

## Outside this plan (continue as planned)

- [ ] The re-lock (chore-relock-flang-rt-10) merged as its own PR (R1 =
      a), before #14's bump publishes, so that build 5 carries the exact
      flang pins
- [ ] #14 (fix-rzig-baseline-cpu) merged: `-mcpu=baseline`, build 5;
      needed at the latest before phase 5 ships compilers to Windows
- [ ] #15: phase 1's remaining checks pass after the re-lock (History);
      then #15 merges with phases 0-1 and these docs (B37 a)
- [ ] The stress suite starts now, in parallel, on its own branch (D15 =
      a); its results feed the extras group, B39 and B43
- [ ] feat-no-host-paths' proposed follow-up PRs: (i) with D12
      (rattler-build error flags; phase 4 relies on it), (ii) rzig fixes
      with D6 (phase 5 relies on it)

## The zig 0.17 wave (B18 = a; not a phase of this plan)

- [x] 2026-10-06: conda-forge has 0.17.0 only on the `zig_dev` label
      (snapshots 0.17.0-dev.2320+1e770dbef, builds 23200-23202); main is
      0.16.0 build 20; PyPI ziglang is 0.16.0; ziglang.org has 0.17.0
      (2026-10-01) for all five platforms
- [x] 2026-10-07/08: flang-pixi's flang-zig 6, lld-zig 5 and
      flang-rt-zig 10 are zig 0.16.0 builds; its 0.17 builds will be 7, 6
      and 11. PyPI ziglang 0.17.0 uploaded 2026-10-08 01:00 UTC (six
      wheels at 01:09 UTC, no win_amd64); conda-forge's main label still
      0.16.0
- [x] 2026-10-13: conda-forge's main label has zig 0.17.0, B18's
      trigger (PHASE4 Cg14). Phase 4 stays on 0.16 because build.zig
      does not compile on 0.17 yet: r-zig-compilers' `zig 0.16.*` and
      r-zig-slim's `run_constraints: zig 0.16.*` (K a) keep a solved
      env on R's zig (gamma, 2026-10-14: `pixi add r-zig-slim zig`
      solves 0.16.0 `_20`); the 0.17 wave bumps both
- [x] Superseded: the old flang-rt-zig `build-number = ">=10"` item;
      the re-lock pins exact builds and drops the win-64 override
- [x] 2026-10-08, A2': no upstream report on the MinGW atexit export;
      build.zig's atexit workaround stays in the 0.17 port
- [ ] Before our pins move to flang-rt-zig 11 (a 0.17 build): nm its
      runtime archive on every subdir for symbols our zig 0.16 lacks, link
      each with zig 0.16, build R and a Fortran package on kappa
- [ ] The port of build.zig and rzig to 0.17 (`b.install_prefix`,
      `b.pathFromRoot`, configure caching) and zig-build.sh's argument
      order, behind a 0.16/0.17 switch, on the linux and macOS
      upstream-zig legs; fetch-zig.sh gets a 0.17 pin once PyPI has all
      five ziglang 0.17.0 wheels (win-64 stays on 0.16 until then)

## Phase 2 — rzig knows the groups

Needs (answered): B26, B32, B34, B35, B38, B40, B43 (the two names); B37
(the branch).

Status (2026-10-09): implemented in the worktree feat-standalone-phase2,
not committed; tested on linux-64, omicron and kappa; the review's code
fixes and CI pending. PLAN.md, "Phase 2 record", has what changed and the
choices made, and "Phase 2 tested" the results and the review.

- [x] find_zig.zig: `ZIG_BIN`, `<rzig dir>/zig/zig` (`zig.exe`),
      `<env dir>/bin/zig` (Windows `x86_64-w64-mingw32-zig.exe`), PATH,
      `python3 -m ziglang`; B35's text and exit 127 when the python3
      fallback cannot start or has no ziglang
- [x] flang_rt.flang(): `<rzig dir>/flang/bin/flang`, `<env dir>/bin/flang`,
      PATH; fortran.zig's no-flang text becomes B35's; its unit test and
      wheel-test.sh:149-168 follow (and verify-bundle.sh's check)
- [x] OpenMP (B40 a): `<rzig dir>/openmp/include` on every compile
      (`-idirafter` on Windows), `-L <rzig dir>/openmp/lib` on Windows,
      only when the base has the libomp runtime; `-lomp` rule counts
      `openmp/`
- [x] Check mode (B26 a): the compile lookup (`fortran` also flang), the
      build-tools check (make; Windows also sh), the zig and its
      version, the major.minor check (B32 a)
- [x] rzig's name map: `gcc-ar` (as zig-ar) and `gcc-ranlib` (as
      zig-ranlib) (B43)
- [x] build.zig passes R's version to rzig; the platform name comes from
      rzig's target (recorded in PLAN.md)
- [x] B35's text in one place (groups.zig), naming what exists today:
      r-zig-toolchain for conda and pip, the tools themselves for the
      standalone tree. Later phases edit only groups.zig for it (PLAN.md)
- [x] Unit tests: each lookup step, "zig/ wins over PATH", the env-bin
      step, missing zig and flang, the openmp rule with and without
      libomp, the check mode's exit codes and texts, the two new names
- [x] The shims mirror the zig and flang lookups; parity-test.sh: 15 new
      cases (openmp/ as deliberate differences) and 11 check-mode checks
- [x] `pixi run --locked rzig-test` on linux-64, conda-forge zig and
      upstream zig (fetch-zig): 94 unit tests, parity 0 failed
- [x] `pixi run rzig-test` on osx-arm64, osx-64 (omicron) and win-64
      (kappa)
- [x] conda test-toolchain.R and wheel-test.sh unchanged in behaviour
      (wheel-test.sh's no-flang check is new); verify-bundle as today
      (linux-64; verify-package also on omicron and kappa)
- [x] Review fix: the shims' environment variable `_e` becomes `_env`
      (the -march=armv* loop empties `_e`), plus two parity cases with
      `-march=armv8-a+crc` and the toolchain's flang
- [x] Review fix: Windows' build-tools check looks for make and ignores
      MAKE (R runs make there), plus a unit-test line
- [x] Review fix: parity-test.sh's "a zig that is not R's" check renamed,
      and a check with a zig that says 0.99.0
- [x] CI; then the user commits (hand over the commands) (merged as
      #22, 966d661)

## Phase 3 — the standalone layout, today's contents

Needs (answered): B7, B12, B13, B17, B23, B24, B25, B26, B30, B31, B36,
B38, B42, B43.

Status (2026-10-11): steps 1 to 6 done; steps 1 to 3 and P3-C committed
(a40fadb), steps 4 to 6 not. Tested on linux-64 (both zigs), omicron
(osx-arm64, osx-64 under Rosetta) and kappa (win-64); CI has not run.
PLAN.md's "Phase 3 record" sections have what changed, the choices and
the results; B24's routing check moved no tool (follow-up PRs).

- [x] env.sh: platform name once; prefixes `dist/<flavor>/R-<ver>-zig`
      and `dist/toolchain/R-<ver>-zig` (replacing env.sh:29's PREFIX);
      the seven scripts (zig-build, zig-package, zig-verify-package,
      zig-smoke, zig-contract, verify-tree, hermetic-check) read them;
      make-wheel.py:350 derives the same prefix (step 1, 2026-10-10,
      uncommitted: zig-package.sh and zig-verify-package.sh deleted;
      package-standalone.sh, verify-bundle.sh and fetch-zig.sh read the
      platform too; tested on linux-64, PLAN.md's "Phase 3 record")
- [x] build.zig toolchain step (pixi task `toolchain`), each directory
      with `LICENSES/` and `SOURCES`: `openmp/` (moved out of the base),
      unix `usr/bin/make` (moved out of minimal's tree), Windows
      `binutils/`: nm, dlltool, as, strip, windres (moved out of
      installWindowsCompilerContract) and objdump (new, from
      binutils_impl_win-64; check it ships it); ar, ranlib and ld.exe
      dropped (step 2, 2026-10-10, uncommitted: its own build root,
      zigbuild/toolchain/build.zig (open point A a), with
      `toolchain-test`, `verify-toolchain` and `unpack-toolchain`;
      objdump ships; `binutils/` also gets zstd.dll and vcruntime140.dll;
      the R trees keep their copies until step 3; tested on linux-64,
      PLAN.md's "Phase 3 record: step 2")
- [x] P3-C (a): each SOURCES package block names its recipe's sources
      (`source:`, URL and checksum or repository and revision) and its
      feedstock and commit (`feedstock:`), from the package cache; a GPL
      package with no source stops the build; verify-toolchain.sh
      checks the lines (2026-10-10, uncommitted; tested on linux-64,
      PLAN.md's "Phase 3 record: P3-C")
- [x] The base's TC holds only rzig; Windows adds `zig-ar.exe`,
      `zig-ranlib.exe`, `gcc-ar.exe`, `gcc-ranlib.exe` and drops `zig-cc`
      and `zig-cxx`; verify-tree.sh's rzig names (76) follow (step 3,
      2026-10-10: TC holds only rzig, the four names added, and `ar.exe`
      and `ranlib.exe` for CMake, which looks for them beside CC (step
      3's review); the names in verify-helpers.sh's `rzig_names`; step 4,
      2026-10-11, uncommitted: `zig-cc` and `zig-cxx` dropped; kappa's
      verify-tree finds exactly the nine names, PLAN.md's "Phase 3
      record: step 4" and "step 6")
- [ ] rzig routing check (B24): dlltool (zig dlltool, GNU long options
      and `--as`), windres (zig rc behind a windres-syntax front), strip
      (zig objcopy), nm and as (none in zig 0.16.0); move each one that
      passes, here or in a follow-up PR; record the result in PLAN.md
      (checked on kappa 2026-10-11 with both zigs, recorded in PLAN.md's
      "Phase 3 record: step 6": dlltool passes and takes as with it,
      windres works behind a front still to write, strip, nm and as are
      not routable; nothing moved in phase 3. Open until the dlltool/as
      follow-up PR; windres' front is the PR after it. feat-zig-pkg-build's
      stress table, 2026-10-12: no dlltool, windres, objdump or strip in
      make's echoed recipes of the Windows rows, which shows little:
      binutils calls are not traced, configure.win and `@`-recipes run
      silently, R CMD check did not run, and RcppParallel's TBB build ran
      windres through Rcmd_environ's RC, unseen; the table adds no
      evidence on B24 either way [stress-S2])
- [x] unix etc/Renviron: `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`,
      `MAKE=${MAKE-'make'}` for every flavor (minimal's `R_ZIG_MAKE` goes)
      (step 3, 2026-10-10, uncommitted: the file's last line; tested on
      linux-64, PLAN.md's "Phase 3 record: step 3")
- [x] Windows etc/Rcmd_environ:
      `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`
      (step 3, 2026-10-10, uncommitted: through the helper
      `R_ZIG_TOOLS_PATH`, since Renviron.c expands only a whole `${...}`
      default (C16); `R_ZIG_RC` names `binutils/windres.exe`; PLAN.md's
      "Phase 3 record: step 3"; kappa, 2026-10-11: verify-tree.sh's
      Rcmd_environ lines and verify-bundle's PATH run check (C27) pass,
      "Phase 3 record: step 6")
- [x] Makeconf.win: AR (103) `$(BINPREF)zig-ar`, RANLIB (213)
      `$(BINPREF)zig-ranlib`; LTO gcc-ar/gcc-ranlib (267, 269) unchanged
      (now rzig); NM (78, 204) → `binutils/nm.exe`; LTO gcc-nm (268)
      unchanged (B43-2); DLLTOOL (76), RESCOMP (79), OBJDUMP (211),
      STRIP_* (251-252) → `binutils/` (or rzig for moved tools);
      PKG_CONFIG (75) bare `pkg-config` (found in `TC/usr/bin` on PATH,
      like sed; conda's is in `Library/bin`); BINPREF for gcc/g++ and
      rzig's names (step 3, 2026-10-10, uncommitted: AR and RANLIB with
      `.exe`, `$(BINPREF)zig-ar.exe`, as CC for CMake (C16); OBJDUMP
      without `.exe`, which R CMD check adds (sotools.R; step 3's
      review); RESCOMP with windres' `--preprocessor` arguments; PLAN.md's
      "Phase 3 record: step 3"; kappa, 2026-10-11: verify-tree's lines,
      scenario 3's tools.mk, R CMD config AR/NM/OBJDUMP, R CMD check's
      objdump and RcppParallel's CMake pass; no tool moved to rzig (B24's
      follow-up PRs), "Phase 3 record: step 6")
- [x] Windows slim documented (B42 a): README and the recipe's summaries
      say Windows slim has full's content (step 3: the recipe's
      r-zig-slim `about:`; step 5, 2026-10-11, uncommitted: README's
      "Standalone archives" and conda install sections)
- [x] vendor-libs.sh: Windows libomp.dll trigger on R's OpenMP setting
      (step 3, 2026-10-10, uncommitted: `^SHLIB_OPENMP_CFLAGS = *-` in
      etc/x64/Makeconf; PLAN.md's "Phase 3 record: step 3")
- [x] Patches 0009 and 0010 call the check mode (compilers and build
      tools); 0009's fallback removed; 0010's `command -v` replaced (step
      4, 2026-10-11, uncommitted: 0009 runs `--rzig-check`, or
      `--rzig-check=fortran` for Fortran at src/'s top level, then
      `--rzig-check=build-tools`, through `system2(stdout = FALSE)`, and
      counts only the configure script R runs (Windows: configure.win,
      configure.ucrt); 0010 ends with rzig's status, 127; both keep the
      rzig-missing branch with R_ZIG_TOOLCHAIN_HINT until phase 4 (C8);
      tested on linux-64, omicron and kappa, PLAN.md's "Phase 3 record:
      step 4")
- [x] groups.zig (B35): unix's build-tools standalone line names
      `R-<ver>-<plat>-build-tools.tar.gz`; decide where the preflight
      shows a user's R_ZIG_TOOLCHAIN_HINT (rzig does not read it) (step 3,
      2026-10-10, uncommitted: Windows' line names its .zip (binutils) and
      the compilers line the compilers archive for OpenMP (C19); the hint:
      only in 0009's rzig-missing branch until phase 4, which prints a
      user's own as a `hint:` line after rzig's text (PHASE3 C8); PLAN.md's "Phase 3 record: step 3")
- [x] Check mode lines on Windows, before the preflight shows them: one
      path separator (find_zig joins with `\`, rzig's own path has `/`);
      a zig that cannot start says so, not "does not say its zig version"
      (step 3, 2026-10-10, uncommitted: `/` only, display only; "did not
      run: <reason>", exit 1; plus the Windows binutils in the build-tools
      check; unit tests run on linux-64, and on kappa in step 6, PLAN.md's
      "Phase 3 record: step 3")
- [x] package-standalone.sh: base archive + compilers + build-tools
      archives, `.sha256` each (step 2: `package-standalone.sh
      toolchain`, pixi task `package-toolchain`)
- [x] hermetic-check.sh: the R tree is the base, nothing deleted (step
      4, 2026-10-11, uncommitted: a compiled package stops with rzig's
      compilers text, unix R CMD config CC with the build tools' text;
      strace allows TC/zig-cc; no configure marker, which could not tell
      (C26 moved to verify-bundle's scenario 3); tested on linux-64,
      omicron and kappa, PLAN.md's "Phase 3 record: step 4")
- [x] verify-tree.sh: base TC = rzig only; toolchain tree records,
      closures (OS, own directory, base runtime), glibc 2.28 ceiling
      (the toolchain tree's part: verify-toolchain.sh, step 2; the base's
      and the move of the 2.28 tier: step 3, 2026-10-10, uncommitted,
      with the Makeconf, Renviron and Rcmd_environ lines and OpenMP's
      runtime; tested on linux-64, PLAN.md's "Phase 3 record: step 3")
- [x] verify-bundle.sh: the three scenarios (scenario 2 takes zig from
      `ZIG_BIN=$ZIG` and flang from the env until phases 5 and 6; Windows
      scenario 3 takes sh/make from the env until phase 7); file-list
      check (step 3, 2026-10-10: scenario 1 asserts the check mode's exit
      codes; tested on linux-64 slim and minimal, both zigs for slim,
      PLAN.md's "Phase 3 record: step 3"; step 4, 2026-10-11,
      uncommitted: rzig's texts, the preflight's branches in scenario 2
      and the R_ZIG_NO_PREFLIGHT pair in scenario 3 (C26); Windows' "no
      import library left" check; omicron and kappa pass, "Phase 3
      record: step 6")
- [x] conda: build.sh runs the toolchain step into `$PREFIX` (Windows
      binutils); packages unchanged until phase 4, no bump (step 3,
      2026-10-10, uncommitted; test-toolchain.R's static-library package
      and Windows records check; conda-package passes on linux-64 (step
      3's review); C22 and the Windows checks pass on kappa (step 6, which
      also empties dist/conda before each local build))
- [x] make-wheel.py: make from the toolchain tree; wheel-test checks
      `Sys.which("make")` (step 3, 2026-10-10, uncommitted:
      `--toolchain-prefix`, only rzig taken from the R tree's TC; tested
      on linux-64, PLAN.md's "Phase 3 record: step 3")
- [x] CI (B31 a, B12; PHASE3 section 3): toolchain.yaml, called from
      build.yaml, upstream-zig.yaml and stress.yaml (C3), builds,
      archives and checks the groups once per platform and uploads them
      as `toolchain-<runner.os>-<runner.arch>` (`-upstream` for upstream
      zig), kept 30 days (as long as failed legs can be re-run; still
      short of a release, B12); every leg needs it (`!cancelled()`, C4),
      full and openblas included, downloads its archives and runs
      `unpack-toolchain` (contract and stress use the compile tree); the
      packaging legs (default, minimal) run verify-package's three
      scenarios and upload only the base, as
      `standalone-<env>-<os>[-upstream]`, kept 7 days (step 5,
      2026-10-11, uncommitted; actionlint clean, PLAN.md's "Phase 3
      record: step 5"; PR #24's CI, 2026-10-12: all green, the toolchain
      legs 0-2 min, PLAN.md's "Phase 3 record: CI on PR #24")
- [x] kappa and windows-latest: a static-library package through
      `$(AR)`/`$(RANLIB)` (rzig), an `--use-LTO` build, and the packages
      that use each tool the routing check moved; stress RcppParallel
      with no ar on PATH (CMake finds rzig's `ar.exe` beside CC), and
      `R CMD check` of a package with a DLL (its compiled-code check runs
      `binutils/objdump.exe`, no "requires 'objdump.exe'" warning) (kappa,
      2026-10-11: all pass, the LTO builds once rzig drops -flto at
      Windows links, which zig 0.16.0 cannot link; no tool moved, so no
      moved tool's packages; PLAN.md's "Phase 3 record: step 6".
      windows-latest, PR #24's CI, 2026-10-12: verify-package's scenario
      3 and the LTO record pass)
- [x] compile-tree.sh requires the toolchain tree's `openmp/` where the
      base has the libomp runtime (the user's answer (4) to step 3's
      review, 2026-10-11; step 4, uncommitted; checked on linux-64,
      omicron and kappa)
- [x] stress.R classes the install preflight's stop as toolchain and
      reports rzig's `zig-cc:` line naming what is missing (step 4's
      review, uncommitted)
- [x] rzig's Windows links (kappa's findings, step 6, uncommitted): -flto
      dropped at image links (zig 0.16.0 cannot link LTO for
      x86_64-windows-gnu; the tester's option (b)); zig's import library
      named `<output>.rzig.lib` and deleted after the link, so no
      `guard_dispatch.lib` is left in src/; 98 unit tests; kappa's rounds
      2 and 3 pass
- [x] conda-package empties dist/conda before building (rattler-build
      kept a stale index on a rebuild with the same build string; step 6,
      uncommitted; linux-64 and kappa's round 3)
- [x] PLAN.md: the records of steps 4 to 6 with B24's result, the
      build-number texts (C14), Risks and the Verification recipe
- [x] Tested: linux-64 (slim, minimal, wheel, conda-package), omicron
      (osx-arm64 slim and minimal, osx-64 slim), kappa, CI (2026-10-11
      and 2026-10-12; PLAN.md's "Phase 3 record: step 6" and "CI on
      PR #24"; conda-package on macOS ran in CI)
- [x] Before merging: universe holds build 8 for all five subdirs (C13,
      `pixi run -e pkg conda-channel-list`) (r-zig-slim and
      r-zig-toolchain build 8 on all five, repodata, 2026-10-11)
- [x] The user commits steps 4 to 6 (hand over the commands); then the
      PR's CI: the core tier with conda-package, the `full-ci` label, the
      `upstream-zig` label, one stress dispatch (PHASE3 section 10)
      (548da1a, PR #24, 2026-10-12: all green)

## Phase 4 — conda and PyPI on the same boundary

Needs (answered): B14, B28, B29, B35, B38, B39, B11, B41; D7, D12, E2;
PHASE4's open points A-L (the user, 2026-10-14: the recommended
options; PLAN.md's "Phase 4: the user's answers").

Status (2026-10-14): steps 1 to 5 done in the worktree
feat-standalone-phase4 (from main d11dee1), not committed. Tested on
linux-64 (both zigs), omicron (osx-arm64) and kappa (win-64), two
rounds on each remote host; the upgrade from `_8` passed on all three.
CI has not run. PLAN.md's "Phase 4 record" sections have what changed,
the choices and the results; the reviewed plan and its critique are in
phase4/ beside these files.

- [x] Check: rattler-build 0.76.1 makes outputs with no files that do not
      inherit the staging build (not needed: the group packages and the
      metapackage `inherit` with `files: []` and package only their test
      file, as rattler-build's own staging-empty-files test does; the
      form without inherit stays untested, Cc17; step 1's file lists)
- [x] rattler-build >= 0.76 with warnings as errors (D12), if
      feat-no-host-paths' follow-up PR (i) has not done it (on main since
      3510530: conda-package's `--error-overlapping-files` and
      `--error-unused-staging-files`; every phase 4 conda-package ran
      with both)
- [x] recipe.yaml: r-zig-slim excludes only
      `lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` (and
      `Library/...`); r-zig-compilers, r-zig-build-tools, r-zig-toolchain
      metapackage; build number: the one after the number published
      when phase 4 merges (build 8 is on universe, so 9 unless another
      PR bumps first; B14 a, C14); since 2026-10-19 it stays 8 (B14's
      amendment). feat-zig-pkg-build (PR #25 and its
      review follow-up) changes r-zig-slim (patches 0009, 0012, 0013,
      share/zig/rpkg) and r-zig-toolchain (rzig: `--rzig-check=package`,
      `rzig build`, `rzig def`, the `rzig` name) and bumps nothing (its
      N5). They are coupled: a new r-zig-slim with an older
      r-zig-toolchain stops every compiled install (the old rzig answers
      `--rzig-check=package` with exit 2; without the preflight, 0013
      stops on CC's binary with no rzig). The bump that publishes phase
      4 publishes both together, and until then no channel mixes a
      locally built `_8` with universe's `_8` [phase3-P3-7,
      records-REC-7]. That bump comes with phase 7's merge (the user's
      decision, 2026-10-19: phases 4, SHLIB routing, 5 and 6 keep 8;
      PLAN.md's B14 amendment), and main does not publish until then
      (build.yaml's `CONDA_PUBLISH`) (step 1, 2026-10-14: build 9, built
      locally before that decision; universe still `_8` only on all
      five subdirs at 17:50 UTC; r-zig-slim keeps rzig and rpkg and gets
      `run_constraints: zig 0.16.*` (K a); `package_contents` tests on
      each output (Cc12); licences per E (a); PR #27's runner is in
      the build too; PLAN.md's "Phase 4 record: step 1")
- [x] win-64 r-zig-build-tools: B41's binutils copies (nm, dlltool, as,
      strip, windres, objdump, less any tool moved to rzig); run
      dependencies on conda-forge packages for B39's list and pkg-config
      (today's m2 list plus pkg-config until phase 7 chooses) (no tool
      moved, so all six; the eight m2 packages, pkg-config (F a) and
      zstd; no native make, Cg7; `GPL-3.0-or-later`; checked on kappa's
      packages and upgraded envs)
- [x] zstd declared (E2): r-zig-slim and win-64 r-zig-build-tools
      (r-zig-slim on every OS: libR.dylib links libzstd too, Cg18)
- [x] CC_VER/FC_VER refreshed in phase 4 (D7). On linux CC_VER is
      what the dev envs' zig prints (pixi.lock's libclang-cpp21.1 `_6`:
      clangdev 334cf9a5); the conda build solves libclang-cpp21.1 `_7`,
      whose zig prints 0586bae9, so phase 4's R_compiled_by()["C"] on
      linux-64 and linux-aarch64 is not the compiler libR.so's .comment
      names. PHASE4's risk 7 has come already, from a libclang-cpp
      rebuild, not a zig one (the first "Later" item)
      [conda-d7-cc-ver-stale] (step 4: osx-arm64's FC_VER is "flang
      version 23.1.1", confirmed on omicron; Windows' strings come from
      build.zig)
- [x] Hint writers removed: `-Dtoolchain-hint`, zig-build.sh's conda
      branch, make-wheel.py's renviron_hint (step 3, with recipe.yaml's
      `R_ZIG_CONDA_BUILD`; 0009 shows a user's hint on 127 only and
      0010 none, B b)
- [x] groups.zig (B35): the conda and pip lines name r-zig-compilers and
      r-zig-build-tools (steps 1 and 2: each ends "; r-zig-toolchain
      installs every group", H a; the pip compilers line says PyPI has
      no Fortran compiler, Cg3)
- [x] make-wheel.py: r-zig with rzig; r-zig-build-tools with
      `usr/bin/make`; r-zig-compilers and r-zig-toolchain without files;
      one tag set; the zig-cc check moves to the base wheel (step 2:
      Requires-Dist per A (a), licences per E (a); PLAN.md's "Phase 4
      record: step 2")
- [x] test-preflight.R: rzig present, no zig, preflight names
      r-zig-compilers (steps 1 and 3 and the review: also the
      configure-script stop with both texts (H), the user's hint (B), no
      hint writer, J's non-127 stop with a stand-in zig; wheel-test runs
      it with pip too, Cg10)
- [x] test-compilers.R and test-build-tools.R (new), test-toolchain.R
      with a narrowed PATH, one shared header (Cc4, Cg9); unix PATH for
      make's recipes: the host's /usr/bin:/bin after the env (step 1's
      B25 finding)
- [x] wheel-test.sh: the three scenarios with pip; uninstalling the
      groups leaves R whole (step 2: r-zig alone, + r-zig-compilers,
      + r-zig-build-tools, + r-zig-toolchain, the metapackage alone with
      `--no-index`, the groups and then ziglang uninstalled)
- [x] check.zig: one stop names every missing group (H a); a build tool
      installed in R's environment but not on PATH is named (I a); 0009
      tells exit 1 from 127 (J a; I-T11's third text); 0013's "older
      than this R" stop gone (C a) (step 3)
- [x] scripts/conda-consume.sh and its pkg task; build.yaml runs it on
      every conda-package leg before the publish (Cg8; steps 1 and 4)
- [x] rzig keys the zig command with `/` on Windows, for the shared
      build runner and the cfguard/dso_fini objects
      (feat-shared-build-runner open decision 1 b; step 3 and the host
      fixes: cache.command; kappa round 2: one zig spelled three ways,
      one build-runner and one cfguard directory)
- [x] verify-tree.sh on a conda env: rzig's copies compared unsigned in
      a macOS conda env (rattler-build signs each copy under its own
      name), and the binary checks read R_HOME only (conda-forge's zig
      wrappers, sysroot and ncurses failed them) (the host fixes; gamma's
      seven envs, omicron's four, kappa's two)
- [x] README (five platforms; universe public, L a; the groups and the
      one recommendation; four wheels), pixi.toml's and verify-tree.sh's
      comments (step 4)
- [x] Upgrade test from the build on the channel (`_8` on 2026-10-11;
      pixi, conda, mamba): no clobber error (2026-10-14, G a: gamma
      pixi, conda, micromamba; kappa pixi, conda; omicron pixi; no
      clobber, no `__clobbers__`, nothing left over, test-toolchain.R and
      verify-tree pass; PLAN.md's "Phase 4 record: the upgrade from
      `_8`", with what changed in the procedure)
- [x] The universe-first solve that failed on kappa (r-zig-slim `_9`,
      built locally before the 2026-10-19 decision kept 8, on win-64
      needs libcurl 8.23.0, which prefix.dev's conda-forge mirror,
      read through universe's `channel_relations`, lacked): a solve-only
      probe on gamma at 17:54 UTC with kappa's packages solved in both
      channel orders once the mirror had it; pixi.toml's and stress.R's
      comments give the reason for conda-forge first
- [x] Tested: conda-package on linux-64, omicron (osx-arm64), kappa;
      wheel-test on linux-64 and omicron (2026-10-14, both rounds)
- [ ] Tested by CI (the PR's run): the core tier with the five
      conda-package legs, each with its four package tests and
      conda-consume. osx-64 and linux-aarch64 conda-package have run on
      no host (omicron's Rosetta row was not run), and conda-consume has
      not run on GitHub's Windows runner. Then `full-ci` (wheel-test on
      the four unix minimal legs: the linux-aarch64 and osx-64 wheels
      exist nowhere else) and `upstream-zig` (the patches changed)
- [ ] CI's conda legs' times against ea7e6ee's (win-64 15.5 min; Cc11);
      they decide whether the four tests keep sharing a zig cache
      (`R_ZIG_TEST_ZIG_CACHE` as a rattler-build test secret, step 4),
      which saved no measurable time on gamma
- [ ] Optional: one stress dispatch with `distribution: conda`,
      `channel: local`, `g3 g4` on the five runners, which installs the
      PR's r-zig-slim and r-zig-toolchain (PHASE4 section 8)
- [x] ~~Just before merging: universe still holds `_8` and nothing
      newer on the five subdirs, else the number moves (B14 a)~~: no
      number to check since 2026-10-19 (phase 4 keeps 8); phase 7's
      item does it for the bump
- [x] build.yaml's publish step needs `vars.CONDA_PUBLISH == 'true'`
      (2026-10-19): without a bump, a push to main would upload the new
      r-zig-compilers, r-zig-build-tools and a new-hash r-zig-toolchain
      at `_8` beside universe's old r-zig-slim `_8`, which has no rzig
      (N5's coupling). The variable stays unset until phase 7's bump
      merges (phase 7's item)
- [ ] The user commits and opens the PR (hand over the commands, no
      trailer)
- [ ] After the publish from main, which waits for phase 7's bump and
      `CONDA_PUBLISH` (PHASE4 section 7, with that bump's number `_N`
      for `_9`): the four `_N` files on all five subdirs
      (`conda-channel-list`); a fresh env from universe only (no local
      channel, fresh caches, dist/conda removed) gets `_N` with `pixi
      add r-zig-toolchain` and passes test-toolchain.R; then the closing
      note "published as `_N`, <date>" in feat-zig-pkg-build's N5 and
      fix-zig-pkg-build-review's status (Cc19)

Taken before phase 5: R CMD SHLIB through rzig build
(feat-shlib-rzig-build, its PLAN.md), from "Later" (its open point A a,
the user, 2026-10-15).

## Phase 5 — zig in the compilers group

Needs (answered): B4; B6 (both cases are tested either way); B13 (sizes
only recorded); D6 (b). PHASE5's open points A-T: the recommended option
each (the user, 2026-10-15, "Start phase 5"; PLAN.md "Phase 5: the
user's answers"). Build number 11 (M a); since 2026-10-19 it stays 8
(the user's decision; PLAN.md's B14 amendment).

- [x] Toolchain step: fetch-zig's zig into `TC/zig/` with `LICENSES/`
      (LICENSE, dist-info licences) and `SOURCES` (wheel URL, sha256)
      (2026-10-15: build.zig and wheel.zig from fetch-zig's unpacked
      wheel, `-Dziglang`; a `file:` line per copy from the RECORD)
- [x] verify-toolchain (not verify-tree, which checks the R trees):
      `zig/` third-party in the build-path scan; `zig/zig version` is
      0.16.0; the checks in batch for 19.5k files (D a)
- [x] groups.zig (B35): the compilers standalone line names
      `R-<ver>-<plat>-compilers.tar.gz` (.zip on Windows) for zig
- [x] `-lsynchronization` with upstream zig (D6 b): done by PR #19
      (fix-rzig-follow-ups, 7a3004d), a rename to
      `api-ms-win-core-synch-l1-2-0` for both zigs; no import library is
      generated (zig builds it from the API set's `.def`); no upstream
      report. Phase 5 adds verify-bundle's Windows package test
- [x] verify-bundle scenario 2 with `ZIG_BIN` unset: RZIG_PRINT_ARGV shows
      `TC/zig/zig`; C, C++ (no shared libc++/libstdc++), OpenMP C (3
      forms), flagless omp.h probe; on Windows a `-lsynchronization`
      package builds and loads; the env-tools pass kept (the `build`
      pass)
- [ ] The mixed case (default legs) passes on every OS: by hand on
      linux-64, osx-arm64, osx-64 (omicron, Rosetta) and win-64
      (2026-10-15); linux-aarch64's comes from CI's default leg (tick
      this then). The one-zig case runs on the upstream legs only
      (linux-64, osx-arm64, win-64; 2026-10-15 by hand, CI with the
      `upstream-zig` label); per K (a) there is no upstream leg for
      linux-aarch64 or osx-64, so their one-zig case stays untested
      (open item: an upstream leg for them is a later menu)
- [x] Archive sizes recorded in PLAN.md; the first C++ compile's time
      with upstream zig measured ("Later": cache pre-seeding)
- [ ] Tested: linux-64, omicron (both), kappa, CI, upstream-zig label run
      (2026-10-15: linux-64, omicron and kappa done, then round 1 on
      both hosts after the review's fixes and round 2 on kappa after the
      host fix, all passed; CI and the label run wait for the PR, which
      the user pushes, so this stays open)
- [ ] After phase 4's and SHLIB's PRs merge: phase 5's commit
      (`phase5-only.diff`, open point O) and its PR with the `full-ci`
      and `upstream-zig` labels; record CI's run IDs, each toolchain
      leg's time and artifact size, windows-latest's toolchain step times
      (Cc7), unpack times per leg kind (Cg6) and verify-package's
      per-pass times against ea7e6ee's (Cg1) in PLAN.md
- [x] ~~Before merging: `pixi run -e pkg conda-channel-list universe
      <subdir>` still shows nothing newer than `_8` (else the number
      after universe's newest, M a); after merging, the publish of `_11`
      follows phase 4's and SHLIB's~~: no number to check since
      2026-10-19 (phase 5 keeps 8); phase 5 publishes with phase 7's
      bump (phase 7's items)

## Phase 6 — Fortran in the compilers group

Needs (answered): B9, B13 (revisit), B29 (a), B44 (every OS must pass).

Prototype first (linux-64, osx-arm64, osx-64, win-64):
- [ ] zig-fc sends every link through zig (`flang -c` per source + the
      zig link); unit tests; a real configure probing `$FC` passes in the
      standalone tree and in a conda env
- [ ] zig-fc passes `-fintrinsic-modules-path` from flang's location;
      harmless beside a conda env's flang.cfg; where the triple comes from
- [ ] rzig's runtime lookup under `TC/flang/` (Windows without
      `Library/`); the driver as the single file `flang`
- [ ] kappa: a Fortran package without `-lc++` (flang-rt-zig 10's archive
      checked first); omicron: R without linkFortranRt's `link_libcpp`
- [ ] An OS whose prototype fails: fix it with flang-pixi (flang-zig),
      then run the prototype again (B44); no OS ships without
      `TC/flang/`

Then:
- [ ] Toolchain step: the set from the env into `TC/flang/` (no
      `Library/`, no flang.cfg, no lld, the driver once, no linux
      module-directory symlink); `flang/SOURCES` from conda-meta;
      verify-tree checks against `paths_data`
- [ ] The carve script's cross-check, once
- [ ] groups.zig (B35): the compilers standalone line names the archive
      for flang too
- [ ] `-lc++` and `link_libcpp` dropped where those runs passed
- [ ] verify-bundle scenario 2, no flang on PATH, no flang.cfg: a
      derived-type module, USE_FC_TO_LINK, `use omp_lib` on two threads,
      a configure linking with `$FC`
- [ ] Compression revisited with the measured compilers archives (B13)
- [ ] Tested and passing on every OS: linux-64, omicron (both), kappa,
      CI (all five platforms)

## Phase 7 — Windows build tools: usr/bin

Needs (answered): B11, B25, B39, B43 (pkg-config).

- [ ] Choose the conda-forge package for each of B39's tools and
      pkg-config: native win-64 build first, `m2-*` where conda-forge has
      none (B11); each tool an .exe of its own name (check
      uutils-coreutils); record the choice
- [ ] Decide whether make.exe is stripped
- [ ] Toolchain step: the chosen packages' files into `TC/usr/bin/` with
      their DLL closure (msys-2.0.dll and the msys-*.dll for m2 ones),
      `usr/LICENSES/` and `usr/SOURCES` from conda-meta; verify-tree
      checks the closure
- [ ] conda's win-64 r-zig-build-tools depends on the same packages
      (replacing phase 4's interim list)
- [ ] Rprofile.windows PATH line, if the tests need it
- [ ] groups.zig (B35): Windows' build-tools standalone line names
      `R-<ver>-win-64-build-tools.zip`
- [ ] `R CMD config` without the build tools fails with one clear message
- [ ] Re-scope from feat-zig-pkg-build's stress table (its PLAN.md,
      "Consolidation with phase 3", M6: one dispatch after its push, with
      stress.yaml's `trace` and `builder` inputs): which rows need the
      group at all. `R CMD INSTALL` of tier 0 to 2 packages without a
      configure script R runs (a src/build.zig and no src/Makefile, or
      no configure, no src/Makefile and a Makevars of assignments)
      builds through rzig build with no sh or make [records-REC-6]; the
      group is for packages that need make, configure scripts R runs,
      `R CMD SHLIB` (run-time compilation, pkgbuild's probe and so pak),
      `R CMD config`'s direct callers, `R CMD check`'s objdump (Windows)
      and cleanup.ucrt/cleanup.win under `--clean` or `--preclean`
      [stress-S10]. The table (2026-10-12, run 38317654371 on 45892fb,
      five runners, `trace`, `builder = auto`; feat-zig-pkg-build's
      PLAN.md, "Stress dispatch", corrected by its review follow-up): of
      the suite's 47 rows that compile, 30 need the group on Windows: 29
      whose run_shlib goes to make (12 configure.win scripts, 9 Makevars
      rules in src/Makevars, .win or .ucrt, 5 `$(shell)`, 2
      conditionals, 1 include) [stress-S8] and Rhdf5lib, whose
      configure script builds HDF5 through CMake and make [stress-S9];
      17 go through rzig build. From the recipes and the packages'
      messages, not word counts in the logs [stress-S3]: winshlib.mk's
      silent def and link recipe runs nm, sed, basename and rm in every
      make row, the configure.win scripts sh, pkg-config at least 9
      rows, rzig's AR/RANLIB 12 and 2, cmake Rhdf5lib and RcppParallel's
      TBB (which also runs windres through RC). So: sh, make, coreutils,
      sed, pkg-config and the make path's nm stay in the group; nothing
      leaves it on the table's evidence; cmake stays the extras
      candidate
- [ ] verify-bundle scenario 3 on Windows with PATH = bin\x64 + System32:
      the contract set, pak, data.table, glue and a pkg-config package
      build and load
- [ ] The same with Rtools or Git for Windows also on PATH (msys-2.0.dll
      clash), and in a fresh conda env with r-zig-toolchain
- [ ] Tested: kappa, CI windows-latest (watch for the old spawn hangs)
- [ ] The build-number bump (PLAN.md's B14 amendment, the user's
      decision of 2026-10-19): phases 4, SHLIB routing, 5 and 6 kept 8;
      phase 7's PR takes the number after universe's newest (B14 a),
      checked just before merging (`pixi run -e pkg conda-channel-list
      universe <subdir>` on the five subdirs), with one history entry
      for phases 4 to 7
- [ ] Set CONDA_PUBLISH=true (`gh variable set CONDA_PUBLISH --body
      true`) after phase 7's bump merges, then publish (that push's run
      once the variable is set, or `pixi run ci-trigger`) and run phase
      4's post-publish check with the new number

## Phase 8 — the base's runtime files

Needs (answered): B27, B33.

- [ ] unix: CA bundle at `<top>/ssl/cacert.pem`; Renviron's
      `R_ZIG_CA_BUNDLE`, make-wheel.py's check (368-371) follow
- [ ] Windows: fontconfig at `<top>/Library/etc/fonts`; `FONTCONFIG_PATH`
      moves to a place R reads under `--vanilla`
- [ ] `<env dir>/share/licenses/<package>/` and `SOURCES` for every
      vendored package; the wheel's dist-info/licenses the same;
      verify-tree requires an entry for every vendored file
- [ ] verify-bundle scenario 1 on every OS: TLS, an svg device with
      fonts (Windows also under `--vanilla`), tcltk (full, Windows);
      wheel-test's TLS check
- [ ] Tested: linux-64, omicron (both), kappa, CI

## Phase 9 — finish

Needs (answered): B14 (a), with B37 (a).

- [ ] Build number per B14 (a): a bump only if a package changed since
      the last bump; conda-package on all five platforms.
      feat-zig-pkg-build's PR changes r-zig-slim (patches 0009, 0012,
      0013, share/zig/rpkg) and r-zig-toolchain (rzig's new modes and
      name) and bumps nothing (its N5, 2026-10-12): the bump that
      publishes phase 4 publishes both, together (phase 4's item says
      why); since 2026-10-19 that is phase 7's bump, not a 9 in phase 4
- [ ] feat-no-host-paths PLAN.md: What remains 3 points here; the T
      record and the OpenMP note (467-470) updated
- [ ] This PLAN.md: status and records with dates and test results
- [ ] upstream-zig label run green
- [ ] Last round: linux-64, omicron (osx-arm64, osx-64), kappa, CI all
      green; hand the commit and PR commands to the user

## Later / future checks

- [ ] build.zig fills CC_VER/FC_VER from the zig and flang that build R,
      on every OS, as it fills Windows' COMPILED_BY (compiledBy): the
      vendored strings in zigbuild/config drift with every rebuild of
      conda-forge's zig or of the libclang-cpp21.1 it loads, and phase
      4's linux packages already show it (phase 4's D7 item; PHASE4 risk 7)
      [conda-d7-cc-ver-stale]
- [ ] Which full-only features can become add-on R components (tcltk
      first); drop the separate full build only if readline/NLS can be
      settled
- [ ] Make Windows slim really slim (B42, the user's note of 2026-10-08;
      relates to C1, Windows minimal); until then it has full's content
- [ ] Depend less on make for package installs (Windows needs sh/make
      for now): done for `R CMD INSTALL` of tier 0 to 2 packages by
      feat-zig-pkg-build (rzig build; its PLAN.md, "What the build-tools
      group is for"). R CMD SHLIB is done by feat-shlib-rzig-build
      (its PLAN.md; it publishes with phase 7's bump): run-time
      compiles, pkgbuild's has_compiler probe and so pak need no make
      where the code needs none. Left:
      `R CMD config` through rzig (unix src/scripts/config; Windows with
      phase 7's rcmdfn.c). That would serve rstan on macOS, which runs
      `R CMD config CXX17` after each `stan_model()` compile, and
      pkgbuild's Windows `has_rtools()`, which warns "Rtools is
      required" on base + compilers (feat-shlib-rzig-build's open point
      H), and would also free the `R CMD config` run before a configure
      script for tier 0 and 2 packages on unix (feat-zig-pkg-build fact
      3). The shared
      tier-1 build runner is done by feat-shared-build-runner's PR (its
      PLAN.md) [stress-S1, records-REC-4, phase3-P3-8]: stress dispatch
      38467907779 (`shared_cache = false`, main ea7e6ee) measured the
      per-install runner at +3.3 s (ubuntu-latest), +11.1 s
      (ubuntu-24.04-arm), +9.6 s (macos-latest), +11.9 s
      (macos-15-intel) and +12.8 s (windows-latest) per tier-1 install,
      where make installs a small package in 1 to 2 s; rzig build now
      keeps one runner per content of R's build_t1.zig and zig in rzig's
      cache, `build-runner-<key>/`, and removes one no install has used
      for a week (pkgbuild.zig's `zigBuildDirs` and `sharedRunner`); each
      install's objects and library stay in its build root. With the
      runner warm, a small tier-1 package installs within 0.2 s of make
      on linux-64 and osx-arm64 and 0.4 to 0.8 s faster on win-64 (its
      PLAN.md, "Measurements"). verify-bundle
      scenario 2's new assertions (the tier-1 install with the compilers
      alone, the Makevars-rule stop; on unix also the configure-only and
      no-flang stops; Windows since the review follow-up
      [phase3-P3-9]) are the gate for the group's scope
- [x] A stress dispatch of g3 g4 with trace and `shared_cache = false`
      on main after feat-shared-build-runner merges: rzig build's
      default cache, as a user's install has it, should bring the small
      tier-1 rows back to about 38317654371's shared-cache times on the
      five runners, the first tier-1 row of each leg carrying the one
      runner compile (feat-shared-build-runner's PLAN.md, "CI"). Done:
      run 38569895172 on main d11dee1 (2026-10-14) passed on the five
      runners with no unexpected row, one build-runner directory per
      leg; the small tier-1 rows' means were 1.3, 1.2, 1.8, 4.8 and
      2.6 s (ubuntu-latest, ubuntu-24.04-arm, macos-latest,
      macos-15-intel, windows-latest), against 1.1, 1.2, 2.2, 5.4 and
      1.6 s shared and 4.4, 12.3, 11.9, 17.2 and 14.4 s per install: the
      shared runner brings tier-1 installs back to the shared-cache
      times on every CI runner, the runner compile paid once per runner
      per leg
- [ ] A stress dispatch of g1 with trace (Rcpp's cppFunction, rstan's
      stan_model): run-time compilation, `R CMD SHLIB`, which the g3 g4
      dispatch of 2026-10-12 did not exercise (no smoke compiled)
      [stress-S6, records-REC-9]. The smoke's result is the evidence, not
      a trace line: R CMD SHLIB went through make then, and sourceCpp keeps
      its output (a local Rcpp run, 2026-10-13). Now feat-shlib-rzig-build's
      dispatch (its open point J a): g1 and g2 (RcppArmadillo's and
      RcppParallel's configure scripts run SHLIB) with trace on its
      branch, Rcpp's smoke with `showOutput = TRUE`, so its log carries
      `rzig build: R CMD SHLIB, tier 1`; ticked with that run
- [ ] pkgbuild's Windows `has_rtools()` on base + compilers
      (feat-shlib-rzig-build's open point H, (a): no change to 0010 now,
      the README says Rtools is not needed and the warning can be
      ignored). Seen on kappa, 2026-10-15: with no sh, `R CMD config CC`
      says "'sh' is not recognized" and exits 1, so pkgbuild's
      `cc_path` is empty; `has_rtools()` answered TRUE there only from
      stale registry entries for Rtools 4.4 and 4.5, while
      `has_compiler()` and `check_build_tools()` were TRUE through rzig
      build. Clears with `R CMD config` through rzig (the item above)
- [ ] TMB's precompile across model names (feat-shlib-rzig-build's open
      point D): under rzig build each new model name compiles libTMB.cpp
      again (about 45 s and 4 MB of zig cache on linux-64), where make
      reused one libTMB.o; only if users ask
- [ ] The build root of R CMD INSTALL's package mode under
      `R_SESSION_TMPDIR` too, as SHLIB mode's (feat-shlib-rzig-build's
      open point M c), if a killed install's `src/.rzig` is seen
- [ ] macOS `zig cc --version` writes an empty `a.o` in the working
      directory (conda-forge's zig and upstream 0.16.0): rzig's driver
      adds `-c` to a version query (compiler.zig; feat-shlib-rzig-build's
      "Host fixes, round 1"). Drop it when a zig writes none; no upstream
      report (L)
- [ ] Tier 2's own compile flags: an optional `cflags` in rpkg's
      LibraryOptions, appended to each C/C++ source's flags, when a zig
      package needs its own include paths or defines (tier 2 does not
      read src/Makevars; fix-zig-pkg-build-review's PLAN.md, code-4)
- [ ] Optional extras group, only when the stress suite shows a need
      (the suite starts now, D15 a)
- [ ] After the stress suite: reassess B39's list and B43's pkg-config
      and objdump, and whether a gcc-nm from conda-forge is really
      needed (B43-2) (what is really needed, what zig cc/rzig
      already covers)
- [ ] The rest of the Windows binutils through rzig as zig gains them
      (B24); LLVM's tools are the other way out of GPL-3 binaries
- [ ] GNU make built with zig (B7 b)
- [ ] The release job (B12): `v*` tags, GitHub Release, GPL sources
      mirrored
- [ ] The four PyPI names (r-zig, r-zig-compilers, r-zig-build-tools,
      r-zig-toolchain), all free on 2026-10-13: reserve or publish them
      with B12's wheel publishing; until then the README and wheel-test
      install the group wheels with `--no-index` (PHASE4 Cc14)
- [ ] The toolchain in an environment of its own (feat-no-host-paths
      item 4; D14 a)
- [ ] Windows minimal and the Windows wheel (C1-C3 a), after phase 7
- [ ] zig's global cache: after phase 5's measurement, put pre-seeding
      to the user as a menu (measured 2026-10-15, PLAN.md "Phase 5
      record: the measurements"); in the same menu, two zigs sharing
      zig's default cache on a user's machine, a standalone R's and a
      conda R's (PHASE5 open point N a)
- [ ] Menu: the groups' licence completeness, zig/ now and flang/ in
      phase 6 (LLVM's attribution, Apple's SDK headers and libSystem.tbd,
      the NetBSD and OpenBSD headers), with phase 6's licence review; B33
      covers only the base's runtime files (PHASE5 Cc5, Cg2)
- [ ] Menu: leave zig/ out of the legs that never read it (build-r's
      build-only legs, stress, the local dev chains), with phase 5's
      unpack timings (Cg6)
- [ ] Menu: upstream-zig.yaml reuses build.yaml's toolchain artifact,
      which carries the same TC/zig since phase 5 (Cg9)
- [ ] Menu: verify-package's build pass: keep, reduce to the package
      blocks (PHASE5 F b), or run it only under full-ci, with CI's
      per-pass times (Cg1)
- [ ] Menu: the one-zig case (TC/zig is the build's zig) on
      linux-aarch64 and osx-64, which no CI leg runs: upstream-zig.yaml
      has ubuntu-latest, macos-latest and windows-latest only, and PHASE5
      K (a) took no upstream osx-64 leg; their mixed case is covered
      (omicron's osx-64 by hand, CI's default legs)
- [ ] Menu: `compression-level: 0` on toolchain.yaml's upload (the
      archives are already compressed), with windows-latest's step times
      (PHASE5 T a, Cc7)
- [ ] Windows: Rust static libraries built for the r-windows clang
      bundles (gifski's prebuilt one) need an unwinder in a C link
      through gcc.exe: 9 undefined `_Unwind_*`/`_GCC_specific_handler`
      with both zigs; `SHLIB_LIBADD = -lunwind` fixes it (kappa,
      2026-10-15, phase 5 step 3b). Options when it comes back: a
      windows.zig rule adding `-lunwind` to image links through gcc.exe,
      or leave it to packages
- [ ] Windows `-lmsvcrt` with upstream zig (PHASE5 open point L a): map
      `msvcrt` in `mingw_names` only if a real package needs it (magick
      and gifski did not reach it, 2026-10-15)
- [ ] package-standalone.sh's "== done:" size is `du -h`'s, the blocks
      used (97M on APFS, 45M on gamma's compressed filesystem, for an
      87-88 MB compilers archive): print the byte size instead, as
      verify-bundle's cache size does (phase 5, 2026-10-15)
- [ ] macOS without the Command Line Tools: observe a Mac that never had
      them, then put rzig's `xcrun` handling to the user as a menu

## History: phases 0 and 1 (done, recorded in 9bbce0b, #15; verbatim from 9bbce0b)

The two sections below are copied unchanged. Their decision numbers
are the old ones (PLAN.md, "Old decisions and their status"). Phase 1's
open boxes are still open: omicron and kappa have not run
conda-package, and on #15 CI's osx-64 and win-64 conda-package jobs and
the seven macOS and Windows build legs failed at `pixi install` (a 404
on deleted flang builds, confirmed in the job logs).

## Phase 0 — measurements (no code changes)

Done 2026-10-06. The details and the method are in PLAN.md, "Phase 0
measurements".

The trees, all existing ones read in place:
- linux-64: the main checkout's dist/ (2026-10-02/03);
- osx-arm64: omicron's ~/r-zig-pixi/dist (2026-10-04, 4868515's
  sources, pixi.lock f743e74f…);
- win-64: kappa's dist (the same sources and lock);
- osx-64 and linux-aarch64: no tree exists, so build 4's
  r-zig-toolchain packages stand in.

Downloads and tools came from pixi.lock e9f17d31…9513.

- [x] omicron: `lib/R/bin/toolchain` of the osx-arm64 trees.
      - slim and full: rzig ×5 at 306,416 B, 1,532,080 B raw, 591,854
        gzip -6.
      - minimal: the same plus make (267,120 B), 1,799,200 B raw,
        708,972 gzip -6.
      - linux-64 for comparison: slim 2,036,800 B raw (rzig 407,360);
        minimal 2,350,456 B (make 313,656).
      - `strings` of minimal's make, which is pixi.lock's package file
        byte for byte: macOS names
        `/Users/runner/miniforge3/conda-bld/make_<ts>/_h_env_placehold…/include|lib`;
        linux names `/home/conda/feedstock_root/…/_h_env_placehold…/include|lib|share/locale`.
      - These are dead compiled-in defaults, since the package records
        no prefix placeholder. None names our build machine.
- [x] kappa: `Library/lib/R/bin/toolchain` of the win-64 tree.
      - rzig ×5 at 746,496 B and the 8 binutils at 13,642,752 B
        together: 17,375,232 B raw, 7,394,501 B zip -6.
      - The binutils equal build 4's.
      - R.dll imports zstd.dll itself (`objdump -p`), and so do tiff.dll
        and all the binutils. zstd.dll stays in base.
- [x] rzig's sha256 across flavors: identical.
      - linux-64 slim = minimal (b4320d5e…; no full tree on linux).
      - osx-arm64 slim = full = minimal (fe70b0ec…).
      - win-64: one flavor, five equal copies.
      - Conda's macOS packages differ per copy: rattler-build re-signs
        each copy under its own name.
- [x] Every OS: upstream zig plus make, as they would sit in
      bin/toolchain. Shown as gzip -6 / xz -6 / zstd -19, with rzig and
      zig's licence texts included:
      - linux-64: 87.5 / 57.6 / 61.6 MB;
      - linux-aarch64: 84.5 / 53.1 / 59.3 MB;
      - osx-arm64: 86.6 / 54.2 / 60.1 MB;
      - osx-64: 90.7 / 59.8 / 63.5 MB;
      - win-64 (binutils, no make): 94.7 / 60.3 / 64.3 MB, zip -6
        106.8 MB.
      - zig alone on linux-64: 86.6 / 57.4 / 61.3 MB.
      - make alone: 0.12-0.17 MB gzip on unix. win-64's make.exe is
        17.1 MB unstripped (4.8 MB gzip), 288 KB stripped.
- [x] flang's set: sizes per subdir measured by flang-pixi (docs/19 §2,
      2026-10-06); not repeated
- [x] omicron: `xcrun --sdk macosx --show-sdk-path` without the Command
      Line Tools. The real state is untested: omicron has the CLT (26.4)
      and removing them is not safe. Simulated instead with an empty
      DEVELOPER_DIR:
      - xcrun exits 1 at once, with empty stdout and "invalid
        DEVELOPER_DIR path" on stderr;
      - rzig drops the SDK's `-F`/`-L` silently;
      - plain C compiles, links and runs;
      - `-framework CoreFoundation` fails ("unable to find framework").
      - The install dialog could not be observed.

## Phase 1 — recipe host which/sed/grep cleanup

PLAN.md's "Phase 1 record" (under Design 11) has the details.

- [x] recipe.yaml: delete the `if: unix` host entries which/sed/grep
      (lines 224-228) and their comment (196-223)
- [x] build.zig mkRbase: delete the `@WHICH@` substitution (3416-3422)
- [x] verify-tree.sh: correct the "nm/realpath/sed/... for bin/libtool
      and javareconf" comment (455-461) to what bin/toolchain holds
- [x] feat-no-host-paths PLAN.md: correct "Vendored in the standalone
      tree today" (321-324)
- [ ] `pixi run -e pkg conda-package` passes on linux-64, osx-arm64,
      osx-64 (omicron) and win-64 (kappa), both packages' tests included
      (linux-64 passed 2026-10-06; omicron and kappa not run)
- [x] File lists of r-zig-slim and r-zig-toolchain equal build 4's; etc/
      and base's R code equal build 4's; no `/bin/which`, `/bin/sed`,
      `/bin/grep` in either package (linux-64, 2026-10-06. Besides the
      file lists: the toolchain is byte-identical, and slim differs
      only in build directories, dates and conda-forge's newer
      harfbuzz run-export floor)
- [x] Optional: drop `which` from the staging build requirements; the
      same conda-package runs pass (dropped: an execve trace of the
      linux-64 run shows nothing running `which`; the macOS runs above
      still have to pass)
- [ ] CI: the five conda-package jobs green
