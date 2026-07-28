# TODO — feat-zig-build (Milestone 5)

## Phase 0 — spec extraction (from the milestone-1 objdir, the ground truth)

- [x] Artifact inventory: 6 static libs, libR.so (101 src/main objs),
      libRblas.so, libRlapack.so + lapack.so, internet.so, 9 base-package
      shlibs (+ grDevices cairo.so), bin/exec/R, bin/Rscript
- [x] config.status output inventory: 1 header (config.h) + ~14 real
      files; everything else is Makefiles (dead once make is gone)
- [x] Fortran source inventory: src/appl/*.f, src/extra/blas/*.f,
      src/modules/lapack/*.f, src/library/stats/src/*.f
- [x] Per-directory ALL_CFLAGS/ALL_CPPFLAGS from the objdir's generated
      Makefiles — dumped via a make print-rule into make-vars.txt; encoded
      in zigbuild/rspec.zig + build.zig
- [x] Bootstrap command sequence from src/library/Makefile.in +
      share/make/{basepkg,lazycomp}.mk — encoded in build.zig's bootstrap()
- [x] **config.status's S["VAR"]="value" table vendored wholesale** as
      zigbuild/config/linux-x86_64/subst.txt (machine paths parameterized
      as @ZR_*@ placeholders) — build.zig replays it for every `@VAR@`
      template, which makes template processing exactly config.status-
      faithful instead of a hand-maintained variable list. Gotcha: the
      table has awk continuation lines (`"\` + leading `"`), which a naive
      `grep '^S\['` silently drops — join them first.

## Phase 1 — worktree setup

- [x] R source tree in worktree (reuse cached tarball, fetch-r.sh extract)
- [x] pixi env solves in worktree; zig 0.16.0 + flang 22.1.8 run
- [x] Vendor config.h + Rconfig.h from build/obj-4.6.1-slim
- [x] Sys.which source patch applied (also folded into scripts/zig-build.sh
      so it can't silently go stale on refetch — the feat-initial-setup
      staleness gap doesn't apply here since there's no configure guard)

## Phase 2 — compile graph in build.zig

- [x] Generated headers: config.h/Rconfig.h vendored; Rversion.h generated
      in-zig (GETVERSION reimplemented); Rmath.h via subst of Rmath.h0.in
- [x] All C groups compile natively via Module.addCSourceFiles (one module
      per artifact, per-group flags); zig sets DT_SONAME correctly on its
      own (verified empirically) and allows undefined syms in shared libs,
      so package .so files link exactly like make's
- [x] Fortran via per-file flang Run steps (`-o` + `-module-dir` output
      args make them cacheable); libRlapack's f90 module deps expressed as
      step deps (la_constants → la_xisnan → lartg/lassq)
- [x] libRblas.so, libRlapack.so, libR.so (src/main + appl/nmath/tre/
      tzone/xdr/unix objects in one link, FLIBS + LIBS from Makeconf)
- [x] modules/lapack.so (+ flexiblas.o from src/main), modules/internet.so
- [x] 9 package .so + grDevices cairo.so (rbitmap.o from src/modules/X11;
      CAIRO_CPPFLAGS/CAIRO_LIBS taken from the vendored S-table)
- [x] bin/exec/R (rdynamic), bin/Rscript (-DR_HOME baked, like make's
      install-time compile)
- [x] Every module gets -L/-rpath $CONDA/lib at creation (first build
      failure: linkSystemLibrary("curl"/"z") without a search path)

## Phase 3 — bootstrap + layout in build.zig

- [x] etc/: Makeconf (zig-shim contract), Renviron, ldpaths, javaconf,
      repositories — all subst of the .in templates via the S-table
- [x] Front scripts: bin/R (R.sh.in subst + the four install-time seds:
      R_HOME_DIR first-occurrence, R_SHARE/INCLUDE/DOC_DIR), SCRIPTS_S
      copied, SCRIPTS_B subst; chmod +x Run step (WriteFiles emit 0644)
- [x] share/ + doc/ wholesale from srcdir; include/ = 5 public headers +
      generated 3 + R_ext/; share/zoneinfo via `unzip zoneinfo.zip`
- [x] library/ payload staged as its own WriteFiles tree; **bootstrap
      resets library/ from it on every run** (rm -rf + cp -R + chmod) —
      R mutates library/ in place, so rerunning after an interrupted
      bootstrap must not inherit half-mutated state (bug found the hard
      way: a stale Meta/package.rds without features.rds made the next
      run's loadNamespace(tools) fail with "installed by an R version
      with different internals")
- [x] Bootstrap chain (each step = one R Run step, stdin = the same R
      expressions the mk files feed): tools sysdata → compiler mkdesc/
      lazycomp → translations → base makebasedb + baseloader → tools
      makeLazyLoad + **tools mkdesc** (writes Meta/features.rds with
      internalsID — it's the tail of tools/Makefile.in's `all`, easy to
      miss, and required before anything with a libs/ dir loads once
      Meta/ exists) → BASE1 packages (mkdesc, sysdata/demos/data
      specials, mklazycomp; methods via loadNamespace + nspackloader;
      tcltk = stub, no lazycomp in slim) → base mkdesc → descriptions/
      namespaces/bibliographies/dictionaries RDS → Rd DBs + metadata +
      help indices → doc/NEWS artifacts → Rscript SVD sanity check
- [x] Base package shlibs staged into library/*/libs/ (part of the
      library payload so the reset re-places them)
- [x] lib/pkgconfig/libR.pc (install-pc, sed-style tokens)

## Phase 4 — validation (stop line for this branch)

- [x] `zig build` (via `pixi run zig-build`) produces a runnable slim R
      prefix at dist/R-4.6.1-slim-zig — 152/152 steps, ~5 min cold
      compile + ~1.5 min bootstrap; rebuilds re-run only the bootstrap
- [x] scripts/smoke-test.sh green against the zig-built prefix
      (2026-07-23, via new R_TEST_R_BIN override): numerics
      (solve/qr/fft through flang-built BLAS/LAPACK), pcre2, compression,
      exact slim capability profile (cairo/png/ICU/iconv/libcurl TRUE;
      X11/aqua/tcltk/jpeg/tiff/NLS FALSE), sessionInfo pointing at the
      zig-built libRblas/libRlapack; plus a real cairo PNG render
- [x] File-list diff vs the make-installed tree: 1840 make files vs 1853
      zig files, gaps closed to just bin/libtool (deliberate — see
      deltas below)

## Known deltas vs the autoconf/make build (deliberate, revisit later)

