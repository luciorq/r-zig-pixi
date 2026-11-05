# Phase 6 critique: verdicts and amendments (amender, read-only)

2026-10-16. The amender checked every point of the two critiques of
`phase6/planner/PHASE6-IMPLEMENTATION.md` against the worktree's code
(`wt/feat-standalone-phase6`, unchanged: pixi.lock sha256 starts
fbb64b7ba4e31e45, `git diff | sha256sum` starts 69a83be6e2638c69, 69
status entries) and, for claims about flang, against the surveyor's
staged linux-64 `TC/flang` (flang 23.1.1). The amended plan is
`phase6/critic/PHASE6-IMPLEMENTATION.md`; each amendment there carries
its tag.

**Note (2026-10-19).** The user decided that these PRs do not bump the
conda build number: "do not bump conda package build version in the
previous PRs. the next build bump is going to be after phase 7 is
merged." Phase 6 keeps build 8, as phase 4, SHLIB routing and phase 5
do, and main publishes nothing until the user sets the repository
variable `CONDA_PUBLISH` after phase 7's bump merges (PLAN.md, B14's
amendment). Where this critique says phase 6 takes 12 (or names the earlier
layers' 9, 10 and 11), read: the number stays 8, and phase 6 publishes
with phase 7's bump, at the number after universe's newest (B14 a).

- critique-code.md: Cc1-Cc18.
- critique-goals.md: Cg1-Cg11.
- The amender's probes (CA), in `phase6/critic/probe/`:
  - CA1: `flang -Qunused-arguments -c s.f90 -o s.o <flag>` for 49 link
    flags. 31 are refused with "unknown argument", 18 are accepted
    (the list is in the plan's Sources).
  - CA2: `flang --target=aarch64-unknown-linux-gnu -c` with the x86_64
    driver writes an AArch64 object.
  - CA3: `strings` of the linux-64 driver names flang-pixi's gamma build
    path 912 times.
  - CA4: gamma has no zig, flang or qemu-aarch64 in /usr/bin, no binfmt
    entry, and no ziglang in its system python3.
  - CA5: the module directory names of the five staged subdirs.

Nothing in the worktree was written. No flang-pixi contact. No
dependency or lock change. `df -h /` showed 7.5 GB free throughout.

Every open point takes its ★ option, by the user's standing
instruction ("Keep going", after "Follow with the recommended"). Each
one is recorded as answered that way, and its menu is kept in the
plan's section 11.

## Verdicts

| point | severity (critic's) | verdict | checked against | lands in the plan |
|---|---|---|---|---|
| Cc1 flang refuses link-only flags | Medium | **Accepted, widened.** CA1 confirms Cc1's 7 refusals and finds 24 more: `-install_name`, `-current_version`, `-compatibility_version`, `-exported_symbols_list`, `-bundle_loader`, `-multiply_defined`, `-force_load`, `-weak_framework`, `-F`, `-headerpad_max_install_names`, `-single_module`, `-flat_namespace`, `-dead_strip`, `-arch`, `-static-libstdc++`, `-shared-libgcc`, `-static-pie`, `-mconsole`, `-municode`, `-mthreads`, `-z`, `-u`, `-T`, `-e` | CA1; fortran.zig's planned split | `compileArgs`, a second measured list (section 3); risk 1 rewritten; tests in step 1; re-measured on every host in step 3; E's reason |
| Cc2 `takes_value` gaps | Medium | **Accepted.** `-undefined`, `-force_load`, `-multiply_defined` and `-Xflang` are missing from cmdline.zig's `takes_value` (lines 61-75). Today only `outputIndex` and zig-cc's rewriting read it | cmdline.zig | cmdline.zig section; a macOS SHLIB-style `inputs` test |
| Cc3 modules path: `..`, separators, physical path | Medium | **Accepted.** `find_zig.inDir` joins with `\` on Windows. `flang_rt.find` already turns `\` into `/` for `-print-resource-dir`'s answer | find_zig.zig:80-85, flang_rt.zig:96-101 | `modulesDir` (string cut, `/` only, no `..`); verify-bundle compares against `pwd -P` / `cygpath -m -l` |
| Cc4 trees must obey `prefix_is_env` | Medium | **Accepted.** build.zig skips only a `Copy` when `prefix_is_env and !c.in_conda` (line 157). recipe/build.sh exports `CONDA_PREFIX=$PREFIX` and runs zig-toolchain.sh into `$PREFIX`. The host env has flang-rt-zig (recipe.yaml:273) | toolchain build.zig, recipe/build.sh:16,48 | build.zig section; step 2's fake-env test. The test never uses the real env as the prefix (amender's addition) |
| Cc5 L decided on one Windows | Medium | **Recording half accepted; `.zip` fallback not taken** (Cg2 decides L). `untar(tar = "internal")` reads xz on every Windows that has the base. R links liblzma (build.zig `lzma`) | build.zig:1662; Cg2 | L (a) amended; kappa records `tar --version` and the Windows build; README names `untar()` first on Windows |
| Cc6 `ZIG_LIB_DIR=` line in a split's dry run | Medium | **Accepted.** `printArgv` prints `ZIG_LIB_DIR=` first (main.zig:347). The mirror sets it for conda-forge's zig with a shared libc++ | main.zig:343-351, libcxx_mirror.zig:28-39 | Ctx/main section; G (a); a unit test; verify-bundle skips the line |
| Cc7 C sources in a split get Fortran flags | Low/Medium | **Accepted (simplification).** A C-family source stays on zig's link line. Amender's addition: a source that only `-x` classified keeps `-x <lang> <src> -x none` | compiler.zig (zig-cc compiles and links in one call) | F (a) amended, the planner's version kept as (a0); risk 16; tests |
| Cc8 modules directory picked by byte order | Low | **Accepted, merged with Cg8.** The critic's two-versions-in-one-env example is from separate envs (`full` has `lib/clang/22`, `default` has 23), not one env. Still cheap robustness. macOS's triple starts with `arm64-` (CA5), so `aarch64` also matches `arm64-` | main checkout's envs; CA5 | D (a): `<v>` holds `finclude/flang/`, `<t>` is named for rzig's CPU; unit tests |
| Cc9 the flag on `-E`, `-fsyntax-only` | Low | **Accepted.** `cmdline.compileOnly` has no `-fsyntax-only` (cmdline.zig:25-30). CP2 shows `include 'omp_lib.h'` resolves through the intrinsic module path | cmdline.zig | `kind`, `modules`, `xLang` (`f95-cpp-input`); step 3's `$FC -E` check |
| Cc10 the clobber check cannot see tree files | Low | **Accepted, done differently (W).** `readRecords` parses only records that contain a needle (build.zig:343-370). One pass with a separator-free needle per tree (`name`, else the last component of `from`). Cc10's second pass is not needed | toolchain build.zig | W (a); build.zig section; toolchain-test fixture with two owners |
| Cc11 macOS signing | Info | **Accepted as a record** | CP4 | step 3 omicron: `codesign -dv`, `codesign -v`, `spctl`; PLAN record |
| Cc12 licence set complete | Info | **Accepted** | CP5 | risk 14 marked as checked; Later licence item (zig's MIT text) |
| Cc13 the flag is needed on macOS only | Info | **Accepted, merged with Cg4** | CP1, CP2 | section 0; `modules` doc; C's reason; PLAN record |
| Cc14 K drops as a recorded patch | Low | **Accepted** | (process) | section 1; steps 3 and 5; K's reason |
| Cc15 Windows temp directory; signal exit codes | Low | **Accepted.** main.zig's Windows `run` returns 1 for a termination that is not an exit. On unix, exec passes the shell's 128+n | main.zig:363-382 | split's `<tmp>` rule; `runSteps`; unit tests |
| Cc16 the prototype has no zig under `env -i` | Low | **Accepted.** The prototype has no `zig/`. CA4: gamma has no zig on `/usr/bin:/bin` and no ziglang in python3 | find_zig.zig:1-15; CA4 | step 1: `ZIG_BIN` set, once for each zig |
| Cc17 summary package order | Low | **Accepted (X a: the test expects copy order).** build.zig prints packages in `copies.items` order (lines 192-199) | toolchain build.zig | step 2's expected line; build.zig section; X |
| Cc18 checked, holds | Info | **Accepted**, including build number 12 whether or not K lands | — | section 0's build-number bullet |
| Cg1 B40 has no Fortran half | Medium-High | **Accepted (U a).** One change: the minimal assertion checks for the linker's undefined `omp_`/`__kmpc_` symbol, not "a message naming the missing runtime", which rzig does not print. B40 (a) hides only C's `openmp/include` (PLAN:1880-1907) | PLAN B40; environment.zig | U; section 0; step 6; verify-bundle; README; PLAN's B40 record |
| Cg2 L's Windows fallback is not needed | Medium | **Accepted (L a amended).** `.tar.xz` on every platform, with no OS test | env.sh:43 (`ARCHIVE_EXT`); R links liblzma | L; section 0; step 4; risk 6; README; open items (the `.zip` item replaced by "stop and report if `untar()` fails") |
| Cg3 B44 for aarch64, native osx-64 and upstream needs the user's push | Medium | **Accepted.** CA2 confirms the pre-check is possible. CA4 confirms no emulator | CA2, CA4 | section 1; step 3 (gamma pre-check); step 8; T; open items; PLAN status line |
| Cg4 B/C reasons; the bare driver differs per OS | Medium-Low | **Accepted.** B's reason is "a by-product of A (a)". C's reason uses the measurement. README says one thing. A bare-driver probe on each host is recorded | CP1, CP2 | B, C; steps 2 and 3; README; section 7 |
| Cg5 decisions made in passing | Medium-Low | **Accepted.** New V (`ISO_Fortran_binding.h`), A2 (the LLVM-major constant), K2 (macOS libc++ exports). E's answer covers list growth. A Later item for the lld-zig pin (not acted on) | plan text | section 11; section 10; open items |
| Cg6 write the flang `Dir` once | Low | **Accepted.** `ompHeaders(comptime include)` is the existing pattern (build.zig:80-87) | toolchain build.zig | build.zig section (`flangDir`) |
| Cg7 compare FC_VER with TC/flang's version | Low | **Rejected.** FC_VER is a hand-kept captured string (`zigbuild/config/*/{subst.txt,config.h}`). On Windows it is a fixed text with no version (build.zig:967). So the check fails on Windows by design and on unix compares a hand-kept string. Same-bytes is already enforced: one solve-group `r`, and exact flang-zig/flang-rt-zig build pins in both `[dependencies]` and `[feature.minimal.dependencies]` (pixi.toml 237, 244, 468, 470) | build.zig:962-967; zigbuild/config; pixi.toml | section 12 |
| Cg8 another CPU's modules for a PATH flang | Low | **Accepted, merged with Cc8** | CA5 | D (a) |
| Cg9 PyPI users' own flang | Low | **Accepted.** Recorded as a risk. Gamma runs a non-flang-zig flang as a record, not a gate. `flang_rt.find` globs only `.a` (flang_rt.zig:92-110) | flang_rt.zig | risk 15; section 4's PyPI row; step 1; section 7 |
| Cg10 embedded build paths on every OS | Low | **Accepted.** CA3 confirms the linux driver embeds `/data/gamma/.../rb-out/...`. That path is outside every directory verify-toolchain scans for on gamma, so nothing is listed there. omicron and kappa record `flang -###` | CA3; verify-toolchain.sh:155-199 | risk 9; verify-toolchain note; step 3; section 7 |
| Cg11 the format rule lives in bash and Zig | Low | **Accepted.** groups.zig is the reference (B35). With Cg2, neither side has an OS test | env.sh, groups.zig | env.sh comment; step 4 |

Conflicts between the critics:
- Cc5 and Cg2 (Windows' format): Cg2 is taken. Cc5's recording and its
  README order are kept.
- Cc8 and Cg8 (module directory choice): merged into one rule.
- Cc13 and Cg4 (the bare driver): merged. The flag is one rule
  everywhere, the per-OS facts are recorded, and the README text is the
  same on every OS.

## Open points and the option taken

Every point takes ★ (a). The menus are in the plan's section 11.
- A: driver as a renamed copy, modules and runtime as record trees.
- A2 (new): the LLVM-major constant in the toolchain build.
- B: keep both Windows module directories (reason corrected).
- C: no cfg.
- D: real path, no `..`, `/` only; the version directory that holds
  `finclude/flang/`; the CPU-named triple directory; the flag on
  `-c`/`-S`/`-E`/`-fsyntax-only` and on split compiles.
- E: every link through zig. Two measured lists: `linkArgs` and
  `compileArgs`. Spawned. 128+n on a signal.
- F: amended. A Fortran source becomes a flang step; a C source stays on
  zig's line.
- G: `&&` blocks, with `ZIG_LIB_DIR=` placed before zig's block.
- H: accept `feedstock: unknown` (an open item).
- I: version check.
- J: carve cross-check once, by hand.
- K: drops where step 3 passed, via `k-drops.diff`.
- K2 (new): macOS drop stays, with the exports recorded.
- L: amended. `.tar.xz` on every platform, no OS condition, `untar()`
  named first on Windows.
- M: the standalone line names flang.
- N: move `flang/bin/flang` aside.
- O: TC/flang in both passes.
- P: `$FC` probe in test-compilers.R.
- Q: keep the lld-zig pin.
- R: build 12. Conda and PyPI contents change (rzig on every OS), so 12
  holds whether or not K lands.
- S: `phase6-only.diff` against the phase 5 baseline.
- T: CI's arm leg, plus gamma's pre-check. Pending the user's push.
- U (new): accept B40's Fortran limit, with a minimal assertion.
- V (new): `ISO_Fortran_binding.h` left out.
- W (new): one-pass needles per tree.
- X (new): summary in copy order.

## Open items for the user

None filed, nobody contacted.
- Phase 6 is "pending CI": linux-aarch64, native osx-64 and the
  upstream-zig label run need your push.
- H: flang-pixi's recipes record no repository.
- Only if kappa's `untar()` fails: win-64's format is blocked.
- Any B44 failure in flang-zig or flang-rt-zig: a new flang-pixi build
  and a re-lock.
- Any K drop left out.
- Later: the redundant lld-zig pin (a dependency change).

No point needed a flang-pixi change, a pixi.lock change or a dependency
change.
