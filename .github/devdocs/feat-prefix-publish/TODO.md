# TODO

## Interim: manual publish from dev machines

- [x] Channel created: `universe` on prefix.dev (private)
- [x] gamma (linux-64) authenticated (`rattler-build auth login prefix.dev`,
      account `luciorq`) — confirmed via `rattler-build auth status`
- [x] omicron (osx-arm64) authenticated (account `luciorq`, confirmed via
      `rattler-build auth status`)
- [x] kappa (win-64) authenticated (account `luciorq`, confirmed via
      `rattler-build auth status`)
- [x] `conda-publish` pixi task, one per platform under
      `[feature.pkg.target.<platform>.tasks]` — plain `rattler-build
      upload prefix --channel universe --skip-existing
      dist/conda/<platform>/*.conda` one-liners, no wrapper script
      (first draft used a `scripts/publish-conda.sh` + a new
      `conda_platform()` env.sh helper; removed both — unnecessary
      indirection for something `rattler-build upload` already does
      directly, and inconsistent with `conda-package`'s own plain-CLI
      style). Verified via `pixi run -e pkg --dry-run conda-publish` on
      linux-64 that it resolves to the right platform-scoped command.
- [x] First real publish from gamma (linux-64) — done by the user
      (`r-zig-slim-4.6.1-hb0f4dca_0.conda`)
- [x] First real publish from omicron (osx-arm64) — done 2026-07-23
      (`r-zig-slim-4.6.1-h60d57d3_0.conda`), confirmed via
      `rattler-build upload prefix -vv`: "Upload complete... Packages
      successfully uploaded to prefix.dev server"
- [x] First real publish from kappa (win-64) — done 2026-07-23
      (`r-zig-slim-4.6.1-h9490d1a_0.conda`), same confirmation. Note: the
      plain `conda-publish` pixi task exits 0 with almost no visible
      output over a non-interactive SSH session (rattler-build's "fancy"
      log style doesn't render well without a real TTY) — ran with
      `-vv` directly to get an explicit confirmation line when verifying
      remotely; the task itself is unchanged and fine to use normally.
- [x] **Windows post-install bug found and fixed (2026-07-24)**: after
      installing the published win-64 package into a fresh env, R landed
      inside the env's Python `Lib/` (NTFS case-folds our `lib/R` into the
      pre-existing capital `Lib`) and neither `R` nor `Rscript` was on
      PATH. Two fixes: `R_HOME_DIR="$PREFIX/Library/lib/R"` on Windows
      (env.sh) + `Library/bin/{R,Rscript}.bat` PATH shims (stage.sh).
      Neither this project's `dist/` runs nor rattler-build's own
      absolute-path test could catch it. build.number bumped 0→1 to
      republish over the broken win-64 build-0. Verified end-to-end: fresh
      pixi project + `pixi add r-zig-slim` from a local file:// channel,
      then bare `R --version` and `Rscript -e ...` both resolve (ahead of
      system R) and run, `R.home()` → `...\Library\lib\R`. Fixed win-64
      `_1` published to universe. linux-64/osx-arm64 left at `_0` (not
      broken there; user chose win-64-only for now).
- [x] Verified a real fresh-env install works on win-64 (see above). Still
      open for linux-64/osx-arm64: confirm `pixi add -c
      https://prefix.dev/universe r-zig-slim` from a machine that didn't
      build it (the unix packages were only tested via rattler-build's own
      isolated test env, which — unlike Windows — does exercise a real
      solved run env, but a true fresh consume is still worth doing).
- [x] **Automate the fresh-env PATH-shim check for Windows** — added a
      `Fresh-env consume test (Windows PATH shim)` step to the
      `conda-package` CI job's windows-latest leg
      (`.github/workflows/build.yml`): after `conda-package` builds,
      `pixi init`s a throwaway project pointed at the just-built
      `dist/conda` local channel (plus `conda-forge` for transitive
      deps), `pixi add r-zig-slim`, then `pixi run Rscript -e ...`
      invoking bare `Rscript` and asserting `R.home()` contains
      `Library` — the same shape of check done by hand on kappa, now
      gated on every CI run instead of only a manual one. Verified the
      `pixi init`/`pixi add`/`pixi run` mechanics locally against the
      existing linux-64 `dist/conda` build (bare-path channel, no
      `file://` prefix needed — pixi accepts a plain absolute path
      directly); the Windows-specific `pwd -W` path conversion and the
      actual shim regression can only be confirmed on a real CI run.

## 2026-07-28: republished with zig-built packages (build number 2)

