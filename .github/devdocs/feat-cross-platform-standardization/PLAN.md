# Milestone 8 — Cross-platform standardization (architectural readiness)

## Context

Milestone 5 got `zig build` working on all 3 target platforms (linux-64,
osx-arm64, win-64), and Milestone 7 retired the old autoconf/gnuwin32
fallback path entirely. With the build genuinely working and unified on
all three OSes, the next goal — explicitly requested — is to standardize
`build.zig` as much as possible across those OSes (leveraging that pixi,
conda-forge, and zig build already give one common toolchain and one
directory-layout convention per OS), while making sure the structure
doesn't block adding more platforms later (osx-64, linux-aarch64,
win-arm64) once conda-forge's dependencies for them are stable.

Two review docs already exist from a prior pass
(`.github/devdocs/feat-zig-build/CROSS_PLATFORM_STANDARDIZATION.md` and
`WINDOWS_FRONTEND_UNIFICATION.md`, both "review/plan only, no code yet").
This milestone builds directly on both rather than re-deriving them, plus
closes a real, newly-found gap: `zigbuild/tools/gen-subst.sh`'s own
documented prerequisite (`pixi run configure`) was deleted as a side
effect of Milestone 7's legacy-script cleanup, so the config-regeneration
procedure is currently broken for every platform, not just new ones.

**Confirmed scope boundary** (explicit user decision): no new
hardware/CI access to osx-64, linux-aarch64, or win-arm64 exists right
now. This milestone is **architectural readiness only** — de-duplicate,
unify mechanisms, make `arch` a first-class parameterized dimension — all
verified on the existing 3 real machines (gamma=linux-x86_64,
omicron=osx-arm64, kappa=win-x86_64). Actually building/shipping a 4th
platform is out of scope; it becomes a small, mechanical follow-up once
real hardware exists, and this milestone's Phase 7 proves — on paper,
via real package inspection, without hardware — exactly how small.

Work happens on branch `feat-cross-platform-standardization`, off latest
`main` (post Milestone 7 merge, commit `1422fa4`).

## Prior art (already read in full, not re-derived)

- `.github/devdocs/feat-zig-build/CROSS_PLATFORM_STANDARDIZATION.md`
  (2026-07-28) — source of Phases 1 and 4.
- `.github/devdocs/feat-zig-build/WINDOWS_FRONTEND_UNIFICATION.md`
  (2026-07-28) — addressed in Phase 6 (scope decision).

## New findings (verified today, not in the prior docs)

- `Ctx` (build.zig:65) has an `os: Os` field but **no `arch` field at
  all** — `arch_str`/`platform`/`config_dir` are local variables inside
  `build()` (build.zig:191-209), discarded after constructing the
  config-dir path string. This is the core gap blocking "add a platform
  mechanically."
- `buildWindows()` hardcodes the literal `"zigbuild/config/win-x86_64-full"`
  three times (build.zig:611, 614, 1403 — confirmed exact) instead of
  using the `config_dir` value already computed generically for unix.
- Hardcoded arch-specific literals that would each need to become
  computed: `findFlangRt`'s `"x86_64-unknown-linux-gnu"` triple
  (build.zig:1684, confirmed) — silently wrong for linux-aarch64, which
  `pixi.toml` already declares as a platform; macOS's gcc-root
  `"arm64-apple-darwin20.0.0"` (build.zig:249, confirmed) — needs an
  x86_64 branch for osx-64; Windows's MinGW prefix
  (`x86_64-w64-mingw32-`) and the pervasive gnuwin32 `R_ARCH="x64"`
  convention, both far more deeply embedded — win-arm64 support is
  "essentially unbuilt, not just unparameterized."
