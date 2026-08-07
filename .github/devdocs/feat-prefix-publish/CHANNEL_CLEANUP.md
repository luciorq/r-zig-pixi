# Plan: clean up `universe` before going public (2026-08-06)

**Status: plan only, no packages deleted yet.** Decided alongside the
version-bump policy (see `TODO.md`'s "End goal" section): the channel
goes public, but only after a cleanup pass removes the messy
build-number history from the autoconf→zig-build migration period and a
single, synchronized, clean release replaces it at build number 1.

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

## What I can't do, and why

Deleting published packages needs an actual delete operation against
prefix.dev — confirmed no such operation exists in either CLI tool I have
access to. prefix.dev's web dashboard clearly has one (any package
manager UI does), backed by an internal API (`https://prefix.dev/api/
graphql` responds), but reverse-engineering and calling an undocumented
mutation to delete published artifacts is exactly the kind of
destructive, hard-to-reverse action that should go through the real,
confirmed-in-the-UI path — not something to improvise from outside. This
step is yours to do directly.

## The plan

1. **You delete the 18 packages listed above** via prefix.dev's own
   channel management UI (Settings → the `universe` channel → per-package
   version management, or equivalent — the exact UI path isn't something
   I can verify without access to it myself). Every file to remove is
   listed in the table's build-number ranges above, one entry per
   (platform, build number) pair.
2. **Bump `recipe/recipe.yaml`'s `number:` from 9 back to 1** once step 1
   is done (not before — publishing at "1" while old content still sits
   at that number on win-64 would either collide or silently overwrite
   the wrong thing). Update the build-number history comment to note the
   reset and why.
3. **Publish fresh, synchronized builds from all 3 machines** (gamma/
   omicron/kappa) — `pixi run -e pkg conda-package` then
   `pixi run -e pkg conda-publish` on each, same procedure as every prior
   release, verified via the "Packages successfully uploaded" line each
   time. This produces `linux-64`/`osx-arm64`/`win-64` all at build
   number 1 together — the first genuinely synchronized release across
   all 3 platforms since the zig-build migration.
4. **You flip `universe` to public** via prefix.dev's channel settings —
   also your own action, not something to script.

## Verification

After step 3, before step 4: fresh-env consume test on all 3 platforms
(`pixi init` + `pixi add -c https://prefix.dev/universe r-zig-slim` from
a throwaway project, same check already automated for Windows in CI's
`conda-package` job) — confirm the new build-1 packages install and run
cleanly before making the channel visible to anyone outside this project.
