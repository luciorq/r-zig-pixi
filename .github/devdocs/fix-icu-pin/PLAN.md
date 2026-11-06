# fix-icu-pin — r-zig-build's host pins icu below 79

**Merged (2026-11-04, #28); floor added (2026-11-06, #40).** The pin
went into `_9`, published as `_9` on 2026-11-05 (build.yaml dispatch 41942729382 on main, CONDA_PUBLISH set for it and deleted after the check): r-zig-slim `_9` depends on
`icu >=78.3,<79.0a0` on all five subdirs. With `<79` alone, main's
next conda builds took the 2022 icu-70 stack, so #40 made the pin
`icu 78.*` ("Follow-up: a floor too"), with no bump: `_9`'s build
strings are unchanged. Lift both bounds as "Lifting it" says.

**Status (2026-10-31).** Branch fix-icu-pin, from main at d11dee1 (the
merge of feat-shared-build-runner, PR #27). One change: the host of
recipe.yaml's r-zig-build staging output, which r-zig-slim inherits,
says `icu <79`, with a comment in the style of the libdeflate pin.
Checked by real conda builds on all five subdirs (see "Tested"). The
hosted conda-package legs are UNVERIFIED until this PR's CI runs; the
PR carries the labels full-ci and upstream-zig.

**Build number.** No bump: build 8 stays. The pin changes no build
string. rattler-build's build string is `h<variant hash>_<number>`, and
a version bound in host is not a variant input, so the recipe renders
the same ten `_8` names as d11dee1 on all five subdirs (see "Tested").
universe's `_8` files were built on 2026-10-10 against icu 78.3, and
r-zig-slim's already depends on `icu >=78.3,<79.0a0`, the bound this pin
gives. So main's publish (`--skip-existing`) uploads nothing for this
PR, and conda users lose nothing: the channel already has what the pin
asks for. The next bump (phase 7 of feat-standalone-toolchain, 8 → 9)
carries the pin.

## What

recipe.yaml, the host of the r-zig-build staging output, which
r-zig-slim inherits: `- icu` becomes `- icu <79`. r-zig-slim's run
section's `- icu` stays unpinned; icu's run export sets r-zig-slim's
bound from the host.

## Why

conda-forge published icu 79.1 on 2026-10-22. The r-zig-build staging
host, which r-zig-slim inherits, had an unpinned `icu`, so a build since
then solves icu 79.1, and icu's run export makes r-zig-slim depend on
`icu >=79.1,<80.0a0`.

r-zig-toolchain depends on zig 0.16. conda-forge's zig 0.16.0 needs
libllvm21 21.1.8, which needs libxml2-16, and no libxml2-16 it accepts
allows icu 79 (2.15.3 and 2.15.4 need `icu >=78.3,<79.0a0`). So
r-zig-toolchain's test env, which holds r-zig-slim and zig, cannot be
solved. conda-package stops after r-zig-slim's tests:

```
× Test failed
├─▶ failed to setup test environment
╰─▶ Cannot solve the request because of: The following packages are
    incompatible
```

followed by `r-zig-slim ... would require icu >=79.1,<80.0a0` against
`zig 0.16.0 -> zig_impl -> libllvm21 21.1.8 -> libxml2-16 2.15.x ->
icu >=78.3,<79.0a0`. The same happens to r-zig-compilers' test env once
phase 4 adds that package. The solve is deterministic: rerunning the
job does not help. Every conda-package leg on all five subdirs fails
this way, for d11dee1 and for every layer stacked on it, so main's
push run after any merge would go red, and a publish dispatch would
publish nothing.

With `icu <79` the host solves icu 78.3 again, as for universe's `_8`.

## Tested

The testers' records are under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/final/ (`F` below). The
5-subdir builds used the one-line form `- icu <79` (with a scratch
comment); the merged comment changes no solve and no build string.

| what | result |
|---|---|
| conda-forge, 2026-10-30 and 2026-10-31 02:54Z (`pixi search`; `F/reporter/search.txt`, `F/followup-3-docs/logs/pixi-search.txt`) | icu 79.1 (2026-10-22) is the newest; libxml2-16 2.15.4 (2026-10-08) needs `icu >=78.3,<79.0a0` |
| conda-package without the pin, real builds | fails at the toolchain's (`_8`) or compilers' (`_9`) test env, as above, on all five subdirs: linux-64 (`F/gamma-conda/logs/t9g-pkg-conda-package.log:2957-`; `_8` control `F/followup-2-gamma-conda`, u8c), linux-aarch64 under qemu (`F/followup-1-aarch64-ci/logs/arm/t9u-conda-package.log`), osx-arm64 and osx-64 on omicron (`F/omicron/logs/remote/c9/conda-package.log`, `c9x/`), win-64 on kappa (`F/kappa/logs/t9-conda.log`) |
| `_8` + the pin, real builds (d11dee1 or 951675f + `icu <79`, `pixi run --frozen -e pkg conda-package`) | rc 0 on all five subdirs; both packages pass their tests; slim's run export `icu >=78.3,<79.0a0`. The names are exactly the ten `_8` files on universe: linux-64 hb0f4dca_8 / hc48ad4c_8 (`F/followup-2-gamma-conda`), linux-aarch64 he8cfe8b_8 / h7d89bf6_8 (`F/followup-2-aarch64-ci`), osx-arm64 h41cfa24_8 / h3e6e5e3_8 and osx-64 he0379dc_8 / h86d195b_8 (`F/followup-2-omicron`), win-64 h9490d1a_8 / hbceaa80_8, with the PATH-shim consume step (`F/followup-2-kappa`) |
| `_9` (phases 4 to 7 and win-link-fixes) + the pin, real builds | the four packages build, pass their tests and pass conda-consume on all five subdirs; the build strings are those of the unpinned render (next row) |
| rattler-build 0.76.1 `--render-only`, the stacked `_9` trees with no pin, `icu <79`, `icu 78.*` and this text (`F/followup-3-docs`, R1; this text's final wording again on T9, the `_9` tree, 2026-10-31: 5/5) | 40/40 rc 0; on each subdir all four give the same strings: linux-64 slim hb0f4dca, compilers and build-tools h9276ec7, toolchain hdc6fa2d; linux-aarch64 he8cfe8b / h54b5fbe / ha1671ba; osx-64 he0379dc / hd71bc05 / hbd7205e; osx-arm64 h41cfa24 / h3c217e4 / h80fa0fb; win-64 h9490d1a / h5f95ccc / h98fa296 (all `_9`) |
| `pixi run --frozen -e pkg rattler-build build --render-only`, this branch and d11dee1, 5 subdirs (2026-10-31) | 10/10 rc 0; both give the same ten `_8` names as above; the rendered staging host has `icu <79` |
| this branch, `pixi run --frozen -e pkg conda-package`, linux-64 (gamma, pixi 0.81.0, 2026-10-31) | rc 0: hb0f4dca_8 and hc48ad4c_8, both tests pass, icu run export `>=78.3,<79.0a0` (below) |
| placement before utf8: a merge rehearsal of this pin, utf8, the six stacked merges and PR 1 and PR 2 (`F/followup-3-docs`, R7) | every merge and patch is clean; the final main is TF plus this hunk |

### linux-64 build of this text

On gamma, 2026-10-31 09:21 to 09:27Z, as CI's conda-package leg runs
it: a copy of this branch's files, pixi 0.81.0 (CI's pin), fresh
caches, `pixi install --frozen -e pkg`, then
`pixi run --frozen -e pkg conda-package`. Log:
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/queue3/fix/logs/build-conda-package.log.

- rc 0 in 263 s; pixi.lock unchanged (fbb64b7b…).
- Host: icu 78.3 (py310h44b86e0_2).
- Archives: `r-zig-slim-4.6.1-hb0f4dca_8.conda` and
  `r-zig-toolchain-4.6.1-hc48ad4c_8.conda`, the linux-64 names on
  universe.
- Tests: "all tests passed!" for both packages. r-zig-slim prints
  `conda R OK` and `base package without the toolchain: OK`;
  r-zig-toolchain prints its 10 `toolchain: ...: OK` lines.
- r-zig-slim's run export: `icu >=78.3,<79.0a0 (RE of [host: icu])`.
  Its index.json depends on `icu` and `icu >=78.3,<79.0a0`, as
  universe's `_8` does.

## Known, not this fix: a rebuilt `_8` is not universe's `_8`

A `_8` built today has newer run-export floors than universe's `_8`
under the same name (libcurl, libexpat, libharfbuzz, llvm-openmp, and
pango renamed libpango), and its libR differs: PRs #25 to #27 landed
with no bump. `--skip-existing` keeps universe's files, so nothing
changes for users. Do not delete a `_8` file from universe before `_9`
is published: the next publishing main run would upload today's
content under the old name (`F/followup-2-gamma-conda`, "Content vs
universe `_8`").

## Follow-up: a floor too, `icu 78.*` (2026-11-06)

After the queue merged, every conda-package leg of main's push runs
failed again (run 42126061546, after PR #39; `_9` was already
published, with `icu >=78.3,<79.0a0` and `cairo >=1.18.6`, and is
fine). The host solve had changed: with `icu <79`, rattler's solver
(resolvo) took the 2022 stack, cairo 1.16.0, pango 1.50.10, harfbuzz
5.2.0, glib 2.72.1 and icu 70.1. r-zig-slim's run export became
`icu >=70.1,<71.0a0`, which clashes with zig's libxml2-16 (icu 78)
in r-zig-compilers' test env, as icu 79 did. `libdeflate <1.26` alone
gives the same stack. micromamba solves the same specs to today's
stack (cairo 1.18.6, harfbuzz 15.0.0, icu 78.3); rattler does not.

The fix is a floor as well as the ceiling: `- icu 78.*`. With it,
rattler (pixi exec, the same specs) takes cairo 1.18.6, pango 1.58.2,
harfbuzz 15.0.0, glib 2.90.0 and icu 78.3 on linux-64, linux-aarch64
and win-64; on osx-arm64 the `<79` solve takes glib 2.72.1 too. A
version bound in host is not a variant input, so the build strings
stay those of `_9`, and CONDA_PUBLISH is unset: nothing is uploaded.

## Lifting it

Lift the pin (both bounds) when conda-forge's libxml2-16, the one libllvm21 needs, is
built against icu 79, so that zig 0.16 (or the zig the recipe then
uses) installs beside icu 79. Check with:

```sh
pixi search -c conda-forge -p linux-64 libxml2-16   # its icu dependency
```

Lift it with a build-number bump. Without one the build strings stay
the same, `--skip-existing` skips them, and the channel never gets the
icu 79 build (as with libdeflate's pin, fix-stress-round1 S19).
