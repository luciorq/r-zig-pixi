#!/bin/sh
# L4 prototype (b13-design PLAN.md): busybox-w32 for Windows built with
# zig through busybox's own Kbuild (a build.zig port is sized in PLAN.md,
# not written). Runs on a linux host with GNU make, bzip2 and perl on PATH
# (the host C compiler is zig cc too). On a host without them:
#   pixi exec -s make -s perl -s bzip2 -- sh build-busybox.sh ...
#
#   build-busybox.sh <zig> <busybox-w32 tarball> <x86_64|aarch64> <outdir>
#
# Config: upstream's mingw64u (x86_64) or mingw64a (aarch64) defconfig,
# compilers renamed to clang (upstream's llvm-mingw convention), no
# libgcc, and the make/pdpmake applets off, so a bare `make` in sh is
# GNU make and never pdpmake (which cannot read R's Makeconf).
set -eu
ZIG=$1 TGZ=$2 A=$3 OUT=$4
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
W=$OUT/work; rm -rf "$W"; mkdir -p "$W/wrap"
tar -xzf "$TGZ" -C "$W"
SRC=$W/busybox-w32
VER=$(cat "$SRC/.frp_describe")

# The cross tools busybox's Makefile asks for, as zig commands. zig's COFF
# driver rejects -Map and --verbose (scripts/trylink adds both). On the
# link line (no -c) the no-unwind-tables flags are dropped too: zig 0.17.1
# compiles mingw's crtexe.c with them on aarch64, which then fails
# (".seh_ directive must appear within an active frame"; PLAN.md L4-F6).
T=$A-w64-mingw32
cat > "$W/wrap/$T-clang" <<EOF
#!/bin/sh
link=1; for a in "\$@"; do [ "\$a" = -c ] && link=0; done
for a in "\$@"; do
  shift
  case "\$a" in
    -Wl,-Map,*|-Wl,--verbose) continue;;
    -fno-unwind-tables|-fno-asynchronous-unwind-tables) [ \$link = 1 ] && continue;;
  esac
  set -- "\$@" "\$a"
done
exec "$ZIG" cc -target $A-windows-gnu "\$@"
EOF
printf '#!/bin/sh\nexec "%s" ar "$@"\n' "$ZIG" > "$W/wrap/$T-ar"
printf '#!/bin/sh\nexec "%s" ranlib "$@"\n' "$ZIG" > "$W/wrap/$T-ranlib"
printf '#!/bin/sh\nexec "%s" cc "$@"\n' "$ZIG" > "$W/wrap/clang"
case $A in x86_64) RCT=X64;; aarch64) RCT=ARM64;; esac
cat > "$W/wrap/$T-windres" <<EOF
#!/bin/sh
# GNU windres "[-Dx] [--include-dir=d] in.rc out.o" as zig rc writing COFF
args=""; in=""; out=""
for a in "\$@"; do
  case "\$a" in
    -D*) args="\$args /d \${a#-D}";;
    --include-dir=*) args="\$args /i \${a#--include-dir=}";;
    *) if [ -z "\$in" ]; then in="\$a"; else out="\$a"; fi;;
  esac
done
exec "$ZIG" rc /:target $RCT /:output-format coff /:auto-includes gnu \$args /fo "\$out" -- "\$in"
EOF
chmod +x "$W"/wrap/*
export PATH="$W/wrap:$PATH"
export ZIG_GLOBAL_CACHE_DIR=$W/zig-global ZIG_LOCAL_CACHE_DIR=$W/zig-local TZ=UTC0
export SOURCE_DATE_EPOCH=$(stat -c %Y "$SRC/Makefile")

cd "$SRC"
case $A in x86_64) CFG=mingw64u_defconfig;; aarch64) CFG=mingw64a_defconfig;; esac
make HOSTCC=clang "$CFG" > "$OUT/defconfig-$A.log" 2>&1
sed -i -e 's/^CONFIG_HOST_COMPILER=.*/CONFIG_HOST_COMPILER="clang"/' \
       -e 's/^CONFIG_CROSS_COMPILER=.*/CONFIG_CROSS_COMPILER="clang"/' \
       -e 's/^CONFIG_STATIC_LIBGCC=y/# CONFIG_STATIC_LIBGCC is not set/' \
       -e 's/^CONFIG_MAKE=y/# CONFIG_MAKE is not set/' \
       -e 's/^CONFIG_PDPMAKE=y/# CONFIG_PDPMAKE is not set/' .config
make HOSTCC=clang oldconfig < /dev/null >> "$OUT/defconfig-$A.log" 2>&1
cp .config "$OUT/busybox-$A.config"
t0=$(date +%s)
make -j"$(nproc)" HOSTCC=clang SKIP_STRIP=y EXTRAVERSION="-$VER" MINGW_VER="zig $("$ZIG" version)" > "$OUT/build-$A.log" 2>&1
echo "busybox $VER $A: $(( $(date +%s) - t0 )) s" | tee "$OUT/time-$A.txt"
cp busybox.exe "$OUT/busybox-$A.exe"
