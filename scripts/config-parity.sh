#!/usr/bin/env bash
# R CMD config, rzig's config mode (patch 0010, zigbuild/tools/rzig/
# config.zig), against R's own src/scripts/config run with make: the same
# stdout, stderr and exit status for every case below
# (feat-config-rzig PLAN.md). R's script is the reference only; the tree
# does not ship it. Both run under R CMD, with R CMD's environment:
# `R CMD config ...` against `R CMD sh <R's script> ...`, so make and sh
# must be on the PATH R CMD gives (the env's, or the build-tools group's
# in the compile tree).
#
# Cases: no arguments, -h/--help, -v/--version, every variable the script
# accepts (and its Windows-only ones, unknown here), --all, --cppflags,
# --ldflags, an unknown, a defunct and a second variable, an empty
# argument, --no-user-files and --no-site-files, and the user's and
# site's files: ~/.R/Makevars, ~/.R/Makevars-$R_PLATFORM,
# R_MAKEVARS_USER, R_MAKEVARS_SITE (set to a file, set empty), with
# assignments that override, append, quote and refer to the environment;
# export, unexport, `export` alone, .EXPORT_ALL_VARIABLES and vpath, and
# the variables make sets itself (CURDIR, MAKELEVEL, SHELL, ...).
# HOME is a fresh directory. On unix also the Windows branch of both
# (R_OSTYPE=windows): its help text and variables. Then what only make
# can answer ($(shell), define, !=, MAKEFLAGS, MAKEFILE_LIST, a glob):
# rzig exits 2 and names the file and line (the user's decision of
# 2026-11-13), where make answers.
#
# Usage: config-parity.sh [TREE]   (default: env.sh's prefix, the tree
# zig-build.sh installed). Called by zig-contract.sh on the compile tree.
. "$(dirname "$0")/env.sh"

TREE="${1:-$PREFIX}"
if command -v cygpath > /dev/null 2>&1; then TREE="$(cygpath -u "$TREE")"; fi
if [ "$OS" = windows ]; then R="$TREE/$RH/bin/R.exe"; else R="$TREE/$RH/bin/R"; fi
test -x "$R" || { echo "error: no R at $R: run 'pixi run build' first" >&2; exit 1; }
script="$SRC_DIR/src/scripts/config"
test -f "$script" || { echo "error: no $script: run 'pixi run fetch' first" >&2; exit 1; }
if grep -q 'r-zig' "$script"; then
  echo "error: $script carries an r-zig change; the reference is R's own script" >&2; exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/config-parity.XXXXXX")"
work_sh="$work"   # as MSYS's sh spells it (Windows: /tmp/...)
trap 'rm -rf "$work"' EXIT
# Windows: one spelling (C:/...) for rzig and for MSYS's sh and make, in
# the long form: GitHub's runners have TEMP=C:\Users\RUNNER~1\..., and
# make's CURDIR (the process's directory) comes back in the long form
if command -v cygpath > /dev/null 2>&1; then work="$(cygpath -m -l "$work")"; fi
export HOME="$work/home"
mkdir -p "$HOME/.R"
unset R_MAKEVARS_USER R_MAKEVARS_SITE MAKEFLAGS
cd "$work"

fail=0
n=0
skipped=""
# Windows: R's script runs under MSYS's sh and make, which see the
# environment as MSYS converts it (HOME, the working directory: /tmp/...),
# while rzig, a native program, prints the native spellings it gets
# (C:\... from R, C:/... for CURDIR). The values are the same directory, so
# each output has the scratch directory's spellings replaced by
# <work> (and a backslash after it by a slash) before the comparison.
# R's MSYS has its own root (R_HOME/bin/toolchain) and no /tmp mount, so
# its sh may spell the directory /c/... where this script's MSYS says
# /tmp/... (GitHub's runners: the Temp directory).
norm_paths() {
  [ "$OS" = windows ] || return 0
  local f wm
  wm="$(cygpath -m "$work")"
  for f in "$@"; do
    WU="$work_sh" WU2="$(cygpath -u "$work")" WM="$wm" WW="$(cygpath -w "$work")" \
    WD="/$(printf '%s' "${wm%%:*}" | tr 'A-Z' 'a-z')${wm#?:}" awk '
      function rep(s, f,   o, i) { o = ""; while (f != "" && (i = index(s, f)) > 0) { o = o substr(s, 1, i - 1) "<work>"; s = substr(s, i + length(f)) } return o s }
      { $0 = rep($0, ENVIRON["WW"]); $0 = rep($0, ENVIRON["WM"]); $0 = rep($0, ENVIRON["WU"]); $0 = rep($0, ENVIRON["WU2"]); $0 = rep($0, ENVIRON["WD"]); gsub(/<work>\\/, "<work>/"); print }' "$f" > "$f.n" && mv "$f.n" "$f"
  done
}
# compare <label> <args...>: R CMD config <args> against R's script
compare() {
  local label="$1"; shift
  local rc_a=0 rc_b=0
  "$R" CMD config "$@" > a.out 2> a.err || rc_a=$?
  "$R" CMD sh "$script" "$@" > b.out 2> b.err || rc_b=$?
  norm_paths a.out b.out a.err b.err
  n=$((n + 1))
  if [ "$rc_a" != "$rc_b" ] || ! cmp -s a.out b.out || ! cmp -s a.err b.err; then
    fail=$((fail + 1))
    echo "MISMATCH [$label] R CMD config $*: exit $rc_a (rzig) vs $rc_b (make)" >&2
    diff b.out a.out >&2 || true
    diff b.err a.err >&2 || true
  fi
}

