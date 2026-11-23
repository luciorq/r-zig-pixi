# chore-env-ci

Goal: the env and CI items of the build 12 backlog (chore-release-12/BACKLOG.md): Q10, Q11, Q12, Q13, Q15, Q16, Q19, M-3 (env half), M-4, M-5, D10.
Branch chore-env-ci from main 3395a08. Lock regenerated on delta (pixi 0.84.2), copied back to gamma.

## Decisions

All defaults, taken by me under the user's batch approval (2026-11-23).

| # | Question | Chosen | Reason |
|---|---|---|---|
| 1 | Q10: how one task takes the subdir | pixi task `args = ["subdir"]`, `dist/conda/{{ subdir }}/*.conda`; build.yaml passes `${{ matrix.name }}` (its names are the subdirs) | No glob over dist/conda/, so the old guarantee (never another platform's or broken/ packages) holds; no default, so a bare call stops |
| 2 | Q12: which tables | expat, fontconfig, freetype moved to `[target.unix.dependencies]` and to the recipe's `if: unix` (staging host and r-zig-slim run); stress env keeps freetype and fontconfig on all six | Unused by R on Windows (F1). The stress copies serve systemfonts, textshaping and ragg rows, which have no @os |
| 3 | Q13: openblas on Windows | `[feature.openblas] platforms` = the four unix subdirs; comment rewritten | buildWindows ignores -Dblas (F2). Making it work stays M-7 |
| 4 | Q16: which pin | actions/cache@v6 | The repo pins actions/* at their newest major (checkout v7, upload-artifact v7, download-artifact v8 are each the latest release's major); cache's latest is v6.1.0. v6.0.0's only change: package updates and an ESM move |
| 5 | Q19: lift the icu pin | No, keep `icu: '78'`; dated note added to variants.yaml | No libxml2-16 build for icu 79 on any subdir (F4) |
| 6 | M-3: protoc source on win-arm64 | libprotobuf moved to the unix and win-64 stress tables | The task's rule (the tree has protoc.exe: F5). With no protoc on PATH, protolite's Makevars.win takes protoc, headers and lib from one source, r-windows' protobuf 21.12 clang-aarch64 bundle (F6). Not: putting the tree's bin/ on PATH (a stress.R change, outside this batch) |
| 7 | M-4: which runners | all six (adds ubuntu-24.04-arm, macos-15-intel, windows-11-arm) in both the toolchain and build matrices of upstream-zig.yaml; windows-11-arm as build.yaml's (--verbose, 150 min) | Artifact names are runner.os/runner.arch (toolchain) and inputs.os (standalone), so the six do not collide |
| 8 | M-5: which legs | New build-r.yaml input `recommended` (boolean, default false); build.yaml's `build` job sets it for the default (slim) leg of each of the six runners when the run is in the full tier (dispatch or `full-ci`); step after `check`: `recommended` then `verify-recommended` | slim is the flavor r-zig-recommended is built for; build-full has no default leg, so the core job carries it, gated to the full tier |
| 9 | D10: which uploads get compression-level 0 | toolchain.yaml's group archives (.tar.xz/.tar.gz/.zip), build-r.yaml's standalone base (.tar.gz/.zip) and the wheel (.whl, a zip) | Already compressed. Not: stress logs and gen-config's config dirs (text, compresses well) |

## Findings

- F1 (V) Nothing in Windows R uses expat, fontconfig or freetype. `grep -rniE 'fontconfig|freetype|expat' zigbuild/config/win-*` gives nothing. zigbuild/cairo.zig:12-14 says no FreeType or fontconfig: R picks its fonts through GDI. build.zig:3726 `shipsFonts` is `ctx.os != .windows and ...`. Rendering the recipe after the change (`rattler-build build --render-only --target-platform <p>`) names expat/fontconfig/freetype 13 times each on linux-64 and 0 times on win-64 and win-arm64. Stale text left alone: build.zig:3573 still says "the tree ships the DLLs cairo imports and nothing else of fontconfig's".
- F2 (V) buildWindows (build.zig:1062-1898) never reads `ctx.blas`. The only reads are at :275, :284, :708, :806 and :840, all in the unix path after `if (os == .windows) return buildWindows(...)` (:641). It always compiles src/extra/blas into Rblas.dll (:1125-1126).
- F3 (V) Lock diff (old lock against new, per env and platform; script on delta). Only removals, no version moved anywhere:
  - default, full, pkg (win-64, win-arm64): -expat, fontconfig, freetype, libfreetype, libfreetype6; default and full also -libexpat
  - openblas, full-openblas: win-64 (96 and 100 packages) and win-arm64 (84 and 88) removed
  - stress win-64: -libgdal-core 3.13.3 and its closure (freexl, libarchive, libkml, librttopo, libspatialite, lzo, minizip, muparser, uriparser, xerces-c, expat)
  - stress win-arm64: -libprotobuf 7.36.2, libabseil 20260817.0, expat
  - minimal: unchanged (`minimal-check`: none on the deny-list, all six)
- F4 (V) icu 79: in a scratch workspace with `libxml2-16 = "*"`, `icu = "79.*"` and one platform at a time, `pixi lock` finds no solution on linux-64, linux-aarch64, osx-64, osx-arm64, win-64 and win-arm64. `pixi search -p <p> libxml2-16`: 2.15.4 _1 needs `icu >=78.3,<79.0a0` (delta, 2026-11-23).
- F5 (V) The Rtools45 aarch64 tree (stress.R's pinned URL; sha256 64dceac9…e9e8b5 matches) ships `bin/protoc.exe`, 278 files under `include/google/protobuf/`, `lib/libprotobuf.a`, `lib/libprotoc.a` and `lib/pkgconfig/protobuf.pc` (`tar --zstd -tvf`, delta).
- F6 (I) protolite 2.4.0's src/Makevars.win uses `pkg-config protobuf` flags only when `protoc --version` is non-empty. Otherwise it downloads r-windows' protobuf-21.12-clang-aarch64 bundle (tools/winlibs.R) and runs that bundle's protoc. stress.R puts neither the tree's bin/ nor anything else with a protoc on PATH (stress.R:460-464), so on win-arm64 protolite now takes the bundle. stress.R's warning lists libprotobuf among the sysdeps missing from the env (stress.R:381-382; libprotobuf is not in rtools_has, :569). The row's expect is not changed to `?`: stress.R:883 does that only for zig-* sysdeps (row_zig, :843-848), so windows-aarch64=fail-package stays and a passing protolite shows as unexpected until test-stress-rows (B5) updates the row (review R1).
- F7 (V) packages.tsv names libgdal-core only as `@linux`/`@macos` (sf, terra, gdalraster); Windows takes zig-gdal (awk over column 5).

## Review (adversarial pass, 2026-11-23)

- R1 (V) F6's "expect `?`" claim was wrong; corrected above (stress.R:883 reads row_zig, which keeps only `zig-*` names).
- R2 (V) build-r.yaml's new recommended step had no `shell:`; on Windows the default pwsh runs `verify-recommended` after a failed `recommended` and takes only the last exit code. Fixed: `shell: bash` (as the fetch-zig step, build-r.yaml:88).
- R3 (V) stress/README.md:17 listed the win-arm64 stress env's missing libraries without libprotobuf; added.
- Checked, no change: lock diff re-derived independently (old lock from HEAD against new, per env/platform; delta): identical to F3. actions/cache latest is v6.1.0 (`gh api repos/actions/cache/releases/latest`). protolite 2.4.0 Makevars.win and tools/winlibs.R read (delta scratch copy): F6's bundle path holds. fetch-zig.sh has wheels for linux-aarch64, osx-64 and win-arm64 (M-4). conda-publish now in `[feature.pkg.tasks]`; nothing else names the six old tasks or require_not_windows.

## Tests

| What | Where | Result |
|---|---|---|
| `pixi lock` (old lock kept as preference) | delta, ~/rz/wt/chore-env-ci | ok; diff F3; lock sha256 eb5833cf…c814a7 copied to gamma |
| `pixi lock --check` | delta | up to date |
| `pixi run -e minimal minimal-check` | delta | none on the deny-list, all six |
| Task args: the same task with `echo` in a scratch workspace | delta | `conda-publish linux-64` expands to the two files; without an argument: "no value provided for argument 'subdir'", exit 1 |
| YAML parse of .github/workflows/*.yaml and recipe/variants.yaml | delta | ok |
| `actionlint` 1.7.12 with shellcheck (`pixi exec`) | delta | no findings, exit 0 |
| `bash -n scripts/env.sh` | delta | ok |
| `rattler-build --render-only` for linux-64, win-64, win-arm64 | delta | F1 |
| After the review fixes: `pixi lock --check`, actionlint + shellcheck, YAML parse, `bash -n scripts/env.sh`; lock sha256 on delta and gamma | delta | all ok; eb5833cf…c814a7 on both |

## Not verified

- M-5's step on CI (six runners, full tier). The recommended build on Windows and macOS in a build-r leg has not run (conda-package builds it).
- M-4's three new upstream-zig legs: need a dispatch or the `upstream-zig` label.
- M-3 on windows-11-arm: protolite through r-windows' bundle (zig libc++ against the bundle's LLVM libc++ libprotobuf.a), and the bundle download from GitHub inside the stress run. packages.tsv's windows-aarch64 expect (fail-package) is unchanged until a stress run.
- Q11/Q12 on Windows: the core tier's Windows legs and conda-package win-64/win-arm64 show whether anything needed the removed packages.
- D10 time saved: not measured.

## Backlog items closed

Q10, Q11, Q12, Q13 (comment and envs; the Windows openblas work stays M-7), Q15, Q16, Q19 (recorded, pin kept), M-3 (env half), M-4, M-5, D10.
