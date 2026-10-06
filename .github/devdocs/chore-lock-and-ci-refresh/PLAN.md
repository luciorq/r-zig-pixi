# chore-lock-and-ci-refresh — one solve group for R's environments, a full lock update, current CI actions

**Status (2026-10-06).** Branch chore-lock-and-ci-refresh, from main at
53687ab (the merge of feat-no-host-paths, PR #12). Not committed. It
changes pixi.toml (a solve group and its comment), pixi.lock (one
deliberate full `pixi update`) and three workflows (action versions and a
pixi version pin). recipe/, scripts/, build.zig and zigbuild/ are
untouched, and the recipe's build number stays 4. Tested on linux-64,
osx-arm64, osx-64 under Rosetta and win-64, and macOS again after the
lock's last re-solve (see "Tested"); no CI run yet (see "CI to watch").

Why (the user, 2026-10-06): lock inertia had left the environments on
different builds of the same packages (zig_impl 0.16.0 `_15` in default
against `_19` in minimal; libomp 22.1.8 against 23.1.2 until the OpenMP
work pinned 23.*), and the project pins versions, never build numbers
(consolidation PLAN.md, convention 2). rattler-build solves fresh and
does not read pixi.lock, so an old lock tests against packages the
conda package no longer gets. And GitHub warns that
actions/upload-artifact@v4 runs on the deprecated Node.js 20;
ubuntu-latest moves to Ubuntu 26.04 from 2026-10-19.

The existing pins are unchanged: zig 0.16.*, llvm-openmp 23.*, tk 8.6.*,
flang-rt-zig build-number >=9 (>=4 on win-64), pango 1.56.*, harfbuzz
14.2.*, rattler-build >=0.70.

## The solve group

- **What.** `solve-group = "r"` on pkg, default, full, openblas,
  full-openblas and minimal (pixi.toml `[environments]`, with the reason
  in the comment above it). wheel is not in it.
- **What a group does** (pixi's manifest reference,
  https://pixi.prefix.dev/latest/reference/pixi_manifest/, the
  environments table, the same text at the v0.81.0 tag): "These
  dependencies will then be the same version in all environments that
  have the same solve group. But the different environments contain
  different subsets of the solve-groups dependencies set." In pixi
  v0.81.0's source the group is solved once per platform from its
  members' combined dependencies (FeaturesExt::combined_dependencies,
  crates/pixi_manifest/src/features_ext.rs), and each environment then
  takes the records its own specs reach (spawn_extract_environment_task,
  crates/pixi_core/src/lock_file/update.rs).
- **Different platform lists.** minimal has no win-64. Allowed since
  pixi 0.66.0 (#5538, "Allow to solve environments with different
  platforms in the same solve group"): combined_dependencies leaves out a
  feature that does not support the platform, so the group's win-64
  solve leaves minimal's features out (pixi's own test
  test_solve_group_heterogeneous_platforms covers this). pixi.lock is
  format 7, which already needs pixi 0.68 or newer, so no
  `requires-pixi` is needed.
- **A group can still add packages.** It adds no other environment's
  specs, but the one build it keeps of a shared package brings that
  build's own dependencies. Compared with a fresh solve of the same
  repodata without the group (2026-10-06; repeated by three later runs
  with the same result):
  - minimal: identical on all four of its platforms. It gains no
    graphics stack and nothing else; its icu, libxml2, readline and
    llvm-openmp were there before, through zig's LLVM, flang-rt-zig and
    libpsl.
  - default, openblas and pkg (unix): libdeflate 1.25, not 1.26, because
    full's libtiff 4.7.2 needs `libdeflate >=1.25,<1.26`.
  - full and full-openblas (linux-64, linux-aarch64): gawk 5.4.1 and
    gettext 0.25.1, plus gmp and mpfr, which the other R envs already
    had. Solved alone they would take gawk 5.1.0 (a 2021 build) and
    gettext 1.0 with json-c, because gawk 5.4.1 needs
    libasprintf/libgettextpo <1.0.
  - wheel and every win-64 env: identical.
