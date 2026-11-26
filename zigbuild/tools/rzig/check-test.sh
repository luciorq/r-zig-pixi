#!/usr/bin/env bash
# End-to-end tests of rzig's own modes, the real binary in a fake
# installed tree: the check mode (check.zig: --rzig-check and its groups'
# texts and exit codes), `rzig build` (pkgbuild.zig: tiers, preflight,
# the build root) and `rzig build --shlib` (R CMD SHLIB's call). Cases
# that need a real zig, make or flang run when they are found. Linux only
# (test.sh); how rzig turns arguments into zig command lines for every OS
# is its unit tests' business.
#
#   zigbuild/tools/rzig/check-test.sh [path/to/rzig]
#
# Without an argument it builds rzig with $ZIG (default: zig on PATH).
# (These cases were the `check` part of parity-test.sh, whose reference,
# the bash shims in toolchain/, is gone.)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/rzig-check.XXXXXX")" && pwd -P)
trap 'rm -rf "$W"' EXIT

RZIG=${1:-}
if [ -z "$RZIG" ]; then
  # (zig's local cache out of the source tree, which the recipe copies)
  "${ZIG:-zig}" build --build-file "$here/build.zig" --cache-dir "${ZIG_LOCAL_CACHE_DIR:-$W/zig-cache}" --prefix "$W/rzig"
  RZIG=$W/rzig/bin/rzig
fi
RZIG=$(cd "$(dirname "$RZIG")" && pwd)/$(basename "$RZIG")

# tree NAME: an installed R_HOME/bin with copies of rzig, its link objects
# beside them, and what every linux C++ command needs (libstdcxx.zig):
# libstdc++'s headers' directories and runtime in the tree; empty fakes,
# which the stub never reads
cxx_triple="$(uname -m | sed 's/^arm64$/aarch64/')-conda-linux-gnu"
tree() {
  local tc=$W/$1/lib/R/bin/toolchain n
  mkdir -p "$tc" "$tc/libstdcxx-shim" "$W/$1/lib/gcc/$cxx_triple/15.3.0/include/c++/$cxx_triple"
  : > "$W/$1/lib/libstdc++.so.6"; : > "$W/$1/lib/libgcc_s.so.1"
  for n in zig-cc zig-cxx zig-ar zig-ranlib gcc g++ gcc-ar gcc-ranlib ar ranlib; do cp "$RZIG" "$tc/$n"; done
  # rzig's link objects beside it, as R's build installs them (rzig's
  # build.zig, linkObject): the ones that build made beside $RZIG (the
  # real builds below link dso_fini.o), else empty files
  for n in dso_fini.o cfguard.o clear_cache.o; do
    if [ -f "${RZIG%/*}/$n" ]; then cp "${RZIG%/*}/$n" "$tc/$n"; else : > "$tc/$n"; fi
  done
}
tree tree

# stub <path> [argv0]: stands in for zig (or python3), prints the child's
# ZIG_LIB_DIR when it has one, then its argv, one per line: the format of
# RZIG_PRINT_ARGV.
stub() {
  mkdir -p "$(dirname "$1")"
  {
    echo '#!/bin/sh'
    echo 'if [ -n "${ZIG_LIB_DIR+x}" ]; then printf "ZIG_LIB_DIR=%s\n" "$ZIG_LIB_DIR"; fi'
    if [ -n "${2:-}" ]; then echo "printf '%s\n' '$2' \"\$@\""; else echo 'printf "%s\n" "$0" "$@"'; fi
  } > "$1"
  chmod +x "$1"
}
touchf() { mkdir -p "$(dirname "$1")"; : > "$1"; }
# prog <path> <sh body>: a stand-in for flang or gfortran
prog() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n%s\n' "$2" > "$1"; chmod +x "$1"; }

# zig's stand-in: prints its argv, one per line
STUB=$W/stub/zig
stub "$STUB"
# a flang whose LLVM has the runtime archive
touchf "$W/llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a"
prog "$W/flang/flang" "echo '$W/llvm/lib/clang/23'"

pass=0 fail=0
check() {
  local name=$1; shift
  if "$@" > /dev/null 2>&1; then
    pass=$((pass + 1)); printf 'ok   %-8s %s\n' check "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %-8s %s\n' check "$name"
  fi
}

# --- the check mode (check.zig): the real binary ----------------------------------
# a group's tools found: one line on stdout, 0; one missing: its group's
# text, 127; a zig whose major.minor is not R's (rzig's own), or that does
# not run: 1
tc=$W/tree/lib/R/bin/toolchain
real_zig=$(command -v "${ZIG:-zig}" || :)
if [ -n "$real_zig" ]; then
  check "--rzig-check: zig and its version (ZIG_BIN)" \
    bash -c "env -i ZIG_BIN='$real_zig' '$tc/zig-cc' --rzig-check | grep -q '^zig-cc: compilers ok: zig [0-9]'"
  check "--rzig-check: the toolchain's zig/" \
    bash -c "mkdir -p '$W/realtc/lib/R/bin/toolchain/zig' && cp '$RZIG' '$W/realtc/lib/R/bin/toolchain/gcc' && ln -sf '$real_zig' '$W/realtc/lib/R/bin/toolchain/zig/zig' &&
      env -i '$W/realtc/lib/R/bin/toolchain/gcc' --rzig-check | grep -qF 'zig-cc: compilers ok: zig ' "
  check "--rzig-check=fortran: no flang, 127, the compilers group" \
    bash -c "env -i ZIG_BIN='$real_zig' PATH='$W/nothing' '$tc/zig-cc' --rzig-check=fortran > /dev/null 2> '$W/check.err'; [ \$? = 127 ] &&
      grep -q '^Compiling needs the r-zig compilers for R ' '$W/check.err' &&
      grep -q '^  standalone:  extract R-[^ ]*-compilers\.tar\.xz where you extracted R (zig [0-9.]*, libstdc++.s headers, flang and the OpenMP files)\$' '$W/check.err'"
  check "zig-fc --rzig-check checks flang too" \
    bash -c "cp '$RZIG' '$tc/zig-fc' && env -i ZIG_BIN='$real_zig' PATH='$W/flang' '$tc/zig-fc' --rzig-check | grep -qF '; flang at $W/flang/flang'"
