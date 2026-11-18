# feat-extras-group: the extras toolchain group (cmake)

2026-11-13. Item D of the release-11 PR (#48, branch feat-win-arm64).
Status: implemented; tested on linux-64 only (results below). macOS and
Windows runs are still to do. The standalone tree's cmake/ was first
PyPI's cmake wheel and is now Kitware's release archive (the user's
decision the same day; section "Kitware archives (2026-11-13)" at the
end). The sections below describe the current design.

## Why

R packages that bundle a C or C++ library often build it with CMake
(nloptr's NLopt, RcppParallel's oneTBB, s2's abseil, Rhdf5lib's HDF5,
arrow from source). The toolchain had two groups, compilers and
build-tools. A user of the standalone tree had no cmake unless the host
had one, and a conda user had to know to install it. Stress round 1
decided "cmake joins the extras group on every OS" (decision 16,
2026-10-08); the user asked for the group now (2026-11-12).

## The user's decisions (2026-11-13)

- "The design as proposed": cmake from PyPI's cmake wheel for the
  standalone tree and the wheel channel; conda-forge's cmake as a run
  dependency of an empty r-zig-extras conda output; r-zig-toolchain
  includes r-zig-extras.
- 3.1 = A: "`rzig --rzig-check=package` prints a NOTE (never an error,
  never stops the build) when the package needs make, its DESCRIPTION's
  SystemRequirements mentions cmake, and no cmake is on PATH."
- 3.2 = A: "verify-toolchain allows exactly libstdc++.so.6 and
  libgcc_s.so.1 for files under cmake/ on linux (and nothing else,
  nowhere else), recorded with the reason (manylinux2014 hosts have
  them)." Void since the switch below: Kitware's cmake needs neither,
  and the exception is gone.
- Later the same day: "the standalone tree's cmake/ comes from Kitware's
  own release archives on GitHub, NOT the PyPI wheel. No fallback to the
  wheel." conda keeps conda-forge's cmake (r-zig-extras unchanged); a
  pip channel keeps PyPI's cmake. Why: the wheel's linux cmake needs
  libstdc++.so.6 and libgcc_s.so.1 (manylinux policy); Kitware's needs
  only glibc.

## Design

### Where cmake comes from

| Channel | cmake |
|---|---|
| standalone tree, archive `R-<ver>-<plat>-extras.tar.gz` (.zip on Windows) | Kitware's cmake 4.4.4 release archive (GitHub releases), into `TC/cmake/` |
| conda | `r-zig-extras`: no files, run-depends on conda-forge's `cmake` |
| PyPI | `cmake` itself (an `r_zig_extras` wheel is designed below, not built) |

Rejected: copying conda-forge's cmake into the tree, as the other groups'
files are. Its `bin/cmake` carries a prefix placeholder (conda rewrites
it at install, so `copyOf` stops on it), and it links about a dozen of
the env's libraries (libcurl and its closure, libexpat, libbz2, liblzma,
libzstd, librhash, libuv, libz; Windows the same DLLs and the VC
runtime). That would be a vendoring step per OS. Kitware's cmake loads
nothing from an env (static reading of the five archives' cmake,
2026-11-13, rel11/scratchc-extras/static-inspect.log):

