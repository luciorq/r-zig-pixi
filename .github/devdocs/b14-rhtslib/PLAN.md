# b14-rhtslib: Rhtslib's regex.h on Windows

Build 14, on origin/main 77abec1 (worktree build14, lock with
zig-libcurl build 1: win-64 `zig_38b206d_1`, win-arm64
`zig_12f6e5a_1`). First a research track (F1-F12, D1); after the user's
decisions U1-U3, the fallback track (F13-F22, D2-D13): rzig's drop of
Rtools' unresolved curl-closure names (U2) and the retirement of
`R_ZIG_FALLBACK_SOFT` and the stress Rtools45 tree (U3).

## Goal

- Why Rhtslib (Bioconductor 3.8.0, bundled htslib 1.18) fails on
  Windows: which file needs `regex.h`, and why.
- What CRAN's Rtools45 tree provides for it.
- Why win-64 fails with and without the "tree" leg.
- Options to serve it without the Rtools45 tree, with an owner.
- What retiring `R_ZIG_FALLBACK_SOFT` needs (b13-slice2 PLAN.md D6, F4,
  "Not covered").
- Fallback track: U2 in rzig (windows.zig) with unit tests and a link
  test; U3 everywhere F12 lists; every remaining mention resolved or
  left as history (F22); the note to libs-zig-pixi on CONTRACT.md
  section 6 (drafted below, not sent).

## Findings

- F1 (V) Logs of stress 45714066676 (S1, Rtools45 tree on arm) and
  45714071892 (S3, `rtools_libs=false`), `gh run download` on gamma,
  `logs/Rhtslib.log` per leg:

  | run | leg | Rhtslib first error |
  |---|---|---|
  | S1 | windows-latest conda | `hts_expr.c:37:10: fatal error: 'regex.h' file not found` |
  | S1 | windows-latest tree | same |
  | S1 | windows-11-arm conda | `lld-link: error: undefined symbol: if_nametoindex` (zig-libcurl build 0; F23) |
  | S1 | windows-11-arm tree | same |
  | S3 | windows-11-arm conda | `'regex.h' file not found` |
  | S3 | windows-11-arm tree | same |

  Rsamtools is `skipped` (`failed dependency: Rhtslib`) on all six.
- F2 (V) The only user of `regex.h` in htslib 1.18 is `hts_expr.c`
  (`grep -rn regex` in `src/htslib-1.18`, Rhtslib_3.8.0.tar.gz from
  bioconductor.org/packages/3.23): an unconditional `#include <regex.h>`
  at line 37 and `regcomp`/`regexec`/`regerror`/`regfree` for the filter
  expression `=~` operator. It is not optional: no `HAVE_REGEX` guard in
  `config.h` or `Makefile.Rhtslib.win`. zig's MinGW headers
  (any-windows-any) have no `regex.h`, so every zig build of Rhtslib on
  Windows stops here unless something on the include path has it.
- F3 (V) The link side is hard-coded too. `src/Makevars.win` and
  `R/zzz.R` `pkgconfig("PKG_LIBS")` (which Rsamtools and other
  LinkingTo packages use) both write Rtools45's static libcurl closure:
  `-lm -lbz2 -llzma -lcurl -lsecur32 [nghttp2 psl brotli if
  $(R_TOOLS_SOFT)/lib has them] -lbcrypt -lidn2 -lunistring -liconv
  -lssl -lcrypto -lz -lcrypt32 -lwsock32 -lwldap32 -lssh2 -lgcrypt
  -lgpg-error -lws2_32 -lzstd -lregex`. `Makefile.Rhtslib.win`'s
  `htslib_default_libs` is the same list.
- F4 (V) Where each `-l` bound on S1 windows-11-arm tree (rzig trace in
  Rhtslib.log): zig-libs: curl, ssl, crypto, z, bz2, lzma, zstd, iconv,
  brotlidec, brotlicommon; zig itself: m, bcrypt, crypt32, secur32,
  wldap32, ws2_32, wsock32; conda-forge's `libssh2.lib` (env): ssh2; the
  Rtools45 tree: **regex, idn2, unistring, gcrypt, gpg-error**. Only
  `regex` is needed by a symbol (hts_expr.o); zig-libcurl is Schannel
  with WinIDN, libidn2/libssh2/libpsl/nghttp2 off (libs slice2 PLAN.md
  S2-F32), so the other four are names only.
- F5 (V) The Rtools45 tree serves regex with MXE's libgnurx, in the
  "base" tarball (so in "full" too). `curl .../rtools45-toolchain-libs-
  base{,-aarch64}-6768.tar.zst | zstd -dc | tar -tv` (gamma): both
  arches have `include/regex.h` (22162 bytes, 2015-12-17),
  `lib/libregex.a` (x64 93148, arm64 97090 bytes), `lib/libgnurx.a` a
  hard link to it, and `installed/libgnurx`. No TRE, no libsystre. The
  base tarball also has libidn2.a, libunistring.a, libgcrypt.a,
  libgpg-error.a, libssh2.a, libnghttp2.a, libpsl.a.
- F6 (V) Why win-64 fails even on the "tree" leg: "tree" is the R
  install kind (the compile tree vs the conda package), not the Rtools45
  tree. stress.R uses the Rtools45 tree only `if (win && arch ==
  "aarch64" && !flag("no-rtools-libs"))` (stress.R ~line 770), and rzig
  ignores `R_ZIG_FALLBACK_SOFT` off aarch64 (environment.zig
  `fallbackDir`). The win-64 compile lines in S1 have `-idirafter` only
  for the toolchain's openmp, zig-libs and the env: nothing has
  `regex.h`. So win-64 has always failed (packages.tsv Rsamtools
  `windows=fail-dependency`, stress 43947228208), and win-arm64 passed
  only through the tree (stress 44450918935).
- F7 (V) conda-forge has no usable provider (`pixi search -c
  conda-forge`, gamma, win-64 and win-arm64): no libgnurx, tre, libtre,
  libsystre; only `m2w64-libsystre 1.0.1-3` on win-64 (MSYS2 2016
  epoch, depends on m2w64-libtre-git, no win-arm64). pcre2 has
  `pcre2posix.h`, not `regex.h`, and its library is not `-lregex`.
