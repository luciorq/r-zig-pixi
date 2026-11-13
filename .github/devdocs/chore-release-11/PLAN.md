# chore-release-11 — one pull request for the whole backlog

Branch: feat-win-arm64 (pull request #48, retargeted to main after #45,
#46 and #47 merged on 2026-11-12). Recipe build number: 11, not yet
published.

## Decisions (user, 2026-11-12)

- One release at the end of the whole backlog. No publish, no
  `CONDA_PUBLISH` and no further build-number bump before it.
- One large pull request to test everything together: R's latest
  release (4.6.2), zig 0.17, Windows on ARM working, the open
  follow-ups, and the items below. The stress run comes last.
- The yardstick: "simplicity and feature parity between the different
  targets, OSs, arches. Minimizing the amount of shelling out and
  workarounds."
- The release publishes conda packages only. The standalone archives
  and the wheels are released "only when we know we can build a good
  number of packages and feature parity across targets is stable".
- Into this pull request: `R CMD config` through rzig, libR hiding its
  internal symbols, the extras group (cmake), and the recommended
  packages, which "need to ship on their own conda package".
- After the release, one pull request each: native Windows build tools
  (no MSYS2), one base with add-ons (tcltk first, a really slim Windows,
  a Windows wheel), the C++ ABI boundary and a binary package
  repository.
- The conda base keeps its name, r-zig-slim.

Reviewed and found not needed: flang-pixi's "upstream-zig switch"
(building flang-pixi's own packages with the ziglang.org tarball).
Nothing here depends on it: r-zig-pixi uses the flang driver, the module
files and libflang_rt.runtime.a by exact pin, rzig links with the user's
zig, and both zigs are tested for R and packages (upstream-zig.yaml).
flang-pixi measured identical machine code from both zigs. Its record:
flang-pixi docs/19 §6.

## What changed

### R 4.6.2

- `R_VERSION`, build.zig's `r_version`, the recipe's version, the
  checksum file, `zigbuild/patches/R-4.6.2/` (renamed; all 14 patches
  apply to 4.6.2 with no offset and no fuzz).
- The build graph needs no change: 4.6.2 adds one R file
  (parallel/R/mvrnorm0.R, which the build collects by listing the
  directory) and changes no makefile's source list.
- The captured configs (zigbuild/config/). A real configure run of 4.6.2
  on linux-x86_64 (slim) changed only the version strings and
  `R_SYSTEM_ABI`, whose Fortran words are now `flang,flang` (4.6.1's
  configure said `ClassicFlang` for a compiler named flang). The same
  lines were changed in the other eleven unix directories;
  `win-full/GENERATED_FROM` names 4.6.2.

### flang 23.1.5 and one libomp

- flang-zig 0, flang-rt-zig 1 (flang-pixi's LLVM 23.1.5 release). The
  lld-zig pins are gone: flang-zig depends on its own build of it.
- llvm-openmp is flang-pixi's build (`universe`, build string `zig_*`,
  build 1) on all six platforms, in pixi.toml and in the recipe's host,
  and r-zig-slim's and r-zig-compilers' run dependency is
  `llvm-openmp >=23.1.5 zig_*`. The build string selects it although
  conda-forge is the first channel (checked with pixi 0.84.2 for all six
  platforms). It has conda-forge's file names (omp.h, libomp.so /
  .dylib / .dll, libomp.lib, libomp.dll.a) and no dependency but the C
  library.
- Why: conda-forge's win-arm64 libomp.dll passes a parallel region only
  its first six shared variables (feat-win-arm64/PLAN.md); data.table's
  sort crashed on windows-11-arm. One libomp built one way on every
  platform, not a win-arm64 exception.
- The lock changed in these packages only: flang-zig, lld-zig,
  flang-rt-zig and llvm-openmp, six platforms each.
- flang-pixi pruned build 0 of flang-rt-zig and llvm-openmp the day it
  published build 1 (2026-11-12): a lock that names a pruned build gives
  a 404 on a machine without it in its cache. `pixi lock` kept the
  locked llvm-openmp build 0 while the spec allowed it, so the spec
  names the build number too (`zig_*_1`).

### Hidden symbols on linux, as on macOS and in CRAN's R

- linux's captured config had no `HAVE_VISIBILITY_ATTRIBUTE`, and macOS's
  had it. Cause: configure asks `$CC -Werror -S conftest.c`, and `zig cc`
  gives clang `-c` beside `-S`, so clang warns that `-c` is unused: an
  error with `-Werror` (zig 0.17.0 and 0.17.1, conda-forge's and
  upstream's). macOS's configure takes another branch.
- rzig (compiler.zig) and the capture shims (toolchain/zig-cc,
  toolchain/zig-cxx) add `-Wno-unused-command-line-argument` to a command
  with `-S`. This also serves every package whose configure script
  probes that way.
- With that, a real configure run on linux says
  `r_cv_visibility_attribute=yes`: `HAVE_VISIBILITY_ATTRIBUTE 1`
  (config.h and Rconfig.h), `C_VISIBILITY` and `CXX_VISIBILITY`
  `-fvisibility=hidden`. The six linux directories have these lines.
- build.zig gives `$(C_VISIBILITY)` to the directories whose makefile
  does (CGroupOpts.visibility): src/extra's tre, tzone and xdr, the
  internet module, and stats, graphics, grid, methods, parallel,
  splines, tools, utils and tcltk. It applied to no directory before, on
  macOS too.
- linux-64, slim: libR.so exports 1257 symbols (2541 before; CRAN's
  about 1259); utils, tools, methods, graphics, grid, splines and
  parallel export their R_init function only; internet.so one symbol.

### R_compiled_by()

- build.zig reads CC_VER and FC_VER from the compilers of the build on
  every OS (versionLine: the first line of `zig cc --version` and of
  `flang --version`) and writes them into config.h (setDefine on unix,
  the `@CC_VER@` and `@FC_VER@` tokens on Windows). The captured strings
  said clang 21.1.8 and flang 23.1.1 under zig 0.17 and flang 23.1.5;
  Windows had a fixed text.

### Windows on ARM

- windows-11-arm is a leg of build.yaml as the other five platforms:
  toolchain, the default build leg in the core tier, conda-package and
  the publish. win-arm64.yaml and its label are gone.
- build-r.yaml keeps its temporary probe step until the first green
  contract run on windows-11-arm.

### Small follow-ups

- stress.R `--conda` (K2), test-preflight.R's message and wheel-test.sh's
  mktemp (N9).
- evex512: not needed with zig 0.17 (feat-standalone-toolchain/TODO.md).

### Items in progress (not in this tree yet)

Three items were started on 2026-11-12, each in its own copy of this
tree (a git worktree at 28eaf9e plus the uncommitted baseline), and were
stopped unfinished when the session ended. Nothing of them is merged
here. See "State at the stop" below.

- `R CMD config` through rzig (no make, no sh).
- The extras group (cmake) and an `r-zig-extras` conda package.
- The recommended packages, built by a Zig step, in their own conda
  package.

## Findings (2026-11-12)

1. R 4.6.2 is CRAN's latest release (2026-10-29; R-latest.tar.gz is the
   same file; 4.7.0 is devel only). sha256
   c297040f6392b1dac6e5c0eb398422cfdaedf540ae2205edb9ad0d10cb10ee00.
   Against 4.6.1: 136 files differ, 1 new R file, 11 recommended
   tarballs replaced; build-relevant changes are configure/m4's
   R_SYSTEM_ABI words, Rdll.hide (+dim2total), shext.c, Rmath.h0.in,
   parallel's DESCRIPTION (Imports stats), stats' NAMESPACE, tzdata
   2026e. None changes build.zig's source lists.
2. `zig cc -S` warns "argument unused during compilation: '-c'" (zig
   0.17.0 conda-forge and 0.17.1 upstream): with -Werror an error. No
   upstream report was filed.
3. linux's captured configs lacked HAVE_VISIBILITY_ATTRIBUTE because of
   finding 2; macOS's had it. build.zig applied $(C_VISIBILITY) to no
   directory on any OS.
4. The captured CC_VER/FC_VER were stale (clang 21.1.8, flang 23.1.1).
5. evex512: zig 0.17 has no such CPU feature; AVX-512 target-attribute
   functions compile at -mcpu=baseline. The TODO item is closed.
6. conda-forge's win-arm64 libomp.dll (llvm-openmp 23.1.5 hef4af3d_0)
   is the cause of windows-11-arm's contract crash (feat-win-arm64).
   flang-pixi's zig-built llvm-openmp replaces it on every platform.
7. Channel order: with `channels = ["conda-forge", universe]` a bare
   `llvm-openmp` resolves to conda-forge's; `build = "zig_*"` selects
   universe's in every order ONLY as a direct requirement (pixi.toml).
   As a package's dependency (flang-rt-zig 23.1.5 `_1`, the r-zig recipe's
   run requirements) strict priority filters it: conda-forge first makes
   flang-rt-zig uninstallable (flang-pixi test.yml run 43337035109). Fixed
   2026-11-12: universe listed first everywhere (pixi.toml, the
   conda-package task, scripts/conda-consume.sh, stress.R, README
   `--prepend`), and universe's prefix.dev base relation to conda-forge
   removed by the user (a base channel outranks the channel). `pixi lock` keeps an already locked build
   that the spec still allows, even after the channel deleted it: name
   the build number in the spec.
