# fix-verify-scripts (build 12 backlog, batch B4)

Goal: make verify-tree.sh's C++-runtime and baseline-CPU checks catch what
they missed, keep `-F` in pkg-parity's argv, and make the standalone tar archives reproducible.

Branch fix-verify-scripts from main 3395a08. Items: Q6, M-8, Q14, M-22
done; M-21 deferred. Tests ran on delta (linux-64, Ubuntu 26.04), on the slim tree from main
(~/rz/base, `pixi run build`, base-build.log EXIT=0).

## Decisions

| # | question | chosen | reason |
|---|---|---|---|
| D1 | Q6: where the GLIBCXX bound comes from | the newest `GLIBCXX_3.4.N` in libstdcxx-devel_linux-*'s own `lib/gcc/<triple>/<ver>/libstdc++.so.6`, found through its conda-meta record (the tree's conda-meta if it is a conda env that has one, else `$CONDA_PREFIX`'s) | the devel package ships the same gcc's runtime next to the headers (F2). No gcc-to-GLIBCXX table to maintain. A first draft with such a table (one tag per major from 14) was wrong for gcc 16 (F3) |
| D2 | Q6: no devel record found | error (linux) | a silent pass is what the hard-coded bound was meant to stop |
| D3 | M-8: how to catch legacy-encoded extensions | a whole-mnemonic ERE (`legacy_mnemonics`) over SSE3, SSSE3, SSE4.1, SSE4.2, POPCNT, LZCNT, MOVBE, BMI1, BMI2, with an optional AT&T b/w/l/q suffix only where the instruction takes one | the backlog's "mnemonic list". An exact match keeps baseline names with the same prefix (andnps, pextrw, pmaxsw, pinsrw) out |
| D4 | M-8: tzcnt | not counted | LLVM emits `rep bsf` (F3 0F BC) for the baseline, and objdump prints it as tzcnt (F4) |
| D5 | M-8: osx-64 | SSE3 and SSSE3 not counted on macOS | zig's x86_64-macos baseline is core2 (F5), and verify-bundle.sh already expects target-cpu core2 there |
| D6 | M-22: mtime | `SOURCE_DATE_EPOCH`, else HEAD's commit time, else 0 | reproducible-builds convention. It does not touch the tree |
| D7 | M-22: zip (Windows) | unchanged, recorded | zip stores each file's mtime, and making it reproducible means rewriting the tree's mtimes or another zip tool. Not testable here |
| D8 | M-21 | deferred | see Not verified |

## Findings

- F1 (V) Q14: `argv_of` dropped the directory of a `-F<dir>` path but also dropped the `-F`. With `(-[ILF]|`, `-F/Library/Frameworks/x` becomes `-Fx` (the old code gave `x`). Ran on delta with `~/rz/scratch/fvs-q14.sh`: it evals `argv_of` from both scripts on one synthetic log line. Change at scripts/pkg-parity.sh:167.
- F2 (V) libstdcxx-devel_linux-64 15.3.0 ships `lib/gcc/x86_64-conda-linux-gnu/15.3.0/libstdc++.so.6.0.34` and `.a`, beside the headers. Source: its conda-meta `files` list on delta. Its newest tag is GLIBCXX_3.4.34.
- F3 (V) The env's runtime libstdcxx 16.2.0 defines GLIBCXX_3.4.35 and 3.4.36. Command: `grep -ao 'GLIBCXX_3\.4\.[0-9]*' .pixi/envs/default/lib/libstdc++.so.6`. So "one tag per gcc major" does not hold, and D1 avoids any mapping.
- F4 (V) tzcnt is in baseline builds: `objdump -d | grep -cw tzcnt` counts 3 in every rzig name, and 1 each in libR.so, libRblas.so and libRlapack.so, on main's slim tree.
- F5 (V) `lib/zig/std/Target.zig:2164-2166`: `.x86_64 => switch (os.tag) { ... .macos => &x86.cpu.core2`. core2 has ssse3 (Target/x86.zig).
- F6 (V) GNU objdump prints register-only forms without the AT&T suffix (`popcnt %rdi,%rax`, `crc32 %rsi,%rdi`), so the suffix is optional in the ERE.
- F7 (V) xz 5.8 man page: `-T0` always uses the multi-threaded compressor, even on one core (since 5.4), and its output does not depend on the thread count. `-T1` is single-threaded and gives other bytes (F8 numbers).
- F8 (I) The old `tar -czf` is not reproducible: two copies of one tree give different archives (`cmp` differs).

## Tests (delta; base env ~/rz/base/.pixi/envs/default, tree ~/rz/base/dist/slim/R-4.6.2-zig)