fi
check "--rzig-check: no zig, 127, the compilers group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' --rzig-check > /dev/null 2> '$W/check.err'; [ \$? = 127 ] &&
    grep -q '^zig-cc: no zig (ZIG_BIN, ' '$W/check.err'"
check "--rzig-check: a zig that does not say its version, 1" \
  bash -c "env -i ZIG_BIN='$STUB' '$tc/zig-cc' --rzig-check > /dev/null 2> '$W/check.err'; [ \$? = 1 ] &&
    grep -q ' does not say its zig version ' '$W/check.err'"
: > "$W/notzig"; chmod +x "$W/notzig"   # an executable file that is no program
check "--rzig-check: a zig that does not run, 1, and why" \
  bash -c "env -i ZIG_BIN='$W/notzig' '$tc/zig-cc' --rzig-check > /dev/null 2> '$W/check.err'; [ \$? = 1 ] &&
    grep -qF 'zig-cc: $W/notzig did not run: InvalidExe ' '$W/check.err'"
prog "$W/zig-other/zig" '[ "$1" = version ] && echo 0.99.0'
check "--rzig-check: a zig whose major.minor is not R's, 1" \
  bash -c "env -i ZIG_BIN='$W/zig-other/zig' '$tc/zig-cc' --rzig-check > /dev/null 2> '$W/check.err'; [ \$? = 1 ] &&
    grep -q ' is zig 0.99.0, not R.s zig ' '$W/check.err'"
check "--rzig-check with R_ZIG_NO_PREFLIGHT: no version check, 0" \
  env -i ZIG_BIN="$STUB" R_ZIG_NO_PREFLIGHT=1 "$tc/zig-cc" --rzig-check
check "--rzig-check=build-tools: make on PATH" \
  bash -c "env -i PATH='$(dirname "$(command -v make)")' '$tc/zig-cc' --rzig-check=build-tools | grep -q '^zig-cc: build-tools ok: make at '"
check "--rzig-check=build-tools: no make, 127, the build-tools group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' --rzig-check=build-tools > /dev/null 2> '$W/check.err'; [ \$? = 127 ] &&
    grep -q '^Building packages needs the r-zig build tools for R ' '$W/check.err' &&
    grep -q '^  standalone:  extract R-[^ ]*-build-tools\.tar\.gz where you extracted R, or put GNU make on PATH\$' '$W/check.err'"
# Windows' rules from here (RZIG_OS): make and sh on PATH, and nothing
# else: the binutils Makeconf.win names are rzig's own names beside it
# (binutils.zig, feat-win-zig-binutils), not a group directory
tree winbt/Library
wtc=$W/winbt/Library/lib/R/bin/toolchain
mkdir -p "$W/onlymake"; ln -sf "$(command -v make)" "$W/onlymake/make"
win_env="env -i RZIG_PRINT_ARGV=1 RZIG_OS=windows PATH='$(dirname "$(command -v make)"):$(dirname "$(command -v sh)")'"
check "--rzig-check=build-tools on Windows: make but no sh, 127, the build-tools group" \
  bash -c "env -i RZIG_PRINT_ARGV=1 RZIG_OS=windows PATH='$W/onlymake' '$wtc/gcc' --rzig-check=build-tools > /dev/null 2> '$W/check.err'; [ \$? = 127 ] &&
    grep -q '^zig-cc: no sh on PATH' '$W/check.err' &&
    grep -q '^Building packages needs the r-zig build tools for R ' '$W/check.err'"
check "--rzig-check=build-tools on Windows: make and sh, and no binutils directory asked for" \
  bash -c "[ ! -e '$wtc/binutils' ] && $win_env '$wtc/gcc' --rzig-check=build-tools | grep -q '^zig-cc: build-tools ok: make at [^;]*; sh at [^;]*\$'"
