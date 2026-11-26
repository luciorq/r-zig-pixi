# chore-release-12: publish build 12

Started 2026-11-23 on main 3395a08. Build 12 is published only after all open items (BACKLOG.md) are in (user, 2026-11-23). Release 11 (build 11) was published
on 2026-11-18 (run 44336177906, chore-release-11/PLAN.md). Build 12 is
the recipe number on main since #49 and has never been published.

Tags: **V** verified, **I** inferred, **A** assumption.

## Goal

Gate and publish build 12 of every r-zig output on all six subdirs, as
release 11 was: CI full tier and upstream-zig on the release code,
stress on all six runners, the publish preflight, then the publish
dispatch on main and the post-publish checks.

## What build 12 contains

Package-affecting merges since d65f1db (`git log --first-parent
d65f1db..3395a08`):

| PR | Platforms | Change | Risk |
|---|---|---|---|
| #49 feat-linux-libstdcxx (f668295) | linux-64, linux-aarch64 | Every C++ compile and link uses gcc's libstdc++ (rzig libstdcxx.zig); libR needs libstdc++.so.6 and libgcc_s.so.1; r-zig-compilers depends on libstdcxx-devel_linux-* 15.* and libstdcxx >=15; shim headers in the base | medium-high: the linux C++ ABI of packages changes (CXX-STDLIB.md decisions 1-3) |
| #50 feat-winarm-gaps (f951022) | win-64, win-arm64 | `_LINK_=/OPT:NOICF` on Windows image links; win-arm64 rzig and r-zig.cmake take the opt-in `R_ZIG_FALLBACK_SOFT` tree | low: opt-in, ICF off is the conservative choice |
| #51 feat-zig-libs (fbd692a) | win-64, win-arm64 | rzig searches `<env>/Library/zig-libs/<triple>` first; Rcmd_environ: `R_ZIG_LIBS`, zig-libs `.pc` first on `PKG_CONFIG_PATH`, a `PKG_CONFIG_LIBDIR` default, `R_TOOLS_SOFT` defaults to zig-libs; r-zig.cmake: zig-libs on `CMAKE_PREFIX_PATH` | medium-low: without zig-* packages the directory is missing, but `R_TOOLS_SOFT` is now set and a user's `PKG_CONFIG_PATH` no longer comes first |

Not package-affecting: e1835b4 (LICENSE, README), #52 (stress env and
stress files), #53 (docs). macOS has no functional change since 11; its
packages rebuild as `_12` because the number is one for all subdirs.
`recipe/variants.yaml` and the R patches did not change.

## Decisions

| # | Question | Options | Chosen | Reason | Who, date |
|---|---|---|---|---|---|
| R1 | How to gate | A ★ a release PR with `full-ci` and `upstream-zig` labels plus a stress dispatch on it, as #48 did for 11; B dispatch the workflows on main directly | A, as one integration PR per wave (one commit per topic, CI once) | The user, 2026-11-23: no release until all open items are in; "what can go together and be tested together should go into a single PR and run CI only once". Batch 1 is PR #54 | user, 2026-11-23 |
| R2 | The 11 → 12 comment in recipe.yaml named only #49 | A ★ extend it with #50 and #51 (comment only); B leave it | A | Every change in a published build is recorded in the recipe (document-decisions); build 12 is unpublished, so the comment changes nothing published | default, 2026-11-23 |
| R3 | Stress scope | A ★ all six runners, tree and conda (local channel), conda-forge zig, default groups g0 g3 g4 plus g1 and g2; then upstream zig (fetch-zig, any runner) on all six runners, tree; B linux and macOS only (Windows ran 45219870330) | A | No stress has run on #50/#51 code on linux or macOS, nor g1 on Windows since #50, nor upstream zig since b9c39fc | default, 2026-11-23 |

## Findings

