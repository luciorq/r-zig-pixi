#!/usr/bin/env bash
# rzig's tests (feat-no-host-paths F3): its unit tests on this machine,
# then, on linux, the parity test against the bash shims in toolchain/
# (parity-test.sh: every OS's command lines, from one machine). Needs no R
# build: `pixi run rzig-test`. The repo's build.zig runs the same unit
# tests as `zig build rzig-test`.
. "$(dirname "$0")/../../../scripts/env.sh"
here=$(cd "$(dirname "$0")" && pwd)

# zig as zig-build.sh finds it (on win-64 conda-forge's real binary is
# x86_64-w64-mingw32-zig; `zig` is a .bat MSYS cannot run)
ZIG="${ZIG_BIN:-$(command -v zig || command -v x86_64-w64-mingw32-zig)}"
"$ZIG" build --build-file "$here/build.zig" test --summary all
if [ "$OS" = linux ]; then
  ZIG="$ZIG" bash "$here/parity-test.sh"
fi
