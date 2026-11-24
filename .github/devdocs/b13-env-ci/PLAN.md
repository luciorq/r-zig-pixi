# b13-env-ci: environments, wheels and CI for build 13

Branched from origin/main 7e3648e (build 12 published, run
45381914199). Items from chore-release-12/BACKLOG.md: L8, L2, L1, M-24,
CI9, CI11, and the CI dispatch list for the wave (CI1, CI3-CI7).

## Goal

- L8: pixi.toml's `[dependencies]` split into features, so minimal no
  longer repeats the toolchain. No env's specs and no lock entry change.
- L2: Windows wheels (win-64, win-arm64) from make-wheel.py, a Windows
  wheel test, and the wheel steps on the Windows minimal CI legs.
- L1: a release workflow (standalone archives, GitHub Release, PyPI)
  that is gated off.
- M-24: the win.binary-by-default experiment, behind an opt-in, with
  findings. The default stays "source".
- CI9, CI11: check and explain. The wave's dispatch commands.

Files: pixi.toml, pixi.lock, scripts/make-wheel.py, the new
scripts/wheel-test-windows.py, .github/workflows/{build-r,build,stress}.yaml
and the new release.yaml and win-binary.yaml. python/r_zig/__init__.py
(the wheel's own Python package: Windows launch and ZIG_BIN) is not this
topic's file: its change is need 0 below (review).

## Decisions

| id | question | options (chosen in bold) | reason | who |
|---|---|---|---|---|
| E1 | L8 shape | (a) shared toolchain in `[dependencies]`, slim extras in a feature; **(b) no `[dependencies]`: features `toolchain`, `r-libs`, `slim`, each env lists them**; (c) one feature per package group | (b) matches the backlog source (feat-win-variants PLAN.md "toolchain and library features"); minimal = toolchain + r-libs, with no copy; minimal drops `no-default-feature` (the default feature now holds only R_VERSION and two CI tasks) | default, 2026-11-24 |
| E2 | pkg-config on Windows | **in slim's Windows target (as before)**; in toolchain everywhere | minimal's Windows envs never had it (conda-forge's brings libglib, minimal-deny.txt); keeps every env's specs identical | default, 2026-11-24 |
| E3 | Windows wheel layout | **the tree's Library/ contents under r_zig/R/ (R_HOME = r_zig/R/lib/R, as on unix)**; keep Library/ in the wheel | r_zig.r_home() and every `${R_HOME}/../..` path in Rcmd_environ keep their meaning; no change to the unix layout | default, 2026-11-24 |
| E4 | Windows platform tag | **from the R tree's PE machine field**; from the host | lets a CI artifact be wrapped on linux; the build tools are x86_64 MSYS2 programs on both arches, so only the R tree counts | default, 2026-11-24 |
| E5 | Windows wheel test language | **Python (scripts/wheel-test-windows.py)**; port wheel-test.sh to bash on Windows | the wheel env on Windows is python alone (no bash, no lock churn); same scenarios as wheel-test.sh, minus the unix-only ones (readelf/otool rpaths, CONDA_PREFIX decoy, Fortran stop) | default, 2026-11-24 |
| E6 | python for the Windows wheel steps | **add win-64/win-arm64 to [feature.wheel] (lock gains only the wheel env's two new platforms)**; actions/setup-python | one toolchain source (pixi); the lock diff is additions only (finding F3) | default, 2026-11-24 |
| E7 | build-tools wheel licence on Windows | **every license line of the group's SOURCES, joined with AND; dist-info licences = the group's LICENSES/ texts**; GNU make's alone | the Windows group is the whole MSYS2 userland plus pkgconf, not make | default, 2026-11-24 |
| E8 | L1 gate | **repository variable R_ZIG_RELEASE == 'true' AND workflow_dispatch AND ref main, on every job; PyPI a separate `pypi` input + `pypi` environment, OIDC only** | the task's gate; no names reserved, no tokens; D7 (conda only until the parity gate) still holds | default, 2026-11-24 |
| E9 | L1 input | **artifacts of one successful build-r run on main at the dispatch's sha (nothing rebuilt)**; rebuild in the release job | releases what CI verified (verify-package, wheel-test); the sha must match | default, 2026-11-24 |
| E10 | M-24 opt-in | **R's own R_PLATFORM_PKGTYPE=win.binary (env or Renviron.site), exercised by a dispatch-only workflow, win-binary.yaml**; -DPLATFORM_PKGTYPE in build.zig; options(pkgType) in Rprofile.site | no rebuild or R_HOME change; Rprofile's option alone is refused by install.packages (finding F9); default unchanged (finding F8) | default, 2026-11-24 |
| E11 | CI4 `--no-rtools-libs` | **new stress.yaml input `rtools_libs` (boolean, default true)** | a run could not be expressed before; 11 inputs are within GitHub's 25 (actionlint 1.7.12 enforces 25, finding F12) | default, 2026-11-24 |

## Findings

- **F1 V (L8).** Effective specs per env and platform, before and
  after: `pixi workspace export conda-environment -e <env> -p <plat>`
  for 8 envs x 6 platforms, normalized (sorted deps, channels,
  variables): 48 of 48 identical after the split. After E6 the only
  difference is `python >=3.9` in wheel's win-64 and win-arm64.
- **F2 V (L8).** `pixi lock --check` passed after the split with the
  lock byte-identical (`cmp` with the saved copy; sha256 prefix
  c7834c2e79e4b1fe before and after the split).
- **F3 V (L2 lock).** `pixi lock` after adding the Windows platforms to
  [feature.wheel]: package lists (name-version-build from every lock
  URL, per env and platform) differ only by 18 added entries in
  `wheel win-64` and 17 in `wheel win-arm64` (python 3.15.2, as the
  linux wheel env). No existing entry changed; zig-* and r-zig-* pins
  untouched. Lock sha256 prefix after: 48227fb455716269. `pixi lock
  --check` passes.
- **F4 V (L2).** make-wheel.py wraps both Windows CI trees (run
  45381914199 artifacts standalone-minimal-windows-latest/-11-arm and
  toolchain-Windows-X64/-ARM64) on linux: r_zig 55.6 MiB (win_amd64),
  40.7 MiB (win_arm64); r_zig_build_tools 10.8 MiB; compilers and
  toolchain wheels hold their .dist-info alone. All PE files of each R
  tree are one machine type.
- **F5 V (L2, no unix regression).** The linux-64 wheels from the old
  and the new make-wheel.py (same CI tree, SOURCE_DATE_EPOCH fixed) are
  byte-identical except r_zig/__init__.py (and so RECORD).
- **F6 V (L2).** R's Renviron reading drops backslashes: with ZIG_BIN
  set by the console script as `C:\...\zig.exe`, R saw
  `C:Usersadmin...zig.exe` (kappa) and rzig found no zig. r_zig now sets
  ZIG_BIN with forward slashes on Windows. A user's own ZIG_BIN with
  backslashes is mangled the same way by Renviron.site's
  `${ZIG_BIN-...}` (I: same mechanism, not run).
- **F7 V (L2).** zig needs LOCALAPPDATA for its global cache on Windows
  ("unable to resolve zig cache directory: AppDataDirUnavailable" with a
  reduced environment); the Windows test keeps one, as
  hermetic-check.sh does.
- **F8 V (M-24).** kappa, published r-zig-slim/r-zig-toolchain 4.6.2
  `_12` (universe), CRAN binaries jsonlite, data.table, Rcpp, quadprog
  plus fastmap from source, one session. With R_PLATFORM_PKGTYPE=
  win.binary: .Platform$pkgType "win.binary", getOption("pkgType")
  "both"; the four install as binaries (MD5 file), fastmap from source
  through rzig build; all load together, no warnings; data.table runs 2
  OpenMP threads (CRAN's static libgomp beside our libomp); quadprog and
  jsonlite work. **But** Rcpp code compiled at run time
  (cppFunction, zig/libc++) against CRAN's binary Rcpp (gcc/libstdc++):
  `f(2)` works, a thrown C++ exception ends R (child R exit 5, no
  message; in-process the session died with exit 1). With Rcpp built
  from source (the default "source"), the same exception is caught as
  an R error (baseline run, every package source, all OK). So binaries
  by default would break sourceCpp/cppFunction exceptions, and any
  source package whose C++ errors reach Rcpp's C callables. Keep
  "source" (decision 2026-11-14 stands).
- **F9 I (M-24).** options(pkgType = "both") in Rprofile.site is not an
  opt-in on its own: install.packages() checks .Platform$pkgType, which
  only R_PLATFORM_PKGTYPE or -DPLATFORM_PKGTYPE change (R's documented
  behaviour; not run here).
- **F10 V (CI11).** win-64 conda-package, run 45381914199 job
  138402832839: 0 "Overlinking" warnings name zstd.dll (37 warnings in
  all). R.dll's zstd.dll now resolves to the zstd package `(zstd)` in
  the linking report (log line 2553): zstd is a host requirement of the
  build since feat-standalone-toolchain E2 (bc2ad81, 2026-11-04;
  recipe/recipe.yaml:438-441, 523). Explained and gone.
- **F11 V (CI11, new).** The 37 warnings left are r-zig-recommended's:
  its DLLs' R.dll, Rblas.dll, Rlapack.dll and Rgraphapp.dll resolve to
  the hosted runner's CRAN R, `C:\Program Files\R\R-4.6.2\bin\x64` on
  PATH (36), and mgcv's libomp.dll to the pkg env (1). That output has
  no host env with r-zig-slim, so rattler-build searches PATH. A
  warning only; a follow-up for the recipe (not this topic's file).
- **F12 V (CI4).** actionlint 1.7.12 accepts 11 workflow_dispatch
  inputs and rejects 26 ("maximum number of inputs ... is 25"), so the
  new `rtools_libs` input is within the limit.
- **F13 V (CI9).** build.yaml's linux_runner input reaches every
  linux-64 job: toolchain, build (default and minimal), build-full
  (full, openblas) and conda-package use
  `inputs.linux_runner || 'ubuntu-latest'` (build.yaml:84, 128, 139,
  194, 197, 305); artifacts are named by runner.os/arch, so a
  ubuntu-26.04 leg downloads toolchain-Linux-X64. ubuntu-latest is
  already ubuntu-26.04 (run 45381914199, job 138402831909: "Image:
  ubuntu-26.04"), so the dispatch checks the explicit label only.
- **F14 V (wave).** Stress 45305358893 (d58dc2c, every OS, tree and
  conda, all rows, trace on) already covers most of CI1, CI4 and CI5.
  Non-ok rows: macos-15-intel arrow and arrow:source (install-failed,
  sysdep, expect ?); windows-11-arm protolite (fail-package), arrow
  (x64 libarrow, fail-package), rstan (smoke-failed, fail-package);
  windows-latest hdf5r (fail-package), gsl (fail-upstream), igraph
  (fail-sysdep), Rsamtools and scran (skipped, fail-dependency),
  protolite and arrow (fail-abi), rstan (smoke-failed, fail-package);
  each the same on tree and conda; every linux and macos-latest row ok,
  including RcppParallel:system-tbb, mlpack and lwgeom (CI5's rows).
  Rcpp's smoke log shows `rzig build: R CMD SHLIB, tier 1` on every leg
  (CI6's Rcpp half); rstan's smoke log shows no rzig line (its
  compileCode hides the output).
- **F15 V (L2 text).** rzig's group texts still say "pip: no wheels for
  Windows" (zigbuild/tools/rzig/groups.zig:138, 290 and its tests;
  recipe/test-preflight.R:112). The Windows test accepts that line or
  the future `pip install r-zig-build-tools` and prints a note.

## Tests run

| where | command | result |
|---|---|---|
| gamma | `pixi lock --check` (after split; after E6) | up to date both times; lock sha256 c7834c2e79e4b1fe, then 48227fb455716269 |
| gamma | export + compare, 48 env/platform pairs | identical (F1) |
| gamma | `pixi run --frozen -e minimal minimal-check` | all six platforms, none on the deny-list |
| gamma | make-wheel.py on the CI Windows trees (cross) | 4 + 4 wheels (F4) |
| gamma | old vs new make-wheel.py on the CI linux-64 tree | identical but r_zig/__init__.py (F5) |
| delta | `pixi run --frozen build`, `smoke` (default) | build 0, "Smoke test passed (linux/slim)" |
| delta | `pixi run --frozen -e minimal build`, `smoke` | build 0, "Smoke test passed (linux/minimal)" |
| delta | `pixi run --frozen -e wheel wheel-test` on the new linux-64 wheels | "wheel test passed" (all scenarios) |
| kappa | `pixi run -e wheel wheel-test` (scripts/wheel-test-windows.py) on the cross-built win_amd64 wheels | "wheel test passed" (run 7, with TLS: requests OK) |
| kappa | `pixi run -e wheel wheel` (native make-wheel.py) then `wheel-test` | wheels written, "wheel test passed" |
| kappa | win-binary.R with and without R_PLATFORM_PKGTYPE=win.binary | F8 |
| gamma | `pixi exec -s actionlint -s shellcheck actionlint .github/workflows/*.yaml` | clean |
| gamma | release.yaml's assemble shell steps on local copies of the artifacts | checksums OK, wheel set check OK |

Upstream zig: the Windows wheel test compiles with PyPI ziglang 0.17.1,
which is upstream zig; the linux wheel test on delta too. No conda-zig
compile path changed (L8 left every env's specs and the lock entries
as they were).

## Not verified

- The win_arm64 wheels on Windows on ARM (no host): the full-tier
  windows-11-arm minimal leg runs them (ziglang 0.17.1 has a win_arm64
  wheel on PyPI, V).
- The new CI steps themselves (no dispatch): the Windows wheel steps in
  build-r.yaml, release.yaml, win-binary.yaml, stress.yaml's
  rtools_libs.
- macOS wheels after the change (the unix path is byte-identical on
  linux, F5; the macOS tag code is unchanged).
- R_PLATFORM_PKGTYPE set to an empty string (win-binary.yaml's baseline
  leg) behaving as unset (A).

## Needs from other topics

0. **Blocking for L2 on Windows.** Owner of python/r_zig/__init__.py
   (the wheel's Python package; no topic owns it, so whoever merges the
   wave): without this the Windows console scripts stop with "this
   wheel's R build is unix-only", and build-r.yaml's Windows minimal
   legs fail at wheel-test. Tested on kappa with it applied (F6, Tests
   run):
   ```diff
   @@ def prefix() -> str:
   -    """The installation prefix: ``bin/R``, ``bin/Rscript``, ``lib/``."""
   +    """The installation prefix: ``bin/R``, ``bin/Rscript``, ``lib/``
   +    (Windows: ``bin/R.bat``, ``lib/R/bin/R.exe``)."""
   @@ def environ(base: dict[str, str] | None = None) -> dict[str, str]:
            if zig:
   -            env["ZIG_BIN"] = zig
   +            # forward slashes on Windows: R reads ZIG_BIN again through
   +            # R_HOME/etc/Renviron.site's ${ZIG_BIN-...}, which takes a
   +            # backslash as an escape and drops it
   +            env["ZIG_BIN"] = zig.replace("\\", "/") if os.name == "nt" else zig
   @@ def _exec(name: str, args: list[str]) -> None:
   -    if os.name == "nt":
   -        raise SystemExit("r-zig: this wheel's R build is unix-only")
   -    exe = os.path.join(prefix(), "bin", name)
        env = environ()
   -    # bin/R derives R_HOME from its own location and warns ("ignoring
   -    # environment value of R_HOME") whenever the environment disagrees —
   -    # e.g. a system R's R_HOME left in the shell. Let it derive.
   +    # R derives R_HOME from its own location and, on unix, warns
   +    # ("ignoring environment value of R_HOME") whenever the environment
   +    # disagrees, e.g. a system R's R_HOME left in the shell. Let it derive.
        del env["R_HOME"]
   +    if os.name == "nt":
   +        # Windows: R_HOME/bin's front ends (R.exe, Rscript.exe), which
   +        # start R_HOME/bin/x64's. No exec there: os.execve starts a new
   +        # process and returns to the console at once, so wait for it.
   +        import subprocess
   +
   +        exe = os.path.join(r_home(), "bin", name + ".exe")
   +        raise SystemExit(subprocess.call([exe, *args], env=env))
   +    exe = os.path.join(prefix(), "bin", name)
        os.execve(exe, [exe, *args], env)
   ```
   The full patch: scratch-b13-env-ci/r_zig-init.diff (git apply).
1. rzig owner (zigbuild/tools/rzig/groups.zig) and recipe owner
   (recipe/test-preflight.R): the Windows pip lines, now that Windows
   wheels exist. groups.zig:138:
   ```diff
   -    const pip = if (p.windows) "  pip:         no wheels for Windows\n" else switch (g) {
   -        .compilers => if (p.linux)
   +    const pip = switch (g) {
   +        .compilers => if (p.linux)
   ```
   (Windows then takes the macOS compilers line, `pip install
   r-zig-compilers (zig only: PyPI has no Fortran compiler)...`, the
   build-tools line and `pip install cmake`), the three `win` expected
   texts in groups.zig's tests (lines 243, 264, 278) and line 290's
   `if (this.windows) "no wheels for Windows" else` dropped;
   recipe/test-preflight.R:112: drop `if (windows) "  pip:         no
   wheels for Windows" else`, so Windows takes the non-linux line.
2. stress owner (stress/packages.tsv), for CI7: magick's smoke renders
   an SVG through the bundle's librsvg (CFG code on win-arm64):
   ```diff
   -magick	g3	...	magick::magick_config()$version	...
   +magick	g3	...	{i <- magick::image_read(charToRaw('<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="red"/></svg>')); magick::image_info(i)$width == 8}	...
   ```
3. stress owner, for CI6: rstan's smoke so its log shows the SHLIB
   line: `rstan::stan_model(model_code = ..., verbose = TRUE)` in the
   rstan row's smoke (stress/packages.tsv:74).
4. recipe owner (F11): r-zig-recommended's Windows linking check
   resolves R.dll from the runner's PATH. A candidate: give that output
   `r-zig-slim` (pin_subpackage exact) in host requirements so the check
   finds R.dll in the host prefix. Not tried.
5. Records owner (chore-release-12/BACKLOG.md): L8, L2 and L1 done
   here; M-24 closed as "keep source" (F8); CI9 and CI11 explained;
   new item from F11.

## CI dispatch list for the wave (run after this branch is merged)

Every command reads its result tables row by row (stress.R's report.md
per leg). Stress needs `ENABLE_HOSTED_JOBS=true`.

- **Full tier, incl. the Windows wheel legs (L2):**
  `gh workflow run build.yaml --ref main`
- **CI9:** `gh workflow run build.yaml --ref main -f linux_runner=ubuntu-26.04`
  (can be the same run as the full tier above).
- **CI1** (largely covered by 45305358893 on d58dc2c, F14; repeat on the
  wave's main):
  `gh workflow run stress.yaml --ref main -f oses='["windows-latest","windows-11-arm"]' -f packages=all -f distribution=both -f channel=local -f trace=true`
- **CI3:**
  `gh workflow run stress.yaml --ref main -f oses='["ubuntu-latest","ubuntu-24.04-arm","macos-latest","macos-15-intel"]' -f packages=all -f distribution=tree -f zig=upstream`
- **CI4** (with the Rtools45 tree: 45305358893's windows-11-arm legs, F14;
  without it, new input):
  `gh workflow run stress.yaml --ref main -f oses='["windows-11-arm"]' -f packages=all -f distribution=both -f rtools_libs=false -f trace=true`
  then diff its two report.md tables against 45305358893's
  stress-windows-11-arm-{tree,conda}.
- **CI5** (rows ok on linux in 45305358893, F14; the "full and openblas
  variants" cannot be expressed: the stress task runs the slim compile
  tree only):
  `gh workflow run stress.yaml --ref main -f oses='["ubuntu-latest","ubuntu-24.04-arm"]' -f packages='RcppParallel:system-tbb mlpack lwgeom' -f distribution=both`
- **CI6** (after need 3):
  `gh workflow run stress.yaml --ref main -f oses='["ubuntu-latest","macos-latest","windows-latest"]' -f packages=g1 -f trace=true`
- **CI7** (after need 2):
  `gh workflow run stress.yaml --ref main -f oses='["windows-11-arm"]' -f packages=magick -f distribution=both -f trace=true`
- **M-24 again on hosted Windows (optional):**
  `gh workflow run win-binary.yaml --ref main`
- **L1:** never in the wave. For a release: `gh variable set R_ZIG_RELEASE --body true`,
  `gh workflow run release.yaml --ref main -f run_id=<build-r run> -f tag=v4.6.2-<N>`,
  then `gh variable delete R_ZIG_RELEASE`.

## Review (2026-11-24)

What changed in review:

- R1. python/r_zig/__init__.py reverted to main (not an owned file);
  its diff moved to need 0, marked blocking for the Windows wheel legs.
  With it reverted the linux wheels are byte-identical to main's
  make-wheel.py output again (F5 had r_zig/__init__.py as the only
  difference).
- R2. release.yaml: the assemble job now fails unless the run has six
  artifacts of each kind (standalone-default, standalone-minimal,
  toolchain, r-zig-wheel). A push to main runs the core tier only and
  succeeds with linux-64's artifacts, which the old checks (sha256,
  one wheel of each name per tag) would have released as a partial
  release. The header said "or a pull request with `full-ci` merged";
  that run is on the PR branch and the merge push is core tier, so only
  a dispatch of build.yaml on main qualifies (build.yaml:7, 188-190).
- R3. pixi.toml: two comments reworded (pipeline feature, stress env);
  no spec change.

Checked and left as is: make-wheel.py's Windows path (Library/ as the
prefix, PE machine tag, rzig's 16 names + cfguard.o/clear_cache.o,
toolchain usr/ + etc/; the cross-built win_amd64 wheels' METADATA and
licence files inspected); wheel-test-windows.py; build-r.yaml (bash
shell on Windows; dist/toolchain comes from unpack-toolchain on every
leg); stress.yaml's rtools_libs (stress.R:69, 722 know
--no-rtools-libs); win-binary.yaml (experiment only, hosted-jobs
switch). Noted, not changed: the Windows build-tools wheel's
dist-info licences are the m2-* recipe-script licence texts conda-forge
ships (E7); the programs' own GPL texts are not among them (I:
conda-forge's m2-* ship no upstream licence file).

Tests re-run in review:

| where | command | result |
|---|---|---|
| gamma | `pixi exec -s actionlint -s shellcheck actionlint .github/workflows/*.yaml` | clean |
| gamma | `pixi lock --check` | up to date; lock sha256 prefix 48227fb455716269 (unchanged) |
| gamma | release.yaml's six-artifact check on a mock `dl/` (6 of each; then one wheel dir removed) | passes; then fails with "has 5 r-zig-wheel-* artifacts" |
| delta | `pixi lock --check`; `pixi run --frozen build`, `smoke` (default) | up to date; build 0, "Smoke test passed (linux/slim)" |
| delta | `pixi run --frozen -e minimal build`, `smoke`, `toolchain` | build 0, "Smoke test passed (linux/minimal)", toolchain 0 |
| delta | `pixi run --frozen -e wheel wheel`, `wheel-test` (linux-64, __init__.py as on main) | four wheels; "wheel test passed" |

Not re-run in review: the Windows wheel test on kappa (its result
needs need 0 applied; the implementer's kappa runs had it, F6).

## Suggested commit message

feat: Windows wheels, pixi deps split into features, a gated release workflow and the win.binary experiment
