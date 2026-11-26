# b13-stress

## Goal

Build 13, stress data side (files: `stress/**`): M-3 (protolite on
win-arm64), M-6 (arrow on macos-x86_64), M-2's row half (rstan smoke on
Windows), M-9 (a CMake consumer of zig-libs on Windows), M-10 (runtime
smokes on win-arm64, one copy per library in a trace), W9 (libs-zig-pixi's
`tests/r/smoke.R` from stress), Q26 (R_TOOLS_SOFT side effects in
Makevars), and the rows CI4 to CI7 need. Evidence base: stress
45305358893 on d58dc2c (every OS, tree and conda), read row by row.

## Decisions

| id | question | options (chosen in bold) | reason | who |
|---|---|---|---|---|
| D1 | M-3 fix | **`MAKEFLAGS=-j1` on the protolite row (every OS)**; a per-OS env column form; protoc from the Rtools45 tree on PATH | F1: a make -j race in protolite's own Makevars.win, not a toolchain fault; -j1 is the row's only lever; protolite is 3 small sources, so -j1 everywhere costs nothing; no new column syntax | default, 2026-11-24 |
| D2 | M-6 fix | **`EXTRA_CMAKE_FLAGS=-DCMAKE_C_FLAGS=-Wno-error=unused-variable` on arrow and arrow:source**; `ARROW_S3=OFF` (drops S3 coverage on linux and macos-arm64 too: the env column is not per OS); `-mno-avx512f` (the env header still says AVX-512: the same errors); `-Wno-unused-variable` (a later -Wall turns it back on: F4) | F3-F5: makes aws-c-common's AVX-512 probe pass, so the file gets the flags the env's config.h assumes; every OS keeps its S3 build; the root cause (the env's -I before the bundled -isystem) stays chore-release-11 finding 30's later item, not a stress change | default, 2026-11-24 |
| D3 | Longer smoke calls | **`@<file>.R` in the smoke column: stress/smoke/<file>.R, copied into the run's smoke file**; longer one-line expressions | readable, reviewable files; the run's artifact still holds the code it ran | default, 2026-11-24 |
| D4 | M-9 form | **a `local` row, zigcmake (stress/local/zigcmake), Windows only**; a CRAN package that uses CMake configs (none links all four zig-libs configs) | proves find_package/find_library/find_path resolve under zig-libs through R's own Rcmd_environ defaults and r-zig.cmake, and that CMake's link lines link with zig | default, 2026-11-24 |
| D5 | `local` rows' sources | **a directory stress/local/<name>/ copied per install; tinyjobs stays generated**; generate every local package in stress.R | a package is files; STRESS_REPEAT defaults to 1 | default, 2026-11-24 |
| D6 | M-10 checks | **smoke files for hdf5r, sf, terra, fst, magick on every OS, plus a `copies` field in the zig-libs column**; win-arm64-only smokes | the checks are valid on every OS (round trip, EPSG lookup, error path, OpenMP threads); Windows-only parts are guarded by `.Platform$OS.type` | default, 2026-11-24 |
| D7 | W9 form | **`--libs-smoke[=REF]` option (opt-in, git ref or local file), one report line**; a row | it tests four rows' packages together, after them; the script is libs-zig-pixi's, fetched, not copied into this repo | default, 2026-11-24 |
| D8 | Expects | **unchanged** for every row this topic touched; zigcmake `?` | no stress run has these changes yet (task rule: expects only from a run id); the kappa and delta runs below are evidence for the record, not a stress CI run | default, 2026-11-24 |

## Findings

- F1 (V) M-3 cause. stress-45305358893/stress-windows-11-arm-tree/logs/protolite.log: `make: protoc: No such file or directory`
  (no protoc on PATH: libprotobuf left the win-arm64 env, chore-env-ci), then `Rscript.exe ../tools/winlibs.R` starts, then three
  `../windows/protobuf/bin/protoc: No such file or directory` (Error 127) and only then winlibs.R's `[1] TRUE`. protolite 2.4.0
  src/Makevars.win: `$(OBJECTS): $(RWINLIB) $(PROTOCS)` with no edge from `$(PROTOCS)` to `$(RWINLIB)`, so make -j4 runs the protoc
  rules while winlibs.R still downloads. The bundle (protobuf-21.12-clang-aarch64.tar.xz, downloaded on gamma) has
  bin/protoc.exe, lib/libprotobuf.a and lib/libz.a. Whether the link and load then pass: not known until a windows-11-arm run.
- F2 (V) M-6 failure, stress-macos-15-intel-tree/logs/arrow.log (and the conda leg, arrow:source both): `AWS_HAVE_AVX512_INTRINSICS -
  Failed` at configure, then crc32c_sse42_avx512.c:65 `'_mm512_loadu_si512' requires target feature 'avx512f'`; the compile line has
  `-I<env>/include` last (rzig) and no -mavx512f; `CMAKE_C_FLAGS: -O2 -Qunused-arguments -Wall ...` (line 777).
- F3 (V) aws-c-common 0.12.6 cmake/AwsSIMD.cmake: the probe is `__m512 a = _mm512_setzero_ps(); return 0;` with
  `CMAKE_REQUIRED_FLAGS = <AVX flags> -Werror`, after CMAKE_C_FLAGS (-Wall): unused variable, error. aws-checksums 0.2.10
  CMakeLists.txt:81-97 adds the AVX-512 flags to crc32c_sse42_avx512.c only when the probe passed; the file's `#if
  defined(AWS_HAVE_AVX512_INTRINSICS)` reads config.h, which the env's (conda-forge aws-c-common 1.0.x) defines.
- F4 (V) gamma, `zig cc -target x86_64-macos.13.0 -mcpu=baseline <pre> -O2 -Qunused-arguments -Wall -mavx512f ... -Werror -c probe.c`:
  pre empty rc 1; pre `-Wno-unused-variable` rc 1 (the later -Wall turns it on again); pre `-Wno-error=unused-variable` rc 0 (a
  warning). Same with conda-forge zig 0.17.1 and upstream zig 0.16.0 (build/zig-upstream). With the uber flags (-mavx512f
  -mvpclmulqdq -mavx512vl -mavx -mavx2 -mpclmul -msse4.2) and a config.h that defines the macro, crc32c_sse42_avx512.c compiles;
  with -msse4.2 only, 21 errors.
- F5 (V) omicron, osx-64 under Rosetta: an env from universe and conda-forge (micromamba `--platform osx-64`: r-zig-slim
  4.6.2 h9825941_12, r-zig-toolchain _12, zig 0.17.1, aws-c-common 1.0.6, cmake <4.5), a CMake project that FetchContent's
  aws-c-common v0.12.6 and aws-checksums v0.2.10 (arrow 26's versions and URLs' tarballs) with `CC="$(R CMD config CC)"` and arrow's
  C flags: without the flag, probe Failed and the build stops in crc32c_sse42_avx512.c:65 with the CI's errors (20 errors); with
  `-DCMAKE_C_FLAGS=-Wno-error=unused-variable ...`, probe Success, crc32c_sse42_avx512.c compiles, libaws-checksums.a is built.
  (The harness lacked arrow's AWS::aws-c-common alias, so its configure ended in an unrelated target_link_libraries error after
  generating; the aws-checksums target built.) The whole arrow build was not run there (about 20 min on CI, longer under Rosetta).
- F6 (V) nixlibs.R (arrow 26.0.1.1) passes `EXTRA_CMAKE_FLAGS` (Sys.getenv) to inst/build_arrow_static.sh, which splits it on
  spaces into cmake's arguments; the cmake line (arrow.log:38) names no CMAKE_C_FLAGS, so the -D sets it; arrow then appends its own.
- F7 (V) M-2: stress 45305358893, rstan smoke on all four Windows legs: `Error in compileCode(...)`, the message the last 1000
  characters (inline 0.3.21 compileCode: `substr(errmsg, nchar(errmsg) - getOption("warning.length") + 1, ...)`), which held only
  the compile command; the dry run shows `-std=gnu++17` and later `-std=c++1y` (2 hits). The cause (rstan's plugin.R -std=c++1y) is
  b13-rzig's; the smoke now prints inline's whole R CMD SHLIB output (a tracer in compileCode), so the next run shows the
  compiler error.
- F8 (V) CI6: `rzig build: R CMD SHLIB, tier 1` is in Rcpp-smoke.log on all 12 jobs of 45305358893 (cppFunction, showOutput =
  TRUE); in no rstan-smoke.log (0 of 12): inline runs R CMD SHLIB with stderr to a file it deletes after a success, so rzig's
  trace line cannot reach the log. The rzig build roots are gone after the compile (a `.rzig*` listing of tempdir() was empty on
  delta). The rstan smoke file's tracer prints that output, and with it the tier line (delta, Tests).
- F9 (V) CI5 data: RcppParallel:system-tbb (linux, macos) and mlpack (all) rows exist and are ok against their expects on every leg
  of 45305358893 (report.json); lwgeom ok on every leg.
- F10 (V) CI7: magick ok on windows-11-arm (45305358893) with the one-line version smoke; the SVG check is new (smoke/magick.R).
- F11 (V) zig links its own copy of a library zig serves, whatever -L holds: a non-archive `libc++.a` (also libm, libc, libstdc++,
  libc++abi, libunwind, libpthread, libmingwex, libws2_32, libole32, libpsapi, libshell32, libadvapi32, libdbghelp, libgdi32,
  libcrypt32, libuser32, libgcc, libgcc_s) first on -L links (`zig c++ -target aarch64-windows-gnu -shared x.cpp -Lfakelib -l<n>`:
  rc 0), while an unknown `-lfoo` reads the file and fails (rc 1); conda-forge zig 0.17.1 and upstream 0.16.0 alike (gamma). So
  rzig's trace line `lib -lc++ <tree>/lib/libc++.a` (sf, terra, gdalraster, lwgeom on windows-11-arm) names a file zig does not
  read; the DLL has zig's libc++ only. Needs N2 for the trace.
- F12 (V) M-10 copies on 45305358893: the new `copies` check over windows-11-arm and windows-latest tree logs (terra, sf,
  gdalraster, s2, lwgeom, Rsamtools, magick, fst): `none` in each; a log with a second libgeos.a and libproj.a added gives
  `geos (...zig-libs.../lib, c:/other/lib); proj (...)`.
- F13 (I) M-10 C++ exceptions across libc++ versions: the Rtools45 tree libraries the rows take on win-arm64 (report.json
  info.rtools_libs: glpk gmp gsl harfbuzz hdf5 libnetcdf libpq mpfr nlopt udunits2) are C APIs (harfbuzz is C++ inside, built
  without exceptions), and zig-libs' C++ (GDAL, GEOS, PROJ, abseil, oneTBB) is built by zig; with F11 no row throws out of tree
  C++ code. The new error-path checks (sf, terra, hdf5r) and Rcpp's throw cover exceptions inside one zig libc++.
- F14 (V) Q26: CRAN and Bioconductor 3.23 sources downloaded on gamma 2026-11-24 (gert 2.5.0, stringi 1.8.9, qs2 0.4.0, fst 0.9.8,
  fstcore 0.10.0, Rhdf5lib 2.0.0, V8 8.3.0, duckdb 2.0.1, mlpack 4.8.0-1, rstan 2.32.7, StanHeaders 2.39.1.1, RcppParallel 6.2.1,
  DESeq2 1.52.0, systemfonts 1.3.4, geos 0.2.5, libgeos 3.11.1-3, Rsamtools 2.28.0, Rhtslib 3.8.0); `grep -rn
  'R_TOOLS_SOFT|LOCAL_SOFT|RTOOLS4x_HOME'` over Makevars*, configure*, R/ and tools/: only Rhtslib (src/Makevars.win:7-9 adds
  -lnghttp2, -lpsl, -lbrotlidec -lbrotlicommon when `$(R_TOOLS_SOFT)/lib/lib<x>.a` exists; R/zzz.R:19 pkgconfig() repeats it for
  Rsamtools' link via `R CMD config R_TOOLS_SOFT`). Per package: gert, systemfonts, V8: tools/winlibs.R downloads an r-windows
  bundle (no R_TOOLS_SOFT); stringi: bundled ICU (configure.win); qs2: RcppParallelLibs() and bundled zstd; fst/fstcore: own
  sources; Rhdf5lib: cmake via biocmake; duckdb: vendored, -lws2_32 -lrstrtmgr; mlpack, rstan, StanHeaders, DESeq2, geos/libgeos:
  own sources. Makeconf.win's LOCAL_SOFT does not follow R_TOOLS_SOFT (`R_TOOLS_SOFT ?= $(LOCAL_SOFT)`, the other way), so no
  -I/-L comes from it. Effect on win-arm64 (stress.R sets R_TOOLS_SOFT to zig-libs when the env has zig-gdal, else the tree): with
  zig-libs, Rhtslib's three extras drop out, and its -lcurl binds the env's libcurl.lib (trace, windows-11-arm Rhtslib.log), a
  DLL: no need for them; Rsamtools ok on both windows-11-arm legs. With the tree, they would bind the tree's static archives:
  harmless extras. No row change needed.
- F15 (V) W9: github.com/luciorq/libs-zig-pixi is public (gh api: private false, default branch main);
  raw.githubusercontent.com/luciorq/libs-zig-pixi/main/tests/r/smoke.R HTTP 200 (blob eb156427).

## Tests run

| where | command | result |
|---|---|---|
| gamma | `Rscript -e 'parse(...)'` on stress.R, stress/smoke/*.R, local/zigcmake/R/found.R; `awk -F'\t' 'NF!=10'` on packages.tsv; non-ASCII grep | parse ok; 46 rows x 10 fields; ASCII |
| gamma | `Rscript stress/stress.R --help`, `--sysdeps hdf5r protolite arrow`, `--list tinyjobs` | help shows --libs-smoke; hdf5, libprotobuf; plan ok |
| gamma | F4's probe with conda-forge zig 0.17.1 and upstream zig 0.16.0; F11's `-l<n>` with a fake lib<n>.a, both zigs | as in F4 and F11 |
| gamma | `copies()` over 45305358893's windows-11-arm and windows-latest tree logs, and over a terra log with a second libgeos.a and libproj.a | `none` for all; the doctored log lists geos and proj with both directories |
| omicron (osx-64, Rosetta) | F5's aws-c-common + aws-checksums CMake build, build 12 from universe, with and without the flag | without: probe Failed, 20 errors in crc32c_sse42_avx512.c; with: probe Success, libaws-checksums.a built |
| delta (linux-64) | `stress.R --conda=universe --jobs=16 --trace --libs-smoke tinyjobs hdf5r fst magick sf terra s2 gdalraster protolite rstan arrow:source` (build 12 r-zig-slim h3e03716_12, zig 0.17.1; worktree without .git, so commit "unknown") | 11 targets ok, 66 dependencies ok, 0 unexpected; every new smoke file passed; protolite ok with MAKEFLAGS=-j1 (0.58 min); arrow:source ok (5.2 min). libs smoke ran its 21 checks: FAIL on "terra: built with TBB" and "TBB focal uses several threads" (linux terra has no TBB; the script is written for Windows), the other 19 PASS |
| delta | arrow:source again with `ARROW_R_DEV=true` added (STRESS_TSV copy) | ok, 4.8 min; `CMAKE_C_FLAGS: -Wno-error=unused-variable -Qunused-arguments -Wall ...` (the flag reaches libarrow's cmake and the bundled dependencies) |
| delta | the rstan smoke file by hand, `RZIG_TRACE=1`, with the run's library | `[1] TRUE`; the log has `inline's R CMD SHLIB output:` and `rzig build: R CMD SHLIB, tier 1, root .../.rzig.<hash>` (two earlier drafts printed nothing: an exit tracer is replaced by compileCode's own on.exit, and rstan sinks stdout) |
| kappa (win-64) | pixi env from universe and conda-forge (r-zig-slim hb04b5bb_12, r-zig-toolchain, cmake, zig-abseil, zig-gdal, zig-geos, zig-onetbb, zig-openssl, zig-proj, zig-expat, udunits2, libboost-headers); `stress.R --jobs=8 --trace --libs-smoke zigcmake fst magick sf terra s2` with that env's R (conda distribution) | 6 targets ok, 12 dependencies ok, 0 unexpected. zigcmake: absl_DIR, GEOS_DIR, TBB_DIR, expat_DIR, libz.a and expat.h all under Library/zig-libs/x86_64-windows-gnu, CMake (MSYS Makefiles, the env's cmake) linked the probe with zig, which printed abseil-42, GEOS 3.14.1-CAPI-1.20.5, tbb sum 499500, expat 2.7.3. fst: 58 modules, one OpenMP DLL (libomp.dll). magick: rsvg TRUE, SVG 20 x 10. sf: PROJ search path `run/lib/sf/proj`, EPSG 3857, missing read an error. terra: code 3857. copies: none (s2, sf, terra). libs smoke: pass (sf terra s2; 18 checks) |
| hosts | cleanup | kappa `%USERPROFILE%\rz-b13-stress` and omicron `~/rz-b13-stress` removed; delta `~/rz/scratch-b13-stress` and `~/rz/wt/b13-stress` kept (topic dirs) |

