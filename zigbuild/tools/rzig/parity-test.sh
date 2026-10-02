#!/usr/bin/env bash
# Parity test for rzig (feat-no-host-paths phase F3a): the bash shims in
# toolchain/ (the reference; configure-only.sh still runs them) and the
# rzig binary must turn the same arguments into the same zig command line
# (and the same ZIG_LIB_DIR, the same warnings, the same files made on
# the way), for every OS's branches, from one linux machine.
#
#   zigbuild/tools/rzig/parity-test.sh [path/to/rzig]
#
# Without an argument it builds rzig with $ZIG (default: zig on PATH).
#
# Both sit in a fake installed tree, so that "four levels above my own
# directory" (where OpenMP comes from) names the same place:
#   $W/<tree>/lib/R/bin/toolchain/{zig-cc,...,gcc,g++}  copies of rzig
#   $W/<tree>/lib/R/bin/bash/{zig-cc,...}               the shims, with
#       /usr/bin/xcrun replaced by a stub that prints $FAKE_SDK
# Each case runs three times, in an emptied environment:
#   bash  the shim, with a fake `uname` that answers for the OS under test
#         and ZIG_BIN (or PATH) naming a stub that prints what it was given;
#   dry   rzig with RZIG_PRINT_ARGV=1 RZIG_OS=<os> RZIG_XCRUN=<stub>;
#   real  linux cases only: rzig for real, execve into the same stub.
# Standard output (and state a case inspects) and standard error must be
# equal. Two kinds of difference are deliberate and reported as such when
# they are the only ones: rzig names the tree it is installed in without
# the shim's `<dir>/../../../..` (always applied), and what a case's
# CASE_DELIBERATE sed script does to the bash side, with CASE_WHY.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
shims=$(cd "$here/../../../toolchain" && pwd)
PATH0=$PATH
W=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/rzig-parity.XXXXXX")" && pwd -P)
trap 'rm -rf "$W"' EXIT

RZIG=${1:-}
if [ -z "$RZIG" ]; then
  # (zig's local cache out of the source tree, which the recipe copies)
  "${ZIG:-zig}" build --build-file "$here/build.zig" --cache-dir "${ZIG_LOCAL_CACHE_DIR:-$W/zig-cache}" --prefix "$W/rzig"
  RZIG=$W/rzig/bin/rzig
fi
RZIG=$(cd "$(dirname "$RZIG")" && pwd)/$(basename "$RZIG")

# What the bash shims run besides zig, flang, gfortran and python3, and a
# uname and an xcrun for the OS under test.
mkdir -p "$W/tools"
for t in dirname cksum cut ls mkdir ln sleep; do ln -s "$(command -v "$t")" "$W/tools/$t"; done
cat > "$W/tools/uname" << 'EOF'
#!/bin/sh
case "$1" in -m) echo "$FAKE_UNAME_M" ;; *) echo "$FAKE_UNAME_S" ;; esac
EOF
cat > "$W/tools/xcrun" << 'EOF'
#!/bin/sh
[ "$*" = "--sdk macosx --show-sdk-path" ] && [ -n "${FAKE_SDK:-}" ] && echo "$FAKE_SDK"
exit 0
EOF
chmod +x "$W/tools/uname" "$W/tools/xcrun"

# tree NAME: an installed R_HOME/bin with rzig and the shims side by side
tree() {
  local tc=$W/$1/lib/R/bin/toolchain sh=$W/$1/lib/R/bin/bash n
  mkdir -p "$tc" "$sh"
  for n in zig-cc zig-cxx zig-ar zig-ranlib gcc g++; do cp "$RZIG" "$tc/$n"; done
  for n in zig-cc zig-cxx zig-ar zig-ranlib; do
    sed "s|/usr/bin/xcrun|$W/tools/xcrun|g" "$shims/$n" > "$sh/$n"
    chmod +x "$sh/$n"
  done
}
tree tree                                   # no omp.h: OpenMP from CONDA_PREFIX
tree omptree; mkdir -p "$W/omptree/include" "$W/omptree/lib"; : > "$W/omptree/include/omp.h"
mkdir -p "$W/winomptree/include" "$W/winomptree/lib"; tree winomptree
: > "$W/winomptree/include/omp.h"; : > "$W/winomptree/lib/libomp.lib"

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