| Archive | cmake loads | Floor |
|---|---|---|
| `cmake-4.4.4-linux-x86_64.tar.gz` | libdl, librt, libpthread, libm, libc, ld-linux-x86-64 (C++ runtime linked in) | GLIBC_2.17 |
| `cmake-4.4.4-linux-aarch64.tar.gz` | the same, ld-linux-aarch64 | GLIBC_2.28 (verify-toolchain's ceiling, 2.28) |
| `cmake-4.4.4-macos-universal.tar.gz` (osx-64 and osx-arm64) | /usr/lib/libcurl.4, libiconv.2, libcharset.1, libz.1, libc++.1, libSystem.B; CoreFoundation, CoreServices; no LC_RPATH | x86_64 slice: LC_VERSION_MIN_MACOSX 10.13; arm64 slice: minos 11.0 (MACOS_MIN 13.0) |
| `cmake-4.4.4-windows-x86_64.zip`, `-windows-arm64.zip` | POWRPROF, bcrypt, Secur32, dbghelp, ADVAPI32, IPHLPAPI, ole32, SHELL32, USER32, WS2_32, CRYPT32, KERNEL32, OLEAUT32; no delay imports, no VC runtime DLL | |

Each archive's sha256 is Kitware's (cmake-4.4.4-SHA-256.txt beside
them; all five checked). conda-forge also has cmake for win-arm64
(4.4.5, h668d1a9_0), so r-zig-extras resolves there too.

### Layout: `R_HOME/bin/toolchain/cmake/`

- `bin/cmake` (`bin/cmake.exe`), with its mode (zig's fetch sets the
  executable bit on an ELF or Mach-O file; the install keeps it);
- `share/cmake-4.4/Modules` and `Templates` (1,746 files, the same in
  the five archives), which cmake finds at `../share` from its own place
  (macOS: Kitware's archive is CMake.app/Contents/{bin,share}; cmake/
  takes bin/ and share/ from there, the same shape). Help/ (the manual's
  sources for `cmake --help-*`) is left out: no build reads it, and 24 of
  its file names have blanks ("Unix Makefiles.rst"), which SOURCES'
  `file:` lines cannot hold (decision A = keep out, pending). Licenses/
  (LGPLv3.txt, Qt's, for cmake-gui) is left out with cmake-gui;
- `SOURCES`: one block in conda's shape, written by conda.zig's writer:
  `package: cmake`, `version: 4.4.4`, `build:` the archive's platform
  (`linux-x86_64`, `macos-universal`...), the archive's URL and Kitware's
  sha256, `license: BSD-3-Clause`, `source:` cmake's source tarball
  (cmake-4.4.4.tar.gz with its sha256), `feedstock:
  https://github.com/Kitware/CMake v4.4.4`, and a file line per
  installed file: its path in the archive (under the archive's top
  directory) and the sha256 the toolchain build computes of it (an
  archive has no RECORD; zig itself checks build.zig.zon's hash of the
  whole tree);
- `LICENSES/cmake/`: the archive's doc/cmake/ less its manual (html/,
  CMake.qch, cmake.org.html): cmake's LICENSE.rst (Kitware's BSD-3-Clause
  text, which the source tree has as Copyright.txt), the CONTRIBUTORS.rst
  it names, and the licences of the libraries built into cmake (curl,
  libarchive, liblzma, librhash, libuv, nghttp2, zlib, zstd, cppdap,
  kwsys). On macOS curl, nghttp2 and zlib are the system's, so that
  archive has no cmcurl/, cmnghttp2/ or cmzlib/ texts (9 files, else 12).

Left out: ctest, cpack, ccmake, cmake-gui, cmcldeps (Windows), the macOS
app bundle's GUI files (MacOS/CMake, the Qt frameworks and plugins),
man/, the manual, share/aclocal, the editors' and shells' files. On
linux-64 cmake/ is 17 MB (du); its archive 10,214,209 bytes.

### How the tree gets it

`zigbuild/toolchain/build.zig.zon` has one lazy dependency per archive,
`cmake_linux_x86_64`, `cmake_linux_aarch64`, `cmake_macos_universal`
(both macOS arches), `cmake_windows_x86_64`, `cmake_windows_arm64`, as
it has pkgconf (and the root build.zig.zon cairo).
`zigbuild/toolchain/cmake.zig` pins the version, each archive's URL and
Kitware's sha256, the source tarball, and decides which files cmake/
gets (`wanted`); its tests check the zon's URLs are its. build.zig's
`installCmake` picks the archive for the host, asks for the dependency
(zig fetches it into zigbuild/toolchain/zig-pkg/, checks its hash and
runs the configure step again), walks the tree, installs the wanted
files and writes SOURCES. Never for the conda build (the prefix is the
env): conda keeps conda-forge's cmake, and that build fetches nothing.
There is no `-Dcmake` and no fetch script; `scripts/zig-toolchain.sh` is
as before the extras group.

