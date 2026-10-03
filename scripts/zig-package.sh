#!/usr/bin/env bash
# Run package-standalone.sh, which archives the zig-built prefix (the
# final tree `pixi run build` installs and vendors). Mirrors zig-smoke.sh's
# own prefix derivation so callers don't need to know $FLAVOR to find it.
. "$(dirname "$0")/env.sh"

export R_INSTALL_PREFIX="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
exec bash "$(dirname "$0")/package-standalone.sh"
