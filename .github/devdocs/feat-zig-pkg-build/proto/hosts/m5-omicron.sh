#!/bin/bash
# M5 on omicron (macOS arm64): R CMD INSTALL through the rzig build hook, on the branch's dist. Scratch: ~/rz-m5
set -u
W=$HOME/rz-m5; D=$HOME/r-zig-pixi/dist/R-4.6.1-slim-zig; R=$D/lib/R; ENV=$HOME/r-zig-pixi/.pixi/envs/default
PROTO=$HOME/r-zig-pixi/.github/devdocs/feat-zig-pkg-build/proto
export PATH=$ENV/bin:/usr/bin:/bin R_MAKEVARS_USER=/nonexistent R_ZIG_EXTRA_ENV=$ENV
cd $W || exit 1
rm -rf lib-zig lib-make lib-t2 lib-nomake logs neg3 zighello nomake-bin; mkdir -p lib-zig lib-make lib-t2 lib-nomake logs
echo "== host"; sw_vers | tr '\n' ' '; echo; uname -m; zig version; $R/bin/R --version | head -1; ls -la $R/bin/toolchain/rzig | awk '{print $6, $7, $8}'
echo "== tree"; ls $R/bin/toolchain/ | tr '\n' ' '; echo; ls $R/share/zig/rpkg/ | tr '\n' ' '; echo
echo "== spawnWait"; $R/bin/Rscript -e 'print(.Internal(spawnWait(c("true"), 0L))); print(.Internal(spawnWait(c("false"), 0L))); print(.Internal(spawnWait(c("no-such-program-xyz"), 0L))); print(.Internal(spawnWait(c("sleep", "5"), 1L)))' 2>&1
norm() { grep -E '^(zig-cc|zig-cxx|zig-fc): ' "$1" | grep -v -- '--version' | sed -E 's#[^ ]*/([^/ ]+)#\1#g' | sort; }
minos() { otool -l "$1" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}'; }
for p in cli digest quadprog Rcpp; do
  t=pkgs/$p.tar.gz
  s=$(date +%s.%N); RZIG_TRACE=1 $R/bin/R CMD INSTALL -l $W/lib-zig $t > logs/$p-zig.log 2>&1; rc=$?
  printf '%-9s zig  rc=%s %5.1fs  tier:%s  compilers:%s  make-lines:%s\n' $p $rc $(echo "$(date +%s.%N) - $s" | bc) "$(grep -o 'tier [12]' logs/$p-zig.log | head -1)" "$(grep -c '^using .* compiler' logs/$p-zig.log)" "$(grep -c 'make\[\|^make ' logs/$p-zig.log)"
  s=$(date +%s.%N); RZIG_TRACE=1 R_ZIG_PKG_BUILDER=make $R/bin/R CMD INSTALL -l $W/lib-make $t > logs/$p-make.log 2>&1; rc=$?
  printf '%-9s make rc=%s %5.1fs\n' $p $rc $(echo "$(date +%s.%N) - $s" | bc)
  z=lib-zig/$p/libs/$p.so; m=lib-make/$p/libs/$p.so
  [ -f $z ] && [ -f $m ] || { echo "          MISSING library: $(ls $z $m 2>&1 | grep -i 'no such')"; tail -5 logs/$p-zig.log; continue; }
  if cmp -s <(nm -gU $z | awk '{print $3}' | sort) <(nm -gU $m | awk '{print $3}' | sort); then echo "          exports identical ($(nm -gU $z | wc -l | tr -d ' '))"; else echo "          EXPORTS DIFFER"; diff <(nm -gU $z | awk '{print $3}' | sort) <(nm -gU $m | awk '{print $3}' | sort) | head; fi
  norm logs/$p-zig.log > logs/argv-zig-$p; norm logs/$p-make.log > logs/argv-make-$p
  if cmp -s logs/argv-zig-$p logs/argv-make-$p; then echo "          rzig argv identical ($(wc -l < logs/argv-zig-$p | tr -d ' ') lines)"; else echo "          RZIG ARGV DIFFER"; diff logs/argv-zig-$p logs/argv-make-$p | head -8; fi
  echo "          install name zig: $(otool -D $z | tail -1) | make: $(otool -D $m | tail -1)"
  echo "          minos zig: $(minos $z) make: $(minos $m) | deps zig: $(otool -L $z | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