- **Urgent, separate regression**: `gen-subst.sh` requires a real
  `config.status` (errors "run 'pixi run configure' first" if missing —
  gen-subst.sh:25-29), but `scripts/configure-r.sh` and the `configure`
  pixi task were deleted wholesale in Milestone 7. Confirmed via `git
  show 665811f~1:scripts/configure-r.sh`: the deleted script also carried
  two R-source patches (`Sys.which` bundled-`which`, `R_LIBS_USER_default`
  XDG/LOCALAPPDATA) — both now independently owned by `scripts/zig-build.sh`
  (confirmed present there, zig-build.sh:19-30,47-76) — so a restored
  configure-only script must NOT resurrect those patches, only the real
  `configure` invocation itself.
- `pixi.lock` already contains fully-solved osx-64 (631 lines) and
  linux-aarch64 (676 lines) dependency graphs, including real
  `gcc_impl_osx-64-15.2.0-h93e45a1_19.conda` /
  `gcc_impl_linux-aarch64-15.2.0-h3530432_19.conda` package refs —
  obtainable and inspectable without owning that hardware, since pixi
  solves lockfiles for every declared platform regardless of host.
- `pixi.toml` is already "ahead" of `build.zig`: `[target.osx-64...]`/
  `[target.linux-aarch64...]` dependency blocks exist, but
  `[feature.pkg.target.linux-aarch64.tasks]`'s `conda-publish` entry is
  missing even though its dependency block exists.

## Phase 0 — Unblock config regeneration (urgent, do first)

Everything else either touches the vendored-config mechanism (Phase 3) or
depends on proving new config dirs are addable (Phase 7) — that mechanism
is broken today for every platform.

Restore a thin, **configure-only** script (new file, e.g.
`zigbuild/tools/configure-only.sh`, or a stripped `scripts/configure-r.sh`
with both source-patch blocks removed — pick one, keep `gen-subst.sh`'s
own pointer comment consistent). Sources `scripts/env.sh`; keeps the same
flag set the deleted script used (`--prefix`, per-variant
`VARIANT_ARGS`, `BLAS_ARGS`, `--enable-R-shlib --with-x=no --without-aqua
--with-cairo --with-libpng --with-internal-tzcode
--without-recommended-packages --disable-java`, `CC/CXX/OBJC/OBJCXX`
pointed at `zig-cc`/`zig-cxx`, `FC=$(fortran_compiler)`,
`AR/RANLIB=zig-ar`/`zig-ranlib`, the macOS gfortran `-O1` cap, the flang
`FLIBS_ARGS` workaround) — byte-identical flags so a regeneration doesn't
silently diverge from what's already vendored. Keep the Windows
short-circuit (`exit 0`, matching `gen-subst.sh`'s permanent Windows
refusal). Restore a `configure` pixi task pointing at it, so
`checkConfigFreshness`'s existing error message (build.zig:2117) and
`PLAN.md`'s documented regen procedure both work again untouched.

**Acceptance bar**: run it on gamma into a scratch objdir (don't overwrite
the live vendored config), run `gen-subst.sh` against it, diff the fresh
`subst.txt` against `zigbuild/config/linux-x86_64-slim/subst.txt` —
should match modulo the 6 host-specific `@ZR_*@` paths. No
smoke/contract/etc. re-run required (this path never runs during a normal
build) beyond a quick `pixi run build && pixi run smoke` sanity check on
gamma.

## Phase 1 — Safe mechanical de-duplication (CROSS_PLATFORM_STANDARDIZATION.md §1)

Pure refactors, zero intended behavior change. Order (matches the source
doc):

1. **§1c** — delete `rspec.zig`'s byte-identical `win_utils_c`/
   `win_blas_f`/`win_blas_f90` (duplicates of `utils_c`/`blas_f`/
   `blas_f90`); reference the shared arrays directly, matching how
   `win_tzone_c`/`tzone_c` already do it correctly.
2. **§1a** — `Ctx.condaDir(comptime sub)` helper, collapsing the
   `if (ctx.os == .windows) "{conda}/Library/X" else "{conda}/X"` ternary
   re-derived at 8+ sites (build.zig:209, 1685/1688, 1750, 1802/1804,
   1223-1224, 1350, 1362, 1655 — re-grep before editing).
