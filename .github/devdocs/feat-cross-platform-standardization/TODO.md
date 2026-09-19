# Milestone 8 — Cross-platform standardization: TODO

See `PLAN.md` in this directory for full context, rationale, and exact
file/line references per phase. This file tracks progress only.

## Follow-up work (post-milestone, picked up after Phase 7)

- [x] **Regenerated `linux-x86_64-slim/subst.txt` for real** — Phase 0's
      verification run found it stale (missing the F7.8 `OBJC=zig-cc`
      fix, originally found/applied on macOS, never backported to the
      vendored Linux config via a real regen). Confirmed genuinely
      consumed, not dead data: `etc/Makeconf.in` has `OBJC = @OBJC@`,
      substituted into the real installed `etc/Makeconf` — a package
      with real Objective-C source compiled on Linux today would get
      `OBJC` pointing at nothing instead of `zig-cc` (rare in practice,
      but a real correctness gap). `config.h` confirmed byte-identical
      before/after (no defines changed); `Rconfig.h` isn't produced by
      plain `configure` at all, so neither needed re-copying —only
      `subst.txt` changed, and `GENERATED_FROM` didn't need bumping
      (R version unchanged, that field only tracks version staleness).
      Full trust bar (build/smoke/contract/check/install/package/
      verify-package) green on gamma. Linux-only change, no
      omicron/kappa impact (their own vendored configs untouched).

