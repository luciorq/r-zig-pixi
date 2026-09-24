# Phase 2 — Fortran convergence on flang-zig, platform by platform

Tracks PLAN.md's Phase 2: replace gfortran with flang-pixi's zig-built
`flang-zig` + `flang-rt-zig` (LLVM 23.1.1, `universe` channel) on each
platform that lacks a usable conda-forge flang, in value order. The bar
before a platform's default flips (flang-pixi docs/11): build +
`check`'s lapack.R + the full contract suite, **all at -O2**.

## Mechanism (landed with osx-arm64, 2026-09-19)

The Fortran compiler is a *dependency* decision, not a build.zig
platform table:

- **build.zig** probes `$CONDA/bin/flang` (`Library/bin/flang.exe` on
  Windows) and sets `ctx.fc` (`FortranCompiler`), printing
  `r-zig: Fortran compiler = <fc> (<platform>)` once per configure.
  `fortranOne` compiles with `flang -fpic -O2 -module-dir` or
  `gfortran -fpic -O{1,2} -J`; the macOS `-O1` cap now applies to
  gfortran only. `findFlangRt` globs `lib/clang/*/lib/*/
  libflang_rt.runtime.a` (the subdir is `darwin` on macOS, a triple on
  linux). `linkFortranRt` links `flang_rt.runtime` **statically** on
  every platform (what linux-64 always got; explicit now because
  flang-rt-zig ships a `.dylib` beside the `.a`) plus zig's own libc++ on
  macOS so libR/libRblas/libRlapack stay self-contained.
- **pixi.toml** adds `https://prefix.dev/universe` after conda-forge and
  swaps the platform's `[target.<plat>.dependencies]` from `gfortran` to
  `flang-zig` + `flang-rt-zig`. **recipe.yaml** mirrors the split in
  build, host and run (`target_platform == "osx-arm64"` selectors; the
  `conda-package` task passes `-c https://prefix.dev/universe`).
- **Vendored config** for the platform is regenerated from a real
  `pixi run configure` + `gen-subst.sh` with flang in the env. The diff
  against the gfortran capture is the expected set: FC/FC_VER/FLIBS/
  FLIBS_IN_SO (`-L<conda>/lib/clang/23/lib/darwin -lflang_rt.runtime
  -lm`), FFLAGS/FCFLAGS/SAFE_FFLAGS `-O1 → -O2`, R_SYSTEM_ABI
  `gfortran → ClassicFlang`, F_VISIBILITY and the Fortran OpenMP flags
  emptied, `SUPPORT_OPENMP` undefined in config.h (same as linux-64's
  flang capture; R core's own OpenMP pragmas only, packages unaffected —
  SHLIB_OPENMP_CFLAGS is unchanged). Incidental: without gfortran's
  package the env no longer carries conda's cctools, so STRIP/NM/LD/
  OTOOL/LIPO capture Apple's `/usr/bin` tools and FOUNDATION_LIBS gains
  `-framework Foundation`; build.zig consumes none of those.

## Follow-ups from the flang-pixi handoff review (same day)

`FLANG_PIXI_HANDOFF.md` (written by the flang-pixi side) reviewed this
wiring; three of its findings were acted on before merge:

- **LLVM major no longer baked into Makeconf.** gen-subst.sh now turns
  the captured runtime dir (`<conda>/lib/clang/<major>/lib/<subdir>`)
  into `@ZR_FLANGRT_DIR@`, which build.zig fills from `findFlangRt` at
  build time (and refuses a flang-captured config in a gfortran env).
  Applied to the linux-x86_64 and osx-arm64 captures. Verified: the
  linux-64 Makeconf resolves to the env's real `clang/22` dir and minqa
  links through it (contract test).
- **Fortran OpenMP restored on osx-arm64.** The first flang capture had
  empty `SHLIB_OPENMP_FFLAGS`/`R_OPENMP_FFLAGS`/`OPENMP_FCFLAGS` and
  `SUPPORT_OPENMP` undefined — not because the omp_lib module was
  missing (flang-rt-zig build 4 ships it) but because configure's probe
  *links* with flang, and on macOS the flang driver cannot find libSystem
  without `SDKROOT` ("ld: library 'System' not found", reproduced on
  omicron). configure-only.sh now exports `SDKROOT` from `xcrun` for
  flang captures on macOS; the re-capture carries `-fopenmp` in all
  three and `SUPPORT_OPENMP 1`, parity with the gfortran capture.
  linux-64 (conda-forge flang) keeps them empty: its llvm-openmp ships
  no `omp_lib.mod`.
- **Windows import-stub step hardened** (`pipefail` + export-count
  check) after an MSYS fork flake produced an empty stub and surfaced as
  a link storm two jobs later — unrelated to flang, found by this PR's
  CI.

