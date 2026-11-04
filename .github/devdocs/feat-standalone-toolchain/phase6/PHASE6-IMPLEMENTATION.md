# Phase 6 implementation plan — Fortran in the compilers group

The planner's plan of 2026-10-16, amended the same day by the critic
(amender) after two reviews: `phase6/critique-code.md` (points tagged
(Cc1)-(Cc18)) and `phase6/critique-goals.md` ((Cg1)-(Cg11)). Every point
was checked against the worktree's code and, where it is a claim about
flang, against the staged copy; `phase6/critic/CRITIQUE.md` gives each
one's verdict (accepted, accepted with a change, or rejected with the
reason). An amendment is tagged where it lands; text with no tag is the
planner's. A tag written "phase 5's Cg<n>" is phase 5's critique, as the
planner cites it; every other (Cc<n>)/(Cg<n>) is phase 6's. One point was rejected (Cg7, section 12); one was decided
otherwise than its critic proposed (Cc5, by Cg2).

Read-only work: nothing in the worktree changed and nothing was built or
installed there. Two short probes ran in `phase6/planner/probe/` with
binaries that already existed (an extracted flang-zig `_6` and the main
checkout's two zigs); their results are cited as (PP). The critic's own
probes are (CP, in `phase6/critic-code/`) and the amender's (CA, in
`phase6/critic/probe/`, the surveyor's staged linux-64 `TC/flang`).
Where an open point (section 11) offers options, the plan is written
with its recommended option. The user's instruction for this run ("Keep
going", after "Follow with the recommended") answers every open point
that way: each is recorded as answered with its ★ option, and the menu
is kept for the record. Format as phase5/PHASE5-IMPLEMENTATION.md.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 6 keeps build 8, as phase 4, SHLIB routing and phase 5
do, and main publishes nothing until the user sets the repository
variable `CONDA_PUBLISH` after phase 7's bump merges (PLAN.md, B14's
amendment). Where this plan says phase 6 takes 12 (or names the earlier
layers' 9, 10 and 11), read: the number stays 8, and phase 6 publishes
with phase 7's bump, at the number after universe's newest (B14 a).

Sources:
- The worktree `wt/feat-standalone-phase6`, branch feat-standalone-phase6:
  main d11dee1 plus phase 4's, the R CMD SHLIB routing's and phase 5's
  changes, none committed.
  - Baselines: `wt/phase4-base.diff` (main → phase 4, `number: 9`),
    `wt/shlib-base.diff` (main → phase 4 + SHLIB, `number: 10`) and
    `wt/phase5-base.diff` (main → phase 4 + SHLIB + phase 5, cumulative,
    `number: 11`), plus their untracked files. git status on 2026-10-16:
    69 entries, 62 modified and 7 untracked
    (`.github/devdocs/feat-shlib-rzig-build/`, `phase4/`, `phase5/`,
    recipe/test-build-tools.R, recipe/test-compilers.R,
    scripts/conda-consume.sh, zigbuild/toolchain/wheel.zig);
    `git diff | sha256sum` starts with 69a83be6e2638c69.
  - Line numbers are this worktree's. When implementing, cite the
    function, not the line.
  - pixi.lock's sha256 starts with fbb64b7ba4e31e45. Phase 6 changes no
    dependency: the lock and pixi.toml's dependency tables stay as they
    are. The default env already has flang-zig `_6`, lld-zig `_5` and
    flang-rt-zig `_10` on all five platforms (pixi.toml:237-244), and
    `xz` (pixi.toml:250, which brings xz-tools' `xz` program on every
    platform, win-64 included: pixi.lock has xz-tools 5.8.3 for all
    five).
- feat-standalone-toolchain PLAN.md: "### Phase 6 — Fortran in the
  compilers group" (5080-5117), "The toolchain groups" (151-170),
  "Discovery and fallbacks" (171-209), the facts (573-628), Verification
  (5189-5270), Risks, "Open questions" (5371-5406), "Later and future
  checks"; TODO.md "## Phase 6" (654-686). Decisions: B9 (a), B13 (a,
  revisit), B14 (a), B17, B29 (a), B30 (a), B35, B40 (a), B44 (the
  user's own), D2 (a); the phase 3, 4 and 5 records.
- .github/devdocs/consolidation/FLANG_PIXI_HANDOFF.md §8 (the
  standalone set, measured 2026-10-06), §9 (the release we pin), §11
  (the 0.17 set; ours retained); PHASE2_FORTRAN.md.
- The three surveys, cited by section:
  - survey-tree.md (ST): the flang set per subdir, how build.zig copies
    it, the carve script, `-lc++`, B13's measurements, CI, conda/PyPI;
  - survey-rzig.md (SR): rzig's Fortran path, what changes with
    TC/flang;
  - survey-records.md (SD): the decisions, the 16 points to decide,
    the records that disagree.
  Their scratch is in `phase6/surveyor-{tree,rzig}/` (the 15 pinned
  `.conda` files checked against the lock, extracted, the staged
  compilers group per subdir, its archives in each format, the carve
  output, nm lists).
- (PP) this planner's probes, 2026-10-16, linux-64:
  - flang 23.1.1 (flang-zig `_6`'s `flang-23`, copied alone):
    `flang -c p.f90 -o p.o -L/x -lfoo -Wl,-rpath,/y -shared` exits 0
    with four `-Wunused-command-line-argument` warnings;
    `-Qunused-arguments` silences them (exit 0, the same object);
    `-fintrinsic-modules-path D -fintrinsic-modules-path D` (the same
    directory twice) exits 0. The copied driver reports
    `Target: x86_64-conda-linux-gnu`.
  - A Fortran object linked into an executable by `zig cc -target
    x86_64-linux-gnu.2.17 -mcpu=baseline -o pexe p.o
    <libflang_rt.runtime.a> -lm <flag>`: 40 flags tried (28 with
    upstream zig 0.16.0, then 12 more and the refused ones again with
    conda-forge's zig 0.16.0 and upstream's alike); zig cc refuses only `-J <dir>` (the separate form: "<dir>: unrecognized
    file extension"), `-Mfree`, `-Mfixed`, `-Mextend` and
    `-fno-fortran-main` ("Unknown Clang option"). Accepted: `-J<dir>`,
    `-module-dir <dir>`, `-fintrinsic-modules-path <dir>`, `-ffree-form`,
    `-ffixed-form`, `-ffixed-line-length-132`, `-fdefault-real-8`,
    `-fdefault-integer-8`, `-fdefault-double-8`, `-fimplicit-none`,
    `-cpp`, `-nocpp`, `-std=f2018`, `-fbackslash`, `-fconvert=...`,
    `-frecursive`, `-fno-automatic`, `-frealloc-lhs`, `-f(no-)underscoring`,
    `-ffpe-trap=...`, `-fbounds-check`, `-fcheck=all`, `-flarge-sizes`,
    `-fxor-operator`, `-funsigned`, `-fhermetic-module-files`,
    `-fopenmp`, `-ffast-math`, `-O2`, `-I.`, `-DX=1`, `-Werror`, `-w`.
    `-v` prints zig's `ld.lld ...` line. The program ran (`1`).
- (CA) the amender's probes, 2026-10-16, linux-64, the staged
  `TC/flang/bin/flang` (flang 23.1.1), `flang -Qunused-arguments -c s.f90
  -o s.o <flag>` (Cc1's measurement, widened):
  - refused, exit 1, "flang: error: unknown argument" (an option with a
    value also reports its value as a missing input): `-dynamiclib`,
    `-bundle`, `-undefined <v>`, `-framework <v>`, `-weak_framework <v>`,
    `-F<dir>`, `-install_name <v>`, `-current_version <v>`,
    `-compatibility_version <v>`, `-exported_symbols_list <v>`,
    `-bundle_loader <v>`, `-multiply_defined <v>`, `-force_load <v>`,
    `-headerpad_max_install_names`, `-single_module`, `-flat_namespace`,
    `-dead_strip`, `-arch <v>`, `-static-libgcc`, `-static-libstdc++`,
    `-shared-libgcc`, `-static-pie`, `-s`, `-mwindows`, `-mconsole`,
    `-municode`, `-mthreads`, `-z <v>`, `-u <v>`, `-T <v>`, `-e <v>`;
  - accepted (exit 0): `-shared`, `-static`, `-pie`, `-no-pie`, `-fPIC`,
    `-rdynamic`, `-pthread`, `-nostdlib`, `-nodefaultlibs`, `-rpath <v>`,
    `-Wl,...`, `-Xlinker <v>`, `-fuse-ld=lld`, `-lc++`,
    `-mmacosx-version-min=11.0`, `-target <t>`, `-Xflang <v>`,
    `-fsyntax-only`;
  - `flang --target=aarch64-unknown-linux-gnu -c s.f90` with the x86_64
    driver writes an AArch64 ELF object: the driver has the AArch64
    backend (Cg3's pre-check is possible);
  - the linux-64 driver embeds flang-pixi's gamma build path
    (`/data/gamma/luciorq/workspaces/temp/rb-out/bld/rattler-build_flang-zig_1791332521/work/...`,
    912 strings) (Cg10);
  - gamma has no `zig`, `flang` or `qemu-aarch64*` in /usr/bin and no
    binfmt entry, and its system python3 has no ziglang (Cc16, Cg3).

TC is `R_HOME/bin/toolchain` (unix `lib/R/bin/toolchain`, Windows
`Library/lib/R/bin/toolchain`). "The tree" is the toolchain tree,
`dist/toolchain/R-<ver>-zig` (B30, B36). Decision IDs are PLAN.md's.
This plan's open points are letters (section 11).

## 0. What phase 6 delivers

- **The toolchain tree gets `TC/flang/`**, flang's compile set copied
  from the build env (B9 a), the bytes that compiled R's own Fortran:

  | piece | from (unix; win-64 under `Library/`) | to, in `TC/flang/` |
  |---|---|---|
  | driver | flang-zig `bin/flang-23` (win-64 `Library/bin/flang.exe`) | `bin/flang` (`bin/flang.exe`), once |
  | modules | flang-rt-zig, every regular file under `lib/clang/23/finclude/flang/` | the same path: linux and macOS one directory (the conda triple), win-64 two identical ones (`x86_64-w64-mingw32`, `x86_64-w64-windows-gnu`); 18 files each: 15 intrinsic `.mod`, `omp_lib.mod`, `omp_lib_kinds.mod`, `omp_lib.h` |
  | runtime | flang-rt-zig `lib/clang/23/lib/<rt dir>/libflang_rt.runtime.a` | the same path (rt dir `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `darwin`, `x86_64-w64-windows-gnu`) |
  | licences | each package's `info/licenses/` | `LICENSES/flang-zig/flang/LICENSE.TXT`, `LICENSES/flang-rt-zig/flang/LICENSE.TXT` |
  | records | conda-meta | `SOURCES`: a block per package, a `file:` line per copy with paths_data's sha256 |

  - Left out: lld-zig (zig links), every `.cfg` (open point C), `bbc`,
    `tco`, `fir-*`, `flang-new`, the MLIR/Fortran static libraries,
    `include/`, the compiler-rt objects and builtins, the linux module
    directory softlink, the unix `lib/libflang_rt.runtime.a` softlink,
    win-64's MinGW CRT snapshot and its `libomp.dll.a`/`libatomic.a`
    shims (ST §1).
  - Raw size: linux-64 210.0 MB, linux-aarch64 195.9, osx-64 157.3,
    osx-arm64 144.0, win-64 190.3 (ST §1; the driver is 136-196 MB of
    it). No file has a prefix placeholder in any of the 15 packages, so
    every copy is the package's bytes.
  - Made by zigbuild/toolchain/build.zig, with a copy driven by the
    conda-meta record (open point A). Every flang copy is `in_conda =
    false`, and its trees are skipped like copies when the prefix is the
    env (Cc4): conda keeps depending on flang-zig and has no TC/flang
    (B30, B41).
- **zig-fc sends every link through zig** (PLAN facts 600-603; reverses
  F3c's "a mixed call stays flang's"):
  - a link of objects, shared or executable: zig cc as today's shared
    link, with the runtime;
  - a call with sources and a link (configure's `$FC -o conftest
    conftest.f`, `-shared -o p.so a.f b.o`): `flang -c` per Fortran
    source into a temporary directory, its arguments less the measured
    link-only options flang refuses (Cc1), then the zig link with each
    Fortran source replaced by its object; a C-family source stays on
    that zig line, which compiles and links it as zig-cc does (Cc7); then
    the directory removed (open points E, F, G);
  - compile-only calls and probes: flang, as today.
- **zig-fc passes `-fintrinsic-modules-path`** on every call that reads
  Fortran source and is not a probe (`-c`, `-S`, `-E`, `-fsyntax-only`
  and the split's compiles, Cc9), from flang's own location (open point
  D), after the caller's arguments. In a conda env it repeats the path
  flang.cfg already names. Measured (Cc13, CP1/CP2): linux's and
  Windows' drivers find their modules under their default triple
  without it; macOS's does not, so the flag is what makes macOS work,
  and one rule on every OS.
- **B40's Fortran half** (Cg1, open point U): `omp_lib.mod`,
  `omp_lib_kinds.mod` and `omp_lib.h` sit in flang's one module
  directory, so on minimal (no libomp) `use omp_lib` compiles and the
  link fails on the `omp_*` symbols. Recorded as B40's Fortran limit and
  asserted once in minimal's verify-bundle; no second module tree.
- **rzig's runtime lookup needs no change**: `flang_rt.flang` already
  looks in `TC/flang/bin` first, and `flang -print-resource-dir` gives
  `TC/flang/lib/clang/23` (SR §1.1, §1.3). On Windows that holds without
  `Library/` as long as the layout above is kept (checked on kappa,
  step 3).
- **`-lc++` and `link_libcpp` go** where step 3's runs pass (open point
  K): rzig's `flibs` on Windows, Makeconf.win's FLIBS, and
  linkFortranRt's `link_libcpp` on macOS and Windows. flang-rt-zig 10's
  archives reference no C++ runtime symbol on any OS (ST §4, SR §2).
- **rzig's compilers text** (B35, TODO:678-679): the standalone line
  names the archive for flang too, and no longer says "put LLVM flang on
  PATH" (open point M).
- **verify-toolchain checks flang/**: its copies and records, its
  binary's closure, and `flang --version` against SOURCES' flang-zig
  version (open point I).
- **verify-bundle scenario 2 compiles Fortran with TC/flang only**: no
  flang on PATH and no `.cfg` file anywhere in the extracted tree. New: a
  derived-type module (two files, `use` across them) through rzig build
  and R CMD SHLIB, a configure that compiles, links and runs a program
  with `$FC`, RZIG_PRINT_ARGV showing `TC/flang/bin/flang` compiling and
  zig linking, and the first Fortran compile timed with an empty zig
  cache. Existing: USE_FC_TO_LINK, `use omp_lib` on two threads (slim
  and full, B40), FLIBS, the SHLIB Fortran shapes. The no-flang checks
  move `TC/flang/bin/flang` aside (open point N).
- **Compression (B13)**: the compilers archives are measured with flang
  in step 2. ST's estimates put linux-64's `.tar.gz` at about 150.8 MB
  and win-64's `.zip` at about 160.0 MB. If any measured archive is over
  150 MB, the compilers archive becomes `.tar.xz` on every platform,
  Windows included with no condition: about 78-95 MB (open point L;
  Cg2). On Windows R's own `untar()` reads it wherever the base is
  installed, and System32's `tar.exe` where its build has liblzma, so
  no OS keeps another format (Cc5's `.zip` fallback not taken).
- **Records**: the carve script's cross-check, once (open point J); the
  sizes, times and host results in PLAN.md's phase 6 record.
- **Build number 12** (B14 a; open point R): rzig changes (zig-fc,
  groups.zig), and so do Makeconf.win and, on macOS and Windows, libR,
  Rblas and Rlapack. r-zig-slim and the r-zig wheel carry these. The
  conda and PyPI contents do change (rzig's bytes, on every OS), so 12
  follows from B14 (a) whether or not any K drop lands (Cc18); the wheel
  gains no Fortran (B29 a).

Not in phase 6:
- conda: no TC/flang (B30, B41); r-zig-compilers keeps depending on
  flang-zig `*_6`, lld-zig `*_5` and flang-rt-zig `*_10` (open point Q).
- PyPI: no Fortran (B29 a); make-wheel.py takes only `usr/` from the
  tree.
- Dev compiles keep the env's flang with its flang.cfg: compile-tree.sh
  leaves `zig/` and `flang/` out (C12), so contract, pkg-parity and
  stress run zig-fc against the env's flang. That is also phase 6's
  "conda env" coverage of the new zig-fc.
- A flang-pixi change: none is needed for the tree (ST §8, SR §4). If a
  host run finds one, it becomes an open item for the user (B44; this
  run's rule: nobody contacts flang-pixi, nothing is filed).
- `ISO_Fortran_binding.h` (C calling Fortran descriptors): rzig puts no
  flang include directory on any path today, conda included (ST §1).
  A scope decision, now a lettered point (V, Cg5): left out, the same on
  every channel, added with an include rule if a package needs it.
- The groups' licence completeness (a "Later" menu since phase 5): phase
  6 records what flang/ adds to it (section 10).
- zig 0.17 and flang-pixi's 0.17 set (B18 a, HANDOFF §11): no pin moves.
- Windows' `usr/bin` (phase 7), the base's runtime records (phase 8).

## 1. Sequencing and preconditions

- **Stacked on three uncommitted branches.** This worktree is main
  d11dee1 + phase 4 (build 9) + SHLIB (10) + phase 5 (11), none
  committed. No other worktree is touched.
  - Phase 6 edits files the baselines edit: verify-bundle.sh (SHLIB's
    and phase 5's largest), zigbuild/toolchain/build.zig and
    verify-toolchain.sh (phase 5), groups.zig and parity-test.sh (phases
    4 and 5), recipe/recipe.yaml (the number), README.md, PLAN.md and
    TODO.md. So phase 6's diff is against the phase 5 baseline, never
    against main (open point S).
  - At the start the implementer records, in `phase6/implementer/`:
    `git diff | sha256sum`, `git status --short`, and the sha256 of each
    untracked baseline file. The final `phase6-only.diff` is made
    against these (step 8).
  - Merge order: phase 4's PR, then SHLIB's, then phase 5's, then phase
    6's. If the user folds them differently, the build number follows
    (open point R).
- **universe** held `_8` and nothing newer when phase 5 ended. Phases 4,
  SHLIB and 5 (9, 10, 11) are unpublished. Phase 6 takes 12. Check again
  with `pixi run -e pkg conda-channel-list universe <subdir>` before
  merging.
- **The env.** The worktree has no `.pixi/envs/` (ST). The implementer
  installs `default` (then `minimal`, `wheel`, `pkg` as the steps need
  them) with `PIXI_CACHE_DIR=/data/gamma/luciorq/workspaces/temp/r-zig-pixi/pixi-cache-p6`
  and `TMPDIR` under `phase6/implementer/tmp`, for every pixi run.
  zigbuild/toolchain/build.zig reads licences and recipes from that
  package cache (`extracted_package_dir`), so the cache must be the one
  the env was installed from.
- **Disk.** `/` had 7.9-8.1 GB free during the surveys and planning; the
  stop line is 6 GB (`df -h /` before each long run, and on any drop
  stop and report). Everything goes under /data: the worktree's
  `.pixi/`, `build/` (env.sh's zig caches are there), `dist/`, the pixi
  cache, and TMPDIR (verify-bundle's VERIFY_DIR, zig-fc's split
  objects). Per gamma: the default env and its cache take several GB;
  the tree grows by about 210 MB, each compilers archive by 40-63 MB
  (xz) or 150 MB (gzip); each verify-bundle pass extracts about 0.9 GB
  (base + zig 360 MB + flang 210 MB) and removes it before the next
  pass starts (phase 5's Cc4 rule).
- **Network.** `pixi run toolchain` fetches the ziglang wheel once (phase
  5). The carve cross-check needs `pixi exec --spec "python>=3.14"`,
  outside the lock, under PIXI_CACHE_DIR (open point J).
- **flang-pixi's clone** (`/home/luciorq/projects/flang-pixi`) is read
  only: the carve script is copied into `phase6/implementer/carve/` and
  run from there.
- **Ownership** (parallel testers): one owner per host; gamma's owner
  owns `dist/` and the builds there; remote testers own their hosts; no
  one writes pixi.lock; each records the lock's sha256 and `git diff |
  sha256sum` at the start and the end; scratch and TMPDIR under
  `phase6/<role>/`. omicron's osx-64 copy (re-solved for osx-64 under
  Rosetta) and its lock stay in the tester's scratch and are never
  synced back.
- **The K prototypes are one recorded patch** (Cc14): before step 3 the
  implementer writes the three drops (rzig's Windows `flibs` without
  `-lc++`, Makeconf.win's `FLIBS = -lflang_rt.runtime`, linkFortranRt
  without `link_libcpp`) as `phase6/implementer/k-drops.diff` with its
  sha256. Each host applies it to its own scratch copy (never to this
  worktree), records the diff's sha256 and its copy's `git diff |
  sha256sum`, and reverts it after; step 5 lands exactly that diff's
  hunks for each OS whose run passed.
- **linux-aarch64** has no interactive host: CI's ubuntu-24.04-arm leg
  (`full-ci`) is its B44 run (open point T). It runs only after the
  user pushes, as do native osx-64 (macos-15-intel under `full-ci`) and
  the `upstream-zig` label run (Cg3). This run allows no push, so phase
  6 ends here as "pending CI", never "done", and the hand-over says so
  (section 11, open items). Before that, a recorded pre-check on gamma
  that needs no emulator (Cg3, CA: the x86_64 driver has the AArch64
  backend): step 3's gamma part.

## 2. Steps

Each step is a local checkpoint that leaves every test it names green.
CI sees only the PR's final state. From step 2 on the compilers archive
holds flang/, so verify-package is named only from step 6, which is
where verify-bundle's Fortran blocks learn about TC/flang (until then
"zig-fc with no flang" would find TC/flang and fail its exit-127
check).

1. **zig-fc: the modules flag and every link through zig** (open points
   D, E, F, G), on today's tree and the dev env.
   - Changes: zigbuild/tools/rzig/fortran.zig (the call kinds, the split,
     the flag), Ctx.zig (a command of several steps), main.zig (running
     and printing them), cmdline.zig (Fortran's options that take a
     value), flang_rt.zig (`modulesDir`, `globDirs` made public), and
     their unit tests (section 3). `flibs` keeps `-lc++` until step 5.
   - Over 200 lines (fortran.zig, main.zig, Ctx.zig): a skeptical diff
     review before the tests: the unix exec/spawn split (a single command
     still execs), every exit code and the temporary directory's removal
     on each path (success, a compile failing, the link failing, a
     spawn failing, a step killed by a signal: 128+n on unix, Cc15),
     Windows paths (`\` in TEMP, `.exe` on executables,
     `windows.implib`'s discard list still deleted, no TEMP and no TMP:
     the output's directory, Cc15), `-o` absent (`a.out`, Windows
     `a.exe`), a source given twice, two sources with one base name in
     different directories, the compile-side list (Cc1) taking each
     option with its value, the `ZIG_LIB_DIR=` line's place in a dry run
     (Cc6).
   - Before the tests, the measured lists (Cc1): the compile-side list is
     CA's refused set, re-measured on gamma with the env's `flang-23`
     (`flang -Qunused-arguments -c s.f90 -o s.o <flag>` per entry,
     recorded); `-Xflang <v>` is tried on zig cc's link too (CA measured
     it on flang only) and joins `linkArgs` if zig refuses it.
   - Tests:
     - `zig fmt --check zigbuild/tools/rzig/`.
     - `pixi run rzig-test` with conda-forge's zig and with upstream zig
       (`ZIG_BIN="$(pixi run fetch-zig)"`): the unit tests and
       parity-test.sh (linux).
     - The unit tests named in section 3 (fortran.zig): compile-only,
       `-fsyntax-only` and probes stay flang's, with the flag on every
       call that reads Fortran source but no probe (Cc9); links of
       objects, shared and executable, go to zig with the runtime; a
       source plus a link splits (Fortran, `-x f95`, `-x
       f95-cpp-input`, a C source left on the zig line (Cc7), two
       sources with one base name, `-J dir` kept off the link, `-Mfree`
       dropped from it, `-dynamiclib -undefined dynamic_lookup` and
       `-static-libgcc -s` kept off the compile and on the link (Cc1,
       Cc2)); the flag's directory found under a fixture `TC/flang`
       tree, a linux-style twin (directory + symlink) and a
       Windows-style twin (two directories), the CPU-named directory
       before another CPU's (Cc8, Cg8), the `lib/clang/<v>` that holds
       `finclude/flang/` before one that does not (Cc8), no `..` and no
       `\` in the result (Cc3), and absent when there is none;
       RZIG_PRINT_ARGV's blocks, with `ZIG_LIB_DIR=` set (Cc6).
     - By hand, linux-64, in `phase6/implementer/proto/`, both zigs, in
       the dev env (a conda env with flang.cfg; R from `pixi run
       build`): `R CMD config FC` → zig-fc; `$FC -o conftest conftest.f
       && ./conftest`; `$FC -v -o conftest conftest.f` (exit 0, zig's
       `ld.lld` line on stderr); `$FC -shared -o m.so m.f90 u.f90` (a
       derived-type module, `use` across the two files); `use omp_lib`
       with `-fopenmp` into an executable that reports two threads; each
       with RZIG_TRACE=1 (the flang compiles, then the zig link). No
       `rzig-fc-*` directory is left under TMPDIR after any of them,
       including one whose compile fails.
     - The same by hand with a prototype layout:
       `phase6/implementer/proto/R-4.6.1-zig/lib/R/bin/toolchain/flang/`
       filled by hand from the env (driver, the module directory, the
       runtime; no cfg), rzig copied beside it as `zig-fc`, under `env
       -i HOME=... PATH=/usr/bin:/bin ZIG_BIN=<zig>`, once with
       conda-forge's zig and once with `$(pixi run fetch-zig)` (the
       prototype has no `zig/`, and gamma has no zig on that PATH, CA;
       Cc16): the same five calls pass, and `RZIG_PRINT_ARGV=1` shows the
       prototype's `flang/bin/flang` and `-fintrinsic-modules-path
       <proto, physical>/flang/lib/clang/23/finclude/flang/x86_64-conda-linux-gnu`
       (no `..` in it, Cc3).
     - Recorded, not a gate (Cg9): the same five calls with a flang that
       is not flang-zig, conda-forge's linux-64 `flang` through `pixi
       exec --spec flang` under PIXI_CACHE_DIR (outside the lock, as
       J's python and the CMake run), PATH holding only its bin:
       whether `flang_rt.find` finds its runtime (it globs `.a` only)
       and the executable links and runs. This is the PyPI channel's
       "a user's own flang" case, whose executable links and configure
       probes now go through zig too.
     - `pixi run contract` (minqa, quadprog: zig-fc with the env's flang
       and its cfg, the flag repeated) and `pixi run pkg-parity`.
     - A CMake Fortran project (`project(x Fortran)`, an executable from
       one `.f90`) configured with `FC=<zig-fc>` through `pixi exec
       --spec cmake` under PIXI_CACHE_DIR: it configures and builds.
       Recorded, not a gate: CMake parses the `-v` link line for
       implicit libraries, and it is now zig's (SR §3.3, risk 4).
2. **`TC/flang/` in the toolchain tree** (B9 a; open points A, B, C, H,
   I, J).
   - Changes: zigbuild/toolchain/conda.zig (`path_type` in
     `Record.Path`; `under`, the record's regular files under a
     directory); zigbuild/toolchain/build.zig (the flang directory: the
     driver as a renamed copy, the modules and the runtime by record;
     `readRecords`' needles; the header comment; the summary);
     scripts/verify-toolchain.sh (the flang check, the positive binary
     check for `flang/bin/flang`, the header).
   - Tests:
     - `zig fmt --check zigbuild/toolchain/`; `bash -n
       scripts/verify-toolchain.sh`.
     - `pixi run toolchain-test` with both zigs: conda.zig's new tests
       (`under` keeps hardlink entries only, drops softlinks and other
       directories; `Library/` dropped from `to`).
     - The conda rule before conda-package (Cc4): a scratch env
       `phase6/implementer/fakeenv/` holding a copy of the default env's
       `conda-meta/` only; `CONDA_PREFIX=<fakeenv> zig build
       --build-file zigbuild/toolchain/build.zig --prefix <fakeenv>`
       prints "nothing to install" on linux (no flang tree is listed,
       none stops the build), and writes nothing under it but zig's
       caches (`find <fakeenv> -newer <stamp> -type f` empty). Never
       with the real env as the prefix.
     - `pixi run toolchain` with both zigs: the summary names `flang/
       (flang-zig, flang-rt-zig)`, copy order (Cc17, point X);
       `pixi run verify-toolchain` passes
       and prints the flang line and its time (record). Listing:
       `TC/flang` has exactly `bin/flang`, 18 module files under one
       directory, one `libflang_rt.runtime.a`, SOURCES, the two licence
       files; `find TC/flang -type l` is empty; no `*.cfg`.
     - `cmp TC/flang/bin/flang $CONDA_PREFIX/bin/flang-23`;
       `TC/flang/bin/flang --version` says 23.1.1;
       `TC/flang/bin/flang -print-resource-dir` is
       `TC/flang/lib/clang/23`; a `use iso_c_binding` and a `use
       omp_lib` compile with only `-fintrinsic-modules-path` from the
       tree.
     - The bare driver, recorded per OS (Cg4, Cc13): `TC/flang/bin/flang
       -c use_iso_c_binding.f90` with no flag (linux-64 here: CP1 says it
       passes; omicron and kappa in step 3). README does not depend on
       the result: it says one thing on every OS (section 3, README).
     - The record reader (Cc10, point W): a fixture conda-meta in
       toolchain-test where a second package also lists a file under
       `lib/clang/23/finclude/flang/`: the build stops with the
       two-owners message.
     - The conda path: in step 7's `pixi run -e pkg conda-package`, the
       build log's toolchain line names no `flang/` and every package's
       `package_contents` check passes (none holds
       `bin/toolchain/flang`).
     - Negative cases on a copy of the tree under `phase6/implementer/`
       (`verify-toolchain.sh <copy>`): a changed module file (sha256
       mismatch), the runtime deleted (in SOURCES, missing), a stray
       `bin/flang.cfg` (no file line), `flang/bin/flang` replaced by a
       script that prints another version (the version check fails).
     - `pixi run package-toolchain`: the compilers archive's size and
       member count in today's format (`.tar.gz`, Windows `.zip`):
       B13's measurement (record it on every host). `pixi run
       unpack-toolchain` and verify-toolchain again (the tree from the
       archives).
     - The carve cross-check, once (open point J), in
       `phase6/implementer/carve/`.
     - `pixi run compile-tree`, then `contract`: the compile tree has no
       `flang/` (C12).
   - Then hosts: omicron (osx-arm64, and osx-64 under Rosetta) and kappa
     run `toolchain`, `verify-toolchain`, `package-toolchain` on this
     worktree's state, so step 3 has their trees and B13 their sizes.
3. **The hosts' prototype runs** (PLAN phase 6's "prototype first"; open
   points K, K2, L, T; B44). As soon as steps 1 and 2 exist, before step 4. Each
   host builds R with this worktree's state (`build`, `toolchain`,
   `package`, `package-toolchain`), extracts base + compilers +
   build-tools into a scratch directory, and, with no flang on PATH and
   ZIG_BIN unset, runs:
   - every OS: the five calls of step 1 through the bundle's zig-fc;
     `R CMD INSTALL` of a Fortran package with a derived-type module
     (rzig build, tier 1), of a USE_FC_TO_LINK package, and of an
     OpenMP Fortran package (`use omp_lib`, two threads); `include
     'omp_lib.h'` (not `use`) with only zig-fc's flag, and the same file
     through `$FC -E` (Cc9; ST T6-7); the bare-driver probe (Cg4:
     `TC/flang/bin/flang -c use_iso_c_binding.f90`, no flag, recorded);
     the compile-side list (Cc1): each entry re-measured with the host's
     driver, anything else the host's link lines carry that flang
     refuses added with its measurement.
   - The K drops come from `phase6/implementer/k-drops.diff` (Cc14),
     applied to the host's scratch copy, its sha256 recorded, reverted
     after. (The drops are in the tree since step 5: a host whose run
     fails takes its OS's drop back on its copy with `patch -p1 -R` of
     `phase6/fix/k-revert-windows.diff` or `k-revert-macos.diff`.)
   - kappa (win-64): `TC/flang/bin/flang.exe -print-resource-dir` is
     `...\toolchain\flang\lib\clang\23` with no `Library/` (the
     runtime found, rzig's warning absent); `TC/flang/bin/flang.exe -###
     -c a.f90` from the extracted tree names only paths under it (no
     `.cfg` read, no resource dir outside it: kappa is flang-pixi's
     build host, Cg10); then the `-lc++` drop:
     rzig built with `flibs` = `-lflang_rt.runtime` only, R built with
     Makeconf.win `FLIBS = -lflang_rt.runtime` and linkFortranRt without
     `link_libcpp`, then `pixi run check` (R's own tests, LAPACK's
     included), quadprog, minqa, the three packages above, and `nm`
     of R.dll, Rblas.dll and Rlapack.dll: no new undefined import.
     Then the archive readers for open point L, recorded (Cc5, Cg2):
     System32's `tar.exe --version` (its `liblzma/` component, or none)
     and the Windows build (`cmd /c ver`); System32's `tar.exe` lists and
     extracts `R-...-compilers.tar.xz` made by `tar -cf - | xz -9 -T0`
     (timed, or its failure); R's `untar(<file>, exdir = ., tar =
     "internal")` of the same file under the base's Rscript (timed).
     R's `untar()` must pass: it is the reader the README names for
     every Windows; if it fails, stop and report (blocking for win-64's
     format, not a planned fallback).
   - omicron (osx-arm64; osx-64 under Rosetta): `link_libcpp` dropped
     from linkFortranRt; `pixi run check`; the three packages; Rcpp's
     and RcppArmadillo's install and load (C++ with FLIBS); `nm -gU
     libR.dylib | c++filt | grep -c 'std::'` before and after the drop
     (does libR export libc++ symbols that a package could have
     resolved through `-undefined dynamic_lookup`? risk 3, K's macOS
     sub-point (Cg5): the drop stays with both counts recorded);
     `___cxa_atexit` resolves from libSystem (`nm -m` of a linked
     package). For `TC/flang/bin/flang` on both subdirs (Cc11):
     `codesign -dv` (Signature=adhoc, no linker-signed flag), `codesign
     -v` (valid), `spctl -a -t exec` (expected "rejected", and it runs
     with no prompt), and whether the endpoint agent touches the 147 MB
     osx-64 copy (phase 5's K wording); `flang -### -c a.f90` names only
     paths under the extracted tree (Cg10).
   - gamma (linux-64): the same packages (linux never had `-lc++` or
     `link_libcpp`, so only the TC/flang half). Then linux-aarch64's
     pre-check, recorded and not a gate (Cg3): with the surveyor's
     lock-checked aarch64 packages (`phase6/surveyor-tree/x/linux-aarch64/`),
     gamma's x86_64 `flang --target=aarch64-unknown-linux-gnu -c` of
     `p.f90` and the derived-type module with `-fintrinsic-modules-path`
     at the aarch64 module directory, then `zig cc -target
     aarch64-linux-gnu.2.17 -mcpu=baseline` linking them with the
     aarch64 `libflang_rt.runtime.a`, through the same `linkArgs` and
     `flibs` (an rzig dry run's argv, retargeted); the link succeeds and
     `file` says AArch64. It cannot run the program (no emulator, CA).
   - Results: each passing item of K takes its drop in step 5; a failing
     item keeps its flag and is recorded (open point K). A failure whose
     cause is in flang-zig or flang-rt-zig is an open item for the user
     (B44), and that OS does not finish phase 6 (section 11, "Open items
     for the user").
4. **Compression and the compilers line** (B13, B35, B17; open points L,
   M).
   - If no compilers archive measured in steps 2-3 is over 150 MB, B13
     (a) stays: no format change, and this step changes only groups.zig's
     line (today's extensions).
   - Otherwise (expected: linux-64 and win-64 are over), on every
     platform with no OS condition (Cg2; per group, never per OS, Cg11):
     - scripts/env.sh: `group_ext <group>` (compilers `tar.xz`, others
       `$ARCHIVE_EXT`), its comment naming groups.zig's `archiveExt` as
       the reference (B35: rzig's text is the reference) (Cg11);
     - scripts/package-standalone.sh: a `tar.xz` branch;
     - scripts/verify-helpers.sh: `archive_files` and `extract_archive`
       read `*.tar.xz`;
     - scripts/unpack-toolchain.sh and scripts/verify-bundle.sh (two
       sites each): `group_ext` instead of `$ARCHIVE_EXT`;
     - zigbuild/tools/rzig/groups.zig: the compilers archive's extension
       is `tar.xz` on every platform.
   - groups.zig's standalone line names flang (M), its header comment,
     its tests; parity-test.sh's anchored grep; wheel-test.sh's grep.
   - Tests:
     - `bash -n` on the four scripts; `zig fmt --check
       zigbuild/tools/rzig/`.
     - `pixi run rzig-test` with both zigs.
     - `pixi run package-toolchain`: `dist/R-4.6.1-linux-64-compilers.tar.xz`
       and its `.sha256`, size, time (record); build-tools still
       `.tar.gz`; `sha256sum -c` passes. `pixi run unpack-toolchain`
       then `verify-toolchain` (the tree from the `.tar.xz`).
     - `git grep -n 'LLVM flang on PATH' -- ':!.github/devdocs'` finds
       only make-wheel.py and python/r_zig/__init__.py (PyPI's text,
       unchanged).
5. **`-lc++` and `link_libcpp` dropped where step 3 passed** (open point
   K).
   - Changes (each only if its run passed, exactly k-drops.diff's hunk
     for it, Cc14; after steps 5 and 6 k-drops.diff is the record of
     what landed, and a host takes an OS's drop back with
     `phase6/fix/k-revert-windows.diff` or `k-revert-macos.diff`,
     `patch -p1 -R`, made against the tree): fortran.zig `flibs` (Windows `-lc++` gone) and its
     comment; build.zig's Makeconf.win `FLIBS =
     -lflang_rt.runtime` and its comment; linkFortranRt without
     `link_libcpp`, its comment and the zig-lib-dir comment that cites
     it; the tests that pin `-lc++` (fortran.zig, compiler.zig,
     flang_rt.zig, parity-test.sh's two Windows cases); verify-bundle's
     Windows dry run (its `-lc++` assertion becomes "no `-lc++`").
   - Tests: `pixi run rzig-test` (both zigs); `pixi run build`, `smoke`,
     `contract`, `verify-tree` on gamma (linux: nothing changes, libR's
     bytes compared with step 2's, equal); omicron and kappa repeat their
     step 3 runs on the final code.
6. **verify-bundle with TC/flang** (open points N, O; PLAN phase 6's
   tests).
   - Changes: scripts/verify-bundle.sh (section 3).
   - Over 200 changed lines: before the tests, a skeptical diff review
     (Windows: `cygpath -m -l`, `flang.exe`, `\` in RZIG_PRINT_ARGV's
     lines, the case-insensitive greps; every former `fc_dir` site;
     every no-flang check restores `flang/bin/flang` on every exit path;
     nothing dropped from SHLIB's and phase 5's blocks; the `-lc++`
     assertion per step 5).
   - Tests (gamma):
     - `bash -n scripts/verify-bundle.sh`.
     - default env, conda-forge's zig: `build`, `package-toolchain`,
       `verify-package`. Both passes: the Fortran lines name
       `TC/flang/bin/flang` in each; the first Fortran compile's line
       (toolchain pass) is recorded; the last "verified" line names the
       build pass.
     - upstream zig: `export ZIG_BIN="$(pixi run fetch-zig)"`, then
       `build`, `toolchain`, `package-toolchain`, `verify-package` (the
       one-zig pass; the build pass skipped).
     - minimal: `pixi run -e minimal build && pixi run -e minimal
       verify-package` (no OpenMP checks, B40; every other Fortran check
       runs; and the one assertion of B40's Fortran limit, U: a `use
       omp_lib` program built through zig-fc with `-fopenmp` compiles
       and its link fails, naming an undefined `omp_` or `__kmpc_`
       symbol (Cg1)).
     - A negative run: with `TC/flang` removed from the extracted tree by
       a one-line edit in a scratch copy of the script, the toolchain
       pass fails at its first Fortran check, naming the compilers group.
7. **Docs, comments, build number, the other channels** (open points P,
   Q, R).
   - Changes: README.md; build.zig's stale comments (flang "NOT
     bundled"); scripts/env.sh and compile-tree.sh comments;
     zigbuild/toolchain/build.zig's header; .github/workflows/toolchain.yaml's
     comments; pixi.toml's archive comments (comments only);
     recipe/recipe.yaml `number: 12` with its history entry;
     recipe/test-compilers.R's configure-style probe (P).
   - Tests:
     - after the pixi.toml comment edit: `sha256sum pixi.lock` still
       starts with fbb64b7ba4e31e45, and `pixi lock --check` passes.
     - actionlint on toolchain.yaml.
     - `pixi run -e pkg conda-package` (four tests, both `--error-*`
       flags), then `pixi run -e pkg conda-consume`: zig-fc's split with
       the env's flang and its cfg (P's probe), no `bin/toolchain/flang`
       in any package.
     - `pixi run -e minimal build`, `-e minimal toolchain`, `-e wheel
       wheel`, `-e wheel wheel-test`: zig-fc with no flang exits 127
       with the new compilers text and the pip line.
     - The default chain end to end (PLAN's Verification block):
       `rzig-test`, `toolchain-test`, `build`, `toolchain`, `verify-tree`,
       `verify-toolchain`, `smoke`, `contract`, `hermetic`, `pkg-parity`,
       `package-toolchain`, `verify-package`.
8. **Other hosts, CI, the records, the hand-over.**
   - omicron (osx-arm64; osx-64 under Rosetta), kappa (win-64), CI
     (section 6), each passing (B44).
   - The measurements (section 7) and the cross-check into PLAN.md's
     phase 6 record; the records and stale references (section 10).
   - `phase6/implementer/phase6-only.diff`, made against the step-0
     baseline (open point S), and the commit commands for the user,
     with no trailer and no session link.
   - The hand-over and PLAN's status line say "phase 6 pending CI"
     (Cg3): linux-aarch64 (its only B44 run), native osx-64
     (macos-15-intel) and the `upstream-zig` label run happen only after
     the user pushes; the PR does not merge before they pass (T).

## 3. Per file: the exact change

### zigbuild/tools/rzig/fortran.zig (step 1; open points D, E, F, G)

The module doc (lines 1-45) is rewritten for the new rule; F3c's "A
mixed call stays flang's" paragraph goes, replaced by why (PLAN facts
600-603, HANDOFF §8: flang's own driver link needs ld.lld and a sysroot
on linux, SDKROOT on macOS, ld.lld and a CRT snapshot on Windows, none
of which a standalone tree has; zig links what it compiled).

`command(ctx, caller)`:

```zig
pub fn command(ctx: *Ctx, caller: Args) !Ctx.Command {
    const flang = (try flang_rt.flang(ctx)) orelse { ...NoFlang as today };
    const floor: Args = if (ctx.os == .macos) &.{floors.macos_min_flag} else &.{};
    switch (kind(caller)) {
        // -c/-S/-E/-M/-fsyntax-only, --version, -v alone, -print-*, -###, no input
        .flang => return .{ .program = concat(flang, floor, caller, modules(ctx, flang, caller)) },
        // a link of objects (shared or executable): zig, as zig-cc links
        .link => return .{ .zig = try compiler.argv(ctx, .c, concat(linkArgs(caller), flibs(ctx.os))) },
        // sources and a link: a compile per source, then that link
        .split => return split(ctx, flang, floor, caller),
    }
}
```

- `kind`: `.flang` when `cmdline.compileOnly` or `-fsyntax-only` is
  there (Cc9: flang checks and writes nothing to link), when a probe word
  is there (`--version`, `-###`, `--help`, `-dumpversion`,
  `-dumpmachine`, `-print-*`), or when the call has no input (`-v`
  alone, `[]`); `.split` when an input is a Fortran source (by
  extension, or under an `-x` naming Fortran: F); `.link` otherwise (a C
  source with no Fortran one is zig's whole, as for zig-cc, Cc7). Inputs
  come from `cmdline.inputs` with Fortran's and the link's value-taking
  options (cmdline.zig below, Cc2), so `-J dir`'s `dir` and `-undefined
  dynamic_lookup`'s value are no input.
- `modules(ctx, flang, args)`: `&.{ "-fintrinsic-modules-path", dir }`
  on a call that reads Fortran source and is no probe (`-c`, `-S`, `-E`
  or `-fsyntax-only` with a Fortran source, and every split compile;
  Cc9: flang's prescanner finds `include 'omp_lib.h'` through the
  intrinsic module path, so `-E` needs it on macOS, CP2), else nothing.
  `dir` is `flang_rt.modulesDir(ctx, flang)`; null gives nothing. Placed
  after the caller's arguments: flang searches module paths in order, so
  a caller's own `-fintrinsic-modules-path` (or `-I` holding the same
  modules) wins, as the macOS floor goes first so the caller's own
  `-mmacosx-version-min` wins. Needed on macOS only (its driver's
  default triple has no module directory); linux's and Windows' drivers
  find theirs without it (Cc13, CP1); passed everywhere, one rule.
- `linkArgs(args)`: `args` without the flags zig cc refuses on a link,
  measured (PP), one list with its comment: `-J` and its value (the
  separate form; `-J<dir>` passes), `-Mfixed`, `-Mfree`, `-Mextend`,
  `-fno-fortran-main` (and `-Xflang <v>` if step 1 measures zig refusing
  it). Hosts add to the list only what a step 3 run shows, each with its
  measurement, recorded as E (a)'s answer covers (Cg5). Used by `.link`
  and by the split's link. (`.link` is today's `sharedLink` widened to
  executables: an executable link of objects was flang's, which needs
  ld.lld outside conda.)
- `compileArgs(args)` (Cc1): `args` without the link-only options
  flang's driver refuses ("unknown argument", even with
  `-Qunused-arguments`, which silences only unused-argument warnings),
  each with its value where it takes one, measured (CA, flang 23.1.1;
  the driver's option table is the same on every host), one list with
  its comment beside `linkArgs`: `-dynamiclib`, `-bundle`, `-undefined`,
  `-framework`, `-weak_framework`, `-F` (both forms), `-install_name`,
  `-current_version`, `-compatibility_version`,
  `-exported_symbols_list`, `-unexported_symbols_list` (by analogy;
  step 1 measures it), `-bundle_loader`, `-multiply_defined`, `-force_load`,
  `-headerpad_max_install_names`, `-single_module`, `-flat_namespace`,
  `-dead_strip`, `-arch`, `-static-libgcc`, `-static-libstdc++`,
  `-shared-libgcc`, `-static-pie`, `-s`, `-mwindows`, `-mconsole`,
  `-municode`, `-mthreads`, `-z`, `-u`, `-T`, `-e`. Two lists, one per
  direction, both measured; a flag on neither list that one side
  refuses fails loudly with that driver's message, never silently.
  Used by the split's compiles only (a `.flang` call is the caller's
  as given, as today).
- `split(ctx, flang, floor, caller)` (E, F):
  - a temporary directory `<tmp>/rzig-fc-<random>`, `<tmp>` being
    TMPDIR, else `/tmp` on unix; on Windows TEMP, then TMP, else the
    output's directory, else the working directory (never MSYS'
    TMPDIR, whose `/tmp` a native rzig cannot use; Cc15), from
    `ctx.env`. Not created in a dry run (its name there is
    `<tmp>/rzig-fc-dryrun`, so RZIG_PRINT_ARGV is reproducible).
  - for each input that is a Fortran source, in the caller's order
    (Fortran modules are compiled in the order given, as gfortran's
    driver does): its object `<dir>/<n>-<basename>.o` (`n` its position,
    so `a/x.f` and `b/x.f` differ) and one step: `flang <floor>
    <compile args> -Qunused-arguments -c <src> -o <obj> <modules
    flag>`, where `<compile args>` = `compileArgs` of the caller's
    arguments without `-o` and its value, without the inputs (every
    source and object) and without every `-x` and its value; a source
    classified by `-x` gets its own `-x <lang>` just before it. The
    link flags that flang accepts but does not use are silenced by
    `-Qunused-arguments` (PP).
  - A C-family source is no step (Cc7): it stays on the link line as
    given, and zig cc compiles and links it in that one call, exactly
    as zig-cc does; "zig links (and compiles) what is not Fortran". It
    gets the caller's flags as a gfortran driver would give them; a
    Fortran-only flag that clang refuses (`-std=f2018`) fails that call
    loudly, recorded as the caller's (risk 16).
  - then the link step: `compiler.argv(ctx, .c, linkArgs(<caller with
    each Fortran source replaced by its object and every -x and its
    value dropped; a C-family source that only an -x classified is
    written `-x <lang> <src> -x none`>) ++ flibs)`. The caller's `-v` reaches both
    (autoconf's AC_FC_LIBRARY_LDFLAGS reads the link line, now zig's
    `ld.lld` line, PP).
  - `.steps = .{ .steps = ..., .tmp = dir }`.
- `flibs` keeps `-lc++` on Windows until step 5; then `.windows =>
  &.{flang_rt.flag}` (if K's kappa run passed) and the doc comment says
  why (no C++ runtime symbol in flang-rt-zig 10's archive, ST §4).
- Tests (replacing "mixed source+link calls ... stay flang's"):
  - "compiles, -E and probes: flang ...": the expected argv gains the
    flag on `-c`/`-S`/`-E`/`-fsyntax-only` calls with a Fortran source
    (Cc9; not `--version`, `-v`, `[]`, a C-only `-E`), placed last, with
    a fixture flang whose
    `../lib/clang/23/finclude/flang/x86_64-conda-linux-gnu/` exists;
    with no such directory, no flag; `-fsyntax-only a.f90` is one flang
    call, no split.
  - "links of objects go through zig": `-o prog a.o b.o` (linux, macOS,
    Windows: `prog.exe` by `windows.exeSuffix`), `-shared ...` as today.
  - "sources and a link split": `-o conftest -O2 conftest.f` (two steps:
    the flang compile with `-O2 -Qunused-arguments -c conftest.f -o
    <tmp>/0-conftest.o -fintrinsic-modules-path ...`, then zig with `-o
    conftest -O2 <tmp>/0-conftest.o <runtime> -lm`); `-shared -o p.so
    a.f b.o`; `-shared -o p.so a.f glue.c` (one flang step, then zig's
    line holding the object and `glue.c`, Cc7); `-shared -x f95 -o p.so
    a` (Fortran by `-x`); `-x f95-cpp-input` likewise; `-o p a/x.f
    b/x.f` (two objects, distinct names); `-J mods -o p m.f90 u.f90`
    (`-J mods` on both compiles, off the link); `-Mfree -o p a.f` (on
    the compile, off the link); macOS: the floor on each flang compile,
    and `-dynamiclib -undefined dynamic_lookup -framework Accelerate -o
    x.so a.f90` (all three, with their values, off the compile and on
    the link, Cc1, Cc2); Windows: `-shared -s -static-libgcc -o x.dll
    a.f90` likewise.
  - "the modules directory": a fixture tree
    `tree/lib/R/bin/toolchain/flang/{bin/flang,lib/clang/23/finclude/flang/<t>/}`,
    the expected string with no `..` and only `/` (Cc3); linux's twin
    (directory + symlink: the directory, byte order); Windows' twin
    (`x86_64-w64-mingw32`, `x86_64-w64-windows-gnu`: the first);
    `aarch64-unknown-linux-gnu` and `x86_64-unknown-linux-gnu` side by
    side (the one named for rzig's CPU, Cc8, Cg8); `lib/clang/{21,23}`
    with only 23 holding `finclude/flang/` (23, Cc8); a flang that is a
    symlink into another tree (its own tree's directory, symlinks
    resolved); none.
  - the no-flang test unchanged; "the compilers group's flang wins over
    PATH's" gains the flag.

### zigbuild/tools/rzig/Ctx.zig, main.zig (step 1; open points E, G)

- Ctx.zig `Command` gains a third kind:

  ```zig
  /// A call that compiles sources and links (zig-fc, fortran.zig): each
  /// step in order, the first failing one's exit code, then `tmp`
  /// removed, whatever happened.
  steps: struct { steps: []const Step, tmp: []const u8 },
  pub const Step = union(enum) { zig: []const []const u8, program: []const []const u8 };
  ```

  and the `discard` comment says it is also deleted after a split on
  unix.
- main.zig:
  - `.steps` resolves each `.zig` step with the found zig (no zig: the
    compilers text and 127, before anything runs) and applies the
    libc++ mirror once, as for a single zig command (unix).
  - A dry run prints each step's argv as today, with a line `&&` between
    two steps (the shell's "then": it cannot be an argument rzig would
    print alone). The `ZIG_LIB_DIR=<v>` line, when the mirror set it,
    is printed immediately before the first zig step's block (it applies
    to zig only), never at the top of a split's output; a single command
    prints as today (Cc6: printArgv prints it first, so on macOS conda
    zig verify-bundle's "first block's first word is flang" would read
    `ZIG_LIB_DIR=...`). RZIG_TRACE prints one line per step, the zig
    step's with its `ZIG_LIB_DIR=` prefix as today.
  - `runSteps`: creates `tmp`, spawns and waits for each step (on unix
    too: a split cannot `execve` and still remove its objects), stops at
    the first nonzero exit or spawn failure (`cannotRun`'s codes), then
    deletes `tmp` and `ctx.discard`, and returns the code. A step killed
    by a signal returns 128+n on unix, as the shell and today's exec give
    (Cc15); on Windows a non-exit termination stays 1, as `run` has it.
    Single commands keep `run` as it is (exec on unix).
  - The module doc's table: `zig-fc  flang for compiles; every link
    through zig cc as zig-cc, with the static Fortran runtime; sources
    and a link: a flang compile each, then that link (fortran.zig)`.
- Tests: the dry run's `&&` format (main.zig's printArgv test, or a new
  one), with ZIG_LIB_DIR set: flang's block first, then `&&`, then
  `ZIG_LIB_DIR=...` and zig's block (Cc6); a unit test of `runSteps`
  with stand-in programs (`/bin/true`, `/bin/false`, and `/bin/sh -c
  'kill -TERM $$'` on unix; skipped on Windows like the shell-script
  stand-ins): the first failure's code, 143 for the killed step
  (Cc15), the later step not run, `tmp` gone; the temporary directory's
  choice on Windows with neither TEMP nor TMP (the output's directory),
  as a pure function of the environment (Cc15).

### zigbuild/tools/rzig/cmdline.zig (step 1)

- `takes_value` gains flang's separate forms: `-J`, `-module-dir`,
  `-fintrinsic-modules-path`. `-J` is also a Fortran compile's module
  output on gfortran-style command lines; without this, `inputs` would
  read its directory as an input file. It also gains the link's
  separate forms it lacks (Cc2): `-undefined`, `-force_load`,
  `-multiply_defined`, `-Xflang`, and the rest of compileArgs' list that
  takes a value and is not there yet (`-unexported_symbols_list` and
  the others are). Before phase 6 only `outputIndex` and zig-cc's
  rewriting read it, where a misread value was harmless; the split now
  builds argv from `inputs`, where `-undefined dynamic_lookup` would
  read `dynamic_lookup` as an input and leave a dangling `-undefined`.
- `isFortran(x)` (Fortran extensions of `source_ext`), and `xLang(args,
  i)`: the `-x` in force at input `i` (`-x f95`, `-xf95`,
  `-x f95-cpp-input`, ... until `-x none`; Cc9), for fortran.zig's
  split.
- Tests: `inputs` skips `-J mods` and `-module-dir mods`; `inputs` over a
  macOS SHLIB-style line, `-dynamiclib -undefined dynamic_lookup -o x.so
  a.f90`, gives only `a.f90` (Cc2); `xLang` on `-x f95 a -x none b.o`
  and on `-x f95-cpp-input a`.

### zigbuild/tools/rzig/flang_rt.zig (steps 1, 5; open point D)

- `pub fn modulesDir(ctx, flang) !?[]const u8`: `flang`'s real path
  (symlinks resolved: a PATH flang symlinked into an LLVM tree finds
  its own tree; conda's `bin/flang` → `flang-23` stays in `bin/`), with
  every `\` turned into `/` (as `find` already does to
  `-print-resource-dir`'s answer); its tree is that path less its last
  two components (the file, then `bin`), cut as strings, so the result
  has no `..` (Cc3: `<TC>/flang/bin/../lib/...` matches neither step 1's
  expectation nor verify-bundle's prefix test). Then
  `<tree>/lib/clang/<v>/finclude/flang/<t>`:
  - `<v>`: the first entry of `lib/clang/` in `globDirs`' byte order
    that holds `finclude/flang/` (Cc8: an env can hold another LLVM's
    `lib/clang/<v>` without Fortran modules);
  - `<t>`: the first entry whose name starts with the CPU rzig was built
    for and a `-` (`x86_64-`; `aarch64-` or `arm64-`, macOS's conda
    triple being `arm64-apple-darwin20.0.0`), else the first in byte
    order (Cc8, Cg8: a PATH LLVM with several targets' modules sorts
    `aarch64-*` first; the `.mod` bytes differ per CPU, ST §1).
  The staged trees have one CPU's directories each (linux-64
  `x86_64-conda-linux-gnu`, linux-aarch64 `aarch64-conda-linux-gnu`,
  osx-64 `x86_64-apple-darwin13.4.0`, osx-arm64
  `arm64-apple-darwin20.0.0`, win-64 the two `x86_64-w64-*`), so on
  them the rule is byte order, which picks the directory flang.cfg
  names in every pinned package (`x86_64-conda-linux-gnu` before the
  `unknown` symlink; `x86_64-w64-mingw32` before
  `x86_64-w64-windows-gnu`) (SR §2), and beside a conda env's cfg the
  flag repeats the same path, which flang takes (PP: exit 0). No process
  is run: three directory reads per Fortran compile. Doc comment: why
  not `-print-resource-dir` (one more flang per compile) and why not a
  triple per platform (it ties rzig to conda's triple names; HANDOFF §1
  warns against a fixed LLVM major).
- `globDirs` becomes `pub`.
- Step 5: the test at line 236 drops its `-lc++` from the Windows case
  only if K's drop lands (the case tests `resolve`, which passes other
  flags through, so it may keep `-lc++` as an ordinary flag: the
  implementer keeps whichever reads true after step 5).

### zigbuild/tools/rzig/compiler.zig (step 5)

- The Windows test at 628-639 (`-lflang_rt.runtime -lc++` on a shared
  link): `-lc++` stays as a caller's flag there (zig resolves it), so
  only its comment changes, saying FLIBS no longer has it.

### zigbuild/tools/rzig/groups.zig (step 4; open point M)

- `text()`'s compilers head:

  ```zig
  "  standalone:  extract {s} where you extracted R (zig {s}, flang and the OpenMP files)\n"
  ```

  The first line ("zig 0.16, and flang for Fortran.") and the pip line
  ("zig only: PyPI has no Fortran compiler") stay.
- The archive's extension: `compilers` → `tar.xz` on every platform
  when L's xz lands (else today's `tar.gz`/`zip`); `build_tools` keeps
  `tar.gz`/`zip`. One function, `archiveExt(g, p)`, with a comment
  citing env.sh's `group_ext` (the two must agree; scenario 1 checks it,
  below).
- The header comment (lines 23-29): "compilers holds zig (from phase 5,
  PyPI's ziglang wheel, B4), flang (from phase 6, flang-pixi's
  flang-zig and flang-rt-zig, B9) and the OpenMP files (C19)", and the
  archive names.
- The tests' expected lines:
  - `  standalone:  extract R-4.6.1-linux-64-compilers.tar.xz where you extracted R (zig 0.16, flang and the OpenMP files)`
  - `  standalone:  extract R-4.6.1-win-64-compilers.tar.xz where you extracted R (zig 0.16, flang and the OpenMP files)`
  - the comment listing who greps what: wheel-test.sh greps the pip line
    and "flang and the OpenMP files".

### zigbuild/tools/rzig/parity-test.sh (steps 4, 5)

- Line 616's anchored grep: `'^  standalone:  extract
  R-[^ ]*-compilers\.tar\.xz where you extracted R (zig [0-9.]*, flang
  and the OpenMP files)\$'`.
- Step 5: the two Windows FLIBS cases (570, 573) keep `-lc++` as
  callers' flags only if their expectations still hold; their names
  drop "then -lc++" if K's Windows drop lands.

### scripts/wheel-test.sh (step 4)

Lines 182-196: the grep "LLVM flang on PATH" becomes "flang and the
OpenMP files" (the standalone line), the pip line's grep stays; the
comment says the compilers archive holds flang since phase 6, and pip
still has no Fortran (B29 a).

### zigbuild/toolchain/conda.zig (step 2; open point A)

- `Record.Path` gains `path_type: []const u8 = ""` (paths_data's
  `hardlink`, `softlink`, `directory`).
- `pub fn under(arena, records, package, dir) ![]const []const u8`: the
  `_path`s of `package`'s record that start with `dir` and are
  `hardlink` entries, in byte order. A softlink (linux's
  `x86_64-unknown-linux-gnu` module directory) is not one, which is how
  it stays out without a rule.
- Tests: a fixture flang-rt-zig record (two module files under the
  conda-triple directory, one under a softlinked directory as
  `softlink`, the runtime, a compiler-rt object elsewhere): `under(...,
  "lib/clang/23/finclude/flang/")` gives the two module files; a
  Windows fixture with `Library\\lib\\clang\\23\\finclude\\flang\\...`
  paths (conda-meta's `\`, read as `/`) gives both twins' files.

### zigbuild/toolchain/build.zig (step 2; open points A, B, C, H)

- Header comment: the table gains

  ```
  //!   flang/     compilers    flang's compile set from the env (B9 a):
  //!                           flang-zig's driver as bin/flang (once),
  //!                           flang-rt-zig's intrinsic and OpenMP
  //!                           modules and its static runtime, by their
  //!                           conda-meta records; no cfg, no lld
  ```

  "flang/ (compilers) comes in phase 6" goes. The conda paragraph:
  "no zig/ and no flang/ there".
- A copy kind that the fixed `Copy` lists cannot express (ST §2): the
  record's regular files under a directory. Shape, kept beside `Dir`:

  ```zig
  /// Every regular file of `package`'s record under `from` (relative to
  /// the env), installed at the same path less a leading `Library/`
  /// (win-64): flang-rt-zig's modules and runtime, whose triple directory
  /// differs per platform and whose module set follows LLVM (B9 a; PHASE6
  /// open point A). None stops the build.
  const Tree = struct { package: []const u8, from: []const u8, name: ?[]const u8 = null };
  ```

  with `name` keeping only files of that base name
  (`libflang_rt.runtime.a` under `lib/clang/23/lib/`). `Dir` gains
  `trees: []const Tree = &.{}` (openmp/, usr/ and binutils/ have none).
  The flang `Dir`:

  The flang `Dir` is written once, as `ompHeaders` already is (Cg6): a
  function of the platform's prefix and driver, called in `unix_dirs`
  with `("", "bin/flang-23")` and in `windows_dirs` with `("Library/",
  "Library/bin/flang.exe")`, so the set (the driver, two trees, the
  runtime's name, the LLVM-major constant) is stated once for every OS:

  ```zig
  fn flangDir(comptime prefix: []const u8, comptime driver: []const u8) Dir {
      return .{ .name = "flang", .copies = &.{.{ .from = driver, .to = "bin/" ++ <flang or flang.exe> }}, .trees = &.{
          .{ .package = "flang-rt-zig", .from = prefix ++ "lib/clang/" ++ llvm_major ++ "/finclude/flang/" },
          .{ .package = "flang-rt-zig", .from = prefix ++ "lib/clang/" ++ llvm_major ++ "/lib/", .name = "libflang_rt.runtime.a" },
      } };
  }
  ```

  (the `to` name from the driver's extension, or a third argument: the
  implementer's choice, whichever reads plainer). The LLVM major `23`
  (`llvm_major`) is a constant beside it, with a comment: it is
  flang-zig's (pixi.toml pins 23.1.1), and a new major moves the pin,
  this constant and SOURCES together (findFlangRt in R's build.zig and
  rzig's modulesDir scan instead because they must find whatever flang
  the env or PATH has; the tree copies what the pin says). That a
  constant here and a scan in rzig state one fact two ways is recorded
  as A's sub-point (A2, Cg5).
- Every tree is `in_conda = false`, and is skipped exactly as a copy
  is (Cc4): when the prefix is the env (`prefix_is_env`), before its
  record is listed, before `conda.find`, and before the empty-tree
  check. Without that, the conda build (recipe/build.sh runs the
  toolchain build with `R_TOOLCHAIN_PREFIX=$PREFIX` and
  `CONDA_PREFIX=$PREFIX`; the host env has flang-rt-zig, recipe.yaml
  273, but not flang-zig, a build requirement) would install
  flang-rt-zig's modules, runtime, SOURCES and LICENSES into
  `$PREFIX/lib/R/bin/toolchain/flang` (hidden from r-zig-slim only by
  the recipe's exclusion) and no longer print "nothing to install".
- Each tree file of the standalone build goes through `conda.find` like
  any copy (owner, no second owner, paths_data sha256, no placeholder);
  an empty tree stops the build ("flang-rt-zig's record lists nothing
  under ..."). The package name in `Tree` only selects which record's
  paths to list; `conda.find` still decides the owner by path (C23).
- `readRecords`' needles (Cc10, point W): a copy's basename as today;
  a tree's `name` when it has one (`libflang_rt.runtime.a"`), else the
  last component of its `from` (`flang`). Both are free of separators,
  so they match Windows' `\\` paths and do not depend on rattler's JSON
  spacing, and every record that lists a file under the tree is read,
  so `conda.find`'s two-owner check sees a second package holding
  `lib/clang/23/finclude/flang/...` (a conda-forge flang-rt beside
  flang-rt-zig). A `"name": "<package>"` needle would read only the
  named package and leave that clobber unseen. The configure step stays
  quick: a few more records (those mentioning `flang`) are parsed.
- The recipe's exclusion of `toolchain/flang/**` (recipe.yaml:375-376,
  520-521) stays as a guard (B41).
- The summary line: `flang/ (flang-zig, flang-rt-zig)`, the order of the
  copies as for every other directory (Cc17, point X).
- Unchanged: `installLicenses` (it already keeps a package's
  `info/licenses/` subdirectories: `LICENSES/<package>/flang/LICENSE.TXT`),
  `readUpstream` (llvm-project 23.1.1's tarball and sha256 as the
  `source:` line; `feedstock: unknown (the package's about.json names
  none)`, open point H), zig/ (phase 5), `samePhysicalDir`.

### scripts/verify-toolchain.sh (step 2; open point I)

- Header: "Every file ... from a conda package (flang/: flang-pixi's
  flang-zig and flang-rt-zig, from universe) or, in zig/, ..."; a new
  item: "flang: flang/bin/flang runs and says the flang-zig version
  SOURCES records".
- The closures block: after the loop, the positive check phase 5 added
  for zig (Cg8) also for `flang/bin/flang` (Windows `flang.exe`) when
  `flang/` is in the tree: "the binary detection missed
  flang/bin/flang". The closure rules need no change: linux's driver
  needs glibc only with GLIBC 2.17 at most and has `$ORIGIN/../lib`;
  macOS's loads only libSystem with minos 11.0; Windows' imports system
  DLLs (ST §1). The runtime archive is not a binary to these checks.
- New, after the zig check:

  ```bash
  # The compilers group's flang (B9 a, phase 6): flang-zig's driver as
  # flang/bin/flang; it runs, and says the version SOURCES records for
  # flang-zig. Its modules and runtime are copies like any other, checked
  # above.
  fl="$TREE/$tc/flang/bin/flang"; [ "$OS" = windows ] && fl="$fl.exe"
  [ -x "$fl" ] || { echo "error: ${fl#"$TREE"/} is missing (the compilers group's flang)" >&2; exit 1; }
  want="$(awk '{ sub(/\r$/, "") } $1 == "package:" { p = $2 } p == "flang-zig" && $1 == "version:" && v == "" { v = $2 } END { print v }' "$TREE/$tc/flang/SOURCES")"
  got="$("$fl" --version 2>&1 | tr -d '\r' | sed -n '1s/^flang version //p')" || true
  [ -n "$want" ] && [ "$got" = "$want" ] ||
    { echo "error: ${fl#"$TREE"/} says '$got', SOURCES records flang-zig '${want:-(none)}'" >&2; exit 1; }
  echo "== flang verified: ${fl#"$TREE"/} $got, the flang-zig version SOURCES records"
  ```

- The build-path scan's note: every OS's driver embeds flang-pixi's
  build paths (Cg10; CA: the linux-64 driver names
  `/data/gamma/luciorq/workspaces/temp/rb-out/bld/...`, which is
  outside every directory the scan looks for on gamma, so it is not
  listed there); on omicron and kappa they are under `$HOME`
  (`/Users/luciorq/...`, `C:\Users\admin\...`, flang-pixi's build
  hosts), so the drivers and darwin/Windows runtimes are listed, never
  failed, as for make (ST §1). No code change: the scan already lists
  copies and fails only SOURCES and LICENSES.

### scripts/env.sh, package-standalone.sh, verify-helpers.sh, unpack-toolchain.sh (step 4; open point L)

Only if L's xz lands (a compilers archive over 150 MB). The rule is per
group, never per OS (Cg2, Cg11): no platform test in `group_ext` or
`archiveExt`.
- env.sh, beside `ARCHIVE_EXT`:

  ```bash
  # A group archive's extension (B17): the compilers group's is .tar.xz on
  # every platform since phase 6, B13: with zig and flang it was over
  # 150 MB in gzip (PHASE6 open point L); the base and build-tools keep
  # ARCHIVE_EXT. rzig's groups.zig (archiveExt) is the reference, as its
  # text is (B35); this follows it, and verify-bundle checks they agree.
  group_ext() { if [ "$1" = compilers ]; then echo tar.xz; else echo "$ARCHIVE_EXT"; fi; }
  ```

- package-standalone.sh `archive()`: a third branch,

  ```bash
  elif [ "${artifact##*.}" = xz ]; then
    # one level for every platform; -T0: as many threads as xz finds
    # cores and memory for (PHASE6 risk 7)
    tar -cf - -C "$parent" "$@" | xz -9 -T0 > "$artifact"
  ```

  (`set -o pipefail` holds in env.sh's scripts: a failing tar fails the
  archive.) The toolchain loop names `$(group_ext "$group")`; the header
  comment's names.
- verify-helpers.sh: `archive_files`'s and `extract_archive`'s `*.tar.xz)`
  cases, `xz -dc "$1" | tar -tf -` and `xz -dc "$1" | tar -xf - -C "$2"`:
  the env's `xz` (xz-tools) on every OS, so GNU tar's `-J` and MSYS
  tar's program lookup play no part; macOS's bsdtar is not used here
  either (the env's GNU tar is first on PATH).
- unpack-toolchain.sh: `$(group_ext "$group")`.

### scripts/verify-bundle.sh (steps 4, 5, 6; open points N, O)

Names (step 4): the two archive loops (lines 139-143, 212) use
`group_ext`. Scenario 1 adds one assertion: the compilers text's
standalone line names `${archives[1]##*/}`, the file this script
extracts (groups.zig's `archiveExt` and env.sh's `group_ext` agree).

flang (step 6):
- `pass_flang`, set where scenario 2 extracts the compilers archive,
  beside `pass_zig`, in both passes (O: TC/flang in both):
  - unix `"$(cd "$TC/flang/bin" && pwd -P)/flang"`;
  - Windows `"$(cygpath -m -l "$TC")/flang/bin/flang.exe"` (rzig prints
    `...\flang\bin\flang.exe`: compared after `tr '\\' /`,
    case-insensitively, as phase 5's Q (a) does for zig).
  - `test -x` first: "the compilers group holds flang since phase 6
    (B9)".
- `fc_dir` (line 612) goes. Every site that used it (the check mode at
  655-663, `pkg_path` at 1239, the no-make SHLIB block at 851-890,
  scenario 3's Windows PATH at 1964-2020) uses no flang directory: zig-fc
  finds TC/flang. The Windows copy dance at 863-881 (flang.exe,
  flang-new.exe, the cfg files, the runtime) is removed: TC/flang is
  that copy, made by the toolchain build.
- After the extraction, two assertions:
  - no `.cfg` file anywhere in the extracted tree: `find "$BUNDLE_DIR"
    -name '*.cfg'` prints nothing;
  - no flang on the check mode's and the compiles' PATHs: `env -i
    PATH="$chk_path" sh -c 'command -v flang'` (Windows: `flang.exe` on
    `$R_BINDIR:$sys32`) finds none; if a host has one in /usr/bin, the
    script notes it and the RZIG_PRINT_ARGV check below still proves
    which flang runs.
- Check mode: `zig-fc --rzig-check` (PATH = `$chk_path`) names "flang at
  $pass_flang" (`grep -qiF`); "flang from TC/flang" in the summary line.
- New, after the first C++ compile: **the first Fortran compile** (PLAN's
  measurement): in a fresh HOME of its own (`$VERIFY_DIR/fhome`, empty
  zig cache, no build runner), `R CMD SHLIB -o fmod.so m.f90 u.f90` (a
  module with a derived type, and a file that uses it; Windows
  `fmod.dll`) under `env -i "${base_env[@]}" HOME=<fhome> ...`, PATH the
  tree's bin alone (Windows bin\x64 + System32), timed with `SECONDS`;
  then loaded and called (`.Fortran` of a routine that builds the type
  and returns a field). It prints "== the first Fortran compile (TC/flang,
  <pass's zig>, empty zig cache): N s, zig's cache M MB"; a second
  identical call prints the warm time. In the build pass the line says
  "for comparison".
- New, every OS: **RZIG_PRINT_ARGV**:
  - `RZIG_PRINT_ARGV=1 "$fc" -c a.f90 -o a.o`: the first line, `\` → `/`,
    equals `$pass_flang` (`grep -qixF`), and the line after
    `-fintrinsic-modules-path`, `\` → `/`, lies under
    `$tc_phys/flang/lib/clang/23/finclude/flang/`, where `tc_phys` is
    `$(cd "$TC" && pwd -P)` (Windows: `cygpath -m -l`, compared
    case-insensitively), and holds no `..` (Cc3: on omicron a VERIFY_DIR
    under TMPDIR is `/private/var/...` physically, and rzig reports the
    real path);
  - `RZIG_PRINT_ARGV=1 "$fc" -o conftest conftest.f`: the blocks are
    read by skipping any `ZIG_LIB_DIR=` line rather than assuming line 1
    (Cc6; it stands before zig's block on a conda-forge zig whose libc++
    is mirrored, the macOS build pass): a first block whose first word
    is `$pass_flang` and which holds `-c`, a line `&&`, then a second
    block whose first word is `$pass_zig` and which holds
    `TC/flang/lib/clang/23/lib/<rt dir>/libflang_rt.runtime.a`.
  TODO's "RZIG_PRINT_ARGV shows TC/flang/bin/flang compiling and zig
  linking" is ticked on these.
- New, every OS: **a configure that links with `$FC`**:
  - unix (scenario 2, the host's make as today): a package `fcconf`
    whose `configure` runs `FC=$("${R_HOME}/bin/R" CMD config FC)`,
    writes `conftest.f` (`program t / print '(a)', 'ok' / end`), runs
    `$FC -o conftest conftest.f && ./conftest` (must print `ok`) and
    `$FC -v -o conftest conftest.f` (exit 0), then writes
    `src/Makevars`; its `src/f.f90` builds and loads.
  - Windows: scenario 2 runs the same two `$FC` calls directly
    (`zig-fc.exe -o conftest.exe conftest.f`, then `conftest.exe`) under
    `env -i` with bin\x64 + System32; scenario 3 installs `fcconf` with
    a `configure.win` doing the same, with the sh scenario 3 already
    takes from the env's `Library/usr/bin` (phase 7 replaces it).
- The derived-type module through rzig build: a package `fdt` (`src/m.f90`
  with `module m; type :: pt; real(8) :: x, y; end type; contains ...`,
  `src/u.f90` using it, `src/init.c` registering the routine), installed
  with RZIG_TRACE=1 (`rzig build: tier 1` asserted), loaded, the result
  checked. It runs in scenario 2 on unix (make not needed: tier 1) and
  on Windows (tier 1, no make).
- Existing Fortran blocks, unchanged in what they build, now with
  TC/flang: fs.f/FLIBS (1353-1392), USE_FC_TO_LINK `fl` (1395-1432), the
  SHLIB no-make Fortran shapes (960-990), fomp/fompfc's `use omp_lib`
  on two threads (241-284, 1562-1600; slim and full only, B40).
- New, minimal only: **B40's Fortran limit** (Cg1, U): where fomp's
  block is skipped for minimal, `$FC -fopenmp -o ompf ompf.f90` (`use
  omp_lib`, `print *, omp_get_max_threads()`) must fail, and its output
  must name an undefined `omp_` or `__kmpc_` symbol (the compile passed: the module
  is in flang/'s directory; the link has no `-lomp`, the base having no
  libomp). No new rzig message: the link's own error is the record.
  "== B40's Fortran limit: use omp_lib compiles, the link fails without
  libomp (as decided)".
- The Windows dry run at 1152-1164: after step 5, "a shared link goes
  through zig with the static flang runtime" and **no** `-lc++` (if K's
  Windows drop landed; else unchanged).
- The no-flang checks (open point N): pfF (752, 795-797), "zig-fc with
  no flang" (1436-1448) and "`$(FLIBS)` with no Fortran compiler"
  (1450-1470) move `TC/flang/bin/flang$exe` into `$VERIFY_DIR/flang.aside`
  first and back after (the binary only, as phase 5's E (a) moves
  `TC/zig/zig`); the restore runs on the failure paths too (a `trap`
  local to the block, or the restore before each `exit 1`). "zig-fc with
  no flang"'s condition (today: no `/usr/bin/flang`) stays. They run in
  both passes (they pass `zig_env`).
- Header comments (20-105): scenario 2's flang from TC/flang; "What
  phase 5 leaves to later phases" loses its flang sentence; the two
  passes both take TC/flang (O).

### build.zig, R's (step 5, step 7; open point K)

- `installWindowsCompilerContract`: `mk.put("FLIBS",
  "-lflang_rt.runtime")` and its comment (flang-rt-zig 10's archive
  references no C++ runtime symbol, ST §4; kappa's run, step 3); the FC
  comment loses "and libc++" and "flang itself is not copied into
  bin/toolchain". The function's doc (1761-1766): "flang is NOT
  bundled here ... a standalone copy breaks it" becomes: the compilers
  group's flang/ is a copy that works (its resource dir follows the
  binary, and zig-fc passes the modules path), and conda's is the env's.
- `linkFortranRt`: `link_libcpp` gone (if K's macOS and Windows runs
  passed), the doc comment's libc++ paragraph replaced by the
  measurement; the zig-lib-dir comment near 2302 ("R itself links it on
  macOS") follows.
- Linux: no change (no `-lc++`, no `link_libcpp` there).

### recipe/recipe.yaml, recipe/test-compilers.R (step 7; open points P, Q, R)

- `number: 12`, after the "10 → 11" entry:

  ```yaml
  # 11 → 12: the compilers group's flang/ (feat-standalone-toolchain
  # phase 6): zig-fc sends every link through zig and passes the
  # intrinsic modules' path, and the compilers text names flang in the
  # archive (rzig, in r-zig-slim); Makeconf.win's FLIBS and libR (macOS,
  # Windows) no longer link libc++. No flang is packaged: conda keeps
  # flang-zig, lld-zig and flang-rt-zig (r-zig-compilers), and the
  # toolchain build installs no flang/ into the env. The number follows
  # phase 5's 11 (B14 a); if another build publishes first, this takes
  # the one after it.
  number: 12
  ```

  (The sentence on Makeconf.win and libR lists only the drops that
  landed.) The dependency lines (lld-zig `*_5` and the rest) are not
  touched.
- test-compilers.R (r-zig-compilers' test, P): after the inline
  Fortran block, a configure-style probe with the env's flang and its
  cfg: `R CMD config FC` → zig-fc; `<FC> -o conftest conftest.f` and
  `<FC> -o p m.f90 u.f90` (a derived-type module) in a temp directory,
  each program run, `ok` printed; no `rzig-fc-*` left in `tempdir()`'s
  TMPDIR. This is TODO's "a real configure probing `$FC` passes ... in a
  conda env" on the conda channel.

### README.md (step 7)

- The compilers bullet (238-244): zig 0.16, flang 23.1.1 (flang-pixi's
  flang-zig and flang-rt-zig, the compiler R's own Fortran was built
  with) and OpenMP's headers; the archive `R-<ver>-<platform>-compilers.tar.xz`
  (if L landed) and its size; "flang joins it later" goes.
- SOURCES' sentence (251-256): flang/'s files come from flang-pixi's
  packages on prefix.dev's universe channel, not conda-forge.
- The extract example (258-262): `tar -xJf R-4.6.1-linux-64-compilers.tar.xz
  # + .../toolchain/zig/, flang/ and openmp/`; a line for macOS (`tar
  -xf`, which reads xz); and Windows (Cg2, Cc5): first the reader that
  always works once the base is extracted, `Rscript -e "untar('R-4.6.1-win-64-compilers.tar.xz',
  exdir = '.', tar = 'internal')"` run where R was extracted (the
  exact command kappa ran), then System32's `tar -xf`, "where `tar
  --version` lists liblzma" (Windows 11's current builds; Windows 10's
  `tar.exe` has no liblzma, as recalled by Cc5 and recorded on kappa).
- Fortran (Cg4, Cc13): "Run Fortran through zig-fc (`R CMD config
  FC`). The bare `toolchain/flang/bin/flang` needs
  `-fintrinsic-modules-path <toolchain>/flang/lib/clang/23/finclude/flang/<the one directory there>`."
  One sentence on every OS; the per-OS results of the bare-driver
  probe go in PLAN's record only.
- minimal's text (Cg1): "minimal has no OpenMP: `use omp_lib` compiles
  but does not link" (B40's Fortran limit, U).
- The PyPI text (218-222) stays: no Fortran on PyPI.

### .github/workflows/toolchain.yaml, pixi.toml (step 7, comments only)

- toolchain.yaml's header (9-16): the tree holds flang/ too, copied from
  the env's flang-zig and flang-rt-zig (B9 a). The upload comment
  (86-87): the compilers archive's size and format as measured. No step
  changes: `default` already has flang, the upload's
  `dist/R-*-compilers.*` takes `.tar.xz` and its `.sha256`, and
  `timeout-minutes: 30` covers xz's 1-4 minutes (record the step time on
  every runner; it moves only if a measurement says so).
- pixi.toml's archive comments (123-124, 161-162): the compilers
  archive's `.tar.xz`. No table changes.

### scripts/env.sh, scripts/compile-tree.sh comments (step 7)

- env.sh's group comment (72): "zig/ (upstream zig, B4), flang/
  (flang-zig, B9) and openmp/".
- compile-tree.sh (21-23): "zig/ and flang/ stay out (C12): dev compiles
  use the env's zig and flang, with its flang.cfg".

### Files that need no change (checked)

- zigbuild/tools/rzig/check.zig: `--rzig-check=fortran` reports `flang
  at <TC>/flang/bin/flang` through `flang_rt.flang` (SR §3.7); a
  presence check, as decided for zig.
- zigbuild/tools/rzig/pkgplan.zig, pkgbuild.zig, zigbuild/rpkg/build_t1.zig:
  rzig build and R CMD SHLIB reach flang only through zig-fc and FLIBS
  (SR §1.6, §3.8). The shared build runner (PR #27) is keyed by zig's
  path; build roots are per call, so moving flang from the env to TC
  reuses no object (SR §1.6).
- zigbuild/tools/rzig/environment.zig (OpenMP, B40: `omp_lib.mod` is in
  flang/'s modules, found through the flag; a Fortran `-fopenmp` link
  gets `-lomp` as a C one does).
- scripts/compile-tree.sh's code, contract-test.sh (dev compiles keep
  the env's flang and copy it for pak), smoke-test.sh, pkg-parity.sh,
  stress, hermetic-check.sh (first lines only), verify-tree.sh (its
  FLIBS check is a prefix match), make-wheel.py and
  python/r_zig/__init__.py (PyPI's text), recipe/build.sh,
  recipe/test-toolchain.R (its FLIBS grep is a substring), build.yaml,
  build-r.yaml, upstream-zig.yaml, stress.yaml (they download and
  unpack what the toolchain job uploads, through unpack-toolchain.sh).
- Windows' R_SYSTEM_ABI stays `windows,gcc,gxx,flang,flang` (D2 a); unix
  stays `ClassicFlang`.

## 4. Per channel: what changes

| channel | what changes | build number / version |
|---|---|---|
| standalone base (`R-<ver>-<flavor>-<plat>`) | rzig (zig-fc's split and flag, the compilers text); Windows Makeconf FLIBS; libR, Rblas, Rlapack without libc++ on macOS and Windows (where K landed) | — (no release, B12) |
| standalone compilers (`R-<ver>-<plat>-compilers`) | gains `flang/` (144-210 MB raw); `.tar.xz` on every platform if L landed (about 78-95 MB), else `.tar.gz`/`.zip` (131-160 MB) | — |
| standalone build-tools | nothing | — |
| conda r-zig-slim | rzig; Windows Makeconf FLIBS; libR (macOS, Windows) | 11 → 12 (B14 a) |
| conda r-zig-compilers, r-zig-build-tools, r-zig-toolchain | no file and no dependency change; they share the recipe's number and pin r-zig-slim `_12`; r-zig-compilers' test gains the `$FC` probe (P) | 12 |
| PyPI r-zig | rzig (the split and flag apply to a user's own flang: its executable links and configure probes now go through zig too, with `flang_rt.find`'s `.a`-only runtime lookup, a behaviour change recorded as risk 15 (Cg9); the compilers text); libR on macOS | the wheel's version carries no build number; nothing is published (B12) |
| PyPI r-zig-compilers (ziglang), r-zig-build-tools, r-zig-toolchain | nothing; no Fortran (B29 a) | — |

conda depends on flang-zig `==23.1.1 *_6`, lld-zig `*_5` and
flang-rt-zig `*_10` (recipe.yaml:567-569), as before. In a conda env
zig-fc runs the env's flang with its flang.cfg; its modules flag repeats
the cfg's path, and its links through zig no longer use the cfg's
`-fuse-ld=lld`, `--sysroot` and absolute `-Wl,-rpath,<env>/lib` for
executables (they never did for shared links).

## 5. rzig with flang in TC/flang (what changes for it, from SR)

- **Lookup**: unchanged. `TC/flang/bin/flang` first, then R's
  environment's bin, then PATH (B2 a, B34 a). The driver must be the one
  regular file `bin/flang` (its mode as flang comes from the name; its
  resource dir from its place).
- **Compiles** (and `-E`, `-fsyntax-only`, Cc9): flang with the
  caller's arguments, the macOS floor first, the modules path last. The
  path is TC/flang's own; in a conda env the cfg's twin; for a PATH
  flang from another LLVM, its own tree's `finclude/flang/` directory
  for rzig's CPU (Cc8, Cg8), or nothing.
- **Links**: every one is zig's: shared and executable links of objects,
  and calls with sources (a flang compile per Fortran source, then the
  link, which also compiles any C-family source, Cc7). Executables on
  Windows get `.exe` as with gcc. The runtime is the archive of the
  flang that compiled (flang_rt.find), unchanged.
- **The runtime lookup**: `-print-resource-dir` (`TC/flang/lib/clang/23`)
  and the glob, unchanged; on Windows CRLF and `\` are handled.
- **OpenMP** (B40): unchanged; `use omp_lib` finds `omp_lib.mod` through
  the modules path, and a `-fopenmp` link (now also an executable's) gets
  `-lomp` when the base has libomp. On minimal (no libomp) the module is
  still found and the link fails: B40's Fortran limit, decided as U (a)
  (Cg1).
- **rzig build, R CMD SHLIB**: unchanged code; they get the flag and the
  new links through zig-fc.
- **Check mode**: names `TC/flang/bin/flang`.
- **RZIG_PRINT_ARGV / RZIG_TRACE**: a split prints its steps, `&&`
  between them (G).

## 6. Tests per OS and CI

### What each scenario proves (verify-bundle, two passes)

| scenario | toolchain pass (ZIG_BIN unset) | build pass (ZIG_BIN=$ZIG) |
|---|---|---|
| file lists | the compilers archive holds `zig/`, `flang/`, `openmp/` under its own directories, no overlap; read from `.tar.xz` (L) | the same |
| 1. base alone | unchanged, plus: the compilers text names the extracted compilers archive's file (L/M) | skipped (S of phase 5) |
| 2. + compilers | no `.cfg`, no flang on PATH; check mode names TC/zig and TC/flang; the first C++ compile and the first Fortran compile (empty caches) timed; RZIG_PRINT_ARGV: TC/flang compiles (with the modules path, physical, no `..`), zig links (with TC/flang's runtime), a `ZIG_LIB_DIR=` line skipped; `include 'omp_lib.h'` through `$FC -E` (Cc9); the derived-type module (R CMD SHLIB and rzig build); a configure that compiles, links and runs with `$FC` (unix); USE_FC_TO_LINK; FLIBS; `use omp_lib` on two threads (slim, full); the SHLIB Fortran shapes; Windows: the dry runs (no `-lc++`), the direct `$FC` link and run | the same with `$ZIG`; TC/flang too (O) |
| 3. + build-tools | as today; Windows: `fcconf` with configure.win; the no-flang checks with `TC/flang/bin/flang` moved aside (N) | the same |

Default legs: toolchain pass = the mixed case (R by conda-forge's zig,
packages by upstream zig), build pass = conda-forge's zig; flang is
TC/flang in both. Upstream legs: the one-zig pass; build pass skipped.
minimal: every Fortran check but OpenMP (B40), plus the one assertion
of B40's Fortran limit (U, Cg1).

### Per host

| host | runs |
|---|---|
| gamma (linux-64; implementer, owns `dist/`) | steps 1-7 with conda-forge's zig and upstream zig: `rzig-test`, `toolchain-test`, `toolchain`, `verify-toolchain` (timed), `package-toolchain` (sizes, both formats), `build`, `verify-tree`, `smoke`, `contract`, `hermetic`, `pkg-parity`, `verify-package` (both passes on default; the one-zig pass upstream); minimal `build` + `verify-package`; `wheel`, `wheel-test`; `conda-package`, `conda-consume`; step 1's prototype calls (dev env and the hand-made layout, `ZIG_BIN` per zig), the CMake project, the non-flang-zig flang run (Cg9, recorded); step 2's fake-env conda check (Cc4); the bare-driver probe (Cg4); `k-drops.diff` written (Cc14); linux-aarch64's cross pre-check (Cg3, recorded); the carve cross-check |
| omicron, osx-arm64 (tester) | step 2's `toolchain`, `verify-toolchain`, `package-toolchain` (sizes); step 3's prototype (k-drops.diff) and the `link_libcpp` drop (`check`, packages, libR's exported C++ symbols before/after, `___cxa_atexit`); the bare-driver probe, `flang -###` paths (Cg10), `codesign -dv`/`-v`/`spctl` of `TC/flang/bin/flang` (Cc11), the compile-side list re-measured (Cc1); then `rzig-test` (both zigs), `build` → `verify-package` (default: both passes; upstream: one-zig), minimal `build` + `verify-package`, `wheel`, `wheel-test`, `conda-package`, `conda-consume`. Record the first Fortran compile's time |
| omicron, osx-64 under Rosetta (a copy re-solved for osx-64) | `toolchain`, `verify-toolchain`, `package-toolchain`; step 3's Fortran prototype calls; `codesign -dv`/`-v`/`spctl` of the 147 MB `TC/flang/bin/flang` and whether the endpoint agent touches it (Cc11); `verify-package`'s toolchain pass (a kill by the endpoint agent recorded as such, phase 5's K) |
| kappa (win-64, tester) | step 2's tree and sizes; step 3 first: the resource dir without `Library/`, the `-lc++` / `link_libcpp` drop (`build`, `check`, quadprog, minqa, the three packages, `nm` of R.dll, Rblas.dll, Rlapack.dll), System32's `tar.exe --version` and the Windows build, System32's `tar.exe` and R's `untar()` on the `.tar.xz` (timed; `untar()` must pass, Cg2, Cc5); the bare-driver probe, `flang.exe -###` paths (Cg10), the compile-side list re-measured (Cc1), k-drops.diff (Cc14); then `rzig-test`, `toolchain` (time the install), `verify-toolchain`, `package-toolchain` (xz time and size), `unpack-toolchain` (time), `build` → `verify-package` (both passes), upstream one-zig pass, `conda-package`, `conda-consume`. Record the first Fortran compile's time |
| CI, the PR | the core tier (toolchain legs and verify-package on linux-64 and windows-latest); conda-package by its path filter (five legs, four tests and conda-consume each); then `full-ci`: every leg, including linux-aarch64 (its first TC/flang run, T), macos-latest, macos-15-intel (osx-64), minimal and wheel-test; then the `upstream-zig` label (three runners). All of these run only after the user pushes: phase 6 is handed over "pending CI" (Cg3). Record each toolchain leg's time (xz step) and artifact size, unpack-toolchain's time per leg kind, verify-package's per pass against phase 5's times |
| CI, main after merge | the publish of `_12`, after phase 4's, SHLIB's and phase 5's |

Every host records the pixi.lock sha256 (must stay
fbb64b7ba4e31e45...) and `git diff | sha256sum` at start and end.

## 7. Measurements to record (PLAN.md's phase 6 record)

| what | where | per |
|---|---|---|
| compilers archive with flang/: size in today's format (`.tar.gz`, `.zip`) and in `.tar.xz` (`-9 -T0`), member count; `TC/flang` unpacked size and file count | `package-toolchain`'s "== done:" line (the archive's size in bytes, `wc -c`; before the 2026-10-16 fix it printed `du -h`, the space on disk: 512 for gamma's 95,251,492-byte `.tar.xz`), `du` for `TC/flang` unpacked, `archive_files \| wc -l` | linux-64, linux-aarch64 (CI), osx-arm64, osx-64, win-64. ST's figures to compare: gzip/zip 150.8, 144.4, 132.7, 142.1, 160.0 MB; xz 78-95 MB |
| xz's compress time (package-toolchain) and decompress time (unpack-toolchain) | wall time, and the toolchain job's step time | gamma, omicron, kappa, every CI runner |
| the first Fortran compile with TC/flang only: seconds, zig cache MB (empty cache, no build runner), and warm | verify-bundle's new line, toolchain pass; the build pass's for comparison | every host and CI leg |
| verify-toolchain time with flang/ | wall time | gamma, omicron, kappa, CI |
| verify-package time per pass | wall time | gamma, omicron, kappa, CI legs, against phase 5's (PLAN phase 5 record) |
| System32 `tar.exe` and R's `untar()` on the compilers `.tar.xz` | works or not; time; `tar --version` (liblzma or not) and the Windows build (Cc5, Cg2) | kappa |
| the bare driver without the flag (`use iso_c_binding`) | passes or not | gamma, omicron (both subdirs), kappa (Cg4, Cc13) |
| the compile-side list (flags flang refuses) | per entry, refused or not; additions | gamma, omicron, kappa (Cc1) |
| `TC/flang/bin/flang`'s signature | `codesign -dv`, `codesign -v`, `spctl -a -t exec`; the endpoint agent's reaction | omicron, both subdirs (Cc11) |
| `flang -### -c a.f90` from the extracted tree | only paths under it, no `.cfg` | omicron, kappa (Cg10) |
| linux-aarch64's cross pre-check | compile and link pass or not; `file` of the result | gamma (Cg3) |
| a non-flang-zig flang through zig-fc (conda-forge's linux-64 `flang`) | the five calls: pass or not, runtime found or not | gamma (Cg9) |
| libR/Rblas/Rlapack size and exported C++ symbols before and after `link_libcpp` | `ls -l`, `nm -gU \| c++filt` | omicron (osx-arm64), kappa (R.dll exports) |
| the zig link's `-v` line seen by autoconf's FLIBS probe and by CMake | the prototype's logs | gamma (step 1) |
| the carve cross-check | per subdir: files compared, equal | the five subdirs |

## 8. Risks

1. **The split's flag lists** (two, one per direction, both measured;
   Cc1). `linkArgs` drops what zig cc was seen to refuse (PP, linux-64,
   both zigs); `compileArgs` drops the link-only options flang's driver
   refuses (CA: 31 measured, among them macOS's `-dynamiclib`,
   `-undefined`, `-framework` and Windows' `-s`, `-static-libgcc`,
   `-mwindows`). `-Qunused-arguments` silences only flang's
   unused-argument warnings; an option flang does not know is an error,
   so the planner's "the compile half is list-free" did not hold. A
   flag on neither list that one side refuses fails that call with the
   driver's message: visible at once, never silent; each host's step 3
   adds what it finds, with its measurement (E). R's own links are not
   hit (Makeconf's LDFLAGS is empty; SHLIB's links are of objects): a
   package's configure or configure.win is where it shows.
2. **Configure probes that parse `-v`.** autoconf's
   AC_FC_LIBRARY_LDFLAGS and CMake's Fortran implicit-link detection
   now read zig's `ld.lld` line (PP): FLIBS from such a configure may
   name zig's own paths. R packages take FLIBS from Makeconf, so only a
   package's own probe sees it; recorded with step 1's CMake run (PLAN
   risk "zig-fc's split of mixed calls").
3. **libR without libc++ on macOS.** A package whose C link pulls a C++
   static library and relied on `-undefined dynamic_lookup` finding
   libc++ symbols in libR would fail to load. omicron's step 3 reads
   whether libR exports any. K's macOS sub-point (K2, Cg5), decided:
   the drop stays, with `nm -gU libR.dylib | c++filt | grep -c std::`
   before and after recorded, unless a package is seen to fail.
4. **Temporary objects.** A split killed between its steps leaves
   `<TMPDIR>/rzig-fc-*`; hermetic-check's "no temp leftovers" and the
   new unit test cover the normal paths. Its directory is TMPDIR's
   (Windows: TEMP, TMP, else the output's directory, Cc15), so R's
   session cleanup does not remove it.
5. **Windows' resource dir without `Library/`.** docs/19 tested only
   with `Library/`; phase 5's no-make block ran a bare copy (SD), and
   kappa's step 3 checks TC/flang itself. A failure is a B44 item.
6. **`.tar.xz` readers.** Linux needs the `xz` program for `tar -xJf`
   (minimal containers may lack it); macOS's tar reads it; Windows'
   System32 `tar.exe` reads it only where its libarchive was built with
   liblzma (Windows 11's current builds; not Windows 10's, as recalled,
   Cc5), so kappa's one result says nothing about the oldest Windows.
   R's own `untar()` reads xz on every OS (R links liblzma: build.zig's
   `lzma`), and a Windows user who has extracted the base `.zip` has it:
   the README names it first for Windows (Cg2). If kappa's `untar()`
   fails, stop and report: win-64's format is then blocked, not
   silently changed.
7. **xz's cost.** `-9` uses about 674 MB per thread and up to four
   threads on this input (blocks of 3 × 64 MB): about 2.7 GB on CI
   runners (16 GB on ubuntu-latest and windows-latest); 91 s on gamma's
   16 threads, 225 s single-threaded (ST §5). Within toolchain.yaml's
   30 minutes; recorded per runner.
8. **Size of the toolchain artifact.** It grows by flang (about 63 MB
   gzip, 35-40 MB xz) per platform, downloaded by every build-r and
   stress leg though only verify-package reads it (phase 5's Cg6 menu
   covers both directories).
9. **Embedded build paths.** All three OSes' drivers embed flang-pixi's
   build paths (Cg10; CA: linux-64's names
   `/data/gamma/luciorq/workspaces/temp/rb-out/bld/...`, ST §1's "linux
   has none" was wrong). On gamma the path is outside every directory
   verify-toolchain scans for, so nothing is listed; omicron's and
   kappa's verify-toolchain list flang/'s driver and runtime as copies
   naming `$HOME` (`/Users/luciorq/...`, `C:\Users\admin\...`):
   listed, not failed, as for make. Those two hosts are flang-pixi's
   build hosts, so their `flang -###` from the extracted tree is
   recorded to show no `.cfg` or resource dir outside it was used (no
   compiled-in config or resource prefix was found in the three
   drivers' strings, only `/work/` source paths).
10. **`feedstock: unknown`** for both flang packages (H): SOURCES does
    not name flang-pixi until its recipes record their repository.
11. **B44.** If a host run fails for a cause in flang-zig or
    flang-rt-zig, phase 6 does not finish on that OS; the fix needs a
    new flang-pixi build and a re-lock, both the user's (an open item;
    pixi.lock does not change in this run).
12. **linux-aarch64** runs only in CI (`full-ci`): its first TC/flang
    run, and the only check of its cross-built flang-zig with zig-fc's
    links (T). It, native osx-64 and the upstream-zig label run all
    need the user's push, so phase 6 is handed over "pending CI" (Cg3).
    gamma's cross pre-check (x86_64 driver `--target=aarch64`, zig cc's
    aarch64 link) narrows the risk to running the aarch64 driver
    itself.
13. **Stacking**: phase 6's diff sits on three uncommitted baselines that
    edit the same files (open point S's check).
14. **The licence set** (checked, Cc12). flang/'s LICENSES hold the
    LLVM project's Apache-2.0 WITH LLVM-exception text (both packages).
    CP5: every driver (linux-64, osx-arm64, win-64) says LLVM was built
    without zlib and without zstd, so no third-party compression
    library is in it; the linux driver's NEEDED list is glibc only, so
    it carries zig's static libc++/libc++abi (LLVM's own licence, the
    text LICENSES/<pkg>/flang/LICENSE.TXT holds) and zig's compiler_rt
    (MIT, zig's licence, which TC/zig/LICENSES/ziglang holds in the same
    compilers archive). The "Later" licence-completeness menu records
    that a flang/ shipped alone would need zig's MIT text.
15. **A user's own flang** (PyPI's case, Cg9). Shared links of a PATH
    flang already went through zig with its runtime; now executable
    links and configure probes do too. A flang whose runtime is not
    flang-zig's (a distro or Homebrew flang-rt) may need `-lstdc++` or
    `-lc++`, or ship only a `.so`, which `flang_rt.find` (it globs `.a`)
    does not find: its links then miss the runtime. wheel-test has no
    Fortran (B29 a), so step 1's run with conda-forge's `flang` is the
    only record (not a gate).
16. **C-family sources in a Fortran call** (Cc7). They stay on zig's
    line with the caller's flags; a Fortran-only flag clang refuses
    (`-std=f2018`, `-ffixed-form` where clang does not take it) fails
    that call loudly. The caller's flags, as with gfortran's driver,
    which warns; R's own calls never mix them (USE_FC_TO_LINK links
    objects).

## 9. Overlap with other pending work

- **Phases 4, SHLIB and 5** (uncommitted baselines): shared files in
  section 1. If a baseline changes after phase 6 starts, the implementer
  re-reads the changed hunks of verify-bundle.sh, build.zig (toolchain),
  verify-toolchain.sh and groups.zig before step 4.
- **Phase 7** (Windows usr/bin): scenario 3's sh for `fcconf`'s
  configure.win comes from the env until then.
- **zig 0.17 wave** (B18): flang-zig 7 / flang-rt-zig 11 move with it;
  the toolchain build's LLVM-major constant and the pins move together.
- **"Later: zig's global cache"**: the first Fortran compile's time
  joins phase 5's C++ figures.
- **feat-zig-pkg-build** (on hold): no shared file.

## 10. Records (step 8) and the stale references to fix

**PLAN.md: "Phase 6 record"** (new subsections under "### Phase 6"):
- What changed and why: the flang set and its copy (A, B, C), zig-fc's
  split and flag (D, E, F, G), verify-toolchain's flang check (I),
  verify-bundle's Fortran blocks (N, O), the drops that landed (K), the
  format (L), the line (M), the conda probe (P); the answers to section
  11, each recorded as answered with its ★ option ("Phase 6: the user's
  answers").
- The split recommendation (as phase 5's Cg5): B (Windows' second module
  directory) went with the tree survey's and PLAN:161's "keep both";
  the rzig survey recommended one. The reason recorded is B's corrected
  one (a by-product of A (a), no rule; Cg4).
- The modules flag per OS (Cc13): linux's and Windows' drivers find
  their modules under their default triple without it (CP1; SR §3.2's
  "linux finds them only through the symlink" was wrong); macOS's do not
  (CP2); the flag is kept on every OS as one rule; the bare-driver
  probe's per-OS results (Cg4).
- **B40** (Cg1): its entry gains the Fortran limit, decided as U (a):
  `omp_lib.mod` lives in flang/'s one module directory, so on minimal
  `use omp_lib` compiles and the link fails; asserted in minimal's
  verify-bundle; README's minimal text says so.
- The macOS signatures of `TC/flang/bin/flang` (Cc11: CS_ADHOC, not
  linker-signed, valid after the copy; omicron's records) beside phase
  5's zig notes.
- The amendment record: the two critiques' points and their verdicts
  (CRITIQUE.md's table, summarised), the one rejection (Cg7) with its
  reason.
- The measurements (section 7), the host results, CI run IDs, the carve
  cross-check's result.
- **Phase 6's step text** (SD §3): "verify-tree checks against
  `paths_data`" → verify-toolchain (PLAN:5105-5106, TODO:676).
- **Facts** (573-628): the `-lc++` paragraph cites build.zig:1836 and
  :2833 (not 1824 and 2702) and records build 10's check (ST §4, SR §2)
  and the drops; "Still ours for Fortran" gets "done in phase 6".
- **Phase 3's step 3 note** (3091-3093, "flang.exe cannot be copied"):
  corrected by the SHLIB record and phase 6 (a copy works: its resource
  dir follows it, zig-fc passes the modules path).
- **Verification** (5226-5239): "from phase 6 the Fortran checks" lists
  them; "the existing compiles with ZIG_BIN=$ZIG and the env's make and
  flang as a fourth pass" → "... with ZIG_BIN=$ZIG; flang is TC/flang in
  both passes, the env's flang keeps contract, pkg-parity, stress and
  the conda tests" (O). The by-hand block's extract line for the
  compilers archive (`tar -xJf`).
- **Open questions**: "Is passing -fintrinsic-modules-path twice
  harmless ... without Windows' Library/?" and "Is flang-pixi's docs/19
  ... committed now?" (yes: flang-pixi eaa07ba, SD) and "Does
  flang-rt-zig 10's win-64 archive still need no -lc++?" answered.
- **Risks**: "zig-fc's split of mixed calls" gets step 1's and the hosts'
  results; "Fortran on every OS" gets the per-OS outcome.
- **B13's record**: the measured sizes and the choice (L).
- **B17**: the compilers archive's name is `.tar.xz` on every platform
  (if L landed).
- **Later and future checks**: the licence-completeness item gains
  flang/ (the LLVM text present; checked: no zlib or zstd in any driver,
  zig's static libc++ and compiler_rt in it, so a flang/ shipped alone
  would need zig's MIT text, Cc12); "zig's global cache" gains the
  first Fortran compile's times; a new item (Cg5, not acted on): after
  phase 6 nothing of ours links with lld-zig, so r-zig-compilers'
  explicit `lld-zig ==23.1.1 *_5` pin is redundant (flang-zig
  run-depends on lld-zig anyway); dropping it is a dependency change
  for the user to decide.
- The status line: "phase 6 pending CI" until the user's push runs
  linux-aarch64, native osx-64 and the upstream-zig legs (Cg3).

**TODO.md, "## Phase 6"**: tick the boxes; "verify-tree" →
"verify-toolchain"; the `-lc++` box says which drops landed where.

**HANDOFF**: nothing is sent; §1 item 3 (HANDOFF:43, "never copy
flang.exe") and :54 (consumers should not pass the modules path) are
noted in PLAN's record as superseded by §8, the HANDOFF itself
unchanged.

**Other records**: recipe.yaml's history entry; README (section 3).

**Stale references**: fortran.zig's F3c doc; build.zig's "flang is NOT
bundled" (1761-1766, 1822-1827); verify-bundle's "phase 6 puts it in the
compilers group" (612-613) and header (101-105); groups.zig's "phase 6
adds flang, until then on PATH"; README's "flang joins it later";
toolchain.yaml's and pixi.toml's archive comments; carve script's own
"four duplicate runtime archives" comment (flang-pixi's file: recorded,
not edited).

## 11. Open points (answered with the recommended option)

The user's instruction for this run ("Keep going", after "Follow with
the recommended"): every point below is answered with its ★ option, and
PLAN.md's phase 6 record lists each as answered that way, the menu kept
for the record.

**A. How the toolchain build lists the flang set** (ST T6-1).
- (a) ★ The driver as one renamed `Copy`; the modules and the runtime
  as record-driven trees: every regular (`hardlink`) file of
  flang-rt-zig's record under `lib/clang/23/finclude/flang/`, and the
  file named `libflang_rt.runtime.a` under `lib/clang/23/lib/`, each
  installed at its path less `Library/`; each checked by `conda.find`.
- (b) Fixed lists per platform: five triples, five rt dirs and 18 module
  names in build.zig.
- Reason for (a): the set follows the env's packages (B9 a: "the set
  from the env"), on the five packages it gives exactly PLAN:160's
  table, the linux softlink stays out because it is a softlink, and a
  new module or triple needs no edit. (b) ties build.zig to flang-pixi's
  file lists.
- **A2. The LLVM major in the toolchain build** (Cg5: decided in passing
  by the planner, now a lettered sub-point).
  - (a) ★ A constant (`llvm_major = "23"`) beside the flang directory,
    with its comment: the tree copies what the pin says, and a new major
    moves the pin, the constant and SOURCES together; rzig's
    `modulesDir` and R's findFlangRt scan, because they must find
    whatever flang the env or PATH has.
  - (b) The toolchain build scans `lib/clang/*` as rzig does.
  - Reason for (a): one copy rule that reads like the pin; a scan there
    would copy whatever a stray `lib/clang/<v>` holds. The two ways of
    stating one fact are recorded here as decided.

**B. Windows' second module directory** (ST T6-2; SR §3.2 disagreed).
- (a) ★ Keep both (`x86_64-w64-mingw32`, `x86_64-w64-windows-gnu`),
  as PLAN:161 says: A (a) installs them with no rule.
- (b) Only the first: a rule in build.zig, 263 KB saved.
- Reason for (a): a by-product of A (a), with no rule (Cg4), and
  PLAN's table (HANDOFF §8: "keep both Windows directories if you carve
  by hand"). The bare-driver argument the planner gave is dropped: the
  bare driver's behaviour per OS is recorded (step 2, step 3), not a
  reason, since zig-fc's flag is the one rule (C). The rzig survey
  recommended (b) for "no more than needed"; the record says (a) was
  taken for simplicity.

**C. A flang.cfg in TC/flang** (the task's "its config"; PLAN:5104 "no
flang.cfg").
- (a) ★ None. zig-fc passes the modules path (D); the driver needs no
  other cfg line for compiling (HANDOFF §8), and zig links.
- (b) flang-zig's own `bin/flang-compile.cfg` copied as
  `TC/flang/bin/flang.cfg` (a package file, renamed, in SOURCES): the
  bare driver finds its modules on every OS, macOS included.
- Reason for (a): the plan of record and its tests ("no flang.cfg");
  one rule for every flang zig-fc runs (TC's, a conda env's, a PATH
  LLVM's) instead of a file only TC has. Measured (Cc13, CP1/CP2):
  linux's driver (default triple `x86_64-conda-linux-gnu`, shipped) and
  Windows' (`x86_64-w64-windows-gnu`, shipped) find their modules bare;
  macOS's does not. README says one thing on every OS (Cg4): run Fortran
  through zig-fc; the bare driver needs the flag.

**D. The modules path: where it comes from and when** (SD 2.1, 2.2; SR
§3.2).
- (a) ★ From flang's real path, separators turned to `/`, its tree
  the path less `bin/<file>` cut as strings (no `..`; Cc3):
  `<tree>/lib/clang/<v>/finclude/flang/<t>`, `<v>` the first entry in
  byte order holding `finclude/flang/` (Cc8), `<t>` the first entry
  named for rzig's CPU (`x86_64-`, `aarch64-`/`arm64-`), else the first
  in byte order (Cc8, Cg8); on every call that reads Fortran source and
  is no probe (`-c`, `-S`, `-E`, `-fsyntax-only`, the split's compiles;
  Cc9), after the caller's arguments, also beside a conda env's cfg
  (the same directory, PP: harmless); none found: nothing.
- (b) From `flang -print-resource-dir` on every compile.
- (c) A triple constant per platform built into rzig.
- (d) Only when no cfg sits beside flang.
- Reason for (a): no extra process, no constant to keep in step with
  conda's triples or the LLVM major, the same rule everywhere; byte
  order picks the cfg's own directory in every pinned package (SR §2),
  and the CPU preference only matters for a PATH LLVM with several
  targets' modules. (d) is a second rule for a case (a) shows
  harmless.

**E. The link split** (SD 2.3; SR §3.3).
- (a) ★ Every call that links goes to zig. A call with Fortran
  sources: a flang compile per Fortran source (`-c` with the caller's
  arguments less `-o`, the inputs and the measured link-only options
  flang refuses (Cc1: `compileArgs`), plus `-Qunused-arguments` and the
  modules path) into `<tmp>/rzig-fc-<random>/` (Windows' `<tmp>`: TEMP,
  TMP, else the output's directory, Cc15), then the zig link of the
  caller's arguments with each Fortran source replaced by its object
  (a C-family source left on that line, Cc7), less the measured list
  zig cc refuses (`-J <dir>`, `-Mfixed`, `-Mfree`, `-Mextend`,
  `-fno-fortran-main`); spawned and waited on every OS; the first
  failing exit code (128+n for a signal on unix, Cc15); the directory
  removed on every path. Each list grows only by a host's measured
  refusal, recorded with its measurement as this answer covers (Cg5).
- (b) The link gets only a whitelist of link options.
- (c) Executables and mixed calls stay flang's (today).
- Reason for (a): the plan of record (facts 600-603, HANDOFF §8: "your
  plan to send configure probes through zig too is the right one"); the
  link already hands every caller argument to zig for R's shared links,
  so only a short measured list is needed (PP: five of 40 flags); a
  whitelist would drop an unlisted link flag silently. The compile side
  needs its own measured list (Cc1, CA: 31 link-only options flang
  refuses), for the same reason taken as a refusal list, not a
  whitelist: a missed entry fails loudly, a whitelist would drop a
  compile flag (`-fdefault-real-8`) silently. (c) fails every configure
  probe outside conda.

**F. `-x` and non-Fortran sources in a split** (SR §3.3).
- (a) ★ (amended, Cc7) Each input is classified by the `-x` in force
  (`f95`, `f95-cpp-input`, ...: Cc9), else its extension: Fortran →
  a flang compile step; a C-family source is no step, it stays on zig's
  link line, which compiles and links it as zig-cc does (`-x <lang>
  <src> -x none` around it when only an `-x` classified it); no other
  `-x` reaches the link.
- (a0) The planner's: a C-family source by its own zig-cc compile step
  with the caller's (Fortran) flags.
- (b) Calls with `-x` stay flang's.
- Reason for (a): "every link through zig" with no exception, one step
  kind fewer and one test fewer than (a0), and the rule "zig links (and
  compiles) what is not Fortran" is zig-cc's own. Both (a) and (a0) give
  a C source the caller's Fortran flags (risk 16). (b) fails outside
  conda for the calls it keeps.

**G. RZIG_PRINT_ARGV and RZIG_TRACE for a split** (SR §3.3).
- (a) ★ Each step's argv as today, a line `&&` between steps; the
  `ZIG_LIB_DIR=` line, when set, immediately before the first zig
  step's block, never at the top (Cc6); RZIG_TRACE one line per step.
  In a dry run the temporary directory is `<tmp>/rzig-fc-dryrun`, not
  created.
- (b) Print only the link.
- Reason for (a): verify-bundle asserts both halves (TODO: "TC/flang/bin/flang
  compiling and zig linking"); single commands print exactly as before.

**H. `feedstock: unknown` in flang/'s SOURCES** (ST T6-4).
- (a) ★ Accept it: the `source:` line names llvm-project 23.1.1 with its
  sha256, verify-toolchain passes. Recorded as an open item for the user
  (not filed): flang-pixi's recipes could set `extra.remote_url` and
  `extra.sha`, and SOURCES would then name github.com/luciorq/flang-pixi
  and its commit.
- (b) A flang-pixi override in build.zig.
- Reason for (a): the record is true as it stands; (b) writes a fact no
  package states.

**I. verify-toolchain's flang check** (ST T6-3).
- (a) ★ `flang/bin/flang --version`'s version equals SOURCES' flang-zig
  `version:`, and the closures block must have counted
  `flang/bin/flang` (phase 5's Cg8 shape).
- (b) Presence only.
- Reason for (a): the zig check's shape; a wrong or broken copy fails
  here, not in a user's compile.

**J. The carve script's cross-check** (B9 a; ST T6-6; SD 2.7).
- (a) ★ Once, by hand, in `phase6/implementer/carve/`: flang-pixi's
  `scripts/carve-fortran-standalone.py` (eaa07ba) copied there, run with
  `pixi exec --spec "python>=3.14" python carve-fortran-standalone.py
  --out . --archive none <the ten pinned flang-zig and flang-rt-zig
  .conda files>` (the surveyor's files, lock-checked); the sha256 of
  every carved regular file (`Library/` dropped, `bin/flang-23` read as
  `bin/flang`) compared with the `file:` lines of each host's
  `flang/SOURCES` (linux-64 gamma, osx-* omicron, win-64 kappa,
  linux-aarch64 the CI artifact), the extras being exactly the decided
  omissions (symlinks, `flang.cfg`, `STANDALONE-ORIGIN.txt`); recorded.
- (b) A script in the repo (B9 says no).
- Reason for (a): B9's "once, as a cross-check"; nothing in the build
  depends on Python.

**K. `-lc++` and `link_libcpp`** (SD 2.8; ST §4; SR §3.5).
- (a) ★ Drop each where step 3 passed: rzig's Windows `flibs`, Makeconf.win's
  FLIBS (kappa), linkFortranRt's `link_libcpp` on macOS (omicron) and
  Windows (kappa). One that fails stays, recorded with its failure.
- (b) Drop only Windows' `-lc++`; keep `link_libcpp`.
- (c) Keep all three.
- Reason for (a): the runtime archives reference no C++ runtime symbol
  on any OS (build 10, ST §4); PLAN's step says "dropped where those
  runs passed". The drops are prototyped as one recorded patch,
  `phase6/implementer/k-drops.diff` (Cc14), and step 5 lands exactly
  its hunks per passing OS. (Once landed and reworded by steps 5 and 6,
  k-drops.diff is that record only; the patches that take an OS's drop
  back from the tree are `phase6/fix/k-revert-windows.diff` and
  `k-revert-macos.diff`, applied with `patch -p1 -R`.)
- **K2. The macOS libc++ exports** (Cg5: the planner's risk 3 judgement,
  now a sub-point).
  - (a) ★ Drop `link_libcpp` on macOS when omicron's runs pass, with
    `nm -gU libR.dylib | c++filt | grep -c std::` before and after
    recorded; it is restored only if a package is seen to fail.
  - (b) Keep `link_libcpp` on macOS whenever libR exported any libc++
    symbol before the drop.
  - Reason for (a): no package R installs resolves libc++ through libR
    by design (C++ packages link libc++ themselves); (b) keeps a link
    for a hypothetical case at the cost of a libR closure that differs
    from linux's.

**L. Compression** (B13 revisit; ST T6-5).
- (a) ★ (amended, Cg2; Cc5's fallback not taken) If a measured
  compilers archive is over 150 MB: `.tar.xz` for the compilers archive
  on every platform, Windows included with no condition (`tar -cf - |
  xz -9 -T0`; read with `xz -dc | tar`), the base and build-tools
  keeping `.tar.gz`/`.zip`. The rule is per group, never per OS:
  `group_ext` and `archiveExt` hold no platform test. On Windows the
  README names R's `untar(..., tar = "internal")` first (every Windows
  that has the base has it) and System32's `tar -xf` where `tar
  --version` lists liblzma. kappa records `tar --version`, the Windows
  build and both readers' times; if kappa's `untar()` fails, stop and
  report (blocking), not a planned per-OS fallback.
- (a0) The planner's: Windows included only if kappa's System32
  `tar.exe` or R's `untar()` extracts it, else win-64 stays `.zip` and
  goes to the user as an open item. Cc5's variant: decided by the
  oldest supported Windows' `tar.exe`, so `.zip` on Windows when it has
  no liblzma.
- (b) zstd -19 for the compilers archive.
- (c) xz on unix only; Windows keeps `.zip`.
- Reason for (a): the smallest (78-95 MB, 10 % under zstd; every subdir
  under 100 MB), the most common reader (the xz program, macOS's tar,
  Python's lzma, R's untar), one name rule for the group (B17), and xz
  is in the default env on every platform. zstd's faster decompression
  (0.6 s against 5.8 s) does not matter for a one-time extract. (a0)
  and Cc5's variant would put an OS test into `group_ext` and
  `archiveExt` and leave win-64, the largest archive (160 MB), over
  B13's mark, for a case R's own `untar()` already covers (Cg2).

**M. The compilers group's standalone line** (B35; TODO:678-679).
- (a) ★ `extract R-<ver>-<plat>-compilers.tar.xz where you extracted R
  (zig 0.16, flang and the OpenMP files)` (the extension per L); the
  first line and the pip line unchanged.
- (b) Name flang's version too ("flang 23.1.1"): a second version for
  groups.zig to keep in step with the pin.
- Reason for (a): B35's "name the archive for what it holds"; one thing
  to do. wheel-test.sh greps "flang and the OpenMP files".

**N. verify-bundle's no-flang checks** (SR §3.11; SD 2.13).
- (a) ★ Move `TC/flang/bin/flang` (`flang.exe`) aside into VERIFY_DIR
  and back, as phase 5's E (a) moves `TC/zig/zig`; the restore on every
  exit path.
- (b) A directory of its own without flang/.
- Reason for (a): the binary is all `flang_rt.flang` tests; two lines,
  the same question rzig is asked.

**O. The build pass's flang** (Verification: "the env's make and
flang").
- (a) ★ TC/flang in both passes: rzig has no flang override, and
  TC/flang is the env's flang bytes (B9 a); the build pass varies the
  zig only. The env's flang with its cfg keeps its coverage through
  contract, pkg-parity, stress and the conda tests. PLAN's Verification
  wording is corrected.
- (b) The build pass moves TC/flang aside and puts the env's bin on
  PATH.
- Reason for (a): (b) tests the cfg's path, already covered, at the cost
  of a second Fortran setup in the script.

**P. A `$FC` probe on the conda channel** (TODO: "in the standalone tree
and in a conda env").
- (a) ★ recipe/test-compilers.R gains the probe (compile, link and run a
  program; a derived-type module) with the env's flang and cfg.
- (b) Only the dev env's step 1 run.
- Reason for (a): the conda channel's own test, run by conda-package on
  five legs; no package file changes beyond the test.

**Q. lld-zig in r-zig-compilers** (SD 2.12).
- (a) ★ Keep the pin (`lld-zig ==23.1.1 *_5`): flang-zig run-depends on
  lld-zig anyway (HANDOFF:18), and a dependency change is outside this
  run.
- (b) Drop it: zig links everything now. A dependency change: an open
  item for the user.
- Reason for (a): the task's "conda keeps depending on flang-zig", no
  dependency change.

**R. Build number** (B14 a).
- (a) ★ 12: rzig changes (in r-zig-slim and the r-zig wheel), and so do
  Makeconf.win and libR (macOS, Windows) where K landed. If another
  build publishes first, the one after universe's newest.
- Reason: B14 (a) bumps in each PR that changes a conda package's files.

**S. How phase 6's diff is handed over** (stacked).
- (a) ★ `phase6/implementer/phase6-only.diff`: main exported (`git archive
  d11dee1`) into a scratch directory, `phase5-base.diff` applied and
  the baseline's untracked files copied in, then `diff -ruN` against
  the worktree for every path either touches; checked by applying it to
  a second scratch copy and comparing with the worktree. The commands
  for phase 6's commit (after phase 5's) are handed over with no
  trailer.
- (b) The worktree's whole diff for the user to split.
- Reason for (a): four PRs in order, each with its own bump (B14 a);
  read-only git only.

**T. linux-aarch64** (SD §1, "Windows, macOS, linux-aarch64 specifics").
- (a) ★ CI's ubuntu-24.04-arm leg under `full-ci` is linux-aarch64's B44
  run (toolchain, verify-toolchain, verify-package with TC/flang); the
  PR does not merge before it passes.
- (b) A cross-check of the aarch64 tree on gamma only (sizes, records),
  no run.
- Reason for (a): B44 needs it to pass, and CI is the only aarch64 host.
  Added (Cg3): it needs the user's push, so phase 6 is handed over
  "pending CI" (an open item below), and gamma runs a recorded,
  non-gating cross pre-check first (step 3: the x86_64 driver with
  `--target=aarch64-unknown-linux-gnu` and the aarch64 modules, zig cc's
  aarch64 link with the aarch64 runtime; CA: the driver has the AArch64
  backend). It cannot run the aarch64 driver itself, so it does not
  replace (a).

**U. B40's Fortran half** (Cg1: the planner passed the modules flag on
every flavor without listing what it means for minimal).
- (a) ★ Accept and document it as B40's Fortran limit: `omp_lib.mod`,
  `omp_lib_kinds.mod` and `omp_lib.h` stay in flang/'s one module
  directory; on minimal `use omp_lib` compiles and the link fails on
  the `omp_*`/`__kmpc_*` symbols (no `-lomp`: the base has no libomp).
  One minimal verify-bundle assertion records it (the link fails and
  names an undefined `omp_`/`__kmpc_` symbol; no new rzig message); PLAN's
  B40 entry and README's minimal text say so.
- (b) zig-fc leaves the modules flag out on a base without libomp, so
  the bare driver's defaults apply: a second rule, which also hides the
  intrinsic modules on macOS.
- (c) The toolchain build writes a second module directory without the
  OpenMP files: a second copy rule, against "no more than needed".
- Reason for (a): one module directory, one rule; a probe that links
  (as autoconf's OpenMP checks do) concludes "no OpenMP" on minimal,
  which is true. Amended from Cg1's text: the assertion checks the
  linker's own undefined-symbol message rather than a message naming
  the missing runtime, which rzig does not print and would need a new
  rule to.

**V. `ISO_Fortran_binding.h`** (Cg5: a scope choice the planner made in
passing).
- (a) ★ Left out of flang/, the same on every channel (conda's
  `-I<env>/include` does not reach `include/flang/` either); added with
  an include rule if a package needs it.
- (b) Copied into `TC/flang/include/flang/` with rzig adding it to C
  compiles.
- Reason for (a): nothing of R's or of the tested packages uses it, and
  the channels stay alike.

**W. How the toolchain build reads the trees' records** (Cc10).
- (a) ★ One pass, with a separator-free needle per tree: its `name`
  (`libflang_rt.runtime.a"`) when it has one, else the last component
  of its `from` (`flang`): every record listing a file under the tree is
  read, so `conda.find`'s two-owner check sees a clobber, on Windows'
  `\` paths too and whatever rattler's JSON spacing.
- (b) Cc10's: after the first pass, each tree file's basename as a
  needle and a second read.
- (c) The planner's `"name": "<package>"` needle, with build.zig's
  comment saying trees check ownership against their package only.
- Reason for (a): (b) gives the same records with a second pass; (c)
  leaves a second owner unseen and depends on JSON spacing.

**X. The toolchain summary's package order** (Cc17).
- (a) ★ Copy order, as for every directory (`flang/ (flang-zig,
  flang-rt-zig)`): the test expects that.
- (b) build.zig sorts the summary's package names.
- Reason for (a): no code change; the planner's expected line was the
  only thing wrong.

### Open items for the user (none filed, nobody contacted)

- **Phase 6 is pending CI** (Cg3): linux-aarch64 (its only B44 run),
  native osx-64 (macos-15-intel) and the `upstream-zig` label run happen
  only after your push with `full-ci` and the label; the PR does not
  merge before they pass. The hand-over says "pending CI", never "done".
- H: flang-pixi's recipes record no repository (`extra.remote_url`,
  `extra.sha`), so flang/'s SOURCES says `feedstock: unknown`. Cosmetic;
  a flang-pixi change if wanted.
- If kappa's R `untar()` cannot read the compilers `.tar.xz` (not
  expected; Cg2): win-64's format is blocked and reported, with the
  measurement (the planner's "win-64 stays `.zip`" item is gone).
- If a host run fails for a cause in flang-zig or flang-rt-zig (B44):
  the OS, the failure, and that the fix needs a new flang-pixi build and
  a re-lock (pixi.lock is not changed in this run).
- If K leaves a drop out: which, and why.
- Later, not acted on (Cg5): r-zig-compilers' explicit `lld-zig ==23.1.1
  *_5` pin is redundant once zig links everything (flang-zig
  run-depends on lld-zig anyway); dropping it is a dependency change,
  yours to decide.

## 12. Critique points not taken

- **Cg7 (rejected): compare the base's FC_VER / `R_compiled_by()` with
  `TC/flang/bin/flang --version`.** FC_VER is not read from the build
  env's flang: on unix it is a captured string in
  `zigbuild/config/<plat>-<flavor>/{subst.txt,config.h}` (`flang version
  23.1.1`, refreshed by hand under D7), and on Windows build.zig sets a
  fixed text, `"flang (flang-pixi flang-zig, MinGW target)"` (build.zig
  967), with no version. The check would fail on Windows by design and
  on unix compare a hand-kept string. The invariant it wants is already
  enforced where it is decided: every env is in one solve-group (`r`),
  and both `[dependencies]` and `[feature.minimal.dependencies]` pin
  `flang-zig ==23.1.1` build `==6` and `flang-rt-zig` build `==10`
  (pixi.toml 237, 244, 468, 470), so the toolchain env and every
  flavor's env hold the same flang bytes from the one lock; and
  verify-toolchain checks TC/flang against SOURCES' flang-zig version
  (I).
- **Cc5's Windows fallback** (decided otherwise, by Cg2): see L. Its
  recording half (`tar --version`, the Windows build, README naming
  `untar()` first on Windows) is taken.