## Not verified

- Every row change in a stress CI run: protolite on windows-11-arm, arrow and arrow:source on macos-15-intel, the smoke files on
  macOS and Windows on ARM (linux-64 and win-64 passed on delta and kappa, not in CI), zigcmake on windows-11-arm and in the tree
  distribution (kappa ran the conda one). These need the CI wave (list below).
- The rstan smoke file on Windows (it should now show the -std=c++1y compile error there).
- The fst OpenMP check on windows-11-arm, where the tree's libomp import and the env's libomp meet (kappa win-64 has one libomp).
- arrow as a whole on macos-x86_64 with the flag: only aws-checksums (F5).
- Whether protolite links and loads against r-windows' clang-aarch64 protobuf bundle after the race is gone.

## Rows for the CI wave

- windows-11-arm, tree and conda: protolite, zigcmake, magick, hdf5r, sf, terra, fst, rstan (with --trace and --libs-smoke);
  without --no-rtools-libs and with it (CI4; needs N3).
- windows-latest: zigcmake, magick, fst, sf, terra, rstan, --libs-smoke.
- macos-15-intel: arrow, arrow:source.
- every OS: the smoke-file rows (hdf5r, sf, terra, fst, magick, rstan); ubuntu: RcppParallel:system-tbb, mlpack (CI5).

