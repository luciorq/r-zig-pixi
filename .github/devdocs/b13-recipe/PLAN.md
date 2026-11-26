# b13-recipe

## Goal

Build 13's recipe items (chore-release-12/BACKLOG.md): the build-number
bump, L3 (one base with add-ons, tcltk first), licence and test hygiene
for the new output, Q20 (which flang-pixi builds the recipe still pins),
and CI11's recipe side if b13-env-ci needs it. Branched from main
7e3648e (build 12 published, run 45381914199).

## Decisions

| id | question | options (chosen in bold) | reason | who |
|---|---|---|---|---|
| R1 | how tcltk becomes an add-on | (a) slim's variant table gets tcltk on every OS (regenerate 5 vendored configs, standalone trees ship Tcl/Tk); **(b) a build option `-Dtcltk` that puts Tcl/Tk on top of the variant, used by the conda build only**; (c) keep tcltk in a full-only build | (b) changes nothing for the standalone archives and the wheel, needs no config capture, and reads the Tcl/Tk keys from the platform's own vendored full config, so there is no second copy of them; (a) is the larger "one base" step and can follow | default, 2026-11-24 |
| R2 | which package holds the tcltk package | **(a) r-zig-tcltk holds `library/tcltk/**` whole, r-zig-slim has no tcltk directory**; (b) r-zig-slim keeps the stub and r-zig-tcltk overwrites it; (c) the R code in the base, only `libs/` in the add-on | (b) is a clobber (`--error-overlapping-files`); (c) leaves a package whose .onLoad fails on a missing DLL; (a) is r-zig-recommended's pattern | default, 2026-11-24 |
| R3 | capabilities("tcltk") in the base | **(a) TRUE (libR built with HAVE_TCLTK)**; (b) FALSE (no HAVE_TCLTK; only the package) | packages test capabilities("tcltk") before using tcltk, so with the add-on it has to be TRUE; capabilities() is compile-time in libR (platform.c). Without the add-on it says TRUE and library(tcltk) says the package is not installed, as CRAN's macOS R says TRUE without XQuartz | default, 2026-11-24 |
| R4 | win-arm64 | **(a) no r-zig-tcltk there; the base keeps the stub (no -Dtcltk)**; (b) Tcl/Tk 9 | conda-forge has only tk 9.0.4 for win-arm64 (`pixi search -p win-arm64 tk`), and win-full's config links tcl86t/tk86t; Tcl/Tk 9 is its own item | default, 2026-11-24 |
| R5 | r-zig-tcltk's run deps | **r-zig-slim exact, `tk 8.6.*`, linux `xorg-xorgproto`**; no `xorg-libx11` | tcltk.so needs libtcl8.6/libtk8.6 and not libX11 (readelf, T3); tk.h includes X11/X.h, so a package compiled against Makeconf's TCLTK_CPPFLAGS (tkrplot) needs xorgproto (T5) | default, 2026-11-24 |
| R6 | r-zig-tcltk's licence | **`GPL-2.0-only OR GPL-3.0-only`; R's COPYING, GPL-2, GPL-3, r-zig's LICENSE, zig's set** | the payload is R's tcltk package; Tcl/Tk is a dependency, not bundled; tcltk.so is zig-linked (compiler_rt, libc start files), as wave2-licences L3 | default, 2026-11-24 |
| R7 | the build-13 comment above `number:` | **not written here** (only `number: 12` → `13`); the summary is below for whoever writes it | the task: another branch edits that block | task, 2026-11-24 |

## Findings

- **F1 (V) L3 works on linux-64 with the build.zig change below.** delta,
  `pixi run -e pkg conda-package` (log ~/rz/scratch-b13-recipe/conda-package2.log):
  seven packages, all `_13`, "all tests passed" 7 times;
  r-zig-tcltk-4.6.2-hdf2e536_13.conda 308 KiB, its test
  "conda tcltk OK: Tcl 8.6.13 ; Tk not started (no display)";
  r-zig-slim's one-liner with `caps[["tcltk"]], !nzchar(system.file(package = "tcltk"))`
  printed "conda R OK". r-zig-slim's build string is unchanged
  (h3e03716, as `_12`): tk is no variant key.
