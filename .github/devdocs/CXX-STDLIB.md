# The C++ standard library per platform

A design record that holds across branches, like CONVENTIONS.md. It
records which C++ standard library R packages compile against on each
platform, why, and what was ruled out. The probes and their numbers
are in `chore-release-11/PLAN.md`, finding 31 (2026-11-16).

## The problem

zig c++ links its own libc++ (namespace `std::__1`). A C++ API that
passes `std::string`, `std::vector` or exceptions across a shared
library boundary works only when both sides use the same standard
library. On linux, conda-forge, the distros, CRAN, Posit Package
Manager, r2u and Bioconductor's images build with gcc and libstdc++
(`std::__cxx11`). So, on linux only, a package that calls the C++ API
of a prebuilt library fails to load (undefined `std::__1` symbols).

| The package uses | Examples | Affected |
| --- | --- | --- |
| a C library | curl, openssl, xml2, hdf5r, RPostgres (libpq) | no |
| a C++ library through its C API | geos, proj, harfbuzz (lwgeom, s2, textshaping) | no |
| header-only C++ it compiles itself | Rcpp, cpp11, BH, Eigen, Armadillo, assorthead | no |
| a library it builds from bundled source | stringi, duckdb, arrow:source, Rhtslib | no |
| the C++ API of a prebuilt gcc library | Magick++, GDAL, protobuf, libv8 (magick, sf, terra, gdalraster, protolite, V8) | linux |
| C++ objects from another R package at run time | Rcpp's callables (demangle), textshaping's header to ragg (std::vector) | if the two differ |

Likely affected too, not tested: pdftools (poppler-cpp), tesseract,
opencv, RQuantLib.

Other platforms: macOS is libc++ everywhere (Apple, conda-forge, zig).
Windows (MinGW): the r-windows bundles are clang and libc++, as zig.
conda-forge's win-64 C++ libraries are MSVC builds, which no MinGW
toolchain links in any configuration.

## Decisions

1. **Each platform's native C++ standard library** (user, 2026-11-16):
   libc++ on macOS and Windows, libstdc++ on linux. This is the libc
   rule applied to C++: r-zig already accepts glibc, libSystem and ucrt
   under one interface. What stays the same on every platform is what
   users and package authors see: `R CMD INSTALL`, rzig, Makevars, the
   variants and their flags. The benefit: R packages compile against
   the C++ libraries conda-forge (and the distros) already ship.
