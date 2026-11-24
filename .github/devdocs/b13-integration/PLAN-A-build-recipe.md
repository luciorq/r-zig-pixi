# Build 13 integration, group A (build.zig, zigbuild/, recipe/, build scripts)

Applied to the build13 worktree, uncommitted (2026-11-24).

## Needs

| need | result | notes |
|---|---|---|
| b13-recipe N1 (-Dtcltk in build.zig) | applied | scratch-b13-recipe/proto/build-zig-tcltk.diff applied cleanly (`git apply`) onto build.zig with b13-build's changes |
| b13-recipe N2 (conda-consume tcltk env) | applied | scripts/conda-consume.sh: `[feature.tcltk.dependencies]` and `[environments.tcltk]` appended to the manifest, and `tcltk:test-tcltk.R` in the loop, only when `$PLAT` is not win-arm64. An `[environments.tcltk]` sub-table, not a second `[environments]` table (TOML forbids that); generated manifest parsed with tomllib |
| b13-recipe N3 (F10, `iconv -l` on Windows) | open, not changed | the Windows conda build runs `iconv -l` (build.zig, utils/iconvlist) from the machine: no recipe package ships iconv.exe; kappa needed Git's usr/bin on PATH. Needs a decision (a recipe package with iconv.exe, or build.zig without the machine's iconv) |
| b13-rzig: Windows R_ZIG_TOOLS_PATH | applied | build.zig rcmdEnviron: `;${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin` appended, comment line extended. **Needs from group owning scripts/verify-tree.sh**: its Windows `has_line` for `R_ZIG_TOOLS_PATH=...` (verify-tree.sh:390) is an exact line and must gain the same suffix, or verify-tree fails on Windows |
| b13-rzig: Sys.unsetenv lists | applied | test-build-tools.R, test-extras.R, test-preflight.R gain `"R_ZIG_TOOLCHAIN_ENV", "R_ZIG_SYSTEM_LIBS"` |
| b13-env-ci 1: test-preflight.R pip line | applied | Windows branch dropped; Windows takes the non-linux text, `pip install r-zig-compilers (zig only: PyPI has no Fortran compiler); r-zig-toolchain installs every group`, which is groups.zig's macOS compilers line that group B's change gives Windows |
| b13-env-ci F11 (r-zig-recommended host pin) | skipped | no output has host requirements: every add-on inherits the staging output and pins r-zig-slim in run only, so a host pin is not "how the other outputs do it"; r-zig-tcltk would need the same; untestable here (win-64 conda build). Stays a follow-up: try `host: [pin_subpackage r-zig-slim exact]` on r-zig-recommended and r-zig-tcltk in one win-64 conda-package run and read the linking-check warnings |
| b13-build N4 (comments) | applied | recipe.yaml sources comment: `zig build fetch`, "configure-only.sh runs rzig too"; build.sh: "as `zig build fetch` does" |
| b13-build N5 (L7, zig-built make) | applied | see below |
| b13-build N7 (openblas link-name symlink) | applied | vendor-libs.sh's libopenblas.so / libopenblas.dylib block removed (Makeconf has no bare -lopenblas since D6); tested below |
| Build-13 comment above `number: 13` | applied | build-12 text kept; a `Build 13:` paragraph appended |

## N5: GNU make built with zig (linux, macOS)

- zigbuild/toolchain/build.zig: unix usr/ is no longer a copy of the
  env's bin/make; installMake builds it through the `r_zig_make` path
  dependency (zigbuild/make/build.zig) from `-Dmake=<dir>` (conda build)
  or build.zig.zon's lazy `make` (standalone), on both channels, as
  installPkgconf does on Windows; usr/SOURCES gets a built-file block
  (make 4.4.1, ftp.gnu.org url and sha256, GPL-3.0-or-later),
  LICENSES/make/COPYING from the source.
- zigbuild/toolchain/make.zig (new): version, url, sha256, licence, and
  tests that build.zig.zon and recipe.yaml carry them (toolchain-test).
