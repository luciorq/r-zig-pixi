# feat-win-link-fixes: response files, a default Winsock link, patch

**Status (2026-10-21).** Uncommitted, stacked on phase 7
(wt/feat-standalone-phase7: `git diff | sha256sum` 167659b3..., 83
status entries, pixi.lock fbb64b7b...) in wt/feat-win-link-fixes, branch
feat-win-link-fixes from d11dee1. No pixi.toml or pixi.lock change
(pixi.lock is still fbb64b7b...; pixi.toml only in comments). One recipe
run dependency added: r-zig-build-tools on win-64 depends on m2-patch
(recipe.yaml), a change to a published package's dependencies: kept by
the user's decision (2026-10-22, "Merge order and publishing"). Tested on linux-64
(gamma), win-64 (kappa) and osx-arm64 (omicron), with both zigs
(conda-forge's and upstream 0.16.0); "Tested" below.

**Merge order and publishing.** This layer merges after phase 7 and
before the user sets `CONDA_PUBLISH=true`. It has no build-number bump of
its own: it rides on phase 7's `_9` (r-zig-slim: rzig and
share/zig/rpkg/build_t1.zig; r-zig-build-tools: m2-patch as a run
dependency on win-64; the standalone build-tools archive: patch.exe).
recipe.yaml's 8 → 9 history entry says so.

The new run dependency: kept (user decision, 2026-10-22). m2-patch is
on conda-forge and already in pixi.lock (11841); the conda outputs do not
ship TC/usr, so without it a conda environment with r-zig-build-tools
has no `patch` on Windows. r-zig-build-tools (win-64) `_9` depends on
m2-patch; `patch` is in the standalone archive and in conda.

universe's newest was `_8` on all five subdirs when checked (2026-10-21,
repodata of linux-64, linux-aarch64, osx-64, osx-arm64, win-64:
r-zig-slim 8, r-zig-toolchain 8). If universe has a `_9` before this merges, it needs its own bump.

The user's request (2026-10-21): fix (1) a response file for `rzig def`
and the link step, and the three toolchain improvements: (2) default
Windows system libraries, (3) `lib<name>.lib` lookup, (4) `patch` in
TC/usr/bin. Evidence: phase7m2/experiment/RESULTS.md (unix build files on
Windows; F1), KN (phase7native/kappa/REPORT.md). The planner's final plan
was winfix/plan/PLAN.md; the probes behind its findings F-a to F-i are in
winfix/plan/probe/.

## 1. A response file for `rzig def` and the link

**The bug (experiment F1).** build_t1.zig's `link()` named every object
on `rzig def -o`'s and the link driver's command lines. libgeos with its
unix Makevars (about 390 objects under
`<TMP>\RtmpX\R.INSTALLx\libgeos\src\.rzig\obj\N\...`) made a
42,743-character `rzig def`; Windows' CreateProcess stops at 32,767:
`error: failed to spawn and capture stdio from .../rzig.exe:
NameTooLong`. Any Windows package that rzig build (tier 1 or 2) builds
with enough objects hits it. The make path does not: make names objects
relative to src/ (stock libgeos's longest line, `zig-ar.exe crs ...`,
was 14,162 characters).

**What zig offers.** zig 0.16's `std.Build.Step.Run` writes no response
file (only Compile steps do, for zig's own commands). zig cc reads
`@file` with both zigs, with std.process.Args.IteratorGeneral (comments,
single quotes): `"` quotes, `\` is literal unless before a quote, `#` at
a word's start comments out the line, and `'` pairs with `"` (one quote
state for both), so a `'` cannot be written in the file.

