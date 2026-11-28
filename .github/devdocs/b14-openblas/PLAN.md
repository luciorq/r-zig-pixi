# b14-openblas: the Windows openblas crash at ar.ols

Build 14, track b14-openblas, worktree build14 (uncommitted), 2026-11-26.
Follows b13-fixes F14/D13 and chore-release-13 F1: in the Windows
openblas leg, stats-Ex.R dies with 0xC0000005 at
`ar.ols(diff(log(EuStockMarkets)), order.max = 6, demean = FALSE,
intercept = TRUE)` on `__archspec=1=x86_64_v4` runners only. Publish run
45858899338, job 140060790975 (AMD EPYC 9V45, Zen 5): OpenBLAS prints
`Core: Haswell` and the call crashes as is, with one thread and with
`OPENBLAS_CORETYPE=Haswell`.

Tags: V verified, I inferred, A assumption.

## Cause

OpenBLAS 0.3.34 bug (upstream OpenMathLib/OpenBLAS #6013, fixed on
`develop` by PRs #6014 and #6027, in no release yet). conda-forge's
win-64 `libopenblas 0.3.34 pthreads_h952cde7_2` has it. Not caused by the
zig build of R, the Rblas forwarder or stack alignment.

## Findings

- **F1 (V) The crash is OpenBLAS 0.3.34's Zen 4/5 block sizes overrunning
  the Haswell DGEMM kernel's Windows stack buffer.**
  - 0.3.34 `kernel/setparam-ref.c`, end of `init_parameter()`, outside
    every per-core `#ifdef`: if the vendor is AuthenticAMD, L2 (cpuid
    0x80000006) is 1024 KB, L3 is a multiple of 32 MB and CPUID.7:EBX
    bit 16 (AVX512F) is set, it sets `dgemm_p = 512, dgemm_q = 512`
    (also s/c/z). It checks the host CPU, not the selected core, so it
    changes the Haswell and Zen tables too.
  - `kernel/x86_64/dgemm_kernel_4x8_haswell.S` (Haswell and Zen DGEMM
    kernel) copies the B panel to a stack buffer, 96 bytes per k. Under
    the Windows ABI the buffer is `128*8*12+512` bytes (k <= 128), and
    `param.h` sets `DGEMM_DEFAULT_Q 128` there for that reason. With
    Q = 512 a call with k > 128 writes past the frame.
  - Disassembly of the lock's `openblas.dll` (sha256 of the .conda
    138056f6..., the lock's): 11 copies of the block (one per x86_64 core
    table), each `cmp $0x68747541,%ebx` (AuthenticAMD), `xor $0x400`
    (L2 = 1024), `test $0x10000,%ebx` (AVX512F), then stores
    `0x200`/`0x200` (dgemm P, Q 512). The conda-forge 0.3.33 DLL
    (`pthreads_h877e47f_0`) has none.
  - Upstream #6013: same configuration (conda-forge clang-cl + flang,
    DYNAMIC_ARCH, NO_AVX512, NUM_THREADS=128), GitHub windows-latest,
    EPYC 9V45 and 9V74 with AVX-512 exposed: crash in
    `dgemm_kernel_HASWELL+0x6ea6` (the `ret`), registers and return
    address holding doubles; `dsyrk('U','T', n=55, k)` crashes from
    k = 160 on the 9V45; 0.3.27 to 0.3.33 pass; EPYC 7763, 9V74 without
    AVX-512 and Intel Xeon 8573C pass.
  - It explains all observations: CPU-dependent with the same kernel,
    independent of `OPENBLAS_CORETYPE=Haswell` and of threads, Intel
    AVX-512 (icelake) passing (b13-fixes F14 gap), x86_64_v3 runners
    (Zen 3, no AVX-512) passing, internal-BLAS flavors passing.
