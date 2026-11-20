# feat-winarm-gaps — Windows on ARM gaps after release 11

Branch feat-winarm-gaps, from main d65f1db (the merge of #48). Three
parts: ARM64 Control Flow Guard, ICF off on Windows links, and CRAN's
Rtools45 aarch64 libraries as a fallback. Probe plans and their reviews:
scratch next/probe-cfg, next/probe-icf, next/probe-rtools. This branch's
own scratch: next/impl-winarm (implementation) and next/fix-winarm
(review fixes). Scratch root: /data/gamma/luciorq/workspaces/temp/r-zig-pixi.

Status (2026-11-18): all three parts edited, reviewed, fixed after the
review, uncommitted. The branch's code was tested on gamma (linux-64)
only. This branch's agents used no ssh. One native check ran on kappa
(win-64): plain zig cc with _LINK_, run by Claude (finding 79). No CI
run yet.

Status (2026-11-19): committed as fd44749, PR #50 (no labels). The core
CI tier passed on it (build-r run 44450920834; upstream-zig run
44450920934 skipped, no label), and a stress run on both Windows
runners (44450918935) put 14 windows-aarch64 rows at ok (findings
81-87). Still not run: the full tier, upstream-zig CI, and the rows
outside that stress run (Not verified).

Recipe build number: not changed on this branch. Build 11 was published
on 2026-11-18 (run 44336177906). feat-linux-libstdcxx bumps the number
to 12; the next release is cut after both branches merge (decision W20).

User direction, 2026-11-18, after release 11: "Fix and implement all of
it! No upstream reporting." (the list: libstdc++ on linux; win-arm64
gaps: Rtools tree, ICF off, ARM64 CFG; cleanup). Then: "Document well
all our decisions." and "and findings".

## Decisions

Where the user gave no choice, the entry says "default chosen by
Claude; user may revisit".

- W1. ARM64 Control Flow Guard: what to add.
  Options: (a) a cfguard_arm64.zig link object; (b) nothing;
  (c) no object, plus a link test.
  Choice: (c).
  Reason: zig's libmingw32 defines `__guard_check_icall_fptr` for
  aarch64 (a `ret` dummy), and clang's ARM64 CFG uses only that pointer
  (findings 1-3). A second definition would collide (finding 8).
  Who: default chosen by Claude; user may revisit. The user asked to fix
  the item ("Fix and implement all of it!"). Date: 2026-11-18.
