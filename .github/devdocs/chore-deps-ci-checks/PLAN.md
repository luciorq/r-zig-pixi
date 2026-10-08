# chore-deps-ci-checks — binutils and strace from conda-forge, a check of minimal's packages, LLVM in the zig cache key, CI fails a check it cannot run

**Status (2026-10-08).** Branch chore-deps-ci-checks, at a42c781, whose
content is main's (0c7e19a, the merge of PR #16). Not committed. This is
follow-up PR (i), "chore: dependencies and CI checks", of
feat-no-host-paths/PLAN.md ("Answers of 2026-10-08", in the copy on
feat-standalone-toolchain). It changes pixi.toml, pixi.lock (additions
only), five scripts plus two new files in scripts/, and two workflows.
recipe/, build.zig and zigbuild/ are untouched, so the recipe's build
number stays 4. The tested lock is sha256
`7aef60ff4b270486cf70786f20e21b50cde2638eb6b6deba62d934e780355a63`.
Tested on linux-64, omicron (osx-arm64, osx-64) and kappa (win-64), all
passed; CI has not run yet ("Tested").

Why. On 2026-10-08 the user answered the menu of 2026-10-07 "all ★"
(option a) for D7 to D13 and E3 (chore-lock-and-ci-refresh/PLAN.md,
"Open questions", in the copy on feat-standalone-toolchain). D8 to D13
and E3 are this PR. D7 rides with feat-standalone-toolchain's phase 4
build-number bump. One answer, D10, cannot be done as answered; it
waits for the user (below).

## The items

- **E3 (answer: a): binutils on linux.** `binutils = "*"` in
  `[target.linux-64.dependencies]`, `[target.linux-aarch64.dependencies]`
  and minimal's two linux sections. verify-tree.sh's `objdump -T` (the
  glibc ceiling) and vendor-libs.sh's `strip --strip-debug` (minimal)
  ran the host's /usr/bin tools; now they run conda-forge's 2.46.1.
  `binutils` is the package with the bare names (objdump, strip,
  readelf, ...); binutils_impl_linux-* has only prefixed ones. It also
  puts bare ld, as, ar and nm on PATH. Nothing calls them: zig links
  in-process, flang links with ld.lld (flang-zig's flang.cfg:
  `-fuse-ld=lld`), rzig's ar is `zig ar`. The vendored configs store
  names, not paths (subst.txt: STRIP="strip", NM="nm -B",
  OBJDUMP="objdump"), so a re-capture should not differ.
- **strace on linux (added here, not a menu item).** `strace = "*"` in
  the same four linux sections. hermetic-check.sh (`pixi run hermetic`)
  and verify-bundle.sh (`pixi run verify-package`) trace with it, and
  with D11 CI fails without it. From conda-forge it no longer depends
  on the runner image. strace 7.2 needs only libgcc, which every linux
  env has.
- **binutils in the wheel env on linux (added here).** One
  `[feature.wheel.target.linux.dependencies]` section with
  `binutils = "*"`, so wheel-test.sh's readelf (its C++ runtime and
  rpath checks) comes from the env. macOS uses otool there. wheel is
  outside solve group "r"; its other entries did not change.
- **D10 (answer: a, `libglib` instead of `glib`): not done; the
  re-decision is pending with the user.** libglib alone breaks R's
  cairo device. R compiles cairoBM.c against pango's headers, which
  include glibconfig.h, and only `glib` ships it
  (lib/glib-2.0/include). R links `-lgobject-2.0 -lglib-2.0`
  (subst.txt's CAIRO_LIBS; build.zig links them by name), and the
  unversioned libraries those name are in glib-tools, which glib brings;
  libglib has only the .so.0 files. A scratch test on linux-64 (zig
  0.16, pango 1.56, cairo, libglib, no glib) failed both ways:
  `'glibconfig.h' file not found`, and `unable to find dynamic system
  library 'gobject-2.0'`. The proposal:
  - Keep `glib = "*"` in pixi.toml, with the reason in a comment (done).
    No lock change.
  - Drop `glib` from r-zig-slim's run requirements (recipe/recipe.yaml,
    the r-zig-slim run list) at feat-standalone-toolchain's phase 4
    build-number bump, not now. Host glib's run export already adds
    `libglib`, and on unix the newest pango and harfbuzz need only
    libglib, so user envs would lose python. Not touched here.
