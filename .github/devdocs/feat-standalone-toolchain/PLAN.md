# feat-standalone-toolchain — R as a base plus toolchain groups, on three channels

**Status (2026-11-12): the three "next" items below are done. pkgconf
from source (#45), the zig 0.17 port (#46) and Windows' binutils from
zig and rzig (#47) merged into main on 2026-11-12; Windows on ARM is
branch feat-win-arm64 (#48, the build 11 release, not yet published;
record .github/devdocs/chore-release-11/PLAN.md).**

**Status (2026-11-09): phases 0 to 9 merged (#15 to #43) and published
as `_10` on 2026-11-09; the record is under "Phase 9" below.** The status blocks that follow are as of their dates.
Next (the user's order, 2026-10-22): pkgconf from source (TODO.md; in
progress on branch feat-zig-pkgconf, record pkgconf/PKGCONF.md), the
zig 0.17 port, Windows on ARM.

**Status (2026-10-08): the menus are answered (2026-10-08; "Resolved
decisions"). Implementation may start per B37 (a): #15 merges with
phases 0-1 and these documents once its checks pass, which needs the
re-lock PR on main first (R1 = a: the re-lock is its own PR); then one
PR per phase.** The re-lock PR (worktree chore-relock-flang-rt-10) and
#14 (fix-rzig-baseline-cpu) continue as planned. Nothing here changes
them.

- Branch feat-standalone-toolchain. Phases 0 and 1 are done. Their
  records were committed in 9bbce0b (PR #15), on top of the original
  single-archive plan (afd59a2). They are kept verbatim in "History" at
  the end.
- Phase 2 (2026-10-09): implemented in the worktree feat-standalone-phase2
  (branch feat-standalone-phase2, from main b2e73a5), not committed.
  Every test passed on linux-64, omicron (osx-arm64, osx-64) and kappa
  (win-64). The review found two code problems, in the bash shims and in
  Windows' build-tools check, and a mislabelled parity check; its diff is
  applied (rzig-test 94/94, parity 0 failed, both zigs). CI has not run.
  Its record and test results are under "Phase 2" below.
- This plan replaces the single toolchain archive of 2026-10-05/06 with
  the user's layered model of 2026-10-07: a base that holds R, rzig and
  R's external runtime, and toolchain groups that hold only third-party
  compile-time software, with the same boundaries on the standalone,
  conda and PyPI channels.
- It is "What remains" item 3 of .github/devdocs/feat-no-host-paths/PLAN.md
  (lines 157-158).
- Code references (file:line) are to HEAD 9bbce0b and to R 4.6.1's
  patched sources in `build/R-4.6.1/`. "feat-no-host-paths PLAN.md" means
  that file as it is today. Inside the verbatim History parts, line
  numbers and "Design N" or "decision N" are those of 9bbce0b's plan;
  "Old decisions and their status" maps them.
- Decision IDs: B1-B18 are the old decisions 1-18 as the menu of
  2026-10-07 (14:04 UTC) numbered them. That menu did not keep the old
  order (B1 = old 1, B2 = old 4, B3 = old 16, ...); the full map is in
  "Old decisions and their status". B19-B22 are the user's answers of
  2026-10-07. B23 and up are new here. The user answered every open one
  on 2026-10-08; four answers are the user's own (B11, B24, B43, B44).

## Core goals

The user's words (2026-10-07), the guide for every decision:

> * Make R simpler and uniform across every OS and architecture.
> * Establish one standardized toolchain with sane, universal defaults.
> * Minimize reliance on makefiles and shell scripts so R operates as a single, cohesive runtime rather than a patchwork of OS-specific workarounds.
> * Ensure R is fully distributable via conda packages, PyPI, and as a standalone, relocatable installation.

Below, G1-G4 name these four goals in this order. Each recommendation
says which goal it serves.

## The layered model

### The user's architecture (2026-10-07, verbatim)

> New Architecture (Replacing the single-toolchain-archive model):
>
> 1. R vs. External Software: `rzig` is part of R (just like R's own headers, `Makeconf`, and import libraries). It must ship in the base across every channel: standalone base archive, `r-zig-slim`, and the `r_zig` wheel. The toolchain itself will only hold third-party software.
> 2. Runtime vs. Compile-time Dependencies:
>    * Runtime: External runtime libraries (vendored libraries, `libomp`'s runtime, Tcl/Tk, CA bundle, fontconfig) belong with the base since R requires them to run. Give them dedicated directories where the OS allows; on Windows, the DLLs must remain beside `R.dll`.
>    * Compile-time: These strictly belong in the toolchain.
> 3. Toolchain Segmentation: The toolchain will be split into modular groups, each within its own subdirectory under `bin/toolchain/` (with its own `LICENSES`/`SOURCES`):
>    * Compilers: `zig` (only where conda-forge or PyPI doesn't provide it); `flang`'s compile set; `omp.h` and `libomp.lib` under `bin/toolchain/{zig,flang,openmp}/`.
>    * Minimal build tools: Unix `make`; Windows `sh`, `make`, `coreutils` (`usr/bin/`), and `binutils` (`binutils/`).
>    * Optional extras: Extensions to the minimal build, added only when the stress suite demonstrates a need.
> 4. Discovery & Fallbacks: `rzig` will locate each group in its respective subdirectory. If a group is missing, it will explicitly name the archive or package required to install it.
> 5. Channel Consistency: We must enforce the same boundaries across all three channels:
>    * Standalone: One archive per group, all extracting into the same top directory (B1).
>    * Conda: Packages that depend on conda-forge or universe `zig` and `flang-pixi`'s `flang` rather than bundling them.
>    * PyPI: The `ziglang` dependency plus our own small packages.
> 6. Platform-Level Toolchains: The toolchain will no longer depend on the flavor. We will ship one toolchain per platform, tested once, rather than maintaining a toolchain for every flavor.

### Terms and paths

| Term | linux and macOS | Windows |
|---|---|---|
| `<top>` | the top directory every archive extracts into: `R-<ver>-zig/` (B36 a) | the same |
| env dir (rzig's "environment") | `<top>` | `<top>/Library` |
| R_HOME | `<top>/lib/R` | `<top>/Library/lib/R` |
| TC | `R_HOME/bin/toolchain` | `R_HOME/bin/toolchain` |

- In a conda env, `<top>` is the env's prefix. In the wheel it is
  `site-packages/r_zig/R`.
- rzig's own environment is rzig's real path minus `/lib/R/bin/toolchain`,
  and on Windows the rest must end in `/Library`
  (zigbuild/tools/rzig/environment.zig:47-64). So rzig stays at TC itself,
  and the groups are subdirectories of TC. Moving rzig anywhere else
  would change that rule.
- "flavor" is the R build: slim (default), full, minimal, each with
  internal BLAS or openblas (scripts/env.sh:17-23). Windows builds only
  full (build.zig:401-406) and calls it slim on every channel (B42 = a,
  documented: Windows slim has full's content); minimal has no Windows
  build.
- Group names: B38 = (a), `compilers` and `build-tools`. The brief calls
  the second group "minimal build tools".

### 1. R and external software (the base)

The base is R plus rzig, on every channel:
- **unix:** the launchers `<top>/bin/R` and `<top>/bin/Rscript`; R_HOME
  with its headers (`R_HOME/include`), `etc/Makeconf` and `etc/Renviron`;
  rzig at `TC/zig-cc`, `TC/zig-cxx`, `TC/zig-fc`, `TC/zig-ar` and
  `TC/zig-ranlib` (installRzig, build.zig:2430-2441).
- **Windows:** `<top>/Library/bin/R.bat` and `Rscript.bat`; R.dll,
  Rblas.dll, Rlapack.dll, Rgraphapp.dll, Riconv.dll and the executables
  in `R_HOME/bin/x64`, which is also where packages link R.dll from
  (IMPDIR); `etc/x64/Makeconf` and `etc/Rcmd_environ`; rzig at
  `TC/gcc.exe`, `TC/g++.exe` and `TC/zig-fc.exe`, and from phase 3 also
  at `TC/zig-ar.exe`, `TC/zig-ranlib.exe`, `TC/gcc-ar.exe` and
  `TC/gcc-ranlib.exe` (B43: AR and RANLIB go through rzig as on unix,
  and rzig answers to gcc-ar and gcc-ranlib), and `TC/ar.exe` and
  `TC/ranlib.exe`, which CMake looks for beside CC (phase 3's step 3
  review). The extensionless `zig-cc` and `zig-cxx` copies exist only
  for the preflight's file test (build.zig:2420-2421) and go with B26
  (a).
- rzig is one binary per platform, byte-identical across flavors (Phase
  0 measurements), copied once per name.
- The external runtime (section 2) is also in the base.
- Third-party compile-time software is not. It is the toolchain
  (section 3). One exception, on Windows: Tcl/Tk's headers in
  `R_HOME/Tcl/include`, beside the Tcl/Tk runtime (T1).

### 2. Runtime and compile-time

Runtime: what R or a binary package needs to load and run. It stays in
the base (B21 = a). Today's places, and what B27 (a) changes (phase 8):

| Runtime item | linux and macOS today | Windows today | B27 (a) |
|---|---|---|---|
| vendored shared libraries | `<top>/lib/*.so.N`, `*.dylib`: only third-party libraries sit as files in `<top>/lib`; its subdirectories are R_HOME, `pkgconfig` (R's libR.pc) and Tcl's scripts (scripts/vendor-libs.sh:116-172) | `R_HOME/bin/x64/*.dll`, beside R.dll (vendor-libs.sh:76-115) | unchanged |
| libomp runtime (slim, full) | `<top>/lib/libomp.so`, `libomp.dylib` (libR links it, build.zig:2677-2684) | `R_HOME/bin/x64/libomp.dll` (no R DLL imports it; packages do) | unchanged; on Windows its trigger changes (phase 3) |
| Tcl/Tk (unix full; Windows always) | `<top>/lib/{tcl8.6,tk8.6,tcl8}` and `libtcl8.6`, `libtk8.6` in `<top>/lib` (build.zig:3031-3046) | `R_HOME/Tcl/bin/{tcl86t,tk86t}.dll`, `R_HOME/Tcl/lib` (CRAN's layout; tcltk's .onLoad looks there); the headers in `R_HOME/Tcl/include` (T1) | unchanged |
| CA bundle (not Windows) | `R_HOME/etc/ca-bundle.crt`, named by etc/Renviron's `R_ZIG_CA_BUNDLE` (build.zig:3006-3029, 3665-3674) | none: libcurl uses Schannel | `<top>/ssl/cacert.pem`, conda's place |
| fontconfig (slim, full) | `<top>/etc/fonts`; the launchers set `FONTCONFIG_PATH` (zigbuild/launchers/R:17-21) | `R_HOME/etc/fonts`; `FONTCONFIG_PATH` in etc/Renviron.site, which `--vanilla` skips (build.zig:3077-3080) | `<top>/Library/etc/fonts`, where conda-forge's win-64 fontconfig keeps it; `FONTCONFIG_PATH` set where `--vanilla` still reads it |
| licence texts and sources | none | none | `<env dir>/share/licenses/` (B33) |

The libraries R's own binaries need are found through two relative
rpaths, R_HOME/lib and `<top>/lib`, and the comment there relies on
conda and the standalone tree sharing `<top>/lib` (build.zig:165-188).

Compile-time: everything a package compile needs that is neither R nor
rzig: zig, flang's compile set, the OpenMP headers and (Windows)
libomp.lib, make, and on Windows sh, make, the other userland tools
(B39), pkg-config (B43) and the binutils rzig does not serve (B24). It
goes in the toolchain. On unix the libomp runtime is also the link
input for `-lomp` (there is no import library), so OpenMP's
compile-time part there is the four headers. One exception (T1):
Windows' Tcl/Tk headers stay in the base, in `R_HOME/Tcl/include`.

### 3. The toolchain groups

One archive (standalone), one package (conda) and one wheel (PyPI) per
group. A group is a set of directories directly under TC. Each of those
directories has its own `LICENSES/` and `SOURCES`, as point 3 requires
(what they hold: phase 3).

| Group | Directory | linux and macOS | Windows |
|---|---|---|---|
| compilers | `TC/zig/` | `zig`, `lib/` (upstream 0.16.0; B4) | `zig.exe`, `lib/` |
| compilers | `TC/flang/` | `bin/flang`; `lib/clang/23/finclude/flang/<conda triple>/` (15 intrinsic modules, `omp_lib.mod`, `omp_lib_kinds.mod`, `omp_lib.h`); `lib/clang/23/lib/<rt dir>/libflang_rt.runtime.a`. On linux flang-rt-zig also ships `x86_64-unknown-linux-gnu` as a symlink to the conda-triple directory (seen with build 9 in the default env; build 10 too: a `softlink` in its record, phase 6). It is not needed once zig-fc passes `-fintrinsic-modules-path`, and must not be installed as a copy (phase 6 copies only `hardlink` paths, PHASE6 open point A a) | `bin/flang.exe`; the same tree, with both `x86_64-w64-mingw32` and `x86_64-w64-windows-gnu` module directories |
| compilers | `TC/openmp/` | `include/{omp.h,ompx.h,omp-tools.h,ompt.h}` | `include/{omp.h,ompx.h}`, `lib/libomp.lib` |
| build-tools (the brief's "minimal build tools") | `TC/usr/` | `usr/bin/make` (B23 a) | `usr/bin/`: B39's list (sh, make, coreutils, sed, grep, gawk, which, findutils, patch: feat-win-link-fixes item 4), every file of the nine `m2-*` packages' usr/bin with the nine MSYS DLLs they import (B11's phase 7 outcome: m2's make and coreutils too), and pkg-config 0.29.2 (B43), conda-forge's native build with its glib closure; no `pkgconf` name until it is built from source (TODO.md). `TC/etc/fstab` makes TC the MSYS root (phase 7) |
| build-tools | `TC/binutils/` | none | copies of conda-forge's MinGW binutils, as .exe: `nm, dlltool, as, strip, windres` and `objdump` (B24, B43); ar and ranlib are rzig's (B43), and each other tool moves to rzig once rzig can serve it (B24) |
| extras | later | added when the stress suite shows a need; the first, from round 1 (2026-10-08): cmake on every OS | the same |

Fortran's OpenMP module (`omp_lib.mod`) comes from flang-rt-zig, in
flang's resource directory, not from llvm-openmp (conda-meta of the
default env). So it belongs to `flang/`, not `openmp/`.

### 4. Discovery and fallbacks

rzig looks in its own directories (`TC/zig/`, `TC/flang/`, `TC/openmp/`)
before PATH; for zig, `ZIG_BIN` comes first. In a conda env and in the
wheel those directories do not exist, so the lookups fall through as
today.
- **zig** (B2 = a, B34 = a): `ZIG_BIN` (when it names an executable),
  then `TC/zig/zig` (`zig.exe`), then R's own environment's `bin/` (unix
  `<top>/bin/zig`; Windows `<top>/Library/bin/x86_64-w64-mingw32-zig.exe`),
  then PATH, then `python3 -m ziglang`. With none, a message that names
  the compilers group and how to install it (B35). Today:
  find_zig.zig:15-23.
- **flang** (B2 = a, B34 = a): `TC/flang/bin/flang` (`flang.exe`), then
  the environment's `bin/`, then PATH. One function (flang_rt.zig:45-46)
  serves both zig-fc and the runtime lookup, so the compiler and its
  runtime archive stay paired.
- **OpenMP** (B22 = a, B40 = a): when the base has the libomp runtime
  (`<top>/lib/libomp.so`/`.dylib`, `R_HOME/bin/x64/libomp.dll`), rzig
  adds `TC/openmp/include` to every compile (`-idirafter` on Windows, as
  for an environment's include today, compiler.zig:133-140), on Windows
  `-L TC/openmp/lib` so that `-lomp` resolves to libomp.lib
  (windows.zig:62-75), and `-lomp` to a `-fopenmp` link. minimal has no
  libomp, and its Makeconf's `SHLIB_OPENMP_*` are empty.
- **make, sh and the other build tools:** R runs them from PATH (B25);
  rzig never runs them. Point 4 has rzig locate this group too: with
  B26 (a), rzig's check mode resolves make (and on Windows sh) as R will
  run them and names the group when they are missing.
- **binutils and the other named tools** (Windows; the caveat, B24,
  B43): Makeconf.win names each one. AR and RANLIB name rzig
  (`$(BINPREF)zig-ar`, `$(BINPREF)zig-ranlib`, as on unix), and the LTO
  lines' `$(BINPREF)gcc-ar` and `gcc-ranlib` are rzig copies under those
  names. NM (and the LTO gcc-nm), OBJDUMP, DLLTOOL, RESCOMP and STRIP
  name files under `TC/binutils/`. PKG_CONFIG names `pkg-config` bare,
  as SED names `sed`: it is found on PATH like the other `usr/bin` tools
  (B25).
- **A missing group:** rzig prints the group's text (B35), at a compile
  for the compilers group and from the check mode for any group. The
  install preflight (patch 0009) and `R CMD config` (patch 0010) call the
  check mode (B26 a).

### 5. The same boundaries on every channel

| Component | Standalone | conda | PyPI |
|---|---|---|---|
| R (R_HOME, launchers, Makeconf, headers) | base archive `R-<ver>-<flavor>-<plat>` | r-zig-slim | r-zig (minimal) |
| rzig | base archive (today in the tree, archived with it) | r-zig-slim (since phase 4; on universe from the bump with phase 7's merge) | r-zig (since phase 4) |
| vendored runtime libraries | base archive | conda-forge packages, r-zig-slim's run dependencies | r-zig |
| libomp runtime | base archive (slim, full) | llvm-openmp, a run dependency of r-zig-slim | none (minimal) |
| Tcl/Tk | base archive (unix full; Windows, with its headers in `R_HOME/Tcl/include`: T1) | unix: none (conda builds slim); win-64: tk 8.6 through `MY_TCLTK` | none |
| CA bundle | base archive (unix) | ca-certificates, libcurl's compiled-in path | r-zig |
| fontconfig | base archive (slim, full) | fontconfig | none |
| zig | compilers archive: `TC/zig/` | conda-forge `zig 0.16.*`, through r-zig-compilers | `ziglang`, required by r-zig-compilers |
| flang's compile set | compilers archive: `TC/flang/` | universe flang-zig, lld-zig, flang-rt-zig, through r-zig-compilers | none (B29 a) |
| OpenMP headers, libomp.lib | compilers archive: `TC/openmp/` | llvm-openmp: one conda-forge package with headers and runtime, already a run dependency of r-zig-slim (B41); r-zig-compilers names it too | none (minimal) |
| unix make | build-tools archive: `TC/usr/bin/make` | conda-forge make, through r-zig-build-tools | r-zig-build-tools |
| Windows sh, make, pkg-config and the rest (B39, B43) | build-tools archive: `TC/usr/bin/`, copies of B11's conda-forge packages with their DLL closure | the same conda-forge packages (native first, `m2-*` where needed; B11), dependencies of r-zig-build-tools | none (no Windows wheel yet) |
| Windows binutils (nm, dlltool, as, strip, windres, objdump) | build-tools archive: `TC/binutils/` | r-zig-build-tools: the same copies in `TC/binutils/` (B41) | none |
| all groups at once | both group archives | r-zig-toolchain, a metapackage (B28 a) | r-zig-toolchain, a wheel with no files (B29 a) |

Where conda cannot match the standalone boundary as drawn (B41 = a: both
accepted and recorded as conda's two exceptions):
- conda-forge packages llvm-openmp as one package, and r-zig-slim needs
  its runtime (libR links libomp on unix). So in a conda env omp.h
  arrives with the base, and rzig's environment rule
  (environment.zig:91-99) turns OpenMP on with r-zig-slim alone. The
  effect is small: a compile still needs zig, which comes with
  r-zig-compilers or from the user.
- The Windows binutils are copies we make (Makeconf.win names a path
  under R_HOME), so win-64 r-zig-build-tools holds files, as
  r-zig-toolchain does today, instead of depending on conda-forge's
  binutils package.

Where PyPI differs: linux and macOS only, and the minimal flavor only.
r-zig-compilers brings zig (ziglang) and no flang or OpenMP (B29 a), so
`flang/` and `openmp/` exist on the standalone and conda channels only.
The wheel's etc/Renviron.site sets a `ZIG_BIN` default that names the
sibling ziglang (make-wheel.py's renviron_site); that is the wheel's one
channel-specific setting.

Where names differ: Windows builds full, and every channel calls it slim
(B42 = a), documented as "Windows slim has full's content". The user
wants a really slim Windows slim later ("Later and future checks").

### 6. One toolchain per platform

- rzig is identical across flavors, and the only flavor difference
  inside TC today is minimal's make (Phase 0). The flavor-dependent
  compile-time files today sit outside TC: the OpenMP headers (absent in
  minimal) and Makeconf.
- In the model Makeconf stays in the base, per flavor. The groups hold
  nothing flavor-specific, so one set per platform serves every flavor.
  What still differs by flavor (OpenMP) is decided in rzig from the base
  (B40).
- They are assembled once per platform in a toolchain tree (B30 a) and
  tested once per platform with each packaged base (B31 a).

### What a user gets

| Tier | Covers | Standalone | conda | PyPI |
|---|---|---|---|---|
| 0 Run, 1 Install without compiling | `R`, `Rscript`, `library()`, R-only source and binary packages, `install.packages(Ncpus > 1)` | base archive | r-zig-slim | r-zig |
| 2 Compile, compilers alone | `src/` and run-time compiles (`R CMD SHLIB`) that `rzig build` builds: no configure script R runs, a Makevars that only sets variables, no Objective-C (feat-zig-pkg-build N2; feat-shlib-rzig-build, 2026-10); pkgbuild's probe, so pak, once they are installed (installing them from source needs the build tools once); not `R CMD config` | base + compilers archives | + r-zig-compilers | + r-zig-compilers (zig only, no Fortran) |
| 2 Compile | `configure`, Makevars rules, `R CMD config`, and installing pkgbuild, pak and their dependencies from source | base + compilers + build-tools archives in one directory (unix: build-tools optional where the host has make) | + r-zig-toolchain (r-zig-compilers and r-zig-build-tools) | + r-zig-toolchain (r-zig-compilers and r-zig-build-tools) |
| 3 Develop | `R CMD check`, `Rd2pdf`, vignettes | host tools found on PATH when used (unchanged) | the same | the same |

verify-bundle's three scenarios follow these tiers: base alone; base +
compilers; base + compilers + build-tools.

## Caveats (the user's, verbatim) and what each implies

> * "Full" is not just "slim plus a toolchain." `readline`, NLS, and the image formats are R build options.
>    * Future check: We will eventually see which full-only features can become add-on R components (starting with `tcltk`), and drop the separate full build only if `readline`/NLS can be settled.

- The base stays per flavor; only the toolchain becomes per platform.
- Windows builds full but names it slim today (env.sh:17-23,
  build.zig:401-406): `R-4.6.1-slim-win-64.zip` holds tcltk, jpeg, tiff
  and NLS, and so does conda's win-64 r-zig-slim. B42 = (a): it keeps the
  name slim on every channel, documented as having full's content; a
  really slim Windows slim is a later aim.
- The future check is in "Later and future checks".

> * "Minimal" remains a separate R build (`ICU`, OpenMP, and `libdeflate` are linked into `libR`).

- minimal keeps its own base archive and stays the wheel's R.
- It has no libomp, so the shared `openmp/` must not switch OpenMP on
  for it (B40).
- verify-bundle's base + compilers scenario on minimal runs without the
  OpenMP checks.

> * Windows still requires `sh`/`make` for R's make-based package installation (for now).

- install.R hard-codes `make` and runs `sh ./configure.win`
  (install.R:174, 1297-1316, 1431, 2619); `R CMD config` runs
  `sh config.sh` (rcmdfn.c:532-533). The Windows build-tools group
  carries them in `usr/bin/`: which tools is B39, where they come from
  is B11 (conda-forge's packages, `m2-*` where needed), and R puts that
  directory on PATH (B25).
- The brief names sh, make and coreutils. conda's r-zig-toolchain also
  needed sed, grep, gawk, which and findutils after a real failure
  (recipe.yaml:414-442). B39 = (a): the set includes them, and B43 adds
  pkg-config. The stress suite reassesses the list (D15 = a).
- Depending less on make is a later aim ("Later and future checks").

> * Windows `binutils` living in `binutils/` means `Makeconf` will name each tool explicitly instead of routing through `BINPREF`.

- BINPREF is `$(R_HOME)/bin/toolchain/` (build.zig:1787) and serves both
  rzig (gcc.exe, g++.exe) and the binutils. Makeconf.win
  (zigbuild/config/win-x86_64-full/Makeconf.win) names a binutils-like
  tool through BINPREF on lines 75 (pkg-config), 76 (dlltool, `--as`),
  78 and 204 (nm), 79 (windres), 103 (ar), 211 (objdump), 213 (ranlib),
  251-252 (strip) and 267-269 (the LTO gcc-ar, gcc-nm, gcc-ranlib).
- With B24 and B43 as answered, each line names one place:
  - rzig (in TC itself): AR (103) as `$(BINPREF)zig-ar` and RANLIB (213)
    as `$(BINPREF)zig-ranlib`, the names unix's Makeconf uses; the LTO
    gcc-ar (267) and gcc-ranlib (269) keep their lines, and rzig answers
    to those names.
  - `TC/binutils/` (conda-forge's copies): nm (78, 204, and the LTO
    gcc-nm, 268), dlltool and its `--as` (76), windres (79), objdump
    (211), strip (251-252).
  - `TC/usr/bin/` (B39's directory): pkg-config (75). The line names it
    bare, `pkg-config`, as lines 86 and 215 name `sed`. R puts
    `TC/usr/bin` first on PATH (B25), and in a conda env the package's
    file is in `Library/bin`, not under R_HOME, so a bare name is what
    lets one Makeconf.win serve both channels.
  - BINPREF itself stays for gcc and g++ (and the rzig names above).
- dlltool, windres, strip, nm and as move from `binutils/` to rzig one by
  one, as rzig can serve them (B24; checked in phase 3).
- gcc-nm, pkg-config and objdump are reassessed after the stress suite
  shows what is really needed and what zig cc and rzig already cover
  (B43).
- No R code reads BINPREF (grep of src/library, src/scripts, share);
  CRAN packages' Makevars.win were not surveyed.

> * `verify-bundle` must cover three scenarios: base alone, base + compilers, and base + compilers + minimal.

- The user's "minimal" here is the minimal build tools group. This plan
  calls it build-tools (B38 a), because minimal is also an R flavor and
  the wheel's R.
- Today verify-bundle.sh opens one archive (57-74) and compiles with the
  build env's make and flang and `ZIG_BIN=$ZIG` (323-345). In the
  standalone tree, base alone is tested only by hermetic-check.sh on a
  copy of the tree with all of TC deleted (hermetic-check.sh:88-91);
  conda's recipe/test-preflight.R and wheel-test.sh:131-137 test their
  channel's base alone. Neither group scenario exists.
- From phase 3 every phase runs the three scenarios on every OS
  ("Verification").

## Principles and constraints (carried forward)

- **The user's aim:** "a single build path that should just
  work everywhere and depend the minimum possible in OS specific or
  shell specific trickery. Allowing user to build, compile, and install
  packages from a unified toolchain."
- **Both zigs** (2026-10-04/05, feat-no-host-paths PLAN.md, F4): R and
  packages build with conda-forge's zig and with upstream zig (PyPI
  ziglang); upstream is the reference, a conda-forge quirk gets an
  isolated workaround only. The upstream-zig CI legs are a gated release
  check (.github/workflows/upstream-zig.yaml: PR label, `v*` tags,
  dispatch). These answers are not part of this plan but constrain it.
- **The standalone toolchain ships upstream zig** (decided 2026-09-29,
  feat-no-host-paths PLAN.md:444-446); conda keeps conda-forge's zig.
- **zig is pinned by exact version** (0.16.0), never by build number.
  Windows is MinGW (`-windows-gnu`) everywhere.
- **rzig decides the environment** from its own path and never reads
  `CONDA_PREFIX` (environment.zig:7-32).
- **The installed tree is the shipped tree, restated:** every archive is
  a file selection of one installed tree. A base archive is its
  flavor's R tree; a group archive is the platform's toolchain tree
  (B30 a). `package` only archives; nothing is added at packaging time.
- **Fold logic into build.zig and rzig,** not into shell steps that
  differ by OS.
- **Work style.** Each phase in a worktree, reviewed, tested on
  linux-64 here, osx-arm64 and osx-64 (Rosetta) on omicron, win-64 on
  kappa, then CI. The user makes every commit (hand over the commands);
  docs-only commits carry `[skip ci]`.

## What exists today (HEAD 9bbce0b, checked 2026-10-07)

### The three channels

- **conda** (recipe/recipe.yaml). One staging output, `r-zig-build`,
  whose build.sh runs scripts/zig-build.sh with the env as the prefix.
  Two packages split by directory:
  - r-zig-slim excludes `lib/R/bin/toolchain/**` and
    `Library/lib/R/bin/toolchain/**` (279-285). Its run dependencies
    include llvm-openmp (305; headers and runtime in one package).
  - r-zig-toolchain holds exactly those (396-405), with
    `run_exports: false`, and run-depends on
    `pin_subpackage("r-zig-slim", exact=True)`, `zig 0.16.*`, flang-zig,
    flang-rt-zig and `make >=4.4` (452-455). On win-64 it adds m2-bash,
    m2-sed, m2-grep, m2-gawk, m2-coreutils, m2-make, m2-which and
    m2-findutils (410-442), after real failures (pak: `sed: command not
    found`).
  - Build number 4 (120). universe has r-zig-slim `_2`, `_3`, `_4` and
    r-zig-toolchain `_4` on all five subdirs (fetched 2026-10-07).
    r-zig-toolchain `_4` holds rzig ×5 on unix (152,824-182,732 B per
    package) and rzig ×5 plus the 8 binutils on win-64 (2,508,022 B).
  - conda-publish uploads with `--skip-existing` (pixi.toml:461-479), so
    a build number already on the channel is not uploaded again.
  - In the conda build the prefix is the env, so installOpenMP, the env
    runtime and vendor-libs.sh are skipped; those files come from
    conda's own packages at conda's paths.
- **PyPI** (scripts/make-wheel.py; the `wheel` env, linux and macOS
  only). It reads the installed minimal tree and splits on
  `TOOLCHAIN_PREFIX = "lib/R/bin/toolchain/"` (52, 399-402).
  - r-zig: the rest of the tree under `r_zig/R/` (50,507,743 B on
    linux-64, 2026-10-03).
  - r-zig-toolchain: rzig ×5 and minimal's make (892,229 B), with
    Requires-Dist `r-zig==<ver>` and `ziglang>=0.16.0,<0.16.1`
    (make-wheel.py:333-334; the constant at 58).
  - etc/Renviron.site sets `ZIG_BIN=${ZIG_BIN-${R_ZIG_ZIGLANG}}` to the
    sibling ziglang (229-241); etc/Renviron gets the pip hint unless a
    hint line exists (244-250).
  - Tags are computed over both wheels' files together (404).
  - `--prefix` defaults to `dist/R-<ver>-<variant>-zig` (350).
  - Neither name is published on PyPI yet (feat-wheel-minimal PLAN.md,
    open items).
- **Standalone** (scripts/package-standalone.sh). One archive of the
  whole installed tree: `dist/R-<ver>-<flavor>-<plat>.tar.gz` (Windows
  `.zip`) and a `.sha256` (41-52). Its top directory is the prefix's
  basename, `R-<ver>-<flavor>-zig` (15-20). Seven scripts default to
  that prefix (zig-build.sh:19, zig-package.sh:7, zig-verify-package.sh:7,
  zig-smoke.sh:7, zig-contract.sh:7, verify-tree.sh:60,
  hermetic-check.sh:43), and so does make-wheel.py's `--prefix` (350).
  env.sh:29 defines its own `PREFIX`, `dist/R-$R_VERSION-$FLAVOR`, with
  no `-zig` suffix. CI packages the default and minimal legs and runs
  verify-package on them (.github/workflows/build-r.yaml:110); it
  uploads only the wheels (121-127). There is no release job.

### R_HOME/bin/toolchain and the compile-time files outside it

- unix: rzig ×5; minimal also gets conda-forge's GNU make 4.4.1
  (build.zig:910-917), and minimal's etc/Renviron gets
  `R_ZIG_MAKE=${R_HOME}/bin/toolchain/make` and
  `MAKE=${MAKE-${R_ZIG_MAKE}}` (build.zig:3653-3657). slim and full have
  `MAKE=${MAKE-'make'}`, the host's make.
- Windows: rzig as gcc.exe, g++.exe, zig-fc.exe, zig-cc and zig-cxx, and
  plain copies of conda-forge's MinGW ar, ranlib, nm, dlltool, strip, as,
  ld and windres (build.zig:1763-1766): 13,642,752 B, GPL-3.0-only, all
  importing zstd.dll. zstd.dll is in `R_HOME/bin/x64` (R.dll imports it
  too), and the binutils find it there only because every `R CMD` puts
  `R_HOME\bin\x64` first on PATH (rcmdfn.c:418-424).
- installOpenMP (build.zig:2947-2963) puts omp.h, ompx.h, omp-tools.h
  and ompt.h in `<top>/include` (Windows `Library/include`: omp.h and
  ompx.h) and, on Windows, libomp.lib in `Library/lib`. These are the
  only files in those directories. Its comment still says "Phase T's
  standalone toolchain archive takes the headers and the import library
  over".
- On Windows vendor-libs.sh copies libomp.dll into `R_HOME/bin/x64` only
  when `Library/lib/libomp.lib` exists (vendor-libs.sh:96-100). It walks
  every PE in the whole prefix (88), so the dependencies of anything
  under TC land in the base.

### How a compile finds its tools

- **zig:** `ZIG_BIN` when it names an executable, else `zig` or
  `x86_64-w64-mingw32-zig` on PATH, else `python3 -m ziglang`
  (find_zig.zig:15-23). With nothing, the only output is
  `<shim>: cannot run python3: FileNotFound` and exit 127
  (main.zig:272-278); it never mentions zig.
- **flang:** PATH only (flang_rt.zig:45-46). Without one zig-fc exits 127
  with "no flang on PATH ... the wheels and the standalone tree bring
  none: install LLVM flang" (fortran.zig:62-68), a text pinned by a unit
  test and by wheel-test.sh.
- **Fortran runtime:** rzig asks the flang it found for
  `-print-resource-dir` and links `<dir>/lib/*/libflang_rt.runtime.a`
  (flang_rt.zig). FLIBS is `-lflang_rt.runtime -lm` on unix and
  `-lflang_rt.runtime -lc++` on Windows.
- **environment:** rzig's own (above) plus `R_ZIG_EXTRA_ENV`
  (environment.zig:66-89). For each, `-I<dir>/include` (Windows
  `-idirafter`) on every compile and `-L<dir>/lib` (plus `-rpath` for a
  conda env) on links (compiler.zig:107-152). A `-fopenmp` link gets
  `-lomp` when an environment has `include/omp.h` (environment.zig:91-99).
- **make, sh:** unix from etc/Renviron's MAKE; unix R does not change
  PATH. Windows: install.R's `make` and `sh` from PATH; nothing in r-zig
  adds TC or a usr/bin to PATH. R's own hook for that,
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_RTOOLS45_PATH}};${PATH}/"`, ships
  commented out in etc/Rcmd_environ:38-42 (installed as gnuwin32 ships
  it, build.zig:1518) and disabled in Rprofile.windows:64-87
  (`setRtools45Path <- 0`, line 66).

### The preflight, the hint and R CMD config

- **Patch 0009** stops a compiled-code install when
  `R_HOME/bin/toolchain/zig-cc` does not exist (0009:27), the CC that
  Makeconf names does not exist, there is no user Makevars and
  `R_ZIG_NO_PREFLIGHT` is unset. The message ends with
  `R_ZIG_TOOLCHAIN_HINT`, or "install the r-zig toolchain package for
  this R".
  - The Makeconf-CC fallback adds nothing in any installed tree: on unix
    it tests the same zig-cc; on Windows it reads `R_HOME/etc/Makeconf`,
    which does not exist (Makeconf is in `etc/x64`), and its tryCatch
    returns FALSE.
- **Patch 0010** makes `R CMD config` fail with "needs make, which comes
  with the r-zig toolchain" when `${MAKE%% *}` is not found. build.zig
  installs the same patched script as Windows' `bin/config.sh`, so the
  check also runs on Windows once `sh` is found. (The old plan said
  Windows had no such check; that was wrong.) Rcmd.exe reads only
  etc/Rcmd_environ (rcmdfn.c:256-265), so a hint in Renviron.site is not
  in its environment when it starts from a shell; started from an R
  session (install.R:1308-1310, pkgbuild, pak) it inherits R's
  environment, Renviron.site's hint included.
- **The hint** is written only for conda (zig-build.sh:57-66 passes
  `-Dtoolchain-hint`; build.zig writes etc/Renviron, or etc/Renviron.site
  on Windows) and by the wheel. The standalone tree has none.

### Checks

- hermetic-check.sh copies the tree and deletes all of TC to simulate
  the base (88-91). It checks the preflight message and, on unix,
  `R CMD config` "needs make".
- verify-bundle.sh: one archive (57-74); its compiles use the build
  env's make and flang and `ZIG_BIN=$ZIG` (323-345).
- verify-tree.sh: rzig copies compared by cmp (73-84); the 2.28 glibc
  ceiling for `lib/R/bin/toolchain/*` (466-493); the DLL closure check
  accepts `R_HOME/bin/x64` for any PE (343-345).
- Tests that encode "TC/zig-cc exists = toolchain installed":
  recipe/test-preflight.R:4, recipe/test-toolchain.R:3,
  scripts/wheel-test.sh:117 and 265-271, make-wheel.py:364-365, and
  hermetic-check.sh:91.
- No LICENSES or SOURCES are installed anywhere. make (minimal, wheel)
  and the Windows binutils are redistributed with R's COPYING only.

### Open PRs and the channel (2026-10-07)

- **#14** (fix-rzig-baseline-cpu, 481255d): rzig passes `-mcpu=baseline`
  on every OS (Windows package compiles were native: kappa "skylake"),
  verify-bundle gets a baseline-CPU check, and the recipe's build number
  goes 4 → 5.
- **The re-lock** (worktree chore-relock-flang-rt-10, uncommitted): pins
  `flang-zig ==23.1.1 *_6`, `lld-zig ==23.1.1 *_5` and
  `flang-rt-zig ==23.1.1 *_10` in the recipe's staging build (all
  three), host (flang-rt-zig only) and r-zig-toolchain's run (all
  three), and the same in pixi.toml; build number stays 4 because #14
  bumps it.
- **#15** (this branch): phase 1. On CI run 37628782590, conda-package
  passed on linux-64, linux-aarch64 and osx-arm64, and every linux build
  leg passed. conda-package osx-64 and win-64 failed, and so did all
  seven macOS and Windows build legs (macos-latest and macos-15-intel
  default, full, minimal; windows-latest default). All nine stopped at
  `pixi install` with a 404 on flang builds that flang-pixi deleted (for
  example flang-zig `_5` on osx-64 and flang-rt-zig `_4` on win-64; job
  logs read 2026-10-07). #14 failed the same nine jobs.
- **flang-pixi** published flang-zig 6, lld-zig 5 and flang-rt-zig 10 on
  2026-10-07 (zig 0.16.0, LLVM 23.1.1) and deleted every older build.
  flang-rt-zig 10 depends on `llvm-openmp >=23`. Download sizes of
  flang-zig: 124.5 MB (linux-64), 120.1 (linux-aarch64), 106.4
  (osx-64), 98.7 (osx-arm64), 205.8 (win-64); lld-zig win-64 108.2 MB.
- **The published r-zig-toolchain `_4`** run-depends on flang-zig and
  flang-rt-zig with no pin. Installs that resolve `_4` will take
  flang-pixi's 0.17 builds (7 and 11) when they appear. Only a published
  build carrying the re-lock's exact pins avoids that: the re-lock must
  be on main when #14's bump to 5 publishes.

## Facts the design depends on (carried forward, condensed)

- **PyPI's ziglang is ziglang.org's build.** For 0.16.0 the zig binary
  and all 19,541 lib files are byte-identical (feat-no-host-paths
  PLAN.md:782-787). scripts/fetch-zig.sh pins the five 0.16.0 wheels by
  sha256 and unpacks `ziglang/` (19,546 files; lib/ 184,249,850 B;
  dist-info licences 15 files, 119,414 B). ziglang.org asks automated
  downloaders to use its community mirrors and verify with minisign.
- **flang relocates; its own executable links do not** (flang-pixi
  docs/19 §2-§5, handoff §8).
  - The compile set (table in "The toolchain groups") compiles hello, a
    derived-type module, `use omp_lib` and OpenMP directives with
    nothing else on PATH on linux-64, osx-arm64, osx-64 and win-64; zig
    links the objects with the runtime archive (unix `-lm`, plus `-lomp`;
    Windows our libomp import library). No lld, sysroot, SDK path or
    MinGW CRT snapshot. The executables load only system libraries.
  - No flang.cfg on linux and Windows. macOS needs
    `-fintrinsic-modules-path <root>/lib/clang/23/finclude/flang/<conda triple>`,
    which zig-fc can pass; zig-fc already passes
    `-mmacosx-version-min=13.0` (fortran.zig:58).
  - flang's own driver link needs ld.lld and conda's sysroot (linux),
    SDKROOT and a linker (macOS), or ld.lld and the CRT snapshot
    (Windows). So configure probes that link through flang's driver
    fail outside conda.
  - Sizes of the set: raw 143.9-210.0 MB, of which the driver is
    136-196 MB.

    | subdir | raw | gzip -9 | zstd -19 | xz -9 |
    |---|---|---|---|---|
    | linux-64 | 210.0 MB | 62.2 MB | 43.9 MB | 39.3 MB |
    | linux-aarch64 | 195.9 MB | 58.9 MB | 41.3 MB | 34.7 MB |
    | osx-arm64 | 143.9 MB | 45.1 MB | 30.5 MB | 25.9 MB |
    | osx-64 | 157.3 MB | 50.3 MB | 35.0 MB | 31.8 MB |
    | win-64 | 190.1 MB | 58.0 MB | 40.1 MB | 35.6 MB |
- **Still ours for Fortran** (old Design 5; done in phase 6, 2026-10-16,
  "Phase 6 record: what changed"):
  - zig-fc sends every link through zig: a call with sources and a link
    becomes `flang -c` per source plus the zig link with the runtime
    archive. This reverses F3c's "a mixed call stays flang's"
    (fortran.zig:1-30) and is what configure's `$FC` probes need.
  - zig-fc passes `-fintrinsic-modules-path` on every compile, found from
    flang's own location. Answered in phase 6: passing it beside a conda
    env's flang.cfg (the same directory twice) is harmless (PHASE6 PP),
    and the triple is a directory scan (PHASE6 open point D a).
  - rzig finds the runtime under `TC/flang/` through
    `-print-resource-dir`; on Windows, without the `Library/` prefix.
  - The driver ships once, as `flang` (`flang.exe`): zig 0.16's install
    step copies a symlink's target (std/Build/Step.zig:525-531), so
    installing flang-23 and its link would store 196 MB twice. The same
    holds for the linux module-directory symlink ("The toolchain
    groups").
- **Windows FLIBS' `-lc++`** (checked 2026-10-06 on flang-rt-zig build 4's
  win-64 archive): 131 external undefined names, none from the C++
  runtime; a cross link of a Fortran exe and DLL succeeds without it, and
  with it the DLL is the same. So the `-lc++` in Windows FLIBS
  (build.zig:1836 before phase 6), in rzig's flibs (fortran.zig:75) and
  linkFortranRt's `link_libcpp` (build.zig:2833 before phase 6) look like
  no-ops. Re-checked on build 10 (PHASE6 ST §4, SR §2): no runtime
  archive references a C++ runtime symbol on any OS; the only
  C++-looking one is `__cxa_atexit` (`___cxa_atexit` on macOS), which
  libc or libSystem defines. Phase 6 drops all three (open point K a):
  rzig's Windows flibs and Makeconf.win's FLIBS are `-lflang_rt.runtime`
  alone, and linkFortranRt has no `link_libcpp`. omicron's and kappa's
  runs (2026-10-17) confirm every drop: libR, Rblas and Rlapack on
  macOS are the same bytes either way, and R.dll imports no C++ runtime
  ("Phase 6 record: tests on every host").
- **Windows userland facts.** GNU make on Windows runs simple recipe lines
  without a shell, so rm, cp, sed and the rest must be real .exe files.
  busybox-w32's make applet (pdpmake) cannot parse Makeconf.win
  (`$(if)`, `$(patsubst)`, `$(shell)`). configure.win runs as
  `sh configure.win`, and R-exts says bash since R 4.2.0, so busybox ash
  may not be enough (B11's answer takes no busybox). winshlib.mk runs
  `$(NM)` on every package DLL link without a `<pkg>-win.def`
  (winshlib.mk:15-27), so nm is required.
- **conda-forge's Windows tools in pixi.lock** (checked 2026-10-08):
  native win-64 builds of make 4.4.1 (hba3369d_3), uutils-coreutils
  0.0.20 (hd956f44_0) and pkg-config 0.29.2 (hffdb5b9_1013); and the
  noarch `m2-*` packages of MSYS2 (msys2-runtime 3.6.1.4) for bash, sed,
  grep, gawk, which, findutils, coreutils and make, among others
  (pixi.toml:247-261). Whether conda-forge has native win-64 builds of
  the others is phase 7's check. Answer (PHASE7's package survey, PS
  §4): none for bash, sed, grep, gawk, which, findutils, GNU coreutils,
  diffutils or busybox; native make and uutils-coreutils exist and were
  not taken (B11's phase 7 outcome); uutils 0.0.20 is a 73-name
  multicall binary without touch, uname or chmod.
- **zig's own binutils-like commands** (conda-forge zig 0.16.0, run
  2026-10-07): ar, ranlib, dlltool (llvm-dlltool; its help lists only
  short options), rc (resinator: rc.exe syntax, not windres'
  `-i $< -o $@`), objcopy (ELF only) and objdump (a stub). No nm, no
  windres, no as, no PE strip.
- **macOS without the Command Line Tools** (simulated, Phase 0): xcrun
  exits 1 at once, rzig drops the SDK flags silently, plain C links,
  `-framework` fails. Whether a Mac that never had the CLT opens the
  install dialog is unobserved.
- **conda-forge's make** carries dead compiled-in build paths
  (`/home/conda/feedstock_root/...`, `/Users/runner/...`; win-64
  `D:\bld\...` in debug sections); none names our build machine.
- **The two zigs' code** (FLANG_PIXI_HANDOFF.md §8): with the same
  explicit flags, upstream and conda-forge zig emit the same machine
  code; objects differ in the clang version string, linked programs in
  NEEDED. Measured on linux-64 with
  `-target x86_64-linux-gnu.2.17 -mcpu=baseline`.
- **Licences** of what the groups carry:

  | Component | Licence |
  |---|---|
  | zig | MIT; libc and libc++ notices in the wheel's dist-info/licenses |
  | GNU make, binutils, the MSYS2 tools | GPL-3.0 or GPL-3.0-or-later |
  | pkg-config (B43) | GPL-2.0-or-later |
  | busybox (not used: B11) | GPL-2.0-only |
  | flang, flang-rt | Apache-2.0 WITH LLVM-exception |
  | llvm-openmp | Apache-2.0 WITH LLVM-exception |

  GPLv3 §6(d) allows the source on another server with clear directions
  next to the binary. GPLv2 §3 wants it "from the same place" or a
  written offer.
- **Sizes, per group, estimated from Phase 0 and flang-pixi** (zig: gzip
  -6 / xz -6 / zstd -19, Phase 0; flang: gzip -9 / xz -9 / zstd -19,
  flang-pixi; each group figure is a sum of two streams):

  | platform | zig: gzip / xz / zstd | flang set: gzip / xz / zstd | compilers group, about |
  |---|---|---|---|
  | linux-64 | 86.6 / 57.4 / 61.3 MB | 62.2 / 39.3 / 43.9 MB | 149 / 97 / 105 MB |
  | linux-aarch64 | 83.6 / 52.8 / 59.1 MB | 58.9 / 34.7 / 41.3 MB | 143 / 88 / 100 MB |
  | osx-arm64 | 85.9 / 54.0 / 59.8 MB | 45.1 / 25.9 / 30.5 MB | 131 / 80 / 90 MB |
  | osx-64 | 89.9 / 59.5 / 63.2 MB | 50.3 / 31.8 / 35.0 MB | 140 / 91 / 98 MB |
  | win-64 | 87.3 (zip 98.9) / 58.2 / 62.1 MB | 58.0 / 35.6 / 40.1 MB | 145 (zip about 157, with flang's gzip -9 standing in for its zip) / 94 / 102 MB |

  - The OpenMP group is about 145 KB raw on unix (the four headers of
    llvm-openmp 23.1.2; about 23 KB with tar and gzip -6) and about
    226 KB on win-64 (omp.h, ompx.h, libomp.lib; about 31 KB).
  - build-tools: unix make 0.12-0.17 MB gzip; win-64 binutils with rzig
    were 7.4 MB gzip (rzig leaves for the base), make.exe 4.8 MB gzip
    unstripped or 0.15 MB stripped, plus the userland (B11, B39).
  - The base: linux-64 slim's archive of 2026-10-03 is 73.8 MB, its TC
    0.74 MB of it.

## Resolved decisions

No decision is open. Every B decision and every related item of the
2026-10-07 menu is answered (2026-10-07 and 2026-10-08), and so is T1,
a later question of the same day. What still comes back with results
is listed at the end of this section.

### The answers of 2026-10-07

The user's answers of 2026-10-07, as given:
- **B1 = (a):** one top directory for all archives. (Old decision 1,
  widened from one toolchain archive to one archive per group.) Its
  consequence for the top directory's name is B36.
- **B2 = (a):** `ZIG_BIN` → rzig's own `zig/` → PATH →
  `python3 -m ziglang`; flang from rzig's `flang/` then PATH; output a
  no-zig message that explicitly names the toolchain. (Old decision 4.)
  B34 refines it; B35 says where the message text comes from.
- **B19 = (a):** rzig resides in the base: the standalone base archive,
  r-zig-slim and the r_zig wheel.
- **B20 ≈ (a):** the group design detailed above applies (compilers:
  `zig/`, `flang/`, `openmp/`; minimal build tools: unix make, Windows
  `usr/bin/` and `binutils/`; optional extras later). Point 3 also
  settles the records: every group directory has its own `LICENSES/` and
  `SOURCES`.
- **B21 = (a):** external runtime libraries stay with the base. B27 says
  where exactly.
- **B22 = (a):** OpenMP compile files go in the compilers group
  (`TC/openmp/`). This was old decision 7's option c; its old
  recommendation (keep them in the base) is reversed. B40 keeps it off
  for minimal, B41 accepts conda's exception.

Done:
- **B16** (old 14), the recipe's host which/sed/grep cleanup: phase 1,
  committed in 9bbce0b (PR #15). Its conda-package runs on omicron and
  kappa, CI's osx-64 and win-64 conda-package jobs and the seven macOS
  and Windows build legs are still to pass (History).

Earlier answers that are not part of this plan but constrain it: both
zigs keep working (conda-forge's zig and upstream/PyPI zig), and the
upstream-zig CI legs are a gated release check ("Principles and
constraints").

### The answers of 2026-10-08

The user's reply to the menus, verbatim:

> all ★ execpt:
>
> * B11: Get all tools from conda-forge, look for m2-* variant of pacakges if needed.
> * B24: conda-forge copies `binutils/` for now, but keeping rzig routing for what is possible.
> * B42: keep "slim" everywhere and document that it has full's content (But keep notes that we want to work on that and make slim really slim, but later).
> * B43: rzig answers to `gcc-ar`/`gcc-ranlib`, and Windows `AR`/`RANLIB` also go through rzig as on unix. `gcc-nm`, `pkg-config` and `objdump` can come from conda-forge, but we need to reaccess after the stress suite decide what is really needed and what zig cc/rzig already covers.
> * B44: fortran through flang should succeed, we can work the flang-zig project to fit our needs.
> * D6: b - rzig deals with the import library, do not report anything yet.
> * A2: Do not file any report
> * D1: Strip Linux debug info
> * D2: Keep `flang`
> * D3: b - Fix it.

What it means for this plan:
- "all ★" takes the recommended option, (a), for B4, B6, B7, B9, B12,
  B13, B14, B17, B18, B23, B25, B26, B27, B28, B29, B30, B31, B32,
  B33, B34, B35, B36, B37, B38, B39, B40 and B41. Each record under
  "Decision records" says what its (a) is.
- **B42 = (a)**, with a note: Windows keeps the name slim on every
  channel, documented as having full's content; the user wants to make
  Windows slim really slim later ("Later and future checks"; it relates
  to C1, Windows minimal).
- **B11, B24, B43 and B44** are the user's own answers:
  - **B11:** every Windows `usr/bin` tool comes from a conda-forge
    package: a native win-64 build first, an `m2-*` package where
    conda-forge has no native one. The same packages serve both
    channels: the standalone build-tools group copies them into
    `TC/usr/bin/` with their DLL closure, and conda's r-zig-build-tools
    depends on them. There is no busybox-w32 prototype. Phase 7 chooses
    the packages for B39's list, copies them and tests them on kappa and
    CI.
  - **B24:** conda-forge's MinGW binutils stay as copies in
    `TC/binutils/` for now, but every tool rzig can serve goes through
    rzig: now ar and ranlib (B43). For dlltool, windres, strip, nm and
    as, phase 3 checks whether rzig can route them (zig's dlltool, rc
    and objcopy are the candidates) and moves each one that works; the
    copies stay only for the rest.
  - **B43:** rzig answers to `gcc-ar` and `gcc-ranlib` (two new rzig
    names), and Makeconf.win's AR and RANLIB go through rzig as on unix
    (`zig-ar`, `zig-ranlib`). gcc-nm, pkg-config and objdump come from
    conda-forge: pkg-config into `TC/usr/bin/` (so B39's list gains
    it), objdump into `TC/binutils/`. gcc-nm ships, from conda-forge,
    only if really needed (B43-2, below). All three are reassessed after
    the stress suite shows what is really needed and what zig cc and
    rzig already cover.
  - **B43 follow-ups (2026-10-08):** B43-1 (a): Windows AR and RANLIB
    are `zig-ar`/`zig-ranlib` as on unix, plus `gcc-ar`/`gcc-ranlib`
    (four rzig copies). B43-2, the user's: "Ship from conda-forge if
    really needed": no gcc-nm ships now and Makeconf.win's gcc-nm line
    (268) is not pointed at binutils' nm; a real gcc-nm from
    conda-forge's MinGW GCC comes only if the stress suite shows a
    package needs it. B43-3 (a): Makeconf.win names a bare
    `pkg-config`.
  - **B44:** Fortran through flang must succeed on every OS. If phase
    6's prototype fails on an OS, the fix is made together with
    flang-pixi (the flang-zig project), which we can adapt to our needs;
    no OS ships its compilers group without `TC/flang/`.
- "A2", "D1", "D2", "D3" and "D6" are items of the same 2026-10-07 menu
  (next section).

| ID | Question | Answer (2026-10-08) | Blocks |
|---|---|---|---|
| B4 | zig's artifact for the standalone compilers group | (a) PyPI's ziglang wheel as fetch-zig pins it | phase 5 |
| B6 | Which zig builds the released standalone R | (a) upstream, once a release job exists | the release job |
| B7 | Where unix make comes from | (a) conda-forge's 4.4.1 from the build env | phase 3 |
| B9 | Where flang's compile set comes from | (a) copied from the build env, SOURCES from conda-meta | phase 6 |
| B11 | Where Windows' usr/bin tools come from | the user's: conda-forge packages, native first, `m2-*` where needed | phase 7 |
| B12 | Publishing | (a) CI artifacts now, release job later | phase 3 |
| B13 | Compression | (a) gzip/zip now, measure after phase 6 | phases 3, 6 |
| B14 | conda build number | (a) bump in phase 4's PR and in each later PR that changes a package; amended 2026-10-19: no bump in phases 4, SHLIB routing, 5 and 6, the next with phase 7's merge | phases 7, 9 |
| B17 | Archive names | (a) working names, groups without flavor | phase 3 |
| B18 | The zig 0.17 wave | (a) upstream leads on the gated legs, conda waits for conda-forge | not phases 2-9 |
| B23 | Where unix make sits | (a) `TC/usr/bin/make` | phase 3 |
| B24 | Windows binutils | the user's: conda-forge's copies in `binutils/` for now, rzig routing for what is possible | phase 3 |
| B25 | How R finds the build tools | (a) `TC/usr/bin` first on PATH, MAKE stays `make` | phases 3, 7 |
| B26 | What tells R a group is missing | (a) rzig's check mode for every group, called by patches 0009 and 0010 | phases 2, 3 |
| B27 | Where the base's runtime files sit | (a) conda's prefix paths, two moves | phase 8 |
| B28 | conda packages | (a) r-zig-slim, r-zig-compilers, r-zig-build-tools and the r-zig-toolchain metapackage, one recipe | phase 4 |
| B29 | PyPI packages | (a) r-zig, r-zig-compilers, r-zig-build-tools, r-zig-toolchain; no Fortran | phase 4 |
| B30 | Where the groups are assembled | (a) a toolchain tree per platform; R trees hold the base only | phase 3 |
| B31 | CI for one toolchain per platform | (a) a toolchain job per subdir; the packaging legs run the three scenarios | phase 3 |
| B32 | zig version check | (a) the check mode fails on another major.minor | phase 2 |
| B33 | Licences and sources for the base's runtime files | (a) in this plan (phase 8) | phase 8 |
| B34 | Refinement of B2 | (a) R's own environment's `bin/` after `zig/` (`flang/`), before PATH | phase 2 |
| B35 | The text that names a missing group | (a) one text built into rzig, the same on every channel | phases 2, 4 |
| B36 | The shared top directory | (a) `R-<ver>-zig/`, dev trees under `dist/<flavor>/` and `dist/toolchain/` | phase 3 |
| B37 | How this plan lands | (a) #15 merges with phases 0-1 and these docs, then one PR per phase | phase 2, B14 |
| B38 | Group names | (a) compilers, build-tools | phases 2, 3, 4 |
| B39 | What Windows' usr/bin holds | (a) sh, make, coreutils, sed, grep, gawk, which, findutils; pkg-config joins through B43 | phases 4, 7 |
| B40 | How rzig decides OpenMP is available | (a) only when the base has the libomp runtime | phase 2 |
| B41 | conda's exceptions to the shared boundary | (a) omp.h with the base and the win-64 binutils copies, accepted and recorded | phase 4 |
| B42 | Windows' flavor name | (a) slim on every channel, documented; a really slim Windows slim later | phase 3 |
| B43 | Makeconf.win's tools r-zig did not ship | the user's: AR, RANLIB, gcc-ar and gcc-ranlib through rzig (B43-1 a: `zig-ar`/`zig-ranlib` as on unix); pkg-config (bare name, B43-3 a) and objdump from conda-forge; gcc-nm from conda-forge only if really needed (B43-2); reassessed after the stress suite | phases 2, 3, 7 |
| B44 | Fortran on an OS whose phase 6 prototype fails | the user's: Fortran through flang must succeed on every OS, fixed with flang-pixi | phase 6 |

### Related items of the 2026-10-07 menu, answered 2026-10-08

The items that touch this plan:
- **D6 = (b):** "rzig deals with the import library, do not report
  anything yet." For upstream zig on Windows, which has no
  `synchronization` import library, rzig provides `-lsynchronization`'s
  import library itself (for example generated from MinGW's `.def`
  with zig's dlltool). Nothing is reported upstream. It is an rzig
  change: feat-no-host-paths PLAN.md groups it in its proposed rzig
  follow-up PR (ii). Phase 5 needs it, since the compilers group makes
  upstream zig the standalone default on Windows; if (ii) has not landed
  by then, phase 5 does it.
- **A2' (the user wrote "A2"):** "Do not file any report." The upstream
  zig report on the auto-exported MinGW atexit is not filed. build.zig's
  atexit workaround (addSharedLib's `.drectve` exclude) stays, through
  the 0.17 port too (B18).
- **D7 = (a):** CC_VER/FC_VER are refreshed with the first B14 bump,
  phase 4's (done in phase 4, which keeps build 8 since 2026-10-19: the
  first bump is phase 7's, B14's amendment).
- **D12 = (a):** rattler-build >= 0.76 with its warnings as errors.
  feat-no-host-paths PLAN.md puts it in its proposed follow-up PR (i);
  phase 4's rattler-build checks (B28) and the overlapping-files risk
  rely on it.
- **D14 = (a):** the toolchain in an environment of its own stays later
  ("Later and future checks").
- **D15 = (a):** the stress suite starts now, in parallel with this plan
  (its own branch, feat-stress-suite). It decides the extras group and
  reassesses B39's list and B43's tools.
- **E2 = (a):** zstd is declared in the recipe with the first bump,
  phase 4's (done in phase 4; the first bump is phase 7's since
  2026-10-19): in r-zig-slim (R.dll imports zstd.dll) and in win-64
  r-zig-build-tools (the binutils import it).
- **C1 = (a):** Windows minimal drops ICU, cairo, Tcl/Tk and OpenMP and
  keeps png/jpeg/tiff and NLS. **C2 = (a):** a Windows wheel without
  compile support comes first. **C3 = (a):** both come after this plan's
  phase 7, which settles the Windows build tools they share.
- **R1 = (a):** the re-lock lands as its own PR.

The same reply answered D1 (b: strip Linux debug info), D2 (a: keep
`flang` in Windows' R_SYSTEM_ABI), D3 (b: fix the build paths in the
lazy-load databases), D4 (a), D5 (a), D8-D11 (a), D13 (a), E3 (a) and
E4 (a). They are not part of this plan; feat-no-host-paths PLAN.md and
chore-lock-and-ci-refresh PLAN.md record them.

### T1 (2026-10-08): Tcl/Tk headers in the Windows base

The question came from D5 (fix-rzig-follow-ups PLAN.md). The
standalone Windows tree ships Tcl/Tk's runtime in R_HOME/Tcl (Tcl/bin,
Tcl/lib) but had no headers. A package that compiles against Tcl/Tk
then built only where rzig's environment has them: from the tree alone,
tkrplot stopped at "tcltkimg.c:3:10: fatal error: 'tk.h' file not
found" (kappa). The question: ship the env's tk headers as
R_HOME/Tcl/include, where Makeconf's TCLTK_CPPFLAGS looks, although
this plan puts compile-time files in the toolchain?

The user's answer, verbatim:

> Ship the headers in the base at R_HOME/Tcl/include, where package Makevars expect them.

**T1 = (a).** On Windows, Tcl/Tk's headers ship in the base at
`R_HOME/Tcl/include`. They are the one exception to "compile-time
files go in the toolchain" (point 2; section 2 above). The reasons:
- Packages look for them there. Makeconf.win has
  `TCL_HOME = $(R_HOME)/Tcl` and
  `TCLTK_CPPFLAGS = -I "$(TCL_HOME)/include"`, and tkrplot's
  Makevars.win names `-I "$(TCL_HOME)"/include`. It is CRAN's layout:
  R's Windows build compiles tcltk with `-I "$(TCL_HOME)"/include`
  (src/library/tcltk/src/Makefile.win), and its installer copies the
  whole R_HOME/Tcl, deleting only `Tcl/lib/*.lib`
  (src/gnuwin32/installer/Makefile:154-163).
- The headers belong to the DLLs beside them (Tcl/Tk 8.6.13, the
  threaded build) and change only with the base's Tcl/Tk.
- They are small: 13 files, 690,477 B.

What ships (fix-rzig-follow-ups: build.zig installEnvRuntime, in a
tree that is not the env): tcl.h, tk.h and tkPlatDecls.h with what they
include, from conda-forge's win-64 tk (tk-8.6.13-h967ab96_4). That is
tcl.h, tclDecls.h, tclPlatDecls.h, tk.h, tkDecls.h, tkPlatDecls.h,
tkIntXlibDecls.h, and X11/X.h, Xfuncproto.h, Xlib.h, Xutil.h, keysym.h
and keysymdef.h (Tk's stand-in for Xlib on Windows; tk.h includes
X11/Xlib.h). The package's other 15 headers stay out (tclOO,
tclTomMath, itcl, tdbc, and X11 headers that none of these include).
verify-tree.sh requires tcl.h and tk.h in Tcl/include. B33's record
for tk (phase 8) covers these files too.

Tested on kappa (2026-10-08, fix-rzig-follow-ups PLAN.md, D5): with
the extracted standalone zip, and only the env's zig, sh and make
besides (no env headers or libraries), tkrplot 0.0-32 compiles against
R_HOME/Tcl/include, links R_HOME/Tcl/bin's DLLs, loads and draws. With
R_HOME/Tcl/include moved away it stops at 'tk.h'.

The other channels do not change. conda: the tk package, a run
dependency, has the headers in `Library/include`, which rzig's
environment already searches (`-idirafter`); there is no R_HOME/Tcl
there. PyPI: none, as for Tcl/Tk itself (section 5's table): the
wheel is minimal, and Windows minimal drops Tcl/Tk (C1).

### What comes back with results (not open decisions)

- B39's list and B43's gcc-nm, pkg-config and objdump: reassessed after
  the stress suite (D15). Round 1 (2026-10-08) did it in part: see the
  notes at B39 and B43.
- B24: which of dlltool, windres, strip, nm and as move to rzig (phase
  3's check; the rest stay in `binutils/`).
- B11: which conda-forge package provides each tool, and whether
  make.exe is stripped (phase 7).
- B13: the format of any compilers archive above 150 MB, chosen after
  phase 6's measurements (part of answer a).
- B25: whether Rprofile.windows needs the PATH line too (phase 7).

## Decision records (answered 2026-10-08)

Each record keeps the context and the options as they were put to the
user on 2026-10-07/08, headed by the answer. "Recommendation" is the
recommendation the user saw.

### B4. zig's artifact for the standalone compilers group (old 2)

**Answer (2026-10-08): (a).** fetch-zig's PyPI wheel fills `TC/zig/`
(phase 5).

Context:
- zig is part of our files only in the standalone compilers group:
  conda takes conda-forge's zig and PyPI takes ziglang (architecture
  point 3: "only where conda-forge or PyPI doesn't provide it").
- scripts/fetch-zig.sh already pins the five PyPI ziglang 0.16.0 wheels
  by sha256 and downloads them with curl (fetch-zig.sh:22-67). The
  upstream-zig CI legs use it.
- The wheel's `ziglang/` is ziglang.org's release byte for byte. Its
  dist-info/licenses holds the libc and libc++ notices the group must
  ship.

Options:
- **(a)** PyPI's ziglang wheel as fetch-zig.sh pins it. `TC/zig/` gets
  `zig` (`zig.exe`) and `lib/`; `TC/zig/LICENSES/` gets its LICENSE and
  the dist-info licences; `__init__.py`, `__main__.py` and README.md are
  left out. One download path and format, the zig PyPI users run.
- **(b)** ziglang.org's tar.xz (Windows zip) from a community mirror,
  checked with sha256 and minisign, as ziglang.org asks. A second
  download path; GNU tar needs the xz program.

Recommendation: **(a)**. The same bytes as ziglang.org, through one path
that is pinned and already tested on five platforms (G2, G4).
Blocks: phase 5. Replaces: old 2 (narrowed to the standalone channel).

### B6. Which zig builds the released standalone R (old 9)

**Answer (2026-10-08): (a).** The release job (later) builds the
released standalone R with upstream zig.

Context:
- CI's default legs build R with conda-forge's zig. upstream-zig.yaml
  builds the default env with fetch-zig's zig on ubuntu-latest,
  macos-latest and windows-latest, on demand.
- With B4 the compilers group carries upstream zig. A release built by
  conda-forge's zig therefore ships the mixed case (R by conda-forge
  zig, packages by upstream zig). The wheel already ships that mix, but
  only for minimal (no OpenMP, no Fortran).
- With the same explicit flags both zigs emit the same machine code;
  they differ in the clang version string and in NEEDED (measured on
  linux-64, handoff §8).

Options:
- **(a)** Upstream zig, once a release job exists. Until then
  verify-bundle's base + compilers scenario tests the mixed case on the
  default legs and the one-zig case on the upstream legs.
- **(b)** conda-forge's zig (the default legs).

Recommendation: **(a)**. A released standalone distribution then has
one zig, the reference one (G2).
Blocks: the release job (later), not phases 2-9: answer now or later.
Phase 5 tests both cases either way. Replaces: old 9.

### B7. Where unix make comes from (old 5, its source)

**Answer (2026-10-08): (a).** Windows' make is no longer a separate
question: it comes with B11's conda-forge packages (phase 7).

Context:
- B20 puts unix make in the build-tools group, and the group is per
  platform, so every flavor gets it. Today only minimal has it
  (build.zig:910-917).
- conda-forge's make 4.4.1 links only glibc (libc and libdl; on
  linux-aarch64 also its ld.so; GLIBC_2.17) or libSystem (minos 11.0),
  and records no prefix placeholder (Phase 0).
- Windows' make is not asked here. It is needed only if B11's userland
  brings none (busybox-w32's pdpmake cannot parse Makeconf.win; MSYS2
  brings m2-make). If busybox-w32 wins B11's prototype, B11 comes back
  with that question: conda-forge's win-64 make.exe stripped (287,744 B)
  or as shipped (17,111,844 B, 4.8 MB gzip -6).

Options:
- **(a)** conda-forge's GNU make 4.4.1 from the build env (pixi.lock
  pins it), on linux and macOS.
- **(b)** GNU make 4.4.1 built from source by build.zig with zig: one
  make with no conda-forge build paths. More work.

Recommendation: **(a)**. One make, from the env pixi.lock already pins,
and the file minimal ships today (G2). (b) stays under "Later".
Blocks: phase 3. Replaces: old 5's source part; B20 settled "make for
every flavor".

### B9. Where flang's compile set comes from (old 17)

**Answer (2026-10-08): (a).**

Context:
- B20 puts flang's compile set in `TC/flang/` (the table in "The
  toolchain groups").
- build.zig already finds the env's flang and its runtime (it stops
  without one, build.zig:462-479; findFlangRt). It already copies
  third-party binaries from the env (make, the binutils).
- conda-meta's flang-zig and flang-rt-zig JSON hold name, version,
  build, URL, sha256 and each file's sha256 (`paths_data`).
- The re-lock pins the env to flang-zig 6 and flang-rt-zig 10, the
  builds flang-pixi retains on universe.
- flang-pixi's carve-fortran-standalone.py needs Python ≥ 3.14 or
  zstandard, reads the published `.conda` files, and was not committed
  on 2026-10-06.

Options:
- **(a)** Copy the set from the build env's installed flang-zig and
  flang-rt-zig in build.zig's toolchain step. `flang/SOURCES` comes
  from conda-meta, and verify-tree checks each copy against
  `paths_data`. flang-pixi's script runs once, in the phase 6
  prototype, as a cross-check.
- **(b)** Run the carve script on the published `.conda` files, pinned
  to a flang-pixi commit: Python in R's build, a second download of
  both packages, two pins to keep in step.

Recommendation: **(a)**. One install step in build.zig, no Python,
pinned by pixi.lock; the flang that ships is the one that compiled R's
own Fortran, so CRAN's rule (the Fortran compiler R was built with)
holds by construction (G2, G4).
Blocks: phase 6. Replaces: old 17. Old 6 ("which Fortran") is settled
by B20.

### B11. Where Windows' usr/bin tools come from (old 8)

**Answer (2026-10-08), the user's own:** "Get all tools from
conda-forge, look for m2-* variant of pacakges if needed."

What it means:
- Every tool of B39's list, and pkg-config (B43), comes from a
  conda-forge package: a native win-64 build where conda-forge has one,
  else the `m2-*` package (MSYS2).
- The same packages on both channels that ship Windows build tools: the
  standalone build-tools group copies their files into `TC/usr/bin/`
  with their DLL closure (`usr/LICENSES/`, `usr/SOURCES` from
  conda-meta); conda's win-64 r-zig-build-tools depends on them.
- None of the options below as written: no busybox-w32 prototype, no
  Rtools45. It is closest to (b), with native builds preferred over the
  m2 ones.
- Phase 7 chooses the package for each tool, copies them, and tests on
  kappa and CI. The msys-2.0.dll clash and the old spawn hangs stay
  recorded as risks. Whether make.exe is stripped is a phase 7 detail.

Context:
- Windows R needs sh and make on PATH (caveat above). GNU make runs
  simple recipe lines without a shell, so every tool must be an .exe.
- Which tools is B39; this decision is their source.
- conda's r-zig-toolchain brings the MSYS2 set through m2 packages
  (recipe.yaml:410-442). The standalone zip brings none.
- busybox64u.exe is 675,840 B, GPL-2.0-only, imports system DLLs only,
  and has a published SHA256SUM and source. The m2 set is about 16 MB
  compressed with its dependencies. Rtools45 is a 461 MB installer.
- Shared with feat-no-host-paths' item 2 (the Windows minimal variant
  and wheel; C1-C3), whose blocker is the same userland.

Options:
- **(a)** Prototype on kappa: busybox-w32 (sh.exe and one .exe per
  applet in B39's list) with a GNU make.exe, against the MSYS2 set. Each
  runs the contract set (C, C++, Fortran, OpenMP), pak, data.table and
  glue; plus a scan of CRAN's configure.win and configure.ucrt for
  bash-only syntax. Ship the winner in `TC/usr/bin/`. B11 comes back
  with the result and, if busybox-w32 wins, the Windows make question
  (B7's context).
- **(b)** The MSYS2 set now, from conda's m2 packages: known to work
  with R's makefiles (Rtools and our conda package use it). Its
  msys-2.0.dll may clash with a user's Rtools or Git for Windows
  (Cygwin FAQ 4.20), and windows-latest has shown spawn hangs.
- **(c)** Require Rtools45: nothing to ship; `R_CUSTOM_TOOLS_PATH`
  points at it. The user then has a second toolchain, and Windows is no
  longer "one toolchain".

Recommendation (not taken): **(a)**, with (b) as the fallback. Evidence
decides between a small set without msys-2.0.dll and the set known to
work (G1, G2). Whichever wins, the conda package uses the same set if
conda-forge packages it, else keeps the m2 dependencies.
Depends on: B39 (the list). Blocks: phase 7. Replaces: old 8; B20
settled the split and the `usr/bin/` and `binutils/` places.

**Phase 7 outcome (the user's decisions of 2026-10-20 and 2026-10-21;
PHASE7 open points A-C, amendments Am5, Am17, D0 a):** make and
coreutils are m2's, as are sh (bash), sed, grep, gawk, which and
findutils: every file of m2-bash, m2-make, m2-coreutils, m2-sed, m2-grep,
m2-gawk, m2-which and m2-findutils's usr/bin, with the nine MSYS DLLs
they import, in `TC/usr/bin`, and pkg-config is conda-forge's native
(MSVC) pkg-config 0.29.2 with its glib closure (140 files, 24,891,268
bytes, as the plan's probe said; kappa 2026-10-21). No `pkgconf` name:
a later PR (TODO.md). Why the native alternatives were not taken: uutils-coreutils
0.0.20 has no touch, uname or chmod (PS); conda-forge's native make with
MSYS's or busybox's sh needs an R source patch for install.R's
single-quoted `SHLIB_LD`/`PKG_LIBS` (KN's F1: stock R left x.cpp's DLL
unbuilt), and the parked native set (busybox-w32, a zig-built make, a
cmake forwarder) is not phase 7's; m2 needs none of those fixes (KN's
M/N matrix, AMENDMENTS Am5). make.exe is not stripped: m2's has no debug
sections. A name list in build.zig was not taken: configure.win scripts
call coreutils beyond any list (Rmpfr: 12 names).

### B12. Publishing (old 10)

**Answer (2026-10-08): (a).**

Context: CI uploads only the wheels (build-r.yaml:121-127); standalone
archives are never uploaded; there is no release job. Under the model
there is one base archive per packaged flavor and platform, and two
group archives per platform. Mirroring the GPL sources belongs to
whatever publishes.

Options:
- **(a)** In this plan, CI uploads the base and group archives as
  workflow artifacts with a short retention. A release job on `v*` tags
  (GitHub Release, the GPL sources mirrored beside the archives)
  follows.
- **(b)** The release job in this plan.

Recommendation: **(a)**. Keeps this plan to layout and tests;
publishing and the GPL source mirror are a job of their own (G4 later,
without holding up G1-G3).
Blocks: phase 3 (uploads). Replaces: old 10.

### B13. Compression (old 11)

**Answer (2026-10-08): (a).** Phase 6 measures; a compilers archive
above 150 MB comes back then.

Context:
- The compilers group carries almost all bytes: about 149 MB with gzip
  on linux-64 (zig 86.6 + flang 62.2), 97 MB with xz, 105 MB with zstd
  ("Facts the design depends on").
- win-64's `.zip` estimate, about 157 MB, is already above 150 MB.
- The build-tools group is small. The base uses gzip (Windows zip). GNU
  tar needs the xz or zstd program to read those formats.

Options:
- **(a)** gzip (`.tar.gz`; Windows `.zip`) for every archive now. After
  phase 6, measure; if any compilers archive is above 150 MB, choose
  between (b) and (c) for it then.
- **(b)** xz for the compilers archive now.
- **(c)** zstd for the compilers archive now.

Recommendation: **(a)**. Every unix tar reads gzip, and the real sizes
come with phase 6 (G4).
Blocks: phase 3 (format), phase 6 (revisit). Replaces: old 11.

Revisited in phase 6 (2026-10-16, PHASE6 open point L a): the measured
linux-64 compilers `.tar.gz` with flang/ is 150,809,244 bytes, over
150 MB, so the compilers archive is `.tar.xz` (`xz -9 -T0`) on every
platform, Windows included, and the base and build-tools keep
`.tar.gz`/`.zip`. linux-64's `.tar.xz` is about 95.3 MB (103 s to make
on gamma's 16 threads, 9 s to unpack). The rule is per group, never per
OS (env.sh's `group_ext`, groups.zig's `archiveExt`). On Windows R's own
`untar(..., tar = "internal")` reads it wherever the base is, and
System32's `tar.exe` where its build has liblzma (kappa, 2026-10-17:
bsdtar 3.7.2 with liblzma, 12.8 s; `untar()` 66.7 s). Measured
`.tar.xz`: osx-arm64 79.1 MB (gzip 132.7 MB), win-64 92.7 MB (`.zip`
160.0 MB); linux-aarch64 and osx-64 come with CI ("Phase 6 record: the
measurements").

### B14. conda build number (old 12)

**Answer (2026-10-08): (a)**, with B37 (a). D7 (CC_VER/FC_VER) and E2
(zstd declared) ride with phase 4's bump. Phase 4's number (2026-10-11,
PHASE3 C14): the number after the one published when phase 4 merges
(build 8 is on universe; so 9 unless another PR bumps first). The
context below counts from 2026-10-08's build 4.

Context:
- recipe.yaml:120 is `number: 4`; #14 makes it 5; the re-lock keeps 4.
- conda-publish uploads with `--skip-existing` (pixi.toml:461-479), so a
  merged change reaches the channel only with a bump.
- Phase 4's PR must bump. Otherwise r-zig-compilers and
  r-zig-build-tools, new names, publish at the old number and pin
  exactly the channel's older r-zig-slim of that number, which has no
  rzig, while the old r-zig-toolchain (with rzig) stays.
- Phases 2 and 3 change conda files (rzig, Renviron, Makeconf.win) but
  keep today's package boundary. Publishing them alone gains nothing.
- D7 (CC_VER/FC_VER) rides with the first bump.

Options:
- **(a)** Phase 4's PR bumps (to the number after the one published
  when phase 4 merges: build 8 is on universe, so 9 unless another PR
  bumps first), and each later PR that changes a conda package's files
  or dependencies bumps again. Phases 2 and 3 take no bump; their
  changes publish with phase 4's. Goes with B37 (a).
- **(b)** One bump, to the number after the one published then, at the
  end (phase 9). Goes with B37 (b) or (c), where phases 2-9 merge
  together.

Recommendation: as B37, so **(a)**. The channel gets the new boundary
when it is complete on conda, and each later change when it merges (G4).
Depends on: B37. Blocks: phase 4 (the bump) and phase 9; later PRs
follow the same answer. Replaces: old 12; "no bump" is no longer
possible.

**Amended (2026-10-19, the user): "do not bump conda package build
version in the previous PRs. the next build bump is going to be after
phase 7 is merged."** Phases 4, SHLIB routing (feat-shlib-rzig-build),
5 and 6 keep build 8. The next bump comes with phase 7's merge, and (a)
still decides its number then: the one after universe's newest. Without
a bump, a publish from main would upload the new r-zig-compilers and
r-zig-build-tools and a new-hash r-zig-toolchain at `_8`, while
`--skip-existing` keeps universe's old r-zig-slim `_8`, which has no
rzig (feat-zig-pkg-build's N5 coupling: every compiled install would
stop). So build.yaml's publish step also needs the repository variable
`CONDA_PUBLISH` to be `true`; it is unset until phase 7's bump merges,
and the user sets it then (`gh variable set CONDA_PUBLISH --body true`;
TODO.md, phase 7). Phases 4 to 6 publish with that bump. Their records
of local builds at `_9` to `_12` are from before this decision. Until
the bump, a local r-zig-slim build has universe's file name: linux-64's
r-zig-slim hash is hb0f4dca in the render of 2026-10-19 and in phase
4's and 6's builds (hb0f4dca_9, hb0f4dca_12), so build 8 is
r-zig-slim-4.6.1-hb0f4dca_8, the name of universe's build 8, while
r-zig-toolchain's hash moves (phase 4's build: hdc6fa2d, universe's
build 8: hc48ad4c). So a local test empties dist/conda (as
conda-package does) and uses fresh package caches (N5's cache trap,
pixi.toml's conda-package comment), and a local channel is not mixed
with universe in a solver without strict channel priority: universe's
r-zig-toolchain `_8` pins that exact r-zig-slim file name and would
pair the new R with the old rzig.

### B17. Archive names (old 15)

**Answer (2026-10-08): (a).**

Context:
- Today: `dist/R-<ver>-<flavor>-<plat>.tar.gz` (Windows `.zip`) and a
  `.sha256` (package-standalone.sh:41-52), FLAVOR = variant[-blas].
- The groups are per platform (point 6), so their names carry no
  flavor. The group words are B38; the Windows flavor word is B42.
- The v3 naming question (feat-no-host-paths PLAN.md:2687-2689) is open.

Options:
- **(a)** Working names now. Base `R-<ver>-<flavor>-<plat>.tar.gz`;
  groups `R-<ver>-<plat>-<group>.tar.gz` (with B38 a:
  `R-<ver>-<plat>-compilers.tar.gz`, `R-<ver>-<plat>-build-tools.tar.gz`);
  Windows `.zip`; a `.sha256` each.
- **(b)** Wait for the v3 naming decision.
- **(c)** Group archives named and versioned by their contents (zig and
  LLVM versions), with B32's check deciding compatibility. That needs a
  top directory without R's version (B36 c).

Recommendation: **(a)**. It unblocks phase 3, each name says what is
inside, and the final names can follow v3 (G4).
Depends on: B38, B42; (c) needs B36 (c). Blocks: phase 3. Replaces:
old 15.

Since phase 6 (2026-10-16, B13's revisit): the compilers archive is
`R-<ver>-<plat>-compilers.tar.xz` on every platform, Windows included;
the base and build-tools keep `.tar.gz` (Windows `.zip`).

### B18. The zig 0.17 wave (old 18)

**Answer (2026-10-08): (a).** With A2' (2026-10-08) no upstream report
on the MinGW atexit export is filed, so the 0.17 port keeps build.zig's
atexit workaround.

Context (facts revalidated 2026-10-07/08):
- ziglang.org released 0.17.0 on 2026-10-01 (tar.xz 52.9-59.3 MB, win
  zip 100.3 MB).
- PyPI ziglang 0.17.0 was uploaded 2026-10-08 01:00 UTC. At 01:09 UTC it
  listed six wheels (macosx_13_0 arm64 and x86_64; manylinux i686,
  x86_64, aarch64, armv7l) and no win_amd64.
- conda-forge has 0.17.0 only on the `zig_dev` label; the main label's
  newest is 0.16.0 (build 20).
- flang-pixi's flang-zig 6, lld-zig 5 and flang-rt-zig 10 are zig 0.16.0
  builds. Its 0.17 builds will be lld-zig 6, flang-zig 7 and
  flang-rt-zig 11; from flang-zig 7 on, flang-zig pins its own lld-zig.
- Our pins: `zig = "0.16.*"` (pixi.toml:140, 352), `zig 0.16.*`
  (recipe.yaml:132, 452), `ziglang>=0.16.0,<0.16.1` (make-wheel.py:58);
  with the re-lock, exact flang builds.
- build.zig does not compile on 0.17: `b.install_prefix` and
  `b.pathFromRoot` are gone, and configure caching needs `poisonCache`
  or `dependOn*` for env lookups and file reads. zig-build.sh's non-`-D`
  arguments must come before the `-D` options. rzig is unchecked.
- upstream-zig.yaml has three legs: ubuntu-latest, macos-latest and
  windows-latest.

Options:
- **(a)** Upstream leads. Port build.zig, rzig and zig-build.sh to 0.17
  on the gated upstream-zig legs, with a small 0.16/0.17 switch, while
  the default legs, the conda build and the conda packages stay on
  conda-forge's 0.16 until its main label has 0.17. fetch-zig.sh gets a
  0.17 pin once PyPI has all five ziglang 0.17.0 wheels; until then the
  0.17 port runs on the linux and macOS upstream legs, and win-64 stays
  on 0.16. The compilers group's zig follows the zig that builds the
  released R (B6, B32), so it stays 0.16.0 until a release is built
  with 0.17.
- **(b)** The conda build uses a sha256-pinned upstream zig (a
  `source:` entry, or a universe repackage), as flang-pixi does.
  conda-forge's zig stays in the dev envs and CI. The conda packages'
  run dependency on `zig 0.16.*` is the hard part: conda-forge has no
  0.17 to name.

Recommendation: **(a)**; revisit (b) if conda-forge stalls after the
upstream legs are green on 0.17. The conda packages keep one zig, the
one their run dependency names, upstream stays the reference, and
fetch-zig keeps one download path (G2). Either way, before our pins move
to flang-rt-zig 11 (a 0.17 build): the symbol check of its runtime
archives on every subdir, a link of each with our zig 0.16, and an R
build plus a Fortran package on kappa.
Blocks: none of phases 2-9: answer now or later. It decides the
compilers group's zig version later. Replaces: old 18.

### B23. Where unix make sits (new)

**Answer (2026-10-08): (a).**

Context:
- B20 puts unix make in the build-tools group; the brief names
  directories only for Windows (`usr/bin/`, `binutils/`).
- Today make is a file, `TC/make`, named by minimal's Renviron
  (build.zig:3653-3657) and pinned by wheel-test.sh:144.
- Point 3 gives every group directory its own LICENSES/SOURCES. A file
  directly in TC has no directory of its own, so today's place is not
  offered.

Options:
- **(a)** `TC/usr/bin/make`: the same `usr/bin/` as Windows' tools, with
  `TC/usr/LICENSES/` and `TC/usr/SOURCES`.
- **(b)** `TC/make/make`: a directory named after the tool, with
  `TC/make/LICENSES/` and `TC/make/SOURCES`.

Recommendation: **(a)**. One place for build tools on every OS, and one
PATH entry for R (B25) (G1).
Blocks: phase 3. Replaces: none (new; part of old 5).

### B24. Windows binutils (new; an open question of the old plan)

**Answer (2026-10-08), the user's own:** "conda-forge copies `binutils/`
for now, but keeping rzig routing for what is possible."

What it means:
- (a) for now: conda-forge's MinGW binutils as copies in
  `TC/binutils/`, each named by Makeconf.win; ld.exe dropped.
- With (b)'s direction for every tool rzig can serve: ar and ranlib go
  through rzig now (B43), so they leave `binutils/`.
- For dlltool, windres, strip, nm and as, phase 3 checks whether rzig
  can route each one (zig's dlltool for dlltool; zig's rc behind a
  windres-syntax front for windres; zig's objcopy for strip) and moves
  each one that passes the Windows tests. zig 0.16.0 has no nm, no as
  and no PE strip (Facts), so those stay unless the check finds a way.
  The copies stay only for the rest.
- `binutils/` therefore holds, at most: nm, dlltool, as, strip, windres,
  and objdump (B43).

Context:
- build.zig copies conda-forge's MinGW ar, ranlib, nm, dlltool, strip,
  as, ld and windres (binutils_impl_win-64 2.46.1) into TC
  (build.zig:1763-1766): 13,642,752 B, GPL-3.0-only, each importing
  zstd.dll from the base's `R_HOME/bin/x64`.
- Makeconf.win names them through BINPREF (the caveat lists the lines).
  ld.exe is shipped and named nowhere. The tools Makeconf.win names but
  r-zig does not ship are B43.
- nm is required: winshlib.mk runs `$(NM)` on every DLL link without a
  `.def`. zig has no nm; its rc takes rc.exe syntax, not windres';
  objdump is a stub; dlltool's GNU long options are unverified.
- Makeconf.win has an `LLVMPREF` hook on lines 76, 78, 79 and 103 (for
  Rtools' LLVM toolchains), but it routes through BINPREF.

Options:
- **(a)** Keep conda-forge's binutils, in `TC/binutils/`: ar, ranlib, nm,
  dlltool, as, strip and windres (ld.exe dropped). Makeconf.win names
  each one (`$(R_HOME)/bin/toolchain/binutils/nm.exe`, ...); BINPREF
  stays `$(R_HOME)/bin/toolchain/` for gcc.exe and g++.exe. They keep
  loading zstd.dll from the base's `bin/x64`, which every `R CMD` puts
  first on PATH.
- **(b)** zig's tools through rzig applets (zig ar, ranlib, dlltool, rc
  behind a windres-syntax front) plus an nm from elsewhere: no GPL-3
  binaries, more work, and an nm still to find.
- **(c)** LLVM's tools (llvm-nm, llvm-ar, llvm-ranlib, llvm-dlltool,
  llvm-windres; Apache-2.0 WITH LLVM-exception) in `TC/binutils/`, named
  one by one in Makeconf.win. Source package and sizes not measured.

Recommendation (the user's answer starts from it and adds rzig routing):
**(a)**. It works today with R's makefiles and follows the user's caveat
(each tool named, under `binutils/`); (b) and (c) wait under "Later and
future checks" (G2).
Blocks: phase 3. Replaces: none (new).

### B25. How R finds the build tools (new)

**Answer (2026-10-08): (a).** Phase 7's tests settle the
Rprofile.windows question (there is no prototype any more: B11).
Settled (PHASE7 open point I a, amendment Am4): Rprofile.windows gets
the same line (patch 0014), so an R session puts
`R_HOME/bin/toolchain/usr/bin` (or `R_CUSTOM_TOOLS_PATH`, an empty one
read as unset) first on PATH, as R CMD does; install.packages' parallel
make and `Sys.which("make")` see the group (verify-bundle scenario 1 and
3, kappa 2026-10-20). PHASE7 F2 (b) (the user's decision of 2026-10-21):
right after the group's usr/bin, Rcmd_environ's `R_ZIG_TOOLS_PATH`
names `R_HOME/../../usr/bin` and patch 0014 the same directory spelled
without ".." (`dirname(dirname(R.home()))/usr/bin`), a conda env's MSYS
dir (`<env>/Library/usr/bin`, m2's), on both channels: with Git for
Windows' `usr\bin` before an activated conda env, Git's sed (a second
msys-2.0.dll) had written winshlib.mk's tmp.def from offset 0 and R CMD
SHLIB exited 0 with no DLL (Rmpfr, ncdf4, stringi; kappa 2026-10-20/21).
R's own command search (run.c's expandcmd and Sys.which: SearchPath,
then a second call given the first call's size plus ten) rejects a match
in an entry whose ".." shortens it by more than ten characters, so the
session's spelling has none and comes first; the programs R CMD starts
(CreateProcess, MSYS, rzig) resolve Rcmd_environ's (kappa 2026-10-21).
In the standalone tree the entry is `<top>/Library/usr/bin`, inside the
install and never created; each channel has one of the two directories.
An unactivated conda env now finds make and sh under R CMD and in
sessions (PHASE4 open point I a's line then comes only from a check run
outside R).

Context:
- unix: MAKE comes from etc/Renviron, `MAKE=${MAKE-'make'}` (slim, full)
  or minimal's absolute default (build.zig:3653-3657). bin/Rcmd sources
  etc/Renviron and exports its names (patch 0008). Unix R does not
  change PATH.
- Windows: install.R hard-codes `make` (install.R:174); Rcmd puts only
  `R_HOME\bin\x64` on PATH (rcmdfn.c:418-424). R's own hook,
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_RTOOLS45_PATH}};${PATH}/"`, ships
  commented out in etc/Rcmd_environ:38-42 and disabled in
  Rprofile.windows:64-87.
- One platform toolchain serves every flavor, and a base without the
  build-tools group should keep using a host make where there is one
  (linux machines, macOS with the CLT).

Options:
- **(a)** PATH. R puts `TC/usr/bin` first on PATH: unix through
  etc/Renviron (`PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`), which
  bin/Rcmd also exports; Windows through Rcmd_environ's installer line
  with our directory,
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`.
  MAKE stays `make` for every flavor, and minimal's `R_ZIG_MAKE` goes.
  A missing directory is harmless, so the base alone keeps a host make
  or Rtools. A user who sets `R_CUSTOM_TOOLS_PATH` replaces our
  directory, as R intends. The phase 7 prototype settles whether
  Rprofile.windows needs the same line (for `system("make")` from an R
  session).
- **(b)** unix: an absolute MAKE for every flavor (minimal's rule
  today); Windows as in (a). Without the group, MAKE names a missing
  file even where the host has make, and unix and Windows differ.
- **(c)** An rzig `make` applet that runs the group's make, else PATH's:
  unix only; Windows' sh and the rest still need PATH.

Recommendation: **(a)**. One mechanism on every OS, R's own hook on
Windows, and minimal's special Renviron rule goes (G1, G3).
Blocks: phase 3 (unix and the Windows line), phase 7 (Windows
contents). Replaces: none (new).

### B26. What tells R a group is missing (new; absorbs old 13)

**Answer (2026-10-08): (a).**

Context:
- With rzig in the base, `TC/zig-cc` always exists, so patch 0009's
  file test (0009:27) never fires.
- Its Makeconf-CC fallback (old decision 13) is already dead in every
  installed tree ("What exists today").
- Only rzig knows whether a zig is reachable: the wheel sets ZIG_BIN in
  Renviron.site, conda puts zig on PATH, the standalone tree has
  `TC/zig/`.
- Point 4 has rzig locate each group. Today R checks make itself: patch
  0010's `command -v "${MAKE%% *}"` in `R CMD config`.
- Without a preflight the user meets a missing zig late. install.R runs
  .SHLIB's `cc --version` probe inside `try(silent = TRUE)` after
  `make compilers` (install.R:2931-2943); rzig's one stderr line shows,
  but the install goes on to the compile, and a configure script
  reports "C compiler cannot create executables".

Options:
- **(a)** rzig gets a check mode for every group. `zig-cc --rzig-check`
  (Windows `gcc.exe`) runs the compile lookup; `--rzig-check=fortran`
  (zig-fc) also checks flang; `--rzig-check=build-tools` resolves make
  as R will run it (MAKE's first word on PATH; on Windows also sh). Each
  exits 0, or prints the group's text (B35) and exits 127. Patch 0009
  calls it for the compilers and the build tools instead of its file
  test; patch 0010 calls the build-tools check instead of its own test.
  The Makeconf-CC fallback and Windows' extensionless `zig-cc` and
  `zig-cxx` go. `R_ZIG_NO_PREFLIGHT` still skips the preflight.
- **(b)** As (a) for the compilers; R checks make (and on Windows sh)
  itself, in patch 0009 and in patch 0010 as today. Two lookups, and two
  texts to keep in step.
- **(c)** Patch 0009 tests group files in R (`TC/zig/zig`, ...). True
  only for the standalone tree; conda and the wheel need other tests.
- **(d)** No preflight: rzig's message at the first compile.

Recommendation: **(a)**. One lookup, in rzig, for every group and every
channel, as point 4 says; the message appears before configure runs
(G1, G3).
Blocks: phase 2 (the check mode), phase 3 (patches 0009 and 0010).
Replaces: old 13 (B15).

### B27. Where the base's runtime files sit (new)

**Answer (2026-10-08): (a).**

Context: the table in "Runtime and compile-time" (2. of the model). The
user: "Give them dedicated directories where the OS allows; on Windows,
the DLLs must remain beside `R.dll`."
- unix `<top>/lib` already holds only third-party libraries as files;
  R's own libraries are in R_HOME/lib. R's binaries reach both through
  two relative rpaths that conda and the standalone tree share
  (build.zig:165-188), and packages link `-lomp` and `-lopenblas`
  through rzig's `-L<top>/lib`.
- Two items sit inside R_HOME or differ by OS: the unix CA bundle
  (`R_HOME/etc/ca-bundle.crt`) and Windows' fontconfig
  (`R_HOME/etc/fonts`, while unix uses `<top>/etc/fonts`).
- Windows sets `FONTCONFIG_PATH` in etc/Renviron.site
  (build.zig:3077-3080), which `--vanilla` skips.
- conda's packages use `<env>/lib`, `<env>/etc/fonts`,
  `<env>/ssl/cacert.pem`, `<env>/lib/tcl8.6`. conda-forge's win-64
  fontconfig (2.18.3, the lock's build) keeps its configuration in
  `Library/etc/fonts`.

Options:
- **(a)** conda's prefix paths: outside R_HOME, at conda's conventional
  places. Libraries in `<top>/lib` (unix) and beside R.dll (Windows);
  Tcl/Tk as today (`<top>/lib/tcl8.6` ...; Windows `R_HOME/Tcl`, where
  tcltk looks); fontconfig in `<env dir>/etc/fonts` (moves on Windows to
  `<top>/Library/etc/fonts`, and its `FONTCONFIG_PATH` moves out of
  Renviron.site to a place R reads under `--vanilla`; phase 8 finds
  which); the CA bundle in `<top>/ssl/cacert.pem` (moves on unix, wheel
  included). The records go in `<env dir>/share/licenses/` (B33). One
  rpath set for every channel. `<top>/lib` still also holds R_HOME
  (`lib/R`) and libR.pc, so "dedicated" here means "not mixed with R's
  own files", not a directory of their own; (c) is the literal reading.
- **(b)** Today's places, unchanged, recorded only (B33). This leaves the
  CA bundle and Windows' fonts inside R_HOME, so it does not meet point
  2's "dedicated directories".
- **(c)** A dedicated runtime root, e.g. unix `<top>/lib/r-zig-runtime/`
  with data under `<top>/share/r-zig-runtime/`: a third rpath (or rpaths
  that differ from conda's), rzig's `-L` for libomp and libopenblas,
  vendor-libs.sh, verify-tree.sh and make-wheel.py all change. Windows
  DLLs stay beside R.dll in any case.

Recommendation: **(a)**. Two small moves take the runtime out of R_HOME,
the layout matches conda's, and one rpath rule serves all channels (G1,
G4).
Blocks: phase 8. Replaces: none (new; follows B21).

### B28. conda packages (new)

**Answer (2026-10-08): (a).** On win-64, r-zig-build-tools holds the
binutils copies (B41) and depends on B11's conda-forge packages for
`usr/bin`.

Context:
- With rzig in r-zig-slim, and zig, flang and make coming from
  conda-forge and universe, a unix toolchain package holds no files. On
  win-64 it holds the binutils copies (B41).
- r-zig-toolchain's `inherit: r-zig-build` and exact
  `pin_subpackage(r-zig-slim)` (recipe.yaml:396-409) were there because
  Makeconf names its files.
- conda-forge's llvm-openmp is one package (headers and runtime), already
  a run dependency of r-zig-slim (B41).
- Not checked: whether rattler-build 0.76.1 (pixi.lock's) makes an
  output with no files that does not inherit the staging build. D12 was
  pending then (answered 2026-10-08: a, warnings as errors).

Options:
- **(a)** From the one recipe, same version and build number (names per
  B38 a):
  - r-zig-slim: the base, rzig included;
  - r-zig-compilers: no files; depends on `zig 0.16.*`, flang-zig,
    lld-zig and flang-rt-zig (the re-lock's exact builds) and
    llvm-openmp;
  - r-zig-build-tools: unix `make >=4.4`; win-64 the binutils copies in
    `TC/binutils/` plus B11's userland or the m2 packages (B39's list);
  - r-zig-toolchain: a metapackage of the two, so
    `pixi add r-zig-toolchain` keeps working.

  Each pins r-zig-slim exactly, as today.
- **(b)** One r-zig-toolchain (today's minus rzig), no per-group
  packages.
- **(c)** As (a), with the group packages in a recipe of their own,
  versioned on their own and constrained by zig's version instead of an
  exact R pin.

Recommendation: **(a)**. The same boundaries and names as the standalone
archives and the wheels, and the published name r-zig-toolchain keeps
working (G4).
Depends on: B38 (names). Blocks: phase 4. Replaces: none (new).

### B29. PyPI packages (new)

**Answer (2026-10-08): (a).**

Context:
- Today: r-zig (base) and r-zig-toolchain (rzig ×5, make; requires
  `r-zig==<ver>` and ziglang). Linux and macOS only.
- The wheel's R is minimal: no OpenMP in libR, empty `SHLIB_OPENMP_*`.
  It has no Fortran.
- Neither name is published yet, so there is no compatibility burden.
- Wheels cannot hold symlinks. PyPI's default file limit is 100 MB.
- The tags of a make-only wheel computed alone would be macOS minos 11.0
  instead of 13.0 (make-wheel.py:404 computes them over both wheels).

Options:
- **(a)** r-zig (the base, rzig included); r-zig-compilers (no files;
  requires ziglang); r-zig-build-tools (`TC/usr/bin/make`);
  r-zig-toolchain (requires both). The same names as conda. One tag set
  for all of them. No Fortran and no OpenMP on PyPI for now; zig-fc's
  message says so.
- **(b)** As (a), plus r-zig-flang (flang's compile set; on linux-64
  62.2 MB with gzip -9, about the same deflated in a wheel), required by
  r-zig-compilers: Fortran on PyPI. It repackages third-party flang in a
  wheel of ours, against point 5's "our own small packages".
- **(c)** Extras instead of empty wheels: `r-zig[compilers]` (ziglang)
  and `r-zig[toolchain]` (ziglang and r-zig-build-tools); only
  r-zig-build-tools is a second wheel. PyPI's own way, but the names
  differ from conda's.

Recommendation: **(a)**. One set of names on all channels, so B35's text
is one text, and no PyPI compatibility burden yet (G4).
Depends on: B28 (a) and B38 (the names). Blocks: phase 4 (and phase 6
for b). Replaces: old 6's PyPI part.

### B30. Where the groups are assembled (new; replaces old 3)

**Answer (2026-10-08): (a).**

Context:
- The groups need no R build: zig from fetch-zig, flang and the OpenMP
  files from the build env, make and the binutils from the build env,
  the Windows userland from B11.
- Today every third-party file of TC is installed into each R tree by
  build.zig, and vendor-libs.sh walks the whole prefix, so a group
  binary's dependencies land in the base.
- zig is 343-380 MB and 19,546 files; flang 144-210 MB.

Options:
- **(a)** A toolchain tree per platform. A build.zig step (a pixi
  `toolchain` task) installs the groups into
  `dist/toolchain/R-<ver>-zig/` (`lib/R/bin/toolchain/<dir>/`; Windows
  `Library/lib/R/bin/toolchain/<dir>/`). The R trees of every flavor
  hold the base only. Group archives are file selections of the
  toolchain tree; verify-bundle extracts base and groups into one
  directory. Dev trees stay small, and dev compiles keep R's zig
  without env.sh having to force `ZIG_BIN`.
- **(b)** Every non-conda R tree installs every group: dev tree =
  shipped tree, but about 360 MB of zig and up to 210 MB of flang per
  tree, env.sh must always export `ZIG_BIN` (or dev compiles switch
  zig silently), and the group archives come from one leg.
- **(c)** package-standalone.sh adds the groups at packaging: files no
  check saw in a tree, and `package` no longer only archives.

Recommendation: **(a)**. Flavor-independent, built and tested once per
platform, and still "every archive is a selection of one installed
tree" (G1, G2).
Depends on: B36 (a) for the paths. Blocks: phase 3. Replaces: old 3
(B5).

### B31. CI for one toolchain per platform (new; takes old 16's leftover)

**Answer (2026-10-08): (a).**

Context:
- build.yaml's conda-package job is the only per-platform job; its
  matrix already maps subdir to runner. No workflow uses `needs:` or
  download-artifact today.
- `needs:` works per job and within one workflow. build.yaml's legs are
  one matrix job, `build` (build.yaml:62-105), so `needs: toolchain`
  makes every leg wait, full and openblas included. upstream-zig.yaml is
  a separate workflow and needs a toolchain job of its own.
- build-r.yaml has an `os` input but no platform name. upstream-zig.yaml
  calls the same build-r.yaml.
- CI packages the default and minimal legs only (build-r.yaml:110).

Options:
- **(a)** A `toolchain` job in build.yaml, one leg per subdir, builds the
  toolchain tree and the group archives, runs verify-tree on them and
  uploads them. The `build` job `needs:` it (every leg waits); the legs
  that package today (default and minimal; Windows default) download
  their subdir's groups and run verify-bundle's three scenarios. full
  and openblas stay unpackaged. upstream-zig.yaml gets its own
  toolchain job.
- **(b)** As (a), and full and openblas are packaged and tested too
  (more legs pay archive and upload time).
- **(c)** No separate job: the default leg builds the groups and runs
  the scenarios; minimal tests the base alone.

Recommendation: **(a)**. One toolchain per platform, built once and
tested with each base CI packages (point 6; G1).
Depends on: B30 (a). Blocks: phase 3. Replaces: old 16 (B3), moot by
point 6; its leftover was which base flavors CI packages.

### B32. zig version check (new)

**Answer (2026-10-08): (a).**

Context:
- The per-directory `LICENSES/` and `SOURCES` are not asked here: point
  3 requires them (Resolved decisions).
- Nothing checks that the zig a compile runs matches the zig R was built
  with. conda pins `zig 0.16.*`, the wheel `<0.16.1`. A standalone user
  can combine any base and compilers archive, or put another zig on PATH
  or in `ZIG_BIN`.
- R's zig is rzig's own `builtin.zig_version`, since the same zig builds
  both.

Options:
- **(a)** rzig's check mode (B26) prints the zig it runs and fails when
  its major.minor differs from R's. Compiles themselves do not check.
  `R_ZIG_NO_PREFLIGHT` skips it with the rest of the preflight.
- **(b)** The check mode prints a warning and continues.
- **(c)** No check.

Recommendation: **(a)**. An untested zig stops once, before configure,
with a clear message, not deep in a compile, and the user can still
skip it (G2).
Depends on: B26 (a). Blocks: phase 2. Replaces: none (old Design 9 put
one LICENSES/SOURCES in TC).

### B33. Licences and sources for the base's runtime files (new)

**Answer (2026-10-08): (a).**

Context: the base archive and the r-zig wheel redistribute OpenSSL,
curl, krb5, ICU and the rest with R's COPYING only. feat-wheel-minimal
lists the texts as a prerequisite for publishing the wheel; the conda
packages' info/licenses are the source.

Options:
- **(a)** In this plan (phase 8): `<env dir>/share/licenses/<package>/`
  for each vendored package and one `<env dir>/share/licenses/SOURCES`;
  the wheel's dist-info/licenses carries the same; verify-tree requires
  an entry for every vendored file.
- **(b)** Later, as the wheel work's prerequisite.

Recommendation: **(a)**. One mechanism for groups and base, and G4
(fully distributable) needs it on all three channels.
Blocks: phase 8. Replaces: none (new).

### B34. Refinement of B2: R's own environment's bin/ (new)

**Answer (2026-10-08): (a).**

Context:
- rzig knows R's own environment (environment.zig:47-64) but looks for
  zig and flang only through ZIG_BIN and PATH.
- A conda env used without activation, such as an IDE pointed at
  `<env>/bin/R`, has zig and flang in `<env>/bin` (win-64:
  `Library/bin/x86_64-w64-mingw32-zig.exe` and `Library/bin/flang.exe`)
  but not on PATH. Compiling fails there today, and zig-fc's message
  says "activate that env" (fortran.zig:62-68).
- In the standalone tree and the wheel, `<env dir>/bin` holds only R's
  launchers.

Options:
- **(a)** Look in `<env dir>/bin` after `zig/` (`flang/`) and before
  PATH.
- **(b)** Keep B2 as answered.

Recommendation: **(a)**. conda R then compiles with the zig and flang
its packages installed, activated or not; an activated env sees no
change, since `<env>/bin` is first on PATH there (G1). make in an
unactivated env stays PATH's (B25 does not cover it).
Blocks: phase 2. Replaces: none (refines B2).

### B35. The text that names a missing group (new)

**Answer (2026-10-08): (a).**

Context:
- Today `R_ZIG_TOOLCHAIN_HINT` is written for conda (zig-build.sh:57-66;
  build.zig into etc/Renviron, or etc/Renviron.site on Windows) and by
  the wheel (make-wheel.py:244-250); the standalone tree has none.
- rzig's no-flang text is fixed and ignores the hint (fortran.zig:62-68).
- Windows' Rcmd.exe reads only etc/Rcmd_environ (rcmdfn.c:256-265), so a
  Renviron.site hint is not in `R CMD config`'s environment when it
  starts from a shell; started from an R session it inherits R's
  environment, the hint included.
- Point 4: name the archive or package.

Options:
- **(a)** One text per group, the same on every channel, built into rzig
  by build.zig from R's version and the platform. For example (names
  per B38 a):

  ```
  zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, PATH, python3 -m ziglang).
  Compiling needs the r-zig compilers for R 4.6.1 on linux-64:
    standalone: extract R-4.6.1-linux-64-compilers.tar.gz where you extracted R
    conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers)
    pip:         pip install r-zig-compilers
  ```

  The preflight and patch 0010 get the text from the check mode (B26 a).
  `R_ZIG_TOOLCHAIN_HINT` stays only as a user's override. The
  per-channel writers go: `-Dtoolchain-hint`, zig-build.sh's conda
  branch, make-wheel.py's renviron_hint.
- **(b)** One line per channel in `R_ZIG_TOOLCHAIN_HINT`, written for
  every channel (the standalone added); rzig prints the missing group,
  then the hint. Shorter text, three writers, and rzig outside R sees no
  hint.

Recommendation: **(a)**. One source for the text on every channel, and
it works when rzig runs outside R (G1, G3). The only per-channel state
left is the wheel's `ZIG_BIN` default in Renviron.site
(make-wheel.py:229-241), which B2's lookup uses to find PyPI's ziglang.
Depends on: B26 (a) for the preflight's text, B38 for the names.
Blocks: phase 2 (the text), phase 4 (the writers go). Replaces: none
(new).

### B36. The shared top directory (new; follows from B1)

**Answer (2026-10-08): (a).**

Context:
- Today the top directory is the prefix's basename,
  `R-<ver>-<flavor>-zig` (package-standalone.sh:15-20;
  verify-bundle.sh:74). Seven scripts and make-wheel.py:350 default to
  that prefix; env.sh:29's own `PREFIX` has no `-zig` suffix ("What
  exists today").
- A per-platform group archive cannot share a flavor-named top directory
  with every flavor's base.
- package-standalone.sh archives from the prefix's parent, with tar on
  unix and zip on Windows; renaming the root at packaging time takes
  GNU tar's `--transform`, bsdtar's `-s` or a staged copy for zip.
- R's own source tarball unpacks to `R-<ver>/`.

Options:
- **(a)** `R-<ver>-zig/` for the base of every flavor and for the
  groups. Each flavor's tree installs to `dist/<flavor>/R-<ver>-zig/`
  and the toolchain tree to `dist/toolchain/R-<ver>-zig/`, so `package`
  still archives each tree as it is. env.sh computes the prefix once
  for every script.
- **(b)** The same name, with the dev trees kept at
  `dist/R-<ver>-<flavor>-zig/` and the root renamed at packaging: three
  OS-specific code paths in package-standalone.sh.
- **(c)** `r-zig/`, without R's version, so one group archive could serve
  several R versions (with B17 c); one R per parent directory.

Recommendation: **(a)**. It satisfies B1 with no OS-specific renaming at
packaging, and `package` still only archives (G3). Two flavors then need
two extraction directories ("Risks").
Blocks: phase 3. Replaces: none (new; B1's consequence).

### B37. How this plan lands (new)

**Answer (2026-10-08): (a).** #15 merges once its checks pass, which
needs the re-lock PR on main first (R1 = a).

Context:
- #15 (draft) holds phases 0 and 1 and, once the user commits them,
  these documents. Its CI fails today on the deleted flang builds; it
  can pass once the re-lock is on main and merged in (R1).
- Each later phase is already a unit: its own worktree, review and tests
  on linux-64, omicron, kappa and CI.
- conda-publish runs on main with `--skip-existing`; the PR that splits
  the packages must bump the build number however the plan lands (B14).

Options:
- **(a)** #15 merges with phases 0-1 and these documents once its checks
  pass. Phases 2-9 follow as one PR each (5 and 6 may share one).
- **(b)** Phases 2-9 stay on #15: one long-lived PR.
- **(c)** #15 merges with phases 0-1; phases 2-9 go on one new branch and
  PR.

Recommendation: **(a)**. Each phase is reviewed and tested as a unit
already; merging it keeps main, CI and the channel in step and keeps
reviews small (G4).
Blocks: phase 2 (which branch), B14. Replaces: none (new).

### B38. Group names (new)

**Answer (2026-10-08): (a).**

Context:
- One name per group appears in the archives (B17), the conda packages
  (B28), the wheels (B29), the check mode (B26) and rzig's text (B35).
- The brief says "Compilers" and "Minimal build tools", and in its
  verify-bundle caveat "base + compilers + minimal".
- "minimal" is also an R flavor and the wheel's R.

Options:
- **(a)** compilers and build-tools (`R-<ver>-<plat>-build-tools`,
  r-zig-build-tools).
- **(b)** compilers and tools (`R-<ver>-<plat>-tools`, r-zig-tools).
- **(c)** compilers and minimal, the brief's word. It clashes with the
  minimal flavor in every name (base `R-4.6.1-minimal-linux-64` beside
  group `R-4.6.1-linux-64-minimal`; r-zig-minimal).

Recommendation: **(a)**. It says what is inside, cannot be read as the
flavor, and is one name on all three channels (G4).
Blocks: phase 2 (B35's text), phase 3 (archive names), phase 4
(packages). Replaces: none (new).

### B39. What Windows' usr/bin holds (new; refines B20's "sh, make, coreutils")

**Answer (2026-10-08): (a).** B43's answer adds pkg-config from
conda-forge, so the shipped list is (a) plus pkg-config. The stress
suite reassesses the list (D15 = a).

**Stress round 1 (2026-10-08; feat-stress-suite's
`stress/results/2026-10-08.md`).** The run cannot show that the list is
enough. The win-64 stress env had all of it and more (diffutils, tar,
gzip, unzip, zip, patch, texinfo, perl, a native make, pkg-config, MinGW
binutils, cmake). "command not found" appeared only for windres, which
CMake looks for. A test of the list itself needs a run with only B39's
tools on PATH. The user's answer to round 1's decision 16 (2026-10-08):
on Windows the pkg-config in `usr/bin/` also answers to `pkgconf`,
because s2's `src/Makevars.win` calls it by that name. The list is
otherwise unchanged.

Context:
- GNU make runs simple recipe lines without a shell, so every tool a
  recipe or a configure script calls must be an .exe on PATH.
- conda's r-zig-toolchain needed bash, sed, grep, gawk, coreutils, make,
  which and findutils after a real failure (pak:
  `./configure: line 62: sed: command not found`; recipe.yaml:414-442).
  texinfo, diffutils, tar, gzip, unzip and zip stayed build-only there.
- sed, grep, gawk, which and find are not coreutils, so the brief's list
  read literally leaves them out.
- Makeconf.win:75 names pkg-config; no group ships it (B43).

Options:
- **(a)** The set conda proved: sh (bash-compatible, per B11), make,
  coreutils, sed, grep, gawk, which and findutils. The same list on the
  standalone and conda channels. pkg-config is a candidate for the
  extras group, decided by the stress suite.
- **(b)** Strictly sh, make and coreutils; the rest only when the stress
  suite shows a need (pak's configure fails until then).
- **(c)** (a) plus pkg-config (pkgconf) in usr/bin.

Recommendation: **(a)**. The smallest set with evidence behind it, and
the same list on both channels that ship Windows build tools (G1, G4).
Blocks: phase 4 (conda's win-64 dependencies), phase 7 (and B11's
prototype list). Replaces: none (new).

**Phase 7 (2026-10-20; PHASE7 open point G a): the list stays.** From
the three stress runs' Windows rows (38317654371, 38467907779,
38569895172): sh, make, coreutils, sed, awk and pkg-config ran; grep in
Rmpfr's autoconf configure; find and xargs only in cleanup.win under
`--preclean` or R CMD build; which in no row. verify-bundle's btTools
runs each of them through a configure.win, a cleanup.win and a Makevars
rule with PATH = bin\x64 + System32. The `--msys-from-tree` dispatch
(PHASE7 open point L a) checks the 30 rows with the group alone, after
the push. No `pkgconf` name in phase 7 (the user's decision D0 a,
2026-10-21; amendment Am1 withdrawn): a later PR adds pkgconf built from
source, one exe answering both names on both channels (TODO.md).

### B40. How rzig decides that OpenMP is available (new; follows B22)

**Answer (2026-10-08): (a).**

Context:
- Today a standalone flavor has OpenMP when installOpenMP put omp.h in
  its `<top>/include`; minimal has none. rzig adds `-lomp` to a
  `-fopenmp` link when an environment has `include/omp.h`
  (environment.zig:91-99).
- With one `openmp/` per platform, that per-flavor signal is gone. rzig
  is byte-identical across flavors (Phase 0); a flavor flag built into
  rzig would end that.
- minimal's Makeconf has empty `SHLIB_OPENMP_*`, so R never asks for
  OpenMP there. A configure script's flagless omp.h probe would still
  find `TC/openmp/include`, and its `-lomp` link would fail.

Options:
- **(a)** `openmp/` counts only when the base has the libomp runtime
  (`<top>/lib/libomp.so` or `.dylib`; `R_HOME/bin/x64/libomp.dll`).
- **(b)** A per-flavor variable in etc/Renviron (for example
  `R_ZIG_OPENMP=0` in minimal) that rzig reads. rzig run outside R sees
  none.
- **(c)** No rule: `openmp/include` is always added. On minimal, flagless
  omp.h probes pass and their `-lomp` links fail; documented as a limit.

Recommendation: **(a)**. No per-flavor state, it works when rzig runs
outside R, and it keeps minimal safe (G1, G2).
Blocks: phase 2. Replaces: none (new).

The Fortran half (phase 6, 2026-10-16; PHASE6 open point U a, Cg1):
(a) hides only C's `openmp/include`. Fortran's OpenMP files
(`omp_lib.mod`, `omp_lib_kinds.mod`, `omp_lib.h`) sit in flang/'s one
intrinsic-module directory, which zig-fc passes on every flavor. So on
minimal (no libomp) `use omp_lib` compiles, and the link fails on the
`omp_*`/`__kmpc_*` symbols (no `-lomp`): a probe that links, as
autoconf's OpenMP checks do, concludes "no OpenMP", which is true.
minimal's verify-bundle asserts it (measured on linux-64: "ld.lld:
error: undefined symbol: omp_get_max_threads"), and README's minimal
text says so. No second module directory and no flavor rule in zig-fc.

### B41. conda's exceptions to the shared boundary (new; follows B22 and point 5)

**Answer (2026-10-08): (a).** With B24 and B43 as answered, the win-64
copies are nm, dlltool, as, strip, windres and objdump; ar and ranlib
are rzig's.

Context:
- Point 5 asks for the same boundaries on every channel. Two cannot hold
  on conda as drawn ("The same boundaries on every channel").
- conda-forge packages llvm-openmp as one package (headers and runtime).
  r-zig-slim needs the runtime (libR links libomp; recipe.yaml:305), so
  omp.h arrives with the base, and rzig's environment rule
  (environment.zig:91-99) turns OpenMP on with r-zig-slim alone. A
  compile still needs zig, which comes with r-zig-compilers or from the
  user.
- Makeconf.win names the binutils by path under R_HOME (B24 a), so
  win-64 r-zig-build-tools carries copies of binutils_impl_win-64's
  files instead of depending on that package.

Options:
- **(a)** Accept both and record them as conda's two exceptions.
  r-zig-compilers still names llvm-openmp. win-64 r-zig-build-tools
  holds the copies, and its SOURCES names the conda package and its
  sha256.
- **(b)** As (a) for the binutils. For OpenMP, rzig turns on an
  environment's omp.h only when r-zig-compilers is installed (a
  conda-meta lookup in rzig), so B22 holds on conda too.
- **(c)** As (a) for OpenMP. win-64 r-zig-build-tools depends on
  conda-forge's binutils package, and the conda build's Makeconf.win
  names the env's copies, so Makeconf.win differs between conda and the
  standalone tree.

Recommendation: **(a)**. Both exceptions follow from how conda-forge
packages llvm-openmp and from Makeconf.win naming paths under R_HOME;
(b) and (c) add conda-only logic to rzig or build.zig (G1, G3).
Blocks: phase 4. Replaces: none (new).

**Phase 7 (2026-10-21; the user's decision D0 a):** win-64
r-zig-build-tools still owns `TC/binutils/` alone and depends on the
env's pkg-config (B43), as before phase 7: a conda env's TC holds no
`usr/` and no `etc/`, and verify-tree.sh's conda exception stays
binutils only. (Amendment Am2's three pkgconf copies in `TC/usr/bin`,
with pkgconf in the staging host and its run export ignored, were built
and tested on 2026-10-20 and withdrawn: kappa's verify-tree rejected
them in a conda env, F1, and pkgconf leaves phase 7.)

### B42. Windows' flavor name (new)

**Answer (2026-10-08): (a), with a note.** The user: "keep "slim"
everywhere and document that it has full's content (But keep notes that
we want to work on that and make slim really slim, but later)."
- Windows keeps the name slim on every channel; the docs say "Windows
  slim has full's content" (phase 3 writes it where the archives and
  packages are described).
- Making Windows slim really slim is a later aim ("Later and future
  checks"). It relates to C1 (Windows minimal) and to the full-only
  add-on check.

Context:
- Windows builds only full (build.zig:401-406), but env.sh and the
  archive call it slim (env.sh:17-23): `R-4.6.1-slim-win-64.zip` holds
  tcltk, jpeg, tiff and NLS.
- conda's win-64 r-zig-slim holds the same full content.
- The full-only add-on check (the user's caveat) may change what Windows
  builds.

Options:
- **(a)** slim on every channel, as today, documented ("Windows slim has
  full's content") until the add-on check settles what Windows builds.
- **(b)** full for the standalone archive and env.sh
  (`R-<ver>-full-win-64.zip`); conda keeps r-zig-slim, so the names
  differ by channel.
- **(c)** full everywhere, including a conda r-zig-full on win-64.

Recommendation: **(a)**. One name per build on all channels until the
add-on check decides; a rename now may have to be undone (G4).
Blocks: phase 3 (names). Replaces: none (new; it was part of the
writer's B17 a).

### B43. Makeconf.win's tools r-zig does not ship (new)

**Answer (2026-10-08), the user's own:** "rzig answers to
`gcc-ar`/`gcc-ranlib`, and Windows `AR`/`RANLIB` also go through rzig as
on unix. `gcc-nm`, `pkg-config` and `objdump` can come from conda-forge,
but we need to reaccess after the stress suite decide what is really
needed and what zig cc/rzig already covers."

What it means (neither (a) nor (b): every line names a tool that r-zig
ships):
- rzig's name map gains `gcc-ar` (as zig-ar) and `gcc-ranlib` (as
  zig-ranlib); phase 2.
- Windows installs rzig also as `TC/zig-ar.exe`, `TC/zig-ranlib.exe`,
  `TC/gcc-ar.exe` and `TC/gcc-ranlib.exe`; phase 3. Makeconf.win's AR
  (103) and RANLIB (213) become `$(BINPREF)zig-ar` and
  `$(BINPREF)zig-ranlib`, the names unix's Makeconf uses. The LTO lines
  267 and 269 keep `$(BINPREF)gcc-ar` and `$(BINPREF)gcc-ranlib`, which
  now exist. ar and ranlib leave `binutils/` (B24).
- gcc-nm (268): B43-2, the user's (2026-10-08): "Ship from conda-forge
  if really needed". No gcc-nm ships now; the line stays as it is
  (`$(BINPREF)gcc-nm`, a file that does not exist), so an LTO build that
  needs it fails the same way everywhere. A real gcc-nm from
  conda-forge's MinGW GCC packages ships only if the stress suite shows
  a package needs it.
- objdump (211): conda-forge's MinGW objdump, copied into `TC/binutils/`
  with the other binutils (phase 3 checks that binutils_impl_win-64 has
  it); the line names `$(R_HOME)/bin/toolchain/binutils/objdump`, with
  no `.exe`: R CMD check takes `R CMD config OBJDUMP` only when its
  value plus `.exe` is a file (sotools.R's read_symbols_from_dll; phase
  3's step 3 review).
- pkg-config (75): conda-forge's native win-64 pkg-config (0.29.2 in
  pixi.lock) in `TC/usr/bin/`, with B39's list (phase 7); B39's list
  gains it. The line names it bare, `pkg-config`, as Makeconf.win names
  `sed`: the standalone tree's copy is first on PATH (B25), and conda's
  r-zig-build-tools brings the package itself, whose file is in
  `Library/bin` (B11), so a path under R_HOME would be wrong there. The
  binutils lines can name paths because conda carries copies of them in
  `TC/binutils/` (B41).
- After the stress suite (D15 = a) shows what is really needed and what
  zig cc and rzig already cover, gcc-nm, pkg-config and objdump are
  reassessed.

**Stress round 1 (2026-10-08; feat-stress-suite's
`stress/results/2026-10-08.md`), and the user's answer to round 1's
decision 16 (the same day):**
- pkg-config: needed when there is a libraries env, and it must be on
  PATH. Packages call `pkg-config` from PATH, not Makeconf.win's line
  (some expand `$(BINPREF)pkg-config` before Makeconf sets BINPREF).
  It ships as planned, and on Windows it also answers to `pkgconf`
  (B39's note).
- objdump: no install used it. R CMD check's compiled-code check on
  Windows does (`R CMD config OBJDUMP`). It stays in `binutils/`.
- gcc-nm: no package used LTO and no log calls it. None ships: B43-2
  holds.
- windres: CMake looks for it on PATH or in `RC`, not through
  Makeconf.win's `RESCOMP`. Branch fix-stress-round1 sets `RC` and
  `RCFLAGS` in Rcmd_environ (round 1's decision 15).

Context:
- Makeconf.win names pkg-config (75), objdump (211) and the LTO gcc-ar,
  gcc-nm and gcc-ranlib (267-269) through BINPREF, so today they name
  files under TC that do not exist.
- Upstream R with Rtools has an empty BINPREF and finds them on PATH.
- With bare names a package uses whatever copy is on PATH (Rtools',
  Git's, a conda env's), so results depend on the machine.
- The extras group is added only when the stress suite shows a need
  (B39 c for pkg-config).

Options:
- **(a)** Bare names, so a copy on PATH is used, as upstream R does with
  Rtools.
- **(b)** Unchanged: the lines keep naming files under TC that do not
  exist. A package that needs one fails the same way on every machine,
  and the stress suite sees each such need.

Recommendation (not taken): **(b)**. The same result on every machine,
and no host tool hides a need the stress suite should find (G1, G2).
Blocks: phase 3 (Makeconf.win). Replaces: none (new).

**Phase 7 (2026-10-21; the user's decision D0 a, amendments Am1 and
Am2 withdrawn):** on Windows `pkg-config` is conda-forge's native (MSVC)
pkg-config 0.29.2: the standalone tree copies it into `TC/usr/bin` with
its glib closure (glib-2.0-0.dll, iconv.dll, charset.dll, intl-8.dll,
pcre2-8.dll, vcruntime140.dll), and a conda env has its own in
`Library/bin` (r-zig-build-tools' run dependency). No `pkgconf` name.
0.29.2 prints `Libs.private` without `--static`, so ncdf4 (`-ldebug`,
KN d) and RPostgres (the env's static libpq, KN i) stay expected
failures. A later PR builds pkgconf from source in build.zig, one static
exe answering both names on both channels (TODO.md); with conda-forge's
pkgconf 3.0.7 both were fixed (kappa 2026-10-20: ncdf4 links
`-lnetcdf`, RPostgres takes its winlibs.R download). nm for R
CMD check is the group's `binutils/nm.exe` through Rcmd_environ's
`UserNM` (PHASE7 open point H a); objdump and gcc-nm unchanged. No `ld`
anywhere: winch's bundled libbacktrace configure finds none (C6), a
toolchain follow-up for the user, not phase 7.

### B44. Fortran on an OS whose phase 6 prototype fails (new)

**Answer (2026-10-08), the user's own:** "fortran through flang should
succeed, we can work the flang-zig project to fit our needs."

What it means:
- Fortran through flang must succeed on every OS (linux-64,
  linux-aarch64, osx-arm64, osx-64, win-64). Neither option is taken.
- If phase 6's prototype fails on an OS, the cause is fixed together
  with flang-pixi (the flang-zig project, which we can adapt to our
  needs), and the prototype runs again. Phase 6 does not finish until
  every OS passes.
- No OS ships its compilers group without `TC/flang/`, and zig-fc gets
  no "Fortran is not in this OS's group" text.

Context:
- Phase 6 prototypes zig-fc's links through zig and the flang set in
  `TC/flang/` on linux-64, osx-arm64, osx-64 and win-64.
- conda already has Fortran on every OS (flang-zig from universe).
- An OS whose links fail cannot ship `flang/` in its compilers group.

Options:
- **(a)** That OS's compilers group ships without `flang/`; zig-fc's
  text says Fortran is not in that OS's group and names the conda
  package; the other OSes ship Fortran.
- **(b)** No OS ships `flang/` until every OS passes.

Recommendation (not taken): **(a)**. Fortran reaches the OSes where it
works, and the gap is named in one place (G4). The user is asked again
only if a prototype fails.
Blocks: phase 6. Replaces: the old plan's "an OS whose links fail ships
without Fortran" step, which is gone.

## Phases

**The decisions are answered (2026-10-08).** Implementation may start
per B37 (a): #15 merges with phases 0-1 and these documents once its checks
pass (after the re-lock PR is on main), then phases 2-9 follow, one PR
each. The re-lock PR and #14 continue as planned. Phases 0 and 1 are
done (History).

Each phase: a worktree, review, tests on linux-64 here, omicron
(osx-arm64, then osx-64 under Rosetta) and kappa (win-64), then CI. The
user loads the SSH key for omicron and kappa and makes the commits.
"The three scenarios" are verify-bundle's (Verification); they start in
phase 3 and every later phase runs them on every OS. With B37 (a), each
phase is its own PR.

Prerequisites from outside this plan:
- The re-lock merged, as its own PR (R1 = a; exact flang builds). The
  conda packages, phase 6 and the flang file list depend on it, and
  installs of a published r-zig-toolchain otherwise take flang-pixi's
  next builds.
- #14 merged (`-mcpu=baseline`), at the latest before phase 5 ships
  compilers to Windows users.
- #15's remaining checks green after the re-lock (History, Phase 1);
  then #15 merges (B37 a).
- In parallel, not a prerequisite: the stress suite starts now on its
  own branch (D15 = a). Its results decide the extras group and
  reassess B39's list and B43's tools.

### Phase 2 — rzig knows the groups

Goal: rzig finds zig, flang and the OpenMP files in its own
directories, names a missing group, and has the check mode the preflight
will call. No layout change: conda and the wheel behave as before.

Decisions (all answered): B26 (the check mode), B32, B34, B35, B38 (the
names in the text), B40, B43 (rzig's gcc-ar and gcc-ranlib names); B37
for the branch; B2 and B22.

Steps:
- find_zig.zig (B2 = a, B34 = a): `ZIG_BIN`, then `<rzig dir>/zig/zig`
  (`zig.exe`), then `<env dir>/bin/zig` (Windows
  `x86_64-w64-mingw32-zig.exe`), then PATH, then `python3 -m ziglang`.
  When the python3 fallback cannot start or has no ziglang, rzig prints
  B35's text and exits 127.
- flang_rt.flang() (B2 = a, B34 = a): `<rzig dir>/flang/bin/flang`
  (`flang.exe`), then `<env dir>/bin/flang`, then PATH. fortran.zig's
  no-flang text becomes B35's; its unit test and wheel-test.sh:149-168
  follow.
- OpenMP (B40 = a): `<rzig dir>/openmp/include` on every compile
  (`-idirafter` on Windows) and `-L <rzig dir>/openmp/lib` on Windows
  links, when the directory exists and the base has the libomp runtime;
  the `-lomp` rule counts `openmp/` like an environment with omp.h.
- The check mode (B26 a): the compile lookup (`fortran` also checks
  flang), and the build-tools check (make as R will run it; Windows also
  sh); prints the zig and its version; fails on a major.minor different
  from R's (B32 a).
- rzig's name map (main.zig) gains `gcc-ar` (as zig-ar) and `gcc-ranlib`
  (as zig-ranlib) (B43). Phase 3 installs the Windows copies.
- build.zig passes R's version and the platform name to rzig's build;
  R's zig version is rzig's own `builtin.zig_version`, since the same
  zig builds both.
- Unit tests: each lookup step, "zig/ wins over PATH", the env-bin
  step, a missing zig and flang, the openmp rule with and without a
  libomp, the check mode's exit codes and texts for each group, and the
  two new names.

Tests:
- `pixi run rzig-test` on linux-64, osx-arm64, osx-64 and win-64.
- conda: test-toolchain.R still compiles with the env's zig and flang.
- wheel-test.sh still uses ziglang through ZIG_BIN.
- verify-bundle as today; its zig-cc still runs the build's zig.

**Status (2026-10-09): implemented and tested, not committed.** The
worktree feat-standalone-phase2 (branch feat-standalone-phase2, from main
b2e73a5, build 7 published) has every step. Every test above passed on
linux-64, omicron (osx-arm64, osx-64) and kappa (win-64): "Phase 2
tested". Still to do: the review's code fixes (same section), then CI,
then the commit.

#### Phase 2 record (2026-10-09, linux-64)

What changed (zigbuild/tools/rzig unless named):
- find_zig.zig: `ZIG_BIN`, `<rzig dir>/zig/zig`, then zig and
  x86_64-w64-mingw32-zig in `<env dir>/bin`, then the same two names on
  PATH, then `python3 -m ziglang`. `find` returns the command and the
  file it found, or null. The python3 step first runs
  `python3 -c "import ziglang"`, quietly; when that fails there is no
  zig.
- flang_rt.flang(): `<rzig dir>/flang/bin/flang`, `<env dir>/bin/flang`,
  PATH. zig-fc and the runtime lookup still share it.
- environment.zig: `toolchain()` is rzig's own directory. `list()`
  counts `<rzig dir>/openmp` as one more environment, right after R's
  own, when it exists and R's own environment has `lib/libomp.so` or
  `lib/libomp.dylib` (Windows `lib/R/bin/x64/libomp.dll`). So its
  include/ goes on every compile (`-idirafter` on Windows), its lib/ on
  links where it exists (Windows), and the `-lomp` rule sees its omp.h.
- groups.zig (new): the group names (B38) and B35's text, built from R's
  version (a build option) and the platform. `report` prints a first
  line (what is missing) and the group's text on stderr.
- check.zig (new): `--rzig-check`, `--rzig-check=fortran`,
  `--rzig-check=build-tools`, as the only argument of any rzig name.
  zig-fc's plain `--rzig-check` is fortran's.
- main.zig: `gcc-ar` and `gcc-ranlib` in the name map (as zig-ar and
  zig-ranlib); the check mode; a command that runs zig with none found
  prints the compilers group's text and exits 127.
- fortran.zig: the no-flang text is the compilers group's.
- build.zig (both): rzig's build takes R's version (`-Dr-version` in
  rzig's own build.zig; "dev" by default, for the parity and smoke
  tests).
- The shims (toolchain/zig-cc, zig-cxx, zig-ar, zig-ranlib) mirror the
  zig lookup, and zig-cc and zig-cxx the flang lookup. They do not probe
  python3.
- parity-test.sh: 15 new cases (the lookups, the toolchain's openmp/,
  gcc-ar and gcc-ranlib) and 11 checks of the real binary's check mode.
- wheel-test.sh and verify-bundle.sh check the new no-flang text;
  make-wheel.py's comment on the fallback is corrected.

Choices made while implementing (each within the answered decisions):
- **The text names what exists on the day it is printed.** conda and pip
  name r-zig-toolchain, the one package with every group today. The
  standalone line names the tools themselves (zig 0.16 on PATH or in
  `ZIG_BIN`, LLVM flang on PATH; GNU make on PATH; on Windows sh and
  make on PATH), since no group archive exists yet. The pip line says
  "no Fortran" (B29) and "no wheels for Windows". The text lives only in
  groups.zig. Phase 3 names R-<ver>-<plat>-build-tools.tar.gz (unix;
  Windows' usr/bin and its .zip come in phase 7), phases 5 and 6 name
  R-<ver>-<plat>-compilers.tar.gz (zig, then flang), and phase 4 names
  r-zig-compilers and r-zig-build-tools. Why: a text that names an
  archive or a package nobody can install sends users nowhere. No wheel
  is on PyPI yet ("What exists today"), so the pip line names the wheel
  make-wheel.py builds beside r-zig, as the wheel's own hint does.
- **rzig does not read R_ZIG_TOOLCHAIN_HINT.** Until phase 4 the conda
  and wheel builds still write it, for patches 0009 and 0010, and the
  wheel's value ("pip install r-zig-toolchain") is wrong for a missing
  flang. After phase 4 it is only a user's override; where the preflight
  shows it is phase 3's patch work.
- **The platform comes from the target rzig is built for**
  (`builtin.cpu.arch`, `builtin.os.tag`, mapped to linux-64,
  linux-aarch64, osx-64, osx-arm64, win-64). build.zig passes R's
  version only. Why: it is the target build.zig gives rzig's build, and
  it cannot disagree with the binary.
- **`<rzig dir>` is rzig's own directory**, from its own path. Installed,
  that is TC. A bare copy (zig-out/bin) looks in its own `zig/` and
  `flang/bin/`; openmp/ also needs R's own environment (the base), so a
  bare copy never counts it.
- **The environment's bin is searched for both PATH names**, zig then
  x86_64-w64-mingw32-zig, on every OS: one rule. conda's win-64 layout
  has only the second.
- **Exit codes of the check mode:** 0, with one line on stdout; 127 when
  a tool is missing, as for a compile; 1 when zig's major.minor is not
  R's, or zig does not say its version; 2 for an unknown
  `--rzig-check=` value. Every failure prints the group's text on
  stderr. `R_ZIG_NO_PREFLIGHT` (non-empty, as R's `nzchar` test) skips
  only the version comparison.
- **make "as R runs it":** the first word of `MAKE`, else make; a word
  with a separator must be an executable file, any other is looked up on
  PATH (`command -v`). sh is checked when the OS is Windows.
- **zig-fc's compiles do not need zig.** find_zig runs first, as before,
  but only a command that runs zig stops when there is none. A Fortran
  compile with no flang shows the flang text, not the zig one.
- **The python3 probe** also ends fix-stress-round1's note that the last
  fallback reached the Microsoft Store alias on Windows ("Python was not
  found", exit 49): that python3 fails the probe, and rzig names the
  compilers group.

What a user sees (rzig built with `-Dr-version=4.6.1`, linux-64):

```
$ env -i PATH=/nowhere zig-cc -c a.c          # exit 127
zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the environment's bin, PATH, python3 -m ziglang)
Compiling needs the r-zig compilers for R 4.6.1 on linux-64: zig 0.16, and flang for Fortran.
  standalone:  zig 0.16 on PATH or in ZIG_BIN, LLVM flang on PATH
  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
  pip:         pip install r-zig-toolchain (no Fortran)
$ zig-fc --rzig-check                          # exit 0
zig-fc: compilers ok: zig 0.16.0 at <env>/bin/zig; flang at <env>/bin/flang
$ ZIG_BIN=<a zig 0.17.0> zig-cc --rzig-check   # exit 1
zig-cc: <a zig 0.17.0> is zig 0.17.0, not R's zig 0.16 (R_ZIG_NO_PREFLIGHT=1 skips this check)
Compiling needs the r-zig compilers for R 4.6.1 on linux-64: ...
$ MAKE=gmake zig-cc --rzig-check=build-tools   # exit 127, no gmake on PATH
zig-cc: no gmake on PATH (MAKE=gmake)
Building packages needs the r-zig build tools for R 4.6.1 on linux-64: make.
  standalone:  GNU make on PATH
  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
  pip:         pip install r-zig-toolchain
```

Tests (linux-64, pixi.lock sha256
7aef60ff4b270486cf70786f20e21b50cde2638eb6b6deba62d934e780355a63,
unchanged):
- `pixi run --locked rzig-test`, conda-forge zig 0.16.0: 94 unit tests
  pass (74 before). Parity: 75 identical, 59 identical but for rzig's
  own -L or compiled object, 32 deliberate, 0 failed (before: 60, 58,
  22). The 12 checks are among the identical.
- The same with upstream zig (`ZIG_BIN` from `pixi run --locked
  fetch-zig`, PyPI ziglang 0.16.0): the same counts.
- rzig cross-builds for x86_64-windows-gnu, aarch64-macos, x86_64-macos
  and aarch64-linux-musl, and the unit tests compile for Windows and
  macOS hosts (`zig test -fno-emit-bin`). They have not run there.
- The repo's build.zig compiles with the new argument. Its `rzig-test`
  step was not run: the worktree has no extracted R source, which
  build.zig checks first.

#### Phase 2 tested (2026-10-09)

Every host tested the worktree as the implementer left it. At the start
and the end of each run, `git diff` had sha256 1fb0dd29...169e6 and
pixi.lock had sha256 7aef60ff...355a63 (unchanged). Nothing is committed
or pushed, so CI has not run. The review then changed comments only, and
`rzig-test` passed again on linux-64 with the same counts.

linux-64 (local):
- `rzig-test`: 94/94 unit tests with conda-forge zig 0.16.0 and with
  upstream zig (fetch-zig). Parity 75 / 59 / 32 deliberate / 0 failed
  with both.
- default (slim): build, verify-tree, smoke, contract and verify-package
  pass. verify-package's no-flang check prints the new line, exit 127.
- minimal: build and verify-package pass, the same check included.
- wheel: wheel and wheel-test pass. The no-flang check shows the
  compilers text with "pip install r-zig-toolchain (no Fortran)". R CMD
  INSTALL works three ways: ZIG_BIN from `import ziglang`, Renviron.site's
  sibling ziglang, and `python3 -m ziglang` with ZIG_BIN naming nothing.
- pkg: conda-package passes. r-zig-slim-4.6.1-hb0f4dca_7 and
  r-zig-toolchain-4.6.1-hbd87d40_7 each report "all tests passed";
  test-toolchain.R compiles its C, C++, zlib, FLIBS-Fortran and
  USE_FC_TO_LINK packages with the env's zig and flang.
- 189 behaviour checks on copies of the built slim and minimal trees, all
  pass:
  - zig: ZIG_BIN, then TC/zig/, then `<top>/bin` (zig, then the mingw
    name), then PATH. A real upstream zig tree in TC/zig/ with
    PATH=/usr/bin:/bin compiles, links, runs and builds an R CMD SHLIB
    package. A bare copy of rzig does not look in `<top>/bin`.
  - No zig: every name and the check exit 127 with B35's text alone on
    stderr. The same with a python3 without ziglang, with no python3, and
    with a python3 that fails like the Store alias. With PyPI's ziglang on
    PYTHONPATH, `python3 -m ziglang` compiles, links and runs.
  - flang: TC/flang/bin, then `<top>/bin`, then PATH, for the compile and
    for the runtime archive. No flang: 127 and the compilers text, also
    from zig-fc with no zig.
  - openmp/ (B40): counted only with `<top>/lib/libomp.so` (or
    `.dylib`). Its -I comes after the tree's include and before
    R_ZIG_EXTRA_ENV's; -lomp appears once; a real OpenMP R CMD SHLIB
    package runs 3 threads. minimal has no libomp, so openmp/ is never
    counted there.
  - Check mode: the exit codes and texts of the record. MAKE='make -j8'
    and an absolute MAKE pass. A stand-in zig 0.17.0 exits 1, and 0 with
    R_ZIG_NO_PREFLIGHT=1. 0.16.9 passes, 0.15.2 fails.
  - gcc-ar and gcc-ranlib build an archive that links.

omicron:
- osx-arm64: `rzig-test` 94/94 with both zigs. build, verify-tree (62
  Mach-O files), smoke, contract (Rcpp, data.table, minqa, quadprog, pak,
  ps) and verify-package pass, the no-flang check included.
- osx-64 under Rosetta, in a copy with `platforms = ["osx-64"]` re-solved
  once (the same osx-64 packages in all 7 environments): `rzig-test`
  94/94, build and verify-package pass.
- 55 checks on the osx-arm64 tree, all as designed. The script counted 2
  as failed, but there it expected "gcc-ar:" where rzig prints "zig-ar:".
  They cover the lookups (upstream zig in TC/zig/ with an empty PATH, R
  CMD SHLIB and dyn.load), flang/bin, openmp/ (a 3-thread OpenMP load),
  the python3 step with the Command Line Tools' python3, the check mode,
  and gcc-ar and gcc-ranlib.

kappa (win-64):
- `rzig-test`: 69 passed and 25 skipped of 94, with both zigs. The 5 new
  skips use shell-script stand-ins (check.zig's three, find_zig's python3
  test, flang_rt's runtime test); the tree checks below cover them.
- build, verify-tree, smoke, contract and verify-package pass.
- On a copy of the tree:
  - B35's text names R 4.6.1 on win-64 and "no wheels for Windows". The
    Store alias python3 (exit 9009) gives the text and 127; nothing of its
    message leaks.
  - ZIG_BIN works with and without .exe and with `/`. Upstream zig.exe in
    TC\zig is found with PATH=System32, also through the 8.3 path, and
    compiles, links and runs. In `Library\bin`, zig.exe comes before the
    mingw name, both before PATH; zig.bat is ignored; R_ZIG_EXTRA_ENV's bin
    is not searched.
  - flang in TC\flang\bin and in `Library\bin` is found.
  - openmp\ with libomp.dll beside R.dll: -idirafter, -L openmp/lib and
    libomp.lib. Phase 3's layout (omp.h and libomp.lib only in openmp\)
    compiles, links and runs 3 threads; without libomp.dll nothing is
    added.
  - build-tools: sh and make from pixi global or from `Library\usr\bin`.
  - gcc-ar and gcc-ranlib copies build an archive.

Review (2026-10-09), against the decisions:
- Lookup order and conda: an activated env sees the same zig and flang,
  as B34 says. One effect: a zig put first on PATH no longer wins over
  the zig in R's own env's bin; ZIG_BIN is the way to pick another one.
- The wheel: Renviron.site's ZIG_BIN default is still the first step. A
  ZIG_BIN that names nothing falls through to PATH and python3
  (wheel-test's third install).
- The dev tree: env.sh exports ZIG_BIN only when it is set. Without it
  the build's zig is PATH's, and a dev tree has no TC/zig/ and no
  `<top>/bin/zig`, so rzig runs PATH's too. verify-bundle passes
  `ZIG_BIN=$ZIG` and checks that its compiles run the build's zig; that
  passed on the four unix builds. Phase 5's scenario 2 unsets it
  (TODO.md).
- Windows paths: `Library/bin`, `.exe` and 8.3 paths hold (kappa).
- The openmp rule: the runtime test is right per OS and flavor (linux
  .so, macOS .dylib, Windows R_HOME/bin/x64/libomp.dll; none in minimal;
  conda and the wheel have no openmp/).
- The check mode is ready for patches 0009 and 0010: fixed flags; exit 0,
  127, 1 or 2; one line on stdout (`<name>: compilers ok: ...`,
  `<name>: build-tools ok: ...`); failures on stderr. R_ZIG_NO_PREFLIGHT
  counts when non-empty, as 0009's `nzchar` test.
- B35: the text is in groups.zig only, and true today, with the PyPI
  caveat in the record's choices.
- The version check: a tree built with conda-forge zig 0.16.0 passes with
  upstream zig 0.16.0 on all three hosts, and the upstream `rzig-test`
  runs pass. A 0.17.0 zig fails.
- Parity: the counts hold. Of the 10 new deliberate cases, 5 are
  openmp/'s and 5 differ only in the shim's unnormalized path.

Code problems found by the review, fixed after it (2026-10-09: the
diff applied in the worktree, then rzig-test re-run on linux-64 with
conda-forge and upstream zig). The exact diff was handed over; on a copy, rzig's unit tests (94/94) and the parity test
(76 / 59 / 34 deliberate / 0 failed) pass with it, with both zigs:
- **The shims lose the environment after -march=armv*-a.** zig-cc and
  zig-cxx keep the environment's directory in `_e`, and the -march loop
  reuses `_e` and leaves it empty. The flang lookup that follows then
  skips TC/flang/bin and `<top>/bin` and drops the runtime archive. rzig
  is right. Fix: name the variable `_env` in the four shims, and add two
  parity cases, `-march=armv8-a+crc` with the toolchain's flang (zig-cc
  and zig-cxx). Today's shims fail both. Found by the linux tester.
- **Windows' build-tools check reads MAKE, but R runs make there.**
  install.R:174 and R CMD config set `MAKE=make` on Windows, so
  `MAKE=gmake` fails the check although R would run make. Fix: on Windows
  check make and ignore MAKE, with one more unit-test line; the record's
  "make as R runs it" choice then says that MAKE is unix's.
- **A parity check's name is wrong.** "a zig that is not R's" runs the
  stub, which gives no version. Fix: rename it, and add a check with a
  zig that says 0.99.0.

Observations (no change needed now):
- On Windows the check lines mix separators
  (`.../toolchain/zig\zig.exe`): find_zig joins with `\`, rzig's own
  path uses `/`. Phase 3's preflight shows these lines, so one separator
  would read better (TODO.md).
- A zig that cannot start, such as conda-forge's win-64 zig.exe copied
  without its DLLs (zlib.dll, zstd.dll, libxml2.dll), gets "does not say
  its zig version". Upstream zig.exe runs alone, which B4 (a) already
  takes for phase 5.
- gcc-ar and gcc-ranlib print their messages as zig-ar and zig-ranlib,
  by design.
- In the last fallback rzig starts python3 twice per call (the probe,
  then the run).
- On Windows the pipeline leaves rzig's cache in `%LOCALAPPDATA%\r-zig`,
  since XDG_CACHE_HOME is unset. This predates phase 2.
- On macOS with PATH=/usr/bin:/bin the build-tools check finds Apple's
  GNU make 3.81 and passes; it does not check make's version.

Not run: CI; a full R build with upstream zig on any host; `check`,
hermetic, full and openblas; wheel-test on macOS; conda-package on
omicron and kappa; the repo's `zig build rzig-test` step.

The review also corrected comments that still said rzig runs PATH's zig
or flang (env.sh, verify-bundle.sh, verify-tree.sh, build.zig), the
check mode's comment (exit 1 for a zig with no version, exit 2), and
groups.zig's (the preflight calls the check mode from phase 3).

### Phase 3 — the standalone layout: base, toolchain tree, groups with today's contents

Goal: the R trees hold the base only (rzig included). A toolchain tree
per platform holds the groups' directories, filled with today's
third-party files. package makes a base archive and two group archives
sharing one top directory, and verify-bundle runs the three scenarios.

Decisions (all answered): B7, B12, B13, B17, B23, B24, B25 (unix, and
the Windows line), B26 (patches 0009 and 0010), B30, B31, B36, B38,
B42, B43.

Steps:
- env.sh: the platform name, computed once; the prefixes
  `dist/<flavor>/R-<ver>-zig` and `dist/toolchain/R-<ver>-zig` (B36),
  replacing env.sh:29's `PREFIX`. zig-build.sh, zig-package.sh,
  zig-verify-package.sh, zig-smoke.sh, zig-contract.sh, verify-tree.sh
  and hermetic-check.sh read them from env.sh; make-wheel.py:350 derives
  the same prefix (it does not source env.sh).
- build.zig, a toolchain step (pixi task `toolchain`) installing into
  the toolchain tree, each directory with `LICENSES/` and `SOURCES`
  (point 3):
  - `openmp/`: the headers (and libomp.lib on Windows), moved out of the
    base (installOpenMP's destinations, build.zig:2947-2963);
  - unix `usr/bin/make` (B7, B23): conda-forge's make, moved out of
    minimal's tree (build.zig:910-917);
  - Windows `binutils/` (B24, B43): nm, dlltool, as, strip and
    windres, moved out of installWindowsCompilerContract
    (build.zig:1763-1766), and objdump, new, from the same
    binutils_impl_win-64 (check that it ships it). ar and ranlib leave
    for rzig; ld.exe dropped.
- The base: TC holds only rzig. On Windows installRzig adds
  `zig-ar.exe`, `zig-ranlib.exe`, `gcc-ar.exe` and `gcc-ranlib.exe`
  (B43), and `ar.exe` and `ranlib.exe` for CMake (step 3's review), and
  drops the extensionless `zig-cc` and `zig-cxx` (B26 a);
  verify-tree.sh's rzig name list (76) follows.
- rzig routing for the rest of `binutils/` (B24): for dlltool, windres,
  strip, nm and as, check whether rzig can serve each one (zig's dlltool,
  including Makeconf.win's GNU long options and `--as`; zig's rc behind
  a windres-syntax front; zig's objcopy for strip). Each one that passes
  the Windows tests moves to an rzig name, in this phase or in a
  follow-up PR if the work grows; the copies stay only for the rest.
  Record the result here.
- Renviron and Rcmd_environ (B25): unix etc/Renviron gets
  `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}` and every flavor keeps
  `MAKE=${MAKE-'make'}` (minimal's `R_ZIG_MAKE` goes,
  build.zig:3653-3657); Windows etc/Rcmd_environ gets
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin};${PATH}/"`.
- Makeconf.win (B24, B43; the caveat lists the lines): AR (103) and
  RANLIB (213) become `$(BINPREF)zig-ar` and `$(BINPREF)zig-ranlib`; the
  LTO gcc-ar and gcc-ranlib lines (267, 269) stay and now name rzig
  copies; NM (78, 204) names `$(R_HOME)/bin/toolchain/binutils/nm.exe`;
  the LTO gcc-nm line (268) stays unchanged (B43-2: a gcc-nm ships only
  if the stress suite shows a need); DLLTOOL with its `--as`
  (76), RESCOMP (79), OBJDUMP (211) and STRIP_* (251-252) name their
  files under `binutils/`, or rzig's names for any tool the routing
  check moved; PKG_CONFIG (75) becomes bare `pkg-config`, found on PATH
  in `TC/usr/bin` (filled in phase 7) as sed is.
  BINPREF stays `$(R_HOME)/bin/toolchain/` for gcc, g++ and rzig's
  names.
- Windows slim (B42 a): where the archives and r-zig-slim are described
  (README, the recipe's summaries), one line says that Windows slim has
  full's content.
- vendor-libs.sh: the Windows libomp.dll trigger keys on R's OpenMP
  setting instead of `Library/lib/libomp.lib` (vendor-libs.sh:96-100).
  It no longer sees group binaries, since they are not in the R tree. A
  group binary may load only the OS, its own directory and the base's
  runtime (B21: the runtime stays in the base); verify-tree checks that
  on the toolchain tree.
- Patches 0009 and 0010 (B26 a): 0009 calls the check mode for the
  compilers and the build tools instead of its file test, and its
  Makeconf-CC fallback goes; 0010 calls the build-tools check instead
  of its own `command -v`.
- package-standalone.sh: the base archive of the flavor tree and the two
  group archives of the toolchain tree (B17 names), a `.sha256` each;
  only archives.
- hermetic-check.sh: the R tree is the base; nothing is deleted.
- verify-tree.sh: the base's TC holds only rzig; the toolchain tree's
  checks (every file in a directory with `LICENSES/` and `SOURCES`
  entries; closures limited to the OS, the directory itself and the
  base's runtime; the 2.28 glibc ceiling; build-path scan with
  third-party files listed).
- verify-bundle.sh: the three scenarios (Verification) from the
  archives. At this phase the compilers archive holds only `openmp/`, so
  scenario 2 takes zig from `ZIG_BIN=$ZIG` and flang from the env; on
  Windows, scenario 3 takes sh and make from the env until phase 7.
- conda (packages unchanged until phase 4, no bump, B14): recipe/build.sh
  also runs the toolchain step into `$PREFIX` (only what conda does not
  provide: the Windows binutils); r-zig-toolchain still owns all of TC.
- make-wheel.py (wheels unchanged until phase 4): make comes from the
  toolchain tree; wheel-test checks `Sys.which("make")` instead of MAKE.
- CI (B31 a, B12; PHASE3 section 3): a `toolchain` job
  (toolchain.yaml, called from build.yaml, upstream-zig.yaml and
  stress.yaml, C3) builds, archives and checks the groups once per
  platform and uploads the two group archives as
  `toolchain-<runner.os>-<runner.arch>` (`-upstream` for upstream zig),
  kept 30 days, as long as failed legs can be re-run (still short of a
  release, B12). Every leg needs it (with `!cancelled()`, C4), full and
  openblas included, downloads its platform's archives and runs
  `unpack-toolchain`, since contract and stress compile in the compile
  tree. The packaging legs (default, minimal) run verify-package's three
  scenarios on those archives and upload only the base, as
  `standalone-<env>-<os>` (`-upstream`), kept 7 days.

Tests:
- linux-64 (slim, minimal, wheel, conda-package), omicron (osx-arm64
  slim and minimal, osx-64 slim), kappa (win-64), CI.
- The three scenarios on every OS, with the gaps named above.
- kappa and windows-latest: a package that builds a static library
  with `$(AR)` and `$(RANLIB)` (now rzig's zig ar), and one built with
  `--use-LTO` (gcc-ar, gcc-ranlib and the binutils nm); each tool the
  routing check moved, on the packages that use it.
- File lists: base ∪ groups = R tree ∪ toolchain tree, no overlap.

**Status (2026-10-12): steps 1 to 6 done and committed (548da1a, PR
#24). Tested on linux-64 (both zigs), omicron (osx-arm64; osx-64 under
Rosetta), kappa (win-64) and CI (the full tier, upstream-zig and one
stress dispatch, all green; "Phase 3 record: CI on PR #24").** The
worktree feat-standalone-phase3 (branch feat-standalone-phase3, from
main 966d661, with main 888faa6 (PR #23) merged) follows the reviewed
implementation plan (PHASE3-IMPLEMENTATION.md and CRITIQUE.md, in
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/phase3plan/critic/),
with the user's answers to its open points: A (a), the toolchain build
in its own zigbuild/toolchain/build.zig, run by `pixi run toolchain`
through `zig build --build-file`; B (a), a compile tree for contract and
stress; P3-C (a); and to step 3's review (2026-10-11; step 4's record).
B24's routing check moved no tool; dlltool (with as) and windres can
move in follow-up PRs (step 6's record). Next: PR #24 merges; then
feat-zig-pkg-build merges main and adapts to this layout (the user's
order (a), 2026-10-11: its install path needs the build tools only for
packages that need make, so 0009's build-tools check is gated on its
tier); then phase 4.

**feat-zig-pkg-build consolidated (2026-10-12; its PLAN.md,
"Consolidation with phase 3", and `consolidation/CONSENSUS.md` and
`FINDINGS.md` there).** Patch 0009's preflight now runs rzig's
`--rzig-check=package`, which decides as `rzig build` (patch 0013)
decides in run_shlib, through one function (classify the files, then
plan the Makevars and Makeconf): the compilers (flang when Fortran is
compiled), and the build tools only when the package needs make (a
configure script, src/Makefile*, an Objective-C source, a Makevars
with rules, an `include`, conditionals, `$(shell)` or a foreign
compiler, MAKEFLAGS setting a variable, `R_ZIG_PKG_BUILDER=make`)
[records-REC-6] or when R runs a configure script
(`R_ZIG_CONFIGURE=1` from install.R, whatever the tier: tier 0 and 2
packages can have one, and install.R's `R CMD config`, 0010, runs
before it). The failing line gives rzig's reason first (`<pkg> needs
make: src/Makevars has a rule or target line: '...'; no make on PATH`),
then the group's text. 0010 is unchanged: install.R reaches it only
through an R-run configure. The build-tools group is also needed by
`R CMD SHLIB` (run-time compilation: Rcpp's sourceCpp, inline, rstan,
TMB; pkgbuild's has_compiler probe, through which pak refuses every
compiled package before `R CMD INSTALL`), by `R CMD config`'s direct
callers and `R CMD check`'s objdump (Windows), and on Windows by
cleanup.ucrt/cleanup.win under `--clean` or `--preclean`; tier 0 to 2
installs without a configure script R runs, through `R CMD INSTALL` and
install.packages, need it no more [records-REC-6, stress-S10].
verify-bundle scenario 2 asserts the tier-1 install through rzig build
with the compilers alone, the stops for a Makevars rule and (unix) for
an R-only package with a configure script (Windows' pfC and pfM since
the review follow-up below [phase3-P3-9]);
scenario 3 asserts btA through rzig build and btLib through the group's
make in one install.packages run, and the LTO record's tier-1 twin
going to make for MAKEFLAGS' assignment. Phase 7 and B24 are re-scoped
from the stress table that followed the push (TODO.md; the table in
feat-zig-pkg-build's PLAN.md, "Stress dispatch", 2026-10-12: five
runners, 0 unexpected rows; of the 47 rows that compile, 16 (unix) or
17 (Windows) through rzig build, and 31 or 30 need the group: through
make for configure scripts, Makevars rules and (Windows) `$(shell)`,
conditionals and an include [stress-S8], and Rhdf5lib through its
configure script's CMake [stress-S9]; it adds no evidence on B24,
whose dlltool/as follow-up PR stands [stress-S2];
the shared tier-1 runner stays open, since the dispatch shared one
cache and did not measure the per-install cost [stress-S1]; done since
by feat-shared-build-runner, its PLAN.md, after dispatch 38467907779
measured that cost at 3.3 to 12.8 s per tier-1 install). `rzig` /
`rzig.exe` is one more name in `rzig_names()` (the hook's name for
`rzig build` and `rzig def`), and `R_HOME/share/zig/rpkg/` holds the zig
build roots. No build-number bump: phase 4's (8 to 9) publishes both
(since 2026-10-19: phase 7's bump, B14's amendment).

**feat-zig-pkg-build's review follow-up (2026-10-13;
fix-zig-pkg-build-review's PLAN.md, and the review in `review/`
there).** PR #25 merged before the phase 3 session's review finished;
the review's 51 confirmed findings, and 9 more from the fixes' own
review, are fixed in one follow-up PR on main 07e12c0. What
touches this plan: Makeconf.win's NM_FILTER is CRAN's (build.zig
substitutes it; `rzig def` leaves out `.refptr.` and `.weak.` names
too), so package DLLs export what CRAN's do; 0009's stops say "this
package needs the r-zig toolchain (compiled code or a configure
script), which is incomplete (see above)" or "..., which is not
installed: <hint>"; a src/build.zig package whose build would need
make fails with "<pkg>: src/build.zig cannot be built by make:
<reason>" instead of reaching make, and a src/Makefile wins over a
src/build.zig (install.R runs the Makefile with make, so the preflight
asks for the build tools); verify-bundle scenario 2 runs on
Windows too (pfC and pfM) and scenario 3 builds the OpenMP packages
through rzig build there; verify-bundle and contract use the
per-install zig build cache a user's install gets (since
feat-shared-build-runner: for tier 1 the shared build runner in rzig's
cache, contract's in build/rzig-cache). The records above
and TODO.md's phase 4, 7 and later items are corrected from the
review's B items.

#### Phase 3 record: step 1, paths (2026-10-10, linux-64)

What changed (B36, B17):
- env.sh computes each of these once: `PLAT` (conda's name for the
  platform), `ARCHIVE_EXT` (zip on Windows, else tar.gz), `RH` (R_HOME
  in a prefix), `TOP` (`R-<ver>-zig`), `PREFIX`
  (`dist/<flavor>/R-<ver>-zig`) and `TOOLCHAIN_PREFIX`
  (`dist/toolchain/R-<ver>-zig`, used from step 2). `R_HOME_DIR` is
  `$PREFIX/$RH`. The old `PREFIX`, `dist/R-<ver>-<flavor>`, was a path
  nothing installed into: only configure-only.sh's capture passed it to
  R's configure, and gen-subst.sh turns it into `@ZR_PREFIX@` before
  `$ROOT`, so the vendored configs do not change (C37).
- zig-build.sh, zig-smoke.sh, zig-contract.sh, hermetic-check.sh and
  verify-tree.sh read `PREFIX` and `RH` instead of deriving
  `dist/R-<ver>-<flavor>-zig` each.
- package-standalone.sh archives `$PREFIX` from its parent, so the top
  directory is `R-<ver>-zig/`. A prefix of another name fails (B1). The
  archive's name is unchanged. verify-bundle.sh reads `PLAT`,
  `ARCHIVE_EXT` and `TOP`. Their two copies of the platform table are
  gone.
- zig-package.sh and zig-verify-package.sh are deleted. The tasks
  `package` and `verify-package` call package-standalone.sh and
  verify-bundle.sh.
- make-wheel.py's `--prefix` default is `dist/<variant>/R-<ver>-zig`.
- The stress task runs `dist/slim/R-<ver>-zig`'s Rscript.
- clean.sh removes the flavor's tree, since `PREFIX` names it now.
- Comments that named `dist/R-*-zig` follow: pixi.toml, recipe/build.sh,
  rzig's smoke-test.sh, verify-tree.sh's first lines.
- Trees from before, `dist/R-<ver>-<flavor>-zig/`, stay on disk and
  nothing reads them. Delete them by hand.

Three changes the plan puts elsewhere, each from the same rule (every
script reads env.sh's names):
- verify-bundle.sh's `BUNDLE_DIR` is `$VERIFY_DIR/$TOP` now, not in step
  3's rewrite: the top directory changes in this step.
- make-wheel.py's default moves now, not in step 3 (TODO.md lists it
  with env.sh): the wheel reads the moved tree.
- fetch-zig.sh's wheel table is keyed on `PLAT`: it computed the
  platform name too.

PR #23 overlap: this step changes verify-tree.sh's lines 4, 71 and 73
only, outside #23's hunks. `git merge-file` of verify-tree.sh,
vendor-libs.sh, build.zig and recipe.yaml against #23's worktree (merged
with 966d661) gives no conflict.

Tests (linux-64, conda-forge zig 0.16.0, every task with `--locked`;
the code diff, records left out, had sha256 1f83a7ee...877218; pixi.lock
had sha256 fbb64b7b...a68bb96 before and after):
- `rzig-test`: 94/94 unit tests; parity 76 / 59 / 34 deliberate / 0
  failed.
- default (slim), from an empty worktree: build (R fetched, then 2m56s)
  into `dist/slim/R-4.6.1-zig`, verify-tree, smoke, contract, hermetic
  and verify-package pass.
- minimal: build into `dist/minimal/R-4.6.1-zig`, verify-tree and
  verify-package pass.
- wheel: wheel (from `dist/minimal/R-4.6.1-zig`) and wheel-test pass.
- The archives keep their names (`dist/R-4.6.1-slim-linux-64.tar.gz`,
  `dist/R-4.6.1-minimal-linux-64.tar.gz`), and each has the one top
  directory `R-4.6.1-zig`. Their `.sha256` files check.
- package-standalone.sh with `R_INSTALL_PREFIX` naming the slim tree
  through a link of another name fails with the B36 message and writes
  nothing.
- `pixi run -e stress stress --help` and `--list g1` run the moved
  tree's Rscript.
- `fetch-zig` prints `build/zig-upstream/ziglang-0.16.0-linux-64/...`,
  the same directory as before, and that zig says 0.16.0.

#### Phase 3 record: step 2, the toolchain tree (2026-10-10, linux-64)

What changed (B30, B17, point 3; open point A (a)):
- zigbuild/toolchain/build.zig, a build root of its own, as rzig's is:
  `zig build --build-file zigbuild/toolchain/build.zig --prefix <tree>`.
  It needs no R source and runs no R configure. It copies the groups'
  third-party files from the env (CONDA_PREFIX) into
  `<tree>/<RH>/bin/toolchain/`: `openmp/` (llvm-openmp's omp.h, and
  ompx.h, omp-tools.h and ompt.h where the env has them, installOpenMP's
  list; Windows also `lib/libomp.lib`), unix `usr/bin/make`, Windows
  `binutils/` (nm, dlltool, as, strip, windres and objdump, with the two
  DLLs they load, below). R's build.zig is not touched: the R trees keep
  their copies until step 3, at other paths, so nothing breaks.
- zigbuild/toolchain/conda.zig: the conda-meta reader and the SOURCES
  writer, with 5 unit tests on fixture records (paths_data, a prefix
  placeholder, a file in no record, a file missing from paths_data, a
  path with a blank, a Windows record's `\`; C31).
- A file's package is the conda-meta record whose `files` lists its path
  (C23). A file no record lists, one with no sha256 in paths_data, one
  with a prefix placeholder, and a package with no licence files stop
  the build and name it.
- `SOURCES` in each directory: one block per package (`package:`,
  `version:`, `build:`, `url:`, `sha256:`, `license:`), then one line per
  file, `file: <path in the package> -> <path here> <sha256>`. It names
  no local path. `LICENSES/<package>/` is the package's
  `info/licenses/` from the package cache (the record's
  `extracted_package_dir`), subdirectories kept. A missing cache stops
  the build with "reinstall the env (pixi reinstall; in CI, setup-pixi
  with cache: false)" (C33, risk 2).
- When the prefix is the env (the conda build, from step 3), only
  Windows' six binutils are installed, with their records (B41); conda's
  packages provide the rest. On unix nothing is installed.
- scripts/zig-toolchain.sh runs it with env.sh's `$ZIG` (both zigs).
  A plain install first removes env.sh's toolchain tree (zig's install
  keeps files it no longer installs), never an `R_TOOLCHAIN_PREFIX`.
  Its arguments go to zig build: `zig-toolchain.sh test` runs the unit
  tests.
- package-standalone.sh takes a mode, `base` (the default, as before) or
  `toolchain`: one archive per group,
  `dist/R-<ver>-<plat>-<group>.<ext>` and its `.sha256`, holding the
  group's directories under `R-<ver>-zig/<RH>/bin/toolchain/` (B17,
  B36). It checks first that every file of the tree is in a group
  directory and that each group has a directory, then writes.
- scripts/verify-toolchain.sh, the tree's static checks: layout (group
  directories only), records (SOURCES, a non-empty `LICENSES/<package>/`
  per package and no other), each copy's sha256 against SOURCES, build
  paths (in SOURCES or LICENSES: an error; in a copy: listed, C18),
  closures (linux: glibc's libraries only, GLIBC at most 2.28, relative
  rpaths; macOS: /usr/lib and /System, minos at most 13.0; Windows:
  every import beside the file or the system's) and OpenMP's files.
- scripts/unpack-toolchain.sh rebuilds the tree from the two archives
  in `dist/`: it checks each `.sha256` and that each archive's members
  lie under its own group's directories, removes env.sh's tree and
  extracts both (C6).
- env.sh: `TOOLCHAIN_GROUPS` and `group_dirs` (compilers: zig, flang,
  openmp; build-tools: usr, binutils). Only directories that exist count.
- verify-helpers.sh: `archive_files` (an archive's files and links, no
  directories) and `extract_archive` (`unzip -q -n`); verify-bundle.sh
  extracts with it. Also `path_forms` and `path_re`, verify-tree.sh's
  build-path helpers, for verify-toolchain.sh. verify-tree.sh keeps its
  own copies until step 3, since they sit in PR #23's block. #23's
  `path_forms` also prints each directory's 8.3 short name on Windows
  (`cygpath -m -s`); the helper's copy does not yet. Step 3, which
  drops verify-tree.sh's copies, takes #23's body into the helper.
- pixi.toml, `[feature.pipeline.tasks]`: `toolchain`, `toolchain-test`,
  `verify-toolchain`, `package-toolchain` (depends on `toolchain`) and
  `unpack-toolchain`. No dependency change.

Choices, with their reasons:
- `binutils/` copies zstd.dll and vcruntime140.dll, where the plan's
  table names zstd.dll alone. C23's check, done from linux on the lock's
  win-64 packages (sha256 as in pixi.lock), read with objdump -p: the six
  tools of binutils_impl_win-64 2.46.1 import KERNEL32, API sets and
  zstd.dll; zstd.dll (zstd 1.5.7) imports VCRUNTIME140.dll
  (vc14_runtime) besides KERNEL32 and API sets; vcruntime140.dll imports
  only KERNEL32 and API sets. With both, the tools load with only the
  system beside them on any Windows, also one without the VC++
  redistributable, which is what the plan wanted from zstd.dll there.
  It is the base's rule too: vendor-libs.sh copies every import the
  env's Library/bin has beside R.dll, vcruntime140.dll included.
  verify-toolchain.sh checks the closure on kappa. The same check shows
  objdump ships in binutils_impl_win-64 (the phase's "check that it
  ships it").
- The linux closure rule is "glibc's libraries" (libc, libm, libdl,
  libpthread, librt, libutil, libresolv, ld-linux), not the plan's
  "libc, libdl and ld.so": one rule for the system's C library. make
  needs libc and libdl.
- `group_dirs` is a function: a group name has a `-`, which the plan's
  `GROUP_DIRS_<group>` variables cannot have.
- `toolchain-test` runs `zig-toolchain.sh test`, as `check` runs
  `zig-build.sh check`, rather than an inline `bash -c`.

Tests (linux-64, conda-forge zig 0.16.0 unless named, every task with
`--locked`; the code diff, records left out, had sha256
f59cc4a0...feae69; pixi.lock had sha256 fbb64b7b...a68bb96 before and
after):
- The chain: `rzig-test` (94/94; parity 76 / 59 / 34 deliberate / 0
  failed), `toolchain-test` (5/5), then default (slim) build,
  verify-tree, smoke, contract, hermetic and verify-package; minimal
  build, verify-tree and verify-package; wheel and wheel-test; `stress
  --help` and `--list g1` (dist/slim's Rscript); toolchain,
  verify-toolchain, package-toolchain, verify-toolchain. All pass.
- `toolchain-test` and `toolchain` with upstream zig (ZIG_BIN from
  fetch-zig) pass, and so does `-e minimal toolchain`. Both trees are
  identical to the default env's with conda-forge zig. Its configure
  step takes about a second.
- The toolchain tree, `dist/toolchain/R-4.6.1-zig/lib/R/bin/toolchain/`:
  `openmp/include/{omp.h,ompx.h,omp-tools.h,ompt.h}`, `openmp/SOURCES`
  (llvm-openmp 23.1.2), `openmp/LICENSES/llvm-openmp/openmp/LICENSE.TXT`,
  `usr/bin/make`, `usr/SOURCES` (make 4.4.1),
  `usr/LICENSES/make/COPYING`. verify-toolchain: 9 files, 5 copies with
  the packages' sha256, make needs libc and libdl and GLIBC 2.17.
- The archives: `R-4.6.1-linux-64-compilers.tar.gz` (32K: the 4
  headers, SOURCES, LICENSE.TXT) and `R-4.6.1-linux-64-build-tools.tar.gz`
  (152K: make, SOURCES, COPYING), each under `R-4.6.1-zig/`, with
  `.sha256` files that check.
- One directory, base + compilers + build-tools: the slim base archive
  (1,941 files and links) and the groups (6 and 3) have disjoint lists,
  the base's equals the slim tree's, the groups' together equal the
  toolchain tree's; extracted into one directory, all 1,950 are there,
  under one `R-4.6.1-zig/`, with `openmp/` and `usr/` beside rzig in
  `lib/R/bin/toolchain`. That make says GNU Make 4.4.1 and the
  extracted Rscript runs, both under `env -i`. The same with minimal's
  base (1,402): its `TC/make` (until step 3) sits beside the group's
  `usr/bin/make`, no overlap.
- unpack-toolchain rebuilds the tree from the two archives, identical
  to the built one (a stray file put in before is gone). It refuses an
  archive that fails its `.sha256`, and a build-tools archive (with a
  matching `.sha256`) that holds a file of `openmp/`.
- verify-toolchain fails, naming the file, on: a copy changed (sha256),
  a file directly in TC, a file in a directory of no group, a missing
  `LICENSES/make/`, a SOURCES that names the checkout, a file with no
  SOURCES line, a SOURCES line with a short sha256. A copy that names
  `$HOME` (with SOURCES' sha256 matching it) is listed and passes.
- package-standalone.sh's toolchain mode fails, writing no archive, on
  a file outside the group directories, a tree with no build-tools
  directory, and a tree not named `R-4.6.1-zig`; an unknown mode prints
  the usage. The helpers' zip branch (Windows' format) round-trips with
  the env's zip and unzip, and a second extract over it asks nothing.
- With `R_TOOLCHAIN_PREFIX` naming the env, the build installs nothing
  on unix ("the prefix is the env") and the env is unchanged.
- PR #23 overlap: this step does not touch build.zig, verify-tree.sh,
  vendor-libs.sh or recipe.yaml (verify-tree.sh keeps step 1's three
  lines).

Not tested in this step: the Windows table (`binutils/`, libomp.lib,
`Library/` paths, the closure check with objdump) and macOS (kappa,
omicron); CI; conda-package (recipe/build.sh calls the toolchain build
from step 3).


After the steps 1-2 review (2026-10-10), applied and re-run on linux-64
(lock fbb64b7b): gen-subst.sh keeps its config name in its own variable
(cfg_plat), not env.sh's PLAT; package-standalone.sh and
unpack-toolchain.sh convert an override path with cygpath -u on Windows;
zig-toolchain.sh starts from no tree on every install, arguments or not
(only `test` keeps it); conda.zig stops on a file two packages list
(TwoOwners). toolchain-test, toolchain, verify-toolchain,
package-toolchain and unpack-toolchain pass; a stray file is gone after
`pixi run toolchain --summary none`. Left for step 3, once #23 is on
main: verify-helpers.sh's path forms get #23's Windows 8.3 short names.

#### Phase 3 record: P3-C, where the sources are (2026-10-10, linux-64)

P3-C (a), the user's answer after the steps 1-2 review: SOURCES says
where each package's program comes from, for the GPL tools above all
(make, binutils), whose binaries ship with a pointer to their source.
- Each package block gains, after `license:`, a `source:` line per
  source of the package's recipe (its URL, the first of its mirrors, and
  `sha256:` or `md5:`; or a git repository and `rev:`) and one
  `feedstock:` line, the recipe's repository and commit (conda-forge's
  feedstock: its patches are there). A package with none says `unknown`.
- Both come from the package cache, as LICENSES does: the rendered
  recipe (rattler-build's `info/recipe/rendered_recipe.yaml`,
  `finalized_sources`, else conda-build's `info/recipe/meta.yaml`,
  `source`) and `info/about.json` (`extra.remote_url`, `extra.sha`).
  conda.zig reads the YAML with a line scanner (both tools write it in
  block style); unit tests on the shapes in this cache: a mapping
  (make), lists with mirrors and patches first (binutils, gcc), column-0
  lists and git sources (rattler-build).
- A GPL package (GPL, LGPL, AGPL in its licence) whose recipe lists no
  source stops the toolchain build.
- verify-toolchain.sh checks each block has a `source:` line or more and
  one `feedstock:` line (a SOURCES without its feedstock line fails).

Run on linux-64: toolchain-test (8 tests), toolchain, verify-toolchain,
package-toolchain, unpack-toolchain. `openmp/SOURCES` names
llvmorg-23.1.2.zip and openmp-feedstock 51dc92fc; `usr/SOURCES` names
make-4.4.1.tar.gz and make-feedstock 1060ed0e.

main (888faa6, PR #23) merged into the branch with no conflict.
verify-helpers.sh's `path_forms` takes #23's 8.3 short names, and
verify-tree.sh uses the helpers' `path_forms` and `path_re` instead of
its own copies.

#### Phase 3 record: step 3, the base and the three scenarios (2026-10-10, linux-64)

What changed (B19-B25, B30, B40, B43; open point B (a); C1, C2, C11,
C12, C15, C19, C20, C25, C27, C28, C30, C32, C36):
- build.zig, the base: minimal's `TC/make` and `installOpenMP` are gone,
  so no R tree has `include/omp*.h`, `Library/include/omp*.h`,
  `Library/lib/libomp.lib` or a make; libomp itself stays in the base
  (B21). installWindowsCompilerContract no longer copies ar, ranlib, nm,
  dlltool, strip, as, ld and windres into TC, and its `toolchain_dir`
  went with the loop (C1). installRzig's Windows names are gcc.exe,
  g++.exe, zig-fc.exe, zig-ar.exe, zig-ranlib.exe, gcc-ar.exe and
  gcc-ranlib.exe (B43), ar.exe and ranlib.exe (the names CMake looks for
  beside CC; the review below), plus zig-cc and zig-cxx until step 4.
  Comments that named installOpenMP or the moved files follow (C15).
- etc/Rcmd_environ (rcmdEnviron, Windows): after R's file and before the
  CMake lines, with R's CRLF ends,
  `R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin` and
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_ZIG_TOOLS_PATH}};${PATH}/"` (B25);
  `R_ZIG_RC` names `bin/toolchain/binutils/windres.exe`.
- etc/Renviron (finalRenviron, unix, every flavor and the conda build):
  minimal's `R_ZIG_MAKE` branch is gone, so `MAKE=${MAKE-'make'}` is R's
  own everywhere (B25 a), and the file ends with
  `PATH=${R_HOME}/bin/toolchain/usr/bin:${PATH}`.
- zigbuild/config/win-x86_64-full/Makeconf.win (section 5 of the plan):
  `PKG_CONFIG = pkg-config`; DLLTOOL (with its `--as`), both NM lines,
  RESCOMP (with windres' `--preprocessor` arguments) and STRIP_* name
  `$(R_HOME)/bin/toolchain/binutils/<tool>.exe`, OBJDUMP
  `$(R_HOME)/bin/toolchain/binutils/objdump` with no `.exe`, which R
  CMD check adds (sotools.R; the review below); AR and
  RANLIB are `$(BINPREF)zig-ar.exe` and `$(BINPREF)zig-ranlib.exe`. The
  LTO block and LLVMPREF are unchanged. One `## r-zig:` block says why
  (B24, B43, B43-2, B43-3, C21).
- vendor-libs.sh: Windows copies libomp.dll into `bin/x64` wherever
  Makeconf offers OpenMP (`^SHLIB_OPENMP_CFLAGS = *-`), no longer keyed
  on a libomp.lib in the tree: rzig counts `TC/openmp/` only where the
  base has that DLL (B40).
- rzig: groups.zig's standalone lines name the group archives (unix
  build-tools `extract R-<ver>-<plat>-build-tools.tar.gz where you
  extracted R, or put GNU make on PATH`; Windows build-tools names
  binutils and its .zip; compilers adds `for OpenMP, extract
  R-<ver>-<plat>-compilers.<ext> where you extracted R`, C19). check.zig:
  on Windows the build-tools check also needs the six binutils at
  `<rzig dir>/binutils/{nm,dlltool,as,windres,strip,objdump}.exe` (one
  list; a missing one exits 127 with the build-tools text, success adds
  `; binutils at <dir>`); the lines show paths with `/` only on Windows
  (display only); a zig that cannot start or that a signal ends says
  `did not run: <reason>`. Ctx.zig's `capture` keeps that reason
  (`Output.not_run`). main.zig: the names `ar` and `ranlib` (as zig-ar
  and zig-ranlib; the review below); environment.zig: doc comments only.
  Unit tests 94 → 96 (C30), and parity-test.sh greps the new lines.
- The compile tree (open point B (a)): scripts/compile-tree.sh makes
  env.sh's `COMPILE_TREE`, `build/compile-tree/<flavor>/R-<ver>-zig`, a
  fresh `cp -a` of the R tree plus every group directory of the
  toolchain tree but zig/ and flang/ (C12; in phase 3 openmp/ and usr/
  or binutils/). It stops when the R tree or a build-tools directory is
  missing. Task `compile-tree`; `contract` and `stress` depend on it and
  run its Rscript (zig-contract.sh). clean.sh removes it too (C36).
  contract-test.sh: on Windows `R CMD config NM` names a file that exists
  (C11).
- verify-tree.sh: TC holds rzig's names and nothing else, no directory
  (a conda tree on win-64 may have binutils/, B41); a leftover fails with
  "remove the tree and build again" (C25). The names come from
  verify-helpers.sh's `rzig_names`, shared with verify-bundle.sh. New
  whole-line checks (CR dropped, C20): Windows Makeconf's lines of
  section 5, the three LTO lines, no binutils tool through `$(BINPREF)`;
  Rcmd_environ's `R_ZIG_TOOLS_PATH`, PATH and `R_ZIG_RC` lines; unix
  Renviron's PATH line and `MAKE=${MAKE-'make'}`. OpenMP: no compile-time
  file in the base; the runtime where Makeconf offers OpenMP, none where
  it does not. glibc: one floor, 2.17, for every ELF (the 2.28 tier is
  verify-toolchain.sh's).
- verify-bundle.sh, rewritten around the three scenarios (section 8,
  C2). Inputs: the base archive and both group archives with their
  `.sha256`. Before extracting: the base's file list equals the R tree's,
  it holds no compile-time OpenMP or environment file (Tcl/Tk's headers
  stay, T1) and nothing in TC but rzig, each group archive holds only its
  directories, and no file is in two archives (C6). Then:
  - 1, the base: R and its capabilities, PATH starting with
    `R_HOME/bin/toolchain/usr/bin` in R and under R CMD (Windows: the
    entry after bin\x64, or R_CUSTOM_TOOLS_PATH; C27), rzig's check mode
    exits 127 for both groups (texts from step 4), TLS, and
    hermetic-check.sh on the extracted base.
  - 2, + compilers: the check mode names `ZIG_BIN` and the env's flang;
    the baseline CPU; unix's compiled-package block, now with omp.h from
    `TC/openmp/include` (RZIG_PRINT_ARGV shows the `-I`) and, on
    minimal, openmp/ unused and a flagless `#include <omp.h>` failing
    (B40); Windows' dry runs with openmp/'s `-idirafter` and `-L`, and an
    OpenMP DLL linked by gcc.exe alone.
  - 3, + build-tools: unix, rzig's check mode under R CMD and
    `Sys.which("make")` name the group's make, `make --version` says the
    version SOURCES records, install.packages with Ncpus = 2 builds btA
    and btLib (a static library through `$(AR)` and `$(RANLIB)`, rzig)
    and, under strace on linux, the group's make is the only one that
    ran. Windows: every tool path Makeconf names is a file but the LTO
    gcc-nm, `R CMD config` AR, NM and OBJDUMP, R CMD check's
    `tools:::read_symbols_from_dll` on R.dll with the group's objdump
    (the review), nm.exe with PATH = System32, the check mode under
    `R.exe CMD`, a tools.mk running each binutils tool through
    Makeconf's rules (C10, C11), rzig's ar.exe and ranlib.exe beside
    gcc.exe making a static library with PATH = System32 (CMake's
    archiver; the review), the OpenMP
    packages, btA, btLib and btRc (a `.rc` in OBJECTS), and the LTO
    record (C9).
- verify-helpers.sh: `tree_files` (a tree's files and links as an
  archive of it lists them) and `rzig_names`.
- make-wheel.py: `--toolchain-prefix` (default
  `dist/toolchain/R-<ver>-zig`); the r-zig-toolchain wheel takes rzig ×5
  from the R tree and `lib/R/bin/toolchain/usr/**` (make, SOURCES,
  LICENSES/) from the toolchain tree, not openmp/ (B29); leak_scan covers
  those files. wheel-test.sh checks `Sys.which("make")` ends in
  `bin/toolchain/usr/bin/make` and MAKE is `make`, and that uninstalling
  r-zig-toolchain leaves no file under R_HOME/bin/toolchain (C32).
- recipe: build.sh runs `R_TOOLCHAIN_PREFIX="$PREFIX" bash
  scripts/zig-toolchain.sh` after zig-build.sh (unix: nothing to
  install; win-64: TC/binutils/ with SOURCES and LICENSES/, B41, which
  r-zig-toolchain owns with the rest of TC). recipe.yaml: comments,
  r-zig-slim's `about:` saying Windows slim has full's content (B42 a),
  r-zig-toolchain's summary naming Windows' binutils; no bump (B14).
  test-toolchain.R: AR and RANLIB are rzig's on every OS and a package
  links a static library made with them; on Windows NM names
  `binutils/nm.exe`, the six tools exist, SOURCES names
  binutils_impl_win-64 with a sha256, LICENSES/ is not empty and
  `nm --version` runs (C28); R CMD check's read_symbols_from_dll reads
  R.dll with OBJDUMP, and ar.exe and ranlib.exe are beside CC (the
  review).
- Docs: pixi.toml's comments (contract, verify-tree, package,
  verify-package, compile-tree, the wheel feature, stress), the
  hermetic-check.sh header, zigbuild/toolchain/build.zig's header list
  comment. Phase 9's "installOpenMP's comment" item is gone with the
  function (C14).

Choices and deviations, with their reasons:
- Windows PATH line through a helper variable, not B25's
  `${R_CUSTOM_TOOLS_PATH:-${R_HOME}/bin/toolchain/usr/bin}`: Renviron.c's
  `subterm` expands a default only when it is a whole `${...}` term and
  would leave that one as it is (C16). The helper comes first;
  verify-tree.sh checks the lines, not their order, and verify-bundle's
  run-time check (C27) would see an empty entry.
- AR and RANLIB are `$(BINPREF)zig-ar.exe` and `$(BINPREF)zig-ranlib.exe`,
  with `.exe` where B43 wrote `$(BINPREF)zig-ar`: CMake takes a tool from
  `R CMD config` only when it names an existing file, as for CC (S15;
  C16).
- `binutils/` carries zstd.dll and vcruntime140.dll beside the six tools
  (step 2's record), so they load with only the system beside them,
  stricter than the phase's "the base's runtime" (C16). verify-bundle's
  scenario 3 runs nm.exe with PATH = System32 to show it.
- The compile tree is a copy under build/ (open point B (a)): the R tree
  stays the base that ships, contract compiles as a user with all three
  archives does, Windows gets the binutils Makeconf.win names, and
  openmp/ makes contract run B40 on every leg (C12). Only a build-tools
  directory is required; without openmp/ a slim contract would take
  omp.h from R_ZIG_EXTRA_ENV. (Superseded in step 4: openmp/ is required
  too where the base has the libomp runtime, the user's answer (4).)
- Scenario 2's make (C17): unix compiles there use the env's make, which
  stands in for "a make that is not the group's" (PLAN's Verification
  says the host's /usr/bin make): the env's is on every machine this runs
  on, where a host has none (CI's containers) or Apple's 3.81 (omicron).
  Scenario 3 checks the group's.
- `did not run` exits 1 and R_ZIG_NO_PREFLIGHT skips it, as the version
  check it sits in; the preflight tests only for a non-zero status. An
  rzig that cannot tell its own directory fails the Windows binutils
  check naming `R_HOME/bin/toolchain/binutils/nm.exe`.
- The `/`-only display follows Windows' rules (ctx.os), so its unit test
  runs on every host.
- verify-tree.sh checks more than the plan's bullets: the B40 converse
  (minimal has no libomp runtime, which would make rzig count openmp/),
  the compile-time OpenMP files on every tree that is not a conda env,
  all three LTO lines, and no binutils tool through `$(BINPREF)` (the
  template sets NM twice and make takes the last). Lines are compared
  whole after `tr -d '\r'` (has_line, `grep -xF`), not with `\r?$`
  patterns: no escaping of `$(...)`, and one grep's CR handling no
  longer matters. The conda exception is binutils/ on win-64 only.
- verify-bundle.sh: install.packages from a local `file:` repository,
  not `repos = NULL`, since only a repository install reads Ncpus and
  runs R's `make -k -j 2`; env -i runs get a fresh HOME, so no
  ~/.R/Makevars or rzig cache of this machine reaches them; Windows'
  builds run under env -i with Windows' own variables, and fomp/fompfc
  get flang's directory (the env's Library/bin) last on PATH, since
  flang.exe cannot be copied and phase 6 brings TC/flang (corrected by
  the SHLIB record and phase 6: a copy works, since its resource
  directory follows the binary and zig-fc passes the modules path;
  since phase 6 they use TC/flang with no flang on PATH); the make
  version comes from usr/SOURCES; Makeconf.win's tool paths are read
  from make's own expansion (plain and with LTO_OPT=-flto), not a text
  scan; `R.exe CMD` gets gcc.exe as a `cygpath -w -s` path, which
  rcmdfn.c puts into cmd.exe's line unquoted (C5); scenario 1's check
  mode asserts exit 127 only, and the compilers' check is skipped with a
  note where the host has a zig in /usr/bin or /bin.
- etc/Renviron's PATH line is the file's last line, after the CMake, CA
  and Tcl lines.
- make-wheel.py stops when the R tree's TC holds anything but rzig (a
  pre-phase-3 TC/make would ship beside usr/bin/make; C25); its message
  says `pixi run -e minimal toolchain`. wheel-test's uninstall check
  covers all of R_HOME/bin/toolchain (C32's superset).
- test-toolchain.R checks AR and RANLIB on every OS, not only Windows,
  and runs `nm --version` there (B41's copies in an activated env).
- The integration pass: verify-tree.sh takes the names from
  `rzig_names` (one list for step 4 to shorten), and the stale comments
  above.

Tests (linux-64, every task with `--locked`, TMPDIR on /data; dist/'s
trees and archives removed first, C25; the code diff, records left out
and compile-tree.sh included, had sha256 b11f6e54...ddbce0b; pixi.lock
had sha256 fbb64b7b...a68bb96 before and after):
- `rzig-test`: 96/96 unit tests; parity 79 identical / 59 / 34
  deliberate / 0 failed, with conda-forge zig 0.16.0 and with upstream
  zig 0.16.0 (ZIG_BIN from fetch-zig). `toolchain-test` passes with both.
- default (slim), conda-forge zig: build, toolchain, verify-tree,
  verify-toolchain, smoke, contract (in the compile tree, with openmp/
  and usr/), hermetic, package-toolchain and verify-package pass. The
  base archive has 1,937 files and links, the groups 6 and 3; scenario 3
  shows GNU Make 4.4.1 at the extracted `TC/usr/bin/make`, the only make
  strace saw run.
- minimal: build, verify-tree (no libomp, no omp.h), contract (compile
  tree) and verify-package (1,401 files; openmp/ there and unused) pass.
- wheel: r_zig (1,402 files) and r_zig_toolchain (rzig ×5,
  `usr/bin/make`, `usr/SOURCES`, `usr/LICENSES/make/COPYING`) from
  `dist/minimal` and `dist/toolchain`; wheel-test passes (make at
  `.../bin/toolchain/usr/bin/make`).
- default (slim) again with upstream zig 0.16.0 (ZIG_BIN from
  fetch-zig): build, toolchain, verify-tree, verify-toolchain, smoke,
  contract, hermetic, package-toolchain and verify-package pass;
  scenario 2's check mode names that zig.
- After the integration's last edits (comments, and verify-tree.sh's
  `rzig_names`): zig fmt and bash -n clean; verify-tree (slim with
  upstream zig, minimal) passes again.

Not tested in this step: Windows (Makeconf.win, Rcmd_environ, the
binutils check, scenario 3's tools.mk, `.rc` and LTO runs, the PATH run
check) and macOS, which need kappa and omicron; conda-package (C22's
host records and path lengths are kappa's first conda run); CI, whose
contract, stress and verify-package legs need step 5's toolchain job
and artifact (contract and stress now depend on compile-tree, which
needs a toolchain tree; verify-package reads the group archives in
dist/). README (`pixi run toolchain` before contract, `pixi run -e
minimal toolchain` before wheel) is step 5's.

#### Phase 3 review: step 3 (2026-10-10)

Three reviews of the uncommitted step 3 diff, one lens each:
correctness (the scripts', rzig's and the tests' logic), Windows
(Makeconf.win, Rcmd_environ and the binutils as R, make and CMake run
them, read against R 4.6.1's sources) and the plan (the records,
TODO.md and the docs against the code). A verifier confirmed each
finding before the fix. Six findings, none failing linux-64:
- Windows, OBJDUMP: R CMD check takes `R CMD config OBJDUMP` only when
  its value plus `.exe` is a file (sotools.R's read_symbols_from_dll,
  written for upstream's OBJDUMP, which has no `.exe`). Step 3's
  `.../binutils/objdump.exe` made it look for `objdump.exe.exe`, fall
  back to an objdump.exe on PATH, which neither a standalone tree nor a
  conda env has, and skip every compiled-code check with "this requires
  'objdump.exe' to be on the PATH". Fixed: Makeconf.win's OBJDUMP names
  `$(R_HOME)/bin/toolchain/binutils/objdump`, and its comment says why;
  R's system() (run.c's expandcmd) and sh find objdump.exe from it.
  verify-tree.sh's line follows (the comment avoids a `$(BINPREF)`
  tool name, which its BINPREF scan would count); scenario 3 tests R
  CMD config's value plus `.exe` and runs `tools:::read_symbols_from_dll`
  on R.dll under env -i, PATH = bin\x64, the env's usr/bin and System32,
  where it must take the group's objdump; test-toolchain.R does the same
  in the conda env.
- Windows, CMake's archiver: CMakeFindBinUtils (read in cmake 4.4) looks
  for `llvm-ar`/`ar` and `llvm-ranlib`/`ranlib` in the C compiler's
  directory before PATH, and packages hand it R CMD config CC,
  `TC/gcc.exe`. Step 3 took MinGW's ar.exe out of that directory, so a
  CMake-built static library with no ar on PATH (a standalone user; a
  conda env has only `x86_64-w64-mingw32-ar.exe`) would stop at
  CMAKE_AR-NOTFOUND. Fixed with the review's option (b), closer to B43
  than a CMake toolchain file: rzig is also `TC/ar.exe` and
  `TC/ranlib.exe` on Windows, and its name map serves `ar` and `ranlib`
  as zig-ar and zig-ranlib. CMake finds them with no environment
  variable, also under a package's own toolchain file, and
  `$(BINPREF)ar` works again. rzig_names, the unit test (its "ar and
  ranlib are no names" line goes) and two parity cases follow; scenario
  3 checks both are rzig and make a static library with PATH = System32
  as CMake runs them (`qc`, then ranlib); test-toolchain.R checks they
  are beside CC. A CMake run itself is kappa's (TODO.md: stress
  RcppParallel with no ar on PATH).
- parity-test.sh: the three new check-mode checks (a zig that does not
  say its version, one that does not run, Windows' missing binutils)
  piped into `grep -q` and then tested `${PIPESTATUS[0]}`, so only the
  exit code counted. Fixed: those and the three older checks of that
  form (no zig, another major.minor, a compile with no zig) write stderr
  to a file, test the code and then grep the file, as the fortran and
  build-tools checks do.
- TODO.md had ticked Windows' Rcmd_environ box as "checked on linux-64
  by verify-tree.sh's lines, run on Windows by kappa": verify-tree reads
  those lines only on Windows, and nothing has run on kappa. Unticked,
  with what kappa owes.
- stress/README.md's local recipe lacked `pixi run toolchain` (the
  stress task runs the compile tree's R now), and its `--conda` note
  said any R starts the run. Fixed.
- package-standalone.sh's header still said contract saw exactly the
  archived tree; it now says contract compiles with the compile tree.

Open, for the user (the implementers' questions, unchanged here): a zig
that does not run exits 1, not 126; the compilers text names the
compilers archive for OpenMP on minimal too, where B40 leaves openmp/
unused; verify-tree.sh does not check the order of Rcmd_environ's lines
(verify-bundle's PATH run check, C27, would see a wrong one);
compile-tree.sh does not require openmp/ where the base has libomp.
(Answered 2026-10-11: step 4's record.)

Ran again (linux-64, every task with `--locked`, TMPDIR on /data,
conda-forge zig 0.16.0 unless named; dist/'s trees and archives removed
first, C25):
- `rzig-test`: 96/96 unit tests; parity 81 identical / 59 / 34
  deliberate / 0 failed (79 before, plus the two `ar`/`ranlib` cases),
  with conda-forge zig and with upstream zig (ZIG_BIN from fetch-zig).
  rzig cross-builds for x86_64-windows-gnu and its unit tests compile
  for it (not run: no Windows here).
- slim: build, toolchain, verify-tree, verify-toolchain, smoke,
  contract, hermetic, package-toolchain and verify-package pass (the
  base 1,937 files and links, the groups 6 and 3; scenario 3: GNU Make
  4.4.1, the only make strace saw run).
- minimal: build, verify-tree, contract and verify-package pass (1,401
  files; openmp/ there and unused).
- conda-package (the task's rattler-build command with its output
  under /data): r-zig-slim and r-zig-toolchain build 8 build and pass
  their tests; build.sh's zig-toolchain.sh says "nothing to install",
  and test-toolchain.R's static-library package (AR and RANLIB, rzig)
  links and loads. The first conda-package run of step 3 (linux-64
  only; C22 stays kappa's).
- pixi.lock: sha256 fbb64b7b...a68bb96 before and after. The code diff
  as left (records left out, compile-tree.sh included) has sha256
  8a1a5170...3f1a8e1; it differs from what the runs used only in
  Makeconf.win's comment, edited after them, which no linux run reads.

Not run: the Windows-only fixes (Makeconf.win's OBJDUMP, rzig's ar.exe
and ranlib.exe, the new checks in verify-bundle's Windows scenario 3
and in test-toolchain.R's Windows block), read twice and checked
against the template (verify-tree's Makeconf lines and BINPREF scan
run on it); they join step 3's Windows list for kappa. wheel and
wheel-test: no wheel file changed.

#### Phase 3 record: step 4, the preflight (2026-10-11)

What changed (B26 a, B35; C8, C26, C29):
- Patch 0009 (install.R, before the configure step). For a package with
  `src/`, or with a configure script R runs (unix `configure`; Windows
  `configure.win` or `configure.ucrt`), and with no user Makevars and no
  R_ZIG_NO_PREFLIGHT, it runs rzig's check mode by CC's name,
  `R_HOME/bin/toolchain/zig-cc` (gcc.exe on Windows): `--rzig-check`,
  or `--rzig-check=fortran` when `src/`'s top level has `.f`, `.f90`
  or `.f95` files (either case of the f), then
  `--rzig-check=build-tools`. A failing check prints what is missing and
  the group's text on stderr, as it comes, and the install stops with
  "ERROR: this package has compiled code, and the r-zig toolchain is
  incomplete (see above)" (since feat-zig-pkg-build's review follow-up,
  2026-10-13: "this package needs the r-zig toolchain (compiled code or
  a configure script), which is incomplete (see above)", one
  `--rzig-check=package` call [tests-T11]). The
  Makeconf-CC fallback is gone. Without rzig (r-zig-slim or the r_zig
  wheel without their toolchain package, until phase 4) the old branch
  and message stay, with R_ZIG_TOOLCHAIN_HINT (C8).
- Patch 0010 (src/scripts/config, also Windows' bin/config.sh): with
  rzig, `"${rzig}" --rzig-check=build-tools > /dev/null || exit`, so R
  CMD config ends with rzig's status after its text; without rzig, the
  old `command -v make` test and message.
- build.zig: installRzig's Windows names lose the extensionless zig-cc
  and zig-cxx (B26 a): gcc.exe, g++.exe, zig-fc.exe, zig-ar.exe,
  zig-ranlib.exe, gcc-ar.exe, gcc-ranlib.exe, ar.exe and ranlib.exe.
  verify-helpers.sh's `rzig_names` follows. The `-Dtoolchain-hint`
  comment says the hint shows only where rzig is missing.
- rzig: doc comments only (check.zig, groups.zig): the patches call the
  check mode, and Fortran is looked for at `src/`'s top level.
- hermetic-check.sh: nothing is deleted from the copied tree; its TC
  holds rzig, as the base ships. A package with C code must stop with a
  non-zero exit and a line starting "Compiling needs the r-zig compilers
  for R ", and not install. On unix `R CMD config CC` must exit non-zero
  with a line starting "Building packages needs the r-zig build tools
  for R ". linux's strace allowlist adds `$T/lib/R/bin/toolchain/zig-cc`.
- verify-bundle.sh asserts rzig's texts as check.zig and groups.zig
  print them: "zig-cc: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the
  environment's bin, PATH, python3 -m ziglang)", "zig-cc: no flang
  (R_HOME/bin/toolchain/flang/bin, the environment's bin, PATH)",
  "zig-cc: no make on PATH", and each group's first line up to "for R
  <ver> on <plat>: " (`starts_line`: a line starts with the text, CRs
  dropped).
  - Scenario 1: the check mode exits 127 with those lines.
  - Scenario 2 (unix; ZIG_BIN=$ZIG, PATH the extracted tree's bin): a C
    package stops with no make and the build tools' text, a `src/a.f`
    package with no flang and the compilers' text; neither installs, and
    both print the preflight's ERROR line (C26).
  - Scenario 3 (every OS, no ZIG_BIN): a package with C code and a
    configure script stops with the compilers' text, its configure not
    run; with R_ZIG_NO_PREFLIGHT=1 its configure runs (verify-helpers.sh's
    `configure_marker`: configure and configure.win write
    `configure-ran` with the shell builtin `:`) and the compile fails
    with the no-zig line (C26). Skipped with a note where the host has a
    zig of its own.
- compile-tree.sh, the user's answer (4) below: it stops, naming the
  file and "run 'pixi run toolchain' (or 'pixi run unpack-toolchain')",
  when the R tree has the libomp runtime (`lib/libomp.so`,
  `lib/libomp.dylib` or `<RH>/bin/x64/libomp.dll`) and the toolchain
  tree has no `openmp/`. A slim contract can no longer take omp.h from
  R_ZIG_EXTRA_ENV.
- recipe: test-toolchain.R's line 3 checks the platform's rzig name
  (gcc.exe on Windows, else zig-cc), with `windows` and `tc` defined once
  at the top; test-preflight.R's line 4 checks that the same name is
  absent (C29).
- stress/stress.R: the toolchain class also matches "r-zig toolchain is
  (incomplete|not installed)", and for the "incomplete (see above)" stop
  the reported line is the last `zig-cc: ` line above it, which names
  what is missing. stress/README.md's class table says so.
- pixi.toml: the `hermetic` and `verify-package` comments mention the
  preflight.

The user's answers to step 3's review (2026-10-11): (1) a zig that
cannot start keeps exit 1 in the check mode; (2) one compilers text for
every flavor; (3) Rcmd_environ's line order is left to verify-bundle's
PATH run check (C27); (4) compile-tree.sh requires the toolchain tree's
openmp/ where the base has the libomp runtime; (5) rzig stays ar.exe and
ranlib.exe beside gcc.exe on Windows, for CMake. Only (4) changed code.

Choices and deviations, with their reasons:
- 0009 runs `system2(rzig, chk, stdout = FALSE)` and tests its status,
  not PHASE3 section 7's `system2(..., stdout = TRUE, stderr = TRUE)`
  followed by message(): on unix R's system(intern = TRUE) turns exit
  127 into the R error "error in running command" (src/unix/sys-unix.c,
  cmdError), so that message branch never ran (reproduced: R CMD INSTALL
  died with that error). rzig's text now goes straight to R CMD
  INSTALL's stderr, and its ok line is discarded.
- The preflight counts only the configure script R runs. PHASE3's
  condition also counted a plain `configure` on Windows, where R only
  warns about it, so an R-only package shipping a unix configure alone
  would have stopped on the Windows base (the review below).
- Fortran is looked for at `src/`'s top level only, as R's default
  OBJECTS rule compiles (install.R's `srcs <- dir(pattern = ...)`). A
  Makevars that builds Fortran from a subdirectory passes the preflight
  and stops later, at zig-fc, with the same no-flang line and text. Not
  recursive, so that a vendored Fortran file that is never built does
  not ask for flang, which the pip channel lacks. 0009's header and
  comment and check.zig say so (the review).
- R CMD config's exit status is rzig's, 127, as PHASE3 section 7 has it
  (step 4's open question; (a), as recommended, kept with the user's
  "follow recommendations"): R's callers that use system(intern = TRUE)
  end with R's "error in running command", after rzig's text on stderr.
- No configure marker in hermetic-check.sh's hermeticSrc or in scenario
  2's packages, against PHASE3's hermetic bullet: without the build
  tools the install's R CMD config (0010) fails before a configure would
  run, wherever the preflight sits, so the marker proved nothing (the
  review). Scenario 3 is the one place where R CMD config passes, so the
  order is told there, and C26's R_ZIG_NO_PREFLIGHT test moved there from
  scenario 1: install.R runs R CMD config (CC and the rest) before
  configure, and with the base alone that stops first.
- `configure_marker` is one helper, writing both configure and
  configure.win on every OS, not a unix configure plus a Windows
  configure.win.
- hermetic-check.sh captures R CMD config through a file
  (`system2(stdout = log, stderr = log)`): its 127 through `stdout =
  TRUE` would be an R error.
- verify-bundle compares the exact `zig-cc: ...` lines and each group's
  first line up to "on <plat>: ", not its zig version part;
  hermetic-check uses PHASE3's shorter prefixes.
- The hint (C8): until phase 4 it shows only in the rzig-missing branch,
  as today, which answers TODO's "decide where the preflight shows a
  user's R_ZIG_TOOLCHAIN_HINT". Since hermetic keeps TC, no linux test
  reaches 0010's rzig-missing branch any more (step 3's hermetic
  deleted TC to reach it); test-preflight.R still runs 0009's in the
  conda build, and 0010's lines pass when run alone. The branch is not
  published (B14: no bump in phase 3) and phase 4 removes it.

Tests: step 6's record.

#### Phase 3 record: step 5, CI (2026-10-11)

What changed (B31 a, B12, B42; C3, C4, C33, C34, C35, C36):
- .github/workflows/toolchain.yaml (new, workflow_call; inputs `os`, and
  `zig`: conda, the default, or upstream): checkout; setup-pixi v0.11.0
  with pixi v0.81.0, the default env and `cache: false` (C33: the
  toolchain build reads info/licenses and info/recipe from pixi's
  package cache, which is empty when the env comes from setup-pixi's
  cache); for upstream, ZIG_BIN from fetch-zig (C35); `toolchain-test`,
  `package-toolchain`, then `verify-toolchain`, so the tree checked is
  the one archived (C34); the group archives and their `.sha256`
  uploaded as `toolchain-<runner.os>-<runner.arch>`, `-upstream` added
  for upstream zig, kept 30 days, `if-no-files-found: error`. The job is
  named "toolchain" or "toolchain (upstream zig)", with a 30-minute
  timeout.
- build.yaml: a `toolchain` job, one leg per platform (conda-package's
  five runners, `linux_runner` included), with the build job's
  condition. `build` and `build-full` need it, with `!cancelled() &&`
  after the ENABLE_HOSTED_JOBS test, where conda-package has it: a
  failed toolchain leg fails only its own platform's legs, at their
  download (C4). conda-package is unchanged.
- build-r.yaml: right after setup-pixi every leg downloads
  `toolchain-<os>-<arch>[-upstream]` into dist/ (download-artifact@v8)
  and runs `unpack-toolchain`: contract (every leg, full and openblas
  too) compiles in the compile tree, verify-package extracts the
  archives, the wheel takes make from the tree. The packaging legs
  (default, minimal) run verify-package's three scenarios on the
  downloaded group archives, then upload the base archive and its
  `.sha256` as `standalone-<env>-<os>[-upstream]` (dist/R-* without the
  group archives), kept 7 days (B12).
- upstream-zig.yaml: its own `toolchain` job (toolchain.yaml with `zig:
  upstream` on its three runners, build's condition); `build` needs it,
  with `!cancelled()`.
- stress.yaml (C3): a `toolchain` job per runner of `inputs.oses`, with
  `inputs.zig`; the stress job needs it (with `!cancelled()`), downloads
  its artifact into dist/ and runs `unpack-toolchain` before `stress`.
  The `oses` description asks for one runner per OS and arch, which name
  the artifact.
- README.md: a "Standalone archives" section: the base per flavor (R
  alone, only rzig in R_HOME/bin/toolchain; Windows slim has full's
  content, B42), the compilers group (OpenMP's files for now; zig from
  ZIG_BIN or PATH, which PyPI's ziglang covers, flang from PATH), the
  build-tools group (unix make; Windows binutils, sh and make still from
  PATH), one top directory `R-<ver>-zig/` with SOURCES and LICENSES/ in
  each group directory, extracting into one directory with one flavor
  per directory, `pixi run package` and `package-toolchain`, CI's
  retention and no release yet. The conda install section gains the
  Windows slim line and "the MinGW binutils"; "Run R from source" runs
  `pixi run toolchain` before contract and describes the dev, toolchain
  and compile trees; the upstream-zig task list gains `toolchain` and
  `toolchain-test` (C36); the wheel section runs `pixi run -e minimal
  package-toolchain` first; the CI section names the toolchain job, both
  artifacts (base 7 days, groups 30) and the per-platform failure.

Choices and deviations, with their reasons:
- download-artifact@v8: it came out with upload-artifact v7.0.0
  (2026-02-26), so it is the major that pairs with @v7; it fails on a
  digest mismatch by default.
- The group archives are kept 30 days, not PHASE3's 7: every leg of a
  run downloads them, and GitHub lets failed jobs be re-run for 30 days
  without re-running a toolchain job that passed, so after 7 days such a
  re-run would fail at its download (the review). Still CI's, not a
  release (B12). The base archives stay at 7 days.
- No `overwrite: true` on the uploads (step 5's open question; as
  recommended, and as the wheel and stress uploads): a re-run of a leg
  that already uploaded may get 409 Conflict; add it if a live run shows
  that. For the same reason two stress runners of one OS and arch would
  collide on the artifact's name, hence the `oses` description (the
  review).
- `!cancelled()` sits after the ENABLE_HOSTED_JOBS test rather than in
  front of the condition (the same logic), and stress.yaml's stress job
  has it too, as C4 does for build.yaml.
- The toolchain job's 30-minute timeout is a guess: PHASE3 names none,
  and an uncached Windows env install is unmeasured.
- The README's wheel section runs `package-toolchain`, not PHASE3's bare
  `toolchain`: verify-package before the wheel needs the group archives.
  The bare command is in the prose.
- Job counts (chore-ci-tiers' table): every build.yaml run with build
  legs also runs the toolchain job's 5 legs, and every leg waits for all
  five (a matrix need). A pull request without `full-ci` is 6 legs, 5
  toolchain jobs and packaging (plus 5 conda-package jobs when packaging
  says yes), a push to main 16 jobs, a full run 25.
  chore-ci-tiers/PLAN.md has a dated note.

Checked here: actionlint 1.7.12 on the six workflows; every task the
workflows and README name exists in pixi.toml under the env they use.
Not run: no push or dispatch was allowed, so toolchain.yaml, the
artifact round trip, the timeout, verify-toolchain on GitHub's macOS and
Windows runners and C4 (which rests on GitHub's documented `needs` and
status-function rules) wait for the PR's first run.

#### Phase 3 record: step 6, tests on every OS and B24 (2026-10-11)

Code changed by this step's tests (kappa's findings, fixed on linux-64,
then run again on kappa):
- rzig, LTO on Windows (B43-2's record). With `MAKEFLAGS='LTO_OPT=-flto'`
  every install failed on kappa: ltodef, ltonodef, and ltoplain, which
  has no static library and no `.def`. The cause is zig 0.16.0's own,
  with both zigs: an x86_64-windows-gnu link with -flto (or -flto=thin)
  on its line builds zig's MinGW runtime for LTO, and lld-link stops at
  symbols that runtime then lacks (wmemchr, mempcpy, frexpf, modfl, ...).
  `zig cc -target x86_64-windows-gnu -flto` reproduces it from linux.
  Bitcode objects linked without -flto link, and lld still optimizes
  them together (in the linked DLL, g() is inlined into h()). So
  windows.zig's `noLtoLink` drops -flto and -flto=<x> from Windows image
  links (compiler.zig's argv, after exeSuffix; zig-fc's shared links go
  through it); compiles keep -flto. The tester left this to the user:
  (a) record only, or (b) drop -flto at links. (b) is applied, as
  recommended; going back to (a) removes the noLtoLink call, the
  function and its tests.
- rzig, import libraries on Windows. Every package link left
  `src/guard_dispatch.lib`: zig writes an import library beside the
  output of every DLL link (and of a program that exports symbols),
  named after the link's first input, which is rzig's CFG stub since
  stress round 2's Z11. After an in-place install R CMD build packs it
  and R CMD check warns "These are unlikely file names for src files".
  zig cc has no flag against it (both zigs reject -fno-emit-implib,
  -Wl,/noimplib, -Wl,-noimplib and --no-out-implib). `windows.implib`
  names `<output>.rzig.lib` through `-Xlinker --out-implib=<path>` (a
  comma in the path cannot split it) for image links that name no import
  library themselves (no `-implib` in any argument) and records it in
  Ctx's new `discard` list; main.zig's Windows run() deletes the list
  once zig exits. A caller's own, such as CMake's
  `-Wl,--out-implib,lib<name>.dll.a`, is kept. Not the tester's
  cache-directory trial, which left a file per link, created
  directories and would break on a comma in %LOCALAPPDATA%. Unit tests:
  7 updated, 2 new (98); parity-test.sh drops the new flag where the CFG
  stub's rule puts it. verify-bundle's Windows OpenMP block fails when a
  `*.lib` is left beside a DLL.
- pixi.toml's conda-package task runs `rm -rf dist/conda && rattler-build
  build ...`, where it removed only `dist/conda/build_cache`.
  rattler-build 0.76.1 indexes the output directory as the build starts
  and lists a package only under a file name the index lacks, so a local
  rebuild with the same build string kept the old sha256 in
  repodata.json, and r-zig-toolchain's test, and any env made from
  dist/conda, installed the previous r-zig-slim from the rattler cache
  (kappa's round 2; the old command reproduces it on linux-64). The
  whole directory rather than the tester's three globs: no reliance on
  how the task shell treats a glob that matches nothing, every leftover
  gone, as CI's empty start. The cost: R's sources are downloaded on
  every build. README's conda section says each run empties dist/conda.

Ran (every task with `--locked`; pixi.lock sha256 fbb64b7b...a68bb96 at
the start and the end on every host, the osx-64 copy's own re-solved
lock aside; no git writes):
- linux-64, three times: on steps 4 and 5's diff, after the review's
  fixes, and after kappa's.
  - Static: bash -n, zig fmt --check, shellcheck -S warning (no finding
    on the changed scripts), actionlint 1.7.12 (six workflows).
  - `rzig-test`: 96/96, then 98/98 unit tests; parity 81 identical / 59
    / 34 deliberate / 0 failed; with conda-forge zig 0.16.0 and with
    upstream zig 0.16.0 (ZIG_BIN from fetch-zig). `toolchain-test` with
    both.
  - slim, both zigs: build (R re-extracted for the new patches; dist/'s
    trees removed first, C25), toolchain, verify-tree, verify-toolchain,
    smoke, contract, check, hermetic, package-toolchain, verify-package.
    hermetic prints "preflight: compiled package stopped: Compiling needs
    the r-zig compilers for R 4.6.1 on linux-64: ..."; R CMD config exits
    127 with the build tools' text; strace saw only /bin/sh, R's
    launchers and TC/zig-cc. verify-package: the base 1,937 files and
    links, the groups 6 and 3, the three scenarios with their preflight
    checks, GNU Make 4.4.1 the only make that ran in scenario 3.
  - minimal: build, verify-tree, contract, verify-package (1,401
    files). wheel and wheel-test: with r-zig alone the rzig-missing
    branch names `pip install r-zig-toolchain`; with r-zig-toolchain the
    check mode passes with ZIG_BIN from ziglang, unset, and
    `/nonexistent` (python3 -m ziglang).
  - conda-package: r-zig-slim-4.6.1-hb0f4dca_8 and
    r-zig-toolchain-4.6.1-hc48ad4c_8, both tests (test-preflight.R takes
    the rzig-missing branch with the conda hint; test-toolchain.R
    compiles through the check mode). The new task from no dist/ and as
    a rebuild over a stale index (the old command left it stale: slim
    7330fbd1 listed, f866bb23 on disk); a fresh pixi project on
    dist/conda locks the rebuilt sha256s.
  - File lists: each base archive equals its R tree; the group
    archives' union equals the toolchain tree (9 files). `pixi run -e
    minimal package-toolchain` gives a tree identical to the default
    env's.
  - compile-tree.sh with a toolchain tree without openmp/: slim stops
    and leaves the old compile tree alone; minimal passes.
  - stress.R's classifier, on synthetic logs and real preflight logs:
    "toolchain", with the `zig-cc:` line that names what is missing; a
    missing header stays "sysdep".
  - After kappa's rzig fixes: rzig-test with both zigs; slim with
    conda-forge zig from build to verify-package; slim with upstream zig
    build, verify-tree, smoke, contract, hermetic, verify-package;
    minimal build, verify-tree, contract, verify-package. The installed
    rzig's dry-run argv (RZIG_OS=windows, LTO), run with a real zig and
    `-target x86_64-windows-gnu`, links an LTO DLL that uses frexp, with
    both zigs.
- omicron (macOS 26.4.1, pixi 0.81.0), once, on the diff after the
  review's fixes (`git diff` sha256 88eb3ccd...ad49dc), before kappa's:
  - osx-arm64, conda-forge zig: rzig-test (96/96), toolchain-test,
    build, toolchain, verify-tree, verify-toolchain, smoke, contract,
    hermetic, package-toolchain, verify-package (the base 1,931 files
    and links, the groups 6 and 3); minimal build, verify-tree, contract,
    verify-package (1,399); wheel (r_zig-4.6.1-py3-none-macosx_13_0_arm64,
    1,400 files; r_zig_toolchain 11 files) and wheel-test. With upstream
    zig: rzig-test, toolchain-test, build, toolchain, verify-tree,
    verify-toolchain, contract, hermetic, package-toolchain,
    verify-package.
  - osx-64 under Rosetta (a copy re-solved for osx-64, its package sets
    equal to the lock's): rzig-test, toolchain-test, build, toolchain,
    verify-tree, verify-toolchain, smoke, contract, package-toolchain,
    verify-package (baseline target-cpu core2).
  - Scenario 3 runs GNU Make 4.4.1 at the extracted TC/usr/bin/make,
    never Apple's 3.81 (C24). make has minos 11.0 / sdk 11.0 on both
    arches, loads only /usr/lib/libSystem.B.dylib, has LC_RPATH
    `@loader_path/../lib/`; ad-hoc signed on arm64 (the copy keeps it),
    unsigned on x86_64 (verify-toolchain's log prints only "minos <=
    13.0"). The preflight's texts as on linux. compile-tree.sh's openmp/
    rule: slim stops naming lib/libomp.dylib, minimal passes.
  - No Falcon event and no retry. Not run there: conda-package and C22
    (not on its list); upstream zig on osx-64 (an unsigned x86_64 zig
    under Rosetta, which Falcon may kill; no CI leg runs it either, as
    upstream-zig.yaml has macos-latest only). Not run again after
    kappa's fixes, whose rzig code acts on Windows links only and whose
    task change is conda-package's.
- kappa (win-64, Windows 11, pixi 0.81.0, rattler-build 0.76.1),
  conda-forge zig unless named, three rounds: 1 on 88eb3ccd...ad49dc, 2
  with kappa's rzig fixes (4d24652b...), 3 with the conda-package task
  (1d23cdcb..., this diff before these records):
  - Every round: rzig-test (71/96, then 73/98; 25 skipped on Windows),
    toolchain-test, build, toolchain, verify-tree, verify-toolchain,
    smoke, contract (compile tree with openmp/ and binutils/), hermetic,
    package-toolchain, verify-package; rzig-test and toolchain-test with
    upstream zig; conda-package (r-zig-slim-4.6.1-h9490d1a_8,
    r-zig-toolchain-4.6.1-hbceaa80_8, both tests). All pass.
  - verify-tree: TC holds exactly the nine rzig names; libomp.dll in
    bin/x64, no omp.h or libomp.lib in the base; no VEX/EVEX instruction
    in R's binaries; the DLL closure, 78 PE files. verify-toolchain: 22
    files, 11 copies matching SOURCES, 4 packages each with LICENSES/, 8
    PE files whose imports sit beside them or are the system's. The six
    binutils import KERNEL32, API sets and zstd.dll, which imports
    VCRUNTIME140.dll (C23).
  - verify-package: the base zip 61 MB, 2,943 files; the groups 5 and 17
    files, disjoint. Scenario 1: PATH's entry after bin\x64 is
    TC/usr/bin (or R_CUSTOM_TOOLS_PATH, C27); both check modes exit 127
    with their texts; hermetic's preflight. Scenario 2: the check modes
    find zig and flang; baseline target-cpu x86-64; an OpenMP DLL linked
    by gcc.exe alone. Scenario 3: every tool Makeconf names is a file
    (the LTO gcc-nm aside); R CMD config AR, NM and OBJDUMP;
    read_symbols_from_dll reads R.dll through binutils/objdump (626
    symbols); nm.exe runs with PATH = System32 (GNU nm 2.46.1); tools.mk
    runs $(NM), $(DLLTOOL) --as, $(AR), $(RANLIB), $(STRIP_STATIC_LIB),
    $(RESCOMP) and $(OBJDUMP); rzig's ar.exe and ranlib.exe make a static
    library with PATH = System32; the OpenMP probe, omp, lomp, fomp and
    fompfc; btA, btLib and btRc (`.rsrc` present); the preflight and
    R_ZIG_NO_PREFLIGHT pair; from round 2, no import library beside a
    DLL.
  - The LTO record (B43-2, C9; recorded, not checked). Round 1:
    "ltodef (ltodef-win.def, a static library): install exit 1, gcc-ar
    and gcc-ranlib ran" and "ltonodef (no .def, a static library):
    install exit 1, gcc-ar and gcc-ranlib ran, the missing gcc-nm named
    in its log". Rounds 2 and 3, with noLtoLink: "install exit 0, gcc-ar
    and gcc-ranlib ran; loads, f() = 42" for both. With both zigs,
    ltodef, ltonodef and ltoplain install and load with and without the
    flag, the compiles keep -flto, and gcc.exe links with -flto and
    -flto=thin.
  - C22: every conda-meta record in rattler-build's build_env (73),
    h_env (75) and both test envs (65 and 98) has
    extracted_package_dir and paths_data, on every conda run (one in
    round 1, four in round 2, two in round 3). The longest path under
    TC/binutils/LICENSES is 156 characters in the test env, 141 in h_env
    and 79 within the package: far under 260. The host solve took
    llvm-openmp 23.1.3; the lock's dev env has 23.1.2.
  - A fresh pixi project on dist/conda, conda-forge and universe, with
    the local build-8 packages: a C package and a static-library package
    (zig-ar.exe cr, zig-ranlib.exe) install and load. R CMD config AR is
    toolchain/zig-ar.exe, NM binutils/nm.exe, OBJDUMP binutils/objdump,
    all there; under R CMD, PATH has no ar, ranlib, windres, objdump, nm
    or gcc. RcppParallel 6.2.1 from CRAN: CMake 4.4.4 takes CMAKE_AR and
    CMAKE_RANLIB from rzig's toolchain/ar.exe and ranlib.exe and
    CMAKE_RC_COMPILER binutils/windres.exe (preprocessor gcc.exe); TBB's
    three DLLs carry `.rsrc`; it installs and loads (S15's case after the
    move). R CMD check --no-manual of a package with a DLL: Status OK,
    "checking compiled code ... OK", no objdump warning. The devtools
    flow (R CMD INSTALL in place, R CMD build, R CMD check): Status OK
    from round 2; on round 1's rzig the same script left
    guard_dispatch.lib and got "Status: 1 WARNING".
  - Round 3, the conda-package task: run over round 2's leftover
    dist/conda (18,473 items, paths up to 267 characters) and over a
    build killed in the middle of R's build (65,401 items). Each time
    the rm took seconds, repodata.json matched the new files, and the
    tests and a fresh env used them. The killed build left an orphaned
    flang.exe; an rm over a file such a process holds was not tried.
  - Seen, not acted on: zig writes `<output>.pdb` beside each Windows
    image linked without -s (R's links pass -s, so none lands in a
    package's src/); rattler-build's Windows test env prints "Setting
    LC_* failed" lines, and zstd.dll gives overlinking warnings for the
    binutils, as before.
- B24's routing check (kappa, both zigs 0.16.0: conda-forge's
  `Library\bin\x86_64-w64-mingw32-zig.exe` and upstream's from
  fetch-zig; the reference was the env's MinGW binutils 2.46.1, the
  copies in TC/binutils/; R-side links used the slim tree's gcc.exe).
  A record, not a gate: nothing moved in phase 3. Every result holds for
  both zigs.
  - dlltool passes; it can move to rzig in a follow-up PR. `zig
    dlltool` (llvm-dlltool) takes GNU's long options, though its help
    lists only short ones: `-m i386:x86-64 -k --dllname foo.dll
    --input-def foo.def --output-lib libfoo.dll.a` makes a 1,432 B
    short-import library (GNU's: 2,980 B); `--as <as.exe>` and `-S
    as.exe` are accepted and ignored; Makeconf.win's exact command (`--as
    as.exe -k --dllname ... --input-def ... --output-lib ...`, no `-m`)
    works, taking x86-64 from the host. Programs linked against each
    library by zig cc and by `gcc.exe -L. -lfoo` printed the right
    values, as with GNU's (a function through the thunk, a DATA export
    through `__imp_`). Not supported: the `--opt=value` forms
    (`--input-def=foo.def` fails with "cannot open file =foo.def";
    `--dllname=foo.dll` exits 0 and names the DLL `=foo.dll`) and
    `--output-exp` (usage, exit 1); `-A` is ignored with a warning. The
    route: an rzig name `dlltool.exe` that runs `zig dlltool -m
    i386:x86-64` with the caller's arguments, splitting `--dllname=`,
    `--input-def=`, `--output-lib=`, `--as=` and `--machine=` into two
    words (about 40 lines in main.zig beside ranlib's entry, plus unit
    tests). Makeconf.win's DLLTOOL becomes `$(BINPREF)dlltool.exe
    $(DT_ARCH)` without its `--as`. That `--as` is as.exe's only user
    (Makeconf.win names no AS), so as.exe leaves `binutils/` with
    dlltool.exe: 3,741,696 B of GPL-3 binaries (1,530,880 + 2,210,816).
    check.zig's binutils list, the toolchain build's copies and
    verify-tree follow.
  - windres: zig rc works; a windres-syntax front in rzig is viable but
    larger, and goes in its own follow-up PR after dlltool's. On a `.rc`
    with windows.h, a VERSIONINFO and a STRINGTABLE, `zig rc
    /:auto-includes gnu /fo r.res r.rc` makes a `.res` zig's linker takes
    directly (the program reads its string and version); `/fo r.res.o`
    makes a COFF object (sections `.rsrc$01` and `.rsrc$02`; GNU's has
    one `.rsrc`) that zig cc and gcc.exe link the same way; zig cc also
    takes the `.rc` itself. RcppParallel's tbb.rc built with zig rc and
    with GNU windres in R's RESCOMP form, and both objects linked into a
    DLL. zig rc rejects windres' syntax: `-i r.rc -o x.res.o` ("invalid
    option: -o"; its `-i` is an include directory), `--preprocessor=`,
    `--preprocessor-arg=` and `-O coff`. conda-forge's zig ships
    `x86_64-w64-mingw32-zig-windres.exe`, a 121-line C wrapper from its
    feedstock that maps `-o` to `/fo` and `-i` to the input and nothing
    else: it fails on R's RESCOMP (`--preprocessor`) and CMake's `-O
    coff`, and upstream's zig has none, so it is not a route. A front in
    rzig maps `-i`/`--input`, `-o`/`--output` or the positional pair to
    the input and `/fo`; `-O`, `-J` and `-F` (and their long forms) to
    `/:output-format`, `/:input-format` and `/:target`; `-I -D -U -c -l`
    to `/i /d /u /c /l`; drops `--preprocessor` and `--preprocessor-arg`
    (resinator preprocesses itself and defines RC_INVOKED and _WIN32);
    ignores `-v`, `--use-temp-file` and `-r`; always passes
    `/:auto-includes gnu` (the default, `any`, prefers MSVC's headers
    where Visual Studio is installed). About 150-200 lines of Zig and
    80-100 of unit tests. Makeconf.win's RESCOMP becomes
    `$(BINPREF)windres.exe $(RC_ARCH)`, Rcmd_environ's RC names it and
    R_ZIG_RCFLAGS goes. Caveats: resinator follows rc.exe's syntax, not
    GNU windres', and only these two files were tried; the first zig rc
    in a zig cache builds resinator (under a minute on kappa, 3.6 MB).
    windres.exe (1,613,824 B) stays until that PR.
  - strip is not routable. `zig objcopy` with `--strip-all`,
    `--strip-debug` or `-S` on a PE DLL or EXE fails ("invalid elf file:
    InvalidElfMagic"): zig's objcopy reads ELF only. zig's PE images
    carry no debug sections and no symbol table (debug info goes to the
    .pdb): GNU `strip --strip-unneeded` left a `-g` DLL as it was
    (777,216 B), and `zig cc -s` (526,336 B) builds zig's runtime pieces
    differently rather than stripping the image. R on Windows never runs
    STRIP_* itself (`R CMD INSTALL --strip` reads R_STRIP_SHARED_LIB,
    unset there), so strip.exe stays for packages' own makefiles.
  - nm and as: zig 0.16.0 has neither (`zig nm`, `zig as`, `zig strip`
    and `zig windres` say "unknown command"). nm stays: winshlib.mk runs
    `$(NM)` on every DLL link without a `.def`, `zig objdump` cannot
    stand in ("unrecognized file: foo.dll", no `-p`), and an nm in rzig
    reading COFF symbol tables would be new code, not routing (G2). as
    goes with dlltool.
  - After both follow-up PRs, `binutils/` holds nm, strip and objdump
    (and windres until its front lands). TODO's B24 box stays open until
    the dlltool/as PR.
  - Aside: `zig rc /h` (help only) rewinds a redirected stdout to offset
    0 and overwrites what the log held, with both zigs; compiles and
    errors append normally. It does not touch R.
  - Logs and probe scripts:
    /data/gamma/luciorq/workspaces/temp/r-zig-pixi/phase3-step4/b24/.

The review of steps 4 and 5 (2026-10-11; correctness, Windows, CI and
the plan, a verifier confirming each finding; 8 confirmed, 3 refuted):
- Fixed (in steps 4 and 5's records): the Windows preflight counted a
  plain configure (major); the top-level-only Fortran search was not
  documented; the group archives' 7 days against 30 days of re-runs;
  two stress runners of one OS and arch would collide on the artifact's
  name; stress.R classed the preflight's stop as "package" and hid what
  was missing; the configure marker in hermetic and scenario 2 passed
  whatever the preflight did; PLAN.md's Verification recipe ran
  verify-package without making the group archives (it now runs
  PHASE3 section 4's chain).
- Fixed here: the phase's CI step and TODO.md's CI box described
  another upload and download layout (both rewritten).
- Refuted: "0010's rzig-missing branch is untested" (true, but the
  branch is never published, B14, and phase 4 removes it; its lines
  pass when run alone); "test-preflight.R cannot catch a missing conda
  hint" (unchanged lines, the hint is delivered today, B35 removes the
  mechanism); "the base layout still names Windows' zig-cc and zig-cxx"
  (it says they "go with B26 (a)", which step 4 did).

Closes the risk "the binutils need the base's zstd.dll on PATH":
`binutils/` carries zstd.dll and vcruntime140.dll beside the tools (step
2), and nm.exe runs with PATH = System32 on kappa.

Not tested anywhere yet, CI's after the PR's first run: toolchain.yaml
and the artifact round trip, the 30-minute timeout, C4's
`!cancelled()`, stress.yaml's toolchain jobs; on windows-latest the
static-library and LTO packages and verify-package; conda-package on
macOS (omicron's list did not have it); upstream zig on osx-64 (no host
or leg). Before merging: C13's check that universe holds build 8 for all
five subdirs (`pixi run -e pkg conda-channel-list`).

#### Phase 3 record: CI on PR #24 (2026-10-12)

The user committed steps 4 to 6 as 548da1a and opened PR #24 with the
`full-ci` and `upstream-zig` labels. Every run on 548da1a passed:
- build.yaml, run 38247190923, the full tier: 25 jobs. The five
  toolchain legs (toolchain.yaml, one per platform) took 0 to 2 minutes
  each, so the CI wall-time risk (PHASE3 risk 3) does not arise and the
  30-minute timeout is ample. The 15 build legs (default, minimal, full,
  openblas where the tier has them) downloaded their platform's
  archives and ran unpack-toolchain; the packaging legs ran
  verify-package's three scenarios. conda-package passed on all five
  subdirs, macOS included.
- windows-latest's verify-package: scenario 3's Makeconf tools are
  files, $(NM), $(DLLTOOL) --as, $(AR), $(RANLIB), $(STRIP_STATIC_LIB),
  $(RESCOMP) and $(OBJDUMP) run as R's makefiles run them, the OpenMP
  packages build with openmp/ and load, and the LTO record matches
  kappa's: ltodef and ltonodef install (exit 0) and load, f() = 42, with
  gcc-nm's absence named in ltonodef's log (B43-2).
- upstream-zig.yaml, run 38247190926: its three toolchain legs and three
  default legs, built with upstream zig.
- stress.yaml, dispatch 38251125721 (ubuntu-latest, tree, the default
  targets g3 and g4): its toolchain job and the stress leg, which
  unpacked the archives and ran in the compile tree. Targets: 22 ok, 1
  install-failed, 0 unexpected; dependencies 37 ok. The failure is
  magick, as its row expects (linux=fail-abi): the C++ ABI boundary
  (stress round 1's A1, under "Later and future checks"): it needs
  `Magick::magickImage(std::__1::basic_string const&)`, and conda-forge's
  libMagick++ exports only the libstdc++ (`std::__cxx11`) one. The job
  exits 0 unless --strict, so a row's failure shows only in its table.
C13 holds: universe has r-zig-slim and r-zig-toolchain build 8 on all
five subdirs (repodata, 2026-10-11), so phase 3's files publish nothing
until phase 4's bump (since 2026-10-19: the bump with phase 7's merge,
B14's amendment). Not run anywhere: upstream zig on osx-64.

#### Phase 3 review: steps 1 and 2 (2026-10-10)

An adversarial review of the uncommitted diff against steps 1 and 2 and
B1, B17, B20, B23, B24, B30, B36, B43 and open point A. No blocking
problem. Checked:
- No script, task, workflow, recipe file, make-wheel.py or stress file
  still names `dist/R-<ver>-<flavor>-zig` (only historical records do).
- The packages in pixi.lock ship what the tables copy, with no prefix
  placeholder: win-64 binutils_impl_win-64 2.46.1 (the six
  `x86_64-w64-mingw32-*.exe`, each importing KERNEL32, API sets and
  zstd.dll), zstd 1.5.7 (`Library/bin/zstd.dll`), vc14_runtime
  (`Library/bin/vcruntime140.dll`), llvm-openmp (`Library/include/omp.h`,
  `ompx.h`, `Library/lib/libomp.lib`); osx-arm64 and osx-64 make 4.4.1
  (`bin/make`: minos 11.0, only /usr/lib/libSystem.B.dylib,
  `@loader_path/../lib/` rpath; osx-arm64's is ad-hoc signed by its
  linker, and an unchanged copy keeps that signature valid, so nothing
  re-signs). Each has `info/licenses`. macOS make holds conda-forge's
  build path under /Users/runner: verify-toolchain.sh lists it on
  GitHub's runners (C18).
- No linux-64 env here records two owners for a copied file, and pixi
  0.81.0's records have `extracted_package_dir` and `paths_data`.
- `git merge-file` against PR #23's commit (cb386b8) gives no conflict
  in verify-tree.sh, vendor-libs.sh, build.zig or recipe.yaml.
- toolchain-test, package-toolchain, verify-toolchain, unpack-toolchain
  and verify-toolchain pass again here; pixi.lock is unchanged.

Code suggestions, not applied (the review changes comments and docs
only): the helper's `path_forms` takes #23's 8.3 line (above);
zigbuild/tools/gen-subst.sh no longer reuses env.sh's name `PLAT` for its
own `linux-x86_64`-style config name; package-standalone.sh and
unpack-toolchain.sh turn a Windows-form `R_TOOLCHAIN_PREFIX` into `/c/...`
with cygpath, as verify-toolchain.sh does; zig-toolchain.sh removes the
tree before any install, not only one with no arguments.

### Phase 4 — conda and PyPI on the same boundary

Goal: r-zig-slim and the r-zig wheel carry rzig; the group packages
carry or depend on only third-party software.

Decisions (all answered): B14 (the bump), B28, B29, B35 (the writers
go), B38, B39 and B11 (conda's win-64 dependencies), B41; with the
related items D7, D12 and E2.

Steps:
- First check that rattler-build 0.76.1 makes outputs with no files that
  do not inherit the staging build.
- rattler-build >= 0.76 with its warnings as errors (D12 = a), so that
  overlapping files between outputs fail the build. feat-no-host-paths
  PLAN.md proposes it in follow-up PR (i); if that has not landed, this
  PR does it.
- recipe.yaml (B28): r-zig-slim excludes only the group directories
  (`lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` and
  `Library/...`); r-zig-compilers, r-zig-build-tools and the
  r-zig-toolchain metapackage; the build number per B14 (a: the number
  after the one published when phase 4 merges; build 8 is on universe,
  so 9 unless another PR bumps first; C14). Amended 2026-10-19: phase 4
  keeps 8 and main does not publish it; the bump comes with phase 7's
  merge (B14's amendment).
  - win-64 r-zig-build-tools holds B41's binutils copies (nm, dlltool,
    as, strip, windres, objdump, less any tool rzig took over: none in
    phase 3; B24's follow-up PRs can take dlltool and as, then windres)
    and depends on conda-forge packages for B39's list and pkg-config
    (B11). Until phase 7 has chosen the packages it keeps today's m2
    list (recipe.yaml:410-442) plus pkg-config; phase 7 switches both
    channels to its choice.
  - zstd declared (E2 = a): a run dependency of r-zig-slim (R.dll
    imports zstd.dll) and of win-64 r-zig-build-tools (the binutils
    import it).
  - CC_VER/FC_VER refreshed (D7 = a), with this first bump.
- The hint writers go (B35): `-Dtoolchain-hint`, zig-build.sh's conda
  branch (57-66), make-wheel.py's renviron_hint (244-250).
- make-wheel.py (B29): r-zig takes rzig; r-zig-build-tools takes
  `usr/bin/make` from the toolchain tree; r-zig-compilers and
  r-zig-toolchain are wheels with no files; one tag set; the zig-cc
  check (364-365) moves to the base wheel.
- recipe tests: test-preflight.R expects rzig present, no zig, and the
  preflight naming r-zig-compilers; test-toolchain.R unchanged in what
  it compiles.
- wheel-test.sh: the three scenarios with pip (r-zig alone; with
  r-zig-compilers; with r-zig-build-tools), then uninstall the groups and
  check R is whole.

Tests:
- conda-package on linux-64, omicron (both), kappa and CI, both
  packages' tests and a fresh-env consume test.
- An upgrade in an existing env (pixi, conda, mamba) from the build on
  the channel (`_8` on 2026-10-11; C14) to the new
  build: rzig moves from r-zig-toolchain to r-zig-slim without a clobber
  error.
- wheel-test on linux-64 and CI's four unix minimal legs.

**Status (2026-10-14): steps 1 to 5 done in the worktree
feat-standalone-phase4 (branch feat-standalone-phase4, from main
d11dee1: phase 3, PR #25 and #26's rzig build, PR #27's shared tier-1
build runner), not committed. Tested on linux-64 (both zigs), omicron
(osx-arm64) and kappa (win-64), two rounds on each remote host, and the
upgrade from universe's `_8` with pixi, conda and micromamba (gamma),
pixi and conda (kappa) and pixi (omicron): all pass. CI has not run.**
The work follows the reviewed implementation plan, copied here as
phase4/PHASE4-IMPLEMENTATION.md with its critique phase4/CRITIQUE.md
(cited below as PHASE4 <section>, Cc<n> and Cg<n>), and the user's
answers to its open points ("Phase 4: the user's answers"). The build
number was 9 (universe holds r-zig-slim and r-zig-toolchain `_8` and
nothing newer on all five subdirs: repodata, read again 2026-10-14
17:50 UTC; C14); since the user's decision of 2026-10-19 it stays 8,
and the records below of `_9` packages are local builds from before
it (B14's amendment). pixi.lock is unchanged on every host (sha256
fbb64b7b...a68bb96); phase 4 changes no dependency of a pixi env. Next:
the user commits and opens the PR with the `full-ci` and `upstream-zig`
labels; CI's five conda legs run the four package tests and
conda-consume each (phase 4's first conda-package on osx-64 and
linux-aarch64). Phase 4's merge publishes nothing: build.yaml's publish
step waits for `CONDA_PUBLISH`, which the user sets after phase 7's bump
merges; PHASE4 section 7's post-publish check runs after that publish
(TODO.md).

N5 closes with the bump that publishes phase 4: since 2026-10-19 the
one with phase 7's merge, not a `_9` from phase 4. That build ships
rzig in the base on conda (r-zig-slim) and PyPI (r-zig), in the same
package as patches 0009, 0012 and 0013 and share/zig/rpkg, as the
standalone base archive has since phase 3 (B19), and the exact pins
make its base with an `_8` r-zig-toolchain unsolvable. So no channel
can pair a new R with an older rzig again. It also publishes what
bumped nothing: phase 3, feat-zig-pkg-build (PR #25), its review
follow-up (PR #26), the shared tier-1 build runner (PR #27) and phases
4 to 6. The closing notes "published as `_<N>`, <date>" in
feat-zig-pkg-build's N5 and fix-zig-pkg-build-review's status wait for
that publish (Cc19; TODO.md). Until then main must not publish at all:
a build 8 from main would put the new group packages beside universe's
old r-zig-slim `_8`, which has no rzig (build.yaml's `CONDA_PUBLISH`).

#### Phase 4: the user's answers (2026-10-14)

The user, 2026-10-14: "Start phase 4 now"; PHASE4 section 12's open
points take their recommended options.
- A (a): each group wheel requires `r-zig==<ver>` (r-zig-compilers also
  `ziglang>=0.16.0,<0.16.1`); r-zig-toolchain requires
  `r-zig-compilers==<ver>` and `r-zig-build-tools==<ver>`, as conda's
  exact pins (B28).
- B (b): `R_ZIG_TOOLCHAIN_HINT` is a user's own value only. Patch 0009
  shows it as `hint: <value>` after rzig's text, on exit 127 only; patch
  0010 shows none.
- C (a): patch 0013 drops "the r-zig toolchain is older than this R";
  I-PF4's `R_ZIG_PKG_BUILDER=zig` stop and the make path stay.
- D: settled before phase 4 started. The user had the shared tier-1
  build runner land first (feat-shared-build-runner, PR #27, main
  d11dee1), so phase 4's publish carries it too: (b) in effect (that
  publish was `_9`; since 2026-10-19 it is phase 7's bump). Its open
  decision 1 (b), the Windows key, is folded into phase 4 (step 3 and
  the host rounds).
- E (a): a package or wheel that holds third-party files states their
  licence: conda's win-64 r-zig-build-tools `GPL-3.0-or-later` (the
  MinGW binutils), pip's r-zig-build-tools `GPL-3.0-or-later` with
  make's COPYING as its licence file. The base and the packages and
  wheels with no third-party file say R's `GPL-2.0-only OR
  GPL-3.0-only` on both channels (conda said `GPL-2.0-or-later` on every
  output until `_8`).
- F (a): conda's win-64 r-zig-build-tools depends on `pkg-config` only;
  phase 7 adds the `pkgconf` name on both channels. (Phase 7 did not:
  the user's decision D0 a of 2026-10-21 leaves it to a later PR, a
  pkgconf built from source for both names and channels.)
- G (a): the upgrade test by hand before merging: gamma (pixi, conda,
  micromamba), kappa (pixi, conda), omicron (pixi).
- H (a): `--rzig-check=package` names every missing group the package
  needs in one stop (both texts, compilers first, one exit 127), and
  each conda and pip line ends "; r-zig-toolchain installs every group".
  A refinement within B35: one text per group, several groups per stop.
- I (a): a build tool installed in R's environment but not on PATH is
  named as such ("<path> is installed in R's environment, which is not
  on PATH: activate it (pixi shell, conda activate) or start R with pixi
  run"). Finding it stays PATH's (B34's note).
- J (a): 0009 says "...which is incomplete (see above)" after a 127 and
  "this package cannot be built (see above)" after any other status.
  I-T11 gets that third text (fix-zig-pkg-build-review PLAN.md), and
  stress.R classes it.
- K (a): r-zig-slim has `run_constraints: zig 0.16.*`, bumped with
  r-zig-compilers' pins in the 0.17 wave (B18).
- L (a): the README says universe is public and needs no login.

Also folded into phase 4 by the user: any fix the stress dispatch on
main d11dee1 (38569895172) called for. It called for records only: its
table and conclusion are in feat-shared-build-runner's PLAN.md ("CI"),
and TODO.md's "Later" item is ticked. No code changed for it.

The two decisions the phase 4 run left open, answered by the user on
2026-10-14 ("Follow with the recommended"):
- A (a): conda-package keeps `-c conda-forge` (conda.anaconda.org). A
  build can take a conda-forge package that prefix.dev's mirror has not
  synced yet (libcurl 8.23.0 on win-64, 2026-10-14); the risk is recorded
  under Risks and the README's channel order is the one tested.
- B (a): the four recipe tests keep sharing one zig cache
  (`R_ZIG_TEST_ZIG_CACHE`) until CI's conda leg times decide (TODO.md).

#### Phase 4 record: step 1, conda's four packages (2026-10-14, linux-64)

What changed (B28 a, B41, B39/B11 interim, E2, B14; open points E, H,
K; Cc4, Cc11, Cc12, Cg7, Cg8, Cg9):
- recipe.yaml: build number 9, with an 8 → 9 history entry; the outputs
  comment covers four packages. (2026-10-19: the number is back to 8
  and the history entry is one line, "8 stays", B14's amendment.)
  - r-zig-slim excludes only
    `lib/R/bin/toolchain/{zig,flang,openmp,usr,binutils}/**` and its
    `Library/` form, so it keeps rzig under its six names (unix) or ten
    (Windows) beside share/zig/rpkg. `run_constraints: zig 0.16.*` (K).
    zstd is a run dependency on every OS (E2); libiconv, libstdcxx and
    libgcc stay linux-only.
  - r-zig-compilers: `inherit` with `run_exports: false` and `files:
    []`. It depends on the exact r-zig-slim, `zig 0.16.*`, `flang-zig
    ==23.1.1 *_6`, `lld-zig ==23.1.1 *_5`, `flang-rt-zig ==23.1.1 *_10`
    and llvm-openmp.
  - r-zig-build-tools: win-64's `binutils/**` only (B41). It depends on
    the exact r-zig-slim; on unix also `make >=4.4`; on win-64 today's
    eight m2 packages, pkg-config and zstd, and no native make (Cg7:
    m2-make is the one on PATH, SC §5). Its licence is
    `GPL-3.0-or-later` on win-64 and R's elsewhere (E a).
  - r-zig-toolchain: a metapackage (`files: []`) that exactly pins the
    three others. The recipe's licence is `GPL-2.0-only OR
    GPL-3.0-only` (E a).
  - A `package_contents` test on each output (Cc12): rzig, zig-cc or
    gcc.exe and rpkg/build_t1.zig in r-zig-slim, and no group directory;
    nothing under `lib/R` in the group packages; win-64
    r-zig-build-tools' six tools, SOURCES and LICENSES. Not `strict`:
    every output carries its test file (PHASE4 risk 4).
- The first action, rattler-build 0.76.1's file lists: r-zig-slim
  linux-64 holds 1,883 files, rzig ×6 at 633 KiB each and
  share/zig/rpkg; r-zig-compilers, unix r-zig-build-tools and
  r-zig-toolchain hold only `etc/conda/test-files/<name>/0/<test>.R`.
  r-zig-slim keeps `_8`'s hashes (hb0f4dca linux-64; h41cfa24 osx-arm64
  and h9490d1a win-64 from `--render-only`): target_platform is its
  only hash input.
- recipe/build.sh's comment: r-zig-build-tools owns the binutils (B41),
  r-zig-slim owns rzig (B28).
- The four recipe tests start with one shared header (PHASE4 section
  3): the caller's variables that change what a test checks are unset;
  `R_MAKEVARS_USER` names a file that does not exist (unset, R and rzig
  fall back to ~/.R/Makevars, A3); zig's cache is
  `R_ZIG_TEST_ZIG_CACHE` or the test's own; `narrow()`, `shown()`,
  `same_path()` and `run_to()`.
  - test-preflight.R (r-zig-slim alone), rewritten: rzig and rpkg
    present, no binutils/ or usr/; an R-only package installs; a
    compiled one stops with `zig-cc: no zig (`, the compilers text, the
    conda line naming r-zig-compilers, the pip line, "which is
    incomplete (see above)" and no `hint:` line.
  - test-compilers.R (new): no make on PATH; `--rzig-check=fortran`
    finds the env's flang; a C package and a Fortran package (s.f, the
    FLIBS path) build through `rzig build: tier 1` and load; a package
    with a Makevars rule stops naming r-zig-build-tools and installs
    nothing; unix `R CMD config CC` exits 127 with the build-tools text.
  - test-build-tools.R (new): `--rzig-check=build-tools` finds this
    env's make (Windows: also sh, and the binutils beside rzig);
    `--rzig-check` exits 127 naming r-zig-compilers; `R CMD config CC`
    names toolchain/zig-cc (gcc.exe). Windows: SOURCES and LICENSES
    (moved from test-toolchain.R), nm with only the env's bin and
    System32 on PATH, `pkg-config --version`.
  - test-toolchain.R: every install under the narrowed PATH (Cg9);
    readelf and otool found before PATH is narrowed and run by path;
    the Windows block keeps NM, OBJDUMP and ar.exe.
- groups.zig's conda line: "pixi add r-zig-<group> (or conda install
  r-zig-<group>); r-zig-toolchain installs every group" (H a), with the
  tests' expected texts and the header's conda/pip bullet.
- scripts/conda-consume.sh (new) and the pkg task `conda-consume`
  (Cg8): a fresh pixi workspace from dist/conda, then conda-forge, then
  universe, with environments default, compilers and build-tools; each
  runs its test through `pixi run Rscript` (win-64: Rscript.bat, which
  rattler-build's test phase cannot run).
- conda-package sets `R_ZIG_TEST_ZIG_CACHE` (one zig cache for the four
  tests, Cc11) and empties it with dist/conda: zig's cache cannot tell
  two builds of zig 0.16 apart (env.sh's lesson).

Choices and deviations, with their reasons:
- A B25 finding: on unix R's makefiles need more than make and sh's
  builtins. GNU make runs a recipe line without shell syntax directly,
  by PATH, so config.mk's `@echo $($(VAR))` failed with a PATH of the
  env alone ("make: echo: No such file or directory", 127).
  `narrow(usr_bin = TRUE)` therefore adds the host's /usr/bin:/bin after
  the env on unix (B25's host userland) and m2's Library\usr\bin first
  on Windows. Only test-build-tools.R and test-toolchain.R use it; the
  base-alone and compilers tests keep a PATH of the env only, and
  test-build-tools.R asserts that the make it finds is this env's.
  PHASE4 risk 1 expected such a finding.
- rzig prints its ok lines with the tool's prefix, so the tests match
  `zig-cc: compilers ok: zig 0.16.` and `zig-cc: build-tools ok: make
  at `.
- `run_to()` wraps system2 in suppressWarnings: a 127 written to a file
  makes R warn "error in running command", and the status is the check.
- conda-consume.sh runs pixi by `$PIXI_EXE`, as check-minimal.sh does
  (env.sh narrows PATH), converted with `cygpath -u` on Windows.
- groups.zig's header bullet changed in step 1, with the conda line.
- test-preflight.R and test-compilers.R install with Rcmd.exe INSTALL on
  Windows, as test-toolchain.R does.

Tests (linux-64, conda-forge zig unless named; logs in
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/phase4/step1/):
- `rzig-test` with conda-forge zig and with upstream zig: 129/129;
  parity 112 identical, 59 identical but for the own-env `-L`, 34
  deliberate, 0 failed.
- build, verify-tree, hermetic, package-toolchain, verify-package (the
  three scenarios); `-e minimal` build and toolchain; wheel and
  wheel-test.
- conda-package from an emptied output directory and zig cache: both
  `--error-*` flags, no overlapping or unused staging file, the four
  packages' `package_contents` and script tests (13:38:54 to 13:43:40
  UTC); conda-consume on its three environments (about 30 s).
- verify-tree on an r-zig-slim-alone env made by hand from that channel:
  "compilers verified: lib/R/bin/toolchain/{zig-cc,zig-cxx,zig-fc,
  zig-ar,zig-ranlib,rzig} are rzig, and nothing else is there".

#### Phase 4 record: step 2, PyPI's four wheels (2026-10-14, linux-64)

What changed (B29 a, B35; open points A, E, H; Cg3, Cg10, Cg16, Cc5,
Cc8, Cc14):
- make-wheel.py writes four wheels with one tag set, computed over
  r-zig's and r-zig-build-tools' files together (B29):
  - r-zig: the minimal tree with rzig under its six names beside
    share/zig/rpkg, 51.9 MB (PHASE4's estimate);
  - r-zig-build-tools: the toolchain tree's `usr/` (make, SOURCES,
    `LICENSES/make/COPYING`), 169 KB, `GPL-3.0-or-later` with make's
    COPYING as its licence file (E a); a missing COPYING stops the
    build;
  - r-zig-compilers (8.5 KB) and r-zig-toolchain (8.3 KB): their
    `.dist-info` only.
  - Requires-Dist per A (a); one `metadata()` and one description table,
    every description giving the one recommendation (Cg16) and saying
    PyPI has no Fortran compiler.
  - renviron_hint and TOOLCHAIN_HINT are gone (B35): the wheel's
    etc/Renviron has no hint line. renviron_site (Renviron.site's
    `ZIG_BIN` default, the sibling ziglang) stays. The precondition now
    also requires TC/rzig.
- groups.zig's pip lines: "pip install r-zig-compilers (zig only: PyPI
  has no Fortran compiler); r-zig-toolchain installs every group" and
  "pip install r-zig-build-tools; r-zig-toolchain installs every group"
  (Cg3, H a). Windows keeps "no wheels for Windows".
- python/r_zig/__init__.py's docstring: rzig is in this wheel, `pip
  install r-zig-toolchain` is the recommendation, what r-zig-compilers
  alone does, no Fortran on PyPI.
- test-preflight.R expects the new pip line.
- wheel-test.sh follows PHASE4 section 3's scenarios, with two PATHs:
  `run` (the venv's bin, /usr/bin, /bin) and `run_venv` (the venv's bin
  only) for the boundary checks (Cc8, Cg11):
  - r-zig alone: no ziglang pulled in; zig-cc and rzig present, no
    TC/usr; TLS; then recipe/test-preflight.R itself (Cg10);
  - + r-zig-compilers: ziglang installed, still no TC/usr; zig-fc with
    no flang exits 127 with the new pip text; the console-script install
    builds through `rzig build: tier 1`; the static C++, CONDA_PREFIX
    decoy and R_ZIG_EXTRA_ENV checks as before; `ZIG_BIN=/nonexistent`
    builds through `python3 -m ziglang`; a Makevars-rule package stops
    naming r-zig-build-tools and installs nothing;
  - + r-zig-build-tools: make is TC/usr/bin/make; the Makevars-rule
    package builds through it; the bundled bin/R with
    `R_ZIG_PKG_BUILDER=make`;
  - + r-zig-toolchain: the two empty wheels hold only `.dist-info` (pip
    show -f). A second venv gets ziglang first, then r-zig-toolchain
    with `--no-index --find-links dist/wheel` (Cc5, Cc14): all five
    names, and `Sys.which("make")` is that R's own usr/bin/make;
  - uninstalling the three groups leaves TC with rzig's six names and a
    C/C++ package still builds through rzig build; after `pip uninstall
    ziglang`, test-preflight.R runs again (PHASE4 risk 10).
- The diff is over 200 lines, so it was reviewed skeptically before the
  tests (dropped names, quoting, the globs, `--no-index`, PATH, BSD
  tools); negative controls showed that the dist-info-only assertion
  catches a stray file and a missing METADATA.

Choice: the second venv installs ziglang at the version the first venv
resolved, so wheel-test does not repeat make-wheel.py's requirement
string.

Tests (linux-64; logs in .../phase4/step2/logs/): `rzig-test` with both
zigs (129/129, parity 0 failed); `-e minimal` build and toolchain;
wheel; wheel-test (also a run that kept its temp dir, whose logs were
read: the `ZIG_BIN=/nonexistent` install ran `python3 -m ziglang
build`); the default chain's verify-package.

#### Phase 4 record: step 3, the hint writers and the stop texts (2026-10-14, linux-64)

What changed (B35, C8; open points B, C, H, I, J; Cg1, Cg2, Cg4, Cg5,
Cc9, Cc19):
- build.zig: `-Dtoolchain-hint`, Ctx's field and both writers
  (Renviron.site, etc/Renviron) are gone. installRzig's doc comment says
  the base carries rzig on every channel (B19, B28, B29). win-64's
  Renviron.site keeps MY_TCLTK.
- zig-build.sh's `R_ZIG_CONDA_BUILD` branch and recipe.yaml's
  `R_ZIG_CONDA_BUILD: "1"` are gone.
- Patch 0009: the rzig-missing branch and its "not installed" stop are
  gone (C8). After a 127: a set `R_ZIG_TOOLCHAIN_HINT` as `hint:
  <value>`, then "...which is incomplete (see above)"; after any other
  status: "this package cannot be built (see above)", with no hint (B b,
  J a).
- Patch 0010 keeps one line, `"${rzig}" --rzig-check=build-tools >
  /dev/null || exit` (B b).
- Patch 0013: the "older than this R" stop and its cc lookup are gone;
  I-PF4's stop and the make path stay (C a).
- The series was regenerated in scratch (0001-0008 applied, then 0009,
  0010 and 0013 edited and diffed): all 13 patches apply to the pristine
  tarball with `patch -p1 -f -F0`, no offset, fuzz or reject.
- check.zig: H's stop (with the compilers missing, a package that needs
  make and has none gets both texts, compilers first, one 127; a wrong
  zig's exit 1 returns before that, with no build-tools text) and I's
  `notOnPath()` line (unix: `<env>/bin/<MAKE's first word>`; Windows:
  `<env>/Library/usr/bin/make.exe` or `sh.exe`; a MAKE that is a path
  gets none), with unit tests; the tier-3 `m` and configure `zF` cases
  now expect both texts.
- pkgbuild.zig's sharedRunner keys the zig command with `/` on Windows
  (feat-shared-build-runner open decision 1 b), with a unit test. The
  host round moved the normalisation into cache.zig (below).
- Comments: groups.zig's header (rzig does not read the hint; nothing
  writes it since phase 4), fortran.zig's test, parity-test.sh's and
  check.zig's code-6. stress.R's classifier and stress/README.md learn
  J's stop (Cc19).
- test-preflight.R: no `R_ZIG_TOOLCHAIN_HINT=` line in etc/Renviron or
  Renviron.site (Cc9); a configure-script package (configure.win on
  Windows) stops with both texts, compilers first, its script not run
  (H); a user's hint appears once, after the compilers text and before
  the stop (B). test-build-tools.R: with an empty PATH (Windows: plus
  System32), the build-tools check exits 127 with I's line naming this
  env's make.

Choices and deviations, with their reasons:
- I's lookup uses MAKE's first word (MAKE=gmake looks for
  `<env>/bin/gmake`); PHASE4 named `<env>/bin/make`.
- 0010's comment points at 0009 without naming the variable, so PHASE4
  section 2's `git grep` keeps to its list. The grep finds only 0009,
  test-preflight.R, the comments in groups.zig, fortran.zig and
  verify-bundle.sh, and the shared test header's unset (the plan's own
  header).
- 0009's header covers rzig shipping on every channel, the two stops,
  H's stop and code-6's extra line (fix-zig-pkg-build-review's small
  follow-up).

Tests (linux-64; logs in .../phase4/step3/logs/):
- `rzig-test` with both zigs: 132/132; parity 112/59/34/0. rzig and its
  unit tests cross-compiled (`--test-no-exec`) for x86_64-windows-gnu,
  aarch64-macos and x86_64-macos.
- default: build (R re-extracted for the new series, 161 s), toolchain,
  verify-tree, smoke, compile-tree, contract, hermetic, pkg-parity,
  package-toolchain, verify-package. minimal: build, verify-tree,
  contract, verify-package; wheel, wheel-test.
- conda-package: r-zig-slim hb0f4dca_9, r-zig-compilers h9276ec7_9,
  r-zig-build-tools h9276ec7_9, r-zig-toolchain hdc6fa2d_9 (built
  locally as `_9` before the 2026-10-19 decision; the PR keeps 8), the
  four tests with the new H, B and I checks; conda-consume.
- By hand on dist/slim: a stand-in zig 0.17 with the hint set gives "is
  zig 0.17.0, not R's zig 0.16", the compilers text and "ERROR: this
  package cannot be built (see above)", no hint; no zig gives the
  compilers text, `hint: site-hint` and the incomplete stop. stress.R on
  synthetic logs: 127 and a wrong zig are toolchain, a src/build.zig
  make cannot build is package.
- pkg-parity failed once only because a minimal build beside it wrote to
  the shared build/zig-cache between its two counts; run alone it
  passed. Do not run another R build, contract or verify-package beside
  pkg-parity.

#### Phase 4 record: step 4, D7, docs and CI (2026-10-14, linux-64)

What changed (D7; open point L; Cg8, Cc11, Cc14):
- D7: CC_VER in linux-x86_64-{slim,full} and linux-arm64-{slim,full}
  (config.h and subst.txt) names clangdev-feedstock 334cf9a5 (the lock's
  libclang-cpp21.1 `_6`, the same build on linux-aarch64;
  linux-arm64-minimal had it). FC_VER in osx-arm64-{slim,full,minimal}
  is "flang version 23.1.1": the lock's osx-arm64 flang-zig `_6` has no
  repository string (it was built from a rattler-build work dir, not a
  git checkout), as omicron's `flang --version` confirmed. Windows'
  strings come from build.zig (compiledBy) and are unchanged.
- README: five platforms; universe is public, no login (L a);
  r-zig-slim with the one recommendation ("To compile packages, add
  r-zig-toolchain (r-zig-compilers and r-zig-build-tools)") and a bullet
  per group (r-zig-compilers alone installs packages with no configure
  script whose Makevars only sets variables; r-zig-build-tools serves
  configure scripts, Makevars rules, `R CMD SHLIB` and pak's probe); the
  stop that names the package to add, and I's advice; the four .conda
  files and conda-consume; four wheels, Linux and macOS only, with the
  ziglang-first and `--no-index --find-links dist/wheel` lines (Cc14),
  no Fortran or OpenMP on PyPI (B29), and "uninstall ziglang too for R
  alone" (PHASE4 risk 10).
- pixi.toml's comments (minimal's wheel, `[feature.wheel]`, wheel-test,
  conda-package) and verify-tree.sh's (r-zig-build-tools carries
  binutils/, B41).
- build.yaml: the win-64-only "Fresh-env consume test (Windows PATH
  shim)" becomes "Fresh-env consume test (each group alone)", `pixi run
  -e pkg conda-consume`, on every conda-package leg before the publish
  (Cg8). recipe.yaml's win test comment points at conda-consume.sh.
- recipe.yaml: the four R tests declare `secrets:
  [R_ZIG_TEST_ZIG_CACHE]` (below).

Findings and deviations, with their reasons:
- Cc11's shared test cache had never worked on unix. rattler-build
  0.76.1's unix test env keeps PATH and rattler-build's own variables
  only (a probe recipe dumped it); SC §3 had seen win-64's, which keeps
  the caller's. The tests now get the variable as a test secret: the
  test sees it (masked in the log), info/tests records only its name,
  and without it one warning and the test's own cache. `env:` would have
  written the build machine's path into the package. The shared header's
  and pixi.toml's comments say how the variable arrives. Sharing saved
  no measurable time on gamma (preflight 3 and 4 s, compilers 20 and
  22 s, build tools 1 and 1 s, toolchain 40 and 42 s, without and with):
  CI's conda legs decide whether it stays (TODO.md).
- D7 drifted on day one (PHASE4 risk 7). The conda build solves
  libclang-cpp21.1 21.1.8 `_7` (clangdev 0586bae9) where the lock has
  `_6`, and zig `_20` takes its clang version from libclang-cpp at run
  time. So linux `_9`'s libR.so carries config.h's 334cf9a5, which
  R_compiled_by() prints, and 0586bae9, the compiler's own `.comment`.
  recipe.yaml's history note said so (until 2026-10-19, when the
  history entry became one line), and TODO's first "Later" item is
  build.zig computing CC_VER/FC_VER on every OS (Cg15).
- README: "packages" in Publish and two plural headings, from the split.

Tests (linux-64; logs in .../phase4/step4/logs/): build, then
`R_compiled_by()` prints the clangdev 334cf9a5 string and "flang version
23.1.1", what the lock's zig and flang print; verify-tree; actionlint on
the six workflows, no finding; conda-package before and after the
secrets (after: build/conda-test-zig-cache 56 MB, the four suites pass)
and conda-consume on each; `rattler-build --render-only` for win-64 and
osx-arm64 renders the five outputs.

#### Phase 4 review (2026-10-14)

An adversarial review of steps 1 to 4 confirmed four findings, all
fixed and rerun on linux-64 (logs in .../phase4/fix/logs/):
- [conda-d7-cc-ver-stale] the recipe said CC_VER was refreshed while
  linux `_9` names another compiler: the 8 → 9 history note said what
  CC_VER is and why it differs (that note gave way to the one-line "8
  stays" entry on 2026-10-19), TODO.md's D7 item records it, and
  "Later" starts with build.zig filling CC_VER/FC_VER. Pinning
  libclang-cpp21.1 `_6` in the staging env was the alternative, not
  taken (simplicity first).
- [conda-win64-boundary-usr-bin] on win-64 the "no build tools in this
  group" checks ignored `Library\usr\bin`, where m2's make and sh
  install: test-compilers.R and test-preflight.R fail on make or sh
  there too, and their stop assertions also reject I's "is installed in
  R's environment".
- [conda-stale-pin-comment] the staging flang pins' comment named
  r-zig-toolchain's depends: it names r-zig-compilers' now
  (r-zig-toolchain pins the other three outputs).
- [preflight-j-b-untested] no test checked J's non-127 stop or B's
  127-only hint: test-preflight.R (unix) points ZIG_BIN at a stand-in
  zig that says 0.99.0, with the hint set, and asserts "is zig 0.99.0,
  not R's zig", "this package cannot be built (see above)", no
  "incomplete", no `hint:` line and nothing installed.
Rerun: conda-consume on step 4's packages, wheel-test (test-preflight.R
twice), conda-package (15:31:56 to 15:36:40 UTC, the four tests) and
conda-consume on its packages.

#### Phase 4 record: tests on every host (2026-10-14)

Round 1 ran on the worktree after the review's fixes (`git diff` sha256
0a033cb3...4a83962), round 2 after the host fixes below (88c0160a...
f14e540). pixi.lock was fbb64b7b...a68bb96 at every start and end, and no
host wrote the worktree. The code has not changed since round 2's sync
(16:50 UTC); only these records have.
- omicron (macOS 26.4, osx-arm64, pixi 0.81.0), both rounds: `rzig-test`
  with conda-forge zig and with upstream zig (132/132, then 133/133);
  build, toolchain, verify-tree, compile-tree, contract, pkg-parity,
  package-toolchain, verify-package; `-e minimal` build, toolchain,
  verify-package (round 2 also verify-tree); wheel (four wheels,
  macosx_13_0_arm64, r_zig 46.8 MiB) and wheel-test (322 s);
  conda-package (248 s; r-zig-slim h41cfa24_9, r-zig-compilers
  h3c217e4_9, r-zig-build-tools h3c217e4_9, r-zig-toolchain h80fa0fb_9,
  built locally as `_9` before the 2026-10-19 decision, the PR keeps 8;
  the four tests) and conda-consume (40 s). D7: flang-zig prints
  "flang version 23.1.1" and zig cc "clang version 21.1.8", as the
  osx-arm64 configs now say, and R_compiled_by() prints both. Not run:
  osx-64 under Rosetta (PHASE4 section 8's conda-package and
  conda-consume row); CI's macos-15-intel leg is the first run there.
- kappa (win-64, Windows 11, pixi 0.81.0), both rounds: `rzig-test` with
  both zigs (104 pass and 28 skipped, then 105 and 28); build (7 min),
  toolchain, verify-tree (TC holds exactly the ten rzig names),
  compile-tree, contract, pkg-parity, hermetic, package-toolchain,
  verify-package; conda-package (12.5 min; r-zig-slim h9490d1a_9,
  r-zig-compilers h5f95ccc_9, r-zig-build-tools h5f95ccc_9,
  r-zig-toolchain h98fa296_9, built locally as `_9` before the
  2026-10-19 decision, the PR keeps 8; the four tests; R_ZIG_TEST_ZIG_CACHE
  reached the win-64 tests) and conda-consume (1.8 min through
  Rscript.bat: the H, I and boundary checks, nm with the env's zstd.dll,
  pkg-config 0.29.2). r-zig-build-tools holds the six binutils, SOURCES
  and LICENSES; the other three hold only their test file.
- gamma (linux-64): steps 1 to 4 and the review's reruns (above), the
  upgrade test (below), and the host fixes' reruns.

The host fixes, between the rounds (linux-64, then round 2 on omicron
and kappa):
- verify-tree.sh's rzig-names check compared the copies byte for byte.
  In a macOS conda env rattler-build relinks every Mach-O it packages
  (rzig gets the rpath `@loader_path/../../..`) and signs each copy ad
  hoc under its own file name (Identifier=zig-cc-5555...), so the six
  copies differ in their signatures alone, as `_8`'s did. `same_rzig()`
  compares them unsigned there (copies run through codesign
  --remove-signature; plain cmp elsewhere), and the baseline-CPU check's
  "is this rzig" test uses it too.
- verify-tree.sh's binary checks walked the whole conda env, so
  conda-forge's own files failed them: zig's wrappers (glibc 2.34;
  macOS 15.7), sysroot_linux-64's libc (2.28 in pixi's solve, 2.39 in
  conda's and micromamba's), ncurses' libtinfo named by its path. In a
  conda env they now read R_HOME only: r-zig-slim ships no binary
  outside it (bin/R and bin/Rscript are scripts). Trees that are not
  conda envs are read whole, as before. The check predates phase 4 (an
  `_8` env fails it the same way); section 7 was the first to run it on
  an env with every group.
- cache.zig's `command()` keys the zig command with `/` on Windows, for
  `compiled()` (the cfguard and dso_fini objects) and pkgbuild's
  sharedRunner alike: in round 1 the runner was fixed, but one zig
  still got two cfguard entries (04c199fe, 6dc1c0c6). Unit test `test
  command`.
- stress.R's and pixi.toml's comments on universe and conda-forge (the
  upgrade's channel order, below).
- Reruns on linux-64: `rzig-test` with both zigs (133/133, parity 0
  failed); the patched verify-tree on gamma's seven upgrade and fresh
  envs (pixi ×2, conda, micromamba, r-zig-slim alone, + compilers,
  + build tools: 22 R_HOME binaries each, glibc worst 2.17 at libR.so;
  unpatched, every env with r-zig-compilers had failed) and on dist/slim
  (71 binaries) and dist/minimal (43). Round 2: omicron's verify-tree
  passes on the upgraded env and three single-group envs (22 Mach-O
  files each) and on dist/slim (63) and dist/minimal (40); kappa's on
  its upgraded envs.

The Windows runner key (feat-shared-build-runner open decision 1 b),
on kappa: one conda-forge zig reached three ways (PATH's
`C:\...\x86_64-w64-mingw32-zig.exe`, `ZIG_BIN=C:/...` and
`ZIG_BIN=C:\...`) used one `build-runner-6960828f...` directory in round
1, and one build-runner and one `cfguard-6dc1c0c6...` directory in round
2; upstream zig got its own pair. The runner's last-used names the `/`
form. Other OSes key the command as spelled (`\` is a file name's
character there).

Local conda-package times (Cc11; CI's legs are still to come, against
ea7e6ee's, win-64 15.5 min): linux-64 about 4 min 45 s, osx-arm64 248 s,
win-64 12.5 min.

#### Phase 4 record: the upgrade from `_8` (2026-10-14)

PHASE4 section 7, G (a). Each host went from universe's `_8` to its own
`_9` channel (built locally as `_9` before the 2026-10-19 decision;
the PR keeps 8), in scratch with fresh caches (PIXI_CACHE_DIR,
RATTLER_CACHE_DIR, CONDA_PKGS_DIRS, MAMBA_ROOT_PREFIX):
- gamma (linux-64; pixi 0.81.0, and conda 26.9.2 with libmamba and
  micromamba 2.9.0 through `pixi exec`; `env -i` with PATH=/usr/bin:/bin,
  so gamma's ~/.pixi/bin zig 0.17 stayed out): pixi (section 7's
  channels, universe first), `conda update` and `micromamba update` of
  r-zig-slim and r-zig-toolchain, and conda adding only r-zig-compilers
  to an `_8` env, which moved all four to `_9` in one transaction (the
  forced replacement section 7 predicts). The channel was the review
  fix's conda-package (r-zig-slim hb0f4dca_9 sha256 3b443b89...). Its
  rzig predates cache.command, which changes nothing on linux.
- kappa (win-64; pixi 0.81.0, conda 26.9.2 through `pixi exec`): a
  script run as `bash <file>` in Git Bash, from a .bat over ssh, with
  paths in `cygpath -m` form and `file:///` for conda's channel URL
  (the form Cc7 named; no PowerShell). conda with section 7's channels
  (local, universe, conda-forge) in both rounds; pixi in README's order
  (conda-forge, universe, the local channel prepended) in both rounds.
- omicron (osx-arm64; pixi 0.81.0): pixi in both rounds, README's order
  in round 2.

Every upgraded env ended with:
- the four packages at `_9`; no clobber in any log and no
  `__clobbers__`;
- TC exactly rzig's names (six on unix, ten on win-64), one binary
  (macOS: once unsigned), owned by r-zig-slim `_9` in conda-meta; on
  win-64 also binutils/ with its six tools, SOURCES and LICENSES, owned
  by r-zig-build-tools `_9`, and none of `_8`'s as, ld, nm, dlltool,
  strip, windres, zig-cc or zig-cxx at TC's top (`ar.exe` is
  `gcc.exe`'s bytes);
- share/zig/rpkg/build_t1.zig present; no `R_ZIG_TOOLCHAIN_HINT` in
  etc/Renviron or Renviron.site (`_8`'s line gone);
- R starting; recipe/test-toolchain.R passing (C and C++ through rzig
  build and make, zlib, AR/RANLIB, NM/OBJDUMP on win-64, Fortran with
  USE_FC_TO_LINK); verify-tree passing on the env, with the host fixes.
This closes the risk "rzig moving between conda packages".

Also on gamma, fresh envs from the `_9` channel: r-zig-slim alone passes
test-preflight.R, and a compiled install stops naming r-zig-compilers
and "r-zig-toolchain installs every group", with no hint; with gamma's
zig 0.17 on PATH it stops with "is zig 0.17.0, not R's zig 0.16" and
"this package cannot be built (see above)" (J a). + r-zig-compilers
passes test-compilers.R and installs a C package through tier 1 with no
make anywhere on PATH. + r-zig-build-tools passes test-build-tools.R.
K: `pixi add r-zig-slim zig` solves zig 0.16.0 `_20` although
conda-forge has 0.17.0. Each group package installs only its test file,
and all four say `GPL-2.0-only OR GPL-3.0-only` on unix.

What changed against section 7's procedure:
- pixi 0.81.0's `pixi workspace channel add --prepend` re-locks and
  installs, so the `pixi update` after it reports the lock up to date
  and its log shows no transaction. With `--no-install` the lock is
  `_9` (`pixi list` reads it) while the env stays `_8` until `pixi
  install` or `pixi run`. Round 2 ran `channel add --prepend
  --no-install "$CH"`, checked that the env still held `_8`, then `pixi
  install -v 2>&1 | tee`. That log has summary lines only, so "no
  clobber" rests on no WARN line and no `__clobbers__`.
- "All the same bytes" holds on macOS once unsigned (above).
- verify-tree on a conda env reads R_HOME's binaries (above).
- The channel order. kappa's pixi solve with universe before
  conda-forge (section 7's `pixi init` line) failed on 2026-10-14:
  r-zig-slim `_9` win-64 has the run export libcurl >=8.23.0 (its build
  solved conda.anaconda.org's libcurl-8.23.0-hdb0ef4a_0, uploaded at
  15:14 UTC, about an hour earlier), and universe's shard index
  (win-64/repodata_shards.msgpack.zst) declares `channel_relations:
  {base: ../conda-forge}`. Listed first, universe gives pixi, whose
  channel priority is strict, every conda-forge name from prefix.dev's
  conda-forge mirror, which did not have that libcurl on win-64 yet
  (linux-64's had it: gamma's universe-first upgrade passed, taking make
  and zig from prefix.dev/conda-forge). README, conda-consume.sh and
  stress.R list conda-forge first, and conda reads repodata.json, which
  has no channel relations. At 17:54 UTC the mirror listed the package,
  and a solve-only probe on gamma (platform win-64, kappa's round-2
  packages, fresh caches; .../phase4/recorder/probe/) solved
  r-zig-toolchain `_9` in both orders, universe-first taking libcurl
  8.23.0 from prefix.dev/conda-forge: it was the mirror's lag.
  pixi.toml's and stress.R's comments now give this as the reason for
  conda-forge first. They said that priority was moot because
  universe's names never collide with conda-forge's, and that universe
  mirrors libdeflate; universe's repodata lists only blast, flang-rt-zig,
  flang-zig, lld-zig, r-zig-slim and r-zig-toolchain, and the base
  relation is what matters. Users who list universe first can meet the
  same lag after any publish ("Risks"). (2026-11-12: superseded. universe
  has had no base relation on prefix.dev since 2026-11-12, and universe
  is listed before conda-forge everywhere: flang-rt-zig's `llvm-openmp
  zig_*` dependency is uninstallable with conda-forge first under strict
  priority; see chore-release-11/PLAN.md, findings 13 and 14.)

Not run, by G (a): micromamba on kappa and omicron, conda on omicron.

#### Phase 4 record: what PHASE4 asked to record, and the rest

- E2 is applied on every OS (Cg18): osx-arm64's libR.dylib links libzstd
  too, and `HAVE_ZSTD` is set in all 13 configs (SC §9), so r-zig-slim
  states zstd everywhere; the host's run exports gave it already.
- No native make on win-64 (Cg7): r-zig-build-tools depends on m2-make,
  which is the make on PATH (SC §5). Phase 7 chooses the set for both
  channels.
- I-T11's third text (J a) is recorded in fix-zig-pkg-build-review's
  PLAN.md; its "not installed" text is gone with 0009's rzig-missing
  branch.
- H's stop names every missing group: one text per group (B35), several
  groups in one stop.
- The test PATH (PHASE4 risk 1, Cg9): every recipe test narrows PATH to
  its env; on unix the build-tools and toolchain tests add the host's
  /usr/bin:/bin after it (step 1's B25 finding), and rattler-build's
  unix test env passes no other caller variable (step 4).
- PHASE4 section 11's stale line references were not rewritten: the
  decision records and "What exists today" cite HEAD 9bbce0b, as this
  file's header says, and phase 4 moved those lines again. The
  references in text that looks forward now name functions ("Where PyPI
  differs", phase 8).
- The copied plan keeps section 7's original procedure; the changes are
  above.

### Phase 5 — zig in the compilers group

Goal: base + compilers compiles with nothing from the build env.

Decisions (answered): B4; B6 (both cases are tested either way); B13
only records sizes; the related item D6 (b).

Steps:
- The toolchain step installs fetch-zig's zig into `TC/zig/` (B4), with
  `LICENSES/` (LICENSE and the dist-info licences) and `SOURCES` (wheel
  URL and sha256).
- verify-toolchain (verify-tree checks the R trees, which hold no
  `zig/`; phase 3 split the two): `zig/` counted as third-party in the
  build-path scan; `zig/zig version` prints 0.16.0.
- verify-bundle scenario 2 without `ZIG_BIN`: RZIG_PRINT_ARGV shows
  `TC/zig/zig`.
- `-lsynchronization` with upstream zig on Windows (D6 = b): done by PR
  #19 (fix-rzig-follow-ups, 7a3004d): rzig renames `-lsynchronization`
  to `api-ms-win-core-synch-l1-2-0` for both zigs; phase 5 adds the
  Windows package test. No import library is generated: zig builds it
  from the API set's `.def`, which both zigs ship, and fix-rzig-follow-ups
  PLAN.md ("How this answers D6 b") gives why the rename meets the
  user's answer. Nothing is reported upstream.
- The existing compiles with `ZIG_BIN=$ZIG` and the env's tools stay as
  a fourth pass, so conda-forge's zig keeps its package coverage:
  verify-bundle's `build` pass.
- Record the archive sizes per OS here.

Tests:
- The three scenarios on every OS: C, C++ (no shared libc++ or
  libstdc++), OpenMP C in three forms and the flagless omp.h probe
  (slim); the mixed case on the default legs, the one-zig case on the
  upstream legs (label run).
- kappa and windows-latest, with `TC/zig/` (upstream zig): a package
  that links `-lsynchronization` builds and loads.

**Status (2026-10-15): steps 1 to 6 done in the worktree
feat-standalone-phase5 (branch feat-standalone-phase5: main d11dee1 plus
phase 4's and the R CMD SHLIB routing's uncommitted changes), not
committed. Tested on linux-64 (both zigs), omicron (osx-arm64, both zigs;
osx-64 under Rosetta) and kappa (win-64, both zigs); the review's two
findings and one host finding are fixed, and the testers' rounds after
them pass ("Phase 5 review", "tests on every host"). CI has not run: the
branch is not pushed.** The work follows the reviewed implementation
plan, copied here as phase5/PHASE5-IMPLEMENTATION.md with its critique
phase5/CRITIQUE.md (cited below as PHASE5 <section>, Cc<n> and Cg<n>),
and the user's answers to its open points ("Phase 5: the user's
answers"). The build number stays 8 (the user's decision of
2026-10-19, B14's amendment; it was 11, the number after SHLIB's 10, B14
a): phase 5 changes rzig's text, which r-zig-slim and the r-zig wheel
carry, and publishes with phase 7's bump.
pixi.lock is unchanged on every host (sha256 fbb64b7b...a68bb96); phase 5
changes no dependency of a pixi env. Merge order: phase 4's PR, then
SHLIB's, then phase 5's, which is `phase5-only.diff` against those two
(open point O). Next: the user commits and opens the PR (the core
tier and conda-package first, then the `full-ci` and `upstream-zig`
labels); CI's numbers go into a new "Phase 5 record: CI".

#### Phase 5: the user's answers (2026-10-15)

The user, 2026-10-15: "Start phase 5", after "Follow with the
recommended" for the previous work. Every open point of PHASE5 section
11 takes its recommended option; each is recorded here as answered that
way, the options not taken named after it.
- A (a): zig-toolchain.sh runs fetch-zig, the one pin table, and passes
  the unpacked wheel as `-Dziglang=<dir>`; fetch-zig's `.complete`
  marker holds the wheel's URL, its sha256 and the source line; build.zig
  and wheel.zig read the rest from the wheel's METADATA and RECORD. Not
  taken: (b) build.zig.zon lazy dependencies (a second pin table), (c)
  the pins in build.zig read by bash.
- B (a): `zig/SOURCES` is one block in conda's shape: package ziglang,
  version, build (the wheel's tag), url and sha256 (the wheel), license
  (METADATA's `License-Expression`), a `source:` line (ziglang.org's
  zig-0.16.0.tar.xz and its sha256), a `feedstock:` line (zig-pypi; the
  wheel records no commit) and a `file:` line per copy with the RECORD's
  sha256 in hex. Not taken: (b) a shorter PyPI block with its own
  branch in verify-toolchain.
- C (a): `zig/LICENSES/ziglang/` is the wheel's dist-info licences, 15
  files, as B4 says. Not taken: (b) adding LLVM's LICENSE.TXT from no
  release. The licence wording is below ("the licence set").
- D (a): verify-toolchain in batch: one hashing pass and one awk join
  for the records and copies, one `xargs grep -l` for the build-path
  scan, one `xargs grep -l` of the magic numbers before the exact binary
  test, and the zig version check. Not taken: (b) skipping `zig/lib/`.
- E (a): verify-bundle's no-zig preflight check moves `TC/zig/zig`
  (`zig.exe`) aside into VERIFY_DIR and back. Not taken: (b) a directory
  of its own with the base and the build-tools archive, (c) dropping the
  check. The surveys split (Cg5): the records survey recommended (b), a
  layout a user can have; the rzig survey (a). The plan took (a) for
  simplicity, the user's rule: two lines and the same question rzig is
  asked. (a) tests a modified tree, not a layout a user has.
- F (a): verify-bundle.sh takes the pass as its argument: `toolchain`,
  the default, runs every scenario with ZIG_BIN unset; then the script
  runs itself once more as `build`, with ZIG_BIN=$ZIG and env.sh's
  cache, unless `$ZIG` has TC/zig's bytes (the upstream legs). Not taken:
  (b) only the package blocks twice, wrapped in a function; (c) no fourth
  pass.
- G (a): the toolchain pass passes no cache variable, so zig keeps its
  default cache under the fresh HOME, as a new user's does; the build
  pass keeps env.sh's. Not taken: (b) env.sh's cache in both passes.
- H (a): the compilers group's standalone line reads `extract
  R-<ver>-<plat>-compilers.tar.gz where you extracted R (zig 0.16 and the
  OpenMP files), and put LLVM flang on PATH` (`.zip` on Windows); ZIG_BIN
  is no longer named there (the README keeps it as an override). Not
  taken: (b) "or zig 0.16 in ZIG_BIN". The surveys' wordings (Cg5): the
  records survey proposed "(zig, OpenMP); LLVM flang on PATH for
  Fortran", the rzig survey the wording taken.
- I (a): every toolchain leg fetches the wheel through zig-toolchain.sh;
  the artifact grows to 84-100 MB per platform; retention stays 30 days.
  Not taken: (b) 7 days for the group artifacts.
- J (a): no `zig/` and no fetch when the prefix is the env: build.zig's
  `prefix_is_env` decides what is installed, zig-toolchain.sh whether to
  download, by the same real-path test (`same_dir` in env.sh, which was
  vendor-libs.sh's `resolved()`). Not taken: (b) R_TOOLCHAIN_PREFIX
  conda-only.
- K (a): CI's macos-15-intel leg (full-ci) is the osx-64 test; omicron
  tried the toolchain tree and verify-package under Rosetta (below). Not
  taken: (b) an upstream-zig osx-64 leg. So the one-zig case has no run
  on osx-64 or linux-aarch64 (upstream-zig.yaml's three runners only);
  their mixed case passes (omicron's osx-64, CI's default legs). TODO's
  "Later" has the menu.
- L (a): `-lmsvcrt` is recorded as an open item; kappa tested magick and
  gifski with TC/zig (step 3b, below); no package reached `-lmsvcrt`, so
  no `mingw_names` mapping. Not taken: (b) `msvcrt` → `c` now.
- M (a): build number 11 (B14 a). If another build publishes first,
  the one after universe's newest. (Superseded 2026-10-19: no bump in
  phase 5, the number stays 8; B14's amendment.)
- N (a): two zigs sharing zig's default cache on a user's machine goes
  under "Later: zig's global cache"; no rzig change. Not taken: (b) a
  per-zig ZIG_GLOBAL_CACHE_DIR set by rzig.
- O (a): `phase5-only.diff` against the SHLIB baseline, checked by
  applying it to a second copy; three PRs in order. Not taken: (b) the
  whole worktree diff for the user to split.
- P (a): the minimal env's `toolchain` fetches zig too: one tree per
  platform. Not taken: (b) a flavor rule.
- Q (a): verify-bundle asserts the zig through the check line (`/` only)
  and through RZIG_PRINT_ARGV's first word with `\` turned into `/`,
  case-insensitive, on every OS; rzig is unchanged. Not taken: (b)
  find_zig's `inDir` joining with `/` on Windows.
- R (a): the mixed case's notes are recorded below, no change. Not
  taken: (b) CC_VER fixed now.
- S (a): the build pass skips scenario 1 and the no-zig check, one note
  line each. Not taken: (b) the whole script twice.
- T (a): no workflow step changes; `compression-level: 0` goes to
  "Later and future checks". Not taken: (b) the one line now.

One more point, from step 3b, answered the same way (its (a)): Rust
static libraries built for the r-windows clang-x86_64 bundles need an
unwinder in a C link. gifski's prebuilt library, linked through gcc.exe,
fails with 9 undefined `_Unwind_*` and `_GCC_specific_handler` symbols
(Rust std's `rust_eh_personality`), with both zigs alike, so neither
TC/zig nor `-lmsvcrt` is the cause. GNU gcc with `-static-libgcc` links
libgcc_eh and llvm-mingw's clang links libunwind by default; zig cc does
neither for a C link. magick's librsvg links only because its link is
C++, where zig adds libunwind. (a) taken: recorded as an open item for
after phase 5 ("Later and future checks"). Not taken: (b) a windows.zig
rule adding `-lunwind` to an image link (-shared or exe) through
gcc.exe, measured to work with both zigs via `SHLIB_LIBADD = -lunwind`;
(c) leave it to packages.

#### Phase 5 record: what changed (2026-10-15)

- scripts/fetch-zig.sh: the source tarball's pin beside the version
  (`https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz`, sha256
  43186959..., checked against ziglang.org's index.json). `.complete`
  holds `url:`, `sha256:` and `source: <url> sha256:<hex>` (SOURCES'
  form); an empty marker (the old fetch-zig's) fetches again.
- scripts/zig-toolchain.sh: runs `bash fetch-zig.sh` and passes
  `-Dziglang=<dir>`, except for `test` or when `same_dir
  "$TOOLCHAIN_PREFIX" "$CONDA_PREFIX"` (J). scripts/env.sh: `same_dir`,
  vendor-libs.sh's `resolved()` moved and made a predicate (Windows
  compares `cygpath -m -l`, lower-cased); vendor-libs.sh calls it.
- zigbuild/toolchain/wheel.zig (new, pure, 6 tests): the marker,
  METADATA (headers end at the first blank line; Project-URL `Source
  Code`), the wheel tag and RECORD (`ziglang/<exe>` and `ziglang/lib/...`
  kept, urlsafe base64 decoded to hex).
- zigbuild/toolchain/build.zig: the `ziglang` option. Unless the prefix
  is the env it reads the marker and the one `ziglang-*.dist-info`,
  checks every RECORD entry exists, installs `zig/zig` (mode kept),
  `zig/lib` and `zig/LICENSES/ziglang`, and writes `zig/SOURCES` with
  conda.zig's `writeSources` from a synthetic record (B). The option
  missing is an `addFail` step. The test step runs wheel.zig's tests.
- scripts/verify-toolchain.sh (D): each directory's records and copies
  as one find, one batched sha256sum and one awk join (messages sorted);
  the build-path scan of the copies as one LC_ALL=C `xargs grep -laE`;
  the binary detection as one `xargs grep -l` of the magic number ($'^\x7fELF'
  on linux, Mach-O's $'^\xcf\xfa\xed\xfe' on macOS; Windows keeps its
  name filter), then the four-byte test on those only; a positive check
  that `zig/zig` is among the binaries when `zig/` is there (Cg8); `zig/zig
  version` must equal SOURCES' ziglang version. Every batched grep sits
  behind a `[ -s ]` guard or `|| true`, so a match of nothing does not
  stop the script under pipefail (Cc2, Cc6).
- zigbuild/tools/rzig/groups.zig (H, B35): the standalone line above;
  parity-test.sh's anchored grep for it.
- scripts/verify-bundle.sh (E, F, G, Q, S; Cc3, Cc4, Cc8, Cc11, Cg1,
  Cg4): the pass argument and `pass_zig`; the check mode asserts "at
  $pass_zig"; the first C++ compile (`<iostream>`, `<string>`,
  `<vector>`) timed under env -i, with its cache where the pass puts it
  (unix `$HOME/.cache/zig`, Windows `%LOCALAPPDATA%\zig`) and no shared
  C++ runtime; RZIG_PRINT_ARGV's first word equals `$pass_zig` on every
  OS, and again on unix under the package compiles' PATH, whose first
  entry is the env's bin with conda-forge's zig (find_zig's order, B4;
  review finding tests-1); every zig guard of scenarios 2 and 3 tests `$pass_zig`; the
  baseline-CPU compiles under one shared `env -i` environment (three
  calls: Windows' bin\x64 + System32 has no sh to run one shell); Windows'
  `syncw` package (`PKG_LIBS = -lsynchronization`, WakeByAddressSingle)
  built through rzig build tier 1, importing
  api-ms-win-core-synch-l1-2-0.dll, loaded and called, in both passes;
  the no-zig check moves only `TC/zig/zig` aside; the toolchain pass
  removes its VERIFY_DIR before it `exec`s the build pass (Cc4); one
  final line per pass with its zig and wall time.
- Docs and comments: README (the compilers bullet, SOURCES, the extract
  example, "a week" → the bases a week and the groups 30 days, the dev
  note that `toolchain` downloads the wheel once per platform into
  build/zig-upstream/, Cg6); env.sh, compile-tree.sh, toolchain.yaml's
  header and upload comment, pixi.toml's fetch-zig, toolchain and
  toolchain-test comments (comments only: no table changed, the lock
  unchanged, `pixi lock --check` passes).
- recipe/recipe.yaml: `number: 11` with its 10 → 11 history entry (M).
  (2026-10-19: back to 8, with one "8 stays" line for phases 4 to 6;
  B14's amendment.)

What did not change: rzig's lookup (ZIG_BIN, then `<rzig dir>/zig/zig`,
then R's environment's bin, PATH, `python3 -m ziglang`; B2 a, B34 a),
package-standalone.sh, unpack-toolchain.sh (env.sh's `group_dirs
compilers` already listed `zig`), windows.zig (D6 was PR #19's), the
conda recipe's outputs (the exclusion of `lib/R/bin/toolchain/zig/**`
now guards a directory the conda build never makes), make-wheel.py
(it takes only `usr/` from the tree), compile-tree.sh's rule (zig/ and
flang/ stay out, C12).

#### Phase 5 record: the measurements (2026-10-15)

Sizes (bytes; B13 a: recorded only, no format change). The compilers
archive holds zig/ (19,558 files, 360.4 MB unpacked on linux-64) and
openmp/; the archive's file count is verify-bundle's file-list line.

| platform | compilers | files | build-tools | slim base |
|---|---|---|---|---|
| linux-64 (gamma) | 88,083,009 (.tar.gz) | 19,564 | 155,102 | 63,049,365 |
| osx-arm64 (omicron) | 87,459,159 (.tar.gz) | 19,564 | 130,805 | 57,679,464 |
| osx-64 (omicron, Rosetta) | 91,438,973 (.tar.gz) | 19,564 | 136,407 | about 57 MB |
| win-64 (kappa) | 101,618,280 (.zip) | 19,563 | 5,401,812 | 64,582,740 |
| linux-aarch64 | CI | | | |

The survey's estimates were linux-64 87.1, linux-aarch64 84.1,
osx-arm64 86.5, osx-64 90.4 and win-64 100.3 MB. The minimal
linux-64 base is 51,743,277. win-64's zip is the largest, at 101.6 MB,
under B13's 150 MB mark before flang.

The first C++ compile with an empty zig cache: verify-bundle's new line,
the toolchain pass (TC/zig, a new user's cache under the fresh HOME);
the build pass's line for comparison. That cache is env.sh's, and it is
warm only after an earlier task compiled C++ with it.

| host | TC/zig, empty cache | the build's zig (env.sh's cache) |
|---|---|---|
| linux-64 | 15-18 s, 49 MB, about 3,350 warning lines | 1 s (warm) |
| osx-arm64 | 9-11 s, 68 MB, about 3,420 lines | 9 s, 3,422 lines (cold: a fresh copy); minimal 1 s (warm) |
| osx-64 (Rosetta) | 13 s, 68 MB, 3,440 lines | 15 s, 3,435 lines (cold) |
| win-64 | 46 s, 94 MB, about 3,677 lines | 62 s, 3,668 lines (cold) |

Each first compile builds libc++ into zig's cache, and its warnings
are the libc++ headers' `-Wnullability-completeness` lines. That cost
is zig's, not upstream's: conda-forge's zig pays the same when its
cache is cold (step 3b on kappa, Rcpp's first build: TC/zig 66 s,
conda-forge's 93 s). Pre-seeding stays a later menu.

`pixi run toolchain` (the wheel cached; the task removes and rebuilds
the tree each time): linux-64 5-11 s, osx-arm64 13 s, win-64 49-52 s
(the 19.5k-file install). The first fetch of a wheel: osx-arm64 38 s
(fetch-zig), osx-64 94 s for `toolchain` with its fetch, win-64 within
step 3b's 3 min 37 s `package-toolchain`.

verify-toolchain (wall time):
- Before phase 5, today's tree (no zig/): linux-64 0.8 s batched, 3.3 s
  per file.
- With zig/ (19,567 files): linux-64 6 s (10 s as a pixi task),
  osx-arm64 6 s (task), osx-64 12 s (task), win-64 49 s on the tree the
  build installed and 157 s on the tree unpacked from the zip.
- The old per-file script on a tree with zig/ (linux-64): 11 min.
- win-64 stays well inside toolchain.yaml's 30-minute timeout.

Step 1's binary count (Cg8): the old and the new script agree on the
tree without zig/ on every host: linux-64 1 ELF file (GNU grep and
xargs), osx-arm64 1 Mach-O (BSD grep and xargs), win-64 8 PE files
(MSYS). With zig/ the new count is 2, 2 and 9: zig/zig (zig.exe) is
among them. On the tree without zig/ the new script then stops at its
zig check ("lib/R/bin/toolchain/zig/zig is missing"), as it should.

unpack-toolchain: linux-64 8 s, osx-arm64 6 s, win-64 38 s, all
as pixi tasks. CI's per-leg-kind times (Cg6) come with the PR.

verify-package, per pass (verify-bundle's final line per pass; Cg1):

| host | toolchain pass | build pass | the whole task |
|---|---|---|---|
| linux-64, slim | 73-75 s | 51 s | 278 s |
| linux-64, minimal | 62 s | 40 s | 242 s |
| linux-64, upstream (one zig) | about 72 s | skipped | 220 s |
| osx-arm64, slim | 109 s | 91 s (cold cache) | 302 s |
| osx-arm64, minimal | 90 s | 53 s | 233 s |
| osx-arm64, upstream | 109 s | skipped | 210 s |
| osx-64 (Rosetta), slim | 207 s | 179 s | 570 s |
| win-64, slim | 243 s | 238 s | 12 min |
| win-64, upstream | 246 s | skipped | 8 min |

Against the step-0 baseline (main d11dee1 + phase 4 + SHLIB) on gamma,
the same day, in a scratch copy: its verify-bundle.sh alone took 56 s;
phase 5's took 127 s (73 s and 51 s). On the default legs verify-package
is about 2.3 times as long; the toolchain pass is the slower of the two
because every compile in it starts from an empty zig cache. CI's
"Package + verify" step at ea7e6ee (run 38467545177, the newest
completed build-r run before PR #27; d11dee1's own push run,
38569479149, was cancelled) took: ubuntu-latest 237 s, ubuntu-24.04-arm
293 s, macos-latest 268 s, macos-15-intel 484 s, windows-latest 312 s,
ubuntu-latest minimal 198 s. The upstream legs at 60afeb0 (run
38430385664) took: ubuntu-latest 206 s, macos-latest 258 s,
windows-latest 309 s. The PR's times are compared with these.

CI's toolchain jobs at ea7e6ee (for Cc7): windows-latest 278 s, of which
setup-pixi took 214 s, the tests 21 s, the build and archive 4 s and
verify-toolchain 6 s. The upstream windows-latest job (60afeb0) spent
26 s fetching and unzipping the same wheel in its "Upstream zig" step.
The PR's run gives the new step times.

Not measured separately: the build runner's first build with TC/zig.
It is inside verify-bundle's preflight block, which passed on every host
(`rzig build: tier 1`).

#### Phase 5 review (2026-10-15)

The skeptical review of steps 1 and 2 together (Cg8) ran on gamma's diff
in step 2 (Windows paths, `zig.exe`, quoting, the `set -e` and pipefail
sites); its Windows parts were confirmed by kappa's runs (step 6). An
adversarial review of the six steps then confirmed two findings, both
fixed and rerun on linux-64 (logs in .../phase5/fix/):
- [tests-1] step 4 moved the RZIG_PRINT_ARGV check to `PATH=/usr/bin:/bin`,
  but the unix package compiles run with a PATH whose first entry is the
  env's bin, which holds conda-forge's zig; so nothing showed those
  compiles still run the pass's zig. verify-bundle.sh's unix packages
  block now repeats the dry run under that PATH and requires its first
  word to be `$pass_zig` (find_zig's order, B4). It passed in both passes
  (73 s and 51 s). A negative run: with TC/zig moved aside, the first word
  became the env's zig, so a find_zig change that let PATH win would fail
  the check.
- [tests-2] TODO.md waited on CI for a one-zig run that no CI leg makes
  (upstream-zig.yaml runs linux-64, osx-arm64 and win-64 only), and left
  out osx-64's mixed case, which had passed on omicron. The item now says
  what passed where; the missing one-zig runs on linux-aarch64 and osx-64
  are a "Later" menu and a note under K (a).

One host finding, from kappa's round 1, fixed (logs in .../phase5/rfix1/):
- On Windows, with ZIG_BIN unset, the build pass's label printed
  `ZIG_BIN=/conda_bin/x86_64-w64-mingw32-zig`, the MSYS spelling of
  env.sh's `$ZIG` (env.sh converts only a given ZIG_BIN). The zig handed
  to rzig was already the `cygpath -m` form, so no check was wrong. The
  label now uses `cygpath -m` on Windows; no assertion changed. Not
  taken: env.sh converting `$ZIG` always, which touches about 27 users
  that already convert where a native program needs it. kappa's round 2
  shows `ZIG_BIN=C:/.../Library/bin/x86_64-w64-mingw32-zig.exe` on every
  build-pass line.

#### Phase 5 record: tests on every host (2026-10-15)

pixi.lock was fbb64b7b...a68bb96 at every start and end, on gamma and
in each host's copy but the osx-64 one, which is re-solved on purpose
(below). `pixi lock --check` passes, and every other pixi task ran
`--locked`. The hosts ran copies of the worktree made from its file
list: 233 regular files, checked by sha256 against gamma's manifest at
the start and the end of each chain (the osx-64 copy at its start, before
its platform edit), all OK. No host wrote the worktree. The
worktree's `git diff | sha256sum` was 847ec97b... at step 6's start.
After the hosts' sync, step 6 changed one message in verify-bundle.sh:
the build pass's C++ line said "warm" for a cache that was cold on
omicron and kappa. Gamma's verify-package ran again on step 6's tree.
The review's and the host's fixes came after these runs; the testers'
rounds 1 and 2 on the fixed tree are at the end of this section.
- gamma (linux-64): steps 1-5's chains, with conda-forge's zig and with
  upstream zig (each step's record), and step 6's verify-package on
  step 6's tree (278 s; toolchain pass 75 s, build pass 51 s).
- omicron (macOS 26.4.1, osx-arm64, pixi 0.81.0), copy ~/rz-p5:
  - `rzig-test` with both zigs (151/151 each);
  - `build`, `toolchain`, verify-toolchain, step 1's binary count,
    `package-toolchain`, `unpack-toolchain`, then verify-toolchain on
    the unpacked tree, and verify-package (both passes);
  - `-e minimal build` and verify-package (both passes);
  - wheel (four wheels, macosx_13_0_arm64) and wheel-test (312 s);
  - upstream zig (`ZIG_BIN` = fetch-zig's): `build`, `toolchain`,
    `package-toolchain`, verify-package (the one-zig pass, the build
    pass skipped with its note);
  - conda-package (264 s; r-zig-slim h41cfa24_11, r-zig-compilers and
    r-zig-build-tools h4105b44_11, r-zig-toolchain h0527d79_11, built
    locally as `_11` before the 2026-10-19 decision; the PR keeps 8; the
    four tests; "toolchain tree $PREFIX: nothing to install (the prefix
    is the env)") and conda-consume (43 s).
  - Nothing on macOS asked about the extracted zig: a tar.gz extracted
    by the scripts carries no quarantine attribute. A browser download
    was not tested (Risks).
- omicron, osx-64 under Rosetta (open point K), copy ~/rz-p5-osx64,
  re-solved for osx-64 (its lock 0662b7ae..., scratch only; the
  worktree's lock fbb64b7b... before and after):
  - `rzig-test` (151/151, an x86_64 zig);
  - `toolchain` (it fetched the osx-64 wheel; zig/zig is "Mach-O 64-bit
    executable x86_64" and prints 0.16.0, 26 s on its first run under
    Rosetta), verify-toolchain and `package-toolchain`;
  - `build` (223 s) and verify-package, both passes (570 s).
  - The endpoint agent killed nothing: the first run of upstream's
    unsigned x86_64 zig on omicron passed.
  - A first try ran GNU sed from ~/.pixi/bin with BSD `-i ''`. The
    platform edit failed, and the try was stopped before it did
    anything for osx-64. The copy was cleaned and run again with
    /usr/bin/sed.
- kappa (Windows 11, win-64, pixi 0.81.0), copy C:\Users\admin\rz-p5-3b
  (step 3b's, synced again):
  - `rzig-test` with both zigs (121 pass and 30 skipped each);
  - `build`, `toolchain` from an empty dist/toolchain (49 s) and again
    (52 s), verify-toolchain (49 s), step 1's binary count,
    `package-toolchain`, `unpack-toolchain` (38 s), verify-toolchain on
    the unpacked tree (157 s);
  - verify-package, both passes: in each, syncw (`PKG_LIBS =
    -lsynchronization`) built through rzig build tier 1, imported the
    API set and loaded with PATH = bin\x64 + System32. The no-zig check
    moved `TC/zig/zig.exe` aside;
  - upstream zig: `build`, `toolchain`, `package-toolchain`,
    verify-package (the one-zig pass with syncw; the build pass skipped,
    since `cmp` found the same bytes);
  - conda-package (13 min; r-zig-slim h9490d1a_11, r-zig-compilers and
    r-zig-build-tools hc5b9da2_11, r-zig-toolchain h7b95333_11, built
    locally as `_11` before the 2026-10-19 decision; the PR keeps 8; the
    four tests; the toolchain line names only `binutils/`, "(the prefix
    is the env)") and conda-consume (2 min).
  - Step 4's open Windows questions are answered by these runs:
    `cygpath -m -l`'s `pass_zig` matched both the check line and
    RZIG_PRINT_ARGV's `<TC>/zig\zig.exe`; zig 0.16 put its cache in
    `LOCALAPPDATA\zig`; the baseline-CPU compiles ran a `C:/...zig.exe`
    path under env -i; the build pass's argv matched `cygpath -m "$ZIG"`.
  - Step 3b (before step 4): the `-lmsvcrt` check (open point L) with
    magick and gifski in an extracted bundle (base + both groups,
    ZIG_BIN unset). magick, with Rcpp, magrittr and curl, built and
    rendered an SVG through librsvg. No log names msvcrt. gifski's
    unwinder failure is the open item under "Later".
- CI: not run. Phase 5 is not pushed: the user commits and pushes
  (open point O). The PR's runs go into "Phase 5 record: CI" when they
  exist, with their run IDs, each toolchain leg's time and artifact
  size, windows-latest's toolchain step times (Cc7), the unpack time per
  leg kind (Cg6), and verify-package per pass against the baselines
  above (Cg1).

Round 1 ran after the review's fixes (`git diff` sha256 4783d159...),
round 2 after the host fix (f91d1b59..., the tree handed over). Each
copy matched gamma's 235-file manifest at its chain's start and end,
pixi.lock was fbb64b7b... throughout, and each tester removed its copy
when everything passed (logs in .../phase5/omicron-tester/ and
.../phase5/kappa/, round 2 in kappa/r2/).
- omicron, osx-arm64, round 1 (35 min, every task passed, nothing
  killed by the endpoint agent):
  - `rzig-test` with both zigs, `toolchain-test`, `fetch-zig` (58 s on
    a first fetch), `build`, verify-tree, `toolchain` (6 s),
    verify-toolchain (6 s, BSD tools: 19,547 copies, 2 Mach-O files,
    zig/zig among them), step 1's binary count (1 and 1 on the tree
    without zig/), `package-toolchain` (87,457,796 B, 20,865 members),
    `unpack-toolchain` and verify-toolchain on the result, contract,
    pkg-parity, wheel and wheel-test (no `bin/toolchain/zig/` in any
    wheel, B30);
  - verify-package, slim: toolchain pass 109 s (first C++ compile 10 s,
    68 MB), build pass 72 s (env.sh's cache warm, 1 s); minimal 90 s and
    52 s; upstream, the one-zig pass 107 s, the build pass skipped. In
    every pass tests-1's new check ran ("with the env's bin on PATH too,
    the bundle's compilers run the ... pass's zig");
  - conda-package (`_11`, built locally as `_11` before the 2026-10-19
    decision; the PR keeps 8; r-zig-compilers 45 KB, no zig,
    conda-forge's zig its dependency, B30) and conda-consume;
  - Gatekeeper: TC/zig/zig is ad-hoc linker-signed and carries only
    `com.apple.provenance`, no quarantine; `spctl` says "rejected" (not
    notarized) yet it runs with no prompt;
  - the first tier-1 install with TC/zig, by hand (base + compilers,
    env -i, a fresh HOME): a plain C package in 15 s with empty caches
    (rzig's 19 MB, zig's 47 MB), 1 s the second time.
- kappa, win-64, round 1 (every task passed): `rzig-test` with both
  zigs, `fetch-zig`, `build`, `toolchain` (2 min 48 s on an empty tree,
  52 s again), verify-toolchain (48 s; the old per-file script took
  1,934 s on the same tree, over toolchain.yaml's 30 minutes), step 1's
  binary count (8 and 8; 9 with zig.exe), verify-tree, smoke,
  `package-toolchain` (101,618,280 B), `unpack-toolchain` (37 s) and
  verify-toolchain on the result (2 min 36 s), verify-package (toolchain
  pass 244 s, first C++ compile 46 s, 94 MB; build pass 249 s, 67 s on
  env.sh's cache; syncw in both), magick in an extracted bundle with
  ZIG_BIN unset (179 s, an SVG through librsvg, no msvcrt), compile-tree
  (no zig/), contract, pkg-parity, hermetic, the upstream chain (one-zig
  pass 243 s, the build pass skipped), conda-package (`_11`, built
  locally as `_11` before the 2026-10-19 decision; the PR keeps 8, no
  zig/, no download, 12 min 39 s) and conda-consume (the new standalone
  line names R-4.6.1-win-64-compilers.zip). Its one finding, the build
  pass's label, is in "Phase 5 review".
- kappa, win-64, round 2 (the label fix; verify-bundle.sh was the only
  file changed since round 1): `build`, `toolchain`, `package-toolchain`
  and verify-package on both legs passed. The conda leg's build-pass
  lines (header, check mode, syncw, the final line) now name
  `ZIG_BIN=C:/.../x86_64-w64-mingw32-zig.exe`; toolchain pass 245 s,
  build pass 236 s. The upstream leg's one-zig pass 248 s, no build
  pass. The other tasks do not run verify-bundle.sh and were not rerun.
  omicron had no round 2: the fix only changes a Windows branch, and
  gamma's build pass ran again after it (51 s, the same label).

Two observations, no failures: the archives are not byte-identical
across builds of the same tree (osx-arm64's compilers 87,459,159 and
87,457,796 B; win-64's slim zip 64,582,740, 64,582,695 and 64,582,494 B,
three sha256s), since tar and zip record mtimes; and package-standalone's
"== done:" size is `du`'s (97M on APFS and 45M on gamma's compressed
filesystem for an 87-88 MB file), so the sizes here come from `ls -l`.

#### Phase 5 record: the mixed case and the facts the critiques added

The mixed case (open point R, (a): recorded, no change):
- CC_VER: `R_compiled_by()` and R CMD INSTALL's "using C compiler" line
  name conda-forge's clang 21.1.8 when TC/zig (clang 21.1.0) compiles
  the package. Cosmetic; TODO's "Later" item (build.zig fills CC_VER
  from the zig that builds R) covers it.
- An inherited ZIG_LIB_DIR reaches TC/zig too; upstream zig needs no
  libc++ mirror (it links its own static libc++).
- The shared build runner (PR #27) keys on the zig's path: each place a
  compilers archive is extracted builds its own runner (about 45 MB, 3-13
  s), swept after 7 days idle; conda-forge's and upstream zig never share
  one. rzig build's tiers and every compile step they run find the same
  zig (find_zig in each), and tier 2 compiles with that zig's own lib
  dir.

The facts the critiques added:
- The build pass repeats every zig-independent check but scenario 1 and
  the no-zig check (S), so verify-package nearly doubles on the default
  legs; the per-pass times are in "the measurements".
- Every build-r and stress leg downloads and unpacks the toolchain
  artifact, now with zig/, though only verify-package reads zig/ (Cg6).
  The dev chains (contract, pkg-parity, stress) reach PyPI once per
  platform for it, and `toolchain` needs the network once (README's dev
  note).
- After phase 5 build.yaml's and upstream-zig.yaml's toolchain
  artifacts carry the same TC/zig, so the upstream-zig run builds the
  same tree twice (Cg9).
- The licence set (Cc5, Cg2): the licence texts of the bundled
  components are in `zig/LICENSES/ziglang/` as upstream ships them,
  LLVM's included: libcxx's, libcxxabi's and libunwind's `LICENSE.TXT`
  are the LLVM project's Apache-2.0 WITH LLVM-exception text, which
  covers LLVM, Clang and LLD linked into the binary, libtsan
  (compiler-rt) and clang's resource headers. What is missing is
  upstream's attribution (no statement that the binary contains LLVM),
  not a text, plus Apple's SDK headers and libSystem.tbd (APSL/BSD) and
  the NetBSD and OpenBSD headers, which ship with no text of their own.
  SOURCES' `license: MIT` is the wheel's METADATA `License-Expression`.
  B33 covers the base's runtime files only, so the groups' licence
  completeness is a "Later" menu, with phase 6's licence review.

### Phase 6 — Fortran in the compilers group

Goal: flang's compile set in `TC/flang/`, and zig-fc links everything
through zig.

Decisions (answered): B9, B13 (revisit), B29 (a: no Fortran on PyPI),
B44 (Fortran must pass on every OS).

Steps (prototype first, on linux-64, osx-arm64, osx-64 and win-64):
- zig-fc sends every link through zig (a call with sources and a link
  becomes `flang -c` per source plus the zig link); unit tests; a real
  configure that probes `$FC` passes in the standalone tree and in a
  conda env.
- zig-fc passes `-fintrinsic-modules-path` from flang's own location;
  harmless beside a conda env's flang.cfg; where the triple comes from.
- rzig's runtime lookup finds the archive under `TC/flang/`; on Windows
  without `Library/`; the driver works as the single file `flang`.
- kappa: a Fortran package builds and loads without `-lc++` (flang-rt-zig
  10's archive checked first); omicron: R builds without
  linkFortranRt's `link_libcpp`.
- If an OS's prototype fails, the cause is fixed together with
  flang-pixi (flang-zig), and the prototype runs again (B44). Every OS
  ships `TC/flang/`; phase 6 does not finish without all of them.

Then:
- The toolchain step installs the set from the env (B9 a) into
  `TC/flang/` (flang-zig's layout, no `Library/`, no flang.cfg, no lld,
  the driver once, no linux module-directory symlink), `flang/SOURCES`
  from conda-meta, verify-toolchain checks each copy against
  `paths_data` (verify-tree checks the R trees, which hold no flang/;
  phase 3 split the two).
- The carve script's cross-check, once.
- `-lc++` and `link_libcpp` dropped where those runs passed.
- Compression revisited with the measured compilers archives (B13).

Tests: scenario 2 with no flang on PATH and no flang.cfg: a
derived-type module, a USE_FC_TO_LINK package, `use omp_lib` on two
threads, a configure that links with `$FC`; RZIG_PRINT_ARGV shows
`TC/flang/bin/flang` compiling and zig linking. Every OS (all five
platforms in CI), each one passing.

**Status (2026-10-17): phase 6 pending CI.** Steps 1 to 8 are done in
the worktree feat-standalone-phase6 (branch feat-standalone-phase6:
main d11dee1 plus phase 4's, the R CMD SHLIB routing's and phase 5's
uncommitted changes), not committed. Every test passes by hand on
linux-64 (gamma, both zigs), osx-arm64 (omicron, both zigs) and win-64
(kappa, both zigs); the standalone runs have no flang on PATH and no
cfg, so TC/flang is the only flang (B44 met on those three). The host
stage took two rounds: round 1 found two test bugs and no product bug
(the kit's five.sh grepped linux's `ld.lld` on macOS;
recipe/test-compilers.R expected zig's file to be named `zig` on
win-64), both were fixed, and round 2 passed on both hosts ("Phase 6
record: tests on every host"). All three K drops stay: macOS
and Windows pass without `-lc++` and `link_libcpp`. kappa's R
`untar(..., tar = "internal")` reads the compilers `.tar.xz`, so L
holds on Windows. No flang-pixi change is needed. osx-64 under Rosetta
on omicron did not run in this phase (an open item below). CI has not
run: the branch is not pushed. linux-aarch64 (its only B44 run),
native osx-64 (macos-15-intel) and the `upstream-zig` label run happen
only after the user's push (PHASE6 open point T, Cg3), and the PR does
not merge before they pass. The work follows the
reviewed implementation plan, copied here as
phase6/PHASE6-IMPLEMENTATION.md with its critique phase6/CRITIQUE.md
(cited below as PHASE6 <section>, Cc<n> and Cg<n>), and the user's
answers to its open points ("Phase 6: the user's answers"). The build
number stays 8 (the user's decision of 2026-10-19, B14's amendment; it
was 12, the number after phase 5's 11, B14 a, open point R), and phase
6 publishes with phase 7's bump: conda's and PyPI's contents change (rzig on every OS; Makeconf.win's
FLIBS and the links of libR, Rblas and Rlapack on macOS and Windows).
pixi.lock is unchanged (sha256 fbb64b7b...a68bb96); phase 6 changes no
dependency. Merge order: phase 4's PR, SHLIB's, phase 5's, then phase
6's, which is `phase6-only.diff` against those three (open point S).
Next: the user commits and opens the PR with
`phase6/handover/commands.sh` (the core tier and conda-package first,
then the `full-ci` and `upstream-zig` labels); CI's numbers go into a
new "Phase 6 record: CI".

#### Phase 6: the user's answers (2026-10-16)

The user, 2026-10-16: "Keep going", after "Follow with the
recommended". Every open point of PHASE6 section 11 takes its ★ option;
each is recorded here as answered that way, the options not taken named
after it.
- A (a): the driver is one renamed copy (`bin/flang-23`, win-64
  `Library/bin/flang.exe`, to `flang/bin/flang[.exe]`); the modules and
  the runtime are record-driven trees: every `hardlink` file of
  flang-rt-zig's record under `lib/clang/23/finclude/flang/`, and the
  file `libflang_rt.runtime.a` under `lib/clang/23/lib/`, each installed
  at its path less `Library/` and checked by `conda.find`. Not taken:
  (b) fixed lists per platform.
- A2 (a): `llvm_major = "23"` is a constant beside the flang directory
  in the toolchain build; rzig's `modulesDir` and R's findFlangRt scan,
  since they must find whatever flang the env or PATH has. Not taken:
  (b) a scan in the toolchain build too.
- B (a): win-64 keeps both module directories (`x86_64-w64-mingw32`,
  `x86_64-w64-windows-gnu`; 263 KB). The surveys split (as phase 5's
  Cg5): the tree survey and this plan's table ("The toolchain groups")
  said keep both, the rzig survey one. (a) is a by-product of A (a),
  with no rule (Cg4), and was taken for simplicity. Not taken: (b) a
  rule keeping only the first.
- C (a): no `flang.cfg` in TC/flang; zig-fc passes the modules path.
  Not taken: (b) flang-zig's `flang-compile.cfg` copied as
  `flang/bin/flang.cfg`.
- D (a): the modules path comes from flang's real path, `\` turned
  into `/`, `bin/<file>` cut as strings (no `..`, Cc3):
  `<tree>/lib/clang/<v>/finclude/flang/<t>`, `<v>` the first entry in
  byte order holding `finclude/flang/`, `<t>` the first entry named for
  rzig's CPU (`x86_64-`, `aarch64-`/`arm64-`), else the first in byte
  order (Cc8, Cg8). It goes last on every call that reads Fortran
  source and is no probe (`-c`, `-S`, `-E`, `-fsyntax-only`, the split's
  compiles; Cc9), beside a conda env's cfg too. Not taken: (b)
  `-print-resource-dir` on every compile, (c) a triple constant in
  rzig, (d) only without a cfg.
- E (a): every link goes through zig. A call with Fortran sources is
  split: a flang compile per source into `<tmp>/rzig-fc-<random>/`,
  then the zig link with each source replaced by its object; spawned
  and waited on every OS; the first failing exit (128+n for a signal on
  unix); the directory removed on every path (Cc15). Two measured
  refusal lists (Cc1): `link_refused` (what zig cc refuses) and
  `compile_refused` (the link-only options flang refuses). Each grows
  only by a host's measured refusal, with its measurement. Not taken:
  (b) a whitelist of link options, (c) executables and mixed calls kept
  flang's.
- F (a), as amended (Cc7): each input is classified by the `-x` in
  force, else its extension; a C-family source stays on zig's line
  (`-x <lang> <src> -x none` when only an `-x` classified it); no other
  `-x` reaches the link. Not taken: (a0) the planner's separate zig-cc
  compile step for a C source, (b) calls with `-x` kept flang's.
- G (a): RZIG_PRINT_ARGV prints each step's argv with a line `&&`
  between steps, `ZIG_LIB_DIR=` just before the first zig block (Cc6);
  RZIG_TRACE one line per step; a dry run's directory is
  `<tmp>/rzig-fc-dryrun`, not created. Not taken: (b) the link only.
- H (a): flang/'s SOURCES says `feedstock: unknown` (flang-pixi's
  recipes record no repository); an open item for the user, not filed.
  Not taken: (b) an override in build.zig.
- I (a): verify-toolchain checks `flang/bin/flang --version` against
  SOURCES' flang-zig `version:` and that the closures block counted the
  driver (phase 5's Cg8 shape). Not taken: (b) presence only.
- J (a): flang-pixi's carve script ran once, by hand, as the
  cross-check ("the per-OS facts" below). Not taken: (b) a script in
  the repo (B9 says no).
- K (a): `-lc++` and `link_libcpp` are dropped where step 3's runs
  passed, as one recorded patch (`k-drops.diff`, Cc14). K2 (a): the
  macOS drop stays when omicron passes, with libR's exported `std::`
  count before and after recorded. Not taken: (b) only Windows'
  `-lc++`, (c) keep all three; K2 (b) keep `link_libcpp` on macOS
  whenever libR exported a libc++ symbol. How they landed: below
  ("what changed") and in the host section.
- L (a), as amended (Cg2): the measured linux-64 `.tar.gz` was over
  150 MB, so the compilers archive is `.tar.xz` on every platform,
  Windows included with no condition; the base and build-tools keep
  `.tar.gz`/`.zip`; the rule is per group, never per OS. On Windows the
  README names R's `untar(..., tar = "internal")` first. kappa's
  `untar()` failing would stop the work, not switch win-64 back. Not
  taken: (a0) the planner's per-OS fallback, Cc5's variant (`.zip`
  where the oldest Windows' tar has no liblzma), (b) zstd, (c) xz on
  unix only.
- M (a): the standalone line reads `extract
  R-<ver>-<plat>-compilers.tar.xz where you extracted R (zig 0.16,
  flang and the OpenMP files)`; the first line and the pip line are
  unchanged. Not taken: (b) flang's version in the text.
- N (a): verify-bundle's no-flang checks move `TC/flang/bin/flang[.exe]`
  aside into VERIFY_DIR and back, restored on every exit path. Not
  taken: (b) a directory without flang/.
- O (a): TC/flang in both verify-bundle passes; the env's flang with
  its cfg keeps its coverage through contract, pkg-parity, stress and
  the conda tests. Not taken: (b) the build pass on the env's flang.
- P (a): recipe/test-compilers.R gains a `$FC` probe (a program and a
  derived-type module, compiled, linked and run) with the env's flang
  and cfg. Not taken: (b) the dev env's step 1 run only.
- Q (a): r-zig-compilers keeps its `lld-zig ==23.1.1 *_5` pin, though
  nothing of ours runs lld-zig now (a recipe comment says so). Not
  taken: (b) drop it, a dependency change.
- R (a): build 12. If another build publishes to universe first, the
  one after universe's newest. (Superseded 2026-10-19: no bump in phase
  6, the number stays 8; B14's amendment.)
- S (a): `phase6-only.diff` against the step-0 baseline (main d11dee1
  + phase5-base.diff + the baseline's untracked files), checked by
  applying it to a second copy; four PRs in order. Not taken: (b) the
  whole worktree diff for the user to split.
- T (a): CI's ubuntu-24.04-arm leg under `full-ci` is linux-aarch64's
  B44 run, after gamma's non-gating cross pre-check (Cg3). Not taken:
  (b) the aarch64 tree checked on gamma only.
- U (a): B40's Fortran limit is accepted and documented: `omp_lib.mod`,
  `omp_lib_kinds.mod` and `omp_lib.h` sit in flang/'s one module
  directory, so on minimal `use omp_lib` compiles and its link fails on
  the `omp_*`/`__kmpc_*` symbols; one minimal verify-bundle assertion
  (the linker's own undefined-symbol message). Not taken: (b) no
  modules flag on a base without libomp, (c) a second module directory
  without the OpenMP files.
- V (a): `ISO_Fortran_binding.h` is left out of flang/, the same on
  every channel; it comes back with an include rule if a package needs
  it. Not taken: (b) copied, with rzig adding it to C compiles.
- W (a): the toolchain build reads the trees' records in one pass with
  a separator-free needle per tree (`libflang_rt.runtime.a"`, `flang`),
  so `conda.find`'s two-owner check sees a clobber. Not taken: (b) a
  second pass by basename, (c) a `"name": "<package>"` needle.
- X (a): the toolchain summary lists packages in copy order (`flang/
  (flang-zig, flang-rt-zig)`). Not taken: (b) sorted names.

#### Phase 6 record: what changed (2026-10-16)

`phase6-only.diff`: 29 files against the phase 5 baseline (the two new
records under phase6/ included).
- zigbuild/tools/rzig/fortran.zig (D, E, F, G): a call is one of three
  kinds: `.flang` (compiles, probes, no input), `.link` (objects or
  C-family sources only, through zig cc as zig-cc links, executables
  included, with the runtime) or `.split` (a Fortran source plus a
  link: one flang step per Fortran source in the caller's order, `flang
  <floor> <compile args> -Qunused-arguments -c [-x lang] <src> -o
  <tmp>/<n>-<stem>.o -fintrinsic-modules-path <dir>`, then one zig link).
  `link_refused` holds `-J <dir>`, `-Mfixed`, `-Mfree`, `-Mextend` and
  `-fno-fortran-main`; `compile_refused` the 31 options CA measured plus
  `-unexported_symbols_list`, with `-F` in both forms. One `drop` helper
  takes each option with its value. The split's temporary directory is
  TMPDIR's, else /tmp; on Windows TEMP, then TMP, else the output's
  directory (never MSYS' TMPDIR). The module doc says why zig links
  everything, replacing F3c's "a mixed call stays flang's"; split()'s
  doc says configure's `-v` parse reads zig's link line (`ld.lld`, on
  macOS `zig ld`). `flibs` on
  Windows is `-lflang_rt.runtime` alone (K).
- flang_rt.zig: `modulesDir` (D; no process runs); `globDirs` made
  public. cmdline.zig: `takes_value` gains `-undefined`, `-force_load`,
  `-multiply_defined`, `-Xflang`, `-J`, `-module-dir` and
  `-fintrinsic-modules-path` (Cc2); new `isFortran`, `xLang` and
  `isFortranLang`. Ctx.zig: a command of several steps (`.steps`) and a
  `dry_run` field. main.zig: commands are a list of blocks; `runSteps`
  spawns and waits for each, stops at the first failure and removes the
  directory and the discard on every path; single commands still exec
  on unix; with no zig the run exits 127 before any step. compiler.zig:
  its Windows FLIBS test without `-lc++` (K).
- zigbuild/tools/rzig/groups.zig (L, M): `archiveExt` (compilers
  `.tar.xz` everywhere; build-tools `.zip` on Windows, `.tar.gz`
  elsewhere), the standalone line above, the header naming flang (B9)
  in the compilers group. parity-test.sh: the anchored grep for the new
  line; the two Windows FLIBS cases without `-lc++`.
- zigbuild/toolchain/build.zig (A, A2, B, C, W, X): `Tree{package,
  from, name?}` and `Dir.trees`; `flangDir(prefix, driver)` written
  once (Cg6), listed first in unix_dirs and windows_dirs; trees are
  skipped when the prefix is the env (Cc4), before any record is read;
  an empty tree stops the build with "<pkg>'s record lists no <name>
  under <dir>"; one `copyOf` helper for copies and trees; the header
  table gains flang/ ("no cfg, no lld, no ISO_Fortran_binding.h", V).
  conda.zig: `Record.Path.path_type`, `under` (a package's `hardlink`
  paths under a directory, `\` read as `/`) and `inDir` (drops a
  leading `Library/`), with three tests (the linux softlinks left out,
  win-64's twins and `\` paths, a second owner gives TwoOwners).
- scripts/verify-toolchain.sh (I): flang's driver tracked in the
  closures (`flang_exe`, `.exe` on Windows) with the positive check;
  `flang --version` against SOURCES' flang-zig `version:`; the header
  notes the Cg10 build paths.
- Compression (L): env.sh's `group_ext` (compilers `tar.xz`, the rest
  `$ARCHIVE_EXT`, no OS test; Cg11, groups.zig the reference);
  package-standalone.sh's `archive()` picks zip, xz (`tar -cf - | xz -9
  -T0`) or gz from the artifact's extension; verify-helpers.sh's
  `archive_files` and `extract_archive` read `.tar.xz` with the env's
  xz on every OS; unpack-toolchain.sh and verify-bundle.sh name
  archives with `group_ext`. package-standalone.sh's "== done:" line
  prints each archive's size in bytes (`wc -c`), where `du -h` printed
  the space on disk (512 for a fresh file on gamma's ZFS; fixer,
  2026-10-16).
- R's build.zig (K): Makeconf.win's `FLIBS = -lflang_rt.runtime`;
  linkFortranRt without `link_libcpp` on macOS and Windows, its doc
  giving the measurement (the runtime's only C++-ABI reference is
  `__cxa_atexit`, from libc or libSystem); the FC comment and
  installWindowsCompilerContract's doc no longer say flang cannot be
  copied (TC/flang is a copy that works; conda's flang is the env's).
  linux's libR, libRblas, libRlapack and R binary are byte-identical
  before and after.
- scripts/verify-bundle.sh (N, O, U; Cc3, Cc6, Cc9): `pass_flang`
  (`TC/flang/bin/flang[.exe]`, `pwd -P` / `cygpath -m -l`) in both
  passes, and the archive named when it is missing; no `*.cfg` in the
  extracted tree and no flang on the check mode's PATH; the check mode
  names "flang at $pass_flang"; the first Fortran compile (R CMD SHLIB
  of a derived-type module across two files, rzig build with no make,
  PATH the tree's bin, a fresh HOME) timed cold and warm; RZIG_PRINT_ARGV
  of `-c` (flang first, the modules path under TC/flang, physical, no
  `..`) and of `-o conftest conftest.f` (two blocks, `&&`, zig linking
  TC/flang's runtime); `$FC -E` of a `#include "omp_lib.h"` source
  naming exactly the modules directory's file, `$FC -c` of a Fortran
  `INCLUDE 'omp_lib.h'`; the `fdt` package (derived-type module, no
  Makevars, rzig build tier 1); `fcconf` (one configure and
  configure.win script: `R CMD config FC`, conftest compiled, linked,
  run and linked with `-v`); under the package PATH (the env's bin with
  its flang and cfg first), zig-fc still runs TC/flang (the rz/rf dry
  runs and the fs build); fl, fcconf, fomp and fompfc build with no
  flang on PATH and no cfg, PATH the env's make alone, linked, then
  /usr/bin:/bin (fixer, 2026-10-17: they had run under the package
  PATH; default both passes, minimal and upstream pass again); the no-flang
  checks with the driver moved aside (`flang_aside`, `flang_back`, the
  EXIT trap); minimal's U assertion; the Windows dry run with TC/flang's
  runtime and no `-lc++`. The `fc_dir` variable and the Windows copy of
  flang.exe, flang-new.exe, the cfg and the runtime are gone. Scenario 1
  checks that the compilers text names the extracted archive.
- Docs and comments: README (the compilers bullet: `.tar.xz`, about
  95 MB on linux-64, zig 0.16, flang 23.1.1 and OpenMP's headers; one
  bare-driver sentence for every OS; SOURCES naming flang-pixi's
  packages; `tar -xJf` and, on Windows, `untar()` first, then
  System32's tar where `tar --version` lists liblzma; minimal's
  `use omp_lib` limit, U); scripts/env.sh, compile-tree.sh (zig/ and
  flang/ stay out, C12), contract-test.sh; toolchain.yaml's header and
  upload comment; pixi.toml's toolchain and package-toolchain comments
  (comments only: no table changed, `pixi lock --check` passes).
- recipe/recipe.yaml: `number: 12` with its 11 → 12 history entry
  (2026-10-19: back to 8, with one "8 stays" line for phases 4 to 6;
  B14's amendment); the lld-zig pin's comment (Q). recipe/test-compilers.R (P): Makeconf's FC
  is zig-fc; a dry run of `zig-fc -o p m.f90 u.f90` gives three blocks
  (two flang compiles with the modules flag, then the link by the same
  zig that `zig-fc --rzig-check=fortran` reports, compared as paths:
  on win-64 conda-forge's zig is `x86_64-w64-mingw32-zig.exe`, since
  its `zig` is a .bat, find_zig.zig; host fix, 2026-10-17, after kappa's
  round 1 failed on a check of the name `zig`); conftest and a
  derived-type module program are linked and run ("ok"); no
  `rzig-fc-*` is left in the probe's TMPDIR. It reads FC from Makeconf,
  not `R CMD config FC`, since r-zig-compilers alone has no make and
  patch 0010 stops R CMD config with 127 there.
- wheel-test.sh greps "flang and the OpenMP files" and keeps the pip
  line's grep (B29 a: PyPI has no Fortran).

What did not change: rzig's flang lookup (`flang_rt.flang` already looks
in `TC/flang/bin` first, and `-print-resource-dir` gives
`TC/flang/lib/clang/23`); conda's recipe outputs (the conda build's
tree is its env, where flang/ is skipped, so no package holds
`bin/toolchain/flang`); make-wheel.py and the PyPI text (no Fortran);
compile-tree.sh's rule; pixi.lock and every dependency table.

#### Phase 6 record: the measurements (2026-10-16/17: linux-64, osx-arm64, win-64)

The compilers archive with flang/ (B13, L). TC/flang is 23 files,
210,055,043 bytes unpacked on linux-64 (driver, 18 module files in one
directory, the runtime, two licences, SOURCES); 23 files, 143,977,601
bytes on osx-arm64 (module directory `arm64-apple-darwin20.0.0`); 41
files, 182 MB on win-64 (36 module files in the two twins).

| platform | `.tar.gz` / `.zip` | `.tar.xz` (`-9 -T0`) | members |
|---|---|---|---|
| linux-64 (gamma) | 150,809,244 (.tar.gz, 29 s) | 95,251,492-95,533,632 (103-104 s) | 19,587 files |
| linux-aarch64 | CI | CI | |
| osx-arm64 (omicron) | 132,668,316 (gzip -6 of the same tar stream) | 79,145,836-79,158,960 (66 s) | 20,903 entries, 38 under flang/ |
| osx-64 | not run (CI's macos-15-intel) | not run | |
| win-64 (kappa) | 160,012,809 (.zip, `zip -qr`, 26.4 s) | 92,652,560-92,657,048 (96.4 s with build-tools' zip) | 19,604 files |

ST's estimates were gzip/zip 150.8, 144.4, 132.7, 142.1 and 160.0 MB
and xz 78-95 MB. linux-64's gzip archive measured 150.8 MB, over B13's
150 MB, which decided L. The two xz sizes are two builds of the same
tree (tar records mtimes). The base and build-tools archives keep their
formats: slim base 63,084,045-63,084,785 B, minimal 51,820,204 B,
build-tools 155,101 B.

xz's cost on gamma (16 threads): package-toolchain 103-104 s against
29 s with gzip; unpack-toolchain 9.3 s (phase 5's gzip: 8 s); `xz -dc |
tar -tf -` of the archive 2.0 s. omicron: package-toolchain 66 s in
all, `xz -dc` 2 s, unpack-toolchain 7 s. kappa: package-toolchain's
archive step 96.4 s, `xz -dc` 2.4 s, unpack-toolchain 19 s.

The Windows readers (L): System32's `tar.exe` on kappa (Windows
10.0.22621.4317, Windows 11 22H2) is bsdtar 3.7.2 with liblzma 5.4.3:
`-tf` 5.9 s, `-xf` 12.8 s. R's `untar(..., tar = "internal")` read the
whole archive in 66.7 s (65.45 s elapsed), all 19,604 files, the same
bytes as tar.exe's tree. macOS's `/usr/bin/tar` (bsdtar 3.5.3, liblzma
5.4.3) reads it too.

The first Fortran compile with TC/flang only (verify-bundle's line: R
CMD SHLIB of a derived-type module, rzig build, no make, a new user's
empty zig cache):

| leg | toolchain pass (TC/zig, empty cache) | build pass (env.sh's cache) |
|---|---|---|
| linux-64 slim | 8-9 s, zig's cache then 44 MB; warm 0 s | 6 s; warm 1 s |
| linux-64 minimal | 9 s, 44 MB; warm 0 s | 6 s; warm 1 s |
| linux-64 upstream (one zig) | 8 s, 44 MB | skipped |
| osx-arm64 slim | 10 s, 43 MB; warm 1 s | 13-14 s; warm 0-1 s |
| osx-arm64 minimal | | 10 s |
| osx-arm64 upstream (one zig) | 10 s; warm 1 s | skipped |
| win-64 slim | 39 s, 55 MB; warm 1 s | 50 s |

The first C++ compile stays 15 s and 49 MB on linux-64 (omicron 12 s
and 68 MB, the build pass 11 s; kappa 49 s), so a Fortran-only
package pays about half of the C++ first-compile cost on linux-64 and
about four fifths of it on macOS and Windows. kappa's bundle run:
conftest.exe 28.0 s cold, 0.3 s warm. On the hosts the build pass's
caches were cold too (each copy had its own), so its first C++ compile
prints about 3,400 warning lines like the toolchain pass's (gamma's
warm build pass: 0); not a change.

verify-toolchain with flang/ (19,590 files): 23-24 s as a pixi task on
gamma (phase 5: 10 s); the closures block counts 3 ELF files (phase
5: 2; the new one is flang/bin/flang). omicron 8 s (19,590 files);
kappa 1m30s on the built tree and 3m24s on the unpacked one (19,621
files, 10 PE closures).

verify-package per pass (verify-bundle's final line per pass):

| leg | toolchain pass | build pass | whole task |
|---|---|---|---|
| linux-64 slim | 86-88 s | 62-64 s | 307 s |
| linux-64 minimal | 77 s | 52 s | |
| linux-64 upstream (one zig) | 87 s | skipped | |
| osx-arm64 slim | 135 s | 113 s | 349-351 s |
| osx-arm64 minimal | 115 s | 73 s | |
| osx-arm64 upstream (one zig) | 132 s | skipped | 232 s |
| win-64 slim | 275 s | 256 s | 12m55s with `package` |
| win-64 upstream (one zig) | 276 s | skipped | 8m40s |

Phase 5's were 73-75 s and 51 s (278 s), minimal 62 s and 40 s,
upstream about 72 s: phase 6's Fortran blocks add about 11-15 s per
pass on linux-64. omicron's phase 5 passes were 107 s and 72 s,
minimal 90 s and 52 s, upstream 107 s: about 20-40 s more per pass;
kappa's whole task was 12m39s in phase 5.

The rest of section 7's entries are in "the per-OS facts" and "tests
on every host" below. CI's figures (linux-aarch64, macos-15-intel,
windows-latest) come with the PR.

#### Phase 6 review (2026-10-16)

Each change over about 200 lines had a skeptical review of its diff
before its tests:
- Step 1 (the 1,000-line zig-fc diff): exec against spawn, every exit
  path's cleanup of the temporary directory and the discard, Windows
  paths and `.exe`, the import-library discard, a missing `-o`,
  duplicate sources and base names, options with values on both lists,
  where `ZIG_LIB_DIR=` prints. rzig also cross-compiles for
  x86_64-windows-gnu, aarch64-macos, x86_64-macos and
  aarch64-linux-musl.
- Step 6 (verify-bundle.sh, 524 lines): every former `fc_dir` site and
  the Windows copy are gone, every `flang_aside` has its `flang_back`
  and the EXIT trap restores the driver, `cygpath -m -l`, `flang.exe`
  through `$exe`, `\` → `/` with lower-cased comparisons, `tr -s` for
  `#line`'s `\\`, no `grep -q` after `tr` (SIGPIPE), nothing dropped
  from SHLIB's and phase 5's blocks.

What the implementation corrected in the plan:
- flang 23.1.1's `-E` does not expand a Fortran `INCLUDE` line: it
  keeps the line for the compile, and exits 0 even when the file does
  not exist. Only a cpp `#include "omp_lib.h"` is expanded under `-E`,
  through the intrinsic modules path. So Cc9's "`-E` of a file with
  `include 'omp_lib.h'` fails on macOS without the flag" holds for
  `#include`; verify-bundle checks `#include` with `-E` and `INCLUDE`
  with `-c`. The flag on `-E` stays right.
- flang 23 also refuses `-Mfree`, `-Mfixed`, `-Mextend` and
  `-fno-fortran-main` on its own compile; they stay on `link_refused`
  only, for links of objects (`link_refused`'s comment).
- verify-bundle's comment "minimal empties FLIBS" was stale: minimal's
  Makeconf has `FLIBS = -lflang_rt.runtime -lm` and an empty
  `SHLIB_OPENMP_FFLAGS`, so every Fortran check but OpenMP runs on
  minimal.
- A standalone executable linked with `-fopenmp` needs the base's
  `lib/` on the loader path (no rpath outside conda), as zig-cc's
  executables do; package libraries R loads are fine, so verify-bundle
  tests OpenMP Fortran through R.

#### Phase 6 record: tests on every host (2026-10-16/17)

gamma (linux-64; the implementer, who owns `dist/`): pixi.lock was
fbb64b7b...a68bb96 at every step's start and end, `pixi lock --check`
passes (the env was installed with `--locked` in step 0), and every
pixi task ran with PIXI_CACHE_DIR=.../pixi-cache-p6 and TMPDIR under
`phase6/<step>/` (logs there). `/` held 7.2-7.4 GB free (stop line
6 GB); every output went to /data.
- Steps 1-5: `rzig-test` with both zigs (162/162 at the end; parity
  125 identical, 59 identical but for rzig's own additions, 34
  deliberate, 0 failed); `toolchain-test` with both zigs; `toolchain`
  with both zigs, byte-identical trees; verify-toolchain (19,590 files,
  `flang verified: ... 23.1.1`) and its seven negative cases (a changed
  module, the runtime missing, a stray `bin/flang.cfg`, a script as the
  driver, an ELF printing 99.0.0, the driver missing, no `version:`
  line); the six two-owner and empty-tree fixtures through the real
  build; the fake-env conda run ("nothing to install (the prefix is the
  env)", nothing written); `package-toolchain`, `unpack-toolchain` and
  verify-toolchain on the unpacked tree; `build`, verify-tree, smoke and
  contract after K's drops (linux's libR unchanged).
- Step 3's bundle (base, compilers and build-tools extracted, `env -i`,
  `PATH=/usr/bin:/bin`, ZIG_BIN unset, no flang on PATH, no `*.cfg`):
  TC/flang reports 23.1.1 with `-print-resource-dir` under the tree;
  `flang -### -c` names only paths under the tree; the five zig-fc
  calls (conftest, `-v` with zig's ld.lld line, a derived-type module
  `.so` loaded by R, `use omp_lib` on two threads in an executable and
  in a `.so` R loads, a failing compile leaving nothing); R CMD INSTALL
  through rzig build tier 1 of dtmod, fcl (USE_FC_TO_LINK), fomp and
  fompfc (two threads), quadprog 1.5-8, Rcpp 1.1.2 and minqa 1.2.8.
- Step 6: verify-package, both passes, with conda-forge's zig; the
  one-zig pass with upstream zig; minimal's both passes with the U
  assertion ("ld.lld: error: undefined symbol: omp_get_max_threads");
  a negative run with TC/flang removed fails at once, naming the
  compilers archive.
- Step 7, the default chain end to end (seconds): rzig-test 51,
  toolchain-test 6, build 150, toolchain 7, verify-tree 24,
  verify-toolchain 23, smoke 3, contract 104, hermetic 11, pkg-parity
  137, package-toolchain 103, verify-package 307; `-e minimal build`
  140 and `toolchain` 5; `-e wheel wheel` 16 and `wheel-test` 66 (zig-fc
  with no flang exits 127 naming the compilers `.tar.xz`; the pip line
  unchanged); `-e pkg conda-package` 283 (r-zig-slim hb0f4dca_12,
  r-zig-compilers and r-zig-build-tools h318eb1d_12, r-zig-toolchain
  h889a3b9_12, built locally as `_12` before the 2026-10-19 decision,
  the PR keeps 8; the four tests and P's probe pass; no package lists
  `bin/toolchain/flang` or `bin/toolchain/zig`) and `conda-consume` 25.
  actionlint passes on every workflow.
- Step 8: records only; `git diff` before and after, the lock unchanged
  ("Phase 6 record: hand-over").

omicron (osx-arm64) and kappa (win-64), the host stage (2026-10-17).
Each tester ran a copy of the worktree (`~/rz-p6`,
`C:\Users\admin\rz-p6`; never this worktree), recorded pixi.lock's
sha256 (fbb64b7b... at every start and end, on the host and in this
worktree) and a manifest of the copy at start and end, and deleted
the copy, its lock and its scripts afterwards (checked again by the
recorder: no `rz-p6*` left on either host). kappa kept PIXI_CACHE_DIR,
RATTLER_CACHE_DIR, XDG_CACHE_HOME and TEMP inside its copy, and its
shared rattler, zig and r-zig caches were checked unwritten. Round 1
ran the worktree at `git diff` sha256 050f3c2a...; round 2 ran it after
the host fixes (48d46c81...; two files changed: recipe/test-compilers.R
and a comment in fortran.zig). Logs: `phase6/omicron/` (round 2 in `r2/`),
`phase6/kappa/` (`r2/`).
- omicron, round 1, all passing but one kit check: `lock-check`;
  `rzig-test` with conda-forge's zig (38 s) and upstream zig (29 s);
  `toolchain-test`; `build` (330 s); verify-tree; `toolchain` (summary
  `flang/ (flang-zig, flang-rt-zig), openmp/, usr/, zig/`);
  verify-toolchain ("flang verified: ... 23.1.1"; the driver and
  runtime listed as naming flang-pixi's build paths under `$HOME`, not
  failed, as Cg10 expected); `package-toolchain`; `unpack-toolchain`
  and verify-toolchain on the unpacked tree; verify-package, both
  passes, under `env -i PATH=/usr/bin:/bin` (each pass: "no .cfg in
  the extracted tree, no flang on PATH", "flang from TC/flang");
  `check` (190 s); contract; pkg-parity; minimal `build` and
  verify-package (B40's limit: "undefined symbol:
  _omp_get_max_threads"); `wheel` and wheel-test (zig-fc with no flang
  exits 127; the compilers text names the `.tar.xz`); the upstream
  one-zig leg (`build`, verify-tree, `toolchain`, verify-toolchain,
  `package-toolchain`, verify-package); `-e pkg conda-package` (r-zig-*
  `_12`, built locally before the 2026-10-19 decision kept 8, no
  `bin/toolchain/flang` or `bin/toolchain/zig/` in any
  package, P's probe OK) and conda-consume. The step-3 kit's
  bundle-unix.sh passed every section (resource dir, `flang -###`,
  the split's RZIG_PRINT_ARGV, `omp_lib.h` with INCLUDE, `#include` and
  `-E`, the renamed-module-directory simulation, dtmod, fcl, fomp and
  fompfc on two threads, quadprog, Rcpp and minqa through rzig build
  tier 1, nothing left in TMPDIR) but five.sh's call 2: it grepped
  `-v`'s output for `ld.lld`, linux's linker, where macOS's zig prints
  `zig ld ...` (a kit bug; the binary was linked). K on macOS
  (`k-mac.sh`, then `patch -p1 -R` of `phase6/fix/k-revert-macos.diff`,
  a rebuild with `link_libcpp`, and back): libR.dylib 3,051,112 B,
  libRblas 238,064 B and libRlapack 1,820,000 B with and without
  `link_libcpp`, each exporting 0 `std::` and 0 `___cxa`/`___gxx`
  symbols and none referencing `___cxa_atexit`; RcppArmadillo 15.6.0-1
  (fastLm), Rcpp, quadprog and minqa build and load, `___cxa_atexit`
  is "undefined external (from libSystem)" in minqa.so, Rcpp.so and
  RcppArmadillo.so, and no package loads libc++. So the drop changes
  nothing on macOS and stays (K2 a; risk 3 does not occur).
- kappa, round 1, all passing but one test: `lock-check`; `rzig-test`
  with both zigs (130 pass, 32 skipped); `build` with K's drops (6m48s;
  R.dll, Rblas.dll and Rlapack.dll link without libc++, which PE would
  refuse if a symbol were missing); verify-tree; smoke; `toolchain`
  (2m51s; `flang/ (flang-zig, flang-rt-zig)` first); verify-toolchain
  (19,621 files, flang.exe 23.1.1, 10 PE closures; flang.exe and the
  runtime listed as naming kappa's flang-pixi build paths);
  `package-toolchain`; `unpack-toolchain` and verify-toolchain on the
  unpacked tree; verify-package, both passes (every Fortran line names
  TC/flang; the zig-fc.exe dry run has no `-lc++`; fcconf's
  configure.win, USE_FC_TO_LINK, Fortran OpenMP and the derived-type
  module pass); `check` (8m56s); compile-tree, contract, pkg-parity,
  hermetic; the upstream one-zig leg (`build`, `toolchain`,
  `package-toolchain`, verify-package). kappa's own bundle-win.sh (its
  first run had three bugs of its own; the rerun, bundle-win2, passed):
  System32's tar and R's `untar()` on the `.tar.xz` (L holds);
  `-print-resource-dir` is TC/flang/lib/clang/23 with no `Library/`;
  `flang.exe -###` names only the tree and reads no `.cfg`; the five
  calls (conftest.exe, `-v` with `lld-link`, m.dll loaded with 42,
  omp.exe and ompso.dll on two threads, a failing compile leaving no
  `rzig-fc-*` in TEMP); RZIG_PRINT_ARGV with the modules path at
  `.../finclude/flang/x86_64-w64-mingw32` and zig.exe linking the
  runtime with no `-lc++`; dtmod, fcl, fomp and fompfc through rzig
  build tier 1; quadprog and Rcpp tier 1, and minqa with make (its
  Makevars.win `$(shell)`, as contract already asserts). K on Windows:
  R.dll (3,631,104 B) imports no C++ runtime DLL; Rblas.dll and
  Rlapack.dll export 0 `_Z` symbols; the Fortran package DLLs import
  only R, Rblas, libomp and system DLLs; so all the Windows drops stay
  (K a). The one failure: `-e pkg conda-package`'s r-zig-compilers
  test, where P's new probe required the link's first word to be named
  `zig`; on win-64 conda-forge's zig is
  `Library/bin/x86_64-w64-mingw32-zig.exe`, since its `zig` is a .bat
  (find_zig.zig). With kappa's proposed name-list fix on its copy,
  conda-package (`_12`, built locally before the 2026-10-19 decision
  kept 8; P's probe OK, no `bin/toolchain/flang`) and conda-consume
  passed.
- The host fixes (2026-10-17; `phase6/rfix1/`): recipe/test-compilers.R
  now compares the link's first word, as a path, with the zig that
  `zig-fc --rzig-check=fortran` reports (stricter than a list of names,
  and no Windows special case); the kit's five.sh accepts `ld\.lld|^zig
  ld ` (a fixed kit with its kit.sha256 in `phase6/rfix1/kit/`;
  `phase6/step-3/kit/` is left as it was); fortran.zig's split() doc
  says so too. gamma: bundle-unix.sh with the fixed kit and `-e pkg
  conda-consume` with the new probe pass.
- Round 2, both hosts passing every task: omicron `lock-check`,
  `rzig-test`, `build`, `toolchain`, verify-toolchain,
  `package-toolchain`, verify-package (351 s), bundle-unix.sh with the
  fixed kit (0 FAILED lines; five.sh matches "zig ld -dynamic
  -platform_version macos 13.0.0 26.4 ..."), contract, pkg-parity,
  conda-package (the probe's link uses `$PREFIX/bin/zig`, the check's)
  and conda-consume; kappa `lock-check`, `rzig-test` with both zigs,
  conda-package (13 min; r-zig-slim h9490d1a_12 and the three group
  packages, built locally as `_12` before the 2026-10-19 decision, the
  PR keeps 8; the probe's path comparison passes, rattler-build's
  `%PREFIX%` and `%SRC_DIR%_run_env` display masks normalised to the
  same file) and conda-consume. The tasks whose inputs rfix1 did not
  touch were not run again.
- Not run in this phase: omicron's osx-64 under Rosetta (the plan's
  table had `toolchain`, verify-toolchain, `package-toolchain`, the
  Fortran calls, the driver's signature and whether the endpoint agent
  touches it, verify-package's toolchain pass); the open items below
  say how it is covered. No failure on any host had a cause in
  flang-zig or flang-rt-zig, so B44 needs nothing from flang-pixi.
- The K revert patches were made for a failing host and are now
  history: `patch -p1 -R` of `phase6/fix/k-revert-windows.diff`
  (sha256 b13ada78...) or `phase6/fix/k-revert-macos.diff` (1acdf6f4...)
  takes that OS's `-lc++` back (omicron used the macOS one for its
  before/after); `phase6/implementer/k-drops.diff` (e0bcd4bc...) is
  the record of what step 5 landed.

CI: not run. The PR's runs go into "Phase 6 record: CI": run IDs; each
toolchain leg's time (the xz step) and artifact size; unpack-toolchain's
time per leg kind; verify-package per pass against phase 5's (above) and
the CI baselines in "Phase 5 record: the measurements"; linux-aarch64's
first TC/flang run (T); and the carve cross-check (J) for linux-aarch64,
osx-64 and win-64 against the SOURCES in each leg's compilers artifact
(`phase6/step-2/carve/crosscheck.sh` with that subdir's carve; gamma
compared linux-64 and omicron's SOURCES osx-arm64; kappa's tree was
deleted before its SOURCES was compared).

#### Phase 6 record: the per-OS facts and what the critiques added

The modules flag per OS (Cc13, Cg4): linux's and Windows' drivers find
their modules under their default triple without it (CP1:
`x86_64-conda-linux-gnu` and `x86_64-w64-windows-gnu` are shipped
directories; SR §3.2's "linux finds them only through the symlink" was
wrong); macOS's does not (CP2). The flag is kept on every OS as one
rule. Bare-driver probe (TC/flang/bin/flang -c with no flag and no
cfg), linux-64: `use iso_c_binding`, `use omp_lib`, `INCLUDE
'omp_lib.h'` and `#include "omp_lib.h"` all compile. gamma reproduced
macOS's case with a copy whose module directory was renamed: the bare
driver fails all four, zig-fc compiles them and links a `-fopenmp`
program that runs on two threads. omicron (osx-arm64; the driver's
default target `arm64-apple-darwin25.4.0`, the shipped directory
`arm64-apple-darwin20.0.0`): the bare driver fails all four ("Semantic
errors" for `use`, "Could not scan" for the includes), and zig-fc
compiles them, as CP2 measured. kappa (win-64): the bare driver
compiles all four; zig-fc's flag picks `x86_64-w64-mingw32`, the
first of the two twins in byte order (B a).

B40's Fortran limit (U): recorded in B40's entry and asserted in
minimal's verify-bundle; README's minimal text says so.

macOS signatures of TC/flang/bin/flang (Cc11): CP4 read both macOS
packages' `bin/flang-23` as ad-hoc signed (CS_ADHOC, not zig's
linker-signed flag); no file has a prefix placeholder, so rattler never
re-signs it and the toolchain build's byte copy should stay valid.
Phase 5's zig notes, for comparison: TC/zig/zig is ad-hoc
linker-signed, `spctl` "rejected", and runs with no prompt. omicron
(osx-arm64, 2026-10-17), in `dist/toolchain` and in the extracted
tree: Mach-O arm64, 135,869,744 B; `Signature=adhoc`,
`flags=0x2(adhoc)`, no linker-signed flag (CP4 confirmed); `codesign
-v` valid; `spctl -a -t exec` "rejected" (exit 3), yet it runs with no
prompt; xattr `com.apple.provenance` only, no quarantine; `otool -L`
libSystem only; minos 11.0. The endpoint agent left it alone (no
`Killed: 9` anywhere in the chain). osx-64's driver was not checked
(Rosetta did not run; open items).

#### Phase 6 record: osx-64 under Rosetta (2026-10-17, omicron)

Run after the hand-over, as its menu recommended, in a scratch copy
re-solved for osx-64 (lock 0662b7ae…, the same as phase 5's; conda-forge
zig 0.16.0, flang-zig 23.1.1 `zig_0257dba_6`, flang-rt-zig
`zig_e4a4366_10`). Every task passed and nothing was left to CI; no
Falcon event (no kill, no exit 137, no quarantine, no binary gone):
- toolchain 119 s (TC/zig and TC/flang x86_64; TC/flang 23 files,
  150 MB, one module directory `x86_64-apple-darwin13.4.0`),
  verify-toolchain 12 s, package-toolchain 84 s: the compilers
  `.tar.xz` is 90,125,796 bytes, 20,903 members (38 under flang/).
- build 221 s: libR, libRblas and libRlapack export no `std::`,
  `___cxa` or `___gxx` symbol and load no libc++ (K2's after count).
- verify-package 751 s (phase 5: 570 s): the toolchain pass took zig
  from TC/zig and flang from TC/flang with PATH=/usr/bin:/bin; the
  first Fortran compile 32 s cold, 2 s warm; the build pass passed too.
- The host kit's Fortran calls: 41 ok, 0 failed (resource dir in the
  tree; `flang -###` reads no `.cfg`; modules, OpenMP, `omp_lib.h`, the
  dtmod/fcl/fomp/fompfc packages, quadprog, Rcpp and minqa at tier 1).
  The compile-side list refuses the same 40 flags as osx-arm64. The bare
  driver fails all four files without zig-fc's flag (its default triple
  is darwin25.4.0), as expected on macOS. The carve cross-check matches
  (20 files).
- Signatures: TC/flang/bin/flang is ad hoc signed (`codesign -v` exit
  0; `spctl` rejects it, as the plan expects) and runs with no prompt;
  TC/zig/zig (the ziglang wheel's) is not signed at all (`codesign -v`
  exit 1) and still runs under Rosetta. The endpoint agent touched
  neither.
Logs: /data/gamma/luciorq/workspaces/temp/r-zig-pixi/phase6/omicron-osx64/.

The licence set (Cc12, checked): flang/'s LICENSES hold the LLVM
project's Apache-2.0 WITH LLVM-exception text for both packages. CP5:
every driver (linux-64, osx-arm64, win-64) says LLVM was built without
zlib and zstd, so no third-party compression library is in it. The
linux driver's NEEDED list is glibc only, so it carries zig's static
libc++/libc++abi (LLVM's licence, the text flang/'s LICENSE.TXT holds)
and zig's compiler_rt (MIT, the text TC/zig/LICENSES/ziglang holds in
the same compilers archive). A flang/ shipped alone would need zig's MIT
text ("Later and future checks").

Embedded build paths (Cg10): all three OSes' drivers embed flang-pixi's
build paths; linux-64's names
`/data/gamma/luciorq/workspaces/temp/rb-out/bld/...` 912 times, outside
every directory verify-toolchain scans on gamma, so nothing is listed.
omicron's and kappa's verify-toolchain listed flang/'s driver and
runtime as copies naming flang-pixi's build paths
(`/Users/luciorq/flang-pixi-rbout/bld/...` on omicron), listed, not
failed, as for make. `flang -###` from each host's extracted tree
(gamma, omicron and kappa are flang-pixi's build hosts) names only
paths under it and reads no `.cfg`.

The carve cross-check (J; B9's "once"): flang-pixi's
`carve-fortran-standalone.py` (sha256 a350d078..., unchanged since
eaa07ba; the clone's HEAD e384eba) ran under `pixi exec --spec
"python>=3.14"` on the ten pinned flang-zig and flang-rt-zig `.conda`
files, each sha256 found in pixi.lock. It carved 24, 24, 24, 24 and 40
files (linux-64 210.0 MB raw, linux-aarch64 195.9, osx-64 157.3,
osx-arm64 143.9, win-64 190.3). linux-64: the 20 carved regular files
(`Library/` dropped, `bin/flang-23` read as `bin/flang`) equal flang/
SOURCES' 20 `file:` lines with the same sha256; the extras are exactly
STANDALONE-ORIGIN.txt, `bin/flang.cfg`, the `bin/flang` symlink, the
linux module-directory symlink and the `lib/libflang_rt.runtime.a`
symlink, the decided omissions. osx-arm64 (omicron's SOURCES,
compared on gamma): the 20 carved regular files MATCH SOURCES' 20
lines; the extras are STANDALONE-ORIGIN.txt, `bin/flang.cfg` and the
`bin/flang` and `lib/libflang_rt.runtime.a` symlinks. linux-aarch64,
osx-64 and win-64 are compared against CI's artifacts (above). The
script's own "four duplicate runtime archives" comment is flang-pixi's
file: recorded, not edited.

linux-aarch64's cross pre-check (Cg3, recorded, not a gate): the x86_64
TC/flang driver with `--target=aarch64-unknown-linux-gnu` and the
aarch64 module directory compiles the derived-type module, its users and
a `-fopenmp` `use omp_lib` source to AArch64 objects; TC/zig links an
aarch64 executable (interpreter /lib/ld-linux-aarch64.so.1, NEEDED libm
and libc) and a shared object with the aarch64 runtime. Neither can run
on gamma; CI runs the aarch64 driver itself (T). The aarch64 and x86_64
runtime archives leave no `_Z` symbol unresolved, and their only C++-ABI
reference is `__cxa_atexit` (K's premise on linux).

The compile-side list (Cc1), re-measured with the extracted driver: 65
entries, 40 refused, every exit code equal to step 1's, so no additions
on linux-64. omicron's macOS driver and kappa's flang.exe (MSYS argument
conversion off) give the same 65 entries and 40 refusals, every exit
code equal to gamma's: neither list grows (E a).

A flang that is not flang-zig's through zig-fc (Cg9, risk 15; a record,
not a gate): conda-forge's flang 23.1.3 alone: compiles, but a link
misses the runtime (`undefined symbol: _FortranAProgramStart`; that
package has no flang_rt archive). With flang-rt_linux-64 23.1.3 too,
`flang_rt.find` finds its `.a`: conftest links and runs and `-v`
shows zig's ld.lld line; the derived-type module's second compile
aborts inside flang 23.1.3 itself ("runtime derived type info
descriptor was not generated"), and `use omp_lib` fails because
conda-forge's packages ship no intrinsic modules. flang-zig's driver
passes all five.

Configure probes that parse `-v` (risk 2): CMake's Fortran detection
now reads zig's link line. A CMake project with a Fortran target built
and ran through zig-fc; its `CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES`
names TC/flang's runtime plus two archives in zig's cache
(`libc_nonshared.a`, `libcompiler_rt.a`). A package that copies those
paths into its own link would depend on that cache; R packages take
FLIBS from Makeconf, so only a package's own probe sees them.

FLANG_PIXI_HANDOFF.md §1 item 3 ("never copy flang.exe") and its note
that consumers should not pass the modules path are superseded by §8
and by this phase (a copy works: the resource directory follows the
binary, and zig-fc passes the modules path); the HANDOFF itself is
unchanged, and nothing was sent to flang-pixi.

The amendments (phase6/CRITIQUE.md): the code critique's Cc1-Cc18 and
the goals critique's Cg1-Cg11 were checked against the worktree and,
for flang claims, a staged TC/flang. All were accepted (some widened,
merged or done differently: Cc1 widened to 31 refusals; Cc8 with Cg8;
Cc10 as W; Cc13 with Cg4; Cc17 as X) but two. Cc5's `.zip` fallback for
Windows was decided otherwise by Cg2 (L), its recording half kept.
Cg7, comparing the base's FC_VER or `R_compiled_by()` with
TC/flang's `--version`, was rejected: FC_VER is a hand-kept captured
string on unix (`zigbuild/config/*/{subst.txt,config.h}`) and a fixed
text with no version on Windows (`"flang (flang-pixi flang-zig, MinGW
target)"`), so the check would fail on Windows by design and on unix
compare a hand-kept string; same-bytes is already enforced by the one
solve-group `r` and the exact flang-zig and flang-rt-zig build pins in
`[dependencies]` and `[feature.minimal.dependencies]`, and
verify-toolchain checks TC/flang's version against SOURCES (I).

Recorded by kappa, not failures: `R CMD config` needs `sh` on Windows
(with PATH `bin\x64` and System32 only it has none; phase 7);
`R CMD config SHLIB_OPENMP_FFLAGS` prints "no information for
variable" on Windows, as before phase 6; RZIG_TRACE lines mix `/` and
`\` (cosmetic); minqa needs make on Windows (its Makevars.win uses
`$(shell)`), as contract asserts.

Open items for the user (none filed, nobody contacted):
- Phase 6 is pending CI: linux-aarch64 (its only B44 run), native
  osx-64 (macos-15-intel) and the `upstream-zig` label run need your
  push with `full-ci` and the label; the PR does not merge before they
  pass. CI's artifacts also give the carve cross-check for
  linux-aarch64, osx-64 and win-64.
- osx-64 under Rosetta on omicron: run after the records, on
  2026-10-17 (the hand-over menu's recommended option; see "Phase 6
  record: osx-64 under Rosetta" below). It passed.
- H: flang-pixi's recipes record no repository (`extra.remote_url`,
  `extra.sha`), so flang/'s SOURCES says `feedstock: unknown`.
  Cosmetic; a flang-pixi change if wanted.
- Settled by the host stage, nothing left: kappa's `untar()` reads the
  `.tar.xz` (L holds); no host failure had a cause in flang-zig or
  flang-rt-zig (B44 needs no flang-pixi build and no re-lock); K keeps
  every drop.
- Later, not acted on (Cg5, Q): r-zig-compilers' explicit `lld-zig
  ==23.1.1 *_5` pin is redundant now (flang-zig run-depends on lld-zig
  anyway); dropping it is a dependency change, yours to decide.

#### Phase 6 record: hand-over (2026-10-17)

`phase6-only.diff` (open point S) is made by
`phase6/handover/make-diff.sh`: main d11dee1 exported with `git
archive`, `phase5-base.diff` applied (sha256 checked), the baseline's
eleven untracked files copied from the phase 5 worktree (each sha256
checked against step 0's record); that baseline is identical to the
phase 5 worktree. Then `diff -ruN` against the worktree's tracked and
untracked files, and the check: the diff applied to a second copy of the
baseline reproduces the worktree exactly. The earlier copies in
`phase6/step-8/handover/` and `phase6/implementer/` predate the host
stage and are superseded. The commit and PR commands are
`phase6/handover/commands.sh`, with no trailer: it applies the diff
with `patch -p1 --no-backup-if-mismatch` (a hunk applied with an offset
or fuzz leaves no `.orig`), and step 3 adds, commits, pushes and opens
the PR only when `git status` shows no `.orig` or `.rej` file
(.gitignore has neither, so `git add -A` would stage one; fixer,
2026-10-16). The PR body (`phase6/handover/pr-body.md`) gives the host
results and says phase 6 is pending CI.

### Phase 7 — Windows build tools: usr/bin

Goal: on Windows, base + compilers + build-tools compiles with PATH set
to `R_HOME\bin\x64` and System32 only.

Decisions (answered): B11 (conda-forge packages, `m2-*` where needed),
B25 (Windows contents), B39, B43 (pkg-config).

Steps:
- Choose the conda-forge package for each tool of B39's list and for
  pkg-config: a native win-64 build where conda-forge has one, else the
  `m2-*` package (B11). pixi.lock already has native make 4.4.1,
  uutils-coreutils and pkg-config, and the m2 set ("Facts"). Each tool
  must be an .exe of its own name (GNU make runs simple recipe lines
  without a shell); check that for uutils-coreutils. If conda-forge's
  native make.exe is chosen, whether it is stripped (17,111,844 B as
  shipped, 287,744 B stripped) is decided here. Record the choice and
  why.
- The toolchain step copies the chosen packages' files from the build
  env into `TC/usr/bin/` with their DLL closure (for the m2 ones,
  msys-2.0.dll and the msys-*.dll they import), and writes
  `usr/LICENSES/` and `usr/SOURCES` from conda-meta (name, version,
  build, URL, sha256). verify-tree checks the closure.
- conda's win-64 r-zig-build-tools depends on the same packages (B11),
  replacing phase 4's interim list.
- Rprofile.windows gets the same PATH line if the tests need it.
- `R CMD config` without the build tools fails with one clear message
  (rcmdfn.c runs `sh` before patch 0010's check can run).
- The build-number bump (B14's amendment, 2026-10-19): phases 4, SHLIB
  routing, 5 and 6 kept 8, so phase 7's PR takes the number after
  universe's newest (B14 a), with one history entry for phases 4 to 7.
  After it merges the user sets `gh variable set CONDA_PUBLISH --body
  true` and dispatches build.yaml on main, which publishes all four
  packages; then PHASE4 section 7's post-publish check, and the user
  deletes the variable (a release switch, decided 2026-10-27). Done:
  published as `_9` on 2026-11-05 (build.yaml dispatch 41942729382 on main, CONDA_PUBLISH set for it and deleted after the check).

Tests: scenario 3 on kappa and windows-latest with the contract set,
pak, data.table, glue and a package whose configure.win uses
pkg-config; the same in a fresh conda env with r-zig-toolchain; a run
with Rtools or Git for Windows also on PATH (the msys-2.0.dll risk).

#### Phase 7 record: what changed (2026-10-20, as amended 2026-10-21)

The plan: phase7/PHASE7-IMPLEMENTATION.md as amended by
phase7/AMENDMENTS.md (the m2 set, the user's decision of 2026-10-20, the
★ options; no open menu before implementation), then by its "User
decisions 2026-10-21" (pkgconf out, F2 b, MSYSTEM a; the last subsection
below). `phase7-only.diff` against phase 6's worktree (git diff
7304b53c...), the bump apart (`bump.diff`, the hand-over's last commit).
The list below is the final state; the measurements and tests of
2026-10-20 that follow it ran with pkgconf (Am1, Am2).
- zigbuild/toolchain/build.zig (A-F, O): Windows' `usr` directory:
  every regular file of the eight m2 tool packages' `Library/usr/bin/`
  (`m2Tool`, a `Tree` with `strip = "Library/usr/"`; `Tree.strip`
  defaults to flang/'s `Library/`), the nine MSYS DLLs (`usrBin`), and
  pkg-config 0.29.2 with its glib closure (`glib-2.0-0.dll`, `iconv.dll`,
  `charset.dll`, `intl-8.dll`, `pcre2-8.dll`, `vcruntime140.dll`; D0 a),
  none of them `in_conda`; `etc/fstab`, two lines written (D a), with
  `etc/SOURCES` (`written:` and a `file:` line, no LICENSES/); the m2
  licence fallback: an m2 package with no `info/licenses/` takes
  `m2-licenses/<name>/`'s texts after its VERSION matches the record's
  `<version> <build>`, else the build stops ("... does not hold its
  texts"), and SOURCES gets `licenses: from <its MSYS2 source archive>`
  (E a). `readUpstream` takes a rattler-build output's
  `finalized_cache_sources` when its `finalized_sources` is empty (an
  output of a staging output: libglib, whose LGPL needs its source named;
  kappa 2026-10-21). conda.zig: `inDir(path, strip)`,
  `Upstream.licenses_from`; three new unit tests and a staging-output
  case in the recipe-sources test (20 in all).
- zigbuild/toolchain/m2-licenses/ (E a): 17 directories, 31 texts
  (812 KB), VERSION and ORIGIN each, and a README; taken by hand from
  the 17 MSYS2 source archives (each checked against its recipe's
  sha256; grep's and findutils' from the conda-forge mirror, MSYS2 no
  longer has them). ORIGIN notes four licences that differ from
  conda-meta's `license:` (which SOURCES keeps): msys2-runtime (the
  Cygwin DLL: LGPL-3.0-or-later with Cygwin's linking exception, newlib's
  BSD-like texts), m2-libintl (LGPL-2.1-or-later), m2-libiconv's
  library (LGPL-2.1-or-later), m2-gmp (LGPL-3.0-or-later or
  GPL-2.0-or-later).
- scripts/env.sh: `group_dirs build-tools` is `usr etc binutils`.
  scripts/verify-toolchain.sh (O a, Am10): on Windows each of B39's
  names, coreutils' 21 R's makefiles and configure scripts run and
  pkg-config is an .exe in usr/bin that runs with PATH = System32 (33),
  make says SOURCES' m2-make version less MSYS's
  release, etc/fstab is the two lines, and TC's sh, started from cmd.exe
  with TMP and TEMP a scratch directory, says / is R_HOME/bin/toolchain
  and /tmp that directory. Started from the env's MSYS bash, a child
  with the same msys-2.0.dll release takes its parent's mount table
  (kappa: root and /tmp the env's): R starts sh natively, so R is not
  affected; the check goes through cmd.exe.
- zigbuild/patches/R-4.6.1/0010 (J a): a second hunk, rcmdfn.c runs
  `gcc.exe --rzig-check=build-tools > NUL` before `sh config.sh` and
  returns its status. 0014 (new, I a, Am4, F2 b): Rprofile.windows puts
  `R_CUSTOM_TOOLS_PATH` (empty read as unset) or `TC/usr/bin` then
  `dirname(dirname(R.home()))/usr/bin` first on PATH (without "..": R's
  own command search rejects `R_HOME/../../usr/bin` there, "Found while
  implementing" below; only Rcmd_environ spells it with "..").
  build.zig's rcmdEnviron (H a):
  `UserNM=${UserNM-${R_ZIG_NM}}`, the group's binutils/nm.exe; (F2 b)
  `R_ZIG_TOOLS_PATH` gains `${R_HOME}/../../usr/bin` (a conda env's
  `Library/usr/bin`) after the group's usr/bin, and verify-tree.sh's
  Rcmd_environ line check with it; check.zig's comment on PHASE4 I a's
  line says when it still comes on Windows. groups.zig (K a): "extract
  R-<ver>-win-64-build-tools.zip where you extracted R".
- scripts/verify-bundle.sh: scenario 1's R CMD and session PATH, both
  entries (unset, empty and set R_CUSTOM_TOOLS_PATH); scenario 3 on Windows with PATH = bin\x64 +
  System32 (no CONDA_PREFIX): the check names TC's make and sh, bt.R's
  `Sys.which("make")` is TC's make.exe on every OS, btTools (21 steps of
  B39's tools through a configure.win, a cleanup.win under --preclean
  and a Makevars rule), btPc (pkg-config 0.29.2, a .pc under a path with
  a space: the public libraries, the private ones with --static, the
  redefined prefix, the escaped -I compiled through make and sh), R CMD
  check's nm (UserNM,
  a user's kept), and the clash with Git for Windows' MSYS (first with
  MSYSTEM=MINGW64, the packages again and btMix running Git's diff and
  cygpath from TC's sh; after, Sys.which and the check only).
  hermetic-check.sh, test-preflight.R, test-compilers.R: R CMD config's
  127 and text on Windows too, no "is not recognized".
- recipe/recipe.yaml (Cr5, N a, D0 a): `etc` in r-zig-slim's exclusion
  and `not_exists` globs; the comments no longer call the win-64 list
  interim and say R puts the env's Library/usr/bin on PATH (F2 b);
  r-zig-build-tools still owns binutils/ alone and depends on pkg-config
  (no pkgconf). recipe/test-build-tools.R (Am6, F2 b): B39's names are
  this env's m2 tools (System32's names by file), B43's bare pkg-config
  is this env's, and with no MSYS dir on PATH the check under R CMD finds
  the env's make and sh. scripts/conda-consume.sh (P a): a fourth env,
  r-zig-toolchain, test-toolchain.R.
- pixi.toml: the m2 comment only. pixi.lock: unchanged, phase 6's
  (fbb64b7ba4e31e45...): the 2026-10-20 re-lock that added pkgconf
  (e7dacdcb...) was undone with D0 a (the approved restore of the
  pre-relock file, byte-equal to phase 6's; `pixi lock --check`
  passes).
- stress/stress.R, .github/workflows/stress.yaml, stress/README.md (L a):
  `--msys-from-tree` (Windows tree runs only; elsewhere and for conda
  ignored with a note), the `msys_from_tree` input, report.json's
  `msys_from_tree`. stress/packages.tsv: unchanged; ncdf4 and RPostgres
  stay expected failures on Windows (D0 a).
- README.md (Windows build tools, pkg-config's search, the System32
  names, spaces and long paths, a conda env's MSYS dir on PATH, Git
  Bash's MSYSTEM triplet), the
  compile-tree.sh header, pixi.toml's m2 comment, the
  feat-shlib-rzig-build J dispatch's baseline note.

#### Phase 7 record: the measurements (2026-10-20, linux-64, osx-arm64, win-64)

| what | value |
|---|---|
| `usr/` (kappa) | 137 files, 21,751,172 bytes (Am15's figure), 19 packages in usr/SOURCES (17 with `licenses: from`), 19 LICENSES/ directories; `etc/` fstab (84 B) and SOURCES |
| build-tools `.zip` (kappa) | 16,386,817 bytes, 192 members; phase 6's 5,401,812: +10,985,005 (Am15 said about 10.6 MB) |
| toolchain step (kappa) | 157 s; its configure step (toolchain-test's second run: build() with readRecords' `bin` needle and cached tests) 2 s, so risk 9's narrower needle is not needed |
| verify-toolchain (kappa) | 85-99 s (phase 6: 90 s) |
| verify-package (kappa, conda-forge's zig) | toolchain pass 379 s, build pass 338 s, 728 s in all (phase 6's kappa round 1: 775 s) |
| MSYS root (kappa, TC's sh from cmd.exe) | with etc/fstab: / = TC, /tmp = TEMP, drives at /c, here-doc and mktemp ok; without it: "could not find /tmp, please create!", /cygdrive/c, mktemp fails; cp and mkdir in a fresh directory: only inherited ACEs either way |
| the clash (kappa, Git for Windows' msys-2.0.dll 3.6.5) | Git first with MSYSTEM=MINGW64: R CMD sh's `uname -s` is MINGW64_NT-10.0-22621 (TC's uname reads MSYSTEM), btMix's `which diff` Git's, `cygpath -m /` "C:/Program Files/Git/"; the packages build in 37-40 s; no cygheap, fork or fatal-error line |
| R CMD config (kappa) | install.R never runs it (Cr12's premise was wrong: no `CMD config` in R 4.6.1's install.R); a configure.win runs it once per variable it asks; `R CMD config CC` takes 0.40-0.53 s a call on kappa (10 calls: 4.00 s and 5.25 s), rzig's check alone 9 ms (10 calls: 0.090 s), `R CMD sh -c true` 55 ms: J (a)'s second check costs about 9 ms a call, far under risk 7's second per package, so J (b) does not come back |
| step 1's pkg-config probe (kappa, conda-forge's MSVC pkgconf) | `pkg-config --libs libcurl` under R CMD sh: `-L<env>/Library/lib -lcurl <env>/Library/lib/z.lib -lwldap32 -lbcrypt -ladvapi32 -lcrypt32 -lsecur32 -lws2_32 -liphlpapi -lssh2 -lz -lpsl`, conda-forge's libcurl.pc's public `Libs`, which list its own dependencies; `--cflags` adds `-DCURL_STATICLIB`. Under the space path the `-I` and `-L` values are escaped (`r\ zig`, one `-I` twice: `r\\\ zig`) and z.lib's absolute path is not (Am1's second risk, seen) |
| KN's 38 targets | KN's M column (the m2 set with pkg-config 0.29.2) installed 30 of 38; with pkgconf, ncdf4 (d) and RPostgres (i, by its download) are expected ok: 32 of 38; a, b, c, e, f, j stay the toolchain's or the packages' (stress expects them). Step 1's run: Rcpp, glue, ps, minqa, systemfonts, ncdf4 (links `-lnetcdf`: d fixed), RPostgres (its winlibs.R download, "using libpq from Rtools" absent; offline: "Could not connect to server", FAIL as expected), pkgbuild, pak (214 s), winch (installs, `winch_available()` FALSE: "no acceptable ld found in $PATH", C6) installed and passed their smokes on the first pass; data.table and gmp failed on `libintl.h` and units on `-lexpat`, which the planned libraries env lacked (libintl-devel, expat: added), units then loaded once the env's `Scripts\` (udunits2.dll's place) was on PATH, and Rmpfr and qfratio failed in configure only because the batch named the libraries env `LIBS`, which autoconf reads (renamed: both install; qfratio's config.guess says x86_64-pc-msys). No failure is the build tools' |

#### Phase 7 record: tests on every host (2026-10-20)

gamma (linux-64; the implementer, who owns `dist/`): every pixi task
with `--frozen` (the approved re-lock apart), PIXI_CACHE_DIR
pixi-cache-p6 and the caches and TMPDIR under phase7m2/implementer/.
- Step 2: `zig fmt --check`; `toolchain-test` with both zigs (34/34:
  conda.zig 20, wheel.zig 14); `toolchain` with both zigs prints phase
  6's summary and the tree's 19,590 files and sha256s equal step 0's
  (phase 6's code) for each; `verify-toolchain` passes; the m2 texts'
  check script re-hashes 31 texts against ORIGIN (0 bad); the re-lock
  (above).
- Step 3: `rzig-test` with both zigs (162/162; parity 125 identical, 59
  identical but for rzig's own additions, 34 deliberate, 0 failed);
  `build` (the series hash changed: R extracted again, 0001-0014 applied
  with -F0), `smoke`, `verify-tree`, `hermetic` (R CMD config exit 127
  with the text); libR.so, bin/exec/R and base's Rprofile equal step 0's
  by sha256.
- Step 4: `verify-package` both passes (413 s), `-e minimal
  verify-package` (400 s).
- Step 5 and 7: `-e pkg conda-package` (r-zig-slim hb0f4dca_9,
  r-zig-compilers and r-zig-build-tools h9276ec7_9, r-zig-toolchain
  hdc6fa2d_9; the four tests pass), `conda-consume` (four envs, the new
  toolchain one included); the upgrade test from universe's `_8` with
  pixi, conda and micromamba, fresh caches: each OK (rzig's names, no
  clobber, four `_9` records, none `_8`, R CMD config CC, a tier-1
  package installs and loads).
- Step 7's default chain end to end on the final code: lock-check, rzig-test 56 s, toolchain-test 3, build 145,
  toolchain 7, verify-tree 25, verify-toolchain 11, smoke 2, contract
  128, hermetic 11, pkg-parity 189, package-toolchain 99, verify-package
  298, `-e minimal build` 138 and `verify-package` 261, `-e wheel wheel`
  13 and `wheel-test` 75, `-e pkg conda-package` 256 (the four `_9`
  files above), `conda-consume` 50: every step exit 0; only devdocs
  changed while it ran.
  actionlint passes on stress.yaml.

kappa (win-64; this implementer, `C:\Users\admin\rz-p7m-impl`, a copy
of the worktree checked by a sha256 manifest at each round's start and
end, all OK; pixi.lock e7dacdcb... throughout; PATH and every cache in
the scratch directory; C: had 7.6 GB free at the start, other users'
directories untouched; GAPS.md item 1 lists what did not fit).
- Step 2: `toolchain` (157 s; summary in copy order: `binutils/
  (binutils_impl_win-64, zstd, vc14_runtime), usr/ (m2-msys2-runtime,
  m2-libintl, m2-libiconv, m2-libpcre, m2-gmp, m2-mpfr, m2-libreadline,
  m2-ncurses, m2-gcc-libs, pkgconf, vc14_runtime, m2-bash, m2-make,
  m2-coreutils, m2-sed, m2-grep, m2-gawk, m2-which, m2-findutils), etc/
  (r-zig's fstab)`); the licence fallback stops with m2-sed's VERSION
  edited ("m2-sed 4.9.1 hc364b38_6 ships no licence file, and
  zigbuild/toolchain/m2-licenses/m2-sed/ does not hold its texts: its
  VERSION is 4.9.1 hc364b38_99") and passes restored; `verify-toolchain`
  ("usr/ verified: 34 tools run with PATH = System32; make 4.4.1; MSYS
  root <TC>, /tmp = TMP and TEMP"); its negative cases on a copy, each
  failing with its message: msys-2.0.dll deleted with its file line (the
  closure names every importer), deleted alone (in SOURCES, missing),
  sed.exe replaced (sha256), fstab with a third line (its sha256; with
  etc/SOURCES updated, "not build.zig's two lines"), a stray diff.exe (no
  file line), LICENSES/m2-sed emptied (missing or empty), fstab missing;
  `package-toolchain`, `unpack-toolchain`, `verify-toolchain` on the
  unpacked tree.
- Step 3: `build` (448 s; 0010's rcmdfn.c hunk and 0014 applied),
  `smoke`, `verify-tree`, `hermetic`: "R CMD config: exit 127 with rzig's
  build-tools text", no "is not recognized"; `R CMD config --help` with
  the base alone: the check runs first, exit 127 (as unix).
- Step 4: `verify-package` with conda-forge's zig, both passes, and the
  upstream-zig one-zig pass (346 s): scenario 1's R CMD and session PATH
  (unset, empty and set R_CUSTOM_TOOLS_PATH); scenario 3 with PATH =
  bin\x64 + System32: "zig-cc: build-tools ok: make at
  <TC>/usr/bin/make.exe; sh at <TC>/usr/bin/sh.exe; binutils at
  <TC>/binutils", bt.R's Sys.which("make"), btA, btLib and btRc with
  Ncpus = 2 through the session's make, every phase 6 block, btTools (21
  steps), btPc (`-lbtpc_pub`; `--static` adds `-lbtpc_priv`;
  `-IC:/.../pc\ dir/include`), R CMD check's nm, the clash. The negative
  run (the compile tree without usr/bin/sh.exe): "zig-cc: no sh on PATH"
  and the build-tools text (GAPS.md item 6).
- Step 8: `compile-tree` (openmp/, usr/, etc/, binutils/), `contract`
  (341 s; pak, ps, the no-make SHLIB and pak probes), `pkg-parity` (389
  s): both with the group's usr/bin first and the env's after it (risk
  8), no difference recorded.
- Step 1 (the bundle as a user extracts it, after steps 2-4; Am7, Am18):
  the bundle as a user extracts it (base, compilers and build-tools
  archives of the upstream-zig pass, `tar -xf` into one directory), its
  Rscript, PATH = bin\x64 + System32 + a libraries env's Library\bin
  (pixi exec: freetype, fontconfig, libpng, zlib, gmp, mpfr, udunits2,
  libnetcdf, libpq, libboost-headers, cmake, libcurl; no pkg-config,
  pkgconf, make or sh in its Library\bin, checked), R_ZIG_EXTRA_ENV and
  PKG_CONFIG_PATH its own, R_TOOLS_SOFT, MAKEFLAGS, CONFIG_SHELL and
  CMAKE_GENERATOR unset, Ncpus = 2, RZIG_TRACE=1, a fresh HOME. The
  session's PATH starts with TC/usr/bin; Sys.which gives the group's sh,
  make, sed, grep, gawk and pkg-config (8.3 names), System32's bash,
  find and sort (Am6); under R CMD `UserNM` is binutils/nm.exe (8.3
  form), the check names TC's make and sh, `R CMD config CC` is
  gcc.exe, R CMD sh's `uname -s` MSYS_NT-10.0-22621.
  `pkgbuild::has_rtools(debug = TRUE)` is TRUE and
  `check_build_tools(debug = TRUE)` says "Your system is ready to build
  packages!" (TODO's Later item answered: with sh present R CMD config
  CC answers). The packages: Rcpp, glue, ps, minqa, systemfonts, ncdf4 (links `-lnetcdf`: d fixed), RPostgres (its winlibs.R download, "using libpq from Rtools" absent; offline: "Could not connect to server", FAIL as expected), pkgbuild, pak (214 s), winch (installs, `winch_available()` FALSE: "no acceptable ld found in $PATH", C6) installed and passed their smokes on the first pass; data.table and gmp failed on `libintl.h` and units on `-lexpat`, which the planned libraries env lacked (libintl-devel, expat: added), units then loaded once the env's `Scripts\` (udunits2.dll's place) was on PATH, and Rmpfr and qfratio failed in configure only because the batch named the libraries env `LIBS`, which autoconf reads (renamed: both install; qfratio's config.guess says x86_64-pc-msys). No failure is the build tools'. Git first with
  MSYSTEM=MINGW64 (Am4 item 3): stringi (597 s), RcppParallel (121 s),
  gmp, Rmpfr, qfratio and winch install and pass. The space run (the
  bundle moved under `rz-p7m-impl\r zig\` with a second libraries env
  there): `R.home()` and UserNM are 8.3 paths with no space, R CMD
  check's `read_symbols_from_object_file` reads t.o with it (Cr11, risk
  10: no change needed where the volume has 8.3 names), data.table and
  Rmpfr install, ncdf4 fails as pre-registered ("C:/Users/admin/rz-p7m-impl/r:
  unrecognized file extension": libcurl.pc's z.lib path, README's "no
  spaces"). The negative check under R CMD with usr/bin/sh.exe moved
  aside: exit 127, "zig-cc: no sh on PATH" and the build-tools text.

omicron (osx-arm64; `~/rz-p7m-impl`, manifest OK at start and end,
pixi.lock e7dacdcb...): `rzig-test` with both zigs (162/162),
`toolchain-test` (34/34), `toolchain` and `verify-toolchain` (19,590
files; the tree's file list and sha256s equal phase 6's code's on the
same env, 19,590 entries), `build`, `smoke`, `verify-tree`, `hermetic`
(R CMD config exit 127), `package-toolchain`, `verify-package` both
passes (133 s and 110 s), `-e pkg conda-package` (r-zig-slim
h41cfa24_9, r-zig-compilers and r-zig-build-tools h3c217e4_9,
r-zig-toolchain h80fa0fb_9), `conda-consume` (four envs), the upgrade
test from universe's `_8` with pixi: OK (rzig's five other names equal
rzig once their ad-hoc signatures are removed, as phase 4 found). No
failure that could be the Falcon agent's.

#### Phase 7 record: the user's decisions of 2026-10-21

AMENDMENTS.md's "User decisions 2026-10-21", after the 2026-10-20 runs
(kappa's F1: verify-tree rejected the pkgconf files in a conda env's
TC/usr; F2: with Git for Windows' usr\bin before an activated conda
env, Git's sed wrote tmp.def from offset 0 and R CMD SHLIB exited 0 with
no DLL). All the recommended options:
- D0 (a): pkgconf leaves phase 7 (Am1, Am2 and Am16 withdrawn, Am3
  moot). The tree's usr/bin ships pkg-config 0.29.2 with its glib
  closure; conda's TC holds no usr/ (F1 gone, verify-tree unchanged);
  pixi.lock is phase 6's again; ncdf4 and RPostgres are expected
  failures again (KN d, i). The pkgconf follow-up is TODO.md's "After
  phase 9: pkgconf from source" (moved after phases 8 and 9 by the
  user, 2026-10-22).
- F2 (b): the env's MSYS dir after the group's usr/bin, in Rcmd_environ
  and in sessions, on both channels (B25's note has the evidence for
  both channels and for the session's spelling without "..").
- MSYSTEM (a): recorded (B25 here, README's line); MSYSTEM is not set.

Found while implementing them (kappa):
- The toolchain build stopped on libglib (LGPL, "its recipe lists no
  source"): a rattler-build output of a staging output keeps its sources
  under `finalized_cache_sources`. `readUpstream` reads them when
  `finalized_sources` is empty; usr/SOURCES then names glib-2.90.0's
  tarball and the glib feedstock.
- R's own command search rejects a PATH entry whose ".." shortens it by
  more than ten characters (B25's note): the first spelling of patch
  0014's second entry, `R_HOME/../../usr/bin`, made R CMD SHLIB say
  "'make' not found" in a conda-shaped tree; 0014 now spells it
  `dirname(dirname(R.home()))/usr/bin`.

Measurements (kappa, 2026-10-21):

| what | value |
|---|---|
| `usr/bin` | 140 files, 24,891,268 bytes (the plan's probe: the same); `usr/` 180 files, 25,896,285 bytes; 23 packages in usr/SOURCES, 23 LICENSES/ directories |
| build-tools `.zip` | 17,989,545 bytes, 199 members (2026-10-20 with pkgconf: 16,386,817, 192; phase 6: 5,401,812) |
| the toolchain tree | 19,803 files, 30 packages; verify-toolchain 100 s, "33 tools run with PATH = System32; make 4.4.1"; toolchain step 171 s |
| pkg-config 0.29.2 in TC | `--variable pc_path pkg-config`: TC/usr/lib/pkgconfig and TC/usr/share/pkgconfig (neither exists): PKG_CONFIG_PATH alone; btPc: `--libs` gives `-lbtpc_pub -lbtpc_priv` (Libs.private without `--static`), the prefix redefined and the space escaped |
| verify-package (one pass, the toolchain pass: ZIG_BIN = fetch-zig's zig) | 340 s |

Tests (2026-10-21; `phase7m2/implementer2/RESULTS.md`):
- gamma (linux-64): `zig fmt --check`; toolchain-test with both zigs
  (34/34 each, after the staging-output case); rzig-test with both
  zigs (162/162; parity 125/59/34/0); the default chain on the final
  code: lock-check, rzig-test 56 s, toolchain-test, toolchain,
  verify-toolchain, build 151 s (0001-0014 with -F0, no fuzz or offset),
  smoke, verify-tree, hermetic (exit 127 with the text),
  package-toolchain, verify-package both passes (299 s; its `==` lines
  equal 2026-10-20's but for the base archive's bytes), conda-package
  (the four `_9`, each "all tests passed!") and conda-consume (four envs;
  its OK lines equal 2026-10-20's): every step exit 0. The toolchain
  tree's 19,590-file list (both zigs) is byte-equal to 2026-10-20's;
  libR.so, bin/exec/R, base's Rprofile and rzig equal 2026-10-20's by
  sha256. That chain ran while the code still changed; test2-gamma
  (`phase7m2/test2-gamma/RESULTS.md`) ran it again on git diff 1cf7ce78
  from start to end, with the same results, plus the upgrade from
  universe's `_8` (pixi, conda, micromamba), actionlint and the
  pkg-config closure's licences in kappa's build-tools zip.
- kappa (win-64), on the final code but patch 0014's spelling: build
  (677 s), smoke, verify-tree, hermetic (R CMD config exit 127, no "is
  not recognized"), toolchain and verify-toolchain (above),
  package-toolchain, verify-package's toolchain pass: scenario 1 with
  both PATH entries under R CMD and in sessions (unset, empty and set
  R_CUSTOM_TOOLS_PATH), scenario 3 with PATH = bin\x64 + System32 (the
  check, btTools 21 steps, btPc, nm, the clash with Git's msys-2.0.dll
  3.6.5: Git first with MSYSTEM=MINGW64, `uname -s` MINGW64_NT, btMix
  ran Git's diff and cygpath, no MSYS failure), every phase 6 block, the
  no-zig preflight. The F2 probe on a conda-shaped tree (the base zip,
  binutils/ alone in TC, `Library\usr` and `\etc` junctions to an
  env's m2 dirs, gmp and mpfr from a libraries env): with Git first and
  with no MSYS dir on PATH, rzig's check under R CMD found the env's make
  and sh, R CMD sh's `command -v` gave the env's sh, make and sed, and R
  CMD SHLIB failed "'make' not found" (the ".." finding, fixed above).
- Not run in that round (kappa's disk: another user's files in
  AppData\Local\Temp took C: to 0.3 GB free while round 5 rebuilt R):
  the final 0014 on Windows, the four win-64 conda packages,
  conda-consume and verify-tree on a win-64 conda env. All ran after the
  user cleaned kappa, the next two bullets.
- kappa (win-64), 2026-10-21 after the cleanup, the final code (git
  diff 1cf7ce78, `phase7m2/build-kappa/RESULTS.md`): build 486 s (0014's
  final spelling: Rcmd_environ:47 `${R_HOME}/../../usr/bin`, the
  Rprofile's `dirname(dirname(R.home()))`), smoke, verify-tree,
  hermetic, toolchain (usr/ 180 files, no pkgconf file) and
  verify-toolchain (33 tools), verify-package both passes (676 s;
  scenario 1: the session's second entry `<top>/Library/usr/bin`, no
  `..`, never created; scenario 3: btPc on 0.29.2, Git first with
  MSYSTEM=MINGW64 all seven packages, the clash "no MSYS failure"), and
  conda-package: the four win-64 `_9` (slim h9490d1a, compilers and
  build-tools h5f95ccc, toolchain h98fa296), each "all tests passed!",
  build-tools' F2 line "under R CMD the check finds this env's make and
  sh: OK"; no output has TC/usr/, TC/etc/ or a pkgconf file.
- kappa, the same artifacts (`phase7m2/test2-kappa/RESULTS.md`):
  verify-bundle again (834 s); B39's 33 names; R CMD check's nm (a NOTE
  under rzig build: no symbols.rds, feat-zig-pkg-build PLAN.md:543; OK
  through make); a conda env from the `_9` packages in five PATH modes,
  0 assertion failures each: with Git's usr\bin first and
  MSYSTEM=MINGW64, Rmpfr, data.table and stringi link and make their
  DLLs, and `R CMD SHLIB t.c` makes t.dll (F2 fixed); unactivated, R CMD
  finds the env's make and sh and outside R the check names them as
  installed in R's environment; ncdf4 fails with KN d in each mode;
  conda-consume's four envs; the upgrade from universe's `_8` to `_9`
  with pixi and with conda, verify-tree rc 0 on the fresh and both
  upgraded envs (F1 gone); KN's 38-target set 30/38, equal to KN's M
  row by row (a gsl, b hdf5r, c igraph, d ncdf4, e ragg, f Rhdf5lib, i
  RPostgres, j s2, each with KN's cause).
- omicron: not run again. Changed since its run (2b60018b) and used on
  macOS: build.zig (rcmdEnviron's Windows lines and comment), patch 0014
  (Rprofile.windows, not installed on unix), zigbuild/toolchain/build.zig
  (`readUpstream`'s fallback, the Windows usr copies), conda.zig (tests),
  check.zig (a comment), verify-bundle.sh, verify-toolchain.sh and
  verify-tree.sh (Windows blocks and comments), recipe.yaml and
  test-build-tools.R (Windows parts), pixi.lock (win-64 entries only).
  gamma's linux runs cover the shared code.

#### Phase 7 record: what stays open

- CI, after the push (labels full-ci and upstream-zig): the core tier,
  the full matrix, conda-package's five legs (win-64:
  test-build-tools.R's Windows block, its R CMD check of an unactivated
  env, conda-consume's four envs), the upstream-zig legs, and the stress
  dispatch (L a): `gh workflow run stress.yaml --ref
  feat-standalone-build-tools-windows -f oses='["windows-latest"]' -f packages='g3
  g4' -f trace=true -f shared_cache=false -f msys_from_tree=true -f
  distribution=both -f channel=local`, read row by row against
  38569895172; ncdf4 and RPostgres stay expected failures. Phase 7 is
  "pending CI" until those runs pass.
- After the merge: `gh variable set CONDA_PUBLISH --body true`, `pixi
  run ci-trigger`, then phase 4's post-publish check with `_9`; the
  CONDA_PUBLISH notes in build.yaml, pixi.toml and README are reworded
  then. Done: phase 7 merged as #34 (2026-11-05), and the queue (#28 to
  #35) was published as `_9` on 2026-11-05 (build.yaml dispatch 41942729382 on main, CONDA_PUBLISH set for it and deleted after the check;
  the dispatch ran on #35's merge, 1e5c7bf, at 00:37 UTC, before #36
  and #37 merged, so those two publish with `_10`, phase 9;
  that run's windows-latest default leg failed, fixed by #38 and #39,
  while its five conda-package legs passed and published). The variable is a release switch (the user's
  option c, 2026-10-27): set for a bump's publish dispatch, deleted after
  its check, so a merge without a bump uploads nothing; build.yaml,
  pixi.toml and README say so.
- Next work (user, 2026-10-22): phases 8 and 9, then pkgconf from
  source (TODO.md), a separate PR, then the zig 0.17 port, then Windows
  on ARM.
- feat-tier1-engine (its PLAN.md; it replaces PR #27's shared runner):
  after the queue merges. Its slot beside phase 8 is the user's.
- Follow-ups for the user (not phase 7): no `ld` anywhere (winch, C6);
  R's Windows manifest for non-ASCII paths (Am12) is fix-r-utf8-manifest,
  merged before phase 7 and published with `_9`; m2's behaviour past
  MAX_PATH (UNVERIFIED, Am12); R's SearchPath slack for ".." in PATH
  (run.c, recorded, worked around by spelling).

### Phase 8 — the base's runtime files: places and records

Goal: the base's third-party runtime files sit where B27 says, with
their licences and sources (B33).

Decisions (answered): B27 (a), B33 (a).

Steps:
- unix: the CA bundle at `<top>/ssl/cacert.pem`; etc/Renviron's
  `R_ZIG_CA_BUNDLE` follows; patch 0011 unchanged; make-wheel.py's check
  (`has_ca` in its main) follows.
- Windows: fontconfig at `<top>/Library/etc/fonts`; `FONTCONFIG_PATH`
  moves out of etc/Renviron.site to a place R reads under `--vanilla`
  (find which first).
- `<env dir>/share/licenses/<package>/` and `SOURCES` for every vendored
  package, from the conda packages' info/licenses and conda-meta; the
  wheel's dist-info/licenses the same; verify-tree requires an entry for
  every vendored file.

Tests: scenario 1 on every OS (TLS with the shipped bundle, an svg
device with fonts, also under `--vanilla` on Windows, tcltk on full and
Windows), wheel-test's TLS check, verify-tree.

Done (2026-11-07; phase8/PHASE8-IMPLEMENTATION.md): as above, except
Windows. R on Windows never reads fontconfig's configuration (its cairo
device picks fonts through Win32), so the tree ships none and sets no
`FONTCONFIG_PATH` (open point D a). unix sets `FONTCONFIG_PATH` in
etc/Renviron, not in the launchers (G a). The records are written by
zigbuild/toolchain/build.zig `-Dbase`, the groups' conda-meta reader and
SOURCES writer (A a).

### Phase 9 — finish

Decisions (answered): B14 (a), with B37 (a).

Steps:
- The build number per B14 (a): a bump here only if a package changed
  since the last PR that bumped. conda-package on all five platforms.
- feat-no-host-paths PLAN.md: "What remains" 3 points here; the T record
  and the OpenMP note (467-470) updated.
- This PLAN: status and records with dates and test results.
- An upstream-zig label run; a last round on linux-64, omicron (both),
  kappa and CI; hand the commit and PR commands to the user.

Done (2026-11-08, branch chore-phase9 from main e409bae, pixi.lock
fbb64b7b..., unchanged):
- Build number 9 to 10. universe's newest is `_9` on all five subdirs.
  `_9` was built from #35's merge (dispatch 41942729382, 00:37 UTC on
  2026-11-05), before #36 and #37 merged, so they publish here (earlier
  records said #28 to #37 went into `_9`; corrected). linux-64 `_9`
  against the local `_10`: r-zig-slim gains
  lib/R/bin/toolchain/dso_fini.o (#37), loses
  share/zig/rpkg/build_t1.zig (#36), and its launchers (bin/R,
  bin/Rscript, lib/R/bin/Rscript) lose the `FONTCONFIG_PATH` lines
  (phase 8's G a; PHASE8-IMPLEMENTATION.md section 6 corrected: conda's
  fontconfig defaults to the env's etc/fonts, checked with fc-match on
  linux and macOS). Its depends are `_9`'s, `icu >=78.3,<79.0a0`
  included. The other three packages change only their exact pins.
- feat-no-host-paths PLAN.md: an update note at the top, What remains 3
  done, phase T superseded by the layered model, the OpenMP note says
  where the headers are now (B22, B40; phase 3's C14).
- Tests (conda-package, then conda-consume): linux-64 (gamma), osx-arm64
  and osx-64 (omicron, Rosetta), win-64 (kappa): all ok. Each
  conda-package ran its four packages' tests ("all tests passed" four
  times). The R trees did not change since phase 8's round and PR
  #42's CI (31 checks green on 50a3aca), so no tree was rebuilt by hand.
- CI: PR #43 with `full-ci` and `upstream-zig` (run 42605096793 on
  228af6a): 31 checks passed, including the six upstream-zig legs
  (default and toolchain on ubuntu-latest, macos-latest and
  windows-latest); 4 matrix rows skipped, as on every PR.
- Published (2026-11-09): #43 merged as 4e2b015. The user set
  CONDA_PUBLISH and ran the `ci-trigger` dispatch (build.yaml run
  42644467377 on main): all 26 jobs passed, packaging skipped. The
  post-publish check (PHASE4 section 7): `conda-channel-list` shows the
  four `_10` files on all five subdirs. In a fresh universe-only pixi env
  on linux-64 (fresh caches), `pixi add r-zig-toolchain` resolved all
  four packages at `_10`, recipe/test-toolchain.R passed every check, and
  the launchers have no `FONTCONFIG_PATH`. The user then deleted
  CONDA_PUBLISH.

## Verification

What must stay green:
- every build.yaml leg (default, full, openblas, minimal, Windows):
  rzig-test, build, smoke, contract, check; the default and minimal legs
  also verify-tree, hermetic and verify-package (build-r.yaml:83, 97,
  110); minimal also wheel and wheel-test (build-r.yaml:117);
- the new `toolchain` job (B31);
- the conda-package jobs with their tests;
- the upstream-zig legs, on the PR label.

verify-bundle's three scenarios, from the archives, freshly extracted
into one directory, `ZIG_BIN` unset. unix runs under
`env -i HOME=<tmp> PATH=/usr/bin:/bin`; Windows runs from cmd.exe with
PATH set to `R_HOME\bin\x64;C:\Windows\System32`.

1. **Base alone.**
   - R starts; the flavor's capabilities; TLS with the shipped bundle
     (unix); tcltk on full and Windows.
   - An R-only package installs; `install.packages(Ncpus = 2)` falls
     back to one at a time without make (patch 0006).
   - The check mode exits 127 with B35's compilers text, and a package
     with `src/` stops with the same text before configure.
   - unix, with a PATH that has no make: `R CMD config CC` names the
     build-tools group.
2. **Base + compilers.**
   - The check mode exits 0 and reports zig 0.16.0 from `TC/zig/`.
   - C, C++ (static libc++), OpenMP C in three forms and the flagless
     omp.h probe (not on minimal); from phase 5 on Windows, a package
     linking `-lsynchronization` (D6), built and loaded; from phase 6
     the Fortran checks of phase 6, which must pass on every OS (B44):
     TC/flang with no flang on PATH and no `.cfg` in the tree; the check
     mode names TC/flang; the first Fortran compile timed (a
     derived-type module through R CMD SHLIB and rzig build); the
     RZIG_PRINT_ARGV of a compile (TC/flang, the modules path under it)
     and of a split (TC/flang compiling, zig linking TC/flang's
     runtime); `omp_lib.h` through `$FC -E` (`#include`) and `$FC -c`
     (`INCLUDE`); the `fdt` package; a configure that compiles, links
     and runs with `$FC` (`fcconf`); USE_FC_TO_LINK, FLIBS and `use
     omp_lib` on two threads (not on minimal, which asserts B40's
     Fortran limit instead); the no-flang checks with the driver moved
     aside; on Windows the dry runs (no `-lc++`) and the direct `$FC`
     link and run.
   - unix uses the host's make from `/usr/bin` here; on Windows this
     scenario runs rzig's dry runs and direct compiles, since `R CMD
     INSTALL` needs make.
3. **Base + compilers + build-tools.**
   - unix: `Sys.which("make")` is `TC/usr/bin/make`;
     `install.packages(Ncpus = 2)` of two compiled packages runs it; on
     omicron no Command Line Tools make is involved.
   - Windows: ar and ranlib (and the LTO gcc-ar and gcc-ranlib) are
     rzig; the other binutils come from `TC/binutils/` (nm on every DLL
     link); from phase 7, the contract set builds and loads with PATH as
     above, sh, make, pkg-config and the rest coming from `TC/usr/bin/`.

Also in verify-bundle: the file lists (base ∪ groups = R tree ∪
toolchain tree, no overlap, nothing compile-time in the base but
Windows' Tcl/Tk headers, T1), and the existing compiles with
`ZIG_BIN=$ZIG` as a fourth pass: from phase 5, `verify-bundle.sh
build`, which the default `toolchain` pass runs after itself unless
`$ZIG` has TC/zig's bytes (the upstream legs). The build pass skips the
base alone and the no-zig check (PHASE5 open point S). flang is TC/flang
in both passes (PHASE6 open point O a); the env's flang with its cfg
keeps its coverage through contract, pkg-parity, stress and the conda
tests.

The same three scenarios on the other channels: conda (the recipe's
tests and conda-consume: r-zig-slim alone, with r-zig-compilers, with
r-zig-build-tools, and r-zig-toolchain) and pip (wheel-test: r-zig
alone, with r-zig-compilers, with r-zig-build-tools, r-zig-toolchain,
the groups uninstalled).

By hand on each machine (after phase 3; names per B17, B36 and B38):

```sh
pixi run rzig-test && pixi run toolchain-test
pixi run build && pixi run toolchain && pixi run verify-tree && \
  pixi run verify-toolchain && pixi run smoke && pixi run contract && \
  pixi run hermetic && pixi run package-toolchain && pixi run verify-package
# minimal reuses the default env's group archives: their names do not
# depend on the flavor
pixi run -e minimal build && pixi run -e minimal verify-tree && \
  pixi run -e minimal contract && pixi run -e minimal verify-package   # unix
pixi run -e wheel wheel && pixi run -e wheel wheel-test                # unix
pixi run -e pkg conda-package && pixi run -e pkg conda-consume
# upstream zig (F4), then the same tasks:
export ZIG_BIN="$(pixi run fetch-zig)"   # PowerShell: $env:ZIG_BIN = pixi run fetch-zig
# a user's view: the archives, nothing else
mkdir /tmp/sa && cd /tmp/sa
tar -xzf .../R-4.6.1-slim-linux-64.tar.gz
tar -xJf .../R-4.6.1-linux-64-compilers.tar.xz     # .tar.xz since phase 6 (B13)
tar -xzf .../R-4.6.1-linux-64-build-tools.tar.gz
env -i HOME=/tmp/sa PATH=/usr/bin:/bin RZIG_TRACE=1 \
  R-4.6.1-zig/bin/R CMD INSTALL -l lib <a package with src/>
```

## Risks

- **Two flavors in one directory.** All archives share `R-<ver>-zig/`
  (B1, B36), so extracting slim and full in the same place mixes them.
  One flavor per extraction directory; the archive names say which.
- **minimal and the shared `openmp/`.** Without B40's rule, a minimal R
  with the compilers group could include omp.h and fail at link.
- **rzig moving between conda packages.** An upgrade from the build on
  the channel (`_8` on 2026-10-11) must
  unlink r-zig-toolchain's rzig before linking r-zig-slim's.
  rattler-build's `--error-overlapping-files`
  (>= 0.76; D12 = a, warnings as errors) catches overlap between
  outputs at build time. Closed (2026-10-14): pixi, conda and micromamba
  on linux-64, pixi and conda on win-64 and pixi on osx-arm64 went from
  universe's `_8` to `_9` with no clobber and nothing left over ("Phase
  4 record: the upgrade from `_8`"; built locally as `_9` before the
  2026-10-19 decision, the PR keeps 8: the files move the same way at
  phase 7's number).
- **Unpinned flang in the published `_4`.** Installs that resolve
  r-zig-toolchain `_4` take flang-pixi's next builds (7 and 11, zig 0.17)
  when they appear; only a published build with the re-lock's exact pins
  avoids it. Those builds exist now, and `_4` resolves to them (PHASE4
  section 10, 2026-10-13); `_8` and the next build pin exact builds, so
  only a user who pins `_4` by hand gets them.
- **universe listed before conda-forge.** universe's index names
  `../conda-forge` as its base (`channel_relations`), so pixi, whose
  channel priority is strict, then reads every conda-forge package from
  prefix.dev's mirror. A new build that took a conda-forge package
  newer than the mirror cannot be installed that way until the mirror
  syncs (win-64's libcurl 8.23.0 on 2026-10-14: on conda.anaconda.org at
  15:14 UTC, not on the mirror at 16:50, there at 17:54; "Phase 4
  record: the upgrade from `_8`"). README, pixi.toml,
  conda-consume.sh and stress.R list conda-forge first. (2026-11-12:
  no longer a risk, and the order is reversed: the base relation is
  removed, and README, pixi.toml, the conda-package task,
  conda-consume.sh and stress.R list universe first, which flang-rt-zig's
  `llvm-openmp zig_*` dependency needs under strict priority;
  see chore-release-11/PLAN.md, findings 13 and 14.)
- **Size.** zig is 343-380 MB and 19,546 files per platform, flang
  144-210 MB raw; now confined to the toolchain tree and the compilers
  archive (about 131-149 MB with gzip). Measured with zig and before
  flang (phase 5, 2026-10-15): the compilers archive is 87.5-91.4 MB as
  .tar.gz (linux-64 88.1, osx-arm64 87.5, osx-64 91.4) and 101.6 MB as
  win-64's .zip; linux-aarch64 comes with CI ("Phase 5 record: the
  measurements"). With flang (phase 6, 2026-10-16): linux-64's gzip
  archive was 150.8 MB, so the compilers archive is `.tar.xz`: about
  95.3 MB on linux-64, 79.1 MB on osx-arm64 and 92.7 MB on win-64
  (B13's revisit; "Phase 6 record: the measurements").
- **The mixed zig case.** R by conda-forge's zig and packages by
  upstream zig; tested before phase 5 only by wheel-test, without OpenMP
  or Fortran. Since phase 5 verify-bundle's toolchain pass covers it on
  the default legs, every scenario with TC/zig (passed on linux-64,
  osx-arm64, osx-64 and win-64 by hand, 2026-10-15). Its cosmetic
  CC_VER mismatch and a build runner per extraction place are recorded
  in "Phase 5 record: the mixed case".
- **Windows with upstream zig.** `-lsynchronization` (Rust packages)
  failed with upstream zig 0.16.0 (feat-no-host-paths, What remains 8),
  and the compilers group makes upstream zig the standalone default.
  D6 = (b) is done by PR #19 (fix-rzig-follow-ups, 7a3004d): rzig
  renames `-lsynchronization` to `api-ms-win-core-synch-l1-2-0` for both
  zigs, and zig builds the import library from the API set's `.def`
  (that PLAN.md's "How this answers D6 b"); phase 5's verify-bundle
  builds and loads such a package with TC/zig (kappa, 2026-10-15).
  Nothing is reported upstream. `-lmsvcrt` fails with upstream zig and
  links msvcrt.dll with conda-forge's: no package tried reached it
  (PHASE5 open point L a, "Later and future checks"). A Rust static
  library in a C link needs an unwinder with both zigs (the same
  section).
- **The first compile is slow.** zig builds libc++ and compiler_rt
  into its global cache on the first C++ compile and prints about 3.4k
  warnings once; conda-forge's zig does the same with a cold cache.
  Measured with TC/zig and an empty cache (phase 5, 2026-10-15): linux-64
  15-18 s, osx-arm64 9-11 s, osx-64 under Rosetta 13 s, win-64 46 s.
  The first Fortran compile (phase 6, linux-64): 8-9 s, zig's cache
  then 44 MB. Pre-seeding is a later menu ("zig's global cache").
- **macOS without the Command Line Tools.** rzig runs `xcrun` on every
  compile; frameworks need the SDK; whether a fresh Mac opens the install
  dialog is unobserved.
- **Packages that use `$(BINPREF)` for a binutils tool** in Makevars.win
  break once the binutils leave TC's top (B24). Not surveyed.
  (2026-11-12: moot since #47: nm, objdump, strip, dlltool, windres and
  as are rzig names beside gcc.exe in `R_HOME/bin/toolchain`, so
  `$(BINPREF)<tool>` names a file again; verify-tree checks each
  `$(BINPREF)` name in Makeconf.win; feat-win-zig-binutils/PLAN.md.)
  `$(BINPREF)gcc-ar` and `gcc-ranlib` keep working (rzig, B43), and so
  do `$(BINPREF)ar` and `ranlib` (rzig's ar.exe and ranlib.exe, for
  CMake; phase 3's step 3 review).
- **AR and RANLIB through rzig on Windows** (B43). zig's ar replaces
  GNU ar for every package's static library on Windows. It is what unix
  uses already, but on Windows it was untested with R packages. Phase 3
  passed on kappa (static-library packages, tools.mk, RcppParallel's
  CMake, LTO builds; step 6's record); windows-latest runs them on the
  PR's first CI run.
- **GPL obligations.** Unmet today for make and the binutils, and
  coming for the Windows userland and pkg-config (GPL-2.0-or-later); the
  per-directory records (point 3) fix the texts, the sources mirror
  waits for the release job (B12).
- **The Windows userland** (B11: conda-forge packages, `m2-*` where
  needed). The m2 tools bring msys-2.0.dll, which may clash with a
  user's Rtools or Git for Windows (Cygwin FAQ 4.20), and
  windows-latest has shown spawn hangs with the MSYS2 set. A mix of
  native tools and MSYS2's bash is untested with R's makefiles. Phase 7
  tests all three; the risks stay recorded until it does.
- **zig-fc's split of mixed calls.** Probes that rely on flang's driver
  (`-v` output parsed for library paths) may behave differently; the
  prototype runs real configure scripts. Phase 6 (linux-64, 2026-10-16):
  `-v` prints zig's `ld.lld` line; a configure that compiles, links and
  runs with `$FC` passes (verify-bundle's `fcconf`); CMake's Fortran
  detection works, and its implicit link libraries name TC/flang's
  runtime and two archives in zig's cache. Each refusal list (the link
  options flang refuses, the Fortran options zig cc refuses) is measured
  and grows only by a host's measured refusal (PHASE6 open point E a).
  omicron and kappa (2026-10-17): the same lists, nothing added; macOS
  `-v` prints `zig ld ...`, Windows `lld-link`, and configure (fcconf,
  configure.win on Windows) passes on both.
- **Fortran on every OS** (B44). A prototype failure on one OS holds
  phase 6 until it is fixed with flang-pixi; the fix may need a new
  flang-zig or flang-rt-zig build, and a re-lock to it. Phase 6
  (2026-10-16): linux-64 passes with TC/flang alone (gamma);
  linux-aarch64's cross pre-check passes (gamma, not a gate);
  osx-arm64 and win-64 pass by hand with both zigs (2026-10-17);
  linux-aarch64, native osx-64 and the upstream legs come with CI after
  the push.
- **VCRUNTIME140.dll.** libomp.dll and zstd.dll (which R.dll imports)
  import it; a clean Windows without the VC++ redistributable is
  untested, for the base as well.
- **The message names no download place** until a release page exists
  (B12).

## Open questions (not decisions)

- Does Rprofile.windows need the build-tools PATH line too (phase 7)?
- Does conda-forge's win-64 uutils-coreutils install one .exe per tool,
  and which of B39's tools have native win-64 builds on conda-forge
  (phase 7)?
- Does `R CMD INSTALL --use-LTO` work on Windows with zig? No gcc-nm
  ships (B43-2), and neither GNU nm nor gcc-nm reads zig's LLVM bitcode
  objects; the stress suite shows whether any package needs it.
  (2026-10-11, kappa: it does since rzig drops -flto at Windows links,
  which zig 0.16.0 cannot link; without a `.def` the missing gcc-nm
  leaves auto-export to lld. Phase 3's step 6 record.)
- pip upgrade and uv tests for the wheels.
- Where is the release published, and how does the message name it?
- Is passing `-fintrinsic-modules-path` twice harmless, and where does
  the conda triple come from? Does flang find its resource dir without
  Windows' `Library/`? (2026-10-16, phase 6: harmless, the same
  directory twice exits 0 (PHASE6 PP); the triple is the directory
  scan of open point D a; without `Library/` flang's
  `-print-resource-dir` follows the binary: checked on linux-64,
  osx-arm64 and, without `Library/`, on win-64, 2026-10-17.)
- Is flang-pixi's docs/19, its file lists and its carve script committed
  now? (2026-10-16: yes, flang-pixi eaa07ba; the carve script ran as
  phase 6's cross-check.)
- Can rattler-build 0.76.1 (pixi.lock) make an output with no files that
  does not inherit the staging build (B28 a)? (2026-10-14, phase 4: not
  needed. The group packages and the metapackage `inherit` with `files:
  []` and package only their test file, as rattler-build's own
  staging-empty-files test does; the form without inherit stays
  untested, Cc17.)
- Which make wins on PATH in a win-64 conda env today: m2-make or
  conda-forge's make (r-zig-toolchain `_4` depends on both)? (2026-10-14:
  m2-make, PHASE4 SC §5; phase 4's r-zig-build-tools depends on m2-make
  only, Cg7.)
- Does zig's dlltool accept the GNU long options and the `--as`
  Makeconf.win passes (B24's routing check, phase 3)? (2026-10-11,
  kappa: yes, in their two-word forms, and `--as` is ignored; the
  `--opt=value` forms are not; phase 3's step 6 record.)
- Do CRAN packages' Makevars.win use `$(BINPREF)` for a binutils tool?
  (2026-11-12: no longer needs an answer: since #47 every binutils name
  `$(BINPREF)` can form is an rzig file beside gcc.exe.)
- Does flang-rt-zig 10's win-64 archive still need no `-lc++` (phase 6
  checks it)? (2026-10-16: statically yes, 131 external names and none
  from the C++ runtime (PHASE6 ST §4); phase 6 drops `-lc++`, and on
  kappa R, `check`, quadprog, Rcpp, minqa and the Fortran packages pass
  without it, 2026-10-17.)

## Later and future checks

- **Full-only features as add-on R components** (the user's caveat): see
  which full-only features can become add-on components, starting with
  tcltk, and drop the separate full build only if readline and NLS can
  be settled.
- **Less make.** Windows still needs sh and make for R's make-based
  installs, for now. The longer-term aim is to depend less on make and
  on shell scripts (feat-no-host-paths' long-term "no shell scripts" and
  its in-process installer item).
- **Optional extras.** A third group, added only when the stress suite
  (.github/devdocs/feat-stress-suite/) shows a package needs a tool the
  minimal build tools lack. The suite starts now, in parallel (D15 = a);
  pkg-config on Windows is no longer a candidate, since it ships in
  `usr/bin/` (B43). The user's answer to stress round 1's decision 16
  (2026-10-08): cmake joins the extras group on every OS. RcppParallel's
  bundled TBB, Rhdf5lib (biocmake), nloptr (unix), s2 (linux; Windows'
  bundled path) and arrow from source (linux and macOS) build with it.
  Every run had the env's cmake, so the run shows the need, not what
  happens without it.
- **Reassess after the stress suite** (B39, B43): which of B39's tools
  are really needed, whether pkg-config and objdump are needed or
  already covered by zig cc and rzig, and whether a gcc-nm from
  conda-forge is really needed (B43-2). Round 1 (2026-10-08) answered
  pkg-config, objdump and gcc-nm (B43's note); B39's list still needs a
  run with only its tools on PATH (B39's note). (2026-11-12: objdump
  and nm are rzig's own since #47, and pkg-config is pkgconf built from
  source since #45, in the build-tools group's `usr/bin/`; B39's run is
  still open.)
- **The C++ ABI boundary** (stress round 1's A1 and A2; the user's
  answer to its decision 12, 2026-10-08: recorded now, designed after
  the standalone work). Packages built by zig use its static libc++. On
  linux conda-forge's C++ libraries use libstdc++: magick, sf, terra,
  gdalraster and protolite fail to load against them (and V8 to link
  its downloaded libstdc++ libv8). On Windows they are MSVC builds,
  which no MinGW toolchain links; their C APIs work. macOS has no
  mismatch (libc++ on both sides). The design is open, for example a
  libstdc++ mode on linux for boundary packages, or MinGW builds of
  those libraries on Windows.
- **zig's MinGW headers lack the WinRT headers** (stress round 2's Z12;
  the user's answer to its decision 2, 2026-10-09: recorded only). s2's
  `configure.win` builds its bundled abseil whenever `pkg-config
  absl_base` fails, as for a Windows user without a libraries env.
  abseil's `time_zone_lookup.cc` then includes
  `windows.globalization.h`: zig's `_mingw.h` defaults `_WIN32_WINNT` to
  0xa00, so `sdkddkver.h` sets `NTDDI_VERSION` above `NTDDI_WIN10_NI`.
  zig 0.16.0's `any-windows-any` (conda-forge's and upstream's, the
  standalone's zig, B4) has none of mingw-w64's `windows.*.h` WinRT
  headers. So s2, and sf and lwgeom behind it, do not build there. Two
  candidates, untested beyond a one-file compile: ship the WinRT headers
  abseil needs where rzig adds the tree's headers, or define
  `NTDDI_VERSION` below `NTDDI_WIN10_NI` (which hides newer Windows APIs
  from every package).
- **CMake and Homebrew on macOS** (stress round 2's H2; the user's
  answer to its decision 10, 2026-10-09: implemented on branch
  fix-stress-round1, build 7). CMake's `Platform/Darwin.cmake` puts
  Homebrew's prefix (`brew --prefix`, else `/opt/homebrew` on arm64)
  before the others in `CMAKE_SYSTEM_PREFIX_PATH`, whatever PATH says.
  Round 2's arrow linked `/opt/homebrew/lib/libsnappy.a`. Every macOS
  tree ships `etc/r-zig.cmake`, which leaves out the prefixes
  Darwin.cmake adds for a package manager (`/opt/homebrew`,
  `/usr/local`, `/opt/local`, `/sw`), and `etc/Renviron` makes it
  `CMAKE_TOOLCHAIN_FILE`'s default (unix R has no Rcmd_environ, where
  S15 sets CMake's generator on Windows). So host libraries do not leak
  into packages through CMake's search. The standalone layout keeps the
  file and its setting. Not covered: a package's own `brew --prefix`
  call (arrow's OpenSSL, with brew on PATH) and pkg-config's own search
  path.
- **The rest of the Windows binutils through rzig** (B24): ar and
  ranlib go through rzig now; dlltool, windres, strip, nm and as follow
  as rzig can serve them (phase 3's check, then each zig release).
  LLVM's tools in `binutils/` stay the other way out of GPL-3 binaries.
  (2026-11-12: done in #47: dlltool, windres, strip, nm, objdump and as
  are rzig names; there is no `binutils/` directory any more;
  feat-win-zig-binutils/PLAN.md.)
- **A really slim Windows slim** (B42, the user's note of 2026-10-08):
  Windows slim has full's content for now; make it really slim later.
  It relates to C1 (Windows minimal) and the full-only add-on check.
- **GNU make built with zig** for all five platforms (B7 b).
- **The release job** (B12): `v*` tags, GitHub Release, GPL sources
  mirrored.
- **The toolchain in an environment of its own** (feat-no-host-paths
  item 4, `R_ZIG_TOOLCHAIN_ENV`; D14 = a: later): the group layout under
  one root is meant to serve it as it is.
- **Windows minimal and the Windows wheel** (feat-no-host-paths item 2;
  C1 = a, C2 = a, C3 = a): after phase 7, whose userland they share.
  Windows minimal drops ICU, cairo, Tcl/Tk and OpenMP and keeps
  png/jpeg/tiff and NLS; a wheel without compile support comes first.
- **The zig 0.17 wave** (B18 = a). build.zig's atexit workaround stays
  in the port, since no upstream report is filed (A2'). (2026-11-12:
  done in #46, 0.17 only; the atexit exclusion stays in build.zig;
  feat-zig-017/PLAN.md.)
- **zig's global cache.** Measure the first C++ compile with upstream
  zig in phase 5; then put pre-seeding the cache to the user as a menu.
  Measured (2026-10-15, "Phase 5 record: the measurements"): the first
  C++ compile with an empty cache is a libc++ build into zig's cache, as
  slow and as loud with conda-forge's zig as with upstream's. The same
  menu decides where rzig's zig keeps its cache: a standalone R's zig
  and a conda R's (both 0.16.0; 0.17 since #46, 2026-11-12) share zig's default cache today, which
  env.sh's comment says can mix objects (PHASE5 open point N a: not
  seen to break a package, no rzig change). The first Fortran compile
  with TC/flang and an empty cache (phase 6, 2026-10-16, linux-64): 8-9
  s, zig's cache then 44 MB, warm 0 s; the build's zig with env.sh's
  cache 6 s ("Phase 6 record: the measurements").
- **The groups' licence completeness** (PHASE5 Cc5, Cg2; a menu with
  phase 6's licence review): zig/ ships upstream's licence set, whose
  gaps are LLVM's attribution in the binary, Apple's SDK headers and
  libSystem.tbd, and the NetBSD and OpenBSD headers ("Phase 5 record:
  the mixed case and the facts the critiques added"); flang/ joins in
  phase 6. B33 covers the base's runtime files only, so no phase picks
  this up otherwise. flang/ (phase 6, PHASE6 Cc12, checked): its
  LICENSES hold the LLVM project's Apache-2.0 WITH LLVM-exception text
  for flang-zig and flang-rt-zig; no driver has zlib or zstd in it; the
  linux driver carries zig's static libc++/libc++abi (LLVM's text, the
  one flang/ holds) and zig's compiler_rt (MIT, the text in
  TC/zig/LICENSES/ziglang, in the same compilers archive). So a flang/
  shipped alone would need zig's MIT text too.
- **The lld-zig pin in r-zig-compilers** (PHASE6 Cg5, open point Q a;
  not acted on): since phase 6 nothing of ours links with lld-zig, so
  r-zig-compilers' explicit `lld-zig ==23.1.1 *_5` pin is redundant
  (flang-zig run-depends on lld-zig anyway). Dropping it is a dependency
  change, the user's to decide.
- **zig/ on the legs that never read it** (Cg6; a menu): build-r's
  build-only legs, stress and the local dev chains download and unpack
  the compilers archive (or fetch the wheel) though only verify-package
  reads zig/. Options: a toolchain artifact without zig/ for them, or
  keep one artifact; with phase 5's unpack timings.
- **upstream-zig.yaml reusing build.yaml's toolchain artifact** (Cg9; a
  menu): since phase 5 both carry the same TC/zig, so the label run
  builds the same tree again.
- **verify-package's build pass** (Cg1; a menu): keep it, reduce it to
  the package blocks (PHASE5 F b), or run it only under full-ci; with
  CI's per-pass times against ea7e6ee's.
- **The toolchain artifact's compression** (PHASE5 T a; a menu):
  `compression-level: 0` on toolchain.yaml's upload, since the archives
  are already .tar.gz/.zip; with windows-latest's step times (Cc7).
- **Rust static libraries and an unwinder on Windows** (phase 5 step
  3b; recorded, its option (a)): a Rust static library built for the
  r-windows clang-x86_64 bundles (gifski's prebuilt one) fails a C link
  through gcc.exe with 9 undefined `_Unwind_*` and
  `_GCC_specific_handler` symbols, with both zigs. GNU gcc with
  `-static-libgcc` links libgcc_eh and llvm-mingw's clang libunwind; zig
  cc does neither for a C link (a C++ link gets libunwind, which is why
  magick's librsvg links). `SHLIB_LIBADD = -lunwind` in a user's
  Makevars.win fixes it with both zigs. When it comes back: a windows.zig
  rule adding `-lunwind` to image links through gcc.exe, or leave it to
  packages.
- **`-lmsvcrt` with upstream zig on Windows** (PHASE5 open point L a):
  upstream zig 0.16.0 has no msvcrt import library and conda-forge's
  links msvcrt.dll into a UCRT R. No package tried reached it (magick
  with Rcpp, magrittr and curl; gifski); map `msvcrt` to `c` in
  `mingw_names` only when a real package needs it.
- **macOS without the Command Line Tools.** Observe a Mac that never had
  them (does running `xcrun` open the install dialog?); then put rzig's
  `xcrun` handling to the user as a menu. `xcode-select -p` exits 0
  under the simulation, so it cannot tell.

## History

Phases 0 and 1 of the single-archive plan (afd59a2), done and recorded
in 9bbce0b (#15). The two records below are copied verbatim from
9bbce0b's PLAN.md (lines 349-526 and 1345-1413). Inside them, "Design
N", "decision N", "Phase T" and line numbers refer to that plan and to
the code at that commit. The superseded design text (old Designs 1-10,
the old phases 2-9, the old 0.17 section) is not kept; its facts that
still hold are in "What exists today" and "Facts the design depends
on", and the decisions are mapped here.

### Old decisions and their status

| Old | Menu ID | Question | Status under the layered model | Now |
|---|---|---|---|---|
| 1 | B1 | Layout: overlay archive or a separate toolchain directory | Resolved (user, 2026-10-07): (a) one top directory for all archives, widened to one archive per group | B36 (the top directory's name) |
| 2 | B4 | zig's artifact | Narrowed to the standalone compilers group; answered 2026-10-08: (a) | B4 |
| 3 | B5 | Where zig enters the tree (`-Dbundle-zig` in every tree, ...) | Changed: replaced by where the groups are assembled; zig in every R tree is option (b) there | B30 |
| 4 | B2 | rzig's lookup | Resolved (user): (a) | B34 (refinement), B35 (the message) |
| 5 | B7 | make on unix | Partly resolved by B20: make ships in the build-tools group for every flavor; B7, B23, B25 answered 2026-10-08: (a) | B7 (unix source), B23 (place), B25 (how R finds it); Windows make with B11's conda-forge packages |
| 6 | B8 | Fortran | Resolved by B20: flang's compile set in `TC/flang/` | B9 (source), B44 (every OS must pass), B29 (PyPI) |
| 7 | B10 | OpenMP headers and libomp.lib | Resolved by B22 = (a), old option c; the old recommendation (base) is reversed | B40 (minimal), B41 (conda) |
| 8 | B11 | Windows | Partly resolved by B20: Windows splits too; `usr/bin/` and `binutils/` are in the build-tools group; answered 2026-10-08 (the user's own: conda-forge packages, `m2-*` where needed) | B11 (source), B39 (the list), B24 (binutils), B43 (unshipped tools), B25 (PATH) |
| 9 | B6 | Which zig builds released standalone R | Unchanged; answered 2026-10-08: (a) | B6 |
| 10 | B12 | Publishing | Now per group; answered 2026-10-08: (a) | B12 |
| 11 | B13 | Compression | Now per group; answered 2026-10-08: (a) | B13 |
| 12 | B14 | conda build number | Changed: "no bump" is no longer possible, and the bump follows how the plan lands; answered 2026-10-08: (a) | B14, B37 |
| 13 | B15 | The preflight's Makeconf-CC fallback | Merged: with rzig in the base the whole preflight test changes, and the fallback is dead code in every installed tree | B26 |
| 14 | B16 | Recipe which/sed/grep cleanup | Done (phase 1, 9bbce0b); omicron, kappa and CI's macOS and Windows jobs still to pass | History |
| 15 | B17 | Names | Group archives carry no flavor; answered 2026-10-08: (a) | B17, B36, B38, B42 |
| 16 | B3 | Which flavors get a toolchain pair | Moot: one toolchain per platform (point 6); its leftover is which base flavors CI packages | B31 |
| 17 | B9 | Where build.zig gets the flang files | Unchanged; answered 2026-10-08: (a) | B9 |
| 18 | B18 | The zig 0.17 wave | Facts updated (flang-pixi 6/5/10 are 0.16 builds, PyPI has 0.17.0 without win_amd64); answered 2026-10-08: (a) | B18 |
| new | B19 | rzig's place | Resolved (user): (a) the base, every channel | phases 2-4 |
| new | B20 | The group design | Resolved (user): approximately (a); point 3 also settles the per-directory records | "The toolchain groups", B39 |
| new | B21 | External runtime libraries | Resolved (user): (a) the base | B27 (where) |
| new | B22 | OpenMP compile files | Resolved (user): (a) the compilers group | B40, B41 |

The old prerequisites:
- rzig's `-mcpu=baseline`: implemented in #14 (open).
- The symbol and link check before flang-pixi published flang-rt-zig 10:
  moot, since build 10 is a zig 0.16.0 build and passed the re-lock's
  tests. The same check now comes before our pins move to flang-rt-zig
  11 (B18).

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

### Phase 1: the recipe's host which/sed/grep cleanup

What it did (old Design 11, condensed): build.zig had baked
`$CONDA_PREFIX/bin/which` into Sys.which (`@WHICH@`) and `$PREFIX/bin/sed`
into bin/R; recipe.yaml's unix host which, sed and grep were left over
from that. build.zig now maps every `@ZR_CONDA@/bin/<tool>` to the bare
name, patch 0002 replaced Sys.which, and patches 0007 and 0008 made
bin/R and Rcmd sed-free. Phase 1 deleted the host block and its comment,
mkRbase's dead `@WHICH@` replace and the build requirement `which`, and
corrected two stale comments. Neither package changed, so it needed no
build-number bump.

Status after the record below: committed in 9bbce0b (PR #15). Still to
pass: `pixi run -e pkg conda-package` on omicron (osx-arm64, osx-64) and
kappa (win-64); CI's osx-64 and win-64 conda-package jobs; and the seven
macOS and Windows build legs. All nine of those CI jobs failed on #15
(run 37628782590) at `pixi install`, with a 404 on flang builds that
flang-pixi deleted, as confirmed in the job logs on 2026-10-07. #14
failed the same nine. They can pass once the re-lock is on main and
merged in.

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
