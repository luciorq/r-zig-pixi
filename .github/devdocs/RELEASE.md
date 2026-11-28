# Release checklist (conda packages to universe)

The durable steps of a release. Derived from chore-release-11/PLAN.md
(build 11, run 44336177906), fix-icu-pin/PLAN.md ("a rebuilt `_8` is
not universe's `_8`") and build.yaml's conda-publish job. Each release still
keeps its own record (a `chore-release-<N>/PLAN.md`) with the run ids.

## Rules

- **Never delete a universe `_N` file before `_N+1` is published.** A
  `_N` rebuilt today differs from universe's (newer run-export floors, a
  different libR), and `--skip-existing` only keeps universe's copy
  while it exists: delete it first and the next publishing run uploads
  today's content under the old name.
- **One build number per publish.** Bump `build.number` in
  `recipe/recipe.yaml` once per release, never publish two contents
  under one number. Between releases the `CONDA_PUBLISH` repository
  variable stays unset, so a dispatch on main uploads nothing (a push
  never does).
- **All six subdirs together.** One job uploads them, after every
  subdir's packages passed their tests.
- **Both zigs.** conda-forge zig and upstream zig (PyPI ziglang) must
  both pass on the release code: the `upstream-zig` label run is a
  release gate, not optional.

## Before

1. The release code is on one sha: a release PR with the `full-ci` and
   `upstream-zig` labels (build-r full tier and upstream-zig), plus a
   stress dispatch on it. Read every result table row by row, never just
   the job status.
2. The bump: `build.number` is the number after universe's newest on
   every subdir (`pixi run -e pkg conda-channel-list universe <subdir>`
   for linux-64, linux-aarch64, osx-64, osx-arm64, win-64, win-arm64).
3. `pixi lock --check` passes; the lock's sha is in the release record.
4. The publish preflight (the `publish-preflight` skill): disk space,
   lockfile, no gitignored recipe inputs. Hosted CI publishes through
   OIDC trusted publishing, so no token is needed there; a host that
   uploads by hand needs a live prefix.dev token (401 means stop).
   Any no-go stops the release.

## Publish

1. Merge the release PR (the user). The merge's push run on main
   publishes nothing: only a dispatch does (build 14 on; until build 13
   a push with `CONDA_PUBLISH` set published too, and release 13
   cancelled its push run).
2. `gh variable set CONDA_PUBLISH --body true`
3. `gh workflow run build.yaml --ref main`. The job `conda-publish` of
   `.github/workflows/build.yaml` uploads all six subdirs, after all six
   `conda-package` jobs passed: it runs only for a dispatch on main with
   `CONDA_PUBLISH` set (its `if:`). If a `conda-package` job fails,
   nothing is uploaded: re-run the failed jobs. If only `conda-publish`
   fails, re-run it alone.
4. When the run is done: `gh variable delete CONDA_PUBLISH`, success or
   not.

A dispatch on main without `CONDA_PUBLISH` is a rehearsal: the packages
are built, tested and kept as the artifacts `conda-<subdir>`, and
`conda-publish` is skipped.

## After

1. universe has every package at `_N` on all six subdirs, with
   `conda-channel-list` or the subdir's `repodata.json`. The packages
   are the outputs of `recipe/recipe.yaml`, less each output's
   `build.skip`; count them from the recipe, not from this list. Build
   13: r-zig-slim, -compilers, -build-tools, -extras, -toolchain,
   -recommended and -tcltk, seven per subdir, six on win-arm64 (no
   r-zig-tcltk there). Build 14 adds r-zig-native-tools on Windows: seven per unix subdir, eight on win-64, seven on win-arm64. The staging output r-zig-build is not published.
2. A fresh environment from universe only (no local channel, fresh
   caches), universe listed before conda-forge (README's `--prepend`):
   `pixi add r-zig-slim r-zig-toolchain`, R starts,
   `R CMD config CC` names zig-cc, a small C library builds with
   `R CMD SHLIB` and loads.
3. macOS packages: every Mach-O file's LC_BUILD_VERSION minos is 13.0
   (`llvm-otool -l`, or a Mach-O scan of the extracted `.conda`), as
   `__osx >=13.0` in index.json says (build 11: docs-backlog-hygiene
   PLAN.md, Q21).
4. The release record gets the run id, the date and the build strings;
   the recipe comment on the published number is updated; open records
   that waited for "published as `_N`" are closed.
5. Only now may older `_N-1` files be deleted from universe, if at all.
