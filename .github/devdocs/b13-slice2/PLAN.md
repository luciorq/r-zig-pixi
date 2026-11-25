# b13-slice2

## Goal

Consume libs-zig-pixi slice 2 (published on universe 2026-11-25, libs run
45603825536; win-64 and win-arm64, static only, `Library/zig-libs/<triple>`
with closed `.pc` files) in the stress suite: the stress env's Windows
dependencies (pixi.toml), a relock, the `packages.tsv` rows the slice
serves (sysdeps, expects, notes), a win-64 run on kappa, and the list of
rows that still need the Rtools45 aarch64 tree, which decides when
`R_ZIG_FALLBACK_SOFT` can go (build 14; not retired here).

Slice 2: zig-gmp 6.3.0, zig-mpfr 4.2.2, zig-glpk 5.0, zig-gsl 2.7.1,
zig-nlopt 2.10.0, zig-udunits2 2.2.28, zig-libpq 16.10, zig-zstd 1.5.7,
zig-xz 5.8.2, zig-libdeflate 1.25, zig-brotli 1.2.0, zig-bzip2 1.0.8,
zig-libpng 1.6.54, zig-libjpeg 9f, zig-libwebp 1.6.0, zig-libtiff 4.7.1,
zig-freetype 2.14.1, zig-fribidi 1.0.16, zig-harfbuzz 12.3.0,
zig-libiconv 1.17, zig-libxml2 2.12.10, zig-libaec 1.0.6, zig-hdf4 4.2.15,
zig-hdf5 1.12.1, zig-libcurl 8.18.0 (Schannel), zig-netcdf 4.9.2; slice 1
rebuilt at build 1 (zig-zlib, -sqlite, -expat, -openssl, -abseil,
-onetbb, -geos, -proj, -gdal).

## Decisions

| id | question | options (chosen in bold) | reason | who, date |
|---|---|---|---|---|
| D1 | conda-forge's Windows-only stress deps that zig-* now replace | **remove from `[feature.stress.target.win-64.dependencies]` udunits2, harfbuzz, hdf5, libnetcdf, gsl, mpfr, gmp, libpq, glpk, nlopt; keep libprotobuf and imagemagick**; keep all of them next to zig-* | each was used only by rows the slice now serves (units, textshaping, hdf5r, ncdf4, gsl, Rmpfr, RPostgres, igraph, nloptr); they are MSVC builds that left traps for a zig link even with zig-libs first (gsl's MKL gslcblas.lib: F1; conda-forge's HDF5 2.2 API: hdf5r; the missing glpk.pc: igraph); with them gone win-64 and win-arm64 resolve the same names from the same zig-* packages. libprotobuf (protolite) and imagemagick (magick) have no zig-* package. The all-six table (freetype, libpng, libtiff, libjpeg-turbo, libwebp-base, fribidi, libxml2-devel, ...) stays: it is not Windows-only and the task leaves it | default, 2026-11-25 |
| D2 | Slice-1 packages at build 0 in the lock (pixi lock keeps a locked build that still matches `*`) | **`pixi update -e stress -p win-64 -p win-arm64` on the nine slice-1 names to their build 1**; leave build 0 | libs' consumer job (the expect evidence) ran build 1 with zig-toolchain 0.2.0; one zig-libs tree from one toolchain | default, 2026-11-25 |
| D3 | Windows sysdeps of the served rows | **conda-forge names `@linux @macos`, `zig-<name>@windows`** (as sf, terra, gdalraster); conda-forge names on every OS plus zig-* | a `--conda` env on Windows then installs the zig-* package only, and a tree run's drift check names what the row uses | default, 2026-11-25 |
| D4 | RPostgres' boost headers | **`libboost-headers@windows` in RPostgres' sysdeps** | zig-libpq's closed libpq.pc has -lwldap32 in Libs, so RPostgres 1.4.10's Makevars.win takes the system libpq ("using libpq from Rtools") and needs boost from the env, as libs S2-F27 found; the conda leg's env had no libboost-headers (2026-11-23 note) | default, 2026-11-25 |
| D5 | Evidence for expects | **ok where libs run 45603825536's r-consumer job (r-zig _12 from universe, zig-* from universe, conda env, both arches) or a kappa run showed the row (none ran: F7); `?` otherwise** (scran on win-64: no run has it) | the task's rule; the r-consumer job is the same zig-libs-first setup (zig-libs' `.pc` files first, rzig's zig-libs search), without the Rtools45 tree | default, 2026-11-25 |
| D6 | `rtools_has` and `R_ZIG_FALLBACK_SOFT` | **unchanged** | with the D3 sysdeps no served row asks the tree for a sysdep, so `rtools_has`' conda names are unused on Windows; retiring the fallback is build 14's step, after a windows-11-arm `--no-rtools-libs` run (F4) | default, 2026-11-25 |

