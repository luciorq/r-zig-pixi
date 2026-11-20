# feat-linux-libstdcxx — libstdc++ for all C++ on linux

chore-release-11 finding 31 and .github/devdocs/CXX-STDLIB.md decision 3.
Branch feat-linux-libstdcxx, from main d65f1db. Every C++ compile and
link rzig does on linux (x86_64 and aarch64) uses gcc's libstdc++, in
every distribution: the pixi envs (default, full, minimal, openblas),
the conda packages, the standalone archives and the wheel. macOS and
Windows keep zig's libc++. Recipe build number 12 (L12). Nothing is
committed; the user runs commits and pull requests.

## Decisions

Each entry: the question, the options, the choice, the reason, who
decided and when. "Default chosen by Claude; user may revisit" means
the user gave no choice for that point. The user's direction for this
branch, 2026-11-18, after release 11: "Fix and implement all of it! No
upstream reporting.", then "Document well all our decisions." and "and
findings".

L1. Which C++ standard library on each platform?
- Options: (a) libstdc++ on linux, libc++ on macOS and Windows; (b)
  rebuild the C++ libraries with zig and libc++; (c) conda-forge's
  prebuilt r-* packages; (d) accept the boundary.
- Choice: (a).
- Reason: R packages reuse the C++ libraries conda-forge and the distros
  ship. (b) makes r-zig own every rebuild and drops GDAL drivers; (c)
  has no R 4.6 builds; (d) leaves sf and terra broken on linux.
- Who: the user, 2026-11-16 (CXX-STDLIB.md decision 1).

L2. Per package or for all C++ on linux?
- Options: (a) all C++ on linux; (b) per package, chosen by rzig at link
  time.
- Choice: (a).
- Reason: Rcpp and cpp11 packages pass C++ objects across .so files at
  run time. A libstdc++ package beside a libc++ Rcpp gives 'double
  free'; the reverse gives 'irrecoverable exception'. (b) makes results
  depend on install order.
- Who: the user, 2026-11-16 (CXX-STDLIB.md decision 2).

L3. When and where?
- Options: now, on its own branch; later.
- Choice: now, on feat-linux-libstdcxx from main d65f1db.
- Reason: release 11 was published that day; the branch keeps the
  change out of the release (one change, its own PR).
- Who: the user, 2026-11-18 ("Fix and implement all of it!").

L4. How do the standalone tree and the wheel get libstdc++?
- Options: (a) one mode: ship the headers, use the runtime in R's tree;
  (b) keep libc++ there (a second mode); (c) use the host's or an env's
  headers when present.
- Choice: (a).
- Reason: one mode on every linux distribution. libstdc++ is backward
  compatible, so the newest runtime also runs distro libraries built
  with an older gcc. The 2026-11-16 record leaned to (a); the menu got
  no answer.
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L5. Which group carries libstdc++'s headers?
- Options: (a) the compilers group: conda's r-zig-compilers (run deps
  libstdcxx-devel_linux-*), the standalone compilers archive
  (toolchain/libstdcxx), the r-zig-compilers wheel [implemented]; (b)
  the base: the r-zig wheel and r-zig-slim (+ about 3 MiB compressed),
  so C++ works with ziglang alone; (c) another layout.
- Choice: (a). The two shim headers stay in the base, beside rzig.
- Reason: the headers are only needed to compile, like zig and flang;
  the base stays small.
- Consequence: on linux, r-zig plus ziglang alone (without
  r-zig-compilers) compiles C but no longer C++. It did before this
  branch. A C++ package stops in the install preflight with the
  compilers group's text. wheel-test.sh tests this.
- Who: default chosen by Claude; user may revisit. 2026-11-18. The
  review (finding R2) asked for a menu; this record replaces it.

L6. How does every variant load R's libstdc++ first?
- Options: (a) rely on ICU loading it (slim and full only); (b)
  etc/ldpaths; (c) libR.so needs libstdc++.so.6 and libgcc_s.so.1
  (DT_NEEDED).