- F8 (V) Prototype on delta (zig 0.17.1, `~/rz/base` default env):
  libgnurx 2.6.1 (github.com/TimothyGu/libgnurx release, the source
  MXE's libgnurx.mk pins, sha256 ee6edc11...612c7; its `regex.h` is
  22162 bytes, the size of Rtools45's) built with `zig cc -target
  {x86_64,aarch64}-windows-gnu -O2 -std=gnu99 -c regex.c` (19
  K&R-prototype warnings, no error) and `zig ar rcs libregex.a`; a test
  program with `regcomp`/`regexec` links to a PE32+ exe on both arches.
  htslib 1.18 `hts_expr.c` (`-std=gnu2x -D_FILE_OFFSET_BITS=64`, the
  flags of the stress log): without the header `'regex.h' file not
  found` (the CI error, reproduced); with `-idirafter <prefix>/include`
  it compiles on both arches. Not run: the exe (no Windows host in this
  track).
- F9 (V) Same delta session: linking with Rhtslib's full Windows `-l`
  list and only libregex.a on `-L`, zig stops with `unable to find
  dynamic system library` for exactly idn2, unistring, gcrypt,
  gpg-error, ssh2 (both arches; ssh2 only resolves in the stress env
  because conda-forge libssh2 is there). With empty archives
  `lib{idn2,unistring,gcrypt,gpg-error,ssh2}.a` on `-L` the link
  succeeds on both arches. So regex alone does not unblock Rhtslib
  without the tree: the five names must resolve too.
- F10 (V) S3 report.md, windows-11-arm conda and tree legs without the
  tree: every non-ok row other than Rsamtools is an expected
  fail-package (protolite, arrow, rstan smoke); magick, V8,
  RcppParallel (`-lssp`, b13-slice2 F3) and nanoarrow are ok. This
  confirms b13-slice2 F4/F12: Rhtslib (and Rsamtools behind it) is the
  only thing the tree still serves.
- F11 (V) libs-zig-pixi's view (libs-select b00cc44, slice2 PLAN.md
  S2-F35): "On win-64, Rhtslib still fails earlier (regex.h not found)
  and on win-arm64 without the tree too: r-zig-pixi's, not a zig-*
  library." CONTRACT.md section 6 names `R_ZIG_FALLBACK_SOFT` as part of
  the consumer side, so retiring it is a contract change (section 8).
- F12 (V) Footprint of `R_ZIG_FALLBACK_SOFT` and the stress tree on
  77abec1 (`git grep -c`, devdocs excluded): stress.R 23 lines,
  packages.tsv 22, stress/README.md 10, stress.yaml 7 (input
  `rtools_libs`, the tarball cache step, `--no-rtools-libs`), rzig
  environment.zig 14, compiler.zig 3, main.zig 1, windows.zig 1,
  build.zig 5 (the `etc/r-zig.cmake` block, docs), verify-tree.sh 3,
  README.md 1, recipe.yaml 1. pixi.toml 751-754 is only a comment about
  the tree's protobuf.
- F13 (V) Rtools45's libcurl closure. `rtools45-toolchain-libs-base{,-aarch64}-6768.tar.zst`
  downloaded again on gamma (sha256 96ee3f41...24cc4 x64, 8ca25e5d...04d61
  aarch64), `lib/pkgconfig/libcurl.pc` extracted: both arches have the
  same `Libs`/`Libs.private`, whose distinct names are curl secur32
  nghttp2 idn2 unistring iconv charset wldap32 ssh2 gcrypt gpg-error
  ws2_32 z psl bcrypt advapi32 crypt32 ssl crypto gdi32 zstd brotlidec
  brotlicommon m pthread (Requires: libidn2, zlib, libbrotlidec,
  libbrotlicommon, libzstd, openssl, libpsl, libssh2, libnghttp2).
- F14 (V) zig-libcurl 8.18.0 build 1 (universe, the lock's
  `zig_38b206d_1` and `zig_12f6e5a_1`, unpacked on gamma with the other
  zig-* of Rhtslib's link: zlib, bzip2, xz, openssl, libiconv, zstd,
  brotli): its `libcurl.pc` `Libs: -lcurl -lz -lbrotlidec -lbrotlicommon
  -lzstd -lwldap32 -lnormaliz -lbcrypt -ladvapi32 -lcrypt32 -lsecur32
  -lws2_32`, the same on both arches. zig-libiconv has `libcharset.a`
  too. So of F13's names, zig's MinGW import libraries serve secur32,
  wldap32, ws2_32, bcrypt, advapi32, crypt32, gdi32, m, pthread; zig-*
  packages serve curl, z, ssl, crypto, zstd, brotlidec, brotlicommon,
  iconv, charset; seven names stay unserved and unused by zig-libcurl:
  nghttp2, idn2, unistring, ssh2, gcrypt, gpg-error, psl (windows.zig
  `rtools_curl`, with the reason per name).
- F15 (V) Rhtslib 3.8.0's own lists (gamma, the Bioconductor 3.23
  tarball): `src/Makevars.win` PKG_LIBS and `R/zzz.R` `pkgconfig()`
  name idn2, unistring, ssh2, gcrypt, gpg-error unconditionally and
  nghttp2, psl, brotlidec/brotlicommon only when
  `$(R_TOOLS_SOFT)/lib/lib<n>.a` exists. With R_TOOLS_SOFT = zig-libs
  (Rcmd_environ's default) brotli is added (zig-brotli) and nghttp2/psl
  are not. `Makefile.Rhtslib.win`'s `htslib_default_libs` (the same
  names) only feeds `config_vars.h` and htslib's own programs, which
  `lib-static` does not link.
- F16 (V) Link test on delta (`~/rz/wt/build14-fb/linktest/linktest.sh`,
  logs in `~/rz/wt/build14-fb/logs/`), for x86_64- and
  aarch64-windows-gnu, with conda-forge zig 0.17.1 (`~/rz/base`) and
  upstream zig 0.17.1 (PyPI ziglang): libgnurx 2.6.1 (sha256
  ee6edc11...612c7) built as `libregex.a` + `libgnurx.a` + `regex.h`
  (the zig-libgnurx stand-in); htslib 1.18 from Rhtslib 3.8.0 built with
  its `Makefile.Rhtslib.win lib-static` (CC `zig cc -target <t>`,
  `-O2 -std=gnu2x -D_FILE_OFFSET_BITS=64 -DCURL_STATICLIB`, `-idirafter`
  the zig-libs and libgnurx includes): 52 objects, `libhts.a`. Then a DLL
  link of a stand-in for `R_init_Rhtslib.o` with all of `libhts.a`
  (`--whole-archive`, so every object's references must resolve) and
  `-L` zig-libs and libgnurx: with Makevars.win's PKG_LIBS as given, zig
  stops at exactly idn2, unistring, ssh2, gcrypt, gpg-error (F9, now
  with real zig-* archives); with the `-l` words rzig prints for the same
  line (`RZIG_PRINT_ARGV=1 RZIG_OS=windows RZIG_TRACE=1`, rzig built
  from this tree) the link succeeds: PE32+ DLL, x86-64 and ARM64, all
  four legs. rzig's trace: those five `(dropped: Rtools curl closure)`,
  regex `<libgnurx>/lib/libregex.a`, curl bz2 lzma iconv ssl crypto z
  zstd brotli* from zig-libs, the system names `(zig)`. No archive for a
  dropped name exists in any `-L` directory (the script lists any:
  none). zig-libcurl's `-lnormaliz` is not on Rhtslib's line, and the
  link needs it on neither arch.
- F17 (V) rzig tests on delta, both zigs 0.17.1: `zig build --build-file
  zigbuild/tools/rzig/build.zig test`: 244/244 (the new windows.zig test,
  the rewritten compiler.zig and environment.zig Windows-on-ARM tests);
  `check-test.sh` 60 passed; `link-objects-test.sh` ok. Run twice, the
  second time on the worktree as it was after every edit (other tracks'
  rzig changes included).
- F18 (V) stress.R on delta (R 4.6.2 from `~/rz/base/dist/slim`, linux):
  `parse()` ok; `--help` has no `--no-rtools-libs`; `--no-rtools-libs`
  now stops with `unknown option`; `--sysdeps Rsamtools` prints the unix
  names (bzip2 libcurl liblzma-devel zlib). The zig-libs column's new
  `dropped` part parsed from the F16 trace (the same regexes as
  `zig_column`, in a script): `idn2 unistring ssh2 gcrypt gpg-error`.
- F19 (V) The stress env's lock (pixi.lock, win-64 and win-arm64) has
  zig-zlib, zig-bzip2, zig-xz, zig-libcurl, zig-openssl, zig-libiconv,
  zig-zstd and zig-brotli (as dependencies of the listed zig-*), not
  zig-libgnurx (not published). So the Rsamtools row's
  `zig-libgnurx@windows` is in "Sysdeps missing" and its expect is `?`
  on both Windows arches until the package is published and listed
  (stress.R line `if (length(intersect(rz, sysdeps_missing)))`), and a
  `--conda` leg leaves it out of its env (`absent`) instead of failing
  the solve.
- F20 (V) Root `build.zig` after the r-zig.cmake change: `zig ast-check`
  and `zig build -l` (which compiles build.zig) pass on delta;
  `scripts/verify-tree.sh` passes `bash -n`; `.github/workflows/stress.yaml`
  parses as YAML (actionlint is not installed on gamma or delta).
- F21 (I) Nothing else used the Rtools45 tree in stress.R: its block
  (tarball, extraction, `rtools_pc`, `zig_lib`, `PKG_CONFIG_PATH`,
  `R_TOOLS_SOFT`, `served`, `rt_tree`) was referenced only by the
  report's Fallback line and the zig-libs column (grep of the names on
  the edited file). `R_TOOLS_SOFT` is still set for Windows to zig-libs
  (else the env's Library) before the block, as before. Inferred from
  the code: no Windows run of the edited stress.R.
- F22 (V) Remaining mentions after the change (`grep -rn` of
  R_ZIG_FALLBACK_SOFT, FALLBACK_SOFT, rtools_has, rtools_libs,
  no-rtools-libs, STRESS_RTOOLS, `(fallback)`, "Rtools45 tree" outside
  `.git`, `.pixi`, `build`, pixi.lock):
  - outside devdocs, resolved as history or as the retirement itself:
    README.md (the retirement note), recipe/recipe.yaml (build 12's
    history line and the 13 → 14 note), stress/README.md (the retired
    section), stress/smoke/hdf5r.R ("until build 13"), rzig's
    environment.zig item 3 ("Retired in build 14") and the two tests that
    set the variable to show it is no longer read, verify-tree.sh's
    negative check, stress/packages.tsv dated notes (past tense since
    D9).
  - pixi.toml 719-722 and 751-754 (comments): not this track's file;
    the exact change is in "For the user" below.
  - devdocs left as history on purpose: b13-env-ci, b13-fixes,
    b13-hosts, b13-integration (PLAN.md, PLAN-C-env-stress-docs.md, and
    CI-WAVE.md, which gets one line saying build 14 removed the input),
    b13-slice2, b13-stress, chore-env-ci,
    chore-release-11, chore-release-12 (PLAN.md, BACKLOG.md: Q23, CI4,
    CI13, W7 are closed by this), docs-backlog-hygiene,
    feat-standalone-toolchain (PLAN.md, phase7/AMENDMENTS.md),
    feat-winarm-gaps, feat-zig-libs, feat-zig-libs-universe,
    test-stress-rows. CXX-STDLIB.md "Windows on ARM: the Rtools45 tree"
    is a living reference, not a branch record: not this track's file,
    flagged for the user (below).
- F23 (V) F1's `if_nametoindex` (S1, both windows-11-arm legs) came from
  zig-libcurl build 0, and build 1 does not have it (b13-slice2 F12, F13
  recorded the cause; this checks it). S1's report.md (commit 21fee4e)
  lists `zig-libcurl-8.18.0-zig_12f6e5a_0` in zig-libs, and
  `git show 21fee4e:pixi.lock` has `zig_12f6e5a_0` and `zig_38b206d_0`;
  40ca257 ("relock zig-libcurl build 1", an ancestor of 77abec1 and of
  this worktree) moved both to `_1`. Both builds of both subdirs
  downloaded from universe on gamma, `llvm-nm -A libcurl.a` on delta
  (llvm-tools 23.1.6): build 0 (x86_64 and aarch64) `url.c.obj: U
  if_nametoindex`, a direct import of iphlpapi's function, which Rhtslib's
  line (no `-liphlpapi`) does not bind; build 1 (both) `url.c.obj: U
  Curl_if_nametoindex`, defined in `system_win32.c.obj` as data (`B`,
  a function pointer) next to `s_hIpHlpApiDll`: curl loads iphlpapi.dll
  and the function at run time. F16's link used build 1 (the `zl-*`
  libcurl.a sha256 equal the `_1` archives: aef3dd9f... aarch64,
  0b5a9cd4... x86_64). Rerun of `linktest.sh` (both arches, both zigs
  0.17.1, rzig rebuilt from the worktree as of this check), now with the
  DLL's import table from `llvm-readobj --coff-imports` (F16's script
  listed `strings` matches, not an import table): no `if_nametoindex` and
  no iphlpapi.dll import on any of the four legs (imports: WSOCK32,
  WS2_32, WLDAP32, ADVAPI32, CRYPT32, Secur32, bcrypt, KERNEL32 and the
  api-ms-win-crt set). The same rzig line with build 0's libcurl.a first
  on `-L` stops with `undefined symbol: if_nametoindex` on all four legs:
  S1 reproduced, and its cause is gone from the current lock.
- F24 (V) Rsamtools on windows-11-arm, by run (report.md rows, gamma):
  44450918935 (2026-11-19, fd44749, tree) ok; 45548386803 (e26b5ff,
  tree, before slice 2) ok on both legs; 45714066676 (S1, 2026-11-25,
  21fee4e, tree, zig-libcurl build 0) skipped behind Rhtslib's
  `if_nametoindex` (F23); no windows-11-arm run since 40ca257. So at
  build 13's head (77abec1) the row's `windows-aarch64=ok` was not
  backed by the latest run; with the tree and zig-libcurl build 1 it is
  likely ok again (I: F23's link, not a stress run). Build 14 without
  the tree and without zig-libgnurx fails Rhtslib at `regex.h` on
  win-arm64 for certain (F1 S3 legs), so the change on win-arm64 is
  "unverified, likely ok" to "fails", not "ok" to "fails". The previous
  Rsamtools note and the earlier report rested only on 44450918935;
  the note now has the S1 entry.
- F26 (V) windows-11-arm stress 45858117550 (55ce1db = build 13's code,
  lock cf4b3220532c, zig-libcurl build 1, the Rtools45 tree still on),
  report.json read row by row on gamma: tree and conda legs each 168 ok,
  not ok only protolite and arrow (install-failed, expect fail-package)
  and rstan's smoke (expect fail-package); Rhtslib and Rsamtools ok on
  both legs; libs smoke 21/21. This confirms F23: with zig-libcurl build
  1 the if_nametoindex failure is gone, and build 13 on win-arm64 builds
  Rsamtools with the tree. Build 14's removal of the tree turns that into
  a failure until zig-libgnurx is in the env (Decision A).
- D16 (default, 2026-11-26) Decision A: (a), hold build 14's merge and
  publish until zig-libgnurx is on universe, listed in pixi.toml, and a
  Windows stress run without the tree has Rhtslib and Rsamtools ok. This
  is U3's own condition ("once U1 and U2 land and an `rtools_libs=false`
  stress run is green"); the user's "recommended is fine" (2026-11-26)
  came before this menu was shown, so it is recorded as a default
  following U3, not as a new user decision.
- D17 (default, 2026-11-26) libs coordination: libs-zig-pixi plans
  libcurl build 2 at Rtools45 parity (libssh2 on OpenSSL, libidn2,
  libunistring, libpsl, nghttp2; no gcrypt, gpg-error) and zig-protobuf
  29.5 with protoc.exe per arch in Library/zig-libs/<triple>/bin. Answer
  sent: parity yes; the U2 drop list then only drops gcrypt and gpg-error
  (a name that resolves links normally); libcurl.pc Libs.private must
  list the full static closure; protobuf.pc must require absl_* and
  utf8_range with GNU-style Cflags. Our side: Rcmd_environ puts
  `${R_ZIG_LIBS}/bin` on R CMD's PATH after the tools (build.zig,
  verify-tree.sh), because protolite's Makevars.win calls `protoc` by
  name and runs `$(BINPREF)pkg-config --libs protobuf` (protolite 2.4.0;
  RProtoBuf 0.4.28 uses pkg-config only). Checked: `zig build -l` and
  `zig fmt --check build.zig` on delta, `bash -n` verify-tree.sh; not run
  on a Windows tree yet.
- F25 (V) Present-tense claims about zig-libgnurx (review, 2026-11-26):
  README.md ("zig-* packages serve those libraries on both Windows
  platforms") and stress/README.md ("comes from zig-libgnurx") said what
  is true only once libs-zig-pixi publishes zig-libgnurx. Both now say
  regex.h/-lregex wait for zig-libgnurx (not on universe) and that
  Rhtslib does not build on Windows until then (Rsamtools `?`). The
  packages.tsv note and recipe.yaml's 13 → 14 note already said "not yet
  on universe" or did not claim it.
- F27 (V) libs slice 3 on universe (2026-11-27, libs run 46079530353,
  repodata checked on gamma): zig-libgnurx 2.6.1 (zig_599dde6_0 win-64,
  zig_b471b37_0 win-arm64), zig-protobuf 29.5 (zig_463c35a_0,
  zig_5c7856f_0; protoc.exe in Library/zig-libs/<triple>/bin, "libprotoc
  29.5"), zig-libcurl 8.18.0 build 2 (zig_f8676a9_2, zig_078318b_2) with
  zig-libssh2 1.11.1 (OpenSSL), zig-libidn2 2.3.8, zig-libunistring
  1.4.1, zig-libpsl 0.21.5, zig-nghttp2 1.68.0. libs' r-consumer (r-zig
  build 13, both arches): 24/24 installs with protolite 2.4.0 and
  RProtoBuf 0.4.28; Rhtslib not in that set. libcurl.pc has no -lgcrypt
  -lgpg-error, so U2's drop stays needed for those two.
- D18 (default, 2026-11-27) The Windows stress env (pixi.toml
  `[feature.stress.target.win.dependencies]`) lists zig-libgnurx,
  zig-protobuf and `zig-libcurl = { version = ">=8.18.0", build-number =
  ">=2" }`; win-64 drops conda-forge's libprotobuf (an MSVC build, and its
  protoc 7.36 would sit next to zig-protobuf's headers: chore-env-ci M-3).
  Relock: sha256 0b512c3435b4. Only the stress env's win-64 and
  win-arm64 changed (libabseil and libprotobuf out on win-64; the eight
  slice-3 packages in, zig-libcurl _1 → _2 on both). packages.tsv:
  protolite's sysdeps are `libprotobuf@linux libprotobuf@macos
  zig-protobuf@windows`, expect `windows=?` (was fail-abi and
  windows-aarch64=fail-package); a new RProtoBuf row (g2, `?` on every
  OS until a run); Rsamtools' note records slice 3. windows.zig's
  `rtools_curl` comment, README.md, stress/README.md and CXX-STDLIB.md
  say what build 2 links (only gcrypt and gpg-error stay dropped). D16's
  first two conditions are met; the Windows stress run is the third.
- F28 (V) Host test of the slice-3 rows (2026-11-27, lock 0b512c3435b4,
  tree mode; kappa win-64 with PR #59's licence folders, which build14
  alone needs for `pixi run toolchain`: "m2-bash 5.3.20.2 ha3ae583_11
  ships no licence file"; delta linux-64):
  - kappa Rsamtools ok 0.48 min (Rhtslib ok 0.26), smoke ok, no Rtools45
    tree; `-l from zig-libs: bz2 lzma curl nghttp2 psl brotlidec
    brotlicommon idn2 unistring iconv ssl crypto z ssh2 zstd regex;
    dropped: gcrypt gpg-error`.
  - kappa protolite install-failed: `make: protoc: No such file or
    directory`, then r-windows' bundle and `lld-link: duplicate symbol
    std::__1::bad_function_call`. Cause: in tree mode Rcmd_environ's
    `${R_ZIG_LIBS}/bin` is the compile tree's env, which has no zig-libs,
    and stress.R did not put the stress env's zig-libs bin on PATH. Fix
    (stress.R, the Windows PATH): `file.path(zig_libs, "bin")` after the
    sysroot. With it: ok 0.78 min, "libprotoc 29.5", smoke 2. The conda
    distribution was not run (there R_ZIG_LIBS is the stress env).
  - RProtoBuf: `methods::new(P, ...)` gives `no slot of name "virtual"`;
    the smoke now uses `RProtoBuf::new`. delta: install-failed at
    `google/protobuf/stubs/common.h... no` (configure adds -std=gnu++11,
    abseil needs C++17); the row env `ac_cv_prog_cxx_cxx11=` fixes it.
    With both: delta ok 0.51 min, kappa ok 0.92 min, smoke TRUE.
  - Expects: protolite and Rsamtools `windows=ok`, RProtoBuf `linux=ok
    macos=? windows=ok`; `windows-aarch64=?` on all three until the
    PR's stress dispatch. Not run: conda distribution, macOS,
    windows-aarch64.

## Options

Serving `regex.h` + `-lregex` (compile side):

- R1 zig-libgnurx from libs-zig-pixi: libgnurx 2.6.1 (LGPL-2.1, MXE's
  pin, Rtools45's header), `include/regex.h`, `lib/libregex.a` and
  `lib/libgnurx.a`, win-64 and win-arm64. Rtools45 names, like
  zig-libiconv's `iconv.pc`. Owner libs-zig-pixi (new recipe, contract
  section 1 list). F8 shows it builds with zig on both arches.
- R2 the same library built by r-zig's build.zig into the toolchain
  group (next to `openmp/`). Owner us. Puts a third-party library in the
  R toolchain, outside zig-libs, against the contract's split.
- R3 conda-forge: nothing for win-arm64; `m2w64-libsystre` is win-64
  MSYS2 2016 (F7). Rejected.
- R4 patch Rhtslib/htslib (drop the `=~` operator). We do not patch
  CRAN/Bioconductor sources. Rejected.

Resolving the other five hard-coded names (link side, F9):

- L1 rzig drops an unresolved Windows `-l` when the name is one of
  Rtools45's libcurl closure that zig-libcurl does not use (idn2,
  unistring, gcrypt, gpg-error, ssh2, and nghttp2, psl for safety), with
  an RZIG_TRACE line `lib -l<n> (dropped: Rtools curl closure)`. Owner
  us (windows.zig `libs`, beside `mingw_names`). Covers every package
  that copies Rtools' curl link list, not only Rhtslib.
- L2 empty archives for those names in a libs package (for example in
  zig-libcurl). Owner libs. Shadows a real zig-libssh2/zig-libidn2 if
  one ever ships; a contract change.
- L3 real zig-libidn2, zig-libunistring, zig-libgcrypt, zig-libgpg-error,
  zig-libssh2 (Rtools parity). Owner libs. Large, and the code is never
  called.

## Decisions

| id | question | options (chosen in bold) | reason | who, date |
|---|---|---|---|---|
| D1 | Scope of this track | **research and record only; no stress dispatch, no repo edits** | the task; a dispatch is the user's call | default, 2026-11-26 |
| D2 | U2's fixed list | (a) the five Rhtslib names (idn2 unistring ssh2 gcrypt gpg-error); **(b) the seven of Rtools45's libcurl closure that zig-libcurl does not use: also nghttp2, psl** | F13-F15: the same reason holds for all seven; Rhtslib adds nghttp2 and psl whenever `$(R_TOOLS_SOFT)/lib` has them, and any package that copies libcurl.pc's static Libs names them; dropped only when unresolved, so a real library still links | default, 2026-11-26 |
| D3 | When a name is "unresolved" | **none of zig's or GNU ld's five file names (`lib<n>.dll.a`, `<n>.dll`, `<n>.lib`, `lib<n>.a`, `lib<n>.lib`) in any `-L` directory of the command (the environments' included, envFlags runs first), and not a name zig serves (`zigServes`)**; only the -L directories | the same test the trace already uses (`resolved`); conda-forge's `libssh2.lib` in an env keeps `-lssh2` (unit test) | default, 2026-11-26 |
| D4 | Message for a dropped name | **RZIG_TRACE line only, `lib -l<n> (dropped: Rtools curl closure)`**; a warning on every link | U2 asked for the trace line; a warning on every Rhtslib/Rsamtools link would be noise for an expected case | default, 2026-11-26 |
| D5 | A set `R_ZIG_FALLBACK_SOFT` after the retirement | **not read at all (tests set it and expect nothing)**; a "retired" warning | simplicity: no code for a removed variable; README and recipe say it is gone; a win-arm64 user of builds 12-13 then gets zig-libs, which serve the same libraries | default, 2026-11-26 |
| D6 | environment.zig's numbered items | **item 3 kept as "Retired in build 14"**; renumber | "item 4" and "item 5" are cited in windows.zig, compiler.zig, build.zig and CONTRACT.md section 6 | default, 2026-11-26 |
| D7 | stress.yaml's `rtools_libs` input and stress.R's `--no-rtools-libs` | **both removed; the option is now unknown (stress.R stops)**; keep the option as a no-op | without the tree neither means anything; a stale dispatch or command then fails loudly instead of silently testing something else (F18) | default, 2026-11-26 |
| D8 | The report's zig-libs column | **"from the fallback tree" becomes "dropped: <names>" (the trace's dropped lines); "Rtools tree" status gone** | the column is where a reader sees which -l names a link did not bind (F18) | default, 2026-11-26 |
| D9 | packages.tsv notes that name the tree | **keep the dated history; the 15 copies of "stress.R now uses CRAN's Rtools45 aarch64 tree there by default" become "then used ... (retired in build 14, b14-rhtslib U3)"; the 5 present-tense "and not served by the Rtools45 tree" are removed; a dated Rsamtools note** | notes are evidence; only present-tense claims about stress.R became false | default, 2026-11-26 |
| D10 | Rsamtools row | **sysdeps in b13-slice2 D3 form: conda names `@linux @macos`, and `zig-zlib zig-bzip2 zig-xz zig-libcurl zig-openssl zig-libiconv zig-zstd zig-brotli zig-libgnurx` `@windows` (what Rhtslib's link binds, F16); expect `linux=ok macos=ok windows=?`** (no windows-aarch64 key) | the evidence rule of b13-slice2 D5: no Windows run without the tree yet; zig-libgnurx missing makes it `?` anyway (F19) | default, 2026-11-26 |
| D11 | verify-tree.sh's win-arm64 check | **turned into a check on every Windows tree that `etc/r-zig.cmake` does not read `R_ZIG_FALLBACK_SOFT`**; drop the check | keeps a stale tree or a reverted build.zig from passing | default, 2026-11-26 |
| D12 | stress/README.md's "Windows on ARM: the Rtools45 fallback" | **a short "(retired in build 14)" section: what it was, what replaced it, the dropped names; the runtime-checks paragraph kept**; delete the section | pixi.toml cites the heading; the history lives in feat-winarm-gaps and git | default, 2026-11-26 |
| D13 | Order against U3's condition ("once U1 and U2 land and an `rtools_libs=false` stress run is green") | **apply U3 in the worktree now (the task), and leave merge/publish gated on zig-libgnurx and a Windows stress run (user, below)** | U1 is libs' work; the code and docs are ready for it; the gate is a release decision. **Conflicts with U3's own wording** (review 2026-11-26): U3 (a) says remove the tree *once* U1 and U2 land and an `rtools_libs=false` stress run is green; U1 has not landed and no such run exists. D13 is the task's order, not a user decision: it stands only if the user answers decision A below with (a) or (b); with (c) U3's removal is undone until its condition holds | default, 2026-11-26; open against U3 until decision A |
| D14 | How to show the link test's DLL imports | **`llvm-readobj --coff-imports` (llvm-tools 23.1.6 on delta), and a second link with zig-libcurl build 0 first on `-L` to reproduce S1**; `strings` (F16 first run) | `strings` also matched names that are not imports (`api.dll`, `Rhtslib.dll`); the build-0 link shows the test can see the S1 failure (F23) | default, 2026-11-26 |
| D15 | Docs while zig-libgnurx is unpublished | **say in README.md and stress/README.md that regex.h/-lregex wait for zig-libgnurx and Rhtslib does not build on Windows until then (F25)**; leave the text for when it lands | docs on main must be true at every commit; one line to drop when zig-libgnurx lands | default, 2026-11-26 |

The research track's open questions (R1/R2, L1/L2/L3, when to retire)
are answered by U1-U3 below. Open after the fallback track: whether
build 14 waits for zig-libgnurx and a Windows stress run before it is
merged and published (D13; decision A).

### Decision A (open, user)

U3's removal is in the worktree before U3's condition holds (D13). What
build 14 does about that, with F23/F24's corrected premises (win-arm64
Rsamtools was not verified ok at build 13's head; its S1 failure was
zig-libcurl build 0, fixed in the lock):

- (a) ★ hold build 14's merge and publish until zig-libgnurx is on
  universe, pixi.toml lists it (For the user), the stress env is
  relocked, and a Windows stress run (both arches, no tree) has Rhtslib
  and Rsamtools ok. U3's condition then holds before release.
- (b) release build 14 without zig-libgnurx: Rhtslib and Rsamtools fail
  on both Windows arches (win-64 always did; win-arm64 goes from
  unverified-likely-ok to fail, F24), and nothing replaces the tree for
  them until zig-libgnurx.
- (c) undo U3 in build 14 (keep the tree and `R_ZIG_FALLBACK_SOFT`,
  keep U2), and remove it in a later build once U3's condition holds;
  needs a windows-11-arm run with the tree first to know whether it
  still gives ok (F24).

The README.md and stress/README.md text (F25) is right under (a) and
(b); (c) would need it reverted with the rest of U3.

### User decisions (2026-11-26)

| id | question | choice |
|---|---|---|
| U1 | H1: regex.h and -lregex | (a) ★ zig-libgnurx from libs-zig-pixi (requested 2026-11-26) |
| U2 | H2: Rtools' dead curl-closure link names | (a) ★ rzig drops them on Windows when unresolved, fixed list, RZIG_TRACE line |
| U3 | H3: R_ZIG_FALLBACK_SOFT | (a) ★ remove everywhere in build 14 once U1 and U2 land and an `rtools_libs=false` stress run is green |

## Retiring R_ZIG_FALLBACK_SOFT

What it needs, in order:

1. Rhtslib links on windows-11-arm without the tree: regex (R1 or R2)
   and the five names (L1, L2 or L3). The same change makes win-64 work,
   so Rsamtools' `windows=fail-dependency` becomes `ok` on both.
2. A stress dispatch with `rtools_libs=false` on both Windows arches
   (S3 already shows 166 ok and only Rhtslib/Rsamtools left, F10), with
   Rsamtools ok and its smoke ok.
3. Then remove: stress.R's Rtools45 block (`rtools_tarball`,
   `rtools_has`, `rtools_libs()`, `rtools_pc()`, `--no-rtools-libs`,
   the Fallback report line), stress.yaml's `rtools_libs` input and
   cache step, stress/README.md, the packages.tsv notes that name the
   tree; in rzig `environment.fallback`, the `tree` argument in
   windows.zig, compiler.zig and main.zig docs and their tests;
   build.zig's `etc/r-zig.cmake` fallback block; verify-tree.sh's check;
   README.md and recipe.yaml mentions (F12). Bump the build number.
4. Tell libs-zig-pixi: CONTRACT.md section 6 drops the fallback tree
   (their file, section 8 procedure).

A smaller step is possible: keep rzig's opt-in (users on Windows on ARM
with their own Rtools45 tree) and remove only the stress default. That
keeps ~25 lines of rzig and its tests for no tested user.

Status (2026-11-26, fallback track, uncommitted in worktree build14):

1. U2 done (windows.zig `rtools_curl`, F16, F17). U1 open: zig-libgnurx
   is libs-zig-pixi's (requested), not on universe; the stress env
   needs it in pixi.toml after it is published ("For the user").
2. Not run: no stress dispatch (the user's call); it needs 1 first.
   Without the tree every stress run is what `rtools_libs=false` was.
3. Done, ahead of 1 and 2 and so ahead of U3's condition (D13; open
   until decision A): stress.R (Rtools45 block, `--no-rtools-libs`,
   `STRESS_RTOOLS_DIR`, the Fallback line, the zig-libs column),
   stress.yaml (input, cache step, env, argument), stress/README.md,
   packages.tsv (D9, D10), smoke/hdf5r.R's comment, rzig
   (environment.zig, Ctx.zig, windows.zig, compiler.zig, main.zig docs
   and tests), build.zig (`etc/r-zig.cmake` block and its doc, the
   rcmdEnviron doc line), verify-tree.sh (D11), README.md, recipe.yaml
   (13 → 14 note). The build number is 14 already (recipe.yaml).
4. Drafted below, not sent.

## Note to libs-zig-pixi (draft, not sent)

> r-zig-pixi build 14 changes the consumer side of CONTRACT.md section 6
> (your file; section 8 procedure on your side, please):
>
> 1. rzig's environment order loses its last entry: delete "and the
>    Rtools45 fallback tree (`R_ZIG_FALLBACK_SOFT`, win-arm64 only)
>    last". Build 14's rzig and `etc/r-zig.cmake` no longer read the
>    variable, and the stress suite no longer downloads the Rtools45
>    aarch64 tree; zig-libs serve what it served (b14-rhtslib U3).
> 2. New consumer rule, Windows: rzig drops an `-l` of Rtools45's
>    static libcurl closure when no `-L` directory has it and zig does
>    not serve it: `nghttp2 idn2 unistring ssh2 gcrypt gpg-error psl`
>    (`zigbuild/tools/rzig/windows.zig` `rtools_curl`; RZIG_TRACE prints
>    `lib -l<n> (dropped: Rtools curl closure)`). Packages such as
>    Rhtslib hard-code Rtools' curl link line. It holds because
>    zig-libcurl 8.18.0 (Schannel, WinIDN) uses none of them (its
>    libcurl.pc Libs). Producer obligation to add: if zig-libcurl (or
>    any zig-*) starts to need one of these seven, ship that library's
>    `lib<n>.a` in zig-libs (rzig then links it; it drops only an
>    unresolved name) and say so in the handover, or the links fail with
>    undefined symbols instead of a missing library.
> 3. The stress bullet: the report's zig-libs column now lists the
>    dropped names instead of "the fallback tree"; the stress env's list
>    is slice 1 and slice 2's packages (pixi.toml), plus zig-libgnurx
>    once published; packages.tsv's Rsamtools row names
>    `zig-libgnurx@windows` and the zig-* Rhtslib links.
> 4. U1 (requested 2026-11-26): zig-libgnurx, libgnurx 2.6.1 (MXE's pin,
>    LGPL-2.1, github.com/TimothyGu/libgnurx release, sha256
>    ee6edc110c6b63d0469f4f05ef187564b310cc8a88b6566310a4aebd48b612c7),
>    win-64 and win-arm64: `include/regex.h`, `lib/libregex.a` and
>    `lib/libgnurx.a` (Rtools45's names). Our delta prototype (F8, F16)
>    builds it with `zig cc -O2 -std=gnu99 -c regex.c` on both arches and
>    links Rhtslib with it.
> 5. "The first r-zig build that carries this section" becomes 14 for
>    items 1-3, when it is published.

## Tests

| host | command | result |
|---|---|---|
| gamma | `gh run download 45714066676` and `45714071892`; grep `logs/Rhtslib.log` | F1 table: 4 legs regex.h, 2 legs if_nametoindex |
| gamma | Rhtslib_3.8.0.tar.gz (Bioconductor 3.23): `grep -rn regex src/htslib-1.18`, read Makevars.win, zzz.R | only hts_expr.c (F2); hard-coded `-l` list (F3) |
| gamma | `grep '^zig-cc: lib -l'` S1 arm tree Rhtslib.log | F4 binding table |
| gamma | list Rtools45 base tarballs (x64, aarch64), grep regex/gnurx | libgnurx as libregex.a, regex.h (F5) |
| gamma | `pixi search -c conda-forge -p win-64/-p win-arm64` libgnurx, tre, libsystre, pcre2 ... | only m2w64-libsystre win-64 (F7) |
| delta | libgnurx 2.6.1 with zig 0.17.1 for x86_64 and aarch64-windows-gnu; test exe link; hts_expr.c with and without the header | builds, links, compiles with header; error reproduced without (F8) |
| delta | link with Rhtslib's `-l` list, then with five empty archives | 5 names unresolved; links with the empties (F9) |
| gamma | S3 report.md non-ok rows, both arm legs | only Rsamtools beyond expected fail-package rows (F10) |
| gamma | Rtools45 base 6768 tarballs (x64, aarch64), `lib/pkgconfig/libcurl.pc` | closure names (F13) |
| gamma | universe zig-libcurl, -libiconv, -openssl, -zlib, -xz, -bzip2, -zstd, -brotli (lock builds, both arches) unpacked; libcurl.pc | F14 |
| delta | `zig build --build-file zigbuild/tools/rzig/build.zig test`, conda-forge zig 0.17.1 and upstream 0.17.1, twice | 244/244 each (F17; the first run caught a wrong expectation in the new test, fixed) |
| delta | `check-test.sh`, `link-objects-test.sh`, both zigs | 60 passed; ok (F17) |
| delta | `linktest.sh` (htslib 1.18 + libgnurx + zig-libs, Rhtslib DLL link as given and after rzig), x86_64 and aarch64, both zigs | as given: idn2 unistring ssh2 gcrypt gpg-error unresolved; after rzig: links, 4/4 (F16) |
| delta | stress.R `parse`, `--help`, `--no-rtools-libs`, `--sysdeps Rsamtools`; zig column regexes on the F16 trace | F18 |
| gamma | pixi.lock stress env, win-64 and win-arm64 zig-* names | F19 |
| delta | `zig ast-check build.zig`, `zig build -l`, `bash -n scripts/verify-tree.sh`; YAML parse of stress.yaml | F20 |
| gamma | grep of every fallback name outside `.git`, `.pixi`, `build`, pixi.lock | F22 |
| gamma | S1 report.md zig-libs line; `git show 21fee4e:pixi.lock`, `git log -S zig_12f6e5a_1 -- pixi.lock`; universe zig-libcurl `zig_12f6e5a_{0,1}` (win-arm64), `zig_38b206d_{0,1}` (win-64) unpacked | S1 had build 0; 40ca257 moved to build 1 (F23) |
| delta | `llvm-nm -A` on the four libcurl.a | build 0 `U if_nametoindex`; build 1 `U Curl_if_nametoindex`, defined in system_win32 (F23) |
| delta | `linktest.sh` again (rzig rebuilt from the worktree, both zigs 0.17.1, both arches), `llvm-readobj --coff-imports`, plus the build-0 link; logs `logs/linktest2-{cf,up}.log` | 4/4 link, 5 dropped, no if_nametoindex import; build 0: `undefined symbol: if_nametoindex` 4/4 (F23) |
| gamma | report.md Rhtslib/Rsamtools rows of 45548386803 and 45714066676 | arm ok before slice 2, skipped at S1 (F24) |
| delta | `stress.R --sysdeps Rsamtools`; `read.delim` of packages.tsv after the F24 note | unix sysdeps as before; 46 rows, 10 fields, expect `linux=ok macos=ok windows=?` |

Delta scratch: `~/rz/scratch-b14-rhtslib` (build outputs deleted; the
source tarball and t.c kept). Fallback track: `~/rz/wt/build14-fb`
(worktree copy, `linktest/` inputs and script; logs in `logs/`; build
outputs, caches and rzig builds deleted).

## Not verified

- Running the regex test exe or a built Rhtslib on Windows (no host in
  this track; kappa needs the passphrase).
- A full Rhtslib build with R1 + L1 through rzig: needs the package
  (or a local zig-libs overlay) and a Windows stress run.
- Both zigs: the prototype used only the delta base env's zig 0.17.1
  (`~/rz/base/.pixi/envs/default/bin/zig`), not checked against PyPI
  ziglang. (The fallback track's link test, F16, ran both.)

Fallback track, not run:

- Anything on Windows: rzig.exe's drop on a real link, Rhtslib and
  Rsamtools installed, loaded and smoked, the edited stress.R's Windows
  paths (the zig-libs column with dropped names), a win-arm64 tree's
  `etc/r-zig.cmake` and verify-tree.sh's new check on it. This track has
  no kappa use; the unit tests and the cross link stand in.
- The F16 link is a stand-in: `-O2 -std=gnu2x`, not R CMD config's
  CFLAGS; a two-line stand-in for `R_init_Rhtslib.o` (no R); all of
  libhts.a (`--whole-archive`), a superset of what Rhtslib's and
  Rsamtools' links pull. rzig ran as a dry run on linux (`RZIG_OS`,
  host arch x86_64); its `-l` words were reused for the aarch64 link.
- A stress dispatch (both Windows arches): needs zig-libgnurx on
  universe and in pixi.toml; the user's call.
- conda-forge's `libssh2.lib` binding `-lssh2` in the stress env: unit
  test only.
- actionlint on stress.yaml (not installed).
- Review fixes (2026-11-26), not run: a windows-11-arm stress run with
  the tree and zig-libcurl build 1 (F24's "likely ok" is inferred from
  F23's cross link); curl's run-time load of iphlpapi.dll's
  `if_nametoindex` on a Windows host (no Windows host in this track).

## For the user

- pixi.toml (not this track's file), after zig-libgnurx is on universe
  for win-64 and win-arm64 (not before: the solve would fail), then a
  relock of the stress env:

  ```toml
  # [feature.stress.target.win.dependencies], after zig-nlopt:
  zig-libgnurx = "*"      # Rsamtools (Rhtslib's regex.h and -lregex)
  ```

  and the two comments that describe the tree as current:

  ```diff
  -# and stress.R reports it as missing from the env. On win-arm64 stress.R
  -# takes most of them from CRAN's Rtools45 aarch64 tree by default
  -# (stress/README.md, "Windows on ARM: the Rtools45 fallback").
  +# and stress.R reports it as missing from the env. On Windows the zig-*
  +# packages below serve them (the Rtools45 aarch64 tree stress.R used
  +# until build 13 is retired: stress/README.md, b14-rhtslib U3).
  ```
  ```diff
  -# r-windows' protobuf bundle (tools/winlibs.R). The Rtools45 tree has a
  -# protoc.exe (bin/) but stress.R does not put the tree's bin/ on PATH.
  +# r-windows' protobuf bundle (tools/winlibs.R).
  ```
- `.github/devdocs/CXX-STDLIB.md` "Windows on ARM: the Rtools45 tree"
  describes the tree as in use (line 214 names R_ZIG_FALLBACK_SOFT): a
  one-line "retired in build 14 (b14-rhtslib)" there is for its owner.
