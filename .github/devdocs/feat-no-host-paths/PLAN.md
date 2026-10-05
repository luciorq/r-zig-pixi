# feat-no-host-paths — no build-machine paths, and a base R that installs without a toolchain

**Status and handoff (2026-10-05).** Read this first; the sections
below hold the detail and the reasons.

Where it stands (branch feat-no-host-paths, PR open against main; pushed
up to b4f97cc, CI green on every job through d233f2a "chore(ci): verify
before package", run 37123137421; F1.7 committed as 23841a4 "feat: unify
ci matrix", tested on every OS by hand; linux-64 on flang-zig committed
as 2622a6d; OpenMP for packages on every OS committed as 4868515, CI
green on all 20 jobs; F4 committed as a1edc58 "feat: accept upstream
zig" and pushed, tested with both zigs on linux-64, osx-arm64, osx-64
under Rosetta and win-64; What remains 6 and 7, no gfortran and no
build-machine paths in R's files, done in the working tree on top of
a1edc58, tested on linux-64, osx-arm64, osx-64 under Rosetta and win-64,
not yet committed):
- Phase A done on all five platforms (the hermetic tier-0/1 check runs in
  CI everywhere). Phase T done for conda and pip (`r-zig-slim` +
  `r-zig-toolchain`; `r-zig` + `r-zig-toolchain` wheels); the standalone
  tarball is not split yet. libc++ and the flang runtime are static
  everywhere (flang-rt-zig build >= 9 is static-only).
- Phase F: F1 (zig build installs the final tree; F1.5 Makeconf names no
  build path) done; F2 (R patches as a series under
  zigbuild/patches/R-4.6.1/) done; F3a (rzig, one Zig binary, replaces
  the bash shims and win-exec-forward.c), F3b (rzig owns the compile
  environment; Makeconf CPPFLAGS/LDFLAGS empty; R_ZIG_EXTRA_ENV; never
  CONDA_PREFIX) and F3c (zig-fc: Fortran in the toolchain) done. macOS
  deployment target 13.0 (`-target <arch>-native.13.0`, SDK `-F`/`-L`
  last; rzig re-signed with codesign on macOS hosts) done.
- F1.6 committed as d233f2a ("chore(ci): verify before package"),
  tested on linux-64, osx-arm64, osx-64 under Rosetta and win-64:
  verify-bundle.sh split into scripts/verify-tree.sh (static checks on
  the installed tree, pixi task `verify-tree`), scripts/verify-bundle.sh
  (archive checks) and scripts/verify-helpers.sh; hermetic on a copy of
  the installed tree; new CI order (green in CI). Docs-only commits: add `[skip ci]`, else the push
  cancels a running CI run (pull_request paths-ignore looks at the whole
  PR, and cancel-in-progress is on).
