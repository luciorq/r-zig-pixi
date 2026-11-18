# R's recommended packages as an opt-in build product (2026-11-13)

Item E of the release-11 pull request (#48). Record of the design, the
user's decisions, the tests run on linux-64 and what remains for macOS
and Windows.

## What and why

CRAN's R ships 15 recommended packages (MASS, lattice, Matrix, nlme,
survival, boot, cluster, codetools, foreign, KernSmooth, rpart, class,
nnet, spatial, mgcv). r-zig builds R `--without-recommended-packages`
and build.zig builds the base packages only, so every user compiled
Matrix, MASS or lattice first. They are now built by one Zig step, from
the tarballs R's source carries, with the R and the compilers this
build made, into a tree of their own, and shipped as:

- the conda package `r-zig-recommended` (same recipe, new output);
- the standalone archive `R-<ver>-<flavor>-<platform>-recommended.tar.gz`
  (Windows `.zip`), extracted over the base archive.

Neither r-zig-slim nor the base archive holds them.

## The user's decisions

- 2026-11-12: "Recommended packages need to ship on their own conda
  package", not inside r-zig-slim.
- 2026-11-13, open point 5 = A: the standalone archive's name carries
  the flavor, `R-<ver>-<flavor>-<platform>-recommended`, because mgcv
  links OpenMP and a default-built mgcv does not load on minimal. The
  conda output is `r-zig-recommended`, opt-in (nothing depends on it),
  with an exact pin on r-zig-slim.

## Design

### The step: zigbuild/recommended/build.zig

Its own small build file, as zigbuild/toolchain/build.zig is, not a step
of R's build.zig: it needs no R configure and none of that build's
options, and it runs R from another tree than the one build.zig
installs (the compile tree, which exists only after `toolchain`).

    zig build --build-file zigbuild/recommended/build.zig \
      -Dprefix=<tree> -Dr=<R tree> -Dsrc=<R source> [-Djobs=<n>]

- Nothing about the packages is typed (order.zig, with unit tests):
  the names are share/make/vars.mk's `R_PKGS_RECOMMENDED`; the order is
  the `<pkg>.ts: <dep>.ts` lines of src/library/Recommended/Makefile.in;
  R CMD INSTALL's options are that file's `INSTALL_OPTS` words that
  configure does not fill in (`--pkglock --data-compress=xz
  --no-staged-install`) plus the rule's `--byte-compile`; the tarball
  is `<pkg>_<ver>.tar.gz` found in the directory (not the `.tgz` links,
  which a Windows extraction may lose).
- One Run step per package (`R CMD INSTALL ... -l <prefix>/<R_HOME>/library
  <tarball>`; Windows R_HOME is Library/lib/R and R is bin/x64/R.exe),
  each depending on its makefile prerequisites. stdio is inherited, so
  zig runs them one at a time with live logs; the parallelism is inside
  a package: MAKEFLAGS=-j<jobs>, which rzig build's tier 1 and make
  read. `--summary all` prints each package's time.
- The rule's environment: R_LIBS unset, R_LIBS_USER and R_LIBS_SITE
  NULL, `_R_CHECK_INSTALL_DEPENDS_=no`; R_ENVIRON_USER, R_PROFILE_USER
  and R_MAKEVARS_USER name a file that does not exist (R's `--vanilla`
  there; Windows cannot hold an empty value, so one form everywhere);
  R_ZIG_EXTRA_ENV removed, so rzig adds no include, lib or rpath of the
  pixi env to files that ship.
- Install test load kept (R's makefile does not pass --no-test-load).
  `--install-tests` is not passed: unix's rule does not, Makefile.win
  does; one way on every OS.
- Rejected: a bash loop over the tarballs (the order would be typed
  again, and it is shell); a step of R's build.zig (it would need R's
  configure and options to run, and the compile tree is made after it);
  installing into the R tree itself (verify-tree would see them and the
  base archive would carry them).

### Where it runs

