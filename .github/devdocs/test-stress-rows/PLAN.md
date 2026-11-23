# test-stress-rows

## Goal

Bring stress rows (notes, expects, sysdeps) in line with stress 45219870330 (Windows, zig-* from universe) and 44438790229 (linux). Stop
stress runs from leaving `.zig-cache` in the checkout, and give the Windows tree CRAN's R_HOME/include set.

## Decisions

| # | question | chosen | reason |
|---|---|---|---|
| D1 | lwgeom linux expect: no linux run of lwgeom since sf turned ok | `ok` (the bare value; was `linux=fail-dependency macos=ok windows=ok`) | its only blocker, sf, is ok on all four linux legs of 44438790229; expects are guesses until a run (packages.tsv header); CI5 confirms |
| D2 | RPostgres sysdeps: K1's `libpq libboost-headers@windows lz4-c@windows` | keep `libpq`, note why | evidence F5/F6: neither boost nor lz4 is reached on Windows with RPostgres 1.4.10 |
| D3 | Q17 fix: where zig cc's local cache goes | `ZIG_LOCAL_CACHE_DIR` = the run's `zig-cache` (same as the global one) | zig cc's local cache is the global one on a user's machine (no build.zig above); the run directory is in the checkout, below r-zig's build.zig. Cost: tier 2's zig build cache is the run's, not one per build root (pkgbuild.zig's comment already said stress.R did this). Rejected: deleting the root `.zig-cache` at the end (would delete a concurrent build's), a sentinel build.zig in the run dir (trickery), moving TMPDIR out of the checkout (CI disk layout risk) |
| D4 | M-2 tree half (bin/Rscript) | nothing to change | already done: build.zig installs winRfe as R_HOME/bin/R.exe and bin/Rscript.exe (fix-stress-round1 S14, 117e4cb, 2026-10-09) |
| D5 | H2 headers | follow src/include/Makefile.win: add iconv.h (gnuwin32/fixed/h), graphapp.h and ga.h (extra/graphapp); drop Rinterface.h | CRAN's install rule; Makefile.win: "deliberately does not include Rinterfaces.h, which is Unix-only". R_ext/ left as is (Makefile.win also omits GetX11Image.h, QuartzDevice.h, eventloop.h; not in H2) |
| D6 | M-6 arrow macos-x86_64 | deferred | the env column has no per-OS form; ARROW_S3=OFF or ARROW_SIMD_LEVEL on the whole row would change linux and macos-arm64 coverage; needs macos-15-intel to verify |

## Findings

- F1 (V) lwgeom is not in 44438790229 (20 targets: `grep -l lwgeom -r` over its four artifacts: none); sf, terra, gdalraster ok on
  linux-64 and linux-aarch64, tree and conda (report.md rows).
- F2 (V) hdf5r windows-latest tree and conda (45219870330): `1_12_0/Wrapper_auto_H5P.c:1525:71: ... passing 'off_t *' (aka 'long *')
  to parameter of type 'HDoff_t *' (aka 'long long *')`; env hdf5 2.2.0 (conda/pixi.lock). windows-11-arm legs ok.
- F3 (V) igraph windows-latest tree and conda: first error `libxml/globals.h' file not found`. Cause: igraph 2.3.4 Makevars.ucrt runs
  `pkg-config --cflags libxml-2.0 glpk` as one call; glpk has no .pc (log: "Package 'glpk' not found"), so PKG_CPPFLAGS gets no
  include/libxml2. libxml2-devel 2.15.4 (win-64 and linux-64 packages, downloaded) does ship libxml/globals.h. Still the glpk.pc
  sysdep; class unchanged.
- F4 (V) rstan's "open point H" was closed by feat-config-rzig (`R CMD config` through `rzig config`, patch 0010;
  feat-standalone-toolchain/TODO.md:1028-1036).
