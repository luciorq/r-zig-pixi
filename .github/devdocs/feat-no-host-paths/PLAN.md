# feat-no-host-paths — no build-machine paths, and a base R that installs without a toolchain

**Status (2026-10-01).** Phase A done on all five platforms (the
hermetic tier-0/1 check runs in CI everywhere). Phase T done for conda
and pip (`r-zig-slim` + `r-zig-toolchain`, `r-zig` + `r-zig-toolchain`);
the standalone tarball is not split yet. libc++ and the flang runtime are
static everywhere. Next: phase F (see "Simplicity review and phase F"),
which collapses the post-build tree surgery into `zig build` before T's
standalone part, B (now F3), C, D, S and P. R source references are to R
4.6.1 (`build/R-4.6.1/`).

## Goal

1. **No path from the build machine in anything we ship.** Every tool R
   refers to is R's own implementation, a binary we ship, the conda
   environment's own binary, or a name looked up when it is used. Never
   a path configure happened to find on the capture machine.
2. **A base package that runs R and installs packages without
   compiling.** R-only source packages and pre-compiled binary packages
   install with no toolchain present. The toolchain (compilers, make,
   and on Windows the POSIX userland) becomes a separate package.
3. **Long term: no shell scripts** in starting R or in `R CMD`.

Agreed so far:
- conda packages use the environment's binaries and vendor nothing;
- the standalone tree and the wheel vendor as little as possible;
- optional tools (browser, PDF viewer, pager, TeX) are found when used;
  shims that make those lookups robust come in phase B.

## Principles

- **In-process before external.** If R calls something as a function,
  it is implemented inside R (R code or a C `.Internal`). If something
  runs it by name (make running `CC`, R running `PAGER`, a user running
  `R`), it has to be an executable, and those are the binaries we write:
  Zig for our own tools, C for R's front-end.
- **Resolution order:** R's own implementation, then a binary we ship,
  then (conda) the environment's `bin/` reached from R_HOME as
  `${R_HOME}/../../bin/<tool>` so it works without an activated env,
  then PATH at the time of use.
