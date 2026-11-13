# feat-win-arm64 — Windows on ARM

The last item of the user's order of 2026-10-22 (pkgconf from source, the
zig 0.17 port, Windows on ARM). Branch feat-win-arm64, stacked on
feat-win-zig-binutils (on feat-zig-017, on feat-zig-pkgconf). Nothing
here can run on x86_64 Windows: R's build runs the R it builds (the
bootstrap). CI's `windows-11-arm` runner, behind the `win-arm64` label
(.github/workflows/win-arm64.yaml), is where it is tested.

## Decisions (user, 2026-11-10: "Accept the revised recommendations")

1. Host: A, GitHub's hosted `windows-11-arm` runner behind a label, as
   the upstream-zig legs are.
2. Cairo: A, build it with zig. The user asked first whether cairo is
   needed for most of R's plotting: on Windows R's own devices draw the
   screen, png/jpeg/bmp/tiff (GDI) and pdf()/postscript(); svg(),
   cairo_pdf(), cairo_ps() and the bitmap devices' type = "cairo" need
   cairo (winCairo.dll). Without it they would fail on win-arm64 alone,
   a platform difference the project exists to remove.

## In place before this branch

- zig: conda-forge zig 0.17.0 has a win-arm64 build; PyPI ziglang 0.17.1
  has win_arm64, pinned in scripts/fetch-zig.sh.
- Fortran: flang-pixi's flang-zig 7, lld-zig 6 and flang-rt-zig 11 are
  on universe for win-arm64.
- pkgconf builds for the host's arch (zigbuild/toolchain/pkgconf.zig).
- Binutils: rzig's nm, objdump, strip, dlltool, windres and as
  (feat-win-zig-binutils) take the machine from the target.
- rzig's groups.zig names win-arm64's archives.

## What changed

cairo (both Windows arches, both channels):
- zigbuild/cairo.zig (new): cairo 1.18.6 from its tarball, without meson,
  linked statically into winCairo.dll (CRAN's Rtools links it statically
  too). Features: image, PNG, PDF, PS, SVG, script, the Win32 surface
  and font backends, and DirectWrite, as conda-forge's win-64 cairo; no
  FreeType or fontconfig (R's Windows device picks fonts through GDI,
  cairoFns.c). config.h and cairo-features.h are meson's for
  x86_64- and aarch64-windows-gnu with zig 0.17 (probed 2026-11-10; the
  same but aarch64's ATOMIC_OP_NEEDS_MEMORY_BARRIER). cairo 1.18.6 does
  not build for Windows without DirectWrite: cairo-win32-system.c calls
  cairo_win32_dwrite_finalize unconditionally (meson with -Ddwrite=disabled
  fails the same way). pixman, libpng and zlib are the env's (conda-forge
  has them for both arches); CAIRO_LIBS in the vendored subst.txt names
  them, cairo.zig the Windows libraries (gdi32, msimg32, dwrite, d2d1,
  windowscodecs, ole32).
- The source: build.zig.zon (new, at the root) has the lazy `cairo`
  dependency for the standalone build; the recipe has it as a win source
  (cairo-src) and recipe/build.sh passes -Dcairo. cairo.zig's tests
  (toolchain-test) check both pins.
- Records: R_HOME/share/licenses/cairo/ (COPYING, COPYING-LGPL-2.1,
  COPYING-MPL-1.1 and SOURCE: version, url, sha256, licence, the zig
  that built it). r-zig-slim's Windows licence is
  `(GPL-2.0-only OR GPL-3.0-only) AND (LGPL-2.1-only OR MPL-1.1)`.
- conda-forge's cairo, pango and harfbuzz leave Windows: pixi.toml and the
  recipe have them on unix only, and pixman on Windows.

