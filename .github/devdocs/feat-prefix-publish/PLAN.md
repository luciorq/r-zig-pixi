# PLAN: publish r-zig-slim to a conda channel

## Goal

Make the conda packages already built and tested by `recipe/recipe.yaml`
(linux-64, osx-arm64, win-64 — see `feat-initial-setup`) installable by
`pixi add`/`conda install` from a real channel, not just artifacts sitting
in `dist/conda/` on whichever machine built them.

## End goal: CI trusted publishing (target state)

The channel gets updated automatically by CI, with no human manually
SSHing into a machine and running `rattler-build upload` by hand — that
manual loop is what every real release (build numbers 2 through 8) has
used so far, and it doesn't scale (see `TODO.md`'s per-build entries for
how much friction it's caused: quoting bugs across the SSH/PowerShell/bash
chain, stale-process-tracking issues, transient network errors needing
manual retries).

Two designs were considered for *how* CI actually runs the platform-
specific builds:

### Option A: OIDC trusted publishing on GitHub-hosted runners (originally sketched here, not chosen for now)

`rattler-build`'s `upload prefix` (and the newer unified `publish --to
<url>`) subcommands support OIDC **trusted publishing** — GitHub Actions
mints a short-lived, repo-and-workflow-scoped OIDC token (via the standard
`id-token: write` permission), rattler-build hands it to prefix.dev, and
prefix.dev verifies it against a trusted-publisher entry configured on the
channel itself before accepting the upload. No API key ever exists to leak
or rotate — the strongest security story of the two options. Needs:

1. The workflow has `permissions: id-token: write`.
2. The channel's *Trusted Publishers* settings on prefix.dev list this
   repo (owner/name) and the exact workflow filename allowed to publish.
3. rattler-build ≥0.31.1 (pinned to `>=0.70`, comfortably past this).

This runs cleanly on GitHub-*hosted* runners (`ubuntu-latest`/
`macos-latest`/`windows-latest`), same as the existing `build`/
`build-windows` jobs in `.github/workflows/build.yml`.

### Option B: self-hosted runners on gamma/omicron/kappa (chosen — see `CI_SELF_HOSTED_PLAN.md` in this same devdocs folder)

Instead of hosted runners + OIDC, install a persistent GitHub Actions
runner agent directly on the three machines already used for every manual
build/publish this whole project (gamma = linux-64, this same machine;
omicron = osx-arm64; kappa = win-64). Chosen over Option A for now because:

- **No new auth setup at all.** All three machines already have a live,
  interactive `rattler-build auth login prefix.dev` session (see "Interim
  strategy" below) — a self-hosted runner inherits that local credential
  automatically if it runs as the same user account. Option A requires
  configuring Trusted Publishers on the prefix.dev channel settings
  first, a one-time step not yet done.
- **Persistent build cache.** Self-hosted runners keep their checkout
  directory between runs (`build/zig-cache`, the fetched R tarball, the
  resolved pixi env all stay warm) — hosted runners start from a bare VM
  every single time, meaningfully slower for a build this size (10–25
  minutes even with a warm cache).
- These are the exact machines every Windows/macOS fix in this project
  has been verified against — known-good environments, not generic CI
  images.

Trade-off, explicitly acknowledged: Option A's "no persistent credential
anywhere" property is real security hardening that Option B gives up in
exchange for simplicity — worth revisiting later if that matters more than
it does today (a private repo, personal machines). Full implementation
plan (runner provisioning steps, exact `build.yml` changes, verification)
is in `CI_SELF_HOSTED_PLAN.md`, this same devdocs folder.

**Status: planned, not yet implemented** — deliberately postponed until
after the `worktree-feat-zig-build` branch merges back to `main` (a
cleaner base for CI changes than an in-progress feature branch).

We picked prefix.dev over anaconda.org specifically because anaconda.org
has no equivalent trusted-publishing support at the time of writing — it's
API-key-only, meaning a stored secret either way (relevant to Option A
specifically; Option B doesn't use either channel's trusted-publishing
feature).

## Interim strategy: publish by hand from an authenticated dev machine

Until the CI path above is built, publishing happens manually from one of
three dev machines — gamma (this machine, linux-64), omicron (macOS
arm64), kappa (Windows) — each already set up to build+test the recipe
locally (see `feat-initial-setup`).

- **Channel**: `universe` on prefix.dev, currently private.
- **Auth**: `rattler-build auth login prefix.dev` (interactive, stores a
  bearer token in `~/.rattler/credentials.json` — a real local credential,
  which is exactly what the CI end-goal above avoids). Confirmed already
  done on gamma (account `luciorq`). **Not yet done on omicron or kappa**
  — each machine needs its own `rattler-build auth login prefix.dev` run
  before it can publish (a human has to do this interactively/with their
  own token; not something to automate here).
- **Tooling**: `conda-publish` pixi task, defined once per platform under
  `[feature.pkg.target.<platform>.tasks]` (`linux-64`/`osx-64`/
  `osx-arm64`/`win-64`) — a plain `rattler-build upload prefix --channel
  universe --skip-existing dist/conda/<platform>/*.conda` one-liner each,
  matching `conda-package`'s own style (no wrapping shell script; the
  first version of this task did wrap one, which was unnecessary
  indirection for something `rattler-build upload` already does
  directly). Deliberately *not* chained onto `conda-package` via
  `depends-on` — publishing an already-built artifact shouldn't force a
  full R rebuild (10–25 minutes depending on platform). Workflow is two
  explicit steps: `pixi run -e pkg conda-package` then
  `pixi run -e pkg conda-publish`.
- `--skip-existing` makes re-running after a no-op rebuild safe (the same
  version+build-string just gets skipped, not rejected as an error).
- Scoping the glob to `dist/conda/<platform>/*.conda` per platform (rather
  than one task globbing `dist/conda/*/*.conda`) means it can never pick
  up another platform's artifact or anything sitting in rattler-build's
  own `dist/conda/broken/` (its convention for a package that failed its
  test phase) — since it's picked by pixi's own target resolution at
  `pixi run -e pkg conda-publish` time, not a runtime glob, there's no
  ambiguity to defend against in the first place.

## Why not `pixi publish`/`pixi upload`

Pixi has its own newer `pixi build`/`pixi publish` package-building
system that also supports trusted publishing to prefix.dev. Sticking with
`rattler-build` directly (orchestrated through the existing `pixi run -e
pkg` task pattern) instead of adopting pixi's system: `recipe/recipe.yaml`
+ `rattler-build build` is already fully proven on all three OSes with a
green CI job — switching build systems now would be a much larger,
unrelated restructuring for no functional gain on the publishing question
itself.