zig 0.17 notes (rel11/scratchc-extras/zig-fetch.log,
lazy-unpack-probe.log). The `zig fetch` defect has its own record, with a
repro and the checks for each zig update:
feat-zig-017/ZIG-FETCH-CACHE.md (not reported upstream: the user,
2026-11-14).

- The hashes are what `zig fetch <url>` prints, and a build's own fetch
  computes the same. But `zig fetch` run outside a build caches a broken
  copy (global cache `p/<hash>.tar.gz` keeps the archive's top
  directory), and a later build that unpacks that copy stops with a
  hash mismatch. A broken cached copy of any of the five entries fails
  every build of this build.zig.zon, asked for or not (zig unpacks every
  cached lazy dependency up front): one bad linux-x86_64 copy stops a
  linux-aarch64 build too, and the conda build's run (recipe/build.sh),
  which asks for none. Delete `p/<hash>.tar.gz` from zig's global cache
  after such a `zig fetch`, or let the build fetch. The five hashes were
  checked through a build with the zon's own entries.
- zig's fetch sets the executable bit by content (ELF, Mach-O, `#!`)
  with mode 0777; the install copies it under the umask (0750 here,
  0755 on the runners), as zig/'s.
- A build unpacks every lazy dependency the global cache already has
  into zig-pkg/ (cheap, local); with an empty cache it downloads only the
  one asked for (65 MB on linux-64, 89 MB the macOS one).