STUB=$W/stub/zig
stub "$STUB"
RH=$W/tree/lib/R             # an R_HOME, by name only
SDK=$W/sdk/MacOSX.sdk
mkdir -p "$W/cwd"

# A conda-like zig: <env>/bin/zig with <env>/lib/zig/std/std.zig. Names in
# the lib dir sort differently by byte and by locale, for the mirror key.
zig_env() {
  stub "$1/bin/${2:-zig}"
  touchf "$1/lib/zig/std/std.zig"
  for f in c.zig compiler/x compiler_rt.zig Zed.h _under libcxx/x .hidden; do touchf "$1/lib/zig/$f"; done
}
zig_env "$W/envA"                                   # no libc++ beside
zig_env "$W/envB"; touchf "$W/envB/lib/libc++.so.1"   # conda-forge zig with libcxx
zig_env "$W/envD"; touchf "$W/envD/lib/libc++.1.dylib"
mkdir -p "$W/envC/lib/zig/std"; touchf "$W/envC/lib/zig/std/std.zig"; touchf "$W/envC/lib/libc++.so"
mkdir -p "$W/plain/lib/zig"
stub "$W/mingw/bin/x86_64-w64-mingw32-zig"
stub "$W/py/python3" python3
touchf "$W/noexec/zig"
mirror_state='for f in "$XDG_CACHE_HOME"/r-zig/*/.complete "$XDG_CACHE_HOME"/r-zig/*/lib/zig/* "$XDG_CACHE_HOME"/r-zig/*/lib/zig/.[!.]*; do [ -e "$f" ] || [ -L "$f" ] || continue; printf "%s -> %s\n" "${f#"$XDG_CACHE_HOME"/}" "$(readlink "$f" || :)"; done'

# flang: one whose LLVM has the runtime archive (two triple directories,
# the first in glob order wins), one whose has none, one that fails, one
# that answers as a Windows flang does (CRLF, backslashes).
for d in aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu; do touchf "$W/llvm/lib/clang/23/lib/$d/libflang_rt.runtime.a"; done
touchf "$W/llvm2/lib/clang/23/lib/x86_64-unknown-linux-gnu/libclang_rt.builtins.a"
touchf "$W/winllvm/lib/clang/23/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a"
prog "$W/flang/flang" "echo '$W/llvm/lib/clang/23'"
prog "$W/flang-noarchive/flang" "echo '$W/llvm2/lib/clang/23'"
prog "$W/flang-fails/flang" "echo '$W/llvm/lib/clang/23'; exit 1"
winrd=$(printf '%s' "$W/winllvm/lib/clang/23" | tr / '\\')
prog "$W/flang-win/flang" "printf '%s\\r\\n' '$winrd'"

# Library directories for the Windows -l logic.
for f in libdlla.dll.a ziglib.lib libmsvc.lib stop.dll; do touchf "$W/win/d1/$f"; done
for f in libstop.dll.a libdlla.lib libonly2.dll.a; do touchf "$W/win/d2/$f"; done
touchf "$W/winenv/Library/lib/libomp.lib"
mkdir -p "$W/winenv2/Library/lib"
for f in libgfortran.dll.a libquadmath.dll.a; do touchf "$W/gcclib/$f"; done
prog "$W/gf/gfortran" "echo '$W/gcclib/libgfortran.dll.a'"

pass=0 deliberate=0 fail=0
why_tree="rzig names the tree it is installed in as such, not as the shim's <its dir>/../../../.."

