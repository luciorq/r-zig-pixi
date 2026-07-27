# Milestone 5 — Finalization spec (for a later session)

This document is the pick-up point for finishing `build.zig`. It assumes a
**cold start**: read it top to bottom, then `PLAN.md` (architecture) and
`TODO.md` (what's already done) in this same directory. Everything here is
concrete — exact files, commands, and acceptance criteria — so a future
session can execute without re-deriving the design.

**Status (2026-07-27): F1–F5 are all green, on linux-64 AND macOS
(osx-arm64)** (trust bar, hardening, full+openblas variants,
distribution/CI integration, and now the macOS port — see the per-phase
status lines below and `TODO.md`'s finalization checklist for exact
detail, including the two subst-table bugs, the join-logic bug, the
reproducibility leaks, and the two macOS-only linking bugs found and fixed
along the way). **F6.1 (Windows compile graph) is now green too**:
`zig build` on kappa produces R.dll/Rblas.dll/Rlapack.dll/Rgraphapp.dll/
Riconv.dll/lapack.dll/Rscript.exe, and `Rscript.exe --version` runs
correctly. **F6.2 (Windows bootstrap/layout) is what's left** — Rscript.exe
can't yet evaluate any real R code (`-e "1+1"` exits 10) because
`buildWindows()` doesn't stage the R library or lazy-load base packages
yet; see F6.1/F6.2 below for the full gotcha catalog from getting the
compile graph green.

## Where things stand

- Branch: `worktree-feat-zig-build` (git worktree at
  `.claude/worktrees/feat-zig-build`). Changes are uncommitted by project
  policy ([[no-git-commits]] — the user commits).
- **Proven on linux-64 AND macOS (osx-arm64, on omicron), all three
  flavors**: `pixi run zig-build` (slim), `pixi run -e full zig-build`,
  and `pixi run -e openblas zig-build` each produce a complete R 4.6.1
  with no autoconf and no make, on both platforms. Each passes smoke +
  `pixi run contract`/`zig-contract` + `pixi run zig-check` +
  `stage.sh`/`package-standalone.sh`/`verify-bundle.sh` (F4.1/F5.2's
  adversarial moved-tree test, including the R CMD SHLIB/dyn.load check).
  File layout on linux is within one deliberate file (`bin/libtool`) of
  the make-installed tree. A `build-zig` CI job matrixes linux+macOS ×
  default/full (openblas stays linux-only in CI, matching the autoconf
  `build` job's own scope, even though it's verified working on macOS too)
  in `.github/workflows/build.yml`, beside the existing autoconf `build`
  job (not yet observed on a real Actions run — no push access from the
  session that added it; confirm on the next push).
- Entry points: `build.zig` (root — now genuinely cross-platform: `Os`
  enum + `platform`/`dylib_ext` computed at runtime from the resolved
  target, not a hardcoded linux constant), `zigbuild/rspec.zig` (source
  inventory), `zigbuild/tools/gen-subst.sh` (subst.txt regeneration, OS-
  aware since F5.1), `zigbuild/config/{linux-x86_64,osx-arm64}-{slim,full}/`
  (vendored `config.h`, `Rconfig.h`, `subst.txt`, `GENERATED_FROM` — one
  dir per platform × variant, since capabilities are compile-time),
  `scripts/zig-build.sh` (pixi wrapper, takes `-Dvariant`/`-Dblas` from
  `env.sh`'s `$VARIANT`/`$BLAS`, now allows macOS through),
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

Phases are ordered by dependency and value. F1–F4 (linux-64) and F5
(macOS) are **done**; F6 (Windows) is the last port.

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

**✅ DONE (2026-07-27), both subtasks, on omicron/osx-arm64, all three
flavors (slim/full/openblas).** Two real bugs found beyond what this spec
anticipated (both in build.zig, both macOS-only, see TODO.md's "Bugs found
by F5.1"): base packages need zig's `linker_allow_shlib_undefined` (the
Mach-O equivalent of ELF's tolerance for undefined shlib symbols), and the
`full` variant needs an explicit `LIBINTL`/`-framework` link that isn't
needed on linux (macOS's libc has no native gettext, unlike glibc) — its
absence didn't fail the *link* (dynamic_lookup masked it) but crashed R
with a null-pointer SIGSEGV the instant startup code called gettext for
the first time. `platform`/`dylib_ext` are now computed at runtime from
the resolved target instead of a hardcoded linux constant, so build.zig
itself, not just the vendored config, is genuinely cross-platform now.

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

### F6.0 — Scoping decision: CLI/headless only, no GUI front-ends (2026-07-27)

**Decision: build `R.dll` + `Rblas.dll`/`Rlapack.dll` + `Rgraphapp.dll` +
`Riconv.dll` + `Rscript.exe` only. Do NOT build `Rgui.exe`, `Rterm.exe`,
the `R.exe`/`Rcmd.exe` dispatchers, `RSetReg.exe`, or `open.exe`.** This
matches the project's existing `slim` philosophy on linux/macOS (headless,
CLI-focused, drop interactive-only surface) and was reachable without
guessing, by checking what the project's own test scripts actually invoke
on kappa's existing gnuwin32 checkout (not assumed):

- `scripts/smoke-test.sh` and `scripts/contract-test.sh` both hardcode
  `bin/x64/Rscript.exe` (with a `bin/Rscript.exe` fallback) as `$R_BIN` —
  neither ever touches `R.exe`, `Rterm.exe`, `Rgui.exe`, or `Rcmd.exe`.
- Package compilation (what `contract-test.sh` actually exercises —
  Rcpp/data.table/minqa) is driven by `install.packages()` /
  `tools:::.install_packages()`, R-level code that calls the configured
  compiler via `system()` directly. `Rcmd.exe` is a convenience shell
  substitute for typing `R CMD ...` at a raw `cmd.exe` prompt — package
  builds never depend on it existing as a binary.
- The regression suite (`zig-check`) is *our own* harness (F1.1's
  `addCheckStep`), not gnuwin32's `tests/Makefile.win` — we already choose
  what "R" means for it (can point at `Rscript.exe --vanilla` directly, no
  need for a separate `R.exe`).

**What can't be dropped, verified by reading `src/gnuwin32/Makefile`'s
own `CSOURCES`/`R-DLLLIBS`, not assumed:** `R.dll`'s required source list
is `console.c dynload.c editor.c embeddedR.c extra.c opt.c pager.c
preferences.c psignal.c rhome.c rt_complete.c rui.c run.c shext.c
sys-win32.c system.c dos_wglob.c` — this **includes** `console.c`/
`editor.c`/`pager.c`/`preferences.c`/`rui.c`/`run.c`, the same files that
look Rgui-exclusive at a glance. Unlike linux/macOS (where readline/tcltk
are separable link-time additions to an otherwise self-contained
`sys-unix.c`), gnuwin32 built `R.dll` as one monolithic library that
architecturally bakes in the console/GUI plumbing as required compile
units — there is no source-level slim/full split available *inside*
`R.dll` itself (matches the pre-existing "slim==full on Windows,
gnuwin32 has no off-switches" note below, just deeper than previously
documented). `R.dll`'s own `R-DLLLIBS` also links `-lRgraphapp`
unconditionally — so `Rgraphapp.dll` (`src/extra/graphapp/`, a `$(wildcard
*.c)` full Win32 GUI-widget toolkit — buttons/menus/dialogs/tooltips/
windows, ~30 files, no internal slim switch either) is a genuine, required
*link-time* dependency of `R.dll`, not optional GUI plumbing we can skip
building. It is however **not exercised at runtime** by `Rscript.exe`'s
actual execution path (R.dll's console/window-creation code is simply
never invoked when driven via `Rscript.exe` with `R_Interactive=FALSE` —
this is exactly how stock R already behaves: `Rscript.exe` never pops up a
window today either, on any R distribution).

**Net effect of the decision**: the real simplification is dropping the
*executables* (`Rgui.exe`/`Rterm.exe`/`R.exe`/`Rcmd.exe`/`RSetReg.exe`/
`open.exe` and their private objects — `graphappmain.o`, `rgui.o`,
`rterm.o`, `rcmd.o`, `rcmdfn.o`, icon/manifest resources), not the
`R.dll`/`Rgraphapp.dll` dependency graph, which must be built in full
either way. Still a meaningful win: fewer link targets, no resource-file/
manifest compilation, no `-mwindows` GDI implicit-library handling to
replicate (that's `Rgui.exe`/`Rterm.exe`-only), smaller final distribution.
One more small required library found while tracing `R.dll`'s link line:
`Riconv.dll` (`src/extra/win_iconv/`, R's own bundled iconv — gnuwin32
predates a good native Windows iconv option; build from source rather than
risk an ABI/symbol-name mismatch substituting conda's `libiconv`, since
`R.dll` calls `Riconv`-prefixed symbols matching this specific API, not
`iconv_open`/`iconv`).

### F6.1a — Ground-truth spec extraction (2026-07-27, from kappa's existing gnuwin32 build)

Before writing new build.zig code, extracted the actual object/source
list the same rigorous way Milestone 5's original Phase 0 did for linux
(from a real, already-built objdir — `~/r-zig-pixi/build/R-4.6.1` on
kappa, a working gnuwin32+zig-cc-shim build from milestone 3, NOT the
`~/r-zig-pixi-zig-build` dir used for the new zig-native work) — rather
than hand-parsing gnuwin32's recursive Makefile system (conditionals +
wildcards make that error-prone without a ground truth to check against).

Per F6.0, only the subset needed for `R.dll` + `Rblas.dll`/`Rlapack.dll` +
`Rgraphapp.dll` + `Riconv.dll` + `Rscript.exe` matters (skip everything
private to `Rgui.exe`/`Rterm.exe`/`Rcmd.exe`/`RSetReg.exe`/`open.exe`):

- **`R.dll` core (18 files, gnuwin32-only, no unix equivalent)**:
  `console.c dynload.c editor.c embeddedR.c extra.c opt.c pager.c
  preferences.c psignal.c rhome.c rt_complete.c rui.c run.c shext.c
  sys-win32.c system.c dos_wglob.c` + `dllversion.o` (a compiled Windows
  resource, not proper C). Confirms F6.0's finding that these are
  unavoidable, required `R.dll` compile units.
- **`R.dll` also statically links**: `src/main` (`libmain.a`), `src/appl`
  (`libappl.a`), `src/nmath` (`libnmath.a`) — **the same source files
  already in `rspec.main_c`/`appl_c`/`nmath_c`**, just compiled for the
  MinGW target. Also `src/extra/xdr`, `src/extra/tzone`, `src/extra/tre` —
  **also already in `rspec.xdr_c`/`tzone_c`/`tre_c`**, reusable as-is.
  Genuinely new-to-Windows: `src/extra/intl` (21 files — real
  bundled-gettext implementation; recall F5.1 found macOS needs
  `-lintl`+CoreFoundation instead, and linux needs neither — Windows is
  a *third* distinct NLS story, its own compiled library) and
  `src/extra/trio` (2 files — a `printf`-family replacement library,
  needed because MinGW's own printf has historically had
  format/rounding quirks R depends on not matching glibc's).
- **`Rgraphapp.dll`**: 31 object files, `src/extra/graphapp/*.c`
  (`$(wildcard)`, no partial-build option — matches F6.0's finding that
  it can't be selectively pruned).
- **`Riconv.dll`**: exactly 1 file, `src/extra/win_iconv/win_iconv.o` —
  small, low-risk to build from source as planned in F6.0.
- **BLAS/LAPACK: a genuinely different source layout from linux/macOS,
  not the same `rspec.blas_f`/`rlapack_f90_ordered` lists.** BLAS is just
  5 files (`blas.f`, `blas2.f90`, `cmplxblas.f`, `cmplxblas2.f90`,
  `blas00.c`) — far fewer than unix's per-routine split, gnuwin32
  aggregates BLAS into a handful of bundled files. LAPACK is even more
  aggregated: **a single `dlapack.f`** (vs. unix's ~15 separate
  `rlapack_f90_ordered`/`rlapack_f` files) plus `Lapack.c` and
  `accelerateLapack.c` producing `modules/lapack.dll` (a loadable module,
  matching unix's `modules/lapack.so` pattern) — `Rblas.dll`/`Rlapack.dll`
  themselves are separate from this module, need their own link recipe
  (not yet fully traced — next step for whoever picks this up).

**Net assessment**: this is comparable in size to the *original* Milestone
5 Phase 0–4 effort (the whole autoconf/make replication that happened
*before* F1's finalization work started), not a quick follow-on the way
F5's macOS port was — macOS reused the exact same `unix/*` source set and
front-end (`Rmain.c`/`Rscript.c`) as linux, needing only link-flag and
Fortran-compiler changes. Windows needs a materially new, second compile
graph (the 18-file `R.dll` core, 31-file `Rgraphapp.dll`, its own intl/
trio libraries, and a differently-shaped BLAS/LAPACK) layered on top of
the *reused* `main`/`appl`/`nmath`/`xdr`/`tzone`/`tre` groups. Picking
this up: don't restart the ground-truth extraction above — it's already
done and captured here; go straight to writing the build.zig code against
these confirmed source lists, verifying against kappa's existing working
build (`~/r-zig-pixi/build/R-4.6.1`, its actual DLL exports/imports via
`objdump`/`dumpbin`) at each step, the same iterate-on-real-errors
discipline that worked for F5.

### F6.1 — Windows compile graph — RESOLVED (2026-07-27)

`zig build` on kappa now produces a working R.dll + Rblas.dll + Rlapack.dll
+ Rgraphapp.dll + Riconv.dll + lapack.dll (module) + Rscript.exe, and
`Rscript.exe --version` runs correctly (proves the whole DLL dependency
chain loads at runtime, not just links). `-e` expression evaluation still
fails (exit 10, no output) — expected, since `buildWindows()`'s install
step doesn't yet stage R's library tree or lazy-load base packages
(F6.2's job, not yet started).

Gotchas found via real build attempts on kappa, each fixed in `build.zig`,
roughly in the order hit:

- **Missing headers via include-path ordering** (same root cause,
  multiple sites): module-level `addIncludePath` calls precede a compile
  group's own "extra" `-I` flags in the actual invocation, so a
  same-named file elsewhere on the path can shadow the intended one.
  Hit for: graphapp's own `internal.h` (shadowed by `src/include/
  internal.h`), `win_iconv.c`'s `<iconv.h>` (shadowed by conda-forge's
  real libiconv header — needs `src/gnuwin32/fixed/h/iconv.h` first),
  and R's own `psignal.h`/`trioremap.h`/`rgui_UTF8.h`/`run.h`/
  `dos_wglob.h`/`devWindows.h` (all need specific `-I` dirs: `src/
  gnuwin32/fixed/h`, `src/gnuwin32`, `src/library/grDevices/src`,
  `src/gnuwin32/front-ends` for Rscript.c's `#include "rterm.c"`).
- **Missing Win32 import libs gcc implicitly links via `-mwindows`**:
  `gdi32`/`user32` (Rgraphapp.dll, R.dll) and `comdlg32` (Rgraphapp.dll's
  common-dialog APIs) — gcc's own mingw driver spec adds these
  implicitly, zig cc/lld does not.
  - **conda-forge Windows lib naming quirks**: `libbz2.lib` (not
    `bz2.lib` — zig's dynamic search tries `{name}.lib`/`lib{name}.a`,
    not `lib{name}.lib`, so link as `"libbz2"`), and `libgfortran.dll.a`/
    `libquadmath.dll.a`/`libgcc*.a` living under a gcc-VERSION-specific
    subdir (`Library/lib/gcc/x86_64-w64-mingw32/<ver>/`), not directly
    under `Library/lib` — found the dir at build-config time by scanning
    for the one subdirectory containing `libgfortran.dll.a` (mirrors
    `findFlangRt`'s pattern for linux), not hardcoded.
- **Missing Windows-only source files**: `src/main/mkdtemp.c` (Windows
  has no native `mkdtemp`), `src/extra/tzone/registryTZ.c` (on top of
  unix's `localtime.c`/`strftime.c`), `src/gnuwin32/getline/{getline,
  wc_history}.c` (console history — `wgl_hist_*`).
- **`libintl.h` vs `libgnuintl.h`**: R's own Makefile.win does `cp
  libgnuintl.h libintl.h` (both names needed) — vendoring only the
  former left angle-bracket `#include <libintl.h>` (in `win-nls.h`)
  falling through to conda-forge's REAL gettext package header instead,
  which redefines `fprintf`/`vfprintf`/`setlocale` to `libintl_*` names
  our own compiled intl sources (built with R's own `HAVE_POSIX_PRINTF=1`,
  which disables that exact redefinition) never define — a genuinely
  confusing one, only resolved by tracing exactly which header's macros
  were active for the failing translation unit.
- **`mod_lapack` (lapack.dll) never linked the real `libR`** — unlike
  the unix build, which does; needed for the R API calls
  (`Rf_getAttrib`, `R_PPStack`, `R_chk_calloc`, ...) `Lapack.c` makes.
  Required reordering `buildWindows()` so `libR` is built before
  `lapmod`, since Zig's build graph needs the `*Step.Compile` value to
  exist before it can be passed to `linkLibrary`.
- **The big one — `libgfortran.a`'s runtime-support symbols**
  (`__gthr_win32_create/join/self`, `__emutls_get_address`,
  `_Unwind_GetIPInfo`/`_Unwind_Backtrace`, needed only by Rlapack.dll's
  f90-module LAPACK code, not Rblas.dll's/R.dll's plain f77 objects):
  `nm` proved all six are real, defined exports of
  `libgcc_s_seh-1.dll` (via `libgcc_s.a`, its import lib), but no
  combination of `-lgcc`/`-lgcc_eh`/`-lgcc_s` (any order, any
  repetition/"sandwich" pattern) got lld-link to actually resolve them.
  First workaround — extracting the exact archive members defining each
  symbol via `nm -A`/`ar p` and feeding them as plain `addObjectFile`
  inputs — got everything to **link**, but the resulting R.dll then
  failed to **load** at runtime with `STATUS_DLL_NOT_FOUND`
  (`-1073741511`): hand-picking individual thunk objects (plus the
  `_head_libgcc_s_seh_1_dll`/`libgcc_s_seh_1_dll_iname` anchor members,
  each surfacing only once the previous fix revealed the next missing
  link) skips whatever else a real dlltool-built import archive bundles
  (null-descriptor/null-thunk terminator members), which lld-link's own
  linking didn't need but the real Windows loader does. Root-caused via
  a minimal `LoadLibraryA` C test program + `objdump -p` dependency
  dumps on kappa, isolating it from a red herring (an unrelated `ar`/nm
  process-locking flake and an MSYS `as.exe`-over-non-interactive-ssh
  hang, neither of which was the actual bug). **Fixed** by generating a
  fresh, complete import library through `dlltool` directly (a
  synthetic `.def` + `--dllname libgcc_s_seh-1.dll`, same mechanism
  `winMakeImportStub` already uses for the R.dll↔Rblas.dll circular
  dependency) instead of extracting fragments of the real one — see
  `winMakeImportLibFor` in `build.zig`.
- Also found along the way, not yet re-verified with a passing build at
  the time: `zig cc`'s "coff does not support linking multiple objects
  into one" (`b.addObject()` can't merge multiple C sources into one
  COFF object, unlike ELF/Mach-O) — worked around by compiling the R.dll
  stub as a single-file object instead of a merged one (see the
  R_stub/`winMakeImportStub` code in `build.zig`).

### F6.1 — Windows compile graph (original pre-implementation notes)

- **Fortran = MinGW gfortran** (conda-forge `gcc_impl_win-64`); one
  GNU/MinGW ABI across the whole toolchain (zig targets `-windows-gnu`).
- **Resolved**: the zig-cc **GNU-ld emulation layer** (in `toolchain/
  zig-cc`) cannot be "routed through" for the native compile graph — it's
  a wrapper around invoking `zig cc` as a *subprocess*, but `build.zig`'s C
  compile graph uses zig's in-process Module/Compile API, a fundamentally
  different code path that never shells out to a `zig cc` process at all.
  So Windows linking needs the **lib<n>.dll.a/lib<n>.lib search** and
  **`-mwindows` implied GDI libs** logic reimplemented as explicit
  build.zig link-flag handling, same pattern as F5.1's macOS
  `linker_allow_shlib_undefined`/`LIBINTL` fixes (find the missing
  resolution from a real build attempt's error output, fix in build.zig,
  not in a shell shim). gfortran's private libdir (already solved
  generically by F5.1's `linkFortranRt`/FLIBS-from-subst-table pattern)
  needs the Windows FLIBS captured the same way.
- No `config.status` on Windows: the make build's Windows config comes from
  gnuwin32's `MkRules` defaults + the generated `MkRules.local`
  (`scripts/build-gnuwin32.sh`). Build a Windows `subst`-equivalent table
  by hand from those (`LOCAL_SOFT`, `ICU_PATH`, `CAIRO_CPPFLAGS`/
  `CAIRO_LIBS`, `TCL_HOME`/`TCL_VERSION` — all derived directly from
  `$CONDA_PREFIX`, no configure step involved), plus a vendored Windows
  `config.h`. Simpler than expected: gnuwin32 ships a **static, ready-to-
  use** `src/gnuwin32/fixed/h/config.h` (NOT autoconf-generated, and not a
  template needing ~500 substitutions like `config.h.in`) — it has exactly
  **3** `@VAR@` placeholders (`@CC_VER@`, `@FC_VER@`, `@VERSION@`, all
  informational version strings), verified by grepping the file directly
  rather than assuming. Vendor it close to as-is; `Rconfig.h` still comes
  from running `tools/GETCONFIG` against it (that script is OS-agnostic).

### F6.2 — Windows layout + known traps

- **`R_HOME` must be `<prefix>/Library/lib/R`, NOT `lib/R`** — NTFS is
  case-insensitive and collides with Python's `Lib` (env.sh already
  branches this; `build.zig` currently hardcodes `lib/R` — parameterize).
- **`ICU_PATH` must be set** so `src/extra/tzone/registryTZ.c` finds
  `unicode/ucal.h` (the 2026-07-23 bug — masked by an incremental dev
  objdir, exposed only by a clean build; the zig build is always clean, so
  this WILL surface — set it from day one).
- jpeg/tiff/tcltk are forced on (gnuwin32 has no off-switches → slim==full
  on Windows). Keep that parity caveat. Independent of, and not resolved
  by, F6.0's GUI-executable scoping decision — that's about which
  *binaries* get built, not grDevices' own capability set.
- gnuwin32 builds in-tree with no `make install`; the zig build installs
  into the prefix layout directly, which is actually *simpler* than the
  gnuwin32 manual-copy path.
- Per F6.0: no `Rgui.exe`/`Rterm.exe`/`R.exe`/`Rcmd.exe` — skip
  `graphappmain.o`, `rgui.o`, `rterm.o`, `rcmd.o`, `rcmdfn.o`, and the
  per-exe icon/manifest resource compiles entirely. `R.dll`'s own
  `CSOURCES` and `Rgraphapp.dll` are still built in full (see F6.0 for
  why they can't be pruned); only `Rscript.exe` needs building as a
  front-end (from the same `unix/Rscript.c` linux/macOS already use, plus
  a trivial compiled icon resource).

**Acceptance**: build + smoke + `zig-check` + contract + bundle on kappa
(Windows 11) — see [[test-servers]]. `smoke`/`contract`/`zig-check` all
already only require `Rscript.exe` (verified per F6.0), so this is
unaffected by the narrower binary scope. This is the point where
`build.zig` truly is "one build system" and gnuwin32 + autoconf can both
retire (for the CLI/headless surface this project targets — not a
byte-for-byte replacement of every gnuwin32 executable).

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
- [x] **F5.1** macOS compile graph (gfortran, -O1 cap, vendored osx config,
      fd ulimit) — done 2026-07-27 on omicron, all 3 flavors
- [x] **F5.2** macOS Mach-O relocation + ad-hoc codesign; omicron green
      — done 2026-07-27, full adversarial bundle test included
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
| `zig build` on macOS: "undefined symbol" linking every base package | Mach-O's lld doesn't tolerate undefined shlib symbols by default, unlike ELF | `linker_allow_shlib_undefined = true` on every `addLibrary` (F5.1, `addSharedLib`) |
| macOS `full` variant: SIGSEGV (null function pointer) on the very first bootstrap R call | macOS libc has no native `gettext()` (unlike glibc) — `LIBINTL="-lintl -Wl,-framework -Wl,CoreFoundation"` on macOS wasn't applied; masked at *link* time by the `-undefined dynamic_lookup` fix above, so it only crashed at runtime | apply `LIBINTL` in `linkCoreLibs`; also fix `applyLinkFlags` to handle `-framework X` pairs (it silently dropped them before) (F5.1) |
| `lldb` refuses to attach over SSH: "cannot get permission to debug processes" | non-interactive SSH sessions can't get macOS debug entitlements | use `~/Library/Logs/DiagnosticReports/*.ips` instead (JSON body after a one-line header) |
