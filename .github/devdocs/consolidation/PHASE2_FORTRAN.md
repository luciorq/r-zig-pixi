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

## osx-arm64 — DONE 2026-09-19 (omicron, macOS 26.4.1, native)

| step | result |
|---|---|
| `pixi run build` (slim, flang 23.1.1, -O2) | PASS |
| `pixi run smoke` | PASS |
| `pixi run contract` (Rcpp, data.table+OpenMP, minqa incl. package Fortran via `$(FLIBS)`, pak, ps) | PASS |
| `pixi run check` (Examples/Specific/Reg) — **lapack.R at -O2** | PASS (the test that caught gfortran's zgesdd miscompile) |
| `pixi run verify-package` (relocatable standalone bundle) | PASS |
| full variant `-e full` build / smoke / contract (tcltk, readline, NLS, jpeg/tiff) | PASS |

flang emits `-Wfolding-failure` warnings on loessf.f / cmplx.f /
dlapack.f (`exp(real(kind=8)) cannot be folded on host`); zig prints a
step's captured stderr under a "failed command" heading even though the
step exits 0 — harmless, but easy to misread in a log.

**Cost**: the osx-arm64 env closure grows by ~1.5 GiB (flang-zig +
lld-zig + flang-rt-zig); the r-zig-slim package's run deps carry the
same pair so users compile packages with the compiler R was built with
(CRAN's rule). gfortran's cctools/tapi/sigtool deps drop out.

**Still gfortran**: osx-64, linux-aarch64, win-64 — next in that order
per PLAN.md (win-64 is the MinGW-ABI case only flang-pixi covers).
