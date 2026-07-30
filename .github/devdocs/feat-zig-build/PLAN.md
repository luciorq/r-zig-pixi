# feat-zig-build — Milestone 5: R built by `zig build` alone

**Status (2026-07-28): DONE, and then some — `zig build` is now the
project's default build path on linux-64, macOS (osx-arm64), and Windows,
including full package compilation there.** All six finalization phases
(F1-F6, see FINALIZATION.md) are green, the "Final" item (retiring
autoconf/gnuwin32 from the default path) is done, and F7 (the Windows
package-compilation contract — originally scoped OUT of this milestone
entirely) got done too, on direct request: `pixi run build`/`smoke`/
`contract`/`install`/`package`/`verify-package` all run the zig pipeline
and all pass on every platform now (`check`, R's regression suite, is
still unix/macOS-only — no equivalent step exists in the Windows compile
graph; `-e full`/`-e openblas` still select variant/BLAS flavor as
before). The old autoconf (unix) / gnuwin32 (windows) pipeline survives as
an explicit `*-legacy` fallback for one release, then removable.
`recipe/build.sh` (the real rattler-build release pipeline) drives
`zig-build.sh` too. See TODO.md's "Final", "F6.3", and "F7" entries for
the exact task/CI/recipe changes, the real Windows capability-profile bugs
(libcurl/ICU/cairo) found and fixed, and the package-compilation-contract
work (a native `gcc.exe`/`g++.exe` forwarder, a real `R.exe`, and three
wrong-by-default Makeconf.win values).
build.zig itself is fully cross-platform (`Os` enum, runtime-computed
platform/dylib-extension, gfortran-vs-flang Fortran dispatch, a real
`buildWindows()` compile graph) rather than hardcoded to linux. See
FINALIZATION.md for the phase-by-phase spec and status, and TODO.md for
exact bugs found/fixed and verification detail.

## Goal

Replace autoconf + make (and eventually gnuwin32) with a single `build.zig`
so the R build graph is owned by one tool. Original scope for this
feature branch: **a full working slim-variant R on linux-64, built
end-to-end by `zig build`, passing the existing smoke test** — no
`configure`, no `make`. That stop line was reached 2026-07-23; the branch
then continued through finalization (see FINALIZATION.md) and now also
covers the full variant, the openblas flavor, and CI/distribution
integration, all on linux-64. Ports to macOS/Windows are the remaining
work (F5/F6).

Dependencies still come from conda-forge through pixi (that is the point of
the project, not a compromise): third-party libs (cairo, pcre2, icu, …),
the Fortran compiler (flang — zig has no Fortran frontend), and the
userland the bootstrap R invocations need. What goes away is the *build
system*: autoconf's shell-driven feature detection, config.status
substitution, recursive make, and the `MkRules`/gnuwin32 fork on Windows
(later).

## What autoconf+make actually do for R (the inventory)

From the known-good milestone-1 objdir (`build/obj-4.6.1-slim`), the whole
build reduces to five jobs:

### 1. Feature detection → `src/include/config.h`

The only `config.status` *header* output. ~500 `HAVE_*`/sizeof macros.
**Decision: vendor the known-good per-platform `config.h`** (captured from
the milestone 1–3 builds) under `zigbuild/config/<platform>/config.h`
instead of reimplementing detection. Rationale: the pixi env is pinned, so
detection results are a pure function of (platform, pixi.lock, R version) —
re-running detection every build adds fragility, not information. A
regeneration path is documented (run the old configure once per R-version
bump, diff the result). Native `zig build` detection can replace individual
macros later if they ever need to vary.

### 2. File substitution (config.status `@VAR@` templates)

Everything else config.status generates is either a Makefile (dead once
make is gone) or one of these real files, all `@VAR@` substitution on `.in`
sources:

- `Makeconf` (build-tree) and `etc/Makeconf` (installed; the package-
  compilation contract — must keep pointing at `toolchain/zig-*` shims)
- `etc/Renviron`, `etc/ldpaths`, `etc/javaconf`
- `src/include/Rmath.h0` → `Rmath.h`
- `src/library/*/DESCRIPTION` (Built:/version fields)
- front scripts: `src/scripts/R.sh` → `bin/R`, `Rcmd`, `javareconf`,
  `mkinstalldirs`, `pager`, `rtags`
- made by make, not config.status, but same class: `src/include/Rversion.h`
  (version/date), `Rconfig.h` (distilled from config.h by a shell rule in
  `src/include/Makefile.in`)

**Decision (as implemented):** config.status's own `S["VAR"]="value"`
substitution table is vendored wholesale per platform
(`zigbuild/config/<plat>/subst.txt`, machine-specific paths parameterized
as `@ZR_*@` placeholders), and `build.zig` replays it over the pristine
`.in` templates at configure time — no helper tool needed, and template
processing is config.status-faithful by construction rather than by a
hand-maintained variable list. Rversion.h (tools/GETVERSION) and the
install-time seds on bin/R are reimplemented directly in zig.

