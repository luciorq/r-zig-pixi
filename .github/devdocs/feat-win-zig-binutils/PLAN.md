# feat-win-zig-binutils — Windows' binutils from zig and rzig

Branch feat-win-zig-binutils, stacked on feat-zig-017 (which carries
feat-zig-pkgconf): zig 0.17 only. Status: implemented and tested on linux-64 and kappa (2026-11-09); not run on CI or on an ARM machine.
(2026-11-12: merged into main as #47. CI has since run it on every
platform, windows-11-arm included, on #48 (run 43344258167).)

## Why

On Windows, R's makefiles, R CMD check and CMake run nm, objdump, strip,
dlltool, windres and as. Until now they were conda-forge's GNU MinGW
binutils (`binutils_impl_win-64` 2.46.1), copied with the `zstd.dll` and
`vcruntime140.dll` they load into the build-tools group's
`R_HOME/bin/toolchain/binutils/` (feat-standalone-toolchain B24, B41), and
R's own build ran `x86_64-w64-mingw32-nm` and `-dlltool` through `sh` for
its import stubs. That was:

- a second toolchain beside zig, for six commands;
- x86_64 only: conda-forge has no `binutils_impl_win-arm64`, so it
  blocked Windows on ARM;
- a GPL-3.0 payload and two extra DLLs in r-zig-build-tools, and a
  `binutils_impl_win-64` dependency in the recipe's build and host envs.

zig 0.17 ships `zig dlltool` (llvm-dlltool), `zig rc` (resinator, which
writes a COFF object directly), `zig ar`/`ranlib` and `zig objcopy`/`objdump`
(ELF and partial COFF). What it lacks, a GNU-format `nm`, an `objdump -p`
in GNU's layout and a COFF `strip`, rzig now does itself: it already read
COFF symbol tables for `rzig def` (def.zig).

## Design (implemented)

rzig gains six names (zigbuild/tools/rzig/binutils.zig), installed beside
gcc.exe in `R_HOME/bin/toolchain` on Windows, the base's (r-zig-slim's)
on every channel, as zig-ar.exe is:

| name | does | notes |
|---|---|---|
| nm | reads COFF objects, archives (GNU/BSD long names), short import objects | BSD format by default, `-P`, `-g`, `-u`, `-U`, `-p`, `-n`, `-r`, `-A`, `-a`; GNU's letters for COFF (T D R B C U W A I, lowercase locals) |
| objdump | `-h`, `-f`, `-p`, `-t`, `-x` for PE images and COFF objects | GNU's text layout where R parses it: sotools.R's `read_symbols_from_dll` (`\tDLL Name:` ... three lines ... `The Export Tables`) |
| strip | `--strip-debug`, `--strip-unneeded`, `-s`, `-o` | objects and archive members lose `.debug*` sections (headers kept, emptied, LNK_REMOVE: section and symbol numbers unchanged); archives rewritten by `zig ar crs`; an image loses a trailing COFF symbol table; zig's DLLs have neither (debug goes to .pdb), so they are left as they are |
| dlltool | `zig dlltool` | GNU's `--input-def/-d`, `--output-lib/-l`, `--dllname/-D`, `-k`, `-m`; `--as`, `-f`, `-t` dropped; machine from rzig's target |
| windres | `zig rc /:output-format coff /:target <m> /:auto-includes gnu` | GNU's `-i/-o` and positional, `-O`, `-J`, `-F`, `-I`, `-D`, `-U`, `-l`, `-c`; `--preprocessor[-arg]` dropped (zig rc preprocesses and defines RC_INVOKED) |
| as | `zig cc -c -x assembler` | `-o`, `-I`; one input |

Elsewhere:

