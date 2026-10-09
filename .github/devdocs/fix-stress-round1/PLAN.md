# fix-stress-round1: the stress suite's round 1 fixes

Branch fix-stress-round1, from main 7a3004d (PRs #14, #17, #18, #19).
The answers: feat-stress-suite stress/results/2026-10-08.md, "Decisions
for the user", all recommended options (the user, 2026-10-08).
Implementer A writes the rzig sections; implementer B the Windows tree
and the recipe (below).

## rzig (implementer A)

**Status (2026-10-08).** Implemented on branch fix-stress-round1 (main
7a3004d), not committed. Tested by its implementer on linux-64 (gamma),
with both zigs: unit tests, parity, smoke, real links and an R package
unload (see "Tested, rzig"). Then tested on linux-64, osx-arm64 and
win-64 with the stress suite ("Tested on the hosts", at the end), and
reviewed ("Review", at the end: four code items open).

The user's answer to decisions 1 to 11 of the results' "Decisions for
the user" (2026-10-08, "Everything sounds exactly right"): every
recommended option. Here that is S1 to S11, one rule each:

| item | round 1 | rule | where |
|---|---|---|---|
| S1 | Z1 | `-Wno-error=date-time` on every call | compiler.zig |
| S2 | Z2 | -L inside -Wl, or -Xlinker, and --library-path, become a plain -L | linker_args.zig |
| S3 | Z3 | the linker option --dependency-file goes, in every spelling | linker_args.zig |
| S4 | Z4 | linux links with a version script get `-Wl,--undefined-version` | compiler.zig |
| S5 | Z5 | `-march=armv<N>[.<M>]-a[+ext]` becomes `-mcpu=generic+v<N>[_<M>]a[+ext]` | compiler.zig |
| S6 | Z6 | an ar archive input without zig's extension goes as an .a copy | archives.zig |
| S7 | Z7, R1 | Windows: `-c` without `-o` names `<stem>.o`; the tool named from the long path | windows.zig, main.zig |
| S8 | Z8 | --allow-multiple-definition and -z muldefs go, in every spelling | linker_args.zig |
| S9 | Z9 | linux shared links get a crtbeginS-like object | dso_fini.zig |
| S10 | R2 | the environments' -L and rpath come after the caller's arguments | compiler.zig |
| S11 | Z10 | `-g0` unless the caller passes a -g option | compiler.zig |

Files: zigbuild/tools/rzig/compiler.zig, linker_args.zig (new),
archives.zig (new), dso_fini.zig (new), cache.zig (new), cmdline.zig,
Ctx.zig, main.zig, windows.zig, fortran.zig, libcxx_mirror.zig,
parity-test.sh, smoke-test.sh; toolchain/zig-cc and zig-cxx.

### The command line

What rzig runs for zig-cc, zig-cxx, gcc.exe, g++.exe and zig-fc's
shared links:

    zig cc|c++ -fno-sanitize=undefined -mcpu=baseline -Wno-error=date-time
        [-g0] [<target>] [-F<SDK frameworks>] [<soname>]
        [-Wl,--undefined-version] [<dso_fini.o>] <caller's, rewritten>
        [<environments' -L and rpath>] <environments' headers> [-lomp]
        [-L<SDK>/usr/lib]

The caller's arguments are rewritten in this order: -mtune= dropped
(#14), -march=armv*-a (S5), linker options (S2, S3, S8), the Fortran
runtime (#19), archive inputs (S6), and on Windows `-c` without `-o`
(S7). Then the SONAME, S4, S9 and S11 are decided on them, and the
environments' flags added (S10).

### S1 (Z1): -Wno-error=date-time

zig cc adds `-Werror=date-time` at -O1 and above, so `__DATE__` or
`__TIME__` stops the compile: duckdb on every OS (its bundled pcg
header), arrow's bundled mimalloc on linux and macOS. gcc and clang
only warn, with -Wdate-time. rzig adds `-Wno-error=date-time` to every
call, after -mcpu=baseline. `zig cc -###` shows zig's own flag before
it, and the caller's flags after it, so a package's own
`-Werror=date-time` still wins (unit test). The compile then prints
clang's warning. On a link line the flag does nothing.

### S2, S3, S8 (Z2, Z3, Z8): linker options zig cannot take

linker_args.zig, one rule per option, for every spelling: inside -Wl,
as one item or two (`-Wl,-L,dir`), after -Xlinker (`-Xlinker -L
-Xlinker dir`), and for -z also on its own (`-z muldefs`).

- S2: `-L<dir>`, `-L <dir>`, `--library-path=<dir>` and
  `--library-path <dir>` become the driver's `-L<dir>`, in the same
  place ("error: unsupported linker arg: -L...", RcppParallel's
  `-Wl,-Ltbb/build/lib_release` on every OS). The other items of the
  same -Wl, stay one -Wl,. An -L with no value is left alone, for zig
  to report.
- S3: `--dependency-file=<file>` and `--dependency-file <file>` go.
  conda-forge's zig panics on it ("index out of bounds"), upstream's
  segfaults. CMake (4.4 in round 1) adds `-Xlinker
  --dependency-file=...` to every ELF link when the linker it found
  lists it in --help, as lld-zig's ld.lld does on the dev env's PATH:
  RcppParallel's TBB, Rhdf5lib's libaec, arrow's zlib. The file only
  tells CMake when to relink; CMake builds and rebuilds without it, and
  which linker it finds no longer matters. clang's own
  `-dependency-file` (a compile's) is not touched.
- S8: `--allow-multiple-definition`, `-allow-multiple-definition`, `-z
  muldefs` and `-zmuldefs` go ("unsupported linker arg", StanHeaders'
  Makevars.win). With nothing defined twice the link is the same; a
  real duplicate now fails loudly (checked: "ld.lld: error: duplicate
  symbol"). Other -z keywords stay.

### S4 (Z4): --undefined-version

ld.lld stops at a version script that names a symbol the link does not
define (its default since LLVM 16); GNU ld does not (oneTBB's
tbbmalloc, in RcppParallel). Linux links whose arguments contain
`-version-script` (one dash or two, joined or not) get
`-Wl,--undefined-version` before the caller's arguments, so a caller's
`--no-undefined-version` still wins (checked with ld.lld). Compiles,
macOS and Windows get nothing. As with GNU ld, a real mistake in a
version script then passes.

### S5 (Z5): -march=armv<N>-a

zig reads -march as a CPU name: "unknown CPU: 'armv8'", also with
+crc (arrow's CMake pthread probe, then its bundled aws-checksums, on
macOS; linux-aarch64 has the same zig behaviour). rzig writes
`-march=armv<N>[.<M>]-a[+ext...]` as `-mcpu=generic+v<N>[_<M>]a`, with
each extension in zig's name: simd neon, fp fp_armv8, fp16 fullfp16,
rdma rdm, rng rand, memtag mte, profile spe (the seven clang names zig
does not take, checked one by one against zig's aarch64 features), `-`
as `_` (sve2-aes), and no<x> as -<x>. The version must be digits and
dots; anything else (CPU names, armv8-r, armv8-m.main) is kept. On
every arch: it names an Arm architecture, which zig refuses elsewhere
in either spelling. Four more clang names zig spells otherwise (fcma,
jscvt, pmuv3, predres2): "Review", 4.

With #14's -mcpu=baseline: rzig puts -mcpu=baseline first and the
rewritten flag where the caller put it, later, and zig takes the last.
Checked with `zig cc -###`: on aarch64-linux the compile's target-cpu
is generic with +crc, on aarch64-macos generic (not apple-m1) with
+crc. So a package's own architecture wins, as its -march would; for
arm64 macOS that is below the apple-m1 baseline, which is what the
package asked for. rzig's printed command lines, run with the target
switched to aarch64-linux-gnu.2.17 and aarch64-macos.13.0, compile a
`__crc32b` call.

Open ("Review (2026-10-09)", 1): S5 also rewrites a -march that is the
value of `-Xarch_<arch>`. zig hands that value to clang's driver as it
is, and clang refuses zig's -mcpu spelling. abseil's CMake on macOS
passes `-Xarch_arm64 -march=armv8-a+crypto`, so s2's bundled abseil
fails (R2-4's conda run on omicron).

### S6 (Z6): an archive named without an extension

zig cc classifies an input by its name and stops at one it does not
know ("unrecognized file extension", on every target), where ld64 and
GNU ld read the file. V8 on macOS links `../.deps/v8_monolith`, an
archive its autobrew script renamed. Rule: on a link line, an input
file (not an option or an option's value) whose name has none of zig's
library or object extensions (.a .lib .o .obj .lo .so .so.<N> .dylib
.tbd .dll, the names zig cc took an archive under, each tried) and
that starts with `!<arch>\n` goes to zig as
`<cache>/archive-<key>/<name>.a`, the key from its bytes (SHA-256).
Everything else passes unchanged. Found on omicron: V8's file is a
universal (fat) file of two ar archives, x86_64 and arm64, which this
rule does not take yet, so V8 still fails ("Review", 2).

Why a copy keyed by content: it works on every OS and file system and
is never stale. A symlink needs a privilege on Windows. A hard link
fails across file systems (the cache is in $HOME, builds often in
/tmp), and shares later in-place writes to the original, so a content
key could come to name other bytes. Keyed by path, a copy goes stale
when the archive changes. The cost: the archive is read once per link,
and copied once per distinct content. Thin archives (`!<thin>`) are
left alone, since their members are paths relative to them. The shims
do not do this (deliberate in parity).

### S7 (Z7, R1): Windows

- windows.zig objSuffix (round 1's rzig-3, applied by hand): with
  `-c`, no -S, -E, -M or -MM, no output named (`-o <file>`,
  `-o<file>`) and one source file among the inputs, rzig appends `-o
  <stem>.o` (the base name, in the current directory), as MinGW gcc
  names it; zig would write `<stem>.obj` (QuickJSR's libquickjs.o,
  then rstan). -M and -MM are new here (with -c they mean -E). It runs
  before the environments' flags, so the `-o` stays among the caller's
  arguments.
- main.zig (rzig-3): when argv[0] names no tool on a Windows host (R
  starts programs by their 8.3 short path, G__~1.EXE for g++.exe), the
  tool is named from this binary's long path (GetLongPathNameW, which
  selfExe already used for the environment rule). This covers
  ZIG-RA~1.EXE and GCC-RA~1.EXE too.

### S9 (Z9): the finalization object of linux shared libraries

zig links linux-gnu shared libraries without crtbeginS.o, so nothing
calls `__cxa_finalize` at dlclose and lld's `__dso_handle` is the
image base: handlers registered with __cxa_atexit (C++ static
destructors) or atexit stay registered, and glibc calls them at exit,
after the code is unmapped (lme4 and fstcore after unloadNamespace, a
Stan model; exit status 139).

dso_fini.zig: round 1's fini2.c, embedded, with one change:
`__dso_handle` is weak. It is compiled once with the zig that links,
for the target it links (`cc -target <t> -mcpu=baseline
-fno-sanitize=undefined -O2 -g0 -fPIC -c`), into
`<cache>/dso-fini-<key>/dso_fini.o`, next to the dso_fini.c it was
compiled from. The key: SHA-256 of the source, the target triple, the
zig command and what `zig version` prints (one `zig version` run per
linux shared link, about 30 ms). Safe under parallel make: the source
is written atomically, the object compiled under a random temporary
name and renamed into place; jobs that race write the same bytes.

Which links: linux, `-shared` as a word, no compile-only flag, and
neither `-nostartfiles` nor `-nostdlib` (gcc leaves crtbeginS.o out
then, and so does rzig). It goes first among the inputs, after the
SONAME and S4's flag, where gcc puts crtbeginS.o: its .fini_array
entry is the first, so it runs last, after the library's own
destructors. A link that names a crtbeginS.o itself (without
-nostartfiles) still links: the weak `__dso_handle` yields to its
strong one, and the second `__cxa_finalize` finds nothing left
(checked with gcc 13's crtbeginS.o). Executables, archives, macOS and
Windows are untouched (macOS: dyld does not unload images with
thread-local variables, and all 76 packages exited 0 on omicron;
Windows: nine packages, no crash). zig-fc's shared links get it too,
through compiler.zig. When the object cannot be made (no writable
cache, zig fails) the link goes on without it, with a warning.

Why weak: round 1 tested a strong definition. A strong one would make
a duplicate-symbol error out of a link that brings its own crtbeginS.o;
weak changes nothing otherwise (checked: the same unload results).

### S10 (R2): the environments' -L and rpath after the caller's

envFlags put the environments' `-L<dir>/lib` (and a conda env's
`-Wl,-rpath,<dir>/lib`) before the first -o, where Makeconf's LDFLAGS
sat, so the environment's library won over a package's bundled one of
the same name: with tbb-devel in the env, RcppParallel bound the env's
TBB (linux: NEEDED libtbb.so.12, RUNPATH env first; Windows: conda's
MSVC tbb.lib). Now they come after the caller's arguments, with the
headers (which already did). zig and lld search every -L directory for
every -l whatever its place, so only the order among -L directories
changes: the caller's first. The same for RUNPATH. Everything else of
environment.zig's rule stays: which environments, -I after the
caller's, rpath for conda envs only, -lomp. On macOS the SDK's -L stays
last.

Checked: an environment libfoo (SONAME libfoo-env.so) and a package's
libfoo (libfoo-pkg.so), `-Lpkg/lib -Wl,-rpath,$ORIGIN/pkg/lib -lfoo`
with R_ZIG_EXTRA_ENV naming the environment: main's rzig binds
libfoo-env.so with RUNPATH env first; this one libfoo-pkg.so with
`$ORIGIN/pkg/lib` first.

### S11 (Z10): -g0

zig cc emits DWARF without -g (`-debug-info-kind=constructor` at -O2),
and Makeconf's CFLAGS are -O2 alone. rzig adds `-g0` to every call
unless an argument starts with `-g` (-g, -g0 to -g3, -ggdb*, -gdwarf*,
-gline-tables-only, -gsplit-dwarf, ...: the caller chose). A C++
object: 95,608 bytes with -g, 4,832 without. On a link line -g0
changes nothing (the same bytes, checked).

Found, not decided: a linux C++ package library still carries the
DWARF of zig's own libc++ and libc++abi, which zig builds with debug
info whatever -g0 says (a small C++ package: 1.17 MB of 1.51 MB;
`strip --strip-debug` leaves 0.34 MB). Removing it would take a
linker strip on linux links without -g (`-Wl,--strip-debug`), a new
rule for the user to decide.

### rzig's cache

cache.zig: `${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/r-zig`; on a
Windows host `%LOCALAPPDATA%/r-zig` comes before HOME ("After the
review", 3). Shared with the libc++ mirror:

- zig-lib-<cksum>/: the libc++ mirror (unchanged);
- dso-fini-<key>/dso_fini.c and dso_fini.o: S9;
- cfguard-<key>/guard_dispatch.S and guard_dispatch.o: R2-1 (Windows);
- archive-<key>/<name>.a: S6.

### The shims and parity-test.sh

toolchain/zig-cc and zig-cxx do S1, S2, S3, S4, S5, S7 (in the Windows
branch), S8 and S11 the same way, line for line (zig-cxx with short
comments). Not in the shims: S9 (an object compiled into the cache)
and S6 (an archive copied into it); S10 is rzig's environment rule,
which the shims never had. The shims' S7 counts sources among the
arguments that do not start with `-` (rzig skips option values too).

parity-test.sh:
- every case now carries `-Wno-error=date-time` and `-g0` on both sides;
- S9's object is taken out of rzig's side like its own -L, after
  checking it is there exactly when the rule says (a linux link,
  `-shared` as a word, no -nostartfiles or -nostdlib, no compile-only
  flag), and reported as ok+; the zig stand-ins write the object rzig
  asks them to compile;
- S6 is a CASE_DELIBERATE (the path of the copy, from sha256sum), and a
  `check` compares the copy with the archive;
- new cases: -g options, -Werror=date-time, -march rewrites and the
  values kept, every linker-option spelling (-Wl,, -Xlinker, -z, two-item
  forms, empty items), version scripts, the S9 object (with the cache
  directory's files as state), -nostartfiles and -nostdlib, archives on
  each OS, Windows -c without -o (and four cases that stay unchanged),
  StanHeaders' line, macOS's none-off-linux cases.

smoke-test.sh: the shared libraries are no longer byte-identical to the
shims' build (rzig's have S9's object); objects, archive and program
still are. It now checks that rzig's .so files have a .fini_array and
the shims' do not, and that a C++ library with a static destructor
unloads cleanly (dlopen, dlclose, exit 0).

### For implementer B (scripts/)

- scripts/contract-test.sh line 175 checks `lo < le < o` (the
  environments' -L before -o). With S10 it is `o < lo < le`: both
  after -o, R's own before R_ZIG_EXTRA_ENV's. The rpath check (`re =
  le + 1`) and the header checks still hold. Line 195's message says
  "-L before -o".
- The dry runs (RZIG_PRINT_ARGV) of a linux `-shared` link in
  contract-test.sh, wheel-test.sh, verify-bundle.sh and
  recipe/test-toolchain.R now compile S9's object into the cache as a
  side effect (with the real zig; a warning and no object if the cache
  is not writable) and print its path among the arguments. None of
  their checks looks at it.

### Tested, rzig (linux-64, gamma)

pixi.lock 7aef60ff...a355a63 (main's), unchanged. conda-forge's zig
0.16.0 (the worktree's default env) unless said otherwise; upstream is
PyPI's ziglang 0.16.0.

- `pixi run --locked rzig-test`: 68 of 68 unit tests (46 before);
  parity 68 identical, 45 ok+, 21 deliberate, 0 failed (98 cases
  before, 134 now). With upstream zig: the unit tests 68 of 68, and
  parity with an rzig it built, the same counts. `zig fmt --check`
  clean.
- Mutation checks of the harness, on a scratch copy: a shim that keeps
  -zmuldefs, a shim that adds -g0 after -ggdb3, a shim that drops rng,
  a shim without the .o naming, and an rzig that adds S9's object to a
  -nostartfiles link each fail exactly the case that covers them;
  putting the environments' -L back before -o fails six unit tests.
- Cross-compiled rzig and its unit tests (not run) for
  x86_64-windows-gnu, aarch64-macos, x86_64-macos and
  aarch64-linux-musl.
- smoke-test.sh part 1: passes, with the new unload check.
- Real links through rzig copies, both zigs: `__DATE__ __TIME__` at -O2
  compiles (S1); `-Wl,-Ltbb/lib -ltw` and `-Xlinker -L -Xlinker
  tbb/lib` link (S2); `-Xlinker --dependency-file=CMakeFiles/x.d` links
  (S3); a version script naming an undefined symbol links, and fails
  with the caller's `--no-undefined-version` (S4); `.deps/tw_monolith`
  links (S6); `-Wl,--allow-multiple-definition -Wl,-z,muldefs` links,
  and a real duplicate fails (S8); objects without -g have no .debug
  sections, with -g six (S11).
- S9, round 1's repro (lib.cpp with two static destructors, lib3.c
  with atexit, main.c with dlopen, dlclose, exit): plain zig, exit 139;
  rzig, both destructors run at dlclose and exit 0, both zigs. With gcc
  13's crtbeginS.o named by the link, and with `-nostartfiles` plus
  crtbeginS.o and crtendS.o (no object from rzig): exit 0. 24 parallel
  links into an empty cache: all exit 0, no message, the directory
  holds dso_fini.c and dso_fini.o only.
- S9 in R: a copy of the stress worktree's dist tree (R 4.6.1, round
  1's rzig), and the same copy with this rzig in bin/toolchain. A C++
  package with static objects and `.onUnload` calling
  `library.dynam.unload` (as lme4 does), `R CMD INSTALL --preclean`,
  then `library(); f(); unloadNamespace()`: round 1's rzig, "caught
  segfault", exit 139; this rzig, exit 0.
- S5: see above (rzig's command lines run with aarch64 targets; no
  aarch64 host or qemu here).
- S10: see above.

Tests on the hosts: "Tested on the hosts", at the end.

### Not tested yet (rzig)

- Done since: Windows (S1, S2, S7, S8, S10, R1), macOS (S1, S2, S3, S5,
  S6 for plain archives, S8, S10, S11) and the unload step on linux
  (S9), in "Tested on the hosts". R1's zig-ranlib.exe item does not
  apply: bin/toolchain on Windows has binutils' ar.exe and ranlib.exe.
- S6 with V8 on macOS: fails until "Review", 2.
- linux-aarch64: S5 natively. osx-64.
- Upstream zig on macOS and Windows.
- The stress suite's round 2 on all three, with the expectations below.

## Windows tree and recipe (implementer B)

**Status (2026-10-08).** Implemented on branch fix-stress-round1 (main
7a3004d), not committed. Checked on linux by its implementer (see
"Tested, tree and recipe"), then on kappa ("Tested on the hosts", at
the end). The user's answer of 2026-10-08,
"Everything sounds exactly right", takes every recommended option of
the stress suite's "Decisions for the user"
(feat-stress-suite stress/results/2026-10-08.md). This part covers
S13 (T1), S14 (T2), S15 (T3) and S19 (U4), and the recipe's build number.

Files: build.zig, zigbuild/config/win-x86_64-full/Makeconf.win,
scripts/verify-tree.sh, recipe/recipe.yaml.

### S13 (T1): R_ARCH = /x64 and COMPILED_BY

etc/x64/Makeconf had `R_ARCH =` and `COMPILED_BY =` empty. CRAN's R has
`R_ARCH = /x64`; gnuwin32's fixed/Makefile writes both with a sed.

- Makeconf.win: the two lines are `R_ARCH = @R_ARCH@` and
  `COMPILED_BY = @COMPILED_BY@`. installWindowsCompilerContract fills
  them in with the other values fixed/Makefile writes (BINPREF, FLIBS,
  FC, LDFLAGS: the `mk` map). Round 1's diff used a replaceLine; the
  placeholder is the same mechanism as BINPREF's, and the template
  keeps its line count.
- R_ARCH is `/x64`.
- COMPILED_BY is `clang-<version>` of the zig that builds R, read from
  `zig cc --version` at configure time (build.zig compiledBy):
  clang-21.1.8 with conda-forge's zig 0.16.0, clang-21.1.0 with
  upstream's (PyPI ziglang 0.16.0). Why:
  - R's convention is `$(CCBASE)-<version>` (MkRules.rules), and zig
    cc is clang. With gnuwin32's USE_LLVM, CCBASE is clang too.
  - It is the compiler and version R itself reports in R_COMPILED_BY
    ("clang 21.1.8", system.c, from the same __clang_*__ macros).
    Packages' winlibs.R read R_COMPILED_BY to pick the r-windows
    bundles built with clang against libc++, zig's C++ runtime (curl,
    magick and V8 loaded and passed in round 1).
  - Packages use COMPILED_BY as `lib$(subst gcc,,$(COMPILED_BY))$(R_ARCH)`
    (curl, openssl, gert, sf, xml2, magick, protolite, arrow), then a
    plain `-L$(RWINLIB)/lib`. With clang-21.1.8 the first names
    `libclang-21.1.8/x64`, which no bundle has; zig only warns about a
    missing -L directory, and the bundle's lib is used. CRAN's
    gcc-<version> works the same way.
  - Not `zig-0.16.0`: no package looks for "zig", and the code is
    clang's. Not a fixed string: the version follows the zig.

Where R_ARCH is used, checked against R 4.6.1's sources and the tree:
- share/make/winshlib.mk: `$(R_HOME)/bin$(R_ARCH)/Rterm.exe` (the
  symbols.rds step; igraph, duckdb) is now bin/x64/Rterm.exe, which
  exists.
- Makeconf.win: `LOCAL_LIBS = -L"$(LOCAL_SOFT)/lib$(R_ARCH)" ...`, only
  when LOCAL_SOFT is set (it is empty). IMPDIR stays the literal
  `bin/x64` (CRAN's is `bin$(R_ARCH)` expanded by fixed/Makefile, the
  same text). LIBR, BLAS_LIBS and LAPACK_LIBS use IMPDIR.
- Packages: `-L.../lib$(R_ARCH)$(CRT)` (arrow: lib/x64-ucrt),
  `${R_HOME}/bin${R_ARCH_BIN}/Rscript.exe` (R_ARCH_BIN is set by
  install.R from the R_ARCH environment variable, /x64; unset, it is now
  bin/Rscript.exe, which exists, S14), `-I.../include-config${R_ARCH}`
  (magick: a directory its current bundle does not have, as on CRAN;
  the next -I is used).
- R's own code reads the R_ARCH environment variable, not Makeconf:
  install.R (etc$(R_ARCH)/Makeconf, makevars_user's /x64 test), and
  rcmdfn.c and main.c set it to /x64 (both compiled with
  -DR_ARCH="x64"). etc/Rcmd_environ's own `R_ARCH=` line comes from R;
  rcmdfn.c reads that file first and sets R_ARCH=/x64 after it, as on
  CRAN.
- The tree: patch 0010's config script reads etc${R_ARCH}/Makeconf
  (the environment variable). verify-tree.sh, verify-bundle.sh and
  contract-test.sh do not read Makeconf's R_ARCH (verify-tree now
  checks it, below).

### S14 (T2): R_HOME/bin/R.exe and R_HOME/bin/Rscript.exe

CRAN builds one program, Rfe.exe, and copies it to bin/R.exe and
bin/Rscript.exe (src/gnuwin32/front-ends/Makefile, only when R_ARCH is
set): `Rfe.exe: Rfe.o ../rhome.o ../shext.o rcico.o rcmdfn.o
Renviron.o`, `Rfe-LIBS = -lole32 -luuid`. Rfe.c runs
`<R_HOME>\bin\x64\Rscript.exe` when its own name ends in Rscript.exe or
Rscript, else `<R_HOME>\bin\x64\R.exe`, with its arguments, through
system(); R_ARCH or `--arch` pick another arch directory. It finds
R_HOME two levels above itself (getRHOME(2)).

- build.zig winRfe builds it with zig as the other front ends (newCMod,
  addCGroup): Rfe.c and rcmdfn.c with R.exe's flags (-DBINDIR="bin/x64"
  -DR_ARCH="x64"), rhome.c and shext.c, Renviron.c with
  -DRENVIRON_WIN32_STANDALONE. It links no R.dll: R.dll is in bin/x64,
  and the loader does not look there for a program in bin. So rhome.c
  and shext.c are compiled in, as gnuwin32 does, and the Windows
  libraries are named: advapi32, shell32, user32, ole32, uuid. No icon
  resource (as R.exe, Rcmd.exe and Rterm.exe here).
- buildWindows installs it as R_HOME/bin/R.exe and R_HOME/bin/Rscript.exe.
- Not built: CRAN's bin/x64/Rfe.exe (nothing runs it).
- conda: both files are in r-zig-slim (not under bin/toolchain).
  Library/bin/R.bat and Rscript.bat still start bin\x64's programs.

Callers: Rmpfr's configure (`${R_HOME}/bin/R CMD config CC`), rstan's
Makevars.win (`${R_HOME}/bin/Rscript` for STANHEADERS_SRC and
RcppParallel::CxxFlags()), s2's bundled-abseil path.

### S15 (T3): CMake on Windows

Three parts, as round 1 tested them on kappa (RcppParallel's TBB,
Rhdf5lib through biocmake; cmake 4.4.4 from conda-forge).

1. Makeconf.win names the compilers by their files, `.exe` included:
   CC, CC17, CC23, CC90 and CC99 are `$(BINPREF)$(CCBASE).exe`; CXX and
   CXX17 `$(BINPREF)$(if $(USE_LLVM),clang++,g++).exe` (CXX20, CXX23 and
   CXX26 are $(CXX17); OBJC, DLL, SHLIB_LD and SHLIB_CXXLD follow CC and
   CXX). CMake 4.4 stops with "is not a full path to an existing
   compiler tool" on `R CMD config CC` without .exe. BINPREF stays
   `$(R_HOME)/bin/toolchain/`, and the other tools (ar, nm, windres,
   dlltool, strip, objdump, ranlib, pkg-config) keep their names. One
   `## r-zig:` comment line in the template says why. contract-test.sh
   already accepts gcc or gcc.exe.
   FC stays `$(R_HOME)/bin/toolchain/zig-fc` (no .exe): CMake with
   Fortran was not part of round 1. If a CMake Fortran package shows
   up, the same rule applies to FC.
2. etc/Rcmd_environ: R's file, then these lines (build.zig rcmdEnviron;
   CRLF like R's file):

       ## r-zig: CMake for packages that build a bundled library with it.
       CMAKE_GENERATOR=${CMAKE_GENERATOR-'MSYS Makefiles'}
       R_ZIG_RC=${R_HOME}/bin/toolchain/windres.exe
       RC=${RC-${R_ZIG_RC}}
       R_ZIG_RCFLAGS=--preprocessor=${R_HOME}/bin/toolchain/gcc.exe --preprocessor-arg=-E --preprocessor-arg=-xc --preprocessor-arg=-DRC_INVOKED
       RCFLAGS=${RCFLAGS-${R_ZIG_RCFLAGS}}

   - Why Rcmd_environ: R CMD (rcmdfn.c) reads it before every
     subcommand, so the values are in package builds (R CMD INSTALL,
     install.packages(), pak, pkgbuild) and nowhere else. R's
     `${VAR-default}` syntax: a value set in the environment wins,
     an empty one included. Renviron expands a nested default only as
     a whole `${...}` term, hence the R_ZIG_ helpers, as etc/Renviron's
     TCL_LIBRARY.
   - CMAKE_GENERATOR: with no -G, conda-forge's cmake picks NMake
     Makefiles ("make: invalid option -- ?"). MSYS Makefiles are
     makefiles for make with sh as the shell, which is how R runs
     packages' makefiles: in a conda env, m2-make (conda's and pixi's
     activation put Library/usr/bin before Library/bin on PATH, so it is
     the `make` CMake and R find) and m2-bash's sh, both run
     dependencies of r-zig-toolchain. Round
     1's Rhdf5lib built with it on kappa ("Building for: MSYS
     Makefiles"; the stress env had m2-make and conda-forge's make, and
     the log does not say which one CMake used). A package that passes
     its own -G (s2's build_absl.sh: "Unix Makefiles") is not changed.
   - RC and RCFLAGS: CMake compiles a .rc file (TBB's) with RC, else a
     windres on PATH, where there is none. The tree's windres is in
     bin/toolchain. windres preprocesses with a gcc it looks for by
     name; `--preprocessor` names the toolchain's gcc.exe (rzig), and
     then windres drops its default arguments, so they are given back
     with `--preprocessor-arg` (`-E -xc -DRC_INVOKED`, windres's
     default). These are round 1's values.
   - R_HOME there is rcmdfn.c's, with forward slashes, and its 8.3 form
     when the path has a space (getRHOME), so RCFLAGS splits right.
3. Later: feat-standalone-toolchain's phase 3 (B24) moves windres into
   bin/toolchain/binutils/ or to an rzig name, and phase 3/7 (B25) adds
   a PATH line to Rcmd_environ. R_ZIG_RC moves with windres then.

### S19 (U4): libdeflate <1.26 in the recipe's host

r-zig-slim's builds 2 to 6 (universe) for linux and macOS were built
against libdeflate 1.26, so they ask `>=1.26,<1.27.0a0`, while every
conda-forge libgdal-core asks `<1.26.0a0` (round 1's harness solve log).
No conda env could hold r-zig-slim with sf, terra, lwgeom or
gdalraster. win-64's builds 2 to 6 ask `>=1.25,<1.26.0a0` already (the
channel's repodata, 2026-10-08).

- recipe.yaml host: `libdeflate <1.26` (all subdirs; 1.25 exists for all
  five). libdeflate's run export then gives r-zig-slim
  `>=1.25,<1.26.0a0`, the same bound libgdal-core carries. The run list
  keeps its unpinned `libdeflate`.
- How it is lifted: when conda-forge's libgdal-core is built against
  libdeflate 1.26 (its libdeflate migration; then its depends say
  `>=1.26,<1.27.0a0`), remove the pin in the same PR as a build-number
  bump. Kept past that point, the pin causes the same conflict the
  other way.
- pixi.toml is not changed: the lock holds 1.25, and the standalone tree
  vendors its own libdeflate.

### Build number 6 → 7

recipe.yaml `number: 7`, with a history line: rzig's zig 0.16
workarounds (S1-S11, implementer A), the Windows tree (S13-S15), the
libdeflate pin (S19). Every one changes r-zig-slim's or
r-zig-toolchain's files or dependencies, so B14 (a)'s rule ("each later
PR that changes a conda package's files or dependencies bumps again")
applies.

E2 (zstd declared) and D7 (CC_VER/FC_VER refreshed) are not in this
bump. The records tie both to phase 4's bump, not to the next one:
feat-standalone-toolchain PLAN.md says "D7 = (a): CC_VER/FC_VER are
refreshed with the first B14 bump, phase 4's", "E2 = (a): zstd is
declared in the recipe with the first bump, phase 4's", and B14's
answer "D7 (CC_VER/FC_VER) and E2 (zstd declared) ride with phase 4's
bump"; feat-no-host-paths PLAN.md and chore-lock-and-ci-refresh PLAN.md
say the same. Phase 4 has not landed (r-zig-toolchain still exists;
r-zig-compilers and r-zig-build-tools do not). Note for phase 4: its
text says "5 → 6"; #19 took 6 and this branch takes 7, so phase 4's
bump is the next number after whatever is published then.

### verify-tree.sh

New Windows check, for every Windows tree (the conda env too, since
build.zig installs both there): Makeconf's `R_ARCH = /x64` (CRLF
allowed, as the other Makeconf checks), and R_HOME/bin/R.exe and
R_HOME/bin/Rscript.exe are PE files (they start with MZ). The header
list names it. The baseline CPU check and, outside a conda env, the DLL
closure check already take in the two files (they import only system
DLLs).

### Tested, tree and recipe (linux-64, gamma)

- `zig fmt --check build.zig`: clean.
- `zig build --help` on a scratch copy of build.zig and zigbuild/ (the
  checkout's build/R-4.6.1 linked in), with conda-forge's zig 0.16.0
  and with upstream's (PyPI ziglang 0.16.0): builds. buildWindows,
  winRfe, rcmdEnviron and compiledBy are analysed on linux: a type
  error put into each one fails the build.
- compiledBy, run through build() by a probe: `clang-21.1.8`
  (conda-forge's zig), `clang-21.1.0` (upstream's).
- Rfe cross-compiled with conda-forge's zig, `zig cc -target
  x86_64-windows-gnu -mcpu=baseline` and addCGroup's flags (-std=gnu23
  -O2 -DHAVE_CONFIG_H, the win-x86_64-full config.h, R 4.6.1's sources):
  compiles and links with no warning. llvm-objdump -p: it imports
  ADVAPI32, KERNEL32, ole32, SHELL32, USER32 and the UCRT API sets only
  (no R.dll); no VEX instruction, no %ymm.
- rcmdEnviron's output, written by build.zig through a probe, read by R's
  own Renviron.c (compiled on linux with RENVIRON_WIN32_STANDALONE):
  with R_HOME=C:/R/lib/R, CMAKE_GENERATOR=MSYS Makefiles,
  RC=C:/R/lib/R/bin/toolchain/windres.exe and RCFLAGS as above; with
  RC, CMAKE_GENERATOR and an empty RCFLAGS in the environment, those
  win.
- verify-tree.sh: `bash -n`. The new block, run alone on a fake tree:
  passes with a CRLF Makeconf and Rfe.exe copies; fails on an empty
  R_ARCH, on `/x64/foo`, on missing files and on a script named R.exe.
- recipe.yaml parses (python yaml). `rattler-build build --render-only
  --with-solve` (0.70.0, linux-64, conda-forge and universe): renders
  r-zig-slim and r-zig-toolchain at build 7. The render does not show
  the staging output's host solve, so the libdeflate bound is not seen
  there; libdeflate 1.25's run export (`>=1.25,<1.26.0a0`) is what
  libgdal-core carries in round 1's solve log.

### Not tested yet (tree and recipe)

- Done since, on kappa ("Tested on the hosts"): build, verify-tree,
  smoke, contract (but for its S10 check), verify-package, R.exe and
  Rscript.exe, R CMD config, Rcmd_environ's values, the stress rows
  Rmpfr, RcppParallel, StanHeaders, duckdb, igraph, Rhdf5lib and rstan,
  and conda-package for win-64 (build 7, its tests pass).
- arrow on Windows (lib/x64-ucrt, T1; then A2).
- conda-package on linux or macOS, where builds 2 to 6 had the
  libdeflate conflict. win-64 never had it, so kappa's solve with
  libgdal-core does not exercise the pin; a scratch solve of the
  recipe's host list does ("Review").
- Upstream zig on Windows for Rfe (no DLL is involved, so the atexit
  workaround of addSharedLib does not apply).

## Tested on the hosts (testers, 2026-10-08)

The worktree after both implementers: main 7a3004d plus the uncommitted
changes, pixi.lock 7aef60ff...a355a63, unchanged on every host.
conda-forge's zig 0.16.0 everywhere. The stress runner (stress/stress.R)
and its `stress` env came from feat-stress-suite, read-only (its lock
a8d7319c...ab61ab8f97, unchanged), run against this branch's tree. The
stress report's header names the stress worktree's commit, not this
tree's. Logs: /data/gamma/luciorq/workspaces/temp/r-zig-pixi/round1fix/
(linux/, omicron/, kappa/).

linux-64 (gamma):
- rzig-test (68 of 68; parity 0 failed), build (2.9 min), verify-tree,
  smoke, verify-package, `-e minimal` build and verify-package: pass.
  rzig's smoke-test.sh with the tree and RZIG_SMOKE_CRAN=1, parts 1 and
  2: pass.
- contract: fails only at its order-of-L check, which still expects
  S10's old order ("Review", 1). With the check rewritten: pass.
- Stress, -j6, 29 min: 11 of 11 targets and 67 dependencies ok, every
  one unloaded and R exited 0. Round 1's failures now ok: RcppParallel,
  RcppParallel:system-tbb, Rhdf5lib, arrow:source, duckdb (S1 to S4,
  S10); lme4, rstan (a Stan model compiled and sampled) and fstcore (S9).
  Also ok: qs2, StanHeaders, fst, mlpack.
- Controls: fstcore and lme4 built with round 1's rzig still exit 139
  after unloadNamespace, under either R; built with this rzig, 0. A
  CMake link (`-Xlinker --dependency-file`) with plain `zig cc` panics;
  through rzig it links and runs.
- RcppParallel binds its bundled libtbb.so, `$ORIGIN/../lib` first in
  RUNPATH; the system-tbb row binds the env's libtbb.so.12 (S2, S10).
- S11: mlpack.so 33.1 MB (round 1: 304), duckdb.so 64.5 (426),
  arrow.so 57.9 (402). What DWARF is left is zig's own libc++,
  libc++abi and libunwind: 4.2 to 6.1 MB per C++ package ("Review").
- S9's cache after about 80 package builds at -j6 and -j4: one
  dso-fini-<key>/ holding dso_fini.c and dso_fini.o; no rzig warning in
  any log. Every C++ package .so checked has a .fini_array.

osx-arm64 (omicron):
- rzig-test (68 of 68; parity runs on linux only), build (1.9 min),
  verify-tree, smoke, verify-package: pass. contract: as on linux.
- Probes through the tree's compilers: S1 (a caller's own
  -Werror=date-time still stops the compile), S2 (three spellings), S3,
  S5 (armv8-a, +crc with a __crc32b call, armv8.2-a+fp16+dotprod, C++
  +simd; a CMake project with -march=armv8-a finds Threads and accepts
  +crc), S6 (a plain archive; the copy is byte-identical), S8, S10's
  order, S11: pass.
- Stress, -j6, 28.8 min: 10 of 11 targets and 64 dependencies ok, every
  one unloaded and R exited 0. Now ok without round 1's workarounds:
  arrow (default SIMD, S3 support on), arrow:source, duckdb,
  RcppParallel, RcppParallel:system-tbb. Also ok: qs2, StanHeaders,
  rstan, lme4, fst.
- V8: "../.deps/v8_monolith: unrecognized file extension" (a universal
  file, "Review", 2). With that fix in a copy of the tree, V8 installs,
  evaluates `1 + 1` and unloads.
- Nothing of the run left on omicron but pixi's shared package cache;
  no Falcon detection in any log.

win-64 (kappa):
- rzig-test (50 passed, 18 skipped: the tests that need linux or macOS
  stand-ins), build (7.5 min), verify-tree (its new check: R_ARCH =
  /x64, bin/R.exe and bin/Rscript.exe are PE files), smoke,
  verify-package: pass. contract: order-of-L only; the rewritten check
  passes on the line it printed (judged by hand).
- `-e pkg conda-package`: r-zig-slim-4.6.1-h9490d1a_7 and
  r-zig-toolchain-4.6.1-h5e29ac5_7, all tests pass; r-zig-slim depends
  on `libdeflate >=1.25,<1.26.0a0`. A scratch solve with libgdal-core
  3.13.3 works.
- By hand: bin/R.exe --version; R CMD config CC (gcc.exe), CXX (g++.exe
  -std=gnu++20), CXX17 (g++.exe), FC (zig-fc, no .exe); bin/Rscript.exe
  -e 1. Inside R CMD: R_ARCH=/x64, CMAKE_GENERATOR=MSYS Makefiles, RC
  and RCFLAGS as designed. g++.exe and gcc.exe by their 8.3 paths say
  clang 21.1.8 (R1); `gcc.exe -c f.c` writes f.o (S7).
- Stress, -j4, 38.6 min: Rmpfr (T2), RcppParallel (T3, S2, S10: it and
  rstan import the bundled tbb.dll, whose .rsrc shows windres ran
  through RC), StanHeaders (S8) and duckdb (S1, T1; 14.6 min) ok, and
  QuickJSR (S7) among 51 dependencies ok. All 11 C++ install logs say
  `using C++ compiler: 'clang version 21.1.8'` (R1).
- Package or sysdep failures, not this branch's: igraph (no glpk.pc in
  conda's win-64 glpk; with a hand-written one it installs and writes
  libs/x64/symbols.rds, T1); Rhdf5lib (T3 works, then P4's FLT16_MAX;
  ok with -D__STDC_WANT_IEC_60559_TYPES_EXT__); rstan's smoke step
  (rstan 2.32.7's plugin.R adds -std=c++1y on Windows after Makeconf's
  -std=gnu++17, and StanHeaders 2.39.1 needs C++17; ok with
  CXX17FLAGS += -std=gnu++17).
- Nothing of the run left on kappa but rattler's shared package cache.

Not run on any host: upstream zig (linux only, by implementer A),
linux-aarch64, osx-64, the default arrow row on linux and Windows, a
`--conda` stress run against build 7.

For round 2's packages.tsv (the stress branch): linux, the seven rows
marked (!) are ok; macOS, RcppParallel, RcppParallel:system-tbb, arrow,
arrow:source and duckdb ok, V8 fail-toolchain until "Review", 2;
Windows, Rmpfr, RcppParallel, StanHeaders and duckdb ok, Rhdf5lib and
rstan fail-package, igraph stays fail-sysdep.

## Review (2026-10-08)

Open code items, for the user. Each diff is in
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/round1fix/review/diffs/
and passes `git apply --check` on this worktree.

1. contract-test.sh still checks the environments' -L before -o, so
   `pixi run contract` fails on every OS (contract-test-s10.diff). The
   diff checks `o < lo < le` and updates the comment and the message.
   It passed on omicron and matches the lines gamma and kappa printed.
   (gamma's variant anchors on `-lz` instead; that works too, but an -l
   is what windows.libs may rewrite to a path.)
2. S6 and universal files (archives-fat.diff). V8's autobrew bundle is
   a macOS universal file holding two ar archives (magic cafebabe), not
   an ar archive. The diff also takes a fat file whose first slice is an
   archive; a Java class file has the same magic and stays out (a test
   for each). Unit tests 68 of 68 on gamma and omicron; V8 installs with
   it on omicron. S6's text above changes with it.
3. The cache root on Windows (cache-root-windows.diff; low). R CMD and
   Rterm set HOME to R_USER, by default the Documents folder, when it is
   unset (rcmdfn.c, system.c), so under R the %LOCALAPPDATA% branch
   never runs and S6's copies would go to Documents/.cache/r-zig. The diff
   puts %LOCALAPPDATA% before HOME on a Windows host, where zig keeps
   its own cache. Only S6 uses the cache on Windows. Unit tests 68 of 68
   on gamma; they also compile for x86_64-windows-gnu.
4. S5's names (s5-names.diff; low). clang (LLVM 23's driver, checked
   through flang) also takes fcma, jscvt, pmuv3 and predres2, which zig
   names complxnum, jsconv, perfmon and specres2; zig refuses the clang
   names. The diff maps them in rzig and both shims, with a unit test
   and a parity case. Unit tests 68 of 68, parity 0 failed (69
   identical); zig compiles with the mapped names for aarch64.

Found, not decided:
- Z10's residual: zig's own libc++, libc++abi and libunwind keep their
  DWARF in every linux C++ package (4.2 to 6.1 MB; in fst.so 4.2 of
  5.35 MB). A linker strip on linux links without -g
  (`-Wl,--strip-debug`) would remove it: a new rule. On macOS the .so
  keeps OSO stabs into zig's cache for those members, not the DWARF.
- S6's copies are never evicted (V8's: 161 MB, one per distinct file).
- recipe/test-toolchain.R leaves zig's cache (about 64 MB in
  %LOCALAPPDATA%\zig on win-64) and R temp dirs; contract leaves one R
  temp dir on Windows. kappa's untested test-toolchain-zigcache.diff
  gives the test its own ZIG_GLOBAL_CACHE_DIR.
- rzig's last fallback, `python3 -m ziglang`, reaches the Microsoft
  Store alias on Windows when zig is not on PATH ("Python was not
  found", exit 49); rzig says nothing about where it looked.
- S10 also puts a package's own -L into a system directory
  (/usr/local/lib, /opt/homebrew/lib) before the environment's, as
  stock R does; nothing in the stress runs hit it.
- Not covered by S2 and S8: an option split over two -Wl, arguments
  (`-Wl,-z -Wl,muldefs`, `-Wl,-L -Wl,dir`). None seen.
- Not rzig's: on macOS qs2 and stringfish link the stress env's oneTBB
  (their own pkg-config `-L<env>/lib` comes before RcppParallelLibs()'s
  -L), so two TBB runtimes load in one process; the default arrow row
  links Homebrew's /opt/homebrew/lib/libsnappy.a; RcppParallel's bundled
  libtbbmalloc_proxy.so.2 keeps CMake's build-tree RUNPATH, with an
  empty element.

Checked in review:
- `pixi run --locked rzig-test`: 68 of 68; parity 68 identical, 45
  ok+, 21 deliberate, 0 failed. pixi.lock unchanged.
- S9, real links through an rzig built from this tree: a C++ library
  with a static destructor unloads and the program exits 0 with
  --gc-sections, -z defs, a version script with `local: *`,
  --no-undefined with -Bsymbolic, and --as-needed; .fini_array is kept
  and __dso_handle is local. The same library from plain zig: exit 139.
  The object also compiles for aarch64-linux-gnu.2.17.
- S5 with `-###`: on aarch64-macos zig passes apple-m1 and its
  features, then `-target-cpu generic` with a full feature list that
  turns them off (-aes and the rest) and +crc. So the package's
  architecture wins, as S5 says.
- With conda-forge's zig a fresh cache's libc++ build prints about
  37,000 lines of -Wnullability-completeness warnings, with or without
  rzig's flags: not this branch's.
- S19: a scratch solve of the recipe's unix host list with `libdeflate
  <1.26`, plus libgdal-core, picks libdeflate 1.25 and libgdal-core
  3.13.3 on linux-64, linux-aarch64, osx-64 and osx-arm64; without the
  pin, 1.26 (conda-forge).
- Rcmd_environ: in R 4.6.1's Renviron.c a set variable wins over
  `${VAR-default}`, an empty one included (`${VAR:-default}` needs it
  non-empty), as the comment says.
- kappa's rstan finding: rstan 2.32.7's R/plugin.R line 63 adds
  ' -std=c++1y' on Windows.
- Comments fixed: recipe.yaml's libdeflate note (builds 2 to 6 on linux
  and macOS, not build 4), and this file.

## After the review (2026-10-08)

The review's four diffs are applied:
- contract-test.sh's order-of-L check now expects the order S10 makes
  (the caller's -L, then the environments'); without it `pixi run
  contract` failed on every OS.
- S6 also takes a universal (fat) file whose first slice is an ar
  archive: V8's macOS bundle is one (omicron installed V8 with it).
- rzig's cache on Windows: %LOCALAPPDATA% before HOME, since R sets HOME
  to the Documents folder (only S6 uses the cache there).
- S5 maps four more clang extension names (fcma, jscvt, pmuv3,
  predres2), in rzig and both shims.

Re-run on linux-64 after them, lock 7aef60ff unchanged: rzig-test
(parity 69 identical, 45 ok+, 21 deliberate, 0 failed), build,
verify-tree, contract (passes). Not re-run on the hosts: the fat-file
diff is omicron's own tested change; the Windows cache-root branch is
type-checked only.


## Round 2's answers, rzig (implementer A, 2026-10-09)

The user's answer to round 2's decisions (feat-stress-suite
stress/results/2026-10-08-round2.md, "Decisions for the user" 1 to 9
and 10), 2026-10-09: "Continue with all recommended option." Here: R2-1
(Z11, into this branch) and R2-3 (Z10's residual). R2-10's section,
implementer B's report, follows ("Round 2's answer, the tree"); R2-4 is
in "Tested on the hosts (testers, 2026-10-09)".

Files: zigbuild/tools/rzig/cfguard.zig (new), cache.zig, dso_fini.zig,
compiler.zig, fortran.zig (tests), Ctx.zig, main.zig, parity-test.sh;
toolchain/zig-cc and zig-cxx.

The command line now:

    zig cc|c++ -fno-sanitize=undefined -mcpu=baseline -Wno-error=date-time
        [-g0] [<target>] [-F<SDK frameworks>] [<soname>]
        [-Wl,--undefined-version] [-Wl,--strip-debug]
        [<dso_fini.o> | <guard_dispatch.o>] <caller's, rewritten>
        [<environments' -L and rpath>] <environments' headers> [-lomp]
        [-L<SDK>/usr/lib]

### R2-1 (Z11): the CFG stub on Windows links

kappa's diff (round2/kappa/diffs/rzig-z11-cfguard.diff) is applied as
it was (`git apply`, no conflict), with one change, below. cfguard.zig
holds mingw-w64-crt's guard_dispatch.S: `__guard_dispatch_icall_dummy`,
a `jmp *%rax`, the target of `__guard_dispatch_icall_fptr`. rzig
assembles it once, with the zig that links, into its cache:
`cfguard-<key>/guard_dispatch.o`, with guard_dispatch.S beside it. It
goes through `cache.compiled`, which dso_fini.zig now uses too.
compiler.zig passes it on every Windows command with `-o` as a word and
no compile-only flag, where S9 puts its object: after the SONAME,
before the caller's arguments. `--version`, windres's `-E` and `-c` get
nothing.

The change: the stub carries a `.drectve` directive,
`-exclude-symbols:__guard_dispatch_icall_dummy`. clang writes the same
for a hidden symbol on MinGW. Without it, lld's MinGW auto-export (a DLL
with no .def file and no dllexport exports every global symbol) exports
the stub. Measured: such a DLL's export table gained
`__guard_dispatch_icall_dummy`. With the directive, the table is the
same as without the stub. R's package DLLs export through tmp.def and
never had it; a CMake or libtool DLL without exports would have.

Plain object or archive member. Measured with both zigs
(x86_64-windows-gnu cross-links on gamma):
- plain object: CFG code links; other links carry 16 bytes of .text; a
  link that defines the symbol in an object of its own (as kappa's
  `PKG_LIBS += guard_dispatch.o` experiment did) stops at "duplicate
  symbol".
- archive member (`zig ar rcs` of the same object): CFG code links;
  other links are unchanged; a link with its own definition links.

The archive is more robust in those two cases, but not simpler: it
takes a second tool (zig ar) and a second step in the cache. The brief
was to take it only if it was both. So the plain object stays. No
package is known to define the symbol itself; should one appear, the
archive is the change to make.

Unit tests (kappa's): cfguard.zig's `wanted` and "made once into the
cache, from guard_dispatch.S"; compiler.zig's "Windows links: the CFG
stub before the caller's arguments; nothing elsewhere". parity-test.sh
takes the stub out of rzig's side as it does S9's object, after checking
that it is there exactly when the rule says. The ten Windows link cases
now report ok+.

Checked on gamma:
- Through rzig (`RZIG_PRINT_ARGV=1 RZIG_OS=windows`, which compiles the
  stub with the real zig), with conda-forge's and upstream's zig 0.16.0:
  the cache holds `cfguard-<key>/guard_dispatch.S` and `.o`, and the
  `.o` has the directive. `zig cc -target x86_64-windows-gnu -shared
  -mguard=cf <stub> lib.c` (kappa's repro) links; without the stub,
  "undefined symbol: __guard_dispatch_icall_dummy". The DLL exports
  `call` alone. A DLL without dllexport exports what it exports without
  the stub. Compiles and `--version` print no stub.
- rzig cross-compiles for x86_64-windows-gnu; its unit tests compile.

Done since, on kappa ("Tested on the hosts (testers, 2026-10-09)"):
R2-1 (a)'s end-to-end check (magick installs through the tree, loads,
passes its smoke call and an SVG read through the bundle's CFG-built
librsvg, unloads; with both zigs, and through the conda build), and
rzig-test (52 passed, 20 skipped).

For the testers and implementer B: on Windows, the dry runs of a link
(contract-test.sh, verify-bundle.sh, recipe/test-toolchain.R) now
compile the stub into rzig's cache as a side effect
(%LOCALAPPDATA%/r-zig/cfguard-<key>/), as linux's dry runs compile S9's
object, and print its path among the arguments. None of their checks
looks at it.

### R2-3 (Z10's residual): -Wl,--strip-debug on linux links

Rule: a linux command with no -g option and no compile-only flag gets
`-Wl,--strip-debug`. The -g test is S11's (an argument that starts with
-g; -g0 counts). Executables and shared libraries alike. The flag goes
after the SONAME and S4's flag, before S9's object and the caller's
arguments. macOS and Windows get nothing. A -g on the link line keeps
the debug info.

What zig makes of it. zig cc reads `-Wl,--strip-debug` (and `-Wl,-S`)
as its own strip option, the same as `-s`, with both zigs:
- It links a libc++, libc++abi and libunwind it built without debug
  info, a second build in zig's cache (libc++.a 2.4 MB, against 14 MB
  with DWARF). A build without any -g needs only that one, so a fresh
  cache still builds libc++ once.
- The link is a full strip: .symtab goes with the .debug_* sections.
  .dynsym stays, so loading, dlsym, R's routines, .eh_frame (exceptions)
  and S9's .fini_array are as before.

That is what `R CMD INSTALL --strip` does on linux (`STRIP_SHARED_LIB =
strip --strip-unneeded`: no .symtab either). It is not binutils'
--strip-debug, which keeps .symtab (the small library below: 345 KB
with `strip --strip-debug`, 245 KB through zig).

Consequences, for the user:
- R CMD check's compiled-code check sees no symbols in a package built
  this way. tools:::check_compiled_code runs `nm -Pg` on the installed
  .so; nm prints "no symbols" and the check reports nothing. With S11
  alone, Rcpp's check reported `abort` and `stderr`. zig's static
  libc++abi references both (abort_message.o), so every C++ package
  showed them. The check had a false positive in every C++ package
  before; now it is blind.
- Debug info from compile lines with -g goes too when the link line has
  no -g. R CMD SHLIB's link line carries LDFLAGS, not CFLAGS. A user who
  sets `CFLAGS = -g -O2` in ~/.R/Makevars to debug a package must add
  -g to LDFLAGS too.
- The same for devtools::load_all(): pkgbuild 1.4.8's
  compile_dll(debug = TRUE) puts `-g -O0` in CFLAGS, CXXFLAGS and FFLAGS
  and nothing in LDFLAGS, so its .so has no debug info (measured on
  linux, "Tested on the hosts (testers, 2026-10-09)").
- Backtraces (gdb, perf) through a package's internal functions show
  addresses, not names.

If keeping .symtab matters (the check above), the alternative is a
strip after the link (`zig objcopy --strip-debug` on the output): a
second step on every linux link. Not done. zig 0.16.0 cannot do it:
`zig objcopy` stops at "error: unimplemented" on an ELF shared library
with --strip-debug, -g, -S or --strip-all, with both zigs (review,
2026-10-09). It would take binutils' or LLVM's objcopy, which the tree
does not ship.

Shims: zig-cc and zig-cxx do the same, after S4's block, with the -g0
test they already had. parity-test.sh: every linux link case now
carries the flag on both sides. Two new cases: a shared link with -g,
and an executable with -gline-tables-only (no -g0, no flag). Mutations
on a scratch copy: a zig-cc that does not strip fails every linux
zig-cc link case; an rzig that strips despite a -g fails the two new
cases.

Unit test: compiler.zig's "linux links without a -g option:
--strip-debug, after the SONAME and --undefined-version". It covers
shared and executable links, C and C++, the order after the SONAME and
S4's flag, seven -g options (the flag stays out), the compile-only
flags, --version, and macOS and Windows (none). The existing tests'
linux link lines now carry the flag.

Checked on gamma, both zigs (an rzig built by each, ZIG_BIN that zig):
- Commands that do not link, through plain zig cc, with and without the
  flag: --version, -v, -dumpversion, -dumpmachine, -print-file-name,
  -print-search-dirs, -print-prog-name, -fsyntax-only (with and without
  -Werror), a header to a .pch (with -Werror), -r. Same exit status and
  output each time.
- A small C++ library (std::string, an exception thrown and caught, a
  static destructor), through rzig:
  - no -g anywhere: 245,456 bytes (upstream 245,160), no .debug_*
    section, no .symtab. Through plain zig: 1,557,952 bytes, seven
    .debug_* sections;
  - -g on the compile and the link: 1,630,064 bytes, seven .debug_*
    sections, .symtab;
  - -g on the compile only: the same as no -g;
  - dlopen, the calls (the exception included), dlclose (the static
    destructor runs), exit 0.
- smoke-test.sh part 1 with both zigs, and part 2 with RZIG_SMOKE_CRAN=1
  (a copy of this branch's dist/R-4.6.1-slim-zig with the new rzig in
  bin/toolchain): pass. Objects, archive and program stay byte-identical
  to the shims' build.
- Rcpp 1.1.2, R CMD INSTALL with that tree before and after: Rcpp.so
  goes from 5,775,056 bytes (4,222,656 of .debug_*) to 1,162,176 (none).
  library(Rcpp), evalCpp("1 + 1"), Rcpp::stop() caught in R, a
  cppFunction that throws and catches, unloadNamespace: exit 0.

### Tested (implementer A, 2026-10-09)

pixi.lock 7aef60ff...a355a63, unchanged.
- `pixi run --locked rzig-test`: 72 of 72 unit tests (68 before: three
  from kappa's diff, one for R2-3); parity 59 identical, 57 ok+, 21
  deliberate, 0 failed (137 cases; 135 before). `zig fmt --check`
  clean.
- Upstream zig (PyPI ziglang 0.16.0): unit tests 72 of 72; parity with
  an rzig it built, the same counts.
- rzig and its unit tests cross-compiled (not run) for
  x86_64-windows-gnu, aarch64-macos, x86_64-macos and
  aarch64-linux-musl.

Not run here: kappa's end-to-end check (R2-1); R2-4's `--conda` run on
the three OSes and its upstream-zig check; rzig-test on macOS and
Windows. All run since on the hosts ("Tested on the hosts (testers,
2026-10-09)").

## Round 2's answer, the tree (implementer B, 2026-10-09)

### R2-10 (H2): CMake on macOS leaves out Homebrew

The user's answer of 2026-10-09 ("Continue with all recommended
option.") takes round 2's decision 10 into this branch. Round 2 had set
it aside for feat-standalone-toolchain. r-zig keeps CMake away from
Homebrew for users on macOS. Files: build.zig, scripts/verify-tree.sh.

- etc/r-zig.cmake, macOS only, in every tree (the conda build's too).
  r-zig-slim ships it, beside etc/Renviron. build.zig's
  macos_cmake_toolchain holds a short comment and
  `set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH /opt/homebrew /usr/local /opt/local /sw)`.
  installStaticTree stages it.
- etc/Renviron on macOS (finalRenviron):

      ## r-zig: CMake leaves out Homebrew's, Fink's and MacPorts' prefixes.
      R_ZIG_CMAKE_TOOLCHAIN_FILE=${R_HOME}/etc/r-zig.cmake
      CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE-${R_ZIG_CMAKE_TOOLCHAIN_FILE}}

  R reads this file at startup, and R CMD sources it and exports every
  name (Rcmd.in). So install.packages() and R CMD INSTALL both pass the
  variable to CMake. CMake 3.21 and later read CMAKE_TOOLCHAIN_FILE from
  the environment when the command line names none. The helper variable
  is there for the same reason as TCL_LIBRARY's.
- Why (H2): cmake 4.4.4's Platform/Darwin.cmake prepends the output of
  `brew --prefix` to CMAKE_SYSTEM_PREFIX_PATH. Without brew it prepends
  /opt/homebrew on arm64 or /usr/local on Intel. Both come before the
  env. It appends Fink's /sw and MacPorts' /opt/local last. All of this
  happens whatever PATH says. The list is those four prefixes, the ones
  Darwin.cmake adds for a package manager. Round 2's diff had only
  Homebrew's two; Fink and MacPorts follow the same rule.
- Which variable: CMAKE_SYSTEM_IGNORE_PREFIX_PATH (CMake 3.23 and later;
  older versions skip it). This is the variable meant for toolchain
  files, so CMAKE_IGNORE_PREFIX_PATH stays the project's. On the probe
  both act the same. The file uses set(), not list(APPEND): CMake reads a
  toolchain file twice per configure, and APPEND lists each prefix twice.
- What wins: a package's own -DCMAKE_TOOLCHAIN_FILE. Also a
  CMAKE_TOOLCHAIN_FILE already set in the environment, an empty one
  included. An empty one gives no toolchain file, which brings back stock
  CMake's search.
- The env's own libraries: the match is exact. CMake finds the env
  through the prefix of the cmake it runs (UnixPaths.cmake), PATH's
  <env>/bin and CMAKE_PREFIX_PATH. None of these is one of the four,
  unless the env is exactly one of them. A prefix below one of them is
  kept (miniforge's cask: /opt/homebrew/Caskroom/miniforge/base). The
  conda build's R_HOME is <env>/lib/R.
- Not linux: Platform/Linux.cmake goes through UnixPaths.cmake, which
  adds /usr/local, /usr, /, cmake's own prefix, the install prefix,
  /usr/X11R6, /usr/pkg and /opt. No package manager's prefix is among
  them. Linuxbrew is searched only when PATH (find_package CONFIG) or
  CMAKE_PREFIX_PATH names it. Under the same rule there is nothing to
  leave out, so linux gets no file and no line.
- Not Windows: WindowsPaths.cmake adds Program Files and cmake's own
  prefix. S15's Rcmd_environ already sets CMake's generator and windres
  there.
- verify-tree.sh (macOS, every tree): etc/r-zig.cmake sets
  CMAKE_SYSTEM_IGNORE_PREFIX_PATH with /opt/homebrew, and etc/Renviron
  has both lines.

Added in review:
- Scope. Unix R has no Rcmd_environ, so the variable is in every R
  session on macOS and in every program R starts, not only in package
  builds (S15's values on Windows are). A CMake run from R for something
  else (reticulate's pip, a terminal an IDE opens under R) leaves
  Homebrew out too.
- How a user opts out: CMAKE_TOOLCHAIN_FILE set in the environment
  before R starts (empty: no toolchain file), `Sys.setenv()` in a session
  or .Rprofile, or another file named in ~/.Renviron. An empty value in
  ~/.Renviron does nothing: R's reader skips a line whose value is empty
  (Renviron.c, `if(strlen(lhs) && strlen(rhs))`).
- Limits, measured on omicron: a package's own configure that asks
  Homebrew is not CMake's search. arrow runs `brew --prefix openssl`
  when brew is on PATH, exports OPENSSL_ROOT_DIR, and links Homebrew's
  OpenSSL. pkg-config's own search path is not covered either. Stock R
  does the same. A Homebrew installed elsewhere (`brew --prefix` not one
  of the four) is still searched first ("Review (2026-10-09)").

Tested on linux-64 (gamma) by its implementer, lock 7aef60ff unchanged:
- `pixi run --locked zig build --help`: rc 0. The macOS branches are
  compiled, since ctx.os is only known at run time. `zig fmt --check
  build.zig` and `bash -n scripts/verify-tree.sh` are clean.
- The text build.zig writes, in a mock macOS etc/. Unset
  CMAKE_TOOLCHAIN_FILE gives R_HOME/etc/r-zig.cmake, a set one keeps the
  user's value, an empty one stays empty. This holds for R's C reader
  (readRenviron, through the linux tree's Rscript) and for R CMD's sh
  sourcing.
- cmake 4.4.4 (the stress env) on a probe project with a fake prefix. A
  prefix on PATH: find_package CONFIG finds it, find_library and
  find_path do not. Either variable drops it, and a program on PATH is
  still found. A prefix put first in CMAKE_SYSTEM_PREFIX_PATH (Darwin's
  Homebrew, simulated): its library, header, config package and program
  are all dropped. A prefix in CMAKE_PREFIX_PATH: dropped; a prefix below
  it: kept. An empty CMAKE_TOOLCHAIN_FILE gives no toolchain file, and -D
  wins over the environment. With the real file: CMAKE_CROSSCOMPILING is
  FALSE, find_library(z) skips /usr/local/lib and /usr/local, keeps
  PATH's directories and /usr, and finds the env's lib/libz.so.
- verify-tree's new block on mock trees: passes on a good one, fails
  with no file and with the Renviron line missing, and is skipped on
  linux.
- On macOS since: omicron ("Tested on the hosts (testers, 2026-10-09)").

## Tested on the hosts (testers, 2026-10-09)

The worktree after round 2's answers: main 7a3004d plus the uncommitted
changes (`git diff | sha256sum` 382d401f...; the five untracked .zig
files, `sha256sum | sha256sum` 2923c91c...), pixi.lock 7aef60ff...a355a63,
unchanged on every host. The stress runner and its env came from
feat-stress-suite, read-only (`git diff | sha256sum` fe3477f0..., its
lock fbb64b7b...bb96). conda-forge's zig 0.16.0 (build 20); "upstream"
is PyPI's ziglang 0.16.0 from `pixi run fetch-zig`, through ZIG_BIN.
The testers worked on copies on omicron and kappa and edited neither
worktree. Logs: /data/gamma/luciorq/workspaces/temp/r-zig-pixi/r2ans/
(testlinux/, omicron/, kappa/).

linux-64 (gamma):
- rzig-test (72 of 72; parity 59 identical, 57 ok+, 21 deliberate, 0
  failed), build (2.4 min), verify-tree, smoke, contract,
  verify-package, hermetic: pass.
- R2-3, the full stress suite through the tree (-j6, 52.7 min): 33
  targets ok, 6 fail-abi (magick, sf, terra, gdalraster, protolite, V8,
  A1), lwgeom skipped (fail-dependency), 86 dependencies ok, 0
  unexpected: round 2's statuses. Every ok target loaded, ran its smoke
  call, unloaded, and R exited 0. None of the 81 package .so files has a
  .debug_* section or a .symtab. In all they went from 402.6 MB (round 2)
  to 208.6 MB: Rcpp 5.78 to 1.16 MB, duckdb 64.5 to 47.5, arrow 57.6 to
  39.7, mlpack 33.1 to 23.1. RcppParallel's bundled libtbb*.so.2 keep
  their DWARF: oneTBB's CMake defaults to RelWithDebInfo, so its link
  line has a -g.
- R2-3 and debug builds, a small C++ package through the tree: no
  Makevars, 242,992 bytes and stripped; `CXXFLAGS = -g`, stripped;
  `CXXFLAGS = -g` and `LDFLAGS = -g`, 1,558,816 bytes, 7 .debug_*
  sections and .symtab. pkgbuild 1.4.8's compile_dll(debug = TRUE):
  f.o has 5 .debug_* sections, gpk.so none (R2-3's consequences). Each
  loads, throws and catches, and unloads.
- R2-4 (1): `pixi run --locked -e pkg conda-package` in a copy (4.5
  min): r-zig-slim-4.6.1-hb0f4dca_7 and r-zig-toolchain-4.6.1-hbd87d40_7,
  both tests pass. r-zig-slim depends on `libdeflate >=1.25,<1.26.0a0`.
- R2-4 (2): `stress.R --conda=<that channel> units s2 sf terra gdalraster
  lwgeom` (8.1 min). The env solved with libgdal-core 3.13.3, libdeflate
  1.25, geos 3.14.1 and proj 9.9.0 (S19). units and s2 ok; sf, terra and
  gdalraster compiled and linked, then failed their load test with
  abi (A1, as expected); lwgeom skipped; 16 dependencies ok; 0
  unexpected.
- R2-4 (3), upstream zig: rzig-test (72 of 72, parity 0 failed), build
  (3.75 min), verify-tree, smoke, contract, verify-package: pass.
  contract's Rcpp.so: 1,161,880 bytes, no .debug_*.
- The runner's cache rule (the suite's R2-9) with real rzig entries:
  each run, with an XDG_CACHE_HOME of its own, removed only the
  dso-fini-<key>/ it added and kept an older entry.

osx-arm64 (omicron):
- rzig-test (72 of 72; the CFG and strip tests have nothing to check
  there), build (2.0 min), verify-tree (with R2-10's check), smoke,
  contract, verify-package: pass.
- R2-10, a probe package whose configure runs CMake's find_* and builds
  a static library with R's CC, against Homebrew's snappy: with the
  tree's file, the env's libsnappy, with brew off PATH and on it; with
  `CMAKE_TOOLCHAIN_FILE=""` (stock CMake), /opt/homebrew/lib/libsnappy
  both times. The same through the conda build 7's R and its own
  etc/r-zig.cmake. Only find_library and find_path leaked: find_package
  CONFIG and FindOpenSSL found the env first anyway.
- R2-10 with arrow's default row, `--keep-path` (so the tree's file
  applies) and brew off PATH, round 2's H2 case: ok, 8.7 min. PKG_LIBS
  and the log name no /opt/homebrew (round 2: /opt/homebrew/lib/
  libsnappy.a); otool -L shows the env and the system only. With brew on
  PATH: ok, but arrow's configure asks brew for OpenSSL and links
  Homebrew's (R2-10's limits).
- R2-4 (1): conda-package (3.1 min): r-zig-slim-4.6.1-h41cfa24_7 and
  r-zig-toolchain-4.6.1-hadbdee1_7, both tests pass; libdeflate
  `>=1.25,<1.26.0a0`. The package has etc/r-zig.cmake and the two
  Renviron lines.
- R2-4 (2): `--conda sf terra gdalraster lwgeom units s2 xml2`. units,
  s2 and xml2 are named so that their sysdeps are in the env
  ("Review (2026-10-09)", the suite). The env solved (libgdal-core
  3.13.3, libdeflate 1.25, geos 3.14.1, proj 9.9.0, cmake 4.4.4). xml2,
  units, terra and gdalraster ok. s2 failed: the env has no libabseil,
  so s2 builds its bundled abseil, and S5 rewrote the -march after
  abseil's `-Xarch_arm64` ("Review (2026-10-09)", 1). sf and lwgeom were
  skipped behind it. With that item's rzig copied into the env's
  R_HOME/bin/toolchain and `--resume`: 7 of 7 targets ok (s2 1.1 min, sf,
  lwgeom), each unloaded, R exited 0. A conda package built with the fix
  has not been run.
- R2-4 (3), upstream zig: rzig-test, build (2.0 min), verify-tree,
  smoke, contract, verify-package: pass. rzig's cache stayed empty
  (upstream zig needs no libc++ mirror).
- No Falcon sign in any log. Everything the run made on omicron is
  removed; rzig's cache is back to its 15 earlier entries.

win-64 (kappa):
- rzig-test (52 passed, 20 skipped of 72: the tests with shell
  stand-ins, cfguard's cache test among them), build (7.5 min),
  verify-tree, smoke, contract (S10's check included), verify-package:
  pass.
- R2-1 (a): magick 2.9.1 through the tree, `--trace`: ok in 1.02 min,
  61.9 MB, with the clang-x86_64 r-windows ImageMagick 6.9.13.29 bundle.
  The link line has cfguard-<key>/guard_dispatch.o before the caller's
  arguments. It loads, magick_config()$version
  is 6.9.13.29, it unloads, and R exits 0. An SVG read through the
  bundle's librsvg (Rust, built with CFG, whose indirect calls go
  through the stub) gives the right pixels. magick.dll does not export
  `__guard_dispatch_icall_dummy`. With upstream zig (a tree it built):
  ok, 0.75 min, the SVG check too. Through the conda build 7: ok.
- Six rounds of 12 parallel `gcc.exe -shared` links, each round from no
  cfguard entry: 72 of 72 exit 0, no rzig warning, one entry per round.
  Under R CMD the stub went to %LOCALAPPDATA%\r-zig, so the review's
  Windows cache root ("After the review", 3), type-checked only then,
  now runs.
- R2-4 (1): conda-package (22.9 min): r-zig-slim-4.6.1-h9490d1a_7 and
  r-zig-toolchain-4.6.1-h5e29ac5_7, all tests pass; libdeflate
  `>=1.25,<1.26.0a0`. universe's win-64 has builds 2 to 6.
- R2-4 (2): `--conda sf terra gdalraster`. The env solved (build 7 from
  the local channel, libgdal-core 3.13.3, libdeflate 1.25, geos 3.14.1,
  proj 9.9.0). terra fail-sysdep (SD2) and gdalraster fail-abi, as
  expected. sf was skipped: its dependencies units and s2 failed, their
  sysdeps not in the env ("Review (2026-10-09)", the suite). 16
  dependencies ok, 0 unexpected. `--conda magick`: ok.
- R2-4 (3), upstream zig: rzig-test (52 and 20), build (6.5 min),
  verify-tree, smoke, contract, verify-package: pass.
- The runner's cache rule on Windows: each run removed only the
  cfguard-<key>/ it added, and the cache root when the run made it.
- recipe/test-toolchain.R leaves %LOCALAPPDATA%\zig (64.2 MB) and two
  cfguard-<key>/ entries per conda-package run ("Review (2026-10-09)",
  4).

Not run on any host: linux-aarch64 and osx-64; R2-4's macOS run with a
conda package built with "Review (2026-10-09)", 1; the full stress suite
on macOS and Windows with build 7 as it is now; `pixi run check`.

## Review (2026-10-09)

Open code items, for the user. Each diff is in
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/r2ans/review/diffs/
and passes `git apply --check` on this worktree; they touch different
files.

1. S5 and `-Xarch_<arch>` (rzig-s5-xarch.diff, omicron's; it blocks
   R2-4 on macOS). S5 rewrites a -march that is the value of
   `-Xarch_<arch>`. zig hands that value to clang's driver as it is, and
   clang refuses zig's spelling: "unsupported argument
   'generic+v8a+crypto' to option '-mcpu='". abseil's CMake on macOS
   passes `-Xarch_x86_64 -maes -Xarch_x86_64 -msse4.1 -Xarch_arm64
   -march=armv8-a+crypto`, so every bundled abseil fails there: s2 in a
   conda env without libabseil, a standalone user's s2, and sf and lwgeom
   behind it. Plain zig compiles the same line. The rule: the value of
   `-Xarch_<arch>` stays the caller's (cmdline.xarchValue, in marchArgs
   and dropTune, and the same in both shims), with lines in S5's unit
   test and one parity case. Tested: unit tests 72 of 72 on gamma and
   omicron; parity 60 identical, 57 ok+, 21 deliberate, 0 failed (138
   cases); marchArgs without the rule fails S5's test. On omicron, s2
   with S2_FORCE_BUNDLED_ABSEIL=true fails through the tree and installs
   through a patched one (its smoke call TRUE), and the conda run above
   reaches 7 of 7. No linux or Windows stress log has an `-Xarch_`
   (round 2's and this round's), so only macOS changes. With it, S5's
   text gains a sentence.
2. The CFG stub and -r (rzig-cfguard-no-r.diff; low). cfguard.wanted
   takes any command with an -o, a partial link too. zig's COFF -r takes
   one object ("coff does not support linking multiple objects into
   one", checked on gamma), so `-r a.o -o part.o`, which worked before,
   now stops. No package is known to do it. The diff leaves -r out, with
   a unit test case: 72 of 72 on gamma, `zig fmt` clean.
3. A Homebrew installed elsewhere (cmake-homebrew-prefix-env.diff;
   low). Darwin.cmake searches `brew --prefix` first, and a prefix other
   than the four stays in. The diff adds `$ENV{HOMEBREW_PREFIX}` (`brew
   shellenv` sets it; unset, it adds nothing) to etc/r-zig.cmake's list.
   Checked on gamma with cmake 4.4.4: a fake prefix named there is
   dropped from find_library and find_path, and without the variable the
   list is the four. Not run on macOS.
4. recipe/test-toolchain.R leaves caches (test-toolchain-caches.diff,
   kappa's; low). It leaves zig's cache (64.2 MB on win-64) and rzig's
   cfguard-<key>/ entries, keyed on the test env's zig, which is deleted
   afterwards. The diff gives the test its own ZIG_GLOBAL_CACHE_DIR,
   ZIG_LOCAL_CACHE_DIR and XDG_CACHE_HOME in its temp dir. On kappa,
   against a build-7 conda env: every line passes, and nothing is left
   (before: zig's 64.2 MB and two entries). Round 1's review listed the
   zig part as found, not decided.

For feat-stress-suite (same directory; each applies there alone, and
all four together in either order):
- stress-conda-deprow-sysdeps.diff (kappa's, rebased on the review's
  comment edits): `--conda` installs the sysdeps of every row the run
  installs, its dependencies' rows too. As it is, `--conda sf` skips sf
  on every OS, since units and s2 lack udunits2, cmake and openssl.
  `--sysdeps sf` goes from 'geos libgdal-core proj' to 'cmake geos
  libgdal-core openssl proj udunits2'; `--sysdeps` then reads the
  repositories.
- classifier-unsupported-argument.diff (omicron's): `unsupported
  argument '[^']*' to option '` joins the toolchain pattern. Item 1's
  log is then toolchain, not sysdep (s2's configure goes on to print
  "Package absl_base was not found"). None of round 1's or round 2's 55
  failed items changes class.
- stress-cmake-tree-file.diff (review): the runner writes its own
  toolchain file only for a tree without etc/r-zig.cmake. As it is, the
  runner's file replaces a build-7 tree's, so a default macOS run never
  tests the file r-zig ships. README and `--help` follow.
- packages-tsv-magick-windows.diff (kappa's): magick's Windows expect
  becomes ok, with R2-1.

Decisions for the user:
- A. R2-3 and debug builds. zig makes `-Wl,--strip-debug` a full strip.
  So R CMD check's compiled-code check (`nm -Pg`) sees no symbols, and a
  debug build keeps its DWARF only with -g on the link line.
  devtools::load_all() puts -g in CFLAGS, CXXFLAGS and FFLAGS only
  (pkgbuild 1.4.8), so its builds are stripped on linux.
  - (a) Keep it, and say so in the user docs: a debug build needs -g in
    LDFLAGS too (~/.R/Makevars). R's own Windows Makeconf strips every
    package DLL (DLLFLAGS = -s) unless DEBUG is set; linux now strips by
    default too.
  - (b) rzig strips only when no input object has DWARF (it reads the
    ELF section headers of the link's .o inputs). load_all() builds
    then keep theirs. More code, one more read per link.
  - (c) Back to S11 alone: 4 to 6 MB of zig's libc++ DWARF in every
    linux C++ package.
  Recommended: (a). `zig objcopy --strip-debug` after the link, which
  would keep .symtab, does not exist in zig 0.16.0 (R2-3).
- B. Build 7's publish (R2-4). As it stands, the macOS conda run fails
  for s2, sf and lwgeom. Recommended: apply item 1, build the conda
  package on omicron, and run `stress.R --conda sf terra gdalraster
  lwgeom units s2 xml2` there again (or `--conda sf terra gdalraster
  lwgeom` with the suite's deprow diff). The linux and Windows runs
  stand: item 1 changes nothing their logs have.

Found, not decided:
- In `--conda` mode the inner R inherits what the outer tree R's
  etc/Renviron set: R_ZIG_CA_BUNDLE, and on macOS CMAKE_TOOLCHAIN_FILE
  naming the outer tree's file (the same content). Inferred from R's
  reader and Rcmd.in, not measured.
- cfguard's key hashes zig's path as spelled, so one zig gets two
  entries on kappa (`C:/.../Library/bin\x86_64-w64-mingw32-zig.exe` and
  `C:\...\Library\bin\...`); the stub's path mixes separators. Each
  entry is about 0.9 KB; links work.
- magick.dll imports iconv.dll: the bundle has no libiconv.a, so after
  S10 -liconv binds the env's import library (Rtools links it
  statically). The tree ships iconv.dll in bin/x64.
- Each R build on kappa left two zero-byte cc* files in %TEMP%
  (libiberty's make_temp_file prefix; windres, probably).

Checked in review:
- `pixi run --locked rzig-test` on gamma: 72 of 72; parity 59
  identical, 57 ok+, 21 deliberate, 0 failed. pixi.lock unchanged.
- R2-1's stub: the directive works as A says (implementer A's DLLs: the
  one built with the stub but no directive exports
  `__guard_dispatch_icall_dummy`; with the directive, the same four
  names as without the stub). The source is mingw-w64's x86_64 part;
  `wanted` runs only when the OS is Windows; a link that pulls no
  mingw_cfguard_support.obj carries 16 bytes and nothing else uses them.
- R2-3: zig 0.16.0's main.zig reads -Wl,-s, --strip-all, -S and
  --strip-debug alike (strip = true), and its -g options set strip off.
  So the -g test decides it, and it reaches executables as well as
  shared libraries (configure's test programs, a package's own helper
  programs), as the rule says. R's own build is untouched: build.zig compiles R and its own
  shared objects without rzig. The shims also serve configure-only.sh's
  capture (gen-config), so the flag reaches its linux conftest links;
  not run.
- R2-10: Darwin.cmake in cmake 4.4.4 adds the prefixes B lists, and
  its framework paths name no package manager's prefix. Renviron.c and
  Rcmd.in read etc/Renviron as B says, with the empty-value rule above.
- The testers' claims against their logs: the linux .so table (81
  files, 402.6 to 208.6 MB, none with .debug_* or .symtab), the bundled
  libtbb*.so.2's DWARF, the debug-build sizes, kappa's magick link line
  and SVG check, omicron's probes and arrow logs, and the conda reports
  match. Two notes: kappa's Windows conda report counts 2 dependencies
  failed (units, s2) besides the 16 ok; omicron's standalone s2 check
  installed s2 and its smoke call printed TRUE, then stopped at a
  function s2 does not export, before its unloadNamespace (the conda
  run's `--resume` did unload s2).
- Comments and docs fixed: S5's open item, the cache section (Windows
  root, cfguard-<key>/), R2-1's end-to-end status, R2-3's `-Wl,-S`, its
  objcopy alternative and the load_all() consequence, and this file's
  R2-10 section (implementer B's text) and host results. In
  feat-stress-suite: the README's and `--help`'s `--keep-path` text,
  the cache entries (cfguard), round 2's record of where the answers
  landed, and feat-standalone-toolchain's H2 bullet.
