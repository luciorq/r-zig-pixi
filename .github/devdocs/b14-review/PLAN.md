# b14-review: the review findings sent to build 14

The findings B1-B17 of chore-review-consistency/PLAN.md ("Findings sent
to build 14", 2026-11-26), handled on the build14 worktree (origin/main
77abec1, uncommitted). One section per track; each row: the finding,
the verdict (confirmed or rejected, with the evidence), the fix and the
test.

## Track: docs (B6, B10, B11, B12, B13)

Scope: stress.yaml's upstream-zig step (B6), README.md but its L5 and
wheel sections (B10), stress/README.md (B11), CXX-STDLIB.md (B12) and
CONVENTIONS.md (B13). pixi.toml is the build track's (its line 238 comment
now says 21 legs).

| id | verdict and evidence | fix | test |
|---|---|---|---|
| B6 | confirmed. stress.yaml:157 was `echo "ZIG_BIN=$(pixi run -e stress fetch-zig)" >> "$GITHUB_ENV"`: under Actions' `bash -eo pipefail` a failing command substitution inside echo's argument does not stop the step (gamma: `echo "Z=$(false)"` exit 0; `z="$(false)"` exit 1), so an upstream-zig stress leg would run with the env's zig | build-r.yaml's two-line form (`zig="$(...)"`, then the echo) with a comment | the step's `run` text taken from the YAML and run with a pixi that fails: exit 1, `GITHUB_ENV` not written; YAML parses |
| B10 build 11 CI | confirmed. chore-release-11 findings 17 and 18: both resolved 2026-11-13 (run 43437326154: the VEX hit was a Mach-O jump table; the make segfault only when Git bash starts MSYS make directly, which README's Git Bash bullet already says) | the "Open in build 11's CI" paragraph and "one check there is still open" removed | read |
| B10 upstream-zig runners | confirmed. upstream-zig.yaml's build matrix: ubuntu-latest, ubuntu-24.04-arm, macos-latest, macos-15-intel, windows-latest, windows-11-arm | "all six runners" | read |
| B10 full tier legs | confirmed. build.yaml: build's 7 (default on 6, minimal on linux-64) plus build-full's 14 (full on 6, openblas on both linux runners and windows-latest, minimal on the other 5) = 21; build.yaml's header says 21 | "21", with the split; pixi.toml:238 already says 21 (build track) | count from the matrix |
| B10 igraph | confirmed. zigbuild/make/build.zig:133 adds `-DBATCH_MODE_ONLY_SHELL` for Windows targets (b14-l4 U6) | README's "Known gap" replaced by what the flag does; b14-l4 PLAN.md's Open items M4 marked answered and applied (U6) | kappa 2026-11-26: make.exe cross-built on delta from this worktree's zigbuild/make (conda-forge zig 0.17.1, x86_64-windows-gnu) ran a recipe of a 48,000-character line through `sh.exe` (`echo ... \| wc -c`: 48000, exit 0); the same build without the flag: `CreateProcess(...) failed. make (e=87)`, Error 87. igraph itself not reinstalled |
| B10 recommended | confirmed. build.yaml:174 passes `recommended` to build-r on the default legs of a dispatch or a `full-ci` pull request; build-r.yaml:279-285 runs recommended and verify-recommended | "the only job" replaced | read |
| B10 m2 tar | confirmed. windows_dirs has m2-tar (also on main); the build track added m2-gzip (B5) | "tar and, build 14 on, gzip" | read zigbuild/toolchain/build.zig |
| B10 PKG_CONFIG_PATH | confirmed. build.zig rcmdEnviron: `PKG_CONFIG_PATH="${R_ZIG_LIBS}/lib/pkgconfig;${PKG_CONFIG_PATH-${R_ZIG_PKG_CONFIG_PATH}}"`, and PKG_CONFIG_LIBDIR's default | the bullet says zig-libs first always, then the set value or R's env's, and PKG_CONFIG_LIBDIR | read |
| B10 "build 14 on" | confirmed. recipe.yaml's 13 → 14 note: r-zig-native-tools new, usr/bin/zip.exe new | added to r-zig-native-tools, zip (both places) and native/bin | read |
| B10 libstdcxx-shim | confirmed. build.zig's rzig install doc and recipe.yaml:748-749 (r-zig-slim's lib/R/bin/toolchain/libstdcxx-shim/) | named in both "only rzig" passages | read |
| B10 R_ZIG_EXTRA_ENV | confirmed (no definition). environment.zig item 2, main.zig's variable list, pixi.toml's activation | a paragraph | read |
| B10 R_ZIG_NO_PREFLIGHT | confirmed. patch 0009 skips the preflight on `nzchar(Sys.getenv("R_ZIG_NO_PREFLIGHT"))`; check.zig skips the zig version comparison and its message names it | a paragraph | read |
| B10 R_ZIG_PKG_BUILDER=zig, R_ZIG_JOBS | confirmed. patch 0013's .rzig_build: auto, zig (stop where make would run), make; R_ZIG_JOBS else MAKEFLAGS' -j | the builder paragraph covers all three values and R_ZIG_JOBS | read |
| B10 gates | confirmed. release.yaml: every job needs `vars.R_ZIG_RELEASE == 'true'`, a dispatch, main (and `inputs.pypi` for PyPI); repo.yaml's publish job: ENABLE_HOSTED_JOBS, R_ZIG_REPO_PUBLISH, dispatch, main, `inputs.publish`. Also found: ENABLE_HOSTED_JOBS is read by build, upstream-zig, stress, repo and win-binary, not by gen-config or release, where README said "all CI jobs". `gh release list`: no release | a paragraph on both gates; the kill switch's list of workflows | read |
| B11 universe build | confirmed ("build 10 ... until build 11 is published") | universe's newest on 2026-11-26: build 13 | read |
| B11 Z9 | confirmed. fix-stress-round1 S9 (dso_fini, build 7); round 2: "119 of 119 unloaded" | past tense in the step text and the crash class | read |
| B11 g3 jpeg | confirmed. packages.tsv: jpeg is g3 | added | awk over packages.tsv |
| B11 round 2's values | confirmed. the notes carry dated entries through 2026-11-26 | "each row's note dates its values" | read |
| B11 compile tree | confirmed. compile-tree.sh copies every group directory but zig/ and flang/; env.sh group_dirs: openmp libstdcxx, usr etc native, cmake | the list | read |
| B11 fail-dependency | confirmed. no row's expect has it (awk over column 8); lwgeom's linux expect went to ok on 2026-11-23 | the example says so | awk |
| B12 distro -dev | confirmed. system_libs.zig (build 13, b13-rzig M-29 F6: magick, terra, sf against Ubuntu 22.04 and 24.04) | the passage keeps the default and adds R_ZIG_SYSTEM_LIBS=1 | read |
| B12 header order | confirmed. libstdcxx.zig headersDir: own env, the group's libstdcxx/, R_ZIG_TOOLCHAIN_ENV, R_ZIG_EXTRA_ENV (its test names this order). Its own doc comment (lines 36-40) omits R_ZIG_TOOLCHAIN_ENV too: not this track's file | order corrected | read |
| B12 Rtools45 section | confirmed. pixi.toml's stress feature: slice 2 (2026-11-25) zig-nlopt, -gsl, -mpfr, -gmp, -glpk, -hdf5, -netcdf, -udunits2, -harfbuzz, -libpq; b14-rhtslib U3 retires the tree | section in the past tense, titled retired | read |
| B12 not tested yet | confirmed for three items: upstream-zig 44735388684 (6/6, #50's head with #49, docs-backlog-hygiene F4) and 45813752664 (chore-release-13 Gate); stress on macOS and Windows (b13-stress, b13-slice2 F12); older libstdc++ hosts (wave2-compat M-12: Rocky 8, Ubuntu 22.04) | a "Tested since" item; the rest stays | read |
| B13 f7d1558 | confirmed. `git log`: f7d1558 2026-11-10 `build: zig 0.17 on every platform`; the rule is 2026-11-11; no other non-conforming type on origin/main | added to the list | git log |
| B13 groups wording | confirmed. README: tcltk and recommended are add-ons, compilers/build tools/extras groups; recommended was missing | groups vs add-ons, recommended and Windows' native tools added; README's native-tools bullet now says add-on | read |
| B13 index link | no `.github/devdocs/README.md` in this worktree | nothing written about it | ls |
| re-check (2026-11-26) | B6, B10-B13 re-checked against the code and records by a second reviewer: no defect. One wording point: CONVENTIONS' layered-toolchain bullet called Windows' native tools an add-on, true for conda (`r-zig-native-tools`) but in the standalone toolchain `native/` is in the build-tools archive (scripts/env.sh group_dirs: `build-tools) usr etc native`; README's toolchain section says the same) | the bullet says both: a separate package on conda, `native/` in the build-tools archive standalone | read env.sh and zigbuild/toolchain/build.zig:320-324 |
| Goals sections | CONVENTIONS' "Goals and principles" and README's goals section were in the build14 preparation before this track; this track changed only the layered-toolchain bullet (B13 groups wording, re-check row) | none | read |

B17 (report only; nothing changed). Proposed rule: an on/off
variable is on when set to `1`, `true` or `yes` (case-insensitive) and
off otherwise, unset and empty included, as `R_ZIG_NATIVE_TOOLS`
already reads; one helper in rzig (and its R and Rcmd_environ readers)
used by `R_ZIG_SYSTEM_LIBS`, `R_ZIG_NO_PREFLIGHT` and the rest, with
the docs saying `=1`.

Not verified: igraph itself under the final native make (only the long
recipe line above); the README's L5 and wheel sections (another
workflow's).

## Track: rzig (B4, B7, B8 parts)

Scope: zigbuild/launchers/Rscript against R 4.6.2's src/unix/Rscript.c
(B4, menu M6 option a: the sh launcher corrected, no Zig launcher);
rzig's windows.zig, environment.zig and Ctx.zig (B7); stress.R
`--strict` and repo/build-repo.R (B8; python/r_zig is not this track's).

| id | verdict and evidence | fix | test |
|---|---|---|---|
| B4 options after -e | confirmed. Rscript.c: `if (e_mode) break;` "Any remaining --options belong to the expressions (PR#18102)"; the launcher passed `-*` to R in any position. Old launcher against conda-forge's compiled Rscript 4.6.2 on delta: `-e 'commandArgs(TRUE)' --foo x` gave R `--foo` before `--args` | the launcher is Rscript.c's main() case for case: after a -e only further -e pairs are read, anything else starts the arguments; before the first non-option, --verbose and --default-packages are Rscript's, other `--` options R's, and the first argument not starting with `--` is the file (a single-dash `-x` too, as Rscript.c) | rscript-test.sh (below) |
| B4 R_SCRIPT_DEFAULT_PACKAGES | confirmed: not read. Rscript.c sets R_DEFAULT_PACKAGES from it when set (empty too) and no --default-packages was given; R_SCRIPT_LEGACY=yes's default list as well | both read | cases env-sdp*, env-legacy*; real R: `R_SCRIPT_DEFAULT_PACKAGES=NULL` search() |
| B4 #! line | confirmed. Rscript.c splits argv[1] at spaces and tabs when it starts with `--` and holds more than one word; the old launcher passed `--vanilla --default-packages=NULL` to R as one unknown option | split with `set -f` and IFS space-tab, only for more than one word (a lone `--version ` stays one word, as there) | cases shebang*; a real `#!<Rscript> --vanilla --default-packages=utils` script |
| B4 --version, --help | confirmed. Rscript.c answers both itself, and only as the only argument (`argc == 2`); the old launcher exec'd `R --version` for --version anywhere and passed --help to R | usage text as Rscript.c's on stdout (exit 0 for --help, 1 for no arguments); `Rscript (R) version x.y.z (date)` from the tree's include/Rversion.h (Rscript.c has it compiled in), with R_STATUS and the revision when R_STATUS is not empty | cases help*, version*, no-args; r-zig-slim _13 on delta: `Rscript (R) version 4.6.2 (2026-10-29)` |
| B4 no file | confirmed. Rscript.c: "file name is missing", exit 1, for options and no file; "-e not followed by an expression", exit 1; the old launcher ran R | the same messages and status | cases file-missing*, expr-missing* |
| B4 cd -P | confirmed. `R_HOME="$(cd "$here/../lib/R" && pwd)"` for the prefix/bin copy, logical where everything else is physical | `cd -P` | cases prefix-bin, symlink |
| B4 also found | R_HOME was exported by the launcher, so a different R_HOME in the environment was replaced silently, where with Rscript.c bin/R warns "ignoring environment value of R_HOME" (R.sh.in); RHOME was not read (Rscript.c runs `$RHOME/bin/R` when it is set and not empty); --verbose printed nothing; an exec failure | R_HOME no longer set; RHOME read; --verbose's "setting ..." and "running ..." lines; "Rscript execution error: ..." exit 255 for a missing or non-executable bin/R. Not carried over, in the file's header: the PATH_MAX length checks, a bare `--default-packages` (Rscript.c reads past its end; here R gets it as an unknown option), R_ARCH (empty on unix here) | cases env-rhome*, rhome-*, verbose-* |
| B4 R_HOME of the same tree (re-review) | confirmed. bin/R's R_HOME_DIR is physical (makeRFrontScript, `cd -P`) and R.sh.in compares strings, so with R_HOME no longer replaced an R_HOME naming this tree through a symlink or with a trailing "/" warned on every Rscript call (rpy2 via python/r_zig/_rpy2.py's abspath R_HOME, macOS /tmp; wave2-compat inside.sh). Delta, r-zig-slim _13 with the launcher and `envlink -> env`: `R_HOME=$PWD/envlink/lib/R env/bin/Rscript -e 'cat(R.home())'` printed `WARNING: ignoring environment value of R_HOME`, trailing "/" too; the old launcher did not. The row above's "as with the compiled Rscript" held for conda-forge's literal R_HOME_DIR only | the launcher unsets an R_HOME that resolves (`cd -P`, not empty) to the tree whose bin/R it runs (its own, or RHOME's); any other R_HOME is left to bin/R and its warning; header says so | rscript-test.sh: env-rhome-same (symlink, trailing "/", plain, `bin/..`), env-rhome-same-rhome, env-rhome-missing (passed on); these 5 fail with the launcher before the fix. Delta, the same _13 copy: symlinked, trailing "/" and plain R_HOME print R.home() alone from bin/ and lib/R/bin via envlink, `/elsewhere` still warns, a child Rscript from R under a symlinked R_HOME prints no warning. omicron (macOS): stub tree in /tmp, R_HOME as /tmp/..., /private/tmp/... and with "/" unset, /elsewhere passed on, /bin/sh and bash |
| B4 test | | zigbuild/launchers/rscript-test.sh `<R_HOME of a reference R>`: a stub bin/R prints the arguments and R_DEFAULT_PACKAGES, R_HOME, R_ARCH; the compiled Rscript runs it through RHOME, the launcher from lib/R/bin, bin and a symlink; stdout, stderr and exit status compared for 62 cases; then 7 cases through the reference's real R (with the re-review's 6 launcher-only R_HOME cases: 75; delta, after that fix: 75 of 75 with /bin/sh (dash), bash and busybox sh) | delta, conda-forge r-base 4.6.2 hc453583_3: 69 of 69 with dash, bash 5 and busybox sh; omicron (macOS 26, arm64): 69 of 69 with /bin/sh (bash 3.2), bash and dash (zsh in native mode, not a POSIX sh, splits no words: 5 fail, not a target). The pre-fix launcher: 0 of 69 (R_HOME exported in all; the diffs above in each case). r-zig-slim 4.6.2 _13 from universe on delta with the new launcher in bin/ and lib/R/bin: the B4 cases by hand, as expected |
| B4 re-review, also found (fixed after the user decision: menu 4 (a), see "Track: launcher-front" item 4) | bin/R itself (lib/R/bin/R, build.zig makeRFrontScript) warns the same way when started directly: delta, r-zig-slim env, `R_HOME=<symlink>/lib/R lib/R/bin/R -s -e 'cat(1)'` and `R_HOME=<env>/lib/R/ bin/R RHOME` both print `WARNING: ignoring environment value of R_HOME`. Reached by `R CMD ...` children of an embedded R (rpy2) whose R_HOME is a logical path. build.zig is outside this track | none here; fixed in build.zig makeRFrontScript by the launcher-front track (item 4) | see the track's report and item 4 below |
| B7 two-argument -L | confirmed. cmdline.libDirs read `-L<dir>` only, so `-L dir -lssh2` with dir/libssh2.lib dropped -lssh2 as an unresolved Rtools curl name (rzig dry run, RZIG_OS=windows: "lib -lssh2 (dropped: Rtools curl closure)"); libDirs is used by windows.libs only | libDirs reads `-L <dir>` too, unless that `-L` is another option's value (`-Xlinker -L`) | cmdline's libDirs test and windows.zig's Rtools test extended; the dry run after: `lib -lssh2 <dir>/libssh2.lib`, -lidn2 still dropped |
| B7 R_ZIG_EXTRA_ENV warnings | confirmed. rzig dry run, a missing R_ZIG_EXTRA_ENV: zig-cc twice, zig-cxx three times on linux and twice on Windows (compiler.envFlags, libstdcxx.headersDir and runtime, windows.demoteZigLibs, RZIG_TRACE's list); R_ZIG_TOOLCHAIN_ENV the same way | environment.named resolves a variable's value once per command and keeps the answer in `Ctx.env_roots` (keyed by name and value; conda-meta looked at each time) | environment.zig's R_ZIG_EXTRA_ENV test: four rounds of list, extra and toolchainEnv give one warning each; a new value is resolved again. Dry run after: one line per variable |
| B7 list's mutable Ctx | confirmed as a leftover: the retired R_ZIG_FALLBACK_SOFT memo needed it. Kept mutable, now for named's memo (extra and toolchainEnv take `*Ctx` too; every caller already had one) | doc comment says why | compiles; unit tests |
| B8 --strict and libs smoke | confirmed. The exit status read `res$unexpected` only; a libs-smoke FAIL changed nothing | `--strict` also exits 1 when --libs-smoke was given and its line is not "pass" (FAIL, or "not run: ..."), with a message; header and stress/README.md say so | stress.R parses; the last three expressions evaluated with mocks on delta: 6 of 6 (strict off, no smoke, pass, FAIL, not run, an unexpected row) |
| B8 build-repo ${ORIGIN} | confirmed. origin_dir accepted `${ORIGIN}`; bundle()'s two checks `grep("^\\$ORIGIN", ...)` refused it, and accepted `$ORIGINAL` as relative | one `origin_rel` (`$ORIGIN` or `${ORIGIN}`, alone or followed by "/") used by both checks | below |
| B8 empty licence dir | confirmed. `dir.exists(lic)` passed an empty info/licenses; file.copy's result unchecked | no files: the package fails with "no licence files of ..."; a failed copy fails it | below |
| B8 test | | bundle() and its helpers evaluated from build-repo.R with prefix, lib and owner mocked; ELF fixtures linked with zig cc (pkg .so with `${ORIGIN}`, `$ORIGIN`, `$ORIGINAL`; libfoo with `$ORIGIN/.`, `${ORIGIN}`, `$ORIGIN/../lib`, `/abs`) | delta, R 4.6.2: 7 of 7; the pre-fix logic: 4 fail (`${ORIGIN}` twice, `$ORIGINAL` taken as relative, the empty licence directory passing) |

Tests of the rzig changes: rzig's unit tests, 244 of 244, with
conda-forge zig 0.17.1 and with upstream zig 0.17.1 (PyPI's ziglang,
fetch-zig's), sources touched first; check-test.sh 59 of 59 with each;
`zig fmt --check zigbuild/tools/rzig` clean.

B17 (report only): this track agrees with the docs track's rule and
would take R's own reading for the off side: on is `1`, `true` or
`yes`, any case; unset, empty, `0`, `false` and `no` are off; any other
value is off with a warning naming the variable (R's
tools:::config_val_to_logical warns and gives NA for it, see the
onoff track's review fixes).

On kappa (2026-11-26), rzig.exe cross-built from this worktree
(conda-forge zig, x86_64-windows-gnu) as `Library\lib\R\bin\toolchain\gcc.exe`
in a scratch tree, dry run (RZIG_PRINT_ARGV, RZIG_TRACE) of
`-shared -o x.dll a.o -L "<dir>" -lssh2 -lidn2 -lgpg-error` with
`<dir>\libssh2.lib` and a missing R_ZIG_EXTRA_ENV: `lib -lssh2
<dir>/libssh2.lib`, -lidn2 and -lgpg-error dropped, one R_ZIG_EXTRA_ENV
warning. Scratch removed.

Not verified (this track): a package install on Windows linking through
a two-argument -L (the dry run above is the command line only). The
launcher on linux-aarch64 and osx-64 (the same sh file). stress.R's
`--strict` in a real stress run.

## Track: build (B2, B3, B5, B9, B14, B15)

Scope: build.zig, zigbuild/toolchain/build.zig, verify-tree.sh,
verify-toolchain.sh, build-r.yaml's recommended step, pixi.toml (the
only track that edits it) and recipe.yaml's comments and m2 list.

| id | verdict and evidence | fix | test |
|---|---|---|---|
| B2 | confirmed. R 4.6's src/main/Renviron.c: `subterm` returns `""` for `${VAR}` unset with no default; `Putenv` then drops every `\` outside quotes. A harness of Renviron.c built with `-DRENVIRON_WIN32_STANDALONE` (the code Rcmd.exe and R.exe use) on build14's old line, R_HOME `C:/env/Library/lib/R`: unset gave the last entry `/Library/usr/bin`; `R_ZIG_TOOLCHAIN_ENV=C:\tc\env` gave `C:tcenv/Library/usr/bin` (a second defect of the same unquoted line) | rcmdEnviron: `R_ZIG_ENV_ROOT=${R_HOME}/../../..`, `R_ZIG_TOOLCHAIN_ROOT="${R_ZIG_TOOLCHAIN_ENV:-${R_ZIG_ENV_ROOT}}"`, and R_ZIG_TOOLS_PATH, quoted, ends in `${R_ZIG_TOOLCHAIN_ROOT}/Library/usr/bin` (unset or empty: R's own env's MSYS dir, the entry before it again). verify-tree.sh: the three expected lines, and an error for any uncommented `${R_ZIG_TOOLCHAIN_ENV}` | harness, new lines: unset and empty give `C:/env/Library/lib/R/../../../Library/usr/bin`, the backslash value is kept, a second read (nested R CMD) gives the same. kappa, a win-64 tree built from this worktree: `Rcmd.exe Rscript p.R` printed R_ZIG_TOOLCHAIN_ROOT = R_HOME/../../.. (normalizePath: the tree's Library\usr\bin) unset, and `C:\Users\admin\rz-build\tcenv/Library/usr/bin` set; verify-tree passed |
| B2 also seen | PATH's one root entry `/` comes from upstream's own `${PATH}/` ("trailing slash to protect against trailing backslash in PATH", gnuwin32's Rcmd_environ) when PATH ends in `;`: CRAN's R does the same | none (upstream's) | kappa, as above |
| B3 | confirmed. gnuwin32's fixed/Makefile: fixhtml copies html/rwin.html to doc/html/index.html, fixetc copies fixed/etc/* (Rdevga, rgb.txt among them), fixdoc copies CHANGES0-2 to doc/; installer ETC_FILES = Rprofile.site Rconsole Rdevga rgb.txt repositories Rcmd_environ; doc/Makefile.win makes CHANGES.rds, CHANGES and html/CHANGES.html, which rwin.html links. help.start() opens doc/html/index.html; devWindows.c's RFontInit reads R_HOME/etc/Rdevga. buildWindows calls installCommonPayload, not installStaticTree, so the Windows tree had none of them | installLibraryWindows installs etc/Rdevga, etc/rgb.txt, rwin.html as doc/html/index.html, doc/CHANGES0-2; the bootstrap's doc NEWS step also writes CHANGES.rds, CHANGES and html/CHANGES.html on Windows (doc/Makefile.win's commands). Not Rprofile.site (menu below) nor rw-FAQ.html (makeinfo, as R's manuals on every OS). verify-tree.sh: the four files on Windows | kappa: `pixi run --locked build` (slim) and verify-tree from this worktree, exit 0, "doc/html/{index,CHANGES}.html, etc/{Rdevga,rgb.txt}"; index.html has rwin.html's "Material specific to the Windows port"; delta: the CHANGES commands with the built linux R on R 4.6.2's CHANGES.Rd, no warning (44984, 27416, 38287 bytes) |
| B5 | confirmed. windows_dirs copied m2-tar and no m2-gzip; the conda package has m2-gzip since b13-fixes F10 | `m2Tool("m2-gzip")`; verify-toolchain.sh runs gzip --version with the other tools; pixi.toml's comment lists tar and gzip | kappa: `pixi run --locked toolchain` + verify-toolchain, exit 0, "38 tools run with PATH = System32"; with PATH = usr\bin and System32, `sh -c 'tar czf t.tar.gz x && rm -rf x && tar xzf t.tar.gz && cat x/f'` printed the file. usr/LICENSES/m2-gzip holds only recipe-scripts-license.txt (B1, menu M1) |
| B9 verify-toolchain.sh:386 | confirmed. `vers="$(cd <missing dir> 2> /dev/null && ...)"` fails under set -e, with both stderr streams sent to /dev/null: exit 1, no output (bash, the line alone) | `|| true`, so the message after it runs | the line alone: before, exit 1 and nothing; after, the message and exit 1 |
| B9 verify-tree.sh:198 | confirmed. a missing base extra directory (libstdcxx-shim) failed find inside `got="$(...)"`: exit before "holds ..., not ..." | `2> /dev/null`, `|| true` on got and want | delta, a copy of the built tree without libstdcxx-shim/: "error: lib/R/bin/toolchain/libstdcxx-shim holds '', not '...'", exit 1 |
| B9 cannot_check | confirmed in kind (the line number does not match this worktree): the closures read needed_of and rpaths_of, which print nothing without patchelf (linux), otool (macOS) or llvm-objdump (Windows), so every closure passed unread; only objdump had a cannot_check. Also `id="$(otool -D ...)"` in both scripts ended them silently without otool | verify-toolchain.sh: a cannot_check for the reader before the closures; `|| true` on the two otool -D lines | the block alone with PATH=/usr/bin:/bin on gamma: a note and on; CI=true: the error, exit 1; with patchelf: on |
| B9 wheel-test.sh rpath_of (second review) | confirmed. rpath_of ran readelf, else otool, else printed nothing; the decoy check took the empty result for "no rpath" and printed `ok: ... no rpath` without reading the file. (The R_ZIG_EXTRA_ENV check compares to `$xenv/lib` and fails loudly.) | the reader is picked once (`rpath_reader`); without one, cannot_check and `ok: rzig names only ... (rpath not read)`; the ok line names the reader | delta, the block alone on copies of libRblas.so: readelf, rpath removed: `ok: ... no rpath (readelf)`; readelf, `$ORIGIN` rpath: the error, exit 1; PATH with no readelf or otool, a file with an rpath: the note and "(rpath not read)" (before: "no rpath"); CI=true: the error, exit 1. The whole wheel-test not run (no wheel built in this track; the wheel workflow owns that run) |
| B9 verify-tree.sh reader (second review) | confirmed, beyond the finding's lines: verify-tree.sh had no reader guard. Without patchelf the rpath and DT_NEEDED closures pass unread, and the first needed_of use (libR's libomp, line ~730) fails with a wrong cause ("does not link libomp") | the verify-toolchain.sh guard at the top (patchelf, otool, llvm-objdump by OS): cannot_check, and the rpath and DT_NEEDED lines end in "(patchelf unavailable: NOT read)" | delta, the built linux slim tree: `pixi run --locked verify-tree` exit 0, unchanged output; the same with a shadow env without patchelf: the note first, then the libomp error, exit 1; CI=true: "error: patchelf unavailable ... (CI: every check must run)", exit 1 at the top. The rpath block alone: with patchelf, an absolute rpath (/build/env/lib) is an error, exit 1; without, the note and "NOT read" (before: "all relative"). macOS (otool) and Windows (llvm-objdump) branches not run: both tools are present there (Xcode CLT; pixi.toml's llvm-tools) |
| B9 recommended-test | confirmed: in no workflow | wired: build-r.yaml's recommended step runs it before recommended | delta: `pixi run --locked recommended-test --summary all`, 3/3 steps |
| B14 messages | confirmed. no `zig-build` task (pixi.toml has `build`); gen-subst.sh writes config.h, Rconfig.h and GENERATED_FROM itself (lines 110-112), so steps 2 and 4 were stale | `pixi run build`; the regeneration message has two steps, the gen-config workflow, Windows' PROVENANCE and the full PLAN.md path | zig build -l |
| B14 dead code | confirmed. Ctx.linkLapack never called (the lapack module links ctx.rlapack); ctx.openmp_pkgs written, never read (checkVariantConfig reads the table's field); `%C` in no extra; Rscript.c reads R_HOME only under `#ifndef _WIN32` (R 4.6 source); replaceLine's TCL_HOME line equals the LF template's line 37 (upstream's), so a no-op | all removed; comments say where packages' OpenMP and TCL_HOME come from | zig fmt --check, zig build -l (with a prefix), linux and Windows builds |
| B14 gnuwin32O3ToO2 | rejected as a bug. the template is upstream's etc/Makeconf with recorded edits (diff: no -O change), and the pass is fixed/Makefile's own `s/-O3/-O2/`; editing the template instead would hide that line from a diff against upstream | none | read |
| B14 comments | confirmed. lines 3-5 ("linux-64 and macOS so far", "F6 Windows remains"), 674-684, the Rscript and buildWindows banners, the `r` step's description ("Rscript.exe ... CLI-only") and the "etc/ stays deferred" note | rewritten: Windows builds R.dll, the libraries and Rscript, Rterm, R, Rcmd and bin/'s R and Rscript, no Rgui | read |
| B14 flang | confirmed. fortranOne ran `flang` from PATH though build() locates it (BUILD_PREFIX, then the env) | `Ctx.flang`, the located file | delta and kappa build logs: `<env>/bin/flang -O2 -c ...`, `...default/Library/bin/flang.exe -O2 -c ...` |
| B14 other host tools (follow-up) | confirmed, not changed: by bare name `patchelf` (linux SONAME), `chmod`, `cp`, `rm`, `mkdir`, `gzip -9fn` (bootstrap), `make` (check steps), `sh -c 'rm; cp'` (check tree). In the pixi env all but sh resolve to the env (delta: `command -v`); `sh` is /usr/bin/sh. `iconv -l` is the host's /usr/bin/iconv (glibc's on linux, the system's on macOS) and its output ships as library/utils/iconvlist | none: each needs its own change (an env tool by path, or iconvlist from R's own iconvlist()) | delta, `pixi run bash -c 'command -v ...'` |
| B15 m2-texinfo | confirmed dead: no makeinfo, texi2any or install-info in the build, scripts or zigbuild | removed from pixi.toml's toolchain feature and recipe.yaml's Windows build deps; recipe comments rewritten | pixi lock (below) |
| B15 full-openblas | confirmed: no workflow, task, script or doc uses it | environment removed; comments that named it updated | pixi lock |
| B15 comments | confirmed. pixi.toml: "all 20 legs" (build.yaml: 7 + 14 = 21), configure-r.sh (gone; R_BUILD_VARIANT is env.sh's VARIANT), the self-hosted runner, minimal's profile "guaranteed by configure-only.sh"; recipe.yaml: the "gnuwin32 ... native make can't spawn the zig shim scripts" block, "tar/gzip stay build:-only" above `- m2-tar` and `- m2-gzip`, no publish date for build 13 | rewritten; build 13: published 2026-11-26, run 45858899338, main 77abec1 (chore-release-13) | read |

pixi.lock: fcae3a49b0e2 → 15d0764b893f (`pixi lock`, gamma; `pixi lock
--check` clean). Only removals: m2-texinfo, m2-perl, m2-info, m2-db,
m2-gdbm, m2-libdb, m2-libgdbm and m2-libxcrypt from default, full,
minimal, pkg and stress on win-64 and win-arm64 and from openblas on
win-64, and the full-openblas environment. No other package moved.

Tests: delta, this worktree: `pixi run --locked build` (slim) and
verify-tree, exit 0; `pixi run --locked toolchain` and verify-toolchain,
exit 0; toolchain-test and recommended-test, exit 0; `zig fmt --check
build.zig zigbuild/toolchain/build.zig` clean; `zig build -l` exit 0;
`bash -n` on both scripts. kappa, the same snapshot: build and
verify-tree, toolchain and verify-toolchain, exit 0, plus the Rcmd.exe
and tar runs above; scratch removed.

B17 (report only): this track takes the docs track's rule (on: `1`,
`true`, `yes`, any case; everything else off), read by one helper per
language: rzig, R (patch 0009's preflight), stress.R and the docs.

Not verified (this track): win-arm64, macOS (the otool lines, and
CHANGES on Windows ARM), a full-variant Windows build; a package whose
configure needed the env's m2-perl on PATH (the stress env on Windows
loses it; no stress row names perl); the Windows standalone archive
(package-standalone) with gzip.

## Track: wheel items (deferred until the rpy2 work finished)

| id | verdict | fix | test |
|---|---|---|---|
| B8 `python/r_zig/__init__.py` ZIG_BIN | confirmed by reading: `environ()` turned only its own zig path's backslashes into `/`; a user's `ZIG_BIN` with backslashes went to R unchanged and Renviron.site's `${ZIG_BIN-...}` drops them | the same `/` rule for a user's `ZIG_BIN` on Windows | `ast.parse`; on linux the branch is a no-op. Not run on Windows |
| B15 `scripts/make-wheel.py` descriptions | confirmed: the unix build-tools text said GNU make is "conda-forge's build of it, unchanged" (it is zigbuild/make since build 13), the Windows text called every program an m2 package (pkgconf since build 11 and zip since build 14 are built with zig) | both texts corrected; the licence sentence waits for the user's M1 | `ast.parse` |

## User decisions on the review menus (2026-11-26)

The user answered chore-review-consistency's menus M1-M6 with "Continue
with recommended" (relayed by that session, PR #59). Their parts in
build14's files:

| menu | choice | applied here |
|---|---|---|
| M1 m2 licences | (a) | `hasLicenseFiles` (zigbuild/toolchain/build.zig) skips conda-forge's `recipe-scripts-license.txt`, so `ownLicenses` runs for the m2 packages again; the same rule in repo/build-repo.R (a package whose only licence file is that one fails). m2-gzip and gzip in verify-toolchain.sh were already in (B5). The retaken `licenses/m2-*/` directories (and new m2-tar, m2-gzip) come from PR #59; until they are in this tree the Windows toolchain build stops on VERSION, as designed. `zig fmt --check`, R `parse()` on delta; the Windows toolchain build is not run yet |
| M2 skip tags | (a) | CONVENTIONS.md "Skip tags" |
| M3 publish on dispatch only | (a) | build.yaml is PR #59's; here README.md's CI section and the pixi.toml ci-trigger comment say a dispatch on main publishes once, in `conda-publish`, after all six conda-package legs; a push never |
| M4 macOS SDK | (a) | CONVENTIONS.md Goals and README.md Goals name the exception, checked against build.zig:519 (`/usr/bin/xcrun --sdk macosx --show-sdk-path`, `b.run` stops on failure) and rzig darwin.zig (`-F<sdk>/System/Library/Frameworks`, `-L<sdk>/usr/lib`, `no_sdk` warning) |
| M5 root PLAN.md/TODO.md symlinks removed | (a) | README "More detail" and pixi.toml's configure comment name `.github/devdocs/feat-zig-build/PLAN.md`; build.zig's message already did |
| M6 launcher | (a) | already done here (track rzig, B4, 75-case test); PR #59 was told to skip it |

## User decisions on the build14 menus 3-8 (2026-11-26)

The user: "Continue" after the menu list, taken as the recommended
options, as for every earlier menu.

| # | choice |
|---|---|
| 3 | (a) rscript-test.sh in CI on the linux core leg |
| 4 | (a) bin/R compares R_HOME physically before warning |
| 5 | (a) one on/off rule: 1, true, yes (any case); other values off, with a warning |
| 6 | (a) upstream's etc/Rprofile.site stays out on Windows |
| 7 | (a) next build: iconv -l and sh from the env (or iconvlist from R); not in build 14 |
| 8 | (a) igraph proven in the build-14 PR's native_tools stress leg |

## Track: onoff (item 5, B17: one rule for every on/off switch)

The user's menu 5 choice (a), 2026-11-26: an on/off variable is on when
its value is `1`, `true` or `yes` (any case); unset, empty, `0`, `false`
and `no` are off; any other value is off, with a warning naming the
variable.

### Readers found

| variable | reader(s) before | now |
|---|---|---|
| `RZIG_TRACE` | rzig main.zig, pkgbuild.zig, libstdcxx.zig, windows.zig: on unless unset, empty or `0` (windows.zig: empty was on) | `Ctx.on` |
| `RZIG_PRINT_ARGV` | rzig main.zig: on unless unset, empty or `0` | `Ctx.on` |
| `RZIG_KEEP_ROOT` | rzig pkgbuild.zig: on unless unset, empty or `0` | `Ctx.on` |
| `R_ZIG_SYSTEM_LIBS` | rzig system_libs.zig: on unless unset, empty or `0` | `Ctx.on` |
| `R_ZIG_NO_PREFLIGHT` | patch 0009: on when non-empty (`0` was on); rzig check.zig: on when non-empty | `tools:::.rzig_on`; `Ctx.on` |
| `R_ZIG_CONFIGURE` | rzig check.zig (0009 sets `1` or `0`): on unless `0` | `Ctx.on` |
| `R_ZIG_NATIVE_TOOLS` | patch 0018 (install.R and Rprofile.windows): `1`, `true`, `yes`, any case, silent otherwise | `tools:::.rzig_on` |
| `R_ZIG_BOOTGATE_LIST` | build.zig and zigbuild/tools/bootgate.zig: on when set, even empty or `0` | `onoff.parse` |
| `RZIG_SMOKE_CRAN` | rzig smoke-test.sh: on only for `1` | verify-helpers.sh `switch_on` |

Left alone: `R_ZIG_ENV_RPATH` (`0`, `origin` or unset, its own values;
compiler.zig's `envRpath` unchanged, its test still passes `0`),
`R_ZIG_PKG_BUILDER`, `R_ZIG_JOBS`, `R_ZIG_C_STD`, `RZIG_OS`,
`RZIG_TEST_STRESS` (a count) and the path variables. `R_ZIG_RELEASE` and
`R_ZIG_REPO_PUBLISH` are GitHub repository variables read by workflow
expressions (`vars.X == 'true'`), not by a program: decision O1 below.
No reader in python/r_zig, stress/stress.R (it only sets `RZIG_TRACE=1`
and `R_ZIG_NATIVE_TOOLS=1`), scripts/*.py, or the Renviron, Rprofile and
Rcmd_environ lines build.zig writes.

### Changes

- `zigbuild/tools/rzig/onoff.zig` (new): `parse` (on, off, other) and
  the warning text, std only, so that build.zig and bootgate.zig import
  it too; its own test (on: `1 true TRUE True yes YES`; off: unset,
  empty, `0 false FALSE no No`; other: `maybe 2 on y " 1" "1 "`).
- `Ctx.on(name)` (Ctx.zig): the rzig reader; warns once per run and
  variable (`switches_warned`), since a compile reads `RZIG_TRACE` up to
  three times. main.zig's and pkgbuild.zig's `isSet`, check.zig's
  `envSet` and libstdcxx.zig's and windows.zig's own tests are gone;
  `keepRoot`, `traced` and `system_libs.enabled` take `*Ctx`.
- Patch 0009 defines `.rzig_on(name)` in tools' install.R (after
  `.shlib_internal`, a spot no other patch touches), with a per-process
  record of the warned names (`.rzig_warned`, an environment), and the
  preflight reads `R_ZIG_NO_PREFLIGHT` through it. Patch 0018's
  `.rzig_native_tools` reads `R_ZIG_NATIVE_TOOLS` through it; its
  Rprofile.windows block calls `tools:::.rzig_on` only when the variable
  is set, inside `tryCatch` (an R without tools, R's own build, takes it
  as off). Patch 0013's last hunk header moved by 21 lines (`-3493
  +3517`), regenerated, so the series applies with no offset, as before.
- `switch_on` in scripts/verify-helpers.sh (the sh helper smoke-test.sh
  already sources); smoke-test.sh's `RZIG_SMOKE_CRAN` uses it.
- build.zig and bootgate.zig read `R_ZIG_BOOTGATE_LIST` through
  `onoff.parse`, with a warning for other values.
- Docs: README.md (the rule, after the preflight paragraph, with what
  changed from build 13), rzig main.zig's header, check.zig's and
  windows.zig's comments, patch headers 0009 and 0018. The docs already
  wrote `=1` for every switch (README, stress/README.md, stress.R).

Behaviour changes from build 13: `R_ZIG_NO_PREFLIGHT=0` (and `false`,
`no`) no longer skips the preflight; `RZIG_TRACE=x` and the like no
longer turn tracing on (they warn); `R_ZIG_BOOTGATE_LIST=` (empty) or
`=0` no longer writes the lists; `RZIG_SMOKE_CRAN=true` now runs the
CRAN part.

### Patches regenerated

As zig-build.sh applies them: pristine R 4.6.2 (rsrc tarball, sha256
c297040f... as scripts/checksums), 0001-0008, then 0009 edited in place
and diffed with `diff -u --label a/<f> --label b/<f>` under its old
header text; 0010-0012, 0013 rediffed (only its last hunk header
changed); 0014-0017; 0018 edited and diffed the same way. The full
series 0001-0018 applies to a pristine tree with `patch -p1 -f -F0`, no
offset and no fuzz, and the result is identical (`diff -r`) to the
tree the edits were made in.

### Tests

| test | result |
|---|---|
| `zig test onoff.zig` (upstream zig 0.17.1, gamma) | 1/1 |
| bootgate built with upstream zig; `R_ZIG_BOOTGATE_LIST` = empty, `1`, `TRUE`, `maybe`, `0`, unset | lists for `1`, `TRUE` only; one warning for `maybe` |
| rzig-test (zigbuild/tools/rzig/test.sh) on delta, conda-forge zig 0.17.1 | 246/246 unit tests (new: `Ctx.on` rule and once-only warning, R_ZIG_SYSTEM_LIBS values, R_ZIG_NO_PREFLIGHT `""`, `0`, `false` off and `TRUE` on), fetch 5/5, check-test.sh 67 passed 0 failed |
| the same, upstream zig 0.17.1 (sources touched) | 246/246, 5/5, 67/0 |
| new check-test.sh cases (real binary) | `R_ZIG_NO_PREFLIGHT=YES` skips the version check (0); `=false` keeps it (1, no warning); `=maybe` keeps it with exactly one warning line; `RZIG_PRINT_ARGV=true` is a dry run (zig not run), `=0` runs zig; `RZIG_TRACE=maybe` warns once and does not trace; `RZIG_TRACE=Yes` traces |
| `.rzig_on` taken from the patched install.R, R 4.5.3 (gamma) | `1 true TRUE True yes YES` on; unset, empty, `0 false FALSE no No` off; `maybe` off with one warning, none the second time |
| `parse()` of the patched install.R and Rprofile.windows | ok |
| `switch_on` (bash, `set -u`) | same table as R; one warning on stderr for `maybe` |
| recipe/test-preflight.R | new block: `tools:::.rzig_on` cases, `R_ZIG_NO_PREFLIGHT=false` and `=maybe` keep the preflight (maybe with the warning); not run here (needs r-zig-slim alone: a conda-package run) |
| linux tree on delta (~/rz/b14m-onoff, conda-forge zig, `pixi run build` then `pixi run verify-tree`) | build 0, the 18-patch stamp; verify-tree "installed tree verified (linux/slim)" |
| `tools:::.rzig_on` in that tree | the rule's table; one warning for `maybe` across two calls |
| patch 0018's Rprofile.windows block, sourced by that R (linux) | unset and empty: PATH unchanged, tools not loaded; `0`: unchanged (tools loaded); `maybe`: unchanged, one warning; `TRUE`, `yes`: native/bin put first |
| `R CMD INSTALL` of a C package, `ZIG_BIN` a zig 0.99.0 | `R_ZIG_NO_PREFLIGHT` unset, `0`, `false`: stops in the preflight ("not R's zig", "cannot be built"); `maybe`: the same, with R's warning and rzig's (one each); `1`, `TRUE`: no preflight stop |
| `R CMD SHLIB foo.c`, real zig | `RZIG_TRACE=0`: no trace; `=maybe`: no trace, one warning per rzig process (rzig build, the compile, the link: 3); `=yes`: traced |

A value that is neither on nor off warns once per process that reads
it: R and rzig's check for `R_ZIG_NO_PREFLIGHT` (two lines), and each
rzig process of a build for `RZIG_TRACE` (`rzig build` and the
`zig-cc` compile and link it runs: three lines for one file): decision
O2.

Not verified: Windows (`.rzig_native_tools` and the Rprofile.windows
block in a Windows R; windows.zig's trace reader ran only in the unit
tests on linux), macOS, recipe/test-preflight.R's new block (needs
r-zig-slim alone, a conda-package run), smoke-test.sh's
`RZIG_SMOKE_CRAN` (needs network and a tree; the helper alone was
run), the bootgate list during a real bootstrap.

### Decisions for the user

O1. `R_ZIG_RELEASE` and `R_ZIG_REPO_PUBLISH` (GitHub repository
variables, publish guards):
- (a) ★ leave them at `== 'true'`: they gate a publish, are set and
  deleted around one run, and GitHub's `==` already ignores case
  (`TRUE` works); a warning has no place to go.
- (b) accept `1` and `yes` too, through
  `contains(fromJSON('["1","true","yes"]'), vars.X)`.

O2. A value neither on nor off, read by several processes:
- (a) ★ one warning per process (now): simple, each process says what it
  read.
- (b) one warning per build: rzig build passes an internal marker to the
  processes it runs; more code for a misconfiguration the first line
  already names.

### Review fixes (2026-11-27)

Three comment errors from the review, no behaviour change:

- check.zig: the doc line of the removed `envSet` sat on top of
  `envValue`'s; removed.
- Patch 0009, `.rzig_on`'s comment: it said R's `config_val_to_logical`
  would stop on a value that is neither on nor off. It does not: in R
  4.6.2 it is `utils:::str2logical` (utils/R/strcapture.R), which
  warns "cannot coerce ... to TRUE or FALSE" and gives `NA`; it also
  takes `as.logical`'s spellings, so `T` and `F` are on and off there.
  The comment now says R's rule differs in both. Same line count, so
  no hunk header moved. The rzig track's B17 note (above) said R
  "errors on it"; corrected there too.
- onoff.zig's header named smoke-test.sh's `on`; the helper is
  `switch_on` in scripts/verify-helpers.sh (smoke-test.sh calls it).

Finding (design difference, not a bug): `R_ZIG_NO_PREFLIGHT=T` warns
and is off under the r-zig rule, while R's own rule takes `T` as TRUE.
`True`, `TRUE`, `true` are on in both: decision O3.

| test | result |
|---|---|
| series 0001-0018 on pristine R 4.6.2 (sha256 c297040f...), `patch -p1 -f -F0` (gamma) | applies, no offset, no fuzz; install.R parses; its `.rzig_on`: `1 TRUE yes` on, `"" 0 no` off, `T` and `maybe` off with the warning |
| `zig fmt --check zigbuild/tools/rzig`; `zig test onoff.zig` (gamma, 0.17.1) | clean; 1/1 |
| rzig-test on delta (~/rz/b14m-onoff, worktree synced), conda-forge zig 0.17.1 | 246/246, fetch 5/5, check-test.sh 67 passed 0 failed |
| the same, upstream zig 0.17.1 (`ZIG_BIN`) | 246/246, 5/5, 67/0 |
| delta `pixi run build` then `pixi run verify-tree` (slim, linux-64) | build 0 ("zig-built R OK"), verify 0 ("installed tree verified (linux/slim)"); built install.R has the new comment |
| that tree: `tools:::.rzig_on("X")` with `X=T`; `tools:::config_val_to_logical` of `maybe` and `T` | `FALSE` with the warning; `NA` with "cannot coerce 'maybe' to TRUE or FALSE"; `TRUE` |
| readers.sh against that tree (`.rzig_on` table, Rprofile.windows block) | `rzig_on ok`; the block's table as before (unset, empty, `0`, `maybe` keep PATH; `TRUE`, `yes` change it; one warning for `maybe`) |

O3. `T` and `F` (R's `as.logical` spellings) for the on/off switches:
- (a) ★ keep the rule as chosen (menu 5): `T` and `F` warn and are off;
  the docs and every example write `1`, and one short list is the same
  in Zig, R and sh.
- (b) accept `T` as on and `F` as off too, in onoff.zig, `.rzig_on`
  and `switch_on`, to match R's `config_val_to_logical` on those two.

## Track: launcher-front (items 3 and 4)

Menus 3 and 4 above, option (a) of each. Tested on a copy of this
worktree taken 2026-11-26 (delta `~/rz/b14m-front/src`).

| item | change | test |
|---|---|---|
| 3 rscript-test.sh in CI | build-r.yaml, after "rzig tests": step "Rscript launcher against the compiled Rscript (r-base 4.6.2)", `if: runner.os == 'Linux' && runner.arch == 'X64' && inputs.env == 'default' && inputs.zig == 'conda'`, so it runs once per build.yaml run, on the core tier's linux-64 default leg (`inputs.linux_runner`, ubuntu-latest by default), and not in upstream-zig.yaml's legs nor build-full's (no default env there). `pixi exec --spec r-base==4.6.2 -- bash -c '...'` runs rscript-test.sh with `"$CONDA_PREFIX/lib/R"` as the reference, `SH=/bin/sh` (dash) and then `SH=/bin/bash`, joined by `&&`: a mismatch exits 1 and fails the leg. The exec env is pixi's cache, not pixi.lock; the version is pinned, the build string is not (conda-forge's newest 4.6.2 build). No pixi task (pixi.toml unchanged): the step is the only caller | `pixi exec -s actionlint -s shellcheck -- actionlint .github/workflows/*.yaml`: clean (SC2016 on the single-quoted `$CONDA_PREFIX` disabled in the step, it is meant for the inner bash). The step's `run` text taken from the YAML (PyYAML) and run on delta with `bash --noprofile --norc -eo pipefail` (Actions' bash): exit 0, "rscript-test (/bin/sh): 75 passed, 0 failed", "rscript-test (/bin/bash): 75 passed, 0 failed". Negative: the same with a launcher whose usage text differs in one word: 2 FAIL lines, exit 1 |
| 4 bin/R compares R_HOME physically | build.zig makeRFrontScript replaces R.sh.in's `   test "${R_HOME}" != "${R_HOME_DIR}"; then` with that test plus `test "$(cd -P "${R_HOME}" 2>/dev/null && pwd)" != "${R_HOME_DIR}"`; R_HOME_DIR is already physical (`cd -P`), so an R_HOME naming the same tree through a symlink, with trailing "/", as `bin/..` or relative to the cwd does not warn; another tree, a missing directory or a parent still warns, as upstream; unset or empty never did. The same rule as zigbuild/launchers/Rscript's unset. The build stops (`error.RShInChanged`) when R.sh.in no longer has that line, so an R update cannot drop the rule silently. Everything else in R.sh.in is unchanged; the launcher's own unset stays (it also covers RHOME naming another R's tree, whose bin/R compares strings), its header comment now says so (the CI step rerun after that edit: 75 and 75 passed) | delta, `pixi run --locked build` (slim, linux-64): exit 0, "zig-built R OK"; `pixi run --locked verify-tree`: exit 0. A case script (`R_HOME` unset, empty, plain, "/", "//", symlinked prefix, symlink + "/", `bin/..`, relative `lib/R`: quiet; another tree, missing, `lib`: warn; each through lib/R/bin/R and through a symlinked prefix; `R RHOME` and the real `R -s -e 'cat(R.home())'`, whose last line must be the physical R_HOME): 46 of 46 with /bin/sh (dash) and bash. By hand: `R_HOME=<symlink>/lib/R <symlink>/bin/Rscript -e` with a child `R CMD config CC`: no warning, R.home() physical; `R_HOME=/elsewhere`: the warning from Rscript's bin/R and from `lib/R/bin/R --version`. omicron (macOS 26, arm64), the generated script text in a stub tree (`R RHOME` only, no build): 23 of 23 with /bin/sh (bash 3.2), bash, dash and zsh, under ~ and under /tmp (R_HOME as /tmp/..., /tmp/.../, /private/tmp/... quiet; /tmp/elsewhere warns); the upstream string compare in the same harness: 11 of 23 fail (the quiet same-tree cases). omicron dirs removed |

Hand-over: zigbuild/launchers/rscript-test.sh (from the B4 track) is
not tracked by git yet and the CI step of item 3 runs it, so it must be
in the commit with build-r.yaml (`git add zigbuild/launchers/rscript-test.sh`);
without it the step fails with "No such file" instead of testing.

Review fixes (2026-11-27): rscript-test.sh's comment on the
env-rhome-same cases no longer says this tree's bin/R would warn (after
item 4 it does not; the unset is kept for an RHOME tree whose bin/R
compares strings); row "B4 re-review, also found" in the rzig track
now points to item 4. Rerun on delta after the comment edit (the
step's `run` text from build-r.yaml, `bash --noprofile --norc -eo
pipefail`): exit 0, "rscript-test (/bin/sh): 75 passed, 0 failed",
"rscript-test (/bin/bash): 75 passed, 0 failed".

Not verified: busybox sh for bin/R (the case script's harness could not
start it through `env`; dash, bash, bash 3.2 and zsh were run); the CI
step on GitHub's runner (the commands were run on delta, ubuntu's
/bin/sh is dash there too); a macOS tree built with this build.zig (the
generated linux text was used; makeRFrontScript is OS-independent);
the conda package build (recipe/build.sh runs the same `zig build`).

## M1 test on kappa (2026-11-27)

build14 snapshot (hasLicenseFiles change) with PR #59's 20 `licenses/m2-*/`
folders and licenses/README.md overlaid (copies only; neither worktree
edited), kappa win-64: `pixi run --locked toolchain` exit 0 (9 min 50 s),
`verify-toolchain` exit 0 ("31 packages, each with its LICENSES/"; 38
usr/ tools run with PATH = System32, gzip among them; native/ verified),
`toolchain-test` exit 0. usr/LICENSES/ has all 20 m2 packages, each
identical to its licences folder, and no recipe-scripts-license.txt;
SOURCES names each package's MSYS2 source archive (for example
gzip-1.15-1.src.tar.zst, tar-1.35-3.src.tar.zst). No missing package.
The folders reach build 14 through PR #59, not a copy here.

- 2026-11-27 (V) PR #59's second push moves the upload into a
  `conda-publish` job (dispatch on main, CONDA_PUBLISH only). pixi.toml's
  conda-publish task comment now says that job runs the task once per
  subdir, and the stale "six per-platform copies (Q10)" sentence is gone.
  README's publish text already matched. Lock unchanged (15d0764b893f).
  recipe/test-native-tools.R exists on build14, so conda-consume.sh's
  native-tools env first runs in build14's CI.

## User decisions O1-O3 (2026-11-27)

The user chose the recommended option of each ("All recommended"):

| decision | chosen | effect |
|---|---|---|
| O1 publish guards | (a) | `R_ZIG_RELEASE` and `R_ZIG_REPO_PUBLISH` stay `vars.X == 'true'` in the workflows; no change |
| O2 repeated warning | (a) | one warning per process, as implemented; no change |
| O3 `T` and `F` | (a) | they warn and are off; onoff.zig, `.rzig_on` and `switch_on` unchanged |

No code changes from these three: the worktree already implements (a)
of each.

## Build 14 commit plan (2026-11-28)

Base: main e999d92 (PR #59 merged; build14 moved onto it by the user,
one header conflict in scripts/verify-helpers.sh resolved). Lock
sha256 0b512c3435b4. Nine commits, one per topic; a file that carries
more than one topic goes to one commit, named in its message:

| # | type | topic | files |
|---|---|---|---|
| 1 | fix | win-64 openblas 0.3.33 and the one relock | pixi.toml, pixi.lock (the relock takes every pixi.toml change: the pin, slice 3, B15) |
| 2 | feat | the on/off rule; rzig without R_ZIG_FALLBACK_SOFT, with R_ZIG_ENV_RPATH | zigbuild/tools/rzig/ (builds only as a whole), bootgate.zig, verify-helpers.sh, patches 0009 and 0013, recipe/test-preflight.R |
| 3 | feat | native Windows build tools, r-zig-native-tools, patches 0017 and 0018 | zigbuild/busybox/, zigbuild/zip/, zigbuild/toolchain/*, zigbuild/make/build.zig, recipe/, scripts/env.sh, verify-toolchain.sh, compile-tree.sh |
| 4 | test | stress without the Rtools45 tree, slice 3 rows, native_tools | stress.yaml, stress/ |
| 5 | feat | experimental repository and rpy2 from the wheel | repo/, repo.yaml, python/r_zig/, make-wheel.py, wheel-test.sh |
| 6 | fix | Rscript launcher, tested in CI | zigbuild/launchers/, build-r.yaml (rscript-test.sh must ship with the step that runs it, launcher-front track) |
| 7 | fix | build.zig and verify-tree.sh review findings, bin/R R_HOME | build.zig, scripts/verify-tree.sh |
| 8 | docs | goals, principles and user docs | README.md, CONVENTIONS.md, CXX-STDLIB.md, devdocs README.md (index), RELEASE.md |
| 9 | docs | records | b14-*/, chore-release-13/, b13-integration/CI-WAVE.md |

Coverage check (script over the `git add` lines against `git diff
--name-only HEAD` plus untracked files): 75 wanted, 75 added, none
twice, none missing. Commits 2 to 7 may not build on their own; CI tests
the PR head. The superseded "Suggested commit messages" sections of
b14-l4 and b14-l5 point here.

Integration review after the move onto e999d92 (no behaviour change
found; six doc gaps fixed): the devdocs index lists b14-review;
RELEASE.md counts r-zig-native-tools (8 outputs on win-64, 7 on
win-arm64, 7 per unix subdir; b14-l4 F26's render); README names the
consume test's tcltk and native-tools environments and the conda-publish
job; compile-tree.sh's comment names native/; b14-l4 F27 closed (main's
conda-consume.sh has the native-tools env). The review's F4 (the
verify-helpers.sh header) was already covered by the switch_on comment.

Tests after the move (delta ~/rz/b14rb, the snapshot at lock
0b512c3435b4): rzig-test 250/250, fetch 5/5, check-test.sh 67/0 with
conda-forge and upstream zig 0.17.1; zig fmt clean (68 files); patches
0001-0018 apply with -F0 to pristine R 4.6.2 and the patched R files
parse; build and verify-tree (slim, linux-64) pass; rscript-test 75/75
with dash and bash; toolchain and verify-toolchain pass; bash -n on the
changed scripts; actionlint clean; pixi lock --check ok. (The review's
66/66 check-test.sh count came from a partial copy without
zigbuild/rpkg; 67 is the full tree's.)

Second round on the same delta snapshot (2026-11-28, the critic's gaps):
the changed R files parse (stress.R, smoke/hdf5r.R, test-preflight.R,
test-native-tools.R, build-repo.R, install-test.R); the changed Python
files compile; rzig-test with the built R runs smoke-test.sh ("rzc,
rzcxx, rzomp, rzf built through rzig load and run"); toolchain-test
`--summary all`: 20/20 steps; recommended then recommended-test: exit 0;
shellcheck -S warning on the changed scripts: the same 20 warnings as
main's copies, none new; `conda-package` (linux-64): seven outputs at
number 14 (r-zig-slim h3e03716_14, r-zig-toolchain h71bc1f0_14, the
rest h9d0481e_14; no r-zig-native-tools, skipped off Windows), then
`conda-consume`: exit 0 (recommended 15 loaded, tcltk Tcl 8.6.13).
Windows-only parts (busybox-w32, make's BATCH_MODE_ONLY_SHELL, zip,
patches 0017 and 0018, test-native-tools.R, the conda native-tools env)
have no local evidence in this round: kappa ran the slice-3 rows (F28 in
b14-rhtslib), the rest is CI's and the stress dispatches'.

## PR #60 CI, first round (2026-11-28)

build-r 46160406600 and upstream-zig 46160406612 on 56c750d. Failed
jobs, read from each job's log:

| job | step | cause |
|---|---|---|
| build-r windows-latest / toolchain | Build + archive the toolchain tree | F-C1 |
| upstream-zig windows-11-arm / toolchain | the same | F-C1 |
| conda-package / win-64, win-arm64 | Build + test conda package | F-C1 (rattler-build's source fetch) |
| windows-latest / default, full, minimal, openblas; upstream-zig windows-11-arm / default | Download the toolchain groups | no toolchain archive (F-C1) |
| macos-latest / minimal, macos-15-intel / minimal | Build + test the r-zig wheel | F-C2 |

- F-C1 (V) frippery.org answers busybox-w32-FRP-6354-g5f09fb446.tgz with
  `403 Forbidden` to some GitHub-hosted runners (both toolchain logs:
  `build.zig.zon:28:20: error: bad HTTP response code: '403 Forbidden'`;
  conda-package: `HTTP status client error (403 Forbidden)`). The
  build-r windows-11-arm toolchain job fetched it, so the refusal depends
  on the runner's address. From gamma every User-Agent zig and
  rattler-build send gets 200 (only `Go-http-client/1.1` gets 403). The
  earlier fetches were on kappa and delta, never on a hosted runner.
- D-B1 (user, 2026-11-28, option a) busybox-w32's source is GitHub's
  archive of the release tag,
  https://github.com/rmyorston/busybox-w32/archive/refs/tags/FRP-6354-g5f09fb446.tar.gz
  (sha256 b076d55e4aca74d57d4e77c2ca77abc94dd4926f424fa752889414e1b68f6ebc,
  zig hash N-V-__8AAPEAvgBuQupMj-ICN-yT2RYz3ygu9awV7iCqhFX8), in
  busybox.zig, both build.zig.zon files and recipe.yaml. Option b
  (frippery's exact tarball as a release asset of this repository) was
  not taken: it needs a manual upload. The two unpacked trees are the
  same (`diff -rq`) except frippery's `.frp_describe`, so
  zigbuild/busybox/build.zig checks that file only when it is present;
  the URL and hash pin the release.
  Evidence (delta, zig 0.17.1): busybox.exe built from each source is
  byte-identical (x86_64 738,816 B 9749cec02f90, aarch64 656,896 B
  9a358890c244); `zig fetch` of the frippery tarball gives the old zon
  hash; zig fmt --check ok; toolchain-test exit 0 (busybox.zig's tests
  check the zon and recipe pins).
- F-C2 (V) wheel-test.sh's per-user library check compared R_LIBS_USER
  with the raw $HOME. R builds the default from `normalizePath("~")`
  (library.R), and on macOS TMPDIR is under /var, a link to
  /private/var, so `startsWith` failed although the library was right.
  The check now normalizes both paths.
  Evidence (delta, linux-64): `pixi run -e minimal build`, `wheel`, then
  `wheel-test` pass ("ok: .../home/.local/share/R/linux-64-zig/4.6/
  rzigUserLib"); macOS is CI's.
- F-C3 (V) In the same build-r run windows-11-arm / default passed: the
  toolchain job there fetched frippery's tarball, and that leg's rzig
  tests, build, verify-tree, smoke, contract, parity, regression,
  recommended, hermetic and standalone-archive steps ran green on
  win-arm64 (the native-tools test is conda-package's and stress's).

## PR #60 CI, second round (2026-11-28)

build-r 46171347861 and upstream-zig 46171347880 on 09b457e. All
toolchain jobs pass, the Windows ones included (D-B1's source), and
upstream-zig's legs are green. conda-package linux-64, linux-aarch64,
osx-64, osx-arm64 pass. conda-package win-64 and win-arm64 built and
tested r-zig-slim, r-zig-compilers and r-zig-build-tools, then failed:

- F-C4 (V) r-zig-native-tools' package content test: `not_exists:
  Library/lib/R/bin/toolchain/*.exe` matched native/bin/*.exe ("Found
  matches for files 'not_exists' glob ... files should not exist").
  rattler-build's `*` also matches `/`. Reproduced on delta with
  rattler-build 0.80.1 and a two-recipe check: `t/*.exe` fails on
  t/native/bin/sh.exe, `t/{rzig,gcc,sh}.exe` passes. The entry now names
  r-zig-slim's exes, `toolchain/{rzig,gcc,nm,objdump,strip,dlltool,
  windres,as}.exe` (the list its own `exists` test has). The run stopped
  there, so r-zig-native-tools' script test (test-native-tools.R) and
  the outputs after it (extras, recommended, tcltk, toolchain) have no
  Windows evidence yet.
