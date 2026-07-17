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

bash scripts/configure-r.sh
bash scripts/build-r.sh
bash scripts/install-r.sh
