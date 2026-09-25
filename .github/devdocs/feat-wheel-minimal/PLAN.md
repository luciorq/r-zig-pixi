# feat-wheel-minimal — the `minimal` variant and the r-zig Python wheel

**Status (2026-09-24): linux-64 done end to end, locally.** `minimal`
builds with `zig build`, passes smoke, the CRAN contract suite, R's
regression suite (`check`) and verify-package, and `pixi run -e wheel wheel` turns it into
`r_zig-4.6.1-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl`
(49 MiB). That wheel pip-installs into a fresh venv next to PyPI
`ziglang` 0.16.0 and compiles a C/C++ package outside pixi. It does so
through three zig lookup paths (below). linux-aarch64, osx-64 and
osx-arm64 are wired but not yet built: their vendored configs come from
gen-config.yaml's new minimal legs. Windows is out: gnuwin32 has no
switches for any of this.

## Goal

A variant smaller than slim that can ship inside a Python wheel: one
`pip install` gives a working R, including `install.packages()` for
packages with C/C++ code. The compiler comes from the `ziglang` package
on PyPI rather than from the system or conda.

## The profile

| | slim | minimal | why minimal drops it |
|---|---|---|---|
| cairo/png devices (pango, harfbuzz, fontconfig, freetype, glib, pixman, X11 libs) | yes | **no** | the biggest dependency closure. `pdf()`/`postscript()` still work (grDevices' own C) |
| ICU | yes | **no** | ~35 MiB of libs. Collation falls back to the C library |
| OpenMP | yes | **no** | a libomp inside a Python process conflicts with the libgomp/libomp that numpy/scipy/torch wheels load |
| libdeflate | yes | **no** | lazy-load compression falls back to zlib |
| translation catalogs | shipped | **not shipped** | NLS is off in both, so R never reads them. Upstream's make install copies them anyway; slim keeps that parity |
| debug info | kept | **stripped** | R's own binaries (`.strip` in newCMod) and vendored libs (package-standalone.sh, before patchelf) |
| tcltk/readline/NLS/jpeg/tiff/X11/aqua | no | no | |
| pcre2, libcurl, zlib/bzip2/xz, zstd, iconv | yes | yes | required by R's configure (zstd/iconv come with them) |

Every optional part is switched off explicitly in configure-only.sh
(`--without-cairo --without-libpng --without-ICU --disable-openmp
--without-libdeflate-compression`, plus slim's). Leaving it to "not
installed" is not enough: on linux-64, flang's LLVM puts icu, llvm-openmp
and libiconv into the env regardless. The `minimal` pixi environment is
its own (`no-default-feature`) anyway, so the graphics stack isn't even
installed. Its toolchain lines duplicate the default ones, so keep them
in sync. The tasks don't: the R pipeline tasks moved from `[tasks]` into
`[feature.pipeline.tasks]`, which every build environment lists. A copy
in the minimal feature had made bare `pixi run build` fail as
"ambiguous". pixi resolves a task to `default` only when every
environment offering it gets it from the same feature.

build.zig reads what to compile from the vendored config, not from the
variant name: `Ctx.openmp` from `R_OPENMP_CFLAGS` (gates `-fopenmp` in
addCGroup and `-lomp` in linkOmp) and `Ctx.devcairo` from
`BUILD_DEVCAIRO_TRUE` (cairo.so, exactly as grDevices' Makefile.in
decides). (`HAVE_OPENMP` is still defined in minimal's config.h, a quirk
in R's configure `elif` branch, but no C source reads it.)

## The wheel

`scripts/make-wheel.py` (stdlib only, no build backend) zips the tree
that verify-package leaves in `dist/R-<ver>-minimal-zig` under
`r_zig/R/`, adds `python/r_zig/` (the Python package) and a `.dist-info`
(METADATA with `Requires-Dist: ziglang>=0.16.0,<0.16.1`, WHEEL,
entry_points, RECORD, R's COPYING).

- **Console scripts** `R`/`Rscript` (and `python -m r_zig`) set
  `ZIG_BIN` from `import ziglang` and exec the bundled launchers.
  `r_zig.r_home()`/`r_zig.environ()` are for embedders (rpy2).
- **Finding zig at compile time.** Makeconf names the zig-cc/zig-cxx/
  zig-ar/zig-ranlib shims. They exec `$ZIG_BIN` when it is executable,
  else a `zig` on PATH, else `python3 -m ziglang`. The wheel's
  `etc/Renviron.site` defaults `ZIG_BIN` to
  `${R_HOME}/../../../../ziglang/zig`, the sibling install pip normally
  produces, so an R started without the console scripts still finds it.
  wheel-test.sh runs `R CMD INSTALL --preclean` once for each of the
  three paths.
- **make is bundled** (minimal only, stage.sh): `python:*-slim` images
  have none. conda-forge's make links libc only, at GLIBC_2.17. Renviron's
  `MAKE` default points at it; Renviron only expands a nested default
  that is a whole `${...}` term, hence the `R_ZIG_MAKE` helper.
- **FLIBS is emptied** (minimal only, package-standalone.sh): the flang
  runtime is linked statically into libR/libRblas/libRlapack, and FLIBS'
  `-L` pointed into the build env. With it empty, C/C++ packages using
  CRAN's usual `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` link.
  **Fortran packages are not supported**: ziglang has no Fortran
  frontend.
- **Platform tag from the binaries.** Linux takes the highest `GLIBC_x.y`
  in any ELF's `.gnu.version_r`, parsed directly. A byte regex was tried
  first and claimed 2.36: binutils' `nm` carries "GLIBC_2.36" as data.
  The parser matches `objdump -T` on 272 ELF files. macOS takes the
  highest LC_BUILD_VERSION minos, rounded up to `N_0` for 11+ because pip
  only generates those tags.
- **manylinux2014 needed two changes** (minimal only, stage.sh): don't
  bundle `realpath` (coreutils needs GLIBC_2.28, and its only user is
  `bin/javareconf`, behind an `if realpath ...` guard, with R built
  `--disable-java`), and drop `bin/R`'s lib64 multilib probe (dead once
  R_HOME_DIR is self-derived, and it was the only build path in a
  run-time file; make-wheel.py refuses those).
- **macOS deployment target 13.0** (minimal only, build.zig): a native
  macOS query stamps every binary with the *build host's* version, so a
  wheel from a macOS 15.x runner would claim 15.x. 13.0 is zig 0.16's
  own supported floor; ziglang needs 12. This means a non-native OS query
  and zig's bundled Darwin headers. Checked against the source: the
  only SDK-only headers R includes are under `HAVE_AQUA`, and minimal
  links no framework. **Not yet built on macOS.**

## Measured (linux-64, 2026-09-24)

| | before trimming | after |
|---|---|---|
| standalone tarball | 68 MiB | 50 MiB |
| wheel | — | 49.2 MiB (94 MiB unpacked, 1415 files) |

Largest wheel items: libicudata 12.2 MiB, R_HOME/doc 4.3, stats 3.9,
base 3.5, R's own libs 2.7, libcrypto 2.4. R's own binaries link only
pcre2, zstd, lzma, bz2, zlib, iconv (libR) and libcurl (internet.so).
verify-bundle.sh now fails if any of them links graphics/ICU/OpenMP/
libdeflate libraries.

## Open

- **ICU is back, but only through libcurl.** conda-forge's libcurl >= 8.21
  (2026-08-19) links libpsl, which is always built against ICU (and so
  libstdc++). That is libicudata + libicuuc + libstdc++ = 14.3 MiB of the
  49 MiB wheel. Pinning `libcurl <8.21` in `[feature.minimal]` removes it
  (8.20.0 is from 2026-04-29) at the cost of shipping an older curl. Not
  done: that is a security-vs-size call for the maintainer.
  verify-bundle.sh reports these libraries and doesn't fail on them.
- **Other platforms**: run gen-config (push to a branch, or dispatch on
  main), vendor `zigbuild/config/{linux-arm64,osx-x86_64,osx-arm64}-minimal`,
  then add each OS to build.yaml's `minimal` matrix include.
- **Third-party license texts** for the vendored libraries (OpenSSL,
  curl, krb5, ICU, ...) are not in the wheel yet. Needed before
  publishing to PyPI. The conda packages' `info/licenses` are the source.
- **Publishing**: not wired. PyPI trusted publishing needs the project
  created on PyPI first, and the name `r-zig` is still to be checked or
  claimed.
- The first C++ package compiled into a fresh zig cache builds zig's own
  libc++ and prints ~3k `-Wnullability-completeness` warnings from its
  headers. This is zig's own output, once per cache.
- The slim/full conda packages likely have the same host-version macOS
  minos issue that the deployment-target change fixes for minimal. Worth
  checking with `otool -l` on a published osx package.
