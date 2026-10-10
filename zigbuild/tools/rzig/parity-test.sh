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
# directory" (where the shims' OpenMP comes from) names the place rzig
# finds its own environment in (environment.zig):
#   $W/<tree>/lib/R/bin/toolchain/{zig-cc,...,gcc,g++}  copies of rzig
#   $W/<tree>/lib/R/bin/bash/{zig-cc,...}               the shims, with
#       /usr/bin/xcrun replaced by a stub that prints $FAKE_SDK
# (the Windows tree is $W/winomptree/Library/lib/R/bin/...).
# Each case runs three times, in an emptied environment:
#   bash  the shim, with a fake `uname` that answers for the OS under test
#         and ZIG_BIN (or PATH) naming a stub that prints what it was given;
#   dry   rzig with RZIG_PRINT_ARGV=1 RZIG_OS=<os> RZIG_XCRUN=<stub>;
#   real  linux cases only: rzig for real, execve into the same stub.
# Standard output (and state a case inspects) and standard error must be
# equal. Four kinds of difference are deliberate and reported as such
# when they are the only ones:
#   - rzig names the tree it is installed in without the shim's
#     `<dir>/../../../..` (always applied to the bash side);
#   - rzig adds -L<tree>/lib, its own environment's (F3b: Makeconf's
#     LDFLAGS did that before, the shims never), on every link line: taken
#     out of rzig's side (where it goes is compiler.zig's unit tests'
#     business) and reported as "ok+";
#   - rzig adds the finalization object of linux shared libraries
#     (dso_fini.zig) and the CFG stub of Windows links (cfguard.zig), each
#     compiled once into its cache, which a shim cannot reasonably do:
#     taken out of its side too, after checking that it is there exactly
#     when the rule says (a linux link with -shared as a word, no
#     -nostartfiles or -nostdlib; a Windows command with -o as a word; no
#     compile-only flag), and reported as "ok+". The zig stand-ins write
#     the object rzig asks them to compile;
#   - what a case's CASE_DELIBERATE sed script does to the bash side, with
#     CASE_WHY: F3b's other differences (rzig never reads CONDA_PREFIX; the
#     tree's headers on every call, -idirafter on Windows), the message
#     for an archive ar cannot seed, an archive input passed as an .a
#     copy in rzig's cache (archives.zig), no -Wl,--strip-debug on a
#     link whose input objects have debug info (strip.zig reads them; a
#     shim cannot reasonably parse ELF), and the toolchain's openmp/
#     (feat-standalone-toolchain B40: rzig counts it when the base has the
#     libomp runtime; the shims never knew it).
# check NAME COMMAND... adds a case that passes when COMMAND does: the
# check mode (check.zig) runs that way, the real binary with the real zig.
# zig-fc (F3c) has no bash shim to compare with: fortran.zig's unit tests
# cover it.
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
  for n in zig-cc zig-cxx zig-ar zig-ranlib gcc g++ gcc-ar gcc-ranlib; do cp "$RZIG" "$tc/$n"; done
  for n in zig-cc zig-cxx zig-ar zig-ranlib; do
    sed "s|/usr/bin/xcrun|$W/tools/xcrun|g" "$shims/$n" > "$sh/$n"
    chmod +x "$sh/$n"
  done
}
tree tree                                   # no omp.h: the shims' OpenMP from CONDA_PREFIX
tree omptree; mkdir -p "$W/omptree/include" "$W/omptree/lib"; : > "$W/omptree/include/omp.h"
# installed on Windows: <prefix>/Library/lib/R/bin/toolchain
W_LIB=winomptree/Library W_LIB2=winomptree2/Library
mkdir -p "$W/$W_LIB/include" "$W/$W_LIB/lib"; tree "$W_LIB"
: > "$W/$W_LIB/include/omp.h"; : > "$W/$W_LIB/lib/libomp.lib"
mkdir -p "$W/$W_LIB2/include" "$W/$W_LIB2/lib"; tree "$W_LIB2"; : > "$W/$W_LIB2/include/omp.h"

