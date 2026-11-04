# Phase 5 implementation plan — zig in the compilers group

The planner's plan of 2026-10-15, amended by the amender (read-only) the
same day after two critiques: `phase5/critique-code.md` (code
correctness, findings tagged **(Cc1)**..**(Cc11)**) and
`phase5/critique-goals.md` (the user's goals and decisions, tagged
**(Cg1)**..**(Cg10)**). Each amendment carries its tag where it lands;
`phase5/critic/CRITIQUE.md` lists every point, the check made against
the worktree, and whether it was accepted, accepted in part or rejected.
Read-only work: nothing in the worktree changed, nothing was built or
installed. Where an open point (section 11) offers options, the plan is
written with its recommended option, and the user's instruction for
this run ("Start phase 5", after "Follow with the recommended") answers
every open point that way: each is recorded as answered with its ★
option, the menu kept for the record. The amendments add open points S
and T (section 11), answered the same way. Format as
phase4/PHASE4-IMPLEMENTATION.md.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 5 keeps build 8, as phase 4, SHLIB routing and phase 6
do, and main publishes nothing until the user sets the repository
variable `CONDA_PUBLISH` after phase 7's bump merges (PLAN.md, B14's
amendment). Where this plan says phase 5 takes 11 (or names phase 4's 9
and SHLIB's 10), read: the number stays 8, and phase 5 publishes with
phase 7's bump, at the number after universe's newest (B14 a).

Sources:
- The worktree `wt/feat-standalone-phase5`, branch feat-standalone-phase5:
  main d11dee1 (PR #27, the shared build runner, merged) plus phase 4's
  and the R CMD SHLIB routing's uncommitted changes.
  - Baselines: `wt/phase4-base.diff` (main → phase 4, `number: 8 → 9`)
    and `wt/shlib-base.diff` (main → phase 4 + SHLIB, cumulative,
    `number: 8 → 10`), plus their untracked files (git status: 53
    modified, 5 untracked; 58 entries).
  - Line numbers are this worktree's. When implementing, cite the
    function, not the line.
  - pixi.lock sha256 starts with fbb64b7ba4e31e45. Phase 5 changes no
    dependency: the lock and pixi.toml's dependency tables stay as they
    are.
- feat-standalone-toolchain PLAN.md ("### Phase 5 — zig in the compilers
  group", Verification, Risks, "Later and future checks") and TODO.md
  ("## Phase 5"). Decisions: B2, B4, B6, B13, B14, B17, B18, B30, B32,
  B34, B35, B40, C12, D6; the phase 2, 3 and 4 records.
- fix-rzig-follow-ups PLAN.md "D6: -lsynchronization links with upstream
  zig" (PR #19, merged 7a3004d).
- feat-shared-build-runner PLAN.md (PR #27): the runner key.
- feat-shlib-rzig-build PLAN.md: build number 10, and its note that it
  and phase 5 share verify-bundle.sh, so they do not run in parallel.
- The three surveys, cited by section:
  - survey-tree.md (ST): the tree, the archives, sizes, CI;
  - survey-rzig.md (SR): rzig with a zig in TC/zig;
  - survey-records.md (SD): the records, the decisions and the open
    points P5-A..P5-L.
  Their scratch is in `phase5/surveyor-{tree,rzig,records}/` (the five
  pinned wheels' zig binaries, sizes.tsv, PyPI's and ziglang.org's JSON).
- Read again here (2026-10-15): the unpacked linux-64 wheel in the main
  checkout's `build/zig-upstream/ziglang-0.16.0-linux-64/`: METADATA
  (`Version: 0.16.0`, `License-Expression: MIT`, `Project-URL: Source
  Code, https://github.com/ziglang/zig-pypi`), WHEEL (`Tag:` lines),
  RECORD (19,565 lines, `<path>,sha256=<urlsafe base64, no
  padding>,<size>`; its own line `...RECORD,,`); zig 0.16's std.Build
  has `addFail` and `addInstallDirectory` (Build.zig:1107, 1726).

TC is `R_HOME/bin/toolchain` (unix `lib/R/bin/toolchain`, Windows
`Library/lib/R/bin/toolchain`). "The tree" is the toolchain tree,
`dist/toolchain/R-<ver>-zig` (B30, B36). Decision IDs are PLAN.md's.
This plan's open points are letters (section 11).

## 0. What phase 5 delivers

- **The toolchain tree gets `TC/zig/`**: upstream zig, ziglang.org's
  build as PyPI's ziglang 0.16.0 wheel carries it, the wheel fetch-zig
  already pins per platform (B4 a, B18 a).
  - `zig/zig` (`zig/zig.exe`) and `zig/lib/` (19,541 files), as the
    wheel's `ziglang/` has them; `__init__.py`, `__main__.py`,
    README.md and the top LICENSE file are left out (B4).
  - `zig/LICENSES/ziglang/`: the wheel's `dist-info/licenses/ziglang/`,
    15 files (zig's MIT LICENSE, libc++/libc++abi/libunwind, the libc
    notices) (open point C).
  - `zig/SOURCES`: one `package: ziglang` block in the shape conda's
    blocks have, so verify-toolchain stays one checker: the wheel's URL
    and sha256, its tag, MIT, a `source:` line (ziglang.org's
    zig-0.16.0.tar.xz and its sha256), a `feedstock:` line (zig-pypi),
    and one `file:` line per copy with the wheel's own sha256 from its
    RECORD (open point B).
  - Made by the toolchain build (zigbuild/toolchain/build.zig) from the
    directory fetch-zig unpacks, which zig-toolchain.sh passes as
    `-Dziglang=<dir>` (open point A). The rules live in build.zig and a
    new `zigbuild/toolchain/wheel.zig`; bash only downloads.
- **The standalone compilers archive brings zig**:
  `R-<ver>-<plat>-compilers.tar.gz` (Windows `.zip`) grows from about
  32 KB to 84-100 MB (ST §2). package-standalone.sh, unpack-toolchain.sh
  and verify-bundle's list checks already accept `zig/`: env.sh's
  `group_dirs compilers` is `zig flang openmp`.
- **rzig finds it with no change to its lookup**: ZIG_BIN, then
  `<rzig dir>/zig/zig`, then R's environment's bin, PATH, `python3 -m
  ziglang` (B2 a, B34 a; find_zig.zig `find`, since phase 2). The check
  mode now compares the compilers archive's zig with the base's rzig
  (B32): both 0.16, so base and compilers from one release pass.
- **rzig's text** (B35): the compilers group's standalone line names the
  archive for zig and the OpenMP files, and flang on PATH until phase 6
  (open point H). This is the one rzig change, so conda and PyPI
  contents change (r-zig-slim and the r-zig wheel carry rzig): build
  number 10 → **11** (B14 a; open point M).
- **verify-toolchain scales to 19.5k files**: the records and copies
  checks, the build-path scan and the binary detection run in batch
  (open point D). It also checks that `zig/zig version` prints the
  version SOURCES records.
- **verify-bundle tests the user's zig**: by default every scenario runs
  with ZIG_BIN unset, so rzig takes `TC/zig/zig`, with zig's cache under
  the fresh HOME (a new user's). Then the same script runs once more
  with `ZIG_BIN=$ZIG` and env.sh's cache, the fourth pass that keeps
  conda-forge's zig's package coverage (PLAN step 5; open points F, G).
  - On the default legs that is the mixed case (R by conda-forge's zig,
    packages by upstream zig) and then conda-forge's zig; on the
    upstream legs the one-zig case, where the fourth pass is skipped
    because `$ZIG` has TC/zig's bytes (B6 a).
  - New: the first C++ compile with an empty zig cache, timed (the
    measurement "Later: zig's global cache" asks for); on Windows a
    package linking `-lsynchronization` builds and loads with TC/zig
    (D6); the no-zig preflight check moves `TC/zig/zig` aside (open
    point E; the binary only, (Cc8)); one RZIG_PRINT_ARGV assertion of
    the zig on every OS (TODO's box, (Cg4)).
- **D6 is already done**: PR #19 maps `-lsynchronization` to
  `api-ms-win-core-synch-l1-2-0` for both zigs (windows.zig
  `mingw_names`). Phase 5 only adds the package test above and corrects
  the PLAN and TODO wording (a rename, not a generated import library).
- **Recorded**: archive sizes per OS (B13 a: no format change), the
  first C++ compile's time per OS, verify-toolchain's and verify-package's
  times, and the mixed-case notes (CC_VER, ZIG_LIB_DIR, a build runner
  per extraction place).

Not in phase 5:
- conda and PyPI get no `TC/zig` (B30, B28/B29, point 5): conda keeps
  conda-forge's zig through r-zig-compilers, PyPI keeps ziglang. The
  conda build runs the toolchain build into its env, which installs no
  zig and fetches nothing (open point J). make-wheel.py takes only
  `usr/` from the tree.
- Dev compiles keep the zig that built R: compile-tree.sh leaves `zig/`
  and `flang/` out (C12), so contract, pkg-parity and stress do not use
  TC/zig.
- flang in `TC/flang/` (phase 6), Windows' `usr/bin` (phase 7), the
  base's runtime records (phase 8).
- zig 0.17 (B18 a): TC/zig stays 0.16.0 until a release is built with
  0.17.
- Pre-seeding zig's global cache: phase 5 measures, a later menu decides
  ("Later and future checks").
- Leaving zig/ out of the legs that never use it (build-r's build-only
  legs, stress, the local dev chains, which all download or fetch it):
  recorded with timings, a later menu (Cg6).
- upstream-zig.yaml reusing build.yaml's toolchain artifact (the two
  carry the same TC/zig once phase 5 lands): recorded, a later menu
  (Cg9).
- Compression (B13 a): sizes only; the format comes back after phase 6.

## 1. Sequencing and preconditions

- **Stacked on two uncommitted branches.** This worktree is main d11dee1
  + phase 4 (build 9) + SHLIB routing (build 10), neither committed. The
  phase 4 worktree (`.claude/worktrees/feat-standalone-phase4`) and the
  SHLIB worktree (`wt/feat-shlib-rzig-build`) are not touched.
  - Phase 5 edits files both baselines edit: verify-bundle.sh (SHLIB's
    largest file), groups.zig and parity-test.sh (phase 4),
    recipe/recipe.yaml (the number), README.md, PLAN.md and TODO.md.
    Phase 5's own diff is therefore against the SHLIB baseline, never
    against main (open point O).
  - At the start the implementer records, in `phase5/implementer/`:
    `git diff | sha256sum`, `git status --short`, and the sha256 of
    each untracked baseline file. These are the baseline the final
    `phase5-only.diff` is made against (step 6).
  - Merge order: phase 4's PR, then SHLIB's, then phase 5's. If the user
    folds them differently, the build number follows (open point M).
- **universe holds `_8` and nothing newer** (SD §4, 2026-10-15). Phase
  4's 9 and SHLIB's 10 are unpublished. Phase 5 takes 11. Check again
  with `pixi run -e pkg conda-channel-list universe <subdir>` before
  merging.
- **Prerequisites are on main**: #14 (baseline CPU), #15, #16 (the
  re-lock), #19 (D6), #27 (the shared build runner) (SD §2).
- **Network**: `pixi run toolchain` now downloads the wheel once per
  platform (about 95-101 MB, cached in `build/zig-upstream/`). A host
  that ran fetch-zig before has an empty `.complete` marker; the new
  fetch-zig fetches once more (step 2).
- **Disk**: each host gains about 400 MB in `build/zig-upstream/`,
  400 MB in `dist/toolchain/`, 100 MB per compilers archive, and up to
  400 MB per verify-bundle pass under TMPDIR. The passes run one at a
  time only because the toolchain pass removes its own VERIFY_DIR before
  it execs the build pass (section 3, (Cc4)); without that the two
  directories coexist (about 800 MB). publish-preflight's 20 GB floor
  covers it; check it before the conda chains.
- **Ownership** (parallel testers): one owner per host; gamma's owner
  owns `dist/` and the builds there; remote testers own their hosts; no
  one writes pixi.lock; each records the lock's sha256 and the
  worktree's `git diff | sha256sum` at the start and the end; scratch
  and TMPDIR under `phase5/<role>/`. omicron's osx-64 copy (re-solved
  for osx-64 under Rosetta) and its lock live only in the tester's
  scratch and are never synced back; the worktree's pixi.lock sha256
  (fbb64b7ba4e31e45...) is recorded before and after that run (Cg10).
- **The network**: `pixi run toolchain` now reaches PyPI once per
  platform on every host and leg that runs it, including the dev chains
  (contract, pkg-parity, stress) that never read zig/; README's dev
  notes say so (Cg6).

## 2. Steps

Each step is a local checkpoint that leaves every test it names green.
CI sees only the PR's final state. verify-package is named from step 4
on: once the compilers archive holds zig (step 2), today's
verify-bundle's last check (no zig with both groups) cannot pass until
step 4 changes it.

1. **verify-toolchain in batch** (open point D), on today's tree.
   - Changes: scripts/verify-toolchain.sh (section 3): the records and
     copies check as one hashing pass and one join; the build-path scan
     as one `xargs grep -l`; the closure checks' binary detection by
     one `xargs grep -l` of the magic numbers, then today's exact check
     on those only; the wording "third-party copies".
   - Done first so that step 2's 19.5k files never meet the per-file
     loop (ST §1: about 345 s on linux, unknown and likely over the
     30-minute CI timeout on MSYS).
   - Tests:
     - `bash -n scripts/verify-toolchain.sh`.
     - `pixi run toolchain && pixi run verify-toolchain` on today's tree
       (openmp/, usr/; Windows binutils/): the same "== ... verified"
       lines and counts as before the change.
     - Negative cases, by hand on a copy of the tree under
       `phase5/implementer/` (`verify-toolchain.sh <copy>`): a changed
       copy (sha256 mismatch), a deleted copy (in SOURCES, missing), a
       stray file (no file line), a SOURCES line with 4 fields (not a
       file line), a package block with no `feedstock:`, a copy that
       names the checkout (listed, not failed), a LICENSES file that
       names `$HOME` (fails), a SOURCES with no `file:` lines at all
       (every copy "no file line in SOURCES", (Cc6)), a stray file named
       `SOURCES` in a subdirectory (no file line, (Cc6)). Each gives
       today's message.
     - Positive cases, explicit (Cc2): a clean tree in which no copy
       names a build path and (macOS: no) binary is absent from no
       directory passes every block and prints the "verified" lines;
       a directory with no binary passes the closures block with
       `0 ... files`. Under `set -euo pipefail`, a batched grep that
       matches nothing must not stop the script silently.
     - The binary count (Cg8): `n_bin` after the change equals today's
       per-file count on today's tree, on gamma (GNU grep and xargs),
       omicron (BSD grep and xargs) and kappa (MSYS), before CI; after
       step 2 the list of candidates includes `zig/zig` (Windows
       `zig/zig.exe`, by the name filter) on every OS.
     - Both zigs (`ZIG_BIN="$(pixi run fetch-zig)"` for the second).
     - Steps 1 and 2 together are over ~200 lines (verify-toolchain,
       wheel.zig, build.zig): the skeptical diff review before step 2's
       tests too (Cg8): Windows paths and `\` in sha256sum's output, the
       quoting of `find`/`xargs` lists, every `|| true` and `[ -s ]`
       guard, nothing dropped from today's checks.
2. **`TC/zig/` in the toolchain tree** (B4; open points A, B, C, J).
   - Changes:
     - scripts/fetch-zig.sh: the source tarball's pin beside the
       version; `.complete` holds the wheel's URL, its sha256 and the
       source line, and an empty marker fetches again.
     - scripts/zig-toolchain.sh: runs fetch-zig (not for `test`, not
       when the prefix is the env, by real path: build.zig's rule,
       (Cc1)/(Cg7)) and passes `-Dziglang=<dir>`.
     - scripts/env.sh: `same_dir`, vendor-libs.sh's `resolved()` test
       moved here so zig-toolchain.sh and vendor-libs.sh share it
       (Cc1); scripts/vendor-libs.sh calls it.
     - zigbuild/toolchain/wheel.zig (new): the marker, METADATA and
       RECORD readers, pure, with unit tests.
     - zigbuild/toolchain/build.zig: the `ziglang` option; `zig/`,
       `zig/LICENSES/ziglang/` and `zig/SOURCES`; nothing when the
       prefix is the env; an `addFail` step when the option is missing;
       the header comment; the test step runs wheel.zig's tests too.
     - scripts/verify-toolchain.sh: `zig/zig` must exist and print
       SOURCES' ziglang version.
   - Tests:
     - `zig fmt --check zigbuild/toolchain/`; `bash -n` on both scripts.
     - `pixi run toolchain-test` with both zigs: wheel.zig's tests
       run, and the log has no "fetch-zig:" line (no download).
     - `pixi run toolchain` with both zigs: the summary line names
       `zig/ (ziglang)`; `pixi run verify-toolchain` passes and prints
       the zig line and its time (record it).
     - `cmp` of `TC/zig/zig` with fetch-zig's `ziglang/zig`; `diff -r`
       of `TC/zig/lib` with `ziglang/lib` (no difference);
       `TC/zig/zig version` = 0.16.0; `TC/zig/zig env` names
       `TC/zig/lib` as its lib dir.
     - A marker from the old fetch-zig (an empty `.complete`): the next
       `pixi run toolchain` downloads again and writes the new marker.
     - `pixi run package-toolchain`: the compilers archive's size and
       member count (record); `pixi run unpack-toolchain` into a fresh
       `dist/toolchain` and verify-toolchain again (the tree from the
       archives).
     - The conda path, without touching the dev env: in step 5's
       `pixi run -e pkg conda-package`, the build log's toolchain line
       ends "(the prefix is the env)" and names no `zig/`, the log has
       no "fetch-zig:" line, and every package's `package_contents`
       check passes (none holds `bin/toolchain/zig`).
     - A non-env override (Cc1): `R_TOOLCHAIN_PREFIX=<scratch>/R-4.6.1-zig
       pixi run toolchain` fetches, installs zig/ there, and
       `verify-toolchain.sh <scratch>/R-4.6.1-zig` passes; with
       `R_TOOLCHAIN_PREFIX="$CONDA_PREFIX"` spelled differently (a
       trailing `/`, a symlinked path on unix) it is still "the env":
       no fetch line and no zig/ (bash and build.zig agree).
     - vendor-libs.sh after the helper move: `pixi run build`'s
       vendor-libs line unchanged; the conda build's vendor-libs still
       exits early (prefix is the env).
     - `pixi run compile-tree`, then `contract`: unchanged, the compile
       tree has no `zig/` (C12).
3. **rzig's standalone compilers line** (B35; open point H).
   (Then, before step 4 on gamma finishes and before any of step 5's
   chains, kappa runs step 3b.)
   - Changes: zigbuild/tools/rzig/groups.zig (the line, the header
     comment, the two expected texts in its test);
     zigbuild/tools/rzig/parity-test.sh's anchored grep.
   - Tests:
     - `zig fmt --check zigbuild/tools/rzig/`.
     - `pixi run rzig-test` with conda-forge's zig and with upstream zig
       (unit tests, parity-test.sh on linux).
     - `git grep -n 'on PATH or in ZIG_BIN' -- ':!.github/devdocs'`
       finds nothing; `git grep -n 'LLVM flang on PATH'` still finds
       groups.zig, parity-test.sh, wheel-test.sh, make-wheel.py and
       python/r_zig/__init__.py.
3b. **kappa early: `-lmsvcrt` with TC/zig** (open point L; (Cg3)).
   - As soon as step 2's tree and step 3's rzig exist: kappa builds R
     with this worktree's state (`build`, `toolchain`, `package`,
     `package-toolchain`), extracts base + both groups into a scratch
     directory, and with ZIG_BIN unset runs `install.packages("magick")`
     under the bundle's R (its librsvg holds Rust's std), and one Rust
     package if cargo is on the host.
   - If a package fails on `-lmsvcrt`, open point L's (b) applies:
     step 3 grows the `mingw_names` mapping (`msvcrt` → `c`, unit test in
     windows.zig), `rzig-test` with both zigs again, and only then does
     step 5 run, once. The build number stays 11.
   - If nothing fails, L stays (a), recorded with the packages tried.
4. **verify-bundle with TC/zig** (PLAN steps 3-5; open points E, F, G,
   Q, S; D6's test).
   - Changes: scripts/verify-bundle.sh (section 3): the pass argument
     (`toolchain`, the default, and `build`), the zig each pass runs and
     asserts, the first C++ compile timed, the baseline-CPU compiles
     under env -i, Windows' `-lsynchronization` package, the no-zig
     check with `TC/zig/zig` moved aside (Cc8), the argv assertion on
     every OS (Cg4), the fourth pass started at the end after the first
     pass's VERIFY_DIR is gone (Cc4), the zig-independent blocks only in
     the toolchain pass (open point S, (Cg1)), and the comments.
   - Over 200 changed lines: before the tests, a skeptical diff review
     (Windows paths: `cygpath -m -l` and the `zig\zig.exe` spelling;
     `pwd -P` on unix; quoting of the arrays; every `$ZIG` and
     `$zig_bin` site; no cache variable leaking into the toolchain
     pass; nothing dropped from SHLIB's blocks).
   - Tests (gamma):
     - `bash -n scripts/verify-bundle.sh`.
     - default env, conda-forge's zig: `build`, `package-toolchain`,
       `verify-package`. Both passes run: the toolchain pass (mixed
       case) asserts `TC/zig/zig` everywhere and prints the first C++
       compile's time; the build pass asserts `$ZIG`. The log's last
       "verified" line names the build pass; the first pass's VERIFY_DIR
       is gone while the build pass runs (`ls` of TMPDIR). Each pass's
       wall time recorded (Cg1).
     - In the skeptical review (Cc3): every hit of `grep -n
       '"\$cc"\|"\$fc"\|"\$pass_zig"\|"\$ZIG"' scripts/verify-bundle.sh`
       is either under `env -i "${base_env[@]}"` or an RZIG_PRINT_ARGV
       dry run (which runs no zig), a `version` call or a `-x`/`cmp` test;
       the baseline-CPU block's three
       compiles are under one env -i.
     - upstream zig: `export ZIG_BIN="$(pixi run fetch-zig)"`, then
       `build`, `toolchain`, `package-toolchain`, `verify-package`: the
       toolchain pass (one-zig case); the build pass is skipped with its
       note (same bytes).
     - minimal: `pixi run -e minimal build && pixi run -e minimal
       verify-package` (no OpenMP; openmp/ left alone, B40).
5. **Docs, comments, build number, the other channels** (open point M).
   - Changes: README.md; scripts/env.sh, scripts/compile-tree.sh and
     zigbuild/toolchain/build.zig comments; .github/workflows/
     toolchain.yaml's header comment; pixi.toml's fetch-zig and
     toolchain comments (comments only, no table changes);
     recipe/recipe.yaml `number: 11` with its history line.
   - Tests:
     - After the pixi.toml comment edit (Cg10): `sha256sum pixi.lock`
       still starts with fbb64b7ba4e31e45 and `pixi lock --check`
       passes (it writes nothing).
     - actionlint on toolchain.yaml.
     - `pixi run -e pkg conda-package` (four tests, both `--error-*`
       flags), then `pixi run -e pkg conda-consume`: rzig changed, and
       the conda build must neither fetch nor install zig (step 2's
       conda checks).
     - `pixi run -e minimal build`, `-e minimal toolchain`, `-e wheel
       wheel`, `-e wheel wheel-test`: wheel-test greps "LLVM flang on
       PATH" and the pip line, both unchanged.
     - The default chain once more end to end (PLAN's Verification
       block): `rzig-test`, `toolchain-test`, `build`, `toolchain`,
       `verify-tree`, `verify-toolchain`, `smoke`, `contract`,
       `hermetic`, `pkg-parity`, `package-toolchain`, `verify-package`.
6. **Other hosts, CI, the records, the hand-over.**
   - omicron (osx-arm64; osx-64 under Rosetta, open point K), kappa
     (win-64; `-lmsvcrt`'s check already ran in step 3b, open point L),
     CI (section 6).
   - The measurements (section 7) into PLAN.md's phase 5 record; the
     records and stale references (section 10).
   - `phase5/implementer/phase5-only.diff`, made against the step-0
     baseline (open point O), and the commit commands for the user,
     with no trailer and no session link.

## 3. Per file: the exact change

### scripts/fetch-zig.sh (step 2; open point A)

- Beside `version=0.16.0`, the source the wheel's zig is built from,
  one pin per version, not per platform (SD §4; ziglang.org's
  index.json, read by ST):

  ```bash
  # The source of this zig, for the toolchain tree's SOURCES (zig/, B4):
  # ziglang.org's release tarball, which the wheels' zig is built from.
  src_url=https://ziglang.org/download/$version/zig-$version.tar.xz
  src_sha=43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf
  ```

- The marker carries what the wheel's own files cannot say: where it
  came from. Today it is empty and the .whl is deleted (fetch-zig.sh
  `: > "$dir/.complete"`), so the URL and sha256 exist only in the case
  table. The test becomes `-s` (non-empty), so a marker from the old
  script fetches again:

  ```bash
  if ! [ -s "$dir/.complete" ] || ! [ -f "$zig" ]; then
    ...
    printf 'url: %s\nsha256: %s\nsource: %s sha256:%s\n' \
      "https://files.pythonhosted.org/packages/$path/$whl" "$sha" "$src_url" "$src_sha" > "$dir/.complete"
  fi
  ```

  The URL is built once into a variable and used by both the `curl` and
  the marker. The `source:` line has SOURCES' own form (conda.zig
  `writeUpstream`); wheel.zig parses it into one `conda.Source{ .url,
  .sha256 }`, which writeSources writes back (Cc10: not copied as text,
  so one writer makes every `source:` line).
- The header comment gains one sentence: the toolchain build installs
  this zig into the toolchain tree's `zig/` (zig-toolchain.sh), and the
  marker records the wheel's URL, sha256 and source for its SOURCES.
- Unchanged: the five pins, the sha256 check, `unset ZIG_BIN`, the
  printed path (C:/... on Windows). fetch-zig runs as its own `bash`
  process, so its `unset ZIG_BIN` never reaches zig-toolchain.sh (SD
  P5-A's note).

### scripts/zig-toolchain.sh (step 2; open points A, J)

- After the `"$ZIG" version` check and before `rm -rf`:

  ```bash
  # The compilers group's zig/ (B4, phase 5): PyPI's ziglang wheel as
  # fetch-zig pins and unpacks it, whose directory the build reads. Not
  # for the unit tests, and not when the prefix is the env (the conda
  # build, recipe/build.sh): conda keeps conda-forge's zig (B30) and its
  # build reaches no PyPI. build.zig decides what is installed
  # (prefix_is_env, the same test by real path); this only decides
  # whether to download, so the two must agree.
  ziglang=()
  if [ "${1:-}" != test ] && ! same_dir "$TOOLCHAIN_PREFIX" "${CONDA_PREFIX:-}"; then
    zig_path="$(bash "$ROOT/scripts/fetch-zig.sh")"
    ziglang=("-Dziglang=$(dirname "$(dirname "$zig_path")")")
    echo "r-zig: the toolchain's zig/ from ${ziglang[0]#-Dziglang=}"
  fi
  ```

  and the build line passes `"${ziglang[@]}"` before `"$@"`. (Cc1,
  Cg7) The condition is build.zig's `prefix_is_env`, not the `rm -rf`'s
  "R_TOOLCHAIN_PREFIX is set": R_TOOLCHAIN_PREFIX is a general override
  (env.sh, package-standalone.sh, unpack-toolchain.sh), and with the
  `rm -rf`'s test a non-env override would get no `-Dziglang` and stop
  in build.zig's addFail step, whose message tells the user to run what
  they just ran. The `rm -rf` guard stays as it is (it is about deleting
  a tree, not about zig). The env's bash is 5.2 on every OS (pixi.lock),
  so an empty array under `set -u` is fine.
- `same_dir` (Cc1): vendor-libs.sh's `resolved()` (`cd && pwd -P`;
  Windows `cygpath -m -l`, lower-cased, since MSYS may be handed C:\...,
  C:/... or /c/... with 8.3 names) moves to env.sh as

  ```bash
  # Whether two directories are one, by real path: build.zig's
  # samePhysicalDir, for the scripts (vendor-libs.sh, zig-toolchain.sh).
  # One that does not exist (a prefix not made yet) is another.
  same_dir() { ... }
  ```

  and vendor-libs.sh's test becomes `if same_dir "$PREFIX" "$CONDA";
  then exit 0; fi`. One test in bash, one in zig, the same rule; each
  comment cites the other.
- The header comment names `zig/` with the other directories.

### zigbuild/toolchain/wheel.zig (new, step 2; open points B, C)

The wheel's records, as conda.zig is conda-meta's: pure functions, no
I/O, unit tests on fixture text. build.zig reads the files and installs.

- `pub const Marker = struct { url, sha256, source_url, source_sha256 }`
  and `pub fn parseMarker(text) !Marker`: the three lines fetch-zig
  writes; a missing line is an error that names it.
- `pub const Metadata = struct { version, license, source_code }` and
  `pub fn parseMetadata(text) !Metadata`: METADATA's `Version:`,
  `License-Expression:` and the `Project-URL: Source Code, <url>` line
  (the feedstock line's repository; METADATA has three Project-URL
  lines, Homepage, Source Code and Bug Tracker). The headers end at the
  first blank line (line 31 in 0.16.0's): the README body after it is
  never read (Cc10). A missing field is an error.
- All three readers drop a trailing `\r` from each line, as
  verify-toolchain does (a marker edited by hand) (Cc10).
- `pub fn tag(file_name) []const u8`: the wheel's tag from its file
  name (`ziglang-0.16.0-<tag>.whl`), for SOURCES' `build:` line.
- `pub const Entry = struct { from, to, sha256_hex }` and
  `pub fn parseRecord(a, text, exe_name) ![]Entry`: RECORD's lines
  `ziglang/<exe_name>` and `ziglang/lib/...`, with `to` the path in
  `zig/` (`zig`, `zig.exe`, `lib/...`), the hash's urlsafe base64 (no
  padding) decoded and written as 64 lowercase hex characters. Skipped:
  `ziglang/__init__.py`, `__main__.py`, `README.md`, `LICENSE` (the
  licence is in LICENSES/, B4) and every `*.dist-info/` line. Errors: a
  quoted line (a path with a comma; RECORD is CSV), an entry with no
  `sha256=` hash, a hash that does not decode to 32 bytes, no entry for
  the binary.
- Tests: the empty file's hash
  (`47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU` →
  `e3b0c442...b855`, the RECORD line for `ziglang/__init__.py`); a
  fixture of real RECORD lines (the binary, two lib files, the four
  skipped files, three dist-info lines, RECORD's own `,,` line) gives
  three entries; a Windows fixture with `ziglang/zig.exe`; a quoted line
  and a missing hash fail; the marker and METADATA parsers on fixture
  text, and their missing-field errors; a METADATA fixture with all
  three Project-URLs and a body line `Version: 9.9` after the blank line
  (the header's version wins) (Cc10); a marker with CRLF line ends;
  `tag` on the five pinned file names.

### zigbuild/toolchain/build.zig (step 2; open points A, B, C, J)

- Header comment: the table gains

  ```
  //!   zig/       compilers    upstream zig, PyPI's ziglang wheel as
  //!                           fetch-zig pins it (B4, phase 5): zig and
  //!                           lib/, LICENSES/ziglang/ from the wheel's
  //!                           dist-info, SOURCES from its RECORD
  ```

  "zig/ and flang/ (compilers) come in phases 5 and 6" becomes "flang/
  (compilers) comes in phase 6". The paragraph "Each file's package is
  the conda-meta record ..." gains: zig/'s files are the wheel's, with
  the wheel's own sha256 of each (its RECORD), the counterpart of
  paths_data. The conda paragraph gains: no zig/ there (B30).
- Option: `const ziglang = b.option([]const u8, "ziglang", "PyPI's
  ziglang wheel, unpacked (scripts/fetch-zig.sh's directory): the
  compilers group's zig/");`
- After the conda directories' loop, when `!prefix_is_env`:
  - option missing: `b.getInstallStep().dependOn(&b.addFail("the
    toolchain tree's zig/ comes from PyPI's ziglang wheel: run pixi run
    toolchain (scripts/zig-toolchain.sh runs fetch-zig and passes
    -Dziglang=<dir>)").step);` A failing step, not a configure error,
    so `zig build test` (toolchain-test) runs without the wheel.
  - option given, `installZig(b, io, dir, tc, os)`:
    - reads `<dir>/.complete`, `<dir>/ziglang-*.dist-info/METADATA`
      and `.../RECORD` (one dist-info directory, found by iterating
      `<dir>`; none or two stop the build), and parses them with
      wheel.zig;
    - checks that every RECORD entry's `from` exists under `<dir>`
      (a stop that names the first missing one: an unpack that went
      wrong);
    - installs `ziglang/zig` (`zig.exe`) with `addInstallFileWithDir`
      (the mode is kept, as for usr/bin/make) and `ziglang/lib` with
      one `addInstallDirectory` to `zig/lib`: one step for 19,541
      files, not one each;
    - installs `<dist-info>/licenses/ziglang/` with one
      `addInstallDirectory` to `zig/LICENSES/ziglang` (15 files; none
      stops the build, as `installLicenses` does);
    - writes `zig/SOURCES` with `conda.writeSources` from a synthetic
      `conda.Record` (`name = "ziglang"`, version and license from
      METADATA, `build` = the tag, `url` and `sha256` from the marker,
      `upstream = .{ .sources = &.{.{ url, sha256 }}, .feedstock =
      source_code }`) and one `conda.Copy` per RECORD entry
      (`from = "ziglang/..."`, `to`, the hex sha256). One writer for
      both kinds of block; BlankInPath still guards the format.
  - The summary line gets `zig/ (ziglang)`.
- `prefix_is_env`: no zig/ and no option needed (open point J). The
  conda build's summary stays as today.
- The test step: a second `b.addTest` with `wheel.zig` as its root,
  both run by `test`; the step's description says "the conda-meta and
  wheel readers' and SOURCES writer's unit tests".
- Unchanged: the conda directories, `readRecords`, `readUpstream`,
  `installLicenses`, `samePhysicalDir`.

### scripts/verify-toolchain.sh (steps 1, 2; open point D)

Header: "Every file in it is a third-party file copied unchanged from a
conda package, or that package's record" becomes "... from a conda
package or, in zig/, from PyPI's ziglang wheel (B4), or that package's
record"; the copies item says the sha256 is "the package's (conda-meta's
paths_data; the wheel's RECORD)"; a new item: "zig: zig/zig prints the
version SOURCES records for ziglang". The layout check (a pure bash
loop, no forks) stays.

Records and copies, per directory (replaces the two `while` loops over
`files.txt` and `find "$D"`, today's lines 107-127):

```bash
  # file: <path in the package> -> <path here> <sha256>, as "<path here>
  # <sha256>"; then every copy here and its sha256, in one pass (zig/ has
  # 19,557 files: one sha256sum and one awk per file took minutes, PHASE5
  # open point D)
  tr -d '\r' < "$D/SOURCES" | awk ... > "$WORK/files.txt"          # as today
  (cd "$D" && find . ! -type d ! -path ./SOURCES ! -path './LICENSES/*' | sed 's|^\./||' |
    LC_ALL=C sort) > "$WORK/here.txt"
  : > "$WORK/sums.txt"
  if [ -s "$WORK/here.txt" ]; then
    (cd "$D" && tr '\n' '\0' < "$WORK/here.txt" | xargs -0 sha256sum) |
      awk '{ h = $1; sub(/^\\/, "", h); n = substr($0, length($1) + 2); sub(/^[ *]/, "", n); print n, h }' > "$WORK/sums.txt"
  fi
  while IFS= read -r line; do bad="$bad
  $line"; done < <(awk -v d="$d" '
    FILENAME == ARGV[1] { if ($1 == "BAD") { $1 = ""; print substr($0, 2) " (not a file line)" } else want[$1] = $2; next }
    { got[$1] = $2 }
    END {
      for (f in want) if (!(f in got)) print d "/" f " (in SOURCES, missing)";
                      else if (got[f] != want[f]) print d "/" f " (sha256 " got[f] ", SOURCES says " want[f] ")"
      for (f in got) if (!(f in want)) print d "/" f " (no file line in SOURCES)"
    }' "$WORK/files.txt" "$WORK/sums.txt" | LC_ALL=C sort)
  awk -v d="$D/" '{ print d $0 }' "$WORK/here.txt" >> "$WORK/copies.txt"
```

(Cc6) `! -path ./SOURCES` skips only the directory's own SOURCES, as
today's `case "$rel" in SOURCES|...` does (`! -name` would skip a file
named SOURCES at any depth). `FILENAME == ARGV[1]` reads files.txt as the
`want` table even when it is empty (a SOURCES with no `file:` lines),
where `FNR == NR` would read sums.txt as `want`. awk's prefix, not
`sed "s|^|$D/|"`, so a `&` or `|` in `$D` stays itself.

- `here.txt` is never empty in practice (SOURCES has at least one copy
  per directory); it is guarded with `[ -s ]` anyway, since GNU xargs
  runs its command once on empty input and sha256sum would then print a
  line for stdin. Every batched call has its own `[ -s ]` guard; no
  `xargs -r`, whose support in macOS's xargs would be one more thing to
  check (Cc2, partly).
- **Batched greps under `set -euo pipefail`** (Cc2): grep exits 1 when
  nothing matches, and xargs then exits 123 (GNU) or 1-125 (BSD). Every
  batched grep therefore runs only inside a process substitution that
  feeds a `while` loop, ending in `|| true`:
  `done < <(tr '\n' '\0' < "$WORK/copies.txt" | xargs -0 grep ... || true)`.
  Never `x="$(... | xargs grep ...)"` and never in a plain pipeline: on a
  clean tree that would end the script with no message.
- `sha256sum`'s output is read as GNU's `<hash>  <name>` or `<hash>
  *<name>` (MSYS's binary mode), with MSYS's leading `\` dropped, as
  fetch-zig drops it. `xargs` splits the list by the OS's command-line
  limit (MSYS: 32k characters, a few dozen runs). A path with a blank
  cannot reach here: writeSources refuses one, and such a copy shows as
  "no file line".
- Build-path scan of the copies (today's lines 164-172): one
  `tr '\n' '\0' < "$WORK/copies.txt" | LC_ALL=C xargs -0 grep -laE
  "${icase[@]}" -e "$re"` lists the copies that name one; `first_match`
  runs only on those. `LC_ALL=C` (Cc7): the paths are ASCII bytes, and
  `-i` then folds ASCII, which drive letters and `Users` need, without
  GNU grep's slow multibyte case folding over 360 MB of binary data on
  MSYS. The copies are only listed, never failed, so a non-ASCII user
  name's case (not folded in C) costs at most a missing note line. The
  note says "third-party copies that name one of them, as their packages
  ship them" (TODO's "zig/ third-party in the build-path scan").
- Binaries (today's lines 188-189 and 217-218 read four bytes of every
  copy with `head | od | grep`): candidates first, with one `xargs -0
  grep -l` of the magic number at a line start (`LC_ALL=C`,
  `$'^\x7fELF'` on linux, `$'^\xcf\xfa\xed\xfe'` on macOS; GNU and BSD
  grep both take it), then today's exact four-byte test on the
  candidates only (a static archive holding ELF objects matches the
  grep, not the test). Windows keeps its name filter (`*.exe`,
  `*.dll`). The candidate grep is batched as above (`[ -s ]`, process
  substitution, `|| true`) (Cc2). A positive check after the loop
  (Cg8): when zig/ is in the tree, `zig/zig` (Windows `zig/zig.exe`) is
  among the files the closures block counted, else the block fails with
  "the binary detection missed zig/zig", so a grep that misses on BSD
  or MSYS cannot skip the closures silently.
- New, after the OpenMP check:

  ```bash
  # The compilers group's zig (B4, phase 5): upstream zig, PyPI's ziglang
  # wheel; it runs, and says the version SOURCES records for it.
  zig="$TREE/$tc/zig/zig"; [ "$OS" = windows ] && zig="$zig.exe"
  [ -x "$zig" ] || { echo "error: $tc/zig/zig is missing (the compilers group's zig)" >&2; exit 1; }
  want="$(tr -d '\r' < "$TREE/$tc/zig/SOURCES" | awk '$1 == "package:" { p = $2 } p == "ziglang" && $1 == "version:" { print $2; exit }')"
  got="$("$zig" version | tr -d '\r')"
  [ -n "$want" ] && [ "$got" = "$want" ] ||
    { echo "error: $tc/zig/zig says '$got', SOURCES records ziglang '${want:-(none)}'" >&2; exit 1; }
  echo "== zig verified: $tc/zig/zig $got (PyPI's ziglang, as SOURCES records)"
  ```

  verify-toolchain runs only on the standalone tree, never on the conda
  env, so zig/ is required. (The version is SOURCES', not a literal: the
  0.17 wave changes fetch-zig only, B18.)
- The closures need no change for zig: linux's binary is static (no
  NEEDED, no GLIBC versions), macOS' has minos 13.0 (= MACOS_MIN) and
  only libSystem, win-64's imports system DLLs and API sets (ST §1,
  measured on all five binaries).

### zigbuild/tools/rzig/groups.zig (step 3; open point H)

- `text()`'s compilers head, second line:

  ```zig
  "  standalone:  extract {s} where you extracted R (zig {s} and the OpenMP files), and put LLVM flang on PATH\n", .{ p.r, p.name, p.zig, archive, p.zig }
  ```

  (the format arguments re-ordered to match). It keeps "LLVM flang on
  PATH", which wheel-test.sh greps, until phase 6 puts flang in the
  archive.
- The test's two expected lines:
  - `  standalone:  extract R-4.6.1-linux-64-compilers.tar.gz where you extracted R (zig 0.16 and the OpenMP files), and put LLVM flang on PATH`
  - `  standalone:  extract R-4.6.1-win-64-compilers.zip where you extracted R (zig 0.16 and the OpenMP files), and put LLVM flang on PATH`
- Header comment (lines 23-29): "compilers holds zig (from phase 5,
  PyPI's ziglang wheel, B4) and the OpenMP files (C19); phase 6 adds
  flang, until then on PATH". The test comment listing the greps stays
  true.
- `no_zig` and `no_flang` are unchanged (`no_zig` already names
  `R_HOME/bin/toolchain/zig`).

### zigbuild/tools/rzig/parity-test.sh (step 3)

The check "--rzig-check=fortran: no flang, 127, the compilers group"
(line 616) anchors the new line:

```bash
grep -q '^  standalone:  extract R-[^ ]*-compilers\.tar\.gz where you extracted R (zig [0-9.]* and the OpenMP files), and put LLVM flang on PATH\$' '$W/check.err'
```

(BRE: the parentheses are literal.) The check "--rzig-check: the
toolchain's zig/" (line 611) already proves the lookup with a real zig
in `zig/`.

### scripts/verify-bundle.sh (step 4; open points E, F, G, Q)

The pass (open point F):
- `verify-bundle.sh [toolchain|build]`, default `toolchain`; any other
  word is an error. `pixi run verify-package` keeps its command.
  - `toolchain`: what a user of the archives gets. `zig_env=()`: no
    ZIG_BIN, no ZIG_GLOBAL_CACHE_DIR, so rzig takes `TC/zig/zig` and
    zig its default cache under the fresh HOME (unix `$home/.cache/zig`,
    Windows `LOCALAPPDATA=$home`) (open point G).
  - `build`: today's `zig_env` (ZIG_BIN=$ZIG and env.sh's
    ZIG_GLOBAL_CACHE_DIR, never ZIG_LOCAL_CACHE_DIR), the fourth pass.
- `pass_zig`, the zig every assertion names, set when scenario 2
  extracts the compilers archive:
  - toolchain, unix: `"$(cd "$TC/zig" && pwd -P)/zig"` (rzig resolves
    its own path's symlinks, main.zig `selfExe`: macOS' /var is
    /private/var);
  - toolchain, Windows: `"$(cygpath -m -l "$TC")/zig/zig.exe"` (rzig
    prints the long form, and windows-latest's TEMP is an 8.3 path);
  - build: `$zig_bin`, as today.
  - The guards `if [ -n "$ZIG" ]` (and `-x "$ZIG"`) in scenarios 2 and
    3 test `$pass_zig` instead: in the toolchain pass a zig exists
    once the compilers are extracted, whatever env.sh found.
- The end of the script, after scenario 3's last check:

  Which pass follows is decided once, right after scenario 2 extracts
  the compilers archive, while TC/zig is in place (Cc4):

  ```bash
  # The fourth pass follows unless the build's zig is TC/zig's bytes (the
  # upstream legs: fetch-zig's zig, the same wheel): nothing more to test.
  build_pass=""
  if [ "$pass" = toolchain ] && [ -n "$ZIG" ] && ! cmp -s "$ZIG" "$TC/zig/zig$exe"; then build_pass=1; fi
  ```

  and the end of the script, which replaces today's last line:

  ```bash
  # The fourth pass (feat-standalone-toolchain phase 5, PHASE5 open point
  # F): the same archives with the build's zig, ZIG_BIN=$ZIG, so that
  # conda-forge's zig keeps its package coverage on the default legs. This
  # pass's directory goes first, so the two never take TMPDIR's space at
  # once, and the build pass's result is the script's.
  echo "== standalone archives verified ($OS/$FLAVOR, the $pass pass: $pass_what): the base alone, + compilers, + build-tools"
  if [ -n "$build_pass" ]; then
    rm -rf "$VERIFY_DIR"; trap - EXIT
    exec bash "$0" build
  elif [ "$pass" = toolchain ] && [ -n "$ZIG" ]; then
    echo "   note: the build's zig is TC/zig's ($ZIG): no second pass"
  fi
  ```

  (`exe` is `.exe` on Windows, empty elsewhere; `pass_what` is "TC/zig"
  or "ZIG_BIN=$ZIG".) So the log's last "verified" line is the last pass
  that ran, never a success line followed by a failing pass (Cc4). Each
  pass has its own VERIFY_DIR and HOME.
- Open point S (Cg1): blocks that pass no `zig_env` test the same thing
  in both passes; the build pass skips them with one note line: scenario
  1 (the base alone) and the no-zig preflight check. The file lists
  stay in both (seconds). The record says the build pass repeats the
  other zig-independent checks.
- Header comments (lines 31-95): scenario 2's "rzig's check mode finds
  zig and flang" names zig from `TC/zig` and flang from PATH; "Every
  OS, with no ZIG_BIN (no zig: phase 5)" becomes "with no zig (TC/zig
  moved aside)"; "What phase 3 leaves to later phases" loses zig's
  sentence; a paragraph on the two passes.

Scenario 2 (in order):
- Check mode (today's lines 575-597): "zig from TC/zig" in the toolchain
  pass, "zig from ZIG_BIN" in the build pass; the line must contain
  `" at $pass_zig"` (`grep -qiF`; Windows compares the check line,
  which shows `/` only: check.zig `display`) (open point Q). The flang
  half is unchanged.
- New, right after: **the first C++ compile**. A C++ source with
  `<iostream>`, `<string>` and `<vector>` (a function returning a
  string's length), compiled and linked as a shared library by the
  bundle's C++ compiler (`$TC/zig-cxx -shared -fPIC -o x.so`, Windows
  `$TC/g++.exe -shared -o x.dll`, (Cc11)) under `env -i "${base_env[@]}"
  "${zig_env[@]}"` with the check mode's PATH, timed with bash's
  `SECONDS`. It prints "== the first C++ compile (<pass>, <which
  cache>): N s, zig's cache M MB, K warning lines". zig's cache is read
  where zig puts it (Cc11): in the toolchain pass unix `$home/.cache/zig`,
  Windows `$home/zig` (zig 0.16 takes LOCALAPPDATA, which base_env sets
  to `$home`); in the build pass env.sh's ZIG_GLOBAL_CACHE_DIR, and the
  line says "warm (env.sh's cache), for comparison" so nobody records
  it as a cold time. In the toolchain pass the cache is empty, so this
  is the measurement (TODO: "the first C++ compile's time with upstream
  zig"); it asserts no shared libc++/libstdc++ (`cxx_deps`; Windows: no
  `libc++.dll` or `libstdc++-6.dll` among `needed_of`).
- New, right after, every OS, one code path (Cg4): the zig the
  compilers run, from RZIG_PRINT_ARGV: the first line of `RZIG_PRINT_ARGV=1
  "$cc" -c a.c` (after any `ZIG_LIB_DIR=` line), with `\` turned into
  `/` (`tr '\\' /`), must equal `$pass_zig` (`grep -qixF`: NTFS
  ignores case). Today's unix-only `rz = $ZIG` check (lines 1081-1083)
  is this check, moved out of the unix block. TODO's box "RZIG_PRINT_ARGV
  shows `TC/zig/zig`" is ticked on it, on Windows too; Q (a) still holds
  (rzig unchanged), the check line stays a second assertion.
- The preflight block and the R CMD SHLIB no-make block (SHLIB's) run
  as they are, with the pass's `zig_env`.
- Baseline CPU (lines 958-968): all three IR compiles, `want` from
  `"$pass_zig" cc -mcpu=baseline` (the same zig as the compiles) and the
  two `"$cc"` compiles, under one `env -i "${base_env[@]}"
  "${zig_env[@]}" PATH=...` (Cc3: `want` too; outside env -i it would
  write upstream zig's objects into env.sh's conda-forge-keyed caches,
  the mix risk 3 forbids). The Windows dry runs (`RZIG_PRINT_ARGV=1
  "$cc" ...`, lines 996, 1017) stay outside: they print argv and run no
  zig.
  Today they run in env.sh's shell, which exports ZIG_BIN (upstream
  legs) and env.sh's ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR: in
  the toolchain pass on a default leg that would hand upstream zig
  conda-forge's caches (env.sh's comment on the 2026-10-04 mix). The
  comment loses "the bundle has no toolchain zig/".
- Windows, new, after the OpenMP DLL: **`-lsynchronization`** (D6). A
  package `syncw` (mkpkg's shape) whose `src/sync.c` calls
  `WakeByAddressSingle` and whose `src/Makevars.win` is `PKG_LIBS =
  -lsynchronization` (no rule, so rzig build's tier 1, no make),
  installed with `R CMD INSTALL` under `env -i` with PATH = bin\x64 +
  System32 and RZIG_TRACE=1 (`rzig build: tier 1` asserted), then
  loaded with the same PATH, `f()` checked. It runs in both passes, so
  both zigs link it. (`#define _WIN32_WINNT 0x0602` before
  `<windows.h>` if zig's MinGW headers hide `WakeByAddressSingle`
  otherwise.)
- unix compiled packages (lines 1061-1475): `rz` must be `$pass_zig`
  (line 1083); the CONDA_PREFIX argv filter `grep -vxF -- "$ZIG"`
  (line 1466) drops `$pass_zig`; the echo says which zig.

Scenario 3: the `$ZIG` guards as above; nothing else changes.

The no-zig preflight check (lines 1943-1983; open point E): with
`host_zig` empty, before the loop:

```bash
  # The compilers group brings zig since phase 5: without its binary, rzig
  # sees what a user with R and the build tools only sees (find_zig tests
  # only <rzig dir>/zig/zig). The binary alone, out of R_HOME and back
  # after: a rename of the 19.5k-file directory fails on NTFS while
  # anything (Defender) holds a handle under it.
  mv "$TC/zig/zig$exe" "$VERIFY_DIR/zig.aside"
  ...
  mv "$VERIFY_DIR/zig.aside" "$TC/zig/zig$exe"
```

(Cc8) Its comment loses "(ZIG_BIN unset; the compilers group has none
until phase 5)". It runs in the toolchain pass only (open point S,
(Cg1)): it passes no zig_env, so the build pass would test the same
thing.

### scripts/env.sh, scripts/compile-tree.sh (step 5)

- env.sh line 72: "zig/ (phase 5), flang/ (phase 6) and openmp/" →
  "zig/ (upstream zig, B4), flang/ (phase 6) and openmp/". The comment
  on `$ZIG` (lines 113-127) adds: a standalone tree's compiles find
  `TC/zig/zig`; a dev tree has none (the compile tree leaves it out).
- compile-tree.sh line 21: "zig/ and flang/ (phases 5 and 6) stay out"
  → "zig/ and flang/ (flang from phase 6) stay out".

### README.md (step 5)

- The compilers bullet (lines 233-238): it holds zig 0.16 (PyPI's
  ziglang build, the ziglang.org release) and OpenMP's headers (Windows
  also `libomp.lib`), about 85-100 MB; flang joins it later, until then
  LLVM `flang` from `PATH`; `ZIG_BIN` still overrides the group's zig.
- The records sentence (lines 245-248): `SOURCES` names the package
  each file comes from (a conda-forge package; for `zig/` PyPI's
  ziglang wheel), its sha256 and where its source is.
- The extract example (line 254): `# + .../toolchain/zig/ and openmp/`.
- Line 266-267 (stale, SD §9): CI keeps the base archives a week and the
  group archives 30 days, as the CI section and toolchain.yaml say.
- The dev notes (Cg6): `pixi run toolchain` downloads PyPI's ziglang
  wheel once per platform (about 100 MB, cached in `build/zig-upstream/`)
  for the tree's zig/, even for the chains that use only the compile
  tree; an offline host needs that cache.

### recipe/recipe.yaml (step 5; open point M)

`number: 11`, after the "9 → 10" history entry:

```yaml
  # 10 → 11: the compilers group's standalone line names its archive for
  # zig (feat-standalone-toolchain phase 5, B35): rzig's text changes in
  # r-zig-slim. No zig is packaged: conda keeps conda-forge's zig (B30),
  # and the toolchain build installs no zig/ into the env. The number
  # follows SHLIB's 10 (B14 a); if another build publishes first, this
  # takes the one after it.
```

### .github/workflows/toolchain.yaml and pixi.toml (step 5, comments only)

- toolchain.yaml's header (lines 9-13): the tree holds, from phase 5,
  `zig/` (PyPI's ziglang wheel, which the toolchain build fetches on
  every leg) besides openmp/, usr/bin/make and binutils/. The upload
  step's comment: the compilers archive is 84-100 MB. No step changes:
  zig-toolchain.sh fetches, and on the upstream legs the earlier
  "Upstream zig (ZIG_BIN)" step has already filled the same directory.
  `timeout-minutes: 30` stays (step 1 makes verify-toolchain batch);
  each step's time on windows-latest's first run is recorded, and the
  timeout moves only if a measurement says so (Cc7). No
  `compression-level` change (open point T).
- pixi.toml's comments on fetch-zig (lines 66-78) and `toolchain` (near
  line 148): `toolchain` runs fetch-zig for the tree's `zig/`. No table
  changes.

### Files that need no change (checked)

- zigbuild/tools/rzig/find_zig.zig: the order and its unit test
  "the toolchain's zig/ wins over the environment's bin and PATH" (SR
  §1).
- zigbuild/tools/rzig/windows.zig: D6's mapping (PR #19). `-lmsvcrt` is
  open point L.
- zigbuild/tools/rzig/libcxx_mirror.zig: `zigLibDir` finds no
  `TC/lib/zig` for TC/zig, so there is no mirror, which is right for
  upstream zig (SR §2).
- zigbuild/tools/rzig/check.zig: the version check (major.minor, B32)
  and `display` (SR §3, §8).
- zigbuild/tools/rzig/cache.zig, pkgbuild.zig: the runner key includes
  the zig's path, `\` normalised (SR §5).
- scripts/package-standalone.sh, scripts/unpack-toolchain.sh: they take
  every group directory the tree has (ST §1).
- scripts/compile-tree.sh's code (C12), scripts/verify-tree.sh (R trees
  only; the TODO's "verify-tree" item lands in verify-toolchain),
  scripts/hermetic-check.sh (first lines only), scripts/make-wheel.py
  (`usr/` only), scripts/wheel-test.sh ("LLVM flang on PATH" kept),
  python/r_zig/__init__.py, recipe/test-*.R (first lines only),
  recipe/build.sh (R_TOOLCHAIN_PREFIX already set), build.yaml,
  build-r.yaml, stress.yaml (they download and unpack whatever the
  toolchain job uploads), conda.zig (writeSources serves both kinds of
  block).

## 4. Per channel: what changes

| channel | what changes | build number / version |
|---|---|---|
| standalone base (`R-<ver>-<flavor>-<plat>`) | rzig's compilers text (the standalone line) | — (no release, B12) |
| standalone compilers (`R-<ver>-<plat>-compilers`) | gains `zig/`: the binary, `lib/`, `LICENSES/ziglang/`, `SOURCES`; 84-100 MB instead of ~32 KB | — |
| standalone build-tools | nothing | — |
| conda r-zig-slim | rzig's text; no other file | 10 → 11 (B14 a) |
| conda r-zig-compilers, r-zig-build-tools, r-zig-toolchain | no file and no dependency changes; they share the recipe's number and pin r-zig-slim `_11` | 11 |
| PyPI r-zig | rzig's text | the wheel's version carries no build number; nothing is published (B12) |
| PyPI r-zig-compilers (ziglang), r-zig-build-tools, r-zig-toolchain | nothing | — |

conda depends on conda-forge's `zig 0.16.*` (r-zig-compilers;
r-zig-slim's run_constraint, phase 4's K) and PyPI on ziglang, as
before (B30, point 5). The recipe's exclusion of
`lib/R/bin/toolchain/{zig,...}/**` stays; it now guards a directory the
conda build never makes.

