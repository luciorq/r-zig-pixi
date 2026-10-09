#!/usr/bin/env bash
# PROTOTYPE ONLY. Writes plan.zon for a tier-1 package from the dev tree's
# Makeconf, using GNU make's $(file) function to dump the exact strings
# R's make-based install would use (what rzig's own evaluator must
# reproduce without make). usage: mkplan.sh R_HOME pkgsrc/src name out.zon [linkingto include dirs...]
set -euo pipefail
R_HOME=$1; SRC=$(cd "$2" && pwd); NAME=$3; OUT=$(cd "$(dirname "$4")" && pwd)/$(basename "$4"); shift 4
export R_HOME R_INCLUDE_DIR="$R_HOME/include" R_SHARE_DIR="$R_HOME/share" R_DOC_DIR="$R_HOME/doc" R_ARCH=""
TC="$R_HOME/bin/toolchain"
T=$(mktemp -d)
CLINK=""; for d in "$@"; do CLINK="$CLINK -I'$d'"; done
# languages present (install.R 2708-2733)
cd "$SRC"
srcs=$(ls | grep -E '\.(c|cc|cpp|f|f90|f95|m|mm|M)$' || true)
with_c=0; with_cxx=0; with_f=0; with_f9x=0
for s in $srcs; do case $s in *.c) with_c=1;; *.cc|*.cpp) with_cxx=1;; *.f) with_f=1;; *.f90|*.f95) with_f9x=1;; esac; done
MV=""; [ -f Makevars ] && MV="include $SRC/Makevars"
# command-line overrides .shlib_internal passes (install.R 2844-2918)
over=""
if [ $with_cxx = 1 ]; then over="$over SHLIB_LDFLAGS=\$(SHLIB_CXXLDFLAGS) SHLIB_LD=\$(SHLIB_CXXLD)"; fi
libadd='$(SHLIB_LIBADD)'
if [ $with_f = 1 ] || [ $with_f9x = 1 ]; then libadd="$libadd \$(FLIBS) \$(FCLIBS_XTRA)"; fi
cat > $T/Makefile <<MK
$MV
include $R_HOME/etc/Makeconf
-include $R_HOME/etc/Makevars.site
include $R_HOME/share/make/shlib.mk
SHLIB_LIBADD := $libadd
# printf, not GNU make 4's \$(file): macOS ships make 3.81
dump:
	@printf '%s\n' '\$(CC) \$(ALL_CPPFLAGS) \$(ALL_CFLAGS)' > $T/cc.txt
	@printf '%s\n' '\$(CXX) \$(ALL_CPPFLAGS) \$(ALL_CXXFLAGS)' > $T/cxx.txt
	@printf '%s\n' '\$(FC) \$(ALL_FFLAGS)' > $T/fc.txt
	@printf '%s\n' '\$(FC) \$(ALL_FCFLAGS)' > $T/f9x.txt
	@printf '%s\n' '\$(SHLIB_LINK)' > $T/link.txt
	@printf '%s\n' '\$(ALL_LIBS)' > $T/libs.txt
	@printf '%s\n' '\$(OBJECTS)' > $T/objects.txt
	@printf '%s\n' '\$(SHLIB_EXT)' > $T/ext.txt
MK
objects_default=$(for s in $srcs; do printf '%s ' "${s%.*}.o"; done)
CLINK_CPPFLAGS="$CLINK" make -s -C "$SRC" -f $T/Makefile dump OBJECTS="$objects_default" $over >/dev/null
ext=$(cat $T/ext.txt)
# tokens: shell word splitting with quotes, no expansion (xargs rules)
toks() { xargs printf '%s\n' < "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/        "&",/'; }
# the driver is token 1 of each line; strip it (the root names the tool)
drv() { xargs printf '%s\n' < "$1" | head -1; }
tail_toks() { xargs printf '%s\n' < "$1" | tail -n +2 | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/        "&",/'; }
link_driver=$(basename "$(drv $T/link.txt)")
{
  echo ".{"
  echo "    .name = \"$NAME\","
  echo "    .srcdir = \"$SRC\","
  echo "    .output = \"$NAME$ext\","
  echo "    .toolchain = \"$TC\","
  echo "    .link_driver = \"$link_driver\","
  echo "    .sources = .{"
  for o in $(cat $T/objects.txt); do
    base=${o%.o}; src=""; lang=""
    for e in c cc cpp f f90 f95; do if [ -f "$base.$e" ]; then src="$base.$e"; case $e in c) lang=c;; cc|cpp) lang=cxx;; f) lang=f;; f90|f95) lang=f9x;; esac; break; fi; done
    [ -n "$src" ] || { echo "no source for $o" >&2; exit 1; }
    echo "        .{ .lang = \"$lang\", .path = \"$src\", .obj = \"$o\" },"
  done
  echo "    },"
  echo "    .cc = .{"; tail_toks $T/cc.txt; echo "    },"
  echo "    .cxx = .{"; tail_toks $T/cxx.txt; echo "    },"
  echo "    .fc = .{"; tail_toks $T/fc.txt; echo "    },"
  echo "    .f9x = .{"; tail_toks $T/f9x.txt; echo "    },"
  echo "    .link = .{"; tail_toks $T/link.txt; echo "    },"
  echo "    .libs = .{"; toks $T/libs.txt; echo "    },"
  echo "    .env = .{ \"R_PACKAGE_NAME=$NAME\", \"CLINK_CPPFLAGS=$CLINK\" },"
  echo "}"
} > "$OUT"
rm -rf $T
echo "wrote $OUT ($(grep -c '.lang' "$OUT") sources, driver $link_driver)"