# stub <path> [argv0]: stands in for zig (or python3), prints the child's
# ZIG_LIB_DIR when it has one, then its argv, one per line: the format of
# RZIG_PRINT_ARGV.
stub() {
  mkdir -p "$(dirname "$1")"
  {
    echo '#!/bin/sh'
    echo 'if [ -n "${ZIG_LIB_DIR+x}" ]; then printf "ZIG_LIB_DIR=%s\n" "$ZIG_LIB_DIR"; fi'
    # the objects rzig compiles into its cache (dso_fini.zig, cfguard.zig):
    # the compile's -o written
    echo 'o=; p=; for a in "$@"; do [ "$p" = -o ] && o=$a; p=$a; done; case "$o" in */r-zig/dso-fini-*|*/r-zig/cfguard-*) : > "$o" ;; esac'
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

# The toolchain's groups (feat-standalone-toolchain phase 2): zig and flang
# in R_HOME/bin/toolchain/{zig,flang/bin}, which win over the ones in the
# environment's bin/ (no archive there), which win over PATH's; openmp/,
# which counts only when the base has the libomp runtime (B40).
tree tctree
stub "$W/tctree/lib/R/bin/toolchain/zig/zig"
prog "$W/tctree/lib/R/bin/toolchain/flang/bin/flang" "echo '$W/llvm/lib/clang/23'"
stub "$W/tctree/bin/zig"; prog "$W/tctree/bin/flang" "echo '$W/llvm2/lib/clang/23'"
tree bintree
stub "$W/bintree/bin/zig"; prog "$W/bintree/bin/flang" "echo '$W/llvm/lib/clang/23'"
W_BIN=winbintree/Library
mkdir -p "$W/$W_BIN/lib"; tree "$W_BIN"; stub "$W/$W_BIN/bin/x86_64-w64-mingw32-zig"
for t in omptc omptcmin; do tree $t; touchf "$W/$t/lib/R/bin/toolchain/openmp/include/omp.h"; done
touchf "$W/omptc/lib/libomp.so"          # omptcmin has none, as minimal
W_OMPTC=winomptc/Library
mkdir -p "$W/$W_OMPTC/lib"; tree "$W_OMPTC"
touchf "$W/$W_OMPTC/lib/R/bin/toolchain/openmp/include/omp.h"; touchf "$W/$W_OMPTC/lib/R/bin/toolchain/openmp/lib/libomp.lib"
touchf "$W/$W_OMPTC/lib/R/bin/x64/libomp.dll"

# Library directories for the Windows -l logic.
for f in libdlla.dll.a ziglib.lib libmsvc.lib stop.dll; do touchf "$W/win/d1/$f"; done
for f in libstop.dll.a libdlla.lib libonly2.dll.a; do touchf "$W/win/d2/$f"; done
touchf "$W/winenv/Library/lib/libomp.lib"
for f in libgfortran.dll.a libquadmath.dll.a; do touchf "$W/gcclib/$f"; done
prog "$W/gf/gfortran" "echo '$W/gcclib/libgfortran.dll.a'"

pass=0 own=0 deliberate=0 fail=0
obj_re='/r-zig/(dso-fini-[0-9a-f]*/dso_fini|cfguard-[0-9a-f]*/guard_dispatch)\.o$'
why_tree="rzig names the tree it is installed in as such, not as the shim's <its dir>/../../../.."
why_conda="rzig never reads CONDA_PREFIX (F3b): an activated env R is not installed in adds nothing"

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
  local shim=$tool uname_s side status ok=1 t=${CASE_TREE:-tree} obj_want=0 n a
  case $tool in gcc) shim=zig-cc ;; g++) shim=zig-cxx ;; gcc-ar) shim=zig-ar ;; gcc-ranlib) shim=zig-ranlib ;; esac
  case $os in linux) uname_s=Linux ;; macos) uname_s=Darwin ;; windows) uname_s=MINGW64_NT-10.0-26100 ;; esac
  local -a env=(HOME="$W/home" LC_ALL=C)
  if declare -p CASE_ENV > /dev/null 2>&1; then env+=("${CASE_ENV[@]}"); else env+=(ZIG_BIN="$STUB"); fi
  [ "$os" = macos ] && ! declare -p CASE_ENV > /dev/null 2>&1 && env+=(FAKE_SDK="$SDK")
  local p=${CASE_PATH:-}
  # the finalization object's rule (dso_fini.zig's `wanted`, linux only)
  # and the CFG stub's (cfguard.zig's `wanted`, Windows only: an -o)
  if [ "$os" = linux ] && [ "$shim" != zig-ar ] && [ "$shim" != zig-ranlib ] &&
    [[ " $* " == *" -shared "* && " $* " != *" -nostartfiles "* && " $* " != *" -nostdlib "* ]]; then
    obj_want=1
  elif [ "$os" = windows ] && [ "$shim" != zig-ar ] && [ "$shim" != zig-ranlib ] && [[ " $* " == *" -o "* ]]; then
    obj_want=1
  fi
  if [ "$obj_want" = 1 ]; then
    for a in "$@"; do case "$a" in -c|-S|-E|-M|-MM) obj_want=0 ;; esac; done
  fi
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
  # always: rzig's -L into its own environment (F3b) and the object it
  # compiles (dso_fini.zig, cfguard.zig), taken out of its side
  local own_l="-L$W/$t/lib" own_added=0
  for side in "${sides[@]:1}"; do
    grep -qxF -- "$own_l" "$W/out.$side" && own_added=1
    n=$(grep -cE -- "$obj_re" "$W/out.$side" || :)
    [ "$n" = 0 ] || own_added=1
    [ "$n" = "$obj_want" ] || { ok=0; echo "    $side: $n objects rzig compiled, want $obj_want" >> "$W/report"; }
    grep -vxF -- "$own_l" "$W/out.$side" | { grep -vE -- "$obj_re" || :; } > "$W/cmp.$side"
    cmp -s "$W/want" "$W/cmp.$side" || { ok=0; diff -u "$W/want" "$W/cmp.$side" | sed 's/^/    /' >> "$W/report" || :; }
  done
  if [ "$ok" = 1 ] && ! cmp -s "$W/out.bash" "$W/cmp.dry"; then
    deliberate=$((deliberate + 1))
    printf 'ok*  %-8s %s\n     deliberate: %s\n' "$os" "$name" "${CASE_WHY:-$why_tree}"
    diff "$W/out.bash" "$W/out.dry" | sed 's/^/     /' || :
  elif [ "$ok" = 1 ] && [ "$own_added" = 1 ]; then
    own=$((own + 1)); printf 'ok+  %-8s %s\n' "$os" "$name"
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

