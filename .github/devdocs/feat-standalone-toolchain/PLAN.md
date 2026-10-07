# feat-standalone-toolchain — a standalone toolchain archive, and the recipe's host which/sed/grep cleanup

**Status (2026-10-05): planned, not started.** Branch
feat-standalone-toolchain, to start from main once feat-no-host-paths is
merged. This is "What remains" item 3 of
.github/devdocs/feat-no-host-paths/PLAN.md (lines 154-155): "T's
standalone split (a standalone toolchain archive), then the recipe's host
which/sed/grep cleanup." Everything under Design is a proposal until the
user settles the numbered items under "Decisions for the user". Earlier
decisions are marked "(decided <date>)" with their source. Line
references are to feat-no-host-paths at 992269a and to R 4.6.1
(`build/R-4.6.1/`, patched). "PLAN.md" alone means feat-no-host-paths'
PLAN.md.

**Updated 2026-10-06.** feat-no-host-paths is merged (main 53687ab,
whose tree equals 992269a, so the line references hold). flang-pixi
measured the trimmed flang this plan proposed (flang-pixi
docs/19-standalone-fortran-toolchain.md; handoff §8 in
.github/devdocs/consolidation/FLANG_PIXI_HANDOFF.md). Design 5 and
decision 6 now use those measurements instead of estimates, and the
sizes are corrected. Two decisions are new: 17, how build.zig gets the
flang files, and 18, the zig 0.17 wave (its own section, before the
decisions). Also checked here: whether Windows FLIBS still needs
`-lc++` (Design 5), conda-forge's zig labels (the 0.17 section), and
the channel's build 4, whose r-zig-toolchain takes flang-pixi's newest
flang-zig and flang-rt-zig unpinned ("What exists today").