- **F2 (V) r-zig-slim does not depend on tk.** Its info/index.json
  `depends` has no tk (the `ignore_run_exports: by_name: [tk]`);
  r-zig-tcltk's: `r-zig-slim ==4.6.2 h3e03716_13`, `tk 8.6.*` (first
  run, with xorg-libx11 since dropped; second run adds xorg-xorgproto,
  log line 7623).
- **F3 (V) tcltk.so links what it should.** readelf: NEEDED libR.so,
  libtcl8.6.so, libtk8.6.so, libc.so.6; RPATH
  `$ORIGIN/../../../..:$ORIGIN/../../../lib` (the env's lib, R's lib).
  rattler-build's overlinking warnings for it are libc.so.6 and libR.so,
  as for every R package (r-zig-recommended's too).
- **F4 (V) Makeconf names no build path.** First run stopped in
  build.zig's assertNoBuildPath: `TCLTK_CPPFLAGS = -I$PREFIX/include`;
  the change now writes Makeconf's form through makeconfValue, as
  loadSubstFile does: `TCLTK_CPPFLAGS = -I$(R_HOME)/../../include ...`,
  `TCLTK_LIBS = -L$(R_HOME)/../../lib -ltcl8.6 -L$(R_HOME)/../../lib -ltk8.6 -lX11`.
- **F5 (V) a fresh env behaves as designed** (delta, pixi workspace
  ~/rz/scratch-b13-recipe/consume, channels dist/conda, universe,
  conda-forge, no DISPLAY): r-zig-slim alone: capabilities("tcltk") TRUE,
  `library(tcltk)` → "‘tcltk’ is not a valid installed package";
  + r-zig-tcltk: test-tcltk.R OK (tk 8.6.13 noxft_h1df4ec4_4, xorg-libx11
  1.8.14 pulled by tk).
- **F6 (V) tkrplot compiles against the add-on** (r-zig-tcltk +
  r-zig-toolchain, `install.packages("tkrplot", INSTALL_opts = "--no-test-load")`):
  without xorg-xorgproto, `tk.h` → `X11/Xlib.h:44: 'X11/X.h' file not found`;
  with it, DONE; tkrplot.so NEEDED libtcl8.6, libtk8.6, libX11.so.6, libR.
  Test-load skipped: no X server on delta.
- **F7 (V) upstream zig.** delta, full env (tk 8.6), PyPI ziglang 0.17.1
  (`pixi run -e full fetch-zig`), `R_BUILD_VARIANT=slim ... zig-build.sh -Dtcltk=true`
  into a standalone prefix: EXIT=0; the tree has lib/R/library/tcltk/libs/tcltk.so,
  lib/{libtcl8.6.so,libtk8.6.so,tcl8,tcl8.6,tk8.6} (installEnvRuntime
  follows ctx.feat.tcltk), the same Makeconf lines as F4, and
  capabilities("tcltk") TRUE, `clock format 0 -gmt 1 -format %Y` = 1970
  without DISPLAY.
- **F8 (V) renders.** `rattler-build build --render-only` (delta,
  rattler-build from the pkg env): linux-64, win-64, osx-arm64 list seven
  outputs with r-zig-tcltk; win-arm64 six (build.skip).
- **F9 (V) conda-consume still passes** on the new packages (delta,
  `pixi run -e pkg conda-consume`, EXIT=0, log ~/rz/scratch-b13-recipe/consume.log).
  It does not test r-zig-tcltk yet (Needs N2).
- **F10 (V, pre-existing) the Windows conda build runs `iconv -l` from
  the machine, not from a recipe package.** kappa, first conda-package
  run: `error: failed to spawn and capture stdio from iconv: FileNotFound`
  (build.zig:2302, utils/iconvlist). The build env has libiconv
  (Library/bin/iconv.dll) and m2-libiconv but no iconv.exe anywhere in
  build_env, h_env or the pkg env (`dir /s /b ...\iconv.exe`: File Not
  Found); kappa's own Git has `C:\Program Files\Git\usr\bin\iconv.exe`
  but not on PATH. (I) GitHub's Windows images put Git's usr/bin on
  PATH, which is why CI's win-64 conda-package passes. Not caused by
  this change (the step is the same for slim). For b13-build or
  b13-env-ci: give the step an iconv from the build env, or write
  iconvlist without a program. The kappa test re-ran with Git's usr/bin
  appended to PATH, to match CI.
- **F13 (V) win-64 builds and runs tcltk.** kappa, conda-package with
  Git's usr/bin on PATH (F10), log copied to gamma scratch-b13-recipe/kappa-conda2.log:
  the staging build passed (`-Dcairo=... -Dtcltk=true`), staging cache
  has Library/lib/R/library/tcltk/libs/x64/tcltk.dll; r-zig-slim
  `_13` built and its tests passed with test-win.R's new branch ("conda
  R OK", "conda tcltk: none in the base (r-zig-tcltk's)", "all tests
  passed!"). A fresh pixi env on kappa with that r-zig-slim and tk
  8.6.13, plus the staging cache's tcltk directory copied into its
  library (what r-zig-tcltk installs): etc/Renviron.site has
  `MY_TCLTK=${MY_TCLTK-${R_ZIG_TCLTK}}`, and test-tcltk.R printed
  "conda tcltk OK: Tcl 8.6.13 ; Tk up" (exit 0).
- **F11 (V) Q20: what universe still holds and who pins it**
  (repodata.json of all six subdirs, fetched 2026-11-24 from
  repo.prefix.dev/universe; scratch-b13-recipe/repodata/). This recipe
  pins flang-zig 23.1.5 `_0` and flang-rt-zig 23.1.5 `_1` (lld-zig
  23.1.5 `_0` through flang-zig) and llvm-openmp `zig_*`; nothing 23.1.1.
  On universe:
  - LLVM 23.1.1, zig 0.16 set (lld-zig `_5`, flang-zig `_6`,
    flang-rt-zig `_10`): still pinned exactly by published
    r-zig-compilers 4.6.1 `_9`, `_10` and r-zig-toolchain 4.6.1 `_5` to
    `_8` (linux-64, linux-aarch64, osx-64, osx-arm64, win-64; none on
    win-arm64). Needed while those r-zig builds stay on the channel.
  - LLVM 23.1.1, zig 0.17 set (lld-zig `_6`, flang-zig `_7`,
    flang-rt-zig `_11`): pinned by no published r-zig package (build 11
    went straight to 23.1.5). flang-pixi may prune them as far as r-zig
    is concerned.
  - r-zig-slim 4.6.1 `_2`/`_3` depend on unpinned `flang-zig` and
    `flang-rt-zig` (osx, win-64, linux-aarch64), so any build satisfies
    them.
  Note for flang-pixi (not sent, per the task): "r-zig's recipe (build
  13) pins only LLVM 23.1.5: flang-zig _0, flang-rt-zig _1, lld-zig _0
  (through flang-zig), llvm-openmp zig_*_1. The retained 23.1.1 set
  lld-zig 5 / flang-zig 6 / flang-rt-zig 10 is still pinned by the
  published r-zig-compilers 4.6.1 _9/_10 and r-zig-toolchain 4.6.1
  _5.._8; keep it while r-zig keeps those. The zig-0.17 23.1.1 set
  lld-zig 6 / flang-zig 7 / flang-rt-zig 11 is pinned by no r-zig
  package." Telling flang-pixi, and deciding whether r-zig deletes its
  4.6.1 builds (which would free the retained set), is the user's.
- **F12 (V) CI11 now: no zstd overlinking on win-64; other warnings.**
  Run 45381914199, job 138402832839 (conda-package / win-64), 37
  "Overlinking against" lines, none for zstd.dll: 36 against the
  runner's CRAN R (`C:\Program Files\R\R-4.6.2\bin\x64\R.dll`, Rblas,
  Rlapack, Rgraphapp) for R's own DLLs and the recommended packages, 1
  against the pkg env's `Library/bin/libomp.dll`. rattler-build
  resolves a DLL by the machine's search path, not the package's
  bin/x64 or the host prefix. The recipe already lists zstd and
  llvm-openmp in host and run on every OS, so no recipe change; b13-env-ci
  owns the item.