- **`/bin/sh` only for shell syntax.** R's C code hard-codes it for
  every program it starts on unix today (`src/unix/sys-unix.c:582`,
  `:668`, `:784`, plus libc's `system()` and `popen()`). After phase S,
  R starts programs without it and reaches `/bin/sh` only when a
  command string written by the user contains shell syntax. POSIX
  guarantees it exists.
- **Tiers are enforced by CI, not by documentation** (see Verification).
- **One tree, built once, archived by every distribution** (added
  2026-10-01, see "Simplicity review and phase F"): `zig build` installs
  the tree that ships; conda, the standalone tarball and the wheel only
  vendor libraries and wrap it. CI tests that tree, not an intermediate
  one. No post-link binary surgery, no sed over generated files.

## Tiers

| Tier | Covers | Needed before phase A (unix) | After phase A (2026-10-01) | Target | Ships in |
|---|---|---|---|---|---|
| 0 Run | `R`, `Rscript`, `library()` | bash (`#!/bin/bash` in `bin/R` and in the Rscript emulator), `sed`, `dirname`, `readlink`, `expr`; at every start `/bin/sh` running `which` and `uname`, at exit `/bin/sh` running `rm` | `/bin/sh` for the launcher scripts (and `readlink` when reached through a symlink); nothing else is started | after phase C, nothing | base |
| 1 Install without compiling | R-only source packages, binary packages, `remove.packages()` | `/bin/sh`, `mv`, `cp`, external `tar`; `make` and `cat` when `Ncpus > 1` | `/bin/sh` only (R starting R, `R CMD` scripts); verified with strace on linux | binary packages: nothing (in-process, see "Binary packages"); R-only source packages: nothing after phase S | base |
| 2 Compile | `src/`, `configure`, `R CMD SHLIB`, `R CMD config` | zig, flang, make, `sh` plus a POSIX userland, strip/otool/patchelf | the same, from the toolchain package; without it, the compile preflight and `R CMD config` say so | unchanged | toolchain package |
| 3 Develop | `R CMD build`/`check`, `Rd2pdf`, vignettes | TeX, qpdf, gs, pandoc, tidy, nm, zip, diff, patch | found on PATH when used (bare names) | found when used, all optional | neither |

A3 leaves `readlink` in tier 0 for launchers reached through a symlink,
until the C front-end replaces the script.

**Runtime libraries stay in base.** Whatever a compiled package needs in
order to *load* belongs to tiers 0–1: libR, the BLAS/LAPACK library,
libomp (slim's `libR.so` needs `libomp.so`), libcurl, zlib and the rest.
Measured on linux-64: packages compiled here (quadprog and minqa with
Fortran, Rcpp with C++) need only `libR.so`, the BLAS library and
libc/libm at load time, because flang's runtime and libc++ are linked
statically. So Fortran and C++ binary packages load without the
toolchain. Still to confirm on macOS and Windows.

## Where R mixes the tiers

| What | R source | Fix | Phase |
|---|---|---|---|
| Every start: loading utils computes `osVersion` by running `Sys.which("uname")` and `system("uname -a")`, only to learn the OS name | `src/library/utils/R/zzz.R:71`; `sessionInfo.R:26-27` | `Sys.info()[["sysname"]]` (the `uname(2)` call, in-process). webR patches the same function | A2 |
| Every exit: R deletes its session temp directory with `rm -Rf` through `R_system()` | `src/main/platform.c:2067` | always use `R_unlink()`, already the fallback three lines below (for paths with special characters) and what Windows does | A2 |
| Every install moves the finished package into place with `mv -f` through the shell; lock backup and restore also use `mv -f` | `src/library/tools/R/install.R:1994`; `:118`, `:530`, `:1142` | use the `WINDOWS` branches (`file.rename`, falling back to `file.copy` + `unlink`) on every OS | A2 |
| Binary packages install with `cp -R .`, falling back to a `tar` pipe | `install.R:535` | `file.copy(recursive = TRUE)`, as on Windows | A2 |
| `configure` runs whether or not there is a `src/` | `install.R:1309`, before the `src/` check at `:1360` | "needs compilation" means `src/` or `configure`; the preflight names the toolchain package | T |
| `install.packages(Ncpus > 1)` writes a Makefile and runs `make -k -j`, then `cat` to show failures | `src/library/utils/R/packages2.R:899`, `:911` | install one at a time when make isn't found; `writeLines(readLines())` instead of `cat` | A2 |
| `untar()` uses Renviron's `TAR`; the `unzip` option defaults to `R_UNZIPCMD` | `etc/Renviron.in` | `TAR=internal`, `R_UNZIPCMD=internal` | A4 |
| `Sys.which()` runs `which` through `/bin/sh`, once per name | `src/library/base/R/unix/system.unix.R` (already patched by `scripts/zig-build.sh` to prefer `bin/toolchain/which`) | scan PATH in R: first match that is executable (`file.access(mode = 1)`) and not a directory. Windows already does this in C (`src/gnuwin32/run.c`, `do_syswhich`). Not `command -v`, which returns builtins such as `echo` as bare names | A2 |
| `R CMD config` evaluates Makeconf with make | `src/scripts/config` | compile tier by construction; without the toolchain it must fail cleanly, since pkgbuild and pak call it to detect compilers. A make-free version comes with the front-end | T, D |
| During an install R starts copies of itself (test load, `install.packages` running `R CMD INSTALL`) through `system()`, so through `/bin/sh` | `install.R`; `packages2.R:753` | start R through the argument-vector primitive | S |

## The tool table (phase A)

"Bare" means the name alone, found on PATH when used.

| Variable | Used by | Tier | Today | Target |
|---|---|---|---|---|
| `R_SHELL`, `SHELL` | shebang of `bin/R` (`#!@R_SHELL@`) and the `R CMD` scripts | 0 | the capture machine's `$SHELL` (`/bin/bash` on linux) | `/bin/sh`, pinned in configure-only.sh |
| `SED` | `bin/R` argument parsing | 0 | vendored `sed` | not needed: POSIX parameter expansion in `bin/R`. Makeconf's `$(SED)` is only used by `winshlib.mk` (Windows, compile tier) |
| `WHICH` | `Sys.which()` | 0 | vendored `which` | not needed (R code) |
| `TAR` | `untar()`; the fallback pipe in `install.R:534` | 1 | vendored `tar` | `internal`, in the same change as A2 (which removes that pipe; `internal` is not a command it could run) |
| `R_UNZIPCMD` | `getOption("unzip")` | 1 | vendored `unzip` | `internal` |
| `R_GZIPCMD`, `R_BZIPCMD` | `tar()` with an external tar only | 3 | vendored gzip, bzip2 | bare |
| `R_ZIPCMD` | `utils::zip()`; R has no internal zip writer | 3 | vendored `zip` | bare; a zip applet in phase B could replace it |
| `MAKE` | compiling; `install.packages(Ncpus > 1)` | 2 | vendored `make` (standalone, wheel), the env's make (conda) | toolchain package |
| `NM` | `R CMD check` symbol checks | 3 | vendored `nm` or `/usr/bin/nm` | bare |
| `PAGER` | `file.show()`, text help | 0, optional | `/usr/bin/less` | bare `less`; pager applet in B (less, then more, then built-in) |
| `R_BROWSER`, `R_PDFVIEWER` | `browseURL()`, `help.start()`, vignettes | 3 | `/usr/bin/open` (even on linux), `/usr/bin/firefox` | `xdg-open` on linux, `open` on macOS; opener applet in B |
| `R_PRINTCMD`, `TEXI2DVICMD` | printing, `texi2dvi()` | 3 | differs by capture machine | bare `lpr`, `texi2dvi` |
| `LD`, `TEXI2ANY`, `INSTALL_INFO`, `oldincludedir` | build tree only | none | differs by capture machine | pinned in configure-only.sh so every capture is identical |

After phase A, tiers 0–1 need nothing external except `/bin/sh`, and
after phase S not even that. In conda, the tools that remain external
are tier 2 and come with the toolchain package's run dependencies,
resolved under the environment
(`${R_HOME}/../../bin/`; on Windows `Library/bin`, with the m2 tools in
`Library/usr/bin`). Tier 3 stays bare everywhere.

Vendored in the standalone tree today: `bzip2`, `gzip`, `make`, `nm`,
`sed`, `tar`, `unzip`, `which`, `zip`, plus the zig shims. After A and
T, the base vendors nothing; the wheel's toolchain package ships make
(pip has no other way to provide it) and the shims.

## Packaging (phase T)

- **conda:** one recipe, two outputs.
  - base: R and its runtime libraries. No zig, flang, make or m2 run
    dependencies.
  - toolchain (for example `r-zig-toolchain`): run dependencies zig
    0.16, flang (and flang-rt to link against), make; on Windows the m2
    userland (bash, sed, grep, gawk, coreutils, make, which,
    findutils). Pinned to the exact base build. Installs the compiler
    shims into `lib/R/bin/toolchain/` (Windows:
    `Library/lib/R/bin/toolchain/`), the directory base's Makeconf
    already points at.
- **wheel:** `r-zig` drops `Requires-Dist: ziglang` and the bundled
  make. A separate `r-zig-toolchain` distribution requires ziglang and
  ships make and the shims into the same `r_zig/R/bin/toolchain/`
  directory. Two distributions can share a package directory, since
  each owns only the files in its RECORD; to prototype: whether pip and
  uv handle uninstall and upgrade cleanly.
- **Static libc++ everywhere (decided 2026-09-30),** superseding the
  2026-09-29 choice of conda's shared libc++ for the conda build: R
  itself in every variant and distribution, and every package compiled
  through the shims, link libc++ statically. Upstream zig does that by
  itself. For conda-forge's zig, whose patch links a shared libc++
  whenever `<zig lib dir>/../../lib` has one (always in a macOS conda
  env, on linux with any `libcxx` package), `zig-build.sh` and the
  zig-cc/zig-cxx shims point `ZIG_LIB_DIR` at a mirror of the lib dir
  (a real directory of symlinks, nested as `<mirror>/lib/zig` so that
  its `../../lib` is empty): `build/zig-lib-static` for R, and
  `${XDG_CACHE_HOME:-~/.cache}/r-zig/zig-lib-<key>` for the shims (made
  once per lib dir; `mkdir` is the lock for parallel make jobs).
  `zig-build.sh` also moves zig build's local cache aside when the
  mirror is on (`zig-cache/local-static-libcxx`): that cache is not
  keyed on the probe, and a warm one hands back the shared links.
  `zig cc` outside zig build follows `ZIG_LIB_DIR` on every call
  (tested). On Windows MSYS cannot make the symlinks; no win-64 env has
  `libc++.dll.a`, and `zig-build.sh` stops if one appears. Enforced by
  verify-bundle.sh (R's own binaries and its C++ test package, linux and
  macOS) and the contract suite (every compiled package). Conda's own C++
  libraries (ICU on macOS) still bring the shared libc++ into the
  process next to R's static one; macOS two-level namespaces keep their
  symbol bindings apart.
- **Which zig each toolchain uses (decided 2026-09-29):**
  - conda: conda-forge's `zig`, made to link libc++ statically as above.
  - wheel: PyPI `ziglang` (upstream zig, static libc++), as today.
    `wheel-test.sh` fails if the C++ test package depends on a shared
    libc++ or libstdc++.
  - standalone tree: the official ziglang.org release (the same upstream
    build as PyPI `ziglang`), checksum-pinned, in the standalone
    toolchain download.
  - r-zig-packages binaries: built with upstream zig for the standalone
    tree and the wheel, and with conda-forge's zig for conda; static
    libc++ either way.
  - Optional, upstream: an opt-out in the conda-forge feedstock for its
    shared-libc++ lookup, which would replace the mirror.
- **Base keeps what compiling needs from R itself:** headers,
  `etc/Makeconf`, libR. Those are part of R, not of the toolchain.
- **OpenMP headers come with the toolchain** (found 2026-09-30): the
  shims add `-I$CONDA_PREFIX/include` only for `-fopenmp` compiles, and
  a packaged tree's Makeconf has no conda include dir. data.table's
  macOS probe passes `-Xclang -fopenmp` through the environment's
  `CPPFLAGS`, which Makeconf's own `CPPFLAGS` overrides, so the probe
  compiles `#include <omp.h>` with no OpenMP flag and only succeeds when
  `omp.h` is already on the include path (the dev tree and the conda
  package have it there; CRAN's macOS R does not either). The toolchain
  package for the standalone tree and the wheel must ship `omp.h` and
  put it on the include path; the shims also add `-L<omp lib dir>` when
  the caller links `-lomp` itself. Since F1.5 (2026-10-02) Makeconf's
  CPPFLAGS is `-I$(R_HOME)/../../include` and build.zig installs the
  OpenMP headers there for a non-conda tree, until phase T's standalone
  toolchain archive takes them over.
- **Preflight** (small `install.R` patch): before running `configure`
  or make, if the package needs compilation and the compiler Makeconf
  names doesn't exist, stop with one message naming the package to
  install for this distribution.

## Simplicity review and phase F (2026-10-01)

The project's aim: **one build path that just works everywhere, with as
little OS- or shell-specific trickery as possible, and one toolchain with
which users build, compile and install packages.** Reviewed against what
this branch has built so far.

**On track:**
- One build system on every OS: `zig build`, no autoconf, no make for R,
  no gnuwin32.
- One compiler family, zig and flang, for R and for packages; one
  toolchain package for conda and for pip.
- The tier boundary is enforced: the base needs `/bin/sh` and its own
  binaries only, checked on all five platforms by the hermetic job.
- libc++ and the flang runtime are static: compiled packages load
  without the toolchain.

**Drifting (measured 2026-10-01):**

| Area | Today | What it costs |
|---|---|---|
| Compiler shims | bash: `zig-cc` 238 lines with 10 OS branches, `zig-cxx` 182 with 8, mostly duplicated. Each branch works around a zig or conda-forge quirk (see phase B's list) | Windows needs the m2 bash just to run the compiler wrapper; no unit tests; every fix lands twice |
| Shipping tree made by post-processing | stage.sh (305 lines: rpath surgery with patchelf, install_name_tool and codesign; launchers; sed over Makeconf and Renviron; shim copies), package-standalone.sh (245: vendoring, Makeconf stripping), make-wheel.py (471: Renviron edits, the split), build.zig's `fixRpath`; 23 calls to patchelf/install_name_tool/codesign | CI tests the tree `zig build` installed, which no user receives (three bugs lived in that gap, see Verification); `install_name_tool` needs Xcode's tools; conda, standalone and wheel each get a slightly different tree |
| R source patches | 34 `r-zig:` sites in zig-build.sh, applied with awk and sed, idempotent by marker | a changed patch does not re-apply over an old one (hit twice); hard to review or rebase onto a new R |
| Two zigs | conda-forge's zig links a shared libc++ when it finds one, is dynamically linked to conda's LLVM, and differs from PyPI/upstream zig | the `ZIG_LIB_DIR` mirror in zig-build.sh and in both shims |
| Verification | verify-bundle.sh 348 lines with 12 OS branches | grows with every workaround it has to check |

**Phase F — `zig build` installs the final tree, then fold the
workarounds into code.** In order:

- **F1. The installed tree is the shipped tree.**
  - rpaths set at link time, relative (`$ORIGIN/...` on ELF,
    `@loader_path/...` on Mach-O), and the conda lib dir never added as
    one (`addCondaLibPath`'s `addRPath`); `fixRpath` and stage.sh's rpath
    surgery go. conda and the standalone tree share the layout
    (`<prefix>/lib/R`, `<prefix>/lib`), so the same relative rpaths serve
    both. To check: what rattler-build's relink pass does with them, and
    whether vendored conda libraries still need package-standalone.sh's
    `patchelf --set-rpath '$ORIGIN'`.
  - `bin/R`, the Rscript emulator, `etc/ldpaths`, `etc/Renviron` (tool
    defaults, `R_ZIG_TOOLCHAIN_HINT` from a build option) and
    `etc/Makeconf` written with their final values by build.zig instead
    of sed afterwards; the shims installed into `bin/toolchain` by
    build.zig on every OS, as on Windows today (then the preflight's
    Makeconf-`CC` fallback is unneeded).
  - Makeconf's include and library flags for the environment: today the
    absolute conda paths, kept for conda and stripped for the standalone
    tree, which is why the packaged tree lost `omp.h`. Candidate:
    `$(R_HOME)/../../include` and `$(R_HOME)/../../lib`, right in a conda
    env and harmless (or the toolchain's place for headers) in the
    standalone tree. FLIBS needs the same answer, together with the
    standalone toolchain's Fortran story.
  - What is left per distribution: conda, nothing after the build;
    standalone, vendor conda's libraries and the CA bundle, then archive;
    wheel, wrap and split. stage.sh retires.
  - CI's smoke, contract and `check` then run on the tree that ships.
- **F2. R's patches as a patch series**, one file per concern under
  `zigbuild/patches/R-<version>/`, applied with `patch -p1` (conda-forge
  has `patch` on unix and `m2-patch` on win-64; rattler-build can also
  apply a recipe's `source: patches:` itself). No awk, no markers; a new
  R version means refreshing the series.
  - **F2 done 2026-10-01**, tested on linux-64 (minimal and slim: build,
    smoke, contract, verify-package, hermetic; the wheel and wheel-test;
    the conda build and its tests), osx-arm64 on omicron (minimal and
    slim: build, smoke, contract, verify-package, hermetic; the wheel)
    and win-64 on kappa (slim: verify-package, contract, hermetic, with
    `m2-patch`). `zigbuild/patches/R-4.6.1/` holds 11 patches (user
    library, `Sys.which`, `osVersion`, temp dir, install.R's file
    operations, `install.packages` without make, bin/R and Rcmd without
    sed, the compile preflight, `R CMD config`'s make check, the CA
    rule), each with a header saying what and why. Generated from the
    old awk/sed blocks one at a time; the series applied to a pristine
    source is byte-identical to the tree the old zig-build.sh produced.
    zig-build.sh applies it with GNU patch (`-p1 -f -F0`: no fuzz, no
    prompts, never reversed), and a stamp in the source,
    `.r-zig-patches`, says what the tree carries: empty after extraction
    (fetch-r.sh, recipe/build.sh), the series' sha256 list once applied.
    Any other tree (no stamp, as in trees the old script patched; another
    series; an interrupted run) is extracted again from the tarball
    first, so a changed patch never meets an old one. `patch` comes from
    conda-forge on unix and `m2-patch` on win-64 (conda-forge has no
    win-64 `patch`), in pixi.toml and the recipe's build requirements.
    One mechanism on every path: rattler-build's `source: patches:`
    would cover the conda build only, with its own patch implementation.
- **F3. Phase B: one Zig binary for `cc`, `c++`, `ar`, `ranlib`** (and
  the Windows `gcc.exe`/`g++.exe` forwarders), the same code on every OS
  and unit-tested. Compiling then needs no bash on Windows; package
  `configure` scripts still need `sh`, which is theirs, not ours.
  - **F3a. Parity and integration.** rzig (prototype built 2026-10-01 in
    a worktree off b244ba6) catches up with the shims as they are now
    (the macOS `<arch>-native.13.0` target and SDK search dirs, the
    `-lflang_rt.runtime` resolver, OpenMP found from the tree's own
    location) and replaces them: build.zig builds it for the target and
    installs it as `bin/toolchain/{zig-cc,zig-cxx,zig-ar,zig-ranlib}`
    (and `gcc.exe`/`g++.exe` on Windows); the bash shims and
    win-exec-forward.c retire.
  - **F3b. The toolchain owns the compile environment** (direction set
    2026-10-02, after F1.5): where the environment is (rzig's own
    location), its `-I`/`-L`, OpenMP, the flang runtime, the conda-only
    rpath, the macOS SDK and deployment target, the glibc floor. Makeconf
    then shrinks to R's own values and `$(R_HOME)/bin/toolchain`, the same
    file in every distribution, and zigbuild/dev.Makevars goes. F1.5
    made those Makeconf values relative and moved FLIBS and the OpenMP
    lookup into the shims; this finishes the move. To weigh: the flags
    leave `R CMD config` (configure scripts and people read it); `-I` to
    the environment on every Windows compile (MinGW header shadowing);
    a standalone R run inside an unrelated activated conda env must not
    pick up that env through CONDA_PREFIX.
- **F4. One zig** (see Open): upstream zig everywhere, or a feedstock
  opt-out; the mirror goes.

**F1 implementation steps** (worked out 2026-10-01 from build.zig and
zig 0.16's std.Build):
- What ties the build tree to the pixi env today: `addCondaLibPath` adds
  the env's lib dir as an absolute rpath to every artifact, and
  std.Build adds the zig-cache directory of every sibling library a step
  links (`linkLibrary(libR)` and the rest; Compile.zig, unconditionally
  off Windows) as a further rpath. `fixRpath` strips the second kind on
  linux with patchelf; stage.sh replaces all of them afterwards. The
  bootstrap steps run the freshly installed R, which finds conda's
  libraries only through the absolute rpath, and so do smoke and the
  contract suite in CI.
- F1.1 Bootstrap without baked rpaths: the bootstrap Run steps set
  `R_LD_LIBRARY_PATH=<R_HOME>/lib:<env>/lib`, which R's `etc/ldpaths`
  already honours and turns into `LD_LIBRARY_PATH` or
  `DYLD_FALLBACK_LIBRARY_PATH` inside the launcher (after macOS's SIP has
  dropped `DYLD_*` from the environment). Build time only, nothing baked.
- F1.2 Relative rpaths at link time: `addRPathSpecial` with `$ORIGIN/...`
  (ELF) or `@loader_path/...` (Mach-O) per install directory, the pair
  stage.sh writes today (R_HOME/lib and `<prefix>/lib`); sibling libraries
  linked by their file (`addObjectFile(lib.getEmittedBin())`) rather than
  `linkLibrary`, which adds no zig-cache rpath; no rpath from
  `addCondaLibPath`. `fixRpath` and stage.sh's rpath surgery retire.
- F1.3 The dev tree is the standalone tree: when the install prefix is
  not the env (every build but the conda one), the build vendors the
  env's libraries into `<prefix>/lib` (package-standalone.sh's vendoring,
  moved into the build), so the installed tree runs on its own and every
  CI check runs on it. In the conda build the prefix is the env and the
  libraries are already there. F1.2 and F1.3 land together: either one
  alone leaves a tree that does not run.
- **F1.1–F1.3 done 2026-10-01**, tested on linux-64 (minimal, slim, the
  conda build with both packages' tests), osx-arm64 on omicron (minimal
  and slim: build, an `env -i` run of the installed tree, smoke, contract,
  verify-package, hermetic, both wheels) and win-64 on kappa (verify,
  contract, hermetic; the build.zig changes are no-ops there).
  - build.zig: `buildLdPath` (R_LD_LIBRARY_PATH on the bootstrap steps,
    `verify Rscript` and `zig build check`); `linkSibling` (libR,
    libRblas, libRlapack linked by file off Windows); `relRPaths` on
    libR/libRblas/libRlapack, `bin/exec/R`, the modules and every base
    package and cairo .so; `each_lib_rpath = false` on every library and
    executable; no rpath from `addCondaLibPath` or `applyLinkFlags`;
    `fixRpath` deleted.
  - scripts/vendor-libs.sh (new): the dependency walk from
    package-standalone.sh as a plain copy, run by zig-build.sh after
    every build and by package-standalone.sh. conda-forge's libraries
    already carry `$ORIGIN/.` (linux) or `@loader_path/` (macOS) rpaths,
    so no patchelf and no install_name_tool: stage.sh and
    package-standalone.sh have none left, and macOS binaries keep zig's
    ad hoc signatures (`codesign -v` passes) without re-signing.
  - Result: every R binary carries exactly the relative pair, the
    installed tree runs with an empty environment on linux and macOS,
    and rattler-build's relink pass leaves the relative rpaths working.
- **F1.4 done 2026-10-01**, tested on linux-64 (minimal and slim: build,
  smoke, contract, `check`, verify-package, hermetic, both wheels, the
  conda build with both packages' tests), osx-arm64 on omicron (minimal
  and slim, the same chain and both wheels) and win-64 on kappa (verify,
  contract, hermetic; `Library/bin/R.bat`/`Rscript.bat` and `TCL_HOME`
  now from build.zig).
  - build.zig: `makeRFrontScript` writes the self-locating `R_HOME_DIR`
    line and `${R_HOME_DIR}`-relative share/include/doc, and drops the
    lib64 probe; `ldpaths()` generates etc/ldpaths per OS;
    `finalRenviron()` sets `TAR`/`R_UNZIPCMD` internal, `R_PRINTCMD` lpr,
    minimal's bundled make and the `-Dtoolchain-hint` line; the configure
    table maps `@ZR_CONDA@/bin/<tool>` to the bare name and `@ZR_TOOLCHAIN@`
    to `$(R_HOME)/bin/toolchain`; the shims (and, for minimal, conda's
    make) are installed into `lib/R/bin/toolchain`; `<prefix>/bin/R` and
    both Rscripts come from `zigbuild/launchers/` (the compiled unix
    Rscript, which embeds R_HOME, is no longer built); Windows gets
    `TCL_HOME = $(R_HOME)/Tcl`, the `.bat` forwarders and `Renviron.site`
    with the hint.
  - stage.sh and zig-stage.sh are gone; `pixi run install` is an alias of
    `build`; recipe/build.sh runs zig-build.sh only, which passes the
    conda hint as `-Dtoolchain-hint` when `R_ZIG_CONDA_BUILD` is set.
- F1.4 Launchers, `ldpaths`, Renviron and Makeconf written final by
  build.zig, the shims installed into `bin/toolchain` on every OS, the
  Windows `R.bat`/`Rscript.bat` shims too; stage.sh retires.
- F1.5 Makeconf's environment flags (`-I`/`-L`, FLIBS) in a form that is
  right for conda and for the standalone tree (candidate:
  `$(R_HOME)/../..`-relative), so package-standalone.sh strips nothing.
  - **F1.5 done 2026-10-02.** Designed by a workflow (four read-only
    maps, three designs, a judge, an adversarial critique; scratch under
    the session's `f15/`), decided by the user, then built:
    - **The rule.** Inside an installed Makeconf the environment is
      `$(R_HOME)/../..`, which make expands where it runs: the conda
      env, the standalone prefix, the wheel's `r_zig/R` (Windows:
      `<prefix>/Library`). build.zig computes these values from the raw
      subst.txt entries (`makeconfValue`, a Makeconf-only overlay
      `ctx.mk_subst`); R's own build keeps the absolute ones. Seven keys
      carry it: CPPFLAGS, LDFLAGS, LIBS_PKGS, FLIBS_IN_SO, TCLTK_*, and
      the `R_CONFIG_ARGS` comment line. Windows: BINPREF
      `$(R_HOME)/bin/toolchain/`, LDFLAGS `-L"$(R_HOME)/../../lib"`, FC
      bare `flang`, FLIBS `-lflang_rt.runtime -lc++` (the Windows zip
      had never had these four corrected). `libR.pc` is relative to
      `${pcfiledir}` and drops the env `-L`/rpath.
    - **One difference by distribution, decided:** the conda build
      (`-Dconda-env`, which zig-build.sh passes when `R_ZIG_CONDA_BUILD`
      is set) keeps `-Wl,-rpath,$(abspath $(R_HOME)/../../lib)` in
      LDFLAGS. Reason, measured: glibc consults only the *executable's*
      DT_RPATH for a dlopened library's dependencies, so a package that
      links an env library loads in exec/R but not in an embedding
      process (rpy2, RInside). Revisit with data: recipe/test-toolchain.R
      builds a package linking fontconfig (an env library R does not load
      at startup) without the rpath and reports, never fails, whether it
      loads in a fresh R. That measures R's own process only, where
      exec/R's rpath into the env covers it (linux-64: TRUE); an embedder
      needs its own probe before the rpath can go.
    - **FLIBS is `-lflang_rt.runtime -lm`** (decided). toolchain/zig-cc
      and zig-cxx replace it with the static archive of the flang on PATH
      (`flang -print-resource-dir`/lib/<triple>/, checked for flang-zig on
      osx-arm64, osx-64, win-64 and conda-forge flang 22/23 on linux-64),
      once; with no flang on PATH they drop it (nothing was compiled by
      it; CRAN's `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` is on C links
      too); a flang without the archive drops it with a warning. Not tied
      to the LLVM major R was built with. Moves into rzig at F3.
    - **omp.h** (decided): build.zig installs `omp.h`, `ompx.h`,
      `omp-tools.h`, `ompt.h` into `<prefix>/include` for a non-conda
      OpenMP build (llvm-openmp owns that path in a conda env); phase T's
      standalone toolchain archive takes them over. The shims' OpenMP
      block now finds the environment four levels above the script
      (R_HOME/bin/toolchain → `$(R_HOME)/../..`), falling back to
      CONDA_PREFIX.
    - **The dev tree** (decided): it is the shipped tree, so its Makeconf
      no longer names the pixi env. pixi.toml's
      `[feature.pipeline.activation.env]` points `R_MAKEVARS_USER` at
      `zigbuild/dev.Makevars`, which adds the env's `-I`/`-L` (and the
      rpath on unix) from `$(CONDA_PREFIX)` (Windows: `-L` only, and the
      OS is told apart by Makeconf's `SHLIB_EXT`, since `OS=Windows_NT`
      does not reach make under pixi). A Windows CPPFLAGS there tripped an
      R bug found on kappa: with all eight of CC, CFLAGS, CXX, CXXFLAGS,
      CPPFLAGS, LDFLAGS, FC, FCFLAGS non-empty in `R CMD config`, a
      configure.win run inside another one's (pak's embedded curl) ends in
      `do.call(Sys.setenv, list())`, "all arguments must be named". The
      variable overrides a user's own `R_MAKEVARS_USER` inside the
      pipeline envs only. `pixi run contract` and
      interactive use behave as before; `env -i` checks and `R CMD config
      --no-user-files` see the shipped Makeconf alone. A user Makevars
      also switches the compile preflight off, so pixi runs skip it; the
      hermetic check (`env -i`) still exercises it.
    - **Guards:** build.zig fails the build if etc/Makeconf,
      etc/x64/Makeconf or libR.pc names the env, the prefix, the R
      source, the checkout, `$BUILD_PREFIX` (either slash) or a leftover
      `@ZR_` placeholder, comment lines included, counted against the
      template the file came from: only what substitution added counts
      (a `/usr/local` prefix would otherwise trip over Makeconf.in's own
      "/usr/local/lib" comment; checked both ways). verify-bundle.sh
      checks the extracted Makeconf (no build path in any slash or drive
      case, no rpath, the bare FLIBS), its Fortran package now does
      internal formatted I/O, which needs the runtime (a dropped
      `-lflang_rt.runtime` fails the load), it links a C package with
      `$(FLIBS)` and no flang on PATH (the env's make alone on PATH),
      and (slim, full) builds an OpenMP package from the tree's own
      omp.h and libomp, no rpath, plus data.table's probe shape (omp.h
      with no flag). contract-test.sh checks `R CMD config
      --no-user-files` FLIBS and LDFLAGS. recipe/test-toolchain.R checks
      the conda Makeconf's rpath and CPPFLAGS and builds a zlib and a
      Fortran package with no flags of their own (unix).
    - **Review:** an adversarial review of the diff (three lenses, one
      skeptic per finding) confirmed eight defects, all fixed before
      commit: the recipe test's `^` under `fixed = TRUE`; the guard's
      false positive above; Fortran tests that needed no runtime; an
      informational test that reused the rpath'd `.so` (make: nothing to
      do); the shims' OpenMP lookup on Windows, where the gcc.exe
      forwarder passes a backslash path; verify-bundle's Windows leak
      check, which searched only the `/c/...` form; the openblas
      standalone tree, which had no unversioned `libopenblas` for
      Makeconf's bare `-lopenblas` (vendor-libs.sh now adds the link
      name; the gap predates F1.5); and the no-flang test's reliance on a
      host make.
    - **Tested 2026-10-02** (all after the review's fixes unless noted):
      linux-64 slim and minimal (build, smoke, contract, verify-package,
      hermetic; minimal before the fixes), openblas (build,
      verify-package), the wheel and wheel-test, the conda package and its
      recipe tests; osx-arm64 on omicron slim (build, verify-package, the
      conda package and its tests), minimal, the wheel and osx-64 slim
      (before the fixes: build, smoke, contract, verify-package, hermetic);
      win-64 on kappa slim (verify-package, contract with dev.Makevars incl.
      pak and data.table's OpenMP, hermetic). linux-aarch64 and the
      Windows conda package: CI.
    - **What stopped:** package-standalone.sh no longer edits Makeconf
      (the whole-token sed and minimal's emptied FLIBS are gone);
      make-wheel.py's leak scan counts comment lines and it checks for
      the CA bundle itself; conda's prefix replacement no longer touches
      Makeconf or libR.pc.
    - Not done here: Windows CPPFLAGS stays empty (a later, kappa-tested
      `LOCAL_SOFT ?= $(R_HOME)/../..`); USE_FC_TO_LINK packages
      (`SHLIB_FCLD = $(FC)`) link through the flang driver, which cannot
      find its runtime in a conda env today either.
- F1.6 CI: build (final tree), then smoke, contract, check, hermetic, then
  archive; verify-package shrinks to the archive checks.

Order: T's conda and wheel parts (done) → F1 → F2 → F3 → T's standalone
split (it needs F1's layout and F3's binary) → P. F4 can be decided at
any point. The decisions this branch made stay valid through F: tiers,
the split by `bin/toolchain`, the preflight, static runtimes, the
hermetic check.

## Phases

A, then T, are sequential; F follows T's conda and wheel parts and comes
before T's standalone part. B is F3. C, D, S and P can run in parallel.

**A — host-path cleanup and tier-1 independence (this branch).**
- A1: configure-only.sh pins every value in the tool table that comes
  from the capture machine; re-capture all configs. Done so far
  (2026-09-29): every autoconf precious variable is unset before
  configure runs (JAVA_HOME was one instance of that leak), and macOS
  captures get `--build=<arch>-apple-darwin` with no Darwin version, so
  `R_PLATFORM` no longer records the runner's kernel (the vendored macOS
  configs were normalized the same way; the next gen-config run
  re-captures them).
- A2: R source patches, in `scripts/zig-build.sh` next to the existing
  `Sys.which` patch: `Sys.which` PATH scan; `osVersion` from
  `Sys.info()`; the temp directory removed with `R_unlink()`;
  install.R's Windows file operations on unix; one-at-a-time install
  without make.
- A3: `bin/R` without sed or bash (POSIX parameter expansion instead of
  `echo | sed`, `#!/bin/sh`); the Rscript emulator that stage.sh writes
  rewritten in POSIX sh (it uses bash arrays today).
- A4: Renviron: `TAR=internal`, `R_UNZIPCMD=internal`, bare names for
  tier 3.
- A5: stop vendoring `which`, `sed`, `tar`, `unzip`, `gzip`, `bzip2`,
  `zip`, `nm`. make stays only with the wheel's toolchain.
- A6: the hermetic tier-0/1 CI job.
- A7: libcurl (see "libcurl"): first the interim CA fix for the
  standalone tree and the wheel, then the CA rule and the per-platform
  curl.

**Progress (2026-09-29).** Tested on linux-64 (minimal and slim) and on
osx-arm64 (omicron: minimal verify-package, contract, wheel, wheel-test,
hermetic check); CI legs other than these run on the next push.
- A1: `R_SHELL=/bin/sh` pinned in configure-only.sh; the linux-x86_64
  configs re-captured with it (the full one also picked up `OBJC=zig-cc`
  and a different `LD` path, being older than the script), the other
  unix configs edited to match (`R_SHELL` and `'R_SHELL=/bin/sh'` in
  `config_opts`/`R_CONFIG_ARGS`), confirmed by gen-config on PR #12
  (osx-arm64 slim/full are not in its matrix). The other capture-machine
  values are normalized after capture rather than pinned in configure
  (`zigbuild/tools/normalize-subst.sh`, run by gen-subst.sh and applied
  to all 12 unix configs): `LD`, `TEXI2ANY(_VERSION_*)`, `INSTALL_INFO`
  and `TEXI2DVI` blank (manuals and configure internals only; none
  reaches an installed file); `NM` `nm -B` (it reached Makeconf as
  `/usr/bin/nm` on arm64 and macOS), `TEXI2DVICMD`, `YACC`, the
  autotools `missing` wrappers, `PAGER` less, `R_BROWSER`/`R_PDFVIEWER`
  xdg-open or open. After it the linux-arm64 and linux-x86_64 configs
  differ only by architecture (triples, `-fpic`) and flang's version
  string. `oldincludedir` is autoconf's fixed default (`/usr/include`
  everywhere): nothing to do. Pinning in configure itself is riskier
  than it looks: `R_UNZIPCMD` also unpacks zoneinfo at install,
  `R_PRINTCMD` reaches config.h, and an empty `TEXI2ANY` just makes
  configure search again.
- A2: all five patches in zig-build.sh (`Sys.which` replaced whole,
  `osVersion`, `R_CleanTempDir`, install.R's four `mv`/`cp` sites taking
  the `WINDOWS` branches with `patch_rpaths()` kept before the move,
  packages2.R). The old `bin/toolchain/which` is no longer used.
- A3: `R.sh.in`'s argument loop replaced whole (parameter expansion, no
  `echo`, whose backslash handling differs under dash), `R CMD` runs
  `/bin/sh Rcmd` instead of a PATH lookup of `sh`, and `Rcmd.in`'s
  `export \`sed ...\`` of Renviron's names became a `read` loop (found by
  the hermetic check: every `R CMD`, INSTALL included, ran sed). The
  lib64 probe is dropped for every variant. stage.sh's launchers and
  Rscript emulator are POSIX sh, use `${_s%/*}` instead of `dirname`, and
  Rscript prints usage without arguments (it used to wait on stdin).
- A4: stage.sh rewrites Renviron: `TAR` and `R_UNZIPCMD` `internal`;
  `PAGER` less, `R_BROWSER`/`R_PDFVIEWER` xdg-open (linux) or open
  (macOS), `R_PRINTCMD` lpr, `R_TEXI2DVICMD` texi2dvi.
- A5: stage.sh turns `$CONDA/bin/<tool>` into the bare name everywhere
  and vendors nothing but the shims and, for minimal (the wheel), make.
  This also fixed Makeconf's `NM`/`SED`, which read `$R_HOME/bin/...`,
  i.e. make's `$(R)_HOME/...`.
- A6: `scripts/hermetic-check.sh` (`pixi run hermetic`, CI step after
  verify-package on the unix default and minimal legs and on Windows).
  Windows (tested on kappa, slim, 2026-09-30): environment reduced to
  SYSTEMROOT/WINDIR/USERPROFILE/LOCALAPPDATA/TMP and PATH = R's
  `bin\x64` plus System32; R-only source installs (Ncpus = 2), a CRAN
  `win.binary` (jsonlite, which has a DLL) and R6 from source. The
  binary comes from CRAN because `--build` needs an external zip there;
  the DLL is unloaded before `remove.packages()`, since Windows cannot
  delete a loaded DLL. No execve trace on macOS or Windows: the reduced
  PATH is the check.
- Measured after A2/A3 (linux, minimal): `R -e` starts `bin/R`,
  `lib/R/bin/R` and `bin/exec/R`, nothing else. The hermetic scenario
  (source, `Ncpus = 2` and binary installs, removal, R6 from CRAN) starts
  only those and `/bin/sh` (R starting R, phase S).
- Found on the way: `Sys.timezone()` runs `timedatectl` when it is on
  PATH (seen during installs; optional, tier 0). The recipe's host
  `which`/`sed` dependencies existed for the old `@WHICH@`/`@SED@` bakes
  and can go in phase T.

**T — split the toolchain out**, once A6 passes on every platform:
the packaging above, the preflight, and `R CMD config` failing cleanly.

**T progress (2026-09-30), working package names `r-zig-slim` (base),
`r-zig-toolchain` (conda) and `r-zig`/`r-zig-toolchain` (PyPI):**
- Preflight (zig-build.sh, install.R patch before the configure step):
  a package with `src/` or a configure script, when
  `R_HOME/bin/toolchain/zig-cc` is missing, stops with "this package has
  compiled code, and the r-zig toolchain is not installed: <hint>". The
  file, not the directory, because pip or conda can leave the emptied
  directory behind. Also accepted: the compiler Makeconf's `CC` names,
  when it exists (`$(R_HOME)` expanded). An unstaged build tree has no
  `bin/toolchain` on unix (stage.sh makes it) and names the repo's
  `toolchain/zig-cc` directly; CI's contract step runs there, and the
  first push of the preflight refused every package on every unix leg
  (2026-10-01; local runs had been after staging). `R_ZIG_TOOLCHAIN_HINT` comes from etc/Renviron (read
  even under `--vanilla`; Renviron.site on Windows): the conda build's
  stage.sh names `pixi add r-zig-toolchain`/`conda install
  r-zig-toolchain`, make-wheel.py `pip install r-zig-toolchain`. A user
  Makevars (their own compiler) or `R_ZIG_NO_PREFLIGHT` skips it.
- `R CMD config` (src/scripts/config): checks for make before evaluating
  Makeconf and says it comes with the toolchain.
- conda (recipe/recipe.yaml): one staging output (`r-zig-build`, the
  build) and two packages split by directory. `r-zig-slim` excludes
  `lib/R/bin/toolchain/**` (`Library/...` on Windows) and run-depends on
  the runtime libraries only; `r-zig-toolchain` holds that directory and
  run-depends on `pin_subpackage("r-zig-slim", exact=True)`, zig, flang,
  flang-rt, make and, on Windows, the m2 userland. The staging script
  gets `R_VERSION` and `R_ZIG_CONDA_BUILD` from the recipe (a staging
  output has no `PKG_VERSION`). Tests: recipe/test-preflight.R (base:
  an R-only package installs, one with `src/` stops with the hint) and
  recipe/test-toolchain.R (a C and C++ package compiles and loads).
  Build number 3 → 4.
- wheel (scripts/make-wheel.py): two wheels from the minimal tree.
  `r-zig` drops `Requires-Dist: ziglang` and `R_HOME/bin/toolchain`;
  `r-zig-toolchain` holds only `r_zig/R/lib/R/bin/toolchain/*` (shims and
  GNU make, 0.2 MiB) and requires `ziglang` and `r-zig==<same version>`.
  Both share the `r_zig/` directory without a common file; wheel-test.sh
  installs `r-zig` alone (no ziglang pulled in, preflight names `pip
  install r-zig-toolchain`), then the toolchain (the existing compile
  tests), then uninstalls the toolchain and checks R is whole.
- Hermetic check: removes the toolchain directory from the extracted
  tree (tiers 0/1 are the base), and adds the negative tests: a `src/`
  package stops with the preflight, `R CMD config CC` fails cleanly.
- The toolchain package inherits the staging output with
  `run_exports: false`: its run dependencies are only the exact base,
  zig, flang, flang-rt and make (the inherited host run exports had added
  cairo, icu, libcurl and the rest, which the base brings anyway).
- Local pitfall: rattler-build restores the staging output from
  `dist/conda/build_cache` under a key that does not hash the recipe's
  `path:` sources, so a rebuild after editing scripts/ silently reused
  the old R build. `pixi run -e pkg conda-package` now deletes that cache
  first; CI runners start empty.
- CI, first push (`fae15f7`, 2026-10-01): all five conda-package jobs
  (both packages and their tests) and the Windows leg passed; every unix
  build leg failed the contract step on the preflight (see the first
  bullet: unstaged tree). Fixed by accepting Makeconf's `CC`.
- Not split yet: the standalone tarball. Its toolchain download (the
  official zig, checksum-pinned; `omp.h` for OpenMP; a Fortran compiler
  or not) still needs designing. The recipe's host `which`/`sed`/`grep`
  (for the old `@WHICH@`/`@SED@` bakes) are also still there.

**F — `zig build` installs the final tree** (added 2026-10-01): see
"Simplicity review and phase F" above for F1–F4.

**B — one Zig multi-call binary** (now F3, moved up 2026-10-01) that
dispatches on its own name, like busybox. It replaces the bash shims and
has to carry everything they learned: Windows' `-l` lookup of
`lib<n>.dll.a`/`lib<n>.lib`, the `-mwindows` link set, the macOS
deployment target (`-target <arch>-native.13.0`, `-F` for the SDK's
frameworks, the SDK's `-L` last on links), `-l` de-duplication (dyld's "duplicate
linked dylib"), the glibc 2.17 target pin, OpenMP wiring (`-I`/`-L` for
`omp.h`/libomp, also when the caller links `-lomp`), the `ZIG_LIB_DIR`
mirror against conda-forge zig's shared libc++ (until F4), the SONAME
injection, `-fno-sanitize=undefined`, and the zig lookup (`ZIG_BIN`,
PATH, `python3 -m ziglang`):
- compiler shims: `zig-cc`, `zig-cxx`, `zig-ar`, `zig-ranlib` (bash
  today) and `win-exec-forward.c`. The Windows shims stop needing bash;
  the m2 userland stays in the toolchain for make recipes and
  `configure.win`.
- robustness applets: an opener for the browser and PDF viewer
  (`xdg-open`, `open`, `start`), a pager (less, then more, then a
  built-in), possibly `zip` (std has deflate compression; a zip writer
  on top of it is small).

**C — C front-end**, ported from R's Windows one
(`src/gnuwin32/front-ends/rcmdfn.c` for `R CMD` dispatch, `rhome.c` for
finding R_HOME from the executable's location). Replaces `bin/R`, the
Rscript emulator and `bin/Rcmd`. `etc/ldpaths` becomes unnecessary: on
linux-64, `bin/exec/R` already finds libR through its RUNPATH
(`$ORIGIN/../../lib`).

**P — binary packages for the standalone tree and the wheel** (see
"Binary packages" below): the in-process installer, our repository
layout, and the fallbacks. The Linux fallback (P3M manylinux) already
works with our R, so P can start there once P3M's terms are checked;
CRAN's Windows binaries work as they are (tested on kappa).

**D — the remaining `R CMD` scripts** (`config`, `BATCH`, `COMPILE`,
`LINK`, `Rd2pdf`, `rtags`, `javareconf`, `pager`, `mkinstalldirs`):
built into the front-end or rewritten as R code.

**S — starting programs without a shell**, in C
(`src/unix/sys-unix.c`). On unix every program R starts goes through
`/bin/sh -c <string>` today:
- libc `system()` via `R_system()`: `system(intern = FALSE)`, the REPL's
  `!` escape, `edit()`, `file.show()` (`'pager' < 'file'`), postscript
  printing;
- libc `popen()` via `R_popen()`: postscript pipes;
- R's own `fork()` + `execl("/bin/sh", ...)`: `R_popen_timeout`
  (`system(intern = TRUE)`), `R_system_timeout`, `R_popen_pg` (`pipe()`
  connections).

Windows' `system()` already calls `CreateProcess` directly
(`src/gnuwin32/run.c:408`); only `shell()` and `pipe()` use `cmd.exe`.
processx (MIT) is the proof that this works from R: `fork()` +
`execvp()` of an R character vector (`src/unix/processx.c:550`, `:345`).
- S1: an argument-vector primitive built on `posix_spawnp()`, with file
  actions for stdin/stdout/stderr and a process group for timeouts,
  keeping R's signal handling. Unlike `fork()`, which R, processx and
  Zig 0.16 all use, it doesn't duplicate R's address space (glibc 2.24+
  and musl use `clone(CLONE_VM | CLONE_VFORK)`; macOS has it as a
  system call), so `system()` also stops failing for lack of memory in
  large sessions. `wait = FALSE` means R reaps the child itself; today
  the shell's `&` does that.
- S2: R's own spawns move to it: `R CMD INSTALL` starting R,
  `install.packages()` starting `R CMD INSTALL`, `file.show()`,
  `edit()`. Tier 1 then needs no shell, source installs included.
- S3: a no-shell fast path for `system()`, `system2()` and `pipe()`,
  following GNU make, which runs a recipe line directly when it
  contains none of ``#;"*?[]&|<>(){}$`^~!`` and doesn't start with one
  of about 40 shell builtins (make 4.4.1, `src/job.c:2844`). Two R
  additions: `system()`'s own `ignore.stdout`/`ignore.stderr`/`input`
  and `system2()`'s `env=`/`stdout=`/`stderr=`/`stdin=` become file
  actions and environment entries instead of appended shell text, and
  leading `VAR=value` words are applied as environment (make hands those
  to the shell). A missing command still prints a "not found" message
  and returns 127 (126 if not executable), as `sh` does.
- Unchanged: strings with shell syntax, the REPL's `!` escape and tier
  2 (package `configure` scripts, make recipes) keep `/bin/sh`. That is
  `system()`'s documented contract.

C rather than Zig here: `posix_spawnp()` is a single libc call, Zig
0.16's `std.process.spawn(io, ...)` needs an `std.Io` instance that
libR doesn't have, and a C patch stays reviewable upstream. Zig's spawn
is what the phase-B binary uses.

## Verification

- **Hermetic tier-0/1 job**, all five platforms: an empty environment
  (`env -i`) with PATH set to R's own `bin/` only (linux: optionally
  `bwrap` exposing only the R tree and `/bin/sh`). Start R, load the
  base and recommended packages, install R6 and withr from source and
  one binary package, remove them. Any undeclared tool fails the job.
- **Trace test (linux):** run the same scenarios under
  `strace -f -e trace=execve` and fail on any program not declared for
  that tier. An empty PATH alone is not enough, because these calls fail
  silently: `Sys.which()` returns `""`, `osVersion` becomes `NULL`, the
  temp directory is left behind. Measured on the minimal build
  (2026-09-25): `R --vanilla -e 'invisible(1)'` executes `dirname`,
  `sed` three times, `bin/exec/R`, `/bin/sh` + `which`, `/bin/sh` +
  `uname`, and `/bin/sh` + `rm`.
- **Build-path scan:** fail if any file in the standalone tree or the
  wheel contains the build machine's paths (`/home/`, `.pixi/envs`, the
  CI workspace). Conda packages are exempt, since conda rewrites their
  prefix at install. Today the scan would flag libcurl, libcrypto and
  the krb5 libraries (see "libcurl").
- **Negative test:** installing a package with `src/` and no toolchain
  stops with the preflight message.
- **Phase S differential test:** run a corpus of command strings through
  the fast path and through `/bin/sh -c`, and compare exit status and
  stdout; R's own regression tests cover the rest.
- smoke, contract and `check` keep running with the toolchain installed
  (tier 2).
- **Gap until F1: CI tests a tree no user receives.** smoke, contract and
  `check` run on what `zig build` installed, before stage.sh and
  package-standalone.sh change it; verify-package and the hermetic check
  run on the packaged tree, but compile only one C++ and one Fortran
  file. Bugs that lived in the gap (2026-09-30/10-01): Fortran packages
  not loading on the staged macOS tree (FLIBS), data.table losing OpenMP
  on the packaged tree (no `omp.h` on the include path), and the
  preflight refusing everything on the unstaged tree. After F1 there is
  one tree and every check runs on it.

## Zig 0.16 std (reference for B)

Where `std.Io` is heading after 0.16, and what a move to 0.17 would
break here: [ZIG_IO.md](ZIG_IO.md).

| Need | std | Gap |
|---|---|---|
| files and directories | `std.Io.Dir`: `createDirPath`, `deleteTree`, `copyFile`, `rename`, `symLink`, `readLink`, `setPermissions`, `setTimestamps`, `walk`, `access` | none |
| archives | `std.tar` (extract and `Writer`), `std.zip`, `std.compress.flate` (gzip, zlib, raw; both directions), xz, zstd, lzma | zip is extract-only; xz, zstd and lzma decompress only |
| processes | `std.process.spawn`, `run`: argument list, no shell, Windows quoting and PATHEXT | PATH lookup lives inside spawn (`Io/Threaded.zig`), not as a public function |
| own location | `std.process.executableDirPath` | none |

## Prior art: R on WebAssembly

webR ([r-wasm/webr](https://github.com/r-wasm/webr), R 4.6.0 patches
in `patches/R-4.6.0/`) and emscripten-forge's `r-base` 4.6.1 with
[IsabelParedes/r-main](https://github.com/IsabelParedes/r-main) (used
by xeus-r) have no processes at all, so they don't solve these
dependencies at run time: they move them all to build time. What they
confirm or teach, checked 2026-09-25:

- **R starts without `bin/R`.** webR's worker sets `R_HOME`,
  `R_ENABLE_JIT` and `TZ` in the Emscripten environment and calls
  `Rf_initialize_R`/`setup_Rmainloop` itself. r-main is a 34-line C
  front-end (`Rf_initEmbeddedR` plus `R_running_as_main_program = 1`),
  with `R_HOME` and `R_ENVIRON` set by its JS pre-run. That is phase C
  minus `R CMD`, which neither supports.
- **Binary installs never touch `R CMD INSTALL`.** `webr::install()`
  replaces `install.packages()`: `available.packages()` on a CRAN-like
  `bin/emscripten/contrib/<ver>` repo, then `utils::untar(tar =
  "internal")` or a filesystem-image mount. r-main extracts
  pre-solved conda packages with libarchive. R itself already installs
  binaries in-process on macOS (`.install.macbinary`, via
  `utils::untar`) and Windows (`unpackPkgZip`); only linux binaries go
  through `R CMD INSTALL` and its `cp -R`.
- **Compiling is a separate environment.** emscripten-forge's `r-base`
  output has only fonts as run dependencies; package recipes compile
  with `cross-r-base` and the compilers in their build environment.
  webR compiles with rwasm, which swaps each package's `configure` for
  an emconfigure wrapper and keeps per-package Makevars overrides: the
  realistic cost of compiling CRAN at scale (the r-zig-packages
  analogue).
- **Their patch sets are an inventory of R's host dependencies.**
  Comparing them with this plan found the `osVersion`/`uname` shell-out.
  Both stub `Sys.which()` to return `""` and webR makes `system()` an
  error; neither applies to us, since we have processes.
- **Pure-R packages are reused, not rebuilt.** xeus-r environments take
  pure-R packages from conda-forge's `noarch` builds (`r-ggplot2` has
  no emscripten-forge recipe; almost all of its R recipes are compiled
  packages). That works because the runtime package is named `r-base`.
- Both build R with LLVM flang and its runtime, like this repo, and run
  build-time R code with a native R (webR builds one first;
  emscripten-forge uses a linux build via
  `0009-Use-linux-executables.patch`). That matters only if R builds go
  cross.

## Using conda-forge's R packages (the `r-base` question)

**Decision (2026-09-25):** provide `r-base` (so conda-forge's `r-*`
packages install on top of r-zig) only if they are proven to work with
r-zig on all five platforms.

**First evidence (2026-09-25):**
- **No R 4.6 packages yet.** conda-forge has had r-base 4.6.0 and 4.6.1
  on all platforms since 2026-06-24, but its `r-*` packages are still
  built only for R 4.4 and 4.5. Every package tested requires `r-base
  >=4.5,<4.6.0a0`, including uploads from September. Until conda-forge
  migrates its packages to 4.6, none of them can install against an
  r-zig 4.6.1 `r-base`.
- **linux-64, run:** R6 (pure R), jsonlite, cli, rlang (C), Rcpp (C++),
  data.table (C + OpenMP), quadprog (Fortran + BLAS) and xml2 (C++ +
  libxml2), all built with R 4.5.x, load and run under r-zig 4.6.1 (slim
  and minimal) when their conda runtime libraries (libgcc, libstdcxx,
  libgomp, libgfortran5, libblas, libxml2) sit in the same prefix. Their
  RUNPATH finds `<prefix>/lib` without `LD_LIBRARY_PATH`; they need
  glibc 2.17 at most.
- **Symbols:** conda-forge's 4.6.1 `libR.so` exports 1259 symbols;
  r-zig's exports all of them except `_init`, `_fini` and
  `R_setX11Routines`. r-zig exports 2537 in total, because its internal
  symbols aren't hidden (to investigate).
- **macOS (run on omicron, macOS 26.4, 2026-09-29):** conda-forge's
  osx-arm64 jsonlite, placed where conda would put it, loads and runs in
  r-zig's minimal R, bound to r-zig's libR (the only libR mapped). It
  records libR compatibility version 4.5.0 while r-zig's `libR.dylib`
  declares 1.0.0, and dyld did not refuse it, contrary to what static
  inspection suggested. Upstream R sets `-compatibility_version
  ${MAJR_VERSION} -current_version ${PACKAGE_VERSION}`
  (`configure.ac:1877`); matching it is still tidy, but not a blocker on
  macOS 26 (untested on macOS 13, the deployment target).
- **Windows (run on kappa, 2026-09-29):** conda-forge's win-64 jsonlite
  and quadprog (built with R 4.5.1) load and run in r-zig's Windows R
  4.6.1, quadprog's BLAS through r-zig's `Rblas.dll`. Only the location
  differs: conda-forge's R lives in `<prefix>/lib/R`, r-zig's in
  `Library/lib/R`.

**What providing `r-base` would also require:**
1. The same R minor version as conda-forge's packages (4.5 today; 4.6
   after their migration).