2. **For all C++ on linux, not per package.** rzig could detect a
   libstdc++ library at link time, but packages pass C++ objects to
   each other at run time (Rcpp's `R_GetCCallable` functions,
   textshaping's API to ragg). A libstdc++ package beside a libc++ Rcpp
   gives 'double free' on the first C++ exception; the reverse gives
   'irrecoverable exception'. A per-package choice would make results
   depend on install order.
3. **Implemented on feat-linux-libstdcxx** (user, 2026-11-18: "Fix and
   implement all of it!"; that branch's PLAN.md has the decisions L1-L26,
   the findings and the evidence), on its own branch after release 11,
   with recipe build number 12. The branch flips the six rows from
   linux fail-abi to ok in stress/packages.tsv. The cpp11 rows
   (RPostgres, systemfonts, textshaping, ragg) and the Bioconductor rows
   (DESeq2, scran, Rsamtools) passed under libstdc++ in a linux-64
   stress tree leg (17 ok, 0 unexpected; that PLAN's finding 33). The
   run used conda-forge zig, before the review fixes. linux-aarch64 and
   the conda leg were not run.
4. **r-zig-slim has the run constraint `r-base <0a0`** (release 11).
   conda-forge's r-* packages depend on r-base; without the constraint,
   adding one to an env silently installs conda-forge's R over r-zig's.
   With it the solve fails and names r-base. It blocks every
   conda-forge r-* package, none of which can work beside r-zig's R
   today (R 4.4 and 4.5 builds; no R 4.6 builds on 2026-11-16).

## How libstdc++ on linux works

rzig does it, in `zigbuild/tools/rzig/libstdcxx.zig`, for every C++
command on linux (zig-cxx, and zig-cc with `-x c++`). The first probe
was T/abi-libstdcxx: zig c++ against the env's `libstdcxx-devel` 15.3.0.
- Compile: `-nostdinc++` before the caller's arguments. After them, and
  after the environments' `-I`, as gcc searches `-I` before its own C++
  headers: `-I` to rzig's two shim headers (`R_HOME/bin/toolchain/
  libstdcxx-shim`: `sys/single_threaded.h`, and a `bits/c++config.h`
  that undefines `_GLIBCXX_HAVE_OBSOLETE_ISINF` and `_ISNAN` for zig's
  glibc 2.17 headers), then `-I` to the headers
  (`lib/gcc/<triple>/<version>/include/c++`, its `<triple>` and
  `backward` directories), then `-D_GLIBCXX_SYSHDR`. libstdc++ 15 marks
  its headers as system headers only with that macro; it replaces the
  first probe's 131 `--system-header-prefix=` flags (warnings in a
  `-Wall -Wextra -pedantic` file: 146 without it, 0 with it).
- Where the headers are (first found): R's env (conda:
  `libstdcxx-devel_linux-*`, a run dependency of r-zig-compilers), the
  compilers group's `R_HOME/bin/toolchain/libstdcxx` (the standalone
  tree and the wheel), then `R_ZIG_EXTRA_ENV`; the highest version
  there. None: a compile stops with the compilers group's text, never a
  silent libc++ fallback. A command with no input (`--version`,
  `-dumpversion`, `-print-*`) gets no flags and needs no headers.
- Link: `-nostdlib++`, then R's runtime by path: `lib/libstdc++.so.6`
  and `lib/libgcc_s.so.1` of the first env that has both (R's own, then
  `R_ZIG_EXTRA_ENV`). DT_NEEDED is the soname. A caller's `-lstdc++`
  (and `-l:libstdc++.so*`) becomes those two paths on every linux link,
  C links too (cc-rs, cgo, a Makefile that links C++ objects with
  `$(CC)`): without libgcc_s zig links its own `libunwind.a`, and a throw
  aborts. `-lgcc_s` becomes its path; `-lstdc++fs` and `-lstdc++exp`
  gcc's archives beside the headers when they are there, else nothing;
  `-static-libstdc++` is dropped (a note under `RZIG_TRACE`; silent
  otherwise, on purpose (feat-linux-libstdcxx/PLAN.md decision L15): zig
  ignores it too, and a note on every link would reach configure and CMake checks that read stderr). The
  two-argument `-l stdc++` is rewritten too. `-Wl,-lstdc++` is not: lld
  then searches -L for `libstdc++.so` (a known gap).
- libR needs `libstdc++.so.6` and `libgcc_s.so.1` (build.zig's
  `linkCxxRuntime`; a reference from `zigbuild/cxx_runtime.zig` keeps
  zig's `--as-needed` from dropping them). Its RUNPATH then loads the
  tree's (or the env's) runtime before any package, in every variant:
  minimal too, whose libR loads no ICU. Without it a minimal or
  standalone R's packages bound the host's libstdc++, which is older
  than the headers on gcc < 13 hosts (the probe's F8).
- arrow: its `nixlibs.R` no longer refuses its prebuilt libstdc++
  libarrow, so on an allowlisted distro (or with `NOT_CRAN=true`) it
  downloads it instead of building from source. `LIBARROW_BINARY=false`
  keeps the source build.
- What does not work: zig ignores `-stdlib=libstdc++`; it maps
  `-lstdc++` to its own libc++ and drops `-lgcc_s` (without libgcc_s an
  exception thrown in libstdc++ code aborts); `-isystem` breaks
  libstdc++'s `#include_next <stdlib.h>`. So the flags go inside rzig,
  not in user flags (terra's configure needs them in the driver).
- R loads the tree's `libstdc++.so.6` (GLIBCXX_3.4.36, the env's
  libstdcxx 16); packages built with the 15.3 headers need at most
  GLIBCXX_3.4.32 (symbol versions follow what the headers reference).
- Tested in CI on PR #49 (2026-11-19, conda-forge zig): build-r
  44438791005 on all six hosts and conda subdirs, and stress 44438790229
  on linux-64 and linux-aarch64, tree and conda legs, 20 targets
  including arrow:source, rstan and qs2, all ok (feat-linux-libstdcxx
  PLAN.md findings 64-66).
- Not tested yet (full list: feat-linux-libstdcxx/PLAN.md "Not
  verified"): upstream zig in CI (no 'upstream-zig' label run); stress
  on macOS and Windows; hosts with a libstdc++ older than
  GLIBCXX_3.4.32; Rust (cc-rs) and Go packages; a CMake mixed C/C++
  target linked through the C compiler; `-Wl,-lstdc++`; a prebuilt
  libc++ static archive inside a package.

Known differences from gcc:
- **`-isystem` order.** rzig passes libstdc++'s directories as `-I`
  (`-isystem` breaks its `#include_next <stdlib.h>`), and clang searches
  every `-I` before any `-isystem`. gcc searches a caller's `-isystem`
  before its own C++ headers. So a package's `-isystem` copy of a
  standard C++ header does not override libstdc++'s with rzig, as it
  would with gcc. Not a regression: the review found the released rzig
  (zig's libc++ headers) behaves the same.
- **The process's libstdc++ is R's.** libR loads the tree's (or env's)
  runtime first, and the soname then wins for the whole process. An
  `R_ZIG_EXTRA_ENV` whose libraries were built with a newer libstdcxx
  (17.x later) than R's runtime gives "GLIBCXX_3.4.3x not found" when
  they load. This already happened for slim through ICU; it is new for
  minimal and the wheel. Not probed: rpy2 or other embedded R, where
  Python may have loaded the host's older libstdc++ first; then
  packages that need GLIBCXX_3.4.32 fail to load.

## Ruled out, and why

- **Rebuild the C++ libraries with zig and libc++** (T/abi-cxxrebuild).
  It works: Magick++ in seconds, abseil and protobuf in about 2 min,
  GDAL 3.13.2 in about 5 min (37 MB stripped, renamed soname, without
  xerces-c, libkml, muparser, OpenEXR); V8 from its author's libc++
  bundle. But r-zig would own every rebuild on every upstream release
  (4-6 days to set up, then upkeep), and GDAL loses drivers. It is the
  opposite of reusing what conda-forge builds.
  Amended (feat-zig-libs, 2026-11-22): for Windows it is done, in a
  repository of its own, libs-zig-pixi, not in r-zig. There conda-forge
  has no usable C++ build at all (MSVC on win-64, none on win-arm64), so
  there is nothing to reuse. Its `zig-*` conda packages (zig-zlib 1.3.1,
  zig-sqlite 3.51.2, zig-expat 2.7.3, zig-openssl 3.6.0, zig-abseil
  20250127.0, zig-onetbb 2022.2.0, zig-geos 3.14.1, zig-proj 9.7.1,
  zig-gdal 3.12.1 with 166 drivers) are static libraries built with zig
  and libc++ for win-64 and win-arm64, in `<env>/Library/zig-libs/<triple>`.
  rzig searches that directory before its environment, R's
  `Rcmd_environ` puts its `.pc` files first and points `R_TOOLS_SOFT` at
  it, and stress.R's s2, sf, terra and gdalraster rows expect `ok` on
  Windows with them (stress/README.md, "Windows: zig-libs"). Linux and
  macOS stay as decided above: libstdc++ on linux (decision 2),
  conda-forge's libc++ on macOS. Published on universe since 2026-11-23
  (libs-zig-pixi M5); the Windows stress env takes them (PR #52).
- **Per-package switching in rzig**: decision 2.
- **conda-forge's prebuilt r-* packages** (T/abi-condaforge-bin). R 4.5
  builds load in r-zig's R 4.6.2 (except rlang: SETLENGTH is gone in
  R 4.6), but there are no R 4.6 builds yet, and their Rcpp is
  libstdc++, so mixing them with libc++ packages crashes.
- **Accept the boundary**: leaves sf and terra, the base of R's spatial
  ecosystem, unusable on linux.

## Windows on ARM: the Rtools45 tree

stress.R uses CRAN's Rtools45 aarch64 toolchain-libs tree on Windows on ARM
for the libraries conda-forge lacks there (stress/README.md,
feat-winarm-gaps). That tree is LLVM 19 libc++ (std::__1), as zig. Its C++
libraries (GDAL, Magick++, oneTBB, libnlopt's StoGO) link with zig's clang
22 libc++ and libc++abi from zig's cache: package-like DLLs cross-linked
from linux, with both zigs (2026-11-18). So on win-arm64 GDAL's C++ API
(gdalraster, terra, sf) may work, unlike win-64. Not checked: run time,
C++ exceptions thrown in the tree's code and caught in zig's, and layout
skew between LLVM 19's libc++ headers and zig's clang 22 libc++. win-64
is not affected: conda-forge is MSVC there, and x86_64 Rtools is gcc's
libstdc++.

With libs-zig-pixi's aarch64 `zig-*` packages (zig's own clang and libc++,
the same as the packages) the GDAL stack, abseil and oneTBB come from
zig-libs, which rzig searches before the env and the tree, and the tree
keeps the libraries libs-zig-pixi does not build (nlopt, gsl, mpfr, gmp,
glpk, hdf5, netcdf, udunits2, harfbuzz, libpq). The LLVM 19 against clang
22 skew above then no longer applies to those four rows. R_ZIG_FALLBACK_SOFT
stays until no stress row resolves an `-l` into the tree (the report's
zig-libs column, with `--trace`); retiring it is a later slice.

## Deferred (no decision)

- **Reusing conda-forge's R packages** (user, 2026-11-16: no design
  decision yet). Candidates: an `r-base` metapackage on universe
  (version = R's, build `zig_*`, depending on r-zig-slim) that lets
  conda-forge's r-* packages solve against r-zig's R; or a `_r-mutex`
  build of r-zig's own (conda-forge's r-base depends on
  `_r-mutex 1.* anacondar_1`). Raise again only when r-zig's build is
  stable and conda-forge ships R packages built for R 4.6 or later.
  Known issues: safe only after decision 1 lands on linux (their Rcpp
  is libstdc++); universe must be listed before conda-forge, so with
  strict channel priority a universe `r-base` or `_r-mutex` shadows
  conda-forge's for every universe user, r-zig or not; r-zig-recommended
  installs the same files as conda-forge's r-mass, r-class,
  r-kernsmooth.
  Watch (chore-release-12 M11, decision D11, 2026-11-23): unchanged.

## Standalone and wheel on linux: option (a), default chosen by Claude

Chosen 2026-11-18 on feat-linux-libstdcxx, as a default by Claude; the
user may revisit it (that branch's PLAN.md, decisions L4 and L5). The
user had not answered the 2026-11-16 menu.

- L4, one mode: option (a) below. The standalone tree and the wheel
  ship libstdc++'s headers, and the runtime is the one in R's tree.
- L5, which group holds the headers. Options: (a) the compilers group
  (implemented); (b) the base, the r-zig wheel and r-zig-slim (+ about
  3 MiB compressed), so C++ works with ziglang alone; (c) another
  layout. Choice (a): the headers are only needed to compile, like zig
  and flang.

Layout: the standalone compilers archive's and the pip r-zig-compilers
wheel's `R_HOME/bin/toolchain/libstdcxx/lib/gcc/<triple>/<version>/include/c++`
(copied from `libstdcxx-devel_linux-*` by its conda-meta record,
zigbuild/toolchain/build.zig; include/c++ is 5.6 MB by du, 131
entries, the same in the conda package and the toolchain tree; the
toolchain tree's whole libstdcxx/ is 5.7 MB), and conda's r-zig-compilers
depends on `libstdcxx-devel_linux-*` 15.* and `libstdcxx >=15`. The
two shims are the base's, beside rzig. The runtime is the base's `lib/`
(`libstdc++.so.6`, `libgcc_s.so.1`, which libR needs). Consequence: r-zig
with ziglang alone, without r-zig-compilers, compiles C but no longer
C++ on linux; the preflight stops a C++ package with the compilers
group's text.

The record of the options, kept: neither has a conda env, so neither
had libstdc++ headers. Options: (a) ship the headers and the newest
`libstdc++.so.6` in the tree; (b) keep libc++ there (a second mode);
(c) use the host's or an env's headers when present.

- **Standalone**: users would reuse distro libraries (libgdal-dev,
  libmagick++-dev), gcc and libstdc++ builds with the same new ABI as
  conda-forge. A binary built against newer headers needs a libstdc++
  at least as new at run time, but libstdc++ is backward-compatible: a
  tree that ships the newest runtime with its headers (a) also runs a
  distro's older libgdal. Leaning: (a), one mode. To probe: Ubuntu
  22.04 (gcc 12) and 24.04 with distro GDAL and Magick++; the size of
  the headers.
- **Wheel**: PyPI wheels do not, as a rule, provide libraries to link
  against. auditwheel copies dependencies into a private
  `<pkg>.libs/` with hashed names and no headers (rasterio and fiona
  for GDAL, Pillow, pyproj). Linking against those would need path and
  soname tricks, against r-zig's goals. Exceptions made for linking:
  pyarrow (libarrow with `pyarrow.get_include()`; the arrow R package
  needs a matching libarrow version), scipy-openblas32/64 (headers and
  pkg-config). manylinux2014 wheels use the old libstdc++ string ABI
  (`_GLIBCXX_USE_CXX11_ABI=0`), manylinux_2_28 the new one. PEP 725
  (external dependency metadata) is a draft and ships no libraries.
  Leaning: the wheel is the standalone tree inside a Python package
  for C++ (same headers, same runtime, libraries from the system or a
  conda env), plus the few linkable library wheels where they fit. To
  probe: rpy2 embedding R in Python, where R's libstdc++ shares the
  process with Python's and each wheel's vendored copy.
