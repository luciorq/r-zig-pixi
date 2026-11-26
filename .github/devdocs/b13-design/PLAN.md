# b13-design: L4 (native Windows build tools) and L5 (binary repository)

Build 13 design records, each with a working prototype under
`prototype/l4/` and `prototype/l5/`. Nothing here is wired into the build.
Backlog rows: chore-release-12/BACKLOG.md §4, L4 (R-F1) and L5 (R-F3).
Base: main 7e3648e (build 12, published run 45381914199).

## Goal

- **L4:** `R CMD INSTALL` on Windows without MSYS2. Find out what R's
  Windows package build actually calls, compare the replacements, and
  prove the best one on kappa with real CRAN packages (plain C, Rcpp,
  configure.win) and no MSYS2 on PATH.
- **L5:** a CRAN-like repository of r-zig-built binaries. Decide the
  layout, the ABI key, rebuild triggers and signing. Prototype on delta:
  build packages with published build 12 linux-64, index them, and
  install them from a `file://` repository into a fresh environment.

## Decisions

All by default, 2026-11-24, inside the approved batch. The user's choice
is the menu at the end of each part (L4-M, L5-M).

| id | question | options (chosen in bold) | reason |
|---|---|---|---|
| D1 | Which L4 candidate to prototype | **busybox-w32 + GNU make, both built with zig**; uutils/MS coreutils; prefix-dev/shell or brush; rzig applets | the only set that replaces sh, sed, awk, grep and make together (phase7alt SYNTHESIS §1, L4-F1); the rest leave msys-2.0.dll in |
| D2 | How the prototype builds GNU make | **build.zig (prototype/l4/build.zig), pkgconf.zig's shape**; build_w32.bat; conda-forge's make | simplicity rule (Zig, not bash); it can move into zigbuild/toolchain as is (backlog L7) |
| D3 | How the prototype builds busybox | **busybox's Kbuild with zig as the compiler (build-busybox.sh)**; a build.zig port now | a build.zig port is 300-400 lines (phase7native BUILD-REPORT §3); prove behaviour first |
| D4 | How the tools reach R in the prototype | **R_CUSTOM_TOOLS_PATH to one directory, env without r-zig-build-tools**; replacing TC/usr/bin | it is R's own switch and Rcmd_environ/Rprofile already honour it (build.zig:2857, patch 0014); the conda env then has no MSYS2 file at all |
| D5 | busybox applet names | **hard links (`busybox --install DIR`)**; copies; launcher exes | one file on disk, no launcher cost (6.5 ms per exec in phase7native) |
| D6 | The F1 make-argument quoting | **an R patch (draft 0016, Windows only)**; a make wrapper; the profile stand-in | R CMD SHLIB reads no profile; a wrapper is more trickery; the patch is 2 lines |
| D7 | L4 test packages | **jsonlite (C, Makevars rule), minqa (Rcpp + Fortran, $(shell)), ps (configure.win), Rmpfr (autoconf configure.win), RcppParallel (configure.win + cmake)**, plus Rcpp itself and `Rcpp::cppFunction` | all five go through make on build 12 (stress 45305358893 windows tree: "rzig build: ... needs make"), so they test the tools, not rzig |
| D8 | L5 layout in the prototype | **`bin/linux/<arch>-rzig<abi>/contrib/<x.y>/`** plus a P3M-style root whose `src/contrib` is the same files | the first is CRAN's shape for binaries; the second needs no R change on linux |
| D9 | L5 ABI key | **`<arch>-rzig<abi epoch>` in the path, R x.y as CRAN does, build number only in PACKAGES** | binaries stay valid across r-zig builds that keep the ABI; build 12's libc++ to libstdc++ switch is the kind of change that bumps the epoch |
| D10 | L5 packages | **Rcpp, jsonlite, cli, data.table, xml2** (+ rlang as a dependency) | C, C++, OpenMP (libomp) and a conda library (libxml2) |

## L4: native Windows build tools

### What R CMD INSTALL calls on Windows (survey)