# --rzig-check=package: the install preflight (patch 0009) for the package
# in the working directory, decided as `rzig build` decides (pkgbuild.decide):
# a tier-1 package asks for the compilers alone; one that needs make (a
# Makevars rule, MAKEFLAGS setting a variable, R_ZIG_PKG_BUILDER=make) or a
# configure script R runs (R_ZIG_CONFIGURE=1) asks for the build tools too,
# with rzig's reason first in the failing line; Fortran asks for flang.
rh=$W/tree/lib/R
mkdir -p "$rh/etc" "$rh/share/make" "$W/pkgs/p0" "$W/pkgs/p1/src" "$W/pkgs/p2/src" "$W/pkgs/pf/src"
cat > "$rh/etc/Makeconf" <<'MK'
CC = $(R_HOME)/bin/toolchain/zig-cc
CFLAGS = -O2
CPICFLAGS = -fpic
CXX = $(R_HOME)/bin/toolchain/zig-cxx
FC = $(R_HOME)/bin/toolchain/zig-fc
FFLAGS = -O2
FPICFLAGS = -fpic
FLIBS = -lflang_rt.runtime
LIBR = -L"$(R_HOME)/lib" -lR
SHLIB_EXT = .so
SHLIB_LD = $(CC)
SHLIB_LDFLAGS = -shared
SHLIB_LINK = $(SHLIB_LD) $(SHLIB_LDFLAGS)
ALL_CFLAGS = $(PKG_CFLAGS) $(CPICFLAGS) $(CFLAGS)
ALL_CPPFLAGS = -I"$(R_INCLUDE_DIR)" $(PKG_CPPFLAGS) $(CLINK_CPPFLAGS)
ALL_FFLAGS = $(PKG_FFLAGS) $(FPICFLAGS) $(FFLAGS)
ALL_LIBS = $(PKG_LIBS) $(SHLIB_LIBADD) $(LIBR)
MK
printf 'all: $(SHLIB)\n' > "$rh/share/make/shlib.mk"
# p3F a Makevars rule and a top-level .F (tier 3); pz src/build.zig and a
# stray .f (tier 2); pzF src/build.zig and a .F; pzurl a URL dependency;
# pw a configure.win, pu a configure.ucrt (Windows' rules)
mkdir -p "$W/pkgs/p3F/src" "$W/pkgs/pz/src" "$W/pkgs/pzF/src" "$W/pkgs/pzurl/src" "$W/pkgs/pw/src" "$W/pkgs/pu/src"
for d in p0 p1 p2 pf p3F pz pzF pzurl pw pu; do printf 'Package: %s\n' "$d" > "$W/pkgs/$d/DESCRIPTION"; done
: > "$W/pkgs/p1/src/a.c"; : > "$W/pkgs/p2/src/a.c"; printf 'all: $(SHLIB)\n' > "$W/pkgs/p2/src/Makevars"; : > "$W/pkgs/pf/src/a.f"
printf 'all: $(SHLIB)\n' > "$W/pkgs/p3F/src/Makevars"; : > "$W/pkgs/p3F/src/x.F"
: > "$W/pkgs/pz/src/build.zig"; : > "$W/pkgs/pz/src/x.f"; : > "$W/pkgs/pzF/src/build.zig"; : > "$W/pkgs/pzF/src/x.F"
: > "$W/pkgs/pzurl/src/build.zig"; printf '.{ .dependencies = .{ .x = .{ .url = "https://example.invalid/x.tar.gz" } } }\n' > "$W/pkgs/pzurl/src/build.zig.zon"
: > "$W/pkgs/pw/configure.win"; : > "$W/pkgs/pw/src/a.c"; : > "$W/pkgs/pu/configure.ucrt"; : > "$W/pkgs/pu/src/a.c"
# a user Makevars with a compiler that is not R's toolchain's
printf 'CC = ccache $(R_HOME)/bin/toolchain/zig-cc\n' > "$W/ccache.mk"
mkdir -p "$W/home/.R"; cp "$W/ccache.mk" "$W/home/.R/Makevars"
pkg_check() { # <pkg> <env...>: the package check from the package's directory (by $cc, default zig-cc), stdout and stderr to $W/check.out and $W/check.err
  local d="$1"; shift
  (cd "$W/pkgs/$d" && env -i R_HOME="$rh" "$@" "${cc:-$tc/zig-cc}" --rzig-check=package > "$W/check.out" 2> "$W/check.err")
}
# rzig build <pkg> <env...>: into $W/out/<pkg>, with the repo's root files
# (zigbuild/rpkg), stdout and stderr to $W/check.out and $W/check.err
pkg_build() {
  local d="$1"; shift
  rm -rf "$W/out/$d"
  env -i R_HOME="$rh" "$@" "$RZIG" build --pkg "$W/pkgs/$d" --out "$W/out/$d" --rpkg-dir "$here/../../rpkg" > "$W/check.out" 2> "$W/check.err"
}
# the functions and their variables, for the `bash -c` the cases run
pc="W='$W'; rh='$rh'; tc='$tc'; RZIG='$RZIG'; here='$here'; $(declare -f pkg_check pkg_build);"
check "--rzig-check=package: no src/, 0" \
  bash -c "$pc pkg_check p0 PATH='$W/nothing' && grep -qx 'zig-cc: package ok: p0 has no src/, nothing to compile' '$W/check.out'"
