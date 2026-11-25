# Build 13 fixes (b13-fixes)

Worktree wt/build13 (branch build13, PR #57, pushed head cc7d810), all
work uncommitted (2026-11-24), on top of the uncommitted decision 4b and
b13-leftovers work, which stays. Hosts: delta (linux-64,
~/rz/wt/build13-fix, ~/rz/scratch-b13-fix), kappa (win-64, developer
mode on, %USERPROFILE%\rz-b13-fix, removed after). Local scratch:
scratch-b13-fix/ beside the worktrees.

## Items

| # | item | state |
|---|---|---|
| 1 | REGRESSION: fetch.zig left Windows trees with symbolic links (or none), `check: fresh tests tree` failed on windows-latest and windows-11-arm (upstream-zig run 45447897929) | done: links materialized as copies on Windows |
| 2 | b13-leftovers N1: no `iconv -l` on Windows | done (build.zig, N1's diff as recorded) |
| 3 | LOCAL_SOFT (libs-zig-pixi: CRAN jpeg 0.1-11 on build 12 win-64) | done: Rcmd_environ default, rzig demotes the -I, scan, stress row |
| 5 | rzig windres: -D/--define values unescaped as GNU windres' shell does (libs-zig-pixi: libiconv 1.17) | done |
| 4 | delta: rzig-test (both zigs), fetch, build, verify-tree, smoke, contract, conda-package | see Tests |
| 6 | Windows openblas: packages linking BLAS fail to load, "32 bit pseudo relocation ... out of range" (stress 45548393985) | done: Rblas.dll's import library libRblas.dll.a in bin/x64 (F13, D12) |

## Changes

- `zigbuild/tools/fetch.zig`: on Windows, after extraction (still in the
  `.extract` directory, so an interrupted run leaves no half tree), every
  symbolic link entry of the archive (std.tar.Iterator over the tar
  bytes) becomes a copy of its target: a file (`copyFile`) or a directory
  tree (`walk`). The target is resolved against the link's directory
  (`resolveLink`) and must stay inside the archive's top directory (an
  absolute, drive-letter or escaping target stops the fetch). A symlink
  std.tar made (developer mode) is removed first (`removeLink`: the
  link, never its target). Links to links wait for their target
  (`materialize`); a cycle or a link into itself is an error. The copies
  get their targets' tar times (`setCopies`, from setMtimes). The wrong
  "none is built" message is gone; std.tar's `unable_to_create_sym_link`
  is accepted on Windows only (materialized anyway). linux and macOS
  unchanged (real links). Also setMtimes' root is now src_dir's parent,
  not the tarball's directory (they are the same in `zig build fetch`;
  a tarball elsewhere failed with FileNotFound, F3). 5 unit tests,
  run by `zigbuild/tools/rzig/test.sh` (`zig test fetch.zig`).