2. A dependency on `_r-mutex 1.* anacondar_1`, as conda-forge's r-base
   has.
3. On Windows, R_HOME at `lib/R`.
4. Tidy, not required on macOS 26: libR's macOS versions as upstream
   sets them.
5. Recommended: `_openmp_mutex *_llvm` in the environment, so
   `libgomp.so.1` resolves to the same LLVM libomp r-zig uses (mixing
   both worked for data.table, but two OpenMP runtimes in one process
   can oversubscribe cores).
6. Optional: R linked to conda's `libblas`/`liblapack` like conda-forge's
   (`BLAS_LIBS = -lblas`), so the `blas` metapackage switches BLAS for R
   and packages together. Not needed to load: quadprog ran with conda's
   BLAS next to r-zig's.

**The gate:** a CI job on each platform that installs r-zig plus the most
used compiled conda-forge `r-*` packages and their runtime
dependencies, compares each package's imported libR symbols with
r-zig's exports, then loads each package and runs a call. It becomes
meaningful once conda-forge publishes R 4.6 builds.

## Binary packages for the standalone tree and the wheel

**Wanted (2026-09-25):** a binary repository for the standalone tree and
the wheel, reusing existing providers where their binaries fit. conda
users get binaries from the package manager instead.

**Survey (2026-09-25; linux-64 binaries loaded into our R 4.6.1 slim and
minimal on Ubuntu 24.04; macOS and Windows binaries inspected only):**