- **D9 (answer: a): a check of minimal's locked packages.**
  - scripts/minimal-deny.txt: one regular expression per line, matched
    against the whole package name. It lists the graphics stack with
    what it brings into the R envs (cairo, pango, harfbuzz, glib,
    libglib, libffi, fontconfig, fonts and font-ttf, expat, freetype,
    pixman, png, jpeg, tiff, webp, X11), libdeflate, tk, python and
    libpython, and libgcc-ng and libstdcxx-ng. Checked against the lock:
    every other line matches a package of the R envs (default, full,
    openblas, pkg) on some platform, and none matches one of minimal's.
    libgcc-ng and libstdcxx-ng match nothing today; an old pkg-config
    build once brought them (the note above `[environments]`).
    font-ttf-*, expat, libexpat and libdeflate were added to the prep's
    list from that comparison.
  - scripts/check-minimal.sh: for linux-64, linux-aarch64, osx-64 and
    osx-arm64 it runs `pixi list -e minimal --platform <p> --frozen
    --no-install --json` and matches the names with `grep -x -E -f`. It
    reads the lock only, so one machine checks all four platforms in
    about 2 s. It fails on a match, or when it reads no names.
  - Task `minimal-check` in `[feature.minimal.tasks]`; a step in
    build-r.yaml before rzig's tests, on the minimal legs (four, one per
    platform). The note above `[environments]` now points to it.
- **D8 (answer: a): LLVM in the zig cache key.** scripts/env.sh's key
  is the cksum of zig plus the non-symlink files
  `<zig dir>/../lib/libLLVM[.-]*` and `libclang-cpp[.-]*`, read with
  `cat ... | cksum`. File names, from the locked packages:
  - linux-64, linux-aarch64: lib/libLLVM.so.21.1 and
    lib/libclang-cpp.so.21.1 (lib/libLLVM-21.so is a symlink, skipped).
  - osx-64, osx-arm64: lib/libLLVM.21.1.dylib and
    lib/libclang-cpp.21.1.dylib (lib/libLLVM-21.dylib is a symlink).
  - win-64: zig_impl_win-64 (Library/bin/x86_64-w64-mingw32-zig.exe, a
    170 MB exe with LLVM linked in) depends on no LLVM package, and
    conda-forge's win-64 libllvm21 is an empty package. No LLVM DLL is
    in Library/bin, nothing matches, and the key stays as before. The
    exe is not fully static: it loads zlib.dll, zstd.dll and libxml2.dll
    from Library/bin, and the MSVC runtime. Those are not hashed, as on
    linux libLLVM's own dependencies are not.
  - Upstream zig (PyPI ziglang) has LLVM linked in: nothing matches,
    and the key stays as before.
  Every unix machine rebuilds once into the new key. The old
  build/zig-cache/zig-<old> directories can be deleted.
- **D11 (answer: a): fail in CI, lenient locally.** A helper
  `cannot_check` in scripts/verify-helpers.sh: with `CI=true` (GitHub
  Actions sets it) it prints `error: ... (CI: every check must run)` and
  exits 1; otherwise it prints `note: ... (an error in CI)` and the
  script goes on. It replaces the quiet fallbacks in hermetic-check.sh
  (strace missing or blocked), verify-bundle.sh (strace missing or
  blocked; the build-env CA check) and verify-tree.sh (objdump missing).
  verify-tree.sh also calls it when objdump read no glibc version from
  any runtime file; before, that passed with an empty "runtime worst".
  rattler-build's isolated build env drops CI, and the recipe runs none
  of these scripts.
