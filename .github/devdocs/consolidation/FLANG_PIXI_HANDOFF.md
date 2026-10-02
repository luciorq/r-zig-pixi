# flang-pixi → r-zig-pixi handoff: review of the Phase 2 wiring, caveats, and everything learned on the toolchain side (2026-09-19)

Written from the flang-pixi side after reviewing this repo's Phase 2
implementation (build.zig `FortranCompiler`/`findFlangRt`/`fortranOne`/
`linkFortranRt`, pixi.toml + recipe.yaml target splits, the osx-arm64
vendored config, scripts/env.sh, zigbuild/tools, CI). Ground truth for
the toolchain is flang-pixi `docs/10-status-log.md` (log), `docs/11`
(interface contract), `docs/14` (what is on universe). Everything below
is measured, not assumed, unless marked *expect*.

## 0. What flang-pixi ships (facts to build against)

| | |
|---|---|
| packages | `lld-zig`, `flang-zig`, `flang-rt-zig` — version **23.1.1**, zig 0.16.0, channel `https://prefix.dev/universe`. `llvm-zig` is build-time only and is never published. |
| subdirs | all six: linux-64, linux-aarch64, osx-64, osx-arm64, win-64, win-arm64 — every one validated on GitHub's native runners (smoke + Fortran OpenMP; ABI probe on unix). |
| build numbers | **differ per subdir** (each bump fixed one subdir): win-arm64 lld `_3`/flang `_4`/flang-rt `_7`; linux-aarch64 + osx-64 flang-rt `_5`; the rest lower. **Pin by version only** (`flang-zig ==23.1.1`), never by build string. Older win-arm64 builds still on universe are dead (fail to load); the solver picks the newest, so they only bite if someone pins them. |
| flang binary | `$PREFIX/bin/flang` (unix), `$PREFIX/Library/bin/flang.exe` (win); `flang-new` alias exists too. `flang-zig` run-depends on `lld-zig`. |
| runtime archive | `lib/clang/23/lib/<dir>/libflang_rt.runtime.a` with `<dir>` = `x86_64-unknown-linux-gnu` / `aarch64-unknown-linux-gnu` / `darwin` (macOS, both arches; a `.dylib` sits beside the `.a`) / `Library/lib/clang/23/lib/x86_64-w64-windows-gnu` / `aarch64-w64-windows-gnu` (Windows). `lib/libflang_rt.runtime.a` symlink/copy exists on unix as a convenience. `findFlangRt`'s two-level glob is the right consumer code. |
| intrinsic modules | `lib/clang/23/finclude/flang/<conda-triple>/*.mod` (`x86_64-conda-linux-gnu`, `aarch64-conda-linux-gnu`, `x86_64-apple-darwin13.4.0`, `arm64-apple-darwin20.0.0`; Windows `x86_64-w64-mingw32` / `aarch64-w64-mingw32` with a copy under the `*-w64-windows-gnu` name). The driver only finds them through `flang.cfg` (next row). |
| `flang.cfg` (unix) | `-Wl,-L,<CFGDIR>/../lib`, `-Wl,-rpath,<CFGDIR>/../lib`, `-fintrinsic-modules-path <CFGDIR>/../lib/clang/23/finclude/flang/<triple>`, `-Wl,-rpath-link,…`, `--sysroot=<CFGDIR>/../<triple>/sysroot` (linux), `-fuse-ld=lld`, `--rtlib=compiler-rt`. |
| `flang.cfg` (win) | `-fuse-ld=lld`, `-fintrinsic-modules-path <CFGDIR>/../lib/clang/23/finclude/flang/<arch>-w64-mingw32`, and on win-arm64 `-lcompat_arm64`. |
| OpenMP | flang-rt-zig run-depends on conda-forge **`llvm-openmp`** (host dep on win) and ships `omp_lib.mod`, `omp_lib_kinds.mod`, `omp_lib.h` next to the intrinsic modules; on Windows also `Library/<triple>/lib/libomp.dll.a` (import lib for conda-forge's `libomp.dll`, made with zig dlltool) and an empty `libatomic.a` (the MinGW driver emits `-latomic -lomp`). Never build a second libomp: one OpenMP runtime per process, the same `libomp.dll`/`libomp.so` zig cc's C code uses. `flang -fopenmp` + `use omp_lib` proven on all six subdirs. |
| Windows CRT | `Library/<arch>-w64-mingw32/lib/` holds zig's mingw CRT extracted into GNU names (`libmsvcrt.a` = zigc + all UCRT api-set import libs merged; `libmingw32.a`; `libgcc.a` = compiler-rt; `libkernel32.a` …) so the flang driver's MinGW toolchain logic links without gcc. On win-arm64 `libmsvcrt.a` also contains a `wcstold` shim (zig's aarch64 CRT lacks it) and `libcompat_arm64.a` exists (see §3). |
| what is NOT shipped on Windows | no `llvm-nm`, `llvm-ar`, `llvm-objdump`, `dlltool` binaries — flang-zig ships `flang.exe`, `flang-new.exe`, `bbc.exe`, `tco.exe`, `fir-opt.exe`, `fir-lsp-server.exe`, `f18-parse-demo.exe`; lld-zig ships `ld.lld`, `lld-link`, `lld`, `ld64.lld`, `wasm-ld`. |
| glibc floor | linux packages depend on `__glibc >=2.17` / `sysroot_linux-64 >=2.17` (enforced by a build-time tripwire in flang-pixi). macOS floor `__osx >=11.0` (arm64) / `>=10.13`-class (osx-64, see docs/06). Same floor r-zig-pixi already ships against. |
| closure cost | ~1.5 GiB installed per platform (flang-zig ~880 MiB unix / 173 MiB compressed on win, lld-zig ~94 MiB compressed, flang-rt-zig ~6 MiB). |

## 1. Review of what is in the repo now

**Right, keep:**
- Fortran compiler as a *dependency decision*, probed on disk, printed once (`r-zig: Fortran compiler = …`). Matches flang-pixi's contract #1.
- The uncommitted BUILD_PREFIX-then-CONDA_PREFIX probe order in build.zig is correct for rattler-build: compilers live in `$BUILD_PREFIX`, the runtime in the host prefix; `findFlangRt` searching the host prefix is right because flang-rt-zig is a host dep. Keep both `flang-zig` (build) and `flang-rt-zig` (host + run) in the recipe exactly as done for osx-arm64.
- `-lflang_rt.runtime` linked **statically**, `link_libcpp` on macOS. Measured on the Linux archives: the only C++-runtime undefined symbol is `__cxa_atexit` (libc), so Linux needs no libc++; macOS evidently does (you found it) — *expect* Windows to behave like macOS, so set `link_libcpp = true` there too when the win-64 leg comes (zig links its libc++ statically on windows-gnu; there is no libc++.dll to depend on).
- `SHLIB_OPENMP_CFLAGS=-fopenmp` kept; `R_SYSTEM_ABI … ClassicFlang`; explicit FLIBS (contract #3: autoconf mis-parses flang's `-###`).

**Will break, fix before the next platform:**

1. **The LLVM major is hard-coded in every vendored FLIBS.** osx-arm64: `-L@ZR_CONDA@/lib/clang/23/lib/darwin`; linux-x86_64: `-L@ZR_CONDA@/lib/clang/22/lib/x86_64-unknown-linux-gnu` with `FC_VER = flang 22.1.8`. That string lands in the installed `Makeconf`, i.e. in every user package link. conda-forge already ships flang 23.1.1 on linux-64, so the next fresh solve of `flang = "*"` (rattler-build always solves fresh — the same class of bug as the gfortran 15.2.0→16.1.0 path you already hit) makes the `-L` dir vanish and `-lflang_rt.runtime` fail to resolve. Fix once, generically: let gen-subst.sh capture the path as a token (`@ZR_FLANGRT_DIR@`) and have build.zig substitute it from `findFlangRt` at build time, the same way `@ZR_CONDA@` is substituted. Then bumping flang-pixi to LLVM 24 later costs nothing here.

2. **Fortran OpenMP regressed silently on flang platforms.** gfortran configs carry `SHLIB_OPENMP_FFLAGS=-fopenmp`; both flang captures have it empty (R's configure probes `use omp_lib`, which failed because no `omp_lib.mod` existed when they were captured). With flang-rt-zig ≥ build 4 the module exists and `flang -fopenmp` links against conda-forge's libomp on every subdir, so packages using `$(SHLIB_OPENMP_FFLAGS)` (there are CRAN packages with Fortran OpenMP) can have it back: set `SHLIB_OPENMP_FFLAGS=-fopenmp` in the flang-zig configs, or re-capture with the module present. Caveat for linux-64 while it stays on **conda-forge's** flang: conda-forge's `llvm-openmp` ships no `omp_lib.mod`, so `use omp_lib` fails there (directives alone work). Moving linux-64 to flang-zig too would make all six identical.

3. **Windows still hard-codes gfortran** in `buildWindows`: `FC_VER = "gfortran (conda-forge, MinGW target)"`, `FC = "<conda>/Library/bin/gfortran.exe"`, and the gfortran-specific import-lib dance in `linkFortranRt`. With flang the Windows leg needs: `FC = "<conda>/Library/bin/flang.exe"` (absolute path — same reasoning as gfortran: never route flang through BINPREF, and **never copy `flang.exe` anywhere**: it finds `flang.cfg` relative to its own location, and without the cfg every compile dies with "cannot find module iso_c_binding" / "runtime derived type info descriptor was not generated"), `FLIBS = -L<conda>/Library/lib/clang/23/lib/x86_64-w64-windows-gnu -lflang_rt.runtime`, `SHLIB_FCLD = $(FC)` so Fortran packages link through the flang driver (which then applies `-fuse-ld=lld` and needs `ld.lld.exe` from lld-zig on PATH — it is, in `Library/bin`), and `FC_VER` from `flang --version`.

4. **Dropping `gfortran` on win-64 also drops binutils.** `winMakeImportLibFor` / `winMakeImportStub` call `x86_64-w64-mingw32-dlltool` and `x86_64-w64-mingw32-nm`, which come with conda-forge's gcc toolchain, and neither flang-zig nor lld-zig ships an nm. Options: `zig dlltool` is a drop-in replacement for dlltool (`zig dlltool -m i386:x86-64 -d x.def -D R.dll -l R.dll.a`; flang-pixi builds `libomp.dll.a` exactly this way); for the symbol dump either keep a binutils package in build deps, use conda-forge's `llvm-tools` (MSVC-built but reads COFF fine), or parse the COFF symbol table in a few lines of Python (flang-pixi's `scripts/pe-exports.py` does the DLL-export half).

5. **CI's Windows consume test solves without universe.** `pixi init --channel "$channel" --channel conda-forge` — once `r-zig-slim` run-depends on `flang-zig` on win-64 that solve needs `--channel https://prefix.dev/universe` too. Same for any fresh `pixi init` a user does: document it.

6. **osx-64 in CI runs on `macos-15-intel`, so the Rosetta caveat is only on omicron.** flang-pixi's osx-64 packages were built under Rosetta and then validated on a real Intel runner (run 35444075028); the build host's `CONDA_TOOLCHAIN_HOST` was unset in that setup, which is why flang-rt `_5` derives its paths from `target_platform`. Nothing to do here, but if osx-64 flang-rt looks wrong, check you have `_5`, not `_4`.

## 2. Traps we hit that a consumer can hit too

- **zig's Run-step cache does not track the flang binary.** After swapping the Fortran compiler (gfortran → flang, or flang 22 → 23) `zig build` happily reuses old `.o`/`.mod` outputs: `rm -rf build/zig-cache` (and the global cache if `--global-cache-dir` is used) or you will "validate" the old objects. This is how the first "flang 23 passes lapack.R" run on linux-64 was nearly wrong.
- **LLVM 23 moved the intrinsic `.mod` files** from `include/flang` to `lib/clang/23/finclude/flang/<driver-triple>/`, and the driver matches that directory name exactly. flang-pixi renames it to the conda triple and points the driver there in `flang.cfg`. Consumers should not pass `-fintrinsic-modules-path` themselves and should not rely on `include/flang` existing (it does not).
- **flang warnings that look like errors.** `-Wfolding-failure` on loessf.f/cmplx.f/dlapack.f (`exp(real(kind=8)) cannot be folded on host`) is harmless; zig prints captured stderr under a "failed command" heading even for exit 0. Also *expect* `-fpic` to be reported as unused on Windows; drop it there rather than teaching yourself to ignore the warning.
- **macOS: the `.dylib` beside the `.a`.** Your `preferred_link_mode = .static` handles libR/libRblas/libRlapack; but a *package* linked by the flang driver with `-L…/darwin -lflang_rt.runtime` (FLIBS in Makeconf) lets ld64.lld pick the dylib first, so package `.so`s may carry an `@rpath/libflang_rt.runtime.dylib` dependency resolved through `-Wl,-rpath,<CFGDIR>/../lib` from `flang.cfg`. minqa passed the contract suite, so it resolves — just know which one you got (`otool -L`) before promising relocatability of user-built packages. If you want the static one always, put `<dir>/libflang_rt.runtime.a` in FLIBS instead of `-lflang_rt.runtime`.
- **Linux: `flang.cfg` adds `-Wl,-rpath,$CONDA/lib` to every driver link.** package-standalone.sh strips `-Wl,-rpath,$CONDA/lib` from Makeconf, but the cfg re-adds it inside the driver, so user-built Fortran packages get an absolute RUNPATH to the env's lib dir. Harmless in a pixi env; relevant only to the "relocatable bundle" story.
- **Linux: `--sysroot` in `flang.cfg` and the glibc floor.** flang-zig links against conda's `sysroot_linux-64 2.17` (the cfg's `--sysroot`) and `--rtlib=compiler-rt`, so Fortran objects never reference glibc symbols newer than 2.17 — consistent with zig's `-target …-gnu.2.17`. Your gfortran-only `-fno-tree-loop-vectorize` (libmvec) is not needed for flang: flang never picks up glibc's `math-vector-fortran.h`.
- **`SDKROOT` on macOS.** The flang driver locates the SDK via `xcrun` when `SDKROOT` is unset; in a sandbox without Xcode CLT that yields "library not found for -lSystem". flang-pixi's CI sets `SDKROOT=$(xcrun --show-sdk-path)` explicitly. rattler-build's conda-forge-style activation usually sets it; if a link step fails only in the package job, this is the first thing to check.
- **Windows: `SHLIB_OPENMP_FFLAGS=-fopenmp` needs the two shims.** The MinGW driver emits `-latomic -lomp`; both resolve only because flang-rt-zig ships `libatomic.a` (empty) and `libomp.dll.a` in the CRT lib dir. `llvm-openmp` must be installed at link *and* run time (it is a run dep of flang-rt-zig, so a normal solve has it).
- **`pixi publish` / pixi-build would silently raise your glibc floor.** Not your path today, but if r-zig-pixi ever builds packages through pixi-build instead of rattler-build: pixi derives `c_stdlib_version` from the *build machine's* `__glibc`/`__osx` (defaults 2.28/13.0) and ignores `variants.yaml`; only `[workspace.build-variants]` in the manifest overrides it. flang-pixi lost two days to packages that said `__glibc >=2.28` while the recipe said 2.17. `scripts/check-stdlib-floor.py` there is a 60-line tripwire you can copy.
- **prefix.dev quirks.** `rattler-build upload prefix` prints nothing on success without `-v`; repodata re-indexes asynchronously (minutes; Windows subdirs were slowest) — verify uploads through the GraphQL API, not by absence of an error. The upload key scope needed to delete a file (`channel:delete-package`) is separate; plan for dead builds to linger.

## 3. Windows on ARM (for when win-arm64 becomes a platform here)

Three gaps in zig 0.16's bundled mingw-w64 CRT for `aarch64-windows-gnu`, all found the hard way, all self-contained in flang-pixi's packages — but only for links that go through the **flang driver**. `zig build` links get none of them and need them as follows:

1. **`__C_specific_handler` (SEH personality, referenced by any code using `__try`/SEH; all of LLVM).** zig's arm64 `libkernel32.a` claims KERNEL32.dll exports it — true on x64 only; arm64 kernel32 and ntdll do not, arm64 exports it from the UCRT (`api-ms-win-crt-private-l1-1-0.dll` → ucrtbase; also vcruntime140). Plain `zig cc` resolves it right; anything that names `-lkernel32` ahead of the CRT (**CMake's MinGW platform module does on every link line**) resolves it from KERNEL32 and the exe/dll dies at load with `0xC0000139 STATUS_ENTRYPOINT_NOT_FOUND`. flang-pixi's fix is `Library/aarch64-w64-mingw32/lib/libcompat_arm64.a` (a one-symbol import library for the private api set + the wcstold shim), on every link of its own builds and via `-lcompat_arm64` in `flang.cfg`. R itself does not use SEH; R packages built with CMake (or anything passing `-lkernel32`) would. build.zig never links kernel32 explicitly, so R.dll is fine; keep it that way.
2. **`wcstold` is missing from zig's aarch64 CRT** (x64 has it). One-line shim: `long double wcstold(const wchar_t *n, wchar_t **e) { return (long double)wcstod(n, e); }` — exact on arm64 Windows where long double is double. flang-pixi bakes it into the extracted `libmsvcrt.a` for flang links; a `zig build` of anything calling `wcstold` needs its own copy.
3. **`__intrinsic_setjmpex` is fine.** arm64 ucrtbase exports it (verified from the real DLL); the first guess that setjmp was missing cost a full 3.5 h chain rebuild. Lesson that transfers: when a Windows binary exits `0xC0000139`, do not diff imports against another arch — resolve every imported symbol on the target machine. flang-pixi's `scripts/pe-resolve-imports.py` (pure Python, `GetProcAddress` per import) does that and is now the CI diag step; the Windows SDK NuGet `Microsoft.Windows.SDK.CPP.arm64` (`c/ucrt/arm64/ucrt.lib`, `c/um/arm64/kernel32.Lib`) plus the redist `ucrtbase.dll` inside the base SDK NuGet are the offline ground truth for what arm64 Windows exports.

Also: the `zig_win-arm64` package exists only in the win-64 subdir, so win-arm64 is a cross-only target for anything built with zig through conda (r-zig-pixi included) until that changes; `windows-11-arm` hosted runners can *run* the result.

## 4. Per-platform checklist before flipping a default (what flang-pixi already proved, so you only re-prove the R side)

For each platform, flang-pixi's `test.yml` run on the native runner already shows: `flang --version`, hello + derived types (exercises the intrinsic-module path), `-fopenmp` with directives and `use omp_lib` (3 threads), and on unix the zig-cc↔flang ABI probe. What only r-zig-pixi can prove: `pixi run build` at -O2, `check`'s lapack.R (the gfortran-darwin zgesdd miscompile detector), the contract suite (minqa = package Fortran through `$(FLIBS)`; data.table = OpenMP), `verify-package`, and the conda-package job with a *fresh* solve (that is where hard-coded paths and missing channels surface, never in the dev env with its lockfile).

Order that matches value and risk: osx-64 (same mechanism as osx-arm64, runtime dir also `darwin`, no Rosetta in CI) → linux-aarch64 (flang-rt `_5`; drops the gfortran sysroot-leak workaround) → win-64 (items 3–5 above; the only MinGW flang in existence, so also the only path to zero-gfortran on Windows) → win-arm64 (§3, plus adding the platform).

## 5. Where to look in flang-pixi

`docs/11` interface contract (items 5–8 added 2026-09-19 for the Windows legs) · `docs/10` status log (every finding, dated; the 2026-09-19 entries cover finclude, OpenMP, the two win-arm64 diagnoses) · `docs/14` publishing runbook + the live file list on universe · `docs/06` recipe conventions (why standalone rattler-build, not pixi-build) · `docs/13` zig-feedstock glibc coupling · `scripts/ci-smoke.sh`, `ci-omp.sh`, `ci-abi.sh`, `pe-resolve-imports.py`, `check-stdlib-floor.py` (all reusable as-is) · `tests/openmp/*.f90` (OpenMP smoke sources).

## 6. The conda-forge zig is not upstream zig — reconciled with r-zig-pixi's findings (2026-10-01; first written 2026-09-30, flang-pixi docs/16)

Measured on zig-feedstock build 19; corrected and extended after this
branch's own measurements (PLAN.md "flang-pixi handoff §6, reconciled" and
"Packaging (phase T)"). Facts, then what flang-pixi recommends.

**libc++**
- conda-forge's zig prefers a *shared* libc++ whenever
  `<zig lib dir>/../../lib/libc++.{1.dylib,so.1}` exists (patch
  `Lld.zig-prefer-shared-libcxx`, native-arch links only, no opt-out:
  `-static-libstdc++` is ignored, `-stdlib=` stripped by the wrappers).
  Always true on macOS (`zig_impl_osx-*` run-depends on `libcxx 21.*`), true
  on Linux the moment a `libcxx` package enters the env, never on Windows
  today (no `libc++.dll.a` there).
- The `ZIG_LIB_DIR` mirror defeats it: a **real** directory `<mirror>/lib/zig`
  whose entries are symlinks into the env's `lib/zig`. The probe is an
  `access()` on `<lib dir>/../../lib/<name>`, and the kernel resolves `..`
  after following symlinks, so a symlinked `lib/zig` would point the probe
  straight back into the env. Both projects use the same construction;
  flang-pixi's four build scripts have since 2026-09-30, r-zig-pixi's
  `zig-build.sh` and shims too.
- **`zig build`'s local cache is not keyed on the probe's outcome** (found
  by r-zig-pixi): a warm cache hands back shared-libc++ link outputs after
  the mirror is switched on, so a mirror build needs its own
  `ZIG_LOCAL_CACHE_DIR` or a cold cache. Plain `zig cc` follows
  `ZIG_LIB_DIR` on every call. (flang-pixi builds in fresh rattler-build
  work dirs, so it never saw this.)
- flang-pixi's packages are static libc++ on all six subdirs (published
  2026-09-30; universe pruned to exactly the 18 live files). The macOS
  binaries depend on `libSystem` only and the packages no longer depend on
  `libcxx`. Exceptions crossing from a package into code built against a
  different libc++ are catchable only as `catch(...)`: known, accepted.

**The flang runtime: link the archive by path, and keep the dylib off the
line (2026-10-01).** The clang resource dir (`lib/clang/23/lib/darwin` on
macOS, `lib/clang/23/lib/<triple>` on Linux) holds both
`libflang_rt.runtime.a` and the shared library, and `lib/` symlinks both.
Two traps, both measured:
- `-L<dir> -lflang_rt.runtime` takes the shared one on macOS (zig and the
  flang driver alike; the driver also records an absolute rpath to the env's
  `lib`), so packages built that way load only inside the build env. Your
  archive-path `FLIBS` is the right rule.
- **Apple's `ld` cannot link the archive while the dylib is reachable.**
  zig-built dylibs export `___dso_handle` (Apple-built ones do not;
  `libflang_rt.runtime.dylib` does). The flang driver always adds
  `-lflang_rt.runtime` plus the resource dir, so `flang -shared obj
  <dir>/libflang_rt.runtime.a` through Apple's `ld` (R's
  `SHLIB_FCLD=$(FC)` on macOS) fails: `ld: fixup error
  (kind=arm64_adrp_lo12) at '__GLOBAL__sub_I_external_unit.cpp' … target
  '___dso_handle'`, with `_4` and `_8` alike. It links when the dylib is off
  the search path (archive-only dir first on `-L`), with `-fuse-ld=lld`,
  and under zig's own linker. If your Fortran packages currently link, check
  which linker and search path they really use; the robust fix is on the
  flang-pixi side (next bullet).
