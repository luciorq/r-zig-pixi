# Phase 8 — the base's runtime files: places and records

**Status (2026-11-07).** Implemented and tested on every platform (section 9); CI next. The user answered every
open point with its ★ option (2026-11-07, section 7). Worktree
`wt/feat-standalone-phase8`, branch feat-standalone-phase8 from main at
6cdd9eb (#41). pixi.lock is main's,
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96.

Decisions this phase implements: B27 (a) and B33 (a) (PLAN.md). The
phase's steps are in PLAN.md, "Phase 8", and TODO.md, "Phase 8".

## 1. What changes

| Runtime item | today | after phase 8 |
|---|---|---|
| CA bundle (unix) | `R_HOME/etc/ca-bundle.crt`; etc/Renviron `R_ZIG_CA_BUNDLE=${R_HOME}/etc/ca-bundle.crt` | `<top>/ssl/cacert.pem`, conda's place; `R_ZIG_CA_BUNDLE=${R_HOME}/../../ssl/cacert.pem` |
| fontconfig (Windows) | `R_HOME/etc/fonts`; `FONTCONFIG_PATH` in etc/Renviron.site, which `--vanilla` skips | B27 said `<top>/Library/etc/fonts`; nothing on Windows reads it (section 2), so open point D asks whether to ship it at all |
| fontconfig (unix) | `<top>/etc/fonts`; the launchers set `FONTCONFIG_PATH` | the same place; open point G asks where the variable is set |
| licences and sources | none (R's COPYING only) | `<top>/share/licenses/<package>/` and `<top>/share/licenses/SOURCES` (Windows: open point C) |

Not changed: the vendored libraries' places (`<top>/lib`; Windows
beside R.dll), libomp, Tcl/Tk (unix full `<top>/lib/tcl8.6` ...;
Windows `R_HOME/Tcl`), and the conda packages, whose runtime files come
from conda-forge's own packages (`prefix_is_env`: build.zig installs none
of them, vendor-libs.sh copies nothing, and conda keeps each package's
licences in its info/).

## 2. Facts found (2026-11-06)

- **R on Windows reads no Renviron file under `--vanilla`.**
  gnuwin32/system.c never calls `process_system_Renviron`; it calls
  `process_site_Renviron` and the user's file only without
  `--no-environ` (system.c:982, 1223). unix reads etc/Renviron always
  (unix/system.c:337). The system profile
  (`R_HOME/library/base/R/Rprofile`, built from
  src/library/profile/Rprofile.windows) is read under `--vanilla` on
  both: `--vanilla` skips only the site and user profiles. Patch 0014
  already adds a PATH block there (phase 7).
