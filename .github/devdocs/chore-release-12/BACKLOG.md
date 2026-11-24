# Build 12 backlog (one batched release)

Inventory of 2026-11-23 (main 3395a08): every open item in the records and code, deduplicated and sized. Items are ticked here as batches land.

Source keys: **R** = recent sweep, **O** = older-records sweep, **K** = code sweep. Record paths are relative to `.github/devdocs/` unless they start with another folder. Sizes: S is under 1h, M is half a day, L is several days.

Build 12 is no longer a separate release step. It is the final batch after everything below lands. The publish and the recipe comment (R-B1, K4) are at the end.


## Status

- **Batch 1, PR #54 (branch build12-batch1, 2026-11-23):** five commits,
  records in `.github/devdocs/<batch>/PLAN.md`.
  - docs-backlog-hygiene: Q2, Q3, Q18, Q21, Q22, Q23; M12 checked (fix:
    `license_file` in the recipe, open); decisions D1-D12 (all defaults).
  - fix-rzig-quick: Q1, Q7, Q8, Q9, M-1, Q24, Q25, M-15 (decision);
    M-2 left to the stress row.
  - chore-env-ci: Q10, Q11, Q12, Q13, Q15, Q16, Q19, M-3 (env half),
    M-4, M-5, D10.
  - fix-verify-scripts: Q6, M-8, Q14, M-22; M-21 deferred.
  - test-stress-rows: Q4, Q5, Q17, H2; M-2 tree half was already done;
    M-6 deferred (needs macos-15-intel).
- **Wave 2, PR build12-wave2 (2026-11-23):** five commits, records in
  `.github/devdocs/<topic>/PLAN.md`.
  - wave2-licences: M12 (licence files in every package; `license`
    fields not changed).
  - wave2-build: M-19 (bootstrap skipped when its inputs are unchanged:
    a no-change build 18 s against about 110 s), M-21 (linux host tools
    from the env); M-20 deferred (design in its PLAN.md).
  - wave2-rzig: M-18 (tier-2 `cflags`/`cxxflags`), Q24's `-Xlinker`
    form checked; M-16 closed as won't-do: linux keeps `-I` (wave2-rzig
    W6, user 2026-11-23).
  - wave2-compat: M-12 (Ubuntu 22.04/24.04, Rocky 8: tree and conda ok),
    M-14 (rpy2: base packages now link libR), M-26 (pip, uv); M-13
    deferred: new item M-29 below.
  - wave2-fixes: verify-tree allows SSE4.1 on macOS (flang's penryn
    default; build-r 45275675601); stress/README notes the first r-zig
    build with zig-libs (12).
- **New item M-29 (from M-13):** rzig and distro libraries on linux:
  `/usr/include` and `/usr/lib` as `-idirafter`/last `-L` behind an
  opt-in, and distro `.pc` files' `-I/usr/include/<triple>` kept from
  mixing the host's glibc headers into zig's (`__time64_t`); the C++
  ABI part already works (wave2-compat F-M13).
