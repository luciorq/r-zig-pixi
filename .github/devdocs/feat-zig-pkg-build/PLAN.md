# feat-zig-pkg-build: R installs source packages with zig alone

Branch feat-zig-pkg-build, from main 7a3004d, rebased on b490bdf.
Milestone 1 (2026-10-09): the design, a hand-run prototype on linux-64,
and measurements; no file of R, rzig or build.zig changed. Milestone 2
(2026-10-09, below): `rzig build`, the evaluator and the shipped roots.
Milestone 3 (2026-10-09, below): R CMD INSTALL calls it (patches 0012,
0013). Milestone 5 (2026-10-10, below): the patched R on macOS and
Windows; M4 (the parity script in the repo) is still open.

## The question (the user, 2026-10-08)

How could zig's standard library and `zig build` alone replace R's
dependency on external tools for package installation, so that pure R
packages and some level of C, C++ and zig-based packages install with
nothing but zig: no sh, no make, no coreutils, no nm/sed.

The project already removed mv/cp/tar/sed/which from R's own install
code (patches 0002-0010), plans a shell-free front end and spawn
(feat-no-host-paths C/S/D/P) and a `build-tools` toolchain group that
carries make, sh and coreutils (feat-standalone-toolchain B23/B39).
This record is about the part those plans leave to make and sh: the
native build of a package.

## Decisions (2026-10-08, each the recommended option)

1. **Orchestrator:** `zig build` with a fixed root that R ships; every
   C, C++ and Fortran compile and the link are std.Build Run steps that
   call rzig (zig-cc, zig-cxx, zig-fc). No flag is derived in the root:
   rzig's argv rules stay the one place (compiler.zig, fortran.zig,
   libcxx_mirror, S1-S11). Pure-zig code goes through `b.addObject`.
2. **Classification, Makeconf evaluation and the plan live in rzig**
   (zig code). R gets one hook before `run_shlib` and a shell-free
   spawn primitive.
3. **zig packages:** `src/build.zig` exporting
   `pub fn rbuild(comptime rpkg: type, b: *std.Build, opts: rpkg.Options) std.Build.LazyPath`;
   the root imports the package as a path dependency, so the package
   never imports anything outside its tree.
4. **Milestone 1:** prototype and measurements only, then go/no-go.

## What zig std / zig build replaces, tool by tool

Checked in zig 0.16.0's `lib/std` (the pixi env's zig).

