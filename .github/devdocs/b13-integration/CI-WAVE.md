# Build 13 CI wave

One wave, after the build13 pull request exists. Every input name below
was checked against `.github/workflows/stress.yaml` and `build.yaml` on
branch build13 (2026-11-24). Hosted jobs need the repository variable
`ENABLE_HOSTED_JOBS=true` (the user's). Read every result table row by
row (stress: each leg's `report.md`; build: each leg's log), never the
job status alone.

## 0. Before the wave (kappa, 2026-11-24, integration group C)

Two Windows blockers found on kappa with the integrated worktree; every
Windows leg (build, stress, toolchain-free legs alike) hits them:

- `zig build fetch` panics on Windows after extracting:
  `@panic("TODO implement dirSetTimestamps windows")` from
  zigbuild/tools/fetch.zig:255 (setMtimes, b13-build D3; zig 0.17.1's
  std has no Windows `Dir.setTimestamps`). No `.r-zig-patches` stamp is
  written, so zig-build.sh extracts again and fails on every run.
- verify-tree on Windows: build.zig's Rcmd_environ line now ends
  `;${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin` (b13-rzig's need), but
  scripts/verify-tree.sh:390 still expects the old line ("the build
  tools' lines are not build.zig's").

Fix both (their owners' files) and re-check on kappa first.

## 1. build-r (full tier) and upstream-zig, on the pull request

The user sets the labels on the pull request:

- `upstream-zig`: upstream-zig.yaml.
- Full tier, one of:
  - (a, recommended) no `full-ci` label; dispatch build.yaml on the
    branch with the CI9 runner. A dispatch runs the full tier (21 legs,
    with the new windows-latest openblas leg, the Windows wheel legs and
    conda-package), so CI9 and the full tier are one run:

        gh workflow run build.yaml --ref build13 -f linux_runner=ubuntu-26.04

  - (b) the `full-ci` label. Then CI9 needs no run of its own:
    ubuntu-latest is ubuntu-26.04 already (b13-env-ci F13); read the
    "Image: ubuntu-26.04" line of a linux-64 job.

What to read: the windows-latest openblas leg (build, verify-tree, smoke;
b13-build M-7), the Windows minimal legs' wheel step (b13-env-ci L2),
gen-config (runs on the push: configure-only.sh and rzig/build.zig are in
its paths; captures equal the vendored configs but CC_VER/FC_VER,
b13-build F5), conda-package's r-zig-tcltk (b13-recipe), toolchain.yaml's
Windows legs with the trimmed usr/bin (b13-build D14).

## 2. stress: four dispatches

stress.yaml takes `zig`, `channel`, `rtools_libs` and `packages` per
run, not per OS, so these are the fewest runs that cover the list.
(Build 14 removed the `rtools_libs` input with the Rtools45 tree:
b14-rhtslib U3. The S1/S3 commands below are build 13's.)

S1. Every OS, every row, both distributions, trace, libs smoke. Covers
CI1 (full Windows), CI2 (macOS), CI4's "with the Rtools45 tree" half,
CI5 (RcppParallel:system-tbb, mlpack, lwgeom on linux), CI6 (g1 with
trace: Rcpp and rstan's `rzig build: R CMD SHLIB, tier 1`), CI7 (magick's
SVG smoke on windows-11-arm) and b13-stress's rows (protolite, zigcmake,
the smoke files, arrow and arrow:source on macos-15-intel,
`--libs-smoke`):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["ubuntu-latest","ubuntu-24.04-arm","macos-latest","macos-15-intel","windows-latest","windows-11-arm"]' \
      -f packages=all -f distribution=both -f channel=local -f trace=true -f libs_smoke=main

S2. CI3, upstream zig on ubuntu and macOS (tree):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["ubuntu-latest","ubuntu-24.04-arm","macos-latest","macos-15-intel"]' \
      -f packages=all -f distribution=tree -f zig=upstream

S3. CI4's other half, windows-11-arm without the Rtools45 tree
(`rtools_libs=false` passes `--no-rtools-libs`; b13-stress N3's
`no_rtools_libs` is this input):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["windows-11-arm"]' -f packages=all -f distribution=both \
      -f rtools_libs=false -f trace=true -f libs_smoke=main

S4. CI13, the published packages on windows-11-arm (b13-hosts F20):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["windows-11-arm"]' -f packages=g3 -f distribution=conda -f channel=universe

Not expressible, left out: CI5's "full and openblas variants" (the
stress task runs the slim compile tree only, b13-env-ci).

Optional: `gh workflow run win-binary.yaml --ref build13` (M-24 on hosted
Windows; the decision "keep source" does not depend on it).

## 3. What to read

- S1 and S3 windows-11-arm: diff the two `report.md` tables (CI4); S1's
  logs print `stress: Rtools45 tree extracted with <tool>` (b13-hosts
  N2, CI8's R-C9).
- S1 every leg: the libs smoke line; on linux and macOS terra's two TBB
  checks fail by design (the script is written for Windows, b13-stress).
- S1: protolite on windows-11-arm (M-3), arrow on macos-15-intel (M-6),
  rstan's smoke log on Windows (the compiler's `-std=c++1y` error, M-2),
  the `copies` field (M-10), zigcmake on Windows (M-9).
- S4: report.md's Fallback line ends `rzig uses it (R_ZIG_FALLBACK_SOFT)`
  (stress.R), r-zig-slim `*_12` from universe.
- Expects change only from these run ids (b13-stress D8).

## 4. Finding the runs

    gh run list --workflow stress.yaml --branch build13 --limit 4
    gh run list --workflow build.yaml --branch build13 --limit 2
    gh run download <run-id> --dir T/stress-<run-id>