# run_case NAME OS TOOL [ARGS...], with
#   CASE_ENV         VAR=value words for every side (array; default ZIG_BIN=stub,
#                    and FAKE_SDK=$SDK for macos)
#   CASE_PATH        PATH entries searched for zig, python3, flang, gfortran
#   CASE_TREE        the installed tree both run from (default: tree)
#   CASE_RESET       shell code run before each side
#   CASE_STATE       shell code whose output joins each side's
#   CASE_DELIBERATE  sed script for the bash side's output, and CASE_WHY
run_case() {
  local name=$1 os=$2 tool=$3; shift 3
  local shim=$tool uname_s side status ok=1 t=${CASE_TREE:-tree}
  case $tool in gcc) shim=zig-cc ;; g++) shim=zig-cxx ;; esac
  case $os in linux) uname_s=Linux ;; macos) uname_s=Darwin ;; windows) uname_s=MINGW64_NT-10.0-26100 ;; esac
  local -a env=(HOME="$W/home" LC_ALL=C)
  if declare -p CASE_ENV > /dev/null 2>&1; then env+=("${CASE_ENV[@]}"); else env+=(ZIG_BIN="$STUB"); fi
  [ "$os" = macos ] && ! declare -p CASE_ENV > /dev/null 2>&1 && env+=(FAKE_SDK="$SDK")
  local p=${CASE_PATH:-}
  local -a sides=(bash dry)
  [ "$os" = linux ] && sides+=(real)
  for side in "${sides[@]}"; do
    (cd "$W/cwd" && eval "${CASE_RESET:-:}")
    status=0
    case $side in
      bash) (cd "$W/cwd" && env -i "${env[@]}" PATH="${p:+$p:}$W/tools" FAKE_UNAME_S="$uname_s" FAKE_UNAME_M="$(uname -m)" \
              "$BASH" "$W/$t/lib/R/bin/bash/$shim" "$@") > "$W/out.$side" 2> "$W/err.$side" || status=$? ;;
      dry)  (cd "$W/cwd" && env -i "${env[@]}" PATH="$p" RZIG_PRINT_ARGV=1 RZIG_OS="$os" RZIG_XCRUN="$W/tools/xcrun" \
              "$W/$t/lib/R/bin/toolchain/$tool" "$@") > "$W/out.$side" 2> "$W/err.$side" || status=$? ;;
      real) (cd "$W/cwd" && env -i "${env[@]}" PATH="$p" "$W/$t/lib/R/bin/toolchain/$tool" "$@") > "$W/out.$side" 2> "$W/err.$side" || status=$? ;;
    esac
    [ "$status" = 0 ] || { ok=0; echo "    $side exited $status" >> "$W/report"; }
    if [ -n "${CASE_STATE:-}" ]; then
      (cd "$W/cwd" && env -i "${env[@]}" PATH="$PATH0" "$BASH" -c "$CASE_STATE") | sed 's/^/state: /' >> "$W/out.$side"
    fi
    sed 's/^/stderr: /' "$W/err.$side" >> "$W/out.$side"
  done
  # always: the shim's unnormalized "<its dir>/../../../.." is rzig's tree
  sed -e "s|$W/$t/lib/R/bin/bash/\.\./\.\./\.\./\.\.|$W/$t|g" ${CASE_DELIBERATE:+-e "$CASE_DELIBERATE"} "$W/out.bash" > "$W/want"
  for side in "${sides[@]:1}"; do
    cmp -s "$W/want" "$W/out.$side" || { ok=0; diff -u "$W/want" "$W/out.$side" | sed 's/^/    /' >> "$W/report" || :; }
  done
  if [ "$ok" = 1 ] && ! cmp -s "$W/out.bash" "$W/out.dry"; then
    deliberate=$((deliberate + 1))
    printf 'ok*  %-8s %s\n     deliberate: %s\n' "$os" "$name" "${CASE_WHY:-$why_tree}"
    diff "$W/out.bash" "$W/out.dry" | sed 's/^/     /' || :
  elif [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'ok   %-8s %s\n' "$os" "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %-8s %s\n' "$os" "$name"
    cat "$W/report"
  fi
  : > "$W/report"
  unset CASE_ENV CASE_PATH CASE_TREE CASE_RESET CASE_STATE CASE_DELIBERATE CASE_WHY
}
: > "$W/report"

