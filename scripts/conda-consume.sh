#!/usr/bin/env bash
# The conda packages as a user consumes them: a fresh pixi workspace from
# this checkout's dist/conda (then universe and conda-forge, as stress.R
# --conda orders them), one environment per group, and the recipe's tests
# run through pixi's activation by bare Rscript (win-64:
# Library/bin/Rscript.bat, which rattler-build's test phase cannot run).
# CI runs it on every conda-package leg before the publish; each host runs
# it after conda-package (feat-standalone-toolchain phase 4; PHASE4 Cg8).
# One manifest, one environment per package: the base alone (on Windows
# also test-win.R, as the recipe's own test of r-zig-slim), base +
# compilers, base + build tools, base + extras (cmake,
# feat-extras-group), r-zig-toolchain, the metapackage of the groups
# (test-toolchain.R through activation, as a user's `pixi add
# r-zig-toolchain` gets it; PHASE7 open point P a), base + R's
# recommended packages (feat-recommended-packages), base + the tcltk
# add-on (b13-recipe; not on win-arm64, which has no r-zig-tcltk) and, on
# Windows where the recipe has it (build 14 on, b14-l4), base + compilers
# + r-zig-native-tools, with no MSYS2 in the environment.
# Removing a group is the package manager's, and the files that move
# between packages are the upgrade test's.
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
channels = ["$ch", "https://prefix.dev/universe", "conda-forge"]
platforms = ["$PLAT"]

[dependencies]
r-zig-slim = "*"

[feature.compilers.dependencies]
r-zig-compilers = "*"

[feature.build-tools.dependencies]
r-zig-build-tools = "*"

[feature.extras.dependencies]
r-zig-extras = "*"

[feature.toolchain.dependencies]
r-zig-toolchain = "*"

[feature.recommended.dependencies]
r-zig-recommended = "*"

[environments]
compilers = ["compilers"]
build-tools = ["build-tools"]
extras = ["extras"]
toolchain = ["toolchain"]
recommended = ["recommended"]
EOF
tests="default:test-preflight.R compilers:test-compilers.R build-tools:test-build-tools.R extras:test-extras.R toolchain:test-toolchain.R recommended:test-recommended.R"
if [ "$PLAT" != win-arm64 ]; then
  cat >> "$T/pixi.toml" << EOF

[feature.tcltk.dependencies]
r-zig-tcltk = "*"

[environments.tcltk]
features = ["tcltk"]
EOF
  tests="$tests tcltk:test-tcltk.R"
fi
if [ "$OS" = windows ]; then
  # r-zig-slim's Windows recipe test runs test-win.R before the preflight
  tests="default:test-win.R $tests"
  # r-zig-native-tools, when this checkout's recipe builds it (its test
  # file is there): the compilers and the native set, no r-zig-build-tools
  if [ -f "$rec/test-native-tools.R" ]; then
    cat >> "$T/pixi.toml" << EOF

[feature.native-tools.dependencies]
r-zig-compilers = "*"
r-zig-native-tools = "*"

[environments.native-tools]
features = ["native-tools"]
EOF
    tests="$tests native-tools:test-native-tools.R"
  fi
fi
# the zig cache conda-package's recipe tests filled (pixi.toml)
export R_ZIG_TEST_ZIG_CACHE="$cache"
for t in $tests; do
  echo "== ${t%%:*}: ${t#*:}"
  "$pixi" run --manifest-path "$T/pixi.toml" -e "${t%%:*}" Rscript "$rec/${t#*:}"
done
