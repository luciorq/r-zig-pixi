# Plan: clean up `universe` before going public (2026-08-06)

**Status (2026-08-07): in progress.** Decided alongside the version-bump
policy (see `TODO.md`'s "End goal" section): the channel goes public, but
only after a cleanup pass removes the messy build-number history from the
autoconf→zig-build migration period and a single, synchronized, clean
release replaces it at build number 1. Step 2 (`recipe.yaml`'s `number:`
9 → 1) is done, prepared in parallel while step 1 (deletion) happens —
**step 3 (the real publish) is gated on confirming step 1 is actually
complete first**, not run yet.

## Real current inventory (fetched 2026-08-06, not guessed)

Neither `rattler-build` nor `pixi` has a CLI subcommand to list every
package/build on a channel (`rattler-build upload`/`pixi upload` only
upload; `pixi search` only returns the single latest match). Fetched the
real per-platform `repodata.json` directly instead (the same file any
conda client reads to resolve packages — a plain authenticated GET, not
a destructive action) and parsed every entry:

| Platform | Build numbers present | Count |
|---|---|---|
| linux-64 | 0, 2, 5, 8, 9 | 5 |
| osx-arm64 | 0, 2, 5, 8, 9 | 5 |
| win-64 | 0, 1, 2, 3, 4, 5, 7, 8 | 8 |

**18 package files total.** Confirmed exact match against `pixi search`'s
own "`r-zig-slim-4.6.1-hb0f4dca_9` (+ 17 builds)" count (1 + 17 = 18).

None of these are "broken" in the sense of a failed/corrupt upload —
every one was a real, deliberately verified publish at the time (see
`TODO.md`'s own per-build "Packages successfully uploaded to prefix.dev
server" confirmations). What makes the *set* messy for a first-time
public consumer:

- **Builds 0/1** were produced by the old autoconf/gnuwin32 pipeline —
  an architecture retired entirely in Milestone 7
  (`feat-legacy-retirement/`). Nothing in this repo can reproduce them
  anymore.
- **The per-platform build numbers don't line up** (win-64 tops out at
  8, linux-64/osx-arm64 at 9, with gaps at 1/3/4/6/7 on the unix side and
  a gap at 6 on Windows) — an accurate reflection of this project's real
  iteration history (every gap/asymmetry is explained in
  `recipe/recipe.yaml`'s own build-number comment and `TODO.md`'s
  per-build entries), but not something a new public consumer should
  have to understand just to `pixi add r-zig-slim`.

## Deletion tooling (added 2026-08-10)

Originally believed impossible from outside prefix.dev's own dashboard
(see the git history of this file for that earlier, since-corrected
reasoning) — the dashboard genuinely has no delete button, but that's a
deliberate UI choice to discourage casual deletion, not the absence of
the capability. prefix.dev documents a real, intentional REST API for
this at <https://prefix.dev/docs/prefix/api>:

```
DELETE /api/v1/delete/:channel/:subdir/:package_file_name
POST   /api/v1/reindex/:channel/:subdir
```

Both auth'd via `Authorization: Bearer pfx_...` — an API key with
**Read/write/delete** scope on the channel, generated separately from
whatever `rattler-build auth login` already stored (that credential is a
bare opaque `BearerToken`, not the `pfx_`-prefixed shape the docs show
for API keys — different credential type, unconfirmed whether it even
has delete scope, so the tooling below doesn't try to reuse it).

Two new scripts, plus `pixi run -e pkg` tasks wrapping them (see
`pixi.toml`'s `[feature.pkg.tasks]`):

- `scripts/prefix-list-packages.sh <channel> <subdir>` /
  `pixi run -e pkg conda-channel-list <channel> <subdir>` — real
  inventory via `repodata.json`, same mechanism used to build the table
  above, no API key needed (uses the existing upload credential, which
  does have read access).
- `scripts/prefix-delete-package.sh [--yes] <channel> <subdir>
  <file.conda> [<file.conda> ...]` /
  `pixi run -e pkg conda-channel-delete -- [--yes] <channel> <subdir>
  <file.conda> ...` — real deletion + reindex. **Defaults to a dry run**
  (lists what would be deleted, makes no API calls) — `--yes` is required
  to actually delete anything. Requires `PREFIX_API_KEY` env var set to a
  real, delete-scoped key; fails with a clear error rather than silently
  trying a wrong-scoped credential.

Verified (2026-08-10, on gamma): dry-run mode, missing-arg handling, and
the real request shape (a deliberately-wrong API key against the real
endpoint returned a genuine `401 Not authorized` — confirms the URL/
method/header shape is correct).

**Real deletion run for real 2026-08-11**: all 18 packages deleted
across all 3 subdirs (5 linux-64 + 5 osx-arm64 + 8 win-64), each
individual `DELETE` call and each per-subdir `POST reindex` call
returned `200`. **One real gotcha hit and resolved**: immediately after
the win-64 batch finished, re-running `conda-channel-list` against all 3
subdirs still showed the old (pre-deletion) package lists — looked like
a failed deletion at first. Root-caused via `curl -sI` on the redirect
target (`packages.prefix.dev/.../repodata.json`, Cloudflare-fronted,
`cf-cache-status: DYNAMIC`) and fetching the raw body directly: the
`DELETE`/`reindex` calls succeed and return `200` immediately, but the
actual `repodata.json` content takes some number of seconds to catch up
server-side (not simple edge-cache staleness — `cf-cache-status:
DYNAMIC` means Cloudflare wasn't the one serving stale content) — a
short real propagation delay, not a failed operation. Re-checking a
short while later showed genuinely empty repodata (`"n_packages": 0`,
`"packages": {}"`) on all 3 subdirs, confirmed via both
`conda-channel-list` and a raw `curl` of the repodata body. **Lesson for
next time**: don't treat an immediately-after-deletion listing as
authoritative — wait/retry before concluding a delete didn't work.

## The plan

1. ~~**Delete the 18 packages listed above**~~ — **done 2026-08-11**, see
   above. Channel confirmed empty on all 3 subdirs.
2. **Bump `recipe/recipe.yaml`'s `number:` from 9 back to 1.** Done
   2026-08-07, prepared in parallel with step 1 rather than strictly
   after it — safe to do regardless of step 1's exact completion state
   since it's a local, uncommitted/unpublished change on its own branch
   (`feat-channel-cleanup`) until step 3 actually runs. Build-number
   history comment updated to note the reset and why.
3. **Publish fresh, synchronized builds from all 3 machines** (gamma/
   omicron/kappa) — `pixi run -e pkg conda-package` then
   `pixi run -e pkg conda-publish` on each, same procedure as every prior
   release, verified via the "Packages successfully uploaded" line each
   time. This produces `linux-64`/`osx-arm64`/`win-64` all at build
   number 1 together — the first genuinely synchronized release across
   all 3 platforms since the zig-build migration. **Blocked on step 1
   being confirmed complete first** — publishing at "1" while old content
   still sits at that number on win-64 would either collide or silently
   overwrite the wrong thing. **linux-64 done and index-verified
   2026-08-15 (see "Linux publish + stuck indexer" below);
   omicron/kappa still pending (explicit user instruction was "run just
   the Linux publishing for now" — awaiting go-ahead for the other
   two).**
4. **You flip `universe` to public** via prefix.dev's channel settings —
   also your own action, not something to script. **Not started.**

### Linux publish + stuck indexer (2026-08-11)

`pixi run -e pkg conda-package` on gamma succeeded (`r-zig-slim-4.6.1-
hb0f4dca_1.conda`, recipe's own tests passed — `conda R OK` / `✔ all
tests passed!` in the build log). `pixi run -e pkg conda-publish`
(silent, known behavior) followed by an explicit `rattler-build upload
prefix ... -vv` re-run both confirm a genuine successful upload
("Packages successfully uploaded to prefix.dev server"), and a direct
`curl -sI` on the package file URL confirms the blob exists in storage
(`303` redirect to a real `packages.prefix.dev/<hash>` content-addressed
URL).

**But `universe/linux-64/repodata.json` still shows `packages: {}` /
`packages.conda: {}` after 3 separate manual `POST /api/v1/reindex/
universe/linux-64` calls (each returned `200 {"started":true}`) and
~10+ minutes total waiting** — far past the docs' own "usually completes
within a few seconds" claim, and much longer than the deletion batch's
propagation delay (which resolved in under a minute). Checked whether
this was channel-wide: `noarch` (never touched by the deletion cleanup)
correctly shows 5 real indexed packages, so the reindexing mechanism
works in general — the stuck state is isolated to the 3 subdirs touched
by the 18-package deletion batch (`linux-64`, `osx-arm64`, `win-64`, all
independently confirmed still empty).

**Working theory** (unconfirmed): the rapid-fire batch of 18 individual
`DELETE` + per-file `reindex` calls run back-to-back during cleanup left
the indexer wedged for this channel's 3 subdirs specifically — not
something a 4th manual reindex trigger is likely to fix blind, and no
job-status endpoint is documented to check what's actually queued/stuck
server-side.

**Decision (2026-08-11): wait and check back later** rather than
continue polling or attempting further unwedging tricks now. Current
state: linux-64 build-1 package is genuinely uploaded and safe (exists
in storage, will be picked up whenever indexing recovers) but not yet
visible/installable through the channel. **Step 3 is not complete** —
don't treat the linux-64 publish as done until `conda-channel-list
universe linux-64` actually shows it.

**Resolved 2026-08-15**: re-checked after ~4 days; `conda-channel-list
universe linux-64` now shows exactly `r-zig-slim-4.6.1-hb0f4dca_1.conda`
(total: 1). The indexer recovered on its own — no further reindex
triggers or intervention needed. The linux-64 leg of step 3 is complete
end-to-end. Amended lesson: post-deletion/publish indexing delays on
this channel can run to *days*, not seconds — the docs' "usually
completes within a few seconds" is not a bound to alarm on, and
uploaded blobs are safe in storage regardless (they get indexed
whenever the backlog clears).

## Verification

After step 3, before step 4: fresh-env consume test on all 3 platforms
(`pixi init` + `pixi add -c https://prefix.dev/universe r-zig-slim` from
a throwaway project, same check already automated for Windows in CI's
`conda-package` job) — confirm the new build-1 packages install and run
cleanly before making the channel visible to anyone outside this project.
