# b14-l4: native Windows build tools, an opt-in

Build 14, track b14-l4, from build13 head cc7d810 (worktree, uncommitted).
User decision U1 (b13-integration PLAN.md, b13-design L4-M option b):
busybox-w32 plus a zig-built GNU make, no MSYS2, shipped as an opt-in in
build 14; MSYS2's tools stay the default; the default switches later,
when a report-only stress leg matches the MSYS2 leg. Design and
prototype: b13-design PLAN.md (L4 section) and prototype/l4/.

## Goal

- (a) GNU make for x86_64/aarch64-windows-gnu from zigbuild/make in the
  toolchain build.
- (b) busybox-w32 built with zig through build.zig (the design's D3: a
  port of build-busybox.sh's Kbuild run), its source pinned by hash in a
  .zon.
- (c) The opt-in: how a user turns it on, and where the tools live.
- (d) R patch 0017: make arguments in double quotes on Windows (the
  design's draft 0016; build13 takes 0016 for 0016-rfe-env-dll-path).
- (e) A report-only native-tools stress leg.
- The design's gaps where feasible: RcppParallel (`/c/` paths), `zip`.
- Tests: cross-builds on delta (x86_64, aarch64 compile-only, both zigs);
  kappa, 3+ CRAN packages (plain C, Rcpp, configure.win) with MSYS2 absent
  and the opt-in on, and the default unchanged; timings and sizes.

## What was built

| piece | files |
|---|---|
| busybox-w32 with zig, no Kbuild | zigbuild/busybox/build.zig (Kbuild's work in Zig: vendored config, generated headers, Kbuild lists evaluated, host programs run), usage_h.zig (usage_compressed.h), config/{x86_64,aarch64}.config, build.zig.zon (frippery.org tarball, zig hash) |
| toolchain build | zigbuild/toolchain/build.zig: `native/` group directory on Windows (installNative: busybox.exe + 52 applet copies, make.exe from zigbuild/make via installMake, pkgconf again), SOURCES, LICENSES/{busybox-w32,make,pkgconf}/ with busybox's SOURCE note; -Dbusybox; zigbuild/toolchain/busybox.zig (pins, applet list, tests); build.zig.zon (`busybox`, `r_zig_busybox`); make.zig doc |
| R patches | zigbuild/patches/R-4.6.2/0017-install-make-args-windows-quotes.patch, 0018-native-tools-windows.patch |
| conda | recipe/recipe.yaml: make source on every platform, busybox source (win), r-zig-slim excludes native/, new output r-zig-native-tools (win only); recipe/build.sh passes -Dmake/-Dbusybox on Windows; recipe/test-native-tools.R |
| standalone | scripts/env.sh: build-tools group = usr etc native; scripts/verify-toolchain.sh: native/ checks |
| stress | stress/stress.R `--native-tools`; .github/workflows/stress.yaml input `native_tools`; stress/README.md |
| docs | README.md (r-zig-native-tools, the build-tools archive's native/) |

How a user turns it on (conda): install `r-zig-native-tools` (with
r-zig-slim and r-zig-compilers; r-zig-build-tools not needed) and set
`R_ZIG_NATIVE_TOOLS=1`. Standalone: the Windows build-tools archive has
`native/` beside `usr/`; the same variable picks it.

## Decisions

All defaults (default, 2026-11-24), inside the approved batch, unless
marked as the user's.

| id | question | options (chosen ★) | reason |
|---|---|---|---|
| U1 | (user, 2026-11-24) L4 | b13-design L4-M (b) ★ native set as an opt-in in build 14, default later | the user's decision |
| D1 | Where the tools live | (a) inside r-zig-build-tools' usr/ behind a switch; (b) ★ a `native/` group directory, R_HOME/bin/toolchain/native/{bin,SOURCES,LICENSES}: conda's own add-on output r-zig-native-tools (Windows only), and in the standalone Windows build-tools archive beside usr/ | r-zig-build-tools depends on the m2 packages, so only a separate conda package gives an env with no MSYS2 file (the point of L4); a directory of its own keeps usr/bin's pkgconf and MSYS tools apart and makes the PATH switch one entry. The standalone archive is extracted, not solved, so one archive with both sets and the variable picking is simplest there |
| D2 | How the opt-in is read | (a) etc/Rcmd_environ (a value-as-directory trick, `${R_ZIG_TOOLS-usr}`); (b) a C patch to rcmdfn.c; (c) ★ R code: patch 0018, tools' `.rzig_native_tools()` called by R CMD INSTALL (`.install_packages`) and R CMD SHLIB (`.shlib_internal`), and the same rule in Rprofile.windows for sessions; (d) only R's R_CUSTOM_TOOLS_PATH (the user names the directory) | Rcmd_environ's `${VAR-default}` tests whether a variable is set, never its value (Renviron.c subterm, read on delta), and the CMake generator has to change with the tools (D3): two settings from one switch need code. R CMD INSTALL and SHLIB are the only R CMD paths that run configure or make (R CMD config is rzig's, check/build call INSTALL); (c) is R code next to 0013's, Windows-only, a no-op when unset |
| D3 | The variable | ★ `R_ZIG_NATIVE_TOOLS`, on for 1/true/yes (case-insensitive), anything else off | the task's suggestion; plain switch semantics |
| D4 | CMake's generator under the opt-in | (a) leave Rcmd_environ's `MSYS Makefiles`; (b) ★ `Unix Makefiles` when unset or the MSYS default, a user's other choice kept | MSYS Makefiles write `/C/...` paths and pass them to native programs, which only MSYS2's runtime translates (b13-design L4-F9; RcppParallel's failure). Unix Makefiles write `C:/...` paths, which GNU make for Windows reads (F16) |
| D5 | CONFIG_SHELL under the opt-in | ★ `sh` unless set | as the b13-design prototype ran autoconf scripts (run.bat `CONFIG_SHELL=sh`) |
| D6 | busybox's build | (a) Kbuild with zig as the compiler (prototype build-busybox.sh, needs make, perl, bzip2 and shell wrappers); (b) ★ zigbuild/busybox/build.zig doing Kbuild's work (D7-D10) | the design's D3 (a port of build-busybox.sh into Zig build steps); simplicity rule: Zig, not bash/sed; one zig for the whole build |
| D7 | busybox's configuration | (a) defconfig + kconfig at build time; (b) ★ vendored `.config` per arch (the prototype's oldconfig output), read by build.zig, which writes include/autoconf.h as kconfig's conf does | as make's and R's vendored configs; kconfig is a C host program with lex/yacc output; `oldconfig` changes the shipped defconfig (CP_SPARSE added, SGI/SUN labels dropped), so the result, not the defconfig, is the input |
| D8 | Config changes from the prototype's | ★ FEATURE_COMPRESS_USAGE off (std has no bzip2 compressor; the usage text is stored as is), FEATURE_SH_EMBEDDED_SCRIPTS off (no applet script is configured: NUM_SCRIPTS 0 either way); kept: MAKE and PDPMAKE off, clang as compiler names, no STATIC_LIBGCC | F2: the object list is Kbuild's; usage costs nothing measurable (exe 739,328 B vs the prototype's 752,640 B unstripped) |
| D9 | `-include include/autoconf.h` | (a) `-include` flag; (b) ★ a generated wrapper per source (`#include "autoconf.h"` then the source by absolute path) | zig 0.17's cache records `-include`'s file as a bare name and fails its next check (`checking cache failed: file_open FileNotFound .../autoconf.h`, delta); the wrapper keeps the source's own `"..."` includes relative to its directory and `-ffile-prefix-map` maps the path away (F3) |
| D10 | Kbuild's lib.a archives | ★ one static library of every lib-y object, obj-y objects (applets.o) and the resource in the exe, `--gc-sections` | trylink links lib.a archives in a group; one archive keeps archive semantics (unreferenced objects stay out) |
| D11 | Applet names in native/bin | (a) hard links (`busybox --install`); (b) ★ copies of busybox.exe under 52 names (busybox.applets: what make starts itself, F11 of b13-build, phase 7's names, R-exts' makefile commands); (c) all 179; (d) small launchers | conda packages store hard links as separate files (F8), so (a) is (b) on disk; inside busybox's sh every applet runs without a name file (PREFER_APPLETS, SH_STANDALONE); (d) costs a process per call (6.5 ms, phase7native). 53 copies are 39 MB on disk, 1 copy in the .conda (zstd) |
| D12 | pkg-config in native/ | ★ the same pkgconf exe again (bin/pkgconf.exe, pkg-config.exe) | an env with r-zig-native-tools and no r-zig-build-tools then has pkg-config; usr/bin's copy is r-zig-build-tools' |
| D13 | Windows make | ★ zigbuild/make/build.zig as it is (it already targets windows-gnu), installMake(group) for native/ | no change to make's build; usr/ keeps m2-make (b13-build D12) |
| D14 | Patch numbers | ★ 0017 make-args quoting (the design's draft, unchanged in substance), 0018 the opt-in | build13 adds an unrelated 0016 (0016-rfe-env-dll-path); the three apply in any combination (F12) |
| D15 | r-zig-toolchain metapackage | ★ unchanged (no r-zig-native-tools) | the default stays MSYS2's |
| D16 | Wheels | ★ unchanged: make-wheel.py takes usr/ and etc/ only | the opt-in is conda and standalone first; a wheel set can follow the default switch |
| D17 | busybox's AUTOCONF_TIMESTAMP | ★ `"r-zig"` (`BusyBox v1.39.0-FRP-6354-g5f09fb446 (r-zig)`) | reproducible; kconfig's is the configure time |
| D18 | Stress leg | ★ `--native-tools` / input `native_tools`: R_ZIG_NATIVE_TOOLS=1, R_CUSTOM_TOOLS_PATH = native/bin;cmake/bin (R CMD's PATH then has no MSYS2 directory), the env's Library/usr/bin and mingw-w64/bin off PATH, a conda run adds r-zig-native-tools | it measures the native set alone, as a user without r-zig-build-tools has it; report-only like every stress job (exit 0 unless --strict) |
| D19 | zip and RcppParallel | ★ recorded, menu M2/M3 | both are outside what this change can fix cheaply (F13, F14) |
| D20 | (review) 0017's and 0018's Windows test | (a) install.R's `WINDOWS`; (b) ★ the host, `.Platform$OS.type == "windows"` | R_CROSS_BUILD sets `WINDOWS <- TRUE` on a unix host (install.R, `.install_packages` and `.shlib_internal`), whose make runs under sh: double quotes there make sh run `$(CC)` as a command substitution. The quoting concerns the host's make, so the host decides (R1) |

### User decisions (2026-11-26)
| U6 | M4: igraph's DLL link passes the 32k command line under the native make | (a) ★ build Windows make with `-DBATCH_MODE_ONLY_SHELL` (zigbuild/make/build.zig); (b) R patch 0019, objects through a response file; (c) record as fail-known | the user: "All recommended" (2026-11-26). Applied; delta: make built for x86_64- and aarch64-windows-gnu and x86_64-linux-gnu with conda-forge and upstream zig 0.17.1, 6/6 ok, the Windows exe has the batch-file code (`Cleaning up temp batch file`); `zig fmt --check` ok. Not rerun on kappa with the final make (the F39 prototype installed igraph, RcppParallel and minqa). Side finding: delta's shared zig cache held a bad `p/<make hash>.tar.gz` (a repacked tarball), which made both zigs report a hash mismatch; moved aside to ~/rz/bad-make-pkg.tar.gz, not a repo problem |

| id | question | choice | note |
|---|---|---|---|
| U3 | M1: when native tools become the default | (a) ★ after a `native_tools` stress leg matches the MSYS2 leg | the user: all recommended |
| U4 | M2: `zip` | (a) ★ Info-ZIP zip built with zig, in native/ | the user: all recommended |
| U5 | M3: RcppParallel's `-G "MSYS Makefiles"` | (b) patch busybox-w32 to convert `/c/` paths for native programs, if feasible | the user: "RcppParallel should work right now, if patching busybox is feasible go with B" |

## Findings

| id | tag | finding and evidence |
|---|---|---|
| F1 | V | zigbuild/busybox builds with both zigs 0.17.1 (conda-forge `~/rz/base/.pixi/envs/default/bin/zig`, upstream `~/rz/base/build/zig-upstream/.../ziglang/zig`) for both arches on delta (`bb-matrix.sh`): cf x86_64 ok 40 s 738,304 B fae8b88a...; cf aarch64 ok 31 s 656,384 B f3e40c34...; up x86_64 ok 148 s 738,304 B d8f8f49a...; up aarch64 ok 31 s 656,384 B eebd79c9... (cold caches; upstream x86_64 also built its compiler_rt/crt). aarch64 links without the prototype's link-flag drop (L4-F6): build.zig's unwind flags reach the sources, not zig's crtexe.c |
| F2 | V | The object list equals Kbuild's: the wrapped sources of the cf x86_64 build (327) against the prototype Kbuild build's `.*.o.cmd` (332): the same less scripts/kconfig's 4 host objects and resources.o (zig's resource compiler here) (`diff` of the two lists empty otherwise) |
| F3 | V | No build path in the exes: `grep -c -a -E "/home/|rz/scratch|zig-pkg|\.cache"` = 0 for all four busybox.exe (delta); `strings` shows `BusyBox v1.39.0-FRP-6354-g5f09fb446 (r-zig)` |
| F4 | V | zigbuild/make for Windows, both zigs (delta `mk-matrix.sh`): x86_64 329,216 B ae802161... from both zigs (identical); aarch64 246,784 B, 8601f1a9... (cf), a4d1560c... (upstream); 6-14 s |
| F5 | V | `zig build --build-file zigbuild/toolchain/build.zig test` (CONDA_PREFIX the delta base env): 16/16 steps, 51/51 tests with each zig (busybox.zig's 4 included: zon URL, recipe URL+sha256, zigbuild/busybox's frp and zon, applets unique) |
| F6 | V | Native Windows build (kappa, win-64 host, conda-forge zig 0.17.1 from r-zig-compilers 4.6.2 _12): the toolchain build into an env copy as recipe/build.sh runs it (`-Dprefix=` the env, -Dpkgconf/-Dmake/-Dbusybox): `usr/ (pkgconf (built)), native/ (busybox-w32 (built), make (built), pkgconf (built)) (the prefix is the env)`, 92/92 steps; 13:40:52 to about 13:47 cold (busybox's host programs and objects, make, pkgconf), 4 min 12 s for the second env with a warm global cache. busybox's host programs (applet_tables, usage) build and run on Windows |
| F7 | V | zig 0.17.1's `--summary new` panicked printing the summary after 92/92 steps succeeded (`thread aborting due to recursive panic`, exit 1, kappa, output to a pipe); without `--summary` exit 0. Not ours; worth an upstream report |
| F8 | V | rattler-build keeps no hard links: a test recipe making `x/a` with hard links `x/b`, `x/c` (200,000 random bytes) gives three regular tar entries, each `path_type: hardlink` (conda's install mode) with the same sha256, in a 202,350 B .conda: zstd stores the bytes once (delta, `~/rz/scratch-b14-l4/hl`). So applet copies cost one busybox in the download and N copies on disk |
| F9 | V | native/ on kappa: 64 files, 39,998,751 B: busybox.exe 739,328 B + 52 copies, make.exe 330,240 B, pkgconf.exe 207,872 B (x2), SOURCES (3 packages, 56 file lines), LICENSES/{busybox-w32/{LICENSE,mingw-w64-crt-COPYING,SOURCE},make/{COPYING,mingw-w64-crt-COPYING},pkgconf/{COPYING,mingw-w64-crt-COPYING}}. The MSYS2 env's Library/usr: 7,790 files, 81,672,688 B (same as b13-design L4-F7). Download size: native/bin as the package would hold it (delta, cf x86_64 busybox + 52 copies + make, 54 files, 39,459,328 B) is 547,542 B as `tar | zstd -19` (543,146 B with --long=27): the copies cost nothing in the .conda (F8) |
| F10 | V | The tools run with PATH = System32 (kappa): `busybox.exe` says `BusyBox v1.39.0-FRP-6354-g5f09fb446 (r-zig)`, `sh.exe -c 'uname -a'` `Windows_NT kappa 10.0 22621 x86_64 MS/Windows`, `make.exe --version` `GNU Make 4.4.1 / Built for Windows32`, pkgconf `3.0.11`, `busybox --list` 179 applets. verify-toolchain.sh's new native/ block, run alone on kappa against the env copy: `== native/ verified: busybox.exe and 52 applet copies, sh says Windows_NT; make 4.4.1; pkgconf; no MSYS DLL` |
| F11 | V | Probe (kappa, test.R probe): N (envN: no MSYS2 file, R_ZIG_NATIVE_TOOLS=1): the session's Sys.which sh, make, sed, grep, awk, rm, cp, chmod, uname, pkg-config, unzip all from native/bin; `R CMD sh`: uname `Windows_NT`, make native/bin/make.exe `GNU Make 4.4.1`; `tools:::.rzig_native_tools()` gives PATH head native/bin, CMAKE_GENERATOR `Unix Makefiles`, CONFIG_SHELL `sh`. D (envM: build-tools' MSYS2 set + native/, variable unset): Sys.which from Library/usr/bin (MSYS2), `R CMD sh` uname `MSYS_NT-10.0-22621`, make /c/.../Library/usr/bin/make; `.rzig_native_tools()` changes nothing. As before, Sys.which gives System32's tar and find and WSL's bash (R's own search) |
| F12 | V | The series applies to a pristine R 4.6.2 with `patch -p1 -f -F0` (delta): 0001-0015 + 0017 + 0018 (17 patches) clean, and with build13's 0016-rfe-env-dll-path.patch (18) clean; the result's install.R equals the edited tree's; `parse()` of install.R and Rprofile.windows ok |
| F13 | V | `zip` (R CMD INSTALL --build, install.R:498 `ZIP <- "zip"`): busybox has no zip applet (`--list`), and the default set has none either: r-zig-build-tools' run dependencies and the toolchain tree's usr/ trees list no m2-zip (recipe.yaml, zigbuild/toolchain/build.zig windows_dirs). A gap of both sets today, not a regression (menu M2) |
| F14 | V | RcppParallel 6.2.1 passes `-G "MSYS Makefiles"` itself on Windows (src/install.libs.R:317, CRAN tarball), so D4's generator default does not reach it; busybox-w32 reads no `/c/` paths (b13-design L4-F9) and has no MSYS argument conversion for the native cmake.exe it would start. Result row below (menu M3) |
| F15 | V | kappa tooling: OpenSSH's `cmd /c x.bat arg` hands the last argument with a trailing `"` (`one=[envN"]`), and an unactivated R.exe/Rscript.exe needs `<env>\Library\bin` on PATH (b13-hosts N3, U4); the kappa scripts strip quotes (`%~1`, `%A:"=%`) and set PATH |
| F16 | V | Installs on kappa: the results table below (N: native, opt-in on, no MSYS2 file; D: the default, opt-in off) |
| F17 | V | CMake under the opt-in (D4): `cmaketest`, a package whose configure.win runs `cmake -S src/lib -B src/lib/build` and `cmake --build` with the environment's default generator (scratch-b14-l4/kappa/cmaketest): N status 0, smoke TRUE, 3.7 s, `configure.win: CMAKE_GENERATOR=Unix Makefiles uname=Windows_NT`, `[ 50%] Building C object CMakeFiles/t.dir/t.c.obj` from native make. D: see the results table (first D run invalid, F18) |
| F18 | V | Test-harness trap, not a product finding: a robocopy'd copy of an env with m2 packages keeps the ORIGINAL env's path in its MSYS mount table (`Library/etc/fstab`: `C:/Users/admin/rz-b14-l4/.pixi/envs/msys/Library/bin /conda_bin ntfs auto`, the line conda rewrites at install). In the copy MSYS then maps the copy's `Library\bin` to `/bin` (= /usr/bin) and drops it for native children: the first D run failed ps (`R.exe: error while loading shared libraries: ?`, ps's configure got an empty `_WIN32_WINNT`), Rmpfr, RcppParallel and cmaketest (`cmake: command not found`), while the original env (cfg O, build 12 unpatched) installed ps (ok, 81.5 s). After pointing the copy's fstab at its own Library/bin (fixfstab.R), sh's PATH has `/conda_bin` and `command -v cmake` = `/conda_bin/cmake`. D was run again (results table). A copy of an MSYS-using env needs its fstab rewritten; the native set has no mount table (no such trap) |
| F19 | V | GNU make for Windows starts a recipe line without shell metacharacters itself (CreateProcess), so the applet names must exist as files (D11): upstream-zig make.exe on kappa with only sh.exe beside it: `process_begin: CreateProcess(NULL, echo make-ok Windows32, ...) failed. make (e=2)`; with echo.exe (a busybox copy) `make-ok Windows32`. The upstream-zig busybox.exe and make.exe (delta F1, F4) run on kappa: `BusyBox v1.39.0-FRP-6354-g5f09fb446 (r-zig)`, `Windows_NT`, sed ok |
| F20 | V | recipe/test-native-tools.R passes on kappa in envN (no MSYS2 file, PATH = env Library\bin + System32): `configure.win: uname Windows_NT, sh .../native/bin/sh.exe`, `rzig build: nativetools needs make: a configure.win script`, the C++ link through make with 0017's quoting, `make: MAKE_HOST Windows32`, `native tools: ... ok` (after fixing its own `::` to `:::` for an unexported function) |

## Results on kappa (build 12, win-64, 2026-11-24)

Envs: `pixi install --all` of the workspace (r-zig-slim, r-zig-compilers,
r-zig-extras 4.6.2 `_12`, gmp, mpfr; `msys` + r-zig-build-tools `_12`),
robocopy'd to envN and envM (copies: no file is the package cache's).
The toolchain build installed native/ into both copies (F6); envN's usr/
(pkgconf only) was removed again, as an env without r-zig-build-tools has
none. `bake.R` evaluated the patched install.R (0001-0018) over the tools
package's objects and wrote its lazy-load DB, and appended 0018's
Rprofile.windows lines to base's Rprofile, in each copy (a stand-in for
a rebuilt R; build 12's patches are 0001-0015, unchanged in build 13:
`git diff --stat 7e3648e HEAD -- zigbuild/patches` empty). Each target
with its dependencies from a local CRAN copy (`file://`), fresh library,
`MAKEFLAGS=-j4`, `Ncpus=1`; smoke = load and one call. PATH = the env's
Library\bin, the env, System32, Windows. N: envN, R_ZIG_NATIVE_TOOLS=1;
D: envM, unset (the default). Logs (gamma, scratch-b14-l4/kappa/):
install-N.log, install-D.log (the invalid first D run, F18),
install-D2.log, logs/{N,D}/*.out (D: the second run); the kappa scratch
`rz-b14-l4` was deleted after.

| target (why make) | N: native, opt-in, no MSYS2 | D: default (MSYS2), patched R, opt-in off | b13-design M (build 12 as shipped) |
|---|---|---|---|
| jsonlite (C; Makevars rule) | ok 50.0 s | ok 6.5 s | ok 96.9 s |
| minqa (Rcpp + Fortran; `$(shell)`; 0017's quoting) | ok 60.8 s | ok 24.9 s | ok 70.2 s |
| ps (configure.win) | ok 51.8 s | ok 13.2 s | ok 105.6 s |
| Rmpfr + gmp (autoconf configure.win) | ok 39.3 s | ok 41.3 s | ok 246.4 s |
| RcppParallel (configure.win + cmake, its own `-G "MSYS Makefiles"`) | **fail** 35.6 s: `.../native/bin/sh: line 0: /C/Users/admin/RZ-B14~1/envN/Library/bin/cmake.exe: not found` in cmake's compiler check (F14, M3) | ok 187.1 s | ok 404.0 s |
| nloptr (rzig build tier 1, no make) | fail 1.4 s: `nlopt.h` not found (its Makevars.win wants nlopt from R_TOOLS_SOFT/zig-libs; no tool involved) | fail 1.2 s, the same | not run |
| cmaketest (configure.win runs cmake with the default generator; F17) | ok 3.7 s, Unix Makefiles + native make | ok 6.0 s, MSYS Makefiles + MSYS make | not run |
| `Rcpp::cppFunction` (R CMD SHLIB, rzig) | ok 4.0 s | ok 4.1 s | ok 10.8 s |
| recipe/test-native-tools.R | ok (F20) | not run | not run |

- N installs every target the MSYS2 set does except RcppParallel, the
  known casualty (b13-design L4-F1, L4-F9), with no MSYS2 file in the env
  and no MSYS2 directory on PATH (F11). The 0017 quoting is what makes
  minqa build under native make (b13-design L4-F3: stock R failed).
- D, the default with 0017 and 0018 in R and native/ present but the
  variable unset, installs everything M did: 0017 is harmless with MSYS2's
  make, 0018 is a no-op (F11). Its first run was invalid (F18) and is not
  in the table.
- Times: N's are cold (envN's first compiles: its zig cache started empty);
  D's are the second run with a warm cache; M's are b13-design's (another
  day, other caches). They show no slowdown from the native set, not a
  benchmark. Native process starts are 2-3x cheaper (b13-design L4-F10).

## Tests run

| where | command | result |
|---|---|---|
| delta | zigbuild/busybox `zig build -Dtarget={x86_64,aarch64}-windows-gnu`, both zigs | 4 x ok (F1); object list = Kbuild's (F2); no build paths (F3) |
| delta | zigbuild/make `zig build -Dtarget={x86_64,aarch64}-windows-gnu`, both zigs | 4 x ok (F4) |
| delta | zigbuild/toolchain `zig build test`, both zigs | 51/51 (F5) |
| delta | rattler-build of a hard-link test recipe | F8 |
| delta | patch series 0001-0018 with and without build13's 0016, `patch -F0`; parse() | clean (F12) |
| kappa | toolchain build into env copies (native Windows host) | ok (F6, F7) |
| kappa | the native tools with PATH = System32; verify-toolchain.sh's native/ block | F10 |
| kappa | run.bat N probe, D probe | F11 |
| kappa | run.bat N install, D install | results table |
| kappa | run.bat N cmake, D cmake (cmaketest) | F17, F18 |
| kappa | recipe/test-native-tools.R in envN | ok (F20) |
| kappa | upstream-zig busybox.exe and make.exe from delta | F19 |
| delta | `rattler-build build --render-only` for win-64 and linux-64 | win-64 outputs include r-zig-native-tools (files native/**, the licence line), linux-64 skips it; busybox-src only on win-64, make-src on both |
| local | `zig fmt --check` of every changed .zig; `bash -n` of build.sh, verify-toolchain.sh; `parse()` of stress.R and test-native-tools.R; stress.yaml as YAML | ok |

## Not verified

- recipe/recipe.yaml's r-zig-native-tools output in a real rattler-build
  run (win-64 conda build: CI's conda-package job, not dispatched here).
  It renders (Tests run), the toolchain build it runs ran the same way on
  kappa (F6), and its test script passed there (F20).
- 0017/0018 compiled into R (tested as the patched install.R baked into
  build 12's tools package and the Rprofile hunk appended).
- aarch64 Windows: built, not run (no Windows ARM host).
- upstream-zig binaries on Windows: built on delta, the kappa run used the
  conda-forge zig's own native build.
- The stress leg itself (`native_tools`; needs a dispatch).
- ~~The unix toolchain build after installMake's new group parameter~~:
  run in review (delta, both zigs, verify-toolchain ok; Review).
- scripts/package-standalone.sh and unpack-toolchain.sh with native/ in
  the build-tools group (group_dirs change only; no standalone archive
  was built here).

## Open items (menus, recommended ★)

- **M1, the default switch** (U1's "default later"): (a) ★ after a
  `native_tools` stress leg on windows-latest (all rows, skip heavy)
  whose rows match the default leg's, flip: r-zig-toolchain takes
  r-zig-native-tools, r-zig-build-tools stays as the fallback; (b) flip
  in build 14 itself; (c) keep opt-in indefinitely.
- **M2, zip** (F13, both sets): (a) ★ Info-ZIP zip 3.0 built with zig
  into native/bin (and usr/bin), a build.zig like make's (BSD-like
  Info-ZIP licence); (b) a small `zip -r9Xq` writer in Zig (std.compress.flate)
  as an rzig applet; (c) m2-zip into r-zig-build-tools only (MSYS2 again);
  (d) record only: `R CMD INSTALL --build` on Windows stays unsupported.
- **M3, RcppParallel's `-G "MSYS Makefiles"`** (F14): (a) ★ ask
  RcppParallel upstream to honour CMAKE_GENERATOR (or use Unix Makefiles
  when `sh --version` is not MSYS's), record the row as fail-known in
  stress; (b) a busybox-w32 patch translating `/x/...` arguments for
  native programs (MSYS's argument conversion: large, fragile); (c) keep
  MSYS2 for it (the default set).

## Needs from other topics

- CI: a `native_tools=true` stress dispatch on windows-latest (and
  windows-11-arm) for M1; the conda-package job builds r-zig-native-tools.
- Release: r-zig-native-tools is a new package name on universe (win-64,
  win-arm64); until it is there, a `native_tools` stress leg with
  `distribution=conda` cannot solve its env (tree legs can run).

## Implementer self-check

Skeptical pass over the diff (11 changed files, 7 new), 2026-11-24.

- Fixed in review: test-native-tools.R called an unexported function with
  `::` (failed on kappa, now `:::`, F20); the Windows make record's build
  string lacked `-gnu` (`zig0.17.1_x86_64-windows`, F6's SOURCES; now as
  busybox's and pkgconf's); busybox's LICENSES directory is named after
  its SOURCES package (`busybox-w32`), which verify-toolchain.sh requires;
  `zig fmt` on zigbuild/busybox/build.zig and toolchain/busybox.zig
  (formatting only); a stray-quote trap in kappa's `cmd /c` arguments
  (F15, harness only).
- Retracted: a first reading of the D failures as a product bug of the
  default tools (cmake unreachable from MSYS2's sh in a conda env). It was
  the env copy's MSYS mount table (F18); the original env and the fixed
  copy find cmake as `/conda_bin/cmake`.
- Harness: the first bake.R wrote lazy-load promises, not values (a
  208 KB tools.rdb, "lazy-load database ... is corrupt"); the copies' DBs
  were restored from the pixi envs and baked again with values (2.19 MB).
- Checked, no change: 0017's first hunk drops the prototype's
  `if (WINDOWS)` (the src/Makefile.win branch is Windows-only); 0018's
  `.rzig_native_tools()` is idempotent (`startsWith` on PATH) and a no-op
  unset (F11, D); Rcmd_environ untouched, so verify-tree.sh's and
  verify-bundle.sh's PATH checks are unaffected; r-zig-slim excludes
  native/ (rendered); busybox's wrapper sources include the source by
  absolute path, mapped by `-ffile-prefix-map` (F3); the Kbuild
  evaluator's list equals Kbuild's (F2).
- Left as is, recorded: busybox in the toolchain build adds about 6 min
  cold to a Windows toolchain build (F6; CI caches zig's global cache);
  windows-11-arm builds busybox natively for aarch64 untested (delta's
  cross-build only); wheels carry no native/ (D16); `zip` and
  RcppParallel (M2, M3).

## Review

Reviewer pass over the whole diff and the new files, 2026-11-24.
Scope: correctness, Windows paths and quoting, both zigs, the workflow,
files outside the track, dead code and overclaims. Every changed file is
inside the track's set; no b13-* record was touched.

### Fixed

- **R1, 0017 and 0018 keyed on install.R's `WINDOWS`** (D20). With
  R_CROSS_BUILD set, R sets `WINDOWS <- TRUE` on a unix host, both in
  `.install_packages` and in `.shlib_internal`. That make runs under sh,
  where 0017's `CC="$(CC)"` makes sh run `$(CC)` as a command
  substitution. Before this fix it was a regression for R's own cross
  builds; CRAN's tools never use them, but stock R supports them. Both
  0017 hunks now test `.Platform$OS.type == "windows"`.
  `.rzig_native_tools()` returns FALSE on a non-Windows host, which covers
  both of 0018's call sites. Each hunk keeps its line count, so the
  headers did not change. The patch descriptions say why.

### Checked, no change

- The gated workflow (stress.yaml): it is dispatch-only, with no
  pull_request or pull_request_target trigger. The new input reaches the
  script through `env:` (STRESS_NATIVE_TOOLS), not through `${{ }}`
  inside `run:`, so it cannot be injected. It adds no secret and no
  permission. There are 13 inputs, under GitHub's limit of 25. Nothing
  in the change uploads anything.
- 0017's first hunk (the src/Makefile.win branch) is inside
  `if (WINDOWS)`, but that is true under R_CROSS_BUILD too, hence R1.
  `SHLIB=` uses `shQuote`, whose Windows default is cmd-style double
  quotes, so it was already correct. One remaining edge, recorded and not
  fixed: a `PKG_LIBS` value that itself holds a single or double quote
  would nest quotes after the gsub. install.R builds that value from
  `-l`/`-L` arguments, and no stress row has one. TMB keeps its own copy
  of the SHLIB body (0013's note), so TMB under native make still passes
  single quotes. Only the opt-in is affected, and it is untested.
- busybox's `-ffile-prefix-map` uses the native spelling of `src_dir`
  (backslashes on a Windows host), while the wrapper includes the source
  with forward slashes. This is not a leak: the only `__FILE__` in the
  shipped code is libbb.h's BBUNIT macro (unit tests, off), `assert` is
  compiled out (NDEBUG), and the exe is stripped. On kappa,
  verify-toolchain's build-path step passed for native/busybox.exe and
  make.exe (below).
- Dead code: `busybox.repository` is unused, as `pkgconf.repository`
  is. Both document where upstream lives, so they were left.
- Overclaims: F13 holds (r-zig-build-tools' run list has no m2-zip; only
  r-zig-build's build list has one). In the implementer's report, "the
  verify-toolchain checks passed on kappa" meant the native/ block alone
  (F10). The full script now passed (below).
- stress.R `--native-tools` with `distribution=conda` adds
  r-zig-native-tools to the env. Until that package is on the channel,
  the conda leg fails to solve (harness exit 2). The tree leg works
  without it. Recorded under Needs.

### Tests (reviewer)

| where | what | result |
|---|---|---|
| gamma | pristine R 4.6.2 + 0001-0015, 0017, 0018 (`patch -F0`), and with build13's 0016 | 17/17 and 18/18 clean; `parse()` of install.R (both) and Rprofile.windows ok |
| gamma | `.rzig_native_tools()` from the patched install.R on linux with R_ZIG_NATIVE_TOOLS=1, CMAKE_GENERATOR=MSYS Makefiles | returns FALSE; PATH and CMAKE_GENERATOR unchanged |
| delta | `zig build --build-file zigbuild/toolchain/build.zig test`, conda-forge and upstream zig 0.17.1 | 16/16 steps, 51/51 tests, each |
| delta | unix standalone toolchain build after installMake's group parameter (scratch prefix), conda-forge zig and upstream zig; `verify-toolchain.sh` on each tree | both builds exit 0: `usr/ (make (built))`, SOURCES `build: zig0.17.1_x86_64-linux` (no `-gnu`, as before); verify exit 0, `usr/ verified: ... make 4.4.1` (closes "Not verified": the unix build) |
| kappa | `pixi install -e default --frozen`, `pixi run toolchain`, `pixi run verify-toolchain` (standalone Windows tree, conda-forge zig 0.17.1) | all exit 0. Toolchain 9 min 21 s including fetch-zig; the tree has `native/ (busybox-w32 (built), make (built), pkgconf (built))`. The full verify-toolchain passed (records with native/'s three packages and LICENSES, the build-path check on busybox.exe and make.exe, closures over 161 PE files, `native/ verified: busybox.exe and 52 applet copies, sh says Windows_NT; make 4.4.1; pkgconf; no MSYS DLL`). Logs: scratch-b14-l4/review-kappa/. The kappa scratch rz-b14-l4 was deleted |

R1 is a no-op on a Windows host (`.Platform$OS.type` is "windows"
there), so the kappa install rows above still stand without a re-run.

### Still not verified

The items above, less the unix toolchain build and with the full
verify-toolchain now done on Windows: a real rattler-build of
r-zig-native-tools, 0017 and 0018 compiled into R, aarch64 Windows, the
stress leg, and the standalone archives (package-standalone.sh,
unpack-toolchain.sh) with native/.

## Suggested commit messages (superseded: b14-review/PLAN.md, "Build 14 commit plan")

```
feat: native Windows build tools (busybox-w32 and GNU make built with zig, pkgconf) as the opt-in r-zig-native-tools, R_ZIG_NATIVE_TOOLS (patches 0017, 0018)
test: a report-only native-tools stress leg
docs: b14-l4 record of the native Windows build tools
```

## Port onto main (build14)

The track was written on cc7d810 (build13 head) and ported, uncommitted,
into the build14 worktree on origin/main 77abec1 (build 13 merged).
2026-11-26. Compared: `git -C wt/b14-l4 diff cc7d810` against
`git -C wt/build14 diff origin/main` over the track's files, and
`git diff cc7d810 origin/main` for what main changed.

### Decisions

| id | question | options (chosen ★) | reason |
|---|---|---|---|
| D21 | recipe build number | ★ 14, with a `13 → 14` comment line in the style of the earlier ones | build 13 is on main and publishing; this is build 14's first change to the recipe |
| D22 | make's source after main's mirror list (b13-fixes F12) | ★ one unconditional source with main's three mirrors (`url:` list), busybox's source alone under `if: win` | keeps main's mirrors and L4's "make on every platform" (Windows' native make.exe) |
| D23 | `dynamic_linking: binary_relocation: false` (main added it to r-zig-build-tools, b13-make-aarch64 F1) for r-zig-native-tools | (a) add it; ★ (b) leave it out | the output is Windows-only; the patchelf rewrite that crashed make is ELF-only, and native/'s exes carry no prefix (F3) |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F21 | V | The port mixed two sources in recipe/recipe.yaml: main's make mirror list (b13-fixes F12) ended up under the `if: win` busybox source (`url: [frippery busybox tgz, mirrors.kernel.org make, ftpmirror.gnu.org make]`, sha256 busybox's), and make's source lost its mirrors. rattler-build would try make tarballs as busybox when frippery fails. Fixed (D22). The unit tests catch the broken form: busybox.zig's recipe test on a copy with the ported block, delta, conda-forge zig: `RecipeHasNoBusyboxUrl`, `14/16 steps succeeded (1 failed); 50/51 tests passed` |
| F22 | V | Patch numbers: main's series is 0001-0016 (`git ls-tree origin/main zigbuild/patches/R-4.6.2/`); 0017 and 0018 are free. The 18 patches apply in order to a pristine R 4.6.2 as zig-build.sh applies them (`patch -p1 -f -F0 --no-backup-if-mismatch`, delta, `~/rz/base/build/R-4.6.2.tar.gz`): 18/18, no offset or fuzz in any log, no .rej/.orig; `parse()` ok for install.R, Rprofile.windows, Common.R |
| F23 | V | Everything else of the track is unchanged by the port: zigbuild/busybox/**, toolchain/busybox.zig, 0017, 0018, test-native-tools.R and this record are byte-equal to wt/b14-l4's (`cmp`, `diff -rq`); the diffs of toolchain/build.zig, build.zig.zon, make.zig, env.sh, verify-toolchain.sh, build.sh, stress.yaml, stress.R and stress/README.md differ from the original only in context lines (main's `variant` input, its R_HOME report line). Main did not touch toolchain/build.zig, env.sh or verify-toolchain.sh since cc7d810. README.md and stress.R also carry b14-l5's lines (L5's, not changed here) |
| F24 | V | Cross builds on delta (build14-l4 copy, cold caches) give the same bytes as on cc7d810 (F1, F4): busybox cf x86_64 738,304 B fae8b88a..., cf aarch64 656,384 B f3e40c34..., up x86_64 738,304 B d8f8f49a..., up aarch64 656,384 B eebd79c9...; make x86_64 329,216 B ae802161... (both zigs), aarch64 246,784 B 8601f1a9... (cf), a4d1560c... (up). No build path in any exe (`grep -c -a -E '/home/|zig-pkg|\.cache|build14'` = 0); version string `BusyBox v1.39.0-FRP-6354-g5f09fb446 (r-zig)` |
| F25 | V | stress.yaml has 14 dispatch inputs after the port (main added `variant`), under GitHub's 25 |
| F26 | V | `rattler-build build --render-only` (rattler-build 0.80.1, delta): win-64 8 outputs, win-arm64 7 (no r-zig-tcltk there), both with r-zig-native-tools; linux-64 and osx-arm64 7, without it; every output number 14; make-src with the three mirrors on all four, busybox-src (frippery, 950d2c73...) on win only |
| F27 | O | scripts/verify-tree.sh (not this track's file) allows only `usr` as an extra directory in R_HOME/bin/toolchain of a Windows conda env. An env with r-zig-native-tools has `native/` there too, so verify-tree on such an env would fail. Nothing runs it on one today (conda-consume.sh has no native-tools feature); the owner of verify-tree.sh should allow `native` next to `usr` |
| F27 fix | V | Fixed in the integration pass: verify-tree.sh skips `usr` and `native` in a Windows conda env (`case "$n" in usr \| native) continue`); `bash -n` ok. Not run on a Windows env with r-zig-native-tools yet (CI conda legs need the package on universe) |
| F27 closed | V | 2026-11-28: main's conda-consume.sh (PR #59, 61188f0) has a native-tools environment (r-zig-slim, r-zig-compilers, r-zig-native-tools) that runs recipe/test-native-tools.R; its first run is build 14's CI (integration review after the rebase onto e999d92) |

### Tests (port)

| where | command | result |
|---|---|---|
| delta | zigbuild/busybox and zigbuild/make `zig build -Dtarget={x86_64,aarch64}-windows-gnu`, conda-forge zig 0.17.1 (`~/rz/base/.pixi/envs/default`) and upstream zig 0.17.1 (PyPI ziglang), fresh caches | 8/8 ok, bytes equal to F1/F4 (F24); busybox 148-169 s cold x86_64, 28-30 s aarch64; make 7-15 s |
| delta | `zig build --build-file zigbuild/toolchain/build.zig test --summary all`, busybox.zig and make.zig touched, fresh cache, both zigs | 16/16 steps, 51/51 tests, each |
| delta | the same test on a copy with the ported (broken) recipe block | 50/51, busybox's recipe test fails (F21) |
| delta | unix toolchain tree (`R_TOOLCHAIN_PREFIX=<scratch> bash scripts/zig-toolchain.sh`, conda-forge zig) and `verify-toolchain.sh` | ok 125 s, `usr/ (make (built))`; verify ok, `usr/ ... make 4.4.1` |
| delta | R patch series 0001-0018 on pristine R 4.6.2, zig-build.sh's `patch` flags; `parse()` | 18/18 clean (F22) |
| delta | `pixi lock --check` (pixi 0.84.2) | exit 0, "already up-to-date"; pixi.lock and pixi.toml sha256 unchanged; no .pixi created |
| delta | `rattler-build build --render-only` for win-64, win-arm64, linux-64, osx-arm64 | ok (F26) |
| delta | `zig fmt --check` (busybox/build.zig, usage_h.zig, toolchain/{busybox,build,make}.zig); `bash -n` build.sh, env.sh, verify-toolchain.sh; `parse()` stress.R, test-native-tools.R; stress.yaml and recipe.yaml as YAML | ok |

Logs: delta `~/rz/wt/build14-l4/build/l4/` (t1.out, t2.out, t3c.out, the
per-step logs, render-*.json). Build outputs and caches there were
deleted.

### Left for kappa and CI (not run here)

- kappa: the toolchain build into an env with native/ on main's base
  (F6 again, with main's rzig and binutils changes); recipe/test-native-tools.R;
  the N/D install rows with an R that has 0001-0018 compiled in (until
  now a baked install.R, "Not verified").
- CI: a win-64 and win-arm64 conda-package run that builds and tests
  r-zig-native-tools (first real rattler-build of the output); a
  `native_tools=true` stress dispatch on windows-latest and
  windows-11-arm (tree legs; conda legs need the package on universe);
  windows-11-arm's native aarch64 busybox build.

## Build 14 completion: zip (U4), RcppParallel (U5), kappa, delta

2026-11-26, the build14 worktree on origin/main 77abec1 (uncommitted).
The user's decisions U4 (M2 a: Info-ZIP zip built with zig) and U5 (M3 b:
patch busybox-w32 if feasible; "RcppParallel should work right now"),
and the kappa items left from the port. Delta dir `~/rz/wt/build14-l4b`
(scratch `~/rz/scratch-b14-l4b`); kappa scratch `C:\Users\admin\rz-l4`.

### What changed

| piece | files |
|---|---|
| zip with zig | zigbuild/zip/build.zig (win32/makefile.gcc's OBJZ in Zig, no makefile), build.zig.zon (Debian's copy of the tarball, zig hash) |
| zip in the toolchain | zigbuild/toolchain/zip.zig (pins, tests), build.zig (installZip: usr/bin/zip.exe and native/bin/zip.exe, LICENSES/zip/, SOURCES record; -Dzip), build.zig.zon (`zip`, `r_zig_zip`) |
| busybox patch | zigbuild/busybox/patches/0001-msys-drive-paths.patch, zigbuild/busybox/patch.zig (unified diff applier, tests), build.zig (applies `patches` to copies of the sources), build.zig.zon (.paths); zigbuild/toolchain/busybox.zig (`patches`, test), build.zig (patches shipped in native/LICENSES/busybox-w32/patches/, SOURCE text) |
| conda | recipe/recipe.yaml (zip source on win with a mirror; zip in r-zig-build-tools' and r-zig-native-tools' tests, licence and license_file; busybox source note), recipe/build.sh (-Dzip), recipe/test-native-tools.R (R CMD INSTALL --build and utils::zip()) |
| checks | scripts/verify-toolchain.sh (zip in usr/'s names; native/: zip's version against SOURCES and an archive busybox's unzip lists; zip in the build-path check) |
| R patch 0018 | description and one comment: the generator default stays, busybox now also reads /c/ paths (no code change) |
| docs | README.md (zip in both sets, busybox's /c/ paths), stress/stress.R and stress/README.md, stress.yaml and scripts/env.sh comments (zip) |

### Decisions

| id | question | options (chosen ★) | reason |
|---|---|---|---|
| D24 | zip's source and pin | ★ Info-ZIP zip 3.0 (2008, the last release), sha256 f0e8bb1f...; recipe: SourceForge with Debian's identical copy as mirror; build.zig.zon: Debian's URL | the only Info-ZIP zip release; zig's fetch of the SourceForge URL keeps the tarball's top directory, so its tree hash differs from `zig fetch`'s and build.zig would see zip30/ (F28); Debian's pool copy has the same sha256 and unpacks like make's and busybox's |
| D25 | how zip is built | (a) its makefile; ★ (b) zigbuild/zip/build.zig: win32/makefile.gcc's OBJZ and ziprc.o, -DWIN32 -DFORCE_WIN32_OVER_UNIX, -DNO_ASM (C in place of match.S, crc_i386.S; aarch64 has no x86 assembly), zip.exe only (no zipnote, zipsplit, zipcloak) | simplicity rule, as make and busybox; R needs zip.exe alone |
| D26 | zip's C under clang 22 | ★ -std=gnu89 and the K&R warnings off, a wrapper per source that includes <windows.h> first (F29), -U__DATE__ (no build date in `zip -v`: reproducible) | zip.h's `#define CR 13` breaks mingw-w64's winnt.h otherwise; no source edit (the Info-ZIP licence asks altered versions to be marked; this is an unmodified build) |
| D27 | where zip goes | (a) native/bin only; ★ (b) native/bin and usr/bin | M2 (a) said "(and usr/bin)"; F13: neither set had zip, so R CMD INSTALL --build failed with MSYS2's default set too. One build (installZip per group); r-zig-build-tools' licence becomes ISC AND Info-ZIP AND ZPL-2.1 |
| D28 | zip's licence id | ★ `Info-ZIP` (SPDX), LICENSES/zip/{LICENSE, mingw-w64-crt-COPYING} | the tarball's LICENSE is the Info-ZIP license 2007-Mar-4 |
| D29 | U5: how RcppParallel's `-G "MSYS Makefiles"` works natively | (a) a cmake.exe front in native/bin that swaps the generator for Unix Makefiles; (b) GNU make converting /c/ paths in its commands; (c) record fail-known; ★ (d) a busybox-w32 patch: MSYS2's drive-path handling (D30) | F31-F33: busybox alone is enough, make needs no change (GNU make for Windows already hands a command whose program starts with "/" to `$(SHELL) -c`, sub_proc.c), the patch is 2 files, 5 hunks, about 100 lines, and it brings the native set to MSYS2's behaviour (the default set converts these paths too), so a package written for Rtools behaves the same. (a) is an extra wrapper and a PATH lookup of the real cmake, and changes the generator a package named; (b) would rewrite text in every recipe line (`sed '/a/d'` patterns) and touch zigbuild/make, not this track's file |
| D30 | the patch's scope | ★ drive paths only (`/c` and `/c/...`; no mount table, `/usr/bin` stays): sh runs a program named by one (tryexec, in place) and `cd`s to one (cdcmd, `/c` too); a native program's arguments (`/c/...` only, not a bare `/c`: D36) are converted where MSYS2's find_path_start_and_type would (the whole argument, `-I/c/x`, after `=`, in an option after `,` or `:`), none with quotes or glob characters, none under `MSYS_NO_PATHCONV`, as MSYS2; busybox's applets get their arguments unchanged, as MSYS2's own programs | what CMake's MSYS Makefiles write (F31: `/C/...` programs, arguments, `--progress-dir=/C/...`, `-S/C/...`, `cd /C/...`). Not done (no case seen): environment values, redirections and applet file arguments (`rm /c/x`), path lists |
| D31 | MAKEFLAGS through busybox's sh | ★ the same patch: setwinxp leaves MAKEFLAGS, MFLAGS and GNUMAKEFLAGS alone | F32: busybox turns backslashes into slashes in every imported variable but COMSPEC and SYSTEMROOT; in make's flags a backslash escapes. A general bug of the native set, not RcppParallel's alone |
| D32 | how the patch is applied | (a) patch(1) in a script; ★ (b) zigbuild/busybox/patch.zig: build.zig parses the unified diff and writes patched copies, strict as `patch -F0` (exact old lines, at the header's line or at one place only), .c files only; a patched object compiles from its copy with `-iquote` its source directory | the rules: Zig, no sed, no host tool; a header patch would not reach `"..."` includers next to the original, hence the declarations in ash.c instead of mingw.h |
| D33 | GPL source for the modified busybox | ★ native/LICENSES/busybox-w32/patches/<patch> beside LICENSE, SOURCE says tarball + patches | the corresponding source of a modified binary includes the modification |
| D34 | 0018's Unix Makefiles default under the opt-in | ★ kept | Unix Makefiles writes c:/ paths that need no conversion layer; the patch is for packages that name MSYS Makefiles themselves |
| D35 | kappa test setup | ★ R, toolchain and compile tree built on kappa from this worktree (`pixi run --locked build`, `toolchain`, `verify-toolchain`, `compile-tree`), stress tree legs N (`--native-tools`) and D (`--msys-from-tree`) over a 13-row STRESS_TSV; standalone trees treeN (R + zig, flang, openmp, cmake, native; no usr/, no etc/) and treeD (+ usr/, etc/) for test-native-tools.R and the zip and CMake checks | an R with 0001-0018 compiled in (closes "0017/0018 compiled into R"), the user's standalone layouts, and the stress harness's PATH rules (D18) |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| F28 | V | zig 0.17.1 fetches the SourceForge URL as a tree with zip30/ at its top (`zigbuild/zip/zig-pkg/N-V-__8AADgXPACp67Hrxl8olLRyrIgqaWE1dG6gZJykNkzy/zip30`, delta), hash ...p67Hr...; `zig fetch` of the same URL, of the local tarball and the build's fetch of Debian's URL give ...FlXeM929... with the files at the top. Debian's zip_3.0.orig.tar.gz has SourceForge's sha256 f0e8bb1f... (delta, `sha256sum`) |
| F29 | V | zip 3.0 with zig 0.17.1 (clang 22): zip.h's `#define CR 13` before <windows.h> breaks winnt.h's `DWORD CR : 2;` (103 errors, `expected member name or ';'`), K&R definitions fail under clang's C23 default, and win32.c's `__DATE__` trips zig's -Werror=date-time. With D26: no error, no warning |
| F30 | V | zip cross builds on delta, fresh caches: conda-forge zig x86_64 262,144 B 2d3eead0..., aarch64 202,752 B 183b5af8...; upstream zig x86_64 261,632 B 9444d6b2..., aarch64 202,752 B 69272039...; no build path in any (`grep -c -a -E '/home/\|zig-pkg\|\.cache\|build14'` = 0). `zip -v` names the compiler (`Clang 22.1.8 (https://github.com/conda-forge/clangdev-feedstock ...)` for conda-forge's zig), not the machine |
| F31 | V | RcppParallel 6.2.1 under the native set, published build 13 (kappa probe env, no MSYS2 file, delta's busybox and make first on R CMD's PATH): CMake's compiler check fails `.../nb/sh: line 0: /C/Users/admin/rz-l4/probe/PIXI~1/envs/native/Library/bin/cmake.exe: not found` (F14 reproduced). The MSYS Makefiles (a kept TryCompile dir) hold `/C/...` program paths, standalone `/C/...` arguments, `--progress-dir=/C/...`, `-S$(CMAKE_SOURCE_DIR)` with `/C/...` values and, for targets in subdirectories, `cd /C/... &&`. Lines without a shell metacharacter (`$(CMAKE_COMMAND) -E cmake_progress_start /C/... /C/...`) are run by make itself: make 4.4.1's w32 process_begin passes a program it cannot find whose name starts with "/" to `$(SHELL) -c` (src/w32/subproc/sub_proc.c, the comment at line 605), so busybox sees those too |
| F32 | V | busybox-w32's sh imports a Windows environment with backslashes turned into slashes (ash.c setwinxp, all variables but COMSPEC and SYSTEMROOT). make writes command-line variables with spaces into MAKEFLAGS escaped (`OBJECTS=a.o\ b.o\ c.o`), so a make started through sh reads `a.o/ b.o/` (kappa, `make -f outer2.mk OBJECTS="a.o b.o c.o"` whose rule runs Rscript, which runs make: stock busybox: `sh sees [... OBJECTS=a.o/ b.o/ c.o]`, `make[1]: *** No rule to make target 'b.o/'`; patched: `OBJECTS=a.o\ b.o\ c.o`, `inner OBJECTS=[a.o b.o c.o]`). R CMD INSTALL passes OBJECTS="..." to make, so any package whose make reaches another make through sh (RcppParallel's tbb: make, sh, R, cmake, make) failed under the native set; latent until U5 got RcppParallel past its configure step |
| F33 | V | The prototype (patch(1) on delta, then a probe on kappa with published build 13): a CMake project with a shared library, an executable and a custom command, `-G "MSYS Makefiles"`, configures and builds with the patched busybox and zig's make (`twice 42`), where stock busybox failed as F31. RcppParallel then configures and builds TBB (`*** finished building tbb`, tbb.dll, tbbmalloc.dll, tbbmalloc_proxy.dll); its last link failed in build 13 for want of 0017 (`sh: line 8: .../g++.exe -std=gnu++20  : not found`, the single-quoted SHLIB_LD) |
| F34 | V | patch.zig's build equals the patch(1) prototype byte for byte (busybox.exe 738,816 B, 35373689..., conda-forge zig x86_64, delta). Size: +512 B over the unpatched 738,304 B. No build path in it |
| F35 | O | busybox.exe built natively on kappa (twice: the standalone toolchain tree and the env build, both 1db4b1dc...) differs from delta's cross build of the same source and zig (35373689...); each host repeats its own. Not investigated further (same as before the patch: F1 and F6 never compared hashes across hosts) |
| F36 | V | The toolchain build into an env on main's base (a robocopy of a pixi env with published r-zig-slim, r-zig-compilers and r-zig-extras 4.6.2 `_13`, no build-tools group), as recipe/build.sh runs it (-Dprefix the env, the sources from zig-pkg/): `usr/ (pkgconf (built), zip (built)), native/ (busybox-w32 (built), make (built), zip (built), pkgconf (built)) (the prefix is the env)`, exit 0, 9 min 20 s with a cold zig cache while a stress leg ran (13:19:22 to 13:28:42). native/: 68 files, 40,327,253 B (bin/ 57 files, 40,246,272 B: busybox.exe and 52 copies, make.exe, zip.exe, pkgconf.exe twice); LICENSES/busybox-w32/{LICENSE, mingw-w64-crt-COPYING, SOURCE, patches/0001-msys-drive-paths.patch}, LICENSES/{make,pkgconf,zip}/; SOURCES records busybox-w32, make, pkgconf and zip (Info-ZIP) with `build: zig0.17.1_x86_64-windows-gnu` |
| F37 | V | kappa, this worktree: `pixi run --locked build` 14 min 45 s (12:30:03 to 12:44:48), `toolchain` 9 min 57 s cold, `verify-toolchain` exit 0, `compile-tree` exit 0; after the patch and zip, `toolchain` again 3 min 4 s and verify-toolchain: `usr/ verified: 37 tools run with PATH = System32` (zip among them), `native/ verified: busybox.exe and 52 applet copies, sh says Windows_NT; make 4.4.1; zip 3.0, an archive unzip lists; pkgconf; no MSYS DLL`; the tree's busybox has the patch (`MSYS_NO_PATHCONV` in it) |
| F38 | V | Stress tree leg N on kappa (the compile tree of this worktree: R with 0001-0018, native/ with the patched busybox and zip; `--native-tools`: R_ZIG_NATIVE_TOOLS=1, R_CUSTOM_TOOLS_PATH native/bin and cmake/bin, no MSYS2 directory on PATH; `--jobs=4`; STRESS_TSV of 13 rows): 12 ok, 1 install-failed, 27.9 min, 17 dependencies ok. **RcppParallel ok (1.6 min)**: `*** configuring tbb`, `*** finished building tbb` (its own `-G "MSYS Makefiles"`), smoke `defaultNumThreads() > 0` TRUE. Also ok: jsonlite, Rcpp, minqa (0017's quoting), ps and Rmpfr (configure.win), curl, openssl, xml2, nloptr, s2 and Rhdf5lib (cmake). Rows in the results table below. Logs: kappa `rz-l4\stress-N\` (copied to gamma, scratch-b14-l4b/kappa/) |
| F39 | V | igraph fails under the native set: `process_begin: CreateProcess(...\native\bin\sh.exe, ... sh.exe -c "if test \"zvendor/arpack/dgetv0.o ...", ...) failed. make (e=206): The filename or extension is too long.` at R's share/make/winshlib.mk:16. That recipe (the DLL link) holds $(OBJECTS) four times (two echoes, nm, the link); for igraph's several hundred objects the `sh -c` command line passes Windows' 32,767-character CreateProcess limit. MSYS2's make starts its sh through the MSYS runtime, which has no such limit, hence no failure in D. GNU make for Windows has a build option for it: `BATCH_MODE_ONLY_SHELL` (main.c), which writes every recipe to a temporary .sh file and runs `sh <file>` (job.c create_batch_file). A make.exe built from zigbuild/make with `-DBATCH_MODE_ONLY_SHELL` (a scratch copy of zigbuild/make/build.zig on delta, swapped into the compile tree's native/bin) installs igraph (ok, 5.58 min), RcppParallel (ok) and minqa (ok) under N (kappa `stress-N-batch`). zigbuild/make/build.zig is not this track's file: menu M4 |
| F40 | V | The patch on kappa (`sh conv.sh` with treeN's native/bin and System32 on PATH, conv.log): `cd /c/Windows` gives `C:/Windows`, `cd /c` `C:/`; the applet `echo /c/x -I/c/y` prints them unchanged; Rscript (native) receives `c:/x`, `-Ic:/y`, `--dir=c:/z`, `-Wl,--out-implib,c:/w`, `X=c:/v`, `c:/` (for `/c`; a defect, F42, fixed), `@c:/r.rsp`, and unchanged `/c/q*`, `/usr/bin`, `plain`, `C:/k`, `s/a/b/`, `//c`; with MSYS_NO_PATHCONV=1 nothing converts. **Withdrawn (review, no log):** the make fallback with an Rscript recipe; conv.log ends with that step failing (`can't create /c/Users/...conv.mk: nonexistent directory`, the redirection), conv2.sh's output was not kept and no log holds `Rscript (R)`. The fallback is shown with logs in F43. Not converted, as D30 says: a redirection `> /c/...` (`can't create /c/Users/...: nonexistent directory`) |
| F41 | V | Standalone trees from this worktree on kappa (tests.R, tests-N.log, tests-D.log): N (treeN: no usr/, no etc/, R_ZIG_NATIVE_TOOLS=1, PATH R's bin/x64 + System32): cmaketest ok (CMAKE_GENERATOR `Unix Makefiles`, uname Windows_NT, 95.0 s cold), cmakemsys ok (the package names MSYS Makefiles; its makefiles hold `CMAKE_COMMAND = /C/...cmake.exe` and `cd /C/.../build/sub && /C/...cmake.exe -E copy ...`; 5.9 s), `R CMD INSTALL --build` of cmaketest writes cmaketest_0.1.zip (27 entries, DESCRIPTION, libs/x64/cmaketest.dll) with `native/bin/zip.exe`. D (treeD: usr/ and etc/, opt-in unset): cmaketest ok (`MSYS Makefiles`, uname MSYS_NT-10.0-22621), cmakemsys ok, `R CMD INSTALL --build` ok with usr/bin's zip (`/usr/bin/zip` under MSYS's mount table). recipe/test-native-tools.R with treeN's R: exit 0, `configure.win under busybox sh, make for Windows32, C++ through make: ok` and `R CMD INSTALL --build and utils::zip() with native/bin's zip: ok` (closes "0017/0018 compiled into R": this R was built with them) |

### Results on kappa (this worktree, win-64, 2026-11-26)

Stress tree legs with the compile tree (`pixi run -e stress stress`,
STRESS_TSV = the 13 rows below, `--jobs=4`; the libraries env `stress`
with zig-libs). N: `--native-tools` (patched busybox, zig's make, zip,
no MSYS2 on PATH). D: `--msys-from-tree` (the default MSYS2 set of the
tree's usr/). N-batch: N with make.exe built `-DBATCH_MODE_ONLY_SHELL`
(a prototype, F39). Minutes as stress reports them (N ran with a cold
zig cache and partly beside the env toolchain build; D after it).

| target (why) | N | D | N-batch |
|---|---|---|---|
| jsonlite (C, Makevars rule) | ok 1.12 | ok 1.17 | |
| Rcpp | ok 0.97 | ok 2.00 | ok 2.42 |
| minqa (Rcpp + Fortran, `$(shell)`, 0017) | ok 0.16 | ok 0.25 | ok 0.24 |
| ps (configure.win) | ok 1.15 | ok 1.45 | |
| curl | ok 0.37 | ok 0.35 | |
| openssl | ok 0.26 | ok 0.36 | |
| xml2 (zig-libxml2) | ok 0.27 | ok 0.29 | |
| Rmpfr + gmp (autoconf configure.win) | ok 0.57 | ok 0.57 | |
| nloptr (cmake, zig-nlopt) | ok 0.54 | ok 0.10 | |
| s2 (cmake, zig-abseil) | ok 4.49 | ok 4.40 | |
| igraph (several hundred objects) | **install-failed** 3.04: e=206, F39 | ok 4.27 | ok 5.58 |
| Rhdf5lib (cmake via biocmake) | ok 5.24 | ok 6.81 | |
| **RcppParallel** (its own `-G "MSYS Makefiles"`) | **ok 1.60** (failed before: F14) | ok 2.16 | ok 4.44 |
| summary | 12 ok, 1 failed, 27.9 min | 13 ok, 33.7 min | 3 ok, 0 unexpected |

The kappa trees were built from the worktree as it was at 12:29 (R
build) and 13:02 (toolchain again), other tracks' uncommitted changes of
that moment included; later changes by other tracks were not tested
there.

Logs (gamma): scratch-b14-l4b/kappa/{stress-N,stress-D,stress-N-batch}/
(report.md, report.json, logs/), logs/ (chain, build, toolchain,
verify-toolchain, stress, tests, conv, test-native-tools, tc-envT, the
RcppParallel probes rcpppar*.log), the scripts. The kappa scratch
`rz-l4` was deleted after.

### Tests (build 14 completion)

| where | command | result |
|---|---|---|
| delta | zigbuild/zip `zig build -Dtarget={x86_64,aarch64}-windows-gnu`, both zigs, fresh caches | 4 x ok (F30) |
| delta | zigbuild/busybox (with the patch), zigbuild/make, zigbuild/zip, both zigs, both arches, fresh caches (delta-checks.sh) | 12 x ok; busybox cf x86_64 738,816 B 35373689..., aarch64 656,896 B a177f8dd...; up x86_64 738,816 B a6efe8b4..., aarch64 656,896 B f48ecc3a...; make as F24; no build path in any exe |
| delta | `zig build --build-file zigbuild/toolchain/build.zig test --summary all`, both zigs | 20/20 steps, 58/58 tests, each (zip.zig's 2, busybox.zig's new patches test, patch.zig's 4 added) |
| delta | `zig test zigbuild/busybox/patch.zig` | 4/4 |
| delta | patch.zig build vs patch(1) prototype | byte-equal (F34) |
| delta | R patches 0001-0018 on pristine R 4.6.2, `patch -p1 -f -F0` | 18/18, no offset or fuzz, no .rej/.orig; parse() of install.R, Rprofile.windows, Common.R ok |
| delta | `rattler-build build --render-only` (0.80.1) win-64, win-arm64, linux-64, osx-arm64 | exit 0 each; win-64 8 outputs, win-arm64 7, with r-zig-native-tools (licence `GPL-2.0-only AND GPL-3.0-or-later AND Info-ZIP AND ISC AND ZPL-2.1`, license_file busybox-src/LICENSE, zip-src/LICENSE ...) and r-zig-build-tools (`ISC AND Info-ZIP AND ZPL-2.1`, zip-src/LICENSE); zip-src and busybox-src sources on win only; every output number 14 |
| delta | `zig fmt --check` (busybox, zip, toolchain .zig); `bash -n` build.sh, env.sh, verify-toolchain.sh, verify-tree.sh; parse() stress.R, test-native-tools.R; stress.yaml as YAML | ok |
| kappa | probe env (published `_13`, no MSYS2): CMake MSYS Makefiles project, RcppParallel, MAKEFLAGS through sh, with stock, patched and patched+MAKEFLAGS busybox | F31-F33 |
| kappa | `pixi run --locked build`, `toolchain`, `verify-toolchain`, `compile-tree` (this worktree), then toolchain/verify/compile-tree again with the patch and zip | all exit 0 (F37) |
| kappa | toolchain build into an env on build 13 (recipe/build.sh's way) | ok (F36) |
| kappa | stress N, D, N-batch | results table |
| kappa | conv.sh, conv2.sh (the patch's rules, make's fallback) | F40 |
| kappa | tests.R N and D (cmaketest, cmakemsys, R CMD INSTALL --build); recipe/test-native-tools.R in treeN | F41 |

### Not verified

- A real rattler-build of r-zig-native-tools and of r-zig-build-tools
  with zip (CI's win-64 and win-arm64 conda-package jobs; not
  dispatched). Rendered, and the same toolchain build ran into an env
  on kappa (F36).
- aarch64 Windows: busybox (with the patch), make and zip cross-build
  with both zigs; none ran (no Windows ARM host).
- upstream-zig binaries on Windows: built on delta; kappa's runs used
  conda-forge zig's native builds.
- A `native_tools=true` stress dispatch on GitHub's runners (needs a
  dispatch; tree legs only until r-zig-native-tools is on universe).
- The standalone archives with zip in usr/ and native/
  (package-standalone.sh, unpack-toolchain.sh): no archive was built.
- The Windows wheel: make-wheel.py takes the whole usr/, so its
  r-zig-build-tools wheel now carries zip.exe and LICENSES/zip/ (its
  licence comes from SOURCES); not built or tested here, and its README
  text (make-wheel.py, not this track's) still says the programs are
  m2 packages unchanged.
- The patch's untouched cases (D30): redirections to `/c/...` (F40),
  applet file arguments, environment values, path lists. No package in
  these runs needed them.
- Why busybox built on kappa differs from delta's cross build (F35).
- The Windows `R CMD INSTALL --build` under the conda layout (env
  r-zig-build-tools with usr/bin/zip.exe): tested in the standalone
  treeD only.

### Open items (menus, recommended ★)

- **M4, long link lines under the native make** (F39, igraph): answered
  and applied, (a): U6 (the user, 2026-11-26), `-DBATCH_MODE_ONLY_SHELL`
  in zigbuild/make/build.zig for Windows targets. The options were: (a) ★
  build Windows' make with `-DBATCH_MODE_ONLY_SHELL` (one line in
  zigbuild/make/build.zig, which is not this track's file: every recipe
  goes to a temporary .sh file, no command-line limit; prototype: igraph,
  RcppParallel, minqa ok); (b) an R patch 0019 to winshlib.mk passing
  the objects in a response file (changes the link of every package on
  both sets); (c) record igraph as fail-known under the native set.
- M1 (U3) stands: the default switches after a native_tools stress leg
  matches the MSYS2 leg; with M4 (a) the 13 rows here would match.

### Implementer self-check (completion)

- Re-checked: busybox's patch declares its two functions in ash.c, not
  mingw.h (a patched header would not reach includers, D32); the wrapper
  path to a patched copy (`../../patched/shell/ash.c`) is relative to
  gen's src/<dir>/; the patched copies compile with `-iquote` their own
  source directory, so shell/'s headers are found; the build equals
  patch(1)'s (F34); no build path in the exes.
- busybox's SOURCE note no longer says "unmodified"; the patch ships in
  native/LICENSES/busybox-w32/patches/ (recipe test, F36).
- 0018's text changed after the kappa R build (a comment and the patch
  description only): the R tested on kappa has the earlier comment; the
  series still applies (delta, 18/18).
- zip's version check in verify-toolchain.sh reads `This is Zip 3.0 (...)`
  (revision.h's banner) and passed on kappa (F37).

### Review fixes (2026-11-26)

A review of the completion found one defect in the busybox patch and one
claim without a log (F40). Fixed patch: zigbuild/busybox/patches/
0001-msys-drive-paths.patch (msys_convert_arg leaves a bare `/x`; header
text). Logs (gamma): scratch-b14-l4b/kappa/fix/ (fix.log, fix-old.log,
harness.log, fix-checks.out, the scripts and printargs.c).

| id | question | options (chosen ★) | reason |
|---|---|---|---|
| D36 | a bare `/c` argument of a native program | (a) convert it as MSYS2 does (`c:/`), as before; (b) also take MSYS2's `//x` to `/x` rule and drop busybox's own libtool slash drop; ★ (c) leave a bare `/x` alone (only `/x/...`, also after `-I`, `=`, `,`); `cd /c` still works (cdcmd) | for a native Windows program a bare `/x` is a switch (`cmd /c`, `xcopy /s`, `findstr /i`); MSYS2's conversion of it is the known pitfall libtool works around with `cmd //c`, which busybox's tryexec turns into `cmd /c`, and (a) then broke (F42). (b) changes every `//...` argument (UNC paths `//server/share` too) and a stock busybox behaviour, larger and no case needs it. A drive root as a whole argument was in no makefile seen (F31). A deviation from MSYS2, written in the patch header |

| id | tag | finding and evidence |
|---|---|---|
| F42 | V | Defect (review): busybox's tryexec turns libtool's `cmd //c echo` into `cmd /c echo` (w64devkit issue 50); execve reaches spawnveq through mingw_spawn_interpreter with cmd.exe's path, not busybox's, so the patch converted `/c` to `c:/`. kappa, `sh t.sh` with the busybox built from the patch before the fix (delta, conda-forge zig, x86_64, 35373689..., the F34 binary rebuilt): `cmd //c echo libtool-ok` and `cmd /c echo plain-ok` both start an interactive cmd.exe (`Microsoft Windows [Version 10.0.22621.4317]`, prompt `C:\>`, no output) (fix-old.log); printargs.exe receives `[c:/]` for `/c`, `[y:/]` for `/y`, `[-Ic:/]`, `[X=c:/]`. With the fix (D36; 9749cec0..., fix.log): `libtool-ok` and `plain-ok`, exit 0; printargs receives `[/c]`, `[//c]`, `[/y]`, `[-I/c]`, `[X=/c]` unchanged and still `[c:/x]`, `[-Ic:/y]`, `[--dir=c:/z]`, `[-Wl,--out-implib,c:/w]`, `[X=c:/v]`, `[@c:/r.rsp]`, `[-SC:/src]`, `[--progress-dir=C:/b]`, unchanged `/c/q*`, `/usr/bin`, `plain`, `C:/k`, `s/a/b/`; MSYS_NO_PATHCONV=1: `/c/x`, `-I/c/y` unchanged; `cd /c/Windows` and `cd /c` give `C:/Windows` and `C:/`; the applet echo keeps `/c/x -I/c/y`. Stock busybox FRP-6354 (same script): cmd lines ok, every `/c/` program `not found`, `cd /c/Windows` fails. A harness on gamma compiling the patched process.c's functions as patch(1) writes them (h.c, harness.log) gives the same table |
| F43 | V | make's fallback to sh (replaces F40's withdrawn sentence): kappa, zig's make 4.4.1 (delta cross build) with a recipe `/c/Users/admin/rz-l4/printargs.exe --version /c/x -I/c/y` (no metacharacter), PATH = the busybox dir + System32: fixed busybox: `[--version]`, `[c:/x]`, `[-Ic:/y]`, make exit 0; stock busybox: `.../s/sh: line 0: /c/Users/admin/rz-l4/printargs.exe: not found`, `make: *** [C:/Users/admin/rz-l4/conv.mk:2: all] Error 127` (fix.log). printargs.exe (a 3-line C program, printargs.c) stands in for Rscript |

Tests (review fixes):

| where | command | result |
|---|---|---|
| gamma | the patch on the FRP-6354 tarball, `patch -p1 -F0` (dry run, then applied); its conversion functions in h.c | applies; table as F42 (harness.log) |
| delta | zigbuild/busybox, both zigs, x86_64 and aarch64, fresh build caches (fix-checks.sh) | 4 x ok: cf x86_64 738,816 B 9749cec0..., aarch64 656,896 B 9a358890...; up x86_64 738,816 B a1366341..., aarch64 656,896 B 3399ce4e...; no build path; `MSYS_NO_PATHCONV` in each |
| delta | `zig build --build-file zigbuild/toolchain/build.zig test --summary all`, both zigs | 20/20 steps, 58/58 tests, each |
| delta | `zig test zigbuild/busybox/patch.zig`, both zigs; `zig fmt --check` busybox, zip, toolchain | 4/4 each; ok |
| kappa | t.sh and conv.mk with the fixed, the pre-fix and the stock busybox (run.cmd, run-old.cmd) | F42, F43 |
| kappa | this worktree (with the fix and the other tracks' uncommitted changes of 14:45): `pixi run --locked build`, `toolchain`, `verify-toolchain`, `compile-tree` (chain.bat) | all exit 0: build 10 min 46 s (14:45:48 to 14:56:34), toolchain 8 min 11 s, verify-toolchain (`native/ verified: busybox.exe and 52 applet copies, sh says Windows_NT; make 4.4.1; zip 3.0 ...`), compile-tree |
| kappa | t.sh and conv.mk with the compile tree's native/bin (busybox built on kappa, sha256 8f69e574...; run-tree.cmd) | as the fixed row of F42 and F43: `libtool-ok`, `plain-ok`, `[/c]` unchanged, `[c:/x]`, make exit 0 (fix-tree.log) |
| kappa | stress tree leg N (`--native-tools`, `--jobs=4`) over fix.tsv: jsonlite, minqa, ps, Rmpfr, RcppParallel | 5 ok, 0 unexpected, 2 dependencies ok (Rcpp, gmp), 5.7 min; RcppParallel ok 2.02 min (`*** configuring tbb`, `*** finished building tbb`, smoke TRUE): the fix keeps U5 (stress-N/report.md) |

Not verified (review fixes):

- The fixed busybox on aarch64 Windows (cross-built only) and the
  upstream-zig build on Windows (kappa ran conda-forge zig's x86_64 cross
  build).
- A real libtool configure that reaches `cmd //c echo` (it does so only
  for an MSYS build triplet; busybox's uname says Windows_NT): tested
  with the command itself, not through libtool.
- `//c` stays `//c` for a native program other than cmd's echo case;
  MSYS2 gives `/c` (D36 (b) not taken).
- After the fix only the N leg's 5 rows ran; igraph, s2, Rhdf5lib,
  nloptr, curl, openssl, xml2 and the D leg were not rerun (the change
  only leaves bare `/x` arguments alone; F38's rows ran with `/c/...`
  conversion, which is unchanged).
- The kappa scratch rz-l4 was deleted after; logs kept on gamma.