## Needs from other topics

- N1 (b13-rzig, M-2): the -std=c++1y cause; the rstan row stays `windows=fail-package` until a run shows the fix.
- N2 (b13-rzig, F11): rzig's `lib -l<n>` trace should print `(zig)` for a name zig serves itself, not the first -L file, so the
  zig-libs column's "from the fallback tree" list stops naming c++, m, ws2_32, ole32, psapi, shell32 and the like. stress.R needs no
  change: a value that is not a path is no file there already.
- N3 (workflow owner, .github/workflows/stress.yaml, W9 and CI4): two inputs and their arguments:

```diff
       msys_from_tree:
         description: 'Windows tree legs (stress.R --msys-from-tree): ...'
         type: boolean
         default: false
+      libs_smoke:
+        description: 'stress.R --libs-smoke=REF: after the rows, libs-zig-pixi''s tests/r/smoke.R at this git ref (empty: off) for sf, terra, gdalraster, s2'
+        type: string
+        default: ''
+      no_rtools_libs:
+        description: 'windows-11-arm (stress.R --no-rtools-libs): no Rtools45 aarch64 fallback tree'
+        type: boolean
+        default: false
@@
           STRESS_MSYS_FROM_TREE: ${{ inputs.msys_from_tree }}
+          STRESS_LIBS_SMOKE: ${{ inputs.libs_smoke }}
+          STRESS_NO_RTOOLS_LIBS: ${{ inputs.no_rtools_libs }}
@@
           if [ "$STRESS_MSYS_FROM_TREE" = true ] && [ "$RUNNER_OS" = Windows ]; then args+=("--msys-from-tree"); fi
+          if [ -n "$STRESS_LIBS_SMOKE" ]; then args+=("--libs-smoke=$STRESS_LIBS_SMOKE"); fi
+          if [ "$STRESS_NO_RTOOLS_LIBS" = true ]; then args+=("--no-rtools-libs"); fi
```

