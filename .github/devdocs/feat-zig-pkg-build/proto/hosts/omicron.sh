#!/bin/bash
# M1 step 4 on omicron (macOS arm64): tier-1 cli + quadprog, tier-2 zighello. Scratch: ~/rz-pkgbuild
set -u
W=$HOME/rz-pkgbuild; R=$HOME/r-zig-pixi/dist/R-4.6.1-slim-zig/lib/R; ENV=$HOME/r-zig-pixi/.pixi/envs/default
ZIG=$ENV/bin/zig
export ZIG_BIN=$ZIG R_ZIG_EXTRA_ENV=$ENV RZIG_TRACE=1 PATH=$ENV/bin:$PATH  # flang for zig-fc
cd $W || exit 1
rm -rf src lib-make lib-zig lib-t2 out logs plans zcache zighello-nosrc; mkdir -p logs; cp -R root-t2 root-t2.bak 2>/dev/null
mkdir -p src lib-make lib-zig lib-t2 out logs plans
tar xzf cli.tar.gz -C src; tar xzf quadprog.tar.gz -C src
echo "== host"; sw_vers | tr '\n' ' '; echo; uname -m; $ZIG version; make --version | head -1
echo "== make reference (R CMD INSTALL)"
for p in cli quadprog; do
  s=$(date +%s.%N); $R/bin/R CMD INSTALL -l $W/lib-make src/$p > logs/make-$p.log 2>&1; rc=$?; e=$(date +%s.%N)
  printf 'make %s rc=%s %.2fs\n' $p $rc $(echo "$e - $s" | bc)
done
echo "== plans (mkplan.sh, make 3.81)"
for p in cli quadprog; do bash proto/mkplan.sh $R src/$p/src $p $W/plans/$p.zon 2>&1 | tail -1; done
# zighello: flags only, plus the tier-2 fields
bash proto/mkplan.sh $R proto/zighello/src zighello $W/plans/zighello.zon 2>&1 | tail -1
sed '$d' $W/plans/zighello.zon > plans/z.tmp && { cat plans/z.tmp; echo "    .target = \"$(uname -m | sed 's/arm64/aarch64/')-native.13.0\","; echo "    .r_include = \"$R/include\","; echo "}"; } > $W/plans/zighello.zon && rm plans/z.tmp
grep -E '\.(output|link_driver|target)' plans/*.zon
echo "== zig build tier 1 (cold cache: runner compile included)"
for p in cli quadprog; do
  s=$(date +%s.%N); $ZIG build --build-file proto/rpkg/build_t1.zig --cache-dir $W/zcache --prefix out/$p -Dplan=$W/plans/$p.zon -j4 --summary all > logs/zig-$p.log 2>&1; rc=$?; e=$(date +%s.%N)
  printf 'zig %s rc=%s %.2fs\n' $p $rc $(echo "$e - $s" | bc); ls -la out/$p/libs/ 2>&1 | tail -n +2
done
echo "== zig build tier 1 warm (no change)"
s=$(date +%s.%N); $ZIG build --build-file proto/rpkg/build_t1.zig --cache-dir $W/zcache --prefix out/cli -Dplan=plans/cli.zon -j4 > logs/zig-cli-warm.log 2>&1; e=$(date +%s.%N); printf 'zig cli warm rc=%s %.2fs\n' $? $(echo "$e - $s" | bc)
echo "== exports: make vs zig (nm -gU, sorted)"
for p in cli quadprog; do
  nm -gU lib-make/$p/libs/$p.so | awk '{print $3}' | sort > logs/nm-make-$p; nm -gU out/$p/libs/$p.so | awk '{print $3}' | sort > logs/nm-zig-$p
  if cmp -s logs/nm-make-$p logs/nm-zig-$p; then echo "$p: exports identical ($(wc -l < logs/nm-make-$p) symbols)"; else echo "$p: exports DIFFER"; diff logs/nm-make-$p logs/nm-zig-$p | head -20; fi
done
echo "== rzig argv: make vs zig (sorted, basenames)"
norm() { grep -E '^zig-(cc|cxx|fc): ' "$1" | grep -v -- '--version' | sed -E 's#[^ ]*/([^/ ]+)#\1#g' | sort; }
for p in cli quadprog; do
  norm logs/make-$p.log > logs/argv-make-$p; norm logs/zig-$p.log > logs/argv-zig-$p
  if cmp -s logs/argv-make-$p logs/argv-zig-$p; then echo "$p: argv identical ($(wc -l < logs/argv-make-$p) lines)"; else echo "$p: argv DIFFER"; diff logs/argv-make-$p logs/argv-zig-$p | head -20; fi