- **F2 (V) The calls ar.ols makes (R 4.6.2, src/library/stats/R/ar.R
  333-410), and which library serves them in the Windows openblas flavor.**
  X is 1853 x 25 at order 6 (EuStockMarkets 1860 x 4, diff, embed).
  | R call | routine | library |
  |---|---|---|
  | `crossprod(X)` | dsyrk n=25, k=1853 | OpenBLAS |
  | `qr(XX)`, `qr(varE)` in det() | LINPACK dqrdc2 (R.dll) -> dnrm2, ddot, daxpy, dscal | R.dll, BLAS from OpenBLAS |
  | `solve(XX)` | La_solve: dgesv, dgetrf/dgetrf2, dlaswp, dgecon, dlange (Rlapack.dll) -> dgemm, dtrsm, idamax, dscal, ... | Rlapack.dll (R's LAPACK, flang), BLAS from OpenBLAS |
  | `Y %*% X %*% P` | dgemm (k=1853, then k=25) | OpenBLAS |
  | `tcrossprod(A, X)` | dgemm (k=25) | OpenBLAS |
  | `tcrossprod(E)` | dsyrk n=4, k=1853 | OpenBLAS |
  | `P %x% varE` | R code | - |
  - On Windows the openblas flavor keeps R's Rlapack.dll (b13-build D8):
    build.zig links Rlapack.dll, R.dll and the lapack module against
    Rblas.dll's import library, which forwards to openblas.dll. So LAPACK
    is R's, BLAS is OpenBLAS's.
  - Every `crossprod(X)` and `Y %*% X` has k = 1853 > 128, so the crash
    is expected in the first of them whose B panel is wide enough to
    pass the buffer (the kernel copies up to 12 columns, 96 bytes per k),
    at a low model order. Section 1 of the step names the call. (I)
- **F3 (V) `OPENBLAS_L2_SIZE` does not work as a workaround on Windows.**
  `common.h` 0.3.34, Windows branch: `readenv_atoi` is
  `return readenv(p,env) ? 0 : atoi(p);`, inverted: when the variable is
  set it returns 0, when it is unset it returns `atoi` of an
  uninitialised buffer. The DLL matches: `GetEnvironmentVariableA("OPENBLAS_L2_SIZE", buf, 0x104)`,
  nonzero result -> cpuid path, zero -> `atoi(buf)`. Upstream #6021's
  `OPENBLAS_L2_SIZE=2048` workaround is from linux. Not reported upstream
  yet (N2).
- **F4 (I) `OPENBLAS_CORETYPE=Sandybridge` or `Prescott` likely avoids
  the crash.** Their DGEMM kernels (dgemm_kernel_4x8_sandy.S,
  gemm_kernel_4x4_sse3.S) and the Sandybridge ZGEMM kernel
  (zgemm_kernel_1x4_nehalem.S) have no stack B buffer (no
  `L_BUFFER_SIZE`); the block still sets Q = 512 but nothing overruns.
  Haswell, Zen and SkylakeX (= Haswell under NO_AVX512) use the Haswell
  kernel. The new diagnostics step checks this.
- **F5 (V) No env-file fix inside the R tree is possible.** OpenBLAS
  reads its variables in `gotoblas_init`, a load-time constructor
  (driver/others/memory.c), and openblas.dll loads with R.dll (static
  imports through Rblas.dll), before R reads etc/Renviron. Rblas.dll's
  own initialisation also runs after openblas.dll's (a dependency
  initialises first). A variable must be in the environment before
  Rterm.exe starts.
- **F6 (V) kappa cannot reproduce it.** kappa is an Intel i7-8850H (no
  AVX-512, not AMD); the block needs an AMD CPU with AVX-512. delta is an
  Intel i9-10900X (AVX-512, Intel): no reproduction either. kappa has no
  cdb.exe.
- **F7 (V) conda-forge has no fixed build.** Newest win-64 libopenblas:
  0.3.34 `pthreads_h952cde7_2` / `openmp_h4bb5e94_2` (2026-09-11), whose
  patches are 0001-0003 (test_fork, win-arm64). conda-forge
  openblas-feedstock #196 (same report) is open. Latest OpenBLAS release:
  0.3.34. 0.3.33 `pthreads_h877e47f_0` exists for win-64.
- **F8 (I) Users are not affected through a published package.** The
  openblas flavor is not packaged (chore-release-13 F1). A user who
  builds the Windows openblas flavor from this repo on a Zen 4/5 CPU with
  AVX-512 gets the crash in any dsyrk/dgemm with an inner dimension over
  about 130.

## Decisions

| id | decision | options | chosen | reason | who, date |
|---|---|---|---|---|---|
| D1 | The diagnostics step (build-r.yaml, "openblas crash diagnostics") | (a) ★ replace the three ar.ols runs and the event-log query with: each call alone (inputs built with matprod "internal"), cdb at the fault, five core types plus one thread and `OPENBLAS_L2_SIZE`, libopenblas 0.3.33 in a copy of the tree, a summary table; (b) keep the step and add cdb only | (a) | one failed run then confirms F1 (which calls crash, the k threshold, the overwritten frame), F3, F4 and the 0.3.33 fix at once. The event-log query showed nothing (WER logs no Application Error on the runner) | default, 2026-11-26 |
| D2 | How cdb is run | (a) ★ `cdb -g -G -o -c "<cmds>;q" Rterm.exe --file=...`; (b) `-cf` with `sxe -c ... av` | (a) | (a) is the form #6013's reporter used on windows-latest and got a dump (bodono/scs-python win_dense_probe.yml); not testable on kappa (no cdb) | default, 2026-11-26 |
| D3 | Run Rterm.exe, not Rscript.exe | (a) ★ Rterm.exe `--no-echo --vanilla --file=`; (b) Rscript.exe | (a) | Rscript.exe starts Rterm.exe as a child process (src/unix/Rscript.c, `_WIN32`), so cdb on Rscript sees only the parent | default, 2026-11-26 |
| D4 | No fix in the repo now | (a) ★ diagnostics only, fix proposed (Proposals); (b) `OPENBLAS_CORETYPE` in CI env (outside this track's step); (c) patch the exported `gotoblas` table from Rblas.dll at load | (a) | the fix is a dependency change (pixi.toml, the user's) or an upstream build; (c) depends on the private struct layout and is a workaround in code, against simplicity first; F5 rules out etc/Renviron | default, 2026-11-26 |