if [ -n "$real_zig" ]; then
  check "--rzig-check=package: tier 1 asks for the compilers alone (no make on PATH), 0" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' && grep -q '^zig-cc: package ok: p1 tier 1 (rzig build); compilers ok: zig ' '$W/check.out'"
  check "--rzig-check=package: a Makevars rule needs make, 127, rzig's reason, the build-tools group" \
    bash -c "$pc pkg_check p2 ZIG_BIN='$real_zig' PATH='$W/nothing'; [ \$? = 127 ] &&
      grep -qx 'zig-cc: p2 needs make: src/Makevars has a rule or target line: .all: .(SHLIB).; no make on PATH' '$W/check.err' &&
      grep -q '^Building packages needs the r-zig build tools for R ' '$W/check.err'"
  check "--rzig-check=package: a configure script R runs needs make whatever the tier, 127" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' R_ZIG_CONFIGURE=1; [ \$? = 127 ] &&
      grep -qxF 'zig-cc: p1 needs make: a configure script R runs; no make on PATH' '$W/check.err'"
  check "--rzig-check=package: R_ZIG_PKG_BUILDER=make needs make, 127" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' R_ZIG_PKG_BUILDER=make; [ \$? = 127 ] &&
      grep -qxF 'zig-cc: p1 needs make: R_ZIG_PKG_BUILDER=make; no make on PATH' '$W/check.err'"
  check "--rzig-check=package: MAKEFLAGS setting a variable needs make, 127" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' MAKEFLAGS='k -j2 -- LTO_OPT=-flto'; [ \$? = 127 ] &&
      grep -qxF 'zig-cc: p1 needs make: MAKEFLAGS sets LTO_OPT; no make on PATH' '$W/check.err'"
  check "--rzig-check=package: make's options in MAKEFLAGS plan tier 1, 0" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' MAKEFLAGS='k -j2 --jobserver-auth=fifo:/tmp/x' && grep -q 'p1 tier 1 (rzig build)' '$W/check.out'"
  check "--rzig-check=package: make and a configure script, 0, the reason and make named" \
    bash -c "$pc pkg_check p2 ZIG_BIN='$real_zig' PATH='$(dirname "$(command -v make)")' R_ZIG_CONFIGURE=1 && grep -q '^zig-cc: package ok: p2 needs make (a configure script R runs); compilers ok: zig .*; build-tools ok: make at ' '$W/check.out'"
  check "--rzig-check=package: Fortran asks for flang, 127 without one, the compilers group" \
    bash -c "$pc pkg_check pf ZIG_BIN='$real_zig' PATH='$W/nothing'; [ \$? = 127 ] && grep -q '^zig-cc: no flang (' '$W/check.err'"
  check "--rzig-check=package: Fortran with flang on PATH, 0, flang named" \
    bash -c "$pc pkg_check pf ZIG_BIN='$real_zig' PATH='$W/flang' && grep -q 'pf tier 1 (rzig build); compilers ok: zig .*; flang at $W/flang/flang' '$W/check.out'"
  # flang [preflight-PF-5]: tier 3 by src/'s top level, either case; tier 2
  # never (rpkg compiles C and C++ only); a configure script R runs by
  # src/'s top level whatever the tier
  check "--rzig-check=package: tier 3 with a top-level .F asks for flang, 127 without one" \
    bash -c "$pc pkg_check p3F ZIG_BIN='$real_zig' PATH='$W/nothing'; [ \$? = 127 ] && grep -q '^zig-cc: no flang (' '$W/check.err'"
  check "--rzig-check=package: tier 2 with a stray .f asks for no flang, 0" \
    bash -c "$pc pkg_check pz ZIG_BIN='$real_zig' PATH='$W/nothing' && grep -q '^zig-cc: package ok: pz tier 2 (rzig build); compilers ok: zig ' '$W/check.out' && ! grep -q flang '$W/check.out'"
  check "--rzig-check=package: tier 2 and a configure script, a top-level .F asks for flang, 127 without one" \
    bash -c "$pc pkg_check pzF ZIG_BIN='$real_zig' PATH='$W/nothing' R_ZIG_CONFIGURE=1; [ \$? = 127 ] && grep -q '^zig-cc: no flang (' '$W/check.err'"
  # MAKEFLAGS cannot change a tier-2 build: no make build to differ from
  # [preflight-PF-1]
  check "--rzig-check=package: tier 2 with MAKEFLAGS setting a variable, 0" \
    bash -c "$pc pkg_check pz ZIG_BIN='$real_zig' PATH='$W/nothing' MAKEFLAGS='k -j2 -- X=1' && grep -q 'pz tier 2 (rzig build)' '$W/check.out'"
  # the user Makevars as R finds it [preflight-PF-2]: ~/.R/Makevars, and
  # none when R_MAKEVARS_USER is set but empty
  check "--rzig-check=package: ~/.R/Makevars with a foreign CC needs make, 127, its reason" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' HOME='$W/home'; [ \$? = 127 ] &&
      grep -q '^zig-cc: p1 needs make: CC = ccache is not a compiler of R.s toolchain (.*); no make on PATH\$' '$W/check.err'"
  check "--rzig-check=package: an empty R_MAKEVARS_USER leaves ~/.R/Makevars out, tier 1, 0" \
    bash -c "$pc pkg_check p1 ZIG_BIN='$real_zig' PATH='$W/nothing' HOME='$W/home' R_MAKEVARS_USER= && grep -q 'p1 tier 1 (rzig build)' '$W/check.out'"
  # Windows' rules (RZIG_OS, with RZIG_PRINT_ARGV): a configure script
  # needs make, its reason before the missing build tool (sh: the
  # binutils are rzig's own names) [preflight-PF-8]
  tree winnobu/Library
  wnb=$W/winnobu/Library/lib/R/bin/toolchain
  mk_only="$W/onlymake"
  check "--rzig-check=package on Windows: a configure.win script, no sh, 127, the reason" \
    bash -c "$pc cc='$wnb/gcc' pkg_check pw ZIG_BIN='$real_zig' RZIG_PRINT_ARGV=1 RZIG_OS=windows PATH='$mk_only'; [ \$? = 127 ] &&
      grep -q '^zig-cc: pw needs make: a configure.win script; no sh on PATH' '$W/check.err' &&
      grep -q '^Building packages needs the r-zig build tools for R ' '$W/check.err'"
  check "--rzig-check=package on Windows: a configure.ucrt script, no sh, 127, the reason" \
    bash -c "$pc cc='$wnb/gcc' pkg_check pu ZIG_BIN='$real_zig' RZIG_PRINT_ARGV=1 RZIG_OS=windows PATH='$mk_only'; [ \$? = 127 ] &&
      grep -q '^zig-cc: pu needs make: a configure.ucrt script; no sh on PATH' '$W/check.err'"
  check "--rzig-check=package on Windows: a configure script R runs (R_ZIG_CONFIGURE=1), no sh, 127" \
    bash -c "$pc cc='$wnb/gcc' pkg_check pw ZIG_BIN='$real_zig' RZIG_PRINT_ARGV=1 RZIG_OS=windows PATH='$mk_only' R_ZIG_CONFIGURE=1; [ \$? = 127 ] &&
      grep -q '^zig-cc: pw needs make: a configure script R runs; no sh on PATH' '$W/check.err'"
