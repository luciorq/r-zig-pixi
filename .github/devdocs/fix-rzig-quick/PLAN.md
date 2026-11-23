# fix-rzig-quick

## Goal

Small rzig fixes from chore-release-12's BACKLOG.md (Q1, Q7, Q8, Q9, M-1,
M-2, Q24, Q25, M-15's decision), each recorded with its evidence.

## Decisions (defaults, user-approved batch, 2026-11-23)

| # | question | chosen | reason |
|---|----------|--------|--------|
| D1 | Q7: drop `-c` when `-S` is given? | no code change | the `-c` is zig's own (I2): rzig cannot drop it; 42cba99's `-Wno-unused-command-line-argument` with `-S` already fixes it |
| D2 | Q8: where to refuse a src/Makefile package under R_ZIG_PKG_BUILDER=zig | rzig's `--rzig-check=package` (check.zig), exit 1 and a reason line | install.R runs src/Makefile with make before the 0013 hook can refuse; the preflight (0009) runs first and stops on exit 1. Only src/Makefile*: other make cases reach the hook, which refuses them (no early refusal from inputs that differ from the hook's). No patch change |
| D3 | Q9: drop or keep `-lgfortran -lquadmath` on flang's commands | drop them, and `-lflang_rt.runtime`, from every flang command (compile, probe, split compile) | flang never links under zig-fc; the words only warn (I3); the zig link still resolves them (flang_rt.zig) |
| D4 | M-1: scope of `-D__STDC_WANT_IEC_60559_TYPES_EXT__` | every Windows zig command of rzig (C and C++), right after `-target` | same MinGW header order in C++ (I4); link line and a `#define ... 1` in the source are silent (I4) |
| D5 | M-2 (rstan's C++ standard) | not rzig's job: defer to test-stress-rows | make orders the flags the same way (I6); rzig must not reorder a caller's -std |
| D6 | Q24 `-Wl,-lstdc++`: rewrite or document | rewrite: any `-l` inside `-Wl,`/`-Xlinker` (`-l<n>`, `-l <n>`, `--library[=]<n>`) becomes the driver's `-l<n>` in place (linker_args.zig) | zig refuses every such `-l` (I7), so it never linked; the later rules (libstdc++, flang runtime, Windows import libs) then apply. ld64's `-lto_library`/`-lazy*` stay. Shims not changed (parity has no such case) |
| D7 | Q24 libc++ archive in a linux package | document only | links silently, fails at load (I9); detection would need symbol scanning of inputs, more than this batch |
| D8 | Q25 un-skip Windows tests | none un-skipped; two skips got their missing reason comment | all 29 need sh stand-ins, symlinks or a file-as-directory (A1); un-skipping needs native stand-ins and a Windows host |
| D9 | M-15: the Windows Rust `-lunwind` rule (O-A3) | (a) take it: windows.zig adds `-lunwind` to Windows C image links (-shared or exe) through gcc.exe; implement with M-15's gifski stress row, which tests it | matches MinGW gcc's default libgcc_eh on a C link; archive, so nothing is pulled unless `_Unwind_*` is referenced; measured fix (`SHLIB_LIBADD = -lunwind`, kappa 2026-10-15, feat-standalone-toolchain PLAN.md:4880-4892). Not taken: (b) leave it to packages |

## Findings

- I1 (V) Q1: `zig fmt --check zigbuild/` listed rspec.zig and
  tools/rzig/makefile.zig; after `zig fmt` both zigs (conda-forge 0.17.1,
  PyPI 0.17.1) report it clean (delta).
- I2 (V) Q7: delta, both zigs, `zig cc -target x86_64-linux-gnu -Werror
  -S s.c` and `-c -S`: rc=1, "argument unused during compilation: '-c'"
  for a plain `-S` too, so zig adds the -c; with
  `-Wno-unused-command-line-argument` both rc=0 and write the assembly.
  rzig adds that flag with -S since 42cba99 (compiler.zig argv; unit test
  `pre_s`).
- I3 (V) Q9: delta, conda flang 23: `flang -c a.f -o a.o -lgfortran
  -lquadmath` warns "-lgfortran: 'linker' input unused" for both. With
  the new rzig (scratch tree) `zig-fc -c a.f -o fa.o -lgfortran
  -lquadmath`: rc=0, no warning.
- I4 (V) M-1: delta, both zigs, snippet `#include <float.h>` + FLT16_MAX:
  x86_64- and aarch64-windows-gnu (and x86_64-linux-gnu) "use of
  undeclared identifier 'FLT16_MAX'" without the define, compiles with
  it; C++ (`<cfloat>`) the same. A link line with the define and -Werror
  links (rc=0); a source's `#define __STDC_WANT_IEC_60559_TYPES_EXT__ 1`
  with -Werror: rc=0; an empty `#define` only warns -Wmacro-redefined.
  Rhdf5lib's report: stress/packages.tsv Rhdf5lib row (K9).
- I5 (V) Q8: scratch tree with the new rzig, package with src/Makefile:
  `R_ZIG_PKG_BUILDER=zig zig-cc --rzig-check=package` → "zig-cc: mk
  needs make: src/Makefile, which R runs with make, and
  R_ZIG_PKG_BUILDER is 'zig'", rc=1; unset → "package ok: mk needs make
  (src/Makefile); ...", rc=0.
- I6 (A) M-2: rstan 2.32.7 R/plugin.R:63 puts ` -std=c++1y` in
  PKG_CPPFLAGS on Windows; R's compile rule is `$(CXX) $(ALL_CPPFLAGS)
  $(ALL_CXXFLAGS)` with CXX = `$(CXX17) $(CXX17STD)`, so make's command
  also ends with -std=c++1y after -std=gnu++17, and libstdc++ and libc++
  both define `std::is_same_v` for C++17 only. The failure is rstan
  2.32.7 with StanHeaders 2.39.1, not rzig; its fix (CXX17FLAGS +=
  -std=gnu++17, or a matching StanHeaders) belongs in the stress row.
  The other half (`bin/Rscript`) is not in this batch.
- I7 (V) Q24: delta, both zigs: `zig cc -shared ... -Wl,-lm`,
  `-Wl,-lm,-lc` and `-Xlinker -lm` all fail "error: unsupported linker
  arg: -lm"; main's tree: `zig-cc`/`zig-cxx ... -Wl,-lstdc++` fail the
  same way. New rzig: `zig-cc -shared -o n1.so main.o part.o
  -Wl,-lstdc++` rc=0, NEEDED libstdc++.so.6, libgcc_s.so.1, libc.so.6;
  `-Xlinker -lm` rc=0.
- I8 (V) Q24: CMake 4.5.1 + Ninja (pixi exec), main's tree, C target
  (LINKER_LANGUAGE C, shared and exe) linking a C++ static library through
  CMAKE_C_COMPILER=zig-cc: configure ok, build ok, exe prints 5 and
  exits 0. CMAKE_CXX_IMPLICIT_LINK_LIBRARIES = T/lib/libstdc++.so.6;
  T/lib/libgcc_s.so.1; zig-cache libunwind.a; libm/libc/...; CMake adds
  only libstdc++.so.6 and libgcc_s.so.1 to the C link (libunwind.a is in
  C's implicit list too, so CMake leaves it off); the .so's NEEDED
  libstdc++.so.6, libgcc_s.so.1, libc.so.6. Needs R_ZIG_EXTRA_ENV (the
  slim tree alone has no libstdc++ headers: zig-cxx stops with the
  compilers group's text).
- I9 (V) Q24: an archive built with raw `zig c++` (libc++, std::__1)
  linked into a .so by zig-cxx (or zig-cc): link rc=0, NEEDED
  libstdc++.so.6; loading it: "undefined symbol:
  _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev".
  Such a package fails at load, not at link (a prebuilt libc++ archive
  inside a linux package is unsupported since feat-linux-libstdcxx).
- A1 (A) Q25: the 29 tests that return error.SkipZigTest on Windows
  (grep SkipZigTest, zigbuild/tools/rzig/*.zig): shell-script stand-ins
  for zig/flang/gfortran/python3/xcrun/make (check.zig 535, 585, 617,
  727, 782, 973, 1078; compiler.zig 895, 936; darwin.zig 88;
  find_zig.zig 111, 200; flang_rt.zig 234, 250, 272, 301, 314;
  fortran.zig 735, 776, 799; pkgbuild.zig 1134, 1226; main.zig 655,
  /bin/sh), symlinks (flang_rt.zig 352; libcxx_mirror.zig 199, 228, 251,
  268: the mirror is unix-only), a file as a directory (archives.zig
  300). None can run on Windows as written.
- I10 (V) review, Q24: the first rewrite moved every `-l` out of a
  `-Wl,` ahead of the options kept there, so
  `-Wl,--whole-archive,-lfoo,--no-whole-archive` became `-lfoo
  -Wl,--whole-archive,--no-whole-archive`: zig applies -Wl,'s
  --whole-archive/-Bstatic to the -l after them, so the archive's
  unreferenced object was silently dropped (delta, conda zig 0.17.1,
  raw zig: in-order form exports `unref_sym`, moved form does not).
  Fixed: wl() flushes the options before each -l as their own `-Wl,`
  (linker_args.zig `flush`, two more assertions). This branch's rzig as
  zig-cc in a scratch tree, both zigs: `-Wl,--whole-archive,-lfoo,
  --no-whole-archive` rc=0, `unref_sym` exported; `-Wl,-lfoo` rc=0,
  not exported.

## Changes

- zigbuild/rspec.zig, zigbuild/tools/rzig/makefile.zig: zig fmt (Q1).
- check.zig: R_ZIG_PKG_BUILDER=zig refuses src/Makefile*, test (Q8);
  pkgplan.zig: `Planner.srcMakefile`, shared with classify.
- fortran.zig: `runtime_libs` off every flang command; tests (Q9).
- windows.zig `iec_60559_types`, compiler.zig: on every Windows
  command; tests updated; parity-test.sh's drop_wintarget drops it (M-1).
- linker_args.zig: -l out of -Wl,/-Xlinker; test; libstdcxx.zig comment
  (Q24).
- flang_rt.zig: two skip reasons (Q25).

## Tests

- delta, `pixi run bash zigbuild/tools/rzig/test.sh` (unit tests, parity,
  link-objects) from ~/rz/base's env, conda-forge zig 0.17.1 and PyPI
  ziglang 0.17.1 (ZIG_BIN): before (main 3395a08) 226/226 unit tests,
  parity 109 + 77 + 33, 0 failed, link-objects ok, both zigs; after
  228/228, parity the same 109 + 77 + 33, 0 failed, link-objects ok,
  both zigs. Logs: delta ~/rz/scratch/rzq/{before,after}-{conda,upstream}.log.
- delta: `zig fmt --check zigbuild/` clean with both zigs.
- delta, after the review fix (I10), run.sh: 228/228 unit tests, parity
  109 + 77 + 33, 0 failed, link-objects ok, EXIT=0, both zigs
  (~/rz/scratch/rzq/rev-{conda,upstream}.log); fmt clean, both zigs.
- delta: scratch copy of ~/rz/base/dist/slim/R-4.6.2-zig with this
  branch's rzig: I3, I5, I7.

## Not verified

- M-1 on Windows (kappa, windows-11-arm): Rhdf5lib itself not built;
  only the cross-compile snippet (I4) and unit tests.
- Q8 through R CMD INSTALL (0009's stop text); a user Makevars or
  R_ZIG_NO_PREFLIGHT skips the preflight, and then a src/Makefile
  package still runs make under R_ZIG_PKG_BUILDER=zig (an install.R
  guard would need a patch to both branches of patch 0013).
- Q24's rewrite on macOS and Windows (unit tests only).
- Q25: no Windows host run.

## Backlog items closed

Q1, Q7 (by 42cba99, recorded), Q8 (preflight path), Q9, M-1 (rzig side;
Windows host check open), Q24 (probes recorded, -Wl,-l fixed), Q25
(listed), M-15 (decision D9 only). M-2: deferred to test-stress-rows
(D5).