- Choice: (c), on linux, in every variant.
- Reason: minimal, the standalone tree and the wheel otherwise bind the
  host's libstdc++, which can be older than the headers (packages need
  GLIBCXX_3.4.32; Ubuntu 22.04 has 3.4.30). Finding 8. (b) only acts
  where R's shell front end sources etc/ldpaths. An embedder that loads
  libR directly (rpy2, the wheel's r_zig.r_home()) does not read it,
  and (b) would add a second mechanism next to libR's RUNPATH. (a)
  covers slim and full only. (Claude's reading; the probe did not test
  (b).)
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L7. Which runtime do C++ links name, and what happens to the caller's
runtime flags?
- Options: (a) R's runtime (lib/libstdc++.so.6, lib/libgcc_s.so.1) by
  path; (b) the devel package's libstdc++.so.6.0.34 copy; (c) leave the
  flags to zig.
- Choice: (a). rzig rewrites -lstdc++ (and -l:libstdc++.so*) to both
  paths, libgcc_s once; -lgcc_s to its path; -lstdc++fs and -lstdc++exp
  to gcc's archives beside the headers, or nothing.
- Reason: zig maps -lstdc++ to its libc++ and drops -lgcc_s (finding
  5). Symbol versions follow the headers, so the newer runtime is safe
  (finding 10), and the tree needs only the headers, not the 21 MB
  devel copy.
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L8. How are libstdc++'s headers marked as system headers?
- Options: (a) 131 --system-header-prefix flags (the first probe); (b)
  -D_GLIBCXX_SYSHDR.
- Choice: (b).
- Reason: same effect (0 warnings in the -Wall -Wextra -pedantic test
  file, 146 without), one flag. Finding 2.
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L9. What happens when the headers are missing?
- Options: (a) stop and name the compilers group; (b) fall back to
  libc++.
- Choice: (a). A compile exits 127 with the compilers group's text; the
  install preflight stops a C++ package before configure.
- Reason: L2 (mixing standard libraries crashes).
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L10. arrow on linux.
- Options: (a) let arrow take its prebuilt libstdc++ libarrow when its
  allowlist matches; (b) force the source build.
- Choice: (a). LIBARROW_BINARY=false keeps the source build (the
  arrow:source row).
- Reason: that is arrow's normal gcc path on linux. Finding 13.
- Who: default chosen by Claude; user may revisit. 2026-11-18.

L11. How does the toolchain build find the headers' version?
- Options: (a) a pinned constant gcc_version = "15.3.0"; (b) the
  package's conda-meta record.
- Choice: (b).
- Reason: a lock bump to 15.4 must not break the build.
- Who: default chosen by Claude after the probe review; user may
  revisit. 2026-11-18.

L12. Recipe build number.
- Options: (a) 12; (b) stay at 11.
- Choice: (a), 11 → 12 (recipe/recipe.yaml).
- Reason: build 11 was published on 2026-11-18 (build.yaml run
  44336177906; chore-release-11/PLAN.md "Released"). The implementer
  first kept 11, on the claim that 11 was unpublished; that claim was
  wrong.
- Who: default chosen by Claude under the user's standing rule
  (2026-11-10: may update pixi.lock and bump build numbers when needed);
  user may revisit. 2026-11-18. The release is a separate step.

L13. Report upstream (zig, conda-forge)?
- Options: (a) report upstream (zig: -lstdc++ mapped to libc++,
  -lgcc_s dropped, --as-needed dropping libR's runtime; conda-forge:
  libstdcxx-devel ships no info/licenses); (b) no.
- Choice: (b).
- Reason: the user's direction.
- Who: the user, 2026-11-18 ("No upstream reporting.").

Decisions made during the implementation (all: default chosen by
Claude; user may revisit; 2026-11-18):

L14. How does libR get DT_NEEDED on the runtime? zig links shared
libraries with --as-needed and drops a library nothing references.
- Options tried (next/impl-libstdcxx/asneeded): (a) the two runtime
  paths as positional link inputs; (b) linkSystemLibrary(":libstdc++.so.6",
  .needed) and ":libgcc_s.so.1" (x.so: no NEEDED); (c)
  --force_undefined on a runtime symbol; (d) a hidden reference
  (ref2.zig, ref3.zig: garbage collected with its references); (e) an
  exported reference, `R_zig_cxx_runtime` (zigbuild/cxx_runtime.zig);
  (f) post-process libR (patchelf --add-needed).
- Choice: (e). build.zig's linkCxxRuntime links both paths and the
  object.
- Reason: (a)-(d) leave no NEEDED. (f) goes against the
  no-post-processing rule (simplicity first).
- Cost: libR exports one more symbol on linux.

L15. -static-libstdc++ on linux.
- Options: (a) drop it, a note under RZIG_TRACE only; (b) drop it with
  a one-line note on stderr on every link.
- Choice: (a).
- Reason: zig ignores it too (the output still needs libstdc++.so.6),
  and a note on every link would reach configure and CMake checks that
  read stderr. Review finding R7 asked for a notice or a record; this
  is the record.

L16. The rule the checks use for a linux C++ library (verify-helpers.sh
stdcxx_wrong).
- Options: (a) always require NEEDED libstdc++.so.6; (b) require it
  only when the object calls into the runtime (an undefined std:: or
  C++ ABI symbol, or one versioned GLIBCXX_/CXXABI_); (c) keep (a) and
  require test files to call the runtime.
- Choice: (b). Always: no NEEDED libc++, no undefined std::__1 symbol.
  glibc's own symbols do not count: anything versioned GLIBC_, and
  __cxa_finalize, __cxa_atexit and __cxa_thread_atexit_impl (finding
  58).
- Reason: zig's --as-needed gives correct C++ code that never calls the
  runtime no NEEDED (finding 37); (a) would fail it with a misleading
  message (review finding R3).

L17. One place for the rule.
- Options: (a) one helper in verify-helpers.sh, sourced by
  contract-test.sh and smoke-test.sh; (b) the rule written in each
  script (as implemented first, five places).
- Choice: (a). verify-helpers.sh holds cxx_deps ("a shared C++ runtime this
  OS must not need": libc++ on linux, any on macOS and Windows),
  libcxx_deps, elf_needed, elf_undefined, stdcxx_wrong and
  cxx_runtime_wrong. contract-test.sh and smoke-test.sh source it. The
  recipe's R tests repeat the rule in R (they run without the scripts).
- Reason: review finding R4.

L18. contract's no-make run on the base.
- Options: (a) R_ZIG_EXTRA_ENV = the whole pixi env; (b) a directory
  with only lib/gcc (a link to the env's), so rzig finds the headers and
  nothing else.
- Choice: (b).
- Reason: (a) adds the env's -I, -L and an rpath and hides a package
  that reaches into the env (review finding R5).

L19. The cross-library std::string check (Rcpp's demangle) runs on
linux only.
- Options: (a) linux only; (b) every OS.
- Choice: (a).
- Reason: on macOS and Windows each .so has its own static libc++, so
  that crossing is not this test's (review finding R6). The exception
  check runs on every OS.

L20. Test code calls Rf_error with no C++ object alive (the message is
copied to a char buffer first).
- Options: (a) copy the message to a char buffer and call Rf_error
  with no C++ object alive; (b) Rf_error with the std::string alive.
- Choice: (a).
- Reason: Rf_error longjmps; a live std::string's destructor is skipped,
  and on Windows SEH makes it fragile (review finding R10).

L21. The two-argument `-l stdc++` is rewritten like `-lstdc++`.
`-Wl,-lstdc++` is not: lld then searches -L for libstdc++.so (R's env
has it). Recorded as a known gap (review finding R7).
- Options: (a) rewrite both forms; (b) rewrite `-l stdc++` and record
  `-Wl,-lstdc++` as a gap.
- Choice: (b).
- Reason: -Wl, arguments go to lld unchanged; rewriting inside them
  would mean parsing linker options.

L22. On a C link, -lstdc++ brings libgcc_s once.
- Options: (a) add libgcc_s once with -lstdc++ on any link; (b) only on
  C++ links.
- Choice: (a).
- Reason: without libgcc_s, zig cc links its own libunwind.a and a
  throw aborts (finding 16).

L23. A command with no input (--version, -dumpversion, -print-*) gets
no libstdc++ flags and needs no headers; standard input (-) counts as
an input.
- Options: (a) no flags and no headers needed for a command with no
  input; (b) always add them (the probe).
- Choice: (a).
- Reason: finding 17.

L24. The toolchain tree's libstdcxx/ group is linux only, its package
chosen by the host's arch (libstdcxx-devel_linux-64 or _aarch64). macOS
and Windows have no libstdcxx/ (verify-toolchain.sh checks both).
- Options: (a) linux-only Dir chosen by host arch; (b) a shared unix
  Dir.
- Choice: (a).
- Reason: macOS must not gain an empty libstdcxx/ (probe review).

L25. stress/packages.tsv: the six rows flip to linux=ok on linux-64
evidence, with "linux-64 only; linux-aarch64 not run" in each note.
- Options: (a) a note; (b) a per-arch key.
- Choice: (a).
- Reason: `linux=` covers aarch64 too; nothing ran there (review
  finding R9).

L26. gcc's licence texts (COPYING3, COPYING.RUNTIME from the gcc 15.3.0
tarball, sha256 matching the conda recipe's) go with the headers:
zigbuild/toolchain/licenses/libstdcxx-devel_linux-{64,aarch64} and the
r-zig-compilers wheel. The conda package ships no info/licenses.
- Options: (a) gcc 15.3.0's texts, checked against the recipe's sha256;
  (b) none (the package ships none).
- Choice: (a).
- Reason: the headers are GPL-3.0 WITH GCC-exception-3.1;
  licenses/README.md requires texts when info/licenses is missing.

L27. stress/packages.tsv: arrow's heavy@linux tag, now that linux takes
the prebuilt libarrow (1.27 min in the stress tree leg, finding 33).
- Options: (a) keep heavy@linux; (b) drop it.
- Choice: (a).
- Reason: one linux-64 run, before the review fixes; linux-aarch64 not
  run. The arrow row's note says the tag stays until the user decides.
- Who: default chosen by Claude; user may revisit. 2026-11-18 (records
  audit).

L28. stress/packages.tsv: the six rows of L25 now say "linux-64 and
linux-aarch64, tree and conda: ok (stress 44438790229, 2026-11-19)" in
place of "linux-64 only; linux-aarch64 not run". The arrow row's
"linux-aarch64's binary not checked" now records the linux-arm64
download (finding 66).
- Options: (a) rewrite the notes; (b) keep them and add a new note.
- Choice: (a).
- Reason: stress run 44438790229 ran every row on both arches, both legs
  (finding 65); the old text would be wrong.
- Who: Claude, in the workflow step that recorded PR #49's CI.
  2026-11-19.

- L29. Merge before the upstream-zig gate ran.
  Options: (a) add the 'upstream-zig' label on #49 and merge after
  its runs; (b) merge #49 now and run the gate on #50 after main is
  merged into feat-winarm-gaps.
  Choice: (b). The user merged #49 as 2674ab4 (main f668295) on
  2026-11-19, before its upstream-zig runs; these CI and stress
  results then came to main through #50's branch.
  Reason: #50 still needed its full-ci and upstream-zig runs; on the
  merged tree, one set of runs checks both branches with both zigs.
  Who: user (merge, "merge 50 together with the script"); the gate on
  #50 proposed by Claude. Date: 2026-11-19.

## Findings

Each finding: the fact, its evidence, the date, and what is not
verified. 1-15 are the probe's F1-F15 (probe-libstdcxx, 2026-11-18;
scratch /data/gamma/luciorq/workspaces/temp/r-zig-pixi/next/probe-libstdcxx,
README.txt and logs/). 16-32 come from the probe's review, 33-45 from
the implementation, 46-56 from the implementation review and how each
was resolved, 57-60 from the final pass, 61-63 from the records
audit, 64 onward from PR #49's CI (GitHub-hosted, 2026-11-19). 1-63 on
gamma (linux-64, Ubuntu 24.04), 2026-11-18, unless said otherwise.

Probe:

1. The working flags (F1), x86_64, both zigs (conda-forge and PyPI
   ziglang 0.17.1). G = <root>/lib/gcc/x86_64-conda-linux-gnu/15.3.0.
   Compile: -nostdinc++ before the caller's arguments; after them and
   after the environments' -I: -I<rzig dir>/libstdcxx-shim
   -I$G/include/c++ -I$G/include/c++/<triple> -I$G/include/c++/backward
   -D_GLIBCXX_SYSHDR. Link: -nostdlib++ before, then <R env>/lib/libstdc++.so.6
   and lib/libgcc_s.so.1 by path (DT_NEEDED is the soname). Evidence:
   a.cpp (iostream, regex, format, filesystem, thread, cmath isinf)
   compiles with -Werror -Wall -Wextra and runs; it needs GLIBCXX_3.4.32
   at most, GLIBC 2.17 at most, and _Unwind_Resume@GCC_3.0 from libgcc_s.
2. -D_GLIBCXX_SYSHDR replaces the 131 --system-header-prefix flags (F2).
   Every libstdc++ 15 header has '#pragma GCC system_header' under
   '#ifdef _GLIBCXX_SYSHDR'. Warnings in the -Wall -Wextra -pedantic
   test file: 146 without, 0 with. Install logs: 0 warnings from
   include/c++ for Rcpp, magick, terra, arrow and their dependencies;
   the 275 warnings in the sf/protolite/gdalraster/V8 log all come from
   s2's bundled abseil. Decision L8.
3. Both shims are still needed with zig 0.17.1 (F3). Without the
   c++config.h shim, <cmath> fails for C++11, 17 and 20 ('no member
   named isinf in the global namespace'): libstdc++'s c++config.h
   defines _GLIBCXX_HAVE_OBSOLETE_ISINF and _ISNAN (aarch64's too,
   lines 1253 and 1256). conda-forge's own zig wrapper (zig_linux-64,
   share/zig/cxx-overlay) ships only the single_threaded.h shim.
4. -isystem and -cxx-isystem fail (F4): zig passes its libc directories
   as -isystem first, and libstdc++'s '#include_next <stdlib.h>' then
   finds no stdlib.h. -I is required, inside rzig, not in user flags.
5. zig and the runtime flags (F5): with -nostdlib++, zig swallows
   -lstdc++ ('undefined symbol: std::cout'); it drops -lgcc_s; it
   ignores -static-libstdc++ (the output still needs libstdc++.so.6).
   Decision L7.
6. Where rzig builds argv (F6): compiler.zig argv(); the libstdc++ hook
   goes after envFlags, pre flags before the caller's arguments, post
   flags after them and before link_last.
7. Interactions (F7): -std unchanged; -fopenmp links NEEDED libomp.so
   and libstdc++.so.6 and loads; dso_fini.o is still needed (library and
   unloadNamespace exit 0); R CMD config CXX stays 'zig-cxx -std=gnu++20'
   (config-parity unaffected); a CMake project through zig-cxx builds
   with 0 warnings and a throw across its .so is caught;
   CMAKE_CXX_IMPLICIT_LINK_LIBRARIES still lists zig's cache libunwind.a.
   Not verified: a mixed-language CMake link that adds it.
8. The runtime gap (F8): R loads <tree>/lib/libstdc++.so.6 only through
   ICU. minimal has it in lib/ but does not load it at startup. In
   rel11-int's minimal tree, with the packages' RUNPATH removed, cxxexc
   and Rcpp loaded the host's /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.33
   (GLIBCXX_3.4.33). Packages need GLIBCXX_3.4.32: fine on Ubuntu 24.04,
   would fail on 22.04 (3.4.30) or RHEL 8. Decision L6. Not verified:
   the failure on an older host (inferred from version numbers).
9. Headers and runtime per distribution (F9): libstdcxx-devel_linux-64 /
   _linux-aarch64 15.3.0 is noarch, depends only on __unix, is
   GPL-3.0-only WITH GCC-exception-3.1, ships no info/licenses, and
   already reaches every pixi env but wheel through conda-forge's
   zig_linux-* (pixi.lock). Layout: lib/gcc/<triple>/15.3.0/include/c++
   (5.6 MB by du, 131 entries; the toolchain tree's whole libstdcxx/
   is 5.7 MB), libstdc++.so.6.0.34 (GLIBCXX_3.4.34), .a
   files. The env's runtime is libstdcxx 16.2.0 (GLIBCXX_3.4.36), which
   vendor-libs.sh copies into the tree's lib/.
10. Linking against the runtime R loads (16.2) instead of the devel
    copy (15.3) is safe (F10): packages built with the 15.3 headers
    needed at most GLIBCXX_3.4.32; symbol versions follow what the
    headers reference. So the tree's group needs only the headers.
11. What asserted libc++ / no shared C++ runtime on linux (F11):
    verify-helpers.sh cxx_deps, verify-tree.sh, contract-test.sh,
    verify-bundle.sh (first C++ compile, sourceCpp, rp package),
    verify-recommended.sh, wheel-test.sh, the recipe's tests,
    parity-test.sh, comments. All flipped (What changed).
12. On the prototype, 208/213 rzig unit tests passed (F12): 5 compiler.zig
    linux C++ tests lacked a headers fixture. Fixed with testutil's
    libstdcxx fixtures.
13. arrow (F13): arrow 26.0.1's nixlibs.R rejected its prebuilt libarrow
    under libc++ ('Linux binaries incompatible with libc++'). Under
    libstdc++ it passes; on an allowlisted distro (ubuntu, centos,
    redhat, rhel, rocky, opensuse) or with NOT_CRAN=true it downloads
    r-libarrow-linux-x86_64-26.0.1.zip (checksum checked) and links it
    with the env's libcurl, OpenSSL 3 and libxml2; arrow.so 61 MB, needs
    libstdc++.so.6. On gamma NOT_CRAN was empty: the allowlist (ubuntu)
    alone selected the binary. On a distro not in the allowlist, arrow
    still builds libarrow from source, now with libstdc++. arrow_info()
    reports cpp_compiler GNU; the smoke returns 3. Decision L10. Not
    verified: whether a linux-arm64 libarrow exists.
14. Stress rows (F14), linux-64, prototype: magick, terra, protolite, sf
    (with s2, units), gdalraster and V8 install and pass their smokes; a
    Magick++ exception and a JS exception are caught.
15. aarch64, cross only (F15): libstdcxx-devel_linux-aarch64 15.3.0 has
    lib/gcc/aarch64-conda-linux-gnu/15.3.0/include/c++/aarch64-conda-linux-gnu;
    a.cpp compiles for aarch64-linux-gnu.2.17 with the same flags, and a
    shared library links against its libstdc++.so.6 and needs
    GLIBCXX_3.4.32 at most. Nothing ran on aarch64.

The probe's review (each point turned out true):

16. Bug, reproduced by the critic: rewriting -lstdc++ alone on a C link
    makes zig cc link its own libunwind.a, and a throw aborts
    (`zig-cc -o m4 m.o t.o -lstdc++`: 'terminate called after throwing
    ... runtime_error', rc 134). Fixed (L22). Verified on the
    implementation: no libunwind.a on the link line, NEEDED
    libstdc++.so.6 and libgcc_s.so.1, the throw is caught, exit 0
    (next/impl-libstdcxx/clink). Critic's repro: session scratchpad
    lsx/ (not kept); the implementation's re-check:
    next/impl-libstdcxx/clink/m4 and trace.log (the link line has both
    runtime paths and no libunwind.a).
17. Regression: with no headers, every zig-cxx command failed, --version,
    -dumpversion and -E included. Fixed (L23). Verified: with the
    headers removed from the minimal tree, `zig-cxx --version` and
    `-dumpversion` answer as the released rzig does; `zig-cxx -c` exits
    127 with the compilers group's text.
18. The base content checks (verify-bundle.sh, wheel-test.sh,
    verify-tree.sh) rejected the new libstdcxx-shim/ directory. Fixed
    with base_extra_files and base_extra_dirs in verify-helpers.sh;
    recipe.yaml's package_contents lists the two shims.
19. smoke-test.sh part 1 ran rzig copies outside any tree (no headers)
    and compared C++ outputs byte for byte with the libc++ shims. Fixed:
    the copies run in an R-shaped tree with the env's runtime and
    headers; only C objects and the archive are compared.
20. wheel-test.sh assumed r-zig plus ziglang alone compiles C++. With
    the headers in r-zig-compilers it no longer does on linux. Recorded
    as L5's consequence; wheel-test.sh checks that a C package still
    builds and the C++ one stops with the compilers group's text.
21. groups.zig's compilers text and pip line named only zig and flang.
    Fixed: on linux they name libstdc++'s headers ("Compiling needs the
    r-zig compilers for R 4.6.2 on linux-64: zig 0.17, libstdc++'s
    headers for C++, and flang for Fortran.", verify-package log).
22. Risk: libR loads R's runtime first, and its soname then wins for the
    process. An R_ZIG_EXTRA_ENV built with a newer libstdcxx than R's
    gives 'GLIBCXX_3.4.3x not found'; under rpy2 Python may load the
    host's older libstdc++ first. Recorded in CXX-STDLIB.md. Not probed.
23. The libR DT_NEEDED approach was untested in the plan. It needed L14:
    zig's --as-needed dropped the runtime with every ordinary link
    option tried.
24. The plan pinned gcc_version = "15.3.0" in the toolchain build. Fixed
    by L11.
25. The toolchain group had to be linux only and per host arch. Done
    (L24).
26. -lstdc++fs and -lstdc++exp were neither mapped nor dropped. Fixed
    (L7); a std::filesystem program linked with -lstdc++fs runs
    (next/impl-libstdcxx/clink/fs.cpp and fs; no output saved).
27. No Rust or Go stress row. pixi.lock's stress env has no rust or
    cargo package. Not done: unit tests cover the -lgcc_s rewrite only.
28. The arrow:source and s2 notes still gave libc++ reasons. Updated;
    BUNDLED stays (not tested without it).
29. The prototype's unit tests ran with conda-forge zig only. Now both
    zigs, 220/220 each.
30. A caller's -isystem copy of a standard C++ header does not override
    libstdc++'s with rzig (clang searches every -I before -isystem), as
    it would with gcc. Not a regression: the released rzig (libc++
    headers) behaves the same. Recorded in CXX-STDLIB.md.
31. The wheel had to place libstdcxx/ under the r-zig-compilers wheel's
    lib/R/bin/toolchain; the wheel env has no libstdcxx-devel, so it
    takes the toolchain tree's copy. Done (36).
32. Tests the plan omitted: verify-bundle.sh scenario 3 and the hermetic
    check (run in the final pass, 57-58), test-preflight.R (done),
    check.zig unit tests (done), a CMake mixed C/C++ target linked
    through zig-cc (not done).

Implementation (logs next/impl-libstdcxx/logs):

33. Stress, tree leg, linux-64, conda-forge zig, 17 targets (magick sf
    terra gdalraster protolite V8 Rcpp RPostgres systemfonts textshaping
    ragg DESeq2 scran Rsamtools arrow RcppParallel duckdb), jobs 6, 42.6
    min: 17 ok, 0 unexpected, 94 dependencies ok; every row of the table
    is ok. sf, magick, V8, arrow and terra need libstdc++.so.6 and leave
    no std::__1 symbol undefined. Report:
    next/impl-libstdcxx/stress-run/report.md. This ran before the review
    fixes; the later rzig change (the two-argument `-l stdc++` rewrite)
    did not run in stress.
34. Minimal runtime check: the minimal tree with the toolchain tree's
    zig/, libstdcxx/ and usr/ copied in; a C++ package that throws and
    catches, installed and loaded under `env -i` with no
    R_ZIG_EXTRA_ENV, prints 'cxx: boom'. /proc/self/maps names only the
    tree's lib/libstdc++.so.6 and lib/libgcc_s.so.1; the package has no
    RPATH or RUNPATH.
35. conda: `pixi run -e pkg conda-package` (linux-64) exit 0 in 16.8 min,
    all six packages and their recipe tests. r-zig-slim holds the two
    shims; r-zig-compilers depends on `libstdcxx-devel_linux-64 15.*`
    and `libstdcxx >=15`; test-compilers.R: the C++ package needs
    libstdc++.so.6, no libc++, and its exception is caught. This ran
    before the review fixes to test-compilers.R and test-toolchain.R
    (48, 55, 59) and before the build number became 12.
36. Wheel: r-zig 51.0 MiB, r-zig-compilers 3.0 MiB (842 files, the
    headers). wheel-test.sh passed on its second run (the first stopped
    on an apostrophe in a new R string): C++ runtime libstdc++.so.6,
    `cxx_throw()` caught; with r-zig-compilers uninstalled the C package
    builds and the C/C++ one stops with the compilers group's text.
    This ran before the review fix to cxx_throw (55).
37. Side finding: zig links shared libraries with --as-needed, so C++
    code that never calls the runtime gets no NEEDED libstdc++.so.6
    (the reviewer's `extern "C" int k(){return 3;}` through dist/slim's
    zig-cxx has no NEEDED at all). This is correct; see L16.
38. Side finding: arrow now downloads its prebuilt libarrow
    ("Successfully retrieved libarrow (linux-x86_64)", 1.3 min in the
    stress run) instead of building it from source. It needs network.
39. libR on linux needs both runtime libraries: readelf -d on
    lib/R/lib/libR.so shows NEEDED libstdc++.so.6 and libgcc_s.so.1,
    RUNPATH $ORIGIN:$ORIGIN/../..; nm -D shows R_zig_cxx_runtime.
    verify-tree (final pass): "C++ runtime verified: libR needs
    libstdc++.so.6 and libgcc_s.so.1 (lib/ has both, GLIBCXX_3.4.34),
    none of 16 R binaries needs libc++".
40. Process: contract failed twice on new test code (`Rcpp::demangle` is
    the global `demangle()`; the no-make run on the base needed the
    headers), then passed. pkg-parity failed once in a C build of cli
    while `pixi run -e stress stress --help` rebuilt the compile tree
    underneath it (the stress task depends on compile-tree), then
    passed. wheel-test failed once on an apostrophe.
41. Side finding: the `-fsyntax-only` quirk (zig rejects the unused
    '-c') is not new: the released rzig does the same.
42. Side finding: parity-test.sh counts 109 identical inside pixi (both
    zigs, implementation and final pass) and 108 when the reviewer ran
    it with conda-forge zig outside pixi; 77 ok+, 33 deliberate, 0
    failed in all runs. The count depends on the environment; no case
    fails.
43. Side finding: `zig-cxx -dumpversion` fails with zig's own 'version
    .2.17 in target triple' error, as in the released rzig (F7).
44. The implementer kept build number 11 on the claim that 11 was
    unpublished. Wrong: 11 was published on 2026-11-18 (build.yaml run
    44336177906; chore-release-11/PLAN.md "Released"). Fixed by L12.
45. The four failed ways to keep libR's runtime NEEDED and the one that
    works: L14 (next/impl-libstdcxx/asneeded).

The implementation review (next/review-libstdcxx). Each finding and its
resolution:

46. R1 (Medium): verify-package and hermetic, both CI steps on every
    build-r leg, had not run. Resolved: run in the final pass (57, 58).
47. R2 (Medium): the header placement (r-zig plus ziglang alone no
    longer compiles C++ on linux) was recorded as decided without a
    user answer. Resolved: L5, "default chosen by Claude; user may
    revisit", with options (a) [implemented], (b), (c); CXX-STDLIB.md
    says the same.
48. R3 (Low): the check failed correct C++ that never calls the runtime.
    Resolved: L16 in verify-helpers.sh and test-toolchain.R. The first
    version of that fix had a bug of its own (59).
49. R4 (Low): the rule was written in five places. Resolved: L17.
50. R5 (Low): contract's no-make run got the whole env through
    R_ZIG_EXTRA_ENV. Resolved: L18.
51. R6 (Low): the new demangle check in contract.R ran on every OS.
    Resolved: L19 (linux only); the exception check runs everywhere.
52. R7 (Low): -static-libstdc++ dropped silently; `-l stdc++` (two
    arguments) and `-Wl,-lstdc++` not rewritten. Resolved: L15 (silent
    drop is a recorded choice), L21 (two-argument form rewritten, with
    a unit test; the -Wl form a known gap).
53. R8 (Low): stale comments (strip.zig, compiler.zig: linux links
    libc++; verify-tree.sh vs CXX-STDLIB.md on 3.4.34 vs 3.4.32).
    Resolved: strip.zig and compiler.zig say libc++ is macOS's and
    Windows'; verify-tree.sh calls GLIBCXX_3.4.34 "the version the
    libstdc++ 15 headers belong to (a safe bound: what they compile
    needs at most GLIBCXX_3.4.32)".
54. R9 (Low): six packages.tsv rows flipped on linux-64 evidence only.
    Resolved: L25.
55. R10 (Low): test code called Rf_error with a std::string alive.
    Resolved: L20 (test-compilers.R and wheel-test.sh's cxx_throw).
56. R11 (Info): the report said cargo was unchecked; the PLAN said the
    stress env has no cargo. The PLAN is right (pixi.lock). No change.

Final pass (logs next/finish-libstdcxx/logs):

57. verify-package (verify-bundle.sh), slim, both passes (the toolchain
    pass with zig from the compilers group, the build pass with the
    env's zig): exit 0. Scenario 1 (the base alone): the preflight stops
    a compiled package with the compilers text that names libstdc++'s
    headers. Scenarios 2-4: the first C++ compile has 0 warning lines
    and the library needs libstdc++.so.6; C++ packages through R CMD
    SHLIB (make) and R CMD INSTALL (rzig build) have no rpath, need
    libstdc++.so.6 and load; R CMD SHLIB with no make builds sourceCpp,
    cpp11 and TMB; CONDA_PREFIX is ignored. Run twice: before and
    after the fix in 59 (both exit 0). minimal (`pixi run -e minimal
    verify-package`, which rebuilt the minimal tree): exit 0, both
    passes, the same C++ lines. The toolchain pass's zig, TC/zig, is
    upstream PyPI ziglang 0.17.1 (package-toolchain.log: "the
    toolchain's zig/ from build/zig-upstream/ziglang-0.17.1-linux-64").
    So C++ packages (R CMD SHLIB with and without make, R CMD INSTALL,
    sourceCpp, cpp11, TMB) were built and loaded with upstream zig as
    well as with conda-forge zig (the build pass). The stress run used
    conda-forge zig only.
58. hermetic (hermetic-check.sh): exit 0 on slim (twice, before and
    after 59) and on minimal ("hermetic tier 0/1 verified
    (linux/<flavor>): PATH=bin, empty environment"; the compiled package
    stops with the compilers text). verify-tree on minimal: "none of 15
    R binaries needs libc++", libR needs both runtime libraries.
59. Bug in the R3 fix, found here: the new stdcxx_wrong counted glibc's
    __cxa_finalize as a call into the C++ runtime. quadprog.so names
    `__cxa_finalize@GLIBC_2.2.5`; every library rzig links names it
    weakly with no version (dso_fini.o). contract failed ("data_table.so,
    client.so, processx.so, ps.so, quadprog.so: calls into the C++
    runtime but does not need libstdc++.so.6") and smoke-test.sh part 2
    failed on rzc.so, a C package. The earlier passes had run before
    that fix. Fixed: symbols versioned GLIBC_ and __cxa_finalize,
    __cxa_atexit and __cxa_thread_atexit_impl do not count, in
    verify-helpers.sh and test-toolchain.R. Checked both ways: a C
    library, quadprog.so and Rcpp.so give nothing; a library that
    throws, linked with -nostdlib++ and no runtime, gives "calls into
    the C++ runtime but does not need libstdc++.so.6". Then contract,
    smoke-test (both zigs) and verify-tree pass.
    The fix took two rounds. After the first round (summary2.txt),
    contract passed (contract-slim-2.log), but smoke-test.sh part 2
    still failed with both zigs on rzc.so: the unversioned weak
    __cxa_finalize from dso_fini.o (rzig-test-prefix-{cf,up}-2.log:573).
    The second round excluded __cxa_finalize, __cxa_atexit and
    __cxa_thread_atexit_impl by name (summary3.txt: all exit 0).
    Evidence for the two-way check: next/finish-libstdcxx/ctest/{c.so,
    t.so,u.so}; quadprog.so and Rcpp.so are build/testlib-slim's. No
    output was saved. Re-run 2026-11-18 by the records audit with
    verify-helpers.sh's stdcxx_wrong: c.so, t.so, quadprog.so and
    Rcpp.so give nothing; u.so gives "calls into the C++ runtime but
    does not need libstdc++.so.6".
60. Side finding: a library linked by plain `zig c++` (static libc++)
    has no undefined std::__1 symbol and no NEEDED libc++, so the linux
    checks do not see a libc++ linked statically into a package. rzig
    never does that on linux (-nostdlib++); a prebuilt static archive
    built with libc++ would be the case. Not covered by any check.

Records audit (2026-11-18):

61. verify-bundle.sh's success line still said "only rzig and its
    dso_fini.o in .../lib/R/bin/toolchain" after the base gained
    libstdcxx-shim/ (verify-package-slim-2.log:25 and :175,
    verify-package-minimal.log:25 and :161). Its checks were right
    (lines 248-261 require the shims); only the text was stale. Fixed:
    on linux the line now names the shims (base_extra_files). Checked
    by bash -n and by running the message code with PLAT=linux-64 and
    osx-arm64. Not verified: a full verify-package run with the new
    text.
62. Side finding: with build number 11, the branch's conda build
    produced r-zig-slim-4.6.2-h3e03716_11.conda (conda-package.log:4760)
    and r-zig-compilers-4.6.2-hcc6102e_11.conda (:5073). h3e03716_11 is
    the file name of the published build 11 (run 44336177906;
    chore-release-11/PLAN.md), with different content (the shims, libR's
    NEEDED). The build string does not change with the content. An
    upload with --skip-existing would have skipped it, as happened with
    the gfortran builds in Phase 2. L12's bump to 12 avoids this. A
    build with number 12 has not run (conda-package not rerun).
63. Side finding: `zig fmt --check zigbuild/tools/rzig/*.zig` fails on
    makefile.zig, which this branch does not change (git diff main: no
    change). Every changed Zig file passes. Reported by the
    implementation review (next/review-libstdcxx) and re-checked by the
    records audit with upstream zig 0.17.1. No log saved. Not verified:
    whether main fails the same way in CI.

PR #49's CI (2026-11-19, commit 2674ab4, label full-ci):

64. build-r run 44438791005: 32 jobs success; packaging skipped (full
    tier, no publish). A second build-r run, 44438791017, was cancelled
    (duplicate). Jobs: toolchain on all six hosts; conda-package on all
    six subdirs; default, minimal and full on ubuntu-latest,
    ubuntu-24.04-arm, macos-latest, macos-15-intel, windows-latest and
    windows-11-arm; openblas on both ubuntu hosts. Each default, minimal
    and full job ran rzig tests, the R build, verify-tree, smoke,
    contract, pkg-parity, the regression suite and hermetic; default and
    minimal jobs also packaged and verified the standalone archives;
    the minimal jobs on ubuntu-latest, ubuntu-24.04-arm, macos-latest and
    macos-15-intel built and tested the wheel (skipped on Windows).
    Details read from the job logs (gh run view --job):
    - rzig tests: 220/220 on ubuntu-24.04-arm and macos-latest default
      (jobs 135278797002, 135278797077); 191/220 with 29 skipped on
      windows-latest default (135278796899). Which 29 were skipped was
      not checked.
    - verify-tree on both linux arches: "C++ runtime verified: libR
      needs libstdc++.so.6 and libgcc_s.so.1 (lib/ has both,
      GLIBCXX_3.4.34), none of 16 R binaries needs libc++" (135278797002,
      135278797119). macos-latest: "none needs a shared
      libc++/libstdc++".
    - contract: "C++ runtime: libstdc++ in every compiled C++ package
      (Rcpp, minqa), no libc++" on both linux arches; "C++ runtime:
      static in every compiled package" on macos-latest; the Rcpp
      cppFunction exception is caught on linux-64, linux-aarch64, macOS
      and windows-latest (the default jobs read).
    - verify-bundle's success text (finding 61) ran: "== compilers
      verified: ... dso_fini.o is its link object,
      lib/R/bin/toolchain/{libstdcxx-shim/bits/c++config.h,libstdcxx-shim/sys/single_threaded.h}
      the libstdc++ shims, and nothing else is there" (135278797002 line
      1101, 135278797119 line 1103).
    - aarch64 toolchain (135274213342): "libstdc++ headers verified:
      libstdcxx/lib/gcc/aarch64-conda-linux-gnu/15.3.0/include/c++";
      libstdcxx-devel_linux-aarch64 15.3.0 h0e8df58_107.
    - conda-package: build number 12 on all six subdirs (for example
      r-zig-slim-4.6.2-h3e03716_12 on linux-64, h0122563_12 on
      linux-aarch64); test-compilers.R's "a C++ package through rzig
      build (tier 1): an exception caught: OK" on linux-64,
      linux-aarch64, osx-64, osx-arm64, win-64 and win-arm64; on linux
      "the C++ package needs libstdc++.so.6, no libc++".
      test-toolchain.R's NEEDED check (a silent stopifnot) passed before
      "toolchain: C and C++ package compiled (rzig build: tier 1) and
      loaded: OK" on linux-64 and linux-aarch64 (135274213575,
      135274213750). linux-aarch64's r-zig-compilers solved
      libstdcxx-devel_linux-aarch64 15.* to 15.3.0 h0e8df58_107.
    - wheel-test on ubuntu-24.04-arm minimal (135278797247): "wheel test
      passed (r_zig-4.6.2-py3-none-manylinux_2_17_aarch64...)". The
      wheel test compiles with PyPI ziglang (its design), not with a
      separate upstream-zig leg.
    Not verified: anything with upstream zig in CI. The upstream-zig
    runs 44438791162 and 44438791002 were skipped: the PR has no
    'upstream-zig' label. Under the both-zigs rule this is a gated
    release check; the label should run before merge.
65. stress run 44438790229 (2674ab4): ubuntu-latest and
    ubuntu-24.04-arm, tree and conda legs, 20 targets (magick sf terra
    gdalraster protolite V8 Rcpp RPostgres systemfonts textshaping ragg
    DESeq2 scran Rsamtools arrow arrow:source RcppParallel duckdb rstan
    qs2). Every leg: "Targets: 20 ok. Unexpected (!): 0. Dependencies:
    116 ok." All 80 rows read: status ok, expect ok. The conda legs
    used the run's own build 12 packages (aarch64:
    r-zig-slim-4.6.2-h0122563_12, r-zig-toolchain-4.6.2-h1fb4297_12).
    The Rcpp row's smoke throws std::range_error and catches it in R
    ("stress: smoke ok") on every leg. Times in minutes (x86_64 tree,
    x86_64 conda, aarch64 tree, aarch64 conda): arrow 1.92, 1.19, 2.73,
    1.4; arrow:source 15.18, 9.32, 9.47, 9.88; duckdb 16.29, 10.19,
    10.26, 10.51; rstan 1.06, 0.63, 0.85, 0.83; qs2 0.31, 0.24, 0.32,
    0.33. StanHeaders built as rstan's dependency. Reports and logs:
    /data/gamma/luciorq/workspaces/temp/r-zig-pixi/next/stress-44438790229/stress-*/report.md
    and logs/. Not verified: upstream zig in stress; macOS and Windows
    stress (the run was linux only).
66. On linux-aarch64 (both legs) arrow downloads a prebuilt libarrow:
    "Checksum validated successfully for libarrow", "Successfully
    retrieved libarrow (linux-arm64)" (logs/arrow.log); arrow:source
    prints "Building libarrow from source". x86_64 retrieves
    linux-x86_64. V8 takes jeroen's static bundle: "Getting bundle:
    v8-debian-11-arm64.tar.gz" on aarch64, "v8-rocky-8-amd64.tar.gz" on
    x86_64, linked as -lv8_monolith (logs/V8.log). This answers
    finding 13's open question: a linux-arm64 libarrow exists and is
    used.
67. Finding 62's build 12: conda-package built number 12 on all six
    subdirs (finding 64), so the file names differ from the published
    build 11. Not verified: an upload (publish skipped).

## Design (as implemented)

1. Standalone and wheel: option (a) of CXX-STDLIB.md (decisions L4 and L5). The headers are
   the compilers group's: conda's r-zig-compilers depends on
   `libstdcxx-devel_linux-64` (or `_linux-aarch64`) 15.* and
   `libstdcxx >=15`; the standalone tree has
   `toolchain/libstdcxx/lib/gcc/<triple>/<version>/include/c++`; the pip
   r-zig-compilers wheel has the same directory at the path rzig looks
   in. The two shim headers are the base's, beside rzig
   (`R_HOME/bin/toolchain/libstdcxx-shim/`).
2. The runtime: libR.so on linux needs libstdc++.so.6 and libgcc_s.so.1,
   so every variant loads the tree's (or env's) runtime first, and
   vendor-libs.sh copies both. rzig links C++ against that runtime by
   path.
3. The probe's flags F1-F5 (probe-libstdcxx), as below.

## What changed and why

rzig (zigbuild/tools/rzig/):
- libstdcxx.zig (new): finds the headers (R's env, then
  `<rzig dir>/libstdcxx`, then R_ZIG_EXTRA_ENV; the highest version
  under `lib/gcc/<triple>/`) and the runtime (the first env with both
  `lib/libstdc++.so.6` and `lib/libgcc_s.so.1`). `flags()`: compile pre
  `-nostdinc++`; post (after the caller's and the environments' flags)
  `-I<shim> -I<gcc>/include/c++ -I<gcc>/include/c++/<triple>
  -I<gcc>/include/c++/backward -D_GLIBCXX_SYSHDR`; link pre
  `-nostdlib++`, post the two runtime paths. `rewriteLibs()` on every
  linux link, C links too: `-lstdc++` and `-l:libstdc++.so*` become the
  runtime's two paths (libgcc_s once), `-lgcc_s` its path, `-lstdc++fs`
  and `-lstdc++exp` gcc's archive beside the headers (dropped if
  absent, a note under RZIG_TRACE), `-static-libstdc++` dropped (a note
  under RZIG_TRACE). A C++ command is zig-cxx's or one with `-x c++`. A
  command with no input (`--version`, `-dumpversion`, `-print-*`) gets
  nothing and needs no headers; standard input (`-`) counts as an input.
  No headers on a real compile: the compilers group's text, exit 127.
  No runtime on a C++ link: a one-line error, exit 127.
- Two review findings are fixed. The C-driver link bug: the probe's
  rewrite gave `-lstdc++` no libgcc_s, zig cc then linked its own
  libunwind.a and a throw aborted. Now libgcc_s comes with it. The
  version-query regression: with no headers, `zig-cxx --version` and
  `-dumpversion` failed. Now they run.
- compiler.zig: the hook after envFlags, linux only; the argv comment;
  the five linux C++ tests get a libstdc++ fixture (testutil's
  `libstdcxx`, `libstdcxxEnv`); a new test covers the order, a C link's
  `-lstdc++`, zig-cc `-x c++`, no input, no headers, and macOS.
- check.zig: the install preflight asks for libstdc++'s headers on
  linux when the package compiles C++ (tier 1 by the plan's sources;
  tier 2, tier 3 and a configure script by src/'s top level), and
  `rzig build --shlib` for an R CMD SHLIB call with C++ files. The ok
  line names the headers.
- groups.zig: on linux the compilers text names libstdc++'s headers, and
  the pip line says "zig and libstdc++'s headers". Platform gains
  `linux`.
- main.zig: error.NoLibstdcxx is exit 127.
- include/libstdcxx-shim/{sys/single_threaded.h,bits/c++config.h} (new):
  the probe's shims, each with `#pragma GCC system_header`. build.zig
  installs them beside rzig on linux (Artifacts.shim).
- smoke-test.sh: part 1 runs the copies in an R-shaped tree with the
  env's runtime in its lib/ and the env's headers in its libstdcxx/;
  only C objects and the archive are compared with the shims byte for
  byte; libgreet.so must need libstdc++.so.6. Part 2: the C++ package
  must need libstdc++.so.6.
- parity-test.sh: every fake tree has fake headers and runtime; the
  libstdc++ flags are taken out of rzig's side as "ok+"; the Fortran
  check's standalone text.
- libcxx_mirror.zig: comment only.

R's build:
- build.zig: `linkCxxRuntime` links the env's libstdc++.so.6 and
  libgcc_s.so.1 into libR on linux, by path. zig links shared libraries
  with --as-needed and dropped both (tested: positional paths,
  `linkSystemLibrary(.needed)` with `:name`, `--force_undefined`; none
  kept them, and zig maps `stdc++` to libc++ and drops `gcc_s`).
  zigbuild/cxx_runtime.zig (new) holds one exported reference to each
  (`R_zig_cxx_runtime`); a hidden one is garbage collected with its
  references. installRzig installs libstdcxx-shim/ on linux.
- scripts/zig-build.sh, scripts/vendor-libs.sh: comments.

Toolchain tree:
- zigbuild/toolchain/build.zig: on linux a `libstdcxx` group dir, a
  Tree of `libstdcxx-devel_linux-64` (or `_aarch64` by the host's arch)
  under `lib/gcc/<triple>/`, filtered to `/include/c++/` by the new
  `within` field. The version comes from the package's record, not a
  constant, so a lock that moves libstdcxx-devel needs no code change.
  macOS gets no libstdcxx/.
- zigbuild/toolchain/licenses/libstdcxx-devel_linux-64 and
  _linux-aarch64 (new): COPYING3 and COPYING.RUNTIME from gcc-15.3.0,
  VERSION 15.3.0, ORIGIN. The package ships no info/licenses. The
  tarball's sha256 matched the recipe's (d6c1a7d2...); both texts have
  the same sha256 as gcc 16.2.0's. licenses/README.md lists them.
- scripts/env.sh: group_dirs compilers adds libstdcxx.
- scripts/verify-toolchain.sh: linux needs one version's include/c++
  with `<triple>/bits/c++config.h`, `vector` and `cmath`, and nothing
  else under libstdcxx/; macOS and Windows must have no libstdcxx/.

Checks:
- scripts/verify-helpers.sh: `base_extra_files` and `base_extra_dirs`
  (the shims, linux only), `elf_needed`, `libcxx_deps`, `stdcxx_wrong`,
  `cxx_runtime_wrong`, `cxx_runtime_word`. One place for every check.
- scripts/verify-tree.sh: the base may hold libstdcxx-shim/ with exactly
  the two files; on linux libR must need both runtime libraries, lib/
  must have them, libstdc++ must offer GLIBCXX_3.4.34, and no R binary
  may need libc++. macOS unchanged.
- scripts/verify-bundle.sh: the base list allows the shims and requires
  them, and its success line names them on linux (finding 61); the first C++ compile, the sourceCpp shape and the rp package
  use cxx_runtime_wrong (libstdc++.so.6 on linux, none elsewhere).
- scripts/contract-test.sh: on linux no package needs libc++ or leaves a
  `St3__1` symbol undefined, and Rcpp and minqa need libstdc++.so.6; an
  exception thrown and caught, and a std::string through Rcpp's
  callable `demangle()` from a sourceCpp library into Rcpp.so.
- scripts/verify-recommended.sh: libc++ only, on linux.
- scripts/wheel-test.sh: the pip line per OS; the C++ runtime check by
  cxx_runtime_wrong; a `cxx_throw()` caught in R; r-zig-compilers may
  hold libstdcxx/ on linux (and must have the headers); after the groups
  are uninstalled the base keeps the shims, a C-only package still
  builds with ziglang, and on linux the C/C++ package stops in the
  preflight with the compilers group's text (r-zig with ziglang alone
  no longer compiles C++ on linux).
- scripts/make-wheel.py: r-zig-compilers takes the toolchain tree's
  libstdcxx/ on linux, its licence gains gcc's, its README says so; the
  stray check allows the shims.

conda (recipe/):
- recipe.yaml: r-zig-compilers' run deps (libstdcxx-devel_linux-* 15.*
  by target_platform, libstdcxx >=15); r-zig-slim's exclude and
  not_exists list libstdcxx; package_contents requires the shims; build
  number comments. Build number 11 -> 12 (L12).
- test-compilers.R: a C++ package throws and catches, the message
  reaches R; on linux it needs libstdc++.so.6, no libc++, no `St3__1`.
- test-toolchain.R: the C/C++ package's NEEDED check on linux.
- test-preflight.R: the shims in the base, no libstdcxx/, the pip line.

stress/:
- packages.tsv: magick, sf, terra, gdalraster, protolite and V8:
  linux=fail-abi becomes ok, with a dated note. Notes for arrow (it now
  takes its prebuilt libstdc++ libarrow), arrow:source, Rcpp,
  RcppParallel:system-tbb and s2.
- README.md: the abi class and rzig's cache text.

README.md: on linux C++ uses gcc's libstdc++ (headers in
r-zig-compilers, R's runtime), r-zig with ziglang alone compiles C but
not C++, and the compilers archive holds libstdcxx/ (records audit).

.github/devdocs/CXX-STDLIB.md: decision 3 implemented; how it works;
"Open: standalone and wheel" closed with (a); the `-isystem` order and
the process-runtime risk (newer libstdcxx in an extra env, rpy2) as
known differences.

## Tests (gamma, linux-64, 2026-11-18)

Logs: implementation next/impl-libstdcxx/logs; final pass
next/finish-libstdcxx/logs (under /data/gamma/luciorq/workspaces/temp/r-zig-pixi/).
"Final" rows ran on the worktree as it is now, unless the note says
otherwise.

| Test | When | Result |
| --- | --- | --- |
| rzig unit tests, conda-forge zig 0.17.1 | final | 220/220 |
| rzig unit tests, upstream zig 0.17.1 (build/zig-upstream) | final | 220/220 |
| `zig fmt --check` on every changed Zig file (upstream zig) | final | clean (no log saved; re-checked by the records audit; makefile.zig, unchanged, fails: finding 63) |
| parity-test.sh, both zigs (inside `pixi run rzig-test`) | final | 109 identical, 77 ok+, 33 deliberate, 0 failed |
| `pixi run rzig-test dist/slim/R-4.6.2-zig` (unit, parity, smoke-test.sh parts 1-2), both zigs | final | failed twice, then exit 0. Run 1 (summary1.txt) failed in smoke-test.sh part 2 on rzc.so. Run 2, after the first change to stdcxx_wrong, failed the same way with both zigs (rzig-test-prefix-{cf,up}-2.log line 573), although contract passed in that chain. Run 3 exited 0 with both zigs (summary3.txt) |
| R build, slim (`pixi run build`) | final | exit 0 |
| verify-tree, slim | final | passed three times: before 59, after its first round and after its second (verify-tree-slim{,-2,-3}.log) |
| toolchain, package-toolchain, verify-toolchain | final | passed; "libstdc++ headers verified: libstdcxx/lib/gcc/x86_64-conda-linux-gnu/15.3.0/include/c++" |
| verify-package, slim, both passes | final | exit 0 (before and after 59) |
| hermetic, slim | final | exit 0 (before and after 59) |
| verify-package, minimal, both passes (rebuilt the minimal tree) | final | exit 0 |
| verify-tree, minimal | final | passed (15 R binaries) |
| hermetic, minimal | final | exit 0 |
| smoke (`pixi run smoke`), slim | final | passed |
| contract, slim | final | failed (finding 59), then passed twice (contract-slim-2.log, -3.log): "C++ runtime: libstdc++ in every compiled C++ package (Rcpp, minqa), no libc++" |
| stdcxx_wrong on a C library, quadprog.so, Rcpp.so, and a throwing library linked with no runtime | final | nothing, nothing, nothing, "calls into the C++ runtime but does not need libstdc++.so.6" |
| `bash -n` on every changed script | final | ok |
| recipe/*.R parse (the slim tree's Rscript) | final | ok |
| make-wheel.py compiles (py_compile) | final | ok |
| R build, minimal (rebuilt by `pixi run -e minimal verify-package`) | final | exit 0 (verify-package-minimal.log) |
| minimal runtime check (finding 34) | implementation | passed (next/impl-libstdcxx/minrt) |
| toolchain-test (zigbuild/toolchain unit tests, conda-forge zig) | implementation | exit 0 (next/impl-libstdcxx/logs/toolchain.log; it prints no test count) |
| pkg-parity, slim | implementation | passed on the second run (finding 40) |
| conda-package, linux-64 | implementation | exit 0, 16.8 min (finding 35) |
| wheel, wheel-test | implementation | passed on the second run (finding 36) |
| stress, tree leg, 17 targets | implementation | 17 ok, 0 unexpected (finding 33) |

## Tests in CI (PR #49, commit 2674ab4, 2026-11-19)

GitHub-hosted runners, conda-forge zig only (no upstream-zig label).

| Test | Run | Result |
| --- | --- | --- |
| build-r, full tier: toolchain (6 hosts), conda-package (6 subdirs), default/minimal/full (6 hosts), openblas (2 linux hosts) | 44438791005 | 32 jobs success, packaging skipped (finding 64) |
| rzig tests | 44438791005 | 220/220 (linux-aarch64, macOS); windows-latest 191/220, 29 skipped |
| verify-tree, smoke, contract, pkg-parity, regression suite, hermetic | 44438791005 | success on every default, minimal and full job |
| verify-package (standalone archives), with finding 61's text | 44438791005 | success on every default and minimal job |
| conda-package with test-compilers.R and test-toolchain.R, build 12 | 44438791005 | success on linux-64, linux-aarch64, osx-64, osx-arm64, win-64, win-arm64 |
| wheel, wheel-test | 44438791005 | success on linux-64, linux-aarch64, osx-arm64 (macos-latest), osx-64 (macos-15-intel); not run on Windows |
| upstream-zig | 44438791162, 44438791002 | skipped (no 'upstream-zig' label) |
| stress, tree and conda legs, linux-64 and linux-aarch64, 20 targets | 44438790229 | every leg 20 ok, 0 unexpected, 116 dependencies ok (finding 65) |

## Not verified

- Upstream zig (PyPI ziglang as ZIG_BIN) in CI: the upstream-zig runs
  were skipped (no label), so no CI job and no stress leg ran with it.
  Upstream zig ran only on gamma (Tests table: unit tests, parity,
  rzig-test) and as wheel-test's PyPI ziglang. Under the both-zigs
  rule this is a gated release check. #49 merged without it (L29);
  the 'upstream-zig' runs on PR #50, after main is merged into it,
  check this code too.
- macOS and Windows: build-r passed (finding 64), but no stress run on
  this branch covered them; the stress run was linux only.
- Which 29 rzig unit tests were skipped on windows-latest (191/220) was
  not checked.
- Stress not run: upstream zig, RcppParallel:system-tbb, mlpack; the
  full and openblas builds.
- Hosts with a libstdc++ older than GLIBCXX_3.4.32 (Ubuntu 22.04, RHEL
  8): the failure without libR's NEEDED is inferred (finding 8).
- rpy2 or another embedder that loads an older libstdc++ first;
  an R_ZIG_EXTRA_ENV built with a newer libstdcxx (finding 22).
- Rust (cc-rs, -lgcc_s) and Go packages: unit tests only; the stress
  env has no cargo.
- A CMake mixed C/C++ target linked through CMAKE_C_COMPILER, and
  CMAKE_CXX_IMPLICIT_LINK_LIBRARIES's libunwind.a.
- `-Wl,-lstdc++` (not rewritten, L21) and a prebuilt static archive
  built with libc++ inside a package (finding 60).
- verify-tree.sh checks GLIBCXX_3.4.34, a constant tied to the 15.x
  headers. When libstdcxx-devel moves to newer headers, the check still
  passes but its bound is too low; nothing flags this.
