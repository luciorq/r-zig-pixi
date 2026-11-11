# pkgconf from source (after phase 9; build 11)

Branch feat-zig-pkgconf, from main a211121. pixi.lock unchanged
(fbb64b7b...). TODO.md's "After phase 9: pkgconf from source" lists the
items.

## Why

Windows' `pkg-config` was conda-forge's pkg-config 0.29.2 (MSVC, with a
glib DLL closure), in the standalone tree's usr/bin and as a run
dependency of r-zig-build-tools. It prints `Libs.private` without
`--static`, so ncdf4 (PHASE7 KN d) and RPostgres (KN i) fail on Windows.
The user's decision D0 (a) of 2026-10-21 moved pkgconf out of phase 7
into this change.

## Decisions (user, 2026-11-09: "All recommended", then A)

1. A: Windows only. Unix keeps the host's or conda-forge's pkg-config:
   the default search path there is the distribution's.
2. A: built by the toolchain build (zigbuild/toolchain/build.zig) with
   pkgconf.zig, adapted from wt/feat-userland's recipe/userland/pkgconf.zig.
   The standalone build fetches the tarball as build.zig.zon's lazy
   `pkgconf` dependency; the conda build takes it as a win-64 source of
   recipe.yaml and passes the unpacked directory as `-Dpkgconf=<dir>`
   (recipe/build.sh). pkgconf.zig's `test` checks that the zon's URL and
   the recipe's URL and sha256 are its own.
3. A: r-zig-build-tools (win-64) ships
   `Library/lib/R/bin/toolchain/usr/bin/{pkgconf,pkg-config}.exe`, with
   usr/SOURCES and usr/LICENSES/pkgconf/, and drops conda-forge's
   pkg-config from its run dependencies.