- F5 (V) RPostgres 1.4.10 src/Makevars.win: Rtools branch only when `pkg-config --libs libpq` contains `ldap32`; else downloads the
  r-windows libpq 15.12 bundle and uses `-Ivendor` (vendored boost). conda-forge win-64 libpq 19.0's libpq.pc has wldap32 and lz4.lib
  in Libs.private only (package extracted). 45219870330 windows-latest: `lib -lpq ../windows/libpq/lib/libpq.a`, ssl/crypto from the
  bundle; windows-11-arm: `using libpq from Rtools`, boost from the Rtools45 tree's include-pinned. All four legs ok; neither conda
  leg's pixi.toml has libboost-headers or lz4-c.
- F6 (I) pixi.toml's `[feature.stress.target.win.dependencies] libboost-headers` and its "RPostgres includes Rtools' boost headers"
  comment look stale (F5); not changed here (outside this batch's files).
- F7 (V) zig cc without ZIG_LOCAL_CACHE_DIR makes `.zig-cache` beside the nearest build.zig above its cwd; with it, none (delta,
  zig 0.17.1: `touch build.zig; cd a/b; zig cc -c x.c` gave `<dir>/.zig-cache`; with ZIG_LOCAL_CACHE_DIR set, none).
- F8 (V) M-2: build.zig `for ([_][]const u8{ "R.exe", "Rscript.exe" })` installs winRfe in R_HOME/bin; rstan note round 2 already
  says "installs (S14, S10)".
- F9 (I) H2 risk: R_HOME/include/iconv.h now comes before an env's libiconv iconv.h (-I R_INCLUDE_DIR before rzig's -idirafter). It
  maps iconv_* to libiconv_* (dllimport) and declares only iconv_open, iconv, iconv_close, iconvlist, as on CRAN.

## Tests

- delta: stress.R parses (baseline `~/rz/base/dist/slim/R-4.6.2-zig/bin/Rscript -e parse(...)`); packages.tsv reads as 45 rows x 10
  columns (`awk -F'\t' '{print NF}'`: 45 rows of 10, 31 comment lines, unchanged).
- delta: build.zig compiles and configures with conda-forge zig 0.17.1 and upstream ziglang 0.17.1 (`zig build --help --prefix P
  -Dprefix=P`, CONDA_PREFIX = the base env, R source linked from ~/rz/base): exit 0 with both. The Windows graph itself cannot be
  configured on linux (`-Dtarget` is not an option), so the Windows install list is compile-checked only.
- delta: Q17, tinyjobs (g0) stress run with the baseline tree (`~/rz/base/dist/slim/R-4.6.2-zig`, `--jobs=8`): HEAD's stress.R:
  ok, `.zig-cache` in the checkout root: yes; this stress.R: ok (Targets: 1 ok, Unexpected 0), `.zig-cache` in the root: no,
  `zig-cache` in the run directory.

- review: stress.R reparsed on delta after the review edits (comment-only change).

## Review

- R1 (V, fixed) Q17's acceptance "box ticked" was not met: feat-standalone-toolchain/TODO.md N6 (and K1, Q5's source) were open;
  both ticked with the evidence above.
- R2 (V) spot-checked against 45219870330's artifacts: hdf5r H5P.c:1525 off_t/HDoff_t (windows-latest both legs), igraph
  `libxml/globals.h` + "Package 'glpk' not found", RPostgres `-Ivendor`/`../windows/libpq/lib/libpq.a` (x86_64) and "using libpq
  from Rtools" + include-pinned boost (arm64), all 8 sf/terra/gdalraster/s2/lwgeom cells ok; H2 list matches R-4.6.2
  src/include/Makefile.win:13-34.
- R3 (I, kept) tier 2 in stress no longer exercises the per-root cache default; pkg-parity.sh covers it. iconv.h order (F9) is CRAN's.

## Not verified

- H2 on a Windows tree (no Windows host in this batch; backlog said kappa): headers' presence and a package build against them.
- lwgeom linux `ok` (CI5). M-2's C++-standard half (other batch). M-6 (D6).

## Backlog items closed

Q4, Q5 (K1 proposal rejected, D2), Q17, M-2 tree half (already done, D4), H2 (implemented, Windows check pending). Deferred: M-6.
