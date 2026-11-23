# wave2-compat: older hosts, distro libraries, rpy2, wheel upgrades

Branch `wave2-compat` from main f5a6c84 (build-12 batch 1). Backlog:
`chore-release-12/BACKLOG.md` items M-12, M-13, M-14, M-26. Probes run on
delta (linux-64, docker) on 2026-11-23; the scripts are in `probes/`.

## Goal

Evidence for the release: does r-zig (conda packages and the standalone
tree) compile and run C and C++ on older linux hosts, can the standalone
tree build against distro libraries, does embedding libR (rpy2) work,
and do pip and uv install, upgrade and reinstall the wheels.

## Decisions

| # | Question | Chosen | Reason |
| --- | --- | --- | --- |
| W1 | Inputs | conda packages from `pixi run -e pkg conda-package` of this branch; standalone archives from `pixi run package` + `package-toolchain`, reusing ~/rz/base's build/ and dist/ (3395a08 build, cached) | velocity; same sources as f5a6c84 except batch 1's non-R files |
| W2 | Probe hosts | docker `ubuntu:22.04` (glibc 2.35, GLIBCXX_3.4.30), `ubuntu:24.04` (2.39, 3.4.33), `rockylinux:8` (2.28, 3.4.25) | the backlog's list; Rocky 8 = RHEL 8 |
| W3 | Conda env in the containers | pixi from pixi.sh, channels `/chan` (dist/conda), universe, conda-forge; `r-zig-toolchain` | universe before conda-forge (strict priority), as users do |
| W4 | rpy2 from conda-forge | not possible: it depends on `r-base`, which r-zig-slim's `r-base <0a0` excludes (by design, CXX-STDLIB.md decision 4); rpy2 from PyPI into the conda env instead | the only way today; recorded as finding F4 |
| W5 | Fix the embedding bug found (F5) here | yes: base packages' shared objects link libR (build.zig `newPkgMod`, tcltk) | one line each, what R's own shlib.mk does; obviously needed |
| W6 | M-13 header mixing (F7) | deferred, not fixed here | an rzig design change (system include roots), more than half a day with tests |
| W7 | M-26 upgrade path | two builds of the same wheels, `--build-tag 1` and `--build-tag 2` | there is no second version to upgrade to; shows what a rebuilt wheel does |
| W8 | Wheel input | `pixi run -e minimal build` before the W5 fix | pip/uv mechanics do not depend on it |

## Findings

Legend: V = verified, I = inferred, A = assumed.

1. **V, M-12 standalone.** On all three hosts the standalone tree (base +
   compilers + build-tools archives, nothing else installed but xz and
   ca-certificates) starts R, compiles and loads a C and a C++ SHLIB,
   installs jsonlite (C) and Rcpp from CRAN source, and `Rcpp::stop` and a
   `std::range_error` are caught by R's `tryCatch`. R loads its own
   `lib/libstdc++.so.6` and `libgcc_s.so.1` first (`/proc/self/maps`), so
   Rcpp.so, which needs GLIBCXX_3.4.32, loads on Rocky 8 (host 3.4.25) and
   Ubuntu 22.04 (3.4.30). No libstdc++ floor failure on a bare distro.
   Logs: delta `~/rz/scratch/wave2-compat/out/sa-{ubuntu-22-04,ubuntu-24-04,rockylinux-8}.log`,
   `PROBE-SUMMARY: shlib-c=ok shlib-cxx=ok install-jsonlite-c=ok install-Rcpp=ok rcpp-stop=ok cxx-throw-std=ok`.
2. **V, M-12 conda.** The same probe in a pixi env from the local
   channel (`r-zig-toolchain`, conda-forge zig 0.17.1, libstdcxx 16.2.0):
   all six steps ok on the three hosts; R loads the env's
   `libstdc++.so.6.0.36`. Logs: `out/conda-*.log`.
