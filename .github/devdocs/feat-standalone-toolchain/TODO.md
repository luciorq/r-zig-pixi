# TODO — feat-standalone-toolchain

PLAN.md (same directory) has the layered model, the facts, the options
and the reasons; the IDs below are its decision IDs (B1-B44).

**Implementation is on hold until the user has answered the open
decisions below.** The re-lock PR, #14 and #15 continue as planned.

Every phase: implement in a worktree, review, test on linux-64 here,
omicron (osx-arm64, osx-64 under Rosetta) and kappa (win-64), then CI.
From phase 3 on, every phase runs verify-bundle's three scenarios (base
alone; base + compilers; base + compilers + build-tools) on every OS.
The user makes the commits (hand over the commands); docs-only commits
get `[skip ci]`.

## Decisions the user makes first

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

Open. Reply e.g. "all recommended" or "all recommended except B27c
B36b". B6 and B18 block none of phases 2-9. B11 comes back after phase
7's prototype; B44 only if phase 6's prototype fails on an OS.
- [ ] B4 zig's artifact for the standalone compilers group: (a) PyPI
      ziglang wheel as fetch-zig.sh pins it; (b) ziglang.org via a
      mirror with minisign. Rec. (a)
- [ ] B6 zig that builds the released standalone R: (a) upstream, once a
      release job exists; (b) conda-forge's. Rec. (a)
- [ ] B7 unix make's source: (a) conda-forge's 4.4.1 from the build env;
      (b) GNU make built with zig. Rec. (a)
- [ ] B9 flang's compile set: (a) copied from the build env, SOURCES
      from conda-meta; (b) flang-pixi's carve script on the .conda files.
      Rec. (a)
- [ ] B11 source of Windows' usr/bin tools: (a) prototype busybox-w32 +
      make vs MSYS2 on kappa, ship the winner in `usr/bin/`; (b) MSYS2
      now; (c) require Rtools45. Rec. (a)
- [ ] B12 publishing: (a) CI artifacts now, release job later; (b)
      release job now. Rec. (a)
- [ ] B13 compression: (a) gzip/zip now, measure after phase 6 and
      choose for any compilers archive above 150 MB; (b) xz for
      compilers now; (c) zstd for compilers now. Rec. (a)
- [ ] B14 conda build number: (a) bump in phase 4's PR (required) and in
      each later PR that changes a package, none in phases 2-3; (b) one
      bump 5 → 6 at the end. Rec. as B37: (a)
- [ ] B17 names: (a) base `R-<ver>-<flavor>-<plat>`, groups
      `R-<ver>-<plat>-<group>`; (b) wait for v3 naming; (c) groups named
      by their contents. Rec. (a)
- [ ] B18 zig 0.17 wave: (a) upstream leads on the gated legs (fetch-zig
      0.17 pin once PyPI has all five wheels), conda waits for
      conda-forge's main label; (b) conda build on a pinned upstream zig.
      Rec. (a)
- [ ] B23 unix make: (a) `TC/usr/bin/make`; (b) `TC/make/make`. Rec. (a)
- [ ] B24 Windows binutils: (a) conda-forge's in `binutils/`, Makeconf
      names each, ld.exe dropped; (b) zig's tools + an nm; (c) LLVM's
      tools in `binutils/`. Rec. (a)
- [ ] B25 build tools on PATH: (a) R puts `TC/usr/bin` first (unix
      etc/Renviron, Windows Rcmd_environ), MAKE stays `make`; (b) absolute
      MAKE on unix; (c) an rzig make applet. Rec. (a)
- [ ] B26 a missing group: (a) rzig's check mode for every group (zig,
      flang, make/sh), called by patches 0009 and 0010; (b) check mode
      for compilers, R checks make itself; (c) file tests in R; (d) no
      preflight. Rec. (a)
- [ ] B27 runtime places: (a) conda's prefix paths (CA bundle to
      `<top>/ssl/cacert.pem`, Windows fonts to `<top>/Library/etc/fonts`
      with FONTCONFIG_PATH read under `--vanilla`); (b) today's places,
      recorded only; (c) a dedicated runtime root. Rec. (a)
- [ ] B28 conda: (a) r-zig-slim + r-zig-compilers + r-zig-build-tools +
      r-zig-toolchain metapackage, one recipe; (b) one r-zig-toolchain;
      (c) group packages in their own recipe. Rec. (a)
