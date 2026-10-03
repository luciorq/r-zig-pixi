#!/usr/bin/env bash
# Run package-standalone.sh against the zig-built prefix (staged by
# `pixi run build`, which installs the final tree). Mirrors zig-smoke.sh's own prefix
# derivation so callers don't need to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

export R_INSTALL_PREFIX="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
exec bash "$(dirname "$0")/package-standalone.sh"
