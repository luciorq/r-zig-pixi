# chore-review-consistency: a review of the whole project against its goals

Goal: read the living documents, the records' structure and the code
against the goals and principles of [CONVENTIONS.md](../CONVENTIONS.md),
correct what disagrees, and record the rest. Asked by the user on
2026-11-26. Branch `chore-review-consistency`, worktree
`wt/review-consistency`, from main 77abec1 (build 13 published).

Tags: **V** verified by me (the command or the source is named), **A**
found by a read-only audit pass that quoted both sides, which I did not
re-run, **I** inferred.

## How the review was done

- Seven read-only audit passes over the newest tree (wt/build14: main
  plus build 14's uncommitted work): the living documents against the
  code; the workflows, pixi.toml and the recipe; scripts/; rzig's
  compiler half and its build and binutils half; the root build.zig;
  the toolchain build, the wheel, the stress suite and repo/. Each
  finding names file:line and quotes both sides.
- I checked a finding against its source before I changed code for it:
  GNU make 4.4.1's source and a GNU make 4.3 run, R 4.6.2's install.R,
  winshlib.mk and Renviron.c, cross-links with zig 0.17.1, and the
  locked m2 packages themselves.
- Two sessions, two sets of files. Session r-zig-pixi-ed works on build
  14 in wt/build14. Every file it has changed or added stays its own:
  this branch does not touch them, and their findings are in "Findings
  sent to build 14" below. `git diff --name-only` of the two worktrees
  has no file in common (checked at the end).

## Decisions

Defaults are mine (the user may revisit); none changes what a release
publishes.

| # | question | options | chosen | reason |
|---|---|---|---|---|
| D1 | where to edit while build 14 is uncommitted | (a) wt/build14; (b) a worktree of its own from main, only files build 14 has not touched | (b) | two sessions writing one file lose work; agreed with r-zig-pixi-ed, 2026-11-26 |
| D2 | `rzig def`'s names | (a) as they are; (b) in double quotes, as winshlib.mk's ADDQU | (b) | F5: lld and `zig dlltool` read an unquoted DATA or VERSION as a keyword and stop |
| D3 | a Makevars `export` | (a) accept and drop the export; (b) needs make, in every form | (b) | F3: the code's own stated rule; tier 1 gives the compilers no environment of make's |
| D4 | a half-made libc++ mirror | (a) fail after the wait, for ever; (b) finish it after the wait | (b) | F8: links that exist are kept and the marker comes last, so no incomplete mirror is handed out |
| D5 | warn when `ZIG_BIN` names no executable | (a) warn; (b) stay silent | (b) | the wheel's Renviron.site sets `ZIG_BIN` to ziglang's path whether ziglang is installed or not (scripts/make-wheel.py): a warning on every command of a base-only install |
| D6 | warn when flang fails `-print-resource-dir` | (a) warn; (b) stay silent | (b) | tried (a): rzig's tests use empty programs as flang and assert no warning (fortran.zig "sources and a link"); reverted |
| D7 | a relative `include` also found beside the including file | (a) keep; (b) only the working directory, as make | (a) | written as intended in makefile.zig's `load`; rarely met; N2 |
| D8 | automatic variables (`$*`, `$<`) in a package Makevars value | (a) leave; (b) send the package to make | (a) for now | (b) changes which packages need the build tools: a stress run must show the cost first; N1 |
| D9 | the fresh-env consume test on Windows | (a) as it is; (b) add test-win.R and, when the recipe has it, r-zig-native-tools | (b) | F12: the consume test exists to run the recipe's tests through activation; not run on Windows here (Not verified) |
| D10 | workflow token permissions | (a) the repository default; (b) `contents: read` at the top of build.yaml, upstream-zig.yaml and gen-config.yaml | (b) | the four other workflows say so already; jobs that need more name it themselves |
| D11 | publishing on a push to main, and `id-token: write` on the whole conda-package job | (a) change build.yaml now; (b) add the caution to RELEASE.md, ask the user | (b) | it changes the release procedure and cannot be tested before a release: menu M3 |

### User decisions (2026-11-26)

The user, after the menus below: "Pr created, Continue with
recommended." Pull request #59. Every menu's option (a).

| # | menu | chosen | done where |
|---|---|---|---|
| U1 | M1, the m2 licences | (a) only real licence files count; texts retaken; m2-tar and m2-gzip added | here: the 20 `zigbuild/toolchain/licenses/m2-*/` directories and their README (F21). build 14: `hasLicenseFiles`, `windows_dirs` |
| U2 | M2, `[skip ci]` | (a) allowed only on the merge commit of a pull request whose head ran CI | build 14: CONVENTIONS.md |
| U3 | M3, the publish step | (a) a dispatch only, in a job of its own | here: build.yaml's `conda-publish`, RELEASE.md (F22). build 14: README.md, pixi.toml's comment |
| U4 | M4, macOS and the SDK | (a) state the exception | build 14: CONVENTIONS.md, README.md |
| U5 | M5, the root symlinks | (a) removed | here: `PLAN.md`, `TODO.md` gone (F23). build 14: build.zig's message, pixi.toml:232, README.md |
| U6 | M6, the unix launchers | (a) the sh launcher follows Rscript.c | build 14, done there before this menu (b14-review PLAN.md: 75 cases against R 4.6.2's compiled Rscript) |

## Findings fixed in this branch

rzig, the package build engine (all **V**; `zigbuild/tools/rzig/`):

- **F1. `override` was not sticky** (makefile.zig, `assign`). A later
  plain assignment replaced an `override` value: a Makevars' `override
  CFLAGS = -O0` was lost to Makeconf, read after it. GNU make keeps it
  (variable.c: "If the old definition is from a stronger source than
  this one, don't redefine it"; make 4.3: `[a] [x z]` for the new
  test's text).
- **F2. `OBJECTS +=`, `:=`, `?=` and `OBJECTS<TAB>=` dropped R's
  command-line OBJECTS** (pkgplan.zig). install.R tests `^OBJECTS *=`
  only (install.R:2732, :2755); with `OBJECTS += extra.o` make builds
  every top-level source and rzig built `extra.o` alone. New
  `lineAssigning`, used for OBJECTS.
- **F3. `export NAME = value` and a bare `export` in a package's
  Makevars were accepted and the export dropped** (makefile.zig). Only
  `export NAME` was refused. Now every form needs make (D3).
- **F4. `CXX_STD = 17` (no `CXX`) selected C++17** (pkgplan.zig,
  `cxxStdLine`). install.R strips `^CXX_STD *= *CXX` and ignores any
  other value with a warning (install.R:2736-2747).
- **F5. `rzig def` wrote unquoted names** (def.zig). winshlib.mk quotes
  each (`ADDQU = 's/[^ ][^ ]*/"&"/g'`). A C file with globals `VERSION`
  and `DATA`, linked with `zig cc -target x86_64-windows-gnu -shared`:
  the unquoted .def stops with "lld-link: error: identifier expected,
  but got DATA" and `zig dlltool` with "error parsing definition"; the
  quoted one links and exports DATA, VERSION, bar, foo (objdump -p).
- **F6. A tab-indented line with no rule before it was dropped**
  (makefile.zig, lenient mode), so a site Makevars' `ifdef X` /
  `<TAB>CFLAGS += -g` / `endif` did nothing. make reads it as any line
  (read.c: "If there is no preceding rule line, don't treat this line
  as a command"). Conditionals no longer end the rule before them (they
  do not in make). make 4.3 agrees with the new test's four values.
- **F7. `$(V:%.c=all.o)` gave `<stem>all.o`** (makefile.zig): a `%` was
  prepended to the replacement whatever the pattern. expand.c adds one
  to both sides only when the pattern has none.
- **F8. A libc++ mirror whose maker died never recovered**
  (libcxx_mirror.zig): every later compile waited 10 s and then linked
  the shared libc++. Now finished after the wait (D4); a lib dir that
  cannot be listed gives no mirror, where it gave an empty one marked
  complete. The test waits 0.1 s, not 10 (the suite: 16 s to 7 s).
- **F9. strip: 0xffff relocations without the overflow flag were read
  as an extended count** (binutils.zig, `stripObject`; the test was a
  no-op expression). **objdump: a truncated table ended with `error:
  BadFile`, no file name, and lost the output so far**; now a warning
  with the name, exit 1, as nm.
- **F10. `-Wl,-load_hidden,libx.a` and `-Wl,-large-address-aware`
  became a driver `-l`** (linker_args.zig). Single-dash `-library=` and
  `-library-path=` are read as the double-dash forms.
- Small: `rzig def` reads objects up to nm's 1 GiB (it stopped at 256
  MiB; one constant, `binutils.max_file`); dead `Section.discardable`,
  `bu_x64_o` and its fixture, `shellwords.Result`; a `@max(u32, 0)`;
  comments that named the wrong thing (pkgbuild.zig, groups.zig,
  crash.zig, binutils.zig, check-test.sh); `platformName`'s win-arm64
  has a test line.

Scripts, capture tools, build helpers:

- **F11 (V). A config capture in the `openblas` environment would
  overwrite the slim or full vendored config with a bare `-lopenblas`**
  (configure-only.sh passed `--with-blas=-lopenblas`, gen-subst.sh
  names the output by variant only; build.zig:696-703 says openblas has
  no vendored config). Both scripts now stop when `R_BLAS` is not
  internal.
- **F12 (V). conda-consume ran 7 of the recipe's test scripts.**
  test-win.R, the first test of r-zig-slim on Windows
  (recipe.yaml:654), was not among them; r-zig-native-tools (build 14)
  had no environment. Both added, the second only where the recipe has
  its test file (D9).
- **F13 (V). The shared-C++-runtime helper could not match on Windows**
  (verify-helpers.sh `cxx_deps`, `libcxx_deps`: a `.dylib` pattern for
  every OS but linux). verify-recommended.sh's check there was vacuous.
  A Windows branch, with the pattern verify-bundle.sh used inline,
  which now calls the helper.
- **F14 (V). contract-test never emptied its library**, so a package an
  earlier local run left could stand in for a failed install; the
  directory was per variant, shared by default and openblas. Per
  flavor, emptied.
- **F15 (V). verify-recommended.sh skipped the glibc ceiling silently
  with no objdump.** `cannot_check`, as verify-tree.sh.
- **F16 (V). smoke-test.sh and contract-test.sh defaulted to the
  retired autoconf and gnuwin32 trees** (`$OBJ_DIR/bin/R`,
  `$SRC_DIR/bin/x64`, `build/win-toolchain`). The defaults are the
  installed tree and the compile tree.
- Comments: verify-helpers.sh (llvm-objdump, who sources it),
  zig-smoke.sh, compile-tree.sh, unpack-toolchain.sh,
  package-standalone.sh, zig-toolchain.sh, normalize-subst.sh
  (`stage.sh`), configure-only.sh (`PLAN.md`), rspec.zig
  (`make-vars.txt`, a gfortran warning). rspec.zig's Windows LAPACK
  lists are the unix ones (they were copies). Dead `repository`
  constants in cairo.zig and pkgconf.zig. wheel.zig's tag test uses the
  six 0.17.1 wheel names fetch-zig.sh pins (it had five 0.16.0 names).

Workflows and documents:

- **F17 (V). RELEASE.md's check after a publish listed six packages.**
  The recipe has seven on main (r-zig-tcltk, build 13; six on
  win-arm64) and build 14 adds r-zig-native-tools on Windows: the step
  now says to count from the recipe. Its `build.yaml:345` named a
  comment line; it names the step. Publish step 1 says what release 13
  did with the merge's push run.
- **F18 (V). gen-config.yaml's comment gave a reason that is gone** and
  listed two of its four paths (the fourth is b13-build N6); the
  workflow had no kill switch, while README says `ENABLE_HOSTED_JOBS`
  pauses all CI. Comment rewritten, switch added.
- **F19 (V).** `permissions: contents: read` (D10).
- **F20 (V). 62 record directories, 68,000 lines, no map.**
  [README.md](../README.md) here: the living documents, the release
  records, the branch records by build, and how a record is written.
- test-toolchain.R and test-build-tools.R headers (the toolchain has
  three groups; `R CMD config` runs no make); build.yaml's publish
  comment points at RELEASE.md; .gitignore names `python/r_zig`.

After the user's decisions:

- **F21 (V). The m2 licence texts, for the locked builds** (U1). Taken
  again as the README there says, for the `ha3ae583_11` packages of
  pixi.lock: each package's source archive is the `.src.tar.zst` of its
  `rendered_recipe.yaml`, checked against the recipe's sha256, and the
  files come from the upstream tarball inside it (m2-msys2-runtime: from
  the archive's git clone, at the PKGBUILD's tag). New: m2-tar and
  m2-gzip. Every directory's `VERSION` is the lock's version and build.
  Until build 14's `hasLicenseFiles` change the build does not read
  them (B1).
- **F22 (V, by reading). Publishing is a job of its own**, U3.
  `conda-publish` in build.yaml: only for a dispatch on main with
  `CONDA_PUBLISH` set, after all six `conda-package` jobs passed, from
  their artifacts (`conda-<subdir>`); it alone has `id-token: write`.
  A push no longer publishes, and a release has all six subdirs or
  none. A dispatch on main without the variable uploads the artifacts
  and skips the job: a rehearsal. RELEASE.md says so.
- **F23 (V). The root `PLAN.md` and `TODO.md` symlinks are gone** (U5).
  contract-test.sh's two bare "TODO.md" citations name
  feat-zig-build's.

## Findings sent to build 14

Files build 14 owns (README.md, stress/, CXX-STDLIB.md, CONVENTIONS.md,
build.zig, zigbuild/toolchain/build.zig, pixi.toml, recipe.yaml,
build-r.yaml, stress.yaml, env.sh, make-wheel.py, verify-tree.sh,
verify-toolchain.sh, wheel-test.sh, rzig's main, compiler, environment,
windows and Ctx, python/, repo/). Sent to r-zig-pixi-ed on 2026-11-26.

Behaviour:

- **B1 (V). The MSYS2 programs ship without their licence texts.** The
  locked `m2-*` `ha3ae583_11` packages hold one file in
  `info/licenses/`, `recipe-scripts-license.txt` (conda-forge's
  BSD-3-Clause for its recipe scripts; all 20 the group copies from
  were downloaded and opened, F21). `hasLicenseFiles` (zigbuild/toolchain/build.zig) then
  returns true, so `ownLicenses` and the 18 hand-taken
  `zigbuild/toolchain/licenses/m2-*/` directories (VERSION
  `hc364b38_6`, taken 2026-10-20) are never read, and the Windows
  build-tools archive and wheel carry GPL binaries with that one text.
  There is no `licenses/m2-tar/`. b13-env-ci's record has it as
  inferred. Not in a release: no archive or wheel is published. Menu M1.
- **B2 (V). Windows `etc/Rcmd_environ` puts `/Library/usr/bin` on
  R CMD's PATH** when `R_ZIG_TOOLCHAIN_ENV` is unset (build.zig:2948,
  on main since build 13): `${R_ZIG_TOOLCHAIN_ENV}/Library/usr/bin`,
  and Renviron.c's `subterm` gives "" for an unset variable with no
  default. A drive-rooted host path. Fix: a helper variable with a
  default inside the tree, as the file's other `R_ZIG_` helpers.
- **B3 (V, by grep). The Windows tree has no `doc/html/index.html`, no
  `etc/Rdevga`, no `etc/rgb.txt`.** build.zig installs index.html in
  installStaticTree, which buildWindows does not call; upstream's
  `fixed/Makefile` copies `html/rwin.html` and `fixed/etc/*`.
  `help.start()` opens that file.
- **B4 (A, two passes). zigbuild/launchers/Rscript against Rscript.c:**
  options after `-e` go to R (upstream: "Any remaining --options belong
  to the expressions"), so `Rscript -e 'commandArgs(TRUE)' --foo x`
  loses `--foo`; `R_SCRIPT_DEFAULT_PACKAGES` is not read; a `#!` line's
  `--a --b` is one word; `--version`; no file; `cd` without `-P`.
- **B5 (A). The standalone Windows build tools have MSYS2 tar and no
  gzip** (`windows_dirs`); the conda package got `m2-gzip` for "tar
  (child): gzip: Cannot exec" (b13-fixes F10). verify-toolchain.sh's
  list has no gzip.
- **B6 (A). stress.yaml:157** `echo "ZIG_BIN=$(pixi run -e stress
  fetch-zig)"` cannot fail: an upstream-zig stress leg then runs with
  conda-forge's zig. build-r.yaml's two-line form fails.
- **B7 (A). rzig windows.zig:** an Rtools-curl `-l` is dropped although
  a two-argument `-L dir` has the library (`cmdline.libDirs` skips that
  form). **environment.zig:** a wrong `R_ZIG_EXTRA_ENV` warns two to
  four times per command; `list` still takes a mutable Ctx.
- **B8 (A). stress.R `--strict`** does not see a libs-smoke FAIL.
  **python/r_zig/__init__.py:** a user's `ZIG_BIN` with backslashes is
  read again through Renviron.site, which drops them. **repo/
  build-repo.R:** `${ORIGIN}` accepted in one place and refused in two;
  an empty licence directory passes.
- **B9 (A). verify-toolchain.sh:386 and verify-tree.sh:198** end the
  script silently, under `set -e`, before the error message written for
  that case; verify-toolchain.sh:314 and wheel-test.sh's `rpath_of`
  skip without `cannot_check`. **build-r.yaml:** `recommended-test`
  runs in no workflow.

Documents and comments (all **A** unless marked):

- **B10. README.md.** The "Open in build 11's CI" paragraph and "one
  check there is still open": both resolved 2026-11-13
  (chore-release-11 findings 17, 18). upstream-zig runs six runners,
  not three. The full tier has 21 legs (also pixi.toml:238). igraph
  under the native make is not a gap: `-DBATCH_MODE_ONLY_SHELL` is in
  zigbuild/make/build.zig (b14-l4 U6, whose "Open items" still lists
  M4). conda-package is not the only job that builds the recommended
  packages. The m2 tool list lacks tar. `PKG_CONFIG_PATH`: zig-libs'
  directory is first, always (build.zig:2960). r-zig-native-tools and
  zip carry no "build 14 on". The base's `bin/toolchain` also holds
  `libstdcxx-shim/` on linux. No definition of `R_ZIG_EXTRA_ENV`; no
  word on `R_ZIG_NO_PREFLIGHT`, which rzig's own message recommends,
  `R_ZIG_PKG_BUILDER=zig`, `R_ZIG_JOBS`, or the gates of release.yaml
  and repo.yaml.
- **B11. stress/README.md.** "build 10 (R 4.6.1) until build 11 is
  published"; Z9 "until rzig's fix" (shipped in build 7); g3 lacks
  jpeg; "The values are round 2's"; the compile tree's directories; a
  `fail-dependency` example no row has.
- **B12. CXX-STDLIB.md.** Distro `-dev` packages "fail today"
  (`R_ZIG_SYSTEM_LIBS=1` since build 13); the header search order
  lacks `R_ZIG_TOOLCHAIN_ENV`; the Rtools45 section is in the present
  tense and names ten libraries libs-zig-pixi now builds; "Not tested
  yet" names runs that happened.
- **B13. CONVENTIONS.md.** `f7d1558` (`build:`, 2026-11-10) predates
  the rule too. "optional groups: compilers, build tools, extras,
  tcltk, native tools": README calls tcltk and recommended add-ons, and
  recommended is missing. A link to the index would help. See M2 and M4.
- **B14. build.zig.** Two messages give steps that do not work (`pixi
  run zig-build`, lines 33 and 408; the four regenerate-config steps,
  3493-3506, which gen-subst.sh replaced). About 20 host tools by bare
  name (`rm`, `cp`, `chmod`, `unzip`, `gzip`, `iconv -l`, whose output
  ships; `flang` by name at 3441 although its path is located).
  `replaceLine` is a no-op and `gnuwin32O3ToO2` edits the repo's own
  template. Dead: `Ctx.linkLapack`, `openmp_pkgs`, `%C`, `-DR_HOME` on
  Windows' Rscript.c. Comments that say Windows is unfinished (lines
  3-5, 684, 1547, 1948's step description).
- **B15. pixi.toml, recipe.yaml, make-wheel.py.** `m2-texinfo` is a
  dead dependency with a gnuwin32 comment; `full-openblas` is solved
  and used nowhere; comments name `scripts/configure-r.sh`, the
  self-hosted runner and gnuwin32 as current (pixi.toml:511, 559, 644;
  recipe.yaml:412-417, :937 above `- m2-tar`); the build-13 paragraph
  has no publish date. The wheels' descriptions say make and pkgconf
  are conda-forge's builds, unchanged; both are built from source.
- **B16. The not-found texts** (groups.zig `no_zig`, `no_flang`;
  libstdcxx.zig `no_headers`) leave out `R_ZIG_TOOLCHAIN_ENV`, which is
  searched. My files, but wheel-test.sh and verify-bundle.sh match the
  text: one change, after build 14 lands.
- **B17. Three truthiness rules for on/off variables**: "set, not
  empty, not 0" (`R_ZIG_SYSTEM_LIBS=false` turns it on); any non-empty
  value (`R_ZIG_NO_PREFLIGHT=0` skips the check); "1, true or yes"
  (`R_ZIG_NATIVE_TOOLS`).

## Not changed, with the reason

- **N1.** D8: automatic variables in a Makevars value expand to
  nothing in tier 1 (Windows: `<stem>-CPPFLAGS` through Makeconf.win's
  `$($*-CPPFLAGS)`). Open; needs a stress run.
- **N2.** D7.
- **N3.** verify-bundle.sh's sixteen always-true `[ -n "$pass_zig" ]`
  guards and four dead "skipped (no zig)" branches (**A**). Removing
  them re-indents a 3,000-line script that only a full `verify-package`
  run checks: for a batch that runs one.
- **N4.** vendor-libs.sh is a bash step inside the build path, with
  three closure tools and a second `zig build` to record what it copied
  (**A**); the R patch series is applied by bash, so `zig build` alone
  builds an unpatched R (**A**); macOS scripts use the host's otool,
  install_name_tool, codesign, find and bash (**A**). Each is design
  work for a branch of its own (feat-no-host-paths' phase F names the
  first).
- **N5.** The package tests install what CRAN serves that day and
  assert each package's builder by name (**A**): a CRAN release can turn
  `contract` red with no change here. A dated snapshot would pin it.
- **N6.** `rzig def`'s de-duplication is quadratic in the number of
  names (**A**). Speed only.
- **N7.** release.yaml's `pypa/gh-action-pypi-publish@release/v1`: the
  only action on a branch. It is the ref its own project documents, and
  the workflow is switched off.
- **N8.** zig's fetch tool pins a checksum it has just computed when
  none is recorded (**A**): only on a version bump, with a message.
- **N9.** Eleven of the twelve unix vendored configs name the previous
  compilers in two lines build.zig overwrites (**A**).

## Menus for the user (recommended first)

Answered on 2026-11-26: option (a) of each (User decisions, above).

- **M1, the m2 licences (B1).** (a) Count only real licence files
  (`recipe-scripts-license.txt` is not one), retake the 18 directories
  for the `_11` builds, add m2-tar and m2-gzip; the build then stops on
  the next re-lock, as designed. (b) Accept conda-forge's file as what
  ships, delete the 18 directories and say so in the README there.
- **M2, `[skip ci]`.** chore-ci-tiers decided "no skip tags" (CI1,
  2026-10-08; build.yaml's header says why), and 13 commits on main
  since 2026-11-18 carry the tag, four of them merges of code (#49,
  #51, #52, #55). (a) Write the practice down in CONVENTIONS.md: never
  on a docs-only commit (the path filter does it), allowed on the merge
  commit of a pull request whose head ran CI on the same tree. (b) Stop
  using it.
- **M3, the publish step.** (a) Publish on a dispatch only (drop
  `push`), in a job of its own that alone has `id-token: write` and
  takes the packages as an artifact; README, pixi.toml and RELEASE.md
  follow. (b) Dispatch only, same job. (c) Keep; RELEASE.md's caution
  stays.
- **M4, macOS and the Command Line Tools.** The goals say "No Rtools,
  Xcode command line tools or system compiler"; R's build runs
  `/usr/bin/xcrun` and stops without it (build.zig:527), and rzig adds
  the SDK's Frameworks and `usr/lib` to every command when it finds one
  (darwin.zig; warn-and-go-on is b13-rzig D3/D4). (a) State the macOS
  exception in CONVENTIONS.md and README now. (b) Also plan the SDK out
  of package builds.
- **M5, the root `PLAN.md` and `TODO.md` symlinks** (to
  feat-zig-build's, July). README has to say they are "not the current
  work", and build.zig's message sends users to "PLAN.md". (a) Remove
  them and cite the full path. (b) Keep.
- **M6, the unix launchers (B4).** (a) Correct the sh launcher against
  Rscript.c. (b) One self-locating Zig launcher for `bin/R`,
  `bin/Rscript` and Windows' `Library\bin`, in place of two sh files, a
  third copy in build.zig and the .bat files.

## Tests

| what | where | result |
|---|---|---|
| rzig unit tests, before any change | gamma, conda-forge zig 0.17.1 | 243 of 243 |
| rzig unit tests, after | gamma | 247 of 247 (four new tests; others extended) |
| `zigbuild/tools/rzig/test.sh`: units, fetch.zig, check-test.sh, link-objects-test.sh | gamma, main's pixi env, `PIXI_PROJECT_ROOT` at this worktree | exit 0; 60 of 60 checks; five Windows cross-links |
| `scripts/zig-toolchain.sh test` | gamma, same | exit 0 |
| `zig test zigbuild/toolchain/wheel.zig` | gamma | 21 of 21 |
| `zig fmt --check zigbuild build.zig` | gamma | clean |
| `zig build -l` on the root build.zig (compiles it with the edited rspec.zig, cairo.zig, libcxx_mirror.zig) | gamma | exit 0 |
| GNU make 4.3 on the new makefile tests' texts | gamma | `[a] [x z]`; `[-g]`; `[] [] [after] [line]`; `[a.o sub/b.o c.cpp]` twice, `[all.o all.o c.cpp]` |
| a quoted and an unquoted .def with globals `VERSION` and `DATA`, `zig cc -target x86_64-windows-gnu -shared` and `zig dlltool` | gamma | F5 |
| `bash -n` on every edited script | gamma | clean |
| the 20 m2 licence directories (F21): each source archive against its recipe's sha256, each `file:` line's sha256 against the file, each .conda's `info/licenses/` listed | gamma, `take-m2.py` | 20 of 20; every package ships `recipe-scripts-license.txt` alone |
| the Windows toolchain build with these 20 directories and build 14's `hasLicenseFiles` change (a build14 snapshot; r-zig-pixi-ed, 2026-11-26) | kappa (win-64) | `toolchain`, `verify-toolchain` and `toolchain-test` exit 0; "31 packages, each with its LICENSES/"; `usr/LICENSES/` has all 20 m2 packages, each identical to the directory here; `recipe-scripts-license.txt` nowhere in the tree; no package without a directory |
| build.yaml after F22: YAML parse, the jobs' `if:`, permissions and steps read back | gamma | `conda-package` has no `id-token`; `conda-publish` has it and the gate |
| PR #59, first push (949cff0 to f8f8abd): gen-config's four legs with the new capture guard | GitHub, run 45941439403 | linux-arm64 default, full, minimal and osx-arm64 minimal pass (the others: see the pull request) |
| PR #59 at f8f8abd, labels `full-ci` and `upstream-zig`: every check (read 2026-11-27) | GitHub, runs 45941445437 (build-r), 45941445250 (upstream-zig), 45941439403 (gen-config) | 52 pass, 0 fail. 4 skipped, each as designed: `packaging` (skipped under `full-ci`), and the label events' two duplicate runs 45941445063 and 45941445546 |
| rzig's tests in that run, both zigs | GitHub: the `default` legs of ubuntu-latest, macos-latest, windows-latest, windows-11-arm; upstream zig (PyPI ziglang 0.17.1) on ubuntu-latest, macos-latest, windows-latest | linux and macOS: 247 of 247, and check-test.sh's 60 of 60 on linux; Windows: 217 of 247 with 30 skipped (the 30 `SkipZigTest` returns for a Windows host, all older than this branch), none failed; the same counts with upstream zig |
| F12: the consume test on Windows | GitHub, `conda-package / win-64` and `/ win-arm64` | both start with `== default: test-win.R` ("conda R OK"), then preflight, compilers, build-tools, extras, toolchain, recommended (and tcltk on win-64), each to its last OK line. The `native-tools` env did not run: main has no `recipe/test-native-tools.R` (build 14 adds it) |
| F11, F13 to F16: the script changes in real builds | GitHub, the `default` legs of the four runners above | `contract program ran to the end` on all four; linux "C++ runtime: libstdc++ in every compiled C++ package (Rcpp, minqa), no libc++"; macOS "static in every compiled package"; verify-bundle's first C++ compile "static libc++" on macOS and both Windows legs; `recommended packages verified` and `pkg-parity verified` (windows/slim); no `##[error]` or `##[warning]` line in the eight logs read |

## Not verified

- The first CI run (the rows above) built R and the packages on all six
  platforms with both zigs, so F5, F11 to F16 and F12's `test-win.R`
  are no longer unverified. Still not run: F12's `native-tools` env
  (until build 14's `recipe/test-native-tools.R` is on main), and
  `cannot_check` of F15 and the `$BLAS != internal` stop of F11, whose
  conditions no CI leg meets.
- I read eight of the 46 job logs line by line (the four `default`
  legs, four `conda-package` legs) and three upstream-zig legs for
  their test counts; the other jobs by their status alone.
- The workflow edits (F18, F19, F22) are checked by reading and a YAML
  parse alone. `conda-publish` runs first at the next release: a
  dispatch on main without `CONDA_PUBLISH` before it rehearses the
  artifact upload, not the download and the upload to prefix.dev.
- The **A** findings were not re-run by me, apart from the ones this
  record marks **V**.