- W2. The x86_64 "links without cfguard.o" case in link-objects-test.sh.
  Options: (a) fail the test; (b) print a WARNING and pass.
  Choice: (b).
  Reason: a zig that gains guard_dispatch.S must not block every linux
  CI leg (finding 44).
  Who: default chosen by Claude (the critic's proposal); user may
  revisit. Date: 2026-11-18.
- W3. Turn lld's ICF off on Windows image links.
  Options: (a) -g (writes a .pdb, bigger DLL); (b) a zig patch;
  (c) LINK; (d) _LINK_ set by rzig; (e) build Rtools' own freetype only.
  Choice: (d), `/OPT:NOICF` first in `_LINK_` on every Windows image link
  (windows.noIcf).
  Reason: zig cc rejects /OPT: in -Wl and -Xlinker (finding 11); ICF
  folded nothing in the tested MinGW links (findings 13, 67); it fixes
  finding 35 of chore-release-11 and removes the risk of folding
  functions whose addresses are compared. R.dll is not stripped, so lld
  already uses no ICF there (finding 15).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W4. Fill the win-arm64 library gap with CRAN's Rtools45 aarch64
  toolchain-libs "full" tree, build 6768, sha256 64dceac9....
  Options: (a) this tree; (b) wait for conda-forge; (c) build the
  libraries ourselves.
  Choice: (a).
  Reason: conda-forge win-arm64 lacks GDAL, nlopt, gsl, gmp, mpfr, hdf5,
  netcdf, udunits2, glpk, libpq and harfbuzz (chore-release-11 finding
  26). The tree has them, built with LLVM and libc++ as zig builds.
  Who: user, 2026-11-17 (chose the Rtools aarch64 C-library tree as the
  gap-filler; no verbatim quote kept in this record) and 2026-11-18
  ("Fix and implement all of it!").
- W5. How rzig finds the tree.
  Options: (a) a new variable R_ZIG_FALLBACK_SOFT; (b) a list-valued
  R_ZIG_EXTRA_ENV; (c) LOCAL_SOFT.
  Choice: (a). Windows aarch64 target only, searched after every
  environment, `-idirafter` and `-L` only, never used for OpenMP.
  Reason: LOCAL_SOFT's `-I` breaks every libc++ compile, because the
  tree is a full MinGW sysroot (finding 22). A separate name keeps
  R_ZIG_EXTRA_ENV's meaning.
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W6. PKG_CONFIG_PATH order on win-arm64.
  Options: (a) conda's .pc dir first, the tree's closed .pc after (the
  probe's recommendation); (b) the tree's closed .pc first.
  Choice: (b).
  Reason: CRAN's own aarch64 build uses this tree; modules asked
  through pkg-config (gdal, geos, proj and every module both have)
  resolve to the tree's closed .pc, archives and, with W15, headers, so
  the GDAL stack gets the tree's copy only for those modules
  (finding 50). A CMake find_* (finding 66) or a bare -l of an env
  library can still bring the env's copy; not tested. It also avoids conda-forge's win-arm64 proj.pc `-lproj_9` and libcurl.pc
  `D:/bld` z.lib bugs (findings 31, 32). With conda first, sf and ncdf4
  fail to link (finding 68).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W7. R_TOOLS_SOFT on win-arm64.
  Options: (a) leave it as the conda Library; (b) the tree.
  Choice: (b).
  Reason: it matches CRAN's aarch64 LOCAL_SOFT; sf, terra and gdalraster
  copy share/gdal and share/proj from it, and those must match the
  linked PROJ 9.7.1 (finding 27).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W8. How the tree's .pc files are used.
  Options: (a) the tree's own .pc files; (b) closed, path-pinned copies
  made with the build-tools pkgconf.
  Choice: (b). Their stamp is the tarball sha256, `zig version` and
  zig's lib_dir.
  Reason: the tree's .pc files are static-only (finding 24); pinning
  stops `-ljpeg` binding conda's libjpeg-turbo; the MinGW system-library
  list differs between zigs (findings 52, 61).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W9. When stress.R uses the tree.
  Options: (a) a `--rtools-libs` flag passed by stress.yaml; (b) on by
  default on Windows aarch64, `--no-rtools-libs` to turn it off.
  Choice: (b). The tarball is kept in the Actions cache.
  Reason: the windows-aarch64 expects then hold for local runs too; one
  path (finding 53).
  Who: default chosen by Claude (the critic's proposal); user may
  revisit. Date: 2026-11-18.
- W10. packages.tsv expects for rows the tree should fix.
  Options: (a) `ok`; (b) `?` until a windows-11-arm run.
  Choice: (b). Exception: ragg keeps windows-aarch64=fail-dependency
  until the run, because once textshaping links it may fail on its own
  clang-aarch64 libpng/libtiff/libwebp bundle (critic G9).
  Reason: nothing ran on Windows on ARM; the read-result-tables rule.
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W11. How the tree is distributed.
  Options: (a) repackage it (conda or wheel); (b) download from CRAN at
  run time.
  Choice: (b). Never repackage.
  Reason: gsl and glpk are GPL-3, gmp and mpfr LGPL-3+; repackaging
  would need licence texts and a source offer (finding 30).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W12. A user-facing option for the tree.
  Options: (a) wait for a windows-11-arm stress run; (b) document the
  manual steps; (c) an `rzig rtools-libs <dir>` subcommand.
  Choice: (a). R_ZIG_FALLBACK_SOFT stays stress-only and is not
  documented for wheel or standalone users.
  Reason: nothing has run on windows-11-arm yet, so a user-facing
  option would ship an untested path; the wheel and standalone rzig
  already read the variable, undocumented.
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W13. Upstream reports (zig, conda-forge).
  Options: (a) report to zig and conda-forge (the cfguard dispatch
  dummy, libcurl.pc D:/bld, proj.pc -lproj_9); (b) none.
  Choice: (b), none.
  Who: user, 2026-11-18 ("No upstream reporting.").

Decisions made during implementation and the review fixes:

- W14. A failure of the tree in stress.R.
  Options: (a) a warning: the rows run without the tree and report.md's
  line says `Fallback: not used: <reason>`; (b) harness_error, plus a
  workflow input to turn the tree off.
  Choice: (a).
  Reason: a CRAN outage, a missing pkgconf or an extractor without zstd
  must not stop a leg whose rows ran before this branch (finding 71).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W15. Header/archive version skew in the GDAL stack.
  Options: (a) record it only; (b) `<tree>/include-pinned` (a copy of
  include/ without the names zig ships, without c++/, flang/ and the
  OpenMP headers), with `-I<tree>/include-pinned` first in every closed
  .pc's Cflags.
  Choice: (b).
  Reason: conda's newer headers were found before the tree's while the
  tree's archives linked (finding 70). No name zig has is copied, so
  zig's headers are never shadowed.
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W16. The tree's import libraries (lib<n>.dll.a, lib<n>.lib) for DLLs
  it does not install.
  Options: (a) record the limit; (b) importLib skips them in the
  fallback tree's lib/.
  Choice: (b). Such an `-l` is left to zig, so the link fails instead of
  the DLL's load.
  Reason: the tree installs no DLL for libomp, boost, eigen, clang, LTO
  or Remarks, so an import library would make the link succeed and the
  DLL fail at load (finding 72).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W17. The "ignored" warning for R_ZIG_FALLBACK_SOFT outside Windows on
  ARM.
  Options: (a) warn on every list() call; (b) warn once per command
  (Ctx.fallback_soft); (c) no warning.
  Choice: (b), one warning per command: environment.fallback resolves
  once into Ctx.fallback_soft.
  Reason: list() runs several times per command; configure probes read
  repeated warnings as noise (finding 73).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W18. The verbose word in verify-bundle.sh's ICF check.
  Options: (a) `_LINK_=/VERBOSE`; (b) `_LINK_=-verbose`;
  (c) `/VERBOSE` with MSYS2_ENV_CONV_EXCL=_LINK_.
  Choice: (b).
  Reason: verify-bundle runs under MSYS2 bash, which converts
  path-like environment values when it starts a native program
  (finding 69). lld-link takes the dash form. lld read `-verbose`
  inside _LINK_ natively on kappa (finding 79).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W19. A stress.yaml workflow_dispatch input for the tree.
  Options: (a) add `rtools_libs`; (b) no new input.
  Choice: (b).
  Reason: stress.R's default covers CI (W9) and a failure no longer
  stops a leg (W14). stress.yaml already has 10 inputs (finding 54).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W20. The recipe build number on this branch.
  Choice: not bumped.
  Reason: build 11 was published on 2026-11-18 (run 44336177906).
  feat-linux-libstdcxx bumps the number to 12, and the next release is
  cut after both branches merge. The implementer's report said 11 was
  unpublished; that was wrong. feat-linux-libstdcxx's recipe diff sets
  number: 12 (checked 2026-11-18). If this branch merges first, no
  package may be built or uploaded until the bump to 12 is on main:
  build 11 is on the channel, and conda-publish uses --skip-existing.
  Who: default chosen by Claude under the user's rule of one release at
  the end of the backlog (2026-11-12); user may revisit.
  Date: 2026-11-18.
- W21. Which targets read R_ZIG_FALLBACK_SOFT.
  Options: (a) any Windows target; (b) aarch64 Windows targets only.
  Choice: (b). Elsewhere it is ignored with the W17 warning.
  Reason: the aarch64 tree on win-64 gives arch-mismatch link errors,
  not a clear message (finding 57).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W22. CMake and the tree.
  Options: (a) CMake builds do not see the tree, recorded; (b) an
  aarch64 Windows R's etc/r-zig.cmake appends the tree to
  CMAKE_SYSTEM_PREFIX_PATH after the environments.
  Choice: (b). verify-tree.sh checks the line on win-arm64.
  Reason: configure scripts that use CMake find_* (nloptr's cmake path,
  Rhdf5lib, arrow:source, duckdb, mlpack) would otherwise not see the
  tree (critic of the rtools probe plan). Consequence: CMake prefers
  the env's copy and pkg-config the tree's (finding 66).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W23. OpenMP and the tree.
  Options: (a) let openmp() pick the tree like any environment;
  (b) openmp() skips the fallback.
  Choice: (b): environment.openmp() skips the fallback (Env.fallback).
  Reason: the tree's omp.h and libomp.dll.a are for a libomp.dll that
  nothing installs (finding 49).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W24. Extracting the .tar.zst on the runner.
  Options: (a) cmake -E tar only; (b) cmake -E tar, then System32
  tar.exe; (c) R untar() (cannot read zstd, finding 21).
  Choice: (b): `cmake -E tar` first, then System32's tar.exe (Windows 11
  bsdtar), else the W14 failure line.
  Reason: whether conda-forge's win-arm64 cmake reads zstd is not known
  (findings 58, 60).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W25. How the `_LINK_` value is shown.
  Options: (a) print a _LINK_= line in RZIG_PRINT_ARGV dry runs;
  (b) show it only in RZIG_TRACE.
  Choice: (b): RZIG_TRACE shows `_LINK_=<value> ` before zig's line;
  RZIG_PRINT_ARGV (dry runs) stays unchanged; main.zig's header says so.
  Reason: parity-test.sh, test-compilers.R, verify-bundle.sh,
  verify-tree.sh and pkg-parity.sh parse the dry run's first line
  (finding 17).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W26. A caller's LINK variable.
  Options: (a) rzig also rewrites LINK; (b) rzig leaves LINK alone, and
  its doc says a LINK=/OPT:ICF turns ICF back on.
  Choice: (b).
  Reason: a caller who sets LINK=/OPT:ICF asks for ICF (finding 63).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W27. stress.R's map of the sysdeps the tree serves.
  Options: (a) the probe's map, with imagemagick and tbb-devel;
  (b) without them.
  Choice: (b): imagemagick and tbb-devel are left out.
  Reason: magick takes r-windows' bundle whatever the env has;
  RcppParallel:system-tbb is a unix row (finding 51).
  Who: default chosen by Claude; user may revisit. Date: 2026-11-18.
- W28. packages.tsv after stress run 44450918935 (findings 83-85).
  Options: (a) write `windows-aarch64=ok` on every confirmed row;
  (b) drop the `windows-aarch64=` key where the bare or `windows=`
  value is already ok, and write `windows-aarch64=ok` only where
  windows= is a failure. For sf and lwgeom: (c) a `windows=` value
  for both arches; (d) separate windows= and windows-aarch64= keys.
  Choice: (b) and (c). units, textshaping, Rmpfr, nloptr and lme4 are
  `ok`; ragg and ncdf4 `linux=ok macos=ok windows=ok`; hdf5r, gsl,
  igraph, Rsamtools, terra, gdalraster and scran keep their windows=
  failure and get `windows-aarch64=ok`. sf and lwgeom are
  `windows=fail-dependency` (they were windows=?). s2 keeps
  `windows=fail-abi`, with a windows-aarch64 note. Each row has a dated
  note.
  Reason: (b) is the same result from stress.R's parser with fewer
  keys (checked: only these rows' windows-aarch64 values and sf's and
  lwgeom's windows values changed; linux and macOS are unchanged).
  (c): s2 failed on all four Windows legs, so sf and lwgeom were
  skipped on all four.
  Who: the row values were set by the workflow step that recorded the
  run (2026-11-19); the key form is a default chosen by Claude; user
  may revisit. Date: 2026-11-19.

- W29. Merge order with PR #49 (feat-linux-libstdcxx).
  Options: (a) #49 first, main merged into feat-winarm-gaps, then
  full-ci and upstream-zig on #50; (b) the same, but the labels before
  the merge (the full matrix twice); (c) #50 first, then full CI and
  stress again on #49.
  Choice: (a). The user merged #49 (main f668295) on 2026-11-19. The
  merge of main into this branch has two conflicts:
  zigbuild/tools/rzig/build.zig (both additions kept) and
  stress/packages.tsv (merged row by row: #49's linux= values and
  notes, this branch's windows-aarch64= values and notes; magick, s2,
  sf, terra and gdalraster had both). #49's record commit (its CI and
  stress results) comes in on this branch, because #49 merged before
  it was pushed.
  Reason: #50 still needed full-ci and upstream-zig; #49's 32-job run
  and its stress would otherwise have to run again. The two branches
  touch 12 of the same files, but rzig's compiler.zig and main.zig
  merge without conflict (linux-only against Windows-only code).
  Check before the commit: on gamma, the merged tree passed rzig's
  unit tests (6/6 steps), parity-test.sh (109 identical, 77 identical
  but for flags, 33 deliberate, 0 failed) and link-objects-test.sh.
  Who: user (merge order); the conflict resolution by Claude.
  Date: 2026-11-19.

## Findings

All on gamma (linux-64), 2026-11-18, unless a line says otherwise.
"Not verified" names what the finding does not cover. Paths under
next/ are in the scratch root above. "zig" without a qualifier means
both conda-forge zig 0.17.1 and upstream (PyPI ziglang) zig 0.17.1.

### ARM64 Control Flow Guard (probe next/probe-cfg, F1-F9)

1. (cfg F1) zig's MinGW has no guard_dispatch.S. `<zig 0.17.1>/lib/libc/mingw/cfguard/`
   holds only mingw_cfguard_support.c. Its
   `#elif defined(__i386__) || defined(__aarch64__) || defined(__arm__)`
   branch (line 24) defines `static void __guard_check_icall_dummy(void) {}`
   and `__guard_check_icall_fptr` (line 44) in .00cfg.
   `__guard_dispatch_icall_fptr` exists only under `__x86_64__`, and only
   that branch needs the missing `__guard_dispatch_icall_dummy`. The
   upstream ziglang 0.17.1 wheel has the same file.
2. (cfg F2) clang's ARM64 CFG uses only the check pointer.
   `zig cc -target aarch64-windows-gnu -mguard=cf -O2 -c lib.c` gives
   `U __guard_check_icall_fptr` and no dispatch symbol. llvm-objdump:
   adrp/ldr x8 <- `__guard_check_icall_fptr`; mov x15, x2; blr x8; br x2.
   x86_64 gives `U __guard_dispatch_icall_fptr`.
3. (cfg F3) The arm64 dummy in zig's built libmingw32.lib
   (member mingw_cfguard_support.obj) disassembles to `d65f03c0 ret`.
   It touches no register.
4. (cfg F4) An aarch64 `-mguard=cf` DLL and an EXE that imports it link
   with no extra object, rc=0, with both zigs. The x86_64 DLL fails:
   `lld-link: error: undefined symbol: __guard_dispatch_icall_dummy >>>
   referenced by libmingw32.lib(mingw_cfguard_support.obj):(__guard_dispatch_icall_fptr)`.
5. (cfg F5) With rzig's aarch64 object: a C++ `-mguard=cf` DLL (virtual
   calls, std::function, try/catch) plus clear_cache.o links rc=0 and
   exports only `run`; a C one exports only `apply` (lld does not
   auto-export `__guard_check_icall_fptr`). clear_cache.o from
   `zig build -Dtarget=aarch64-windows-gnu` is byte-identical (cmp) to
   `zig build-obj -target aarch64-windows-gnu -mcpu=baseline -OReleaseSmall -fstrip objects/clear_cache.zig`.
6. (cfg F6) The linked aarch64 EXE has LoadConfigTableRVA 0x0: no load
   config, no guard flags. Every checked call goes through the `ret`
   dummy. CFG is not enforced, as in mingw-w64 on x86_64 with cfguard.o.
   The link is a no-op at run time, not CFG protection.
7. (cfg F7) A package does hit ARM64 CFG. In the r-windows
   imagemagick-6.9.13.29-clang-aarch64 bundle (65 .a files), only
   librsvg-2.a references CFG: 5 objects with `U __guard_check_icall_fptr`.
   magick was ok on windows-11-arm in stress 44259183592, and that link
   took librsvg-2.a. Not verified: its smoke only reads
   magick_config()$version, so no CFG-checked call ran.
8. (cfg F8) No rzig logic change is needed. compiler.zig's switch
   (x86_64 cfguard.o, aarch64 clear_cache.o), build.zig linkObject,
   verify-helpers.sh link_object and verify-tree.sh's magic check stay.
   A strong `__guard_check_icall_fptr` in our object would collide with
   libmingw32's member once that member is pulled in.
9. (cfg F9) No automated test covered `-mguard=cf` links on either arch.
   A cross-build of all of rzig only to get its object took 2 min 56 s;
   a `zig build object` step took 0.41 s once the build runner was
   compiled (143 s for the runner).

Not verified for 1-9: Rust CFG objects other than this librsvg-2.a
(tail calls, other LLVM versions); ARM64EC (LLVM uses a dispatch scheme
there; R does not target it); MSVC `/guard:cf` static libraries (they
may expect a load config and `__guard_fids_table`).

### ICF and the addrsig error (probe next/probe-icf, F1-F8)

10. (icf F1) `-s` turns ICF on. zig 0.17.1 src/link/Lld.zig:449-458 adds
    -DEBUG (and -PDB) only when not stripping; zig never passes /OPT:REF
    or /OPT:ICF (only lldlto=N under LTO, :470-476, and -OPT:REF for
    uefi). src/main.zig:2902-2907: -s, --strip-all, -S, --strip-debug
    all set strip. Without /DEBUG, lld defaults to /OPT:REF,ICF. The -v
    line with -s has no -DEBUG; without -s it has `-DEBUG -DLL`.
11. (icf F2) zig cc has no flag that turns ICF off. `-Wl,--icf=none`,
    `-Wl,--icf=all`, `-Wl,/OPT:NOICF`, `-Wl,/opt:noicf`, `-Wl,/OPT:NOREF`
    and `-Wl,-Xlink=...` stop with "error: unsupported linker arg".
    `-Wl,-OPT:NOICF` is read as -O: "warning: ignoring deprecated linker
    optimization setting "PT:NOICF"", and the link still fails.
    --gc-sections, --no-gc-sections and -fno-addrsig do not help. `-g`
    links but writes a .pdb: 1,976,832 B plus a 1.6 MB .pdb, against
    1,809,920 B with -s and NOICF. Logs: next/probe-icf/log/f*.txt.
12. (icf F3) The environment works. `_LINK_=/OPT:NOICF` or
    `LINK=/OPT:NOICF` fixes the link, both arches, both zigs. lld puts
    these words before zig's: `_LINK_=/VERBOSE` shows "Command line:
    lld-link /VERBOSE -lldmingw ...". aarch64 `-shared -s` against
    harfbuzz-8.2.1-clang-aarch64's libfreetype.a: rc=1 "lld-link: error:
    libfreetype.a(src_base_ftinit.c.obj): invalid symbol index in addrsig
    section"; with the variable rc=0. x86_64 with the clang-x86_64
    bundle: the same. A textshaping-like C++ link (harfbuzz, hb-ft,
    freetype, fribidi): fails without, links with (ts-aarch64-noicf.dll
    2,007,552 B; ts-x86_64-noicf.dll 2,266,112 B).
13. (icf F4) ICF folded nothing in the tested MinGW C links. clang names
    each MinGW function section `.text$<name>` (zig ignores
    -fno-unique-section-names), and lld folds only same-named sections.
    icf.c/icf2.c/icf3.c twins stay apart with /OPT:ICF, /OPT:SAFEICF and
    the default ("ICF needed 2 iterations"). A png+zlib DLL with -s has
    the same size with and without NOICF (x86_64 340,992 B; aarch64
    255,488 B) and an empty objdump -d diff. lld marks exported and
    addrsig-listed symbols keepUnique. See finding 67 for C++.
14. (icf F5) rzig passes -s on (compiler.zig test at :1154). Every
    Windows image link (make, rzig build tiers 1 and 2, zig-fc through
    fortran.zig:168) goes through compiler.argv's `cfguard.wanted`
    block, where noLtoLink and implib already run. Before this branch,
    main.zig handed zig an environment only for libcxx_mirror, which is
    off on Windows.
15. (icf F6) R's own Windows build does not use rzig: build.zig links
    R.dll with zig directly (addLibrary :2942; `.strip = null` on Windows,
    :2633-2636, the only `.strip` in build.zig). Not stripped means
    -DEBUG, so lld already defaults to /OPT:NOREF,NOICF there. No
    build.zig change. Not verified: a Windows build log of R.dll's link.
16. (icf F7) Stale stress records: packages.tsv textshaping
    `windows-aarch64=fail-toolchain` and ragg
    `windows-aarch64=fail-dependency`. stress.R:225 keeps the addrsig
    text in the toolchain class; it still catches a regression.
17. (icf F8) Dry-run consumers parse RZIG_PRINT_ARGV's first line:
    parity-test.sh's Windows cases, recipe/test-compilers.R:211,
    verify-bundle.sh:954/1020, verify-tree.sh:225, pkg-parity.sh:164. A
    `_LINK_=` line there would break them (decision W25).

Not verified for 10-17: the real textshaping and ragg link lines (a
hand-written link against the same bundle was used); a fresh bundle
download through tools/winlibs.R; whether anything else in Windows CI
sets LINK or _LINK_; whether zig's link cache reuses an output linked
without _LINK_ (harmless: with and without ICF the outputs differ only
in PE hash fields). See also findings 79 (native win-64 check) and 80
(scope of the x86_64 repro).

### Rtools45 aarch64 tree (probe next/probe-rtools)

18. Download. URL
    https://cloud.r-project.org/bin/windows/Rtools/rtools45/files/rtools45-toolchain-libs-full-aarch64-6768.tar.zst
    (also on cran.r-project.org). 415437513 bytes (396 MiB), dated
    2026-01-28, sha256
    64dceac9ecdd54aa85a209a0529f5a96c4b7898ae830c165d0d05bffa5e9e8b5
    (curl | sha256sum on both mirrors and the triage copy). CRAN
    publishes no checksum file, so we pin our own. Rtools-aarch64 is de
    facto unmaintained (r-universe README), so 6768 is likely the last
    tree.
19. The base tarball lacks the gap libraries. The "base" tarball
    (164 MB, sha256 8ca25e5d...) lists only bzip2..dlfcn-win32 in
    settings.mk. "full" is required.
20. Contents. One top directory, aarch64-w64-mingw32.static.posix:
    41937 entries (38185 files, 2591 directories, 1161 hard links, all in
    bin/), no symlinks, longest path 132 characters, 2.86 GB unpacked.
    include/ has 2441 entries, with all MinGW-w64 headers and libc++
    headers (include/c++/v1). lib/ has 899 .a files and lib/pkgconfig
    456 .pc files (counted 2026-11-18 in next/fix-winarm/rt/a; the probe
    wrote 457). Also libclang_rt.builtins-aarch64.a, libc++.a,
    libunwind.a, libFortranRuntime.a, libomp.dll.a, share/gdal,
    share/proj. Versions (installed.list): gdal 3.12.1, geos 3.14.1,
    proj 9.7.1, glpk 5.0, gmp 6.3.0, gsl 2.7.1, harfbuzz 12.3.0, hdf5
    1.12.1, imagemagick 7.1.2-5, intel-tbb 2022.2.0, mpfr 4.2.2, netcdf
    4.9.2, nlopt 2.10.0, postgresql 16.10, udunits 2.2.28. udunits2 has
    no .pc file, only libudunits2.a.
21. Extraction. `cmake -E tar xf <tb> <top>/include <top>/lib
    <top>/share/gdal <top>/share/proj` took 7.6 s: 1.4 GB, 29958 files.
    cmake 4.4.5's libarchive reads zstd; R's untar() does not. R 4.6 has
    tools::sha256sum().
22. LOCAL_SOFT's -I breaks libc++ compiles. Makeconf.win
    (zigbuild/config/win-common/Makeconf.win:40-63) adds
    `-I"$(LOCAL_SOFT)/include"` when LOCAL_SOFT is set; CRAN's aarch64
    logs (triage cran-aarch64-out/nloptr.out) show it. With
    `-I<tree>/include`, `zig c++ -target aarch64-windows-gnu` fails on
    t_gdal.cpp, t_tbb.cpp, t_magick.cpp and a plain cstdio/cmath/thread
    file: "error: <cstddef> tried including <stddef.h> but didn't find
    libc++'s <stddef.h> header" (also cstdlib, cstdio, cmath,
    __math/traits.h). C files compile. With `-idirafter <conda>/include
    -idirafter <tree>/include` all compile (regex.h, windows.h, boost,
    omp.h included). So LOCAL_SOFT and the raw .pc Cflags must not reach
    zig.
