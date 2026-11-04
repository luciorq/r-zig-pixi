# Phase 7 (m2) plan: amendments of 2026-10-20

The planner's amendments to `phase7plan/PHASE7-IMPLEMENTATION.md` (the
plan, 2026-10-19) and its `CRITIQUE.md`, for the user's final decision of
2026-10-20: phase 7 = MSYS2's tools from conda-forge's m2 packages in
`TC/usr/bin`, the plan's ★ options. Each amendment says what changes, why
(evidence), which plan section it replaces, and the options (★) where
there is a real choice. Revised the same day after two critiques
(section "Critique": C1-C12, S1-S10, each taken or not with the reason).
Nothing in any worktree was written; no build ran; no pixi.lock was
written; no git command wrote. Revised on 2026-10-21 by the user's
decisions (section "User decisions 2026-10-21", at the end): Am1, Am2
and Am16 withdrawn, Am3 moot, Am4 conda (b). Scratch work (a pkgconf 3.0.7 source
tree, a size probe, two CRAN tarballs) is under the planner's scratchpad
only.

Evidence names:
- **KN** `phase7native/kappa/REPORT.md` and its logs (kappa, 2026-10-20).
  Its **M** column is today's m2 set (conda env, build 8, MSYS make,
  conda pkg-config 0.29.2); **N** is the parked native set.
- **7a** `phase7/kappa/RESULTS.md` (kappa, 2026-10-20, the native final
  layout; its pkgconf was a zig build of pkgconf 3.0.7 under both names).
- **PS/PP** the plan's package survey and probe (`phase7plan/pkgs`,
  `dl`, `dl2`, `probe`).
- **P6** the phase 6 worktree `wt/feat-standalone-phase6`, read only.
- **SRC** pkgconf 3.0.7's source, `phase7/userland/dl-pkgconf/pkgconf-3.0.7.tar.xz`,
  extracted in scratch.

## State the amendments were made against

| what | value | command |
|---|---|---|
| P6 `git diff \| sha256sum` | `7304b53c9a1506d515947a2016269ab5b65fae27079230ba5ed6dda61dcae189` (the plan had 9587f87ad4a6e48c) | `git -C wt/feat-standalone-phase6 diff \| sha256sum` |
| P6 `git status --short` | 79 entries (71 M, 8 ??), HEAD d11dee1 | `git status --short \| wc -l` |
| P6 `git diff --stat` | 71 files changed, 8932 insertions(+), 1618 deletions(-) | |
| pixi.lock sha256 | `fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96` (unchanged) | `sha256sum pixi.lock` |

## Summary

| # | amendment | replaces (plan section) | choice |
|---|---|---|---|
| Am1 | `pkg-config` and `pkgconf` are one program, conda-forge pkgconf 3.0.7's `pkgconf.exe` with its own `pkgconf-8.dll` beside it, on both channels; pkg-config 0.29.2 and its glib closure leave the tree. Fixes ncdf4 (d); RPostgres (i) installs only through its own download | §0 table rows "pkg-config", "pkgconf"; §3 build.zig `usr` copies; §5 table; §11 F; §12 2nd bullet; risks 5, 12 | ★ (a), approved 2026-10-20 |
| Am2 | conda: r-zig-build-tools owns three in_conda copies in `TC/usr/bin` (`pkgconf.exe`, `pkg-config.exe`, `pkgconf-8.dll`); pkgconf `==3.0.7 *_0` in host with its run_export ignored (placement checked on all four outputs); pkg-config stays a run dependency for its activation | §0 "conda's win-64 r-zig-build-tools"; §3 recipe.yaml, test-build-tools.R; §4 rows and last paragraph; the in_conda invariant's wording everywhere | consequence of Am1 |
| Am3 | No PKG_CONFIG_PATH line in Rcmd_environ, after a measurement in conda (share/pkgconfig) | new (task item 1) | ★ (a), approved; (b) only if step 5's count differs |
| Am4 | PATH order: Rcmd_environ already right; patch 0014 treats an empty `R_CUSTOM_TOOLS_PATH` as unset; the clash test: run 1 (Git first, `MSYSTEM=MINGW64`) with packages and a mixed-runtime step, run 2 (Git after) the PATH assertions only | §3 patch 0014; §3 verify-bundle "The clash"; step 1 "The clash"; step 5 by-hand runs; §11 M | ★ (a) of two (conda), approved |
| Am5 | The parked native work's fixes are not needed with m2; step 1's recorded native-make and uutils runs dropped | step 1 "Recorded, not a gate"; §7 row; §0 "Not in phase 7" | none |
| Am6 | R's `Sys.which`/`system()` find System32's programs before PATH: the shadowed names are computed, not listed; path comparisons normalised | risk 6; §3 test-build-tools.R | none |
| Am7 | Step 1's kappa set gains ncdf4, RPostgres, stringi, RcppParallel, qfratio and winch; its environment is stated; expected results per package | step 1 "A libraries env", "Real packages", "R_HOME with a space" | none |
| Am8 | stress: ncdf4's Windows expect moves to ok, RPostgres' to ok with a download note, when a `distribution=both channel=local` dispatch shows it | step 6; §3 stress files | none |
| Am9 | verify-bundle's btPc pins the d behaviour (no Libs.private without `--static`) and the space-path escape | §3 verify-bundle "btPc" | none |
| Am10 | verify-toolchain (O): `pkg-config` and `pkgconf` join the names; no new version check | §3 verify-toolchain.sh | none |
| Am11 | Measurements: Defender cold start dropped (answered by KN, 7a); pkg-config's link line added | step 1 "Measured"; §7; risk 13 | none |
| Am12 | Long paths past MAX_PATH and non-ASCII paths: not phase 7 (records only) | §8 risk 10; §10 | none |
| Am13 | Line references become function or block names; phase 6's moved lines | §1, §3, §10 (every `file:line`) | none |
| Am14 | m2 versions and file lists checked against today's lock; pkgconf 3.0.7's contents, DLLs, licence | §5 | none |
| Am15 | Sizes and file counts with Am1 | §0, §4, §5, §7, step 2 | none |
| Am16 | The approved re-lock (F a): what it may change, and minimal-check after it | §1 "Ownership", step 2 changes, §3 pixi.toml | none |
| Am17 | Records and stale references added since the plan | §9, §10, §12 | none |
| Am18 | Step order: the toolchain step (2) runs before the kappa probes (1); no `proto-usr.sh` | steps 1, 2; §7 kappa row | none |
| Am19 | The decided options become records; no live menus for A, B, C, F | §11 A, B, C, F; §12; check.zig's comment; B11 | none |

## Am1. Which program answers `pkg-config` and `pkgconf` (task item 1)

**What.** In `TC/usr/bin`, both names are conda-forge pkgconf 3.0.7's
`pkgconf.exe`, copied twice (`pkgconf.exe`, and `pkg-config.exe` by a
`Copy` whose `.to` differs from `.from`), with `pkgconf-8.dll` beside
them; the tree also copies `vcruntime140.dll`. The three pkgconf files
are `in_conda` (Am2, C3), so a conda env's `TC/usr/bin` holds the same
program with the same DLL. conda-forge's pkg-config 0.29.2 is no longer
copied, and neither is its glib closure (`glib-2.0-0.dll`, `iconv.dll`,
`charset.dll`, `intl-8.dll`, `pcre2-8.dll`). One rule: under R CMD and
in R sessions, `pkg-config` and `pkgconf` are one program with its own
DLL, on both channels.

**Why.**
- pkg-config 0.29.2 (conda-forge, built with `nmake /f Makefile.vc`,
  `phase7plan/pkgs/pkg-config-0.29.2-hffdb5b9_1013/root/info/recipe/build.bat`)
  prints `Libs.private` without `--static`:
  - d, ncdf4: its Makevars.ucrt calls bare `pkg-config --libs netcdf
    libcurl` (ncdf4_1.24 `src/Makevars.ucrt:7`); the link gets
    `-ldebug ... -loptimized` and lld stops: "unable to find dynamic
    system library 'debug'" (`phase7native/kappa/logs/M/outputs/ncdf4.out:16-17`).
    With pkgconf it links the env's netcdf (`logs/N/outputs/ncdf4.out:16`,
    `-L<env>/Library/lib -lnetcdf -lcurl ...`): a real fix.
  - i, RPostgres (C1): its Makevars.win takes `PKG_LIBS := $(shell
    $(PKG_CONFIG) --libs libpq)` and uses the env's libpq only when that
    output contains `ldap32` ("using libpq from Rtools"); otherwise it
    runs `tools/winlibs.R`, which downloads r-windows' libpq-15.12 clang
    bundle from GitHub into `../windows/libpq`. Under M, 0.29.2's private
    libs carry `-lwldap32`, so it links the env's static libpq and fails
    on `libMSVCRT.a` (`logs/M/outputs/RPostgres.out:9`, 30-33). Under
    pkgconf the public `Libs` have no wldap32, so it downloads and links
    the bundle first (`logs/N/outputs/RPostgres.out:9` runs
    `../tools/winlibs.R`; :202 `-L../windows/libpq/lib/x64
    -L../windows/libpq/lib -lpq -lpgport -lpgcommon ...`; 7a F the same,
    `phase7/kappa/logs/F/outputs/RPostgres.out:9`). So i becomes ok only
    through the network, conda's libpq unused; offline it is expected to
    fail (UNVERIFIED; step 1 records it, Am7).
  - Makeconf: r-zig's Makeconf.win has `PKG_CONFIG = pkg-config` (P6
    `scripts/verify-tree.sh`, the Makeconf line list) and
    `BINPREF=$(R_HOME)/bin/toolchain/` (P6 build.zig, the Makeconf
    writer's `mk.put("BINPREF", ...)`); RPostgres' `PKG_CONFIG ?=
    $(BINPREF)pkg-config` comes out bare only because its `:=` is
    expanded before Makeconf is read. Either way the bare name decides.
  - The two probes side by side: `pkg-config --libs libcurl` under M
    lists libcurl's private libs three times and `-L.../Library/bin`
    (`logs/M/probe.log:110`); under pkgconf only the public `Libs`
    (`logs/N/probe.log:110`).
- pkgconf adds `Libs.private` only with `--static` or a personality that
  asks for it (SRC `cli/core.c:1107`); its default personality is used
  for the name `pkg-config.exe`, since only a name containing `-pkg`
  selects a cross personality (SRC `cli/main.c:91-93`). That is what
  unix's pkg-config does: Windows then links as linux and macOS.
- Both packages call a bare name or Makeconf's name, so only the
  program behind `pkg-config` decides them; a `PKG_CONFIG=pkgconf`
  variable would reach RPostgres and not ncdf4.
- No regression in the 62-package sample: every package M installed, N
  installed too, except the RcppParallel chain (KN h, g: busybox's `/C/`
  paths, not pkgconf); N's extra successes are exactly d and i (KN
  "Summary of the table"; 7a: "missing list identical to N").