## Review

Skeptical pass over the whole diff (2026-11-24). Every file is under `stress/` plus this record: nothing outside the topic.
Line endings: `.gitattributes` `* text=auto eol=lf` covers configure.win and the smoke files (`git check-attr`: eol lf).

Changed:

- R1 stress.R: a smoke `@<file>.R` whose file is missing now stops the run at startup, naming the file (only the selected
  rows are checked), instead of failing inside the row as a harness error.
- R2 stress.R `local_pkg`: a failed copy of stress/local/<p> stops with a message (file.copy returned FALSE silently before, and
  the install then failed on an empty directory).
- R3 stress.R `--libs-smoke`: checks for sf/terra/gdalraster/s2 before downloading the script (no network when it would not run).
- R4 stress.R `copies()`: directories go through normalizePath (winslash "/", mustWork FALSE) before tolower, so one directory
  spelled two ways (`..`, short names) is not reported as two copies.
- R5 smoke/fst.R: the OpenMP DLL match was any module name containing "omp" (compstui.dll matches); now
  `^(lib[gi]?omp|vcomp).*\.dll$` (libomp, libgomp-1, libiomp5md, vcomp140, libomp140.x86_64; checked on gamma).

Kept as is after checking: row_env keeps everything after the first `=` (EXTRA_CMAKE_FLAGS value with two `=`);
the protolite row's MAKEFLAGS=-j1 overrides the global MAKEFLAGS through run()'s Sys.setenv; trace()'s `at` indexes
`body()` the same way the rstan smoke computes it; variant rows (name:variant) do not enter `--libs-smoke` (package field
differs). zigcmake's `CC="$CC"` assumes R CMD config CC has no space in its path (true on the runners and kappa).