## Build-13 summary (for the comment block above `number:`)

12 → 13: R's tcltk package is the add-on r-zig-tcltk (every subdir but
win-arm64), built in the same build on top of slim (`-Dtcltk`: the
platform's full config's Tcl/Tk keys and HAVE_TCLTK) against
conda-forge's tk 8.6; r-zig-slim has no tcltk package there and
capabilities("tcltk") is TRUE; win-arm64 keeps the stub
(b13-recipe PLAN.md). Plus the other build-13 topics' lines.

## Tests run

| where | command | result |
|---|---|---|
| gamma | `curl repo.prefix.dev/universe/<subdir>/repodata.json` (6 subdirs) | F11 |
| gamma | `gh run view 45381914199 --job 138402832839 --log` | F12 |
| delta | `rattler-build build --render-only` linux-64, win-64, osx-arm64, win-arm64 | F8 |
| delta | `pixi run -e pkg conda-package` with the build.zig change (run 1) | stopped: F4 |
| delta | same, makeconfValue added (run 2) | 7 packages, 7 test sets passed |
| delta | same, recipe with xorg-xorgproto and without xorg-libx11 (run 3, conda-package2.log) | 7 packages, 7 test sets passed |
| delta | `pixi run -e pkg conda-consume` | EXIT=0 (F9) |
| delta | fresh pixi workspace: base alone; + r-zig-tcltk (test-tcltk.R); + r-zig-toolchain, tkrplot | F5, F6 |
| delta | upstream zig 0.17.1, full env, `R_BUILD_VARIANT=slim zig-build.sh -Dtcltk=true`, standalone prefix | EXIT=0 (F7) |
| kappa | `pixi run -e pkg conda-package` (win-64) | run 1 stopped at F10 (pre-existing); run 2 (Git usr/bin on PATH): staging and r-zig-slim passed (F13), stopped during r-zig-compilers' tests (time) |
| kappa | fresh pixi env: r-zig-slim `_13` + tk 8.6 + the staged tcltk directory, test-tcltk.R | OK, Tk up (F13) |