echo "== rzig parity against $shims ($RZIG)"

# --- compile and link, linux ---------------------------------------------------
run_case "compile C" linux zig-cc -std=gnu23 -I"$RH/include" -DNDEBUG -I/usr/local/include -fpic -O2 -Wall -c init.c -o init.o
run_case "compile C++" linux zig-cxx -std=gnu++20 -I"$RH/include" -DNDEBUG -fpic -O2 -c rcpp.cpp -o rcpp.o
run_case "dependency rules (-M)" linux zig-cc -M -I"$RH/include" foo.c
run_case "-MM, -E, -S" linux zig-cxx -MM -E -S foo.cpp
run_case "package link: no SONAME" linux zig-cc -std=gnu23 -shared -L"$RH/lib" -L/usr/local/lib -o pkg.so a.o b.o -L"$RH/lib" -lR
run_case "lib*.so link: SONAME" linux zig-cc -shared -o ../lib/libR.so a.o -lm
run_case "versioned lib*.so*: SONAME" linux zig-cxx -shared -o lib/libfoo.so.1.2 x.o
run_case "lib.so: SONAME" linux zig-cc -shared -o lib.so x.o
run_case "explicit -soname kept" linux zig-cc -shared -Wl,-soname,libkeep.so.0 -o libkeep.so x.o
run_case "-soname anywhere disables it" linux zig-cc -shared -o libk.so '-DX=-soname' x.o
run_case "attached -olib.so not seen" linux zig-cc -shared -olibx.so x.o
run_case "first -o only" linux zig-cc -shared -o pkg.so -o libx.so x.o
run_case "-shared as a word inside an argument" linux zig-cc '-DMSG=a -shared b' -o libq.so q.o
run_case "-Wl,-shared is no -shared" linux zig-cc -Wl,-shared -o libq.so q.o
run_case "quotes and spaces kept" linux zig-cc -DMBEDTLS_CONFIG_FILE='"zip_mbedtls_config.h"' '-DNAME=two words' "-I$W/dir with space" -c z.c
run_case "empty argument kept" linux zig-cc -c '' a.c
run_case "nothing de-duplicated off macOS" linux zig-cc -shared -o pkg.so a.o -lm -lm -L/x -L/x
run_case "gcc name" linux gcc -c a.c
run_case "g++ name, SONAME" linux g++ -shared -o libg.so a.o

# --- the Fortran runtime (Makeconf's FLIBS = -lflang_rt.runtime) ---------------
CASE_PATH="$W/flang"
run_case "FLIBS twice: the archive once" linux zig-cc -shared -L"$RH/lib" -o quadprog.so solve.o -L"$RH/lib" -lRlapack -L"$RH/lib" -lRblas -lflang_rt.runtime -lm -lflang_rt.runtime -lm
CASE_PATH="$W/flang"
run_case "FLIBS on a C++ link" linux zig-cxx -shared -o minqa.so a.o -lflang_rt.runtime
run_case "no flang on PATH: dropped" linux zig-cc -shared -o p.so a.o -lflang_rt.runtime -lm
CASE_PATH="$W/flang-noarchive"
run_case "flang without the archive: dropped, warned" linux zig-cxx -shared -o p.so a.o -lflang_rt.runtime
CASE_PATH="$W/flang-fails"
run_case "flang that fails: dropped" linux zig-cc -shared -o p.so a.o -lflang_rt.runtime
CASE_PATH="$W/flang-noarchive"
run_case "the flag inside an argument: flang asked, nothing replaced" linux zig-cc '-DX=a -lflang_rt.runtime b' -c a.c
CASE_PATH="$W/flang"
run_case "-lflang_rt alone is another library" linux zig-cc -shared -o p.so a.o -lflang_rt -lflang_rt.runtimex

