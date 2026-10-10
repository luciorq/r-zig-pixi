# fix-no-build-leftovers — no build-machine paths in R's compressed files, and stripped linux binaries (PR iii)

**Status (2026-10-10).** Branch fix-no-build-leftovers, from main
b490bdf (build 7 published, the stress suite merged). Implemented,
reviewed and tested, not committed. Tested on linux-64 (slim with both
zigs, minimal, full, the conda package), osx-arm64 (slim) and win-64
(see "Tested"). Not tested on osx-64, linux-aarch64, macOS full or the
openblas flavours. pixi.lock is unchanged (sha256
fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96).
The recipe's build number goes 7 → 8. Main is now 966d661 (PR #22
merged); this branch's diff applies to it without conflicts.

## What, and the user's answers

PR (iii) of feat-no-host-paths/PLAN.md's follow-up list. The user's
answers of 2026-10-08 (feat-standalone-toolchain/PLAN.md, "Answers of
2026-10-08"; the reply was "all ★" with exceptions, these two among
them), verbatim:

> * D1: Strip Linux debug info
> * D3: b - Fix it.

- D1 b (feat-no-host-paths/PLAN.md, record "Build-machine paths in R's
  files"): R's own linux binaries are stripped in every variant, as
  macOS's and minimal's already were. linkRoot goes.
- D3 b (feat-no-host-paths/PLAN.md, What remains 9): the base packages'
  compressed files name no build path. The plan was: change how the
  bootstrap installs the Rd objects, run its R from a neutral prefix,
  and add a check that reads the lazy-load databases. The first and the
  last are done as planned. A neutral prefix does not exist (below), so
  a bootstrap step makes R_HOME relative inside the code databases
  instead.

An investigation came first (the counts, the design, a proposed diff);
this implementation follows it, with one change (the rewrite step's
files, below). The investigation's scan script (scan-lazyload.R:
every .rdx entry, .rds and .rda of a tree, and the objects that name
given paths) stays in the workflow's scratch, not in the repo;
verify-tree's check is the repo's version of it.

## D1: R's linux binaries carry no debug info

Before: newCMod set `strip = false` for linux slim and full. linkRoot
then gave each of R's links (addSharedLib, bin/exec/R) a stripped root
module of its own, one empty C file importing R's module. zig builds
its runtime libraries (compiler_rt, libc_nonshared, libc++) with the
root module's strip, so those lost their DWARF, which named zig's lib
dir and global cache, while R's objects kept theirs (remapped by
filePathFlags). A module without C (libRblas, libRlapack: Fortran only)
was simply stripped.

Now newCMod sets `strip = true` on linux and macOS, in every variant;
Windows stays unset (its debug info goes to a .pdb in zig's cache,
which nothing installs). linkRoot, its empty C file (`Ctx.empty_c`)
and their comments are gone. This changes linux slim, full and the
openblas flavours; minimal and macOS were stripped already. zig then
compiles R's C without -g and links with a full strip: no .debug_*
sections and no .symtab. filePathFlags stays: `__FILE__`, OpenMP's
source locations and Windows' .pdb still need it (its comment says so
now). vendor-libs.sh's comment on minimal's stripping is updated.

linux-64 slim, the baseline (b490bdf) and this branch, built in the
same scratch copy, in bytes:

| | before | after |
|---|---:|---:|
| R's 16 binaries (bin/exec/R, every .so under R_HOME) | 20,663,448 | 8,319,432 |
| lib/libR.so | 11,842,672 | 3,508,112 |
| library/stats/libs/stats.so | 2,006,616 | 786,880 |
| library/graphics/libs/graphics.so | 982,544 | 263,720 |
| library/grDevices/libs/grDevices.so | 845,040 | 275,376 |
| modules/internet.so | 241,608 | 62,120 |
| modules/lapack.so | 179,480 | 42,920 |
| bin/exec/R | 7,112 | 4,816 |
| lib/libRblas.so, lib/libRlapack.so | 254,264; 2,654,784 | the same |
| R_HOME | 64,964,712 | 52,435,818 |
| the whole tree | 161,252,858 | 148,723,964 |
| the tree as .tar.gz (tar -czf, as package-standalone.sh) | 74,362,702 | 70,111,835 |

