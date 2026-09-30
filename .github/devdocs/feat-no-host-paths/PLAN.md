# feat-no-host-paths — no build-machine paths, and a base R that installs without a toolchain

**Status (2026-09-29): phase A implemented on unix** (A1 partly, A2–A5,
A6 without Windows; see "Progress" below), plus the interim libcurl CA
fix and the compiled-package rpath fix. Phases T, B, C, D, S and P are
design only. R source references are to R 4.6.1 (`build/R-4.6.1/`).

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

## Tiers

| Tier | Covers | Needs today (unix) | Target | Ships in |
|---|---|---|---|---|
| 0 Run | `R`, `Rscript`, `library()` | bash (`#!/bin/bash` in `bin/R` and in the Rscript emulator), `sed`, `dirname`, `readlink`, `expr`; at every start `/bin/sh` running `which` and `uname`, at exit `/bin/sh` running `rm` | `/bin/sh` and its builtins for the launcher script; after phase C, nothing | base |
| 1 Install without compiling | R-only source packages, binary packages, `remove.packages()` | `/bin/sh`, `mv`, `cp`, external `tar`; `make` and `cat` when `Ncpus > 1` | binary packages: nothing (in-process, see "Binary packages"); R-only source packages: nothing after phase S (`/bin/sh` on unix until then) | base |
| 2 Compile | `src/`, `configure`, `R CMD SHLIB`, `R CMD config` | zig, flang, make, `sh` plus a POSIX userland, strip/otool/patchelf | unchanged | toolchain package |
| 3 Develop | `R CMD build`/`check`, `Rd2pdf`, vignettes | TeX, qpdf, gs, pandoc, tidy, nm, zip, diff, patch | found when used, all optional | neither |

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
- **Which zig each toolchain uses (decided 2026-09-29):**
  - conda: conda-forge's `zig`. Its patch links conda's shared libc++ on
    macOS, which is right inside conda: a package that links other conda
    C++ libraries must share one libc++ with them.
  - wheel: PyPI `ziglang` (upstream zig, static libc++), as today.
    `wheel-test.sh` fails if the C++ test package depends on a shared
    libc++ or libstdc++.
  - standalone tree: the official ziglang.org release (the same upstream
    build as PyPI `ziglang`), checksum-pinned, in the standalone
    toolchain download.
  - r-zig-packages binaries: built with upstream zig for the standalone
    tree and the wheel, and with conda-forge's zig for conda.
  - Optional, upstream: an opt-out in the conda-forge feedstock for its
    shared-libc++ lookup, so conda users could choose static too.
- **Base keeps what compiling needs from R itself:** headers,
  `etc/Makeconf`, libR. Those are part of R, not of the toolchain.
- **Preflight** (small `install.R` patch): before running `configure`
  or make, if the package needs compilation and the compiler Makeconf
  names doesn't exist, stop with one message naming the package to
  install for this distribution.

## Phases

A, then T, are sequential. B, C, D, S and P can run in parallel with them.

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
  `config_opts`/`R_CONFIG_ARGS`), to be confirmed by gen-config. Still
  recorded from the capture machine, but no longer shipped (stage.sh
  overrides them in Renviron): `PAGER`, `R_BROWSER`, `R_PDFVIEWER`,
  `R_PRINTCMD`, `TEXI2DVI`. Not pinned yet: `LD`, `TEXI2ANY`,
  `INSTALL_INFO`, `oldincludedir` (build tree only). Pinning the tool
  variables in configure itself is riskier than it looks: `R_UNZIPCMD`
  also unpacks zoneinfo at install, and `R_PRINTCMD` reaches config.h.
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
  verify-package on the unix default and minimal legs). Windows is not
  covered yet.
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

**B — one Zig multi-call binary** that dispatches on its own name, like
busybox:
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
  macOS 26 (untested on macOS 13, minimal's deployment target).
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

## Open

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
    `-fno-each-lib-rpath` ("Unknown Clang option"), and pinning
    `-target <arch>-macos.13.0` loses the SDK (no `-framework`; `-F`
    panics zig) and makes conda-forge zig build libc++ from source, which
    fails. The shims now resolve `-l<name>` against the `-L` directories
    themselves (ld64's order) and drop the `-L` flags. Packages with no
    rpath load: libR, libc++ and libomp are already in the process and
    match by install name (tested with C and C++ on omicron).
  - R's own macOS binaries also carried build-machine rpaths (the conda
    lib dir, absolute, and `build/zig-cache/...`, relative): stage.sh
    only added its `@loader_path` pair. It now deletes every other
    LC_RPATH, as patchelf `--set-rpath` does on linux.
  - verify-bundle.sh fails on any RUNPATH/LC_RPATH not relative to the
    file, and compiles a C++ SHLIB with the extracted tree that must have
    no rpath and load.
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
- **macOS deployment target of compiled packages.** With the native
  target, zig stamps `minos` with the build host's version (26.4.1 on
  omicron), and zig 0.16 ignores `MACOSX_DEPLOYMENT_TARGET`. R minimal
  targets 13.0. r-zig-packages binaries built on a newer runner would
  claim that runner's macOS. Options: build them on the oldest runner,
  patch `minos` after linking (vtool), or find a way to pass an OS
  version to zig without losing the native SDK.
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