All three platforms' previously-published packages (built via the old
autoconf/gnuwin32 pipeline, build number 0/1) superseded by zig-built ones,
following `feat-zig-build`'s Milestone 5 default-path swap
(`recipe/build.sh` now calls `zig-build.sh` + `stage.sh` instead of
`configure-r.sh`/`build-r.sh`/`install-r.sh`). `recipe.yaml`'s `build:
number` bumped `0` → `2` (a Windows-only build 1 had already been
released, so 2 is the first number unused on every platform) — needed
because publishing at the same version+build number as an already-published
package risks `--skip-existing` treating it as a no-op rather than a real
supersession.

Published, all confirmed via `rattler-build upload prefix -vv`'s explicit
"Packages successfully uploaded to prefix.dev server" line (the plain
`conda-publish` pixi task itself is often silent over a non-TTY session —
same caveat as the original 2026-07-23 publishes):

- linux-64: `r-zig-slim-4.6.1-hb0f4dca_2.conda`
- osx-arm64: `r-zig-slim-4.6.1-h60d57d3_2.conda`
- win-64: `r-zig-slim-4.6.1-h9490d1a_2.conda`

Getting there found and fixed four real bugs — none of them present on
linux/macOS, all Windows-specific, each root-caused via reading actual
generated output/source rather than guessed:

- **`recipe.yaml`'s `source:` list never actually included `build.zig`/
  `zigbuild/`**, even after `recipe/build.sh` started depending on them.
  A **local** `rattler-build build` "succeeded" anyway — `zig build`
  walks UP parent directories looking for `build.zig` when it's missing
  from the sandbox's own work dir, and this repo's own `dist/conda/bld/
  .../work/` happens to sit inside the real checkout, so it silently
  found the REAL project's `build.zig` several levels up instead of a
  sandboxed copy. Confirmed by inspecting the actual kept work directory
  (`rattler-build build --keep-build`) — genuinely no `build.zig`/
  `zigbuild/` in it — then proved the fix by rebuilding with
  `--output-dir` pointed **outside** the project tree entirely (where the
  upward-walk trick can't possibly succeed) and confirming it still
  builds once the explicit `path: ../build.zig` / `path: ../zigbuild`
  source entries were added. This accidental-success mode would not have
  survived e.g. a standalone feedstock-style recipe repo, or (very
  plausibly) real CI depending on exactly how deep the runner's checkout
  path is relative to `CONDA_BLD_PATH`.
- **`dlltool` (building `libgcc_s_seh-1.dll`'s import lib, part of R.dll's
  link — the same "gthr_win32_lib" gotcha from `feat-zig-build`'s own F6.1
  catalog) fails with "failed to open temporary head file" once the
  rattler-build sandbox's own path gets long enough** — `dlltool` mangles
  the *entire absolute output path* into a single temp filename (replacing
  `\`, `:`, `.` with `_`), and the sandbox's own deep nesting
  (`dist/conda/bld/rattler-build_<pkg>_<timestamp>/work/build/zig-cache/
  local/o/<32-char-hash>/...`) pushed the mangled name past what Windows
  can handle. Fixed for this session's publish by using a short absolute
  `--output-dir` (`C:\rb`) plus `--no-build-id` (drops the timestamp
  component) — not (yet) made the pixi.toml `conda-package` task's
  default, since the "safe" length depends on wherever the repo happens
  to be checked out; worth revisiting if this bites CI too.
- **`ctx.prefix` (`b.install_prefix` in `build.zig`) was never normalized
  to forward slashes**, unlike `src_abs`, which already had this exact
  fix from `feat-zig-build`'s F6.2 (Windows-native backslash paths
  breaking R code string literals). Never hit before by coincidence — the
  short-`--output-dir` fix above produced a host-env directory literally
  named `h_env`, and `\h` is not a valid R escape sequence at all
  (`'\h' is an unrecognized escape...`), which is what actually surfaced
  it. For *other* letters that happen to form a **valid** (but wrong) R
  escape (`\n`, `\t`, `\r`, ...) this could have been silently corrupting
  paths instead of erroring, undetected. Fixed in `build.zig` by
  normalizing `b.install_prefix` once, right where `ctx.prefix`/
  `ctx.rhome` are derived from it — same treatment `src_abs` already gets.
  Re-verified zero regression on linux (full `pixi run build` rebuild).
- **`recipe.yaml`'s Windows test script silently corrupted its own R code
  at run time**: `Rscript -e 'set.seed(1); m <- matrix(...); ... %*% ...'`
  looked byte-for-byte correct in the *generated* `conda_build.bat`
  (verified by reading the actual file from a kept failed test work
  directory) — the corruption happened purely from **cmd.exe's own
  parsing of that line**, which has no concept of single quotes as a
  quoting mechanism at all (they're literal characters to cmd.exe): `%*%`
  triggered percent-variable-expansion (`%X%` for an undefined `X` just
  vanishes) and `<-` triggered input-redirection parsing, both silently
  eating characters before `Rscript` ever saw them — reproduced
  independently of any SSH/PowerShell invocation-chain quoting by
  re-running via an uploaded plain script file. Fixed by moving the
  Windows test off inline `-e` entirely: a real `recipe/test-win.R` file,
  staged into the test work directory via rattler-build's `tests: -
  script: {content: ..., files: {recipe: [test-win.R]}}` form, then
  invoked as a bare `Rscript test-win.R` — no cmd.exe metacharacters on
  the command line at all. Validated the YAML/schema cheaply via
  `rattler-build build --render-only` before committing to a full
  rebuild.

## 2026-07-28 (same day, continued): Windows-only follow-up (build number 3)

Real user bug report: `install.packages("pak", ...)` failed with `Rcmd.exe`
not found — F7's own package-compilation-contract work only ever built
`R.exe`, not the separate `Rcmd.exe` many packages call directly for `R
CMD config`-style compiler discovery. Fixed on the `build.zig` side (see
`feat-zig-build/TODO.md`'s F7.1 entry for the full detail: a shared
`winCmdFrontend` helper builds both `R.exe`/`Rcmd.exe`; two more real
installed-file-location bugs found and fixed alongside it —
`bin/config.sh` needed installing directly under `RHome/bin/`, not
`RHome/bin/x64/`, and a completely missing `etc/Rcmd_environ`, a real
static gnuwin32 file that sets `R_OSTYPE=windows`). `recipe.yaml`'s `build:
number` bumped `2` → `3` (Windows-only bump — linux-64/osx-arm64 stay at
build 2, since this fix is Windows-specific and there's no requirement
build numbers stay in lockstep across platforms).

Published: `r-zig-slim-4.6.1-h9490d1a_3.conda` (win-64 only), confirmed via
`rattler-build upload prefix -vv`'s "Packages successfully uploaded to
prefix.dev server" line — same verification standard as every other
publish in this doc.

**Still open, not fixed by this release** (see F7.1 in `feat-zig-build/
TODO.md` for the full detail): a real access-violation crash surfaces when
a package's own `configure` script recursively re-invokes `R.exe` (`pak`'s
does, calling `dynamic-help.R` via a fresh `R.exe` → `Rterm.exe` chain,
5 process levels deep). Root cause not isolated yet — needs a real
interactive Windows console to debug properly, not available over the
non-interactive SSH sessions used for everything else in this project so
far.

## 2026-07-28 (same day, continued again): Windows-only follow-up (build number 4)

Real user bug report: `install.packages()` for packages with compiled C
code (`glue`, `cli` — unlike `pak`, which has none) failed at their own
`system(paste(cc, "--version"), ...)` compiler probe, "had status 1". Root
cause was much broader than `--version` itself — see `feat-zig-build/
TODO.md`'s F7.2 entry for the full detail: the `gcc.exe`/`g++.exe` native
forwarder stubs had `BASH_PATH`/`SCRIPT_PATH` baked in at **compile time**
from the rattler-build sandbox's own paths (confirmed via `strings` on the
shipped binary — both pointed at `C:/rb/bld/rattler-build_r-zig-slim/...`,
which doesn't exist post-install), so *every* invocation on a real
installed package was silently broken, not just `--version`. Compounding
it, `m2-bash` was `build:`-only in `recipe.yaml`, so `bash.exe` wasn't even
guaranteed present in an installed env. Fixed: `win-exec-forward.c` now
resolves both paths at runtime (script co-located via `GetModuleFileName`,
bash via the runtime `CONDA_PREFIX` env var); `m2-bash` added to `run:`.

Verified in three stages on kappa before publishing: real `pixi run`
activation against a bare build tree, a fresh `rattler-build build`, and —
critically, matching the user's actual failure mode — installing that
fresh artifact into a brand-new throwaway pixi env (not the build sandbox,
not the dev env) and confirming `gcc.exe --version`/`g++.exe --version`
both exit 0 with real `clang version 21.1.8` output there.

Published: `r-zig-slim-4.6.1-h9490d1a_4.conda` (win-64 only), confirmed via
`rattler-build upload prefix -vv`'s "Packages successfully uploaded to
prefix.dev server" line.

## 2026-07-29: all 3 platforms (build number 5)

Requested directly (not a bug): differentiate the default per-user R
package library from any other R install on the machine. Went through
three design rounds on direct feedback before landing on the shipped one —
see `feat-zig-build/TODO.md`'s F7.3 entry for the full history. Final
design: unix (Linux and macOS alike) follows the XDG base directory spec
(`$XDG_DATA_HOME` if set, else `~/.local/share`) instead of R core's own
per-OS defaults, landing on `R/<platform>-zig/<x.y>` under that —
`~/.local/share/R/linux-64-zig/4.6`, `~/.local/share/R/osx-arm64-zig/4.6`.
Windows has no XDG equivalent; `LOCALAPPDATA` (already what R core uses,
for the same non-roaming/machine-local reason) is unchanged:
`%LOCALAPPDATA%/R/win-64-zig/4.6`. Implemented as an `R_LIBS_USER_default()`
source patch (`library.R`, same "compiled into base.rdb" constraint as the
existing `Sys.which()` patch), applied idempotently in both
`scripts/zig-build.sh` and `scripts/configure-r.sh`.

Verified for real on all three platforms before publishing (not just read
through): `Rscript -e 'Sys.getenv("R_LIBS_USER")'` against a fresh
`pixi run build` on each of linux (local), kappa (Windows), and omicron
(macOS), including confirming `$XDG_DATA_HOME` overrides are actually
respected on Linux/macOS.

Building the macOS package for this release found a second, unrelated real
bug along the way (F7.4 in `feat-zig-build/TODO.md`): `linkFortranRt`'s
macOS branch took gfortran's runtime link path from a vendored `subst.txt`
value hardcoding gcc 15.2.0 — a fresh `rattler-build` sandbox solve (no
lockfile, unlike the dev pixi env) resolved conda-forge's current
`gcc_impl_osx-arm64` (16.1.0) instead, and the stale path broke the build
(`unable to find dynamic system library 'emutls_w'`). Fixed by generalizing
`findGfortranLibDir` (previously Windows-only) to scan for the actually-
installed gcc version on macOS too, the same pattern Windows already used
for exactly this reason. Re-verified: the macOS package built clean against
16.1.0 afterward.

Published, all confirmed via `rattler-build upload prefix -vv`'s "Packages
successfully uploaded to prefix.dev server" line (one transient network
error on the Windows upload — "error sending request for url" — cleared on
a plain retry, no code involved):

- linux-64: `r-zig-slim-4.6.1-hb0f4dca_5.conda`
- osx-arm64: `r-zig-slim-4.6.1-h60d57d3_5.conda`
- win-64: `r-zig-slim-4.6.1-h9490d1a_5.conda`

## 2026-07-29 (continued, into 2026-07-30): Windows-only follow-up (build number 7)

Root-caused and fixed a real, previously-unconfirmed bug: a deterministic
access violation (`0xC0000005` in `R.dll`) hit every recursive front-end
invocation on Windows — `R CMD INSTALL` → `Rterm.exe` → a package's own
`configure` script → `R.exe` → another `Rterm.exe`, a real, not-uncommon
pattern (e.g. `pak`'s own `configure` re-invokes R directly). Confirmed
with 5 separate reproductions correlated precisely against Windows' own
crash log (`Get-WinEvent`), then root-caused via a bisection by Zig
optimize level rather than guessing from unsymbolized disassembly further:
`.Debug` and `.ReleaseSafe` both make the crash vanish entirely (pak's
build gets all the way past the recursive invocation and fails later on a
real, unrelated `mbedtls`/Windows-platform-detection compile error in its
own bundled `zip` library, identically under both) while `.ReleaseFast`
(the shipped default) crashes every single time on identical source — a
Zig/MinGW codegen issue specific to that optimize level on the
`windows-gnu` target (likely TLS-access lowering), not a plain logic bug
in R's own C code. See `feat-zig-build/TODO.md`'s F7.6 entry for the full
diagnostic detail (WER `LocalDumps` setup, WinDbg/`cdbX64.exe`
installation, `x86_64-w64-mingw32-objdump` disassembly at the crash
offset, etc.).

Fix: `build.zig`'s `newCMod` now builds Windows with `.ReleaseSafe`
instead of `.ReleaseFast` (Linux/macOS unchanged — this was never
observed there). Verified against the actual shipped conditionally-scoped
code (not just an ad-hoc throwaway build): `pixi run smoke` and `pixi run
contract` both pass on Windows with zero regression, and a real
`install.packages("pak")` reproduction against the final build no longer
crashes.

Published, confirmed via `rattler-build upload prefix -vv`'s "Packages
successfully uploaded to prefix.dev server" line (first attempt, no
retry needed this time):

- win-64: `r-zig-slim-4.6.1-h9490d1a_7.conda`

(linux-64/osx-arm64 stay at build 5 — `build.zig`'s change is Windows-only
in effect, `ctx.os != .windows` still resolves to unchanged `.ReleaseFast`,
so there's nothing new to rebuild/republish on those platforms.)

## 2026-07-30: win-64 + osx-arm64 follow-up (build number 8)

Two more real bugs found and fixed while adding `pak` to `contract-test.sh`
(requested directly): F7.7 (Windows) — `win-exec-forward.c`'s `_spawnv`-
based command-line construction silently stripped embedded double-quote
characters from `-D` flag values, breaking any package quoting a string
literal that way (not just `pak`'s `mbedtls` config); fixed by building the
command line manually with the Microsoft-documented argv-quoting algorithm
and calling `CreateProcessA` directly. F7.8 (macOS) — `OBJC` was never
routed through the `zig-cc` toolchain shim (only `OBJCXX` was, by an
autoconf fallback accident), so any package with real Objective-C source
silently compiled as plain C; fixed in both the vendored `subst.txt` and
`configure-r.sh`'s own `./configure` invocation. Full detail in
`feat-zig-build/TODO.md`'s F7.7/F7.8 entries.

Verified via the real `contract-test.sh` path (with `pak` now included)
passing on all 3 platforms before publishing, not just ad-hoc reproductions.

Published, confirmed via `rattler-build upload prefix -vv`'s "Packages
successfully uploaded to prefix.dev server" line (one transient network
error on the Windows upload, cleared on a plain retry — same class of
blip seen on earlier releases):

- win-64: `r-zig-slim-4.6.1-h9490d1a_8.conda`
- osx-arm64: `r-zig-slim-4.6.1-h60d57d3_8.conda`

(linux-64 stays at build 5 — neither fix touches Linux.)

## End goal: CI trusted publishing

**Status update (2026-08-06): this checklist predates the Option A vs.
Option B decision recorded above** ("Two designs were considered..."),
and 3 of its original 5 items assumed Option A (OIDC Trusted Publishers)
was the path taken — it wasn't. Corrected below, matching what was
actually built (`CI_SELF_HOSTED_PLAN.md`, `.github/workflows/build.yaml`'s
`conda-package` job):

- [x] ~~Configure Trusted Publishers on the `universe` channel~~ — N/A,
      Option B (self-hosted runners + local `rattler-build auth login`
      credentials) was chosen instead of Option A (OIDC). No Trusted
      Publishers config needed.
- [x] ~~Add an upload step to the `conda-package` CI job, gated to push
      on main, with `permissions: id-token: write`~~ — done, but not via
      `id-token: write` (that's Option A's OIDC permission, unused here).
      The `Publish to prefix.dev` step in `.github/workflows/build.yaml`'s
      `conda-package` job already exists, gated to
      `github.ref == 'refs/heads/main' && (push || workflow_dispatch)`,
      authenticating via each self-hosted runner's own already-logged-in
      `rattler-build` session.
- [x] ~~Once CI publishing is green and trusted, retire the interim
      dev-machine `rattler-build auth login` credentials~~ — N/A under
      Option B: those credentials aren't "interim," they're the
      permanent auth mechanism the self-hosted runners themselves use
      (the runner service inherits the same local session — see
      `CI_SELF_HOSTED_PLAN.md`). Nothing to retire; revoking them would
      break publishing, not clean it up.
- [x] **Version-bump / build-number strategy — decided 2026-08-06: stays
      fully manual.** A human bumps `recipe.yaml`'s `number:` as a
      deliberate part of any PR that should trigger a republish (exactly
      how all 9 build numbers to date have been produced — this just
      writes the existing practice down as the going-forward policy,
      not a change). `--skip-existing` is the safety net for CI runs
      that don't include a bump: same version+build string already on
      the channel, silently skipped, not an error. Considered and
      rejected: auto-incrementing the build number in CI (e.g. querying
      the channel for the current max, or a run-counter) — real added
      complexity (querying channel state or maintaining counter state)
      for a project that publishes maybe once every few days, and
      against this project's established discipline of deliberate,
      human-reviewed changes over inferred/computed ones.
- [x] **Channel visibility — decided 2026-08-06: go public**, but only
      after a cleanup pass first (see `CHANNEL_CLEANUP.md`, this same
      devdocs folder) — remove existing broken/superseded releases and
      republish a single clean release at build number 1 before flipping
      the channel to public, so first-time consumers don't land on a
      messy build-number history from the zig-build migration period.
