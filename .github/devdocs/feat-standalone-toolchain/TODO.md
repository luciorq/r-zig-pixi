# TODO — feat-standalone-toolchain

PLAN.md (same directory) has the design, the options and the reasons;
the numbers below refer to its "Decisions for the user". Every phase:
implement in a worktree, review, test on linux-64 here, omicron
(osx-arm64, osx-64 under Rosetta) and kappa (win-64), then CI. The user
makes the commits (hand over the commands); docs-only commits get
`[skip ci]`.

## Decisions the user makes first

- [ ] 1 Layout: overlay archive in the same top directory (rec.), or a
      separate toolchain directory (item 4)
- [ ] 2 zig's artifact: fetch-zig.sh's pinned PyPI wheel (rec.), or
      ziglang.org via a mirror with minisign
- [ ] 3 Where zig enters: build.zig `-Dbundle-zig` for every non-conda
      tree plus env.sh always exporting ZIG_BIN (rec.), opt-in for
      packaging, added at packaging, or downloaded by rzig
- [ ] 4 rzig lookup: ZIG_BIN, bundled, PATH, python3 -m ziglang; flang
      bundled before PATH (rec.)
- [ ] 5 make on unix: conda-forge's make in every non-conda unix tree
      (rec.), host make for slim/full, or make built with zig
- [ ] 6 Fortran: flang-pixi's compile set (flang-23 + link, the .mod
      files, libflang_rt.runtime.a; 30.5-43.9 MB zstd; no lld, sysroot
      or flang.cfg; proved by flang-pixi on all four OSes) in the
      toolchain archive, once zig-fc's executable links through zig
      pass (rec.); none; the full closure; or a separate archive
- [ ] 7 OpenMP headers and libomp.lib: stay in base (rec.), move to the
      toolchain archive, or under bin/toolchain with an rzig change
- [ ] 8 Windows: split now, toolchain zip still expects sh/make on PATH,
      userland prototype then bundle (rec.); or m2 now; or Rtools; or
      unsplit until item 2
- [ ] 9 Zig for released standalone R: upstream once a release job exists
      (rec.), or the env's conda-forge zig
- [ ] 10 Publishing: CI artifacts in this PR, release job later (rec.),
      or a release job now
- [ ] 11 Compression: gzip (rec., revisit after phase 4; with flang,
      linux-64 is about 150 MB gzip, 105 MB zstd), xz or zstd
- [ ] 12 Conda build number 4 → 5 in the last phase (rec.), or none
- [ ] 13 Remove patch 0009's Makeconf-CC fallback (rec.), or keep it
- [ ] 14 Recipe cleanup scope and order: host block, comment, dead
      @WHICH@, stale comments, first (rec.); or last
- [ ] 15 Working names now (rec.), or wait for the v3 naming decision
- [ ] 16 Every packaged flavor gets the pair; CI packages default and
      minimal (rec.)
- [ ] 17 flang files: copy the documented set from the build env's
      installed flang-zig/flang-rt-zig, provenance from conda-meta into
      SOURCES (rec.); or run flang-pixi's carve script on the .conda
      pinned to a flang-pixi commit (needs Python >= 3.14, a second
      download; the script is not committed in flang-pixi yet)
- [ ] 18 zig 0.17 wave: do not tie our move to flang-pixi's; port
      build.zig/rzig/zig-build.sh to upstream 0.17 on the gated legs
      with a small 0.16/0.17 switch; conda build and r-zig-toolchain
      stay on conda-forge's zig until its main label has 0.17 (rec.); or
      the conda build on a sha256-pinned upstream tarball (`source:`
      entry or universe repackage), as flang-pixi does

## Prerequisites from outside this plan