23. Every gap library cross-links with zig, flags as rzig's
    (`-target aarch64-windows-gnu -g0`, clear_cache.o, `-shared -s`,
    `-lws2_32`): one test DLL each for nlopt, gsl+gslcblas, gmp+mpfr,
    glpk, hdf5_hl, netcdf (nc_create NETCDF4|DISKLESS), udunits2+expat,
    libpq, harfbuzz+freetype, oneTBB, GDAL+GEOS+PROJ (C++,
    OGRSpatialReference, try/throw/catch) and Magick++. All rc=0, both
    zigs, IMAGE_FILE_MACHINE_ARM64. Sizes: gdal 78 MB, magick 30.6 MB,
    netcdf 15 MB. Imports: api-ms-win-crt-*, KERNEL32, system DLLs, plus
    libomp.dll for gdal and magick. `-###` shows libc++, libc++abi,
    libunwind and compiler_rt from zig's cache. `-lws2_32` resolves to
    zig's import lib even with `-L<tree>/lib`. Side results: libnlopt.a
    is C++ inside (stogo), so a C-only link fails on std::__1::ios_base
    (nloptr links through CXX, so fine); the tree's Magick++ closure
    (libffi) needs `__clear_cache` and links only with clear_cache.o;
    the tree's freetype links with -s, so it does not hit the addrsig
    error; libgdal pins its own libFortranRuntime.a and
    libFortranDecimal.a (LLVM 19 flang) and imports libomp.dll.