| tool on R's install path | zig replacement | where |
|---|---|---|
| `sh -c` as spawner (unix `system()`), `sh.exe` | `std.process.spawn` / `run` / `replace`: argv, no shell | rzig already; R needs one spawn primitive to call rzig |
| `sh` for `configure`, `cleanup`, Makevars recipes | none: tier 3. zig packages probe features with `std.Build.Step.ConfigHeader` and probe-compile Run steps | tier-2 helper |
| `make` (shlib.mk, winshlib.mk) | `std.Build` graph, content cache, `-j`, `--verbose`, `--summary` | zig build |
| cp mv rm mkdir touch cat | `std.Io.Dir` copyFile, rename, deleteTree, createDirPath | rzig (R side done, patch 0005) |
| tar + gzip/xz/zstd (read) | `std.tar.extract` + `std.compress.{flate,xz,zstd}` | rzig, optional (R's untar is internal) |
| bzip2 | not in std | R's internal `bzfile()` |
| unzip | `std.zip.extract` (reader only) | rzig, optional (R's unzip is internal) |
| nm \| sed for the Windows `.def` | rzig writes the `.def` from the objects' COFF symbol tables (`std.coff`); `--export-all-symbols` is not equivalent (step 4) | rzig link rule |
| strip | `-Wl,-s` at link on every OS (`zig objcopy` is ELF only) | rzig, opt-in |
| uname | `builtin.os`, `std.posix.uname` | rzig |
| curl/wget | `std.http.Client` + `std.crypto.tls` (TLS 1.2/1.3, no HTTP/2); not needed, libR has libcurl | rzig, later |
| which | `find_zig.onPath` | rzig (exists) |
| flang | no zig Fortran front end; external and optional | rzig zig-fc |

What stays R code because it is R, not an external tool: NAMESPACE and
`useDynLib`, the lazy-load DB, byte-compilation, help indices, `Meta/`,
the staged-install rename, test-load.

## Architecture

### Tiers

| tier | condition in the unpacked package | path |
|---|---|---|
| 0 | no `src/` | R only |
| 2 | `src/build.zig` exists (wins over Makevars and configure) | rzig build → zig build, tier-2 root |
| 1 | `src/` present; no `configure` (unix) or `configure.win/.ucrt` (Windows); no `src/Makefile*`; the selected `Makevars` (Windows: `.ucrt`, `.win`, then `Makevars`; unix: `Makevars`) holds only assignments | rzig build → zig build, tier-1 root |
| 3 | anything else: recipes, targets, `include`, `ifeq`, `$(shell`, configure, `src/Makefile`, Type: Frontend | today's make path when the build-tools group is present, else an error naming it |

A `cleanup` script does not make a package tier 3: R runs it only with
`--clean`/`--preclean` (install.R run_clean) and in `R CMD build`.
digest and Rcpp ship one and are tier 1 (found in the prototype; the
plan of 2026-10-08 listed cleanup as a tier-3 marker, corrected here).

Makevars grammar accepted for tier 1: blank lines, `#` comments,
backslash continuations, `NAME = | := | += | ?= value`, `$(NAME)`
references to names set in the file, in the environment, or in the
Makeconf whitelist (R_HOME, R_ARCH, R_INCLUDE_DIR, CC/CXX/CXXnn/FC,
*FLAGS, *PICFLAGS, SHLIB_OPENMP_*, BLAS_LIBS, LAPACK_LIBS, FLIBS, LIBR,
C/CXX/F/F77_VISIBILITY, SAFE_FFLAGS, SHLIB_*FLAGS, TCLTK_*, SHLIB_*LD*,
Windows LOCAL_SOFT/BINPREF). Phase-2 extensions: `$(wildcard)`,
`$(VAR:.cpp=.o)`, `$(patsubst)`, `$(subst)`. Rejected: tab-indented
lines, `name:` targets, include, conditionals, define/export/override,
`$(shell|foreach|eval|call|if)`, unquoted shell metacharacters after
expansion, unknown `$(NAME)`. Estimated share of compiled CRAN packages
at tier 1: about half by count, more by install weight (Rcpp, cli,
digest, RcppEigen, lme4, mgcv, minqa, cpp11 packages); jsonlite,
data.table, stringi, xml2, curl, openssl, Matrix, arrow, sf are tier 3.

### The flow

1. R (`tools:::.install_packages`, one hook before `run_shlib`): spawn
   `R_HOME/bin/toolchain/rzig build --src src --name <pkg> --out <staging>/libs --linkingto <dir>... -j <Ncpus>`
   with no shell. Exit 0: continue with `shlib_install` as today. Exit
   3 ("needs make"): the make path, or the tier-3 error when make and
   sh are absent. Anything else: install error.
2. rzig `build`: classify; read `R_HOME/etc/Makeconf` (Windows:
   `etc/x64/Makeconf`; simple assignments, `$(VAR)` expansion, `#`
   comments, `include vars.mk`) and the Makevars into a plan: OBJECTS,
   per-language argv as Makeconf's suffix rules compose them
   (`$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS)`, ...), `CXX_STD`/`C_STD` →
   `CXXnn`/`CXXnnSTD`, `USE_FC_TO_LINK`, LinkingTo include dirs
   (`CLINK_CPPFLAGS`), `PKG_LIBS`, `ALL_LIBS` (LIBR on linux and
   Windows, FLIBS with Fortran), the link prefix (`SHLIB_LINK`;
   winshlib's `$(SHLIB_LD) $(SHLIB_LDFLAGS) $(LDFLAGS) $(DLLFLAGS)`),
   the output `<pkg>.so|.dylib|.dll`, jobs, os, R's include dir and
   target. Word-split with shell quoting rules; a leftover
   metacharacter means tier 3.
3. rzig materialises a build root under `<staging>/.rzig/`: the helper
   files copied from `R_HOME/share/zig/rpkg/`, the chosen root as
   `build.zig` (`build_t1.zig` or `build_t2.zig`), `plan.zon`, and for
   tier 2 a `build.zig.zon` with `.pkg = .{ .path = "<rel path to src>" }`
   and a fingerprint. Then
   `zig build --build-file <root> --cache-dir <cache>/zig-build --prefix <staging> -j N -Dplan=plan.zon`
   with zig from `find_zig` (ZIG_BIN, PATH, python ziglang);
   `RZIG_TRACE` prints the line.
4. The roots. Tier 1 (`proto/rpkg/build_t1.zig`): parse the plan with
   `std.zon.parse`; per source one
   `Run(<toolchain>/zig-cc|zig-cxx|zig-fc, flags, -c, src, -o, addOutputFileArg)`
   with cwd = `src/`; then one
   `Run(<link driver>, link prefix, -o, addOutputFileArg(<pkg>.so), objects, libs)`,
   installed as `libs/<pkg>.so` under the prefix. The pattern is
   build.zig's `fortranOne` (~2728). Tier 2 (`build_t2.zig`):
   `const pkg = @import("pkg")`; `pkg.rbuild(rpkg, dep.builder, opts)`
   with the target from the plan (`x86_64-linux-gnu.2.17` + baseline,
   as floors.zig and compiler.zig spell it), and installs the returned
   library.
5. The helper (`proto/rpkg/rpkg.zig`): `rModule` = TranslateC of a
   header that defines `R_NO_REMAP` and `STRICT_R_HEADERS` and includes
   `Rinternals.h` and `R_ext/Rdynload.h`, with `R_HOME/include` on the
   include path, as `@import("R")`; `addLibrary(b, opts, .{ root_source_file, c_sources })`
   = `b.addObject` for the zig root (link_libc, pic, the R module
   imported) plus tier-1 Run steps for C sources, all linked by the
   same rzig link rule. A pure-zig package exports
   `export fn R_init_<pkg>(dll: *R.DllInfo) void` and registers its
   routines with `R.R_registerRoutines`.
6. R, in-process: everything after the native library, unchanged.

### Windows (run on kappa in step 4)

Link with a `.def` that rzig writes from the objects' COFF symbol
tables (defined external symbols, winshlib.mk's `[BCDRT]` set) unless
`<pkg>-win.def` exists (then pass it). Not `-Wl,--export-all-symbols`:
lld's auto-export skips every symbol that R.dll also exports (quadprog's
`dposl_`, a LINPACK routine libR carries too) and, in some links, leaks
mingw CRT symbols (`_CRT_INIT`, `__mingw_module_is_dll`); see step 4.
`-L R_HOME/bin/x64 -lR` as Makeconf.win's LIBR already
does; objects are `.o` as Makeconf.win names them; install `rzig.exe` beside `gcc.exe`
(main.zig already dispatches on argv[1] when argv[0] is not a tool
name); R's `system()` is CreateProcess, rzig spawns `zig.exe` with
std.process.

### Cache and cleanliness

`--cache-dir ${XDG_CACHE_HOME:-$HOME/.cache}/r-zig/zig-build`
(`%LOCALAPPDATA%/r-zig` on Windows), shared, so the build runner of the
tier-1 root compiles once per (root content, zig); the build root is
under the staging dir and goes with it; nothing is written into
`src/`. zig cc keeps its own object cache in zig's global cache, keyed
by the source path among other things (see "Measurements"). `rzig cache prune` later.

### What must remain on the R side (small)

- the hook before `run_shlib` (exit 3 falls through to make);
- a shell-free spawn primitive on unix (feat-no-host-paths S1 as its
  own patch: `posix_spawnp` in `src/unix/sys-unix.c` + `names.c`), used
  by the hook, by test-load `R_runR_deps_only`, and by
  `install.packages` → `bin/exec/R` so the `bin/R`, `Rcmd`, `INSTALL`
  shell scripts are bypassed; Windows already spawns without a shell;
- `uname -a` in `patch_rpaths` → `Sys.info()`; shlib-clean → `unlink`;
  `make compilers` and the compilers' `--version` → one `rzig --version`;
  symbols.rds only when R CMD check asks (skipped without nm);
- the tier-3 message in patch 0009's style with
  `R_ZIG_BUILD_TOOLS_HINT`; `R_ZIG_PKG_BUILDER=auto|zig|make` for parity
  runs and bisecting.

## Milestone 1: what was run (linux-64, gamma, 2026-10-09)

Dev tree: `pixi run build` of main 7a3004d in the main checkout
(`dist/R-4.6.1-slim-zig`, conda-forge zig 0.16.0, flang 23.1.1).
Fixtures from CRAN: cli 3.6.6 (C, `$(C_VISIBILITY)`, `-lpthread`),
digest (C, `-I.`, a `cleanup` script, `Makevars.win`), quadprog (`.f`
through zig-fc, `$(BLAS_LIBS) $(FLIBS)`, PKG_FFLAGS with
`$(F77_VISIBILITY) $(FPICFLAGS) $(SAFE_FFLAGS)`), mgcv (C with
`$(SHLIB_OPENMP_CFLAGS)` and `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`),
Rcpp (C++, `-I../inst/include/`, a `cleanup` script). Every Makevars is
assignment-only: all five are tier 1.

The prototype (`proto/` here, copied from the session's scratch):
- `proto/mkplan.sh`: PROTOTYPE ONLY. Writes `plan.zon` from the dev
  tree's Makeconf and the package's Makevars using make recipes that
  `printf` (not GNU make 4's `$(file)`: macOS ships make 3.81) the exact strings `.shlib_internal`'s make
  invocation would use (its include chain and command-line overrides:
  `SHLIB_LDFLAGS/SHLIB_LD` for C++, `SHLIB_LIBADD` with FLIBS for
  Fortran, `OBJECTS`, `CLINK_CPPFLAGS`). This is what rzig's evaluator
  must reproduce without make; the real work of milestone 2.
- `proto/rpkg/build_t1.zig`, `build_t2.zig`, `rpkg.zig`,
  `build_t2.zig.zon` (the root's zon; `.pkg` is a relative path to the
  package's `src/`). The plan names the tool files (`cc_tool`,
  `cxx_tool`, `fc_tool`; defaults zig-cc/zig-cxx/zig-fc, Windows
  gcc.exe/g++.exe/zig-fc.exe) and `readPlan` raises
  `@setEvalBranchQuota`: std.zon.parse's inline switch over the struct's
  fields exceeds the default 1000 at this field count.
- `proto/hosts/`: the step-4 drivers (`omicron.sh`, `kappa-step[123].bat`),
  the hand-derived Windows plans (`plans-win/`), the `.def` files, the
  tier-2 root zon, and `results/` (host logs and Windows export lists).
  Kept in the branch's history for the record; see "Cleanup before
  merge".
- `proto/zighello/`: the tier-2 hello-world package (DESCRIPTION,
  NAMESPACE with `useDynLib(zighello, .registration = TRUE, .fixes = "C_")`,
  `R/hello.R`, `src/build.zig`, `src/hello.zig`).
- `proto/plan-cli.example.zon`: cli's generated plan. `proto/smoke.R`.

Reference: each fixture installed with the make path
(`R CMD INSTALL --no-test-load`, `RZIG_TRACE=1`) into `lib-make`; the
zig-built `libs/<pkg>.so` then replaced the make-built one in a copy
(`lib-zig`); both libraries loaded and exercised by `smoke.R`.

## Results

### Tier 1: five of five build, load and match the make build

| package | sources | zig build | exports (`nm -D --defined-only`) | rzig argv vs make | smoke (make = zig) | unload, exit |
|---|---|---|---|---|---|---|
| cli | 26 C | ok | identical, 185 | identical | `rule()`, `hash_md5("abc")` = 900150…8e17f72 | 0 |
| digest | 19 C (link via zig-cxx: a `.cpp` is present) | ok | identical, 127 | identical | sha256("abc") = ba7816bf… | 0 |
| quadprog | 7 Fortran (zig-fc = flang) | ok | identical, 6 | identical | `solve.QP` → (1, 1) | 0 |
| mgcv | 18 C, `-fopenmp`, LAPACK/BLAS/FLIBS | ok | identical, 318 | identical | `gam()` dev.expl 0.70784, edf 13.8873 | 0 |
| Rcpp | 6 C++ | ok | identical, 642 | identical | 23 registered `.Call` routines | 0 |

"rzig argv vs make": the `RZIG_TRACE` final `zig cc|c++` lines of both
runs (the `--version` probes excluded), each line's tokens sorted,
source and object paths reduced to their base names. Every compile line
is identical token for token. The link line differs only in the object
paths: relative under make, zig's cache paths under zig build.

### Tier 2: zighello builds, loads, runs, unloads

`zighello.so` (16 KB): `R_init_zighello` exported, NEEDED libR.so;
`library(zighello); hello(21)` → 42; `getDLLRegisteredRoutines` lists
`hello`; `unloadNamespace`, exit 0. Installed by `R CMD INSTALL` of a
copy without `src/` plus the library dropped into `libs/` (R has no
hook yet). The package's `src/build.zig` is 10 lines; `hello.zig` 17.

Verified in the process: `@import("pkg")` of a path dependency's
build.zig from the root works (`dependencyFromBuildZig`); steps created
on `dep.builder` and installed by the root work; the zon needs
`.fingerprint` (zig prints the value to use); `R.SEXP`, `R.Rf_asInteger`,
`R.Rf_ScalarInteger`, `R.R_CallMethodDef`, `R.DllInfo`,
`R.R_registerRoutines`, `R.R_useDynamicSymbols`, `R.FALSE` all translate
as used. Not yet exercised: `ISNAN`/`R_FINITE`, `Rcomplex` (the planned
`r_shim.c`), and C sources beside zig sources.

### Measurements (x86_64 linux, 8 jobs, conda-forge zig 0.16.0)

| what | time |
|---|---|
| build runner compile for the tier-1 root (once per root content and local cache dir) | 3.5-4 s |
| zig build, warm (nothing to do), without `pixi run` | 0.10 s |
| `pixi run` wrapper overhead | 0.16 s |
| cli, zig build steady state (runner cached, zig's object cache empty) | 5.07 s |
| cli, make -j8 (object cache empty) | 5.23 s |
| cli, zig build, everything cached | 0.83 s |
| cli, make -j8, objects cached by zig cc | 0.54 s |
| Rcpp, zig build steady state | 20.24 s |
| Rcpp, make -j8 | 20.85 s |
| Rcpp, both cached | 0.64 s vs 0.54 s |
| first zig build with a fresh **global** cache (compiler_rt, libc stubs; make pays the same) | +7 s |
| first tier-2 build on this machine: zig compiles its `translate-c` tool into the global cache | 48 s once; 3.8 s after, of which translate-c 99 ms, object 175 ms, link 116 ms |
| local cache after two packages | 41 MB; one runner binary |

Cache sharing: confirmed. quadprog on a fresh local cache 4.04 s, then
cli on the same cache 0.65 s (26 compiles, objects served by zig cc's
global cache); `find <cache> -name build -type f` = 1.

zig cc's object cache (global, `~/.cache/zig`) is keyed by the source
path: the make path (`-c ansi.c` in `src/`) and the zig build path
(absolute path) do not share entries, and a copy of the package in
another directory recompiles. This only matters for benchmarks and for
the choice of build-root paths.

### Assumptions checked

| assumption (plan of 2026-10-08) | result |
|---|---|
| std.Build Run steps calling rzig reproduce make's compile lines | yes, identical argv on five packages |
| one build runner per root content, shared across packages via `--cache-dir` | yes |
| runner compile cost small | 3.5-4 s once; then 0.1 s |
| `rbuild(dep.builder)` pattern, `@import` of the package's build.zig | works |
| zig object (`addObject`, ReleaseFast, baseline, glibc 2.17) linked by `zig cc -shared` through rzig | works; libR resolved, no extra runtime |
| R headers under translate-c | the used subset translates; macro helpers untested |
| absolute `.path` in zon | not tried; relative path used (as planned) |
| macOS target query `aarch64-native.13.0` + baseline = rzig's `-target aarch64-native.13.0 -mcpu=baseline` | yes: LC_BUILD_VERSION minos 13.0 on both paths, exports and argv identical (step 4) |
| Windows: `--export-all-symbols` replaces the nm \| sed `.def` | **refuted** for the general case: identical for cli (187), drops `dposl_` for quadprog, leaks two CRT symbols for zighello; an explicit `.def` through zig cc is exact (step 4) |
| Windows: zig `addObject` + `zig cc -shared` exports `R_init_<pkg>` | yes (with the `.def`: exactly that one symbol) |
| PE timestamp / reproducible DLL bytes | not checked |
| `cleanup` marks tier 3 | refuted: only with `--clean`/`--preclean` |

### Step 4: macOS (omicron) and Windows (kappa), 2026-10-09

Same prototype, same fixtures (cli, quadprog, zighello), the hosts'
existing dists (omicron `~/r-zig-pixi/dist/R-4.6.1-slim-zig`, kappa
`C:\Users\admin\r-zig-pixi\dist\R-4.6.1-slim-zig\Library`, both built
2026-10-01..04, conda-forge zig 0.16.0, flang 23.1.1). Scratch dirs
deleted afterwards. Drivers and raw results in `proto/hosts/`.

**omicron, macOS 26.4.1 arm64** (`omicron.sh`; the reference make path
and `mkplan.sh` ran with the pixi env's GNU make 4.4.1, so the printf
dump is not yet exercised on make 3.81):

| check | result |
|---|---|
| cli, quadprog: zig build | ok; exports (`nm -gU`) identical to make (3 and 8 symbols); rzig argv identical token for token (zig-cc and zig-fc) |
| LC_BUILD_VERSION | minos 13.0, sdk 26.4 on make's and zig's libraries alike (`aarch64-native.13.0` + baseline = rzig) |
| smoke lib-make vs lib-zig | identical (`rule()`, md5, `solve.QP` → 1 1), unload 0 |
| zighello | builds (`aarch64-native.13.0` ReleaseFast object, 50 KB dylib), `hello(21)` → 42, unload 0 |
| timing | tier-1 cold incl. runner compile 7.0 s (cli), quadprog on the same cache 0.7 s, warm 0.17 s; tier-2 first 26.9 s (translate-c tool 21 s), then 0.25 s; cache 43 MB |
| finding | the zig-linked dylib's install name (LC_ID_DYLIB) is the absolute cache path of the link output; make's is `cli.so`. Harmless for dlopen, but M2's macOS link rule passes `-Wl,-install_name,<pkg>.so` for parity |

**kappa, Windows 11 22621 x64** (`kappa-step[123].bat`; plans derived
by hand from the make log and Makeconf.win since mkplan.sh needs sh):

| check | result |
|---|---|
| cli: zig build | ok (29 steps); DLL imports identical to make's; `library(cli)` smoke identical, 49 registered `.Call` routines both |
| cli exports: make's nm \| sed `.def` vs `--export-all-symbols` | identical, 187 |
| quadprog: zig build (zig-fc = flang.exe, `-lflang_rt.runtime -lc++`) | ok; `solve.QP` → 1 1; `is.loaded("qpgen2")` TRUE |
| quadprog exports with `--export-all-symbols` | 5: `dposl_` missing although util.o defines it. R.dll exports `dposl_` too, and lld's auto-export skips a symbol whose `__imp_` twin is defined |
| zighello exports with `--export-all-symbols` | 3: `R_init_zighello` plus `_CRT_INIT`, `__mingw_module_is_dll` from zig's mingw CRT (cli's link, which has `-lpthread`, did not leak them) |
| relink with an explicit `.def` (step 3) | quadprog 6 = the linux set; zighello exactly `R_init_zighello`. zig cc accepts the `.def` as an input like the make path's `tmp.def` |
| zighello | `hello(21)` → 42, `getDLLRegisteredRoutines` lists `hello`, unload ok |
| timing | reference `R CMD INSTALL cli` on a cold zig global cache 88 s; zig build cli 25 s cold (runner + 26 compiles), 0.8 s warm; quadprog 36 s (first `-lc++` link builds libc++ into the global cache); zighello 66 s first (translate-c tool), 0.24 s after |
| observed, out of scope | the make path cannot install Fortran packages on kappa: install.R passes `SHLIB_LIBADD='$(FLIBS) $(FCLIBS_XTRA)'` and kappa's make.exe (pixi global, not an MSYS build) keeps the POSIX quotes: `No rule to make target '$(FCLIBS_XTRA)''`. Another sh/make quoting hazard the zig path removes |

### Not done in milestone 1

- PE timestamp and byte-reproducibility of the DLLs; a `cleanup`-free
  tier-3 negative; `r_shim.c` macro helpers.
- The hook in install.R, the spawn primitive, rzig's evaluator: by
  design (milestone 2 and 3).

## Go/no-go and the next milestone

Go. The orchestration costs the same as make in steady state, less in
rebuilds, and removes make, sh, nm and sed from tiers 0 to 2 with one
fixed root and one helper, on all three OSes (step 4). Recommended
next milestone (M2): rzig `build` (classify, Makeconf and Makevars
evaluator, plan, build root, `zig build`), the helper installed to
`R_HOME/share/zig/rpkg` by build.zig, the `rzig` install name, exit
code 3; the Windows link writes the `.def` from the objects (std.coff)
and the macOS link passes `-install_name`; its acceptance test is
`mkplan.sh`'s output reproduced token for token on the five fixtures
without make, with the step-4 export lists as the Windows oracle. M3 the R side (hook,
spawn, `uname`, shlib-clean, compiler version, `packages2.R`), M4
parity in contract-test.sh and hermetic-check.sh, M5 hosts, stress
suite through the zig path, docs.

## Milestone 2 (2026-10-09): `rzig build`

What M1 did by hand and with make (`proto/mkplan.sh`), rzig now does
alone. New in `zigbuild/tools/rzig/` (2 577 lines with tests) and
`zigbuild/rpkg/`:

| file | what |
|---|---|
| `makefile.zig` | the part of GNU make R's build reads without running a recipe: `=` `:=` `::=` `+=` `?=`, `#` comments and `\#`, backslash continuations, `$(VAR)` `${VAR}` `$x` `$$`, substitution references `$(V:a=b)` and `$(V:%.a=%.b)`, the functions `subst patsubst strip findstring filter filter-out sort word wordlist words firstword lastword dir notdir suffix basename addsuffix addprefix join wildcard if or and value origin flavor`, `ifdef ifndef ifeq ifneq else endif`, `include -include sinclude`, `export`, `override`; automatic variables expand to nothing (Makeconf.win's `$($*-CPPFLAGS)`). Precedence as make's: command line over files over environment, `override` over the command line, `?=` only when unset. Two modes: `makeconf` skips rules and recipes (Makeconf, shlib.mk, the site and user Makevars); `makevars` accepts assignments only. `$(shell)`, `foreach`, `call`, `eval`, `define`, `!=` and a reference loop are refused with a reason |
| `shellwords.zig` | the words a POSIX shell hands the compiler from one recipe line: `'…'`, `"…"`, backslashes; an unquoted `$ \` \| & ; < > ( ) * ? [`, a `#` or `~` at a word's start, is refused |
| `pkgplan.zig` | the tiers (`classify`) and the plan: install.R's `.shlib_internal` order (the package's Makevars, Makeconf, Makevars.site, shlib.mk / winshlib.mk, the user Makevars) and its command-line overrides (`SHLIB`, `OBJECTS` unless the Makevars sets it, the C++ standard from `CXX_STD`/`USE_CXXnn`/`R_PKG_CXX_STD` with `CXX=$(CXXnn) $(CXXnnSTD)` and the `SHLIB_CXXnnLD` link, the default C++ link, `USE_FC_TO_LINK`, `SHLIB_LIBADD` with `$(FLIBS) $(FCLIBS_XTRA)` for Fortran, `CCnn`/`CnnFLAGS`, `P_FCFLAGS`, `WIN=64 TCLBIN=`, `DEBUG=T`, `LTO`/`LTO_FC`), then `$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS)` and its siblings, `$(SHLIB_LINK)` (winshlib's `$(SHLIB_LD) $(SHLIB_LDFLAGS) $(LDFLAGS) $(DLLFLAGS)` on Windows), `$(ALL_LIBS)`, word-split. Every compiler on a line that is used must be a file of `R_HOME/bin/toolchain` (else: needs make, as with `CC = ccache gcc` in `~/.R/Makevars`). Objects map to sources in `.SUFFIXES` order; an object without a source needs make. macOS appends `-Wl,-install_name,<pkg>.so`; Windows sets `def` (or `win_def` when `<pkg>-win.def` exists) and `libs/x64` |
| `pkgbuild.zig` | `rzig build --pkg <dir> --out <dir> [--name] [--linkingto <dir>]… [--cxx-std NN] [--c-std NN] [--use-lto yes\|no] [--debug] [-j N] [--r-home] [--rpkg-dir] [--cache-dir] [--keep-root]`; `--plan-only` prints plan.zon, `--classify` the tier. Exit 0 built or nothing to build, **3 needs make** (why, on stderr), 2 usage, 1 failed. Writes `<out>/.rzig/plan.zon`; tier 2 also copies the three root files there as `build.zig`, `build_t1.zig`, `rpkg.zig` and writes `build.zig.zon` with `.pkg = .{ .path = "<relative src>" }`; runs `zig build --build-file … --cache-dir <cache>/zig-build --prefix <out> -Dplan=… [-jN]` with zig from find_zig; removes `.rzig` after success (`--keep-root`, `RZIG_KEEP_ROOT=1` keep it). Site and user Makevars found as install.R does (`R_MAKEVARS_SITE`, `etc<R_ARCH>/Makevars.site`; `R_MAKEVARS_USER`, `~/.R/Makevars.ucrt`/`.win64`/`.win` on Windows, `~/.R/Makevars-<R_PLATFORM>`, `~/.R/Makevars`) |
| `def.zig` | `rzig def -o <pkg>.def <objects>`: winshlib.mk's `nm \| sed -n 's/^.* [BCDRT] / /p'` from the objects' COFF symbol tables (std.coff's records at the object's offsets; `Coff.init` reads images only): storage class EXTERNAL, defined in a CODE, INITIALIZED_DATA or UNINITIALIZED_DATA section that is not LNK_INFO/LNK_REMOVE/MEM_DISCARDABLE, or a common; not undefined, not weak, not the compiler's `.refptr.*` / `.weak.*` helpers (nm lists those as R and T, the make path's DLLs do not export them: cli's 187); de-duplicated. Test object `testdata/win-syms.{c,o}` (zig cc, x86_64-windows-gnu) holds every kind |
| `main.zig` | `rzig build` and `rzig def` dispatch only when rzig is started as itself (never through a compiler's name, where `build` could be a source file) |
| `zigbuild/rpkg/build_t1.zig`, `build_t2.zig`, `rpkg.zig` | the M1 roots, now shipped: `libs_dir` from the plan, the `def` Run step (`rzig def`) or the package's `-win.def` before the objects in the link, `rpkg.addLibrary` with `cxx_sources` and extra imports; installed to `R_HOME/share/zig/rpkg` by build.zig's `installRzig`, which also installs rzig as `rzig` / `rzig.exe`; `scripts/verify-tree.sh` checks both |

`compiler.linux_target` and `darwin.triple` became `pub` (the tier-2
target string). No change to R, to the compiler rules, or to any
Makeconf.

### Acceptance (linux-64, gamma, 2026-10-09, dist of main 7a3004d)

The oracle is `proto/mkplan.sh` (make's own expansion) run with
`LC_ALL=C`, so that `ls` lists sources in byte order as rzig does
(R's `dir()` collates by locale; the order only moves objects on the
link line). Compared field by field after parsing both ZON files
(name, output, link driver, sources with language and object, cc, cxx,
fc, f9x, link, libs, env):

| package | `rzig build --plan-only` vs mkplan.sh | `rzig build` | exports vs make (`nm -D --defined-only`) | cold, 8 jobs | smoke |
|---|---|---|---|---|---|
| cli | identical, 26 sources | ok | identical, 185 | 8.1 s (runner compile included) | `rule()`, md5 = make |
| digest | identical, 19 | ok | identical, 127 | 1.8 s | sha256 = make |
| quadprog | identical, 5 | ok | identical, 6 | 0.7 s | `solve.QP` → 1 1 |
| mgcv | identical, 17 | ok | identical, 318 | 3.9 s | dev.expl 0.70784, edf 13.8873 |
| Rcpp | identical, 6 | ok | identical, 642 | 8.6 s | 23 `.Call` routines |

Warm `rzig build` of cli: 0.14 s. Tier 2: `rzig build` of
`proto/zighello` materialises the root, builds in 3.9 s (translate-c
tool already in the global cache), 0.26 s warm, `hello(21)` → 42,
`.rzig` removed. Negatives, all exit 3 with the reason on stderr:
a `configure` script; a Makevars with `all: $(SHLIB) extra` and a
recipe; `PKG_LIBS = $(shell pkg-config --libs zlib)`. A package without
`src/` exits 0 and builds nothing. `rzig def` on the test object lists
the five exported names. Unit tests: 93 in `zig build --build-file
zigbuild/tools/rzig/build.zig test` (the planner's run on a modelled
R_HOME for linux, Windows and macOS). The repo's build.zig compiles
with the new install steps (its run needs the pixi env; `pixi run build`
not repeated here).

Observed: with `RZIG_TRACE=1`, zig build echoes every step whose rzig
wrote to stderr under the heading `failed command:` although the step
passed (build_runner.zig prints any stderr that way); exit code and
outputs are right. Noted in main.zig's header.

### Not in M2

- R does not call `rzig build` yet: the install.R hook, the exit-3 fall
  through, the spawn primitive (M3). Until then `rzig build` runs by
  hand, as above.
- `rzig build` itself has run on linux only; the roots ran on macOS and
  Windows in M1 step 4, the planner's Windows and macOS paths are unit
  tests on a modelled Makeconf (M5 runs the real `etc/x64/Makeconf`
  and the `.def` link on kappa, the install name on omicron).
- `rzig --version` (compiler report for install.R), `rzig cache prune`,
  the M4 parity script that replaces mkplan.sh as the asserted oracle
  (the ZON comparison above was a scratch script).

## Milestone 3 (2026-10-09): R calls `rzig build`

Two R source patches, applied by scripts/zig-build.sh with the series:

| patch | what |
|---|---|
| `0012-spawn-wait.patch` | `.Internal(spawnWait(argv, timeout))` on unix: `R_system_timeout`'s fork-and-wait machinery (timeout, signals, process group) with `execvp(argv[0], argv)` in place of `execl("/bin/sh", "-c", cmd)`; the shared body is `R_run_timeout(cmd, argv, timeout)`. Status as `system()`'s: exit code, 127 when the program cannot start, 124 after the timeout. Not defined on Windows, whose `system2()` already spawns without a shell. feat-no-host-paths S1, the part R CMD INSTALL needs |
| `0013-install-rzig-build.patch` | install.R: `rzig_build()` before `run_shlib`'s make path runs `R_HOME/bin/toolchain/rzig build --pkg .. --src . --out . --flat --name <pkg> [--use-lto yes\|no] [--c-std NN] [--debug] [-j N]` from `src/` (unix through `spawnWait`, Windows through `system2`), then `shlib_install()` as for make (so `install.libs.R`, strip and dSYM behave as before). Exit 3 falls through to the make path. `R_ZIG_PKG_BUILDER=auto\|zig\|make` (zig: a tier-3 package is an error naming it; make: rzig is never asked). `R_ZIG_JOBS`, else `MAKEFLAGS`' `-j`, is the job count. A `src/build.zig` alone counts as compiled code (install.R's `allfiles`), so a zig package without C sources reaches the hook. `patch_rpaths` reads the OS from `Sys.info()` instead of `uname -a`. CLINK_CPPFLAGS and R_PKG_CXX_STD reach rzig through the environment install.R already sets |

rzig side: `--src <dir>` (install.R's `src-<arch>` copies), `--flat`
(the library in `<out>` itself, where make leaves it), the compiler
report (`using C compiler: 'clang version …'`, `using Fortran compiler:
'flang version …'`, `using zig: '0.16.0'` for tier 2, from the
toolchain's `--version`: R CMD check greps these from the install log),
the build root removed after a failed build too (`--keep-root` /
`RZIG_KEEP_ROOT` keep it), and the empty `.zig-cache` zig build leaves in
a path dependency's directory removed from the package's `src/` after a
tier-2 build when it was not there before.

### Acceptance (linux-64, gamma, 2026-10-09; the worktree's own
`pixi run build`, dist with patches 0001-0013)

`R CMD INSTALL --no-test-load -l <lib> <CRAN tarball>`, with `RZIG_TRACE=1`
once (the zig path) and `R_ZIG_PKG_BUILDER=make` once (the make path):

| package | zig path | make path | exports | smoke |
|---|---|---|---|---|
| cli | tier 1, 7.0 s, no make line in the log | 8.1 s | identical, 185 | identical |
| digest | tier 1, 2.5 s | 2.9 s | identical, 127 | identical |
| quadprog | tier 1, 1.5 s | 2.2 s | identical, 6 | identical |
| mgcv | tier 1, 34.2 s (first OpenMP compiles) | 42.9 s | identical, 318 | |
| Rcpp | tier 1, 9.5 s | 3.7 s (zig cc's object cache warm from the zig run) | identical, 642 | identical |

Every zig-path log carries `using C compiler` (and Fortran) lines and no
make output. `spawnWait`: `true` 0, `false` 1, a missing program 127, a
timed-out `sleep` 124 with R's warning. A cli copy with a `configure`
script falls through: the log says `rzig build: cli needs make: a
configure script`, then make builds it; with `R_ZIG_PKG_BUILDER=zig` it
stops with `ERROR: this package needs make, and R_ZIG_PKG_BUILDER is
'zig'`. **No make on PATH** (`env -i`, PATH = a directory holding only
`sh`, `zig`, `flang`): quadprog and cli install, cli with its test load.
`sh` is still needed by `bin/R` itself (feat-no-host-paths C), `zig` by
rzig (ZIG_BIN, PATH, or python's ziglang), `flang` by zig-fc.
`R CMD INSTALL proto/zighello` (a directory, test load included): `**
libs`, `using zig: '0.16.0'`, `rzig build: tier 2`, `hello(21)` → 42;
afterwards `src/` holds `build.zig`, `hello.zig` and `zighello.so` (as
make would leave the library), no `.rzig`, no `.zig-cache`.

### Not in M3

- `R_runR` (test load) and `install.packages()`'s start of `R CMD
  INSTALL` still spawn through `system2()` and `/bin/sh`: they need
  stdin and output redirection, the rest of feat-no-host-paths S1/S2.
- Windows and macOS runs of the patched R (M5): the hook's Windows
  branch (`system2(rzig.exe, shQuote(args))`, `src-x64` copies) is
  untested there.
- `symbols.rds` (R CMD check's `_R_SHLIB_BUILD_OBJECTS_SYMBOL_TABLES_`)
  is not produced on the zig path; check falls back to the library.

## Milestone 5 (2026-10-10): the patched R on macOS and Windows

The branch (commit 4a167f5) synced to the two test hosts (omicron
`~/r-zig-pixi`, kappa `C:\Users\admin\r-zig-pixi`, working copies as
before), R rebuilt there with `pixi run build` (the pixi lock of main
b490bdf; conda-forge zig 0.16.0, flang 23.1.1), then the M3 acceptance
run against those dists: `R CMD INSTALL -l <lib> <CRAN tarball>` with the
test load, `RZIG_TRACE=1` on both paths, `R_ZIG_PKG_BUILDER=make` for the
reference. Drivers `proto/hosts/m5-omicron.sh`, `m5-kappa.bat` +
`m5-kappa.R`; raw output in `proto/hosts/results/m5-*.log`. Scratch
(`~/rz-m5`, `C:\Users\admin\rz-m5`) deleted afterwards. The argv
comparison takes rzig's `RZIG_TRACE` command lines from both logs
(basenames, sorted; the `self` and `environment` lines dropped).

### omicron, macOS 26.4.1 arm64

Rebuild 5 min (incremental). `bin/toolchain/` holds `rzig`,
`share/zig/rpkg/` the three roots. `spawnWait`: 0, 1, 127, 124 with the
timeout warning, as on linux.

| package | zig path | make path | exports (`nm -gU`) | rzig argv | install name, minos |
|---|---|---|---|---|---|
| cli | tier 1, 11.1 s, no make line | 10.4 s | identical, 3 | identical, 27 lines | `cli.so` both, 13.0 both |
| digest | tier 1, 3.4 s | 7.3 s | identical, 129 | identical, 20 | `digest.so`, 13.0 |
| quadprog | tier 1, 2.5 s | 3.0 s | identical, 8 | identical, 6 | `quadprog.so`, 13.0; deps `@rpath/libRblas.dylib`, `@rpath/libR.dylib` |
| Rcpp | tier 1, 6.2 s | 11.2 s | identical, 228 | identical, 7 | `Rcpp.so`, 13.0 |

"identical" argv means every compile and the link are the same words,
except the one token rzig adds on macOS, `-Wl,-install_name,<pkg>.so`
(M1 finding (b)): with it the zig-linked library's LC_ID_DYLIB is
`<pkg>.so`, as make's. Smoke (`proto/smoke.R`) identical on both
libraries, unload 0. zighello from its directory: 7.7 s with the test
load (`using zig: '0.16.0'`, `rzig build: tier 2`), 1.7 s again,
`hello(21)` → 42, exports `_R_init_zighello` plus the dylib's own
`___dso_handle`/`__mh_dylib_header`, install name `zighello.so`, minos
13.0. A cli copy with `configure` falls through (`rzig build: cli needs
make: a configure script`, make builds it, exit 0);
`R_ZIG_PKG_BUILDER=zig` stops with the ERROR. **No make on PATH**
(`env -i`, PATH = `sh`, `zig`, `flang`): quadprog and cli (with test
load) install. Cache `~/.cache/r-zig` 65 MB after the run.

### kappa, Windows 11 22621 x64

Rebuild 35 min (the whole series re-extracted). `bin/toolchain/` holds
`rzig.exe` beside `gcc.exe`, `g++.exe`, `zig-fc.exe` and the binutils
names; `share/zig/rpkg/` the three roots. Times from the driver's
`%TIME%` stamps, test load included; the first zig-path install also
compiles the build runner and fills a cold zig cache.

| package | zig path | make path (kappa: pixi's make.exe and sh.exe, no sed, no Rtools) | exports (`objdump -p`) | rzig argv |
|---|---|---|---|---|
| cli | tier 1, 79 s | 37 s | zig 185 through `rzig def`; make 187: `tmp.def` is empty because `sed` is missing, so lld auto-exports and adds `_CRT_INIT`, `__mingw_module_is_dll`; imports identical (`R.dll`, `KERNEL32.dll`, `api-ms-win-crt-*`) | identical, 27 lines, except `cli.def` for `tmp.def` on the link line |
| digest | tier 1, 37 s | fails: `sed: command not found`, then `g++.exe -std=gnu++20  : No such file or directory` (SHLIB_CXXLD's quoting through kappa's non-MSYS make and sh) | zig 129 | 19 compile lines identical; make has no link line |
| quadprog | tier 1, 3 s | fails: `No rule to make target '$(FCLIBS_XTRA)''` (M1 finding (c)) | `R_init_quadprog` alone: the package ships `src/quadprog-win.def`, which winshlib.mk links instead of the nm \| sed list, and rzig does the same; `solve.QP` → 1 1 | 6 lines (make: none) |
| Rcpp | tier 1, 21 s | fails as digest | zig 738 | 6 compile lines identical |

The cli export set settles M1's Windows question: `rzig def`'s 185
symbols are exactly the M1 "make" list (`proto/hosts/results/kappa-exports-cli-make.txt`,
187) without `_CRT_INIT` and `__mingw_module_is_dll`. Those two were
never in a nm \| sed `.def`: they came from the same empty `tmp.def`, so
M1's "make vs `--export-all-symbols` identical, 187" compared two
auto-exports. On a host with Rtools' sed, make's DLL exports the 185.
Smoke (`proto/smoke.R`) on the zig library: the same values as linux and
macOS, `*.dll` loaded, unload 0 (the make library lacks digest, so the
make smoke stops there). zighello from its directory: 64 s with the test
load (the translate-c tool's first compile), 1.5 s again, `hello(21L)` →
42, `getDLLRegisteredRoutines` lists `hello`, exports exactly
`R_init_zighello`. A cli copy with `configure.win` falls through (`rzig
build: cli needs make: a configure.win script`, make's C link works on
kappa, exit 0); `R_ZIG_PKG_BUILDER=zig` stops with the ERROR. **No make
or sh on PATH** (PATH = `System32` plus a directory holding copies of
`flang.exe`, `flang-new.exe` and their two `.cfg` files; `ZIG_BIN` names
the env's zig; `where make sh` finds nothing): quadprog and cli (with
test load) install, the log reporting `clang version 21.1.8`, `flang
version 23.1.1`, `tier 1`. Cache `%LOCALAPPDATA%\r-zig\zig-build`.

Observed: the Fortran link carries `-lc++` twice (Makeconf's FLIBS has
one, rzig's flang-rt rule adds one); harmless and the same on both
paths, since the rule is rzig's. `rzig def` prints nothing under
`RZIG_TRACE`; the evidence of the `.def` link is `<pkg>.def` on the link
line.

### Not in M5

- The stress suite through the zig path, and the docs entries in the
  feat-no-host-paths and feat-standalone-toolchain records.
- `R_runR`/`install.packages()` spawns, `symbols.rds`, `rzig --version`
  (as "Not in M3").

## Cleanup before merge

The milestone-1 commit keeps every prototype file so the record is
complete in history. The last commit of the PR removes what M2 makes
redundant and keeps what M2 and M4 build on (decided 2026-10-09):

| remove in the last commit | why |
|---|---|
| `proto/hosts/results/` | raw host logs and export lists (M1 step 4 and M5); the tables above carry every number |
| `proto/hosts/plans-win/` | hand-derived Windows plans; `rzig build` generates them |
| `proto/hosts/omicron.sh`, `kappa-step[123].bat`, `smoke-win.R`, `root-t2.build.zig.zon` | host-specific drivers for the prototype; superseded by the M5 drivers, which run through `R CMD INSTALL` |
| `proto/mkplan.sh`, `proto/plan-cli.example.zon` | M2 reproduces them (acceptance above); removed once M4 asserts it in a script of the repo |
| `proto/rpkg/` | superseded by `zigbuild/rpkg/` in M2 |

Keep: `PLAN.md`, `proto/zighello/` (M4 fixture), `proto/hosts/defs/*.def`
(the Windows export oracle for `rzig def`), `proto/smoke.R`, and the M5
host drivers `proto/hosts/m5-omicron.sh`, `m5-kappa.bat`, `m5-kappa.R`,
`t2.R` (the rerun recipe for the hosts).

    git rm -r -q .github/devdocs/feat-zig-pkg-build/proto/hosts/{results,plans-win} \
      .github/devdocs/feat-zig-pkg-build/proto/hosts/{omicron.sh,kappa-step1.bat,kappa-step2.bat,kappa-step3.bat,smoke-win.R,root-t2.build.zig.zon} \
      .github/devdocs/feat-zig-pkg-build/proto/{mkplan.sh,plan-cli.example.zon} \
      .github/devdocs/feat-zig-pkg-build/proto/rpkg

Then drop the prototype part of the rerun section below.

## How to rerun

M3 and M5, with a dist of this branch (`pixi run build`) and the pixi
env's zig and flang on PATH (any OS; `R` is the dist's `bin/R`, on
Windows `bin\x64\Rcmd.exe INSTALL`):

    RZIG_TRACE=1 R CMD INSTALL -l <lib> <pkg.tar.gz>             # zig path: the log says `rzig build: tier N`
    R_ZIG_PKG_BUILDER=make R CMD INSTALL -l <lib> <pkg.tar.gz>   # the make reference
    R CMD INSTALL -l <lib> .github/devdocs/feat-zig-pkg-build/proto/zighello   # tier 2
    # hosts: proto/hosts/m5-omicron.sh (scratch ~/rz-m5 with pkgs/{cli,digest,quadprog,Rcpp}.tar.gz);
    # m5-kappa.bat with m5-kappa.R, proto/smoke.R and proto/hosts/t2.R in C:\Users\admin\rz-m5

M2, with a built dist (`pixi run build`) and the pixi env's zig and
flang on PATH:

    R=<dist>/R-4.6.1-slim-zig/lib/R
    zig build --build-file zigbuild/tools/rzig/build.zig --prefix /tmp/rz   # or $R/bin/toolchain/rzig
    R_HOME=$R /tmp/rz/bin/rzig build --pkg <unpacked pkg> --plan-only          # the plan
    R_HOME=$R RZIG_TRACE=1 /tmp/rz/bin/rzig build --pkg <pkg> --out /tmp/out/<pkg> \
        --rpkg-dir zigbuild/rpkg --cache-dir /tmp/zc -j8                        # -> /tmp/out/<pkg>/libs/<pkg>.so
    LC_ALL=C bash proto/mkplan.sh $R <pkg>/src <pkg> plan-make.zon             # the oracle (needs make)
    zig build --build-file zigbuild/tools/rzig/build.zig test                 # unit tests

The M1 prototype:

    R=<dist>/R-4.6.1-slim-zig/lib/R          # pixi run build
    bash proto/mkplan.sh $R <pkg>/src <pkg> plan.zon   # needs make (prototype only)
    cd proto/rpkg && zig build --build-file build_t1.zig --cache-dir /tmp/zc -Dplan=plan.zon --prefix /tmp/out -j8
    # tier 2: a root dir with build_t2.zig as build.zig, build_t1.zig, rpkg.zig,
    # build_t2.zig.zon as build.zig.zon (fix the .pkg path; proto/hosts/root-t2.build.zig.zon
    # is the one used on the hosts), plan.zon with .target and .r_include set;
    # then zig build as above.
    # hosts: proto/hosts/omicron.sh (bundle = proto/, root-t2/, cli and quadprog
    # tarballs in ~/rz-pkgbuild); kappa-step1.bat (make reference), step2 (zig
    # builds + smoke + tier 2), step3 (.def relinks); plans in proto/hosts/plans-win.