**Phase 0 measured 2026-10-06** (no code changes; "Phase 0
measurements" below, after "Other facts"). It answers three open
questions:
- rzig is byte-identical across the flavors of a platform;
- R.dll imports zstd.dll itself;
- what xcrun and rzig do with no usable developer directory, simulated
  on omicron.

It also replaces the toolchain size estimates with measurements per
platform: upstream zig, conda-forge's make and rzig, as they would sit
in bin/toolchain. The decisions are untouched.

**Phase 1 implemented 2026-10-06** (the recipe cleanup, Design 11;
uncommitted). On linux-64 conda-package passes, and both packages equal
build 4's apart from build directories, dates and conda-forge's newer
harfbuzz floor ("Phase 1 record" under Design 11). omicron, kappa and
CI are still to run.

Two other items overlap with this one:
- Item 2, the Windows minimal variant and the Windows wheel. Its blocker
  is the sh/make/coreutils userland that package compilation needs on
  Windows (PLAN.md:2402-2431), and this plan's Windows toolchain needs
  the same userland. One choice serves both items (Design 7).
- Item 4, the toolchain in an environment of its own
  (`R_ZIG_TOOLCHAIN_ENV`, PLAN.md:681-692, "later, test carefully
  first"). This plan keeps it out of scope, and picks a layout that item
  4 can adopt later (Design 1 and 2).

## Goal

What a user of the standalone distribution gets, by tier (tiers from
PLAN.md:258-265):

| Tier | Covers | What to download | What it needs from the machine |
|---|---|---|---|
| 0 Run | `R`, `Rscript`, `library()` | the base archive | unix: `/bin/sh` (and `readlink` when R is reached through a symlink); Windows: nothing beyond System32 |
| 1 Install without compiling | R-only source packages, binary packages, `remove.packages()`, `install.packages(Ncpus > 1)` | the base archive | the same |
| 2 Compile | `src/`, `configure`, `R CMD SHLIB`, `R CMD config` | the base and the toolchain archive, extracted in the same place | unix: `/bin/sh` and the POSIX tools every unix has. No conda, pixi, Python, Command Line Tools make, or zig on PATH. Windows: nothing, once the userland is decided (decision 8) |
| 3 Develop | `R CMD check`, `Rd2pdf`, vignettes | neither | found on PATH when used (unchanged) |

Without the toolchain archive, a package with compiled code stops with
the preflight message, which names the toolchain archive. `R CMD config`
says make is missing (unix today, Windows in phase 8).

For the project, the standalone distribution splits the way conda and
pip already do:
- base = the installed tree minus `R_HOME/bin/toolchain`;
- toolchain = that directory.
That is one rule for all three distributions.

Second, and separate: the recipe loses its unix host `which`, `sed` and
`grep`, leftovers of the `@WHICH@`/`@SED@` bakes. Neither conda package
changes as a result.

Not in this PR (proposed):
- publishing the archives anywhere but CI artifacts (a release job,
  decision 10);
- the toolchain in an environment of its own (item 4);
- the Windows minimal variant and wheel (item 2), apart from the shared
  userland choice;
- the final package and archive names (the v3 naming question,
  PLAN.md:2601-2603).

## What exists today

### The conda and wheel splits (phase T, done)

- **conda.** One staging output (`r-zig-build`) and two packages split
  by directory (recipe/recipe.yaml:312-319, 429-489).
  - r-zig-slim excludes `lib/R/bin/toolchain/**` and
    `Library/lib/R/bin/toolchain/**`.
  - r-zig-toolchain holds exactly those. It uses `run_exports: false`
    and run-depends on `pin_subpackage("r-zig-slim", exact=True)`,
    `zig 0.16.*`, flang-zig, flang-rt-zig and `make >=4.4`. On Windows
    it also depends on the m2 userland: bash, sed, grep, gawk,
    coreutils, make, which and findutils.
  - Build number 4 is on the channel since the merge. universe's
    repodata for all five subdirs lists r-zig-slim `_4` and
    r-zig-toolchain `_4` (fetched 2026-10-06; on 2026-10-05 it had only
    r-zig-slim `_2` and `_3`).
  - r-zig-toolchain `_4` run-depends on `zig 0.16.*`, and on
    `flang-zig` and `flang-rt-zig` with no version or build pin (the
    same repodata). Every new install therefore takes flang-pixi's newest
    builds ("The zig 0.17 wave").
- **pip.** make-wheel.py splits the minimal tree on `TOOLCHAIN_PREFIX =
  "lib/R/bin/toolchain/"` (scripts/make-wheel.py:52, 399-402).
  - The r-zig-toolchain wheel (892 KB) holds the five rzig copies and
    GNU make. It requires `ziglang>=0.16.0,<0.16.1` and
    `r-zig==<version>`.
  - zig is not in it. The base wheel's etc/Renviron.site points
    `ZIG_BIN` at the sibling ziglang install (make-wheel.py:229-241).
    The hint is appended to etc/Renviron (make-wheel.py:244-251).
  - wheel-test.sh installs r-zig alone and expects the preflight. It
    then installs the toolchain and compiles, then uninstalls the
    toolchain and checks that R is whole. pip upgrade and uv are not
    tested.
- **In both,** the toolchain directory holds only our own files (rzig,
  plus make in the wheel). The compilers come from the package manager:
  conda's run dependencies, or the ziglang distribution.

### The standalone archive

- `scripts/package-standalone.sh` only archives the installed tree (F1,
  F1.7).
  - Output: `dist/R-<ver>-<flavor>-<plat>.tar.gz` (Windows `.zip`) plus
    a `.sha256`, with top directory `R-<ver>-<flavor>-zig`.
  - The flavor is the variant, plus `-<blas>` for openblas
    (scripts/env.sh:22-24).
- CI packages the default leg (slim, and Windows' one variant) and the
  minimal leg, and runs verify-package on both. It uploads only the
  wheel (.github/workflows/build-r.yaml:84-121), and nothing publishes
  standalone archives. upstream-zig.yaml runs on `v*` tags as a release
  gate, but there is no release job.
- `R_HOME/bin/toolchain` in the tree:
  - unix: rzig as zig-cc, zig-cxx, zig-fc, zig-ar and zig-ranlib
    (build.zig:2412-2440). On linux-64 each copy is static: 407,360 B
    in the trees of 2026-10-02/03, and 407,872 B in build 4's
    r-zig-toolchain (HEAD's rzig sources). In the trees of 4868515's
    sources each copy is 306,416 B on osx-arm64 and 746,496 B on win-64
    (build 4: 306,416-306,432 and 747,008; Phase 0 measurements).
  - minimal also holds GNU make, conda-forge's 4.4.1
    (build.zig:910-917), and minimal's Renviron names it as `MAKE`
    (build.zig:3660-3664). slim and full have `MAKE=${MAKE-'make'}`,
    which is the host's make.
  - Windows: rzig as gcc.exe, g++.exe, zig-fc.exe, zig-cc and zig-cxx.
    It also holds plain copies of conda-forge's MinGW binutils: ar,
    ranlib, nm, dlltool, strip, as, ld and windres (build.zig:1744-1764).
    They are GPL-3.0-only and 13,642,752 B together. All of them import
    zstd.dll, and so does R.dll (Phase 0 measurements).
- Outside that directory, for packages:
  - the OpenMP headers omp.h, ompx.h, omp-tools.h and ompt.h in
    `<prefix>/include`. On Windows they go in `Library/include`, and
    there are only omp.h and ompx.h.
  - on Windows, `Library/lib/libomp.lib`.
  - These come from installOpenMP (build.zig:2925-2963), whose comment
    says "Phase T's standalone toolchain archive takes the headers and
    the import library over".
  - libomp itself is in base: unix `lib/`, Windows
    `R_HOME/bin/x64/libomp.dll`.
- Not in the tree: zig, flang, make for slim and full, and on Windows
  any sh/make/coreutils.
- Sizes on linux-64 (built 2026-10-03, before the last five commits):
  - slim archive: 73.8 MB (159 MB unpacked);
  - minimal archive: 51.2 MB (98 MB unpacked).

### How a compile finds its tools today

- **zig.** rzig takes `ZIG_BIN` when it names an executable. Otherwise
  it takes `zig` or `x86_64-w64-mingw32-zig` from PATH, and finally
  `python3 -m ziglang` (zigbuild/tools/rzig/find_zig.zig:14-23). With
  none of these, the error is about python3 (exit 127) and does not
  mention zig or the toolchain.
- **flang.** Found on PATH only. Without one, zig-fc exits 127 with "no
  flang on PATH ... the wheels and the standalone tree bring none:
  install LLVM flang" (zigbuild/tools/rzig/fortran.zig:62-68). flang
  reads a flang.cfg beside itself if there is one. flang-pixi has since
  shown that a small set of files copied out of the install compiles
  without the cfg on linux and Windows, and on macOS with one flag that
  zig-fc can pass (Design 5).
- **The Fortran runtime.** rzig asks the flang it found for
  `-print-resource-dir`, and links
  `<resource dir>/lib/*/libflang_rt.runtime.a`
  (zigbuild/tools/rzig/flang_rt.zig:43-60). FLIBS is
  `-lflang_rt.runtime -lc++` on Windows (build.zig:1816-1824,
  fortran.zig:73-77) and `-lflang_rt.runtime -lm` elsewhere.
- **make and sh.**
  - unix: Renviron's `MAKE`.
  - Windows: install.R hard-codes `MAKE <- "make"` (install.R:174) and
    runs configure.win/configure.ucrt with `sh`, so make and sh must be
    on PATH.
- **The environment.** It is rzig's own real path minus
  `/lib/R/bin/toolchain` (Windows `/Library/lib/R/bin/toolchain`), plus
  `R_ZIG_EXTRA_ENV`. `CONDA_PREFIX` is never read
  (zigbuild/tools/rzig/environment.zig:7-20, 54-63). A copy of rzig
  anywhere else has no environment of its own. A `-fopenmp` link gets
  `-lomp` when an environment has `include/omp.h` (:91-97).

### The preflight, the hint and R CMD config

- **The preflight.** Patch 0009 adds a check to install.R before
  configure runs. It stops the install when all of these hold:
  - the package has `src/` or a configure script;
  - `R_HOME/bin/toolchain/zig-cc` does not exist;
  - the CC that Makeconf names does not exist (a fallback for the
    unstaged build tree, which F1 retired);
  - there is no user Makevars;
  - `R_ZIG_NO_PREFLIGHT` is unset.

  The message is "this package has compiled code, and the r-zig
  toolchain is not installed: " followed by `R_ZIG_TOOLCHAIN_HINT`.
  Without a hint, it ends with "install the r-zig toolchain package for
  this R". The check looks at the zig-cc file rather than the directory,
  because pip or conda can leave the emptied directory behind.
- **R CMD config.** Patch 0010 makes unix `R CMD config` fail with
  "needs make, which comes with the r-zig toolchain" when `${MAKE%% *}`
  is not found. Windows runs `sh R_HOME/bin/config.sh`
  (src/gnuwin32/front-ends/rcmdfn.c:532-533) and has no such check.
- **The hint.**
  - build.zig writes `R_ZIG_TOOLCHAIN_HINT` only with
    `-Dtoolchain-hint`: into etc/Renviron, or etc/Renviron.site on
    Windows (build.zig:313-318, 3050-3052, 3669-3671).
  - zig-build.sh passes it only for the conda build
    (scripts/zig-build.sh:57-65).
  - The wheel appends its own.
  - The standalone tree has none, so it prints the generic text.
- **hermetic-check.sh** simulates the base by deleting the toolchain
  directory from a copy of the installed tree. It then checks tiers 0
  and 1, the preflight and, on unix, `R CMD config`
  (scripts/hermetic-check.sh:88-91, 138-153).
- **verify-bundle.sh's compile checks use the build env's tools**
  (scripts/verify-bundle.sh:323-345).
  - unix: under `env -i`, PATH is the pixi env's make and flang
    directories plus /usr/bin:/bin, with `ZIG_BIN=$ZIG`.
  - Windows: make, sh, flang and zig all come from the pixi env's PATH.

  No check compiles with the standalone tree alone.

### What tier 2 needs on each OS, beyond today's tree

| Need | linux | macOS | Windows |
|---|---|---|---|
| zig, upstream 0.16.0 | ziglang.org tar.xz 55.5 MB (aarch64 51.2 MB); PyPI wheel 97.9 MB (aarch64 95.0 MB). Unpacked 356.9 MB (390 MiB on disk): the binary is 172.6 MB and static, lib/ 184.2 MB (225 MiB on disk). Measured: gzip -6 86.6 MB, xz -6 57.4 MB, zstd -19 61.3 MB (aarch64: 83.6 / 52.8 / 59.1 MB) | tar.xz 52.2 MB (arm64) / 57.4 MB (x86_64); wheel 97.3 / 101.2 MB. gzip -6 85.9 / 89.9 MB, xz -6 54.0 / 59.5 MB, zstd -19 59.8 / 63.2 MB | zip 97.2 MB; wheel 98.7 MB. Our zip -6 98.9 MB, gzip -6 87.3 MB, xz -6 58.2 MB, zstd -19 62.1 MB |
| make | slim/full: the host's. minimal: in the tree (conda-forge 4.4.1, 313,656 B, aarch64 436,424 B; links libc and libdl, GLIBC_2.17 at most, RPATH `$ORIGIN/../lib`; about 141 KB gzip -6) | slim/full: `/usr/bin/make`, which on a Mac without the Command Line Tools is a stub that offers to install them. minimal: conda-forge's, 267,120 B (osx-64: 251,736 B), libSystem only | install.R runs `make` from PATH; conda gets m2-make. conda-forge's native make.exe is 17.1 MB unstripped (4.8 MB gzip -6), 288 KB stripped |
| sh and the POSIX tools | the host's | the host's | none. Options: the m2 set (about 16 MB compressed with its dependencies), or busybox-w32 (busybox64u.exe, 675,840 B, GPL-2.0-only) plus a native GNU make |
| flang (flang-zig + flang-rt-zig 23.1.1) | full package 124.5 MB download, 1.07 GB installed. The compile set (Design 5) is 210 MB raw, 43.9 MB zstd -19, 62.2 MB gzip -9 (aarch64: 195.9 / 41.3 / 58.9). Our 279 MB / 63 MB of 2026-10-05 included lld, which is not needed | flang-zig 98.7 / 106.4 MB download; the set is 143.9 / 157.3 MB raw, 30.5 / 35.0 MB zstd | flang-zig 205.7 MB plus lld-zig 108.2 MB download; the set is 190.1 MB raw, 40.1 MB zstd. flang-rt-zig build 4 is 8.7 MB |
| omp.h, libomp.lib | in the tree | in the tree | in the tree |
| binutils | not needed: rzig runs zig's ar and ranlib | not needed | in the tree. nm is used on every DLL link (winshlib.mk) |
| SDK | none | rzig runs `xcrun --sdk macosx --show-sdk-path`; frameworks need the SDK. With no usable developer directory (simulated), xcrun exits 1 at once, and rzig compiles without the SDK flags: plain C links, `-framework` fails | none |

Sources:
- https://ziglang.org/download/index.json and
  https://pypi.org/pypi/ziglang/0.16.0/json (fetched 2026-10-05);
- prefix.dev universe repodata for each subdir (2026-10-05);
- flang-pixi docs/19 §1-§2 (the flang compile set, measured 2026-10-06);
- pixi.lock's m2-* entries;
- https://frippery.org/busybox/;
- zigbuild/tools/rzig/darwin.zig:31-55;
- build/R-4.6.1/share/make/winshlib.mk:7-26;
- "Phase 0 measurements" below (2026-10-06): the make sizes and
  linkage, the measured zig sizes, and the SDK simulation.

### Other facts the design depends on

- **PyPI's ziglang is ziglang.org's build.** For 0.16.0, the zig binary
  and all 19,541 lib files are byte-identical (F4, PLAN.md:715-720).
  - scripts/fetch-zig.sh already pins the PyPI wheel's sha256 for all
    five platforms. It downloads with curl and unpacks with unzip into
    `build/zig-upstream/` (fetch-zig.sh:20-78).
  - ziglang.org asks automated downloaders not to hardcode ziglang.org.
    It wants them to use its community mirrors and verify with minisign
    (https://ziglang.org/download/community-mirrors/).
- **zig 0.17.0** has been on ziglang.org since 2026-10-01. It is not on
  PyPI or on conda-forge's main label (checked again 2026-10-06; "The
  zig 0.17 wave" below). flang-pixi's docs/17 said "look now, change
  nothing yet".
- **flang relocates, but its own executable links do not** (flang-pixi
  docs/19 §3, measured 2026-10-06).
  - flang-zig, lld-zig and flang-rt-zig have no prefix placeholders, so
    they relocate by plain extraction.
  - The compile set (Design 5) compiles `use omp_lib` with nothing else
    on PATH, and zig links the result.
  - flang's own driver link needs much more than the set:
    - linux: `ld.lld`, conda's `sysroot_linux-64` (265 MB; without it
      the result binds the build host's glibc, GLIBC_2.34 on a 2.39
      host), flang-rt's compiler-rt crt objects and
      `--rtlib=compiler-rt`;
    - macOS: `SDKROOT`, then Apple's `ld` or lld-zig's `ld64.lld`;
    - Windows: `ld.lld` and flang-rt's 14 MB MinGW CRT snapshot.

    So configure probes that compile and link a Fortran program through
    flang's driver would fail in the standalone tree.
  - Package shared links (USE_FC_TO_LINK) already go through zig, not
    flang's driver (fortran.zig).
- **Our compiles' CPU baseline** (checked 2026-10-06). R itself is
  built for the baseline CPU on every OS (build.zig:352-387,
  `cpu_model = .baseline`; no %ymm/%zmm registers in R's linux and win-64
  binaries). rzig's package compiles are baseline on linux
  (`-target x86_64-linux-gnu.2.17` gives target-cpu x86-64) and on macOS
  (`-target <arch>-native.13.0` gives apple-m1 or core2). On Windows
  they are native: rzig passes no `-target` there
  (zigbuild/tools/rzig/compiler.zig:42-43), and on kappa a compile has
  target-cpu "skylake". flang's output is x86-64 baseline. Plain `zig
  cc` emits native-CPU code unless given `-mcpu=baseline`; conda-forge's
  wrapper adds it, but rzig calls the zig binary directly (flang-pixi
  docs/19 §6). A `-target` that names the architecture, as rzig's linux
  and macOS targets do, also selects the baseline CPU (zig 0.16's
  std/zig/system.zig:377-380), which is why only Windows is native.
  This holds for both zigs. A fix (rzig passes
  `-mcpu=baseline`) is pending the user's go; Design 3 lists it as a
  prerequisite.
- **GNU make on Windows needs real executables, and needs to be GNU
  make.**
  - It runs simple recipe lines without a shell. So `rm`, `cp`, `sed`
    and the rest must exist as .exe files on PATH, not only as shell
    applets (CRAN's R 4.6 Windows howto; make's README.W32).
  - busybox-w32's own make applet (pdpmake) cannot parse R's
    Makeconf.win, which uses `$(if)`, `$(patsubst)` and `$(shell ...)`.
- **configure.win may use bash syntax.** It runs as `sh configure.win`,
  and R-exts says bash is used since R 4.2.0. Some CRAN scripts may
  therefore use bash syntax that busybox's ash lacks.
- **R's own hook for tools outside Rtools.** In installer builds, R
  uncomments lines in etc/Rcmd_environ and Rprofile.windows that prepend
  `${R_CUSTOM_TOOLS_PATH:-${R_RTOOLS45_PATH}}` to PATH
  (src/gnuwin32/fixed/etc/Rcmd_environ:38-42,
  src/library/profile/Rprofile.windows:64-86). build.zig installs
  Rcmd_environ as it is, with those lines commented
  (build.zig:1501-1518).
- **Licences of what the toolchain would bundle.**

  | Component | Licence |
  |---|---|
  | zig | MIT; the libc notices are in the wheel's dist-info/licenses |
  | GNU make, binutils, the MSYS2 tools | GPL-3.0, or GPL-3.0-or-later |
  | busybox | GPL-2.0-only |
  | flang, flang-rt (lld is no longer needed, Design 5) | Apache-2.0 WITH LLVM-exception |

  The r-zig-toolchain wheel and the minimal tree already redistribute
  GNU make, and the Windows tree redistributes binutils, with only R's
  COPYING. feat-wheel-minimal/PLAN.md:130-135 lists third-party licence
  texts as an open prerequisite for publishing the wheel.

### Phase 0 measurements (2026-10-06)

TODO.md's phase 0, measured with no code change. Sizes are in bytes;
MB means 10^6 bytes.

Compression method: each tree goes through `tar --sort=name` and then
one of gzip 1.14 `-6 -n`, xz 5.8.3 `-6 -T1` or zstd 1.5.7 `-19 -T1`;
win-64 also gets Info-ZIP 3.0 `zip -r -6`. These tools come from the
default env, installed from pixi.lock sha256
e9f17d315fd52ccf58db6a9840379e787e5c51ad80406982f907faa2dc1b9513
(main 6cc4ba6, this branch's afd59a2).

**The trees.** All of them already existed; none was rebuilt.
- **linux-64:** the main checkout's dist/. rzig was installed
  2026-10-02 in slim and 2026-10-03 in minimal, before 2622a6d to
  a1edc58 changed rzig's sources. There is no full tree on linux.
- **osx-arm64:** omicron's ~/r-zig-pixi/dist, with slim, full and
  minimal built 2026-10-04 08:02-08:41. The copy has no .git. Its
  build.zig and rzig sources equal 4868515's, and its pixi.lock is
  f743e74f… (the lock of 4868515 through 992269a).
- **win-64:** kappa's dist\R-4.6.1-slim-zig, the one Windows variant
  (toolchain written 2026-10-04), from the same sources and lock.
- **osx-64 and linux-aarch64:** there is no tree; omicron's ~/rz-osx64
  is gone. rzig comes instead from the channel's r-zig-toolchain build
  4: universe's `_4` packages, whose sha256 matched the repodata. Their
  timestamps are 2026-10-06 10:53-10:58 -0400, right after the merge
  53687ab (10:52), which has HEAD's rzig sources.

**R_HOME/bin/toolchain today:**

| platform, flavor | contents | raw | gzip -6 | xz -6 | zstd -19 |
|---|---|---|---|---|---|
| linux-64 slim | rzig ×5 (407,360 each) | 2,036,800 | 740,733 | 124,700 | 133,290 |
| linux-64 minimal | rzig ×5, make (313,656) | 2,350,456 | 883,035 | 243,772 | 260,258 |
| osx-arm64 slim, full | rzig ×5 (306,416 each) | 1,532,080 | 591,854 | 91,348 | 104,807 |
| osx-arm64 minimal | rzig ×5, make (267,120) | 1,799,200 | 708,972 | 184,960 | 210,523 |
| win-64 | rzig ×5 (746,496 each), 8 binutils (13,642,752) | 17,375,232 | 7,394,695 (zip: 7,394,501) | 2,031,372 | 2,187,770 |

- xz and zstd store the five identical rzig copies about once. gzip's
  32 KB window cannot, so it stores each.
- Build 4's rzig, from HEAD's sources, is 407,872 B on linux-64,
  306,536 on linux-aarch64, 306,416-306,432 on osx-arm64,
  350,880-350,896 on osx-64 and 747,008 on win-64.
- Build 4's win-64 binutils are byte for byte the files in kappa's
  tree.

**rzig across flavors.**
- linux-64: all ten copies in slim and minimal have sha256 b4320d5e….
  That includes two trees installed a day apart, and the
  r-zig-toolchain wheel of 2026-10-03, which also carries minimal's
  make.
- osx-arm64: all fifteen copies in slim, full and minimal have
  fe70b0ec…. That is codesign's ad-hoc signature, identifier
  `rzig-5555…`.
- win-64: one flavor; its five copies are identical (718b1fe7…).
- So rzig depends on the platform only.
- Conda's macOS packages differ. In build 4, the five copies on
  osx-arm64 and on osx-64 each have five different sha256, and their
  sizes differ by up to 16 B: rattler-build re-signs every Mach-O it
  packages, and the identifier follows the file name. Build 4's copies
  on linux-64, linux-aarch64 and win-64 are identical.

**R.dll and zstd.dll** (kappa's tree, `objdump -p`).
- R.dll imports zstd.dll directly, beside Rblas, zlib, deflate, libbz2,
  liblzma, Rgraphapp, pcre2-8, icuuc78, icuin78 and Riconv.
- tiff.dll and all eight binutils import it too.
- rzig's copies import only ntdll and KERNEL32.
- zstd.dll (658,432 B) imports KERNEL32, VCRUNTIME140 and
  api-ms-win-crt-*.
- So zstd.dll stays in base, whatever the split.

**Upstream zig 0.16.0.**
- Source: fetch-zig.sh's PyPI wheels, each checked against its pinned
  sha256. linux-64 came through `pixi run --locked fetch-zig` in this
  worktree; the other four were downloaded on linux the same way.
- The unpacked `ziglang/` holds 19,546 files: zig (zig.exe), lib/
  (19,541 files), LICENSE, README.md, `__init__.py` and `__main__.py`.
- The dist-info is 2.25 MB more, almost all of it RECORD (the wheel's
  file list with hashes, 2,128,153 B on linux-64). Its licence notices
  in `licenses/` are 15 files and 119,414 B.
- lib/ is 184,249,850 B on every platform.
- On disk (btrfs, linux-64) they take 398,976 KiB, of which lib/ is
  230,340 KiB. So the 390 MB and 225 MB this plan gave before were MiB
  on disk; the apparent sizes are 356.9 MB and 184.2 MB.

| platform | wheel | `ziglang/` raw | zig binary | gzip -6 | xz -6 | zstd -19 |
|---|---|---|---|---|---|---|
| linux-64 | 97.9 MB | 356.9 MB | 172.6 MB | 86.6 MB | 57.4 MB | 61.3 MB |
| linux-aarch64 | 95.0 MB | 343.3 MB | 159.0 MB | 83.6 MB | 52.8 MB | 59.1 MB |
| osx-arm64 | 97.3 MB | 369.6 MB | 185.3 MB | 85.9 MB | 54.0 MB | 59.8 MB |
| osx-64 | 101.2 MB | 379.8 MB | 195.5 MB | 89.9 MB | 59.5 MB | 63.2 MB |
| win-64 | 98.7 MB | 361.4 MB | 177.1 MB | 87.3 MB (zip -6: 98.9 MB) | 58.2 MB | 62.1 MB |

In bytes, linux-64's gzip -6 is 86,558,717 and its zstd -19 is
61,303,632. Both reproduce the 86.6 and 61.3 MB measured on
2026-10-05.

**conda-forge's make 4.4.1** (build 3 for each subdir, as pixi.lock
pins it; sha256 checked against the lock). The sizes are of the file
alone, passed to each compressor (no tar):

| subdir | bin/make | gzip -6 | xz -6 | zstd -19 | links |
|---|---|---|---|---|---|
| linux-64 (hb03c661_3) | 313,656 | 141,443 | 119,892 | 127,387 | libc.so.6, libdl.so.2; GLIBC_2.17 at most; RPATH `$ORIGIN/../lib`; not stripped |
| linux-aarch64 (he30d5cf_3) | 436,424 | 167,157 | 128,452 | 148,181 | the same plus ld-linux-aarch64.so.1; GLIBC_2.17 |
| osx-arm64 (h84a0fba_3) | 267,120 | 117,571 | 95,412 | 107,323 | libSystem; minos 11.0; LC_RPATH `@loader_path/../lib/`; ad-hoc signed |
| osx-64 (ha1e9b39_3) | 251,736 | 123,195 | 108,388 | 114,060 | libSystem; minos 11.0; LC_RPATH `@loader_path/../lib/`; not signed (load commands parsed on linux, 2026-10-06) |
| win-64 (hba3369d_3) | make.exe 17,111,844 | 4,830,494 | 779,916 | 863,354 | ADVAPI32, KERNEL32, USER32, api-ms-win-crt-*; 12 debug sections |

- The win-64 package ships the same binary three times: make.exe,
  gnumake.exe and mingw32-make.exe. Stripping a copy gives 287,744 B
  (146,873 with gzip -6).
- The minimal trees' make is the package's file, byte for byte: linux
  8a9d9648…, osx-arm64 f1bbc4fa…. Its info/paths.json records no prefix
  placeholder, so conda installs it unchanged.

**Build paths in make** (`strings -a`). None names our build machine.
- linux: `/home/conda/feedstock_root/build_artifacts/make_<ts>/_h_env_placehold…`
  with `/include`, `/lib` and `/share/locale`.
- macOS: `/Users/runner/miniforge3/conda-bld/make_<ts>/_h_env_placehold…`
  with `/include` and `/lib`.
- These are make's compiled-in INCLUDEDIR (where `include` looks),
  LIBDIR (for `-l<name>` prerequisites) and, on linux, LOCALEDIR. The
  placeholder is never replaced and names no directory, so make falls
  back to its other defaults, and linux make prints English only.
- win-64: `D:\bld\make_<ts>\work`, its `_build_env` headers, and
  `/home/conda/feedstock_root/...` paths of the m2w64-sysroot and gcc
  builds. All of them are in the debug sections: a stripped copy keeps
  only `/usr/local/include`.

**The toolchain directory as it would sit.** This stages one possible
layout of Designs 3a, 4a and 9, not a decision.
- unix: rzig ×5 (build 4's), conda-forge's make, `zig/` (fetch-zig's
  `ziglang/` as unpacked), and `LICENSES/zig-dist-info/` (the
  dist-info's `licenses/`).
- win-64: rzig ×5, the 8 binutils, `zig/` and the same licences. There
  is no make, since decision 8 is open.
- No flang, no SOURCES, no BUILD file.

| platform | files | raw | gzip -6 | xz -6 | zstd -19 |
|---|---|---|---|---|---|
| linux-64 | 19,567 | 359.4 MB | 87.5 MB | 57.6 MB | 61.6 MB |
| linux-aarch64 | 19,567 | 345.4 MB | 84.5 MB | 53.1 MB | 59.3 MB |
| osx-arm64 | 19,567 | 371.5 MB | 86.6 MB | 54.2 MB | 60.1 MB |
| osx-64 | 19,567 | 381.9 MB | 90.7 MB | 59.8 MB | 63.5 MB |
| win-64 | 19,574 | 378.9 MB | 94.7 MB (zip -6: 106.8 MB) | 60.3 MB | 64.3 MB |

- zig is 99 % (98.9-99.7 %) of each unix archive, and 92 % (gzip) to
  97 % (xz, zstd) of win-64's.
- On unix, make, rzig and zig's licence texts add 0.7-0.9 MB with
  gzip, and 0.2-0.3 MB with xz or zstd.
- On win-64, the binutils, rzig and the licences add 7.4 MB with gzip
  and 7.9 MB with zip. A make.exe would add 4.8 MB (gzip -6) as
  conda-forge ships it, or 0.15 MB stripped.
- xz -6 is 34-37 % smaller than gzip -6, and zstd -19 is 30-32 %
  smaller.

**xcrun without the Command Line Tools** (omicron, macOS 26.4.1).
- omicron has the CLT (26.4) and no Xcode. Removing them was not
  safe, so the real state is untested.
- Simulation: DEVELOPER_DIR pointed at an empty directory, one command
  at a time. A missing directory gives "missing DEVELOPER_DIR path"
  instead.
- `xcrun --sdk macosx --show-sdk-path` exits 1 at once. stdout is
  empty, and stderr says
  `xcrun: error: invalid DEVELOPER_DIR path (<dir>), missing xcrun at: <dir>/usr/bin/xcrun`.
- `xcode-select -p` prints the directory and exits 0.
- rzig then omits the SDK's `-F<sdk>/System/Library/Frameworks` and
  `-L<sdk>/usr/lib`, and prints nothing about it. That was the minimal
  tree's zig-cc (4868515's rzig) with the env's conda-forge zig as
  ZIG_BIN, and zig's caches in a scratch directory.
- A C hello compiles, links and runs (minos 13.0), from zig's own macOS
  headers and libSystem stubs. `zig cc` run directly behaves the same.
- A `-framework CoreFoundation` link fails: "unable to find framework
  'CoreFoundation'. searched paths: none". With the CLT, the same link
  passes.
- Not observable over ssh with the CLT present: whether a Mac that
  never had them opens the install dialog when rzig runs xcrun.

## Principles and constraints

- **The user's aim:** "a single build path that should just work
  everywhere and depend the minimum possible in OS specific or shell
  specific trickery. Allowing user to build, compile, and install
  packages from a unified toolchain."
- **Both zigs, with upstream as the reference** (PLAN.md:133-142). The
  user's words: "I want this project to keep the capability of being
  able to be built by both zig from conda-forge and upstream" and "we
  should not deviate further from supporting upstream just to satisfy
  conda-forge quirks". The standalone toolchain ships upstream zig
  (decided 2026-09-29, PLAN.md:377-379). conda-forge's zig stays the
  conda toolchain's. A conda-forge quirk gets a small, isolated
  workaround and never a design change.
- **zig is pinned by exact version** (0.16.0), never by build number
  (consolidation/PLAN.md, convention 2). Windows is MinGW
  (`-windows-gnu`) everywhere.
- **rzig decides the environment** from its own path and never reads
  `CONDA_PREFIX` (PLAN.md:120-129). rzig stays at
  `<prefix>/lib/R/bin/toolchain`.
- **The installed tree is the shipped tree.** zig build installs it,
  every check runs on it, and `package` only archives it. No sed over
  generated files and no post-link surgery (PLAN.md:112-113, 252-256).
  Both archives are file selections of that one tree.
- **Fold logic into build.zig and rzig,** not into shell steps that
  differ by OS (the simplicity review, PLAN.md:409-415).
- **Runtime libraries stay in base:** whatever a compiled package needs
  in order to load (libR, BLAS, libomp, ...). libc++ and the flang
  runtime are linked statically, so binary packages load without the
  toolchain (PLAN.md:270-277).
- **Work style.**
  - Each phase is implemented in a worktree and reviewed.
  - It is tested on linux-64 here, on osx-arm64 and osx-64 (Rosetta) on
    omicron, on win-64 on kappa, and then in CI on GitHub-hosted
    runners.
  - The user makes every commit. Docs-only commits carry `[skip ci]`.

## Design (proposal)

Each part lists the options and a recommendation, and the
recommendations fit together. The choices are collected under
"Decisions for the user".

### 1. The split and the archives

The boundary is the one conda and pip use: `R_HOME/bin/toolchain`, that
is `lib/R/bin/toolchain` (Windows `Library/lib/R/bin/toolchain`).

How the toolchain archive relates to the base:
- **a. An overlay.** The toolchain archive has the same top directory
  as the base archive and holds only
  `R-<ver>-<flavor>-zig/lib/R/bin/toolchain/...`. Extracting both in the
  same place gives the full tree.
  - rzig lands where environment.zig expects it.
  - The preflight's zig-cc test works unchanged.
  - The base is exactly what hermetic-check.sh already tests: the tree
    without that directory.
- **b. A separate toolchain directory** named by a variable
  (`R_ZIG_TOOLCHAIN_ENV`, item 4), so that one toolchain serves several
  R installs. That needs rzig in the base, or a new rule for rzig's own
  environment, and a new preflight test. This is item 4, which is marked
  "later, test carefully first".

Recommendation: a. Item 4 can come later without changing the layout
inside the toolchain directory (Design 2). Only the way its root is
found would change.

Names (working names; the final ones follow the v3 naming decision):
- base: `R-<ver>-<flavor>-<plat>.tar.gz` (Windows `.zip`), as today but
  without `R_HOME/bin/toolchain`;
- toolchain: `R-<ver>-<flavor>-<plat>-toolchain.tar.gz` (Windows
  `.zip`), with the same top directory;
- each with its `.sha256`.

How the pair is tied together:
- They share a name and are made from the same tree in the same run.
- A file `R_HOME/bin/toolchain/BUILD` records the base it belongs to
  (R version, flavor, platform, commit).
- rzig is built from the target alone (build.zig:526,
  `rzig_build.add(b, ..., target, ...)`). It is byte-identical across
  the flavors of one platform: measured on linux-64 slim and minimal,
  and on osx-arm64 slim, full and minimal (2026-10-06, Phase 0
  measurements). Today the toolchain directories of one platform still
  differ by minimal's make. With make in every unix tree (Design 4a)
  they would be the same, so one toolchain archive per platform would
  be possible later. It is not needed now.

package-standalone.sh makes both archives from the one tree:
- unix: tar once with an exclude of that directory, once with only that
  directory;
- Windows: zip `-x`, then a second zip.

No new tree is built, and no file is added at packaging time.

### 2. How the toolchain is found at run time

One rule, in rzig: rzig's own directory, `<prefix>/lib/R/bin/toolchain`,
is the toolchain root. The toolchain's programs sit at fixed places
under it:
- `zig/zig` (Windows `zig/zig.exe`): upstream zig as its release
  unpacks. zig finds its `lib/` next to itself.
- `flang/bin/flang` (Windows `flang/bin/flang.exe`) and
  `flang/lib/clang/23/...`, in flang-zig's own relative layout without
  Windows' `Library/` prefix, and with no flang.cfg, if Fortran ships
  (Design 5).
- `make` on unix, which R reads through Renviron's `MAKE`.
- `usr/bin/` on Windows: make.exe, sh.exe and the tools (Design 7).

rzig's lookup order becomes:
- **zig:**
  1. `ZIG_BIN`, the explicit override, as today;
  2. `<root>/zig/zig`;
  3. PATH;
  4. `python3 -m ziglang`.

  When none is found, the message names zig and `R_ZIG_TOOLCHAIN_HINT`
  instead of failing on python3.
- **flang:** `<root>/flang/bin/flang`, then PATH.

In a conda env and in the wheel the root has no `zig/` or `flang/`, so
lookups behave as today: PATH, or the wheel's ZIG_BIN. A bundled zig
wins over PATH on purpose: it is the zig this R was tested with,
whatever zig the user has on PATH.

Alternatives:
- A Renviron default `ZIG_BIN=${ZIG_BIN-${R_HOME}/bin/toolchain/zig/zig}`
  written by build.zig, which is the wheel's pattern. Its drawbacks:
  etc/Renviron.site is skipped under `--vanilla`; a base file would name
  a toolchain file; and a compile started outside R would not see it.
- PATH only. The user would have to edit PATH, which does not just work.

Recommendation: the rule in rzig. It can be unit-tested and is the same
on every OS. Item 4 would later add only another way to name the root.

Where the bundled zig sits also matters for one more reason.
conda-forge zig's shared-libc++ probe looks at `<zig lib dir>/../../lib`.
Under `bin/toolchain/zig/lib` that resolves to `bin/toolchain/lib`, which
does not exist. The libc++ mirror never fires for the bundled zig, which
is upstream zig and has no such probe anyway.

### 3. zig

What the standalone toolchain carries was decided on 2026-09-29
(PLAN.md:377-379): "the official ziglang.org release (the same upstream
build as PyPI `ziglang`), checksum-pinned, in the standalone toolchain
download". Still open: which artifact, and where it enters the tree.

The artifact:
- **a. PyPI's ziglang 0.16.0 wheel, pinned as in fetch-zig.sh.**
  - It is byte-identical to ziglang.org's release.
  - Its pin list is already tested on all five platforms.
  - It is one format (zip) unpacked with one tool, from PyPI's CDN,
    which suits automated downloads.
  - It is the zig the wheel's users run.
  - Its `ziglang-0.16.0.dist-info/licenses/` holds the libc and libc++
    notices the toolchain must ship.
- **b. ziglang.org's tar.xz or zip,** pinned by sha256 (and minisign)
  and fetched from a community mirror, as ziglang.org asks. That makes a
  second download path.

Recommendation: a. Record it as meeting the 2026-09-29 decision.

Where zig enters the tree (one place):
- **a. build.zig installs it.** A new option `-Dbundle-zig=<dir>` takes
  fetch-zig's unpacked `ziglang/` and installs it into
  `R_HOME/bin/toolchain/zig/`. That is one install-directory step, plus
  the licences (Design 9). zig-build.sh runs fetch-zig and passes the
  option for every build that is not the conda build. The installed tree
  is then the shipped tree, and every check sees the bundled zig.
- **b. Only in packaging runs,** through an opt-in variable set in CI.
  Dev trees and shipped trees would then differ.
- **c. package-standalone.sh adds it to the toolchain archive.** The
  archive would hold a file that no check saw, and `package` would no
  longer only archive.
- **d. Not bundled; rzig downloads it at first use.** Zig 0.16's std has
  http, sha256 and zip, and uv downloads Python the same way. The
  archive would be small, but the first compile would need the network,
  there would be no offline install, and it goes against the 2026-09-29
  decision.

Recommendation: a.

What a means elsewhere:
- **Dev trees grow.** Every non-conda tree, the dev tree included,
  carries zig: 343-380 MB and 19,546 files per platform (390 MiB on
  disk on linux-64; Phase 0 measurements).
- **The pipeline keeps the zig that built R.** contract, check and
  verify-package's existing compiles must keep compiling with the zig
  that built R, as F4 set up. So env.sh exports `ZIG_BIN=$ZIG` always,
  not only when ZIG_BIN was set. Otherwise rzig would switch dev
  compiles to the bundled zig. New checks that unset ZIG_BIN exercise
  the bundled zig (see Verification).
- **The wheel excludes it.** make-wheel.py excludes
  `lib/R/bin/toolchain/zig/`, since the ziglang distribution provides zig
  to the wheel. PyPI's default limit is also 100 MB per file.
- **conda is unchanged.** The conda build's prefix is the env, and no
  option is passed.
- **hermetic-check.sh** copies the tree without `bin/toolchain`, instead
  of copying it and then deleting it. That is about 360 MB and 19,500
  files less to copy.
- **verify-tree.sh** treats `bin/toolchain/zig/**` as third-party in its
  build-path scan, like the vendored libraries. It also checks that
  `zig/zig version` prints 0.16.0.

Which zig builds the released standalone R (decision 9):
- R built with conda-forge's zig (what build.yaml runs) and packages
  compiled with the bundled upstream zig is the mix the wheel already
  ships. The wheel covers it only for minimal: no OpenMP and no Fortran.
- Building the released archives with upstream zig (upstream-zig.yaml's
  legs) gives a standalone distribution with one zig, the reference one.

Recommendation: build releases with upstream zig once a release job
exists. This PR tests the mixed case for slim with OpenMP.

Pin 0.16.0 until conda-forge also has 0.17, so that both zigs stay at
one version (flang-pixi docs/17). How the project moves to 0.17 is
decision 18 ("The zig 0.17 wave").

A prerequisite for the toolchain's compilers: baseline CPU code on
Windows. rzig's Windows package compiles target the build machine's CPU
today ("Other facts": no `-target`, so zig picks the native CPU;
"skylake" on kappa). Each package built on one machine and loaded on an
older CPU can then fail with an illegal instruction. That is true with
conda-forge's zig and with upstream zig, so a bundled zig changes
nothing about it. It already applies to r-zig-toolchain on win-64 and
to the Windows zip with sh and make from PATH. The fix, rzig passing
`-mcpu=baseline`, is pending the user's go and is not part of this plan.
It should land at the latest before the toolchain archive ships
compilers to Windows users (phase 4), and before any Windows binary
package is built for others.

### 4. make (unix)

- **a. Ship conda-forge's GNU make in every unix toolchain.**
  - build.zig installs it into `bin/toolchain/make` for every non-conda
    unix tree. Today that happens for minimal only (build.zig:910-917).
  - finalRenviron writes `R_ZIG_MAKE=${R_HOME}/bin/toolchain/make` and
    `MAKE=${MAKE-${R_ZIG_MAKE}}` for those trees. Today that is also
    minimal only (build.zig:3660-3664).
  - Why: on a Mac without the Command Line Tools, `/usr/bin/make` is a
    stub that offers to install them, and many linux containers have no
    make.
  - Without the toolchain, `MAKE` names a missing file. Patch 0006 then
    installs packages one at a time, and patch 0010 says make is
    missing. Both handle an absolute `MAKE`, because patch 0002's
    Sys.which checks a path that contains a slash directly.
- **b. The host's make for slim and full** (today). This fails on stock
  macOS and in slim containers.
- **c. GNU make 4.4.1 built from source by build.zig with zig,** for all
  five platforms including Windows. That gives one make with no
  conda-forge provenance and no build-path strings (conda-forge's make
  names /home/conda/feedstock_root/... and /Users/runner/...). It is
  more work: a later option if a causes trouble.

Recommendation: a. make stays under verify-tree's glibc 2.28 ceiling for
the toolchain directory (scripts/verify-tree.sh:448-466).

### 5. Fortran

The record leaves this open: "a Fortran compiler or not"
(PLAN.md:1948-1951). The recipe quotes CRAN's rule that the Fortran
compiler must be the one R was built with.

#### What flang-pixi measured (2026-10-06)

flang-pixi tested the trimmed set this plan proposed, from the published
packages, on linux-64, osx-arm64, osx-64 (under Rosetta) and win-64
(flang-pixi docs/19 §2-§5; handoff §8). These parts of the earlier
prototype are done:
- **The set.**
  - `bin/flang-23` and the `flang` link (Windows
    `Library/bin/flang.exe`);
  - the intrinsic and OpenMP modules (15 intrinsic `.mod` files,
    `omp_lib.mod`, `omp_lib_kinds.mod` and `omp_lib.h`) under
    `lib/clang/23/finclude/flang/<conda triple>/`. On Windows, keep both
    directories flang-rt ships: `x86_64-w64-mingw32` and
    `x86_64-w64-windows-gnu`, the driver's default;
  - `lib/clang/23/lib/<rt dir>/libflang_rt.runtime.a`, one copy. The
    win-64 package ships the runtime under five names.

  As the carving script writes it, that is 24 files on unix and 40 on
  Windows. The count includes the one-line flang.cfg,
  STANDALONE-ORIGIN.txt and, on unix, the `lib/libflang_rt.runtime.a`
  symlink, none of which this plan needs. flang-pixi's
  docs/19-file-lists/ lists every file of every package.
- **It compiles on its own.** With nothing else on PATH (`env -i`; on
  Windows, PATH set to the set's bin), these compile on all four:
  hello, a derived-type module, `use omp_lib` and OpenMP directives.
  zig links the objects with the runtime archive and the programs run,
  OpenMP on two threads against conda-forge's libomp. No lld-zig, no
  sysroot, no SDK path and no Windows CRT snapshot.
- **It loads only system libraries.** The flang executables need only:
  - on linux, glibc's libraries;
  - on macOS, libSystem (minos 11.0);
  - on Windows, OS DLLs and api-ms-win-crt-*.

  Nothing comes from conda (handoff §7, flang-pixi docs/18 §6.1).
- **Sizes** (one tar of the set; the driver binary is 136-196 MB of the
  raw size):

  | subdir | raw | gzip -9 | zstd -19 | xz -9 |
  |---|---|---|---|---|
  | linux-64 | 210.0 MB | 62.2 MB | 43.9 MB | 39.3 MB |
  | linux-aarch64 | 195.9 MB | 58.9 MB | 41.3 MB | 34.7 MB |
  | osx-arm64 | 143.9 MB | 45.1 MB | 30.5 MB | 25.9 MB |
  | osx-64 | 157.3 MB | 50.3 MB | 35.0 MB | 31.8 MB |
  | win-64 | 190.1 MB | 58.0 MB | 40.1 MB | 35.6 MB |

  Our 2026-10-05 figure (279 MB raw, 63 MB zstd on linux-64) included
  lld.
- **No flang.cfg.**
  - Linux and Windows compile with no cfg at all, because flang-rt
    ships the module directory under the driver's default triple.
  - macOS needs one line,
    `-fintrinsic-modules-path <root>/lib/clang/23/finclude/flang/<conda triple>`.
    The driver's default triple there carries the host's macOS version
    (`arm64-apple-macosx26.0.0`), so it matches no shipped directory.
  - Passing that flag from zig-fc removes the cfg on every OS (verified
    with `use omp_lib`).
  - The rest of the published cfg (`--sysroot`, `-fuse-ld=lld`,
    `--rtlib=compiler-rt`, `-Wl,-L`, `-rpath`, `-rpath-link`) serves the
    driver's own link, which the standalone tree does not use.
- **The macOS floor.** Unless given `-mmacos-version-min=<floor>`,
  flang stamps its objects with the host SDK's version. zig-fc already
  passes `-mmacosx-version-min=13.0` before the caller's arguments
  (fortran.zig:58, floors.zig:17-22). Both spellings give the same
  result (handoff §6).
- **The link line.**
  - unix: the runtime archive and `-lm`, plus `-lomp` against our
    libomp for `-fopenmp`.
  - Windows: the runtime archive plus our libomp import library
    (`libomp.lib` works, as does `libomp.dll.a`). Nothing from the CRT
    snapshot, and no libatomic. flang-rt's `libomp.dll.a` and
    `libatomic.a` shims exist only for the driver's `-latomic -lomp`.
  - A Windows Fortran DLL linked by zig exports only its own symbols:
    24 in their test, and no runtime symbol. lld's MinGW auto-export
    skips archive members.

#### What is still ours to prove

- **zig-fc links executables through zig.**
  - Today only a shared link of objects goes through zig. A call that
    compiles sources and links them, or that links objects into an
    executable, runs flang's driver (fortran.zig:5-29, F3c: "a mixed
    call stays flang's").
  - configure's `$FC` probes are such calls, and the driver's link
    fails outside conda ("Other facts").
  - The change: every link goes through zig. A call with sources and a
    link becomes `flang -c` for each source, into a temporary object,
    and then the zig link with the runtime archive, as the shared link
    already does. This reverses F3c's rule, whose reason was to avoid
    exactly this splitting.
  - Proposed: one rule everywhere, conda envs included, not a branch
    for the standalone tree.
  - flang-pixi linked by hand. zig-fc doing it from one call, on the
    four OSes, is ours to prove.
- **zig-fc passes `-fintrinsic-modules-path` on every compile,** so that
  no compile needs a flang.cfg.
  - The directory is found from flang's own location:
    `<flang's dir>/../lib/clang/<major>/finclude/flang/<conda triple>`.
  - In a conda env the env's flang.cfg names the same directory. That
    the flag given twice does no harm is still to be checked.
  - The prototype settles where the triple comes from: a constant per
    target, or the one directory under `finclude/flang/` that holds
    `omp_lib.mod`.
- **rzig finds the runtime in the new layout.**
  - flang_rt.zig asks flang for `-print-resource-dir` and looks under
    its `lib/*/`. In `bin/toolchain/flang/` the resource dir is
    `lib/clang/23`, so the lookup should work unchanged.
  - On Windows, the prototype confirms that flang still finds its
    resource dir after `Library/` is dropped.
- **The R-side checks.** These run with the standalone tree alone,
  ZIG_BIN unset and no flang on PATH (Verification):
  - a Fortran package;
  - USE_FC_TO_LINK;
  - `use omp_lib` running on two threads;
  - a configure that probes `$FC`.

#### Where build.zig gets the files (decision 17)

Both options put the same files under `bin/toolchain/flang/`. They
differ in where build.zig reads them from. flang-pixi will not publish
a second artifact. If one is wanted later, it offers GitHub release
assets carved from the published `.conda` files (handoff §8).

- **a. Run flang-pixi's carving script on the published packages.**
  build.zig installs the output of scripts/carve-fortran-standalone.py
  run on the two `.conda` files. The script is pinned to a flang-pixi
  commit.
  - flang-pixi maintains the file list. A change to the set (flang-zig
    build 6's `bin/flang-compile.cfg`, a new LLVM major) arrives with
    the script.
  - The script writes STANDALONE-ORIGIN.txt with the package file names
    and build numbers.
  - Costs:
    - **Python.** It needs Python ≥ 3.14 (`compression.zstd`) or the
      zstandard package. R's build environments declare no Python.
      default, full, openblas and full-openblas get Python 3.14
      transitively (on linux-64 through glib), and minimal's lock has
      none (pixi.lock). In practice it would be
      `pixi exec --spec "python>=3.14"`: a second language and a
      download during the build.
    - **A second download.** The rattler cache keeps extracted
      packages, not the `.conda` files. So the build downloads both
      packages again, by the URL and sha256 in pixi.lock, and must keep
      them equal to what the env installed.
    - **Two pins in step:** the flang-pixi commit and the packages. As
      of 2026-10-06 the script and docs/19 are not committed in
      flang-pixi, so there is no commit to pin yet.
    - **Memory.** It holds all of flang-zig in memory, the decompressed
      tar and then every member's bytes (members(), lines 34-48): more
      than the installed size, which docs/19 §1 gives as 1,023 MB on
      linux-64 and 1.7 GB on win-64.
- **b. Copy the documented set from the build env's installed flang-zig
  and flang-rt-zig,** in build.zig, and write our own provenance from
  conda-meta.
  - build.zig already finds both. It stops without a flang in
    `$BUILD_PREFIX` or `$CONDA` (build.zig:462-478), and findFlangRt
    (build.zig:2294) finds the runtime's directory.
  - It already installs third-party binaries this way: make for minimal
    (build.zig:910-917) and the Windows binutils
    (build.zig:1744-1764).
  - The list is short and fixed: the driver, the module directories,
    and one runtime archive.
  - The driver goes in once, as `flang/bin/flang` (`flang.exe`).
    Proposed: on unix that is a copy of flang-23, with no second name.
    zig 0.16's install-file step copies a symlink's target
    (`Io.Dir.updateFile`, std/Build/Step.zig:525-531), and its
    install-directory step skips symlinks (InstallDir.zig:88-105). So
    installing both `flang-23` and the `flang` link would store the
    196 MB driver twice. The Windows package ships only flang.exe. The
    prototype confirms that the driver behaves the same under the one
    name.
  - conda-meta records the exact packages installed:
    `conda-meta/flang-zig-*.json` and `flang-rt-zig-*.json` hold the
    name, version, build, build number, URL and sha256. On linux-64,
    for example, that is `flang-rt-zig 23.1.1 zig_501841f_9`, its
    prefix.dev URL and its sha256. Their `paths_data` also lists every
    installed file with its own sha256, so verify-tree can check each
    copy against its package.
  - build.zig writes those into `bin/toolchain/SOURCES` (Design 9).
    That is what STANDALONE-ORIGIN.txt records, plus the package
    checksums.
  - The flang that ships is, file for file, the flang that compiled R's
    own Fortran. CRAN's rule then holds by construction, not by keeping
    two pins equal.
  - Costs:
    - We follow docs/19's list by hand, and a change on flang-pixi's
      side reaches us when we read it. The verification catches a
      missing file, because the standalone checks compile derived types
      and `use omp_lib` with nothing else on PATH.
    - On zig 0.17, build.zig must register the conda-meta files it
      reads (configure caching, flang-pixi docs/17 §4).

How the two compare against this plan's principles:

| Principle | a | b |
|---|---|---|
| Fold into build.zig, little shell or OS trickery | a Python step and a download outside build.zig | one install step in build.zig, the same on every OS |
| The installed tree is the shipped tree | yes: the output goes into the tree before every check | yes |
| Reproducibility | the package pins again, plus a script commit | pixi.lock, which already pins both packages by URL and sha256 |
| Both zigs | does not depend on zig | does not depend on zig. The upstream-zig legs (ZIG_BIN from fetch-zig) use the same env, so they ship the same flang |
| No Python in R's build env | needs one | needs none |
| Provenance | STANDALONE-ORIGIN.txt: the package file names and build strings | conda-meta: name, version, build, URL and sha256 of each package, and each file's sha256 |

Recommendation: b. In phase 7's prototype, run flang-pixi's script
once as a cross-check: carve the same two packages and compare the
driver, the modules and the runtime archive, by sha256, with what
build.zig installs (the carved flang.cfg, `lib/` symlink and origin
file aside).

#### Windows FLIBS: does the runtime still need -lc++? (checked 2026-10-06)

Where libc++ is linked today:
- Windows' FLIBS is `-lflang_rt.runtime -lc++` (build.zig:1816-1824),
  and rzig's flibs says the same (fortran.zig:73-77).
- linkFortranRt links zig's libc++ into R's own libraries on macOS and
  Windows (build.zig:2698-2702).

The comments give the reason: the runtime is C++, and "only Linux's
archive is libc++-free". flang-pixi's Windows link line has no libc++.
So I checked the archive itself:
- **The package.** pixi.lock's win-64
  `flang-rt-zig-23.1.1-zig_03d85fb_4.conda`, downloaded from prefix.dev.
  The local rattler cache holds only linux-64's `_4` and `_9`. Its
  sha256, cd8c5928…17b5, matches pixi.lock:13219.
- **The archive.**
  `Library/lib/clang/23/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a`:
  14,320,302 B, 88 pe-x86-64 members (87 `.cpp.obj` and one `.c.obj`,
  complex-reduction). `.static.a` is byte-identical to it.
- **Its undefined symbols.** GNU nm 2.42 (which reads pe-x86-64) and
  llvm-nm 23 agree: 494 distinct undefined names, 131 of which no
  member of the archive defines. Those 131 are:
  - the C library: malloc, free, memcpy, snprintf, strtol, qsort,
    open/read/write/lseek64, and the math and fenv functions;
  - Win32 and UCRT imports through `__imp_`: CreateProcessW,
    GetLastError, VirtualAlloc, the critical-section calls, `_errno`,
    `__acrt_iob_func`;
  - compiler-rt builtins: `__divdc3`, `__muldc3`, `__mulxc3`,
    `__fixdfti`, `__floattidf`, `__modti3`, `__udivti3`,
    `___chkstk_ms`.
- **No C++ runtime symbol among them.** None of the 131 is a mangled
  (`_Z`) name. Specifically:
  - no operator new or delete (`_Znw*`, `_Zna*`, `_Zdl*`, `_Zda*`);
  - no `__cxa_*`, `__gxx_personality_*` or `_Unwind_*`;
  - no `std::` name (`_ZSt*`, `_ZNSt*`), no `__cxxabiv1` type info and
    no `__dynamic_cast`.

  The `std::__1` names that do occur are header templates (std::variant
  visitation, std::optional::emplace, `__throw_bad_variant_access`, ABI
  tag `nn210100`), defined inside the archive itself. Static destructors
  use `atexit`, not `__cxa_atexit`. No member carries a `-defaultlib`
  directive: the `.drectve` sections hold only `-exclude-symbols`.
- **A link test, cross-compiled here on linux-64.**
  - The objects: from the default env's flang-zig with
    `--target=x86_64-w64-windows-gnu`. One is a main program; the other
    is a subroutine with list-directed and internal formatted I/O.
  - The link: the env's zig 0.16.0,
    `zig cc -target x86_64-windows-gnu -mcpu=baseline`, with the
    archive alone.
  - An executable and a `-shared` DLL both link without `-lc++`. They
    import only KERNEL32 and api-ms-win-crt-*.
  - With `-lc++` added, the DLL has the same size (1,209,344 B), the
    same imports and the same 9 exports: libc++ adds nothing.
  - Not run, since there is no Windows here.
- **The other platforms, for comparison.** The build 9 archives of
  osx-arm64 (`zig_eb63498_9`, sha256 958da2be… as pixi.lock:13183) and
  linux-64 (`zig_501841f_9`), checked the same way with llvm-nm,
  reference only `__cxa_atexit` and `__dso_handle` from the C++ ABI. The
  C library (libSystem, glibc) and the linker provide both. Handoff §1
  found only `__cxa_atexit` on Linux's archives.

Conclusion: the win-64 runtime of build 4 needs no libc++ at link time.
These are all no-ops for the runtime:
- the `-lc++` in Windows FLIBS;
- the `-lc++` in rzig's flibs;
- linkFortranRt's `link_libcpp` on Windows, and on macOS with build 9.

The comments' premise is out of date. Handoff §1 measured only Linux,
and for Windows wrote "*expect* Windows to behave like macOS". Both
`link_libcpp` settings date from Phase 2, with earlier flang-rt builds
(consolidation/PHASE2_FORTRAN.md). Nothing changes now. Proposed for
phase 7:
- drop the Windows ones after a kappa run builds and loads a Fortran
  package without them, and macOS's `link_libcpp` after an omicron run
  builds R without it;
- repeat this symbol check on flang-rt-zig build 10, which a different
  zig builds, before flang-pixi publishes it ("The zig 0.17 wave").

#### Options and recommendation

- **a. None** (today). zig-fc's message tells the user to install LLVM
  flang. The user would need flang 23.1.1 built the way flang-zig is. In
  practice Fortran packages do not compile from the standalone tree.
- **b. The compile set inside the toolchain archive,** as measured
  above. It adds 30.5-43.9 MB with zstd (45-62 MB with gzip). It is the
  flang R was built with, so CRAN's rule holds by construction. rzig
  finds it beside itself (Design 2). What remains is the zig-fc work
  above.
- **c. All of flang-zig, lld-zig and flang-rt-zig** (plus the sysroot on
  linux). That is about 0.9-2.1 GB installed per platform (osx-arm64 to
  win-64, flang-pixi docs/19 §1). Not proposed.
- **d. b as a separate, optional `-fortran` archive.** C and C++ users
  would skip 30-44 MB (zstd), at the cost of a third download.

Recommendation: b, inside the one toolchain archive, as its own phase
after zig and make. The open risk was lld and the sysroot, and that is
gone. What is left is our own zig-fc work.
- If zig-fc's executable links fail on an OS, that OS ships without
  Fortran, and zig-fc's message says what to do.
- The wheel stays without Fortran unless decided otherwise:
  make-wheel.py excludes `bin/toolchain/flang/`.

### 6. OpenMP files

- **a. Keep them in base.** That means omp.h, ompx.h, omp-tools.h and
  ompt.h in `<prefix>/include`, and libomp.lib on Windows.
  - They are about 330 KB.
  - The split stays one directory in all three distributions.
  - It matches conda, where the base's llvm-openmp run dependency
    provides the same files.
  - rzig's `openmp()` rule (an environment's include/omp.h) is
    unchanged.
- **b. Move them to the toolchain archive,** as installOpenMP's comment
  and F1.5 intended. The split becomes a directory plus files outside
  it, and the standalone distribution differs from conda.
- **c. Move them under `bin/toolchain/`** and teach rzig a second
  include root. The split is one directory again, but rzig's OpenMP rule
  changes for one distribution only.

Recommendation: a. It supersedes installOpenMP's "Phase T's standalone
toolchain archive takes the headers and the import library over"; that
comment and PLAN.md:400-403 get updated. libomp itself stays in base
whatever is chosen.

### 7. Windows

What the Windows toolchain directory holds today: rzig (gcc.exe,
g++.exe, zig-fc.exe, zig-cc, zig-cxx) and the binutils.
- The binutils import zstd.dll, which lands in `R_HOME/bin/x64`
  (vendor-libs.sh walks every PE in the tree).
- R.dll imports zstd.dll itself, and so does tiff.dll (confirmed on
  kappa's tree, 2026-10-06, Phase 0 measurements). So zstd.dll stays in
  base under any split.
- With Design 3 and 5, zig.exe and flang join the directory.

What is missing is the userland that compiling needs:
- make and sh: install.R's `make`, and `sh configure.win`;
- rm, cp, mkdir, sed, cat, echo, sort, basename and test
  (Makeconf.win:75-94, winshlib.mk).

This is item 2's blocker too, and one choice serves both.

Options (PLAN.md:2404-2431, plus the readers' findings):
- **a. busybox-w32 plus a native GNU make.**
  - busybox64u.exe is 675,840 B, imports system DLLs only, is
    GPL-2.0-only, and comes with a published SHA256SUM and source
    tarball. It would serve as sh.exe, and as one .exe for each applet
    that make runs directly: copies in a zip, or tiny launchers in the
    style of rzig.
  - The GNU make: conda-forge's win-64 make.exe (a native MinGW UCRT
    build that imports system DLLs only; 17 MB unstripped), or one built
    by zig (Design 4c).
  - About 1-2 MB before the per-applet copies. w64devkit ships exactly
    this pair.
  - There is no msys-2.0.dll that could clash with a user's Rtools or
    Git for Windows.
  - Risks: configure.win scripts that need bash, and it is untested with
    R's makefiles.
- **b. The MSYS2 set from conda's m2 packages:** bash, make, coreutils,
  sed, grep, gawk, which, findutils, msys-2.0.dll and their
  dependencies.
  - r-zig-toolchain's conda package and Rtools use it.
  - About 16 MB compressed, and known to work with R's makefiles.
  - Risks: Cygwin FAQ 4.20 says two msys-2.0.dll installations in one
    process tree "may or may not work"; and the process-spawn hangs seen
    on windows-latest.
- **c. Require Rtools45** (a 461 MB installer) and point R at its
  usr/bin. Nothing to redistribute, but the user then has a second
  toolchain on the machine.
- **d. Defer the userland.** The Windows toolchain archive holds rzig,
  the binutils, zig (and flang), and still expects sh and make on PATH,
  as the Windows zip does today.

Recommendation:
- Use d until a prototype on kappa chooses between a and b, with b as
  the fallback.
- Then put the chosen userland in `bin/toolchain/usr/bin/`.
- R finds it through R's own hook. For a non-conda Windows tree,
  build.zig writes etc/Rcmd_environ with the installer-build PATH line
  active:
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`.
  - Every `R CMD` then has make and sh, including the
    `R CMD INSTALL` that install.packages() runs.
  - `R_CUSTOM_TOOLS_PATH` remains the user's override, as in R.
- The prototype also settles whether Rprofile.windows needs the same
  line, for `system("make")` from an R session and for pkgbuild's
  checks.

What the prototype runs:
- R's own Makeconf.win and winshlib.mk on a C, a C++, a Fortran and an
  OpenMP package (the contract set);
- packages with configure.win or configure.ucrt (pak, data.table,
  glue);
- one package that uses pkg-config;
- a scan of CRAN's configure.win and configure.ucrt files for bash-only
  syntax.

Separate from the userland: on Windows, `R CMD config` without the
toolchain fails with whatever not finding `sh` prints. A clean message
needs a check before rcmdfn.c runs `sh` (phase 8).

Gaps that remain on Windows with upstream zig:
- `-lsynchronization` (Rust packages) does not link with upstream zig
  0.16.0 (What remains 8);
- Tcl's TCL_VERSION is 86, not conda's 86t (What remains 5);
- windows.zig still looks for gfortran (What remains 10);
- package compiles target the build machine's CPU until rzig passes
  `-mcpu=baseline`, with either zig (Design 3's prerequisite, pending
  the user's go).

### 8. The preflight, the hint and R CMD config

- **The preflight is unchanged.** rzig stays in the toolchain archive,
  so the test for `bin/toolchain/zig-cc` is still the right one.
- **A standalone hint.** zig-build.sh passes `-Dtoolchain-hint` for
  every non-conda build. The hint names this flavor's and platform's
  toolchain archive, for example: "extract
  R-4.6.1-slim-linux-64-toolchain.tar.gz where you extracted this R".
  - The platform name moves from package-standalone.sh into env.sh, so
    the hint and the archive name come from one place.
  - It includes a URL only once there is a release page (decision 10).
- **The wheel's hint.** make-wheel.py must replace the standalone hint
  line. Today `renviron_hint` keeps an existing `R_ZIG_TOOLCHAIN_HINT`
  (make-wheel.py:244-251), which would leave the standalone text in the
  wheel.
- **The preflight's Makeconf-CC fallback** serves an unstaged tree that
  no longer exists; F1.4 said it would become unneeded
  (PLAN.md:452-453). Removing it simplifies patch 0009. It changes
  r-zig-slim's install.R, so it goes with the build-number bump
  (decisions 12 and 13).
- **zig-fc's no-flang message** changes with Design 5 (today it says
  "the standalone tree brings none").

### 9. Licences and sources

The toolchain directory gets `LICENSES/` and `SOURCES`. They sit inside
`bin/toolchain`, so the split stays one directory.

| Component | What goes in LICENSES/ and SOURCES |
|---|---|
| zig | its LICENSE (MIT), plus the wheel's dist-info licences: glibc, musl, mingw, wasi, freebsd, libc++, libc++abi, libunwind |
| GNU make (GPL-3.0-or-later) | the licence text; in SOURCES, the exact upstream source tarball and conda-forge feedstock version, with sha256 |
| the Windows binutils (GPL-3.0-only) | the same |
| the Windows userland (busybox: GPL-2.0-only; MSYS2: GPL/LGPL) | the same |
| flang and flang-rt (Apache-2.0 WITH LLVM-exception; no lld, Design 5) | the LICENSE.TXT from the packages' info/licenses; in SOURCES, the two packages' name, version, build, URL and sha256 from conda-meta (decision 17) |

- build.zig installs these from files kept in the repository, since
  licence texts do not change per build, plus the zig dist-info it
  unpacks.
- What the GPLs require:
  - GPLv3 §6(d) allows the source on another server, with clear
    directions next to the binary. The distributor stays responsible for
    keeping it available.
  - GPLv2 §3 wants the source offered "from the same place", or a
    written offer.
- Mirroring the GPL source tarballs next to the archives belongs to the
  publishing step (decision 10).
- The same LICENSES/ and SOURCES also cover the make in the
  r-zig-toolchain wheel, which is the same directory.
- The base's vendored libraries (OpenSSL, curl, ICU, ...) are the wheel
  work's open prerequisite, not this PR's.

### 10. Sizes (the toolchain measured in phase 0, the archives in phases 2-4)

What is measured: the toolchain directory without flang, staged per
platform on 2026-10-06 ("Phase 0 measurements": rzig, make on unix, the
binutils on win-64, upstream zig and its licence texts).

What is estimated: the flang column and the sums.
- The flang column is flang-pixi's set (docs/19 §2) at gzip -9, xz -9
  and zstd -19.
- A sum adds two separately compressed streams. One stream would come
  out a little smaller, and gzip/xz at -6 a little larger.

| platform | toolchain, measured: gzip -6 / xz -6 / zstd -19 | flang set: gzip -9 / xz -9 / zstd -19 | sum: gzip / xz / zstd |
|---|---|---|---|
| linux-64 | 87.5 / 57.6 / 61.6 MB | 62.2 / 39.3 / 43.9 MB | about 150 / 97 / 106 MB |
| linux-aarch64 | 84.5 / 53.1 / 59.3 MB | 58.9 / 34.7 / 41.3 MB | about 143 / 88 / 101 MB |
| osx-arm64 | 86.6 / 54.2 / 60.1 MB | 45.1 / 25.9 / 30.5 MB | about 132 / 80 / 91 MB |
| osx-64 | 90.7 / 59.8 / 63.5 MB | 50.3 / 31.8 / 35.0 MB | about 141 / 92 / 99 MB |
| win-64 (no make or userland) | 94.7 (zip -6: 106.8) / 60.3 / 64.3 MB | 58.0 / 35.6 / 40.1 MB | about 153 (zip about 165) / 96 / 104 MB |

- The base: linux-64 slim's archive of 2026-10-03 is 73,768,677 B.
  Its toolchain directory is 0.74 MB with gzip -6, so the base would
  be about 73 MB (not measured as an archive).
- The flang set adds 30.5-43.9 MB with zstd, or 45-62 MB with gzip
  (Design 5's table). It does not add 88 MB.
- gzip is what the base uses, and every unix tar reads it.
- xz would save 34-37 % on the toolchain (linux-64: 57.6 MB against
  87.5 MB), but GNU tar needs the xz program for it. zstd saves 30-32 %,
  and GNU tar needs the zstd program for it.

Recommendation: gzip. Decide again if phase 4's measurement shows the
toolchain with flang above about 150 MB (decision 11). With gzip,
linux-64 is estimated at about that threshold, so decision 11 is likely
to come back after phase 7.

### 11. The recipe's host which/sed/grep cleanup

Why they were added (the comment at recipe/recipe.yaml:196-223):
- build.zig baked `$CONDA_PREFIX/bin/which` into Sys.which (`@WHICH@`)
  and `$PREFIX/bin/sed` into bin/R's `SED=`;
- grep was added for GREP, EGREP and FGREP;
- the comment also cites stage.sh, retired in 182d313.

Why none of that holds now:
- build.zig turns every `@ZR_CONDA@/bin/<tool>` into the bare name
  (build.zig:2840-2844). So `WHICH`, `SED` and `GREP` are `which`, `sed`
  and `grep`. subst.txt (lines 222-224 and 285-286) still records the
  old values, but they are mapped, not used.
- Patch 0002 replaces Sys.which with a PATH scan in R. `@WHICH@` no
  longer appears in system.unix.R, so build.zig's mkRbase substitution
  (build.zig:3416-3422) is dead code.
- Patches 0007 and 0008 make bin/R and Rcmd sed-free. GREP appears in no
  installed template.
- recipe/build.sh sets `CONDA_PREFIX=$PREFIX`, and env.sh puts
  `$CONDA_PREFIX/bin:$BUILD_PREFIX/bin:/usr/bin:/bin` on PATH. The
  staging output's unix build requirements already list sed, grep and
  which (recipe.yaml:149-156).

The change:
- delete the `if: unix` host block (recipe.yaml:224-228) and its
  comment;
- delete mkRbase's `@WHICH@` substitution;
- correct verify-tree.sh's stale comment ("nm/realpath/sed/... for
  bin/libtool and javareconf", verify-tree.sh:455-461);
- correct the PLAN.md tool-table line "Vendored in the standalone tree
  today" (PLAN.md:321-324);
- optional, if a conda-package run proves it: drop `which` from the
  build requirements, since no script calls it;
- not touched: subst.txt (12 configs, and no output change).

How to prove nothing changed:
- run `pixi run -e pkg conda-package` on all five platforms;
- compare both packages' file lists with build 4's, plus the contents
  of etc/ and of the base package's R code;
- grep the extracted packages for `/bin/which`, `/bin/sed` and
  `/bin/grep`.

Since neither package changes, the cleanup needs no build-number bump
of its own.

Proposed order: do this first, before the split, so that the comparison
with build 4 is clean. The item lists it second, but it does not depend
on the split.

#### Phase 1 record (2026-10-06, linux-64)

Done in the worktree (not committed; the build number stays 4):
- recipe.yaml: the `if: unix` host block and its comment are deleted,
  and so is `which` in the staging build requirements (below).
- build.zig: mkRbase's `@WHICH@` replace is deleted, and `all_r` is
  now `const`. The patched R sources still name `@WHICH@` only in
  share/make/basepkg.mk and base's Makefile.in, which build.zig does not
  read.
- verify-tree.sh's glibc comment now says what bin/toolchain holds: rzig,
  and minimal's make (GLIBC_2.17). The 2.28 case is kept as history.
- PLAN.md (feat-no-host-paths): the "Vendored in the standalone tree"
  paragraph now lists today's bin/toolchain.

Test: `pixi run --locked -e pkg conda-package` (pixi.lock sha256
e9f17d315fd52ccf58db6a9840379e787e5c51ad80406982f907faa2dc1b9513), run
under `strace -f -e trace=execve`.
- It passed in 12.5 min, both packages' tests included, with build 4's
  build strings (hb0f4dca_4, hf9c1e0e_4).
- `which`: none of the 1,251 execve calls, successful or failed, ran a
  file named `which`, and no script, build.zig or rzig source calls it.
  So `which` left the build requirements too. On macOS this is shown by
  CI only.
- No host sed or grep ran: sed came from the build env, and grep never
  ran.

Compared with universe's build 4 (r-zig-slim sha256 5956f25c...,
r-zig-toolchain 9f8b8620...):
- r-zig-toolchain: its 6 files are byte-identical, and its depends are
  equal.
- r-zig-slim, files:
  - the same 1,860 paths, with the same paths.json types, modes and
    prefix placeholders;
  - lib/R/etc is identical, and 1,761 files are byte-identical.
- r-zig-slim, the 99 files that differ:
  - which they are: DESCRIPTION and Meta/package.rds, 15 each (the
    `Built:` date); doc/NEWS*.rds (3); help/paths.rds (14); and 52 R
    and help lazy-load DB files.
  - How they were compared: loaded object by object (7,691 objects),
    with the rattler-build directories and dates replaced by tokens.
  - All are equal except two kinds: paths.rds's `first` attribute,
    which is the build directory's length; and Rd2HTML's help, which
    holds a build-time `\Sexpr` date.
  - base's R code: all 1,179 objects are identical without any
    normalizing (bytecode included), except `.Library` and `.popath`.
- r-zig-slim, depends: one difference, `libharfbuzz >=14.5.1` became
  `>=14.6.0`. That is the run export of conda-forge's harfbuzz 14.6.0,
  published after build 4; rattler-build solves when it runs. The only
  other changes in what it resolved are python 3.14.7 → 3.14.8 and
  `which` gone.
- `/bin/which`, `/bin/sed`, `/bin/grep`:
  - none in either package's files, nor in the deparsed R code DBs;
  - the one match, in both builds, is upstream R's Solaris comment
    `/usr/xpg4/bin/sed` in bin/R;
  - build 4's info/recipe/recipe.yaml still had the deleted comment's
    paths.

Noticed, not changed:
- Build 4 has the same build-machine paths in its R and help DBs,
  NEWS*.rds and paths.rds: rattler-build's host prefix and work
  directory, in `.Library`, `.popath`, each namespace's `path`, and the
  Rd file names.
- These files are compressed, so conda's prefix replacement and a text
  scan both miss the paths.
- At run time base's Rprofile sets `.Library` and `.popath` again, and
  loadNamespace sets `path` again.

Still to do: omicron (osx-arm64, osx-64), kappa (win-64; the deleted
block was unix-only) and the five CI conda-package jobs.

## The zig 0.17 wave (open, decision 18)

This is not one of this PR's phases. It is recorded here because it
decides three things: which zig builds the conda packages, which zig
the toolchain archive carries, and which build of flang's runtime we
link.

### Where things stand (checked 2026-10-06)

- **Upstream.**
  - ziglang.org's download/index.json lists 0.17.0, dated 2026-10-01,
    for every platform we build:

    | Platform | Archive | Size |
    |---|---|---|
    | x86_64-linux | tar.xz | 57.3 MB |
    | aarch64-linux | tar.xz | 52.9 MB |
    | aarch64-macos | tar.xz | 54.0 MB |
    | x86_64-macos | tar.xz | 59.3 MB |
    | x86_64-windows | zip | 100.3 MB |

  - PyPI's ziglang is still at 0.16.0. fetch-zig.sh's pins (PyPI
    wheels, decision 2's option a) therefore have no 0.17 to name. Until
    PyPI publishes, an upstream 0.17 means ziglang.org's archive
    (decision 2's option b).
- **conda-forge.**
  - Source: anaconda.org's file lists
    (`api.anaconda.org/package/conda-forge/<name>`) for `zig`,
    `zig_impl_linux-64`, `zig_impl_osx-arm64` and `zig_impl_win-64`.
  - They have 0.17.0 only under the `zig_dev` label. These are master
    snapshots, 0.17.0-dev.2320+1e770dbef, with build strings
    `<hash>_2320_1e770dbef_23200` to `_23202`. The newest was uploaded
    2026-10-03.
  - The main label's newest is 0.16.0 build 20, also uploaded
    2026-10-03. `pixi search zig_impl_linux-64 -c conda-forge` resolves
    `0.16.0 h0addc32_20`.
  - The feedstock has not said whether 0.17 will replace main's 0.16 or
    land in a separate feedstock or label (flang-pixi docs/17 §8).
- **flang-pixi.**
  - At its 0.17 wave, flang-pixi builds flang-zig with upstream zig,
    from a sha256-pinned ziglang.org tarball. That is the user's summary
    of flang-pixi's report (2026-10-06). flang-pixi's docs/19 §6 and
    handoff §8 still describe it as an open principle decision.
  - With the same explicit flags, upstream 0.16.0 and conda-forge's zig
    produce identical machine code. Only the clang version string and
    NEEDED differ: conda-forge's `--no-as-needed` patch adds all eight
    glibc libraries.
  - From that wave on, each package has one build number on every
    platform: flang-zig 6, flang-rt-zig 10 and lld-zig 5 (handoff §7).
- **Us.**
  - zig is pinned to `0.16.*` in pixi.toml:140 and :352, in the
    recipe's staging build (recipe/recipe.yaml:132) and in
    r-zig-toolchain's run dependencies (recipe.yaml:486). The wheel
    requires `ziglang>=0.16.0,<0.16.1`.
  - build.zig does not compile on 0.17 (flang-pixi docs/17 §4).
    `b.install_prefix` and `b.pathFromRoot` are gone, and configure
    caching needs `poisonCache` or a `dependOn*` call for every env
    lookup and file read.
  - scripts/zig-build.sh runs `zig build`, whose non-`-D` arguments
    must now come before the `-D` options (flang-pixi docs/17 §8,
    "Maker-first argument order").
  - rzig's own sources have not been checked against 0.17's std.

### The pins after flang-pixi's wave

- **flang-rt-zig.** After the wave, set `build-number = ">=10"` on
  every platform:
  - in [dependencies] (pixi.toml:154-160);
  - in [feature.minimal.dependencies] (pixi.toml:373);
  - and delete the win-64 override (`>=4`, pixi.toml:229-234).

  Build 10 is static with hidden visibility everywhere.
- **llvm-openmp.** flang-rt-zig 10 also adds `llvm-openmp >=23` to its
  unix run dependencies. omp_lib.mod declares OpenMP 6.0-era entry
  points that only an LLVM 23 libomp exports (flang-pixi docs/19 §7).
  Our `llvm-openmp = "23.*"` (pixi.toml:183) already matches.
- **The recipe.** recipe.yaml names flang-zig and flang-rt-zig without
  a pin (lines 139-140, 232 and 487-488), so the conda build takes the
  newest anyway.
- **One check comes first,** whatever decision 18 says.
  - Build 10 reaches us without any change of ours, built by zig 0.17
    while we still link with 0.16:
    - the conda build resolves recipe.yaml's unpinned flang-rt-zig at
      build time, with no lock, so the first conda-package job after
      flang-pixi publishes takes it;
    - every new install of the published r-zig-toolchain `_4` takes
      it, since its run dependencies name flang-zig and flang-rt-zig
      unpinned ("What exists today"). Conda users then compile with
      flang-zig 6 and flang-rt-zig 10 under zig 0.16;
    - the first re-lock of pixi.lock takes it (`>=9` and `>=4` have no
      upper bound).
  - On Windows, 0.17 compiles MinGW code with `-D__CRT__NO_INLINE`,
    which turns header inlines into calls into zig's own libc
    (flang-pixi docs/17 §2). 0.16's CRT may not provide those.
  - On every platform, build 10 is compiled against 0.17's libc++ 22
    headers (docs/17 §7), while build 4's and 9's archives reference
    nothing from libc++ (Design 5's check). A new libc++ reference
    would not resolve on unix, where FLIBS has no `-lc++`.
  - So the check has to run before flang-pixi publishes build 10, not
    before our re-lock: Design 5's symbol check on build 10's archive
    for every subdir, a link of each with our zig 0.16, and an R build
    and a Fortran package on kappa.
  - Proposed: ask flang-pixi to run it as part of their wave, on their
    candidate packages, before upload. A temporary `<10` bound in
    recipe.yaml and pixi.toml would protect only our own builds and
    locks, not installs of the published `_4`.

### What r-zig-pixi's conda build does at 0.17

- **a. Wait for conda-forge's main label.** Everything moves together
  once a main-label `zig_impl_*` 0.17.0 resolves from conda-forge: the
  pixi envs, the recipe and CI.
  - The conda packages keep one zig: the zig that builds R is the one
    that r-zig-toolchain's run dependency installs. That is the
    2026-09-29 rule, "conda: conda-forge's `zig`" (PLAN.md:372-373; this
    plan's Principles: "conda-forge's zig stays the conda toolchain's").
  - The recipe is unchanged apart from the version.
  - Cost: a wait of unknown length; the feedstock has given no date.
- **b. The pinned upstream tarball in the conda build, as flang-pixi
  does.** "Both zigs" then means:
  - conda-forge's zig in the pixi dev envs and regular CI;
  - upstream zig in the conda build and the gated upstream-zig legs.

  When conda-forge publishes 0.17, the dev envs and CI follow.
  - What it gains:
    - The conda build no longer waits for conda-forge.
    - The published R is built by the reference zig: the same zig as
      flang-pixi's packages and the standalone toolchain (decision 9).
    - conda-forge's patches stop applying to it: the shared-libc++
      preference, which today needs the ZIG_LIB_DIR mirror, and the
      Linux linker patches such as `--no-as-needed` (flang-pixi docs/16
      D1 and D6). The wrappers' flag drops (D5) never applied, since
      build.zig and rzig call the zig binary directly.
  - What the recipe needs, one of:
    - **A `source:` entry per build platform.** It names ziglang.org's
      archive (or a community mirror's), with its sha256 from
      index.json, selected by `if:` and unpacked into, say,
      `zig-upstream/`. rattler-build checks the hash and caches the
      download. build.sh exports `ZIG_BIN` to it, which is zig-build.sh's
      F4 path, the one upstream-zig.yaml already runs. `zig 0.16.*`
      leaves the staging output's build requirements (recipe.yaml:132).
    - **A universe repackage.** A small recipe of our own unpacks the
      same tarball into a package, for example `zig-upstream`, installed
      away from `bin/zig` so that it cannot clash with conda-forge's
      `zig`. It is then a build requirement like any other, and could
      be r-zig-toolchain's run dependency. The cost is one more package
      to publish, store and maintain: 55-100 MB per subdir and version
      on prefix.dev, where flang-pixi already prunes for space.
  - **The run dependency is the hard part.** r-zig-toolchain
    run-depends on `zig 0.16.*` (recipe.yaml:486), and conda-forge has
    no 0.17 to name. Either it keeps 0.16, or it names our repackage.
    Keeping 0.16 means every conda user compiles packages with 0.16
    under an R built by 0.17: the mixed case across versions, which
    nothing tests.
  - It changes the 2026-09-29 rule above.

Both options share one constraint if upstream 0.17 is supported before
conda-forge's: build.zig and rzig must build with 0.16 and 0.17 at
once.
- For the two verified blockers, that is a small switch on
  `builtin.zig_version` (or `@hasDecl`) in two helpers, plus the cache
  registration.
- The switch is isolated, and goes when conda-forge has 0.17. That is
  the "small, isolated workaround" the principles allow.
- docs/17 §4 also expects unverified renames in `std.Build.Step.Run` and
  `Compile`. If the port needs more than a few such switches, it waits
  on a branch instead.

Recommendation (proposal):
1. **Do not tie our move to flang-pixi's wave.** Their 0.17 outputs are
   static and load only system libraries (handoff §7), so we can use
   them under either zig version. The one coupling is linking the
   runtime archive. Since build 10 reaches the conda build and conda
   users by itself, the check above has to be part of flang-pixi's
   wave, before upload.
2. **Upstream leads.** Port build.zig, rzig and zig-build.sh to 0.17
   and run the port on the gated upstream-zig legs. Meanwhile the
   default legs and the conda build stay on conda-forge's 0.16. The
   interim version switch keeps both zigs working.
   - The legs get 0.17 through fetch-zig.sh: PyPI's 0.17 wheel once
     it exists (docs/17 §4, in its unverified list, expects it before
     conda-forge's main label),
     keeping decision 2's one download path. Until then, ziglang.org's
     archive from a community mirror, sha256-pinned (decision 2's b).
   - The toolchain archive keeps bundling 0.16.0 until conda-forge has
     0.17 (Design 3), so fetch-zig.sh carries both versions during the
     gap.
3. **The conda build and r-zig-toolchain stay on conda-forge's zig**
   (a), and move when the main label has 0.17. The run dependency
   decides it: the conda packages run-depend on conda-forge's zig. If R
   were built with upstream 0.17 beside a toolchain package that runs
   0.16, every conda user would get the untested cross-version mix.
   flang-pixi has no such dependency, since its packages run without
   zig, which is why b suits it.
4. **Revisit b,** as a `source:` entry rather than a repackage, in
   either case:
   - conda-forge has not published 0.17 by the time the upstream legs
     are green on it;
   - the feedstock moves 0.17 to a separate feedstock or label.

## Decisions for the user

Each item lists the options, with the recommendation first.

1. **Layout.**
   - (a, recommended) An overlay archive with the same top directory,
     extracted in the same place.
   - (b) A separate toolchain directory found through
     `R_ZIG_TOOLCHAIN_ENV`, which is item 4.
2. **zig's artifact.**
   - (a, recommended) PyPI's ziglang wheel, as fetch-zig.sh pins it
     (byte-identical to ziglang.org's release).
   - (b) ziglang.org's archive, from a community mirror, with minisign.
3. **Where zig enters the tree.**
   - (a, recommended) build.zig's `-Dbundle-zig` for every non-conda
     tree, with env.sh always exporting `ZIG_BIN`.
   - (b) Opt-in, for packaging runs only.
   - (c) Added by package-standalone.sh.
   - (d) Downloaded by rzig at first use.
4. **rzig's lookup.**
   - (recommended) `ZIG_BIN`, then the zig beside rzig, then PATH, then
     `python3 -m ziglang`; flang beside rzig before PATH; a no-zig
     message that names the hint.
   - (alternative) A Renviron `ZIG_BIN` default written by build.zig.
   - (alternative) PATH only.
5. **make on unix.**
   - (a, recommended) conda-forge's make in every non-conda unix tree,
     with `MAKE` defaulting to it.
   - (b) The host's make for slim and full, as today.
   - (c) make built with zig, as a later option.
6. **Fortran.**
   - (b, recommended) flang-pixi's compile set inside the toolchain
     archive: flang-23 and its link, the intrinsic and OpenMP modules,
     and libflang_rt.runtime.a. It adds 30.5-43.9 MB with zstd, and
     needs no lld, no sysroot and no flang.cfg. flang-pixi has proved
     it on all four OSes (Design 5). Still ours: zig-fc sends executable
     links (configure probes) through zig and passes
     `-fintrinsic-modules-path`.
   - (a) None, as today.
   - (c) The full flang-zig closure.
   - (d) A separate `-fortran` archive.
7. **OpenMP files.**
   - (a, recommended) They stay in base, as in conda.
   - (b) Move them to the toolchain archive.
   - (c) Move them under `bin/toolchain` and change rzig.
8. **Windows** (shared with item 2).
   - (recommended) Split Windows too: the base zip is useful on its own,
     because CRAN ships Windows binaries. Ship the toolchain zip with
     rzig, the binutils and zig, expecting sh and make on PATH as today.
     Prototype busybox-w32 plus GNU make against the m2 set on kappa,
     and then bundle the winner in `bin/toolchain/usr/bin`, put on PATH
     through Rcmd_environ.
   - (alternative) The m2 set now.
   - (alternative) Require Rtools45.
   - (alternative) Leave Windows unsplit until item 2.
9. **Which zig builds released standalone archives.**
   - (recommended) Upstream zig, once a release job exists; this PR
     tests the mixed case.
   - (alternative) The env's conda-forge zig.
10. **Publishing.**
    - (recommended) In this PR, CI uploads both archives as workflow
      artifacts with short retention. A release job on `v*` tags,
      mirroring the GPL sources, is a follow-up.
    - (alternative) The release job in this PR.
11. **Compression.**
    - (recommended) gzip, as the base uses; revisit after phase 4's
      sizes. With flang, linux-64's toolchain is estimated at about
      150 MB with gzip, or 105 MB with zstd (Design 10).
    - (alternative) xz or zstd for the toolchain archive.
12. **Conda build number.**
    - (recommended) Bump 4 → 5 once, in the last phase (build 4 is on
      the channel since 2026-10-06). rzig and patch 0009 change both
      packages, and `--skip-existing` would keep build 4's files
      otherwise.
    - (alternative) No bump, leaving the channel behind main until the
      next bump.
13. **The preflight's Makeconf-CC fallback.**
    - (recommended) Remove it.
    - (alternative) Keep it.
14. **The recipe cleanup.**
    - (recommended) Scope: the host block and its comment, the dead
      `@WHICH@`, and the stale comments; drop the build `which` only if
      a run proves it. Order: first.
    - (alternative) Order: last, as the item lists it.
15. **Names.**
    - (recommended) Working names now.
    - (alternative) Wait for the v3 naming decision.
16. **Variants.**
    - (recommended) Every flavor that `package` runs on gets the pair;
      CI packages default and minimal, as today.
17. **Where build.zig gets the flang files** (with decision 6 = b;
    Design 5).
    - (b, recommended) Copy the documented set from the build env's
      installed flang-zig and flang-rt-zig. build.zig writes their
      name, version, build, URL and sha256 from conda-meta into
      `bin/toolchain/SOURCES`. flang-pixi's carving script serves once,
      in the prototype, as a cross-check.
    - (a) Run flang-pixi's carve-fortran-standalone.py on the published
      `.conda` files, pinned to a flang-pixi commit. It needs Python ≥
      3.14 or zstandard, and a second download of both packages. As of
      2026-10-06 the script is not committed in flang-pixi.
18. **The zig 0.17 wave** (its own section, before these decisions).
    - (recommended) Do not tie our move to flang-pixi's wave. Upstream
      leads: port build.zig, rzig and zig-build.sh to upstream 0.17
      (PyPI's wheel once it exists, else ziglang.org's archive) on the
      gated upstream-zig legs, with a small version switch so that
      conda-forge's 0.16 keeps building. The conda build and
      r-zig-toolchain stay on conda-forge's zig until its main label has
      0.17, because the toolchain package run-depends on it. Revisit
      (b) if conda-forge stalls.
    - (b) The conda build uses a sha256-pinned upstream tarball (a
      `source:` entry, or a universe repackage), as flang-pixi does.
      conda-forge's zig stays in the dev envs and CI.
    - Either way, before flang-pixi publishes flang-rt-zig 10 (the
      conda build and installs of r-zig-toolchain `_4` take it
      unpinned): the symbol and link check with our zig 0.16, proposed
      as part of flang-pixi's wave. After the wave: flang-rt-zig `>=10`
      on every platform, replacing the split `>=9`/`>=4`.

## Phases

Each phase is small and testable on its own. Each one goes through
implementation in a worktree, review, tests on linux-64 here, omicron
(osx-arm64, then osx-64 under Rosetta in ~/rz-osx64) and kappa (win-64,
C:\Users\admin\r-zig-pixi), then CI. The user loads the SSH key for
omicron and kappa and makes the commits. Phases 7 and 8 depend on
decisions 6 and 8 and can move to their own PRs.

Prerequisites from outside this plan:
- rzig passes `-mcpu=baseline` (Design 3). This is pending the user's
  go. It already affects r-zig-toolchain on win-64, and is needed at the
  latest before phase 4 ships compilers to Windows users.
- Before flang-pixi publishes flang-rt-zig 10: the symbol and link
  check of its archives with our zig 0.16 ("The zig 0.17 wave"),
  proposed as part of flang-pixi's wave.

0. **Decisions and measurements.**
   - The user settles the decisions above.
   - Measure:
     - the Windows zip's toolchain directory (kappa) and the macOS
       tree's (omicron);
     - whether rzig is byte-identical across slim, full and minimal;
     - whether R.dll imports zstd.dll (kappa);
     - the gzip and xz sizes of zig plus make on each OS.
   - flang's sizes are flang-pixi's (docs/19 §2) and are not measured
     again.
   - No code changes.
   - The measurements are done (2026-10-06, "Phase 0 measurements").
     The full tree was measured on osx-arm64 only, and osx-64 and
     linux-aarch64 through build 4's packages. The decisions are still
     open.
1. **Recipe cleanup** (Design 11). conda-package runs on all five
   platforms, and both packages compare equal to build 4.
2. **The split, with today's contents.**
   - package-standalone.sh makes the base and toolchain archives.
   - The standalone hint comes from zig-build.sh and build.zig, and
     make-wheel.py replaces it in the wheel.
   - Patch 0009 loses its fallback (if decided).
   - verify-bundle.sh checks the base archive alone, then the
     toolchain archive over it, plus the file-list equivalence.
   - CI uploads both archives.
   - No new tools in the archives yet.
3. **rzig's toolchain root** (Design 2).
   - rzig looks for zig and flang beside itself, and prints a no-zig
     message that names the hint.
   - Unit tests cover both.
   - env.sh always exports `ZIG_BIN`.
   - conda and the wheel behave as before.
4. **Upstream zig in the toolchain** (Design 3).
   - Covers `-Dbundle-zig`, zig-build.sh, the make-wheel.py exclusion,
     verify-tree, the copy in hermetic-check.sh, and zig's licences.
   - verify-package compiles under `env -i` with ZIG_BIN unset and the
     archives alone: C, C++, and OpenMP C (the mixed case on the default
     legs).
5. **make in every unix toolchain** (Design 4). verify-package compiles
   with no make on PATH, and `R CMD config` works with the toolchain.
6. **Licences and sources** (Design 9). verify-tree checks for
   `LICENSES/` and `SOURCES` in the toolchain directory.
7. **Fortran** (Design 5; decisions 6 and 17).
   - Already proved by flang-pixi (docs/19), so not repeated:
     - the set compiles alone;
     - zig links the runtime archive without lld, a sysroot, an SDK
       path or the CRT snapshot;
     - the executables load only system libraries;
     - no flang.cfg is needed;
     - the sizes.
   - Ours, first, as the prototype on linux-64, osx-arm64, osx-64 and
     win-64:
     - zig-fc sends executable links and mixed source-and-link calls
       through zig, so that a configure probe of `$FC` passes in the
       standalone tree and in a conda env;
     - zig-fc passes `-fintrinsic-modules-path`;
     - rzig finds the runtime in `bin/toolchain/flang/`, and the driver
       works as the single file `flang` (`flang.exe`);
     - Windows: a Fortran package builds and loads without `-lc++`;
       macOS (omicron): R builds without the runtime's `link_libcpp`.
   - Then:
     - the set in the tree, from the env (decision 17), with its SOURCES
       entries;
     - the carve script's cross-check;
     - rzig's lookup;
     - the compile checks;
     - removing `-lc++` and the runtime's `link_libcpp` where those runs
       passed.
8. **Windows userland** (Design 7; decision 8).
   - First the prototype on kappa.
   - Then the userland in `bin/toolchain/usr/bin`, Rcmd_environ, and a
     clean `R CMD config` failure.
   - Then the Windows compile checks with PATH set to bin\x64 and
     System32.
9. **Finish.**
   - The build-number bump (if decided).
   - Updates to the records: feat-no-host-paths PLAN.md (What remains 3,
     the T record, the OpenMP note) and this PLAN.
   - A run of the `upstream-zig` label, and one last cross-OS round.

## Verification

What must stay green:
- every build.yaml leg (default, full, openblas, minimal, Windows):
  rzig-test, build, verify-tree, smoke, contract, check, hermetic,
  verify-package, wheel and wheel-test;
- the five conda-package jobs, with both packages' tests
  (test-preflight.R and test-toolchain.R);
- the upstream-zig legs, run on demand with the PR label.

New checks, in verify-bundle.sh (`pixi run verify-package`):
- **File lists.** The base archive is the installed tree minus
  `R_HOME/bin/toolchain`, the toolchain archive is only that directory,
  and together they are the tree.
- **The base alone, freshly extracted:**
  - R starts (unix: `env -i` with PATH set to `<base>/bin`; Windows:
    bin\x64 plus System32);
  - a package with `src/` stops with the standalone hint's text;
  - unix: `R CMD config CC` fails with "needs make" (Windows: from
    phase 8).
- **The base with the toolchain over it, freshly extracted, ZIG_BIN
  unset:**
  - unix: `env -i HOME=<tmp> PATH=/usr/bin:/bin`.
  - `RZIG_PRINT_ARGV=1` shows `<toolchain>/zig/zig` as the command, and
    `MAKE` is `<R_HOME>/bin/toolchain/make` (macOS's `/usr/bin/make`
    stub and a runner's make on PATH must not be what runs).
  - It compiles a C package, a C++ package (no shared libc++ or
    libstdc++), an OpenMP C package and the flagless omp.h probe.
  - From phase 7, with no flang on PATH and no flang.cfg in the tree,
    it also compiles:
    - a Fortran package with a derived-type module;
    - a USE_FC_TO_LINK package;
    - `use omp_lib` running on two threads;
    - a configure that compiles and links a program with `$FC`.

    RZIG_PRINT_ARGV shows `<toolchain>/flang/bin/flang` compiling and
    zig linking.
  - `install.packages(Ncpus = 2)` of two compiled packages runs make.
  - Windows (phase 8): the same, with PATH set to bin\x64 plus System32,
    so that the userland comes only through Rcmd_environ.
- The existing compile checks keep running with `ZIG_BIN=$ZIG`, the
  zig that built R.

By hand on each machine, for each phase:

```sh
pixi run rzig-test
pixi run build && pixi run verify-tree && pixi run smoke && \
  pixi run contract && pixi run hermetic && pixi run verify-package
pixi run -e minimal build && pixi run -e minimal verify-tree && \
  pixi run -e minimal verify-package
pixi run -e wheel wheel && pixi run -e wheel wheel-test   # unix
pixi run -e pkg conda-package
# upstream zig (F4), then the same tasks:
export ZIG_BIN="$(pixi run fetch-zig)"   # PowerShell: $env:ZIG_BIN = pixi run fetch-zig
# a user's view: both archives, nothing else
mkdir /tmp/sa && cd /tmp/sa
tar -xzf .../R-4.6.1-slim-linux-64.tar.gz
tar -xzf .../R-4.6.1-slim-linux-64-toolchain.tar.gz
env -i HOME=/tmp/sa PATH=/usr/bin:/bin RZIG_TRACE=1 \
  R-4.6.1-slim-zig/bin/R CMD INSTALL -l lib <a package with src/>
```

On Windows the user's view runs from cmd.exe, with PATH set to
`R-...\Library\lib\R\bin\x64;C:\Windows\System32` and
`R.exe CMD INSTALL`.

The recipe cleanup is verified by conda-package on the five CI jobs
plus omicron and kappa, and by the comparison with build 4 (Design 11).

## Risks

- **Size.** Every non-conda tree grows by 343-380 MB of zig (19,546
  files), plus 144-210 MB
  if flang ships (raw; the flang driver binary alone is 136-196 MB,
  flang-pixi docs/19 §2). That costs dev disk space and CI time: copies,
  archive time, and artifact storage for two archives on each of ten
  legs.
- **A silent switch of zig.** If env.sh does not export `ZIG_BIN`
  always, dev compiles quietly move to the bundled upstream zig, and the
  conda-forge zig path for packages loses its coverage in every commit.
- **The mixed zig case.** R built with conda-forge zig and packages
  compiled with upstream zig is tested today only by wheel-test, which
  has no OpenMP and no Fortran.
- **Windows with upstream zig.** Rust-based packages fail
  (`-lsynchronization`, What remains 8), and the bundled toolchain makes
  that the standalone user's default.
- **The first compile is slow.** Upstream zig builds libc++ and
  compiler_rt into its global cache (`~/.cache/zig`, `%LOCALAPPDATA%\zig`)
  on the first C++ compile, and prints about 3k warnings once
  (feat-wheel-minimal/PLAN.md).
- **macOS without the Command Line Tools.** rzig runs `xcrun` on every
  compile, and on such a Mac that may open the install dialog (not
  observed: omicron has the CLT).
  - Simulated with an empty DEVELOPER_DIR (Phase 0 measurements): xcrun
    fails at once, and rzig drops the SDK flags without a word. Plain C
    still compiles and links, but `-framework CoreFoundation` fails
    with "unable to find framework".
  - So packages that link frameworks need the SDK.
  - Browser downloads get quarantined by Gatekeeper; curl downloads do
    not.
- **conda-forge's binaries carry build-path strings.**
  - make names /home/conda/feedstock_root/... (linux) and
    /Users/runner/miniforge3/conda-bld/... (macOS). These are its
    compiled-in include, lib and locale directories under an
    unreplaced `_h_env_placehold` prefix.
  - win-64's make.exe names D:\bld\... and /home/conda/... in its debug
    sections.
  - None of them names our build machine (Phase 0 measurements).
    verify-tree lists them and does not fail on them.
- **GPL obligations grow.** They are already unmet for make and the
  Windows binutils. Shipping without SOURCES and a source mirror repeats
  that.
- **The Windows userland.**
  - m2: the msys-2.0.dll clash with Rtools or Git for Windows, and the
    spawn hangs.
  - busybox: bash-only configure.win scripts, and make's direct exec of
    simple commands.
- **The hint.** Until a release page exists, the hint names an archive
  but no place to get it.
- **zig 0.17.** It has been released upstream, and conda-forge has it
  only on the `zig_dev` label. Moving to it is decision 18, not part of
  this PR ("The zig 0.17 wave").
- **flang-rt-zig 10 built by a newer zig.** flang-pixi's wave builds the
  runtime with zig 0.17. The conda build and every new install of the
  published r-zig-toolchain `_4` take it as soon as it is published
  (unpinned), and a re-lock takes it too (`>=9` and `>=4` have no upper
  bound). On Windows its objects may call functions that our zig 0.16's
  CRT lacks (`-D__CRT__NO_INLINE`, flang-pixi docs/17 §2), and on every
  platform it is compiled against 0.17's libc++ 22 headers. This touches
  R's own build and every Fortran package, conda users' included. The
  check, which has to run before flang-pixi uploads build 10, is in "The
  zig 0.17 wave".
- **Native CPU code on Windows.** Until rzig passes `-mcpu=baseline`,
  Windows package compiles target the CPU of the machine that compiles
  them. A bundled toolchain does not change that, but standalone users
  who share built packages would meet it (Design 3).
- **zig-fc's split of mixed calls.** Sending configure's
  compile-and-link calls through `flang -c` plus a zig link is the
  splitting F3c avoided. A probe that relies on driver behaviour, such
  as `-v` output parsed for library paths, or flags meant for flang's
  linker, may behave differently. The prototype runs real configure
  scripts, not only a hand-written probe.
- **The wheel picks up the toolchain's new files.** Unless make-wheel.py
  excludes `bin/toolchain/zig/` (and `flang/`), the wheel goes past
  PyPI's limit.
- **libomp.dll and VCRUNTIME140.dll.** On Windows libomp.dll imports
  VCRUNTIME140.dll, and a clean Windows without the VC++ redistributable
  has never been tested. This is not new, but standalone users are the
  ones who would hit it.

## Open questions

- Can the macOS check run on a Mac without the Command Line Tools?
  omicron has them (CLT 26.4, no Xcode). An empty DEVELOPER_DIR
  simulates part of it (Phase 0 measurements): xcrun exits 1 at once,
  rzig drops the SDK flags, plain C links and frameworks do not. Still
  unobserved: whether a Mac that never had the CLT opens the install
  dialog on rzig's xcrun call. And what should rzig do there: skip
  `xcrun` when `xcode-select -p` fails? Under the simulation
  `xcode-select -p` prints the directory and exits 0, so that test
  would need the real case.
- Is rzig byte-identical across flavors? Yes (2026-10-06): linux-64
  slim = minimal, and osx-arm64 slim = full = minimal (Phase 0
  measurements). One toolchain archive per platform is possible later,
  once minimal's make is in every unix tree.
- Does R.dll import zstd.dll? Yes (kappa, 2026-10-06), so zstd.dll
  stays in base. Still open: should conda's packages declare zstd,
  given rattler's overlinking warning?
  - Neither build 4 package lists it (universe win-64 repodata,
    2026-10-06), although R.dll and the binutils import it.
  - It arrives through other packages: in pixi.lock's win-64 entries,
    libtiff, binutils_impl, ld_impl, zig_impl and python depend on
    zstd.
- Do the Windows binutils stay, or do zig's dlltool, ar and rc plus an
  rzig `nm` applet replace them? That would remove GPL-3 binaries other
  than make. A later question.
- Should Rprofile.windows also put the userland on PATH, for
  `system("make")` and pkgbuild? To be answered in phase 8's prototype.
- Pre-seeding zig's global cache (libc++, compiler_rt) in the archive,
  or accepting the slow first compile?
- The wheel toolchain mechanism (PLAN.md:2604-2605: a shared directory
  or discovery at startup), and pip upgrade and uv uninstall/upgrade.
  This plan does not change the wheel's mechanism. Should those tests be
  added here, since make-wheel.py changes?
- Where is the release published (GitHub Releases on `v*` tags?), and
  how does the hint name it?
- Item 4 later: the layout under the toolchain root (`zig/`, `flang/`,
  `make`, `usr/bin/`) is meant to serve a shared toolchain as it is. Is
  that the layout the user wants for item 4?
- flang-pixi's docs/19, its file lists and carve-fortran-standalone.py
  are untracked in the flang-pixi checkout (2026-10-06). Decision 17's
  option a needs them committed, and so does citing them by commit.
- Does flang-pixi's upstream-zig build for the 0.17 wave stand as
  decided? The user's summary says it does. flang-pixi's docs/19 §6 and
  handoff §8 still call it an unscheduled principle decision.
- Will flang-pixi run our check (build 10's archives linked with zig
  0.16, a Fortran package on kappa) before uploading build 10? If not,
  do we add a temporary `<10` bound to recipe.yaml and pixi.toml, which
  protects our builds but not installs of r-zig-toolchain `_4`?
- When zig-fc passes `-fintrinsic-modules-path` in a conda env, the
  env's flang.cfg names the same directory. Is the flag given twice
  harmless? And where should zig-fc get the conda triple: a constant
  per target, or a directory scan?
- Does flang still find its resource dir when Windows' `Library/` prefix
  is dropped under `bin/toolchain/flang/`?
- macOS: linkFortranRt links zig's libc++ into libR, libRblas and
  libRlapack for the runtime's sake. With flang-rt build 9 that is a
  no-op too (only `__cxa_atexit` and `__dso_handle`). Should it go in
  phase 7 with the Windows `-lc++`, after an omicron run?
