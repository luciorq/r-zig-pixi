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
# stamp, as `zig build fetch` does), so zig-build.sh applies zigbuild/patches/
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
# On Windows, winCairo.dll links cairo, which R's build compiles from the
# recipe's cairo source (-Dcairo; zigbuild/cairo.zig).
cairo=()
if [ -d cairo-src ]; then
  cairo=("-Dcairo=$(cygpath -m "$PWD/cairo-src")")
fi
# Tcl/Tk on top of slim (-Dtcltk: HAVE_TCLTK, the tcltk package's DLL and
# its R code, from the full config's Tcl/Tk keys) for the add-on
# r-zig-tcltk, against the host's tk 8.6; not on win-arm64, where
# conda-forge has no tk 8.6 and the base keeps the stub (recipe.yaml)
tcltk=()
if [ "${target_platform:?}" != win-arm64 ]; then
  tcltk=(-Dtcltk=true)
fi
bash scripts/zig-build.sh "${cairo[@]}" "${tcltk[@]}"
# The toolchain build (zigbuild/toolchain/build.zig), into the env itself,
# as the dev tree's groups are installed into dist/toolchain/R-<ver>-zig.
# Here too conda's own packages provide the groups' files where they are
# looked for (llvm-openmp's omp.h), so it installs only what it builds:
# on Windows usr/bin/pkgconf.exe and pkg-config.exe, from the recipe's
# pkgconf source (-Dpkgconf; zigbuild/toolchain/pkgconf.zig), usr/bin/zip.exe
# from its zip source (-Dzip; zigbuild/toolchain/zip.zig), and native/
# (busybox-w32, make, zip and pkgconf; -Dbusybox, -Dmake;
# zigbuild/toolchain/busybox.zig), on unix usr/bin/make, from the
# recipe's make source (-Dmake; zigbuild/make/build.zig).
# r-zig-build-tools owns usr/, r-zig-native-tools native/, and
# r-zig-slim owns rzig, the rest of R_HOME/bin/toolchain (B28), the
# binutils' names included (feat-win-zig-binutils).
srcs=()
if [ -d pkgconf-src ]; then
  srcs+=("-Dpkgconf=$(cygpath -m "$PWD/pkgconf-src")")
fi
if [ -d make-src ]; then
  case "$target_platform" in
    win-*) srcs+=("-Dmake=$(cygpath -m "$PWD/make-src")") ;;
    *) srcs+=("-Dmake=$PWD/make-src") ;;
  esac
fi
if [ -d busybox-src ]; then
  srcs+=("-Dbusybox=$(cygpath -m "$PWD/busybox-src")")
fi
if [ -d zip-src ]; then
  srcs+=("-Dzip=$(cygpath -m "$PWD/zip-src")")
fi
R_TOOLCHAIN_PREFIX="$PREFIX" bash scripts/zig-toolchain.sh "${srcs[@]}"
# R's recommended packages (feat-recommended-packages PLAN.md), into the
# env with the env's R: r-zig-recommended's files (the recipe's globs;
# r-zig-slim leaves them out). Last: they need R and, for Matrix's
# makefile rules, make, which the build env has.
R_RECOMMENDED_PREFIX="$PREFIX" bash scripts/zig-recommended.sh
# Licence texts for the packages' info/licenses (recipe/recipe.yaml's
# license_file globs, which read the work dir, not $PREFIX). zig's: the
# build env's zig package's own info/licenses (zig's MIT text for
# compiler_rt, and the libc start files and libunwind zig links), from the
# package cache its conda-meta record names. The recommended packages':
# the LICENCE files R CMD INSTALL put in their directories (Matrix's).
# r-zig's own MIT LICENSE comes in as a recipe source.
bp="$BUILD_PREFIX" hp="$PREFIX"
if command -v cygpath >/dev/null; then bp="$(cygpath -u "$bp")" hp="$(cygpath -u "$hp")"; fi
zig_pkg="$(sed -n 's/.*"extracted_package_dir": *"\([^"]*\)".*/\1/p' "$bp"/conda-meta/zig-[0-9]*.json | sed 's|\\\\|/|g')"
[ -d "$zig_pkg/info/licenses" ] || { echo "build.sh: no zig licences in the package cache ('$zig_pkg')" >&2; exit 1; }
mkdir -p licenses/zig licenses/recommended
cp -R "$zig_pkg/info/licenses/." licenses/zig/
for f in "$hp"/lib/R/library/*/LICEN[CS]E* "$hp"/Library/lib/R/library/*/LICEN[CS]E*; do
  [ -f "$f" ] || continue
  pkg="$(basename "$(dirname "$f")")"
  mkdir -p "licenses/recommended/$pkg"
  cp "$f" "licenses/recommended/$pkg/"
done
