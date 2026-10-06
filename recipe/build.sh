#!/usr/bin/env bash
# rattler-build entry point: drive the exact same scripts the pixi tasks
# use, pointed at rattler's work dir and host prefix.
set -euxo pipefail

export PIXI_PROJECT_ROOT="$PWD"
# set by the recipe (a staging output has no PKG_VERSION)
export R_VERSION="${R_VERSION:-${PKG_VERSION:?}}"
# internal tzcode needs zoneinfo; host tzdata provides it. TZ pinned for
# reproducible doc builds regardless of the build machine's zone.
export TZDIR="$PREFIX/share/zoneinfo"
export TZ=UTC
export R_INSTALL_PREFIX="$PREFIX"
# scripts resolve headers/libs and the Fortran runtime via CONDA_PREFIX;
# in a rattler build those live in the host prefix
export CONDA_PREFIX="$PREFIX"

mkdir -p build
mv R-src "build/R-$R_VERSION"
# rattler-build extracted a pristine source: mark it as such (empty patch
# stamp, as fetch-r.sh does), so zig-build.sh applies zigbuild/patches/
# to it instead of extracting it again from a tarball it doesn't have.
: > "build/R-$R_VERSION/.r-zig-patches"
chmod +x scripts/*.sh

# zig build alone (no autoconf, no make) — the default path since
# Milestone 5's F1-F6 (see .github/devdocs/feat-zig-build/). $R_INSTALL_
# PREFIX is already rattler's own $PREFIX (set above), so zig-build.sh's
# PREFIX_ZIG resolves to it directly (no "-zig" suffix leaks into the
# conda package). zig build installs the final tree: relative rpaths,
# relocatable launchers, rzig as the compilers in lib/R/bin/toolchain
# (feat-no-host-paths PLAN.md, F1 and F3); nothing runs after it. What a
# standalone tree takes from the env (build.zig's installEnvRuntime: the
# CA bundle, fontconfig's configuration, Tcl/Tk; vendor-libs.sh: the
# shared libraries) is left out here, since the prefix is the env: its
# own packages provide all of it. On Windows, etc/Renviron.site points
# tcltk at the tk package's DLLs instead (MY_TCLTK, installEnvRuntime).
bash scripts/zig-build.sh
