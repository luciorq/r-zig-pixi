# Developer records

One directory per branch, as [CONVENTIONS.md](CONVENTIONS.md) says. This
page is the map: which files are rules, which are the current work and
which are history.

## How to read this directory

- **Living documents** state what holds now. A change that makes one of
  them wrong corrects it in the same pull request.
- **Branch records** (`<branch>/PLAN.md`) state what a branch decided
  and found, at the date they give. After the branch merges they are
  history: they are not rewritten when a later branch changes the
  design, so they can name things that no longer exist. A closed item
  gets a dated note, not an edit of its text.
- A record cites another by its directory and its item id (`b13-fixes
  F14`, `chore-release-11 finding 23`). Code comments cite records the
  same way.
- The newest release record says what is published. The newest `bNN-*`
  directories are the work for the next build.

## Living documents

| File | What it holds |
| --- | --- |
| [CONVENTIONS.md](CONVENTIONS.md) | The goals, the working principles and the commit rules |
| [RELEASE.md](RELEASE.md) | The steps of every release to universe |
| [CXX-STDLIB.md](CXX-STDLIB.md) | The C++ standard library on each OS, and why |
| [../../README.md](../../README.md) | What users install and how; the CI tiers |
| [../../stress/README.md](../../stress/README.md) | The stress suite: its rows, their expectations, how to read a run |

## Release records

| Build | Published | Record |
| --- | --- | --- |
| 13 | 2026-11-26 | `chore-release-13/` |
| 12 | 2026-11-24 | `chore-release-12/` (`BACKLOG.md` is the list that builds 12 to 14 work through) |
| 11 | 2026-11-18 | `chore-release-11/` |
| 10 | 2026-11-09 | `feat-standalone-toolchain/PLAN.md`, "Phase 9" |
| 9 | 2026-11-05 | `feat-standalone-toolchain/PLAN.md` (dispatch 41942729382) |

## Branch records, newest first

### Build 14 (in progress)

| Directory | Topic |
| --- | --- |
| `chore-review-consistency/` | A review of the whole project against its goals: rzig make-parity fixes, script checks, this page |
| `b14-l4/` | Native Windows build tools, an opt-in (`r-zig-native-tools`) |
| `b14-l5/` | The linux binary package repository (experimental) |
| `b14-openblas/` | The Windows openblas crash at `ar.ols` |
| `b14-rhtslib/` | Rhtslib's `regex.h` on Windows |

### Build 13 (2026-11-24 to 2026-11-26)

| Directory | Topic |
| --- | --- |
| `b13-integration/` | The integration plan of the tracks below, and its CI wave |
| `b13-build/` | `zig build fetch`, config capture with rzig, the BLAS contract, GNU make built with zig |
| `b13-recipe/` | The recipe: the `r-zig-tcltk` add-on, licence and test hygiene |
| `b13-rzig/` | `R_ZIG_TOOLCHAIN_ENV`, `R_ZIG_SYSTEM_LIBS` |
| `b13-env-ci/` | The pixi features, Windows wheels, the gated release workflow |
| `b13-stress/`, `b13-slice2/` | Stress rows; the `zig-*` libraries of libs-zig-pixi slice 2 |
| `b13-hosts/` | Checks on the test hosts |
| `b13-design/` | The designs of L4 and L5, with prototypes |
| `b13-leftovers/`, `b13-fixes/`, `b13-make-aarch64/` | The open items after the integration; fixes found by the build-13 CI wave |

### Build 12 (2026-11-18 to 2026-11-24)

| Directory | Topic |
| --- | --- |
| `feat-linux-libstdcxx/` | libstdc++ for all C++ on linux |
| `feat-winarm-gaps/` | Windows on ARM gaps after release 11 |
| `feat-zig-libs/`, `feat-zig-libs-universe/` | The `zig-*` libraries of libs-zig-pixi on Windows |
| `docs-backlog-hygiene/` | The record-only items of the backlog; the menu answers D1 to D12 |
| `chore-env-ci/`, `fix-rzig-quick/`, `fix-verify-scripts/`, `test-stress-rows/` | Batch 1 |
| `wave2-build/`, `wave2-compat/`, `wave2-rzig/`, `wave2-licences/`, `wave2-fixes/` | Wave 2 |

### Build 11 (2026-11-10 to 2026-11-18)

| Directory | Topic |
| --- | --- |
| `feat-zig-017/` | The zig 0.17 port |
| `feat-win-zig-binutils/` | Windows' binutils from zig and rzig |
| `feat-win-arm64/` | Windows on ARM |
| `feat-win-variants/` | One variant table for every OS |
| `feat-config-rzig/` | `R CMD config` answered by rzig |
| `feat-extras-group/` | The extras group (cmake) |
| `feat-recommended-packages/` | R's recommended packages as their own package |

### Builds 5 to 10 (2026-09-29 to 2026-11-09)

| Directory | Topic |
| --- | --- |
| `feat-no-host-paths/` | No build-machine paths; a base R that installs without a toolchain |
| `feat-standalone-toolchain/` | R as a base plus toolchain groups, on three channels (phases 0 to 9, pkgconf) |
| `feat-zig-pkg-build/`, `fix-zig-pkg-build-review/` | R installs source packages with zig alone (`rzig build`) |
| `feat-shared-build-runner/`, `feat-tier1-engine/` | The tier-1 build runner inside rzig |
| `feat-shlib-rzig-build/` | `R CMD SHLIB` through `rzig build` |
| `feat-r-home-link-objects/` | rzig's link objects in `R_HOME` |
| `feat-win-link-fixes/`, `fix-r-utf8-manifest/` | Windows link fixes; R's UTF-8 manifest |
| `fix-rzig-baseline-cpu/`, `fix-rzig-follow-ups/` | Baseline CPU for packages; rzig follow-ups |
| `fix-no-build-leftovers/`, `fix-icu-pin/` | No build paths in R's compressed files; the ICU pin |
| `feat-stress-suite/`, `fix-stress-round1/` | The stress suite and its first round |
| `chore-ci-tiers/`, `chore-deps-ci-checks/`, `chore-lock-and-ci-refresh/`, `chore-relock-flang-rt-10/` | The CI tiers, CI checks and lock updates |

### Milestones 1 to 8 (2026-07 to 2026-09)

| Directory | Topic |
| --- | --- |
| `feat-initial-setup/` | The first design: R built with zig and pixi |
| `feat-zig-build/` | Milestone 5: R built by `zig build` alone. The root `PLAN.md` and `TODO.md` are symlinks to this directory's |
| `feat-prefix-publish/` | Publishing to prefix.dev; the self-hosted CI fleet (decommissioned 2026-09-19) |
| `feat-legacy-retirement/` | Milestone 7: the autoconf and gnuwin32 builds retired |
| `feat-cross-platform-standardization/` | Milestone 8: the same build on every platform |
| `consolidation/` | One direction for the zig, pixi and conda-forge projects; flang with zig (phase 2) |
| `feat-wheel-minimal/` | The `minimal` variant and the Python wheel |

## A new record

1. Make `.github/devdocs/<branch>/PLAN.md`.
2. Start with the goal, the base commit and the date.
3. Keep a `## Decisions` table (the question, the options, the choice,
   the reason, who decided and when) and a `## Findings` list (one fact
   per entry, with its evidence: the command, the run id or the
   `file:line`). Tag a fact **V** verified, **I** inferred or **A**
   assumption.
4. Record the tests that ran and where, and list what is not verified.
5. Add the directory to this page.