3. **§1e** — `Ctx.rhomeInstallDir(comptime sub)` helper, collapsing the
   hand-typed `"Library/lib/R/..."` literal at 9 sites in
   `buildWindows()`.
4. **§1f** — `installCommonPayload(ctx, inst)`, folding
   `installLibraryWindows`/`installStaticTree`'s identical
   header+share+doc staging (biggest literal-duplicate block in the
   file) into one function, built on step 3's helper.
5. **§1b** — pairing helper for unix's `addLibraryPath`+`addRPath`
   (always called together with the identical path at 4 sites) so the
   pairing can't be forgotten at a future call site.
6. **§1d** — `rspec.zig` base+diff lists for `win_grdevices_c` (10/14
   entries shared with `grdevices_c`) and canonicalize
   `rlapack_f90_ordered`/`win_lapack_f90_ordered`'s ordering.

**Verification**: full trust bar (`build`/`smoke`/`contract`/`check`
unix-only/`install`/`package`/`verify-package`) on gamma, omicron, AND
kappa once after the whole phase (steps are tightly related; bisect
per-step only if something breaks).

## Phase 2 — `arch` as a first-class `Ctx` field

The highest-risk phase — touches Fortran-compiler selection, a
load-bearing decision already hardened through real F5.1/F6.1/F7.4 bugs.

1. Add `const Arch = enum { x86_64, aarch64 };` and an `arch: Arch` field
   on `Ctx`, populated once in `build()` from `target.result.cpu.arch`
   (replacing the bare-string switch at build.zig:191-198). Keep a
   `condaForgeSuffix()`-style method returning the exact strings already
   in use (`"x86_64"`/`"arm64"`) so every existing `zigbuild/config/`
   directory name is unaffected.