### 3. The compile graph (what the objdir proves)

Static archives folded into libR:
`src/appl` (C + LINPACK-era `.f`), `src/nmath` (120 C), `src/extra/tre`,
`src/extra/tzone`, `src/extra/xdr`, `src/unix`.

Shared objects:
- `lib/libR.so` — src/main (101 C objs) + the static libs + FLIBS + LIBS
- `lib/libRblas.so` — `src/extra/blas/{blas,cmplxblas,lsame,zdotc,zdotu}.f`
- `lib/libRlapack.so` + `modules/lapack.so` — `src/modules/lapack`
  (`dlapack.f`, `cmplx.f`, `dlamch.f` at -O0…, wrappers in C)
- `modules/internet.so`
- base-package shlibs: `library/{stats(C+.f),graphics,grDevices(+cairo.so),
  grid,methods,parallel,splines,tools,utils}/libs/*.so`

Executables: `bin/exec/R` (Rmain.c, links libR + `-Wl,--export-dynamic`),
`bin/Rscript` (src/unix/Rscript.c).

**Decision:** C compiles natively in `zig build` (`addCSourceFiles`) — the
`zig-cc` shims are *not* used for R's own build anymore; their flags move
into build.zig explicitly:
- `-fno-sanitize=undefined` (zig cc traps UBSan by default; R's numeric
  code has benign UB — the single most load-bearing flag in the project)
- `-std=gnu23` (configure picked it via `CC=… -std=gnu23`)
- `-fopenmp` where Makeconf had it, with conda's `llvm-openmp` supplying
  `omp.h`/`libomp` (zig does the codegen but ships no runtime)
- soname on every shared lib (lld records literal paths otherwise; zig's
  Compile step sets DT_SONAME correctly on its own)
- `-fpic`, `-O2`, `-DHAVE_CONFIG_H`, include dirs `-I<obj>/src/include
  -I<src>/src/include -I$CONDA_PREFIX/include`

Fortran has no zig frontend: **flang runs as `Step.Run` producing `.o`
files** consumed via `addObjectFile()`. FLIBS
(`-lflang_rt.runtime -lm` from the conda clang lib dir) links into libR
and libRlapack exactly as Makeconf records today.

### 4. The R-level bootstrap (make's hidden second half)

`src/library/Makefile.in` + `share/make/{basepkg,lazycomp}.mk` install the
base packages *by running the freshly built R*: concatenate each package's
R sources per DESCRIPTION `Collate`, install `DESCRIPTION`/`NAMESPACE`/
`data`/`inst`, byte-compile + build lazy-load DBs (`tools:::makeLazyLoading`),
Rd DBs, and a strict ordering where `base` bootstraps first as plain
concatenated source and is lazy-loaded last. R is the build tool here and
that is inherent (packages are installed by R); make contributes only
sequencing. **Decision:** each bootstrap action becomes a `Step.Run` of
`bin/exec/R` (env: `R_HOME=<build tree>`) with the same R expressions the
mk files use, extracted verbatim during implementation. Dependency edges in
zig's step graph replace make's ordering.

### 5. Install layout

`make install` + our `stage.sh`. build.zig installs the same
`<prefix>/lib/R` layout into its own out dir; the existing `stage.sh`/
`package-standalone.sh`/recipe remain downstream consumers unchanged. Also
copied wholesale from the source tree: `share/`, `doc/`, `include/`
(public headers), `library/*/` non-code payloads, and `share/zoneinfo`
(internal tzcode; the unzip dance from milestone 1).

## What deliberately stays outside `zig build` (for now)

- **fetch**: `scripts/fetch-r.sh` (curl + checksum pin) still fetches the
  source tree; a `zig build fetch` step is a later nicety.
- **Fortran compiler**: flang from conda-forge, invoked by build.zig.
- **Third-party libs**: linked from the pixi env, not built from source.
  Building deps under zig too is a possible milestone 7, not this one.
- **The `toolchain/zig-*` shims**: no longer used to build R itself, but
  still written into `etc/Makeconf` — they remain the contract for
  *package* compilation (`R CMD SHLIB`) on the installed R.
- **smoke/check/contract test scripts**: unchanged; they validate the
  product, whoever built it.

## Layout (new pieces)

```
build.zig                  # the whole build graph, root of the repo
zigbuild/
  rspec.zig                # source inventory (from the make-vars dump)
  tools/gen-subst.sh       # regenerates subst.txt from a real config.status
  config/linux-x86_64-slim/
  config/linux-x86_64-full/     # F3.1: capabilities are compile-time, so
                                 # full is its own vendored config, not a
                                 # flag toggle
    config.h               # vendored configure feature detection
    Rconfig.h              # vendored (distilled from config.h by GETCONFIG)
    subst.txt              # vendored config.status S-table, parameterized
    GENERATED_FROM          # R version subst.txt/config.h were captured from
```

