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
| D5 | protolite on windows-aarch64: "Protobuf C++ gencode is built with an incompatible version" (F5) | A expect `windows-aarch64=fail-package` with the cause in the row's note; B fix it here (protoc from the Rtools tree, or the env's protobuf .pc first); C leave it unexpected | A | Not caused by this branch (F5); a fix belongs with the Rtools fallback work (slice 2) | default, 2026-11-23 |

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

**F3 V. prefix.dev's plain `repodata.json` lags the upload.** At
2026-11-23 16:32Z (one minute after the upload) no subdir's
`repodata.json` listed the zig-* packages; later win-64's listed its 9,
the others none; at 16:44Z (about 13 minutes after) all of them: win-64
9, win-arm64 9, linux-64 1 (zig-toolchain). pixi reads the sharded index,
which had all of them at once, so the lock solved meanwhile.

**F4 V. Stress 45219870330, windows-latest / tree (g2 g3 g4, conda-forge
zig, trace).** The first tree leg with zig-libs: zig-libs
`.pixi/envs/stress/Library/zig-libs/x86_64-windows-gnu` with the nine
universe builds (zig-gdal `zig_85e8ffa_0`, ...). Targets: 6
install-failed, 25 ok, 1 skipped; Unexpected 0; dependencies: 1
install-failed, 64 ok. sf, terra, gdalraster, lwgeom and s2 ok; each row's
zig-libs column names the universe builds, every `-l` for gdal, proj,
geos, sqlite3, expat, z, tbb12 (terra), abseil, ssl and crypto (s2) from
zig-libs, none from a fallback. Non-ok rows, all as expected: hdf5r
(`off_t` against `HDoff_t`, fail-package), gsl (LoadLibrary,
fail-upstream), igraph (`libxml/globals.h`, fail-sysdep), Rhdf5lib
(`FLT16_MAX`, fail-package), protolite and arrow (MSVC C++ libraries,
fail-abi), Rsamtools skipped (Rhtslib, fail-dependency).

**F5 V. Stress 45219870330, windows-11-arm / tree.** zig-libs
`aarch64-windows-gnu` with the nine universe builds (zig-gdal
`zig_8d757d0_0`, ...); the Rtools45 fallback for glpk, gmp, gsl,
harfbuzz, hdf5, libnetcdf, libpq, mpfr, nlopt, udunits2 (libgdal-core no
longer: zig-gdal serves it). Targets: 3 install-failed, 29 ok;
Unexpected 1; dependencies: 65 ok. sf, terra, gdalraster, lwgeom and s2
ok, every library `-l` from zig-libs; from the fallback tree only system
and runtime names (ws2_32, psapi, ole32, shell32, c++, m; the reporting
quirk of feat-zig-libs). Rhdf5lib (`FLT16_MAX`) and arrow (x64 objects in
libarrow_dataset.a) as expected. protolite (!): expect fail-abi, result
fail-package: "Protobuf C++ gencode is built with an incompatible version
of" in `geobuf.pb.h`. Its `Makevars.win` (protolite 2.4.0) takes the
headers from `pkg-config protobuf`, which finds the Rtools45 tree's
closed `.pc` first (`-I .../include-pinned`), and runs `protoc` from
PATH ("libprotoc 36.2"; the stress env's conda-forge libprotobuf 7.36.2,
I). zig-libs has no protobuf, and its include directory comes after both
(`-idirafter`), so this branch does not cause it. None of the five
earlier windows-11-arm tree reports on hand (runs 43879895297 to
44450918935) has the row, so this is its first windows-aarch64 run (D5).

**F6 V. PR #52 CI run 45219775112: windows-11-arm / default failed in
R's own `reg-tests-1c.R`** (line 61, `stopifnot(t2 / t1 < 30)`: `str()`
of a 1e5-level factor timed against a character vector, ratio 40 on the
runner). A timing check; the branch changes nothing that job builds or
runs. The same job logged a GitHub 503 for pak's `zip.exe` download,
which only warns. Re-run of the failed job: pending.

**F7 V. Stress 45219870330, the conda legs (the env from universe and
conda-forge, no libs channel).** windows-latest / conda: the nine win-64
universe builds in the conda env's zig-libs; Targets: 6 install-failed,
25 ok, 1 skipped; Unexpected 0; the same rows and causes as F4.
windows-11-arm / conda: the nine win-arm64 builds; Targets: 3
install-failed, 29 ok; Unexpected 1, protolite, with the error of F5 (the
conda env has conda-forge's libprotobuf too); Rhdf5lib and arrow as
expected. In all four legs sf, terra, gdalraster, lwgeom and s2 are ok
with the universe builds. All six jobs of the run succeeded.

## Tests

gamma, 2026-11-23: `parse("stress/stress.R")`: ok; `stress.yaml` loads as
YAML; `pixi lock --check`: ok.

CI: stress 45219870330 (g2 g3 g4, both Windows arches, tree and conda,
conda-forge zig, trace) on 919f3fc, lock a4ae1990b010: F4, F5, F7. With
D5 every leg has Unexpected 0. PR CI 45219775112: F6.

## Next steps

1. Done 2026-11-23: PR #52; stress 45219870330 (F4, F5, F7).
2. The user commits D5 and the findings; re-run of the failed PR CI job (F6).
3. Optional: the full set on Windows, as feat-zig-libs finding 20.