## Findings

- F1 (V) Current state, stress 45548386803 on e26b5ff, artifacts read row by row. windows-latest tree non-ok: jpeg `*** ERROR: unable to
  find JPEG files` (zig-libjpeg missing), hdf5r `Wrapper_auto_H5P.c:1525:71 ... 'off_t *' ... 'HDoff_t *'`, gsl `LoadLibrary failure:
  The specified procedure could not be found.`, igraph `'libxml/globals.h' file not found`, Rsamtools skipped (Rhtslib), protolite and
  arrow abi (std::__1 undefined), scran skipped (igraph, bluster), rstan smoke. win-64 link lines (rzig trace): units `-ludunits2
  ENV/lib/udunits2.lib`, nloptr `ENV/lib/nlopt.lib`, Rmpfr and gmp `libgmp.dll.a`/`libmpfr.dll.a`, ncdf4 `netcdf.lib libcurl.lib psl.lib
  libssh2.lib`, textshaping `harfbuzz.lib freetype.lib fribidi.lib`, ragg `freetype.lib png16.lib tiff.lib jpeg.lib libwebp*.lib`, xml2
  `xml2.lib`: conda-forge's DLL import libraries; RPostgres downloads the r-windows libpq bundle; curl its own bundle.
- F2 (V) The windows-11-arm tree leg of the same run: -l names and archives by path that resolved into the Rtools45 tree (rzig trace and
  the closed `.pc` archive paths in each `-shared` link): gmp, Rmpfr (gmp mpfr), gsl (gsl gslcblas), nloptr (nlopt), units (udunits2),
  hdf5r (dl hdf5 hdf5_hl sz z), igraph (glpk iconv lzma xml2 z), ncdf4 (netcdf hdf5 hdf5_hl mfhdf df curl ssl crypto ssh2 nghttp2 psl
  idn2 unistring gcrypt gpg-error brotli* zstd sz jpeg xml2 iconv lzma z portablexdr dl), ragg/systemfonts/textshaping (freetype
  harfbuzz fribidi png16 tiff jpeg webp webpmux sharpyuv deflate Lerc zstd lzma bz2 brotli* glib-2.0 intl pcre2-8 iconv uuid z),
  RPostgres (pq pgport pgcommon ssl crypto z), xml2 (xml2 iconv lzma z), nanoarrow (lz4 zstd), Rhtslib and Rsamtools (regex gcrypt
  gpg-error idn2 unistring), magick, V8 and RcppParallel (`-lssp`). Every name but those of nanoarrow (lz4), Rhtslib (regex, gcrypt,
  gpg-error, idn2, unistring) and `-lssp` now has a zig-* package that comes first (zig-libs' `.pc` files before the tree's, rzig's
  zig-libs search before the fallback).
