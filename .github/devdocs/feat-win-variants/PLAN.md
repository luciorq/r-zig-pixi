# feat-win-variants — one variant table for every OS

**Status (2026-11-15).** Part of the release-11 pull request (#48),
implemented in the integration tree T/wt/rel11-int. Built and tested on
linux-64 and on kappa (win-64): every check passed (see "Tests").
win-arm64 and macOS are CI only (the full tier). Not committed: the
user commits. Recipe build number stays 11.

## Why

chore-release-11/PLAN.md, finding 23. On kappa, `pixi run recommended`
failed for Matrix, nlme, cluster, foreign and rpart: "fatal error:
'libintl.h' file not found". build.zig always built Windows as full, so
Rconfig.h defined ENABLE_NLS, but R_HOME/include had no libintl.h. R's
own Windows build installs one (src/extra/intl/Makefile.win:8-10).

The user's decision (2026-11-14): Windows follows the unix variants.
"Good opportunity to match configs across variants and remove OS
specific workarounds." Windows stops being "always full". slim, full
and minimal exist on Windows with the same features as on unix.

This replaces B42 (feat-standalone-toolchain/PLAN.md, 2026-10-08):
"Windows slim has full's content".

## The variant table

build.zig `variantFeatures(variant, os)` is the one source. On every
build, `checkVariantConfig` compares the vendored config.h, Rconfig.h
and subst.txt with it, and stops with one error line per mismatch
(`error.VariantConfigMismatch`).

| Feature | Where it shows | slim | full | minimal |
|---|---|---|---|---|
| NLS | ENABLE_NLS (config.h, Rconfig.h) | off | on | off |
| tcltk | HAVE_TCLTK, TCLTK_LIBS | off | on | off |
| jpeg | HAVE_JPEG, -ljpeg in BITMAP_LIBS | off | on | off |
| tiff | HAVE_TIFF, -ltiff in BITMAP_LIBS | off | on | off |
| png | HAVE_PNG | on | on | off |
| cairo | BUILD_DEVCAIRO_TRUE (cairo.so, winCairo.dll) | on | on | off |
| ICU | USE_ICU (Windows: ICU_LIBS) | on | on | off |
| libdeflate | USE_LIBDEFLATE (Windows: LIBDEFLATE_LIBS) | on | on | off |
| OpenMP for packages | SHLIB_OPENMP_CFLAGS, libomp in the base | on | on | off |
| OpenMP inside R | SUPPORT_OPENMP, HAVE_OPENMP_SIMDRED, R_OPENMP_CFLAGS | on | on | off |
| readline | HAVE_LIBREADLINE | off | unix on, Windows off | off |
| memory profiling | R_MEMORY_PROFILING | Windows on, unix off | same | same |

The same on every OS (linux, macOS, win-64, win-arm64), except:

- **OS-inherent, not the variant's choice.**
  - readline: unix full only. Windows R has its own console line
    editing (getline).
  - R_MEMORY_PROFILING: each OS keeps upstream's default. gnuwin32's
    fixed config.h defines it; unix configure leaves it off. Not
    changed here (decision below).
  - HAVE_OPENMP: on Windows it follows the table. On unix it is
    configure's probe result and is also 1 in minimal (linux); minimal
    has SUPPORT_OPENMP and R_OPENMP_CFLAGS off, so R uses no OpenMP.
    checkVariantConfig checks HAVE_OPENMP on Windows only.
  - ICU_LIBS and LIBDEFLATE_LIBS are Windows-only subst keys, named as
    in gnuwin32's MkRules.rules. unix has no such keys: its ICU and
    libdeflate flags sit in LIBS. On unix the check reads USE_ICU and
    USE_LIBDEFLATE from config.h only.

- **Deliberate deviations from upstream R on Windows.**
  - OpenMP inside R. Upstream leaves it off on Windows only, because
    MinGW's libgomp was "too slow to be usable"
    (gnuwin32/fixed/h/config.h:609-613, main/Makefile.win:58). r-zig
    links LLVM's libomp on every OS. Windows slim and full define
    HAVE_OPENMP, SUPPORT_OPENMP and HAVE_OPENMP_SIMDRED, as unix does.
    R's own C is compiled with -fopenmp, and R.dll, the lapack and
    internet modules and stats.dll link libomp. win-64 gets conda's
    llvm-openmp, win-arm64 the zig-built llvm-openmp (`zig_*`, universe
    channel), and libomp.dll is vendored into bin/x64. R's own code has
    real parallel regions: colSums()/colMeans() (array.c, 10
    firstprivate values, entered even with 1 thread) and stats' dist()
    (distance.c, with more than 1 thread). These are the region shape
    that broke in conda-forge's win-arm64 libomp (more than six shared
    values, feat-win-arm64 PLAN.md). smoke-test.sh and recipe/test-win.R
    run both with 1 and 4 threads (2026-11-14, review); on win-arm64
    they run in CI only.
  - TCLTK_CPPFLAGS and TCLTK_LIBS in etc/x64/Makeconf are tokens: the
    upstream values where the variant has tcltk, empty otherwise, as in
    unix's slim Makeconf. Upstream's Makeconf keeps them fixed even when
    R is built without tcltk. `R CMD config TCLTK_LIBS` must print an
    empty line on Windows slim (not yet run on Windows).
  - The winbitmap patch, below. Upstream never turns a bitmap format
    off on Windows.

