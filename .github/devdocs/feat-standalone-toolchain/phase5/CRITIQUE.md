# Phase 5 critiques, verified against the code (amender, read-only)

Inputs: `phase5/critique-code.md` (Cc1-Cc11) and `phase5/critique-goals.md`
(Cg1-Cg10) on `phase5/planner/PHASE5-IMPLEMENTATION.md`. Each point was
checked against the worktree `wt/feat-standalone-phase5` (main d11dee1
plus phase 4 and SHLIB, uncommitted) and the unpacked linux-64 wheel in
the main checkout (`build/zig-upstream/ziglang-0.16.0-linux-64`). The
amended plan is `phase5/critic/PHASE5-IMPLEMENTATION.md`, where each
amendment carries its tag. Nothing in the worktree changed; pixi.lock's
sha256 still starts with fbb64b7ba4e31e45.

Verdicts: 20 accepted, 1 accepted in part (Cc2), none rejected.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 5 keeps build 8, as phase 4, SHLIB routing and phase 6
do, and main publishes nothing until the user sets the repository
variable `CONDA_PUBLISH` after phase 7's bump merges (PLAN.md, B14's
amendment). Where this critique says phase 5 takes 11 (or names phase 4's 9
and SHLIB's 10), read: the number stays 8, and phase 5 publishes with
phase 7's bump, at the number after universe's newest (B14 a).
Two open points were added (S, T). Like A-R, each is answered with its
recommended option, per the user's standing instruction.

## Code critique

| # | point | checked | verdict | where it landed |
|---|---|---|---|---|
| Cc1 | zig-toolchain.sh decides on "R_TOOLCHAIN_PREFIX set", build.zig on `prefix_is_env` | env.sh:68 makes R_TOOLCHAIN_PREFIX a general override. unpack-toolchain.sh:32 and package-standalone.sh:43 also handle a non-env override. build.zig:129 uses `samePhysicalDir`. A non-env override gets no `-Dziglang` and then hits the plan's addFail step | **accepted** | Section 3, zig-toolchain.sh: a `same_dir "$TOOLCHAIN_PREFIX" "$CONDA_PREFIX"` test. The helper is vendor-libs.sh's existing `resolved()` (which already covers Windows: `cygpath -m -l`, lower-cased), moved into env.sh and shared. The critic's snippet had no Windows branch, so the move replaces it. The `rm -rf` guard is unchanged. Step 2 adds tests for a non-env override and for an env spelled differently. Open point J is amended, with (b) "R_TOOLCHAIN_PREFIX is conda-only" kept as the rejected alternative |
| Cc2 | Batched greps under `set -euo pipefail` exit non-zero when nothing matches | env.sh:3 sets pipefail. Today's code ignores the status through `< <(find ... -exec grep)` (verify-toolchain.sh:159) | **accepted in part** | Every batched grep runs inside a process substitution and ends in `\|\| true`. The new positive test runs on a clean tree. **Not taken:** `xargs -r`. Each batched call keeps the plan's `[ -s ]` guard instead, because it works whatever macOS xargs does with `-r`. GNU xargs gives its child /dev/null as stdin, so an unguarded empty run of sha256sum would print a hash line for "-". The guard covers that |
| Cc3 | The `want` compile (`"$ZIG" cc -mcpu=baseline`) runs in env.sh's shell | verify-bundle.sh:965 runs it in that shell, and env.sh:175-176 exports ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR | **accepted** | All three IR compiles run under one `env -i`. A review grep checks every zig and compiler call site. The Windows dry runs (996, 1017) stay outside, since they run no zig |
| Cc4 | The build pass runs while the first pass's VERIFY_DIR still exists, and the success line comes too early | The trap at :120-121 removes the directory only at exit. The last line (:1985) prints "verified" before any nested pass | **accepted** | `cmp` decides which pass follows, right after scenario 2's extraction. The final line names the pass. Then `rm -rf "$VERIFY_DIR"; trap - EXIT; exec bash "$0" build`. No top-level `cd` exists, so `$0` stays valid. Section 1's disk figure is corrected |
| Cc5 | LLVM's licence text is in the wheel | `dist-info/licenses/ziglang/lib/libcxx/LICENSE.TXT` begins "The LLVM Project is under the Apache License v2.0 with LLVM Exceptions". METADATA has `License-Expression: MIT` | **accepted** (no code) | Risk 8 and open point C reworded |
| Cc6 | `! -name SOURCES` matches at any depth; `FNR == NR` misfires when files.txt is empty; `sed` treats `&` as special | All three are standard find/awk/sed behaviour. Today's code skips only the top SOURCES (`case "$rel" in SOURCES\|LICENSES/*`) | **accepted** | `! -path ./SOURCES`, `FILENAME == ARGV[1]`, and an awk prefix replace them. Two negative tests added |
| Cc7 | The `-i` build-path grep over 360 MB, not under `LC_ALL=C`, and the 30-minute timeout | verify-toolchain.sh:151 sets `icase=(-i)` on Windows. toolchain.yaml:35 sets `timeout-minutes: 30` | **accepted** | `LC_ALL=C` on the batched grep. The cost: a non-ASCII user name's case is no longer folded, which loses at most a listed note, since copies are never failed. Windows step times are recorded, and the timeout is raised only if the measurements call for it |
| Cc8 | Move only the zig binary aside, not the directory | find_zig.zig:40-42 and `inDir` test only `<rzig dir>/zig/zig[.exe]` | **accepted** | `mv "$TC/zig/zig$exe"`. Open point E's reason and the section 6 table updated |
| Cc9 | The repository is public, so artifact storage is not billed | `gh repo view` returns `"visibility":"PUBLIC"` | **accepted** | Risk 6 and open point I record it. The optional `compression-level: 0` became **open point T**, answered (a): left for later, with no workflow step change in phase 5 |
| Cc10 | wheel.zig: METADATA's body after the blank line, three Project-URLs, the `source:` line parsed rather than copied, `\r` | The headers end at line 31 of METADATA, and the body has a line starting `License` (line 80). There are three `Project-URL:` lines | **accepted** | The parser stops at the first blank line. Fixtures added. The `source:` line is parsed into `conda.Source`, so writeSources writes every `source:` line. All three readers trim `\r` |
| Cc11 | The first C++ compile: `-o` on Windows, where zig's cache lives, and the warm-cache label | verify-bundle.sh:314: base_env sets `LOCALAPPDATA=$home` | **accepted** | `-o x.so` / `-o x.dll`. The cache is read at `$home/.cache/zig` (unix) or `$home/zig` (Windows). The build pass's line is labelled warm |

## Goals critique

| # | point | checked | verdict | where it landed |
|---|---|---|---|---|
| Cg1 | The fourth pass's fallback is chosen in advance; it re-runs zig-independent blocks | Scenario 1 (:376, :483) and the no-zig check (:1966) pass only `base_env`, never `zig_env`. The plan's risk 2 and F named (b) as the fallback | **accepted** | "(b) is the fallback" is removed. Any later change goes to the user as a menu with the times measured per leg. The optional guard became **open point S**, answered (a): the build pass skips scenario 1 and the no-zig check |
| Cg2 | Open point C's reason cites B33, which covers only the base's runtime files | PLAN.md:1663 "B33. Licences and sources for the base's runtime files". zig's lib has licence texts for libcxx, libcxxabi, libunwind and the libcs, but none for darwin, netbsd or openbsd | **accepted** | C's reason fixed. A "Later and future checks" menu item added for the groups' licence completeness, to go with phase 6's licence review |
| Cg3 | L's kappa test runs after the conda and build-number chains and can still change rzig | Plan step 6 ran it after step 5 | **accepted** | New step **3b** on kappa, before step 5. If it leads to L (b), step 3 grows the mapping and step 5 runs once. The build number stays 11 |
| Cg4 | On Windows, TODO's "RZIG_PRINT_ARGV shows TC/zig/zig" is replaced by another check, not met | The unix-only `rz = $ZIG` check is at verify-bundle.sh:1081-1083. find_zig's `inDir` joins with `\` on Windows | **accepted** | One assertion on every OS: the first argv word, with `\` turned into `/`, matched by `grep -qixF` against `$pass_zig`. Q (a) is kept; rzig is unchanged |
| Cg5 | The planner settled E (and H) itself where the two surveys differed | Plan E's reason says so | **accepted** (record) | E's and H's records name both surveys' recommendations and the option taken |
| Cg6 | zig/ costs download, unpack and network on legs that never read it | build-r.yaml and stress.yaml unpack the toolchain artifact, and compile-tree leaves zig/ out (C12) | **accepted** (record) | No change in phase 5. README's dev note, unpack times for each kind of leg, and a later menu |
| Cg7 | The conda boundary is decided in two places | Same finding as Cc1 | **accepted**, merged with Cc1 | One rule (real-path equality) in both places. build.zig decides what is installed; each comment cites the other |
| Cg8 | The new verify-toolchain mechanisms could skip checks silently on BSD or MSYS; steps 1-2 need the skeptical review | A missed candidate grep skips that file's closure check | **accepted** | A positive check that `zig/zig` is among the binaries counted. The binary count before and after is compared on gamma, omicron and kappa. The skeptical review now covers steps 1-2 |
| Cg9 | After phase 5, both toolchain artifacts per platform carry the same zig | TC/zig is always the pinned wheel | **accepted** (record) | Risk 6, the record, and a later menu |
| Cg10 | Rule hygiene: osx-64 copy's lock, pixi.toml comment edits, D6's verbatim answer | The rules as given | **accepted** | Ownership notes in section 1. Step 5 checks the lock sha and runs `pixi lock --check`. The records section keeps D6's verbatim answer |

## Points the critics confirmed (no amendment needed)

- The B30 boundary. conda and PyPI get no TC/zig: recipe.yaml excludes
  `{zig,...}/**` and make-wheel.py reads only `usr/`.
- find_zig is unchanged (B2/B34).
- The shared runner key normalises `\`, so each extraction place gets one
  runner.
- The `cmp` skip on the upstream legs.
- D6's rename (windows.zig:58-59) works for both zigs.
- The build number. recipe.yaml:174 is `number: 10` (SHLIB's), so phase
  5 takes **11** (B14 a). The task's "(11)" is that result.
- groups.zig's new format arguments `.{ p.r, p.name, p.zig, archive,
  p.zig }` match the head line and the new standalone line (checked
  against groups.zig:113-115).
