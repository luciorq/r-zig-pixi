# chore-relock-flang-rt-10 — re-lock on flang-pixi's first aligned release

**Status (2026-10-07).** Branch chore-relock-flang-rt-10, from main at
6cc4ba6 (the merge of PR #13). Not committed. It changes pixi.toml (the
flang pins and their comments), pixi.lock (only flang-zig, lld-zig and
flang-rt-zig move), recipe/recipe.yaml (the same pins) and adds this file.
FLANG_PIXI_HANDOFF.md is the main checkout's copy (sections 7 to 10; main
had up to 6). build.zig, zigbuild/, scripts/ and toolchain/ are
untouched. The recipe's build number stays 4 (PR #14
bumps it to 5).

## What flang-pixi did

On 2026-10-07 flang-pixi published lld-zig `_5`, flang-zig `_6` and
flang-rt-zig `_10` on every subdir (one build number per package per
release, FLANG_PIXI_HANDOFF.md §7 and §9). They are still zig 0.16.0
(conda-forge zig_impl build 20) and LLVM 23.1.1. Then it deleted every
older build from `universe`. Our lock (sha256 e9f17d31...) named the
deleted files (flang-rt-zig `_9`, win-64 `_4`; flang-zig `_1`, `_2`,
`_5`; lld-zig `_0`, `_1`, `_4`), so `pixi install --locked` failed on a
machine without them in its cache: CI on PRs #14 and #15 failed on
macOS and Windows (404 on the old flang-zig).

Its zig 0.17 builds will come at the next numbers: lld-zig 6, flang-zig
7, flang-rt-zig 11. Nothing with a lower number will be published again.

## Pins

- pixi.toml `[dependencies]` and `[feature.minimal.dependencies]`:
  `flang-zig = { version = "==23.1.1", build-number = "==6" }`, lld-zig
  `==5`, flang-rt-zig `==10`. The win-64 override (`>=4`) is gone; one
  pin covers every platform.
- recipe/recipe.yaml: the same builds, as `flang-rt-zig ==23.1.1 *_10`
  etc. (the build string's `_N` suffix), in the staging output's build
  (all three) and host (flang-rt-zig), and in r-zig-toolchain's run (all
  three), so users of the next published toolchain get the 0.16 flang it
  was built and tested with. Not the bracket form
  `[build_number="==10"]`: rattler-build copies it as written into
  r-zig-toolchain's depends, which conda's default solver and micromamba
  cannot parse (below, "The recipe's pin form").
- Why an upper bound: the lock and the recipe stay on the 0.16 builds
  when the 0.17 builds appear; we move by changing the pins.
