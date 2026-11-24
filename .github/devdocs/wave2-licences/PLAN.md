# wave2-licences

## Goal

Backlog M12 (docs-backlog-hygiene/PLAN.md F6): no r-zig conda package
ships `info/licenses/`. Give every recipe output `about.license_file`,
with the texts of what it bundles. Build number unchanged (12, unpublished).

## Decisions

| # | question | chosen | reason |
|---|---|---|---|
| L1 | where the texts come from | the work dir only: R's source (`build/R-<ver>/`, where build.sh moves it), the recipe's sources (`cairo-src/`, `pkgconf-src/`), a new `path: ../LICENSE` source (`licenses/r-zig/`), and `licenses/zig/`, `licenses/recommended/` that build.sh fills | rattler-build's `license_file` reads the work dir and the recipe dir, never `$PREFIX`; the staging work dir is restored for each output (checked with a mini recipe, Findings V1) |
| L2 | zig's texts | build.sh copies the build env's zig package's `info/licenses/` (16 files) from the package cache its conda-meta record names | every zig-linked binary carries compiler_rt (zig's MIT) and the libc start files (glibc, mingw-w64, ...); copying the package's own set follows the zig that built it, no vendored copies to drift; build.zig's installLicenses reads the same field |
| L3 | which texts per output | r-zig-slim: R's COPYING, doc/COPYRIGHTS and the files it names (tre, xdr, lapack, afm LPPL, share/licenses GPL/LGPL), r-zig's, zig's; Windows + cairo's. r-zig-recommended: R's GPL/LGPL/Apache-2.0 texts, Matrix's LICENCE, r-zig's, zig's. r-zig-build-tools: the top level's; Windows + pkgconf's COPYING and zig's set (pkgconf.exe is zig-linked; review A1). compilers, extras, toolchain (no payload): the top level's (R's COPYING, GPL-2, GPL-3, r-zig's) | each set matches the package's declared `license` and the code in its payload; the payload-less packages' dependencies ship their own |
| L4 | recommended packages' own files | build.sh copies `library/*/LICEN[CS]E*` from `$PREFIX` after the recommended install | only Matrix has one (`_11` osx packages: `lib/R/library/Matrix/LICENCE`); the others are GPL/LGPL/Unlimited by DESCRIPTION |
| L5 | Apple SDK, NetBSD/OpenBSD headers (F6) | nothing added | they carry notices inline and zig ships no text (F6); no binary of ours links them statically |

## Findings

- **V1 rattler-build 0.80.1 mechanics** (mini recipe on delta,
  ~/rz/wt/lic-mini): a `path:` source naming a file lands at
  `<target_directory>/<name>`; files the staging script makes or moves in
  the work dir are seen by the inheriting outputs; the top-level
  `about.license_file` reaches an output that sets none; paths keep their
  relative directories (`info/licenses/build/R-1.0/COPYING`); one glob
  that matches nothing fails the package ("No license files were
  copied"), so a missing text stops the build.
- **V2 render**: `rattler-build build --render-only` for linux-64 and
  win-64 gives each output the lists of L3 (the `if: win` entries only on
  win-64; the top-level list on compilers, extras, toolchain).
- **I1** The zig 0.17.1 package in delta's rattler cache (`zig-0.17.1-89c0722_0`)
  has 16 licence files under `info/licenses/` (`zig-source/LICENSE`,
  libcxx, libcxxabi, libunwind, libc/{glibc,musl,mingw,freebsd,wasi...},
  `building/mingw-defs/DISCLAIMER.PD`) and none in its payload.
- **V3 linux-64 packages** (delta, `pixi run -e pkg conda-package`,
  log ~/rz/wt/wave2-licences.conda.log, EXIT=0, recipe tests included;
  6 `.conda` in dist/conda/linux-64, all `_12`): `info/licenses/` per
  package, read from each info-*.tar.zst: r-zig-slim 28 files (R's 11:
  COPYING, doc/COPYRIGHTS, GPL-2/3, LGPL-2/2.1/3, tre, xdr, lapack, afm
  LPPL; r-zig/LICENSE; zig's 16); r-zig-recommended 24 (R's COPYING,
  GPL-2/3, LGPL-2/2.1, Apache-2.0; recommended/Matrix/LICENCE;
  r-zig/LICENSE; zig's 16); r-zig-compilers, -build-tools, -extras,
  -toolchain 4 each (COPYING, GPL-2, GPL-3, r-zig/LICENSE). Every
  component F6 names for linux has its text: R, rzig (repo MIT), zig's
  MIT (compiler_rt), libc start files (glibc LICENSES), libunwind/libc++
  (LLVM text), Matrix/SuiteSparse.

- **A1 review: Windows r-zig-build-tools lacked zig's MIT text.** Its
  pkgconf.exe is zig-linked (compiler_rt, mingw-w64 CRT), the L2 case, but
  the list named only `licenses/zig/zig-source/lib/libc/mingw/COPYING`.
  Now `licenses/zig/**` as r-zig-slim (recipe/recipe.yaml, build-tools
  `license_file`). The declared `license` expressions still name no MIT
  for compiler_rt (unchanged, all outputs).
- **A2 review: recommended-licence glob used the raw `$PREFIX`.** On
  Windows that is a backslash path in a bash glob; build.sh now globs the
  `cygpath -u` form (`hp`), as it already did for `$BUILD_PREFIX`. On
  unix a no-op. A failure would have been loud (`licenses/recommended/**`
  matching nothing stops the package, V1), not a silent gap.
- **V4 review evidence:** conda-forge zig-0.17.1 for win-64 (bd21d8f_0),
  win-arm64 (d7e684b_0) and osx-arm64 (0ccaba2_0) carry the same 16
  `info/licenses` paths as linux-64 (listed from each `.conda`'s info
  tarball on delta); cairo-1.18.6 has `COPYING{,-LGPL-2.1,-MPL-1.1}` and
  pkgconf-3.0.11 `COPYING` at their top level (tarball listings). The
  six `_12` linux-64 packages' `info/licenses` were re-listed and match V3.

## Tests

| test | where | result |
|---|---|---|
| mini recipe (L1 mechanics, missing-glob failure) | delta, rattler-build 0.80.1 | V1 |
| render linux-64, win-64 | delta | V2 |
| `pixi run -e pkg conda-package` (linux-64), then `info/licenses` of each `.conda` | delta, ~/rz/wt/wave2-licences | EXIT=0, V3 (before A1/A2) |
| review: render linux-64, win-64 after A1/A2 | delta | linux lists unchanged; win-64 build-tools = top level + pkgconf COPYING + `licenses/zig/**` |
| review: build.sh licence block in a fake Windows layout (JSON-escaped `extracted_package_dir`, backslash `$PREFIX`/`$BUILD_PREFIX`, cygpath stub) | delta | copies zig's and Matrix's texts |

## Not verified

- Windows: build.sh's `cygpath -u` of `$BUILD_PREFIX` and the
  backslash unescape of `extracted_package_dir`; `cairo-src/` and
  `pkgconf-src/` texts. Needs a Windows conda-package leg (CI full tier).
- macOS, linux-aarch64: same code path as linux-64, not built.
- No linux-64 rebuild after A1/A2: A1 is win-only, A2 a no-op without
  cygpath (render and the block simulation above cover them).

## Backlog items closed

M12 (docs-backlog-hygiene F6's gap).