`pixi run zig-build` (scripts/zig-build.sh) wraps `zig build` so the pixi
env (flang, libs, tzdata…) is always present, applies the Sys.which source
patch, passes `-Dvariant=$VARIANT` (env.sh's `VARIANT`, itself
`R_BUILD_VARIANT` from the active pixi environment), and sets the prefix to
dist/R-<ver>-<flavor>-zig; zig cache stays in `build/zig-cache`.

## Regenerating the vendored config (per platform × variant × R version)

The vendored `config.h`/`Rconfig.h`/`subst.txt` in
`zigbuild/config/<plat>-<variant>/` are a pure function of (platform,
variant, pixi.lock, R version) — nothing in build.zig re-derives them at
build time. `GENERATED_FROM` records the R version they were captured
from; `build.zig`'s `checkConfigFreshness` compares it against `r_version`
on every `zig build` and errors with this same procedure if they've
drifted (an R version bump is the main trigger, but a pixi.lock update
that changes a detected library version, e.g. a cairo/pango bump that
changes `CAIRO_CPPFLAGS`, also warrants regenerating even though
`GENERATED_FROM` won't catch that case — rerun after any `pixi.lock`
change that touches a build dependency).

1. `pixi run configure` (slim) or `pixi run -e full configure` (full) —
   runs the real autoconf `configure` against the pixi env, writing
   `build/obj-<ver>-<variant>/config.status`. (Requires that objdir not
   already configured; `pixi run clean` first if it is stale.)
2. Copy the two headers:
   `cp build/obj-<ver>-<variant>/src/include/config.h zigbuild/config/<plat>-<variant>/`
   — `Rconfig.h` isn't written by `configure` itself (it's a `make` rule
   that shells out to `tools/GETCONFIG`); generate it directly instead of
   running `make`: `bash tools/GETCONFIG > zigbuild/config/<plat>-<variant>/Rconfig.h`
   (run from inside the objdir's `src/include`, or point `GETCONFIG`'s
   invocation at that `config.h` — it just reads `config.h` in the cwd).
3. Regenerate the substitution table:
   `pixi run bash zigbuild/tools/gen-subst.sh` (slim) or
   `pixi run -e full bash zigbuild/tools/gen-subst.sh` (full) — reads the
   matching-environment objdir's `config.status` (env.sh's `VARIANT`/
   `OBJ_DIR` already track which pixi env this runs under), joins its
   awk-style backslash-newline continuation lines (a naive `grep '^S\['`
   truncates multi-line values — verified this the hard way: it silently
   produced a corrupt `-l"m` mid-token the first time the join logic had
   an off-by-one in how it stitched line halves back together), and
   rewrites the six machine-specific absolute paths (`$CONDA_PREFIX`,
   `$OBJ_DIR`, `$SRC_DIR`, `$PREFIX`, `$TOOLCHAIN`, `$ROOT`,
   longest/most-specific first since they nest under `$ROOT`) to `@ZR_*@`
   placeholders, which `build.zig`'s `loadSubstTable` resolves back from
   the *current* env at `zig build` time. Writes to
   `zigbuild/config/<plat>-<variant>/subst.txt` automatically.
4. Bump `zigbuild/config/<plat>-<variant>/GENERATED_FROM` to the new
   version string.
5. Rebuild (`pixi run zig-build` / `pixi run -e full zig-build`) and
   re-run the full trust bar for that variant: smoke, `pixi run contract`,
   `pixi run zig-check` — a version/library bump can change feature flags
   in ways that only show up in one of the three.

## Risks / open questions

- **config.h staleness**: vendored headers are per (platform × R version);
  an R bump must regenerate them (documented procedure above, added
  2026-07-24) or silently build with stale feature flags. Mitigation:
  build.zig embeds the R version the header was generated from
  (`GENERATED_FROM`) and errors on mismatch (`checkConfigFreshness`).
- **Flag drift vs. the make build**: any flag the objdir's Makefiles carry
  that build.zig misses is a silent behavior change. Mitigation: derive
  flags from the objdir's generated Makefiles/Makeconf (they are the spec),
  and gate on smoke + `make check` parity before trusting.
- **`zig build` running R as a build step**: R writes into its own build
  tree during bootstrap (library/, doc/), which fights zig's
  cache/out-of-tree model. Plan: bootstrap into an explicit prefix dir
  (WriteFiles/InstallDir), treat R invocations as always-dirty steps keyed
  on their inputs.
- **gfortran platforms (macOS/aarch64)** and **Windows/gnuwin32** are out
  of scope here; the build.zig is written with a platform table from day
  one so they slot in later.
- **`make check` parity** is the real acceptance bar for replacing the
  autoconf build permanently; this branch's stop line is smoke-test green
  (slim, linux-64), with check parity tracked in TODO.