- **The trap, for later re-locks.** Adding the group with plain `pixi
  lock` (the old lock as preferences) kept default's pkg-config `_1009`,
  which links libglib, and so added libglib and libffi to minimal on
  linux-aarch64 and osx-arm64, and libgcc-ng and libstdcxx-ng on linux.
  The full update picks `_1013` and adds none. After any partial re-lock,
  check minimal with `pixi list -e minimal --platform <p> --frozen`
  (the pixi.toml comment says so); verify-tree checks only what R links.
  On this lock a deny-list of the graphics stack (cairo, pango,
  harfbuzz, glib/libglib, fontconfig, freetype, pixman, fribidi,
  graphite2, libpng, libjpeg-turbo, libtiff, libwebp, tk, libxcb,
  xorg-*, libffi) matches nothing in minimal (62 packages on each linux,
  55 on each macOS).
- **The effect.** Packages with more than one (version, build) per
  platform across the six environments: 44/44/40/40/0 (linux-64,
  linux-aarch64, osx-64, osx-arm64, win-64) in main's lock, 0 everywhere
  now. pixi.lock went from 740 to 546 distinct records (617 KB to 535
  KB).
- **Why wheel is out.** It is Python-only: nothing in it builds or links
  R, so it gains nothing from alignment, and in the group its python and
  libcxx would be held to R's (zig_impl holds libcxx at 21.* on macOS;
  wheel has 23.1.2). The premise that keeping wheel out keeps libcxx out
  of R's build envs does not hold: libcxx 21.1.8 (macOS) and libstdcxx
  (linux) are already in every R build env through zig_impl/libllvm21,
  icu, krb5 and libpsl, and python 3.14.8 with libpython is in every R
  env but minimal because conda-forge's `glib` depends on python (open
  question below).

## The lock update

One `pixi update` of every environment and platform with pixi 0.81.0,
repodata as of about 16:35 UTC 2026-10-06 (lock sha256 9b38d7d2...,
the one the test rounds ran on). Re-solved at 18:00 UTC, after those
rounds: the branch's pixi.lock is now sha256
e9f17d315fd52ccf58db6a9840379e787e5c51ad80406982f907faa2dc1b9513, which
differs from 9b38d7d2 only in libcxx 21.1.8 build `_4` instead of `_3`
on osx-64 and osx-arm64 (a build the first solve's repodata did not have
yet; byte-identical to two earlier re-solves at 17:23 and 17:27 UTC).
The linux and win-64 packages are the same in both locks. The diff
below is main's lock against 9b38d7d2.

Behaviour-relevant moves first (main's lock to this one; "R envs" means
default, full, openblas, full-openblas and pkg):
- **zig.** zig, zig_impl_<subdir> and zig_<subdir> 0.16.0 `_15` (R envs)
  and `_19` (minimal) to `_20` on all five platforms. conda-forge
  zig-feedstock PRs #176 (build 17), #188 (18), #190 (19) and #198 (20,
  tests only). #190 runs the recipe scripts under brush and drops
  patches/non_unix/Lld.zig-remove-ucrt.patch, so zig's UCRT append is
  back in Windows links (described as an aarch64-MSVC fix); none of them
  mentions the glibc stubs. Together with it, in the R envs on the four
  unix platforms (minimal had them already): libllvm21 21.1.8 `_0` to
  `_1` and libclang-cpp21.1 21.1.8 `_4` to `_6`, the libraries
  conda-forge's zig loads. So `zig cc` itself changed: its version
  string now names clangdev-feedstock 334cf9a5, not 0b2bbeec.
- **Unchanged:** flang-zig, flang-rt-zig (`_9`; win-64 `_4`), lld-zig,
  llvm-openmp 23.1.2, pango 1.56.4, harfbuzz/libharfbuzz 14.2, libcxx
  21.1.8 (`_3`; `_4` after the re-solve), binutils_impl_win-64, every
  m2-* package, patch, sed, bash, tar, gzip.
- **Network:** libcurl/curl 8.21.0 to 8.22.0 (minimal had it), libpsl
  0.22.0 to 0.23.1, openssl 3.6.3 to 3.6.5 (minimal and wheel 3.6.4 to
  3.6.5); libssh2, libnghttp2, krb5, c-ares, zstd, zlib, xz, bzip2 and
  pcre2 are new builds of the same versions.
- **icu** 78.3 `_1` to `_2` (minimal had `_2`; the `py310`/`py311`/
  `py313` build strings are a feedstock quirk, the package does not
  depend on python). wheel no longer has icu (libsqlite 3.53.4 dropped
  it).
