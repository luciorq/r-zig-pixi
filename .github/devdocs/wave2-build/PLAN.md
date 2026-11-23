# wave2-build: bootstrap stamp, host tools, fetch (M-19, M-21, M-20)

Branch wave2-build from main f5a6c84. Tested on delta (linux-64).

## Goal

- M-19: a `zig build` whose inputs did not change skips R's bootstrap
  (~1.5 min of R runs on every build).
- M-21: the linux scripts stop using host tools (cmp, find, ldd, bash,
  dirname).
- M-20: `zig build fetch` to retire scripts/fetch-r.sh, if under half a
  day; else a design and a deferral.

## Decisions

| # | question | chosen | reason |
|---|---|---|---|
| 1 | How to skip the bootstrap | One gate for the whole chain: `bootgate check` (after the install step) decides run/skip; every bootstrap step is `bootgate run <decision> -- <cmd>`; `bootgate stamp` records the tree after the last step (zigbuild/tools/bootgate.zig, built for the host by build.zig) | zig 0.17 has no custom make steps (the graph is serialized for the Maker), so the logic is a small Zig tool. A per-step zig cache key was tried first and dropped: hit/miss is per step, and a mixed outcome left the tree without library/ (finding 3) |
| 2 | What the stamp covers | sha256 of: every step's command, stdin, environment and cwd (computed at configure), each mkdesc DESCRIPTION, the staged library payload's path (content-addressed), and path/kind/size/mtime of every file under R_HOME, `<prefix>/bin` and R's source tree | Anything that changes what the bootstrap reads or writes makes it run; directories by name only and no file modes (finding 2) |
| 3 | Where the stamp lives | `<zig local cache>/r-zig-bootstrap/<wyhash(prefix)>.stamp` | Not in the tree that ships; deleting the cache or the prefix makes it run again. A failed or interrupted run deletes the stamp first, so it runs again |
| 4 | `Built:` time | The decision's second line: SOURCE_DATE_EPOCH if set, else the time the bootstrap actually ran (stays the same while skipped). Staged base/tools DESCRIPTIONs get SOURCE_DATE_EPOCH or the epoch (both are rewritten by mkdesc) | The configure-time wall clock changed the staged payload, and so the stamp, on every build |
| 5 | Steps that always run | `chmod scripts` and `verify Rscript` | The install step puts the launchers' 0644 mode back on every build; the sanity check costs 0.1 s |
| 6 | Volatile env | Not passed to R steps: SSH_*, OLDPWD, SHLVL, `_`, terminal/tmux ids, and every `PIXI_*` | pixi sets PIXI_ENVIRONMENT_PLATFORMS in a random order per run (finding 4); nothing in the bootstrap reads them |
| 7 | doc/NEWS, doc/html/NEWS.html | No longer installed from the source tree's doc/ | The bootstrap writes both; installed too, they were replaced on every build and forced a rerun. Final tree unchanged (bootstrap's copies, as before) |
| 8 | M-21 tools | findutils + diffutils in `[target.linux.dependencies]` and minimal's linux target; bash + coreutils in the wheel env's linux target; vendor-libs.sh linux uses needed_of (patchelf) + `$CONDA/lib` instead of ldd | Same closure as ldd (walk over copies), no host binary |
| 9 | M-20 | Deferred (design below) | Over half a day and needs Windows/macOS hosts |
| 11 | doc exclude suffix (review) | `"NEWS.html"`, not `"html/NEWS.html"` | zig's InstallDir matches `endsWith(entry.path, ext)` (lib/zig/compiler/Maker/Step/InstallDir.zig:61) and the walker joins with `path.sep` (std/Io/Dir.zig:254): `html\NEWS.html` on Windows; only doc/html/NEWS.html ends in NEWS.html |
| 10 | Debugging aid | `R_ZIG_BOOTGATE_LIST=1` writes `<stamp>.key.list`, `.check.list`, `.stamp.list` | Was needed to find findings 2 and 4; cheap to keep |

## Findings