- verify-tree.sh (new) on main's slim tree: exit 0. Output: "baseline CPU verified: 22 binaries ... 0 of SSE3 to SSE4.2, POPCNT, LZCNT, MOVBE, BMI1/2" and "C++ runtime verified: ... GLIBCXX_3.4.36 >= GLIBCXX_3.4.34 of the libstdc++ 15.3.0 headers". Log: ~/rz/scratch/fvs-pos2.log.
- M-8 negative: `zig cc -mcpu=x86_64+popcnt+sse4_2+lzcnt+bmi+bmi2` built a shared library (popcnt, lzcnt, pdep, crc32, no VEX), copied over the tree copy's `lib/R/modules/internet.so`. New script: exit 1, "4 of SSE3 to SSE4.2, ...", and the four instructions named. Main's script on the same tree: exit 0 ("0 VEX/EVEX"), which is the gap M-8 described. Script: ~/rz/scratch/fvs-neg.sh.
- Q6 negative: conda-forge libstdcxx 14's real libstdc++.so.6 (GLIBCXX_3.4.33, from `pixi exec --spec 'libstdcxx=14.*'`) in a tree copy, with its SOURCES sha updated so the records check passes. Exit 1: "lib/libstdc++.so.6's newest version is GLIBCXX_3.4.33, older than GLIBCXX_3.4.34 of the libstdc++ 15.3.0 headers". Script: ~/rz/scratch/fvs-neg3.sh.
- Q6 boundary: the devel's own 6.0.34 in the tree gives exit 0, "GLIBCXX_3.4.34 >= GLIBCXX_3.4.34".
- Q6 derivation, with the functions extracted from the script (~/rz/scratch/fvs-neg2.sh):
  - a fake aarch64 devel 17.1.0 record (multi-line JSON) resolves to its .so, and the max is 3.4.40 (3.4.9 and a bare 3.4 do not win);
  - no record gives empty, which the script turns into an error;
  - a conda tree's own conda-meta is read before the env's;
  - the real env resolves to 15.3.0.
- M-22: `package-standalone.sh base` was run twice with `PIXI_PROJECT_ROOT` set to the worktree. The second run was on a fresh `cp -r` copy (new mtimes). Both archives have sha256 d78c4be5…4f26, and `cmp` finds them identical. Members are 0/0 with HEAD's commit time. The old command gives different archives for the same two copies.
  - xz path (`tar_repro` | `xz -9`, the toolchain archives' command) on the tree: `-T0`, `-T4` and `-T0` under `taskset -c 0` (one CPU) all give ac459158…f2e2. `-T1` gives 42f22196…4207 (F7). Script: ~/rz/scratch/fvs-m22.sh, log: ~/rz/scratch/fvs-all.log.
- Q14: see F1.
- Review (delta, 2026-11-23): the scripts above re-run, same results. They share ~/rz/scratch/fvs and must run in order: fvs-neg.sh (its own Q6 cases fail on other checks, records and the fake env's paths, so only its M-8 case counts), fvs-neg2.sh (fetches libstdcxx 14's runtime), fvs-neg3.sh.
- Review, M-8 list on both disassemblers (~/rz/scratch/rev-m8.sh, rev-m8.log, rev-m8-llvm.log): 26 baseline lookalikes (andnps, pextrw, pinsrw, pmaxsw, pmaxub, movsd, movss, movsl, bsf, bsr, `rep bsf`, fistpll, shld, ...) match 0; 46 instructions of the listed extensions match 46 on linux, 32 on macOS (the 14 SSE3/SSSE3 ones excluded), with GNU objdump and with llvm-objdump (`pixi exec --spec llvm-tools`, the Windows and macOS disassembler, which prints the AT&T suffixes: popcntq, pdepq, movbel).
- `bash -n` on all three scripts.

## Not verified / deferred

- M-21 (host tools on linux: cmp, find, ldd, bash, dirname), deferred. It needs diffutils and findutils in pixi.toml and pixi.lock (batch B3's files). The wheel env would need bash and coreutils. vendor-libs.sh's `ldd` closure would need a needed_of-based walk with its own verification on all linux legs. Together that is over an hour and touches another batch's files. Source: chore-deps-ci-checks/PLAN.md:355-358.
- osx-64 and win-64 runs of the new baseline-CPU list: needs a Mac or Windows host, so it is not run here. CI's build-r verify-tree step covers it in the group-2 wave. A failure there names the instructions and functions.
- M-22 file modes: the archives keep each file's permission bits, so a checkout under another umask (002 on delta, 022 on CI) gives other bytes. Not normalized here (it would change what ships).
- M-22 on macOS and Windows, not run. The tar flags need GNU tar: conda-forge `tar` on unix and m2-tar on Windows, both first on PATH. A BSD tar would fail loudly on `--sort`, not silently. The Windows .zip stays non-reproducible (D7).
- Q14's omicron parity run (CI10): group 2.
- Both zigs: no zig or rzig code changed. The tests used conda-forge zig (main's build and the M-8 negative library). The upstream-zig legs are not needed for this diff.

## Backlog items closed

Q6, M-8, Q14, M-22. M-21 is deferred (above).