8. flang-zig 23.1.5 depends on `lld-zig ==23.1.5 *_0` itself.
9. The bash shims in toolchain/ (zig-cc, zig-cxx, zig-ar, zig-ranlib,
   834 lines) are used only by the configure capture
   (zigbuild/tools/configure-only.sh, gen-config.yaml) and as rzig's
   parity reference (rzig-test). A candidate to remove: capture with
   rzig itself.
10. pixi.toml has six per-platform `conda-publish` tasks that differ in
    the subdir only.
11. omicron: LuLu blocks network access of binaries at new paths; a tree
    under `~/.pixi/` matches the user's directory rule
    (`/Users/luciorq/.pixi/*`). The test trees are in
    `~/.pixi/rz-rel11/`.
12. The larger-items review (an agent's report, 41 items) found these
    still worth doing after the release, beyond the user's list: the
    C++ ABI boundary (sf, terra, magick, V8 on linux are expected
    failures), WinRT headers missing from zig's MinGW (s2, sf, lwgeom on
    Windows), libcurl -> libpsl -> ICU in the wheel (14 of 49 MiB), a
    win-arm64 stress subset without system libraries, the release job
    for standalone archives and PyPI (B12). Not needed: flang-pixi's
    upstream-zig switch, `zig build fetch`, v3 package flags,
    R_ZIG_TOOLCHAIN_ENV, ARM64 Control Flow Guard (until a package hits
    it). Stale records it listed are not all corrected yet:
    feat-standalone-toolchain/PLAN.md:5-7, :6787, :6872, :6899-6904,
    :6944-6947, :6961; TODO.md:149-161, :1091-1096, :1241-1254;
    feat-win-zig-binutils/PLAN.md:265-280; feat-wheel-minimal/PLAN.md
    :3-14, :103, :127-135; consolidation/PLAN.md:16-18, :65-68, :190;
    zigbuild/toolchain/build.zig.zon:5 (minimum_zig_version 0.16.0).

