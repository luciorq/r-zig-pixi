# feat-shared-build-runner — one tier-1 build runner, shared by every install

**Status (2026-10-13).** Branch feat-shared-build-runner, from main
ea7e6ee (PR #26). Prototyped, implemented, then reviewed: an
adversarial review confirmed eight findings, all fixed here ("The
review"). Tested on linux-64 (gamma), osx-arm64 (omicron) and win-64
(kappa), each with conda-forge's and upstream zig: every task passed
("Tested"). CI is still to run ("CI"). Not committed: the user commits.
pixi.lock is main's, unchanged, sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96. No
build-number bump: phase 4's bump (8 to 9) publishes both packages
(feat-zig-pkg-build's N5). Three choices are left to the user ("Open
decisions").

## Why

The user, 2026-10-13: "continue with the shared builder PR before we
start phase 4". feat-zig-pkg-build's N3 gave every install its own zig
build cache, in its build root, so every tier-1 install compiled
build_t1.zig's build runner again. Stress dispatch 38467907779 (main
ea7e6ee, `shared_cache = false`, g3 g4, trace) measured that cost
against 38317654371 (one cache for the run), from the smallest tier-1
rows (fix-zig-pkg-build-review's B1 asked for this dispatch):

| runner | rows | shared, mean s | per install, mean s | added per tier-1 install |
|---|---|---|---|---|
| ubuntu-latest | askpass, base64enc, glue, magrittr | 1.1 | 4.4 | +3.3 s |
| ubuntu-24.04-arm | askpass, base64enc, glue, magrittr | 1.2 | 12.3 | +11.1 s |
| macos-latest | askpass, base64enc, glue, magrittr | 2.2 | 11.9 | +9.6 s |
| macos-15-intel | askpass, base64enc, glue, magrittr | 5.4 | 17.2 | +11.9 s |
| windows-latest | base64enc, glue, magrittr | 1.6 | 14.4 | +12.8 s |

make installs those packages in 1 to 2 s. Both runs had the same
targets, tree distribution, `builder = auto` and trace, and no
unexpected row (igraph's download failed on macos-15-intel, network).

The goal: tier-1 installs reuse one build runner per build_t1.zig and
zig across installs, while each install's objects and library stay in
its build root and go with it (N3's bounded cache), and zig's global
cache keeps A1's flat keys (sources named relative to src/). Tier 2
keeps the per-install cache unless sharing it is as simple and bounded
(it is not: "The mechanism").

## The mechanism (prototype, 2026-10-13)

zig build has no switch that keeps the runner apart from the steps:
cmdBuild compiles the runner into `--cache-dir`, then hands that
directory to the runner as its cache root, which build_runner.zig uses
for the steps' manifests (`h/`) and outputs (`o/`).
`--global-cache-dir` has to stay zig's real global cache (std,
compiler_rt, and zig cc's objects for A1), and `--build-runner`
replaces the runner's source, not where it is cached. So a shared
`--cache-dir` stays bounded only if the steps stop writing into it.

Prototyped on gamma with both zigs, through drivers that do what
pkgbuild.zig does (a fresh R.INSTALL copy per install, plan.zon in
`<src>/.rzig`, `zig build --build-file ... --cache-dir ... -Dplan=...
-jN` from src/, the root removed afterwards):

| variant | what | result |
|---|---|---|
| main's build_t1.zig on a shared `--cache-dir` | `addOutputFileArg` | `h/` and `o/` at 8, 15, 23, 32, 42 entries after 1 to 5 installs (both zigs), every install's library in the shared `o/`: a step's key hashes the whole environment, `R_SESSION_TMPDIR` included, and the cwd, so no entry is ever reused (N3's reason, fact 9) |
| A ★ | each step names its output in the build root: `has_side_effects`, `expectExitCode(0)`, the path as an argument, a `GeneratedFile` LazyPath | the shared directory at `h:2 o:2 z:2 tmp:0` after 1, 2, 5 and 10 installs of different packages, both zigs; zig's global cache `o/` at 63 entries before and after (A1 holds: only `-o` changed, not in zig cc's key); 9 one-second compiles at `-j8` in 1.33 s (main's file 1.31 s) |
| A without the stdio line | the same with no `expectExitCode` | bounded, but a step with no output argument inherits stdio, and zig build holds its stderr lock while each child runs: 10.0 s at `-j1`, `-j4` and `-j8` |
| B | readPlan re-points `b.cache_root` and the manifest directory at `<root>/zig-cache` | 6 lines, the same census and times, today's error text; not chosen: it overrides state the runner set up before `build()` runs, and the runner still writes its lazy-dependency `tmp/<nonce>` into the shared directory (build_runner.zig:475), so a later zig that writes more there would grow it with no visible failure |

Also rejected:

- rzig running a precompiled runner itself, with a per-install cache
  root: it depends on the runner's internal, unversioned argv protocol.
- A shared directory and rzig deleting the install's `o/` entries
  afterwards: post-processing, racy under concurrent installs, against
  simplicity first.
- Sharing tier 2's runner: its `dependencies.zig` embeds the install's
  build root, and the runner imports the package's build.zig from its
  R.INSTALL path, so every install compiled a new runner in any shared
  directory (about 47 MB and 3.7 s each, under every variant).
- One unkeyed directory: conda-forge's and upstream's zig both say
  0.16.0 and give the runner's manifest the same name, but conda-forge
  patches std/posix.zig and std/zig/target.zig; alternating them
  (3.71, 2.27, 3.64, 2.20 s) rebuilt the runner at every switch.
- The prototype's own key (the zig command only, R_HOME's build_t1.zig
  as the build file): zig records the build file by its absolute path,
  so each R_HOME added a 45 MB runner that nothing removed (the
  review's code-runner-growth). Replaced by the copy keyed by content
  ("What changed").

What keys a runner (the prototype's probes): the build file's path and
content, the zig version, the content of zig's lib directory (recorded
relative to it, so a byte-identical zig at another path reuses it) and
the host. Not: `-Dplan`, `--prefix`, `-j`, the install directory, the
environment, the cwd, `ZIG_GLOBAL_CACHE_DIR`, an mtime-only touch of
build_t1.zig.

Concurrency: on a cold shared directory, 2 and then 6 builds started
together, with each zig, all exited 0 and left one runner. zig's Cache
locks the runner's manifest on a miss, so the second build waits and
then hits rather than compiling its own (wall 3.64 s, user 0.48 s,
against the first's 3.63 s and 7.08 s). Each install's outputs are in
its own build root, so concurrent installs share only the runner.

## What changed

- **build_t1.zig** writes what an install makes into the build root:
  each object to `<root>/obj/<n>/<name>`, the library to
  `<root>/<output>`, Windows' `.def` beside it (`outputFile`: the path
  on the step's command line, `has_side_effects`, `expectExitCode(0)`
  for the piped stdio a step with an output file has). The Run steps'
  cache keys hash the whole environment, `R_SESSION_TMPDIR` included,
  so in a shared cache every install added entries never reused (N3,
  fact 9); now the steps always run, as they did with a cache per
  install, and put nothing in the cache. `Plan.root` is plan.zon's
  directory, set by readPlan. One numbered directory per source, where
  the prototype had `obj/<s.obj>`: OBJECTS may name two files of one
  name (`util.o`, `sub/util.o`) or one outside src/ (`../x.o`), and
  rpkg names a tier-2 source's object by its stem. Command lines keep
  make's file names, so pkg-parity's argv comparison is unchanged.
  rpkg.zig and build_t2.zig needed no change.
- **rzig build** (pkgbuild.zig's `zigBuildDirs`): `--cache-dir`, else
  `ZIG_LOCAL_CACHE_DIR`, with R_HOME's build_t1.zig as the build file;
  else for tier 1 `sharedRunner`; else, and for tier 2,
  `<build root>/zig-cache`, gone with the root. find_zig now runs
  before the directory is chosen.
- **`sharedRunner`**: `<rzig cache>/build-runner-<key>/`, the key the
  SHA-256 of build_t1.zig's content, the zig command and `zig version`
  (as cache.zig's `compiled` keys its entries). rzig writes a copy of
  build_t1.zig there once and zig builds from it: zig names the runner's
  manifest by its build file's path, relative to the cache when the
  file is in it, so every R whose build_t1.zig has that content shares
  the directory's one runner. Each use rewrites `last-used` (a
  temporary file renamed into place), which is also the check that rzig
  can create files there; when it cannot, the build root's cache, as
  before. rzig's cache is `${XDG_CACHE_HOME:-$HOME/.cache}/r-zig`
  (`%LOCALAPPDATA%\r-zig` on Windows), as for its other entries.
- **The sweep** (`sweepRunners`): each tier-1 build removes the
  build-runner directories whose `last-used` is a week old
  (`runner_idle_days`), each renamed to `<name>.<random>.old` first so
  that an install finds a directory whole or not at all, and finishes
  what an earlier sweep left. rzig's other cache entries are never
  removed, as before. An install that takes up a week-idle directory in
  the instant between another build's stat and rename fails once
  (documented in the code).
- **Error text**: a failed compile now ends with zig build's `process
  exited with code 1 (expected exited with code 0)` instead of `process
  exited with error code 1`; the compiler's message and the "failed
  command:" line are shown as before, and nothing in the repo matches
  either text.
- **Tests**: three unit tests (the dirs by tier and override, the key by
  content and zig, two R installations sharing; a directory rzig cannot
  write; the sweep); parity-test's real-zig cases (the copy as build
  file, no file of the package in the cache, a second install and an
  install from another R's rpkg adding no file); pkg-parity (one runner
  directory, its files unchanged by every later install, a kept build
  root with obj/ and no zig-cache, install.packages(Ncpus = 2) from a
  cold cache); verify-bundle (pfC's runner under the fresh HOME, none of
  its objects there; the shapes' objects in obj/); contract-test (rzig's
  cache under `build/rzig-cache`); stress.R and its README
  (`--no-shared-cache` now means rzig build's default: tier 1's shared
  runner, the rest per install).

## The review

An adversarial review of the implementation (verifier ids):

| id | finding | fixed |
|---|---|---|
| code-runner-growth | the directory was keyed by the zig command alone; zig's manifest keyed the runner by build_t1.zig's path, so every R_HOME (conda env, worktree, wheel) added a 45 MB runner, an upgrade in place a second one beside the first, and nothing removed any | the key adds build_t1.zig's content and `zig version`; zig builds from a copy in the directory (one runner per directory, shared across R_HOMEs); the sweep removes directories idle for a week |
| code-unwritable-cache | an existing directory that cannot be written (read-only file system, another user's cache) passed `createDirPath`, and zig then failed opening its manifest, exit 1, no make fallback | `last-used` is written through a temporary file on every use; any failure gives the build root's cache; unit test with a 0555 directory (skipped on Windows and as root) |
| code-contract-home-cache | `pixi run contract` left a runner per worktree and zig in the developer's ~/.cache/r-zig | contract-test.sh exports `XDG_CACHE_HOME=$BUILD_DIR/rzig-cache` (Windows through `cygpath -w`) |
| tests-1 | parity-test compared only the count of `o/` entries, so a cache growing by one `h/` manifest per install passed | it compares the directories' full file lists; a mutation dropping `has_side_effects` now fails two checks |
| tests-2 | pkg-parity's Ncpus = 2 count exited 2 under `set -euo pipefail` with no message when no directory existed | `(ls ... \|\| true)` |
| tests-3 | two pkg-parity comments described the per-install layout | reworded |
| tests-4 | stress.R said the run removes its runner at its end; an older directory it used stays | reworded (with the copy, a directory holds one runner, so the run adds none inside an older one) |
| tests-5 | the records described the per-install cache and the runner as undecided | feat-standalone-toolchain TODO.md and PLAN.md, feat-zig-pkg-build PLAN.md (N3), fix-zig-pkg-build-review PLAN.md (B1), and this file |

Noted by the review, not changed:

- On a cold cache, `R CMD check --as-cran` on linux lists the new
  `~/.cache/r-zig/build-runner-*` files under "new files in some other
  directories", as it did for dso-fini's entries: once per R and zig.
- pkg-parity's kept-root case and its tier-3 and no-make installs
  compile under the checkout, so zig cc caches those objects in the
  repository root's gitignored `.zig-cache` (build.zig is above them),
  as it did at main.
- The conda recipe's tests set `ZIG_LOCAL_CACHE_DIR`, so they build with
  it, not with rzig's cache.

## Measurements (2026-10-13)

Per install, `R CMD INSTALL` of a tarball on the compile tree, median of
three rounds, zig's global cache warm for both builders; "cold" with no
build-runner directory, "warm" with it. make goes through zig cc too,
so it is timed with each zig. Seconds:

| host, package | conda-forge: make | cold | warm | upstream: make | cold | warm |
|---|---|---|---|---|---|---|
| linux-64, askpass | 1.40 | 5.18 | 1.45 | 1.25 | 3.18 | 1.36 |
| linux-64, base64enc | 1.64 | 5.15 | 1.59 | 1.36 | 3.24 | 1.40 |
| linux-64, glue | 1.98 | 5.54 | 1.91 | 1.70 | 3.61 | 1.78 |
| linux-64, magrittr | 1.63 | 5.29 | 1.68 | 1.43 | 3.45 | 1.50 |
| osx-arm64, askpass | 1.56 | 6.90 | 1.63 | 1.53 | 6.32 | 1.62 |
| osx-arm64, base64enc | 2.25 | 7.28 | 2.10 | 2.27 | 6.62 | 2.10 |
| osx-arm64, glue | 2.31 | 7.45 | 2.21 | 2.29 | 6.73 | 2.19 |
| osx-arm64, magrittr | 2.11 | 7.33 | 2.06 | 2.12 | 6.61 | 2.08 |
| win-64, base64enc | 3.01 | 12.94 | 2.18 | 2.61 | 10.10 | 1.95 |
| win-64, glue | 3.78 | 13.83 | 3.14 | 3.37 | 10.93 | 2.74 |
| win-64, magrittr | 3.29 | 13.62 | 2.89 | 3.13 | 10.66 | 2.48 |
| win-64, mime | 2.79 | 12.83 | 2.24 | 2.51 | 10.10 | 1.96 |

(askpass is not tier 1 on Windows: its Makevars.win has a rule.) So the
runner compile costs about 3.6 s (conda-forge) and 1.9 s (upstream) on
linux-64, 5.2 s and 4.5 s on osx-arm64, 10.7 s and 8.2 s on win-64,
once per build_t1.zig and zig instead of once per install. With the
directory warm, rzig build is within 0.2 s of make on linux-64 and
osx-arm64, and 0.4 to 0.8 s faster than make on win-64.

The directory itself, one per zig:

| host | size | files |
|---|---|---|
| linux-64 | 45 MB | 8: `h/` manifest and timestamp, `o/<d>/build` (46.6 MB apparent), `o/<d>/dependencies.zig`, two `z/` files, `last-used`, the build_t1.zig copy |
| osx-arm64 | 19 MB | 9: the same, with `build` 7.0 MB and `build_zcu.o` 12.3 MB |
| win-64 | 24 MB | 10: the same, with `build.exe` 4.9 MB, `build.pdb` 6.6 MB and `build_zcu.obj` 13 MB (and zig's empty `tmp/`) |

- Bounded: on linux-64, ten packages installed twice (sys, askpass,
  base64enc, glue, magrittr, cli, digest, fansi, backports, mime) left
  one directory, its files the same after the first install and the
  twentieth; on kappa, nine packages twice, the same. On all three
  hosts, the compile tree's R and the dist tree's R (one build_t1.zig
  content, two R_HOMEs) used one directory and left its files
  unchanged.
- The sweep, on all three hosts and both zigs: a directory last used 8
  days ago went at the next tier-1 install, one used 6 days ago stayed,
  no `.old` left behind.
- A directory rzig cannot write (0555 on unix, an icacls deny on
  Windows) falls back to the build root's cache: magrittr in 5.1 s on
  linux-64, 7.3 s (conda-forge) and 6.6 s (upstream) on osx-arm64,
  13.3 s and 10.8 s on win-64, as cold; once the deny was lifted, kappa
  used the directory again (2.5 to 2.7 s).
- install.packages of sys, askpass, base64enc, glue and magrittr (on
  Windows without askpass) from a cold rzig cache, one runner compile
  included, every package through rzig build and one directory left:

  | host | zig | Ncpus = 2, zig / make | Ncpus = 4, zig / make |
  |---|---|---|---|
  | linux-64 | conda-forge | 8.7 / 4.9 s | 7.0 / 3.1 s |
  | linux-64 | upstream | 6.3 / 4.2 s | 4.8 / 2.7 s |
  | osx-arm64 | conda-forge | 10.4 / 5.1 s | 8.8 / 3.4 s |
  | osx-arm64 | upstream | 9.9 / 5.1 s | 8.0 / 3.4 s |
  | win-64 | conda-forge | 20.9 / 10.3 s | 17.7 / 7.8 s |
  | win-64 | upstream | 16.4 / 9.2 s | 13.7 / 6.8 s |

- Concurrency on kappa: 168 `R CMD INSTALL`s in rounds of 6 and of 12
  started together, cold and warm, both zigs: all built, none on the
  fallback cache, one directory, no temporary file left. Six at once:
  13.3 to 13.6 s cold and 5.5 to 5.9 s warm (upstream), 17.6 to 19.4 s
  and 6.1 to 6.4 s (conda-forge). On gamma, four `rzig build`s started
  together on a cold directory, each zig: all exit 0, one runner.
- pkg-parity's cli (27 compiles), make against rzig build: the first
  install, which also compiles the runner, 11 against 9 s on linux-64
  (conda-forge), 13 against 7 s on omicron, 30 against 17 s on kappa;
  the second install from the tarball, runner warm, 7 against 9 s on
  linux-64, 15 against 17 s (conda-forge) and 14 against 16 s
  (upstream) on kappa.
- `-j` is unaffected: 9 compiles that each sleep 1 s took 1.23 to
  1.32 s at `-j8` through rzig build (6.4 s at `-j1`).

## Tested

Every host: pixi.lock sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96,
unchanged before and after; the slim (default) environment and
conda-forge zig 0.16.0 unless named; upstream zig is PyPI's ziglang
0.16.0 from `pixi run fetch-zig`, as ZIG_BIN. omicron and kappa ran
the final code diff, sha256
2beebb85555d7f46f8ee7286cd8ef884e0c09817828aef6600bada77dfa3151a
(`git diff -- . ':!.github/devdocs' | sha256sum`, 10 files); gamma's
chain ran it but for the last two test-only edits (a unit-test helper
in pkgbuild.zig, after which `rzig-test` ran again with both zigs, and
a pkg-parity.sh line, which omicron and kappa ran). Afterwards only the
records changed. Logs under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/shared-runner/:
`proto/` (the prototype), `linux/` (the chain before the review),
`fix/` (after it), `omicron/`, `kappa/`.

### linux-64 (gamma)

The full chain ran twice, on the implementation before the review
(`linux/`, all pass) and again after the fixes (`fix/`):

| what | result |
|---|---|
| `rzig-test`, conda-forge and upstream zig | 129 unit tests; parity-test 112 identical, 0 failed, with the real `rzig build` cases; they fail against main's build_t1.zig, and a mutation dropping `has_side_effects` fails two of them |
| rzig cross-compiled for x86_64-windows-gnu, aarch64-macos, x86_64-macos, aarch64-linux-musl; the unit tests for windows and both macOS targets (`--test-no-exec`) | compile |
| `build`, `toolchain`, `verify-tree`, `compile-tree` | pass; the compile tree's share/zig/rpkg/build_t1.zig is the worktree's |
| `contract`, conda-forge and upstream zig | pass: Rcpp, minqa, quadprog through rzig build; data.table, ps make; pak mixed; one runner directory per zig under `build/rzig-cache`, nothing added to ~/.cache/r-zig |
| `pkg-parity`, conda-forge and upstream zig | pass: one runner per zig, its files unchanged by every later install; the kept root (plan.zon, obj/, the library, no zig-cache); `ZIG_LOCAL_CACHE_DIR`; Ncpus = 2 from a cold cache; tier 2, tier 3, the base with no make |
| `hermetic`, `rzig-test dist/slim/R-4.6.1-zig` (the smoke) | pass |
| `package-toolchain`, `verify-package` (slim), `-e minimal build`, `toolchain`, `verify-package` | pass: pfC's `--cache-dir .../r-zig/build-runner-<32 hex>`, one runner under the fresh HOME, none of pfC's objects in it; the shapes' objects in `.rzig/obj`; scenario 3's install.packages(Ncpus = 2) |
| `-e wheel wheel`, `wheel-test` | pass: tier 1 under PyPI ziglang, with its own HOME |
| conda packages (rattler-build, the `conda-package` command with another output dir) | r-zig-slim and r-zig-toolchain 4.6.1 build 8 built, both test phases pass, C, C++ and Fortran packages through rzig build |
| a tier-1 Windows cross-build (x86_64-windows-gnu, the real `rzig def`); tier 2 with same-stem C sources (`a.c`, `sub/b.c`, `sub2/a.c`) | `pkg2.def` in the root, the DLL linked and installed to `libs/x64`; every symbol exported |
| `zig fmt --check` (both zigs), `bash -n` on the four scripts, `parse()` of stress.R, a YAML load of stress.yaml | clean |

### osx-arm64 (omicron, macOS 26.4.1)

rsync of the worktree to a scratch copy, 2026-10-13. Pass with
conda-forge zig: `rzig-test` (129/129, none skipped, so the 0555 test
ran), `build` (113 s), `toolchain`, `compile-tree`, `pkg-parity`,
`package-toolchain`, `verify-package`, and the measurements above. With
upstream zig: `rzig-test` (129/129), `pkg-parity`, the measurements.

- pkg-parity: cli, digest, quadprog, Rcpp and minqa give the same
  exports and rzig command lines on both builders; one runner
  directory, reused; cli twice leaves zig's global cache flat (205
  entries; 130 with upstream zig); digest's kept root has plan.zon,
  obj/ and digest.so and no zig-cache; Ncpus = 2 from a cold cache in
  11 s (10 s upstream), one runner.
- verify-package: under the fresh HOME a C package builds through rzig
  build with the runner in rzig's cache, leaves no build root and
  loads; the C++, Fortran, FLIBS and OpenMP checks pass through both
  builders; install.packages(Ncpus = 2) takes btA through rzig build and
  btLib through make.
- No build-runner directory appeared under the real HOME. No Falcon
  kill (`Killed: 9`, exit 137, quarantine) in any log.

### win-64 (kappa, Windows 11)

A synced copy of the worktree (its fingerprint the same in the worktree
at the end). Pass with conda-forge zig: `rzig-test` (101 passed, 28
skipped: the Windows skips, the 0555 test among them; the key, override
and sweep tests ran), `build` (6.8 min), `toolchain`, `verify-tree`,
`compile-tree`, `contract`, `pkg-parity`, `package-toolchain`,
`verify-package`. With upstream zig: `rzig-test`, `build` (5.9 min),
`verify-tree`, `compile-tree`, `contract`, `pkg-parity`,
`verify-package` (`package-toolchain` not rerun: the toolchain tree
does not depend on zig).

- contract: every tier-1 build (quadprog, Rcpp, and pak's cli, lpSolve,
  pkgcache, yaml) ran with `--build-file <dir>/build_t1.zig --cache-dir
  <dir>`, `<dir>` being `build/rzig-cache/r-zig/build-runner-<key>`;
  one directory per zig; nothing added to `%LOCALAPPDATA%\r-zig`.
- With XDG_CACHE_HOME unset, the directory is
  `%LOCALAPPDATA%\r-zig\build-runner-<key>`, with none of an install's
  objects, DLL or `.def` in it.
- The sweep, the icacls fallback, the concurrency rounds and
  install.packages with Ncpus = 2 and 4: as in "Measurements".
- Cleaned afterwards: the scratch copy, the runner and cfguard
  directories the run made in `%LOCALAPPDATA%\r-zig`, the run's
  `%TEMP%` leftovers.

### CI

To come on the PR (menu 3): the `full-ci` label for the five platforms'
full tier (linux-aarch64 and osx-64 have no host here), and
`upstream-zig` for the five upstream legs, where the runner gets its
own directory per zig. After the merge, a stress dispatch on main
confirms the CI runners' figures:

    gh workflow run stress.yaml -f packages='g3 g4' -f trace=true -f shared_cache=false

`shared_cache = false` now means rzig build's default, as a user's
install has it: the small tier-1 rows should come back to about
38317654371's shared-cache means (1.1, 1.2, 2.2, 5.4 and 1.6 s), the
first tier-1 row of each leg carrying the one runner compile, and
report.md should name the build-runner directory among what the run
removed from rzig's cache.

## Not tested

- linux-aarch64 and osx-64 on a host (CI's legs), so the runner's size
  there is unknown.
- The 0555 unit test on Windows (skipped there; kappa checked the
  fallback by hand with an icacls deny).
- The sweep's residual race (an install taking up a week-idle
  directory between another build's stat and rename): documented, not
  provoked.
- rzig's cache on a network or shared file system.
- `R CMD check --as-cran`'s "new files" note (from the code; not run).

## Open decisions (for the user)

1. What the directory is keyed by besides build_t1.zig's content.
   - (a) ★ The zig command and `zig version`, as now: each pixi env,
     worktree or venv with its own zig has its own directory (19 to 45
     MB), and the sweep removes it a week after its last use. Two zigs
     never share a directory: zig names the runner's manifest by its
     inputs' paths, so conda-forge's and upstream's zig (both 0.16.0,
     different std files) would replace each other's runner at every
     alternation. kappa found that the command is keyed as spelled: one
     conda-forge zig reached as `C:\...\x86_64-w64-mingw32-zig.exe`
     (PATH, in contract) and as `C:/.../x86_64-w64-mingw32-zig.exe`
     (ZIG_BIN through MSYS) got two 24 MB directories. A user's
     installs find zig one way; the idle one goes after a week.
   - (b) As (a), with `\` turned into `/` in the command before keying
     on Windows: one line in `sharedRunner`, and a kappa rerun.
   - (c) `zig version` and a hash of zig's lib/std instead of its path:
     envs with the same zig share one runner, at the cost of hashing
     std's files (or caching that hash per zig) on every install.
2. How long an unused directory stays.
   - (a) ★ A week (`runner_idle_days = 7`): a runner compiles again in
     3 to 13 s, and a week keeps what is in use.
   - (b) 30 days.
   - (c) Never: no sweep, as rzig's other cache entries.
3. CI labels for the PR.
   - (a) ★ `full-ci` and `upstream-zig`, as PR #26: the runner is
     compiled by and keyed per zig, and upstream zig's legs are the
     release check.
   - (b) `full-ci` only.

## Follow-ups (not on this branch)

In feat-standalone-toolchain TODO.md unless named:

- The stress dispatch above, after the merge (`shared_cache = false`).
- With open decision 1 at (b) or (c): the key change and a kappa rerun.
- Route `R CMD SHLIB` through rzig build, or give it a preflight;
  revisit 0010 for pkgbuild's probe (as before).

## Files

- rzig (zigbuild/tools/rzig/): pkgbuild.zig (`zigBuildDirs`,
  `sharedRunner`, `useRunnerDir`, `writeWhole`, `sweepRunners`, three
  unit tests), cache.zig (header comment), parity-test.sh.
- rpkg (zigbuild/rpkg/): build_t1.zig.
- Tests: scripts/pkg-parity.sh, verify-bundle.sh, contract-test.sh.
- stress: stress.R, README.md; .github/workflows/stress.yaml (the
  `shared_cache` input's description).
- Records: this file; feat-zig-pkg-build/PLAN.md (N3);
  fix-zig-pkg-build-review/PLAN.md (B1); feat-standalone-toolchain
  TODO.md and PLAN.md. consolidation/CONSENSUS.md and
  fix-zig-pkg-build-review's `review/` are left as they were agreed.

## How to rerun

    pixi run rzig-test                                 # unit tests, parity-test's real rzig build cases (linux)
    ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test   # the same with upstream zig
    pixi run pkg-parity                                # one runner, unchanged files, the kept root, Ncpus = 2 from a cold cache
    pixi run contract                                  # rzig's cache in build/rzig-cache, one runner directory per zig
    pixi run verify-package                            # pfC's runner under a fresh HOME, the shapes' objects in .rzig/obj
    RZIG_TRACE=1 R CMD INSTALL -l <lib> <pkg.tar.gz>   # the log names --build-file and --cache-dir (build-runner-<key>)
    gh workflow run stress.yaml -f packages='g3 g4' -f trace=true -f shared_cache=false
