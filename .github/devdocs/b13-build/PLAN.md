# b13-build: fetch, capture, BLAS contract, make with zig, build tools

Build 13, topic b13-build, from main 7e3648e (worktree, uncommitted).
Backlog rows: chore-release-12/BACKLOG.md M-20, M-17, M-25, M-7, M-23, L7.
Tested on delta (linux-64), with cross-builds checked on kappa (win-64)
and omicron (osx-arm64).

## Goal

- M-20: `zig build fetch` replaces scripts/fetch-r.sh, same sources and
  sha256.
- M-17: gen-config's configure capture runs rzig; the bash shims in
  toolchain/ (841 lines) go; the captured configs stay identical.
- M-25: B39's restricted-PATH run, then trim the build-tools list to what
  is used.
- M-7: `-Dblas=openblas` on Windows (chore-env-ci F2: buildWindows ignored
  it).
- M-23: the BLAS link contract for binary packages.
- L7: GNU make built with zig, for the build-tools group.
- `pixi run build`, verify-tree and smoke stay green on delta with
  conda-forge zig and upstream zig.

## Decisions

All defaults (default, 2026-11-24), under the batch approval.

| id | question | options (chosen ★) | reason |
|---|---|---|---|
| D1 | How `zig build fetch` works | (a) build.zig.zon lazy dependency; (b) ★ a `fetch` step running a host tool, zigbuild/tools/fetch.zig (std.http.Client, CRAN then cloud.r-project.org, 3 tries each, sha256 against scripts/checksums/, std.compress.flate + std.tar into build/R-<ver>, the empty `.r-zig-patches` stamp); (c) keep fetch-r.sh | (a) ruled out in wave2-build's design (zig's package hash is not the pinned sha256, one URL, read-only cache, zig-build.sh patches the tree in place). (b) is wave2-build's design |
| D2 | Who runs it when the tree is missing | (a) build.zig's install step depends on fetch (impossible: build.zig's configure reads the tree); (b) ★ scripts/zig-build.sh runs `zig build fetch` when `$SRC_DIR/configure` is missing, and `zig-build.sh fetch` does only that (pixi's `fetch` task, Needs N1); build.zig with no tree registers `fetch` and a fail step for every other step | Without a tree build.zig can only offer `fetch`; with one, a `zig build fetch` would configure the whole build for nothing (the tool itself also exits at once when `configure` exists) |
| D3 | File times of the extracted tree | (a) extraction time (std.tar's behaviour); (b) ★ the tar headers' mtimes (files and directories, ustar/GNU long name/pax), as tar sets them | (a) changed lib/R/doc/NEWS.rds, NEWS.2.rds and NEWS.3.rds: they keep NEWS.Rd's mtime in a srcref (F4) |
| D4 | Which rzig the capture runs | (a) the main build.zig's `zig build rzig` (needs a fresh vendored config: fails on the stale one being replaced, checkConfigFreshness); (b) ★ rzig's own build.zig (no R source, no config), installed into build/capture-rzig/bin, copied as zig-cc, zig-cxx, zig-ar and zig-ranlib; (c) symlinks | (b) works with a stale config; copies because rzig dispatches on its name and resolves its own path for its environment. Outside OBJ_DIR/SRC_DIR/PREFIX, which gen-subst.sh replaces before @ZR_TOOLCHAIN@ |
| D5 | The shims | (a) ★ deleted; rzig's parity-test.sh and smoke-test.sh part 1, whose reference they are, lose that comparison (Needs N3); (b) moved under zigbuild/tools/rzig/testdata as the parity reference | The backlog item is their removal; rzig is the tested implementation (unit tests, contract, stress). (b) stays open to the rzig owner |
| D6 | M-23: the BLAS link contract | (a) ★ every flavor ships libRblas and libRlapack (Rblas.dll, Rlapack.dll) and Makeconf's BLAS_LIBS/LAPACK_LIBS name them in every flavor (`-lRblas`, `-lRlapack`); in the openblas flavor they are forwarders to openblas; (b) libRblas.so a symlink to libopenblas (conda-forge r-base's way: a package then records libopenblas's SONAME); (c) as before, `-lopenblas` in Makeconf and no libRblas | (a) makes a package's binary name the same libraries whichever flavor built it, so it loads in both (F6 on linux, F7 for Windows' mechanism; macOS: D9). The openblas BLAS_LIBS override in build.zig goes (the vendored config's lines are right again) |
| D7 | Forwarder form | linux/macOS: ★ an empty library (a Zig file referencing openblas_get_config) linked with openblas `needed`, SONAME libRblas.so/libRlapack.so, rpath `$ORIGIN/../..`; Windows: ★ Rblas.dll with Rblas.def's 76 exports forwarded to `openblas.<name>` plus one real import of openblas.dll | The reference keeps the dependency in the DT_NEEDED/import table, which vendor-libs.sh and verify-tree.sh follow (a forwarded export alone puts no DLL in the import table) |
| D8 | M-7: what changes on Windows | (a) ★ Rblas.dll only (forwarder), Rlapack.dll stays R's LAPACK, as R's own USE_OPENBLAS build (src/extra/blas/Makefile.win); (b) Rlapack.dll forwarded too | (a) is upstream R's Windows openblas build; Rlapack.dll has no .def to forward from |
| D9 | macOS packages built on the internal tree, loaded in the openblas tree | (a) ★ not solved now, recorded; (b) libRblas.dylib as a renamed copy of libopenblas (install_name_tool + re-sign: post-processing) | zig 0.17's Mach-O linker has no re-export (`error: unsupported linker arg: -reexport-l`, `-reexport_library`; F8); a two-level binding to libRblas needs one. Packages built on the openblas tree link with `-undefined dynamic_lookup` and load in both |
| D10 | L7: where make is built | (a) ★ its own build, zigbuild/make/build.zig (lazy ftp.gnu.org tarball, sha256 dd16fb1d...; `-Dsource=<dir>` for the recipe; vendored config per OS); (b) a step of zigbuild/toolchain/build.zig | Same shape as zigbuild/recommended/ and the toolchain build; wiring it into the build-tools group (recipe output, toolchain build's usr/bin/make, verify-toolchain's SOURCES checks) is Needs N5 |
| D11 | L7: make's configuration | ★ linux: config.h from its configure run with `zig cc -target x86_64-linux-gnu.2.17`; macOS: from a cross configure (`aarch64-macos.13.0`), HAVE_GETTIMEOFDAY and HAVE_STRCOLL set by hand (the cross run's "no (cross-compiling)"); Windows: the release's src/config.h.W32; CPU macros and MAKE_HOST left to the compiler/build.zig | No configure at build time, as R's vendored config |
| D12 | L7 on Windows | (a) ★ built (x86_64, aarch64) but the build-tools group keeps MSYS2's m2-make; (b) replace m2-make | PHASE7 open point B (a) still holds: msys-2.0.dll ships for sh/sed/grep/gawk anyway, and a native make quotes for MSVCRT and runs `echo` as a program |
| D13 | M-25: how to see which tools run | (a) ★ NTFS last-access times on kappa (DisableLastAccess = 2, enabled): every usr/bin file's set to 2001-01-01, package installs with PATH = bin\x64 + System32 (the tree's build-tools group alone), then the files with a newer time; (b) a tracing wrapper per tool | (a) needs no change to the tools; the probe (true.exe) shows a run updates the exe and the DLLs it loads (F10) |
| D14 | M-25: what to trim | (a) keep every file (PHASE7 C a); (b) ★ leave out 35 files no build runs (m2_exclude in zigbuild/toolchain/build.zig: bug-report scripts, gawk's version-named copy, locate/updatedb, tar's backup/restore, coreutils' SELinux, terminal, login, disk and interactive programs); (c) only what ran (15 files) or B39's names (52 files) | (c) has no margin: the run's failing packages stopped at a missing library before their later tools, and configure scripts call coreutils beyond any list (PHASE7 C a). (b) keeps every name any run used or verify-toolchain.sh checks, and anything a later m2 release adds; it saves 3,264,843 bytes raw, 1,340,999 zipped (13% and 12% of usr/bin), measured on build 12's win-64 build-tools zip |
| D15 | M-25 on linux | ★ nothing to trim: the unix build-tools group is usr/bin/make alone (the toolchain build's unix dirs; delta's tree: `usr/ (make)`) | B39's list is Windows' |

## Findings

- F1 (V) Fetch, delta: `pixi run fetch` (pixi.toml patched as N1, on
  delta only) from nothing: downloaded from CRAN, "Checksum OK",
  extracted. The tree equals GNU tar's extraction of the same tarball:
  `find -printf '%y %m %s %p %l'` lists, normalised to type, exec bit,
  size, path and link target, differ only in `.r-zig-patches` (5458
  entries, 16 symlinks). Again with the tarball present: 0.9 s; with the
  tree present: 0.25 s ("already present").
- F2 (V) fetch.zig's paths (delta, `zig build-exe` of the tool): CRAN 404
  -> next URL (cloud), checksum file missing -> pinned
  (`c297040f...  R-4.6.2.tar.gz`, same as scripts/checksums); pinned
  `0000` -> "checksum mismatch", exit 1, tarball removed; unknown host ->
  3 tries, exit 1.
- F3 (V) Other OSes (the tool cross-built on delta for
  x86_64/aarch64-windows-gnu, x86_64/aarch64-macos, aarch64-linux): kappa
  (x86_64 windows) downloaded, checksum equal, 5143 entries with the 16
  symlinks made (developer mode); omicron (arm64) the same (5127 files +
  16 links), but only from a path LuLu allows (`~/.pixi/rz-b13-build`;
  from `~/rz-b13-build` every try failed with UnknownHostName: LuLu
  blocks a binary at a new path, chore-release-11 finding 11). The
  Windows symlink-skip path (no developer mode) is not exercised.
- F4 (V) Without D3, the tree built after a zig fetch differed from the
  GNU-tar baseline in 63 files: the 33 `Built:`-time files of wave2-build
  F5's kind (DESCRIPTION, Meta/package.rds, methods.rdb/rdx, tools.rdb) plus
  doc/NEWS.rds, NEWS.2.rds, NEWS.3.rds, whose srcref holds NEWS.Rd's
  timestamp (`all.equal`: "srcfile ... timestamp: Mean absolute difference:
  3081129"). With D3: the mtimes of all 5126 files equal GNU tar's; the
  tree differs from the baseline in the 33 `Built:` files only (15
  DESCRIPTION, 15 package.rds, methods.rdb/rdx, tools.rdb).
- F5 (V) Capture, delta, linux-64: configure + gen-subst.sh with the shims
  (main's code) gives the vendored zigbuild/config/linux-x86_64-{slim,
  minimal,full} byte for byte except CC_VER/FC_VER (stale clang 21.1.8 /
  flang 23.1.1 lines, which build.zig rewrites; known, chore-release-11
  item 4). With rzig (D4): `diff -r` against the shim captures is empty
  for all three variants (config.h, Rconfig.h, subst.txt,
  GENERATED_FROM). configure's log names build/capture-rzig/bin/zig-cc.
- F6 (V) M-23 on linux (delta): the openblas tree has lib/R/lib/libRblas.so
  and libRlapack.so (NEEDED libopenblas.so.0, SONAME libRblas.so /
  libRlapack.so, RUNPATH `$ORIGIN:$ORIGIN/../..`), Makeconf's BLAS_LIBS and
  LAPACK_LIBS equal the internal tree's. quadprog 1.5-8 (`PKG_LIBS =
  $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`) installed in each tree and loaded
  in each, solve.QP and crossprod checked: all four combinations pass;
  sessionInfo's BLAS is libRblas.so in the internal tree and
  libopenblas.so.0 in the openblas tree whichever tree built quadprog.
  The internal-built quadprog.so needs libRblas.so; the openblas-built one
  needs neither (lld's as-needed drops the empty forwarder; its symbols
  resolve in what libR loads).
- F7 (V) M-7 on Windows, without a Windows R build: conda-forge's win-64
  libopenblas 0.3.34 ships Library/bin/openblas.dll, its openblas package
  Library/lib/openblas.lib; openblas.dll exports all 76 names of R's
  src/extra/blas/Rblas.def. A scratch build of winBlasForwarder's exact
  module, .def and link (delta, x86_64-windows-gnu, against that
  openblas.lib) gives Rblas.dll with 76 "Forwarder RVA --
  openblas.<name>" exports and openblas.dll in its import table; a program
  linked against its import library, run on kappa beside openblas.dll,
  prints ddot's 14.
- F8 (V) zig 0.17.1 (conda-forge) rejects every Mach-O re-export spelling:
  `-Wl,-reexport-lopenblas`, `-Wl,-reexport_library,<dylib>`,
  `-Wl,-reexport-l,openblas` -> "error: unsupported linker arg".
- F9 (V) GNU make 4.4.1 with zig (delta): `zig build --build-file
  zigbuild/make/build.zig test install` builds and runs; linux-x86_64
  binary needs GLIBC_2.17 at most. GNU make's own test suite
  (`run_make_tests.pl`) against it and against the env's conda-forge
  make 4.4.1: 133 ok each, the same one failure
  (functions/wildcard test 10, identical diff: a host-dependent
  directory). Before `exe.rdynamic` the zig make failed features/load and
  features/loadapi (a loaded object could not find gmk_*). Cross-builds:
  aarch64-linux, x86_64-macos, aarch64-macos (minos 13.0), x86_64- and
  aarch64-windows. omicron: the arm64 make runs a pattern-rule makefile
  with -j4 and `$(shell)`; kappa: make.exe (`Built for Windows32`) runs one
  with cmd.exe recipes (`copy`).
- F10 (V) kappa: after resetting usr/bin's access times, running
  usr/bin/true.exe updated true.exe, msys-2.0.dll, msys-iconv-2.dll and
  msys-intl-8.dll only.
- F11 (V) M-25 on kappa: build 12's win-64 base, compilers, build-tools
  and extras archives (run 45381914199) extracted; usr/bin's 139 files'
  access times reset; `install.packages(type = "source")` of 30 packages
  (stringi, fs, processx, ps, cli, data.table, Rcpp, fst, qs2, geos,
  RcppParallel, httpuv, curl, openssl, xml2, magick, Rmpfr, gert, units,
  nloptr, igraph, RPostgres, ncdf4, hdf5r, gsl, V8, sass, jsonlite, zip,
  rlang) with PATH = the tree's bin\x64 + System32, so R CMD's PATH gave
  the group's tools alone: 50 packages installed (dependencies included);
  fs, data.table, httpuv, xml2, magick, gmp/Rmpfr, gert, units, nloptr,
  igraph, ncdf4, hdf5r, gsl and sass failed, each on a library the
  machine lacks (uv.h, gmp.h, glpk.h, `-liconv`, pkg-config's "Package
  'libxml-2.0' not found"); no "command not found" in the log. Files run
  (newer access time): basename, cat, cp, cut, echo, make, pkg-config, rm,
  sed, sh, touch, tr and msys-2.0.dll, msys-iconv-2.dll, msys-intl-8.dll:
  15 of 139.
- F12 (I) The recipe (recipe/recipe.yaml) fetches R's tarball itself
  (rattler-build `source:`), so fetch-r.sh served only pixi's `fetch`
  task and zig-build.sh; no workflow calls it (`grep -rn fetch-r
  .github/workflows` is empty).
- F13 (V) The 35 files of D14 are none of: F11's 15, phase 7's run names
  (feat-standalone-toolchain PLAN.md B39 "Phase 7": sh, make, coreutils,
  sed, awk, grep, find, xargs, which in no row), verify-toolchain.sh's
  name list (scripts/verify-toolchain.sh:410-412), verify-bundle's btTools
  steps, tar and patch (their rows). `pixi run toolchain-test`,
  `toolchain` and `verify-toolchain` pass on delta (linux; the Windows
  tree is not built here).

## Tests run

| where | command | result |
|---|---|---|
| delta | baseline (main's code): `pixi run build -j16`, `verify-tree`, `smoke` | 0, 0, 0 (4m22s) |
| delta | shim captures: `pixi run -e {default,minimal,full} configure` + gen-subst.sh | 0; equal to vendored but CC_VER/FC_VER (F5) |
| delta | rzig captures, same | 0; equal to the shim captures (F5) |
| delta | `pixi run fetch` (N1 applied on delta), download + extract, then again | F1 |
| delta | fetch.zig failure paths | F2 |
| kappa, omicron | fetch.zig cross-built, run | F3 |
| delta | conda-forge zig 0.17.1: `pixi run build -j16`, `verify-tree`, `smoke` (default) after a zig fetch | 0, 0, 0; tree vs baseline F4 |
| delta | conda-forge zig: `pixi run -e openblas build`, `verify-tree`, `smoke` | 0, 0, 0 ("installed tree verified (linux/slim-openblas)") |
| delta | M-23 cross-load (quadprog) | F6 |
| delta, kappa | Windows forwarder scratch build, run | F7 |
| delta, omicron, kappa | zigbuild/make build, test suite, cross-builds | F9 |
| delta | `zig fmt --check build.zig zigbuild/tools/fetch.zig zigbuild/make/build.zig` | clean |
| delta | upstream zig 0.17.1 (`ZIG_BIN=$(pixi run fetch-zig)`): `pixi run fetch` (fetch.zig built by it), `build -j16`, `verify-tree`, `smoke`, default and openblas | all 0 |
| delta | upstream zig: `pixi run configure` + gen-subst.sh (slim; rzig built by upstream zig) | differs from the shim capture in CC_VER only ("clang version 22.1.8", upstream zig's clang string, which build.zig rewrites anyway) |
| delta | upstream zig: `zig build --build-file zigbuild/make/build.zig test install` | 0, "GNU Make 4.4.1" |
| delta | build.zig with no source tree: `zig build --prefix ... -Dvariant=slim -Dblas=internal` | exit 1, "error: R source tree not found at build/R-4.6.2: run `zig build fetch` first (scripts/zig-build.sh does)" |
| delta | final state (after the last edits): `zig fmt --check`, `pixi run build -j16`, `verify-tree`, `smoke` (conda-forge zig) | 0, 0, 0, 0 |
| kappa | M-25 last-access run (F10, F11) | 50 packages installed, 15 of 139 usr/bin files ran |
| delta | `zig fmt --check zigbuild/toolchain/build.zig`, `pixi run toolchain-test`, `toolchain`, `verify-toolchain` | 0, 0, 0, 0 |

## Not verified

- The capture on osx-64 and linux-aarch64 (osx-arm64 slim: Review R3).
  The gen-config workflow runs on its own when this branch is pushed
  (configure-only.sh is in its `paths`); its artifacts should equal the
  vendored configs but CC_VER/FC_VER.
- `zig build fetch` behind a proxy (initDefaultProxies reads
  HTTPS_PROXY/ALL_PROXY), and SSL_CERT_FILE's extra roots.
- A Windows R build with `-Dblas=openblas` (needs Needs N2: the openblas
  env on win-64 and a CI leg); vendor-libs.sh copying openblas.dll and
  its VCRUNTIME140 dependency; verify-tree's DLL closure with it.
- The openblas flavor on osx-64, and macOS package cross-loading between
  the flavors (D9; no osx openblas CI leg). osx-arm64 build, verify-tree
  and smoke: Review R3.
- make: the macOS config's cross-run values beyond the two fixed by hand;
  GNU make's test suite on macOS and Windows.
- D14 on Windows: the toolchain build with m2_exclude (toolchain.yaml's
  windows legs; verify-toolchain and verify-bundle's btTools there).
  The kappa run's package set needs no library env; packages that need
  one (stress's g3 rows) ran no further than their library check.

## Needs from other topics

- N1 (b13-env-ci, pixi.toml; blocking: without it `pixi run fetch`,
  `build`, `check` and `configure` fail, fetch-r.sh is gone):

  ```diff
  -fetch = "bash scripts/fetch-r.sh"
  +fetch = "bash scripts/zig-build.sh fetch"
  ```

  and in the rzig-test comment (pixi.toml:220-222) drop "and on linux the
  parity test against the bash shims in toolchain/ for every OS's command
  lines" once N3 lands.
- N2 (b13-env-ci, pixi.toml and build-r.yaml/build.yaml; for M-7):
  `[feature.openblas] platforms` gains `"win-64"` (conda-forge has
  libopenblas/openblas 0.3.34 for win-64), the comment that says Windows
  ignores -Dblas goes, and a windows-latest openblas leg (full tier is
  enough) runs build, verify-tree and smoke. smoke-test.sh's BLAS check
  (`grepl("openblas", si$BLAS)`) is unix-only today.
- N3 (b13-rzig, zigbuild/tools/rzig/; blocking for `pixi run rzig-test`
  on linux, which build-r.yaml:102 runs on every leg): toolchain/ is
  gone, so
  - test.sh: remove `ZIG="$ZIG" bash "$here/parity-test.sh"` and the
    header lines about it; delete parity-test.sh (its reference is the
    shims), or keep it with the shims moved to rzig/testdata (D5 b);
  - smoke-test.sh: `shims=$(cd "$here/../../../toolchain" && pwd)`
    (line 39) fails under `set -e`; drop the `bash` side: `$T/bash` in
    the `mkdir -p` and the `ln -s "$shims/$n" "$T/bash/$n"` line, the
    `for kind in bash rzig` loop becomes rzig only, and the byte-identity
    (`cmp "$T/out-bash/$f"`) and `.fini_array` checks of `$T/out-bash`
    go, with their header text (lines 14-19, 27-28);
  - doc comments naming the shims (main.zig:2-7, linker_args.zig:24-25,
    cmdline.zig:1, cache.zig) are history only.
- N4 (b13-recipe or docs, recipe/recipe.yaml:15-20, recipe/build.sh:21):
  comments naming scripts/fetch-r.sh and "the bash shims in toolchain/ only
  serve configure-only.sh" become `zig build fetch` and "configure-only.sh
  runs rzig".
- N5 (b13-recipe; L7 wiring): a make output built by
  `zig build --build-file zigbuild/make/build.zig -Dsource=<make src>
  --prefix <TC>/usr` (the recipe adds make-4.4.1.tar.gz, sha256
  dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3, as a
  source); then zigbuild/toolchain/build.zig's unix usr/ installs it in
  place of conda-forge's make (its SOURCES block as a built file, like
  pkgconf's), and verify-toolchain.sh's make checks follow. Linux and
  macOS only (D12).
- N6 (b13-env-ci, gen-config.yaml, optional): add
  `"zigbuild/tools/rzig/build.zig"` to the push `paths`, since the capture
  now builds rzig.
- N7 (vendor-libs.sh owner, optional): its openblas `libopenblas.so`
  link-name symlink (vendor-libs.sh:179-192) served Makeconf's bare
  `-lopenblas`, which is gone (D6); harmless, can go.

## Review

Skeptical pass over the whole diff (2026-11-24). Nothing outside the
topic's files is changed; the deleted toolchain/ shims are this topic's
item (M-17), and their other users are Needs N1, N3, N4.

Changed:

- build.zig: Ctx.rblas/rlapack's comment still said "null when blas ==
  .openblas", wrong since blasForwarder; linkBlas' comment now says R's
  own libraries link openblas itself, not the forwarders.
- zigbuild/tools/fetch.zig: setMtimes skipped any name containing `..`
  anywhere (a file `a..b` would have kept its extraction time); now it
  skips absolute names and `..` components only (hasDotDot).

Checked and left as is: zig-build.sh runs under env.sh's `set -euo
pipefail`, so a failed `zig build fetch` stops it; `zig build` finds the
root build.zig from pixi's working directory as the main call does;
gen-subst.sh replaces $TOOLCHAIN after OBJ_DIR/SRC_DIR, and
build/capture-rzig is under neither; m2_exclude's names appear in no
script, workflow, recipe or stress file (grep -w); Windows' Rlapack.dll
links the forwarder's import library, whose 76 names cover what R's
LAPACK imports (F7).

| id | where | command | result |
|---|---|---|---|
| R1 | delta (conda-forge zig 0.17.1), N1 applied to the mirror's pixi.toml only | `rm -rf build/R-4.6.2 build/R-4.6.2.tar.gz dist`, `pixi run fetch` | 0 (48 s); stamp empty; doc/NEWS.Rd mtime 2026-10-19 18:15:01 (the tar header's) |
| R2 | delta | `pixi run build -j16`, `verify-tree`, `smoke`; `-e openblas` the same; `pixi run configure` + `pixi run bash zigbuild/tools/gen-subst.sh` (slim) | 0/0/0; 0/0/0 (openblas lib/R/lib: libRblas.so, libRlapack.so 1824 bytes each); 0, 0, `diff -r` against the vendored linux-x86_64 configs empty |
| R3 | omicron (osx-arm64), worktree mirrored, R tarball copied (sha256 c297040f...) | `pixi run -e openblas build -j8`, `verify-tree`, `smoke`; `pixi run configure` + gen-subst.sh (slim, rzig capture) | 0/0/0 ("installed tree verified (macos/slim-openblas)"); libRblas.dylib: id @rpath/libRblas.dylib, LC_LOAD_DYLIB @rpath/libopenblas.0.dylib, rpaths @loader_path, @loader_path/../..; capture differs from the vendored osx-arm64-slim only in CC_VER (clang 22.1.8) and FC_VER (flang 23.1.5), the known stale lines build.zig rewrites. Scratch dir removed |
| R4 | delta | `zig fmt --check` build.zig, fetch.zig, make/build.zig, toolchain/build.zig | clean |

Not re-run after the review edits (comment-only and one helper in
fetch.zig): upstream zig (the implementer's runs above), kappa.

## Suggested commit message

    feat: fetch R with zig build, capture configs with rzig, forward BLAS in the openblas flavor, build make with zig