check() {
  local name=$1; shift
  if "$@" > /dev/null 2>&1; then
    pass=$((pass + 1)); printf 'ok   %-8s %s\n' check "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %-8s %s\n' check "$name"
  fi
}

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
run_case "a package's own -march/-mcpu after -mcpu=baseline" linux zig-cxx -march=native -mcpu=haswell -O2 -c a.cpp
run_case "-mtune= dropped (zig would take it as the CPU)" linux zig-cc -mtune=native -O2 -mtune=haswell -march=x86-64 -c a.c

# --- debug info, __DATE__ (compiler.zig): every case has -Wno-error=date-time ----
# (every linux link without a -g option has -Wl,--strip-debug; in rzig, not
# one with an input object that has debug info)
run_case "-g given: no -g0" linux zig-cc -g -O2 -c a.c -o a.o
run_case "-ggdb3, -gdwarf-4: no -g0" linux zig-cxx -O2 -ggdb3 -gdwarf-4 -c a.cpp -o a.o
run_case "-g on a shared link: no -g0, no --strip-debug" linux zig-cxx -g -shared -o pkg.so a.o
run_case "-gline-tables-only on an executable link: no --strip-debug" linux zig-cc -O2 -gline-tables-only -o prog a.o
# strip.zig's objects (testdata/): one compiled with -g, one with -g0
cp "$here/testdata/f-g.o" "$W/cwd/dbg.o"; cp "$here/testdata/f-g0.o" "$W/cwd/nodbg.o"; cp "$here/testdata/f-g.o" "$W/cwd/libdbg.a"
CASE_DELIBERATE='/^-Wl,--strip-debug$/d'
CASE_WHY="rzig reads the link's input objects (strip.zig): one with debug info keeps it; the shims do not parse ELF"
run_case "an input object with debug info: no --strip-debug (load_all())" linux zig-cxx -shared -o pkg.so nodbg.o dbg.o -lR
run_case "objects without debug info, an archive with some: --strip-debug" linux zig-cc -shared -o pkg.so nodbg.o libdbg.a
run_case "a caller's -Werror=date-time after ours" linux zig-cc -Werror=date-time -O2 -c a.c -o a.o

# --- -march=armv<N>-a[+ext] in zig's words (compiler.zig's marchArgs) ------------
run_case "-march=armv8-a+crc: -mcpu=generic+v8a+crc" linux zig-cc -march=armv8-a+crc -O2 -c a.c -o a.o
run_case "-march=armv9-a, empty extension items" linux zig-cxx -O2 -march=armv9-a++sve2+ -c a.cpp
run_case "-march=armv8-a, clang's fcma, jscvt, pmuv3, nopredres2" linux zig-cc -march=armv8-a+fcma+jscvt+pmuv3+nopredres2 -c a.c
run_case "other -march values kept" linux zig-cc -march=armv8-r -march=armv-a -march=armvx-a -march=native -march= -c a.c

# --- linker options zig cannot take (linker_args.zig) -----------------------------
run_case "-Wl,-L<dir>: a plain -L (RcppParallel)" linux zig-cxx -shared -o RcppParallel.so a.o -Wl,-Ltbb/build/lib_release -ltbb '-Wl,-rpath,$ORIGIN/../lib'
run_case "-Xlinker -L and --library-path forms" linux zig-cc -shared -o p.so a.o -Xlinker -L/a -Xlinker -L -Xlinker /b -Wl,--library-path=/c,--library-path,/d,-z,now -Wl,-L,/e -lx
run_case "CMake's --dependency-file dropped" linux zig-cxx -shared -Xlinker --dependency-file=CMakeFiles/tbb.dir/link.d -o libtbb.so.2 a.o
run_case "--dependency-file, other spellings" linux zig-cc -o x a.o -Wl,--dependency-file,x.d,-z,now -Xlinker --dependency-file -Xlinker y.d -Wl,--dependency-file=z.d
run_case "-z muldefs and --allow-multiple-definition dropped, every form" linux zig-cc -shared -o p.so a.o -z muldefs -Wl,-z,muldefs,-z,now \
  -Xlinker -z -Xlinker muldefs -Wl,-zmuldefs,-allow-multiple-definition -Xlinker --allow-multiple-definition -z defs
