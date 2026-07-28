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
- [ ] Verify an install actually works: `pixi add -c https://prefix.dev/universe
      r-zig-slim` (or equivalent) from a machine that isn't one of the
      three that built it

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

## End goal: CI trusted publishing

- [ ] Decide a version-bump / build-number strategy (`recipe.yaml`'s
      version and build number are both static today — repeat CI runs
      against an unchanged R version would need this settled before
      `--skip-existing`-based idempotency is meaningful)
- [ ] Configure *Trusted Publishers* on the `universe` channel (prefix.dev
      channel settings): this repo's owner/name + the exact CI workflow
      filename that will be allowed to publish
- [ ] Add an upload step to the existing `conda-package` CI job (see
      `feat-initial-setup`'s `.github/workflows/build.yml`), gated to
      `push` on `main` only (not `pull_request`), with
      `permissions: id-token: write`
- [ ] Decide whether `universe` stays private or goes public before wiring
      real automated publishes to it
- [ ] Once CI publishing is green and trusted, retire the interim
      dev-machine `rattler-build auth login` credentials (revoke via
      prefix.dev account settings) — no reason to keep long-lived tokens
      around once nothing needs them
