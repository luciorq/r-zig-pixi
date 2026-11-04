# Phase 7 plan: self-critique and amendments

2026-10-19. One pass over `PHASE7-IMPLEMENTATION.md` (the planner's
first version), checked against:
- the code: wt/feat-standalone-phase6 (read only; 79 status entries,
  `git diff | sha256sum` 9587f87ad4a6e48c at the start, pixi.lock
  fbb64b7ba4e31e45);
- the tools and packages: the package survey's extracted packages and
  PE imports, R 4.6.1's sources (rcmdfn.c, Rprofile.windows,
  sotools.R, packages2.R, install.R), msys2-runtime 3.6.1's
  `cygheap.cc` and `mount.cc`;
- the user's goals (R simple and uniform on every OS; one toolchain;
  minimal makefiles and shell; the same boundaries on conda, PyPI and
  standalone) and decisions (B11, B25, B39, B43, round 1's decision 16,
  the build-number decision of 2026-10-19, the memory rules: decision
  menus, no commits, simplicity first, read result tables, self-review
  after rewrites).

Each point is tagged where it lands in the amended plan (Cr<n>). One
new probe ran (PP2: the B39-names-only set zipped, in
`probe/b39/`). Nothing in any worktree was written.

## Points and what changed

| point | kind | what was wrong or missing | what changed in the plan |
|---|---|---|---|
| Cr1 | simplicity, correctness | E (a) planned a zig step (`pixi run m2-licenses`: std.http, zstd, tar, the inner tarballs) to fetch the m2 licence texts. msys2-runtime's MSYS2 source archive holds a git clone, not a tarball; some inner upstream archives are bzip2 or lzip, which zig's std does not read; m2-ncurses and m2-gcc-libs already ship partial texts. A program would special-case most of the 17 packages for a run made once per pin move: code against the "minimal code" goal. The step also had to read win-64 records from pixi.lock on gamma, a second reader | E (a): the texts are taken once by hand into `zigbuild/toolchain/m2-licenses/<pkg>/` (VERSION, ORIGIN, a README with the per-package steps); no code but build.zig's fallback and its VERSION check. The zig step is kept as option (a2). Section 0's table, section 1's network bullet, step 2's changes and tests, section 3 (build.zig licences, m2-licenses, conda.zig), section 6, section 7, risk 4 follow |
| Cr2 | correctness | The plan copied conda's SPDX `license:` into SOURCES without noting that the source texts can say otherwise (msys2-runtime: Cygwin's LGPL-3.0 with its linking exception, where conda says GPL-3.0-or-later; m2-libintl: gettext's LGPL for libintl) | ORIGIN records any difference; `license:` stays conda-meta's; risk 4 and PLAN's record list it. Worded as expected, to be settled by the texts |
| Cr3 | correctness (tools) | verify-toolchain and step 1 ran `sh -c 'cygpath -m /'` through TC's sh. `cygpath.exe` is msys2-runtime's program, and `usr/bin` takes only `msys-2.0.dll` from that package, so it is not on that PATH | Both use bash's builtin `pwd -W` (`cd / && pwd -W`, `cd /tmp && pwd -W`); the comparison side uses the checking script's own MSYS `cygpath -m -l`. Not copying cygpath is recorded in section 12 |
| Cr4 | simplicity | O compared bash's version with SOURCES through a second normalisation (5.2.037.2 → 5.2.37), fragile for a check that adds nothing to "sh runs" | Only make's version is compared (MSYS's release dropped, as unix's make check); sh must run |
| Cr5 | correctness (code) | Step 2's conda test copied phase 6's conda-meta-only fake env. On Windows the binutils are `in_conda` copies whose files must exist in the env, so that env stops the build before it can show anything. Also, recipe.yaml's group-directory globs (`{zig,flang,openmp,usr,binutils}`, r-zig-slim's exclusion and its `not_exists`) did not get the new `etc` | The conda rule is checked in step 5's real conda-package (the log's toolchain line names `binutils/` only; `package_contents`). recipe.yaml's four globs gain `etc` |
| Cr6 | correctness (packages) | Step 1's CRAN set had Rmpfr and units with no libraries: Rmpfr needs gmp and mpfr, units udunits2 (the stress runs had them from the conda env). igraph's cleanup "without building it" was not a runnable step (igraph fails to compile on Windows anyway) | A scratch libraries env (freetype, fontconfig, libpng, zlib, gmp, mpfr, udunits2; no tool of B39's names) feeds Rmpfr, units and systemfonts; find and xargs under `--preclean` are covered by verify-bundle's btTools |
| Cr7 | correctness (R) | The Rprofile prototype used `R_PROFILE_USER`, which `--vanilla` skips | Step 1 runs that check without `--vanilla` |
| Cr8 | correctness (code) | Step 2's expected summary listed `usr/` with the tool packages first; build.zig prints packages in copy order, and `build()` appends a directory's copies before its trees, so the DLL packages and pkg-config's come first. Section 3 also called env.sh's order the `windows_dirs` order | The expected line follows copy order (copies, then trees); the `windows_dirs` remark says the order only sets the summary's |
| Cr9 | evidence | Open point C's size difference (B39's names only) was an estimate | PP2 measured it: 52 files, 19,216,248 bytes, zipped 9,537,393; C (b) says 5.7 MB less raw, 2.6 MB less zipped |
| Cr10 | the user's approval rule | F (a)'s re-lock was planned as `pixi lock` with no check of what else it moves | The lock's diff must add pkgconf's entries and change nothing else, else stop and report; the new sha256 is recorded on every host |
| Cr11 | correctness (R) | H (a)'s `UserNM` goes unquoted into `system()` in sotools.R: an R_HOME whose long form has a space would break R CMD check's symbol tables unless R gives R_HOME in its 8.3 form | Step 1 records `R.home()` and `UserNM` under `C:\r zig\` and whether the symbol tables are read; risk 10 says what follows if they are not |
| Cr12 | performance | J (a)'s double check was costed per call, not per install: install.R calls `R CMD config` several times before each configure.win | Step 1 measures the count and the time; risk 7 puts J (b) back to the user above one second per package |
| Cr13 | the memory rule "read result tables" | The stress dispatch's success was phrased as "give 38569895172's builders and results" | Its per-row table is read row by row and every non-ok row listed with its expect and cause |
| Cr14 | TODO coverage | TODO's "the same with Rtools or Git for Windows also on PATH ... and in a fresh conda env" was met for the standalone tree only | Step 5's by-hand conda run is repeated with Git's `usr\bin` appended |
| Cr15 | correctness | The libraries env's `Library/bin` was put on PATH "for the DLLs at load only", but install.R loads each package during the install | It is on PATH during the installs too; the plan checks it holds no tool of B39's names, so it cannot stand in for the group |
| Cr16 | correctness (records) | Section 1 named a `phase6-base.diff`, which does not exist | The baseline is `git diff` of the phase 6 worktree, made at step 0, plus its untracked files |
| Cr17 | assumption | The plan assumed kappa has Git for Windows | Recorded if present; the clash is required in CI (windows-latest always has Git's MSYS) |
| Cr18 | risk | No account of Defender scanning 140 new executables on their first start (a slow first configure.win, a slow first CI block) | Risk 13; step 1 measures cold and warm `R CMD sh -c true` |

Also corrected in passing: step 3's unix comparison is against step 0's
baseline build (step 2 builds no R); the per-host table follows Cr6 and
Cr12.

## Checked and found right (no change)

- The package set's closure: recomputed from the survey's PE imports
  for every file of the eight tool packages, not only B39's names: the
  same nine MSYS DLLs, nothing else outside the system; the copied set
  has no prefix placeholder (the only one in the m2 set is
  m2-filesystem's `etc/fstab`, which the plan writes instead of
  copying).
- msys2-runtime 3.6.1 strips `bin` and then `usr` from msys-2.0.dll's
  directory: with the DLL in `TC/usr/bin` the MSYS root is TC and
  `TC/etc/fstab` is read; `/bin` is automounted on `<root>/usr/bin`, so
  Makeconf's default `SHELL = /bin/sh` is TC's sh.
- rcmdfn.c processes etc/Rcmd_environ (line 265) and prepends
  `bin\x64` before the `config` branch (532-533), so J's check sees
  `TC/usr/bin` on PATH; `system()` returns cmd.exe's exit code, rzig's
  127.
- verify-toolchain.sh's records loop accepts `etc/` as planned: a
  SOURCES with no `package:` block asks for no `LICENSES/`, and its
  `file:` line makes fstab a checked file; the new `licenses:` line is
  ignored by its awk.
- env.sh's `group_dirs` is the only list package-standalone.sh,
  unpack-toolchain.sh, verify-bundle.sh's file-list check and
  compile-tree.sh read: adding `etc` needs no other script change.
- conda.zig's `recipeSources` reads the m2 recipes' list-valued `url:`
  (first mirror), so `usr/SOURCES` names both the MSYS2 binary package
  and its source archive; about.json's `extra.remote_url` and `sha`
  give the feedstock line.
- Rprofile.windows becomes library/base/R/Rprofile (build.zig
  3502-3506) and runs under `--vanilla`; R's installer build turns on
  the Rtools block in the same file, so I (a) is upstream's own
  mechanism with our directory; `R.home()` has `/` separators.
- packages2.R's parallel make (r-zig's patch 0006) and its
  compile-from-source decision ask `Sys.which("make")` in the session,
  which only I (a) makes find the group on Windows.
- The user's decisions: B11 (every tool from conda-forge; m2 where
  needed) holds, with the reasons for m2 make and m2 coreutils put to
  the user as A and B rather than decided; B25 (a) and its Rprofile
  question answered by I; B39's list unchanged unless the user takes G
  (b); decision 16's pkgconf name kept, with its lock change put to the
  user (F); the build number bumped in or right after phase 7's PR (N),
  publishing resumed by the user after the merge, as build.yaml's
  publish step says.
- Goals: one mechanism on every OS (R puts `TC/usr/bin` first in the
  session and under R CMD, as unix's etc/Renviron); no new makefile; the
  only new shell is test code in the existing verify scripts; conda
  depends on the packages the tree copies, and the names are the same on
  both channels (pkgconf included under F a).

## Not taken

Recorded in the plan's section 12: copying `cygpath.exe` (no caller
seen), pkgconf for both names (the channels would differ, and every
pkg-config row ran pkg-config 0.29.2), and J (b) chosen now (kept (a)
with a measured threshold).