## What changed

### build.zig

- `Features`, `variantFeatures` and `checkVariantConfig`. The forced
  `variant = .full` and the Windows minimal reject are gone.
  `ctx.openmp`, `ctx.openmp_pkgs` and `ctx.devcairo` come from subst.txt
  on every OS.
- Windows sites follow the table:
  - grDevices gets -DHAVE_PNG/-DHAVE_JPEG/-DHAVE_TIFF from the table,
    BITMAP_LIBS, and -lz on every variant (devPS.c calls zlib's
    compress(); a PE DLL does not get zlib through R.dll).
  - winCairo.dll only with cairo.
  - tcltk.dll, R_HOME/Tcl and Renviron.site's MY_TCLTK only with
    tcltk. The tcltk stub is R/unix/zzzstub.R, as upstream's
    tcltk/Makefile.win:31.
  - libintl.h is installed into R_HOME/include when the variant has
    NLS (the finding-23 fix). R's other include files are unchanged
    (decision below).
  - R.dll links WIN_R_DLL_LIBS + ICU_LIBS + LIBDEFLATE_LIBS.
- Unix sites read the same table (tcltk, readline). linux-64 slim's
  libR.so is byte-identical to the 2026-11-13 build.

### The win-* config dirs

- Three vendored dirs: zigbuild/config/win-slim, win-full and
  win-minimal. Windows has no configure, so they are not generated.
  config.h and Rconfig.h are R's src/gnuwin32/fixed/h/ files with
  r-zig's edits: HAVE_CURL_CURL_H and HAVE_LIBCURL (the internet
  module), USE_ICU and the OpenMP defines where the variant has them,
  and each define of the table flipped to the variant's value. Each dir
  has a PROVENANCE file that lists these edits. GENERATED_FROM holds
  only the R version, because `checkConfigFreshness` reads it.
- subst.txt is written by hand from upstream's Makefile.win link lists:
  one key per feature (BITMAP_LIBS, TCLTK_LIBS, CAIRO_LIBS,
  BUILD_DEVCAIRO_TRUE, R_OPENMP_CFLAGS, SHLIB_OPENMP_CFLAGS, ICU_LIBS,
  LIBDEFLATE_LIBS), plus the WIN_* lists that every variant shares.
  WIN_BITMAP_LIBS and WIN_TCLTK_LIBS are gone, and WIN_R_DLL_LIBS no
  longer holds -ldeflate or -licu*.
- One Makeconf template for every Windows variant:
  zigbuild/config/win-common/Makeconf.win (was win-full/Makeconf.win).
- To regenerate after an R update: start again from the new
  fixed/h files and apply the edits in PROVENANCE. checkVariantConfig
  catches a define that drifts from the table. gen-config.yaml does not
  cover Windows; its header says so.

### The winbitmap patch

zigbuild/patches/R-4.6.2/0015-winbitmap-stubs.patch adds `#else` stubs
to src/library/grDevices/src/winbitmap.c for R_SaveAsPng, R_SaveAsJpeg
and R_SaveAsTIFF. devWindows.c and cairo/cairoBM.c call them with no
guard, so without stubs grDevices.dll and winCairo.dll do not link when
a format is off. Each stub gives the warning of unix's rbitmap.c ("No
jpeg support in this version of R") and returns 0. So jpeg() and tiff()
on slim, and png(type = "windows") on minimal, fail at run time as on
unix. full compiles the real code, unchanged. The patch is
upstreamable.

### pixi.toml, pixi.lock and the recipe