done
echo "== Mach-O: LC_BUILD_VERSION minos/sdk, make vs zig"
for f in lib-make/cli/libs/cli.so out/cli/libs/cli.so lib-make/quadprog/libs/quadprog.so out/quadprog/libs/quadprog.so; do
  echo "$f: $(otool -l $f | awk '/LC_BUILD_VERSION/{f=1} f&&/minos|sdk/{printf "%s %s ", $1, $2} /LC_BUILD_VERSION/&&c++{} END{}' ) | arch: $(lipo -archs $f) | deps: $(otool -L $f | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
done
echo "== smoke: lib-make vs lib-zig"
cp -R lib-make/. lib-zig/; for p in cli quadprog; do cp out/$p/libs/$p.so lib-zig/$p/libs/$p.so; done
cat > smoke-mac.R <<'R'
lib <- commandArgs(TRUE)[1]; .libPaths(c(lib, .libPaths()))
chk <- function(name, expr) { v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e))); cat(sprintf("%-10s %s\n", name, paste(format(v), collapse = " "))) }
library(cli); chk("cli", nchar(cli::rule()) > 10); chk("cli-md5", cli::hash_md5("abc"))
library(quadprog); chk("quadprog", quadprog::solve.QP(diag(2), c(1, 1), diag(2), c(0, 0))$solution)
for (p in c("cli", "quadprog")) { chk(paste0("dll-", p), basename(getLoadedDLLs()[[p]][["path"]])); unloadNamespace(p) }
cat("unloaded all; exiting\n")
R
for l in lib-make lib-zig; do echo "-- $l"; $R/bin/Rscript smoke-mac.R $W/$l 2>&1; echo "rc=$?"; done
echo "== tier 2: zighello"
s=$(date +%s.%N); $ZIG build --build-file $W/root-t2/build.zig --cache-dir $W/zcache --prefix out/zighello -Dplan=$W/plans/zighello.zon --summary all > logs/zig-zighello.log 2>&1; rc=$?; e=$(date +%s.%N)
printf 'zig zighello (first: translate-c tool) rc=%s %.2fs\n' $rc $(echo "$e - $s" | bc); [ $rc = 0 ] || tail -30 logs/zig-zighello.log
s=$(date +%s.%N); touch proto/zighello/src/hello.zig; $ZIG build --build-file $W/root-t2/build.zig --cache-dir $W/zcache --prefix out/zighello -Dplan=$W/plans/zighello.zon > logs/zig-zighello2.log 2>&1; e=$(date +%s.%N); printf 'zig zighello again rc=%s %.2fs\n' $? $(echo "$e - $s" | bc)
ls -la out/zighello/libs/ | tail -n +2
f=out/zighello/libs/zighello.so; echo "$f: $(otool -l $f | awk '/LC_BUILD_VERSION/{f=1} f&&/minos|sdk/{printf "%s %s ", $1, $2}') | arch: $(lipo -archs $f) | deps: $(otool -L $f | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"; nm -gU $f | awk '{print $3}' | tr '\n' ' '; echo
cp -R proto/zighello zighello-nosrc && rm -rf zighello-nosrc/src
$R/bin/R CMD INSTALL --no-test-load -l $W/lib-t2 zighello-nosrc > logs/install-zighello.log 2>&1; echo "install zighello (R only) rc=$?"
mkdir -p lib-t2/zighello/libs && cp $f lib-t2/zighello/libs/
$R/bin/Rscript -e '.libPaths(c(commandArgs(TRUE)[1], .libPaths())); library(zighello); print(hello(21L)); print(getDLLRegisteredRoutines("zighello")$.Call); unloadNamespace("zighello"); cat("ok\n")' $W/lib-t2 2>&1; echo "zighello rc=$?"
echo "== cache size"; du -sh zcache | cut -f1
echo "EXIT=done"