- `sh configure.win` / `sh configure.ucrt` (install.R:1329-1344), and
  `cleanup.win`. R-exts says bash since R 4.2.0; autoconf scripts need
  `chmod`, `CONFIG_SHELL` (phase7alt F2).
- `make` with Makeconf (Makeconf.win) and `share/make/winshlib.mk`. GNU
  make functions (`$(if)`, `$(shell)`, `$(patsubst)`), so no pdpmake.
- In recipes: `rm`, `cp`, `mkdir`, `echo`, `test`, `basename`
  (`$(shell basename ...)`), `sed` and `nm` (winshlib.mk builds the
  `.def` export list as `$(NM) $(OBJECTS) | $(SED) ...` when there is no
  `<pkg>-win.def`). GNU make runs simple lines without a shell, so these
  must be real `.exe` names.
- `zip` for `R CMD INSTALL --build` (install.R:53, :498).
- `pkg-config` (r-zig ships pkgconf, built with zig, since build 11) and
  `cmake` (r-zig-extras) for some packages.
- On build 12, **tiers 0-2 need none of this**: `rzig build`
  compiles a package without make or sh unless it has a configure
  script, a Makefile, or Makevars rules/conditionals/`$(shell)`
  (patches 0009/0013). On the Windows stress tree (45305358893), 45 of
  the 111 compiled packages still needed make (L4-F2).

### Options

| option | covers | size (win-64) | licence | status |
|---|---|---|---|---|
| (a) MSYS2 m2-* (today) | everything | conda env `Library\usr`: 7,790 files, 81.7 MB; `usr\bin` 192 files, 30.1 MB (kappa, L4-F7) | GPL-3 and others, msys-2.0.dll | ships |
| (b) busybox-w32 + GNU make, zig-built | sh, sed, awk, grep, find, coreutils, unzip, patch, diff; make | 752,640 B busybox + 329,216 B make, applets as hard links (L4-F5) | GPL-2.0-only + GPL-3.0 | **prototyped here** |
| (c) uutils coreutils / MS coreutils | coreutils (+grep/find for MS) | 8.4 MB + launchers (uutils) | MIT | needs sh, make, sed, awk from elsewhere; uutils has no chmod on Windows by design (phase7alt SYNTHESIS §1) |
| (d) prefix-dev/shell, brush | sh only | | MIT | cannot run R's scripts (no backticks; brush cannot run `#!` scripts, phase7alt) |
| (e) rzig applets (rzig already dispatches on its name; its make evaluator answers R CMD config) | make's variable side only | | MIT | a shell and a make that runs recipes are big programs; rzig would grow into busybox. Keep rzig for tiers 0-2 |
| (f) Rtools45 | everything | ~ GB-scale installer | mixed | not redistributable as our group, MSYS2 again |

### Findings