run_case "other linker options kept, as they were" linux zig-cc -shared -o p.so a.o -Wl,-z,relro,,-L/x -Wl, -Xlinker -rpath -Xlinker /r -Wl,-L -Wl,-L, -Xlinker

# --- version scripts on linux (compiler.zig) --------------------------------------
run_case "version script: --undefined-version (tbbmalloc)" linux zig-cc -shared -Wl,--version-script=tbbmalloc.def -o libtbbmalloc.so.2 a.o
run_case "the caller's --no-undefined-version after ours" linux zig-cxx -shared -Wl,-version-script,v.map -Wl,--no-undefined-version -o p.so a.o
run_case "version script on a compile: nothing" linux zig-cc -Wl,--version-script=v.map -c a.c

# --- linux shared libraries' finalization object (dso_fini.zig) -------------------
CASE_RESET="rm -rf '$W/home/.cache/r-zig'/dso-fini-*"
CASE_STATE='cd "$HOME/.cache/r-zig" 2> /dev/null && for f in dso-fini-*/*; do [ -e "$f" ] && echo "${f#*/}"; done; :'
CASE_DELIBERATE='$a state: dso_fini.c
$a state: dso_fini.o'
CASE_WHY="rzig compiles dso_fini.c into its cache once (state: that directory's files)"
run_case "shared link: the object, compiled once" linux zig-cxx -shared -o lme4.so a.o
run_case "-nostartfiles: no object" linux zig-cc -shared -nostartfiles -o p.so crtbeginS.o a.o crtendS.o
run_case "-nostdlib: no object" linux zig-cc -shared -nostdlib -o p.so a.o

# --- an archive input without zig's extension (archives.zig) ----------------------
mkdir -p "$W/cwd/.deps"; printf '!<arch>\nv8 member\n' > "$W/cwd/.deps/v8_monolith"
printf 'not an archive\n' > "$W/cwd/.deps/notar"; cp "$W/cwd/.deps/v8_monolith" "$W/cwd/.deps/libv8.a"
v8_copy="$W/home/.cache/r-zig/archive-$(sha256sum "$W/cwd/.deps/v8_monolith" | cut -c1-32)/v8_monolith.a"
why_ar="zig takes a link input by its extension: rzig passes an archive named without one as an .a copy in its cache"
for os in linux macos windows; do
  CASE_DELIBERATE="s|^\.deps/v8_monolith\$|$v8_copy|"; CASE_WHY=$why_ar
  run_case "an archive without an extension: an .a copy (V8)" $os zig-cxx -shared -o V8.so a.o .deps/v8_monolith -lR
done
check "the .a copy has the archive's bytes" cmp "$W/cwd/.deps/v8_monolith" "$v8_copy"
run_case "not an archive, a name zig takes, an option's value: unchanged" linux zig-cc -shared -o p.so a.o .deps/notar .deps/libv8.a -Xlinker .deps/v8_monolith

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
# a Makevars written for gcc: -lgfortran and -lquadmath are flang's runtime
CASE_PATH="$W/flang"
run_case "-lgfortran -lquadmath, then FLIBS: the archive once" linux zig-cc -shared -o p.so a.o -lgfortran -lquadmath -lm -lflang_rt.runtime -lm
CASE_PATH="$W/flang"
run_case "-lquadmath alone: the archive" linux zig-cxx -shared -o p.so a.o -lquadmath
run_case "-lgfortran -lquadmath without flang: dropped" linux zig-cc -shared -o p.so a.o -lgfortran -lquadmath -lm
CASE_PATH="$W/flang"
run_case "-lgfortran5, -lquadmathx and a word inside an argument are other things" linux zig-cc -shared -o p.so a.o -lgfortran5 -lquadmathx '-DX=a -lgfortran b'

