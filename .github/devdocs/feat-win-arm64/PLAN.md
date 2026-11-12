# feat-win-arm64 — Windows on ARM (status and open decisions)

The last item of the user's order of 2026-10-22 (pkgconf from source, the
zig 0.17 port, Windows on ARM). Not implemented: nothing here can be
tested without an ARM Windows machine, because R's build runs the R it
builds (the bootstrap), and x64 Windows cannot run ARM64 code.

## In place after feat-zig-pkgconf, feat-zig-017 and feat-win-zig-binutils

- zig: conda-forge zig 0.17.0 has a win-arm64 build; PyPI ziglang 0.17.1
  has win_arm64, pinned in scripts/fetch-zig.sh.
- Fortran: flang-pixi's flang-zig 7, lld-zig 6 and flang-rt-zig 11 are
  on universe for win-arm64.
- Build tools: pkgconf builds for aarch64-windows-gnu (pkgconf.zig takes
  the host's arch). The MSYS2 tools are conda-forge's m2 packages, noarch
  x86_64 MSYS binaries, which Windows on ARM runs under emulation.
- Binutils: rzig's nm, objdump, strip, dlltool, windres and as
  (feat-win-zig-binutils) take the machine from the target; conda-forge
  has no win-arm64 MinGW binutils, so this was the blocker.
- rzig cross-builds for aarch64-windows-gnu, and its Windows test binary
  passes on x64.

## conda-forge win-arm64, R's dependencies (2026-11-09)

Present: zig, curl, zlib, bzip2, xz, liblzma-devel, pcre2, libcurl, icu,
libdeflate, llvm-openmp, expat, fontconfig, freetype, libpng, glib,
libjpeg-turbo, libtiff, tk, gettext, uutils-coreutils, zstd,
vc14_runtime, openblas; tzdata and the m2 packages are noarch.

Missing: cairo, pango and harfbuzz (R's Windows cairo devices, the
`type = "cairo"` png/svg/pdf), and binutils_impl (no longer needed).

## Open decisions (the user's)

1. How to get an ARM Windows host:
   - A ★ GitHub's hosted `windows-11-arm` runner, behind a label as the
     upstream-zig legs are (free for public repositories);
   - B a local ARM machine (none of the test hosts is one);
   - C wait.
2. Cairo on win-arm64. Without it, svg(), cairo_pdf(), cairo_ps() and
   png(type = "cairo") fail on win-arm64 only, a platform difference the
   project exists to remove. The windows() screen device,
   png/jpeg/bmp/tiff through GDI, and pdf() and postscript() do not use
   cairo.
   - A ★ build the missing libraries (cairo, pango, harfbuzz, and pixman
     or fribidi if they are missing too; not yet checked) for win-arm64
     with zig, the same way as pkgconf;
   - B ship without cairo first, list the missing devices in the README,
     and add cairo later;
   - C wait for conda-forge.
3. The vendored config (zigbuild/config/win-arm64-full/): captured on the
   ARM host by gen-config, as every other platform's was.
4. Control Flow Guard: rzig's cfguard.o is x86_64 code; ARM64's CFG
   support in zig's MinGW CRT needs checking on the host.
5. pixi.toml gains win-arm64 in `platforms`, which re-solves pixi.lock.

Note: R's build.zig runs the target's rzig (`rzig def`, `rzig dlltool`)
on the build machine for R.dll's import stubs. A native ARM build (option
1 A or B) is unaffected; building ARM R on an x64 machine would need a
host rzig built beside the target's (feat-win-zig-binutils review, L5).
