# feat-zig-libs — libs-zig-pixi's zig-* libraries in r-zig (M4)

Branch feat-zig-libs, from main e1835b4 (one LICENSE commit after
f951022, the merge of #50). Worktree
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/wt/feat-zig-libs.
Scratch root: /data/gamma/luciorq/workspaces/temp/r-zig-pixi/m4
(impl: implementation; kappa: the win-64 test; review: the review;
fix: the review fixes).

Status (2026-11-22): implemented, tested natively on kappa (win-64),
reviewed, review fixes applied, uncommitted. No CI run yet. The kappa
run predates the review fixes (see "What changed after kappa").

Recipe build number: unchanged at 12 (main's unreleased number;
universe's newest is `_11`). pixi.lock: unchanged. pixi.toml: unchanged.

## Goal

Milestone M4 of libs-zig-pixi (its `.github/devdocs/DESIGN.md`, section
7 "Consumer integration in r-zig-pixi", and the M4 row of section 9.2):
r-zig compiles R packages on Windows against libs-zig-pixi's `zig-*`
conda packages, static C and C++ libraries built with zig and libc++ in
`<env>/Library/zig-libs/<triple>` (`x86_64-windows-gnu`,
`aarch64-windows-gnu`).

M4 exit criteria (DESIGN 9.2): sf, terra, gdalraster and s2 install and
pass a smoke test on both arches with conda-forge zig, and in the gated
leg with upstream ziglang; a multi-threaded terra call; stress rows ok;
link logs show `lib<n>.a`.

The packages are not published yet (M5). Until then they come from the
artifacts of libs-zig-pixi CI run 44984149674 (`channel-<subdir>-<leg>`,
expires 2026-12-06), used as a local channel (DESIGN 7, item 6).

## Scope

In:

- rzig (`zigbuild/tools/rzig`): each environment's zig-libs before it
  (DESIGN 7, item 1); an RZIG_TRACE line per `-l` naming the file it
  resolves to.
- `build.zig` `rcmdEnviron`: `R_ZIG_LIBS`, zig-libs' `.pc` first on
  `PKG_CONFIG_PATH`, `PKG_CONFIG_LIBDIR` and `R_TOOLS_SOFT` defaults
  (item 2). `cmakeToolchain`: zig-libs on `CMAKE_PREFIX_PATH` (item 3,
  changed after the review, decision ZL11).
- stress: `--libs-channel`, `R_TOOLS_SOFT` and `.pc` order (item 4),
  packages.tsv rows for s2, sf, terra, gdalraster and lwgeom (item 5),
  the zig-libs report column (item 8), stress.yaml inputs `libs_run_id`
  and `libs_leg`.
- `CXX-STDLIB.md`: the "Ruled out" amendment (item 7).
- `scripts/verify-tree.sh` and `scripts/verify-bundle.sh`: checks of
  the new Rcmd_environ and r-zig.cmake lines.

Out: publishing (M5) and the pixi.toml/lock changes it brings; an rzig
`pkg-config` mode (D10, later); retiring `R_ZIG_FALLBACK_SOFT` (DESIGN
7, later slice); linux and macOS (D5).

## Decisions

All dated 2026-11-22 unless stated. "user" cites the user's decision in
libs-zig-pixi DESIGN 10 (accepted 2026-11-20). Choices made while
implementing are "default (user may revisit)".

User, 2026-11-22 ("Follow with all recommended"): every ★ of the first
round's menu accepted: ZL19 (a) with the secret `LIBS_ZIG_PIXI_TOKEN`
(the user creates it); the R smoke script as libs-zig-pixi
`tests/r/smoke.R` (its DESIGN D81); ZL11 `CMAKE_PREFIX_PATH`, with
libs-zig-pixi DESIGN 7 item 3 updated (its D80); every other default
below as recorded; the CI dispatch of Next steps 3.

| # | Question | Options | Choice | Reason | Who |
|---|---|---|---|---|---|
| ZL1 | Where the libraries live | (a) libs-zig-pixi, r-zig a consumer; (b) inside r-zig | (a) | U1 | user (DESIGN U1, 2026-11-20) |
| ZL2 | Install layout | (a) `<env>/Library/zig-libs/<triple>`, found by rzig; (b) conda-forge paths; (c) `LOCAL_SOFT` only | (a) | D2: no clash with conda-forge, arches side by side | user (D2) |
| ZL3 | pkg-config search path | (a) Rcmd_environ lines now; (b) an rzig `pkg-config` mode now | (a) | D10: least rzig work before M4 | user (D10) |
| ZL4 | Zigs | conda-forge zig for packages, upstream ziglang as the gated reference leg | as D11 | D11; rzig.exe from both zigs is byte-identical (finding 6) | user (D11) |
| ZL5 | `PKG_CONFIG_PATH` prepend | (a) zig-libs' `.pc` only in the unset default; (b) always first | (b) | pixi's activation and stress.R set `PKG_CONFIG_PATH`, so (a) would never apply under pixi (finding 12 shows the activation entry). Side effect: a nested R CMD prepends again, which only repeats a search | default (user may revisit) |
| ZL6 | `PKG_CONFIG_LIBDIR` line | (a) DESIGN's `${PKG_CONFIG_LIBDIR-${R_ZIG_LIBS}/lib/pkgconfig;…}`; (b) a helper `R_ZIG_PKG_CONFIG_LIBDIR` and `${PKG_CONFIG_LIBDIR-${R_ZIG_PKG_CONFIG_LIBDIR}}` | (b) | Renviron.c expands a default only when it is one whole `${…}` term; (a) stays unexpanded (finding 1) | default (user may revisit) |
| ZL7 | `PKG_CONFIG_LIBDIR` content | (a) zig-libs' `.pc` only; (b) zig-libs', then the env's `lib/pkgconfig` and `share/pkgconfig` | (b) | a package that replaces `PKG_CONFIG_PATH` (s2, finding 2) still finds the env's `.pc` files | default (user may revisit) |
| ZL8 | `R_TOOLS_SOFT` default | (a) zig-libs whether or not it exists; (b) only when it exists (needs code, Renviron cannot test) | (a) | Makeconf.win's `R_TOOLS_SOFT ?= $(LOCAL_SOFT)` was empty before; the surveyed users do not break on a missing directory (finding 3) | default (user may revisit) |
| ZL9 | rzig zig-libs on unix | (a) Windows only; (b) every OS | (a) | the packages are Windows-only (D5); unix rzig behaviour unchanged by construction | default (user may revisit) |
| ZL10 | Report column's "-l into the fallback tree" | (a) rzig `lib -l<n> <file>` trace lines, parsed by stress.R; (b) parse the link command | (a) | rzig knows the `-L` order it built; a trace line does not change arguments. Without `--trace` the column says "-l: no trace" | default (user may revisit) |
| ZL11 | CMake prefix variable for zig-libs | (a) `CMAKE_SYSTEM_PREFIX_PATH` (DESIGN 7, item 3); (b) `CMAKE_PREFIX_PATH`; (c) (a) plus a docs note | (b), changed after the review | `find_package` (every host) and, on Windows, `find_library`/`find_path` search PATH's prefixes before `CMAKE_SYSTEM_PREFIX_PATH`, so a conda-forge config under `<env>/Library` (PATH has `Library/bin`) would win over zig-libs; zig-abseil, zig-geos, zig-onetbb and zig-expat ship CMake configs (slice-1 D67). `list(APPEND)` keeps a package's `-DCMAKE_PREFIX_PATH` first (finding 14) | default (user may revisit) |
| ZL12 | Expect when zig-* sysdeps are missing | (a) keep `windows=ok` and show (!); (b) report `?` for a target whose zig-* sysdeps (its row's or its dependencies') are missing and not served by the Rtools tree | (b) | before M5 every tree leg and every conda leg without `--libs-channel` would show (!) on 5 rows | default (user may revisit) |
| ZL13 | Rtools tree as stand-in for zig-* | (a) map zig-gdal, zig-geos, zig-proj, zig-onetbb to the tree's libs; (b) also zig-abseil; (c) none | (a) | stress 44450918935: terra and gdalraster ok from the tree on windows-11-arm; s2's make-time pkg-config never found the tree's `absl_base` | default (user may revisit) |
| ZL14 | Rtools tree when zig-gdal is present | (a) DESIGN 7 item 4: only when zig-gdal is absent; (b) still used, after zig-libs | (b) | nlopt, gsl, hdf5, netcdf and others still come only from it on win-arm64; order zig-libs, tree, env makes zig-libs win | default (user may revisit) |
| ZL15 | lwgeom row (not in DESIGN 7) | (a) leave; (b) `zig-geos@windows zig-proj@windows`, `windows=ok` | (b) | it follows sf (LinkingTo); not run (Not verified) | default (user may revisit) |
| ZL16 | `windows-aarch64=` keys | (a) keep per-arch keys; (b) fold into `windows=ok` | (b) | the expected result is ok on both arches (DESIGN 7 item 5 asks for a key only where arches differ) | default (user may revisit) |
| ZL17 | `--libs-channel` form | (a) a `file://` URL; (b) a directory, normalized like `--conda=DIR`, or a URL | (b) | CI passes the relative `build/libs-channel`; a Windows backslash path through pixi's task shell is a risk | default (user may revisit) |
| ZL18 | stress.yaml artifact step | (a) Windows conda legs only; (b) also tree legs | (a) | the tree leg's libraries env is the locked stress env, which has no zig-* until M5 | default (user may revisit) |
| ZL19 | Token for the cross-repo artifact download | (a) secret `LIBS_ZIG_PIXI_TOKEN`, fallback the run's token; (b) the secret only, a missing one fails; (c) the run's token only | (a), `actions: read` dropped, comment and README corrected after the review | an unauthenticated download is a 401 (finding 15); whether the run's token can read another repo's artifacts is not tested. Needs the user: create the secret (menu item A) | default (user may revisit) |
| ZL20 | pixi.toml | (a) unchanged; (b) a feature with the artifact channel | (a) | stress.R `--conda` writes its own workspace from the channels, the `pixi exec` equivalent DESIGN 7 item 6 asks for; no lock change before M5 | default (user may revisit) |
| ZL21 | zig-libs report column on unix | (a) on every OS; (b) Windows only | (b), after the review | the zig-* packages are Windows'; unix report.md keeps its format (finding 17) | default (user may revisit) |
| ZL22 | How kappa tested the branch | (a) rebuild r-zig from the worktree; (b) universe's r-zig-slim `_11` with the new rzig.exe and the new Rcmd_environ lines edited into the installed file | (b) | the R build is unchanged by this branch except those two files; editing the file tests the real lines | default (user may revisit) |
| ZL23 | Smoke expressions | (a) keep packages.tsv's one-line smokes, run a richer smoke separately; (b) richer smokes in packages.tsv now | (a) | the kappa smoke (scratch `kappa/logs/smoke.R`) is the candidate for DESIGN 9.2's `tests/r/smoke.R` (menu item B) | default (user may revisit) |
| ZL24 | Build number | no bump | — | recipe at 12, universe newest `_11`; one release at the end of the backlog | user (2026-11-12) |

## Findings

All on gamma (linux-64) unless the line says kappa (Windows 11 x64,
win-64), 2026-11-22. V = checked, I = inferred. "zig" = both
conda-forge zig 0.17.1 and upstream ziglang 0.17.1 unless stated.

### Implementation and review

1. V. Renviron.c (`subterm`) expands `${VAR-default}` only when the
   default is one whole `${…}` term: `${PKG_CONFIG_LIBDIR-${R_ZIG_LIBS}/lib/pkgconfig}`
   stays literal. Run through R's own `readRenviron` in scratch
   impl/renviron: unset gives zig-libs' `.pc` first, the
   `PKG_CONFIG_LIBDIR` default and `R_TOOLS_SOFT` = zig-libs; values the
   user set (backslashes too) are kept after the prepend; an empty
   `PKG_CONFIG_PATH` gives `<zl>/lib/pkgconfig;`.
2. V. s2's `Makevars.win` runs
   `PKG_CONFIG_PATH="$(CURDIR)/../tools/pkgconfig" pkgconf absl_s2 --libs`,
   so only `PKG_CONFIG_LIBDIR` reaches zig-abseil's `absl_*.pc`.
3. V. Makeconf.win has `R_TOOLS_SOFT ?= $(LOCAL_SOFT)`, so the
   environment's value wins. In the cached sources surveyed, the users
   of `R_TOOLS_SOFT` (nloptr's `-I…/include/nlopt`, igraph's and ncdf4's
   non-pkg-config branches) do not break on a missing directory.
4. V. r-zig's Windows R_HOME is `<env>/Library/lib/R`, so
   `${R_HOME}/../../zig-libs/<triple>` is `<env>/Library/zig-libs/<triple>`,
   where the recipes install and where `r-zig.cmake` reaches through
   `CMAKE_CURRENT_LIST_DIR/../../..`.
5. V. rzig unit tests pass with both zigs (Tests).
6. V. rzig.exe cross-built for x86_64- and aarch64-windows-gnu is
   byte-identical between conda-forge zig and upstream ziglang (Tests).
7. V. `cmakeToolchain` output for linux and macOS (both arches) is
   unchanged; only the Windows files gained the zig-libs blocks
   (scratch impl/cmake-diff, fix/cmake-diff).

### kappa win-64 run (2026-11-22, before the review fixes)

Env: kappa's pixi 0.84.2, workspace written as stress.R `--conda`
writes it; channels `file:///C:/Users/admin/rz-m4/ch-win-64`
(artifact `channel-win-64-default` of run 44984149674, downloaded with
gh), `https://prefix.dev/universe`, `conda-forge`. Resolved: r-zig-slim
4.6.2 hc365614_11, r-zig-toolchain h7cdf2a3_11 (universe), zig 0.17.1
(conda-forge), flang-zig, lld-zig, llvm-openmp 23.1.5 (universe);
zig-abseil 20250127.0 zig_2e57825_0, zig-expat 2.7.3 zig_7fcb7fd_0,
zig-gdal 3.12.1 zig_d646007_0, zig-geos 3.14.1 zig_573ba6a_0,
zig-onetbb 2022.2.0 zig_d03d386_0, zig-openssl 3.6.0 zig_436c1ea_0,
zig-proj 9.7.1 zig_4f71b06_0, zig-sqlite 3.51.2 zig_1d5992e_0,
zig-zlib 1.3.1 zig_29ef852_0. rzig.exe sha256 2e2a58a3… in place of
all 16 toolchain names plus `cfguard.o`; the 13 new Rcmd_environ lines
edited into the installed file (CRLF kept); r-zig.cmake replaced with
the then-current Windows x86_64 output. Command:
`stress.R --conda=universe --libs-channel=C:/Users/admin/rz-m4/ch-win-64 --trace sf terra gdalraster s2`
at jobs 8, 11.4 min. Logs: scratch kappa/logs (run/report.md,
report.json, per-package install and smoke logs, phase1-6 logs).
`C:\Users\admin\rz-m4` was deleted afterwards (`Test-Path` False).

8. V (kappa). s2 1.1.13: install ok, 2.07 min. All 68 `-labsl_*` trace
   lines resolve to `<env>/Library/zig-libs/x86_64-windows-gnu/lib/libabsl_*.a`;
   `-lssl`, `-lcrypto`, `-lz` to zig-libs' `libssl.a`, `libcrypto.a`,
   `libz.a`. conda-forge openssl 3.6.5 is in the env but was not used.
   Smoke ok: s2_area, s2_union, s2_buffer_cells, s2_intersects +
   s2_distance, `s2_union_agg` of France, Germany and Belgium. Its
   configure.win prints "Using Abseil from RTools via pkg-config": a
   hard-coded message.
9. V (kappa). sf 1.1-3: install ok, 0.87 min. Link line
   `-L<env>/Library/lib/R/../../zig-libs/x86_64-windows-gnu/lib -lgdal … -lgeos_c -lgeos -lproj -lc++ … -lsqlite3`;
   each `-l` resolves to that directory's `lib<n>.a` (gdal, expat, z,
   geos_c, geos, proj, sqlite3). `cp -r …/zig-libs/x86_64-windows-gnu/share/{gdal,proj}`.
   `sf_extSoftVersion()`: GEOS 3.14.1, GDAL 3.12.1, PROJ 9.7.1. Smoke
   ok: read nc.shp (100 rows), write and read back a GPKG, read the
   bundled nc.gpkg, st_transform 4267→32119 and 4326→3857, GEOS
   union+buffer+area and intersects, s2 area.
10. V (kappa). terra 1.9-60: install ok, 2.44 min. The same `-l` set
    plus `lib -ltbb12 …/zig-libs/x86_64-windows-gnu/lib/libtbb12.a`.
    Smoke ok: read elev.tif, project to EPSG:3857, read lux.shp.
    `.have_TBB()` TRUE. `focal(2000×2000, 9×9, fun="median")`: serial
    5.82 s elapsed; `terraOptions(parallel=TRUE, threads=4)` 1.68 s
    elapsed, 6.04 s CPU, CPU/elapsed 3.60; result equal to serial.
    `app(cores=2)` ok.
11. V (kappa). gdalraster 2.7.0: install ok, 0.75 min. Every `-l` for
    gdal, proj, geos_c, geos, sqlite3, expat and z resolves to
    `zig-libs/x86_64-windows-gnu/lib/lib<n>.a`. `gdal_version()`
    3.12.1; `GDALRaster$new(storml_elev.tif)$dim()` 143 107 1;
    srs_to_wkt and transform_xy work; more than 100 drivers.
12. V (kappa). Stress report: "Targets: 4 ok. Unexpected (!): 0.
    Dependencies: 17 ok"; zig-libs column "from the fallback tree: none"
    on all four rows. Under `R CMD`, `PKG_CONFIG_PATH` was
    `<zig-libs>/lib/pkgconfig;<env>\Library\lib\pkgconfig;` (the second
    entry from pixi's activation); `PKG_CONFIG_LIBDIR` and
    `R_TOOLS_SOFT` as designed. pkgconf 3.0.11 from the toolchain's
    usr/bin. `objdump -p`: sf.dll, terra.dll and gdalraster.dll import
    only R.dll, the api-ms-win-crt DLLs, KERNEL32, SHELL32, WS2_32 and
    ADVAPI32; s2.dll also dbghelp, USER32, CRYPT32; none a gdal, proj,
    geos, tbb, abseil, ssl or zlib DLL. `-l` with no file in any `-L`
    directory (trace `(none)`): c++ (zig supplies libc++), ws2_32,
    psapi, ole32, shell32, m, advapi32 and similar system libraries.
13. V (kappa). Two smoke pitfalls, not defects of this branch:
    `terra::libVersion("TBB")` returns a data.frame, never TRUE (terra
    1.9-60 `R/gdal.R:81` lowercases `lib`, then compares it to "TBB");
    use `.have_TBB()` and `libVersion("all")`. `focal` with `fun="sum"`
    or `"max"` takes fast paths with no parallel speed-up (max: CPU/elapsed
    1.06); use `"median"` to show threads.

### Review fixes

14. V on linux for `find_package`, I (CMake's documented order) for
    Windows `find_library`/`find_path`. CMake searches the prefixes PATH
    gives (`<prefix>/bin` → `<prefix>`) before `CMAKE_SYSTEM_PREFIX_PATH`.
    Test (scratch fix/cmake-order, CMake 3.31.8): a `fooConfig.cmake`
    under a PATH prefix and one under a `CMAKE_SYSTEM_PREFIX_PATH` entry:
    `find_package(foo CONFIG)` takes the PATH one; with
    `CMAKE_PREFIX_PATH` it takes the zig-libs one. The rendered win-64
    `r-zig.cmake` (fix/cmake-tc), PATH prefix and env's `Library` both
    with a config: no zig-libs → PATH's; own zig-libs → own zig-libs;
    plus `R_ZIG_EXTRA_ENV` → own zig-libs (own before extra on the
    list); extra only → extra's zig-libs; a `-DCMAKE_PREFIX_PATH=<user>`
    → the user's, zig-libs after it. Latent: no current Windows stress
    row uses CMake for these (kappa: s2 took pkg-config). Fixed: ZL11.
15. V. Downloading a libs-zig-pixi artifact zip without a token returns
    401; r-zig-pixi has no repository secrets (`gh secret list`); the
    `actions: read` permission applies only to r-zig-pixi. I: whether
    the run's own token can read another public repo's artifacts.
    Fixed: comment, `actions: read` dropped, README documents
    `LIBS_ZIG_PIXI_TOKEN` (ZL19).
16. V. verify-tree.sh checked only R's own zig-libs line of
    `r-zig.cmake`; verify-bundle.sh's `pcpath.R` checked only
    `PKG_CONFIG_PATH`. Fixed: `pcpath.R` checks `PKG_CONFIG_PATH`,
    `PKG_CONFIG_LIBDIR` and `R_TOOLS_SOFT`, unset and user-set;
    verify-tree.sh checks both zig-libs lines and that R's own env's
    comes first. Not run on Windows (Not verified).
17. V. The report's zig-libs column was added on every OS. Fixed: on
    Windows only; the unix table is byte-for-byte the old format
    (scratch fix/col.R).

### PR #51 CI (2026-11-22)

18. V. build-r run 45039724911 (head 0e36490): `conda-package / win-64`
    and `/ win-arm64` failed in the r-zig-build-tools package test,
    `recipe/test-build-tools.R:153-157`, which still wanted the old
    `PKG_CONFIG_PATH` (`R_HOME/../../lib/pkgconfig;…/share/pkgconfig`):
    `Error: PKG_CONFIG_PATH is '…/Library/lib/R/../../zig-libs/x86_64-windows-gnu/lib/pkgconfig;…/lib/pkgconfig;…/share/pkgconfig', not …`
    (win-arm64 the same with `aarch64-windows-gnu`, which confirms the
    triple). The new value is the intended one (ZL5); the test was
    missed, since the first round ran rzig's tests and the verify
    scripts but not the recipe's R tests. Fixed: the test wants zig-libs'
    `.pc` directory first and also checks the `PKG_CONFIG_LIBDIR` and
    `R_TOOLS_SOFT` defaults, with all three unset, as verify-bundle.sh's
    pcpath.R. Only parsed locally (it runs in the Windows package test).
    The stress dispatches 45039934825 and 45039937348 build the same
    packages (`channel=local`) and stop there too.

## What changed after kappa

- `r-zig.cmake`: zig-libs on `CMAKE_PREFIX_PATH` instead of
  `CMAKE_SYSTEM_PREFIX_PATH` (ZL11). kappa ran the older file, but no
  row used CMake, so its results do not depend on it.
- stress.R report: the column is Windows-only; on Windows the output is
  the same as kappa's.
- stress.yaml, README, packages.tsv notes, verify-tree.sh,
  verify-bundle.sh: not exercised by kappa.
- rzig and Rcmd_environ: unchanged since kappa; the rebuilt rzig.exe
  hashes are in Tests.

## Results

| package | win-64 (kappa, conda-forge zig, default leg) | win-arm64 | upstream-zig leg |
|---|---|---|---|
| s2 1.1.13 | V ok, smoke ok (finding 8) | pending CI | pending CI |
| sf 1.1-3 | V ok, smoke ok (finding 9) | pending CI | pending CI |
| terra 1.9-60 | V ok, smoke ok, TBB threads (finding 10) | pending CI | pending CI |
| gdalraster 2.7.0 | V ok, smoke ok (finding 11) | pending CI | pending CI |
| lwgeom | not run | pending CI | pending CI |

## Tests

gamma, 2026-11-22, after the review fixes (scratch fix/checks.log):

- `zig fmt --check build.zig zigbuild/tools/rzig/{environment,windows,main,compiler}.zig`: rc 0.
- `bash zigbuild/tools/rzig/test.sh`, conda-forge zig 0.17.1: rc 0,
  "226/226 tests passed"; parity "109 identical, 77 identical but for
  …, 33 deliberate differences, 0 failed"; link-objects-test all ok.
  With `ZIG_BIN=<ziglang 0.17.1>`: the same counts, rc 0.
- Cross builds of rzig (`-Dtarget=<x86_64|aarch64>-windows-gnu
  -Dr-version=4.6.2`) with both zigs: rc 0 each. rzig.exe sha256
  2e2a58a3… (x86_64) and e912c92a… (aarch64), identical between the
  zigs and to the implementation's (and so kappa's) x86_64 binary.
- The repo's build.zig compiles: `zig build --help` reaches its
  configure step, which stops at run time with `MissingRSource` (no R
  source in the worktree).
- `Rscript -e 'parse("stress/stress.R")'`: ok. `bash -n` on
  verify-tree.sh and verify-bundle.sh: ok. stress.yaml through
  `yaml.safe_load`: ok. packages.tsv: 10 fields on every data row.
- The new verify-tree.sh `r-zig.cmake` checks run by hand against the
  rendered win-64 file: both lines present, order ok.

Not run: verify-tree.sh and verify-bundle.sh themselves (they need a
Windows tree), actionlint (not installed), any CI, any stress run after
the fixes.

## Not verified

- win-arm64 with zig-* packages, and the upstream-zig leg
  (`channel-*-upstream-zig`) on either arch.
- A full Windows stress run: zig-libs now comes first for every row, so
  `-lz`, `-lssl`/`-lcrypto`, `-lexpat` and `-lsqlite3` bind the zig-*
  archives instead of conda's import libraries in every package; seen
  only in the 21 packages of the kappa run (V there).
- A CMake consumer of zig-libs on Windows (abseil, GEOS, TBB, expat
  configs), and `find_library` on Windows with the new
  `CMAKE_PREFIX_PATH` lines.
- The stress.yaml artifact step, with or without `LIBS_ZIG_PIXI_TOKEN`.
- The tree leg with zig-libs; lwgeom.
- verify-tree.sh and verify-bundle.sh with the new checks; an R built
  from this branch.
- libs-zig-pixi's `tests/r/smoke.R` (D81 there, made from kappa's
  smoke.R and smoke-terra.R): only parsed, and its check helper run on
  base R; never run against the packages. kappa ran the two scratch
  scripts it comes from.

## Next steps

1. Commit and open the PR (the user).
2. Add `LIBS_ZIG_PIXI_TOKEN` (fine-grained, Actions read on
   luciorq/libs-zig-pixi) as an r-zig-pixi secret (the user, ZL19).
3. CI: `gh workflow run stress.yaml -R luciorq/r-zig-pixi --ref feat-zig-libs -f oses='["windows-latest","windows-11-arm"]' -f packages='s2 sf terra gdalraster lwgeom' -f distribution=conda -f channel=local -f libs_run_id=44984149674 -f trace=true`,
   then the same with `-f zig=upstream -f libs_leg=upstream-zig`; read
   every row of both reports. `channel=local`, not `universe`: the
   published r-zig (build 11) has neither the zig-libs rzig nor the new
   Rcmd_environ lines, so a universe leg would not test this branch. Then the full Windows stress set with `libs_run_id`
   (the side effect in Not verified). The artifacts expire 2026-12-06.
4. The upstream-zig gated leg of build-r (label `upstream-zig`) and
   `full-ci` on the PR.
5. M5 (libs-zig-pixi): publish build 0 to universe; then r-zig-pixi
   takes the zig-* packages from universe (pixi.toml, lock), drops
   `--libs-channel` from CI, and the stress column shows the
   published builds.