- Makeconf.win: `NM`, `DLLTOOL`, `RESCOMP`, `OBJDUMP`, `STRIP_*` through
  `$(BINPREF)`, as R's own template does for MinGW (no `--as`, no
  `--preprocessor`); verify-tree checks every `$(BINPREF)` name is a file
  beside rzig (but the LTO block's gcc-nm, B43-2) and nothing goes
  through `$(LLVMPREF)`.
- Rcmd_environ: `R_ZIG_RC` and `R_ZIG_NM` name rzig's windres.exe and
  nm.exe; the `RCFLAGS` default (gcc as windres' preprocessor) is gone.
- R's build.zig: `winMakeImportStub` runs `rzig def` and `rzig dlltool`
  (Run steps, no `sh`, no pipe): the same symbol set gnuwin32's R0.def
  has (`nm | sed $(SYMPAT) | ... $(NM_FILTER)`).
- The toolchain build: no `binutils/` directory; with it the copy
  mechanism's `in_conda` flag (binutils were its only user) is gone: the
  conda build copies nothing, and builds pkgconf only. env.sh's
  build-tools group is `usr etc`.
- recipe.yaml: `binutils_impl_win-64` leaves the build and host envs,
  `zstd` leaves r-zig-build-tools' run deps (r-zig-slim keeps it: R.dll
  links it), r-zig-build-tools' win-64 licence is `ISC AND ZPL-2.1`
  (pkgconf and the CRT startup), r-zig-slim's package_contents lists the
  six names, and no package may hold `binutils/`.
- rzig's `--rzig-check=build-tools` no longer looks for binutils (they are
  rzig): its Windows line is `make at ...; sh at ...`.
- pixi.toml keeps `binutils_impl_win-64` in the win-64 dev env for the
  verification scripts' own `x86_64-w64-mingw32-objdump` (import closures,
  baseline-CPU disassembly, pkg-parity's exports). Nothing R builds or
  ships runs it.
  (2026-11-12: replaced by conda-forge's llvm-tools (llvm-objdump) for
  both Windows arches in feat-win-arm64; pixi.toml has no
  binutils_impl_win-64.)

## Decisions taken (with the alternatives)

1. rzig personalities, not conda-forge's `llvm-tools` (llvm-nm,
   llvm-objdump, llvm-strip, llvm-rc, llvm-dlltool). llvm-tools exists for
   win-64 and win-arm64, but its exes load libLLVM (over 100 MB per
   group archive), print LLVM's formats (sotools.R parses GNU's), and are a
   second toolchain. zig's own dlltool and rc are LLVM's and resinator,
   already in every r-zig compilers group.
2. objdump and nm in rzig, not zig's `objdump`: zig 0.17's `objdump`
   prints its own layout (`--imports`, `--exports`, `--section-headers`)
   and has no `-p`/`-x`; sotools.R and R's makefiles need GNU's.
3. strip: debug sections only, not GNU's full `--strip-unneeded` (local
   symbol removal). zig links DLLs with no symbol table and puts debug
   information in a .pdb, so a package DLL has nothing to strip; R CMD
   INSTALL --strip runs STRIP_SHARED_LIB on exactly those. For static
   libraries (STRIP_STATIC_LIB, --strip-lib) the debug sections go, which
   is GNU's --strip-debug. An image with debug sections inside (not
   zig's) is refused with a reason rather than rewritten.
4. Names beside rzig in the base, not in the build-tools group: they are
   the compilers' tools as much as make's companions, and CMake finds
   them beside gcc.exe (CMakeFindBinUtils) as it finds ar.exe.

## Behaviour differences from GNU binutils

- nm: symbol sizes are not printed (COFF has none; GNU prints none either
  for COFF); `-C` (demangle) is accepted and does nothing; options GNU
  has and R never uses (`--size-sort`, `-l`, `-S`, the sysv and just-symbols
  formats) stop with a message.
- objdump: `-d` (disassembly) and `-s` are not there; `-x`'s symbol
  table is rzig's one-line form; an archive's members are listed with
  their headers.
