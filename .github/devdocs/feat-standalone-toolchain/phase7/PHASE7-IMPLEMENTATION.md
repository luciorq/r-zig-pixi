# Phase 7 implementation plan — Windows build tools: usr/bin

The planner's plan of 2026-10-19, read-only. Nothing in any worktree was
changed, nothing was built or installed there, and no git command wrote.
The plan was critiqued once by its author and amended: CRITIQUE.md
beside this file lists every point and what changed; an amendment is
tagged (Cr<n>) where it lands. Format as
phase6/PHASE6-IMPLEMENTATION.md. Where an open point (section 11)
offers options, the plan is written with its recommended option (★);
the user answers them.

Sources:
- The worktree `wt/feat-standalone-phase6` (branch feat-standalone-phase6):
  main d11dee1 plus four uncommitted layers: phase 4 (the conda/PyPI
  split), R CMD SHLIB through rzig build (feat-shlib-rzig-build), phase 5
  (zig in the compilers group) and phase 6 (flang in the compilers
  group). On 2026-10-19 its `git status --short` had 79 entries (71
  modified, 8 untracked) and `git diff | sha256sum` started with
  9587f87ad4a6e48c, while another agent was reverting the build number
  to 8 and adding the `CONDA_PUBLISH` gate in it (recipe.yaml's "8
  stays" entry, build.yaml's publish step, pixi.toml's and README's
  notes); this plan builds on those lines and does not repeat them.
  - Line numbers are this worktree's on 2026-10-19. When implementing,
    cite the function, not the line.
  - pixi.lock's sha256 starts with fbb64b7ba4e31e45. The recommended set
    needs no lock change; open point F's recommended option does (the
    user approves it or picks F c).
- feat-standalone-toolchain PLAN.md: "### Phase 7 — Windows build tools:
  usr/bin" (5955-5987), "The toolchain groups" (151-170), the Windows
  userland facts (631-645), decisions B11, B20, B23, B25, B26, B35, B39,
  B43, B44; the phase 3-6 records; TODO.md "## Phase 7" (742-795), its
  "Re-scope from feat-zig-pkg-build's stress table" item and "Later".
- feat-zig-pkg-build PLAN.md: tiers, "What the build-tools group is for"
  (1016-1046), "Stress dispatch" (M6); feat-shlib-rzig-build PLAN.md
  (open point H: `R CMD config` and Windows `has_rtools()`);
  feat-shared-build-runner PLAN.md.