- **bin/libtool is not installed (F2.4, confirmed 2026-07-24).** It's
  generated by config.status CONFIG_COMMANDS (a 300KB shell script);
  nothing in the slim runtime, package compilation, smoke, or the F1.2
  contract test (which specifically exercises `R CMD SHLIB`/`INSTALL`
  compiling Rcpp's C++, data.table's C+OpenMP, and minqa's Fortran+Rcpp —
  the exact paths that would need it if anything did) uses it on Linux.
  Decision: drop it, per FINALIZATION.md's stated default. Revisit only if
  some R CMD flow turns out to want it later.
- ~~RUNPATH on zig-linked artifacts carries one extra relative zig-cache
  entry~~ — fixed (F2.3, 2026-07-24): `fixRpath` in build.zig strips it at
  the source via `patchelf --set-rpath` before install.
- **Vignettes and man pages** (R.1/Rscript.1, NEWS.pdf regeneration) are
  skipped exactly like the make build skips them here: no pdflatex or
  help2man in the env (NEWS.pdf ships prebuilt in the tarball).
- **Bootstrap steps re-run on every `zig build`** (side-effect Run steps,
  ~1.5 min): correctness over speed — library/ is reset from the staged
  pristine payload each time. A content-stamp optimization is possible
  later.
- The compile graph uses zig's native Compile steps, NOT the
  toolchain/zig-* shims — but etc/Makeconf still points packages at the
  shims, so the R CMD SHLIB contract is unchanged.

## Finalizing this milestone

See **FINALIZATION.md** (same directory) for the concrete, cold-start-ready
spec: phases F1 (make check + contract = the trust bar) → F2 (hardening) →
F3 (full/openblas variants) → F4 (distribution + CI) → F5 (macOS) → F6
(Windows, the endgame), each with exact commands, acceptance criteria, and
a carried-forward gotcha catalog.

### Finalization task checklist (transcribed from FINALIZATION.md)

- [x] **F1.2** contract test (Rcpp/data.table/minqa) green via
      `R_TEST_R_BIN` override against the zig prefix (2026-07-24) — found
      and fixed two real subst-table bugs in `loadSubstTable`/`build.zig`,
      see "Bugs found by F1.2" below
