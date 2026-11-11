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

win-arm64 itself is CI's: the first run will show
what x86_64 assumptions remain in the scripts' Windows branches (they
were written on win-64). Unverified until then: that
PROCESSOR_IDENTIFIER names the ARM CPU inside the x64-emulated MSYS2
bash (env.sh's PLAT); if it does not, every PLAT-keyed step says win-64.

Checked without the runner (2026-11-10): `rattler-build build
--render-only --with-solve --target-platform win-arm64` renders and
solves the recipe (cfguard.o not expected; pixman in, no cairo, pango or
harfbuzz); the same for win-64 (cfguard.o expected; r-zig-slim's
licence with cairo's). zigbuild/cairo.zig builds for aarch64- and
x86_64-windows-gnu, and a test program using it (PNG with a GDI font and
alpha, PDF, PS, SVG) runs correctly on kappa (x64).

## Not done

- Publishing win-arm64: build.yaml's conda-package matrix gains it once
  win-arm64.yaml's legs pass.
- Stress on win-arm64 (no GDAL and others on conda-forge).
- ARM64 Control Flow Guard: rzig has a stub for x86_64 only; whether an
  ARM64 package built with CFG links is open.
