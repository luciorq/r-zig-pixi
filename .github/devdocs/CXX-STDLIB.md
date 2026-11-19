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
3. **Planned after release 11**, on its own branch. Release 11 keeps the
   six rows as linux fail-abi in stress/packages.tsv. The branch reruns
   the cpp11 rows (RPostgres, systemfonts, textshaping, ragg) and the
   Bioconductor rows (DESeq2, scran, Rsamtools) under libstdc++.
4. **r-zig-slim has the run constraint `r-base <0a0`** (release 11).
   conda-forge's r-* packages depend on r-base; without the constraint,
   adding one to an env silently installs conda-forge's R over r-zig's.
   With it the solve fails and names r-base. It blocks every
   conda-forge r-* package, none of which can work beside r-zig's R
   today (R 4.4 and 4.5 builds; no R 4.6 builds on 2026-11-16).

## How libstdc++ on linux works (probe, linux-64)

T/abi-libstdcxx: zig c++ against the env's `libstdcxx-devel` 15.3.0.
- Compile: `-nostdinc++`, `-I` to the headers (`lib/gcc/<triple>/15.3.0/
  include/c++` and its `<triple>` directory), `--system-header-prefix=`
  for the header names, and two shim headers: `sys/single_threaded.h`,
  and a `c++config.h` that undefines `_GLIBCXX_HAVE_OBSOLETE_ISINF` and
  `_ISNAN` (zig's glibc 2.17 headers).
- Link: `-nostdlib++ -l:libstdc++.so.6 -l:libgcc_s.so.1`.
- What does not work: zig ignores `-stdlib=libstdc++`; it maps
  `-lstdc++` to its own libc++ and drops `-lgcc_s` (without libgcc_s an
  exception thrown in libstdc++ code aborts); `-isystem` breaks
  libstdc++'s `#include_next <stdlib.h>`. So the flags go inside rzig,
  not in user flags (terra's configure needs them in the driver).
- R already loads `libstdc++.so.6` through ICU (the tree's lib/,
  GLIBCXX_3.4.36); packages built with these headers need
  GLIBCXX_3.4.32.
- Not tested yet: linux-aarch64, the minimal variant (no ICU), the wheel,
  arrow (it would take its libstdc++ prebuilt instead of building).

## Ruled out, and why

- **Rebuild the C++ libraries with zig and libc++** (T/abi-cxxrebuild).
  It works: Magick++ in seconds, abseil and protobuf in about 2 min,
  GDAL 3.13.2 in about 5 min (37 MB stripped, renamed soname, without
  xerces-c, libkml, muparser, OpenEXR); V8 from its author's libc++
  bundle. But r-zig would own every rebuild on every upstream release
  (4-6 days to set up, then upkeep), and GDAL loses drivers. It is the
  opposite of reusing what conda-forge builds.
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

## Open: standalone and wheel on linux

Neither has a conda env, so neither has libstdc++ headers. Options:
(a) ship the headers and the newest `libstdc++.so.6` in the tree;
(b) keep libc++ there (a second mode); (c) use the host's or an env's
headers when present.

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