- [x] **F1.1** `zig build check` step + `pixi run zig-check` (2026-07-24):
      new `addCheckStep` in build.zig generates a synthetic "objdir" (a
      WriteFiles tree with `bin/R` wrapper + top-level `Makeconf` + stub
      `config.status` + subst'd `tests/Makefile` and
      `tests/Examples/Makefile`, srcdir pointed at the real source tree via
      a new `substFileTests` override) and runs `make -C .../tests
      test-Examples test-Specific test-Reg`. **Exit 0, zero real
      failures** — Examples for all 14 base packages, Specific (complex
      numbers, LAPACK, IEEE754, method dispatch), Reg (BLAS, S4, IO,
      encodings, plots) all green. Two cosmetic, non-zig diffs seen (both
      reproduce on any build, autoconf included — verified their root
      cause is unrelated to the compiler): reg-plot.pdf has ~0.05pt text-
      position drift (cairo/pango font-metrics version, not gated by
      R's own Rdiff — no `|| exit 1` on that comparison upstream); tools'
      examples emit one Rdiff "NOTE" because `system.file("doc",
      "grid.Rnw", package="grid")` resolves to "" — grid's shipped
      `inst/doc/` has no `.Rnw` source at all (only prebuilt PDFs), true
      of the R release tarball itself, nothing to do with the build.
      Deliberately NOT run: test-Internet (network, upstream itself
      `-@`-guards it), Packages/recommended (not built in slim),
      Embedding/Standalone (separate opt-in targets, out of scope for
      "check" parity).
- [x] **F2.1** config.h staleness guard + regeneration procedure in PLAN.md
      (2026-07-24): `GENERATED_FROM` + `checkConfigFreshness` in build.zig,
      verified it actually fires on a version mismatch and gives the
      regen steps; procedure documented in PLAN.md
- [x] **F2.2** SOURCE_DATE_EPOCH → reproducible (2026-07-24): `utcNow()`
      honors `SOURCE_DATE_EPOCH` instead of the wall clock; found and fixed
      two real leaks along the way — `gzip -9f` on grDevices' afm files
      embeds a timestamp in the gzip header (added `-n`), and R's own
      `tools:::.install_package_description()` calls `Sys.time()`
      internally unless given an explicit `builtStamp` argument (it has
      one *exactly* for this — "some build systems want to supply a
      package-build timestamp for reproducibility" — `mkdesc` in
      build.zig's bootstrap now passes `utcNow()` through it). Verified by
      building twice into the same prefix with a fixed `SOURCE_DATE_EPOCH`
      and `diff -rq`: went from ~130 differing files (mostly DESCRIPTION/
      Meta/package.rds/afm.gz) down to exactly 3 — `methods/R/methods.{rdb,rdx}`
      and `tools/help/tools.rdb`. Investigated (not just assumed): byte-
      level diffs are scattered mid-file with no clustering near a
      plausible timestamp offset, and `methods.rdb` differs in the
      majority of its bytes (995975/1355049) — consistent with R's own S4
      class/method registry using hash-table iteration order that isn't
      guaranteed stable across separate `loadNamespace("methods")` runs,
      not a wall-clock leak build.zig controls. Documented as a known,
      understood non-determinism (R-internals characteristic, not a
      zig-build defect) rather than chased further — matches
      FINALIZATION.md's own acceptance bar ("no differences except a
      documented, understood short list").
- [x] **F2.3** RUNPATH normalized (2026-07-24): new `fixRpath` helper in
      build.zig runs `patchelf --set-rpath` (via `--output`-free copy +
      rewrite, since it's inserted as a proper LazyPath-producing Run step)
      on every installed artifact (libR/libRblas/libRlapack, lapack.so/
      internet.so, bin/exec/R, bin/Rscript, all 9 package .so's, cairo.so),
      stripping zig's relative `build/zig-cache/local/o/<hash>` RUNPATH
      entries and keeping only the real absolute conda/flang-rt ones.
      Verified via `readelf -d` on every artifact category, then re-ran
      smoke + contract + zig-check — all still green.
- [x] **F2.4** bin/libtool: documented as dropped (2026-07-24) — F1.2's
      contract test is exactly the flow that would need it and doesn't
- [x] **F2.5** `zigbuild/tools/gen-subst.sh` committed (2026-07-24) —
      found and fixed a real join bug while writing it (see below)
- [x] **F3.1** full variant (2026-07-24): `-Dvariant=full` is a genuine
      second configure profile — `zigbuild/config/linux-x86_64-{slim,full}/`
      (moved slim's vendored config into its own `-slim` dir to make room;
      `gen-subst.sh` now writes `$PLAT-$VARIANT`). Captured full's config
      via a real `pixi run -e full configure` (216 config.h lines differ
      from slim, matching the ~108-line estimate in FINALIZATION.md).
      Every capability turned out to need less new linking than expected,
      because build.zig already compiles the same source files
      unconditionally and the *vendored, per-variant* config.h's
      `#ifdef`s are what actually change behavior — the real work was
      almost entirely finding the right link flags, not new compile logic:
      - **tcltk**: real `src/library/tcltk/src/{init,tcltk,tcltk_unix}.c`
        (new `pkg_libs` entry, `-Dvariant=full`-gated) linked against
        `TCLTK_LIBS`/`LIBM` from the vendored S-table (`-ltcl8.6 -ltk8.6
        -lX11 -lm`); R-code side needed a `concatRSourcesEx` (new
        `exclude` param on `concatRSources`) to pull real `R/*.R` +
        `R/unix/zzz.R` while skipping `zzzstub.R` — both live in the same
        directory and sort adjacently, so the generic glob-and-concat
        helper would have silently concatenated both (zzz.R's real
        `.onLoad` then getting clobbered by zzzstub's `stop()` one,
        since zzzstub.R sorts after zzz.R alphabetically). Verified with
        `library(tcltk); tclvalue(tclVar("hello"))` actually working
        end-to-end (Tk itself degrades gracefully without a DISPLAY, as
        expected headless).
      - **readline**: zero new compile-time logic — `src/unix/sys-std.c`
        etc. already had `#ifdef HAVE_LIBREADLINE` branches compiled from
        the same source; only needed `-lreadline` added to `libR`'s link
        when full (`linkCoreLibs`).
      - **NLS**: zero new linking at all — `LIBINTL`/`INTLLIBS` are empty
        in the vendored S-table (glibc provides `gettext()` natively on
        Linux, no separate libintl), and the `.mo` catalogs are
        pre-compiled and shipped in the tarball under
        `src/library/translations/inst/` (no `msgfmt` step needed),
        already staged unconditionally by `installStaticTree` for every
        variant. `ENABLE_NLS` in config.h is the entire mechanism.
      - **jpeg/tiff**: `rbitmap.c` (already compiled into `cairo_mod` for
        every variant) has direct `#ifdef HAVE_JPEG`/`HAVE_TIFF` calls
        into `jpeglib.h`/`tiffio.h` — needed `BITMAP_LIBS` (`-ltiff
        -ljpeg -lpng16`) applied to `cairo_mod`'s link line only for full
        (slim's `BITMAP_LIBS` is just `-lpng16`, already covered via
        `CAIRO_LIBS`, so applying it unconditionally would just be a
        harmless redundant `-lpng16`, but full's needs the real flags).
      Acceptance, all verified: `pixi run -e full zig-build` → smoke
      asserts the full profile (tcltk/jpeg/tiff/NLS **TRUE**, matching the
      capabilities() output exactly) → `pixi run -e full contract` → `pixi
      run -e full zig-check`, all green, zero regressions on slim
      (re-verified after every change).
- [x] **F3.2** openblas flavor (2026-07-24): `-Dblas=openblas` build
      option, orthogonal to `-Dvariant` — a pure link-time swap, not a
      separate vendored config (R's C code calls BLAS/LAPACK through a
      fixed Fortran-callable ABI regardless of implementation, so no
      config.h difference is needed). `ctx.rblas`/`ctx.rlapack` are now
      `?*std.Build.Step.Compile` (null for openblas); new `Ctx.linkBlas`/
      `Ctx.linkLapack` helpers pick internal-libRblas/libRlapack vs
      `-lopenblas` at every call site (libR, bin/exec/R, modules/lapack.so,
      library/stats). openblas skips compiling the reference BLAS/LAPACK
      Fortran entirely (noticeably faster build) and installs no
      libRblas.so/libRlapack.so. Verified `pixi run -e openblas zig-build`
      → smoke (`sessionInfo()$BLAS` correctly resolves the real
      `libopenblasp-r0.3.34.so`, not a hardcoded string) → contract →
      zig-check, all green on the first real attempt; re-verified slim
      (internal BLAS) has zero regressions after the refactor.
- [x] **F4.1** stage.sh/package/verify-bundle green on zig prefix
      (2026-07-24): all three scripts ran completely unchanged against the
      zig-built prefix via the existing `R_INSTALL_PREFIX` override
      (`scripts/env.sh` already derives `PREFIX`/`R_HOME_DIR` from it —
      the same mechanism `R_TEST_R_BIN` uses for smoke/contract). One real
      gotcha, not a build.zig bug: `zig-build.sh`'s default prefix is
      `dist/R-<ver>-<flavor>-zig` (the `-zig` suffix that lets it coexist
      with an autoconf build of the same flavor), but
      `package-standalone.sh`'s final `tar -C "$ROOT/dist" "R-$R_VERSION-
      $FLAVOR"` hardcodes the *directory's basename* to match — it doesn't
      go through `$PREFIX`, so a `-zig`-suffixed prefix produces "tar:
      R-4.6.1-slim: Cannot stat: No such file or directory". Not a bug to
      fix now (the suffix is exactly the transitional coexistence
      mechanism these scripts don't need to know about); worked around by
      pointing `R_INSTALL_PREFIX` at the unsuffixed name for this
      verification pass. Once the zig path retires autoconf (the "Final"
      item below), dropping the suffix makes this a non-issue permanently.
      Ran the full adversarial standard beyond `verify-bundle.sh`'s own
      (solve + capabilities) check: extracted the packaged tarball to a
      fresh `/tmp` dir, **deleted the original** staged tree, then with
      `env -i PATH=/usr/bin:/bin` (no conda env, no pixi) verified `print
      (base::Sys.which)` shows the dynamic `R.home()`-relative expression
      (the canonical tell), `library(utils)` loads, and a real cairo PNG
      renders. `R CMD SHLIB` on a fresh `.c` file correctly fails with
      `zig` off PATH (documented, deliberate: package compilation needs
      zig, the one external-tool contract — never vendored) and
      succeeds — compiling, `dyn.load`, and `.Call` all correct — once
      zig's directory alone is added back to the otherwise-scrubbed PATH.
- [x] **F4.2** CI `zig-build` leg (2026-07-24): new `build-zig` job in
      `.github/workflows/build.yml`, matrixed over `default`/`full`/
      `openblas` on ubuntu-latest, beside (not replacing) the autoconf
      `build` job. Runs `zig-build` → `zig-smoke` → `zig-contract` →
      `zig-check`. Two new tiny pixi tasks/scripts (`zig-smoke`,
      `zig-contract`, mirroring `scripts/zig-build.sh`'s own prefix
      derivation via `env.sh`'s `$FLAVOR`) so the workflow doesn't need to
      compute the `dist/R-<ver>-<flavor>-zig` path itself — same pattern
      `zig-build`/`zig-check` already established. Verified all three new
      tasks work locally (`pixi run zig-smoke`, `pixi run zig-contract`);
      the workflow YAML itself validated (`yaml.safe_load`) but **not
      observed running on an actual GitHub Actions runner** — this
      session has no way to push/trigger CI, so treat the job definition
      as reviewed-and-locally-equivalent, not CI-green, until it runs for
      real on the next push.
- [x] **F5.1** macOS compile graph (2026-07-27, on omicron/osx-arm64):
      gfortran (not flang, unavailable on macOS) with `-J` for the module
      dir (flang's `-module-dir` doesn't exist in gfortran) and `-O1` cap
      (matches configure-r.sh's known gfortran-darwin miscompile
      workaround); FLIBS-driven Fortran runtime linking instead of the
      linux flang_rt.a search; `zigbuild/config/osx-arm64-{slim,full}/`
      vendored from real `pixi run [-e full] configure` runs on omicron;
      `platform`/`config_dir` now computed at runtime from
      `ctx.target`'s os/arch instead of a hardcoded linux constant;
      `linkCoreLibs`'s LIBS now comes from the vendored S-table instead of
      a hand-written array (a hardcoded `-lrt` would have broken macOS —
      no separate librt there). All three flavors (slim/full/openblas)
      built and passed smoke+contract+zig-check on the first or second
      real attempt. Two real bugs found getting `full` working (both
      documented below): the base-package link needing
      `linker_allow_shlib_undefined` (zig's Mach-O equivalent of ELF's
      undefined-shlib-symbol tolerance), and a missing `LIBINTL`/
      `-framework` link that crashed R at startup.
- [x] **F5.2** macOS Mach-O relocation + ad-hoc codesign (2026-07-27):
      `stage.sh`/`package-standalone.sh`/`verify-bundle.sh` ran completely
      unchanged (dual `@loader_path` rpaths + ad-hoc codesign, from
      milestone 2's existing macOS support). `fixRpath` (the ELF-only
      patchelf F2.3 fix) is a no-op passthrough on macOS per
      FINALIZATION.md's own guidance — leaves all Mach-O rpath/codesign
      surgery to stage.sh rather than duplicating it in build.zig. Ran the
      full adversarial standard beyond `verify-bundle.sh`'s own check
      (same as F4.1 on linux): extracted to a fresh dir, deleted the
      original, `env -i PATH=/usr/bin:/bin` confirmed the dynamic
      `Sys.which` tell, `library(utils)`, a real cairo PNG render, and
      `R CMD SHLIB` + `dyn.load`/`.Call` (correctly failing without zig on
      PATH, succeeding once its dir is added back).
- [x] **F6.0** scoping decision (2026-07-27): CLI/headless only — build
      `R.dll`/`Rblas.dll`/`Rlapack.dll`/`Rgraphapp.dll`/`Riconv.dll`/
      `Rscript.exe`, skip `Rgui.exe`/`Rterm.exe`/`R.exe`/`Rcmd.exe`/
      `RSetReg.exe`/`open.exe` entirely. Verified (not assumed) against
      kappa's real gnuwin32 checkout: smoke/contract only ever invoke
      `Rscript.exe`; package builds go through R-level
      `tools:::.install_packages()`, not a compiled `Rcmd.exe`.
      `Rgraphapp.dll` turned out to be a genuine required *link-time* dep
      of `R.dll` itself (`R-DLLLIBS` in `src/gnuwin32/Makefile`), not
      prunable GUI-only plumbing — see FINALIZATION.md F6.0 for the full
      trace (R.dll's own `CSOURCES` bakes in console.c/rui.c/etc as
      required compile units; only the separate front-end *executables*
      are droppable, not R.dll's dependency graph).
- [x] **F6.1** Windows compile graph (2026-07-27): `zig build` on kappa
      produces R.dll/Rblas.dll/Rlapack.dll/Rgraphapp.dll/Riconv.dll/
      lapack.dll/Rscript.exe; `Rscript.exe --version` runs correctly
      (proves the full runtime DLL dependency chain loads, not just
      links). See FINALIZATION.md F6.1 for the full gotcha catalog
      (include-path shadowing, conda lib naming, missing Windows-only
      sources, libintl.h vs libgnuintl.h, mod_lapack needing libR, and
      the libgcc_s_seh-1.dll runtime-symbol saga resolved via a
      dlltool-generated import lib).
- [x] **F6.2** Windows layout + bootstrap (2026-07-27): `zig build` on
      kappa produces a complete, working Windows R — `Rscript.exe -e
      "cat(1+1, R.version.string)"` runs with completely default flags
      and evaluates real R code, exit 0. library/ staging, the full
      R-level bootstrap (base package lazy-loading, DESCRIPTION/NAMESPACE
      installation, metadata caches, docs), and 9 base-package DLLs
      (tools/grDevices/utils/graphics/stats/methods/grid/splines/parallel)
      all build and load correctly. See FINALIZATION.md F6.2 for the full
      gotcha catalog — an `R_ARCH` macro needed in two separate compile
      groups (system.c's R_HOME `dirstrip` computation AND platform.c's
      `.Platform$r_arch`), Windows-native backslash paths breaking R code
      string literals, per-package Windows source-list differences
      (parallel's ncpus.c, grDevices' devWindows.c/winbitmap.c, utils'
      windows/*.c), a genuine cross-DLL symbol collision (loadRconsole),
      and the final blocker — a silent `exit(10)` traced to `rterm.c`'s
      unconditional `readconsolecfg()` call failing to find a missing
      `etc/Rconsole` (fixed by vendoring gnuwin32's own static copy).
      Also corrects F6.0: `Rterm.exe` is not GUI-only after all and IS now
      built (needed for `Boot.r()`'s bootstrap invocations).
      Still deferred (not needed by anything hit so far): full `etc/`
      (package-compilation contract), `tcltk`'s real Tcl/Tk linking,
      `ICU_PATH`, `winCairo.dll`.
- [x] **F6.3** Windows capability-profile gaps found + fixed (2026-07-28):
      F6.2's own "Rscript.exe -e evaluates real R code" acceptance bar
      never actually ran the *full* `smoke-test.sh` capability-profile
      assertions to completion on Windows — doing so for real (as prep for
      retiring the legacy default path, below) found `capabilities()`
      genuinely FALSE for `libcurl`/`ICU`/`cairo`, none of which were on
      F6.2's own "still deferred" list except `winCairo.dll`. All three
      fixed and verified on kappa (`pixi run zig-smoke`/`zig-contract`/
      `stage.sh`/`package-standalone.sh`/`verify-bundle.sh` all green):
      - **libcurl** (`modules/internet.dll` didn't exist at all): added,
        mirroring unix's `mod_internet` — same `rspec.internet_c` source
        list, links `-lR -lRgraphapp -lwininet -lws2_32 -llibcurl` (ground
        truth from `src/modules/internet/Makefile.win`); needed the same
        `src/gnuwin32/fixed/h` include path as `r_core_mod` for
        `psignal.h`. Separately, `capabilities()$libcurl` turned out to be
        a **pure compile-time `#ifdef HAVE_LIBCURL` check in `platform.c`**
        (`src/main/platform.c`'s `do_capabilities`) — completely
        independent of whether `internet.dll` exists at runtime; fixed by
        defining `HAVE_CURL_CURL_H`/`HAVE_LIBCURL` in the vendored Windows
        `config.h` (gnuwin32's own static `fixed/h/config.h` ships these
        commented out, since its real build sets them via per-Makefile.win
        `-D` flags from `MkRules`, which this project has no subst table
        to source centrally — defining them once in the vendored config.h,
        already included via `HAVE_CONFIG_H` everywhere, reproduces the
        same effective behavior).
      - **ICU**: same class of bug — `USE_ICU` was commented out in the
        vendored `config.h` (copied verbatim from gnuwin32's static
        `fixed/h/config.h`, whose real build instead flips it via
        `MkRules`' `USE_ICU ?= YES` default plus per-Makefile `-D` flags).
        Fixed by defining `USE_ICU 1` directly in the vendored config.h
        (`platform.c`/`util.c`/`registryTZ.c` — all three already compiled
        into `r_core_mod`/`win_tzone_c`, no new sources needed) plus
        linking `icuin`/`icuuc`/`icudt` (ICU4C's Windows component names,
        `icuin` not unix's `icui18n`; no lib-prefix quirk this time) into
        R.dll's own link list.
      - **cairo** (`capabilities()$cairo` on Windows is `stat()`-based —
        `platform.c` checks whether `library/grDevices/libs/x64/
        winCairo.dll` exists on disk, not a compile-time macro): built it
        for real. Ground truth from gnuwin32's own
        `src/library/grDevices/src/cairo/Makefile.win`: **one** source
        (`cairoBM.c`, not unix's `cairoBM.c`+`rbitmap.c` pair — Windows
        already compiles `winbitmap.c` straight into `grDevices.dll`
        itself), linked against `grDevices.dll` (`-lgrDevices`) plus
        `cairo`/`fontconfig` (the exact literal flags
        `scripts/build-gnuwin32.sh`'s own live `$CONDA_PREFIX` patch
        already uses for the legacy path: `-lcairo -lfontconfig`).
        Needed `linkLibrary(libR)` too, *in addition to* the grDevices
        import lib — gnuwin32's real link line is `-lgrDevices` alone,
        relying on gcc's transitive DLL relinking, which lld-link does not
        replicate (found via a real ~80-symbol undefined-R-API-symbol
        link error). Required plumbing a `grdevices_lib` reference out of
        the grDevices package block and a new `win_cairo` parameter into
        `installLibraryWindows` (winCairo.dll isn't a per-package DLL —
        it's an extra file dropped into grDevices' own `libs/x64/` dir).
      - Ground truth for all three was pulled from kappa's OTHER, already-
        working gnuwin32 checkout (`~/r-zig-pixi/build/R-4.6.1`, milestone
        3's objdir — same source F6.1a used), via its real Makefile.win
        files and a real `capabilities()` call — same "extract from a
        known-good build rather than reverse-engineer gnuwin32's Makefile
        system" methodology as F6.1a.
      - Also found and fixed a real, independent bug while verifying the
        packaging chain against these fixes: **`package-standalone.sh`/
        `verify-bundle.sh` hardcoded the archive's top-level directory
        name as `R-$R_VERSION-$FLAVOR`**, silently producing an empty
        zip/tar (`zip error: Nothing to do!` / `tar: ...: No such file or
        directory`) whenever `$PREFIX`'s actual basename didn't match
        exactly — which every zig-built prefix's `-zig` suffix guarantees.
        This is the same gap F4.1 already documented and worked around
        per-invocation (pointing `R_INSTALL_PREFIX` at the unsuffixed
        name); fixed at the source instead, now that `zig-package`/
        `zig-verify-package` are first-class default tasks: both scripts
        now derive the archive's directory name from `$(basename
        "$PREFIX")` rather than a hardcoded string. Verified on both
        linux (existing prefix) and kappa (against the real `-zig`-suffixed
        prefix directly, no more manual workaround).
- [x] **F7** Windows package-compilation contract (2026-07-28, on kappa) —
      the last item FINALIZATION.md's original spec left explicitly
      deferred ("Makeconf.win wiring... not required for the CLI-only,
      headless R this milestone targets"). Done anyway, on direct request
      after F7.0-F6.3 wrapped up: `pixi run contract` now passes on
      Windows exactly like linux/macOS — Rcpp (C++), data.table (C +
      OpenMP), and minqa (Rcpp + Fortran) all compile and run correctly
      through the zig/gfortran toolchain via `install.packages(type=
      "source")`. Three real, non-obvious blockers found and fixed, each
      via the same "reproduce narrowly, read the real R/gnuwin32 source,
      fix root cause, re-verify on kappa" discipline as every prior phase:
      - **R's own Windows `system()`/`CreateProcess` call can NEVER find a
        bash-script "gcc"/"g++" shim, no matter where it sits or how it's
        referenced.** `do_system` (`src/gnuwin32/sys-win32.c`) →
        `runcmd_timeout` → `pcreate` → `CreateProcess(NULL, cmd, ...)` —
        with `lpApplicationName` NULL, Win32 only ever auto-appends
        `.exe` to a bare command name; it does NOT consult `PATHEXT` the
        way `cmd.exe` does, so a `.bat` wrapper is equally invisible.
        Confirmed empirically before writing any fix: `system("gcc
        --version")` against the EXISTING `win-toolchain` shim dir (the
        legacy gnuwin32 build's own, already-proven-for-building-R-itself
        mechanism, contract-test.sh's Windows branch already PATH-
        prepends it) silently resolved to conda-forge's own unrelated
        `gcc.exe` elsewhere on PATH instead — meaning **package
        compilation on Windows had never actually exercised zig at all,
        on the legacy gnuwin32 build either** (same bare `CC =
        $(BINPREF)$(CCBASE)` line, `BINPREF` empty). Fixed with a real
        native PE forwarder: `zigbuild/tools/win-exec-forward.c` (a ~20-
        line C program, `_spawnv`-forwarding argv to the existing
        `toolchain/zig-cc`/`zig-cxx` bash scripts unmodified) compiled by
        build.zig itself into `gcc.exe`/`g++.exe` (`winCompilerWrapper` in
        build.zig) — verified the mechanism in complete isolation on
        kappa (a standalone test wrapper forwarding to a bash echo
        script, then to the real `zig-cc`, compiling and running a
        trivial `hello.c`) before wiring it into the real build.
      - **`install.packages(type="source")` hard-requires a real,
        compiled `R.exe`, contradicting F6.0's original "not needed,
        `tools:::.install_packages()` is R-level" finding.** That finding
        checked what `smoke`/`contract`*invoke directly* (only ever
        `Rscript.exe`) but missed that `utils::install.packages()` itself
        (`src/library/utils/R/packages2.R`) hardcodes `cmd0 <-
        file.path(R.home("bin"), "R")` unconditionally, for both the
        serial and `Ncpus>1` parallel-Makefile install paths — without a
        real `bin/x64/R.exe`, package installation fails immediately
        ("No such file or directory"), before the toolchain even matters.
        Rather than reimplement `rcmdfn.c`'s ~15-subcommand CMD dispatch
        (INSTALL/SHLIB/REMOVE/build/check/...) from scratch, compiled the
        REAL gnuwin32 sources instead (`front-ends/R.c` + `rcmdfn.c` +
        `src/main/Renviron.c` with `-DRENVIRON_WIN32_STANDALONE`, minus
        the icon/manifest resource — same "no icon resource" precedent as
        Rterm.exe) — reading `rcmdfn.c` directly showed every subcommand
        is itself just a templated `Rterm.exe -e tools:::.foo() ...
        --args ...` string it re-execs, so the real logic already lives
        in R code this build has, not C to duplicate. `rhome.c`/`shext.c`
        (R_HOME/RUser helpers `rcmdfn.c` needs) are NOT recompiled here —
        they're already part of `R.dll`'s own `win_gnuwin32_c` group;
        doing so again produced real "duplicate symbol: getRHOME" link
        errors (zig/lld-link exports every public DLL symbol by default,
        same class of issue as F6.2's `loadRconsole` collision) — fixed
        by linking `libR` instead and letting its exports satisfy them.
      - **Real `BINDIR`/`IMPDIR` values needed correcting against ground
        truth, not guessed.** First attempt used `-DBINDIR="x64"`,
        producing a silent, generic "The system cannot find the path
        specified" from `R.exe`'s own `system(cmd)` call launching
        Rterm.exe — traced (not guessed) by manually reproducing the
        exact quoted command string via `cmd.exe` directly, then a
        `Test-Path` check on the constructed path, which was missing a
        `bin/` segment entirely. Real gnuwin32 value (confirmed against a
        real generated Makeconf on kappa's milestone-3 objdir):
        `BINDIR=bin$(R_ARCH)` = `"bin/x64"`, not just `"x64"`. The
        vendored `Makeconf.win` template's own `IMPDIR = bin` (used by
        `LIBR`/`BLAS_LIBS`/`LAPACK_LIBS` to find R.dll/Rblas.dll/
        Rlapack.dll) has the identical gap — real value is `bin/x64`
        too, found via a real "unable to find dynamic system library 'R'"
        link error once BINDIR was already fixed.
      - **`LDFLAGS` is empty in both the vendored template AND a real
        generated Makeconf** — gnuwin32 provides external-library search
        paths via `MkRules.local`'s `LOCAL_SOFT`, sourced only when
        building R itself, not for package builds afterward. CRAN
        packages routinely link bare `-lz`/`-lpng`/etc. expecting *some*
        global search path to exist regardless (found via a real "unable
        to find dynamic system library 'z'" link error compiling
        data.table) — fixed by setting `LDFLAGS = -L"<conda>/Library/lib"`
        directly in the installed Makeconf, since there's no
        `MkRules.local`-equivalent mechanism for package builds to source
        it from otherwise.
      - **`gfortran.exe` cannot be relocated/copied — it locates its own
        `f951` backend relative to its own original install path.**
        Copying it into the `BINPREF` toolchain dir (matching `gcc.exe`/
        `g++.exe`'s own treatment) broke it: "cannot execute 'f951':
        CreateProcess: No such file or directory" compiling minqa's
        Fortran. Fixed by pointing `FC` at the conda env's *original*
        `gfortran.exe` path directly, bypassing `BINPREF` for that one
        variable — the exact same absolute location `fortranOne`'s own
        bare `"gfortran"` PATH lookup already resolves to successfully
        when building R itself.
      CI: `build-windows` job in `build.yml` now runs the `contract` step
      too (previously build+smoke+verify-package only).
- [x] **Bug found by the conda-package republish (2026-07-28, real build.zig
      fix)**: `ctx.prefix` (`b.install_prefix`) was never normalized to
      forward slashes, unlike `src_abs`, which already got this exact fix
      under F6.2 (Windows-native backslash paths breaking R code string
      literals). Never hit on a normal `zig build` invocation by
      coincidence — surfaced only via `.github/devdocs/feat-prefix-
      publish/TODO.md`'s rattler-build sandbox work, where a short
      `--output-dir` workaround (for an unrelated `dlltool` path-length
      limit) produced a host-env directory literally named `h_env`, and
      `\h` is not a valid R escape sequence at all. For *other* letters
      forming a **valid** (but wrong) R escape (`\n`/`\t`/`\r`/...) this
      could have been silently corrupting paths instead of erroring,
      undetected, in any Windows build whose install prefix happened to
      contain one of those sequences. Fixed by normalizing
      `b.install_prefix` once, at the same point `ctx.prefix`/`ctx.rhome`
      are derived from it — see feat-prefix-publish's TODO.md for the
      full incident writeup (recipe.yaml/rattler-build side of the story).
      Re-verified zero regression on linux.
- [x] **Final**: retire autoconf/gnuwin32 from the default path (2026-07-28)
      — F1-F6 (+F6.3 above) all green on linux/macOS/Windows. `pixi run
      build`/`install`/`package`/`verify-package`/`smoke`/`contract`/
      `check` now run the zig pipeline (the old `zig-*`-prefixed task
      names are gone, folded into the bare names); the old autoconf
      (unix)/gnuwin32 (windows) pipeline is kept as an explicit `*-legacy`
      fallback (`build-legacy`, `smoke-legacy`, etc.) for one release, per
      this item's own original plan, then removable. `check`/`contract`
      have no zig-Windows equivalent (see F6.3 above and F6.1/F6.2's own
      scope) — `pixi run check`/`contract` are unix-only on the new
      default path; Windows keeps `check-legacy`/`contract-legacy` as its
      only regression-suite/package-contract coverage until Windows'
      package-compilation contract (Makeconf.win) is done. `.github/
      workflows/build.yml`: renamed `build`→`build-legacy`, `build-zig`→
      `build` (added a Windows leg, build+smoke+package/verify only, no
      check/contract), `build-windows`→`build-windows-legacy`.
      `recipe/build.sh` (the real rattler-build release pipeline) now
      calls `zig-build.sh` + `stage.sh` instead of `configure-r.sh`/
      `build-r.sh`/`install-r.sh` — verified with a real `pixi run -e pkg
      conda-package` run (not just read through), which took 5 real
      attempts to go green and found genuine `recipe.yaml` gaps the old
      autoconf-driven recipe never hit (rattler-build's split
      build_env/host_env sandbox behaves differently from a single unified
      pixi dev env — see "Bugs found switching `recipe/build.sh` to zig"
      below for the four real, root-caused fixes: `harfbuzz`, `unzip`/
      `gzip`/`tar`/`zip`, and `which`/`sed`/`grep` all missing from
      `host:`).
      New wrapper scripts `scripts/zig-stage.sh`/`zig-package.sh`/
      `zig-verify-package.sh` (mirroring `zig-smoke.sh`'s own prefix-
      derivation pattern) back the new `install`/`package`/
      `verify-package` tasks — no `zig-install`/`zig-package`/
      `zig-verify` equivalents existed before this. Along the way, fixed a
      real, independent bug in `package-standalone.sh`/`verify-bundle.sh`
      themselves (not recipe-specific): both hardcoded the packaged
      archive's top-level directory name as `R-$R_VERSION-$FLAVOR`,
      silently producing an empty zip/tar whenever `$PREFIX`'s actual
      basename didn't match exactly — the same gap F4.1 already documented
      and worked around per-invocation; fixed at the source now that
      `zig-package`/`zig-verify-package` are first-class default tasks (see
      F6.3 above for the full detail — found there first, on kappa, before
      recipe verification even started).

### Bugs found switching `recipe/build.sh` to zig (real, all in
`recipe/recipe.yaml`, fixed 2026-07-28 — found via 5 real
`pixi run -e pkg conda-package` attempts, each fixed and re-verified)

`recipe.yaml`'s `host:`/`build:` dependency lists were written against the
old autoconf-driven `recipe/build.sh`, which never exercised these gaps —
either because `./configure`'s real feature detection degraded gracefully
(cairo) or because it resolved tools via a plain `$PATH` search that
happens to include both rattler-build's `$BUILD_PREFIX/bin` and
`$PREFIX/bin` inside a build script, unlike this project's own
vendored-config-replay design (`@ZR_CONDA@`-style subst placeholders,
resolved from `ctx.conda`/`$CONDA_PREFIX` — a single directory, set by
`recipe/build.sh` to rattler's host `$PREFIX`, not `$BUILD_PREFIX`).
Every fix below is the same root shape: something the old path never
needed as an explicit `host:` (not just `build:`) dependency, because a
plain `$PATH` search would have found it in `$BUILD_PREFIX` regardless of
which env variable pointed where.

- **`harfbuzz` headers.** `hb.h` not found compiling `pango-coverage.h`
  (pulled in by the cairo module's `CAIRO_CPPFLAGS`, which zig-build.sh
  compiles unconditionally — the equivalent pixi.toml dev env never hit
  this because something else in its much larger dependency graph happens
  to pull `libharfbuzz-devel`'s headers in transitively too, but
  recipe.yaml's narrower host list didn't). Fixed: added `harfbuzz` to
  `host:`.
- **`unzip`/`gzip`/`tar`/`zip` missing entirely from the unix `build:`
  list** — the old autoconf path apparently never invoked these inside
  the sandbox (or was never exercised there); `build.zig` shells out to
  `unzip` directly for `share/zoneinfo` and `gzip` for grDevices' afm
  compression. Fixed: added all four (matching `pixi.toml`'s own
  `[target.unix.dependencies]` set this recipe otherwise mirrors) to
  `build:`.
- **`which` (then `sed`, then proactively `grep`) missing from `host:`.**
  The deepest and most interesting bug: `@WHICH@`/`@SED@`/`@GREP@` in the
  vendored subst table are `"@ZR_CONDA@/bin/<tool>"` — an *absolute path*
  baked into R's own `Sys.which()` fallback and `bin/R`'s `SED=`/`GREP=`
  variables at build time, resolved from `ctx.conda` (`$CONDA_PREFIX`).
  `recipe/build.sh` sets `$CONDA_PREFIX="$PREFIX"` (the host env, matching
  what R needs at *runtime* after install) — but `which`/`sed`/`grep` were
  only `build:` dependencies, living in `$BUILD_PREFIX/bin`, not
  `$PREFIX/bin`. The old autoconf path never hit this because
  `AC_PATH_PROG`-style detection searches `$PATH` (which includes both
  envs inside a rattler-build script) and bakes in whatever it *finds*,
  which happens to work at configure time regardless of which prefix
  variable was set to what. First surfaced as `library(utils)`'s
  `.onLoad` failing (`Sys.which()` calling a nonexistent binary), fixed
  for `which`, rebuilt, then hit the identical failure one bootstrap step
  later for `sed` (`bin/R: line 195: $PREFIX/bin/sed: No such file or
  directory`) — fixed, and `grep` added proactively in the same pass
  (identical `@ZR_CONDA@/bin/grep[-flags]` pattern in `EGREP`/`FGREP`/
  `GREP`, not yet hit by a real failure but the same bug waiting to
  happen) rather than doing a fifth round trip just to rediscover it.
  `AWK="gawk"` (no baked absolute path, `$PATH`-resolved) isn't affected.
  Unix-only fix — this whole subst-table mechanism belongs to
  `installStaticTree`/`mkRbase`, which `buildWindows()` never uses (no
  `bin/R` front script on Windows, per F6.0).

### Bugs found by F1.2 (real, both in `loadSubstTable`/build.zig, fixed 2026-07-24)

- **`AC_SUBST_FILE` vars silently vendored empty.** `r_cc_rules_frag`,
  `r_cxx_rules_frag`, `r_objc_rules_frag` are config.status *file-content*
  substitutions (configure writes `Makefrag.cc`/`.cxx`/`.m` and inlines
  their contents), not normal `S["VAR"]="value"` entries — subst.txt never
  had them, so `@r_cc_rules_frag@` etc. leaked into `etc/Makeconf` as
  literal text, and make died with "missing separator" on line 189 (no
  colon, no leading tab) the moment any package tried to compile. Fixed by
  hardcoding the fragment content in `loadSubstTable` (it's fixed shell
  heredoc text in `configure`, `-M`-based since zig cc/zig c++ both support
  `-M` — verified directly). Same class of gap would hit any other
  `AC_SUBST_FILE` var if one is ever added upstream — grep `ac_subst_files`
  in `configure` to check.
- **Awk string-escape underdecoding: `\"` never unescaped.** `subst.txt`
  values that legitimately contain a literal `"` (e.g. `R_INCLUDES=-I\"$(R_INCLUDE_DIR)\"`,
  `LIBR0`, `LAPACK_LIBS`, `BLAS_LIBS`) kept the backslash in Makeconf
  (`-I\"$(R_INCLUDE_DIR)\"`), so the shell passed `\"` literally to the
  compiler instead of a quoted path — `'R.h' file not found` (the quote
  chars, not the path, were the broken part; the path itself was correct).
  `loadSubstTable` only unescaped `\$` → `$`. Fixed by also unescaping
  `\"` → `"` (confirmed no vendored value contains a literal `\\`, so the
  unescape order isn't ambiguous — checked before assuming it's safe).

### Bug found by F2.5 (`zigbuild/tools/gen-subst.sh`, fixed 2026-07-24)

- **Continuation-line join left a stray quote mid-token.** config.status
  wraps long `S["VAR"]="..."` values across physical lines by ending the
  line in `"\` and starting the next in `"` (e.g. `-lrt -ldl -l"\` then
  `"m -liconv..."` — reassembling to `-lrt -ldl -lm -liconv...`). The
  first version of the join `sub(/"\\$/, "\"", full)` *kept* the quote
  instead of removing it, producing a literal `-l"m` (and, worse, many
  stray mid-string quotes in longer multi-continuation values like
  `CAIRO_CPPFLAGS`, silently truncating everything after the first
  reinserted quote when later fed through `@VAR@` substitution). Caught by
  regenerating `subst.txt` for real and grepping the output for embedded
  `"` characters before trusting it — fixed by removing both the trailing
  `"` and `\` (`sub(/"\\$/, "", full)`), then re-verified smoke + contract
  + zig-check all still green against a full rebuild with the regenerated
  file.

### Bugs found by F5.1 (macOS port, fixed 2026-07-27, on omicron/osx-arm64)

- **Base packages segfault-free on linux but fail link with "undefined
  symbol" on macOS.** `library/*/libs/*.so` and modules never
  `.linkLibrary(ctx.libR)` — their R-API symbols resolve at runtime since
  libR is already loaded into the process ("zig allows undefined symbols
  in shared libs" on ELF, verified in F1/PLAN.md). Mach-O's lld does NOT
  tolerate that by default; the real make build's Makeconf carries
  `-undefined dynamic_lookup` on every `SHLIB_LDFLAGS`/`DYLIB_LDFLAGS` for
  exactly this. Fixed with a new `addSharedLib` helper (wraps every
  `b.addLibrary` call site, 16 of them) that sets zig's
  `linker_allow_shlib_undefined = true` on macOS — the equivalent knob,
  not anticipated in FINALIZATION.md's spec, found from the first real
  build attempt's error output.
- **`full` variant builds clean but segfaults (SIGSEGV, null function
  pointer) on the very first bootstrap R invocation.** Root cause chain:
  macOS's libc has *no* native `gettext()` (unlike glibc, which is why
  linux's `LIBINTL` is empty and needs no extra link) — macOS's vendored
  S-table has a real `LIBINTL="-lintl -Wl,-framework -Wl,CoreFoundation"`
  that `linkCoreLibs` wasn't applying at all. Compounded by the
  `linker_allow_shlib_undefined` fix above: it let the *missing* gettext
  symbols link successfully anyway (silently), so the crash only
  surfaced at runtime, as a call through a null pointer, the instant R's
  startup code invoked `_()` (gettext) for the first time — traced via
  macOS's own crash reporter (`~/Library/Logs/DiagnosticReports/*.ips`,
  a JSON body after a one-line header) since `lldb` refuses to attach in
  a non-interactive SSH session. Fixed two things: (1) `linkCoreLibs` now
  applies `LIBINTL` from the S-table (empty/no-op on linux and macOS
  slim, real on macOS full); (2) `applyLinkFlags`'s tokenizer silently
  *dropped* `-framework X` pairs entirely (it only recognized `-L`/`-l`
  prefixes) — added explicit handling via zig's `Module.linkFramework`.
  The second bug was latent and harmless until the first one needed it
  (cairo's own `CAIRO_LIBS` also carries several `-framework`s that were
  silently no-ops before this fix — undetected because slim's cairo
  happened to work anyway via transitively-linked frameworks).

## Later (explicitly out of scope for this branch)

- [x] Contract test (Rcpp/data.table) against zig-built R — etc/Makeconf
      shim contract must hold (2026-07-24, see F1.2 above)
- [x] `make check` (R regression suite) parity vs the autoconf build
      (2026-07-24, see F1.1 above — Phase F1, the finalization trust bar,
      is now fully green)
- [x] full variant (-Dvariant=full): tcltk/readline/NLS/jpeg/tiff
      (2026-07-24, see F3.1 above)
- [x] openblas flavor (-Dblas=openblas) (2026-07-24, see F3.2 above)
- [x] macOS (gfortran table entry, Mach-O/codesign handling in zig build)
      (2026-07-27, on omicron — see F5.1/F5.2 above)
- [x] Windows (replaces gnuwin32 as the default — the big prize) — F6
      (2026-07-27/28, on kappa — see F6.0-F6.3 above and the Final item)
- [ ] `zig build fetch` (retire fetch-r.sh) — not attempted; still a real
      gap, low priority (fetch-r.sh is a one-line curl+checksum, no
      correctness risk in leaving it as-is)
- [x] config.h regeneration procedure doc + version-mismatch guard
      (2026-07-24, see F2.1 above)
- [x] Wire `pixi run zig-build` into CI next to the autoconf path
      (2026-07-24, see F4.2 above — `build-zig` job in build.yml; not yet
      confirmed on a real Actions run). Autoconf/gnuwin32 still retire only
      after F1-F6 are green on all platforms (F5/F6 remain).
