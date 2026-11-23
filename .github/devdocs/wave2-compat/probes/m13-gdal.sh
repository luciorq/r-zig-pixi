#!/usr/bin/env bash
# M-13, the ABI half, inside ubuntu:24.04 (run.sh-style mounts: /probe,
# /dist): an R SHLIB that calls the C++ API of the distro's GDAL
# (CPLString, a std::string, returned by value from libgdal, and a C++
# exception thrown in our code), compiled by the standalone tree's rzig
# with the system's glibc include roots after zig's (-idirafter), not -I.
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends libgdal-dev libcurl4-openssl-dev xz-utils ca-certificates > /dev/null
cd /opt && for a in /dist/R-*-slim-linux-64.tar.gz /dist/R-*-linux-64-compilers.tar.xz /dist/R-*-linux-64-build-tools.tar.gz; do tar -xf "$a"; done
T="$(ls -d /opt/R-*-zig)"; mkdir -p /w && cd /w
echo "== libcurl.pc cflags: $(pkg-config --cflags libcurl 2>/dev/null || grep -h '^Cflags' /usr/lib/x86_64-linux-gnu/pkgconfig/libcurl.pc)"
printf '#include <curl/curl.h>\nint v(void){ return (int)CURLE_OK; }\n' > c.c
echo "== -I/usr/include/x86_64-linux-gnu (what libcurl.pc gives):"
"$T/lib/R/bin/toolchain/zig-cc" -I/usr/include/x86_64-linux-gnu -c c.c -o c.o 2>&1 | grep -m2 error || echo "   compiles"
echo "== -idirafter /usr/include/x86_64-linux-gnu:"
"$T/lib/R/bin/toolchain/zig-cc" -idirafter /usr/include/x86_64-linux-gnu -c c.c -o c.o 2>&1 | grep -m2 error || echo "   compiles"
cat > g.cpp << 'EOF'
#include <R.h>
#include <Rinternals.h>
#include <stdexcept>
#include <string>
#include <cpl_string.h>
#include <gdal_priv.h>
extern "C" SEXP g(void) {
  GDALAllRegister();
  CPLString base = CPLGetBasename("/a/b/raster.tif");          // std::string from libgdal
  std::string drv = GetGDALDriverManager()->GetDriverByName("GTiff")->GetDescription();
  try { throw std::runtime_error(base + "+" + drv); }
  catch (const std::exception& e) { return Rf_mkString(e.what()); }
}
EOF
cat > Makevars << 'EOF'
PKG_CPPFLAGS = -idirafter /usr/include/gdal -idirafter /usr/include -idirafter /usr/include/x86_64-linux-gnu
PKG_LIBS = -L/usr/lib/x86_64-linux-gnu -lgdal
EOF
R_MAKEVARS_USER=/w/Makevars "$T/bin/R" CMD SHLIB g.cpp 2>&1 | tail -n 4
echo "== needs: $(readelf -d g.so 2>/dev/null | grep NEEDED | sed 's/.*\[//;s/\]//' | tr '\n' ' ')"
"$T/bin/Rscript" -e 'dyn.load("/w/g.so"); print(.Call("g")); m <- readLines("/proc/self/maps"); print(unique(sub(".* ", "", grep("libstdc|libgdal", m, value = TRUE))))' 2>&1
echo "EXIT=$?"