- Dev: `scripts/zig-recommended.sh` (pixi task `recommended`, after
  `compile-tree`) installs with the compile tree's R (R tree plus the
  toolchain groups: Matrix's makefile rules need make) into env.sh's
  `RECOMMENDED_PREFIX`, `dist/recommended/<flavor>/R-<ver>-zig`. The R
  tree is only read. rzig's own cache is build/rzig-cache, as
  contract-test.sh has it; this zig build's own cache is env.sh's local
  zig cache (`--cache-dir`), not zigbuild/recommended/.zig-cache.
  `pixi run clean` removes the tree with the R tree it was built against.
- Conda: recipe/build.sh's last line sets `R_RECOMMENDED_PREFIX=$PREFIX`;
  the R tree is then the env too, and the recipe's file globs divide the
  files.

### The conda package

- `r-zig-recommended`, `inherit: {from: r-zig-build, run_exports: false}`,
  files `lib/R/library/<15>/**` and `Library/lib/R/library/<15>/**`.
  r-zig-slim's `files.exclude` has the same two globs (one context
  variable, `recommended`), so --error-unused-staging-files and
  --error-overlapping-files hold; slim's package_contents test says
  none of the 15 is there.
- Run: `pin_subpackage("r-zig-slim", exact=True)` only. Measured on
  linux-64 (verify-recommended): the package binaries need libR,
  libRblas, libRlapack, libomp (mgcv) and libc/libm only, all slim's or
  the system's; the Fortran runtime is static (KernSmooth links
  libflang_rt.runtime.a).
- Test: recipe/test-recommended.R (also conda-consume's new
  `recommended` environment): the 15 installed, as R's own
  `tools:::.get_standard_package_names()$recommended` lists them, each
  with a License field and loaded; a Matrix sparse Cholesky and LU
  solve; an mgcv gam fit on two threads (OpenMP); survival's coxph on
  lung; nlme's lme on Orthodont; MASS's glm.nb and lqs; cluster's pam,
  class's knn, nnet, rpart, spatial's surf.ls, KernSmooth's bkde
  (Fortran), foreign's dbf round trip, lattice, boot, codetools.
- Licence: no license_file, as the other outputs. about.license is the
  DESCRIPTIONs' licences in SPDX: GPL-2.0-or-later (cluster, foreign,
  lattice, mgcv, nlme, Matrix, codetools' "GPL"), GPL-2.0-only OR
  GPL-3.0-only (class, MASS, nnet, rpart, spatial), LGPL-2.0-or-later
  (survival), LicenseRef-Unlimited (boot, KernSmooth), and Matrix's
  bundled SuiteSparse (its LICENCE file): BSD-3-Clause,
  LGPL-2.1-or-later, Apache-2.0 (METIS). The texts are in each package's
  directory (DESCRIPTION, Matrix/LICENCE, Matrix/doc/SuiteSparse/).
- Nothing depends on it (opt-in), r-zig-toolchain included.

### The standalone archive

`pixi run package-recommended` (package-standalone.sh's `recommended`
mode) archives RECOMMENDED_PREFIX as
`dist/R-<ver>-<flavor>-<platform>-recommended.<ext>`, top directory
R-<ver>-zig/, extracted over the base archive.

### verify-recommended (scripts/verify-recommended.sh)

The tree holds R_HOME/library/<15>/ and nothing else (no 00LOCK, build
root or object file); every library a package binary needs is the
base's (R_HOME/lib, <prefix>/lib, Windows R_HOME/bin/x64) or the
system's; linux: bare names, glibc at most 2.17; macOS: install names
relative or the system's, minos at most 13.0; no shared C++ runtime;
rpaths relative; no build path in any file or in R's compressed files
read uncompressed; then test-recommended.R with the base's R and the
tree's library in R_LIBS.