# --- OpenMP ------------------------------------------------------------------------
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env")
run_case "OpenMP compile (CONDA_PREFIX)" linux zig-cc -fopenmp -c a.c
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env")
run_case "OpenMP link" linux zig-cxx -shared -fopenmp -o pkg.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env")
run_case "OpenMP link, caller's -lomp (data.table)" linux zig-cc -shared -fopenmp -o datatable.so a.o -lomp
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env")
run_case "-fopenmp-simd counts (substring)" linux zig-cc -fopenmp-simd -o prog a.o
run_case "OpenMP without CONDA_PREFIX" linux zig-cc -fopenmp -shared -o pkg.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env"); CASE_TREE=omptree
run_case "OpenMP from the tree rzig is in (omp.h there)" linux zig-cc -shared -fopenmp -o pkg.so a.o
CASE_TREE=omptree
run_case "OpenMP from the tree, compile, no CONDA_PREFIX" linux zig-cxx -fopenmp -c a.cpp
CASE_TREE=omptree
run_case "OpenMP from the tree, caller's -lomp" linux zig-cc -shared -fopenmp -o dt.so a.o -lomp
CASE_TREE=omptree
run_case "no -fopenmp: nothing from the tree" linux zig-cc -shared -o pkg.so a.o -lomp

# --- ar, ranlib ----------------------------------------------------------------------
CASE_RESET='rm -f libstat.a'; CASE_STATE='ls libstat.a 2>&1 || :'
run_case "ar rcs (no seed off macOS)" linux zig-ar rcs libstat.a a.o b.o
run_case "ranlib" linux zig-ranlib libstat.a

# --- which zig, and the libc++ mirror ------------------------------------------
CASE_ENV=(); CASE_PATH="$W/envA/bin"
run_case "zig on PATH, no libc++ beside: no mirror" linux zig-cc -c a.c
CASE_ENV=(XDG_CACHE_HOME="$W/cache"); CASE_PATH="$W/envB/bin"
CASE_RESET="rm -rf '$W/cache'"; CASE_STATE=$mirror_state
run_case "libc++.so.1 beside zig: mirror made by each" linux zig-cxx -shared -o libx.so x.o
CASE_ENV=(XDG_CACHE_HOME="$W/cache"); CASE_PATH="$W/envB/bin"; CASE_STATE=$mirror_state
run_case "mirror reused across both" linux zig-cc -c a.c
CASE_ENV=(HOME="$W/home2"); CASE_PATH="$W/envB/bin"
CASE_RESET="rm -rf '$W/home2'"; CASE_STATE='cd "$HOME" && ls -d .cache/r-zig/*'
run_case "mirror under \$HOME/.cache without XDG_CACHE_HOME" linux zig-cc -c a.c
CASE_ENV=(ZIG_BIN="$STUB" ZIG_LIB_DIR="$W/envC/lib/zig" XDG_CACHE_HOME="$W/cache3"); CASE_RESET="rm -rf '$W/cache3'"
run_case "ZIG_LIB_DIR given, libc++.so two up: mirror" linux zig-cc -c a.c
CASE_ENV=(ZIG_BIN="$STUB" ZIG_LIB_DIR="$W/plain/lib/zig")
run_case "ZIG_LIB_DIR without libc++ beside: left alone" linux zig-cc -c a.c
CASE_ENV=(ZIG_BIN="$STUB" ZIG_LIB_DIR="$W/envB/lib/zig" XDG_CACHE_HOME="$W/cache4"); CASE_RESET="rm -rf '$W/cache4'"
CASE_STATE='ls "$XDG_CACHE_HOME" 2>&1 || :'
run_case "ar and ranlib never mirror" linux zig-ar rcs libm.a m.o
CASE_ENV=(ZIG_BIN="$W/noexec/zig"); CASE_PATH="$W/envA/bin"
run_case "ZIG_BIN not executable: PATH" linux zig-cc -c a.c
CASE_ENV=(ZIG_BIN="$W/nowhere/zig"); CASE_PATH="$W/mingw/bin"
run_case "only x86_64-w64-mingw32-zig on PATH" linux zig-cc -c a.c
CASE_ENV=(); CASE_PATH="$W/py"
run_case "no zig anywhere: python3 -m ziglang" linux zig-cxx -c a.cpp
CASE_ENV=(); CASE_PATH="$W/py"
run_case "python3 -m ziglang for ranlib" linux zig-ranlib libx.a
CASE_ENV=(ZIG_LIB_DIR="$W/envB/lib/zig" XDG_CACHE_HOME="$W/cache5"); CASE_PATH="$W/py"; CASE_RESET="rm -rf '$W/cache5'"
run_case "python3 -m ziglang with ZIG_LIB_DIR: mirror" linux zig-cc -c a.c