- Decision on the flang-pixi side: **flang-rt build 9 = static-only
  (no `.so`/`.dylib` in any subdir) and hidden visibility** for the runtime
  objects, all six subdirs, pending the maintainer's go-ahead. After it,
  `-lflang_rt.runtime` resolves to the archive, the driver trap disappears,
  and a package `.so` no longer re-exports the runtime.
- Your `_4` numbers: the 88 members at 13.0 are flang-rt `_4`; `_8` (on
  universe since 2026-09-30) is 11.0 throughout — re-lock to see it. The
  macOS dylib depends on `libSystem` only (no libc++).

**Runtime symbols re-exported by Fortran packages (your question).**
Measured: a Fortran `.so` linking the archive statically exports 1,238
symbols on Linux (1,142 runtime: `_Fortran*`, `_ZN7Fortran*`, CFI_*, …) and
828 on macOS (808 runtime). flang-pixi's view: hide them, at build time.
Link-time options are uneven — Linux: a version script through zig+lld
works (`{ global: *; local: _Fortran*; _ZN7Fortran*; _ZNK7Fortran*;
_ZT[VIS]N7Fortran*; };` leaves 25 exports; `--exclude-libs` is rejected by
zig); macOS: zig's Mach-O linker *accepts and ignores*
`-exported_symbols_list` and rejects `-unexported_symbols_list` and
`-hidden-l`, so nothing at link time works under zig there. flang-rt has no
visibility option of its own (hidden only for CUDA offload objects), so
build 9 compiles the runtime with `-fvisibility=hidden
-fvisibility-inlines-hidden`; consumers then export nothing of it without
doing anything. Until then, the Linux version script is safe to use; on
macOS, accept the re-export (two-level namespaces keep each `.so`'s copy
private, so there is no interposition, only size).

