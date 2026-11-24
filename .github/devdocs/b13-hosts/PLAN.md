# b13-hosts: host checks for build 13

Worktree from main 7e3648e (build 12's source; build 12 published by
build-r run 45381914199). Items: H3, H4, H5, H6, CI8, CI10, CI12, CI13
(chore-release-12/BACKLOG.md). H2 was done in batch 1; H1 is b13-rzig's.
No repo source file changes. Records annotated: feat-zig-017/ZIG-FETCH-CACHE.md
(status row), feat-r-home-link-objects, feat-winarm-gaps, feat-shlib-rzig-build,
feat-config-rzig (dated update lines).

T = /data/gamma/luciorq/workspaces/temp/r-zig-pixi. Logs of every run below
are in T/scratch-b13-hosts (kappa/, omicron/, logs/, fetch-repro-delta.log).

## Goal

Run the host items against the published build 12 (fresh pixi env per
host, universe listed before conda-forge) and read the CI logs, then
record what holds, what does not, and what is left over on the hosts.

## Decisions

| id | question | options (chosen in bold) | reason | who |
|---|---|---|---|---|
| D1 | H3: kappa has Rtools45 installed (C:\rtools45, RTOOLS45_HOME, registry). How to test "compilers only"? | (a) as is; **(b) as is, then again with RTOOLS40..45_HOME pointing at missing dirs**; (c) uninstall Rtools | (a) alone answers from Rtools (F1). (c) changes the host | default, 2026-11-24 |
| D2 | H3: pkgbuild without the build tools | **(a) CRAN's win.binary for R 4.6 into a private library**; (b) source | processx and ps need make; the item is about r-zig-compilers alone | default, 2026-11-24 |
| D3 | CI12 (b) on Windows: nloptr does not use cmake there | **(a) also build a small CMake project with R's CC and the build-tools make**; (b) only `cmake --version` | shows cmake driving rzig, which nloptr cannot show on Windows (F6) | default, 2026-11-24 |
| D4 | CI10: against what | **(a) the dev tree at 7e3648e on omicron, its toolchain tree from the publish run's toolchain-macOS-ARM64 artifact (as CI's unpack-toolchain)**; (b) the conda env as a fake compile tree | pkg-parity needs the compile tree and the base tree layout; (b) would need edits to the script. 7e3648e is build 12's source | default, 2026-11-24 |
| D5 | omicron cannot resolve hostnames with conda's curl (F25) | **(a) download with /usr/bin/curl and install from files**; (b) fix the host's DNS | no host changes; recorded instead | default, 2026-11-24 |
| D6 | H6 (b) on omicron | (a) run there too; **(b) delta only** | the defect is in zig's package fetch code, not OS-specific in the record; omicron's resolver issue (F25) would confound it | default, 2026-11-24 |
| D7 | own scratch dirs | **deleted after the runs** (kappa rz-b13-hosts 9.8 GB, omicron ~/rz-b13-hosts 6.3 GB, delta ~/rz/scratch-b13-hosts); logs copied to T/scratch-b13-hosts first | kappa had 32 GB free | default, 2026-11-24 |

## Findings

Envs: kappa (win-64) r-zig-slim 4.6.2 hb04b5bb_12, r-zig-compilers
h6a289e5_12 (zig 0.17.1 bd21d8f_0, flang-zig 23.1.5); omicron (osx-arm64)
r-zig-slim ha6b6fea_12, groups h3ae0fae_12, cmake 4.4.5 (conda-forge).

### H3: pkgbuild::has_rtools(debug = TRUE), r-zig-slim + r-zig-compilers (kappa)

- F1 (V) As kappa is set up, it answers from Rtools, not from r-zig:
  `Found in Rtools 4.5 installation folder`, TRUE (kappa/run.log).
- F2 (V) With RTOOLS40..45_HOME pointing at missing dirs: `Scanning R CMD
  config CC... cc_path: <env>/Library/lib/R/bin/toolchain/gcc.exe ...
  Found compatible gcc from R CMD config CC`, TRUE. has_compiler,
  has_build_tools and check_build_tools compile foo.c through rzig
  (`Rcmd.exe SHLIB foo.c`, gcc.exe is rzig) and print `Your system is
  ready to build packages!`; rtools_path() is character(0);
  with_build_tools(1 + 1) is 2 with no warning (kappa/k2.log,
  pkgbuild 1.4.8). Done looks like: met.

