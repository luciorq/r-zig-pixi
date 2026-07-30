# Cross-platform standardization review (2026-07-28)

**Status: review only, no code changes.** Requested after F1-F7 + Final +
the conda republish all went green on linux-64/macOS/Windows: now that the
build genuinely works on all three OSes, where is `build.zig` branching on
`ctx.os` out of real necessity (a genuine platform difference: PE vs ELF vs
Mach-O, MinGW ABI vs glibc, gnuwin32's own source tree vs autoconf/make's),
and where is it branching out of *habit* — duplicated logic that could be
one code path parameterized by a value, not two (or three) separate
implementations? The goal is to "leverage Zig's own standard build-system
primitives and conda packages consistently," per the request — i.e. reduce
the accidental complexity, not the load-bearing kind.

Every finding below is backed by an exact line reference in the `build.zig`
that shipped after F7 (2026-07-28), not guessed. Findings are grouped by
confidence/risk, cheapest and safest first.

## 0. What's already well-unified — do not disturb

Worth stating explicitly so a future pass doesn't "fix" something that
isn't broken:

- **`bootstrap()`** (build.zig:2541) — the ~40-step sequenced R-level
  bootstrap chain, the single riskiest part of this whole build to get
  subtly wrong per-platform — is **one function**, called identically from
  both `build()` (unix/macOS) and `buildWindows()`. This is exactly the
  right shape: OS-specific *path* differences are handled with small
  R_ARCH-aware conditionals *inside* the shared function, not by
  duplicating the whole sequence. This is the template every other
  unification below should be measured against.
- **`stageLibraryPayload()`** (build.zig:2187) already takes an
  `os_subdir`/`os_stamp` parameter and is called by both
  `installStaticTree` (unix) and `installLibraryWindows` (windows) — the
  base-package `library/` tree staging is genuinely one code path.
- **`applyLinkFlags`/`newCMod`/`addCGroup`/`linkOmp`/`linkFortranRt`** are
  each single functions with an internal `switch (ctx.os)` — the right
  granularity (branch at the smallest point that actually differs, not by
  duplicating the caller).
- **`Os` enum + `platform`/`dylib_ext` computed once from the resolved
  target** (build.zig:150-187) — no hardcoded linux assumptions baked in
  anywhere upstream of this; this was the whole point of F5's macOS-port
  refactor and it's held up through F6/F7 without needing to be revisited.

## 1. Safe, mechanical wins (pure refactor, zero behavior change)

### 1a. A single conda-path helper, used everywhere

The pattern `if (ctx.os == .windows) "{conda}/Library/X" else "{conda}/X"`
(or the `switch (ctx.os) { .windows => ..., else => ... }` equivalent) is
independently re-derived at **at least 8 call sites**:

| Line | Function | What it's building |
|---|---|---|
| 209 | top-level `build()` | `rhome` (`Library/lib/R` vs `lib/R`) |
| 1685/1688 | `newCMod` | library search path |
| 1750 | `addCGroup` | `-I` conda include path |
| 1802/1804 | `linkOmp` | libomp search path |
| 1223-1224 | winCairo block | `-I.../include/cairo`, `-I.../include/freetype2` |
| 1350 | `installWindowsCompilerContract` | MinGW binutils source path |
| 1362 | same | toolchain install-dir absolute path |
| 1655 | `findGfortranLibDir` | gcc-versioned libdir search |

This is conda-forge's own real, unavoidable Windows-vs-unix packaging
convention (`Library/{bin,lib,include}` vs flat `{bin,lib,include}`) — not
artificial — but there is no reason `build.zig` should re-derive that
ternary 8 separate times instead of once. Add to `Ctx`:

```zig
fn condaDir(ctx: *const Ctx, comptime sub: []const u8) []const u8 {
    return switch (ctx.os) {
        .windows => ctx.absSub("{s}/Library/" ++ sub, .{ctx.conda}),
        else => ctx.absSub("{s}/" ++ sub, .{ctx.conda}),
    };
}
```

and use `ctx.condaDir("lib")` / `ctx.condaDir("include")` /
`ctx.condaDir("bin")` at every one of the 8 sites (plus
`ctx.condaDir("include/cairo")` etc. for the deeper ones). Zero behavior
change — this is purely `s/inline ternary/named call/`. Lowest possible
risk; do this first, and re-verify all 3 platforms in one pass since it
touches many call sites even though each edit is trivial.

