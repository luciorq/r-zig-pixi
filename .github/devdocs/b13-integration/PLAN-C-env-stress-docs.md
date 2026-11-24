# b13 integration, group C: env, stress, docs

Worktree wt/build13 (branch build13), 2026-11-24. Files: pixi.toml,
pixi.lock, .github/workflows/, python/, stress/, README.md,
chore-release-12/BACKLOG.md, b13-integration/CI-WAVE.md.

## Needs

| need | state | what |
|---|---|---|
| b13-build N1 | applied | pixi.toml `fetch = "bash scripts/zig-build.sh fetch"`; rzig-test comment without the shim parity text; build-r.yaml's rzig-tests comment the same |
| b13-build N2 (M-7) | applied | `[feature.openblas]` gains win-64, comment rewritten; `pixi lock`; build.yaml build-full gains a windows-latest openblas leg (`-- --verbose`, 90 min, as the other windows-latest legs), header/leg counts 20 -> 21, 13 -> 14; build-r.yaml runs verify-tree for openblas too (the task asked for build, verify-tree and smoke; before, openblas skipped verify-tree) |
| b13-build N6 | applied | gen-config.yaml push paths + `zigbuild/tools/rzig/build.zig` |
| b13-env-ci need 0 | applied | scratch-b13-env-ci/r_zig-init.diff (`git apply`, clean) |
| b13-stress N3 | applied in part | `libs_smoke` input -> STRESS_LIBS_SMOKE -> `--libs-smoke=REF`. `no_rtools_libs` skipped: b13-env-ci already added `rtools_libs` (boolean, default true; false passes `--no-rtools-libs` and skips the Rtools45 cache step), the same switch; two inputs for one flag would be a trap. CI-WAVE uses `rtools_libs=false`. stress.R reads both as the PLAN says (`known` has no-rtools-libs and libs-smoke; opt() takes `--libs-smoke=REF`) |
| b13-env-ci need 2 (CI7 magick SVG) | skipped, already covered | b13-stress's `@magick.R` smoke renders an SVG through librsvg on Windows (20x10) and checks rsvg; env-ci's one-line form would also run on linux/macOS, where conda's ImageMagick may lack rsvg |
| b13-env-ci need 3 (CI6 rstan verbose) | skipped, already covered | b13-stress's `@rstan.R` traces inline's compileCode and prints its whole R CMD SHLIB output, with `rzig build: R CMD SHLIB, tier 1` under --trace (b13-stress F8, delta); `verbose = TRUE` would add only noise |
| b13-rzig rstan note | applied | appended to the rstan row's note (10 fields, ASCII) |
| b13-hosts N2 | applied | stress.R prints `stress: Rtools45 tree extracted with <tool>` before the break |
| docs | applied | README: r-zig-tcltk add-on (not win-arm64), variants table note, M-27 sentence, R_ZIG_TOOLCHAIN_ENV and R_ZIG_SYSTEM_LIBS (from main.zig's header), Windows wheels, openblas on windows-latest in CI, `build` fetches with zig build fetch; stress/README: rtools_libs and libs_smoke inputs |
| BACKLOG | applied | "Build 13 wave 1" status block; b13 state on each touched row |
| CI-WAVE.md | written | 1 build.yaml dispatch (full tier + CI9 in one) or the full-ci label, 4 stress dispatches |

## For other owners

- fetch-r.sh / toolchain shims, left: zigbuild/tools/rzig/test.sh (still
  calls parity-test.sh, which is now deleted, and its header names the
  shims), smoke-test.sh:14-19, 39 (`$here/../../../toolchain` under
  `set -e`), 130-132; doc comments main.zig:2, linker_args.zig:24,
  cmdline.zig:1, Ctx.zig:31 (b13-build N3, rzig owner). Root PLAN.md:152
  and 158 describe fetch-r.sh and the shims as current (history record;
  docs owner if wanted). zigbuild/tools/fetch.zig:2, 21 and
  configure-only.sh:147 name them as history only (fine).
- Blocking, b13-build owner (zigbuild/tools/fetch.zig): Windows panic
  in setMtimes, see the tests below.
- Blocking, scripts/verify-tree.sh owner: line 390's expected
  R_ZIG_TOOLS_PATH line vs build.zig:2905's new one.
- b13-recipe N2 (scripts/conda-consume.sh: tcltk env), N3 (`iconv -l`
  on Windows): not this group's files.

## Lock

- sha256 before 48227fb455716269, after befa3d7cd2476b17.
- Package lists (env, platform, URL from every lock entry) before and
  after: only `openblas win-64` (90 entries) and `full-openblas win-64`
  (94) are new; every other env/platform list is identical (diff of the
  lists without those two: empty). Against default/full win-64 they add
  exactly libopenblas 0.3.34 pthreads_h952cde7_2 and openblas 0.3.34
  pthreads_h1c64c9f_2; no removed package entry. `pixi lock --check`
  up to date (gamma, delta).

## Tests

| where | command | result |
|---|---|---|
| gamma | `pixi exec -s actionlint -s shellcheck actionlint .github/workflows/*.yaml` | clean |
| gamma | parse stress.R; packages.tsv fields (10) and ASCII; pixi.toml TOML parse; r_zig/__init__.py ast parse | ok |
| delta (build13-C-env-stress-docs) | `pixi lock --check`; `pixi run fetch` from nothing; `build -j16`, `verify-tree`, `smoke`; `-e openblas` build, verify-tree, smoke | all 0; "installed tree verified (linux/slim)", "(linux/slim-openblas)"; libRblas.so/libRlapack.so in both trees |
| kappa (win-64, rz-b13int-C, removed after) | `pixi run -e openblas build -- --verbose` | run 1: fetch.zig panics, `TODO implement dirSetTimestamps windows` (fetch.zig:255 setMtimes; tree extracted, no stamp); with the empty stamp written by hand: run 2 stopped at `iconv -l` not found (b13-recipe F10, pre-existing; hosted runners have Git's usr/bin); with Git's usr/bin on PATH: build 0 |
| kappa | `pixi run -e openblas verify-tree` | 1: "Rcmd_environ lacks: R_ZIG_TOOLS_PATH=..." (verify-tree.sh:390 vs build.zig:2905; not openblas-specific) |
| kappa | `pixi run -e openblas smoke` | 0, "Smoke test passed (windows/slim)" |
| kappa | Rscript with PATH = bin\x64 + System32: crossprod vs t(m) %*% m, solve() of 500x500 | ok; bin\x64 has openblas.dll, Rblas.dll, Rlapack.dll, VCRUNTIME140.dll |

Not run: the Windows wheel test with need 0 (b13-env-ci ran it on kappa
with the same diff); win-arm64; the new CI steps themselves.