- windres: reads `.rc` (and `.res` with `-J res`) only, never stdin;
  writes coff or res; preprocesses with zig rc's preprocessor (aro), not
  gcc: an `.rc` that relies on a gcc-only extension would differ.
- dlltool: import libraries only (`--output-exp`, `--output-def` and
  `-e` stop with a message); llvm-dlltool's short import format, which
  GNU ld and lld both read.
- as: one `.s` file through zig cc's integrated assembler.

## Tests

Linux (gamma, zig 0.17.1):

- rzig's unit tests: 182 of 182 (7 new in binutils.zig: nm letters and
  formats against def.zig's set, aarch64 objects, archives and
  llvm-dlltool import libraries; objdump -p/-x of x86_64 and aarch64 DLLs
  parsed as sotools.R parses them; objdump -h of a zig rc object; strip of
  an object with .debug$S/.debug$T, idempotent, symbols and code bytes
  unchanged, zig DLLs left alone; dlltool's, windres' and as' argument
  translation). Fixtures in testdata/ (bu.c, bu.def, bu.rc and what zig
  0.17.1 made of them for both machines).
- rzig cross-builds for x86_64-windows-gnu and aarch64-windows-gnu, its
  test binary too.
- The toolchain build's tests: 39 of 39.

kappa (Windows x64, 2026-11-09, the zig 0.17 lock with conda-forge's
zig 0.17.0, its own directory, deleted after; logs kept locally):