**Risk: under-linking static libraries.** Without `--static`, a `.pc`
whose library exists only as a static archive and lists its own
dependencies in `Libs.private` links without them (undefined symbols).
None of the 62 packages hit it (above); conda-forge's win-64 libraries
are mostly DLLs with import libraries. A package that needs the
private libs can still ask `pkg-config --static`. The stress dispatch
(L, Am8) reads every Windows pkg-config row; a new undefined-symbol row
is recorded with its `.pc` and goes back to the user. UNVERIFIED beyond
those rows.

**Second risk: paths with spaces (C2).** pkgconf escapes spaces in the
values it derives from `prefix` (`-IC:/.../r\ z/...`), but not literal
absolute paths in a `.pc`'s `Libs`, and once printed a doubled `r\\\ z`:
`phase7native/kappa/logs/N-space/probe.log:78`, `pkg-config --cflags
--libs libcurl` under `...\r z\` gives `-IC:/Users/admin/rz-p7n/r\ z/...`,
`-IC:/Users/admin/rz-p7n/r\\\ z/...` and an unescaped
`C:/Users/admin/rz-p7n/r z/.../Library/lib/z.lib`, which sh splits into
two words (7a's twin run: the same doubled escape). KN's and 7a's space
runs never linked through pkg-config output (data.table, Rmpfr), so they
say nothing about it. Hence: Am7's space run puts the libraries env
under the space path too and pre-registers ncdf4 as likely FAIL; Am9's
btPc pins the escaped `prefix` case in CI; README says that neither R's
install path nor the libraries env's path may contain spaces.

**Options** (approved: (a), 2026-10-20).
- (a) ★ pkgconf 3.0.7 behind both names on both channels (this
  amendment; with Am2 and Am3). Within the approved F (a): the only new
  package is `pkgconf ==3.0.7`.
- (b) The plan as written: `pkg-config` stays 0.29.2 (with its glib
  closure, 3.5 MB), `pkgconf` is pkgconf. ncdf4 and RPostgres keep
  failing on Windows (as stress expects today: `stress/packages.tsv`
  ncdf4 `windows=fail-upstream`, RPostgres `windows=fail-abi`).
- (c) The tree takes pkgconf for both names, conda keeps 0.29.2 for
  `pkg-config`: one name, two programs across the channels.
- Reason for (a): one rule, the same on both channels and the same as
  unix's semantics; ncdf4 is fixed and RPostgres installs (by its
  download); the tree loses six files (3.1 MB raw).

**Plan text replaced.** §0's table: the "pkg-config" row becomes
"pkg-config, pkgconf | pkgconf 3.0.7: `Library/bin/pkgconf.exe` (twice:
`pkgconf.exe`, `pkg-config.exe`), `pkgconf-8.dll`, and
`vcruntime140.dll` (vc14_runtime) | `usr/bin/`"; the "pkgconf (open point
F a)" row goes. §3 build.zig's `usr` copies: the seven pkg-config lines
(`pkg-config.exe`, `glib-2.0-0.dll`, `iconv.dll`, `charset.dll`,
`intl-8.dll`, `pcre2-8.dll`, `vcruntime140.dll`) and the two pkgconf
lines become:

```zig
        // pkg-config and pkgconf: conda-forge's pkgconf (MSVC) under both
        // names, with its DLL (PHASE7 amendment Am1): it adds Libs.private
        // only with --static, as unix's pkg-config does. The three pkgconf
        // files are in_conda: conda-forge ships no pkg-config.exe, and the
        // DLL beside them keeps the exe off whatever pkgconf the env solves
        // (B41); vcruntime140.dll comes from vc14_runtime on PATH there, as
        // the binutils' zstd.dll does.
        .{ .from = "Library/bin/pkgconf.exe", .to = "bin/pkgconf.exe", .in_conda = true },
        .{ .from = "Library/bin/pkgconf.exe", .to = "bin/pkg-config.exe", .in_conda = true },
        .{ .from = "Library/bin/pkgconf-8.dll", .to = "bin/pkgconf-8.dll", .in_conda = true },
        usrBin("Library/bin/vcruntime140.dll"),
