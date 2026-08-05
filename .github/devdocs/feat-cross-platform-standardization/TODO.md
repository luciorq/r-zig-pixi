# Milestone 8 — Cross-platform standardization: TODO

See `PLAN.md` in this directory for full context, rationale, and exact
file/line references per phase. This file tracks progress only.

- [x] Phase 0 — restored `zigbuild/tools/configure-only.sh` (byte-identical
      flags to the deleted `configure-r.sh`, minus its two R-source-patch
      blocks — those stay solely owned by `scripts/zig-build.sh`) + a
      `configure` pixi task. Verified on gamma: fresh `pixi run configure`
      into a clean `build/obj-4.6.1-slim` produced the expected slim
      profile (no JPEG/TIFF/NLS); `gen-subst.sh` then produced a
      `subst.txt` differing from the currently-vendored
      `linux-x86_64-slim/subst.txt` only by: (a) `OBJC_LIBS` whitespace
      noise, (b) `LD` resolving to a differently-prefixed `ld` symlink
      (environment drift, not a script bug), and (c) **a real, useful
      finding** — `OBJC`/`OBJCFLAGS`/`ac_ct_OBJC` are stale in the
      vendored Linux config: it predates the F7.8 `OBJC=zig-cc` fix
      (originally found/fixed for macOS OBJC routing), which this
      restored script's flags already correctly capture. Reverted the
      live vendored file (this phase proves the mechanism, doesn't apply
      it) — regenerating `linux-x86_64-slim/subst.txt` for real to pick
      up the OBJC fix is a small, separate, optional follow-up, not done
      here. `pixi run build && pixi run smoke` both green afterward on
      gamma, confirming nothing was disturbed.
- [x] Phase 1.1 — deleted `win_utils_c` (byte-identical to `utils_c`;
      Windows call site now references `rspec.utils_c` directly) and
      `win_blas_f`/`win_blas_f90` (byte-identical to `blas_f`/`blas_f90`).
- [x] Phase 1.2 — `Ctx.condaDir(comptime sub)` added; applied at the 4
      genuinely-repeated sites found by grep (build.zig's line numbers
      had drifted from the review doc's 2026-07-28 references, as
      expected — re-grepped rather than trusting stale numbers). Several
      other `{conda}/Library/X` constructions in the file turned out to
      be single-platform literals (winCairo's `-I` flags, the Makeconf
      template strings, the gcc-root lookups) rather than the repeated
      ternary this helper targets — left those as-is rather than forcing
      an ill-fitting abstraction onto them.