## Not verified

- win-64's r-zig-tcltk package itself (its file glob, package_contents
  and script test through rattler-build): kappa's run 2 restored the
  staging cache for each output in about 25 minutes (kappa was shared
  with other topics' builds), so it was stopped while r-zig-compilers'
  tests ran (r-zig-slim and r-zig-compilers `_13` built), and the
  scratch dir removed. F13 has what was verified of tcltk on win-64;
  CI's win-64 conda-package leg covers the package.
- macOS (osx-arm64, osx-64) and linux-aarch64: render only. The full
  configs' Tcl/Tk keys there are the same shape (osx: no -lX11).
- Tk with a display (Xvfb, or Windows' desktop): only Tcl is exercised
  by the recipe test.
- conda-forge's zig with `-Dtcltk` outside rattler-build (the dev tree):
  the conda build is conda-forge's zig, the upstream run is F7.

## Needs from other topics

- **N1 (b13-build, build.zig): the `-Dtcltk` option.** Without it the
  recipe's build.sh passes an option build.zig does not know and the
  conda build stops. Exact diff (tested as F1-F7):

```diff
--- a/build.zig
+++ b/build.zig
@@ -184,7 +184,8 @@
     // only libR/libRblas/libRlapack use this. Packages/modules always use
     // SHLIB_EXT, which is ".so" on every platform R supports.
     variant: Variant,
-    feat: Features, // variantFeatures(variant, os)
+    feat: Features, // variantFeatures(variant, os); tcltk also with -Dtcltk (addTcltk)
+    tcltk_addon: bool, // -Dtcltk: Tcl/Tk on top of the variant (addTcltk)
     blas: Blas,
     conda: []const u8,
     src_abs: []const u8, // absolute path of R source tree
@@ -399,6 +400,11 @@
 
     const variant = b.option(Variant, "variant", "R build variant: slim (default), full, or minimal") orelse .slim;
     const blas = b.option(Blas, "blas", "BLAS/LAPACK flavor: internal (default) or openblas") orelse .internal;
+    // The conda build's add-on r-zig-tcltk (recipe/recipe.yaml): the
+    // variant's R with Tcl/Tk on top (HAVE_TCLTK, the tcltk package's DLL
+    // and its real R code), from the full config's Tcl/Tk keys
+    // (addTcltk). The full variant has it already.
+    const tcltk = b.option(bool, "tcltk", "Tcl/Tk on top of the variant (the conda build's r-zig-tcltk add-on)") orelse false;
     const cairo_dir = b.option([]const u8, "cairo", "cairo's source tarball, unpacked (the conda build's; else build.zig.zon's cairo): Windows' winCairo.dll");
 
     // R's platform is the native one of the zig that runs this build,
@@ -578,6 +584,7 @@
         .dylib_ext = dylib_ext,
         .variant = variant,
         .feat = variantFeatures(variant, os),
+        .tcltk_addon = tcltk,
         .blas = blas,
         .conda = conda,
         .src_abs = src_abs,
@@ -682,7 +689,7 @@
         // The vendored config.h, with the two lines that name the
         // capture's compilers rewritten for this build's (setDefine).
         const raw = try std.Io.Dir.cwd().readFileAlloc(io, rootPath(b, b.fmt("{s}/config.h", .{config_dir})), b.allocator, .limited(4 * 1024 * 1024));
-        _ = geninc.add("config.h", try setDefine(b, try setDefine(b, raw, "CC_VER", ctx.cc_ver), "FC_VER", ctx.fc_ver));
+        _ = geninc.add("config.h", try setDefine(b, try setDefine(b, try tcltkConfigH(&ctx, raw), "CC_VER", ctx.cc_ver), "FC_VER", ctx.fc_ver));
     }
     _ = geninc.addCopyFile(b.path(b.fmt("{s}/Rconfig.h", .{config_dir})), "Rconfig.h");
     _ = geninc.add("Rversion.h", try genRversionH(&ctx, io));
@@ -1099,7 +1106,7 @@
     const geninc = b.addWriteFiles();
     {
         const raw = try std.Io.Dir.cwd().readFileAlloc(io, rootPath(b, b.fmt("{s}/config.h", .{ctx.config_dir})), b.allocator, .limited(4 * 1024 * 1024));
-        _ = geninc.add("config.h", try substitute(ctx, raw));
+        _ = geninc.add("config.h", try substitute(ctx, try tcltkConfigH(ctx, raw)));
     }
     _ = geninc.addCopyFile(b.path(b.fmt("{s}/Rconfig.h", .{ctx.config_dir})), "Rconfig.h");
     _ = geninc.add("Rversion.h", try genRversionH(ctx, io));
@@ -3337,6 +3344,52 @@
     ctx.openmp_pkgs = (try substKey(ctx, "SHLIB_OPENMP_CFLAGS")).len > 0;
     ctx.devcairo = (try substKey(ctx, "BUILD_DEVCAIRO_TRUE")).len == 0;
     try checkVariantConfig(ctx, io);
+    if (ctx.tcltk_addon and !ctx.feat.tcltk) try addTcltk(ctx, io);
+}
+
+/// -Dtcltk: the variant (slim) with Tcl/Tk on top, for the conda build's
+/// r-zig-tcltk add-on. The Tcl/Tk keys of the same platform's full config
+/// (use_tcltk, TCL_CONFIG, TK_CONFIG, TCLTK_CPPFLAGS, TCLTK_LIBS; Windows'
+/// subst.txt has TCLTK_LIBS only) replace the variant's empty ones, and
+/// config.h defines HAVE_TCLTK (tcltkConfigH); Makeconf takes their
+/// env-relative form (makeconfValue). Everything else follows
+/// ctx.feat.tcltk, as for full. Run after checkVariantConfig, which
+/// compares the vendored dir with the variant itself.
+fn addTcltk(ctx: *Ctx, io: std.Io) !void {
+    const b = ctx.b;
+    const dash = std.mem.lastIndexOfScalar(u8, ctx.config_dir, '-').?;
+    const full_dir = b.fmt("{s}-full", .{ctx.config_dir[0..dash]});
+    const raw = try std.Io.Dir.cwd().readFileAlloc(io, rootPath(b, b.fmt("{s}/subst.txt", .{full_dir})), b.allocator, .limited(4 * 1024 * 1024));
+    var lines = std.mem.splitScalar(u8, raw, '\n');
+    while (lines.next()) |raw_line| {
+        const line = std.mem.trimEnd(u8, raw_line, "\r");
+        inline for (.{ "use_tcltk", "TCL_CONFIG", "TK_CONFIG", "TCLTK_CPPFLAGS", "TCLTK_LIBS" }) |key| {
+            const head = "S[\"" ++ key ++ "\"]=\"";
+            if (std.mem.startsWith(u8, line, head) and std.mem.endsWith(u8, line, "\"")) {
+                const val = line[head.len .. line.len - 1];
+                try ctx.subst.put(key, try std.mem.replaceOwned(u8, b.allocator, val, "@ZR_CONDA@", ctx.conda));
+                // Makeconf's form, as loadSubstFile's: $(R_HOME)/../.. for the env
+                if (std.mem.indexOf(u8, val, "@ZR_CONDA@") != null) try ctx.mk_subst.put(key, try makeconfValue(ctx, val));
+            }
+        }
+    }
+    if (std.mem.trim(u8, ctx.subst.get("TCLTK_LIBS") orelse "", " ").len == 0) {
+        std.debug.print("error: -Dtcltk: {s}/subst.txt has no TCLTK_LIBS\n", .{full_dir});
+        return error.MissingSubstKey;
+    }
+    ctx.feat.tcltk = true;
+}
+
+/// config.h with HAVE_TCLTK defined when -Dtcltk added Tcl/Tk (addTcltk):
+/// capabilities("tcltk") and R --gui=Tk, as full's.
+fn tcltkConfigH(ctx: *const Ctx, raw: []const u8) ![]const u8 {
+    if (!ctx.tcltk_addon or !ctx.feat.tcltk or hasDefine(raw, "HAVE_TCLTK")) return raw;
+    const undef = "/* #undef HAVE_TCLTK */";
+    if (std.mem.indexOf(u8, raw, undef) == null) {
+        std.debug.print("error: -Dtcltk: no '{s}' line in {s}/config.h\n", .{ undef, ctx.config_dir });
+        return error.NoSuchDefine;
+    }
+    return std.mem.replaceOwned(u8, ctx.b.allocator, raw, undef, "#define HAVE_TCLTK 1");
 }
 
 /// A key subst.txt must have; a missing one stops the build by name
```

  The same file: scratch-b13-recipe/proto/build-zig-tcltk.diff (gamma).
- **N2 (owner of scripts/conda-consume.sh): test r-zig-tcltk through
  activation**, as the other add-ons:

```
[feature.tcltk.dependencies]
r-zig-tcltk = "*"

[environments]
tcltk = ["tcltk"]
```
  in the heredoc's manifest, and `tcltk:test-tcltk.R` in the loop's
  list; all three only when `$PLAT` is not win-arm64 (no r-zig-tcltk
  there; the manifest's platforms are `$PLAT` only). Tested by hand as
  F5.
- **N3 (b13-build or b13-env-ci): F10**, `iconv -l` on Windows without a
  recipe package that has iconv.exe.
- **N4 (b13-env-ci): F12** for CI11.

## Review

Read the whole diff (recipe.yaml, build.sh, test-win.R, test-tcltk.R)
against the claims above. Findings:

- All changes are inside recipe/ (no variants.yaml, test-toolchain.R,
  or the comment block above `number:`); nothing to revert.
- build.sh: `-Dtcltk=true` reaches `zig build` (scripts/zig-build.sh:71
  forwards `"$@"`); `${target_platform:?}` stops on a missing value
  instead of building the wrong set. `bash -n` OK.
- test-win.R's `R.version$arch == "aarch64"` is right on win-arm64:
  win-slim's config.h:1136 defines R_CPU "aarch64" there.
- Windows MY_TCLTK: build.zig:3651-3657 writes `R_ZIG_TCLTK`/`MY_TCLTK`
  only when ctx.feat.tcltk, which N1's addTcltk sets; win-arm64 (no
  -Dtcltk) keeps an empty Renviron.site.
- The N1 diff still applies cleanly to this worktree's build.zig
  (`git apply --check`), and b13-build's build.zig does not have it yet
  (no `tcltk_addon`), so N1 stays the blocker for merging this topic.
- Changed: two comment lines in recipe.yaml reflowed (the outputs
  header and r-zig-tcltk's header); no behaviour change.
- R3 (capabilities("tcltk") TRUE in a base without the add-on) stays
  the default; it is the one user-visible change for slim users, and is
  noted for the release notes.

Re-run after the change (comment-only, so render only):

| where | command | result |
|---|---|---|
| delta | `rattler-build build --render-only -m recipe/variants.yaml` for linux-64, win-64, osx-arm64, osx-64, linux-aarch64, win-arm64 | 7 outputs with r-zig-tcltk on the first five, 6 on win-arm64 |
| gamma | `git apply --check scratch-b13-recipe/proto/build-zig-tcltk.diff`; `bash -n recipe/build.sh` | applies; OK |

## Suggested commit message

feat: ship R's tcltk package as the r-zig-tcltk add-on, build 13