24. The tree's .pc files are static-only. hdf5_hl.pc has
    `Libs: -L${libdir}` and the rest in Libs.private. Rtools'
    pkg-config is static by default; r-zig's pkgconf 3.0.11 is not, so
    `pkgconf --libs hdf5_hl` gives no -lhdf5. Closed .pc files fix it
    (decision W8). The prototype wrote 456 in 47-50 s (3 pkgconf calls
    per module).
25. libjpeg differs: the tree has IJG libjpeg 9.6, conda has
    libjpeg-turbo (ABI 62/8). An -ljpeg bound in conda's dir would pair
    tree archives with the wrong libjpeg; path pinning prevents it.
26. The tree is LLVM 19 libc++ (std::__1), as zig is, so GDAL's C++ API
    (gdalraster, terra, sf) may work on win-arm64. On win-64 it cannot:
    conda-forge is MSVC there (fail-abi rows) and x86_64 Rtools is
    gcc/libstdc++. Not verified: run-time layout and exceptions between
    LLVM 19 headers and zig's clang 22 libc++.
27. How packages consume the tree (CRAN sources, probe src/x). nloptr
    Makevars.ucrt: `-I$(R_TOOLS_SOFT)/include/nlopt`, `-lnlopt`; its
    "nlopt.h not found" came from R_TOOLS_SOFT being the conda Library.
    gmp `-lgmp`; units `-ludunits2 -lexpat`; gsl `-lgsl -lgslcblas`;
    hdf5r `pkg-config --libs hdf5_hl` with WRAP 1_12_0, which the
    tree's HDF5 1.12.1 matches (conda's 2.2 broke it on win-64); ncdf4
    `pkg-config --libs netcdf libcurl`; igraph `pkg-config libxml-2.0
    glpk`; sf, terra, gdalraster `pkg-config gdal [geos proj]` and
    `cp -r $(R_TOOLS_SOFT)/share/{gdal,proj} ../inst/`; textshaping and
    ragg skip the r-windows bundle when `$(PKG_CONFIG) --libs` is not
    empty; RPostgres pkg-config libpq (its "from Rtools" branch, Libs
    has ldap32); magick always downloads the r-windows imagemagick-6
    bundle.
28. The rzig prototype (scratch only) passed 215/215 unit tests with both
    zigs (213 before, plus 2). Diffs:
    next/probe-rtools/rzig-fallback-environment.diff and
    rzig-fallback-compiler.diff.
29. The stress.R prototype (next/probe-rtools/rtools_libs.R) downloaded,
    checked, extracted and closed the tree in 1.09 min from a file://
    URL; a second call took 0.03 min.
30. Licences. The tarball ships no per-library licence texts: the top
    LICENSE is LLVM's Apache-2.0, and share/licenses has only opencv4.
    gsl and glpk GPL-3; gmp and mpfr LGPL-3+ (gmp also GPL-2+); nlopt
    LGPL/MIT; hdf5 and netcdf BSD-style; gdal, proj, harfbuzz MIT; libpq
    PostgreSQL; ImageMagick its own Apache-like licence; oneTBB
    Apache-2.0; udunits a permissive UCAR licence. Sources:
    svn.r-project.org R-dev-web/trunk/WindowsBuilds/winutf8/ucrt3/toolchain_libs.
    Packages that link gsl or glpk statically are GPL combinations, as
    on CRAN (decision W11).
31. Side finding: conda-forge libcurl 8.23.0's libcurl.pc on win-64
    (hdb0ef4a_0) and win-arm64 (hf244671_0) names a build path in Libs:
    `D:/bld/curl_split_recipe_1791990675856/_h_env/Library/lib/z.lib`.
    zig stops with "file not found" (reproduced in the linux cross link
    for ncdf4, finding 68). Not verified: a Windows R CMD
    INSTALL; ncdf4's status on windows-latest at this lock.
32. Side finding: conda-forge win-arm64 proj.pc says
    `Libs: -L${libdir} -lproj_9` but ships only proj.lib: "unable to
    find dynamic system library "proj_9"" for sf and terra through
    pkg-config proj (cross link). Not verified on Windows.
33. Side finding: the tree has regex.h (include/regex.h, libregex.a,
    libgnurx.a), plus libidn2, libunistring, libgcrypt, libgpg-error
    and libcurl. Rhtslib's missing <regex.h> is there, so Rhtslib and
    Rsamtools may get further on win-arm64. Outcome unknown.
34. Predicted windows-aarch64 results (probe, with conda first): units,
    gsl, nloptr, hdf5r, Rmpfr, lme4, gdalraster, textshaping, ragg ok;
    ncdf4 `?`; igraph and scran `?`; terra, sf fail-sysdep (proj.pc);
    lwgeom fail-dependency; Rhtslib and Rsamtools `?`; RPostgres no key
    change; magick, arrow, s2, protolite, RcppParallel*, qs2 unchanged.
    Superseded by W6 (tree first) and W10 (all `?`). The "unchanged"
    list was stated, not checked.
35. Library search order with both dirs (critic, cross link): `-lz` with
    z.lib in the env dir and libz.a in the tree dir takes the env's
    z.lib whatever -L comes first, also when the env file is libz.lib.
    Not verified: every name form across dirs.
36. C-only links (critic): gsl, Rmpfr, hdf5r, ncdf4, units and glpk with
    `zig cc` in rzig's order: rc=0.
37. envFlags already adds `-idirafter <env>/include` on every Windows
    compile (`windows_headers_always = true`, compiler.zig:360), so the
    fallback tree's headers reach packages (critic).
38. The build-tools group ships pkgconf.exe (zigbuild/toolchain/pkgconf.zig),
    and `zig env` 0.17.1 prints ZON with `.lib_dir` (critic).
39. conda-forge's pkg-config 0.29 stops at the tree's libgcrypt.pc
    ("Libs field occurs twice"); pkgconf is required.
40. Closed .pc Libs hold names the probe did not plan for: -lstdc++ in
    305 files, -lc++ 238, -lmingw32 4, -ltegra_hal and -lSymAppl 1 each
    (unresolvable), -fopenmp in Libs 17 (critic). The implementation
    skips 5 modules: opencv4 (-ltegra_hal), symphony-app (-lSymAppl),
    libgsf-win32-1, libsbml, and grpcpp_otel_plugin (fails in pkgconf).

Not verified for 18-40: see "Not verified" below (everything on
Windows).

### Critics' gaps that proved true (and one that did not)

41. CFG test cost: the prototype used its own `--cache-dir`, so it would
    recompile the build runner each run. True. Fixed: no --cache-dir;
    the test reuses test.sh's cache. Measured: 162 s with both caches
    cold; inside rzig-test 121 s (conda-forge zig) and 151 s (upstream)
    with a cold global cache; 1 s warm.
42. CFG test reach: rzig-test runs on every linux build-r leg
    (ubuntu-latest, ubuntu-24.04-arm, minimal and openblas envs) and in
    upstream-zig.yaml (build-r.yaml:97-98, build.yaml:129-196,
    upstream-zig.yaml:43-46). True; both zigs run it in CI. Not
    verified: cross-linking for Windows from linux-aarch64.
43. The link test calls `$ZIG cc`, never rzig, so it does not prove that
    rzig adds the object. True; its header says so (compiler.zig's unit
    tests and parity-test.sh cover rzig's choice).
44. The x86_64 "must fail" case was a CI tripwire. True; decision W2.
45. Missed records: feat-win-zig-binutils/PLAN.md lines 278 and 291 and
    the packages.tsv magick note. True; edited. The "Not needed" entry
    was at line 441, not ~430. Not true: the critic's
    chore-release-11/PLAN.md:16 follow-up line does not exist at d65f1db.
46. Missed comments (cfguard.zig:2-4, repo build.zig:2845, parity-test.sh:34-36,
    pixi.toml rzig-test comment). True; edited. Also: the repo's
    `zig build rzig-test` step (build.zig:615-624) runs only rzig's
    unit tests; link-objects-test.sh runs only through
    `pixi run rzig-test` (test.sh), which is what build-r.yaml calls.
47. ICF G1/G2: no test covered rzig spawning zig with an explicit
    environment on Windows, or lld reading _LINK_ there. True. Added
    verify-bundle.sh's traced stripped DLL link (Windows block, both
    passes). Not run yet. (2026-11-19: passed on both Windows runners,
    both passes, finding 82.)