- zigbuild/toolchain/build.zig.zon: `make` (lazy tarball, same hash as
  zigbuild/make's) and `r_zig_make` (`.path = "../make"`).
- zigbuild/make/build.zig: every compile gets
  `-ffile-prefix-map=<source>/=`: job.c's assert put the source path
  (zig-pkg under the checkout) in the binary, which verify-toolchain's
  build-path check rejects. The source path is resolved to an absolute
  one first.
- recipe: unix source make-4.4.1.tar.gz (target make-src); build.sh
  passes `-Dmake=$PWD/make-src` to zig-toolchain.sh; r-zig-build-tools
  owns `lib/R/bin/toolchain/usr/**` on unix too, drops the `make >=4.4`
  run dep, package_contents checks usr/bin/make, SOURCES,
  LICENSES/make/COPYING, and its `not_exists` names the base's
  directories (lib/R/{etc,lib,library,include,share,modules}/**,
  rzig and zig-cc) instead of `lib/R/**`; licence GPL-3.0-or-later on unix with
  make-src/COPYING and zig's texts. The build env keeps conda-forge's
  make (zig-recommended.sh runs make in the build).
- recipe/test-build-tools.R (unix): make_dir is
  R_HOME/bin/toolchain/usr/bin (put first by narrow(usr_bin = TRUE), as
  etc/Renviron does); with make off PATH rzig says "no make on PATH
  (MAKE=make)" with no "is installed in" hint (its hint looks in
  <env>/bin, where no make is now);
  new check: an R session started with a PATH without it finds the
  group's make (etc/Renviron).
- scripts/verify-toolchain.sh: make counts as r-zig's build in the
  build-path check (fails if it names the machine, as pkgconf); new unix
  check: usr/bin/make runs with PATH=/usr/bin:/bin and says the version
  SOURCES records.
- Windows unchanged (m2-make, D12).

Follow-ups for other groups (not applied, their files):
- group B (rzig check.zig notOnPath doc): "unix <dir>/bin (conda-forge's
  make and cmake)" is now cmake only; optionally a hint for R_HOME's
  usr/bin/make when rzig runs outside R.
- pixi.toml's build-tools feature still has conda-forge make for the dev
  env (needed by the dev build itself); the toolchain build no longer
  copies it.

## Tests

All on delta (linux-64, conda-forge zig 0.17.1), worktree mirrored to
~/rz/wt/build13-A and build13-A-ob (snapshot of 2026-11-24 ~11:05, other
groups' in-progress edits included).

| command | result |
|---|---|
| `zig fmt --check` build.zig, zigbuild/toolchain/{build,make}.zig, zigbuild/make/build.zig | clean |
| `pixi run toolchain-test` (incl. make.zig's zon/recipe pin tests) | 0 |
| zigbuild/make: `zig build test` with an empty global cache (lazy tarball fetch) | 0; hash N-V-__8AAO76hQBfZ... as declared. A run with the shared global cache unpacked a different hash (zig's cached p/ tarball quirk, as the toolchain zon's note on cmake says), not a pin error |
| `pixi run toolchain` + `verify-toolchain` | run 1: verify failed, make named its zig-pkg path (job.c's __FILE__) -> -ffile-prefix-map added; run 2: 0, "usr/ (make (built))", closures GLIBC <= 2.17, "usr/bin/make 4.4.1, the make version SOURCES records" |
| `-e openblas`: build, verify-tree, smoke (N7) | 0/0/0 (tree verified linux/slim-openblas, no libopenblas.so link name) |
| `toolchain`, `package-toolchain`, `-e openblas verify-package` (verify-bundle) | 0: all scenarios; build-tools scenario ran the zig-built make ("GNU Make 4.4.1, the only make that ran") |
| `rattler-build build --render-only` linux-64, osx-arm64, win-64, win-arm64 | 7/7/7/6 outputs; build-tools unix files lib/R/bin/toolchain/usr/**, licence GPL-3.0-or-later; make source on unix only |
| `pixi run -e pkg conda-package` (linux-64) | run 1: build-tools' `not_exists: lib/R/**` hit usr/ (fixed); run 2: test-build-tools.R expected exactly "no make on PATH", rzig says "(MAKE=make)" (fixed); run 3: 0, 7 packages, every test set passed; staging log "toolchain tree $PREFIX: usr/ (make (built))" |
| `pixi run -e pkg conda-consume` | 0: default, compilers, build-tools, extras, toolchain, recommended, tcltk |

Not tested: macOS (omicron) toolchain/conda build with the built make,
Windows (kappa) after the R_ZIG_TOOLS_PATH change (needs verify-tree.sh's
line too, see above), upstream zig.

## Open

- N3 (F10): `iconv -l` on the Windows conda build (above).
- verify-tree.sh:390 Windows R_ZIG_TOOLS_PATH line (other group's file).
- F11: host pin for r-zig-recommended (and r-zig-tcltk) on Windows,
  needs a win-64 conda-package run.
- macOS: the built make is untested in this integration (b13-build
  built it for macOS, D11); first CI conda-package/toolchain leg shows it.

## Suggested commit message

feat: build GNU make with zig for the unix build-tools group, add the r-zig-tcltk add-on, build 13