- [x] **Unified `Makeconf.win`'s substitution with `ctx.subst`/
      `substitute()`** (the mechanism Phase 4 already unified for this
      file's link-flag entries). Edited the vendored
      `zigbuild/config/win-x86_64-full/Makeconf.win` template itself to
      turn 4 previously bespoke-substring-patched lines
      (`BINPREF`/`IMPDIR`/`LDFLAGS`/`FC`) into real `@VAR@` tokens,
      matching the file's own pre-existing convention (`SYMPAT =
      @SYMPAT@` etc.). `installWindowsCompilerContract` now just
      `ctx.subst.put()`s all 10 values (the 4 new ones plus the 6
      already-`@VAR@` ones — `CSTD`/`EOPTS`/`SANOPTS`/`OPENMP`/`PTHREAD`/
      `SYMPAT`, previously their own separate replaceOwned loop) and
      calls `substitute(ctx, raw)`, the identical call shape unix's own
      template processing uses.
      **Found and fixed a real, previously-silent bug as a side effect**:
      the old `std.mem.replaceOwned(u8, ..., "LDFLAGS =", ...)` was a
      bare substring match, not anchored to line start — confirmed by
      simulating it against the real vendored file that it also matched
      (and corrupted) 12 unrelated variables whose names happen to end in
      "LDFLAGS =" too (`DYLIB_LDFLAGS`, `SHLIB_CXXLDFLAGS`,
      `SHLIB_CXX17LDFLAGS`, `SHLIB_FCLDFLAGS`, `SHLIB_LDFLAGS`, ...),
      silently injecting an extra `-L"..."` into each. Never caused an
      observed failure (an unused extra `-L` flag on a shared-lib-link
      line is harmless to zig cc/lld — that's exactly why it went
      unnoticed), but a real latent defect nonetheless; the token-
      anchored `@LDFLAGS@` substitution only ever touches the one
      intended line, fixing this as a natural side effect of the
      unification rather than a separately-hunted bug.
      Verified for real on kappa: full trust bar green
      (build/smoke/contract/install/package/verify-package — `contract`'s
      minqa/Rcpp checks specifically exercise real Fortran/C++ package
      compilation via the substituted Makeconf), plus direct inspection
      of the generated `Makeconf` confirming `BINPREF`/`IMPDIR`/
      `LDFLAGS`/`FC` all resolved to the correct real paths AND that
      `DYLIB_LDFLAGS`/`SHLIB_CXXLDFLAGS`/`SHLIB_CXX17LDFLAGS`/
      `SHLIB_FCLDFLAGS`/`SHLIB_LDFLAGS` are all clean `-shared` with no
      stray `-L` — the collateral-damage bug is confirmed gone, not just
      theoretically fixed. Smoke-only sanity pass green on omicron/gamma
      (this function is Windows-only, but the shared `substitute()`
      helper it now calls is common code).

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

## 2026-09: the hardware arrived — linux-aarch64 and osx-64 made real (feat-hosted-ci-platforms)

The repo going public (2026-09-03) made GitHub-hosted runners free with
no minute caps, including `ubuntu-24.04-arm` (real linux-aarch64) and
`macos-15-intel` (real osx-64) — dissolving the "no hardware access"
boundary this whole milestone was scoped around. What Phase 7 proved
mechanical on paper was then executed for real:

- **Phase 7's reference diffs applied to build.zig**: the two
  loud-failure placeholders replaced with the verified triples
  (`aarch64-conda-linux-gnu`, `x86_64-apple-darwin13.4.0`).
  `findGfortranLibDir` failures now print the probed gcc_root (review
  finding — a bare GfortranLibNotFound named neither the path nor the
  stale triple).
- **One real gap Phase 7's dry run missed** (caught by code review, not
  CI): `linkFortranRt`'s `.linux` branch unconditionally linked
  `flang_rt.runtime` — right for linux-64/flang, nonexistent on
  linux-aarch64/gfortran. Now keyed on `(os, arch)` like `fortranOne`.
- **Vendored configs generated on real hardware via CI**: new
  `gen-config.yaml` workflow (paths-triggered push + workflow_dispatch)
  runs `pixi run configure` + `gen-subst.sh` on the new runner types;
  gen-subst.sh now stages the complete config dir itself (subst.txt +
  config.h + GETCONFIG-derived Rconfig.h + GENERATED_FROM). Verified
  reproducible: on gamma the round-trip regenerates the vendored
  linux-x86_64-slim config byte-identically.
- **Two real bugs found by the first CI generation runs**: (1) Rconfig.h
  is make-generated, not configure-generated — staging now runs
  `tools/GETCONFIG` exactly as make's own src/include rule does; (2) the
  macos-15-intel image returns "unknown" from `uname -p`, which R's
  config.guess defaults to **powerpc** — configure detected
  `powerpc64-apple-darwin24.6.0` on a genuine x86_64 runner and poisoned
  R_PLATFORM in the generated headers. configure-only.sh now passes an
  explicit `--build` when (and only when) that misdetection would occur.
- **CI matrix**: `build` job gained the arch axis (ubuntu-24.04-arm,
  macos-15-intel × default/full; openblas on both linux archs). The
  self-hosted fleet (gamma/omicron/kappa) was decommissioned outright
  (2026-09-19, see feat-prefix-publish/CI_SELF_HOSTED_PLAN.md's closing
  note): one hosted `conda-package` job now builds + publishes ALL five
  platforms to `universe` via prefix.dev OIDC trusted publishing (no
  stored credentials anywhere), and the Windows fresh-env consume test
  — disabled on kappa over its WSL-bash-on-PATH problem — is re-enabled
  on hosted windows-latest.
- **recipe.yaml**: Fortran selectors collapsed to `linux64 → flang`,
  `not linux64 → gfortran` (render-verified for both linux archs).

**Feature-parity statement**: linux-64, linux-aarch64, osx-arm64,
osx-64, win-64 all get build/smoke/contract (+check on unix) CI legs and
a conda-package publish path. **win-arm64 stays excluded** — a
`windows-11-arm` runner exists, but build.zig's Windows path is
x86_64-only by explicit design (pervasive MinGW-prefix/R_ARCH="x64"
conventions needing an upstream R design decision — Phase 2's documented
non-goal, unchanged by runner availability).

### PR #6 CI: the three hosted-runner failure classes, root-caused (2026-09-19)

All three were "unexplained" when the branch first ran on hosted
runners. Each turned out to be an environment difference between the old
self-hosted fleet and GitHub's runner images (or their conda packages),
not a build.zig platform bug.

1. **ubuntu-24.04-arm: `process terminated with signal ILL` (build job)
   / `SEGV` (conda-package job) at "R bootstrap: tools sysdata", the very
   first R invocation.** Not codegen. The vendored linux-arm64 subst.txt
   carried gfortran's implicit search dirs verbatim in FLIBS/FLIBS_IN_SO/
   FCLIBS **and R_LD_LIBRARY_PATH**, including
   `<conda>/aarch64-conda-linux-gnu/sysroot/{lib64,usr/lib64}` — and
   conda-forge's `sysroot_linux-aarch64` package ships a complete glibc
   runtime there (`lib64/libc.so.6`, `ld-linux-aarch64.so.1`,
   `libm.so.6`; verified by listing the 2.28 package from the lockfile).
   `etc/ldpaths` exports R_LD_LIBRARY_PATH into LD_LIBRARY_PATH, so every
   R process loaded the sysroot's libc.so.6 under the host's ld.so and
   died in startup, the signal varying with layout. linux-64 (flang)
   never had those dirs. The "~86 s is too fast for a real compile"
   premise was wrong too: the leg had finished 120/169 steps, i.e. every
   compile — Cobalt runners are simply fast (x86 build+bootstrap is
   ~3.5 min). Fix: gen-subst.sh strips every `/sysroot/` entry (both the
   `-L` and the `:`-separated form), applied to both vendored linux-arm64
   configs. The earlier `.cpu_model = .baseline` commit was a misdiagnosis
   of this crash but stays on its own portability merits (its comment now
   says so).
2. **macos-15-intel: contract test dies in jsonlite's bundled yajl at
   `zig-ar rcs yajl/libstatyajl.a ...` — "unable to open ...: No such file
   or directory".** conda-forge's osx-64 zig 0.16.0 `zig ar` (llvm-ar)
   cannot *create* an archive: the ENOENT its create path is written for
   fails the `EC != errc::no_such_file_or_directory` guard (macOS zig is
   linked against conda's *shared* libc++, the classic two-error_category-
   instances setup). Reproduced on omicron under Rosetta with a throwaway
   `platforms = ["osx-64"]` pixi env: `zig ar rcs new.a x.o` fails
   identically, the osx-arm64 zig succeeds, and osx-64 appends to an
   already-existing archive fine. Fix: `toolchain/zig-ar` on Darwin seeds
   a missing insert-mode target with the 8-byte `!<arch>\n` header and
   pins `--format=darwin`. jsonlite's yajl is the only `$(AR)` user in the
   whole CI; R itself archives through zig build's own writer.
3. **windows-latest: "failed to check zig installation for DLL import
   libs: Unexpected" at the first system-DLL link (Rgraphapp).** The
   failing command line's last library was literally `"-lmsimg32\"\r"`.
   GitHub's Windows runner images ship Git with `core.autocrlf=true`, so
   checkout converted `zigbuild/config/win-x86_64-full/subst.txt` to CRLF
   and `loadSubstFile` — which only strips a trailing `"` — kept `"\r` on
   every value. zig's mingw `libExists` then tried to stat
   `libmsimg32"\r.a`: Win32 ERROR_INVALID_NAME has no zig error mapping →
   `error.Unexpected` (the same mechanism as ziglang/zig#25758, a lib name
   the check cannot stat). The diagnostic probe job never reproduced it
   because it never read subst.txt. Fix: `.gitattributes` `* text=auto
   eol=lf` plus a CRLF-tolerant parser; the probe job is deleted. (kappa
   also has autocrlf=true and never failed; its checkout is gone, so that
   difference is unexplained — most likely a locally-written LF file.)

Validation before the CI round-trip: linux-64 configure phase + `zig fmt`
clean, full local build/smoke/contract on gamma; the macOS mechanism was
reproduced and the workaround exercised on omicron. ARM and Windows fixes
are validated by the next CI run only (omicron has no container runtime;
kappa's workspace no longer exists).


**Round 2 (same day, after the three fixes above went in — run
35444873262).** Every ARM build leg passed build/smoke/contract/check for
the first time, the win-64 conda package passed, and three *new* failures
surfaced one layer deeper:

4. **verify-package on both linux legs**: the new glibc-ceiling check's
   first-ever CI run tripped on `lib/R/bin/toolchain/realpath`
   (conda-forge coreutils, GLIBC_2.28) — the only file in the whole bundle
   above 2.17; R's own code and every vendored *library* are clean. The
   `exit 1` inside the `while read < <(find ...)` loop also fired the EXIT
   trap mid-walk, burying the one real error under "cannot open" noise.
   Now two tiers: runtime artifacts hard at 2.17, the compile-time helpers
   under bin/toolchain bounded at conda-forge's 2.28 baseline (only used
   by bin/libtool / javareconf, i.e. on a dev machine that needs zig
   anyway); list collected before the loop.
5. **osx-64 conda package: rattler-build's relink pass fails
   `install_name_tool` on every zig-linked Mach-O** ("malformed object
   (offset field of section 0 in LC_SEGMENT command 0 not past the
   headers)"). zig's Mach-O linker on x86_64 starts the first __TEXT
   section at exactly mach_header + sizeofcmds — zero headerpad — so no
   tool can grow the load commands (Apple's says "larger updated load
   commands do not fit"). osx-arm64 has ~15 KiB of accidental slack from
   16 KiB page alignment. Fix: `headerpad_max_install_names` on every
   macOS Compile step in build.zig (what R's Makeconf already passes for
   package .so files). Verified on omicron under Rosetta: conda's
   install_name_tool runs rattler's delete/add/id/change sequence on the
   padded output; without the pad both Apple's and conda's tool fail.
6. **linux-aarch64 conda package: `libRlapack.so: undefined symbol:
   _ZGVnN2v_log`** (glibc libmvec's Advanced-SIMD `log`). rattler-build
   solved gfortran 16.2 + sysroot 2.39 for its build env (the pixi
   lockfile has 15.2 + 2.28); glibc >= 2.30 sysroots ship
   `finclude/math-vector-fortran.h`, which gfortran's driver auto-adds as
   `-fpre-include`, and -O2's loop vectoriser then emits libmvec calls
   that zig's glibc-2.17 stubs can never provide. Verified locally with a
   sysroot-2.39 gfortran env: `-fpre-include=/dev/null` does not override
   the driver's automatic one, `-nostdinc` would drop the intrinsic-module
   dir, `-fno-tree-loop-vectorize` is the targeted fix (build.zig, gfortran
   on linux only). Package-side exposure remains: a user compiling a
   Fortran package with a >= 2.30 sysroot gets the same undefined symbol,
   since R's Makeconf FFLAGS are plain `-O2` and zig-cc links no libmvec —
   noted, not fixed here.

**Outcome**: with rounds 1 and 2 in, run 35446891595 (commit 8f2165b,
2026-09-19) is the first fully green hosted-runner run — all 16 jobs:
build × {ubuntu-latest, ubuntu-24.04-arm, macos-latest, macos-15-intel}
× {default, full} + both linux openblas legs, windows-latest, and all five
conda-package legs. The PR is mergeable pending prefix.dev
trusted-publisher registration.
