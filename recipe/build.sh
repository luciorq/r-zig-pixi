#!/usr/bin/env bash
# rattler-build entry point: drive the exact same scripts the pixi tasks
# use, pointed at rattler's work dir and host prefix.
set -euxo pipefail

export PIXI_PROJECT_ROOT="$PWD"
export R_VERSION="$PKG_VERSION"
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
chmod +x toolchain/zig-* scripts/*.sh

# zig build alone (no autoconf, no make) — the default path since
# Milestone 5's F1-F6 (see .github/devdocs/feat-zig-build/). $R_INSTALL_
# PREFIX is already rattler's own $PREFIX (set above), so zig-build.sh's
# PREFIX_ZIG resolves to it directly (no "-zig" suffix leaks into the
# conda package). stage.sh normalizes the result for conda-package use
# (dual rpath, launcher shims, etc) — same tail call install-r.sh used to
# make for the legacy path.
bash scripts/zig-build.sh
bash scripts/stage.sh
