# feat-zig-pkg-build: R installs source packages with zig alone

Branch feat-zig-pkg-build, from main 7a3004d, rebased on b490bdf.
Milestone 1 (2026-10-09): the design, a hand-run prototype on linux-64,
and measurements; no file of R, rzig or build.zig changed. Milestone 2
(2026-10-09, below): `rzig build`, the evaluator and the shipped roots.
Milestone 3 (2026-10-09, below): R CMD INSTALL calls it (patches 0012,
0013). Milestone 5 (2026-10-10, below): the patched R on macOS and
Windows. Milestone 4 (2026-10-10, below, done after M5): the parity
check in the repo, `pixi run pkg-parity`, in CI. Commit 8ce3f77 removed
the prototype files the table in "Cleanup before merge" lists; they are
in history at aff0f4c. Then the consolidation with
feat-standalone-toolchain's phase 3 (main e1ce179, PR #24; "Consolidation
with phase 3", 2026-10-12, below): the merge of main, the install
preflight deciding the tier as `rzig build` does, the per-install zig
build cache, tier 2 offline, MAKEFLAGS, and each test asserting its
builder. PR #25 merged (07e12c0, 2026-10-13) before the phase 3
session's review of it finished; the review's findings are fixed in one
follow-up PR, branch fix-zig-pkg-build-review, recorded in
`.github/devdocs/fix-zig-pkg-build-review/PLAN.md` (the review itself
in `review/` there). The corrections it made to this file carry the
review's ids in brackets (code-2 to code-6 and coverage-1 are its
second review's) and its interface names (I-C1, I-T11, I-PF5), all
defined there.

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
| 2 | `src/build.zig` exists and no `src/Makefile*` (it wins over Makevars and configure; a src/Makefile, which install.R runs itself, wins over it [code-2]); the package's own src/Makevars is not read [code-4] | rzig build → zig build, tier-2 root |
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
   same rzig link rule. The C and C++ sources get the plan's flags:
   Makeconf's with the site and user Makevars, not the package's own
   src/Makevars, which tier 2 does not read (PKG_CPPFLAGS and
   PKG_CFLAGS do not apply; noted in the follow-up [code-4]). A
   pure-zig package exports
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

As designed (M1 to M5): `--cache-dir ${XDG_CACHE_HOME:-$HOME/.cache}/r-zig/zig-build`
(`%LOCALAPPDATA%/r-zig` on Windows), shared, so the build runner of the
tier-1 root compiles once per (root content, zig); the build root is
under the staging dir and goes with it; nothing is written into
`src/`. zig cc keeps its own object cache in zig's global cache, keyed
by the source path among other things (see "Measurements").

Changed in the consolidation (N3, below): the zig build cache is per
install, `<build root>/zig-cache`, gone with the root. The shared cache
never reused an entry (the Run steps' keys hash the whole environment,
`R_SESSION_TMPDIR` included) and only grew; the build runner is rebuilt
per install (about 3 s warm). zig's global cache is the shared part.
It too grew per install until the follow-up (2026-10-13): zig cc keys
its objects on the source path as given, and build_t1.zig passed the
absolute path under install.R's new R.INSTALL directory, so every
tarball install added one entry per source, never reused (cli: 26 per
install). The compiles now name their source relative to src/, as make
does, and a reinstall adds nothing [tests-T1, records-REC-2]. So
CONSENSUS D's "keyed by target, bounded" (`consolidation/CONSENSUS.md`)
was wrong until the follow-up, because zig cc keyed the objects on the
absolute source path; the copy is left as it was agreed (R2).

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