One object may name the install directory. R CMD INSTALL saves the
namespace's information, with the install directory, as the variable
`.__NAMESPACE__.` in R/<pkg>.rdb, and R never loads it
(share/R/nspackloader.R: `lazyLoad(..., filter = function(n) n !=
".__NAMESPACE__.")`; loadNamespace records where it found the package
instead). scripts/uncompress-r-objects.R walks a database as R loads
it: the variables, then the environments they refer to, in turn. It
writes `.__NAMESPACE__.`, with what only it refers to, to a file of its
own, `<name>.rdx.namespace`, and everything else to `<name>.rdx`.
verify-recommended passes the `.rdx.namespace` files and checks every
other file. verify-tree.sh checks every file, the namespace files too
(build.zig makes base's namespace paths relative), so its coverage is
the same as before.

A first version allowed the text `.../<R_HOME>/library/<pkg>` anywhere
in R/<pkg>.rdx. Review (2026-11-13) found that this would also pass a
package that stores its install directory in an object R does load;
the walk tells the two apart by object.

scripts/uncompress-r-objects.R (shared with verify-tree.sh) now also
reads an environment reference saved with lazy parts (eagerKey and
lazyKeys: survival's data database has three, srcfile environments);
before, it stopped with "bad offset/length argument". verify-tree.sh
reads the base tree with the same walk and still passes (168 files read
uncompressed, 157 before: the 11 new ones are base's namespace files).

verify-recommended's leftover check lists every 00LOCK, .rzig or object
file and prints the count and the first five; with `| head` in the
command substitution, many leftovers made find die of SIGPIPE under
`pipefail` and the script exited 141 with no message.

## Measurements (linux-64, gamma, slim, -Djobs=6, a busy 16-CPU machine)

`RZIG_TRACE=1 pixi run --frozen recommended -- -Djobs=6 -j6 --summary all`:
271 s wall, the compile tree copy included.

| package | tier | time | size (apparent) |
| --- | --- | --- | --- |
| Matrix | make (Makevars rule `$(SHLIB): $(sslib)`, SuiteSparse) | 60 s | 8.3 MB |
| mgcv | 1 (OpenMP) | 37 s | 4.2 MB |
| survival | 1 | 23 s | 9.1 MB |
| lattice | 1 | 13 s | 1.8 MB |
| nlme | 1 | 12 s | 2.6 MB |
| spatial | 1 | 8 s | 0.2 MB |
| MASS | 1 | 6 s | 1.3 MB |
| rpart | 1 | 5 s | 0.8 MB |
| foreign | 1 | 4 s | 0.4 MB |
| KernSmooth | 1 (Fortran) | 4 s | 0.3 MB |
| boot | no code | 3 s | 0.7 MB |
| cluster | 1 | 3 s | 0.7 MB |
| codetools | no code | 2 s | 0.1 MB |
| nnet | 1 | 2 s | 0.1 MB |
| class | 1 | 1 s | 0.1 MB |

Total 30.7 MB installed; the archive is 25.0 MB (tar.gz). Only Matrix
needs the build-tools group (make) at build time; the recipe's build
env has make on every OS.

CI: the conda-package job builds them on every leg. About 3 minutes on
linux; macOS similar; Windows compiles slowest (expect 2 to 3 times);
the 90 minute limit (120 on win-arm64) holds a large margin by the
current leg times (win-64 about 15 minutes when healthy). No cache is
needed now; if Windows grows, the packages without dependencies could
run as parallel steps (zig runs non-inherit Run steps concurrently),
at the cost of interleaved logs.

## Files

- zigbuild/recommended/build.zig, order.zig (new): the step and its
  makefile readers with unit tests.
- scripts/zig-recommended.sh (new), scripts/verify-recommended.sh (new).
- scripts/env.sh: RECOMMENDED_PREFIX (R_RECOMMENDED_PREFIX override).
- scripts/package-standalone.sh: the `recommended` mode.
- scripts/uncompress-r-objects.R: environment references with lazy
  parts; walks a database as R loads it, `.__NAMESPACE__.` to
  `<name>.rdx.namespace`.
- scripts/clean.sh: removes RECOMMENDED_PREFIX too.
- scripts/conda-consume.sh: the `recommended` environment.
- pixi.toml: tasks recommended, recommended-test, verify-recommended,
  package-recommended.
- recipe/recipe.yaml: context `recommended`, the r-zig-recommended
  output, r-zig-slim's exclude and not_exists. recipe/build.sh: the last
  step. recipe/test-recommended.R (new).

## Tests (linux-64, gamma, 2026-11-13)

| command | exit |
| --- | --- |
| `zig test zigbuild/recommended/order.zig` (4 tests) | 0 |
| `pixi run --frozen recommended-test -- --summary all` | 0 |
| `pixi install --frozen` | 0 |
| `pixi run --frozen build -- -j6` | 0 |
| `pixi run --frozen smoke` | 0 |
| `pixi run --frozen verify-tree` (before the step) | 0 |
| `pixi run --frozen toolchain -- -j6` | 0 |
| `pixi run --frozen compile-tree` | 0 |
| `RZIG_TRACE=1 pixi run --frozen recommended -- -Djobs=6 -j6 --summary all` | 0 (271 s) |
| `pixi run --frozen verify-recommended` (first run) | 1: uncompress-r-objects.R could not read survival's data database, then every package's saved namespace path; both fixed above |
| `pixi run --frozen verify-recommended` | 0 |
| verify-recommended on a copy with a stray file / a build path added | 1, 1 (as meant) |
| `pixi run --frozen verify-tree` (after the step) | 0 |
| `pixi run --frozen package-recommended` | 0 (24986563 bytes) |
| the archive extracted over a moved copy of the base, test-recommended.R under `env -i` | 0 |
| `rattler-build build --render-only` for linux-64, win-64, osx-arm64 | 0, 0, 0 |
| `pixi run -e pkg --frozen conda-package` | 0 (964 s with the lock queue; r-zig-recommended 22.6 MiB, its test passed) |
| `pixi run -e pkg --frozen conda-consume` (five environments) | 0 |

Review fix pass (2026-11-13), after the four review findings:

| command | exit |
| --- | --- |
| `pixi run --frozen recommended-test -- --summary all` (with `--cache-dir`; no zigbuild/recommended/.zig-cache made) | 0 |
| uncompress-r-objects.R on two test packages installed with `--no-staged-install`: tp0 (no stored path), tp1 (`where <- Sys.getenv("R_PACKAGE_DIR")`) | 0, 0; the install dir is named by tp0: R/tp0.rdx.namespace only; tp1: R/tp1.rdx.namespace and R/tp1.rdx (the stored object, which verify-recommended now fails). The old script put both in R/<pkg>.rdx |
| verify-recommended on a copy with 5000 `*.o` files | 1, with the message, count and first five (was 141, silent) |
| `pixi run --frozen verify-tree` (new walk over the base tree) | 0 (168 files read uncompressed) |
| `pixi run --frozen recommended -- -Djobs=6 -j6 --summary all` (with `--cache-dir`) | 0 (15 DONE; no zigbuild/recommended/.zig-cache) |
| `pixi run --frozen verify-recommended` (after that rebuild) | 0 (197 uncompressed R objects; the 15 namespace files passed by name) |
| `pixi run --frozen package-recommended` | 0 |
| `zig fmt --check zigbuild/recommended/`, `zig test zigbuild/recommended/order.zig`, `bash -n scripts/*.sh recipe/build.sh` | 0, 0 (4/4), 0 |

conda-package and conda-consume were not run again: the fix pass
changed no recipe file; zig-recommended.sh (run by recipe/build.sh)
only gained `--cache-dir`, which the dev run above covers.

The conda package: depends `r-zig-slim ==4.6.2 <slim's build>`, files
only under lib/R/library/<15>/ (plus its test file), the package
libraries' rpath `$ORIGIN/../../../..` (the env's lib), 30.7 MB
installed. --error-unused-staging-files and --error-overlapping-files
held.

## Not done / to test on macOS and Windows

- macOS (osx-arm64, osx-64) and Windows (win-64, win-arm64) never ran
  the step. To check there: the R CMD INSTALL path (Windows: bin/x64/R.exe
  and C:/ paths through cygpath -m), Matrix's make path, mgcv's OpenMP,
  verify-recommended's load-command and DLL checks, the archive, and
  the conda output with conda-consume.
- linux-aarch64: CI's conda-package leg only.
- minimal: a minimal-built mgcv (no OpenMP) is not tested; the archive
  name keeps flavors apart.
- CI's build-r.yaml does not run `recommended` / `verify-recommended`;
  only conda-package exercises the step in CI.