- **Graphics:** cairo 1.18.4 to 1.18.6; glib/libglib 2.88.2 to 2.90.0;
  libffi 3.5.2 to 3.7.0; fontconfig 2.18.2 to 2.18.3; fribidi 1.0.16 to
  1.0.17; expat 2.8.1 to 2.8.5; libpng 1.6.58 to 1.6.59; freetype,
  pixman, graphite2, libxcb and xorg-* new builds. full only: lerc 4.1.0
  to 4.2.0, new builds of libtiff, libjpeg-turbo, libwebp-base.
- **tk** 8.6.13 `_3` to `_4` on every platform (the 8.6.* pin held).
- **GCC runtime, linux:** libgcc, libstdcxx and libgomp 15.2.0 to 16.2.0
  (libgcc-ng/libstdcxx-ng gone); openblas envs: libgfortran 15.2.0 to
  16.2.0 (linux and macOS). The vendored libstdc++ 6.0.36 still needs at
  most GLIBC_2.17, libgcc_s GLIBC_2.14, libgomp GLIBC_2.17 (`objdump
  -T`), and every package still declares `__glibc >=2.17` (2.28 only for
  the build-only sysroot and uutils-coreutils, as before).
- **macOS baseline:** 29 packages in the osx-64 R envs moved to (or
  gained) `__osx >=11.0`; the highest is 11.0, below MACOS_MIN 13.0.
- **win-64:** libgcc and libgomp 15.2.0 to 16.2.0; vc14_runtime and
  vcomp14 14.51.36231 to 14.51.36247.
- **Other:** libxml2 2.15.3 to 2.15.4; python 3.14.6 to 3.14.8, which
  now ships libpython as its own package; make 4.4.1 new build;
  uutils-coreutils 0.9.0 to 0.12.0; coreutils 9.5 to 9.12
  (linux-aarch64); patchelf 0.17.2 to 0.19.2; pkg-config `_1009` to
  `_1013`; rattler-build 0.70.0 to 0.76.1 (pkg).

Does the vendored configure output still match? On linux-64 the real
configure capture (fetch-r.sh, configure-only.sh, gen-subst.sh) was
re-run with the new lock: minimal is byte-identical to
zigbuild/config/linux-x86_64-minimal, slim and full differ only in
CC_VER (the clangdev commit above). On linux-aarch64, osx-64 and
osx-arm64 the pkg-config files of every changed package were compared:
only glib-2.0.pc's Libs.private order (linux-aarch64) and sqlite3.pc's
Libs.private (no ICU) changed, and neither reaches a vendored config (R
reads Libs.private only for static cairo/libpng; R does not use
sqlite3). The win-64 config is hand-written. CC_VER was not refreshed:
it reaches only R_compiled_by(), the vendored configs were already mixed
(osx-* have no commit, linux minimal had 334cf9a5 already), and
refreshing it changes libR, which would mean build 5 for a cosmetic
string.

**Universe.** The lock has 15 package URLs under
https://prefix.dev/universe (flang-zig, flang-rt-zig and lld-zig for
five subdirs), the same 15 in both locks; all answer 200 (curl -I -L,
2026-10-06, checked three times by different runs, the last at 17:40
UTC). The two libcxx `_4` URLs the re-solve added answer 200 too.

**The zig cache key.** env.sh keys zig's caches on `cksum < $ZIG`
(scripts/env.sh:124); conda-forge's bin/zig is a symlink to the
zig_impl binary, so the key follows zig_impl. `_20`'s keys:
linux-64 zig-3257041897-30115392 (`_15` was zig-4088085285-30139584),
osx-arm64 zig-4103495474-27717392, osx-64 zig-3304267335-30901040,
win-64 zig-4052344430-170182656 (`_15` was zig-4199664326-170184704).
Every test run cleared build/zig-cache first, and after the builds the
cache held only the `_20` key. The key does not cover libLLVM or
libclang-cpp: an update that moved only those would keep the key and
reuse objects the old LLVM built. Not the case here (the binary changed
too); a proposal is in the open questions.

## CI actions and pixi

