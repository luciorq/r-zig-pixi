# feat-zig-libs-universe: the zig-* packages from universe

## Goal

libs-zig-pixi published its zig-* static libraries (build 0) to universe
on 2026-11-23 (libs-zig-pixi M5, run 45198060836, m5/PLAN.md M5-F29).
r-zig-pixi takes them from there: the stress env has them on both Windows
platforms, and the pre-publish path (`--libs-channel`, the stress
workflow's `libs_run_id` download) goes away. This follows feat-zig-libs
(PR #51, M4), which tested the same builds from a libs-zig-pixi CI
artifact.

## Scope

- `pixi.toml`: zig-abseil, zig-gdal, zig-geos, zig-onetbb, zig-openssl,
  zig-proj in `[feature.stress.target.win.dependencies]`; `pixi.lock`.
- `stress/stress.R`: `--libs-channel` and `STRESS_LIBS_CHANNEL` removed;
  the zig-* special case in the `--conda` env's sysdeps removed; the
  report's zig-libs line on every Windows run.
- `.github/workflows/stress.yaml`: the `libs_run_id` and `libs_leg` inputs
  and the artifact download step removed.
- `stress/README.md`: the same.

Not in scope: `R_ZIG_FALLBACK_SOFT` (slice 2), the D77 leftovers.

## Decisions

| # | Question | Options | Chosen | Reason | Who, date |
|---|---|---|---|---|---|
| D1 | How r-zig-pixi takes the published zig-* packages | A one branch: stress env, `--libs-channel` and the workflow download removed, then a stress run on both Windows arches; B the same, `--libs-channel` kept for unpublished builds; C wait for prefix.dev's plain `repodata.json` | A | One path; libs-zig-pixi tests its own unpublished builds (CI test jobs, `tests/r/smoke.R`), and an artifact download needs a cross-repository token | user, 2026-11-23 (A was the recommended option; "CI finished and packages are published") |
| D2 | Where the zig-* specs go | A `[feature.stress.target.win.dependencies]` (win-64 and win-arm64); B the two per-platform tables | A | Both arches have every zig-* package; one list | default, 2026-11-23 |
| D3 | Which zig-* names | A the six named by `packages.tsv` sysdeps (abseil, gdal, geos, onetbb, openssl, proj); B all nine | A | zig-sqlite, zig-zlib and zig-expat come as their dependencies; the spec lists what the rows name | default, 2026-11-23 |
| D4 | `libgdal-core` (conda-forge, MSVC) in the win-64 stress env | A keep it; B remove it | A | No row names it on Windows after #51, but removing it is a separate change; rzig and `PKG_CONFIG_PATH` put zig-libs first, so it is not linked (I until the stress run) | default, 2026-11-23 |

## Findings

**F1 V. `stress.R` needed no new logic.** The `--conda` env leaves out a
sysdep only when the libraries env is the stress env and lacks it
(`setdiff(needed, env_pkgs(libs))`); the zig-* special case existed only
because no channel had them before M5. With the zig-* packages in the
stress env, that general rule covers them, and universe is already in the
conda env's channels.

**F2 V. Lock.** `pixi lock` (pixi 0.84.2) added 18 entries and removed
none (`git diff --text pixi.lock`: 0 `-` lines): stress:win-64 and
stress:win-arm64 each get zig-abseil, zig-expat, zig-gdal, zig-geos,
zig-onetbb, zig-openssl, zig-proj, zig-sqlite and zig-zlib at the
published build strings (win-64: gdal `zig_85e8ffa_0`, ...; win-arm64:
gdal `zig_8d757d0_0`, ...). No other environment changed. `pixi lock
--check`: ok. Lock sha256 a4ae1990b010.

**F3 I. prefix.dev's plain `repodata.json`.** At 2026-11-23 16:32Z (one
minute after the upload) no subdir's `repodata.json` listed the zig-*
packages; later win-64's listed its 9, win-arm64's and linux-64's none.
pixi reads the sharded index, which had all of them, so the lock solved.

## Tests

gamma, 2026-11-23: `parse("stress/stress.R")`: ok; `stress.yaml` loads as
YAML; `pixi lock --check`: ok.

Not run: any stress run. The Windows tree legs have zig-libs in their
libraries env for the first time (feat-zig-libs tested conda legs only).

## Next steps

1. The user commits, pushes and opens the PR.
2. A stress run on both Windows arches, tree and conda:
   `gh workflow run stress.yaml --ref feat-zig-libs-universe -f oses='["windows-latest","windows-11-arm"]' -f packages='g2 g3 g4' -f distribution=both -f trace=true`;
   read every row; the zig-libs column must name the universe builds.
3. Then the full set on Windows, as feat-zig-libs finding 20.