win-arm64:
- pixi.toml: `win-arm64` in platforms. Windows dependencies are
  [target.win] (both arches), except uutils-coreutils (win-64 only: its
  win-arm64 builds, 0.11 and 0.12, refuse m2-coreutils, a run
  constraint) and the stress env (win-arm64 left out: conda-forge has no
  libgdal-core and others for it). The pkg feature has win-arm64's
  conda-publish task.
- The verification scripts' objdump on Windows is conda-forge's
  llvm-objdump (llvm-tools, both arches; binutils_impl_win-64 is x86_64
  only): verify-helpers.sh's needed_of, pkg-parity.sh's exports_of,
  verify-tree.sh's baseline-CPU disassembly.
- scripts/env.sh: PLAT on Windows from PROCESSOR_IDENTIFIER ("ARMv8 ..."
  on ARM), not uname: the MSYS2 tools are x86_64 binaries, which Windows
  on ARM runs under emulation, so their uname says x86_64. verify-tree's
  VEX/EVEX check and verify-helpers' link_object key off PLAT.
- One Windows config, zigbuild/config/win-full (was win-x86_64-full):
  gnuwin32's config.h picks R_CPU and R_PLATFORM by __aarch64__, and R's
  Windows build keeps R_ARCH /x64 on aarch64 (MkRules.rules: WIN = 64),
  so nothing in it is the arch's.
- cfguard.o is x86_64 code: the recipe's package_contents and
  test-preflight.R expect it on win-64 only (rzig's build makes none for
  aarch64, rzig/build.zig).
- .github/workflows/win-arm64.yaml (new): toolchain, one build-r leg and
  conda-package plus conda-consume on windows-11-arm, on the label and on
  dispatch. Nothing publishes there.

## Lock

Written 2026-11-10 (the user: "Feel free to bump versions and update the
pixi lockfile when needed"), sha256 c651a6a6..., solved from the zig 0.17
lock (81c82a76...); `pixi lock --check` passes. It adds win-arm64 and
changes win-64 only:
cairo, pango, harfbuzz (and their fonts and fribidi/graphite2),
binutils_impl_win-64 and its MinGW sysroot leave; llvm-tools (llvm-objdump)
arrives. linux and macOS are unchanged.

## Tests

kappa (win-64, this lock, 2026-11-10): `pixi run --frozen` install,
toolchain-test, rzig-test, build, smoke, verify-tree, toolchain,
verify-toolchain, contract, pkg-parity (cli, digest, quadprog, Rcpp:
735 exports identical; the R CMD SHLIB shapes), check, hermetic, package,
package-toolchain, verify-package, then conda-package and
conda-consume: all exit 0. svg(), cairo_pdf(), cairo_ps() and
png/jpeg/tiff/bmp with type = "cairo" through the built R: correct
images. pkg-parity first failed here on Rcpp: rzig's nm panicked writing
to an MSYS2 pipe (zig 0.17's std, STATUS_PENDING); fixed in
feat-win-zig-binutils (rzig/stdio.zig, recorded in its PLAN.md), whose
files this branch carries. Linux (gamma): build, smoke, verify-tree,
toolchain, contract, toolchain-test, rzig-test.

win-arm64 itself is CI's (windows-11-arm, win-arm64.yaml). What its runs
found (2026-11-11):
- No zig: conda-forge's win-arm64 zig is Library/bin/aarch64-w64-mingw32-zig.exe;
  env.sh, rzig's find_zig.zig and the toolchain shims now look for it
  after x86_64-w64-mingw32-zig.
- PROCESSOR_IDENTIFIER names the ARM CPU inside the x64-emulated MSYS2
  bash: package-toolchain made R-4.6.1-win-arm64-* archives.
- verify-toolchain's build-tools check: every MSYS2 program in the tree's
  usr/bin exited non-zero with no output when the script's own MSYS2 bash
  started it, while the tree's sh.exe started from cmd.exe ran (the
  mount-table check passed). R starts them from a native process, so the
  check now runs each through cmd.exe (run_cmd), and a failure names the
  exit status. Unchanged on win-64 (kappa: toolchain, verify-toolchain).
- With that, the toolchain leg passed, and the build leg built R and passed
  verify-tree and smoke. contract: Rscript ended in a segfault after
  attaching data.table and before getDTthreads' lines (data.table's
  grouped sum, its OpenMP, evalCpp or a package load: the run does not
  say which). build-r.yaml has a TEMPORARY probe step for windows-11-arm
  after a failure: each contract step in its own R process, and an OpenMP
  library from R CMD SHLIB. It goes once the contract passes. Its first
  run: every package loads and evalCpp gives 4 (a run-time C++ compile
  and load works), then data.table's `dt[, sum(x), by = g]` with
  setDTthreads(1) segfaults; set -e ended the probe there. The probe now
  goes on past a crash, runs the OpenMP library first, data.table's
  grouped sum in parts, and the grouped sum under cdb when the image has
  Windows' debugger.