The prototype (`proto/` here, copied from the session's scratch; the
files marked "removed" are in history at aff0f4c, see "Cleanup before
merge"):
- `proto/mkplan.sh` (removed): PROTOTYPE ONLY. Writes `plan.zon` from the dev
  tree's Makeconf and the package's Makevars using make recipes that
  `printf` (not GNU make 4's `$(file)`: macOS ships make 3.81) the exact strings `.shlib_internal`'s make
  invocation would use (its include chain and command-line overrides:
  `SHLIB_LDFLAGS/SHLIB_LD` for C++, `SHLIB_LIBADD` with FLIBS for
  Fortran, `OBJECTS`, `CLINK_CPPFLAGS`). This is what rzig's evaluator
  must reproduce without make; the real work of milestone 2.
- `proto/rpkg/build_t1.zig`, `build_t2.zig`, `rpkg.zig`,
  `build_t2.zig.zon` (removed; now `zigbuild/rpkg/`) (the root's zon; `.pkg` is a relative path to the
  package's `src/`). The plan names the tool files (`cc_tool`,
  `cxx_tool`, `fc_tool`; defaults zig-cc/zig-cxx/zig-fc, Windows
  gcc.exe/g++.exe/zig-fc.exe) and `readPlan` raises
  `@setEvalBranchQuota`: std.zon.parse's inline switch over the struct's
  fields exceeds the default 1000 at this field count.
- `proto/hosts/`: the step-4 drivers (`omicron.sh`, `kappa-step[123].bat`),
  the hand-derived Windows plans (`plans-win/`), the `.def` files, the
  tier-2 root zon, and `results/` (host logs and Windows export lists).
  All but `defs/` removed; in the branch's history for the record, see
  "Cleanup before merge".
- `proto/zighello/`: the tier-2 hello-world package (DESCRIPTION,
  NAMESPACE with `useDynLib(zighello, .registration = TRUE, .fixes = "C_")`,
  `R/hello.R`, `src/build.zig`, `src/hello.zig`).
- `proto/plan-cli.example.zon` (removed): cli's generated plan. `proto/smoke.R`.

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
the choice of build-root paths. (It mattered more: install.R unpacks a
tarball into a new directory each time, so the absolute paths added
entries on every install; the follow-up of 2026-10-13 names the source
relative to src/ [tests-T1].)

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
| `def.zig` | `rzig def -o <pkg>.def <objects>`: winshlib.mk's `nm \| sed -n 's/^.* [BCDRT] / /p'` from the objects' COFF symbol tables (std.coff's records at the object's offsets; `Coff.init` reads images only): storage class EXTERNAL, defined in a CODE, INITIALIZED_DATA or UNINITIALIZED_DATA section that is not LNK_INFO/LNK_REMOVE/MEM_DISCARDABLE, or a common; not undefined, not weak; the compiler's `.refptr.*` / `.weak.*.default.*` globals left out, as CRAN's NM_FILTER (MkRules.rules' default, which fixed/Makefile writes into the installed Makeconf) leaves them out of make's tmp.def (kept from the consolidation to the follow-up, to match this tree's Makeconf.win, whose NM_FILTER was the template's empty line: a gap against CRAN, see "def.zig" in the consolidation and fix-zig-pkg-build-review's PLAN.md, menu 4 [records-REC-3]; M5's "make" reference on kappa was lld's auto-export, with no sed there); de-duplicated. Test object `testdata/win-syms.{c,o}` (zig cc, x86_64-windows-gnu) holds every kind |
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

## Milestone 4 (2026-10-10): `pixi run pkg-parity`

`scripts/pkg-parity.sh`, the pixi task `pkg-parity`, and a CI step after
`contract` in build-r.yaml (every env, every OS). On the installed tree
of the build it asserts what M3 and M5 checked by hand, so the prototype
oracle (`proto/mkplan.sh`) and the M1 drivers can go:

| step | assertion |
|---|---|
| cli, digest, quadprog, Rcpp from CRAN (fetched once into `build/pkg-parity-<flavor>/src`) | `R CMD INSTALL` with the test load, once traced on the zig path (`rzig build: tier 1` in the log, no make line, a `using … compiler` line) and once with `R_ZIG_PKG_BUILDER=make` (no `rzig build:` line); the two libraries export identical symbols (nm; Windows objdump's export table); rzig received identical command lines on both paths (sorted sets, paths by basename, quotes dropped, the known differences normalised: macOS `-Wl,-install_name,<pkg>.so`, Windows `tmp.def`/`<pkg>.def`) |
| smoke | a script loads and exercises the four packages from each library; the outputs are identical and carry no ERROR |
| tier 2 | `proto/zighello` copied and installed: `rzig build: tier 2`, `using zig:`, `hello(21L)` is 42, `R_init_zighello` exported, no `.rzig` or `.zig-cache` left in `src/` |
| tier 3 | cli with a `configure` (`configure.win`) script: `rzig build: cli needs make: a configure script`, make builds it; with `R_ZIG_PKG_BUILDER=zig` the install fails with the `R_ZIG_PKG_BUILDER is 'zig'` message |
| no make | `env -i` with PATH = a directory holding `sh`, `zig`, `flang` (Windows: System32 plus a copy of flang and its two `.cfg`, zig through `ZIG_BIN`): quadprog installs (cli when there is no flang) |

linux-64, 2026-10-10 (the worktree's dist): 1 min 47 s; cli 185, digest
127, quadprog 6, Rcpp 642 exports identical; 27, 20, 6 and 7 rzig
command lines identical; smoke 10 lines identical; zighello 8 s with
the test load; quadprog with `flang sh zig` on PATH 12 s (a fresh HOME,
so the build runner compiles again).

### Not in M4

- The strace deny-list of the plan ("hermetic-check.sh denying sh,
  make, nm, sed, uname, cat"): the restricted PATH is the check, as
  hermetic-check.sh does on macOS and Windows. A traced variant can
  join hermetic-check.sh when `bin/R` no longer needs `sh`.
- The stress suite through the zig path (how many of its packages are
  tier 1), and the docs entries in the feat-no-host-paths and
  feat-standalone-toolchain records.

## Milestone 5 (2026-10-10): the patched R on macOS and Windows

The branch (commit 4a167f5) synced to the two test hosts (omicron
`~/r-zig-pixi`, kappa `C:\Users\admin\r-zig-pixi`, working copies as
before), R rebuilt there with `pixi run build` (the pixi lock of main
b490bdf; conda-forge zig 0.16.0, flang 23.1.1), then the M3 acceptance
run against those dists: `R CMD INSTALL -l <lib> <CRAN tarball>` with the
test load, `RZIG_TRACE=1` on both paths, `R_ZIG_PKG_BUILDER=make` for the
reference. Drivers `proto/hosts/m5-omicron.sh`, `m5-kappa.bat` +
`m5-kappa.R`; raw output in `proto/hosts/results/m5-*.log` (history,
aff0f4c). Scratch
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
symbols are exactly the M1 "make" list (`proto/hosts/results/kappa-exports-cli-make.txt`
in history at aff0f4c, 187) without `_CRT_INIT` and `__mingw_module_is_dll`. Those two were
never in a nm \| sed `.def`: they came from the same empty `tmp.def`, so
M1's "make vs `--export-all-symbols` identical, 187" compared two
auto-exports. On a host with Rtools' sed, make's DLL exports the 185
with CRAN's NM_FILTER; this tree's Makeconf.win had it empty until the
follow-up of 2026-10-13, so the consolidation's kappa run measured 195
on both paths (cli's nine `.refptr.*` names among them) [records-REC-3].
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

## Consolidation with phase 3 (2026-10-12)

feat-standalone-toolchain's phase 3 merged to main as e1ce179 (PR #24)
while this branch waited (the user, 2026-10-10: "let's wait for them to
get merged before we continue here"). This branch's overview of the
merge (CONSOLIDATION.md, not committed: R1) was reviewed by the phase 3
session against main e1ce179 and this branch at 8ce3f77: 35 findings,
34 confirmed by an adversarial verifier and 1 refuted, then the agreed
plan checked by a completeness critic and an accuracy critic. Both
files are in `consolidation/` (R2): `CONSENSUS.md`, the decisions, the
corrected facts and the implementation checklist (sections A to I),
and `FINDINGS.md`, each finding with file:line evidence and the
verifier's note; the ids below (coverage-C1, preflight-F2,
channels-C3, ...) point there. The copies cite CONSOLIDATION.md and
HANDOFF.md by line, as they were in the worktree at 8ce3f77; neither
was committed (R1), and their content is folded into this section, so
those line citations cannot be checked in the repository
[records-REC-14]. The user decided every point on 2026-10-12 (each the
recommended option), and this session implemented them in the
worktree; the phase 3 session was to review the uncommitted result
before the merge commit and the push (N7).

What happened instead (2026-10-13) [records-REC-5]: the merge commit
47e8436 (2026-10-12 20:10Z), the Windows test fix 45892fb (20:40Z) and
the stress follow-up 5416d8d (2026-10-13 10:04Z) were committed and
pushed first, CI and the stress dispatch ran on them (the user: "When
everything is green, I will start the stress and then we can
communicate with the other session"), and PR #25 merged (07e12c0,
10:07Z) about a minute after the review was asked for. The review then
ran on the merged state, 5416d8d (47e8436, 45892fb and 5416d8d): five
angles (phase 3 interfaces, preflight and hook, tests, records, the
stress follow-up), 51 findings confirmed by an adversarial verifier and
3 refuted, copied into `fix-zig-pkg-build-review/review/`
(REVIEW-SUMMARY.md, REVIEW.md; ids such as tests-T1, preflight-PF-1,
records-REC-3). The user took every menu's recommendation on 2026-10-13
and asked for one follow-up PR on the new main:
`.github/devdocs/fix-zig-pkg-build-review/PLAN.md`.

### Decisions

| id | decision |
|---|---|
| M1 | (a') the install preflight (patch 0009) runs rzig's `--rzig-check=package`, which decides as the hook decides: one function shared with `rzig build` (`pkgbuild.decide`: classify, then plan), with the hook's inputs through the environment |
| M2 | (a) `rzig` / `rzig.exe` is one more name of the binary in `R_HOME/bin/toolchain`, in `rzig_names()` and `installRzig` |
| M3 | (a') pkg-parity on the compile tree; the base only for the no-make install, with no argv comparison |
| M4 | (a') verify-bundle scenario 2 asserts the tier-1 install with `RZIG_TRACE=1`; pfM is the Makevars-rule package; an R-only package with a configure script must stop in the preflight |
| M5 | (a) the records go in this branch's PR |
| M6 | (a') one stress dispatch after the push, with stress.yaml's new `trace` and `builder` inputs; its table and the phase 7 / B24 re-scope in a follow-up commit on the same PR |
| M7 | (a) patch 0010 (`R CMD config` needs the build tools) unchanged; its stated reason corrected (fact 1) |
| M8 | (a) merge origin/main, no rebase |
| N1 | (a) every install-based test asserts its builder, and each package shape keeps one make run |
| N2 | (a) the build-tools scope is written as below; routing `R CMD SHLIB` through rzig is a later item |
| N3 | (a) a per-install zig build cache, removed with the install |
| N4 | (a) a variable assignment in MAKEFLAGS makes the package need make, with that reason |
| N5 | (a) no build-number bump in this PR; phase 4's bump (8 to 9) publishes both packages |
| N6 | (a) tier 2 means vendored or path dependencies only: a URL dependency is refused, zig build runs with `--system` |
| N7 | (a) this session implements; the phase 3 session reviews before the commit and push (it reviewed after the merge instead, 2026-10-13: above [records-REC-5]) |
| R1 | (a) CONSOLIDATION.md not committed: its decisions and corrected facts are here; HANDOFF.md folded in below and deleted |
| R2 | (a) CONSENSUS.md and FINDINGS.md copied into `consolidation/`, cited by finding id |

### Facts the overview had wrong, as verified

Line numbers: pristine CRAN install.R (R 4.6.1), then the merged tree's
(`build/R-4.6.1` after patches 0001 to 0013; `git grep` in the patches
for the text). They are PR #25's: the review follow-up's longer 0013
and 0009 move the merged lines after rzig_build by 20 and those after
the preflight by 24 (1392, 1427, 1491 and 2640 are 1416, 1451, 1515
and 2664 there; checked by applying both series to the pristine
tarball, 2026-10-13).

1. **`R CMD config` runs on unix too** [preflight-F1, F6, coverage-C8,
   channels-C10]. install.R calls it for an executable `configure`,
   for each of CC, CFLAGS, CXX, CXXFLAGS, CPPFLAGS, LDFLAGS, FC and
   FCFLAGS not set in the environment (pristine 1324-1329, the call at
   1327; merged 1427), and `Rcmd config` on Windows for configure.win
   or configure.ucrt (pristine 1290-1292; merged 1392): both only for
   a configure script R runs. Tier 1 never has one; tiers 0 and 2 can
   (`classify` returns r_only and zig before it looks for configure;
   pkgplan.zig). So 0010 stays as it is: install.R reaches it only
   through an R-run configure, which the preflight now covers (fact 3),
   and users, pkgbuild and pak call it directly.
2. **A classify-only check is not enough** [coverage-C6, preflight-F3,
   channels-C6]. Makevars with rules (verify-bundle's mkpkg `lib`,
   test-toolchain's rzigar) classify as `makevars` and become make only
   in `plan()`, whose reason is "src/Makevars has a rule or target
   line: '<line>'". So the preflight runs `pkgbuild.decide`, classify
   then plan, as the hook does; `rzig build --classify` now prints that
   decided tier too.
3. **A configure script in tier 0 or 2** [preflight-F2] needs the
   build tools (unix: make, which `R CMD config` needs; Windows: sh,
   make and the binutils), and main's 0009 asked for them. The
   preflight keeps that: install.R passes `R_ZIG_CONFIGURE=1` when it
   will run a configure script, and the check then asks for the build
   tools whatever the tier ("a configure script R runs").
4. **argv differs across the trees** [channels-C1]: rzig adds the
   compilers group's openmp/ to its environments where it is (the
   compile tree) and not on the base, so pkg-parity compares both
   paths on the compile tree.
5. **Tier-3 checks on the base fail on Windows** [channels-C2]: the
   preflight's build-tools stop (no binutils/) comes before the hook.
   So pkg-parity runs the tier-3 checks on the compile tree, where
   they pass [records-REC-10, preflight-PF-7].
6. **macOS trace lines** [channels-C3] (inferred, run on omicron
   below): with conda-forge zig, rzig's trace line is `zig-cc:
   ZIG_LIB_DIR=<mirror> <zig> cc ...`; pkg-parity's `argv_of` dropped
   such lines and would have seen none. It strips the prefix now.
7. **Builders changed silently** [coverage-C2..C5, C9, channels-C4].
   With 0013's default `auto` these moved to rzig build: contract's
   Rcpp and quadprog (every OS) and minqa (unix; its Makevars.win's
   `$(shell ...)` keeps it on make on Windows), pak's embedded cli,
   lpSolve, pkgcache and yaml, the conda recipe's rzigc, rzigz, rzigf
   (unix) and rzigfl, wheel-test's packages (the wheel's make then
   built nothing), scenario 3's btA. Scenario 2 was the reverse: its
   `R CMD SHLIB` checks stay on make, while `R CMD INSTALL` of the
   same shapes takes rzig build. Each test now asserts its builder
   from the install log (`RZIG_TRACE=1`: `rzig build: tier 1`, or
   `<pkg> needs make: <reason>`), and each shape keeps one make run.
8. **`R CMD SHLIB` never reaches the hook** [coverage-C1,
   channels-C8]: `.SHLIB` calls `.shlib_internal` and make (pristine
   2537, merged 2640 [records-REC-10]). Run-time compilation (Rcpp's
   sourceCpp, cppFunction and evalCpp, cpp11::cpp_source, inline,
   rstan, TMB) still needs make, and so does pkgbuild's has_compiler
   probe (`R CMD SHLIB`), which pak runs before every compiled package:
   on base + compilers pak installs no compiled package, tier 1
   included. remotes and devtools were not checked.
9. **The zig build cache grew without bound** [channels-C5]: measured,
   two new `o/` entries per install, never reused (FINDINGS.md's
   channels-C5 verifier note; CONSENSUS.md's fact 9 says only that
   nothing removes them [records-REC-10]). Per install now (N3). zig's
   global cache grew per tarball install too, through zig cc's absolute
   source paths (the same verifier note); fixed only in the follow-up
   [tests-T1, records-REC-2].
10. **MAKEFLAGS** [coverage-C7]: `MAKEFLAGS='LTO_OPT=-flto'` or
    `CFLAGS=...` changed make's build and not rzig build's. `plan()`
    now declines with "MAKEFLAGS sets NAME" for a word after GNU make's
    ` -- ` or a `NAME=value` word; `k -j2 --jobserver-auth=fifo:...`,
    what install.packages(Ncpus > 1) puts there, plans tier 1.
11. **`rzig build: tier N` needs `RZIG_TRACE=1`**, and stress runs
    skip 0009 (stress.R's empty `R_MAKEVARS_USER`) [channels-C7,
    coverage-C10, C11]: the stress table measures the hook's tiers,
    not the preflight; stress.yaml has `trace` and `builder` inputs
    now, and stress.R's toolchain pattern knows rzig build's own
    failure lines.
12. **Records** [coverage-C13, preflight-F8, channels-C11, C14]: the
    worktree had two untracked records; the hook is in 0013's `@@
    -683` hunk only (the 746 hunk is patch_rpaths); pfC has two .c
    files; the compile tree's PATH line (etc/Renviron) is a unix fact
    in phase 3; the pkg-parity prefix line was :34.

### What the merge changed

The merge (`git merge --no-commit origin/main`, e1ce179; M8): four
conflicts, resolved as CONSENSUS.md's section A says: `build.zig`'s
installRzig takes main's lists plus `rzig.exe` and `rzig` (no
extensionless zig-cc/zig-cxx on Windows: the preflight and `R CMD
config` run gcc.exe's check mode, B26 a); verify-tree.sh takes main's
`tc_names="$(rzig_names)"`, and `rzig`/`rzig.exe` join `rzig_names()`
(scripts/verify-helpers.sh); main.zig and pixi.toml keep both sides,
`pkg-parity` depending on `compile-tree`. The find_zig fix in
pkgbuild.zig (main's `find` returns `!?Zig{argv, file}`: no zig is 127
and the compilers group's text, as a compile says); build_t1.zig's
`cc_tool`/`cxx_tool`/`fc_tool` defaults are the OS's names (the plan
always carries them).

- **rzig** (`zigbuild/tools/rzig/`):
  - `pkgbuild.decide` (pkgbuild.zig): classify, then plan; the tier,
    the reason, the plan. `run` and check.zig's `package` both call it.
    `--classify` prints the decided tier (for a tier-2 package whose
    plan needs make: `make`, which the follow-up made the I-C1 line and
    exit 1 [coverage-1]).
  - `--rzig-check=package` (check.zig): the preflight for the package
    in the working directory: the compilers, flang when the plan's
    sources have Fortran (tiers 1 and 2) or src/'s top level has a
    Fortran file in either case (a package make builds, as 0009 did),
    the build tools when the package needs make or `R_ZIG_CONFIGURE=1`,
    the failing line `"<pkg> needs make: <reason>; no make on PATH"`
    before the group text. `R_ZIG_C_STD` is use_C (the hook's
    `--c-std`); `R_ZIG_PKG_BUILDER=make` forces make. Ten
    parity-test.sh cases (the real binary, linux CI); no unit test ran
    `package()` or `decide` until the follow-up [preflight-PF-7]. The
    flang rule for tier 2 changed in the follow-up (never; I-PF5,
    "Known differences").
  - pkgplan.zig: `makeflagsAssignment` and the "MAKEFLAGS sets NAME"
    reason (N4), unit-tested.
  - The per-install cache (N3): `--cache-dir` defaults to `<build
    root>/zig-cache`, or `ZIG_LOCAL_CACHE_DIR` when set (stress.R points
    it at the run directory); `--cache-dir` wins over both.
  - Tier 2 offline (N6): `urlDependency` scans the package's own
    src/build.zig.zon; a dependency with `.url` is "src/build.zig.zon:
    dependency <name> is a URL; tier 2 builds offline, vendor it as a
    .path dependency", exit 1 (not 3: make would compile src/ and
    ignore build.zig); `zig build` runs with `--system <build
    root>/no-packages` (an empty directory), so nothing fetches. The
    rpkg roots use no system integration, so the switch changes
    nothing else (pkg-parity's zighello builds with it).
- **R** (`zigbuild/patches/R-4.6.1/`): 0009 rewritten (one
  `system2(<CC's path>, "--rzig-check=package", stdout = FALSE)`, with
  `R_ZIG_CONFIGURE` and `R_ZIG_C_STD` set around it and unset after;
  the call goes to CC's name, zig-cc / gcc.exe, which hermetic-check's
  strace allowlist admits [coverage-C12]; the rzig-missing branch and
  `R_ZIG_TOOLCHAIN_HINT` stay); 0013 regenerated on it (the hunks at
  683, 746 and 1544, 1548 on the review follow-up's 0009; CC's binary
  beside no `rzig` name stops with "the
  r-zig toolchain is older than this R" instead of a silent make path
  [preflight-F7]). The series applies to the pristine tarball with no
  offset. 0010 unchanged (M7).
- **pkg-parity** (scripts/pkg-parity.sh; M3, F; its Windows and macOS
  legs ran for the first time, on kappa and omicron, see "Test
  results"): parity, the cache
  checks, tier 2 (and the URL refusal), tier 3 on `$COMPILE_TREE`; the
  base (`$PREFIX`) only for the no-make `env -i` install, asserting
  `rzig build: tier 1`; minqa after Rcpp on unix (coverage-C5), with a
  bobyqa line in smoke.R; `argv_of` strips `ZIG_LIB_DIR=<word> `
  (channels-C3); `XDG_CACHE_HOME` under the work directory, no
  `ZIG_LOCAL_CACHE_DIR`, so the `zig-build` check sees rzig's cache.
- **verify-bundle.sh** (G): scenario 2's preflight branches (M4 a'):
  pfC installs through rzig build (`RZIG_TRACE=1`, no make output) and
  loads; pfM (mkpkg `lib`) stops with "pfM needs make: src/Makevars
  has a rule or target line: '$(SHLIB): lib/libval.a'; no make on
  PATH" and the build-tools text; pfG (R only, configure_marker) with
  "a configure script R runs", its configure not run; pfF as before;
  all three stops with 0009's ERROR line. Each `R CMD SHLIB` shape
  (C++, Fortran, USE_FC_TO_LINK, $(FLIBS) with no flang on PATH,
  OpenMP C, Fortran OpenMP, and the C++ one with the CONDA_PREFIX
  decoys) is also a package installed through rzig build (`shape_pkg`),
  with the same rpath, NEEDED, C++ runtime, minos, libomp and load
  checks on `lib/<pkg>/libs/<pkg>.so`. Not yet: the OpenMP decoy rebuild
  through rzig build, and the macOS floor on rzig build's objects (the
  .so only) [tests-T8]; both in the follow-up. Scenario 3: btA through
  rzig build and btLib (Windows: btRc too) through the group's make in
  one install.packages(Ncpus = 2) run, asserted from the kept logs; the
  LTO record's tier-1 twin ltotier1 must go to make with "MAKEFLAGS sets
  LTO_OPT". The header says so, and also said Windows scenario 3's
  OpenMP packages were built as packages through rzig build, which they
  were not (R CMD SHLIB only: checklist G's "likewise Windows scenario
  3's OpenMP packages" was not done) [phase3-P3-1, records-REC-1,
  tests-T3]; scenario 2's new assertions were unix-only [phase3-P3-9].
  Both are in the follow-up.
- **contract-test.sh**: `RZIG_TRACE=1`, `keep_outputs`, the builder
  asserted per package from its log (Rcpp, quadprog, unix minqa: rzig
  build; data.table, ps, Windows minqa: make; pak mixed: its configure
  installs its embedded cli, lpSolve, pkgcache and yaml through rzig
  build and keyring and zip, Makevars rules, through make); the
  comments and pixi.toml's say which. Found on the way: the R program
  is written to a file now, because R's front end omits a `-e`
  expression over 10000 bytes once bin/R has encoded its spaces as
  `~+~` (one WARNING, exit 0: the first run of the grown program was
  vacuous and "passed"; main's program is 9173 bytes, just under), and
  the script requires the program's last line. **recipe/test-toolchain.R**: rzigc's default
  install asserts `rzig build: tier 1`; rzigc, rzigz, rzigfl and unix
  rzigf also through `R_ZIG_PKG_BUILDER=make` into a second library
  (their builder not asserted: RZIG_TRACE was unset there, so "no `rzig
  build:` line" held either way; asserted since the follow-up
  [tests-T2]).
  **wheel-test.sh**: the console-script install asserts rzig build
  (the first under PyPI's ziglang), the bundled bin/R install runs
  with `R_ZIG_PKG_BUILDER=make`, and a Makevars-rule package
  (rzigwheelar, a static library through $(AR)) is built by the
  wheel's make; the header says which. **smoke-test.sh** part 2:
  `RZIG_TRACE=1`, the display grep no longer a gate (coverage-C13);
  it ran in no task until the follow-up's `pixi run rzig-test <prefix>`
  [tests-T12].
- **stress**: stress.yaml inputs `trace` (bool) and `builder`
  (auto|make); stress.R's toolchain pattern gains `rzig build: (zig
  build failed|no zig|cannot |waiting for zig build)` and
  `R_HOME/share/zig/rpkg is not installed`; packages.tsv's notes for
  Rcpp, lme4, mlpack, fst and geos say they build through rzig build.
  (The follow-up drops `zig build failed`, which follows every failed
  compile [tests-T4], and corrects the fst, geos and lme4 notes against
  the stress table [records-REC-12, tests-T5].)
- **def.zig** (found by kappa's first pkg-parity run, 2026-10-12):
  `rzig def` kept out every name starting with `.`, and make's DLL
  exported cli's nine `.refptr.*` stubs: winshlib.mk's `nm | sed -n
  's/^.* [BCDRT] / /p'` filters them only through `NM_FILTER`, which
  phase 3's Makeconf.win leaves empty. M5's kappa had no sed, so its
  make reference was lld's auto-export, which leaves them out, and the
  difference never showed. `rzig def` now keeps the compiler's EXTERNAL
  globals as nm lists them (`.refptr.<name>`, a weak function's
  `.weak.<name>.default.*` alias); its unit fixture has one of each.
  Corrected by the review [records-REC-3]: CRAN's R does filter them.
  MkRules.rules sets `NM_FILTER ?= | $(SED) -e '/[.]refptr[.]/d' -e
  '/[.]weak[.]/d'` and gnuwin32's fixed/Makefile writes it into the
  installed etc/x64/Makeconf (MkRules.dist's commented line documents
  that default, it does not switch it off); this tree's Makeconf.win
  kept the vendored template's empty `NM_FILTER =` (since 174c952, the
  initial vendoring, never decided). So this change matched a gap
  against CRAN, and r-zig's DLLs exported stubs CRAN's do not. The
  follow-up (menu 4 a) substitutes CRAN's NM_FILTER into Makeconf.win
  (build.zig) and `rzig def` leaves those names out again, so both
  paths match CRAN.
- **Records**: this section; feat-standalone-toolchain PLAN.md's phase
  3 note and TODO.md's items (below, "What the build-tools group is
  for"); no build-number bump (N5).

### Known differences between the preflight and the hook (recorded)

Four inputs differ, in the first three items below: CLINK_CPPFLAGS,
the user-Makevars skip, use_LTO and Windows' `--debug` (0009's header
and check.zig said two until the follow-up [preflight-PF-7]). Then the
rules where the two look at different things, as the follow-up left
them.

- `CLINK_CPPFLAGS` is set after the preflight (merged install.R 1491),
  so the preflight plans without the LinkingTo paths. It differs from
  the hook only for an apostrophe or `$` in such a path, where make
  fails too [preflight-F4].
- 0009's `!length(makevars_user())` skip stays: a user Makevars skips
  the whole preflight, though `plan()` reads it and would decide make
  for a foreign compiler [preflight-F4].
- use_LTO and Windows' `--debug` are not passed to the preflight
  (they change flags, LTO and DEBUG, not the tier).
- Fortran in a subdirectory a Makevars OBJECTS names: the plan's
  sources catch it for tier 1; tier 3 keeps 0009's top-level match, so
  such a package stops later, at zig-fc, with the same text
  [preflight-F5].
- flang for tier 2 (I-PF5, the follow-up): never, since rpkg compiles C
  and C++ only, so a stray top-level `.f`, which the plan's sources
  list, is no reason to stop (the hook builds such a package with no
  flang) [preflight-PF-5]; with `R_ZIG_CONFIGURE=1`, whatever the tier,
  src/'s top level in either case, as CONSENSUS B agreed (the
  consolidation used the plan's sources there too) [records-REC-11].
  For tier 2 this departs from CONSENSUS B, which said "plan().sources
  has f or f9x (tiers 1-2)": recorded here.
- The user Makevars: R's makevars_user() reads `R_MAKEVARS_USER` with
  `Sys.getenv(, NA)`, so set but empty is none; rzig does the same since
  the follow-up (it took empty for unset and fell back to
  ~/.R/Makevars) [preflight-PF-2]. `~` as R expands it: on Windows
  R_USER, else HOME, else HOMEDRIVE and HOMEPATH; on unix HOME, where R
  also falls back to the passwd home when HOME is unset or empty, which
  rzig does not mirror, so the hook passes R's own choice,
  makevars_user(), as `R_MAKEVARS_USER` when it names a file (when R
  finds none, rzig's lookup finds none either) [code-5]. The preflight
  runs only when R found no user Makevars.
- A tier-2 package whose plan needs make (I-C1, the follow-up): the
  hook, `rzig build --classify` and the preflight all say "<pkg>:
  src/build.zig cannot be built by make: <reason>" and exit 1; the
  preflight adds "<pkg>: the r-zig toolchain is complete: change what
  the line above names", since 0009's stop after it says the toolchain
  is incomplete (I-T11, a fixed text) [preflight-PF-1, coverage-1,
  code-6].

### What the build-tools group is for (N2, the scope statement)

The build-tools group (unix make; Windows sh, make and the binutils) is
needed by: packages that need make (tier 3: configure scripts,
src/Makefile*, an Objective-C source, Makevars with rules, an
`include`, conditionals, `$(shell)`, a foreign compiler, OBJECTS
without a source, `MAKEFLAGS` setting a variable); any package whose
configure script R runs (tier 0 or 2 can have one; `R CMD config` runs
before it on unix, 0010); `R CMD SHLIB`, so run-time compilation
(Rcpp's sourceCpp/cppFunction/evalCpp, cpp11::cpp_source, inline,
rstan, TMB) and pkgbuild's has_compiler probe, through which pak
refuses every compiled package, tier 1 included, before `R CMD
INSTALL`; `R CMD config`'s direct callers (users, pkgbuild); `R CMD
check`'s objdump (Windows); on Windows, cleanup.ucrt/cleanup.win under
`--clean` or `--preclean` (without sh only a warning: the cleanup is
skipped) [coverage-C1, channels-C8, preflight-F7]. Not needed by tier 0
to 2 installs without a configure script R runs, through `R CMD
INSTALL` and install.packages() [records-REC-6]. Phase 7 (Windows
usr/bin) and B24 are re-scoped from the stress table (M6; "Stress
dispatch" below: 31 of the suite's 47 rows that compile need the group
on unix and 30 on Windows, 30 and 29 of them through make in run_shlib,
24 and 12 of those for a configure script, and Rhdf5lib through its
configure script's CMake [stress-S9]; the table adds no evidence on
B24, whose dlltool/as follow-up PR stands [stress-S2]). Later items:
route `R CMD SHLIB` through rzig build (it would also clear pak's
probe), or give it a preflight; revisit 0010 for pkgbuild's probe; a
shared tier-1 build runner, still open: the stress dispatch shared one
zig build cache, so it did not measure the per-install runner cost,
and a dispatch with `shared_cache = false` decides it (CONSENSUS H;
"Stress dispatch" below; fix-zig-pkg-build-review's PLAN.md)
[stress-S1, records-REC-4]; a g1 dispatch with trace (Rcpp, rstan),
whose smokes compile at run time [stress-S6].

### The couplings to R's tree (from HANDOFF.md, updated for the merge)

Exact couplings to R's tree, Makeconf and the toolchain layout; a
change to any of them needs a matching change in pkgplan.zig, patch
0013 or pkg-parity.sh.

1. **Makeconf location and shape.** pkgplan.zig reads
   `R_HOME/etc$(R_ARCH)/Makeconf` (`R_ARCH` from the environment, else
   `/x64` on Windows, empty elsewhere), in "makeconf" mode:
   assignments, `include $(R_SHARE_DIR)/make/vars.mk`, `ifeq`/`ifdef`
   blocks and the usual text functions are evaluated; rules and
   recipes are skipped. `$(shell ...)` makes the whole package "needs
   make". Phase 3's Makeconf.win has no `$(shell)` or `$(wildcard)`
   on the path to any variable below. On unix `SHLIB_EXT` and
   `SHLIB_LIBADD` are also read raw, as install.R does.
2. **Variables the plan is built from** (the names install.R's make
   path uses): `CC CXX CXXnn CXXnnSTD FC`, `ALL_CPPFLAGS ALL_CFLAGS
   ALL_CXXFLAGS ALL_FFLAGS ALL_FCFLAGS`, `SHLIB_LINK` (unix) or
   `SHLIB_LD SHLIB_LDFLAGS LDFLAGS DLLFLAGS` (Windows), `SHLIB_CXXLD
   SHLIB_CXXLDFLAGS SHLIB_CXXnnLD(FLAGS)`, `SHLIB_FCLD SHLIB_FCLDFLAGS`,
   `ALL_LIBS PKG_LIBS SHLIB_LIBADD SAN_LIBS LIBR FLIBS BLAS_LIBS
   LAPACK_LIBS SHLIB_OPENMP_*`, `R_INCLUDE_DIR R_SHARE_DIR R_DOC_DIR
   R_ARCH`, Windows `LOCAL_SOFT BINPREF`.
3. **The compiler must be a file directly in `R_HOME/bin/toolchain/`.**
   `toolName` takes the first word of `$(CC)`, `$(CXX)`, `$(FC)` and
   `$(SHLIB_LD)`; it must start with `$(R_HOME)/bin/toolchain/` and
   have no further `/`. Anything else (a group subdirectory, a bare
   `gcc`, a user `~/.R/Makevars` override) is "needs make" by design.
   Phase 3 keeps the compilers there: unix `zig-cc zig-cxx zig-fc`,
   Windows `gcc.exe g++.exe zig-fc.exe` (`.exe` appended when Makeconf
   omits it); the AR/RANLIB and binutils names are not the plan's.
4. **`rzig` is one more name of the same binary** in that directory
   (`rzig_names()`, installRzig); main.zig dispatches `rzig build` and
   `rzig def` under that name. The hook calls
   `R_HOME/bin/toolchain/rzig(.exe)`; its absence beside CC's binary
   is an error (0013), with neither it is the make path.
5. **`R_HOME/share/zig/rpkg/{build_t1,build_t2,rpkg}.zig`** must be
   installed, or `rzig build` fails with "R_HOME/share/zig/rpkg is not
   installed". verify-tree.sh asserts it.
6. **Finding zig**: `find_zig.find` returns `!?Zig{argv, file}`;
   pkgbuild.zig and check.zig are its callers outside main.zig.
7. **Windows `.def`.** The link uses `rzig def -o <pkg>.def <objects>`
   unless the package ships `<pkg>-win.def`. R.dll's export set and
   `-L R_HOME/bin/x64 -lR` as LIBR; lld links against R.dll directly.
8. **RZIG_TRACE output format.** pkg-parity.sh normalises the trace
   lines `zig-cc|zig-cxx|zig-fc: [ZIG_LIB_DIR=<word> ]<quoted argv>`
   and drops the `self` and `environment` lines. New trace lines are
   fine if they do not start with a tool name followed by `: `.

Known facts worth not rediscovering (from HANDOFF.md): macOS: the
zig-linked dylib's install name is the cache path unless
`-Wl,-install_name,<pkg>.so` is passed; rzig passes it; minos 13.0 and
exports match make's. Windows: `-Wl,--export-all-symbols` is not
equivalent to nm | sed (lld skips symbols R.dll also exports, quadprog's
`dposl_`), hence `rzig def`; kappa has no `sed`, so its make path made
an empty tmp.def and lld auto-exported; its make path also failed for
C++ and Fortran packages (SHLIB_CXXLD and FCLIBS_XTRA quoting) before
phase 3's Makeconf.win. The Fortran link carries `-lc++` twice;
harmless. A `cleanup` script does not make a package tier 3; `configure`
does. Steady-state tier-1 time equals make's plus the build runner
(below).

### Measurements (linux-64, gamma, 2026-10-12, the compile tree)

pkg-parity (`pixi run pkg-parity`), both paths identical in exports,
rzig command lines and smoke output:

| package | rzig build | make | exports | rzig command lines |
|---|---|---|---|---|
| cli | 11 s | 12 s | 185 | 27 |
| digest | 7 s | 7 s | 127 | 20 |
| quadprog | 6 s | 2 s | 6 | 6 |
| Rcpp | 14 s | 20 s | 642 | 7 |
| minqa | 8 s | 9 s | 187 | 19 |

The per-install cache (N3): the build runner compiles per install
(quadprog's 6 s against make's 2 s is that cost, about 3 to 4 s; the
larger packages hide it in the compiles). cli twice from one
directory: zig's global cache's `o/` unchanged (270 entries), no
`zig-build` under rzig's cache, no build root left in src/. (One
directory is the one case where zig cc's keys, the absolute source
paths, coincide: from its tarball, as install.packages installs, each
install added 26 entries until the follow-up [tests-T1,
records-REC-2].) Tier 2 (zighello): 47 s the first time (zig's global
cache cold for the package target: std, translate-c of R's headers),
then 5 s per install (the second and third installs; `--no-test-load`
5 s); cli `--no-test-load` 10 s. The base alone with PATH = sh, zig
and flang: quadprog in 11 s.

### Test results (checklist I, 2026-10-12)

| where | what | result |
|---|---|---|
| linux-64 (gamma), slim | `rzig-test` with conda-forge zig and with upstream zig (`ZIG_BIN=$(pixi run fetch-zig)`) | 119 unit tests; parity-test 91 identical, 0 failed, the ten `--rzig-check=package` cases included |
| | `toolchain`, `build`, `verify-tree`, `compile-tree` | pass |
| | `pkg-parity` | pass (the table above) |
| | `hermetic` | pass |
| | `contract` | pass: builders Rcpp, minqa, quadprog = rzig build; data.table, ps = make; pak = mixed; evalCpp, OpenMP, the config checks as before |
| | `package-toolchain`, `verify-package` | pass: scenario 2's pfC through rzig build, pfM, pfG and pfF stops, every shape as a package; scenario 3's btA/btLib builders |
| linux-64, minimal | `toolchain`, `build`, `package-toolchain`, `verify-package` | pass |
| linux-64, wheel | `wheel`, `wheel-test` | pass: the console-script install `rzig build: tier 1` under PyPI ziglang (3 rzig commands, the two compiles and the link; the 9 counted then included rzig's self and environment lines [tests-T10]), the bundled bin/R install through make, rzigwheelar through the wheel's make |
| linux-64, pkg | `conda-package` | pass (r-zig-slim and r-zig-toolchain build 8, not published): test-toolchain.R asserts rzigc through rzig build from a captured `R CMD INSTALL` log (install.packages keeps no output for a local path: found by this run), and rzigc, rzigz, rzigf, rzigfl through make too (their builder not asserted until the follow-up [tests-T2]) |
| omicron (osx-arm64, macOS 26.4.1, conda-forge zig) | `toolchain`, `build`, `compile-tree`, `rzig-test`, `pkg-parity`, `package-toolchain`, `verify-package` | pass. pkg-parity: cli 13 s / make 10 s (27 rzig lines identical, the `ZIG_LIB_DIR=` prefix stripped: the first macOS run, channels-C3), digest 17/7 (20), quadprog 9/3 (6), Rcpp (its numbers not recorded [records-REC-10]), minqa 10/7 (19); zighello 29 s cold, URL refused; cli twice: 257 global entries unchanged; quadprog on the base 12 s. verify-package: pfC through rzig build, the shapes, btA = rzig build and btLib = make. Run twice, the second after the def.zig change: pass both times |
| kappa (win-64, Windows 11 22621, conda-forge zig) | `toolchain`, `build`, `compile-tree`, `pkg-parity`, `package-toolchain`, `verify-package`, `conda-package` | pass. pkg-parity (its first runs on Windows) found three things, fixed and rerun: `rzig def` dropped the `.refptr.*` names make exports (def.zig, above); `argv_of` cut `--out-implib=<path>` to the bare file name on the zig path (the option name is kept now); the no-make env lacked zig's cache home (`LOCALAPPDATA`, `ZIG_GLOBAL_CACHE_DIR`) and took zig from `command -v zig`, which finds nothing on win-64 (env.sh's `$ZIG` now). Then: cli 31 s / make 18 s (195 exports, 27 rzig lines identical), digest 18/6 (129, 20), quadprog 15/4 (2, 6), Rcpp 29/9 (744, 7); cli twice: 1718 global entries unchanged; zighello 16 s warm (70 s cold); quadprog on the base 14 s with flang + System32, zig through ZIG_BIN. verify-package: scenario 3's btA = rzig build, btLib and btRc = make; ltotier1 goes to make with "MAKEFLAGS sets LTO_OPT"; the OpenMP DLLs; run twice (before and after def.zig), pass both times. conda-package: both packages build, test-toolchain.R's builder assertions pass |

CI on PR #25 (run 38302765293, after the merge commit 47e8436):
windows-latest / default failed in `rzig tests`: testutil.zig's
`touchExe` used `Permissions.fromMode`, which a Windows host's
`std.Io.File.Permissions` lacks; main's tests never referenced it on
Windows, this branch's pkgplan tests do, and the branch had never run
on Windows CI (kappa's chains ran everything but rzig-test). Fixed with
a comptime switch (a plain file there, as touchProgram makes); rzig-test
on kappa: 94 passed, 25 skipped. CI on 45892fb (run 38305799627, the
full tier): green. The upstream-zig legs did not run on PR #25 (its
only label was full-ci; runs 38302765022 and 38305799647 skipped), so
rzig build on Windows under upstream zig, tier 2 with `--system` and
pkg-parity's argv comparison had not run with upstream zig anywhere
[phase3-P3-10]; the follow-up PR gets the `upstream-zig` label
(menu 3). The stress dispatch followed (M6): the next section.

### Stress dispatch (M6, 2026-10-12)

stress.yaml run 38317654371 on 45892fb: oses ubuntu-latest,
ubuntu-24.04-arm, macos-latest, macos-15-intel, windows-latest;
packages g3 g4; distribution tree; `trace = true`; `builder = auto`.
The make reference is phase 3's dispatch 38251125721 on 548da1a
(ubuntu-latest, tree, g3 g4, no trace; every row through make), the
only earlier run, so the make comparison is linux x86_64 only. Each
leg installs 60 rows: 23 targets and 37 dependencies. A row's tier is
its install log's `rzig build:` line: `tier 1, root ...`, or `<pkg>
needs make: <reason>`; a row with no line built no native library in
run_shlib (R-only, or Rhdf5lib, whose configure builds HDF5 with cmake
into inst/ and has no src/: it still needs the group, sh, make through
`R CMD config` and cmake [stress-S9]). stress.R points
`ZIG_LOCAL_CACHE_DIR` at one run-wide `zig-cache`, so the tier-1 build
runner compiles once per leg (the per-install default pays it per
install), and this dispatch says nothing of the per-install cost
[stress-S1]. Smoke steps: g3 g4 have no smoke that compiles at run
time (Rcpp ran only as a dependency, its smoke `TRUE`; rstan is g1),
so the `R CMD SHLIB` command (run-time compilation, pkgbuild's probe)
was not exercised here; contract's evalCpp and verify-bundle scenario
2's SHLIB shapes cover it [stress-S6, records-REC-9]. Nor would a
smoke log have shown one: a local `stress.R --trace Rcpp` of the
follow-up (2026-10-13) compiled and ran its cppFunction smoke, and
Rcpp-smoke.log has no rzig line (sourceCpp keeps R CMD SHLIB's output
to itself). The artifacts (`stress-<os>-tree`, the reference's too)
were read row by row.

Per leg:

| leg | min | jobs | targets | dependencies | unexpected | tier 1 | make | no native library |
|---|---|---|---|---|---|---|---|---|
| ubuntu-latest, linux x86_64 | 17.8 | 4 | 22 ok, 1 install-failed | 37 ok | 0 | 16 | 30 | 14 |
| ubuntu-24.04-arm, linux aarch64 | 21 | 4 | 22 ok, 1 install-failed | 37 ok | 0 | 16 | 30 | 14 |
| macos-latest, macos aarch64 | 25.7 | 3 | 23 ok | 37 ok | 0 | 16 | 30 | 14 |
| macos-15-intel, macos x86_64 | 68.8 | 4 | 23 ok | 37 ok | 0 | 16 | 30 | 14 |
| windows-latest, windows x86_64 (ucrt) | 24 | 4 | 15 ok, 8 install-failed | 37 ok | 0 | 17 | 29 | 14 |
| reference 548da1a, ubuntu-latest | 27 | 4 | 22 ok, 1 install-failed | 37 ok | 0 | 0 | 46 | 14 |

Every non-ok row, with its builder:

| leg | row | class | expect | first error | builder |
|---|---|---|---|---|---|
| linux x86_64, linux aarch64 | magick | abi | fail-abi | undefined symbol `_ZN6Magick11magickImageC1ERKNSt3__112basic_string...` (`Magick::magickImage(std::__1::basic_string const&)`) | make (a configure script); the libstdc++/libc++ boundary of stress round 1 (A1), as on 548da1a |
| windows | ragg | package | fail-package | `lld-link: error: undefined symbol: __declspec(dllimport) htons` | make (Makevars.win has `$(shell ...)`); its pkg-config branch does not link ws2_32 |
| windows | hdf5r | package | fail-package | `1_12_0/Wrapper_auto_H5FDlog.c:23:22: error: use of undeclared identifier 'H5FD_log_init'` | make (a configure.win script); Makevars.ucrt hardcodes the 1_12_0 wrappers, conda has HDF5 2.2 |
| windows | ncdf4 | upstream | fail-upstream | `unable to find dynamic system library 'debug'` | make (Makevars.ucrt has a conditional); conda's netcdf.pc Libs.private has CMake keywords |
| windows | gsl | upstream | fail-upstream | `LoadLibrary failure: The specified procedure could not be found.` | **rzig build, tier 1** (Makevars.win is assignments only; unix has a configure script): 31 compiles and the link produced gsl.dll; the load fails on conda's gslcblas.lib (MKL's import library lists vfprintf/fprintf the DLL does not export), the row's 2026-10-08 finding under make |
| windows | RPostgres | abi | fail-abi | `lld-link: error: could not open 'libuuid.a'` | make (a configure.win script) |
| windows | s2 | sysdep | fail-sysdep | `unable to find dynamic system library 'absl_raw_hash_set'` | make (a configure.win script) |
| windows | igraph | sysdep | fail-sysdep | `vendor/cigraph/src/io/graphml.c:41:10: fatal error: 'libxml/globals.h' file not found` | make (a configure.win script) |
| windows | Rhdf5lib | package | fail-package | `H5Tconv_integer.c:1746:75: error: use of undeclared identifier 'FLT16_MAX'` | configure's cmake build of HDF5 (no src/) |

Each is the failure its packages.tsv row expects from stress round 1
(2026-10-08, every row through make then); none is new, and the one
row that went through rzig build (gsl on Windows) fails at load on the
same import library make's build did.

The tier-1 rows, minutes per leg (ref = 548da1a through make):

| row | ref | ubuntu | arm | macos | intel | windows |
|---|---|---|---|---|---|---|
| sys (the first tier-1 row of every leg: the build runner compiles here) | 0.02 | 0.10 | 0.25 | 0.27 | 0.65 | 0.21 |
| askpass | 0.02 | 0.01 | 0.02 | 0.03 | 0.12 | make 0.76: Makevars.win `all: clean $(ASKPASS)` |
| base64enc | 0.02 | 0.02 | 0.02 | 0.03 | 0.08 | 0.02 |
| bit | 0.07 | 0.06 | 0.07 | 0.09 | 0.24 | 0.07 |
| bit64 | 0.09 | 0.06 | 0.08 | 0.11 | 0.20 | 0.08 |
| cli | 0.14 | 0.09 | 0.12 | 0.16 | 0.52 | 0.17 |
| fst | 0.11 | 0.07 | 0.08 | 0.13 | 0.26 | 0.08 |
| geos | 0.08 | 0.06 | 0.07 | 0.13 | 0.27 | 0.09 |
| glue | 0.02 | 0.02 | 0.02 | 0.05 | 0.10 | 0.03 |
| lattice | 0.13 | 0.09 | 0.12 | 0.12 | 0.24 | 0.10 |
| libgeos (C++, the largest tier-1 build) | 4.66 | 2.94 | 3.48 | 3.88 | 8.89 | make 3.05: Makevars.win `$(SHLIB): $(STATLIB)` |
| lubridate | 0.09 | 0.07 | 0.09 | 0.09 | 0.29 | 0.08 |
| magrittr | 0.02 | 0.02 | 0.02 | 0.04 | 0.06 | 0.03 |
| Rcpp | 0.20 | 0.16 | 0.18 | 0.25 | 0.64 | 0.22 |
| vctrs | 0.22 | 0.16 | 0.19 | 0.29 | 0.85 | 0.25 |
| wk | 0.13 | 0.11 | 0.11 | 0.21 | 0.48 | 0.14 |
| gmp | make 0.23 | make 0.16 | make 0.18 | make 0.33 | make 1.10 | 0.14 (tier 1: Makevars.win is assignments only) |
| gsl | make 0.09 | make 0.07 | make 0.08 | make 0.15 | make 0.58 | 0.07, then the load failure above |
| nloptr | make 0.30 | make 0.21 | make 0.31 | make 0.69 | make 2.06 | 0.04 (tier 1) |

On ubuntu-latest the tier-1 rows ran at about the same ratio to the
548da1a reference as the make rows: 0.67 against 0.65 summed (4.04
against 6.02 min, 0.66 without sys; the make rows 11.94 against 18.43,
each between 0.50 and 0.86 of its reference time), so with a shared
cache there is no measurable builder difference, and runner variance
explains the rest (the whole leg 17.8 against 27 min) [stress-S4,
phase3-P3-8]. sys, the first tier-1 row,
is slower than its reference on every leg (0.10 against 0.02 on
ubuntu): it carries the one runner compile per cache, 5 to 15 s on
four legs and about 35 s on macos-15-intel, inferred from sys against
the reference and the next warm tier-1 row (askpass, base64enc on
Windows) [stress-S5]. The macos-15-intel runner is two to four times
slower on every row, make rows included (s2 4.27 against 1.94 on
macos-latest, igraph 5.52 against 1.58, stringi:bundled 8.45 against
3.11), so its tier-1 times are read against its own make rows only.
These times say nothing of the per-install runner cost (one shared
cache): see the re-scope below [stress-S1, records-REC-4].

The make rows and their reasons:

| where | reason | rows |
|---|---|---|
| unix (the three legs agree) | a configure script (24) | curl, openssl, xml2, gert, units, systemfonts, stringi, stringi:bundled, textshaping, ragg, magick, hdf5r, ncdf4, gsl, Rmpfr, RPostgres, nloptr, s2, igraph, qs2, fstcore, gmp, RcppParallel, stringfish |
| unix | src/Makevars has a rule or target line (6) | filelock `all: clean`, jsonlite `all: $(SHLIB) cleanup`, Matrix `$(SHLIB): $(sslib)`, rlang `all: $(SHLIB)`, timechange `$(SHLIB): libcctz.a`, zip `.PHONY: all clean` |
| windows | a configure.win script (12) | curl, openssl, xml2, stringi, stringi:bundled, magick, hdf5r, RPostgres, s2, igraph, Rmpfr, RcppParallel |
| windows | a Makevars rule (src/Makevars, .win or .ucrt) (9) | jsonlite, Matrix, rlang, timechange (src/Makevars: no .win or .ucrt file), filelock, zip, askpass `all: clean $(ASKPASS)`, libgeos `$(SHLIB): $(STATLIB)` (Makevars.win), units `all: clean` (Makevars.ucrt) [stress-S8, records-REC-8] |
| windows | Makevars.win has `$(shell ...)` (5) | textshaping, ragg, systemfonts, qs2, stringfish |
| windows | a conditional (2) | gert (`ifneq`), ncdf4 (`.ucrt`, `ifeq`) |
| windows | an include (1) | fstcore (`.ucrt`) |

Windows differs from unix in five rows: gmp, gsl and nloptr are tier 1
there (a configure script on unix, a Makevars.win of assignments on
Windows) and askpass and libgeos go to make (unix Makevars of
assignments, Makevars.win with a rule). The macos-15-intel leg's tiers
are identical to macos-latest's. The 14 rows with no native
library are the same everywhere: biocmake, blob, cpp11, credentials,
DBI, dir.expiry, generics, hms, lifecycle, pkgconfig, R6, rstudioapi,
withr (R-only) and Rhdf5lib.

What the Windows rows not built by rzig ran, from the recipes and the
packages' own messages rather than counts of words in the logs (make
echoes a recipe only when it is not `@`-silent, configure.win's
commands and the binutils are not traced, and 6 of the 29 make rows
failed before their end) [stress-S2, stress-S3, records-REC-8]:
winshlib.mk's `@`-silent def and link recipe runs nm, sed (twice),
basename, echo and rm in every make row that links; the 12
configure.win scripts run under sh; pkg-config in at least 9 rows
(ragg, textshaping, systemfonts, xml2, openssl and RPostgres print
"using ... from Rtools", s2 and igraph its results, ncdf4's `-ldebug`
comes from netcdf.pc); rzig's `$(AR)`/`$(RANLIB)` echoed in 12 and 2
rows; rm echoed in 5 (askpass, filelock, units, ncdf4, Matrix); cmake
in Rhdf5lib (its configure, "Building for: MSYS Makefiles") and in
RcppParallel, whose TBB build keeps CMake's output unless it fails and
whose `.rc` files reach windres through Rcmd_environ's `RC`, so windres
ran there unseen. No echoed recipe calls dlltool, windres, objdump or
strip, which says little: R CMD check, objdump's caller, did not run.
(The earlier counts, sed in 5, cmake in biocmake and cp/mkdir, matched
words such as "used" and a package's name.)

**Re-scope of phase 7 and B24 (feat-standalone-toolchain TODO.md),
from this table** (corrected by the follow-up of 2026-10-13 [stress-S1
to S3, S8, S9, records-REC-4, REC-8]). The suite is the hard set by
construction (configure scripts, system libraries): 31 of its 47 rows
that compile need the group on unix and 30 on Windows, 30 and 29 of
them through make in run_shlib (24 and 12 of those for a configure
script) and Rhdf5lib through its configure script's CMake build, so the
build-tools group stays required for the suite's packages on every OS;
the tier-1 share here (16 to 17 of the 46 rows that build a library in
run_shlib) is below the CRAN estimate of about half because of that
selection, not a measurement of CRAN. Phase 7's Windows `usr/bin`
keeps sh and make (configure.win, Makevars rules, `$(shell)`,
conditionals, `include`), coreutils (winshlib.mk's basename and rm in
every make row; rm also echoed in 5), sed (winshlib.mk's def
step) and pkg-config (B43-3; at least 9 rows). The binutils stay in
TC/binutils/ as phase 3 step 6 left them (B24), not in usr/bin: nm for
the def step, windres for `RC` (RcppParallel's TBB), dlltool and as
until their follow-up PR. cmake stays the extras candidate (Rhdf5lib
through biocmake; RcppParallel's TBB). B24: the table adds no evidence
either way (binutils calls are not traced, configure.win and
`@`-recipes are silent, R CMD check did not run); the dlltool/as
follow-up PR stands. The shared tier-1 build runner (TODO.md "Depend
less on make") stays open: this dispatch shared one zig build cache,
so it did not measure the per-install runner cost. The estimates:
fact 9's about 3.1 s warm per tier-1 install on linux-64 (2026-10-13,
the follow-up: 2 to 2.9 s with conda-forge zig, 1.1 to 1.3 s with
upstream zig; fix-zig-pkg-build-review's PLAN.md), about the whole
make install time of the smallest rows (0.02 min); on the hosts, rzig
build against make in the consolidation's pkg-parity, 6 to 10 s more on
omicron and 11 to 20 s on kappa. Decide with a dispatch with
`shared_cache = false` (stress.R `--no-shared-cache`) on the five
runners. Not measured by this dispatch: `builder = make` on the legs
without a reference, the
preflight (fact 11: stress runs skip 0009), the per-install cache's
cost (the run shared one cache), and run-time compilation (no g3 g4
smoke compiles; a g1 dispatch with trace, Rcpp and rstan, is a later
item) [stress-S6].

## Follow-up: the PR #25 review (2026-10-13)

PR #25 merged (07e12c0) before the phase 3 session's review of it
finished ("Consolidation with phase 3", above). The user took every
menu's recommendation and asked for one follow-up PR on the new main,
branch fix-zig-pkg-build-review. Its record,
`.github/devdocs/fix-zig-pkg-build-review/PLAN.md`, holds the review
(`review/` there), the decisions, the interfaces, what changed per
item, the measurements and the tests; the corrections it made to this
file carry the review's ids in brackets.

## Cleanup before merge

The milestone-1 commit keeps every prototype file so the record is
complete in history. The last commit of the PR (2026-10-10) removed
what M2 makes redundant and kept what M2 and M4 build on (decided
2026-10-09). Everything removed is in the tree at aff0f4c
(`git show aff0f4c:.github/devdocs/feat-zig-pkg-build/proto/mkplan.sh`):

| removed in the last commit | why |
|---|---|
| `proto/hosts/results/` | raw host logs and export lists (M1 step 4 and M5); the tables above carry every number |
| `proto/hosts/plans-win/` | hand-derived Windows plans; `rzig build` generates them |
| `proto/hosts/omicron.sh`, `kappa-step[123].bat`, `smoke-win.R`, `root-t2.build.zig.zon` | host-specific drivers for the prototype; superseded by the M5 drivers, which run through `R CMD INSTALL` |
| `proto/mkplan.sh`, `proto/plan-cli.example.zon` | M2 reproduces them (acceptance above) and M4's `pkg-parity` asserts the command lines against make's in CI |
| `proto/rpkg/` | superseded by `zigbuild/rpkg/` in M2 |

Keep: `PLAN.md`, `proto/zighello/` (pkg-parity's tier-2 fixture), `proto/hosts/defs/*.def`
(the Windows export oracle for `rzig def`), `proto/smoke.R`, and the M5
host drivers `proto/hosts/m5-omicron.sh`, `m5-kappa.bat`, `m5-kappa.R`,
`t2.R` (the rerun recipe for the hosts).

Also removed then: the M2 oracle line and the M1 prototype block of
"How to rerun" (history, aff0f4c). What remains of `proto/`:
`zighello/`, `hosts/defs/`, `hosts/m5-*`, `hosts/t2.R`, `smoke.R`.

## How to rerun

    pixi run pkg-parity        # M4 and the consolidation: the five fixtures on the compile tree, tier 2, tier 3, the caches, the base with no make
    pixi run rzig-test         # rzig's unit tests and the shim parity, with --rzig-check=package's cases
    pixi run rzig-test dist/slim/R-4.6.1-zig   # also smoke-test.sh on that tree (linux): packages through its R CMD INSTALL, rzig build
    gh workflow run stress.yaml -f packages='g3 g4' -f trace=true -f shared_cache=false   # the per-install runner cost (stress.R --no-shared-cache)

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

    R=dist/slim/R-4.6.1-zig/lib/R   # or build/compile-tree/slim/R-4.6.1-zig/lib/R, with the build tools
    zig build --build-file zigbuild/tools/rzig/build.zig --prefix /tmp/rz   # or $R/bin/toolchain/rzig
    R_HOME=$R /tmp/rz/bin/rzig build --pkg <unpacked pkg> --plan-only          # the plan
    R_HOME=$R RZIG_TRACE=1 /tmp/rz/bin/rzig build --pkg <pkg> --out /tmp/out/<pkg> \
        --rpkg-dir zigbuild/rpkg --cache-dir /tmp/zc -j8                        # -> /tmp/out/<pkg>/libs/<pkg>.so
    zig build --build-file zigbuild/tools/rzig/build.zig test                 # unit tests