- [ ] rzig passes `-mcpu=baseline` (pending the user's go): Windows
      package compiles are native today (no `-target`, compiler.zig:42-43;
      kappa target-cpu "skylake"); linux and macOS are baseline already.
      Already affects r-zig-toolchain on win-64; needed at the latest
      before phase 4 ships compilers to Windows users
- [ ] Before flang-pixi uploads flang-rt-zig 10 (the conda build and
      installs of r-zig-toolchain `_4` take flang-zig/flang-rt-zig
      unpinned; a re-lock takes it too): nm build 10's archive on every
      subdir for undefined symbols our zig 0.16 lacks (win-64: 0.17's
      `-D__CRT__NO_INLINE`; all: libc++ 22 headers), link each with our
      zig 0.16, build R and a Fortran package on kappa. Proposed as part
      of flang-pixi's wave; else decide on a temporary `<10` bound

## The zig 0.17 wave (decision 18; not a phase of this PR)

- [x] 2026-10-06: conda-forge has 0.17.0 only on the `zig_dev` label
      (snapshots 0.17.0-dev.2320+1e770dbef, builds 23200-23202); main is
      0.16.0 build 20; PyPI ziglang is 0.16.0; ziglang.org has 0.17.0
      (2026-10-01) for all five platforms
- [ ] After flang-pixi's wave: pixi.toml flang-rt-zig
      `build-number = ">=10"` in [dependencies] (154-160) and
      [feature.minimal.dependencies] (373); delete the win-64 `>=4`
      override (229-234); `llvm-openmp = "23.*"` (183) already matches
      flang-rt 10's new unix `llvm-openmp >=23`
- [ ] With decision 18 settled: the port of build.zig and rzig to 0.17
      (flang-pixi docs/17 §4: `b.install_prefix`, `b.pathFromRoot`,
      configure caching) and zig-build.sh's argument order (docs/17 §8),
      behind a 0.16/0.17 switch; fetch-zig.sh gets a 0.17 pin for the
      upstream legs (PyPI's wheel once it exists, else a ziglang.org
      archive from a mirror, sha256-pinned) while the toolchain archive
      keeps bundling 0.16.0

## Phase 0 — measurements (no code changes)

- [ ] omicron: list and size `lib/R/bin/toolchain` of the osx-arm64 slim
      and minimal trees; `strings` the minimal make for build paths
- [ ] kappa: list and size `Library/lib/R/bin/toolchain` of the win-64
      tree; `needed_of R.dll` shows whether R.dll imports zstd.dll
- [ ] Every OS: sha256 of rzig in slim, full and minimal trees of one
      platform (expected identical)
- [ ] Every OS: gzip -6 and xz -6 sizes of upstream zig plus make, as
      they would sit in bin/toolchain
- [x] flang's set: sizes per subdir measured by flang-pixi (docs/19 §2,
      2026-10-06); not repeated
- [ ] omicron: what `xcrun --sdk macosx --show-sdk-path` does when the
      Command Line Tools are absent (if a machine or account without them
      exists; else note it as untested)

## Phase 1 — recipe host which/sed/grep cleanup

- [ ] recipe.yaml: delete the `if: unix` host entries which/sed/grep
      (lines 224-228) and their comment (196-223)
- [ ] build.zig mkRbase: delete the `@WHICH@` substitution (3416-3422)
- [ ] verify-tree.sh: correct the "nm/realpath/sed/... for bin/libtool
      and javareconf" comment (455-461) to what bin/toolchain holds
- [ ] feat-no-host-paths PLAN.md: correct "Vendored in the standalone
      tree today" (321-324)
- [ ] `pixi run -e pkg conda-package` passes on linux-64, osx-arm64,
      osx-64 (omicron) and win-64 (kappa), both packages' tests included
- [ ] File lists of r-zig-slim and r-zig-toolchain equal build 4's; etc/
      and base's R code equal build 4's; no `/bin/which`, `/bin/sed`,
      `/bin/grep` in either package
- [ ] Optional: drop `which` from the staging build requirements; the
      same conda-package runs pass
- [ ] CI: the five conda-package jobs green

## Phase 2 — the split, with today's contents

- [ ] env.sh: the platform name (linux-64, linux-aarch64, osx-arm64,
      osx-64, win-64) computed once; package-standalone.sh and
      verify-bundle.sh use it
- [ ] package-standalone.sh: base archive = tree minus R_HOME/bin/
      toolchain; toolchain archive `...-toolchain.tar.gz` (Windows `.zip`)
      = only that directory, same top directory; a `.sha256` each
- [ ] build.zig: `R_HOME/bin/toolchain/BUILD` naming R version, flavor,
      platform and commit (only in non-conda trees, or in all; decide in
      review)
- [ ] zig-build.sh: `-Dtoolchain-hint` for every non-conda build, naming
      this flavor's and platform's toolchain archive
- [ ] make-wheel.py: replace an existing R_ZIG_TOOLCHAIN_HINT line with
      the wheel's (renviron_hint), and check it in wheel-test.sh
- [ ] Patch 0009 without the Makeconf-CC fallback (if decision 13); the
      dev contract step still passes
- [ ] verify-bundle.sh: file lists of the two archives against the
      installed tree (base + toolchain = tree, no overlap)
- [ ] verify-bundle.sh: base archive alone, freshly extracted: R starts;
      a `src/` package stops with the standalone hint text; unix `R CMD
      config CC` says "needs make"
- [ ] verify-bundle.sh: the existing checks run on base + toolchain
      extracted over it
- [ ] build-r.yaml: upload both archives (default and minimal legs) with
      a short retention
- [ ] Tested: linux-64 (slim, minimal, wheel, conda-package), omicron
      (osx-arm64 slim and minimal, osx-64 slim), kappa (win-64), CI

## Phase 3 — rzig's toolchain root