- [target.win.dependencies]: libjpeg-turbo, libtiff, tk and gettext are
  gone; zstd is explicit (R.dll links -lzstd). Windows full keeps tk
  (feature.tcltk) and jpeg/tiff (feature.img-formats). Windows NLS is
  R's own src/extra/intl, so feature.nls stays unix only.
- glib moved to [target.unix.dependencies]: on Windows it brought
  python, and python brought tk and libintl-devel back into slim. R's
  Windows build uses no glib.
- [feature.minimal] has win-64 and win-arm64, with its own Windows
  table (llvm-tools, zstd, the m2-* tools; win-64 uutils-coreutils). No
  pkg-config there: conda-forge's Windows pkg-config brings libglib and
  libffi, which minimal-deny.txt forbids.
- Re-locked with pixi 0.84.2. Only Windows entries changed, and only by
  removals; minimal is new on win-64 and win-arm64. The diff:
  T/rel11/var/lock-diff.txt.
- The recipe: Windows r-zig-slim is slim (no tcltk, jpeg, tiff or NLS).
  recipe/test-win.R checks the slim profile, draws with svg() and
  png(type = "windows"), and expects jpeg(), tiff() and library(tcltk)
  to fail cleanly. Build number 11.

### Scripts

- smoke-test.sh: one path for every OS. It checks capabilities()
  against the table, then functional checks. On Windows,
  capabilities() for png, jpeg, tiff, tcltk, NLS and ICU only reflects
  config.h (platform.c), so the functional checks matter:
  - png(), jpeg() and tiff() (type = "windows" on Windows) write a file
    where the variant has the format, and give a warning or error where
    it does not;
  - full loads tcltk and runs `.Tcl`; slim and minimal give the stub's
    "Tcl/Tk support is not available";
  - full translates a base message to German (required on Windows).