# --- OpenMP ------------------------------------------------------------------------
# The shims took OpenMP from CONDA_PREFIX when their tree had no omp.h, and
# put the tree's -L after the caller's arguments with -lomp; rzig ignores
# CONDA_PREFIX and adds its environment's -L to every link (F3b), after the
# caller's arguments (R2).
why_omp="the shims' OpenMP -L<tree>/lib is rzig's own-environment -L (on every link, F3b)"
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env"); CASE_DELIBERATE="\|^-I$W/env/include\$|d"; CASE_WHY=$why_conda
run_case "OpenMP compile (CONDA_PREFIX ignored)" linux zig-cc -fopenmp -c a.c
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env"); CASE_DELIBERATE="\|^-[IL]$W/env/|d
/^-lomp\$/d"; CASE_WHY=$why_conda
run_case "OpenMP link (CONDA_PREFIX ignored)" linux zig-cxx -shared -fopenmp -o pkg.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env"); CASE_DELIBERATE="\|^-[IL]$W/env/|d"; CASE_WHY=$why_conda
run_case "OpenMP link, caller's -lomp (data.table; CONDA_PREFIX ignored)" linux zig-cc -shared -fopenmp -o datatable.so a.o -lomp
CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "-fopenmp-simd counts (substring)" linux zig-cc -fopenmp-simd -o prog a.o
run_case "OpenMP without omp.h anywhere" linux zig-cc -fopenmp -shared -o pkg.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/env"); CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "OpenMP from the tree rzig is in (omp.h there)" linux zig-cc -shared -fopenmp -o pkg.so a.o
CASE_TREE=omptree
run_case "OpenMP from the tree, compile, no CONDA_PREFIX" linux zig-cxx -fopenmp -c a.cpp
CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "OpenMP from the tree, caller's -lomp" linux zig-cc -shared -fopenmp -o dt.so a.o -lomp
CASE_TREE=omptree; CASE_DELIBERATE="\$a -I$W/omptree/include"
CASE_WHY="rzig adds its environment's headers to every call, not only -fopenmp ones (F3b)"
run_case "no -fopenmp: the tree's headers, no -lomp" linux zig-cc -shared -o pkg.so a.o -lomp
# the toolchain's openmp/ (feat-standalone-toolchain B40)
why_tc_omp="rzig counts the toolchain's openmp/ when the base has the libomp runtime (B40): its headers on every call, -lomp on a -fopenmp link; the shims never knew it"
tc_omp=$W/omptc/lib/R/bin/toolchain/openmp
CASE_TREE=omptc; CASE_DELIBERATE="\$a -I$tc_omp/include
\$a -lomp"; CASE_WHY=$why_tc_omp
run_case "OpenMP from the toolchain's openmp/ (libomp.so in the base)" linux zig-cc -shared -fopenmp -o pkg.so a.o
CASE_TREE=omptc; CASE_DELIBERATE="\$a -I$tc_omp/include"; CASE_WHY=$why_tc_omp
run_case "the toolchain's openmp/ headers on a compile" linux zig-cxx -c a.cpp
CASE_TREE=omptc; CASE_DELIBERATE="\$a -I$tc_omp/include"; CASE_WHY=$why_tc_omp
run_case "the toolchain's openmp/: the caller's -lomp, none added" linux zig-cc -shared -fopenmp -o dt.so a.o -lomp
CASE_TREE=omptcmin
run_case "openmp/ without the base's libomp (minimal): nothing" linux zig-cc -shared -fopenmp -o pkg.so a.o

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

# --- the toolchain's groups: zig/, flang/bin/, the environment's bin/ (B2, B34) ---
CASE_ENV=(); CASE_PATH="$W/envA/bin:$W/flang-noarchive"; CASE_TREE=tctree
run_case "zig/ and flang/bin/ in the toolchain, before the environment's bin and PATH" linux zig-cc -shared -o p.so a.o -lflang_rt.runtime -lm
CASE_ENV=(); CASE_PATH="$W/envA/bin:$W/flang-noarchive"; CASE_TREE=tctree
run_case "the toolchain's flang/bin/ after -march=armv8-a+crc" linux zig-cc -march=armv8-a+crc -shared -o p.so a.o -lflang_rt.runtime
CASE_ENV=(); CASE_PATH="$W/envA/bin:$W/flang-noarchive"; CASE_TREE=tctree
run_case "the toolchain's flang/bin/ after -march=armv8-a+crc (C++)" linux zig-cxx -march=armv8-a+crc -shared -o p.so a.o -lflang_rt.runtime
CASE_ENV=(); CASE_PATH="$W/envA/bin"; CASE_TREE=tctree
run_case "the toolchain's zig for ar" linux zig-ar rcs libt.a a.o
CASE_PATH="$W/envA/bin"; CASE_TREE=tctree
run_case "ZIG_BIN before the toolchain's zig" linux zig-cxx -c a.cpp
CASE_ENV=(); CASE_PATH="$W/envA/bin:$W/flang-noarchive"; CASE_TREE=bintree
run_case "the environment's bin, before PATH (a conda env, not activated)" linux zig-cxx -shared -o p.so a.o -lflang_rt.runtime
CASE_ENV=(); CASE_PATH="$W/envA/bin"; CASE_TREE=$W_BIN
run_case "Windows: the environment's bin/x86_64-w64-mingw32-zig, before PATH's zig" windows gcc -c a.c
CASE_ENV=(); CASE_PATH="$W/envA/bin"; CASE_TREE=$W_BIN
run_case "Windows: gcc-ranlib through the environment's zig" windows gcc-ranlib libw.a