2. `findFlangRt` (build.zig:1674-1689) takes `ctx`/`arch` and switches
   the LLVM triple (`x86_64-unknown-linux-gnu` vs
   `aarch64-unknown-linux-gnu` — confirm the aarch64 string via Phase 7's
   real package inspection before trusting it, don't guess).
3. macOS gcc-root computation (build.zig:249) gains an `x86_64` branch
   alongside the existing `arm64-apple-darwin20.0.0` one; the exact
   osx-64 darwin-triple directory name is an explicit, loudly-failing
   placeholder until Phase 7 resolves it from a real package inspection.
4. **Real structural finding to implement carefully**:
   `[target.linux-aarch64.dependencies]` already specifies `gfortran`,
   not `flang` (conda-forge doesn't ship flang for linux-aarch64) — so
   Fortran *compiler selection* itself (`fortranOne`, currently keyed
   only on `os`) must become keyed on `(os, arch)`: linux-aarch64 is the
   one platform where the same OS needs a different Fortran compiler than
   its x86_64 sibling. This is a real logic change, not a rename — flag
   it prominently in review.
5. **Explicitly not touched**: Windows arch (win-arm64) parameterization
   — the MinGW prefix and `R_ARCH="x64"` convention are pervasive
   (build.zig:688,748,1122,1130,1220,1363,1393,1420,1450,1468,1474,1566,
   1587-1588,1798,2642,2923) and `R_ARCH` itself needs a real upstream
   design decision (does win-arm64 even get a defined `R_ARCH` value?)
   before mechanical parameterization is safe. Leave pointer comments at
   each site instead of guessing.

**Verification**: full trust bar on all 3 machines. Confirm `ctx.arch`
resolves to `.x86_64` on gamma/kappa and `.aarch64` on omicron — the only
two values provable on real hardware today.

## Phase 3 — Windows uses the generic `config_dir` mechanism

Replace the 3 hardcoded `"zigbuild/config/win-x86_64-full"` literals
(build.zig:611, 614, 1403) with the already-computed `config_dir` value.
Since Windows always resolves to `variant = .full` and, post-Phase-2,
`platform = "win-" ++ arch.condaForgeSuffix()`, this is a
zero-behavior-change substitution for the one real Windows config that
exists today — prove it explicitly (temporary assertion comparing
computed vs. literal, then remove) rather than trusting by inspection.
Does **not** give Windows arch parameterization "for free" — only means a
future `win-arm64-full` dir would be *found* correctly if everything else
about win-arm64 (Phase 2's explicit non-goal) were separately solved.

**Verification**: full trust bar on kappa; smoke-only sanity pass on
gamma/omicron since `config_dir` computation is shared code.

## Phase 4 — Windows subst-table unification (§2, "the real architectural win")

Its own sub-phase, sized as a half-day task per the source doc.

1. Vendor `zigbuild/config/win-x86_64-full/subst.txt` (same `S["VAR"]=`
   format unix already uses), populated from the 5 currently-hardcoded
   lists (`internet.dll`'s libcurl/wininet/ws2_32 at :933, `winCairo.dll`'s
   cairo/fontconfig at :1229, `grDevices.dll`'s 6-entry list at :1197,
   `R.dll`'s 12-entry array at :1027, `Rgraphapp.dll`'s 8-entry array at
   :983) — **cross-check against a real generated Makeconf on kappa**,
   don't just copy the zig lists verbatim (some current values came from
   zig/lld-link-specific debugging a naive Makeconf diff would miss;
   reconcile any discrepancy explicitly).
2. Replace each hardcoded loop with `applyLinkFlags(ctx, mod,
   ctx.subst.get("KEY").?)`, matching unix's exact call shape.
3. Confirm (don't assume) whether `loadSubstTable` is currently wired for
   `os == .windows` at all, and whether Windows values need the `@ZR_*@`
   path-substitution unix values need (likely not — most are plain
   library-name lists) — a wrong assumption here would silently corrupt
   values instead of failing loudly.

**Verification**: full trust bar on kappa, **plus an explicit re-check of
F6.3's own capability assertions** (`capabilities()$libcurl`/`ICU`/
`cairo` all `TRUE`) — this phase touches exactly the code that fixed
those bugs the first time.

## Phase 5 — Close small, independent gaps

1. `pixi.toml`: add the missing `[feature.pkg.target.linux-aarch64.tasks]`
   `conda-publish` block, mirroring the existing 4 — for consistency with
   the already-existing dependency block, not because it's usable yet.
2. `recipe/recipe.yaml`: leave the Windows test script's
   `Library/lib/R/bin/x64/Rscript.exe` literal as-is, add a comment tying
   it to Phase 2's Windows-arch non-goal (fixing it alone would be
   cosmetic without build.zig's matching fix).
3. `.github/workflows/build.yaml`: comment near the CI matrices noting
   they have zero arch dimension today, pointing future readers at this
   plan for when real new-platform hardware arrives.

**Verification**: `pixi task list` confirms the new task parses; no
functional verification needed for the comment-only changes.

## Phase 6 — Windows front-end unification: scope decision

**Recommendation: keep `WINDOWS_FRONTEND_UNIFICATION.md` as its own,
separate, parallel-track milestone — do not fold it into this one.** It's
already a fully-scoped, self-contained plan (its own verification plan,
its own two open questions) whose goal — deleting ~900 lines of gnuwin32
C and replacing them with the shell-script dispatcher Unix already uses —
is a Windows-only correctness/simplification effort orthogonal to this
milestone's "make new platforms addable" goal. Bundling it in would
dilute this milestone's confirmed scope with a substantial, independently
risky rewrite unrelated to `arch`. The only real intersection: if Phase 4
lands first, front-end unification becomes marginally easier to review
(Windows's link-flag mechanism will already look like unix's) — an
ordering preference, not a dependency.

If picked up later, resolve its own two open questions: (a) move
`Rcmd_environ`'s `R_OSTYPE=windows` into a direct `Rcmd.in` patch rather
than a separately-vendored file (consistent with this milestone's own
"prefer one parameterized mechanism" direction); (b) defer
`Rscript.c`/`Rterm.exe` R_HOME unification, matching the doc's own lean.

## Phase 7 — Definition of done: prove a 4th platform is mechanical, on paper

By the end of this milestone, the exact diff needed for real osx-64 (and
linux-aarch64) support should be small and mechanical — provable without
hardware:

1. Inspect `pixi.lock`'s already-solved osx-64/linux-aarch64 dependency
   sets (confirmed present, see Findings above).
2. Download (not execute — just fetch and unzip) the resolved osx-64
   `gcc_impl_osx-64`/`gfortran` `.conda` packages directly, list their
   `lib/gcc/<triple>/` structure to get the **real** osx-64 darwin-triple
   directory name, resolving Phase 2's placeholder without guessing.
3. Repeat for linux-aarch64's `gfortran` package, confirming the triple
   Phase 2's `findFlangRt`/gcc-root branches need.
4. Write the one-line diffs completing Phase 2's placeholders using the
   confirmed triples.
5. Write out, on paper, how Phase 0's restored procedure would apply to
   osx-64 (`pixi run configure` on real hardware → `gen-subst.sh`,
   already generic for macOS, no changes needed) — and explicitly flag
   that this one step (running real `configure` on real hardware/CI) is
   the *only* piece that genuinely requires hardware; everything else is
   confirmed mechanical by this point.
6. Record findings in a short written note (append here or a sibling
   `DRY_RUN_OSX64.md`) — the real triple, the exact diff, and the
   explicit remaining hardware-gated step list.

No `build.zig` changes, no smoke/contract/etc. re-verification — the
acceptance bar is that the note is concrete (real triples, not
placeholders) and required no guessing.

## Non-goals (explicit, to prevent re-litigation)

- No 4th platform is actually built or shipped this milestone.
- `CROSS_PLATFORM_STANDARDIZATION.md` §3's "do not unify" list stands
  unchanged: `buildWindows()` as a separate function, per-package Windows
  source-list substitutions, `fortranOne`'s per-OS compiler/flags shape
  (Phase 2 extends its *keying*, not its structure), `fixRpath`'s
  format-specific no-ops, the `R_HOME` layout difference.
- Windows-arch (win-arm64) parameterization is explicitly deferred
  (Phase 2).
- Windows front-end unification is explicitly out of this milestone
  (Phase 6) — recommended as its own follow-on.

## Verification discipline (recap)

After each phase that touches `build.zig` (Phases 1-4): full
`build`/`smoke`/`contract`/`check`(unix)/`install`/`package`/
`verify-package` on gamma, omicron, AND kappa — not just once at the
milestone's end, matching the project's established trust bar throughout
`FINALIZATION.md`/`TODO.md`. Phases 0, 5, 7 make no `build.zig` changes
and have their own narrower, stated verification bars.

## Task checklist (transcribe into a new `.github/devdocs/feat-cross-platform-standardization/TODO.md` when starting)

- [ ] Phase 0 — restore configure-only script/task; verify clean
      `subst.txt` diff on gamma
- [ ] Phase 1.1-1.6 — de-duplication helpers + `rspec.zig` cleanup
- [ ] Phase 1 full trust bar, all 3 machines
- [ ] Phase 2.1-2.4 — `Arch` field, `findFlangRt`, macOS gcc-root,
      linux-aarch64 Fortran-compiler-selection fix
- [ ] Phase 2 full trust bar, all 3 machines (highest-risk phase)
- [ ] Phase 3 — Windows generic `config_dir`, 3 literals removed
- [ ] Phase 3 trust bar (kappa full, gamma/omicron smoke-only)
- [ ] Phase 4.1-4.3 — Windows `subst.txt`, 5 lists → `applyLinkFlags`
- [ ] Phase 4 trust bar on kappa + F6.3 capability re-check
- [ ] Phase 5.1-5.3 — pixi.toml task, recipe.yaml comment, CI comment
- [ ] Phase 6 — front-end unification recommendation recorded (not
      implemented here)
- [ ] Phase 7 — real package inspection, written dry-run note committed
