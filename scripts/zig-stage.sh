#!/usr/bin/env bash
# Run stage.sh against the zig-built prefix. Mirrors zig-build.sh's own
# prefix derivation (see zig-smoke.sh/zig-contract.sh) so callers (CI,
# `pixi run install`) don't need to know $FLAVOR to find it. Normalizes the
# zig-built prefix for packaging (dual rpath, launcher shims, etc — see
# stage.sh's own header comment).
. "$(dirname "$0")/env.sh"

export R_INSTALL_PREFIX="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
exec bash "$(dirname "$0")/stage.sh"