| Provider | Linux (x86_64, aarch64) | macOS | Windows x86_64 |
|---|---|---|---|
| P3M `cran/__linux__/manylinux_2_28/latest` | **works as-is**: jsonlite, data.table, cli, Rcpp, quadprog load and run; aarch64 exists too | none | none |
| P3M per distro (`__linux__/noble`, 30+ distros) | only if the host is that distro: they load the host's `libgomp.so.1`, `libblas.so.3`, libstdc++ (GLIBCXX 3.4.32) and need glibc 2.38; quadprog fails here without `libblas.so.3` | CRAN's | CRAN's |
| r-universe (`bin/linux/resolute-{x86_64,aarch64}/4.6/src/contrib`) | only on Ubuntu 26.04, the one distro it builds for; same system-library class as P3M per distro. Its `noble-*`/`jammy-*` paths silently serve source | CRAN class, where built (`sonoma-arm64` in e.g. bioc; none in the cran universe) | 25,191 packages for R 4.6.1 (CRAN class) |
| CRAN | none | needs fixups (below; tested) | **works as-is** (tested on kappa) |
| Bioconductor 3.23 (R 4.6) | via P3M (noble, manylinux_2_28: 2,384 packages) | CRAN class (2,333) | CRAN class (2,305) |
| webR (`repo.r-wasm.org`) | layout reference: `bin/emscripten/contrib/4.6/`, 22,741 packages | | |