Every `uses:` before this branch: actions/checkout@v6 (build-r.yaml,
build.yaml, gen-config.yaml), prefix-dev/setup-pixi@v0.10.0 (the same
three), actions/upload-artifact@v4 (build-r.yaml, gen-config.yaml), and
the local ./.github/workflows/build-r.yaml (build.yaml, upstream-zig.yaml,
which has no other `uses:`). No composite actions, no dependabot.yml.
Only upload-artifact@v4 ran on Node 20 (its action.yml: `using:
'node20'`); the others were node24 already. Releases and action.yml
read through the GitHub API, 2026-10-06.

- **actions/checkout v6 to v7** (latest v7.0.1, 2026-07-20). action.yml
  is byte-identical (same inputs). v7.0.0's one breaking change refuses
  to check out fork pull-request code under `pull_request_target` or
  `workflow_run` unless `allow-unsafe-pr-checkout: true`; we use push,
  pull_request, workflow_dispatch and workflow_call. No usage change.
- **actions/upload-artifact v4 to v7** (latest v7.0.1, 2026-04-10). v5
  had Node 24 support but defaulted to Node 20; v6 runs on Node 24 and
  needs runner 2.327.1 or newer (hosted runners are 2.337.0); v7 moves to
  ESM and adds `archive` (default true, so still a zip). Naming and
  immutability are as in v4: names unique within a run, artifacts
  immutable, `overwrite` false, hidden files excluded. Ours fit:
  r-zig-wheel-<os> comes from the four minimal legs, one per OS;
  config-<platform>-<variant> differs per gen-config leg; neither path
  holds dotfiles. `archive: false` is not used (the artifact would be
  named after the file and `name` ignored). No usage change.
