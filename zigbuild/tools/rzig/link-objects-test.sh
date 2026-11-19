#!/usr/bin/env bash
# Windows links of code compiled with Control Flow Guard (clang
# -mguard=cf), cross-built here for x86_64 and aarch64 (feat-winarm-gaps).
# It tests zig and rzig's link object: `zig build object` installs the
# object rzig adds to a Windows link (build.zig's linkObject), and the
# links run `$ZIG cc` directly. It does not run rzig, so it does not test
# that rzig picks the object (compiler.zig's unit tests and
# parity-test.sh do that).
#
# Each arch must link with its object: x86_64 with cfguard.o (zig's MinGW
# lacks __guard_dispatch_icall_dummy, cfguard.zig), aarch64 with
# clear_cache.o. Then without it. aarch64 must still link: clang's ARM64
# CFG calls only __guard_check_icall_fptr, which zig's libmingw32 defines
# there. Such a link works but checks nothing, as a MinGW image has no
# load config. x86_64 should fail. If it links, zig's MinGW gained
# guard_dispatch.S and cfguard.o can go: a warning, not a failure, so a
# better zig does not stop CI. Also links an aarch64 DLL that calls
# __builtin___clear_cache with clear_cache.o (finding 36).
#
# zig's cache is the one test.sh's `zig build test` uses, so the build
# runner is compiled once; only the outputs go in a temporary directory.
# Run from test.sh on linux: ZIG=<zig> bash link-objects-test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ZIG=${ZIG:-zig}
T=$(mktemp -d "${TMPDIR:-/tmp}/rzig-link-objects.XXXXXX")
trap 'rm -rf "$T"' EXIT
start=$SECONDS

cat > "$T/cfg.c" << 'X'
typedef int (*fn)(int);
static int twice(int x) { return 2 * x; }
static int thrice(int x) { return 3 * x; }
int apply(int which, int x) { volatile fn f = which ? twice : thrice; return f(x); }
X
cat > "$T/flush.c" << 'X'
void flush(char *p, int n) { __builtin___clear_cache(p, p + n); }
X

fail=0
for arch in x86_64 aarch64; do
  t=$arch-windows-gnu
  "$ZIG" build object --build-file "$here/build.zig" -Dtarget=$t --prefix "$T/$arch"
  case $arch in x86_64) o=cfguard.o ;; aarch64) o=clear_cache.o ;; esac
  "$ZIG" cc -target $t -mguard=cf -O2 -c "$T/cfg.c" -o "$T/cfg-$arch.o"
  if "$ZIG" cc -target $t -shared -o "$T/cfg-$arch.dll" "$T/cfg-$arch.o" "$T/$arch/bin/$o" 2> "$T/cfg-$arch.log"; then
    echo "ok: $arch -mguard=cf DLL links with $o"
  else
    cat "$T/cfg-$arch.log" >&2
    echo "FAIL: $arch -mguard=cf DLL does not link with $o" >&2
    fail=1
  fi
  if "$ZIG" cc -target $t -shared -o "$T/no-$arch.dll" "$T/cfg-$arch.o" 2> "$T/no-$arch.log"; then
    if [ $arch = aarch64 ]; then
      echo "ok: aarch64 -mguard=cf DLL links with no CFG stub (libmingw32's __guard_check_icall_fptr)"
    else
      echo "WARNING: x86_64 -mguard=cf DLL links without cfguard.o: zig's MinGW now has guard_dispatch.S, so cfguard.o can go (cfguard.zig)" >&2
    fi
  elif [ $arch = x86_64 ]; then
    echo "ok: x86_64 -mguard=cf DLL still needs cfguard.o"
  else
    cat "$T/no-$arch.log" >&2
    echo "FAIL: aarch64 -mguard=cf DLL does not link without a stub" >&2
    fail=1
  fi
done

"$ZIG" cc -target aarch64-windows-gnu -O2 -c "$T/flush.c" -o "$T/flush.o"
if "$ZIG" cc -target aarch64-windows-gnu -shared -o "$T/flush.dll" "$T/flush.o" "$T/aarch64/bin/clear_cache.o" 2> "$T/flush.log"; then
  echo "ok: aarch64 DLL calling __clear_cache links with clear_cache.o"
else
  cat "$T/flush.log" >&2
  echo "FAIL: aarch64 DLL calling __clear_cache does not link with clear_cache.o" >&2
  fail=1
fi

echo "link-objects-test: $((SECONDS - start)) s"
exit $fail