What makes each one fit or not:
- **P3M manylinux is repaired like Python wheels:** each package bundles
  its libraries under hashed names in `libs/.libs` (RPATH
  `$ORIGIN/.libs`: libgomp, openblas, libgfortran, libquadmath) and
  records them in a `Built/SystemLibs` field. The rest is `libR.so`,
  libc, libstdc++ (GLIBCXX 3.4.21 at most) and libz; glibc 2.17 at most
  in the sample (the policy allows 2.28). Our `libR.so` SONAME matches,
  so packages bind to the R already loaded. Built with R 4.6.0, they
  load in 4.6.1; the bundled libgomp coexists with slim's libomp.
- **P3M only serves binaries to a recognizable R.** R's libcurl code
  replaces any `HTTPUserAgent` that starts with `R (` (R's default) with
  `libcurl/<version>` (`src/modules/internet/libcurl.c:285-302`), so P3M
  sends source: 20.9 s of compiling. With the RStudio-style
  `options(HTTPUserAgent = "R/4.6.1 R (4.6.1 x86_64-pc-linux-gnu x86_64
  linux-gnu)")`, four binaries installed in 4.2 s. P3M is a Posit
  service: check its terms before making it a default.
- **CRAN Windows** (R 4.6.1, Rtools, UCRT): DLLs import only `KERNEL32`,
  `R.dll`, `Rblas.dll` and the UCRT `api-ms-win-crt-*` libraries;
  gfortran, libgomp and libstdc++ are static. r-zig's R also uses UCRT
  (zig's mingw defines `_UCRT`), its DLL names match (`R.dll`,
  `Rblas.dll`, `Rlapack.dll`) and its `R.dll` exports a superset.
  Tested on kappa (2026-09-29) with the published r-zig-slim 4.6.1:
  `install.packages(type = "win.binary")` from CRAN installs jsonlite,
  data.table (OpenMP), quadprog (Fortran, BLAS) and Rcpp, and all load
  and run. (`scripts/contract-test.sh:59` forces `type = "source"`, so
  CI never exercises this path.)
- **CRAN macOS** (arm64 needs macOS 14, x86_64 needs 11): binaries link
  by absolute path into `/Library/Frameworks/R.framework/Versions/4.6/`
  (`4.6-x86_64` on Intel) for libR, libRblas, libomp, libgfortran and
  libquadmath, with no rpaths. Tested on omicron (2026-09-29):
  - **Unmodified, they are dangerous.** omicron has CRAN's R installed,
    so jsonlite loaded CRAN's own libR into r-zig's process and R
    crashed ("address 0x0, cause 'invalid permissions'"). Without CRAN's
    R they fail with "Library not loaded". An installer must rewrite or
    refuse them, never load them as they are.
  - **Rewritten, they work:** changing the framework libR path to
    `@rpath/libR.dylib` and re-signing ad hoc (arm64 refuses modified
    binaries) made jsonlite and Rcpp (C++, system libc++) load and run,
    bound to r-zig's libR only. The test used `install_name_tool`, which
    needs the Xcode tools; an in-process rewrite plus `/usr/bin/codesign`
    (always on macOS) avoids that.
  - Fortran packages would also need libgfortran and libquadmath, which
    r-zig doesn't have.
- **conda-forge packages** could also feed the standalone tree and the
  wheel: our layout (`<prefix>/lib/R`, `<prefix>/lib`) matches their
  RUNPATHs. It needs a solver for their non-R dependencies (rattler has
  Python bindings) and R 4.6 builds, which don't exist yet.

**Design:**
1. **Our own repository first** (r-zig-packages, built with our
   toolchain for our exact ABI: glibc 2.17, macOS 13, UCRT, flang
   runtime and libc++ static), laid out like r-universe and webR:
   `bin/<os>-<arch>/contrib/4.6/`, with `PACKAGES` carrying `Built:`,
   `SHA256:` and the BLAS flavor. On macOS it is the only clean source
   for Fortran packages.
2. **Fallbacks, in order:** Linux, P3M manylinux_2_28 (proven; needs
   the user agent in our `Rprofile.site` and glibc 2.28 on the host).
   Windows, CRAN, P3M, r-universe and Bioconductor binaries, after one
   run on kappa. macOS, CRAN binaries only with the fixups above.
   Per-distro P3M and r-universe only on a matching host, and with
   `libblas.so.3`/`liblapack.so.3` aliases to our libraries in
   `R_HOME/lib` (tested: fixes quadprog).
3. **An in-process installer** (tier 1, no `R CMD INSTALL`): pick the
   repository by platform; trust `Built:` (in `PACKAGES` or the unpacked
   `DESCRIPTION`), never the URL; verify `SHA256:` when present (r-universe
   has it, P3M doesn't); unpack with R's internal untar and move with
   `file.rename()`, as `.install.macbinary` and webR do. Windows'
   `unpackPkgZip` already works this way.

## libcurl

**Bug (2026-09-28): the standalone tree and the wheel cannot use HTTPS on
any other machine.** Both bundle conda-forge's libcurl and OpenSSL, which
carry this machine's paths: libcurl's default CA bundle is
`…/r-zig-pixi/.pixi/envs/minimal/ssl/cacert.pem`, and libcrypto's
OpenSSL directory is `…/.pixi/envs/minimal/ssl` (the wheel's copies are
the same). An HTTPS request from the minimal tree opens exactly those two
files (traced with strace). It only works here because they exist here;
elsewhere every HTTPS download, `install.packages()` included, fails with
"libcurl error code 77: error adding trust anchors from file". Nothing
in packaging sets `CURL_CA_BUNDLE` or ships a CA file. The conda package
is fine: conda rewrites `$PREFIX/ssl/cacert.pem` at install time.

**What R needs from libcurl** (`src/modules/internet/libcurl.c`): 7.28 or
later with HTTPS; the in-memory cookie engine (`:318`, so libpsl, which
refuses cookies set for public suffixes, still has a job); HTTP/2
multiplexing for parallel downloads (`CURLOPT_PIPEWAIT`, so nghttp2);
FTP and FTPS. It does not request compressed transfers (`:797`, commented
out), and uses no Kerberos. SFTP and SCP work only when libcurl has
libssh2. `CURL_CA_BUNDLE` is the only CA setting R reads (`:252`), and it
is ignored under Schannel (`:258`).

**Today's closure is about 50 MB of the minimal tree:** libcurl 1.1 MB,
OpenSSL 8.4 MB, krb5 1.6 MB, libssh2 0.35 MB, nghttp2 0.2 MB, and libpsl,
which pulls in ICU (36 MB) and libstdc++ (3.5 MB). ICU comes back even
though minimal is built without it.

**The design: one CA rule in R, a different curl per build type.**

| Build | curl | Trust |
|---|---|---|
| conda | conda-forge's shared libcurl, as today | conda's `ca-certificates` (path rewritten at install); Windows: Schannel |
| standalone and wheel, Linux | static curl built by build.zig into the internet module (allyourcodebase/curl, bumped from its 8.18.0 to current), with nghttp2, libpsl without ICU, no libssh2 or Kerberos | mbedTLS (Apache-2.0, small) or static OpenSSL, with no compiled-in CA path; the CA file found at run time (below) |
| standalone and wheel, macOS | Apple's `/usr/lib/libcurl.4.dylib` (part of macOS; on macOS 26.4 it is libcurl 8.7.1 with SecureTransport, in the dyld shared cache rather than on disk, and `dlopen` works), linked through a small `.tbd` stub, since zig's bundled SDK has only `libSystem.tbd`; compiled against macOS 13's curl headers | Apple's TLS and keychain, including enterprise roots; never set a CA file there, which would switch native trust off. Fallback: static curl with OpenSSL and Apple SecTrust (curl 8.17+) |
| standalone and wheel, Windows | static curl with Schannel | the Windows certificate store, as conda-forge's curl and Rtools' default |

**The CA rule** (a small patch to `curlCommon()`, applied: see below): when `CURL_CA_BUNDLE`
is unset and the tree ships its own bundle (`R_ZIG_CA_BUNDLE`), use the first that exists of `SSL_CERT_FILE`, the
distribution bundles (`/etc/ssl/certs/ca-certificates.crt`,
`/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`,
`/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`, `/etc/ssl/cert.pem`)
and, last, a Mozilla bundle shipped in `R_HOME/etc` (R for Windows ships
`etc/curl-ca-bundle.crt` the same way). The system bundles come first so
certificates added with `update-ca-certificates` (enterprise TLS
inspection) are trusted. Conda builds don't set `R_ZIG_CA_BUNDLE`, so
nothing changes; under Schannel R already skips it; with Apple's
libcurl on macOS, the tree won't set it either.

Building curl: allyourcodebase/curl's `ca-bundle` option defaults to
`auto`, which detects a CA path *on the build machine* and compiles it
in. Pass `-Dca-bundle=none` (and no CA path). Its nghttp2 is linked as a
system library, so we provide it. The port pins curl 8.18.0 (last
updated 2026-03); we pin the curl source ourselves in `build.zig.zon`,
at the latest release (8.22.0, 2026-09-02). Newer releases can add or
drop source files the port lists, so a bump may need small fixes there
(to upstream). Statically linked curl means a rebuild for every curl
security release: a CI check should flag new curl releases.

**Interim fix (applied 2026-09-29), with the CA rule already in:**
- `scripts/package-standalone.sh` (Linux and macOS) ships the env's
  Mozilla bundle as `R_HOME/etc/ca-bundle.crt` and adds
  `R_ZIG_CA_BUNDLE=${R_HOME}/etc/ca-bundle.crt` to `etc/Renviron` (not
  `Renviron.site`, which `--vanilla` skips). The wheel is built from the
  same tree.
- `scripts/zig-build.sh` patches `curlCommon()` with the CA rule:
  `CURL_CA_BUNDLE`; else, only when `R_ZIG_CA_BUNDLE` is set,
  `SSL_CERT_FILE`, the distribution bundles, then the shipped file. Keyed
  on `R_ZIG_CA_BUNDLE` rather than `CURLINFO_CAINFO`, because the
  compiled-in path does exist on the build machine; conda builds don't
  set it and behave as upstream.
- Not `CURL_CA_BUNDLE` in Renviron (the first version did that): Renviron
  exports to every program R starts, and curl or Python's requests would
  drop their own trust for the frozen copy.
- Regression check `scripts/tls-check.R`, run by `verify-bundle.sh` and
  `wheel-test.sh` under `--vanilla`: no `CURL_CA_BUNDLE` in R's
  environment, the shipped file inside R_HOME, real HTTPS requests with
  the default trust and with the shipped file, and an empty
  `SSL_CERT_FILE` that must make verification fail (proves the CA rule is
  compiled in). On linux, `verify-bundle.sh` also straces the requests
  and fails if a CA file is read from the build env. Offline runs report
  a skip, never a pass.
- Tested 2026-09-29: linux-64 (rebuild, verify-package, wheel-test,
  negative tests) and osx-arm64 on omicron (full `verify-package`,
  including the rule test; the default request uses `/etc/ssl/cert.pem`,
  Apple's copy of the system roots, not keychain additions). Windows:
  the patched `libcurl.c` compiles for x86_64-windows-gnu, where the
  helper only returns `CURL_CA_BUNDLE`, and kappa's r-zig verifies HTTPS
  through Schannel.
- Still there until the per-platform curl: OpenSSL opens its compiled-in
  `openssl.cnf` (harmless where missing), and libpsl's ICU.

Separate from all of this: P3M binaries need the `HTTPUserAgent` option
(see "Binary packages"), whichever curl is used.

## flang-pixi handoff §6, reconciled (2026-09-30)

`consolidation/FLANG_PIXI_HANDOFF.md` section 6 (owned by the flang-pixi
agent) against this branch's findings. Tested on omicron (macOS 26.4,
arm64) with the minimal env's conda-forge zig (build `_19`), upstream
zig 0.16.0 from PyPI `ziglang`, and the packaged minimal tree; on kappa
with the default env's win-64 zig (build `_15`).

**Agrees with this branch:**
- conda-forge zig links shared `libc++.1.dylib` on macOS, no opt-out:
  the 2026-09-29 decision (conda keeps it; wheel and standalone use
  upstream zig).
- `minos` follows the build host with a native target: resolved
  2026-10-01 with `-target <arch>-native.13.0` (below).
- Linux gets static libc++ only while the env has no `libcxx`: none of
  the lockfile's linux envs has one today. Adopted as a check (below).

**macOS deployment target: `-target <arch>-native.13.0` (2026-10-01;
replaces the 2026-09-30 "not viable").** Verified on omicron (macOS
26.4.1 arm64, CLT SDK 26.4) with conda-forge zig 0.16.0 `_15` and `_19`
(with the `ZIG_LIB_DIR` mirror) and upstream 0.16.0 from PyPI `ziglang`,
each probe rebuilt independently by a second agent. The recipe came from
another agent's investigation; this branch's addition is the SDK `-L`
going last.
- The OS word must be the literal `native`, then MAJOR.MINOR
  (`aarch64-native.13` is rejected). zig then treats the OS as
  non-native (`std.Target.Query.isNativeOs` requires `os_version_min ==
  null`): `LC_BUILD_VERSION minos 13.0`, and no LC_RPATH for `-L`
  directories. The ABI still counts as native, so headers and libSystem
  come from the installed SDK (`LibCDirs.detect` looks for it when
  `isNativeAbi`); clang sees the 13.0 target
  (`__ENVIRONMENT_OS_VERSION_MIN_REQUIRED__` 130000, availability
  warnings for macOS 14 APIs).
- The non-native link searches no SDK directory, so two come back by
  hand: `-F$SDK/System/Library/Frameworks` (else `-framework X` fails,
  "searched paths: none"; headers do not need it) and `-L$SDK/usr/lib`
  (else `-lresolv`, `-lz`, `-liconv`, `-lcurl` are not found). The SDK
  `-L` must come **last**: ahead of conda's lib dir, `-lz` silently binds
  the SDK's stub (zlib 1.2.12 against conda's 1.3.2 headers; iconv,
  curl likewise), on both zigs, with no warning.
- conda-forge zig still links a shared `@rpath/libc++.1.dylib` for this
  target without the mirror; the mirror stays.
- zig ignores `-mmacosx-version-min` and `MACOSX_DEPLOYMENT_TARGET`.
  flang does not: its objects default to the host SDK's version (26.0),
  and zig's link stamps 13.0 over them without a warning (all 43 of R's
  Fortran objects were 26.0 in the probe). flang honours
  `-mmacosx-version-min=13.0`, and the flag wins over the variable.
