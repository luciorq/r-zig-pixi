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