- **prefix-dev/setup-pixi v0.10.0 to v0.11.0** (released 2026-10-06
  16:16 UTC; 194 successful check runs on its commit). The one breaking
  change removes `persist-credentials` (now `auth-logout`) and runs `pixi
  auth status` after login; both apply only with `auth-host`, which we
  never set (publishing uses rattler-build's own OIDC). src/cache.ts
  changed only in a lint comment, so the cache key and defaults (cache
  on, `locked` when pixi.lock exists) are as before. v0.10.2 added
  linux-riscv64. v0.10.2 would behave the same for us.
- **pixi in CI: a new pin, `pixi-version: v0.81.0`,** on all three
  setup-pixi steps (the reason in build-r.yaml, a pointer in the other
  two). Unset, setup-pixi installs the newest pixi on every run (its
  src/options.ts), which was already 0.81.0 (run 37482616655 on main
  logged "Pixi version: 0.81.0"). v0.81.0 (2026-09-15) is the latest
  pixi and the one that wrote pixi.lock. Reasons: CI runs the pixi that
  wrote the lock, and setup-pixi's env cache key hashes the pixi binary,
  so "latest" dropped every cached env on each pixi release (four
  between 2026-08-28 and 09-15). Cost: Dependabot does not bump this
  input, so it is bumped by hand with the lock. pixi's notes from 0.77.0
  to 0.81.0 say nothing about --locked/--frozen, the lock format or solve
  groups.
- **rattler-build in the pkg env: 0.70.0 to 0.76.1** (the latest
  release, 2026-09-14), moved by the full update; the spec stays
  `>=0.70`, a floor with a recorded reason (feat-prefix-publish/PLAN.md:
  OIDC publishing needs 0.31.1 or newer). Release notes 0.70.1 to 0.76.1
  read against recipe/recipe.yaml and build.sh:
  - No recipe-format change. Staging outputs now inherit all top-level
    build settings (#2641; ours is only `number: 4`); tests wait until
    the outputs they need are built (#2686; r-zig-toolchain's test needs
    r-zig-slim); @executable_path rpaths are kept (#2718; build.zig
    writes only @loader_path); `files: []`, deletion-only patches,
    disabled relocation and SRC_DIR in tests do not apply to us.
  - May touch us: Windows RuntimeEnv lookups are case-insensitive
    (#2676, PATH vs Path); the solver prefers a candidate's most
    restrictive requirement (rattler, 0.74); new warnings for
    overlapping output files and unused staging files (#2790; none in
    the linux-64 build); the
    staging cache key gains used_variant but still does not hash `path:`
    sources (#2804), so conda-package's `rm -rf dist/conda/build_cache`
    stays.
  - CLI (`--help` diffed): `--env-isolation` (default strict),
    `build --skip-existing` and `upload prefix --skip-existing` are
    unchanged; new `--error-overlapping-files` and
    `--error-unused-staging-files` (warnings by default).
  - `rattler-build build --render-only` of recipe/recipe.yaml exits 0 on
    all five platforms with 0.76.1, and the build strings equal build 4's
    on universe: linux-64 hb0f4dca_4/hf9c1e0e_4, linux-aarch64
    he8cfe8b_4/h390d1ea_4, osx-64 he0379dc_4/hefa434f_4, osx-arm64
    h41cfa24_4/h6f07afa_4, win-64 h9490d1a_4/hc21f241_4 (r-zig-slim/
    r-zig-toolchain).
- **Validation.** `pixi exec --spec actionlint --spec shellcheck --
  actionlint` (actionlint 1.7.12, shellcheck 0.11.0): 0 errors in 4
  files; all four workflows parse as YAML.

## Recipe build number: stays 4

Build 4 of r-zig-slim and r-zig-toolchain is on universe in all five
subdirs (2026-10-06 14:53-14:57 UTC, run 37482616655, the push of
53687ab, this branch's base). This branch changes no recipe input:
recipe/, scripts/, build.zig and zigbuild/ are untouched, none of them
reads pixi.toml or pixi.lock, and rattler-build solves fresh. The only
packaging input that moves is rattler-build itself (0.70.0 to 0.76.1),
which records its version in info/recipe/rendered_recipe.yaml, as
metadata. The build strings are unchanged, so a publish from main would
be skipped by `--skip-existing` and the channel keeps build 4. The
linux-64 build with 0.76.1 confirms it (see Tested): the same build
strings and file lists as build 4, and depends that differ only by
conda-forge drift (one libharfbuzz run export). What would reverse
this: a 0.76.1 build on another platform whose file list or depends
differ from build 4's for another reason; then bump to 5 with a history
line in recipe.yaml's style.

## Ubuntu 26.04 (ubuntu-latest from 2026-10-19)

actions/runner-images issue 14748 (2026-09-17): only x64 ubuntu-latest
moves, rolled out 2026-10-19 to 2026-11-19; ubuntu-24.04-arm stays.
Ubuntu 24.04.5 to 26.04.1, glibc 2.39 to 2.43, kernel 6.17 to 7.0. Our
legs on it: build.yaml's linux-64 default, full, openblas and minimal,
conda-package linux-64, and upstream-zig's ubuntu leg; gen-config has
none.

- **pixi and the glibc checks.** Nothing we ship depends on the host's
  glibc: zig targets 2.17, setup-pixi installs pixi's static musl binary
  on linux, the lock's packages need `__glibc >=2.17` (2.28 for build-only
  tools), and the wheel's manylinux tag comes from the shipped ELF files.
  verify-tree's ceiling check (scripts/verify-tree.sh) reads our ELF
  files with the host's objdump (binutils 2.46 on the 26.04 image). If
  objdump were missing, every ceiling would come back empty and be
  skipped, and the check would pass with an empty "runtime worst".
- **strace.** hermetic-check.sh and verify-bundle.sh use the host's
  strace (not in pixi.toml) and fall back quietly when it is missing or
  cannot trace ("note: strace unavailable; checked with an empty PATH
  only"; "build-env CA check skipped"). It works on 24.04 (run
  37482616655). On 26.04 it is expected through ubuntu-standard's
  Depends (archive.ubuntu.com, resolute), not observed.
- **Host coreutils.** 26.04's default coreutils are the uutils (Rust)
  ones (coreutils-from-uutils); /bin/sh is still dash. hermetic runs with
  the tree's bin/ plus /bin/sh, but verify-package deliberately runs R
  and `R CMD SHLIB` with `PATH=/usr/bin:/bin` as a user machine would
  (scripts/verify-bundle.sh), so R's scripts and make recipes get the
  host's uutils there.
- **What to read in the first ubuntu-latest runs after 2026-10-19:**
  hermetic prints "programs started:", not "note: strace unavailable";
  verify-package prints "TLS trust verified (no CA file read from the
  build env)", "standalone bundle verified relocatable" and every
  "compiled package verified:" line (C++, Fortran, `$(FLIBS)` without a
  Fortran compiler, OpenMP); verify-tree prints a non-empty "runtime
  worst 2.17 (...)". A failure only there points at the host userland
  first.
- **Proposed pin: none applied, none needed for correctness.** The
  cautious option is `runner: ubuntu-24.04` on build.yaml's
  conda-package linux-64 entry, the leg that publishes, until one run on
  26.04 has passed the lines above; its output does not depend on the
  host, so this record does not recommend it. Better, if GitHub already
  offers the `ubuntu-26.04` label: before 2026-10-19, one dispatch of
  build.yaml from a throwaway branch with its linux-64 legs on that
  label.

## Tested

The first round ran on lock 9b38d7d2 on every machine (its sha256
checked before and after each install; omicron's osx-64 copy re-solves
for `platforms = ["osx-64"]`, and its osx-64 packages were compared with
the lock's: identical in every environment). Every copy started without
a zig cache (cleared, or a new copy) and held only the `_20` key after
its builds. All on 2026-10-06, times EDT.

- **linux-64** (dev machine, the worktree, 13:34-14:00): `pixi run
  rzig-test` (42/42 tests); default: build, verify-tree ("runtime worst
  2.17 (lib/libglib-2.0.so.0)"), smoke, contract (Rcpp, data.table,
  minqa, quadprog, pak, ps), check (one NOTE, tools-Ex, grid's vignette
  metadata, as before), hermetic ("programs started:"), verify-package
  (relocatable, TLS, every compiled-package line including both OpenMP
  ones); minimal: build, verify-tree, verify-package, then `-e wheel
  wheel` (manylinux_2_17, 48.2 MiB, highest need GLIBC_2.17) and
  wheel-test; full: build, verify-tree; openblas: build, smoke; `-e pkg
  conda-package` with rattler-build 0.76.1 (both outputs built, their
  tests passed, no overlapping-file or unused-staging warnings). All
  passed.
- **The 0.76.1 packages against build 4** (linux-64, compared with the
  channel's files): the same build strings (hb0f4dca_4, hf9c1e0e_4) and
  the same file lists (1860 and 6 paths); r-zig-toolchain's depends are
  identical; r-zig-slim's differ in one run export, `libharfbuzz
  >=14.5.1` to `>=14.6.0`, from the newer harfbuzz conda-forge has now
  (drift: the recipe solves fresh). rendered_recipe.yaml records
  rattler-build 0.76.1 instead of 0.70.0. No content change from this
  branch, so build 4 stands.
- **osx-arm64** (omicron, a new copy, 13:33-13:43): default build,
  verify-tree, smoke, contract, verify-package; minimal build and
  verify-tree. All passed.
- **osx-64 under Rosetta** (omicron, a new copy, 13:33-13:52): default
  build, verify-tree, smoke, contract, verify-package; minimal build and
  verify-tree. All passed.
- **win-64** (kappa, a new copy, 13:51-14:15): build (zig `_20`, 6.5
  min), verify-tree, smoke, contract, check (the two known NOTEs,
  tools-Ex and stats-Ex), hermetic, verify-package (relocatable; OpenMP
  packages from the tree alone). All passed. So the MinGW links work
  with zig `_20`, whose feedstock dropped the Lld.zig UCRT patch.
- **Second round, macOS, on the re-solved lock e9f17d31** (libcxx `_4`;
  omicron, new copies, from 14:01): osx-arm64's first build step failed
  downloading R's source from CRAN (`curl: (56) Recv failure: Connection
  reset by peer`), so verify-tree and smoke found no tree; verify-package,
  which builds the tree itself, passed, and so did minimal's build,
  verify-tree ("macOS floor verified: 40 Mach-O files, minos <= 13.0")
  and verify-package. Re-run on that copy afterwards: build, verify-tree
  (the build-path check: 1893 files of R's own clean) and smoke passed. osx-64 (14:01-14:23): default build, verify-tree,
  smoke, verify-package, and minimal's build, verify-tree and
  verify-package, all passed.
- **Failures that were not the branch's.** Both came from two test
  runs sharing one checkout; the rule is one test run per checkout.
  - linux-64: one run's `rm -rf build/zig-cache` deleted the cache
    under the other's running default build, which failed with `failed
    to open object build/zig-cache/zig-3257041897-30115392/local/o/.../
    la_constants.o: FileNotFound` (13:32). The second run was stopped
    and the chain re-run alone from a cleared cache (13:34, the results
    above). In the same window one run checked out main's pixi.lock and
    re-solved it for 50 seconds before the branch lock was restored;
    every test copy above was checked to hold the branch lock.
  - win-64: an earlier chain was launched twice in the same copy (13:44
    and 13:48). The second build's vendoring step removed the tree's
    vendored DLLs while the first copy's verify-tree read the tree
    (`rm: cannot remove .../libcrypto-3-x64.dll: Device or resource
    busy`; verify-tree: `DLLs imported but not in the tree`: deflate,
    libbz2, icu, cairo, ...). Neither finished (their status log ends
    at check's start), and one chain was re-run alone from 13:51 (the
    results above; its verify-tree found every imported DLL: 50 in the
    tree, 24 the system's).
- Not tested: any GitHub Actions run with the new actions or the pixi
  pin; Ubuntu 26.04; linux-aarch64 (CI only); check and hermetic on
  macOS, full and openblas outside linux-64, and conda-package outside
  linux-64 (CI's legs run them); whether the libllvm21/libclang-cpp21.1
  rebuilds change generated code beyond the version string.

## CI to watch on the first push

- **Branch push.** build.yaml runs on pushes to main and on pull
  requests only, so pushing the branch runs gen-config alone (its push
  trigger watches .github/workflows/gen-config.yaml, which this branch
  changes): seven legs, linux-arm64 slim/full/minimal, osx-x86_64
  slim/full/minimal and osx-arm64 minimal. Compare with `gh run download
  <run-id> -D <dir>` and `diff -r <dir>/config-<plat>-<variant>
  zigbuild/config/<plat>-<variant>`: expect only CC_VER on linux-arm64
  slim and full, nothing on macOS (its CC_VER has no commit). Vendor
  nothing from it unless the CC_VER question below is decided for a
  refresh.
- **The pull request.** build.yaml's whole matrix, 20 jobs: 15 build
  legs (four OSes x default/full, openblas on both linux, minimal on four,
  windows default) and the five conda-package jobs. Look for: no Node 20
  warning; setup-pixi installing pixi 0.81.0; the four r-zig-wheel-<os>
  uploads with upload-artifact v7; a cache miss on the first run (the
  lock changed); the conda-package logs with rattler-build 0.76.1
  (overlapping or unused staging file warnings; win-64's build and its
  fresh-env consume test, for #2676); the win-64 build with zig `_20`.
- **upstream-zig.** Add the `upstream-zig` label to the PR: three legs,
  default on ubuntu-latest, macos-latest and windows-latest with
  upstream zig.
- **After the merge.** The push to main publishes with `--skip-existing`;
  with unchanged build strings the uploads are skipped and universe keeps
  build 4. Check that the publish step says so.
- **From 2026-10-19:** the Ubuntu 26.04 lines above.

## Open questions

- CC_VER in zigbuild/config/linux-*-{slim,full} still names
  clangdev-feedstock 0b2bbeec; leave it (recommended: cosmetic, and
  refreshing it means build 5) or refresh with feat-zig-build/PLAN.md's
  regenerate rule and bump?
- env.sh's zig cache key: also hash the libLLVM/libclang-cpp next to
  conda-forge's zig (a no-op for upstream's static zig; every cache
  invalidated once)?
- A check of minimal's package set whenever pixi.lock changes (a
  deny-list task, or in CI)?
- `libglib` instead of `glib` in pixi.toml would drop python, packaging
  and libpython from R's build envs (pango links only libglib); not done
  here (no dependency changes in this branch).
- Fail, not fall back, in CI on linux when strace or objdump is missing
  (hermetic-check.sh, verify-bundle.sh, verify-tree.sh)?
- Raise the rattler-build floor to `>=0.76` and pass
  `--error-overlapping-files --error-unused-staging-files` once a 0.76.1
  CI build shows no warnings?
- Seen, not changed (predates this branch): build 4's linux-64
  r-zig-slim depends on pango >=1.58.2 and libharfbuzz >=14.5.1, while
  pixi.toml pins pango 1.56.* and harfbuzz 14.2.* because 1.58 "breaks R
  4.6.1's cairo device compile"; build 4 built and passed its tests.
- gettext stays at 0.25.1 for full on linux until conda-forge rebuilds
  gawk against gettext 1.0; nothing to do.