48. ICF G3, G4, G10, G11: the plan named test.yml, which does not exist
    (rzig-test runs from build-r.yaml); upstream-zig.yaml has no
    windows-11-arm leg (:69-80) and stress.yaml cannot get an upstream
    win-arm64 toolchain artifact; the scratch parity FAIL ("a URL
    dependency is refused") came from the scratch layout and passes in
    the real worktree; the noIcf unit test is not under a Windows skip,
    so it runs natively on win-64 and win-arm64. All true.
49. Rtools: environment.openmp() could pick the tree (it has
    include/omp.h and lib/libomp.dll.a). True; decision W23.
50. Rtools: two copies of one library in one DLL and header/archive skew
    with conda first. True; decisions W6 and W15, numbers in finding 70.
51. Rtools: packages.tsv has no Rhtslib row (it is only Rsamtools'
    dependency); RcppParallel:system-tbb is linux and macOS only; magick
    is not served by the tree. True; decision W27, no Rhtslib edit.
52. Rtools: the closed .pc stamp keyed only on the sha256, but the
    MinGW .def set differs between zigs. True; the stamp now has
    `zig version` and lib_dir. Closed Libs hold unquoted absolute paths,
    which break if a path has spaces: not fixed (fine on runners).
53. Rtools: a CI-only `--rtools-libs` would leave local runs and the
    universe channel with wrong expects. True; decision W9.
54. Rtools: stress.yaml already has 10 workflow_dispatch inputs. True;
    decision W19.
55. Rtools: the 36-package conda env of the probe was not the real
    win-arm64 stress env (no libxml2, expat, libgit2). True; the
    implementation re-ran against all 98 packages (finding 68).
56. Rtools: mixtest-e2e.sh was not rzig (zig c++ for everything,
    -mcpu=generic, --define-prefix, a shell imitation of windows.libs).
    True. Partly closed: C-only rows use zig cc, rzig's order and
    importLib rule were followed. rzig itself was never run with the
    tree: a dry run on gamma uses the host's x86_64 arch.
57. Rtools: fallback() accepted any Windows target and warned on every
    call elsewhere. True; decisions W21 and W17.
58. Rtools: cmake's zstd on win-arm64 unknown. True; decision W24.
59. Rtools: R_TOOLS_SOFT=tree and `-idirafter <tree>/include` change
    other branches. Makevars switch on `$(wildcard $(R_TOOLS_SOFT)/lib/libX.a)`:
    sf, terra, gdalraster, lwgeom add -lsharpyuv; ncdf4 adds -lpsl
    -lbrotlidec -lbrotlicommon; igraph's fallback branch (only when
    `pkg-config --version` fails) sets -I"${LIB_XML}/include", the bare
    tree include. The tree adds dlfcn.h, regex.h, libintl.h, termcap.h,
    readline/readline.h and iconv.h, which configure probes may find.
    True as risks; not assessed further (see Not verified).

### Implementation and review findings

60. Extraction fallback (decision W24): both extractors are tried: `cmake -E tar`, then System32's tar.exe. On linux:
    0.98 min with cmake, 0.9 min with GNU tar when cmake fails, 0.03 min
    on the second call. A changed zig rewrites only the .pc files
    (0.46 min).
61. Prototype bug found and fixed: its system-library test paired the
    two MinGW .def directories with the two suffixes (R's recycling), so
    upstream zig, which has some names only as lib-common/<n>.def.in,
    pinned the tree's libadvapi32.a and others by path. With outer() the
    451 closed .pc files are byte-identical for both zigs (paths aside).
62. ICF fix verified by cross link (next/impl-winarm/icf/summary.txt):
    a DLL of t.c against harfbuzz-8.2.1-clang-<arch>'s libfreetype.a,
    libharfbuzz.a, libpng.a, libbz2.a, libz.a, -lrpcrt4 -lgdi32, -O2
    -shared -s:

    | zig | arch | -s | _LINK_=/OPT:NOICF | + LINK=/OPT:ICF | LINK=/OPT:NOICF |
    | --- | --- | --- | --- | --- | --- |
    | conda-forge 0.17.1 | aarch64 | addrsig error | rc=0 | addrsig error | rc=0 |
    | conda-forge 0.17.1 | x86_64 | addrsig error | rc=0 | addrsig error | rc=0 |
    | upstream 0.17.1 | aarch64 | addrsig error | rc=0 | addrsig error | rc=0 |
    | upstream 0.17.1 | x86_64 | addrsig error | rc=0 | addrsig error | rc=0 |

63. LINK precedence: lld puts _LINK_'s words first, then LINK's, then
    zig's arguments; the last /OPT: wins.
    `_LINK_="/OPT:NOICF /VERBOSE" LINK=/OPT:ICF zig cc ...` prints
    "Command line: lld-link /OPT:NOICF /VERBOSE /OPT:ICF -lldmingw ...",
    and the addrsig error returns (decision W26).
64. Without clear_cache.o, `zig cc -target aarch64-windows-gnu -shared`
    of a `__builtin___clear_cache` call fails: "lld-link: error:
    undefined symbol: __clear_cache". link-objects-test.sh now covers
    chore-release-11 finding 36's manual test.
65. CMake treats rzig's -idirafter directories as implicit include
    directories: with a g++ wrapper adding `-idirafter <tree>/include`,
    CMake 4.4 (stress env) listed it in
    CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES and the compile line had no
    -I for it. So a find_path that lands in <tree>/include adds no -I.
66. Side finding (this record, from reading build.zig): r-zig.cmake
    appends the tree after the environments, so CMake's find_* prefer
    an environment's copy, while PKG_CONFIG_PATH prefers the tree's
    closed .pc (W6). A CMake package and a pkg-config package may bind
    different copies of a library both have. Not tested.
67. Review item 6: "ICF folds nothing" was stated generally. A small C++
    template DLL (std::vector, std::map, std::sort, class templates),
    lld /VERBOSE, both arches, both zigs: ICF folded no function, DLL
    sizes equal with and without /OPT:NOICF; on aarch64 it merged one
    string constant (".str.12" into ".str"). Logs next/fix-winarm/icf.
    Not verified: a large C++ package.
68. Mixed links with the tree first (next/impl-winarm/mix/run-all.sh;
    rerun after the fixes in next/fix-winarm/mix): aarch64-windows-gnu,
    rzig's order and importLib rule, clear_cache.o from
    `zig build object`, _LINK_=/OPT:NOICF, -shared -s, against all 98
    packages of pixi.lock's win-arm64 stress env, zig cc for C-only
    packages. All 14 rc=0 with both zigs: nloptr (c++), gsl (cc), Rmpfr
    (cc), units (c++), hdf5r (cc), ncdf4 (cc, netcdf libcurl), igraph
    (c++, libxml-2.0 glpk), RPostgres (c++), gdalraster (c++), sf (c++,
    gdal geos proj), terra (c++, + -ltbb12), textshaping (c++), tbb,
    magick (c++, Magick++). With tree-first, every module both have
    (libxml-2.0, libcurl, freetype2, fribidi, proj, geos, glpk) resolves
    to the tree's closed .pc (pkgconf --path). With the env's .pc dir
    first instead (next/impl-winarm/mix/out-condafirst, conda-forge zig
    only, three rows): ncdf4 fails, "error:
    D:/bld/curl_split_recipe_1791990675856/_h_env/Library/lib/z.lib:
    file not found"; sf fails looking for proj_9 (proj.pc -lproj_9:
    "unable to find dynamic system library "proj_9""); igraph links,
    with lld "warning: .../Library/lib/xml2.lib: skipping imported
    DllMain symbol [importeddllmain]". Not run conda-first: upstream zig
    and the other 11 rows.
69. Review item 1 (high): verify-bundle.sh's `_LINK_=/VERBOSE` through
    MSYS2 bash's `env -i`. MSYS2 converts environment values that look
    like POSIX paths when it starts a native program (MSYS2_ENV_CONV_EXCL
    exists for this), so lld could read a Windows path as an input
    file. Not reproduced (no Windows). Resolution: decision W18. On
    linux, `_LINK_='/OPT:NOICF -verbose' zig cc -target <arch>-windows-gnu
    -shared -s` prints "Command line: lld-link /OPT:NOICF -verbose
    -lldmingw ...", rc=0, both arches. lld read `-verbose` inside
    _LINK_ natively on kappa (finding 79).
70. Review item 2 (medium): header/archive version skew, confirmed. A C
    file with `_Static_assert`s on the versions, compiled with the
    closed .pc Cflags and rzig's order (-idirafter env, then tree),
    failed on: GEOS minor 15 (conda 3.15.0) != 14 (tree 3.14.1); PROJ
    minor 9 (conda 9.9.0) != 7 (tree 9.7.1); SQLite 3054001 (conda
    3.54.1) != 3051002 (tree 3.51.2); libtiff 20260627 (conda 4.7.2) !=
    20250911 (tree 4.7.1). zlib headers are in both too. Resolution:
    decision W15. include-pinned has 1002 entries (24,973 files), 141 MB on gamma. After
    the fix the same C file and a C++ variant (<cstddef>, <string>)
    compile and link with both zigs, the 14 mixed links still give rc=0,
    and the Libs lines of the 451 .pc files are byte-identical to before
    (paths aside). Not verified: a real sf or terra source (needs
    Windows R headers and Rcpp); a package that asks pkg-config for a
    tree module but links an env library by a bare -l now gets the
    tree's header of that library.
71. Review item 3 (medium): any tree failure stopped the whole
    windows-11-arm leg with a harness error, and CI had no switch to
    turn it off. Resolution: decision W14. Tested on linux with the
    Windows block and a failing rtools_libs (next/fix-winarm/fail-test.R:
    no pkgconf and a failing download): no harness error,
    R_ZIG_FALLBACK_SOFT unset, the reason in info$rtools_libs. The cache
    step saves after a successful job; a stress job succeeds unless the
    harness fails, so a run without the tree still ends green. Evidence
    for the job status, from the code only: stress.R:906
    `quit(status = if (flag("strict") && any(res$unexpected)) 1 else 0)`,
    harness_error() quits with status 2 (stress.R:508-512), and
    stress.yaml (header, lines 5-10) passes no --strict. Not verified:
    no stress run of this branch exists.