- `pixi run toolchain-test` passes no -Dprefix (fix pass, below): its
  configure step stops before the tree's copies, so it fetches nothing
  (neither cmake nor Windows' pkgconf) and runs offline. The archive is
  fetched by `toolchain` (package-toolchain), once per CI leg.
- Windows: the longest path in the zips is 94 characters under the top
  directory (the manual's html/_sources); with the checkout and zig's
  cache paths about 220 of MAX_PATH's 260. Not run on Windows yet.

### The group in the scripts

`scripts/env.sh`: `TOOLCHAIN_GROUPS="compilers build-tools extras"`,
`group_dirs extras` = `cmake`; `group_ext` gives it the base's extension.
package-standalone.sh, unpack-toolchain.sh, compile-tree.sh,
verify-toolchain.sh's layout check and verify-bundle.sh's file lists
follow from that. The compile tree gets cmake/, so contract, pkg-parity
and stress run the group's cmake.

### How R finds it

The build-tools group's mechanism, one more PATH entry after usr/bin:

- unix `etc/Renviron` (build.zig, finalRenviron):
  `PATH=${R_HOME}/bin/toolchain/usr/bin:${R_HOME}/bin/toolchain/cmake/bin:${PATH}`
- Windows `etc/Rcmd_environ` (rcmdEnviron):
  `R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin;${R_HOME}/bin/toolchain/cmake/bin;${R_HOME}/../../usr/bin`
- Windows sessions: patch 0014 (Rprofile.windows) adds the same entry
  between the two it had.

A missing directory is harmless (conda, the wheel, a tree without the
group): conda's cmake is on PATH by activation (Library/bin on Windows).
`R_CUSTOM_TOOLS_PATH` on Windows replaces this entry too, as it replaces
usr/bin. macOS' `R_ZIG_CMAKE_TOOLCHAIN_FILE` lines in etc/Renviron are
unchanged. verify-tree.sh asserts the new lines; verify-bundle.sh's PATH
checks expect the new entry.

No wrapper named cmake: it would shadow a user's own.

### rzig

- `groups.zig`: `Group.extras`, archive extension as build-tools'
  (tar.gz, zip on Windows), and its text:

      Packages that build a bundled library with CMake need the r-zig extras for R 4.6.2 on linux-64: cmake.
        standalone:  extract R-4.6.2-linux-64-extras.tar.gz where you extracted R, or put cmake on PATH
        conda, pixi: pixi add r-zig-extras (or conda install r-zig-extras); r-zig-toolchain installs every group
        pip:         pip install cmake

  (pip: PyPI's cmake is the group there; Windows: "no wheels for Windows".)
- `check.zig`: `--rzig-check=extras` (cmake on PATH; missing: 127 and
  the text; installed in R's env but not on PATH is named as such, unix
  `<env>/bin`, Windows `<env>/Library/bin`). In `--rzig-check=package`,
  decision 3.1 A: when the package needs make (a Makevars rule, or a
  configure script R runs), its DESCRIPTION's SystemRequirements (with
  continuation lines, any case) names cmake, and no cmake is on PATH, rzig
  prints `<pkg>: note: its SystemRequirements name cmake, and no cmake on
  PATH: its build stops where it runs cmake` and the extras' text on
  stderr. The exit code is what it would be without the note. Patch 0009
  shows stderr as it comes, so the note shows in the install log.
- `main.zig`: the usage line names `extras`.

### verify-toolchain.sh

- linux: no exception. cmake/'s ELF files, as every other, may load
  glibc's libraries only (decision 3.2 A's libstdc++.so.6/libgcc_s.so.1
  exception for cmake/ was removed with the switch to Kitware's
  archives), at most GLIBC 2.28 (Kitware: 2.17 on x86_64, 2.28 on
  aarch64).
- macOS: universal Mach-O files (`ca fe ba be`, Kitware's cmake) are
  binaries too, so they are not skipped; `needed_of` (verify-helpers.sh)
  drops every otool header line (one per slice in a universal file).
- The macOS floor check reads every slice: env.sh's `macho_minos`
  prints the highest minos of a file, LC_BUILD_VERSION or
  LC_VERSION_MIN_MACOSX (it stopped at the first before). Kitware's
  cmake: x86_64 10.13 (LC_VERSION_MIN_MACOSX), arm64 11.0, so 11.0;
  under MACOS_MIN 13.0.
- The binary detection must see cmake/bin/cmake when cmake/ is there.
- cmake runs, says the version SOURCES records for `cmake`, and its
  CMAKE_ROOT (asked through `cmake -P`) holds
  `Modules/CMakeDetermineCCompiler.cmake`.

### verify-bundle.sh: a fourth scenario

Before the extras archive is extracted, `cmkpkg` (a synthetic package:
SystemRequirements `CMake (>= 3.10)`; its configure and configure.win
build a static library with `cmake -S cmklib -B cmkbuild` and
`cmake --build`, CC, AR and RANLIB from R CMD config; src/Makevars links
it) must get the preflight's note with the extras' text, go on, and stop
in its configure with "cmkpkg: no cmake on PATH" (unix: skipped with a
note when the host has /usr/bin/cmake or /bin/cmake). After extracting:
`R CMD <zig-cc> --rzig-check=extras` finds TC/cmake/bin/cmake, cmkpkg's
configure says it ran that cmake, and the package installs and loads.

### conda

`recipe/recipe.yaml`: the `r-zig-extras` output (inherit r-zig-build, no
run exports, `files: []`, run: exact r-zig-slim and `cmake`), with
`recipe/test-extras.R` (cmake on PATH is this env's and runs; rzig's
check finds it; off PATH it is named as installed in this env, with the
text). `r-zig-toolchain` pins r-zig-extras exactly. r-zig-slim's
files.exclude and its package_contents test both name `toolchain/cmake/`
(the conda build never makes it; the two lists stay the same).
`scripts/conda-consume.sh` gets an `extras` environment running
test-extras.R.

Size, for including it in r-zig-toolchain: conda-forge's cmake is a
26 MB download (88 MB installed, previous agent's reading of 4.4.4
linux-64); the compilers closure is about 1.9 GB. Not re-measured.

### stress

Nothing to switch: R puts TC/cmake/bin before the stress env's PATH
entries under R CMD (etc/Renviron, which bin/Rcmd sources, patch 0008;
Windows Rcmd_environ), so where the tree has the group its cmake runs,
and the stress env's cmake stays for conda runs. stress.R now records
which cmake R CMD runs (`info$cmake`, and in report.md's header line;
"none" when R CMD finds none).

One change for tree + env runs (dist=tree, compile-tree): the cmake that
runs is the tree's, whose own prefix is TC/cmake, not the env. CMake then
reaches the env's libraries only through PATH's `<env>/bin` (find_*
search `<prefix>/lib` and `<prefix>/include` for it) and
CMAKE_PREFIX_PATH, no longer through its own prefix. build.zig's comment
on the macOS CMake toolchain file says so now. The next stress run must
compare the CMake rows (s2, Rhdf5lib, RcppParallel, arrow:source) with
the recorded results; if one regresses, the fix is CMAKE_PREFIX_PATH=<env>
in stress, not a change to the tree.

### The wheel (design only, not built)

An `r_zig_extras` wheel with no files and `Requires-Dist: cmake==4.4.4`,
in make-wheel.py's TOOLCHAIN_DIST pattern; `r-zig-toolchain` (pip) would
require it. Until then groups.zig's pip line says `pip install cmake`.
cmake from PyPI lands in the venv's bin, which is on PATH when the venv is
active, so R finds it without a PATH entry.

## Files changed

- zigbuild/toolchain/cmake.zig (new): the pins (version, the five
  archives' URLs and Kitware's sha256, the source tarball), which files
  cmake/ gets (`wanted`), tests.
- zigbuild/toolchain/build.zig.zon: the five lazy `cmake_*` dependencies.
- zigbuild/toolchain/build.zig: `installCmake`; cmake.zig in `test`.
- scripts/env.sh: the extras group.
- build.zig: Renviron and Rcmd_environ PATH entries.
- zigbuild/patches/R-4.6.2/0014-rprofile-windows-tools-path.patch: the
  session's entry.
- zigbuild/tools/rzig/{groups,check,main}.zig: the group, its check, the
  note, tests.
- scripts/verify-toolchain.sh, scripts/verify-helpers.sh: closures,
  universal Mach-O, cmake's run.
- scripts/verify-tree.sh: the new PATH lines.
- scripts/verify-bundle.sh: PATH checks, scenario 4.
- recipe/recipe.yaml, recipe/test-extras.R (new), scripts/conda-consume.sh.
- stress/stress.R: records R CMD's cmake.
- .github/workflows/{toolchain,build-r,build}.yaml: the extras archive
  in the artifacts and comments.
- .gitignore: zig-pkg/'s comment names the cmake archives.
- .github/devdocs/feat-standalone-toolchain/{PLAN,TODO}.md: the group
  table's extras row, the TODO item; chore-release-11/PLAN.md: item D's
  design notes marked superseded.

Not changed any more (back to 7697c75): zigbuild/toolchain/wheel.zig
and build.zig's installZig, scripts/zig-toolchain.sh (a comment only).
scripts/fetch-cmake.sh is gone.

## Tests (linux-64, 2026-11-13), PyPI wheel (superseded)

The first implementation, cmake/ from PyPI's wheel. Logs in
rel11/scratchb-extras/. The tests of the current design are in the
section "Kitware archives (2026-11-13)" below.

| Command | Exit | Note |
|---|---|---|
| `zig fetch <cmake wheel URL>` | 1 | "unknown file type": the reason for fetch-cmake.sh |
| `pixi run --frozen bash scripts/fetch-cmake.sh` | 0 | cmake 4.4.4 runs from the unpacked wheel; modes kept |
| `pixi run --frozen toolchain-test` | 0 | wheel.zig's tests, cmake's included |
| `pixi run --frozen rzig-test` | 0 | 192/192 unit tests, parity 0 failed |
| `pixi run --frozen build -- -j6` | 0 | patch 0014 applies with -F0 |
| `pixi run --frozen smoke` | 0 | |
| `pixi run --frozen verify-tree` | 0 | the new Renviron line |
| `pixi run --frozen toolchain -- -j6` | 1, then 0 | first run: BlankInPath (Help/); after leaving Help/ out, 0 |
| `pixi run --frozen verify-toolchain` | 0 | 4 ELF files, cmake/'s libstdc++/libgcc_s allowed, GLIBC <= 2.17; cmake 4.4.4 = SOURCES; CMAKE_ROOT found |
| `pixi run --frozen compile-tree` | 0 | the compile tree has cmake/ |
| nloptr 2.2.1 (CRAN) R CMD INSTALL into the compile tree, `env -i`, PATH=/usr/bin:/bin (host has no cmake, no pkg-config) | 0 | "using cmake via .../bin/toolchain/cmake/bin/cmake", bundled NLopt built; loads, LBFGS solution 2 |
| the same with TC/cmake moved aside | 1 | the preflight's note and the extras' text, then nloptr's own "Could not find 'cmake'" |
| `pixi run -e pkg --frozen rattler-build build --render-only ...` | 0 | r-zig-extras renders (run: r-zig-slim exact, cmake); r-zig-toolchain pins it |
| `pixi run --frozen package-toolchain` | 0 | R-4.6.2-linux-64-extras.tar.gz, 9,951,550 bytes |
| `pixi run --frozen verify-package` | 0 | both passes (TC/zig, then the env's zig): scenario 4 and the cmkpkg check without the extras pass |

### Review fix pass (2026-11-13)

An independent review found no blocking defect on linux-64 and six
points; all were real and are fixed:

1. fetch-cmake.sh's header and this record said the wheel's cmake has
   curl and zlib built in on every OS; on macOS it loads the system's
   (above).
2. `macho_minos` read only the first slice of a universal file; it now
   prints the highest (above).
3. Stale "two groups" comments (build-r.yaml, verify-tree.sh, pixi.toml,
   compile-tree.sh, recipe.yaml), and r-zig-slim's files.exclude now
   names cmake/ as its not_exists test does.
4. build.zig's comment on the macOS CMake toolchain file assumed the
   env's cmake runs; corrected, and the stress section above names the
   rows to compare.
5. stress.R's `info$cmake` was NA when R CMD has no cmake; now "none".
6. conda-package and conda-consume had not run; they have now (below).

| Command | Exit | Note |
|---|---|---|
| `macho_minos` against a fake otool (universal 10.10 + 11.0; 13.0 + 13.10.1; thin; none), with mawk, gawk and gawk in POSIX mode | 0 | 11.0, 13.10.1, 13.0, empty |
| `bash scripts/verify-toolchain.sh <copy>` with usr/bin/make replaced by cmake's binary (SOURCES' sha updated) | 1 | expected: "needs libstdc++.so.6 (not glibc's; only cmake/ may)" for usr/bin/make |
| `pixi run --frozen verify-toolchain` | 0 | after the env.sh change |
| `pixi run --frozen verify-tree` | 0 | |
| stress.R's cmake probe under the compile tree, `env -i` | 0 | with cmake/: TC/cmake/bin/cmake; with cmake/ moved aside: "none"; stress.R parses |
| `pixi run -e pkg --frozen conda-package` | 0 | all five outputs; r-zig-extras' test-extras.R passed with conda-forge's cmake 4.5.0 (the solver's newest; r-zig-extras does not pin a version); r-zig-slim's tests passed with the new exclude |
| `pixi run -e pkg --frozen conda-consume` | 0 | five environments; extras: cmake on PATH, the check finds it, off PATH named as installed in the env |

Not run: `pixi lock` (pixi.toml changed only in a comment).

## Kitware archives (2026-11-13)

The decision (the user, 2026-11-13): the standalone tree's cmake/ comes
from Kitware's release archives on GitHub, not PyPI's wheel, with no
fallback to the wheel; conda keeps conda-forge's cmake (r-zig-extras
unchanged); PyPI's cmake stays a pip user's cmake (make-wheel.py does
not involve cmake). Why: the wheel's linux cmake needs libstdc++.so.6
and libgcc_s.so.1 (manylinux policy); Kitware's
cmake-4.4.4-linux-x86_64.tar.gz bin/cmake needs only glibc, GLIBC_2.17
at most.

What changed:

- cmake/ from build.zig.zon's lazy `cmake_<platform>` dependencies
  (cmake.zig, installCmake; "How the tree gets it" above), one per
  archive, the macOS universal one for both macOS arches. No fallback.
- Deleted: scripts/fetch-cmake.sh, the `-Dcmake` option and its
  plumbing in zig-toolchain.sh. wheel.zig and installZig are back to
  ziglang only, byte for byte as at 7697c75; zig/ is the same tree as
  before (its SOURCES and every file's sha256 equal those of the other
  rel11 worktrees' trees).
- SOURCES: `build:` the archive's platform; `feedstock:` Kitware's
  repository and tag; file lines with the build's sha256 (no RECORD).
- LICENSES/cmake/: the archive's doc/cmake/ less the manual; no
  dist-info texts any more (Apache-2.0 was the wheel's packaging).
- verify-toolchain.sh: the libstdc++/libgcc_s exception for cmake/ is
  gone (decision 3.2 A void); the universal Mach-O detection, the
  minos-across-slices check and cmake's run, version and CMAKE_ROOT
  checks stay.
- Comments and records naming the wheel: toolchain.yaml, recipe.yaml
  (a comment only), env.sh, groups.zig, verify-toolchain.sh,
  zig-toolchain.sh, .gitignore, feat-standalone-toolchain PLAN/TODO,
  chore-release-11 PLAN.
- CI: nothing new. The toolchain build fetches the archive itself, as
  Windows' pkgconf (GitHub's runners have the network); toolchain.yaml
  runs toolchain-test, package-toolchain and verify-toolchain in one job,
  so one download per leg.

Tests (linux-64; logs in rel11/scratchc-extras/):

| Command | Exit | Note |
|---|---|---|
| `sha256sum -c cmake-4.4.4-SHA-256.txt` on the five archives | 0 | all five OK |
| static reading of the five archives' cmake (readelf, objdump, a Mach-O/PE reader) | 0 | the table under "Where cmake comes from" |
| `zig fetch <url>` for each of the five | 0 | the hashes in build.zig.zon; its cached copies were broken (above) and removed |
| a probe build asking for each of build.zig.zon's five dependencies, its entries as they are | 0 (each) | every hash resolves (zon-hash-check.log); with an empty global cache only the one asked for is downloaded |
| `pixi run --frozen toolchain-test` | 0 | cmake.zig's tests among them |
| `pixi run --frozen rzig-test` | 0 | 126 identical, 60 identical but for rzig's own-environment flags, 33 deliberate, 0 failed |
| `flock heavy.lock pixi run --frozen toolchain -- -j6` | 0 | cmake/ (cmake): 1,760 files, 1,747 file lines, 17 MB; bin/cmake 0750 under umask 027 |
| `pixi run --frozen verify-toolchain` | 0 | 4 ELF files, glibc's only, GLIBC at most 2.17; cmake 4.4.4 = SOURCES; CMAKE_ROOT cmake/share/cmake-4.4 |
| `verify-toolchain.sh <copy>`: `cp -al` of the tree, cmake/bin/cmake replaced by the wheel's (needs libstdc++), SOURCES' sha updated | 1 | expected: "cmake/bin/cmake: needs libstdc++.so.6 (not glibc's)" and the same for libgcc_s.so.1 |
| `flock heavy.lock pixi run --frozen compile-tree` | 0 | the compile tree has Kitware's cmake/ |
| nloptr 2.2.1 into the compile tree, `env -i`, PATH=/usr/bin:/bin (no host cmake) | 0 | "using cmake via .../bin/toolchain/cmake/bin/cmake", bundled NLopt built; loads, LBFGS solution 2 |
| the same with TC/cmake moved aside | 1 | expected: the preflight's note and the extras' text, then nloptr's "checking for cmake... no" |
| `flock heavy.lock pixi run --frozen package-toolchain` | 0 | R-4.6.2-linux-64-extras.tar.gz, 10,214,209 bytes |
| `flock heavy.lock pixi run --frozen verify-package` | 0 | both passes (TC/zig, then the env's zig): scenario 4 finds TC/cmake/bin/cmake and cmkpkg installs and loads; without the extras, the note and the configure's stop |
| `pixi run --frozen toolchain-test`, `toolchain`, `verify-toolchain` again after the last build.zig change (the dependency's root as a real path) | 0, 0, 0 | the same tree |
| `pixi run -e pkg --frozen rattler-build build --render-only` for linux-64, osx-arm64, win-arm64 | 0 (each) | recipe.yaml changed in a comment only; r-zig-extras renders on all three |

| `flock heavy.lock pixi run -e pkg --frozen conda-package` | 0 | recipe.yaml changed in one comment; all outputs; r-zig-extras' test-extras.R passed with conda-forge's cmake 4.5.0 |
| `flock heavy.lock pixi run -e pkg --frozen conda-consume` | 0 | extras environment: cmake on PATH, the check finds it, off PATH named as installed in the env |

### Kitware archives: review fix pass (2026-11-13)

The review found no defect in the switch; it found these, fixed here:

- README.md had not been updated for the extras group at all (two
  groups, three archives, three scenarios, no cmake): it now names three
  groups and r-zig-extras, the extras archive (what it holds, its PATH
  entry, what its cmake loads), four archives and four scenarios, the
  five conda packages, and that there is no extras wheel (`pip install
  cmake`).
- pixi.toml: verify-package's comment says four scenarios.
- The zig 0.17 cache trap is broader than recorded: a broken cached copy
  of any of build.zig.zon's entries fails every build of it, asked for
  or not. The zon comment and the zig notes above say so.
- `toolchain-test` needed network on every OS (its -Dprefix made the
  configure step ask for the archive). zig-toolchain.sh now passes no
  -Dprefix for `test`: the configure step stops before the tree's copies
  (build.zig's documented "without it, only `test` runs"), so the unit
  tests fetch nothing and read no conda-meta. This also drops Windows'
  pkgconf fetch from `toolchain-test`. CI loses nothing: package-toolchain
  in the same job runs the full configure step.

| Command | Exit | Note |
|---|---|---|
| `pixi run --frozen toolchain-test` | 0 | fix/toolchain-test.log |
| offline check: the new test command, empty zig global cache, no zig-pkg/, an unreachable proxy | 0 | 45/45 tests passed (fix/offline/new.log) |
| the same with -Dprefix (the command before the fix) | 1 | expected: "fetching lazy dependency" of cmake_linux_x86_64, ConnectionRefused (fix/offline/old.log) |
| `pixi run --frozen rzig-test` | 0 | 126 identical, 60 identical but, 33 deliberate, 0 failed |
| `flock heavy.lock pixi run --frozen package-toolchain` | 0 | runs toolchain; every group's SOURCES byte-identical to before the fix (fix/sources-sha.txt); extras archive 10,221,003 bytes |
| `pixi run --frozen verify-toolchain` | 0 | cmake 4.4.4, CMAKE_ROOT found |
| `flock heavy.lock pixi run --frozen verify-package` | 0 | both passes; scenario 4 and the no-extras check |

No recipe file changed in the fix pass, so conda-package, conda-consume
and the render-only checks were not re-run.

## Not done, and what macOS and Windows must run

- macOS (osx-arm64 and, under Rosetta, osx-64): `pixi run toolchain`
  (fetches the universal archive, symlinks and all: the archive has the
  Qt frameworks' links, which zig's fetch makes and cmake/ does not
  take), `pixi run verify-toolchain` (universal Mach-O path, minos 11.0
  across slices, only /usr/lib and /System; CMAKE_ROOT through ../share
  from bin/, outside the app bundle), `pixi run package-toolchain`,
  `pixi run verify-package` (scenario 4, with etc/r-zig.cmake as
  CMAKE_TOOLCHAIN_FILE), `pixi run -e pkg conda-package` and
  `conda-consume` (test-extras.R). Kitware's macOS cmake is signed; a
  copy of bin/cmake keeps its embedded signature.
- Windows (win-64; win-arm64 in CI only): the same, plus: zig's fetch of
  the zip under MAX_PATH (about 220 characters at most, above),
  Rcmd_environ's and the session's new PATH entry (verify-bundle's
  path.R and session-path.R), cmkpkg's configure.win with
  CMAKE_GENERATOR="MSYS Makefiles", patch 0014 applying with -F0, and
  the conda package's Library/bin/cmake.exe found by
  `--rzig-check=extras`.
- linux-aarch64: CI (GLIBC 2.28, at the ceiling).
- The r_zig_extras wheel.
- Pending user decision A: Help/ stays out (24 file names with blanks).