- `build.zig`: N1 (no utils/iconvlist on Windows); rcmdEnviron adds
  `LOCAL_SOFT="${LOCAL_SOFT-${R_ZIG_LIBS}}"` after R_TOOLS_SOFT's
  default, with its comment and the doc block (CRAN's meaning, history).
- `zigbuild/tools/rzig/windows.zig` `demoteZigLibs` (called by
  compiler.argv before envFlags, Windows only): a caller's `-I<dir>` or
  `-I <dir>` where `<dir>` is a zig-libs root or below it becomes
  `-idirafter <dir>` in place; an `-L<dir>` / `-L <dir>` under zig-libs
  that is not a directory is dropped (LOCAL_LIBS' `lib$(R_ARCH)`, F9).
  Roots: each environment's zig-libs (environment.list) and R_ZIG_LIBS.
  Paths compared ignoring case, `/` vs `\`, `.`/`..` and repeated
  separators (`samePath`, `underPath`). compiler.envFlags does not add an
  environment's include/ as `-idirafter` again when the args have it
  (`hasIdirafter`). main.zig documents R_ZIG_LIBS.
- `zigbuild/tools/rzig/binutils.zig` `unescapeDefine`: windres' `-D`,
  `-D <v>`, `--define=<v>`, `--define <v>` values get `\"` -> `"` and
  `\\` -> `\`; any other backslash stays.
- `scripts/verify-tree.sh`: the LOCAL_SOFT line among the expected
  Rcmd_environ lines. `scripts/verify-bundle.sh` (pcpath.R) and
  `recipe/test-build-tools.R`: LOCAL_SOFT's default (zig-libs) and a
  user's value kept, beside R_TOOLS_SOFT's (Windows legs only).
- `stress/packages.tsv`: jpeg row; `stress/stress.R`: LOCAL_SOFT = the
  stress env's zig-libs when it has one (a tree's Rcmd_environ knows only
  R's own); `stress/README.md`: LOCAL_SOFT note.
- `.github/devdocs/b13-leftovers/PLAN.md`: item 1 marked done here.
- Item 6 (F13, D12). `build.zig`: winBlasForwarder also writes the
  plain names of R's Rblas.def (no forwards) and makes Rblas.dll's
  import library from them with rzig's dlltool (`winDlltool`, split out
  of winMakeImportStub); installed as `bin/x64/libRblas.dll.a` in the
  openblas flavor only. R.dll, Rlapack.dll, modules/lapack.dll and
  stats.dll link that import library instead of the forwarder
  (`linkRblas`); the internal flavor links Rblas.dll as before.
  `scripts/verify-tree.sh` (Windows): openblas needs libRblas.dll.a with
  `T dgemm_` (the tree's nm.exe), internal must not have one.
  `scripts/contract-test.sh` (every OS and flavor): R CMD SHLIB of C
  calling dgemm_ with `PKG_LIBS = $(BLAS_LIBS) $(FLIBS)`, no "pseudo
  relocation" in its output, and the result equals `%*%`.

## Decisions (defaults, 2026-11-24; who: defaults chosen in this track, user may revisit)

| id | question | options | chosen | reason |
|---|---|---|---|---|
| D1 | where Windows materializes links | (a) after extraction, in the `.extract` dir, before the rename; (b) after the rename | (a) | an interrupted run must not leave a tree whose `configure` makes the next run skip the fetch |
| D2 | which links | **(a) every symbolic link entry, also when std.tar made the link**; (b) only those std.tar could not make | (a) | developer mode (kappa) or an admin runner makes the link, and MSYS' `cp -R` then copies a link (CI failure); one rule whatever the machine |
| D3 | copies' times | **(a) the target's tar time**; (b) extraction time | (a) | the tree must not depend on when it was extracted (setMtimes' rule) |
| D4 | link -> link | **(a) wait for the target link, error on a cycle**; (b) unsupported | (a) | small, general; R has none |
| D5 | LOCAL_SOFT default | **(a) R_ZIG_LIBS, as R_TOOLS_SOFT**; (b) only when zig-libs exists | (a) | Rcmd_environ cannot test a directory; jpeg's configure.win copes with a missing one (falls back), as with an empty value |
| D6 | which -I rzig demotes | **(a) a zig-libs root or below it (R_ZIG_LIBS and each environment's)**; (b) only `<root>/include` | (a) | LOCAL_CPPFLAGS and a package's `-I$(R_TOOLS_SOFT)/include/<x>` (nloptr) alike; any zig-libs header after zig's |
| D7 | other trees (Rtools45, a user's LOCAL_SOFT elsewhere) | **(a) untouched**; (b) demote any LOCAL_SOFT | (a) | rzig never sees LOCAL_SOFT itself; stress.R never sets LOCAL_SOFT to the Rtools45 tree (finding 22 stands) |
| D8 | duplicate -idirafter | **(a) envFlags skips an include/ the args already have (lexical compare)**; (b) keep both | (a) | simple; a different spelling (8.3 names) only repeats a search |
| D9 | LOCAL_LIBS' `-L<zig-libs>/lib/x64` | **(a) rzig drops a missing zig-libs -L dir**; (b) keep (zig warns on every link) | (a) | F9: "unable to open library directory" on every package link otherwise |
| D10 | jpeg row's windows expect | **(a) `windows=ok`, sysdep `zig-libjpeg@windows`**; (b) a fail class | (a) | the README's rule for zig-* rows: the expect assumes the zig-* sysdep; stress.R reports `?` while it is missing (zig-libjpeg is libs PR #8, unpublished); pixi.toml's stress feature gets `zig-libjpeg` once it is on universe (not added now: the lock would not solve) |
| D11 | windres unescaping | **(a) `\"` and `\\` only, in -D/--define values**; (b) a full shell unquote | (a) | the coordinator's spec; a Windows path's backslashes (C:\x) stay |
| D12 | packages' -lRblas on Windows openblas (F13) | **(a) an import library libRblas.dll.a from Rblas.def's plain names (rzig dlltool), beside Rblas.dll**; (b) Rblas.dll exports real jump thunks to openblas instead of forwards; (c) rzig rewrites -lRblas to an import library of its own | (a) | rzig and GNU ld take lib<n>.dll.a before <n>.dll, so Makeconf's BLAS_LIBS stays as it is (the M-23 contract); the code is one dlltool run like the R.dll stub; (b) adds code and a call per BLAS function; (c) puts flavor knowledge in rzig. Who: default (2026-11-25) |

## Findings

- **F1 (V) R-4.6.2.tar.gz has 16 symbolic links.** `tar tvzf`: 15
  src/library/Recommended/<pkg>.tgz -> <pkg>_<ver>.tar.gz and
  tests/Pkgs/pkgA -> xDir/pkg (a directory). No build step reads the
  Recommended .tgz (build.zig: "Packages/recommended — not built here");
  the old "none is built" was wrong for tests/Pkgs/pkgA, which
  `check: fresh tests tree` copies.
- **F2 (V) kappa: the old fetch leaves 16 links, the new one none.**
  kappa (developer mode on, so std.tar makes real links), the tarball
  above: build13 head's fetch.zig: 16 links (`find -type l`),
  Recommended .tgz 0/15 regular; this tree's: "Copied the targets of 16
  symbolic links (Windows)", 0 links, pkgA a directory, `diff -r pkgA
  xDir/pkg` identical, 15/15 .tgz regular files `cmp`-identical to their
  targets, `.r-zig-patches` written (empty), Done. Copies' mtimes equal
  their targets' tar times (pkgA/DESCRIPTION 1733321311 = xDir/pkg's;
  MASS.tgz 1784326506 = MASS_7.3-66.tar.gz's).
- **F3 (V) fetch's setMtimes looked under the tarball's directory.**
  kappa, fetch run with the tarball in the current directory and
  src_dir elsewhere: "cannot set the time of R-4.6.2/configure.ac:
  FileNotFound", with the old fetch too. Fixed (src_dir's parent). `zig
  build fetch` passes both in build/, so CI was not affected.
- **F4 (I) the CI `cp` failure did not reproduce on kappa.** With the old
  tree (16 links), `sh -c 'rm -rf $3 && cp -R $1 $3 && cp -R $2
  $3/tests'` passed with Git's cp (MSYS unset, winsymlinks:nativestrict)
  and with conda's m2 coreutils 8.32.5_11 / msys2-runtime 3.6.11.4_11
  (the CI's runtime; MSYS unset, native, nativestrict, sys). CI's
  "cannot create symbolic link ... pkgA: No such file or directory"
  needs a link in the source tree; the new tree has none, so the step
  copies only files and directories.
- **F5 (V) no zig-libs header shadows zig's.** prefix.dev/universe
  repodata 2026-11-24, newest of each: win-64 and win-arm64 each have 9
  zig-* packages (abseil, expat, gdal, geos, onetbb, openssl, proj,
  sqlite, zlib), 1318 headers under Library/zig-libs/<triple>/include
  (the same names on both). Against zig 0.17.1's lib/libc/include/
  any-windows-any (1613 files), lib/libcxx/include (1111) and lib/include
  (243), by relative path and case-insensitively: 0 clashes. jpeg's
  (jpeglib.h, jconfig.h, jmorecfg.h, jerror.h) are not in zig's either.
  Script: scratch-b13-fix/scan.sh.
- **F6 (V) LOCAL_SOFT under R CMD and the demoted -I.** kappa, a copy of
  a pixi env with published r-zig-slim/r-zig-toolchain _12 + zig-zlib,
  zig-expat, zig-geos (robocopy, never the env in place), its 16 rzig
  copies replaced by this tree's rzig.exe (cross-built on gamma), the
  LOCAL_SOFT line appended to its Rcmd_environ: `Rcmd Rscript` sees
  LOCAL_SOFT = R_TOOLS_SOFT = R_ZIG_LIBS =
  `<env>/Library/lib/R/../../zig-libs/x86_64-windows-gnu` (exists);
  `R CMD config LOCAL_SOFT` the same. A C++ package (cstddef, cstdio,
  cmath, thread, vector, string, zlib.h, geos_c.h; -lgeos_c -lgeos -lz)
  installs and loads ("1.3.1 3.14.1-CAPI-1.20.5 2.000000"); RZIG_TRACE:
  make's `-I<...>/zig-libs/x86_64-windows-gnu/include` reaches zig as
  `-idirafter <same>`, no `-I` of it, and the env's zig-libs include/
  is not added a second time.
- **F7 (V) build 12's rzig with LOCAL_SOFT set compiles too.** Same
  package, the published env unmodified, LOCAL_SOFT set by hand to its
  zig-libs: zig gets `-I<zig-libs>/include` and compiles and loads (F5:
  no clash today). The demotion is for a future header name.
- **F8 (V) jpeg 0.1-11 on Windows.** configure.win asks `make -s -f
  Makeconf -f config.mk print VAR=LOCAL_SOFT`, then looks for
  `$local/lib/libjpeg.*` (Makevars-ls.win: `pkg-config --libs libjpeg`,
  else -ljpeg), else downloads rforge's libjpeg-current-win.tar.gz over
  http. kappa: build 12 as published (LOCAL_SOFT empty): "LOCAL_SOFT does
  not contain libjpeg" (MSYS' /lib exists), the download works, then
  `tar (child): gzip: Cannot exec` (F10), configuration failed. This
  tree's rzig + LOCAL_SOFT = zig-libs (no zig-libjpeg): the same. With
  Git's usr/bin (gzip) on PATH: unpacks, compiles (the demoted -I in the
  trace), link fails: `lld-link: error: undefined symbol: __declspec(
  dllimport) __iob_func` (rforge's win64/libjpeg.a is an msvcrt-era gcc
  build; zig links UCRT). So jpeg needs zig-libjpeg in LOCAL_SOFT on
  Windows (libs PR #8); not tested with it (unpublished).
- **F9 (V) LOCAL_LIBS' lib/x64.** With LOCAL_SOFT set, Makeconf.win's
  `-L"$(LOCAL_SOFT)/lib$(R_ARCH)"` names zig-libs/<triple>/lib/x64, which
  no zig-* package has: zig printed `warning: unable to open library
  directory ".../lib/x64": FileNotFound` on the jpeg link. With D9 the
  rebuilt rzig drops it: no such warning in either log (A1b, B3b).
- **F10 (I, follow-up) the build-tools' tar has no gzip.** The env's
  tar.exe is m2-tar 1.35.3_11 (Library/usr/bin, conda-meta); no gzip.exe
  there nor in R_HOME/bin/toolchain/usr/bin, so a configure's `tar xzf`
  (jpeg's fallback) fails under R CMD. Not fixed here: a recipe
  dependency (m2-gzip) for r-zig-build-tools, for the backlog.
- **F11 (V) libiconv 1.17's windres options.** delta, libiconv-1.17
  from ftp.gnu.org: `sh windows/windres-options --escape 1.17` prints
  `-DPACKAGE_VERSION_STRING=\"1.17\"` and three numeric -D. rzig built
  from this tree without unescapeDefine (a copy with the call removed),
  as `windres -F pe-x86-64 $opts -i libiconv.rc -o x.o
  --output-format=coff`, ZIG_BIN = the pixi env's zig 0.17.1: zig rc
  gets `/d 'PACKAGE_VERSION_STRING=\"1.17\"'`, "libiconv.rc:25:34: error:
  expected '<'}' or END>', got '\'" (the libs-zig-pixi error). This
  tree's: `/d 'PACKAGE_VERSION_STRING="1.17"'`, rc 0, an x86-64 COFF
  object with "1.17" in its version strings, byte-identical to the one
  from the unescaped options (`windres-options 1.17`).

- **F12 (V) make's source download is a single point of failure.** stress
  45512789892 (a4d7737), macos-15-intel conda, "Build the conda packages":
  "Failed to fetch from https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz ...
  Request failed after 3 retries"; R's build passed. Fix: the recipe's url
  is a mirror list (ftp.gnu.org first, then mirrors.kernel.org and
  ftpmirror.gnu.org; both mirrors give sha256 dd16fb1d..., gamma 2026-11-24).
  conda.zig's recipeSources reads the first mirror, so usr/SOURCES is
  unchanged. zigbuild's build.zig.zon keeps one url (zon has no mirrors).
  Follow-up: 126320b broke make.zig's test "recipe.yaml's unix source is
  this url and sha256" (it matched `url: <url>` only; upstream-zig
  45533499941, all 6 toolchain jobs, and the 6 default jobs then found no
  toolchain artifact). The test now also takes a mirror list whose first
  entry is make.zig's url. gamma: with a forced test run, a recipe with a
  different first mirror fails and the real recipe passes, with both zigs.
  Note: zig build caches a passed test run and does not track the recipe
  file, so a local re-run proves nothing unless make.zig changed.

- **F13 (V) Windows openblas: forwarded exports become data imports.**
  stress 45548393985 (e26b5ff, windows-latest, tree, openblas): irlba,
  rsvd, ScaledMatrix, beachmat, edgeR and RcppArmadillo fail at load
  ("lld-link: warning: runtime pseudo relocation in irlb.o against
  symbol dgemm_ is too narrow (only 32 bits wide)", then "Mingw-w64
  runtime failure: 32 bit pseudo relocation at 0x00007ff817a4c2f2 out
  of range"); Matrix had the same warnings (expm.o, matmult.o) and
  loaded by chance. Makeconf.win's BLAS_LIBS is `-L$(R_HOME)/bin/x64
  -lRblas` and bin/x64 had only Rblas.dll, the forwarder, so lld linked
  the DLL itself and took its forwarded exports as data (auto-import).
  gamma (zig 0.17.1, x86_64-windows-gnu, a toy forwarder): linking the
  DLL directly warns; an import library from `zig dlltool -m i386:x86-64
  -d plain.def -D Rblas.dll` (names only) beside it gives no warning
  (nm: `T dgemm_`, `I __imp_dgemm_`), and rzig's -l search takes
  lib<n>.dll.a first (windows.zig importLib). Fix: D12.
  R's own DLLs (R.dll, Rlapack.dll, modules/lapack.dll, stats.dll)
  linked the forwarder through zig's linkLibrary. gamma, the same toy:
  lld's own `--out-implib` of the forwarder lists `T dgemm_` and links
  with no warning, so they were likely not affected; they link the new
  import library anyway, one import library for every consumer.

## Tests

| where | command | result |
|---|---|---|
| gamma | `zig test zigbuild/tools/fetch.zig` | 5/5 |
| gamma | `zig build --build-file zigbuild/tools/rzig/build.zig test` | 243/243 |
| kappa | fetch-test.exe (fetch.zig's tests, cross-built for x86_64-windows) | 5/5 |
| kappa | old vs new fetch.exe on R-4.6.2.tar.gz, then the check step's `sh -c 'cp -R ...'` (F2, F4) | old: 16 links; new: 0, copies identical, stamp; cp rc 0 |
| kappa | the worktree's `pixi run build` (conda-forge zig) | rc 0, "Copied the targets of 16 symbolic links", zig-built R OK (ucrt) |
| kappa | `pixi run check` (same tree) | rc 0: `check: fresh tests tree`, test-Examples, test-Specific, test-Reg (last: reg-plot-latin1 OK) |
| kappa | `pixi run verify-tree` (same tree) | "installed tree verified (windows/slim)"; Rcmd_environ has the LOCAL_SOFT line; no library/utils/iconvlist (N1) |
| kappa | LOCAL_SOFT and C++ package, new and build 12 rzig (F6, F7) | ok, ok |
| kappa | jpeg 0.1-11 (F8, F9) | fails without zig-libjpeg, as recorded |
| delta | libiconv.rc via rzig windres, without and with unescapeDefine (F11) | error as reported; ok |
| delta | `pixi run rzig-test` (conda-forge zig 0.17.1), final tree | rc 0: 243/243 unit, fetch 5/5, check-test 60 passed 0 failed, link objects |
| delta | `ZIG_BIN=$(pixi run fetch-zig) pixi run rzig-test` (upstream ziglang 0.17.1), final tree | rc 0: the same counts |
| delta | `pixi run fetch` (fresh, final tree) | rc 0; 16 symlinks kept, stamp written, tar times (VERSION 1793260804) |
| delta | `pixi run build`, `verify-tree`, `smoke`, `toolchain`, `contract`, final tree | all rc 0 ("Smoke test passed (linux/slim)", "Contract test passed (slim/linux)") |
| delta | `pixi run -e pkg conda-package` (linux-64), final tree | rc 0: 7 packages (_13), 7 "all tests passed" |
| delta | item 6: `zig build -l` (build.zig compiles), conda-forge zig and upstream ziglang 0.17.1 | configure reached (stops at MissingPrefix / MissingCondaPrefix outside pixi, as before) |
| delta | item 6: `pixi run rzig-test`, `pixi run toolchain-test`, each with conda-forge zig and with `ZIG_BIN=$(pixi run fetch-zig)` | rc 0 all four (243/243 unit, fetch 5/5, check-test 60 passed) |
| delta | item 6: contract's new BLAS block alone, compile tree slim (linux, internal BLAS) | computes, no pseudo relocation |
| kappa | item 6, own scratch copy (removed after): `pixi run -e openblas build`, `verify-tree`, `toolchain`, `contract` (conda-forge zig) | rc 0 all; bin/x64 has libRblas.dll.a; "BLAS link verified: ... imports dgemm_ as code"; "BLAS_LIBS (R CMD SHLIB, C calling dgemm_): no pseudo relocation, computes: OK"; "Contract test passed" |
| kappa | item 6: irlba 2.4.1 (+ Matrix, lattice) from CRAN with the compile tree (slim-openblas) | installs; 0 "pseudo relocation" lines in the three install logs; irlba(A, 3)$d equals svd(A)$d[1:3] |
| kappa | item 6, negative: the contract BLAS block with libRblas.dll.a moved away | lld's pseudo relocation warning; the block stops (rc 1); moved back: passes |

## Not covered

- Item 6: Windows on ARM (win-arm64 has no openblas flavor); the
  upstream-zig leg on Windows (kappa ran conda-forge zig only).

- Windows on ARM: fetch-arm64.exe cross-builds; not run (no arm64 host).
- A Windows host without developer mode (std.tar cannot make links):
  the same materialize path minus `removeLink`'s delete; the unit test
  covers it on such a host only.
- jpeg with zig-libjpeg (unpublished).
- verify-bundle.sh's and recipe/test-build-tools.R's new LOCAL_SOFT
  checks run on Windows legs only (CI).

## Needs

- pixi.toml `[feature.stress.target.win.dependencies]`: `zig-libjpeg =
  "*"  # jpeg` once on universe, then re-lock.
- recipe: m2-gzip beside m2-tar for the build tools (F10). Done in the integration (r-zig-build-tools Windows run deps).
