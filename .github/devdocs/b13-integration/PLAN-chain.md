# Build 13 integration, group chain (leftovers, full linux chain, Windows wheel)

Applied to the build13 worktree, uncommitted (2026-11-24). Lock sha256
befa3d7cd2476b17 (unchanged by this group).

## Leftover review

`git status --short`, `git diff --stat` (57 files, +1772/-2608 before this
group), grep for `fetch-r.sh`, `toolchain/zig-*`, `parity-test.sh` and
conflict markers outside .github/devdocs and stress/results.

| item | state |
|---|---|
| conflict markers | none |
| `zigbuild/tools/rzig/test.sh` calling parity-test.sh (C's report) | already fixed by group B (runs check-test.sh) |
| `smoke-test.sh` and the removed root `toolchain/` (C's report) | already fixed: it uses `$root/lib/R/bin/toolchain` |
| `scripts/pkg-parity.sh:275` names parity-test.sh | fixed (X1) |
| root `PLAN.md` (milestone 5 record) presents fetch-r.sh and the shims as current | fixed (X4): a dated "Build 13" note on both bullets; the record stays historical |
| `check.zig` notOnPath doc says unix make is conda-forge's (A's open 2) | fixed (X3) |
| `fetch.zig:21` mentions fetch-r.sh | kept: historical ("as fetch-r.sh accepted") |

## Fixes made

| id | file | fix | why |
|---|---|---|---|
| X1 | scripts/pkg-parity.sh | comment: parity-test.sh -> check-test.sh | file deleted (b13-build N3); check-test.sh's `no_root` checks the root |
| X2 | scripts/verify-tree.sh:390 | Windows `R_ZIG_TOOLS_PATH` line ends with `;${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin` | blocker from groups A and C: build.zig:2905 writes it (b13-rzig), verify-tree failed on kappa |
| X3 | zigbuild/tools/rzig/check.zig | notOnPath doc: unix make is the group's own in R_HOME/bin/toolchain/usr/bin since build 13 | b13-build N5 |
| X4 | PLAN.md | two dated notes (fetch, shims) | stale |
| X5 | zigbuild/tools/fetch.zig | new `setTime`: on Windows open the file `.write_only` and use `File.setTimestamps`; directories keep their extraction time on Windows; elsewhere `Dir.setTimestamps` as before | blocker from group C: zig 0.17.1's `Dir.setTimestamps` panics on Windows (`TODO implement dirSetTimestamps windows`), so no `.r-zig-patches` stamp and a re-fetch every run. A directory handle from zig's `openDir` has no FILE_WRITE_ATTRIBUTES, and `openFile` on a directory gives IsDir |

X5 tests: kappa, fetch.exe cross-built (x86_64-windows-gnu, conda-forge zig
0.17.1) on the R 4.6.2 tarball: first try (directories too) `error: IsDir`;
final version "Done.", rc 0, `.r-zig-patches` present, NEWS.Rd's time
2026-10-19 22:15:01 UTC (the tarball's), configure's 2026-10-29. gamma
(linux build of the same file): same NEWS.Rd time, `src/` directory keeps
its tar time. delta: `pixi run fetch` from nothing, then build, verify-tree,
smoke again (row 21-23 below). `zig fmt --check` clean on fetch.zig and
check.zig.

## Chain (delta, linux-64, ~/rz/wt/build13, conda-forge zig 0.17.1 unless said)

| # | step | command | result | time |
|---|---|---|---|---|
| 1 | lock | `pixi lock --check` | ok | 0 s |
| 2 | fetch | `pixi run fetch` | ok | 122 s |
| 3 | rzig, conda-forge zig | `pixi run rzig-test` | 238/238 unit, check-test 60/0, link-objects ok | 103 s |
| 4 | rzig, upstream zig | `ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test` | same counts | 185 s |
| 5 | toolchain | `pixi run toolchain` | ok | 32 s |
| 6 | | `pixi run verify-toolchain` | ok | 6 s |
| 7 | build | `pixi run build` | ok | 141 s |
| 8 | | `pixi run verify-tree` | ok | 18 s |
| 9 | | `pixi run smoke` | "Smoke test passed (linux/slim)" | 1 s |
| 10 | contract | `pixi run contract` | "Contract test passed (slim/linux)" | 151 s |
| 11 | | `pixi run pkg-parity` | "pkg-parity verified (linux/slim)" | 126 s |
| 12 | | `pixi run hermetic` | "hermetic tier 0/1 verified" | 6 s |
| 13 | | `pixi run package-toolchain` | ok | 88 s |
| 14 | | `pixi run verify-package` | all four scenarios; build-tools ran the group's GNU Make 4.4.1 (`lib/R/bin/toolchain/usr/bin/make`) | 96 s |
| 15 | conda | `pixi run -e pkg conda-package` | 7 packages incl. r-zig-tcltk `_13`; r-zig-build-tools holds `lib/R/bin/toolchain/usr/bin/make` + `usr/SOURCES`; 7 test summaries | 394 s |
| 16 | minimal | `pixi run -e minimal build` | ok | 111 s |
| 17 | | `pixi run -e minimal verify-tree` | ok | 18 s |
| 18 | | `pixi run -e minimal toolchain` | ok | 4 s |
| 19 | wheel | `pixi run -e wheel wheel` | 4 manylinux_2_17 wheels | 10 s |
| 20 | | `pixi run -e wheel wheel-test` | "wheel test passed" | 28 s |
| 21 | after X5 | `rm -rf build/R-4.6.2; pixi run fetch` | ok, tar times kept | 36 s |
| 22-23 | after X5 | `pixi run build`, `verify-tree`, `smoke` | ok | 164 s |

Logs: delta `~/rz/b13int-chain/<n>-<step>.log`, runner `~/rz/b13int-chain.sh`.

## Windows wheel (kappa, scratch rz-b13int-chain, deleted afterwards)

Inputs: the CI win-64 minimal tree and toolchain build-tools zip of run
45381914199 (scratch-b13-env-ci/art; build 12 trees), with every rzig
`.exe` in `Library/lib/R/bin/toolchain` replaced by build13's rzig
cross-built on gamma (`zig build -Dtarget=x86_64-windows-gnu
-Dr-version=4.6.2`; cfguard.o identical), wheels written by build13's
make-wheel.py and python/r_zig. On kappa `pixi run --frozen -e wheel
wheel-test` (build13 pixi.toml/lock, scripts/wheel-test-windows.py,
recipe/*.R): "wheel test passed", rc 0, 2 min 13 s; the preflight prints
the new Windows pip lines. Limit: R's own files (etc/Rcmd_environ with the
new R_ZIG_TOOLS_PATH ending, Renviron) are build 12's; the CI wave's
Windows minimal legs cover the build13 tree.

Not run: macOS (omicron), win-arm64, upstream zig for build/conda-package.