**The rule, one code path on every OS** (zigbuild/rpkg/build_t1.zig;
since feat-tier1-engine, 2026-10-23, tier1.zig writes objects.rsp and
rspName and rspText are in rzig's response.zig):

- At build() time `objectsFile` writes `<root>/objects.rsp`: every
  tier-1 object, and tier 2's C and C++ ones, has its path then
  (outputFile). One line per object, `"<name>"`, the name relative to
  srcdir (where both steps run; std.fs.path.relative), `/` on Windows,
  `./` before a name that does not start with `.`, as std.Build.Step.Run
  does, so a root under src/-tmp is not read as an option (review R1,
  2026-10-22: without it `Unknown Clang option: '-tmp/...'`). Relative,
  so a directory every name shares drops out, a `'` in it included
  (`C:\Users\O'Brien\...`).
- A name that still holds `'`, `"` or `\` (legal in a POSIX name): no
  file; every object on the command line as before (only more than
  32,767 characters of such objects then fail).
- Objects whose path zig build knows only once built (tier 2's zig
  object, first in objs) stay on the command line before the `@` word;
  any other order: no file.
- `rzig def` runs in srcdir now (setCwd) and gets `@<root>/objects.rsp`;
  the link gets it where the objects were. Each object stays an input of
  both steps (addFileInput), and so does the file: zig build still orders
  the compiles first and tracks the objects. Both steps have side effects
  and always run, as before.

**rzig** (zigbuild/tools/rzig/response.zig, new): `expand` replaces each
readable `@file` with its words, read as zig cc reads them (one level; a
file that cannot be read stays `@file`). Its readers:
- `rzig def` (def.zig): the objects of `@<root>/objects.rsp`.
- linux's debug-info test (strip.zig `wanted`): objects in a response
  file are read for .debug_info as the command line's. Without it a `-g`
  compile linked without `-g` (pkgbuild's compile_dll(debug = TRUE)) lost
  its DWARF (parity-test's mutation check: the new case FAILs when
  `wanted` does not expand). A foreign tool's `@file` (CMake) is read now
  too.
- RZIG_TRACE's line (main.zig): the link shows its objects, as make's
  does; pkg-parity's command-line comparison stays as it was.
- gcc.exe, g++.exe, zig-fc pass `@file` to zig untouched. fortran's
  kind and archives.rename take `@x` as a plain input (unit tests).

zig 0.16's IteratorGeneral reads past the end of a text that ends inside a
comment with no newline (index out of bounds, found by response.zig's
unit test); `split` appends a newline first. build_t1.zig never writes a
comment.

**Not covered (recorded).** `-l` inside another tool's `@file` reaches
neither windows.libs nor item 2's rule (pre-existing; no known package).

**macOS and linux.** The same code runs there. linux: a tier-1 .so is
byte-identical with phase 7's build_t1.zig and with this one (gamma: a
three-source package through `rzig build --pkg` with each rpkg dir, sha256
277d39ec... both). macOS: the dylib records object names as given, so
only those strings change (the planner's P4: two argv links differ from
each other as much); omicron installs a 61-object package through tier 1
with both zigs (below).

## 2. A default Windows system library: ws2_32

**What links what.** MinGW gcc links its LIB_SPEC set (mingw32.h:112-117:
advapi32, shell32, user32, kernel32); zig links those without an `-l`.
Neither has Winsock. CRAN R 4.6.1's Makeconf adds no system library. ragg
calls `htons` (src/AggDevice16.h includes winsock.h); its Makevars.win
names `-lws2_32` only in its rwinlib branch, not in the pkg-config branch
the conda env takes, so with conda's libraries it failed in both modes:
`lld-link: error: undefined symbol: __declspec(dllimport) htons` (KN's
cause e). Whether Rtools' static .pc chain brings ws2_32 for CRAN is
UNVERIFIED (no Rtools45 on kappa). The stress suite's ragg row already
said "with PKG_LIBS += -lws2_32: ok".

**The rule** (windows.zig `defaultLibs`, called by compiler.zig after
windows.libs): `-lws2_32` last on a link that gets gcc's LIB_SPEC: `-shared`
as a word, no `-c/-S/-E/-M/-MM`, no `-nostdlib` or `-nodefaultlibs`
(`-nostartfiles` still gets it). Executables (configure's conftests,
helper programs) are left as they were. After windows.libs, so it is zig's
own import library, never one in the caller's `-L` directories.

**Why it is harmless.** An import library adds a DLL import only for a
symbol the link takes from it: with and without `-lws2_32 -lwinhttp` a
DLL's import table is the same, with both zigs (planner's F-e, kappa and
gamma), and ws2_32's 197 names share none with kernel32, user32, advapi32,
shell32, ntdll or the CRT's. The KN set before and after (below) checks it
on real packages.

**winhttp: not taken.** Only ux curl (curl with its unix configure) needs
it; stock curl's Makevars.win names it. The rule keeps a library only
when it fixes a measured case.

## 3. `lib<name>.lib`

**No code change.** zig's own search for `-l<n>` on windows-gnu, both
zigs (gamma, `zig cc -target x86_64-windows-gnu -shared ... -Ld -llzma`):
per -L dir `<n>.dll`, `<n>.lib`, `lib<n>.a` ("searched paths: d/lzma.dll
d/lzma.lib d/liblzma.a", strategy paths_first); with `-Wl,-Bstatic` only
`<n>.lib`, `lib<n>.a` (no_fallback). rzig's windows.libs (importLib,
windows.zig) already resolves `-l<n>` to `lib<n>.dll.a`, or to
`lib<n>.lib` when zig's own names are missing, with its unit test:
`RZIG_PRINT_ARGV=1 RZIG_OS=windows rzig gcc -shared -o p.dll a.o -Ld
-llzma` prints `d/liblzma.lib` when d holds liblzma.lib, and `-llzma` when
d holds lzma.lib (zig finds that).

**ux magick was the environment.** win-64 liblzma 5.8.3 ships only
`Library/bin/liblzma.dll`; liblzma-devel ships `Library/lib/lzma.lib`,
which zig finds itself. The experiment's libraries env had liblzma and not
liblzma-devel (libs-meta.txt:86), so neither name existed. With
liblzma-devel in the env, ux magick's next blocker is in the table below.
Pre-existing and unmeasured: under `-Bstatic`, importLib returns early on
`<n>.dll`, which zig would skip.

conda-forge does not link r-magick against its own imagemagick on
Windows either: r-magick-feedstock's recipe/meta.yaml has `imagemagick`
in host only `[not win]`, builds with m2w64 gcc, and its bld.bat is a
plain `R CMD INSTALL`. So magick's stock tools/winlibs.R downloads
r-windows/bundles' static ImageMagick 6 (ucrt-x86_64, gcc and
libstdc++) into the package; r-magick 2.9.1 win-64 `_1` is 19.8 MB and
has no imagemagick dependency. conda-forge's imagemagick 7 on win-64 is
built with clang-cl (MSVC ABI, its test_msvc_compat.c). Stock magick
links under r-zig the same way: COMPILED_BY is `clang-<version>`, so
winlibs.R picks the clang-x86_64 bundle (libc++), whose C++ names match
zig's.

## 4. `patch` in TC/usr/bin

m2-patch 2.7.6.3 hc364b38_6 (pixi.lock:11841, already in the win-64
envs, the same as m2-sed) is copied like the other tools:
`m2Tool("m2-patch")` (zigbuild/toolchain/build.zig), its licence text in
zigbuild/toolchain/m2-licenses/m2-patch/ (COPYING from
patch-2.7.6.3.src.tar.zst's patch-2.7.6.tar.xz, GPL-3.0-or-later,
sha256 8ceb4b9e...; VERSION, ORIGIN; the README's table, now 18
packages). patch.exe imports msys-2.0.dll and KERNEL32 only, so no new
DLL; its manifest says asInvoker (inspection only: kappa's elevated SSH
cannot show UAC). verify-toolchain's names, test-build-tools.R's names,
verify-bundle's btTools (`patch -p0` with a two-line diff from its
configure.win), recipe.yaml's win-64 run dependencies of
r-zig-build-tools, pixi.toml's comments. An ed-style diff needs `ed`,
which is not shipped. It fixes no stock package; ux hdf5r with it is
observed below.

## Tested

The runs and their logs: winfix/implementer/RESULTS.md (scratch).

**gamma, linux-64** (both zigs where named):
- rzig-test: 168/168 unit tests (rzig's and build_t1.zig's), parity-test
  "127 identical, 59 identical but for rzig's own-environment -L,
  compiled object, import library or default system library, 34
  deliberate differences, 0 failed", conda-forge zig and upstream zig.
  parity-test's Windows rows now take `-lws2_32` out of rzig's side like
  the import library, after checking it is there exactly when the rule
  says. Two new tier-1 checks: objects.rsp in the kept root with the
  object named from src/ and the traced link naming it; a `-g` compile
  linked without `-g` keeps .debug_info (FAILs with strip's expansion
  removed). Review fix (2026-10-22): a SHLIB check with R's session
  directory in src/-tmp (128 identical with it, both zigs; FAILs with
  the `./` removed, winfix/implementer/fixes/).
- toolchain-test, both zigs; build, verify-tree, toolchain,
  verify-toolchain, package, package-toolchain, verify-package (btMany:
  "302 objects ... objects.rsp (33832 bytes; their absolute names ...
  65240 characters); f() = 44850, the 300 functions exported", both
  passes), compile-tree, pkg-parity (cli, digest, quadprog, Rcpp, minqa:
  exports and rzig command lines identical on both paths), conda-package
  (four outputs, all tests passed), conda-consume.
- Against phase 7's linux outputs: the conda packages and archives differ
  only in rzig's copies, build_t1.zig, test-build-tools.R (the
  build-tools package's test file), base packages' build dates, and
  vendored libraries that embed the env's install path (each worktree's
  .pixi): no other file.

**kappa, win-64**: from a copy of the worktree, the Windows tree, the
toolchain tree, the three archives and the four conda packages; smoke,
verify-tree, hermetic, verify-toolchain ("34 tools run with PATH =
System32", 146 PE files' closures, 31 packages' LICENSES), verify-package
both passes (btMany with TC/zig and with conda-forge's zig: 33832 bytes,
53764 characters before; btTools 22 steps with `patch -p0`), conda-package.
Before/after (phase 7's archives from phase7m2/build-kappa/dist against
these), in the results below.

**omicron, osx-arm64**: rzig-test 168/168 with both zigs; R built; a
package of 61 objects through rzig build's tier 1 with each zig:
objects.rsp 61 lines, first `".rzig/obj/0/f.o"`, f() = 1770, loads.

## Before / after on kappa

Phase 7's archives (phase7m2/build-kappa/dist: slim 5eae7755...,
compilers 2e9ea3be..., build-tools 47da6b2c...) against this layer's
(slim 5a1321d9..., compilers c6ee022a..., build-tools b715336c...),
each extracted on kappa as a user would. The package runs use the phase 7
experiment's harness (lfx.R, KN's method: the M8 environment, KN's
libraries env, KN's smoke expressions, KN's local CRAN repo), the two
trees at once.

| case | before (phase 7) | after (this layer) |
|---|---|---|
| step 0: zig cc `@file` of 300 objects, 41,400-53,100 bytes, under `rz wf ção` with TMP inside, absolute (LF, CRLF) and relative names | - | rc=0 with both zigs; each DLL exports the 300 functions |
| btMany (302 objects, 96-character names; R CMD INSTALL, compilers, PATH = bin\x64 + System32) | FAIL: `failed to spawn ... rzig.exe: NameTooLong` | ok: f() = 44850, 300 functions exported |
| verify-bundle's btMany, both passes (TC/zig, conda-forge's zig) | (not in phase 7) | ok, objects.rsp 33,832 bytes, absolute names 53,764 characters |
| ux libgeos (unix Makevars, about 390 objects) | FAIL: `rzig.exe: NameTooLong` (the def step) | ok, smoke ok |
| R CMD SHLIB, src and TMP under one `q'...` directory | ok | ok, through objects.rsp |
| R CMD SHLIB, src apart, TMP under a `q'...` directory | ok | ok, objects on the command line (the fallback: a name keeps the `'`) |
| stock ragg (KN e) | FAIL: `undefined symbol: __declspec(dllimport) htons` | ok, agg_png smoke ok; ragg.dll imports WS2_32: htons alone |
| KN's 38 targets (stock files) | 30/38 (KN M's eight failures: a to f, i, j) | 31/38: ragg the one change |
| their 39 DLLs built in both runs (targets and dependencies) | - | the same imports (DLL and symbol) and the same exports, each; the four that import WS2_32 (curl, gert, magick, openssl) name -lws2_32 themselves |
| ux curl | FAIL: WinHttp symbols | FAIL: the same (winhttp not taken) |
| ux magick, libraries env + liblzma-devel | FAIL: 376 undefined Magick++ symbols, no lzma error | the same: the next blocker is C++ ABI, conda's Magick++ 7 (MSVC) against zig's libc++ mangling (`Magick::Image::Image` ...), not the toolchain |
| ux hdf5r (configure applies HDF5 2.2.0's patch) | FAIL: `/bin/sh: line 1: patch: command not found` | ok, smoke ok |
| stock hdf5r (KN b) | FAIL | FAIL (unchanged: Makevars.win's 1_12_0 wrappers) |

Item 2 stays: it fixes a measured case (ragg) and changes no other
package's DLL. winhttp is not added (ux curl only; stock curl names it).
Item 3 has no code change: ux magick's lzma error is gone with
liblzma-devel in the env, under both trees.

## Files

- zigbuild/rpkg/build_t1.zig: objectsFile, addObjects, rspName,
  rspText; def runs in srcdir; unit tests (run by rzig's test step).
- zigbuild/tools/rzig/response.zig (new): expand, split; unit tests.
- zigbuild/tools/rzig/def.zig, strip.zig, main.zig: their response-file
  readers; def's usage. archives.zig, fortran.zig: `@x` test cases.
- zigbuild/tools/rzig/windows.zig: defaultLibs and its test;
  compiler.zig calls it; compiler.zig's and fortran.zig's Windows tests
  expect `-lws2_32` on DLL links.
- zigbuild/tools/rzig/build.zig, build.zig: the build_t1.zig test
  compile in `test` and `rzig-test`.
- zigbuild/tools/rzig/parity-test.sh: Windows DLL links' `-lws2_32`
  taken out of rzig's side when the rule says; two tier-1 checks.
- zigbuild/toolchain/build.zig, m2-licenses/m2-patch/, m2-licenses/
  README.md: patch.exe in TC/usr/bin.
- scripts/verify-toolchain.sh, scripts/verify-bundle.sh (btMany,
  btTools' patch), recipe/test-build-tools.R, recipe/recipe.yaml (m2-patch
  run dependency, the 8 → 9 history), pixi.toml (comments only),
  stress/packages.tsv (ragg's windows expectation), README.md.
