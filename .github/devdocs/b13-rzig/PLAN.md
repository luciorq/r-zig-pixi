# b13-rzig: rzig items of build 13

Worktree from origin/main 7e3648e (build 12 published). Backlog:
`chore-release-12/BACKLOG.md` (docs-release-12). Hosts: delta (linux-64,
docker), omicron (macOS arm64), kappa (Windows 11 x64). Both zigs:
conda-forge zig 0.17.1 and upstream 0.17.1 (PyPI ziglang through `uvx`).

## Goal

| Item | Result |
|---|---|
| H1 `zig cc --version` writes a.o on macOS | re-checked on 0.17.1, both zigs: still writes it; the `-c` workaround stays (F1) |
| M-2 rstan on Windows (rzig half) | not rzig: rstan 2.32.7's plugin.R adds `-std=c++1y` on Windows only, StanHeaders 2.39 needs C++17; GCC fails the same way (F2). No rzig change |
| M-11 /OPT:NOICF and a broken .llvm_addrsig | reproduced cross (delta, aarch64 and x86_64, both zigs) and natively (kappa, x86_64, both zigs, through rzig gcc.exe): rzig's `_LINK_=/OPT:NOICF` fixes it; no code change (F3) |
| M-28 macOS without the Command Line Tools | rzig works without an SDK (zig's own headers and libSystem) and now says why an SDK library or framework is missing, once per link (F4) |
| M-27 MSYS make from Git bash on win-arm64 | recorded as unsupported (F5); no repro (no win-arm64 host) |
| M-29 distro libraries on linux | `R_ZIG_SYSTEM_LIBS=1` (system_libs.zig); magick and terra build and run against Ubuntu 22.04 and 24.04 packages (F6) |
| L9 rzig pkg-config mode | design only (F7, D5): not small, and pkgconf already serves the path |
| L6 toolchain in its own env | `R_ZIG_TOOLCHAIN_ENV` (zig, flang, libstdc++'s headers); tested with two pixi envs on delta (F8) |

## Decisions

All: who = default, 2026-11-24.

| # | Question | Options (chosen in bold) | Reason |
|---|---|---|---|
| D1 | H1: drop the `-c` for `--version` on macOS? | (a) drop; **(b) keep** | 0.17.1 still writes a.o, both zigs (F1) |
| D2 | M-2: where to fix rstan's `-std=c++1y` | (a) rzig drops a lower `-std` after R's; (b) Makeconf `CXX17FLAGS += -std=gnu++17`; **(c) no fix, the stress row stays `windows=fail-package`** | the same failure with GCC 16 (F2), so CRAN's Rtools fails too; (a) would also override packages that ask for C++11 on purpose (auto_ptr code that C++17 libc++ dropped); (b) overrides every C++17 package's own `-std` |
| D3 | M-28: no SDK | (a) error out; **(b) go on, warn on links only** | zig builds without an SDK (F4); only SDK libraries and frameworks fail, and the warning names the fix. Compiles stay quiet (one line per package, not per object) |
| D4 | M-28: when to warn | (a) whenever no SDK; **(b) only when xcrun ran and named none** | /usr/bin/xcrun is on every macOS; "could not run" means a dry run on another OS or the unit tests' fixture, where a warning is noise (it broke three existing tests at first) |
| D5 | L9: implement an rzig pkg-config mode now? | (a) minimal mode in rzig; **(b) design record only** | see F7: the minimal mode is about 400 lines (a .pc parser with variables, Requires recursion, version constraints) beside pkgconf, which the build-tools group already builds and Rcmd_environ already points at (ZL3 a, user D10). It pays off only when it replaces pkgconf |
| D6 | M-29: opt-in spelling | **`R_ZIG_SYSTEM_LIBS`, set and not `0`, linux only (ignored elsewhere, silently; review R1)** | as the backlog proposed; unset keeps today's hermetic behaviour |
| D7 | M-29: host include roots | **`-idirafter /usr/include/<multiarch>` then `/usr/include`**; the caller's `-I`/`-isystem` of exactly those two rewritten to `-idirafter`; other `/usr/include/<x>` stay `-I` | zig's glibc headers must win (`__time64_t`, wave2-compat F7 b); library subdirectories (gdal, webp) are harmless as -I. Matches CRAN's linux layout (implicit system dirs), wave2-rzig W6 |
| D8 | M-29: libraries | **last `-L`: /usr/lib/<multiarch>, /lib/<multiarch>, /usr/lib64, /usr/lib (those that exist)** | after every environment, so an -l an environment has still binds the environment's |
| D9 | M-29: distro libraries need a newer glibc than the 2.17 floor (terra's PROJ check: `pthread_join@GLIBC_2.34` from libsqlite3.so) | (a) raise the target to the host's glibc; **(b) `-Wl,--allow-shlib-undefined` on links** | (b) keeps one target and needs no version parsing; a shared library link already allows it, so only executables (configure tests) change; the program runs on the host that has those symbols |
| D10 | L6: lookup order | **ZIG_BIN, then R_ZIG_TOOLCHAIN_ENV's bin, then the compilers group's zig/, R's env bin, PATH, python3 -m ziglang**; flang the same; libstdc++ headers: R's env, the group's, then R_ZIG_TOOLCHAIN_ENV, then R_ZIG_EXTRA_ENV | a variable set on purpose wins over what R's install happens to have; headers stay paired with R's env's runtime when it has them |
| D11 | L6: scope | **zig, flang (its ld.lld is beside it), libstdc++'s headers**; make and cmake stay PATH's, the check names the env's bin when they are only there | rzig does not run make for R; R and configure scripts find make on PATH. The no-zig/no-flang texts are unchanged (verify-bundle.sh and wheel-test.sh match them in full) |
| D12 | L6: is the toolchain env also an environment of headers and libraries? | (a) yes; **(b) no** | that is R_ZIG_EXTRA_ENV's job; a toolchain env has nothing packages link |

## Findings

- F1 (V) H1. omicron, macOS 26 arm64, empty dir per run:
  `zig {cc,c++} [-target aarch64-native.13.0|x86_64-native.13.0] --version`
  with `pixi exec --spec zig=0.17.1` and `uvx --from ziglang==0.17.1 python
  -m ziglang`: all 12 runs exit 0 and leave `a.o` (0 bytes). With `-c`
  added: nothing written. compiler.zig's comment updated.
- F2 (V) M-2. All four Windows legs of stress 45305358893 fail the same
  way (logs/rstan-smoke.log): the compile line has `-std=gnu++17 ...
  -std=c++1y`; the real error is hidden by rstan's `sink` ("Error in
  sink(type = "output") : invalid connection"). Cause: rstan 2.32.7
  `R/plugin.R:63` adds ` -std=c++1y` when `.Platform$OS.type ==
  "windows"`. Repro on delta with CRAN sources (StanHeaders 2.39.1.1,
  RcppEigen, BH, RcppParallel 6.2.1): `zig c++ -target x86_64-windows-gnu
  -fsyntax-only -std=gnu++17 -std=c++1y ... stan/model/model_header.hpp`:
  `stan/math/prim/eigen_plugins.h:13:24: error: no member named 'void_t'
  in namespace 'std'`; without `-std=c++1y` no such error. GCC 16.2
  (conda-forge gxx_linux-64) with libstdc++: `-std=gnu++17 -std=c++1y`
  gives `'void_t' is not a member of 'std'`, `-std=gnu++17` does not
  (libstdc++ defines void_t for C++17 or GNU++11, not strict C++14). The
  tree's `bin/Rscript` is not involved (conda legs fail identically). The
  row's note already says "with CXX17FLAGS += -std=gnu++17: ok".
- F3 (V) M-11. r-windows bundles harfbuzz-8.2.1-clang-{aarch64,x86_64}:
  a DLL of a FreeType caller, `-shared -s`, linking libfreetype.a and its
  dependencies. delta, cross, conda-forge and upstream zig 0.17.1, both
  arches: without `_LINK_` rc=1 `libfreetype.a(src_base_ftinit.c.obj):
  invalid symbol index in addrsig section`; `_LINK_=/OPT:NOICF` rc=0 (8
  runs). kappa, native x64, this branch's rzig as gcc.exe (cross-built on
  delta) with conda-forge zig (`pixi exec --spec zig=0.17.1`) and
  upstream (`ZIG_BIN`, uv's ziglang): RZIG_TRACE shows `_LINK_=/OPT:NOICF
  '...zig.exe' cc ... -shared -s ...`, the DLL is written (2,057,728 B and
  2,057,216 B); the same command through zig directly fails with the
  addrsig error. Not verified: a native win-arm64 link (no host; CI only).
- F4 (V) M-28. omicron, `DEVELOPER_DIR` at an empty directory: `xcrun
  --sdk macosx --show-sdk-path` exits 1 ("invalid DEVELOPER_DIR path"),
  nothing on stdout. zig 0.17.1 alone then compiles, links and runs a C
  program with `-target aarch64-native.13.0`; `-lz` fails ("unable to find
  dynamic system library "z" ... searched paths: none"). This branch's
  rzig (built on omicron) as zig-cc/zig-cxx, both zigs: `-c` quiet; a link
  prints `zig-cc: warning: no macOS SDK (...) Install the Command Line
  Tools: xcode-select --install` once and links (C and a C++ program run);
  `-lz` prints it and then zig's error. With the Command Line Tools: no
  warning. rzig runs /usr/bin/xcrun by absolute path, so a PATH without
  xcrun changes nothing. Also seen: `zig build` of rzig on omicron over
  ssh reported its codesign step failed ("replacing existing signature"),
  yet bin/rzig was installed and runs (I: ssh session; not followed up).
- F5 (I) M-27, from chore-release-11 PLAN.md finding 18: on windows-11-arm
  the toolchain's MSYS make (R_HOME/bin/toolchain/usr/bin/make) segfaults
  even on `make --version` when Git for Windows' bash starts it, while
  every make R starts works (run 43437326154). **Unsupported:** running the
  toolchain's make directly from Git bash on Windows on ARM; R (R CMD
  INSTALL, install.packages, system2) is the supported caller. rzig never
  starts make from Git bash. Not reproduced here (no win-arm64 host).
- F6 (V) M-29. delta, docker, the standalone archives of wave2-compat's
  dist (main of 2026-11-23) with this branch's rzig copied over every name
  in R_HOME/bin/toolchain; probe `probes/m29.sh`. Ubuntu 24.04 (GDAL
  3.8.4, PROJ 9.4.0, curl 8.5.0, ImageMagick 6.9.12) and 22.04 (GDAL
  3.4.1, PROJ 8.2.1, curl 7.81.0, ImageMagick 6.9.11):
  - an executable with `pkg-config --cflags/--libs gdal libcurl proj`
    (`-I/usr/include/x86_64-linux-gnu` included): off: "unable to find
    dynamic system library gdal"; on: links and runs (`gdal 3.8.4, 216
    drivers`), both releases;
  - first run on 24.04 without D9: terra's configure "ld.lld: error:
    undefined reference: pthread_join@GLIBC_2.34 >>> referenced by
    libsqlite3.so (disallowed by --no-allow-shlib-undefined)"; with D9:
  - magick: installs, `image_blank` works, NEEDED libMagick++-6.Q16.so.9
    ... libR.so libstdc++.so.6 (24.04) and .so.8 (22.04);
  - terra: installs, writes and reads a GeoTIFF (`sum 10`), `gdal()`
    "3.8.4", NEEDED libproj.so.25 libgdal.so.34 libgeos_c.so.1 libR.so
    libstdc++.so.6;
  - sf (with the extras group's cmake for s2's bundled abseil; the first
    run without it stopped at s2's cmake, the extras note said so):
    installs with all its dependencies (units against libudunits2-dev,
    s2, wk, ...), `sf_extSoftVersion()` shows the distro's PROJ (9.4.0;
    8.2.1 on 22.04), `st_buffer` returns a polygon; NEEDED libproj.so.25
    libgdal.so.34 libgeos_c.so.1 (22.04: .so.22, .so.30) libR.so
    libstdc++.so.6;
  - 22.04: magick, terra and sf ok in one run (terra NEEDED libproj.so.22
    libgdal.so.30).
  - Logs on delta: ~/rz/scratch-b13-rzig/m29-{24.04,22.04}-c.log and
    m29-*-c/ (install and load logs).
- F7 (I) L9 design. What an rzig `pkg-config` mode would be: rzig under
  the name pkg-config (pkg-config.exe on Windows) in R_HOME/bin/toolchain,
  searching the .pc directories of environment.list() in rzig's order
  (zig-libs first, R's env, R_ZIG_EXTRA_ENV, the fallback tree; with
  R_ZIG_SYSTEM_LIBS also /usr/lib/<multiarch>/pkgconfig and
  /usr/share/pkgconfig), then PKG_CONFIG_PATH. Minimal surface CRAN
  packages use (configure scripts of sf, terra, magick, s2, curl, xml2):
  `--exists`, `--modversion`, `--atleast-version=`, `--cflags`, `--libs`,
  `--static`, `--variable=`, several modules, version constraints in
  arguments and in Requires. Needs a .pc parser (variables, `${}`
  expansion, Requires/Requires.private recursion with de-duplication).
  What it would replace: pkgconf in the build-tools group
  (zigbuild/toolchain/pkgconf.zig) and Rcmd_environ's PKG_CONFIG_PATH /
  PKG_CONFIG_LIBDIR lines (ZL5-ZL7). What it would gain: one search order
  (rzig's) on every OS, also outside R CMD, and the standalone linux tree
  without a host pkg-config. Size estimate about 400 lines plus tests:
  not small (D5). A prototype was not written in this batch.
- F8 (V) L6. delta, two pixi envs (`probes/l6.sh`): R = r-zig-slim 4.6.2
  from universe (build 12) with this branch's rzig copied in; toolchain =
  zig 0.17.*, flang-zig 23.1.5 *_0, flang-rt-zig 23.1.5 *_1,
  libstdcxx-devel_linux-64 15.*, make. PATH = R env's bin, /usr/bin, /bin.
  Without R_ZIG_TOOLCHAIN_ENV: `--rzig-check` exit 127 "no zig", the C,
  C++ and Fortran packages fail with "no zig". With it: `compilers ok: zig
  0.17.1 at <tc>/bin/zig`, fortran `flang at <tc>/bin/flang`; build-tools
  exit 127 "no make on PATH; <tc>/bin/make is installed in
  R_ZIG_TOOLCHAIN_ENV, which is not on PATH: put <tc>/bin on PATH"; the
  C (`1`), C++ (a thrown and caught std::runtime_error, `two`, libstdc++
  headers `-I<tc>/lib/gcc/x86_64-conda-linux-gnu/15.3.0/include/c++`) and
  Fortran (`3`, compiled by `<tc>/bin/flang`) packages install through
  rzig build and run. With ZIG_BIN = upstream zig and the same
  R_ZIG_TOOLCHAIN_ENV: C++ and Fortran install with upstream zig and the
  env's flang, and run. Not tested: macOS and Windows layouts beyond the
  unit tests (`<root>/Library/bin`, the mingw names).

## Tests run

| Where | Command | Result |
|---|---|---|
| delta | `pixi run rzig-test` before any change | EXIT=0 (parity: 109 identical, 77 identical but for ..., 33 deliberate, 0 failed) |
| delta | `zig build --build-file zigbuild/tools/rzig/build.zig test` (conda-forge 0.17.1) after each change | pass (first M-28 version: 3 failures, fixed by D4) |
| delta | `pixi run rzig-test` (unit, parity, link objects), conda-forge zig 0.17.1, first run | EXIT=1: parity "macos no SDK: target only" (the stub xcrun names no SDK, rzig now warns); declared a deliberate difference in parity-test.sh |
| delta | `pixi run rzig-test`, conda-forge zig 0.17.1, final tree | EXIT=0: 236/236 unit tests; parity 109 identical, 76 identical but for ..., 34 deliberate, 0 failed; link-objects ok |
| delta | `ZIG_BIN=<upstream 0.17.1> pixi run rzig-test`, final tree | EXIT=0: the same counts |
| omicron | H1 matrix (F1) | 12/12 write a.o; with -c none |
| omicron | M-28 with rzig built there, both zigs (F4) | as F4 |
| delta | M-11 cross matrix (F3) | 4 fail without, 4 ok with `_LINK_=/OPT:NOICF` |
| kappa | M-11 native through rzig gcc.exe, both zigs (F3) | ok; direct zig fails |
| delta | M-2 header compiles, zig (windows-gnu) and GCC 16.2 (F2) | c++1y fails both |
| delta docker | `probes/m29.sh magick terra sf` on ubuntu:22.04; `magick terra sf` then `sf` (with extras) on 24.04 (F6) | all PROBE lines ok with R_ZIG_SYSTEM_LIBS=1; the executable link fails without it |
| delta | `probes/l6.sh` and the upstream-zig variant (F8) | all ok as F8 |

## Not verified

- M-11 on a native win-arm64 host.
- M-28 on a Mac that never had the Command Line Tools (simulated with
  DEVELOPER_DIR; the real /usr/bin/xcrun shim may also offer the install
  dialog).
- M-29 on Fedora/RHEL (lib64) and linux-aarch64; with conda R (the
  probes used the standalone tree).
- L6 on macOS and Windows; a conda package layout for it (no recipe
  change here).
- The recipe test change (test-toolchain.R unsets the two new variables)
  was not run through `pixi run -e pkg conda-package`.

## Review

Reviewer pass, 2026-11-24 (default). Every diff hunk read; all changed
files are the topic's own (zigbuild/tools/rzig/**, recipe/test-toolchain.R,
its devdocs).

Changed:
- R1 (V) M-29: the docs (system_libs.zig header, main.zig, D6) said
  R_ZIG_SYSTEM_LIBS warns off linux, but compiler.zig only called
  `enabled` on linux, so no warning was ever printed (dead branch). Kept
  the behaviour, dropped the claim: `enabled` returns false off linux,
  silently (a warning would come on every object compile), compiler.zig
  calls it unconditionally, the unit test expects no warning.
- R2 probes/l6.sh: removed a loop that did nothing (`... && :`).

Checked, no change:
- R3 (V) `-idirafter` and `-L` on a link-only line with `-Werror`, and
  on `--version`: no unused-argument error (delta, conda-forge zig 0.17.1,
  rc=0 both). With R_ZIG_SYSTEM_LIBS=1 through the built tree's zig-cc:
  the caller's `-I/usr/include` and `-isystem /usr/include/x86_64-linux-gnu`
  become `-idirafter`, the host dirs come last, the program runs.
- R4 (V) a bad R_ZIG_TOOLCHAIN_ENV warns once on a command that reaches
  it (`zig-cxx -c` without ZIG_BIN: one line); nothing when an earlier
  place answers (ZIG_BIN set). Same pattern as R_ZIG_EXTRA_ENV.
- R5 (I) the "no zig" text still lists the old search order without
  R_ZIG_TOOLCHAIN_ENV; kept on purpose (D11: verify-bundle.sh and
  wheel-test.sh match it in full); main.zig's header has the order.
- R6 (V) Windows: R_ZIG_TOOLCHAIN_ENV resolves to <root>/Library like
  R_ZIG_EXTRA_ENV, so zig/flang come from Library/bin and the check's make
  from Library/usr/bin, matching the build.zig need below.

Tests re-run after the review changes (delta):

| Command | Result |
|---|---|
| `pixi run rzig-test` (conda-forge zig 0.17.1) | EXIT=0: 236/236 unit; parity 109 identical, 76 identical but for ..., 34 deliberate, 0 failed; link-objects ok |
| `ZIG_BIN=<upstream ziglang 0.17.1> pixi run rzig-test` | EXIT=0, same counts |
| `pixi run build`, `verify-tree`, `smoke` | 0, 0, 0 |
| `pixi run toolchain`, `pixi run contract` (compile tree's zig = upstream ziglang 0.17.1) | 0; "Contract test passed (slim/linux)" |

The darwin (M-28) and Windows (M-11) code paths were not touched by the
review, so omicron and kappa were not re-run. Logs: delta
~/rz/scratch-b13-rzig/rev/.

## Needs from other topics

- b13-stress (stress/packages.tsv, rstan row): optional note text only,
  the expect stays `windows=fail-package`. Append to the note: `; b13
  (2026-11-24): GCC 16 with libstdc++ fails the same headers with
  -std=c++1y ('void_t' is not a member of 'std'), so CRAN's Rtools does
  too; not an r-zig bug (b13-rzig PLAN.md F2)`.
- b13-build (build.zig rcmdEnviron, Windows only, optional, for L6's
  build tools): put R_ZIG_TOOLCHAIN_ENV's MSYS dir after the group's:
  ```
  -        "R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin;${R_HOME}/bin/toolchain/cmake/bin;${R_HOME}/../../usr/bin",
  +        "R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin;${R_HOME}/bin/toolchain/cmake/bin;${R_HOME}/../../usr/bin;${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin",
  ```
  (unset, the entry is `/Library/usr/bin`, a missing directory, which
  PATH skips). Unix needs nothing: rzig finds zig and flang itself, make
  stays PATH's.
- Owners of recipe/test-build-tools.R, test-extras.R, test-preflight.R:
  add `"R_ZIG_TOOLCHAIN_ENV", "R_ZIG_SYSTEM_LIBS"` to their
  `Sys.unsetenv(...)` list, as test-toolchain.R now does.
- Docs owner (README or the Windows docs record), M-27: "Running the
  toolchain's make directly from Git for Windows' bash is not supported on
  Windows on ARM (it segfaults); run builds from R (R CMD INSTALL,
  install.packages)." And user docs for `R_ZIG_SYSTEM_LIBS` and
  `R_ZIG_TOOLCHAIN_ENV` (main.zig's header has the reference text).

## Suggested commit message

```
feat: rzig finds the toolchain in R_ZIG_TOOLCHAIN_ENV, builds against distro libraries with R_ZIG_SYSTEM_LIBS, warns on macOS links without an SDK
```