# --- macOS compiler lines: darwin.zig ------------------------------------------------
run_case "compile: target, SDK frameworks, no SDK -L, -L kept" macos zig-cc -std=gnu23 -I"$RH/include" -fPIC -O2 -c a.c -o a.o -L"$W/mac/a"
run_case "compile: -l deduplicated" macos zig-cc -c -L"$W/mac/a" -lX -lX a.c
run_case "-M: no SDK -L" macos zig-cxx -M -I"$RH/include" a.cpp
CASE_PATH="$W/flang"
run_case "SHLIB link, Fortran: dedup, archive once, SDK -L last" macos zig-cc -std=gnu23 -dynamiclib -Wl,-headerpad_max_install_names -undefined dynamic_lookup \
  -L"$RH/lib" -L/opt/lib -o quadprog.so solve.o -L"$RH/lib" -lRlapack -L"$RH/lib" -lRblas -lflang_rt.runtime -lm -lflang_rt.runtime -lm
run_case "-framework link" macos zig-cc -dynamiclib -o ps.so apps.o -framework AppKit -framework CoreFoundation -lobjc
run_case "-L kept, explicit -rpath kept" macos zig-cxx -shared -L"$W/mac/a" -lX -L"$W/mac/b" -lY -lW -lX -L /sep -Wl,-rpath,/keep -o pkg.so
CASE_ENV=(ZIG_BIN="$STUB")
run_case "no SDK: target only" macos zig-cc -dynamiclib -o pkg.so a.o -lz
CASE_ENV=(ZIG_BIN="$STUB" FAKE_SDK="$SDK" CONDA_PREFIX="$W/macenv")
run_case "OpenMP link: libomp, SDK -L after it" macos zig-cc -dynamiclib -fopenmp -o pkg.so a.o
CASE_ENV=(ZIG_BIN="$STUB" FAKE_SDK="$SDK" CONDA_PREFIX="$W/macenv")
run_case "data.table: -Xclang -fopenmp, -lomp twice" macos zig-cc -dynamiclib -Xclang -fopenmp -o datatable.so a.o -lomp -lomp
CASE_ENV=(ZIG_BIN="$STUB" FAKE_SDK="$SDK" CONDA_PREFIX="$W/macenv")
run_case "OpenMP compile" macos zig-cxx -Xclang -fopenmp -c a.cpp
CASE_TREE=omptree
run_case "OpenMP from the tree" macos zig-cxx -dynamiclib -fopenmp -o pkg.so a.o -lomp
run_case "lib*.so link: SONAME (all OSes)" macos zig-cc -shared -o libfoo.so a.o
CASE_ENV=(XDG_CACHE_HOME="$W/cache6" FAKE_SDK="$SDK"); CASE_PATH="$W/envD/bin"; CASE_RESET="rm -rf '$W/cache6'"; CASE_STATE=$mirror_state
run_case "libc++.1.dylib beside zig: mirror" macos zig-cxx -dynamiclib -o pkg.so a.o
run_case "gcc name" macos gcc -c a.c