- `pixi run --frozen` install, rzig-test (155 pass, 27 POSIX-only skips;
  the binutils tests natively), toolchain-test, toolchain (no binutils/:
  flang/, openmp/, usr/ with pkgconf, etc/, zig/), verify-toolchain,
  build (R's import stubs through `rzig def` and `rzig dlltool`),
  package-toolchain, verify-package (both passes, all three scenarios:
  Makeconf's tools are files; R CMD config NM and OBJDUMP name rzig's;
  read_symbols_from_dll reads R.dll's 627 imports with rzig's objdump;
  the six names run with PATH = System32; tools.mk runs $(NM), $(DLLTOOL),
  $(AR), $(RANLIB), $(STRIP_STATIC_LIB), $(RESCOMP) -i r.rc and $(OBJDUMP)
  -p as R's makefiles do; btRc's resources through $(RESCOMP) in its DLL;
  R CMD check's nm through UserNM; the Git-MSYS clash), compile-tree,
  contract, and verify-tree (every $(BINPREF) name a file beside rzig):
  all exit 0.
- GNU against rzig on the same files (the old env's
  x86_64-w64-mingw32-objdump and -nm 2.46.1): a package DLL's imports as
  read_symbols_from_dll parses them, 25 and 25, identical; R.dll's, 597
  and 597, identical; `nm -Pg` on a package object, 6 and 6, the same
  names and letters.
- `R CMD check` of a package with C code and a `.rc` file (in
  Makevars.win's OBJECTS): installs, loads, and "checking compiled code"
  reports `puts` from `a.o`, the note GNU binutils give (it needs objdump
  -x on the DLL and nm on the object).

## Review fixes (2026-11-10)

An independent review of this change found these; each is fixed, with a
test:

- bigobj objects (LLVM writes one past 65,279 sections: template-heavy
  C++, or `-ffunction-sections` on a large file) were taken for short
  import objects: nm printed one garbage `I __imp_...` line and exited 0,
  so winshlib.mk's `$(NM) | sed` silently lost the object's exports, and
  strip left its debug sections. One COFF reader (binutils.zig's Coff and
  `records`) now reads the bigobj header (its class id; u32 section
  count, symbol table and count at offsets 44, 48, 52) and its 20-byte
  symbol records with 32-bit section numbers; a short import object must
  be version 0, and version 1 is "file format not recognized". nm,
  objdump, strip and rzig def (def.zig, tier 1's .def, which refused
  bigobj before) all use it, so both build paths read bigobj as GNU nm
  did.
- parity-test.sh still expected the binutils/ directory (5 failures in
  rzig-test on linux): its Windows checks now ask that the build-tools
  check names make and sh and nothing else, and that a missing sh is
  reported, with the group's text, for the check and for a configure
  script's package.
- llvm-ar's COFF archive (what `zig ar` writes for Windows) ends a long
  member name with a NUL, not "/\n": names came out with a NUL and
  `strip --strip-debug` of such an archive (R CMD INSTALL --strip-lib)
  failed. Both terminators are read.
- strip of a DLL with DWARF sections (`-gdwarf-4`, or MinGW's ld with
  -g) was refused: those sections are the image's last ones (lld and ld
  place them so, mapped and discardable), and strip now drops them as GNU
  strip does: the file cut where the last kept section's data ends, their
  headers zeroed, NumberOfSections, SizeOfImage (SectionAlignment) and
  the symbol table fields set, CheckSum 0; the kept sections' bytes and
  addresses unchanged. An image laid out otherwise (a kept section after
  a debug one, a data directory in a dropped section, a kept section
  named through the string table, a signature) is refused with a message
  that says so.
- nm: a weak external with section 0 (PE's WEAK_EXTERNAL; its default in
  an aux record) is `w`, weak and undefined, as BFD decodes it, and `W`
  in a section; `-u` and `--defined-only` follow. SYMPAT's [BCDRT] and
  sotools.R's `U` are unaffected.
- `@file` response files in all six tools (GNU's expandargv): rzig's
  response.zig, as rzig def and the compilers already read them.
- nm takes `-f`/`--format` with a separate value (`-f posix`,
  `--format posix`, `-fposix`, `-f p`), and `--plugin <file>` consumes
  its value; dlltool takes `--def` for `--input-def`.
- nm's headers are GNU's: a single archive prints its members' headers
  only; with more than one file each file's (an archive's too in BSD);
  POSIX writes `<member>:`, or `<archive>[<member>]:` with several files;
  `-A` prefixes `<archive>:<member>:` (POSIX `<archive>[<member>]: `).
  objdump with no file reads a.out, as GNU's (an error unless it exists).
- Arithmetic on a corrupt file's offsets (an image's RVAs, the export and
  import tables' entries, the PE header's offset) is done in 64 bits or
  usize: a bad file is an error, not a ReleaseSafe panic.
- Not changed, recorded: R's build.zig runs the target's rzig (`rzig def`
  and `rzig dlltool`) for R.dll's import stubs, on the build machine. A
  native build is unaffected; a cross build (an x64 machine building ARM
  R) could not run that rzig and would need a host rzig built beside it.

### Tests after the review (2026-11-10)

- Linux (zig 0.17.1): rzig's unit tests 187 of 187 (new: a bigobj
  fixture of 70,000 sections read by nm, def.zig and strip, aarch64's
  machine; a short import must be version 0; llvm-ar's NUL-ended long
  names; nm's -f/--format/--plugin and headers; dlltool --def; strip of
  x86_64 and aarch64 DLLs with DWARF sections, their layout, exports and
  SizeOfImage checked, and a kept section after a debug one refused);
  parity-test.sh 125 identical, 60 identical but for rzig's own
  additions, 33 deliberate differences, 0 failed; rzig and its test
  binary cross-build for x86_64- and aarch64-windows-gnu. A zig-built
  bigobj (34,001 functions, -ffunction-sections -g): nm lists all 34,001
  T symbols, strip --strip-debug empties its debug sections and the
  result links into a DLL exporting all of them. A zig ar archive with a
  long member name: nm names it, strip --strip-debug succeeds.