## 5. rzig with a zig in TC/zig (what changes for it, from SR)

- **Lookup**: `TC/zig/zig` second, after ZIG_BIN. On Windows rzig joins
  it as `<long TC path>/zig\zig.exe` (find_zig `inDir`): the check line
  shows `/` only, RZIG_PRINT_ARGV the raw path (open point Q).
- **Version check** (B32): it now compares the compilers archive's zig
  with the base's rzig. Both 0.16.0 in the mixed case (phase 2 record:
  conda-forge-built tree with upstream 0.16.0 passes; 0.17.0 fails).
- **Mixed case's CC_VER**: `R_compiled_by()` and R CMD INSTALL's
  "using C compiler" line say conda-forge's clang 21.1.8 while TC/zig is
  clang 21.1.0. Cosmetic; TODO's "Later" (build.zig fills CC_VER/FC_VER
  from the zig that builds R) covers it (open point R).
- **The libc++ mirror**: none for TC/zig (upstream zig links its own
  static libc++). An inherited ZIG_LIB_DIR would still reach TC/zig
  (open point R).
- **The shared build runner** (PR #27): its key holds the zig's path, so
  each place a compilers archive is extracted gets its own runner (about
  45 MB, 3-13 s to build), swept after 7 days idle; conda-forge's and
  upstream zig never share one (open point R).
- **Tiers**: rzig build and every compile step it runs find the same
  zig (find_zig in each); tier 2 compiles with zig's own lib dir.
- **zig's global cache**: rzig sets none. A user who runs a standalone R
  and a conda R shares zig's default cache between the two 0.16.0
  builds, which env.sh's comment says can mix objects (open point N).
- **First C++ compile, empty cache, linux-64**: 17-18 s with upstream
  zig, 20 s with conda-forge's, about 3,400 `-Wnullability-completeness`
  lines each (ST §4, SR §6): not an upstream-only cost.

## 6. Tests per OS and CI

### What each scenario proves (verify-bundle, two passes)

| scenario | toolchain pass (ZIG_BIN unset) | build pass (ZIG_BIN=$ZIG) |
|---|---|---|
| file lists | the compilers archive holds `zig/` under its own directory, no overlap | the same |
| 1. base alone | unchanged: 127 and the compilers text (whose standalone line is new), R CMD SHLIB's stop, hermetic-check | skipped with a note (no zig_env: open point S, (Cg1)) |
| 2. + compilers | check mode names `TC/zig/zig`; the first C++ compile timed with an empty cache; RZIG_PRINT_ARGV's zig is `$pass_zig`, every OS (Cg4); preflight (pfC through rzig build, the stops); R CMD SHLIB with no make (SHLIB's shapes); baseline CPU; Windows dry runs, OpenMP DLL and `-lsynchronization`; unix C, C++ (no shared libc++), Fortran, OpenMP (three forms), the flagless omp.h probe (B40), decoy CONDA_PREFIX | the same with `$ZIG` (the C++ compile's line labelled warm, (Cc11)) |
| 3. + build-tools | btA/btLib(/btRc), Windows' binutils, tools.mk, CMake's ar, OpenMP C and Fortran packages, LTO recorded; then the no-zig preflight check with `TC/zig/zig` moved aside (Cc8) | the same, but the no-zig check skipped (S) |

Default legs: toolchain pass = the mixed case, build pass = conda-forge's
zig. Upstream legs: toolchain pass = the one-zig case; build pass
skipped (same bytes). minimal: no OpenMP checks (B40) in either pass.

### Per host

| host | runs |
|---|---|
| gamma (linux-64; implementer, owns `dist/`) | steps 1-5's chains (section 2) with conda-forge's zig and with upstream zig (`ZIG_BIN="$(pixi run fetch-zig)"`): `rzig-test`, `toolchain-test`, `toolchain`, `verify-toolchain` (timed), `package-toolchain` (sizes), `build`, `verify-tree`, `smoke`, `contract`, `hermetic`, `pkg-parity`, `verify-package` (both passes on the default env; the one-zig pass on upstream); minimal `build` + `verify-package`; `wheel`, `wheel-test`; `conda-package`, `conda-consume` |
| omicron, osx-arm64 (tester) | step 1's binary count before/after (BSD grep, BSD xargs; Cg8); `rzig-test` (both zigs); `toolchain`, `verify-toolchain` (timed), `package-toolchain` (size); `build` → `verify-package` (default: both passes; upstream: the one-zig pass); minimal `build`, `verify-package`; `wheel`, `wheel-test`; `conda-package`, `conda-consume`. Record the first C++ compile's time. Note whether macOS asks anything about the extracted zig (Gatekeeper: a tar.gz extracted by the scripts has no quarantine attribute; a browser download is not tested) |
| omicron, osx-64 under Rosetta (a copy re-solved for osx-64) | `toolchain` (fetches the osx-64 wheel), `verify-toolchain`, `package-toolchain`; then, if the endpoint agent allows an unsigned x86_64 zig, `verify-package`'s toolchain pass. A kill is recorded as such (open point K) |
| kappa (win-64, tester) | `rzig-test`; `toolchain` (time the 19.5k-file install), `verify-toolchain` (timed), `package-toolchain` (zip time and size), `unpack-toolchain` (unzip time); `build` → `verify-package` (both passes; the `-lsynchronization` package in each); upstream: `verify-package` one-zig pass; `conda-package`, `conda-consume`; open point L's `-lmsvcrt` check first, in step 3b (Cg3): magick with TC/zig in an extracted bundle (base + both groups, ZIG_BIN unset: `install.packages("magick")` under the bundle's R), and a Rust package if cargo is on the host. Record the first C++ compile's time; the binary count before/after step 1 (Cg8) |
| CI, the PR | the core tier (toolchain legs and verify-package on the default legs: the mixed case on linux-64 and windows-latest at least); conda-package by its path filter (recipe/, zigbuild/, scripts/ change: five legs, four tests and conda-consume each); then `full-ci` (every leg: linux-aarch64, macos-latest, macos-15-intel's first upstream zig on osx-64, minimal and wheel-test legs); then the `upstream-zig` label run (the one-zig case on its three runners). Record each toolchain leg's time and artifact size, and verify-package's time per leg against d11dee1's |
| CI, main after merge | the publish of `_11` (four files per subdir), after phase 4's and SHLIB's |

Every host records the pixi.lock sha256 (must stay fbb64b7ba4e31e45...)
and `git diff | sha256sum` at start and end.

## 7. Measurements to record (PLAN.md's phase 5 record)

| what | where | per |
|---|---|---|
| compilers archive size (.tar.gz/.zip), zig part, member count; `TC/zig` unpacked size and file count | `package-toolchain`'s "== done:" line, `du`, `archive_files | wc -l` | linux-64, linux-aarch64 (CI), osx-arm64, osx-64, win-64 (survey estimates: 87.1, 84.1, 86.5, 90.4 MB gzip; 100.3 MB zip) |
| the first C++ compile with an empty zig cache, TC/zig: seconds, cache MB, warning lines | verify-bundle's new line (toolchain pass) | every host and CI leg; the build pass's line for comparison |
| `pixi run toolchain` time (cached wheel) and the first fetch | the task's wall time | gamma, omicron, kappa |
| verify-toolchain time, before (today's tree) and after zig/ | wall time | gamma, omicron, kappa, CI legs |
| unpack-toolchain time | wall time | kappa; CI on every OS, one leg of each kind: build-only (build-r), packaging, stress (Cg6) |
| verify-package time, toolchain pass and build pass, each | wall time | gamma, omicron, kappa, CI legs, against d11dee1's (Cg1) |
| toolchain job's steps on windows-latest: env install, fetch + unzip, zig build install, zip, verify-toolchain, upload | the run's step times | CI windows-latest, first run (Cc7) |
| the build runner's first build with TC/zig | pfC's install log (`rzig build: tier 1`, its time) | gamma, omicron, kappa |
| CI: toolchain leg duration, artifact size, download time in build-r legs | the run's logs | every platform |

B13 (a): the sizes are recorded only; a compilers archive over 150 MB
comes back after phase 6 (win-64's zip is 100.3 MB before flang).

## 8. Risks

1. **Windows file counts.** zig/ adds 19,557 files: the zig build's
   install, `zip -qr`, the artifact's `unzip` in every build-r leg and
   verify-bundle's two extractions per pass. fetch-zig already unzips
   the same wheel on windows-latest (upstream legs), so it is bounded,
   but unmeasured. toolchain.yaml's 30-minute timeout needs step 1.
2. **verify-package's time nearly doubles on the default legs** (the
   fourth pass is the whole script, less scenario 1 and the no-zig
   check, open point S). linux-64's and windows-latest's verify-package
   are in the core tier (CI1), so that is on every push. Recorded per
   leg against d11dee1's. Any later move (F's (b), (c), or a build pass
   only under full-ci) goes to the user as a menu with the measured
   times; none is chosen now (Cg1).
3. **Cache mixing.** The toolchain pass must never see env.sh's
   ZIG_GLOBAL_CACHE_DIR or ZIG_LOCAL_CACHE_DIR: every compile in it
   runs under env -i (the baseline-CPU compiles move there). For users,
   open point N.
4. **osx-64 upstream zig has never run** (SD P5-K). macos-15-intel is
   its first run; omicron's Rosetta and endpoint agent may kill an
   unsigned x86_64 zig.
5. **Windows packages that need what upstream zig lacks.**
   `-lsynchronization` is handled (D6). `-lmsvcrt` fails with upstream
   zig, and conda-forge's links msvcrt.dll into a UCRT R (open point
   L). A package DLL linked without a .def, imported by something else,
   relies on MinGW's atexit auto-export with upstream zig: not seen,
   not tested (SR §4).
