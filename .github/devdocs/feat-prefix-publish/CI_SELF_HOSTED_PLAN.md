# Plan: self-hosted CI for the conda-package build + publish pipeline (2026-07-30)

**Status: planned, approved, not yet implemented.** Deliberately postponed
until after the `worktree-feat-zig-build` branch merges back to `main` —
a cleaner base for CI changes than an in-progress feature branch, and it
lets the newly-added `pixi run contract` (`pak`) checks and the F7.6/F7.7/
F7.8 fixes land on `main` before anything about the release pipeline
itself changes.

## Context

Every conda-package release so far (build numbers 2 through 8) has been
produced the same fully manual way: SSH into kappa/omicron (gamma is the
same machine this whole project's Linux work runs on directly — confirmed
via `hostname`), scp changed files over one by one, run `rattler-build
build`, then `rattler-build upload prefix`. This has repeatedly hit real
friction: quoting bugs across the SSH → PowerShell → bash chain (see
`feat-zig-build/TODO.md`'s F7.7 for one concrete example that cost real
debugging time), stale-process-tracking issues (a background SSH wrapper
reporting "completed" while the actual spawned R/gcc process tree was
still running), and transient `prefix.dev` network errors needing manual
retries.

`.github/workflows/build.yml` already has a full build+test matrix
(`build`, `build-windows`, `build-legacy`, `build-windows-legacy`) on
GitHub-**hosted** runners, triggered automatically on push/PR — that part
already works and isn't the pain point. The gap is narrow: the
`conda-package` job builds and tests the conda package on hosted runners
but **never publishes it**. This plan closes that gap.

See `PLAN.md` (this same folder) for the comparison against Option A
(OIDC trusted publishing on hosted runners) — this doc covers only the
chosen approach (Option B: self-hosted runners) in implementation detail.

**Woodpecker CI was considered and rejected** (asked directly, mid-
planning): this repo already lives on GitHub with a working `build.yml` —
self-hosted GitHub runners reuse it (a `runs-on` swap + one new step)
instead of a rewrite in a different YAML dialect. Woodpecker also needs
its own server + database to stand up and maintain, where GitHub Actions
self-hosted runners need none (GitHub itself is the coordinator).
Woodpecker's main strength is Docker-native pipelines, which doesn't help
2 of the 3 platforms here — macOS and native Windows builds aren't
meaningfully containerizable — so its flagship benefit wouldn't even
apply.

## Phase 1 — provision runners on gamma, omicron, kappa

Needs a GitHub Actions runner registration token per machine (repo-admin
access required to generate one — `gh api
repos/<owner>/<repo>/actions/runners/registration-token`, or manually via
the repo's Settings → Actions → Runners → "New self-hosted runner" page;
tokens expire in ~1 hour so generate right before each machine's setup
step, not all three in advance).

On each machine:
1. Download the matching `actions-runner` release archive (linux-x64 for
   gamma, osx-arm64 for omicron, win-x64 for kappa) into a dedicated
   directory (e.g. `~/actions-runner`), extract it.
2. `./config.sh --url https://github.com/<owner>/<repo> --token <token> --labels self-hosted,<os>,<machine-name>`
   (`config.cmd` on kappa) — e.g. `linux,gamma` / `macos,omicron` /
   `windows,kappa`, so workflows can target an exact machine or just an OS.
3. Install as a persistent background service so it survives
   reboot/disconnect without needing to be manually started:
   `sudo ./svc.sh install && sudo ./svc.sh start` (gamma/omicron), the
   Windows service-install equivalent (kappa) — run under the same user
   account already used for all this project's pixi/rattler-build work,
   so it inherits the existing auth + caches automatically.

This is the one genuinely hard-to-reverse step in this plan (installing
OS-level persistent services on 3 real machines, two of which aren't the
machine driving the work) — get explicit go-ahead immediately before
running the install/service commands on kappa and omicron specifically,
even though the overall plan has already been approved.

## Phase 2 — add self-hosted build+publish to `.github/workflows/build.yml`

Change the existing `conda-package` job:
- `runs-on: ${{ matrix.os }}` (today: `[ubuntu-latest, macos-latest,
  windows-latest]`) → a matrix over the new self-hosted labels
  (`[self-hosted, linux]` / `[self-hosted, macos]` / `[self-hosted,
  windows]`).
- Drop the `prefix-dev/setup-pixi@v0.10.0` step — the self-hosted
  machines already have pixi installed and the `pkg` env resolvable from
  cache; no need to reinstall it every run the way a hosted runner would.
- Keep the existing `pixi run -e pkg conda-package` step unchanged.
- Add a publish step reusing `pixi.toml`'s already-existing per-platform
  `conda-publish` task (`[feature.pkg.target.<platform>.tasks]` already
  resolves the right `dist/conda/<platform>/*.conda` glob automatically —
  no new task needed):
  ```yaml
  - name: Publish to prefix.dev
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    run: pixi run -e pkg conda-publish
  ```
  Gated to push-on-main only, never PRs — matches this doc's own stated
  intent above, and is extra conservative given these are personal
  machines (the repo is private, so the fork-PR risk GitHub warns about
  for self-hosted runners doesn't apply, but no reason to publish
  speculative PR builds either).

No new GitHub secrets — auth is the already-established local
`rattler-build auth login` session on each machine (see `PLAN.md`'s
"Interim strategy" section for how that was set up).

The `recipe.yaml` build-number bump before a real release stays a manual
step, same as today — `--skip-existing` makes a forgotten bump a safe
no-op rather than a broken publish. A real auto-versioning scheme is a
separate, still-open decision (see `PLAN.md`'s implementation sketch
history), out of scope here.

## Phase 3 — verify end-to-end for real

- Trigger a real run (push to main, or `workflow_dispatch` if added)
  after bumping `recipe.yaml`'s build number, and watch it land on the
  self-hosted runners, build+test+publish, and confirm the new artifact
  actually appears on prefix.dev — same "verify for real, not just YAML
  review" discipline as everything else in this project.
- Confirm none of this session's leftover manual-testing state on
  kappa/omicron (stray `dist/testlib`, `00LOCK-*` dirs, the
  `test-pixi-r-zig` project, etc.) interferes with the runner's own
  checkout directory — the runner uses its own `actions-runner/_work/`
  tree, separate from `r-zig-pixi-zig-build`, so this should already be
  naturally isolated; confirm rather than assume.

## Phase 4 — docs

- Update `PLAN.md`'s "End goal" section status once implemented (currently
  marked "planned, not yet implemented").
- Record the three runners' labels/machine mapping here for future
  reference once registered.