- kappa (the zig 0.17 lock, own directory, deleted after): `pixi run
  --frozen` install, rzig-test, toolchain, build, verify-tree,
  package-toolchain, verify-package and compile-tree, all exit 0; then a
  package whose src/big.c compiles to a bigobj (Makevars.win's
  -ffunction-sections, 34,001 functions; its probe object's header is
  version 2, and nm -Pg lists all 34,001): installs and `answer()` returns
  42 through rzig build (rzig def) and through R_ZIG_PKG_BUILDER=make
  (rzig's nm in winshlib.mk's .def rule); and a DLL linked with
  -gdwarf-4: strip --strip-unneeded removes its 4 debug sections, and it
  loads and its routine returns 7.

## Found after the tests (2026-11-10): rzig's writes to an MSYS2 pipe

pkg-parity, not in the kappa runs above, failed on kappa in
feat-win-arm64's chain: Rcpp's DLL from the make path exported 622 names
(and _CRT_INIT), rzig build's 735. rzig's nm had panicked ("reached
unreachable code") in winshlib.mk's `$(NM) $(OBJECTS) | sed ... >>
tmp.def`, so tmp.def held only EXPORTS and lld exported every symbol;
make went on. The make-path bigobj test above passed the same way, by
auto-export, not through the .def.

Cause: zig 0.17's blocking write on Windows (std/Io/Threaded.zig,
fileWriteStreamingWindows) treats NtWriteFile's STATUS_PENDING as
unreachable. MSYS2 creates its pipes as overlapped handles, so a write
larger than the pipe's buffer (Rcpp's listing is 342 KB; cli's, digest's
and quadprog's fit) returns PENDING. A cmd.exe pipe, a file and a
console are synchronous and were never affected.

Fix: zigbuild/tools/rzig/stdio.zig: rzig's own stdout and stderr writes
(nm's and objdump's text, echoed command lines, messages, --version
lines, `rzig build`'s plan and shlib output) go through a writeAll that
does what kernel32's WriteFile does without an OVERLAPPED: on PENDING,
wait on the handle, then read the status block; and an Io.Writer whose
drain is that writeAll. Not Windows: std's writeStreamingAll. Checked on
kappa: the six Rcpp objects' nm listing (342,403 bytes) through an MSYS2
pipe to sed, to a file, appended (`>>`), and through a cmd.exe pipe, all
complete; a pipe closed early (`| head -1`) ends nm with status 1, as
GNU nm ends on SIGPIPE. Then feat-win-arm64's whole kappa chain,
pkg-parity included (see that branch's PLAN.md).

## Remaining for Windows on ARM

(2026-11-12: feat-win-arm64 (#48) settled most of this; its PLAN.md has
the details. One Windows config, zigbuild/config/win-full, serves both
arches (config.h picks R_CPU by `__aarch64__`). cairo is r-zig's own
build (zigbuild/cairo.zig) on both Windows arches; pango and harfbuzz
are not used. The verification scripts use conda-forge's llvm-objdump
on Windows. The runner is windows-11-arm, a leg of build.yaml. Still
open: ARM64 Control Flow Guard (rzig has the stub for x86_64 only), and
building ARM R on an x64 machine, which nothing needs: CI builds
natively.)

- A `win-aarch64-full` vendored config (config.h, Rconfig.h,
  Makeconf.win, from a configure run on an ARM machine), and build.zig's
  Arch/platform names for it (`win-arm64`).
- conda-forge's win-arm64 has no cairo, pango or harfbuzz: Windows R's
  cairo device needs a decision (build without it on ARM, or build them).
- The verification scripts' disassembly (baseline CPU) and import
  closures use x86_64 MinGW objdump: on ARM, rzig's objdump -p gives the
  imports; the baseline check needs another disassembler or none on ARM.
- `cfguard.o` is x86_64 code (rzig_build.linkObject returns none for
  aarch64): ARM64 Control Flow Guard needs checking on a real machine.
- A runner: GitHub's windows-11-arm, or an ARM host for the test loop.
- R.dll's import stubs run the target's rzig on the build machine
  (build.zig): building ARM R on an x64 machine would need a host rzig;
  native ARM builds are unaffected.