R's binaries with .debug_* sections: 14 → 0; with .symtab: 14 → 0.
The exported symbols (.dynsym: name, type, binding, visibility) are
the same in all 16. Side effects:
- OpenMP's source-location strings read `;unknown;unknown;0;0;;`
  instead of `;src/main/array.c;do_colsum;1931;26;;`, as on macOS and
  minimal already.
- gdb and perf see only the exported symbols in R's binaries.
- `__FILE__` is unchanged (`src/main/character.c:1806`).

## D3: build paths in R's compressed files

### Where they were

linux-64 slim, baseline tree (scan-lazyload.R; paths looked for: the
prefix, R's source dir, the env, the checkout, $HOME). 2,975 objects in
43 files named one:
- 14 help databases (help/<pkg>.rdb): 1,471 Rd objects and their 1,471
  srcfile environments. Each Rd object's `Rdfile` attribute and its
  srcfile's `filename` are `<src>/src/library/<pkg>/man/<f>.Rd`; its
  srcfile's `wd` is the checkout (the bootstrap's working directory).
- 14 help/paths.rds: every Rd file's absolute path.
- doc/NEWS.rds, NEWS.2.rds, NEWS.3.rds: `Rdfile` and `filename` are
  `<src>/doc/NEWS*.Rd`, `wd` is `<prefix>/lib/R/doc`.
- 12 code databases: 16 entries with 19 strings, all the install
  prefix. base's `.Library`, `.popath` and `.lib.loc` (the
  `.libPaths()` closure); the namespace `path` of compiler, grDevices,
  graphics, grid, parallel, splines, stats, stats4, tools and utils;
  methods' namespace info (its `path` and its DLL's path); the frame of
  methods' `...onLoad` (`libname`, `dbbase`), in methods.rdb and again
  in stats4.rdb. (What remains 9 said "42 objects": it counted the
  entries that reach these environments; here each string is counted
  where it is stored.)