- [ ] B29 PyPI: (a) r-zig + r-zig-compilers + r-zig-build-tools +
      r-zig-toolchain, no Fortran; (b) plus r-zig-flang; (c) extras on
      r-zig. Rec. (a)
- [ ] B30 assembly: (a) a toolchain tree per platform, R trees hold the
      base only; (b) every R tree installs every group; (c) added at
      packaging. Rec. (a)
- [ ] B31 CI: (a) a `toolchain` job per subdir, the `build` job needs it,
      packaging legs run the three scenarios, upstream-zig.yaml gets its
      own; (b) also package full and openblas; (c) no toolchain job.
      Rec. (a)
- [ ] B32 zig version check: (a) the check mode fails on a major.minor
      different from R's; (b) it warns; (c) no check. Rec. (a)
- [ ] B33 base runtime licences: (a) in this plan (phase 8); (b) later.
      Rec. (a)
- [ ] B34 B2 refinement: (a) also R's own environment's `bin/`, after
      `zig/` (`flang/`) and before PATH; (b) keep B2 as answered. Rec. (a)
- [ ] B35 missing-group text: (a) one text built into rzig, the same on
      every channel; (b) a per-channel hint variable. Rec. (a)
- [ ] B36 top directory: (a) `R-<ver>-zig/`, dev trees under
      `dist/<flavor>/` and `dist/toolchain/`; (b) the same, renamed at
      packaging; (c) `r-zig/`. Rec. (a)
- [ ] B37 landing: (a) #15 merges with phases 0-1 and these docs, then
      one PR per phase; (b) phases 2-9 on #15; (c) one new PR for phases
      2-9. Rec. (a)
- [ ] B38 group names: (a) compilers, build-tools; (b) compilers, tools;
      (c) compilers, minimal. Rec. (a)
- [ ] B39 Windows usr/bin list: (a) sh, make, coreutils, sed, grep, gawk,
      which, findutils (what conda proved); (b) sh, make, coreutils only;
      (c) (a) plus pkg-config. Rec. (a)
- [ ] B40 OpenMP availability: (a) only when the base has the libomp
      runtime; (b) a per-flavor Renviron variable; (c) no rule. Rec. (a)
- [ ] B41 conda exceptions: (a) accept omp.h with the base and the win-64
      binutils copies, recorded; (b) rzig gates conda OpenMP on
      r-zig-compilers; (c) win-64 binutils from a conda dependency.
      Rec. (a)
- [ ] B42 Windows flavor name: (a) slim on every channel, documented;
      (b) full for the standalone archive only; (c) full everywhere.
      Rec. (a)
- [ ] B43 Makeconf.win's unshipped tools (pkg-config, objdump, gcc-ar/nm/
      ranlib): (a) bare names; (b) unchanged, files under TC that do not
      exist. Rec. (b)
- [ ] B44 Fortran on an OS whose phase 6 prototype fails: (a) that OS
      ships without `flang/`; (b) no OS ships `flang/` until all pass.
      Rec. (a)

Still pending from the 2026-10-07 menu and touching this plan (PLAN.md,
"Related items"): D6, D7, D12, D14, D15, C1-C3, E2, R1.

## Outside this plan (continue as planned)

- [ ] The re-lock (chore-relock-flang-rt-10) merged, before #14's bump
      publishes, so that build 5 carries the exact flang pins
- [ ] #14 (fix-rzig-baseline-cpu) merged: `-mcpu=baseline`, build 5;
      needed at the latest before phase 5 ships compilers to Windows
- [ ] #15: phase 1's remaining checks pass after the re-lock (History)

## The zig 0.17 wave (B18; not a phase of this plan)

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
- [ ] Before our pins move to flang-rt-zig 11 (a 0.17 build): nm its
      runtime archive on every subdir for symbols our zig 0.16 lacks, link
      each with zig 0.16, build R and a Fortran package on kappa
- [ ] With B18 settled: the port of build.zig and rzig to 0.17
      (`b.install_prefix`, `b.pathFromRoot`, configure caching) and
      zig-build.sh's argument order, behind a 0.16/0.17 switch, on the
      linux and macOS upstream-zig legs; fetch-zig.sh gets a 0.17 pin
      once PyPI has all five ziglang 0.17.0 wheels (win-64 stays on 0.16
      until then)

