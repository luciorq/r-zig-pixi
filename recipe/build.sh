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
# PREFIX is already rattler's own $PREFIX (set above), so env.sh's PREFIX
# is that, not a dev tree's dist/<flavor>/R-<ver>-zig. zig build installs
# the final tree: relative rpaths, relocatable launchers, rzig as the
# compilers in lib/R/bin/toolchain (feat-no-host-paths PLAN.md, F1 and
# F3); nothing rewrites it after. What a standalone tree takes from the env
# (build.zig's installEnvRuntime: the CA bundle, fontconfig's
# configuration, Tcl/Tk; vendor-libs.sh: the shared libraries) is left
# out here, since the prefix is the env: its own packages provide all of
# it. On Windows, etc/Renviron.site points tcltk at the tk package's DLLs
# instead (MY_TCLTK, installEnvRuntime).
bash scripts/zig-build.sh
# The toolchain build (zigbuild/toolchain/build.zig), into the env itself,
# as the dev tree's groups are installed into dist/toolchain/R-<ver>-zig.
# Here too conda's own packages provide the groups' files where they are
# looked for (llvm-openmp's omp.h, make), so on unix it installs nothing.
# On win-64 it installs R_HOME/bin/toolchain/binutils/: conda-forge's
# MinGW binutils, which Makeconf.win names by path under R_HOME, with
# their SOURCES and LICENSES/ (feat-standalone-toolchain B24, B41).
# r-zig-toolchain owns them, with the rest of R_HOME/bin/toolchain.
R_TOOLCHAIN_PREFIX="$PREFIX" bash scripts/zig-toolchain.sh