- **fontconfig's Windows default is relative to its DLL.** fontconfig
  2.18.3 (the lock's, conda-forge win-64 hd47e2ca_1), src/fccfg.c:2276-2289:
  with no `FONTCONFIG_PATH`, the configuration directory is `<the DLL's
  directory>\etc\fonts`, with a final `bin` or `lib` stripped first. In a
  conda env the DLL is in `Library\bin`, so the default is
  `Library\etc\fonts`, where the package keeps it. In the standalone tree
  the DLL is in `R_HOME\bin\x64` (vendor-libs.sh), so the default is
  `R_HOME\bin\x64\etc\fonts`, which does not exist. The DLL has no
  compiled-in prefix (the package's has_prefix lists two text files
  only).
- **On Windows, R never reads fontconfig's configuration.** R's cairo
  device picks text fonts through Win32 there: cairoFns.c compiles its
  fontconfig branch only `#if CAIRO_HAS_FT_FONT && !defined(_WIN32)`
  (line 1724) and calls `R_win32_cairo_select_font_face` (1957). Its one
  fontconfig use is the glyph path (`grid.glyph`, R 4.3's API, 2523-2530),
  which builds a pattern from an explicit font file. winCairo.dll imports
  only `FcPatternBuild` and `FcPatternDestroy`. kappa, 2026-11-06, the
  slim archive of main's run 42251904523, `Rscript` with etc/Renviron.site
  (FONTCONFIG_PATH set) and `Rscript --vanilla` (unset), `FC_DEBUG=1024`
  (fontconfig's config-loading trace):
  - svg() text in the families sans, serif, mono, Helvetica and Times,
    with Latin, CJK and Cyrillic characters: the same md5 per family in
    both runs;
  - grid.glyph() with C:/Windows/Fonts/arial.ttf: the same md5 in both;
  - no config file loaded in either run; both print fontconfig's
    "using without calling FcInit()" warning, so the shipped
    configuration was never read, with or without the variable.
  If a package calls `FcInit()`, fontconfig's built-in fallback
  (fcinit.c:40-54) already names WINDOWSFONTDIR and WINDOWSUSERFONTDIR
  (fontconfig's meson.build:360, the Windows default).
- **The vendored copies are not always the package's bytes.**
  vendor-libs.sh strips debug info on linux (`strip --strip-debug`), and
  on macOS rewrites env paths with install_name_tool and re-signs. A
  file with a prefix placeholder is the env's rewritten copy. The
  toolchain groups' SOURCES writer (zigbuild/toolchain/conda.zig `find`)
  refuses all three (`PrefixPlaceholder`) or records the package's
  sha256 for the copy, so the base needs a rule for changed copies (open
  point B).
- **The wheel is the tree under `r_zig/R/`** (make-wheel.py), so the
  tree's share/licenses travels in it. Its dist-info/licenses holds R's
  COPYING only.
- **verify-bundle scenario 1 has no fonts check.** It checks TLS
  (tls-check.R), tcltk and R-only installs, but no graphics device that
  loads fontconfig.

## 3. Open points

### A. Who writes the base's records

- **(a) ★** A `base-records` step in zigbuild/toolchain/build.zig, which
  already reads conda-meta, finds each file's package by path, copies
  the package's info/licenses and writes SOURCES for the groups
  (conda.zig). zig-build.sh runs it after vendor-libs.sh, on the tree
  vendor-libs.sh left: the vendored libraries (the same rule as
  verify-helpers.sh's `vendored_files`), the CA bundle, fontconfig's
  configuration and Tcl/Tk's runtime. One reader and one writer for
  groups and base (B33's "one mechanism").
- **(b)** Port vendor-libs.sh to Zig and write the records in the same
  pass. It removes a 202-line shell script (the simplicity goal), but it
  moves ldd, otool, strip, install_name_tool and codesign calls into
  Zig: a larger change than this phase's records. A candidate for phase
  9 or later.
- **(c)** In vendor-libs.sh itself. It needs a JSON reader in bash for
  conda-meta: more shell, against the simplicity goal.

### B. A copy that differs from the package's file

- **(a) ★** The `file:` line keeps the package's path and sha256, and a
  `changed:` line under it names the change and the copy's sha256:
  `strip --strip-debug` (linux), `install_name_tool` (macOS), or `prefix
  rewritten` (conda's placeholder, the env's copy). verify-tree checks the
  copy's sha256. Anyone can get the package, check its file, and see how
  the copy came from it.
- **(b)** Only the package's name and version per file, no sha256. Less
  to check, and nothing ties the copy to the package's bytes.

### C. The records' place on Windows

- **(a) ★** `<top>/Library/share/licenses/`: the Windows tree is laid out
  as a conda env (`Library/lib/R`, `Library/bin`; fontconfig moves to
  `Library/etc/fonts`), so its share/ is `Library/share`.
- **(b)** `<top>/share/licenses/` on every OS: one path in the docs, but
  it is the only top-level directory besides `Library/` on Windows.

### D. fontconfig's configuration on Windows

- **(a) ★** Ship none. installEnvRuntime stops installing it on Windows,
  and etc/Renviron.site loses its `FONTCONFIG_PATH` line (MY_TCLTK
  stays, conda build only). The DLLs stay: cairo.dll and winCairo.dll
  import fontconfig-1.dll. Nothing that R does changes (section 2), the
  tree loses 24 files, and no conda package changes. This revises
  B27 (a)'s Windows move: there is nothing left to move.
- **(b)** A line in Rprofile.windows (patch 0014's file, a new hunk),
  which R reads under `--vanilla`: set `FONTCONFIG_PATH` to
  `<R_HOME's parent's parent>/etc/fonts` when it is unset, spelled
  without ".." (as patch 0014's PATH entry, for R's command search). In
  a conda env that is `Library/etc/fonts`, fontconfig's own default
  there, so one rule serves both channels. etc/Renviron.site loses its
  `FONTCONFIG_PATH` line (MY_TCLTK stays, conda build only).
- **(c)** Ship the configuration at `R_HOME/bin/x64/etc/fonts`,
  fontconfig's own default for a DLL in bin/x64: no variable at all, for
  every program that loads the DLL. It keeps the configuration inside
  R_HOME, against B27's "outside R_HOME".

### E. The wheel's dist-info/licenses

- **(a) ★** dist-info/licenses gets the tree's share/licenses beside R's
  COPYING (each a `License-File:` in METADATA), as B33 says: the files
  that PyPI and pip's tooling read are complete. The cost is one copy
  of the texts per wheel (size in section 4).
- **(b)** COPYING plus a pointer: the texts stay in `r_zig/R/share/licenses`
  only.

### F. Which runtime files the records cover

- **(a) ★** Every file the tree holds that the env provided: the vendored
  libraries, the CA bundle, fontconfig's configuration, Tcl/Tk's
  runtime (unix full; Windows R_HOME/Tcl, headers included, T1).
  verify-tree requires a `file:` line for each.
- **(b)** The vendored libraries only.

### G. `FONTCONFIG_PATH` on unix (a simplification, optional)

Today only the launchers in `<top>/bin` set it, so R started as
`lib/R/bin/R` or `lib/R/bin/Rscript` finds no configuration. etc/Renviron
already sets `TCL_LIBRARY` the same way for the full variant.

- **(a) ★** etc/Renviron: `R_ZIG_FONTCONFIG_PATH=${R_HOME}/../../etc/fonts`,
  `FONTCONFIG_PATH=${FONTCONFIG_PATH-${R_ZIG_FONTCONFIG_PATH}}` (a tree
  that is not the env, slim and full), and the launchers' lines go. One
  rule per OS, inside R, under `--vanilla` too.
- **(b)** Keep the launchers' lines as they are.

### H. A package that ships no licence file

On linux-64's slim tree, 3 of the 35 packages have no info/licenses/:
libfreetype6 (GPL-2.0-only OR FTL), libgcc and libstdcxx (GPL-3.0-only
WITH GCC-exception-3.1; each package's payload has only
share/licenses/<x>/RUNTIME.LIBRARY.EXCEPTION). The toolchain build stops
on such a package unless zigbuild/toolchain/m2-licenses/<name>/ holds its
texts, taken by hand from its source archive, with VERSION and ORIGIN
files (PHASE7 open point E a).

- **(a) ★** The same rule for the base: zigbuild/toolchain/m2-licenses/
  becomes zigbuild/toolchain/licenses/ (one directory for both), with
  freetype's LICENSE.TXT, FTL.TXT and GPLv2.TXT from its 2.14.3 archive,
  and gcc's COPYING3 and COPYING.RUNTIME from gcc 16.2.0's; the package's
  own share/licenses/ files are taken too when present. The build stops
  when a package has no texts and the directory's VERSION differs, so a
  version bump in the lock asks for the texts again.
- **(b)** Record the package's licence field in SOURCES only, with no
  texts, for these three. It leaves GPL-2/GPL-3 code without its licence
  text in the archive, which B33 is there to fix.

## 4. Measurements

Prototype (a scratch script, not in the repo) on linux-64's slim tree,
2026-11-06, built in this worktree from 6cdd9eb:
- 74 files the env provided: 49 vendored libraries, 1 CA bundle, 24
  fontconfig files. Every one has exactly one owner in conda-meta (no
  file without an owner, no clobber), when a soname link
  (`lib/libcurl.so.4`) is resolved to the file it names.
- 35 packages. 25 copies are the package's bytes; 49 differ (linux's
  `strip --strip-debug`; open point B). Several vendored libraries
  are files conda rewrote at install (a binary prefix placeholder:
  libcurl, libcrypto, the krb5 libraries, libglib, libfontconfig, libX11,
  libpango), and so is fonts.conf (text).
- The 32 packages' info/licenses/ hold 390 KB of texts (open point E:
  the wheel's copy). 3 packages hold none (open point H).
- The full variant (Tcl/Tk), macOS and Windows: UNVERIFIED, measured in
  implementation.

## 5. Tests

- linux-64 (gamma), every variant: verify-tree with the new checks
  (each record has its package's licences; each env-provided file has a
  `file:` line whose sha256 matches, or a `changed:` line that matches);
  tls-check.R with the bundle in ssl/; wheel and wheel-test.
- omicron: osx-arm64 and osx-64, the same.
- kappa (win-64): svg() and grid.glyph() under `Rscript --vanilla`
  give the same output as before (section 2's md5s), tcltk,
  verify-tree.
- verify-bundle scenario 1 gains that fonts check on every OS.
- CI: the core tier, full-ci, conda-package (unchanged packages: the
  conda build installs none of these files), upstream-zig.

## 6. Build number

The standalone archives and the wheel change; no conda package does
(`prefix_is_env`: build.zig installs none of these files there, and
vendor-libs.sh copies nothing). So no bump (B14 a). Only D (b) would
change one: win-64 r-zig-slim's system profile.

Correction (2026-11-08, phase 9): G (a) changed the unix conda packages
too. r-zig-slim ships the launchers as bin/R, bin/Rscript and
lib/R/bin/Rscript, and their `FONTCONFIG_PATH` lines are gone (linux-64
`_9` against phase 9's local `_10`). In a conda env that changes
nothing: conda-forge's libfontconfig carries the env's own etc/fonts as
its default (made the env's path at install), and `fc-match sans` with
no `FONTCONFIG_PATH` loads `<env>/etc/fonts/fonts.conf` (FC_DEBUG=1024)
and finds DejaVu Sans. It publishes with phase 9's bump.

## 7. User decisions (2026-11-07)

All ★: A (a), B (a), C (a), D (a), E (a), F (a), G (a), H (a).

The user asked whether D (a) breaks ragg or a ggplot2 font setup on
Windows. It does not. Read from the packages' sources (CRAN, 2026-11-07):
- systemfonts 1.3.2: its `Makevars.win` builds
  `win/FontManagerWindows.o`, which reads Windows' font registry through
  FreeType; it links freetype2 and no fontconfig.
- ragg 1.5.2 and textshaping 1.0.5 find fonts through systemfonts.
  ggplot2 is R code that draws on the active device.
- gdtools 0.5.3, svglite 2.2.2, showtext 0.9-8, sysfonts 0.8.9: no
  fontconfig call.
- Cairo 1.7-0: its fontconfig code is off on Windows
  (`cairogd.h:18`, `!defined(_WIN32)`) unless built with
  `-DUSE_CAIRO_FT=1`.
- R's own devices: section 2 (kappa: the same output with and without
  the configuration, which was never loaded).
What is left: a package that calls fontconfig itself on Windows gets
fontconfig's built-in fallback, every font in Windows' font folders, but
no aliases (`sans` is not mapped to Arial). None of the packages above
does.

## 8. Implementation (2026-11-07)

| Change | Where |
|---|---|
| conda-meta lookup that accepts a rewritten file (`findInEnv`), `changed:` line in SOURCES (B a) | zigbuild/toolchain/conda.zig, with a unit test |
| `-Dbase`: the R tree's records, `installBase` (A a, C a, F a) | zigbuild/toolchain/build.zig |
| `licenses/` (was `m2-licenses/`), a fallback for any package without licence files; VERSION `<version> <build>` or `<version>`; libgcc, libstdcxx, libfreetype6 added (H a) | zigbuild/toolchain/licenses/, build.zig `ownLicenses` |
| the step runs after vendor-libs.sh | scripts/zig-build.sh |
| CA bundle at `<top>/ssl/cacert.pem`, `R_ZIG_CA_BUNDLE=${R_HOME}/../../ssl/cacert.pem` | build.zig installEnvRuntime, finalRenviron |
| Windows: no fontconfig configuration, no `FONTCONFIG_PATH` (D a) | build.zig installEnvRuntime |
| unix: `FONTCONFIG_PATH` in etc/Renviron, the launchers' lines removed (G a) | build.zig finalRenviron, zigbuild/launchers/ |
| records check, CA path, fontconfig lines, no Windows configuration | scripts/verify-tree.sh |
| svg() text in sans, serif, mono under `env -i`, no fontconfig error; unix through `<top>/bin/Rscript` and `lib/R/bin/Rscript` | scripts/verify-bundle.sh scenario 1 |
| CA check, records check, share/licenses in r-zig's dist-info/licenses (E a) | scripts/make-wheel.py |
| the bundle is `<top>/ssl/cacert.pem` | scripts/tls-check.R, wheel-test.sh's comment |

Records shape (linux-64 slim, 2026-11-07): `share/licenses/SOURCES` and
one directory per package. A file line, and the `changed:` line under it
when the copy is not the package's file:

    file: lib/libbz2.so.1.0.8 -> lib/libbz2.so.1.0 89167cfb...
    changed: strip --strip-debug (vendor-libs.sh) a1810030...

The `how` of a `changed:` line is one or both of `conda's prefix at
install` (the package's paths_data has a prefix placeholder) and the
directory's own (linux `strip --strip-debug (vendor-libs.sh)`, macOS
`install_name_tool -change, codesign (vendor-libs.sh)`, etc/fonts
`fonts.conf without the env's directories (build.zig,
installFontconfig)`). A copy that differs where nothing changes it, or an
env file that differs from its package with no placeholder, stops the
build.

Two points differ from section 3's text:
- E (a): no `License-File:` lines. METADATA is version 2.1, and
  `License-File` is version 2.4's (PEP 639): packaging 26.3, whose
  validation PyPI's uploads go through, refuses it ("license-file
  introduced in metadata version 2.4, not 2.1"). Going to 2.4 also replaces `License:` with
  `License-Expression:` and drops the licence classifiers, a separate
  change. The texts are in dist-info/licenses/ as B33 says.
- H (a): the package's own share/licenses/ files are not taken.
  libgcc's and libstdcxx's are RUNTIME.LIBRARY.EXCEPTION, the same bytes
  as gcc's COPYING.RUNTIME (checked with cmp).

A tree built over an older one keeps `lib/R/etc/ca-bundle.crt` and, on
Windows, `R_HOME/etc/fonts` (zig's install removes no file). CI builds
fresh trees, and a local tree is rebuilt with `rm -rf dist/<flavor>`.

## 9. Tests (2026-11-07, pixi.lock fbb64b7b..., unchanged)

| Platform | Run | Result |
|---|---|---|
| linux-64 (gamma) slim | build, verify-tree, smoke, package-toolchain, verify-package | ok; records: 74 files (49 changed: 39 stripped, 9 conda's prefix and stripped, fonts.conf), 35 packages |
| linux-64 slim | verify-tree with a `file:` line removed and every `changed:` sha256 zeroed | fails, naming lib/libz.so.1 and the 48 copies |
| linux-64 minimal | build, verify-tree, toolchain, wheel, wheel-test | ok; records: 23 files, 17 packages; r-zig's dist-info/licenses: 22 files, 270 KB |
| linux-64 full | build, verify-tree, verify-package | ok; records: 484 files (Tcl/Tk's included), 42 packages; tcltk from lib/tcl8.6 |
| osx-arm64 (omicron) slim | build, verify-tree, package-toolchain, verify-package | ok; records: 67 files (10 changed: conda's prefix, fonts.conf), 29 packages |
| osx-64 (omicron, Rosetta) slim | the same | ok; 67 files, 29 packages |
| win-64 (kappa) slim | build, verify-tree, package-toolchain, verify-package | ok; records: 1067 files (Tcl/Tk's and the DLLs), 0 changed, 26 packages; svg() text with no fontconfig configuration and no `FONTCONFIG_PATH`; tcltk from R_HOME/Tcl |

Each platform: the CA bundle at `ssl/cacert.pem` (TLS: "requests OK ...
bundle <top>/ssl/cacert.pem"), unix fonts through `<top>/bin/Rscript`
and `lib/R/bin/Rscript` with `FONTCONFIG_PATH` from etc/Renviron. The
remote scratch directories are deleted. Left: CI (core tier, full-ci,
conda-package, upstream-zig).

CI, PR #42's first run (42419649199, 42419649366): every R build leg
failed in `-Dbase`, `<pkg>: cannot read .../info/about.json
(FileNotFound)` (linux pango, macOS libfreetype6, Windows bzip2).
build-r.yaml's setup-pixi had `cache: true`: the restored env was not
installed on the runner, so pixi's package cache was empty (the
toolchain job's C33, which is why toolchain.yaml has `cache: false`).
Fix: `cache: false` in build-r.yaml and in stress.yaml (its `pixi run
build` runs the same step). Cost, from the same run: setup-pixi took
10 s (linux), 21 s (macOS) and 70 s (Windows) without the cache, 10 s,
9 s and 37 s with it. conda-package's legs passed, and so did the two
R legs whose env had no cache entry (macos-latest minimal,
macos-15-intel full: "Cache miss", the env installed from packages).

Second run (9d87132): the two openblas legs failed in `-Dbase`,
`libgfortran5 16.2.0 h6b99dfc_7 ships no licence file`. The openblas
flavor vendors libgfortran.so.5 and libquadmath.so.0, both libgfortran5's
(OpenMP is llvm-openmp's, with its licence). Fix:
zigbuild/toolchain/licenses/libgfortran5/, gcc's COPYING3 and
COPYING.RUNTIME as libgcc's; the package's own
share/licenses/libgfortran/RUNTIME.LIBRARY.EXCEPTION is COPYING.RUNTIME's
bytes (cmp). Local linux-64 slim-openblas: build, verify-tree, smoke ok;
records: 77 files (52 changed), 37 packages.
