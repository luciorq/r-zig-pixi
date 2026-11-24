# b13-make-aarch64: zig-built GNU make crashes in the linux-aarch64 conda package

Build 13, branch build13 (PR #57, head cc7d810), worktree, uncommitted.
Tested on delta (linux-64) with qemu-aarch64 (conda-forge
qemu-execve-aarch64 11.0.3, ubuntu:24.04 arm64 rootfs as `-L`).

## Problem

build-r run 45447900455, job 138636635576 "conda-package /
linux-aarch64": in r-zig-toolchain's package test, `make -f
'$PREFIX/lib/R/etc/Makeconf' -f '$PREFIX/lib/R/share/make/shlib.mk'
compilers` exits 139 (Segmentation fault) and `R CMD INSTALL` of rzigc
through make fails. The other conda-package legs and every standalone leg
(ubuntu-24.04-arm / toolchain, default, full, openblas, minimal) pass,
with the same make.

## Findings

| id | finding | evidence |
|---|---|---|
| F1 | Cause: rattler-build relinks the package's make with patchelf (`Relinking "make" (patchelf)`, job log line 4702; the only patchelf relink in the run). make has no RUNPATH, so patchelf 0.19.3 moves the program headers, .interp, .dynsym/.dynstr and .dynamic into a new LOAD segment below the image. On aarch64 (64K segment alignment) that segment is 0xff0000-0xff6148, so the old image base 0x1000000 is no longer mapped. lld defines `__dso_handle` at the image base, and glibc's `atexit` (libc_nonshared, zig's copy) loads `__dso_handle`'s value: make calls atexit early in main and faults reading 0x1000000. On x86_64 (4K alignment) the new segment is 0xfff000-0x10051e8 and covers the old base, so the same rewrite runs | qemu `-strace`: `SIGSEGV si_code=2 si_addr=0x0000000001000000` after main's fstat(1)/fstat(2); qemu `-d cpu` last PC 0x1044238 = `adrp x8, 0x1000000; ldr x2, [x8]; b __cxa_atexit@plt` (atexit). `readelf -l` before/after patchelf: first LOAD 0x1000000 (R) becomes LOAD 0xff0000 (RW, 0x6148) + LOAD 0x1005f88; x86_64: 0xfff000 (0x61e8) |
| F2 | The make the toolchain build makes is fine on aarch64; the crash needs the packaging rewrite | Cross-built on delta (`-Dtarget=aarch64-linux-gnu.2.17`): sha256 7835653e... = the toolchain-Linux-ARM64 artifact's usr/bin/make and its SOURCES line (reproducible). Under qemu it runs a `$(shell)`/patsubst makefile and the failing command shape (`-f Makeconf -f shlib.mk compilers` of the standalone-default-ubuntu-24.04-arm tree): rc 0. After `patchelf --set-rpath '$ORIGIN/../../../../../lib'` (with or without --force-rpath): 291720 bytes = the package's 284.88 KiB, rc 139, as CI. Same with upstream zig's build (sha256 65e86d1d...): rc 0, then 139 after patchelf |
| F3 | Not the cause: config/linux.h (x86_64 capture) has no arch-specific macros (no SIZEOF_*, STACK_DIRECTION, C_ALLOCA); sanitizers are off (`.sanitize_c = .off`), optimize ReleaseFast | grep of config/linux.h; zigbuild/make/build.zig |
| F4 | patchelf touched no other file in the run: the other ELF files (R, libR.so, modules) already have a RUNPATH and are rewritten in place by rattler-build's own relinker | `grep '(patchelf)'` over the linux-64 and linux-aarch64 job logs: only make |

## Decisions

| id | question | options (chosen ★) | reason | who, date |
|---|---|---|---|---|
| D1 | How to keep make intact in the package | (a) ★ `build.dynamic_linking.binary_relocation: false` on r-zig-build-tools (all platforms); (b) link make with a long dummy RUNPATH so rattler-build can rewrite it in place; (c) keep conda-forge's make on linux-aarch64; (d) avoid atexit/__dso_handle in make | (a): the group's tools link the system libc alone and need no rpath; the package then ships the bytes usr/SOURCES records, as the standalone tree. (b) is a workaround in the binary for a packaging step that has nothing to do; (c) splits the build path by platform; (d) patches make for a linker/patchelf interaction any lld-linked program has | default, 2026-11-24 |
| D2 | How the package test catches a rewrite | ★ test-build-tools.R (unix): usr/bin/make's sha256 is SOURCES' `file: make -> bin/make` line, and it runs a makefile with `$(shell)` and a recipe (as the Windows block checks pkgconf against SOURCES) | The toolchain test caught the crash only indirectly (R CMD INSTALL through make); a sha check also catches a rewrite that does not crash (linux-64's make was rewritten too) | default, 2026-11-24 |

## Changes

- recipe/recipe.yaml: r-zig-build-tools `build.dynamic_linking.binary_relocation: false`, with the reason.
- recipe/test-build-tools.R: unix check of make's sha256 against usr/SOURCES and a makefile run.
- zigbuild/make/**: unchanged (F2, F3).

## Tests run (delta)

| test | result |
|---|---|
| `zig build --build-file zigbuild/make/build.zig test`, conda-forge zig 0.17.1 | 6/6 steps |
| same, upstream zig 0.17.1 (`pixi run fetch-zig`) | 6/6 steps |
| aarch64 cross-build (both zigs) under qemu-aarch64: makefile, and `-f Makeconf -f shlib.mk compilers` of the CI arm64 tree | rc 0 (both); after patchelf rc 139 (F1, F2) |
| `pixi run toolchain` + `pixi run verify-toolchain` (linux-64) | toolchain tree verified (usr/bin/make 4.4.1, SOURCES records) |
| `pixi run -e pkg conda-package` (linux-64) | all 7 outputs built and tested, 0 test failures; no `Relinking "make"` line; make in the package 225.26 KiB (was 284.88 KiB after patchelf); new check "build tools: the group's make is SOURCES' file and runs a makefile: OK"; toolchain test through make OK. The `Overlinking against libc.so.6/libdl.so.2` warnings for make were there before (CI linux-64 log) |

## Not verified

- linux-aarch64 conda-package itself: needs the CI leg (`full-ci` or the
  conda-package paths); delta has no aarch64 binfmt, and rattler-build
  under qemu was not attempted.
- macOS conda-package with relocation off: rattler-build no longer runs
  install_name_tool/codesign on make; zig signs it ad hoc at link time
  (the standalone macOS trees ship it so).

## Suggested commit message

    fix: ship the build tools' make without relinking (patchelf crashed it on linux-aarch64)