### 1b. Pair `addLibraryPath` with `addRPath` in one helper (unix)

Every unix `addLibraryPath({conda}/lib)` call is immediately followed by
`addRPath({conda}/lib)` with the *identical* path (newCMod:1688-1689,
linkCoreLibs:1780-1781, linkOmp:1804-1805, and `applyLinkFlags`'s own `-L`
branch at 1874-1875). Four independent places that must stay in sync by
convention rather than by construction. A small
`fn addCondaLibPath(ctx, mod)` (or extending `condaDir` above to `void
addSearchPath(ctx, mod, sub)` that does both calls on non-Windows) removes
the "did I remember the rpath pairing" question entirely rather than
relying on four separate authors remembering the same two-line idiom.

### 1c. `rspec.zig`: two lists that are byte-for-byte duplicates of an
existing one

- `win_utils_c` (rspec.zig:180-182) is **character-for-character identical**
  to `utils_c` (rspec.zig:174-176). There is no reason for it to exist as a
  separate array — `buildWindows()` should just reference `rspec.utils_c`
  directly (matching exactly how `win_tzone_c`/`tzone_c` already do it:
  Windows compiles the *shared* list via one `addCGroup` call, then a
  *second* `addCGroup` call for the platform-only addition — see
  build.zig's own `win_tzone_c` usage for the pattern to copy). Right now
  `win_utils_c` is dead weight that can silently drift from `utils_c` on a
  future R version bump without anyone noticing (nothing would fail to
  build — the two lists would just quietly diverge).
- `win_blas_f`/`win_blas_f90` (rspec.zig:292-293) are likewise
  byte-identical to `blas_f`/`blas_f90` (rspec.zig:96-97). Same fix: delete
  the Windows copies, reference the shared arrays directly.

### 1d. `rspec.zig`: two lists that are "shared base + a few
additions/substitutions," but currently duplicated wholesale

- `win_grdevices_c` (rspec.zig:147-151) repeats 10 of `grdevices_c`'s 14
  entries verbatim, swapping only `devCairo.c`/`devQuartz.c` for
  `devWindows.c`/`winbitmap.c`. Worth expressing as a `grdevices_shared_c`
  base list plus a 2-item unix-only tail and a 2-item windows-only tail,
  the same shape `tzone_c`/`win_tzone_c` already use successfully. Lower
  priority than 1c (it's a real, deliberate substitution, not an accidental
  full copy), but the *maintenance* risk is the same: a future upstream R
  change to one of the 10 shared files requires remembering to edit it in
  two places.
- `rlapack_f90_ordered` (rspec.zig:101-104) and `win_lapack_f90_ordered`
  (rspec.zig:298-301) contain the *same six files* but in a different
  order (`dlartg.f90` sits in a different position relative to
  `dlassq.f90`/`zlassq.f90`). Both orders satisfy the real module
  dependency (`la_constants` → `la_xisnan` → the four dependents), so this
  isn't a bug — just an inconsistency worth normalizing to one canonical
  order for readability, not correctness.

### 1e. A single `ctx.rhomeInstallDir(sub)` helper for the R_HOME install
prefix

The literal string `"Library/lib/R/..."` is hand-typed as an
`std.Build.InstallDir` at **9 separate call sites** in `buildWindows()`
alone (`bin_dir` build.zig:1124, `modules_dir` :1132, `toolchain_dir`
:1341, the Makeconf install :1407, headers :1445/1450, `etc/repositories`
:1459, `etc/Rconsole` :1471, `share/`/`doc/` :1477/1483) — every one of
these is a typo away from silently installing into the wrong place with no
compile-time check. A single
`fn rhomeInstallDir(ctx: *const Ctx, comptime sub: []const u8) std.Build.InstallDir`
(windows: `"Library/lib/R/" ++ sub`, else: `"lib/R/" ++ sub`) removes that
entire class of typo risk and shortens every call site.

### 1f. `installLibraryWindows`/`installStaticTree` header+share+doc
staging is genuinely the same operation with a different prefix

Both functions independently do, with only the install-dir prefix
differing:
- copy `rspec.public_headers` into `<prefix>/include` (1437-1438 vs
  2308-2309)
- copy `src/include/R_ext` into `<prefix>/include/R_ext` (1449-1450 vs
  2314)
- copy `share/` wholesale into `<prefix>/share` (1476-1479 vs 2338-2341)
- copy `doc/` wholesale into `<prefix>/doc` (1482-1487 vs 2344-2349)

Once 1e's `rhomeInstallDir` helper exists, these four staging steps can be
one shared function (`fn installCommonPayload(ctx, inst)`, called from
both `installStaticTree` and `installLibraryWindows`) instead of two
independent copies of the same four `addInstallDirectory`/`addCopyFile`
calls. This is the single highest-value item in this "safe" tier — it's
the biggest block of literal duplicated code in the file, and it's copying
*identical source content* to a computed destination, exactly the shape
that should never have needed to be written twice.

## 2. Higher-value, higher-risk: unify the *mechanism* for external-library
link flags, not just the paths

This is the most structurally significant asymmetry in the file, and the
one closest to the spirit of "leverage conda packages consistently instead
of OS-specific workarounds."

**On unix/macOS**, essentially every non-trivial link decision (`LIBS`,
`LIBINTL`, `CAIRO_LIBS`, `CAIRO_CPPFLAGS`, `TCLTK_LIBS`, `TCLTK_CPPFLAGS`,
`FLIBS` on macOS, `BITMAP_LIBS`) is a **lookup into `ctx.subst`** — a table
loaded once from a vendored `subst.txt` (a real `config.status` S-table
capture) — fed through the shared `applyLinkFlags(ctx, mod,
ctx.subst.get("X").?)`. This is genuinely the "standard, declarative"
pattern: the *data* (what libraries, what flags) is separated from the
*mechanism* (how to apply them), and the mechanism is one function used
uniformly.

**On Windows**, `ctx.subst` is never populated with any of this (there's no
`config.status` to replay from) — every equivalent decision is a **hardcoded
imperative list** written directly in `buildWindows()`:

- `internet.dll`: `for ([_][]const u8{ "libcurl", "wininet", "ws2_32" })
  |lib| inetmod.linkSystemLibrary(...)` (build.zig:933)
- `winCairo.dll`: `for ([_][]const u8{ "cairo", "fontconfig" })` (:1229)
- `grDevices.dll`: `for ([_][]const u8{ "libpng", "tiff", "jpeg", "zstd",
  "z", "lzma" })` (:1197)
- `R.dll` itself: a 12-entry hardcoded array including `icuin`/`icuuc`/
  `icudt` (:1027, from the F6.3 work)
- `Rgraphapp.dll`: an 8-entry hardcoded array (:983)

None of this is *wrong* — every one of these was found and verified via a
real link error, same as the unix `subst.txt` values were originally
captured from a real `configure` run. But the **shape** is different:
unix says "look up `CAIRO_LIBS` and apply it generically," Windows says
"here is a literal list of library names for this one DLL, hardcoded at
this one call site." That's exactly the "OS-specific workaround" pattern
the request is asking to reduce — not because the Windows values are
wrong, but because there's no *single place* to look to answer "what does
this build link against libcurl with," the way `ctx.subst.get("CURL_LIBS")`
answers it on unix.

**Recommended shape** (not attempted here — this is the "worth doing, plan
first" item, not a quick mechanical rename): vendor a real
`zigbuild/config/win-x86_64-full/subst.txt`, in the *same* `S["VAR"]="..."`
format the unix ones already use, populated either by hand (there's no
`config.status` to replay, but the values are already known-good — they're
sitting in `buildWindows()` right now) or captured from a real generated
`Makeconf` on kappa (the same "extract from a known-good build, don't
guess" methodology F6.1a/F7 already used repeatedly). Then every one of the
five hardcoded lists above becomes `applyLinkFlags(ctx, mod,
ctx.subst.get("CURL_LIBS").?)` etc. — the exact same call shape unix/macOS
already use. This doesn't change what gets linked; it changes *where the
decision lives* — one vendored table per platform, one application
mechanism shared by all three.

This is real, valuable work, but it touches five separate compile groups
and needs re-verification of `smoke`/`contract`/`verify-package` on
Windows afterward (matching the standard of every prior phase in this
milestone) — sized more like a half-day task than a quick pass. Worth
doing as its own follow-up, not folded into the mechanical renames in §1.

## 3. What looks like duplication but is a real, load-bearing platform
difference — do not try to unify these

Flagging these explicitly so a future pass doesn't spend time trying to
force convergence where the underlying reality genuinely differs:

- **`buildWindows()` as a wholly separate function from `build()`**
  (build.zig:244). Windows has no `config.status`, no shell launchers, a
  structurally different R source tree (gnuwin32's own `front-ends`/
  console-plumbing sources vs unix's `src/unix`), mutual-DLL linking
  (`R.dll` ↔ `Rblas.dll`/`Rgraphapp.dll` via stub import libs) that has no
  unix analogue at all, and a completely different package-DLL
  installation layout (`libs/x64/<pkg>.dll` vs flat `libs/<pkg>.so`). This
  was a deliberate call documented at the branch point itself ("threading
  it through the unix/macOS pipeline... would risk the two already-proven
  platforms") and nothing found in this review changes that calculus.
- **Per-package/per-module Windows source-list *substitutions*** (not the
  byte-identical duplicates in §1c/1d, but genuine differences):
  `parallel`'s `ncpus.c` vs unix's `fork.c` (no `fork()` on Windows),
  `grDevices`'s `devWindows.c` vs `devCairo.c`/`devQuartz.c`, `R.dll`'s own
  required gnuwin32/graphapp/intl/trio/iconv source groups. These mirror
  real upstream R `Makefile.win` vs `Makefile`/`Makefile.in` differences —
  "unifying" them would mean changing what code actually gets compiled,
  which is a correctness question for upstream R, not a build-system
  inconsistency in this project.
- **Fortran compiler/flags per OS** (`fortranOne`, build.zig:1930-1944):
  flang (linux) vs gfortran (macOS/Windows), `-O1` cap on macOS
  specifically (a known gfortran-darwin miscompile), `-module-dir` vs `-J`
  (the two compilers' own, different spellings of the same concept). Real
  toolchain differences, already collapsed into the smallest possible
  `switch` inside one shared function — this is already the "unified
  mechanism, differing data" shape §2 recommends for link flags.
- **`fixRpath`'s no-op on macOS** (build.zig:1902) and the complete absence
  of an rpath concept on Windows (PE/COFF uses PATH/same-directory DLL
  search, not an ELF/Mach-O-style embedded search path) — ELF, Mach-O, and
  PE are just different binary formats with different loader semantics.
  Nothing to unify; the existing per-format handling (patchelf on linux,
  `stage.sh`'s own install_name_tool+codesign on macOS, PATH-relative DLL
  placement on Windows) is already the minimum necessary set, already
  factored to touch only what each format actually needs.
- **`R_HOME` layout** (`lib/R` vs `Library/lib/R`) — conda-forge's own
  Windows packaging convention (avoiding the NTFS case-fold collision with
  a real env's `Lib/`, documented at build.zig:190-194), not something this
  project introduced or could change without breaking conda-forge
  interop.

## Suggested order of work, if picked up

1. §1a (conda path helper) + §1e (rhome install-dir helper) — highest
   ratio of risk-reduction to effort, touch nearly every other item on this
   list, do these two first since later refactors read more cleanly once
   they exist.
2. §1c (delete the two byte-identical `rspec.zig` lists) — zero risk, two
   minutes of work.
3. §1f (shared header/share/doc staging function) — biggest single chunk
   of duplicated code removed, moderate care needed (touches both
   `installStaticTree` and `installLibraryWindows`).
4. §1b (rpath-pairing helper), §1d (base+diff source lists) — smaller,
   lower urgency, fold in whenever touching the surrounding code anyway.
5. §2 (Windows subst-table) — the real architectural win, but sized as its
   own follow-up with a full re-verification pass, not a quick pass.

Every item above should be re-verified with the existing trust bar after
implementation — `smoke`/`contract`/`check` (where it exists)/
`install`/`package`/`verify-package` on all three platforms — the same
discipline every phase in this milestone has followed. None of this is
urgent (the build is fully green today); it's worth doing before the next
R version bump, when `rspec.zig`'s duplicated lists are exactly the kind of
thing that silently drifts.