## Phase 2 — rzig knows the groups

Needs: B26, B32, B34, B35, B38, B40; B37 (the branch).

- [ ] find_zig.zig: `ZIG_BIN`, `<rzig dir>/zig/zig` (`zig.exe`), PATH,
      `python3 -m ziglang`; only with B34 = a, `<env dir>/bin/zig`
      (Windows `x86_64-w64-mingw32-zig.exe`) between `zig/` and PATH;
      B35's text and exit 127 when the python3 fallback cannot start or
      has no ziglang
- [ ] flang_rt.flang(): `<rzig dir>/flang/bin/flang`, PATH; only with
      B34 = a, `<env dir>/bin/flang` between them; fortran.zig's no-flang
      text becomes B35's; its unit test and wheel-test.sh:149-168 follow
- [ ] OpenMP (B40): `<rzig dir>/openmp/include` on every compile
      (`-idirafter` on Windows), `-L <rzig dir>/openmp/lib` on Windows,
      only when B40's rule holds; `-lomp` rule counts `openmp/`
- [ ] Check mode (B26 a): the compile lookup (`fortran` also flang), the
      build-tools check (make; Windows also sh), the zig and its
      version, B32's major.minor check
- [ ] build.zig passes R's version and the platform name to rzig
- [ ] Unit tests: each lookup step, "zig/ wins over PATH", the env-bin
      step (with B34 = a), missing zig and flang, the openmp rule with
      and without libomp, the check mode's exit codes and texts
- [ ] `pixi run rzig-test` on linux-64, osx-arm64, osx-64, win-64
- [ ] conda test-toolchain.R and wheel-test.sh unchanged in behaviour;
      verify-bundle as today

## Phase 3 — the standalone layout, today's contents

Needs: B7, B12, B13, B17, B23, B24, B25, B26, B30, B31, B36, B38, B42,
B43.