Tests re-run after the changes:

| where | command | result |
|---|---|---|
| gamma | parse stress.R and smoke/fst.R; `--list tinyjobs`; `--help`; STRESS_TSV copy with fst's smoke `@nofile.R`, `--list fst` and `--list sf` | parse ok; fst: `Error: no smoke file .../stress/smoke/nofile.R`; sf (row not selected): plan printed |
| delta (linux-64) | `stress.R --conda=universe --jobs=16 --trace --resume --out=run --libs-smoke tinyjobs hdf5r fst sf terra s2` | 6 targets ok, 13 dependencies ok, 0 unexpected; smoke logs rewritten this run; libs smoke FAIL only on the two terra TBB checks, as before (18 checks) |
| kappa (win-64, conda distribution, build 12 r-zig-slim hb04b5bb_12, fresh pixi env in `%USERPROFILE%\rz-b13-stress`) | `pixi run Rscript stress\stress.R --jobs=8 --trace --out=run --libs-smoke zigcmake fst sf terra s2` | 5 targets ok, 10 dependencies ok, 0 unexpected. fst smoke: `modules: 58 ; OpenMP: libomp.dll` (new pattern), TRUE. zigcmake (copied by the new local_pkg path): all six found under `Library/zig-libs/x86_64-windows-gnu`, program printed abseil-42, GEOS 3.14.1-CAPI-1.20.5, tbb sum 499500, expat 2.7.3; R CMD config CC is an 8.3 short path (no spaces). copies (normalized): none for s2, sf, terra. libs smoke: pass (sf terra s2; 18 checks). Scratch dir removed after |

## Suggested commit message

test: stress rows for protolite's make race, arrow's AVX-512 probe, zig-libs CMake configs and runtime smokes
