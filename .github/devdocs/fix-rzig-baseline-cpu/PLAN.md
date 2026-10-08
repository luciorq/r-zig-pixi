# fix-rzig-baseline-cpu — packages compile for the baseline CPU on every OS

**Status (2026-10-06).** Branch fix-rzig-baseline-cpu, from main at
6cc4ba6 (the merge of chore-lock-and-ci-refresh, PR #13). Tested on
linux-64, osx-arm64 and win-64 (see "Tested"). On osx-64 (omicron,
Rosetta) build and verify-tree passed, and verify-package was stopped
by omicron's CrowdStrike Falcon killing the x86_64 rzig; CI's
macos-15-intel legs cover it. The recipe's build number goes 4 → 5.

## What

rzig, the compilers R_HOME/bin/toolchain holds (zig-cc, zig-cxx, gcc.exe,
g++.exe, and zig-fc's shared links), passes `-mcpu=baseline` to zig on
every OS, right after `-fno-sanitize=undefined`, before the target and the
caller's arguments, and drops the caller's `-mtune=<cpu>`, which zig
would take as the CPU. Two checks hold it: verify-bundle.sh (pixi task
verify-package) compiles with the bundle's C compiler to LLVM IR, with
no flags and with `-mtune=native`, and compares its target-cpu with
zig's baseline, on every OS; verify-tree.sh counts VEX/EVEX (AVX-class)
instructions in R's own x86_64 binaries.

## Why

R itself is compiled for the baseline CPU everywhere (build.zig:
`.cpu_model = .baseline` in all three of its target queries), because its
binaries ship to other machines. Packages are too: binary packages built
in CI, a shared library compiled on a cluster's login node and loaded on
its compute nodes. A package compiled for the compiling machine's own CPU
can die with SIGILL on an older CPU of the same arch.

zig's rule (lib/zig/std/zig/system.zig, resolveTargetQuery, lines
374-383 in 0.16.0; std/Target/Query.zig's `determined_by_arch_os`: "If
CPU Architecture is native, then the CPU model will be native. Otherwise,
it will be baseline."): a target that names its arch resolves to that
arch's baseline CPU; no target means native CPU detection.

rzig before this change:
- linux: `-target <arch>-linux-gnu.2.17` (the glibc floor): baseline.
- macOS: `-target <arch>-native.13.0` (the deployment target): baseline
  (apple-m1 on arm64, core2 on x86_64).
- Windows: no target at all (compiler.zig: `.windows, .other => {}`,
  "zig cc's native Windows target is already x86_64-windows-gnu"), so the
  compiling machine's CPU.

## Evidence (2026-10-06)

Gathered before the change (the task's record), on the test machines:

- kappa (Windows 11, x86_64): a C file compiled to LLVM IR by the slim
  tree's gcc.exe (rzig, no -target) has `"target-cpu"="skylake"`, the
  machine's own CPU; flang's is `"x86-64"`.
- omicron (macOS 26, arm64; osx-64 under Rosetta): rzig's
  `-target aarch64-native.13.0` gives `"apple-m1"` and
  `-target x86_64-native.13.0` gives `"core2"`: both baseline.
- R's own binaries have no instruction on a %ymm or %zmm register
  (objdump -d) on linux-64 and win-64.

Measured on this branch, linux-64:

- A vendored conda library does use them: lib/libdeflate.so.0 of a slim
  tree has 451 instructions on %ymm (its run-time CPU dispatch), so the
  AVX check must leave conda's files out.
- This machine (native CPU skylake-avx512), zig 0.16.0 (conda-forge's),
  target-cpu in the IR of `zig cc <flags> -O2 -S -emit-llvm`:

  | flags | target-cpu |
  |---|---|
  | (none) | skylake-avx512 |
  | `-mcpu=baseline` | x86-64 |
  | `-target x86_64-linux-gnu.2.17` | x86-64 |
  | `-target x86_64-linux-gnu.2.17 -mcpu=baseline` | x86-64 |
  | `-target x86_64-windows-gnu -mcpu=baseline` | x86-64 |
  | `-target x86_64-macos.13.0 -mcpu=baseline` | core2 |
  | `-target aarch64-linux-gnu.2.17 -mcpu=baseline` | generic |
  | `-mcpu=baseline -march=native` | skylake-avx512 (the last wins) |
  | `-mcpu=baseline -mcpu=native` | skylake-avx512 |
  | `-mcpu=native -mcpu=baseline` | x86-64 |
  | `-mcpu=baseline -march=haswell` | haswell |

  So the flag is a no-op where the target already gives the baseline,
  and a package's own `-march`/`-mcpu`, which comes after it, still wins.
- `-mtune` (found in review, measured the same way): zig cc reads it as
  the CPU, as it reads `-mcpu` and `-march`, never as tuning alone, on
  every arch; gcc, clang and flang only schedule for it.

  | flags | target-cpu | tune-cpu |
  |---|---|---|
  | `-mcpu=baseline -mtune=native` | skylake-avx512 | generic |
  | `-target x86_64-linux-gnu.2.17 -mcpu=baseline -mtune=native` | skylake-avx512 | generic |
  | `-target x86_64-windows-gnu -mcpu=baseline -mtune=native` | skylake-avx512 | generic |
  | `-mcpu=baseline -mtune=haswell` | haswell | generic |
  | `-target aarch64-linux-gnu.2.17 -mcpu=baseline -mtune=cortex_a76` | cortex-a76 | |
  | `-target aarch64-macos.13.0 -mcpu=baseline -mtune=apple_m4` | apple-m4 | |
  | `-mcpu=baseline -mtune=generic` | fails: "unknown target CPU 'generic'" | |
  | `-target aarch64-linux-gnu.2.17 -mcpu=baseline -mtune=cortex-a76` | fails (no such zig CPU) | |
  | flang `-mtune=native` | x86-64 | skylake-avx512 |

  Upstream zig 0.16.0 (PyPI's ziglang, `pixi run fetch-zig`) gives the
  same: x86-64, skylake-avx512, haswell, and "unknown target CPU
  'generic'" for `-mcpu=baseline` alone, `-mtune=native`,
  `-mtune=haswell`, `-mtune=generic`; tune-cpu "generic" throughout.

  So a Makevars (a package's, or ~/.R/Makevars) with `PKG_CFLAGS =
  -mtune=native`, portable under gcc, made a package that needs the
  compiling machine's CPU through rzig, on every OS (on linux and macOS
  before this branch too), and verify-bundle's IR check, which compiles
  with no package flags, cannot see it. zig sets tune-cpu "generic"
  whatever the flags, so dropping `-mtune=` loses nothing.
- flang (23.1.1, the env's): `"x86-64"` by default; it refuses the flag
  (`flang-23: error: unsupported option '-mcpu=' for target
  'x86_64-conda-linux-gnu'`), so zig-fc's flang commands stay as they
  are. zig-fc's shared links go through compiler.argv (fortran.zig
  `command`), so they get the flag too.

## The change

- zigbuild/tools/rzig/compiler.zig: `cpu_flag = "-mcpu=baseline"`, after
  `-fno-sanitize=undefined` on every OS, with the reason; the Windows
  branch's comment now says the native target's OS and ABI are R's but
  its CPU is the machine's, which the flag replaces. `dropTune` drops
  every caller argument that starts with `-mtune=` (the joined form, the
  only one gcc and clang accept), before anything else reads them, so
  zig-fc's shared links lose it too. Unit tests: the existing exact
  command lines gain the flag (linux, macOS, Windows, and fortran.zig's
  shared links on all three), and a new test checks, per OS and for cc
  and c++, compile and link lines: the flag once, at position 3, before
  the target and before a caller's `-march=native -mcpu=haswell`;
  `-mtune=native` and `-mtune=haswell` gone from compiles and links,
  `-march=x86-64` kept. fortran.zig's tests: a shared link drops
  `-mtune=native`, a flang compile keeps it.
- fortran.zig: its module comment says the shared link gets the baseline
  CPU and no `-mtune=`, and why flang's own commands need no flag and
  keep `-mtune`.
- toolchain/zig-cc and zig-cxx (the bash shims configure-only.sh runs, the
  reference parity-test.sh holds rzig to): the same flag at the same
  place and the same `-mtune=*` drop, so the parity test stays a
  byte-for-byte comparison, with no new deliberate difference. A no-op
  for configure's captures (linux and macOS pass a target; configure
  passes no -mtune). parity-test.sh gains six cases: a package's own
  `-march`/`-mcpu` after the flag, and `-mtune=` dropped, on linux, macOS
  and Windows.
- scripts/verify-bundle.sh (verify-package), every OS, right after R runs
  from the extracted bundle: the bundle's C compiler (zig-cc; Windows
  gcc.exe) compiles a C file with `-O2 -S -emit-llvm`; its target-cpu
  must equal what env.sh's `$ZIG` gives for `zig cc -mcpu=baseline -O2
  -S -emit-llvm` with no target (this machine's arch and OS: x86-64,
  generic, apple-m1, core2). A second compile adds `-mtune=native`, a
  package's portable flag, and must give the same CPU (rzig drops it;
  without the drop it would be this machine's). It prints the CPU name.
  Skipped, said so, with no zig at all.
- scripts/verify-tree.sh, on x86_64 (linux-64, osx-64, win-64): every
  binary of R's own under R_HOME (ELF or Mach-O by magic number; Windows
  .dll and .exe) has no VEX- or EVEX-encoded instruction, and none naming
  %ymm or %zmm (`objdump -d --no-show-raw-insn`; macOS's objdump is
  llvm-objdump; Windows the env's x86_64-w64-mingw32-objdump). VEX/EVEX:
  an instruction line whose mnemonic starts with v (after binutils'
  optional `{vex}`/`{evex}` pseudo-prefix), but verr and verw, the base
  ISA's only such mnemonics; that is AVX, AVX2, FMA, F16C and AVX-512 at
  every register width. The task asked for %ymm/%zmm; review found that
  native code with no 256/512-bit vectors passes that (zig cc
  `-mcpu=native -O2` of `a*b+c` is `vfmadd213sd %xmm2,%xmm1,%xmm0`: 0 on
  %ymm and %zmm, 1 VEX), so the check counts VEX/EVEX, and still prints
  the %ymm and %zmm counts. Not caught: the extensions that keep the
  legacy encoding (SSE3 to SSE4.2, POPCNT, LZCNT, BMI1/2, MOVBE; the same
  file's `shlx` and `popcnt`) when no AVX comes with them; what CPU the
  toolchain compiles for is verify-bundle's IR check, this one is the
  backstop on what shipped. The awk reads GNU and llvm objdump alike
  (checked with binutils' objdump and llvm-objdump 22 on the same .so
  files, and with gawk, mawk, nawk and busybox awk). Not R's:
  vendor-libs.sh's copies (vendored_files, Windows' bin/x64), Windows'
  R_HOME/Tcl, and in the toolchain directory everything that is not rzig
  (Windows' binutils, minimal's make). It prints the counts; on aarch64
  it says the check does not apply.

  On linux the objdump is the host's (binutils): no pixi env has one
  (pixi.toml has no binutils for linux, and this branch does not touch
  pixi.toml). GitHub's ubuntu images have it; on a machine without it
  (a bare container) verify-tree now fails on x86_64, saying "no
  objdump on PATH for the baseline CPU check: it is the host's
  (binutils), which no pixi env provides", where it used to pass. (Its
  glibc check, `objdump -T ... 2>/dev/null || true`, was quietly vacuous
  there; on linux-aarch64 it still is.) Follow-up: binutils for
  linux-64 and linux-aarch64 in pixi.toml, so every tool comes from
  conda-forge.
- recipe/recipe.yaml: build number 4 → 5 (r-zig-toolchain's rzig
  changes; build 4 is on universe for all five subdirs).

## Tested

linux-64 (this machine: native target-cpu skylake-avx512),
conda-forge zig 0.16.0, in the worktree, pixi.lock sha256
e9f17d315fd52ccf58db6a9840379e787e5c51ad80406982f907faa2dc1b9513
(main's 6cc4ba6, unchanged; every task with `--locked`). Re-run in full
after the review fixes (the -mtune drop, the VEX/EVEX rule, verify-bundle's
-mtune=native compile):

- `pixi run --locked rzig-test`: 43/43 unit tests (one new test block,
  and new cases in existing ones); parity "47 identical, 26 identical but
  for rzig's own-environment -L, 18 deliberate differences, 0 failed"
  (the same deliberate differences as before; the six new cases are
  identical). The parity test bites: the new rzig against main's shims
  (no -mcpu=baseline) fails 74 cases; against this branch's shims with
  the -mtune drop taken out, the three -mtune cases fail ("44 identical
  ... 3 failed").
- default (slim): build; verify-tree ("baseline CPU verified: 21
  binaries of R's own under R_HOME, 0 VEX/EVEX instructions (AVX, FMA,
  AVX-512), 0 on %ymm, 0 on %zmm (objdump -d; 0 conda binaries there not
  counted)"); smoke; contract; verify-package ("packages compile for the
  baseline CPU: the bundle's zig-cc gives target-cpu "x86-64", as zig cc
  -mcpu=baseline does (x86_64), and with -mtune=native too", then every
  compiled-package check). The 20 libraries contract compiled
  (data.table, minqa, ps, quadprog, Rcpp, and pak's 15): 0 VEX/EVEX.
- minimal: build; verify-tree (20 binaries of R's own, 0 VEX/EVEX, 0
  and 0; 1 conda binary not counted: lib/R/bin/toolchain/make, which is
  the env's make byte for byte); verify-package (target-cpu "x86-64",
  with -mtune=native too); then `pixi run --locked -e wheel wheel` and
  `wheel-test` (upstream zig through PyPI's ziglang compiles the test
  package). The slim and minimal trees' rzig are byte-identical.
- `pixi run --locked -e pkg conda-package`: r-zig-slim-4.6.1-hb0f4dca_5
  and r-zig-toolchain-4.6.1-hc4a09e7_5, both outputs' tests passed; the
  toolchain package's zig-cc dry run starts `cc -fno-sanitize=undefined
  -mcpu=baseline -target x86_64-linux-gnu.2.17`.
- -mtune, end to end, on the slim tree: its zig-cc with no flag,
  `-mtune=native`, `-mtune=haswell` and `-mtune=generic` gives
  target-cpu "x86-64" every time; the same rzig with dropTune made a
  no-op gives x86-64, skylake-avx512, haswell, and a failed compile.
  `R CMD SHLIB` of an axpy loop with a Makevars `PKG_CFLAGS =
  -mtune=native` (make echoes the flag on the compile line): 0 VEX/EVEX
  instructions; through a hard-linked copy of the tree whose compilers
  are the no-drop rzig: 30, 17 of them on %ymm. With upstream zig
  (ZIG_BIN, fetch-zig) under `env -i`, the tree's zig-cc gives "x86-64"
  with and without `-mtune=native`.
- All the checks bite:
  - verify-tree: a hard-linked copy of the slim tree with one more
    library in lib/R/library/stats/libs, compiled by the tree's own
    zig-cc with `-mcpu=native -O2` (with R_ZIG_EXTRA_ENV unset, so it
    carries no rpath into the pixi env, which the build-path check
    would report first):
    - `a*b+c`, a shift and a popcount: `vfmadd213sd
      %xmm2,%xmm1,%xmm0`, `shlx`, `popcnt`; 0 on %ymm and %zmm, which
      the first version of the check passed: "error: R's own binaries
      use AVX-class instructions, beyond the x86-64 baseline (an object
      compiled for the build machine's CPU): lib/R/library/stats/libs/
      native.so: 1 VEX/EVEX instructions, 0 on %ymm, 0 on %zmm", exit 1;
    - an axpy loop: "30 VEX/EVEX instructions, 17 on %ymm, 0 on %zmm",
      exit 1;
    - the first file without the flag: 22 binaries, 0, 0 and 0, exit 0.
  - verify-bundle, from a scratch project root, after "standalone
    bundle verified relocatable", exit 1 each time:
    - a copy of the slim archive whose toolchain/zig-cc is a wrapper
      handing rzig `-mcpu=native` (after rzig's own -mcpu=baseline, so
      it wins): "error: the bundle's zig-cc compiles for target-cpu
      "skylake-avx512", not this arch's baseline "x86-64" (zig cc
      -mcpu=baseline): packages compiled here would need this machine's
      CPU" (before the review fixes);
    - a copy whose zig-cc is rzig with dropTune made a no-op: "error:
      with -mtune=native the bundle's zig-cc compiles for target-cpu
      "skylake-avx512", not "x86-64": zig takes -mtune as the CPU, and
      the compiler passed it on, so a package's portable -mtune=native
      would need this machine's CPU".

osx-arm64 (omicron, an M2: plain `zig cc` gives "apple-m2"), a copy
of this worktree, the same pixi.lock, `--locked`:
- rzig-test 43/43; build; verify-tree ("baseline CPU: the VEX/EVEX
  check is x86_64's; on arm64 it does not apply"); smoke; contract
  (Rcpp, data.table, minqa, quadprog through zig-fc, pak, ps);
  verify-package ("the bundle's zig-cc gives target-cpu "apple-m1", as
  zig cc -mcpu=baseline does (arm64), and with -mtune=native too"). All
  passed on the first try.
- The tree's zig-cc gives apple-m1, also with `-mtune=native`; with
  `-mcpu=native` it gives apple-m2, so a package's own choice still
  wins.

osx-64 (omicron under Rosetta: zig's native CPU there is "westmere";
`zig cc -mcpu=baseline` gives "core2"):
- build and verify-tree passed (21 binaries of R's own, 0 VEX/EVEX, 0
  and 0). verify-tree catches a planted library (`-mcpu=haswell -O3`):
  "plant.so: 21 VEX/EVEX instructions, 13 on %ymm", exit 1.
- verify-package failed twice, and not because of the check: omicron's
  CrowdStrike Falcon killed (SIGKILL, "Killed: 9") the extracted
  bundle's x86_64 rzig the first time it ran, at the target-cpu
  compile, and then deleted the file. Built the same way and run from a
  fresh directory, main's (6cc4ba6) x86_64 rzig ran 2 of 2 times, and
  this branch's was killed 5 times out of 7 runs. Its ad-hoc signature
  verifies (`codesign --verify`). The one run that was not killed gave
  target-cpu "core2". These runs caused about 5 Falcon detections on
  omicron (2026-10-06, 21:05-21:17 EDT), so testing stopped there.
  GitHub's macos-15-intel runners have no Falcon; CI's osx-64 legs are
  this branch's verify-package there. (Two runs of main's binary are too
  few to say main's is safe; Falcon's classifier is not documented.)

win-64 (kappa, i7-8850H: `zig cc` with no flags gives "skylake"), a
copy of this worktree, the same pixi.lock, `--locked`:
- rzig-test: 30 passed, 13 skipped (the existing Windows-host guards,
  fortran.zig's shared-link tests among them); build (16m41s); verify-tree
  ("25 binaries of R's own under R_HOME, 0 VEX/EVEX instructions, 0 on
  %ymm, 0 on %zmm"; 51 conda binaries not counted: 43 vendored DLLs and
  the 8 binutils); smoke; contract (its 20 DLLs: 0 VEX/EVEX);
  verify-package ("the bundle's gcc.exe gives target-cpu "x86-64" ...
  and with -mtune=native too", then every existing Windows check). All
  passed on the first try.
- The point of the change: the 2026-10-04 tree's gcc.exe gives
  "skylake", with and without `-mtune=native`; this branch's gives
  "x86-64" in both cases. `RZIG_PRINT_ARGV=1` shows gcc.exe, g++.exe and
  zig-fc.exe's shared link starting `<zig> cc|c++ -fno-sanitize=undefined
  -mcpu=baseline`, with `-mtune=native` gone.
- Both checks catch a bad build: verify-tree with a `gcc.exe -mcpu=native`
  DLL planted in stats/libs/x64 ("native.dll: 5759 VEX/EVEX
  instructions, 152 on %ymm", exit 1); verify-package on this archive with
  the 2026-10-04 gcc.exe swapped in ("compiles for target-cpu "skylake",
  not this arch's baseline "x86-64"", exit 1).

## Not tested

- linux-aarch64: CI only. verify-tree should say the check does not
  apply, and verify-package should report target-cpu "generic".
- osx-64 verify-package past the CPU check, on omicron (Falcon, above).
- Upstream zig through ZIG_BIN (`pixi run fetch-zig`) for build and
  verify-package. wheel-test compiled its C package with PyPI's ziglang
  0.16.0 (upstream zig), and on linux the tree's zig-cc through upstream
  zig gives "x86-64" with and without `-mtune=native`.
- The full and openblas variants (rzig is the same file in every flavor
  of a platform).
- macOS's BWK awk for verify-tree's VEX rule (gawk, mawk, nawk, busybox
  awk agree; osx-64's verify-tree ran it with /usr/bin/awk and passed,
  and caught the planted library).

## Follow-ups (not on this branch)

- binutils for linux-64 and linux-aarch64 in pixi.toml, so verify-tree's
  objdump comes from conda-forge (and its glibc check stops passing
  silently without one).
- Falcon and osx-64's rzig: if an Intel Mac user reports the compiler
  killed or deleted, find what in the binary trips Falcon's classifier.
- rzig's `RZIG_PRINT_ARGV` output overwrites the start of a regular file
  it is redirected to: printArgv (zigbuild/tools/rzig/main.zig:242) uses
  `Io.File.stdout().writer(io, &buf)`, a positional writer, which writes
  at offset 0. The repo captures it through `$(...)` (a pipe), so nothing
  here is affected; `writerStreaming` is the likely fix. Already in
  6cc4ba6.
- Legacy-encoded extensions (SSE3 to SSE4.2, POPCNT, LZCNT, BMI1/2,
  MOVBE) alone pass verify-tree; catching them needs a mnemonic list.