- [ ] env.sh: platform name once; prefixes `dist/<flavor>/R-<ver>-zig`
      and `dist/toolchain/R-<ver>-zig` (replacing env.sh:29's PREFIX);
      the seven scripts (zig-build, zig-package, zig-verify-package,
      zig-smoke, zig-contract, verify-tree, hermetic-check) read them;
      make-wheel.py:350 derives the same prefix
- [ ] build.zig toolchain step (pixi task `toolchain`), each directory
      with `LICENSES/` and `SOURCES`: `openmp/` (moved out of the base),
      unix `usr/bin/make` (moved out of minimal's tree), Windows
      `binutils/` (moved out of installWindowsCompilerContract; ld.exe
      dropped)
- [ ] The base's TC holds only rzig; Windows drops `zig-cc` and `zig-cxx`
- [ ] unix etc/Renviron: `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`,
      `MAKE=${MAKE-'make'}` for every flavor (minimal's `R_ZIG_MAKE` goes)
- [ ] Windows etc/Rcmd_environ:
      `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`
- [ ] Makeconf.win: each binutils tool named under `binutils/`; BINPREF
      for gcc/g++ only; unshipped tools per B43
- [ ] vendor-libs.sh: Windows libomp.dll trigger on R's OpenMP setting
- [ ] Patches 0009 and 0010 call the check mode (compilers and build
      tools); 0009's fallback removed; 0010's `command -v` replaced
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
- [ ] Tested: linux-64 (slim, minimal, wheel, conda-package), omicron
      (osx-arm64 slim and minimal, osx-64 slim), kappa, CI

## Phase 4 — conda and PyPI on the same boundary

Needs: B14, B28, B29, B35, B38, B39, B41.

- [ ] Check: rattler-build 0.76.1 makes outputs with no files that do not
      inherit the staging build
- [ ] recipe.yaml: r-zig-slim excludes only
      `lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` (and
      `Library/...`); r-zig-compilers, r-zig-build-tools (win-64: B39's
      list, B41's binutils), r-zig-toolchain metapackage; build number
      per B14 (a: 5 → 6 here)
- [ ] Hint writers removed: `-Dtoolchain-hint`, zig-build.sh:57-66,
      make-wheel.py's renviron_hint
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

Needs: B4 (B6: both cases are tested either way; B13: sizes only
recorded).

- [ ] Toolchain step: fetch-zig's zig into `TC/zig/` with `LICENSES/`
      (LICENSE, dist-info licences) and `SOURCES` (wheel URL, sha256)
- [ ] verify-tree: `zig/` third-party in the build-path scan;
      `zig/zig version` is 0.16.0
- [ ] verify-bundle scenario 2 with `ZIG_BIN` unset: RZIG_PRINT_ARGV shows
      `TC/zig/zig`; C, C++ (no shared libc++/libstdc++), OpenMP C (3
      forms), flagless omp.h probe; the env-tools pass kept
- [ ] The mixed case (default legs) and the one-zig case (upstream legs)
      pass on every OS
- [ ] Archive sizes recorded in PLAN.md; the first C++ compile's time
      with upstream zig measured ("Later": cache pre-seeding)
- [ ] Tested: linux-64, omicron (both), kappa, CI, upstream-zig label run

## Phase 6 — Fortran in the compilers group

Needs: B9, B13 (revisit), B29, B44 (only if a prototype fails).

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
- [ ] An OS whose prototype fails: B44 applies; ask the user with the
      result

Then:
- [ ] Toolchain step: the set from the env into `TC/flang/` (no
      `Library/`, no flang.cfg, no lld, the driver once, no linux
      module-directory symlink); `flang/SOURCES` from conda-meta;
      verify-tree checks against `paths_data`
- [ ] The carve script's cross-check, once
- [ ] `-lc++` and `link_libcpp` dropped where those runs passed
- [ ] verify-bundle scenario 2, no flang on PATH, no flang.cfg: a
      derived-type module, USE_FC_TO_LINK, `use omp_lib` on two threads,
      a configure linking with `$FC`
- [ ] Compression revisited with the measured compilers archives (B13)
- [ ] Tested: linux-64, omicron (both), kappa, CI

## Phase 7 — Windows build tools: usr/bin

Needs: B11, B25, B39.

- [ ] Prototype on kappa: busybox64u.exe (sh + one .exe per applet in
      B39's list) with make.exe, then the MSYS2 set; each on the contract
      set, pak, data.table and glue (a pkg-config package only with
      B39 c)
- [ ] Scan CRAN's configure.win/configure.ucrt for bash-only syntax;
      record the count
- [ ] B11 back to the user with the result (and the Windows make
      question if busybox-w32 wins)
- [ ] Toolchain step: the chosen set into `TC/usr/bin/` with
      `usr/LICENSES/` and `usr/SOURCES` (sha256 pins for downloads)
- [ ] Rprofile.windows PATH line, if the prototype needs it
- [ ] `R CMD config` without the build tools fails with one clear message
- [ ] conda's r-zig-build-tools (win-64) follows the winner where
      conda-forge packages it
- [ ] verify-bundle scenario 3 on Windows with PATH = bin\x64 + System32:
      the contract set builds and loads
- [ ] Tested: kappa, CI windows-latest

## Phase 8 — the base's runtime files

Needs: B27, B33.

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

Needs: B14 (with B37).

- [ ] Build number per B14 (a: only if a package changed since the last
      bump; b: 5 → 6 here); conda-package on all five platforms
- [ ] feat-no-host-paths PLAN.md: What remains 3 points here; the T
      record and the OpenMP note (406-409) updated
- [ ] installOpenMP's comment updated to B22
- [ ] This PLAN.md: status and records with dates and test results
- [ ] upstream-zig label run green
- [ ] Last round: linux-64, omicron (osx-arm64, osx-64), kappa, CI all
      green; hand the commit and PR commands to the user

## Later / future checks

- [ ] Which full-only features can become add-on R components (tcltk
      first); drop the separate full build only if readline/NLS can be
      settled
- [ ] Depend less on make for package installs (Windows needs sh/make
      for now)
- [ ] Optional extras group, only when the stress suite shows a need
      (pkg-config on Windows first; D15 sets when the suite starts)
- [ ] Windows binutils without GPL-3 (zig's tools + an nm, or LLVM's), if
      B24 stays (a)
- [ ] GNU make built with zig (B7 b)
- [ ] The release job (B12): `v*` tags, GitHub Release, GPL sources
      mirrored
- [ ] The toolchain in an environment of its own (feat-no-host-paths
      item 4; D14)
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