- [ ] find_zig.zig: ZIG_BIN, then `<rzig dir>/zig/zig` (`zig.exe` on
      Windows), then PATH, then `python3 -m ziglang`; unit tests for each
      step and for "bundled wins over PATH"
- [ ] flang_rt.zig/fortran.zig: `<rzig dir>/flang/bin/flang` before PATH;
      unit tests
- [ ] main.zig: with no zig at all, a message naming zig and
      R_ZIG_TOOLCHAIN_HINT (exit 127), not a python3 error; unit test
- [ ] env.sh: export `ZIG_BIN=$ZIG` whenever a zig was found; wheel-test
      and conda-package unaffected (checked)
- [ ] `pixi run rzig-test` on linux-64, osx-arm64, osx-64, win-64
- [ ] conda: test-toolchain.R still compiles with the env's zig (a root
      with no zig/); wheel-test still uses ziglang

## Phase 4 — upstream zig in the toolchain

- [ ] build.zig: `-Dbundle-zig=<dir>` installs fetch-zig's `ziglang/`
      into R_HOME/bin/toolchain/zig/ (one install-directory step), with
      the dist-info licences
- [ ] zig-build.sh: runs fetch-zig and passes `-Dbundle-zig` for every
      non-conda build; the conda build gets nothing
- [ ] make-wheel.py: excludes `lib/R/bin/toolchain/zig/`; the toolchain
      wheel stays under 1 MB