- Why `==N` and not `>=N,<N+1`: pixi 0.81.0 rejects a range in
  `build-number` (`">=10,<11"`: "expected EOF"), and rattler-build
  0.76.1 rejects it in `[build_number=...]` ("invalid build number spec:
  expected EOF"). Both take one comparison. Build numbers are integers,
  so `==10` is the same set. pixi.toml keeps `build-number`, as flang-pixi
  asks (handoff §7): only pixi reads it. The recipe uses the build string
  (above), the one form every conda client reads.
- Why lld-zig is listed: flang-zig 6 depends on `lld-zig ==23.1.1`, any
  build, so without a pin a 0.17-built lld-zig 6 could join a 0.16
  flang-zig. Nothing of ours runs lld (zig links), so this only keeps the
  closure on one release.
- Why `==23.1.1`: a build number means something only with its version
  (handoff §7). pixi warns that a bare `23.1.1` is ambiguous.

## Lock diff

`pixi lock` (no update) after the pixi.toml change. Old sha256
e9f17d315fd52ccf58db6a9840379e787e5c51ad80406982f907faa2dc1b9513, new
a7d3dcecb5592fbe165e8476af400c96f6800268d19a7e59dd7357a554154f79.

Compared per environment and platform with python3 + yaml: in pkg,
default, full, openblas, full-openblas (5 platforms) and minimal (4)
exactly three records change, flang-zig, lld-zig and flang-rt-zig, to the
new builds; package counts are unchanged; wheel is unchanged. No other
record or metadata changed. The new records' sha256 match universe's
repodata.json. minimal still has none of the graphics stack, libglib,
libffi, libgcc-ng or libstdcxx-ng (62 packages on each linux, 55 on each
macOS). llvm-openmp stays 23.1.2 (conda-forge has 23.1.3 now; the recipe
solves fresh and gets it).

## What changed in the packages

Downloaded from universe (sha256 checked against repodata.json) for
linux-64, linux-aarch64, osx-64, osx-arm64 and win-64, and compared with
the file lists of the builds our lock named (flang-pixi
docs/19-file-lists, generated from those builds; linux-64 also from the
local rattler cache).

- flang-rt-zig 10: unix file lists identical to build 9. win-64 drops
  `libflang_rt.runtime.{static,static_dbg,dynamic,dynamic_dbg}.a`
  (copies of the same static build) and keeps
  `Library/lib/clang/23/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a`.
  It still ships the MinGW CRT snapshot, including the `libatomic.a` and
  `libomp.dll.a` shims. Depends: `llvm-openmp >=23` everywhere (was bare
  `llvm-openmp`, plus `>=23.1.1` on win-64; win-64 now also `>=23.1.2`),
  `__glibc >=2.17,<3.0.a0` on linux (linux-aarch64 had none),
  `__osx >=11.0` on macOS.
- flang-zig 6: adds `bin/flang-compile.cfg` (`Library/bin` on Windows);
  nothing removed. linux-64's `flang.cfg` is unchanged. Depends on
  `lld-zig ==23.1.1` (any build); linux-aarch64 gains the glibc floor.
- lld-zig 5: same files; linux-aarch64 gains the glibc floor.

## What our code uses

Only `libflang_rt.runtime.a`, found as `<flang resource dir>/lib/*/`
(`$CONDA/lib/clang/*/lib/*` in build.zig findFlangRt and
configure-only.sh; `flang -print-resource-dir` in rzig's flang_rt.zig
and toolchain/zig-cc, zig-cxx), and `-lflang_rt.runtime` in FLIBS
(vendored subst.txt, build.zig's Windows Makeconf, verify-tree.sh,
contract-test.sh, recipe/test-toolchain.R). It exists in every new
package. Nothing names the dropped Windows archives, the CRT snapshot or
the libatomic/libomp shims; OpenMP links use conda-forge's libomp
(`libomp.lib`/`libomp.dll` on Windows). `use omp_lib` finds the modules
through flang's own flang.cfg. No code change was needed.

The osx-arm64 vendored configs record `FC_VER` with a flang-pixi commit
from an older flang-zig build. It is a version string only; left as is.

## Checks on linux-64

- `pixi install --locked` for default, minimal, full, openblas,
  full-openblas, pkg and wheel: all installed.
- `pixi run --locked rzig-test`: 42/42 tests; parity 0 failed.
- With the new packages: `use omp_lib` and OpenMP directives compiled by
  flang, linked by zig against the static runtime and libomp, two
  threads; a Fortran shared library linked by zig exports 3 symbols, its
  own.
- The recipe's specs: `rattler-build build --render-only --with-solve`
  renders on all five platforms, but does not solve the staging output.
  The same spec strings in a scratch recipe solve on all five
  (flang-zig 6, lld-zig 5, flang-rt-zig 10).

## Open questions

- Settled with flang-pixi (2026-10-07): r-zig-toolchain's run pins are
  exact, so these builds must stay on universe while a published
  r-zig-toolchain pins them. flang-pixi now keeps lld-zig 5, flang-zig 6
  and flang-rt-zig 10 as a retained set (scripts/build-alignment.json
  `retain`; its prune script skips them after 0.17's 6/7/11 land). Tell
  flang-pixi when no published r-zig-toolchain pins them any more.
- The recipe's pin form needs flang-pixi's build strings to end in
  `_<build number>`; flang-pixi recorded `zig_<hash>_<N>` as a contract
  (its docs/14). From flang-zig 7, flang-zig pins its lld-zig build
  itself, and our explicit lld-zig pin can go.

## The recipe's pin form (review, 2026-10-07)

The first version used `'flang-zig ==23.1.1[build_number="==6"]'` in the
recipe. rattler-build copies a run requirement into the package's depends
as written. On a local channel with builds 9, 10 and 11: pixi,
rattler-build and conda's classic solver read the bracket form; conda's
default solver (conda-libmamba-solver 26.7.0, libmamba 2.9.0) stops with
"Could not parse spec", and micromamba 2.9.0 rejects `==` as a build
number operator (with another operator it finds no flang-zig at all). The
published build 4 has bare names, so this would have broken conda and
mamba users. `flang-zig ==23.1.1 *_6` works in all of them, picks 10/6/5
and excludes 11/7/6.

## Tested

Lock sha256 a7d3dcec... before and after on every machine. osx-64 ran
on omicron's platforms-sed copy (83ba912c...), whose osx-64 records are
identical to a7d3dcec's in all 7 environments. Every run used
conda-forge zig 0.16.0 build 20; no upstream-zig leg.

- linux-64 (dev machine): all 19 steps passed. rzig-test 42/42, parity
  0 failed; build, verify-tree, smoke, contract (quadprog through
  zig-fc), check (67 OK, the usual tools-Ex NOTE), hermetic,
  verify-package; minimal build, verify-tree, verify-package; wheel,
  wheel-test; full build, verify-tree, smoke; openblas build, smoke;
  conda-package (both outputs' tests passed). No NEEDED names flang. A
  Fortran package with internal I/O holds 86 `_FortranAio*` and loads
  under `env -i`. Not run: full-openblas, verify-package on full and
  openblas.
- linux-aarch64 (CI): not run locally.
- osx-arm64 (omicron): install, rzig-test 42/42, build, verify-tree,
  smoke, contract, verify-package (`use omp_lib` on 2 threads); minimal
  build, verify-tree, verify-package; conda-package (both outputs' tests
  passed). Not run: check, hermetic, full, openblas, wheel.
- osx-64 under Rosetta (omicron): build, verify-tree, smoke, contract,
  verify-package passed. Not run: rzig-test, minimal, conda-package,
  check, full, openblas, wheel.
- Falcon: no Killed: 9, exit 137 or quarantine on omicron. No platform
  was left to CI.
- win-64 (kappa): install, rzig-test (29 pass, 13 linux-only skips),
  build, verify-tree, smoke, contract, check (all examples, 67 OK),
  verify-package (`use omp_lib` on 2 threads), conda-package (both
  outputs' tests passed). No DLL exports a runtime symbol; the archive
  marks all 1421 `_FortranA*` with `-exclude-symbols`. Not run: full,
  openblas, hermetic.
- conda-package on all three machines solved flang-zig 6, lld-zig 5,
  flang-rt-zig 10 and llvm-openmp 23.1.3; the build strings stay `_4`.
  The runs above used the bracket pins.
- After the switch to `*_N` (linux-64): conda-package passed again (3.4
  min, both outputs' tests); r-zig-toolchain's depends read
  `flang-zig ==23.1.1 *_6`, `lld-zig ==23.1.1 *_5`,
  `flang-rt-zig ==23.1.1 *_10`. From a local channel holding the two
  packages, plus universe and conda-forge, `micromamba create --dry-run`
  (2.9) and `conda create --dry-run --solver libmamba` both install
  r-zig-toolchain with flang-zig 6, lld-zig 5, flang-rt-zig 10 and zig
  0.16.0 build 20.
- CI (build.yaml on the PR): not run yet.