- F1.7 (2026-10-03, see its record in the F1 steps): `package` only
  archives on every OS (zig build installs the env's runtime data,
  vendor-libs.sh copies its shared libraries, Windows' DLLs included);
  `check` runs on Windows (R's tests/Makefile.win); one CI matrix with
  windows-latest in it. Found and fixed five bugs on the way: no
  tcltk.dll on Windows, winCairo.dll unloadable on Windows (svg/cairo
  devices), linux full's tcltk.so naming the build env's libtcl, the Tcl
  script libraries missing from standalone trees, and the recipe's win-64
  solve picking tk 9 (tk is pinned to 8.6 now).
- linux-64 on flang-zig (2026-10-03, record under Open, "Absolute
  rpaths", after flang-rt-zig build 9): linux-64 left conda-forge's flang
  for flang-zig + flang-rt-zig >= 9, so every subdir has one Fortran
  toolchain and runtime model (static-only, hidden visibility,
  `use omp_lib` works; slim/full Makeconf now has `SHLIB_OPENMP_FFLAGS =
  -fopenmp` on linux-64 too). Fortran is one `[dependencies]` entry in
  pixi.toml (win-64 overrides the flang-rt-zig build), no `linux64`
  selector in the recipe; the linux-x86_64 configs were re-captured
  (`FC_VER` "flang version 23.1.1" plus the Fortran OpenMP lines).
  Tested on linux-64; the other platforms' locked packages are
  unchanged.
- OpenMP for packages, the same on every OS (2026-10-04, record after
  F1.7's in the F1 steps): one libomp release, llvm-openmp pinned to 23.*
  in pixi.toml and the recipe's host (flang-rt-zig's omp_lib.mod major;
  the lock had kept 22.1.8 on unix by inertia), 23.1.2 on all five
  platforms; r-zig-slim's run dependency stays unbounded (the run export
  gives `>=23.1.2`). The standalone Windows tree ships omp.h and
  libomp.lib (build.zig installOpenMP) and libomp.dll (vendor-libs.sh,
  where the tree has libomp.lib), so OpenMP packages, C and Fortran,
  build with the tree alone, while R itself stays without OpenMP on
  Windows, as upstream; verify-tree checks the OpenMP files,
  verify-package builds and loads OpenMP C and `use omp_lib` Fortran
  packages from the archive on every OS (Windows: with only bin\x64 and
  System32 on PATH), each linking libomp and the Fortran ones running a
  parallel region on two threads.
- F4, both zigs (2026-10-05, record under F4 in "Simplicity review and
  phase F"): R and packages build with conda-forge's zig and with
  upstream zig (the ziglang.org release, which PyPI's ziglang is), and CI
  keeps that tested at release time. `pixi run fetch-zig` gets upstream
  zig (PyPI's wheel, sha256-pinned) and the pipeline tasks that run zig
  honour ZIG_BIN (conda-package and wheel-test do not: rattler-build
  gives the recipe a clean environment, wheel-test compiles with its
  venv's ziglang); env.sh makes it an absolute path and keeps one zig
  cache per zig; zig-build.sh prints the zig it
  builds with; the two libc++ mirrors are one Zig implementation
  (libcxx_mirror.zig, used by rzig and build.zig; zig-build.sh's bash
  mirror is gone); build.zig hides atexit from R's Windows DLLs'
  exports (upstream zig's one real failure, `duplicate symbol: atexit`
  in Rterm.exe/Rscript.exe); verify-bundle.sh's env -i compiles keep
  ZIG_BIN; CI's build steps are one reusable workflow (build-r.yaml),
  called by build.yaml and by upstream-zig.yaml (default on
  ubuntu/macos/windows-latest with upstream zig: dispatch, `v*` tags,
  PRs labelled `upstream-zig`).
- No build-machine paths in R's files (2026-10-05, What remains 7,
  record "Build-machine paths in R's files" after F4's): every C compile
  of R's own gets `-ffile-compilation-dir=.` and `-ffile-prefix-map` for
  the checkout, R's source, the env, zig's cache and zig's lib dir
  (build.zig filePathFlags), so `__FILE__`, OpenMP's source locations and
  the DWARF name none of them (R's long-vector error now says
  `src/main/character.c:1806`); zig's own runtime libraries carry no
  debug info (linkRoot); R's macOS binaries are stripped (their DWARF
  stayed in zig's cache and the binaries named it); tools/misc/top.txt
  is gone; fonts.conf ships without the env's directories
  (installFontconfig). verify-tree.sh fails, on every OS, on any file of
  R's own that names the checkout, zig's caches, the env or $HOME, and
  lists the vendored conda libraries that name one, and build.zig's
  verbatim copies of env files that name only $HOME's path
  (conda-forge's build path: macOS make's /Users/runner/..., under
  GitHub's macOS HOME). Tested on linux-64.
- gfortran removed (2026-10-05, What remains 6, record "gfortran
  removed" after F4's): flang is R's only Fortran compiler in build.zig,
  env.sh, configure-only.sh and gen-subst.sh; without one the build stops
  with one error. Tested on linux-64.

The decisions that shape the code now (each has its record below):
- The installed tree is the shipped tree (F1, on every OS since F1.7);
  every check runs on it, and `package` only archives it.
- Makeconf is the same file in every distribution and names no path
  outside `$(R_HOME)` (F1.5, F3b): FC/CC/CXX are `$(R_HOME)/bin/toolchain/
  zig-*`, FLIBS `-lflang_rt.runtime`, CPPFLAGS/LDFLAGS empty. Reason: the
  user's principle, one build path and one toolchain; the environment
  belongs to the toolchain, not to make variables (asked 2026-10-02:
  "why did we increase our reliance on Makeconf?").
- rzig decides the environment (zigbuild/tools/rzig/environment.zig):
  its own real path minus `/lib/R/bin/toolchain` (Windows `/Library/...`,
  8.3 short names expanded with GetLongPathNameW), plus R_ZIG_EXTRA_ENV
  (pixi sets it to the pixi env for dev runs); conda iff `<root>/conda-meta`;
  never CONDA_PREFIX. Env `-I` after the caller's args (Windows
  `-idirafter`), env `-L` and the conda-only rpath just before the first
  `-o` (where LDFLAGS sat: the environment's libraries win, CRAN link
  order unchanged). The conda rpath stays because glibc applies only the
  executable's DT_RPATH to a dlopened library's dependencies (and
  exec/R has RUNPATH): without it packages bind host libraries silently.
- `RZIG_TRACE=1` prints rzig's own path, the environments it chose and
  the final command; `RZIG_PRINT_ARGV=1` prints the command instead of
  running it.
- Both zigs, upstream zig the reference (F4, the user 2026-10-04/05: "I
  want this project to keep the capability of being able to be built by
  both zig from conda-forge and upstream", and "we should not deviate
  further from supporting upstream just to satisfy conda-forge
  quirks"). The design follows upstream zig (the ziglang.org release,
  PyPI's ziglang); a conda-forge quirk gets a small, isolated workaround
  that is a no-op with upstream zig and can be removed when the quirk
  goes (the libc++ mirror, libcxx_mirror.zig), never a design change.
  A difference that breaks upstream zig is fixed for upstream zig (the
  atexit export, addSharedLib).

What remains, in order (proposed; ask the user before starting each):
1. F4 is done (record under F4), tested on linux-64, osx-arm64, osx-64
   and win-64 with both zigs, and upstream-zig.yaml passed on GitHub on
   a1edc58 (run 37354940568, triggered by the PR's `upstream-zig` label:
   ubuntu 10 min, macos 11, windows 25). Left: decide whether to file the
   drafted upstream zig report on the auto-exported atexit.
2. Major (decided 2026-10-04): a Windows minimal variant, then a Windows
   wheel (first without compile support; compiling needs a sh/make/
   coreutils userland the wheel would have to bring). Analysis and order:
   the section "Windows minimal and the Windows wheel".
3. T's standalone split (a standalone toolchain archive), then the
   recipe's host which/sed/grep cleanup.
4. Later, test carefully first: the toolchain in an environment of its
   own (F3 section).
5. Small, open: Windows Makeconf's TCL_VERSION (86 vs conda's 86t) for
   packages that link Tcl/Tk (F1.7's record).
6. Done 2026-10-05 (record "gfortran removed" after F4's): build.zig,
   env.sh, configure-only.sh, gen-subst.sh and the Windows Makeconf know
   only flang; a missing flang stops the build with one error. Tested on
   linux-64, macOS and Windows.
7. Done 2026-10-05 (record "Build-machine paths in R's files" after
   F4's): no file of R's own names the build machine (`-ffile-prefix-map`
   for every C compile, zig's runtime libraries without debug info,
   macOS's R binaries stripped, no tools/misc/top.txt, fonts.conf without
   the env), and verify-tree.sh checks it on every OS. Tested on linux-64
   (slim with both zigs, minimal and the wheel, full, the conda package),
   osx-arm64 (slim, minimal, full), osx-64 and win-64 (and its conda
   package).
8. Small, open (found in F4): on Windows, packages that link
   `-lsynchronization` (Rust-based ones) build with conda-forge's zig,
   which ships prebuilt MinGW import libraries, but not with upstream
   zig 0.16.0, which has none for it.
9. Open (found in 7): R's compressed lazy-load databases still name the
   build machine, which no byte search sees. In a linux slim tree, 1,471
   Rd objects in the base packages' help databases (every Rd file's
   srcref: its path in R's source tree and the checkout as working
   directory) and 42 objects in their code databases (the install
   prefix: base's `.Library`, `.libPaths`' and `.popath`'s values, each
   namespace's `path`, methods' tables). R sets the second kind again
   when it starts and loads a package; the first is only read by help
   tools. Upstream's make records the same. Fixing them means changing
   how the bootstrap installs Rd objects and where it runs R (a neutral
   prefix), with a check that reads the databases.
10. Small, open (found in 6): rzig on Windows still resolves a
   package's `-lgfortran`/`-lquadmath` against a gfortran on PATH
   (windows.zig `gfortranLibDir`, kept in parity with the bash shims). No
   toolchain of ours has gfortran; whether such a package should get
   flang's runtime instead, or a clear error, is a package-compatibility
   decision.

How to verify (Linux here; omicron = osx-arm64 and osx-64 via Rosetta
in ~/rz-osx64; kappa = win-64 in C:\Users\admin\r-zig-pixi; see the
test-servers notes for SSH):
- `pixi run rzig-test` (rzig unit tests + parity test on linux)
- `pixi run build && pixi run verify-tree && pixi run smoke && pixi run
  contract && pixi run hermetic && pixi run verify-package`
- `pixi run -e minimal build && pixi run -e minimal verify-tree &&
  pixi run -e minimal verify-package`; `pixi run -e wheel wheel &&
  pixi run -e wheel wheel-test`; `pixi run -e pkg conda-package`
- Windows: the same order as unix, `pixi run build && pixi run
  verify-tree && pixi run smoke && pixi run contract && pixi run check &&
  pixi run hermetic && pixi run verify-package` (no minimal or wheel).
- Upstream zig (F4), on every OS: `export ZIG_BIN="$(pixi run
  fetch-zig)"` (PowerShell: `$env:ZIG_BIN = pixi run fetch-zig`), then
  the same tasks; the build log's `r-zig: zig = ...` line, RZIG_TRACE=1
  and `.comment` (linux: `readelf -p .comment`, clang 21.1.0 for
  upstream, 21.1.8 for conda-forge) show which zig built what. Each zig
  has its own build/zig-cache/zig-<cksum>/ (the old build/zig-cache/
  global and local can be deleted).

R source references are to R 4.6.1 (`build/R-4.6.1/`).

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
  env, on linux with any `libcxx` package), zig gets a mirror of the
  lib dir as its lib dir (a real directory of symlinks, nested as
  `<mirror>/lib/zig` so that its `../../lib` is empty; made once per lib
  dir, `mkdir` is the lock for parallel jobs). One implementation since
  F4 (2026-10-05), zigbuild/tools/rzig/libcxx_mirror.zig: rzig (the
  compilers, before them the zig-cc/zig-cxx shims) sets `ZIG_LIB_DIR`
  to `${XDG_CACHE_HOME:-~/.cache}/r-zig/zig-lib-<key>`; build.zig
  (staticLibcxxLibDir) makes it under zig build's local cache and sets
  it as `zig_lib_dir` (`--zig-lib-dir`) on R's links. Until F4
  zig-build.sh did R's in bash (`build/zig-lib-static`, plus a local
  cache of its own, `zig-cache/local-static-libcxx`, because the cache
  is not keyed on the probe); now the mirror is always used where the
  probe fires, and env.sh keeps one cache per zig, so no shared link
  enters a cache. `zig cc` outside zig build follows `ZIG_LIB_DIR` on
  every call (tested). With upstream zig the probe never fires. On
  Windows symlinks need a privilege; no win-64 env has `libc++.dll.a`,
  and build.zig stops if one appears. Enforced by
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
  - R itself builds with either (F4): the env's zig by default, upstream
    zig with `ZIG_BIN` (`pixi run fetch-zig`); CI's upstream-zig.yaml
    tests that as a release gate.
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
    - **F3a done 2026-10-02** (a workflow: one implementer in a worktree
      off 079076c, three review lenses, a skeptic each, a fix pass; then
      the macOS and Windows runs here). rzig is
      `zigbuild/tools/rzig/` (main, compiler, darwin, windows, flang_rt,
      environment, floors, libcxx_mirror, find_zig, ar, cmdline): one
      binary dispatching on argv[0] (zig-cc/gcc → cc, zig-cxx/g++ → c++,
      zig-ar, zig-ranlib). build.zig builds it once for R's target
      (glibc 2.17, macOS 13.0, windows-gnu; `floors.zig` is now the one
      place those numbers live) and installs copies: unix
      `zig-cc zig-cxx zig-ar zig-ranlib`; Windows `gcc.exe g++.exe` (what
      Makeconf.win's BINPREF names) plus `zig-cc zig-cxx`, which the
      compile preflight and the recipe test look for. Linux: a static
      ELF, no interpreter, no GLIBC symbols. Makeconf is unchanged.
      `environment.zig` is the one place that decides where the
      environment is (F3b builds on it). The repo's toolchain/ bash shims
      stay only for configure-only.sh (gen-config) and as the reference
      of `zigbuild/tools/rzig/parity-test.sh` (78 cases identical, 7
      deliberate differences); `pixi run rzig-test` runs the unit tests
      (28; 9 skip on Windows) and, on linux, the parity test, also in CI.
      Windows needs no bash to compile any more (packages' configure
      scripts and make still do).
    - Two macOS findings on omicron: (1) the x86_64 rzig disappeared
      seconds after being written. omicron runs CrowdStrike Falcon
      (managed by Jamf), whose static analysis quarantined it. zig only
      writes a linker signature (`adhoc,linker-signed`), and only on
      arm64; the x86_64 rzig was deleted unsigned and linker-signed
      alike (an entitlements file makes zig linker-sign x86_64 too: still
      deleted), while the same binary re-signed by `codesign --sign -`
      (`adhoc`) was left alone. XProtect's YARA rules do not match it
      (scanned). rzig/build.zig therefore re-signs rzig with
      `/usr/bin/codesign` on a macOS host (always present, like xcrun;
      a cross-build from linux keeps zig's signature): Intel Macs with
      such an agent would otherwise lose the compiler. A post-link step
      we would rather not have, the one place F3 keeps one; R's own
      x86_64 binaries were not touched by the agent. (2) rattler-build's relink of the r-zig-toolchain
      package failed on rzig ("larger updated load commands do not
      fit"): rzig now gets `-headerpad_max_install_names`, as R's own
      Mach-O files do.
    - Tested 2026-10-02: linux-64 (rzig unit and parity tests, slim build,
      smoke, contract, verify-package, hermetic, minimal build and
      verify-package, the wheel and wheel-test, the conda package and its
      tests); osx-arm64 on omicron (unit tests, slim build, smoke,
      contract, verify-package, hermetic, minimal, the wheel, the conda
      package and its tests); osx-64 under Rosetta (unit tests, build,
      contract, verify-package; rzig signed `adhoc`, minos 13.0, not
      quarantined); win-64 on kappa (unit tests 19 pass / 9 skip,
      verify-package with the new "compilers are rzig" check, contract
      incl. pak's quoted `-D` flags through rzig's own Windows quoting and
      data.table's OpenMP, hermetic, the conda package and its tests).
      linux-aarch64: CI.
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
    - **F3b done 2026-10-02.** Designed by a workflow (three designs:
      parity, fully toolchain-owned, explicit environment; a judge; an
      adversarial critique against the code), decided by the user,
      implemented by a workflow (an implementer in a worktree, three
      review lenses, a skeptic each, a fix pass), merged and tested here.
      - **The rule** (zigbuild/tools/rzig/environment.zig, the only
        place it is decided): R's own environment is the real path of
        rzig's executable minus `/lib/R/bin/toolchain` (Windows:
        `/Library/lib/R/bin/toolchain`, ignoring case; the environment
        is then `<root>/Library`); a copy anywhere else has none. A
        second environment comes only from `R_ZIG_EXTRA_ENV` (a root,
        made absolute and resolved; applied even when rzig is not in an
        R tree; dropped when it is the same as R's own). An environment
        is conda iff `<root>/conda-meta` is a directory (unix). rzig
        never reads CONDA_PREFIX, OpenMP included: that closed a leak,
        reproduced by the design workflow, where a standalone R inside
        an unrelated activated env picked up that env's OpenMP flags.
      - **The flags** (compiler.zig `envFlags`, after the flang runtime
        and before Windows' import-library lookup): `-I<env>/include`
        after the caller's arguments on every call (Windows:
        `-idirafter`, measured safe on kappa: the env's 1400 headers and
        zig's MinGW, libc++ and clang headers share one name,
        `profile.h`, and no zig header `#include_next`s it); on links
        only, `-L<env>/lib` and for a conda env `-Wl,-rpath,<env>/lib`
        immediately before the first standalone `-o`, exactly where
        Makeconf's LDFLAGS sat (decided: the environment's libraries
        keep winning over a package's own `-L`, and CRAN packages see
        today's link order); `-lomp` for a `-fopenmp` link when an
        environment has omp.h. Only directories that exist are added.
        macOS: the SDK `-L` stays last, `-l` de-dup covers the new
        flags. `RZIG_TRACE=1` prints the final command, then runs it.
      - **Makeconf after:** CPPFLAGS and LDFLAGS empty on unix and
        Windows (so the nested configure.win bug cannot trigger), the
        configure comment line without them, `-Dconda-env` gone; LIBS,
        TCLTK_*, FC and FLIBS unchanged. The conda package's Makeconf is
        byte-identical to the standalone tree's (sha256 checked).
        zigbuild/dev.Makevars is gone: pixi's pipeline activation sets
        `R_ZIG_EXTRA_ENV` to the pixi env (`%CONDA_PREFIX%` on win-64,
        checked on kappa). pixi runs no longer carry a Makevars of ours,
        so they no longer switch the compile preflight off (a personal
        `R_MAKEVARS_USER` or `~/.R/Makevars` still does, and shapes local
        results; the contract's `R CMD config` checks use
        `--no-user-files`).
      - **What R CMD config loses:** CPPFLAGS and LDFLAGS (and
        `--ldflags` the conda rpath). Scans of 333 and 274 cached CRAN
        and Bioconductor packages found every reader pairing them with
        Makeconf's CC/CXX (rzig, which adds the flags back) or R CMD
        SHLIB. An embedder linked with another compiler on a distro
        without default `--as-needed` loses the conda rpath that
        `R CMD config --ldflags` used to print; conda's Python (DT_RPATH
        `$ORIGIN/../lib`) and RInside (`R CMD config CXX`) do not.
        USE_FC_TO_LINK links and package rules that hand `$(CPPFLAGS)`
        to `$(FC)` lose the environment until F3c (zig-fc, decided as
        next).
      - **Also:** rzig gives an executable link on Windows gcc's `.exe`
        when `-o` names no extension (`gcc px.c -o px`): ps and processx
        build px.exe and interrupt.exe that way, and no r-zig build had
        them before (the warning "problem copying .\px.exe" was in every
        Windows CI log, bash shims included).
      - **Windows short paths** (found on kappa): R starts programs by
        the 8.3 short form of the whole path (`system2()` called
        `.../lib/R/bin/TOOLCH~1/gcc.exe`), so the suffix check missed and
        rzig added no environment; make's calls (Makeconf's
        `$(R_HOME)/bin/toolchain/`) and cmd's were fine. rzig now expands
        its own path with `GetLongPathNameW` (Zig's realpath keeps the
        short names). `RZIG_TRACE=1` also prints rzig's own path and the
        environments it chose, which is how this was found.
      - Tested 2026-10-02: linux-64 (rzig unit tests 35 and the parity
        test; slim build, smoke, contract, verify-package, hermetic;
        minimal build, contract, verify-package; the wheel and
        wheel-test; the conda package and its tests: env -I/-L/rpath from
        rzig, a decoy CONDA_PREFIX ignored, the zlib package's rpath
        exactly `<env>/lib`); osx-arm64 on omicron (the same, plus
        minimal smoke and hermetic); osx-64 under Rosetta (unit tests,
        build, contract, verify-package); win-64 on kappa (unit tests,
        verify-package with the dry run, contract, hermetic, ps's px.exe
        and interrupt.exe installed, the conda package and its tests).
  - **F3c done 2026-10-02: zig-fc, Fortran in the toolchain** (decided
    in F3b's design round; implemented by a workflow: an implementer in a
    worktree, three review lenses, a skeptic each, a fix pass).
    Makeconf's `FC` is `$(R_HOME)/bin/toolchain/zig-fc` on every OS
    (Windows: zig-fc.exe, which MSYS make and sh find without the
    extension); the macOS floor left Makeconf for floors.zig. zig-fc
    (zigbuild/tools/rzig/fortran.zig) is another rzig applet:
    - compiles and everything else (`-E`, `--version`, configure's mixed
      source-and-link probes) run the flang on PATH with the caller's
      arguments, on macOS after `-mmacosx-version-min=13.0`;
    - a shared link of objects (`-shared`/`-dynamiclib`, no source among
      the inputs: R's `USE_FC_TO_LINK`, where `SHLIB_FCLD = $(FC)` and
      install.R drops `$(FLIBS)`) runs zig exactly as zig-cc does
      (floors, SDK, soname, the environment's `-L`/rpath, OpenMP,
      Windows import libraries) with `-lflang_rt.runtime -lm` (Windows
      `-lc++`) appended, resolved to the static runtime archive. Before,
      that link went through flang's own driver and failed in every
      distribution ("cannot find -lflang_rt.runtime", measured);
    - with no flang on PATH it exits 127 with a fixed message (an LLVM
      flang is needed; r-zig-toolchain brings one in a conda env, the
      wheels and the standalone tree bring none). Not the toolchain
      hint: zig-fc ships inside the toolchain package it would name.
    Fortran compiles still get no environment `-I` (Makeconf's Fortran
    rules never used CPPFLAGS); executable links of Fortran (configure
    probes) still go through flang's driver. Under `USE_FC_TO_LINK` on
    Windows, Fortran code calling R needs `$(LIBR)` in PKG_LIBS, as with
    upstream gfortran. R's own Fortran build (fortranOne) keeps calling
    flang directly with the floor from floors.zig.
    Tested 2026-10-02: linux-64 (rzig unit tests 41, slim build,
    smoke, contract, verify-package with a new `USE_FC_TO_LINK` package
    and zig-fc's no-flang exit, hermetic, minimal, the wheel and
    wheel-test, the conda package and its tests); osx-arm64 (the same,
    and rattler-build relinked zig-fc fine); osx-64 under Rosetta
    (unit tests, build, contract, verify-package); win-64 on kappa (unit
    tests, verify-package with a zig-fc.exe dry run, contract with
    quadprog and minqa through zig-fc, hermetic, the conda package with
    its `USE_FC_TO_LINK` package).
  - **Later (not urgent; test carefully first): the toolchain in an
    environment of its own** (asked 2026-10-02). rzig itself is small
    (300-600 KB) and could ship with R; the heavy part, zig and flang
    (about 1.5 GB on macOS), could live in one shared environment that
    several R environments use, as Rtools is installed once on Windows.
    rzig already finds zig through ZIG_BIN, PATH or `python3 -m
    ziglang`, and flang on PATH; one explicit variable (say
    `R_ZIG_TOOLCHAIN_ENV`) would cover both. F3b's `R_ZIG_EXTRA_ENV`
    (an extra environment of headers and libraries) applies even when
    rzig does not sit in an R tree, so it composes with this. Touches
    phase T's package split and the compile preflight's "is the
    toolchain here" test.
- **F4. Both zigs** (redefined 2026-10-04; the original "one zig, the
  mirror goes" is dropped): R and packages build with conda-forge's zig
  and with upstream zig (PyPI's ziglang), and CI keeps that tested. The
  user: "I want this project to keep the capability of being able to be
  built by both zig from conda-forge and upstream (ziglang in PyPI should
  be the same as upstream), so if there are modifications needed to keep
  that capability I would like to keep it."
  - **The user's terms (2026-10-04/05).** "I just want to keep in our
    design decisions that we should not deviate further from supporting
    upstream just to satisfy conda-forge quirks": upstream zig is the
    reference, a conda-forge quirk gets a small, isolated, removable
    workaround, never a design change (now in the Status section's
    decisions). CI: R built with upstream zig on default for
    ubuntu-latest, macos-latest and windows-latest, "not run for every
    commit, treat it as major release gate or an integration test. If
    the wheel packaging is working, it is probably enough for regular
    CI." The two libc++ mirrors become one Zig implementation (the
    user's choice). And the standing principle: "a single build path that
    should just work everywhere and depend the minimum possible in OS
    specific or shell specific trickery."
  - **The investigation (2026-10-04, on 4868515; linux-64 here,
    osx-arm64 and osx-64 on omicron, win-64 on kappa).**
    - PyPI's ziglang 0.16.0 is the ziglang.org 0.16.0 build: the zig
      binary and all 19,541 lib files are byte-identical on all three
      OSes (the wheel only omits a FreeBSD-only header). conda-forge's
      zig (`zig_impl_<subdir>` 0.16.0 `_15` in the lock) is another
      binary, dynamically linked to conda's LLVM 21.1.8, with the
      feedstock's patches.
    - linux-64 and macOS: R built with upstream zig (ZIG_BIN) passes
      build, verify-tree, smoke, contract, check, hermetic and
      verify-package as it is; the same machine code.
    - win-64: one real failure. Linking Rterm.exe and Rscript.exe fails
      with `lld-link: duplicate symbol: atexit` (crtexe.c's crt2.obj
      against Rgraphapp.lib's import of the DLL's own atexit). R's DLLs
      are linked without .def files, so LLD's MinGW auto-export exports
      every global, and LLD's exclusion of the C runtime's symbols knows
      their GNU object names (dllcrt2.o), not zig's (dllcrt2.obj): the
      DLL's atexit (mingw's crtdll.c) is exported. conda-forge's win-64
      zig hides it by accident (its non_unix patches
      mingw-crtexe-no-atexit and ucrtbase-export-atexit-alias). Plain
      `zig cc` reproduces it (the report draft below).
    - Two gaps in our checks: verify-bundle.sh's compiled-package section
      ran every compile under `env -i` with PATH = the dir of `command -v
      zig`, which dropped ZIG_BIN, so after an upstream build it tested
      conda-forge's zig (and skipped everything in an env without zig);
      and zig's cache cannot tell conda-forge's 0.16.0 from upstream's
      (the same version string; lib inputs hashed relative to the lib
      dir): switching zig in one checkout gave a mixed tree (upstream's
      LLD over conda clang's cached objects).
  - **The two zigs, side by side** (what matters to this project):

    | | upstream (ziglang.org, PyPI ziglang) | conda-forge `zig` 0.16.0 `_15` |
    |---|---|---|
    | binary | static, LLVM/clang/LLD built in; clang 21.1.0 in `.comment` | dynamically linked to conda's libLLVM/libclang 21.1.8; 21.1.8 in `.comment` |
    | libc++ | always its own, static | a shared one when `<lib dir>/../../lib` has one (Lld.zig-prefer-shared-libcxx; every macOS env, any env with `libcxx`): the mirror, libcxx_mirror.zig |
    | glibc stubs in DT_NEEDED | only the ones used (`--as-needed`) | all of zig's glibc stubs (linux patch Lld.zig-no-unconditional-as-needed-glibc-bundled) |
    | MinGW `atexit` (win-64 host) | crtexe.c defines it; DLLs auto-export crtdll.c's | crtexe.c's removed, UCRT alias (non_unix patches): no clash |
    | MinGW import libraries | none for `synchronization` | prebuilt ones, `-lsynchronization` links |
    | cache identity | version "0.16.0" | the same "0.16.0": one cache per zig (env.sh) |
    | lib dir | `<dir of zig>/lib` | `<env>/lib/zig` |

  - **What changed (2026-10-05).**
    - build.zig `addSharedLib`, Windows: a generated `no_crt_exports.c`
      whose `.drectve` section says `-exclude-symbols:atexit` (what gcc
      and clang emit for a hidden symbol on MinGW). Fixes upstream zig's
      Rterm.exe/Rscript.exe links; a no-op with conda-forge's zig (export
      tables otherwise identical, kappa 2026-10-04). Packages are not
      affected (R links them with a .def file).
    - One libc++ mirror in Zig: zigbuild/tools/rzig/libcxx_mirror.zig's
      core no longer needs rzig's Ctx: `prepare(io, arena, lib_dir,
      cache_root)` probes `<lib dir>/../../lib` for the names the
      feedstock patch looks for and returns the mirror's lib/zig (made
      once: the directory is the lock, `.complete` the marker), `.none`,
      or `.failed`; `sharedLibcxx(.., .windows)` is the Windows probe.
      rzig's `apply` calls it with `${XDG_CACHE_HOME:-~/.cache}/r-zig`
      (behaviour, mirror path and key unchanged: the parity test against
      the bash shims still passes). build.zig imports the same file
      (staticLibcxxLibDir): when the probe fires for
      `b.graph.zig_lib_directory` it makes the mirror under zig build's
      local cache (`<local cache>/r-zig/zig-lib-<key>`) and sets it as
      `zig_lib_dir` on R's unix links (addSharedLib, R.bin), which std.Build
      passes as `--zig-lib-dir`; on Windows it stops with the old message
      if a libc++.dll.a would be linked. zig-build.sh's bash mirror
      (`build/zig-lib-static`) and its `-static-libcxx` local cache are
      gone: with one cache per zig and the mirror always used where the
      probe fires, no shared-libc++ link can enter the cache. The mirror
      stays while conda-forge's patch does; with upstream zig it does
      nothing. (The bash shims in toolchain/ keep their copy: they are
      the parity test's reference, not shipped.)
    - scripts/env.sh resolves the zig once, `$ZIG`: ZIG_BIN, else `zig`
      on PATH, else `x86_64-w64-mingw32-zig` (win-64), as rzig's
      find_zig does, and always as an absolute path: a bare name in
      ZIG_BIN is looked up on PATH, a relative path is taken from the
      project root (where pixi runs tasks), a ZIG_BIN that names no zig
      that runs stops every script that sources env.sh, and ZIG_BIN is
      exported as the result (`cygpath -m` form on Windows). Without
      that, a relative ZIG_BIN built R with upstream zig, but rzig, which
      resolves ZIG_BIN from its working directory (a package's) and
      otherwise quietly takes PATH's zig, compiled verify-package's,
      contract's and check's packages with the env's; and ZIG_BIN=zig
      skipped verify-package's compiled-package section (`[ -x zig ]`
      from the root). fetch-zig.sh drops ZIG_BIN before env.sh: it runs
      no zig and is what makes one again after `rm -rf build`.
      zig-build.sh and rzig's test.sh use `$ZIG`, and
      zig-build.sh prints `r-zig: zig = <path> (<version>; lib dir
      <dir>)`. zig's caches are `build/zig-cache/zig-<cksum of the zig
      binary: CRC-size>/{global,local}`: one per zig, and another build
      of zig at the same path (a pixi update) gets new ones. cksum reads
      the binary (0.1 s for upstream's 170 MB).
    - scripts/verify-bundle.sh: every `env -i` compile passes ZIG_BIN=$ZIG
      and env.sh's zig caches; make's and flang's directories are found
      on their own (`fc_dir` decides the Fortran checks); the section runs
      whenever there is a zig, and first checks that the bundle's zig-cc,
      from a package directory under that env -i, runs `$ZIG`
      (RZIG_PRINT_ARGV's first line after the `ZIG_LIB_DIR=` line rzig
      prints where the libc++ mirror applies). The Windows branch compiles without
      `env -i` and inherits both (comment added).
    - `pixi run fetch-zig` (scripts/fetch-zig.sh): PyPI's ziglang 0.16.0
      wheel for linux-64, linux-aarch64, osx-arm64, osx-64 or win-64,
      sha256-pinned (the five pins checked against PyPI's JSON and by
      download, 2026-10-05), unpacked with the env's unzip into
      build/zig-upstream/ziglang-0.16.0-<subdir>/ once; prints the zig's
      path (Windows: C:/... form) on stdout, nothing else. Why the wheel,
      not ziglang.org's archive: one format (zip) and one tool on every
      OS (ziglang.org has tar.xz on unix), PyPI's CDN for automated
      downloads, and it is exactly the zig the r-zig wheel's users run.
      No Python is involved and nothing enters R's build env.
    - CI: build.yaml's build steps moved, unchanged, into
      .github/workflows/build-r.yaml (`on: workflow_call`, inputs os, env,
      build_args, timeout, zig), plus one step that runs only for
      `zig: upstream` and puts fetch-zig's path into ZIG_BIN for the
      steps after it (rzig tests included). build.yaml's matrix calls it
      (legs still read "<os> / <env>"; concurrency, the ENABLE_HOSTED_JOBS
      gate and conda-package unchanged). .github/workflows/upstream-zig.yaml
      calls it for default on ubuntu-latest, macos-latest and
      windows-latest (Windows with build.yaml's `--verbose` and 90
      minutes), on workflow_dispatch, `v*` tags and pull requests
      labelled `upstream-zig` (types labeled, synchronize, opened,
      reopened; a job-level `if:` on the label, and a `labeled` event
      only for that label; such an event for another label gets a
      concurrency group of its own so it cannot cancel a run). Its legs
      read "<os> / default (upstream zig)".
  - **Upstream zig report, draft (not filed).** Title: "windows-gnu:
    `zig cc -shared` without a .def exports mingw CRT symbols (atexit),
    so an exe linking the import library fails with duplicate symbol:
    atexit". Body:

        zig 0.16.0 (ziglang.org release; also PyPI ziglang 0.16.0),
        any host, target x86_64-windows-gnu.

        lib.c:  int answer(void) { return 42; }
        main.c: #include <stdlib.h>
                int answer(void);
                static void bye(void) {}
                int main(void) { atexit(bye); return answer() == 42 ? 0 : 1; }

        zig cc -target x86_64-windows-gnu -shared -o lib.dll lib.c -Wl,--out-implib,lib.lib
        zig cc -target x86_64-windows-gnu -o main.exe main.c lib.lib

        lld-link: error: duplicate symbol: atexit
        >>> defined at .../lib/libc/mingw/crt/crtexe.c:328
        >>>            .../crt2.obj
        >>> defined at lib.lib(lib.dll)

        lib.dll exports _CRT_INIT, __mingw_module_is_dll, answer and
        atexit (llvm-readobj --coff-exports). Without a .def file LLD's
        MinGW auto-export exports every global symbol except those it
        recognizes as the C runtime's, which it recognizes by GNU object
        file names (dllcrt2.o and the like); zig's CRT objects are named
        dllcrt2.obj/crt2.obj, so crtdll.c's atexit and the CRT's other
        globals are exported as the DLL's own (with mingw-w64's own CRT
        objects, named that way, LLD leaves them out). Workaround: an object in the
        DLL with `__asm__(".section .drectve,\"yni\"\n\t.ascii \"
        -exclude-symbols:atexit\"\n\t.text");`. Expected: the CRT objects
        zig links are excluded from auto-export like mingw-w64's.

    Reproduced 2026-10-05 from linux-64 with upstream zig and with
    conda-forge's linux zig (cross-compiling; conda-forge's win-64 zig
    does not show it, see above); the workaround object makes both links
    pass.
  - **Found on the way (2026-10-05).** zig build's cache is not keyed on
    the zig lib dir: in a scratch env with `libcxx` (and R linking libc++
    on linux, a scratch-only edit), a build without the mirror on a cold
    cache gave libR, libRblas, libRlapack and stats.so `NEEDED
    libc++.so.1`; with the mirror they had none; a mirror build on the
    cache the mirrorless one had filled got the shared links back. Hence
    the rule above: the mirror is used wherever the probe fires (in
    build.zig itself, so a plain `zig build` gets it too, which the bash
    mirror in zig-build.sh never covered), and caches are per zig, so the
    pre-F4 caches (build/zig-cache/global, local) are never read again.
    The lock has two conda-forge builds of zig 0.16.0 on linux-64
    (default `_15`, minimal `_19`): they get separate caches too.
  - **Tested (linux-64, 2026-10-05, on 4868515 plus these changes).**
    - conda-forge's zig, cold caches: `pixi run rzig-test` (42 unit tests,
      parity 0 failed), build, verify-tree, smoke, contract, check,
      hermetic, verify-package; `pixi run -e minimal build`, verify-tree,
      verify-package; `pixi run -e wheel wheel && pixi run -e wheel
      wheel-test`; `pixi run -e pkg conda-package` (both packages built,
      their tests passed; the build log names `$BUILD_PREFIX/bin/zig`).
    - Upstream zig (`ZIG_BIN` from `pixi run fetch-zig`), cold caches:
      rzig-test, build, verify-tree, smoke, contract, check, hermetic,
      verify-package. The build log: `r-zig: zig = .../build/zig-upstream/
      ziglang-0.16.0-linux-64/ziglang/zig (0.16.0; lib dir ...)`; R's
      binaries' `.comment`: clang 21.1.0 and LLD 21.1.0 (conda-forge's:
      21.1.8), and fewer glibc stubs in DT_NEEDED (exec/R: libR.so and
      libc.so.6; conda-forge's also lists libm, ld-linux, libresolv,
      libpthread, libdl, librt, libutil). RZIG_TRACE=1 through the
      tree's zig-cxx runs the upstream zig; under strace,
      verify-package's compiles executed the upstream zig 67 times and
      the env's zig never.
    - ZIG_BIN as a relative path or a bare name (env.sh's resolution,
      2026-10-05): sourcing env.sh with ZIG_BIN unset, `zig`, relative,
      `./`-relative and absolute gives the absolute `$ZIG` (and the
      caches) of that file; a missing absolute, relative or bare ZIG_BIN
      stops with `error: ZIG_BIN=... names no zig that runs`; fetch-zig
      runs with a stale one. The bundle's zig-cc under verify-bundle's
      env -i, from a package directory, ran the env's zig for the old
      relative ZIG_BIN and runs the upstream zig for env.sh's export.
      `ZIG_BIN=build/zig-upstream/.../zig pixi run verify-package`
      (upstream build), `ZIG_BIN=zig pixi run verify-package` (conda-
      forge's; the compiled-package section ran) and verify-package with
      ZIG_BIN unset: passed, each printing `the bundle's compilers run the
      build's zig, <that zig>`. contract with the relative ZIG_BIN on the
      upstream tree: passed, and under strace executed the upstream zig
      719 times and the env's never. rzig-test with it: 42/42 unit tests,
      parity 0 failed.
    - Cache separation: conda build, upstream build, conda build,
      upstream build in one checkout: each conda tree identical to the
      first (`.comment` 21.1.8, same sha256 of libR, libRblas,
      libRlapack, exec/R, internet.so, stats.so, cairo.so), each upstream
      tree identical to the first upstream one (21.1.0).
    - The mirror: unit test `prepare: build.zig's use...` (none for
      upstream's layout, the mirror under any cache root, made once,
      `.failed` for a half-made one, the Windows name); a scratch copy of
      the project with `libcxx` added to its linux-64 env: build (the log
      says `r-zig: static libc++ (zig lib dir ... mirrored to
      <local cache>/r-zig/zig-lib-<key>/lib/zig)`), verify-tree (no R
      binary needs a shared libc++), contract (every compiled package's
      libc++ static), verify-package; a scratch build.zig linking a C++
      library with and without `zig_lib_dir` = the mirror under conda
      zig with libcxx: `NEEDED libc++.so.1` without, none with; the same
      under upstream zig: the probe finds nothing, static both ways.
    - fetch-zig: downloads, checks and unpacks once, then only prints the
      path (0.2 s); the zig is byte-identical to the ziglang.org
      tarball's (sha256 2317bbb9...); a wrong pinned sha256 stops it with
      nothing unpacked and nothing on stdout; the four other platforms'
      wheels downloaded and matched their pins.
    - CI: `pixi exec actionlint` (with shellcheck) on build.yaml,
      build-r.yaml and upstream-zig.yaml: no findings; a YAML parse of
      all workflows; build-r.yaml's steps are build.yaml's old steps
      (matrix → inputs) plus the upstream-zig step.
    - macOS on omicron (2026-10-05), each zig from a cold cache under
      its own key: osx-arm64 with conda-forge's zig: rzig-test, build
      (the log names the mirror build.zig made), verify-tree (16 R
      binaries, none needs a shared libc++; otool -L names libc++ in
      none), smoke, contract, check, hermetic, verify-package; with
      upstream zig (fetch-zig, the PyPI wheel): the same, no mirror line.
      Controls under conda zig: `zig build-lib -dynamic -lc++` links
      @rpath/libc++.1.dylib with the plain lib dir and nothing with the
      mirror; a scratch std.Build library with zig_lib_dir = the mirror
      is static on a cold cache, but on a cache the plain lib dir filled
      the shared link comes back (zig's cache is not keyed on the lib
      dir), which is why the mirror is always on for conda zig in a cache
      of its own. Alternating warm rebuilds in one checkout (conda,
      upstream, conda, upstream) reproduce each zig's tree byte for byte.
      osx-64 under Rosetta: build, verify-tree, verify-package with both
      zigs (the mirror fires there too; Falcon left the unsigned x86_64
      upstream zig alone). Found and fixed on the way: verify-bundle's
      new "the bundle's compilers run the build's zig" check read
      RZIG_PRINT_ARGV's first line, which is `ZIG_LIB_DIR=<mirror>`
      wherever rzig applies the mirror (every macOS conda env); it now
      skips that line.
    - win-64 on kappa (2026-10-05), cold caches: with conda-forge's zig:
      rzig-test, build (no mirror: no libc++.dll.a), verify-tree (78 PE
      files, the closure complete), smoke, contract, check, hermetic,
      verify-package, and the conda package (both outputs' tests); with
      upstream zig (fetch-zig printed the C:/ path): rzig-test, build
      (Rterm.exe and Rscript.exe link: the atexit fix), verify-tree,
      smoke, contract, check (per-file results identical to conda zig's),
      hermetic, verify-package. The export and import tables of all 21 PE
      files (R.dll, Rgraphapp, Rblas, Rlapack, Riconv, the executables,
      the 11 base-package DLLs) are identical between the two zigs, atexit
      exported by none; _CRT_INIT and __mingw_module_is_dll are still
      exported by the DLLs without a .def, identically under both.
    - On GitHub: build.yaml through build-r.yaml green on all 20 jobs
      (run 37348002704, a1edc58); upstream-zig.yaml green on its three
      legs (run 37354940568, the PR's `upstream-zig` label).
    - Not tested: linux-aarch64 with upstream zig; on Windows a ZIG_BIN other than
      fetch-zig's C:/ form, and build.zig's stop when a libc++.dll.a
      would be linked (no env has one); variants other than slim with
      upstream zig (minimal: linux with the PyPI zig in the
      investigation). Windows' verify-package does not check which zig
      its package compiles run (unix's does since this change); checked
      once by hand with RZIG_TRACE.
- **Build-machine paths in R's files (2026-10-05, What remains 7).**
  Goal 1 for the files R itself builds and installs. Measured before on
  a linux slim tree (the main checkout's dist/R-4.6.1-slim-zig, `grep
  -rlaF <checkout>`): 28 files named the build machine, 19 of R's own
  and 9 vendored conda libraries. After, in a tree built from this
  change: the 9 vendored libraries only.
  - **R's binaries.** libR.so held 314 such strings: 305 R's source
    (`__FILE__` and the DWARF file names), 7 the pixi env and 1 zig's
    cache (both from zig's compiler_rt), and the compilation directory;
    every R binary held the same kinds (stats.so 66, internet.so 9, ...),
    and libRblas and libRlapack only compiler_rt's 8. Three causes, three
    fixes:
    - Clang's own paths: build.zig `filePathFlags`, the first flags of
      every C compile of R's (addCGroup, grDevices' cairo module):
      `-ffile-compilation-dir=.` and `-ffile-prefix-map` (clang 21:
      macro and debug prefix map) for the checkout and R's source tree
      (to "", so relative to "."), the env (`conda-env/`), zig's local
      cache (`zig-cache/`: config.h and the other generated headers) and
      zig's lib dir and libc++ mirror (`zig-lib/`: libc and clang
      headers), each as given and as resolved, in order of length (the
      macro map tries the longest prefix first, the debug map the last
      flag first). That covers `__FILE__`, the OpenMP runtime's source
      locations (`;src/main/array.c;do_colsum;1931;26;;` in libR, remapped
      with the debug prefix map; without debug info, as on macOS now,
      clang writes `;unknown;unknown;0;0;;` instead, except for the
      `omp error` directive, which R does not use) and the DWARF (comp
      dir `.`, file names like `src/main/array.c`,
      `zig-lib/libc/include/...`, `zig-cache/o/<hash>/config.h`,
      `conda-env/include/zlib.h`). R's
      error messages that print `__FILE__` (R_BadLongVector, through
      LENGTH()): `strtoi(seq_len(2^31))` said `long vectors not supported
      yet: <checkout>/build/R-4.6.1/src/main/character.c:1806` and now
      says `... src/main/character.c:1806` (`crossprod` likewise,
      `src/main/array.c:1296`); upstream's make, compiling inside
      src/main, says `character.c:1806`.
    - zig's own runtime libraries (compiler_rt, glibc's libc_nonshared,
      libc++, the MinGW CRT) are built with the root module's strip
      (zig 0.16 `Compilation.compilerRtStrip`), and their DWARF names
      zig's lib dir and global cache, which no clang flag reaches
      (compiler_rt is Zig code). build.zig `linkRoot`: where R's code
      keeps debug info (linux slim and full), a link's root module is a
      stripped module of its own, one empty C file, importing the module
      that holds R's code and every link setting; a module with no C of
      its own (libRblas, libRlapack: Fortran objects, no debug info) is
      simply stripped (its symbol table goes too, its exports stay).
      Tried on a test library first: a sourceless root changes nothing
      (std.Build names a module to zig only when it has sources, and zig
      takes the first module it is given as the root); a root with an
      empty C file keeps the C module's DWARF and drops compiler_rt's.
      libR.so: 12.7 to 11.8 MiB.
    - macOS: the DWARF of R's code stays in the object files in zig's
      cache, and the binary names those files (N_OSO stabs: absolute
      paths that zig's Mach-O linker, `link/MachO/Object.zig`
      writeStabs, writes as they are; seen in a dylib cross-built from
      linux), so no prefix map can help and the debug info never shipped
      anyway. R's own Mach-O files are now stripped (newCMod), as
      minimal's already were. Windows is unchanged: the
      CodeView goes to a .pdb in zig's cache, never installed, and the
      DLL names only its file name (seen in a cross-built test DLL).
    - flang has no prefix-map flag and needs none: R's Fortran objects
      carry no debug info and no file name (the 129 flang objects in this
      worktree's zig caches: none names $HOME, none has .debug_info;
      libRblas and libRlapack held only compiler_rt's strings before,
      none now).
  - **tools/misc/top.txt** is no longer installed. R's make writes the
    source tree's absolute path there (tools/Makefile.in `$(ECHO)
    $(abs_top_srcdir)`; Makefile.win `pwd -W`) and `make install` copies
    it (`cp -R library`), so upstream ships it too. Its one reader,
    `tools:::.R_top_srcdir()` (tools/R/utils.R), finds R's sources for
    R-core's maintenance helpers (aspell over R's manuals and
    dictionaries, the DESCRIPTION fields R-exts documents) and reads a
    missing file as "" (`if(nzchar(system.file(...)))`), the answer for
    a tree without R's sources; `_R_TOP_SRCDIR_` names them for whoever
    has a copy. It is read when tools' code is lazy-loaded, so tools.rdb
    carried the path too; now `.R_top_srcdir()` is "".
  - **etc/fonts** (installEnvRuntime: unix <prefix>/etc/fonts, Windows
    R_HOME/etc/fonts): build.zig `installFontconfig` writes fonts.conf
    without the lines that name the env (`fontsConfWithoutEnv`: each is
    a `<dir>` or `<cachedir>` element on a line of its own; any other line
    naming the env stops the build) and leaves out conf.d/README (it only
    says the env's share/fontconfig/conf.avail holds the conf.d files).
    conda-forge's fontconfig 2.18 (packages unpacked for each platform):
    linux names `<env>/share/fonts`, `<env>/fonts` and the first cache
    `<env>/var/cache/fontconfig`; macOS only that cache; Windows none in
    fonts.conf (README only). What remains are the system's and the
    user's font directories (linux /usr/share/fonts; macOS
    /System/Library/Fonts and the rest; Windows' font folders; the XDG
    and ~/.fonts ones) and the XDG cache directory and ~/.fontconfig.
    The launchers set FONTCONFIG_PATH to this directory (Windows:
    etc/Renviron.site); the vendored libfontconfig names only the build
    env's etc/fonts. With an empty HOME, fc-list through the tree's
    configuration finds the host's 39 fonts and `fc-match sans` DejaVu
    Sans; svg() draws the same 24,798-byte file as before.
  - **The vendored conda libraries** keep their env's path (conda's
    prefix replacement: libcurl's CA file, OpenSSL's directory,
    fontconfig's configuration, krb5's, glib's, X11's, Tcl's script
    library): conda's binaries, not patched; R overrides the defaults
    that matter (R_ZIG_CA_BUNDLE, FONTCONFIG_PATH, TCL_LIBRARY).
  - **The check:** verify-tree.sh, on every OS, for a tree that is not a
    conda env, reads every file as bytes (binaries' strings included)
    for the checkout (ROOT and PIXI_PROJECT_ROOT), zig's two caches
    (env.sh's ZIG_*_CACHE_DIR), the env (CONDA_PREFIX) and $HOME (when
    it has at least two components, so not "/" or "/root"; on Windows
    also USERPROFILE, which MSYS' HOME need not be), as set and
    resolved, with either separator, and on Windows in the drive form too
    (cygpath -m, -l) and in any case: one ERE, so CI's /home/runner/work/
    ... and D:\a\... are just more of them. Every file of R's own must
    name none. Not R's own, and listed, not failed:
    - what vendor-libs.sh vendored, recognised by the rule vendor-libs.sh
      itself removes them by (`vendored_files` in verify-helpers.sh,
      which both scripts use; unix: a file directly in <prefix>/lib
      whose name the env's lib/ has; Windows: a DLL in R_HOME/bin/x64
      whose name the env's Library/bin has);
    - a file build.zig copies from the env as it is (minimal's make, the
      OpenMP headers, fontconfig's conf.d, Tcl/Tk's script libraries;
      Windows' binutils, renamed, and Tcl/Tk DLLs), recognised by its
      bytes (cmp against the env's files of its size, under any name),
      when $HOME is all it names. That is conda-forge's own build path
      under a $HOME of the same user name: conda-forge's macOS make
      (minimal's lib/R/bin/toolchain/make, both macOS builds in the lock)
      names /Users/runner/miniforge3/conda-bld/..., and GitHub's macOS
      runners have HOME=/Users/runner, so counting these files as R's
      own failed both macOS minimal legs (found in review). Such a copy
      that names the checkout, zig's caches or the env still fails,
      marked as build.zig's copy: the tree uses these files as they are
      (fonts.conf named the env that way before installFontconfig).
    A library directly in <prefix>/lib that the env no longer has (a
    soname bump; vendor-libs.sh leaves it, as it says) fails marked as
    an earlier run's leftover, not as R's own; on Windows a DLL in
    bin/x64 without a namesake in the env is marked "R's own, or an
    earlier run's". It prints the counts and, on failure, each offender
    with its first match. Compressed files (the lazy-load databases,
    .rds) are not looked into: What remains 9. On the old slim tree (a
    copy of the main checkout's) it failed with the 19 files of R's own;
    on a copy of the new one with five planted defects (the checkout in
    etc/Renviron, the env's include dir appended to splines.so, the
    checkout written with backslashes in base's html index, $HOME in a
    lib/ file whose name the env lacks, top.txt put back) it named
    exactly those five. After the review's changes, on linux (no macOS
    run): minimal with HOME=/home/conda (linux's make names
    /home/conda/feedstock_root/..., the same collision as macOS's)
    failed before on lib/R/bin/toolchain/make as R's own and passes now,
    listing it as build.zig's copy of bin/make; on a copy of the slim
    tree, the env's own fonts.conf put back fails marked as build.zig's
    copy of etc/fonts/fonts.conf, a renamed copy of the env's make is
    recognised under its new name, a libcurl.so.3 the env lacks fails
    marked as a leftover, and the checkout in etc/Renviron and $HOME in
    base's DESCRIPTION fail as R's own.
  - Tested (linux-64, 2026-10-05, on a1edc58 plus this change and
    "gfortran removed" below; a new worktree, cold zig caches):
    `pixi run rzig-test` (42 unit tests; parity: 0 failed); default
    with conda-forge's zig: build, verify-tree (1,892 files of R's own,
    none naming the build machine; 49 vendored, 9 naming the env: libcurl,
    libcrypto, krb5 and gssapi, pango, glib, gio, fontconfig, X11), smoke,
    contract (Rcpp, data.table, minqa, quadprog, pak, ps), check (one
    NOTE, tools-Ex, as before), hermetic, verify-package; the same build
    and verify-tree with upstream zig (fetch-zig; `.comment` clang
    21.1.0: the same counts, libR's DWARF as clean); minimal: build,
    verify-tree (1,380 own, none; 22 vendored, 4 naming the env; the old
    minimal tree had 11 files of R's own naming it), verify-package,
    then `pixi run -e wheel wheel` (its note now lists only the 4
    vendored libraries) and wheel-test; full: build, verify-tree (2,296
    own, none; 58 vendored, 11 naming the env, libtcl8.6 and libtinfo
    among them), smoke; the conda packages (`pixi run -e pkg
    conda-package`: both outputs' tests passed). In the unpacked
    r-zig-slim `_4`, no file of the package names rattler's work dir,
    its host env or its build env (zig's lib dir) or R's source path;
    the package built from the main checkout on 2026-10-03 had 17, 5, 16
    and 14 such files (libR's DWARF named `$BUILD_PREFIX/lib/zig/libc/
    glibc/io/fstat-2.32.c` and the like, from libc_nonshared; and
    `$PREFIX/include/zlib.h`). Only rattler-build's own
    info/recipe/*.yaml name them. Before and after, libR.so's strings
    naming $HOME: 314 (main checkout tree) and 0 (both zigs); the whole
    slim tree: 28 files and 9 (the vendored ones).
    macOS on omicron (conda-forge's zig, cold caches): osx-arm64
    rzig-test, build, verify-tree (1893 of R's own files clean; 41
    vendored, 9 naming the env), smoke, contract, check, hermetic,
    verify-package; minimal build and verify-tree, also with
    HOME=/Users/runner as on GitHub's macOS runners (minimal's
    bin/toolchain/make, a verbatim copy of conda-forge's, names
    /Users/runner/miniforge3/conda-bld/...: listed, not failed); full
    build and verify-tree; osx-64 under Rosetta build, verify-tree,
    verify-package. R's Mach-O binaries have no N_OSO stabs and no debug
    sections (stripped), libR has 56 relative `src/...` strings and no
    absolute one; `rawToChar(raw(2^31))` reports `src/main/raw.c:68`; a
    planted copy failed naming exactly its 3 files. fonts.conf there
    only loses its `<cachedir>` line; R's cairo text on macOS goes
    through pango's CoreText backend, so fontconfig reads it only with
    PANGOCAIRO_BACKEND=fc (checked by hand: the tree's fonts.conf and
    conf.d load, Helvetica for sans, the cache in $HOME/.cache).
    win-64 on kappa (conda-forge's zig): rzig-test, build (the first,
    cold attempt hit the known MSYS fork flake in winMakeImportStub's
    `wc`; the re-run passed), verify-tree (2892 of R's own files clean;
    43 vendored, none naming the env: conda's win-64 DLLs carry no env
    prefix, only conda-forge's own D:\bld paths), smoke, contract,
    check (its usual two NOTEs), hermetic, verify-package, the conda
    package (both outputs' tests; every file of both packages scanned as
    bytes and UTF-16: only rattler-build's info/recipe/rendered_recipe.yaml
    names its work dir, where the published win-64 r-zig-slim _3 had 14
    such files, R.dll alone 84 strings). Found and fixed there: the
    check's path pattern took one character per separator, so a path
    with doubled backslashes (`C:\\Users\\...`, the form _3's R.dll had)
    was missed; a separator now matches once or more, and a planted
    copy with seven forms (backslash, lower case, MSYS /c/, doubled
    backslashes, ...) fails naming all seven. R.dll's `__FILE__` reads
    `src\main\character.c` in the pixi build; in the conda build it
    reads `\src\main\character.c` (leading backslash; R.dll only, not
    the package DLLs; cosmetic, cause not established). R's Windows
    cairo text uses Win32 fonts, not fontconfig (cairoFns.c's
    fontconfig path is `!defined(_WIN32)`), so fonts.conf there only
    serves fontconfig users. Not tested: linux-aarch64 (CI), the
    openblas variants, upstream zig on macOS and Windows.
- **gfortran removed (2026-10-05, What remains 6).** With linux-64 on
  flang-zig (2026-10-03) no platform used gfortran, and its branch was
  dead code that could still be taken: in an env without flang,
  configure-only.sh would have captured a config with whatever gfortran
  PATH had (env.sh), and build.zig would have taken its gfortran branch
  and failed deep in a gcc lookup. Now flang is the one Fortran compiler:
  - build.zig: `FortranCompiler` and `Ctx.fc` are gone, with
    `findGfortranLibDir` and `Ctx.gfortran_lib_dir` (and `Ctx.arch`, used
    only for the gcc triples), the gfortran cases of `linkFortranRt`
    (macOS emutls/heapt/gfortran/quadmath, MinGW's libgfortran and the
    libgcc_s import library made for it by `winMakeImportLibFor`, which
    went too, as nothing else used it; linux libgfortran) and of
    `fortranOne` (`-J`, macOS `-O1`, linux `-fno-tree-loop-vectorize`),
    the subst.txt "captured with flang but built with gfortran" check,
    and on Windows the gfortran values of FC, FLIBS, FC_VER and
    SAFE_FFLAGS (the vendored Makeconf.win's `@SAFE_FFLAGS_SSE@` became
    a plain `-O2`, what it always was with flang). The flang probe (the
    build env, then the env: never PATH) stops with one error when it
    finds none: `error: no flang in this environment (looked for
    <env>/bin/flang): R's Fortran needs flang-pixi's flang-zig, a
    dependency in pixi.toml and recipe/recipe.yaml`, and the build log
    names the flang it found. Windows' bootstrap R_SYSTEM_ABI (Windows
    has no configure to capture it) said `windows,gcc,gxx,gfortran,
    gfortran` and now says `windows,gcc,gxx,flang,flang`. tools'
    sotools.R reads it when tools is lazy-loaded, so the value is fixed
    in tools.rdb, and it chooses the rows of R CMD check's table of
    compiled-code symbols: on Windows now the 51 `windows, Fortran,
    flang` rows (_FortranAStopStatement, _FortranAio*, _FortranARandom*,
    rand_; upstream's LLVM build uses them too, tools/Makefile.win's
    `windows,clang,clang++,flang,flang`) instead of the 19 gfortran ones.
    The outcome should not change. check_so_symbols on Windows reads a
    DLL's import table, and flang-rt-zig on win-64 is a static library,
    so no package DLL imports a _FortranA* symbol, as none imported a
    _gfortran_* one. With the objects' symbol tables (R CMD check sets
    _R_SHLIB_BUILD_OBJECTS_SYMBOL_TABLES_), check_so_symbols also counts
    the table's first four rows as found and looks for them in the
    objects; those were gfortran's st_open, st_close, st_rewind and
    st_write and are now abort (gcc's and gxx's rows), _assert and exit,
    which an object calling them was already reported for through the
    DLL's imports from the C runtime. Unix differs: its captures say
    `ClassicFlang` (configure's name for an FC called flang), whose 11
    rows name Classic Flang's f90io_* runtime, so there no Fortran row
    ever matches LLVM flang's objects; on Windows the flang rows are now
    live. Not tested: R CMD check of a Fortran package on Windows with
    the new value.
  - scripts/env.sh `fortran_compiler`: flang or flang-new, else
    `error: no flang in the pixi environment: R's Fortran needs
    flang-pixi's flang-zig (pixi.toml)`. zigbuild/tools/configure-only.sh
    lost its gfortran `-O1` cap and its `case` on the compiler.
    zigbuild/tools/gen-subst.sh lost the two sed expressions that
    dropped conda's sysroot directories, which only gfortran's implicit
    search dirs put into FLIBS and R_LD_LIBRARY_PATH (linux-aarch64).
  - Comments in pixi.toml, recipe.yaml and contract-test.sh. Kept:
    history (records, the recipe's build-number comments), the bash
    shims in toolchain/ (parity-test.sh's reference), rzig's Windows
    `-lgfortran` lookup for packages that ask for it (What remains 10),
    and upstream's own text in the vendored Windows config.h and
    Makeconf.win.
  - Tested (linux-64): build.zig's probe with a CONDA_PREFIX that has no
    flang (the error above, nothing else run), env.sh's
    `fortran_compiler` with PATH=/usr/bin:/bin (its error, exit 1);
    `pixi run configure` then gen-subst.sh with the new scripts:
    linux-x86_64-slim's subst.txt, config.h, Rconfig.h and
    GENERATED_FROM came out byte-identical to the vendored ones; and the
    builds and checks of the record above; macOS: the same builds and
    checks, and a build with the env's flang moved aside (the one error,
    from build.zig and from env.sh); win-64: build, contract (quadprog
    with the plain `SAFE_FFLAGS = -O2`), check, verify-package, the
    conda package, `tools:::system_ABI` = `windows gcc gxx flang flang`,
    and the no-flang error. Not tested: R CMD check of a Fortran package
    on Windows with the new R_SYSTEM_ABI; linux-aarch64 (CI).

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
      loads in a fresh R. **Correction (2026-10-02, F3b's critique):**
      its "TRUE" was not the env's library: the package mapped the
      *host's* `/usr/lib/x86_64-linux-gnu/libfontconfig.so.1`. exec/R
      carries DT_RUNPATH, which glibc does not apply to a dlopened
      library's dependencies either, so without the rpath even R's own
      process binds host libraries, silently. The rpath stays, now added
      by rzig (F3b), and the probe is gone.
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
  - **F1.6 done 2026-10-03** (a workflow: an implementer in a worktree,
    two review lenses, a skeptic each, a fix pass; then the macOS and
    Windows runs here). verify-bundle.sh is split by what a check needs:
    - scripts/verify-tree.sh (pixi task `verify-tree`, on the installed
      tree right after the build, about 4 s): the compilers are rzig;
      Makeconf (no build path, the tree's own path included, no rpath,
      CPPFLAGS/LDFLAGS empty, FLIBS, FC = zig-fc); the linux glibc
      ceiling; every rpath relative; no shared C++ runtime in R's
      binaries; macOS minos and load commands; minimal's excluded
      libraries; and a guard that the binary list is not empty.
    - scripts/verify-bundle.sh (`verify-package`, after `package`): what
      needs the extracted archive: R running from a new place under
      `env -i`, TLS with the shipped CA bundle, the compiled packages
      built and loaded there (C++, Fortran, `USE_FC_TO_LINK`, `$(FLIBS)`
      without flang, OpenMP, the decoy CONDA_PREFIX runs, zig-fc without
      flang), the Windows dry runs.
    - scripts/verify-helpers.sh: what both use (needed_of, rpaths_of,
      cxx_deps, minos_over_floor). No check was lost or weakened: the 16
      check lines of the old script are exactly the union of the two
      new ones on the same archive; defects planted in copies of the
      slim and minimal trees (an absolute rpath, a Makeconf build path,
      a script in place of rzig, a shared libc++, ...) were all caught.
    - hermetic runs on a copy of the installed tree (resolved through
      symlinks first), before the archive on unix; on Windows after
      `package`, which is what copies conda's DLLs and Tcl into the tree
      (vendor-libs.sh does nothing there), with a clear error if run
      before it.
    CI order (unix): rzig tests, build, verify-tree, smoke, contract,
    check, hermetic, package + verify-package, the wheel; Windows: rzig
    tests, build, verify-tree, smoke, contract, package + verify-package,
    hermetic. verify-tree runs on the legs verify-package ran on
    (default, minimal); it also passes on linux-64 full and openblas.
- F1.7: Windows joins the CI matrix, and the installed tree is the shipped
  tree on every OS. Why Windows was a separate CI job (asked 2026-10-03):
  history (gnuwin32 and the bash shims were a different build; gone since
  F1/F3) plus four differences: one variant only (R's Windows build has
  no slim/minimal switches; no wheel, no openblas); no `check` step (R's
  regression suite was wired only into build.zig's unix path); hermetic
  had to follow `package`, because only package-standalone.sh vendored
  conda's DLLs and Tcl into the tree; `build -- --verbose` and a
  60-minute timeout against MSYS process-spawn hangs.
  - **F1.7 done 2026-10-03** (a workflow: two implementers in worktrees,
    one for vendoring and CI, one for the Windows check; two review lenses
    and a skeptic each; a fix pass each; merged here, with the integration
    edits below; then the runs on every OS).
  - **`package` only archives, on every OS.** Everything the tree needs
    from the env arrives with the build:
    - build.zig `installEnvRuntime`, for a tree that is not the env
      (`!prefix_is_env`; the conda build's env packages provide it all):
      unix: the env's CA bundle as R_HOME/etc/ca-bundle.crt and
      R_ZIG_CA_BUNDLE in etc/Renviron (finalRenviron; the build fails
      without the bundle), fontconfig's etc/fonts as <prefix>/etc/fonts
      (symlinks followed: conda-forge's conf.d links into
      share/fontconfig, which `cp -a` used to ship as dangling links), and
      in full Tcl/Tk's script libraries and Tcl's modules as
      <prefix>/lib/{tcl8.6,tk8.6,tcl8} with TCL_LIBRARY in etc/Renviron.
      Windows: Tcl/Tk in R_HOME/Tcl, CRAN's layout (the DLLs in Tcl/bin
      only; tcl8.6, tk8.6 and tcl8 in Tcl/lib), fontconfig's configuration
      in R_HOME/etc/fonts with FONTCONFIG_PATH in etc/Renviron.site, which
      installEnvRuntime now writes (with the preflight's hint); in the
      conda build it sets `MY_TCLTK=${R_HOME}/../../bin`, the tk package's
      DLLs (a conda env has no R_HOME/Tcl; Tcl finds its scripts in
      Library/lib beside the DLL).
    - scripts/vendor-libs.sh: on Windows the DLL closure walk that
      package-standalone.sh did (every PE in the tree, conda's Library/bin
      DLLs into R_HOME/bin/x64, the Tcl DLLs never there). zig-build.sh
      runs it before and after zig build, and each run first removes what
      an earlier one copied (files whose name the env also has), so a copy
      that predates a `pixi update` never ships or wins the search order
      during the build's own R runs (Windows: bin/x64 before PATH; macOS:
      the rpath before the fallback). A library the env no longer has at
      all (a soname bump) stays until the tree is removed. The
      prefix-is-env test compares `cygpath -m -l`, lower-cased, on Windows.
    - scripts/package-standalone.sh: the archive and its sha256 (named by
      basename, so `sha256sum -c` works beside it), nothing else.
    - scripts/env.sh no longer exports MY_TCLTK/TCL_LIBRARY on Windows:
      the dev tree ships its own Tcl/Tk now, and every check loads it.
  - **`check` on Windows** (build.zig `addCheckStepWindows`): R's own
    tests/Makefile.win, unmodified, targets test-Examples, test-Specific
    and test-Reg (as unix; Internet left out on both, it needs the
    network and upstream ignores its failures). It runs in a stand-in for
    R_HOME/tests made fresh on every run (a first step removes and copies
    it: the WriteFiles scaffolding, MkRules from MkRules.rules,
    share/make/vars.mk, bin/x64/{Rterm,R,Rcmd} scripts that exec the
    installed tree's .exe, plus R's tests/ from the source), so no output
    of an earlier run is reused. Examples are compared with R's
    .Rout.save (`TEST_DONTTEST=FALSE,srcdir=getwd()`, the one variable
    Makefile.win puts into its R call). No TZ, as upstream (so
    registryTZ.c is exercised; unix keeps TZ=UTC). MY_TCLTK and
    TCL_LIBRARY are removed, so the tcltk examples load the tree's own
    Tcl/Tk. Left out, as unix's configure leaves them out without the
    recommended packages: eval-etc-2.R (Matrix), reg-tests-3.R and
    reg-examples3.R (MASS, survival, Matrix). About 6.5 minutes on kappa,
    including zig re-running the bootstrap.
  - **Bugs found and fixed:**
    1. Windows built no tcltk.dll: `library(tcltk)` failed with "DLL
       'tcltk' not found" while capabilities("tcltk") said TRUE (found by
       check's tcltk examples). `winTcltkLib`, from tcltk's Makefile.win
       (`WIN_TCLTK_LIBS = -ltcl86t -ltk86t -luser32`, conda's Tcl is the
       threaded build).
    2. Windows' winCairo.dll imported `pkg_grDevices.dll`, the zig
       artifact's name, while the tree has grDevices.dll: svg(),
       cairo_pdf() and png(type = "cairo") failed with "unable to load
       winCairo.dll", capabilities("cairo") TRUE (found by verify-tree's
       new DLL closure check). The Windows grDevices artifact is named
       grDevices. smoke now draws with svg() and png(type = "cairo") on
       every OS, and recipe/test-win.R with svg().
    3. linux full: conda-forge's libtcl8.6.so and libtk8.6.so carry no
       DT_SONAME, so lld recorded the path zig gave it, the build env's
       absolute one, in tcltk.so's DT_NEEDED: vendor-libs.sh never copied
       them and off the build machine library(tcltk) failed in dyn.load.
       tcltk.so now links copies (in the cache) that patchelf gives their
       file name as DT_SONAME, and has the package rpaths. Also every
       unix full tree shipped no Tcl script library (Tcl_Init failed off
       the build machine): installEnvRuntime above.
    4. Windows' R_HOME/Tcl lacked lib/tcl8 (msgcat: `clock format`
       failed), and in a win-64 conda env tcltk could not find Tcl at all
       (no R_HOME/Tcl, no MY_TCLTK): installEnvRuntime above;
       recipe/test-win.R loads tcltk and runs `clock format`.
    5. The recipe's win-64 host env solved tk 9.0.4 (unpinned there),
       while pixi.lock has 8.6.13: with tcltk.dll now built, the conda
       build's link of -ltcl86t failed (tk 9 ships tcl90.dll and
       tcl9tk90.dll). tk is pinned to 8.6.* in pixi.toml (win-64 and the
       tcltk feature) and in the recipe (win host and run), the version
       WIN_TCLTK_LIBS, unix full's -ltcl8.6 and the R_HOME/Tcl and
       lib/tcl8.6 layouts are written for. Tcl/Tk 9 is a later, separate
       change.
  - **New checks.** verify-tree.sh: unix (not a conda env) the CA bundle
    and R_ZIG_CA_BUNDLE line, full's Tcl/Tk scripts and TCL_LIBRARY
    lines, linux every DT_NEEDED a bare name; Windows the Tcl/Tk runtime
    (none in bin/x64) and the DLL closure (every import of every PE in the
    tree is in its own directory, bin/x64, Tcl/bin for the Tcl DLLs, or
    the system's). hermetic-check.sh on Windows loads tcltk from R_HOME/
    Tcl with an empty environment and requires Tcl's and Tk's script
    libraries to be under it; verify-bundle.sh (unix full) loads tcltk
    from the extracted archive under env -i.
  - **CI:** build-windows is folded into the build matrix
    (`windows-latest`/`default` with `build_args: "-- --verbose"` and
    `timeout: 90`); one step order on every OS: rzig tests, build,
    verify-tree, smoke, contract, check, hermetic, package +
    verify-package, the wheel (minimal). The 14 unix legs run exactly the
    commands they ran before; Windows gains check, and hermetic moves
    before package.
  - **Tested 2026-10-03:** linux-64 default (build, verify-tree, smoke,
    contract, check, hermetic, verify-package), minimal (build,
    verify-tree, hermetic, verify-package), the wheel and wheel-test, the
    conda package; full (build, verify-tree, smoke, verify-package with
    tcltk from the extracted archive; by the implementer, before the
    merge). osx-arm64 on omicron: slim (the same seven), minimal, the
    wheel, full (build, verify-tree, smoke, verify-package: tcltk from
    the extracted archive's lib/tcl8.6); its conda package did not run
    (omicron's downloads of the new zig_impl build kept being cut off;
    CI builds it). osx-64 under
    Rosetta: build, verify-tree, smoke, hermetic, verify-package. win-64
    on kappa from a removed tree (so vendoring ran from scratch): build,
    smoke, contract, check, hermetic (tcltk from R_HOME/Tcl), verify-package
    passed, verify-tree found bug 2; after its fix build, verify-tree
    (77 PE files, the closure complete), smoke (the cairo devices draw),
    check, hermetic and verify-package passed, and the conda package
    (after bug 5's pin) passed its tests, svg() and tcltk through
    MY_TCLTK included.
    linux-aarch64: CI.
  - **Open:** Windows' etc/x64/Makeconf keeps `TCL_VERSION = 86`, so a
    package that links Tcl/Tk through it (tkrplot) asks for -ltcl86, while
    conda ships tcl86t (and the standalone tree has no Tcl import
    libraries); untested. The Windows check prints two NOTEs: tools-Ex
    (the Windows tree has no COPYING, linux's has) and stats-Ex (two
    htest titles wrap differently). The tree ships no R_HOME/tests (as on
    unix).
- OpenMP for packages, the same on every OS (2026-10-04). Asked: "Is
  there any particular reason for libomp 22.1.8 on Linux? Should we
  standardize?" No reason: lock inertia. And the standalone Windows tree
  offered `SHLIB_OPENMP_*FLAGS = -fopenmp` in etc/x64/Makeconf but shipped
  no omp.h, libomp.lib or libomp.dll: an OpenMP package compiled with the
  tree alone failed with "'omp.h' file not found" (kappa, 2026-10-04); only
  the pixi env as R_ZIG_EXTRA_ENV, or a conda env, made it build.
  - **One libomp release everywhere.** pixi.toml had `llvm-openmp = "*"`,
    and nothing asked for more (`pixi tree -i llvm-openmp`: only
    flang-rt-zig needs it), so the lock kept 22.1.8 on linux-64,
    linux-aarch64, osx-64 and osx-arm64, while minimal had 23.1.2 and
    win-64 23.1.1 (flang-rt-zig build 4 requires >= 23.1.1 there). Now
    `llvm-openmp = "23.*"`, the LLVM major of flang-zig/flang-rt-zig,
    whose omp_lib.mod `use omp_lib` compiles against, in pixi.toml and in
    recipe.yaml's host (the conda build uses the libomp CI tests).
    r-zig-slim's run keeps a bare `llvm-openmp` (review, 2026-10-04): the
    host package's run export already gives it `>=23.1.2`, so a `23.*`
    there would add only `<24`. libomp does not need that (a newer libomp
    runs code built against an older omp.h or omp_lib.mod; conda-forge's
    run exports carry only a lower bound, and flang-rt-zig depends on
    llvm-openmp unbounded), and it would clash with every package built
    against llvm-openmp 24 (run export `>=24`) once conda-forge moves,
    each LLVM major then needing a recipe edit and a build-number bump.
    Package C code is compiled by zig's clang (21.1.8), not LLVM 23,
    anyway. `pixi update llvm-openmp`
    moved only it: 22.1.8 to 23.1.2 on the four unix platforms and 23.1.1
    to 23.1.2 on win-64, in default, full, openblas, full-openblas and
    pkg; minimal (23.1.2 already) and wheel unchanged; no other package
    in any environment moved (compared per environment and platform).
    The recipe's build number stays 4 (not on the channel yet).
  - **Windows: OpenMP for packages, as unix has it.** R itself stays
    without OpenMP on Windows, as upstream (gnuwin32's config.h leaves
    HAVE_OPENMP off, "has it, but it is too slow to be usable", said of
    GCC's libgomp under MinGW-w64; R's own OpenMP threads default to 1
    everywhere anyway); build.zig says so at R.dll's link, where a stale
    comment claimed conda-forge ships no LLVM libomp for Windows. Packages:
    build.zig `installOpenMP`, one function for every OS (it replaces
    unix's inline omp.h block), for a tree that is not the env and a
    profile with OpenMP: llvm-openmp's headers into the environment's
    include/ where rzig looks (unix `<prefix>/include`: omp.h, ompx.h,
    omp-tools.h, ompt.h; Windows `<prefix>/Library/include`: omp.h and
    ompx.h, all that win-64's package has; omp.h required, the others when
    present), and on Windows libomp.lib into `<prefix>/Library/lib` (rzig's
    -L, where windows.libs resolves -lomp). Windows' `ctx.openmp` (true;
    R itself never compiles with it) also drives etc/x64/Makeconf's
    `@OPENMP@`, which was hardcoded to -fopenmp, so one value decides
    both what Makeconf offers and what the tree carries for it.
  - **libomp.dll comes from vendor-libs.sh**, into R_HOME/bin/x64 beside
    R's executables, where the loader finds a package DLL's import of it
    (R's LoadLibrary searches the exe's directory first), as libomp comes
    from it on unix. vendor-libs.sh removes every file in bin/x64 (unix:
    `<prefix>/lib`) whose name the env also has, then copies the closure
    of the tree's PE files again; nothing in the tree imports libomp.dll,
    so its walk takes it as a root where the tree has
    `Library/lib/libomp.lib` (installOpenMP's decision, made in one
    place), with its own imports (VCRUNTIME140.dll, already vendored for
    conda's other DLLs). A first version had zig build install
    libomp.dll and changed the clearing rule to keep any copy still
    byte-identical to the env's file, so the post-build run would not
    delete it. Review (2026-10-04): that kept, in a reused tree, every
    library the tree no longer needs while the env still has it
    unchanged, and package and the wheel archive the tree as it is (e.g.
    macOS minimal's ICU, about 14 MiB, after a `libcurl <8.21` pin, since
    zig's closure keeps ICU in the env). Reverted to remove-all.
  - **New checks.** verify-tree.sh, wherever Makeconf offers OpenMP in a
    tree that is not a conda env: Windows `Library/include/omp.h`,
    `Library/lib/libomp.lib` and `R_HOME/bin/x64/libomp.dll`; unix
    `include/omp.h` and `lib/libomp.{so,dylib}`. verify-bundle.sh: on
    Windows, in the extracted zip, the C shapes unix checks (a package
    with `$(SHLIB_OPENMP_CFLAGS)` on the compile and the link, a flagless
    omp.h probe, `PKG_LIBS = -lomp` alone, resolved to the tree's
    libomp.lib by windows.libs) and two Fortran packages doing `use
    omp_lib` (through `.Fortran`), R-exts' two forms: `PKG_FFLAGS =
    $(SHLIB_OPENMP_FFLAGS)` with `PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)`
    (linked by gcc.exe, rzig) and `USE_FC_TO_LINK` with
    `$(SHLIB_OPENMP_FFLAGS)` (linked by zig-fc), built with
    R_ZIG_EXTRA_ENV empty and a poisoned CONDA_PREFIX (zig, make, sh and
    flang from PATH), each package importing libomp.dll, then loaded in an
    R with an empty environment and PATH = bin\x64 + System32. On unix,
    the same two Fortran packages under env -i from the extracted archive
    (no rpath, no shared flang runtime). Every OpenMP package must link
    libomp itself (unix: NEEDED, for the C ones too): libR has it loaded
    already and a shared link may leave symbols undefined (macOS
    Makeconf: `-undefined dynamic_lookup`), so a dropped -lomp would
    still load. The Fortran source counts the threads of a
    `num_threads(2)` region, which must be 2: without -fopenmp on the
    compile the directives are comments, `use omp_lib` still compiles and
    links, and the old checks (`omp_get_max_threads() >= 1`, the sum
    5050) still passed. minimal's empty `SHLIB_OPENMP_*FLAGS` stay
    contract-test.sh's (a copy in verify-bundle.sh was dropped in review:
    a static read of the file, which F1.6 keeps out of the archive
    checks, and contract runs on every minimal leg first).
  - **Tested 2026-10-04 (first version, before the review).** linux-64,
    cold zig cache (a new worktree): default build (libR's NEEDED
    libomp.so is the vendored
    `lib/libomp.so`, byte-identical to the env's llvm-openmp 23.1.2
    file), verify-tree, smoke, contract (data.table: `OpenMP version
    (_OPENMP) 202011`), check (one NOTE, tools-Ex, as before), hermetic,
    verify-package (the Fortran OpenMP packages: NEEDED libomp.so, no
    RUNPATH, 16 threads); a stale-copy run of vendor-libs.sh (two copies
    made to differ were removed and copied again, an identical one with an
    old mtime stayed); minimal build, verify-tree, verify-package (its
    OpenMP flags empty); full build, verify-tree, verify-package; the
    conda packages (both outputs' tests passed; r-zig-slim `_4` runs with
    `llvm-openmp 23.*` and the run export `>=23.1.2`). win-64 on kappa (the tree left
    by an earlier build: the pre-build vendor-libs run kept all its
    copies, as identical): build, verify-tree (78 PE files, the closure
    complete), smoke, contract (data.table with OpenMP), hermetic,
    verify-package (the C and both Fortran packages built with the tree
    alone and loaded with PATH = bin\x64 + System32, 12 threads). Planted
    defects, each caught: a copy of the installed tree without
    bin/x64/libomp.dll, then without Library/include/omp.h (verify-tree
    names the missing file; the restored copy passes); the zip without
    libomp.dll (the load fails, "LoadLibrary failure: The specified module
    could not be found") and without omp.h (the C package fails, "'omp.h'
    file not found"). A copy of zlib.dll made to differ was removed and
    copied again, libomp.dll stayed. The win-64 conda packages: both
    outputs' tests passed (llvm-openmp 23.1.2 in the test envs). Not
    tested: macOS and linux-aarch64 (for them: llvm-openmp 22.1.8 to
    23.1.2, vendor-libs.sh's rule, the new checks), openblas, the wheel.
  - **Review fixes, tested 2026-10-04.** (r-zig-slim's run unpinned;
    libomp.dll from vendor-libs.sh, the remove-all rule back; Windows'
    `@OPENMP@` from `ctx.openmp`; the libomp and two-thread checks;
    Windows' probe and `-lomp` packages; minimal's copy of the Makeconf
    check dropped; stale comments in pixi.toml, build.yaml and
    verify-tree.sh.) linux-64, warm zig cache: a copy of the env's
    libgomp.so.1, which nothing links, planted in the slim tree's lib/
    was removed by the next build's first vendor-libs run, the vendored
    set otherwise unchanged (49 libraries); slim build, verify-tree,
    smoke, hermetic, verify-package (omp.so, lomp.so, fomp.so and
    fompfc.so NEED libomp.so; the num_threads(2) region ran on 2
    threads); minimal build, verify-tree, verify-package, contract (its
    empty `SHLIB_OPENMP_*FLAGS`); full build, verify-tree,
    verify-package; the conda packages (both outputs' tests passed;
    r-zig-slim `_4`'s index.json depends on `llvm-openmp` and the run
    export `llvm-openmp >=23.1.2`, no upper bound). Planted defects in a
    copy of verify-bundle.sh, each caught: fomp compiled without
    `$(SHLIB_OPENMP_FFLAGS)` ("r$t == 2L is not TRUE"), fomp linked
    without `$(SHLIB_OPENMP_CFLAGS)` ("does not link libomp"), omp.so
    linked without it ("omp.so does not link libomp"). win-64 on kappa,
    with the tree's Library/lib/libomp.lib and bin/x64/libomp.dll
    deleted first: build (the pre-build vendor-libs run, no libomp.lib
    yet, copied 42 DLLs; the post-build run 43, libomp.dll among them),
    verify-tree, smoke, contract (data.table `OpenMP version (_OPENMP)
    202011`), hermetic, verify-package (probe, omp, lomp, fomp and fompfc
    built with the tree alone, each but the probe importing libomp.dll,
    loaded with PATH = bin\x64 + System32, 12 threads, the region on 2);
    planted: fomp compiled without `$(SHLIB_OPENMP_FFLAGS)` fails the
    load ("r$t == 2L is not TRUE"). After the merge, macOS on omicron
    (warm zig caches, llvm-openmp 23.1.2): osx-arm64 slim build,
    verify-tree (omp.h, libomp.dylib), smoke, contract, hermetic,
    verify-package (both Fortran OpenMP packages: 10 threads, the region
    on 2, linked to the tree's libomp, no rpath), minimal build,
    verify-tree, contract, verify-package, the wheel and wheel-test, full
    build, verify-tree, verify-package; osx-64 under Rosetta: build,
    verify-tree, contract, hermetic (CRAN R6 from source), verify-package.
    omicron's network cut several pixi solves and one CRAN download
    (hermetic's first try); the retries passed. Not tested after the
    review fixes: linux-aarch64 (CI), openblas, the win-64 conda packages
    (passed before the fixes).

Order: T's conda and wheel parts (done) → F1 (done) → F2 (done) → F3a/F3b/F3c (done) → F1.7 (done) → F4 (done on
linux-64, 2026-10-05) → T's standalone split (it needs F1's layout and
F3's binary) → P. The decisions this branch made stay valid through F: tiers,
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
mirror against conda-forge zig's shared libc++ (kept by F4 while the feedstock patch is there), the SONAME
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

## Windows minimal and the Windows wheel (major todo, after the current tasks)

Decided 2026-10-04: the next major item once the current work (the OpenMP
gaps, then the queued phases) is done. Today Windows has one profile
(win-x86_64-full) and no wheel.

**A minimal tree on Windows: work, not blockers.** Windows R has no
configure, so build.zig's buildWindows mirrors gnuwin32's one profile and
builds everything unconditionally. Upstream's switches decide what a
Windows minimal can drop without patching R:
- Upstream can turn off: ICU (`USE_ICU`, MkRules.rules; the largest size
  win), cairo (`USE_CAIRO`: winCairo.dll and the pango/fontconfig/
  freetype/harfbuzz/glib closure). The Tcl/Tk runtime is an optional
  component of CRAN's installer; without R_HOME/Tcl, `library(tcltk)`
  stops with "Tcl/Tk support files were not installed".
- Upstream always builds: png/jpeg/tiff in grDevices.dll (no switch), R's
  own NLS (src/extra/intl), libcurl (`USE_LIBCURL = yes`, required).
So a Windows minimal is "minimal within upstream's switches": no ICU, no
cairo, no Tcl/Tk runtime, no OpenMP for packages (empty
SHLIB_OPENMP_*FLAGS, so the Windows libomp of the OpenMP work is not
shipped); png/jpeg/tiff and NLS stay. Its capability profile therefore
differs from unix minimal and needs its own assertions (smoke, contract).
Work: a hand-written zigbuild/config/win-x86_64-minimal (config.h,
Rconfig.h, subst.txt link lists), variant switches in buildWindows
(winCairo, tcltk's DLL and R_HOME/Tcl, ICU in WIN_R_DLL_LIBS), and a
windows-latest/minimal CI leg.

**The Windows wheel.**
1. The real blocker is the userland package compilation needs. On
   Windows, `R CMD INSTALL` of a package with compiled code runs `make`,
   whose recipes need `sh`, `rm`, `cp`, `sed`, and runs `configure.win`
   with `sh`. Unix gets away with bundling only make (every system has
   /bin/sh and the tools); Windows has none of them (Rtools exists to
   provide them; the pixi env takes them from MSYS2: m2-bash, m2-make,
   coreutils). Options: bundle MSYS2's bash/make/coreutils as Rtools does
   (heavy, and the process-spawning layer behind windows-latest's build
   hangs); busybox-w32 (one small exe: sh and the tools) plus a native GNU
   make (light, untested with R's makefiles); or first a wheel without
   compile support: tier 0/1 (binary and R-only source packages) needs
   nothing beyond R's own bin\x64 and System32, which hermetic proves on
   every Windows run, and CRAN ships Windows binaries for nearly every
   package, so such a wheel is already useful there (unlike linux).
2. Plumbing, all solvable: make-wheel.py produces only manylinux and
   macosx tags (it dies on anything else) and knows only the unix layout
   (needs win_amd64, Library/lib/R, R.exe/Rscript.exe launchers);
   embedding R in Python (rpy2) needs r_zig to call
   `os.add_dll_directory` on R_HOME/bin/x64 (Python 3.8+ does not search
   PATH for a loaded DLL's dependencies); wheel-test.sh is unix-only;
   rzig finding zig from PyPI's ziglang (which has Windows wheels) is
   untried on Windows. (F4: R builds on win-64 with PyPI's ziglang
   through ZIG_BIN, with build.zig's atexit fix, kappa 2026-10-04;
   packages linking `-lsynchronization` do not, What remains 8.)
3. Not a blocker: Fortran (the unix wheels ship no flang either).

Order: the Windows minimal tree first (it is what a Windows wheel would
wrap), then a Windows wheel without compile support, then compiling from
the wheel once the userland choice is made.

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

- **Both zigs (F4, redefined 2026-10-04).** Was "one zig": upstream zig
  everywhere, or an opt-out upstreamed to the feedstock, retiring the
  `ZIG_LIB_DIR` mirror. The user chose to keep both conda-forge's zig
  and upstream zig (PyPI ziglang) working instead; an opt-out upstreamed
  to the feedstock would still let the mirror go one day (one Zig
  implementation since F4, libcxx_mirror.zig). conda-forge's zig is
  dynamically linked to conda's LLVM 21, so shipping it means shipping
  that. Done on linux-64 2026-10-05 (record under F4); macOS and win-64
  still to test. Still open from it: the upstream zig report on the
  MinGW atexit export (drafted in the F4 record, not filed) and
  `-lsynchronization` with upstream zig on Windows (Status section,
  What remains 8); the build-path strings in the shipped tree, What
  remains 7, are done (2026-10-05).
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
    pass with it. The archive-path `FLIBS` stays: linux-64 used
    conda-forge's flang-rt, which still ships the shared library (until
    2026-10-03, next items), and win-64 (build 4, no build 9) was always
    static only. No version script or export list is needed.
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
  - **linux-64 on flang-zig (2026-10-03).** linux-64 was the last
    platform on conda-forge's flang (`flang` + `flang-rt_linux-64`; 22.1.8
    in default/full/openblas/pkg, 23.1.1 in minimal), the one platform
    whose Fortran runtime was not static-only with hidden visibility and
    whose `use omp_lib` failed: conda-forge's llvm-openmp ships no
    `omp_lib.mod`, so configure captured `SHLIB_OPENMP_FFLAGS` empty. It
    now uses flang-pixi's flang-zig (`_2`) + flang-rt-zig (`_9`) + lld-zig
    (`_1`), LLVM 23.1.1, like the other four platforms (flang-pixi's note,
    2026-10-03, which also flagged the stale `FC_VER = flang 22.1.8` in
    the vendored config). What changed:
    - pixi.toml: Fortran is one entry in `[dependencies]` (`flang-zig`,
      `flang-rt-zig` build >= 9) and in `[feature.minimal.dependencies]`;
      win-64 overrides `flang-rt-zig` with build >= 4 (it has no build 9).
      The other per-target Fortran lines (all five platforms, the
      minimal feature's four) are gone.
      recipe.yaml: no `linux64` selector left; `flang-zig` +
      `flang-rt-zig` in the staging build, `flang-rt-zig` in host, both
      in r-zig-toolchain's run deps, on every platform. Build number
      stays 4: build 4 is not on the channel yet (linux-64 has `_2` and
      `_3`, the pre-split r-zig-slim), so the change ships with it.
    - pixi.lock (`pixi lock`, nothing else re-solved; only linux-64
      changed, in all six environments that carry Fortran): flang-zig,
      flang-rt-zig and lld-zig added; flang, flang-rt_linux-64 and
      conda-forge's LLVM 22 (23 in minimal) toolchain closure removed:
      clang, clangxx, clangdev, clang-format, clang-scan-deps,
      clang-tools, clang_impl/clangxx_impl, libclang, libclang-cpp,
      libclang13, compiler-rt (and _linux-64, libcompiler-rt), libllvm22
      (libllvm23 + libmlir23 in minimal), llvmdev, llvm-tools,
      binutils(_impl), libgcc-devel/libstdcxx-devel_linux-64, and
      ld_impl_linux-64 in minimal. No version of any other package moved
      (llvm-openmp stays 22.1.8 in default, 23.1.2 in minimal; zig's
      libllvm21 and sysroot_linux-64 2.28 stay). Every universe URL in
      the lock answers 200.
    - The vendored linux-x86_64 configs, re-captured (configure-only.sh
      + gen-subst.sh with flang-zig, all three variants). Only Fortran
      lines changed: `FC_VER` "flang version 22.1.8 (https://github.com/
      conda-forge/clangdev-feedstock ...)" (minimal: 23.1.1 with the
      same suffix) to "flang version 23.1.1" in config.h and subst.txt,
      all three; in slim and full `SHLIB_OPENMP_FFLAGS`,
      `R_OPENMP_FFLAGS` and `OPENMP_FCFLAGS` "" to "-fopenmp" (configure's
      `use omp_lib` probe now passes) and config.h's `SUPPORT_OPENMP`
      now defined, which configure sets when C, C++ and Fortran all
      support OpenMP; R's C code no longer reads it (it left Rconfig.h in
      R 4.x), so R's own build is unchanged. minimal keeps its empty
      OpenMP flags (`--disable-openmp`). Rconfig.h and GENERATED_FROM
      are unchanged. The three files now match linux-arm64's except for
      the CPU, vendor and triple lines, `-fpic` vs `-fPIC`, and full's
      host-tool `INTLBISON`, as before.
    - Dead special cases: none in code. Comments that described the
      exception were updated (pixi.toml, recipe.yaml, build.zig,
      scripts/env.sh, zigbuild/tools/configure-only.sh, rzig's
      flang_rt.zig and fortran.zig, consolidation/PLAN.md); the
      archive-path `FLIBS` and `preferred_link_mode = .static` stay, as
      the rule for any flang-rt that ships a shared runtime beside the
      archive. build.zig's gfortran branch is now no platform's
      (FortranCompiler, findGfortranLibDir, the gfortran cases of
      linkFortranRt and the Windows Makeconf): removable, not removed.
    - Measured on linux-64, the old tree (main checkout, conda-forge
      flang 22.1.8) against the new one, the same two probes run on
      each: a Fortran `R CMD SHLIB` doing formatted I/O exported 1,118
      symbols, 1,099 of them the runtime's (`_Fortran*`,
      `_ZN7Fortran*`, `CFI_*`), and now 4, none the runtime's; R's own
      libraries (libR, libRblas, libRlapack, lapack.so, stats.so)
      exported none before or after, and no binary of either tree
      needs a shared flang runtime. A package whose Fortran does `use
      omp_lib` (`omp_get_max_threads`, a parallel reduction, formatted
      I/O) failed to compile before ("Source file 'omp_lib.mod' was not
      found"); now, under `env -i` with the tree and the env's flang,
      `R CMD INSTALL` (zig-fc compile with `$(SHLIB_OPENMP_FFLAGS)`,
      zig-cc link) and `R CMD SHLIB` with `USE_FC_TO_LINK` (zig-fc link)
      both build it with no RUNPATH, NEEDED libomp.so from the tree, and
      it runs 3 threads with OMP_NUM_THREADS=3. `R_compiled_by()` says
      "flang version 23.1.1". flang-zig's own driver, for comparison,
      finds the static runtime through flang.cfg but records the env's
      lib as RUNPATH: zig-fc's zig link stays the reason packages load
      without an rpath.
    - Tested 2026-10-03 on linux-64, cold zig cache (a new worktree):
      rzig-test (41 unit tests, parity 0 failed); default: build (the
      log says `Fortran compiler = flang`, and libR carries "flang
      version 23.1.1"), verify-tree, smoke, contract (Rcpp, data.table,
      minqa, quadprog, pak, ps: OK; quadprog exports 6 symbols and minqa
      187, none the runtime's), check (lapack.R matches its .Rout.save;
      one NOTE, tools-Ex, grid's vignette metadata, not Fortran),
      hermetic, verify-package; minimal: build, verify-tree, hermetic,
      verify-package, then the wheel and wheel-test; full: build,
      verify-tree, smoke (and the `use omp_lib` package above);
      openblas: build, smoke; the conda packages (`pixi run -e pkg
      conda-package`, a fresh solve that took flang-zig `_2`,
      flang-rt-zig `_9`, lld-zig `_1` from universe): both outputs'
      tests passed; r-zig-slim `_4` depends on no Fortran package at
      all, r-zig-toolchain `_4` on `flang-zig` and `flang-rt-zig`.
    - Not tested here: linux-aarch64, macOS and Windows (their
      dependencies did not change; the manifest restructuring keeps
      their locked packages identical, checked in the lock diff); CI
      runs all of them.
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