3. **V, the floor failure, where it is.** It shows only when the host's
   libstdc++ is in the process before libR (an embedder): Ubuntu 22.04,
   distro python3 + pip rpy2 3.6.9, `ctypes.CDLL("libstdc++.so.6",
   RTLD_GLOBAL)` before `import rpy2.robjects`:
   `OSError: cannot load library '/opt/R-4.6.2-zig/lib/R/lib/libR.so': /lib/x86_64-linux-gnu/libstdc++.so.6: version `CXXABI_1.3.15' not found (required by /opt/R-4.6.2-zig/lib/R/lib/../../libicui18n.so.78)`
   (slim's ICU; `out/rpy2-host-fixed-ubuntu-22-04.log`). Without the
   preload R loads its own runtime and everything works (F6).
4. **V, M-14.** conda-forge's rpy2 cannot join r-zig: the solve fails on
   `r-base <0a0` (rpy2 3.6.x needs `r-base >=4.4,<4.5.0a0`). PyPI's rpy2
   (`pip install rpy2` in the env, conda-forge python 3.12) installs
   (ABI mode).
5. **V, bug, fixed (W5).** Embedding failed before the fix in both the
   conda env and the standalone tree:
   `methods.so: undefined symbol: R_NilValue`. rpy2 loads libR without
   RTLD_GLOBAL, and r-zig's base-package objects (methods.so, stats.so,
   ...) had no `NEEDED libR.so` (`readelf -d`: only libc / BLAS), unlike
   GNU R's (shlib.mk links `$(LIBR)`). Fix: build.zig:3133-3137
   (`newPkgMod`) and build.zig:916 (tcltk). After it methods.so has
   `NEEDED libR.so`, and `pixi run verify-tree`, `smoke`, `hermetic` and
   the six recipe tests of `conda-package` pass.