### CI12 (a): R CMD config from cmd.exe, R_HOME with a space (kappa)

- F3 (V) Activated (`pixi shell-hook -s cmd`, then `call R CMD config
  CC`): rc 0, `.../bin/toolchain/gcc.exe`; CXX17 gives g++.exe. With no
  arguments: the usage text (Windows lines included) and rc 1, as R's
  own script (rzig config.zig:103-106). From a .bat, R.bat needs `call`,
  or the batch file stops after it (run.log: the lines after the first
  R CMD did not run).
- F4 (V) Not activated, `Library\lib\R\bin\R.exe` and `bin\x64\R.exe`
  exit -1073741515 (0xC0000135, STATUS_DLL_NOT_FOUND). R.dll imports
  libomp.dll, zlib.dll, libbz2.dll, liblzma.dll, zstd.dll, deflate.dll,
  pcre2-8.dll, icuuc78.dll and icuin78.dll from `Library\bin`
  (`objdump -p`, kappa/dll.log). With `Library\bin` first on PATH it
  works (rc 0). The same holds for any conda program on Windows; see
  Needs (proposal N3).
- F5 (V) Env under `%USERPROFILE%\rz-b13-hosts\sp ace\env`: R.home() is
  the 8.3 form `C:/Users/admin/RZ-B13~1/SPACE~1/env/PIXI~1/...`
  (normalizePath gives the long one with the space). R CMD config CC
  (activated, and not activated with Library\bin on PATH) rc 0; R CMD
  SHLIB of a C file rc 0, `.Call("hello")` is 42 (kappa/space.log,
  k2.log). 8.3 names are enabled on C: (`fsutil 8dot3name query C:`:
  volume state 0). On a volume with 8.3 names off, not tested (I: R then
  has the space in R_HOME).

### CI12 (b): extras group (omicron, kappa)