- What the 2026-09-30 test got right and wrong: `<arch>-macos.13.0` (an
  explicit OS tag) does lose the SDK's `usr/include` (`net/if_media.h`
  for ps; `libDER/DERItem.h` via AppKit.h). But `-F` does not make
  conda-forge zig panic: the panic ("for loop over objects with
  non-equal lengths"), and upstream zig's "unable to resolve dependency
  /usr/lib/libobjc.A.dylib", happen only without the SDK `-L`. The
  reported `-fvisibility=hidden -O3` linker crash did not reproduce.
- Probe results: zig level, both zigs: CoreFoundation C,
  `net/if_media.h`, Objective-C AppKit, C++ exceptions, conda zlib and
  libomp, flang with the static runtime: all `minos 13.0`, no LC_RPATH,
  valid ad-hoc signature, load and run. Through the shims on the slim and
  minimal trees: Rcpp (and a sourceCpp), ps, data.table with OpenMP,
  quadprog, minqa, cli, a CoreFoundation package: `minos 13.0`, no
  LC_RPATH, no libc++, no host path, all run under `env -i`; the same
  flags minus the target give `minos 26.4.1` and two absolute rpaths.
  Through build.zig, slim: all 16 Mach-O files under `lib/R` at 13.0,
  `otool -L` unchanged, smoke passes, the cairo PNG byte-identical;
  without the SDK paths the cairo module fails to link (`-lresolv`, then
  CoreFoundation).
- **Adopted (decided 2026-10-01):**
  - toolchain/zig-cc and zig-cxx pass `-target <arch>-native.13.0
    -F$SDK/System/Library/Frameworks` and append `-L$SDK/usr/lib` to
    link lines; the `-l`/`-L` rewrite is gone (the target alone records
    no rpaths). `$SDK` from `xcrun --sdk macosx --show-sdk-path`, as zig
    itself asks.
  - build.zig: one query for every macOS variant (`os_version_min =
    macos_min`, no OS tag); `Ctx.addSdkPaths` adds both SDK dirs last on
    every shared library and on `bin/exec/R`; `fortranOne` passes
    `-mmacosx-version-min=13.0`; Makeconf's `FC` carries the same flag
    (in `FC`, not `FFLAGS`, so a user's `~/.R/Makevars` keeps it and
    `SHLIB_FCLD = $(FC)` gets it).
  - Checks: verify-bundle.sh asserts `minos <= 13.0` for every Mach-O in
    the tree and for its test packages' objects and `.so` (C++ and
    Fortran: only the objects show a compiler that ignored the floor),
    relative install names (`libR.dylib` is `@rpath/libR.dylib`), no
    build-machine dependency, and no SDK `/usr/lib` library in R's own
    binaries beyond libSystem, libresolv and libobjc (the guard for the
    SDK `-L` order); contract-test.sh asserts `minos <= 13.0` for every
    compiled package and that data.table's libz is not the SDK's.
  - recipe: `__osx >=13.0` in r-zig-slim's osx run requirements
    (r-zig-toolchain inherits it through its exact pin).