6. **Artifact bandwidth**: 5 × 84-100 MB per toolchain run, twice with
   the upstream label, kept 30 days; every build-r and stress leg
   downloads and unpacks its platform's, though only verify-package
   reads zig/ (Cg6). The repository is public (`gh repo view`:
   PUBLIC), and GitHub does not bill Actions artifact storage for public
   repositories (to confirm once on the repository's usage page), so
   storage is not the limit; upload and download time are (open point I,
   (Cc9)). After phase 5 build.yaml's and upstream-zig.yaml's toolchain
   artifacts carry the same TC/zig (Cg9).
7. **The toolchain task needs the network once per platform** (PyPI).
   An offline host with no cached wheel cannot run `toolchain`.
8. **The licence set is upstream's** (open point C; (Cc5), (Cg2)): the
   licence texts of the bundled components are in LICENSES/ziglang/ as
   upstream ships them, LLVM's included: `lib/libcxx/LICENSE.TXT` (and
   libcxxabi's, libunwind's) is the Apache-2.0 WITH LLVM-exception text
   of the LLVM project, which covers LLVM, Clang and LLD linked into the
   binary, libtsan (compiler-rt) and clang's resource headers. The gap is
   upstream's attribution (no statement that the binary contains LLVM),
   not a missing text, and Apple's SDK headers and libSystem.tbd
   (APSL/BSD) and the netbsd and openbsd headers, which have no text of
   their own. SOURCES' `license: MIT` is the wheel's METADATA
   `License-Expression`; the bundled components' licences are in
   LICENSES/ziglang/.