- F6 (V) `pixi add r-zig-extras` on r-zig-slim: cmake 4.4.5 on both;
  `cmake --version` rc 0 and R's `Sys.which("cmake")` is the env's on
  both. omicron: with r-zig-toolchain, nloptr 2.2.1 from source builds
  its bundled NLopt with the env's cmake (`using cmake via
  <env>/bin/cmake`, `using NLopt via local cmake build on arm64`), loads.
  kappa: nloptr's Windows build does not run cmake: its Makevars.win
  takes nlopt from R_TOOLS_SOFT (zig-libs, `-I.../zig-libs/x86_64-windows-gnu/include/nlopt`),
  and zig-libs has no nlopt, so `'nlopt.h' file not found` (a
  WAITS-LIBS gap, not the extras group). A CMake project ("Unix
  Makefiles", CC from `R CMD config CC`, make from the build tools)
  configures (Clang 22.1.8) and builds libhello.a, rc 0 (k2.log).
- F7 (V) kappa, slim + extras without the build tools: Sys.which("make")
  and ("sh") are `C:\Users\admin\.pixi\bin\make.exe`/`sh.exe`, the
  user's global pixi tools on PATH. With r-zig-toolchain, make is the
  env's `Library\usr\bin\make.exe`. Note only.

### CI12 (c): r-zig-recommended (omicron, kappa)

- F8 (V) 15 of 15 load from the env's library on osx-arm64 and win-64
  (MASS 7.3.66 ... spatial 7.3.19), with Matrix, MASS::rlm, mgcv::gam
  and survival::survfit calls giving the same values on both
  (omicron/omi-env.log, kappa/ext.log).

### H4: zig-lib-<n> in ~/.cache/r-zig (omicron)

- F9 (V) Mechanism: on macOS every conda env has libc++.dylib in
  <env>/lib, beside conda-forge's zig, whose feedstock patch then links
  a shared libc++. rzig gives zig a mirror of its lib dir instead,
  `<cache>/r-zig/zig-lib-<key>/lib/zig` (symlinks, `.complete` marker),
  one per zig lib dir (libcxx_mirror.zig:1-24, 90-108). The cache is
  XDG_CACHE_HOME, else HOME/.cache (cache.zig:28-35); rzig removes no
  entry (cache.zig:9). So any package build with a build-12 env on macOS
  makes one, by design. Upstream zig: none.
- F10 (V) Run with HOME and XDG_CACHE_HOME in the scratch dir (nloptr
  and Rcpp from source, RZIG_TRACE=1): one entry, zig-lib-4119367934,
  in the private cache, its links into the env's lib/zig; 50 traced zig
  calls carry `ZIG_LIB_DIR=<that mirror>`; every `cache` line names the
  private cache. Nothing of this run reached the real cache.
- F11 (V) The real ~/.cache/r-zig on omicron held 12 zig-lib-* from
  2026-10-10 to 11-15 (envs since deleted; 0 B, symlinks). During this
  run a 13th appeared, zig-lib-971555147 (09:15:14), linking to
  ~/rz-b13-stress/env/lib/zig: another topic's env run without a private
  XDG_CACHE_HOME (that dir is gone now; the entry dangles). This is the
  O-D14 observation: an R run with the user's HOME.

### CI10: pkg-parity (Q14 keeps -F)

- F12 (V) omicron, osx-arm64, conda-forge zig 0.17.1: `pixi run build`
  2m48s; toolchain tree from publish run 45381914199's
  toolchain-macOS-ARM64 artifact (unpack-toolchain rc 0); compile-tree
  rc 0; pkg-parity rc 0 in 2m43s, `pkg-parity verified (macos/slim)`:
  cli, digest, quadprog, Rcpp, minqa identical exports and rzig command
  lines, all SHLIB shapes, tiers 2 and 3, caches, base without make
  (omicron/parity.log). Every macOS compile carries
  `-F<SDK>/System/Library/Frameworks`, which Q14's argv_of now keeps.
- F13 (V) The publish run also ran pkg-parity on all 16 build legs,
  each `pkg-parity verified`, macos-latest (job 138408672140) and
  macos-15-intel (138408672337) included (T/scratch-b13-hosts/logs).

### H6: zig 0.17.x watch items

- F14 (V) (a) conda-forge zig 0.17.1 on omicron, osx-arm64 and osx-64
  (Rosetta): `zig ar rcs new.a x.o` with no new.a gives `ar: error:
  unable to open 'new.a': No such file or directory`, rc 1. PyPI
  ziglang 0.17.1 (both macOS wheels): rc 0, `!<arch>` archive listing
  x.o. ar.zig's workaround stays; its comment can name 0.17.1 (Needs N1).
- F15 (V) (b) ZIG-FETCH-CACHE.md's repro on delta (linux-64) with
  conda-forge zig 0.17.1 and PyPI ziglang 0.17.1: the last `zig build`
  stops with the hash mismatch on both; deleting `p/<hash>.tar.gz`
  fixes it; a build asking for one lazy dependency unpacks both when
  both are cached. Record's status table updated.

### CI8: read-only log checks

- F16 (V) R-C9, stress 45305358893, windows-11-arm: the Rtools45 tree
  step (download, extraction, closed .pc files) took 6.9 min (tree leg,
  job 138169627819) and 6.5 min (conda leg, 138169627864), both with
  `Cache not found`; the tree leg saved the cache at its end. Which
  extractor ran is not logged: stress.R:605-610 keeps it in `how`, used
  only in the error (Needs N2). Inferred (I): cmake -E tar, the first
  tried, since cmake 4.x reads zstd and the tree came up.
- F17 (V) R-C11, publish run: link-objects-test on ubuntu-24.04-arm
  181/180/171/183 s (default, minimal, full, openblas), on ubuntu-latest
  99/96/195/133 s; on ubuntu-24.04-arm its x86_64 and aarch64 Windows
  DLL links all print ok, so cross-linking for Windows from
  linux-aarch64 works.
- F18 (V) O-D10 (feat-r-home-link-objects UNVERIFIED): now covered:
  `bin/toolchain/cfguard.o` ships in win-64's r-zig-slim (kappa,
  ext.log listing); magick's windows-latest link names
  `R_HOME/bin/toolchain/cfguard.o` and the row is ok (stress
  windows-latest-tree logs/magick.log); pkg-parity on both Windows
  runners and both macOS runners (F13); rzig-test on ubuntu-24.04-arm
  and macos-latest; the conda-package legs built and tested; zig
  0.17.1 links the objects; omicron runs (F10, F12). Left: a Windows
  wheel (none yet, L2).
- F19 (V) R-F11: every Windows stress leg (both runners, tree and
  conda) links duckdb with `_LINK_=/OPT:NOICF` (one traced link each)
  and duckdb is ok. arrow's link carries it too but fails before run
  time: windows-latest fail-abi (403 undefined `arrow::` symbols with
  libc++ `std::__1` signatures; the prebuilt libarrow exports
  libstdc++ `std::__cxx11` ones), windows-11-arm fail-package (x64
  libarrow_dataset.a). So ICF-off on arrow is not exercised.

### CI13: R_ZIG_FALLBACK_SOFT with channel=universe on windows-11-arm

- F20 (V) No stress run since the publish (latest: 45305358893,
  2026-11-24 01:29, before 11:11; channel local). Its windows-11-arm
  conda leg reads `Fallback: ... rzig uses it (R_ZIG_FALLBACK_SOFT)`
  with r-zig from dist/conda. Not done; dispatch (user):

      gh workflow run stress.yaml --ref main -f oses='["windows-11-arm"]' -f distribution=conda -f channel=universe -f packages='g3'

  Done looks like: report.md's Fallback line ends `rzig uses it
  (R_ZIG_FALLBACK_SOFT)` (stress.R:781), r-zig-slim *_12 from universe.

### H5: leftovers (listed, nothing deleted)

- F21 (V) kappa: a dangling service `actions.runner.luciorq-r-zig-pixi.kappa`
  (Stopped, AUTO_START DELAYED, binary
  `C:\actions-runner-kappa\bin\RunnerService.exe`; the directory is
  gone). `%LOCALAPPDATA%\zig` and `%LOCALAPPDATA%\r-zig`: empty.
  `rz-rel11b-chain.bat`, `rz-rel11b.log` (1 MB, 2026-11-14) in the home
  dir. `cdt` 719 MB (2026-11-23, owner unknown). Temp: 31 Rtmp/zig
  entries, 89 MB. Other b13 topics' scratch: 29.5 GB. C: free: 32 GB.
- F22 (V) omicron: `~/r-zig-pixi` 13 GB (2026-10-12, an R 4.6.1 tree);
  `rt-test` 14 GB (2026-10-30); `cdt-test` 571 MB; `chain-osx-static*.sh`,
  `chain-release-0.1{6,7}.sh`, `omicron-rt9.sh`; `~/.cache/r-zig` 13
  zig-lib-* (F11); `~/.cache/zig` 352 MB (2026-08-13). flang-pixi's
  dirs (`flang-pixi-rbout` 7.4 GB, `fp-*`, `cdv2*`) are another
  project's: not proposed. No launchd runner.
- F23 (V) delta (~/rz): wave2 and build 12 leftovers: `wt/build12-wave2`
  8.9 GB, `wt/wave2-compat` 12 GB, `wt/wave2-build` 5.0 GB,
  `wt/wave2-licences` 3.5 GB, `wt/wave2-rzig` 86 MB,
  `wt/wave2-dist-baseline` 132 MB, `wt/lic-mini`, `wt/wave2-*.log|sh|times`;
  `scratch` 8.9 GB (wave2-compat 6.8 GB, w2rzig, w2review, fvs, rev,
  rzq, envci, tsr-*); `q21` 386 MB; `postpub11` 6.8 GB; `chain-w2*`,
  `wave2-compat-*.log`, `rev*.sh|out`, `minos.py`, `tmp-zigwin.8Aod`.
  `postpub12` (6.8 GB, today) and `base` (7.1 GB) are current. `~/.cache/zig`
  302 MB, written today by a run without a private cache.
- F24 (V) gamma: no runner unit (`systemctl --user/--system
  list-unit-files`: none). `~/.cache/r-zig` 182 MB: 19 dso-fini-*, 2
  build-runner-*, 1 zig-build (2026-10-08..11-18), kinds rzig no longer
  makes (link objects ship in R_HOME; tier 1 runs no build runner).
  `~/.cache/zig` 3.0 GB. T: 91 entries (T/scratch-b13-hosts/gamma-classes.tsv):
  - A, cited by no record, last written before 2026-11-18, about 23 GB:
    deps phase2 phase3 tiers.sh phase4plan pixi-cache-p6 renumber
    phase7alt queue queue4 p8 p9 pkgconf-proto p10-handover zarm pixi081
    render80 review-scratch-* rb-toy omp-* rsrc fp-sync fp-rb fp-kappa
    avx-hunt avx-t pin-* review-lock art-macx abi-*.
  - B, cited as evidence in records, about 55 GB: stress (16 GB) tclhdr
    round2 round1fix rzigfix r2ans gate7 phase3plan phase4 shlib
    shlibplan phase5 phase7plan phase7 phase7native utf8 winfix queue2
    z17 cmk obj-inputs bioc-rows next (26 GB) archive.
  - C, keep: libs-* (libs-zig-pixi's session), the b13 scratch dirs and
    worktrees, stress-45305358893, handover-next, m4, m4logs,
    batch-scratch, zlu, m5-scratch, stress-45219870330.
  - T/wt: wave2-build, wave2-compat, wave2-fixes, wave2-licences,
    wave2-rzig and build12-wave2 are clean worktrees of merged branches
    (PR #55).

- F25 (V) omicron's resolver: conda-forge curl 8.23.0 (c-ares), R's
  libcurl and conda python fail with "Could not resolve host" for
  cloud.r-project.org, files.pythonhosted.org and pypi.org;
  /etc/resolv.conf names only Tailscale's 100.100.100.100;
  /usr/bin/curl and pixi resolve. So on omicron any conda env's
  install.packages() from CRAN, fetch-r.sh and fetch-zig.sh fail
  (omicron/omi-h4.log first run, parity-toolchain.log). A host issue,
  not r-zig's; worked around (D5).

Proposed cleanup (user runs it; all are leftovers of finished work):

1. kappa: `sc delete actions.runner.luciorq-r-zig-pixi.kappa` (admin);
   delete `rz-rel11b-chain.bat`, `rz-rel11b.log`; the b13 topics' rz-b13-*
   once they are done.
2. omicron: `rm -rf ~/r-zig-pixi ~/rt-test ~/cdt-test ~/chain-osx-static*.sh ~/chain-release-0.1?.sh ~/omicron-rt9.sh ~/.cache/r-zig/zig-lib-*`
   (if rt-test and cdt-test are r-zig's: I).
3. delta: `cd ~/rz && rm -rf wt/build12-wave2 wt/wave2-* wt/lic-mini scratch q21 postpub11 chain-w2* wave2-compat-*.log rev.* rev2.* minos.py tmp-zigwin.8Aod base-install.log base-build.log`.
4. gamma: `rm -rf ~/.cache/r-zig/{dso-fini,build-runner,zig-build}-*`; the A list in T;
   `git worktree remove` for the six wave2/build12-wave2 worktrees; B after
   deciding whether the cited evidence is still wanted (or keep only
   the cited files).

## Tests run

| where | command | result |
|---|---|---|
| kappa | run.bat: pixi init, universe prepended, `pixi add r-zig-slim r-zig-compilers`, h3.R | has_rtools TRUE via Rtools (F1) |
| kappa | k2.bat: R CMD config (activated, unactivated, Library\bin on PATH), h3b.R with Rtools hidden, cmake.R | F2-F6 |
| kappa | space.bat: env under "sp ace", R CMD config, shlib.R | rc 0, 42 (F5) |
| kappa | ext.bat: slim, + extras, + recommended, + toolchain, nlo.R | cmake ok, 15/15, nloptr fails on nlopt.h (F6) |
| kappa | dll.bat (objdump -p) | R.dll's conda DLLs (F4) |
| omicron | omi-env.sh: slim, + extras, + recommended, + toolchain | cmake ok, 15/15 |
| omicron | omi-h4.sh: nloptr and Rcpp from source, private HOME/XDG | rc 0, F10 |
| omicron | omi-parity.sh + omi-parity2.sh (build, unpack-toolchain, compile-tree, pkg-parity) | rc 0 (F12) |
| omicron | ar-test.sh, ar-test2.sh (re-run of ar-test.sh in Review) | conda-forge fails (logged), upstream ok (not logged) (F14) |
| delta | fetch-repro.sh (both zigs) | reproduced on both (F15) |
| gamma | gh run view --log (publish 45381914199, 19 jobs; stress 45305358893, 4 jobs); stress-45305358893 reports | F13, F16-F20 |

Upstream zig: F14 and F15 ran with both zigs. H3, H4, CI10 and CI12 ran
the build-12 envs' conda-forge zig only (no compile or link behaviour
changed here).

## Not verified

- osx-64 (Rosetta) for CI12 (b)/(c) and H4; win-arm64 on a host.
- An R_HOME with a space on a volume without 8.3 names (F5).
- Which extractor stress used (F16), until N2 lands.
- CI13 (F20): needs the dispatch above.
- rt-test and cdt-test owners on omicron, cdt on kappa (F21, F22).

## Needs from other topics

- N1 (b13-rzig, zigbuild/tools/rzig/ar.zig:10-11): name 0.17.1 in the comment:

      -//! osx-arm64's 0.17.0 (omicron, 2026-11-09; upstream 0.17.1 creates
      -//! archives on both). Appending to an existing archive works. It bit jsonlite's
      +//! osx-arm64's 0.17.0 (omicron, 2026-11-09) and 0.17.1 (omicron,
      +//! 2026-11-24); upstream 0.17.1 creates archives on both. Appending to
      +//! an existing archive works. It bit jsonlite's

- N2 (b13-stress, stress/stress.R:605-610): say which extractor ran:

      -      if (st == 0 && dir.exists(file.path(tree, "lib", "pkgconfig"))) break
      +      if (st == 0 && dir.exists(file.path(tree, "lib", "pkgconfig"))) {
      +        message("stress: Rtools45 tree extracted with ", basename(t[1]))
      +        break
      +      }

- N3 (b13-rzig or a later item, proposal only): F4. An unactivated
  `R.exe` cannot start on Windows. Options: document "activate, or put
  `<env>\Library\bin` on PATH" in README's Windows notes; or the front
  `bin\R.exe`/`Rscript.exe` prepends `<R_HOME>\..\..\bin` (Library\bin)
  to PATH before starting x64\R.exe, as R already does for the build
  tools. Not decided here.
- N4 (b13-stress, any topic running on omicron): set XDG_CACHE_HOME
  (and ZIG_GLOBAL_CACHE_DIR) to its scratch dir; its run wrote
  ~/.cache/r-zig/zig-lib-971555147 on omicron (F11). And omicron's
  conda curl cannot resolve hostnames (F25): download with
  /usr/bin/curl.

## Suggested commit message

    docs: record the build 13 host checks and CI log reads

## Review (2026-11-24)

Checked the diff (6 files, all records this topic may annotate; no
source files) and the evidence behind each finding.

- Verified against code: config.zig:103-106 (no args: usage, rc 1),
  libcxx_mirror.zig:1-24 and 90-108, cache.zig:9 and 28-35, ar.zig:1-15
  (N1's minus lines match), stress.R:605-610 (N2: `t` is the tried
  command, `basename(t[1])` is right) and stress.R:781 (Fallback text).
- Verified against logs: kappa run.log:69 (Rtools answer), k2.log:243
  (R CMD config CC answer), run.log:119-121 (rc -1073741515); 16 of 16
  build-leg logs of publish run 45381914199 print `pkg-parity verified`
  (5 other job logs are toolchain and conda-package jobs); stress
  windows-11-arm cache `Cache not found` on both legs and `Cache saved`
  on the tree leg; duckdb ok and `/OPT:NOICF` in its logs on all four
  Windows legs; fetch-repro-delta.log: hash mismatch with both zigs.
- Fixed: F19 said arrow's windows-latest link missed libstdc++
  `std::__cxx11` symbols. The log (stress windows-latest-tree
  logs/arrow.log) has 403 undefined `arrow::` symbols with libc++
  `std::__1` signatures: the link asks for libc++ names the libstdc++
  prebuilt libarrow does not have. Reworded.
- Gap fixed in part: F14 had no saved log. Re-ran ar-test.sh on omicron:
  conda-forge zig 0.17.1 `ar rcs new.a x.o` gives `unable to open
  'new.a'`, create rc=1, on osx-arm64 and osx-64 (Rosetta)
  (T/scratch-b13-hosts/omicron/ar-test-review.log). Its PyPI half fails
  at pip (F25, no DNS), and ar-test2.sh (the /usr/bin/curl upstream
  half) was stopped before it ran; so "upstream 0.17.1 creates the
  archive" is I in this record (the implementer's unsaved run), not
  re-verified. omicron ~/rz-b13-hosts deleted afterwards.
- No code changed, so no delta build chain to re-run.
