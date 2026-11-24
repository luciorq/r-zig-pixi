# Build 13 integration

Worktree wt/build13, branch build13 from docs-release-12 229cd9f; all work
uncommitted (2026-11-24). Lock sha256 befa3d7cd2476b17.

## Topics merged

b13-rzig, b13-build, b13-env-ci, b13-recipe, b13-stress, b13-hosts,
b13-design; each record in `.github/devdocs/<topic>/PLAN.md` with its
"Needs from other topics".

## Needs applied, per group

| group | files | record | summary |
|---|---|---|---|
| A build-recipe | build.zig, zigbuild/{toolchain,make}, recipe/, conda-consume.sh, vendor-libs.sh, verify-toolchain.sh | [PLAN-A-build-recipe.md](PLAN-A-build-recipe.md) | all but F11 (no output uses host requirements) and N3 (`iconv -l`, open); zig-built GNU make in the unix build-tools group; r-zig-tcltk; Windows R_ZIG_TOOLS_PATH + R_ZIG_TOOLCHAIN_ENV |
| B rzig | zigbuild/tools/rzig/ | [PLAN-B-rzig.md](PLAN-B-rzig.md) | all five: parity-test.sh gone (check cases kept as check-test.sh), Windows pip lines, `(zig)` in the `-l` trace, ar.zig comment, `--disable-auto-import` dropped, windres seen by meson |
| C env-stress-docs | pixi.toml/lock, workflows, python/r_zig, stress/, README, BACKLOG | [PLAN-C-env-stress-docs.md](PLAN-C-env-stress-docs.md) | all but `no_rtools_libs` (b13-env-ci's `rtools_libs` covers it) and b13-env-ci needs 2/3 (stress smoke files already do them); openblas on win-64; CI wave plan [CI-WAVE.md](CI-WAVE.md) |
| chain | leftovers, two Windows blockers | [PLAN-chain.md](PLAN-chain.md) | fixes X1-X5 below; full linux chain; Windows wheel test |

## Chain results (delta linux-64; kappa for the Windows wheel)

| step | command | result | time |
|---|---|---|---|
| lock | `pixi lock --check` | ok | 0 s |
| fetch | `pixi run fetch` | ok (again after X5: 36 s) | 122 s |
| rzig, conda-forge zig | `pixi run rzig-test` | 238/238, check-test 60/0 | 103 s |
| rzig, upstream zig | `ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test` | 238/238, check-test 60/0 | 185 s |
| toolchain | `pixi run toolchain`, `verify-toolchain` | ok, ok | 32 s, 6 s |
| build | `pixi run build` | ok (again after X5) | 141 s |
| verify-tree | `pixi run verify-tree` | ok | 18 s |
| smoke | `pixi run smoke` | passed | 1 s |
| contract | `pixi run contract` | passed | 151 s |
| pkg-parity | `pixi run pkg-parity` | verified | 126 s |
| hermetic | `pixi run hermetic` | verified | 6 s |
| package | `pixi run package-toolchain`, `verify-package` | ok; build-tools scenario ran the zig-built GNU Make 4.4.1 | 88 s, 96 s |
| conda | `pixi run -e pkg conda-package` | 7 packages `_13` incl. r-zig-tcltk; build-tools holds `usr/bin/make` + SOURCES; all tests | 394 s |
| minimal | `pixi run -e minimal build`, `verify-tree`, `toolchain` | ok | 111 s, 18 s, 4 s |
| wheel (linux) | `pixi run -e wheel wheel`, `wheel-test` | 4 manylinux_2_17 wheels, passed | 10 s, 28 s |
| wheel (win-64, kappa) | `pixi run --frozen -e wheel wheel-test` on wheels from the CI build-12 win-64 tree with build13's rzig, make-wheel.py and r_zig | passed | 133 s |

## Fixes made in integration

- X1 `scripts/pkg-parity.sh`: stale parity-test.sh comment.
- X2 `scripts/verify-tree.sh`: Windows R_ZIG_TOOLS_PATH line now matches
  build.zig's (`;${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin`). Blocked every
  Windows verify-tree.
- X3 `zigbuild/tools/rzig/check.zig`: notOnPath doc (unix make is the
  group's own now).
- X4 root `PLAN.md`: dated notes on the fetch and shim bullets.
- X5 `zigbuild/tools/fetch.zig`: Windows sets file times through an open
  handle (zig 0.17.1's `Dir.setTimestamps` panics there); directories keep
  their extraction time on Windows. Blocked every Windows fetch (no stamp,
  re-fetch every run). Tested on kappa and delta.

## Open items for the CI wave

1. Nothing ran on macOS (omicron) or win-arm64 after integration; the
   Windows R tree itself (build, verify-tree with X2, conda-package win-64
   incl. r-zig-tcltk) is first tested by the wave.
2. b13-recipe N3 / F10: `iconv -l` on Windows needs Git's tools on PATH
   (hosted runners have them; kappa did not). Open, unchanged.
3. b13-recipe F11 skipped: r-zig-recommended pins r-zig-slim in `run`
   only; a win-64 conda build would show whether host pinning matters.
4. rzig windres writes no depfile under meson (zig rc cannot): a header
   change in a `.rc` include does not rebuild the resource.
5. Stress cannot express CI5's full/openblas variants (it builds slim).
6. Upstream zig for build and conda-package: only rzig-test ran with it
   here; the `upstream-zig` label covers the rest.
7. Group A's suggestion: an rzig hint naming R_HOME's `usr/bin/make` when
   rzig runs outside R (not done).
8. The wave itself: [CI-WAVE.md](CI-WAVE.md) (one build.yaml dispatch with
   `linux_runner=ubuntu-26.04` or the `full-ci` label, plus
   `upstream-zig`; stress S1-S4).

## User decisions pending

1. **L4 (native Windows build tools)**, b13-design L4-M: (a) keep MSYS2;
   **(b) recommended**: native busybox-w32 + zig make as an opt-in in build
   13, default later, land the 0016 patch; (c) switch the default now;
   (d) only the 0016 patch and zig make now.
2. **L5 (binary repository)**, b13-design L5-M: (a) none; **(b)
   recommended**: curated linux repository (P3M layout, GitHub Release
   assets); (c) (b) plus an R patch for a linux binary pkgType; (d) rely
   on Posit P3M.
3. **L9 rzig pkg-config mode** (b13-rzig D5): (a) minimal mode in rzig
   now (about 400 lines); **(b) recommended**: design record only, pkgconf
   keeps serving.
4. **b13-hosts N3, unactivated R.exe on Windows cannot start**: (a)
   **recommended**: document "activate, or put `<env>\Library\bin` on
   PATH" in README; (b) the front R.exe/Rscript.exe prepends
   `<R_HOME>\..\..\bin` to PATH.
5. **b13-recipe Q20**: (a) **recommended**: send the drafted note to
   flang-pixi (23.1.1 zig-0.16 set still pinned by r-zig 4.6.1 builds;
   the zig-0.17 23.1.1 set by none) and keep r-zig 4.6.1 builds; (b) also
   delete the r-zig 4.6.1 builds from universe, freeing the retained
   flang set; (c) do nothing now.

Suggested commit (chain group's own fixes):
`fix: set file times on Windows through a handle in fetch, match the Windows tools path in verify-tree`

## User decisions (2026-11-24)

| id | question | choice | follow-up |
|---|---|---|---|
| U1 | L4 native Windows build tools without MSYS2 | b: busybox-w32 plus zig-built make as an opt-in in build 14, default later (b13-design) | build 14 |
| U2 | L5 binary package repository | b: a curated linux repository, CRAN-like layout on GitHub Release assets (b13-design) | build 14 |
| U3 | L9 rzig pkg-config mode | b: design record only; pkgconf keeps serving (b13-rzig D5/F7) | none |
| U4 | unactivated R.exe on Windows (b13-hosts F4/N3) | b: R's front ends put the env's DLL dir (`<R_HOME>\..\..\bin`, when it exists) first on PATH | implemented in this PR (b13-hosts PLAN, Decision 4b) |
| U5 | Q20 flang-pixi note and r-zig 4.6.1 builds | a: note sent to the flang-pixi session (2026-11-24, b13-recipe F11 text); r-zig 4.6.1 builds stay on universe | none |
