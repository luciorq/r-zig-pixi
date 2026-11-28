# chore-release-13: publish build 13

Build 13 was published on 2026-11-26 from main 77abec1 (merge of #57,
on top of #56). Lock cf4b3220532c. Release 12 was published on
2026-11-24 (run 45381914199, chore-release-12/PLAN.md).

Tags: **V** verified, **I** inferred, **A** assumption.

## What build 13 contains

The b13-* tracks (#56 docs, #57 code). Their records are in
.github/devdocs/b13-*/:
- zig build fetches R.
- rzig captures the configs.
- The openblas flavor forwards BLAS.
- GNU make is built with zig in build-tools.
- r-zig-tcltk is a new add-on output (not on win-arm64, build.skip).
- Windows wheels.
- The pixi features are split.
- An openblas leg on win-64.
- A gated release workflow.
- Stress rows served by zig-* slice 2.
- The Windows stress env without conda-forge geos and proj (b13-slice2 F11).
- zig-libcurl build 1 in the Windows stress env (b13-slice2 F13).

## Gate

| check | run | result |
|---|---|---|
| build-r full tier, upstream-zig on 177c08e | 45813752731, 45813752664 | all success. The Windows openblas leg passed on an x86_64_v3 runner |
| stress S1/S3/openblas on 21fee4e | 45714066676, 45714071892, 45714077623 | read row by row (b13-slice2 F12) |
| relock 40ca257 (zig-libcurl build 1, stress env only) | PR CI 45858340433 and 45858340508 | merged before these finished. build-r was cancelled by the user (same tree as the publish run). upstream-zig and windows-11-arm stress 45858117550 kept running |
| publish preflight | | hosted OIDC publish, no token needed. Build number 13 is one above universe's newest (12) on all six subdirs. Lock check ok. No ignored recipe inputs |

## Publish

| step | result |
|---|---|
| `gh variable set CONDA_PUBLISH --body true` | user, 16:27 UTC |
| `gh workflow run build.yaml --ref main` | run 45858899338. The push run 45858465164 was cancelled so only one run publishes |
| conda-package, all six subdirs | success. Uploaded through OIDC |
| run conclusion | failure: only `windows-latest / openblas` failed (F1). `packaging` was skipped (it only runs on pull requests) |
| `gh variable delete CONDA_PUBLISH` | done (user, 2026-11-26) |

## After (RELEASE.md "After")

| check | host | result |
|---|---|---|
| 1. universe at `_13` | delta, repodata.json | all seven outputs on linux-64, linux-aarch64, osx-64, osx-arm64, win-64. Six on win-arm64: no r-zig-tcltk there, by design (b13-recipe R4) |
| 2. fresh universe env, linux-64 | delta, `postpub13.sh` | r-zig-slim h3e03716_13 and r-zig-toolchain h9a77725_13 install. R 4.6.2 starts. `R CMD config CC` = zig-cc. C and C++ `R CMD SHLIB` build, load and run |
| 3. macOS minos | delta | 74 Mach-O files, all minos 13.0 |

Build strings:

| subdir | r-zig-slim | r-zig-toolchain | compilers, build-tools, extras, recommended, tcltk |
|---|---|---|---|
| linux-64 | h3e03716_13 | h9a77725_13 | hdf2e536_13 |
| linux-aarch64 | h0122563_13 | he756b0c_13 | hba1f1e3_13 |
| osx-64 | h9825941_13 | h8135f8e_13 | hf7b29a5_13 |
| osx-arm64 | ha6b6fea_13 | h1a8bc7b_13 | h00661cf_13 |
| win-64 | hb04b5bb_13 | h81436b0_13 | hb3c1eb0_13 |
| win-arm64 | he73fba8_13 | h5c7beb3_13 | h72c7ae5_13 (no tcltk) |

The build strings were sent to libs-zig-pixi on 2026-11-26, so they can
drop D124 LOCAL_SOFT and repin.

## Findings

- F1 (V) The Windows openblas crash (b13-fixes F14) happened again in
  the publish run on an x86_64_v4 runner (job 140060790975, AMD EPYC
  9V45, Zen 5). The D13 diagnostics step ran:
  - OpenBLAS reports `Core: Haswell` in all three cases.
  - `ar.ols` exits 0xC0000005 (access violation) as is, with
    `OPENBLAS_NUM_THREADS=1`, and with `OPENBLAS_CORETYPE=Haswell`.
  - No Application Error event (Id 1000) was logged for Rscript.

  So the crash happens without an AVX-512 kernel and without threads.
  F14's guess that the CPU picks an AVX-512 kernel is wrong. The cause is
  still open. It is not in a published package: the openblas flavor is
  not packaged (b13-fixes F14). Next: build 14, which needs more
  diagnostics (other core types, the BLAS and LAPACK calls `ar.ols`
  makes, one by one).
