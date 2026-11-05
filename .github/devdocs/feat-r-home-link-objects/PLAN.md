# feat-r-home-link-objects — rzig's link objects ship in R_HOME

**Status (2026-10-23).** Worktree `wt/feat-r-home-link-objects`, branch
feat-r-home-link-objects at main d11dee1. It carries feat-tier1-engine
(PR 1) and the queue under it, uncommitted. This layer is on top. The
Zig part, the harnesses and these records are done. Tested on gamma
(linux-64) and kappa (win-64), each with both zigs ("Tested"). A review
of this layer found 5 points; 4 are fixed and 1 is recorded ("Review").
omicron and CI are still to run. Not committed: the user commits. pixi.lock is main's, unchanged,
sha256 fbb64b7ba4e31e45bb18dbd0868a96aa5b0939ee291e0dddeeba2dd09a68bb96.
No dependency change and no build-number bump.

PR 1's state this layer starts from (the handover diffs against it):
- `git -C wt/feat-tier1-engine diff`, sha256
  182b51172a74f8b6ebd5e19f16f95338bfb59d897335ddf8f2c9f64908de5a8a (97
  status entries);
- the sha256 list of its 91 untracked files, sha256
  d2d0f65df31a292a81a50b65431f186a6912148c8188927e782e77650dae8225
  (eece97eaa717e18fb739f4b6517f3de41cb479e057af259910dcb98f446a1ffe
  when tested; only PR 1's PLAN.md changed since, records only).

Both are in the scratch directory
`/data/gamma/luciorq/workspaces/temp/r-zig-pixi/t1e/pr2/` (below:
`t1e/pr2/`), with the measurements (`RESULTS.md`, `NOTES.md`).

## Why

feat-tier1-engine decision 4 (A): a follow-up PR that ships `dso_fini.o`
(linux) and `cfguard.o` (Windows) in R_HOME, prototyped and measured
first. Until now rzig compiled each one at link time into its own cache
(`cache.compiled`):
- `<cache>/dso-fini-<key>/dso_fini.o` (dso_fini.zig, stress round 1 Z9);
- `<cache>/cfguard-<key>/guard_dispatch.o` (cfguard.zig, stress round 2
  Z11).

That cost three things:
- **A `zig version` spawn at every such link.** The key held what `zig
  version` said and the zig command. After PR 1 it was the last one in a
  package install (cr27 finding 8).
- **Trust.** rzig linked a file from its cache into every package. A
  planted dso_fini.o's constructor ran (cr27 g1 probe 6; the residual of
  finding 1). This PR closes that for the link objects only. The same
  class stays for rzig's two other kinds of entry, which are rarer:
  archives.zig links any `archive-<key>/<name>.a` that exists (a package
  that passes an archive without a `.a` name), and libcxx_mirror.zig
  takes any `zig-lib-<key>` with its `.complete` file as ZIG_LIB_DIR (a
  zig with libc++ beside it). Neither checks the entry's owner or
  content.
- **A Windows race.** A reader could fail to open cfguard's object while
  another job renamed over it (feat-tier1-engine, kappa's F1: 14 of
  192,000 opens in a probe).

## The design

### What the objects are and what they depend on

- **dso_fini.o** is crtbeginS.o's part that a zig link of a linux shared
  library lacks: a `.fini_array` entry that calls `__cxa_finalize` with
  the library's `__dso_handle`. Without it, glibc runs a C++ static
  destructor at exit, after dlclose: R segfaults at exit (Z9).
- **cfguard.o** is mingw-w64-crt's `guard_dispatch.S`, which zig's MinGW
  runtime leaves out. Without it, a link of code compiled with Control
  Flow Guard stops at `undefined symbol: __guard_dispatch_icall_dummy`
  (Z11). It is x86_64 code.
- Both are compiled with `zig cc -target <t> -mcpu=baseline
  -fno-sanitize=undefined -O2 -g0 [-fPIC] -c`. They depend on the target
  (the architecture; the glibc floor 2.17 changes nothing in an object)
  and on those flags.