**macOS deployment target and flang — closed (2026-10-01, both sides).**
- A flang-compiled object carries `minos` = the host SDK's version (26.0 on
  omicron) unless told otherwise. `-mmacosx-version-min=13.0`,
  `-mmacos-version-min=13.0`, `--target=arm64-apple-macosx13.0` and
  `MACOSX_DEPLOYMENT_TARGET=13.0` all give 13.0, for objects and flang's own
  links. The flag beats the env var (flag 11.0 + env 13.0 → 11.0, silently)
  and the last flag wins. Your choice — the flag in R's build and inside
  Makeconf's `FC` — is right.
- zig's Mach-O linker stamps the link's floor over newer objects without a
  word; Apple's `ld` warns and does the same. flang's own macOS link runs
  Apple's `ld` and needs `SDKROOT` (`-fuse-ld=lld` works but still needs
  the SDK's `libSystem.tbd`): the Xcode CLT is a requirement of any tier
  that links Fortran on macOS.
- `-target <arch>-native.13.0` (literal `native` + `MAJOR.MINOR`) is
  verified at the binary level on osx-arm64, no macOS 13 load test yet:
  `minos 13.0`, no `LC_RPATH` per `-L`, the SDK's headers and libSystem;
  at link time add `-F$SDK/System/Library/Frameworks` and
  `-L$SDK/usr/lib` LAST (SDK `-L` first silently binds `-lz`/`-liconv`/
  `-lcurl` to the SDK's `.tbd` stubs against conda's headers; a missing SDK
  `-L` is what produced the conda-forge zig panic and upstream's libobjc
  error). The `-fvisibility=hidden -O3` crash did not reproduce.
  `<arch>-macos.13.0` stays unusable (loses `usr/include`: `net/if_media.h`,
  libDER). conda-forge zig still links the shared libc++ with any pinned
  target unless the mirror is on. The same form works on the conda-forge
  zig 0.17 dev snapshot (measured 2026-10-01 on omicron).

