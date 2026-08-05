# Milestone 7 — legacy autoconf/gnuwin32 retirement (2026-08-05)

FINALIZATION.md's "Final" item (2026-07-28) retired autoconf/gnuwin32 from
the *default* path but kept it as an explicit `*-legacy` fallback for one
release. This milestone removes it entirely — done on branch
`feat-legacy-retirement`, off `main`, since the diff touches enough files
to warrant its own PR rather than folding into other work.

## What was removed

- [x] 5 legacy-only scripts: `scripts/build-r.sh`, `build-gnuwin32.sh`,
      `configure-r.sh`, `install-r.sh`, `check-r.sh` — verified via `grep`
      that nothing else `exec`s or sources them.
      `env.sh`/`stage.sh`/`fetch-r.sh` are kept (shared with the
      zig-build path, as expected). **Real near-miss, corrected before
      committing**: `smoke-test.sh`, `contract-test.sh`,
      `package-standalone.sh`, and `verify-bundle.sh` were *also*
      deleted in the first pass on the assumption they were legacy-only
      (matching the `*-test.sh`/`*-standalone.sh` naming pattern of the
      other legacy scripts) — they are not. `zig-smoke.sh`,
      `zig-contract.sh`, `zig-package.sh`, and `zig-verify-package.sh`
      (all active, non-legacy pixi tasks: `smoke`, `contract`, `package`,
      `verify-package`) each just set a couple of zig-prefix env vars and
      then `exec bash ".../<one of these four files>"` — they're the
      actual shared assertion/packaging bodies, not legacy dead code.
      Caught by testing `pixi task list` and re-`grep`ping for `exec`
      references immediately after the first deletion pass, before this
      branch was ever pushed; restored via `git checkout HEAD -- <files>`
      before proceeding. Lesson: a `-legacy`-suffixed *task name*
      pointing at a script doesn't mean the script itself is legacy-only
      — always check what else `exec`s/sources a file before deleting it,
      not just what invokes it directly.
- [x] 8 pixi tasks: `configure-legacy`, `build-legacy`, `smoke-legacy`,
      `check-legacy`, `contract-legacy`, `install-legacy`,
      `package-legacy`, `verify-package-legacy` — removed from
      `pixi.toml`'s `[tasks]`, confirmed via `pixi task list`.
- [x] 2 CI jobs: `build-legacy` and `build-windows-legacy` — removed
      entirely from `.github/workflows/build.yaml` (not just gated off;
      their underlying tasks no longer exist). The zig-build path's own
      hosted-runner jobs (`build`, `build-windows`) are untouched, still
      gated behind `ENABLE_HOSTED_JOBS` (explicit decision — out of scope
      for this milestone, see the milestone-planning conversation).
- [x] `README.md`'s "Toggling the hosted-runner CI jobs" section updated
      to drop the now-nonexistent `build-legacy`/`build-windows-legacy`
      job names.
- [x] `FINALIZATION.md`'s "Final" checklist entry annotated with a pointer
      here.

## What was deliberately left alone

- `[target.win-64.dependencies]`'s `m2-*` packages (m2-bash, m2-sed,
  m2-grep, m2-gawk, m2-coreutils, m2-make, m2-which, m2-findutils,
  m2-tar, m2-gzip, m2-unzip, m2-zip, m2-texinfo, m2-diffutils) — these
  look legacy-gnuwin32-specific at a glance but are genuinely shared: the
  zig-build Windows path needs them too (m2-bash runs `recipe/build.sh`
  itself and backs `win-exec-forward.c`'s `gcc.exe`/`g++.exe` forwarder;
  m2-sed/m2-grep/m2-gawk/etc. were added specifically for the zig path
  per F7.1's follow-up, see `feat-zig-build/TODO.md`). Verified via
  `grep` before touching anything.
- Historical comments across `recipe/recipe.yaml`, `recipe/build.sh`,
  `zig-*.sh`, and other devdocs (`TODO.md`/`PLAN.md`/`FINALIZATION.md` in
  `feat-zig-build`/`feat-initial-setup`/`feat-prefix-publish`) that
  mention the old script names in a "switched FROM X TO Y" or "unlike the
  old path" sense — left as-is, matching this project's established
  convention of keeping historical narrative in devdocs rather than
  scrubbing references to retired code. Only touched comments in files
  describing *current* state (`README.md`, `pixi.toml`, `build.yaml`,
  `FINALIZATION.md`'s own checklist).

## Verification

- `pixi task list` — confirms the 8 legacy tasks are gone, all zig-build
  and CI-helper tasks intact.
- `python3 -c "import yaml; yaml.safe_load(...)"` on `build.yaml` — valid.
- Repo-wide `grep` sweep for legacy script filenames and task names before
  and after, to confirm nothing else referenced them functionally (only
  historical comments remained, see above).