# --- macOS ar: ar.zig's archive seed ----------------------------------------------
CASE_RESET='rm -f libnew.a'; CASE_STATE='od -c libnew.a | head -2'
run_case "ar rcs, missing archive: seed + darwin format" macos zig-ar rcs libnew.a a.o
CASE_RESET='rm -f libf.a'; CASE_STATE='od -c libf.a | head -2'
run_case "ar --format kept, seed written" macos zig-ar --format=gnu rcs libf.a a.o
CASE_RESET="printf 'x' > libold.a"; CASE_STATE='cat libold.a; echo'
run_case "ar on an existing archive: untouched" macos zig-ar rcs libold.a a.o
CASE_RESET='rm -f libq.a'; CASE_STATE='ls libq.a'
run_case "ar q" macos zig-ar q libq.a a.o
CASE_RESET='rm -f libd.a'; CASE_STATE='ls libd.a'
run_case "ar -rcs (dash form)" macos zig-ar -rcs libd.a a.o
CASE_STATE='ls libnone.a 2>&1 || :'
run_case "ar t: no seed" macos zig-ar t libnone.a
CASE_STATE='ls libp.a 2>&1 || :'
run_case "ar --plugin x rcs: x taken as the operation, no seed" macos zig-ar --plugin x rcs libp.a a.o
CASE_STATE='ls nodir 2>&1 || :'
CASE_DELIBERATE='s|^stderr: .*: nodir/libz\.a: No such file or directory$|stderr: zig-ar: cannot create nodir/libz.a: FileNotFound|'
CASE_WHY="the message for an archive it cannot seed is rzig's own, not bash's redirection error"
run_case "ar into a missing directory: warned, still pinned" macos zig-ar rcs nodir/libz.a a.o
run_case "ranlib" macos zig-ranlib libnew.a

# --- Windows: windows.zig (gcc/g++ as Makeconf.win names them) --------------------------
run_case "compile: no target, no mirror" windows gcc -std=gnu2x -I"$RH/include" -DNDEBUG -O2 -Wall -c a.c -o a.o
run_case "-l lookup: .dll.a, zig's own names, lib<n>.lib" windows gcc -shared -s -static-libgcc -o pkg.dll tmp.def a.o \
  -L"$W/win/d1" -L"$W/win/d2" -ldlla -lziglib -lmsvc -lstop -lonly2 -lnowhere -L"$RH/bin/x64" -lR
run_case "-mwindows link set" windows gcc -mwindows -o Rgui.exe a.o -L"$W/win/d1" -ldlla
run_case "lib*.so link: SONAME (all OSes)" windows g++ -shared -o libfoo.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/winenv")
run_case "OpenMP: libomp.lib by path" windows g++ -shared -fopenmp -o pkg.dll a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/winenv2")
run_case "OpenMP: no libomp.lib, -L -lomp" windows gcc -fopenmp -shared -o pkg.dll a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/winenv")
run_case "caller's -lomp resolved to libomp.lib" windows gcc -fopenmp -shared -o pkg.dll a.o -L"$W/winenv/Library/lib" -lomp
CASE_TREE=winomptree
run_case "OpenMP from the tree (<prefix>/Library)" windows g++ -shared -fopenmp -o pkg.dll a.o
CASE_PATH="$W/flang-win"
run_case "FLIBS: Windows flang's answer, then -lc++" windows gcc -shared -o pkg.dll a.o -L"$W/win/d1" -lflang_rt.runtime -lc++ -lflang_rt.runtime -lc++
CASE_PATH="$W/gf"
run_case "-lgfortran: gfortran's libdir searched and added" windows gcc -shared -o pkg.dll a.o -lgfortran -lquadmath -lm
CASE_DELIBERATE='/^-L\.$/d'
CASE_WHY="no gfortran: the shim's dirname turned that into -L. (search the current directory); rzig adds nothing"
run_case "-lgfortran without gfortran" windows gcc -shared -o pkg.dll a.o -lgfortran
CASE_ENV=(XDG_CACHE_HOME="$W/cache7"); CASE_PATH="$W/envB/bin"; CASE_STATE='ls "$XDG_CACHE_HOME" 2>&1 || :'
run_case "libc++ beside zig: no mirror on Windows" windows zig-cxx -shared -o pkg.dll a.o
run_case "ar and ranlib passthrough" windows zig-ar rcs libw.a a.o

echo "== $pass identical, $deliberate deliberate differences, $fail failed"
[ "$fail" = 0 ]
