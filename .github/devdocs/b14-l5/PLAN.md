# b14-l5: the r-zig binary package repository (L5)

Backlog L5 (chore-release-12/BACKLOG.md §4, R-F3); the user's decision
U2 = option (b) of b13-design L5-M (b13-integration PLAN.md, "User
decisions"): a curated linux repository in a CRAN-like (Posit P3M-style)
layout, served from GitHub Release assets. Design and prototype:
`.github/devdocs/b13-design/PLAN.md` (L5) and `prototype/l5/`.
Base: build13 head cc7d810 (build 13 in PR #57). Lands in build 14.

## What is here

| file | what |
|---|---|
| `repo/packages.tsv` | the curated list: package, per-package build env vars, a smoke expression |
| `repo/build-repo.R` | the builder: CRAN sources and hard dependencies, plain `R CMD INSTALL -l <work lib>` each with `R_ZIG_ENV_RPATH=origin` (D15), the libraries a package links outside R copied into `<pkg>/libs/` with `rzig-bundled/` records (D14, D19), then `utils::tar` as `--build` does (D18); an ELF check (only `$ORIGIN` rpaths; a file that needs a carried library must have an rpath of its own directory, D24); PACKAGES/.gz/.rds with RZig-ABI, RZig-Build, RZig-Bundled (D20; SystemLibs before), SHA256 |
| `repo/install-test.R` | installs the list from a finished repository (only that repository) into a new library, runs each smoke, and checks that every carried library mapped comes from the package or R's prefix |
| `repo/embed-test.py` | the rows in R embedded through ctypes (`Rf_initEmbeddedR`, as rpy2) in any python (D22) |
| `repo/README.md` | how to use, layout and key, carried libraries, the wheel's user library and rpy2, how to build, rebuild triggers |
| `.github/workflows/repo.yaml` | builds and tests on ubuntu-latest and ubuntu-24.04-arm with a published build (consumer without libxml2, embed test in the runner's python); uploads to GitHub Releases only behind the gate |
| `zigbuild/tools/rzig/compiler.zig` | `R_ZIG_ENV_RPATH`: `origin` gives links `-Wl,-rpath,$ORIGIN` in place of the conda env's rpath, `0` none; unit test |
| `zigbuild/tools/rzig/main.zig`, `README.md` | the variable documented; README "Install binary packages (linux)" |
| `zigbuild/launchers/Rscript` | passes the script as `--file=<file>`, as R's Rscript.c does (F3) |
| `scripts/make-wheel.py` | the r-zig wheel's `R_HOME/etc/Rprofile.site` (the user library, D21) and `site-packages/r_zig.pth` (rpy2 installs and finds R, D25-D27) |
| `python/r_zig/_rpy2.py` | the finder `r_zig.pth` installs, acting only where rpy2 would find no R or this wheel's R (D27): on rpy2's first import `R_HOME` (unless set) and `RPY2_CFFI_MODE=ABI` (unless set) (D25, D26); on setuptools' first import in an rpy2 source tree `RPY2_CFFI_MODE=ABI` unless set (D26) |
| `scripts/wheel-test.sh` | the user-library block (F31) and the rpy2 block (D25-D27; F45, F49) |
| `stress/stress.R` | one comment corrected (Rscript's `--file=`) |

## Experimental status

The user's decision U3 (2026-11-26): the whole L5 design is
experimental and gets a second review in a later build. That covers
every decision here, D1-D25 (each row tagged "exp."), the open menus,
the layout and URL, the ABI key, the builder, the libraries binaries
carry (D14-D20), the wheel's user library (D21) and the publish
workflow. repo/README.md, the README's L5 section, repo.yaml's header
and the release notes it writes say so. Nothing here is a commitment to
users yet: the URL or key may change, and no release exists.

## Decisions

All by default, 2026-11-24 (inside the approved batch; U2 itself is the
user's). All experimental (U3).

| id | question | options (chosen in bold) | reason |
|---|---|---|---|
| D1 (exp.) | builder language | **R script (repo/build-repo.R)**; a Zig tool | the design's pick (prototype build-repo.R); R already has download, dependency order, write_PACKAGES and sha256sum (R 4.5+); no extra binary to ship |
| D2 (exp.) | package list | **new `repo/packages.tsv` (package, env, smoke)**; reuse stress/packages.tsv rows | the stress rows describe failure expectations, OS limits and sysdeps for a diagnostic; the repository wants a short list of packages that must work, each with its own smoke; 14 rows, 16 packages with dependencies |
| D3 (exp.) | on-disk and URL layout | **`repo/linux-<arch>-rzig<abi>/<x.y>/src/contrib/`, the P3M root only**; also design D8's `bin/linux/<key>/contrib/<x.y>` | a GitHub Release's assets are flat; its tag can hold slashes (F2), so the tag `repo/<key>/<x.y>/src/contrib` makes `<download URL>/repo/<key>/<x.y>` a root for `options(repos)` (no R change, design L5 access (i)); one copy instead of a symlinked second tree; CRAN's `bin/` shape stays for Windows/macOS where `type = "binary"` works |
| D4 (exp.) | ABI key | **design D9: `<os>-<arch>-rzig<epoch>` + R x.y in the path; build only in PACKAGES (`RZig-Build`)**; the build number in the path | the task text said "keyed by r-zig build + platform"; the design's reason holds: binaries stay valid across builds that keep the ABI. Epoch 1 = builds 12-14 (libstdc++ on linux since 12). The constant lives in build-repo.R; users' snippet names it |
| D5 (exp.) | env rpath in binaries | **rzig switch `R_ZIG_ENV_RPATH=0` (unit-tested), the builder sets it and checks every .so**; patchelf after the build; `-Wl,--disable-new-dtags` | design's pick; no post-processing (simplicity rule); a build before 14 fails the check (F4) rather than shipping a stale RUNPATH; the builder's value is `origin` since D15 (2026-11-26) |
| D6 (exp.) | ELF reading | **in R (40 lines in build-repo.R)**; readelf | the build host needs no binutils (r-zig ships none on linux) |
| D7 (exp.) | build env | **`r-zig-slim` + `r-zig-toolchain` (all groups) + `libxml2-devel`, through `pixi exec`, universe first** ; slim + compilers + build-tools only | fs's bundled libuv needs cmake (F5); `pixi exec` activates (make on PATH) and takes the build as a workflow input, no manifest or lock |
| D8 (exp.) | packages that can bundle their library | **bundle (fs: `USE_BUNDLED_LIBUV=1`, the `env` column)**; link the env's | with r-zig-toolchain, cmake brings conda's libuv into the env and fs linked `libuv.so.1` (F5): one more SystemLib for every consumer |
| D9 (exp.) | failure handling | **a failed package skips its reverse dependencies, the rest are indexed, exit 1** | a CRAN update that breaks one package is visible, the artifact still shows the rest; the workflow's test and publish need success |
| D10 (exp.) | publishing | **gated: dispatch on main AND input `publish` AND variable `R_ZIG_REPO_PUBLISH == 'true'` AND both platforms passed; release created once (`--latest=false`), assets replaced (`--clobber`), binaries before PACKAGES; build provenance attestations** ; immutable releases | the repository changes on every rebuild (PACKAGES), so the release cannot be immutable; integrity comes from PACKAGES' SHA256 and the attestations (design "Signing") |
| D11 (exp.) | user helper | **a snippet (README, repo/README.md), no R/rzig helper** | design (i): no R change now; a helper that knows its own epoch belongs with option (c)/(ii), see "Open" |
| D12 (exp.) | Rscript `--file=` | **fix the launcher now** | found here (F3); a one-word change to match R's Rscript.c |
| D13 (exp.) | linux-aarch64 test on delta | **not run (recorded)** | delta has docker but no qemu binfmt (`/proc/sys/fs/binfmt_misc` has only python3.14); installing qemu changes the host; the workflow's ubuntu-24.04-arm leg covers it |

### User decisions (2026-11-26)
| U7 | Open 5: xml2 carries ICU (14.5 MB) | (a) keep it for now (experimental) | the user: "All recommended" (2026-11-26) |
| U8 | Open 6: the wheel's user library is shared with conda r-zig of the same version | (a) keep it, as CRAN R does (experimental) | the user: "All recommended" (2026-11-26) |
| U9 | Open 7: installing rpy2 next to the wheel | none of (a)-(c): "be more creative ... B sounds better, no upstream changes ... find a solution that works cleanly" | the user, 2026-11-26; answered by D26 (a default inside U9): see "rpy2 without setup (U9)" |

| id | question | choice | note |
|---|---|---|---|
| U3 | status of the whole L5 design | **experimental**: every choice above (D1-D13) and the menus below are marked experimental and get a second review in a later build | the user: "not sure about any of this design" |
| U4 | Open 1: the epoch in the snippet | (a) keep the snippet, note a bump in release notes (experimental) | the user: all recommended, flagged experimental |
| U5 | Open 2: R embedded from a Python, R as a Python package | **none of the menu**: it must work with no environment variable and no extra setup when R is installed as a Python package (the r-zig wheel), and that R must find the user's installed packages by itself | the user's requirement; replaces (a) `LD_LIBRARY_PATH` |
| U6 | Open 4: old binaries after a version bump | (a) leave them (experimental) | the user: all recommended, flagged experimental |

## Findings

| id | tag | finding and evidence |
|---|---|---|
| F1 | V | **Build 12 + this rzig builds the set:** 16 packages (14 rows + lifecycle, R6) on delta (20 cores, MAKEFLAGS=-j20), cold zig cache, 77.4 s wall, 288 MB max RSS, 13 MB repository; per package 1.0 s (R6) to 10.0 s (data.table); warm rerun 81.4 s (the time is R CMD INSTALL and configure, not zig). Env: universe r-zig-slim `h3e03716_12`, r-zig-toolchain `hc78f3be_12`, libxml2-devel, made with `pixi exec`, copied, rzig (all six names) and both Rscript launchers replaced by this worktree's (build-env in ~/rz/scratch-b14-l5) |
| F2 | V | **Slash tags work as repository paths.** GitHub serves `releases/download/cmd/builder/v0.165.0/<asset>` (open-telemetry/opentelemetry-collector-releases; curl 206 after 1 redirect, an unknown asset 404); R's `download.file()` fetched such a URL; `available.packages(repos=<tag prefix>)` asks for `<root>/src/contrib/PACKAGES.rds`. Not verified with an r-zig release (none may be created here) |
| F3 | V | **r-zig's Rscript passed `-f <file>`, R's Rscript.c passes `--file=<file>`** (src/unix/Rscript.c:346). Scripts that find themselves through `commandArgs()` (`--file=`) got NA (build-repo.R's first run: `path[1]=NA`). Fixed in zigbuild/launchers/Rscript; the patched launcher prints `--no-echo --no-restore --file=ca.R --args a "b c"`, -e and option forms unchanged. repo/*.R also accept `-f` for builds before 14 |
| F4 | V | **The rpath check catches a build without the switch:** the stock build 12 env via `pixi exec` (the workflow's way): every compiled package `absolute rpath .../cached-envs-v0/54878d193b4af411/lib`, R6 (pure R) built. With this rzig: `readelf -d` of all 15 .so files: no RPATH/RUNPATH. `RZIG_PRINT_ARGV` with upstream zig: `-L<env>/lib -Wl,-rpath,<env>/lib` unset, only `-L<env>/lib` with `R_ZIG_ENV_RPATH=0` |
| F5 | V | Build env contents leak into binaries: with r-zig-toolchain (r-zig-extras' cmake depends on libuv) fs linked the env's `libuv.so.1`; with slim + compilers + build-tools fs fails (`libuv was not found`, and with `USE_BUNDLED_LIBUV=1`: `cmake: not found`). With toolchain + `USE_BUNDLED_LIBUV=1`: fs static, no SystemLibs. SystemLibs found: data.table `libomp.so (llvm-openmp)`, xml2 `libxml2.so.16 (libxml2-16)` (conda-forge's run-time package name, from conda-meta) |
| F6 | V | **Embedding.** Rpath-free binaries in a consumer env (r-zig-slim 12 + libxml2): (a) Rscript, activated or not (`env -i`), loads the env's `libxml2.so.16.1.4` and `libomp.so`; (b) R embedded in the env's own conda python (ctypes, `Rf_initEmbeddedR`, as rpy2): env's libxml2 (python's `RPATH [$ORIGIN/../lib]`); (c) embedded in delta's /usr/bin/python3 3.14: **the host's** `/usr/lib/x86_64-linux-gnu/libxml2.so.16.1.2`; in rockylinux:8's platform-python (no libxml2.so.16): `libxml2.so.16: cannot open shared object file`; with `LD_LIBRARY_PATH=<env>/lib` at start: the env's. So libR's `RPATH [$ORIGIN/../..:$ORIGIN]` does not serve libraries of a dlopened package (rzig's environment.zig comment holds); libomp works because libR itself needs it. Recorded in repo/README.md and compiler.zig |
| F7 | V | **Install from `file://`:** fresh consumer env (own pixi cache; r-zig-slim 12 + libxml2; no make on PATH), the build env moved away: 16 packages in 5.6 s, 14 of 14 smokes; ubuntu:24.04 container (glibc 2.39, no host libxml2.so.16): 16 in 3.8 s, 14/14; rockylinux:8 (glibc 2.28): 16 in 4.0 s, 14/14. Consumer env without libxml2: delta loads the host's libxml2.so.16.1.2 (Ubuntu 26.04 has that SONAME); ubuntu:24.04 fails with `libxml2.so.16: cannot open shared object file` |
| F8 | V | Both zigs: a subset (fs, Rcpp, data.table, xml2 + cli, rlang) built with `ZIG_BIN=<PyPI ziglang 0.17.1>`: 42.1 s, all ok, no rpath failures, installed and 4/4 smokes ok. rzig unit tests 239/239 and check-test.sh 59/59 with conda-forge and upstream zig 0.17.1 |
| F9 | V | Precedence: `available.packages(repos = c(RZIG = <repo>, CRAN))` takes jsonlite, data.table, xml2 from RZIG at equal versions and ggplot2 from CRAN |
| F10 | I | When CRAN has a newer version, R takes CRAN's source (available.packages' duplicates filter keeps the highest version); a consumer without the toolchain then cannot install it until the repository is rebuilt. Not tested |
| F11 | V | Test caveat: the copied build env's xml2-config/pkg-config still name the original env (`-I.../cached-envs-v0/45f6fdf5a5b43125/include/libxml2` in xml2's log): same headers, and nothing of that path reached a binary (F4); the workflow builds in the real env |

## Tests run

| where | command | result |
|---|---|---|
| delta | `zig build --build-file zigbuild/tools/rzig/build.zig test` with conda-forge zig 0.17.1 and PyPI ziglang 0.17.1 | 239/239 both |
| delta | `pixi exec -s make -- env ZIG=<zig> bash zigbuild/tools/rzig/check-test.sh`, both zigs | 59 passed, 0 failed, both (without make on PATH it stops at its `onlymake` step: delta has no make) |
| delta | `pixi exec ... build 12 (slim, compilers, build-tools, libxml2-devel) -- Rscript repo/build-repo.R out-stock` | exit 1: 15 failed (14 absolute rpath, fs no libuv), R6 built (F4, F5) |
| delta | build-env (build 12 toolchain env copy + this rzig + launcher), `Rscript repo/build-repo.R out` | exit 0, 16 built, 77.4 s cold (F1) |
| delta | `readelf -d` on every .so of the 16 tarballs; PACKAGES fields; `sha256sum` vs SHA256 | no rpath; fields as F5; sums match |
| delta | `pixi exec (slim 12 + libxml2) -- Rscript repo/install-test.R out/repo/linux-x86_64-rzig1/4.6 lib-consumer` | 16 installed in 5.6 s, 14/14 (F7) |
| delta docker | the same consumer env in ubuntu:24.04 and rockylinux:8 | 14/14 each (F7) |
| delta (+docker) | embed.py (ctypes, scratch only) with system python, conda python, rocky platform-python | F6 |
| delta | upstream zig subset build + install test | F8 |
| delta | README snippets in R | both give `https://github.com/luciorq/r-zig-pixi/releases/download/repo/linux-x86_64-rzig1/4.6` |
| gamma | `pixi exec -s actionlint -s shellcheck -- actionlint .github/workflows/repo.yaml` | clean; publish step's tag derivation checked on a fake `dl/` tree |

Not run: the workflow itself (no dispatch from here); linux-aarch64 (D13);
an HTTPS install from a real r-zig release (none exists; F2 is the
evidence for the URL shape); a published build 14 (does not exist; F1
used build 12 + this rzig).

## Open (for the user; menus)

1. **The epoch in the user's snippet.** The snippet hard-codes `rzig1`.
   After an epoch bump, a user who upgrades R but keeps an old
   `~/.Rprofile` gets binaries of the old epoch. (a) **recommended** keep
   the snippet and say so in the release notes of an epoch bump; (b)
   write the epoch into r-zig (e.g. `etc/Renviron` `R_ZIG_REPO_ABI`) so
   the snippet reads it; (c) design option (c), an R patch making
   `contrib.url()` add the binary path itself.
2. **Embedding from a Python outside the env (F6).** Answered by U5
   (none of these): binaries carry their libraries, D14-D23, F24-F28.
   The menu as it was: (a) **recommended**
   document `LD_LIBRARY_PATH=<env>/lib` (done in repo/README.md); (b)
   give repository binaries a relative DT_RPATH (`$ORIGIN/../../../..`,
   right only when installed in the env's own library); (c) keep the
   absolute rpath (not possible for a repository).
3. **First publish:** after build 14 is on universe: `gh variable set
   R_ZIG_REPO_PUBLISH --body true`, `gh workflow run repo.yaml --ref
   main -f rzig_build=14 -f publish=true`, then `gh variable delete
   R_ZIG_REPO_PUBLISH`.

## Needs from other topics

- Release: build 14 must be published before the workflow can build
  (with build 12/13 every compiled package fails F4's check, by design).
- recipe tests unset the caller's rzig variables; `R_ZIG_ENV_RPATH` is
  not in their lists. None of them checks an rpath, so it changes no
  result; add it when one does.

## Review (2026-11-24)

Skeptical pass over the diff and the new files. Scope: only files of this
track; no b13-* record touched (`git status`: README.md, stress/stress.R,
zigbuild/launchers/Rscript, zigbuild/tools/rzig/{compiler,main}.zig
modified; repo/, repo.yaml, this record new).

| id | finding | action |
|---|---|---|
| R1 | Workflow gate: publish job needs `ENABLE_HOSTED_JOBS`, `R_ZIG_REPO_PUBLISH == 'true'`, `workflow_dispatch`, `refs/heads/main`, `inputs.publish`, and `needs: build` (implicit `success()`, so one failed leg blocks it). Only trigger is `workflow_dispatch`; no `pull_request_target`; `contents: write` / `id-token` / `attestations` only on the publish job; `GH_TOKEN` only in the upload step; inputs reach shell only through `env:` and are regex-checked. The `repo/...` tags do not match upstream-zig.yaml's `tags: ["v*"]` | none needed |
| R2 | The build job runs CRAN packages' configure scripts and Makefiles after `actions/checkout`, which left the (read-only) job token in `.git/config` | fixed: `persist-credentials: false` |
| R3 | Two publish runs at once would interleave `--clobber` uploads of PACKAGES and binaries | fixed: `concurrency: repo-publish` (no cancel) on the publish job |
| R4 | R's front end shows a space in the script path as `~+~` in `commandArgs()` (both `--file=` and `-f`; delta: `--file=sp~+~ace/x.R`), so `here` broke for a checkout path with a space | fixed: both repo/*.R decode `~+~`; verified by running both scripts from `sp ace/repo/` |
| R5 | F3 checked against R's source: rsrc/R-4.6.1/src/unix/Rscript.c:346 `"--file=%s"`. Old and new launcher both keep `"b c"` as one argument after `--args` (delta) | none needed |
| R6 | README overclaims: "served from this repository's GitHub Releases" (nothing published) and `R_ZIG_ENV_RPATH=0` "linux and macOS" with R's rpath finding libraries (tested on linux only) | fixed: "(from build 14; not published yet)", "on linux ... (macOS not tested)" |
| R7 | Windows: the launcher is POSIX sh (linux/macOS only); `envRpath` only removes the conda `-Wl,-rpath` when set to `0`, unset behaviour unchanged on every OS | no kappa run needed |
| R8 | Old binaries stay as release assets after a version bump (`--clobber` replaces same-name assets only); PACKAGES no longer points at them, so harmless, but the release grows | recorded, Open 4 |
| R9 | The builder must run in an activated env (make on PATH); a first review run with `build-env/bin/Rscript` unactivated failed data.table and rlang with rzig's clear "no make on PATH" message. The workflow and repo/README use `pixi exec`, which activates | none needed |

Review tests (delta, worktree synced):

| command | result |
|---|---|
| `zig build --build-file zigbuild/tools/rzig/build.zig test`, conda-forge zig 0.17.1 (build-env) and PyPI ziglang 0.17.1 | 239/239 both |
| build-env (build 12 + this rzig/launcher) on PATH: `Rscript "sp ace/repo/build-repo.R" out-rev <digest, data.table, xml2>` | 5 built (with cli, rlang), 29.4 s, exit 0; SystemLibs data.table `libomp.so (llvm-openmp)`, xml2 `libxml2.so.16 (libxml2-16)` |
| consumer `pixi exec` (r-zig-slim 12 + libxml2; build env moved away): `Rscript "sp ace/repo/install-test.R" ...` | 5 installed in 1.1 s, 3/3 smokes ok (published launcher's `-f` path, also with the space) |
| gamma: `actionlint .github/workflows/repo.yaml` (with shellcheck) | clean |

Not re-run: the full 14-row build and the docker consumers (F7); the
change since is the `~+~` decode and workflow/README text only.

Open 4 (for the user): stale assets. (a) **recommended** leave them
(small, PACKAGES-driven); (b) after each publish delete assets not named
in PACKAGES (`gh release view --json assets` + `gh release delete-asset`).

## Suggested commit messages (superseded: b14-review/PLAN.md, "Build 14 commit plan")

```
feat: R_ZIG_ENV_RPATH=0 links packages without the conda env rpath
fix: pass the script to R as --file=, as R's Rscript does
feat: a curated linux binary package repository with a gated release workflow
```

## Port onto main (build14)

2026-11-26. The track moved from the b14-l5 worktree (base cc7d810) to
the build14 worktree (base origin/main 77abec1, build 13 merged and on
universe for linux-64). repo/*, repo.yaml and the Rscript launcher are
byte-identical to b14-l5's; the rzig hunks (compiler.zig, main.zig) and
the stress.R comment are the same lines. Delta dir:
`~/rz/wt/build14-l5` (logs in `logs/` and `build/l5/logs/`, tables in
`build/l5/out/build.tsv` and `build/l5/out-stock/build.tsv`; large
outputs deleted).

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F12 | V | **`R_ZIG_ENV_RPATH` composes with main's rzig changes.** Main's compiler.zig changes since cc7d810 are Windows only (`windows.demoteZigLibs`, `windows.hasIdirafter` for the env's `-idirafter`); Windows links never had a conda rpath, so `envRpath` has nothing to do there. Main's main.zig changes (windres depfile, `spawnWait`) do not touch links. `-Wl,-rpath` is added only in `envFlags` (grep of non-test code); fortran.zig links go through `compiler.argv`, so Fortran links follow the switch too. The new test's `-I<env>/include` matches main's d58dc2c (linux keeps `-I`). End to end: every .so of F13's build (including those built by `rzig build`'s tier) has no RPATH/RUNPATH |
| F13 | V | **Build 13 + this rzig builds the set:** published build 13 (`r-zig-slim h3e03716_13`, `r-zig-toolchain h9a77725_13`) + libxml2-devel via `pixi exec`, copied, rzig (six names), `dso_fini.o`, `libstdcxx-shim` and both Rscript launchers replaced by this worktree's (rzig built with `zig build --build-file zigbuild/tools/rzig/build.zig -Dtarget=x86_64-linux-gnu.2.28 -Dcpu=baseline`): 16 built, 0 failed, exit 0, 74.8 s, 288 MB max RSS (delta, MAKEFLAGS=-j20). 15 .so files, none with RPATH/RUNPATH; PACKAGES' SHA256 match `sha256sum` for all 16; `RZig-ABI: linux-x86_64-rzig1`, `RZig-Build: r-zig-slim 4.6.2 h3e03716_13`; SystemLibs as F5 (data.table `libomp.so (llvm-openmp)`, xml2 `libxml2.so.16 (libxml2-16)`) |
| F14 | V | **Stock build 13 still fails the check, by design (F4):** `pixi exec` build 13 env, `Rscript repo/build-repo.R out-stock`: exit 1, 15 failed (10 `absolute rpath .../cached-envs-v0/69643d96a5116ad9/lib (rzig before build 14 ignores R_ZIG_ENV_RPATH)`: cli, rlang, glue, jsonlite, digest, yaml, fs, ps, Rcpp, data.table; 5 skipped as reverse dependencies: lifecycle, vctrs, processx, later, xml2), R6 built; 52.1 s. So repo.yaml still needs `rzig_build >= 14` |
| F15 | V | **R9 no longer applies from build 13:** the copied build env run unactivated (`PATH=<env>/bin:/usr/bin:/bin`, no `make` there; delta has no make) built all 16: build 13's build-tools group has `lib/R/bin/toolchain/usr/bin/make`, which R puts first on `PATH`. `pixi exec` (the workflow's way) still activates |
| F16 | I | data.table's binary holds a text file `data.table/cc` with `CC=<build env>/lib/R/bin/toolchain/zig-cc` (written by its configure; the only file in the 16 tarballs naming the build dir, `grep -rl`). Text only, not loaded by the linker; the smoke passes in a consumer without that path. No action |
| F17 | V | **Install from `file://` with build 13:** consumer `pixi exec` (r-zig-slim build 13 + libxml2, its own pixi cache, `env -i`, the build env and its cache moved away, no make on PATH): 16 installed in 3.5 s, 14 of 14 smokes ok, 10.2 s total. The consumer's published launcher passes `-f`, so install-test.R's `-f` fallback ran |
| F18 | V | **repo.yaml follows main's conventions:** runners `ubuntu-latest` + `ubuntu-24.04-arm` (as build.yaml, stress.yaml); every job gated by `vars.ENABLE_HOSTED_JOBS == 'true'` (the publish job adds release.yaml's dispatch-on-main + variable pattern); top-level `permissions: contents: read`, writes only on the publish job; actions tag-pinned as every workflow here (`checkout@v7`, `setup-pixi@v0.11.3` with `pixi-version: v0.84.2`, `upload-artifact@v7`, `download-artifact@v8`); `attest-build-provenance@v4` is used only here, the tag exists (`gh api repos/actions/attest-build-provenance/tags`: v4, v4.2.2). build.yaml's `linux_runner` input (a newer image before ubuntu-latest moves) has no counterpart here; not needed: zig targets glibc 2.28 on any runner image. `actionlint` (with shellcheck) clean. No change |

Delta hygiene note: the launcher test first copied this worktree's
Rscript into `~/rz/scratch-b14-l5/build-env` (the b14-l5 test env, not
this track's dir); the file is byte-identical to what that env already
had (`diff` of b14-l5's and build14's launchers: same), and the test dir
created there was removed.

### Changes in the port

- README.md (L5 section only): two over-long lines reflowed; no text
  change.

### Tests (port)

| where | command | result |
|---|---|---|
| delta | `touch zigbuild/tools/rzig/compiler.zig; pixi run --locked rzig-test` (conda-forge zig 0.17.1) | unit 244/244, fetch.zig 5/5, check-test.sh 60 passed 0 failed, link-objects-test ok; exit 0 |
| delta | the same with `ZIG_BIN=$(pixi run fetch-zig)` (PyPI ziglang 0.17.1) | 244/244, 5/5, 60/0; exit 0 |
| delta | Rscript launcher against a fake `R` that prints its arguments: file, file + args (`"b c"`), option before file, `-e`, two `-e` + args, a path with a space, `lib/R/bin` copy, through a symlink | 8 passed, 0 failed; `--default-packages=` sets `R_DEFAULT_PACKAGES`; bare `-e` and no args: usage, exit 1 |
| delta | the launcher with real R 4.6.2 (build 12 env): `Rscript s.R a "b c"`, `Rscript "sp ace/x.R" z`, `Rscript -e ... a "b c"`, `--version` | `--file=s.R|a|b c`; `--file=sp~+~ace/x.R|z`; `a|b c`; version printed |
| delta | stock build 13 `pixi exec ... -- Rscript repo/build-repo.R out-stock` | exit 1, 15 failed, R6 built (F14) |
| delta | build 13 + this rzig/launchers: `Rscript repo/build-repo.R out` | exit 0, 16 built, 74.8 s (F13) |
| delta | `readelf -d` of the 15 .so; `sha256sum` vs PACKAGES; fields | no rpath; 16/16 sums; fields as F13 |
| delta | consumer `pixi exec` (slim 13 + libxml2) `Rscript repo/install-test.R out/repo/linux-x86_64-rzig1/4.6 lib-consumer` | 16 installed, 14/14 smokes (F17) |
| gamma | `pixi exec -s actionlint -s shellcheck -- actionlint .github/workflows/repo.yaml` | clean |

Not run (port): the docker consumers and embedding (F6, F7: no input of
theirs changed), upstream zig for the package build (F8; rzig-test ran
with both zigs), linux-aarch64 (D13), any dispatch.

## U5: binaries need nothing outside R; the wheel's user library (2026-11-26)

The user's U5: R installed as a Python package (the wheel, pip into a
plain venv, no conda) and R embedded from a Python outside any conda env
(F6) load the repository's binaries with no environment variable and no
extra setup, and that R finds the user's installed packages by itself.
Delta dir `~/rz/wt/build14-l5b` (worktree synced; scripts and logs in
`scratch/`, `scratch/logs/`). Build env: published build 13
(`r-zig-slim h3e03716_13`, `r-zig-toolchain h9a77725_13`,
libxml2-devel) via `pixi exec`, copied, with this worktree's rzig (six
names), `dso_fini.o`, `libstdcxx-shim` and Rscript launchers
(`scratch/setup-env.sh`), as F13. The wheel: built here from this
worktree (`pixi run --locked -e minimal build`, `-e minimal
toolchain`, `-e wheel wheel`).

### Decisions (all experimental, U3)

| id | question | options (chosen in bold) | reason |
|---|---|---|---|
| D14 (exp.) | how a binary gets the libraries it links outside R | **(i) carry them: copied from the build env's lib/ into `<pkg>/libs/`, found through an `$ORIGIN` rpath (auditwheel's model without renaming)**; (ii) static archives in the package .so; (iii) the wheel ships the curated packages' libraries and libR's rpath finds them; (iv) packages' own bundled sources (USE_BUNDLED_*); (v) `LD_LIBRARY_PATH` (Open 2 (a)) | (i) works in every consumer measured (F24-F28) and needs nothing from the consumer. (ii) conda-forge has no libxml2 static archive (F21), and a static libomp per package would put several OpenMP runtimes in one process. (iii) fails embedded: neither libR's rpath (RUNPATH in the wheel, F19) nor its DT_RPATH (conda, F6) is applied to a dlopened package's libraries, and the wheel would carry every curated package's libraries. (iv) xml2 and data.table have no bundled copy (fs's libuv is D8). (v) is what U5 rules out |
| D15 (exp.) | where `$ORIGIN` comes from | **rzig: `R_ZIG_ENV_RPATH=origin` puts `-Wl,-rpath,$ORIGIN` (macOS `@loader_path`) in place of the env's rpath on links; `0` (none) kept**; `LDFLAGS += -Wl,-rpath,'$$ORIGIN'` in a Makevars file; patchelf after the build | rzig passes argv with no shell, so no `$$`/quote layers through make and sh (the Makevars route's known trap); no post-processing (simplicity rule). Unit test extended (origin: once, before the env -L, links only; a package's own rpath stays first) |
| D16 (exp.) | what a binary does not carry (`r_libs`) | **glibc's libraries, libR/libRblas/libRlapack, and the intersection of libR's DT_NEEDED closures in r-zig-slim and in the wheel's minimal tree: libstdc++, libgcc_s, libz, libbz2, liblzma, libzstd, libpcre2-8, libiconv (F19)**; slim's closure; nothing (carry all) | these are loaded before any package in every R, so the package's NEEDED binds them by SONAME; slim's closure would leave libomp, ICU and libdeflate out, which the wheel's R does not load. libRlapack is R's own; no curated package links it (F33) |
| D17 (exp.) | xml2's libxml2 needs ICU (36 MB of libicudata/libicuuc) | **carry ICU too: xml2's binary is 14.5 MB (F24)**; conda-forge's ICU-free libxml2 build; a static zig-libxml2 for linux from libs-zig-pixi | the ICU-free build cannot be in an env with r-zig-slim, which needs ICU (F23); zig-libxml2 is Windows-only on universe today (`pixi search -p linux-64 zig-libxml2*`: none). Size only: in a conda env R's own ICU is already loaded and the copy is never mapped (F25). Open 5 |
| D18 (exp.) | the tarball | **`R CMD INSTALL` into the work library, then the libraries, then `utils::tar(..., tar = "internal")` of `<pkg>/` (what --build does)**; `--build`, then add files and tar again | one path for every package; R CMD INSTALL of the result says `installing *binary* package` (Built field), F25-F28. No MD5 file is written on linux, so nothing to refresh (checked: no `*/MD5` in the 16 tarballs) |
| D19 (exp.) | licences and provenance of carried libraries | **`<pkg>/rzig-bundled/SOURCES` (conda package, version, build, URL, sha256, licence, each file with its sha256) and `LICENSES/<conda package>/` (its `info/licenses`, from conda-meta's `extracted_package_dir`); a package whose libraries' licences are not found fails**; under `libs/`; PACKAGES only | the same record shape as the standalone tree's share/licenses/SOURCES; outside libs/ so nothing there but shared objects |
| D20 (exp.) | PACKAGES field | **`RZig-Bundled: <soname> (<conda package> <version>), ...` replaces `SystemLibs`**; keep SystemLibs | the consumer now needs nothing; the field says what a binary carries (rebuild trigger on a security fix: repo/README.md) |
| D21 (exp.) | the wheel's R and the user's packages | **the wheel ships `R_HOME/etc/Rprofile.site` that creates `R_LIBS_USER` (patch 0001's `$XDG_DATA_HOME` or `~/.local/share`, then `R/<conda subdir>-zig/<x.y>`: `linux-64-zig`, `linux-aarch64-zig`) at the first start and puts it first in `.libPaths()`**; the venv's `R_HOME/site-library` (shipped existing: per-venv); an R patch; leave it | R adds that directory only once it exists and creates it only from an interactive install.packages() prompt; without it the wheel's R installed into its base library inside site-packages, or failed where that is read-only (F20). Only the wheel gets it (make-wheel.py): conda env R keeps installing into its env. Side effect: once it exists, a conda r-zig R of the same x.y also puts it first (patch 0001's shared default), Open 6 |
| D22 (exp.) | CI consumer | **repo.yaml's consumer has r-zig-slim alone (no libxml2), install-test.R also checks that every carried library mapped comes from the package or R's prefix, and repo/embed-test.py loads every row in R embedded in the runner's own /usr/bin/python3 (ctypes)**; only install-test.R | the CI run then proves U5's two cases on both arches; the wheel itself is not built in repo.yaml (a published build's wheel is not on PyPI) |
| D23 (exp.) | RUNPATH or DT_RPATH for `$ORIGIN` | **RUNPATH (zig's default)**; `--disable-new-dtags` | RUNPATH is searched after `LD_LIBRARY_PATH`, so a user can still override; the carried copy is found before the host's /usr/lib either way (F28: no host libxml2 mapped) |
| D24 (exp.) | a copied library that needs another copied one (review 2026-11-26, finding 5) | **the builder requires an rpath entry of the file's own directory (`$ORIGIN`, `$ORIGIN/`, `$ORIGIN/.`, also `${ORIGIN}`) on every file, package or copied library, that needs a carried library; otherwise the package fails with the reason**; trust conda-forge's rpaths (before); set the rpath (patchelf) | without its own `$ORIGIN` the loader never looks in libs/ for that library's needs, which then come from the host or fail, and install-test.R only sees it on a host without that SONAME; failing keeps the no-post-processing rule. Today's set passes (F24), the negative test fails as it should (F34) |
| D25 (exp.) | rpy2 finding the wheel's R from a venv that is not activated (review finding 1; U5) | **the r-zig wheel ships `site-packages/r_zig.pth` (`import r_zig._rpy2`): a meta path finder that, on the first import of `rpy2`, sets `R_HOME` to the wheel's R unless set, then removes itself**; (b) the .pth sets `R_HOME` at every Python start; (c) an upstream rpy2 change (look for `r_zig`); (d) document: activate the venv | (d) is the setup U5 rules out. (b) also makes `pip install rpy2` work once r-zig is installed (F37), but every other R started from that Python prints `WARNING: ignoring environment value of R_HOME` on stdout (F36); the finder touches only processes that import rpy2, which writes `R_HOME` into the environment itself once R starts (rpy2's embedded.py). Cost at every start: 0.5 ms (F40). (c) is not ours to ship. Installing rpy2: D26 extends this finder |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F19 | V | **libR's closures and rpaths** (delta, `ldd`, `readelf -d`): r-zig-slim 13's libR `RPATH [$ORIGIN/../..:$ORIGIN]`, loads libbz2, libdeflate, libgcc_s, libiconv, libicudata/i18n/uc.78, liblzma, libomp, libpcre2-8, libRblas, libstdc++, libz, libzstd; the wheel's (build 13 minimal tree) libR `RUNPATH [$ORIGIN:$ORIGIN/../..]`, loads libbz2, libgcc_s, libiconv, liblzma, libpcre2-8, libRblas, libstdc++, libz, libzstd (no libomp, no ICU). The intersection is D16's list |
| F20 | V | **The wheel's R before this change** (build 13 wheel, delta's /usr/bin/python3 3.14 venv, no pip in the host python: pip bootstrapped from its own wheel): `.libPaths()` = only `<venv>/.../r_zig/R/lib/R/library`; `R_LIBS_USER` = `~/.local/share/R/linux-64-zig/4.6`, missing; `install.packages()` (non-interactive) installed into the base library (`Updating HTML index of packages in '.Library'`), and later sessions found them there. The repository's binaries (no rpath) loaded in that R only through host libraries or not at all (F6) |
| F21 | V | Static archives: `pixi search -c conda-forge libxml2-static`: no package; the build env's lib/ has no libxml2.a or libomp.a |
| F22 | V | **No second copy in a conda env R** (the build env copy: slim + toolchain + libxml2): xml2 from the repository (carried libxml2) and XML 3.99 from CRAN source (env's libxml2, absolute env RUNPATH) in one session, both orders: exactly one libxml2 mapped each time (xml2 first: the carried copy; XML first: the env's 2.15.4), both parse (`scratch/dup-test.sh`, run on the subset and the full repository). libomp: data.table's carried copy is never mapped in a slim R (F25) |
| F23 | V | conda-forge's ICU-free libxml2-16 builds exist (2.15.4 `hbdfff7e_0/_1` linux-64; anaconda.org files API), but they constrain `icu <0.0a0`: `pixi exec ... -s r-zig-slim==4.6.2=*_13 -s r-zig-toolchain... -s libxml2-devel -s "libxml2-16=*=hbdfff7e*"` is unsolvable (r-zig-slim needs icu). The hashes differ per version and arch, so no spec could pin that variant anyway |
| F24 | V | **The full list with carried libraries:** `Rscript repo/build-repo.R out` (build 13 + this rzig, R_ZIG_ENV_RPATH=origin): 16 built, 0 failed, exit 0, 77.0 s wall, 240 MB max RSS (delta, -j20; run alone). Repository 28 MB (13 MB before; xml2 14.5 MB with ICU, data.table 3.3 MB with libomp). `RZig-Bundled`: data.table `libomp.so (llvm-openmp 23.1.5)`, xml2 `libxml2.so.16 (libxml2-16 2.15.4), libicuuc.so.78 (icu 78.3), libicudata.so.78 (icu 78.3)`. Every ELF in the 16 tarballs: package files `RUNPATH [$ORIGIN]` (19), carried conda libraries `$ORIGIN/.` or `$ORIGIN/` (4); PACKAGES' SHA256 match all 16; rzig-bundled/SOURCES and LICENSES present (llvm-openmp's LICENSE.TXT, libxml2's Copyright, icu's LICENSE) |
| F25 | V | **conda consumer with no libxml2** (r-zig-slim 13 alone, its own pixi cache, `ls lib | grep -c xml2` = 0, `env -i`, build env and its cache moved away): install-test.R 16 installed in 4.1 s, 14/14 smokes; LIB: libxml2.so.16 from xml2/libs, libomp and ICU from the env (R loaded them). The same library in R embedded in delta's /usr/bin/python3 3.14 (repo/embed-test.py, conda libR): 14/14 |
| F26 | V | **wheel consumer** (the wheel built here, fresh venv of /usr/bin/python3 3.14, fresh HOME, `env -i`): first start: `.libPaths()` = the new `~/.local/share/R/linux-64-zig/4.6`, then the base library; `install.packages(<14 rows>, repos = file://...)` with defaults installed into it; ~~a new session finds all 14 there and attaches them~~ (corrected in review: that step of `scratch/wheel-consumer.sh` failed on a script bug, `there is no package called 'package'`; the kept log showed a new session loading only xml2 and data.table by default; F35 is the evidence for all 14); install-test.R 14/14, LIB: libomp, libxml2, ICU all from the packages' libs/; embed-test.py in the venv's python: 14/14; rpy2 3.6.9 (activated venv): `.libPaths()` has the user library first, xml2 and data.table work (getDTthreads 10), the carried libraries mapped |
| F27 | V | **rpy2 and the wheel:** `pip install rpy2` (3.6.9; rpy2-rinterface 3.6.7 is an sdist for Python 3.14) fails in API mode: pip's isolated build environment hides the venv's site-packages from every python it starts, so the venv's `R` console script dies with `ModuleNotFoundError: No module named 'r_zig'` and rpy2 says it cannot find R. `RPY2_CFFI_MODE=ABI pip install rpy2` installs. At run time rpy2 finds R through `R` on PATH (an activated venv) or R_HOME; from a venv's python not activated: `ValueError: r_home is None`. Not a library problem; fixed for run time by D25 (F36); install: F37, then D26 (F41: the two-command install with no variable from a venv not activated, four images) |
| F28 | V | **containers without the libraries** (delta docker, `--user 2011`, everything mounted at its path): ubuntu:24.04 (glibc 2.39) and rockylinux:8 (glibc 2.28), each: the conda consumer env 16 installed, 14/14, carried libxml2 mapped; the wheel's R tree run directly: user library created, 16 installed, 14/14, all carried libraries from the packages; rockylinux:8 platform-python 3.6 embedding the conda libR and the wheel's libR: 14/14 each. python:3.12-slim (no libxml2): pip installs the wheel into a venv, install.packages() defaults into `/tmp/h/.local/share/R/linux-64-zig/4.6`, a new session attaches xml2 and data.table, embed-test.py 3/3, rpy2 (ABI) works with the user library first |
| F29 | I | The carried libxml2.so.16 holds the build env's path as its default catalog, `file://<build env>/etc/xml/catalog` (conda's prefix replacement at install; `strings`); libomp and ICU hold none. libxml2 reads that catalog only to resolve external entities or DTDs and only when it exists; on a consumer it does not (in CI the path is under the runner's rattler cache). Like F16 (data.table's `cc`), text only. No action now; Open 5's zig-libxml2 would remove it |
| F30 | V | Embedded in a host python, the python's own libraries win by SONAME too: libz.so.1 mapped from /usr/lib (delta, rocky), loaded by python before libR. glibc behaviour, ABI-stable; listed so it is not mistaken for leakage |
| F31 | V | `pixi run --locked -e wheel wheel-test` with the new wheel and the new block in scripts/wheel-test.sh (R_LIBS_USER created under the test's HOME, first in `.libPaths()`, an R-only package installed with install.packages() defaults loads in a new session): `wheel test passed`, exit 0 |
| F32 | V | rzig unit tests after the change (`touch compiler.zig; pixi run --locked rzig-test`): conda-forge zig 0.17.1 and upstream (PyPI ziglang 0.17.1, `ZIG_BIN=$(pixi run fetch-zig)`) each: 244/244, fetch.zig 5/5, check-test.sh 60 passed 0 failed, link-objects-test ok, exit 0 |
| F33 | V | No curated binary links libRlapack (NEEDED of all 15 .so: libc, libdl, libgcc_s, libm, libomp, libpthread, libR, librt, libstdc++, libxml2). A future one would find it in an R started normally (etc/ldpaths puts R_HOME/lib on LD_LIBRARY_PATH) but, embedded, only once R's lapack module has loaded it: not carried (D16), recorded |

### Changes

| file | change |
|---|---|
| `zigbuild/tools/rzig/compiler.zig` | `R_ZIG_ENV_RPATH=origin` (enum env/none/origin), docs, unit test cases |
| `zigbuild/tools/rzig/main.zig` | the variable's `origin` value documented |
| `repo/build-repo.R` | R_ZIG_ENV_RPATH=origin; install, carry libraries (`bundle()`), record rzig-bundled/, tar; `r_libs` as D16; RZig-Bundled; rpath check accepts only `$ORIGIN...` |
| `repo/install-test.R` | LIB check: carried libraries mapped only from the package or R's prefix |
| `repo/embed-test.py` | new: the rows in R embedded through ctypes in any python |
| `repo/packages.tsv`, `repo/README.md` | experimental note; carried libraries; consumer needs nothing; wheel user library |
| `.github/workflows/repo.yaml` | experimental header; consumer without libxml2; embed test with the runner's python; release notes say experimental |
| `scripts/make-wheel.py` | `rprofile_site()`: R_HOME/etc/Rprofile.site in the r-zig wheel (D21) |
| `scripts/wheel-test.sh` | the user-library block (F31) |
| `README.md` (L5 section) | experimental note; carried libraries; wheel user library; R_ZIG_ENV_RPATH values |

No R patch was needed (no 0020): the user library is the wheel's
Rprofile.site, and the libraries are the builder's.

### Tests (U5)

| where | command | result |
|---|---|---|
| delta | `setup-env.sh` (build 13 env copy + this rzig built with its zig, `-Dtarget=x86_64-linux-gnu.2.28 -Dcpu=baseline`) | ok |
| delta | `Rscript repo/build-repo.R out-sub subset.tsv` (fs, processx, data.table, xml2) | 8 built, 46.2 s |
| delta | `Rscript repo/build-repo.R out` (all 14 rows) | 16 built, exit 0, 77.0 s (F24) |
| delta | `readelf -d` of every ELF in the 16 tarballs; `sha256sum` vs PACKAGES; `strings` for the build path | F24, F29 |
| delta | conda consumer (slim 13 alone): `install-test.R`, `embed-test.py` with /usr/bin/python3 | 14/14 and 14/14 (F25) |
| delta | `pixi run --locked -e minimal build`, `-e minimal toolchain`, `-e wheel wheel` | exit 0; r_zig wheel 51.1 MiB, 1456 files |
| delta | `pixi run --locked -e wheel wheel-test` | passed (F31) |
| delta | `scratch/wheel-consumer.sh` (fresh venv, host python, the new wheel) | F26 |
| delta | build 13 wheel in a host-python venv (before the change) | F20 |
| delta | `scratch/dup-test.sh` on the subset and on the full repository | one libxml2 per process (F22) |
| delta docker | `scratch/docker-tests.sh`: ubuntu:24.04, rockylinux:8, python:3.12-slim | F28 |
| delta | `touch zigbuild/tools/rzig/compiler.zig; pixi run --locked rzig-test`, conda-forge zig 0.17.1 | 244/244, 5/5, 60/0, exit 0 |
| delta | the same with `ZIG_BIN=<pixi run fetch-zig>` (PyPI ziglang 0.17.1) | 244/244, 5/5, 60/0, link-objects-test ok, exit 0 |
| gamma | `pixi exec -s actionlint -s shellcheck -- actionlint .github/workflows/repo.yaml` | clean |
| delta | after the review edits (docstring, `file.copy` check): subset build again + conda consumer install-test.R | 8 built, exit 0; 4/4, LIB as F25 |
| delta | negative: the stock build 13 env (published rzig) `build-repo.R` on digest | `FAILED digest rpath other than $ORIGIN: <env>/lib (rzig before build 14 ...)`, exit 1 |
| delta | negative: conda consumer with `LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu` | the host's libxml2.so.16.1.2 wins over the RUNPATH (D23: the user can still override) and install-test.R flags it (`NOT from the package or R`), exit 1 |

### Not verified (U5)

- linux-aarch64 (D13: delta has no qemu binfmt); the repo.yaml leg would
  be the first run.
- repo.yaml itself (no dispatch from here), including its new
  embed-test step on the runners' python.
- The package build with upstream zig (F8 covered a subset before the
  change; the carried libraries do not depend on the zig).
- Windows and macOS wheels with the new Rprofile.site (same R code,
  `.Platform$path.sep`; no kappa or omicron run in this track);
  `wheel-test-windows.py` has no user-library check.
- macOS `@loader_path` for `R_ZIG_ENV_RPATH=origin` (unit-tested
  argv only; the repository is linux only).
- A Python process that already has another OpenMP runtime (numpy,
  torch) loading data.table's carried libomp.
- The comment-only edit of compiler.zig made after the rzig test sync
  (a reference to this record) was not rebuilt.

### Open (for the user; menus, experimental)

5. **xml2's size (D17).** (a) ★ keep carrying ICU (14.5 MB binary) for
   now; (b) ask libs-zig-pixi for a linux-64/linux-aarch64 static
   `zig-libxml2` without ICU, as on Windows, and build xml2 against it
   (no carried library, no build path inside, F29); (c) drop xml2 from
   the list until (b).
6. **The wheel's user library is shared with conda r-zig (D21).** Once
   the wheel's R creates `~/.local/share/R/linux-64-zig/4.6`, a conda env
   R of the same x.y also puts it first (patch 0001's shared default), so
   its install.packages() goes there instead of the env. (a) ★ keep it
   (CRAN R's behaviour; one user library per R x.y and platform);
   (b) give the wheel its own default (e.g. `linux-64-zig-wheel`, set
   in the wheel's Renviron.site); (c) per-venv: the wheel ships an
   existing `R_HOME/site-library` and creates no user library.
7. **Closed by U9 and D26 ("rpy2 without setup (U9)").** Installing rpy2 beside the wheel (F37; run time is D25). rpy2
   finds the wheel's R with no setup once installed, but on linux
   `pip install rpy2` builds rpy2-rinterface from source and stops
   unless R is found or `RPY2_CFFI_MODE=ABI` is set. (a) ★ keep D25 and
   ask rpy2 upstream to build the ABI mode when no R is found in its
   default (ANY) mode, as it already does when no compiler is found;
   then `pip install r-zig rpy2` works in one command; until then
   repo/README.md names `RPY2_CFFI_MODE=ABI` for linux; (b) the .pth
   sets `R_HOME` at every Python start (D25's option b): `pip install
   rpy2` works once r-zig is installed (not in the same pip command), and
   every other R started from that Python prints `WARNING: ignoring
   environment value of R_HOME` on stdout; (c) leave rpy2's install to
   rpy2 and say nothing.

## Review fixes (2026-11-26)

The track review found five problems, all claims beyond the evidence or
stale records; each is fixed here. Delta dir `~/rz/wt/build14-l5b`
(scripts in `scratch/`, logs in `scratch/logs2/`). Build env as F13
(published build 13 + this worktree's rzig, `setup-env.sh`); the wheel
built again from this worktree (`-e minimal build`, `-e minimal
toolchain`, `-e wheel wheel`); repository built again in full.

| review finding | result |
|---|---|
| 1. README claimed rpy2 works from anywhere; F27 showed `r_home is None` from a venv not activated; Open 7 (a) was the setup U5 rules out | fixed for using rpy2, not for installing it (Open 7): D25 (`r_zig.pth` finder); F36: rpy2 from the non-activated venv with nothing set loads all 14 rows from the user library; README.md and repo/README.md say what works and that installing rpy2 on linux still needs `RPY2_CFFI_MODE=ABI` (F37); Open 7 rewritten |
| 2. F26's "a new session finds all 14" was not in the kept log (the step failed on a script bug) | fixed: F26 corrected in place; F35 is a new session finding and loading all 14 from the default library, on delta and in python:3.12-slim |
| 3. "What is here" table stale (`R_ZIG_ENV_RPATH=0`, `--build`, SystemLibs; files missing) | fixed: table rewritten (origin, D18 install + tar, RZig-Bundled, embed-test.py, make-wheel.py, wheel-test.sh, `_rpy2.py`) |
| 4. User-library path given as linux-64 only | fixed: README.md and repo/README.md give `$XDG_DATA_HOME` or `~/.local/share`, then `R/<platform>-zig/<x.y>` with linux-64 and linux-aarch64 examples (patch 0001); D21 likewise. repo/README.md's layout line no longer says `--build` tarballs |
| 5. The builder copied a library's needs without checking that the library can find them (no rpath passed) | fixed: D24 (`origin_dir()` in build-repo.R, comment rewritten); F34 |

Files changed by these fixes: `repo/build-repo.R` (`origin_dir()`, the
check, comment), `python/r_zig/_rpy2.py` (new), `scripts/make-wheel.py`
(`r_zig.pth` entry, r-zig's PyPI description), `scripts/wheel-test.sh`
(rpy2 block), `README.md` (L5 section), `repo/README.md`, this record.

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F34 | V | **The copied-library check works:** the full list builds as before (16 built, 0 failed, 68.6 s wall; RZig-Bundled as F24; `logs2/build-full.log`), and with a copy of the build env whose `libxml2.so.16.1.4` had its `$ORIGIN/.` rpath removed (`patchelf --remove-rpath`, test only) `build-repo.R out-neg xml2.tsv` exits 1: `FAILED xml2 libxml2.so.16 needs libicuuc.so.78 but has no $ORIGIN rpath to find them beside it` (`logs2/build-neg.log`). The regex was checked on `$ORIGIN`, `$ORIGIN/`, `$ORIGIN/.`, `${ORIGIN}` (accepted) and `$ORIGIN/../lib`, `$ORIGIN.`, `/usr/lib`, none (refused) |
| F35 | V | **A new session finds all 14 by default** (`scratch/newsession.R`: asserts `.libPaths()[1]` is `R_LIBS_USER`, then for each row `library()`, `find.package()` in that directory, the row's smoke): wheel in a venv of delta's /usr/bin/python3 3.14, fresh HOME, `env -i`, `PATH=/usr/bin:/bin`, after `install.packages(<14 rows>, repos = file://...)` with defaults: `NEW-SESSION 14 of 14 ok`, libomp, libxml2 and ICU mapped from the user library's packages (`logs2/wheel-consumer2.log`); the same in python:3.12-slim (`logs2/docker-tests2.log`) |
| F36 | V | **rpy2 from a venv not activated** (rpy2 3.6.9, rpy2-rinterface 3.6.7 installed with `RPY2_CFFI_MODE=ABI`; then `env -i HOME=... PATH=/usr/bin:/bin <venv>/bin/python -I scratch/rpy2test2.py`, which asserts no R_HOME, no LD_LIBRARY_PATH and no `R` on PATH): `R.home()` is `r_zig.r_home()`, `.libPaths()[1]` the user library, `RPY2 14 of 14 ok` (each row from the user library with its smoke), carried libraries mapped from the packages (delta 3.14 and python:3.12-slim). Control, `r_zig.pth` moved away: `ValueError: r_home is None`. Activated venv: same R and library. A user's `R_HOME=/nonexistent/R` is kept (`get_r_home()` returns it). A process that does not import rpy2 has no `R_HOME`. Option (b) prototype (`os.environ.setdefault("R_HOME", ...)` in the .pth): a subprocess `R RHOME` of the conda build env prints `WARNING: ignoring environment value of R_HOME` before its path; with D25's finder it prints the path alone (`logs2/rpy2d.txt`, `logs2/rpy2beta.txt`) |
| F37 | V | **Installing rpy2 on linux:** PyPI's rpy2-rinterface 3.6.7 has wheels for macOS and Windows only (PyPI JSON API), so pip builds the sdist; its setup.py loads `situation` with `spec_from_file_location` (no import of `rpy2`, so D25's finder does not apply) and exits `rpy2 in API mode cannot be built without R in the PATH or R_HOME defined` when neither is there, in the default ANY mode too. From the non-activated venv: fails (`logs2/rpy2-install.log`); `pip install <r-zig wheel> rpy2` in one command in a fresh venv: fails the same way (pip builds before it installs; `logs2/rpy2-oneshot.log`); with option (b)'s .pth: `pip install rpy2` after r-zig succeeds and rpy2 starts the wheel's R (pip ran with `-q`, so the log is empty and the mode it chose is not recorded; delta has no C compiler); with `RPY2_CFFI_MODE=ABI`: succeeds. Open 7, answered by D26: the second command now succeeds with no variable (F41); one command still fails cold (F44) |
| F38 | V | **Containers again** (`scratch/docker-tests2.sh`; ubuntu:24.04 glibc 2.39 and rockylinux:8 glibc 2.28, neither has libxml2.so.16 or libomp): conda consumer env (r-zig-slim 13 alone) 16 installed, 14/14, libxml2 from the package, libomp and ICU from the env; the wheel's R tree run directly: 14/14, libomp, libxml2 and ICU from the packages; rockylinux:8 platform-python 3.6 embedding the conda libR and the wheel's libR: 14/14 each. python:3.12-slim: pip installs the wheel, all rows with `install.packages()` defaults into `/tmp/h/.local/share/R/linux-64-zig/4.6`, new session 14/14 (F35), embed-test.py 14/14, rpy2 (installed with `RPY2_CFFI_MODE=ABI`) from the non-activated venv 14/14 (F36) |
| F39 | V | **conda env R again:** consumer env (r-zig-slim 13 alone, `env -i`): install-test.R 16 installed in 4.1 s, 14/14; embedded in /usr/bin/python3 3.14 (conda libR): 14/14. Duplicates (build env copy, XML from CRAN source with the env RUNPATH, xml2 from the repository): one libxml2 mapped per process in both load orders (xml2 first: the carried copy; XML first: the env's 2.15.4) (`logs2/consumer-conda.log`, `logs2/dup.log`) |
| F40 | V | `pixi run --locked -e wheel wheel-test` with the new block (stand-in `rpy2` module: `R_HOME` empty before the import, the wheel's R_HOME after it with the venv not on PATH; a set `R_HOME` kept): `wheel test passed`, twice (after the first sync and after the last text edit; `logs2/wheel-test.log`, `logs2/wheel-test-final.log`); the block's check prints an empty `R_HOME` with `r_zig.pth` removed, so it fails without the fix. Start cost (`python -X importtime -c pass`): `r_zig` 352 us cumulative, `r_zig._rpy2` 475 us cumulative |

### Tests (review fixes)

| where | command | result |
|---|---|---|
| delta | `setup-env.sh`, then `Rscript repo/build-repo.R out` (build 13 + this rzig) | 16 built, exit 0 (F34) |
| delta | the same with libxml2's rpath removed, `xml2.tsv` | exit 1 with D24's reason (F34) |
| delta | `pixi run --locked -e minimal build`, `-e minimal toolchain`, `-e wheel wheel` | exit 0; r_zig wheel 51.1 MiB, 1458 files, holds `r_zig.pth` and `r_zig/_rpy2.py` in RECORD |
| delta | `pixi run --locked -e wheel wheel-test` (twice) | passed (F40) |
| delta | `scratch/wheel-consumer2.sh` (host python venv, never activated) | user library first; install defaults into it; new session 14/14 (F35); install-test.R 14/14; embed-test.py 14/14 |
| delta | rpy2: ABI install, run non-activated; control without the .pth; activated; user R_HOME; option (b) prototype; one-shot install | F36, F37 |
| delta | `consumer-conda.sh`, `dup-test.sh` | F39 |
| delta docker | `scratch/docker-tests2.sh` | F38 |
| delta | `touch zigbuild/tools/rzig/compiler.zig; pixi run --locked rzig-test`, conda-forge zig 0.17.1, then upstream PyPI ziglang 0.17.1 (`ZIG_BIN=<fetch-zig>`) | each: 244/244, fetch.zig 5/5, check-test.sh 60 passed 0 failed, link-objects-test ok, exit 0 (rzig unchanged by these fixes) |

Large outputs deleted on delta (build env, repository, venvs, caches,
dist, the worktree's .pixi and build); scripts and logs kept; docker
images pulled for the tests removed again.

### Not verified (review fixes)

- `pip install rpy2` on linux with no variable (F37; Open 7). Only run
  time is fixed. (Done later: D26, F41.)
- rpy2 with the finder on macOS and Windows wheels (same Python code;
  no omicron or kappa run); rpy2 in API mode (no C compiler on delta or
  in python:3.12-slim, so every rpy2 here was ABI mode).
- linux-aarch64 (D13), repo.yaml itself (no dispatch), the package
  build with upstream zig (F8 subset only), as listed under "Not
  verified (U5)".
- A Python that runs with `-S` (no site) does not process `r_zig.pth`;
  rpy2 then needs `R_HOME` as before. Not tested.

### Suggested commit messages (U3, U5; superseded: b14-review/PLAN.md, "Build 14 commit plan")

```
feat: repository binaries carry the libraries they link outside R, found through $ORIGIN (R_ZIG_ENV_RPATH=origin)
feat: the r-zig wheel creates its per-user package library at the first start
feat: rpy2 finds the r-zig wheel's R from a venv that is not activated
test: install-test.R and embed-test.py check where carried libraries load from
docs: mark the binary package repository experimental
```

## rpy2 without setup (U9) (2026-11-26)

The user's U9 (Open 7): installing and using rpy2 beside the r-zig
wheel must need no environment variable and no extra setup, with no
change to rpy2 upstream; option (b) (`R_HOME` at every Python start) is
turned down for its side effect (F36: every other R started from that
Python prints `WARNING: ignoring environment value of R_HOME`). Explorer
prototypes on delta: `~/rz/rpy2-r-side/` (v0-v3), `~/rz/rpy2-pth-scoped/`
(V0-V5, VB), `~/rz/rpy2-packaging/` (C1-C4). This implementation: delta
`~/rz/rpy2-impl/` (worktree copy in `src/`, wheel built there with
`pixi run --locked -e minimal build`, `-e minimal toolchain`, `-e wheel
wheel`; repository built again from build 13 + this rzig, `scratch/`;
container scripts `scratch/t-impl.sh`, `t-impl2.sh`, `t-pip26.sh`; logs
in `scratch/logs/`).

### Design (D26)

One meta path finder, installed by `site-packages/r_zig.pth` (`import
r_zig._rpy2`, unchanged), acting on two imports, each at most once;
it removes itself after both have fired (not after the first: a
process that imports setuptools before rpy2 would lose D25):

| trigger | when | sets |
|---|---|---|
| `rpy2` imported (D25, extended) | `R_HOME` unset | `R_HOME` = the wheel's R; `RPY2_CFFI_MODE=ABI` unless set |
| `setuptools` imported | neither `R_HOME` nor `RPY2_CFFI_MODE` set, and the current directory holds `src/rpy2/rinterface_lib/_rinterface_cffi_build.py` (rpy2-rinterface 3.6 source package) or `rpy2/rinterface_lib/_rinterface_cffi_build.py` (3.5 layout) | `RPY2_CFFI_MODE=ABI` only |

pip, `build` and pyproject_hooks run the build backend with the
unpacked source as the current directory, under the target venv's
python; the `.pth` runs before pip's build-environment `sitecustomize`,
so the finder is in place in isolated and non-isolated builds. rpy2's
ABI build needs no R and no compiler, and gives
`rpy2_rinterface-3.6.7-py3-none-any.whl`, which holds no path.
~~safe in pip's cache across environments~~ (corrected in review, F48:
that wheel has no API module and no `_bufferprotocol`, and pip reuses
it in every later environment, which then runs ABI; D27 limits the
build trigger to hosts where rpy2 would find no R). At run time the ABI default
makes rpy2 open the wheel's libR even when its compiled module came from
elsewhere (an API wheel in pip's cache built against a system R, F43).

### Decisions

| id | question | options (chosen in bold) | reason |
|---|---|---|---|
| D26 (exp.) | installing rpy2 beside the wheel with no variable (U9) | **build-scoped ABI (explorer v1b) joined with D25's run-time finder, plus `RPY2_CFFI_MODE=ABI` as the run-time default when the finder sets `R_HOME`**; VB (`R_HOME` at every start); V5 (act on `import pip`); C1/v1a (`R_HOME` in rpy2's build); a vendored `rpy2_rinterface` dist-info in r-zig; an `r-zig[rpy2]` extra or companion package; an rpy2 change | covers every case VB covers (F41, F42) and touches only processes that build or import rpy2 (F45). VB: the `R_HOME` warning in every other R (F36). V5: sets `R_HOME` in every process that imports pip (pip-tools, tools using pip as a library), needs an `argv[0] == "_in_process.py"` guess, and still builds against R for no gain. C1/v1a: the build then depends on R and `R CMD config`, and gives ABI today only because the API link fails (F46); once that link works, pip's cache would hold API wheels with an rpath into one venv's libR and reuse them in other venvs. Vendored dist-info: clashes with the real package and pins its version. Extra or companion: same pip ordering as one command (F44). The rpy2 change is excluded by U9. Default by me, 2026-11-26, inside U9 |

### Alternatives measured (explorers, delta docker; recorded here)

| design | two-command install, venv not activated | one command, cold | side effect | note |
|---|---|---|---|---|
| D25 alone (before) | fails without `RPY2_CFFI_MODE=ABI` (F37) | fails (F37) | none | run time only |
| VB: `R_HOME` in the `.pth` at every start | works | fails | every other R started from that Python warns about `R_HOME` (F36) | turned down by the user |
| V5: act on `import pip` | works | fails | `R_HOME` set in every process that imports pip | needs an argv heuristic |
| C1 / v1a: `R_HOME` in rpy2's build | works, ABI only because the API link fails (F46) | fails | none outside the build | cache risk once API links |
| v1b: `RPY2_CFFI_MODE=ABI` in rpy2's build | works (python:3.12, python:3.12-slim, ubuntu:24.04) | fails | none | D26's build half |
| **D26** (v1b + D25 + ABI at run time) | **works, four images (F41)** | **fails cold (F44); works from pip's cache (F42)** | **none (F45)** | this record |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F41 | V | **Two-command install with no variable, venv not activated** (`env -i HOME=/tmp/h PATH=/usr/local/bin:/usr/bin:/bin`; `pip install <build14 wheel>`, then `pip install -v --no-cache-dir rpy2`): python:3.12-slim (no compiler, pip 25.0.1), python:3.12 (gcc and Debian's R 4.5.0 on PATH), ubuntu:24.04 (pip 24.0), rockylinux:8 (python3.12, pip 23.2.1, glibc 2.28): rc 0, `cffi mode: CFFI_MODE.ABI`, `ABI mode interface built.` in each; also `python -I -m pip` (T5), `--no-build-isolation` with setuptools, cffi, wheel preinstalled (T6), and `pip --python <venv>` from another venv (T9), each in all four images; with pip 26.3 (python:3.12-slim) too. In use (T3), venv not activated: `R.home()` is `r_zig.r_home()`, mode ABI, `sum(1:10)` 55, only the wheel's libR.so mapped, also in python:3.12 where `/usr/bin/R` is on PATH (since D27 the finder steps aside there: rpy2 builds API against `/usr/lib/R` and uses it, F49). 14-row smoke (`rpy2test2.py`, the 14 rows installed with `install.packages()` defaults from this build's repository): `RPY2 14 of 14 ok` in all four images (`logs/dk-*.log`, `logs/dk2-*.log`, `logs/dk3-pip26.log`) |
| F42 | V | **One command from pip's cache:** after a two-command install filled `--cache-dir` with `rpy2_rinterface-3.6.7-py3-none-any.whl`, `pip install <wheel> rpy2` in a fresh venv: rc 0 in all four images, the cached wheel used, rpy2 ABI on the wheel's R |
| F43 | V | **Stale API wheel in the cache** (python:3.12 + Debian r-base-core and r-base-dev): `pip install rpy2` in a venv without r-zig built `rpy2_rinterface-3.6.7-cp312-cp312-linux_x86_64.whl` in API mode against `/usr/lib/R` (`API mode interface built.`); `pip install <wheel> rpy2` in a fresh venv reused it (`_rinterface_cffi_api.abi3.so` installed). With D26: mode ABI, `R.home()` the wheel's, libR mapped only from the wheel, `sum(1:10)` 55. Control, `RPY2_CFFI_MODE=API` set by the user (the finder keeps it): `tools.so: undefined symbol: Rf_strchr_const` (the system libR with the wheel's R_HOME). So the run-time ABI default is needed (`logs/dk2-python_3.12.log`) |
| F44 | V | **One command cold still fails** without R on PATH (`pip install --no-cache-dir <wheel> rpy2`: python:3.12-slim, ubuntu:24.04, rockylinux:8): `rpy2 in API mode cannot be built without R in the PATH or R_HOME defined`; pip builds rpy2-rinterface before it installs anything, so no r-zig code exists yet, and rpy2's ANY mode calls `sys.exit` inside `except Exception` (`_rinterface_cffi_build.py:206`). With Debian's R on PATH (python:3.12) it succeeds: rpy2 finds `/usr/lib/R`, its API link fails, ABI is built, and at run time the finder points it at the wheel's R |
| F45 | V | **No side effect:** a plain start of the venv's python leaves `R_HOME` and `RPY2_CFFI_MODE` unset; `subprocess.run([<other R>, "RHOME"])` from it prints the path with no warning (python:3.12: Debian's `/usr/bin/R`; the other images: a copy of the wheel's R tree). After `import rpy2.robjects` the warning appears, as before D26 (rpy2's embedded.py exports `R_HOME`; F36). wheel-test's block (stand-ins for rpy2 and setuptools, `env -i`, venv not on PATH): 10 checks pass (plain start untouched; rpy2 sets both; a set `R_HOME` kept with the mode untouched; a set mode kept; setuptools in a source tree gives ABI and no `R_HOME`; elsewhere nothing; a set mode or `R_HOME` blocks it; setuptools then rpy2 both fire; the finder leaves after both). With `r_zig.pth` removed (delta, the same stand-ins): `- -` for both imports, so the checks depend on the fix; `python -S` runs no `.pth` (`- -`). Start cost (`-X importtime -c pass`): `r_zig._rpy2` 506-564 us cumulative, `r_zig` 346-415 us (F40: 475 us) |
| F46 | V | **The wheel's `R CMD config --ldflags` names libraries the wheel has only by SONAME** (explorer C4): `-lpcre2-8 -lzstd -llzma -lbz2 -lz -lrt -ldl -lm -liconv` from Makeconf `LIBS = -L$(R_HOME)/../../lib ...`, while `R/lib` holds `libpcre2-8.so.0`, `libzstd.so.1`, `liblzma.so.5`, `libbz2.so.1.0`, `libz.so.1`, `libiconv.so.2` and no unversioned link, so any link against the wheel's R that uses those flags (rpy2's API mode: `collect2: error: ld returned 1 exit status`, `API mode interface not built because: COMPILATION_STATUS.COMPILE_ERROR` in the uv and cold-with-R logs) fails on a host without the -dev links (`-liconv` is not in glibc). Not fixed here; D26 does not depend on it. A separate topic for the wheel's Makeconf |
| F47 | V | **Front ends that build in their own new venv:** uv (`uv pip install --no-cache rpy2`) with the venv activated: works through the wheel's `R` on PATH (`R home found: <venv>/.../r_zig/R/lib/R`, ANY mode, API link fails, ABI), use ABI on the wheel's R, all four images; uv not activated: fails (`R home found: None`) except in python:3.12, where it built against Debian's R (ABI after the API link failed) and the finder points it at the wheel's R. pip 26.3 `--use-feature=venv-isolation`: activated works (same way as uv), not activated fails; pip 23.2.1-25.0.1 in the images have no such feature (usage error, rc 2) |

### Changes

| file | change |
|---|---|
| `python/r_zig/_rpy2.py` | `_RHomeForRpy2` replaced by `_Rpy2Finder` (two triggers, removal after both; `R_HOME` from `r_zig.r_home()`) |
| `scripts/make-wheel.py` | the `.pth` comment; r-zig's PyPI description (two commands, ABI build) |
| `scripts/wheel-test.sh` | the rpy2 block: stand-in rpy2 and setuptools, ten checks (F45) |
| `README.md` (L5 section), `repo/README.md` | installing rpy2 in two commands with no variable; the limits |
| this record | D26, F41-F47, U9 answered, Open 7 closed; D25, F27, F37 point here |

### Tests (U9)

| where | command | result |
|---|---|---|
| delta | `pixi run --locked -e minimal build`, `-e minimal toolchain`, `-e wheel wheel` (`~/rz/rpy2-impl/src`) | exit 0; r_zig wheel 51.1 MiB with the new `r_zig/_rpy2.py` and `r_zig.pth` |
| delta | `scratch/repo.sh` (build 13 env + this rzig, `build-repo.R`) | 16 built, 0 failed |
| delta | `pixi run --locked -e wheel wheel-test` | `wheel test passed`; rpy2 block 10/10 (F45) |
| delta | the stand-in checks with `r_zig.pth` removed, and with `-S` | `- -` (F45) |
| delta docker | `run-dk.sh` (`t-impl.sh`): T1, T3, T4, T5, T6, T9, uv, venv-isolation, cold one-command, warm cache, stale cache in python:3.12-slim, python:3.12, ubuntu:24.04, rockylinux:8 | F41, F42, F44, F45, F47; its 14-row step ran with `PATH=/usr/local/bin` and failed processx's smoke (`cannot start processx process 'true'`), a test bug; its stale-cache step had no API wheel (no r-base-dev) |
| delta docker | `run-dk2.sh` (`t-impl2.sh`): 14-row smoke with the full PATH; stale cache with r-base-dev | 14/14 in all four (F41); F43 |
| delta docker | `t-pip26.sh` (python:3.12-slim, pip 26.3) | F41, F47 |

### Not verified (U9)

- macOS and Windows: PyPI has rpy2-rinterface wheels there, so only the
  run-time trigger applies; not run (no omicron or kappa run). Windows
  cp313 builds from source and should take the setuptools trigger;
  untested, as is `wheel-test-windows.py` (it has no rpy2 block).
- linux-aarch64 (D13).
- `python -m build`, pipx, Poetry, conda's and pixi's PyPI installs.
- An rpy2 checkout installed with `pip install -e .` in the venv (gets
  ABI unless `R_HOME` or `RPY2_CFFI_MODE` is set; documented, not run).
- rpy2 3.5 (the second accepted layout); only 3.6.9 / rpy2-rinterface
  3.6.7 ran.

### Limits (for the user)

1. `pip install r-zig rpy2` in one command fails cold without an R on
   PATH (F44); it works once pip's cache holds the ABI wheel (F42). Only
   an rpy2 change (catch `SystemExit` in ANY mode, or linux wheels on
   PyPI) closes it, and U9 excludes upstream changes. The documented way
   is two commands.
2. Front ends that build in their own new venv (uv, pip
   `--use-feature=venv-isolation`, likely `python -m build`, pipx) need
   the venv activated (F47). If pip makes venv isolation its default,
   the two-command install from a venv not activated breaks again.
3. The source-tree check follows rpy2's file layout; a rename fails as
   before D26 (a loud build error, not a wrong build).
4. rpy2 under the finder always runs in ABI mode; API cannot be built
   against the wheel today anyway (F46).
5. Another R started after `import rpy2` still warns about `R_HOME`
   (rpy2's own export, F45).

Limit 4 is extended and limits 6-8 added by the review (D27, F48-F51).

### Suggested commit message (U9)

```
feat: rpy2 installs beside the r-zig wheel with no variable (ABI build in an rpy2 source tree, ABI by default at run time)
```

## Review of D26 and D27 (2026-11-26)

A review re-ran D26 in docker on delta (`~/rz/rpy2-review/`, logs
`log-*.log`) and confirmed F41, the cold one-command failure (F44), F45
and the macOS/Windows reading, and found four problems. Fixes: delta
`~/rz/rpy2-fix/` (test scripts `scratch/t-d27.sh`, `scratch/t-remedy.sh`;
logs in `logs/`); wheel rebuilt in `~/rz/rpy2-impl/src` (`pixi run
--locked -e wheel wheel`; the files D26 left there are in
`~/rz/rpy2-impl/pre-d27/`), its `r_zig/_rpy2.py` byte-identical to the
worktree's (sha256 `da72e38f...`), `r_zig.pth` still `import
r_zig._rpy2`.

| review finding | outcome |
|---|---|
| 1. The ABI wheel in pip's cache downgrades unrelated environments | fixed where another R exists (D27, F49); a residual on hosts that had no R when rpy2 was built is recorded with its remedy (F50, limit 7) |
| 2. `pip install --user r-zig` (or a non-venv Python) switches rpy2 to the wheel's R ahead of the R on PATH | fixed (D27, F49) |
| 3. The finder never steps aside for an R on PATH, so rpy2 is always ABI and lacks `_bufferprotocol` | fixed for hosts with another R (D27, F49); on the wheel's R rpy2 stays ABI, now disclosed (limit 4, F51) |
| 4. The PyPI description promises more than the tests show | fixed: the description says experimental, tested on linux x86_64 only, and when the hook acts (F51) |

### Decision

| id | question | options (chosen in bold) | reason |
|---|---|---|---|
| D27 (exp.) | when the finder acts (review findings 1-3) | **only where rpy2 would find no R or this wheel's R: `R_HOME` unset or this R; with `R_HOME` unset, the first `R` on `PATH` missing or an r-zig `R` (a file under an `r_zig/R` tree, or a script or launcher naming `r_zig`), and on Windows no R in the registry (rpy2's last resort). Both triggers use this one test; it runs on those two imports only, never at start**; (b) act only when `r_zig.pth` sits in the running interpreter's own `sys.prefix` site-packages; (c) keep D26 and document | the hook then only fills the gap where rpy2 stops (`r_home is None`, the build's `sys.exit`) or would pick this R anyway, so on a host with another R rpy2 builds and runs exactly as without r-zig: API against that R with a compiler, a `cp312` wheel in pip's cache, `_bufferprotocol` (F49). It covers the user site, system and conda Pythons by itself. (b) fixes finding 2 only: a venv with r-zig still builds ABI next to a system R and gcc and caches it (finding 1), and a non-venv Python with r-zig in its own prefix still overrides the R on PATH. (c) leaves findings 1-3. Cost: a non-activated venv with another R on PATH now gets that R; activating the venv, or `R_HOME` set to `r_zig.r_home()` (which now also gets the ABI default, F49), chooses the wheel's. Default by me, 2026-11-26, inside U9 (no upstream change) |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F48 | V | **Review finding 1 confirmed before the fix** (reviewer's `log-cache.log`, `log-mv.log`): with D26, a venv with r-zig on a host with Debian R 4.5.0, r-base-dev and gcc cached `rpy2_rinterface-3.6.7-py3-none-any.whl` (only `_rinterface_cffi_abi.py`); a later venv with no r-zig on that cache ran `CFFI_MODE.ABI`, no `_bufferprotocol`, and `IntSexpVector.memoryview()` failed with `ModuleNotFoundError: numpy`; the control cache built `cp312-cp312-linux_x86_64` (API, `memoryview()` `[1, 2, 3]`). rpy2-rinterface 3.6.7's `setup.py` builds `_bufferprotocol` (it needs only `Python.h`) only in API mode, and its API module links with `-Wl,-rpath,<R lib>` (`_rinterface_cffi_build.py`), which is why D26's build trigger does not set `R_HOME` to the wheel's R |
| F49 | V | **D27 in docker** (`t-d27.sh`, python:3.12 with gcc; logs `d27b-python_3.12.log`). Debian R and r-base-dev installed: control (no r-zig) API, `/usr/lib/R`, `_bufferprotocol`, `memoryview()` `[1, 2, 3]`, cached `cp312-cp312-linux_x86_64`. **Finding 1:** a venv with r-zig, not activated, fresh cache: `cffi mode: CFFI_MODE.ANY`, `API mode interface built.`, cached `cp312-cp312-linux_x86_64`; that venv not activated: API, `/usr/lib/R`, `memoryview()` `[1, 2, 3]`; an unrelated venv on the same cache: API, `/usr/lib/R`, `memoryview()` `[1, 2, 3]`. The same r-zig venv activated: ABI on the wheel's R, `sum(1:10)` 55, `_bufferprotocol` present (it came with the API wheel), `memoryview()` `[1, 2, 3]`; with `R_HOME` set to the wheel's R and not activated: the same (before this change: `tools.so: undefined symbol: Rf_strchr_const`, the user's `R_HOME` with the Debian-built API module). **Finding 2:** system python with rpy2 built against Debian R (API, `/usr/lib/R`), then `pip install --user <wheel>` (`/tmp/h/.local/lib/python3.12/site-packages/r_zig.pth` present): still API, `/usr/lib/R`, `memoryview()` `[1, 2, 3]`; the same python with `PATH=/usr/local/bin` (no R): ABI on the user site's r-zig R, `sum(1:10)` 55. **No R on the host** (before Debian R; also python:3.12-slim, ubuntu:24.04, rockylinux:8): two commands, venv not activated: rc 0, `cffi mode: CFFI_MODE.ABI`, `ABI mode interface built.`, ABI on the wheel's R, `sum(1:10)` 55, not activated and activated; a plain start leaves `R_HOME` and `RPY2_CFFI_MODE` unset (`d27b-*.log`). wheel-test's rpy2 block, now 15 checks with `PATH` set per check (no R; the venv's `R`; a stand-in other `R` first; `R_HOME` another R or this R; the setuptools cases with and without another R): `wheel test passed` (`logs/wheel-test2.log`) |
| F50 | V | **Residual of finding 1** (`d27b-python_3.12.log`, step 1b): the ABI `py3-none-any` wheel built while the host had no R stays in pip's cache; after Debian R and gcc are installed, an unrelated venv on that cache runs ABI on `/usr/lib/R` with no `_bufferprotocol` (`memoryview()` needs numpy). The ABI wheel there replaced a failed build (`sys.exit`, F44), not an API wheel; rpy2's own ANY mode caches the same ABI wheel whenever its API build fails (no compiler, no headers). The build backend cannot keep pip from caching a wheel. Remedy, verified (`t-remedy.sh`, `logs/d27-remedy.log`): `pip cache remove rpy2_rinterface` (`Files removed: 1`), then `pip install rpy2` in a new venv builds `cp312-cp312-linux_x86_64`: API, `/usr/lib/R`, `_bufferprotocol` present |
| F51 | V | **Disclosure and wording** (review findings 3, 4): on the wheel's R, rpy2 runs ABI and an ABI-built rpy2-rinterface has no `_bufferprotocol`, so `memoryview()` of an R vector needs numpy (`d27b-*.log`: `memoryview=FAILS ModuleNotFoundError` in every no-R image); limit 4 says so. `DESCRIPTIONS[DIST_NAME]` in `scripts/make-wheel.py`, shared by every platform's wheel, now says the hook is experimental, tested on linux x86_64 only, acts only when rpy2 would find no other R, and how to choose this R when another is on `PATH`; README.md and repo/README.md say the same |

### Changes (review)

| file | change |
|---|---|
| `python/r_zig/_rpy2.py` | `_no_other_r()` (D27) gates both triggers; `_is_r_zig()`, `_registry_r()`; `R_HOME` equal to this R gets the ABI default; `shutil` imported only on the two imports |
| `scripts/wheel-test.sh` | the rpy2 block: `PATH` per check, a stand-in other `R`, 15 checks |
| `scripts/make-wheel.py` | the `.pth` comment; r-zig's PyPI description (finding 4) |
| `README.md` (L5 section), `repo/README.md` | when the hook acts, how to choose the wheel's R, limits 4, 6-8 |
| this record | D26's cache claim corrected, F41 annotated, D27, F48-F51 |

### Tests (review)

| where | command | result |
|---|---|---|
| delta | `pixi run --locked -e wheel wheel` (`~/rz/rpy2-impl/src`) | exit 0; `r_zig/_rpy2.py` in the wheel = the worktree's |
| delta | `pixi run --locked -e wheel wheel-test` | `wheel test passed`, rpy2 block 15/15 (F49) |
| delta docker | `t-d27.sh` in python:3.12 (gcc, then Debian R 4.5.0 + r-base-dev), python:3.12-slim, ubuntu:24.04, rockylinux:8 | F49, F50, F51 |
| delta docker | `t-remedy.sh` in python:3.12 | F50 |

Not run: macOS, Windows (the `PATH`, launcher and registry parts of
`_is_r_zig()` / `_registry_r()` are read, not run; `wheel-test-windows.py`
has no rpy2 block), linux-aarch64, uv and venv isolation again after
D27 (the activated case now acts through the venv's `R`, the same path
as before), and the start cost (`-X importtime`; the start path imports
no new module).

### Limits (after the review)

4. rpy2 on the wheel's R runs in ABI mode (API cannot be built against
   the wheel, F46), and the ABI build has no `_bufferprotocol`, so
   `memoryview()` of an R vector needs numpy (F51).
6. With another R on `PATH` (or `R_HOME` set to it), rpy2 uses that R,
   also from a non-activated venv with r-zig; activate the venv or set
   `R_HOME` to `r_zig.r_home()` for the wheel's R (D27).
7. An ABI wheel built while the host had no R stays in pip's cache and
   is reused after the host gains an R and a compiler, until `pip cache
   remove rpy2_rinterface` (F50).
8. Tested on linux x86_64 only; the description and READMEs say so.

### Suggested commit message (review)

```
fix: the rpy2 hook of the r-zig wheel acts only where rpy2 would find no other R
```
