#!/usr/bin/env bash
# rzig's tests (feat-no-host-paths F3): its unit tests on this machine,
# then, on linux, the parity test against the bash shims in toolchain/
# (parity-test.sh: every OS's command lines, from one machine). Needs no R
# build: `pixi run rzig-test`. The repo's build.zig runs the same unit
# tests as `zig build rzig-test`.
#
# With an installed tree's prefix, `pixi run rzig-test dist/slim/R-4.6.1-zig`,
# also smoke-test.sh against it, on linux: real compiles through rzig,
# then R packages (C, C++, OpenMP, Fortran with flang) installed through
# that tree's R CMD INSTALL, which builds them with rzig build, and loaded
# (tests-T12: its part 2 ran in no task). CI runs rzig-test before it
# builds R, so it passes none there.
. "$(dirname "$0")/../../../scripts/env.sh"
here=$(cd "$(dirname "$0")" && pwd)

# zig as zig-build.sh runs it: env.sh's $ZIG (ZIG_BIN, else the env's)
echo "rzig-test: zig = $ZIG ($("$ZIG" version))"
"$ZIG" build --build-file "$here/build.zig" test --summary all
if [ "$OS" = linux ]; then
  ZIG="$ZIG" bash "$here/parity-test.sh"
  if [ $# -ge 1 ]; then
    ZIG="$ZIG" bash "$here/smoke-test.sh" "$1"
  fi
fi
