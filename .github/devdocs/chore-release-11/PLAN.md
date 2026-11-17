# chore-release-11 — one pull request for the whole backlog

Branch: feat-win-arm64 (pull request #48, retargeted to main after #45,
#46 and #47 merged on 2026-11-12). Recipe build number: 11, not yet
published.

Status (2026-11-17, later): feat-win-arm64 at 3c9899e, which holds only
zigbuild/tools/rzig/clear_cache.c and clear_cache.zig; the other 20
files of findings 33-36 (CMake 4.4.5, m2-tar, rzig's clear_cache.o, the
record patch, lock a2d8b95874eb) were staged but left out of that
commit. CI on 3c9899e (build-r 44061457328, upstream-zig 44061457294)
is green but tests none of findings 33-36. Stress run 44111538560 on
3c9899e (arrow, arrow:source, duckdb, magick; six runners, tree and
conda) repeats run 43947228208: arrow and arrow:source fail on every
linux and macOS leg at Boost's locale CMakeLists:236 (CMake 4.5.0),
duckdb fails configure on both Windows tree legs, magick on
windows-11-arm fails at `__clear_cache`; duckdb ok on the other ten
legs, magick ok on macOS and windows-latest, fail-abi on linux as
expected. Next: commit the rest of findings 33-36, CI, the same
targeted stress dispatch, the publish preflight, the release of build 11.

Status (2026-11-17; superseded): feat-win-arm64 at bfb510a (findings 25-32);
T/wt/rel11-fix holds findings 33-36 (the stress triage of run
43947228208: CMake held at 4.4.5, m2-tar in the build-tools group,
rzig's clear_cache.o for win-arm64, the record patch) as working-tree
changes, with zigbuild/tools/rzig/clear_cache.c and clear_cache.zig
untracked. Lock a2d8b95874eb (cmake 4.4.5 in the stress env). Next: the
user commits and pushes, CI, a targeted stress dispatch (arrow,
arrow:source, duckdb, magick on all six runners, tree and conda), then
the publish preflight and the release of build 11.

Status (2026-11-16; superseded): one tree, T/wt/rel11-fix (feat-win-arm64 at
5dd40cf, which holds findings 25-30; 31 and 32 uncommitted):
findings 25 (recipe/variants.yaml), 26 (stress on win-arm64), the review
corrections, 27 (the lock bump), 28 (etc/r-zig.cmake on every OS;
Rhdf5lib), 29 (rzig names R's target to zig and flang on every OS;
the env.sh platform guard; the pango and harfbuzz pins lifted), 30
(clang's CPU names in -march/-mcpu; arrow on macOS x86_64) and 31 (the
C++ ABI on linux: the r-base constraint, three Bioconductor stress
rows; 2026-11-16) and 32 (rzig passes objects with unknown extensions,
such as htslib's .pico, as cached .o copies; 2026-11-16). Lock
55d166564bd6 (dadd317726cf before finding 29's pango lift), unchanged
by 31 and 32. The linux-64 chain, conda-package and the Rhdf5lib,
DESeq2, scran and Rsamtools stress rows pass there. Next: the user
commits findings 31 and 32 on feat-win-arm64, then the CI full tier
(`full-ci` label), then a stress dispatch on all runners (tree and
conda), then the publish preflight and the release of build 11.

Status (2026-11-13; superseded): pushed up to 51588ad (findings 17 and 18 fixed;
CI run 43487408414 green but for windows-11-arm's hermetic step,
finding 20). The three items are done and merged in the integration
tree T/wt/rel11-int (branch rel11-int), with the fixes the host chains
found (findings 19-21); they reach this branch as one patch per commit
(T/rel11/int/patches, "State" below). Open: the decisions listed under
"To resume", the stress run, the release.

Status (2026-11-12, night; superseded): pushed up to 8424d56. CI run 43344258167
passed everything except macos-15-intel default and minimal (finding
17) and windows-11-arm default at pkg-parity (finding 18).
windows-11-arm's contract passes. Not yet committed in this tree: the
probe step's removal from build-r.yaml, the diagnostics in
scripts/verify-tree.sh and scripts/pkg-parity.sh, and findings 13-18
(T/rel11/handover/diag-avx-make.sh commits and pushes them), and the
docs review's edits (README, stress/README, pixi.toml and recipe
comments, the finding-12 records, zigbuild/toolchain/build.zig.zon,
scripts/conda-consume.sh's comment), which diag-avx-make.sh does not
commit. Open: the three items below, findings 17 and 18, the stress
run, the release.

## Decisions (user, 2026-11-12)

- One release at the end of the whole backlog. No publish, no
  `CONDA_PUBLISH` and no further build-number bump before it.
- One large pull request to test everything together: R's latest
  release (4.6.2), zig 0.17, Windows on ARM working, the open
  follow-ups, and the items below. The stress run comes last.
- The yardstick: "simplicity and feature parity between the different
  targets, OSs, arches. Minimizing the amount of shelling out and
  workarounds."
- The release publishes conda packages only. The standalone archives
  and the wheels are released "only when we know we can build a good
  number of packages and feature parity across targets is stable".
- Into this pull request: `R CMD config` through rzig, libR hiding its
  internal symbols, the extras group (cmake), and the recommended
  packages, which "need to ship on their own conda package".
- After the release, one pull request each: native Windows build tools
  (no MSYS2), one base with add-ons (tcltk first, a really slim Windows,
  a Windows wheel), the C++ ABI boundary and a binary package
  repository. (2026-11-14: the really slim Windows moved into release
  11, finding 23.)
- The conda base keeps its name, r-zig-slim.
- BLAS (2026-11-13): no change for build 11. conda-forge's packages
  are preferred over distro- or OS-specific ones; until a route is
  chosen, r-zig only needs to stay compatible with conda-forge's.

### A later BLAS route (recorded 2026-11-13, not planned)

conda-forge selects the BLAS of an environment by a package build:
`pixi add "libblas=*=*openblas"` (or mkl, blis, accelerate...) swaps
the implementation without a rebuild, but only for programs linked
against `libblas`/`liblapack` (the `blas`/`lapack` names). R's
default build uses its internal Rblas/Rlapack and is not affected.
The openblas variant links libopenblas by name (build.zig
`linkBlas`/`linkLapack`), so it cannot be switched. Switching it is
about ten lines in build.zig (link `blas` and `lapack`) and a pixi
feature with `libblas`/`liblapack` in place of `openblas`.
Implementations libblas 3.11 has per subdir: linux-64 openblas, mkl,
blis, netlib; linux-aarch64 openblas, blis, netlib, nvpl; osx-64 and
osx-arm64 openblas, accelerate, newaccelerate, blis, netlib; win-64
mkl, openblas, blis, netlib; win-arm64 openblas, netlib. Most are
built with gfortran and bring libgfortran into the environment.

Reviewed and found not needed: flang-pixi's "upstream-zig switch"
(building flang-pixi's own packages with the ziglang.org tarball).
Nothing here depends on it: r-zig-pixi uses the flang driver, the module
files and libflang_rt.runtime.a by exact pin, rzig links with the user's
zig, and both zigs are tested for R and packages (upstream-zig.yaml).
flang-pixi measured identical machine code from both zigs. Its record:
flang-pixi docs/19 §6.

## What changed

### R 4.6.2

- `R_VERSION`, build.zig's `r_version`, the recipe's version, the
  checksum file, `zigbuild/patches/R-4.6.2/` (renamed; all 14 patches
  apply to 4.6.2 with no offset and no fuzz).
- The build graph needs no change: 4.6.2 adds one R file
  (parallel/R/mvrnorm0.R, which the build collects by listing the
  directory) and changes no makefile's source list.
- The captured configs (zigbuild/config/). A real configure run of 4.6.2
  on linux-x86_64 (slim) changed only the version strings and
  `R_SYSTEM_ABI`, whose Fortran words are now `flang,flang` (4.6.1's
  configure said `ClassicFlang` for a compiler named flang). The same
  lines were changed in the other eleven unix directories;
  `win-full/GENERATED_FROM` names 4.6.2.

### flang 23.1.5 and one libomp

- flang-zig 0, flang-rt-zig 1 (flang-pixi's LLVM 23.1.5 release). The
  lld-zig pins are gone: flang-zig depends on its own build of it.
- llvm-openmp is flang-pixi's build (`universe`, build string `zig_*`,
  build 1) on all six platforms, in pixi.toml and in the recipe's host,
  and r-zig-slim's and r-zig-compilers' run dependency is
  `llvm-openmp >=23.1.5 zig_*`. With conda-forge as the first channel
  the build string selects it only as pixi.toml's direct requirement;
  as a dependency strict priority filters it, so universe is now the
  first channel everywhere (findings 7, 13, 14). It has conda-forge's
  file names (omp.h, libomp.so / .dylib / .dll, libomp.lib,
  libomp.dll.a) and no dependency but the C library.
- Why: conda-forge's win-arm64 libomp.dll passes a parallel region only
  its first six shared variables (feat-win-arm64/PLAN.md); data.table's
  sort crashed on windows-11-arm. One libomp built one way on every
  platform, not a win-arm64 exception.
- The lock changed in these packages only: flang-zig, lld-zig,
  flang-rt-zig and llvm-openmp, six platforms each. Later its
  `channels:` blocks were reordered, universe first (finding 15).
- flang-pixi pruned build 0 of flang-rt-zig and llvm-openmp the day it
  published build 1 (2026-11-12): a lock that names a pruned build gives
  a 404 on a machine without it in its cache. `pixi lock` kept the
  locked llvm-openmp build 0 while the spec allowed it, so the spec
  names the build number too (`zig_*_1`).

### Hidden symbols on linux, as on macOS and in CRAN's R

- linux's captured config had no `HAVE_VISIBILITY_ATTRIBUTE`, and macOS's
  had it. Cause: configure asks `$CC -Werror -S conftest.c`, and `zig cc`
  gives clang `-c` beside `-S`, so clang warns that `-c` is unused: an
  error with `-Werror` (zig 0.17.0 and 0.17.1, conda-forge's and
  upstream's). macOS's configure takes another branch.
- rzig (compiler.zig) and the capture shims (toolchain/zig-cc,
  toolchain/zig-cxx) add `-Wno-unused-command-line-argument` to a command
  with `-S`. This also serves every package whose configure script
  probes that way.
- With that, a real configure run on linux says
  `r_cv_visibility_attribute=yes`: `HAVE_VISIBILITY_ATTRIBUTE 1`
  (config.h and Rconfig.h), `C_VISIBILITY` and `CXX_VISIBILITY`
  `-fvisibility=hidden`. The six linux directories have these lines.
- build.zig gives `$(C_VISIBILITY)` to the directories whose makefile
  does (CGroupOpts.visibility): src/extra's tre, tzone and xdr, the
  internet module, and stats, graphics, grid, methods, parallel,
  splines, tools, utils and tcltk. It applied to no directory before, on
  macOS too.
- linux-64, slim: libR.so exports 1257 symbols (2541 before; CRAN's
  about 1259); utils, tools, methods, graphics, grid, splines and
  parallel export their R_init function only; internet.so one symbol.

### R_compiled_by()

- build.zig reads CC_VER and FC_VER from the compilers of the build on
  every OS (versionLine: the first line of `zig cc --version` and of
  `flang --version`) and writes them into config.h (setDefine on unix,
  the `@CC_VER@` and `@FC_VER@` tokens on Windows). The captured strings
  said clang 21.1.8 and flang 23.1.1 under zig 0.17 and flang 23.1.5;
  Windows had a fixed text.

### Windows on ARM

- windows-11-arm is a leg of build.yaml as the other five platforms:
  toolchain, the default build leg in the core tier, conda-package and
  the publish. win-arm64.yaml and its label are gone.
- build-r.yaml's temporary win-arm64 probe step is removed: the
  contract passed on windows-11-arm (run 43344258167); committed as
  6d52bbd.

### Windows follows the unix variants (finding 23, 2026-11-14)

- One variant table in build.zig for every OS. slim, full and minimal
  exist on Windows with unix's features; build.zig checks each vendored
  config against the table.
- Windows r-zig-slim is slim: no tcltk, jpeg(), tiff() or NLS. Windows
  full installs R's libintl.h.
- OpenMP inside R on Windows slim and full, as on unix (upstream leaves
  it off). A patch to winbitmap.c lets a variant drop a bitmap format.
- pixi.toml and the lock: Windows-only removals; minimal on win-64 and
  win-arm64. CI's full tier: Windows full and minimal (20 legs).
- Record: .github/devdocs/feat-win-variants/PLAN.md.

### Small follow-ups

- stress.R `--conda` (K2), test-preflight.R's message and wheel-test.sh's
  mktemp (N9).
- evex512: not needed with zig 0.17 (feat-standalone-toolchain/TODO.md).

### The three items (done 2026-11-13)

Each was implemented in its own worktree from 7697c75, reviewed by a
second agent and fixed, then merged into T/wt/rel11-int. Their records:

- `R CMD config` through rzig, no make and no sh, on every OS:
  .github/devdocs/feat-config-rzig/PLAN.md.
- The extras group, `R_HOME/bin/toolchain/cmake/` from Kitware's cmake
  4.4.4 release archives (the user, 2026-11-13: not PyPI's wheel, whose
  linux cmake needs libstdc++ and libgcc_s), and the conda package
  `r-zig-extras` (conda-forge's cmake): .github/devdocs/feat-extras-group/PLAN.md.
- R's 15 recommended packages, built by zigbuild/recommended/build.zig,
  as the opt-in conda package `r-zig-recommended` and a standalone
  archive: .github/devdocs/feat-recommended-packages/PLAN.md.

Also in the integration tree: setup-pixi v0.11.3 in every workflow (as
flang-pixi), README sections for the three items, and findings 19-21.

## Findings (2026-11-12)

1. R 4.6.2 is CRAN's latest release (2026-10-29; R-latest.tar.gz is the
   same file; 4.7.0 is devel only). sha256
   c297040f6392b1dac6e5c0eb398422cfdaedf540ae2205edb9ad0d10cb10ee00.
   Against 4.6.1: 136 files differ, 1 new R file, 11 recommended
   tarballs replaced; build-relevant changes are configure/m4's
   R_SYSTEM_ABI words, Rdll.hide (+dim2total), shext.c, Rmath.h0.in,
   parallel's DESCRIPTION (Imports stats), stats' NAMESPACE, tzdata
   2026e. None changes build.zig's source lists.
2. `zig cc -S` warns "argument unused during compilation: '-c'" (zig
   0.17.0 conda-forge and 0.17.1 upstream): with -Werror an error. No
   upstream report was filed.
3. linux's captured configs lacked HAVE_VISIBILITY_ATTRIBUTE because of
   finding 2; macOS's had it. build.zig applied $(C_VISIBILITY) to no
   directory on any OS.
4. The captured CC_VER/FC_VER were stale (clang 21.1.8, flang 23.1.1).
5. evex512: zig 0.17 has no such CPU feature; AVX-512 target-attribute
   functions compile at -mcpu=baseline. The TODO item is closed.
6. conda-forge's win-arm64 libomp.dll (llvm-openmp 23.1.5 hef4af3d_0)
   is the cause of windows-11-arm's contract crash (feat-win-arm64).
   flang-pixi's zig-built llvm-openmp replaces it on every platform.
7. Channel order: with `channels = ["conda-forge", universe]` a bare
   `llvm-openmp` resolves to conda-forge's; `build = "zig_*"` selects
   universe's in every order ONLY as a direct requirement (pixi.toml).
   As a package's dependency (flang-rt-zig 23.1.5 `_1`, the r-zig recipe's
   run requirements) strict priority filters it: conda-forge first makes
   flang-rt-zig uninstallable (flang-pixi test.yml run 43337035109). Fixed
   2026-11-12: universe listed first everywhere (pixi.toml, the
   conda-package task, scripts/conda-consume.sh, stress.R, README
   `--prepend`), and universe's prefix.dev base relation to conda-forge
   removed by the user (a base channel outranks the channel). Details:
   findings 13 and 14. `pixi lock` keeps an already locked build that
   the spec still allows, even after the channel deleted it: name the
   build number in the spec.
8. flang-zig 23.1.5 depends on `lld-zig ==23.1.5 *_0` itself.
9. The bash shims in toolchain/ (zig-cc, zig-cxx, zig-ar, zig-ranlib,
   834 lines) are used only by the configure capture
   (zigbuild/tools/configure-only.sh, gen-config.yaml) and as rzig's
   parity reference (rzig-test). A candidate to remove: capture with
   rzig itself.
10. pixi.toml has six per-platform `conda-publish` tasks that differ in
    the subdir only.
11. omicron: LuLu blocks network access of binaries at new paths; a tree
    under `~/.pixi/` matches the user's directory rule
    (`/Users/luciorq/.pixi/*`). The test trees are in
    `~/.pixi/rz-rel11/`.
12. The larger-items review (an agent's report, 41 items) found these
    still worth doing after the release, beyond the user's list: the
    C++ ABI boundary (sf, terra, magick, V8 on linux are expected
    failures), WinRT headers missing from zig's MinGW (s2, sf, lwgeom on
    Windows), libcurl -> libpsl -> ICU in the wheel (14 of 49 MiB), a
    win-arm64 stress subset without system libraries, the release job
    for standalone archives and PyPI (B12). Not needed: flang-pixi's
    upstream-zig switch, `zig build fetch`, v3 package flags,
    R_ZIG_TOOLCHAIN_ENV, ARM64 Control Flow Guard (until a package hits
    it). Stale records it listed (line numbers as of 2026-11-12) are
    not all corrected yet:
    feat-standalone-toolchain/PLAN.md:5-7, :6787, :6872, :6899-6904,
    :6944-6947, :6961; TODO.md:149-161, :1091-1096, :1241-1254;
    feat-win-zig-binutils/PLAN.md:265-280; feat-wheel-minimal/PLAN.md
    :3-14, :103, :127-135; consolidation/PLAN.md:16-18, :65-68, :190;
    zigbuild/toolchain/build.zig.zon:5 (minimum_zig_version 0.16.0).
    (2026-11-12, night: all corrected, with dated notes; build.zig.zon
    now says 0.17.0. Uncommitted.)
    (2026-11-15: the win-arm64 stress subset is done in build 11:
    finding 26.)

13. **Channel order (2026-11-12, after the interim records).** Finding 7
    held only for direct requirements. flang-rt-zig 23.1.5 `_1` requires
    `llvm-openmp ==23.1.5 zig_*`, and the r-zig recipe's run requirements
    carry the same: as a package's dependency, strict channel priority
    filters it, and with conda-forge first flang-rt-zig is
    uninstallable (flang-pixi test.yml run 43337035109:
    `llvm-openmp 23.1.5 is excluded because due to strict channel
    priority ... 'https://prefix.dev/universe/'`). universe also had a
    prefix.dev base relation to conda-forge; prefix.dev ranks a base
    channel ABOVE the channel (`base -> current -> overrides`), which hid
    universe's llvm-openmp in every order. The user removed it (Base and
    Overrides empty); flang-pixi test.yml run 43339367038 then passed on
    all six with `llvm-openmp zig_*_1` installed from universe. Live
    solves of `flang-rt-zig ==23.1.5` alone (+ conda-forge fftw):
    universe first, strict → ours on all six; conda-forge first, strict →
    unsolvable; either order, disabled → ours. Records: flang-pixi
    docs/10 2026-11-12, docs/18 §5.4.
14. **Universe first everywhere.** pixi.toml `channels`, the
    conda-package task (`-c https://prefix.dev/universe -c conda-forge`),
    scripts/conda-consume.sh, stress/stress.R, README (`pixi workspace
    channel add --prepend`). No workflow or recipe sets channels. The
    old reason for conda-forge first (the base relation pulled
    conda-forge from prefix.dev's lagging mirror) is gone with the
    relation.
15. **The lock keeps its tested solution.** Changing the channel order
    makes `pixi lock` re-solve everything (~1400 conda-forge entries,
    python 3.14 → 3.15 among them; parked, untested, at
    T/rel11/pixi.lock.full-resolve). Instead the tested lock's eight
    `channels:` blocks were swapped (16 lines; sha 59a4052f23ca);
    `pixi lock --check` accepts it. Valid because no universe package
    name (llvm-openmp, flang-zig, lld-zig, flang-rt-zig, r-zig-*, blast,
    blast-scripts, polyglot, tradetracker, marimo-r) is locked from
    conda-forge.
16. **The recipe kept R 4.6.1's sha256** (4da6e61d...); conda-package
    failed on all six (run 43341267916). Fixed: c297040f... (checked
    against CRAN's tarball). No other stale 4.6.1 reference outside
    historical records.
17. **macos-15-intel: one VEX instruction in libR.dylib** (run
    43344258167, default and minimal; `full` skips verify-tree):
    `lib/R/lib/libR.dylib: 1 VEX/EVEX instructions, 0 on %ymm, 0 on
    %zmm`. Ruled out on gamma with llvm-objdump: flang-rt-zig osx-64's
    `libflang_rt.runtime.a` (23.1.5 `_1` and 23.1.1 `_11`: 0 each), and
    libR's 15 Fortran files (src/appl, src/main) compiled with flang
    23.1.5 and 23.1.1 for x86_64-apple-macos13.0 with CI's flags (0
    each). Left: C objects or zig runtime code built for the runner's
    CPU. omicron cannot reproduce a native-CPU leak (Rosetta reports no
    AVX). verify-tree.sh now prints the function and instruction of
    the first 10 hits per binary (tested on glibc's memcpy).
    Resolved 2026-11-13 (run 43437326154 named it: `_bcEval_loop`,
    `vpaddd %xmm7, %xmm5, %xmm7`): a false positive. The bytes c5 d1 fe
    ff are one entry of a jump table that clang keeps inside __text on
    Mach-O (LC_DATA_IN_CODE, 245 entries in libR.dylib); plain
    `objdump -d` decodes it as code. Reproduced on omicron's osx-64
    tree (same address, e063c). verify-tree.sh now runs `objdump --macho
    -d` on macOS, which prints those tables as `.long` data: 0 VEX in
    22 binaries there; conda-forge's libdeflate still shows 893, so the
    check still detects real AVX code.
18. **windows-11-arm: make segfaults in pkg-parity** (run 43344258167):
    `scripts/pkg-parity.sh: line 405: Segmentation fault ... "$mk" -s -f
    "$mconf" -f "$pl/print-var.mk" print-compilers`, after the contract
    passed (R's own make calls worked there). The difference: here make
    is started from Git bash directly. Unconfirmed suspect: two MSYS
    runtimes in one process tree under ARM emulation. pkg-parity.sh now
    logs which make it runs and `make --version` on Windows.
    Resolved 2026-11-13 (run 43437326154): the make is the toolchain's
    own (R_HOME/bin/toolchain/usr/bin/make), and even `make --version`
    segfaults when Git bash starts it, while every make R started in the
    same job worked (tier-1 INSTALL through make for cli, digest,
    quadprog, Rcpp; nine R CMD SHLIB shapes). pkg-parity's pkgload step
    now runs make from R (system2), as pkgload does; the probe is gone.
    Left open, recorded: an MSYS make started directly by Git bash on
    windows-11-arm crashes; R, the supported caller, is not affected.
19. **macOS: zig's compiler_rt debug map names build paths** (omicron,
    osx-arm64, 2026-11-13): verify-recommended.sh failed on
    `Matrix/libs/Matrix.so: .../build/rzig-cache/r-zig/zig-lib-<n>/lib/zig`.
    The bytes are STABS entries of a debug map in the string table: SO
    `<zig lib dir>`, SO `compiler_rt`, OSO `<zig cache>/o/<hash>/
    libcompiler_rt.a(compiler_rt_zcu.o)`. zig builds compiler_rt with
    debug info and its MachO linker writes a debug map for any library
    that pulls a member in; Matrix was the one recommended package to do
    so. libc++ and libc++abi are built the same way: every C++ library
    (Rcpp and the rest) gets a debug map into zig's cache too (review: a
    -g0 C++ dylib had 18 OSO entries, libc++abi.a(cxa_exception.o),
    libc++.a(string.o), ...). Reproduced on gamma (zig 0.17.0 and
    upstream 0.17.1, aarch64 and x86_64, `-dynamiclib -undefined dynamic_lookup` of a -g0 object with
    a _Float16 conversion and `__builtin_available`): 1 OSO path, ~3700
    STABS. -Wl,-S, -s and -Wl,--strip-debug do the same there: no STABS,
    no path, a compiler_rt built without debug info (dylib 343 to 260
    KB); the package's local symbols, exports trie, binds, load commands
    and dylibs unchanged (compiler_rt's ___anon_* locals go with its debug
    build); arm64's ad hoc signature rewritten (page hashes check).
    -Wl,-x drops the local symbols and keeps the debug map. Fixed: rzig
    applies linux's rule on macOS links (strip.zig, compiler.zig): no -g
    option and no input *.o with debug info (a 64-bit Mach-O object with
    __debug_info in __DWARF) gives -Wl,--strip-debug. The bash shims
    zig-cc and zig-cxx do the same, for parity-test.sh (it emulates
    macOS with a uname that answers Darwin); as on linux they do not read
    objects. A malformed segment command (section headers past its
    cmdsize) counts as no debug info. The C++ case is fixed the same way
    (0 STABS, 0 paths; exports stay). Objective-C sources keep their
    debug map: Makeconf's OBJCFLAGS has -g, as on linux. rzig-test passes
    with both zigs; rzig cross-builds for aarch64-macos and x86_64-macos.
    Tested on linux by cross-links; omicron run pending.
20. **windows-11-arm: CRAN has no aarch64 Windows binaries** (run
    43487408414, hermetic): hermetic-check.sh installs CRAN's
    win.binary jsonlite, an x86_64 DLL: "LoadLibrary failure: %1 is not
    a valid Win32 application". R-admin: "At present binary packages
    are not distributed for aarch64 Windows". The step is skipped when
    `R.version$arch` is aarch64 on Windows. stress.R `--conda` had no
    subdir for windows aarch64 (now win-arm64), and stress.yaml's runner
    list names windows-11-arm.
21. **`R CMD config` on a Windows host** (kappa, 2026-11-13): rzig-test
    failed one config test, and config-parity.sh 6 of 310 cases. rzig
    wrote CURDIR with backslashes when its target was unix but its host
    Windows (a backslash is an escape in sh's words); it now writes
    forward slashes on any Windows host, as GNU make does. R's script
    runs under MSYS's sh and make, which see paths from the environment
    in MSYS's spelling (`/tmp/...`, SHELL=/usr/bin/bash), while rzig
    prints the native ones R gives it (`C:\...`): a deliberate
    difference, recorded in feat-config-rzig PLAN.md; config-parity.sh
    maps the scratch directory's spellings to one token on Windows and
    leaves the two `$$SHELL` cases out there. kappa: 309 cases equal.
22. **`.Platform$pkgType` on Windows is "source"** (kappa, 2026-11-13,
    decided 2026-11-14): R's Makefile.win compiles platform.c with
    `-DPLATFORM_PKGTYPE='"win.binary"'`; build.zig does not, so this R
    reports "source" (getOption("pkgType") "source") where CRAN's
    reports "win.binary" ("both"). install.packages() then builds from
    source on Windows, as on linux and macOS; CRAN's Windows binaries
    still install with `type = "win.binary"` and load on win-64
    (hermetic's jsonlite). `R_PLATFORM_PKGTYPE` (R 4.6) overrides it.
    **Decision (user, 2026-11-14): keep "source"** on every OS, so
    every package is built with our toolchain. Later, as an experiment
    only: make binaries the Windows default (win-64 only, because CRAN
    has none for aarch64). The route is `-DPLATFORM_PKGTYPE='"win.binary"'`
    for platform.c in build.zig, or `R_PLATFORM_PKGTYPE=win.binary` in
    etc/Renviron.site. To test it: install CRAN's win.binary packages
    that have DLLs (jsonlite, data.table, Rcpp users) next to packages
    built from source, then load them in one session. Check the
    Rcpp/C++ ABI, OpenMP (CRAN's builds use the Rtools libgomp, not our
    libomp), and `R_compiled_by()` mismatch warnings.
23. **Windows recommended packages: `libintl.h` not found; Windows
    follows the unix variants** (kappa, 2026-11-14). `pixi run
    recommended` failed for Matrix, nlme, cluster, foreign and rpart
    ("fatal error: 'libintl.h' file not found"; boot, survival and mgcv
    followed). The cause: build.zig always built Windows as full
    (ENABLE_NLS in Rconfig.h), while R_HOME/include had no libintl.h.
    R's own Windows build installs one (src/extra/intl/Makefile.win:8-10).
    The unix slim and minimal configs have NLS off. **Decision (user,
    2026-11-14): Windows follows the unix variants** ("good opportunity
    to match configs across variants and remove OS specific
    workarounds"). One variant table holds for every OS; slim, full and
    minimal exist on Windows; Windows full installs R's libintl.h.
    The user's choices, same day:
    - Bitmap formats that are off: a patch to R's winbitmap.c with
      `#else` stubs, so jpeg()/tiff() (and png() on minimal) fail
      cleanly (devWindows.c and cairoBM.c call the save functions
      without guards; upstream never turns the formats off).
    - OpenMP inside R itself: on Windows as on unix (slim and full on,
      minimal off). Upstream leaves it off on Windows only because
      MinGW's libgomp was "too slow to be usable"
      (gnuwin32/fixed/h/config.h:609-613, main/Makefile.win:58). R's
      own code has parallel regions in colSums() (array.c) and dist()
      (stats); smoke-test.sh and test-win.R run both.
    - Release 11 ships the slimmer Windows r-zig-slim (no tcltk,
      jpeg(), tiff() or translations, as on unix).
    - CI: Windows full and minimal on both Windows runners in the
      label-gated full tier; Windows full also runs verify-tree and
      hermetic.
    - Also: one shared Makeconf.win template; three vendored win-*
      config dirs, checked against the table by build.zig; conda's
      gettext dropped on Windows; only libintl.h added to R_HOME/include;
      R_MEMORY_PROFILING left as upstream has it; `-Dblas=openblas` on
      Windows and splitting pixi.toml's [dependencies] left for later.
    Implemented 2026-11-14. linux-64: slim, full and minimal give the
    same trees as before. kappa (final run 2026-11-15): all three
    variants pass build, smoke, verify-tree, hermetic and contract;
    recommended and verify-recommended pass for slim and full. CI: see
    finding 24. The record, with the full variant table and the tests:
    .github/devdocs/feat-win-variants/PLAN.md.

24. **CI on #48 (run 43718810854, 2026-11-15): the contract on every
    Windows leg** (default, full and minimal, windows-latest and
    windows-11-arm; upstream-zig's windows-latest too): config-parity.sh
    found 9 of 309 cases different. Every step before it passed (build,
    smoke, verify-tree). Two causes, neither seen on kappa: GitHub's
    runners set `JAVA_HOME` to a path with backslashes, which MSYS's make
    prints as it is and rzig printed as sh would; and R's MSYS spelled the
    scratch directory `/c/Users/...`. Fixed in rzig's shellwords.zig (MSYS
    make's backslash rule, R CMD config only) and config-parity.sh
    (feat-config-rzig PLAN.md). macos-15-intel minimal failed only in its
    artifact upload ("Failed to CreateArtifact: Unable to make request:
    ENOTFOUND") after every test passed: a network fault. Every other
    leg passed, conda-package on all six platforms included.
    Rerun on 70c240c (runs 43736855864, 43736855916): 2 of 309 left on
    every Windows leg, both make's `$(CURDIR)`/`$$CURDIR`. GitHub's
    runners have `TEMP=C:\Users\RUNNER~1\...` (an 8.3 short name); the
    scratch directory kept that spelling, while make's CURDIR (the
    process's directory) comes back in the long form (`runneradmin`), so
    the mapping missed it. kappa's user name `admin` has no short form.
    Reproduced on kappa with an 8.3 TMPDIR; config-parity.sh now takes
    the long form (`cygpath -m -l`). Build, smoke (OpenMP regions OK on
    all six Windows variants) and conda-package on all six platforms
    passed.

25. **Stress run 43773932212 (0e4f145, 2026-11-15): no conda leg could
    make its env.** conda-package passed on every platform, then
    stress.R's env (r-zig-slim, r-zig-toolchain and the sysdeps, from
    dist/conda, universe, conda-forge) did not solve. Cause: the
    recipe's host libraries had no versions and rattler-build got no
    variant config, so each took the newest build on conda-forge.
    pcre2 10.49 (a conda-forge migration, open; the global pin is
    10.47) gave r-zig-slim `pcre2 >=10.49,<10.50.0a0`; every
    libgdal-core needs `pcre2 >=10.47,<10.48.0a0` or older. Linux,
    macOS and win-64: that conflict. windows-11-arm: `glpk` has no
    win-arm64 build (stress.R's sysdeps, not the recipe; below).
    Host versions in the CI build (all six platforms the same unless
    noted) against conda-forge-pinning 2026.11.15.14.44.40 and the dev
    lock: pcre2 10.49 (pin 10.47, lock 10.47); libcurl 8.23.0 (pin 8,
    lock 8.22.0); expat 2.9.0 (pin 2, lock 2.8.5); glib 2.90.1 (pin 2,
    lock 2.90.0); harfbuzz 15.0.0, osx-64 14.4.0 (no pin, lock 14.2.1);
    pango 1.58.2, osx-64 1.56.4 (pin 1, lock 1.56.4); libdeflate 1.25
    (the recipe's `<1.26`; pin 1.26, lock 1.25); icu 78.3 (pin 78, lock
    78.3); the others equal. Only pcre2 is past conda-forge's pin. zig
    in the build env: conda-forge's 0.17.1, the lock 0.17.0 (not a host
    library; the recipe's `zig 0.17.*`).
    Fix: recipe/variants.yaml, which rattler-build reads next to the
    recipe with no flag, holds conda-forge's global pins for every
    unversioned host library of r-zig-build (bzip2, cairo, expat,
    fontconfig, freetype, glib, icu, libcurl, libdeflate, libiconv,
    liblzma_devel, libpng, pango, pcre2, pixman, xz, zlib, zstd), as a
    feedstock's .ci_support file does. The recipe's inline `icu 78.*`
    and `libdeflate <1.26` go: the variant gives `icu 78.*` and
    `libdeflate 1.26.*` (conda-forge's libgdal-core 3.12.4 and 3.13.3
    now need libdeflate 1.26). conda-forge's conda_build_config.yaml
    itself (conda-forge-pinning, as a locked pkg dependency, with -m)
    was tried first: rattler-build 0.76.1 stops with "Zip key elements
    do not all have same length: fortran_compiler_version" (its
    os.environ selectors are conda-smithy's). One value is not
    conda-forge's: glib 2.90.0 on macOS. conda-forge's macOS glib
    2.90.1 builds need libintl 1.0, its graphviz and gtk3 (pulled by
    imagemagick) libintl 0.25, so with 2.90.1 in the host
    (`libglib >=2.90.1`) osx-arm64's stress env did not solve either.
    Back to '2' when graphviz moves to libintl 1.0. Same build number
    (11, unpublished); the build strings change (linux-64 r-zig-slim
    h81b34b9_11 -> h3e03716_11). pixi.lock unchanged.
    Tests (gamma, wt/fix-pin, rattler-build 0.76.1): render-only for
    linux-64, osx-arm64 and win-64 applies all keys (liblzma-devel
    matches liblzma_devel; pixman on Windows only; glib 2.90.0 on
    macOS). A no-op probe recipe with r-zig-build's host section and
    the same variants.yaml, built for all six platforms (macOS: host
    solve and run exports only; linking its host needs codesign), gives
    `pcre2 >=10.47,<10.48.0a0`, `libdeflate >=1.26,<1.27.0a0`,
    `icu >=78.3,<79.0a0` everywhere and `libglib >=2.90.0` on macOS. A
    pixi workspace per platform as stress.R writes it (r-zig-slim's run
    deps plus those exports, the groups' run deps, pkg-config and the
    sysdeps of the CI error), `pixi lock`: solves on linux-64,
    linux-aarch64, osx-64, osx-arm64 and win-64; the same with the CI
    build's exports (pcre2 10.49, libdeflate 1.25) fails on all six.
    win-arm64 solves only without glpk gmp harfbuzz hdf5 imagemagick
    libgdal-core libnetcdf libpq mpfr nlopt udunits2 (missing or
    unsolvable on conda-forge win-arm64): stress.R's win-arm64 sysdeps
    need their own fix. No full conda-package build was run.

26. **Stress run 43773932212 (2026-11-15): the windows-11-arm legs
    ran an emulated win-64 stress env.** pixi.toml's `[feature.stress]`
    listed five platforms (no win-arm64: conda-forge has no libgdal-core
    and others there, 2026-11-10). On the windows-11-arm runner
    `pixi install -e stress` printed "WARN win-arm64 is not supported by
    the current environment, falling back to win-64 (emulation)" and
    `pixi list -e stress` "Installed for: win-64 (emulated on
    win-arm64)", with zig_impl_win-64 0.17.0. The tree leg's stress.R
    ran on the arm64 tree (`windows aarch64`) with that env first on
    PATH and as R_ZIG_EXTRA_ENV; rzig gives zig no `-target` on Windows,
    so the x64 zig compiled for x64: every link against R.dll failed
    ("lld-link: error: R.dll: machine type arm64 conflicts with x64",
    10 targets, 30 dependencies), and RcppParallel's bundled TBB took
    the x86 path ("'_tpause' requires target feature 'waitpkg'"). The
    conda leg's stress.R put every installed row's sysdeps into the
    conda env for win-arm64 and pixi stopped: "No candidates were found
    for glpk". conda-forge win-arm64 repodata (2026-11-15) has no
    libgdal-core, udunits2, imagemagick, harfbuzz, hdf5, libnetcdf, gsl,
    mpfr, gmp, libpq, glpk, nlopt or tbb-devel; libboost-headers is
    noarch. build-r.yaml's windows-11-arm legs pass because default,
    full and minimal list win-arm64 (native zig_impl_win-arm64). No
    other env run on windows-11-arm lacks win-arm64 (wheel: not run on
    Windows). Fixed: the stress feature has all six platforms, the
    libraries above in unix's and win-64's target tables; stress.R
    stops when the libraries env's conda-meta subdir is not R's
    platform, and `--conda` leaves out the sysdeps the stress env lacks
    on the platform (the report lists them as missing from the env).
    Lock: additions only (stress win-arm64: 99 lines in the env, 20 new
    package records; its zig was 0.17.1, the R envs' 0.17.0, as it is
    in no solve group; the relock of finding 27 gives 0.17.1 to all).
    Review (2026-11-15): `--conda` leaves sysdeps out only when the
    libraries env is the stress env (`basename(R_ZIG_EXTRA_ENV)` is
    `stress`); with any other env it keeps them all, since that env
    does not say what conda-forge has for the platform.
    Option C (rzig passes an explicit `-target` on Windows, as on linux
    and macOS): done in build 11, on every tool path and every OS;
    finding 29.

27. **Lock bump (user request "bump all package versions in the
    lockfiles", 2026-11-15).** Tree: T/wt/rel11-fix (detached at
    0e4f145, with findings 25 and 26 as working-tree changes). `pixi
    update` (all environments, all six platforms), then the pins below
    and `pixi lock`. Lock sha256 93407b87795c -> dadd317726cf. Full list
    (env, platform, package, old, new): T/rel11-fix/lock-diff.txt (1662
    rows; summary T/rel11-fix/lock-summary.txt).
    Versions (all platforms unless named):

    | Package | Old -> new |
    | --- | --- |
    | zig, zig_impl_*, zig_* | 0.17.0 -> 0.17.1 (conda-forge, 2026-11-12) |
    | libdeflate | 1.25 -> 1.26 (conda-forge's pin; finding 25) |
    | libcurl, curl | 8.22.0 -> 8.23.0 |
    | expat, libexpat | 2.8.5 -> 2.9.0 |
    | glib, libglib | 2.90.0 -> 2.90.1 on linux and Windows; macOS 2.90.0 (pin) |
    | python (glib's, pkg's) | 3.14.8 -> 3.15.2 |
    | rattler-build (pkg) | 0.76.1 -> 0.80.1 |
    | cmake (stress) | 4.4.4 -> 4.5.0 |
    | libabseil (stress) | 20260526.0 -> 20260817.0 |
    | m2-* (Windows) | MSYS2 2026-10 set: m2-bash 5.3.20, m2-msys2-runtime 3.6.11, m2-make 4.4.1.3, ... |
    | others | bash 5.3, gzip 1.15, strace 7.3, patchelf 0.19.3, tzdata 2026e, libsqlite 3.54.1, xorg-libx11 1.8.14, ... |

    Unchanged: pcre2 10.47 and icu 78.3 (pins), pango 1.56.4 and
    harfbuzz 14.2.1 on unix (pins; lifted later the same day, the
    open item below), flang-zig 23.1.5 _0, flang-rt-zig
    23.1.5 _1, lld-zig and the zig_* llvm-openmp 23.1.5 _1 (pins),
    cairo 1.18.6, tk 8.6. The stress env's win-arm64 (finding 26) is
    new. The wheel env lost libcxx, libstdcxx and readline (python
    3.15's closure).
    Pins added (pixi.toml, where R's host libraries are; each says
    "mirrors recipe/variants.yaml (conda-forge's global pin)"): `pcre2
    = "10.47.*"` in [dependencies] and in [feature.minimal.dependencies]
    (pixi update took 10.49 on linux and Windows); `glib = "2.90.0.*"`
    in a new [target.osx.dependencies] (pixi update took 2.90.1 on
    osx-64). With them every variants.yaml key resolves within its pin
    in default, full, openblas, full-openblas, minimal and pkg on all
    six platforms (`pixi list --locked -e <env> --platform <p>`,
    T/rel11-fix/pincheck-2.txt). Pins kept: pango 1.56.* and harfbuzz
    14.2.* (R 4.6.2's cairo device; lifted after the retest, below),
    flang-zig/flang-rt-zig build numbers, llvm-openmp zig_*_1, tk 8.6.*,
    zig 0.17.*, rattler-build >=0.76. Pin lifted: the stress env's
    osx-arm64 `libheif <1.23.4`: libheif 1.23.7 gpl_h0a5996c_103 links
    @rpath/libsharpyuv.0.dylib (no /opt/homebrew path). The stress env
    still resolves libheif 1.23.3 there, and libgdal-core 3.13.2 with
    libdeflate 1.25 on unix (until the pango lift below: 1.23.7, 3.13.3
    and 1.26 since): the pango and harfbuzz pins of the default
    feature hold imagemagick to builds that need openexr 3.4 and so
    libdeflate 1.25 (a probe with `libgdal-core >=3.13.3` does not
    solve). Its win-64 has libdeflate 1.26 and libgdal-core 3.13.3. The
    R envs and the conda packages are not affected.
    Lock-like files: R's build.zig.zon keeps cairo 1.18.6 (the newest
    release). zigbuild/toolchain/build.zig.zon: pkgconf 3.0.10 -> 3.0.11
    (security fixes GHSA-qcp5-98c5-hvh7 and GHSA-fr7f-m8jv-4qcm; the
    same meson.build source list), cmake 4.4.4 -> 4.5.0 (Kitware,
    2026-11-12; share/cmake-4.5). The hashes came from `zig fetch` with
    an empty scratch ZIG_GLOBAL_CACHE_DIR (feat-zig-017/
    ZIG-FETCH-CACHE.md; its repro still fails with zig 0.17.1). The
    sha256 values in cmake.zig are Kitware's cmake-4.5.0-SHA-256.txt;
    pkgconf.zig and recipe/recipe.yaml's pkgconf source take
    d0cd841b...2dc4. README and comments that name zig 0.17.0, pkgconf
    3.0.10 or cmake 4.4.4 are updated (history notes keep the old value
    with the date of the change).
    Tests (gamma, linux-64, T/rel11-fix/*.log; lock dadd317726cf):
    `pixi install --frozen`: ok. `pixi run --frozen toolchain-test`: ok
    (cmake.zig and pkgconf.zig pin tests). T/rel11-fix/chain.sh:
    build, smoke, verify-tree, toolchain (cmake/ is cmake 4.5.0;
    `cmake --version` runs), verify-toolchain, contract, check,
    hermetic, `-e pkg conda-package` (rattler-build 0.80.1; the variant
    table lists icu 78, libdeflate 1.26, pcre2 10.47; the same 67
    overlinking warnings as rattler-build 0.76.1 had) and `-e pkg
    conda-consume`: all ok. r-zig-slim-4.6.2-h3e03716_11's index.json
    depends: `pcre2 >=10.47,<10.48.0a0`, `libdeflate >=1.26,<1.27.0a0`,
    `icu >=78.3,<79.0a0`. Stress-like solves (T/rel11-fix/stress-solve,
    `pixi lock`, channels universe then conda-forge): linux-64 with
    dist/conda first and r-zig-slim, r-zig-toolchain, pkg-config and
    the 30 sysdeps of the CI error: solves (r-zig-slim h3e03716_11,
    libgdal-core 3.13.3, pcre2 10.47, libdeflate 1.26). The other five
    platforms with r-zig-slim's run deps as plain deps (the probes of
    finding 25; the linux-64 probe equals the built package's 18
    versioned run deps): linux-aarch64, osx-64, osx-arm64 (libglib
    >=2.90.0) and win-64 solve; win-arm64 solves without the libraries
    conda-forge lacks there (finding 26). `pixi lock --check`: ok.
    Open item done (2026-11-15, with finding 29): R's cairo device
    with pango 1.58 and harfbuzz 15 in the dev env. pixi.toml's
    `pango = "1.56.*"` and `harfbuzz = "14.2.*"` became "*", then `pixi
    update pango harfbuzz libharfbuzz` (pango 1.56.4 -> 1.58.2 with the
    new libpango and libpango-devel, harfbuzz 14.2.1 -> 15.0.0, osx-64
    14.6.0; unix R envs and stress), then `pixi update -e stress`
    (unix: libdeflate 1.25 -> 1.26, libgdal-core 3.13.2 -> 3.13.3,
    imagemagick 7.1.2_27 -> 7.1.2_31, openexr 3.4.15 -> 3.5.4, proj 9.9.0,
    geos 3.15.0, giflib 6.1.3, libjxl 0.13.0, ...; osx-arm64 libheif
    1.23.3 -> 1.23.7). Lock dadd317726cf -> 55d166564bd6; Windows
    unchanged; list: T/rel11-fix/lock-diff-29.txt. `pixi run build`
    (linux-64) compiled R against pango 1.58.2, and smoke's "cairo
    devices OK"; png(type = "cairo") with text and umlauts, svg() and
    cairo_pdf() wrote their files, grSoftVersion() pango "1.58.2" (the
    PNG checked by eye). The stress osx-arm64 libheif spec is now
    `!=1.23.4,!=1.23.5,!=1.23.6` (pixi accepts it; `pixi lock --check`
    was ok before the relock, which then took 1.23.7).
    Not built yet with the lifted pins: macOS. osx-64 resolves harfbuzz
    14.6.0 and pango 1.58.2 _1 (no libpango split), osx-arm64 harfbuzz
    15.0.0 and pango _3; the pin of 2026-09-19 came from pango 1.58 with
    libharfbuzz 14.3 (hb.h include churn). The CI full tier's
    macos-15-intel and macos-latest rows (build, smoke, conda-package)
    decide; if osx-64 fails, pin pango/harfbuzz for osx-64 alone
    ([target.osx-64.dependencies]). Windows is unchanged (no pango).

28. **Stress run 43773932212 (0e4f145, 2026-11-15): the tree's cmake
    does not search the libraries env (Rhdf5lib).** Tree legs:
    linux-64 and linux-aarch64 "Could NOT find ZLIB (missing:
    ZLIB_LIBRARY) (found version "1.3.1")", then "Can not find target
    ZLIB::ZLIB" (CMakeFilters.cmake:134); win-64 "Could NOT find
    OpenSSL (missing: OPENSSL_CRYPTO_LIBRARY OPENSSL_INCLUDE_DIR)";
    osx-arm64 ok. Stress 38569895172 (2026-10-14) was ok on all three.
    Cause: build 11 puts the extras group's Kitware CMake 4.4.4
    (R_HOME/bin/toolchain/cmake/bin) first on PATH under R CMD. CMake
    searches a conda env's lib/ and include/ for find_library and
    find_path only when the env is one of its prefixes. Conda's cmake
    (<env>/bin/cmake, <env>/Library/bin/cmake.exe) adds its own install
    prefix, the env, to CMAKE_SYSTEM_PREFIX_PATH (UnixPaths.cmake,
    WindowsPaths.cmake). The tree's cmake adds its own directory
    instead, so the env is not searched at all. PATH's <env>/bin
    reaches only find_package's config files and the find modules with
    a pkg-config hint: FindCURL everywhere, FindOpenSSL on unix only
    (`if (UNIX)` in FindOpenSSL.cmake). FindZLIB has no pkg-config: on
    linux it failed, and FindOpenSSL failed on Windows. The "1.3.1"
    header is the runner's /usr/include/zlib.h (Ubuntu's zlib1g-dev),
    found through /usr; its libz.so is in /usr/lib/x86_64-linux-gnu,
    which CMake does not search (CMAKE_LIBRARY_ARCHITECTURE is empty
    with zig cc). The 2026-10-14 log shows a second, older defect:
    conda's cmake appends the env after /usr, so HDF5 took the
    runner's zlib.h ("found version "1.3"") with the env's libz.so.
    macOS was ok: FindOpenSSL used pkg-config and FindZLIB took the
    SDK's libz.tbd (Darwin.cmake puts the SDK's usr first).
    Who else: a standalone tree (base + extras) compiling against a
    conda or pixi env through R_ZIG_EXTRA_ENV, the same as the CI tree
    legs. Not the conda channel: r-zig-extras depends on conda-forge's
    cmake, in the env's bin, and R_HOME/bin/toolchain/cmake does not
    exist there; but conda users on Linux with a host zlib1g-dev or
    libssl-dev get the host's headers before the env's (the older
    defect above).
    Fix (build.zig only): etc/r-zig.cmake, until now macOS only, ships
    on every OS (cmakeToolchain; Windows: installed beside
    etc/Rcmd_environ). It appends to CMAKE_SYSTEM_PREFIX_PATH, before
    the platform files do, the environments rzig compiles against
    (zigbuild/tools/rzig/environment.zig), in rzig's order: R's own,
    the directory three levels above the file (<dir>/lib/R/etc; on
    Windows <env>/Library), then R_ZIG_EXTRA_ENV (on Windows its
    /Library). macOS keeps its CMAKE_SYSTEM_IGNORE_PREFIX_PATH line.
    etc/Renviron (unix) and etc/Rcmd_environ (Windows, in double
    quotes as the RC line) make it CMAKE_TOOLCHAIN_FILE's default,
    `${CMAKE_TOOLCHAIN_FILE-${R_ZIG_CMAKE_TOOLCHAIN_FILE}}`: a value set
    in the environment (empty: none) and a package's
    -DCMAKE_TOOLCHAIN_FILE still win. The env then comes before /usr
    for conda's cmake too, which removes the older defect. CMake reads
    a toolchain file more than once, so each prefix shows twice in
    CMAKE_SYSTEM_PREFIX_PATH; that only repeats a search. Not done:
    CMAKE_PREFIX_PATH in the environment (a user's own value would
    replace it, and Windows needs <root>/Library, which an Renviron
    default cannot add only when R_ZIG_EXTRA_ENV is set). stress.R
    needs no change in code: `--conda` already unsets a
    CMAKE_TOOLCHAIN_FILE under this R's R_HOME on every OS. Its comment
    at the `mine` variables and stress/README.md ("A tree from build 7
    on ships its own") said macOS; both now say every OS.
    scripts/verify-tree.sh checks the file on every OS: unix, the
    R_ZIG_EXTRA_ENV line in etc/r-zig.cmake (macOS also the ignore
    line) and the two etc/Renviron lines; Windows, the two
    etc/Rcmd_environ lines and the `/Library` line in etc/r-zig.cmake.
    Tests (gamma, 2026-11-15). Tiny project
    (cmk/tiny/CMakeLists.txt: project(t C), find_package ZLIB, OpenSSL,
    CURL), CC = the rel11-int compile tree's zig-cc, under `env -i`:
    - Tree cmake 4.4.4, PATH = cmake/bin, pkg env bin, /usr/bin, /bin:
      ZLIB not found (missing ZLIB_LIBRARY ZLIB_INCLUDE_DIR), OpenSSL
      and CURL found (pkg-config). The linux CI failure.
    - Same without the env's bin on PATH (no pkg-config, as FindOpenSSL
      on Windows): ZLIB, OpenSSL and CURL not found. The win-64 CI
      failure.
    - conda-forge cmake 4.4.4 (`pixi exec --spec cmake=4.4.4 --spec
      zlib --spec openssl`): CMAKE_SYSTEM_PREFIX_PATH =
      /usr/local;/usr;/;<env>;...; ZLIB and OpenSSL found in the env.
    - Tree cmake with the generated linux r-zig.cmake as
      CMAKE_TOOLCHAIN_FILE and R_ZIG_EXTRA_ENV = the pkg env, with and
      without the env's bin on PATH: ZLIB 1.3.2, OpenSSL 3.6.5 and CURL
      found in the pkg env. Own env only (file in <dir>/lib/R/etc,
      <dir> holding the env's include and lib, no R_ZIG_EXTRA_ENV):
      found in <dir>. The Windows file, run on linux with
      R_ZIG_EXTRA_ENV = a root whose Library/ links the env: found in
      <root>/Library. The macOS file on linux: same as linux.
      CMAKE_TOOLCHAIN_FILE empty: not found (the opt-out works).
    Rhdf5lib 2.0.0 (Bioconductor 3.23, biocmake 1.4.0), the rel11-int
    compile tree's Rscript, cmk/rhdf5/run.sh: R_ZIG_EXTRA_ENV and
    CONDA_PREFIX = rel11-int's pkg env, PATH = the pkg env's bin, the
    default env's bin (zig), /usr/bin, /bin. Without the file: "Could
    NOT find ZLIB (missing: ZLIB_LIBRARY ZLIB_INCLUDE_DIR)",
    configuration failed. With it: Found OpenSSL, CURL and ZLIB 1.3.2
    in the pkg env, DONE (Rhdf5lib), getHdf5Version() "1.14.6", 1.3 min
    at MAKEFLAGS=-j8. The patch applies to 0e4f145 (`git apply
    --check` in wt/rel11-fix: ok; applied to a copy, the result is
    byte-identical to the edited build.zig); `zig ast-check build.zig`
    (zig 0.17.0): ok; cmakeToolchain compiled alone (zig 0.17.0)
    wrote the three files used above. Not run: a zig build of the
    tree with the patch, Windows and macOS. packages.tsv: no change.
    Rhdf5lib's row (linux=ok macos=ok windows=fail-package) is right
    again with the fix; on win-64 the next stop is expected to be P4
    (FLT16_MAX, the package cause) as in round 2. The next stress run
    confirms it.
    Folded into T/wt/rel11-fix (2026-11-15; lock unchanged,
    dadd317726cf; logs in T/rel11-fix/). Tests on gamma, linux-64:
    - `sh T/rel11-fix/chain.sh T/wt/rel11-fix T/rel11-fix/04-chain-cmake.log`
      (each task `pixi run --frozen`): build, smoke, verify-tree ("CMake's
      toolchain file verified"), toolchain, verify-toolchain, contract,
      check, hermetic, `-e pkg conda-package` and `-e pkg
      conda-consume`: all ok. r-zig-slim-4.6.2-h3e03716_11 holds
      lib/R/etc/r-zig.cmake with the env lines and the two Renviron
      lines.
    - `pixi run --frozen -e stress stress
      --out=T/rel11-fix/stress-rhdf5 Rhdf5lib`: Rhdf5lib ok, 1.08 min,
      with the tree's cmake (R_HOME/bin/toolchain/cmake/bin); CURL
      8.23.0, OpenSSL 3.6.5 and ZLIB 1.3.2 found in .pixi/envs/stress;
      smoke "1.14.6".
    - Control, the same with `CMAKE_TOOLCHAIN_FILE=` (no file;
      T/rel11-fix/stress-rhdf5-nofile): install-failed, "Could NOT find
      ZLIB (missing: ZLIB_LIBRARY ZLIB_INCLUDE_DIR)", then
      CMakeFilters.cmake:134: the CI failure, reproduced.
    - CMake rows with the file (T/rel11-fix/stress-cmake-ctl): s2 ok
      (1.13 min), RcppParallel ok (0.44 min).
    - `pixi lock --check`: ok. Not run: Windows and macOS; the CI full
      tier and the stress dispatch cover them.

29. **Explicit target everywhere (user request after finding 26, 2026-11-15:
    "after the fail with wrong architecture / platform on the Windows on
    ARM run, make sure pass platform flags explicitly").** Before: rzig
    gave zig `-target` on linux (`<arch>-linux-gnu.2.17`) and macOS
    (`<arch>-native.13.0`) only; on Windows zig used its native target,
    the arch of the zig binary, so finding 26's x64 zig compiled for x64
    against an arm64 R. flang got no target on any OS (its default
    triple, the arch of the flang binary). rzig's `as` (Windows) ran
    `zig cc -c -x assembler` with no target, and `rzig build`'s tier-2
    plan said `native` on Windows.
    Changed (one rule, from rzig's own build target, which is R's:
    zigbuild/tools/rzig/target.zig, `Ctx.arch` defaulting to it):
    - zig cc/c++ (compiles and links, zig-fc's links too): `-target
      x86_64-windows-gnu` / `aarch64-windows-gnu` on Windows; linux and
      macOS unchanged (the same strings, now from target.zig).
    - flang (every zig-fc command: compiles, probes, split compiles):
      `--target=` flang-zig 23.1.5's own default triple for R's platform,
      before the caller's arguments (a caller's own --target wins):
      x86_64/aarch64-conda-linux-gnu, x86_64-apple-darwin13.4.0,
      arm64-apple-darwin20.0.0, x86_64/aarch64-w64-windows-gnu (from
      `flang --version` on linux-64 and the triple-named .cfg files and
      module directories of the other five platforms' flang-zig and
      flang-rt-zig packages). A flang of R's platform then compiles
      exactly as before, configuration file included: linux-64's object
      is byte-identical with and without the flag, and `-###` shows the
      same x86_64-conda-linux-gnu-flang.cfg. macOS keeps
      -mmacosx-version-min=13.0 after it (`-triple arm64-apple-macosx13.0.0`
      either way). linux-64's flang wrote aarch64 objects for
      aarch64-conda-linux-gnu and aarch64-w64-windows-gnu, so a foreign
      flang cross-compiles too.
    - rzig's `as`: `zig cc -target <R's> -c -x assembler`.
    - `rzig build` tier 2 (pkgplan.packageTarget): R's target on every OS
      (Windows was `native`: the zig's arch and zig's native ABI).
    - The CFG stub (cfguard.o) follows ctx.arch (the link's arch), not
      the binary's; the same value outside tests.
    - Already explicit, unchanged: dlltool `-m` and `zig rc /:target`
      (binutils.zig, rzig's machine); ar/ranlib take no target
      (llvm-ar's format: macOS's --format=darwin stays explicit).
      Machine.own there, and flang_rt.zig's module directory prefixes,
      follow rzig's build arch (builtin), which is Ctx.arch's default:
      one value outside tests; unit tests that set ctx.arch move only
      the zig and flang targets.
    CPU model: none changes. Windows already passed -mcpu=baseline
    (fix-rzig-baseline-cpu), which an explicit target keeps: `zig cc
    -target x86_64-windows-gnu -mcpu=baseline -###` gives target-cpu
    x86-64, aarch64 generic, as before. The explicit target fixes the
    Windows OS version range to zig's default instead of the host's;
    `_WIN32_WINNT` stays 0x0a00 (`-dM -E` of windows.h with the default,
    win10_fe and win11_ge ranges), as R's own build already uses
    (build.zig's non-native query). One change for assembly on
    win-arm64: rzig's `as` had no target and no -mcpu, so zig took the
    machine's CPU (a Snapdragon's +aes/+dotprod); now the target is
    named and the CPU is aarch64's generic, so a .s file with `aese` or
    `sdot` needs its own `.arch`/`.arch_extension` or a -mcpu passed
    through (zig 0.17.1: "instruction requires: aes"), as C with
    intrinsics already does through -mcpu=baseline. x86_64's assembler
    does not gate instructions on CPU features.
    Left implicit, on purpose (comments where they are): build.zig
    builds R for the native arch of the zig that runs it, which is the
    platform of the pixi env whose conda libraries R links; a -Dtarget
    of another arch could only fail at the link, so build.zig takes none.
    zigbuild/toolchain (pkgconf, the cmake archive) uses b.graph.host
    for the same reason. etc/r-zig.cmake sets no CMAKE_SYSTEM_NAME,
    CMAKE_SYSTEM_PROCESSOR or CMAKE_<LANG>_COMPILER_TARGET: the first two
    turn CMake's cross-compiling mode on, the third adds a second target
    to rzig's (build.zig, cmakeToolchain's comment). Makeconf's CC lines
    name rzig, which adds the target. Workflows: pixi 0.84.2 has
    `--platform` on `pixi install` and `pixi run`, but setup-pixi
    installs the envs; rather than a flag on every `pixi run` line, the
    guard below. recipe: rattler-build builds the native subdir per
    runner; unchanged.
    Guards: scripts/env.sh stops every task when the env's platform
    (`$CONDA_PREFIX/conda-meta/pixi`, resolved_platform.subdir) is not
    PLAT (the machine's; on Windows from PROCESSOR_IDENTIFIER): the
    win-64-on-ARM env of finding 26 stops there. Not on macOS (review,
    2026-11-15): an osx-64 env under Rosetta on an arm64 Mac (omicron)
    is a supported setup, all osx-64, and the shell's own arch says
    nothing there (the wheel env has no bash; /bin/bash runs as arm64).
    The subdir read is the one in the resolved_platform block. No
    conda-meta/pixi (rattler-build's env): no check. Tested on gamma
    with a copy of conda-meta/pixi saying linux-aarch64: the error;
    with the real one: passes. No guard in rzig or build.zig: a zig's
    own arch is not visible without running it, and with the target
    named it no longer matters. scripts/verify-tree.sh checks, on every
    OS, that the dry runs (RZIG_PRINT_ARGV) of the tree's C compile, C++
    link and (Windows) as.exe give `-target <R's>` once, and zig-fc's
    compile `--target=<flang triple>` first.
    Tests: rzig unit tests 211/211 (target.zig's triples for both arches
    and every OS; Windows argv for x86_64 and aarch64 through ctx.arch:
    compiles, DLL links with the CFG stub on x86_64 only, a caller's
    -target after R's; zig-fc on Windows for both arches, split compile
    and link; as.exe for both arches; the existing Windows tests now
    expect the target). parity-test.sh: the Windows target is taken
    out of rzig's side after checking it is there (the shims read
    uname -m, which MSYS gives as x86_64 on Windows on ARM, so they stay
    without one): 116 identical, 70 ok+, 33 deliberate, 0 failed. rzig
    compiled for aarch64-windows-gnu, x86_64-windows-gnu, aarch64-macos
    and aarch64-linux-gnu (`zig build -Dtarget=...` of rzig alone).
    Tests on gamma, linux-64 (lock 55d166564bd6, logs in
    T/rel11-fix/): `pixi run --frozen rzig-test` (unit tests and
    parity) 08-rzig-test.log, `toolchain-test` 09-toolchain-test.log:
    ok. `sh T/rel11-fix/chain.sh T/wt/rel11-fix T/rel11-fix/16-chain.log`:
    build, smoke, verify-tree ("R's target verified: zig -target
    x86_64-linux-gnu.2.17 (zig-cc zig-cxx), flang
    --target=x86_64-conda-linux-gnu (zig-fc)"), toolchain,
    verify-toolchain, contract, check, hermetic, `-e pkg conda-package`
    and `-e pkg conda-consume`: all ok. linux unchanged but for flang:
    the dry runs of an rzig built from 0e4f145 and of the new tree's
    differ on linux only in flang's `--target=x86_64-conda-linux-gnu`
    (and paths from where each rzig lives); macOS also only in flang's
    `--target=`; Windows in `-target x86_64-windows-gnu` on every zig
    command, as.exe included, and flang's `--target=`. `R CMD config
    CC` is still `<R_HOME>/bin/toolchain/zig-cc -std=gnu23` (rzig adds
    the target); a verbose R CMD SHLIB of a.c and b.f90
    (17-shlib-verbose.log) shows `zig cc ... -target
    x86_64-linux-gnu.2.17`, `flang --target=x86_64-conda-linux-gnu`,
    clang's `-triple x86_64-unknown-linux5.10.0-gnu` and target-cpu
    x86-64. Not run: macOS and Windows hosts (unit tests and dry runs
    with RZIG_OS only); the CI full tier and the stress dispatch cover
    them.
    Lock: changed for finding 27's open item (below), not for this.
    Not run on Windows yet: finding 28's etc/r-zig.cmake and its
    Rcmd_environ default (CMake's find_library may now take conda's
    MSVC import libraries from <env>/Library for MinGW links); read the
    Windows stress rows RcppParallel, s2, Rhdf5lib and nloptr against
    packages.tsv.

30. **Stress run 43773932212 (2026-11-15): arrow and arrow:source on
    macos-15-intel (`crc32c_sse42_avx512.c:65: always_inline function
    '_mm512_loadu_si512' requires target feature 'avx512f'`).** Two
    causes, both found:
    - zig reads `-march=`/`-mcpu=` as `<cpu>[+feat][-feat]`, so a CPU
      name in clang's spelling fails: `-march=skylake-avx512` is
      skylake minus a feature "avx512" ("unknown CPU feature"),
      `-march=x86-64-v3` "unknown CPU: 'x86'", `-mcpu=cortex-a76` and
      `-mcpu=apple-m1` likewise (zig 0.17.1). arrow's
      CXX_SUPPORTS_AVX512 probe (-march=skylake-avx512) failed so on
      every x86_64 OS. Fixed in rzig (compiler.zig, marchArgs and
      clangCpu): a -march/-mcpu value whose CPU name has a `-`, which
      zig does not know as given but knows with `_` for R's arch
      (std.Target.Cpu.Arch.parseCpuModel), is passed in zig's spelling
      (skylake_avx512, x86_64_v3, cortex_a76+crypto-crc); anything else
      is kept (zig's own `cpu-feature` syntax, native, another arch's
      CPU, a typo). -Xarch_ values stay clang's. Unit tests for both
      arches; through the rebuilt tree's zig-cc on gamma,
      `-march=skylake-avx512` and `-mcpu=x86-64-v4` compile AVX-512
      intrinsics (zmm in the object); `-march=bogus-cpu` still fails.
    - The aws-checksums file itself: aws-c-common's
      AWS_HAVE_AVX512_INTRINSICS probe (`__m512 a = _mm512_setzero_ps();`
      with the AVX-512 flags and -Werror) fails under arrow's -Wall
      ("unused variable 'a'", reproduced on omicron with the osx-64 tree
      of rel11b under Rosetta: rc 0 without -Wall, 1 with), so the
      bundled build leaves the AVX-512 flags off that file. Its
      `#if defined(AWS_HAVE_AVX512_INTRINSICS)` still came true: the
      stress env has conda-forge's aws-c-common 1.0.5 (hdf5 2.2.0 pulls
      aws-c-s3 and the rest, every platform), whose aws/common/config.h
      defines it, and rzig's `-I<env>/include` is searched before the
      `-isystem` directories CMake gives for the bundled aws-c-common
      (clang searches every -I before every -isystem). Not changed in
      rzig: `-isystem <env>/include` would follow CMake's order, but zig
      passes its own clang, libc (and on macOS the SDK's) directories
      as -isystem before the caller's, so the env would lose to them
      (the SDK's iconv.h over conda's libiconv, which R links); the
      env-first order is deliberate (envFlags' comment). Any package
      that bundles a library whose headers the env also has can meet
      this; linux passes only because its probe passes there. Next
      stress run: arrow and arrow:source on macos-15-intel are expected
      to fail the same way (the -march fix does not reach aws-checksums'
      probe); a later item, after the release: weigh `-isystem` for the
      env behind zig's own directories on linux (no SDK) against
      keeping -I.

31. **The C++ ABI on linux (2026-11-16): the six linux fail-abi stress
    rows (magick, sf, terra, gdalraster, protolite, V8).** zig c++ links
    its own libc++ (std::__1); conda-forge's linux C++ libraries are gcc
    builds over libstdc++ (std::__cxx11), so a package that calls their
    C++ API (Magick++, GDAL's OGR/GDAL classes, protobuf, a libstdc++
    libv8) fails to load on undefined std::__1 symbols. macOS is not
    affected (libc++ on both sides). Three probes and a judge, under T/:
    - abi-libstdcxx: zig c++ against conda's libstdc++ (the env's
      libstdcxx-devel headers in lib/gcc/x86_64-conda-linux-gnu/15.3.0,
      -nostdinc++ with -I and --system-header-prefix, two shim headers,
      link -nostdlib++ -l:libstdc++.so.6 -l:libgcc_s.so.1; zig ignores
      -stdlib=libstdc++, maps -lstdc++ to its libc++ and drops -lgcc_s;
      -isystem fails, zig's libc directories come first). All six
      install, load and pass their smokes. But Rcpp passes std::string
      across .so files (demangle() through R_GetCCallable): a libstdc++
      package with a libc++ Rcpp gives 'double free' on any C++
      exception, the reverse 'irrecoverable exception'. So the choice
      is for all C++ on linux, not per package. R already loads
      libstdc++.so.6 (GLIBCXX_3.4.36, the tree's lib/) through ICU;
      packages need GLIBCXX_3.4.32.
    - abi-condaforge-bin: conda-forge's prebuilt r-* packages beside
      r-zig. conda-forge has r-base 4.6.2 but no r46 package builds
      yet; the r45 binaries of the six load in r-zig's R 4.6.2 once
      rlang is rebuilt (r45 rlang needs SETLENGTH, gone in R 4.6), but
      mixing toolchains through Rcpp crashes (zig Rcpp with conda's
      terra: double free). Found a hazard: with r-zig-slim in an env,
      `pixi add r-magick` silently installs conda-forge's r-base over
      r-zig's R (no clobber warning; channel priority does not stop
      it).
    - abi-cxxrebuild: rebuild the C++ libraries with zig and libc++:
      Magick++ (19 files, seconds), GDAL 3.13.2 (about 5 min, 37 MB
      stripped, without xerces-c, libkml, muparser), abseil + protobuf
      (about 2 min), V8 from jeroen's libc++ bundle (its configure takes
      it only when $CXX contains "clang"). All six work (not tested: a
      C++ exception thrown inside libgdal and caught in a package), but
      each library is a rebuild r-zig would own, and GDAL loses drivers.
    - abi-judge: confirmed read-only in this tree that r-zig-slim had
      no r-base constraint and that rzig has no stdlib selection today;
      arrow's linux ok depends on arrow refusing its libstdc++ prebuilt
      under libc++ (it builds from source), which option 1 (below)
      changes.
    User decision (2026-11-16): release 11 keeps the six as linux
    fail-abi (their notes name this finding); recipe/recipe.yaml gives
    r-zig-slim the run constraint `r-base <0a0`, so that solve fails and
    names the conflict; stress/packages.tsv gets three Bioconductor rows
    (DESeq2 and scran in g1, Rsamtools with Rhtslib's bundled htslib in
    g4). Option 1, libstdc++ for all C++ on linux, goes on the next
    branch; rerun there the cpp11 rows RPostgres, systemfonts,
    textshaping and ragg too (textshaping's header passes std::vector
    across packages to ragg, so switching per package is unsafe).
    Stress on linux-64 (gamma, tree, zig 0.17.1, jobs 4, 14.9 min;
    T/bioc-rows/run): DESeq2 and scran ok. Rsamtools is skipped:
    Rhtslib's htslib Makefile links libhts.so from objects named .pico,
    and zig cc (both zigs) stops at them ("kfunc.pico: unrecognized
    file extension"); GNU ld reads them as objects. With .pico renamed
    .pic.o by hand, Rhtslib and Rsamtools install and pass the smoke.
    Fixed by finding 32; Rsamtools is now linux=ok. The r-base
    constraint was checked with a noarch probe package: with it, adding
    r-magick or r-base fails to solve and names r-base; without it,
    r-magick pulls conda-forge's r-base 4.5.3 (T/bioc-rows/constraint).
    The design and what was ruled out: .github/devdocs/CXX-STDLIB.md.

32. **rzig: object files with unknown extensions (2026-11-16).**
    Rhtslib's htslib links libhts.so from objects named kfunc.pico, ...;
    zig cc (both zigs) classifies link inputs by extension and stops
    ("kfunc.pico: unrecognized file extension"; `-Wl,kfunc.pico` fails
    too), where GNU ld reads the file. zigbuild/tools/rzig/archives.zig,
    which already passed archives without a known extension as cached
    <name>.a copies (Z6), now reads an input's first bytes and passes a
    relocatable object as <cache>/object-<key>/<name>.o: ELF ET_REL
    (either byte order), Mach-O MH_OBJECT (32/64 bit, either byte order,
    also in a universal file), COFF for x86, x64 or arm64 with no
    optional header, LLVM bitcode (bare or wrapped). Unchanged: names
    zig takes, source names, option values (-o, -include, ...),
    compile-only calls, shared libraries and executables under any name
    (a shared library without a SONAME is recorded by its path, which
    must not be the cache's). Not covered: `-Wl,x.pico`, COFF bigobj and
    arm64ec objects. macOS links libhts.dylib from .o files and is not
    affected. Tests (gamma, zig 0.17.1, conda-forge and upstream): rzig
    unit tests 213/213 each (two new), rzig-test parity 0 failed; stress
    on linux-64 (tree, jobs 4; T/obj-inputs/run, run-up): Rsamtools ok
    with both zigs (0.3 min, Rhtslib 0.15 min, smoke ok); its expect is
    linux=ok macos=ok windows=?.

33. **Stress run 43947228208 (bfb510a, 2026-11-16): arrow and
    arrow:source fail on every linux and macOS leg, tree and conda**
    (`CMake Error at .../_deps/boost-src/libs/locale/CMakeLists.txt:236
    (source_group)`). Not seen at 0e4f145 (run 43773932212, CMake
    4.4.4); finding 27's lock bump brought CMake 4.5.0, into the stress
    env and the extras group. CMake 4.5.0's `source_group(TREE)`
    compares path components (cmCMakePath::IsPrefix), and Boost 1.92.0's
    locale CMakeLists, which arrow 26.0.1 fetches, passes a TREE its
    files are not under by that test; Boost fixed it after 1.92.0
    (boostorg/locale#273). Reproduced on gamma with Boost 1.92.0's
    locale alone: 4.5.0 fails, 4.4.5 configures (T/triage/
    arrow-boost-cmake). Fixed by holding CMake at 4.4.5 until a Boost
    with the fix reaches arrow: the extras group's Kitware archives
    (zigbuild/toolchain/cmake.zig, build.zig.zon: version, data_dir
    share/cmake-4.4, the six archives; their sha256 checked against
    Kitware's cmake-4.4.5-SHA-256.txt, their zon hashes with `zig
    fetch`), r-zig-extras' run dep `cmake <4.5`, and the stress
    feature's `cmake = "<4.5"` (lock a2d8b95874eb: cmake 4.5.0 -> 4.4.5
    in the stress env on six platforms, nothing else). linux-64 on gamma
    (2026-11-17, this tree): build, toolchain, verify-toolchain (cmake
    4.4.5, share/cmake-4.4) pass; stress, tree, jobs 8 (T/triage/
    stress-l64): arrow ok (6.2 min) and arrow:source ok (8.3 min),
    through the tree's cmake 4.4.5.

34. **Stress run 43947228208: duckdb fails on both Windows tree legs**
    ("configuration failed for package 'duckdb'" after 0.06 min; ok at
    0e4f145 in 24.6 min). duckdb 2.0.0's configure.win runs `tar xf
    duckdb.tar`. The build-tools group has no tar, so the stress env's
    m2-tar answered, a second MSYS2 install, which finding 27's bump
    moved to msys2-runtime 3.6.11 (`_11` builds) while the group's sh is
    its own; that tar exits 127 with no output under the group's sh.
    The conda legs passed (System32's bsdtar answered there). Fix: the
    build-tools group carries m2-tar (zigbuild/toolchain/build.zig,
    the recipe's r-zig-build-tools run deps), as Rtools' usr/bin has
    it; verify-toolchain.sh and test-build-tools.R check it. The cause
    is inferred from the log and the PATH order, not reproduced on a
    Windows host; the targeted stress run checks it.

35. **windows-11-arm (runs 43879895297, 43947228208): textshaping
    (and ragg after it) stops in lld: "invalid symbol index in addrsig
    section"** in the r-windows clang-aarch64 freetype bundle. zig
    turns on lld's identical code folding for a `-s` link on Windows,
    and ICF reads .llvm_addrsig, which those objects have broken (an
    index past the symbol table). Rtools45-aarch64 and r-universe link
    their own freetype and never meet it. Not fixed for release 11:
    recorded (stress.R classes it toolchain; the rows'
    windows-aarch64= expects). After the release: ICF off on Windows
    links (`/OPT:NOICF`), which also removes the risk that ICF folds two
    functions whose addresses a package compares; or Rtools' static
    C libraries as a win-arm64 gap-filler (r-universe research,
    T/triage/runiverse).

36. **windows-11-arm: magick's link stops at "undefined symbol:
    __clear_cache"** (runs 43879895297, 43947228208; both zigs). The
    clang-aarch64 bundle's libffi calls it for its closures; LLVM's
    compiler-rt defines it on Windows with FlushInstructionCache
    (clear_cache.c, `_WIN32`), zig's compiler_rt/clear_cache.zig leaves
    that branch as a TODO (0.17.1). Fixed in rzig as the CFG
    stub: zigbuild/tools/rzig/clear_cache.c, compiler-rt's function,
    weak and excluded from MinGW auto-export, which R's build compiles
    for aarch64 Windows into R_HOME/bin/toolchain/clear_cache.o; rzig
    passes it on the links that get cfguard.o on x86_64
    (clear_cache.zig; compiler.zig). Weak: a link that defines the
    symbol itself keeps its own, with no duplicate (a strong copy
    stopped such a link). Tests (gamma, cross-built, zig 0.17.1
    conda-forge and upstream): a DLL calling `__builtin___clear_cache`
    links with the object and exports only its own symbol; a DLL with
    its own __clear_cache links; magick's static link against the
    bundle (Magick++, librsvg, libffi, ...; iconv stubbed) links with
    and without `-s`, 30.6 MB; rzig unit tests 213/213 with both zigs
    (the Windows tests take both arches), parity 0 failed. magick's
    windows-aarch64 expect is now windows=ok's; run time on
    windows-11-arm is checked by the targeted stress run. To report
    upstream to zig after the release.

    The record patch of the same triage (stress.R, packages.tsv):
    expect keys may name R's arch (`windows-aarch64=`, `macos-x86_64=`;
    the most specific key wins, then os=, then a bare default); the
    classifier's toolchain class takes `__clear_cache` and the addrsig
    error; win-arm64 rows whose libraries conda-forge lacks there
    (units, ncdf4, hdf5r, gsl, Rmpfr, igraph, nloptr, gdalraster,
    terra, sf, ...) say so with windows-aarch64= expects; Rhtslib and
    Rsamtools are windows=fail-dependency (htslib's regex.h, which
    MinGW-w64 and conda-forge lack); DESeq2 is windows=ok; arrow is
    windows-aarch64=fail-package (arrow 26.0.1 downloads an x64
    libarrow) and macos-x86_64=? (finding 30's aws-checksums cause,
    unseen behind finding 33).

## Tests

### The integration tree (2026-11-13)

T/wt/rel11-int, lock 59a4052f23ca (unchanged), conda-forge's zig 0.17.0,
default env (slim). The chain (T/rel11/int/chain.sh; chain-win.bat):
toolchain-test, rzig-test, recommended-test, build, smoke, verify-tree,
toolchain, verify-toolchain, contract (config-parity.sh first),
pkg-parity, check, hermetic, package, package-toolchain, verify-package,
recommended, verify-recommended, package-recommended, then `-e pkg`
conda-package and conda-consume.

- linux-64 (gamma): every step exit 0 (T/rel11/int/linux64.log). The
  macOS strip change (finding 19) landed during the run; it does not
  change linux links.
- osx-arm64 (omicron): first run every step to recommended exit 0;
  verify-recommended failed (finding 19). Rerun with the fix
  (2026-11-13/14): every step exit 0, through conda-package and
  conda-consume (`=== OK -e pkg conda-consume 16:51:01`).
- osx-64 (omicron, Rosetta): every step exit 0, through conda-package
  and conda-consume (`=== OK -e pkg conda-consume 16:42:35`). verify-tree passes there now
  (finding 17).
- win-64 (kappa): rzig-test and then contract failed (finding 21);
  after the fix every step passed through verify-package. recommended
  then failed (finding 23). After finding 23 (2026-11-14/15): slim, full
  and minimal each pass build, smoke, verify-tree, hermetic and
  contract; recommended and verify-recommended pass for slim and full
  (feat-win-variants/PLAN.md, "Tests"). conda-package and
  conda-consume on Windows: CI.
- win-arm64: CI only.

### Earlier runs (2026-11-12)

linux-64 (gamma), default env (slim), conda-forge's zig 0.17.0,
2026-11-12:

- Run 1 (R 4.6.2, flang 23.1.5, libomp build 0, before the visibility
  change): toolchain-test, rzig-test, build, smoke, verify-tree,
  toolchain, verify-toolchain, contract, pkg-parity, check (R's own
  suite), hermetic: all exit 0.
- Run 2 (plus visibility, CC_VER/FC_VER, the -S fix): rzig-test 189/189
  and parity "0 failed"; build; `R_compiled_by()` gives clang 22.1.8 and
  flang 23.1.5; smoke, verify-tree, toolchain, verify-toolchain and
  contract exit 0. pkg-parity, check, hermetic, package,
  package-toolchain and verify-package were still running when this was
  written: read rel11/linux64-chain2.log. (2026-11-12, night: the log
  has `=== OK` for pkg-parity, check, hermetic, package and
  package-toolchain; it ends inside verify-package, with no result.)
- Not yet run with the final lock (libomp build 1) on gamma: the env
  there still has build 0's files (the same code). Run
  `pixi install --frozen` and the chain again.
- full, minimal, openblas, wheel, conda-package and conda-consume: not
  run.
- macOS (omicron) and Windows (kappa): chains started on the baseline,
  results not read. See below.
- win-arm64: CI only. (2026-11-12, night: pushed; see the CI section
  below.)

### CI on the pull request (2026-11-12, night)

- Run 43341267916 (7b0e73c, the interim push): toolchain ✅ on all six,
  windows-11-arm included; conda-package ❌ all six (finding 16); the
  build jobs were cancelled by the next push.
- Run 43344258167 (8424d56, the sha256 fix): toolchain ✅ six;
  conda-package ✅ six; ubuntu-latest default/minimal/full/openblas ✅;
  ubuntu-24.04-arm default/minimal/full/openblas ✅; macos-latest
  default/minimal/full ✅; windows-latest default ✅; macos-15-intel
  full ✅ (verify-tree skipped there); macos-15-intel default and
  minimal ❌ (finding 17); windows-11-arm default ❌ at pkg-parity
  (finding 18). **windows-11-arm's contract passed**: data.table on 2
  threads, `grouped aggregation: OK`, minqa + OpenMP, quadprog, pak, ps
  and the no-make cases — the libomp fix works. Not reached on
  windows-11-arm: regression suite, hermetic, archives, wheel.
- Next push: T/rel11/handover/diag-avx-make.sh (findings 17, 18
  diagnostics only).
- Run 43437326154 (7697c75): the same two failures, now named (findings
  17 and 18).
- Run 43487408414 (51588ad, the fixes of findings 17 and 18): every job
  green, macos-15-intel default and minimal included, but
  windows-11-arm default, which passes pkg-parity and the regression
  suite and fails at hermetic (finding 20). upstream-zig run
  43487408234: every job green.

## State (2026-11-15; older lines from 2026-11-13)

All paths below are under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/ (T).

- 2026-11-16: T/wt/rel11-fix is feat-win-arm64 at 5dd40cf, which
  holds findings 25-30; findings 31 and 32 are working-tree changes.
- 2026-11-15: T/wt/rel11-fix (detached at 0e4f145, feat-win-arm64's
  tip) held findings 25-30 as working-tree changes, with the new
  recipe/variants.yaml and zigbuild/tools/rzig/target.zig untracked; lock 55d166564bd6 (dadd317726cf
  until finding 29's pango lift). Logs, lock diff
  and solve probes: T/rel11-fix/. The lines below are older.

- feat-win-arm64 (origin 51588ad) = T/wt/feat-win-arm64, clean.
- T/wt/rel11-int (branch rel11-int at 48d3650 + the 51588ad changes,
  uncommitted): everything below. T/rel11/int/STATE.md has the commit
  plan; T/rel11/int/make-patches.sh wrote T/rel11/int/patches/1..8.patch
  (2026-11-13), one per commit, which apply in order to 51588ad and
  gave the tree of 2026-11-13 byte for byte (checked in
  T/wt/patch-check).
- 2026-11-15: patches 1..8 do not hold the later work.
  T/rel11/int/make-patches-9-11.sh writes three more, split at the
  copy of the tree taken before finding 23 (T/rel11/var/base):
  9 = the verify-bundle.sh fix, 10 = the record edits of 2026-11-13/14,
  11 = finding 23. It then applies 1..11 to a copy of 51588ad and checks
  every tracked or untracked path against the tree. Do not rerun
  make-patches.sh: it copies the current tree into state 5 and would
  put the later edits into patch 5. Rerun make-patches-9-11.sh after
  any later edit to the tree. The commit messages and commands:
  T/rel11/handover/commit-p*.txt and apply-patches.sh.
- T/wt/rel11b-config, rel11b-recommended, rel11b-extras: the items'
  worktrees (from 7697c75; their scratch T/rel11/scratchb-*,
  scratchc-extras). Kept until the patches are committed.
- Hosts: omicron `~/.pixi/rz-rel11b/{arm64,x64}` (logs `arm64.log`,
  `arm64b.log`, `x64.log`); kappa `C:\Users\admin\rz-rel11b`, log
  `C:\Users\admin\rz-rel11b.log`, script `rz-rel11b-chain.bat`, task
  `schtasks /tn rz-rel11b`. Delete all after the release.

## To resume

0. (2026-11-15) T/wt/rel11-fix holds the later work (findings 25-30).
   The user commits it on feat-win-arm64 and pushes; then CI with the
   `full-ci` label (every row), then the stress dispatch (item 3), then
   item 4. Items 1 and 2 are done or decided.
1. Run T/rel11/int/make-patches-9-11.sh; it must end with "ok". The
   user commits patches 1..11 on feat-win-arm64
   (T/rel11/handover/apply-patches.sh), adds the `full-ci` label and
   pushes; read the
   CI run row by row (windows-11-arm hermetic, every leg's
   conda-package with the two new outputs, the extras archive on all
   six toolchain legs, the recommended packages in conda-package, the
   four new Windows full/minimal legs and test-win.R in Windows
   conda-package).
2. Decided 2026-11-14: finding 22 stays "source" (a later experiment
   is noted there); the `zig fetch` cache defect is not reported
   upstream, and feat-zig-017/ZIG-FETCH-CACHE.md tracks it per zig
   update. Still open: the extras group's Help/ pages and PATH order
   (feat-extras-group PLAN.md); the recommended packages in
   build-r.yaml's per-OS chain (feat-recommended-packages PLAN.md). The
   tree has the recommended options (no Help/, the tree's cmake first,
   recommended in conda-package only).
3. The stress run on the branch (all runners incl. windows-11-arm, tree
   and conda), read its table row by row (N6, K1, the arrow and
   RcppSimdJson rows for evex512, the CMake rows s2, Rhdf5lib,
   RcppParallel, arrow:source with the extras' cmake).
4. The publish preflight, then the one release of build 11 for six
   subdirs.

## State at the stop (2026-11-12, evening; superseded by "State" above)

All paths below are under
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/ (T).

- T/wt/feat-win-arm64: this tree, branch feat-win-arm64 (superseded
  2026-11-12 night: interim commits pushed as 42cba99..7b0e73c, the
  sha256 fix 8424d56; lock sha256 59a4052f23ca, finding 15).
- T/rel11/handover/interim-commands.sh with commit-1..5.txt: the commits
  and the push for this tree as it is (retargets #48 to main first).
  Not run at the stop (2026-11-12, night: run; pushed). Pushing starts CI on all six platforms, windows-11-arm
  included, which is the only test of Windows on ARM.
- T/rel11/baseline: a copy of this tree's sources as the agents got
  them (plus the build-1 pins). An agent's own changes are
  `diff -ru T/rel11/baseline T/wt/rel11-<item>` without .git, .pixi,
  build, dist, .zig-cache, zig-pkg.
- T/wt/rel11-config, T/wt/rel11-extras, T/wt/rel11-recommended (local
  branches rel11-*, at 28eaf9e): the three items' trees, unfinished and
  unreviewed. Each agent was told to write
  T/rel11/scratch-<item>/STATE.md and CHANGED-FILES.txt. Their briefs:
  T/rel11/brief-<item>.md; the shared rules: T/rel11/AGENT-RULES.md.
- Logs: T/rel11/linux64-chain1.log, linux64-chain2.log,
  configure-linux64-slim*.log, lock*.log, rzig-test2.log.
- omicron: `~/.pixi/rz-rel11/{arm64,x64}` and their logs
  `~/.pixi/rz-rel11/arm64.log`, `x64.log` (lines starting `===`); the
  chain script is `~/.pixi/rz-rel11/chain-mac.sh`. The first arm64 run
  (old lock) passed toolchain-test, rzig-test, build, smoke and
  verify-tree with R 4.6.2 before its curl was blocked. Delete the
  directory when done.
- kappa: `C:\Users\admin\rz-rel11`, log `C:\Users\admin\rz-rel11.log`,
  script `C:\Users\admin\rz-rel11-chain.bat`. Delete all three when
  done.
- Since the snapshot this tree gained only records, README lines, the
  recipe's build-number note and the build-1 pins. (2026-11-12, night:
  then the channel order, the recipe's sha256 fix and the CI
  diagnostics, findings 13-18.)

## To resume (2026-11-12; superseded)

1. Read the three STATE.md files; finish or drop each item; merge each
   diff into this tree (recipe.yaml and pixi.toml are touched by more
   than one), then `pixi lock`.
2. Read the omicron and kappa logs; fix what they show.
3. On gamma: `pixi install --frozen`, then the chain for default, full,
   minimal (with the wheel), openblas, and `pixi run -e pkg
   conda-package` + `conda-consume`.
4. DONE: interim commits pushed; windows-11-arm's contract passed
   (run 43344258167) and the temporary probe step is removed from
   build-r.yaml (in this tree, uncommitted). NEXT: push T/rel11/handover/diag-avx-make.sh, read
   the named AVX function (finding 17) and the make diagnostics
   (finding 18), fix both.
5. Correct the stale records of finding 12; README sections for the new
   packages. (2026-11-12, night: done in this tree, uncommitted.)
6. Last: the stress run on the branch (all runners, tree and conda),
   read its table row by row (N6, K1, the arrow and RcppSimdJson rows
   for evex512); then the publish preflight and the one release of
   build 11 for six subdirs.

## The three items, as their agents left them (2026-11-12, 19:47; superseded: done 2026-11-13)

Each agent was stopped early. Their state files have the design, the
remaining steps and the resume commands; none of their work is reviewed.
Paths are under /data/gamma/luciorq/workspaces/temp/r-zig-pixi/ (T).

### `R CMD config` through rzig — design only, no code

State: T/rel11/scratch-config/STATE.md. Tree T/wt/rel11-config has no
change of its own (the build-1 pins are applied there; R and the
toolchain are built; compile-tree's exit was not read).

- Route: R's own Rcmd dispatch runs `rzig config` on every OS, with no
  script: a new patch 0010 (four lines in Rcmd.in, one changed line and
  a quote fix in rcmdfn.c) replaces the make check; bin/config and
  bin/config.sh are no longer installed.
- rzig: a new config.zig that follows the script step by step and reuses
  makefile.zig's evaluator, with two extensions: GNU make's built-in
  variables as a `default` origin (for config only), and a lenient mode
  in shellwords.zig with sh's `echo` rules.
- The variable list and help text are compiled into rzig; a parity test
  (scripts/config-parity.sh, run by `contract` on the compile tree)
  compares `R CMD config <args>` with the unpatched script.
- Traps: the script's output depends on which `echo` make runs (dash
  expands backslash escapes; a leading -n or -e is an option); the "no
  information" error goes to stdout; rcmdfn.c leaves the outer quote
  open when no argument follows; Zig refuses tabs in multiline strings
  (embed the usage text as a file); `$(shell ...)` in a `:=` line of a
  user's Makevars cannot be answered without make (planned: exit 2 with
  the reason; a question for the user).
- The tests that expect exit 127 without build tools must change; the
  state file lists them.

### The extras group (cmake) — design only, no code

State: T/rel11/scratch-extras/STATE.md. Tree T/wt/rel11-extras has no
change of its own, and the build-1 pins are NOT applied there: run
`bash T/rel11/pins-build1.sh <tree>`, copy T/rel11/baseline/pixi.lock,
`pixi install --frozen` first.

- cmake's source: PyPI's `cmake` 4.4.4 wheel for the standalone tree and
  the wheel channel (as `ziglang` serves zig); conda-forge's cmake as a
  dependency of an otherwise empty `r-zig-extras`. conda-forge's cmake
  cannot be copied into the tree: its bin/cmake has a prefix
  placeholder, which the toolchain build refuses, and it links ten
  shared libraries (libcurl and its closure).
- All six targets have a PyPI wheel (macOS: one universal2 wheel);
  conda-forge has cmake 4.4.5 for win-arm64.
- Layout: `TC/cmake/` with bin/cmake, share/cmake-4.4/, SOURCES and
  LICENSES/cmake/; no cpack or ctest (21 MB each).
- R finds it by one more PATH entry, `TC/cmake/bin`, where the build
  tools' are set today: etc/Renviron on unix, R_ZIG_TOOLS_PATH in
  Rcmd_environ and patch 0014 on Windows.
- r-zig-extras pins r-zig-slim and depends on cmake; r-zig-toolchain
  would include it (about 26 MB of download, from the lock).
- Traps: the wheel's cmake needs the host's libstdc++.so.6 and
  libgcc_s.so.1 on linux (verify-toolchain allows glibc's only); the
  macOS binary is a fat Mach-O, which verify-toolchain's detection
  skips.
- Not verified: cmake was never run from the wheel; whether `zig fetch`
  unpacks a .whl and keeps the executable bit.
- Questions for the user: is the host's libstdc++ on linux acceptable;
  may R print a note when a package's SystemRequirements names cmake
  and the group is missing.
- Superseded 2026-11-13: built on branch rel11b-extras; the standalone
  tree's cmake/ now comes from Kitware's release archives, not PyPI's
  wheel (the user's decision; Kitware's linux cmake needs glibc only).
  Record: feat-extras-group/PLAN.md.

### The recommended packages — two Zig files written, never compiled

Superseded 2026-11-13: done in wt/rel11b-recommended, recorded in
.github/devdocs/feat-recommended-packages/PLAN.md. The state below is
the 2026-11-12 stop.

State: T/rel11/scratch-recommended/STATE.md. Tree
T/wt/rel11-recommended has two new files and nothing else; the build-1
pins are NOT applied there (as above). R is built; toolchain and
compile-tree were not run.

- Written, untested: zigbuild/recommended/build.zig (one
  `R CMD INSTALL` step per package) and zigbuild/recommended/order.zig
  (reads the names from share/make/vars.mk and the dependencies and
  INSTALL_OPTS from src/library/Recommended/Makefile.in, with unit
  tests).
- Design: its own small build file, as the toolchain's; it runs R from
  the compile tree.
- Planned conda package: `r-zig-recommended`, run-depends on the exact
  r-zig-slim only, nothing depends on it; r-zig-slim's file list must
  exclude the same 15 directories.
- Not started: scripts/zig-recommended.sh, the env.sh prefix, pixi
  tasks, recipe/test-recommended.R, the verify script, the recipe and
  build.sh changes, the standalone archive, the record.
- From the tarballs only: Matrix is the only one with Makevars rules
  (make path, needs build-tools at build time); the others should be
  tier 1; boot and codetools have no compiled code.
- Trap: mgcv's Makevars uses the OpenMP flags, so a slim-built mgcv
  would not load on minimal; a standalone archive would need the flavor
  in its name.
- Not verified: rpaths in the package libraries, a build path left by
  `--no-staged-install`, all timings and sizes.

## Chains at 19:47 (2026-11-12)

- gamma, linux-64 slim, with visibility: toolchain-test, rzig-test,
  smoke, verify-tree, toolchain, verify-toolchain, contract and
  pkg-parity exit 0; check was running, then hermetic, package,
  package-toolchain, verify-package (T/rel11/linux64-chain2.log, lines
  starting `===`).
- omicron arm64 (final lock, `~/.pixi/rz-rel11/arm64.log`):
  toolchain-test and rzig-test OK, build running; the osx-64 chain
  starts after it (`x64.log`), and `chain.out` ends with `EXIT=done`.
- kappa (final lock, `C:\Users\admin\rz-rel11.log`): toolchain-test and
  rzig-test OK, build running. Its chain runs inside an ssh session of
  the stopped session and may have died with it: if the log has no
  `=== END`, run `C:\Users\admin\rz-rel11-chain.bat` again over a held
  ssh session.
- ssh to both hosts: `export SSH_AUTH_SOCK=/run/user/1000/rz.sock`.