9. **macOS Gatekeeper**: a browser-downloaded archive extracted by
   Archive Utility marks zig quarantined, as it marks the base's
   binaries already. Not phase 5's to change; unobserved.
10. **The first compile is slow and loud** for a new user: 17-20 s on
    linux (both zigs), about 3,400 warning lines once (libc++'s
    headers). Pre-seeding is the later menu.
11. **A build runner per extraction place** (45 MB each, a week's sweep)
    and CC_VER's cosmetic mismatch in the mixed case (open point R).
12. **Mixed separators on Windows** (`zig\zig.exe`): a check that greps
    RZIG_PRINT_ARGV's raw path for `/zig/zig` would fail there (open
    point Q).
13. **Stacking**: phase 5's diff sits on two uncommitted baselines that
    edit the same files; a hand-made phase5-only.diff can drop or
    double a hunk (open point O's check).
14. **Windows MAX_PATH**: zig's longest lib path is 88 characters,
    163 with CI's extraction prefix. A user who extracts into a deeper
    directory than about 170 characters hits it (R itself would too).
15. **zig 0.17** (B18): fetch-zig pins 0.16.0 and the check mode
    accepts only 0.16; the compilers archive follows the zig that builds
    the release. Nothing moves in phase 5.

## 9. Overlap with other pending work

- **Phase 4 and SHLIB** (uncommitted baselines): shared files listed in
  section 1. Phase 5 is the third PR; if either baseline changes after
  phase 5 starts, the implementer re-reads the changed hunks of
  verify-bundle.sh and groups.zig before step 4.
- **Phase 6 (flang)**: the compilers line's "put LLVM flang on PATH"
  goes then, with wheel-test.sh's grep; flang's files come from
  flang-pixi's conda packages, the conda path of build.zig, not the
  wheel path.
- **Phase 7**: Windows' usr/bin; independent of zig/.
- **zig 0.17 wave** (B18): fetch-zig's pin, conda's pins and the check
  mode move together then; `wheel.zig` reads whatever wheel fetch-zig
  names.
- **"Later: zig's global cache"**: phase 5's measurements feed that
  menu; open point N adds the two-zig sharing to it.
- **feat-zig-pkg-build** (on hold): no shared file with phase 5.

## 10. Records (step 6) and the stale references to fix

**PLAN.md: "Phase 5 record"** (new subsections under "### Phase 5"):
- What changed and why: fetch-zig's marker, wheel.zig, build.zig's zig/,
  zig-toolchain.sh's fetch, verify-toolchain in batch, groups.zig's
  line, verify-bundle's two passes; the answers to section 11.
- The measurements (section 7): sizes per OS, first C++ compile per OS,
  the timings.
- The tests per host and CI run IDs.
- The mixed-case notes (open point R).
- The split recommendations (Cg5): E answered with the plan's
  recommendation (a); the records survey recommended (b), a real R +
  build-tools layout, the rzig survey (a). H's final wording likewise:
  the plan's (a), with the surveys' wordings noted.
- The facts the critiques added: the build pass repeats the
  zig-independent checks except scenario 1 and the no-zig check (S);
  every build-r and stress leg downloads the compilers artifact though
  only verify-package reads zig/ (Cg6); build.yaml's and
  upstream-zig.yaml's toolchain artifacts carry the same TC/zig (Cg9).
- **Phase 5's step text**: step 2 "verify-tree" → "verify-toolchain"
  (verify-tree checks the R trees, which hold no zig/); step 4 (D6) →
  "done by PR #19 (fix-rzig-follow-ups, 7a3004d): rzig renames
  `-lsynchronization` to `api-ms-win-core-synch-l1-2-0` for both zigs;
  phase 5 adds the Windows package test".
- **D6's wording** (Cg10): the user's verbatim answer ("rzig deals with
  the import library") stays untouched in "The answers of 2026-10-08";
  only the step, TODO and Risks text change, citing fix-rzig-follow-ups'
  "How this answers D6 b" as the reason the rename satisfies it.
- **Risks**: "Windows with upstream zig" → D6 done (the rename), with
  `-lmsvcrt` as open point L's result; "The first compile is slow" →
  both zigs, with the per-OS times; "Size" → the measured sizes; "The
  mixed zig case" → covered by verify-bundle's toolchain pass on the
  default legs.
- **Verification**: scenario 2's "from phase 5 on Windows, a
  `-lsynchronization` link (D6)" → "a package linking it"; the fourth
  pass described as verify-bundle's `build` pass.
- **Later and future checks**: "zig's global cache" gets the measured
  times and open point N; "macOS without the Command Line Tools"
  unchanged; new items, each to go to the user as a menu (Cg2, Cg6,
  Cg9, Cg1):
  - the groups' licence completeness, zig/ now and flang/ in phase 6
    (Apple's SDK headers, the BSD headers, the LLVM attribution), with
    phase 6's licence review — B33 covers the base's runtime files only,
    so no phase picks this up otherwise;
  - leaving zig/ out of legs that never read it (build-only build-r
    legs, stress, the dev chains), with the unpack timings;
  - upstream-zig.yaml reusing build.yaml's toolchain artifact;
  - verify-package's build pass: keep, reduce (F's (b)), or only under
    full-ci, with the per-leg times;
  - the toolchain artifact's `compression-level: 0` (open point T).
- The status line.

**TODO.md, "## Phase 5"**: tick the boxes; the "verify-tree" box reads
"verify-toolchain"; the `-lsynchronization` box cites PR #19 (no import
library is generated: a rename); "Later" gains open point N (and L's
`msvcrt` mapping if (a)'s test finds a package that needs it).

**Other records.**
- fix-rzig-follow-ups PLAN.md, D6: a closing note that phase 5 tested
  the rename with TC/zig on kappa and windows-latest (package build and
  load).
- recipe.yaml's history entry (section 3).

**Stale references** (SD §9): README.md:266-267 (week vs 30 days,
section 3); verify-bundle.sh, compile-tree.sh and env.sh's "phase 5"
comments (section 3).

## 11. Open points (answered with the recommended option)

The user's instruction for this run ("Start phase 5", after "Follow
with the recommended" for the previous work): every point below is
answered with its ★ option, and PLAN.md's phase 5 record lists each as
answered that way, the menu kept for the record. C, E, F, I, J, L and Q
are amended after the critiques (tags in place); S and T are new, from
the critiques, answered the same way.

**A. How the toolchain build gets zig** (SD P5-A, ST §3).
- (a) ★ zig-toolchain.sh runs fetch-zig (the one pin table) and passes
  the unpacked directory as `-Dziglang=<dir>`; fetch-zig's marker holds
  the wheel's URL, sha256 and source line; build.zig and wheel.zig read
  the rest from the wheel's METADATA and RECORD.
- (b) build.zig fetches the wheels itself through build.zig.zon lazy
  dependencies: a second pin table in zig's hash format, and the
  download moves into zig's global cache.
- (c) build.zig holds the five pins and fetch-zig reads them from zig
  source: one pin, read by bash from zig code.
- Reason for (a): one pin and one download path (B4's reason), already
  used by both CI flavours; the rules stay in zig code, bash only
  downloads.

**B. zig's SOURCES block** (SD P5-B).
- (a) ★ The block conda's have: package, version, build (the wheel's
  tag), url, sha256, license, a `source:` line (ziglang.org's
  zig-0.16.0.tar.xz and its sha256), a `feedstock:` line (zig-pypi, its
  commit unknown: the wheel records none), and a `file:` line per copy
  with the wheel's RECORD sha256 in hex.
- (b) A shorter PyPI block (wheel URL and sha256, no file lines), with
  verify-toolchain branching on it.
- Reason for (a): one writer, one checker, and every one of the 19,557
  files checked against the wheel's own record, as conda's are against
  paths_data.

**C. zig's licences** (SD P5-C).
- (a) ★ `zig/LICENSES/ziglang/` = the wheel's dist-info licences (15
  files, zig's LICENSE among them), as B4 says; the files without a
  licence of their own (LLVM in the binary, libtsan, clang's headers,
  darwin/netbsd/openbsd) are recorded as "as upstream ships it".
- (b) Also add LLVM's LICENSE.TXT ourselves: a file from no release, so
  SOURCES would need a source that is not the wheel.
- Reason for (a): B4 decided the set. The texts are upstream's,
  LLVM's included (libcxx's LICENSE.TXT is the LLVM project's
  Apache-2.0 WITH LLVM-exception); what remains (the attribution,
  Apple's SDK headers, the BSD headers) is recorded "as upstream ships
  it", and the groups' licence completeness is a "Later and future
  checks" menu with phase 6's licence review (Cc5, Cg2). (The planner's
  "phase 8 (B33) revisits licences" was wrong: B33 is the base's runtime
  files.)

**D. verify-toolchain with 19.5k files** (SD P5-D, ST §1).
- (a) ★ Batch: one hashing pass and one awk join for records and
  copies; one `xargs grep -l` for the build-path scan; one `xargs grep
  -l` of the magic numbers before the exact binary test; the zig
  version check here (the PLAN's "verify-tree" predates phase 3's
  split).
- (b) Skip `zig/lib/` in the per-file checks: weaker, and the loop's
  cost stays for every other directory.
- Reason for (a): the same checks, every file, in seconds instead of
  minutes (2.6 s for one batched sha256sum of all 19,546 files on
  gamma), and MSYS's fork cost stops mattering.

**E. verify-bundle's no-zig preflight check** (SD P5-E, SR §7).
- (a) ★ Move `TC/zig` out of R_HOME (into VERIFY_DIR) for that check and
  back after: rzig then sees what a user with R and the build tools
  sees, no zig anywhere.
- (b) Run it in a directory of its own with the base and the
  build-tools archive: a real layout, but every R path (R_BIN, R_EXE,
  the Windows PATH entries) derived again for a second tree.
- (c) Drop the check.
- Reason for (a): two lines, the same thing rzig is asked, and the trap
  removes VERIFY_DIR on any exit. Only the binary moves (`zig/zig`,
  `zig.exe`), which is all find_zig tests (Cc8). (The records survey
  recommended (b), the rzig survey (a); the plan recommends (a) for
  simplicity, the user's rule, and the record says so (Cg5). (a) tests a
  modified tree, not a layout a user has.)

**F. Which compiles use TC/zig, and the fourth pass** (SD P5-F; PLAN
step 5).
- (a) ★ verify-bundle.sh takes the pass as an argument: `toolchain` (the
  default) runs every scenario with ZIG_BIN unset; then it runs itself
  once more as `build`, with ZIG_BIN=$ZIG and env.sh's cache, unless
  `$ZIG` has TC/zig's bytes (the upstream legs).
- (b) One run; only the package-shape blocks (scenario 2's unix
  packages, Windows' OpenMP packages) run a second time with
  ZIG_BIN=$ZIG, wrapped in a function: shorter, but a re-indented
  400-line block and two code paths to keep alike.
- (c) No fourth pass: conda-forge's zig keeps contract, pkg-parity,
  stress and the conda tests. Changes PLAN step 5.
- Reason for (a): one switch at the top and a few assertion sites, no
  block moved; "the existing compiles" stay exactly as they are for the
  build's zig. The cost (verify-package nearly twice on the default
  legs) is measured per leg; any later change goes to the user as a menu
  with those times (Cg1).

**G. zig's global cache in verify-bundle** (SD P5-G).
- (a) ★ The toolchain pass passes no cache variable: zig uses its
  default under the fresh HOME, as a new user's does, and the first C++
  compile's time is measured there. The build pass keeps env.sh's.
- (b) Pass env.sh's global cache to both passes: faster, measures
  nothing, and on the default legs hands upstream zig conda-forge's
  objects.
- Reason for (a): it is the user's case and the measurement TODO asks
  for, and it avoids the 2026-10-04 cache mix.

**H. The compilers group's standalone line** (SD P5-H, SR §8).
- (a) ★ `extract R-<ver>-<plat>-compilers.tar.gz where you extracted R
  (zig 0.16 and the OpenMP files), and put LLVM flang on PATH` (`.zip`
  on Windows); ZIG_BIN is no longer mentioned.
- (b) Keep ZIG_BIN in the line ("or zig 0.16 in ZIG_BIN").
- Reason for (a): B35's "name the archive for what it holds"; one thing
  to do, and the phrase wheel-test.sh greps stays until phase 6.
  ZIG_BIN stays an override for those who know it (README). The surveys
  proposed different wordings; the record says the plan's (a) was taken
  (Cg5).

**I. CI** (SD P5-I).
- (a) ★ Every toolchain leg fetches the wheel through zig-toolchain.sh;
  the artifact grows to 84-100 MB per platform; retention stays 30 days;
  the sizes and the account's storage use are read after the first runs
  and recorded.
- (b) Shorter retention for the group artifacts (for example 7 days, as
  the bases).
- Reason for (a): failed legs can be re-run for 30 days without the
  toolchain job (toolchain.yaml's reason). The repository is public, so
  Actions artifact storage is not billed (Cc9; confirm once on the usage
  page): what remains is upload and download time, recorded per leg.
  (b) is a one-line change if it is ever needed.

**J. The conda build** (SD P5-J; amended (Cc1), (Cg7)).
- (a) ★ No zig/ when the prefix is the env (build.zig `prefix_is_env`),
  and no fetch: zig-toolchain.sh skips it by the same test, the prefix
  being the env by real path (`same_dir`, vendor-libs.sh's test moved
  to env.sh). build.zig decides what is installed; bash only whether to
  download; each comment cites the other.
- (b) Declare R_TOOLCHAIN_PREFIX conda-only from phase 5 (skip the fetch
  whenever it is set) and change env.sh's, package-standalone.sh's and
  unpack-toolchain.sh's comments.
- Reason for (a): B30's boundary; conda keeps conda-forge's zig and the
  conda build reaches no PyPI. (b) would silently break a non-env
  override, which would then stop in build.zig's addFail step.

**K. osx-64's upstream zig** (SD P5-K).
- (a) ★ CI's macos-15-intel leg (full-ci) is the osx-64 test (the mixed
  case); omicron tries the toolchain tree and verify-package under
  Rosetta, and a kill by the endpoint agent is recorded as such.
- (b) Add an upstream-zig osx-64 leg to upstream-zig.yaml.
- Reason for (a): the default leg already runs verify-package with
  TC/zig there; (b) is a workflow change for a case (a) covers except
  the one-zig build of R on osx-64.

**L. `-lmsvcrt` with upstream zig on Windows** (SR §4).
- (a) ★ Record it as an open item; on kappa test magick (its bundle's
  librsvg holds Rust's std) with TC/zig in an extracted bundle, and one
  Rust package if cargo is there; add a `mingw_names` mapping only if a
  real package needs it.
- (b) Map `msvcrt` to `c` in `mingw_names` now for both zigs: fixes
  upstream's failure and conda-forge's msvcrt.dll in a UCRT process in
  one rule.
- Reason for (a): no R package is known to reach `-lmsvcrt` through
  rzig; a rule nobody needs is a rule to keep. If the test finds one,
  (b) is the fix, recorded with the test. The test runs in step 3b,
  before step 5's conda and build-number chains, so a mapping it leads
  to never makes those runs stale (Cg3).

**M. Build number** (B14 a).
- (a) ★ 11: phase 5 changes rzig, which r-zig-slim and the r-zig wheel
  carry, so conda contents change; SHLIB's is 10 (recipe.yaml, its
  PLAN.md), phase 4's 9. If another build publishes first, the one
  after universe's newest.
- Reason: B14 (a) bumps in each PR that changes a conda package's
  files. (The rzig survey's "12" read the task's "(11)" as SHLIB's
  number; the records say SHLIB is 10, and 11 is the number after it.)

**N. Two zigs sharing zig's default cache on a user's machine** (SR
§6, ST §1).
- (a) ★ Record it under "Later: zig's global cache", beside the
  pre-seeding menu; no rzig change in phase 5.
- (b) rzig sets ZIG_GLOBAL_CACHE_DIR per zig (a key like env.sh's) when
  none is set.
- Reason for (a): not seen to break a package; the menu that decides
  pre-seeding decides where rzig's zig keeps its cache too, once.

**O. How phase 5's diff is handed over** (stacked).
- (a) ★ The implementer writes `phase5/implementer/phase5-only.diff`:
  main exported (`git archive d11dee1`) into a scratch directory,
  `shlib-base.diff` applied and the baseline's untracked files copied
  in, then `diff -ruN` against the worktree for every path either
  touches; checked by applying it to a second scratch copy and
  comparing with the worktree. The user commits phase 4 and SHLIB
  first; the commands for phase 5's commit (and its PR after SHLIB's
  merges) are handed over with no trailer.
- (b) Hand over the worktree's whole diff and let the user split it.
- Reason for (a): three PRs in order, each with its own bump (B14 a);
  only read-only git is used.

**P. The minimal env's toolchain fetches zig too** (ST §4).
- (a) ★ Accept it: one tree per platform, one cached download;
  make-wheel.py takes only `usr/`.
- (b) Skip zig/ for minimal: a flavor rule in the platform's one tree
  (B30), which serves every flavor.
- Reason for (a): no flavor rule in a tree that has none.

**Q. Windows' `zig\zig.exe` in RZIG_PRINT_ARGV** (SR §1).
- (a) ★ verify-bundle asserts the zig through the check line (`/`
  only) on Windows; rzig is unchanged. Amended (Cg4): one more
  assertion on every OS, RZIG_PRINT_ARGV's first word with `\` turned
  into `/` equals `$pass_zig` (case-insensitive), so TODO's box is met
  literally on Windows too, with no OS branch.
- (b) find_zig's `inDir` joins with `/` on Windows.
- Reason for (a): Windows takes either separator, cache.zig's key
  already normalises it, and (b) changes every lookup's spelling.

**R. The mixed case's notes** (SR §2, §3, §5).
- (a) ★ Record in PLAN's phase 5 record without a change: CC_VER says
  conda-forge's clang 21.1.8 where TC/zig is 21.1.0 (the TODO "Later"
  item fixes CC_VER from the zig that builds R); an inherited
  ZIG_LIB_DIR reaches TC/zig; a build runner per extraction place.
- (b) Fix CC_VER in phase 5.
- Reason for (a): cosmetic, already a TODO item, and it is the build's
  side, not the compilers group's.

**S. The build pass and the zig-independent blocks** (new, (Cg1)).
- (a) ★ The build pass skips scenario 1 (the base alone) and the no-zig
  preflight check, with one note line each; everything else runs in
  both passes.
- (b) The build pass runs the whole script, as the planner's F (a)
  wrote it.
- Reason for (a): those two blocks pass no `zig_env`, so the second run
  tests nothing new; one `[ "$pass" = toolchain ]` each, no block moved.
  The no-zig check then also moves zig aside only once.

**T. The toolchain artifact's compression** (new, (Cc9)).
- (a) ★ No workflow step changes in phase 5; `compression-level: 0` on
  toolchain.yaml's upload goes to "Later and future checks" with the
  measured step times.
- (b) Add `compression-level: 0` now (one line: the archives are
  already .tar.gz/.zip, so the size stays and the CPU time goes).
- Reason for (a): the plan's "no workflow step changes"; the saving is
  seconds and is measured first (Cc7's step times).