- **They do not depend on the zig.** The key held `zig version` and the
  zig command only so that a new zig made a new object. Measured
  (`t1e/pr2/proto/`):
  - conda-forge's and upstream's zig 0.16.0 give the same bytes except
    `.comment`'s clang version (21.1.8 conda-forge, 21.1.0 upstream).
    With `.comment` removed the objects are identical. cfguard.o has no
    `.comment` and is identical.
  - Each zig links the other's object: a C++ library with a static
    destructor, dlopened and dlclosed, exits 0 with either object and
    segfaults (139) with none, for both zigs. A `-mguard=cf` DLL links
    with either cfguard.o and both zigs (cross-built on gamma), fails
    without one, and does not export `__guard_dispatch_icall_dummy`.
  - The object names its source by its base name only (`STT_FILE
    dso_fini.c`): no build path.

### Where they go: R_HOME/bin/toolchain, beside rzig

`TC/dso_fini.o` on linux and `TC/cfguard.o` on Windows (TC is
R_HOME/bin/toolchain). Nothing on macOS. Reasons:
- **rzig finds it from its own path.** A compile never reads R_HOME or
  CONDA_PREFIX (environment.zig). rzig already finds its environment and
  the groups from its own directory (`environment.toolchain`). So the
  lookup is `<rzig's directory>/<file>`: no path arithmetic, no variable.
- **It is the base's.** rzig is part of R and ships in the base on every
  channel. TC's own files are the base's, and the groups are TC's
  subdirectories (feat-standalone-toolchain B19, B30). The object is
  rzig's own, built from rzig's sources for R's target. It is no
  third-party compile-time file, so it is not a group's.
- **Every layout has it beside rzig.** The base archive, r-zig-slim and
  the wheel copy TC's files. rzig's own build.zig installs it into
  `zig-out/bin` beside rzig, so the harnesses that build rzig alone
  (parity-test.sh, smoke-test.sh) get it too.
- **Rejected:** R_HOME/lib (libR's directory on unix; Windows R_HOME has
  none, and rzig would need R_HOME), share/zig/rpkg (tier 2's zig build
  root, not link inputs), a `TC/lib/` (it reads as a group's directory).

### Who builds it

rzig's build.zig, `linkObject`: a system command, `zig cc` with the
flags above, for the target rzig is built for. The sources are files now,
`zigbuild/tools/rzig/dso_fini.c` and `cfguard.S` (they were string
constants). Both build.zigs install the object beside rzig: the repo's in
`installRzig`, rzig's own in its install step.
- The command is the one rzig ran into its cache, so the object's bytes
  are the same. The build's zig compiles it: conda-forge's in CI and the
  conda recipe, upstream's in a `ZIG_BIN` build.
- cfguard.o only for an x86_64 Windows target. rzig built for another
  Windows architecture (aarch64-windows-gnu, cross-built only) adds no
  stub (compiler.zig): an x86_64 object cannot link into an ARM64 image.
  Before this PR it would have tried.

### When the file is missing: a warning, no fallback

rzig warns once per link and links without it:
`zig-cc: warning: no <TC>/dso_fini.o: this library's static destructors
may run after it is unloaded`. This is what it did when the cache could
not make the object. Reasons:
- rzig and the object come from one build and one install step. A tree
  with rzig and no object is broken, or rzig was copied alone.
- A fallback to the cache keeps all three costs above for exactly the
  broken case, and keeps `cache.compiled` with its key, its renames, its
  tests and its Windows race.
- Failing the link is the other choice. In a broken install it would
  stop every link, including the many that need no object (a library
  with no C++ static, a Windows link with no CFG code).
- A tree built before this PR has no object. rzig ships with its tree, so
  an old tree has the old rzig. Only a newer rzig copied into an old tree
  warns.

When rzig does not know its own path (the OS would not say), it adds
nothing and says nothing, as before with no zig.

## Changes

- `zigbuild/tools/rzig/build.zig`: `linkObject`, `LinkObject`,
  `Artifacts.object`; the install step installs the object.
- `build.zig`: Ctx's `rzig_object`; `installRzig` installs it into TC.
- `zigbuild/tools/rzig/dso_fini.c`, `cfguard.S` (new): the sources.
- `dso_fini.zig`, `cfguard.zig`: `file` and `consequence`; the source
  strings, `object()` and the cache tests are gone; the header comments
  say where the object comes from.
- `compiler.zig`: `linkObject` (the lookup and the warning); cfguard
  only on x86_64. Tests: the objects beside rzig (they now run on a
  Windows host too: no shell stand-in, and on any architecture, with no
  stub off x86_64), a new test for a missing object.
- `cache.zig`: `compiled`, `make`, `key` and `command` deleted (with
  their tests). The cache holds the archive copies and the libc++ mirror.
  PR 1's graft 3 (the rename tolerance in `make`) goes with `make`.
- `fortran.zig`: the zig-fc link test expects the object.
- `main.zig`: RZIG_TRACE prints one more line before the command,
  `cache <dir>`, rzig's cache (cache.zig's root; `(none)` without one).
  The harnesses compare it with the directory they check (below).
