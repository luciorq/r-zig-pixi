# chore-ci-tiers — a core tier on every push, the full matrix on the `full-ci` label

**Status (2026-10-08).** Branch chore-ci-tiers, not committed yet. It
starts from PR (i)'s pushed state, not from main: PR #17,
chore-deps-ci-checks at 3510530, with D13's `linux_runner` input in
build.yaml and D9's minimal check in build-r.yaml. main has since merged
#14 and #15 (92394d5); they touch none of this branch's files. Of the
workflows this branch changes build.yaml only; build-r.yaml,
upstream-zig.yaml and gen-config.yaml are untouched. It also edits the
ci-trigger comment in pixi.toml and adds a paragraph to README.md's
CI section. recipe/, build.zig, zigbuild/, scripts/ and pixi.lock are
untouched, so the recipe's build number does not
move.

Why on PR (i)'s state rather than after its merge: both change
build.yaml's matrix (D13 replaced `ubuntu-latest` with the
`linux_runner` expression on the four linux-64 entries), so this branch
sits on PR (i)'s build.yaml either way. PR (i) is committed and pushed,
so this branch can be reviewed now instead of after #17 merges. The
pull request is stacked on #17 (base chore-deps-ci-checks); once #17
merges, its base moves to main (GitHub does that when #17's branch is
deleted; otherwise `gh pr edit <n> --base main`).

