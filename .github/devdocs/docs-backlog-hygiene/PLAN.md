# docs-backlog-hygiene — records batch B1 of build 12

Goal: close the record-only items of the build-12 backlog
(chore-release-12/BACKLOG.md): Q2, Q3, Q18, Q21, Q22, Q23, M12, and
record the 2026-11-23 menu answers (D1-D12). Branch from main 3395a08.

## Decisions

The user answered the 1b menu on 2026-11-23 with every default (D1-D12).
B-rows are this batch's own defaults.

| # | question | chosen | reason |
|---|---|---|---|
| D1 (M1) | Rtools45 x64 tree fallback for hdf5r, gsl, igraph/scran, Rsamtools on win-64 | no; wait for libs-zig-pixi slice 2 | one path; the zig-* libraries replace it (user, default) |
| D2 (M2) | wheel size from libcurl→libpsl→ICU | accept for now | no pin or rebuild for 14 MiB (user, default) |
| D3 (M3) | arrow `heavy@linux` | keep | (user, default) |
| D4 (M4) | libstdc++ headers in the compilers group (L4/L5 a) | keep as is | headers are needed only to compile (user, default) |
| D5 (M5) | feat-zig-libs ZL5-ZL23 defaults | keep | (user, default) |
| D6 (M6) | extras Help pages and PATH order | keep | (user, default) |
| D7 (M7) | release job / PyPI in build 12 | no; conda only | parity gate not met (user, default) |
| D8 (M8) | package names | keep | (user, default) |
| D9 (M9) | zig cache pre-seeding, sharing, zig hash in key | later | (user, default) |
| D10 (M10) | CI speed menu | the cheap ones, in chore-env-ci | (user, default) |
| D11 (M11) | stale ideas | closed as won't-do or watch; source records annotated where found (Findings I2) | (user, default) |
| D12 (M12) | licence completeness | checked here | (user, default) |
| B1 | where R_ZIG_FALLBACK_SOFT is documented (Q23) | README.md, next to `R_ZIG_PKG_BUILDER` | the only user-facing place naming R_ZIG_* variables; windows-11-arm stress has run since W12 (a) |
| B2 | stale boxes (Q3): tick or annotate | annotate with a dated "Closed"/"Won't do"/"Watch" note and the evidence; tick only N8 | ticking old plan copies would claim checks nobody ran |
| B3 | M12 fix | no recipe change in this batch | the gap is recipe metadata, not a missing file, and needs a package build (Not verified) |

## Findings

- **F1 V (Q21). `_11` macOS packages: minos 13.0.** On delta, the
  universe `.conda` files (sha256 equal to repodata's: osx-64 r-zig-slim
  h9825941_11 `ed00beb0…`, osx-arm64 ha6b6fea_11 `e3e1f9c9…`) unzipped
  and untarred; a Mach-O load-command scan (LC_BUILD_VERSION 0x32,
  LC_VERSION_MIN_MACOSX 0x24, fat archives included) gives, per
  package: r-zig-slim 22 Mach-O files, all `platform 1 (macOS), minos
  13.0.0` (e.g. lib/R/bin/exec/R, lib/R/lib/libR.dylib);
  r-zig-recommended 13 files, all 13.0.0; r-zig-compilers and
  r-zig-toolchain hold no Mach-O file. No LC_VERSION_MIN_MACOSX. index.json
  depends on `__osx >=13.0` on both subdirs.
- **F2 I (D11). M11 sources.** Annotated "Won't do"/"Watch" in place: A6
  TMB precompile and A5 build root and A4 `-lmsvcrt`
  (feat-standalone-toolchain/TODO.md), G10 MinGW `-l`, B11 installer, B12
  manuals (feat-initial-setup/TODO.md status note), F15 BLAS route
  (chore-release-11/PLAN.md), F16/E5 r-base (CXX-STDLIB.md, Deferred),
  E6 pixi_build_zig (consolidation/PLAN.md, phase 4), G8 Falcon
  (feat-no-host-paths/PLAN.md, testing rule). No open source line found
  for A10 Windows `-lc++` (dropped in phase 6, TODO.md "`-lc++` and
  `link_libcpp` dropped", ticked), D13 pak README line, E4 WinRT (avoided
  through zig-abseil, backlog A17; stress/results/2026-10-08-round2.md
  Z12 is a dated result, left as is); these are closed by this record
  only. D11 CFG no-op stays "watch" until CI7 runs the magick SVG smoke.
- **F3 V (Q22). The wheel toolchain mechanism is settled**, both ways at
  once: group wheels write into the shared `r_zig/R/lib/R/bin/toolchain/`
  (scripts/make-wheel.py:19-40, :82-90), rzig discovers zig at startup
  (zigbuild/tools/rzig/find_zig.zig:1-16). Closed in
  feat-no-host-paths/PLAN.md.
- **F4 V (Q2).** build-r 45219775112 attempt 2 succeeded 2026-11-23
  (`gh run view`: attempt 2, success, windows-11-arm / default success).
  #50's head bd4c9ee: build-r 44735387872 (33 jobs, 32 success, 1
  skipped `packaging`), upstream-zig 44735388684 (6/6 success); #49's
  merge f668295 is an ancestor of bd4c9ee. `git worktree list`: main
  checkout plus the six batch worktrees.
