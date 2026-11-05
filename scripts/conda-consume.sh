#!/usr/bin/env bash
# The conda packages as a user consumes them: a fresh pixi workspace from
# this checkout's dist/conda (then conda-forge and universe, as stress.R
# --conda orders them), one environment per group, and the recipe's tests
# run through pixi's activation by bare Rscript (win-64:
# Library/bin/Rscript.bat, which rattler-build's test phase cannot run).
# CI runs it on every conda-package leg before the publish; each host runs
# it after conda-package (feat-standalone-toolchain phase 4; PHASE4 Cg8).
# One manifest, four environments: the base alone, base + compilers,
# base + build tools, and r-zig-toolchain, the metapackage of both groups
# (test-toolchain.R through activation, as a user's `pixi add
# r-zig-toolchain` gets it; PHASE7 open point P a). Removing a group is
# the package manager's, and the files that move between packages are the
# upgrade test's.
. "$(dirname "$0")/env.sh"
ch="$ROOT/dist/conda"; rec="$ROOT/recipe"; cache="$ROOT/build/conda-test-zig-cache"
[ -d "$ch/$PLAT" ] || { echo "error: no $ch/$PLAT: run 'pixi run -e pkg conda-package' first" >&2; exit 1; }
# env.sh's PATH has the pkg env and /usr/bin only: pixi by the path pixi
# run gives its tasks (as check-minimal.sh)
pixi="${PIXI_EXE:-pixi}"
# pixi.exe reads these as Windows paths (env.sh's ZIG_BIN does the same),
# and bash runs pixi.exe by its MSYS path
if command -v cygpath > /dev/null 2>&1; then
  ch="$(cygpath -m "$ch")"; rec="$(cygpath -m "$rec")"; cache="$(cygpath -m "$cache")"
  pixi="$(cygpath -u "$pixi")"
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# this checkout's pixi workspace must not leak in (as stress.R --conda)
unset PIXI_PROJECT_MANIFEST PIXI_PROJECT_ROOT PIXI_PROJECT_NAME PIXI_PROJECT_VERSION \
  PIXI_ENVIRONMENT_NAME PIXI_ENVIRONMENT_PLATFORMS PIXI_IN_SHELL PIXI_PROMPT R_ZIG_EXTRA_ENV
cat > "$T/pixi.toml" << EOF
[workspace]
name = "r-zig-consume"
channels = ["$ch", "conda-forge", "https://prefix.dev/universe"]
platforms = ["$PLAT"]

[dependencies]
r-zig-slim = "*"

[feature.compilers.dependencies]
r-zig-compilers = "*"

[feature.build-tools.dependencies]
r-zig-build-tools = "*"

[feature.toolchain.dependencies]
r-zig-toolchain = "*"

[environments]
compilers = ["compilers"]
build-tools = ["build-tools"]
toolchain = ["toolchain"]
EOF
# the zig cache conda-package's recipe tests filled (pixi.toml)
export R_ZIG_TEST_ZIG_CACHE="$cache"
for t in default:test-preflight.R compilers:test-compilers.R build-tools:test-build-tools.R toolchain:test-toolchain.R; do
  echo "== ${t%%:*}: ${t#*:}"
  "$pixi" run --manifest-path "$T/pixi.toml" -e "${t%%:*}" Rscript "$rec/${t#*:}"
done
