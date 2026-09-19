# flang-zig-validation: R built against flang-pixi's zig-built flang (documented 2026-09-19)

**What this documents**: the `flang-zig-validation` branch + worktree at
`/data/gamma/luciorq/workspaces/temp/r-zig-validation` — an experiment
that was live-in-progress (uncommitted) when the cross-project
consolidation effort started. Recorded here so the branch/worktree can
be cleaned up without losing what it proved.

## Purpose

Validate that this project's R build works with **flang-pixi's own
zig-built LLVM/flang packages** (`flang-zig` + `flang-rt-zig` 23.1.1,
from `file:///home/luciorq/projects/flang-pixi/channel`) as the linux-64
Fortran toolchain, replacing conda-forge's `flang`/`flang-rt_linux-64`.
This is the R-side half of flang-pixi's own
`docs/11-r-zig-integration.md` plan — proving the zig-built Fortran
compiler is a drop-in for the heaviest real consumer available (R's
full LAPACK/BLAS Fortran surface plus package-compilation contract).

## State found (uncommitted, branch based on pre-PR#5 `b580f31`)

Three working-tree changes:

1. **`pixi.toml`**: linux-64 swaps `flang`/`flang-rt_linux-64` →
   `flang-zig`/`flang-rt-zig` with the flang-pixi local `file://`
   channel prepended; plus a validation-only workaround pin
   (`pango 1.56.*`, `harfbuzz 14.2.*`).
2. **`pixi.lock`**: re-solved for the above.
3. **`scripts/verify-bundle.sh`**: NEW glibc-ceiling check (linux):
   scans every shipped ELF with `objdump -T` and fails if anything
   requires `GLIBC_ > 2.17` — the *verification* side of build.zig's
   existing glibc-2.17 floor pin ("a zig update or stray flag that
   raises the requirement should die here, not on a customer's CentOS 7
   box").

## Findings (real, from artifacts present in the worktree)

- **The validation build SUCCEEDED end-to-end**: `dist/R-4.6.1-slim-zig`
  exists, and `build/testlib-slim/` contains all five contract packages
  (Rcpp, data.table, minqa, pak, ps) — i.e. the full
  `contract-test.sh` suite ran against R built with zig-built flang.
  R 4.6.1 + flang-zig 23.1.1 passes the same bar as conda-forge flang.
- **Incidental finding, unrelated to flang** (recorded in the pixi.toml
  comment): a fresh solve pulled `pango 1.58` + split `libharfbuzz
  14.3`, which **break R 4.6.1's cairo compile** (hb.h include churn).
  This will bite the MAIN lockfile too on its next full re-solve —
  independent of any toolchain choice. Watch for it; the fix belongs
  upstream-or-pin in the main `pixi.toml`, not just here.

## What should survive into consolidation

1. **The glibc-ceiling check** in `verify-bundle.sh` — generally useful,
   toolchain-independent, should land on `main` regardless of the flang
   decision.
2. **The flang-zig swap result** — a proven data point for the
   single-direction plan (see PLAN.md in this directory): conda-forge
   flang is swappable for flang-pixi's zig-built flang with zero R-side
   code changes (dependency swap only).
3. **The pango/harfbuzz incompatibility warning** for the next lockfile
   refresh.

## Cleanup path (once the above are absorbed)

The branch itself has no committed work (it sits at `b580f31`, an
ancestor of merged PR #5); everything of value is the uncommitted diff
documented above plus the build artifacts' existence. After the
verify-bundle.sh change is ported to a real branch and the rest is
recorded here: `git worktree remove` the worktree and delete the
branch.