- verify-tree.sh: libR (R.dll) links libomp in slim and full, not in
  minimal; Windows grDevices.dll imports exactly its variant's bitmap
  libraries; Windows without tcltk has no tcltk.dll, no R_HOME/Tcl, an
  empty TCLTK_LIBS and no MY_TCLTK; Windows minimal lists R's own PE
  files by name (R.dll, Rblas.dll, Rlapack.dll, Rgraphapp.dll,
  Riconv.dll, the R*.exe, modules/x64/*.dll, library/*/libs/x64/*.dll)
  and checks they import no excluded library. The conda DLLs vendored
  into bin/x64 are transitive (ICU comes through libcurl → libpsl) and
  are reported, not failed.
- verify-recommended.sh: a name in R CMD INSTALL's temp directory
  (`<temp>/Rtmp<x>/R.INSTALL<hex>/`) is not a build path. The help
  files keep the Rd files' names there (help/paths.rds, the help
  .rdx). On Windows %TEMP% is inside USERPROFILE, which the check
  searches; on unix /tmp is not searched. Unix output is unchanged.
- hermetic-check.sh loads tcltk on Windows only when
  `capabilities("tcltk")`. contract-test.sh reads Makeconf from
  `etc/<r_arch>/`. check-minimal.sh reads its platforms from pixi.toml.

### CI

- build.yaml's full tier gains four legs: full and minimal on
  windows-latest (90 minutes) and windows-11-arm (150 minutes), with
  `-- --verbose`, as the core tier's Windows legs. Full tier: 20 legs
  (was 16). Core tier: unchanged, 7 legs; its Windows legs are now
  really slim.
- build-r.yaml: verify-tree and hermetic run for env full too, on every
  OS. full is the only Windows variant with tcltk.dll, R_HOME/Tcl and
  libintl.h; without this, nothing in CI checks them. One rule for every
  OS keeps the file simple, and the checks are cheap. linux-64 full
  passed both locally (feat-zig-017); macOS full runs them first in CI.
  openblas still skips them (it differs only in BLAS).
- build-r.yaml: the wheel env and the wheel steps only on unix minimal.
  There is no Windows wheel yet.
- upstream-zig.yaml: no Windows full leg. The variant changes defines
  and link lists, not how zig compiles. The file's comment says so.

## Decisions (user, 2026-11-14)

- Bitmap formats that are off: the winbitmap patch (above).
- OpenMP inside R on Windows as on unix (above).
- Release 11 ships the slimmer Windows r-zig-slim. Build number 11.
- CI: as above.
- One shared Makeconf.win template; three vendored win-* dirs checked
  against the table; conda's gettext dropped on Windows; only
  libintl.h added to R_HOME/include; R_MEMORY_PROFILING unchanged.

## Tests

Run on gamma (linux-64), 2026-11-14:

- `zig build -l` for linux-x86_64 slim, full and minimal (this compiles
  build.zig's Windows branch too).
- slim build into a clean prefix; smoke and verify-tree passed. Against
  the 2026-11-13 slim archive: the same file list; Makeconf, Renviron,
  ldpaths and the headers byte-identical; libR.so byte-identical.
- Negative test: HAVE_JPEG undefined in a scratch copy of
  linux-x86_64-full/config.h stops the build with VariantConfigMismatch.
- A Python copy of checkVariantConfig passes for all 15 config dirs.
- rzig-test; `pixi run -e minimal minimal-check` (6 platforms);
  `pixi lock --check`; a recipe render for win-64, win-arm64 and
  linux-64.
- `zig cc -target {x86_64,aarch64}-windows-gnu`: the patched
  winbitmap.c in all three variants; main/array.c, options.c,
  platform.c, util.c and stats/distance.c with each win config.

Round 1 on gamma (linux-64), 2026-11-14: slim, full and minimal built
into clean prefixes. Each tree matches the baseline (file list,
Makeconf, Renviron, headers, libR.so NEEDED/RUNPATH/SONAME; R's
binaries byte-identical). Every check passed except `pixi run -e
minimal smoke`: unix minimal has no cairo, so png() is type Xlib and
gives the error "X11 is not available". The new smoke check took an
error for silence (it counted messages). Fixed: only "drawn" with no
file and no message fails. After the fix: smoke passed for slim, full
and minimal; verify-recommended passed (slim).

Round 1 on kappa (win-64), 2026-11-14: 27 of 29 steps passed. slim,
full and minimal built; smoke, verify-tree, hermetic, contract and the
functional checks passed on all three. Matrix, nlme, cluster, foreign
and rpart install and load on slim and full. On full, libintl.h is in
R_HOME/include and Matrix.dll imports libintl_dgettext from R.dll.
R.dll imports libomp.dll on slim and full, not on minimal. grDevices.dll
imports libpng16.dll (slim), libpng16.dll, jpeg8.dll and tiff.dll
(full), and no bitmap DLL (minimal). verify-recommended failed for
slim and full: help/paths.rds and help/<pkg>.rdx name
`C:/Users/admin/AppData/Local/Temp/Rtmp<x>/R.INSTALL<hex>/...`.
Fixed in verify-recommended.sh (above). Checked on gamma: with /tmp
added to the patterns, the R.INSTALL names pass and other /tmp names
still fail.

Round 2 on kappa (win-64), 2026-11-14, after the two script fixes:
45 of 45 tasks OK (21:08 to 22:37). verify-recommended passes for slim
and full ("30 files name only R CMD INSTALL's temp directory"); slim's
`R CMD config TCLTK_LIBS` prints an empty line.

Round 3 (the final run), 2026-11-14/15, after the review fixes (the
OpenMP checks: colSums, colMeans and dist() with 1 and 4 threads, in
smoke-test.sh and test-win.R): on linux-64, slim, full and minimal
match the baseline again and every check passed. On kappa, 31 of 31
tasks OK (22:55 to 00:07, log T/rel11/var/kappa-r9.log): for slim,
full and minimal: build, smoke ("OpenMP regions (colSums, dist) OK"
on slim and full), verify-tree, hermetic, contract and the functional
checks; recipe/test-win.R on the slim tree; recommended,
verify-recommended and the Matrix.dll import check for slim and full.

The kappa slim build log has a line `failed command: flang -O2 -c
...dlamch.f` after flang's -Wfolding-exception warning, and the build
ends OK. Not investigated.

Not yet run:

- pkg-parity on kappa.
- win-arm64: CI only (the full tier's new legs).
- macOS: CI only.
- The conda package on Windows (CI's conda-package job; test-win.R).

## Later

- `-Dblas=openblas` on Windows: build.zig ignores it there, and the
  openblas envs still lock win packages.
- R_HOME/include parity with src/include/Makefile.win: iconv.h,
  graphapp.h and ga.h are not installed, and Rinterface.h is. No package
  has failed on this yet.
- Splitting pixi.toml [dependencies] into toolchain and library
  features, so minimal need not repeat the toolchain block. It re-solves
  every env on every platform.
- R_MEMORY_PROFILING: on for Windows, off for unix, as upstream.
  Unifying it changes unrelated behaviour.
- fontconfig, freetype and expat are still in the Windows envs and the
  recipe's Windows deps; Windows R uses none of them.