**R12-F1 V. CI already run on code equal to main's build code.** #51's
head 972e5a4 contains f951022 (#50), and 972e5a4 → 3395a08 changes only
stress files, the stress feature of pixi.toml and its lock entries, and
docs. On 972e5a4: build-r full tier 45073714541 (32 success, packaging
skipped, conda-package on all six subdirs) and upstream-zig 45073714520
(6/6 success). On 919f3fc (#52): build-r core 45219775112 (success after
re-running windows-11-arm / default, a timing flake in R's
reg-tests-1c.R, feat-zig-libs-universe F6).

**R12-F2 V. Stress since release 11.** Linux both arches on 2674ab4
(#49 only, 44438790229); Windows only after that (44450918935,
45043098992, 45043101391 upstream zig on b9c39fc, 45079784455 conda on
972e5a4, 45219870330 tree and conda on 919f3fc, 0 unexpected with
protolite's windows-aarch64 expect). No macOS stress since 44259183592
(release 11 code).

**R12-F3 V. Local preflight on main 3395a08 (gamma).** `pixi lock
--check` up to date, lock a4ae1990b010; `/` 88 GB free, `/data/gamma`
7.5 TB; no build input gitignored (only `scripts/__pycache__`);
`CONDA_PUBLISH` not set. The publish is CI OIDC, so no local credential
is involved.

**R12-F4 V. Build 12 published 2026-11-24.** build.yaml 45381914199
(workflow_dispatch, main 7e3648e = #55 merged, CONDA_PUBLISH set).
Post-publish on delta (fresh pixi cache, universe before conda-forge):
all six outputs at `_12` on all six subdirs; linux-64 env installs
r-zig-slim h3e03716_12 and r-zig-toolchain hc78f3be_12, `R CMD config
CC` is zig-cc, `R CMD SHLIB` builds a C and a C++ library and both load
and return the right values; 70 Mach-O files in the osx-64 and osx-arm64
packages, every minos 13.0. Build strings (r-zig-slim, r-zig-toolchain,
the other four):

| subdir | r-zig-slim | r-zig-toolchain | compilers, build-tools, extras, recommended |
|---|---|---|---|
| linux-64 | h3e03716_12 | hc78f3be_12 | h7072f15_12 |
| linux-aarch64 | h0122563_12 | h1fb4297_12 | hebdf983_12 |
| osx-64 | h9825941_12 | h12c1ef1_12 | h19bf20d_12 |
| osx-arm64 | ha6b6fea_12 | h25e8f55_12 | h3ae0fae_12 |
| win-64 | hb04b5bb_12 | h3946dc3_12 | h6a289e5_12 |
| win-arm64 | he73fba8_12 | h3af3256_12 | h29a55db_12 |

Sent to the libs-zig-pixi session the same day (it drops its build-12
emulation, D114). A C++ test that includes `<R.h>` before `<vector>`
fails on libc++ (R's `length` remap): the check uses `R_NO_REMAP` and
C++ headers first, as R's manual says; not a package fault.

## Gates

| Gate | Run | Result |
|---|---|---|
| build-r full tier on the release sha (#55, d58dc2c) | 45299747894 | 32 success, 1 skipped (packaging) |
| upstream-zig on d58dc2c | 45299747858 | 12/12 success |
| stress, 6 runners, tree + conda, conda-forge zig | 45305358893 | 0 unexpected on linux and macOS; Rhdf5lib newly ok on Windows (expect updated, 909a5f2; wave2-fixes X-F3) |
| stress, upstream zig, tree | not run | the upstream-zig label run is the both-zigs gate (RELEASE.md); left for build 13 |
| publish preflight | R12-F3 | go |
| publish dispatch on main 7e3648e | 45381914199 | success; publish step in every conda-package job |
| post-publish: six outputs x six subdirs at `_12`; fresh universe env compiles and loads a C and a C++ SHLIB; osx minos | R12-F4 | ok |

## Not verified

- Old-glibc hosts and the other LATER items of the merged branches'
  records (feat-linux-libstdcxx, feat-winarm-gaps, feat-zig-libs): not
  release gates.

## Next steps

Done 2026-11-24: build 12 published (R12-F4), `CONDA_PUBLISH` deleted.
The rest of BACKLOG.md goes to build 13 (user, 2026-11-23). `_11` files
stay on universe (RELEASE.md: delete only if ever needed).