- sysdata.rdb, Rdata.rdb and Meta/*.rds named nothing.

Upstream records the same: conda-forge's r-base 4.6.1 (h502d0c9_1,
upstream's configure and make) has the same kinds, plus tools'
`.R_top_srcdir_*`, which this project already removed with top.txt.
So did the published r-zig-slim: builds 4 (rattler's cache) and 7
(the channel's current one) for linux-64 name GitHub's
`/home/runner/work/.../rattler-build_r-zig/work` and rattler's host
prefix in the same 43 files (26 .rdx, 14 paths.rds, 3 NEWS*.rds). conda's prefix replacement cannot reach a path inside
compressed data.

### Why R records them (R 4.6.1's source)

- `parse_Rd` always attaches `srcfile(file)`, which keeps the file name
  and `getwd()` (its keep.source test is commented out in parseRd.R).
  `prepare_Rd` copies the file name into the `Rdfile` attribute.
  `.install_package_Rd_objects` makes the man dir absolute
  (`file_path_as_absolute`) and saves those names in paths.rds, with
  `first = nchar(mandir) + 2`.
- The code databases keep where R ran. The profile sets `.Library` and
  `.popath` and calls `.libPaths()` before makebasedb.R saves base.
  loadNamespace's makeNamespace stores `normalizePath(lib/name)`
  ("this should be an absolute path"). methods' `...onLoad` assigns
  `.methodsNamespace <- new.env()`, whose parent is the `...onLoad`
  frame; refClass.R keeps it as envRefClass's
  `refMethods$.objectParent`, so the frame (`libname`, `dbbase`, `ns`,
  ...) is saved with methods and with stats4.

### The fix (build.zig's bootstrap)

1. "install parsed Rd" takes the steps of
   `tools:::.install_package_Rd_objects` (`.build_Rd_db`, paths.rds,
   `makeLazyLoadDB`), run in R's source tree with relative file names.
   Each Rd object names `src/library/base/man/abbreviate.Rd`, the form
   `__FILE__` has (`src/main/character.c`), and its srcfile's `wd` is
   ".". paths.rds holds the same names, with `first =
   nchar("src/library/<pkg>/man") + 2`, so `substring(paths, first)`
   still gives `abbreviate.Rd` (and `unix/Signals.Rd`). The
   function's up-to-date test is left out: library/ is new on every
   build. No base package has man/macros.
2. "doc NEWS" parses `doc/NEWS*.Rd` in R's source tree, with `wd` ".".
   The macros are R_HOME's share/Rd/macros/system.Rd, as before
   (`parse_Rd`'s default). It writes the same files.
3. A new last step, "relative R_HOME in code DBs". For every .rdx under
   library/ it fetches every entry. An entry that names R_HOME (as
   build.zig gives it, as `R.home()`, or as `normalizePath(R.home())`)
   is written again with R_HOME-relative paths; R_HOME itself becomes
   ".". It rewrites character vectors, lists and attributes, and a
   forced promise becomes its value. Every other entry is copied byte
   for byte. The step stops if a rewritten entry still names R_HOME.
   It writes `<db>.rdb.new` and `<db>.rdx.new` and renames them over
   the old files only at the end. R reads its namespaces' code from
   these files while it runs, and keeps each .rdb it has read in
   memory by name; a namespace first loaded after its files changed
   would read the old bytes at the new offsets. (The investigation's
   version rewrote each database in place; it worked because each
   package's namespace was loaded while its own entries were fetched,
   but nothing guaranteed that.)

The rewritten values: `.Library` "library", `.popath`
"library/translations", `.lib.loc` "library", a namespace's `path`
"library/stats", methods' DLL "library/methods/libs/methods.so",
`dbbase` "library/methods/R/methods", `libname` "library". What R does
with them: it sets `.Library`, `.popath` and `.libPaths()` again when it
starts; it sets a namespace's path and DLL path again when it loads one
(nspackloader.R lazy-loads with `filter n != ".__NAMESPACE__."`).
methods' frame is
`parent.env(getClass("envRefClass")@refMethods$.objectParent)`, and it
is in the scope of a bare envRefClass object: code run in
`as.environment(new("envRefClass"))` finds `dbbase` and `libname` (the
build machine's paths before, the relative ones now; the review
checked both trees). Objects of classes made with `setRefClass` have
another parent and do not see them. Nothing in R reads them. On a copy
of the new tree moved elsewhere, `getNamespaceInfo("stats", "path")` and methods' DLL
path name the moved tree, `setRefClass` and stats4's `mle` work, help's
messages still say `abbreviate.Rd:14: ...`, `news()` reads NEWS.rds,
and `help.search` and Rd2HTML work.

The investigation ran the step's code (in place, otherwise the same) on
a copy of the baseline tree: exactly the 16 entries changed, and the
other 9,927 kept their bytes. Between the baseline build and this
branch's, 18 of the 7,001 code-DB entries differ: the same 16, and
methods' two with a build-time `dateCreated` (below). Writing every
entry again would not keep the bytes: the investigation's first
version did, and namespace references came out the same objects with
other bytes (tools' held a 15-string spec, written again a 2-string
one).

### Why not a neutral prefix

- R resolves R_HOME and its library paths to their real directory
  (`normalizePath` in loadNamespace and `.libPaths`), so any prefix R
  runs from is a real directory of the build machine.
- A fixed directory such as /tmp/x would be per machine, would collide
  between builds running at once, is /private/tmp on macOS, and needs a
  drive on Windows.
- R has no option that leaves srcrefs off Rd objects (above).
  `R_KEEP_PKG_SOURCE` and `keep.source.pkgs` only affect R code, and
  base's code databases carry no srcrefs anyway (unless the building
  shell sets `R_KEEP_PKG_SOURCE=yes`: "Not fixed"). Dropping the Rd
  srcrefs would also lose the line numbers in help's messages.
- Fixes at the R level, one per kind, take four mechanisms:
  `set.install.dir` for 10 namespace paths; a prelude for base's
  `.Library`, `.popath` and `.lib.loc`; the working directory and
  `lib.loc` for methods' frame; and methods' own namespace path would
  still need an R patch (its `...onLoad` calls makeLazyLoadDB without
  `set.install.dir`). One rewrite step covers them all, and its own
  test (no entry names R_HOME) and verify-tree's check catch any new
  kind.

### The check

scripts/verify-tree.sh, in its build-path block (every OS, a tree that
is not a conda env), runs the tree's own Rscript (Windows:
R_HOME/bin/x64/Rscript.exe, with C:/ paths from `cygpath -m`) on
scripts/uncompress-r-objects.R. That writes each .rdx (every entry;
environments as empty stand-ins) and each .rds under R_HOME out
uncompressed under `$WORK/serialized`, and the same ERE as the byte
search reads those files. An offender prints as
`lib/R/library/stats/R/stats.rdx (its objects, uncompressed): <first
match>`; the summary says how many files were read uncompressed (157
on slim). The tree's own place (the install prefix, when it is not in
the checkout) is now one of the paths it looks for, beside the
checkout, zig's caches, the env and $HOME; the Makeconf check already
looked for it. verify-tree takes about 19 s on slim, its R run
included.

On the baseline slim tree the new verify-tree fails and names the 43
files: 12 code databases, 14 help databases, 14 paths.rds and 3
NEWS*.rds.

## The conda package: build number 7 → 8

feat-standalone-toolchain PLAN.md, B14 (a): "each later PR that
changes a conda package's files or dependencies bumps again". This PR
changes r-zig-slim's files:
- linux-64 and linux-aarch64: libR.so and every other binary of R's own
  lose their DWARF and symbol table (libR.so about 11.8 → 3.5 MB).
- every platform: the help databases, help/paths.rds, doc/NEWS*.rds and
  the code databases hold relative paths instead of rattler's work dir
  and host prefix.

This branch does not change r-zig-toolchain's files (rzig is not
touched), but both outputs come from one build and share the build
number. No dependency changes.

PR #22 (feat-standalone-phase2) merged into main as 966d661 on
2026-10-10. It does not touch recipe.yaml (B14: phases 2 and 3 take no
bump), so 8 does not collide. It touches build.zig and verify-tree.sh in
other places: this branch's diff applies to 966d661's files with
`git apply --check`, only moved by a few lines. One consequence for the
user to weigh: once main is merged in, build 8's r-zig-toolchain also
carries phase 2's rzig (toolchain groups, the check mode). B14 planned
those changes to publish with phase 4's bump; build 8 would publish
them first.

## Not fixed (found on the way)

- The trees are not fully reproducible. methods.rdb's
  `.__C__sourceEnvironment` and the envRefClass prototype carry a
  build-time POSIXct `dateCreated`; tools' Rd2HTML help page holds an
  install-time timestamp (a `\Sexpr`); DESCRIPTION and
  Meta/package.rds carry the Built time (known, utcNow).
- verify-tree's `first_match` can print a backslash before a path found
  in a serialized file: the separator class `[/\\]+` takes a 0x5c byte
  just before it. Cosmetic.
- slim and full still ship the env's libraries with their debug info
  (linux tester): 12 vendored libraries, libstdc++.so.6 alone has
  20.4 MB of .debug_* in 23.9 MB. D1 covers R's own binaries;
  vendor-libs.sh strips the vendored ones only for minimal. As before
  this branch. Whether D1 should cover them too is the user's call.
- verify-tree looks only for this machine's paths, so a tree built
  elsewhere passes it (a downloaded conda package, a copy of another
  checkout's tree). The conda packages were scanned by hand (Tested).
- verify-tree has no Windows short (8.3) names in its path list (kappa).
  A leak written `C:/RZ6-OU~1/R-46~1.1-S/...` passed on kappa, from a
  tree copied to `C:\rz6-outside`, where no other path in the list
  covered it. It does not matter on CI (D: has no short names) or in a
  checkout whose own path has no short form. As before this branch (the
  byte search had the same list). A one-line fix, `cygpath -m -s` beside
  `cygpath -m -l` in path_forms, caught it there and kept the clean tree
  passing; not applied here.
- The bootstrap passes the caller's environment to R. With
  `R_KEEP_PKG_SOURCE=yes` in the shell that builds (`--vanilla` skips
  ~/.Renviron, not the environment), the base packages keep their source
  in their code databases. makeLazyLoadDB then indexes each srcfile as
  a list of keys (its bindings, and its lines apart), not as one
  offset and length, and the "relative R_HOME in code DBs" step stops
  with `bad offset/length argument`. b490bdf has no such step, so it
  would ship those sources instead (not built here). Setting
  `R_KEEP_PKG_SOURCE=no` in Boot.r (one line, beside TZ and LC_ALL)
  fixes it. Both builds are in "Tested" (the review); the line is
  proposed, not applied here.
- The rewrite step and the check load each namespace an entry refers
  to, so in full they load tcltk. From R's tcltk.c, on unix without
  `HAVE_AQUA` (macOS full builds X11 Tk), Tk starts only when DISPLAY is
  set: without one it warns, and the warning is suppressed; with one
  (a desktop, XQuartz on a Mac) Tk connects to that display.
  `R_DONT_USE_TK=1` for those two R runs would skip Tk; not applied.

## Tested

All on 2026-10-10, with `pixi run --locked`; pixi.lock (sha256
fbb64b7b...) was unchanged on every host. Every tester ran the same
code: before the review, build.zig, scripts/verify-tree.sh and
scripts/uncompress-r-objects.R were byte for byte the implementer's
tested copies, and the linux, omicron and kappa testers saw the same
`git diff` (sha256 8007ec33...dfab) at their start and end. The review
then changed only comments and docs (verify-tree.sh's header comment
and the two PLAN.md files).

### linux-64, the implementer (a scratch copy on another disk)

conda-forge's zig 0.16.0. The baseline is b490bdf's build.zig,
verify-tree.sh and vendor-libs.sh in the same copy, built first, so
both trees name the same build paths.
- slim: build (2 min 25 s), verify-tree (1,892 files of R's own, 157
  read uncompressed, none naming a build path; 49 vendored, the same 9
  naming the env as before), smoke, contract (Rcpp, data.table, minqa,
  quadprog, pak, ps), check (one NOTE, tools-Ex, as before: grid.Rnw's
  vignette title), hermetic, verify-package (the archive: 70,102,491
  bytes).
- The new verify-tree on the baseline slim tree fails, naming the 43
  files (12 code DBs, 14 help DBs, 14 paths.rds, 3 NEWS*.rds).
- scan-lazyload.R: the baseline tree, 2,975 objects in 43 files; this
  branch's slim, minimal and full trees, 0 (9,943 entries in 29
  databases; full 10,245 in 30). All 1,471 Rd objects: no path in
  `Rdfile`, srcfile `filename` or `wd`.
- minimal: build, verify-tree (1,380 files of R's own, 157 read
  uncompressed).
- full (no DISPLAY): build, verify-tree (2,296 files of R's own, 158
  read uncompressed), smoke. The rewrite step and the check load tcltk
  while fetching its entries; neither printed a warning (both suppress
  them).
- Binaries: the table above for slim. minimal's libR.so 3,502,336
  bytes, full's 3,543,448; no binary of R's own in any variant has a
  .debug_* section or a .symtab.
- The two slim builds' databases, entry by entry (raw bytes): 18 of the
  7,001 code-DB entries differ, the 16 rewritten ones and methods' two
  with a build-time `dateCreated`; all 2,942 help-DB entries differ
  (their file names).
- Help text: every one of the 1,471 base help pages rendered with
  `tools::Rd2txt`, on copies of both trees moved elsewhere: the same
  text, except tools' Rd2HTML page (its build timestamp).
- On the moved copy of the new tree (`env -i`): `.Library`,
  `.libPaths()`, `getNamespaceInfo("stats", "path")` and methods' DLL
  path name the moved tree; `setRefClass`, `methods::new("envRefClass")`
  and stats4's `mle` work; `utils:::.getHelpFile` gives `Rdfile` and
  srcfile `src/library/base/man/abbreviate.Rd`, `wd` "."; `Rd2txt`,
  `Rd2HTML`, `tools::Rd_db`, `checkRd`, `help.search` and
  `news(Version == "4.6.1")` work; `tools:::stopRd` says
  `abbreviate.Rd:14: test message`.
- The conda packages (`pixi run -e pkg conda-package`, 4 min 26 s; the
  copy's recipe still said 7, so they came out as `_7`): both outputs'
  tests passed. r-zig-slim's libR.so is 3,508,112 bytes with no
  .debug_* and no .symtab (the published build 4: 11,842,672, with
  DWARF). Its 157 .rdx and .rds files, read uncompressed, name neither
  rattler's work dir nor its host prefix, nor $HOME (published build 4:
  43 files naming `/home/runner/work/...`).
- `zig fmt --check build.zig`, `bash -n scripts/verify-tree.sh`, `git
  diff --check`.

### linux-64, the tester (this worktree)

- rzig-test: 60 identical, 58 identical but for rzig's own environment
  (-L or a compiled object), 22 deliberate differences, 0 failed.
- slim: build (2 min 54 s), verify-tree (1,892 files of R's own, 157
  read uncompressed, none naming a build path), smoke, contract, check
  (the one tools-Ex NOTE), hermetic, verify-package (the archive:
  70,094,190 bytes).
- minimal: build, verify-tree (1,380 files, 157 read uncompressed),
  verify-package. full (no DISPLAY): build, verify-tree (2,296 files,
  158 read uncompressed), smoke; messages translated (de, fr) when the
  working directory holds a fake library/translations.
- slim with upstream zig (PyPI ziglang 0.16.0, fetch-zig): build,
  verify-tree, smoke. libR.so 3,507,832 bytes, no debug info.
- conda-package: r-zig-slim-4.6.1-hb0f4dca_8 and
  r-zig-toolchain-4.6.1-hc48ad4c_8, both outputs' tests passed.
  Installed with micromamba (this channel and conda-forge): its 157
  files and 9,943 entries name none of the worktree, rattler's work dir
  and host prefix, $HOME, /home/runner or .pixi. R's binaries have no
  debug info and no .symtab.
- Planted paths, in a copy of slim outside the checkout: a compressed
  splines.rdb entry naming the checkout's R source (no match in the raw
  bytes); $HOME in stats' help database, the env in doc/NEWS.rds, the
  copy's own place in utils/Meta/Rd.rds. verify-tree fails naming
  exactly those files. An unmodified copy in the same place passes.
- The new verify-tree on a copy of the main checkout's older slim tree
  (built Oct 9): fails naming the 43 files.
- Code databases of that older tree and the new slim, raw bytes per
  entry: 18 of 6,893 entries differ (the 16 rewritten, methods' two
  `dateCreated`), with the same keys. The exported symbols of all 16
  binaries are the same. doc/NEWS and doc/html/NEWS.html are
  byte-identical.
- help(lm) as text (266 lines, the same as the old tree's),
  `tools::Rd_db("base")` (446 objects), example(lm) and example(glm),
  Rd2txt of all 1,471 base pages (the same but tools' Rd2HTML page),
  the dynamic help server, help.search, checkRd, news(), setRefClass,
  stats4's mle. In a moved copy started from a directory that holds a
  fake library/stats, library/translations and library/methods, every
  path R uses names the moved tree.

### osx-arm64, omicron (a copy of this worktree)

- rzig-test: 74 of 74. slim: build (1 min 52 s, the new step ran
  clean), verify-tree (1,894 files of R's own, 157 read uncompressed,
  none naming a build path), smoke, contract, verify-package (the
  archive: 57,021,443 bytes).
- A tree built in the same copy from b490bdf's build.zig: the new
  verify-tree fails naming 43 files (12 code DBs, 14 help DBs, 14
  paths.rds, 3 NEWS*.rds).
- D1 changes nothing on macOS: all 16 of R's binaries are
  byte-identical to that baseline build's.
- Under `env -i`, on the built tree and on a copy unpacked from the
  archive elsewhere: help(lm), example(lm), `.libPaths()`, the stats
  namespace path, methods' DLL, setRefClass, mle, news(), stopRd
  (`abbreviate.Rd:8: test message`), paths.rds' `first`.
- macOS slim has tcltk's help database but no tcltk code database, so
  tcltk's namespace was not loaded there.

### win-64, kappa (a copy of this worktree, built from scratch)

- rzig-test (54 passed, 20 skipped), build (7 min 47 s), verify-tree
  (2,907 files of R's own, 158 read uncompressed, none naming a build
  path; tcltk's entries load with no warning), smoke, contract, check
  (the same tools-Ex and stats-Ex NOTEs as main's Windows CI for
  b490bdf), verify-package (the zip: 66 MB).
- Planted paths in 5 compressed files of a tree copy: backslashes,
  doubled backslashes, a lowercase `c:/`, $USERPROFILE's AppData, and
  an entry of a new lazy-load database. No match in the raw bytes;
  verify-tree fails naming the 5.
- A copy of the tree outside the checkout passes. Its own long path,
  planted in an .rds, fails. Its 8.3 short path does not ("Not fixed").
- The r-zig-slim _7 built on kappa on 2026-10-09 (rattler's cache, not
  the published one): 44 of its 158 files name its work dir and host
  prefix (`C:/Users/admin/rz3-fix/...`). The new tree: 0.
- help(lm), example(lm), stopRd, news() (1,366 rows), help.search,
  setRefClass and mle, on the installed tree and on a moved copy run
  with PATH set to its bin\x64 and System32 only.

### The review (linux-64)

- The published build 7 for linux-64, from the channel: libR.so
  11,842,672 bytes with DWARF. uncompress-r-objects.R finds GitHub's
  work dir and rattler's host prefix in 43 files (12 code DBs, 14 help
  DBs, 14 paths.rds, 3 NEWS*.rds), none of them in the raw bytes.
- readelf over every ELF file of slim, minimal and full: R's own
  (bin/exec/R, every .so under R_HOME, the toolchain's copies of rzig)
  have no .debug_* section and no .symtab. Only the env's libraries
  have them (and minimal's copy of the env's make keeps a .symtab).
- In every .rdx of slim, full and the published build 7, the entries
  listed cover the .rdb byte for byte, so the rewrite step leaves no
  entry behind in these trees.
- A small package whose Rd links to stats, base and methods topics:
  `R CMD build` and `R CMD check --no-manual` with the new slim tree,
  Status OK. A sourced user script with keep.source has the same
  srcref in the old and the new tree; base and stats functions have no
  srcref in either.
- `evalq(dbbase, as.environment(new("envRefClass")))`: the
  implementer's baseline tree gives its build prefix's
  library/methods/R/methods, the new tree `library/methods/R/methods`.
  A `setRefClass` object does not see `dbbase` in either.
- The branch's diff applies to main 966d661's files (`git apply
  --check`).
- `R_KEEP_PKG_SOURCE=yes` in the shell that builds (a scratch copy):
  the build fails at "relative R_HOME in code DBs" with `bad
  offset/length argument`; 11 code databases kept their source. With
  `R_KEEP_PKG_SOURCE=no` set in Boot.r (the proposed line), the same
  build passes (2 min 25 s), keeps no source (stats.rdb the same size
  as the default build's) and verify-tree passes.

## Not tested

osx-64, linux-aarch64, macOS full and minimal, the openblas flavours,
upstream zig on macOS and Windows and for minimal, the wheel, the conda
package on macOS and Windows, check on macOS, hermetic on macOS and
Windows. tcltk's namespace is loaded by
the rewrite step and the check only in full: tested on linux (no
display) and Windows, not on macOS. CI's default tier runs slim on
osx-arm64, osx-64 and linux-aarch64; the `full-ci` label adds full on
the four unix legs, the openblas flavours and minimal on the other
three.

## After the review (2026-10-10)

The review's three diffs are applied:
- The bootstrap sets R_KEEP_PKG_SOURCE=no: with R_KEEP_PKG_SOURCE=yes
  in the caller's shell, base packages kept their source and the rewrite
  step stopped ("bad offset/length argument").
- verify-tree's path forms include Windows 8.3 short names (kappa's
  diff, tested there).
- The bootstrap and verify-tree's database read set R_DONT_USE_TK=1, so
  loading tcltk in full opens no display and warns about none.

Re-run on linux-64 after them, lock fbb64b7b unchanged: build and
verify-tree (slim); a build with R_KEEP_PKG_SOURCE=yes in the
environment, then verify-tree (passes); full build and verify-tree with
DISPLAY=:99 (passes, no Tk message; 158 files read uncompressed, no
build path). Not re-run on the hosts: the 8.3 diff is kappa's own tested
change; the other two do not change what the hosts tested.

## The user's answers to the review's open points (2026-10-10)

"Apply all recommended.":
- Build 8 also publishes phase 2's rzig (PR #22, merged before this
  branch): accepted. B14 had planned it for phase 4's bump; phase 2's
  conda tests passed (test-toolchain.R with the env's zig and flang).
- The vendored conda libraries are stripped too, in every linux flavor:
  scripts/vendor-libs.sh runs `strip --strip-debug` on each one, as it
  did for minimal only (symbol tables kept). Tested on linux-64 (lock
  fbb64b7b): slim build, verify-tree, smoke, contract, hermetic,
  verify-package; full build, verify-tree, smoke. The slim tree's lib/
  went from 148,499,258 to 126,896,734 bytes, and no vendored library
  has a .debug_* section. macOS and Windows are unchanged.

