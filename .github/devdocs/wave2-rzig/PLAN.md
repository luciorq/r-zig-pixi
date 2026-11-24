# wave2-rzig: tier-2 flags (environment headers stay -I: W6)

Branch wave2-rzig from main f5a6c84 (build-12 batch 1, PR #54). Backlog:
`.github/devdocs/chore-release-12/BACKLOG.md`. Tests on delta (linux-64),
conda-forge zig 0.17.1 and upstream (PyPI ziglang) 0.17.1.

## Goal

- M-16 (R-F10, chore-release-11/PLAN.md finding 30): decide `-isystem`
  against `-I` for the environments' include directories on linux, with
  evidence.
- M-18 (O-A2, fix-zig-pkg-build-review/PLAN.md code-4): tier-2 compile
  flags in rpkg's `LibraryOptions`.
- Q24 follow-up: measure the open form `-Xlinker --whole-archive
  -Xlinker -lfoo -Xlinker --no-whole-archive`.

## Decisions

| # | Question | Chosen | Reason |
|---|---|---|---|
| W1 | M-16: environment headers on linux | `-isystem<dir>/include` (joined), still after the caller's arguments; macOS keeps `-I`, Windows `-idirafter` | F1-F3: a package's own `-isystem` (CMake's bundled copy, arrow's aws-c-common) now wins over the env's copy, env header warnings stop failing `-Werror`, and a package's `-I` still wins. conda-forge's own gcc builds use `-isystem $PREFIX/include`. The cost (F4) is iconv.h only, and it links |
| W2 | M-16 on macOS | no change | the SDK's directories are `-isystem` before the caller's; the SDK iconv.h would shadow conda's libiconv, which R links (finding 30). Not measured here (no macOS host in this batch) |
| W3 | M-18: shape | two optional fields, `cflags` (C) and `cxxflags` (C++), passed as `--cflag`/`--cxxflag` to `rzig t1` | a `-std=` for C must not reach C++; mirrors PKG_CFLAGS/PKG_CXXFLAGS |
| W4 | M-18: position | after the plan's flags (Makeconf's with the user's Makevars) | the plan is one flat word list; R puts PKG_* before the user's CFLAGS, so here a package's `-O`/`-std` beats the user's. Recorded in the rpkg.zig doc comment. A relative `-I` is from src/ (the compiles run there) |
| W5 | Q24 open form | no code change; one unit assertion | measured: order kept, archive linked whole (F6) |
| W6 | Keep W1 (-isystem on linux) for build 12? (user, 2026-11-23, after CI) | **No: reverted, linux keeps `-I<env>/include`**, as macOS; W1's code, its parity mapping and the three test changes it needed (test-toolchain.R, contract-test.sh, verify-bundle.sh) are gone | CRAN compatibility, one behaviour on every platform, fewest surprises. CRAN's macOS layout is exactly ours: libraries under one prefix (`/opt/R/<arch>`), `-I/opt/R/<arch>/include` in Makeconf's CPPFLAGS; on CRAN's linux machines library headers are the compiler's implicit system dirs, and Windows (Rtools) the same, which our `-idirafter` matches. W1's gains do not reach CRAN packages: CRAN does not accept `-Werror` in a package's flags, a package's `-I` beats the env either way, and the bundled-`-isystem` case seen (arrow's aws config.h) is on macOS, which W1 left alone. Its cost: a package including iconv.h got glibc's iconv while R links libiconv (F4), and every linux compile changed. It cost three CI failures (#55: 45289106642 conda-package linux, 45289104950 contract, 45292868395 verify-bundle) before any stress run. Revisit only with a stress run showing a real package that needs it | user, 2026-11-23 |

## Findings

- F1 (V) M-16, which header wins. delta, `~/rz/scratch/w2rzig/m16/probe.sh`:
  a fake env (R_ZIG_EXTRA_ENV) and a package each with
  `aws/common/config.h` and `own.h`. main's rzig (`-I<env>/include`):
  `-I own -isystem bundled` gives `env pkg` (the env beats the bundled
  `-isystem` copy: the arrow/aws-checksums case); `-isystem bundled`
  alone `env env`. This branch (`-isystem<env>/include`): `bundled pkg`
  and `bundled env`. `-I own -I bundled`: `bundled pkg` both. No caller
  flag: `env env` both. So a package's own `-I` wins either way.
- F2 (V) M-16, warnings. Same probe, fresh zig cache (zig's cache hides
  warnings on a hit): env header with an unused variable and a
  sign-compare. main: `-Wall -Wextra` 2 warnings, `-Werror` rc=1. Branch:
  0 warnings, `-Werror` rc=0.
- F3 (V) M-16, search order (`zig cc -E -v`, conda zig): caller `-I`,
  zig's clang include, glibc (generic-glibc, x86-linux-gnu, x86-linux-any,
  any-linux-any), caller `-isystem`, then the env's `-isystem`. A caller
  `-I<env>/include` (pkg-config style) is dropped by clang as a duplicate
  of the system directory: `-I<env>/include -isystem bundled -I own`
  gives `env env` on main, `bundled pkg` on the branch (gcc's rule too).
- F4 (V) M-16, shadowing. Header names in the env's include/ (2112 files,
  ~/rz/base's default and pkg envs) against zig's clang and glibc
  directories (1767): only `iconv.h`. Against libstdc++ 15.3's
  include/c++ (834): none. With the branch, `#include <iconv.h>` gets
  glibc's: `iconv_open@GLIBC_2.2.5`, links without `-liconv` (main:
  `undefined symbol: libiconv_open` unless `-liconv`). libiconv.so.2
  exports only `libiconv_*`, so the two never mix. A package's own iconv
  calls now use glibc's converter instead of libiconv's (R's own Riconv
  is unchanged; R itself uses libiconv on linux, config.h
  `HAVE_ICONVLIST 1`). This is where rzig differs from conda-forge's gcc:
  gcc searches `-isystem` before its standard directories, so there
  `$PREFIX/include/iconv.h` (libiconv) wins; zig passes its glibc
  directories as `-isystem` ahead of the caller's, so here glibc's wins.
  Review re-check (delta, `~/rz/scratch/w2review/hdr.sh`, `ic.sh`): the
  same single collision; before `-liconv`-less rc=1 `libiconv_open`,
  after rc=0 with and without `-liconv`, `iconv_open@GLIBC_2.2.5`,
  CP1252 `\xe9` -> `c3a9`.
- F5 (V) M-16, C++: `zig-cxx -std=gnu++17 -Wall -Werror` of
  `<cstdlib> <cmath> <iostream> <zlib.h>` with R_ZIG_EXTRA_ENV=the env:
  rc=0, runs, both trees (libstdc++'s `#include_next <stdlib.h>` still
  finds glibc's).
- F6 (V) Q24 open form. delta, both zigs 0.17.1,
  `~/rz/scratch/w2rzig/q24/q24.sh`, libfoo.a holding an unreferenced
  `unref_sym`: rzig `-Xlinker --whole-archive -Xlinker -lfoo -Xlinker
  --no-whole-archive` rc=0, `unref_sym` exported; `-Xlinker -l -Xlinker
  foo` the same; `-Wl,--whole-archive,-lfoo,--no-whole-archive` the
  same; control `-Xlinker -lfoo` not exported. rzig's argv: `-Xlinker
  --whole-archive -lfoo -Xlinker --no-whole-archive` (order kept). Raw
  zig: that argv rc=0 exported; the unrewritten form rc=1 "unsupported
  linker arg: -lfoo".
- F7 (V) M-18 end to end: tier-2 package `rzigt2f`
  (`~/rz/scratch/w2rzig/m18`), a zig root plus util.c (`#include
  <util.h>` from src/inc) and k.cpp, `.cflags = {"-Iinc","-DMAGIC=7"}`,
  `.cxxflags = {"-DCXXMAGIC=5"}`, installed by R CMD INSTALL of a scratch
  copy of ~/rz/base's slim tree with this branch's rzig and rpkg.zig:
  install rc=0, `f()` = 42; the log's compile lines end
  `-O2 -Iinc -DMAGIC=7 -c util.c` and `-O2 -DCXXMAGIC=5 -c k.cpp`.
  main's rpkg.zig: "no field named 'cflags'", install fails.

## Changes

- compiler.zig `envFlags`: linux `-isystem<dir>/include`; doc comment;
  the libstdc++ comment in argv; unit tests' expectations.
- libstdcxx.zig: header comment (order against the env's -isystem).
- fortran.zig: one test expectation (zig-cc link with -fopenmp).
- parity-test.sh: linux OpenMP-tree cases map the shims' `-I` to
  `-isystem` (deliberate, M-16).
- rpkg.zig `LibraryOptions.cflags`/`cxxflags`; tier1.zig `--cflag`,
  `--cxxflag`; test.
- linker_args.zig: the `-Xlinker` whole-archive assertion.

## Tests

- delta, `run.sh` (test.sh: unit, parity, link-objects) from ~/rz/base's
  env, both zigs. Before (f5a6c84): unit 6/6 steps ok (cached), parity
  109 + 77 + 33, 0 failed, link-objects ok, EXIT=0 both. After:
  228/228 unit tests (new assertions sit in existing tests), parity
  109 + 77 + 33, 0 failed, link-objects ok, EXIT=0, both zigs. Logs:
  delta ~/rz/scratch/w2rzig/{before,after}-{conda,upstream}.log.
- delta, `zig fmt --check zigbuild/`: clean with both zigs.
- delta, smoke-test.sh against a scratch slim tree with this branch's
  rzig and rpkg.zig (conda zig): parts 1 and 2 ok (C, C++, OpenMP and
  Fortran packages build, load, run), EXIT=0
  (~/rz/scratch/w2rzig/smoke-conda.log).
- Probes F1-F7 above (scripts under ~/rz/scratch/w2rzig/).

- Review (adversarial pass): diff re-read; F1, F2, F4, F7 re-run on
  delta with the before/after trees (same results); test.sh again with
  both zigs from the synced tree: parity 109 + 77 + 33, 0 failed,
  EXIT=0 both (`~/rz/scratch/w2rzig/review-{conda,upstream}.log`). R
  itself is built by build.zig, not through rzig, so its own compiles
  are unaffected by M-16.

## Not verified

- macOS and Windows: unchanged code paths; not run (no hosts in this
  batch). M-16 on macOS stays `-I` (W2).
- The stress suite with `-isystem` (arrow:source with the env's
  aws-c-common on linux, and the iconv users): next stress run.
- linux-aarch64.

## Backlog items closed

M-16, M-18; Q24's open form measured.