6. **V, M-14 after the fix.** rpy2 compiles an Rcpp function in the
   embedded R and catches `Rcpp::stop` (`PROBE rpy2-rcpp-compile: ok`,
   `rpy2-rcpp-stop: ok`): conda env (delta, both with and without the
   preload, which there resolves to the env's 6.0.36) and the standalone
   tree with Ubuntu 22.04's python3 (no preload). With the host's
   libstdc++ preloaded: F3.
7. **V, M-13: building against distro -dev packages fails** (Ubuntu
   22.04 and 24.04; libgdal-dev, libmagick++-dev, libgeos-dev,
   libproj-dev, libudunits2-dev, libssl-dev): terra, sf, magick not
   installed (`out/m13-ubuntu-*.log`). Two causes:
   a) zig targets `x86_64-linux-gnu.2.17` and searches no /usr/include
      or /usr/lib: `udunits2.h... no`, `'openssl/opensslv.h' file not found`,
      `'proj.h' file not found`;
   b) distro `.pc` files name `-I/usr/include/x86_64-linux-gnu`
      (libcurl.pc, pulled in by proj.pc's Requires.private); with `-I`
      the host's glibc 2.35/2.39 headers come before zig's 2.17 ones:
      `/usr/include/x86_64-linux-gnu/bits/types/time_t.h:8:9: error: unknown type name '__time64_t'`
      (package curl, terra's PROJ check). Pointing `R_ZIG_EXTRA_ENV` at a
      directory of the library headers alone (`out/m13x-ubuntu-24-04.log`)
      does not help: b) remains.
   Also s2 wants cmake (the extras group; its preflight text named it).
8. **V, M-13 ABI half: the distro's C++ API works.** `probes/m13-gdal.sh`
   on Ubuntu 24.04: an R SHLIB compiled by rzig with `-idirafter` for
   /usr/include/gdal, /usr/include and /usr/include/x86_64-linux-gnu
   (not `-I`) and `-lgdal`, that takes a `CPLString` (std::string) by
   value from libgdal 3.8.4 and a driver name, throws and catches:
   `[1] "raster+GTiff"`, with libgdal.so.34 and R's libstdc++.so.6 in the
   process. The same `curl/curl.h` compile fails with
   `-I/usr/include/x86_64-linux-gnu` and compiles with `-idirafter`.
   So the libstdc++ ABI matches; only the include order (F7 b) and the
   search paths (F7 a) block sf/terra from distro packages.
9. **V, M-26 pip** (pip 26.3, python 3.15 from the wheel env, scrubbed
   environment; `out/m26.log`): `pip install r-zig` then R runs;
   `pip install --upgrade --no-index --find-links <tag 2> r-zig`:
   "Requirement already satisfied"; the tag-2 file directly: "r-zig is
   already installed with the same version as the provided wheel. Use
   --force-reinstall"; `pip install --find-links <tag 1> r-zig-toolchain==4.6.2`
   brings both groups and ziglang 0.17.1 from PyPI, a C++ SHLIB builds,
   make is at `r_zig/R/lib/R/bin/toolchain/usr/bin/make`;
   `--force-reinstall --no-deps` of r-zig (tag 2) keeps the groups' files
   (C++ SHLIB and make still ok), `pip check`: no broken requirements;
   uninstalling the groups leaves r-zig's own toolchain files only, and
   uninstalling r-zig leaves nothing under `r_zig/`.
10. **V, M-26 uv** (uv 0.13.9 via `pixi exec`): the same sequence;
    executable bits kept (`-rwxrwxr-x` on `bin/exec/R` and the console
    script); `--upgrade` with tag 2 offered is a no-op ("Checked 1
    package"); `--reinstall-package r-zig` swaps tag 1 for tag 2 with the
    groups installed and both still work; uninstall leaves nothing.
11. **I, M-26 consequence.** A build tag never upgrades an installed
    wheel (PEP 427: it only orders candidates of one version), and the
    groups pin `r-zig==4.6.2`, which a post-release `4.6.2.post1` would
    not satisfy. A rebuilt wheel reaches users only with a new version
    of all four wheels together (or `--force-reinstall`).

## Tests

All on delta, worktree `~/rz/wt/wave2-compat`, `P=.github/devdocs/wave2-compat/probes`:

| Test | Command | Result |
| --- | --- | --- |
| conda packages | `taskset -c 0-7 pixi run -e pkg conda-package` (before and after W5) | EXIT=0, 6/6 recipe tests passed both times |
| standalone archives | `pixi run package && pixi run package-toolchain` | EXIT=0 |
| fixed tree | `pixi run package && pixi run verify-tree`; `pixi run smoke`; `pixi run hermetic` | all 0 |
| M-12 standalone | `DIST=$PWD/dist bash $P/run.sh standalone <image> sa-<name>` | 3/3 hosts, 6/6 steps ok |
| M-12 conda | `CHAN=$PWD/dist/conda bash $P/run.sh conda <image> conda-<name>` | 3/3 hosts, 6/6 steps ok |
| M-13 distro libs | `DIST=$PWD/dist bash $P/run.sh standalone ubuntu:{22.04,24.04} m13-<name> "EXTRA_PKGS=libgdal-dev libmagick++-dev libgeos-dev libproj-dev libudunits2-dev libssl-dev libsqlite3-dev pkg-config" "PROBE_PKGS=terra sf magick"` | terra, sf, magick FAIL (F7) |
| M-13 headers as extra env | same, 24.04, `SYS_HEADERS="gdal proj.h ... sqlite3ext.h"`, `PROBE_PKGS="terra magick"` | FAIL (F7 b) |
| M-13 ABI | `docker run --rm -v $PWD/$P:/probe:ro -v $PWD/dist:/dist:ro ubuntu:24.04 bash /probe/m13-gdal.sh` | ok (F8) |
| M-14 host python | `DIST=... bash $P/run.sh rpy2-host ubuntu:22.04 rpy2-host[-fixed]-ubuntu-22-04` | before fix: F5 error; after: ok without preload, F3 with it |
| M-14 conda | pixi workspace (local channel, universe, conda-forge; `r-zig-toolchain`, `python 3.12.*`, `pip`), `pixi run pip install rpy2`, `PROBE_LIB=lib pixi run python -I $P/probe-rpy2.py [host-first]` | before fix: F5; after: ok both |
| M-26 | `pixi run -e minimal build`; `pixi run -e wheel wheel --build-tag 1`; `... --build-tag 2 --out-dir dist/wheel-tag2`; `env -i HOME=$HOME PATH=/usr/bin:/bin bash $P/m26-wheels.sh $PWD/.pixi/envs/wheel/bin/python3 $PWD/dist/wheel $PWD/dist/wheel-tag2 ~/rz/scratch/wave2-compat/m26` | every CHECK ok (F9, F10) |

## Not verified

- The fix (W5) on macOS (`@loader_path` rpath to libR.dylib through
  `relRPaths(.pkglibs)`, assumed the same as linux, A) and its CI run;
  Windows is unchanged (its DLLs already link R.dll). The tcltk line
  (full variant only) was not built here.
- linux-aarch64; the conda containers and the wheel ran with the
  pre-fix R (the fix only adds `NEEDED libR.so`).
- rpy2 in API mode (the PyPI build fell back to ABI mode both times).
- minimal (no ICU) or the wheel with a host libstdc++ preloaded: libR
  may load, and then a package needing GLIBCXX_3.4.32 would fail (I).
- RHEL 8 with gcc-toolset or Ubuntu 20.04; the conda containers'
  M-13 (conda-forge GDAL is covered by stress).

## Backlog items closed

- **M-12**: done (F1, F2, F3).
- **M-14**: done, with a fix (F4, F5, F6; W5).
- **M-26**: done (F9, F10, F11).
- **M-13**: probed (F7, F8); building against distro -dev packages is
  **deferred** (W6): needs rzig to treat the system's glibc include roots
  (`/usr/include`, `/usr/include/<multiarch>`) as `-idirafter`, and a
  way to opt into /usr/include and /usr/lib (e.g. `R_ZIG_EXTRA_ENV=/usr`
  with `-idirafter` on linux). New backlog item; overlaps M-16
  (`-isystem` vs `-I` for env dirs on linux), so best done with it.

## Review

Adversarial pass over the diff and the logs on delta (2026-11-23).

- Confirmed, fixed: two build.zig comments still said unix base packages
  never link libR (addSharedLib's doc comment, buildWindows' tools
  block); reworded. `probes/inside.sh` header named an `/out` mount and a
  `distro` mode that do not exist; corrected.
- Confirmed, recorded: M-13's deferred item overlaps backlog M-16 (above).
- Refuted: Windows double link (newPkgMod skips Windows, whose callers
  `linkLibrary(libR)`); unix newPkgMod callers are all base packages and
  run after `ctx.libR` is set (build.zig:778); macOS uses the same
  `linkSibling(libR)` as mod_lapack/internet/cairo, `@rpath/libR.dylib`
  with `.pkglibs` rpaths, and verify-tree's macOS load-command check
  allows `@rpath/*` (still unbuilt on macOS, as above).
- Evidence re-checked: every `PROBE-SUMMARY`, the R_NilValue and
  CXXABI_1.3.15 lines, `"raster+GTiff"` and the M-26 CHECK lines are in
  delta `~/rz/scratch/wave2-compat/out/`; fixed tree and conda staging
  `methods.so` have `NEEDED libR.so`, minimal (wheel input, pre-fix)
  does not. The conda rpy2 run had no log; re-run on the fixed local
  channel (env `methods.so` NEEDED libR.so, rpy2 3.6.9): both modes
  `rpy2-rcpp-compile: ok`, `rpy2-rcpp-stop: ok`.