- **Open after batch 1:** the group 2 CI items (stress on #54), protolite's
  win-arm64 expect once M-3 runs, rstan's `-std=c++1y` (M-2), arrow on
  macos-x86_64 (M-6), licence files in the packages (M12), M-21, host
  items H1-H6, M-7..M-28 not picked, L and WAITS-LIBS groups.

---

## 1. Quick wins (S)

### 1a. Code or records, checked on gamma

Ordered by value.

| # | Item | Sources | Done looks like |
|---|---|---|---|
| Q1 | `zig fmt --check` fails on `zigbuild/rspec.zig:10-34` and `zigbuild/tools/rzig/makefile.zig:115-116` | K1 | fmt applied; clean with both zigs; optionally a CI fmt step |
| Q2 | Record touch-ups: the F6 re-run is done; gamma worktrees C2 are done; the "full tier, upstream-zig not run" lines; close the upstream-zig line with run 44735388684 | R-G1..G4 (R-A12, A13, A1, A2); K7 is resolved | feat-zig-libs-universe/PLAN.md:104,122; feat-winarm-gaps/PLAN.md:16-21,1215; feat-linux-libstdcxx/PLAN.md:947-953 |
| Q3 | Stale open boxes: standalone TODO.md (153-165, 593-625, 659-679, 722-768, 1273, 1286), feat-cross-platform-standardization/PLAN.md:319-333, feat-initial-setup/TODO.md, consolidation/CONSENSUS.md:128-322, chore-lock-and-ci-refresh/PLAN.md:305-327 (N9 wording) | O-G2, O-G3, O-H | Ticked or annotated with evidence |
| Q4 | Out-of-date row notes in packages.tsv: lwgeom `linux=fail-dependency` (L58, cause "not reached: s2"); hdf5r cause is now `off_t`/`HDoff_t` (L43); igraph cause is now `libxml/globals.h` (L50); rstan note still cites "open point H", which is resolved; sf/terra/gdalraster/s2 notes still say "? … before M5" | R-D7, K8, K11, K13, K-D | Notes match stress 45219870330 and 44438790229. The lwgeom expect becomes ok after one linux run |
| Q5 | RPostgres sysdeps are `libpq libboost-headers@windows lz4-c@windows` (packages.tsv:47) | O-D1 (TODO.md:882 K1) | Column updated; the Windows conda row is checked in the stress batch |
| Q6 | verify-tree.sh hard-codes GLIBCXX_3.4.34 | R-E8 (scripts/verify-tree.sh:1200,1226) | Bound derived from the libstdcxx-devel version in conda-meta |
| Q7 | `zig cc -S` warns about an unused `-c` | R-F14 (chore-release-11/PLAN.md:396-398) | rzig drops `-c` with `-S` |
| Q8 | `R_ZIG_PKG_BUILDER=zig` does not refuse a src/Makefile package | O-A8 (fix-zig-pkg-build-review/PLAN.md:519-521) | Clear stop line plus a unit or parity case |
| Q9 | zig-fc's flang-driver still passes `-lgfortran -lquadmath` | O-A9 (fix-rzig-follow-ups/PLAN.md:629) | Dropped from fortran.zig, or the reason recorded |
| Q10 | Six `conda-publish` tasks that differ only in subdir | R-F7 (chore-release-11/PLAN.md:427-428) | One task that takes the subdir |
| Q11 | Remove libgdal-core (MSVC) from the win-64 stress env | R-D2 (feat-zig-libs-universe/PLAN.md:31 D4) | pixi.toml line gone, lock updated (CI check in group 2) |
| Q12 | fontconfig, freetype and expat are in the Windows envs and recipe deps but unused there | O-A16 (feat-win-variants/PLAN.md:307; pixi.toml:314-317,337) | Moved to `target.unix`; re-locked |
| Q13 | Stale BLAS comment at pixi.toml:471. **Conflict:** K2 says `-Dblas=openblas` exists in build.zig:29,275,661, but O-A15 (feat-win-variants/PLAN.md:297) says it is ignored on Windows | K2, O-A15, R-F8 part | Check build.zig's Windows branch. Then fix the comment and either drop win from the openblas envs (S) or move the work to M7 |
| Q14 | pkg-parity `argv_of` does not keep `-F` | O-A7 (fix-zig-pkg-build-review/PLAN.md:515-518; scripts/pkg-parity.sh:167) | `(-[ILF]\|`. The omicron parity run is in group 2 |
| Q15 | Dead `require_not_windows()` | K3 (scripts/env.sh:287-292) | Removed; `bash -n` passes |
| Q16 | actions/cache@v5 not checked against the repo pins | R-C12 (feat-winarm-gaps/PLAN.md:1189) | Pinned like the other actions |
| Q17 | `.zig-cache` left in the checkout root after stress (N6) | O-D8 (TODO.md:894; stress.R:403-410) | One local stress run leaves none; box ticked |
| Q18 | Release rule "never delete `_N` before `_N+1`" belongs in a durable checklist | O-G1 (TODO.md:900; fix-icu-pin/PLAN.md:105-114) | Line in the release checklist |
| Q19 | icu pin lift check (recipe/variants.yaml:48) | O-G4 (TODO.md:870) | `pixi search libxml2-16` result recorded; lifted if built against icu 79 |
| Q20 | Notify flang-pixi about retained lld-zig 5 / flang-zig 6 / flang-rt-zig 10 | O-G5 (chore-relock-flang-rt-10/PLAN.md:127-132) | `conda-channel-list` checked; note sent |
| Q21 | macOS minos of the `_11` osx packages | O-B13 (feat-wheel-minimal/PLAN.md:154) | `llvm-otool -l` shows 13.0 |
| Q22 | Is the wheel toolchain mechanism already settled by the group wheels? | O-B7 (feat-no-host-paths/PLAN.md:2765) | Closed with evidence, or moved to the decision menu |
| Q23 | Document R_ZIG_FALLBACK_SOFT, or record it as stress-only until R-C2 | R-C3 (feat-winarm-gaps/PLAN.md:1197,136-143) | Doc line or a recorded decision |
| Q24 | CMake mixed C/C++ target, libunwind.a; `-Wl,-lstdc++` not rewritten (L21); a prebuilt libc++ archive inside a package | R-E6, R-E7 (feat-linux-libstdcxx/PLAN.md:966,968) | Probes or unit tests recorded |
| Q25 | Which 29 rzig unit tests skip on windows-latest | R-E1 (feat-linux-libstdcxx/PLAN.md:956) | List with reasons; un-skip what can run |
| Q26 | R_TOOLS_SOFT=tree side effects in Makevars (gert, stringi, qs2, fst, Rhdf5lib, V8, duckdb, mlpack, rstan, DESeq2, systemfonts, geos, Rsamtools). M, but source reading only | R-C6 (feat-winarm-gaps/PLAN.md:1161) | Findings per package |

### 1b. One decision menu (no code; ask once, record in PLAN.md)

| # | Decision | Sources |
|---|---|---|
| M1 | Rtools45 x64 tree fallback for hdf5r, gsl, igraph/scran and Rsamtools on win-64 (as on aarch64), or wait for zig-libs | K26, O-F4 |
| M2 | Wheel size: libcurl→libpsl→ICU (14 of 49 MiB). Pin `libcurl <8.21`, use a libpsl without ICU, or accept | R-F5, O-D12 (pixi.toml:490-492) |
| M3 | arrow `heavy@linux`: keep or drop | R-E9, K17 (feat-linux-libstdcxx/PLAN.md:279-286; packages.tsv:65) |
| M4 | L4/L5 libstdc++ headers in the compilers group: confirm or pick L5(b) | R-E10, O-E7 (CXX-STDLIB.md:223-235) |
| M5 | ZL5–ZL23 "user may revisit" defaults | R-D6 (feat-zig-libs/PLAN.md:77-95) |
| M6 | Extras Help/ pages (decision A) and PATH order | R-F12, O-E3 (feat-extras-group/PLAN.md:484) |
| M7 | Release job and PyPI timing ("parity stable" gate); B12 release workflow; reserve the PyPI names | R-F4, O-B2, O-B3 |
| M8 | Base/toolchain package naming (conda + PyPI, v3) | O-B5 |
| M9 | zig cache: pre-seeding, sharing the cache between standalone and conda R, and a zig-binary hash in the key (N7) | O-E2, O-D9 |
| M10 | CI speed menu: compression-level 0, zig/ artifact split, upstream-zig reusing build.yaml's toolchain, the verify-package build pass, R_ZIG_TEST_ZIG_CACHE sharing, dropping check/hermetic from the core legs | O-C1, C2, C3, C4, C6, C7 |
| M11 | Close as won't-do or watch: A5 build root, A6 TMB precompile, A4 `-lmsvcrt`, A10 Windows `-lc++`, B11 installer, B12 manuals, D13 pak README line, E4 WinRT, G8 Falcon, G10 MinGW `-l`, D11 CFG no-op (but see C4 below), F15 BLAS route, F16/E5 r-base, E6 pixi_build_zig | O-A4/A5/A6/A10/B11/B12/D11/D13/E4/E5/E6/G8/G10; R-F15/F16 |
| M12 | Licence completeness of the groups | O-E1 (TODO.md:1142) |

### 1c. S items that need a host

| # | Item | Sources | Host |
|---|---|---|---|
| H1 | macOS `zig cc --version` writes `a.o`; re-check on 0.17 and drop the `-c` workaround (compiler.zig:70-83) | O-A1 | omicron |
| H2 | Windows R_HOME/include parity: iconv.h, graphapp.h, ga.h missing; Rinterface.h extra | O-A14 (feat-win-variants/PLAN.md:299) | kappa |
| H3 | `pkgbuild::has_rtools(debug=TRUE)` with base + compilers only | O-D3 (feat-config-rzig/PLAN.md:248) | kappa |
| H4 | `zig-lib-<n>` showing up in the user's `~/.cache/r-zig` | O-D14 | omicron |
| H5 | Host leftovers (test dirs, gamma runner unit, kappa zig cache, rel11 scratch) | O-G7 | hosts |
| H6 | Watch on each zig update: conda-forge `zig ar` on osx (ar.zig:1-15); zig fetch cache repro (ZIG-FETCH-CACHE.md) | K5, K6, O-G9 | omicron, gamma |

---

## 2. CI runs only (no code)

Run these as one wave after the code batches merge, to keep round trips down. Ordered by value.

| # | Item | Sources | Done looks like |
|---|---|---|---|
| CI1 | Full Windows stress with zig-* from universe: every group, windows-latest and windows-11-arm, tree and conda. Includes the Q5 RPostgres row and the Q11 libgdal-core drop | R-B6, K25, O-F4 | Every non-ok row listed with its cause |
| CI2 | Stress on macOS after #49 (macos-latest, macos-15-intel); this also sets the arrow:source `macos-x86_64=?` expect | R-B5, K18 | 0 unexpected, every row read |
| CI3 | Stress with `zig=upstream` on ubuntu and macos | R-B4 (feat-linux-libstdcxx/PLAN.md:947,958) | Every row read |
| CI4 | windows-11-arm rows outside the 19 targets, with and without `--no-rtools-libs` | R-B7 (feat-winarm-gaps/PLAN.md:1152) | Diff of the row tables |
| CI5 | Targeted linux stress: RcppParallel:system-tbb, mlpack, full and openblas variants; lwgeom expect (Q4) | R-E2 | Rows read |
| CI6 | g1 stress with trace (Rcpp cppFunction, rstan stan_model) through rzig SHLIB | O-D2 (TODO.md:1072) | Log shows `rzig build: R CMD SHLIB, tier 1` |
| CI7 | Run CFG code on win-arm64: the magick SVG smoke. Then O-D11 closes | R-C4, O-D11 | Smoke passes |
| CI8 | Read-only log checks: extractor and time (R-C9); linux-aarch64 cross-link timings (R-C11); feat-r-home-link-objects UNVERIFIED items (O-D10); ICF off on arrow/duckdb DLLs (R-F11) | as listed | Recorded |
| CI9 | build.yaml dispatch with `linux_runner=ubuntu-26.04` | O-C9 (build.yaml:43) | Run read |
| CI10 | pkg-parity run on omicron for Q14 | O-A7 | Green |
| CI11 | win-64 conda-package "Overlinking against" the pkg env's zstd.dll | O-A17 (chore-deps-ci-checks/PLAN.md:359) | Explained or gone |
| CI12 | Host chains: R CMD config from cmd.exe and an R_HOME with a space (O-D4); extras group on macOS/Windows (O-D5); recommended packages on macOS/Windows (O-D6) | as listed | Host runs recorded |
| CI13 | **Final, after publish:** `--conda channel=universe` windows-11-arm leg shows the R_ZIG_FALLBACK_SOFT line as used | R-B2 | Fallback line present |

---

## 3. M code items

Ordered by value.

| # | Item | Sources | Where |
|---|---|---|---|
| M-1 | Rhdf5lib on Windows (both arches): supply `-D__STDC_WANT_IEC_60559_TYPES_EXT__` through rzig windows.zig or Makeconf. Already shown to work | K9 (packages.tsv:56) | kappa + windows-11-arm |
| M-2 | rstan on Windows: the tree needs `bin/Rscript`; C++17 against plugin.R's `-std=c++1y` | K10 (packages.tsv:74) | kappa |
| M-3 | protolite on win-arm64: protoc and headers from one source (tree protoc first on PATH, or drop conda libprotobuf from the win-arm64 stress env) | R-C1, K16, O-F5 | windows-11-arm (cross-build repro on gamma) |
| M-4 | upstream-zig.yaml: add windows-11-arm, plus linux-aarch64/osx-64 legs or a recorded no | R-B3, O-C5 | CI |
| M-5 | `recommended` / `verify-recommended` in build-r.yaml's per-OS chain (full tier) | R-F13, O-C8 | CI |
| M-6 | arrow on macos-x86_64: keep the env's `aws/common/config.h` (AVX-512) out of the bundled aws-checksums build, or use `-mno-avx512` | K17 (chore-release-11 finding 30) | macos-15-intel |
| M-7 | `-Dblas=openblas` on Windows, if Q13 shows it is ignored | R-F8, O-A15 | kappa |
| M-8 | verify-tree baseline-CPU check misses legacy-encoded extensions | O-A11 (fix-rzig-baseline-cpu/PLAN.md:342) | gamma |
| M-9 | CMake consumer of zig-libs on Windows (abseil, GEOS, TBB, expat configs) | R-D1 (feat-zig-libs/PLAN.md:337) | CI-win |
| M-10 | Tree runtime smokes on win-arm64 (C++ exceptions across libc++ versions, libomp, proj.db, HDF5 1.12.1); single copy per library in a trace (sf/terra) | R-C7, R-C8 | CI-win |
| M-11 | /OPT:NOICF native link of clang-aarch64 objects with a broken .llvm_addrsig | R-C5 | CI-win |
| M-12 | Older libstdc++ hosts (Ubuntu 22.04, RHEL 8) | R-E3 | gamma container |
| M-13 | Standalone builds against distro GDAL and Magick++ (22.04/24.04) | R-E11 | gamma container |
| M-14 | rpy2 or another embedder loading an older libstdc++ first | R-E4 | gamma |
| M-15 | cargo and go in a stress feature (gifski, string2path); the Windows Rust `-lunwind` rule (O-A3) | R-E5, O-A3 | gamma + CI |
| M-16 | `-isystem` vs `-I` for env dirs on linux | R-F10 | gamma |
| M-17 | gen-config captures with rzig; remove the 834-line bash shims | R-F6 | gamma + gen-config CI |
| M-18 | Tier-2 `cflags` in rpkg LibraryOptions | O-A2 | gamma |
| M-19 | Content-stamp the bootstrap Run steps (~1.5 min per `zig build`) | O-A13 (feat-zig-build/TODO.md:117) | gamma |
| M-20 | `zig build fetch` to retire fetch-r.sh | O-A12 | gamma + CI |
| M-21 | Host tools on linux (cmp, find, ldd, bash, dirname) | O-A18 | gamma |
| M-22 | Reproducible standalone tar (N9) | O-B4 | gamma |
| M-23 | BLAS link contract for binary packages (forwarding libRblas) | O-B6 | gamma |
| M-24 | win.binary as the default on win-64 (experiment) | R-F9 | CI-win |
| M-25 | B39 restricted-PATH run, then trim the build-tools list | O-D7 | gamma + kappa |
| M-26 | pip upgrade and uv tests for the wheels (S) | O-B15 | gamma |
| M-27 | MSYS make started by Git bash crashes on win-arm64: record as unsupported, optionally repro | R-C10 | CI-win |
| M-28 | macOS without the Command Line Tools (`xcrun` handling) | O-B14 | CI-mac |

---

## 4. L items

Propose leaving these out of build 12 unless chosen in the menu.

| # | Item | Sources |
|---|---|---|
| L1 | Release job: standalone archives, GitHub Release, PyPI (gated by M7) | R-F4, O-B2, O-B3 |
| L2 | Windows wheel (make-wheel.py win-64/arm64 and a wheel-test leg) | O-B1, R-F2 part |
| L3 | One base with add-ons, tcltk first | R-F2, O-B10 |
| L4 | Native Windows build tools without MSYS2 | R-F1 |
| L5 | Binary package repository | R-F3 |
| L6 | Toolchain in its own env (`R_ZIG_TOOLCHAIN_ENV`) | O-B8 |
| L7 | GNU make built with zig | O-B9 |
| L8 | Split pixi.toml `[dependencies]` into features (re-solves every env) | O-E8, R-F8 part |
| L9 | rzig `pkg-config` mode (D10). Design first; leans on WAITS-LIBS | R-D3, O-F1 |

---

## 5. WAITS-LIBS (libs-zig-pixi)

M1 can unblock W3–W6 earlier.

| # | Item | Sources |
|---|---|---|
| W1 | zig-protobuf: protolite win-64 `fail-abi`, and the long-term aarch64 fix | K16, K19 |
| W2 | zig-arrow or a `LIBARROW_BINARY=false` source build: arrow on Windows (win-arm64 downloads an x64 libarrow) | K17, K20 |
| W3 | zig-hdf5: hdf5r win-64 | K11, K21 |
| W4 | zig-gsl: gsl win-64 (the gslcblas MKL import lib) | K12, K22 |
| W5 | zig-libxml2 and zig-glpk: igraph, then scran, on win-64 | K13, K14, K23 |
| W6 | zig-libgnurx and a static curl stack: Rsamtools win-64 | K15, K24 |
| W7 | Retire R_ZIG_FALLBACK_SOFT (needs nlopt, gsl, mpfr, gmp, glpk, hdf5, netcdf, udunits2, harfbuzz, libpq) | R-C2, O-F2 (CXX-STDLIB.md:203-205) |
| W8 | zig-libs on linux and macOS | R-D4, O-F3 |
| W9 | Run libs-zig-pixi's `tests/r/smoke.R` from stress or verify | R-D5 |
| W10 | Close the general Windows C++ ABI item once W1–W6 land | O-F6 |

---

## Work batches (parallel branches, no shared files)

Rule: only one batch edits `pixi.toml`/`pixi.lock`, only one edits `stress/packages.tsv`, and only one edits `.github/workflows/*`. The records under `.github/devdocs/` stay in B1, apart from each batch's own new PLAN.md.

**B1: `docs-backlog-hygiene`** (records only, gamma, about 2h)
- Items: Q2, Q3, Q18, Q22, and writing every 1b menu answer into the records. Plus a new `.github/devdocs/chore-release-12/PLAN.md` holding this backlog.
- Files: `.github/devdocs/{feat-zig-libs-universe,feat-winarm-gaps,feat-linux-libstdcxx,chore-lock-and-ci-refresh,feat-cross-platform-standardization,feat-initial-setup,feat-standalone-toolchain}/…`, `consolidation/CONSENSUS.md`, a release checklist doc, `CXX-STDLIB.md` (Q23 doc line).

**B2: `fix-rzig-quick`** (rzig code, gamma, then kappa/omicron)
- Items: Q1, Q7, Q8, Q9, H1, M-1 (Rhdf5lib define), the M-2 C++-standard half, Q24/Q25 tests, M-15's `-lunwind` decision.
- Files: `zigbuild/rspec.zig`, `zigbuild/tools/rzig/{makefile,compiler,fortran,windows}.zig`, the rzig pkg-builder source or the 0009 patch, the rzig unit tests.

**B3: `chore-env-ci`** (pixi, lock, workflows, gamma lock plus CI)
- Items: Q10, Q11, Q12, Q13 (plus drop win from the openblas envs if that is the outcome), Q15, Q16, Q19, M-3's env half (libprotobuf out of the win-arm64 stress env), M-4, M-5, the M10 menu outcomes.
- Files: `pixi.toml`, `pixi.lock`, `recipe/variants.yaml` (icu, only if lifted), `scripts/env.sh`, `.github/workflows/{upstream-zig,build-r,toolchain,build}.yaml`.

**B4: `fix-verify-scripts`** (scripts, gamma)
- Items: Q6, M-8, Q14, M-21 (optional), M-22 (optional).
- Files: `scripts/verify-tree.sh`, `scripts/pkg-parity.sh`, `scripts/package-standalone.sh`, `scripts/vendor-libs*`.

**B5: `test-stress-rows`** (stress data and tree contents, kappa plus Windows CI)
- Items: Q4, Q5, Q17, the M-2 tree half (`bin/Rscript` in the Windows tree), M-3's PATH-order half (only if B3 does not drop the env package), M-6, M1's x64 fallback if picked, H2 (include parity).
- Files: `stress/packages.tsv`, `stress/*.R`, the Windows install-list section of `build.zig`. B2 does not touch build.zig, so there is no conflict.

**Order:** B1–B5 run in parallel. After they merge, one CI wave runs group 2 (CI1–CI12) against the merged main. Then the release: K4 recipe comment in `recipe/recipe.yaml:235` (wt/chore-release-12), publish-preflight, the build.yaml dispatch (R-B1), and CI13. Groups 4 and 5 stay out of build 12 unless the menu pulls one in.

---

## Resolved (drop from the backlog)

- **Recent sweep:** A1 upstream-zig on #50/#51 (win-arm64 part moved to M-4); A2 full tier; A3 s2/sf/lwgeom absl; A4 sf on windows-latest; A5 make-path simulation; A6 tree leg with zig-libs; A7 verify-tree/bundle; A8 LIBS_ZIG_PIXI_TOKEN; A9 and A10 Next 4/5; A11 D5 committed (52220e6); A12 F6 re-run, so K7 is resolved too; A13 gamma worktrees; A14 omicron/kappa scratch; A15 `__clear_cache` upstream report (declined); A16 win-arm64 stress subset; A17 WinRT headers, avoided through zig-abseil; A18 C++ ABI on linux.
- **Older sweep, H list:** lld-zig pin; package-standalone `du`; D12 rattler flags; D8 cache key; D9 minimal deny-list; D10 glib; pango/harfbuzz pin; E3 binutils on linux; RZIG_PRINT_ARGV writer; linux C++ ABI; Windows slim/minimal; B24 binutils through rzig; B43 (only B39 stays, as M-25); less make; feat-shared-build-runner decisions; fix-zig-pkg-build-review decisions; the CONSENSUS boxes; standalone TODO phase boxes; phase-1 conda-package; cross-platform phases; initial-setup boxes; SOURCE_DATE_EPOCH; evex512; K2/bigobj; wheel licences; `--use-LTO`/Rprofile/dlltool/BINPREF; pkgconf remaining; win-zig-binutils ARM; tier1-engine UNVERIFIED; O-C10 optional stress dispatch, covered by later runs.
- **Code sweep:** "open point H" (R CMD config through rzig); sf, terra, gdalraster, lwgeom and s2 ok on Windows with zig-*; hdf5r, gsl, igraph, Rsamtools and scran ok on win-arm64 through the fallback; protolite and arrow ok on linux.

One conflict needs checking before B3 edits anything: does `-Dblas=openblas` work on Windows? K2 says yes (build.zig:29,275,661). O-A15 says it is ignored there. Q13 settles it by reading build.zig's Windows branch.