**Windows, corrected.** r-zig-pixi's shims call `x86_64-w64-mingw32-zig.exe`
from `zig_impl_win-64` — the real zig binary (`zig.bat` only forwards to
it), whose default target is `x86_64-windows…-gnu`, the gnu ABI. The MSVC
default and the flag dropping belong to the `zig_win-64` wrappers
(`x86_64-w64-mingw32-zig-cc.exe`/`-cxx.exe`, ~200 KB) only; those fail with
`WindowsSdkNotFound` on a machine without Visual Studio unless given
`-target x86_64-windows-gnu`. The host's Windows 11 version reaches
neither the PE header versions (6.0) nor `_WIN32_WINNT` (0x0a00). The
arm64 `__C_specific_handler` entry in zig's kernel32 import library is
still present in build 19 (§3).

**Wrapper flag drops (the `zig_win-64`/`zig_linux-64`/`zig_osx-*` `-cc`/
`-cxx` wrappers only):** `-march=`, `-mtune=`, `-ftree-vectorize`,
`-fstack-protector*`, `-fno-plt`, `-fdebug-prefix-map=`, `-stdlib=`,
`-lgcc_s`, `-lgcc_eh`, `-Wl,-rpath-link*`; `-static-libstdc++` is reported
unused. Plain zig honours them all. Keep plain zig behind the shims.

**Lockfile notes (r-zig-pixi's):** `libcxx 21.1.8` sits in every macOS R
build env through `zig_impl_osx-*` and cannot be dropped; `23.1.2` only in
the Python-only `wheel` env (irrelevant). Mixed zig builds (`_19` in
minimal, `_15` elsewhere): unify on `_19`, the build all of this was
measured on.

**Shipping zig means shipping conda LLVM 21** (`libllvm21`,
`libclang-cpp21.1`; `vc14_runtime`+`ucrt` on Windows; `libcxx` on macOS):
the conda zig binary is dynamically linked, unlike upstream's.

**rattler-build pitfalls r-zig-pixi hit (not seen in flang-pixi, which has
no staging outputs or `path:` sources):** the staging-output `build_cache`
key does not hash `path:` sources, so local rebuilds after editing them
reuse the old output (delete `<output-dir>/build_cache`); a staging output
gets no `PKG_NAME`/`PKG_VERSION`, pass them via `script: {file, env}`.