- Two surveys made for this plan (their scratch is under
  `/data/gamma/luciorq/workspaces/temp/r-zig-pixi/phase7plan/`):
  - **PS** (packages): the 37 locked packages of the candidate set
    downloaded (each matched pixi.lock's sha256), extracted, their PE
    imports read, their records, licences, placeholders and recipe
    sources listed (`dl/inventory.json`, `pkgs/`); conda-forge's API for
    native alternatives (`api/`, `dl2/`); msys2-runtime 3.6.1's
    `mount.cc` and `cygheap.cc`, GNU make 4.4.1's source, the stock
    MSYS2 fstab and Rtools' build scripts (`pkgs/src-*`, `web/`).
  - **SS** (stress): runs 38317654371, 38467907779 and 38569895172, the
    Windows rows, the programs each ran by evidence class
    (`stress-survey/`).
- (PP) this planner's probe: the planned `usr/` and `etc/` assembled in
  `probe/usr-proto/` from PS's extracted packages by
  `scripts/assemble-usr.sh`: 140 files, 24,891,268 bytes; as a deflate
  zip (level 6, as `zip -qr`), 12,167,956 bytes. (PP2, Cr9) B39's names
  only (37 .exe) with the same DLLs, in `probe/b39/`: 52 files,
  19,216,248 bytes, zipped 9,537,393.
- R 4.6.1's sources as the worktree's `build/R-4.6.1/` has them:
  rcmdfn.c, Rcmd_environ, Rprofile.windows, winshlib.mk, Makeconf
  (gnuwin32), packages2.R, sotools.R, install.R.

TC is `R_HOME/bin/toolchain` (Windows `Library/lib/R/bin/toolchain`).
"The tree" is the toolchain tree, `dist/toolchain/R-<ver>-zig`. Decision
IDs are PLAN.md's; this plan's open points are letters (section 11).

## 0. What phase 7 delivers

- **The build-tools group on Windows gets `TC/usr/bin/`**: B39's tools,
  copied unchanged from conda-forge packages in the build env, with the
  DLLs they import beside them, and `usr/SOURCES` and `usr/LICENSES/`
  as every group directory has them (point 3):

  | piece | from (win-64 env) | to |
  |---|---|---|
  | sh, bash | m2-bash 5.2.037.2: `Library/usr/bin/{sh.exe,bash.exe,bashbug}` | `usr/bin/` |
  | make | m2-make 4.4.1.2: `Library/usr/bin/make.exe` (open point B) | `usr/bin/make.exe` |
  | coreutils | m2-coreutils 8.32.5: the 107 files of `Library/usr/bin/` (open points A, C) | `usr/bin/` |
  | sed, grep, awk | m2-sed 4.9.1, m2-grep 1!3.0.7 (`grep.exe`, `egrep`, `fgrep`), m2-gawk 5.3.2.1 (`gawk.exe`, `awk.exe`, `gawk-5.3.2.exe`, `gawkbug`) | `usr/bin/` |
  | which, find, xargs | m2-which 2.23.4, m2-findutils 4.9.0.3 (`find.exe`, `xargs.exe`, `locate.exe`, `updatedb`) | `usr/bin/` |
  | the MSYS DLLs | `msys-2.0.dll` (m2-msys2-runtime 3.6.1.4), `msys-intl-8.dll`, `msys-iconv-2.dll`, `msys-pcre-1.dll`, `msys-gmp-10.dll`, `msys-mpfr-6.dll`, `msys-readline8.dll`, `msys-ncursesw6.dll`, `msys-gcc_s-seh-1.dll` (one package each) | `usr/bin/` |
  | pkg-config | pkg-config 0.29.2: `Library/bin/pkg-config.exe`, and the DLLs it imports: `glib-2.0-0.dll` (libglib 2.90.0), `iconv.dll`, `charset.dll` (libiconv), `intl-8.dll` (libintl), `pcre2-8.dll` (pcre2), `vcruntime140.dll` (vc14_runtime) | `usr/bin/` |
  | pkgconf (open point F a) | pkgconf 3.0.7: `Library/bin/{pkgconf.exe,pkgconf-8.dll}` (not in the lock today) | `usr/bin/` |
  | licences, records | each package's `info/licenses/`; for the m2 packages, which have none, the texts taken once by hand from their MSYS2 source archives and kept in the repository (open point E, Cr1) | `usr/LICENSES/<package>/`, `usr/SOURCES` |

  - 140 files and 24,891,268 bytes raw without pkgconf (PP; 142 files,
    25,036,164 bytes with it). The build-tools `.zip` grows by about
    12.2 MB (PP: `usr/` and `etc/` as a deflate zip), on top of
    `binutils/`.
  - No file has a prefix placeholder (PS: the only one in the whole m2
    set is m2-filesystem's `etc/fstab`). Every path is a regular file.
  - The closure is the same for B39's names and for every file of the
    eight tool packages (PS, recomputed by the planner from PS's
    imports): the nine MSYS DLLs above, and nothing else outside the
    system. gawk alone needs mpfr, gmp, readline, ncurses and gcc_s
    (1,963,534 bytes); expr and factor need gmp; sort and nproc need
    gcc_s; grep needs pcre.
- **`TC/etc/fstab`, MSYS's mount table** (open point D a), written by the
  toolchain build, not copied: msys-2.0.dll in `TC/usr/bin/` makes `TC`
  the MSYS root (msys2-runtime 3.6.1 strips `bin` and then `usr` from the
  DLL's directory, PS), which reads `TC/etc/fstab`. The two lines are
  MSYS2's and conda-forge's (m2-filesystem's, less its build-env
  `/conda_bin` line, which holds the placeholder):

      none / cygdrive binary,posix=0,noacl,user 0 0
      none /tmp usertemp binary,posix=0 0 0

  Drives at `/c` as in Rtools and a conda env, no POSIX ACLs written on
  files the tools create (`noacl`), and `/tmp` the user's `%TEMP%`, so a
  read-only R install works. `etc/SOURCES` names it as r-zig's own file
  with a `file:` line and its sha256; it has no `LICENSES/`.
- **The build-tools group is `usr`, `etc` and `binutils`**: env.sh's
  `group_dirs build-tools` gains `etc` (absent on unix), so
  package-standalone.sh, verify-toolchain.sh, compile-tree.sh and
  unpack-toolchain.sh carry it with no other change.
- **R finds them with no PATH set by the user** (B25 a):
  - under R CMD: etc/Rcmd_environ's line, there since phase 3
    (`PATH="${R_CUSTOM_TOOLS_PATH:-${R_ZIG_TOOLS_PATH}};${PATH}/"`),
    puts `TC/usr/bin` after `bin\x64`; until now it named a directory
    that did not exist;
  - in an R session (open point I a): Rprofile.windows gets the same
    rule (new patch 0014), as R's own installer build turns on Rtools'
    block there and as unix's etc/Renviron does, so `Sys.which("make")`,
    `install.packages(Ncpus = 2)`'s parallel make and `system("sh ...")`
    see the group.
- **`R CMD config` without the build tools fails with one message**
  (open point J a): rcmdfn.c's `config` branch runs `sh config.sh`, so
  with no sh cmd.exe answered "'sh' is not recognized" and R CMD config
  exited 1. Patch 0010 gains an rcmdfn.c hunk that runs rzig's
  `--rzig-check=build-tools` first and returns its status (127, with the
  build-tools group's text) when it fails. One patch, one concern: "R CMD
  config names the missing build tools", on both OSes.
- **R CMD check's object symbol tables find nm** (open point H a):
  Rcmd_environ sets `UserNM=${UserNM-${R_ZIG_NM}}`, `R_ZIG_NM` the
  group's `binutils/nm.exe`, as it sets RC for windres (sotools.R reads
  `UserNM`, else `nm` on PATH, which has none).
- **rzig's build-tools text on Windows** (B35, open point K a): the
  standalone line becomes "extract R-<ver>-win-64-build-tools.zip where
  you extracted R", like unix's, with no "put sh and make on PATH (for
  example Rtools45's usr/bin)".
- **conda's win-64 r-zig-build-tools** (B11): its run dependencies are
  phase 4's interim list, which this phase keeps as the final one (the
  same packages the tree copies: m2-bash, m2-make, m2-coreutils, m2-sed,
  m2-grep, m2-gawk, m2-which, m2-findutils, pkg-config; zstd for the
  binutils), plus `pkgconf` (F a). Its comments stop calling the list
  interim. No file is added to the package.
- **Checks**: verify-toolchain checks `usr/` and `etc/` on Windows (open
  point O); verify-bundle's scenario 3 on Windows runs with PATH =
  `bin\x64` + System32 only, the env's `Library/usr/bin` gone, with new
  packages for B39's tools, for pkg-config and pkgconf and for R CMD
  check's nm, and a run with Git for Windows' MSYS on PATH (open point
  M); hermetic-check.sh and test-preflight.R check `R CMD config`'s text
  on Windows too; test-build-tools.R checks B39's names in a conda env;
  stress.R gets a Windows option that leaves the env's MSYS tools off
  PATH, for one dispatch (open point L).
- **The build number** (the user's decision of 2026-10-19; open point N
  a): phase 7's PR takes the bump, to the number after universe's newest
  (9 while universe holds `_8`), with one history entry for phases 4,
  SHLIB, 5, 6 and 7. After the merge the user sets `CONDA_PUBLISH` and
  the publish runs.

Not in phase 7:
- Windows minimal and the Windows wheel (C1-C3 a): after phase 7. The
  Windows `r-zig-build-tools` wheel, when it comes, takes `usr/` and
  `etc/` from the tree as unix's takes `usr/bin/make`.
- cmake (the extras group's first candidate: Rhdf5lib, RcppParallel's
  TBB), diffutils, tar, gzip, unzip, zip, patch, perl, texinfo: no
  install in the three stress runs needed them (SS §2).
- A native make (open point B b), uutils-coreutils (A b, A c) and
  busybox (B11: none).
- The binutils: unchanged (B24); nm stays in `binutils/` and gets
  `UserNM` (H), not a second copy.
- `R CMD config` through rzig (TODO "Later"): J only makes the failure
  clear.
- Phase 8's runtime files (Windows fonts), B33's base licences.

## 1. Sequencing and preconditions

- **Stacked on four uncommitted layers.** The implementation worktree
  `wt/feat-standalone-phase7` is made as phase 6 made its own (phase 6's
  hand-over, `phase6/handover/make-diff.sh`): `wt/phase6-base.diff` is
  `git diff` of `wt/feat-standalone-phase6` (cumulative from main
  d11dee1; no such file exists yet, Cr16), applied to main exported with
  `git archive`, and the phase 6 worktree's untracked files copied, each
  checked by sha256; the result must equal `wt/feat-standalone-phase6`
  file for file. At the
  start the implementer records in `phase7/implementer/`: `git diff |
  sha256sum`, `git status --short`, the sha256 of each untracked file,
  pixi.lock's sha256. The final `phase7-only.diff` is made against that
  baseline (open point Q).
  - If the phase 6 worktree changes after the baseline is taken (the
    other agent's build-number and CONDA_PUBLISH lines, a CI fix on
    phase 6's PR), the baseline is taken again before step 7, and every
    hunk phase 7 shares with it is re-read: recipe.yaml (the number,
    r-zig-build-tools), build.zig's rcmdEnviron, verify-bundle.sh,
    README.md, pixi.toml, PLAN.md, TODO.md.
  - Merge order: phase 4's PR, SHLIB's, phase 5's, phase 6's, then phase
    7's. Each of the first four keeps build 8 and publishes nothing
    (`CONDA_PUBLISH` unset, the user's decision of 2026-10-19).
- **The build number and publishing** (open point N a):
  - Until the PR's last commit, recipe.yaml keeps `number: 8`.
  - Just before merging: `pixi run -e pkg conda-channel-list universe
    <subdir>` for the five subdirs; the number becomes the one after
    universe's newest (9 if `_8` is still the newest), with one history
    entry in recipe.yaml naming phases 4, SHLIB, 5, 6 and 7, and
    replacing the "8 stays" entry. conda-package runs on the PR with that
    number (the recipe changed, so its path filter runs it).
  - The upgrade test from universe's `_8` (phase 4's G a procedure) runs
    then, on the PR's local packages: gamma (pixi, conda, micromamba),
    kappa (pixi, conda), omicron (pixi). Phase 4 ran it to `_9` with phase
    4 alone; the number that publishes now carries four more phases.
  - After the merge: the user sets the repository variable (`gh variable
    set CONDA_PUBLISH --body true`, as build.yaml's publish step says)
    and dispatches build.yaml on main (`pixi run ci-trigger`), whose
    conda-package legs publish. Then: `conda-channel-list` shows the four
    `_N` files on the five subdirs; a fresh env from universe alone
    (`pixi add r-zig-toolchain`, fresh caches, no local channel) passes
    test-toolchain.R; the closing notes of phase 4 (TODO's "After the
    publish from main"), feat-zig-pkg-build's N5 and
    fix-zig-pkg-build-review's status get "published as `_N`, <date>".
- **Hosts.** kappa (win-64) carries this phase: steps 1 to 5 and 8 run
  there. gamma (linux-64) runs the unit tests, the unix regression and
  the m2 licence texts (E a, by hand; it needs the network). omicron (osx-arm64)
  runs only what changes unix code: zigbuild/toolchain/build.zig's
  `Tree` (the flang trees), verify-toolchain.sh and verify-bundle.sh's
  edits, the patch series (0010 changed, 0014 new) (step 8). osx-64
  under Rosetta is not needed: no osx-64-specific code changes; CI's
  macos-15-intel legs cover it.
- **Ownership** (parallel testers): one owner per host; gamma's owner
  owns the worktree's `dist/` and the edits; kappa's and omicron's
  testers own their hosts and their scratch copies (never synced back);
  no one writes pixi.lock (open point F a's re-lock is the implementer's
  one approved change, on gamma, in step 2, after the user approves it);
  each tester records the lock's sha256 and `git diff | sha256sum` at
  the start and the end; scratch and TMPDIR under `phase7/<role>/`.
- **kappa's key** is passphrase-protected: the user loads it into
  ssh-agent before the kappa steps. kappa's cmd-over-SSH `%VAR%`
  parse-time expansion: run every kappa command through the env's bash
  (`pixi run bash -c ...`), as phases 4-6 did.
- **Disk.** gamma: `df -h /` before each long run; stop line 6 GB on `/`
  (everything under /data). kappa: the default env (~4 GB), the tree, the
  extracted bundles (base + compilers ~0.9 GB + build-tools ~0.05 GB),
  the stress scratch; check free space first and record it.
- **Network.** E (a)'s texts: the 17 MSYS2 source archives downloaded
  once on gamma, by hand, into `phase7/implementer/m2-src/` (GCC's,
  for m2-gcc-libs, about 90 MB), each checked against its recipe's
  sha256; `zstd` through `pixi exec --spec zstd` under PIXI_CACHE_DIR,
  outside the lock, as phase 6's python (Cr1). kappa's step 1 and 4 runs
  install CRAN packages (pak, data.table, glue, Rcpp, minqa, ps, Rmpfr,
  units, systemfonts) and make a small libraries env with pixi (Cr6).

## 2. Steps

Each step is a checkpoint that leaves every test it names green. CI sees
only the PR's final state. Steps 1 to 4 can be checked on kappa one after
the other; step 2's code is what step 4's scenario 3 extracts.

0. **Baseline** (section 1). On gamma the baseline's `pixi run build`
   too (step 3 compares unix's R with it). Also on kappa: the phase 6 state built
   (`pixi run build`, `toolchain`, `package`, `package-toolchain`) in
   the tester's copy, so step 1 has a base and both group archives as
   phase 6 makes them.
   - Tests: `pixi lock --check`; pixi.lock's sha256 starts with
     fbb64b7ba4e31e45 on every host; kappa's `verify-package` passes on
     the phase 6 state (the reference: scenario 3 with the env's
     `Library/usr/bin`, its time recorded).

1. **kappa prototype: the planned usr/bin by hand** (open points A, B, C,
   D, G, I, M; B11, B25, B39). Before any code: the files of section 0
   copied by a scratch script (`phase7/kappa/proto-usr.sh`, the kappa
   twin of PP's `assemble-usr.sh`, reading from the env's
   `$CONDA_PREFIX/Library/usr/bin` and `Library/bin`) into an extracted
   phase 6 bundle (base + compilers + build-tools), plus `TC/etc/fstab`.
   Every run below uses verify-bundle's `base_env` (SYSTEMROOT, WINDIR,
   COMSPEC, PATHEXT, a fresh HOME, TMPDIR/TMP/TEMP under it) and PATH =
   `bin\x64` + System32 alone, ZIG_BIN unset (TC/zig).
   - **The MSYS root** (D): `R CMD sh -c` printing `cd / && pwd -W`,
     `cd /tmp && pwd -W`, `cd /usr/bin && pwd -W` (MSYS bash's builtin:
     `cygpath` is msys2-runtime's program, which `usr/bin` does not hold,
     Cr3), `pwd` in `C:\x`, a here-doc, `mktemp`, and `cp` of a file into
     a fresh library directory followed by `icacls` (System32's) on the
     copy: root is TC, `/tmp` is TEMP, drives at `/c`, the copy has only
     inherited ACEs. Then the same without `etc/fstab` (recorded:
     `/cygdrive/c`, `/tmp` = `TC/tmp`, which does not exist, and the ACEs
     MSYS writes) — the evidence for D.
   - **Each tool starts** with PATH = System32 alone: `TC/usr/bin/<x>.exe
     --version` for sh, bash, make, sed, grep, gawk, awk, which, find,
     xargs, pkg-config, and coreutils' `basename`, `rm`, `cp`, `mv`,
     `mkdir`, `cat`, `tr`, `sort`, `uname`, `chmod`, `ln`, `ls`, `expr`,
     `touch`, `head`, `tail`, `wc`, `env`, `printf`, `mktemp`, `[`/`test`;
     `objdump -p` of each against PS's import lists.
   - **R finds them**: `R CMD gcc.exe --rzig-check=build-tools` (the
     short path, as verify-bundle runs it) says `make at
     <TC>/usr/bin/make.exe; sh at <TC>/usr/bin/sh.exe; binutils at ...`;
     `R CMD config CC` is rzig's gcc.exe; `Rscript -e Sys.which("make")`
     is "" (no Rprofile line yet), and with a user profile holding open
     point I's line (`R_PROFILE_USER` pointing at a file with it, the
     prototype of patch 0014; without `--vanilla`, which skips user
     profiles, Cr7) it is the group's make.
   - **Phase 6's scenario 3 on the group**: a scratch copy of
     verify-bundle.sh whose Windows `bt_path` is `$R_BINDIR:$sys32` and
     whose `usr_bin` is `TC/usr/bin` (two lines), run against the
     prototype bundle: every Windows scenario 3 block passes (Makeconf's
     tools, R CMD config AR/NM/OBJDUMP, R CMD check's objdump, tools.mk,
     CMake's archiver, the OpenMP packages through make and rzig build,
     btA/btLib/btRc with Ncpus = 2, fcconf's configure.win, the LTO
     record, the no-zig preflight).
   - **A libraries env** (Cr6, Cr15): a scratch pixi env on kappa with
     freetype, fontconfig, libpng, zlib, gmp, mpfr and udunits2 only (no
     pkg-config, no make, no m2 package: `Library/bin` then holds no
     tool of B39's names; checked with `ls`), `PKG_CONFIG_PATH` its
     `Library/lib/pkgconfig`, `R_ZIG_EXTRA_ENV` its prefix, its
     `Library/bin` appended to PATH after System32 for its DLLs, during
     the installs too (install.R loads each package).
   - **Real packages** (`phase7/kappa/s3-set.R`, run by the bundle's
     Rscript, CRAN, `type = "source"`, Ncpus = 2, `keep_outputs`,
     RZIG_TRACE=1): Rcpp, data.table (configure.win), minqa (Fortran,
     `$(shell)`), pak (configure.win; its keyring and zip through make),
     ps, glue, Rmpfr (an autoconf configure.win: awk, grep, expr, cat,
     mkdir, mv, tr, sort, uname, chmod, ln, ls; SS §2; gmp and mpfr from
     the libraries env), units (Makevars.ucrt `all: clean`; udunits2 from
     it). find and xargs under `--preclean` are btTools' (step 4), not a
     CRAN package's (Cr6). Each loads and runs a smoke.
     `pkgbuild::has_rtools(debug = TRUE)` and
     `pkgbuild::check_build_tools(debug = TRUE)` recorded (the open
     "Later" item: with sh present `Rcmd config CC` now answers).
   - **pkg-config**: systemfonts from CRAN with the libraries env: the
     install log shows TC's pkg-config's flags (`-I...freetype2`), the
     only pkg-config on that PATH.
   - **The clash** (M a): the scenario 3 copy and s3-set.R again with
     Git for Windows' `usr\bin` appended after System32, then put first,
     if kappa has Git for Windows (recorded with its `msys-2.0.dll`
     version; if it has none, the clash is CI's, Cr17).
     Under R CMD and (with I's line) in the session `TC/usr/bin` comes
     first, so the names TC has run from TC; recorded: any "cygheap",
     "fork: retry", "*** fatal error" or hang, and the times. Rtools45 too
     if kappa has it installed (M a; record its absence otherwise).
   - **Recorded, not a gate** (B b, A b): the scenario 3 copy with
     conda-forge's native `make.exe` (from `Library/bin`, as shipped,
     17,111,844 bytes) in place of m2's in the prototype's `usr/bin`; and
     with uutils-coreutils 0.0.20's names in place of m2-coreutils'.
     Their results go into open points A and B's records.
   - **Measured** (Cr12, Cr18): how many `R CMD config` calls install.R
     makes before one configure.win (data.table's), with their total
     time; the first `R CMD sh -c true` after the files are extracted
     (Defender scans 140 new executables) and the second.
   - **R_HOME with a space** (Cr11): the same bundle extracted under
     `C:\r zig\`: `R.home()` and `R CMD Rscript.exe -e
     'Sys.getenv("UserNM")'` (8.3 form or not), and whether
     `tools:::read_symbols_from_object_file` runs with it (sotools.R puts
     UserNM unquoted into `system()`); recorded for open point H.
   - Results: each open point's evidence in `phase7/kappa/RESULTS.md`; a
     failure in the recommended set stops the plan for that point and
     goes back to the user with the measurement.

2. **The toolchain step: `usr/` and `etc/` in the tree** (open points C,
   D, E, F, O; B11, B39, B43).
   - Changes: zigbuild/toolchain/build.zig (the `usr` directory of
     `windows_dirs`, `Tree.strip`, the fstab writer, the licence
     fallback, the header comment and summary),
     zigbuild/toolchain/conda.zig (`inDir` takes the prefix to strip;
     `licenses_from`; unit tests), zigbuild/toolchain/m2-licenses/ (E a:
     the texts, taken by hand, Cr1), scripts/env.sh (`group_dirs`),
     scripts/verify-toolchain.sh (O), recipe/recipe.yaml (r-zig-slim's
     exclusion globs and `not_exists` gain `etc`, Cr5), pixi.toml and
     pixi.lock (F a, after the user's approval: `pkgconf ==3.0.7` in
     `[target.win-64.dependencies]`, then `pixi lock`; the lock's diff
     must add pkgconf's entries and change nothing else, else stop and
     report, Cr10).
   - Over 200 changed lines (build.zig, verify-toolchain.sh): a skeptical
     diff review before the tests: Windows paths (`\` in conda-meta's
     `_path`, `Library/usr/` stripped once, never `Library/` twice), a
     DLL name in two packages (iconv.dll is libiconv's, msys-iconv-2.dll
     m2-libiconv's), every copy `in_conda = false` and every tree skipped
     when the prefix is the env, the summary's order, no file directly
     in TC.
   - Tests:
     - `zig fmt --check zigbuild/toolchain/`; `bash -n
       scripts/verify-toolchain.sh scripts/env.sh`.
     - `pixi run toolchain-test` with both zigs (gamma): conda.zig's new
       tests: `inDir` with `Library/usr/` (`Library/usr/bin/sed.exe` →
       `bin/sed.exe`), with `Library/` (flang's, unchanged), and a path
       that has neither; `under` on an m2-shaped record (backslash paths,
       a script and exes); `writeSources` with `licenses_from`.
     - E a's texts (gamma, by hand, Cr1): for each of the 17 m2
       packages, the source archive (its recipe's `finalized_sources`
       entry under `/sources/`) downloaded and checked against the
       recipe's sha256, the licence files taken out (README of the
       directory says how, per package), written with VERSION and
       ORIGIN; then a check script in scratch (not committed) that
       re-hashes every text against ORIGIN.
     - The licence fallback, on kappa (it reads a win-64 env): `pixi run
       toolchain` with one package's `m2-licenses/<pkg>/VERSION` edited
       in a scratch copy stops with the "does not hold its texts" line;
       restored, it passes.
     - The conda rule (Cr5): in step 5's `conda-package` on kappa, the
       build log's toolchain line names `binutils/` only (no `usr/`, no
       `etc/`), and r-zig-slim's and r-zig-build-tools'
       `package_contents` checks pass (`not_exists` of
       `Library/lib/R/bin/toolchain/{usr,etc}/**` in r-zig-slim). No
       fake-env run: on Windows the binutils' copies need their files in
       the env, so phase 6's conda-meta-only fake env cannot stand in.
     - linux-64 regression (gamma): `pixi run toolchain` with both zigs
       prints the same summary as phase 6 (`flang/ (flang-zig,
       flang-rt-zig), openmp/ (llvm-openmp), usr/ (make), zig/
       (ziglang)`), `verify-toolchain` passes, and the tree's file list
       and sha256s equal phase 6's (`find | sort | xargs sha256sum`
       compared): the `Tree.strip` change moves no unix file.
     - kappa: `pixi run toolchain` (time recorded, and the configure
       step's alone, risk 9); the summary names, in copy order (Cr8),
       `binutils/ (binutils_impl_win-64, zstd, vc14_runtime)`, `usr/
       (m2-msys2-runtime, m2-libintl, m2-libiconv, m2-libpcre, m2-gmp,
       m2-mpfr, m2-libreadline, m2-ncurses, m2-gcc-libs, pkg-config,
       libglib, libiconv, libintl, pcre2, vc14_runtime[, pkgconf], m2-bash,
       m2-make, m2-coreutils, m2-sed, m2-grep, m2-gawk, m2-which,
       m2-findutils)`, `etc/ (r-zig's fstab)`; `pixi run verify-toolchain`
       passes (O a: names, versions, closure, fstab) and prints its time;
       the listing equals PP's 140 files (142 with pkgconf); `usr/SOURCES`
       has one block per package with `source:` lines naming the MSYS2
       source archive for each m2 package, and `licenses: from <url>`
       for each m2 block; `usr/LICENSES/` one directory per package,
       none empty.
     - kappa negative cases on a copy of the tree (`verify-toolchain.sh
       <copy>`): `usr/bin/msys-2.0.dll` deleted (the closure check names
       every importer), `usr/bin/sed.exe` replaced by another file (sha256
       mismatch), `etc/fstab` with a third line (O's content check), a
       stray `usr/bin/diff.exe` (no file line), `usr/LICENSES/m2-sed/`
       emptied (missing or empty).
     - kappa: `pixi run package-toolchain`: `R-4.6.1-win-64-build-tools.zip`'s
       size and member count recorded against phase 6's (expected +12.2
       MB, PP); `pixi run unpack-toolchain` then `verify-toolchain` again
       (the tree from the zip); `pixi run compile-tree` copies `usr/`,
       `etc/` and `binutils/`.

3. **R's side: R CMD config, the session PATH, UserNM, the text** (open
   points H, I, J, K; B25, B26, B35).
   - Changes: zigbuild/patches/R-4.6.1/0010-config-make-check.patch (the
     rcmdfn.c hunk, its header), zigbuild/patches/R-4.6.1/0014-rprofile-windows-tools-path.patch
     (new), build.zig (rcmdEnviron: `UserNM`, comments),
     zigbuild/tools/rzig/groups.zig (the Windows build-tools line, the
     doc comment, the test), zigbuild/tools/rzig/parity-test.sh only if
     it greps the old Windows line (it greps unix lines: checked, no
     change expected), scripts/hermetic-check.sh (Windows R CMD config),
     recipe/test-preflight.R and recipe/test-compilers.R (Windows R CMD
     config).
   - Tests:
     - `zig fmt --check zigbuild/tools/rzig/`; `pixi run rzig-test` with
       both zigs (gamma): groups.zig's text test with the new Windows line.
     - gamma: `pixi run build` (the series hash changed, so zig-build.sh
       extracts R again and applies 0001-0014; both new hunks apply with
       `-F0`); `smoke`, `verify-tree`, `hermetic`; unix's R is unchanged:
       `lib/R/lib/libR.so`, `bin/exec/R` and `library/base/R/Rprofile`
       compared by sha256 with step 0's build of the baseline (equal;
       0010's rcmdfn.c hunk and 0014 touch Windows files only).
     - kappa: `pixi run build`; `pixi run hermetic` (the installed tree
       has no group: `R CMD config CC` exits 127 with "Building packages
       needs the r-zig build tools for R 4.6.1 on win-64" and no "is not
       recognized" line); `R.exe CMD config --help` without the group
       (recorded: the check runs first, as on unix, so it fails too);
       `Rscript -e 'Sys.getenv("PATH")'` starts with
       `<R_HOME>/bin/toolchain/usr/bin;` and with
       `R_CUSTOM_TOOLS_PATH=C:/x` with `C:/x;`; `R CMD Rscript.exe -e
       'Sys.getenv("UserNM")'` is `<R_HOME>/bin/toolchain/binutils/nm.exe`,
       and an `UserNM` already set is kept.

4. **verify-bundle's scenario 3 on the group** (open points F, H, I, M;
   TODO's phase 7 tests).
   - Changes: scripts/verify-bundle.sh (section 3), scripts/verify-helpers.sh
     only if a helper is shared (`btTools`' configure.win is written by a
     new `tools_pkg` there only if scenario 2 needs it too; it does not:
     inline).
   - Over 200 changed lines: a skeptical diff review before the tests:
     every former `usr_bin`/`CONDA_PREFIX` use in the Windows block, the
     clash block's PATH order and restore, cygpath forms (`-m -l` for
     comparisons, `-w -s` for R CMD's unquoted commands), CRLF stripped
     from every R CMD output, case-insensitive path greps.
   - Tests:
     - `bash -n scripts/verify-bundle.sh`.
     - kappa, default env, conda-forge's zig: `pixi run package-toolchain`
       then `pixi run verify-package`, both passes: scenario 1's new
       session-PATH line; scenario 3 with PATH = `bin\x64` + System32 and
       no `CONDA_PREFIX` needed: the check names TC's make and sh,
       `Sys.which("make")` and `make --version` in an R session (as unix),
       the Makeconf/config/objdump/tools.mk/CMake/OpenMP/bt/fcconf/LTO
       blocks, the new `btTools`, `btPc` and nm blocks, and the clash
       block with Git's `usr\bin` (kappa has it).
     - kappa, upstream zig: `ZIG_BIN="$(pixi run fetch-zig)"` build,
       toolchain, package-toolchain, verify-package (the one-zig pass).
     - kappa negative run: a scratch copy of the script that deletes
       `TC/usr/bin/sh.exe` after extraction: scenario 3 fails at the
       check with "no sh on PATH" and the build-tools text.
     - gamma: `pixi run verify-package` (default, both passes) and
       `-e minimal verify-package`: unix's blocks unchanged.

5. **conda: r-zig-build-tools and its tests** (open points F, P; B11,
   B28).
   - Changes: recipe/recipe.yaml (r-zig-build-tools: the comments, F's
     `pkgconf`, the summary text), recipe/test-build-tools.R (B39's
     names from this env, pkgconf), scripts/conda-consume.sh (P a: a
     fourth environment, r-zig-toolchain, test-toolchain.R).
   - Tests:
     - kappa: `pixi run -e pkg conda-package` (both `--error-*` flags,
       the four outputs' tests), then `pixi run -e pkg conda-consume`
       (four envs); `package_contents` of r-zig-build-tools unchanged
       (binutils only).
     - kappa, by hand: `phase7/kappa/s3-set.R` (step 1's packages) in
       conda-consume's `toolchain` env through `pixi run Rscript`
       (activation's PATH: `Library/usr/bin`, `Library/bin`); and the
       same with PATH narrowed to `Library/usr/bin`, `Library/bin`,
       `bin\x64`, System32 (test-build-tools.R's `narrow`), and once more
       with Git for Windows' `usr\bin` appended where kappa has it (TODO:
       "the same with Rtools or Git ... and in a fresh conda env", Cr14).
     - gamma and omicron: their `conda-package` with the final number
       (step 7); linux and macOS r-zig-build-tools are unchanged.

6. **The stress re-scope evidence** (open points G, L; TODO's re-scope
   item).
   - Changes: stress/stress.R (`--msys-from-tree`: on Windows the PATH
     leaves out the env's `Library/usr/bin` and `Library/mingw-w64/bin`),
     .github/workflows/stress.yaml (an input passing it),
     stress/README.md (the option).
   - Tests:
     - gamma: `Rscript -e 'invisible(parse("stress/stress.R"))'`;
       actionlint on stress.yaml.
     - kappa: `pixi run stress -- --msys-from-tree g3` (or the stress
       task's own way of passing options; recorded), its report's
       Windows rows equal 38569895172's g3 rows (builders and results).
     - CI, after the push (L a): `gh workflow run stress.yaml --ref
       feat-standalone-phase7 -f runners='["windows-latest"]' -f
       packages='g3 g4' -f trace=true -f shared_cache=false -f
       msys_from_tree=true`: the 30 Windows rows that need the group
       give 38569895172's builders and results with B39's list alone
       (Rhdf5lib's and RcppParallel's cmake come from the env's
       `Library/bin`, the extras group's candidate); any "command not
       found" names a tool B39 lacks (recorded, and G's record). The
       report's per-row table is read row by row: every row that is not
       ok is listed with its expect and cause, never "passed" from the
       job's status (Cr13).

7. **Docs, records, the bump, the hand-over** (open points N, Q).
   - Changes: README.md, the stale references (section 10), PLAN.md's
     phase 7 record and B11/B25/B39/B43 records, TODO.md, recipe.yaml's
     number and history entry (N a, just before merging), pixi.toml's
     comments.
   - Tests:
     - after any pixi.toml edit: `pixi lock --check` (and, with F a, the
       new lock's sha256 recorded everywhere it was).
     - actionlint on the workflows touched.
     - gamma: the default chain end to end (PLAN's Verification block):
       `rzig-test`, `toolchain-test`, `build`, `toolchain`, `verify-tree`,
       `verify-toolchain`, `smoke`, `contract`, `hermetic`, `pkg-parity`,
       `package-toolchain`, `verify-package`; `-e minimal build` +
       `verify-package`; `-e wheel wheel` + `wheel-test` (no wheel
       content changes; the rzig text's unix lines unchanged);
       `-e pkg conda-package`, `conda-consume`.
     - The upgrade test from universe's `_8` (section 1), with the final
       number, on gamma, kappa and omicron.
     - `phase7-only.diff` (Q a) applied to a second copy of the baseline
       reproduces the worktree exactly.

8. **Other hosts, CI, records.**
   - kappa: the full round on the final code (section 6's row).
   - omicron (osx-arm64): `rzig-test` (both zigs), `toolchain`,
     `verify-toolchain` (the flang trees after `Tree.strip`), `build`
     (the new series applies), `package-toolchain`, `verify-package`
     (default, both passes), `conda-package`, `conda-consume`.
   - CI on the PR (section 6): the core tier, `full-ci`, the
     `upstream-zig` label (the patches and rzig changed), the stress
     dispatch (L a). The hand-over says "phase 7 pending CI" until they
     pass.
   - The measurements (section 7) and the records (section 10) into
     PLAN.md.

## 3. Per file: the exact change

### zigbuild/toolchain/build.zig (step 2; open points C, D, E, F, O)

Header (lines 15-33): `usr/` gets its Windows row, `etc/` is new, the
"Windows' usr/bin comes in phase 7." line goes:

    //!   usr/       build-tools  unix: conda-forge's GNU make as usr/bin/make
    //!                           (B7, B23); Windows: B39's tools and
    //!                           pkg-config in usr/bin/, from conda-forge's
    //!                           m2 packages (MSYS2) and pkg-config, with
    //!                           the DLLs they import (B11; PHASE7 open
    //!                           points A-C, F)
    //!   etc/       build-tools  Windows: fstab, r-zig's own MSYS mount
    //!                           table (PHASE7 open point D)

and the conda paragraph: "only those [binutils] are installed" stays
true (`usr/` and `etc/` are never installed into the env).

`Tree` gains the prefix its paths lose (C a):

```zig
const Tree = struct {
    package: []const u8,
    from: []const u8,
    name: ?[]const u8 = null,
    /// What the copy's path loses: win-64's `Library/` (flang/'s
    /// trees), or `Library/usr/` (usr/'s: their files sit in bin/).
    strip: []const u8 = "Library/",
};
```

and `build()` calls `conda.inDir(from, t.strip)`.

The Windows `usr` directory (A a, B a, C a, F a), after `binutils` in
`windows_dirs` (the order only sets the summary's; Cr8):

```zig
/// A file of the env's Library/usr/bin/ or Library/bin/ in usr/bin/.
fn usrBin(comptime from: []const u8) Copy {
    return .{ .from = from, .to = "bin/" ++ comptime base(from) };
}

/// Every file of an m2 tool package's usr/bin (PHASE7 open point C a).
fn m2Tool(comptime package: []const u8) Tree {
    return .{ .package = package, .from = "Library/usr/bin/", .strip = "Library/usr/" };
}

.{
    .name = "usr",
    // The DLLs those import, one package each (PS's imports; every
    // other import is the system's): msys-2.0.dll makes
    // R_HOME/bin/toolchain the MSYS root (etc/fstab). pkg-config is
    // conda-forge's native build (MSVC) with its glib closure.
    // verify-toolchain.sh checks the closure.
    .copies = &[_]Copy{
        usrBin("Library/usr/bin/msys-2.0.dll"),
        usrBin("Library/usr/bin/msys-intl-8.dll"),
        usrBin("Library/usr/bin/msys-iconv-2.dll"),
        usrBin("Library/usr/bin/msys-pcre-1.dll"),
        usrBin("Library/usr/bin/msys-gmp-10.dll"),
        usrBin("Library/usr/bin/msys-mpfr-6.dll"),
        usrBin("Library/usr/bin/msys-readline8.dll"),
        usrBin("Library/usr/bin/msys-ncursesw6.dll"),
        usrBin("Library/usr/bin/msys-gcc_s-seh-1.dll"),
        usrBin("Library/bin/pkg-config.exe"),
        usrBin("Library/bin/glib-2.0-0.dll"),
        usrBin("Library/bin/iconv.dll"),
        usrBin("Library/bin/charset.dll"),
        usrBin("Library/bin/intl-8.dll"),
        usrBin("Library/bin/pcre2-8.dll"),
        usrBin("Library/bin/vcruntime140.dll"),
        // the pkgconf name (B39's note; PHASE7 open point F a)
        usrBin("Library/bin/pkgconf.exe"),
        usrBin("Library/bin/pkgconf-8.dll"),
    },
    .trees = &[_]Tree{
        m2Tool("m2-bash"),      m2Tool("m2-make"),  m2Tool("m2-coreutils"),
        m2Tool("m2-sed"),       m2Tool("m2-grep"),  m2Tool("m2-gawk"),
        m2Tool("m2-which"),     m2Tool("m2-findutils"),
    },
},
```

- `binutils/` already copies `vcruntime140.dll` for its own tools; the
  second copy is in another directory and recorded in `usr/SOURCES`.
- The copies go first and the trees after, so `usr/SOURCES` lists the
  DLL packages before the tool packages; the summary prints copy order
  (phase 6's X a). Recorded, no sort.
- `readRecords`: a tree's needle is its `from`'s last component, `bin`,
  which matches nearly every record: all are parsed on Windows, zig's
  included (its record lists 19,546 files). Correct (a second owner of
  any `Library/usr/bin/` file is still seen, phase 6's W a); its cost is
  the configure step's time on kappa, recorded in step 2 (risk 9). If it
  is over a few seconds, the needle becomes `usr/bin` with the separator
  in both forms (`usr\\\\bin`, `usr/bin`): a recorded follow-up, not
  planned.

`etc/` (D a), written, not copied, Windows only and never into the env:

```zig
// MSYS's mount table (PHASE7 open point D a): msys-2.0.dll in usr/bin/
// makes R_HOME/bin/toolchain the MSYS root, which reads etc/fstab. The
// lines are MSYS2's (m2-filesystem's, less its build-env /conda_bin
// line, which conda rewrites at install): drives at /c, no POSIX ACLs
// on created files, /tmp the user's TEMP. Not a copy: etc/SOURCES says
// so, with the file's sha256, and etc/ has no LICENSES/.
const fstab =
    "none / cygdrive binary,posix=0,noacl,user 0 0\n" ++
    "none /tmp usertemp binary,posix=0 0 0\n";
```

`build()` writes `etc/fstab` and `etc/SOURCES` (`written: r-zig's
toolchain build (zigbuild/toolchain/build.zig), MSYS's mount table for
usr/bin's tools` then `file: fstab -> fstab <sha256 of fstab>`, the
`file:` line in the form verify-toolchain.sh reads) when `os ==
.windows and !prefix_is_env`, and appends `etc/ (r-zig's fstab)` to the
summary.

Licences (E a): `installLicenses` keeps its rule, with one fallback:
when `info/licenses/` is missing or empty and the package's name starts
with `m2-`, it installs the licence files of
`zigbuild/toolchain/m2-licenses/<name>/` (the build file's directory,
`b.path`), after checking that directory's `VERSION` line equals the
record's `<version> <build>`; a missing directory or another version
stops the build: "<name> <version> <build> ships no licence file, and
zigbuild/toolchain/m2-licenses/<name>/ does not hold its texts (its
README says how to take them from the package's MSYS2 source archive)".
`SOURCES`' block for such a package gets one line, `licenses: from <the
source archive's URL>` (writeSources: `Upstream.licenses_from`, read
from the directory's ORIGIN). Its `license:` line stays conda-meta's.

No code fetches or extracts the texts (Cr1): the 17 directories are
filled once by hand (step 2), and again only when an m2 pin moves,
which the VERSION check makes visible. The extraction differs per
package, which a program would have to special-case: msys2-runtime's
source archive holds a git clone (`git show <tag>:winsup/COPYING`, its
`CYGWIN_LICENSE`), some upstream tarballs inside are bzip2 or lzip,
which zig's std does not read, and m2-ncurses and m2-gcc-libs already
ship `Library/usr/share/licenses/<name>/` texts (ncurses' licence,
GCC's runtime exception), which complete the source's. The 17 packages:
m2-bash, m2-make, m2-coreutils, m2-sed, m2-grep, m2-gawk, m2-which,
m2-findutils, m2-msys2-runtime, m2-libintl, m2-libiconv, m2-libpcre,
m2-gmp, m2-mpfr, m2-libreadline, m2-ncurses, m2-gcc-libs (GCC's source,
about 90 MB, once).

Summary line and its test expectation per step 2.

### zigbuild/toolchain/conda.zig (step 2)

- `inDir(path, strip)`: `path[strip.len..]` when it starts with
  `strip`, else `path` (flang/'s callers pass `"Library/"`; its doc
  comment names both uses).
- `Upstream` gains `licenses_from: ?[]const u8 = null`; `writeSources`
  prints `licenses: from <url>` after `feedstock:` when set.
  verify-toolchain.sh's records awk ignores the line (it counts only
  `source:` and `feedstock:`), so it needs no change for it.
- Tests: `inDir` (three cases); `under` with an m2-shaped record (paths
  with `\`, `Library\usr\bin\egrep` a script, `Library\usr\share\...`
  left out); `writeSources` with `licenses_from` (the line's place).

### zigbuild/toolchain/m2-licenses/ (step 2; open point E a)

New: one directory per m2 package (17), each with its licence files,
`VERSION` (`<version> <build>`) and `ORIGIN` (the source archive's URL
and sha256 from the recipe, each file's path inside it and its sha256,
and, where the texts name another licence than conda-meta's
`license:`, one line saying so: expected for msys2-runtime, whose
Cygwin sources carry LGPL-3.0 with Cygwin's linking exception where
conda says GPL-3.0-or-later, and for m2-libintl, gettext's libintl
being LGPL where conda says GPL-3.0-or-later; the texts decide, Cr2),
and a README.md: what these are, that the m2 packages
ship no licence file, and the steps per package (download, sha256,
which files, the git and bzip2/lzip cases). About 0.6 MB of text. No
code (Cr1).

### scripts/env.sh (step 2)

`group_dirs`: `build-tools) echo "usr etc binutils" ;;` and its comment
(etc: Windows' MSYS mount table, phase 7).

### scripts/verify-toolchain.sh (step 2; open point O a)

- Header: "Every file in it is a third-party file copied unchanged ...,
  except etc/fstab (Windows), r-zig's own MSYS mount table (PHASE7 open
  point D)"; the closures bullet gains "Windows: usr/bin/'s tools find
  their DLLs beside them".
- The records loop needs no change for `etc/` (its SOURCES has no
  `package:` block and one `file:` line, so no `LICENSES/` is asked and
  fstab is a checked file) — confirmed by step 2's negative case.
- New Windows block after the OpenMP check (O a):
  - `etc/fstab` is exactly build.zig's two lines (CR stripped);
  - each of B39's names and pkg-config's is in `usr/bin/` as an `.exe`
    (`sh bash make sed grep gawk awk which find xargs pkg-config` and
    coreutils' `basename rm cp mv mkdir cat tr sort uname chmod ln ls
    expr touch head tail wc env printf mktemp test [`; `pkgconf` with F
    a);
  - each of them runs `--version` (`[`: `[ 1 = 1 ]` through sh) with
    PATH = System32 alone, from a scratch directory, exit 0;
  - `make --version`'s first line is `GNU Make <v>`, `<v>` SOURCES'
    m2-make version less its last `.N` (MSYS's release: 4.4.1.2 →
    4.4.1), as unix's verify-bundle checks make's; bash's version is not
    compared (m2's 5.2.037.2 against `BASH_VERSION`'s 5.2.37 would need
    a second rule; sh runs, Cr4);
  - with TEMP set to a scratch directory, `sh -c 'cd / && pwd -W'` is
    the tree's TC and `sh -c 'cd /tmp && pwd -W'` that directory
    (`cygpath -m -l` of the script's own MSYS, lower-cased, for both
    sides): the root and fstab in effect. TC's sh has no `cygpath`
    (msys2-runtime's programs are not copied), hence bash's `pwd -W`
    (Cr3).
  - printed: `== usr/ verified: <n> tools run with PATH = System32; make
    <v>; MSYS root <TC>, /tmp = TEMP`.

### zigbuild/patches/R-4.6.1/0010-config-make-check.patch (step 3; open point J a)

Header: the Windows paragraph (rcmdfn.c runs `sh config.sh`, so without
sh cmd.exe answered "'sh' is not recognized"; now rcmdfn.c runs rzig's
check first). A second hunk:

```diff
--- a/src/gnuwin32/front-ends/rcmdfn.c
+++ b/src/gnuwin32/front-ends/rcmdfn.c
@@ -529,8 +529,22 @@
     } else {
 	/* not one of those handled internally */
 	p = argv[cmdarg];
-	if (!strcmp(p, "config"))
+	if (!strcmp(p, "config")) {
+	    /* r-zig: the build tools, by rzig's check mode (feat-standalone-
+	       toolchain B26), before sh runs config.sh: with no sh, cmd.exe
+	       would only say that sh is not a command. rzig finds make and
+	       sh on this PATH (etc/Rcmd_environ's) and the binutils, or
+	       names the build-tools group on stderr and exits 127, which is
+	       then R CMD config's status. Its ok line goes to NUL: stdout is
+	       the value R CMD config prints. config.sh runs the same check
+	       again (patch 0010's other hunk, one script for every OS). */
+	    snprintf(cmd, CMD_LEN,
+		     "\"\"%s/bin/toolchain/gcc.exe\" --rzig-check=build-tools > NUL\"", RHome);
+	    int status = system(cmd);
+	    if (status) { freeRHOME(RHome); return status; }
 	    snprintf(cmd, CMD_LEN, "\"sh \"%s/bin/config.sh\"", RHome);
-	else if (!strcmp(p, "open"))
+	} else if (!strcmp(p, "open"))
```

(the context lines as R 4.6.1 has them; the hunk is made with `diff -u`
against the extracted source, not by hand). `RHome` has `/` and may
hold spaces: the inner quotes cover them, the outer pair is cmd.exe's,
as PROCESS_CMD's. `system()` returns cmd.exe's exit code, rzig's.

### zigbuild/patches/R-4.6.1/0014-rprofile-windows-tools-path.patch (new; step 3; open point I a)

Header: "Rprofile.windows: the build tools first on PATH in R sessions",
the reasons (unix's etc/Renviron does it for sessions; R's installer
build turns on the Rtools block in this file; install.packages' parallel
make and its compile-from-source decision ask `Sys.which("make")`), a
missing directory harmless. The hunk adds, after R's disabled
`setRtools45Path` block (Rprofile.windows:64-87, left as it is):

```r
## r-zig: the build-tools group's usr/bin first on PATH, as etc/Rcmd_environ
## puts it under R CMD (feat-standalone-toolchain B25, PHASE7 open point I):
## R's installer line, with R_HOME/bin/toolchain/usr/bin in Rtools' place.
## A missing directory (no build-tools group, a conda env) is harmless.
local({
    path <- Sys.getenv("R_CUSTOM_TOOLS_PATH",
                       file.path(R.home(), "bin", "toolchain", "usr", "bin"))
    Sys.setenv(PATH = paste0(path, ";", Sys.getenv("PATH")))
})
```

build.zig composes library/base/R/Rprofile from Common.R and
Rprofile.windows (line 3502-3506): no build.zig change.

### build.zig, R's (step 3; open point H a)

`rcmdEnviron` (2496-2549): two lines after RCFLAGS, and the doc
comment's bullets (UserNM; CMAKE_GENERATOR's "in a conda env m2-make,
first on PATH, and m2-bash's sh" becomes "the build-tools group's make
and sh (TC/usr/bin; in a conda env m2's, in Library/usr/bin)"):

```zig
"## r-zig: R CMD check reads objects' symbols with UserNM, else nm on PATH.",
"R_ZIG_NM=${R_HOME}/bin/toolchain/binutils/nm.exe",
"UserNM=${UserNM-${R_ZIG_NM}}",
```

### zigbuild/tools/rzig/groups.zig (step 3; open point K a)

- Doc (25-31): "build-tools holds unix make, and on Windows the
  binutils (B24); phase 7 adds Windows' usr/bin, until then sh and make
  on PATH." → "build-tools holds unix make, and on Windows sh, make and
  the tools R's makefiles run (usr/bin, phase 7) and the binutils
  (B24)."
- `text`, Windows build-tools: `"  standalone:  extract {s} where you
  extracted R\n"`; the first line unchanged ("sh, make, binutils and the
  tools R's makefiles run").
- The test's Windows build-tools expectation (line 224) the same.

### zigbuild/tools/rzig/check.zig (no code change; comment only)

`notOnPath`'s doc (239-246) keeps conda's m2 `Library/usr/bin` (B a
keeps m2-make there); its "The standalone tree and the wheel have none
there" stays true. If B (b) were taken, `notOnPath` would also look in
`<env>/Library/bin` (native make): not planned.

### scripts/verify-bundle.sh (step 4; open points F, H, I, M)

- Header (101-128): scenario 3's Windows sentence becomes "Windows: the
  group's usr/bin with PATH = bin\x64 + System32 (R CMD's Rcmd_environ
  and the session's Rprofile put it first), B39's tools through a
  configure.win and a Makevars rule, pkg-config (and pkgconf) through a
  configure.win and a local .pc file, R CMD check's nm (UserNM), and the
  same with Git for Windows' MSYS on PATH"; the "What phase 6 leaves to
  later phases" paragraph goes.
- Scenario 1, Windows (530-555): `path.R` also run in a session (`env -i
  ... PATH="$R_BINDIR:$sys32" "$RSCRIPT" --vanilla -e ...`): the first
  PATH entry is `<R_HOME>/bin/toolchain/usr/bin` (I a), and
  `R_CUSTOM_TOOLS_PATH`'s value when set. The echo line names both.
- Scenario 3, Windows (2101-2111): `CONDA_PREFIX` no longer required;
  `usr_bin="$TC/usr/bin"` checked for `make.exe` and `sh.exe`;
  `bt_path="$R_BINDIR:$sys32"`. The check's expected lines (2205-2209)
  are `make at $tc_m/usr/bin/make`, `sh at $tc_m/usr/bin/sh`, `binutils
  at $tc_m/binutils`.
- bt.R: the `if (!windows)` make block becomes every OS: `Sys.which("make")`
  is the group's (`make.exe` on Windows), `make --version` says SOURCES'
  m2-make version less its MSYS release (the shell computes `want` as
  verify-toolchain does and passes it, as unix passes `$make_version`).
  install.packages with Ncpus = 2 now takes R's parallel-make path on
  Windows too (the session finds make): the builders' assertions stay
  (btA rzig build, btLib and btRc make).
- New, after the binutils blocks (pass_zig set):
  - **btTools**: a package whose configure.win runs, through the
    group's sh, `awk`, `gawk`, `sed -n`, `grep -E`, `expr`, `tr`,
    `sort`, `uniq`, `cut`, `head`, `tail`, `wc -l`, `basename`,
    `dirname`, `uname`, `mktemp`, `cat`, `cp`, `mv`, `mkdir -p`, `ln -s`
    (MSYS's copy), `chmod`, `touch`, `ls`, `find . -name '*.c' | xargs
    grep -l`, `which sh`, `printf`, `env`, and writes `src/Makevars.win`
    with `PKG_CPPFLAGS = -DBTTOOLS=<a value each step contributed>` and
    a rule (`all: $(SHLIB) stamp` + `stamp: ; @touch $@ && rm -f $@`);
    its cleanup.win runs `find src -name '*.o' | xargs rm -f`. Installed
    with `R CMD INSTALL --preclean` (cleanup.win runs) under bt_path;
    asserted: the log says "btTools: configure.win: all tools ran", the
    builder is make (its Makevars rule), `f()` returns the value, it
    loads with PATH = `bin\x64` + System32.
  - **btPc**: a package whose configure.win runs `pkg-config --exists
    btpc && pkg-config --cflags btpc` and, with F a, `pkgconf --cflags
    btpc`, with `PKG_CONFIG_PATH` = the test's directory holding
    `btpc.pc` (`Cflags: -DBTPC=7`); asserted: both names answer, the
    package's `f()` returns 7 (and the configure.win's lines say which
    names ran).
  - **nm for R CMD check** (H a): `R CMD Rscript.exe --vanilla -e
    'stopifnot(any(tools:::read_symbols_from_object_file("t.o")[,
    "name"] == "tools_sym"))'` on tools.mk's `t.o`: under R CMD the
    object's symbols are read with UserNM, the group's nm.
  - **The clash** (M a): when `C:/Program Files/Git/usr/bin/msys-2.0.dll`
    exists (CI's windows-latest and kappa), btA, btLib, btTools and
    fcconf again, once with Git's `usr\bin` appended to bt_path and once
    first; each passes; the check under R CMD still names TC's make and
    sh. Elsewhere `cannot_check` (fails in CI, where Git always exists).
- The no-zig preflight block (2466-2500) uses `np_path="$bt_path"`:
  unchanged text, now PATH = `bin\x64` + System32.

### scripts/hermetic-check.sh (step 3; open point J a)

check.R (160-171): the `if (!windows)` around R CMD config goes; on
Windows `R.home("bin")/R.exe`; asserted on every OS: exit 127 (unix)
or non-zero equal to rzig's 127 (Windows, through cmd.exe), "Building
packages needs the r-zig build tools for R " in the output, and no line
with "is not recognized". The header's "unix: R CMD config CC fails"
becomes "R CMD config CC fails".

### scripts/compile-tree.sh (step 2; comment only)

Header (1-9): "in phase 3 openmp/, and unix usr/ or Windows binutils/" →
"openmp/, and the build-tools group's directories (unix usr/; Windows
usr/, etc/ and binutils/, phase 7)". contract, pkg-parity and stress on
Windows then run the group's `usr/bin` first under R CMD and in their
sessions, the env's `Library/usr/bin` after it (risk 8).

### recipe/recipe.yaml (steps 5, 7; open points F, N)

- r-zig-build-tools, win-64 run requirements: the comment "phase 7
  chooses native or m2 (B11)" and "win-64's interim set until phase 7
  chooses one for both channels (B11, B39)" become "the build-tools
  group's set on both channels (B11; PHASE7 open points A-C): MSYS2's
  userland from conda-forge's m2 packages and the native pkg-config
  (and pkgconf, F a); the standalone tree copies the same packages'
  files into R_HOME/bin/toolchain/usr/bin". The list itself is unchanged,
  plus `- pkgconf` (F a) after `pkg-config` with "B39's pkgconf name
  (s2's Makevars.ucrt)".
- The B28 comment ("On win-64, m2-make is the make R runs ... phase 7
  chooses native or m2 (B11)") ends "... no native make there (PHASE4
  Cg7; PHASE7 open point B a)".
- The summary: "(make; on Windows also sh, the MSYS2 tools, pkg-config
  and the MinGW binutils)" stays.
- The four `{zig,flang,openmp,usr,binutils}` globs (r-zig-slim's
  `files` exclusion, 351-352, and its `package_contents` `not_exists`,
  496-497) become `{zig,flang,openmp,usr,etc,binutils}`: the group
  directories' list, though the conda build never writes `etc/` (Cr5).
- `number:` and the history entry: N a (section 1), just before merging.

### recipe/test-build-tools.R (step 5)

Windows block: with `narrow(usr_bin = TRUE)`, each of verify-toolchain's
names resolves through `Sys.which` to this env (`Library/usr/bin` for
the m2 names, `Library/bin` for pkg-config and pkgconf), and `pkgconf
--version` runs (F a). The header's "the binutils, with the records of
where they come from" gains "and B39's tools from the env (B11)".

### recipe/test-preflight.R, recipe/test-compilers.R (step 3)

- test-preflight.R: a Windows block (no build tools in this env): `R CMD
  config CC` through `run_to` exits 127, its output starts a line with
  "Building packages needs the r-zig build tools for R " and has no "is
  not recognized" (J a).
- test-compilers.R (259-266): the comment "Windows: ... R CMD config is
  phase 7's item" goes and the `if (!windows)` with it: the same
  assertion on every OS.

### scripts/conda-consume.sh (step 5; open point P a)

A fourth environment, `toolchain = ["toolchain"]` with
`[feature.toolchain.dependencies] r-zig-toolchain = "*"`, and
`toolchain:test-toolchain.R` in the loop: "the same in a fresh conda env
with r-zig-toolchain" (TODO) on every conda-package leg.

### stress/stress.R, .github/workflows/stress.yaml, stress/README.md (step 6; open point L a)

- stress.R (374-380): `--msys-from-tree` (Windows only; elsewhere
  ignored with a note): the Windows PATH list without
  `Library/mingw-w64/bin` and `Library/usr/bin`; report.json's header
  records the flag.
- stress.yaml: input `msys_from_tree` (boolean, default false), passed
  as `--msys-from-tree` on the Windows runner only.
- README.md: one paragraph: what it leaves off PATH and why (the group's
  usr/bin alone answers, the env keeps cmake and the libraries).

### README.md (step 7)

- 47-49: unchanged wording, true now on both channels.
- 68-70 ("On Windows, Rtools is not needed ..."): adds "R puts the build
  tools first on PATH, in R and under R CMD; set R_CUSTOM_TOOLS_PATH to
  use others".
- 256-260 (the build-tools group): "GNU make on linux and macOS, which R
  puts first on its PATH; on Windows sh, make, the tools R's makefiles
  and configure.win scripts run (MSYS2's, from conda-forge's m2
  packages), pkg-config, and the MinGW binutils R's Makeconf names, with
  their DLLs". The Rtools45 sentence goes. The size: the Windows `.zip`
  measured in step 2.
- The extraction example: a Windows comment line `# + ...\toolchain\usr\bin\
  (sh, make, ...)`.

### pixi.toml (step 2 with F a; step 7 comments)

- F a (after the user's approval): `[target.win-64.dependencies]` gains
  `pkgconf = "==3.0.7"  # B39's pkgconf name (PHASE7 open point F a);
  3.0.7: the newest build older than two weeks on 2026-10-19`, then
  `pixi lock`; the new lock's sha256 is recorded in PLAN.md and every
  host's start record.
- Comments: none of pixi.toml's tasks change. `m2-*` comment (line 341
  ff) gains "the build-tools group copies m2-bash, m2-make,
  m2-coreutils, m2-sed, m2-grep, m2-gawk, m2-which and m2-findutils
  (phase 7)". `pixi lock --check` after.

### Files that need no change (checked)

- scripts/package-standalone.sh, unpack-toolchain.sh, verify-helpers.sh:
  generic over `group_dirs` and `group_ext`.
- zigbuild/tools/rzig/check.zig (code), pkgbuild.zig, pkgplan.zig:
  make and sh are found on PATH as before; the binutils by path.
- scripts/verify-tree.sh: the base's TC holds rzig only (B19); the R
  tree gains no file (0014 changes base/R/Rprofile's text).
- scripts/make-wheel.py, python/r_zig/__init__.py: no Windows wheel (C1
  later); the unix build-tools wheel takes `usr/bin/make` as before.
- .github/workflows/toolchain.yaml, build.yaml, build-r.yaml,
  upstream-zig.yaml: they upload, download and unpack what the scripts
  make (B31); the build-tools artifact grows by about 12 MB on win-64.
- recipe/build.sh: the conda build installs the toolchain into the env;
  `usr/` and `etc/` are skipped there by the existing rules.

## 4. Per channel: what changes

| channel | what changes | build number / version |
|---|---|---|
| standalone base (`R-<ver>-<flavor>-win-64`) | Rcmd.exe and R.exe (rcmdfn.c: R CMD config's check), base/R/Rprofile (the PATH line), etc/Rcmd_environ (UserNM), rzig (the text) | — (no release, B12) |
| standalone base, unix | rzig (the text function's Windows branch is in every rzig: its bytes change; unix's lines do not) | — |
| standalone compilers | nothing | — |
| standalone build-tools, win-64 (`.zip`) | gains `usr/` (140 files, 142 with F a; 24.9 MB raw) and `etc/fstab`; about +12.2 MB zipped | — |
| standalone build-tools, unix | nothing | — |
| conda r-zig-slim | win-64: Rcmd.exe, R.exe, Rprofile, Rcmd_environ; every OS: rzig | 8 → universe's newest + 1 (N a), with phases 4-6 |
| conda r-zig-build-tools | win-64: + `pkgconf` (F a); no file change | the same number |
| conda r-zig-compilers, r-zig-toolchain | nothing of their own; pin the new number | the same number |
| PyPI r-zig (unix) | rzig's bytes | no build number; nothing published (B12) |
| PyPI r-zig-compilers, r-zig-build-tools, r-zig-toolchain | nothing | — |

In a conda env the tools stay where conda puts them (`Library/usr/bin`,
`Library/bin`, activated PATH); `TC/usr/bin`, which Rcmd_environ and now
Rprofile name, does not exist there, as before (B30, B41: conda carries
copies only of what Makeconf.win names by path, the binutils).

## 5. The package choice table (B11, B39, B43; PS)

"copied" is what `TC/usr/bin` gets from the package; sizes in bytes.
All locked packages were checked against pixi.lock's sha256 (PS).

| tool / file | conda-forge package | in pixi.lock | .conda | copied | licence (about.json) | msys-2.0.dll |
|---|---|---|---|---|---|---|
| sh, bash (`sh.exe` = `bash.exe`, 2,333,443 each; `bashbug`) | m2-bash | 5.2.037.2 hc364b38_6 | 2,710,840 | 4,673,736 | GPL-3.0-or-later | yes |
| make | m2-make (B a) | 4.4.1.2 hc364b38_6 | 576,744 | 229,856 | GPL-3.0-or-later | yes |
| coreutils (107 files, `[` included; no `install` gap: `install.exe` is there) | m2-coreutils (A a) | 8.32.5 hc364b38_6 | 3,155,019 | 6,483,696 | GPL-3.0-or-later | yes |
| sed | m2-sed | 4.9.1 hc364b38_6 | 291,823 | 178,140 | GPL-3.0-or-later | yes |
| grep (`egrep`, `fgrep` scripts) | m2-grep | 1!3.0.7 hc364b38_6 | 293,845 | 213,766 | GPL-3.0-or-later | yes |
| awk, gawk (three identical .exe, `gawkbug`) | m2-gawk | 5.3.2.1 hc364b38_6 | 1,566,264 | 2,345,479 | GPL-3.0-or-later | yes |
| which | m2-which | 2.23.4 hc364b38_6 | 47,257 | 30,524 | GPL-3.0-or-later | yes |
| find, xargs (`locate.exe`, `updatedb`) | m2-findutils | 4.9.0.3 hc364b38_6 | 553,696 | 492,190 | GPL-3.0-or-later | yes |
| msys-2.0.dll | m2-msys2-runtime | 3.6.1.4 hc364b38_6 | 2,156,552 | 3,269,522 | GPL-3.0-or-later | is it |
| msys-intl-8.dll | m2-libintl | 0.22.5.1 hc364b38_6 | 78,711 | 111,181 | GPL-3.0-or-later | yes |
| msys-iconv-2.dll | m2-libiconv | 1.18.1 hc364b38_6 | 804,476 | 1,098,126 | LGPL-3.0-or-later | yes |
| msys-pcre-1.dll (grep) | m2-libpcre | 8.45.5 hc364b38_6 | 132,304 | 289,270 | BSD-3-Clause | yes |
| msys-gmp-10.dll (gawk, expr, factor) | m2-gmp | 6.3.0.1 hc364b38_6 | 445,326 | 596,041 | LGPL-3.0-or-later | yes |
| msys-mpfr-6.dll (gawk) | m2-mpfr | 4.2.2.1 hc364b38_6 | 451,302 | 652,490 | LGPL-3.0-or-later | yes |
| msys-readline8.dll (gawk) | m2-libreadline | 8.2.013.1 hc364b38_6 | 343,691 | 264,373 | GPL-3.0-or-later | yes |
| msys-ncursesw6.dll (readline) | m2-ncurses | 6.5.20240831.2 hc364b38_6 | 1,428,776 | 341,312 | MIT | yes |
| msys-gcc_s-seh-1.dll (gawk, sort, nproc) | m2-gcc-libs | 13.3.0.1 hc364b38_6 | 1,137,568 | 109,318 | GPL-3.0-or-later AND ... WITH GCC-exception-3.1 | yes |
| pkg-config | pkg-config | 0.29.2 hffdb5b9_1013 | 37,998 | 46,592 | GPL-2.0-or-later | no |
| glib-2.0-0.dll | libglib | 2.90.0 ha564072_0 | 4,572,716 | 1,359,872 | LGPL-2.1-or-later | no |
| iconv.dll, charset.dll | libiconv | 1.18 hc1393d2_3 | 694,899 | 1,099,264 | LGPL-2.1-only | no |
| intl-8.dll | libintl | 0.22.5 h5728263_4 | 96,669 | 224,256 | LGPL-2.1-or-later | no |
| pcre2-8.dll | pcre2 | 10.47 h8466c1e_1 | 993,241 | 603,648 | BSD-3-Clause | no |
| vcruntime140.dll | vc14_runtime | 14.51.36247 habf1de7_41 | 767,955 | 178,616 | LicenseRef-MicrosoftVisualCpp2015-2022Runtime | no |
| pkgconf (F a) | pkgconf | **to be added**: 3.0.7 h6a83c73_0 | 137,187 | 144,896 (+ vcruntime140, shared) | MIT | no |

- Total without pkgconf: 140 files, 24,891,268 bytes (PP), of which the
  eight tool packages' files 14,647,387, the MSYS DLLs 6,731,633,
  pkg-config's closure 3,512,248. Zipped with `etc/`: 12,167,956 (PP).
- Every m2 package lacks `info/licenses/` (PS): open point E. Every
  native package has them (pkg-config, libintl, pcre2: COPYING; libglib:
  LGPL-2.1-or-later.txt; libiconv: COPYING.LIB; vc14_runtime:
  LICENSE.{TXT,RTF,DOCX}; pkgconf: COPYING).
- Every m2 recipe's `finalized_sources` names the MSYS2 binary package
  and its MSYS2 source archive (with the conda-forge mirror), so `usr/SOURCES`
  names the source of each GPL binary (P3-C's rule holds); `feedstock:`
  is m2-binary-packages-feedstock with its commit (about.json's `extra`).
- Not chosen, and why (A, B):
  - native make 4.4.1 (`make`, hba3369d_3, in the lock): 17,111,844
    bytes as shipped, debug sections and 6,073 symbols; 287,744 stripped
    (a changed copy); imports the system only; with MSYS's sh it quotes
    as MSVCRT does and runs `echo` as a program; never run with R's
    makefiles here (B b, B c).
  - uutils-coreutils 0.0.20 (in the lock): one multicall binary as 73
    identical 8,334,848-byte names; no `touch`, `uname`, `chmod`, which
    Rmpfr's configure and R's makefiles use; 0.12.0 (not in the lock,
    2026-09-24): a 142,336-byte launcher per name that starts
    `coreutils.exe` as a second process, still no `chmod` (A b, A c).
  - m2-pkg-config 0.29.2.4: MSYS paths, 4.9 MB with its closure; not
    the one any test ran.
  - conda-forge has no native win-64 bash, sed, grep, gawk, which,
    findutils, coreutils (GNU), diffutils or busybox (PS §4), so
    msys-2.0.dll is in every option.

## 6. Tests per OS and CI

### What each scenario proves on Windows (verify-bundle, two passes)

| scenario | today (phase 6) | phase 7 |
|---|---|---|
| file lists | build-tools holds `binutils/` | `usr/`, `etc/`, `binutils/`, no overlap with the compilers or the base |
| 1. base alone | R CMD's PATH entry after bin\x64 is TC/usr/bin | also the session's first entry (I a); hermetic: R CMD config's 127 and text (J a) |
| 2. + compilers | unchanged | unchanged |
| 3. + build-tools | sh and make from the env's `Library/usr/bin` on PATH | PATH = `bin\x64` + System32: the group's sh and make (the check names them), `Sys.which("make")` and its version in a session, Ncpus = 2 through the session's make, every phase 6 block, btTools (B39's tools), btPc (pkg-config, pkgconf), R CMD check's nm, the clash with Git's MSYS |

### Per host

| host | runs |
|---|---|
| gamma (linux-64; implementer, owns `dist/`) | step 2: `toolchain-test` (both zigs), the m2 licence texts by hand (E a, once), linux `toolchain` + `verify-toolchain` + tree compared with phase 6's; step 3: `rzig-test` (both zigs), `build` with the new series (libR.so, bin/exec/R, base Rprofile equal to step 2's), `smoke`, `verify-tree`, `hermetic`; step 4: `verify-package` (default, both passes), minimal `verify-package`; step 6: stress.R parses, actionlint; step 7: the default chain end to end, minimal, `wheel` + `wheel-test`, `conda-package` + `conda-consume`, the upgrade test from `_8` (pixi, conda, micromamba), F a's re-lock (approved) |
| kappa (win-64; tester) — the runs that matter most | step 0: phase 6's `verify-package` as the reference (time); **step 1: the prototype** (MSYS root and fstab with and without, each tool alone, the check, phase 6's scenario 3 on the group, s3-set.R with the libraries env: Rcpp, data.table, minqa, pak, ps, glue, Rmpfr, units, systemfonts, `has_rtools(debug = TRUE)`; the clash with Git's MSYS before and after where kappa has Git; native make and uutils recorded; R CMD config's count and time, the cold start, an R_HOME with a space); **step 2**: `toolchain` (time), `verify-toolchain` (O; time), the licence fallback's stop, the negative cases, `package-toolchain` (zip size), `unpack-toolchain`, `compile-tree`; **step 3**: `build`, `hermetic`, the session PATH, `R_CUSTOM_TOOLS_PATH`, UserNM; **step 4: `verify-package`** both passes, upstream one-zig pass, the negative run; **step 5**: `conda-package`, `conda-consume` (four envs), s3-set.R in the toolchain env (activated and narrowed); step 6: a local `--msys-from-tree g3` stress run; step 7: the upgrade test from `_8` (pixi, conda); step 8: the full round on the final code, plus `contract` and `pkg-parity` (now with TC/usr/bin first, risk 8) |
| omicron (osx-arm64; tester) | step 8 only: `rzig-test` (both zigs), `toolchain` + `verify-toolchain` (flang trees through `Tree.strip`; tree equal to phase 6's), `build`, `package-toolchain`, `verify-package` (both passes), `conda-package`, `conda-consume`, the upgrade test from `_8` (pixi). osx-64 under Rosetta: not needed (section 1) |
| CI, the PR | core tier: windows-latest's toolchain (build-tools zip with usr/), build-r (verify-package: scenario 3 on the group, the clash block with the runner's Git MSYS, which windows-latest always has; watch for the MSYS spawn hangs, 90-minute guard), and the other four default legs; conda-package's five legs (the recipe changed; win-64's r-zig-build-tools with pkgconf; conda-consume's four envs); then `full-ci` (every leg), the `upstream-zig` label (0010, 0014 and rzig changed); the stress dispatch (L a). Record each Windows job's time against phase 6's |
| CI, main after merge | nothing publishes until the user sets `CONDA_PUBLISH` and dispatches (N a); then the publish of `_N` and section 1's checks |

Every host records the pixi.lock sha256 (fbb64b7ba4e31e45..., or F a's
new lock's) and `git diff | sha256sum` at start and end.

## 7. Measurements to record (PLAN.md's phase 7 record)

| what | where | per |
|---|---|---|
| `usr/` files and raw size; `etc/`; the build-tools `.zip` size and member count, against phase 6's | `verify-toolchain`'s and `package-toolchain`'s lines | kappa, windows-latest (PP's 24,891,268 and 12,167,956 to compare) |
| the toolchain step's time with usr/ (and its configure step: readRecords with the `bin` needle, risk 9) | wall time, CI step time | kappa, windows-latest |
| verify-toolchain's time with usr/ (each tool's `--version`) | wall time | kappa, windows-latest |
| verify-package's scenario 3 time, against phase 6's (env tools) | wall time per pass | kappa, windows-latest |
| the MSYS root, `/tmp`, drive prefix and ACLs with and without `etc/fstab` | step 1's runs | kappa |
| the first configure.win's MSYS start (`R CMD sh -c true`, cold and warm) | wall time | kappa |
| the clash runs: pass or fail, messages, times; Git's msys-2.0.dll version; Rtools45 present or not | step 1, verify-bundle's block | kappa, windows-latest |
| native make and uutils in the prototype (recorded, B, A) | step 1 | kappa |
| `pkgbuild::has_rtools(debug = TRUE)`, `check_build_tools(debug = TRUE)` with the group | step 1 | kappa |
| the stress dispatch with `--msys-from-tree`: the 30 rows' builders and results against 38569895172 | its report | windows-latest |
| the m2 licence texts: files per package, archive sizes and sha256, licences that differ from conda's metadata | `ORIGIN` files | gamma |
| `R CMD config` calls before one configure.win, and their time with J a | step 1 (Cr12) | kappa |
| the first `R CMD sh -c true` after extraction, and the second (Defender) | step 1 (Cr18) | kappa, windows-latest (verify-bundle's first block's time) |
| `R.home()` and `UserNM` under an R_HOME with a space; R CMD check's symbol tables there | step 1 (Cr11) | kappa |

## 8. Risks

1. **msys-2.0.dll from two installations in one process tree.** A user's
   Rtools or Git for Windows `usr\bin` on PATH, or a conda env's
   `Library\usr\bin` (the dev env, compile tree runs), is another MSYS
   installation (msys2-runtime keys its shared memory by the DLL's
   path). Under R CMD and in sessions `TC/usr/bin` comes first, so a
   name TC has always runs TC's; a name only the other has (diff, perl,
   tar) runs as a separate MSYS process tree, which works as a native
   child but loses MSYS's process semantics with its parent. Tested on
   kappa and windows-latest (M a). Mitigation if it fails: none planned
   beyond R_CUSTOM_TOOLS_PATH; recorded and back to the user.
2. **windows-latest's MSYS spawn hangs** ("cygheap read copy failed",
   2026-09-20). Scenario 3 now spawns from `TC/usr/bin` on the runner;
   the 90-minute guard stays; a hang is re-run once and recorded.
3. **Without `etc/fstab`** (D b), `/tmp` would be `TC/tmp` (missing, and
   not writable under Program Files) and MSYS would write POSIX ACLs on
   files the tools create in a user's library. With D a, a wrong fstab
   line breaks every tool: verify-toolchain checks its exact content and
   the root and `/tmp` in effect.
4. **The m2 licences** (E): the m2 packages ship no licence file. E a
   keeps texts in the repository, taken by hand and refreshed when an m2
   pin moves; a re-lock that moves an m2 build without new texts stops
   the Windows toolchain build (by design: VERSION differs), in CI too.
   The texts can name another licence than conda's metadata
   (msys2-runtime, m2-libintl expected, Cr2): `license:` stays
   conda-meta's, ORIGIN records the difference, and PLAN's record lists
   it; no conda-forge report is filed (open items).
5. **The pkgconf name has no working caller** (SS §2): s2's
   Makevars.ucrt is the only one, and s2 fails on Windows for its
   abseil either way (packages.tsv). F a ships it for the user's
   decision of round 1; it is tested only by btPc.
6. **Rprofile's PATH line in every session** (I a): GNU `find`, `sort`
   and the rest come before Windows' `find.exe` and `sort.exe` for
   `system()` calls in R code, as with R's own installer and Rtools.
   Recorded in README.
7. **R CMD config runs rzig's check twice on Windows** (J a): rcmdfn.c's
   and config.sh's, one rzig start more per call (tens of milliseconds).
   install.R calls `R CMD config` several times before each
   configure.win, so a configure package pays it several times: step 1
   measures the count and the time (Cr12); if it is over a second per
   package, J (b) is put back to the user.
8. **Dev tests on Windows change what they run**: the compile tree
   gains `usr/` and `etc/`, so contract, pkg-parity and stress (tree)
   run the group's tools first, the env's after. A tool the group lacks
   is found in the env and not seen: the stress option (L a) is the
   check without that fallback.
9. **readRecords' `bin` needle** parses nearly every conda-meta record on
   Windows (zig's 19,546-file record included): the configure step's
   time is measured; a narrower needle is a follow-up.
10. **Long or space-holding install paths**: R's makefiles need an
    R_HOME without spaces (its 8.3 form where the volume has 8.3 names),
    as with Rtools; not new. New with H a: sotools.R puts `UserNM`
    unquoted into `system()`, so an R_HOME with a space in its long form
    breaks R CMD check's symbol tables unless R gives `R_HOME` in its 8.3
    form there; step 1 records which (Cr11), and if it breaks, H (a)'s
    line names the 8.3 path or H goes back to the user.
11. **The bump and the race**: another build published before phase 7
    merges moves the number (N a checks just before merging). The
    upgrade test from `_8` covers four phases' file moves at once.
12. **Native pkg-config's glib closure** (3.5 MB) carries LGPL DLLs:
    their sources are in `usr/SOURCES` (conda's recipes), as for the
    binutils' zstd; relinking is possible (DLLs).
13. **The first run after extraction** (Cr18): Defender scans the 140
    new executables and DLLs the first time they start, which can make
    the first configure.win slow (and windows-latest's first scenario 3
    block); step 1 measures cold and warm `R CMD sh -c true`.

## 9. Overlap with other pending work

- **Phases 4, SHLIB, 5, 6** (uncommitted, the baseline): shared files
  in section 1; their PRs merge first.
- **The other agent's build-number revert and CONDA_PUBLISH gate**:
  recipe.yaml's "8 stays" entry is replaced by N a's entry; build.yaml's
  publish comment and pixi.toml's and README's notes say "until phase
  7's bump merges", which stays true until then and is reworded in the
  records after the publish ("paused 2026-10-19 to <date>").
- **C1-C3** (Windows minimal and the Windows wheel): after phase 7; the
  wheel's r-zig-build-tools will take `usr/` and `etc/` from the tree.
- **Phase 8**: no shared file but README and PLAN.md.
- **B24's follow-up** (dlltool, as through rzig): `binutils/` only.
- **The extras group** (cmake): the stress dispatch records which rows
  needed the env's cmake.
- **feat-shlib-rzig-build's J dispatch**: its PLAN.md names 38569895172
  as the baseline, but that run is g3 g4, not g1 g2 (SS): a records
  fix there (section 10).

## 10. Records (step 7) and the stale references to fix

**PLAN.md: "Phase 7 record"** (new subsections under "### Phase 7"):
what changed and why (the set, A-C; fstab, D; licences, E; pkgconf, F;
the re-scope, G; UserNM, H; Rprofile, I; R CMD config, J; the text, K;
the stress option, L; the clash, M; the bump, N); the answers to section
11, each recorded as the user gives it; the measurements (section 7);
the hosts' results; CI's run IDs; "pending CI" until the push's runs
pass.

**Decision records**:
- B11: "What it means" gains the phase 7 outcome: native first held for
  pkg-config (and pkgconf); make and coreutils come from m2 packages,
  with the reasons (A, B) and step 1's recorded native make and uutils
  runs; "Whether make.exe is stripped" answered: no native make, so
  nothing to strip (m2's has no debug sections).
- B25: "The phase 7 prototype settles whether Rprofile.windows needs
  the same line" → answered by I.
- B39: the stress re-scope (G): sh, make, coreutils, sed, awk and
  pkg-config ran in the suite's Windows rows; grep in Rmpfr's autoconf
  configure; find and xargs only in cleanup.win under --preclean or R
  CMD build; which in no row; the list stays.
- B43: pkg-config ships in usr/bin; pkgconf per F; nm for R CMD check
  through UserNM (H); objdump and gcc-nm unchanged.
- Facts (631-645): "Whether conda-forge has native win-64 builds of the
  others is phase 7's check" → PS §4's answer (none for bash, sed,
  grep, gawk, which, findutils, coreutils, diffutils, busybox; native
  make and uutils exist, why not taken); uutils 0.0.20 is a 73-name
  multicall without touch, uname, chmod.

**TODO.md, "## Phase 7"**: tick the boxes; "verify-tree checks the
closure" → verify-toolchain; the re-scope item's "winshlib.mk's silent
def and link recipe runs nm, sed, basename and rm in every make row" →
"nm and sed in 25 rows, basename in 27, rm in 26 (SS); cp in
RcppParallel; Rmpfr's autoconf configure: awk, grep, expr, cat, mkdir,
mv, tr, sort, uname, chmod, ln, ls; R CMD config before every
configure.win"; the Later item "pkgbuild's Windows `has_rtools()`"
gains step 1's result.

**feat-shlib-rzig-build PLAN.md**: the J dispatch's baseline note:
38569895172 is g3 g4; g1 g2's baseline is another run (recorded, not
re-run here).

**Stale references** (code and docs):
- zigbuild/toolchain/build.zig:33 "Windows' usr/bin comes in phase 7."
- zigbuild/tools/rzig/groups.zig:28-29 and :133, :224 (K a).
- scripts/verify-bundle.sh:126-128, :2101-2111 (the phase 7 notes).
- recipe/recipe.yaml: "phase 7 chooses native or m2 (B11)", "win-64's
  interim set until phase 7 chooses", "phase 7 adds the pkgconf name".
- recipe/test-compilers.R:259-262 ("R CMD config is phase 7's item").
- README.md:260 (Rtools45's usr/bin), :319 (CONDA_PUBLISH: after the
  publish).
- build.zig's rcmdEnviron doc (CMAKE_GENERATOR's m2 sentence).
- scripts/compile-tree.sh header.
- pixi.toml:204, :605 ("until phase 7's bump merges": after the
  publish).

## 11. Open points (each with the recommended option ★)

**A. coreutils: which package** (B11: native first, m2 where needed).
- (a) ★ m2-coreutils 8.32.5 (in the lock): all 107 names, MSYS like the
  shell that runs them, the set every Windows test ran.
- (b) uutils-coreutils 0.0.20 (in the lock), B11's native build: 73
  names, each an 8,334,848-byte copy of one multicall binary (zip
  stores each: about 250 MB raw); no `touch`, `uname`, `chmod`.
- (c) uutils-coreutils 0.12.0 (a re-lock): 92 launcher names that start
  `coreutils.exe` again; still no `chmod`.
- Reason for (a): the native builds lack tools R's makefiles and
  Rmpfr's configure run; m2 is "needed" in B11's sense.

**B. make, and whether it is stripped** (TODO: "Decide whether make.exe
is stripped").
- (a) ★ m2-make 4.4.1.2 (229,856 bytes, no debug sections: nothing to
  strip), the make every Windows test and CMake's "MSYS Makefiles" ran.
- (b) conda-forge's native make 4.4.1, stripped (17,111,844 → 287,744
  bytes): a changed copy, so SOURCES records the strip and
  verify-toolchain checks the stripped sha256; it quotes for MSVCRT and
  runs `echo` as a program; recorded on kappa in step 1 only.
- (c) native make as shipped (17.1 MB).
- Reason for (a): msys-2.0.dll ships anyway (sh, sed, grep, gawk), so
  the native make saves no runtime and adds an untested make; B11's
  "native first" is set aside for make with this reason, recorded.

**C. What usr/bin holds of each tool package.**
- (a) ★ every file of the eight packages' `Library/usr/bin/` (124
  files, 14.6 MB) plus the nine MSYS DLLs and pkg-config's closure: a
  rule by package, like phase 6's flang trees.
- (b) B39's names only, listed in build.zig (52 files: 5.7 MB less raw,
  2.6 MB less zipped; PP2, Cr9).
- Reason for (a): configure.win scripts call coreutils beyond any list
  (Rmpfr: 12 names), and a list would be edited after each failure.

**D. MSYS's mount table.**
- (a) ★ `TC/etc/fstab`, two lines written by the toolchain build (`/`
  cygdrive with `noacl`, `/tmp` usertemp), in the build-tools group, as
  conda's m2-filesystem has them.
- (b) None: drives at `/cygdrive/c`, `/tmp` = `TC/tmp` (missing; not
  writable under Program Files), POSIX ACLs on created files.
- Reason for (a): the same MSYS behaviour as Rtools and a conda env, and
  an install R cannot write to keeps working; step 1 records (b)'s
  failures.

**E. Licence texts of the m2 packages** (none ships `info/licenses/`).
- (a) ★ The texts from each package's MSYS2 source archive (its
  recipe's own `source:` entry, sha256-checked), taken out once by hand
  into `zigbuild/toolchain/m2-licenses/<package>/` with VERSION and
  ORIGIN and committed, no code (Cr1); build.zig uses them only for an
  m2 package with no `info/licenses/`, and SOURCES says where they come
  from.
- (a2) The same texts, fetched and extracted by a zig step of the
  toolchain build (std.http, zstd, tar): code for 17 one-off cases (a
  git clone in msys2-runtime's archive, bzip2 and lzip tarballs std
  cannot read), run only when an m2 pin moves (Cr1).
- (b) A generated NOTICE per package (its SPDX licence and its source
  archive's URL), no text: simplest, but GPLv3 §4 asks for the licence
  text with the program.
- (c) You ask conda-forge's m2-binary-packages-feedstock to ship
  `info/licenses/`, then a re-lock; (a) until that build exists.
- Reason for (a): exact texts with a checked origin, no network in CI,
  no new code, and the build still stops for any package without a
  licence.

**F. The `pkgconf` name** (round 1's decision 16; PHASE4 F a).
- (a) ★ conda-forge's `pkgconf` 3.0.7 on both channels: the tree copies
  its `pkgconf.exe` and `pkgconf-8.dll`, conda's r-zig-build-tools
  depends on it; `pkg-config` stays pkg-config 0.29.2. Needs
  `pkgconf ==3.0.7` in pixi.toml's win-64 table and a re-lock: **your
  approval**.
- (b) The tree copies `pkg-config.exe` again as `pkgconf.exe`; conda
  depends on `pkgconf` (recipe only, no re-lock): two programs behind
  one name across the channels.
- (c) No pkgconf name for now: its only caller (s2) fails on Windows
  for its abseil either way; no re-lock; the channels identical.
- Reason for (a): decision 16 on both channels with one rule (a name is
  a conda-forge package's file), 0.3 MB.

**G. B39's list after the stress re-scope** (SS).
- (a) ★ Unchanged: sh, make, coreutils, sed, grep, gawk, which,
  findutils, pkg-config.
- (b) Without which (no row calls it; 30 KB).
- Reason for (a): your list (B39); find and xargs serve cleanup.win under
  `--preclean` and R CMD build, and which costs 30 KB.

**H. nm for R CMD check** (sotools.R: `UserNM`, else `nm` on PATH).
- (a) ★ Rcmd_environ: `UserNM=${UserNM-${R_ZIG_NM}}`, the group's
  `binutils/nm.exe`, as RC for windres.
- (b) A second nm (with its zstd.dll and vcruntime140.dll) in usr/bin.
- (c) Nothing: R CMD check warns "this requires 'nm' to be on the PATH"
  and skips objects' symbol tables.
- Reason for (a): one line, the existing nm, and only R CMD's
  environment.

**I. Rprofile.windows** (B25: "if the tests need it").
- (a) ★ Patch 0014: the session PATH starts with
  `R_CUSTOM_TOOLS_PATH` or `TC/usr/bin`, as Rcmd_environ under R CMD,
  unix's etc/Renviron, and R's own installer build (Rtools' block).
- (b) No: R CMD only; in a session `Sys.which("make")` is "", so
  install.packages never takes the parallel make and `type = "both"`
  never compiles from source.
- Reason for (a): R behaves the same in a session and under R CMD on
  every OS.

**J. R CMD config without the build tools.**
- (a) ★ rcmdfn.c runs `gcc.exe --rzig-check=build-tools` before `sh
  config.sh`, always (patch 0010's second hunk); config.sh's check stays
  (twice on Windows).
- (b) rcmdfn.c runs it only when no `sh.exe` is on PATH.
- (c) (a), and config.sh's check becomes unix-only.
- Reason for (a): the fewest lines, the same order as unix (the check
  first, `--help` included), one script for both OSes.

**K. rzig's Windows build-tools line.**
- (a) ★ "extract R-<ver>-win-64-build-tools.zip where you extracted R".
- (b) (a) plus "or set R_CUSTOM_TOOLS_PATH to Rtools45's usr/bin (the
  binutils still come from the archive)".
- Reason for (a): the archive is the whole answer; R_CUSTOM_TOOLS_PATH
  is in README.

**L. The stress evidence for the re-scope.**
- (a) ★ stress.R's `--msys-from-tree` (the env's `Library/usr/bin` and
  `Library/mingw-w64/bin` off PATH on Windows) and one windows-latest
  dispatch of g3 g4 with it on the PR.
- (b) No stress change: verify-bundle's scenario 3 and kappa's step 1
  set only.
- Reason for (a): the only run of all 30 Windows tier-3 rows with B39's
  tools alone.

**M. The clash tests.**
- (a) ★ Git for Windows' `usr\bin` before and after R's entries, on
  kappa and in verify-bundle (windows-latest has it); Rtools45 wherever
  it is installed, recorded where it is not.
- (b) (a), and you install Rtools45 on kappa for the test (a 461 MB
  installer on a test server).
- Reason for (a): Git's MSYS is on every GitHub runner and most user
  machines; Rtools is the same runtime family.

**N. The build number and publishing** (your decision of 2026-10-19).
- (a) ★ Phase 7's PR takes the number after universe's newest, as its
  last commit before merging, with one history entry for phases 4-7;
  after the merge you set `CONDA_PUBLISH` and dispatch build.yaml on
  main.
- (b) A one-line PR right after phase 7 merges takes the bump.
- Reason for (a): CI's conda legs test the number that publishes, and
  one PR less.

**O. verify-toolchain's checks of usr/ and etc/.**
- (a) ★ Each B39 name present and running with PATH = System32; make's
  version against SOURCES (less MSYS's release; bash's not compared,
  Cr4); the root and `/tmp` in effect (bash's `pwd -W`, Cr3); fstab's
  exact lines.
- (b) The generic closure and records checks only.
- Reason for (a): a copy that does not start (a DLL of the wrong
  package, a missing runtime) is caught where the tree is built.

**P. conda-consume and r-zig-toolchain.**
- (a) ★ A fourth environment with r-zig-toolchain running
  test-toolchain.R through activation, on every conda-package leg.
- (b) rattler-build's own test of r-zig-toolchain only.
- Reason for (a): TODO's "in a fresh conda env with r-zig-toolchain",
  through the PATH a user's activation gives.

**Q. The hand-over diff.**
- (a) ★ `phase7-only.diff` against the step-0 baseline, checked by
  applying it to a second copy (phase 6's S a), and the commands for you
  with no trailer.
- (b) One cumulative diff against main.
- Reason for (a): phase 7's PR reviews alone after phase 6's merges.

### Open items for you (none filed, nobody contacted)

- F (a) needs your approval of a dependency and lock change
  (`pkgconf ==3.0.7` on win-64); without it, F (c) or F (b).
- E (c), if you want it: an issue on conda-forge's
  m2-binary-packages-feedstock asking for `info/licenses/`.
- M (b), if you want it: Rtools45 on kappa.
- After the merge: `gh variable set CONDA_PUBLISH --body true` and
  `pixi run ci-trigger` (N a).
- Phase 7 ends "pending CI": the PR's runs (full-ci, upstream-zig, the
  stress dispatch) happen after your push.

## 12. Critique points not taken

CRITIQUE.md lists every point of the self-critique and where it landed
(Cr1-Cr18). Not acted on, with the reason:
- **Copy msys2-runtime's `cygpath.exe` too** (configure scripts written
  for MSYS2 sometimes call it): no row of the three stress runs or of
  R's makefiles calls it; it is one more program from a package the
  tree takes a DLL from. It joins if the stress dispatch (L a) or a user
  shows a caller; B39's list is the user's.
- **pkgconf for both names, dropping pkg-config's glib closure (3.2
  MB)**: every pkg-config row of the stress runs ran pkg-config 0.29.2,
  and conda's r-zig-build-tools would still need the pkg-config package
  for its name (pkgconf ships only `pkgconf.exe`), so the channels would
  differ. F keeps pkg-config.
- **J (b) to avoid the double check**: kept (a) with a measurement and
  a threshold (risk 7) instead of choosing on a guess.