fi
# a tier-2 package whose plan needs make: make would ignore its build.zig,
# so the check and rzig build stop with why, 1, not 3 [preflight-PF-1],
# and the check with a line that says the toolchain is complete [code-6];
# 0009's stop after it says the package cannot be built (PHASE4 open
# point J a)
check "--rzig-check=package: tier 2 whose plan needs make, 1, why, no group's text" \
  bash -c "$pc pkg_check pz PATH='$W/nothing' R_MAKEVARS_USER='$W/ccache.mk'; [ \$? = 1 ] &&
    grep -q '^zig-cc: pz: src/build.zig cannot be built by make: CC = ccache is not a compiler of R.s toolchain (' '$W/check.err' &&
    [ \"\$(tail -1 '$W/check.err')\" = 'zig-cc: pz: the r-zig toolchain is complete: change what the line above names' ] &&
    [ \$(wc -l < '$W/check.err') = 2 ]"
check "rzig build: tier 2 whose plan needs make, 1, why, nothing made" \
  bash -c "$pc pkg_build pz PATH='$W/nothing' R_MAKEVARS_USER='$W/ccache.mk'; [ \$? = 1 ] &&
    grep -qx 'rzig build: pz: src/build.zig cannot be built by make: CC = ccache is not a compiler of R.s toolchain (.*)' '$W/check.err' &&
    [ ! -e '$W/out/pz' ]"
# --classify too: the line and 1, no tier on stdout [coverage-1]
check "rzig build --classify: tier 2 whose plan needs make, 1, why, no tier" \
  bash -c "env -i R_HOME='$rh' PATH='$W/nothing' R_MAKEVARS_USER='$W/ccache.mk' '$RZIG' build --pkg '$W/pkgs/pz' --classify > '$W/check.out' 2> '$W/check.err'; [ \$? = 1 ] &&
    grep -qx 'rzig build: pz: src/build.zig cannot be built by make: CC = ccache is not a compiler of R.s toolchain (.*)' '$W/check.err' &&
    [ ! -s '$W/check.out' ]"
# a src/Makefile beside src/build.zig: install.R runs the Makefile, so
# make it is [code-2]
mkdir -p "$W/pkgs/pzm/src"; printf 'Package: pzm\n' > "$W/pkgs/pzm/DESCRIPTION"; : > "$W/pkgs/pzm/src/build.zig"; : > "$W/pkgs/pzm/src/Makefile"
check "rzig build --classify: src/build.zig and src/Makefile, make" \
  bash -c "env -i R_HOME='$rh' PATH='$W/nothing' '$RZIG' build --pkg '$W/pkgs/pzm' --classify > '$W/check.out' 2> '$W/check.err' && [ \"\$(cat '$W/check.out')\" = make ]"
check "rzig build: tier 1 whose plan needs make, 3" \
  bash -c "$pc pkg_build p1 PATH='$W/nothing' R_MAKEVARS_USER='$W/ccache.mk'; [ \$? = 3 ] &&
    grep -q '^rzig build: p1 needs make: CC = ccache ' '$W/check.err'"
# the build root goes on every return, unless kept [preflight-PF-3]
check "rzig build: a URL dependency is refused, 1, and the build root is gone" \
  bash -c "$pc pkg_build pzurl PATH='$W/nothing'; [ \$? = 1 ] &&
    grep -qxF 'rzig build: src/build.zig.zon: dependency x is a URL; tier 2 builds offline, vendor it as a .path dependency' '$W/check.err' &&
    [ -d '$W/out/pzurl' ] && [ ! -e '$W/out/pzurl/.rzig' ]"
check "rzig build: no zig, 127, the compilers group, and the build root is gone" \
  bash -c "$pc pkg_build p1 PATH='$W/nothing'; [ \$? = 127 ] &&
    grep -q '^Compiling needs the r-zig compilers for R ' '$W/check.err' &&
    [ -d '$W/out/p1' ] && [ ! -e '$W/out/p1/.rzig' ]"
check "rzig build: RZIG_KEEP_ROOT=1 keeps it" \
  bash -c "$pc pkg_build p1 PATH='$W/nothing' RZIG_KEEP_ROOT=1; [ \$? = 127 ] && [ -f '$W/out/p1/.rzig/plan.zon' ]"
# rzig build for real (the real zig): a tier-1 package twice, each from a
# new directory as install.R unpacks every install, in an R_HOME with no
# share/zig/rpkg (tier 1 needs none; a tree without build_t1.zig no longer
# goes to make). rzig compiles and links it itself (tier1.zig): the
# objects and the library in the build root (kept here), no zig build, so
# no build-runner-* entry in rzig's cache, and the second build adds no
# file there (feat-tier1-engine).
if [ -n "$real_zig" ]; then
  tree rbtree
  rb=$W/rbtree/lib/R
  mkdir -p "$rb/etc" "$rb/share/make" "$W/pkgs/pb/src"
  grep -v '^LIBR' "$rh/etc/Makeconf" > "$rb/etc/Makeconf"   # no libR to link here
  cp "$rh/share/make/shlib.mk" "$rb/share/make/"
  printf 'Package: pb\n' > "$W/pkgs/pb/DESCRIPTION"; printf 'int pb(void) { return 1; }\n' > "$W/pkgs/pb/src/a.c"
  rb_build() { # <n>: pb copied to $W/rb/<n>/pb, built into $W/rb/<n>/out, the root kept
    rm -rf "$W/rb/$1"; mkdir -p "$W/rb/$1"; cp -R "$W/pkgs/pb" "$W/rb/$1/"
    env -i R_HOME="$rb" HOME="$W/rbhome" XDG_CACHE_HOME="$W/rbcache" ZIG_BIN="$real_zig" ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$W/zig-global}" \
      ${rb_env:+"$rb_env"} PATH="$W/nothing" RZIG_KEEP_ROOT=1 RZIG_TRACE=1 "$RZIG" build --pkg "$W/rb/$1/pb" --out "$W/rb/$1/out" > "$W/check.out" 2> "$W/check.err"
  }
  # the files in rzig's cache (their names included), none when there is
  # no cache (a zig with no libc++ beside it: no mirror)
  cache_files() { if [ -d "$W/rbcache/r-zig" ]; then (cd "$W/rbcache/r-zig" && find . -type f | LC_ALL=C sort); fi; }
  pc="$pc rb='$rb'; real_zig='$real_zig'; $(declare -f rb_build cache_files);"
  # rzig's trace names its cache (main.zig), the one these checks read
  check "rzig build: tier 1, the objects and the library in the build root, no zig build, nothing of pb's and no build-runner-* in rzig's cache, which the trace names" \
    bash -c "$pc rb_build 1 && [ -f '$W/rb/1/out/libs/pb.so' ] && [ -f '$W/rb/1/out/.rzig/obj/0/a.o' ] && [ -f '$W/rb/1/out/.rzig/pb.so' ] &&
      [ \"\$(grep -E '^zig-(cc|cxx|fc): cache ' '$W/check.err' | sort -u)\" = 'zig-cc: cache $W/rbcache/r-zig' ] &&
      [ ! -e '$W/rb/1/out/.rzig/zig-cache' ] && ! ls -d '$W/rbcache/r-zig'/build-runner-* > /dev/null 2>&1 &&
      grep -qxF 'rzig build: tier 1, root $W/rb/1/out/.rzig' '$W/check.err' && ! grep -q -- ' build --build-file ' '$W/check.err' &&
      [ -z \"\$(find '$W/rbcache' -name a.o -o -name pb.so 2> /dev/null)\" ] && cache_files > '$W/rb/state1'"
  check "rzig build: tier 1 again from another directory, no file added to rzig's cache" \
    bash -c "$pc rb_build 2 && [ -f '$W/rb/2/out/libs/pb.so' ] && cache_files > '$W/rb/state2' && cmp -s '$W/rb/state1' '$W/rb/state2'"
  # the finalization object from beside rzig, as R's build installs it:
  # the link names it, the library has its .fini_array, and rzig's cache
  # has no dso-fini-* entry (feat-r-home-link-objects)
  check "rzig build: tier 1's link names the tree's dso_fini.o, the library has a .fini_array, no dso-fini-* in rzig's cache" \
    bash -c "grep -qE -- '^zig-cc: .* $rb/bin/toolchain/dso_fini\\.o ' '$W/check.err' &&
      readelf -S '$W/rb/2/out/libs/pb.so' | grep -q '\\.fini_array' && ! ls -d '$W/rbcache/r-zig'/dso-fini-* > /dev/null 2>&1"
  # The link's objects in the build root's objects.rsp, one a line in
  # double quotes, named from src/ (tier1.zig, response.zig's rspText;
  # feat-win-link-fixes item 1); RZIG_TRACE's line names them in its
  # place, as make's link does (response.zig). A -g compile with no -g on
  # the link (pkgbuild's compile_dll(debug = TRUE)): strip.zig reads the
  # objects in the file and the library keeps its .debug_info.
  check "rzig build: tier 1 links through objects.rsp in the build root, the object named from src/; the traced link names it" \
    bash -c "$pc rb_build 4 && [ \"\$(cat '$W/rb/4/out/.rzig/objects.rsp')\" = '\"../../out/.rzig/obj/0/a.o\"' ] &&
      grep -qE -- '^zig-cc: .* -o $W/rb/4/out/\\.rzig/pb\\.so \\.\\./\\.\\./out/\\.rzig/obj/0/a\\.o( |\$)' '$W/check.err' &&
      ! grep -qaF .debug_info '$W/rb/4/out/libs/pb.so'"
  printf 'CFLAGS = -g -O2\n' > "$W/debug.mk"
  check "rzig build: tier 1 compiled with -g, linked without: the library keeps .debug_info (objects.rsp read)" \
    bash -c "$pc rb_env=R_MAKEVARS_USER='$W/debug.mk' rb_build 5 && grep -q -- ' -g -O2 ' '$W/check.err' &&
      grep -qaF .debug_info '$W/rb/5/out/.rzig/obj/0/a.o' && grep -qaF .debug_info '$W/rb/5/out/libs/pb.so'"
fi
# --- rzig build --shlib: R CMD SHLIB's call (feat-shlib-rzig-build) ----------
# The real binary and the repo's rpkg, each case in its own $W/sh/<n>, with
# an R_HOME whose Makeconf has no libR to link (as rb's) and the C++ and
# Fortran 9x lines; a case that checks the build root sets
# R_SESSION_TMPDIR=$W/sh/<n>.tmp. The builds use the real zig and rb's
# rzig cache.
tree shtree
sh_rh=$W/shtree/lib/R
sh_tc=$sh_rh/bin/toolchain
cp "$RZIG" "$sh_tc/zig-fc"
mkdir -p "$sh_rh/etc" "$sh_rh/share/make"
grep -v '^LIBR' "$rh/etc/Makeconf" > "$sh_rh/etc/Makeconf"
cat >> "$sh_rh/etc/Makeconf" <<'MK'
CXXFLAGS = -O2
CXXPICFLAGS = -fpic
FCFLAGS = -O2
ALL_CXXFLAGS = $(PKG_CXXFLAGS) $(CXXPICFLAGS) $(CXXFLAGS)
ALL_FCFLAGS = $(PKG_FCFLAGS) $(FPICFLAGS) $(FCFLAGS)
SHLIB_CXXLD = $(CXX)
SHLIB_CXXLDFLAGS = -shared
MK
cp "$rh/share/make/shlib.mk" "$sh_rh/share/make/"
# sh_dir <n>: $W/sh/<n> with foo.c and an invalid junk.c beside it, and
# an empty $W/sh/<n>.tmp
sh_dir() {
  rm -rf "$W/sh/$1" "$W/sh/$1.tmp"; mkdir -p "$W/sh/$1" "$W/sh/$1.tmp"
  printf 'void foo(int *x) { *x = 1; }\n' > "$W/sh/$1/foo.c"
  printf 'this is not C\n' > "$W/sh/$1/junk.c"
}
# sh_build <n> [<env>...] -- <rzig build --shlib's arguments>: in $W/sh/<n>,
# PATH $W/nothing unless the env says, stdout and stderr to $W/check.out
# and $W/check.err
sh_build() {
  local n=$1 envs=(); shift
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  (cd "$W/sh/$n" && env -i R_HOME="$sh_rh" PATH="$W/nothing" "${envs[@]}" "$RZIG" build --shlib --rpkg-dir "$here/../../rpkg" "$@" > "$W/check.out" 2> "$W/check.err")
}
# no root left beside the sources, beside an output in another directory
# ($2, under $W/sh/<n>) or in R's session directory [shlib-tests-1]
no_root() { ! ls -d "$W/sh/$1"/.rzig.* > /dev/null 2>&1 && [ -z "$(ls -A "$W/sh/$1.tmp")" ] &&
  { [ -z "${2:-}" ] || ! ls -d "$W/sh/$1/$2"/.rzig.* > /dev/null 2>&1; }; }
pc="$pc sh_rh='$sh_rh'; sh_tc='$sh_tc'; $(declare -f sh_dir sh_build no_root);"
check "rzig build --shlib --plan-only: argv's files only, not the directory's" \
  bash -c "$pc sh_dir 1 && sh_build 1 -- --output foo.so --plan-only -- foo.c &&
    grep -qF '.path = \"foo.c\"' '$W/check.out' && ! grep -q junk '$W/check.out' && no_root 1"
check "rzig build --shlib --dry-run: no zig needed, make -n's compile line and link block, no root" \
  bash -c "$pc sh_dir 2 && sh_build 2 R_SESSION_TMPDIR='$W/sh/2.tmp' -- --output foo.so --dry-run -- foo.c &&
    head -1 '$W/check.out' | grep -q '^$sh_tc/zig-cc .* -c foo\.c -o foo\.o\$' &&
    sed -n 2p '$W/check.out' | grep -qxF 'if test \"zfoo.o\" != \"z\"; then \\' &&
    sed -n 3p '$W/check.out' | grep -q '^  echo $sh_tc/zig-cc .* -o foo\.so foo\.o; \\\\\$' &&
    [ \"\$(tail -1 '$W/check.out')\" = fi ] && [ ! -e '$W/sh/2/foo.so' ] && no_root 2"
check "rzig build --shlib: pkgload's injected word in the linker words, 3, a single quote" \
  bash -c "$pc sh_dir 3; sh_build 3 -- --output foo.so --pkg-libs \"' --always-make -I\\\"/x\\\" IGNORED='\" --dry-run -- foo.c; [ \$? = 3 ] &&
    grep -qF 'rzig build: foo.so needs make: a single quote in the linker words' '$W/check.err' && [ ! -s '$W/check.out' ]"
check "rzig build --shlib: no zig, 127, the compilers group, the root gone" \
  bash -c "$pc sh_dir 4; sh_build 4 R_SESSION_TMPDIR='$W/sh/4.tmp' -- --output foo.so -- foo.c; [ \$? = 127 ] &&
    grep -q '^Compiling needs the r-zig compilers for R ' '$W/check.err' && no_root 4"
printf 'all: $(SHLIB) extra\n' > "$W/sh/rule.mk"
check "rzig build --shlib: a Makevars rule, no zig, no make: 127, the compilers' text, then the reason and the build tools' text" \
  bash -c "$pc sh_dir 5 && cp '$W/sh/rule.mk' '$W/sh/5/Makevars'; sh_build 5 -- --output foo.so -- foo.c; [ \$? = 127 ] &&
    c=\$(grep -n '^Compiling needs the r-zig compilers for R ' '$W/check.err' | cut -d: -f1) &&
    l=\$(grep -n '^rzig build: foo.so needs make: Makevars has a rule or target line: .all: .(SHLIB) extra.; no make on PATH\$' '$W/check.err' | cut -d: -f1) &&
    b=\$(grep -n '^Building packages needs the r-zig build tools for R ' '$W/check.err' | cut -d: -f1) &&
    [ \"\$c\" -lt \"\$l\" ] && [ \"\$l\" -lt \"\$b\" ] && [ ! -e '$W/sh/5/foo.so' ]"
# a zig that is not R's (another minor version; R CMD SHLIB has no
# preflight): make's, 3, when make is there, else 1 and the compilers'
# text; zig build never runs [shlib-r-2]
prog "$W/sh/otherzig/zig" "[ \"\$1\" = version ] && echo 0.99.0 && exit 0; : > '$W/sh/otherzig/built'"
prog "$W/sh/mkonly/make" 'exit 0'
check "rzig build --shlib: a zig that is not R's: 3 with make, 1 without, no zig build" \
  bash -c "$pc sh_dir 13; sh_build 13 ZIG_BIN='$W/sh/otherzig/zig' -- --output foo.so -- foo.c; [ \$? = 1 ] &&
    grep -q '^rzig build: $W/sh/otherzig/zig is zig 0.99.0, not R.s zig .* (R_ZIG_NO_PREFLIGHT=1 skips this check)\$' '$W/check.err' &&
    grep -q '^Compiling needs the r-zig compilers for R ' '$W/check.err' &&
    { sh_build 13 ZIG_BIN='$W/sh/otherzig/zig' PATH='$W/sh/mkonly' -- --output foo.so -- foo.c; [ \$? = 3 ]; } &&
    grep -qx 'rzig build: foo.so needs make: $W/sh/otherzig/zig is zig 0.99.0, not R.s zig .*' '$W/check.err' &&
    [ ! -e '$W/sh/otherzig/built' ] && [ ! -e '$W/sh/13/foo.so' ] && no_root 13"
if [ -n "$real_zig" ]; then
  # the real builds, with rb's rzig cache and zig's global cache
  sh_env="HOME=$W/rbhome XDG_CACHE_HOME=$W/rbcache ZIG_BIN=$real_zig ZIG_GLOBAL_CACHE_DIR=${ZIG_GLOBAL_CACHE_DIR:-$W/zig-global}"
  pc="$pc sh_env='$sh_env';"
  check "rzig build --shlib: a real build, the library and nothing beside it, junk.c not compiled, no zig build, no file added to rzig's cache" \
    bash -c "$pc sh_dir 7 && sh_build 7 \$sh_env RZIG_TRACE=1 R_SESSION_TMPDIR='$W/sh/7.tmp' -- --output foo.so -- foo.c &&
      [ -f '$W/sh/7/foo.so' ] && [ ! -e '$W/sh/7/foo.o' ] && no_root 7 &&
      grep -q '^rzig build: R CMD SHLIB, tier 1, root $W/sh/7.tmp/\.rzig\.[0-9a-f]\{16\}\$' '$W/check.err' &&
      ! grep -q junk '$W/check.err' && ! grep -q -- ' build --build-file ' '$W/check.err' && cache_files > '$W/sh/state7' && cmp -s '$W/rb/state1' '$W/sh/state7'"
  # R's session directory below the sources, in a directory named -tmp:
  # objects.rsp names each object `./-tmp/...`, not as an option
  # (response.zig's rspName; feat-win-link-fixes review R1)
  check "rzig build --shlib: the root under ./-tmp, the link reads its objects, the root gone" \
    bash -c "$pc sh_dir 14 && mkdir '$W/sh/14/-tmp' && sh_build 14 \$sh_env R_SESSION_TMPDIR='$W/sh/14/-tmp' -- --output foo.so -- foo.c &&
      [ -f '$W/sh/14/foo.so' ] && [ -z \"\$(ls -A '$W/sh/14/-tmp')\" ]"
  check "rzig build --shlib: an absolute source outside the directory, its object not beside it" \
    bash -c "$pc sh_dir 8 && mkdir -p '$W/sh/8ext' && printf 'int ext(void) { return 2; }\n' > '$W/sh/8ext/ext.c' &&
      sh_build 8 \$sh_env -- --output sub/ab.so -- foo.c '$W/sh/8ext/ext.c' &&
      [ -f '$W/sh/8/sub/ab.so' ] && [ ! -e '$W/sh/8ext/ext.o' ] && no_root 8 sub"
  check "rzig build --shlib: a Makevars rule, R's zig, no make: 127, the build tools' text alone" \
    bash -c "$pc sh_dir 9 && cp '$W/sh/rule.mk' '$W/sh/9/Makevars'; sh_build 9 \$sh_env -- --output foo.so -- foo.c; [ \$? = 127 ] &&
      grep -q '^rzig build: foo.so needs make: Makevars has a rule or target line: .*; no make on PATH\$' '$W/check.err' &&
      grep -q '^Building packages needs the r-zig build tools for R ' '$W/check.err' && ! grep -q '^Compiling needs' '$W/check.err'"
  prog "$W/mkstub/make" 'exit 0'
  check "rzig build --shlib: a Makevars rule, zig and make: 3, R runs make" \
    bash -c "$pc sh_dir 10 && cp '$W/sh/rule.mk' '$W/sh/10/Makevars'; sh_build 10 \$sh_env PATH='$W/mkstub' -- --output foo.so -- foo.c; [ \$? = 3 ] &&
      grep -qx 'rzig build: foo.so needs make: Makevars has a rule or target line: .all: .(SHLIB) extra.' '$W/check.err' && [ ! -e '$W/sh/10/foo.so' ]"
  # two calls at once in one directory (R CMD SHLIB under mclapply): a
  # build root each (SZ H2; feat-shlib-rzig-build Cc12), kept, so beside
  # the outputs, in one directory [shlib-code-1]
  sh_dir 11; printf 'int b(void) { return 2; }\n' > "$W/sh/11/b.c"
  check "rzig build --shlib: two calls at once in one directory, two roots" \
    bash -c "$pc cd '$W/sh/11' &&
      { env -i R_HOME='$sh_rh' PATH='$W/nothing' \$sh_env RZIG_KEEP_ROOT=1 R_SESSION_TMPDIR='$W/sh/11.tmp' '$RZIG' build --shlib --rpkg-dir '$here/../../rpkg' --output a.so -- foo.c > '$W/sh/11.a' 2>&1 & pa=\$!; } &&
      { env -i R_HOME='$sh_rh' PATH='$W/nothing' \$sh_env RZIG_KEEP_ROOT=1 R_SESSION_TMPDIR='$W/sh/11.tmp' '$RZIG' build --shlib --rpkg-dir '$here/../../rpkg' --output b.so -- b.c > '$W/sh/11.b' 2>&1 & pb=\$!; } &&
      wait \$pa && wait \$pb && [ -f a.so ] && [ -f b.so ] &&
      [ \$(ls -d '$W/sh/11'/.rzig.* | wc -l) = 2 ] && [ \$(ls '$W/sh/11'/.rzig.*/plan.zon | wc -l) = 2 ] &&
      [ -z \"\$(ls -A '$W/sh/11.tmp')\" ] && rm -rf '$W/sh/11'/.rzig.*"
  # Fortran modules: use_m.f90 uses mod_m.f90's module, so their compiles
  # run in OBJECTS order, as R's serial make runs them; at -j 8, five times,
  # each with no .mod left from the one before (feat-shlib-rzig-build Cc3)
  real_flang=$(command -v flang || :)
  if [ -n "$real_flang" ]; then
    mkdir -p "$W/sh/flang"; ln -sf "$real_flang" "$W/sh/flang/flang"
    sh_dir 12
    printf 'module mod_m\n  implicit none\ncontains\n  subroutine twice(x)\n    double precision, intent(inout) :: x\n    x = 2 * x\n  end subroutine\nend module\n' > "$W/sh/12/mod_m.f90"
    printf 'subroutine use_twice(x)\n  use mod_m\n  double precision, intent(inout) :: x\n  call twice(x)\nend subroutine\n' > "$W/sh/12/use_m.f90"
    check "rzig build --shlib: Fortran modules in OBJECTS order at -j 8, five times, no root left beside the output" \
      bash -c "$pc for i in 1 2 3 4 5; do rm -f '$W/sh/12'/*.mod '$W/sh/12/fm.so';
        sh_build 12 \$sh_env PATH='$W/sh/flang' -- --output fm.so -j 8 -- mod_m.f90 use_m.f90 && [ -f '$W/sh/12/fm.so' ] &&
        ! ls -d '$W/sh/12'/.rzig.* > /dev/null 2>&1 || exit 1; done"
  fi
fi
check "--rzig-check=other: usage, 2" \
  bash -c "env -i '$tc/zig-cc' --rzig-check=other 2> /dev/null; [ \$? = 2 ]"
check "a compile with no zig: 127, the compilers group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' -c a.c > /dev/null 2> '$W/check.err'; [ \$? = 127 ] &&
    grep -q '^Compiling needs the r-zig compilers for R ' '$W/check.err'"

echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