- [ ] verify-tree.sh: bin/toolchain/zig/** counted as third-party in the
      build-path scan; `zig/zig version` is 0.16.0
- [ ] hermetic-check.sh: copies the tree without bin/toolchain
- [ ] verify-bundle.sh: base + toolchain, ZIG_BIN unset, `env -i` with
      PATH=/usr/bin:/bin: RZIG_PRINT_ARGV shows the bundled zig; a C, a
      C++ (no shared libc++/libstdc++) and an OpenMP C package, and the
      flagless omp.h probe, build and load
- [ ] The mixed case: R built with conda-forge zig (default legs), slim
      with OpenMP, through the bundled zig — passes on every OS
- [ ] The same with ZIG_BIN from fetch-zig (R built with upstream zig)
- [ ] Record archive sizes per OS in PLAN.md
- [ ] Tested: linux-64, omicron (both), kappa, CI, upstream-zig label run

## Phase 5 — make in every unix toolchain

- [ ] build.zig: conda-forge's make into bin/toolchain for every
      non-conda unix tree (was minimal only)
- [ ] build.zig finalRenviron: `R_ZIG_MAKE` and `MAKE=${MAKE-${R_ZIG_MAKE}}`
      for every non-conda unix tree
- [ ] verify-tree.sh: make present in slim/full/minimal non-conda trees;
      within the 2.28 glibc ceiling
- [ ] verify-bundle.sh: with the toolchain, `Sys.getenv("MAKE")` is the
      bundled make; `R CMD config CC` works; install.packages(Ncpus = 2)
      of two compiled packages runs make
- [ ] Base alone: hermetic still passes (install one at a time; R CMD
      config "needs make")
- [ ] omicron: slim compiles with no Command Line Tools make involved
      (MAKE is the bundled one)
- [ ] Tested: linux-64, omicron (both), CI

## Phase 6 — licences and sources

- [ ] Licence texts kept in the repository (GPL-3.0, GPL-2.0 if
      busybox, Apache-2.0 WITH LLVM-exception)
- [ ] build.zig installs bin/toolchain/LICENSES/ (zig's LICENSE and
      dist-info licences, make, Windows binutils, and what phases 7/8 add)
      and bin/toolchain/SOURCES (upstream source URL, version, sha256,
      conda-forge feedstock version for each third-party binary)
- [ ] verify-tree.sh: every third-party binary in bin/toolchain has an
      entry in SOURCES and a licence in LICENSES/
- [ ] The r-zig-toolchain wheel carries them (same directory)
- [ ] Tested: linux-64, omicron, kappa, CI

## Phase 7 — Fortran (only with decision 6 = b)

Proved by flang-pixi (docs/19, handoff §8; 2026-10-06), not repeated:
- [x] The set (bin/flang-23 + flang link, Windows flang.exe; the .mod
      files under lib/clang/23/finclude/flang/<conda triple>/, both
      Windows dirs; libflang_rt.runtime.a) compiles hello, derived
      types, `use omp_lib` and OpenMP directives with nothing else on
      PATH on linux-64, osx-arm64, osx-64 and win-64
- [x] zig links the runtime archive (unix `-lm`, plus `-lomp` for
      OpenMP; Windows plus our libomp import lib) with no lld, sysroot,
      SDK path or CRT snapshot; programs run, OpenMP on two threads
- [x] The flang executables load only system libraries; sizes 30.5-43.9
      MB zstd per subdir
- [x] No flang.cfg on linux and Windows; on macOS `-fintrinsic-modules-path`
      replaces it; `-mmacos-version-min` already passed by zig-fc
      (fortran.zig:58)
- [x] Windows `-lc++` checked (PLAN Design 5): flang-rt-zig build 4's
      win-64 archive has no undefined C++ runtime symbol; a cross link
      of a Fortran exe and DLL succeeds without `-lc++`, and with it the
      DLL is the same size with the same imports and exports. FLIBS not
      changed

Ours:
- [ ] Decision 17 settled
- [ ] Prototype: zig-fc sends every link through zig: a call with
      sources and a link becomes `flang -c` per source plus the zig link
      with the runtime archive (reverses F3c's "a mixed call stays
      flang's"); unit tests; a real configure that probes `$FC` passes
      on linux-64, osx-arm64, osx-64 and win-64, from the standalone
      tree and from a conda env
- [ ] Prototype: zig-fc passes `-fintrinsic-modules-path` from flang's
      own location on every compile; harmless beside a conda env's
      flang.cfg; where the conda triple comes from (constant or scan)
- [ ] Prototype: rzig's runtime lookup (`flang -print-resource-dir`)
      finds the archive under bin/toolchain/flang/; on Windows flang
      still finds its resource dir without the `Library/` prefix; the
      driver works as the single file `flang` (no flang-23 beside it)
- [ ] Prototype (kappa): a Fortran package builds and loads without
      `-lc++`; (omicron) R builds, and its Fortran-using libraries load,
      without linkFortranRt's `link_libcpp`
- [ ] Decide with the user from the prototype; an OS whose executable
      links fail ships without Fortran
- [ ] build.zig: install the set from the env into bin/toolchain/flang/
      for non-conda trees (flang-zig's layout, no `Library/`, no
      flang.cfg, no lld; the driver once, as `flang`, since zig's
      install step would copy the `flang` link's 196 MB target again);
      flang-zig/flang-rt-zig name, version, build, URL and sha256 from
      conda-meta into SOURCES; verify-tree checks each copy against
      conda-meta's `paths_data` sha256
- [ ] Cross-check once: flang-pixi's carve-fortran-standalone.py on the
      same two packages gives the same driver, modules and runtime
      archive (sha256; its flang.cfg, lib/ symlink and origin file
      aside)
- [ ] Where the kappa/omicron runs passed: drop `-lc++` from Windows
      FLIBS (build.zig:1824) and rzig's flibs (fortran.zig:75), and the
      runtime's `link_libcpp` (build.zig:2702) on that OS; comments
      updated
- [ ] make-wheel.py: excludes bin/toolchain/flang/ (unless decided)
- [ ] fortran.zig: the no-flang message updated
- [ ] verify-bundle.sh: base + toolchain, ZIG_BIN unset, no flang on
      PATH, no flang.cfg: a Fortran package with a derived-type module,
      USE_FC_TO_LINK, `use omp_lib` running on two threads, and a
      configure that compiles and links with `$FC`
- [ ] Tested: linux-64, omicron (both), kappa, CI

## Phase 8 — Windows userland (only with decision 8)

- [ ] Prototype on kappa: busybox64u.exe as sh.exe plus per-applet .exe
      files, with conda-forge's make.exe; then the m2 set; each against
      the contract set (C, C++, Fortran, OpenMP), pak, data.table, glue
      and a pkg-config package
- [ ] Scan CRAN's configure.win/configure.ucrt for bash-only syntax;
      record the count
- [ ] Decide with the user from the prototype
- [ ] build.zig: install the chosen userland into bin/toolchain/usr/bin
      (Windows, non-conda); SHA256 pins for anything downloaded
- [ ] build.zig: etc/Rcmd_environ with
      `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`
      for non-conda Windows trees; Rprofile.windows too if the
      prototype needs it
- [ ] `R CMD config` without the toolchain fails with one clear message
      on Windows
- [ ] verify-bundle.sh (Windows): base + toolchain with PATH = bin\x64 +
      System32 only: the contract-set packages build and load
- [ ] Licences and SOURCES for the userland (phase 6's format)
- [ ] Tested: kappa, CI windows-latest

## Phase 9 — finish

- [ ] recipe build number 4 → 5 (if decision 12; build 4 is on the
      channel since 2026-10-06); conda-package on all five platforms
- [ ] feat-no-host-paths PLAN.md: What remains 3 points here; the T
      record and the OpenMP note (400-403) updated
- [ ] installOpenMP's comment updated to decision 7
- [ ] This PLAN.md: status and records with dates and test results
- [ ] upstream-zig label run green
- [ ] Last round: linux-64, omicron (osx-arm64, osx-64), kappa, CI all
      green; hand the commit and PR commands to the user
