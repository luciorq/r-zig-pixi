# r-zig-pixi

R, built as a conda package with the [Zig](https://ziglang.org) toolchain
(`zig cc`/`zig c++` in place of a system compiler) and driven end-to-end
through [pixi](https://pixi.sh). One dependency graph — pixi resolves
everything from conda-forge, Zig included, and prefix.dev's `universe`
channel (LLVM flang and libomp, [flang-pixi](https://github.com/luciorq/flang-pixi)'s
zig-built LLVM 23.1.5) — instead of a system compiler toolchain plus a
separate build system.

## Goals

R and its packages built with one toolchain, Zig, on every platform,
installable without a system compiler or Rtools (on macOS, building R
itself and some package links use the macOS SDK when present), and packages with
C++, Fortran or system libraries building from source. The goals and
the working principles (simplicity first, no host leakage, a layered
toolchain, both zigs, evidence over job status, careful releases) are
in [.github/devdocs/CONVENTIONS.md](.github/devdocs/CONVENTIONS.md#goals-and-principles).

## Use cases

### Install R from the built conda packages

The packages target `linux-64`, `linux-aarch64`, `osx-64`, `osx-arm64`,
`win-64` and `win-arm64` (Windows on ARM), and are published to the
`universe` channel on prefix.dev.
The channel is public: adding it is all it takes, with no login.
A release is published by hand, not on every merge: universe's newest
is build 13 (R 4.6.2, all six platforms, published 2026-11-26); build
14 is next. `win-arm64` is published since build
11: R and the groups go through the same CI steps as `win-64`, on
GitHub's `windows-11-arm` runner, where the build tools (MSYS2's x64
binaries) run under x64 emulation.

```bash
pixi init my-r-project
cd my-r-project
pixi workspace channel add --prepend https://prefix.dev/universe
pixi add r-zig-slim
pixi run Rscript -e 'R.version.string'
```

`--prepend` matters: universe must come before conda-forge. r-zig-slim
and r-zig-compilers depend on `llvm-openmp`'s `zig_*` build,
flang-pixi's libomp (LLVM 23.1.5), which only universe has; conda-forge
has an `llvm-openmp` too. With pixi's default (strict) channel priority
the first channel that has a package name is the only one it takes that
package from, so with conda-forge first the solve finds no `zig_*` build
and fails. With conda or mamba, list universe first the same way
(`-c https://prefix.dev/universe -c conda-forge`). r-zig uses this
libomp on every platform: it is the one R is built and tested with, and
conda-forge's win-arm64 `libomp.dll` breaks parallel regions with more
than six shared variables (data.table crashed).

`r-zig-slim` is R alone: it runs R and installs packages that need no
compiling (R-only source packages and binary packages). It is the slim
variant on every OS: no Tcl/Tk, JPEG, TIFF or translations (Windows too
since build 11; see Variants). It carries rzig, the compiler front R's
Makeconf names; the compilers, the build tools and cmake are three
groups, each a package that pins the exact `r-zig-slim` build. To
compile packages, add r-zig-toolchain (r-zig-compilers,
r-zig-build-tools and r-zig-extras):

```bash
pixi add r-zig-toolchain
```

- `r-zig-compilers` (zig 0.17, LLVM flang 23.1.5, OpenMP; on linux also
  gcc's libstdc++ headers, from libstdcxx-devel_linux-*) alone installs
  packages that have no configure script and whose Makevars only sets
  variables. It also compiles such code at run time (`R CMD SHLIB`:
  Rcpp's `sourceCpp()`, inline, TMB, knitr's engines) with no make: R
  builds both with `rzig build`. Once pkgbuild or pak is installed,
  their compiler check passes too.
- `r-zig-build-tools` (make; on Windows also sh, the MSYS2 tools,
  pkg-config and, build 14 on, zip) is for configure scripts, Makevars
  rules and Objective-C. Installing pkgbuild, pak, devtools or the
  packages cpp11's `cpp_source()` requires from source needs it once:
  processx has Makevars rules, and ps and pak have configure scripts.
- `r-zig-extras` (cmake, conda-forge's) is for packages that build a
  bundled library with CMake (nloptr, for example).
- `r-zig-native-tools` (build 14 on, Windows only, an opt-in add-on):
  native build tools in
  place of MSYS2's, all built from source with zig: busybox-w32 (sh,
  sed, awk, grep, coreutils), GNU make, Info-ZIP zip and pkgconf.
  Install it instead of `r-zig-build-tools` and set
  `R_ZIG_NATIVE_TOOLS=1`; R CMD INSTALL, R CMD SHLIB and R sessions then
  put them first on `PATH`, and CMake's default generator becomes Unix
  Makefiles. r-zig patches busybox's sh to read MSYS2-style `/c/...`
  paths and convert them for native programs as MSYS2 does (a bare `/c`
  stays a switch, as in `cmd /c`), for packages that ask for CMake's
  MSYS Makefiles themselves (RcppParallel's TBB build). This make is
  built with `-DBATCH_MODE_ONLY_SHELL` (`zigbuild/make/build.zig`): it
  runs each recipe from a temporary sh file, so a package DLL link with
  several hundred objects (igraph) stays under Windows' command-line
  limit (`.github/devdocs/b14-l4/PLAN.md`, F39, U6).

r-zig-toolchain has the three groups from the start (not
r-zig-native-tools).

`R CMD config` needs no group, on every OS: R CMD runs rzig, which reads
Makeconf and the site's and user's Makevars itself, with no make and no
sh (pkgbuild, pak and configure scripts call it first; rstan after each
`stan_model()` compile). A Makevars construct only make can evaluate
(`$(shell)` in a `:=`, `define`, `!=` and the like) makes it exit 2,
naming the construct, file and line.

R's 15 recommended packages (MASS, lattice, Matrix, nlme, survival,
mgcv, boot, cluster, codetools, foreign, KernSmooth, rpart, class, nnet,
spatial) are not in r-zig-slim. They are the package
`r-zig-recommended`, built with the same R and compilers and pinned to
the exact `r-zig-slim` build; nothing depends on it, r-zig-toolchain
included. It needs no group to use:

```bash
pixi add r-zig-recommended
```

R's tcltk package is the add-on `r-zig-tcltk` (build 13 on; every
platform but win-arm64, where conda-forge has no Tk 8.6), pinned the
same way and bringing conda-forge's `tk`:

```bash
pixi add r-zig-tcltk
```

Without it `capabilities("tcltk")` is still `TRUE` and `library(tcltk)`
says the package is not installed.

Without a group, an install that needs it stops with a message naming the
package to add; without cmake it is only a note, since whether a
package's build runs cmake is not known before it runs (its configure
then decides). In an environment used without activation (an IDE
pointed at `<env>/bin/R`), the build tools are not on `PATH`: activate
the environment (`pixi shell`, `conda activate`) or start R with
`pixi run`.

- If pak or pkgbuild says it could not find the tools, run
  `pkgbuild::check_build_tools(debug = TRUE)`: rzig's text names what to
  install. A pak session that checked before r-zig-compilers was
  installed keeps its answer: restart R.
- pak checks for a compiler before every source package, R-only ones
  too, so with `r-zig-slim` alone it installs no source package:
  `install.packages()` does.
- On Windows, Rtools is not needed: r-zig's build tools take its place.
  R puts the build tools first on `PATH`, in R and under `R CMD` (in a
  conda environment its own MSYS2 tools, `Library\usr\bin`, whatever
  `PATH` holds); set `R_CUSTOM_TOOLS_PATH` to use others. pkgbuild's
  "Rtools is required" warning, printed by `with_build_tools()` callers
  such as devtools, can be ignored. With the tools first, R code's `system()` and `Sys.which()`
  still find `find`, `sort`, `expand`, `hostname`, `timeout`, `whoami`,
  `tar` and `bash` (WSL's) in System32, as with R's own installer and
  Rtools; sh, make and configure scripts get the build tools'.
- On Windows, R's DLLs come from the environment's `Library\bin`.
  Without activation, start R as `<env>\Library\lib\R\bin\R.exe` or
  `Rscript.exe`, which put `Library\bin` on `PATH` first; `bin\x64\`'s
  programs (`R.exe`, `Rterm.exe`, `Rscript.exe`) and `Library\bin\R.bat`
  need activation or `Library\bin` on `PATH`.
- On Windows, a package DLL links Winsock (`ws2_32`) by default, after
  the package's own libraries: a package that calls `htons` without
  naming `-lws2_32` (ragg with a conda environment's libraries) links
  (whether Rtools' libraries bring it for CRAN is not verified). A DLL
  imports from it only what it calls.
- On Windows, `pkg-config` and `pkgconf` are pkgconf 3.0.11, built from
  source with zig into `R_HOME/bin/toolchain/usr/bin` (the build tools,
  on both channels). Under `R CMD`, R's `etc\Rcmd_environ` puts
  libs-zig-pixi's `.pc` files first on `PKG_CONFIG_PATH`, always
  (`Library\zig-libs\<triple>\lib\pkgconfig` of R's environment, when
  `zig-*` packages are installed there); after them comes the
  `PKG_CONFIG_PATH` the environment set, else R's own environment's
  `Library\lib\pkgconfig` and `Library\share\pkgconfig`, so a conda or
  pixi environment's libraries are found with or without activation.
  `PKG_CONFIG_LIBDIR`, unless set, is zig-libs' directory and R's
  environment's two, which a package that sets `PKG_CONFIG_PATH` itself
  still finds (s2's `Makevars.win`). For
  another libraries environment set
  `PKG_CONFIG_PATH=<env>\Library\lib\pkgconfig`. pkgconf
  also reads the registry key `Software\pkgconfig\PKG_CONFIG_PATH`, and
  drops from its output the `-I` directories named in `INCLUDE`,
  `CPATH`, `C_INCLUDE_PATH` and `CPLUS_INCLUDE_PATH` and the `-L` ones in
  `LIBRARY_PATH`. Neither R's install path nor that environment's path
  may contain spaces (pkg-config escapes them, and some packages'
  scripts then split), and keep R's install path short (past about 260
  characters R and make stop finding files).
- From Git Bash on Windows (`MSYSTEM=MINGW64`), configure scripts see
  the build system `x86_64-pc-mingw64`, not `x86_64-pc-msys`; packages
  build either way. Running the toolchain's make directly from Git for
  Windows' bash is not supported on Windows on ARM (it segfaults); run
  builds from R (`R CMD INSTALL`, `install.packages()`).
- A TMB installed by an earlier r-zig build (universe's build 8 or before)
  keeps make, as it keeps a copy of R's own SHLIB code: reinstall it.
  TMB's `precompile()` speeds up only the recompiles of one model name:
  each new name compiles the precompiled library again (about 45 s on
  linux-64) and keeps one more object (about 4 MB) in zig's cache. Where
  the build tools are installed, `R_ZIG_PKG_BUILDER=make` restores make's
  reuse. TMB 1.9.25's default `precompile()` does not compile, with GCC as
  with zig; `precompile(all = FALSE)` does.

`R_ZIG_PKG_BUILDER` chooses who builds a package's compiled code:
`auto` (unset) builds with `rzig build` where the call qualifies and
with make otherwise; `make` sends every `R CMD INSTALL` and `R CMD
SHLIB` to make (the build tools then are needed); `zig` never runs
make, and a package or call that needs it (a `src/Makefile`, a
Makevars rule) stops with the reason. `R_ZIG_JOBS=<n>` sets `rzig
build`'s parallel jobs; unset, it takes `MAKEFLAGS`' `-j<n>`. Details:
`.github/devdocs/feat-zig-pkg-build/PLAN.md`,
`.github/devdocs/feat-shlib-rzig-build/PLAN.md`.

Before compiling a package, `R CMD INSTALL` asks rzig whether the
groups it needs are there and whether the zig found is R's zig
version (the preflight, patch 0009); `rzig build` makes the same zig
check for `R CMD SHLIB`. `R_ZIG_NO_PREFLIGHT=1` skips the preflight
and the version comparison, as rzig's message says when the zig it
finds is another version; a user Makevars (its own compiler) skips the
preflight too.

r-zig's on/off variables (`R_ZIG_NO_PREFLIGHT`, `R_ZIG_SYSTEM_LIBS`,
`R_ZIG_NATIVE_TOOLS`, `RZIG_TRACE`, `RZIG_KEEP_ROOT`, ...) share one
rule from build 14 on: on when set to `1`, `true` or `yes` (any case);
off when unset, empty, `0`, `false` or `no`; any other value is off,
with a warning naming the variable. Before build 14 rzig took any value
but `0` as on, and the preflight any value but an empty one.

`R_ZIG_EXTRA_ENV=<env root>` names one more environment to compile
against, after R's own: rzig adds its `include/` and `lib/`
(`Library\include` and `Library\lib` on Windows) and, for a conda
environment on unix, an rpath into its `lib/`. Use an absolute path.
It is for a standalone R compiling against an environment of
libraries; pixi.toml sets it to the pixi env for this repository's dev
and test runs.

`R_ZIG_TOOLCHAIN_ENV=<env root>` (build 13 on) names an environment
that holds the toolchain when it is not R's own: rzig takes zig and
flang from its `bin/` (`Library\bin` on Windows) before the compilers
group's, and on linux libstdc++'s headers from its `lib/gcc`. It gives
no headers or libraries to packages (that is `R_ZIG_EXTRA_ENV`); make
and cmake stay `PATH`'s, so put that environment's `bin/` on `PATH` for
packages that need them.

`R_ZIG_SYSTEM_LIBS=1` (build 13 on, linux only; ignored elsewhere)
compiles and links against the distribution's libraries in `/usr`: the
host's include directories come after R's environment ones
(`-idirafter`), and its library directories are the last `-L`, so a
package such as magick or terra builds against `apt`'s ImageMagick or
GDAL (`libmagick++-dev`, `libgdal-dev`).

`R_ZIG_FALLBACK_SOFT` (builds 12 and 13, Windows on ARM: an extracted
Rtools45 aarch64 library tree after every environment) is gone from
build 14: libs-zig-pixi's `zig-*` packages serve those libraries on both
Windows platforms, `regex.h` and `-lregex` (Rhtslib, so also Rsamtools)
included: zig-libgnurx, and protobuf with its `protoc` (protolite,
RProtoBuf): zig-protobuf (both from libs-zig-pixi slice 3, 2026-11-27).
On Windows rzig drops an `-l` of Rtools45's static libcurl closure that
no `-L` directory has and zig does not provide (`-lidn2 -lunistring
-lssh2 -lgcrypt -lgpg-error -lnghttp2 -lpsl`). zig-libcurl build 2
links libidn2, libunistring, libssh2, nghttp2 and libpsl itself, so with
it only `-lgcrypt -lgpg-error` are dropped (its libssh2 uses OpenSSL),
and a package that copies Rtools' link line, such as Rhtslib, still
links. `RZIG_TRACE=1` prints each one as
`lib -l<name> (dropped: Rtools curl closure)`.

### Install binary packages (linux)

Experimental: the repository's layout, its key and the way binaries
carry their libraries are to be reviewed again in a later build
(`.github/devdocs/b14-l5/PLAN.md`, decision U3).

On linux-64 and linux-aarch64, a curated set of CRAN packages (Rcpp,
data.table, xml2, cli, vctrs, ... and their dependencies) is built by
r-zig into a CRAN-like binary repository, served from this repository's
GitHub Releases (from build 14; not published yet). With it first in
`repos`, `install.packages()` installs binaries with no compiler, then
falls back to CRAN's sources:

```r
options(repos = c(
  RZIG = sprintf("https://github.com/luciorq/r-zig-pixi/releases/download/repo/linux-%s-rzig1/%s",
                 R.version$arch, sub("^([0-9]+\\.[0-9]+).*", "\\1", getRversion())),
  CRAN = "https://cloud.r-project.org"))
```

A binary needs nothing outside R: the libraries it links that R does
not load itself (xml2's libxml2 and ICU, data.table's libomp) are in the
package's `libs/`, found through its `$ORIGIN` rpath, with their
licences in `<pkg>/rzig-bundled/`. The same binaries load in R from a
conda env, in the r-zig wheel's R in a plain venv, and in R embedded in
a Python from outside any conda env (ctypes, as rpy2 does), with no
environment variable. Where a library of the same name is already
loaded (an R with OpenMP has libomp), that one is used. The wheel's R
creates its per-user library (`R_LIBS_USER`: `$XDG_DATA_HOME`, else
`~/.local/share`, then `R/<platform>-zig/<x.y>`, such as
`R/linux-aarch64-zig/4.6`) at its first start, so `install.packages()`
installs there and later sessions find the packages. Where rpy2 would
find no other R (no `R_HOME`, no other `R` on `PATH`), it installs and
finds the wheel's R with no setup, from a venv that is not activated
too: `pip install r-zig`, then `pip install rpy2` (the wheel's
`r_zig.pth` makes rpy2's source build on linux use its ABI mode, and
points rpy2 at the wheel's R; with another R on `PATH` rpy2 uses that R
as it does without r-zig; `repo/README.md`).
`repo/README.md` has the details, the layout and its ABI key, and how
`.github/workflows/repo.yaml` builds and publishes it (behind a gate;
nothing is published until it runs).

`R_ZIG_ENV_RPATH` (build 14 on, experimental) sets what rpath rzig
gives links in place of the conda env's: `origin` gives only `$ORIGIN`
(the repository's builds), `0` none. Unset, rzig keeps the rpath into
R's conda env (or `R_ZIG_EXTRA_ENV`'s), which serves local installs and
R embedded in a program from outside the env. Linux only tested.

### Build the conda packages yourself

```bash
pixi run -e pkg conda-package
pixi run -e pkg conda-consume
```

`conda-package` produces the packages,
`dist/conda/<platform>/r-zig-slim-*.conda`, `r-zig-compilers-*.conda`,
`r-zig-build-tools-*.conda`, `r-zig-extras-*.conda`,
`r-zig-toolchain-*.conda`, `r-zig-recommended-*.conda`,
`r-zig-tcltk-*.conda` (not on win-arm64) and, on Windows,
`r-zig-native-tools-*.conda`, via
`rattler-build`, using this repo's own recipe (`recipe/recipe.yaml`), and
tests each one in a fresh environment of its own. Useful for testing a
change to the build before publishing, or for producing a package for a
platform not published upstream. Each run empties `dist/conda` first, so
the previous run's packages do not survive it. `conda-consume` then
installs them as a user does: a fresh pixi workspace from `dist/conda`,
with `r-zig-slim` alone, with each group, with `r-zig-toolchain` and
with `r-zig-recommended`, with `r-zig-tcltk` (not on win-arm64) and, on
Windows, with `r-zig-compilers` and `r-zig-native-tools` (no MSYS2
tools), each in an environment of its own, where it
runs the recipe's tests through pixi's activation. CI runs
both on every `conda-package` leg, before the publish.

### Publish to your own channel

```bash
pixi run -e pkg conda-publish linux-64   # the subdir conda-package built
```

Uploads the just-built packages for the subdir it is given
(`dist/conda/<subdir>/*.conda`) to the `universe` channel via
`rattler-build upload prefix --skip-existing`. It takes no glob over
`dist/conda/`, so it never uploads another platform's packages. It is what CI's `conda-publish` job runs, once per subdir (see
CI), not run by hand for `universe`; for a channel of your own, change
`--channel` in that task or run `rattler-build upload` yourself.

### Run R from source without packaging

For iterating on the build itself rather than consuming a package:

```bash
pixi run build         # zig build, no autoconf/make/gnuwin32 (fetches R's sha256-pinned source first: zig build fetch)
pixi run verify-tree   # static checks of the installed tree (Makeconf, rpaths, floors)
pixi run smoke         # quick sanity check
pixi run check         # R's own regression suite
pixi run toolchain     # the toolchain tree: the groups' files (zig, flang, OpenMP headers, make, cmake; Windows sh, make, pkg-config)
pixi run contract      # CRAN packages compiled with the tree and the groups (Rcpp, data.table, minqa)
```

`build` installs `dist/<flavor>/R-<ver>-zig/`, the base that ships: R
and its libraries, with only rzig, the compiler front Makeconf names, and
its link object (linux `dso_fini.o`, win-64 `cfguard.o`, win-arm64
`clear_cache.o`) in
`R_HOME/bin/toolchain`, and on linux `libstdcxx-shim/`, rzig's two
shim headers for libstdc++ (`.github/devdocs/CXX-STDLIB.md`). `toolchain` copies the toolchain groups' files
from the environment into `dist/toolchain/R-<ver>-zig/`, and upstream
zig from PyPI's `ziglang` wheel into its `zig/`, each directory with its
`SOURCES` (package, version, sha256, where its source is) and
`LICENSES/`; one toolchain tree serves every flavor of the platform.
Its `cmake/` comes from Kitware's cmake release archive for the
platform, which the toolchain build fetches itself (network; zig's
package cache keeps it).
For that `zig/`, `toolchain` downloads the wheel once per platform (about
100 MB, `pixi run fetch-zig`; kept unpacked in `build/zig-upstream/`),
even for the tasks that use only the compile tree, which leaves `zig/`
and `flang/` out; an offline machine needs that directory.
`contract` compiles packages in a copy of the installed tree with the
groups added, `build/compile-tree/<flavor>/R-<ver>-zig/`, as a user who
extracted all four archives has it (see Standalone archives). The
archives and their checks:

```bash
pixi run package-toolchain   # the three group archives (runs toolchain first)
pixi run verify-toolchain    # static checks of the toolchain tree (records, copies, closures)
pixi run verify-package      # the base archive, then the four scenarios with the group archives
```

R's recommended packages have a tree of their own,
`dist/recommended/<flavor>/R-<ver>-zig/`, never the R tree: `build`
leaves them out, and `recommended` installs them from the tarballs R's
source carries, in the order of R's own makefile, with the compile
tree's R (Matrix's makefile rules need the build-tools group's make).
The step is `zigbuild/recommended/build.zig`:

```bash
pixi run recommended           # the 15 packages (runs compile-tree first; `-- -Djobs=6` per package)
pixi run recommended-test      # that build's unit tests
pixi run verify-recommended    # static checks of the tree, then the packages' tests with the base's R
pixi run package-recommended   # their archive (see Standalone archives)
```

### Variants

Three variants are available as pixi environments, on every OS:
`default` (slim), `full` and `minimal`. One table in build.zig
(`variantFeatures`) defines them, and the build stops when a vendored
config disagrees with it:

| Feature | slim (`default`) | full | minimal |
|---|---|---|---|
| cairo devices, `png()` | yes | yes | no |
| `jpeg()`, `tiff()` | no | yes | no |
| tcltk | no (conda: the `r-zig-tcltk` add-on) | yes | no |
| translations (NLS) | no | yes | no |
| ICU, libdeflate | yes | yes | no |
| OpenMP for packages | yes | yes | no |
| OpenMP inside R | yes | yes | no |
| readline | no | unix only | no |

readline is unix only: Windows R has its own console line editing.
Memory profiling (`Rprofmem()`) is on in every Windows variant and off
on unix, as in CRAN's R.
OpenMP inside R on Windows differs from CRAN's R, which leaves it off
there; r-zig links LLVM's libomp on every OS. On Windows, `jpeg()`,
`tiff()` (and `png()` on minimal) give R's usual "no support" warning
in a variant without that format. The record is
`.github/devdocs/feat-win-variants/PLAN.md`. On Windows, R's cairo
devices (`svg()`, `cairo_pdf()`, `cairo_ps()`, `type = "cairo"`) use a
cairo that R's build compiles from source and links into winCairo.dll,
the same on x86_64 and ARM; its licence texts are in
`R_HOME/share/licenses/cairo`. `minimal` is the variant the Python
wheel wraps (every OS; Windows since build 13). minimal has no OpenMP: a
Fortran `use omp_lib` compiles but does not link.

### Build with upstream zig

The environment's zig is conda-forge's build. R builds just as well with
upstream zig (the [ziglang.org](https://ziglang.org/download/) release,
which the PyPI [`ziglang`](https://pypi.org/project/ziglang/) package
is), and the project keeps both working; upstream zig is the reference.
`pixi run fetch-zig` downloads PyPI's `ziglang` 0.17.1 wheel for this
platform once (checksum-pinned; a wheel is a zip, so no Python is
involved), unpacks it under `build/zig-upstream/` and prints its zig's
path. The tasks that run zig, `build`, `check`, `rzig-test`, the
toolchain tree's `toolchain` and `toolchain-test`, and the ones that
compile packages with the built tree (`contract`, `verify-package`,
`recommended`), take it from `ZIG_BIN`; the other checks look at the
trees it built:

```bash
export ZIG_BIN="$(pixi run fetch-zig)"   # PowerShell: $env:ZIG_BIN = pixi run fetch-zig
pixi run build && pixi run package-toolchain && pixi run verify-tree && pixi run smoke && pixi run contract && pixi run verify-package
```

The build prints the zig it uses (`r-zig: zig = ...`); unset `ZIG_BIN`
to go back to the environment's. Each zig keeps its own cache in
`build/zig-cache/`, so switching between them never mixes their objects.
The conda package (`pixi run -e pkg conda-package`) always builds with
its recipe's zig, conda-forge's: rattler-build gives the recipe a clean
environment, without `ZIG_BIN`. `wheel-test` always compiles with the
`ziglang` it installs into its venv, which is upstream zig already.

### Build R as Python wheels

```bash
pixi run -e minimal build              # the installed tree, libraries vendored
pixi run -e minimal verify-tree        # its static checks
pixi run -e minimal package-toolchain  # the toolchain tree and its three group archives
pixi run -e minimal verify-package     # archive the tree, check the archives relocated
pixi run -e wheel wheel                # -> dist/wheel/{r_zig,r_zig_compilers,r_zig_build_tools,r_zig_toolchain}-4.6.2-*.whl
pixi run -e wheel wheel-test           # pip-install them into fresh venvs, a group at a time, and use them
```

`wheel` takes GNU make for `r-zig-build-tools` from the toolchain tree,
so it needs `pixi run -e minimal toolchain` first (`package-toolchain`
runs it, and `verify-package` needs the group archives it makes).

The four wheels split as the conda packages do, for Linux, macOS and
Windows (win_amd64 and win_arm64 since build 13; there `wheel-test` runs
`scripts/wheel-test-windows.py`), less the extras group and the recommended packages,
which have no wheel yet. `r-zig` (import name `r_zig`) is the whole
relocatable `minimal` tree, rzig included, plus console scripts
`R`/`Rscript` and `r_zig.r_home()` for embedders such as rpy2; it
installs packages that need no compiling. To compile packages, add
r-zig-toolchain (r-zig-compilers and r-zig-build-tools). r-zig-compilers
brings the PyPI [`ziglang`](https://pypi.org/project/ziglang/) package
as the C/C++ compiler, so no system compiler is needed; alone, it
installs packages that have no configure script and whose Makevars only
sets variables, and compiles such code at run time (`R CMD SHLIB`:
Rcpp's `sourceCpp()`, inline, TMB) with no make. r-zig-build-tools
brings GNU make, for the rest: configure scripts, Makevars rules,
Objective-C, and installing pkgbuild, pak or devtools
from source once. There is no r-zig-extras wheel yet: `pip install
cmake` gives PyPI's cmake. None of the four is on PyPI yet: install them from
`dist/wheel`, ziglang first, so that pip needs no index for the rest:

```bash
pip install 'ziglang>=0.17.1,<0.17.2'
pip install --no-index --find-links dist/wheel r-zig-toolchain
```

ziglang is an upstream zig build. On macOS it links its own libc++
statically, so compiled C++ packages need no C++ runtime (with
conda-forge's zig, which would link conda's shared libc++, rzig keeps
it static). On linux C++ uses gcc's libstdc++: the headers come with
r-zig-compilers, and packages need R's lib/libstdc++.so.6, which libR
loads (`.github/devdocs/CXX-STDLIB.md`). On linux, r-zig with ziglang
alone compiles C but not C++. Linux
wheels are `manylinux2014` (glibc 2.17). PyPI has no Fortran compiler,
and the wheels have no OpenMP: packages with Fortran sources need LLVM
`flang` on PATH, and R's FC, rzig's `zig-fc`, stops with a message when
there is none. pip leaves ziglang installed when the groups are
uninstalled, and rzig still finds it; uninstall ziglang too for R alone.
Details: `.github/devdocs/feat-wheel-minimal/PLAN.md`.

### Standalone archives

R also comes as plain archives that need nothing installed first: no
conda, pixi or Python. Five kinds, `.tar.gz` (Windows `.zip`) but the
compilers group, `.tar.xz` on every platform, each with a `.sha256`
beside it:

- **The base**, one per flavor and platform:
  `R-<ver>-<flavor>-<platform>.tar.gz`, for example
  `R-4.6.2-slim-linux-64.tar.gz`. R alone, with its libraries: it runs R,
  installs packages that need no compiling and answers `R CMD config`.
  Its
  `R_HOME/bin/toolchain` holds only rzig, the compiler front R's
  Makeconf names, and the object rzig adds to links (linux
  `dso_fini.o`, win-64 `cfguard.o`, win-arm64 `clear_cache.o`), plus on
  linux `libstdcxx-shim/` (two headers libstdc++ needs with zig). Each
  flavor has the same features
  on every OS, except where the Variants table says otherwise
  (readline, memory profiling).
- **The compilers group**, one per platform:
  `R-<ver>-<platform>-compilers.tar.xz`, about 95 MB (linux-64). It
  holds zig 0.17 (PyPI's `ziglang` build, which is the ziglang.org
  release), flang 23.1.5 (flang-pixi's flang-zig and flang-rt-zig, the
  compiler R's own Fortran was built with: the driver, its runtime and
  the intrinsic modules) and OpenMP's headers (Windows also
  `libomp.lib`), which the `minimal` flavor, built without OpenMP, leaves
  alone. `ZIG_BIN` still overrides the group's zig. Run Fortran through
  zig-fc (`R CMD config FC`): the bare `toolchain/flang/bin/flang` needs
  `-fintrinsic-modules-path` with the target's directory under
  `toolchain/flang/lib/clang/23/finclude/flang/` (Windows has two, with
  the same files).
- **The build-tools group**, one per platform:
  `R-<ver>-<platform>-build-tools.tar.gz` (`.zip` on Windows, about
  18 MB). GNU make on linux and macOS, which R puts first on its `PATH`;
  on Windows sh, make and the tools R's makefiles and `configure.win`
  scripts run (MSYS2's, from conda-forge's m2 packages: bash, make,
  coreutils, sed, grep, gawk, which, findutils, patch, tar and, build
  14 on, gzip), pkg-config
  (pkgconf) and zip (Info-ZIP's, both built from source; zip build 14
  on), with the DLLs
  they load, in `usr/bin`,
  and MSYS's mount table in `etc/fstab`. R puts `usr/bin` first on
  `PATH`, in R and under `R CMD`. On Windows it also holds, build 14
  on, the native set in `native/bin` (busybox-w32, GNU make, zip and
  pkgconf, built with zig),
  which R puts first instead when `R_ZIG_NATIVE_TOOLS=1`. The binutils R's Makeconf names on
  Windows (nm, objdump, strip, dlltool, windres, as) come with R itself,
  in `R_HOME/bin/toolchain` beside gcc.exe: they are rzig, which reads
  and writes COFF itself and runs `zig dlltool`, `zig rc` and `zig cc`,
  on x86_64 and arm64 alike.
- **The extras group**, one per platform:
  `R-<ver>-<platform>-extras.tar.gz` (`.zip` on Windows, about 10 MB on
  linux-64): cmake 4.4.5 from Kitware's release archive (held below 4.5,
  which breaks the Boost arrow fetches), `bin/cmake` and
  `share/cmake-4.4/` (Modules, Templates), under `cmake/`, for packages
  that build a bundled library with CMake. R puts `cmake/bin` on `PATH`
  after the build tools' directory, in R and under `R CMD`. Linux's
  cmake needs only glibc (2.17 on x86_64, 2.28 on aarch64); macOS has
  Kitware's universal binary (macOS 11 and later); Windows' loads only
  system DLLs.
- **The recommended packages**, one per flavor and platform:
  `R-<ver>-<flavor>-<platform>-recommended.tar.gz` (`.zip` on Windows,
  about 25 MB for linux-64 slim): R's 15 recommended packages under
  `R_HOME/library/`, compiled with that flavor's R (mgcv links OpenMP,
  which the `minimal` base has not, so the flavor is in the name).
  Extracted over the base, they need no group.

Every archive has the same top directory, `R-<ver>-zig/`; the
recommended packages' files sit under its `R_HOME/library/`, and a group
archive's under its `R_HOME/bin/toolchain/`, each directory
with `SOURCES` (the package each file comes from, a conda-forge package,
for `flang/` flang-pixi's packages on prefix.dev's `universe` channel,
or, for `zig/`, PyPI's `ziglang` wheel, for `cmake/`, Kitware's
release archive, its sha256, and where its source is) and `LICENSES/`.
Extract the ones you need into one directory; no file is in two of
them:

```bash
sha256sum -c R-4.6.2-slim-linux-64.tar.gz.sha256
tar -xzf R-4.6.2-slim-linux-64.tar.gz           # R-4.6.2-zig/
tar -xJf R-4.6.2-linux-64-compilers.tar.xz      # + R-4.6.2-zig/lib/R/bin/toolchain/zig/, flang/, openmp/ and (linux) libstdcxx/
tar -xzf R-4.6.2-linux-64-build-tools.tar.gz    # + R-4.6.2-zig/lib/R/bin/toolchain/usr/bin/make
tar -xzf R-4.6.2-linux-64-extras.tar.gz         # + R-4.6.2-zig/lib/R/bin/toolchain/cmake/
tar -xzf R-4.6.2-slim-linux-64-recommended.tar.gz  # + R-4.6.2-zig/lib/R/library/{MASS,Matrix,...}/
R-4.6.2-zig/bin/Rscript -e 'R.version.string'
# Windows: R-4.6.2-win-64-build-tools.zip + R-4.6.2-zig\Library\lib\R\bin\toolchain\usr\bin\ (sh, make, ...) and etc\
```

On macOS, `tar -xf` extracts all five, the `.tar.xz` too. On Windows,
`tar -xf` extracts the `.zip` files the same way, and R is
`R-4.6.2-zig\Library\lib\R\bin\x64\Rscript.exe`. Once the base is
extracted, R's own reader extracts the compilers `.tar.xz`; run it where
you extracted R:

```bat
R-4.6.2-zig\Library\lib\R\bin\x64\Rscript.exe -e "untar('R-4.6.2-win-64-compilers.tar.xz', exdir = '.', tar = 'internal')"
```

System32's `tar -xf` extracts it too where `tar --version` lists liblzma
(Windows 11's current builds; Windows 10's `tar.exe` has none). Use one
directory per flavor: the bases and the recommended packages share the
top directory, and the groups serve every flavor of their platform.
When a compile misses a group,
rzig's message says which archive to extract or what to put on `PATH`.

`pixi run package` makes the base archive of the environment's flavor,
`pixi run package-toolchain` the group archives and `pixi run
package-recommended` the recommended packages' archive, in `dist/`; CI
keeps the base archives for a week and the group archives for 30 days
(see CI), and makes no recommended packages' archive. No release
publishes them yet.

### Older Linux HPC servers

The Linux build targets glibc 2.17 by default (both the R build itself
and the package-compilation toolchain it ships), so binaries — and any
CRAN package compiled against them — run on considerably older
distributions than the build machine, without a separate build variant.

### The platform packages are compiled for

rzig names R's own platform on every command it runs, on every OS:
`-target` to zig (`x86_64-linux-gnu.2.17`, `aarch64-native.13.0`,
`aarch64-windows-gnu`, ...) and `--target=` to flang, with
`-mcpu=baseline`, so a package is compiled for R's architecture and
that architecture's baseline CPU, whatever zig or flang is found first
on PATH. Windows left the target to zig until build 11, when an x64 zig
on Windows on ARM compiled for x64 against an arm64 R. The scripts stop
when pixi installed the environment for another platform than the
machine's (an emulated one, such as win-64 on Windows on ARM).

## CI

Everything runs on GitHub-hosted runners: `toolchain` (the toolchain
groups, once per platform), `build` (ubuntu-latest,
ubuntu-24.04-arm, macos-latest, macos-15-intel, windows-latest,
windows-11-arm × slim/full/minimal, plus openblas on linux and
windows-latest;
the same steps in the same order on
every OS, on the installed tree, which is the tree the standalone base
archive packs), and `conda-package` for all six subdirs (linux-64,
linux-aarch64, osx-arm64, osx-64, win-64, win-arm64; it builds
r-zig-recommended, and the full tier's `default` build legs build and
verify R's recommended packages too). Publishing to the `universe`
channel on prefix.dev (OIDC trusted publishing) happens only in a
dispatch of `build.yaml` on `main`, once, in the `conda-publish` job
after all six `conda-package` legs passed, and only while the
repository variable `CONDA_PUBLISH` is `true`; a push never publishes.
That variable is a release switch: it is set only for a build-number
bump's publish and deleted after it (build 13 was published on
2026-11-26; chore-review-consistency M3).
There is no self-hosted fleet — the former gamma/omicron/kappa runners
were decommissioned in September 2026 and fully removed on 2026-09-24.
Docs-only changes (`*.md`, `.github/devdocs/`, `LICENSE`) skip the
workflow.

The full matrix above runs only on request: on a pull request labelled
`full-ci` and on a manual dispatch (`pixi run ci-trigger` for main, `gh
workflow run build.yaml --ref <branch>` for a branch). Every other pull
request push and every push to `main` runs the core tier: `default` on
all six platforms and `minimal` on linux-64 (7 legs; the full tier has
21: `default`, `full` and `minimal` on all six, `openblas` on both linux
runners and windows-latest). `conda-package`
also runs on every push to `main` (build and test only), and on a pull
request that changes `recipe/`, `pixi.toml`, `pixi.lock`, `build.zig`,
`zigbuild/`, `scripts/` or the workflows. See
`.github/devdocs/chore-ci-tiers/PLAN.md`.

The build legs of both tiers wait for the `toolchain` job
(`.github/workflows/toolchain.yaml`), six legs, one per platform. Each
runs the toolchain build's unit tests (`toolchain-test`), makes the
toolchain tree and its three group archives (`package-toolchain`), checks
the tree (`verify-toolchain`) and uploads the archives as the artifact
`toolchain-<OS>-<arch>` (for example `toolchain-Linux-X64`). Every build
leg downloads its platform's archives first and unpacks them
(`unpack-toolchain`), so `contract` compiles in the compile tree. The
packaging legs (`default` on all six platforms, `minimal`) run
`verify-package`: the base archive, then the four scenarios with the
downloaded group archives (the base alone, with the compilers group,
with the build-tools group, with the extras group). They upload the base archive as
`standalone-<env>-<runner>` (for example `standalone-default-macos-latest`).
The base archives are kept for 7 days, the group archives for 30, as
long as GitHub lets a run's failed legs be re-run (they download them
again); nothing publishes the archives yet. A platform whose `toolchain` leg fails fails only its own
build legs.

`upstream-zig` runs the same `build` steps (`.github/workflows/build-r.yaml`,
shared by both workflows) on `default` for all six runners
with upstream zig (`pixi run fetch-zig`), after a
`toolchain` job of its own built with upstream zig (its artifacts' names
end in `-upstream`). It is a release gate, not per-commit CI: it runs on
demand (`gh workflow run upstream-zig.yaml`), for `v*` tags, and on pull
requests labelled `upstream-zig`. Every commit already compiles packages
with upstream zig through the wheel tests, whose compiler is PyPI's
`ziglang`.

The build, upstream-zig, stress, repo and win-binary workflows are
gated behind one repo variable, an emergency kill switch rather than a
cost control (hosted runners are free for this public repo); gen-config
(a dispatch, or a push that changes its own files) and release (its own
switch, below) do not read it:

```bash
gh variable set ENABLE_HOSTED_JOBS --body false  # pause all CI jobs
gh variable set ENABLE_HOSTED_JOBS --body true   # resume
```

No commit or workflow edit needed either way. Publishing has a switch
of its own, `CONDA_PUBLISH`: without it a dispatch on main still builds
and tests every subdir and uploads nothing. Set it for a build-number
bump's release and delete it after the release's check
(`.github/devdocs/RELEASE.md`):

```bash
gh variable set CONDA_PUBLISH --body true   # after the bump merges
gh workflow run build.yaml --ref main        # conda-publish uploads all six subdirs
gh variable delete CONDA_PUBLISH             # after universe and a fresh env check out
```

Two more workflows publish, each only on a manual dispatch on `main`
with a switch of its own, unset by default and set for one publish:
`release.yaml` (the standalone archives and the wheels of one full-tier
`build.yaml` run on `main`, as a GitHub Release, and with its `pypi`
input on PyPI, whose trusted publishers are not registered yet) needs
`R_ZIG_RELEASE=true`; `repo.yaml` (the linux binary package
repository, experimental) builds and tests on any dispatch and uploads
to GitHub Releases only with its `publish` input and
`R_ZIG_REPO_PUBLISH=true`. Neither has published anything yet.

## More detail

Build internals, platform-specific fixes, and the CI/publish pipeline are
tracked in `.github/devdocs/`, one directory per branch. The current
release's plan is `.github/devdocs/chore-release-13/PLAN.md` (build 14's
tracks: `.github/devdocs/b14-*/`), and the
steps every release follows are `.github/devdocs/RELEASE.md`. The
original build design that code comments cite is
`.github/devdocs/feat-zig-build/PLAN.md` (milestone 5, 2026-07).

## Licence

MIT for this repository's build scaffolding; R (GPL-2.0-only OR GPL-3.0-only),
the patches to R in `zigbuild/patches/` and the bundled third-party components
keep their own licences. See the scope note in `LICENSE`.