- **F5 V (Q3, chore-lock-and-ci-refresh).** 45219775112's ubuntu-latest
  / default log: Ubuntu 26.04.1, image 20261111.635; "programs
  started:", "TLS trust verified", "standalone base verified
  relocatable (linux/slim)", 24 "compiled package verified", "glibc
  ceiling verified: worst 2.17".
- **F6 I (M12). Licence completeness.**
  - Standalone zig/ (compilers group): LICENSES/ziglang/ is the ziglang
    0.17.1 wheel's dist-info/licenses, 16 files: zig's MIT LICENSE,
    libc++, libc++abi, libunwind, libtsan (LLVM's Apache-2.0 WITH
    LLVM-exception text), musl, glibc, mingw-w64, FreeBSD, wasi
    (zigbuild/toolchain/build.zig:821-842; checked on delta). This is
    every licence file upstream ships. The LLVM code in the zig binary
    has the same text as libcxx/LICENSE.TXT. Apple's SDK headers carry
    their notices inline (of 574 files in include/any-darwin-any, 546
    have a copyright line and 455 the APSL); libSystem.tbd is a stub
    with no notice. NetBSD and OpenBSD: 1562 of 1881 files in
    include/generic-{netbsd,openbsd} carry a copyright inline, and zig
    ships no separate text (`grep -rlI` counts on delta). Nothing is
    trivially missing; adding texts zig does not ship would mean writing
    them ourselves.
  - flang/: from conda-meta via installLicenses (LLVM text, phase 6);
    it ships only inside the compilers group, next to zig/'s MIT text,
    so phase 6's "flang/ alone needs zig's MIT text" does not arise.
  - **Gap, not fixed: no conda package has `info/licenses/`.**
    recipe/recipe.yaml has no `license_file` (grep: none). The `_11`
    osx packages (slim, compilers, toolchain, recommended) have no
    info/licenses. R's texts are in the payload (lib/R/doc/COPYING,
    lib/R/share/licenses/), and so are Windows' cairo and pkgconf texts,
    but rzig's own licence (the repo's MIT LICENSE) and zig's MIT text
    (compiler_rt, linked into every binary zig links) are in no conda
    package. Proposed fix for the release batch: `about.license_file`
    with R's COPYING, the repo's LICENSE and zig's LICENSE text, then a
    conda-package run.

- **F7 V (review, Q3).** #30-#33 (phases 4-6, SHLIB) merged 2026-11-05
  with no labels and their own runs cancelled or skipped (`gh run list
  --commit <head>`: build-r 41937914565, 41938121376, 41938285875,
  41938396305 cancelled; upstream-zig skipped). The standalone TODO.md
  closing notes say so now; the evidence that the code passes is the
  later full tier 44735387872 and upstream-zig 44735388684.
- **F8 V (review, Q2/C2).** Worktree backups: archive/wt-backups-2026-11-18/
  (the dirty removed worktrees) and archive/wt-backups-2026-11-23/feat-userland/
  (archived, then removed at the user's request, 2026-11-23); recorded
  in feat-winarm-gaps/PLAN.md C2.

## Tests

| what | where | result |
|---|---|---|
| Q21 download, sha256 against repodata, Mach-O scan of 8 `_11` osx packages | delta (~/rz/q21) | minos 13.0.0 on every Mach-O file (F1) |
| ziglang 0.17.1 wheel licence inventory (`pixi run fetch-zig`) | delta | 16 licence files (F6) |
| CI facts | `gh run view`/`gh pr list`, read-only | F4, F5 |

| review: independent Mach-O re-scan (own LC_BUILD_VERSION parser) of the 8 extracted `_11` osx packages | delta (~/rz/q21) | slim 22 and recommended 13 files per subdir, all minos 13.0.0; compilers/toolchain 0; no info/licenses in osx-arm64 slim |
| review: universe repodata, r-zig-* build numbers | `curl` repodata (linux-64, osx-arm64, win-arm64) | `_9`, `_10`, `_11` present (win-arm64: `_11` only) |
| review: cited run ids, PR merge dates/labels, file:line citations | `gh`, read-only; worktree | as recorded, except F7 (fixed) |

No build ran: the batch changes Markdown only.

## Not verified

- M12 fix (license_file): needs a recipe change and a conda-package run;
  left to the release or env batch (F6).
- Linux and Windows `_11` packages were not opened; the missing
  info/licenses is inferred from the recipe (no `license_file` key).
- The baseline R build of main on delta (~/rz/base-build.log) was not
  used. It did not fail: its dlamch.f lines are zig build printing
  flang's `-Wfolding-exception` warning under "failed command:"; the
  log ends "zig-built R OK" and EXIT=0 (reviewer, 2026-11-23).

## Backlog items closed

Q2, Q3, Q18 (`.github/devdocs/RELEASE.md`), Q21, Q22, Q23, M12
(findings; fix deferred), M1-M12 recorded as D1-D12.