| id | tag | finding and evidence |
|---|---|---|
| L4-F1 | V (earlier) | busybox-w32 + native make was the only set that removed msys-2.0.dll and installed the same packages as MSYS2 in the 2026-10-20 kappa run on build 8 (52 vs 51 of 62; the one real casualty RcppParallel's hard-coded `-G "MSYS Makefiles"`): `scratch/phase7native/kappa/REPORT.md`, `phase7alt/SYNTHESIS.md`. Phase 7 chose m2 then (B11). This record re-tests on build 12 |
| L4-F2 | V | Build 12 still sends 45 of 111 compiled packages of the Windows stress tree through make: `grep -h "^rzig build: .* needs make" stress-45305358893/stress-windows-latest-tree/logs/*.log`: configure.win 16, Makevars rule/target 13, `$(shell)` 6, conditionals 8, include 2 (45 in all; the other 66 went through `rzig build` tier 1) |
| L4-F3 | V | F1 is still there on build 12. With the zig make, stock R: minqa fails `make: *** No rule to make target '$(FCLIBS_XTRA)''.  Stop.` (kappa `logs/N/minqa.out`). install.R passes `SHLIB_LD='$(SHLIB_CXXLD)'` etc. in single quotes (R 4.6.2 install.R:2886-2941); native make keeps them. Draft fix `prototype/l4/0016-install-make-args-windows-quotes.patch` (Windows-only `gsub("'", "\"", makeargs)`), applies to the patched R 4.6.2 tree (`patch -p1 --dry-run` on delta: clean). Both makes read the double-quoted form the same (review, kappa: from cmd, zig make with `ALL_LIBS='-la $(LIBX)'` fails `No rule to make target '$(LIBX)''`, with `ALL_LIBS="-la $(LIBX)"` prints `[-la -lb]`; conda-forge m2-make prints `[-la -lb]` for both forms), so the patch is harmless with MSYS make. Only the `.shlib_internal` hunk ran inside R (test.R `bake`); the `src/Makefile.win` hunk is the same line, not run. Limit: a value ending in `\` would escape the closing double quote under the C runtime rules; none of install.R's values does |
| L4-F4 | V | make 4.4.1 builds with `prototype/l4/build.zig` under both zigs 0.17.1 (upstream PyPI and conda-forge) for x86_64 and aarch64: 329,216 B (x86_64, same sha256 f85829e9... from both zigs) and 246,784 B (aarch64); 95 s cold, 6 s warm. Upstream signature checked (`gpg --verify`, Paul D. Smith key) |
| L4-F5 | V | busybox-w32 FRP-6354-g5f09fb446 (newest, 2026) builds with `build-busybox.sh` under both zigs for x86_64 (752,640 B; two upstream-zig builds byte-identical, e864ebce...; conda-forge zig 16a4914d...) and aarch64 (676,864 B; upstream 34d63a36..., conda-forge a2cbc781... built in the review), 47-65 s at -j20 on delta. `busybox --install DIR` on kappa makes 179 hard-linked names (sh, bash, sed, awk, grep, rm, cp, chmod, uname, unzip, patch, diff, ...; no zip, no nm) |
| L4-F6 | V | zig 0.17.1 bug, aarch64-windows-gnu: linking with `-fno-unwind-tables -fno-asynchronous-unwind-tables` fails in zig's own mingw crtexe.c (".seh_ directive must appear within an active frame"); a hello-world reproduces it on delta. The wrapper drops the two flags on link lines only. Worth an upstream zig issue |
| L4-F7 | V | Sizes on kappa: msys env `Library\usr` 7,790 files / 81,672,688 B, `usr\bin` 192 files / 30,081,837 B; native dir 752,640 + 329,216 + pkgconf 207,872 (x2 names) B |
| L4-F8 | V | R sees the native set with no MSYS2 file in the env and only System32 besides it (kappa probe): `Sys.which` sh/make/sed/grep/awk/rm/cp/chmod/uname from the tools dir; `R CMD sh -c 'uname -a'` = `Windows_NT kappa 10.0 22621 x86_64 MS/Windows`; make = `GNU Make 4.4.1, Built for Windows32`. As before, `Sys.which` returns System32's `tar`, `find` and WSL `bash` (R's own search, unchanged by PATH order) |
| L4-F9 | V | busybox FRP-6354 still has no `/c/` paths: `cd /c/Windows` fails (kappa probe). RcppParallel's cmake `MSYS Makefiles` remains the known casualty (see results) |
| L4-F10 | V | Process start: 200x `sh -c true` from make 3.5-4.8 s native vs 9.4 s MSYS (2 runs each, kappa); 100x `R CMD sh -c true` 8.6 s native vs 7.1 s MSYS (Rcmd.exe's own start dominates) |
| L4-F11 | V | tier 0-2 path unaffected: Rcpp installs through `rzig build` (no "needs make" line) and `Rcpp::cppFunction` (R CMD SHLIB) works with the native set and stock R: `RESULT N cppFunction smoke=TRUE` |
| L4-F12 | I | busybox has `ar.exe` and `strings.exe` applets; R's Makeconf names rzig's `ar` by full path, so no shadowing is expected; not probed |

### Results on kappa (build 12, win-64, 2026-11-24)

Each target installed with its dependencies into a fresh library from a
local copy of CRAN (`file://`), `MAKEFLAGS=-j4`, `Ncpus=1`; smoke = load
and one call. PATH = tools dir (N only), env `Library\bin`, env root,
System32, Windows; no `.pixi\bin` (it has uutils `sh.exe`/`make.exe`
trampolines), no Git. Logs:
`scratch-b13-design/kappa-logs/logs/{N,M}/*.out`, `kappa-*.log`.

| package (why make) | N, stock R | N + 0016 | M (MSYS2, build 12 as shipped) |
|---|---|---|---|
| jsonlite (C; Makevars rule) | ok 77.7 s | ok 52.5 s | ok 96.9 s |
| minqa (Rcpp + Fortran; `$(shell)`) | **fail: F1** (`No rule to make target '$(FCLIBS_XTRA)''`) | ok 101.5 s | ok 70.2 s |
| ps (configure.win) | ok 75.2 s | ok 32.6 s | ok 105.6 s |
| Rmpfr + gmp (autoconf configure.win) | ok 94.6 s | ok 117.0 s | ok 246.4 s |
| RcppParallel (configure.win + cmake) | fail: no cmake (env lacked r-zig-extras; added) | **fail: `/C/.../cmake.exe: not found`** (its hard-coded `-G "MSYS Makefiles"`, L4-F9) | ok 404.0 s |
| `Rcpp::cppFunction` (R CMD SHLIB, rzig) | ok 17.3 s | ok 7.7 s | ok 10.8 s |

- N+0016 installs 4 of 5 targets and cppFunction; M 5 of 5. The only
  difference is RcppParallel, the same casualty as on build 8.
- Times are not a fair benchmark: rzig's zig cache is keyed by paths,
  so each env's first compiles are cold, and runs went N-stock, N+0016,
  M. They show no slowdown from the native set; process-start numbers
  are in L4-F10.

### Judgement

- **(b) works on build 12** for the cases that matter (plain C through
  make, Rcpp + Fortran through make, configure.win, autoconf), with one
  2-line R patch (F1), at ~1.1 MB instead of ~82 MB, with no
  msys-2.0.dll and 2-3x cheaper shell starts. The tools are built from
  source with zig like pkgconf.
- **Risks:** CRAN tests configure.win under Rtools' bash; busybox ash
  lacks arrays, `/c/` paths and `cygpath` (4 of 49 scripts read used
  bash-isms, phase7alt RR C11); RcppParallel's hard-coded MSYS
  generator; no `zip` for `--build`; busybox is GPL-2.0-only (source
  must ship beside it, or a written offer).
- **The way to switch is the stress suite**, not this sample: run the
  Windows stress tree with the native set as a report-only leg and read
  every row.

### L4-M: menu (recommended marked)

- **(a)** Keep MSYS2 (no change).
- **(b) ★** Native set as an opt-in in build 13, default later: add
  make (build.zig, as pkgconf) and busybox (Kbuild with zig first, a
  build.zig later) to the Windows build-tools group behind a switch, land
  the 0016 F1 patch (harmless with MSYS make), add a report-only Windows
  stress leg with the native set; flip the default when its rows match
  the MSYS leg. Keep m2 as the fallback.
- **(c)** Switch the default now and keep m2 in r-zig-build-tools only as
  a documented fallback.
- **(d)** Only land the 0016 F1 patch and the zig make now (backlog L7);
  busybox later.

Open items for (b)/(c): a `zip` (busybox has none; R CMD INSTALL
`--build` on Windows needs it); RcppParallel (`/c/` path mapping as a
busybox patch, or upstream); where the busybox source and GPL-2 offer
live; aarch64 not run (no Windows ARM host here).

## L5: binary package repository

### Design

- **Who it is for.** conda/pixi users get compiled packages as conda
  packages (Phase 3, r-zig-packages on prefix.dev); this repository is for
  `install.packages()` users of the standalone tree and the wheel (no
  solver), and for conda users who install from CRAN inside an env.
- **Layout** (static files; any HTTPS host):
  `bin/linux/<arch>-rzig<abi>/contrib/<x.y>/{PACKAGES,PACKAGES.gz,PACKAGES.rds,<pkg>_<ver>.tar.gz}`;
  Windows and macOS later as CRAN's own `bin/windows/contrib/<x.y>` and
  `bin/macosx/<arch>/contrib/<x.y>` under the same `<arch>-rzig<abi>`
  root, where `type = "binary"` already works. Sources are CRAN's.
- **Linux access.** R on linux has no binary type, so either
  (i) `contriburl=` / `repos=` set to a root whose `src/contrib` is the
  binary directory (Posit P3M's trick; no R change; both modes proven,
  L5-F3), or (ii) a small R patch making r-zig's `contrib.url()` add the
  bin path first and fall back to source (as Windows/macOS do). (i) now,
  (ii) once the key is stable.
- **ABI key** = R x.y (in the path, as CRAN) + arch + r-zig ABI epoch.
  The epoch bumps when a package built before cannot load or behave the
  same: libR's exported ABI, the linux C++ standard library (build 12's
  libc++ to libstdc++ switch would have been one), the OpenMP runtime,
  the glibc/macOS floor. R's own `Built:` field cannot tell an r-zig
  binary from a CRAN/P3M one (`R 4.6.2; x86_64-pc-linux-gnu; ...; unix`,
  L5-F2), so the key must be in the URL. PACKAGES also carries
  `RZig-Build` (the build that made it) and `SystemLibs` (NEEDED
  libraries outside R and libc, as P3M's manylinux binaries record them).
- **Rebuild triggers:** a new package version on CRAN (PACKAGES diff); a
  new version of a LinkingTo dependency (headers compiled in: Rcpp,
  cpp11, RcppArmadillo...: rebuild the reverse LinkingTo set); a SONAME
  change of a `SystemLibs` entry in the reference env (libxml2.so.16 to
  .17); an epoch bump (rebuild everything); a new R x.y (new path).
- **Relocation.** Binaries must not carry the build env's absolute
  RUNPATH (L5-F4): the repository build links with no env rpath; R's
  own `DT_RPATH` (`$ORIGIN/../../..`, the env's lib) then resolves the
  libraries. Needs an rzig switch (e.g. `R_ZIG_ENV_RPATH=0`) for repo
  builds; local installs keep today's rpath.
- **System libraries.** Linux: the consumer needs the same SONAMEs as
  the build env (conda: `SystemLibs` maps to conda package names to
  install; standalone/wheel: bundle as P3M manylinux does, or build only
  packages whose libraries the tree ships). Windows: static zig-libs,
  nothing to install.
- **Signing.** R checks no signature. Serve over HTTPS from immutable
  release assets, add `SHA256` per file to PACKAGES, and attach GitHub
  artifact attestations (sigstore, `gh attestation verify`) from the
  building workflow. An R-side verify (rzig check of SHA256 before
  install) is a later option.
- **Hosting:** GitHub Releases, one release per `<arch>-rzig<abi>-<x.y>`
  (an asset URL directory works as a contriburl: R fetches
  `<url>/PACKAGES` and `<url>/<file>`; limits 1,000 assets and 2 GB per
  asset: enough for a curated set, not all of CRAN); GitHub Pages (1 GB
  site): too small; prefix.dev: a conda channel, not CRAN-like (that is
  Phase 3); an object store (R2/S3) for a large set.

### Findings

| id | tag | finding and evidence |
|---|---|---|
| L5-F1 | V | Build 12 linux-64 from universe (r-zig-slim `h3e03716_12`, r-zig-toolchain `hc78f3be_12`) builds the set with `R CMD INSTALL --build`, one at a time, cold zig cache: cli 10.3 s, rlang 8.9, Rcpp 8.9, jsonlite 2.2, data.table 10.3, xml2 3.4 (44 s); 9.2 MB of binaries; index (write_PACKAGES + extra fields) 0.48 s. `install.packages()` from source of the same set, warm cache: 51.1 s and 48.9 s (delta, 20 cores, MAKEFLAGS=-j8, Ncpus 1) |
| L5-F2 | V | Fresh env with r-zig-slim only (no compilers, `Sys.which("make")` empty): 6 binaries installed from `file://` in 1.82 s with `contriburl=` and 1.82 s with the P3M-style `repos=`; every smoke passed (Rcpp, jsonlite, cli, data.table with libomp, xml2). `Built: R 4.6.2; x86_64-pc-linux-gnu; <date>; unix` |
| L5-F3 | V | Both access modes work without an R change: `install.packages(contriburl = "file://.../bin/linux/x86_64-rzig1/contrib/4.6", type = "source")` and `repos = "file://.../p3m/x86_64-rzig1"` (whose `src/contrib` links to the same files); dependencies (rlang) resolve from the binary index |
| L5-F4 | V | **Relocation bug for a repository:** every binary carries `RUNPATH [/home/.../envs/build/lib]` (rzig adds `-Wl,-rpath,<env>/lib` for a conda env, compiler.zig:433). With the build env moved away, xml2 in a consumer env that has libxml2 loaded the **host's** `/usr/lib/x86_64-linux-gnu/libxml2.so.16.1.2` (Ubuntu 26.04), not the env's: a stale DT_RUNPATH disables R's DT_RPATH. With the RUNPATH removed (patchelf), the same env loads its own `envs/consumer-libs/lib/libxml2.so.16.1.4` through R's exec `RPATH [$ORIGIN/../../..:$ORIGIN/../../lib]`; data.table's libomp resolves the same way |
| L5-F5 | V | `SystemLibs` from `readelf -d` NEEDED: data.table `libomp.so`, xml2 `libxml2.so.16`, the rest none. r-zig-slim's consumer env has no libxml2 (pixi list), so a conda consumer must add it (the repo cannot tell it) |
| L5-F6 | I | Embedding (rpy2 from a non-conda python) with rpath-free binaries relies on libR's own DT_RPATH for libraries dlopened by R; rzig's comment (environment.zig:54-56) says glibc applies only the executable's DT_RPATH. Not tested here |

### L5-M: menu (recommended marked)

- **(a)** No repository: conda packages only (Phase 3).
- **(b) ★** Curated linux repository first: a workflow builds a fixed
  list (the stress set's tier-1/2 packages) for linux-64 and
  linux-aarch64 against the published build, with no env rpath, into
  `bin/linux/<arch>-rzig<abi>/contrib/<x.y>`, hosted as GitHub Release
  assets with SHA256 fields and attestations, used through `repos=`
  (P3M layout) from the standalone tree and the wheel. Rebuild on the
  triggers above. Windows/macOS in CRAN's binary layout next.
- **(c)** As (b) plus the R patch for a linux binary `pkgType` from the
  start.
- **(d)** Rely on Posit P3M manylinux binaries (they load in r-zig, per
  feat-no-host-paths' survey) and build only what P3M lacks.

## Tests run

| where | command | result |
|---|---|---|
| delta | `zig build -Dmake=... -Darch={x86_64,aarch64}` with upstream and conda-forge zig 0.17.1 (prototype/l4/build.zig) | 4 x ok (L4-F4) |
| delta | `build-busybox.sh <zig> busybox-w32-FRP-6354-g5f09fb446.tgz {x86_64,aarch64}` | x86_64 ok with both zigs; aarch64 ok after L4-F6's link-flag drop |
| kappa | `pixi install --all` (prototype/l4/kappa/pixi.toml), `busybox --install tools-N` | envs native (slim + compilers + extras, no MSYS2 file) and msys (+ r-zig-build-tools) |
| kappa | `run.bat N probe`, `run.bat M probe` | L4-F8..F10 |
| kappa | `run.bat N install` (stock R), `bake`, `run.bat N install`, `run.bat M install` | "Results on kappa" table: N stock 3/5, N + 0016 4/5, M 5/5; kappa scratch `rz-b13-design` deleted after |
| delta | `patch -p1 --dry-run < 0016-...patch` on build/R-4.6.2 | clean |
| delta (review) | prototype/l4/build.zig from the mirrored worktree, both zigs, x86_64 and aarch64 | 4 x ok; x86_64 f85829e9... from both zigs, aarch64 0b1e9e4b... (cf) / e2ec978f... (upstream), as first reported |
| delta (review) | `pixi exec -s make -s perl -s bzip2 -- sh build-busybox.sh <conda-forge zig> ... aarch64` | ok, 53 s, 676,864 B (the missing both-zigs cell for aarch64) |
| delta (review) | `patch -p1 --dry-run` of 0016 on ~/rz/base/build/R-4.6.2 | clean |
| kappa (review) | t.bat in `rz-b13-design`: zig make.exe (upstream x86_64) and conda-forge m2-make, stock single-quoted vs 0016 double-quoted make args, from cmd | zig make + single quotes: `No rule to make target '$(LIBX)''`; the other three print `[gpp] [-la -lb] [x.dll]`; scratch deleted |
| delta (review) | `readelf -d` on l5/work/buildlib/*/libs/*.so, PACKAGES fields | every .so has `RUNPATH [.../l5/.pixi/envs/build/lib]`; SystemLibs libomp.so (data.table), libxml2.so.16 (xml2) |
| delta | prototype/l5/run.sh steps 1-3 | L5-F1..F5 |

## Not verified

- aarch64 Windows binaries (no Windows ARM host); upstream vs
  conda-forge make/busybox behaviour on Windows (built with both, only
  the upstream-zig binaries ran on kappa).
- The 0016 patch built into R (tested as the same line injected into the
  installed tools package's `.shlib_internal`; the `src/Makefile.win` hunk
  never ran inside R).
- The stress-suite scale (45 make packages) under the native set.
- L5 on macOS/Windows; rpy2 embedding with rpath-free binaries (L5-F6);
  GitHub Releases as a contriburl over HTTPS (layout reasoning only).

## Needs from other topics

None for this batch: nothing is wired in. Follow-ups if the menus pick
(b): zigbuild/toolchain (make.zig from prototype/l4/build.zig, a busybox
step), recipe (build-tools group contents and licences), patches (0016),
rzig (`R_ZIG_ENV_RPATH`), stress (a native Windows leg), a repository
workflow.

## Review

Skeptical pass over the record and every prototype file, 2026-11-24.

- Only new files under `.github/devdocs/b13-design/`; nothing outside the
  topic's ownership (`git status --short`: one untracked dir).
- Fixed L4-F2's breakdown: it summed to 47, the logs give rule/target 13
  and conditionals 8 (16+13+6+8+2 = 45; 66 more went through `rzig build`
  tier 1, so 111 compiled).
- L4-F3: verified the claim "harmless with MSYS make" on kappa (it was
  reasoned only), recorded that only the `.shlib_internal` hunk ran in R,
  and the trailing-backslash limit of double quotes.
- L4-F5: filled the conda-forge zig aarch64 busybox build (it had not
  run); build-busybox.sh's header now says how to get make/perl/bzip2 on
  a host without them (delta has no make, the first review run failed
  with `make: not found`).
- build-repo.R: its comment named a decision id that does not exist
  (D-L5-2); now D9.
- Re-checked, no change: install.R line refs (1329-1344, 53, 498,
  2886-2941), compiler.zig:433, environment.zig:54-56, build.zig:2857,
  patch 0014; make.exe hashes/sizes; L5 RUNPATH and PACKAGES fields.
- Left as is (prototype scope, recorded): build-busybox.sh's sed on
  `.config` and shell wrappers (D3: a build.zig port comes with option
  (b)); kappa scripts hard-code `C:\Users\admin\rz-b13-design` (kappa's
  `%USERPROFILE%`); run.sh step 3 does not restore the build env if an
  Rscript fails.

## Suggested commit message

```
docs: design L4 native Windows build tools and L5 binary repository with prototypes
```