## Tests

linux-64 (gamma), default env (slim), conda-forge's zig 0.17.0,
2026-11-12:

- Run 1 (R 4.6.2, flang 23.1.5, libomp build 0, before the visibility
  change): toolchain-test, rzig-test, build, smoke, verify-tree,
  toolchain, verify-toolchain, contract, pkg-parity, check (R's own
  suite), hermetic: all exit 0.
- Run 2 (plus visibility, CC_VER/FC_VER, the -S fix): rzig-test 189/189
  and parity "0 failed"; build; `R_compiled_by()` gives clang 22.1.8 and
  flang 23.1.5; smoke, verify-tree, toolchain, verify-toolchain and
  contract exit 0. pkg-parity, check, hermetic, package,
  package-toolchain and verify-package were still running when this was
  written: read rel11/linux64-chain2.log.
- Not yet run with the final lock (libomp build 1) on gamma: the env
  there still has build 0's files (the same code). Run
  `pixi install --frozen` and the chain again.
- full, minimal, openblas, wheel, conda-package and conda-consume: not
  run.
- macOS (omicron) and Windows (kappa): chains started on the baseline,
  results not read. See below.
- win-arm64: CI only; not run. The pull request has not been pushed.

## State at the stop (2026-11-12, evening)

All paths below are under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/ (T).

- T/wt/feat-win-arm64: this tree, branch feat-win-arm64 at 28eaf9e,
  everything above uncommitted. Lock sha256 a423ecfb...
