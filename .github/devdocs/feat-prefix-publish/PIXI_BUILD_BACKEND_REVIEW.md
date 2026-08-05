# Review: migrating `conda-package` from a plain `rattler-build` task to pixi's `pixi-build` backend system (2026-08-05)

**Bottom line: don't migrate now. Revisit in 6–12 months, once `pixi-build`
drops out of `[workspace.preview]`.** Full reasoning and sources below.

## Context

Today `pixi.toml`'s `[feature.pkg]` `conda-package` task just shells out to
`rattler-build` directly:

```
rattler-build build --recipe recipe/recipe.yaml --output-dir dist/conda --no-build-id
```

`rattler-build` is an ordinary CLI dependency in the `pkg` environment; this
isn't using pixi's newer `[package]`/`[build-system]` "workspace as its own
buildable package" feature at all. The question this review answers: should
it be?

## 1. What pixi-build is today (pixi v0.76.1, 2026-08-04)

Still an explicit **preview feature** — `pixi.toml` needs
`[workspace] preview = ["pixi-build"]` to use it at all. From the current
docs (`pixi.prefix.dev/latest/build/getting_started/`): *"pixi-build is a
preview feature, and will change until it is stabilized... users must opt
in... because the developers reserve the option to make breaking changes."*
The prefix.dev blog post "Introducing Pixi Build" (2026-07-02, ~1 month
before this review) repeats the same framing while noting adoption is
growing.

Manifest shape adds two sections:

```toml
[package]
name = "r-zig-slim"
version = "4.6.1"

[package.build]
backend = { name = "pixi-build-rattler-build", version = "*" }
channels = ["https://prefix.dev/conda-forge"]
```

