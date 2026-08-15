# v3 package specs (flags/extras): evaluated 2026-08-15, deferred

pixi and rattler-build recently added opt-in support for "v3" package
specs — see <https://pixi.prefix.dev/latest/CHANGELOG/#v3-repodata> and
<https://rattler-build.prefix.dev/dev/v3/>. Evaluated against this
project right before the channel-cleanup build-1 publish; decision:
**do not adopt now, but v3 variant flags are the designated mechanism
for the day the `full` variant ships.** Rationale recorded here so the
slim/full-unification decision is written down before `universe` goes
public.

## What v3 adds

- **Variant flags** (`build.flags:` in recipe.yaml, e.g.
  `variant:slim`): lowercase tags recorded in the built package's
  `index.json` (`"flags": [...]`, `"repodata_revision": 3`). Unlike
  `variants.yaml`/`conda_build_config.yaml` (which drive matrix
  expansion at build time), flags tag the *resulting* package and let
  consumers select at resolve time: `r-zig[flags=[variant:full]]`.
- **Extras** (`requirements.extras:`): named optional *runtime*
  dependency groups, opt-in at install time
  (`mypkg[extras=[plot]]`) — conda's equivalent of pyproject.toml
  optional-dependencies.
- **`when=` conditionals** on individual run deps
  (`scipy[when="python >=3.10 and __linux"]`).

## Fit for this project

**Strong fit, later — the slim/full split.** Today the variant is
encoded in the package *name* (`r-zig-slim`). Flags are exactly the
right shape for it instead: one public name `r-zig`, builds tagged
`variant:slim`/`variant:full`. This matches the project's reality
better than any existing mechanism — slim/full are genuinely separate
compile-time builds (separate configure profiles, capabilities baked at
compile time), not dependency toggles, so build-matrix-style variants
were never the right tool and the name-suffix convention was the
workaround.

**No fit — extras for slim/full.** Extras add optional runtime deps;
they cannot change what was compiled in. No dependency group turns a
slim build into a full one. (Extras may be interesting for the separate
`r-zig-packages` rz-* repo as a Suggests analog — noted there, not
here.)

**Modest fit, later — `when=`** could collapse some per-platform
dependency sprawl in the recipe (e.g. the win-64 tcltk/jpeg/tiff parity
carve-out).

## Why deferred (2026-08-15)

1. **Beta, opt-in.** rattler-build gates it behind `--v3`; consumers
   need a recent pixi. The entire point of the channel cleanup was that
   a first-time public consumer can `pixi add r-zig-slim` with zero
   surprises — shipping a beta metadata format at that exact moment
   cuts against it.
2. **The unanswered compatibility question.** The docs don't say what a
   non-v3 client (older pixi, conda, mamba) sees when two builds share
   a name and differ only by flags. If they're indistinguishable to old
   resolvers, publishing flag-differentiated slim+full would be
   actively dangerous on a public channel. This must be answered (by
   testing, not docs-reading) before adoption.
3. **Freshness of the machinery.** `universe`'s repodata already serves
   `"repodata_revisions": {"v3": ...}` — prefix.dev's server side is
   v3-ready, and that's the same indexing path that wedged for ~4 days
   after the 18-package deletion batch (see CHANNEL_CLEANUP.md). Not
   disqualifying, but a reminder this is all new plumbing.

## Adoption trigger and naming implication

The natural adoption point is **when the `full` variant first ships**:
that's when a second build per platform exists and flag-based selection
starts paying for itself. At that point, decide between:

- `r-zig` + `variant:slim`/`variant:full` flags (clean, but renames the
  already-public `r-zig-slim` — migration/alias cost grows with every
  day the channel is public), or
- keep `r-zig-slim`/`r-zig-full` names and skip flags for the variant
  axis entirely (no rename, flags then only worth it for a future axis
  like `blas:openblas`).

The rename cost is the one argument for deciding *early* — recorded
here precisely so that decision isn't made by default years in.