```

and the comment "pkg-config is conda-forge's native build (MSVC) with
its glib closure" goes. Two `file:` lines with the same `from` are
fine: verify-toolchain.sh keys them by the path here (P6
`scripts/verify-toolchain.sh`, the `file:` awk, `print $4, $5`), and
`writeSources` writes one line per copy (P6 `zigbuild/toolchain/conda.zig`,
`writeSources`). Step 2's unit tests add a `writeSources` case with two
copies of one file under two names. §11 F becomes a record (Am19). §12's
"pkgconf for both names" bullet is removed (Am19). Risk 5 becomes the
under-linking risk above, risk 12 (glib's LGPL closure) goes, and the
space risk joins risk 10.

## Am2. conda's win-64 r-zig-build-tools under Am1 (task item 1)

**What.**
- The toolchain build's three `in_conda` copies in `usr/`
  (`TC/usr/bin/pkgconf.exe`, `pkg-config.exe`, `pkgconf-8.dll`; C3) are
  installed into the env by the conda build, with `usr/SOURCES` (one
  block, pkgconf) and `usr/LICENSES/pkgconf/`. Every other `usr/` copy
  and every m2 tree stays standalone-only (`prefix_is_env`), as planned.
  `vcruntime140.dll` comes from vc14_runtime, in the env root and
  `Library/bin` (`phase7plan/pkgs/vc14_runtime-14.51.36247-habf1de7_41/root/`).
- recipe.yaml:
  - r-zig-build's win `host:` list gains `pkgconf ==3.0.7 *_0` beside
    `binutils_impl_win-64` (C8: rattler-build solves host fresh, so
    `==3.0.7` alone would take a later rebuild of 3.0.7; the build
    string's `_N` suffix pins it, as the flang pins' comment says), with
    the binutils entry's reason in its comment (the toolchain build
    copies from `$PREFIX`; P6 `recipe/build.sh` sets
    `CONDA_PREFIX="$PREFIX"`, and the host comment says binutils "must
    be in *host* too").
  - r-zig-build's `requirements` gain `ignore_run_exports: from_package:
    [pkgconf]`: pkgconf's weak run_export (`pkgconf >=3.0.7,<4.0a0`,
    `phase7plan/pkgs/pkgconf-3.0.7-h6a83c73_0/root/info/run_exports.json`)
    would otherwise reach r-zig-slim, which inherits r-zig-build's
    run_exports (`inherit: r-zig-build`, no `run_exports: false`; the
    three group outputs set it false). Whether a staging output's ignore
    list filters what r-zig-slim inherits is rattler-build behaviour no
    one has checked (C11): step 5 reads `info/index.json` of all four
    win-64 outputs; if r-zig-slim lists pkgconf, the ignore moves to (or
    is added in) r-zig-slim's own `requirements.ignore_run_exports` and
    conda-package reruns. Which placement rattler-build honours is
    recorded beside B41.
  - r-zig-build-tools: `files` gains `Library/lib/R/bin/toolchain/usr/**`
    (win); run requirements gain `pkgconf >=3.0.7,<4.0a0` (F a's approved
    run dependency: the `pkgconf` name outside R). With the DLL in TC it
    no longer carries R's pkg-config; it stays as approved (dropping it
    is the user's call, not proposed). `pkg-config` **stays**, with the
    comment "kept for its activation's PKG_CONFIG_PATH (Am3), which
    test-build-tools.R checks; under R CMD and in R the build-tools
    group's usr/bin/pkg-config.exe (pkgconf) comes first" (S6).
  - r-zig-build-tools `package_contents` `exists` gains
    `Library/lib/R/bin/toolchain/usr/bin/{pkgconf.exe,pkg-config.exe,pkgconf-8.dll}`,
    `.../usr/SOURCES`, `.../usr/LICENSES/pkgconf/**`; its win
    `license:` becomes `GPL-3.0-or-later AND MIT`; its comment "unix holds
    no file" stays.
- recipe/test-build-tools.R (Windows), testing what R uses (S6) and
  comparing paths with `normalizePath(x, winslash = "/")` and the
  existing `same_path()` on both sides (C5: `Sys.which` returns 8.3
  names):
  - under R CMD (`Rcmd.exe Rscript.exe -e ...`), `Sys.which("pkg-config")`
    and `Sys.which("pkgconf")` are `TC/usr/bin/pkg-config.exe` and
    `TC/usr/bin/pkgconf.exe`;
  - `PKG_CONFIG_PATH` contains `Library/lib/pkgconfig` (the reason
    pkg-config stays a run dependency), and `pkg-config --modversion
    <m>` succeeds, `<m>` the first `.pc` in the test env's
    `Library/lib/pkgconfig` (the test picks it; none is named here);
  - `TC/usr/bin/pkg-config.exe --version` runs, exit 0, with PATH =
    System32 + the env root only (vcruntime140.dll from the env root;
    the DLL beside it, C3).
  - The existing bare `pkg-config --version` check (B43; it answers the
    env's 0.29.2 on the narrowed PATH) goes: it tests conda-forge's
    package, not R (S6). No version string is compared with SOURCES
    (S4): the `file:` lines' sha256 already name the bytes.

**Why.** conda-forge's pkgconf on win-64 ships no `pkg-config.exe`
(its files: `Library/bin/{pkgconf.exe, pkgconf-8.dll, bomtool.exe,
pccritic.exe, spdxtool.exe}`, headers, `pkgconf.lib`, `libpkgconf.pc`,
`pkg.m4`, docs, man pages; no `etc/conda/activate.d`), so the only way
for `pkg-config` to be pkgconf in a conda env is a copy. Under
`TC/usr/bin` it clobbers no other package's file (a copy in `Library/bin`
would collide with pkg-config's), and Rcmd_environ's PATH line and patch
0014 already put `TC/usr/bin` first. The DLL is copied too (C3, S5 b):
`pkgconf.exe` imports `pkgconf-8.dll`, the run dependency lets the env's
DLL move to any 3.x, and libpkgconf's soversion has changed within a
major before (pkgconf NEWS: 5 in 2.x, 8 in 3.0); Windows loads a DLL
from the exe's own directory first, so TC's exe always runs its own
DLL, and the conda layout equals the tree's for `pkg-config`/`pkgconf`
(three files, 193,536 B raw). It follows B41's binutils rule: conda
carries copies of what conda-forge does not provide where R needs it.

**Replaces** (with S7's additions). §0's conda bullet ("No file is added
to the package"); §3 recipe.yaml's F bullet; §3 test-build-tools.R; §4's
r-zig-build-tools row ("win-64: + `pkgconf` (F a); no file change") and
its last paragraph (`TC/usr/bin` now exists in a conda env, holding the
three pkgconf files only); step 2's conda-rule test (the build log's
toolchain line names `binutils/ (binutils_impl_win-64)` and `usr/
(pkgconf)`, no `etc/`); step 5's "package_contents of r-zig-build-tools
unchanged (binutils only)"; and every statement of the in_conda
invariant, which becomes one sentence: "the conda build installs only
the in_conda copies: Windows' binutils (B41) and usr/bin's pkgconf
files (Am2)". That sentence goes in the toolchain build.zig `//!`
paragraph ("except Windows' binutils ... only those are installed") and
the `Copy.in_conda` doc; plan §3's header note ("'only those [binutils]
are installed' stays true", PHASE7-IMPLEMENTATION.md:586-587); step 2's
skeptical-review item ("every copy in_conda = false" becomes "every
usr/ copy in_conda = false except the three pkgconf files", :370-371);
and the "Files that need no change: recipe/build.sh" entry (:1048-1049:
`etc/` and the m2 files are skipped there, usr/bin's pkgconf files are
not).

## Am3. PKG_CONFIG_PATH in Rcmd_environ (task item 1)

**What.** None for now: Rcmd_environ gets no PKG_CONFIG_PATH line,
after one measurement in conda (below, C4).

**Why.**
- pkgconf in `TC/usr/bin` searches `TC/usr/lib/pkgconfig` and
  `TC/usr/share/pkgconfig` by default (exe-relative on Windows: SRC
  `libpkgconf/personality.c:43-80`, `%s/../lib/pkgconfig` and
  `%s/../share/pkgconfig` from `GetModuleFileName(NULL)`), which hold
  nothing, so it needs PKG_CONFIG_PATH (KN: "with `PKG_CONFIG_PATH=` it
  gives Package 'libpng' not found"; 7a the same).
- Where the libraries are, something already sets it: in a conda env,
  pkg-config's activation script (`set "PKG_CONFIG_PATH=%CONDA_PREFIX%\Library\lib\pkgconfig;%PKG_CONFIG_PATH%"`,
  `pkg-config-0.29.2-hffdb5b9_1013/root/etc/conda/activate.d/pkg-config_activate.bat`),
  which Am2 keeps and test-build-tools.R now asserts; in the dev env and
  stress, the same activation (pixi run); for a standalone R over a
  libraries env (R_ZIG_EXTRA_ENV), that env's activation only if it
  contains the pkg-config package, otherwise the user (as Am7's
  libraries env does), as on unix, where R sets no PKG_CONFIG_PATH
  either. The standalone tree has no `.pc` file.
- What conda loses against today (C4): pkg-config 0.29.2 in
  `Library/bin` searches `Library/lib/pkgconfig` and
  `Library/share/pkgconfig` by default, even with PKG_CONFIG_PATH unset
  (`phase7native/kappa/logs/M/probe.log:105-112`: "no PKG_CONFIG_PATH
  exit=0"); activation adds only `Library\lib\pkgconfig`. Under R CMD
  TC's copy answers, so a `.pc` only in `Library/share/pkgconfig`, or
  any `.pc` for a configure that clears PKG_CONFIG_PATH, is no longer
  found. Which win-64 packages R users link put `.pc` files in
  `share/pkgconfig` is UNVERIFIED (on linux the dev env's xorgproto
  ones do). Step 5 measures it in the conda-consume env and the stress
  env: `ls Library/share/pkgconfig/*.pc`, and `pkg-config --list-all |
  wc -l` under R CMD against `Library/bin/pkg-config.exe --list-all |
  wc -l`. Equal: (a) stands and the counts are recorded. Different:
  (b) goes to the user with the lists.
- Correction (C4): the earlier reason against a relocatable default
  rested on the spelling `${R_HOME}/../pkgconfig`, which gives a wrong
  prefix. A spelling ending in `/lib/pkgconfig` is right: pkgconf
  redefines `prefix` on Windows by default (SRC `cli/core.c:1126-1131`)
  by trimming the `.pc` name, requiring `pkgconfig`, and trimming twice
  (`libpkgconf/pkg.c:386-405` `determine_prefix`; `pkgconf_path_relocate`
  folds separators and keeps `..`). For
  `<R_HOME>/../../lib/pkgconfig/x.pc` the prefix is `<R_HOME>/../..`,
  i.e. `<root>/Library` in conda, and the tree's own (empty)
  `Library/lib/pkgconfig` in the standalone tree (TC is
  `Library/lib/R/bin/toolchain`). From the source; not run.
- Also outside R's control (C12): pkgconf 3.0.7 on Windows reads extra
  search directories from the registry (HKCU and HKLM
  `Software\pkgconfig\PKG_CONFIG_PATH`, with a deprecation warning on
  stderr; SRC `libpkgconf/client.c:72-79`, `path.c:547-582`), and drops
  `-I` flags whose directory is in INCLUDE (MSVC's), CPATH,
  C_INCLUDE_PATH or CPLUS_INCLUDE_PATH, and `-L` flags in LIBRARY_PATH
  (`client.c:185-191`). Likely low impact: rzig adds the env's include/
  and lib/ itself (P6 `zigbuild/tools/rzig/main.zig`, the extra-env
  paths). No code change, no test; one README sentence and one PLAN
  line.

**Options** (approved: (a), 2026-10-20, with the measurement).
- (a) ★ No line; README says that R's pkg-config (pkgconf in
  `TC/usr/bin`) searches only PKG_CONFIG_PATH (plus the registry key
  above, and it filters by INCLUDE, CPATH and LIBRARY_PATH); a conda or
  pixi env's activation sets it only when the env has the pkg-config
  package; otherwise set `PKG_CONFIG_PATH=<env>\Library\lib\pkgconfig`.
- (b) only if step 5's counts differ: one Rcmd_environ line,
  `PKG_CONFIG_PATH=${PKG_CONFIG_PATH-${R_HOME}/../../lib/pkgconfig;${R_HOME}/../../share/pkgconfig}`,
  the same on both channels, covering an unset PKG_CONFIG_PATH (an
  activated env still lacks `share/` under this form). Not
  PKG_CONFIG_LIBDIR: it would replace Rtools' own default under
  R_CUSTOM_TOOLS_PATH. Not `PKG_CONFIG_DONT_DEFINE_PREFIX`: the
  spelling above keeps the prefix right.
- Reason for (a): nothing to point at in the tree, and conda's
  activation covers `lib/pkgconfig`; (b) waits for evidence that
  `share/pkgconfig` matters.

## Am4. PATH order and the clash test (task item 2)

**What R does today (P6), confirmed right.**
- Rcmd_environ (P6 build.zig `rcmdEnviron`):
  `PATH="${R_CUSTOM_TOOLS_PATH:-${R_ZIG_TOOLS_PATH}};${PATH}/"`, with
  `R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin`: the group's dir
  comes before everything inherited, Git for Windows' `usr\bin` included,
  whatever the caller's order; rcmdfn.c then puts `bin\x64` before it.
- Patch 0014 (plan §3) prepends the same directory in sessions.
- m2-make runs recipes with `/bin/sh` inside its own MSYS root (`TC`, so
  `TC/usr/bin/sh.exe`, CRITIQUE "Checked and found right"), never PATH's
  first `sh.exe`. KN's stringi failure k (Git's sh first) was native
  make picking PATH's first `sh.exe` (`SHELL=C:/Program Files/Git/usr/bin/sh.exe`,
  KN GP probe), which does not happen with m2-make.

**Amend patch 0014.** R's Rtools block and the plan's line use
`Sys.getenv("R_CUSTOM_TOOLS_PATH", <default>)`, which returns "" for a
variable set to empty, while Rcmd_environ's `:-` treats empty as unset.
The hunk becomes:

```r
local({
    path <- Sys.getenv("R_CUSTOM_TOOLS_PATH")
    if (!nzchar(path)) path <- file.path(R.home(), "bin", "toolchain", "usr", "bin")
    Sys.setenv(PATH = paste0(path, ";", Sys.getenv("PATH")))
})
```

verify-bundle's scenario 1 session check (plan §3) adds a run with
`R_CUSTOM_TOOLS_PATH=` (empty): the first entry is `TC/usr/bin`, as
under R CMD.

**The clash test (M a), defined** (trimmed per S3, MSYSTEM per C10/S8).
Two runs, in verify-bundle's clash block (windows-latest, kappa) and in
step 1. Every `Sys.which` assertion compares `normalizePath(x, winslash
= "/")` on both sides, case-insensitively (C5).
1. **Git first**: the caller's PATH = Git's `usr\bin`, then `bin\x64` +
   System32, with `MSYSTEM=MINGW64` (Git Bash exports it; MSYS's `uname`
   reads it). Asserted: under R CMD and in a session `Sys.which` of `sh`,
   `make`, `sed` and `pkg-config` is `TC/usr/bin`'s; `R CMD gcc.exe
   --rzig-check=build-tools` names TC's make and sh; btA, btLib, btTools,
   btPc and fcconf pass. Added (S3, risk 1's real case): one
   btTools-style step whose configure.win, through TC's sh, runs a
   program only Git's `usr\bin` has (`diff` of two scratch files, and
   `cygpath -m /`), asserts its output, and greps the log for
   "cygheap", "fork: retry" and "*** fatal error": two msys-2.0.dll in
   one process tree. Recorded: `uname -s` under R CMD sh (MSYS_NT or
   MINGW64_NT).
2. **Git after**: Git's `usr\bin` appended after System32: the
   `Sys.which` and `--rzig-check` assertions only, no package
   re-installs (for every name TC has, R CMD and the session put TC
   first whatever the caller's order, so the installs would repeat run
   1; S3). Both orders stay tested, as M (a) was answered.
3. On kappa only, under run 1: stringi (KN k's multi-line winshlib
   recipe over hundreds of objects) and RcppParallel (MSYS Makefiles,
   KN h), once (S3: KN has both ok under M; they leave the base s3-set
   list, Am7); and Rmpfr, qfratio and winch (C10, S8), recording their
   "checking build system type" lines next to the base run's. Equal
   triplets (`x86_64-pc-msys`): recorded, and the PLAN record says the
   caller's MSYSTEM does not change builds. Different: the logs go back
   to the user with (a) ★ record only and README advice, or (b) one
   `rcmdEnviron` line `MSYSTEM=MSYS` (no patch), so builds do not depend
   on the caller's shell. Until then UNVERIFIED in the PLAN record.
- Elsewhere `cannot_check`, as planned (Git's MSYS exists on every
  windows-latest image).

**conda's Git-first case.** In a conda env `TC/usr/bin` holds only
the three pkgconf files (Am2), so with Git's `usr\bin` before the activated
env, Git's `sh` answers under R CMD (`R CMD INSTALL` runs `sh
configure.win`) while make is m2's (Git ships none): two msys-2.0.dll in
one tree (risk 1). Activation puts the env first, so this needs a user
who prepends Git after activating. Never run with m2. Step 5's by-hand
runs add it (PATH = Git's `usr\bin`, then the activated PATH): s3-set.R,
recorded.
- (a) ★ Record only; README's conda paragraph says to keep the
  activated env first.
- (b) `R_ZIG_TOOLS_PATH` also names R's own env's MSYS dir,
  `${R_HOME}/bin/toolchain/usr/bin;${R_HOME}/../../usr/bin` (a missing
  directory in the tree; conda's `Library/usr/bin`), and patch 0014 the
  same: R puts its build tools first on both channels whatever the
  caller's PATH. It changes conda's unactivated case (check.zig's "is
  installed in R's environment, which is not on PATH" would no longer
  appear under R CMD).
- Reason for (a): no failure seen; (b) changes conda behaviour that
  phase 4 tested (PHASE4 open point I a). If step 5's run fails, (b) goes
  back to the user with the log.

**Replaces.** §3 patch 0014's code block; §3 verify-bundle "The clash
(M a)" bullet and the scenario 1 bullet; step 1 "The clash"; step 5's
by-hand bullet; §11 M (a)'s wording ("before and after R's entries"
becomes runs 1-3 above; both orders kept).
## Am5. What the m2 set does not need (task item 3)

Confirmed from KN's M column and F1 table; none of these joins phase 7:

| native-only item | needed with m2? | evidence |
|---|---|---|
| F1: R's install.R single-quoted `SHLIB_LD='...'`, `PKG_LIBS='...'` (an R source patch) | no: MSYS make passes them through its MSYS sh | KN F1 table: M row ok in all six cells, stock DB (`KN:129`); Rcpp ok 81 with no `*` and minqa (Fortran + C++) ok 9 under M (`KN:58,63`) |
| a cmake forwarder (`MSYS Makefiles` → `Unix Makefiles`) | no: RcppParallel's hard-coded `-G "MSYS Makefiles"` works with MSYS make and sh, which read `/C/...` | M: RcppParallel ok, qs2 ok, stringfish ok (`KN:85,87,92`); Rcmd_environ keeps `CMAKE_GENERATOR=${CMAKE_GENERATOR-'MSYS Makefiles'}` (P6 `rcmdEnviron`) |
| `CONFIG_SHELL` | no | M's probe: `CONFIG_SHELL=` empty (`logs/M/probe.log:3`); Rmpfr (autoconf) ok 67 (`KN:69`) |
| `TMPDIR` | no: MSYS maps `/tmp` (the plan's `etc/fstab` `/tmp usertemp` makes it `%TEMP%`) | KN probes: "Under M, MSYS rewrites TMPDIR to /tmp"; 7a: no package needed TMPDIR even under busybox (7a "CONFIG_SHELL and TMPDIR (Z4)") |
| `build_alias` / a `CONFIG_SITE` file | no: the remedy was for busybox ash upper-casing imported names; MSYS bash keeps `build_alias` | 7a "Why build_alias cannot work" and `logs/run/build-alias.log` ("Git's MSYS sh keeps `build_alias`") |
| MAKEFLAGS repair | no: busybox's backslash-to-slash conversion of imported values | 7a "MAKEFLAGS"; RcppParallel ok under M |
| launchers, busybox env patch, `BB_OVERRIDE_APPLETS` | no: m2's files are real .exe copies | §0 |

- config.guess: under m2 `uname -s` is `MSYS_NT-10.0-22621` (KN probes),
  which config.guess knows (`x86_64-pc-msys`), as with Rtools'
  identical userland. qfratio is the config.guess test (UNVERIFIED under
  m2; step 1 runs it, Am7). winch is not (C6): its bundled
  libbacktrace configure also needs an `ld` on PATH (libtool's
  LT_PATH_LD) and the toolchain has none, so it is expected to install
  with `winch_available()` FALSE ("no acceptable ld found in $PATH",
  `phase7/kappa/logs/F-cg-site2/outputs/winch.out:70-71`). A qfratio
  failure goes back to the user; `build_alias` would then work (MSYS
  keeps the name).
- Patch numbering stays 0001-0014 (0014 = Rprofile.windows); the parked
  plan's F1 patch (7a's "patch 0015") is not part of phase 7.
- **Dropped from step 1**: "Recorded, not a gate (B b, A b)": conda-forge's
  native make in place of m2's, and uutils-coreutils. KN's Nc row
  already records native make (stock R fails F1: `x.cpp` exit 0, no DLL;
  `KN:127`), and PS records uutils 0.0.20's missing `touch`, `uname`,
  `chmod`. B (b)/(c)'s and A (b)/(c)'s records cite those instead (§10
  B11).
- §0 "Not in phase 7" gains: busybox-w32, the native GNU make build, the
  F1 patch, the cmake forwarder, CONFIG_SITE/build_alias settings, the
  launchers (the parked native work, `wt/feat-userland`, untouched); §7's
  "native make and uutils in the prototype" row goes.

## Am6. System32 names win in R's own lookups (KN F5)

**What.** R's `Sys.which` (and `system()`'s CreateProcess search) look in
System32 before PATH: with the tools first on PATH, `find` is
`C:\Windows\SYSTEM32\find.exe`, `bash` is WSL's
`C:\Windows\SYSTEM32\bash.exe` and `tar` is bsdtar, under M as under N
(`logs/M/sys-which.tsv`: find, bash, tar). m2-coreutils also ships
`sort`, `expand`, `hostname`, `timeout` and `whoami`, all System32
names too (C5; `phase7plan/pkgs/m2-coreutils-8.32.5-hc364b38_6/root/Library/usr/bin`;
KN never probed them). Inside sh and make (MSYS's lookup) the group's
names win. cmd.exe scripts run under R CMD find GNU `find` first (KN
"cmd's find is shadowed"), as with Rtools.
- Risk 6 is rewritten: "R code's `system()` and `Sys.which()` of
  `find`, `sort`, `expand`, `hostname`, `timeout`, `whoami`, `tar` and
  `bash` (WSL's) get System32's programs, not the group's; sh, make and
  configure scripts get the group's; a `.bat` run under R CMD gets GNU
  `find` (as with R's installer and Rtools)".
- test-build-tools.R and verify-bundle's session checks (Am4) compute the
  exclusions instead of listing them: `shadow <-
  file.exists(file.path(Sys.getenv("SystemRoot"), "System32",
  paste0(names, ".exe")))`; the shadowed names are checked by path, the
  rest through `Sys.which`, every comparison on `normalizePath(x, winslash
  = "/")` with `same_path()` (8.3 names: 7a's `...\PKG-CO~1.EXE`, M's
  `PIXI-C~1\CACHED~1\...`). verify-bundle's btTools already runs `find`
  through sh (no change).

## Am7. Step 1's kappa set (task items 1-3, 6)

Replaces step 1's "A libraries env", "Real packages" and "R_HOME with a
space" bullets where they differ (step 1 now runs on step 2's tree,
Am18):
- **Environment, stated once** (S9): what a user of the tree has:
  `R_TOOLS_SOFT` unset, no `MAKEFLAGS`, no `CONFIG_SHELL`,
  `CMAKE_GENERATOR` unset (Rcmd_environ's default), Ncpus = 2. KN's M
  had `R_TOOLS_SOFT=<env>/Library` (stress.R's emulation of Rtools'
  library root, read by Makeconf's LOCAL_SOFT) and `MAKEFLAGS=-j4`
  (`logs/M/probe.log:3`, `scripts/run-cfg.bat:51`). A package that fails
  only without them is recorded as a stress-only setting, not a tools
  failure, and goes back to the user.
- The libraries env adds libnetcdf, libpq, libboost-headers (RPostgres'
  BH headers, stress S18) and cmake (RcppParallel's TBB; not a B39 name).
  It has no pkg-config package, so `PKG_CONFIG_PATH` is set by hand
  (Am3). The `ls Library/bin` check also asserts no `pkg-config.exe`,
  `pkgconf.exe` or `make.exe` there, so only TC's answer.
- s3-set.R adds ncdf4 and RPostgres (Am1, with conda-forge's MSVC build
  of pkgconf, which no kappa run used yet: KN's and 7a's were zig
  builds), qfratio 1.1.2 and winch 0.1.3 (Am5; their smokes as 7a's
  run2.R; CRAN tarballs downloaded with the rest, 7a's sha256s: qfratio
  `6b22d2a4...`, winch `46031b6c...`). stringi, RcppParallel, Rmpfr,
  qfratio and winch also run under the clash's run 1 (Am4); stringi and
  RcppParallel only there (S3).
- RPostgres' branch is asserted (C1): its output contains
  `../tools/winlibs.R` and not "using libpq from Rtools"; the link line
  is recorded. A second install with the network blocked
  (`http_proxy`/`https_proxy` set to `http://127.0.0.1:9` for that run;
  whether winlibs.R's download honours them is UNVERIFIED, and the log
  shows it) is recorded as the offline result.
- Expected (KN's M column, with R_TOOLS_SOFT set there; Am1 and Am5
  applied):

| package | KN M | expected here |
|---|---|---|
| Rcpp, glue, ps, data.table, minqa, units, Rmpfr, systemfonts | ok | ok |
| pak | not in KN | ok (UNVERIFIED) |
| ncdf4 | FAIL d | ok: links the env's `-lnetcdf` |
| RPostgres | FAIL i | ok through winlibs.R's download (libpq-15.12 bundle; conda's libpq unused); offline FAIL expected (UNVERIFIED) |
| stringi, RcppParallel (run 1) | ok | ok |
| qfratio | never ran under M | config.guess `x86_64-pc-msys`, ok (UNVERIFIED) |
| winch | never ran under M | installs, `winch_available()` FALSE: no `ld` (C6); its configure line recorded; not counted in m2's matrix |

- The ld gap (rzig's answer to `-print-prog-name=ld`, and no `ld` named
  anywhere, B43) is recorded as a toolchain follow-up for the user, not
  phase 7.
- The probe `pkg-config --libs libcurl` (as KN's probe.sh) lists
  libcurl's public libs only, as `logs/N/probe.log:110`.
- **The space run** (`C:\r zig\`, C2): R_HOME **and** a second libraries
  env under the space path (as 7a's SP did), ncdf4 added. Pre-registered:
  ncdf4 likely FAIL (UNVERIFIED), cause libcurl.pc's unescaped
  `.../Library/lib/z.lib`; the link line is recorded. A FAIL there is
  the README's "no spaces in the libraries env's path", not a phase 7
  gate.
- The clash runs per Am4.

## Am8. stress expectations (step 6)

`stress/packages.tsv` (P6): ncdf4 `windows=fail-upstream` and RPostgres
`windows=fail-abi` (their notes name exactly the private-libs causes).
With Am1 both are expected ok on Windows, by different routes. Step 6's
changes gain `stress/packages.tsv`, only after the L dispatch's rows show
ok (read row by row, Cr13):
- ncdf4: `windows=ok`, note "phase 7 (2026-10): pkg-config is pkgconf;
  Libs.private only with --static".
- RPostgres: `windows=ok`, note "windows (phase 7): pkgconf's --libs
  libpq has no wldap32, so Makevars.win takes winlibs.R's r-windows
  libpq-15.12 bundle (network)" (C1).
- The L dispatch (plan step 6) adds `-f distribution=both -f
  channel=local` (C7; `.github/workflows/stress.yaml` inputs
  `distribution`, `channel`; `channel=local` builds the PR's own
  conda-package): the conda windows rows for ncdf4, RPostgres, stringi
  and RcppParallel then run on the PR's r-zig-build-tools, and are read
  row by row with the tree rows. packages.tsv holds one expectation per
  OS, not per distribution, so the note also says: a `channel=universe`
  conda run fails ncdf4 (and RPostgres) until `_N` is published; rows
  read before then are not regressions.

## Am9. verify-bundle's btPc (step 4)

Replaces §3 verify-bundle's btPc bullet. `btpc.pc` gets `Libs:
-lbtpc_pub` and `Libs.private: -lbtpc_priv` (no library needed: only
the flags are read), and `Cflags: -I${prefix}/include -DBTPC=7` with a
header there. Its directory is `<d>/lib/pkgconfig/`, `<d>` a scratch
directory whose name contains a space (C2). configure.win asserts,
through the group's sh (no version strings, S4):
- `pkg-config --libs btpc` has `-lbtpc_pub` and no `-lbtpc_priv`;
  `pkg-config --static --libs btpc` has both (the d behaviour);
- `pkg-config --variable=prefix btpc` is `<d>` (Windows' prefix
  redefinition) and `--cflags` carries the escaped space;
- `pkgconf` gives the same `--libs` as `pkg-config`;
- the package compiles through make and sh with those `--cflags`, and
  `f()` returns 7: the escape path runs on windows-latest every CI run.
`PKG_CONFIG_PATH` is `<d>/lib/pkgconfig`, as planned (Am3). Not taken:
C12's optional INCLUDE-filter run (no R behaviour depends on it).

## Am10. verify-toolchain's usr/ checks (O a, step 2)

Replaces the names list in §3 verify-toolchain.sh:
- the names: B39's list as planned, and `pkg-config` and `pkgconf`
  (no "with F a" condition): each present, its sha256 equal to its
  `file:` line in usr/SOURCES (as today), and running `--version` exit 0
  with PATH = System32 alone.
- No `--version` string comparison for pkg-config or pkgconf (S4): the
  `file:` lines (`Library/bin/pkgconf.exe -> bin/pkg-config.exe <sha256>`)
  already prove the bytes, and step 2's existing "sed.exe replaced by
  another file" negative case covers a swapped binary. The plan's make
  version check (O a, answered) stays as written.
- No 0.29.2 swap case: after Am1 its DLLs are gone, so it would fail on
  a DLL load, never on a version, and could raise a loader dialog (C9).

- bt.R (plan §3 verify-bundle, step 4): on Windows the make block
  asserts identity, `Sys.which("make")` is `TC/usr/bin/make.exe`
  (normalised, Am6), not a version computed a second time (S4); unix
  keeps its `$make_version` check.

## Am11. Measurements (step 1, §7)

- Dropped: Cr18's cold/warm `R CMD sh -c true` and risk 13. KN and 7a
  measured the first exec of each fresh binary: 26-102 ms, then 5-18 ms,
  no detection or quarantine (`KN` "Defender", 7a "First exec after
  extraction"). The plan's own first `verify-toolchain` and scenario 3
  times still show any outlier.
- Kept: Cr12's `R CMD config` count and time (J's threshold, risk 7).
- Recorded for the PLAN record, not measured again: MSYS process start
  about 31 ms against busybox's 16 (KN "Timing"), with equal compile
  times on the 21 packages both sets installed (881.1 s M, 879.6 s N).
- Added to §7: step 1's `pkg-config --libs libcurl` line and ncdf4's and
  RPostgres' results.

## Am12. Paths past MAX_PATH and non-ASCII paths (task item 6)

- Past MAX_PATH (about 260 characters to a tool): R's `system2` reports
  "not found", make fails with e=206 and in `getcwd`, though
  LongPathsEnabled=1 (7a "The long path"; busybox launchers were the
  object there, m2 was not run: UNVERIFIED for m2). A limit of R and
  GNU make, not of phase 7. Recorded in PLAN's phase 7 record and one
  README sentence beside risk 10's ("keep R's install path short");
  no test.
- Non-ASCII: under `C:\...\r ü中\` R itself does not start ("unable to
  open the base package"); r-zig's Rterm/Rscript/R carry no
  `activeCodePage` manifest and kappa's ACP is 1252 (7a "Space path (SP)
  and its non-ASCII twin"). R's own manifest is a separate PR, not phase
  7; phase 7's space run stays ASCII (`C:\r zig\`).

## Am13. Line references (task item 4)

P6 changed since the plan (the build-number revert to 8 and the
CONDA_PUBLISH gate landed: recipe.yaml's "8 stays" entry at the
`number: 8` line, build.yaml's publish step, pixi.toml's and README's
notes). Every hunk phase 7 shares was re-read; the plan's references,
by name, with today's lines for orientation only:

| plan reference | name to cite | today (P6) |
|---|---|---|
| build.zig 2496-2549 | `rcmdEnviron` (doc comment and the line list after `RCFLAGS`) | doc 2496-2526, fn 2527-2550 |
| build.zig 3502-3506 | the library stage's `profile:` block (Common.R + Rprofile.<os>) | 3502-3506 |
| toolchain/build.zig 15-33 | the `//!` "What it installs" block and its line "Windows' usr/bin comes in phase 7." | 14-33 |
| toolchain/build.zig `Tree` | `const Tree` | 84-89 |
| `windows_dirs`, the trees loop's `conda.inDir(from)` | `windows_dirs`; `build()`'s trees loop | 148, 224 |
| `readRecords`, `installLicenses` | same | 421, 494 |
| conda.zig `inDir`, `writeSources` | same | 213-216, ~280-296 |
| groups.zig 25-31, 133, 224 | the module doc's build-tools sentence; `text`'s Windows build-tools branch; its test's Windows expectation | 27-29, 133, 224 |
| check.zig 239-246 | `notOnPath`'s doc comment | ends 246 |
| verify-bundle.sh 101-128 | the header's scenario list and its "What phase 6 leaves to later phases" paragraph | 101-128 |
| verify-bundle.sh 530-555 | scenario 1's Windows `path.R` block | 530-555 |
| verify-bundle.sh 2101-2111 | scenario 3's Windows setup (`CONDA_PREFIX` check, `usr_bin`, `bt_path`) | 2101-2113 |
| verify-bundle.sh 2205-2209 | the check's expected `make at`/`sh at`/`binutils at` loop | 2205 |
| verify-bundle.sh 2466-2500 | the no-zig preflight block | 2455-2500 |
| hermetic-check.sh 160-171 | check.R's `if (!windows)` around R CMD config | 161-170 |
| test-compilers.R 259-266 | the "R CMD config is phase 7's item" block | 260-267 |
| recipe.yaml 351-352, 496-497 | r-zig-slim's `files` exclusion and `package_contents` `not_exists` globs | same |
| recipe.yaml r-zig-build-tools comments | "phase 7 chooses native or m2", "win-64's interim set", "phase 7 adds the pkgconf name" | 593, 597, 633 |
| stress.R 374-380 | the "PATH: the libraries env's programs" block | 374-381 |
| pixi.toml 341 ff, 204, 605 | `[target.win-64.dependencies]`'s m2 lines; the ci-trigger note; the conda-publish note | 330-357, 204, 605 |
| README 47-49, 68-70, 256-260, 319 | same paragraphs | same |
| PLAN.md 5955-5987 | "### Phase 7 — Windows build tools: usr/bin" | 6019-6055 |
| PLAN.md 631-645 | the Windows userland facts ("Whether conda-forge has native win-64 builds") | ~644 |
| TODO.md 742-795 | "## Phase 7 — Windows build tools: usr/bin" | 765-~810 |

§1's "re-read before step 7" rule stands; the baseline for
`phase7-only.diff` is the sha256 above unless P6 moves again.

## Am14. Versions and file lists against today's lock (task item 5)

- Every package of the plan's §5 table is in the default and pkg
  envs' win-64 sets of pixi.lock fbb64b7b... at the plan's version and
  build (script over the lock's `environments:`: m2-bash 5.2.037.2,
  m2-make 4.4.1.2, m2-coreutils 8.32.5, m2-sed 4.9.1, m2-grep 1!3.0.7,
  m2-gawk 5.3.2.1, m2-which 2.23.4, m2-findutils 4.9.0.3,
  m2-msys2-runtime 3.6.1.4, m2-libintl 0.22.5.1, m2-libiconv 1.18.1,
  m2-libpcre 8.45.5, m2-gmp 6.3.0.1, m2-mpfr 4.2.2.1, m2-libreadline
  8.2.013.1, m2-ncurses 6.5.20240831.2, m2-gcc-libs 13.3.0.1, all
  `hc364b38_6`; m2-filesystem `hc364b38_10`; vc14_runtime 14.51.36247
  `habf1de7_41`); all 37 downloaded `.conda` files of PS match the
  lock's sha256 (37 checked, 0 bad). pkgconf is in no env today.
- With Am1, pkg-config 0.29.2, libglib 2.90.0, libiconv 1.18, libintl
  0.22.5 and pcre2 10.47 leave §5's "copied" table (they stay in the
  lock and the env; pkg-config stays a conda run dependency, Am2).
- **pkgconf 3.0.7 `h6a83c73_0` (win-64)**: published 2026-09-05; the
  newest build older than two weeks on 2026-10-20 (3.0.8 is from
  2026-10-08, then 3.0.9 2026-10-16, 3.0.10 2026-10-19;
  `phase7plan/api/pkgconf.json`). `.conda` 137,187 B, sha256
  `47db8e78321814844555d501ef654dca4aa3561954379d1064c620ebfd9a69ed`
  (the file in `phase7plan/dl2/`, equal to the API's).
  - Files: `Library/bin/pkgconf.exe` (48,640 B, sha256 `998a3822...`),
    `pkgconf-8.dll` (96,256 B, `c7dfff06...`), `bomtool.exe`,
    `pccritic.exe`, `spdxtool.exe`; headers, `Library/lib/pkgconf.lib`,
    `Library/lib/pkgconfig/libpkgconf.pc`, `Library/share/aclocal/pkg.m4`,
    docs and man pages. No `pkg-config.exe`, no activation scripts.
    Only `pkgconf.exe` and `pkgconf-8.dll` are copied.
  - Imports: `pkgconf.exe`: pkgconf-8.dll, VCRUNTIME140.dll, KERNEL32,
    api-ms-win-crt-*; `pkgconf-8.dll`: VCRUNTIME140.dll, ADVAPI32,
    KERNEL32, api-ms-win-crt-*. Closure in `usr/bin`: pkgconf-8.dll and
    vcruntime140.dll.
  - Prefix placeholders: only `libpkgconf.pc` (text); the exe and DLL
    have none (paths.json). Their `D:/bld/bld/rattler-build_pkgconf_.../h_env`
    strings are the feedstock build's system dirs and personality dir,
    never present on a user's machine; not a path of ours, so
    verify-toolchain's build-path scan is unaffected.
  - Depends `vc >=14.3,<15`, `vc14_runtime >=14.44.35208`,
    `ucrt >=10.0.20348.0`, all met by the lock (vc 14.5, vc14_runtime
    14.51.36247, ucrt 10.0.26100.0): the re-lock should add pkgconf
    alone (Am16).
  - Licence: conda says `MIT` (about.json, index.json);
    `info/licenses/COPYING` (468 B) is a short ISC-style permissive
    text ("Permission to use, copy, modify, and/or distribute this
    software ..."). As Cr2: `license:` stays conda-meta's, the
    difference goes in PLAN's record; nobody is contacted.

## Am15. Sizes with Am1

- `usr/` (PP's set less pkg-config's closure, plus pkgconf): **137 files,
  21,751,172 bytes** raw (was 140, 24,891,268); with `etc/fstab`, 138
  files. Measured on a copy of PP's `probe/usr-proto` with the six files
  removed and pkgconf's two added (scratch).
- Zipped (python zipfile, deflate level 6, `usr/` + `etc/`): **10,605,723
  bytes**, against 12,156,676 for PP's set by the same method (PP's
  `zip -qr` gave 12,167,956), so the build-tools `.zip` grows by about
  10.6 MB, not 12.2.
- §0, §4's build-tools row, §5's totals, §7's comparison figures and
  step 2's "the listing equals PP's 140 files (142 with pkgconf)" use
  these (137).
- Step 2's expected summary, in copy order:
  `usr/ (m2-msys2-runtime, m2-libintl, m2-libiconv, m2-libpcre, m2-gmp,
  m2-mpfr, m2-libreadline, m2-ncurses, m2-gcc-libs, pkgconf, vc14_runtime,
  m2-bash, m2-make, m2-coreutils, m2-sed, m2-grep, m2-gawk, m2-which,
  m2-findutils)`.
- conda's win-64 r-zig-build-tools grows by the three pkgconf files
  (48,640 + 48,640 + 96,256 = 193,536 B raw) plus usr/SOURCES and
  usr/LICENSES/pkgconf/ (Am2).

## Am16. The approved re-lock (step 2)

Replaces §3 pixi.toml's F bullet and adds to step 2's lock test:
- `pkgconf = "==3.0.7"` in `[target.win-64.dependencies]` (P6
  pixi.toml, beside the m2 lines), comment "pkg-config and pkgconf
  in the build-tools group (PHASE7 amendment Am1); 3.0.7: the newest
  build older than two weeks on 2026-10-20". The lock fixes the build
  (h6a83c73_0).
- `pixi lock` once, by the implementer on gamma. The lock's diff must add
  pkgconf 3.0.7 `h6a83c73_0` for win-64 (its package entry and one line
  per env that has the win-64 dependencies) and change nothing else
  (Cr10): stop and report otherwise. Then `pixi lock --check`, and
  `pixi run -e minimal minimal-check` as pixi.toml's re-lock note asks
  (minimal has no win-64; the check guards against a solve-group side
  effect). The new sha256 is recorded on every host.
- recipe.yaml's host entry is `pkgconf ==3.0.7 *_0` (C8, Am2), so a later
  conda-forge rebuild of 3.0.7 cannot enter the conda build. Step 5
  compares the three pkgconf `file:` lines of conda's usr/SOURCES with
  the tree's: equal sha256 (`998a3822...` twice, `c7dfff06...`), else
  stop and report.
- The three specs (pixi.toml `==3.0.7`, host `==3.0.7 *_0`, the run
  dependency `>=3.0.7,<4.0a0`) stay different on purpose: the first two
  fix the bytes R copies; the run dependency only gives the `pkgconf`
  name outside R, since TC's copy carries its own DLL (Am2). S5 (a)'s
  one exact spec everywhere is not taken (it would pin users' envs).

## Am17. Records and stale references (§9, §10, §12)

- §10's stale list adds `.github/workflows/build.yaml:12` and `:301`
  ("until phase 7's build-number bump merges", reworded after the
  publish, as pixi.toml's and README's).
- B11's record (S10): "phase 7 outcome: pkg-config and pkgconf are
  conda-forge's native (MSVC) pkgconf; make and coreutils are m2's
  (user 2026-10-20), with KN's M/N matrix as the evidence that m2 needs
  none of the native set's fixes (Am5); make.exe is not stripped (m2's
  has no debug sections)". The wording "native first held for
  pkg-config" goes.
- B41's record: conda's r-zig-build-tools carries three more copies,
  `TC/usr/bin/{pkgconf.exe,pkg-config.exe,pkgconf-8.dll}` (Am2), and
  which `ignore_run_exports` placement rattler-build honours (C11).
- B43's record: `pkg-config` and `pkgconf` are pkgconf 3.0.7 on Windows,
  both channels, one program with its own DLL; Libs.private only with
  `--static` (Am1); no `ld` anywhere (winch, C6: a follow-up for the
  user, not phase 7).
- PLAN's phase 7 record lists KN's M column (30/38) as the m2 baseline
  and the expected 32/38 with pkgconf: "d fixed; i via download"
  (RPostgres links winlibs.R's r-windows libpq bundle, network needed,
  conda's libpq unused; C1). The remaining Windows failures a, b, c, e,
  f, j are the toolchain's or the packages' (stress expects them). It
  also records: the space-path behaviour of pkgconf (Am1), the registry
  key and INCLUDE/CPATH/LIBRARY_PATH filters (C12), the share/pkgconfig
  measurement (Am3), the MSYSTEM result (Am4), and that step 1 ran
  without R_TOOLS_SOFT (S9).

## Am18. Step order: no hand-made usr/bin (S1)

The prototype existed to settle open points A-D, G, I and M before any
code; the user has decided all of them (2026-10-20), so what is left of
step 1 is verification, which belongs on the real artifact.
- Steps 1 and 2 swap order; their names stay, so every other reference
  holds. Step 2 (build.zig's `usr` directory, `Tree.strip`, the fstab
  writer, the licence fallback, the re-lock, verify-toolchain, its tests)
  runs first, on gamma, then `pixi run toolchain`, `verify-toolchain`,
  `package-toolchain` and `unpack-toolchain` on kappa. Step 1 then runs
  on that tree.
- Step 1 keeps: the MSYS root with fstab and without it (a copy of the
  tree with `etc/fstab` deleted); "R finds them" (`--rzig-check`, the
  `R_PROFILE_USER` prototype of patch 0014); the libraries env and
  s3-set.R (Am7), the pkg-config probe, the clash's kappa packages
  (Am4 item 3), R CMD config's count and time, `has_rtools(debug =
  TRUE)`, the space run.
- Step 1 drops: `phase7/kappa/proto-usr.sh` (one assembler, build.zig;
  no third file list beside PP's `assemble-usr.sh`); "each tool starts"
  (verify-toolchain's Windows block runs each name with PATH =
  System32); "phase 6's scenario 3 on a scratch copy" (step 4's
  verify-bundle runs it on the real group, kappa included).
- Step 1's rule stands: a failure in the decided set goes back to the
  user with the measurement, now before step 3.
- §7's kappa row is reordered the same way.

## Am19. Decided options become records (S10)

- §11 A, B, C and F become records: "decided (user 2026-10-20):
  m2-coreutils; m2-make, not stripped; every file of the eight
  packages' `Library/usr/bin/` plus the nine MSYS DLLs and pkgconf's
  three files; pkgconf behind both names (Am1)". One line each on why
  the alternatives were not taken: uutils' missing `touch`, `uname`,
  `chmod` (PS); native make's quoting (KN F1); a name list edited after
  each failure (C b); 0.29.2's Libs.private (KN d, i).
- check.zig's planned comment loses "If B (b) were taken, `notOnPath`
  would also look in `<env>/Library/bin` (native make): not planned".
- §12's "pkgconf for both names" bullet is removed (not marked
  reversed); the `cygpath.exe` and J (b) points stand.
- The menus left are the conditional ones below.

## Critique

Two critiques of the first version (C1-C12, S1-S10). Each point's
evidence was re-read where it decides the outcome (RPostgres.out under M
and N, N-space/probe.log:78, winch.out:70-71, run-cfg.bat:51, recipe.yaml's
flang pins, vc14_runtime's files, m2-coreutils' names, test-build-tools.R's
`same_path`).

| id | point | outcome | where |
|---|---|---|---|
| C1 | RPostgres is not fixed by pkgconf: without `ldap32` in `--libs libpq` its Makevars.win downloads r-windows' libpq bundle | **taken**: confirmed (`N/outputs/RPostgres.out:9`, :202; M :9). Am1 says "d fixed; i via download"; the stress note names the download; step 1 asserts the winlibs.R branch and records an offline run; the Makeconf citation corrected to r-zig's `PKG_CONFIG = pkg-config` | Am1, Am7, Am8, Am17 |
| C2 | the space runs never linked through pkg-config output; libcurl.pc's absolute `z.lib` comes out unescaped | **taken**: confirmed (`N-space/probe.log:78`). Space run gets a libraries env under the space path, ncdf4 pre-registered likely FAIL; btPc's `.pc` under a space path in CI; README sentence | Am1, Am7, Am9 |
| C3 | conda's single exe runs against whatever `pkgconf-8.dll` the env solves | **taken, (a)**: the three pkgconf files are in_conda; the DLL is loaded from the exe's directory first, so both channels run one program with its own DLL; no dependency change | Am1, Am2 |
| C4 | TC's copy searches no `share/pkgconfig`; Am3's argument against a relocatable default used the wrong spelling | **taken**: reasoning corrected (`${R_HOME}/../../lib/pkgconfig` keeps the prefix right); (a) stays after a step 5 count, (b) to the user only if counts differ; README text | Am3 |
| C5 | `sort`, `expand`, `hostname`, `timeout`, `whoami` are System32 names too; `Sys.which` returns 8.3 names | **taken**: shadowed names computed from System32; all comparisons normalised with `same_path()` | Am6, Am2, Am4 |
| C6 | winch needs an `ld`, which the toolchain lacks | **taken**: confirmed (`F-cg-site2/outputs/winch.out:70-71`); qfratio is the config.guess test; winch not counted; ld gap a follow-up | Am5, Am7, Am17 |
| C7 | CI never tests the conda half; the L dispatch runs tree rows only | **taken**: `-f distribution=both -f channel=local`; universe-channel rows before the publish are not regressions | Am8 |
| C8 | `==3.0.7` in host takes any later rebuild | **taken**: `pkgconf ==3.0.7 *_0`, as the flang pins; step 5 compares the `file:` sha256 lines | Am2, Am16 |
| C9 | the 0.29.2 swap fails on a DLL load, not a version | **taken in effect**: the version check and the swap case are dropped (S4), so neither is needed | Am10 |
| C10 | `MSYSTEM=MINGW64` may change config.guess; nothing under run 1 runs it | **taken**: Rmpfr, qfratio, winch under run 1; menu only if the triplets differ | Am4 |
| C11 | the staging output's ignore may not filter what r-zig-slim inherits | **taken**: step 5 reads all four outputs' index.json; move the ignore if needed; record beside B41 | Am2 |
| C12 | registry key and INCLUDE/CPATH/LIBRARY_PATH filters | **taken, no code**: README and PLAN lines. The optional INCLUDE test is not taken: no R behaviour depends on it (rzig adds the paths) | Am3, Am9 |
| S1 | drop proto-usr.sh; build.zig first, probes on the real tree | **taken**: every open point is decided; one assembler | Am18 |
| S2 | patch 0014 as a build.zig append instead | **not taken**: I (a) was answered as patch 0014; the R code and tests are identical either way, and the patch sits next to R's own disabled Rtools block it mirrors, readable as an R diff. No decision asked; it can move later without behaviour change | - |
| S3 | runs 1 and 2 duplicate each other; risk 1's mixed-runtime case is untested; stringi/RcppParallel twice | **taken in part**: run 2 keeps the PATH assertions only (both orders stay, as M was answered); run 1 gains a configure.win calling Git's `diff`/`cygpath` through TC's sh; stringi and RcppParallel once, under run 1. Not asked as a menu: the answered "before and after" holds | Am4, Am7 |
| S4 | four places check which program answers a name, two version rules | **taken in part**: no new version checks (Am10's bullet, btPc's `want`, test-build-tools.R's comparison go); bt.R asserts identity on Windows. The plan's make version check in verify-toolchain stays (O a was answered) | Am9, Am10, Am2 |
| S5 | three specs for one package; exe vs env DLL | **taken as (b)** (= C3 a): the DLL in_conda. (a) one exact spec everywhere is not taken: pinning the run dependency to 3.0.7 restricts users' envs; the specs differ on purpose (Am16) | Am2, Am16 |
| S6 | test what R uses; assert why pkg-config stays | **taken**: R CMD resolution, PKG_CONFIG_PATH and a `--modversion`; the bare 0.29.2 check goes; recipe comment reworded | Am2 |
| S7 | the in_conda invariant stated wrongly in several places | **taken**: one sentence, listed places | Am2 |
| S8 | as C10 | **taken** (with C10) | Am4 |
| S9 | KN's M ran with R_TOOLS_SOFT and MAKEFLAGS | **taken**: step 1's environment stated; a difference only without them is a stress-only setting | Am7, Am17 |
| S10 | decided options still read as menus | **taken** | Am19 |

## Decisions

Taken as ★ under the user's "Follow on with the new recommendations!"
(2026-10-20): Am1 (a), Am3 (a), Am4 conda (a). No decision is open
before implementation. Three go back to the user only if a measurement
says so, each with its logs:
1. Am3: step 5's `--list-all` counts differ → (b), the
   `${R_HOME}/../../lib/pkgconfig;.../share/pkgconfig` default.
2. Am4: run 1's triplets differ from the base run's → (a) ★ record and
   README, or (b) `MSYSTEM=MSYS` in rcmdEnviron.
3. Am4 conda: step 5's Git-first run fails → (b), R's env MSYS dir in
   `R_ZIG_TOOLS_PATH` and patch 0014.

No other lock or dependency change is proposed: pkgconf `==3.0.7` on
win-64 (pixi.toml and the re-lock, `==3.0.7 *_0` in host, the approved
run dependency) is the only new package; pkg-config stays a run
dependency of conda's r-zig-build-tools; the extra in_conda files are
copies, not dependencies.

## UNVERIFIED

- conda-forge's MSVC build of pkgconf 3.0.7 on kappa (only zig builds of
  pkgconf ran there); step 1 checks it (Am7).
- Which `ignore_run_exports` placement rattler-build honours for
  r-zig-slim (step 5, C11).
- Whether conda's `Library/share/pkgconfig` holds `.pc` files R users
  need (step 5's counts, Am3); the `../../lib/pkgconfig` prefix result
  (from pkgconf's source, not run).
- qfratio under m2; RPostgres offline (and whether winlibs.R honours the
  proxy variables); ncdf4 in the space run; Git's sh first with m2 in a
  conda env; Git's `diff` from TC's sh (two MSYS runtimes);
  `MSYSTEM=MINGW64`'s effect on configure scripts.
- That the re-lock adds pkgconf alone.
- A `channel=local` conda row's result before the publish (Am8).
- m2 tools past MAX_PATH.
- pkgconf's licence text is ISC-style while conda says MIT (text read;
  no SPDX decision taken here).
- vcruntime140.dll for conda's TC copy in an unactivated env (env root
  or System32 on PATH; test-build-tools.R checks the env root case).

## User decisions 2026-10-21

The user's final decisions after the 2026-10-20 runs (the implementer's
and the gamma, omicron and kappa testers', `phase7m2/*/RESULTS.md`), all
the recommended options. They replace what they name below; the text
above stays as the record of what was planned, built and tested on
2026-10-20.

**D0 (a): pkgconf leaves phase 7.**
- Am1 is withdrawn. The standalone tree's `TC/usr/bin` ships the plan's
  pkg-config 0.29.2 (§0's "pkg-config" row: conda-forge's MSVC build,
  `Library/bin/pkg-config.exe`) with its DLL closure (`glib-2.0-0.dll`,
  `iconv.dll`, `charset.dll`, `intl-8.dll`, `pcre2-8.dll`,
  `vcruntime140.dll`; §3's `usr` copies), and no `pkgconf` name (§0's
  "pkgconf (open point F a)" row and §3's two pkgconf copies are not
  taken either). Found on the way (kappa, 2026-10-21): libglib is an
  output of a rattler-build staging output, so its rendered recipe has
  `finalized_sources: []` and the source under `finalized_cache_sources`;
  the toolchain build's GPL rule (an LGPL package must name its source)
  stopped. `readUpstream` now reads `finalized_cache_sources` when
  `finalized_sources` is empty (a unit case in conda.zig); linux's and
  macOS's trees do not change (no such package in them; gamma's
  19,590-file list is byte-equal). `usr/bin` is then 140 files,
  24,891,268 bytes, the plan's probe's numbers; the build-tools zip
  17,989,545 bytes, 199 members. 0.29.2 prints `Libs.private` without `--static`, so
  ncdf4 (KN d) and RPostgres (KN i) are expected failures again, with
  KN's causes; stress/packages.tsv stays as it is (Am8 moot).
- Am2 is withdrawn. conda's win-64 r-zig-build-tools copies no
  pkg-config or pkgconf file into TC and keeps the env's pkg-config as a
  run dependency, as before Am2: no pkgconf in the staging host, no
  ignored run export, no pkgconf run dependency, `package_contents` and
  `license:` back to the binutils alone. A conda env's TC then holds no
  `usr/`, so verify-tree.sh's conda exception stays binutils only and
  kappa's F1 (2026-10-20) disappears without a verify-tree change.
- Am3 is moot (no pkgconf). Under R CMD a conda env's `pkg-config` is
  its own `Library/bin/pkg-config.exe`, which searches
  `Library/lib/pkgconfig` and `Library/share/pkgconfig` by itself, as
  before phase 7.
- Am9 keeps btPc's `.pc` under a path with a space, the prefix and the
  escaped `--cflags`, and `--static`'s private libraries; its pkgconf
  leg and its "no Libs.private without --static" assertion go (0.29.2
  prints them: d). Am10's names lose `pkgconf` (33 names).
- Am16 is withdrawn: pixi.toml loses the `pkgconf` line and pixi.lock is
  back to `relock/pixi.lock.before` (fbb64b7ba4e31e45...), byte-equal to
  phase 6's; phase 7 changes nothing in pixi.lock.
- The follow-up, a separate later PR: pkgconf built from source by
  build.zig, one static exe answering both names on both channels
  (TODO.md "After phase 7: pkgconf from source"). The parked
  `wt/feat-userland` has a zig build of pkgconf 3.0.7 to read then.

**F2 (b): R's env MSYS dir after the group's usr/bin** (Am4 conda's
option b, after kappa's Git-first failure: Git's `sed`, a second
msys-2.0.dll, wrote winshlib.mk's `tmp.def` from offset 0 and R CMD SHLIB
exited 0 with no DLL; Rmpfr, ncdf4 and stringi).
- Rcmd_environ: `R_ZIG_TOOLS_PATH=${R_HOME}/bin/toolchain/usr/bin;${R_HOME}/../../usr/bin`;
  patch 0014 the same two directories in sessions, the second spelled
  without ".." (`file.path(dirname(dirname(R.home())), "usr", "bin")`).
  `R_CUSTOM_TOOLS_PATH`, when set, still replaces both. Why the session
  spelling differs (kappa, 2026-10-21, `pathdiag.R`): R's own command
  search (run.c's `expandcmd` and `Sys.which`) calls SearchPath twice,
  the second time with the first call's size plus ten, and treats a
  result that does not fit as "not found"; a PATH entry whose ".."
  segments shorten the found path by more than ten characters
  (`lib/R/../../` is twelve) then makes R report "'make' not found" and
  `Sys.which("sed")` empty, while one `..` (`lib/../`) works. A
  conda-shaped tree with the first spelling in its Rprofile failed R CMD
  SHLIB that way. The session's entries come before R CMD's, so R's
  lookups meet the clean one first; the programs R CMD starts
  (CreateProcess, cmd.exe, MSYS, rzig) resolve `..` themselves (rzig's
  check under R CMD found the env's make and sh through it).
- Both channels, one line (the decision asked: standalone too, or conda
  only). Evidence: in the standalone tree R_HOME is
  `<top>/Library/lib/R` (README; kappa's tree), so the entry names
  `<top>/Library/usr/bin`, inside the install's own top directory, which
  no archive creates (kappa: `ls -d <tree>/Library/usr`: none); it is
  never outside the install, and a user who can create it can write
  R_HOME's `bin\x64` too, the same trust as `TC/usr/bin`, which is
  missing whenever the build-tools group is. A conda-only line would
  need a second Rcmd_environ and a second base Rprofile (a build switch
  or a recipe edit of R's files), against one build path. With D0 each
  channel has exactly one of the two directories (conda: no `TC/usr`;
  standalone: no `Library/usr`), so one MSYS runtime answers.
- It changes PHASE4 open point I a's Windows case: an unactivated conda
  env (R.bat adds nothing to PATH) now finds make and sh under R CMD and
  in sessions; rzig's "is installed in R's environment, which is not on
  PATH" line remains for unix and for a check run outside R.
  test-build-tools.R gains that assertion under R CMD; PHASE4's record
  says so.

**MSYSTEM (a):** with Git first and `MSYSTEM=MINGW64` the build triplet
is `x86_64-pc-mingw64` and every package still builds (kappa,
2026-10-20): recorded, one README line, MSYSTEM not set.

**Tests of these decisions** (`phase7m2/implementer2/RESULTS.md`): gamma
(linux-64) the unit tests with both zigs and the default chain;
kappa the Windows tree (toolchain, verify-toolchain: 33 names,
verify-bundle's toolchain pass with scenario 1's two entries, scenario
3, btPc on 0.29.2 and the clash) and an F2 probe on a conda-shaped tree.
The win-64 conda packages and the final 0014 on Windows did not fit in
that round (another user's files filled kappa's disk to 0.3 GB free);
after the user cleaned kappa they ran on the final code
(`phase7m2/build-kappa/RESULTS.md`, `phase7m2/test2-kappa/RESULTS.md`):
the session's second entry has no ".."; the four win-64 `_9` packages,
each "all tests passed!", none with TC/usr/ or a pkgconf file;
conda-consume; the upgrade from `_8` with pixi and conda, verify-tree
rc 0 on each env (F1 gone); in a conda env with Git's usr\bin first and
MSYSTEM=MINGW64, Rmpfr, data.table and stringi link (F2 fixed), ncdf4
fails with KN d; KN's 38-target set 30/38, equal to KN's M. CI's legs
remain.