# --- macOS compiler lines: darwin.zig ------------------------------------------------
run_case "compile: target, SDK frameworks, no SDK -L, -L kept" macos zig-cc -std=gnu23 -I"$RH/include" -fPIC -O2 -c a.c -o a.o -L"$W/mac/a"
run_case "compile: -l deduplicated" macos zig-cc -c -L"$W/mac/a" -lX -lX a.c
run_case "-M: no SDK -L" macos zig-cxx -M -I"$RH/include" a.cpp
CASE_PATH="$W/flang"
run_case "SHLIB link, Fortran: dedup, archive once, SDK -L last" macos zig-cc -std=gnu23 -dynamiclib -Wl,-headerpad_max_install_names -undefined dynamic_lookup \
  -L"$RH/lib" -L/opt/lib -o quadprog.so solve.o -L"$RH/lib" -lRlapack -L"$RH/lib" -lRblas -lflang_rt.runtime -lm -lflang_rt.runtime -lm
run_case "-framework link" macos zig-cc -dynamiclib -o ps.so apps.o -framework AppKit -framework CoreFoundation -lobjc
CASE_PATH="$W/flang"
run_case "-lgfortran -lquadmath, then FLIBS: the archive once, SDK -L last" macos zig-cc -dynamiclib -undefined dynamic_lookup -o p.so a.o -lgfortran -lquadmath -lflang_rt.runtime -lm
run_case "-L kept, explicit -rpath kept" macos zig-cxx -shared -L"$W/mac/a" -lX -L"$W/mac/b" -lY -lW -lX -L /sep -Wl,-rpath,/keep -o pkg.so
CASE_ENV=(ZIG_BIN="$STUB")
run_case "no SDK: target only" macos zig-cc -dynamiclib -o pkg.so a.o -lz
CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "OpenMP link: libomp, SDK -L after it" macos zig-cc -dynamiclib -fopenmp -o pkg.so a.o
CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "data.table: -Xclang -fopenmp, -lomp twice" macos zig-cc -dynamiclib -Xclang -fopenmp -o datatable.so a.o -lomp -lomp
CASE_ENV=(ZIG_BIN="$STUB" FAKE_SDK="$SDK" CONDA_PREFIX="$W/macenv"); CASE_DELIBERATE="\|^-I$W/macenv/include\$|d"; CASE_WHY=$why_conda
run_case "OpenMP compile (CONDA_PREFIX ignored)" macos zig-cxx -Xclang -fopenmp -c a.cpp
CASE_TREE=omptree; CASE_DELIBERATE="\|^-L$W/omptree/lib\$|d"; CASE_WHY=$why_omp
run_case "OpenMP from the tree" macos zig-cxx -dynamiclib -fopenmp -o pkg.so a.o -lomp
CASE_TREE=omptc; CASE_DELIBERATE="\$i -I$tc_omp/include
\$i -lomp"; CASE_WHY=$why_tc_omp
run_case "OpenMP from the toolchain's openmp/, before the SDK -L" macos zig-cc -dynamiclib -fopenmp -o pkg.so a.o
run_case "lib*.so link: SONAME (all OSes)" macos zig-cc -shared -o libfoo.so a.o
CASE_ENV=(XDG_CACHE_HOME="$W/cache6" FAKE_SDK="$SDK"); CASE_PATH="$W/envD/bin"; CASE_RESET="rm -rf '$W/cache6'"; CASE_STATE=$mirror_state
run_case "libc++.1.dylib beside zig: mirror" macos zig-cxx -dynamiclib -o pkg.so a.o
run_case "gcc name" macos gcc -c a.c
run_case "a package's own -mcpu after -mcpu=baseline" macos zig-cc -mcpu=native -c a.c
run_case "-mtune= dropped" macos zig-cxx -mtune=native -c a.cpp

run_case "-g0 given: once" macos zig-cc -g0 -c a.c
run_case "-march=armv8.2-a, clang's extension names" macos zig-cc -march=armv8.2-a+simd+nocrypto+fp16+sve2-aes+rdma+rng+memtag+profile -c a.c
run_case "-Xarch_<arch>'s value kept (abseil's CMake)" macos zig-cxx -Xarch_x86_64 -maes -Xarch_arm64 -march=armv8-a+crypto -Xarch_arm64 -mtune=apple-m1 -c a.cpp
run_case "-Wl,-L<dir>: a plain -L" macos zig-cc -dynamiclib -o p.so a.o -Wl,-L/opt/tbb -ltbb
run_case "no --undefined-version off linux" macos zig-cc -dynamiclib -Wl,--version-script=v.map -o p.so a.o
run_case "shared link: no finalization object off linux" macos zig-cxx -shared -o p.so a.o

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
run_case "compile: no target, -mcpu=baseline, no mirror" windows gcc -std=gnu2x -I"$RH/include" -DNDEBUG -O2 -Wall -c a.c -o a.o
run_case "a package's own -march after -mcpu=baseline" windows g++ -march=native -c a.cpp
run_case "-mtune= dropped" windows gcc -mtune=generic -O2 -c a.c -o a.o
run_case "-l lookup: .dll.a, zig's own names, lib<n>.lib" windows gcc -shared -s -static-libgcc -o pkg.dll tmp.def a.o \
  -L"$W/win/d1" -L"$W/win/d2" -ldlla -lziglib -lmsvc -lstop -lonly2 -lnowhere -L"$RH/bin/x64" -lR