**`pixi build` was deprecated and folded into `pixi publish` in v0.68.0**
(2026-05-07, confirmed via the GitHub release notes directly): *"The `pixi
build` command has been deprecated — use `pixi publish` for equivalent
behaviour."* `pixi publish` now builds and optionally uploads. Relevant
flags (current CLI reference): `--target-channel`/`--to`, `--target-dir`,
`--build-dir`/`-b`, `--clean`/`-c`, `--build-string-prefix`,
`--build-number`, `--variant`, `--force`, `--no-skip-existing`,
`--dry-run`. **No `--output-dir` or `--no-build-id` equivalent anywhere in
this list** — see §3, this is the crux of the recommendation below.

Backends: `pixi-build-cmake`, `pixi-build-python`, `pixi-build-rattler-build`,
`pixi-build-ros`, `pixi-build-r` (installs individual R *packages*, not
relevant — this project builds R itself), `pixi-build-rust`,
`pixi-build-mojo`. Only `pixi-build-rattler-build` consumes a real
`recipe.yaml` directly; the others synthesize one from manifest metadata.

**Structural note**: `prefix-dev/pixi-build-backends` was archived
2026-01-20 — not abandonment, the code moved into the main
`prefix-dev/pixi` monorepo as first-class crates, now versioned/released in
lockstep with pixi itself. Bug reports for backends now go to
`prefix-dev/pixi` (label `area:build`).

## 2. `pixi-build-rattler-build` specifically

**Recipe reuse: yes, as-is, no restructuring.** Per the backend docs page:
*"Uses existing recipe.yaml files as build manifests"*, *"Supports all
standard rattler-build recipe features and selectors."* Discovery order
(explicit path → `recipe.yaml` next to manifest → `recipe/recipe.yaml`
subdirectory) matches this project's existing `recipe/recipe.yaml` layout
exactly. `recipe/build.sh`, the unix/win `requirements:` branching, the
`m2-*` Windows deps, and the vendored `source: - path: ../scripts` /
`../toolchain` / `../build.zig` / `../zigbuild` entries all continue to be
interpreted unchanged, because this backend is a thin wrapper that still
hands off to rattler-build's own recipe engine.

Real (but non-blocking) constraints: binary deps must stay in
`recipe.yaml`, not `pixi.toml` (already true here); `[package.run-exports]`
can't be set via the pixi manifest with this backend (already recipe-side
here); **incremental builds require the build directory to live outside
the workspace root**, a different operating model from today's single
`dist/conda/` tree.

**Maturity signals from live issue-tracker queries (not training
knowledge)**, `prefix-dev/pixi`, queried 2026-08-05: `area:build` currently
has 59 open issues. Specific to this backend: #5782 (package version not
exposed to recipe, open since 2026-04-24), #5364 (custom recipe path
support — only landed 2026-03-05), #5347 (frequent spurious rebuilds, open,
updated 2026-07-28), #6670 (compiler variant selection broken, open,
2026-07-25), #6727 (lock file "out of date" false positive, updated
2026-08-03 — 2 days before this review). `[package.run-exports]` support
itself only shipped in **v0.76.0 (2026-08-03)**, two days before this
review — the manifest surface is still moving weekly.

## 3. Feature parity / risk assessment for r-zig-pixi specifically — the real crux

**Output/work-directory control.** `--no-build-id` exists purely to drop
the `_<timestamp>` suffix from rattler-build's own
`bld/rattler-build_<pkg>_<id>/work/` directory name — a load-bearing fix
(see `CI_SELF_HOSTED_PLAN.md`) for a `dlltool`-vs-260-char-`MAX_PATH` bug
on the Windows self-hosted runner, combined with a short `--work C:\w`
runner directory. **No equivalent flag was found anywhere in the `pixi
publish` CLI reference or the backend docs.** pixi-build's own default
work/cache directories (`.pixi/build/pkgs/`, backend envs under
`.pixi/build/backends-v0/<hash>/`, build *work* dirs reportedly under
`~/.cache/rattler/build-work/` by default) look at least as deep as, and
stacked with additional hash/package-name segments on top of, the path
that already needed a workaround — and on Windows `~/.cache/...` sits under
the service account's user profile, the exact kind of path this project
already had to work around once (both for MAX_PATH and separately for
`NETWORK SERVICE` profile-directory ACL issues, see Phase 1 of
`CI_SELF_HOSTED_PLAN.md`). The rattler-build backend docs explicitly state
the incremental-build directory *must* live outside the workspace root,
reinforcing that this is a different, not-yet-documented-for-Windows
directory model. No GitHub issue or doc page addresses this for Windows
specifically — an absence of evidence, not a confirmed non-issue, but not
reassuring either.

**Source vendoring, per-platform requirements, custom build.sh**: unaffected
— all handled by the underlying rattler-build engine exactly as today,
since this backend treats `recipe.yaml`/`build.sh` as opaque standard
content.

**Windows support in general**: backend docs claim cross-platform support,
but sibling-backend issues (#364 missing Windows executable for
`pixi-build-ros`; #358 generated scripts break when workspace path contains
spaces, python/cmake backends) suggest Windows path-handling is still
shaking out bugs across the backend family — not a system that's been
hardened against the exact edge cases (long paths, symlink privileges,
`core.longpaths`) this project's Windows CI leg already needed fixing once.

**CI model**: no pixi-hosted build farm exists — prefix.dev's hosted piece
is a package *channel* with trusted publishing, not a build executor.
`pixi publish` runs on whatever CI you already have, so migrating wouldn't
change the self-hosted-runner architecture either way — but it also
provides no CI-side benefit to offset the risk in §3.

## 4. Recommendation

**Stay on the current plain-task `rattler-build build --recipe` approach.**
Revisit once `pixi-build` drops the `preview` flag.

1. Confirmed-current primary sources (docs/changelog dated within the last
   month, one release literally 2 days before this review) show the
   feature is still explicitly unstable, with maintainers reserving
   breaking-change rights.
2. The one concrete thing this project needs — precise control over build
   work-directory depth to dodge Windows `MAX_PATH` — has no documented
   equivalent in `pixi publish`/`pixi-build-rattler-build`. Given that this
   exact bug class already cost real debugging effort once, migrating onto
   an unverified, differently-shaped, possibly-deeper directory layout with
   no visible short-path flag is a disproportionate risk for the payoff.
3. The payoff itself is thin here: pixi-build's main value (generating
   recipes from manifest metadata, tighter path-dependency integration)
   mostly helps projects that don't already have a hand-written recipe.
   This project does, and the backend explicitly defers to it. Migrating
   would mostly just add a preview-flagged indirection layer for a CLI
   ergonomics change (`pixi run -e pkg conda-package` → `pixi publish`).
4. Issue velocity (59 open `area:build` issues, several about rebuild
   caching/variant-resolution correctness) confirms active, healthy,
   *unsettled* development — exactly the profile of something not yet safe
   to anchor a hard-won CI configuration on.

**If revisiting later**: the manifest edit itself would be small — add
`workspace.preview = ["pixi-build"]` + `[package]` + `[package.build]` to
`pixi.toml`; leave `recipe/recipe.yaml`/`build.sh` untouched; replace the
`conda-package` task's `rattler-build build ...` invocation with `pixi
publish --target-dir dist/conda [--build-dir <short-path>]`. The real cost
isn't the edit — it's re-running the full Windows self-hosted-runner leg
from scratch, specifically hunting for `MAX_PATH` regressions, before
trusting it in CI again.

## Sources (fetched/queried live during this review, 2026-08-05)

- https://pixi.prefix.dev/latest/build/getting_started/
- https://pixi.prefix.dev/latest/build/backends/
- https://pixi.prefix.dev/latest/build/backends/pixi-build-rattler-build/
- https://pixi.prefix.dev/latest/build/advanced_cpp/
- https://pixi.prefix.dev/latest/reference/cli/pixi/publish/
- https://pixi.prefix.dev/latest/integration/ci/github_actions/
- https://prefix.dev/blog/pixi-build (published 2026-07-02)
- https://github.com/prefix-dev/pixi/releases/tag/v0.68.0
- https://github.com/prefix-dev/pixi/releases/tag/v0.76.0
- https://github.com/prefix-dev/pixi (repo metadata; current release
  v0.76.1 / 2026-08-04)
- https://github.com/prefix-dev/pixi-build-backends (repo metadata:
  `archived: true`, `pushed_at: 2026-01-20`)
- Live issue search against `prefix-dev/pixi` (`area:build`,
  `pixi-build-rattler-build` labels), queried 2026-08-05
- This project's own `pixi.toml` and `recipe/recipe.yaml`/`recipe/build.sh`