- Tested after adoption (omicron, 2026-10-01): osx-arm64 minimal, slim
  and full (build, smoke, contract, verify-package, hermetic), the wheel
  (`macosx_13_0_arm64`, wheel-test), and osx-64 slim under Rosetta
  (build, smoke, contract, verify-package). Every Mach-O in each tree and
  every compiled package at `minos 13.0` or below; 1316 objects compiled
  by the build at 13.0, Fortran included (the only other one is the build
  runner's own object, which zig compiles natively and nothing ships).
  R's own binaries take only libSystem, libresolv and libobjc from
  `/usr/lib`.
- The load-command check found an older bug (the full variant, before
  this branch too): conda-forge's `libncurses.6.dylib` re-exports
  `libtinfo.6.dylib` by the env's absolute path (conda's prefix
  replacement fixes it at install time), and vendor-libs.sh, like
  package-standalone.sh before it, followed only `@rpath/` names. The
  relocated full tree (libR → libreadline → libncurses) therefore needed
  the build machine's env. vendor-libs.sh now follows absolute env paths
  too, vendors their targets, points the reference at `@loader_path/`
  and re-signs; it scans all of `<prefix>/lib`, so a re-run over an
  existing tree sees what an earlier run copied.
- Not tested: loading on macOS 13 (no machine); R-level installs with
  upstream zig.