- `Ctx.zig`, `windows.zig`: comments.
- `parity-test.sh`: the fake trees get the objects beside rzig (the real
  ones from rzig's build, else empty files for the dry runs); `obj_re`
  matches `.../lib/R/bin/toolchain/{dso_fini,cfguard}.o`; cfguard is
  expected on an x86_64 host only; the dso_fini case checks that rzig's
  cache stays empty; a new real check: tier 1's link names the tree's
  dso_fini.o, the library has a `.fini_array`, and rzig's cache has no
  dso-fini-*; the tier-1 check reads its cache only after the trace
  names that directory.
- `smoke-test.sh`: copies dso_fini.o beside its rzig copies.
- `scripts/verify-helpers.sh`: `link_object` (the file name per OS) and
  `link_object_named <log>` (a traced link names it). `rzig_cache_odd`
  now counts dso-fini-* and cfguard-* as odd. Its "no dso-fini-*"
  liveness line is gone: a link leaves nothing in the cache now. Its
  new second argument, a traced log, replaces it: the function also
  prints each `cache` line of the log that names another directory, and
  `no cache line` when there is none (decision 5).
- `scripts/pkg-parity.sh`: `no_runner` also checks `link_object_named`
  and gives `rzig_cache_odd` each traced log (R CMD SHLIB's too, the
  probe's rzig run); `argv_of` leaves the `cache` lines out.
- `scripts/verify-bundle.sh`: the base archive holds the object and
  nothing else beside rzig; pfC's traced link names it, and its trace
  names the cache the step reads.
- `scripts/verify-tree.sh`: TC holds rzig and the object; the object is
  an ELF (linux) or x86-64 COFF (Windows) file.
- `scripts/make-wheel.py`, `scripts/wheel-test.sh`: dso_fini.o is the
  base's on linux; wheel-test's count leaves the `cache` lines out.
- `README.md`, `pixi.toml`, `scripts/hermetic-check.sh`,
  `scripts/verify-tree.sh`: the texts that said TC holds rzig alone name
  the link object too.
- `recipe/recipe.yaml` (r-zig-slim's `package_contents`, a comment) and
  `recipe/test-preflight.R`: the object in the file lists. No dependency
  change.
- Comments: `scripts/contract-test.sh`, `stress/stress.R`,
  `stress/README.md`.

## Measurements

gamma, linux-64, 16 CPUs. **cf** is conda-forge zig 0.16.0, **up** is
upstream zig 0.16.0 (PyPI ziglang). **PR 1** is PR 1's cf-built tree
(`t1e/test-gamma/r2/trees/new`, copied); **this PR** is this layer's
compile tree. Details and logs: `t1e/pr2/RESULTS.md`.

strace of an install of tinyc after two installs (`execve`, `openat`).
**warm:** every cache warm. **first:** rzig's cache emptied, zig's warm.

| tree | zig | mode | execve | `zig version` | `zig cc dso_fini.c` | rzig's cache after |
|---|---|---|---|---|---|---|
| PR 1 | cf | warm | 39 | 1 | 0 | dso-fini-<key> |
| PR 1 | cf | first | 41 | 1 | 1 | dso-fini-<key> |
| PR 1 | up | warm | 39 | 1 | 0 | dso-fini-<key> |
| PR 1 | up | first | 41 | 1 | 1 | dso-fini-<key> |
| this PR (cf-built) | cf, up | warm, first | 38 | 0 | 0 | none |
| this PR (up-built) | cf, up | warm, first | 38 | 0 | 0 | none |

R CMD SHLIB (warm): execve 19 to 18, `zig version` 2 to 1. The one left is
check.zig's gate (feat-tier1-engine decision 6).

Wall seconds, mean / min of 5 interleaved rounds, load1 1.5 to 3.9:

| zig | pkg | mode | PR 1 | this PR |
|---|---|---|---|---|
| cf | tinyc | first | 1.13 / 1.11 | 1.02 / 0.99 |
| cf | tinyc | warm | 1.06 / 1.04 | 1.03 / 1.01 |
| cf | quadprog | first | 2.50 / 2.49 | 2.40 / 2.39 |
| cf | quadprog | warm | 2.43 / 2.41 | 2.41 / 2.39 |
| up | tinyc | first | 0.96 / 0.94 | 0.91 / 0.91 |
| up | tinyc | warm | 0.93 / 0.91 | 0.92 / 0.90 |
| up | quadprog | first | 2.38 / 2.35 | 2.32 / 2.29 |
| up | quadprog | warm | 2.33 / 2.31 | 2.31 / 2.29 |

The gain is small: 0.04 to 0.11 s at the first install after rzig's cache
is empty, 0.01 to 0.03 s warm. The case rests on the spawn, the cache and
the trust surface.

Sizes. The objects: dso_fini.o 1,920 B (cf) or 1,824 B (up) on
x86_64-linux, 2,112 B or 2,016 B on aarch64-linux; cfguard.o 423 B. rzig
shrinks by the deleted cache code (ReleaseSafe, cf):

| target | PR 1 | this PR |
|---|---|---|
| x86_64-linux-gnu.2.17 | 1,080,416 | 1,074,256 |
| x86_64-windows-gnu | 1,351,168 | 1,344,000 |
| aarch64-windows-gnu | 1,112,064 | 1,104,896 |
| aarch64-macos | 879,512 | 879,496 |

The review fixes add the `cache` trace line (main.zig): x86_64-linux
1,075,824, x86_64-windows 1,345,536, aarch64-windows 1,105,920,
aarch64-macos 879,496 (cf; `t1e/pr2-fix/logs/xbuild-*.log`).

## Decisions made here (with reasons)

These follow from decision 4 (A) and the prompt's design questions. The
user confirmed 1 (place), 2 (no fallback) and 4 (cfguard on x86_64 only)
on 2026-10-23; 3 and 5 are implementation choices.
1. **Place: TC, beside rzig.** The section above.
2. **No cache fallback; a warning.** The section above.
3. **Built by a `zig cc` command, not `b.addObject`.** It is the command
   rzig ran, so the object is byte-identical to the cache's (checked:
   sha256 facef652... for cf on x86_64-linux in both). `addObject` goes
   through `zig build-obj`, which was not measured.
4. **cfguard on x86_64 only, in rzig too.** An x86_64 object cannot link
   into an ARM64 image, and a missing file must not warn at every link on
   Windows on ARM.
5. **`rzig_cache_odd`'s liveness check is rzig's trace now.** Before
   this PR the missing `dso-fini-*` or `cfguard-*` entry failed a check
   that read the wrong directory. A link leaves nothing in rzig's cache
   now (up zig: no cache directory at all; cf zig on linux: none
   either), so an empty directory proves nothing. RZIG_TRACE names the
   cache (`cache <dir>`), and the harness requires that it is the
   directory it reads (review of this PR, finding 1). Rejected: a
   fixture that makes an `archive-*` entry. It needs one more package in
   each harness and checks one entry kind, where the trace line checks
   every traced call. `link_object_named` stays: it shows that the link
   took R's object.

## Records

- **zig's global cache is shared across zigs of one version.** With one
  ZIG_GLOBAL_CACHE_DIR, upstream zig reused conda-forge zig's cached
  object for the same `zig cc -c` command: the first measurement showed
  identical bytes, conda-forge's `.comment` included. With a cache per
  zig the `.comment`s differ (`t1e/pr2/NOTES.md`). Harnesses that compare
  the two zigs need a global cache per zig, as scripts/env.sh gives
  (`zig-cache/zig-<cksum>`).
- **kappa's F1 is gone for cfguard.** cfguard.o is a file of the
  install, read and never renamed at link time. The same race stays for
  archive copies: archives.zig writes `archive-<key>/<name>.a` with
  `Io.Dir.copyFile(.replace = true)`, a temporary file renamed into
  place. Two jobs that miss the same entry at once can still rename over
  a file the other has open on Windows. It needs a package that passes
  an archive without a `.a` name, so it is rarer than cfguard's, which
  every Windows link took.
- **The harnesses take Windows to be win-64.** rzig adds no cfguard.o on
  a non-x86_64 Windows, and build.zig makes none there. The harnesses
  do not follow that: `link_object` (verify-helpers.sh) answers
  cfguard.o on every Windows, verify-tree.sh checks the AMD64 COFF
  machine, test-preflight.R and the recipe's `if: win` expect the file.
  They follow env.sh (`windows-*) PLAT=win-64`) and the recipe's
  `bin/x64` test lines, which feat-cross-platform-standardization calls
  a win-arm64 non-goal. A win-arm64 port changes these four together
  with the rest (review of this PR, finding 2: not changed here).
- **PR 1's graft 3 is gone with `make`.** Its rename tolerance only
  served `cache.compiled`. archives.zig and libcxx_mirror.zig have their
  own writes, unchanged.
- **An old tree with a new rzig warns at each link.** zig's install never
  removes a file, and never added this one before. A rebuilt tree has
  it; verify-tree.sh fails a tree without it.

## Review (2026-10-23)

A review of this layer gave 5 findings. The fixes are in
`t1e/pr2-fix/fix.diff` (against the layer before them).
1. **Medium, fixed: `rzig_cache_odd` lost its liveness line.** With
   nothing in rzig's cache after a link, a harness that read the wrong
   directory passed. RZIG_TRACE now names the cache, and the harnesses
   compare it (decision 5). A harness changed to read a wrong directory
   now fails, in pkg-parity and in verify-bundle (gamma, run on purpose).
2. **Low, not changed: the harnesses take Windows to be x86_64.** See
   the record "The harnesses take Windows to be win-64".
3. **Low, fixed: the Windows-link unit test skipped off x86_64.** It runs
   on every host now. On x86_64 it expects the stub; elsewhere no stub,
   with the rest of the line the same. The missing-object test expects
   no warning for a Windows link off x86_64. It now asserts decision 4.
4. **Low, fixed: texts that said TC holds rzig alone.** README.md,
   pixi.toml, hermetic-check.sh and verify-tree.sh name the link object
   too.
5. **Low, fixed: records that read as closed.** The Trust bullet and the
   F1 record name the archive-* and zig-lib-* entries that keep the same
   trust and race. dso_fini.zig says zig 0.16.0, the two zigs measured,
   not "any zig 0.16".

## Tested

The tree: `t1e/pr2/RESULTS.md` names the diff and lock hashes. Tested
on gamma (linux-64) and kappa (win-64), each with both zigs; omicron
was not used.

gamma, before the review fixes (`git diff` ba4e8425...):
- rzig's unit tests: 170/170 with cf and with up (PR 1: 174; 5 cache
  and object tests deleted, 1 added).
- parity-test.sh: 126 ok, 60 ok+, 33 ok*, 0 failed, with each zig. The
  dso_fini case moved from ok* to ok+: no cache state to explain.
- The project chain, R built by cf: build, verify-tree, toolchain,
  verify-toolchain, package-toolchain, verify-package, compile-tree,
  pkg-parity, hermetic, contract: all rc 0. pkg-parity and contract with
  up zig on the same tree: rc 0.
- R built by up (`ZIG_BIN` = upstream zig): build, verify-tree,
  toolchain, compile-tree, pkg-parity and contract with up zig, and
  pkg-parity with cf zig: all rc 0.
- Real installs of tinyc, many, quadprog, fmod, zighello (tier 2),
  zighelloc (tier 2) and R CMD SHLIB, in all four R/zig combinations: rc
  0, the traced link names `TC/dso_fini.o`, each `.so` has a
  `.fini_array`, no warning, rzig's cache stays absent, and the calls
  give PR 1's values. badc fails as designed.
- Z9 end to end: a C++ package with a static destructor, unloaded:
  exit 0 on PR 1's tree and on both new trees with both zigs; a copy of
  the up tree without dso_fini.o warns, links, has no `.fini_array`, and
  R segfaults at exit (139), with both zigs.
- 4 concurrent cold installs (tinyc, many, quadprog, fmod) on the cf tree,
  each zig: 4/4, each `.so` with a `.fini_array`, rzig's cache empty.
- rzig and its object cross-built with both zigs for x86_64- and
  aarch64-linux-gnu.2.17, x86_64- and aarch64-windows-gnu, aarch64- and
  x86_64-macos.13.0: rc 0; dso_fini.o for both linux targets, cfguard.o
  for x86_64-windows only, none for macOS.
- `zig fmt --check` on the 10 changed .zig files: clean with both zigs.

kappa (win-64), both zigs, the archives' trees with this layer's
rzig.exe and cfguard.o put in by hand (`t1e/pr2-kappa/RESULTS.md`):
- unit tests 143 passed, 27 skipped, 0 failed; the two compiler tests
  with the link objects now run on Windows.
- tinyc, many, dtorpkg, fmod, quadprog, cfgpkg (`-mguard=cf`), zighelloc
  and R CMD SHLIB: rc 0, each link names `TC\cfguard.o`, no `r-zig`
  cache directory. The DLLs equal PR 1's but for the link time.
- cfguard.o missing: one warning per link; a `-mguard=cf` link fails as
  designed.

The review of this layer, on the same tree (`t1e/review-pr2/RESULTS.md`):
- gamma: the unit tests 170/170 and parity-test.sh 0 failed, with each
  zig. A rattler-build 0.76.1 probe package with dso_fini.o in
  `lib/R/bin/toolchain`: rc 0, the packaged object byte-identical
  (`facef652...`). `rattler-build --render-only` of recipe.yaml for
  linux-64, linux-aarch64, win-64 and osx-arm64: rc 0; r-zig-slim's
  `exists` list names dso_fini.o for both linux subdirs, cfguard.o for
  win-64 and none for osx-arm64. make-wheel.py on the cf trees: the
  wheel holds `r_zig/R/lib/R/bin/toolchain/dso_fini.o`, tag
  manylinux_2_17. A relocated compile tree: the link names the moved
  dso_fini.o, and a C++ static destructor runs at unload, with both
  zigs.
- kappa: rzig-test.exe, cf-built and up-built, natively: 143 passed, 27
  skipped, 0 failed; the 3 link-object tests run. A `-mguard=cf` DLL
  links (rc 0) with TC/cfguard.o and upstream zig from a path with a
  space, and when rzig is started by its 8.3 short path. With cfguard.o
  removed, the CFG link fails and a plain link warns, as designed.

After the review fixes (the tree below the "Update" of
`t1e/pr2/RESULTS.md`):
- gamma: rzig's unit tests 170/170 and parity-test.sh 126 ok, 60 ok+,
  33 ok*, 0 failed, with each zig; `zig fmt --check` clean with both;
  rzig, its object and the unit-test binary cross-built for the 6
  targets with both zigs, rc 0. The chain on a cf-built and an up-built
  tree: build, verify-tree, toolchain, compile-tree, pkg-parity (all
  four R/zig pairs), and for cf verify-toolchain, hermetic,
  package-toolchain, verify-package and contract: all rc 0. Each traced
  call names the cache pkg-parity reads.
- kappa: the unit tests (up- and cf-built, 2 runs each) 143 passed, 27
  skipped, 0 failed, the same skips as before. Traced installs of tinyc
  and cfgpkg and R CMD SHLIB print `zig-cc: cache <dir>` with
  XDG_CACHE_HOME and with LOCALAPPDATA alone. Under Git for Windows'
  bash, `rzig_cache_odd` accepts that directory in any case and in
  either form, names the other one when the harness looks elsewhere, and
  says `no cache line` for an untraced log.

UNVERIFIED:
- kappa (win-64): a native Windows R build that installs
  `TC/cfguard.o` (the object was built by rzig's build.zig and put in by
  hand), and magick's CFG link. pkg-parity and verify-bundle on Windows
  (only their helper ran there).
- linux-aarch64 and osx-arm64: the unit tests' non-x86_64 branch was
  compiled (aarch64-linux, aarch64-macos), not run.
- omicron (osx-arm64, osx-64): nothing changes on macOS but the deleted
  cache code; not run.
- The conda package: a full rattler-build of recipe.yaml with its tests
  (the new `package_contents` lines, test-preflight.R). The probe
  package and the render ran (above).
- The wheel: pip install and wheel-test.sh. make-wheel.py ran (above).
- CI, linux-aarch64 at run time, Windows on ARM.
- A zig other than 0.16.0 linking these objects (expected: lld links
  older relocatable objects).
