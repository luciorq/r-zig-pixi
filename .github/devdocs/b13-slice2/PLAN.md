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
| D7 | conda-forge geos and proj in the Windows stress env (F11) | **unix only** (a); (b) unset PROJ_NETWORK and PROJ_DATA in stress.R; (c) add proj-data | no Windows row uses them (sysdeps say `zig-proj@windows`); (a) removes the mixed PROJ data instead of masking it | default, 2026-11-25 |

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
- F8 (V) kappa back 2026-11-25: win-64 tree stress on f243dc7, lock 87b58a42ca62, zig 0.17.1, `--libs-smoke=main`, targets hdf5r gsl
  igraph units xml2 systemfonts textshaping ragg ncdf4 Rmpfr nloptr RPostgres jpeg sf terra gdalraster scran (gmp is no row; it built as
  Rmpfr's dependency). report.json: 92 rows, every one ok, unexpected FALSE, first_error empty, sysdeps_missing empty; expects all ok
  but scran `?`. zig-proj 9.7.1 zig_fb84dec_1, zig-geos 3.14.1 zig_51e08d0_1, zig-gdal 3.12.1 zig_f2af728_1.
- F9 (V) The libs smoke fails on Windows, before and after slice 2 (stress 45548386803 on e26b5ff, 45662479912 on f406624 windows-11-arm,
  kappa F8): sf `st_transform 4267 -> 32119 (PROJ)` NA, gdalraster `srs_to_wkt + transform_xy` "transformation failed for all points"
  with `PROJ: Cannot open https://cdn.proj.org/us_noaa_WO.tif: Network functionality not available`. PROJ picks the NAD27 grid
  operation, whose grid is not in the env, and network is off (both proj.ini `network = off`, no PROJ_NETWORK). sf's two GEOS checks
  (union+buffer+area, intersects) fail only because they use the failed transform's output; terra, s2 and the other sf and gdalraster
  checks pass. First thought to be zig-proj's; F11 shows it is the stress env's.
- F10 (V) On kappa, `pixi run build` with its output on the OpenSSH pipe crashed zig's build runner three times (exit 3, "thread aborting
  due to recursive panic", once after 5m41s in flang's lapack dlamch.f, `-j4` too); the same command with output to a file (`> log 2>&1
  < NUL` in a .cmd) passed. A host harness issue, not a build one; hosted CI is not affected.
- F11 (V) F9's cause: the stress env had conda-forge `proj` 9.9.0 and `geos` 3.15.0 on all six platforms (pixi.toml
  `[feature.stress.dependencies]`), although no Windows row uses them (packages.tsv: `proj@linux proj@macos`, `zig-proj@windows`).
  conda-forge proj's activation script (proj-9.9.0-h3767062_1 `etc/conda/activate.d/proj4-activate.sh`) sets
  `PROJ_DATA=<env>/Library/share/proj` and, as proj-data is not installed, `PROJ_NETWORK=ON`. zig-proj is built without curl, so PROJ
  chose the CDN grid operation and failed ("Network functionality not available") instead of falling back. kappa's F8 check looked
  only at user and machine variables, not the pixi-activated env. libs' r-consumer env has no conda-forge proj and passes the same
  checks with the same zig-proj build (libs run 45603825536). sf's own data is zig-proj's (sf.log: `cp -r <env>/Library/zig-libs/
  x86_64-windows-gnu/share/proj ../inst/`). Fix (D7): geos and proj move to `[feature.stress.target.unix.dependencies]`; lock
  87b58a42ca62 -> 54e77c422af4, only stress win-64 (geos, proj, sqlite out) and win-arm64 (geos, proj, sqlite, libsqlite out) change.
  Proof is the next Windows stress round's libs smoke (I until then).

- F12 (V) S1 on 21fee4e (stress 45714066676, lock 54e77c422af4): windows-11-arm tree and conda, Rhtslib `lld-link: error: undefined
  symbol: if_nametoindex` (libcurl.a(url.c.obj):(zonefrom_url)), Rsamtools skipped; ok before slice 2 (45548386803). Rhtslib's
  Makevars.win hard-codes Rtools' curl closure (no -liphlpapi) and -lcurl now resolves to zig-libcurl. Owner libs-zig-pixi: zig-libcurl
  build 1 (libs D128, curl's HAVE_IF_NAMETOINDEX=0; it loads if_nametoindex from iphlpapi.dll at run time), win-64 zig_38b206d_1,
  win-arm64 zig_12f6e5a_1, pending publish; then relock and rerun windows-11-arm. The libs smoke is 21/21 on all six Windows legs of
  45714066676 and 45714071892 (F11's fix holds). S3 (45714071892, `rtools_libs=false`): 166 ok; only Rhtslib (regex.h) and Rsamtools
  still need the tree, so F4's nanoarrow (lz4) no longer does.
- F13 (V) zig-libcurl build 1 on universe (libs run 45834790796, main eee907d; libcurl.pc Libs without -liphlpapi). Relock
  `pixi update -e stress -p win-64 -p win-arm64 zig-libcurl`: pixi.lock 54e77c422af4 -> cf4b3220532c, only zig-libcurl
  zig_38b206d_0 -> _1 (stress win-64) and zig_12f6e5a_0 -> _1 (stress win-arm64). Check: S1-style windows-11-arm stress,
  Rhtslib and Rsamtools rows.

## Tests

| host | command | result |
|---|---|---|
| delta | `pixi lock`, then `pixi update --no-install -e stress -p win-64 -p win-arm64 zig-zlib zig-sqlite zig-expat zig-openssl zig-abseil zig-onetbb zig-geos zig-proj zig-gdal` | pixi.lock befa3d7cd247 -> 87b58a42ca62; per-env diff: only stress win-64 and win-arm64 changed (F5) |
| gamma | packages.tsv parsed as stress.R does (read.delim, `on_os`) | 46 rows, 10 fields each; Windows sysdeps: the 24 zig-* names, libboost-headers, and the unchanged conda names |
| kappa | ssh, 12:20 to 13:00 EST | unreachable (F7) |
| kappa | f243dc7: `pixi run --locked build -- --verbose`, `pixi run --locked toolchain`, `pixi run --locked -e stress stress --libs-smoke=main <F8 targets>` (56 min, scratch dir deleted) | 92/92 ok (F8); libs smoke exit 1 (F9); build runner crash on the ssh pipe (F10) |
| delta | `pixi update -e stress -p win-64 -p win-arm64 zig-libcurl`, `pixi lock --check` | 54e77c422af4 -> cf4b3220532c, 2 packages changed, check ok (F13) |
| gamma | stress 45548386803 artifacts (windows-latest tree, windows-11-arm tree) | F1, F2, F3 |
| delta | `pixi lock --check` (pixi 0.84.2); `Rscript stress/stress.R --sysdeps all` (R 4.6.2 zig build); per-env package sets of pixi.lock vs HEAD | lock up to date (87b58a42ca62); rc 0, 46 rows; only stress win-64 (42 out, 35 in) and win-arm64 (9 out, 35 in) differ, the nine slice-1 build 0 -> 1 swaps included; linux and macos sysdeps of every row unchanged |

## Not covered

- win-64 with this lock: tree only, on kappa (F8); the conda distribution and every other row need the S1 dispatch.
- windows-11-arm: no run with slice 2 here (no arm64 Windows host); its expects rest on the libs r-consumer job (D5). F4's list needs
  a stress dispatch with `rtools_libs=false` before build 14 retires `R_ZIG_FALLBACK_SOFT`.
- The conda distribution (`--conda`) on either Windows arch with the new sysdeps.
- Upstream (PyPI ziglang) zig.