done
echo "== smoke zig"; $R/bin/Rscript $PROTO/smoke.R $W/lib-zig 2>&1 | grep -v '^$'
echo "== smoke make"; $R/bin/Rscript $PROTO/smoke.R $W/lib-make 2>&1 | grep -v '^$'
echo "== tier 2: zighello from its directory"; cp -R $PROTO/zighello zighello
s=$(date +%s.%N); RZIG_TRACE=1 $R/bin/R CMD INSTALL -l $W/lib-t2 zighello > logs/zighello.log 2>&1; printf 'rc=%s %5.1fs\n' $? $(echo "$(date +%s.%N) - $s" | bc); grep -E 'tier|using zig|^\*\* testing' logs/zighello.log | head -5; echo "src after: $(ls -a zighello/src | tr '\n' ' ')"
s=$(date +%s.%N); RZIG_TRACE=1 $R/bin/R CMD INSTALL -l $W/lib-t2 zighello > logs/zighello2.log 2>&1; printf 'again rc=%s %5.1fs\n' $? $(echo "$(date +%s.%N) - $s" | bc)
$R/bin/Rscript -e '.libPaths(c("'$W/lib-t2'", .libPaths())); library(zighello); print(hello(21L)); print(getDLLRegisteredRoutines("zighello")$.Call); unloadNamespace("zighello"); cat("ok\n")' 2>&1 | tail -4
f=lib-t2/zighello/libs/zighello.so; echo "install name: $(otool -D $f | tail -1) | minos $(minos $f) | exports: $(nm -gU $f | awk '{print $3}' | tr '\n' ' ')| deps: $(otool -L $f | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
echo "== tier 3 (configure) falls through to make"; mkdir -p neg3; tar xzf pkgs/cli.tar.gz -C neg3; printf '#!/bin/sh\nexit 0\n' > neg3/cli/configure; chmod +x neg3/cli/configure
RZIG_TRACE=1 $R/bin/R CMD INSTALL --no-test-load -l $W/lib-make neg3/cli > logs/neg3.log 2>&1; echo "rc=$?"; grep -E 'needs make|rzig build:' logs/neg3.log | head -3; echo "make lines: $(grep -c 'make\[\|^make ' logs/neg3.log), compiler lines: $(grep -c '^using C compiler' logs/neg3.log)"
echo "== R_ZIG_PKG_BUILDER=zig on a tier-3 package"; R_ZIG_PKG_BUILDER=zig $R/bin/R CMD INSTALL --no-test-load -l $W/lib-make neg3/cli 2>&1 | grep -E 'ERROR|needs make' | head -3
echo "== no make on PATH"; T=$W/nomake-bin; mkdir -p $T; for x in sh zig flang flang-new; do p=$(command -v $x 2>/dev/null) && ln -s $p $T/$x; done; ls $T | tr '\n' ' '; echo
env -i HOME=$HOME PATH=$T R_MAKEVARS_USER=/nonexistent R_ZIG_EXTRA_ENV=$ENV $R/bin/R CMD INSTALL --no-test-load -l $W/lib-nomake pkgs/quadprog.tar.gz > logs/nomake.log 2>&1; echo "quadprog no-make rc=$?"; grep -E 'ERROR|not found|tier' logs/nomake.log | head -5
env -i HOME=$HOME PATH=$T R_MAKEVARS_USER=/nonexistent R_ZIG_EXTRA_ENV=$ENV $R/bin/R CMD INSTALL -l $W/lib-nomake pkgs/cli.tar.gz > logs/nomake-cli.log 2>&1; echo "cli no-make (with test load) rc=$?"; grep -E 'ERROR|not found' logs/nomake-cli.log | head -3
echo "== cache"; du -sh ${XDG_CACHE_HOME:-$HOME/.cache}/r-zig 2>/dev/null; du -sh ~/Library/Caches/r-zig 2>/dev/null
echo "EXIT=done"
