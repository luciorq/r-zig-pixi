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
      a package
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
- [x] D7 = (a): CC_VER/FC_VER refreshed with phase 4's bump
- [x] D12 = (a): rattler-build >= 0.76 with warnings as errors
      (feat-no-host-paths' proposed follow-up PR (i), or phase 4)
- [x] D14 = (a): the toolchain in its own env stays later
- [x] D15 = (a): the stress suite starts now, in parallel; it decides
      the extras and reassesses B39 and B43
- [x] E2 = (a): zstd declared with phase 4's bump (r-zig-slim; win-64
      r-zig-build-tools)
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
- [ ] CI; then the user commits (hand over the commands)

## Phase 3 — the standalone layout, today's contents

Needs (answered): B7, B12, B13, B17, B23, B24, B25, B26, B30, B31, B36,
B38, B42, B43.

- [ ] env.sh: platform name once; prefixes `dist/<flavor>/R-<ver>-zig`
      and `dist/toolchain/R-<ver>-zig` (replacing env.sh:29's PREFIX);
      the seven scripts (zig-build, zig-package, zig-verify-package,
      zig-smoke, zig-contract, verify-tree, hermetic-check) read them;
      make-wheel.py:350 derives the same prefix
- [ ] build.zig toolchain step (pixi task `toolchain`), each directory
      with `LICENSES/` and `SOURCES`: `openmp/` (moved out of the base),
      unix `usr/bin/make` (moved out of minimal's tree), Windows
      `binutils/`: nm, dlltool, as, strip, windres (moved out of
      installWindowsCompilerContract) and objdump (new, from
      binutils_impl_win-64; check it ships it); ar, ranlib and ld.exe
      dropped
- [ ] The base's TC holds only rzig; Windows adds `zig-ar.exe`,
      `zig-ranlib.exe`, `gcc-ar.exe`, `gcc-ranlib.exe` and drops `zig-cc`
      and `zig-cxx`; verify-tree.sh's rzig names (76) follow
- [ ] rzig routing check (B24): dlltool (zig dlltool, GNU long options
      and `--as`), windres (zig rc behind a windres-syntax front), strip
      (zig objcopy), nm and as (none in zig 0.16.0); move each one that
      passes, here or in a follow-up PR; record the result in PLAN.md
- [ ] unix etc/Renviron: `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`,
      `MAKE=${MAKE-'make'}` for every flavor (minimal's `R_ZIG_MAKE` goes)
- [ ] Windows etc/Rcmd_environ:
      `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`
- [ ] Makeconf.win: AR (103) `$(BINPREF)zig-ar`, RANLIB (213)
      `$(BINPREF)zig-ranlib`; LTO gcc-ar/gcc-ranlib (267, 269) unchanged
      (now rzig); NM (78, 204) → `binutils/nm.exe`; LTO gcc-nm (268)
      unchanged (B43-2); DLLTOOL (76), RESCOMP (79), OBJDUMP (211),
      STRIP_* (251-252) → `binutils/` (or rzig for moved tools);
      PKG_CONFIG (75) bare `pkg-config` (found in `TC/usr/bin` on PATH,
      like sed; conda's is in `Library/bin`); BINPREF for gcc/g++ and
      rzig's names
- [ ] Windows slim documented (B42 a): README and the recipe's summaries
      say Windows slim has full's content
- [ ] vendor-libs.sh: Windows libomp.dll trigger on R's OpenMP setting
- [ ] Patches 0009 and 0010 call the check mode (compilers and build
      tools); 0009's fallback removed; 0010's `command -v` replaced
- [ ] groups.zig (B35): unix's build-tools standalone line names
      `R-<ver>-<plat>-build-tools.tar.gz`; decide where the preflight
      shows a user's R_ZIG_TOOLCHAIN_HINT (rzig does not read it)
- [ ] Check mode lines on Windows, before the preflight shows them: one
      path separator (find_zig joins with `\`, rzig's own path has `/`);
      a zig that cannot start says so, not "does not say its zig version"
- [ ] package-standalone.sh: base archive + compilers + build-tools
      archives, `.sha256` each
- [ ] hermetic-check.sh: the R tree is the base, nothing deleted
- [ ] verify-tree.sh: base TC = rzig only; toolchain tree records,
      closures (OS, own directory, base runtime), glibc 2.28 ceiling
- [ ] verify-bundle.sh: the three scenarios (scenario 2 takes zig from
      `ZIG_BIN=$ZIG` and flang from the env until phases 5 and 6; Windows
      scenario 3 takes sh/make from the env until phase 7); file-list
      check
- [ ] conda: build.sh runs the toolchain step into `$PREFIX` (Windows
      binutils); packages unchanged until phase 4, no bump
- [ ] make-wheel.py: make from the toolchain tree; wheel-test checks
      `Sys.which("make")`
- [ ] CI: `toolchain` job per subdir in build.yaml; the `build` job (all
      legs) `needs:` it; packaging legs download their groups, run the
      scenarios, upload base and group archives (short retention);
      upstream-zig.yaml gets its own toolchain job
- [ ] kappa and windows-latest: a static-library package through
      `$(AR)`/`$(RANLIB)` (rzig), an `--use-LTO` build, and the packages
      that use each tool the routing check moved
- [ ] Tested: linux-64 (slim, minimal, wheel, conda-package), omicron
      (osx-arm64 slim and minimal, osx-64 slim), kappa, CI

## Phase 4 — conda and PyPI on the same boundary

Needs (answered): B14, B28, B29, B35, B38, B39, B11, B41; D7, D12, E2.

- [ ] Check: rattler-build 0.76.1 makes outputs with no files that do not
      inherit the staging build
- [ ] rattler-build >= 0.76 with warnings as errors (D12), if
      feat-no-host-paths' follow-up PR (i) has not done it
- [ ] recipe.yaml: r-zig-slim excludes only
      `lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` (and
      `Library/...`); r-zig-compilers, r-zig-build-tools, r-zig-toolchain
      metapackage; build number 5 → 6 here (B14 a)
- [ ] win-64 r-zig-build-tools: B41's binutils copies (nm, dlltool, as,
      strip, windres, objdump, less any tool moved to rzig); run
      dependencies on conda-forge packages for B39's list and pkg-config
      (today's m2 list plus pkg-config until phase 7 chooses)
- [ ] zstd declared (E2): r-zig-slim and win-64 r-zig-build-tools
- [ ] CC_VER/FC_VER refreshed with this bump (D7)
- [ ] Hint writers removed: `-Dtoolchain-hint`, zig-build.sh:57-66,
      make-wheel.py's renviron_hint
- [ ] groups.zig (B35): the conda and pip lines name r-zig-compilers and
      r-zig-build-tools
- [ ] make-wheel.py: r-zig with rzig; r-zig-build-tools with
      `usr/bin/make`; r-zig-compilers and r-zig-toolchain without files;
      one tag set; the zig-cc check moves to the base wheel
- [ ] test-preflight.R: rzig present, no zig, preflight names
      r-zig-compilers
- [ ] wheel-test.sh: the three scenarios with pip; uninstalling the
      groups leaves R whole
- [ ] Upgrade test from `_5` (pixi, conda, mamba): no clobber error
- [ ] Tested: conda-package on linux-64, omicron (both), kappa, CI;
      wheel-test on linux-64 and CI

## Phase 5 — zig in the compilers group

Needs (answered): B4; B6 (both cases are tested either way); B13 (sizes
only recorded); D6 (b).

- [ ] Toolchain step: fetch-zig's zig into `TC/zig/` with `LICENSES/`
      (LICENSE, dist-info licences) and `SOURCES` (wheel URL, sha256)
- [ ] verify-tree: `zig/` third-party in the build-path scan;
      `zig/zig version` is 0.16.0
- [ ] groups.zig (B35): the compilers standalone line names
      `R-<ver>-<plat>-compilers.tar.gz` (.zip on Windows) for zig
- [ ] rzig provides `-lsynchronization`'s import library when the zig it
      runs has none (D6 b; e.g. from MinGW's `.def` with zig's dlltool),
      unless feat-no-host-paths' rzig follow-up PR (ii) has landed it; no
      upstream report
- [ ] verify-bundle scenario 2 with `ZIG_BIN` unset: RZIG_PRINT_ARGV shows
      `TC/zig/zig`; C, C++ (no shared libc++/libstdc++), OpenMP C (3
      forms), flagless omp.h probe; on Windows a `-lsynchronization`
      package builds and loads; the env-tools pass kept
- [ ] The mixed case (default legs) and the one-zig case (upstream legs)
      pass on every OS
- [ ] Archive sizes recorded in PLAN.md; the first C++ compile's time
      with upstream zig measured ("Later": cache pre-seeding)
- [ ] Tested: linux-64, omicron (both), kappa, CI, upstream-zig label run

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
- [ ] verify-bundle scenario 3 on Windows with PATH = bin\x64 + System32:
      the contract set, pak, data.table, glue and a pkg-config package
      build and load
- [ ] The same with Rtools or Git for Windows also on PATH (msys-2.0.dll
      clash), and in a fresh conda env with r-zig-toolchain
- [ ] Tested: kappa, CI windows-latest (watch for the old spawn hangs)

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
      the last bump; conda-package on all five platforms
- [ ] feat-no-host-paths PLAN.md: What remains 3 points here; the T
      record and the OpenMP note (467-470) updated
- [ ] installOpenMP's comment updated to B22
- [ ] This PLAN.md: status and records with dates and test results
- [ ] upstream-zig label run green
- [ ] Last round: linux-64, omicron (osx-arm64, osx-64), kappa, CI all
      green; hand the commit and PR commands to the user

## Later / future checks

- [ ] Which full-only features can become add-on R components (tcltk
      first); drop the separate full build only if readline/NLS can be
      settled
- [ ] Make Windows slim really slim (B42, the user's note of 2026-10-08;
      relates to C1, Windows minimal); until then it has full's content
- [ ] Depend less on make for package installs (Windows needs sh/make
      for now)
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
- [ ] The toolchain in an environment of its own (feat-no-host-paths
      item 4; D14 a)
- [ ] Windows minimal and the Windows wheel (C1-C3 a), after phase 7
- [ ] zig's global cache: after phase 5's measurement, put pre-seeding
      to the user as a menu
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