# the Windows branch, on unix: R_OSTYPE=windows for both (bin/R sets
# unix's, so it is set inside R CMD)
compare_win() {
  local label="$1"; shift
  local rc_a=0 rc_b=0
  "$R" CMD sh -c 'R_OSTYPE=windows exec "$R_HOME/bin/toolchain/rzig" config "$@"' rzig "$@" > a.out 2> a.err || rc_a=$?
  "$R" CMD sh -c 'R_OSTYPE=windows exec sh "$0" "$@"' "$script" "$@" > b.out 2> b.err || rc_b=$?
  n=$((n + 1))
  if [ "$rc_a" != "$rc_b" ] || ! cmp -s a.out b.out || ! cmp -s a.err b.err; then
    fail=$((fail + 1))
    echo "MISMATCH [$label] (R_OSTYPE=windows) config $*: exit $rc_a (rzig) vs $rc_b (make)" >&2
    diff b.out a.out >&2 || true
    diff b.err a.err >&2 || true
  fi
}

# every variable the script knows: the names --all prints, from R's script
vars="$("$R" CMD sh "$script" --all | sed -n 's/^\([A-Za-z0-9_]*\) =.*/\1/p')"
[ "$(echo "$vars" | wc -w)" -gt 60 ] || { echo "error: R's script printed too few variables: $vars" >&2; exit 1; }

cases() {
  local tag="$1"
  compare "$tag" --all
  for v in $vars COMPILED_BY LOCAL_SOFT R_TOOLS_SOFT OBJDUMP; do compare "$tag" "$v"; done
}

compare base
compare base --help
compare base -h
compare base --version
compare base -v
compare base --cppflags
compare base --ldflags
compare base CC --ldflags
compare base NOPE
compare base CXX11
compare base CPP
compare base CC CXX
compare base --no-user-files
compare base "" CC
compare base --no-site-files --no-user-files CC
cases base

# ~/.R/Makevars: override, append, quotes, the environment, a lazy $(shell)
cat > "$HOME/.R/Makevars" <<'EOF'
CFLAGS += -g "-DQ=a  b" $$HOME '-DS=x  y'
CXX17 = ccache g++ -std=gnu++17
LDFLAGS = -L/opt/x\ y/lib
FC := $(FC) -O0
NEVER = $(shell echo never printed)
ifeq ($(R_OSTYPE),unix)
LTO = -flto=thin
endif
EOF
cases home-Makevars
compare home-Makevars --no-user-files CFLAGS
compare home-Makevars --ldflags

# ~/.R/Makevars-$R_PLATFORM comes first
plat="$("$R" CMD sh -c 'echo "$R_PLATFORM"')"
printf 'CFLAGS = -O0 -platform\n' > "$HOME/.R/Makevars-$plat"
compare platform CFLAGS
compare platform CXX17

# R_MAKEVARS_USER beats both; R_MAKEVARS_SITE, set to a file or empty
printf 'CFLAGS = -O1 -user\nCC += -DUSER\n' > "$work/user.mk"
printf 'CFLAGS += -site\nCC = site-cc\nCXX = site-cxx\n' > "$work/site.mk"
export R_MAKEVARS_USER="$work/user.mk"
compare user CFLAGS
compare user CC
export R_MAKEVARS_SITE="$work/site.mk"
compare site CFLAGS
compare site CC
compare site CXX
compare site --no-site-files CC
compare site --no-user-files --no-site-files CC
cases site
export R_MAKEVARS_SITE=""
compare site-empty CXX
unset R_MAKEVARS_SITE