- F1 (V) baseline no-op `pixi run build -j8` on delta: 135 s, 133 s
  (`~/rz/wt/wave2-baseline.times`); with bootgate 17 s, 18 s
  (`/tmp/w2-run31.log`, `w2-run32.log`: "r-zig: bootstrap inputs unchanged
  since ...: not running it again"). The remaining ~15 s are vendor-libs.sh
  twice and the licence records step (outside zig build).
- F2 (V) zig 0.17's InstallDir/InstallFile atomic copies change the
  directories' mtimes on every build, and `updateFile` resets a mode the
  bootstrap changed (`chmod +x` launchers); the source tree's doc/NEWS and
  doc/html/NEWS.html were installed over the bootstrap's on every build
  (diff of bootgate lists, `/tmp/w2-stamp7.list` vs `.check.list`).
- F3 (V) zig 0.17's Run cache treats a file input rewritten with the same
  content as changed (repro: scratch build.zig, a side-effect step
  rewriting a constant file, a `.check` consumer with addFileInput: never
  cached; cached once the writer keeps the file). With per-step caching a
  mixed hit/miss ran `reset library` but not the rest: `Fatal error:
  unable to open the base package` (`/tmp/w2-run20.log`). Hence decision 1.
- F4 (V) pixi's PIXI_ENVIRONMENT_PLATFORMS is in a different order on each
  `pixi run` (`/tmp/w2-key9.list` vs the next key list).
- F5 (I) methods.rdb/rdx and tools' help rdb/rdx differ between two
  bootstrap runs of the same inputs (`touch` + rebuild, sha256 differ),
  as do every DESCRIPTION and Meta/package.rds (the `Built:` time).
  Existing behaviour, not caused by this branch; the skip makes repeated
  builds keep identical bytes now.
- F6 (V) vendor-libs.sh without ldd vendors the same 49 libraries
  (`== vendored 49 conda libraries`, same file list as the baseline tree).

## Tests (delta, linux-64, slim, conda-forge zig 0.17.1)

Review pass (after decision 11; `~/rz/rev.out`, `~/rz/rev2.out`):
- no-op 19 s (skip); `SOURCE_DATE_EPOCH=1700000000` 112 s (runs,
  `Built: ... 2023-11-14 22:13:20 UTC`), again 18 s (skip, same time);
  unset 107 s (runs, now); bootstrap killed mid-run (process group,
  exit 143): stamp gone, next build runs (107 s), then 18 s skip;
  `verify-tree` exit 0. All 15 base DESCRIPTIONs carry the bootstrap's
  time, none the staged epoch.
- bootgate.zig compiles for x86_64/aarch64 windows, macos and linux with
  conda-forge zig 0.17.1, and native/x86_64-windows/aarch64-macos with
  upstream zig 0.17.1 (build/zig-upstream); `zig fmt --check` clean.
- lock: `git diff pixi.lock` has no removed line; added packages are only
  findutils, diffutils, bash, coreutils, readline.

Implementation pass:

- Full build after the change, then two no-op builds: exit 0, 121 s / 17 s
  / 18 s; `touch library/stats/DESCRIPTION` -> bootstrap runs (107 s).
- Tree vs the baseline build (`~/rz/wt/wave2-dist-baseline`): same 1986
  files; content differs only in the 34 files of F5.
- `pixi run verify-tree`: exit 0 ("installed tree verified (linux/slim)").
- `command -v`: find, cmp, dirname, bash from the default env; bash and
  dirname from the wheel env.
- bootgate unit run in a scratch dir: check/run/stamp/skip, exit code
  passed on, stdin drained on skip.
- `pixi lock` on delta: additions only (diffutils 3.12, findutils 4.10.0
  in every linux env; bash 5.3, coreutils 9.12, readline 8.3 in wheel
  linux-64/aarch64); no package removed or changed.

## Not verified

- (A) The env's shared libraries (<env>/lib, <prefix>/lib copies) are
  not in the stamp: a `pixi update` that changes no header R compiles
  against, so nothing under R_HOME, keeps the old bootstrap results.
  Nothing in them depends on those libraries' versions as far as known;
  delete the stamp (or R_HOME) to force a run.
- macOS and Windows (bootgate's spawn path on Windows, Rterm with
  `--args`, whether vendor-libs.sh's Windows copies into R_HOME/bin/x64
  make the stamp differ on every build: then Windows only keeps running
  the bootstrap, as before). Needs CI.
- Upstream zig (PyPI ziglang 0.17.1) build of build.zig and bootgate.
- linux-aarch64, the full/openblas/minimal variants, the conda recipe
  build (it runs zig-build.sh once per fresh prefix: the gate always says
  run there).
- wheel-test end to end with the env's bash.

## M-20 design (deferred)

`zig build fetch`: a host Zig tool (std.http.Client, CRAN then the CDN,
sha256 against scripts/checksums, std.compress.flate + std.tar into
build/R-<ver>, symlink entries skipped on Windows, the empty
`.r-zig-patches` stamp), run by a `fetch` step; pixi's `fetch` task and
recipe/build.sh then call it, and fetch-r.sh goes. build.zig.zon's lazy
dependency was ruled out: zig's package hash is not the pinned tarball
sha256, it supports one URL, and its read-only global cache cannot take
zig-build.sh's in-place patches. Reason for deferral: TLS/proxy and tar
behaviour must be checked on Windows and macOS CI, over half a day.

## Backlog items closed

M-19, M-21. M-20 deferred (design above).
