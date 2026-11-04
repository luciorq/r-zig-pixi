# Phase 4 implementation plan — conda and PyPI on the same boundary (amended)

The planner's plan of 2026-10-13, amended the same day from the two
critiques beside it: critique-code.md, cited as (Cc<n>), and
critique-goals.md, cited as (Cg<n>). (A<n>) marks the amender's own
checks. Read-only work: nothing in the repo changed, and nothing was
built or installed. CRITIQUE.md beside this file lists every critique
point, whether it held against the code, and what changed. Where an open
point (section 12) is still undecided, the plan is written with its
recommended option and names the point. Format as
phase3plan/critic/PHASE3-IMPLEMENTATION.md.

**Note (2026-10-19).** The user decided that phase 4 does not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 4 keeps 8 (as do SHLIB routing and phases 5 and 6), and
main publishes nothing until the user sets the repository variable
`CONDA_PUBLISH` after phase 7's bump merges (build.yaml's publish step;
PLAN.md's B14 amendment). Where this plan says phase 4 bumps to 9 or
publishes `_9`, read: phase 4 keeps 8, and its files publish with phase
7's bump, at the number after universe's newest (B14 a). Its test
procedures with `_9` hold for that number.

Sources:
- main at ea7e6ee (PR #26 merged), the checkout
  /home/luciorq/projects/r-zig-pixi.
  - Line numbers are ea7e6ee's. When implementing, cite the function,
    not the line.
  - pixi.lock sha256
    fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96, the
    same as fix-zig-pkg-build-review's tested lock.
- feat-standalone-toolchain PLAN.md and TODO.md ("## Phase 4"):
  - the layered model;
  - B11, B14, B18, B28, B29, B33, B34, B35, B38, B39 and B41; D7, D12
    and E2;
  - "Phase 4" and the phase 3 records.
- feat-zig-pkg-build PLAN.md: "Consolidation with phase 3" (M1-M8,
  N1-N7), "What the build-tools group is for" and "The couplings to R's
  tree".
- fix-zig-pkg-build-review PLAN.md: I-T11, I-C1, I-PF4, I-PF5, I-B1;
  "Open decisions" and "Follow-ups".
- The three surveys, cited by section (for example SC §10). Their scratch
  is in surveyor-{conda,pypi,rzig}/.
  - survey-conda.md (SC)
  - survey-pypi.md (SP)
  - survey-rzig.md (SR)
- The two critiques: critique-code.md and critique-goals.md.
- R 4.6.1's sources in the checkout's build/R-4.6.1:
  - install.R: makevars_user at 3380-3405;
  - src/unix/sys-unix.c: intern's 127 at 1012;
  - share/make/shlib.mk;
  - src/scripts/config.
- CI:
  - build-r run 38467545177, ea7e6ee on main: completed, success on all
    18 jobs (read 2026-10-13) (A2).
  - PR #26's runs: 38430368575 (build-r, full tier) and 38430385664
    (upstream-zig).
  - Stress dispatch 38467907779 on ea7e6ee (A1).
    - It is the `--no-shared-cache` run that TODO.md asks for: report.json
      gives `args: --out=build/stress/run --trace --no-shared-cache g3 g4`
      and `shared_cache: false`. It is not a shared-cache run.
    - Four of its five tree legs had finished when read (21:24 UTC). The
      macos-15-intel leg was still running.
    - Its reports were downloaded to critic/stress/.
- Network reads, 2026-10-13:
  - universe's repodata (planner/repodata-linux-64.json): r-zig-slim
    `_2`..`_8`, r-zig-toolchain `_4`..`_8`, no `_9`.
  - conda-forge's zig: 0.17.0 on the main label (api.anaconda.org)
    (Cg14).
  - PyPI: r-zig, r-zig-compilers, r-zig-build-tools and r-zig-toolchain
    all return 404 (Cc14).
  - m2-bash 5.2.037.2 hc364b38_6 (the lock's build) ships
    `Library/usr/bin/sh.exe` (critic/m2/) (Cc16).

Decision IDs are PLAN.md's (B1-B44, C-, D-, E-, N-, T1). I-* are
fix-zig-pkg-build-review's interfaces. This plan's open points are letters
(section 12).

## 0. What phase 4 delivers

- **rzig ships in the base on conda and PyPI**, as it already does in the
  standalone base archive (B19).
  - r-zig-slim and the r-zig wheel carry `R_HOME/bin/toolchain`'s rzig
    names (build.zig:2601-2602):
    - unix: `zig-cc zig-cxx zig-fc zig-ar zig-ranlib rzig`;
    - Windows: `gcc.exe g++.exe zig-fc.exe zig-ar.exe zig-ranlib.exe
      gcc-ar.exe gcc-ranlib.exe ar.exe ranlib.exe rzig.exe`.
  - They sit beside `R_HOME/share/zig/rpkg`, which these packages already
    carry (build.zig:2606-2612; SR §7).
  - So on every channel, patches 0009, 0012 and 0013, the rpkg roots and
    the rzig they call ship in one package. That ends N5's coupling
    (section 1).
- **conda: four packages** (B28 a; one recipe, one build number):
  - r-zig-slim: the base. It gets `run_constraints: zig 0.16.*` (open
    point K) (Cc13, Cg14).
  - r-zig-compilers: no payload. It depends on zig 0.16, flang-pixi's
    flang and llvm-openmp.
  - r-zig-build-tools:
    - unix: no payload; it depends on make;
    - win-64: the MinGW binutils copies in `TC/binutils/`, plus today's
      MSYS2 set, pkg-config and zstd. There is no native make on win-64
      (Cg7). (B41; B39/B11 interim.)
  - r-zig-toolchain: the metapackage of both groups, so
    `pixi add r-zig-toolchain` keeps working.
- **PyPI: four wheels** (B29 a), one tag set, Linux and macOS only.
  Windows comes after phase 7 (C1-C3).
  - r-zig: the base, rzig included.
  - r-zig-compilers: no files; it requires ziglang.
  - r-zig-build-tools: `TC/usr/bin/make` with its SOURCES and LICENSES.
  - r-zig-toolchain: no files; it requires both groups.
- **rzig's texts** (B35, B38):
  - The conda and pip lines name the per-group packages, and r-zig-toolchain,
    which installs every group (open point H) (Cg1).
  - The pip compilers line says that PyPI has no Fortran compiler (Cg3).
  - A package that needs both groups gets both texts in one stop (H)
    (Cg1).
  - Build tools that are installed in R's environment but not on PATH
    are named as such (open point I) (Cg2).
- **The hint writers go:** `-Dtoolchain-hint`, zig-build.sh's conda
  branch and make-wheel.py's renviron_hint. So do the rzig-missing
  branches of 0009 and 0010 (C8).
  - `R_ZIG_TOOLCHAIN_HINT` stays only as a user's own value.
  - 0009 shows it after a 127, and 0010 does not (open point B) (Cg4).
  - 0009 tells the check's exit 1 from 127 (open point J) (Cg5).
- zstd is declared on every OS (E2, widened by SC §9: macOS links it too).
  This widening is recorded (Cg18).
- CC_VER/FC_VER are refreshed (D7), and the build number goes 8 → 9
  (B14 a).
- **Tests:**
  - A recipe test per package, each group alone in rattler-build's
    fresh test env. Every one narrows PATH to the env, test-toolchain.R
    included (section 8) (Cg9).
  - A `package_contents` check per output (Cc12, Cg12).
  - One consume task, `pixi run -e pkg conda-consume`. CI runs it on
    every conda-package leg and each host runs it too (Cg8).
  - wheel-test runs the base-alone recipe test with pip (Cg10), the other
    scenarios and the uninstall.
  - The upgrade from universe's `_8` is tested with pixi, conda and
    micromamba before merging (section 7).

Not in phase 4:
- zig in `TC/zig/` (phase 5).
- flang in `TC/flang/` (phase 6).
- Windows `usr/bin` and the final win-64 package set (phase 7). Phase 7
  replaces phase 4's interim m2 list.
- The base's runtime records (phase 8).
- Publishing wheels (B12: CI artifacts only). feat-wheel-minimal's
  licence texts and trusted publishing are still open, and so is
  reserving the four names on PyPI (Cc14).
- feat-zig-pkg-build's later items: `R CMD SHLIB` through rzig build,
  and the shared tier-1 runner (open point D) (section 10).

What changed since the decisions were taken, and what it means here:
- **feat-zig-pkg-build (PR #25, #26).**
  - The compilers group alone now installs tier 0-2 packages that have
    no configure script for R to run. This is patch 0013's `rzig build`.
    The preflight asks for the build tools only when the package needs
    make (check.zig:271-283; feat-zig-pkg-build N2).
  - B28 and B29 did not depend on this. It makes "r-zig-slim +
    r-zig-compilers" and "r-zig + r-zig-compilers" real configurations,
    so they get tests (sections 8 and 5), and the README says what each
    group is for.
  - pak, pkgbuild's compiler probe and run-time compilation
    (`R CMD SHLIB`) still need the build tools, and give no rzig text
    (SR §12). The README and rzig's texts recommend r-zig-toolchain
    (Cg1, Cg16).
- **0013's no-rzig branches** (0013:63-81) are new since C8, which
  covers only 0009 and 0010: open point C.
- **N5.** universe's `_8` predates phase 3 and PR #25/#26 (SC §4, SR §8),
  so phase 4's `_9` publishes phase 3, PR #25 and PR #26 with it.
- **D12 is already on main** (3510530: pixi.toml:523, 552; SC §0.1).
- **rattler-build's test env keeps the caller's environment** (SC §3: PATH
  and variables, seen on win-64; activation.rs prepends on every OS).
  - Under `pixi run -e pkg`, that PATH has the pkg env's zig 0.16, flang
    and make (pkg includes the default feature, pixi.toml:691).
  - So every recipe test narrows PATH to its own env, and resets the
    caller's variables that change what it tests (section 3) (Cc4).
- **conda-forge's zig 0.17.0 reached its main label** (2026-10-13), which
  is B18's trigger (Cg14).
  - Phase 4 stays on 0.16 per B18, because build.zig does not compile on
    0.17 yet. A 0.17 bump (`_10` or later) follows the wave.
  - The PR text says so.
  - Until then, a user who adds an unpinned `zig` beside r-zig-slim gets
    0.17, unless r-zig-slim constrains it (open point K).

## 1. Sequencing and preconditions

- **Start from main.** ea7e6ee's CI is green: build-r run 38467545177 is
  completed with success on all 18 jobs (A2). Make the worktree
  `feat-standalone-phase4` from main.
- **universe holds `_8` and nothing newer** on all five subdirs for both
  names.
  - Check with `pixi run -e pkg conda-channel-list universe <subdir>`
    (read here for linux-64).
  - Phase 4's number is the next one, 9 (B14 a, C14), unless another PR
    bumps first. Check again just before merging. (2026-10-19: no
    number; phase 4 keeps 8, the note at the top.)
- **N5.**
  - r-zig-slim `_8` has no rzig and no share/zig/rpkg. r-zig-toolchain
    `_8` has rzig ×5 without the `rzig` name, and the phase-2 win-64
    layout (SC §10, SR §8).
  - A new r-zig-slim with that toolchain stops every compiled install:
    the old rzig answers `--rzig-check=package` with exit 2, and 0013
    stops on CC's binary without `rzig`.
  - The bump publishes all four packages from one build, and the exact
    pins make a mix unsolvable. r-zig-toolchain `_8` pins
    `r-zig-slim ==4.6.1 <hash>_8` (SC §4), and every `_9` package pins
    r-zig-slim `_9` (section 4).
  - The upgrade test (section 7) uses fresh package caches
    (`PIXI_CACHE_DIR`, `CONDA_PKGS_DIRS`, `MAMBA_ROOT_PREFIX`).
  - The consume task and the recipe tests rely on conda-package emptying
    dist/conda instead (Cg8). The trap pixi.toml:538-548 records was a
    stale dist/conda index that kept an old sha256. An emptied
    dist/conda gives a rebuilt `_9` a new sha256, which a cached `_9`
    does not match.
- **The stress dispatch 38467907779** is the `--no-shared-cache` run
  (A1). TODO.md ("Depend less on make"; I-B1) needs it to decide whether
  a shared tier-1 build runner is wanted.
  - Its four finished legs are summarized under open point D (Cg6).
  - Read the fifth leg (macos-15-intel) before step 1.
  - If the user wants a runner, that is rzig and rpkg work, independent
    of the package boundary. Open point D recommends its own PR after
    phase 4, with its own bump.
- **publish-preflight** on gamma, omicron and kappa before the long
  conda chains (disk, `pixi lock --check`, no gitignored inputs). No
  host uploads anything: CI publishes from main with OIDC.
- **Every host records two hashes** at the start and the end of its
  runs:
  - the pixi.lock sha256, which must not change (phase 4 changes no
    dependency of any pixi env);
  - the worktree's `git diff | sha256sum`.
  One owner per host; the remote hosts do not write the lock.

## 2. Steps

Each step is a local checkpoint that leaves every named test green. CI
sees only the PR's final state. The order keeps a channel without rzig
from ever meeting a patch that has no rzig-missing branch: conda gets
rzig in step 1, PyPI in step 2, and the branches go in step 3.

1. **conda: four packages** (B28, B41, B39/B11 interim, E2, B14).
   - Changes:
     - recipe.yaml (section 3): r-zig-slim keeps rzig;
       r-zig-compilers; r-zig-build-tools (unix-only make, Cg7);
       r-zig-toolchain as a metapackage; zstd; `package_contents` per
       output (Cc12); r-zig-slim's zig constraint (K); number 9.
     - build.sh's comment.
     - test-preflight.R rewritten. test-compilers.R and
       test-build-tools.R are new. test-toolchain.R gets the narrowed
       PATH (Cg9). All four start with the same header (section 3)
       (Cc4).
     - groups.zig's **conda line** and its tests.
     - scripts/conda-consume.sh and its pkg task. conda-package's
       shared zig cache for the tests (Cc11, Cg8).
   - First action: build, and read rattler-build's file list for each
     package.
     - The metapackages and unix r-zig-build-tools hold only
       `etc/conda/test-files/<name>/0/...`.
     - SC §3: `files: []`, and a conditional list with no matching
       branch, package nothing since 0.76.0. pixi.toml:523 floors
       rattler-build at that version.
     - The `package_contents` tests then keep this check on every
       build.
   - Tests:
     - `rzig-test`, with both zigs.
     - `build`, `verify-tree`, `hermetic`, and `verify-package` (rzig
       changed: groups.zig).
     - `wheel` and `wheel-test`: the split is unchanged, and so are the
       pip lines.
     - `pixi run -e pkg conda-package`: four tests, both `--error-*`
       flags, no overlap.
     - `pixi run -e pkg conda-consume` (Cg8).
     - On gamma only: `pixi run verify-tree -- <env>` on an r-zig-slim
       alone env made by hand from `$CH` (section 7's pixi lines, with
       `$CH` first). The rzig-names check now passes there (SR §10).
       conda-consume.sh removes its own workspace on exit, so it does not
       serve here.
2. **PyPI: four wheels** (B29, B35's wheel writer).
   - Changes:
     - make-wheel.py: rzig in r-zig, usr/ in r-zig-build-tools, two
       empty wheels, no renviron_hint, and the licences (E).
     - groups.zig's **pip lines** and their tests.
     - python/r_zig/__init__.py's docstring.
     - wheel-test.sh's scenarios (section 3), with test-preflight.R run
       for r-zig alone (Cg10).
   - make-wheel.py and wheel-test.sh together are over 200 changed
     lines. Before the tests, do a skeptical diff review: dropped names,
     quoting, PATH, the globs, and `--no-index` (Cc14).
   - Tests: `rzig-test`; `pixi run -e minimal build` and
     `-e minimal toolchain`; `-e wheel wheel` and `-e wheel wheel-test`;
     the default chain's `verify-package` (rzig's text changed).
3. **The hint writers, the rzig-missing branches and the stop texts**
   (B35, C8; open points B, C, H, I, J).
   - Changes:
     - build.zig's `-Dtoolchain-hint` and its two writers; zig-build.sh's
       conda branch; recipe.yaml's `R_ZIG_CONDA_BUILD`.
     - 0009 (127 vs other statuses; the hint on 127 only), 0010 and
       0013. Regenerate 0013 after 0009, as fix-zig-pkg-build-review
       did: the series applies to the pristine tarball with no offset or
       fuzz.
     - check.zig: H's both-groups stop and I's "installed but not on
       PATH" line, with unit tests (Cg1, Cg2).
     - groups.zig's header; fortran.zig's test comment.
     - stress.R's classifier and stress/README.md (J, Cc19).
     - test-preflight.R: the hint and configure-script checks.
       test-build-tools.R: I's check.
   - Changing the patches re-extracts R's source (zig-build.sh's stamp),
     so this step is a full rebuild.
   - Tests:
     - `rzig-test`, with both zigs.
     - default: `build`, `toolchain`, `verify-tree`, `smoke`,
       `compile-tree`, `contract`, `hermetic`, `pkg-parity`,
       `package-toolchain`, `verify-package`.
     - minimal: `build`, `verify-tree`, `contract`, `verify-package`,
       `wheel`, `wheel-test`.
     - `conda-package`, then `conda-consume`.
     - `git grep -nE 'toolchain[-_]hint|R_ZIG_CONDA_BUILD|renviron_hint|TOOLCHAIN_HINT' -- ':!.github/devdocs'`
       finds only:
       - the reader (0009);
       - test-preflight.R;
       - the comments that say rzig does not read it (groups.zig,
         fortran.zig, verify-bundle.sh:962).
4. **D7, docs and CI.**
   - Changes: CC_VER/FC_VER (section 3, zigbuild/config); README;
     pixi.toml's comments; verify-tree.sh's comments; build.yaml's
     consume step (one line: the task).
   - Tests:
     - `build`, then `Rscript -e 'R_compiled_by()'`. On linux-64 it must
       print the clangdev 334cf9a5 string.
     - actionlint.
     - `conda-package`, then `conda-consume`.
5. **Other hosts, the upgrade test, the records.**
   - omicron and kappa (section 8).
   - The upgrade from `_8` (section 7).
   - PLAN.md's phase 4 record and TODO.md (section 11).
   - Hand the commit commands to the user, with no trailer and no
     session link.

## 3. Per file: the exact change

### The recipe tests' shared header (step 1) (Cc4, Cc2, Cc3, Cc11, A3)

test-preflight.R, test-compilers.R, test-build-tools.R and
test-toolchain.R start the same way. rattler-build's test env inherits the
caller's environment (SC §3), and each line below removes one way it
could change what the test checks:

```r
windows <- .Platform$OS.type == "windows"
d <- tempfile("rzig-"); dir.create(d)
## the caller's settings, which rattler-build's test env inherits (SC §3):
## R_ZIG_EXTRA_ENV (pixi.toml) adds an environment; ZIG_BIN a zig;
## R_ZIG_NO_PREFLIGHT skips 0009; R_ZIG_PKG_BUILDER=make sends tier 1 to
## make; RZIG_TRACE changes the logs; a MAKEFLAGS assignment makes rzig
## build decline (0013); ZIG_LOCAL_CACHE_DIR defeats N3's per-install
## cache; R_ZIG_TOOLCHAIN_HINT adds a line
Sys.unsetenv(c("R_ZIG_EXTRA_ENV", "ZIG_BIN", "R_ZIG_TOOLCHAIN_HINT", "R_ZIG_NO_PREFLIGHT",
               "R_ZIG_PKG_BUILDER", "RZIG_TRACE", "MAKEFLAGS", "ZIG_LOCAL_CACHE_DIR"))
## a user Makevars switches the preflight off. Unset, R_MAKEVARS_USER lets
## R (install.R's makevars_user) and rzig (pkgbuild.zig) fall back to
## ~/.R/Makevars*; naming a file that does not exist means "none" to both
Sys.setenv(R_MAKEVARS_USER = file.path(d, "no-Makevars"))
## zig's cache: shared between the recipe tests when conda-package asks
## (R_ZIG_TEST_ZIG_CACHE), else this test's own; rzig's cache in d
Sys.setenv(ZIG_GLOBAL_CACHE_DIR = Sys.getenv("R_ZIG_TEST_ZIG_CACHE", file.path(d, "zig-cache")),
           XDG_CACHE_HOME = file.path(d, "cache"))
## only this env's programs (Windows: also R's bin\x64 and System32, and
## with usr_bin m2's Library\usr\bin); env_bin is <prefix>/bin, on
## Windows <prefix>/Library/bin
env_bin <- normalizePath(file.path(R.home(), "..", "..", "bin"))
narrow <- function(usr_bin = FALSE)
    Sys.setenv(PATH = paste(c(if (windows && usr_bin) normalizePath(file.path(env_bin, "..", "usr", "bin")),
                              env_bin,
                              if (windows) c(R.home("bin"), file.path(Sys.getenv("SystemRoot"), "System32"))),
                            collapse = .Platform$path.sep))
## how rzig shows a path (check.zig's display(): `/` only on Windows), and
## a comparison that ignores the drive letter's case there
shown <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
same_path <- function(a, b) if (windows) tolower(a) == tolower(b) else a == b
## a command's status and output through a file: a 127 through
## system2(stdout = TRUE) is R's own error (sys-unix.c), not a status
run_to <- function(cmd, args) {
    f <- tempfile(tmpdir = d); st <- system2(cmd, args, stdout = f, stderr = f)
    list(status = st, out = readLines(f, warn = FALSE))
}
```

- **Which PATH each test uses.**
  - test-preflight.R and test-compilers.R call `narrow()`. On Windows
    they need no sh and no make, and leaving m2's `Library\usr\bin` out
    keeps the boundary.
  - test-build-tools.R and test-toolchain.R call `narrow(usr_bin = TRUE)`.
  - test-toolchain.R narrows PATH for every install (Cg9). It resolves
    `otool` and `readelf` with `Sys.which()` before narrowing, and calls
    them by that path.
  - Windows takes PATH in its own backslash form. `shown()` is only for
    comparisons (Cc3).
- **The 127 rule.** Any check that expects 127 goes through `run_to()`,
  never `stdout = TRUE` (Cc2). This covers `--rzig-check` and
  `R CMD config` in all four tests.
- **The cache variable.** `R_ZIG_TEST_ZIG_CACHE` is set only by
  conda-package and conda-consume.sh (below). A test run by hand keeps
  its own cache, as test-toolchain.R:17-19 does today (Cc11).
  test-toolchain.R keeps its `ZIG_LOCAL_CACHE_DIR` in `d`. test-compilers.R
  does not set it, so its installs use N3's per-install cache, as a
  user's do.

### recipe/recipe.yaml (steps 1, 3)

- **Build number:** `number: 8` (151) → `number: 9`, with a history entry
  after 144-150 (2026-10-19: not done; the number stays 8 with a one-line
  "8 stays" entry, the note at the top):

  > 8 → 9: feat-standalone-toolchain phase 4. rzig moves into r-zig-slim
  > (R_HOME/bin/toolchain's compiler names and `rzig`, beside
  > share/zig/rpkg). The toolchain splits into r-zig-compilers (zig,
  > flang) and r-zig-build-tools (make; win-64 also the MSYS2 tools,
  > pkg-config and the MinGW binutils). r-zig-toolchain is the
  > metapackage of both (B28). It publishes phase 3 and
  > feat-zig-pkg-build (rzig build, patches 0012 and 0013) with it (N5).
  > zstd is declared on every OS (E2), CC_VER is refreshed (D7), and the
  > compile preflight's hint is gone (B35).
- **outputs comment (153-160):**
  - four packages from one build;
  - the base owns rzig;
  - each group package owns, or depends on, third-party software only;
  - without a group, an install that needs it stops with rzig's text
    naming that package.
- **staging host (298-303):** `zstd` leaves the `if: linux` block for the
  unconditional list (E2; SC §9: win-64's R.dll and osx-arm64's
  libR.dylib link it too). libiconv, libstdcxx and libgcc stay
  linux-only.
- **staging script env (326):** delete `R_ZIG_CONDA_BUILD: "1"` in step
  3. Its only reader is zig-build.sh:63 (SR §3).
- **r-zig-slim (328-452):**
  - files.exclude (332-335) →
    `lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` and
    `Library/lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**`
    (B28; globset's `{a,b}` is valid, SC §3). Only win-64's `binutils/`
    exists in this build (zigbuild/toolchain/build.zig:36-40, 85-86).
  - run: `zstd` becomes unconditional (it moves out of 363-368).
  - run_constraints (open point K) (Cc13, Cg14):

    ```yaml
      run_constraints:
        # the zig that built R and rzig: rzig finds the env's zig first
        # (B34), and B32's check stops a compile with another
        # major.minor; conda-forge's main label has 0.17.0 since
        # 2026-10-13. Constrains an installed zig, pulls none in; bumped
        # with r-zig-compilers' pins in the zig 0.17 wave (B18)
        - zig 0.16.*
    ```

  - tests:
    - The script commands (433-438) are unchanged. test-preflight.R's
      content changes (below).
    - Add the `package_contents` check below (Cc12, Cg12).

    ```yaml
      - package_contents:
          files:
            exists:
              - if: win
                then:
                  - Library/lib/R/bin/toolchain/rzig.exe
                  - Library/lib/R/bin/toolchain/gcc.exe
                  - Library/lib/R/share/zig/rpkg/build_t1.zig
                else:
                  - lib/R/bin/toolchain/rzig
                  - lib/R/bin/toolchain/zig-cc
                  - lib/R/share/zig/rpkg/build_t1.zig
            not_exists:
              - lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**
              - Library/lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**
    ```

  - about:
    - summary: "R built with the zig toolchain, with its compiler front
      rzig (headless slim profile; Windows slim has full's content)".
    - The description adds the one recommendation used everywhere
      (Cg16): "To compile packages, add r-zig-toolchain (r-zig-compilers
      and r-zig-build-tools). r-zig-compilers alone installs packages
      that have no configure script and no make rules."
    - license: open point E (Cc15, Cg13).
- **r-zig-compilers** (new, after r-zig-slim):

  ```yaml
  - package:
      name: r-zig-compilers
    # no files: zig, flang and llvm-openmp come from their packages (B28);
    # without the staging host's run exports, which are R's
    inherit:
      from: r-zig-build
      run_exports: false
    build:
      files: []
    requirements:
      run:
        - ${{ pin_subpackage("r-zig-slim", exact=True) }}
        # the zig that built R and rzig: B32's check fails on another
        # major.minor (r-zig-slim also constrains it, open point K)
        - zig 0.16.*
        - flang-zig ==23.1.1 *_6
        - lld-zig ==23.1.1 *_5
        - flang-rt-zig ==23.1.1 *_10
        # r-zig-slim already has it (B41's exception); named as B28 says
        - llvm-openmp
    tests:
      - package_contents:
          files:
            not_exists: [lib/R/**, Library/lib/R/**]
      - script:
          content:
            - if: win
              then:
                - '%PREFIX%/Library/lib/R/bin/x64/Rscript.exe test-compilers.R'
              else:
                - $PREFIX/bin/Rscript test-compilers.R
        files:
          recipe:
            - test-compilers.R
    about:
      summary: The r-zig compilers for r-zig-slim (zig 0.16, LLVM flang from flang-pixi, OpenMP)
  ```

  - The comment block of 503-513 moves here: why flang-zig, the
    ~1.5 GiB closure, and the pins.
  - Why `inherit` + `files: []`, and not an output without `inherit`:
    - Both make an empty package (SC §3).
    - Only the first is covered by rattler-build's regression test with
      both `--error-*` flags (test_staging.py:443-454).
    - The second may fetch the top-level sources again (SC §12 A,
      unknown).
    - The cost is a ~1 s cache restore.
  - Why the `package_contents` checks are not `strict`: whether the
    packaged test file counts in the checked list is unverified (Cc12).
    The `not_exists` form holds either way.
- **r-zig-build-tools** (new):

  ```yaml
  - package:
      name: r-zig-build-tools
    inherit:
      from: r-zig-build
      run_exports: false
    build:
      # win-64: conda-forge's MinGW binutils, copied by the toolchain build
      # with SOURCES and LICENSES/ (B24, B41; Makeconf.win names them by
      # path under R_HOME). unix: nothing (no branch matches: an empty
      # package, rattler-build >= 0.76)
      files:
        - if: win
          then:
            - Library/lib/R/bin/toolchain/binutils/**
    requirements:
      run:
        - ${{ pin_subpackage("r-zig-slim", exact=True) }}
        # B28 (a): unix make; on win-64 m2-make is the make R runs (it
        # comes first on PATH, SC §5), so no native make there (Cg7)
        - if: unix
          then:
            - make >=4.4
        - if: win
          then:
            - m2-bash        # today's eight (470-502), with their comments,
            - m2-sed         # until phase 7 chooses the set for both
            - m2-grep        # channels (B11, B39)
            - m2-gawk
            - m2-coreutils
            - m2-make
            - m2-which
            - m2-findutils
            - pkg-config     # B43: Makeconf.win names a bare pkg-config
            - zstd           # E2: the six binutils import zstd.dll
    tests:
      - package_contents:
          files:
            exists:
              - if: win
                then:
                  # one entry per tool: an `exists` glob passes when it
                  # matches one file, so a {a,b} list would not catch a
                  # missing tool
                  - Library/lib/R/bin/toolchain/binutils/nm.exe
                  - Library/lib/R/bin/toolchain/binutils/dlltool.exe
                  - Library/lib/R/bin/toolchain/binutils/as.exe
                  - Library/lib/R/bin/toolchain/binutils/strip.exe
                  - Library/lib/R/bin/toolchain/binutils/windres.exe
                  - Library/lib/R/bin/toolchain/binutils/objdump.exe
                  - Library/lib/R/bin/toolchain/binutils/SOURCES
                  - Library/lib/R/bin/toolchain/binutils/LICENSES/binutils_impl_win-64/**
            not_exists:
              - lib/R/**
              - Library/lib/R/bin/toolchain/{gcc,rzig}.exe
              - Library/lib/R/etc/**
      - script: test-build-tools.R, in the same form as r-zig-compilers'
    about:
      summary: The r-zig build tools for r-zig-slim (make; on Windows also sh, the MSYS2 tools, pkg-config and the MinGW binutils)
      # license: open point E (Cc15)
  ```

  - `pkgconf`, the second name B39's note gives `usr/bin`: open point F.
  - **The native make on win-64.** Today's r-zig-toolchain lists `make`
    for every OS only because its run list was shared. B28 (a) lists it
    for unix. The phase 4 record says it was dropped on win-64, and that
    phase 7 chooses native or m2 per B11 (Cg7).
  - **sh.exe.** m2-bash ships `Library/usr/bin/sh.exe` (checked here on
    the lock's build). test-build-tools.R's `--rzig-check=build-tools`
    checks it on every build (Cc16).
- **r-zig-toolchain (455-531):**
  - `inherit` stays as today (459-461).
  - files (463-465) → `files: []`.
  - run (466-518) → only:

    ```yaml
          - ${{ pin_subpackage("r-zig-slim", exact=True) }}
          - ${{ pin_subpackage("r-zig-compilers", exact=True) }}
          - ${{ pin_subpackage("r-zig-build-tools", exact=True) }}
    ```

  - tests: test-toolchain.R as today (519-529), plus `package_contents`
    with `not_exists: [lib/R/**, Library/lib/R/**]`.
  - about: "The r-zig toolchain for r-zig-slim: r-zig-compilers and
    r-zig-build-tools".
  - Every package stays arch-specific: an exact pin's hash differs per
    subdir (SC §5).
- **top-level about (533-536):** open point E. Today every output
  inherits `GPL-2.0-or-later` (Cc15, Cg13).
  - With E (a), r-zig-slim, r-zig-compilers and r-zig-toolchain say R's
    own `GPL-2.0-only OR GPL-3.0-only`.
  - win-64 r-zig-build-tools says binutils' `GPL-3.0-or-later`, through
    an output-level `about.license` with a `${{ ... if win else ... }}`
    expression.
  - There is no `license_file` today (SC §1.1). License files are phase
    8's (B33).

### recipe/build.sh (step 1)

- Comment 39-46: "r-zig-toolchain owns them" → "r-zig-build-tools owns
  them (B41); r-zig-slim owns rzig". No code change.

### recipe/test-preflight.R (steps 1, 3)

Rewritten. It runs in r-zig-slim's own test env (r-zig-slim and its run
closure), in the consume task's default env, and, through wheel-test, for
the r-zig wheel alone (Cg10). One text holds every channel's line (B35),
so the same assertions hold on all three.

```r
## r-zig-slim alone (the r-zig wheel alone too, wheel-test.sh): rzig is
## in the base (feat-standalone-toolchain B19, phase 4). An R-only package
## installs; one with compiled code stops in the preflight (patch 0009)
## with rzig's text, which names r-zig-compilers, and installs nothing.
<the shared header>
narrow()
tc <- file.path(R.home(), "bin", "toolchain")
stopifnot(file.exists(file.path(tc, if (windows) c("gcc.exe", "rzig.exe") else c("zig-cc", "rzig"))),
          file.exists(file.path(R.home(), "share", "zig", "rpkg", "build_t1.zig")),
          !dir.exists(file.path(tc, "binutils")), !dir.exists(file.path(tc, "usr")))
## no writer of R_ZIG_TOOLCHAIN_HINT came back (B35) (Cc9)
for (f in file.path(R.home("etc"), c("Renviron", "Renviron.site")))
    if (file.exists(f)) stopifnot(!any(startsWith(readLines(f, warn = FALSE), "R_ZIG_TOOLCHAIN_HINT=")))
... mkpkg, the R-only install (as today) ...
inst <- function(pkg) run_to(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", "-l", shQuote(lib), shQuote(pkg)))
r <- inst(mkpkg("rzigsrc", src = TRUE)); cat(r$out, sep = "\n")
pip <- if (windows) "  pip:         no wheels for Windows" else "  pip:         pip install r-zig-compilers (zig only: PyPI has no Fortran compiler)"
stopifnot(r$status != 0L,
          ## no zig is reachable: ZIG_BIN unset, no TC/zig, none in the
          ## env's bin or on this PATH, no python3 with ziglang (Cc8);
          ## rzig says `zig-cc:` on Windows too (main.zig: gcc is .cc)
          any(startsWith(r$out, "zig-cc: no zig (")),
          any(startsWith(r$out, "Compiling needs the r-zig compilers for R ")),
          any(startsWith(r$out, "  conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers)")),
          any(startsWith(r$out, pip)),
          any(grepl("which is incomplete (see above)", r$out, fixed = TRUE)),
          !any(startsWith(r$out, "hint:")),                       # (Cc9)
          !dir.exists(file.path(lib, "rzigsrc")))
## a configure script R runs needs both groups: both texts in one stop,
## and the script does not run (open point H) (Cg1)
r <- inst(mkpkg_conf("rzigconf"))   # R-only; configure (Windows: configure.win) writes a marker
stopifnot(r$status != 0L,
          any(startsWith(r$out, "Compiling needs the r-zig compilers for R ")),
          any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")),
          !file.exists(file.path(d, "rzigconf-ran")))
## a user's own R_ZIG_TOOLCHAIN_HINT: shown after rzig's text on a 127
## (C8; open point B) (Cg4)
Sys.setenv(R_ZIG_TOOLCHAIN_HINT = "r-zig-test-hint")
r <- inst(file.path(d, "rzigsrc")); stopifnot(any(r$out == "hint: r-zig-test-hint"))
Sys.unsetenv("R_ZIG_TOOLCHAIN_HINT")
```

- The `no zig` line is asserted now. PLAN.md's phase 4 step asks for it,
  and with PATH narrowed no zig is reachable (Cc8). So there is no
  departure to record.
- **H (b) or (c).** Under H (b), the r-zig-toolchain clause in the line
  checks goes. Under H (c), the configure-script check expects only the
  compilers text.

### recipe/test-compilers.R (new, step 1)

r-zig-slim + r-zig-compilers: verify-bundle's scenario 2 on conda.

- **The shared header.** PATH is `env_bin`, plus R's bin\x64 and System32
  on Windows. There is no usr\bin.
- **No make on PATH.** `stopifnot(!nzchar(Sys.which("make")))`, failing
  with "make on PATH in an env without r-zig-build-tools: <path>". This
  is the group boundary: it catches a run dependency that brings make.
  `Sys.which` scans PATH in R (patch 0002).
- **The Fortran check.** `run_to(<CC's rzig>, "--rzig-check=fortran")`
  must give:
  - exit 0;
  - "compilers ok: zig 0.16.";
  - "flang at " + a path whose directory compares equal (`same_path`) to
    `shown(env_bin)` (Cc3).

  The test does not claim B34's order, since `env_bin` and PATH are the
  same directory here. rzig-test covers the order: find_zig.zig:159 and
  flang_rt.zig:151 (Cc18).
- **A C package and a Fortran package**, each installed with
  `RZIG_TRACE=1` through `R CMD INSTALL` into a temp library. Each log
  must say `rzig build: tier 1`, and each package must load and return
  its value.
  - The C package is src/one.c.
  - The Fortran package is src/s.f with no Makevars: the FLIBS path, on
    every OS (Cc10 b).
  - Windows' FLIBS path through rzig build already runs in CI:
    contract-test's quadprog (pure Fortran, rzig build) runs on
    windows-latest. So this adds the conda env's version of a tested
    path.
  - Cost: on Windows and macOS, FLIBS pulls in libc++ (Windows FLIBS is
    `-lflang_rt.runtime -lc++`; macOS's flang runtime is C++). The first
    cold zig cache of the leg builds it. test-toolchain.R reuses it
    through `R_ZIG_TEST_ZIG_CACHE` (Cc11).
  - There is no C++ package: test-toolchain.R covers C++.
- **A package with a Makevars rule** (test-toolchain.R's rzigar shape).
  The install fails, and nothing is left in the library. Its output must
  have:
  - "rzigmk needs make: src/Makevars has a rule or target line";
  - "Building packages needs the r-zig build tools for R ";
  - "pixi add r-zig-build-tools (or conda install r-zig-build-tools)";
  - "which is incomplete (see above)".
- **R CMD config, unix only.** `run_to(R, c("CMD", "config", "CC"))` must
  give status 127 and "Building packages needs the r-zig build tools for
  R " (0010).
  - Windows: rcmdfn.c runs `sh config.sh` first, so `R CMD config`
    without sh is phase 7's item.

### recipe/test-build-tools.R (new, step 1)

r-zig-slim + r-zig-build-tools.

- **The shared header.** PATH: unix `env_bin`; Windows `Library\usr\bin`,
  `env_bin`, R's bin\x64 and System32.
- **The build-tools check.** `run_to(<CC's rzig>, "--rzig-check=build-tools")`
  must give:
  - exit 0;
  - "build-tools ok: make at " + a path under the env, compared through
    `shown()` and `same_path()` (Cc3);
  - on Windows also "; sh at …/Library/usr/bin/sh.exe; binutils at
    …/toolchain/binutils".
- **The compilers check.** `run_to(<CC's rzig>, "--rzig-check")` must
  give exit 127 and "pixi add r-zig-compilers" (Cc2).
- **R CMD config.** `R CMD config CC` must exit 0. Then (Cc1):
  `cc <- strsplit(trimws(out), " +")[[1]][1]` and
  `stopifnot(basename(dirname(cc)) == "toolchain", basename(cc) == if (windows) "gcc.exe" else "zig-cc")`.
  The value has `-std=gnu23` after it on unix (every subst.txt:256) and
  `$(M_ARCH)` on Windows. So 0010 passes, and make reads Makeconf.
- **Installed but not on PATH (open point I) (Cg2).** With PATH set to an
  empty directory in `d` (Windows: plus System32),
  `run_to(<CC's rzig>, "--rzig-check=build-tools")` must give:
  - exit 127;
  - the line "is installed in R's environment, which is not on PATH",
    naming the env's make (Windows: make.exe under Library/usr/bin);
  - the build-tools text.

  Restore PATH afterwards with `narrow(usr_bin = TRUE)`.
- **Windows only:**
  - `SOURCES` names binutils_impl_win-64 with a sha256, and
    `LICENSES/binutils_impl_win-64/` is not empty. These move from
    test-toolchain.R:221-229, which keeps its NM, OBJDUMP and ar.exe
    checks. The existence of the six `.exe` files is now
    `package_contents`' (Cc12).
  - `nm.exe --version`, with PATH = `env_bin` + System32 only, prints
    "GNU nm". That proves E2: zstd.dll comes from the env (SC §12 E).
  - `pkg-config --version` runs.

### recipe/test-toolchain.R (step 1)

- Header 1-5: "r-zig-toolchain (r-zig-compilers and
  r-zig-build-tools)". rzig belongs to r-zig-slim.
- **The shared header replaces 9-19** (Cg9, Cc4).
  - Every install runs with PATH narrowed as in test-build-tools.R. A
    missing run dependency of r-zig-toolchain then fails here, instead
    of being masked by the runner's or the pkg env's tools:
    windows-latest's C:\mingw64\bin, Git's usr\bin, and the pkg env's
    m2 set (SC §3).
  - Before narrowing, resolve
    `readelf <- Sys.which("readelf"); otool <- Sys.which("otool")` and
    use them by path (the readelf-less branch at 167-175 stays).
  - R CMD config, R CMD INSTALL and the make path need only make and
    sh's builtins on unix: shlib.mk's link rule and config.mk's `print`.
    R itself runs with its bin alone (hermetic-check.sh), and patches
    0002, 0007 and 0008 removed `which` and `sed`.
  - If a unix run needs another host tool, that is a finding to record
    under B25 (the host userland). It is not a reason to put /usr/bin
    back, which would hide a missing make.
- **211-217:** "which this package owns" → "r-zig-build-tools' files". The
  SOURCES/LICENSES lines move to test-build-tools.R (above).
- Nothing else changes. The test is "unchanged in what it compiles", as
  PLAN.md's phase 4 says. The narrower PATH changes only where its tools
  come from.

### zigbuild/tools/rzig/groups.zig (steps 1, 2, 3)

- `text()` (101-120) gets the conda line per group in step 1 and the pip
  lines in step 2:
  - the pip compilers line says what pip cannot give (Cg3);
  - both lines name r-zig-toolchain (open point H, (a)) (Cg1, Cg16).

  ```zig
  const pkg = try std.fmt.allocPrint(a, "r-zig-{s}", .{g.name()});
  // open point H (a): the package that installs every group
  const all = "; r-zig-toolchain installs every group";
  const conda = try std.fmt.allocPrint(a, "  conda, pixi: pixi add {s} (or conda install {s}){s}\n", .{ pkg, pkg, all });
  const pip = if (p.windows) "  pip:         no wheels for Windows\n" else switch (g) {
      .compilers => "  pip:         pip install r-zig-compilers (zig only: PyPI has no Fortran compiler)" ++ all ++ "\n",
      .build_tools => "  pip:         pip install r-zig-build-tools" ++ all ++ "\n",
  };
  ```

- The first lines and the standalone lines are unchanged (SR §1). So
  hermetic-check.sh, verify-bundle.sh and parity-test.sh, which grep
  only those lines for presence, need nothing.
- Tests 163-197 and 207: the five expected texts, with the new lines.
  check.zig's tests build their expectations from `groups.text` (SR §2),
  so they follow without edits.
- Header 16-37 (step 3):
  - The conda/pip bullet says that phase 4 names the per-group packages
    and r-zig-toolchain.
  - The hint paragraph becomes: "rzig does not read
    R_ZIG_TOOLCHAIN_HINT. Nothing writes it since phase 4. The
    preflight (patch 0009) shows a user's own value after rzig's text
    when the check exits 127."

### zigbuild/tools/rzig/check.zig (step 3; open points H and I) (Cg1, Cg2)

The planner listed this file as unchanged. H and I change it.

- **H (a): every missing group in one stop.**
  - In `packageIn`, compilers stay first (269-270). When `compilers()`
    returns 127 and the package needs the build tools (`configure`, or
    tier `.make`), call `buildToolsFound()`.
  - If those are missing too, report the build-tools text as well:
    `groups.report(ctx, what, .build_tools)`. Return one 127.
  - A version mismatch (exit 1) returns as today.
  - Unit tests:
    - a configure-script package with neither group → both texts,
      compilers first, then exit 127;
    - a tier-1 package with neither group → only the compilers text.
  - The header's `=package` paragraph says so.
- **I (a): build tools installed but not on PATH.**
  - In `buildToolsFound`, when make is not found, or on Windows make or
    sh, and R's own environment has it (`environment.own`): unix
    `<dir>/bin/make`; Windows `<dir>/usr/bin/make.exe` and `sh.exe`,
    with `<dir>` being `<root>/Library`.
  - The missing line then reads: "no make on PATH; <path> is installed
    in R's environment, which is not on PATH: activate it (pixi shell,
    conda activate) or start R with pixi run".
  - The group text follows unchanged (B35). Finding make stays PATH's
    (B34's note).
  - The standalone tree and the wheel have no make in `<dir>/bin`, so
    nothing changes for them.
  - Unit tests: a fixture env with `bin/make` and an empty PATH → the
    line; with neither → today's line.

### zigbuild/tools/rzig/fortran.zig (step 3)

- The test at 277-310 stays, since rzig never reads the hint.
- Comment 290-291 → "R_ZIG_TOOLCHAIN_HINT, a user's value since phase 4,
  changes nothing". The two hint strings may stay as sample values.

### build.zig (step 3)

- Delete the option and its comment (311-318), Ctx's field (130) and its
  init (495).
- **installEnvRuntime:**
  - Delete the writer (3153-3155).
  - Its doc (3092-3095) drops "it carries the compile preflight's hint".
  - Renviron.site is then written for the conda build (MY_TCLTK) and for
    a tree with fonts (FONTCONFIG_PATH), as before.
  - `site.items.len > 0` (3210) keeps working when the list is empty.
- **finalRenviron:** delete the writer (3837-3839) and "the compile
  preflight's hint comes from -Dtoolchain-hint" (3812).
- **1900's comment:** "(etc/Renviron.site: installEnvRuntime)".
- **installRzig's doc (2564-2565):** "The r-zig-toolchain packages own
  this directory" → "The base carries them on every channel: the base
  archive, r-zig-slim and the r-zig wheel (B19). The groups' packages
  hold only subdirectories (B28, B29)".

### scripts/zig-build.sh (step 3)

- Delete 56-65, and `"${conda[@]}"` from 77.

### zigbuild/patches/R-4.6.1/0009-install-compile-preflight.patch (step 3; C8; open points B, J) (Cg4, Cg5)

- **Header 28-31.**
  - Replace with: "rzig ships with R on every channel (the base archive,
    r-zig-slim, the r-zig wheel; feat-standalone-toolchain phase 4). A
    check that exits 127 (a group missing) stops with '...which is
    incomplete (see above)', after a user's own R_ZIG_TOOLCHAIN_HINT as
    a `hint:` line when one is set. Any other status (a package make
    cannot build, a zig that is not R's, a path that does not resolve)
    stops with 'this package cannot be built (see above)'."
  - The "Both stops say" sentence (31-33) is reworded to match.
  - The header also gets code-6's extra line, which the review's
    follow-up list says it lacks.
- **Code.**
  - Delete 68-77: the comment and the `!file.exists(rzig)` stop.
  - The comment at 65 stays.
  - After the check:

  ```r
              ## 127: a group is missing, rzig named it above; a site's or
              ## a user's own pointer follows (feat-standalone-toolchain
              ## B35, PHASE3 C8). Any other status: the package cannot be
              ## built as it is, and no group would help (check.zig's
              ## exit 1, with its own line above; 2: a path)
              if (status == 127L) {
                  hint <- Sys.getenv("R_ZIG_TOOLCHAIN_HINT")
                  if (nzchar(hint)) message("hint: ", hint)
                  pkgerrmsg("this package needs the r-zig toolchain (compiled code or a configure script), which is incomplete (see above)",
                            pkg_name)
              }
              if (status != 0L)
                  pkgerrmsg("this package cannot be built (see above)", pkg_name)
  ```

- **I-T11's fixed texts** become three: the 127 stop, unchanged; the
  non-127 stop, new; and the removed "not installed" stop. Record this
  in fix-zig-pkg-build-review's I-T11 note and in PLAN.md's phase 4
  record.
- **A damaged tree with no CC binary.** system2 returns 127 (unix: sh
  says "not found"), and the 127 stop follows. This is accepted: no
  channel ships R without rzig after phase 4 (risk 12).
- **J (b).** Keep the single `if (status != 0L)` with the hint inside
  `status == 127L`. TODO.md then gets the item (section 11).

### zigbuild/patches/R-4.6.1/0010-config-make-check.patch (step 3; open point B (b)) (Cg4)

- Header 10-12 and comment 24-25: drop "Without rzig ...".
- Code 31-36 → the rzig line alone:
  `"${rzig}" --rzig-check=build-tools > /dev/null || exit`. It prints no
  hint, since B (b) keeps the hint to 0009, as C8 decided.
- With B (a), use the planner's four-line block, on status 127 only.

### zigbuild/patches/R-4.6.1/0013-install-rzig-build.patch (step 3; open point C)

- **Recommended (a):**
  - Delete the "older than this R" stop (64-74, with its `cc` lookup)
    and its header sentence (30-31).
  - Keep I-PF4's `R_ZIG_PKG_BUILDER=zig` stop (77-79) and `return(NA)`
    (80).
  - The comment above becomes "no rzig: a damaged tree; the make path,
    unless R_ZIG_PKG_BUILDER=zig".
- **Whatever C's answer:** regenerate 0013 on the new 0009. Its install.R
  hunks sit after 0009's, and the series must apply with no offset and
  no fuzz.

### stress/stress.R and stress/README.md (step 3; open point J) (Cg5, Cc19)

- **stress.R:207**, the preflight-stop branch, also matches "this package
  cannot be built (see above)" after rzig's line. With a "src/build.zig
  cannot be built by make" line it classifies as `package`, as 225
  already does. Any other non-127 stop classifies as `toolchain`.
- **stress.R:181** keeps both I-T11 wordings, harmlessly. Rows from `_8`
  logs still say "not installed".
- **stress/README.md:227:**
  - The toolchain row's "or `which is not installed`" becomes history:
    "build 8 and earlier also said `which is not installed`".
  - The package row's "though the preflight's stop after it says the
    toolchain is incomplete" → "the preflight's stop after it says the
    package cannot be built".

### scripts/make-wheel.py (step 2; B29, B35; open points A, E)

- **Docstring 1-38:** four wheels; rzig is the base's (B19); the
  toolchain tree's usr/ is r-zig-build-tools'.
- **Constants 58-63:**
  - Add `COMPILERS_DIST = "r-zig-compilers"`,
    `BUILD_TOOLS_DIST = "r-zig-build-tools"` and
    `TOOLCHAIN_DIST = "r-zig-toolchain"`.
  - `TOOLCHAIN_PREFIX` and `TOOLCHAIN_USR` stay.
  - Delete `TOOLCHAIN_HINT` (63).
- **Hint:** delete `renviron_hint` (258-264) and its use (431-432).
  `renviron_site` (242-255) stays: it is the wheel's one channel-specific
  setting (B35).
- **Preconditions (385-386):** also require `TC/rzig`, the hook's name,
  with "run `pixi run -e minimal build` first".
- **Split (434-437):**
  - `bt_files` = the files under `TOOLCHAIN_USR`: the toolchain tree's
    make, SOURCES and LICENSES/make.
  - Everything else, rzig ×6 included, stays in `files`.
  - Die if `bt_files` is empty (393-394 already requires make).
  - The stray check (412-420) stays.
- **Tags (439):** `platform_tags(files + bt_files)`, one tag set (B29). A
  make-only wheel alone would tag macOS 11.0 (SP §2).
- **Metadata:** one table (name, summary, description, Requires-Dist,
  licence) for the four wheels.
  - **r-zig:** as today. Its description gives the one recommendation
    (Cg16): rzig is included; to compile, `pip install r-zig-toolchain`;
    r-zig-compilers alone installs packages with no configure script and
    no make rules.
  - **r-zig-compilers:** no files. Requires-Dist `r-zig==<ver>` (open
    point A) and `ziglang>=0.16.0,<0.16.1` (68).
  - **r-zig-build-tools:** `usr/**`. Requires-Dist `r-zig==<ver>`. With
    E (a), `License: GPL-3.0-or-later`, with make's COPYING (already at
    `usr/LICENSES/make/COPYING`) as its dist-info licence.
  - **r-zig-toolchain:** no files. Requires-Dist
    `r-zig-compilers==<ver>` and `r-zig-build-tools==<ver>`.
- **Writing:** `write_wheel` (461-506) already writes a dist-info-only
  zip for empty `entries` (SP §13.3). The wheel file names are
  `r_zig_compilers-...`, `r_zig_build_tools-...` and
  `r_zig_toolchain-...` (457's `replace("-", "_")`).

### python/r_zig/__init__.py (step 2)

- Docstring 8-17, in the same words as the wheel's description (Cg16):
  - rzig is in this wheel;
  - to compile, `pip install r-zig-toolchain` (r-zig-compilers brings
    ziglang; r-zig-build-tools brings GNU make);
  - there is no Fortran (B29).
- Code unchanged.

### scripts/wheel-test.sh (step 2)

Rewritten around pip's three scenarios, with two PATHs:
- `run`: venv/bin, /usr/bin and /bin, as today (113-115). For what needs
  no boundary.
- `run_venv`: venv/bin alone. For where a host make or zig would hide a
  missing group (SP §13.7). hermetic-check runs R with its bin alone in
  the same way.

The base-alone checks are recipe/test-preflight.R itself, which narrows
PATH on its own (Cg10).

- **Header 1-34:** the scenarios below.
- **Globs 39-44:** four wheels, one each (`r_zig-`, `r_zig_compilers-`,
  `r_zig_build_tools-`, `r_zig_toolchain-`).
- **r-zig alone:**
  - Install. No ziglang is pulled in (48-55).
  - The profile check (124-132): `file.exists(TC/zig-cc)` and `TC/rzig`
    are TRUE (128 flips), and there is no `TC/usr`.
  - TLS (140).
  - Then `run "$T/venv/bin/Rscript" "$ROOT/recipe/test-preflight.R"`. Its
    `env_bin` resolves to `r_zig/R/bin`. Its assertions hold on pip,
    since one text has every channel's line (B35), the pip line
    included:
    - rzig and rpkg are there, with no group directory;
    - no hint writer;
    - an R-only install works;
    - the `zig-cc: no zig (` stop;
    - the configure-script stop with both texts;
    - the user's hint.
  - This replaces 142-150 and the planner's shell copy of the scenario.
    The planner's skip "when /usr/bin/zig exists" goes: neither
    test-preflight.R's PATH nor `run_venv` has /usr/bin, so it could
    never trigger (Cc8, Cg11).
- **+ r-zig-compilers:**
  - `pip_ install <compilers wheel>`. ziglang comes from PyPI or
    PIP_FIND_LINKS. `r-zig==<ver>` is already installed, so pip queries
    no index for it (Cc14).
  - ziglang is installed, and `TC/usr/bin/make` is absent.
  - zig-fc with no flang (166-190): exit 127, "LLVM flang on PATH", and
    "pip install r-zig-compilers (zig only: PyPI has no Fortran
    compiler)" (Cg3). The negative grep of the old hint (186) goes.
  - The console-script install (192-202), with `RZIG_TRACE=1` under
    `run_venv`: `rzig build: tier 1`, and the package loads. The static
    C++ runtime check (204-222) and the CONDA_PREFIX decoy (224-247) use
    that build.
  - R_ZIG_EXTRA_ENV (249-272): unchanged.
  - The `ZIG_BIN=/nonexistent` install (288-295) gets `RZIG_TRACE=1`, and
    its output goes to `$T/install3.log` (today it goes to the
    terminal). The test greps `rzig build: tier 1` in that log (Cc6; SP
    §5: inferred today).
  - rzigwheelar (296-307), under `run_venv`, fails with:
    - "rzigwheelar needs make: src/Makevars has a rule or target line";
    - "pip install r-zig-build-tools";
    - the stop.
- **+ r-zig-build-tools:**
  - `Sys.which("make")` ends in `bin/toolchain/usr/bin/make`, and MAKE
    is `make` (152-164).
  - rzigwheelar builds through the wheel's make (as 305-307).
  - The bundled bin/R with `R_ZIG_PKG_BUILDER=make` (274-287).
- **+ r-zig-toolchain:**
  - `pip_ install <toolchain wheel>` resolves from the installed groups.
  - `pip_ show -f r-zig-toolchain`: no line under "Files:" lies outside
    `r_zig_toolchain-<ver>.dist-info/`. The same holds for
    r-zig-compilers. pip lists the dist-info files (METADATA, WHEEL,
    RECORD, INSTALLER, REQUESTED, licenses/), so "no file" cannot be the
    test (Cc6).
- **A second venv**, `$T/venv2`, with its own `pip2_` (Cc5, Cc14):
  - `pip2_ install 'ziglang>=0.16.0,<0.16.1'` (PyPI or
    PIP_FIND_LINKS).
  - Then
    `pip2_ install --no-index --find-links "$ROOT/dist/wheel" "r-zig-toolchain==$R_VERSION"`.
    The other three come from dist/wheel, and pip queries no index for
    names that are not registered on PyPI.
  - `pip2_ list` has r-zig, r-zig-compilers, r-zig-build-tools,
    r-zig-toolchain and ziglang.
  - With venv2's bin on PATH:
    `Rscript -e 'stopifnot(grepl("bin/toolchain/usr/bin/make$", Sys.which("make")))'`.
    The planner's `nzchar(Sys.which("make"))` passes on every runner,
    whose /usr/bin has a make.
- **Uninstall (309-319):**
  - `pip_ uninstall -y r-zig-toolchain r-zig-build-tools r-zig-compilers`.
  - The files left directly under TC are exactly `rzig_names`
    (verify-helpers.sh:41-47), and none are under `usr/`. pip may leave
    empty directories (C32).
  - R runs, and an R-only package installs.
  - A compiled package still builds, because ziglang stays and
    Renviron.site's ZIG_BIN finds it (SP §13.6).
  - Then `pip_ uninstall -y ziglang`, and run test-preflight.R again:
    this is base alone. Its own PATH keeps a host zig out (Cc6, Cg10).

### scripts/conda-consume.sh and its task (new, step 1) (Cg8, Cc11)

One script, run by CI on every conda-package leg and by each host. It
replaces today's win-64-only step and the planner's per-leg bash with an
OS branch.

```bash
#!/usr/bin/env bash
# The conda packages as a user consumes them: a fresh pixi workspace from
# this checkout's dist/conda (then conda-forge and universe, as stress.R
# --conda orders them), one environment per group, and the recipe's tests
# run through pixi's activation by bare Rscript (win-64:
# Library/bin/Rscript.bat, which rattler-build's test phase cannot run).
# CI runs it on every conda-package leg before the publish; each host runs
# it after conda-package (feat-standalone-toolchain phase 4).
. "$(dirname "$0")/env.sh"
ch="$ROOT/dist/conda"; rec="$ROOT/recipe"; cache="$ROOT/build/conda-test-zig-cache"
[ -d "$ch/$PLAT" ] || { echo "error: no $ch/$PLAT: run 'pixi run -e pkg conda-package' first" >&2; exit 1; }
if command -v cygpath > /dev/null 2>&1; then
  ch="$(cygpath -m "$ch")"; rec="$(cygpath -m "$rec")"; cache="$(cygpath -m "$cache")"
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# this checkout's pixi workspace must not leak in (as stress.R:257-259)
unset PIXI_PROJECT_MANIFEST PIXI_PROJECT_ROOT PIXI_PROJECT_NAME PIXI_PROJECT_VERSION \
  PIXI_ENVIRONMENT_NAME PIXI_ENVIRONMENT_PLATFORMS PIXI_IN_SHELL PIXI_PROMPT R_ZIG_EXTRA_ENV
cat > "$T/pixi.toml" << EOF
[workspace]
name = "r-zig-consume"
channels = ["$ch", "conda-forge", "https://prefix.dev/universe"]
platforms = ["$PLAT"]

[dependencies]
r-zig-slim = "*"

[feature.compilers.dependencies]
r-zig-compilers = "*"

[feature.build-tools.dependencies]
r-zig-build-tools = "*"

[environments]
compilers = ["compilers"]
build-tools = ["build-tools"]
EOF
# the zig cache conda-package's recipe tests filled (pixi.toml)
export R_ZIG_TEST_ZIG_CACHE="$cache"
for t in default:test-preflight.R compilers:test-compilers.R build-tools:test-build-tools.R; do
  echo "== ${t%%:*}: ${t#*:}"
  pixi run --manifest-path "$T/pixi.toml" -e "${t%%:*}" Rscript "$rec/${t#*:}"
done
```

- **No OS branch.** The one guarded line is env.sh:155's existing
  `cygpath -m` pattern. On win-64, bare `Rscript` under `pixi run` is
  Library/bin/Rscript.bat: the shim the old step checked, now behind
  every test.
- **Nested pixi.** It follows stress.R's precedent (stress.R:255-269):
  `--manifest-path` on every call and PIXI_* unset.
- **One manifest, three environments.** There is no `pixi add` /
  `pixi remove` sequence. Removal is not tested on conda: removing a
  package removes its own files, and the files that move between
  packages are the upgrade test's (section 7).
- **Cost.** The packages are already in rattler's cache from the test
  phase. The zig cache is the one the recipe tests filled (Cc11), so
  test-compilers' compiles are warm. CI records the step's time per leg
  on the PR. The step runs on all five legs: this is decided now, not
  "if slow" (Cg8).
- **The cache trap.** The script uses rattler's normal package cache.
  conda-package empties dist/conda first, so a rebuilt `_9` gets a fresh
  index entry and a new sha256 that a cached `_9` does not match. The
  recipe's own tests rely on the same thing (section 1).
- **The pkg task:** `conda-consume = "bash scripts/conda-consume.sh"`.

### scripts/verify-tree.sh (step 4)

- Comments 101-103 and 126-127: "r-zig-toolchain's copies" →
  "r-zig-build-tools' copies (B41)". No code change: the conda exception
  (126-133) still holds (SR §10).

### zigbuild/config (step 4; D7)

- `linux-x86_64-{slim,full}` and `linux-arm64-{slim,full}`: in config.h:8
  and subst.txt:5, the clangdev string `0b2bbeec...` →
  `334cf9a5e6c0331e9f261eaf01fc3568724fcce9`.
  - This is what the locked zig `_20` prints on every subdir. The
    minimal configs already say it (SC §8).
- `osx-arm64-{slim,full,minimal}` FC_VER (config.h:38, subst.txt:3):
  whatever `flang --version` prints on omicron with flang-zig `_6`.
  - Today it is `... (https://github.com/luciorq/flang-pixi cf4a479f...)`.
    What `_6` prints is unknown (SC §12 D). If it still says that, no
    change.
- Windows: hand-written strings (build.zig:976-977), unchanged.
- The drift that remains goes to TODO's "Later": build.zig computes
  CC_VER/FC_VER on every OS (section 11) (Cg15).

### README.md (step 4)

- **11-15** (Cc19, Cg17):
  - Name all five platforms: linux-aarch64 is published too (SC §4).
  - "currently private": open point L. With (a), it says the channel is
    public and needs no login.
- **25-38:** the one recommendation, in the same words as r-zig-slim's
  description and the r-zig wheel's (Cg16):
  - "To compile packages, add r-zig-toolchain (r-zig-compilers and
    r-zig-build-tools)."
  - r-zig-compilers alone (zig 0.16, LLVM flang, OpenMP) installs
    packages that have no configure script and whose Makevars only sets
    variables (rzig build).
  - r-zig-build-tools (make; Windows also sh, the MSYS2 tools,
    pkg-config and the MinGW binutils) is for:
    - configure scripts and Makevars rules;
    - `R CMD SHLIB` (Rcpp::sourceCpp, inline);
    - pak, whose compiler probe runs `R CMD SHLIB` (feat-zig-pkg-build
      N2).
  - Without a group, an install that needs it stops, naming the package
    to add.
  - In an env used without activation (an IDE pointed at
    `<env>/bin/R`), make is not on PATH: activate the env or start R
    with `pixi run` (open point I).
- **46-47:** four `.conda` files. Add `pixi run -e pkg conda-consume`
  (Cg8).
- **127-156:** four wheels. No Fortran on pip (B29). Until the wheels are
  on PyPI (Cc14):
  - `pip install 'ziglang>=0.16.0,<0.16.1'`;
  - then `pip install --no-index --find-links dist/wheel r-zig-toolchain`.

### pixi.toml (steps 1, 4)

- **conda-package (552)** (Cc11): its rattler-build call gets the tests'
  shared zig cache, in deno_task_shell's `NAME=value command` form, with
  no OS branch:
  `R_ZIG_TEST_ZIG_CACHE=$PIXI_PROJECT_ROOT/build/conda-test-zig-cache rattler-build build ...`.
  Its comment says that rattler-build's test env inherits it (SC §3),
  and that conda-consume.sh names the same directory.
- **`[feature.pkg.tasks]`:** `conda-consume` (Cg8).
- **Comments only:**
  - 427-430: the wheel's compiler comes with r-zig-compilers;
  - 488-495: four wheels;
  - 513-516: wheel-test's scenarios;
  - 546: "r-zig-toolchain's test" → "a package's test".
- No dependency change.

### .github/workflows/build.yaml (step 4) (Cg8)

- Replace "Fresh-env consume test (Windows PATH shim)" (299-308) with one
  step on every leg. It goes after "Build + test conda package" and
  before the publish, so a failure blocks that subdir's upload:

  ```yaml
      # A fresh pixi workspace from this run's packages, one environment
      # per group (scripts/conda-consume.sh): the recipe's tests through
      # pixi's activation and bare Rscript (win-64: Library/bin/Rscript.bat,
      # which rattler-build's test phase cannot run).
      - name: Fresh-env consume test (each group alone)
        run: pixi run -e pkg conda-consume
  ```

  - The tests narrow PATH themselves. So the runner's tools
    (windows-latest's C:\mingw64\bin, Git's usr\bin; SC §3) cannot stand
    in for a group.
- No other workflow changes:
  - build-r.yaml uploads `dist/wheel/*.whl`, any number (SP §12);
  - stress.yaml's conda mode adds r-zig-slim and r-zig-toolchain, which
    still resolve.

### Files that need no change (checked)

- **hermetic-check.sh, verify-bundle.sh and parity-test.sh.** They grep
  the first lines, the standalone lines and the 127 stop, for presence
  only. H adds a second text after the first, and nothing forbids that:
  hermetic-check.sh:157-168, verify-bundle.sh:273-274, 433-435, 603-606
  and 1669, parity-test.sh:600-811 (checked).
- **check.zig's binutils list.**
- **verify-helpers.sh's `rzig_names`.**
- **zigbuild/toolchain/build.zig** (SC §1.3): unix installs nothing into
  the conda prefix; win-64 installs only `binutils/`.
- **stress.yaml, build-r.yaml and upstream-zig.yaml.**

check.zig and stress.R left this list (H, I, J).

## 4. The conda packages per subdir

Build 9; versions 4.6.1.
- r-zig-slim's hash input is only `target_platform`, so it keeps its
  hashes: `hb0f4dca` (linux-64), `he8cfe8b` (linux-aarch64), `he0379dc`
  (osx-64), `h41cfa24` (osx-arm64), `h9490d1a` (win-64).
- The three others hash the exact pins and change with every build
  (SC §3).
- Licences: open point E (Cc15, Cg13). The tables give E (a).

### linux-64, linux-aarch64, osx-64, osx-arm64

| package | files | run dependencies (constraints) | licence (E a) |
|---|---|---|---|
| r-zig-slim | R as today, plus `lib/R/bin/toolchain/{zig-cc,zig-cxx,zig-fc,zig-ar,zig-ranlib,rzig}` (rzig ×6; .conda's zstd stores the copies about once: `_8`'s toolchain was 209,215 B for rzig ×5 of 464,192 B, SR §7) and `lib/R/share/zig/rpkg/{build_t1,build_t2,rpkg}.zig` (already there) | today's (zlib, bzip2, xz, pcre2, libcurl, icu, tzdata, libdeflate, llvm-openmp, cairo, expat, pango, fontconfig, freetype, libpng, glib; linux libiconv, libstdcxx, libgcc; osx libiconv, `__osx >=13.0`) plus `zstd` on every OS, and the staging host's run exports (SC §4: llvm-openmp ≥ the host's, icu, libdeflate <1.26, zstd >=1.5.7,<1.6.0a0, libcurl, ...); run_constraints `zig 0.16.*` (K) | `GPL-2.0-only OR GPL-3.0-only` |
| r-zig-compilers | none (only `etc/conda/test-files/r-zig-compilers/0/test-compilers.R`) | `r-zig-slim ==4.6.1 <hash>_9`, `zig 0.16.*`, `flang-zig ==23.1.1 *_6`, `lld-zig ==23.1.1 *_5`, `flang-rt-zig ==23.1.1 *_10`, `llvm-openmp` | R's |
| r-zig-build-tools | none (only its test file) | `r-zig-slim ==4.6.1 <hash>_9`, `make >=4.4` | R's |
| r-zig-toolchain | none (only test-toolchain.R) | exact r-zig-slim, r-zig-compilers and r-zig-build-tools `_9` | R's |

### win-64

| package | files | run dependencies | licence (E a) |
|---|---|---|---|
| r-zig-slim | R as today, plus `Library/lib/R/bin/toolchain/{gcc,g++,zig-fc,zig-ar,zig-ranlib,gcc-ar,gcc-ranlib,ar,ranlib,rzig}.exe` (rzig ×10) and `Library/lib/R/share/zig/rpkg/*.zig`; no `binutils/` | today's (the common list; libjpeg-turbo, libtiff, `tk 8.6.*`, gettext) plus `zstd` (E2: R.dll imports zstd.dll); run_constraints `zig 0.16.*` (K) | R's |
| r-zig-compilers | none (test file) | as unix. conda-forge's win-64 zig is `Library/bin/x86_64-w64-mingw32-zig.exe` with a `zig.bat`, which rzig finds in the env's bin (B34) | R's |
| r-zig-build-tools | `Library/lib/R/bin/toolchain/binutils/{nm,dlltool,as,strip,windres,objdump}.exe`, `binutils/SOURCES`, `binutils/LICENSES/binutils_impl_win-64/**`. zstd.dll and vcruntime140.dll are not copied in the conda build: there is no `in_conda` (zigbuild/toolchain/build.zig:109-110) | exact r-zig-slim `_9`, m2-bash, m2-sed, m2-grep, m2-gawk, m2-coreutils, m2-make, m2-which, m2-findutils, `pkg-config`, `zstd` (E2; zstd brings vc14_runtime). No native `make` (Cg7) | `GPL-3.0-or-later` (binutils) |
| r-zig-toolchain | none (test file) | exact r-zig-slim, r-zig-compilers and r-zig-build-tools `_9` | R's |

Notes:
- **B41's two exceptions stay.**
  - llvm-openmp's omp.h arrives with r-zig-slim, so rzig turns OpenMP on
    with the base alone once a zig is there (environment.zig:131-136).
  - win-64's binutils are our copies.
- **binutils_impl_win-64 is solved fresh at build time.** conda-forge has
  `_103` today, against the lock's `_102`. The copies and SOURCES' sha256
  follow the day's build (SC §2).
- **E2 is widened to every OS.** E2 named R.dll and win-64
  r-zig-build-tools. osx-arm64's libR.dylib links libzstd too, and
  `HAVE_ZSTD` is set in all 13 configs (SC §9). The phase 4 record says
  E2 was applied on every OS, and why (Cg18).
- What each group package's test proves: section 8.

## 5. The PyPI wheels per platform

The wheels are built from the minimal tree and the toolchain tree. Names
and tags are as in CI's PR #26 artifacts (SP §1), with phase 4's split.

| platform (CI leg) | tag on all four wheels |
|---|---|
| linux-64 (ubuntu-latest) | `manylinux_2_17_x86_64.manylinux2014_x86_64` |
| linux-aarch64 (ubuntu-24.04-arm) | `manylinux_2_17_aarch64.manylinux2014_aarch64` |
| osx-arm64 (macos-latest) | `macosx_13_0_arm64` |
| osx-64 (macos-15-intel) | `macosx_13_0_x86_64` |
| win-64 | none until after phase 7 (C1-C3; make-wheel.py:191 dies) |

ziglang 0.16.0 has a wheel for each of the four tags (glibc 2.12/2.17
floors, macOS 12.0). So `ziglang>=0.16.0,<0.16.1` resolves on every one
(SP §8).

| wheel | contents | Requires-Dist | licence (E a) | size (linux-64) |
|---|---|---|---|---|
| r-zig | `r_zig/{__init__,__main__}.py`; the minimal tree under `r_zig/R/`, with `lib/R/bin/toolchain/{zig-cc,zig-cxx,zig-fc,zig-ar,zig-ranlib,rzig}` (six deflated copies: wheels hold no links); `lib/R/share/zig/rpkg/*.zig`; `lib/R/etc/Renviron.site` (the sibling ziglang as ZIG_BIN's default); `etc/Renviron` without a hint line; console scripts R and Rscript | none | `GPL-2.0-only OR GPL-3.0-only` (as today) | about 51.9 MB: 50.4 MB today plus rzig ×6, about 1.49 MB deflated (osx-arm64 about 49.1 MB; SP §13.1) |
| r-zig-compilers | dist-info only | `r-zig==4.6.1`, `ziglang>=0.16.0,<0.16.1` | R's | a few KB |
| r-zig-build-tools | `r_zig/R/lib/R/bin/toolchain/usr/{bin/make,SOURCES,LICENSES/make/COPYING}` | `r-zig==4.6.1` | `GPL-3.0-or-later`, make's COPYING as the dist-info licence | about 0.16 MB |
| r-zig-toolchain | dist-info only | `r-zig-compilers==4.6.1`, `r-zig-build-tools==4.6.1` | R's | a few KB |

- **No Fortran and no OpenMP on PyPI** (B29 a).
  - zig-fc stops with exit 127 and the compilers text. Its pip line says
    "zig only: PyPI has no Fortran compiler" (Cg3).
  - rzig drops `-lflang_rt.runtime` from FLIBS when there is no flang
    (flang_rt.zig:138-143).
  - The minimal Makeconf's `SHLIB_OPENMP_*` are empty, and the wheel has
    no libomp (SP §7).
- **How rzig finds zig in a pip install** is unchanged
  (find_zig.zig:36-54; SP §4):
  1. ZIG_BIN. The console scripts set it from `import ziglang`;
     otherwise Renviron.site's sibling.
  2. The env's bin.
  3. PATH.
  4. `python3 -m ziglang`.
- **The names.** None of the four names is registered on PyPI (Cc14).
  The tests and the README install the group wheels with `--no-index`.
  Reserving the names belongs with B12, and goes to TODO (section 11).
- The pins (A) and the licences (E) are open points.

## 6. rzig's texts per channel, and what R does when a group is missing

### The texts (groups.zig after phase 4, with H (a) and Cg3)

```
Compiling needs the r-zig compilers for R 4.6.1 on linux-64: zig 0.16, and flang for Fortran.
  standalone:  zig 0.16 on PATH or in ZIG_BIN, LLVM flang on PATH; for OpenMP, extract R-4.6.1-linux-64-compilers.tar.gz where you extracted R
  conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers); r-zig-toolchain installs every group
  pip:         pip install r-zig-compilers (zig only: PyPI has no Fortran compiler); r-zig-toolchain installs every group

Building packages needs the r-zig build tools for R 4.6.1 on linux-64: make.
  standalone:  extract R-4.6.1-linux-64-build-tools.tar.gz where you extracted R, or put GNU make on PATH
  conda, pixi: pixi add r-zig-build-tools (or conda install r-zig-build-tools); r-zig-toolchain installs every group
  pip:         pip install r-zig-build-tools; r-zig-toolchain installs every group

Compiling needs the r-zig compilers for R 4.6.1 on win-64: zig 0.16, and flang for Fortran.
  standalone:  zig 0.16 on PATH or in ZIG_BIN, LLVM flang on PATH; for OpenMP, extract R-4.6.1-win-64-compilers.zip where you extracted R
  conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers); r-zig-toolchain installs every group
  pip:         no wheels for Windows

Building packages needs the r-zig build tools for R 4.6.1 on win-64: sh, make, binutils and the tools R's makefiles run.
  standalone:  extract R-4.6.1-win-64-build-tools.zip where you extracted R (binutils), and put sh and make on PATH (for example Rtools45's usr/bin)
  conda, pixi: pixi add r-zig-build-tools (or conda install r-zig-build-tools); r-zig-toolchain installs every group
  pip:         no wheels for Windows
```

- osx-* and linux-aarch64 read as linux-64, with their platform name.
- There is one text per group, with every channel's line in it (B35 a).
  The user reads the line for their channel. Under H (b) or (c), the
  "; r-zig-toolchain installs every group" clauses go.
- The line before the text says what is missing. It starts with
  `zig-cc: ` on every OS (Windows' gcc.exe maps to the same tool,
  main.zig):
  - `zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the
    environment's bin, PATH, python3 -m ziglang)`;
  - `zig-cc: no flang (...)`;
  - `<pkg> needs make: <reason>; no make on PATH`, which with I (a)
    adds "; <path> is installed in R's environment, which is not on
    PATH: ..." when it is;
  - `<zig> is zig 0.17.0, not R's zig 0.16 (R_ZIG_NO_PREFLIGHT=1 skips
    this check)` (check.zig:128-131).

### What R does

The same on all three channels; only which line applies differs.
- "stop (127)" means: rzig's line and the group's text, or both texts
  (H), on stderr. Then `hint: <R_ZIG_TOOLCHAIN_HINT>` when it is set (B
  b). Then 0009's "ERROR: this package needs the r-zig toolchain
  (compiled code or a configure script), which is incomplete (see
  above)". Nothing is installed.
- "stop (other)" means: rzig's lines, then 0009's "ERROR: this package
  cannot be built (see above)" (J a), with no hint.

| situation | preflight (0009, `--rzig-check=package`) | hook (0013, `rzig build`) and the rest |
|---|---|---|
| no compilers group (base alone, or base + build tools); a package with src/ or a configure script R runs | stop (127): no zig, compilers text (checked first: check.zig:269-270); with H (a), also the build-tools text when the package needs make or a configure script runs and make is missing too (Cg1) | with the preflight skipped (a user Makevars, `R_ZIG_NO_PREFLIGHT`): rzig build exits 127 with the same text, and the install fails; a tier-3 package fails at make's first zig-cc |
| a zig of another major.minor found (a user's conda-forge zig 0.17, gamma's `~/.pixi/bin/zig`) | stop (other): exit 1, "is zig 0.17.0, not R's zig 0.16", compilers text. On conda, K (a) keeps a solved env from getting there (Cc13) | compiles are not version-checked (check.zig header) |
| R-only package, no configure | no check | installs (tier 0) |
| compilers present, tier 1 or 2, no configure | passes | rzig build; no make needed, Windows included (no sh, no binutils) |
| compilers present, no build tools; tier 3 (a configure script, src/Makefile, a Makevars rule, `$(shell)`, ...) or a configure script R runs | stop (127): "<pkg> needs make: <reason>; no make on PATH", build-tools text | unix: a host make on PATH satisfies the check, and the package builds with it (B25: make from PATH; standalone, conda and pip alike) |
| tier 1 with Fortran sources, no flang | stop (127): no flang, compilers text | pip always (B29: "zig only: PyPI has no Fortran compiler"); conda: flang comes with r-zig-compilers; standalone: LLVM flang on PATH until phase 6 |
| a tier-2 package whose plan needs make | stop (other): exit 1, I-C1's line and "the r-zig toolchain is complete: ..." (code-6), then "this package cannot be built (see above)" (J a) (Cg5) | no group would help |
| `R CMD config` with no build tools | — | 0010: rzig's build-tools text, exit 127; no hint line (B b) (Cg4). Windows without sh: rcmdfn.c's own error (phase 7) |
| `R CMD SHLIB`, pak/pkgbuild's probe, Rcpp::sourceCpp | — | make not found, no rzig text. The README's recommendation, and rzig's "r-zig-toolchain installs every group" (H a), point to the full set. Routing SHLIB through rzig build is a later item |
| conda env used without activation (unix: `<env>/bin` not on PATH; win-64: R.bat adds nothing to PATH, so m2's `Library/usr/bin` is missing too, SC §6) (Cc19) | zig and flang are found in the env's bin (B34). make (Windows: make and sh) is not; with I (a) the stop's first line says it is installed in R's environment and to activate it (Cg2) | B34's note: finding make stays PATH's |

## 7. The upgrade from universe's `_8`

### What moves (SC §10, SR §8)

| path under `[Library/]lib/R/bin/toolchain/` | `_8` owner | `_9` owner |
|---|---|---|
| unix `zig-cc zig-cxx zig-fc zig-ar zig-ranlib` | r-zig-toolchain | r-zig-slim, same path |
| unix `rzig` | none | r-zig-slim |
| win `gcc.exe g++.exe zig-fc.exe` | r-zig-toolchain | r-zig-slim |
| win `ar.exe ranlib.exe` | r-zig-toolchain (GNU binutils) | r-zig-slim (rzig: other content) |
| win `zig-ar.exe zig-ranlib.exe gcc-ar.exe gcc-ranlib.exe rzig.exe` | none | r-zig-slim |
| win `as.exe dlltool.exe nm.exe strip.exe windres.exe` | r-zig-toolchain | gone; `binutils/<tool>.exe` in r-zig-build-tools |
| win `binutils/objdump.exe`, `binutils/SOURCES`, `binutils/LICENSES/**` | none | r-zig-build-tools |
| win `ld.exe zig-cc zig-cxx` | r-zig-toolchain | gone |
| `lib/R/share/zig/rpkg/*.zig` | none | r-zig-slim |
| etc/Renviron's (win: Renviron.site's) `R_ZIG_TOOLCHAIN_HINT` line | r-zig-slim `_8` | gone |

Why no clobber error is expected (source reading only, SC §10):
- pixi 0.81.0 (rattler 0.48.6) finishes every unlink before any link. It
  renames a losing file into `__clobbers__/` rather than failing.
- libmamba unlinks all removed packages before linking.
- conda 26.9.2 does not count paths that are unlinked in the same
  transaction.
- The exact pin in r-zig-toolchain `_8` forces the old r-zig-toolchain
  out of the same transaction that brings r-zig-slim `_9` (SC §4). A
  user who adds only `r-zig-compilers` to an env with r-zig-toolchain
  `_8` gets the same forced replacement.

### How to test it (step 5, before merging; open point G)

The test runs on three hosts, each in a scratch directory with fresh
package caches (N5's cache trap):
- gamma (linux-64): pixi, conda and micromamba;
- kappa (win-64, which has the most moves): pixi and conda;
- omicron (osx-arm64): pixi.

`$CH` is the worktree's `dist/conda` from the last conda-package (after
step 4).

**unix (gamma, omicron):**

```sh
T=$(mktemp -d); export PIXI_CACHE_DIR=$T/pixi-cache CONDA_PKGS_DIRS=$T/pkgs MAMBA_ROOT_PREFIX=$T/mamba
CH="$WT/dist/conda"; CH_URL="file://$CH"
# pixi: the user's path, `pixi update`
pixi init --channel https://prefix.dev/universe --channel conda-forge "$T/px" && cd "$T/px"
pixi add r-zig-toolchain                       # universe only: _8 for both names
pixi list | grep -E '^r-zig'                    # r-zig-slim _8, r-zig-toolchain _8
ls .pixi/envs/default/lib/R/bin/toolchain     # before (win-64: .pixi/envs/default/Library/lib/R/bin/toolchain)
pixi workspace channel add --prepend "$CH"
pixi update 2>&1 | tee "$T/px-update.log"
pixi list | grep -E '^r-zig'                    # all four _9
# conda (libmamba solver) and micromamba, through pixi exec
pixi exec -s conda -- conda create -y -p "$T/c" --override-channels -c https://prefix.dev/universe -c conda-forge 'r-zig-toolchain=4.6.1=*_8'
pixi exec -s conda -- conda install -y -p "$T/c" --override-channels -c "$CH_URL" -c https://prefix.dev/universe -c conda-forge 'r-zig-toolchain=4.6.1=*_9' 2>&1 | tee "$T/c.log"
pixi exec -s micromamba -- micromamba create -y -p "$T/m" -c https://prefix.dev/universe -c conda-forge 'r-zig-toolchain=4.6.1=*_8'
pixi exec -s micromamba -- micromamba install -y -p "$T/m" -c "$CH_URL" -c https://prefix.dev/universe -c conda-forge 'r-zig-toolchain=4.6.1=*_9' 2>&1 | tee "$T/m.log"
```

**kappa (win-64)** (Cc7):
- Write the same commands, without micromamba, into a script file, and
  run it over SSH as `bash <file>`. kappa's SSH shell is cmd, whose
  `%VAR%` expands at parse time.
- In Git Bash, MSYS converts POSIX paths in arguments but not in
  variables. So every path that pixi.exe or conda.exe reads from the
  environment, or as a URL, takes the `cygpath -m` form. A drive path
  needs `file:///`.

```sh
T=$(cygpath -m "$(mktemp -d)")
export PIXI_CACHE_DIR="$T/pixi-cache" CONDA_PKGS_DIRS="$T/pkgs"
CH=$(cygpath -m "$WT/dist/conda"); CH_URL="file:///$CH"
# then the pixi and conda lines above
```

The PowerShell alternative is not used. The phase 4 record says which
form ran.

Check each upgraded env:
- no "clobber" in the log (`grep -i clobber`), and no
  `<env>/__clobbers__`;
- the four packages at `_9` (`pixi list`, `conda list`,
  `micromamba list`);
- TC's files are exactly rzig's names (verify-helpers.sh:41-47), all the
  same bytes:
  - win-64 also has `binutils/` with its six tools, `SOURCES` and
    `LICENSES/`;
  - win-64 has no `as.exe ld.exe nm.exe dlltool.exe strip.exe
    windres.exe zig-cc zig-cxx` at TC's top level, and `ar.exe` compares
    equal to `gcc.exe`;
- `share/zig/rpkg/build_t1.zig` exists, and etc/Renviron (win:
  etc/Renviron.site) has no `R_ZIG_TOOLCHAIN_HINT`;
- `pixi run verify-tree -- <env>` passes (the checkout's task, run on
  the env);
- `<env's Rscript> recipe/test-toolchain.R` passes (pixi:
  `pixi run Rscript`; conda: `conda run -p`). It brings its own narrowed
  PATH (Cg9).

Pass means all of the above on every host and tool. A clobber or a
leftover file stops the merge. The fix is a recipe change (for example a
`run_constraints` entry on r-zig-slim that excludes r-zig-toolchain
`_8`), not a workaround in the env.

After the merge's publish (2026-10-19: the publish after phase 7's bump
and `CONDA_PUBLISH`, with that bump's number for `_9`):
- `conda-channel-list` shows the four `_9` files on all five subdirs.
- On one host, make a fresh env from universe only: no local channel,
  fresh caches, dist/conda removed first. `pixi add r-zig-toolchain` gets
  `_9`, and test-toolchain.R passes.
- feat-zig-pkg-build's N5 and fix-zig-pkg-build-review's "No
  build-number bump" already say that phase 4's bump publishes them. A
  closing note there adds "published as `_9`, <date>" (Cc19).

## 8. Tests per OS and CI

### What each scenario proves

| scenario | conda (recipe test and consume task; PATH = the env) | pip (wheel-test, PATH = the venv) | standalone (verify-bundle, unchanged) |
|---|---|---|---|
| package contents | `package_contents` per output: rzig and rpkg in r-zig-slim, no group directory; no `lib/R` in the group packages; win-64 r-zig-build-tools' binutils, SOURCES and LICENSES (Cc12) | — | the file-list checks |
| base alone | test-preflight.R: rzig and rpkg present, no group directory, no hint writer; R-only installs; compiled stops with `zig-cc: no zig (` naming r-zig-compilers; a configure script stops with both texts (H); the user's hint | the same test-preflight.R, run with the venv's Rscript (Cg10) | scenario 1 |
| base + compilers | test-compilers.R: no make on PATH; the check finds the env's zig and flang; C and plain-FLIBS Fortran tier 1 through rzig build (Cc10); a Makevars rule stops naming r-zig-build-tools; unix R CMD config names the build tools | + r-zig-compilers: tier 1 through the console script, the bundled bin/R and `python3 -m ziglang`; zig-fc no-flang; the Makevars rule stops | scenario 2 |
| base + build tools | test-build-tools.R: build-tools check ok; compilers check names r-zig-compilers; R CMD config CC (Cc1); I's "installed but not on PATH" line; win binutils records; nm with the env's zstd | (+ r-zig-build-tools after compilers: make on PATH, the Makevars rule builds) | — |
| everything | test-toolchain.R, with PATH narrowed to the env (Cg9) | + r-zig-toolchain; the metapackage alone in a second venv, `--no-index` (Cc5, Cc14) | scenario 3 |
| groups removed | — (removal is the package manager's; the upgrade test covers moved files) (Cg8) | uninstall: rzig stays and R is whole; then, with ziglang gone, test-preflight.R again | — |

The consume task (Cg8) runs the base-alone, base + compilers and base +
build tools rows through pixi's activation. On win-64 that is through
Rscript.bat.

### Per host

| host | runs |
|---|---|
| gamma (linux-64) | steps 1-4's chains (section 2); `rzig-test` with conda-forge zig and with upstream zig (`ZIG_BIN=$(pixi run fetch-zig)`); the default chain through `verify-package` with upstream zig; conda-package (four tests) and conda-consume; `verify-tree --` on an r-zig-slim alone env made by hand from `$CH`; the upgrade with pixi, conda and micromamba |
| omicron, osx-arm64 | `rzig-test`; `build` → `verify-package`; minimal `build`, `toolchain`, `verify-package`; `wheel`, `wheel-test`; conda-package and conda-consume; the upgrade with pixi; D7: `flang --version` in the default env |
| omicron, osx-64 (Rosetta, a copy re-solved for osx-64) | conda-package (four tests) and conda-consume |
| kappa (win-64) | `rzig-test`; `build` → `verify-package` (patches changed); conda-package (the build-tools test's binutils, SOURCES and zstd checks; test-toolchain.R with the narrowed PATH: the m2 list really checked, Cg9) and conda-consume (Rscript.bat); the upgrade with pixi and conda, through `bash <file>` (Cc7) |
| CI, the PR | the core tier, and conda-package: packaging's path filter matches recipe/, zigbuild/ and scripts/, so five conda legs run, with four tests and conda-consume each. Then `full-ci` (the four unix minimal legs run wheel-test), then `upstream-zig` (the patches changed). Optional: one stress dispatch with `distribution: conda`, `channel: local`, packages `g3 g4` on the five runners, which installs r-zig-slim + r-zig-toolchain from the PR's packages. Record each conda leg's time against ea7e6ee's (win-64: 15.5 min) (Cc11) |
| CI, main after merge | the publish (four files per subdir); the post-publish check in section 7 (2026-10-19: both after phase 7's bump and `CONDA_PUBLISH`) |

## 9. Risks

1. **The test env's PATH.** rattler-build's test env keeps the caller's
   PATH and variables (SC §3). windows-latest's PATH has C:\mingw64\bin
   and Git's usr\bin.
   - Every recipe test now narrows PATH, test-toolchain.R included
     (Cg9). Each resets the variables that change what it tests (Cc4,
     A3).
   - What remains: on unix the narrowed PATH is stricter than B25's
     promise, since the host userland is not on it. A unix failure from
     a missing host tool is a finding to record, not a reason to widen
     PATH past the env.
   - Later: drop the default feature from the pkg env (a lock change),
     which also shrinks CI's setup.
2. **Clobbering on the upgrade.** Source reading says there is none
   (section 7). The upgrade test, on three hosts with three tools, is the
   check before the publish. The publish cannot be undone, except by
   deleting `_9` files (scripts/prefix-delete-package.sh).
3. **A partial publish.** Each leg uploads its subdir's four files in one
   `rattler-build upload --skip-existing` call. If only some arrive, the
   exact pins keep every solvable combination consistent:
   - a r-zig-compilers `_9` without its r-zig-slim `_9` cannot be
     installed;
   - r-zig-slim `_9` alone has rzig;
   - `_8` pairs stay `_8`.
   A failed leg is re-run (ci-rerun-failed).
4. **Metapackages carry their test file** (`etc/conda/test-files/...`;
   r-zig-toolchain `_8` already does, SC §3). It is not a payload, and
   this is accepted. The `package_contents` checks are not `strict` for
   this reason (Cc12).
5. **N5's cache trap during development.** A rebuilt `_9` keeps its file
   name and changes its sha256 (pixi.toml:538-548).
   - conda-package empties dist/conda, so the index, and with it the
     sha256 a solve asks for, is fresh.
   - The upgrade test uses fresh caches.
   - After the publish, delete dist/conda before consuming universe's
     `_9`.
6. **conda-forge's zig 0.17.0** is on its main label (SC §0.7; read
   again here). r-zig-compilers' `zig 0.16.*`, and with K (a)
   r-zig-slim's constraint, keep a solved env on R's zig (Cc13, Cg14).
   The 0.17 wave (B18) bumps both.
7. **D7 can drift again.** The conda build solves zig fresh (`zig
   0.16.*`, `_20` today). The next zig 0.16 build changes what
   `zig cc --version` prints, while config.h keeps the old string.
   - This is a TODO "Later" item now (section 11) (Cg15): build.zig
     fills CC_VER/FC_VER from the zig and flang that build R, on every
     OS.
   - It already does this for Windows' COMPILED_BY (compiledBy,
     build.zig:1814-1816, 1903-1916).
8. **win-64's interim set.** m2's msys-2.0.dll can clash with a user's
   Rtools or Git for Windows (B11's risk). Phase 7 settles both channels.
   The native make is gone from it (Cg7).
9. **Wheel-test's host tools.** GitHub's runners have /usr/bin/make
   (Apple's 3.81 on macOS).
   - The boundary checks run with the venv's bin alone, or through
     test-preflight.R's own PATH.
   - No host zig can be reached there, so no skip is needed (Cc8, Cg11).
   - The second venv asserts the wheel's make by path (Cc5).
10. **pip leaves ziglang** after the groups are uninstalled, and
    Renviron.site's sibling ZIG_BIN still finds it (SP §13.6). So "R
    whole" and "base alone" differ by `pip uninstall ziglang`.
    wheel-test checks both, and the README says so.
11. **pip upgrades across the move.** A file that moves from one
    distribution to another between versions can be deleted when the old
    one is uninstalled. This is moot: none of the wheels is on PyPI
    (SP §1). Name squatting is the related risk, and `--no-index` keeps
    it out of the tests (Cc14). uv is not tested (PLAN.md's open
    question stays).
12. **No rzig is now an unexplained stop.** A damaged install without
    CC's binary gets "incomplete (see above)" with only sh's "not found"
    above it. No channel ships R without rzig after phase 4.
13. **pak, pkgbuild and `R CMD SHLIB` with r-zig-compilers alone** fail
    with their own messages, not rzig's (SR §12). On Windows, pkgbuild's
    message suggests Rtools.
    - H (a)'s "r-zig-toolchain installs every group" on every stop, and
      the README's one recommendation, steer users to the full set
      first (Cg1, Cg16).
    - Routing SHLIB through rzig build is a later item.
14. **Text churn.** H, I and J change rzig's texts, check.zig and 0009 in
    the same PR that first publishes them. Their tests are in section 3,
    and every grep of the old texts was checked (section 3, "Files that
    need no change").
15. **Packages built by `_8`'s toolchain** stay as they are. Nothing in
    phase 4 changes compiled code: rzig's compile logic is unchanged.

## 10. Overlap with other pending work

- **The stress dispatch 38467907779** (`--no-shared-cache`, A1) and a
  possible shared tier-1 build runner. That work is rzig
  (pkgbuild.zig) and rpkg, so the base. Phase 4 edits none of its files
  except 0013. Open point D, with the dispatch's numbers (Cg6).
- **B24's dlltool/as follow-up PR** (PLAN.md: "dlltool (with as) and
  windres can move in follow-up PRs"):
  - It adds new rzig names in installRzig and `rzig_names`, and changes
    Makeconf.win, check.zig's binutils list, test-toolchain.R,
    test-build-tools.R and the `package_contents` list.
  - Before phase 4: win-64 r-zig-build-tools' copies shrink ("less any
    tool rzig took over", PLAN.md phase 4).
  - After phase 4: its own PR and bump.
  - Textual overlap: installRzig's doc comment (phase 4) and its name
    list (B24).
- **fix-zig-pkg-build-review's later items.**
  - With J (a), 0009's exit 1 vs 127 is folded into phase 4 (Cg5).
  - Still later: 0010 for pkgbuild's probe, and `R CMD SHLIB` through
    rzig build.
  - Phase 4 changes the stop block of 0009 and the check line of 0010.
    Whoever comes second rebases on the other.
- **Phase 7** replaces phase 4's interim win-64 dependencies (the m2 list
  and pkg-config) with its choice for both channels. It also decides the
  `pkgconf` name (open point F), and native or m2 make (Cg7).
- **Phase 8** (B33): licences of the base's runtime files and the wheel's
  dist-info licences. Open point E touches only the packages' licence
  fields and r-zig-build-tools' licence file.
- **feat-wheel-minimal's open items**: wheel publishing (vendored licence
  texts, trusted publishing, the PyPI names: Cc14) and the
  libcurl→libpsl→ICU size call. These are not phase 4's. Phase 4 changes
  what would be published, not whether.
- **The zig 0.17 wave** (B18).
  - r-zig-compilers' `zig 0.16.*` and the flang `_6/_5/_10` pins hold
    it, and so does r-zig-slim's constraint with K (a).
  - universe's r-zig-toolchain `_4` (no flang pins) already resolves to
    flang-pixi's 0.17 builds (SC §4). A user must pin `_4` by hand to
    get it.

## 11. Records (step 5) and the stale references to fix

**PLAN.md: a "Phase 4 record".**
- What changed, and the choices and why:
  - the metapackage form;
  - the narrowed test PATH and the shared test header (Cc4, Cg9);
  - the consume task (Cg8);
  - the `package_contents` checks (Cc12);
  - the answers to section 12.
- The test results per host, the upgrade results (and on kappa, which
  form ran, Cc7), and the conda legs' times (Cc11).
- Recorded deviations and widenings:
  - E2 applied on every OS, and why (Cg18);
  - no native make on win-64, B28 (a)'s list (Cg7);
  - I-T11's third text (J);
  - H's both-groups stop, a refinement within B35 (one text per group,
    several groups per stop).
- The status line.
- **Risks:**
  - "rzig moving between conda packages" closes with the upgrade's
    result.
  - "Unpinned flang in the published `_4`" says the 0.17 builds now
    exist.
- **Open questions:**
  - "Can rattler-build 0.76.1 make an output with no files...?" Answer:
    not needed; phase 4 uses `inherit` + `files: []`, which rattler-build
    covers upstream (staging-empty-files.yaml, test_staging.py:443-454).
    The no-inherit form stays untested (SC §12 A) (Cc17).
  - "Which make wins on PATH in a win-64 conda env?" Answer: m2-make
    (SC §5). Phase 4 then drops the native one (Cg7).

**PLAN.md: the layered model's text** (Cg15).
- Section 5's table: drop "(today r-zig-toolchain)" from the rzig row.
- "Where PyPI differs": make-wheel.py:229-241 → 242-255.
- "What a user gets":
  - add a row for base + compilers, per feat-zig-pkg-build N2: tier 0-2
    installs without a configure script, but not SHLIB or pak;
  - the conda and PyPI "Compile" cells name r-zig-toolchain or the two
    groups.

**TODO.md.**
- Tick phase 4's boxes.
- Tick D12 (3510530).
- The zig 0.17 wave: "conda-forge's main label still 0.16.0" → 0.17.0
  since 2026-10-13 (Cg14).
- "Later" gains:
  - CC_VER/FC_VER computed by build.zig on every OS (D7's drift)
    (Cg15);
  - the four PyPI names, reserved or published with B12 (Cc14);
  - with J (b) only: "0009 tells the check's exit 1 from 127", the item
    fix-zig-pkg-build-review's follow-ups left to this file (Cg5);
  - with I (b) or (c): "an unactivated conda env's make" (Cg2).

**Other records.**
- fix-zig-pkg-build-review PLAN.md: I-T11's third text (J a).
- feat-zig-pkg-build N5 and fix-zig-pkg-build-review's line 13-14: the
  closing note "published as `_9`" after the publish (Cc19).
- stress/README.md:227: section 3 (Cc19).

**Stale line references** (SC §13, SP §13.12, SR §3), to fix in PLAN.md
and TODO.md:
- recipe.yaml:
  - the m2 list 410-442 / 414-442 → 470-502;
  - r-zig-toolchain's inherit/pin 396-409 → 455-469;
  - llvm-openmp 305 → host 270, run 355;
  - `number: 4` at 120 → `number: 8` at 151.
- pixi.toml: conda-publish 461-479 → 576-595.
- zig-build.sh's conda branch 57-66 → 56-65.
- make-wheel.py:
  - renviron_hint 244-250 → 258-264 (call 431-432);
  - the zig-cc check 364-365 → 385-386;
  - the ZIG_BIN default 229-241 → 242-255;
  - TOOLCHAIN_PREFIX 52 → 59;
  - ZIGLANG_REQUIREMENT 58 → 68;
  - Requires-Dist 333-334 → 351-352;
  - tags 404 → 439;
  - `--prefix` 350 → 368-369;
  - split 399-402 → 434-437.
- wheel-test.sh: "117 and 265-271" → 128 and 313-318.

## 12. Open points (need the user)

Each is a menu; ★ marks the recommendation the plan above is written
with.

**A. The group wheels' requirements.** B29 says "r-zig-compilers requires
ziglang" and "r-zig-toolchain requires both", and nothing about r-zig.
- (a) ★ Each group wheel requires `r-zig==<ver>` (r-zig-compilers also
  ziglang). r-zig-toolchain requires `r-zig-compilers==<ver>` and
  `r-zig-build-tools==<ver>`.
- (b) Only r-zig-build-tools requires r-zig. r-zig-compilers requires
  ziglang alone.
- (c) No r-zig requirement on the groups. r-zig-toolchain requires all
  three.
- Reason for (a): these are conda's exact pins (B28). r-zig-build-tools
  writes into `r_zig/R/`, so without its R it leaves a partial tree
  (SP §13.4).

**B. R_ZIG_TOOLCHAIN_HINT after phase 4.** B35 keeps it "only as a
user's override", and C8 has 0009 print it after rzig's text (Cg4).
- (a) 0009 and 0010 both print a set value as `hint: <value>`, on status
  127 only. 0010 gets a four-line shell block.
- (b) ★ 0009 only, as C8 decided, and on 127 only. 0010 keeps its one
  `|| exit`.
- (c) Drop the variable: no writer and no reader. This changes B35.
- Reason for (b): a site's "install the toolchain from X" after "the
  r-zig toolchain is complete" (exit 1) would contradict it. And (a)
  adds shell to 0010 for a variable nothing writes.

**C. 0013's no-rzig branches** (0013:63-81): "the r-zig toolchain is
older than this R", I-PF4's `R_ZIG_PKG_BUILDER=zig` stop, and the make
path. C8 covers only 0009 and 0010.
- (a) ★ Drop the "older than this R" stop. Keep I-PF4's stop and the
  make path.
- (b) Keep all three as defensive code. 0013 is regenerated either way.
- (c) Drop all three: no rzig means the make path, silently.
- Reason for (a): its only cause was a new r-zig-slim beside an old
  r-zig-toolchain (N5). That cannot happen once every channel ships rzig
  with 0013 and the pins forbid the mix. I-PF4 is a decided interface.

**D. A shared tier-1 build runner**, asked with the `--no-shared-cache`
dispatch's numbers (Cg6, A1).
- What `_9` does: it is the first build that makes rzig build the
  default tier-1 path for every conda user, with N3's per-install cache.
- The dispatch's numbers (38467907779, g3 g4, `--trace`, jobs 4; four
  of five legs, read here; macos-15-intel still running). Per leg: the
  tier-1 rows' minimum and median, against the make rows' minimum.

  | leg | tier-1 min | tier-1 median | make min |
  |---|---|---|---|
  | ubuntu-latest (n=16) | 4 s | 9 s | 1 s |
  | ubuntu-24.04-arm (n=16) | 12 s | 16 s | 1 s |
  | macos-latest (n=16) | 9 s | 16 s | 2 s |
  | windows-latest (n=17) | 14 s | 19 s | 2 s |

  - The tier-1 minimum is the smallest packages' floor, so it is a rough
    per-install cost. It matches TODO's estimate: about 3 s on linux-64,
    6-10 s on omicron, 11-20 s on kappa.
  - "Unexpected: 0" on every leg: each failure matches its `expect`
    column. The failures are magick's `fail-abi` on both linux legs, and
    Windows' 8 rows (package, upstream, abi and sysdep).
- (a) ★ Phase 4 does not wait. The runner is its own PR after phase 4,
  with its own bump (`_10`; B14 a).
- (b) The runner lands first, and phase 4's bump publishes both.
- (c) The runner goes into phase 4's PR.
- Reason for (a): `_9` is what publishes phase 3, PR #25/#26 and the
  split. The cost is the known, bounded per-install floor above. A
  runner is an rzig/rpkg design that is not chosen yet, and small PRs
  keep the upgrade test focused (B37 a).

**E. The licence fields, on both channels** (Cc15, Cg13). Today:
- every conda output inherits `GPL-2.0-or-later`, including win-64's
  GNU binutils copies (GPL-3.0-or-later);
- every wheel says `GPL-2.0-only OR GPL-3.0-only`, including make's
  wheel.

Options:
- (a) ★ A package or wheel that holds third-party files states their
  licence:
  - pip r-zig-build-tools: `GPL-3.0-or-later` and make's COPYING;
  - conda's win-64 r-zig-build-tools: binutils' `GPL-3.0-or-later`.

  The base and the empty packages say R's own `GPL-2.0-only OR
  GPL-3.0-only` on both channels, as the wheel already does.
- (b) As (a), but r-zig-slim and the conda metapackages keep
  `GPL-2.0-or-later` until phase 8.
- (c) R's licence everywhere until phase 8 (B33), recorded as a known
  mismatch.
- Reason for (a): nothing that carries these fields is published yet in
  this form (`_9`, unpublished wheels). So making them true and the same
  on both channels costs a few lines now (G4).

**F. The `pkgconf` name on conda's win-64.** B39's note gives the
pkg-config in `usr/bin/` a second name, `pkgconf`, for s2's
Makevars.win. conda-forge's win-64 pkg-config ships only
pkg-config.exe, and pkgconf ships only pkgconf.exe (SC §5).
- (a) ★ pkg-config only now, as PLAN.md's phase 4 says ("today's m2 list
  plus pkg-config"). Phase 7 adds the second name on both channels, with
  its package choice.
- (b) Both pkg-config and pkgconf now. pkgconf adds pkgconf-8.dll and
  three more tools to the env.
- Reason for (a): phase 7 chooses the set again anyway. s2's Windows
  build has other open problems (the WinRT headers when it builds its
  bundled abseil).

**G. Where the upgrade test runs.**
- (a) ★ By hand, once, before merging, on gamma (pixi, conda,
  micromamba), kappa (pixi, conda) and omicron (pixi), recorded in
  PLAN.md.
- (b) Also a CI step on the PR (five legs, pixi only), removed after the
  publish.
- Reason for (a): the files move once, `_8` → `_9`. Later bumps move
  nothing between packages.

**H. What rzig says when more than one group is missing** (Cg1).
- (a) ★ Two changes:
  - `--rzig-check=package` reports every missing group the package needs
    in one stop: both texts, compilers first, one exit 127.
  - Each conda and pip line ends "; r-zig-toolchain installs every
    group".
- (b) Only the package-mode change.
- (c) As the planner had it: one group per stop, and the advice in the
  README.
- Reason for (a): the stop a user meets then names everything they
  need, in one round. It gives the same recommendation as the README and
  the package descriptions (Cg16). pak and SHLIB, which print no rzig
  text, are best served by installing r-zig-toolchain from the start.

**I. Build tools installed but not on PATH** (an unactivated conda env)
(Cg2).
- (a) ★ rzig's missing line says the tool is installed in R's
  environment and to activate it, or to start R with pixi run. The group
  text follows. Finding make stays PATH's (B34's note).
- (b) As the planner had it, plus a README line.
- (c) Make it work instead of explaining it: unix r-zig-build-tools
  links `TC/usr/bin/make` to the env's make, so B25's PATH line finds it.
  This changes B28's "no files" and covers unix only.
- Reason for (a): phase 4 is when the text first names
  r-zig-build-tools. Without (a), an IDE user is told to install what
  they have. (a) is a few lines in check.zig and the same on every OS.

**J. 0009's exit 1 vs 127** (Cg5): fix-zig-pkg-build-review's follow-up,
which is in no TODO today.
- (a) ★ Fold it into phase 4. 0009 says "...which is incomplete (see
  above)" only on 127, and "this package cannot be built (see above)" on
  any other status (the review's option c). I-T11 gets a third text, and
  stress.R's classifier learns it.
- (b) Keep it for later, and add the TODO item.
- Reason for (a): phase 4 already rewrites that block, regenerates 0009
  and 0013, and rebuilds on every host. `_9` is the first publish of
  these stops. Doing it later costs a second patch round.

**K. r-zig-slim constrains zig** (Cc13, Cg14). conda-forge's main label
has zig 0.17.0 since 2026-10-13.
- (a) ★ `run_constraints: [zig 0.16.*]` on r-zig-slim. It is bumped with
  r-zig-compilers' pins in the 0.17 wave. A user's unpinned `pixi add zig`
  beside R then solves to R's zig.
- (b) As the planner had it: rzig's version stop explains it at the
  first compile (B32).
- Reason for (a): rzig now finds the env's zig first (B34). A 0.17 there
  breaks every compile, so solve time is the earliest and clearest place
  to stop it. The cost: an env with r-zig-slim cannot also hold zig 0.17
  for something else.

**L. The README's "currently private"** (Cg17). universe's repodata reads
without auth, but the sentence states an intent.
- (a) ★ Say the channel is public: `pixi workspace channel add
  https://prefix.dev/universe`, no login.
- (b) Keep "private" and the login line until the user publishes an
  announcement.
- Reason for (a): the README's own install lines need the channel to be
  readable, and it is (read here without credentials).
