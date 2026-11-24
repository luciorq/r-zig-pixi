#!/usr/bin/env bash
# M-29 inside ubuntu:24.04 (or 22.04): the standalone tree (/dist: the
# slim, compilers, build-tools and extras archives) with this branch's rzig
# (/rzig/rzig copied over every name in R_HOME/bin/toolchain), against the
# distribution's GDAL, PROJ, GEOS, curl and Magick++.
#   docker run --rm -v <dist>:/dist:ro -v <rzig bin dir>:/rzig:ro \
#     -v <this dir>:/probe:ro -v <out>:/out ubuntu:24.04 bash /probe/m29.sh [pkgs...]
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends \
  libgdal-dev libmagick++-dev libgeos-dev libproj-dev libcurl4-openssl-dev libssl-dev libudunits2-dev \
  pkg-config xz-utils ca-certificates binutils > /dev/null
cd /opt && for a in /dist/R-*-slim-linux-64.tar.gz /dist/R-*-linux-64-compilers.tar.xz /dist/R-*-linux-64-build-tools.tar.gz /dist/R-*-linux-64-extras.tar.gz; do tar -xf "$a"; done
T="$(ls -d /opt/R-*-zig)"; TC="$T/lib/R/bin/toolchain"
for n in rzig zig-cc zig-cxx zig-fc zig-ar zig-ranlib; do cp /rzig/rzig "$TC/$n"; done
export PATH="$T/bin:$TC/usr/bin:$TC/cmake/bin:$PATH"
mkdir -p /w && cd /w
probe() { echo "PROBE $1: $2"; }
cat > g.c << 'C'
#include <stdio.h>
#include <gdal.h>
#include <curl/curl.h>
#include <proj.h>
int main(void) {
  GDALAllRegister();
  PJ_INFO i = proj_info();
  printf("gdal %s, %d drivers, curl %s, proj %s\n", GDALVersionInfo("RELEASE_NAME"), GDALGetDriverCount(), curl_version_info(CURLVERSION_NOW)->version, i.version);
  return GDALGetDriverByName("GTiff") ? 0 : 1;
}
C
flags="$(pkg-config --cflags gdal libcurl proj)"; libs="$(pkg-config --libs gdal libcurl proj)"
echo "== pkg-config cflags: $flags"
for mode in off on; do
  if [ $mode = on ]; then export R_ZIG_SYSTEM_LIBS=1; else unset R_ZIG_SYSTEM_LIBS; fi
  # a configure-style test: compile and link an executable, then run it
  if "$TC/zig-cc" $flags -I/usr/include/x86_64-linux-gnu g.c $libs -o g > g-$mode.log 2>&1 && ./g >> g-$mode.log 2>&1; then
    probe "gdal-exe-$mode" "ok ($(tail -1 g-$mode.log))"
  else
    probe "gdal-exe-$mode" "FAIL: $(grep -m2 -E 'error|undefined' g-$mode.log | tr '\n' ' ')"
  fi
done
export R_ZIG_SYSTEM_LIBS=1
RZIG_TRACE=1 "$TC/zig-cc" $flags -c g.c -o g.o 2>&1 | grep -o -- '-idirafter [^ ]*' | tr '\n' ' '; echo
[ $# -gt 0 ] || set -- magick terra
mkdir -p /w/lib
for p in "$@"; do
  Rscript -e "options(repos = 'https://cloud.r-project.org', Ncpus = 8); install.packages('$p', lib = '/w/lib', dependencies = c('Depends', 'Imports', 'LinkingTo'))" > "inst-$p.log" 2>&1 || true
  if Rscript -e ".libPaths('/w/lib'); library($p); cat('loaded\n')" > "load-$p.log" 2>&1; then
    case $p in
      magick) Rscript -e ".libPaths('/w/lib'); i <- magick::image_blank(10, 10, 'red'); print(magick::image_info(i)\$width); print(magick::magick_config()\$version)" >> "load-$p.log" 2>&1 ;;
      terra) Rscript -e ".libPaths('/w/lib'); r <- terra::rast(nrows=2, ncols=2, vals=1:4); f <- tempfile(fileext='.tif'); terra::writeRaster(r, f); print(terra::global(terra::rast(f), 'sum')); print(terra::gdal())" >> "load-$p.log" 2>&1 ;;
      sf) Rscript -e ".libPaths('/w/lib'); print(sf::sf_extSoftVersion()); print(round(sf::st_area(sf::st_buffer(sf::st_point(c(0,0)), 1)), 2))" >> "load-$p.log" 2>&1 ;;
    esac
    probe "$p" "ok: $(tail -3 "load-$p.log" | tr '\n' ' ')"
  else
    probe "$p" "FAIL: $(grep -m3 -E 'error|ERROR' "inst-$p.log" | tr '\n' ' ')"
  fi
  echo "== needs of $p: $(readelf -d /w/lib/$p/libs/$p.so 2>/dev/null | grep NEEDED | sed 's/.*\[//;s/\]//' | tr '\n' ' ')"
done
cp /w/*.log /out/ 2>/dev/null || true