Noted, not acted on: package `.so`s linked via `$(FLIBS)` on macOS may
pick `libflang_rt.runtime.dylib` (beside the `.a`) — fine in a pixi env
(run dep), a relocatability caveat for user-built packages; the Windows
consume test will need the universe channel once win-64 converges;
`zig build` does not track the Fortran compiler binary in its cache, so
every compiler swap starts with `rm -rf build/zig-cache` (all
validations here did).

## osx-arm64 — DONE 2026-09-19 (omicron, macOS 26.4.1, native)

| step | result |
|---|---|
| `pixi run build` (slim, flang 23.1.1, -O2) | PASS |
| `pixi run smoke` | PASS |
| `pixi run contract` (Rcpp, data.table+OpenMP, minqa incl. package Fortran via `$(FLIBS)`, pak, ps) | PASS |
| `pixi run check` (Examples/Specific/Reg) — **lapack.R at -O2** | PASS (the test that caught gfortran's zgesdd miscompile) |
| `pixi run verify-package` (relocatable standalone bundle) | PASS |
| full variant `-e full` build / smoke / contract (tcltk, readline, NLS, jpeg/tiff) | PASS |
| hosted CI (PR #7, run 35511725052, 2026-09-20): macos-latest default + full legs, conda-package/osx-arm64 — all 16 jobs green | PASS |

flang emits `-Wfolding-failure` warnings on loessf.f / cmplx.f /
dlapack.f (`exp(real(kind=8)) cannot be folded on host`); zig prints a
step's captured stderr under a "failed command" heading even though the
step exits 0 — harmless, but easy to misread in a log.

**Cost**: the osx-arm64 env closure grows by ~1.5 GiB (flang-zig +
lld-zig + flang-rt-zig); the r-zig-slim package's run deps carry the
same pair so users compile packages with the compiler R was built with
(CRAN's rule). gfortran's cctools/tapi/sigtool deps drop out.

## win-64 — DONE 2026-09-20 (kappa, Windows 11 22621, native)

flang-pixi's MinGW-ABI flang-zig replaces conda-forge's MinGW gfortran
(gcc_impl_win-64). Specific to Windows:

- `[target.win-64.dependencies]`: `flang-zig`, `flang-rt-zig` with
  `build-number >= 4` (the build that ships omp_lib.mod and the
  libatomic/libomp driver shims; it requires llvm-openmp >= 23.1.1, which
  an unconstrained re-solve dodged by keeping the locked 22.1.8 and
  picking build 2), and `binutils_impl_win-64` kept explicitly — it used
  to arrive through gfortran and provides the `x86_64-w64-mingw32-nm` /
  `-dlltool` that build.zig's import-stub steps run.
- build.zig's Windows path: `FC`/`FC_VER` substituted per `ctx.fc`
  (flang.exe stays in its package dir — it reads flang.cfg relative to
  itself); new `FLIBS` substitution for Makeconf.win = `-L<resource dir>
  -lflang_rt.runtime -lc++` (R CMD SHLIB appends `$(FLIBS)` to every
  package link with Fortran sources and links through SHLIB_LD, the
  zig-cc shim, never the Fortran driver — so the runtime *and* libc++,
  which the MinGW archive needs and PE cannot leave unresolved, must be
  spelled out; gfortran kept the historical empty FLIBS). `link_libcpp`
  on Windows too; `-fpic` dropped there (flang reports it unused).
- recipe.yaml mirrors it (`win` selectors); the CI Windows consume test
  now passes the universe channel to `pixi init`.

| step | result |
|---|---|
| `pixi run build` (flang 23.1.1 MinGW, -O2) | PASS |
| `pixi run smoke` | PASS |
| `pixi run contract` (minqa's Fortran compiled by flang, linked via FLIBS through the zig-cc shim) | PASS |
| lapack.R at -O2 (`Rterm --vanilla < tests/lapack.R`, `tools::Rdiff` vs lapack.Rout.save — Windows has no wired `check` step) | PASS, Rdiff status 0 |
| `pixi run verify-package` (relocatable bundle) | PASS |
| hosted CI (windows-latest + conda-package/win-64) | pending PR |

Trap for the record: cleaning `build/zig-cache` on kappa *while* the
install stage was still running raced zig's first compiler_rt build
("sub-compilation of compiler_rt failed: UnableToWriteArchive"); a clean
re-run passed. Not needed for this swap anyway — zig keys Run-step
caches on argv, and `gfortran` → `flang` (plus the dropped `-fpic`)
changes every Fortran command line.

## osx-64 — DONE 2026-09-20 (omicron under Rosetta 2, x86_64 env)

Same mechanism as osx-arm64, no new code: `[target.osx-64.dependencies]`
swapped to `flang-zig` + `flang-rt-zig` (build 5; resource subdir is
`darwin` here too), recipe selectors collapsed to `osx or win` (only
linux-aarch64 keeps gfortran), vendored osx-x86_64 configs regenerated.
The capture ran in a copy of the tree with `platforms = ["osx-64"]` so
pixi installs the Intel packages under Rosetta (it warns, then falls
back); `pixi install --frozen`, since the narrowed manifest no longer
matches the lock's platform list. Everything in the chain ran as
genuine x86_64 binaries (flang, zig, the built R). Diff vs the gfortran
capture: the expected Fortran keys, the cctools tool paths that leave
with gfortran, and `R_PLATFORM`/`R_OS` now reading darwin25.4.0
(omicron's macOS 26) instead of the macos-15 runner's darwin24.6.0 —
informational strings only; gen-config.yaml on macos-15-intel can
re-capture them on real Intel hardware whenever wanted.

| step (all -O2) | result |
|---|---|
| `pixi run build` (slim) | PASS |
| `pixi run smoke` | PASS |
| `pixi run contract` | PASS |
| `pixi run check` incl. lapack.R | PASS |
| `pixi run verify-package` | PASS |

(Re-captured on the real macos-15-intel runner via gen-config.yaml
right after: identical apart from `R_PLATFORM`/`R_OS` = darwin24.6.0 and
the runner's JDK path in JAVA_HOME, i.e. the pre-Phase-2 capture's own
values — that runner capture is what is vendored now.)

## linux-aarch64 — DONE 2026-09-20 (PR #9, all 16 CI legs green)

The last gfortran platform. No interactive hardware: flang-pixi's
linux-aarch64 flang-zig is cross-built from linux-64 and smoke-tested
on the hosted arm runner, and that runner is the only place r-zig-pixi
can capture or validate. `[target.linux-aarch64.dependencies]` swapped
to `flang-zig` + `flang-rt-zig` (build 5; runtime under
`lib/clang/23/lib/aarch64-unknown-linux-gnu`, driver cfg with the conda
sysroot), the whole gcc/gfortran/binutils closure leaves the lock, the
recipe is now "conda-forge flang on linux-64, flang-zig on every other
subdir" with no gfortran anywhere. Configs captured by dispatching
gen-config.yaml on the branch (run 35529091202) and vendoring its
`config-linux-arm64-{slim,full}` artifacts; the diff against the
gfortran capture is the expected Fortran set only (FLIBS and
R_LD_LIBRARY_PATH tokenised, R_SYSTEM_ABI ClassicFlang, OpenMP Fortran
flags intact, the sysroot dirs gone, `LD` now /usr/bin/ld since conda's
binutils left — unused by build.zig).

Validated by PR #9's ubuntu-24.04-arm legs (build / smoke / contract /
check incl. lapack.R at -O2, verify-package with the glibc-2.17
ceiling) and conda-package/linux-aarch64 — all green, merged.

## Phase 2 complete (2026-09-20)

Every platform's R Fortran is LLVM flang 23.1.1 — conda-forge's on
linux-64, flang-pixi's zig-built flang-zig on the other four — at -O2.
gfortran is gone from pixi.toml and recipe.yaml; the macOS -O1 cap is
history. Per-platform bar (build, lapack.R, contract suite, all -O2)
met on: linux-64 (validation worktree, 2026-09-19), osx-arm64 (omicron
native), win-64 (kappa native), osx-64 (omicron Rosetta), linux-aarch64
(hosted arm runner via CI). Hosted CI green on all 16 legs for every
step.

**Publishing caveat found at the end**: three merges' "publish =
success" steps shipped nothing — the build string never changed and
`--skip-existing` skipped every existing filename, so the channel kept
the gfortran-built packages (osx-arm64/win-64 files dated 2026-08-15,
osx-64/linux-aarch64 2026-09-19). Verified via repodata `depends`. Fix:
recipe build number 1 → 2 (PR #10); its merge publish uploaded
`*_2.conda` for all five subdirs on 2026-09-24 (verified via repodata:
flang-zig deps on the four, conda-forge flang on linux-64). The `_1` files should
be deleted from the channel (conda-channel-delete) so no solver picks
the gfortran builds by build-number order confusion. Lesson for the
policy comment in recipe.yaml: any change to run: deps is a bump.

Before the next platform read `FLANG_PIXI_HANDOFF.md` (2026-09-19, from the
flang-pixi side): review of this wiring, the hard-coded `lib/clang/<major>`
in FLIBS, the lost `SHLIB_OPENMP_FFLAGS`, the Windows/binutils/channel
caveats and the win-arm64 CRT gaps.