run_case "-mwindows link set" windows gcc -mwindows -o Rgui.exe a.o -L"$W/win/d1" -ldlla
run_case "lib*.so link: SONAME (all OSes)" windows g++ -shared -o libfoo.so a.o
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/winenv"); CASE_DELIBERATE="\|$W/winenv/|d"; CASE_WHY=$why_conda
run_case "OpenMP (CONDA_PREFIX ignored)" windows g++ -shared -fopenmp -o pkg.dll a.o
# the shims' last two lines are their CONDA_PREFIX -I and -L
CASE_ENV=(ZIG_BIN="$STUB" CONDA_PREFIX="$W/winenv"); CASE_WHY=$why_conda
CASE_DELIBERATE="\|^-I$W/winenv/Library/include\$|d
\$ {\|^-L$W/winenv/Library/lib\$|d}"
run_case "caller's -lomp resolved to libomp.lib (CONDA_PREFIX ignored)" windows gcc -fopenmp -shared -o pkg.dll a.o -L"$W/winenv/Library/lib" -lomp
why_win="rzig gives its environment's headers to every Windows compile with -idirafter, after MinGW's (F3b)"
CASE_TREE=$W_LIB; CASE_DELIBERATE="s|^-I\\($W/$W_LIB/include\\)\$|-idirafter\\n\\1|"; CASE_WHY=$why_win
run_case "OpenMP from the tree (<prefix>/Library): libomp.lib by path" windows g++ -shared -fopenmp -o pkg.dll a.o
CASE_TREE=$W_LIB2; CASE_WHY="$why_win; $why_omp"
CASE_DELIBERATE="s|^-I\\($W/$W_LIB2/include\\)\$|-idirafter\\n\\1|
\|^-L$W/$W_LIB2/lib\$|d"
run_case "OpenMP from the tree, no libomp.lib: -lomp" windows gcc -fopenmp -shared -o pkg.dll a.o
win_tc_omp=$W/$W_OMPTC/lib/R/bin/toolchain/openmp
CASE_TREE=$W_OMPTC; CASE_WHY=$why_tc_omp
CASE_DELIBERATE="\$a -L$win_tc_omp/lib
\$a -idirafter
\$a $win_tc_omp/include
\$a $win_tc_omp/lib/libomp.lib"
run_case "the toolchain's openmp/ (libomp.dll beside R.dll): -L, -idirafter, libomp.lib" windows g++ -shared -fopenmp -o pkg.dll a.o
CASE_PATH="$W/flang-win"
run_case "FLIBS: Windows flang's answer, then -lc++" windows gcc -shared -o pkg.dll a.o -L"$W/win/d1" -lflang_rt.runtime -lc++ -lflang_rt.runtime -lc++
# a gfortran on PATH (Rtools'), which neither asks any more
CASE_PATH="$W/flang-win:$W/gf"
run_case "-lgfortran -lquadmath: flang's runtime, not gfortran's" windows gcc -shared -o pkg.dll a.o -lgfortran -lquadmath -lm -lflang_rt.runtime -lc++
CASE_PATH="$W/gf"
run_case "-lgfortran without flang: dropped" windows gcc -shared -o pkg.dll a.o -lgfortran
run_case "-lsynchronization: the API set's import library" windows gcc -shared -o pkg.dll a.o -L"$W/win/d1" -lws2_32 -lsynchronization -lntdll
touchf "$W/win/d3/libapi-ms-win-core-synch-l1-2-0.dll.a"
run_case "-lsynchronization: looked up under the API set's name" windows g++ -shared -o pkg.dll a.o -L"$W/win/d3" -lsynchronization
run_case "-gline-tables-only: no -g0" windows gcc -gline-tables-only -c a.c -o a.o
run_case "-c without -o: <stem>.o, as MinGW gcc (QuickJSR)" windows gcc -O2 -c quickjs/libquickjs.c
run_case "-c without -o, C++ and a backslash path" windows g++ -c 'src\sub\a.cpp' -I/x
run_case "-c with -o: unchanged" windows gcc -c a.c -o b.o
run_case "-c with a joined -o: unchanged" windows gcc -c a.c -ob.o
run_case "-c with two sources: unchanged" windows gcc -c a.c b.c
run_case "-E, -M with -c: unchanged" windows gcc -E -M -c a.c
run_case "--allow-multiple-definition dropped (StanHeaders)" windows g++ -shared -Wl,--allow-multiple-definition -o StanHeaders.dll a.o
# (the cache holds the CFG stub, cfguard.zig, and no mirror)
CASE_ENV=(XDG_CACHE_HOME="$W/cache7"); CASE_PATH="$W/envB/bin"; CASE_STATE='ls -d "$XDG_CACHE_HOME"/r-zig/zig-lib-* 2> /dev/null || echo "no mirror"'
run_case "libc++ beside zig: no mirror on Windows" windows zig-cxx -shared -o pkg.dll a.o
run_case "ar and ranlib passthrough" windows zig-ar rcs libw.a a.o
# Makeconf.win's LTO names (B43): rzig as zig-ar and zig-ranlib
run_case "gcc-ar: zig ar" windows gcc-ar rcs libw.a a.o
run_case "gcc-ranlib: zig ranlib" windows gcc-ranlib libw.a
CASE_RESET='rm -f libgnew.a'; CASE_STATE='od -c libgnew.a | head -2'
run_case "gcc-ar on macOS: zig-ar's seed" macos gcc-ar rcs libgnew.a a.o