Why. Every pull request push and every push to main ran the whole
matrix: 15 build legs and conda-package on all 5 platforms, 20 jobs,
about 57 minutes of wall time and about 305 job-minutes (run
37806314996). Every `git merge origin/main` into a pull request ran it
again. Skip tags typed by hand are fragile: `[skip-ci]` with a hyphen
ran the full matrix for a docs commit, and a merge whose newest commit
is `[skip ci]` was never tested, which is how #15's merge of main went
untested. The planned work adds jobs on top (B31's toolchain job per
platform, verify-bundle's three scenarios). CI should check what each
change can break, run the expensive checks only when someone asks for
them, and need no tags.

## What was there (checked first)

- **Concurrency:** one group per ref, `${{ github.workflow }}-${{
  github.ref }}`, with `cancel-in-progress: true` for every event. A
  newer push to main cancelled the older main run, and a second
  dispatch cancelled the first.
- **ENABLE_HOSTED_JOBS:** `if: vars.ENABLE_HOSTED_JOBS == 'true'` on
  both jobs (build, conda-package).
- **The matrix:** `os` (linux-64 via `linux_runner`, ubuntu-24.04-arm,
  macos-latest, macos-15-intel) × `env` [default, full], plus openblas
  on both linux archs, minimal on the four unix runners, and
  windows-latest default (--verbose, 90 minutes): 15 legs.
- **Publishing:** conda-package's last step, `if: github.ref ==
  'refs/heads/main' && (github.event_name == 'push' ||
  github.event_name == 'workflow_dispatch')`. Unchanged.
- **paths-ignore:** `**/*.md`, `.github/devdocs/**` and `LICENSE`, on
  push and pull_request. Unchanged.
- **Required checks:** none. main is not protected and has no rulesets
  (`gh api repos/luciorq/r-zig-pixi/branches/main/protection`: "Branch
  not protected"; rulesets: `[]`). So paths-ignore cannot block a merge,
  and no always-passing stand-in job is needed. If checks are ever made
  required, the build.yaml header's note applies: a docs-only PR then
  reports no build-r checks and waits on them forever.
- upstream-zig.yaml already runs only with its label, a `v*` tag or a
  dispatch, and already lets a `labeled` event for another label run
  nothing and cancel nothing (its own group). This branch copies that
  pattern. gen-config.yaml runs on dispatch and on its watched paths.
  There is no stress workflow on this base yet; the stress suite's plan
  is dispatch-only.

## What runs when

- **Core tier (6 legs):** `default` on linux-64, linux-aarch64,
  osx-arm64, osx-64 and win-64, and `minimal` on linux-64. minimal on
  linux-64 is in the core because it builds and tests the r-zig wheel.
  Each leg runs build-r.yaml's steps as before (rzig-test, build,
  verify-tree, smoke, contract, check, hermetic, verify-package; on
  minimal also minimal-check and the wheel). Job `build`.
- **Full tier (15 legs):** the core plus `full` on the four unix
  runners, `openblas` on both linux archs, and `minimal` on
  linux-aarch64, osx-arm64 and osx-64. Job `build-full` holds those 9
  legs.
- **conda-package (5 jobs):** on every push to main, because main
  publishes; on every dispatch; with `full-ci`; and on a pull request
  whose diff touches `recipe/`, `pixi.toml`, `pixi.lock`, `build.zig`,
  `zigbuild/`, `scripts/` or `.github/workflows/`. Those are the
  recipe's sources (recipe.yaml copies scripts/, build.zig and
  zigbuild/), the pkg env and the CI that builds it. toolchain/ and
  python/ are not recipe inputs.
- **packaging (one small job):** on a pull request without `full-ci`,
  it lists the pull request's files with `gh api --paginate
  repos/<repo>/pulls/<n>/files` (GITHUB_TOKEN, `pull-requests: read`)
  and matches them against those paths. That list is the pull request's
  whole diff (base...head), the same diff GitHub matches paths-ignore
  against, so a later push that touches no such file still packages a
  pull request that changed the recipe. Renames count by their old name
  too. If the list cannot be read, it answers yes, with a warning. It
  takes seconds and needs no checkout.

Job names do not change: legs read "<os> / <env>", packages
"conda-package / <name>". A skipped matrix job shows in the checks list
under its unexpanded name, as upstream-zig's does today: "matrix.os"
(build-full) and "conda-package / matrix.name".

### Trigger table

| Event | Build legs | conda-package | Publishes | Cancels |
|---|---|---|---|---|
| Docs-only pull request, or docs-only push to main (`*.md`, `.github/devdocs/**`, `LICENSE`) | none, no run | none | no | nothing |
| Pull request opened, pushed or reopened, without `full-ci`, diff touches no packaging path | core, 6 | no | no | the pull request's older run |
| Same, diff touches a packaging path | core, 6 | 5 | no | the pull request's older run |
| `full-ci` added to a pull request (`labeled`) | full, 15 | 5 | no | the pull request's older run |
| Push to a pull request that has `full-ci` | full, 15 | 5 | no | the pull request's older run |
| Any other label added | none (every job skipped) | none | no | nothing (a group of its own) |
| `full-ci` removed | no run (`unlabeled` is not a trigger) | | | |
| Push to main (not docs-only) | core, 6 | 5 | yes | nothing |
| Manual dispatch (`pixi run ci-trigger`, `gh workflow run build.yaml`) | full, 15 | 5 | on main only | nothing |
| upstream-zig label, `v*` tag, its dispatch | upstream-zig.yaml, unchanged | | | |

Counts: a pull request run without `full-ci` is 6 legs plus packaging,
plus 5 conda-package jobs when packaging says yes. A push to main is 11
jobs. A full run is 20 jobs (packaging is skipped).

Wall time, from the green run 37806314996: the core's slowest legs are
macos-15-intel / default (23 to 29 min) and windows-latest / default
(24 to 29 min), and conda-package / win-64 takes about 25 min. A core
run takes about 30 min; the full run took 57. Job-minutes: the core legs
are about 110, the 15 legs 240, conda-package 65.

Note on paths: on a pull request GitHub matches paths-ignore against
the pull request's whole diff, not the pushed commits ("Pull requests:
Three-dot diffs are a comparison between the most recent version of the
topic branch and the commit where the topic branch was last synced with
the base branch", workflow syntax, `on.<push|pull_request>.paths`). So
a docs-only push to a pull request that already changes code runs the
core tier again. A docs-only pull request, and a docs-only push to
main, start nothing.

Note on packaging: all 16 pull requests merged so far touch at least one
packaging path (#4, the smallest, through recipe/recipe.yaml). With this
list, conda-package would have run on every one of them. The saving on
pull requests is in the build legs (15 to 6).

## Why it is built this way

- **Two build jobs, not one matrix chosen per event.** Job-level `if`
  cannot read the matrix, and a matrix's `include` entries cannot be
  dropped by `exclude`, so the extra legs are their own job with its own
  condition. Both matrices stay plain YAML.
- **Conditions in expressions, not in a script.** Every job's condition
  reads only the event (event name, action, the added label, the pull
  request's labels) plus packaging's answer. act evaluates those (see
  Validation), and they mirror upstream-zig.yaml's.
- **The `labeled` trigger.** Without it, adding `full-ci` would start
  nothing until the next push. With it, every label starts a run, so a
  `labeled` event for another label must run nothing (every job's
  condition) and cancel nothing (the concurrency group).
- **The full tier includes the core legs.** A `full-ci` run cancels the
  pull request's running core run (same group), so it has to run those
  legs itself.
- **Concurrency.** The group is `build-r-pr-<number>` for a pull request
  event that runs something, with `cancel-in-progress: true`. Any other
  run (push to main, dispatch, another label) gets `build-r-<run id>`,
  a group of its own, so it is never cancelled and never waits. A
  shared group without cancel-in-progress would still cancel: "By
  default, any existing pending job or workflow in the same concurrency
  group will be canceled" (workflow syntax, `concurrency`).
- **`!cancelled()` on conda-package.** packaging is skipped on push,
  dispatch and with `full-ci`, and a job whose need is skipped is
  skipped too unless its condition uses a status function ("A default
  status check of `success()` is applied unless you include one of
  these functions", expressions reference).
- **No ready-for-review trigger, no full run on push to main.** As
  asked: only the label and a dispatch start the full tier.

## How to run the full matrix by hand

- On a pull request: `gh pr edit <n> --add-label full-ci`. It starts at
  once and stays on for later pushes. `gh pr edit <n> --remove-label
  full-ci` returns to the core tier from the next push. "Re-run failed
  jobs" re-runs with the original event, so the labels it sees are the
  ones of that run.
- On any branch: `gh workflow run build.yaml --ref <branch>` (does not
  publish; `-f linux_runner=ubuntu-26.04` for D13's early 26.04 run).
- On main: `pixi run ci-trigger` (`gh workflow run build.yaml --ref
  main`). This also publishes, as before, with `--skip-existing`.
- The label must exist once: `gh label create full-ci --description
  "build.yaml: run the full matrix" --color 5319e7`.

Add the `full-ci` label to a PR that needs the full matrix (e.g.
toolchain, flavor or packaging changes).

## Validation

Done in a scratch copy of PR (i)'s tree (3510530), with conda-forge's
actionlint 1.7.12, shellcheck 0.11.0 and act 0.2.89 (`pixi exec`). No
dispatch run, no test branch: nothing was pushed. This pull request is
the test branch; the live checks are below.

- **actionlint** (with shellcheck): the four workflows are clean.
  Injecting an unquoted variable into the packaging script made it
  report SC2086, so shellcheck does run on it.
- **The packaging script, unit test.** The step's own `run:` text,
  read from build.yaml, run under GitHub's `bash --noprofile --norc -eo
  pipefail` with a fake `gh` that applies the step's jq filter to a
  fixture. 13 of 13 pass: docs only, false; python/ and toolchain/,
  false; recipe/, pixi.toml, pixi.lock, build.zig, zigbuild/, scripts/
  and a workflow, true; near misses (python/scripts/, docs/pixi.toml,
  pixi.toml.orig, build.zig.zon, .github/devdocs/recipe/), false; a
  rename out of recipe/, true; no files, false; an API error, true with
  the warning.
- **The real API call**, read-only: PR #16 lists 5 files, #13 7, #12
  105 (two pages), equal to each pull request's changedFiles.
- **act dry runs** of build.yaml (`act <event> -e <payload> -n --var
  ENABLE_HOSTED_JOBS=true -P <runner>=<image>`). Images only: with `-P
  <runner>=-self-hosted`, act 0.2.89 runs `run:` steps on the host even
  in a dry run. Jobs act would start:

  | Case | Event | Jobs |
  |---|---|---|
  | (a) docs-only PR push | pull_request synchronize | 6 legs + packaging (act ignores paths-ignore) |
  | (b) code PR push | pull_request synchronize | 6 legs + packaging |
  | (c) packaging PR push | pull_request synchronize | 6 legs + packaging (the dry run sets no outputs) |
  | (d) `full-ci` added | pull_request labeled full-ci | 15 legs + 5 conda-package |
  | (e) push, PR has `full-ci` | pull_request synchronize | 15 legs + 5 conda-package |
  | (f) another label added | pull_request labeled upstream-zig (PR also has full-ci) | 0 |
  | (f2) another label, no `full-ci` | pull_request labeled documentation | 0 |
  | (g) push to main | push | 6 legs + 5 conda-package |
  | (h) dispatch on main | workflow_dispatch | 15 legs + 5 conda-package |
  | (h2) dispatch, `linux_runner=ubuntu-26.04` | workflow_dispatch | 15 legs + 5, the four linux-64 legs on ubuntu-26.04 |
  | gate off | push, ENABLE_HOSTED_JOBS=false | 0 |

  The 6 core legs: ubuntu-latest, ubuntu-24.04-arm, macos-latest and
  macos-15-intel / default, ubuntu-latest / minimal, windows-latest /
  default. The same dry runs of the base build.yaml (PR (i)'s) give 20
  jobs for every event, and its 20 are exactly this branch's full tier,
  leg for leg.
- **act, real run of a stubbed copy** for what the dry run cannot show:
  build.yaml's triggers, conditions, matrices and packaging script
  verbatim; every other step replaced by an echo; a fake `gh`. (b) with
  python/ and toolchain/ files: packaging says `changed=false`, 7 jobs
  ran (6 legs, packaging), no conda-package. (c) with recipe/: `changed=
  true`, 12 jobs (6 legs, packaging, 5 conda-package). (g) push to main,
  packaging skipped: 11 jobs, conda-package ran (`!cancelled()`). The
  Windows leg got timeout 90 and `-- --verbose`, the others 180.
- **The concurrency group**, its expression evaluated by act per event:
  `build-r-pr-7` for a push, the `full-ci` label, and a push with
  `full-ci`; `build-r-<run id>` for another label, push to main and
  dispatch. act's run id is always 1; GitHub's is unique per run ("A
  unique number for each workflow run within a repository", contexts
  reference).
- **What act cannot show:** (a), since act applies neither paths
  filters nor activity types (the base workflow, which has no `labeled`
  type, still ran for the labeled payloads). (a) rests on GitHub's
  documented behavior, unchanged from before (the paths-ignore lines did
  not change). The diff-based part of (b) and (c) rests on the unit test
  and the stub run.

## Live checks (on this pull request)

This pull request changes a workflow, so packaging says yes on it.

- Opened: 6 legs, packaging (`changed=true`, the log names
  .github/workflows/build.yaml), 5 conda-package; build-full skipped
  ("matrix.os"). Result: _pending_.
- Add another label while the first run is going (`gh pr edit <n>
  --add-label documentation`; not upstream-zig, which starts
  upstream-zig.yaml's legs): a build-r run with every job skipped, and
  the running run goes on. Result: _pending_.
- Add `full-ci`: the running run is cancelled; a new run with 15 legs
  and 5 conda-package, packaging skipped. Result: _pending_.
- Remove `full-ci`, push a docs-only commit: the core tier runs again
  (the pull request's diff has code). Result: _pending_.
- Optional, a docs-only pull request (e.g. this PLAN's results on a
  throwaway branch): no build-r run. Result: _pending_.
- After the merge, the push to main: 6 legs and 5 conda-package; the
  publish step runs and skips the existing build 4. Result: _pending_.
- `gh workflow run build.yaml --ref main` (or a branch): 20 jobs.
  Result: _pending_.

## Risks

- Two pushes to main now run side by side, each publishing. With an
  unchanged recipe `--skip-existing` skips both. Two different builds
  of the same version and build number would race for the upload; the
  build number is bumped per release, so that should not happen.
- A pull request event's labels are the ones at that event: a re-run
  keeps them.
- Every label added to a pull request now starts a build-r run, with
  every job skipped for a label other than `full-ci` (upstream-zig.yaml
  already does the same). `pixi run ci-rerun-failed` reruns the newest
  build-r run, so right after a label it finds nothing to rerun; `gh run
  list --workflow=build.yaml` shows which run is which.
- The full matrix runs less often, so a regression in `full`,
  `openblas`, or minimal off linux-64 shows up at the next `full-ci` or
  dispatch, not at the commit that caused it. Pushes to main run the
  core only.

## Open

- check (R's regression suite) and hermetic stay in the core legs; the
  request's list named build, rzig-test, verify-tree, smoke, contract
  and verify-package. Minutes per core leg (runs 37806314996 and
  37512701120): check 3.9 on ubuntu-latest default, 3.9 to 4.3 on
  ubuntu-latest minimal, 3.4 to 3.5 on ubuntu-24.04-arm, 4.0 to 4.4 on
  macos-latest, 5.7 to 6.5 on macos-15-intel, 5.2 to 6.3 on
  windows-latest; hermetic 0.1 on every unix leg, 0.2 to 0.3 on
  windows-latest. Dropping check would take about 6 minutes off the
  core run's critical path (macos-15-intel, windows-latest).
- The packaging path list matches every past pull request, and would
  even without `.github/workflows/`: each of #1 to #16 changed recipe/,
  scripts/, build.zig, zigbuild/, pixi.toml or pixi.lock. So on pull
  requests conda-package will run on most code changes, and narrowing
  the list would not change that. If that is too much, the lever is to
  package on pull requests only with `full-ci` (main still packages
  every push).
- A docs-only push to a code pull request runs the core tier (GitHub
  matches the whole diff). Skipping it would mean comparing the pushed
  commits, and a push that cancels a code push's run would then leave
  that code untested, the problem #15 had.
