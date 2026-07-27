# Milestone 5 — Finalization spec (for a later session)

This document is the pick-up point for finishing `build.zig`. It assumes a
**cold start**: read it top to bottom, then `PLAN.md` (architecture) and
`TODO.md` (what's already done) in this same directory. Everything here is
concrete — exact files, commands, and acceptance criteria — so a future
session can execute without re-deriving the design.

**Status (2026-07-24): F1–F4 are all green on linux-64** (trust bar,
hardening, full+openblas variants, distribution/CI integration — see the
per-phase status lines below and `TODO.md`'s finalization checklist for
exact detail, including the two subst-table bugs, the join-logic bug, and
the reproducibility leaks found and fixed along the way). **F5 (macOS) and
F6 (Windows) are the only phases left** — both need real remote test
hardware (omicron/kappa, see `[[test-servers]]` in memory), not just local
work, which is why they're picked up in a separate session/pass.

## Where things stand

- Branch: `worktree-feat-zig-build` (git worktree at
  `.claude/worktrees/feat-zig-build`). Changes are uncommitted by project
  policy ([[no-git-commits]] — the user commits).
- **Proven on linux-64, all three flavors**: `pixi run zig-build` (slim),
  `pixi run -e full zig-build`, and `pixi run -e openblas zig-build` each
  produce a complete R 4.6.1 with no autoconf and no make. Each passes
  smoke + `pixi run contract`/`zig-contract` + `pixi run zig-check` +
  `stage.sh`/`package-standalone.sh`/`verify-bundle.sh` (F4.1's adversarial
  moved-tree test). File layout is within one deliberate file
  (`bin/libtool`) of the make-installed tree. A `build-zig` CI job matrixes
  all three flavors in `.github/workflows/build.yml`, beside the existing
  autoconf `build` job (not yet observed on a real Actions run — no push
  access from the session that added it; confirm on the next push).
- Entry points: `build.zig` (root), `zigbuild/rspec.zig` (source
  inventory), `zigbuild/tools/gen-subst.sh` (subst.txt regeneration),
  `zigbuild/config/linux-x86_64-{slim,full}/` (vendored `config.h`,
  `Rconfig.h`, `subst.txt`, `GENERATED_FROM` — one dir per variant, since
  capabilities are compile-time), `scripts/zig-build.sh` (pixi wrapper,
  takes `-Dvariant`/`-Dblas` from `env.sh`'s `$VARIANT`/`$BLAS`),
  `scripts/zig-smoke.sh`/`zig-contract.sh` (test-script wrappers that
  resolve the zig prefix path so CI doesn't need to compute `$FLAVOR`
  itself).

### How to build / test what exists

```sh
pixi run zig-build                      # → dist/R-4.6.1-slim-zig
pixi run -e full zig-build              # → dist/R-4.6.1-full-zig
pixi run -e openblas zig-build          # → dist/R-4.6.1-slim-openblas-zig
pixi run zig-smoke                      # smoke test, resolves the prefix itself
pixi run zig-contract                   # Rcpp/data.table/minqa via Makeconf
pixi run zig-check                      # make-check-equivalent (Examples/Specific/Reg)
```
(swap `-e full`/`-e openblas` in front of `zig-smoke`/`zig-contract`/
`zig-check` too, to test those flavors.)

## What "finalized" means

Milestone 5 is **done** when the zig build can replace the autoconf/make +
gnuwin32 pipeline as the project's build system without regressing any
guarantee milestones 1–5 established. Concretely, all six phases below are
green. The gating one was **F1** — until R's own regression suite passes on
a zig-built R, the build is not trustworthy no matter how clean it looks
(now proven, see above).

Phases are ordered by dependency and value. F1–F4 are all on the
already-proven linux-64 platform (**done**); F5/F6 are the ports (do them
in order — F5 before F6).

---

## Phase F1 — Correctness on linux-64 slim (the trust bar)

**✅ DONE (2026-07-24).** `pixi run zig-check` (F1.1) and `pixi run
contract` (F1.2) both pass. Two real bugs found and fixed getting here —
see TODO.md's "Bugs found by F1.2" for the `AC_SUBST_FILE`/quote-unescaping
details. Kept below verbatim as the reference spec (still accurate to how
it was actually built).

The smoke test proves R *starts and computes*; it does not prove R is
*correct* or that it can *build packages*. Those are F1.

### F1.1 — `make check` (R regression suite) parity

**Why**: This is the acceptance bar for replacing autoconf. R's own
`tests/` suite is the reference-output comparison that catches miscompiles
(it's how milestone 2 found the gfortran-darwin SVD bug).

**Problem**: `make check` runs from a configured objdir's `tests/Makefile`
(one of config.status's `CONFIG_FILES`), which the zig build never
generates. The suite drives `../bin/R CMD BATCH` over `tests/*.R` and
diffs against `tests/*.Rout.save`.

**Approach** (pick the first that works):
1. **Generate the tests Makefiles via the existing subst path and run
   them.** `tests/Makefile`, `tests/Embedding/Makefile`,
   `tests/Examples/Makefile` are all `@VAR@` templates already handled by
   `substitute()` in `build.zig`. Add a `zig build check` step (separate
   from the default `r` step) that:
   - subst-generates the three `tests/*/Makefile` into a work dir
     (`build/zig-check/`), with `top_builddir` pointed at the zig prefix's
     `lib/R` and `R_HOME`/PATH set so `bin/R` resolves to the zig build;
   - runs `make -C build/zig-check` (make is still in the pixi env — this
     uses make as a *test runner*, not a build system, which is fine;
     retiring make from the build is the milestone, retiring it from the
     test harness is not required);
   - the reference `.Rout.save` files live in the source tree `tests/`, so
     `VPATH`/`srcdir` must point there.
2. If wiring the Makefiles is fiddly, fall back to invoking the same R
   expressions `tests/Makefile` uses (`tools:::.runPackageTests` is *not*
   the same thing — the base suite is driven by the Makefile's `R CMD
   BATCH` loop, so replicate that loop directly in a Run step).

**Acceptance**: the diff-against-`.Rout.save` comparisons that
`scripts/check-r.sh` produces on the make build are all empty on the zig
build. Wire a `pixi run zig-check` task mirroring `check-r.sh`.

**Gotchas**:
- `tests/Makefile.win` hardcodes `eval-etc-2.R` (needs recommended pkg
  Matrix); the unix path doesn't, so ignore that — but confirm no test
  pulls a recommended package (we build `--without-recommended-packages`).
- The internal-tzcode path means tests must run with `TZ=UTC` and the
  bootstrapped `share/zoneinfo` present (it is).
- If a numeric test fails, isolate whether it's a zig-cc codegen
  difference vs the make build (same compiler, so it shouldn't be) or a
  missing `-DHAVE_CONFIG_H`/include-order difference in some package lib.

### F1.2 — Contract test (package compilation via Makeconf)

**Why**: proves `etc/Makeconf` (which points at the `toolchain/zig-*`
shims) actually compiles CRAN packages against this R — the whole point of
baking the toolchain into Makeconf.

**How**: `scripts/contract-test.sh` currently hardcodes
`R_BIN="$OBJ_DIR/bin/Rscript"` (line 18). Add the same `R_TEST_R_BIN`-style
override already added to `smoke-test.sh`, point it at
`dist/R-4.6.1-slim-zig/lib/R/bin/Rscript`, and run it. It compiles Rcpp
(C++), data.table (C + OpenMP), and minqa (Rcpp + Fortran) from source.

**Acceptance**: `Contract test passed (slim/linux)`. This exercises the
zig-shim C/C++ path AND the flang Fortran path through R's package builder.

**Gotchas**:
- `zig` must be on PATH (the one external-tool contract — the shims call
  it). It is, inside pixi.
- The zig build's `etc/Makeconf` came from subst of `etc/Makeconf.in` via
  the vendored S-table, so it should carry the exact `CC=.../zig-cc` lines
  the make build had. Verify with `grep '^CC' dist/.../lib/R/etc/Makeconf`
  before debugging anything downstream.
- Watch for the double-`-lomp` / "duplicate linked dylib" class of bug if
  this is ever run on macOS (F5) — it's macOS-only but the shim logic that
  prevents it must be intact.

---

## Phase F2 — Production-hardening on linux-64

**✅ DONE (2026-07-24), all 5 subtasks.** Order actually used: F2.5 → F2.1
→ F2.4 → F2.3 → F2.2 (F2.5 first since F2.1's regen procedure needed it to
exist for real). Found and fixed real bugs in F2.2 (gzip timestamps +
`.install_package_description`'s `Sys.time()`) and F2.5 (a join-logic bug
producing corrupt mid-token quotes) — see TODO.md for both. F2.3's
`fixRpath` and F2.1's `checkConfigFreshness` are load-bearing parts of
`build.zig` now, not just one-off fixes.

Small, mostly-mechanical items that make the build releasable. None gate
F1 but all should land before declaring the milestone done.

### F2.1 — config.h staleness guard

**Why**: the vendored `config.h`/`subst.txt` are a pure function of
(platform, pixi.lock, R version). An R-version bump silently builds with
stale feature flags. PLAN.md's stated mitigation is a version guard —
implement it.

**How**: embed the R version the config was generated from (e.g. a
`zigbuild/config/linux-x86_64/GENERATED_FROM` file containing `4.6.1`), and
have `build.zig` compare it to `r_version` at configure time, erroring with
the regeneration procedure if they differ.

**Also document the regeneration procedure** (new section in PLAN.md):
1. Run the autoconf `pixi run configure` once for the new version.
2. Copy `build/obj-<ver>-slim/src/include/{config.h,Rconfig.h}` into
   `zigbuild/config/<plat>/`.
3. Regenerate `subst.txt` with the awk+sed pipeline recorded in F2.5.
4. Bump `GENERATED_FROM`.

### F2.2 — Reproducibility (SOURCE_DATE_EPOCH)

**Why**: the `Built:` DESCRIPTION stamps and Rversion.h currently use
`utcNow()` (wall clock), so two builds differ. TODO.md milestone 5's
reproducibility goal wants bit-for-bit.

**How**: honor `SOURCE_DATE_EPOCH` if set — `utcNow()` reads it instead of
the clock; the same value feeds any other timestamped output. Then verify:
build twice, `diff -r` the two prefixes, expect no differences except
known-nondeterministic RDS (investigate any that appear).

**Acceptance**: `SOURCE_DATE_EPOCH=<fixed> pixi run zig-build` twice into
two prefixes → identical trees (or a documented, understood short list).

### F2.3 — RUNPATH cleanup

**Why**: zig adds a relative `build/zig-cache/local/o/<hash>` entry to
RUNPATH ahead of the conda lib paths on every artifact it links against a
sibling (libR.so → libRblas.so, etc.). Harmless in place (stage.sh's
patchelf pass rewrites rpaths for distribution), but it's grit.

**How**: either (a) a `patchelf --remove-rpath`/`--set-rpath` post-link Run
step in `build.zig` that normalizes every `lib/R/lib/*.so` and
`lib/R/library/*/libs/*.so` to just the dual `$ORIGIN` + conda entries, or
(b) confirm and document that `stage.sh` already fully normalizes it and
leave the in-place tree as-is. Prefer (a) so the pre-stage tree is clean.

### F2.4 — bin/libtool decision

**Why**: the one file the zig tree is missing vs make. It's a 300KB
config.status-generated shell script. Nothing in the slim runtime,
`R CMD SHLIB` (Makeconf uses the shims, not libtool), smoke, or contract
uses it on Linux.

**How**: confirm via F1.2 that package compilation never invokes it, then
either generate it from `ltmain.sh` + the S-table for completeness, or
document it as intentionally dropped in the "Known deltas" list. Default:
drop it, with a one-line note, unless F1.2 proves something needs it.

### F2.5 — Record the subst.txt regeneration pipeline

**Why**: `subst.txt` was produced by a one-off awk+sed pipeline this
session; it must be reproducible for F2.1.

**How**: capture the exact pipeline into a committed script
(`zigbuild/tools/gen-subst.sh`) — it joins config.status's awk
continuation lines (`"\` + leading `"`) and rewrites the six machine paths
to `@ZR_*@` placeholders:
```
# from build/obj-<ver>-<flavor>/config.status:
awk '/^S\["/ { ... join continuation lines ... }' config.status \
  | sed -e 's|<CONDA_PREFIX>|@ZR_CONDA@|g' -e 's|<SRC>|@ZR_SRC@|g' \
        -e 's|<OBJ>|@ZR_OBJ@|g' -e 's|<PREFIX>|@ZR_PREFIX@|g' \
        -e 's|<TOOLCHAIN>|@ZR_TOOLCHAIN@|g' -e 's|<ROOT>|@ZR_ROOT@|g'
```
(The full working awk is in this session's scratchpad; the join is the
load-bearing part — a naive `grep '^S\['` drops multi-line values.)

---

## Phase F3 — Variants on linux-64

**✅ DONE (2026-07-24), both subtasks, first real build attempt each.**
Every full-variant capability (tcltk/readline/NLS/jpeg/tiff) needed far
less new code than this spec anticipated, because the same source files
were already being compiled unconditionally and the *vendored, per-variant
config.h* is what actually switches behavior — see TODO.md for the actual
per-capability breakdown (tcltk needed real new compile+link code and a
`concatRSources` exclude param; readline/NLS/jpeg-tiff needed only link
flags or nothing at all).

Once slim is trusted (F1) and clean (F2), extend to the other compile-time
profiles on the *same proven platform* before porting.

### F3.1 — full variant (`-Dvariant=full`)

**Why**: parity with the make build's `full` env (tcltk, readline, NLS,
jpeg, tiff).

**Design facts** (verified this session):
- full's `config.h` differs from slim's in **108 lines**, all NLS/gettext/
  argz (NLS pulls in libintl). So full needs its **own vendored
  `config.h`/`Rconfig.h`/`subst.txt`** — capture from `build/obj-4.6.1-full`
  exactly as slim's were captured (F2.5 script, `-full` flavor).
- Capabilities are compile-time, so this is a genuine second configure
  profile, not a flag toggle — mirror how `configure-r.sh`'s `VARIANT_ARGS`
  branch differs (`--with-tcltk --with-readline --enable-nls
  --with-jpeglib --with-libtiff`).

**How**: add a `variant` build option to `build.zig`
(`b.option([]const u8, "variant", ...)`, default "slim"), select the
config dir and extra package sources/libs by it:
- tcltk package gains a real `src/library/tcltk/src/*.c` shlib linked
  against conda tk (`--with-tcl-config`/`tkConfig.sh` equivalents → the
  tclConfig values are in full's S-table), and the R-code path switches
  from the `zzzstub.R` slim branch to the real `cat(RSRC)` branch.
- readline: `src/unix` gains readline/ncurses link; grep full's Makeconf
  for `READLINE_LIBS`.
- NLS: libintl link + `src/extra/intl` if `USE_INCLUDED_LIBINTL` (check
  full's config — conda `gettext` likely means system libintl, no
  `src/extra/intl` build). The `.mo` translation compile is a `msgfmt`
  step; check whether the make build actually compiles them or ships them.
- jpeg/tiff: grDevices gains `devQuartz`-adjacent jpeg/tiff device link
  (`libjpeg-turbo`, `libtiff`); grep full's grDevices Makefile `PKG_LIBS`.

**Acceptance**: `pixi run -e full zig-build` → smoke test asserts the full
capability profile (tcltk/jpeg/tiff/NLS **TRUE**), and F1 (`make check` +
contract) green for full.

**Wire pixi**: mirror the existing `full` environment; the zig-build task
should read `R_BUILD_VARIANT` (env.sh already computes `VARIANT`) and pass
`-Dvariant=$VARIANT` to `zig build`.

### F3.2 — openblas flavor (`-Dblas=openblas`)

**Why**: parity with the `openblas` pixi feature.

**How**: when `R_BLAS=openblas`, skip building `libRblas.so`/`libRlapack.so`
and instead link libR/modules/stats against conda `-lopenblas` (mirrors
`configure-r.sh`'s `BLAS_ARGS`). Separate prefix
(`dist/R-<ver>-slim-openblas-zig`, env.sh's `FLAVOR` already encodes this).

**Acceptance**: smoke test's BLAS assertion sees `libopenblas`; numerics
green. Lower priority than F3.1.

---

## Phase F4 — Distribution integration + CI (linux-64)

**✅ DONE (2026-07-24), both subtasks.** stage.sh/package-standalone.sh/
verify-bundle.sh ran completely unchanged against the zig prefix (one
naming-convention gotcha found, not a bug — see TODO.md). The CI job
(`build-zig` in `.github/workflows/build.yml`) is written and locally
verified but **not yet observed on a real GitHub Actions run** — confirm
on the next push before fully trusting it.

Make the zig build feed the existing distribution machinery and gate it in
CI. Do this after F1–F3 so CI gates a trustworthy build.

### F4.1 — stage.sh / package-standalone.sh consume the zig prefix

**Why**: the whole point — the zig build should produce the same staged
prefix the make build does, so `scripts/stage.sh`,
`package-standalone.sh`, and the conda recipe work unchanged downstream.

**How**: the zig build already installs the `<prefix>/lib/R` layout
`stage.sh` expects. Verify `stage.sh` runs clean against
`dist/R-4.6.1-slim-zig` (it does rpath rewriting, launcher fixes, the
`Sys.which`/`base.rdb` handling — all of which should already be satisfied
since the source patch is applied). Run the **adversarial moved-tree test**
(the milestone-1..5 standard): extract to a new path, delete the original,
`env -i PATH=/usr/bin:/bin`, exercise numerics + cairo PNG + `R CMD SHLIB`
+ `library(utils)`.

**Acceptance**: `scripts/verify-bundle.sh` green against a zig-built,
staged, packaged bundle.

**Gotcha**: `base::Sys.which()` bakes an absolute path into `base.rdb`
(compiled, not sed-able). The source patch in `scripts/zig-build.sh` (and
`configure-r.sh`) fixes this at the source, and `stage.sh` bundles a
`which` binary. Confirm `print(Sys.which)` on the zig-built R shows the
dynamic `R.home()`-relative expression, not a literal path — this is the
canonical tell for the whole class of baked-path bugs.

### F4.2 — CI job

**How**: add a `zig-build` matrix leg to `.github/workflows/build.yml`
(linux-64 first) running `pixi run zig-build` + smoke + `zig-check` +
contract. Keep it beside the autoconf legs — the autoconf path retires only
after F1–F6 are all green on all platforms.

---

## Phase F5 — macOS port (osx-arm64 / osx-64)

Port `build.zig` to macOS. gfortran instead of flang; Mach-O instead of
ELF. Everything here is a known quantity from milestone 2 + the macOS
staging work — reuse those lessons, don't rediscover them.

### F5.1 — Compile graph on macOS

- **Fortran = gfortran, not flang** (conda-forge ships no flang for osx).
  The flang Run steps become gfortran Run steps; FLIBS derivation differs
  (gfortran's private libdir under `lib/gcc/<triple>/`). Capture the exact
  FLIBS from `build/obj-<ver>-slim`'s Makeconf on omicron.
- **gfortran-darwin -O2 miscompiles complex LAPACK** (zgesdd, silent wrong
  SVD — milestone 2). Cap Fortran at `-O1` on macOS, exactly as
  `configure-r.sh` does (`FOPT=-O1` when `OS=macos && FC=gfortran`).
- **Vendor a macOS `config.h`/`subst.txt`** (`zigbuild/config/osx-arm64/`)
  captured from a real omicron autoconf build. `long double == double` on
  arm64 (don't assert `long.double` in smoke — it's already not asserted).
- **fd ulimit**: `ulimit -n 4096` before linking libR — macOS's 256
  default breaks zig's linker on ~300 objects (env.sh already does this for
  the make build; `zig-build.sh` must too on macOS).

### F5.2 — Mach-O relocation + codesigning

The staged tree needs the milestone-2 macOS treatment (already implemented
in `stage.sh`, so F4.1 should carry over):
- `install_name_tool` for dual `@loader_path` rpaths; conda dylibs use
  `@rpath/<name>` IDs, R's own libR.dylib/libRblas.dylib use bare names
  (resolved via `DYLD_FALLBACK_LIBRARY_PATH`, NOT `LD_LIBRARY_PATH` — dyld
  ignores the latter). `etc/ldpaths` must write the Darwin variable.
- **Mandatory ad-hoc codesigning** (`codesign --force --sign -`) after every
  `install_name_tool` — arm64 macOS refuses unsigned binaries. If
  `build.zig` itself does any post-link Mach-O surgery (F2.3 RUNPATH), it
  must re-sign; otherwise leave all Mach-O handling to `stage.sh`.
- Launchers: portable `readlink` loop (no `readlink -f` on BSD), and the
  POSIX leading-`(` case-pattern workaround for macOS's frozen bash 3.2.

**Acceptance**: build + smoke + `zig-check` + contract + moved-tree bundle
test all green on omicron (osx-arm64), to the same standard as linux.

**Test hardware**: omicron (macOS arm64) via SSH — see [[test-servers]].

---

## Phase F6 — Windows port (the endgame)

Replace `src/gnuwin32` + its `MkRules` fork with the single `build.zig`.
This is the hardest phase and the biggest prize; do it last, only after
F1–F5 are solid, because it's the one place the make build uses a
*different build system entirely* (gnuwin32, not autoconf), so there's no
`config.status` S-table to vendor — the substitution values must come from
gnuwin32's `MkRules`/`MkRules.local` instead.

### F6.1 — Windows compile graph

- **Fortran = MinGW gfortran** (conda-forge `gcc_impl_win-64`); one
  GNU/MinGW ABI across the whole toolchain (zig targets `-windows-gnu`).
- The zig-cc **GNU-ld emulation layer** (in `toolchain/zig-cc`) is needed
  for Windows links: `lib<n>.dll.a`/`lib<n>.lib` search, `-mwindows`
  implied GDI libs, gfortran private libdir. Since `build.zig` compiles C
  natively (not through the shim), that emulation must be **reimplemented
  as explicit link flags in build.zig** for Windows, OR the Windows target
  keeps routing links through the shim. Decide early — this is the crux of
  the Windows port.
- No `config.status` on Windows: the make build's Windows config comes from
  gnuwin32's `MkRules` defaults + the generated `MkRules.local`
  (`scripts/build-gnuwin32.sh`). Build a Windows `subst`-equivalent table
  by hand from those, plus a vendored Windows `config.h` (gnuwin32 ships
  `src/include/config.h.win`, not an autoconf-generated one — start there).

### F6.2 — Windows layout + known traps

- **`R_HOME` must be `<prefix>/Library/lib/R`, NOT `lib/R`** — NTFS is
  case-insensitive and collides with Python's `Lib` (env.sh already
  branches this; `build.zig` currently hardcodes `lib/R` — parameterize).
- **`ICU_PATH` must be set** so `src/extra/tzone/registryTZ.c` finds
  `unicode/ucal.h` (the 2026-07-23 bug — masked by an incremental dev
  objdir, exposed only by a clean build; the zig build is always clean, so
  this WILL surface — set it from day one).
- jpeg/tiff/tcltk are forced on (gnuwin32 has no off-switches → slim==full
  on Windows). Keep that parity caveat.
- gnuwin32 builds in-tree with no `make install`; the zig build installs
  into the prefix layout directly, which is actually *simpler* than the
  gnuwin32 manual-copy path.

**Acceptance**: build + smoke + `zig-check` + contract + bundle on kappa
(Windows 11) — see [[test-servers]]. This is the point where `build.zig`
truly is "one build system" and gnuwin32 + autoconf can both retire.

---

## Task checklist (transcribe into TODO.md when starting)

F1-F4 done 2026-07-24 — see TODO.md's finalization checklist for the full
detail (bugs found, exact verification commands, gotchas). This list is
kept for the phase-ordering overview; don't re-derive from here, it's a
summary of TODO.md, not the other way around.

- [x] **F1.1** `zig build check` step + `pixi run zig-check`; regression
      suite reference-output-clean on zig-built slim linux-64
- [x] **F1.2** contract test (Rcpp/data.table/minqa) green via
      `R_TEST_R_BIN` override against the zig prefix
- [x] **F2.1** config.h staleness guard + regeneration procedure in PLAN.md
- [x] **F2.2** SOURCE_DATE_EPOCH → reproducible; two-build diff clean
- [x] **F2.3** RUNPATH normalized (patchelf post-link or documented via
      stage.sh)
- [x] **F2.4** bin/libtool: generate or document-as-dropped (per F1.2)
- [x] **F2.5** `zigbuild/tools/gen-subst.sh` committed (subst.txt repro)
- [x] **F3.1** full variant: vendor full config, `-Dvariant=full`, tcltk/
      readline/NLS/jpeg/tiff; smoke+check+contract green for full
- [x] **F3.2** openblas flavor `-Dblas=openblas`
- [x] **F4.1** stage.sh/package/verify-bundle green on zig prefix
      (adversarial moved-tree test)
- [x] **F4.2** CI `zig-build` leg (linux-64) — written + locally verified;
      not yet observed on a real Actions run
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

## Gotcha catalog (carried from earlier milestones — do not rediscover)

| Symptom | Cause | Fix location |
|---|---|---|
| "could not find function rnorm" on a moved tree | `Sys.which` absolute path baked into `base.rdb` | source patch (in `zig-build.sh`) + `stage.sh` bundles `which` |
| macOS launch silently broken | dyld ignores `LD_LIBRARY_PATH`; needs `DYLD_FALLBACK_LIBRARY_PATH` | `stage.sh` ldpaths OS branch |
| arm64 macOS won't run binary | `install_name_tool` invalidates signature | `codesign --force --sign -` after every rewrite |
| complex SVD silently wrong on arm64 | gfortran-darwin -O2 miscompile | `-O1` cap for gfortran-on-Darwin |
| `unicode/ucal.h` not found (Windows) | `ICU_PATH` unset; only surfaces on a *clean* build | set `ICU_PATH` in the Windows config |
| "duplicate linked dylib libomp" | double `-lomp` (package + shim) | shim skips `-lomp` if caller already has it |
| tools loadNamespace "different internals" | `Meta/features.rds` missing (only `package.rds`) | run `.install_package_description` for tools (bootstrap already does) |
| macOS linker `ProcessFdQuotaExceeded` | 256 fd default, ~300 objects | `ulimit -n 4096` |
| make dies "missing separator" the moment a package compiles | `AC_SUBST_FILE` vars (`r_cc_rules_frag` etc.) are file-content substitutions, not `S["VAR"]` entries — silently vendored empty | hardcode the fixed heredoc content in `loadSubstTable` (F1.2) |
| package build: `'R.h' file not found` (quoting broken, not the path) | awk `\"` never unescaped when loading subst.txt | unescape `\"` → `"` too, not just `\$` → `$` (F1.2) |
| `subst.txt` regen produces a corrupt mid-token quote (e.g. `-l"m`) | continuation-line join kept the boundary quote instead of removing it | `sub(/"\\$/, "", full)`, not `"\""` (F2.5, `gen-subst.sh`) |
| two builds differ in `.afm.gz` files even with `SOURCE_DATE_EPOCH` set | `gzip -9f` embeds a wall-clock timestamp in the header regardless | add `-n` (F2.2) |
| two builds differ in every package's DESCRIPTION/Meta despite `SOURCE_DATE_EPOCH` | `tools:::.install_package_description()` calls `Sys.time()` unless given an explicit `builtStamp` arg | pass `utcNow()` through as the 3rd arg (F2.2) |
| RUNPATH has a bogus relative `build/zig-cache/local/o/<hash>` entry | zig adds an rpath for every sibling artifact it links against | `patchelf --set-rpath` post-link, keep only absolute entries (F2.3, `fixRpath`) |
| `package-standalone.sh`'s final `tar` step: "Cannot stat: No such file or directory" | it hardcodes the dist dir *basename* to `R-$R_VERSION-$FLAVOR`, doesn't go through `$PREFIX` — breaks if the prefix has zig-build's `-zig` coexistence suffix | point `R_INSTALL_PREFIX` at the unsuffixed name for verification; a non-issue once autoconf retires (F4.1) |