- T/rel11/handover/interim-commands.sh with commit-1..5.txt: the commits
  and the push for this tree as it is (retargets #48 to main first).
  Not run. Pushing starts CI on all six platforms, windows-11-arm
  included, which is the only test of Windows on ARM.
- T/rel11/baseline: a copy of this tree's sources as the agents got
  them (plus the build-1 pins). An agent's own changes are
  `diff -ru T/rel11/baseline T/wt/rel11-<item>` without .git, .pixi,
  build, dist, .zig-cache, zig-pkg.
- T/wt/rel11-config, T/wt/rel11-extras, T/wt/rel11-recommended (local
  branches rel11-*, at 28eaf9e): the three items' trees, unfinished and
  unreviewed. Each agent was told to write
  T/rel11/scratch-<item>/STATE.md and CHANGED-FILES.txt. Their briefs:
  T/rel11/brief-<item>.md; the shared rules: T/rel11/AGENT-RULES.md.
- Logs: T/rel11/linux64-chain1.log, linux64-chain2.log,
  configure-linux64-slim*.log, lock*.log, rzig-test2.log.
- omicron: `~/.pixi/rz-rel11/{arm64,x64}` and their logs
  `~/.pixi/rz-rel11/arm64.log`, `x64.log` (lines starting `===`); the
  chain script is `~/.pixi/rz-rel11/chain-mac.sh`. The first arm64 run
  (old lock) passed toolchain-test, rzig-test, build, smoke and
  verify-tree with R 4.6.2 before its curl was blocked. Delete the
  directory when done.
- kappa: `C:\Users\admin\rz-rel11`, log `C:\Users\admin\rz-rel11.log`,
  script `C:\Users\admin\rz-rel11-chain.bat`. Delete all three when
  done.
- Since the snapshot this tree gained only records, README lines, the
  recipe's build-number note and the build-1 pins.

## To resume

1. Read the three STATE.md files; finish or drop each item; merge each
   diff into this tree (recipe.yaml and pixi.toml are touched by more
   than one), then `pixi lock`.
2. Read the omicron and kappa logs; fix what they show.
3. On gamma: `pixi install --frozen`, then the chain for default, full,
   minimal (with the wheel), openblas, and `pixi run -e pkg
   conda-package` + `conda-consume`.
4. Hand the commits to the user (the interim script, extended); the
   push runs CI. When windows-11-arm's contract passes, remove the
   temporary probe step from build-r.yaml.
5. Correct the stale records of finding 12; README sections for the new
   packages.
6. Last: the stress run on the branch (all runners, tree and conda),
   read its table row by row (N6, K1, the arrow and RcppSimdJson rows
   for evex512); then the publish preflight and the one release of
   build 11 for six subdirs.

## The three items, as their agents left them (2026-11-12, 19:47)

Each agent was stopped early. Their state files have the design, the
remaining steps and the resume commands; none of their work is reviewed.
Paths are under /data/gamma/luciorq/workspaces/temp/r-zig-pixi/ (T).

### `R CMD config` through rzig — design only, no code

State: T/rel11/scratch-config/STATE.md. Tree T/wt/rel11-config has no
change of its own (the build-1 pins are applied there; R and the
toolchain are built; compile-tree's exit was not read).

- Route: R's own Rcmd dispatch runs `rzig config` on every OS, with no
  script: a new patch 0010 (four lines in Rcmd.in, one changed line and
  a quote fix in rcmdfn.c) replaces the make check; bin/config and
  bin/config.sh are no longer installed.
- rzig: a new config.zig that follows the script step by step and reuses
  makefile.zig's evaluator, with two extensions: GNU make's built-in
  variables as a `default` origin (for config only), and a lenient mode
  in shellwords.zig with sh's `echo` rules.
- The variable list and help text are compiled into rzig; a parity test
  (scripts/config-parity.sh, run by `contract` on the compile tree)
  compares `R CMD config <args>` with the unpatched script.
- Traps: the script's output depends on which `echo` make runs (dash
  expands backslash escapes; a leading -n or -e is an option); the "no
  information" error goes to stdout; rcmdfn.c leaves the outer quote
  open when no argument follows; Zig refuses tabs in multiline strings
  (embed the usage text as a file); `$(shell ...)` in a `:=` line of a
  user's Makevars cannot be answered without make (planned: exit 2 with
  the reason; a question for the user).
- The tests that expect exit 127 without build tools must change; the
  state file lists them.

### The extras group (cmake) — design only, no code