# what make exports to config.mk's echo, and the variables make sets
# itself (CURDIR, MAKELEVEL, SHELL, MAKECMDGOALS)
mk_case() {
  printf '%s\n' "$1" > "$work/user.mk"
  compare "make: $1" CFLAGS
}
mk_case 'export FOO = bar
CFLAGS = -D$$FOO'
mk_case 'FOO = bar
export FOO BAZ
BAZ = q
CFLAGS = -D$$FOO ${BAZ} $$BAZ'
mk_case 'FOO = bar
CFLAGS = -D$$FOO'
mk_case 'export
FOO = bar
CFLAGS = -D$$FOO $$CC $$OBJC $$CURDIR'
mk_case '.EXPORT_ALL_VARIABLES:
FOO = bar
CFLAGS = -D$$FOO'
mk_case 'export FOO = bar
unexport FOO
unexport HOME
CFLAGS = -D$$FOO $$HOME'
mk_case 'export
unexport
FOO = bar
CFLAGS = -D$$FOO'
mk_case 'HOME = /x
override R_HOME = /y
CFLAGS = $$HOME $$R_HOME $$VAR'
mk_case 'CFLAGS = $(MAKE) $(MAKELEVEL) $$MAKELEVEL $(CURDIR) $(origin MAKELEVEL) $(origin CURDIR) $(flavor CURDIR)'
# $$SHELL: on Windows MSYS's bash puts its own SHELL (/usr/bin/bash) in
# the environment of make's sh, which a native R and rzig never see: a
# deliberate difference there (feat-config-rzig PLAN.md)
if [ "$OS" != windows ]; then
  mk_case 'CFLAGS = $(SHELL) $$SHELL $(.SHELLFLAGS) $(MAKECMDGOALS)'
  mk_case 'export SHELL
CFLAGS = $$SHELL'
else
  mk_case 'CFLAGS = $(SHELL) $(.SHELLFLAGS) $(MAKECMDGOALS)'
  skipped=2
fi
mk_case 'vpath %.c src
CFLAGS = ok "*" '"'"'?'"'"' \['
printf 'CC = $(MAKECMDGOALS)\n' > "$work/user.mk"
compare "make: MAKECMDGOALS" --all
MAKELEVEL=3 mk_case 'CFLAGS = $(MAKELEVEL) $$MAKELEVEL'
unset R_MAKEVARS_USER
rm -f "$HOME/.R/Makevars-$plat" "$HOME/.R/Makevars"

if [ "$OS" != windows ]; then
  compare_win windows --help
  compare_win windows --all
  for v in COMPILED_BY LOCAL_SOFT R_TOOLS_SOFT OBJDUMP MAKE CC; do compare_win windows "$v"; done
fi

# What only make can answer: rzig exits 2 and names the construct, the
# file and the line; make answers (the user's decision, no fallback).
need_make() {
  local file="$1" line="$2" var="$3" rc=0
  "$R" CMD config "$var" > a.out 2> a.err || rc=$?
  n=$((n + 1))
  if [ "$rc" != 2 ] || [ -s a.out ] || ! grep -q "^R CMD config: $file:$line: " a.err; then
    fail=$((fail + 1))
    echo "MISMATCH [needs make] R CMD config $var with $file: exit $rc, not 2 with '$file:$line'" >&2
    cat a.out a.err >&2
  fi
}
export R_MAKEVARS_USER="$work/shell.mk"
printf 'X = 1\nCFLAGS := $(shell echo -O1)\n' > "$work/shell.mk"
need_make "$work/shell.mk" 2 CC
printf 'CC = $(shell echo cc)\n' > "$work/shell.mk"
need_make "$work/shell.mk" 1 CC
printf '\ndefine F\nx\nendef\n' > "$work/shell.mk"
need_make "$work/shell.mk" 2 CC
printf 'A != echo a\n' > "$work/shell.mk"
need_make "$work/shell.mk" 1 CC
printf 'CC = $(MAKEFLAGS)\n' > "$work/shell.mk"
need_make "$work/shell.mk" 1 CC
printf '\nCC = cc $$MAKEFLAGS\n' > "$work/shell.mk"
need_make "$work/shell.mk" 2 CC
printf 'CC = $(MAKEFILE_LIST)\n' > "$work/shell.mk"
need_make "$work/shell.mk" 1 CC
printf 'CC = cc *.c\n' > "$work/shell.mk"
need_make "$work/shell.mk" 1 CC
unset R_MAKEVARS_USER

if [ "$fail" != 0 ]; then
  echo "error: R CMD config differs from R's script in $fail of $n cases" >&2
  exit 1
fi
echo "== R CMD config (rzig) matches R's script with make in all $n cases, and exits 2 where only make can answer${skipped:+ ($skipped \$\$SHELL cases left out on Windows)}"
