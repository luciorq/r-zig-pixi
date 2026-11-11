# feat-zig-017 — the zig 0.17 port

Branch feat-zig-017, stacked on feat-zig-pkgconf (pkgconf from source),
from main a211121. The zig 0.17 wave of feat-standalone-toolchain's
TODO.md ("The zig 0.17 wave", B18 = a).

## Why now

- conda-forge's main label has zig 0.17.0 (build 6) on all six subdirs,
  win-arm64 included.
- PyPI's ziglang 0.17.1 has a wheel for every platform the project
  ships, win_amd64 and win_arm64 included (0.17.0 had no win_amd64).
- flang-pixi's zig 0.17 builds are on universe on all six subdirs:
  flang-zig 7, lld-zig 6, flang-rt-zig 11.
- One toolchain: 0.17 only, no 0.16/0.17 switch.

## What changed

Pins:
- pixi.toml `zig = "0.17.*"` (default and minimal), flang-zig 7,
  lld-zig 6, flang-rt-zig 11; recipe.yaml the same (`*_7`, `*_6`,
  `*_11`), r-zig-slim's run_constraints `zig 0.17.*`.
- scripts/fetch-zig.sh: ziglang 0.17.1 wheels (sha256-pinned), win-arm64
  added; make-wheel.py `ziglang>=0.17.1,<0.17.2`.
- pixi.lock: re-solved (needs the user's approval; see "Lock"). The solve
  changes only zig (0.17.0 `_6`, LLVM 22 under it), the three flang
  packages, llvm-openmp 23.1.2 -> 23.1.5, and the libraries zig 0.17.0
  depends on (libllvm22, libclang-cpp22, libcxx 22 on macOS,
  libgcc/libstdcxx-devel).

zig 0.17's build system (a configurer process that serializes the graph
for a separate maker):
- No custom steps (Step.init with makeFn): the toolchain build's
  SourcesStep became a Run step of a host program,
  zigbuild/toolchain/sources_tool.zig, which hashes the built files and
  writes SOURCES with conda.zig's one writer.
- The configure step does not see --prefix: `-Dprefix=<dir>` repeats it.
  scripts/zig-build.sh and zig-toolchain.sh pass both. Both builds call
  b.graph.poisonCache(): they read the env, R's sources and the tree.
- b.pathFromRoot, b.install_prefix, b.build_root, b.cache_root and
  b.graph.zig_lib_directory are gone: buildRoot/rootPath (b.root),
  localCacheDir (ZIG_LOCAL_CACHE_DIR, which env.sh always sets and 0.17's
  maker reads), zigLibDir (`zig env`'s .lib_dir).
- Lazy dependencies: b.dependencyLazy (pkgconf).

std and language changes (rzig, rpkg, the builds): std.builtin.OptimizeMode
-> std.lang.Optimize with lower-case tags; Allocator.dupeZ ->
dupeSentinel; std.zon.parse.fromSliceAlloc -> fromSlice(.{gpa, arena,
source, diagnostics}); CRC-32/CKSUM's name; EnumSet's `.empty`;
`@backingInt`. rzig's def.zig reads COFF symbol records itself: 0.17's
SectionNumber is an i16 and its reader panics on 0xffff/0xfffe and on
sections past 32,767 under ReleaseSafe.

zigbuild/rpkg (tier 2, shipped in R_HOME/share/zig/rpkg): ported; the
contract test now builds and loads a tier-2 package (src/build.zig with
rbuild, a zig root through R's API), which no test covered before.

macOS floor: zig 0.17 supports macOS 15 and later as a host, and the
zig binary of PyPI's ziglang 0.17.1 says minos 15.0. It still builds for
13.0 with no warning (omicron, both arches). R and the packages it
compiles keep MACOS_MIN 13.0; the compilers group's zig/ is checked
against env.sh's ZIG_MACOS_MIN 15.0. Compiling packages therefore needs
macOS 15; running R and compiled packages needs 13.

zig 0.16 workarounds, audited against both 0.17 zigs (linux-64, cross,
kappa, omicron): only `--dependency-file`'s drop could go (0.17 links
with it and writes the file); rzig and the bash shims pass it through.
Still needed: ar.zig's archive seed (conda-forge's 0.17.0 now fails on
osx-arm64 too), response.zig's newline, cfguard.zig, the
synchronization API set (upstream), the LTO drop on image links,
dso_fini.o at R's glibc floor, the atexit exclusion (both zigs export
atexit from a DLL now), dropTune and marchArgs, the other linker
rules, archives.zig, fortran.zig's link_refused.

## Tests (2026-11-09/10)

The 0.17 solve was made in a scratch copy of the project (z17/proj);
the repo's pixi.lock is unchanged (fbb64b7b...). Every step is a pixi
task, as CI runs it.

| Host | zig | Steps | Result |
|---|---|---|---|
| gamma linux-64 | upstream 0.17.1 (ZIG_BIN) | build, smoke, compile-tree, contract, verify-tree, hermetic, rzig-test, toolchain-test, toolchain, verify-toolchain, package, package-toolchain, verify-package | all ok |
| gamma linux-64 | conda-forge 0.17.0 | default: the same, plus pkg-parity and check; full, openblas, minimal: rzig-test, build, verify-tree, smoke, contract, pkg-parity, check, hermetic, verify-package (minimal also minimal-check); wheel, wheel-test | all ok |
| kappa win-64 | conda-forge 0.17.0 (TC/zig 0.17.1 in the toolchain pass) | toolchain-test, toolchain, verify-toolchain, rzig-test, build, smoke, verify-tree, contract, pkg-parity, check, hermetic, package-toolchain, verify-package | all ok |
| omicron osx-arm64 | conda-forge 0.17.0 | build, smoke, verify-tree, hermetic, rzig-test, toolchain-test, toolchain, verify-toolchain, compile-tree, contract, pkg-parity, check, package, package-toolchain, verify-package | all ok |
| omicron osx-64 (Rosetta) | conda-forge 0.17.0 | the same | all ok |

Found and fixed on the way:
- rpkg.zig (tier 2) did not compile on 0.17; no test covered tier 2.
  The contract test now builds and loads a tier-2 package.
- zig/'s binary needs macOS 15 (ZIG_MACOS_MIN above).
- pkg-parity's cache check: zig 0.17 keys a C compile by the source's
  absolute path (its Cache skips the working-directory prefix), so a
  reinstall from a new R.INSTALL directory recompiles, through rzig build
  and through make alike. The check now asserts that the two paths add
  the same number of entries (26 and 26 for cli, every host) instead of
  none. With 0.16 a reinstall of the same tarball reused zig's cache.

## Lock

Writing pixi.lock needs the user's approval. The scratch solve is at
z17/pixi-017.lock (from z17/proj).