State: T/rel11/scratch-extras/STATE.md. Tree T/wt/rel11-extras has no
change of its own, and the build-1 pins are NOT applied there: run
`bash T/rel11/pins-build1.sh <tree>`, copy T/rel11/baseline/pixi.lock,
`pixi install --frozen` first.

- cmake's source: PyPI's `cmake` 4.4.4 wheel for the standalone tree and
  the wheel channel (as `ziglang` serves zig); conda-forge's cmake as a
  dependency of an otherwise empty `r-zig-extras`. conda-forge's cmake
  cannot be copied into the tree: its bin/cmake has a prefix
  placeholder, which the toolchain build refuses, and it links ten
  shared libraries (libcurl and its closure).
- All six targets have a PyPI wheel (macOS: one universal2 wheel);
  conda-forge has cmake 4.4.5 for win-arm64.
- Layout: `TC/cmake/` with bin/cmake, share/cmake-4.4/, SOURCES and
  LICENSES/cmake/; no cpack or ctest (21 MB each).
- R finds it by one more PATH entry, `TC/cmake/bin`, where the build
  tools' are set today: etc/Renviron on unix, R_ZIG_TOOLS_PATH in
  Rcmd_environ and patch 0014 on Windows.
- r-zig-extras pins r-zig-slim and depends on cmake; r-zig-toolchain
  would include it (about 26 MB of download, from the lock).
- Traps: the wheel's cmake needs the host's libstdc++.so.6 and
  libgcc_s.so.1 on linux (verify-toolchain allows glibc's only); the
  macOS binary is a fat Mach-O, which verify-toolchain's detection
  skips.
- Not verified: cmake was never run from the wheel; whether `zig fetch`
  unpacks a .whl and keeps the executable bit.
- Questions for the user: is the host's libstdc++ on linux acceptable;
  may R print a note when a package's SystemRequirements names cmake
  and the group is missing.

### The recommended packages — two Zig files written, never compiled

State: T/rel11/scratch-recommended/STATE.md. Tree
T/wt/rel11-recommended has two new files and nothing else; the build-1
pins are NOT applied there (as above). R is built; toolchain and
compile-tree were not run.

- Written, untested: zigbuild/recommended/build.zig (one
  `R CMD INSTALL` step per package) and zigbuild/recommended/order.zig
  (reads the names from share/make/vars.mk and the dependencies and
  INSTALL_OPTS from src/library/Recommended/Makefile.in, with unit
  tests).
- Design: its own small build file, as the toolchain's; it runs R from
  the compile tree.
- Planned conda package: `r-zig-recommended`, run-depends on the exact
  r-zig-slim only, nothing depends on it; r-zig-slim's file list must
  exclude the same 15 directories.
- Not started: scripts/zig-recommended.sh, the env.sh prefix, pixi
  tasks, recipe/test-recommended.R, the verify script, the recipe and
  build.sh changes, the standalone archive, the record.
- From the tarballs only: Matrix is the only one with Makevars rules
  (make path, needs build-tools at build time); the others should be
  tier 1; boot and codetools have no compiled code.
- Trap: mgcv's Makevars uses the OpenMP flags, so a slim-built mgcv
  would not load on minimal; a standalone archive would need the flavor
  in its name.
- Not verified: rpaths in the package libraries, a build path left by
  `--no-staged-install`, all timings and sizes.

## Chains at 19:47 (2026-11-12)

- gamma, linux-64 slim, with visibility: toolchain-test, rzig-test,
  smoke, verify-tree, toolchain, verify-toolchain, contract and
  pkg-parity exit 0; check was running, then hermetic, package,
  package-toolchain, verify-package (T/rel11/linux64-chain2.log, lines
  starting `===`).
- omicron arm64 (final lock, `~/.pixi/rz-rel11/arm64.log`):
  toolchain-test and rzig-test OK, build running; the osx-64 chain
  starts after it (`x64.log`), and `chain.out` ends with `EXIT=done`.
- kappa (final lock, `C:\Users\admin\rz-rel11.log`): toolchain-test and
  rzig-test OK, build running. Its chain runs inside an ssh session of
  the stopped session and may have died with it: if the log has no
  `=== END`, run `C:\Users\admin\rz-rel11-chain.bat` again over a held
  ssh session.
- ssh to both hosts: `export SSH_AUTH_SOCK=/run/user/1000/rz.sock`.
