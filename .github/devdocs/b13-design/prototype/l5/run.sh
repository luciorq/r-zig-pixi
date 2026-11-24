#!/bin/sh
# L5 prototype (b13-design PLAN.md): what ran on delta, in order.
#   run.sh <scratch dir>     (pixi on PATH; network to prefix.dev and CRAN)
set -eu
P=$(cd "$(dirname "$0")" && pwd)
S=$1; mkdir -p "$S"; cp "$P/pixi.toml" "$S/"; cd "$S"
export PIXI_CACHE_DIR=$S/cache ZIG_GLOBAL_CACHE_DIR=$S/zcache RZIG_BUILD=12 MAKEFLAGS=-j8
pixi install --all
T=Rcpp,jsonlite,cli,data.table,xml2

# 1. sources -> binaries -> bin/linux/<arch>-rzig<abi>/contrib/<x.y> + PACKAGES
pixi run -e build Rscript "$P/build-repo.R" "$S/work" "$T"

# 2. install from file:// into fresh libraries of an R without compilers
for e in consumer consumer-libs; do
  for m in contriburl repos; do
    pixi run -e $e Rscript "$P/install-test.R" "$S/work" "$T" $m "$e-$m"
  done
done

# 3. another machine: the build env gone. With the build env's absolute
#    RUNPATH the packages' libraries resolve from the host (/usr/lib);
#    with no RUNPATH they resolve through R's own DT_RPATH (the env's lib).
rm -rf work/lib-norpath; cp -a work/lib-consumer-libs-repos work/lib-norpath
for f in work/lib-norpath/*/libs/*.so; do pixi exec -s patchelf patchelf --remove-rpath "$f"; done
mv .pixi/envs/build build.away
for l in lib-consumer-libs-repos lib-norpath; do
  .pixi/envs/consumer-libs/bin/Rscript -e ".libPaths(c('$S/work/$l', .libPaths()))
    x <- xml2::xml_text(xml2::read_xml('<a>hi</a>'))
    cat('$l', x, unique(sub('.* ', '', grep('libxml2', readLines('/proc/self/maps'), value = TRUE))), '\n')"
done
mv build.away .pixi/envs/build