- **D12 (answer: a, once CI is clean): rattler-build >= 0.76 and its
  warnings as errors.** pixi.toml's floor is `>=0.76` (the lock has
  0.76.1 on all five platforms, so no lock change), and the
  conda-package task passes `--error-overlapping-files
  --error-unused-staging-files` (added in 0.76.0, prefix-dev/
  rattler-build#2790). The prep found none of their warnings in the
  0.76.1 CI logs (runs 37512701120, 37780307165, and the finished legs
  of 37806314996 and 37806403801).
- **D13 (answer: a): an early Ubuntu 26.04 run.** build.yaml's
  `workflow_dispatch` takes an input `linux_runner` (default
  ubuntu-latest), used as `${{ inputs.linux_runner || 'ubuntu-latest' }}`
  for the linux-64 legs (default, full, openblas, minimal) and
  conda-package linux-64. On push and pull_request the input is empty,
  so nothing changes there. The arm legs stay on ubuntu-24.04-arm. Only
  main publishes, so a dispatch from the branch never does.
  upstream-zig.yaml's ubuntu-latest leg has no such input.

## The lock

`pixi lock` (not `pixi update`) at 2026-10-08 12:45 EDT. The old lock
acts as preferences, so every existing record stayed. A script compared
the old lock (a7d3dcec, main's) with the new one, per environment and
platform, and the package records themselves:
- 546 records to 552. None removed, none changed. The top-level
  metadata is identical. `git diff --text pixi.lock` removes no line.
- Added records: binutils 2.46.1 and binutils_impl_linux-* 2.46.1
  (`_102`), strace 7.2, for linux-64 and linux-aarch64.
- default, full, openblas, full-openblas and pkg on linux (both
  arches): + binutils, binutils_impl_linux-*, strace (default 107 to
  110 packages).
- minimal on linux: the same plus ld_impl_linux-*, which the R envs
  already had (62 to 66).
- wheel on linux: + binutils, binutils_impl_linux-*, sysroot_linux-*
  2.28 and kernel-headers_linux-* 4.18.0, the records the R envs already
  use (23 to 27). sysroot is about 24 MB to download.
- Identical: all osx-64, osx-arm64 and win-64 lists, 19 of 33.
- `pixi lock --check` passes. `pixi run -e minimal minimal-check`
  passes (66/66/55/55 packages).

## Tested

Done while writing this branch, on linux-64 (the worktree, lock
7aef60ff):
- `pixi lock --check`: up to date.
- `pixi run --locked -e minimal minimal-check`: the four platforms
  pass. A copy of the lock with font-ttf-ubuntu and libdeflate injected
  into minimal linux-64 and libglib and libexpat into minimal osx-arm64
  fails, naming those four (exit 1).
- `pixi run --locked rzig-test`: passed (parity: 41 identical, 26
  identical but for rzig's own-environment -L, 18 deliberate
  differences, 0 failed).
- Tools in the envs: objdump, strip, strace and readelf resolve to
  `.pixi/envs/default/bin` and `.pixi/envs/minimal/bin`; readelf to
  `.pixi/envs/wheel/bin`. conda's strace traces here (both preflights,
  `trace=execve` and `trace=?openat,?open`). No file is owned by two
  packages in default, minimal or wheel.
- Cache keys: the env's zig gives zig-2588079272-305049256 (zig,
  libLLVM.so.21.1, libclang-cpp.so.21.1; it was zig-3257041897-30115392);
  upstream zig keeps zig-823780232-172641672; no zig gives zig-none.
- `cannot_check`: with CI unset it prints the note and the script goes
  on; with CI=true it exits 1.
- shellcheck: the five changed scripts have the same warnings as
  before; check-minimal.sh is clean. actionlint 1.7.12: build.yaml and
  build-r.yaml are clean.
- rattler-build 0.76.1 (`-e pkg`) lists both `--error-*` flags.

The test round, 2026-10-08, times EDT. Lock 7aef60ff before and after
on every machine (the worktree, omicron's two copies, kappa's copy);
nobody wrote the lock or made a git write. One test run per checkout.
Every pixi command used `--locked`, except omicron's osx-64 copy
(below).