# --- the check mode (check.zig): the real binary ----------------------------------
# a group's tools found: one line on stdout, 0; one missing: its group's
# text, 127; a zig whose major.minor is not R's (rzig's own): 1
tc=$W/tree/lib/R/bin/toolchain
real_zig=$(command -v "${ZIG:-zig}" || :)
if [ -n "$real_zig" ]; then
  check "--rzig-check: zig and its version (ZIG_BIN)" \
    bash -c "env -i ZIG_BIN='$real_zig' '$tc/zig-cc' --rzig-check | grep -q '^zig-cc: compilers ok: zig [0-9]'"
  check "--rzig-check: the toolchain's zig/" \
    bash -c "mkdir -p '$W/realtc/lib/R/bin/toolchain/zig' && cp '$RZIG' '$W/realtc/lib/R/bin/toolchain/gcc' && ln -sf '$real_zig' '$W/realtc/lib/R/bin/toolchain/zig/zig' &&
      env -i '$W/realtc/lib/R/bin/toolchain/gcc' --rzig-check | grep -qF 'zig-cc: compilers ok: zig ' "
  check "--rzig-check=fortran: no flang, 127, the compilers group" \
    bash -c "env -i ZIG_BIN='$real_zig' PATH='$W/nothing' '$tc/zig-cc' --rzig-check=fortran 2>&1 >/dev/null | grep -q '^Compiling needs the r-zig compilers for R '; [ \"\${PIPESTATUS[0]}\" = 127 ]"
  check "zig-fc --rzig-check checks flang too" \
    bash -c "cp '$RZIG' '$tc/zig-fc' && env -i ZIG_BIN='$real_zig' PATH='$W/flang' '$tc/zig-fc' --rzig-check | grep -qF '; flang at $W/flang/flang'"
fi
check "--rzig-check: no zig, 127, the compilers group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' --rzig-check 2>&1 | grep -q '^zig-cc: no zig (ZIG_BIN, '; [ \"\${PIPESTATUS[0]}\" = 127 ]"
check "--rzig-check: a zig that does not say its version, 1" \
  bash -c "env -i ZIG_BIN='$STUB' '$tc/zig-cc' --rzig-check 2> /dev/null; [ \$? = 1 ]"
prog "$W/zig-other/zig" '[ "$1" = version ] && echo 0.99.0'
check "--rzig-check: a zig whose major.minor is not R's, 1" \
  bash -c "env -i ZIG_BIN='$W/zig-other/zig' '$tc/zig-cc' --rzig-check 2>&1 > /dev/null | grep -q ' is zig 0.99.0, not R.s zig '; [ \"\${PIPESTATUS[0]}\" = 1 ]"
check "--rzig-check with R_ZIG_NO_PREFLIGHT: no version check, 0" \
  env -i ZIG_BIN="$STUB" R_ZIG_NO_PREFLIGHT=1 "$tc/zig-cc" --rzig-check
check "--rzig-check=build-tools: make on PATH" \
  bash -c "env -i PATH='$(dirname "$(command -v make)")' '$tc/zig-cc' --rzig-check=build-tools | grep -q '^zig-cc: build-tools ok: make at '"
check "--rzig-check=build-tools: no make, 127, the build-tools group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' --rzig-check=build-tools 2>&1 | grep -q '^Building packages needs the r-zig build tools for R '; [ \"\${PIPESTATUS[0]}\" = 127 ]"
check "--rzig-check=other: usage, 2" \
  bash -c "env -i '$tc/zig-cc' --rzig-check=other 2> /dev/null; [ \$? = 2 ]"
check "a compile with no zig: 127, the compilers group" \
  bash -c "env -i PATH='$W/nothing' '$tc/zig-cc' -c a.c 2>&1 | grep -q '^Compiling needs the r-zig compilers for R '; [ \"\${PIPESTATUS[0]}\" = 127 ]"

echo "== $pass identical, $own identical but for rzig's own-environment -L or compiled object, $deliberate deliberate differences, $fail failed"
[ "$fail" = 0 ]