72. Review item 4 (low): the tree's lib/ has import libraries for DLLs
    it does not install: libomp.dll.a,
    libboost_{charconv,chrono,system,thread}-mt-a64.dll.a,
    libclang.dll.a, libeigen_{blas,lapack}.dll.a, libLTO.dll.a,
    libRemarks.dll.a. importLib took a lib<n>.dll.a from any -L dir.
    Confirmed. Resolution: decision W16; unit test (compiler.zig):
    `-lomp` and `-lboost_thread-mt-a64` with only the tree's import
    libraries stay `-l`, the env's import library is still taken by
    path. lib<n>.a in the tree still stops zig's search, as before. The
    tree's MinGW import archives (libws2_32.a, libkernel32.a, libucrt.a)
    are fine: zig's .def handling takes those names first.
73. Review item 5 (low): the fallback warning printed on every list()
    call (envFlags, then the trace). Confirmed under RZIG_TRACE.
    Resolution: decision W17; unit test: two list() calls on x86_64
    Windows give one warning.
74. Review item 6 (low): see finding 67. Resolution: windows.zig's noIcf
    doc and chore-release-11 finding 35 now say only what was tested.
75. Review item 7 (low, cosmetic): pkg-parity.sh's sed missed a quoted
    _LINK_ value. Resolution:
    `s/^(zig-(cc|cxx|fc): )(([A-Z_]+)=('[^']*'|[^ ]*) )+/\1/`, checked
    on quoted, unquoted and plain lines.
76. Review info item: link-objects-test.sh costs about 2-2.5 min cold
    per linux build-r leg (setup-pixi runs with cache:false). Not a
    defect; the CI times are to be read on the first CI run.
77. Pre-existing, not from this branch: zigbuild/tools/rzig/makefile.zig
    fails `zig fmt --check` at d65f1db; under `pixi run`, `zig build -l`
    stops at a cairo hash mismatch in build.zig.zon at d65f1db.
78. The review found the Zig logic sound: noIcf runs only on Windows
    image links; `env_set` reaches only zig's processes in run and
    runSteps; tier 1 and tier 2 links go back through rzig and get
    /OPT:NOICF; nothing else in rzig changes ctx.env; the fallback is
    always last in list() and openmp() skips it; both cmakeToolchain
    call sites pass the arch.

### Added after the record audit (2026-11-18)