- **linux-64** (the worktree, 12:51-13:17). All passed.
  - default: rzig-test (41 identical, 26 identical but for rzig's
    own-environment -L, 18 deliberate differences, 0 failed), build
    (2 min 50 s), verify-tree ("runtime worst 2.17
    (lib/libglib-2.0.so.0)"), smoke, contract, hermetic ("programs
    started:", traced by the env's strace), verify-package ("TLS trust
    verified (no CA file read from the build env)"). objdump, strip,
    strace and readelf resolve to .pixi/envs/default/bin (objdump
    2.46.1, strace 7.2).
  - `CI=true`: verify-tree, hermetic and verify-package on default, and
    verify-tree and verify-package on minimal, pass with no
    cannot_check line.
  - minimal: build, verify-tree ("runtime worst 2.17
    (lib/libstdc++.so.6)"), verify-package, minimal-check (66/66/55/55).
    All 22 strip calls of vendor-libs.sh run the env's strip
    (libstdc++.so.6: 3.4 MB, no .debug_ section). Then `-e wheel wheel`
    (manylinux_2_17, 48.2 MiB) and wheel-test. wheel-test.sh's own 3
    readelf calls run the env's readelf; 5 more run the host's, from R's
    own R CMD INSTALL under the PATH a pip user has (/usr/bin:/bin), as
    intended.
  - `-e pkg conda-package` (3 min 36 s) with both `--error-*` flags:
    r-zig-slim-4.6.1-hb0f4dca_4 and r-zig-toolchain-4.6.1-hf9c1e0e_4,
    both outputs' tests passed.
  - Upstream zig (`ZIG_BIN="$(pixi run fetch-zig)" pixi run build`):
    built into build/zig-cache/zig-823780232-172641672, the old
    formula's name (a new directory in this worktree, so not a reuse),
    and verify-tree passed. dist/R-4.6.1-slim-zig is now that tree.
  - binutils changes nothing that ships: the tree's file list, Makeconf
    and Renviron match a tree built without binutils on PATH
    (feat-stress-suite's), and lib/R/bin/toolchain still holds only the
    five rzig compilers. This stands in for the regenerate-rule capture,
    which was not run.
- **Negative tests** (linux-64; scratch copies, scratch PATHs or tools
  hidden by an exported `command` function, since env.sh's PATH always
  ends in /usr/bin:/bin, where this machine has objdump and strace):
  - D9: a lock copy with glib in minimal's linux-64 list: `error:
    minimal (linux-64) has packages it must not have: glib`, exit 1.
  - D11: hermetic-check with no strace, or a strace that cannot trace;
    verify-tree with no objdump, or an objdump that prints nothing;
    verify-bundle with no strace. With `CI=true` each exits 1 with its
    error; without, each prints its note and passes.
  - D8: with a scratch zig and fake lib files, the key changes when
    libLLVM or libclang-cpp changes, ignores a libLLVM-21.so symlink and
    a libLLVMSupport.a, and holds on a rerun. No zig gives zig-none.
  - D12: a scratch recipe whose two outputs package one file warns
    without `--error-overlapping-files` (exit 0) and fails with it
    (exit 1, "which will clobber each other").
- **osx-arm64** (omicron, a new copy, 12:52-13:00). Install of default
  and pkg, rzig-test (42/42), build (2 min 16 s), verify-tree, hermetic
  and verify-package with `CI=true` (no cannot_check line), smoke,
  minimal-check (66/66/55/55), `-e pkg conda-package` with both flags
  (r-zig-slim-4.6.1-h41cfa24_4, r-zig-toolchain-4.6.1-h6f07afa_4, both
  tests passed, no overlapping-file or unused-staging message). The key
  is zig-449293785-234326480: bin/zig, lib/libLLVM.21.1.dylib and
  lib/libclang-cpp.21.1.dylib, which `otool -L` shows zig loads (the
  zig alone: 4103495474-27717392). Upstream zig's key stays
  zig-2230984005-185346592 (key only, no build). All passed.
- **osx-64 under Rosetta** (omicron, a platforms-sed copy,
  13:02-13:08). `--frozen`, since the sed makes `--locked` refuse the
  manifest. rzig-test (42/42), build into zig-2069773851-249628048 (the
  zig alone: 3304267335-30901040), verify-tree with `CI=true`, smoke.
  All passed. No Falcon kill on either copy.
- **win-64** (kappa, a new copy, to 13:15). Install of default and pkg,
  rzig-test (29 passed, 13 skipped), build (43 conda DLLs vendored),
  verify-tree, smoke, verify-package (relocatable; OpenMP probes on 2
  threads), `-e pkg conda-package` with both flags
  (r-zig-slim-4.6.1-h9490d1a_4, r-zig-toolchain-4.6.1-hc21f241_4, both
  tests passed, no overlapping-file or unused-staging message). The key
  stays zig-4052344430-170182656 (the exe alone; Library/lib has no
  libLLVM or libclang-cpp). conda-package's "Overlinking against" the
  pkg env's `Library/bin/zstd.dll` warnings and a "hash mismatch" in
  kappa's shared rattler cache come from before this branch. All
  passed.
- **Review** (linux-64).
  - Its own lock comparison (a7d3dcec from git, 7aef60ff): 546 to 552
    records, none removed or changed, the top-level metadata identical,
    every osx-64, osx-arm64 and win-64 list identical; the changed
    lists gain only binutils, binutils_impl_linux-* and strace (default,
    full, openblas, full-openblas, pkg), plus ld_impl_linux-* (minimal),
    or binutils, binutils_impl_linux-*, sysroot_linux-* and
    kernel-headers_linux-* (wheel). `pixi run --locked` accepts it.
  - bash 3.2.57 (macOS's /bin/bash; the wheel env has no bash, so
    wheel-test.sh, which sources env.sh, can run under it): env.sh gives
    zig-none with no zig, zig-2588079272-305049256 with the env's and
    zig-823780232-172641672 with upstream's; check-minimal.sh passes,
    and fails naming glib and font-ttf-ubuntu on an injected lock;
    cannot_check notes, and exits 1 with `CI=true`.
  - D10's facts, from the default env's conda-meta: glibconfig.h
    (lib/glib-2.0/include) is in glib only; the unversioned
    libglib-2.0.so and libgobject-2.0.so are glib-tools'; glib depends
    on python, glib-tools and libglib; win-64's libharfbuzz-devel
    depends on glib.
  - shellcheck 0.11.0: the five changed scripts have the same warnings
    as before; check-minimal.sh is clean. actionlint 1.7.12: build.yaml
    and build-r.yaml are clean.
  - The hermetic-check change proposed under "Open", in a scratch copy
    of scripts/ with strace hidden: `CI=true` runs the empty-PATH check
    ("tier 0/1 scenario OK"), then exits 1; without CI it notes and
    passes.
- Not tested: linux-aarch64 (CI only); `pixi run check`; the full,
  openblas and full-openblas envs; hermetic and conda-package on
  osx-64; minimal and wheel on macOS; upstream-zig builds on macOS and
  Windows; hermetic on win-64; the regenerate-rule capture; any CI run,
  D13's dispatch included.

## CI to watch

- **The pull request.** build.yaml's 20 jobs. On the minimal legs, "Check
  minimal's locked packages" passes on all four. On linux, hermetic
  prints "programs started:" and verify-tree a non-empty "runtime
  worst"; no "note: ... (an error in CI)" line anywhere, since CI would
  have failed instead. The five conda-package legs pass with the
  `--error-*` flags. setup-pixi's caches miss once on linux (the lock
  changed); macOS and Windows should hit.
- **D13's dispatch, before 2026-10-19.** After the branch is pushed:
  `gh workflow run build.yaml --ref chore-deps-ci-checks -f
  linux_runner=ubuntu-26.04`. Read the lines in
  chore-lock-and-ci-refresh/PLAN.md, "Ubuntu 26.04". This run also
  tests E3 and D11 on 26.04. Result: _pending_.
- **After the merge.** The push to main publishes with
  `--skip-existing`; the recipe did not change, so universe keeps build
  4.

## Risks

- binutils_impl puts headers (bfd.h, ansidecl.h, plugin-api.h, ...) and
  static libraries (libbfd.a, libopcodes.a, ...) into <env>/include and
  <env>/lib, which are on R's `-I` and on rzig's R_ZIG_EXTRA_ENV path.
  No R source includes those header names (the prep's grep of
  R-4.6.1/src).
- minimal's vendored libraries are now stripped by binutils 2.46.1, not
  the host's 2.42.
- A runner or machine where ptrace is blocked now fails hermetic and
  verify-package in CI. Locally it is a note.
- A deny-list misses a name it does not list. If pixi's JSON output
  changes, check-minimal.sh fails with "read no minimal packages".

## Records to correct

They live on feat-standalone-toolchain (64acfbd and later), not on this
branch, so they are not edited here. Once the user re-decides D10:
- chore-lock-and-ci-refresh/PLAN.md, D10: "pango links only libglib" is
  wrong for R (glibconfig.h and the unversioned link names come with
  glib).
- feat-no-host-paths/PLAN.md, follow-up PR (i): "D10 + E3 (libglib
  instead of glib; ...)".
- feat-standalone-toolchain phase 4: add "drop glib from r-zig-slim's
  run requirements" next to E2 and D7.

## Open

- D10: keep glib (this branch) and drop the recipe's glib run
  dependency at phase 4? Pending with the user.
- wheel-test.sh still prints a note, not an error, when neither readelf
  nor otool is found. With binutils in the wheel env that cannot happen
  on linux; it was left as it was.
- hermetic-check.sh (the review's proposal, applied after the tests):
  in CI, cannot_check exited before `run`, so "checked with an empty
  PATH only" was not true there. The cannot_check line now comes after
  `run`: the message is true both ways, the old order is back (the note
  came after `run`), and in CI the empty-PATH check still runs before
  the failure. Tested by the review in a scratch copy (CI=true: "tier
  0/1 scenario OK", then exit 1; without CI: the note, exit 0).
- D11's reach: env.sh's PATH ends in /usr/bin:/bin, so if the env lacked
  binutils or strace, the host's would be used without a word;
  cannot_check fires only when neither exists, ptrace is blocked, or
  objdump reads nothing. pixi.toml holds where the tools come from.
- Host tools still run on linux, for a later PR: verify-tree.sh runs
  /usr/bin/cmp and find (no diffutils or findutils in the env),
  vendor-libs.sh /usr/bin/ldd and find, and the wheel task /usr/bin/bash
  and dirname (the wheel env has only python and binutils).
- win-64 conda-package warns "Overlinking against" the pkg env's
  `Library/bin/zstd.dll` for R.dll and the toolchain's binutils:
  rattler-build resolves zstd.dll from the pkg env on PATH, not the host
  prefix. From before this branch; worth a look.
