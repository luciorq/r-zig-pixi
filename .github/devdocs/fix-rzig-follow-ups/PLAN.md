# fix-rzig-follow-ups — rzig's follow-ups (PR ii): RZIG_PRINT_ARGV, -lgfortran, TCL_VERSION, Tcl/Tk headers, -lsynchronization

**Status (2026-10-08).** Branch fix-rzig-follow-ups, PR #19. It
started from origin/fix-rzig-baseline-cpu at 192ee86 (PR #14 plus
main's 0c7e19a). Implemented, reviewed, and tested on linux-64, win-64
(kappa) and osx-arm64 (omicron): every step passed, see "Tested". The
recipe's build number goes 5 → 6 (main is still at 5). After that,
D5's follow-up was answered (T1, 2026-10-08): the standalone Windows
tree now ships Tcl/Tk's headers in R_HOME/Tcl/include (D5 below),
tested on linux-64 and kappa, reviewed.

The user then rebased the branch onto main 9239285 (PRs #14, #15, #17
and #18 merged) and committed it: a42a6bd (the work below, the same as
471d0e7) and 3ea083c (T1). Since then pixi.lock is main's, sha256
7aef60ff4b270486cf70786f20e21b50cde2638eb6b6deba62d934e780355a63. Next
to 192ee86's it only adds binutils 2.46.1 and strace 7.2 to the linux
envs; no win-64 or osx package changes. The runs in "Tested" used
192ee86's lock; kappa's second T1 run used main's (D5, "Tests (T1)").
The T1 record in feat-standalone-toolchain PLAN.md is applied on top
of 3ea083c, with the review's edits (not committed).

## What, and the user's answers

PR (ii) of feat-no-host-paths/PLAN.md's follow-up list, from the answers
of 2026-10-08 (recorded on feat-standalone-toolchain, 64acfbd, "Answers
of 2026-10-08"; the user's reply to the menu was "all ★", the
recommended option, except, for these items, verbatim "D6: b - rzig
deals with the import library, do not report anything yet."):

- E4 (fix-rzig-baseline-cpu/PLAN.md's follow-ups): `RZIG_PRINT_ARGV`
  overwrote the start of a regular file its output was redirected to.
- D4 a (feat-no-host-paths What remains 10): rzig maps `-lgfortran` and
  `-lquadmath` to flang's runtime (FLIBS's `-lflang_rt.runtime`) instead
  of looking for a gfortran on PATH. The answer named Windows; the task
  asked whether the same rule holds on linux and macOS: it does, and it
  is one rule for every OS (below).
- D5 a (What remains 5): Windows Makeconf's `TCL_VERSION` becomes `86t`,
  and tkrplot is tested on kappa.
- D6 b (What remains 8): rzig provides the `synchronization` import
  library for upstream zig itself; nothing is reported upstream.
- T1 (D5's follow-up, 2026-10-08), verbatim: "Ship the headers in the
  base at R_HOME/Tcl/include, where package Makevars expect them." An
  explicit exception to "compile-time files go in the toolchain"
  (feat-standalone-toolchain PLAN.md), matching CRAN's Windows layout.

## E4: RZIG_PRINT_ARGV appends

main.zig's printArgv wrote through `Io.File.stdout().writer(io, &buf)`,
zig 0.16's positional writer (File.Writer `.mode = .positional`, which
keeps its own position, from 0, and writes there), so in `{ echo
first; RZIG_PRINT_ARGV=1 zig-cc -c a.c; } > out` the argv overwrote
"first". It now writes through `writerStreaming` (`.mode =
.streaming`: write(2) at the file's own offset, as `echo` does), to a
file it is given (main passes stdout). The repo's own uses read it through `$(...)`, a pipe, where
both writers behave the same, so nothing in the pipeline changes.

Unit test (main.zig, `test printArgv`): a file with "first\n" written
through the same handle, then two printArgv calls; the file must hold
all three in order. With `writer` in place of `writerStreaming` the
test fails. The built binary, `{ echo "first line from the shell";
env -i ZIG_BIN=/z/zig RZIG_PRINT_ARGV=1 ./zig-cc -c a.c; } > out`:
192ee86's rzig leaves no trace of the first line; this branch's keeps
it, then the argv.

On the hosts (testers, 2026-10-08), 192ee86's rzig against this
branch's: linux-64, two zig-cc runs into one `>` (192ee86 leaves only
the last argv; this branch everything, in order); osx-arm64, the
shell's first line (lost; kept); win-64 under cmd, `(echo first&
gcc.exe -c a.c) > f`, the same with `>>`, and with a line after (192ee86
loses every line written before it; this branch keeps them all). Two
things the hosts added. With `>>`, 192ee86 appended on Linux, because
Linux's pwrite(2) ignores the offset on an O_APPEND file (POSIX says it
should not); the unit test's file is not O_APPEND, so it catches the bug
on Linux too. On Windows the positional write also left the shared
handle's file pointer after the argv, so later output to the same
redirect, from any process, overwrote what followed (it wrecked a
tester's log on kappa). The streaming writer depends on neither.

## D4: -lgfortran and -lquadmath are flang's runtime, on every OS

flang_rt.zig: `-lflang_rt.runtime`, `-lgfortran` and `-lquadmath`, each
as a whole argument, count as one flag. The first of them becomes the
static archive of the flang on PATH (or goes, with no flang, or with a
warning when that flang has no archive), every later one goes. It runs
first in compiler.argv, so zig-cc, zig-cxx, gcc.exe, g++.exe and zig-fc's
shared links (fortran.zig) all get it. windows.zig's `gfortranLibDir`
(`gfortran -print-file-name=libgfortran.dll.a` and its directory as one
more -L) is gone, and with it the last place rzig looked for gfortran.

Why one rule for every OS: FC is flang everywhere, so the Fortran
runtime a link needs is flang's; gfortran's libgfortran defines no
symbol flang's code calls. What a Makevars with `PKG_LIBS = -lgfortran`
(or `-lquadmath`) did before, measured on linux-64 with 192ee86's rzig,
zig 0.16.0 (conda-forge's), the worktree's pixi env, a flang-compiled
object calling `print *` and a C object:

| env R_ZIG_EXTRA_ENV names | -lgfortran | -lquadmath |
|---|---|---|
| default (no libgfortran; libgcc's libquadmath) | link fails: "unable to find dynamic system library 'gfortran'" | links; zig drops libquadmath as unneeded (no DT_NEEDED) |
| openblas (conda-forge libgfortran 5) | links; zig drops it as unneeded; loading fails: "undefined symbol: _FortranAioBeginExternalListOutput" | the same as default |
| none (a standalone tree used alone) | link fails | link fails: "unable to find dynamic system library 'quadmath'" |

So no case where either flag did anything useful for flang's code.
Only the openblas variants' environments carry libgfortran (openblas's
dependency), on every unix platform (pixi.lock). On macOS (omicron,
osx-arm64, 192ee86's rzig in a copy of the tree) both flags failed the
link outright ("unable to find dynamic system library 'gfortran'", and
the same for 'quadmath'): neither the environment nor the SDK has
either library, so even a C-only package naming them did not install.
On Windows rzig linked Rtools' libgfortran when a gfortran was on PATH
(no flang symbol either) and failed otherwise. kappa, 192ee86's rzig:
with a gfortran on PATH it ran `gfortran
-print-file-name=libgfortran.dll.a` and linked that file, and
`-lquadmath` became the env's Library/lib/libquadmath.dll.a; without
one, every `-lgfortran` link failed, and a flang object linked with
`-lquadmath` alone failed on undefined `_FortranAio*` symbols.

With this branch, the same links: every one succeeds and loads
(`hello from flang 7` through ctypes), with no DT_NEEDED beyond glibc's
and no rpath for the runtime. A C-only link with `-lgfortran
-lquadmath` gives a byte-identical .so to the one without them (an
archive member is only pulled for a symbol something needs). The
package-level checks on the three hosts are under "Tested".

What could lose: C or C++ that calls libquadmath itself (`sqrtq`,
Boost's float128). That needs GCC's quadmath.h, which zig does not ship
and no environment here has (none of the pixi envs' include/, the zig
lib dir), so such code does not compile through rzig in the first place.
flang-rt-zig's runtime does not use libquadmath (no `*q` math symbol
among its undefined ones on linux-64). Two more cases lose, both
outside what the toolchain compiles, and neither seen in a package:
- Code compiled by gfortran (a prebuilt static library a package
  downloads or finds on the system) calls libgfortran's `_gfortran_*`,
  which flang's runtime does not define, and `-lgfortran` no longer
  brings libgfortran. Before, it linked only where the environment
  happened to have libgfortran (the openblas variants') or a gfortran
  was on PATH (Windows). r-zig compiles a package's Fortran with FC,
  flang, and ships no gfortran.
- C that declares libquadmath's functions itself, without quadmath.h:
  it linked where the environment has a libquadmath (linux-64's libgcc,
  win-64's Library/lib/libquadmath.dll.a), and now leaves them undefined
  (a link error on Windows, a load error on linux).

Not covered: zig-fc's own flang commands (compiles, `-E`, configure's
mixed source+link probes) pass the caller's arguments to flang as they
are, so a `-lgfortran` there is flang's driver's to find, as before.

On Windows FLIBS is `-lflang_rt.runtime -lc++` (the runtime is C++
there and PE refuses unresolved symbols); `-lgfortran` maps to the
runtime alone, as `-lflang_rt.runtime` does. A package with Fortran
sources gets FLIBS from R CMD SHLIB anyway (install.R's shlib_libadd),
`-lc++` with it; only a C link that pulls flang's runtime for Fortran
objects it built outside R's rules, with `-lgfortran` and no FLIBS, would
also need `-lc++` (a C++ link has libc++ already). kappa did not
reproduce it: a flang object with internal formatted I/O, linked by
gcc.exe with `-lgfortran` (or `-lquadmath`) alone, no `-lc++` and no
FLIBS, linked and loaded. Runtime members that use libc++ might still
need it; not checked further.

The bash shims (toolchain/zig-cc, zig-cxx), parity-test.sh's reference,
make the same change: their Fortran-runtime block triggers on the three
flags and replaces the first, and their Windows branch no longer asks
gfortran. A no-op for configure-only.sh, R's own configure, whose FLIBS
is flang's. So the parity test stays a byte-for-byte comparison; the
deliberate difference "-lgfortran without gfortran" (the shim's `-L.`)
is gone with the code that made it.

Tests: flang_rt.zig (the three flags on linux, macOS and Windows, with
FLIBS before and after, `-lc++` kept, other names and the two-argument
form untouched, all dropped without flang); compiler.zig (every OS,
cc's whole command line for `-lgfortran -lquadmath -lflang_rt.runtime`
and each alone, a gfortran stub on PATH that records being run must
never run); seven parity cases (four linux, one macOS, two Windows).

## D5: TCL_VERSION = 86t on Windows

zigbuild/config/win-x86_64-full/Makeconf.win (the vendored gnuwin32
Makeconf): `TCL_VERSION = 86` → `86t`, with a comment. R's Makeconf.win
links packages to Tcl/Tk through `TCLTK_LIBS = -L"$(TCL_HOME)/bin"
-ltcl$(TCL_VERSION) -ltk$(TCL_VERSION)`, and tkrplot 0.0-32's
Makevars.win spells the same (`-L"$(TCL_HOME)"/bin$(TCLBIN)
-ltcl$(TCL_VERSION) -ltk$(TCL_VERSION) -lgdi32`). The Tcl/Tk r-zig ships
is conda-forge's tk 8.6, the threaded build: win-64
tk-8.6.13-h967ab96_4 has Library/bin/tcl86t.dll, tk86t.dll,
Library/lib/tcl86t.lib, tk86t.lib and Library/include/tcl.h, tk.h (its
paths.json), and nothing named tcl86. So `-ltcl86` found nothing,
in the standalone tree (R_HOME/Tcl/bin has tcl86t.dll) and in a conda
env (Library/lib has tcl86t.lib) alike.

Where else the names appear, all already 86t: subst.txt's
WIN_TCLTK_LIBS (`-ltcl86t -ltk86t -luser32`, build.zig winTcltkLib for
R's own tcltk.dll); build.zig installEnvRuntime (Tcl/bin/tcl86t.dll,
tk86t.dll; the conda build's Renviron.site sets MY_TCLTK to a
directory, no names); verify-tree.sh's Tcl/Tk and DLL-closure checks;
pixi.toml's and the recipe's `tk = "8.6.*"` comments. verify-tree.sh
now also reads Makeconf's TCL_VERSION and requires
Tcl/bin/tcl$(TCL_VERSION).dll and tk$(TCL_VERSION).dll in a standalone
Windows tree (checked here on a fake tree: 86t passes, 86 fails naming
both DLLs; CRLF line ends handled). build.zig's comment by the TCL_HOME
line says where TCL_VERSION comes from.

zig links a DLL named by `-l` directly (`-L<dir> -lfoo86t` with only
foo86t.dll in dir links and imports from it, both zigs, cross-linked
from linux-64), so the standalone tree's R_HOME/Tcl/bin is enough to
link. On kappa the tkrplot link ran under pixi, where rzig puts the
environments' -L before the package's (before the first -o), so
`-ltcl86t` most likely resolved to the pixi env's
Library/lib/tcl86t.lib, not to R_HOME/Tcl/bin/tcl86t.dll; the DLL
imported is tcl86t.dll either way. A link from the tree alone could not
be tried there: the compile stopped first, at tk.h. The standalone tree
had no R_HOME/Tcl/include (installEnvRuntime shipped Tcl/bin and
Tcl/lib only), so tkrplot's `-I$(TCL_HOME)/include` named nothing and
`#include <tk.h>` resolved only through the environment rzig compiles
against (R_ZIG_EXTRA_ENV's Library/include under pixi; a conda env's
own). A standalone tree used alone could not compile Tcl/Tk C code.
kappa confirmed it: with R_ZIG_EXTRA_ENV unset, tkrplot stopped at
"tcltkimg.c:3:10: fatal error: 'tk.h' file not found". The follow-up
decision (ship the env's tk headers as R_HOME/Tcl/include, where
Makeconf's TCLTK_CPPFLAGS, `-I "$(TCL_HOME)/include"`, looks) is
answered: T1, below.

### The follow-up: Tcl/Tk's headers in R_HOME/Tcl/include (T1)

The user's answer (2026-10-08), verbatim: "Ship the headers in the base
at R_HOME/Tcl/include, where package Makevars expect them." T1 = (a):
the one exception to "compile-time files go in the toolchain"
(feat-standalone-toolchain PLAN.md). It matches CRAN's Windows layout:
Makeconf.win has `TCL_HOME = $(R_HOME)/Tcl`, R's own Windows build
compiles tcltk with `-I "$(TCL_HOME)"/include`
(src/library/tcltk/src/Makefile.win), and its installer copies the
whole R_HOME/Tcl (src/gnuwin32/installer/Makefile:154-163).

What ships. build.zig's installEnvRuntime, in a Windows tree that is
not the env, installs 13 headers from the env's Library/include into
R_HOME/Tcl/include, keeping X11/: tcl.h, tclDecls.h, tclPlatDecls.h,
tk.h, tkDecls.h, tkPlatDecls.h, tkIntXlibDecls.h, X11/X.h,
X11/Xfuncproto.h, X11/Xlib.h, X11/Xutil.h, X11/keysym.h and
X11/keysymdef.h (690,477 B). A missing one fails the build, naming it,
as a missing Tcl/bin DLL does. The set is tcl.h, tk.h and tkPlatDecls.h
(Tk_GetHWND and the rest) with what they include:
- conda-forge's win-64 tk-8.6.13-h967ab96_4 is the lock's only win-64
  tk, in every env that has tk (the downloaded .conda's sha256 matches
  the lock's). Its paths.json lists 28 files in Library/include: these
  13, and tclOO.h, tclOODecls.h, tclTomMath.h, tclTomMathDecls.h,
  itcl.h, itclDecls.h, tdbc.h, tdbcDecls.h, and X11's ap_keysym.h,
  cursorfont.h, DECkeysym.h, HPkeysym.h, Sunkeysym.h, XF86keysym.h and
  Xatom.h. None has a prefix placeholder or names a path.
- tk.h includes X11/Xlib.h, Tk's stand-in for Xlib on Windows. That
  brings X11/X.h, Xfuncproto.h and tkIntXlibDecls.h, which brings
  X11/Xutil.h, keysym.h and keysymdef.h. tcl.h brings tclDecls.h and
  tclPlatDecls.h. tk.h does not include tkPlatDecls.h; a Windows
  package includes it for Tk_GetHWND and the rest.
- `zig cc -target x86_64-windows-gnu -DWin32 -M`, with all 28 on -I: a
  file that includes `<windows.h>`, `<tk.h>` and `<tkPlatDecls.h>`
  depends on exactly these 13. tkrplot 0.0-32's one source,
  tcltkimg.c, depends on the same 13 but tkPlatDecls.h (on Windows it
  includes `<tk.h>` and `<windows.h>`; `<X11/Xutil.h>` only off
  Windows).

The conda build does not change: it has no R_HOME/Tcl, and the tk
package's Library/include, which rzig's environment searches with
`-idirafter`, has the headers. So the conda package's content is the
same and the build number stays 6. Makeconf.win does not change either:
its TCLTK_CPPFLAGS already names `$(TCL_HOME)/include`.

verify-tree.sh's Tcl/Tk check runs on every Windows tree that is not a
conda env, and already requires the DLLs in Tcl/bin. It now also
requires Tcl/include/tcl.h and tk.h, non-empty, and its summary line
counts the headers. Its error now begins "Tcl/Tk in <R_HOME>/Tcl:".

The standalone plan records T1 in its "Resolved decisions", with the
reason, and where it lists what the base holds on Windows (sections
1, 2 and 5, and Verification). The implementer wrote it as a patch
against main's file, since the branch did not have that file yet
(/data/gamma/luciorq/workspaces/temp/r-zig-pixi/tclhdr/impl/t1-standalone-plan.patch).
After the rebase onto main the review applied it, adding the kappa
result and correcting the PyPI line (the wheel is minimal, and Windows
minimal drops Tcl/Tk, C1).

Tests (T1):
- linux-64 (gamma), implementer, in the worktree, pixi.lock unchanged
  (a7d3dcec..., as above):
  - `pixi run --locked zig build --help` compiles build.zig, exit 0.
    The new Windows code is analysed on linux too: a type error planted
    in it failed the same command (then removed).
  - `zig fmt --check build.zig` clean; `bash -n scripts/verify-tree.sh`.
  - The 13 headers alone on -I: the test file above and tkrplot's
    tcltkimg.c (with -DWin32, the linux tree's R headers standing in
    for Windows') compile to x86_64 COFF objects with
    `zig cc -target x86_64-windows-gnu`. With X11/keysymdef.h,
    tkIntXlibDecls.h or tclPlatDecls.h left out, the tkrplot compile
    fails, naming the missing file.
  - verify-tree.sh's Windows Tcl/Tk block on a fake tree (CRLF
    Makeconf): passes with the 13 headers ("13 headers in
    Tcl/include"); fails naming Tcl/include/tk.h when it is missing,
    and naming both when tcl.h is empty and tk.h missing, or when
    Tcl/include is missing.
- win-64 (kappa), tester, pixi 0.81.0, two runs, all passed. Run 1:
  471d0e7 plus the uncommitted T1 diff (sha256 ed5284ff..., the
  implementer's tested diff), lock a7d3dcec.... Run 2: 3ea083c, clean,
  lock 7aef60ff... (main's). 3ea083c's added and removed lines are
  those of the tested diff, and the win-64 tk is the same in both locks.
  Logs: tclhdr/kappa/{run1-471d0e7+T1diff,run2-3ea083c}/ in the scratch
  area, each with a STATE.txt naming the hashes tested.
  - `pixi install --locked`, then `pixi run --locked` build (-j6, 7m43s
    and 7m52s from a fresh zig cache), verify-tree, smoke,
    verify-package and contract (Rcpp, data.table, minqa, quadprog, pak,
    ps): all exit 0. verify-tree: "== Tcl/Tk runtime verified: ...
    Makeconf's TCL_VERSION = 86t, 1009 files in Tcl/lib, 13 headers in
    Tcl/include". Zips: sha256 f37cf136... (run 1), fdfe4c52... (run 2).
  - R_HOME/Tcl/include in the extracted zip: 13 files, 690,477 B, the
    same bytes as the env's Library/include, the installed dist tree and
    the implementer's expected list (run 1's hash.log prints "DIFFERS"
    for that last one only because sha256sum marked binary mode with
    `*`: its expected.norm and kappa-tree.sha256 are equal). R_HOME/Tcl
    holds bin, include and lib.
  - tkrplot 0.0-32 from CRAN source (sha256 a37a591e..., downloaded with
    the tree's own Rscript), from the extracted zip alone: PATH = the
    tree's bin\x64, System32 and the env's Library\usr\bin (sh, make);
    R_ZIG_EXTRA_ENV, CONDA_PREFIX and PIXI_* unset; ZIG_BIN = the env's
    zig (the tree ships none yet). R CMD INSTALL: DONE. The compile has
    `-I "<R_HOME>/Tcl"/include`; the only include option rzig's argv
    (RZIG_PRINT_ARGV=1) adds is `-idirafter <tree>/Library/include`,
    and nothing on it points into the env but zig itself (argv[0]).
    Replayed with -H: the 12 Tcl/Tk headers tcltkimg.c opens
    (tkPlatDecls.h is not one) come from R_HOME/Tcl/include; of 689
    header openings, 29 are the tree's and 660 zig's own libc headers,
    none from anywhere else (both runs, recounted from h.txt at review).
    The link: `-L<R_HOME>/Tcl/bin -ltcl86t -ltk86t`, rzig adding only
    `-L<tree>/Library/lib`, which holds no Tcl/Tk library, so zig linked
    the DLLs directly. tkrplot.dll imports tcl86t.dll, tk86t.dll, R.dll
    and system DLLs.
  - Load, PATH = the tree's bin\x64 and System32 only:
    `library(tkrplot)` with `options(warn = 2)`; Tcl/Tk 8.6.13 with
    tcl_library under R_HOME/Tcl/lib; the Rplot image type is
    registered; `tkrplot(tktoplevel(), function() plot(1:10))` makes a
    344 x 288 image.
  - Control: with R_HOME/Tcl/include moved away, R CMD INSTALL stops at
    "tcltkimg.c:3:10: fatal error: 'tk.h' file not found".
  - Some of the tester's own script output is void, not the product:
    run 1's replay.log hash section (Windows find/sort ran; hash.log
    redoes it); run 1's list of "any header from the pixi env other
    than zig's own lib dir", which shows zig's own headers, and run 2's
    last "zig's own lib dir" count, 0 (both greps missed -H's doubled
    backslashes; the counts above are the review's recount).
- windows-latest (CI, PR #19, run 37844621816, on 3ea083c): build,
  verify-tree (the same line, "13 headers in Tcl/include"), smoke,
  contract, regression, hermetic and the relocated archive passed. Its
  conda-package / win-64 leg was still running at review.

## D6: -lsynchronization links with upstream zig

zig makes the import library for `-l<n>` on a MinGW target from `<n>.def`
in its lib/libc/mingw. Upstream zig 0.16.0 has no synchronization.def;
conda-forge's zig ships one plus prebuilt import libraries
(lib-common/libsynchronization.a and others). conda-forge's
synchronization.def is `LIBRARY api-ms-win-core-synch-l1-2-0.dll` with
the same 17 exports as lib-common/api-ms-win-core-synch-l1-2-0.def, which
both zigs ship (byte-identical). So windows.zig renames the library
before its usual lookup: `mingw_names` maps `synchronization` to
`api-ms-win-core-synch-l1-2-0`, for both zigs, one rule. The simplest
of the options: no import library to build or cache; an
`api-ms-win-core-synch-l1-2-0.dll.a` in a -L directory is still found
first, as any other name.

How this answers D6 b. feat-standalone-toolchain's PLAN and TODO
sketched an import library rzig generates when the zig it runs has none
(for example from MinGW's .def with zig's dlltool, into rzig's cache),
conda-forge's zig keeping its prebuilt one. The rename does that job
with less: zig itself builds the import library from the API set's
.def into its own cache, as for any MinGW system library (`-lws2_32`),
so rzig keeps no cache, generates nothing, has nothing to lock or race
on between parallel links, and needs no "has none" probe. It is one
rule for both zigs: conda-forge's uses the .def too, which gives the
same import table as its prebuilt libsynchronization.a. That TODO's
phase 5 box ("unless feat-no-host-paths' rzig follow-up PR (ii) has
landed it") is this branch. Only the one-argument `-lsynchronization`
is renamed; `-l synchronization`, `-Wl,-lsynchronization` and response
files pass as they are, as importLib leaves them. rustc and
Makevars.win use the one-argument form.

Evidence (linux-64, cross-compiling a C file that calls WaitOnAddress,
WakeByAddressSingle and WakeByAddressAll for x86_64-windows-gnu):

| zig | -lsynchronization | -lapi-ms-win-core-synch-l1-2-0 |
|---|---|---|
| conda-forge 0.16.0 | links | links |
| upstream 0.16.0 (fetch-zig) | "unable to find dynamic system library 'synchronization'" | links |

All three links import the three functions from
api-ms-win-core-synch-l1-2-0.dll (objdump -p). The command rzig prints
for `gcc wait.c -o w -lsynchronization` (RZIG_PRINT_ARGV, RZIG_OS=windows)
links with both zigs once given `-target x86_64-windows-gnu`. Natively
on kappa ("Tested"), the tree's gcc.exe links the same file with both
zigs, and the program runs. The C file:

```c
#include <windows.h>
#include <stdio.h>
int main(void) {
  LONG v = 0, cmp = 1;
  BOOL ok = WaitOnAddress(&v, &cmp, sizeof v, 0);
  WakeByAddressSingle(&v);
  WakeByAddressAll(&v);
  printf("WaitOnAddress %d\n", (int)ok);
  return 0;
}
```

It prints "WaitOnAddress 1": the values differ, so the wait returns at
once.

The shims make the same rename, for parity. Tests: windows.zig (Rust's
library list, the renamed name looked up in -L directories,
`-lsynchronizationx`, `-lsynch`, the two-argument form and `-Wl,` left
alone); two parity cases.

## Files

- zigbuild/tools/rzig/main.zig: printArgv (E4) and its test.
- zigbuild/tools/rzig/flang_rt.zig: the three flags (D4), tests.
- zigbuild/tools/rzig/windows.zig: gfortran's lookup out (D4),
  mingw_names (D6), tests.
- zigbuild/tools/rzig/compiler.zig: a test, every OS (D4).
- zigbuild/tools/rzig/find_zig.zig: a comment (no gfortran).
- toolchain/zig-cc, zig-cxx: the same as rzig (D4, D6).
- zigbuild/tools/rzig/parity-test.sh: nine new cases, two old ones out.
- zigbuild/config/win-x86_64-full/Makeconf.win: TCL_VERSION (D5).
- scripts/verify-tree.sh: TCL_VERSION against R_HOME/Tcl/bin (D5);
  Tcl/include's tcl.h and tk.h (T1).
- build.zig: a comment (D5); Tcl/Tk's headers in R_HOME/Tcl/include,
  Windows trees that are not the env (T1).
- recipe/recipe.yaml: build number 5 → 6.
- .github/devdocs/feat-standalone-toolchain/PLAN.md: the T1 record
  (Resolved decisions; sections 1, 2 and 5; Verification).

## Tested

T1 (D5's follow-up) came after these runs: its checks (linux-64,
kappa, one CI leg) are in D5, "Tests (T1)", and its review below.

Every host: pixi.lock sha256
a7d3dcecb5592fbe165e8476af400c96f6800268d19a7e59dd7357a554154f79
(192ee86's), unchanged before and after, every task `--locked`; the
slim (default) environment; conda-forge zig 0.16.0 unless upstream zig
(PyPI's ziglang 0.16.0, `pixi run --locked fetch-zig`) is named. The
tracked diff the testers ran: sha256
90bc4fcf74a79339ca7380f9bbb6c58f41ab5620e017326dbdc81018cdce09d3 on
192ee86; the review changed only comments and this record afterwards.
The logs are under rzigfix/{impl,linux,kappa,omicron}/ in the scratch
area (/data/gamma/luciorq/workspaces/temp/r-zig-pixi/).

linux-64 (gamma), implementer:
- `pixi run --locked rzig-test`: 46/46 unit tests (43 before: four new
  test blocks, Windows' gfortran test out); parity "50 identical, 31
  identical but for rzig's own-environment -L, 17 deliberate
  differences, 0 failed" (98 cases; 91 before, 18 deliberate then).
- The tests bite: printArgv's test fails with the positional writer;
  without the two new flags three tests fail (flang_rt's two and
  compiler's); without the rename windows.zig's test fails. This rzig
  against 192ee86's shims fails 8 parity cases (every new case but the
  one about other names).
- rzig builds for x86_64-windows-gnu, aarch64-macos, x86_64-macos and
  aarch64-linux-musl; the unit tests compile for Windows and macOS
  (`--test-no-exec`); `zig fmt --check` clean.
- The E4, D4 (default and openblas envs as R_ZIG_EXTRA_ENV), D5 (a fake
  tree for verify-tree's check) and D6 (cross-linked, both zigs) checks
  by hand above.

linux-64 (gamma), tester, in the worktree:
- rzig-test (the same numbers), build ("zig-built R OK: R version
  4.6.1", 49 conda libraries vendored), verify-tree, smoke, contract
  (Rcpp, data.table with OpenMP, minqa, quadprog, pak, ps) and
  verify-package (R-4.6.1-slim-linux-64.tar.gz relocatable; its C++,
  Fortran, USE_FC_TO_LINK and OpenMP packages, `$(FLIBS)` without
  flang, CONDA_PREFIX ignored): all passed.
- E4: `{ echo first; zig-cc -c a.c; zig-cc -c b.c; } > out` with the
  tree's zig-cc: 192ee86's rzig leaves 9 lines (b.c's argv only), this
  branch's 19, in order. `>>` onto a file: both append (Linux O_APPEND).
- D4: a Fortran package (`print *`, an internal write and read, norm2)
  and a C-only package, both `PKG_LIBS = -lgfortran -lquadmath`,
  installed from fresh copies and loaded: under pixi, under `env -i`
  with the tree alone (PATH = env bin:/usr/bin:/bin, no
  R_ZIG_EXTRA_ENV), from the extracted bundle, and with
  `USE_FC_TO_LINK` (the link through zig-fc). The Fortran .so: 0
  undefined `_Fortran*` symbols, NEEDED glibc's only, no rpath except
  the pixi env's under pixi (R_ZIG_EXTRA_ENV's rule). The C-only package
  also installs and loads with no flang anywhere (make, /usr/bin, /bin).
  A copy of the tree with 192ee86's rzig: every one of these links
  fails ("unable to find dynamic system library 'gfortran'"; tree alone
  also 'quadmath').

win-64 (kappa), tester, a copy of the worktree (its 12 changed source
files byte-identical to the worktree's at the end), pixi 0.81.0:
- install, rzig-test (32 passed, 14 skipped: the tests with shell-script
  stand-ins, the new D4 ones among them; printArgv and the
  -lsynchronization test ran), build (7 min), verify-tree (the new line:
  "Tcl/Tk runtime verified: ... Makeconf's TCL_VERSION = 86t"), smoke,
  contract and verify-package: all exit 0.
- D5: tkrplot 0.0-32 from CRAN source with the tree's R under pixi
  links with `-ltcl86t -ltk86t`, imports tcl86t.dll and tk86t.dll,
  passes R's test load; `library(tkrplot)` loads with Tcl 8.6 and
  `tkrplot()` draws. Controls: `MAKEFLAGS=TCL_VERSION=86` fails on
  'tcl86'; verify-tree on a copy of the tree with `TCL_VERSION = 86`
  fails naming Tcl/bin/tcl86.dll and tk86.dll. With R_ZIG_EXTRA_ENV
  unset: 'tk.h' not found (the follow-up below).
- D4: the same two packages (Makevars.win), installed from clean copies
  with `--preclean`, load and return 42 with no gfortran on PATH, with a
  stub gfortran first on PATH that records every run (it never ran), and
  with conda-forge's gfortran 15.2 first on PATH (kappa has no Rtools).
  No DLL imports anything of gfortran's or quadmath's. Link level, a
  flang object through the tree's gcc.exe: `-lgfortran -lquadmath`,
  with `-lc++`, `-lgfortran` alone, `-lquadmath` alone and FLIBS all
  link and load; 192ee86's rzig as the control in "Before" above.
- D6: the tree's gcc.exe links wait.c with `-lsynchronization` under
  conda-forge's zig and under upstream zig (ZIG_BIN = fetch-zig's
  zig.exe); both programs print "WaitOnAddress 1" and import the three
  functions from api-ms-win-core-synch-l1-2-0.dll. 192ee86's rzig with
  upstream zig: "unable to find dynamic system library
  'synchronization'"; with conda-forge's zig it links.
- E4 under cmd: as above.

osx-arm64 (omicron, macOS 26.4), tester, a copy of the worktree, pixi
0.81.0:
- install, rzig-test (46/46; the parity test is linux-only by design),
  fetch, build (1m46s), verify-tree, smoke, contract (static libc++ in
  every package, minos <= 13.0) and verify-package: all passed.
- D4: the two packages (Makevars) install and load, under pixi and
  under `env -i` (PATH=/usr/bin:/bin); load commands libR and libSystem
  only; 110 flang runtime symbols defined in the Fortran package's .so,
  0 in the C one's. rzig's argv for `-dynamiclib -o x.so a.o -lgfortran
  -lquadmath -lflang_rt.runtime`: none of the three flags left, one
  archive (<env>/lib/clang/23/lib/darwin/libflang_rt.runtime.a) where
  -lgfortran was. A copy of the tree with 192ee86's rzig (built arm64):
  both installs fail on 'gfortran' and 'quadmath'.
- E4: as above.

Review (2026-10-08): the diff against the four answers; zig 0.16's
`File.writerStreaming` (Writer.initStreaming, `.mode = .streaming`:
writeStreaming, no offset; rzig's warnings already go through
std.debug.print's stderr writer, which is streaming too, and printArgv
is rzig's only stdout writer); D4's rule with -L directories before the
flags, static and shared runtimes (the archive by its path, so a
libflang_rt.runtime.so or .dylib beside it is never picked), repeated
and mixed flags (zig-fc's appended FLIBS included), compile-only calls,
the two-argument and `-Wl,` forms, and the shims' `" $* "` trigger
against `anyWord`; every place TCL_VERSION and tcl86 appear (above);
D6 with both zigs, caching and parallel links (nothing of rzig's). The
testers' claims match their logs. Fixed at review: comments
(flang_rt.zig's header measured macOS; main.zig's printArgv names
Windows' file pointer; windows.zig's evidence names kappa; the recipe's
build-number comment) and this record. No code change. After those
edits, on linux-64: `zig fmt --check` clean, and `pixi run --locked
rzig-test` passes with the same numbers (46/46; 50, 31, 17, 0 failed).

After the review (2026-10-08): the warning rzig prints when flang has
no runtime archive now says it drops "-lflang_rt.runtime, -lgfortran
and -lquadmath", since either of the other two can trigger it
(flang_rt.zig, its unit test, toolchain/zig-cc and zig-cxx, so parity
holds). linux-64 `pixi run --locked rzig-test` passes again: parity 50
identical, 31 identical but for rzig's own -L, 17 deliberate, 0 failed.
Not re-run on kappa and omicron (a message text only).

Review of T1 (2026-10-08), on 3ea083c: the header set, read from the
win-64 tk's 28 headers' own `#include` lines. tcl.h, tk.h and
tkPlatDecls.h pull in exactly the 13, and none of the 13 includes a
Tcl, Tk or X11 header outside them. tclOO.h, tclTomMath.h, itcl.h and
tdbc.h are separate entry points that nothing shipped includes. The
package's sha256 matches the lock's. None of its 28 headers has a
prefix placeholder or names a path. The new code runs only where
prefix_is_env is false, so the conda build is unchanged. The R sources
cited for CRAN's layout match R 4.6.1's (Makefile.win's
`-I "$(TCL_HOME)"/include`; the installer's `$(CP) -pRf .../Tcl` at
154 and 161 and `$(RM) $(RPREFIX)/Tcl*/lib/*.lib` at 163). kappa's
claims match its logs, as recorded in "Tests (T1)". Fixed at review:
comments in build.zig and verify-tree.sh, and this record. The
standalone plan's T1 record was applied, with the PyPI line corrected
and kappa's result added. No code change.

## Not tested

- osx-64 and linux-aarch64 on a host. CI (build.yaml) ran on 3ea083c
  (PR #19, run 37844621816, the core tier). At the T1 review every
  finished leg had passed: windows-latest, ubuntu-latest (default and
  minimal), ubuntu-24.04-arm, macos-latest, macos-15-intel, and
  conda-package for linux-64, linux-aarch64, osx-64 and osx-arm64.
  conda-package / win-64 was still running. The review read only the
  Windows leg's log.
- A whole R build, or the D4, D5 and E4 checks, with upstream zig: only
  D6 used it (kappa).
- The full, minimal and openblas variants on any host (slim only); the
  openblas environment's libgfortran case was measured by the
  implementer alone (linux-64, as R_ZIG_EXTRA_ENV).
- A real Rtools gfortran on PATH (conda-forge's gfortran 15.2 and a stub
  stood in on kappa).
- A Rust-based CRAN package naming `-lsynchronization` (only wait.c).
- T1: tkrplot with upstream zig (kappa used the env's conda-forge zig
  through ZIG_BIN), and tkrplot in a conda env with r-zig-slim. A
  package that includes one of the 15 headers T1 leaves out (tclOO.h,
  X11/cursorfont.h, ...) does not compile from the tree alone, by
  design.
- The recipe's build number through rattler-build on a host (CI's
  conda-package legs above aside). verify-tree's TCL_VERSION and
  Tcl/include checks run on standalone Windows trees only, not on the
  conda package's.
- On macOS, `-lgfortran` with no flang on PATH (the drop): unit tests
  only.
- `pixi run check` and hermetic on a host (CI's windows-latest leg ran
  both on 3ea083c).

## Follow-ups (not on this branch)

- T1 (2026-10-08) is answered and done on this branch: Tcl/Tk's
  headers in R_HOME/Tcl/include, and its record in
  feat-standalone-toolchain PLAN.md (D5). If a package needs one of the
  15 headers left out, add it to installEnvRuntime's list, or ship all
  28, as CRAN's installer copies its whole R_HOME/Tcl.
- Windows' `-lc++` for a C link that pulls flang's runtime with
  `-lgfortran` and no FLIBS: only if a case shows up (D4 above).
- zig-fc's own flang-driver commands still pass `-lgfortran` and
  `-lquadmath` to flang (D4's "Not covered").
- Leftovers on the hosts, safe to delete, left for the user: kappa's
  default zig cache, C:\Users\admin\AppData\Local\zig (about 105 MB
  added by a first test run that had no private ZIG_GLOBAL_CACHE_DIR;
  shared with other zig users there; T1's kappa tester reported it
  absent on 2026-10-08, before and after its runs), and omicron's
  ~/.cache/r-zig/zig-lib-4120825996 (the libc++ mirror for a deleted
  env's zig lib dir: symlinks only).