| U1 | Fix for the Windows openblas leg | (A) ★ pin 0.3.33 on win-64; (B) `OPENBLAS_CORETYPE=Sandybridge` in CI; (C) wait for conda-forge | (A), applied: pixi.toml `[feature.openblas.target.win-64.dependencies]`, `pixi lock`: pixi.lock cf4b3220532c -> fcae3a49b0e2, only win-64 `openblas` and `full-openblas` envs changed (libopenblas 0.3.34 pthreads_h952cde7_2 -> 0.3.33 pthreads_h877e47f_0, openblas -> 0.3.33 pthreads_h4a7f399_0), `pixi lock --check` ok. Remove the pin when a fixed build exists | the user: "Recommended is fine" | user, 2026-11-26 |
| U2 | Upstream follow-up | (a) ★ comment on openblas-feedstock#196 (P2); (b) also report N2 | (a): the comment is drafted below; posting it is the user's (outward-facing) | the user | user, 2026-11-26 |

## Proposals (for the user)

- P1 (done, U1) Pin the openblas feature to 0.3.33 on win-64 until a fixed build
  exists, in pixi.toml:
  ```toml
  [feature.openblas.target.win-64.dependencies]
  libopenblas = "0.3.33.*"
  openblas = "0.3.33.*"
  ```
  then `pixi lock`. The diagnostics step's section 4 tests 0.3.33 on the
  failing runner first.
- P2 Upstream: comment on conda-forge/openblas-feedstock#196 asking for a
  build 3 with PRs #6014 and #6027 (d3d4c6cd, e5a25b7a) as patches.
- N2 Upstream: report F3 (Windows `readenv_atoi` inverted) to OpenBLAS.

## Tests

| where | what | result |
|---|---|---|
| gamma | download libopenblas 0.3.34 `pthreads_h952cde7_2` (sha256 138056f6..., equal to pixi.lock) and 0.3.33 `pthreads_h877e47f_0`; read info/recipe/build.bat; objdump the DLLs | clang-cl + flang 21, DYNAMIC_ARCH, NO_AVX512=1, NUM_THREADS=128; 0.3.34: 11 Zen 4/5 blocks, `gotoblas` and `gotoblas_HASWELL` exported; 0.3.33: none (F1); L2 env read inverted (F3) |
| gamma | OpenBLAS 0.3.34 source (release tarball): setparam-ref.c, dynamic.c, memory.c, common.h, dgemm_kernel_4x8_haswell.S, KERNEL.* | F1, F3, F4, F5 |
| gamma | job log 140060790975 | `-mcpu baseline` for every zig compile, flang without -march; CPU EPYC 9V45; three cases 0xC0000005 |
| kappa (Windows PowerShell 5.1, `$ErrorActionPreference = 'stop'` as the runner sets) | the new step script, extracted from build-r.yaml, against a stand-in tree (conda-forge r-base via pixi exec, copied to a fake `dist\slim-openblas\R-4.6.2-zig\Library\lib\R`), scratch dir and pixi cache in %USERPROFILE%\rz-openblas (removed after) | parses; finds Rterm.exe; 11 single calls, 15 core-type cases, one thread, L2: exit 0x00000000 "ok"; no cdb on kappa, branch prints "no x64 cdb.exe"; pixi exec finds the 0.3.33 openblas.dll, the tree copy runs 3 cases; summary table; exit 0. Not run: pwsh 7, cdb, a real crash |

## What the next failing Windows openblas run shows

Expected if F1 holds (not yet seen):
- section 1: `ar.ols`, `dsyrk crossprod(X) k=1853`, `dsyrk k=160`,
  `dsyrk k=512`, `dsyrk tcrossprod(E) k=1853` and `dgemm Y %*% X k=1853`
  exit 0xC0000005; `dsyrk k=128`, `dgemm A %*% t(X) k=25`, `qr`, `solve`
  and `chol` exit 0.
- section 2: cdb stops in `openblas!dgemm_kernel_HASWELL` (near +0x6ea6,
  or +0x16e), with doubles in the return address slot.
- section 3: Haswell, Zen, SkylakeX, one thread and `OPENBLAS_L2_SIZE`
  crash; Sandybridge and Prescott pass (F4).
- section 4: the 0.3.33 copy passes.
A different pattern refutes F1 and the cdb stack names the real fault.

## Not covered

- No run on a Zen 4/5 AVX-512 machine: kappa and delta are Intel (F6).
- The step's cdb branch is untested (no cdb on kappa).
- full-openblas on Windows has no CI leg; same DLL, same exposure.