4. A: pkgconf 3.0.10.
5. PKG_CONFIG_PATH, A (AMENDMENTS Am3 b): pkgconf's own search path is
   beside it (usr/lib/pkgconfig, empty), and conda-forge's pkg-config
   package, whose activation set `PKG_CONFIG_PATH`, is no longer a
   dependency. etc/Rcmd_environ (R's build.zig, rcmdEnviron) now has:

   ```
   R_ZIG_PKG_CONFIG_PATH=${R_HOME}/../../lib/pkgconfig;${R_HOME}/../../share/pkgconfig
   PKG_CONFIG_PATH=${PKG_CONFIG_PATH-${R_ZIG_PKG_CONFIG_PATH}}
   ```

   In a conda env that is `<env>/Library/lib/pkgconfig` and
   `<env>/Library/share/pkgconfig`; in the standalone tree it names
   `<top>/Library/lib/pkgconfig`, which does not exist. Limit: an env
   whose activation sets the variable keeps its value as it is.

## What changed

- zigbuild/toolchain/pkgconf.zig (new): the pins (`version`, `url`,
  `sha256`, `license` ISC), `add` (one static exe for the host's arch,
  `-windows-gnu`, baseline CPU, the source directory mapped away with
  `-ffile-prefix-map`, the UTF-8 and long-path manifest), and the pin
  tests.
- zigbuild/toolchain/build.zig.zon (new): the lazy `pkgconf` dependency.
  zig 0.16 fetches it into zigbuild/toolchain/zig-pkg/ (.gitignore).
- zigbuild/toolchain/build.zig: usr/'s seven pkg-config copies removed;
  installPkgconf builds and installs pkgconf under both names, with
  LICENSES/pkgconf/ (its COPYING and the mingw-w64 CRT's, which zig
  links into every exe), on both channels; SourcesStep writes each
  group directory's SOURCES when its files are made, so that a built
  file's line has its sha256. pkgconf's block: the tarball's URL and
  sha256, `build: zig<ver>_<arch>-windows-gnu`, `feedstock:` this
  repository and pkgconf.zig.
- build.zig (R): rcmdEnviron's PKG_CONFIG_PATH default (decision 5).
  Every `${VAR-default}` line there (CMAKE_GENERATOR, RC, RCFLAGS,
  UserNM, PKG_CONFIG_PATH) is now in double quotes: unquoted, R's
  environ reader (Renviron.c) takes each `\` of the expanded value as an
  escape, so a user's `PKG_CONFIG_PATH=C:\x\pc dir` or `UserNM=C:\x\nm.exe`
  arrived without its backslashes (found by btPc on kappa; the old lines
  had the same fault, untested because verify-bundle used `/` paths).
- recipe/recipe.yaml: the win-64 pkgconf source; r-zig-build-tools'
  files gain usr/, its run deps lose pkg-config, package_contents checks
  pkgconf's files, its win-64 licence is `GPL-3.0-or-later AND ISC AND
  ZPL-2.1`; build number 11.
- recipe/build.sh: `-Dpkgconf=<dir>` when the source is there.
- recipe/test-build-tools.R: pkgconf's SOURCES block (each name's
  sha256), LICENSES, both names run with System32 alone; under R CMD,
  PKG_CONFIG_PATH's default and `pkg-config --exists` on a .pc file of
  the env, where it has one.
- scripts/verify-toolchain.sh: `pkgconf` joins the names; pkgconf, r-zig's
  own build, fails when it names a build path.
- scripts/verify-bundle.sh: btPc gets back Am9's pkgconf leg and the
  "`--libs` has no `-lbtpc_priv`" assertion; a new check of
  PKG_CONFIG_PATH under R CMD (the default when unset, a user's kept).
- scripts/verify-tree.sh: a conda env's TC may hold usr/ (and
  binutils/); Rcmd_environ's two new lines.
- README: the Windows pkg-config note (Am3's registry key and filters).

## Tests (2026-11-09)

- `zig build test` (toolchain): 39 of 39, the three pin tests included.
- The toolchain build's pkgconf path, forced on and cross-compiled on
  linux-64 to x86_64-windows-gnu from the lazy dependency: usr/bin has
  both names (208,896 bytes, the same sha256 as the SOURCES lines),
  LICENSES/pkgconf/ both texts; the exe names no build path.
- kappa, from cmd, that exe as `pkg-config.exe` with
  `PKG_CONFIG_PATH=<env>\Library\lib\R/../../lib/pkgconfig;<env>\Library\lib\R/../../share/pkgconfig`
  (Rcmd_environ's shape, mixed separators): `--exists` finds a .pc in
  each directory, `Requires` across them resolves, the prefix is the
  .pc file's (`.../Library/lib/R/../..`), `--libs` has no
  `Libs.private`, `--static` has it. The output paths keep `..`;
  compilers and the Win32 API resolve them.
- Earlier prototype (same sources, userland build.zig): kappa, version
  3.0.10, pc_path exe-relative, the space escape, imports KERNEL32,
  ADVAPI32 and api-ms-win-crt-* only; aarch64-windows-gnu builds
  (138,240 bytes).

- kappa (win-64), the branch as it is, from cmd in its own directory:
  `pixi install --frozen`, toolchain-test, toolchain (usr/ lists
  "pkgconf (built)"), verify-toolchain (19,728 copies, 26 packages;
  build paths; 35 tools in usr/bin run with PATH = System32, pkgconf
  among them), then build, package, package-toolchain and verify-bundle,
  all three scenarios: btPc (pkg-config and pkgconf, no Libs.private
  without --static, the escaped space, the .pc file's prefix),
  PKG_CONFIG_PATH under R CMD (the default unset; a user's
  `C:\r-zig-user\pkg config` kept), UserNM with a backslash path, and
  the Git-for-Windows MSYS clash.

- kappa, `pixi run -e pkg conda-package` then conda-consume: the four
  packages build, each one's tests pass (test-build-tools.R's pkgconf
  records, both names with System32 alone, PKG_CONFIG_PATH under R CMD),
  and the consume test passes. R's runs during the build print "Setting
  LC_*=C.UTF-8 failed" (116 lines), with zig 0.16 here and with the zig
  0.17 stack alike; nothing here touches the locale (not investigated).

- kappa, `pixi run -e stress stress ncdf4 RPostgres` on the tree: both
  install and pass their smoke calls (2026-11-10; they were
  windows=fail-upstream and fail-abi). stress/packages.tsv's rows say
  windows=ok.

## Remaining

- CI on the PR, with `full-ci` and `upstream-zig`.
- A stress Windows dispatch, to confirm the kappa result in CI.
- The `_11` publish, as `_10`'s.
