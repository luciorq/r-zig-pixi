# Build 13 leftovers (b13-left)

Worktree wt/build13 (branch build13, head cc7d810, PR #57), all work
uncommitted (2026-11-24). Four open items from
[b13-integration/PLAN.md](../b13-integration/PLAN.md),
[PLAN-chain.md](../b13-integration/PLAN-chain.md) "Open items" and
[b13-recipe/PLAN.md](../b13-recipe/PLAN.md) N3/F10. Hosts: delta
(linux-64, ~/rz/wt/b13-left, ~/rz/scratch-b13-left), kappa (win-64,
scratch rz-b13-left, removed after).

Files: `zigbuild/tools/rzig/{check,binutils,main}.zig`,
`.github/workflows/stress.yaml`, `stress/{stress.R,README.md}`, this
file. build.zig and recipe/ are not this track's: their changes are under
Needs, as exact diffs.

## Items

| # | item | state |
|---|---|---|
| 1 | N3/F10: Windows `iconv -l` (no iconv.exe in any recipe package) | done: N1 applied by [b13-fixes](../b13-fixes/PLAN.md) item 2 |
| 2 | rzig names R_HOME/bin/toolchain/usr/bin/make when make is not on PATH | done (check.zig); recipe test diff under Needs (N2) |
| 3 | rzig windres writes the depfile meson asks for | done (binutils.zig, main.zig) |
| 4 | CI5: stress.yaml `variant` input (slim, full, openblas) | done (stress.yaml, README); dispatch lines under Needs (N3) |

## Decisions (defaults, 2026-11-24)

| id | question | options | chosen | reason |
|---|---|---|---|---|
| L1 | item 1: how Windows gets utils/iconvlist | (a) rzig or a Zig helper lists the encodings; (b) an iconv.exe from a recipe package (m2's libiconv has none); **(c) no file on Windows** | (c) | upstream's Windows build writes none (src/library/utils/Makefile.win has no iconvlist target; only Makefile.in runs `iconv -l`), and with HAVE_ICONVLIST (every zigbuild/config/win-*/config.h) iconvlist() returns Riconv.dll's own list and reads the file only when that list is empty (base/R/New-Internal.R). CRAN-compatible and the simplest: a step removed, nothing added (F1, F2) |
| L2 | item 1, unix | (a) the same; **(b) unchanged** | (b) | upstream unix runs `iconv -l` too; not this item (F10 is Windows) |
| L3 | item 2: where the hint looks | **(a) rzig's own directory (R_HOME/bin/toolchain) + the group's subdirectory, first, every OS**; (b) unix only | (a) | one rule: R puts R_HOME/bin/toolchain/usr/bin and cmake/bin on PATH itself on every OS (etc/Renviron, Rcmd_environ, base's Rprofile on Windows), and the Windows wheel has its make there too (scripts/wheel-test-windows.py); checked before R's environment, since that is the directory R puts first |
| L4 | item 2: cmake too | **(a) yes, cmake/bin (extras group)**; (b) make only | (a) | the same function and one field (`Sub.own`); the extras group's cmake is in R_HOME/bin/toolchain/cmake/bin |
| L5 | item 2: wording | **"<what>; <path> is R's own, on PATH in R and under R CMD only: outside R, put <dir> on PATH"** | | starts with the lines every harness matches by prefix ("zig-cc: no make on PATH", verify-bundle.sh's starts_line, wheel-test.sh's grep -F, check-test.sh's exact lines have no make beside rzig) and does not contain " is installed in ", which recipe/test-build-tools.R's unix branch forbids today (F4) |
| L6 | item 3: how the depfile is made | (a) drop the request (before); **(b) zig rc's `/:depfile` (JSON, its only format) to `<file>.json`, then rzig writes make's rule and removes the JSON**; (c) run a C preprocessor for -M | (b) | zig rc lists exactly what it read (input, includes, RCDATA/ICON files); (c) would be a second preprocessor whose view may differ (F5) |
| L7 | item 3: which preprocessor args count | **-MD or -MMD, -MF (joined or the next arg), -MQ (make-quoted, several allowed), -MT (as given); the target defaults to the output** | | gcc's meaning; no -MD/-MMD or no -MF: no depfile, as before. -MMD's leaving out of system headers is not kept (zig rc lists all): a superset, only more rebuilds |
| L8 | item 3: run | **spawn and wait only when a depfile is asked for** (exec otherwise, unchanged) | | the rule is written after zig rc exits 0; on failure the JSON is removed and zig rc's code returned |
| L9 | item 4: variant on conda legs | (a) map to r-zig packages; **(b) tree legs only; a conda leg with full/openblas fails its first step** | (b) | stress.R --conda installs r-zig-slim only; full/openblas are not conda packages |
| L10 | item 4: how the variant runs | (a) change pixi.toml's stress task; **(b) in stress.yaml: `pixi run -e <env> build`, `pixi run -e <env> compile-tree`, then `pixi run -e stress <compile tree>/bin/Rscript stress/stress.R`** | (b) | pixi.toml is not this track's, and slim's path stays the stress task, as before. The flavor is env.sh's (full; slim-openblas) |
| L11 | item 4: report | **report.md's Builder line also names R_HOME; artifacts `stress-<os>-<dist>-<variant>` for full/openblas** | | the report says which tree ran; slim's artifact name unchanged |

## Findings

- **F1 (V) upstream writes no utils/iconvlist on Windows.** R 4.6.1
  source: src/library/utils/Makefile.in has `iconvlist:` (`-@iconv -l > $@
  2> /dev/null || touch $@`), Makefile.win has no such target.
  base/R/New-Internal.R: `int <- .Internal(iconv(NULL, ...)); if
  (length(int)) return(sort.int(int))`, the file only after. Every
  zigbuild/config/*/config.h has `#define HAVE_ICONVLIST 1`; nothing in
  the repo reads utils/iconvlist (grep, patches excluded).
- **F2 (V) Windows R's iconvlist() does not need the file.** kappa,
  `pixi exec -c https://prefix.dev/universe -c conda-forge -s r-zig-slim`
  (r-zig-slim-4.6.2-hb04b5bb_12, win-64), Rscript.exe --vanilla:
  `.Internal(iconv(NULL, "", "", "", TRUE, FALSE))` has 374 names,
  `iconvlist()` is identical to it (UTF-8 and CP1252 in it). Build 12
  ships the file (made from CI's Git iconv.exe), unread.
- **F3 (V) the build.zig diff compiles.** delta, a copy of the worktree
  with N1 applied (~/rz/scratch-b13-left/bz): `zig build -l` lists the
  steps (build.zig compiled). Not built for Windows here: the change
  removes a step and adds no code.
- **F4 (V) texts that match the build-tools line.** grep of scripts/,
  recipe/, zigbuild/tools/rzig/*.sh: verify-bundle.sh (`no_make_line`,
  preflight_stops: prefix via starts_line, base alone, so no make beside
  rzig), wheel-test.sh (`grep -qF 'no make on PATH'`, before the
  build-tools wheel), check-test.sh (exact lines; its fake tree has no
  usr/bin/make), recipe/test-build-tools.R (unix: `!grepl(" is installed
  in ", line)`; passes with L5's text, N2 makes it check the new text),
  recipe/test-extras.R (the R's-environment text, unchanged).
- **F5 (V) zig rc's depfile.** delta, zig 0.17.1: `zig rc /?` has
  `/:depfile <path>` and `/:depfile-fmt json` (the only format); a .rc
  with an #include and an RCDATA file gives `["app.rc", "inc/ver.h", "my
  data.bin"]`, relative as given, the input first.
- **F6 (V) meson 1.12.1's request.** mesonbuild/modules/windows.py:
  detects `^.*GNU windres.*$` in --version, calls `<args> @INPUT@
  @OUTPUT@ --preprocessor-arg=-MD --preprocessor-arg=-MQ@OUTPUT@
  --preprocessor-arg=-MF@DEPFILE@`, depfile `<output>.d`, type gcc.
- **F7 (V) meson + ninja with rzig's windres, both zigs.** delta,
  `pixi exec -s meson -s ninja`, cross file host windows/x86_64, c = `zig
  cc -target x86_64-windows-gnu`, windres = rzig (built from this tree)
  by that name, project with `windows.compile_resources('app.rc',
  include_directories: ...)`. ZIG_BIN = conda-forge zig 0.17.1: build ok;
  `ninja -t deps` records app.rc_app.o's 3 deps (../src/app.rc,
  src/inc/ver.h, `../src/my data.bin`); no-op build "no work to do";
  touching ver.h rebuilds the resource ("recorded mtime of app.rc_app.o
  older than most recent input .../inc/ver.h"), touching the data file
  too; no `.d.json` left. ZIG_BIN = upstream ziglang 0.17.1: the same 3
  deps, the rebuild after touching ver.h, no JSON left.

- **F8 (V) the make hint on a real tree.** delta, the full compile tree
  built from this worktree (rzig included): `env -i PATH=/nonexistent
  .../lib/R/bin/toolchain/zig-cc --rzig-check=build-tools` exits 127 with
  "zig-cc: no make on PATH; <R_HOME>/bin/toolchain/usr/bin/make is R's
  own, on PATH in R and under R CMD only: outside R, put
  <R_HOME>/bin/toolchain/usr/bin on PATH", then the build tools' text.
- **F9 (V) stress.yaml's variant path.** delta: the Stress step's `run:`
  script taken from stress.yaml as is (python yaml) and run with the
  step's variables (STRESS_R_ENV=full, then openblas; RUNNER_OS=Linux),
  after `pixi run toolchain` and `pixi run -e <env> build`; targets
  `tinyjobs curl RcppArmadillo`. full: compile tree
  build/compile-tree/full, report R_HOME `.../compile-tree/full/...`,
  3/3 ok (expect ok). openblas: build/compile-tree/slim-openblas, R_HOME
  `.../compile-tree/slim-openblas/...`, 3/3 ok; that tree's La_library()
  and extSoftVersion()["BLAS"] are its lib/libopenblas.so.0. Logs
  ~/rz/scratch-b13-left/variant/. The slim branch (the stress task) is
  unchanged text; not re-run. The "Check the inputs" step and the
  setup-pixi environments expression were read, not run (no dispatch).

## Tests

| where | command | result |
|---|---|---|
| delta | `zig build --build-file zigbuild/tools/rzig/build.zig test` (conda-forge 0.17.1) | 240/240 |
| delta | meson/ninja cross check (F7), conda-forge zig and upstream zig | deps recorded, rebuild on header change, both |
| kappa | iconvlist() on published r-zig-slim _12 win-64 (F2) | 374 names, from Riconv.dll |
| delta | `zig build -l` with N1 applied (F3) | compiles |
| delta | `pixi run rzig-test` (conda-forge zig 0.17.1), final tree | EXIT=0: 240/240 unit, check-test 60 passed 0 failed, link objects |
| delta | `ZIG_BIN=<upstream ziglang 0.17.1> pixi run rzig-test`, final tree | EXIT=0: the same counts |
| delta | `--rzig-check=build-tools` on the full compile tree, empty PATH (F8) | 127, the new line |
| delta | `pixi run -e full build`, `pixi run -e openblas build`, then stress.yaml's Stress script for each (F9) | 0, 0; 3/3 ok each |

## Needs (outside this track's files)

- **N1 (build.zig, item 1)**, exact diff:

```diff
--- a/build.zig
+++ b/build.zig
@@ -2345,11 +2345,11 @@
     // unix, installed under the Windows R_HOME layout.
     installCommonPayload(ctx);
 
-    // utils iconvlist (basepkg iconvlist target: `iconv -l`) — same as
-    // unix; conda-forge's Windows env also ships iconv.exe.
-    const iconv_run = b.addSystemCommand(&.{ "iconv", "-l" });
-    const iconv_out = iconv_run.captureStdOut(.{});
-    _ = libstage.addCopyFile(iconv_out, "utils/iconvlist");
+    // No utils/iconvlist on Windows, as upstream (utils/Makefile.win has
+    // no iconvlist target, unlike Makefile.in's `iconv -l`): config.h's
+    // HAVE_ICONVLIST makes iconvlist() return Riconv.dll's own list, and R
+    // reads the file only when that list is empty (base's New-Internal.R).
+    // No recipe package has an iconv.exe (b13-leftovers item 1).
 
     return libstage;
 }
```

  Then b13-recipe's kappa conda-package runs without Git's usr/bin on
  PATH (F10's workaround no longer needed).

- **N2 (recipe/test-build-tools.R, item 2)**: check the new unix text
  instead of its absence:

```diff
--- a/recipe/test-build-tools.R
+++ b/recipe/test-build-tools.R
@@ -86,8 +86,9 @@
 ## Windows the check says so, naming this env's make (m2's, in
 ## Library/usr/bin), then the text (PHASE4 open point I a, Cg2); on unix,
 ## whose make is R_HOME's (etc/Renviron puts it on PATH in R and under R
-## CMD), it says only "no make on PATH" (with MAKE=make: Renviron's
-## default), then the text. On
+## CMD), it names that make as R's own and the directory to put on PATH
+## outside R (with MAKE=make: Renviron's default; b13-leftovers item 2),
+## then the text. On
 ## Windows only outside R: under R CMD (Rcmd_environ) and in sessions
 ## (Rprofile.windows) R puts this env's Library/usr/bin on PATH itself,
 ## after the group's usr/bin, so the same PATH (with this env's
@@ -102,9 +103,10 @@
           if (windows) endsWith(line, not_on_path) &&
               same_path(sub("^.*; ", "", substr(line, 1L, nchar(line) - nchar(not_on_path))),
                         paste0(make_dir, "/make.exe"))
-          else !grepl(" is installed in ", line, fixed = TRUE),
+          else line == sprintf("zig-cc: no make on PATH; %s/make is R's own, on PATH in R and under R CMD only: outside R, put %s on PATH",
+                               make_dir, make_dir),
           any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")))
-cat("build tools: make off PATH", if (windows) "is named as installed in this env" else "is reported", ": OK\n")
+cat("build tools: make off PATH", if (windows) "is named as installed in this env" else "is named as R's own, with its directory", ": OK\n")
 ## unix: R's own sessions find the group's make with a PATH that lacks
 ## it (etc/Renviron puts R_HOME/bin/toolchain/usr/bin first)
 if (!windows) {
```

- **N3 (b13-integration/CI-WAVE.md, item 4)**: replace "Not expressible,
  left out: CI5's full and openblas variants" with two dispatches (one
  variant per run; tree legs):

```
S5. CI5's full variant (tree):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["ubuntu-latest"]' -f packages=all -f skip=heavy \
      -f distribution=tree -f variant=full

S6. CI5's openblas variant (tree):

    gh workflow run stress.yaml --ref build13 \
      -f oses='["ubuntu-latest"]' -f packages=all -f skip=heavy \
      -f distribution=tree -f variant=openblas
```

  Read: report.md's "R_HOME" line names build/compile-tree/full or
  slim-openblas; the rows against S1's ubuntu-latest tree table.

## Review (2026-11-24)

Skeptical review of the track's diff (check.zig, binutils.zig, main.zig,
stress.yaml, stress/stress.R, stress/README.md, this file).

Scope: the track touched only its own files. The other uncommitted
changes in the worktree (README.md, build.zig's winRfe comment,
zigbuild/patches/R-4.6.2/0016-rfe-env-dll-path.patch,
b13-hosts/PLAN.md, b13-integration/PLAN.md) are decision 4b's (b13-hosts
D9) and were left as they are.

Findings and fixes:

- **R1 (fixed) the make/cmake hint named any usr/bin beside rzig.**
  notOnPath looked in `<rzig's dir>/usr/bin` wherever rzig was, so an
  rzig outside R (a bare copy beside some usr/bin/make) would call that
  make "R's own". Now only when rzig's directory ends in `/bin/toolchain`
  (self_exe is `/`-separated on every OS, main.zig selfExe). Unit test
  extended (a bare zig-cc beside usr/bin/make: no "R's own").
- **R2 (fixed) stress.yaml: openblas on windows-11-arm.** pixi.toml's
  openblas feature has no win-arm64, so setup-pixi would have failed
  solving the env. The "Check the inputs" step now stops that leg first
  with the reason; its values reach the script through `env:`, not
  `${{ }}` in the script text.
- **R3 (checked, no change) Windows variant trees find their DLLs.**
  The variant legs run the variant tree's bin/x64/Rscript.exe in the
  stress env, which has no openblas or Tcl/Tk. vendor-libs.sh copies the
  tree's conda DLLs into R_HOME/bin/x64 (and winBlasForwarder imports one
  openblas function so openblas.dll is in that closure), as slim's tree
  does for its own. Not run on a Windows runner: the windows-latest
  openblas line in stress/README.md is a first dispatch, not a result.
- **R4 (checked) recipe tests with the new hint.** Conda packages put no
  make in R_HOME/bin/toolchain/usr/bin on Windows (recipe.yaml: pkgconf
  only) and no cmake/bin anywhere, so test-build-tools.R's Windows branch
  and test-extras.R keep their "is installed in R's environment" text;
  the unix branch's `!grepl(" is installed in ")` passes with the new
  text. N2 is an improvement, not a fix PR #57 needs. N2 compares the
  whole line with `==`: R's normalizePath and rzig's executable path both
  resolve links, but `same_path()` on the path taken out of the line
  (as line 71 does) would be sturdier.
- **R5 (checked) windres depfile.** Only the `.windres` path spawns
  instead of exec'ing; the failure path removes the JSON and returns zig
  rc's code; ctx.discard is not used by windres (run's Windows-only
  cleanup is dlltool's implib). Make quoting matches gcc's (`\ `, `\#`,
  `$$`), which ninja's depfile parser reads.
- **R6 (checked) gated workflow.** stress.yaml stays workflow_dispatch
  only (no pull_request/pull_request_target), uses no secrets, and its
  only upload is actions/upload-artifact; the variant input is a choice.
- **R7 (checked) claims.** HAVE_ICONVLIST in win-full, win-minimal and
  win-slim config.h (grep); R puts R_HOME/bin/toolchain/usr/bin and
  cmake/bin on PATH (build.zig's Renviron PATH line, R_ZIG_TOOLS_PATH,
  patch 0014). F1 holds for R 4.6.2 too: in R-4.6.2.tar.gz src/library/utils/Makefile.in
  has `iconvlist:` (`-@iconv -l > $@ 2> /dev/null || touch $@`),
  Makefile.win no `iconv` at all.

Review tests:

| where | command | result |
|---|---|---|
| delta | `pixi run rzig-test` (conda-forge zig 0.17.1), after R1 | EXIT=0: 240/240 unit, check-test 60 passed 0 failed |
| delta | `ZIG_BIN=<upstream ziglang 0.17.1> pixi run rzig-test`, after R1 | EXIT=0: the same counts |
| delta | rzig built from the tree as `<dir>/lib/R/bin/toolchain/zig-cc` and as `<dir>/bare/zig-cc`, each with usr/bin/make beside it, `env -i PATH=/nonexistent ... --rzig-check=build-tools` | 127 both; the first names R's own make and its directory, the second says only "no make on PATH" |
| kappa | the same with rzig cross-built for x86_64-windows-gnu, as `...\Library\lib\R\bin\toolchain\gcc.exe` and `bare\gcc.exe` | 127 both; the first: `no make on PATH; C:/.../toolchain/usr/bin/make.exe is R's own, ... put C:/.../toolchain/usr/bin on PATH`; the second the bare line. kappa scratch removed |
| delta | `pixi exec -s actionlint -s shellcheck actionlint .github/workflows/stress.yaml` | rc=0, no findings |