- Its second run: a plain OpenMP library (one shared variable) runs on
  one thread and on four; data.table creates, prints and sums a table,
  and crashes in everything that sorts (order, forderv, the grouped sum,
  with or without GForce), on one thread too; minqa, quadprog and ps
  pass. cdb: an access violation (`ldr w0,[x11]`, x11 = 0) in
  data.table's outlined parallel region, called from
  `libomp!__kmp_invoke_microtask+0xcc`.
- Cause: conda-forge's win-arm64 libomp.dll (llvm-openmp 23.1.5
  hef4af3d_0, clang-cl) carries libomp's C fallback for
  __kmp_invoke_microtask (z_Windows_NT-586_util.cpp), not the assembly
  one (z_Linux_asm.S). For a region with more than six shared variables
  that C code copies the rest into an alloca buffer it expects at the
  stack pointer; the compiler drops the copy as dead code. Disassembled:
  the argc > 6 path loads x2..x7 and calls `blr x8` with nothing on the
  stack, returning to +0xcc, cdb's frame. The 7th and later arguments are
  garbage. data.table's sort regions have more than six; the probe's had
  one. win-64 is not affected (x86_64 uses the MASM file).
- Fix (2026-11-12, chore-release-11): libomp is flang-pixi's build on
  every platform, llvm-openmp 23.1.5 with a `zig_*` build string from
  `universe`, which has the assembly `__kmp_invoke_microtask` on
  win-arm64 (flang-pixi tests a region with many shared variables,
  omp_many_args.f90). One libomp built one way on all six platforms, not
  a win-arm64 exception. pixi.toml, the recipe and the lock name it;
  r-zig-slim's run dependency requires a `zig_*` build, so a user's env
  cannot take conda-forge's.
- upstream zig on windows-latest (not ARM): `zig fetch` of cairo from
  cairographics.org failed once with TlsInitializationFailed; on kappa the
  same zig 0.17.1 failed once, then fetched it seven times from both hosts
  (same hash). Intermittent; conda-forge's zig fetched it on both Windows
  legs. Re-run.

Checked without the runner (2026-11-10): `rattler-build build
--render-only --with-solve --target-platform win-arm64` renders and
solves the recipe (cfguard.o not expected; pixman in, no cairo, pango or
harfbuzz); the same for win-64 (cfguard.o expected; r-zig-slim's
licence with cairo's). zigbuild/cairo.zig builds for aarch64- and
x86_64-windows-gnu, and a test program using it (PNG with a GDI font and
alpha, PDF, PS, SVG) runs correctly on kappa (x64).

## Not done

- Done 2026-11-12 (chore-release-11): windows-11-arm is a leg of
  build.yaml's toolchain, build (core tier) and conda-package jobs, with
  the publish; win-arm64.yaml and the `win-arm64` label are gone. The
  temporary probe in build-r.yaml goes when the contract passes there.
- Stress on win-arm64 (no GDAL and others on conda-forge).
- ARM64 Control Flow Guard: rzig has a stub for x86_64 only; whether an
  ARM64 package built with CFG links is open.
