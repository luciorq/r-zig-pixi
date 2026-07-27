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
- [ ] **F5.1** macOS compile graph (gfortran, -O1 cap, vendored osx config,
      fd ulimit)
- [ ] **F5.2** macOS Mach-O relocation + ad-hoc codesign; omicron green
- [ ] **F6.1** Windows compile graph (MinGW gfortran, ld-emulation
      decision, Windows config table)
- [ ] **F6.2** Windows layout (`Library/lib/R`, ICU_PATH) + traps; kappa
      green
- [ ] **Final**: retire autoconf/gnuwin32 from the default path once all
      six phases green on all platforms; keep them as a fallback one
      release, then remove

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

## Later (explicitly out of scope for this branch)

- [x] Contract test (Rcpp/data.table) against zig-built R — etc/Makeconf
      shim contract must hold (2026-07-24, see F1.2 above)
- [x] `make check` (R regression suite) parity vs the autoconf build
      (2026-07-24, see F1.1 above — Phase F1, the finalization trust bar,
      is now fully green)
- [x] full variant (-Dvariant=full): tcltk/readline/NLS/jpeg/tiff
      (2026-07-24, see F3.1 above)
- [x] openblas flavor (-Dblas=openblas) (2026-07-24, see F3.2 above)
- [ ] macOS (gfortran table entry, Mach-O/codesign handling in zig build)
      — F5, needs omicron (real hardware) access
- [ ] Windows (replaces gnuwin32 — the big prize) — F6, needs kappa (real
      hardware) access
- [ ] `zig build fetch` (retire fetch-r.sh) — not attempted; still a real
      gap, low priority (fetch-r.sh is a one-line curl+checksum, no
      correctness risk in leaving it as-is)
- [x] config.h regeneration procedure doc + version-mismatch guard
      (2026-07-24, see F2.1 above)
- [x] Wire `pixi run zig-build` into CI next to the autoconf path
      (2026-07-24, see F4.2 above — `build-zig` job in build.yml; not yet
      confirmed on a real Actions run). Autoconf/gnuwin32 still retire only
      after F1-F6 are green on all platforms (F5/F6 remain).