**Static libc++ for R itself on macOS (the mirror before `zig build`):
works, with two conditions.**
- Measured (minimal, clean zig cache): `libR.dylib`, `bin/exec/R` and
  `libRlapack.dylib` link no libc++, the tree vendors none, verify-bundle's
  relocation/TLS/rpath checks and the hermetic check pass.
- The zig cache is not keyed on the probe: the first try, on a warm
  cache, silently reused the shared-libc++ link outputs. The mirror
  build needs its own `ZIG_LOCAL_CACHE_DIR` (or a clean one).
- Packages compiled into such a tree must be static too, since libc++
  is no longer in the process or the tree. True for the wheel (PyPI
  zig) and for the standalone tree with the official zig, but not for
  conda-forge zig: verify-bundle's C++ test package, compiled with the
  env's zig, then fails `dyn.load` ("Library not loaded:
  @rpath/libc++.1.dylib"). Adopting it means the verify step compiles
  with the mirror (or upstream zig), and the C++ runtime check extends
  to macOS. Adopted for every build (2026-09-30, "Static libc++
  everywhere" under Packaging): the shims now mirror the lib dir too, so
  the verify step's package is static as well.

**Windows zig.** Our shims find `x86_64-w64-mingw32-zig.exe` (MSYS bash
cannot run the env's `zig.bat`). That is the real 170 MB zig binary
(`zig_impl_win-64`), not one of `zig_win-64`'s flag-dropping cross
wrappers (`x86_64-w64-mingw32-zig-cc.exe` and siblings, ~200 KB), and
`zig.bat` only forwards to it. Its native target is
`x86_64-windows.win11_ga...win11_ga-gnu`: the gnu ABI, not MSVC. The host
Windows 11 version reaches neither the PE headers (OS and subsystem
version 6.0 native and with `-target x86_64-windows-gnu`) nor
`_WIN32_WINNT` (`0x0a00`, Windows 10, both ways). No change needed; an
explicit `-target x86_64-windows-gnu` would only guard against a change
of zig's default.

**The two `libcxx` versions in the lockfile.** osx-64 and osx-arm64:
`libcxx 21.1.8` in every R build env (default, full, full-openblas,
minimal, openblas, pkg), `23.1.2` only in `wheel`, the Python-only env
(`libpython` needs `libcxx >=20`; solved on its own). Nothing built or
shipped comes from `wheel`, so it does not matter here. Also seen: the
minimal env has conda-forge zig build `_19` (the build §6 measured),
the others `_15`.

**Adopted:** `contract-test.sh` fails on linux if any compiled package's
`.so` has `NEEDED libc++.so*`/`libstdc++.so*`; `verify-bundle.sh` does
the same for its C++ test package.

## Open

- **One zig (F4).** Upstream zig everywhere (for conda, a repackaging of
  the official build in our channel), or an opt-out upstreamed to the
  conda-forge feedstock for its shared-libc++ probe. Either retires the
  `ZIG_LIB_DIR` mirror and makes conda, pip and standalone compile the
  same way. conda-forge's zig is also dynamically linked to conda's LLVM
  21, so shipping it means shipping that.
- **Names** of the base and toolchain packages, on conda and PyPI.
  Decide together with the v3 naming question (consolidation/PLAN.md,
  Phase 3); `r-base` depends on the gate above.
- **Wheel toolchain mechanism:** a shared `r_zig/R/bin/toolchain/`
  directory vs discovery at startup.
- **BLAS link contract for binary packages.** openblas builds link
  packages to `libopenblas.so.0` (`BLAS_LIBS = -lopenblas`, as upstream
  configure does), internal-BLAS builds to `libRblas.so`, so a binary
  built for one fails to load on the other. For r-zig-packages: one
  binary per BLAS flavor, or openblas builds ship a `libRblas.so` that
  forwards to openblas so packages always link `-lRblas` (R-admin's
  documented way to swap the BLAS).
- **Absolute rpaths: fixed 2026-09-29.** What was found:
  - linux: not zig. The dev tree's Makeconf carries conda's
    `LDFLAGS = -L$CONDA/lib -Wl,-rpath,$CONDA/lib`; package-standalone.sh
    strips it, so packages compiled with the shipped tree have no
    RUNPATH. zig adds none there because the shim's `-target
    <arch>-linux-gnu.2.17` is not a native target.
  - macOS: zig. For a native target, every `-L` directory becomes an
    LC_RPATH (`src/main.zig`: `each_lib_rpath orelse is_native_os`), so
    each package recorded `R_HOME/lib`. `zig cc` rejects
    `-fno-each-lib-rpath` ("Unknown Clang option"). From 2026-09-30 the
    shims resolved `-l<name>` against the `-L` directories themselves
    and dropped the `-L` flags; since 2026-10-01 they pass
    `-target <arch>-native.13.0`, a non-native OS that records no rpath
    for `-L` directories and still uses the SDK, and the rewrite is gone
    (see "macOS deployment target" under "flang-pixi handoff §6,
    reconciled"). Packages with no rpath load: libR, libc++ and libomp
    are already in the process and match by install name (tested with C
    and C++ on omicron).
  - R's own macOS binaries also carried build-machine rpaths (the conda
    lib dir, absolute, and `build/zig-cache/...`, relative): stage.sh
    only added its `@loader_path` pair. It now deletes every other
    LC_RPATH, as patchelf `--set-rpath` does on linux.
  - verify-bundle.sh fails on any RUNPATH/LC_RPATH not relative to the
    file, and compiles a C++ SHLIB with the extracted tree that must have
    no rpath and load.
  - Regression from removing those rpaths, found 2026-09-30 on omicron:
    Fortran packages (quadprog, minqa) built against the staged macOS
    slim tree failed `dyn.load` ("Library not loaded:
    @rpath/libflang_rt.runtime.dylib"). `FLIBS` was `-L<clang resource
    dir> -lflang_rt.runtime`; that dir holds the `.a` and the `.dylib`,
    a native macOS link takes the `.dylib`, and only the build-env rpaths
    (zig's implicit one, libR's absolute ones) had made it load. CI
    missed it because the contract suite runs before staging; minimal
    missed it because its `FLIBS` is emptied. Linux was never affected
    (the pinned target takes the `.a`). Fix: build.zig writes `FLIBS`
    and `FLIBS_IN_SO` as the archive's path, so every Fortran package
    links the flang runtime statically, like libR, and loads without
    the toolchain, as tier 1 requires. verify-bundle.sh now also
    compiles a Fortran SHLIB with the relocated tree (where `FLIBS` is
    set) and requires no shared flang runtime and a working `.Fortran`
    call.
  - flang-rt-zig build 9 (flang-pixi, 2026-10-01), locked on osx-arm64,
    osx-64 and linux-aarch64 (`build-number >= 9` in pixi.toml): static
    only, no `.dylib`/`.so`, and built with hidden visibility. So
    `-lflang_rt.runtime` can only mean the archive, and a Fortran package
    no longer re-exports the runtime: on omicron with build 9, quadprog
    exports 8 symbols and minqa 41, none of them `_Fortran*`, where the
    probe counted 871 per Fortran `.so` with build 4; libR and
    libRlapack export no `_Fortran*` either. Slim on osx-arm64 (build,
    smoke, contract, verify-package) and osx-64 (build, verify-package)
    pass with it. The archive-path `FLIBS` stays: linux-64 uses
    conda-forge's flang-rt, which still ships the shared library, and
    win-64 (build 4, no build 9) was always static only. No version
    script or export list is needed.
  - The same day flang-pixi pruned universe to its live files, and the
    lock still named deleted builds: flang-zig `_1`/`_2` and lld-zig
    `_0`/`_1` on macOS, and flang-rt-zig `_4`/`_5` in the minimal env
    (its own `[feature.minimal.target.*]` entries had missed the `>= 9`
    pin). Every macOS CI job, the osx conda packages, gen-config and
    ubuntu-arm minimal failed with HTTP 404; omicron had them cached and
    never noticed. Re-locked (`pixi update flang-zig lld-zig
    flang-rt-zig`, nothing else changed) to flang-zig `_5` and lld-zig
    `_4` on macOS (flang-pixi's static-libc++ rebuilds) and flang-rt-zig
    `_9` everywhere it exists; every universe URL in the lock now
    resolves. Tested on omicron from a cold zig cache: osx-arm64 slim
    and minimal (build, smoke, contract, verify-package), osx-64 slim
    (same). A cold cache matters: zig's cache keys a Fortran compile on
    its command line and inputs, not on the flang binary, so a warm
    cache keeps objects from the previous flang (CI always starts cold).
  - Not a fix for the macOS minimal contract failure (first CI run of
    those legs, 2026-09-29, repeated on PR #12): on macOS data.table's
    configure probes `-Xclang -fopenmp` itself and links `-lomp`, and CI's
    contract step runs against the dev tree, whose Makeconf carries
    conda's `-Wl,-rpath,$CONDA/lib`, so conda's llvm-openmp loads. On
    linux data.table follows R's (empty) `SHLIB_OPENMP_*` flags. With the
    packaged tree (no conda rpath) it builds without OpenMP on macOS too
    (omicron). contract-test.sh now asserts minimal's actual property,
    empty `SHLIB_OPENMP_{C,CXX,F}FLAGS` in Makeconf, and requires a
    single-threaded data.table only off macOS.
- **macOS deployment target of compiled packages.** Resolved 2026-10-01
  by `-target <arch>-native.13.0` in the shims and the same query in
  build.zig (see "macOS deployment target" under "flang-pixi handoff §6,
  reconciled"): R and the packages compiled with it say `minos 13.0`
  whatever macOS builds them, so r-zig-packages can build on any
  runner. The shim and build.zig changes ship together: a package only
  loads where its tree's libR does. Still untested: loading on macOS 13
  itself.
- **Load-time needs of compiled packages:** the flang runtime is linked
  statically on linux-64 and macOS (quadprog and minqa need none).
  libc++ is static on linux-64 and Windows, but C++ packages built on
  macOS need `@rpath/libc++.1.dylib`. **That is conda-forge's zig, not
  zig** (found 2026-09-29): upstream zig builds its own libc++ as a
  static archive and links it on every OS (`src/libs/libcxx.zig`,
  `link_mode = .static`; `src/link/MachO.zig`), but the conda-forge
  feedstock applies `Lld.zig-prefer-shared-libcxx.patch`
  unconditionally. For native builds it links a shared libc++ found
  beside zig's install (`<prefix>/lib/libc++.1.dylib`, `libc++.so.1`,
  `libc++.dll.a`), because conda's LLVM uses a shared libc++. A macOS
  conda env always has one; kappa's win-64 env and the linux-64 env
  don't, so those stay static. Tested on omicron with a small C++ dylib:
  conda-forge zig links `@rpath/libc++.1.dylib`; upstream zig 0.16.0
  (ziglang.org tarball, the same build as PyPI `ziglang`) links only
  `libSystem`; conda-forge zig with `ZIG_LIB_DIR` pointing at a copy of
  its lib dir (so the probe finds nothing) also links only `libSystem`.
  Both static builds load and run. The wheel already compiles with PyPI
  `ziglang`, so it gets static libc++.
- **Internal symbols:** r-zig's `libR.so` exports 2537 symbols to
  upstream's 1259, and its `R.dll` exports every public symbol. Hiding
  internals like upstream would keep packages built here from binding to
  them.