79. lld inside conda-forge zig.exe 0.17.1 reads _LINK_ on Windows
    (kappa, win-64, 2026-11-18, run by Claude in the main session, not
    by this branch's agents). In cmd.exe, `zig cc -target
    x86_64-windows-gnu -shared -s` with `_LINK_=/OPT:NOICF /VERBOSE`
    printed "Command line: lld-link /OPT:NOICF /VERBOSE -lldmingw ...
    -MACHINE:X64 -DLL ...", with no "ICF needed" line, rc=0. With
    `_LINK_=-verbose` alone, lld printed "ICF needed 2 iterations", so
    ICF is on by default with -s, natively too (finding 10). With
    `_LINK_=/OPT:NOICF -verbose`, lld also read the dash form ("Command
    line: lld-link /OPT:NOICF -verbose ..."). With no _LINK_, rc=0. Not
    run: through rzig's gcc.exe, under MSYS2 bash, on win-arm64, or
    with upstream zig on Windows. Scratch C:\Users\admin\rz-icf was
    removed. (2026-11-19) Now also verified through rzig's gcc.exe,
    under MSYS2 bash, on win-64 and win-arm64, with both zigs
    (finding 82).
80. Scope of the x86_64 repro (critic G8 of the icf probe plan): on
    win-64 textshaping uses conda-forge's harfbuzz and freetype, not the
    r-windows clang-x86_64 bundle, so the x86_64 repro (findings 12, 62)
    matches no failing row and no windows= (x86_64) expect changes.
    magick on Windows x64 uses a gcc-built bundle (packages.tsv magick
    note), so NOICF changes nothing there. Not verified: read from the
    critic and packages.tsv, no Windows run.

### CI on fd44749 (2026-11-19)

81. build-r run 44450920834 on fd44749 (PR #50, no labels, core
    tier): 20 jobs success, one matrix placeholder skipped (the full
    tier needs the full-ci label). upstream-zig run 44450920934 was
    skipped (no label). Not verified: these job results were given to
    this record step; the job logs are not under next/.
82. verify-bundle.sh's ICF check passed natively on both Windows
    runners, in both passes. Job 135319558860 (windows-latest,
    default) and job 135319558940 (windows-11-arm, default) each
    printed "== lld's ICF off: a stripped DLL link by gcc.exe hands
    zig _LINK_='/OPT:NOICF -verbose', and lld-link reads it (zig from
    TC/zig)" and the same line "(zig from ZIG_BIN=...)", with
    x86_64-w64-mingw32-zig.exe and aarch64-w64-mingw32-zig.exe. The
    RZIG_TRACE lines show "zig-cc: _LINK_=/OPT:NOICF '...zig.exe' cc
    ..." on both. TC/zig is R_HOME/bin/toolchain/zig/zig, the
    compilers group's zig: upstream zig, PyPI's ziglang 0.17.1 wheel
    (verify-bundle.sh's header, the toolchain pass, no ZIG_BIN).
    ZIG_BIN= is the build pass: env.sh's $ZIG, the default env's
    conda-forge zig 0.17.1. The script fails the step unless lld
    prints "Command line: lld-link /OPT:NOICF -verbose ..." and the DLL
    exists. So lld inside zig.exe reads _LINK_ natively on win-64 and
    win-arm64, with upstream and conda-forge zig, when rzig's gcc.exe
    starts zig with an explicit environment, under MSYS2 bash, with
    the dash form. This closes the open part of findings 47 and 79.
    Not verified: a native link of objects with a broken .llvm_addrsig
    (finding 84); the job logs are not under next/ (lines as given to
    this record step).
83. Stress run 44450918935 on fd44749 (2026-11-19): windows-11-arm
    and windows-latest, tree and conda legs, channel local, trace on,
    19 targets (units gsl Rmpfr nloptr hdf5r ncdf4 igraph RPostgres
    systemfonts textshaping ragg gdalraster terra sf lwgeom lme4 scran
    Rsamtools magick). Reports: next/stress-44450918935/stress-*/
    report.md, report.json and logs/.
    windows-11-arm, both legs (tree 48.1 min, conda 49.4 min): "Fallback:
    Rtools45 tree rtools45-toolchain-libs-full-aarch64-6768.tar.zst
    (sha256 64dceac9ecdd) ...; sysdeps from it: glpk gmp gsl harfbuzz
    hdf5 libgdal-core libnetcdf libpq mpfr nlopt udunits2; rzig uses it
    (R_ZIG_FALLBACK_SOFT); PKG_CONFIG_PATH: the tree's closed .pc
    first." "Targets: 17 ok, 2 skipped. Unexpected (!): 1.
    Dependencies: 1 install-failed, 88 ok." "Sysdeps missing from the
    env: imagemagick." The conda leg used r-zig-slim and
    r-zig-toolchain 4.6.2 _11 from dist/conda (channel local), so the
    --conda leg works with an rzig that reads R_ZIG_FALLBACK_SOFT.
    Rows (both legs the same; each smoke log has "stress: smoke ok"):

    | Row | Expect before | Result | Smoke output |
    | --- | --- | --- | --- |
    | units | ? | ok | TRUE |
    | systemfonts | ok | ok | (unchanged row) |
    | textshaping | ? | ok | 3 (finding 84) |
    | ragg | fail-dependency | ok, the one unexpected row | TRUE (finding 84) |
    | magick | ok | ok | '6.9.13.29' (finding 86) |
    | hdf5r | ? | ok | TRUE |
    | ncdf4 | ? | ok | netcdf library version 4.9.2 |
    | gsl | ? | ok | 0.7651977 |
    | Rmpfr | ? | ok | 0.3333...3346 |
    | RPostgres | ok | ok | (unchanged row) |
    | nloptr | ? | ok | 2 |
    | igraph | ? | ok | 10 |
    | Rsamtools | ? | ok | TRUE (finding 87) |
    | sf | ? | skipped: failed dependency s2 | - |
    | lwgeom | ? | skipped: failed dependency sf s2 | - |
    | terra | ? | ok | 2 |
    | gdalraster | ? | ok | GDAL 3.12.1 "Chicoutimi" |
    | lme4 | ? | ok | Days 10.46729 |
    | scran | ? | ok | TRUE |

    windows-latest, both legs (tree 33.5 min, conda 20.3 min): "Targets:
    5 install-failed, 10 ok, 4 skipped. Unexpected (!): 0." Every row
    matched its expect: hdf5r fail-package (Wrapper_auto_H5P.c
    'off_t *' to 'HDoff_t *'), gsl fail-upstream (LoadLibrary
    'procedure could not be found'), igraph fail-sysdep
    ('libxml/globals.h' not found), Rsamtools fail-dependency (Rhtslib:
    'regex.h' not found), terra fail-sysdep ('tbb/parallel_for.h' not
    found), gdalraster fail-abi ('gdal: unrecognized file extension'),
    scran fail-dependency; sf and lwgeom skipped on s2 (expect ?). The
    conda leg also had download failures of SingleCellExperiment and
    beachmat ("download.packages failed 3 times", network); scran's
    outcome is the same. No Fallback line on windows-latest (the tree
    is aarch64 only, W21).
    packages.tsv updated (W28). Not verified: run time beyond each
    row's one-line smoke (finding 88).
84. textshaping and ragg on windows-11-arm took the tree's libraries,
    not r-windows' clang-aarch64 bundle: textshaping's configure
    printed "using harfbuzz freetype2 fribidi from Rtools" and its link
    names the tree's libharfbuzz.a, libfreetype.a and libfribidi.a;
    ragg's printed "using freetype2 libpng libtiff-4 libjpeg libwebpmux
    libwebp from Rtools". So this run did not link the bundle's
    libfreetype.a with its broken .llvm_addrsig (finding 12), and it
    does not show /OPT:NOICF fixing that link natively. Every traced
    image link had `_LINK_=/OPT:NOICF` (textshaping.log, magick.log).
    The addrsig fix stays verified by the cross link from linux
    (findings 12, 62) and the native _LINK_ check (finding 82).
85. s2 (a dependency of sf) failed on all four Windows legs, for two
    different reasons (logs/s2.log of each leg):
    - windows-latest tree: configure.win's pkg-config gave
      "-LD:/a/.../envs/stress/Library/lib -ignore:4221 -labseil_dll"
      (conda-forge's libabseil 20260817, an MSVC C++ DLL) and printed
      "Using Abseil from RTools via pkg-config". But the s2.dll link
      line (s2.log:1001) has no abseil library, not -labseil_dll
      either: only -llibssl -llibcrypto -lR -lws2_32. During make,
      pkg-config for absl_s2 printed "Package absl_base was not found
      in the pkg-config search path" (4 times), as on windows-11-arm
      below. Then 84 lines "lld-link: error: undefined symbol:
      absl::lts_20260817::log_internal::LogMessage::LogMessage(...)",
      class abi. So in this run it is the same make-time lookup
      failure, not a link against conda's MSVC abseil_dll. Corrected
      by the verify step (2026-11-19); the writer had recorded it as
      the 2026-11-15 cause.
    - windows-latest conda: the conda env has no abseil, so s2 builds
      its bundled abseil with CMake through rzig and stops at
      "time_zone_lookup.cc:51:10: fatal error: 'windows.globalization.h'
      file not found" (class sysdep; zig's MinGW headers, Z12 in the
      s2 row).
    - windows-11-arm, both legs: configure.win printed the tree's
      archives (libabsl_base.a, libabsl_raw_logging_internal.a,
      libabsl_log_severity.a, libabsl_spinlock_wait.a) and "Using
      Abseil from RTools via pkg-config". Then, during make, pkg-config
      for absl_s2 printed "Package absl_base was not found in the
      pkg-config search path" and "Package 'absl_base', required by
      'absl_s2', not found" (4 times). The s2.dll link line has no
      abseil library at all, only the tree's libssl.a, libcrypto.a,
      libz.a and -lws2_32 -lgdi32 -lcrypt32. lld-link: undefined absl
      symbols (78 lines conda leg, 84 tree leg), classed abi. The
      mangled names differ: lts_20250127 on the conda leg, lts_20260817
      on the tree leg, where rzig's -idirafter puts the stress env's
      include (conda-forge libabseil 20260817 headers) before the
      tree's. So on the tree leg the headers were conda-forge's and the
      archives would have been the tree's.
    So the failure on windows-11-arm and on the windows-latest tree leg
    is not conda-forge's MSVC abseil: it is a pkg-config lookup that
    works in configure.win and fails in make, and the link then has no
    abseil library. Not verified: why the make-time lookup misses absl_base
    (PKG_CONFIG_PATH in make, or a different pkg-config there; s2's
    Makevars.ucrt was not read); that s2 links once it gets the tree's
    absl_* archives; the tree's abseil version (lts_20250127 is read
    from the conda leg's symbols only).
86. magick on windows-11-arm: ok on both legs, smoke "[1] '6.9.13.29'".
    Its traced link has `-s`, the bundle's -lrsvg-2 and -lffi, and
    clear_cache.o (chore-release-11 finding 36). Not verified: an SVG
    render, so CFG code still has not run on Windows on ARM.
87. Rsamtools on windows-11-arm: Rhtslib compiled hts_expr.c (no
    'regex.h' error; the log does not name which regex.h, so the tree's
    is inferred) and links -lregex (3 times in Rhtslib.log), so htslib's
    missing regex.h (the windows=fail-dependency cause) is filled by
    the tree on aarch64. windows-latest has no tree and still fails
    there.
88. What the run does not cover: run time of the tree's libraries
    beyond each row's one-line smoke (C++ exceptions across the tree's
    LLVM 19 libc++ and zig's clang 22 libc++, proj.db from
    R_TOOLS_SOFT, HDF5 1.12.1 beyond creating a file); the windows-11-arm
    rows outside these 19 targets; --no-rtools-libs on windows-11-arm;
    upstream zig building packages on Windows (upstream-zig run
    44450920934 skipped; only verify-bundle's one DLL link, finding
    82); the full CI tier. Which extractor ran (cmake -E tar or
    System32 tar.exe), its time, and the actions/cache step are not in
    the reports.

## What changed

### Part 1: ARM64 Control Flow Guard needs no stub (findings 1-9, 41-46)

- On aarch64, clang's CFG calls only the check function, through
  `__guard_check_icall_fptr` (target in x15). zig 0.17.1's libmingw32
  defines that pointer for aarch64, aimed at a function that only
  returns. So an aarch64 `-mguard=cf` DLL links with no stub, with both
  zigs. It links and is a no-op: a MinGW image has no load config, so
  CFG is not enforced. x86_64 still needs cfguard.o.
- zigbuild/tools/rzig/build.zig: a new `object` step installs only the
  link object for -Dtarget, so a test can link with it without a
  minutes-long cross-build of rzig.
- zigbuild/tools/rzig/link-objects-test.sh (new): for x86_64 and aarch64
  windows-gnu, compiles a CFG file, links a DLL with the arch's object
  (cfguard.o, clear_cache.o), then without it. aarch64 must link
  without it; x86_64 should fail without it, and a link prints a WARNING
  and passes (W2). It also links an aarch64 DLL that calls
  `__builtin___clear_cache` with clear_cache.o. It tests zig and the
  object, not rzig's choice of the object; its header says so. It uses
  test.sh's zig cache; only its outputs go in mktemp.
- test.sh runs it on linux after parity-test.sh, with or without a
  prefix.
- Comments: cfguard.zig, objects/cfguard.zig, compiler.zig, rzig's and
  the repo's build.zig (linkObject docs), parity-test.sh, test.sh and
  pixi.toml's rzig-test comment.
- Records: feat-win-arm64/PLAN.md (open item closed),
  chore-release-11/PLAN.md (the "Not needed" entry),
  feat-win-zig-binutils/PLAN.md (two lines), stress/packages.tsv (magick
  note: its clang-aarch64 librsvg-2.a uses CFG and links with no stub).

### Part 2: lld's ICF off on Windows image links (findings 10-17, 47-48, 62-63, 67, 69)

- windows.zig `noIcf`: puts /OPT:NOICF first in _LINK_ (the caller's
  words after it, once). compiler.zig calls it on every Windows image
  link (the cfguard.wanted block). Ctx.zig `env_set` lists the variables
  rzig set; main.zig then hands its environment to zig, and RZIG_TRACE
  shows `_LINK_=<value> ` before zig's line. RZIG_PRINT_ARGV is
  unchanged (W25); main.zig's header says so. LINK is left alone (W26).
- scripts/verify-bundle.sh (Windows block, both passes): a real
  stripped DLL link by gcc.exe with `_LINK_=-verbose RZIG_TRACE=1` must
  show `_LINK_='/OPT:NOICF -verbose' ` in the trace, lld's "Command
  line: lld-link /OPT:NOICF -verbose ...", and the DLL (W18). This is
  the native Windows check of rzig spawning zig with an explicit
  environment and of lld inside zig.exe reading _LINK_.
- The noIcf unit test is not under a Windows skip, so build-r.yaml's
  rzig-test runs it natively on win-64 and win-arm64.
- smoke-test.sh's display grep and pkg-parity.sh's trace sed accept the
  prefix.
- chore-release-11/PLAN.md finding 35 is edited in place.
  stress/packages.tsv: textshaping windows-aarch64 is `?` until a
  windows-11-arm run; ragg keeps fail-dependency, with a note.
  (2026-11-19: both ok on windows-11-arm, through the tree's
  libraries, findings 83-84.) R.dll is
  not stripped on Windows, so build.zig needs no change.

### Part 3: CRAN's Rtools45 aarch64 libraries as a fallback (findings 18-40, 49-61, 65-66, 68, 70-73)

- rzig: `R_ZIG_FALLBACK_SOFT` (environment.zig `fallback`), aarch64
  Windows targets only (W21); elsewhere ignored with one warning per
  command (W17, Ctx.fallback_soft). list() appends it last, after R's
  env, openmp/ and R_ZIG_EXTRA_ENV. envFlags gives
  `-idirafter <tree>/include` and `-L<tree>/lib`, never -I. openmp()
  skips it (W23). importLib takes no lib<n>.dll.a or lib<n>.lib from the
  tree's lib/ (W16). RZIG_TRACE marks it `environment <tree> (fallback)`.
  Tests: environment.zig (order, the OpenMP rule, missing dir, x86_64
  Windows and unix ignored with one warning) and compiler.zig (argv on
  aarch64; the real conda names z.lib and libomp.lib in the env with
  libz.a and libomp.dll.a in the tree; the import-library rule).
- build.zig cmakeToolchain: an aarch64 Windows R's etc/r-zig.cmake
  appends R_ZIG_FALLBACK_SOFT's tree to CMAKE_SYSTEM_PREFIX_PATH after
  the environments (W22). verify-tree.sh checks the line on win-arm64.
- stress.R: on by default on Windows aarch64, `--no-rtools-libs` turns
  it off (W9). Pinned file, size and sha256 (finding 18), into
  build/rtools45 (STRESS_RTOOLS_DIR). Extraction of include/, lib/,
  share/gdal, share/proj with `cmake -E tar`, else System32's tar.exe
  (W24). include-pinned and closed .pc files in lib/pkgconfig-closed,
  written with the build-tools group's pkgconf (W8, W15). Stamps: the
  extraction on the sha256; the .pc files and include-pinned on the
  sha256, `zig version` and zig's lib_dir. Modules whose Libs keep an
  unresolvable -l are skipped (finding 40). PKG_CONFIG_PATH: the closed
  .pc dir first, then the current value (or R's default), then the
  env's (W6). R_TOOLS_SOFT is the tree (W7). The sysdeps the tree serves
  leave "Sysdeps missing" (W27). report.md gets a `Fallback:` line: the
  tree, the served sysdeps and whether rzig uses it (`gcc.exe
  --version` under RZIG_TRACE shows `(fallback)`; build 11's rzig
  ignores the variable), or `not used: <reason>` (W14).
- stress.yaml: an actions/cache@v5 step for the tarball on Windows ARM64
  (key rtools45-toolchain-libs-full-aarch64-6768-64dceac9ecdd54aa). No
  new input (W19).
- packages.tsv windows-aarch64: units, hdf5r, ncdf4, gsl, Rmpfr, nloptr,
  lme4, gdalraster are `?`; igraph, scran, terra and Rsamtools get
  `windows-aarch64=?`; sf, lwgeom, RPostgres get notes only (sf and
  lwgeom are windows=? already). Each note says the expected cause.
  Nothing is marked ok (W10). No Rhtslib row exists.
  (2026-11-19) After stress run 44450918935: units, textshaping, ragg,
  hdf5r, ncdf4, gsl, Rmpfr, nloptr, igraph, Rsamtools, terra,
  gdalraster, lme4 and scran are ok on windows-aarch64; sf and lwgeom
  are windows=fail-dependency (s2, finding 85) (W28).
- stress/README.md section "Windows on ARM: the Rtools45 fallback";
  CXX-STDLIB.md paragraph; main.zig doc line; pixi.toml feature.stress
  comment.

## Tests

Run (gamma, linux-64, 2026-11-18):

- Before the review fixes, cold caches: `pixi run rzig-test`
  (conda-forge zig 0.17.1): 216/216 unit tests; parity "116 identical,
  70 identical but for ..., 33 deliberate differences, 0 failed";
  link-objects-test all ok, 121 s; total 6 min 47 s.
  `ZIG_BIN=<ziglang 0.17.1 wheel's zig> pixi run rzig-test`: the same
  counts, link-objects-test 151 s, total 7 min 20 s; warm 32 s.
- After the review fixes, warm caches: `pixi run rzig-test`
  (conda-forge zig): 216/216; parity 116/70/33, 0 failed;
  link-objects-test all ok (1 s); 1 min 22 s. With ZIG_BIN = upstream
  zig: the same counts; 1 min 18 s.
- `zig build test-bin -Dtarget=aarch64-windows-gnu` and
  `-Dtarget=x86_64-windows-gnu`: 6/6 steps each (built, not run).
- `zig fmt --check` on every changed Zig file: clean. `bash -n` on
  verify-bundle.sh, verify-tree.sh, pkg-parity.sh, smoke-test.sh,
  test.sh, link-objects-test.sh: clean.
- stress.R: parse() ok; `--list` (172 lines) and `--sysdeps` (32 lines)
  identical to d65f1db's stress.R on linux, run with a build 11 tree's
  Rscript under `pixi run -e stress` (this worktree has no built R).
- rtools_libs() on linux into next/fix-winarm/rt/a: 1.05 min from the
  tarball (cmake), 0.03 min the second call; 451 closed .pc files, 5
  skipped; include-pinned 1002 entries (24,973 files), 141 MB; every closed .pc has
  the -I.
- The Windows block of stress.R with a mocked R_HOME (pkgconf, cmake,
  zig and a gcc.exe that prints a trace line); the failure path
  (finding 71).
- Cross links: findings 4, 5, 12, 23, 62, 63, 67, 68, 69, 70.

Run (CI on fd44749, 2026-11-19):

- build-r run 44450920834: 20 jobs success, one placeholder skipped
  (core tier) (finding 81). verify-bundle.sh's ICF check passed on
  windows-latest (job 135319558860) and windows-11-arm (job
  135319558940), both passes: upstream zig (TC/zig) and conda-forge
  zig (ZIG_BIN) (finding 82).
- stress run 44450918935, Windows only, tree and conda, channel local:
  windows-11-arm 17 ok, 2 skipped (sf, lwgeom), 1 unexpected (ragg ok);
  windows-latest 10 ok, 5 install-failed, 4 skipped, 0 unexpected
  (findings 83-87).
- packages.tsv after W28: tab field counts unchanged (31 lines of 1
  field, 45 of 10); stress.R's expected() on the old and new file
  (Windows aarch64 and x86_64, linux, macOS) differs only in the
  intended values; `pixi run --frozen -e stress <feat-linux-libstdcxx's
  compile tree>/bin/Rscript stress/stress.R --list`: rc 0, 172 lines
  (gamma). No stress build was run for this.

Not run (2026-11-18 list; see above for what CI ran since): any CI workflow; anything on Windows by this branch's agents
(finding 79 is a separate native check by Claude); the repo's build.zig
after the cmakeToolchain change: only rzig's own build and test-bin
were built (the reviewer's zig build test-bin, both Windows targets).
No log under next/impl-winarm or next/fix-winarm shows a build of the
repo's build.zig.

## Not verified

Everything Windows-native, except the direct zig cc check of
finding 79, the CI checks of finding 82 and the stress rows of findings
83-87 (2026-11-19). In particular:

- Running CFG code on Windows on ARM (an SVG render smoke in magick's
  stress row on windows-11-arm would close it); Rust CFG objects other
  than this librsvg-2.a, ARM64EC, MSVC /guard:cf libraries.
- upstream zig building packages on windows-11-arm (and win-64): the
  upstream-zig workflow was skipped (run 44450920934, no label); only
  verify-bundle's one stripped DLL link ran natively with upstream zig
  (finding 82). The full CI tier has not run on this branch.
- /OPT:NOICF on a native link of r-windows' clang-aarch64 objects with
  a broken .llvm_addrsig: textshaping and ragg took the tree's freetype
  and harfbuzz instead (finding 84).
- windows-11-arm stress rows outside the 19 targets of run 44450918935,
  and every row without the tree (--no-rtools-libs). Tree-first
  PKG_CONFIG_PATH gives xml2, curl, systemfonts, ragg and others the
  tree's static copies, and `-idirafter <tree>/include` exposes
  dlfcn.h, regex.h, iconv.h and libintl.h to configure probes; seen so
  far only in the rows of finding 83 (regex.h for Rhtslib, finding 87).
- s2 on windows-11-arm and the windows-latest tree leg: why the
  make-time pkg-config misses absl_base, and whether s2 then links
  (finding 85); sf and lwgeom wait on it.
- R_TOOLS_SOFT=tree side effects in Makevars not read (gert, stringi,
  qs2, fst, Rhdf5lib, V8, duckdb, mlpack, rstan, DESeq2, systemfonts,
  geos, Rsamtools).
- Run time of the tree's libraries beyond each row's one-line smoke
  (finding 88): C++ exceptions and layout across the tree's LLVM 19
  libc++ and zig's clang 22 libc++ (gdalraster, terra and Rmpfr load
  and pass their smokes); the tree's libomp import against conda's
  libomp 23; proj.db from R_TOOLS_SOFT; HDF5 1.12.1 with hdf5r beyond
  creating a file.
- A real sf or terra compile with include-pinned; a bare -l of an env
  library next to a tree module's header; CMake and pkg-config binding
  different copies (finding 66).
- Which extractor ran on the runner (cmake's zstd or System32
  tar.exe) and the time of the extraction and the include-pinned copy.
  That they work on the runner is shown: both windows-11-arm legs
  report the tree ready, and links name its archives by C:/ paths from
  the closed .pc files (finding 83).
- conda-forge's libcurl.pc and proj.pc bugs in a Windows R CMD INSTALL
  (tree-first avoided them on windows-11-arm); sf on windows-latest at
  this lock (not reached: s2). ncdf4 (ok) and terra (fail-sysdep) ran
  there (finding 83).
- Whether R's real make paths behave as the linux simulation did:
  Makevars.ucrt selection, $(shell pkg-config ...) under R CMD's PATH
  (the build-tools pkgconf first), and PKG_CONFIG_PATH as stress.R sets
  it compared with pixi's activation on Windows. (2026-11-19) On
  windows-11-arm they did for the 17 rows that installed; s2's
  make-time pkg-config missed a module its configure.win found
  (finding 85).
- actions/cache@v5: no other workflow here uses actions/cache, so the
  major is not checked against this repo's pins.
- CI time of link-objects-test.sh on ubuntu-latest and
  ubuntu-24.04-arm; cross-linking for Windows from linux-aarch64.
- The --conda leg needs an rzig with R_ZIG_FALLBACK_SOFT: channel local
  only (universe's build 11 ignores it; the Fallback line says so).
  With channel local it works (finding 83); universe's build 11 with
  the tree was not run.
- R_ZIG_FALLBACK_SOFT is not documented for wheel or standalone users
  (W12).

## Cleanup (2026-11-18)

- C1. Scratch on the test hosts.
  Choice: delete omicron `~/.pixi/rz-rel11b` (15 GB) and kappa
  `C:\Users\admin\rz-rel11b`.
  Who: user, 2026-11-18 ("all of it"); done by Claude the same day.
- C2. Gamma worktrees.
  Options: (a) keep them; (b) remove all except feat-userland,
  feat-linux-libstdcxx and feat-winarm-gaps, first saving each dirty
  one's diff and untracked files to a backup; (c) remove them without a
  backup.
  Choice: (b).
  Reason: their work shipped in build 11.
  Who: the removal is the user's, 2026-11-18 ("all of it"); the backup
  step is a default chosen by Claude, which the user may revisit.
  Status: not yet done. On 2026-11-18 `git worktree list` still shows
  21 worktrees under wt/ besides the three kept ones (and the main
  checkout); no backup path is chosen yet.