- [x] Phase 1.3 — `Ctx.rhomeInstallDir(comptime sub)` added; applied at
      all 11 `"Library/lib/R/..."` literal sites in `buildWindows()`
      (grep found 11, not the review doc's estimated 9 — same line-drift
      reason). Deliberately NOT applied to unix's own `"lib/R/..."`
      literals in this step (out of the plan's stated scope) — except
      where Phase 1.4 needed it for the genuinely-shared share/doc calls.
- [x] Phase 1.4 — `installCommonPayload(ctx)` added, but scoped narrower
      than the review doc suggested after actually reading both
      functions: only the share/doc `addInstallDirectory` calls are
      truly identical-mechanism between `installLibraryWindows`/
      `installStaticTree` (now folded into one shared function, using
      `rhomeInstallDir` on both platforms for the first time). The
      header/R_ext staging is NOT folded in — unix stages those into the
      same `WriteFiles` tree as everything else in `stage`, bulk-installed
      together later, while Windows installs them directly via their own
      `addInstallDirectory` calls with no `WriteFiles` intermediary at
      all. That's a genuine mechanism difference, not just a
      parameterization gap — forcing one shape onto the other would be a
      real behavior change, out of scope for a "zero intended behavior
      change" phase. Documented in the function's own doc comment so a
      future pass doesn't assume it's already done.
- [x] Phase 1.5 — `Ctx.addCondaLibPath(mod)` added (folds the library-path
      +rpath pairing into `condaDir`'s Windows/else split); applied at
      the same 4 sites as 1.2 (`newCMod`, `linkOmp`, `linkCoreLibs`) —
      these three turned out to be exactly where 1.2 and 1.5 overlap, so
      implemented together in one pass rather than two separate ones
      touching the same lines twice.
- [x] Phase 1.6 — `grdevices_c`/`win_grdevices_c` (14 entries each, 12
      shared) restructured into `grdevices_shared_c` (12, shared) +
      `grdevices_cairo_c` (unix-only pair) + `win_grdevices_c` (now just
      the Windows-only pair) — both call sites now use two `addCGroup`/
      `newPkgMod` calls (shared base + platform tail), matching
      `tzone_c`/`win_tzone_c`'s existing pattern exactly. Windows'
      per-file compile flags applied to the whole module rather than
      split further (harmless on files that don't reference them,
      preserves exact prior compiled behavior). `rlapack_f90_ordered`/
      `win_lapack_f90_ordered` reordered to the same canonical sequence
      (cosmetic only — both orders already satisfied the real
      la_constants → la_xisnan → {dlassq,zlassq,dlartg,zlartg}
      dependency).
- [x] Phase 1 full trust bar — **all green on all 3 real machines**:
      gamma (build/smoke/contract/check/install/package/verify-package),
      omicron (same 7, including the codesigned/relocatable bundle
      check), kappa (smoke/contract/install/package/verify-package — no
      `check` on Windows per FINALIZATION.md F6, matches project
      convention). Kappa's `contract` run specifically re-exercised the
      `pak` recursive-R.exe-invocation test (F7.1/F7.6's own regression
      check) with zero regressions from the `newCMod`/Windows install-dir
      changes.
- [x] Phase 2.1 — `Arch` enum (`x86_64`/`aarch64`) + `condaForgeSuffix()`
      method (preserves the exact existing "x86_64"/"arm64" strings —
      note "arm64", not "aarch64", even on Linux, a pre-existing
      convention left unchanged) + `Ctx.arch` field, populated from
      `target.result.cpu.arch` at the same site `arch_str` used to be
      computed.
- [x] Phase 2.2 — `findFlangRt` takes `arch: Arch`, switches the LLVM
      triple (`x86_64-unknown-linux-gnu` / `aarch64-unknown-linux-gnu`).
      Only ever called for linux-x86_64 today (linux-aarch64 uses
      gfortran, see 2.3) but no longer hardcodes the triple.
- [x] Phase 2.3 — macOS gcc-root lookup now switches on `ctx.arch`
      inside the `.macos` branch: `.aarch64` keeps the existing
      `arm64-apple-darwin20.0.0` path; `.x86_64` (osx-64) fails loudly
      with a clear error pointing at Phase 7 rather than guessing a
      Darwin triple with no hardware to confirm it against. Same
      loud-failure treatment added for `.linux`+`.aarch64`'s gfortran
      lookup (conda-forge has no flang there — confirmed via
      `pixi.toml`'s own `[target.linux-aarch64.dependencies]`, which
      already pins `gfortran`, matching macOS/Windows). `fortranOne`'s
      compiler selection restructured around a small local
      `enum { flang, gfortran }` derived from `(ctx.os, ctx.arch)`
      instead of `ctx.os` alone — `compiler`/`moddir_flag` now follow
      that enum (flang→`-module-dir`, gfortran→`-J`) instead of directly
      switching on `os`, so linux-aarch64 correctly gets gfortran's
      flag shape once its gcc-root placeholder (above) is eventually
      resolved. `opt` (the `-O1` gfortran-darwin miscompile cap)
      simplified to `if (ctx.os == .macos) "-O1" else "-O2"` — same
      values as before for every currently-real platform, just no
      longer needs a 3-way `switch`.
- [x] Phase 2 full trust bar — **all green on all 3 real machines**,
      same 7-check suite as Phase 1 (gamma/omicron: full 7; kappa: 5,
      no `check`). Confirms `ctx.arch` resolves correctly on real
      hardware in both directions that exist today — `.x86_64` on
      gamma/kappa (flang still selected on linux, gfortran still
      selected on windows, exactly as before) and `.aarch64` on
      omicron (macOS gcc-root's `.aarch64` branch taken, gfortran
      still selected, `-O1` cap still applied) — with zero behavior
      change on any of them. The two new "unverified, fails loudly"
      branches (osx-64, linux-aarch64) are inherently untestable
      without that hardware; Phase 7 resolves them via real package
      inspection instead of a real build.
- [x] Phase 3 — `Ctx` gained a `config_dir` field (the `build()`-local
      `config_dir` string was never threaded down to `buildWindows()`
      before this — needed a new field, not just a reference, since
      `buildWindows(ctx, io)` has no other way to reach it). All 3
      hardcoded `"zigbuild/config/win-x86_64-full"` literals (config.h,
      Rconfig.h, Makeconf.win) replaced with `ctx.config_dir`. Proved
      zero-behavior-change for real (not just by inspection): added a
      temporary `std.debug.assert(std.mem.eql(u8, ctx.config_dir, "...
      win-x86_64-full"))` right before the swap, ran a real `pixi run
      build` on kappa — the assertion would have panicked immediately if
      wrong, it didn't, build completed ("zig-built R OK") — then removed
      the assertion.
- [x] Phase 3 full trust bar on kappa (build/smoke/contract/install/
      package/verify-package, all green, bundle relocatable), smoke-only
      sanity pass on gamma/omicron (both green) since `config_dir`
      computation is shared code even though only Windows's own literals
      changed.
- [x] Phase 4.0 — checked whether a real captured Makeconf could serve as
      the "cross-check" source the plan called for: it can't — gnuwin32's
      top-level `Makeconf.win` (already vendored, itself a real kappa
      capture) has no `CAIRO_LIBS`/`BITMAP_LIBS`/equivalent entries at
      all; those concepts live in *per-package* `Makefile.win` files
      gnuwin32 never centralizes. The 5 lists already hardcoded in
      `buildWindows()` turned out to already **be** the real, ground-
      truth values — each independently found via a real kappa link
      error and extensively documented in its own comment (F6.3/F7 work)
      — so Phase 4 relocates already-verified data into `subst.txt`
      rather than capturing new data.
- [x] Phase 4.1 — extracted `loadSubstFile` (generic `S["KEY"]="VALUE"` +
      `@ZR_*@` parsing) out of `loadSubstTable`, which now just calls it
      then appends unix-only extras (config.status template-var
      defaults, `AC_SUBST_FILE` rules_frag heredocs — confirmed
      `Makeconf.win` doesn't need any of these, it's substituted via its
      own separate find/replace list, not `ctx.subst`). Vendored
      `zigbuild/config/win-x86_64-full/subst.txt` (new file — Windows had
      none before) with 5 hand-populated entries: `CAIRO_LIBS` (reused —
      genuine conceptual match with unix's own key, just a far simpler
      value), `WIN_INTERNET_LIBS`, `WIN_BITMAP_LIBS`, `WIN_R_DLL_LIBS`,
      `WIN_RGRAPHAPP_LIBS` (4 new Windows-only keys — no unix conceptual
      equivalent exists for pure Win32 GDI/system libs). `buildWindows()`
      now calls `loadSubstFile(ctx, io, ctx.config_dir)` early (Phase 3's
      `config_dir` field made this trivial).
- [x] Phase 4.2 — all 5 hardcoded `for (...) |lib| mod.linkSystemLibrary(...)`
      loops (Rgraphapp.dll, R.dll, internet.dll, grDevices.dll,
      winCairo.dll) replaced with `applyLinkFlags(ctx, mod,
      ctx.subst.get("KEY").?)` — the identical call shape unix has used
      all along. Updated the winCairo comment that explicitly said
      "Windows has no subst table to source these from" (no longer true)
      and referenced the now-deleted `scripts/build-gnuwin32.sh`
      (Milestone 7).
- [x] Phase 4 full trust bar on kappa (build/smoke/contract/install/
      package/verify-package, all green) — **explicit F6.3 capability
      re-check**, the exact regression class this phase risked most:
      `capabilities()$libcurl`/`$ICU`/`$cairo` all confirmed `TRUE`
      (matching smoke-test.sh's own windows/slim assertions), same as
      F6.3 originally fixed. `pak`'s recursive-R.exe-invocation contract
      test also green — this phase's link-flag changes touch every
      Windows DLL in the build (R.dll, Rgraphapp.dll, internet.dll,
      grDevices.dll, winCairo.dll) and none regressed.
- [x] Phase 5.1 — added `[feature.pkg.target.linux-aarch64.tasks]`
      `conda-publish` to `pixi.toml`, mirroring the existing 4 platform
      blocks (its `[target.linux-aarch64.dependencies]` counterpart
      already existed, confirmed via grep). `pixi task list` confirms it
      parses. Nothing to publish through it yet (no zigbuild config for
      that platform) — added purely for consistency, as the plan states.
- [x] Phase 5.2 — added a comment at `recipe.yaml`'s Windows test-script
      `bin/x64` literal tying it to build.zig's own R_ARCH="x64"
      hardcodes and the win-arm64 non-goal. Left the surrounding
      %PREFIX%-vs-relative-path content alone — pre-existing, unrelated
      to this milestone (a separate testing-mechanism concern from
      earlier work, already on `main`).
- [x] Phase 5.3 — added comments at both CI matrices with no arch
      dimension today (`build`/`build-windows`'s hosted matrix,
      `conda-package`'s self-hosted labels), pointing at this plan for
      whenever real new-platform hardware/CI arrives. `build.yaml`
      validated.
- [x] Phase 6 — recommendation already recorded in `PLAN.md`'s own Phase
      6 section at planning time: `WINDOWS_FRONTEND_UNIFICATION.md` stays
      a separate, follow-on milestone, not folded into this one. No
      further action needed here — nothing in Phases 1-5's actual
      implementation changed that reasoning.
- [x] Phase 7 — downloaded and inspected real `gfortran_impl_osx-64` and
      `gfortran_impl_linux-aarch64` `.conda` packages (from URLs already
      solved in `pixi.lock`) directly, no hardware needed. Both real
      Darwin/Linux triples turned out genuinely non-obvious — confirms
      Phase 2's loud-failure-instead-of-guessing was the right call:
      osx-64 is `x86_64-apple-darwin13.4.0` (not a version-substituted
      guess off the existing `arm64-apple-darwin20.0.0`), linux-aarch64
      is `aarch64-conda-linux-gnu` (conda-forge's own custom sysroot
      triple, not a generic `aarch64-unknown-linux-gnu`/`-linux-gnu`).
      Both confirmed to match `findGfortranLibDir`'s existing expected
      layout exactly — no code changes needed to that function, only the
      gcc-root string. Recorded as reference-only diffs (NOT applied to
      build.zig — Phase 2's placeholders stay as-is; this project's own
      established discipline is real-hardware verification before
      trusting a change that ships, and applying just this piece
      wouldn't make either platform buildable anyway with no vendored
      config dir yet) in the new
      `DRY_RUN_NEW_PLATFORMS.md` in this directory, which also lists the
      one genuinely hardware-gated remaining step (running real
      `configure` + `gen-subst.sh` on real hardware) — everything else
      in the procedure is confirmed mechanical.