- F3 (V) `-lssp` on win-64 resolves to `(none)` (zig's own; compiler_rt has ssp.zig), stress e26b5ff windows-latest magick.log; on
  win-arm64 the tree's libssp.a is found first only because the tree is on -L. Without the tree it should resolve as on x64 (I).
- F4 (I) Rows that still need the Rtools45 tree on windows-11-arm with `--no-rtools-libs` (`rtools_libs=false`): Rsamtools through
  Rhtslib (regex.h and -lregex; gcrypt, gpg-error, idn2, unistring through the tree's libcurl closure, which zig-libcurl now replaces
  first), and arrow's dependency nanoarrow (lz4 from the tree; arrow is fail-package there anyway). Headers taken through `-idirafter
  <tree>/include` leave no trace line, so a header-only use elsewhere is not excluded: only a `--no-rtools-libs` run shows it.
- F5 (V) Lock: only the stress env's win-64 and win-arm64 package lists changed (every other env and platform identical, no package
  record changed in place). win-64: 33 conda-forge records out (the ten D1 libraries and what only they pulled: mkl, libblas/libcblas/
  liblapack mkl, numpy, tbb, libhwloc, the aws-c-* set, blosc, snappy, lz4-c, hdf4, libaec, libudunits2, vs2015_runtime), 26 zig-*
  in; win-arm64: 26 zig-* in; both: the nine slice-1 packages build 0 -> 1 (D2). zlib, bzip2, liblzma-devel, libcurl, icu and
  libboost-headers stay in the win-64 env (Rsamtools', curl's, stringi's, RPostgres' sysdeps).
- F6 (V) GLPK's static archive carries a `DllMain` (libs S2-F12, CONTRACT.md 2: GLPK's Windows code, as CRAN's Rtools build): it
  becomes the entry point of a DLL that links libglpk.a, so a package with its own `DllMain` that links glpk gets a duplicate symbol.
  igraph defines none and loads (libs r-consumer, both arches). Recorded in igraph's row note.
- F7 (V) kappa unreachable 2026-11-25 from 12:20 to 13:00 EST: `ssh kappa` "No route to host" (LAN 192.168.1.24) and a time-out
  (tailscale 100.102.76.86); `tailscale status`: offline, last seen 44 minutes before. Step 4 (slim compile tree and the stress rows on
  win-64) did not run; no scratch directory was made there. The win-64 expect changes (hdf5r, gsl, igraph to ok) rest on the libs
  r-consumer job alone (D5); scran stays `?` on win-64.

## Tests

| host | command | result |
|---|---|---|
| delta | `pixi lock`, then `pixi update --no-install -e stress -p win-64 -p win-arm64 zig-zlib zig-sqlite zig-expat zig-openssl zig-abseil zig-onetbb zig-geos zig-proj zig-gdal` | pixi.lock befa3d7cd247 -> 87b58a42ca62; per-env diff: only stress win-64 and win-arm64 changed (F5) |
| gamma | packages.tsv parsed as stress.R does (read.delim, `on_os`) | 46 rows, 10 fields each; Windows sysdeps: the 24 zig-* names, libboost-headers, and the unchanged conda names |
| kappa | ssh, 12:20 to 13:00 EST | unreachable (F7); not run: `pixi run build`, `pixi run toolchain`, `pixi run -e stress stress --trace jpeg igraph gsl hdf5r xml2 ragg ncdf4 RPostgres units nloptr Rmpfr textshaping systemfonts scran` |
| gamma | stress 45548386803 artifacts (windows-latest tree, windows-11-arm tree) | F1, F2, F3 |
| delta | `pixi lock --check` (pixi 0.84.2); `Rscript stress/stress.R --sysdeps all` (R 4.6.2 zig build); per-env package sets of pixi.lock vs HEAD | lock up to date (87b58a42ca62); rc 0, 46 rows; only stress win-64 (42 out, 35 in) and win-arm64 (9 out, 35 in) differ, the nine slice-1 build 0 -> 1 swaps included; linux and macos sysdeps of every row unchanged |

## Not covered

- win-64 with this lock: no kappa run (F7). Next: the kappa command in Tests, or a stress dispatch with `oses=["windows-latest","windows-11-arm"]`, `packages='jpeg igraph gsl hdf5r xml2 ragg ncdf4 RPostgres units nloptr Rmpfr textshaping systemfonts scran'`, `trace=true`, once with `rtools_libs=false`.
- windows-11-arm: no run with slice 2 here (no arm64 Windows host); its expects rest on the libs r-consumer job (D5). F4's list needs
  a stress dispatch with `rtools_libs=false` before build 14 retires `R_ZIG_FALLBACK_SOFT`.
- The conda distribution (`--conda`) on either Windows arch with the new sysdeps.
- Upstream (PyPI ziglang) zig.
