#!/usr/bin/env bash
# Extract the packaged standalone bundle to a fresh location and run it
# with the pixi/conda env off PATH — the same adversarial check done
# manually on omicron/kappa for every relocation fix this project has
# shipped, automated so CI catches a regression instead of relying on a
# human to re-run it. Windows binaries derive R_HOME natively (no PATH
# tricks needed there); unix binaries get a scrubbed PATH
# to prove they need nothing from the environment that built them.
#
# The checks here are the ones whose point is the relocated,
# environment-free tree, or that need what package-standalone.sh adds
# (feat-no-host-paths PLAN.md, F1.6):
#   - the archive exists and extracts;
#   - R runs from the new place (unix: env -i), with the variant's
#     capabilities: the vendored libraries load from there;
#   - TLS trust with the shipped CA bundle and nothing from the build env;
#   - packages compiled with the relocated tree build and load under
#     env -i: C++, Fortran, USE_FC_TO_LINK, $(FLIBS) without flang,
#     OpenMP, decoy CONDA_PREFIX runs, zig-fc with no flang (Windows: rzig's
#     dry runs, -L from where the tree now is, CONDA_PREFIX ignored).
# The static checks of the tree (Makeconf, the compilers are rzig, rpaths,
# the glibc ceiling, the C++ runtime of R's binaries, the macOS floor and
# load commands, minimal's excluded libraries) read files, headers and
# load commands, which moving the tree does not change: verify-tree.sh
# runs them on the installed tree right after the build. Shared helpers:
# verify-helpers.sh (rpaths_of, needed_of, cxx_deps, minos_over_floor).
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

case "$OS" in
  linux)
    case "$(uname -m)" in
      x86_64) plat=linux-64 ;;
      aarch64) plat=linux-aarch64 ;;
      *) plat="linux-$(uname -m)" ;;
    esac
    ext=tar.gz
    ;;
  macos)
    case "$(uname -m)" in
      arm64) plat=osx-arm64 ;;
      x86_64) plat=osx-64 ;;
      *) plat="osx-$(uname -m)" ;;
    esac
    ext=tar.gz
    ;;
  windows)
    plat=win-64
    ext=zip
    ;;
esac

artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.$ext"
test -f "$artifact" || { echo "error: $artifact not found — run 'pixi run package' first" >&2; exit 1; }

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
echo "== extracting $artifact to $VERIFY_DIR"
if [ "$ext" = zip ]; then
  unzip -q "$artifact" -d "$VERIFY_DIR"
else
  tar -xzf "$artifact" -C "$VERIFY_DIR"
fi
# Same $PREFIX-basename derivation as package-standalone.sh's own
# prefix_base fix — the archive's top-level directory name matches
# whatever $PREFIX actually was at package time (zig-built prefixes carry
# a "-zig" suffix), not a hardcoded "R-$R_VERSION-$FLAVOR" (found via a
# real verify-bundle run against a zig-built prefix on kappa: extraction
# succeeded but the hardcoded BUNDLE_DIR guess didn't exist).
BUNDLE_DIR="$VERIFY_DIR/$(basename "$PREFIX")"

# minimal (the wheel profile) has no cairo/png by design — assert that
# instead, so a graphics stack creeping back in fails here too.
if [ "$VARIANT" = minimal ]; then
  CHECK_CAPS='stopifnot(!capabilities("cairo"), !capabilities("png"), !capabilities("ICU"))'
else
  CHECK_CAPS='stopifnot(capabilities("cairo"), capabilities("png"))'
fi
CHECK_R="
stopifnot(max(abs(solve(matrix(c(2,0,0,2),2,2)) - matrix(c(.5,0,0,.5),2,2))) < 1e-9)
$CHECK_CAPS
cat('bundle OK\n')
"

if [ "$OS" = windows ]; then
  R_BIN="$BUNDLE_DIR/Library/lib/R/bin/x64/Rscript.exe"
  test -x "$R_BIN" || { echo "error: $R_BIN missing from extracted bundle" >&2; exit 1; }
  "$R_BIN" --vanilla -e "$CHECK_R"
else
  R_BIN="$BUNDLE_DIR/bin/R"
  test -x "$R_BIN" || { echo "error: $R_BIN missing from extracted bundle" >&2; exit 1; }
  env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
    "$R_BIN" --vanilla --no-echo -e "$CHECK_R"
fi
echo "== standalone bundle verified relocatable ($OS/$FLAVOR)"

# Windows: what rzig (gcc.exe) adds for the environment it is installed in
# (F3b): -L<prefix>/Library/lib on a link, no rpath, and nothing from a
# CONDA_PREFIX it is not installed in. A dry run; contract-test.sh
# compiles for real. (unix: the compiled-package checks below)
if [ "$OS" = windows ]; then
  decoy="$VERIFY_DIR/decoy"
  mkdir -p "$decoy/Library/include" "$decoy/Library/lib"
  : > "$decoy/Library/include/omp.h"; : > "$decoy/Library/lib/libomp.lib"
  argv="$(CONDA_PREFIX="$(cygpath -w "$decoy")" RZIG_PRINT_ARGV=1 "$BUNDLE_DIR/Library/lib/R/bin/toolchain/gcc.exe" -shared -fopenmp -o x.dll a.o)"
  if ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$(basename "$BUNDLE_DIR")/Library/lib\$" ||
     printf '%s\n' "$argv" | grep -qi -- 'rpath\|decoy'; then
    printf '%s\n' "$argv" >&2
    echo "error: gcc.exe's environment flags: no -L<prefix>/Library/lib, or an rpath, or CONDA_PREFIX's" >&2
    exit 1
  fi
  echo "== compilers' environment verified (dry run): -L<prefix>/Library/lib, no rpath, CONDA_PREFIX ignored"
  # zig-fc.exe (F3c): a shared link of objects (USE_FC_TO_LINK) goes
  # through zig as gcc.exe's does, with the static runtime of the flang on
  # PATH and libc++ appended.
  if command -v flang > /dev/null 2>&1; then
    argv="$(RZIG_PRINT_ARGV=1 "$BUNDLE_DIR/Library/lib/R/bin/toolchain/zig-fc.exe" -shared -o x.dll a.o)"
    if ! printf '%s\n' "$argv" | grep -qi -- '/libflang_rt\.runtime\.a$' ||
       ! printf '%s\n' "$argv" | grep -qxF -- '-lc++' ||
       ! printf '%s\n' "$argv" | grep -qi -- "^-L.*/$(basename "$BUNDLE_DIR")/Library/lib\$"; then
      printf '%s\n' "$argv" >&2
      echo "error: zig-fc.exe's shared link lacks the static flang runtime, -lc++ or -L<prefix>/Library/lib" >&2
      exit 1
    fi
    echo "== zig-fc.exe verified (dry run): a shared link goes through zig with the static flang runtime and -lc++"
  fi
fi

# TLS trust (unix): the bundle must verify HTTPS without the build env's
# trust anchors. conda-forge's libcurl/OpenSSL carry $CONDA/ssl compiled
# in, which exists on this machine only, so "HTTPS works here" proves
# nothing on its own. scripts/tls-check.R (shared with wheel-test.sh)
# checks the wiring and makes real requests; here, where strace can
# trace, the requests must also read no CA file from the build env. The
# trace only counts when the requests ran: curl opens its CA file after
# connecting, so an offline run would pass it vacuously. Windows uses
# Schannel (the Windows store) and needs none of this.
if [ "$OS" != windows ]; then
  tls_r="$(cd "$(dirname "$0")" && pwd)/tls-check.R"
  tls_out="$VERIFY_DIR/tls-check.out"
  run_tls() {
    env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
      "$@" "$R_BIN" --vanilla --no-echo -f "$tls_r"
  }
  build_env="${CONDA_PREFIX:-}"
  strace_bin=""
  if [ "$OS" = linux ] && [ -n "$build_env" ] && command -v strace > /dev/null 2>&1; then
    # `?`: skip syscalls this architecture lacks (aarch64 has no open(2)).
    # Preflight: where ptrace is blocked (containers, Yama) the trace is
    # skipped rather than failing a good bundle.
    if strace -f -qq -e 'trace=?openat,?open' -o /dev/null /bin/true 2> /dev/null; then
      strace_bin="$(command -v strace)"
    else
      echo "   note: strace cannot trace here; build-env CA check skipped"
    fi
  fi
  if [ -n "$strace_bin" ]; then
    trace="$VERIFY_DIR/tls-trace.txt"
    run_tls "$strace_bin" -f -qq -e 'trace=?openat,?open' -o "$trace" | tee "$tls_out"
  else
    run_tls | tee "$tls_out"
  fi
  if grep -q '^TLS: requests OK' "$tls_out"; then
    if [ -n "$strace_bin" ]; then
      opened="$(grep -oE "\"$build_env/[^\"]*\"" "$trace" | tr -d '"' | sort -u || true)"
      opened_ca="$(printf '%s\n' "$opened" | grep -E 'cacert|ca-bundle|cert\.pem|/certs(/|$)' || true)"
      if [ -n "$opened_ca" ]; then
        echo "error: HTTPS read trust anchors from the build env:" >&2
        printf '  %s\n' $opened_ca >&2
        exit 1
      fi
      other="$(printf '%s\n' "$opened" | grep -v '^$' | tr '\n' ' ' || true)"
      [ -z "$other" ] || echo "   note: still opened from the build env (missing elsewhere, harmless): $other"
    fi
    echo "== TLS trust verified${strace_bin:+ (no CA file read from the build env)}"
  else
    echo "== TLS trust: wiring checked; requests skipped (offline)"
  fi
fi

# Packages compiled with the relocated tree (unix). A package compiled
# with this tree (C++, so libc++ is involved on macOS) must record no
# rpath at all, and still load: libR and the libraries it needs are
# already in the process. rzig makes that so (on macOS its
# deployment-target triple records no rpath for -L directories), and adds
# an rpath only into a conda env, which this tree is not
# (zigbuild/tools/rzig/environment.zig). That every rpath of the tree's
# own binaries is relative is verify-tree.sh's. Skipped without zig, as on
# a user machine.
if [ "$OS" != windows ]; then
  # A package's objects and .so at or below the floor too: zig stamps the
  # link, so only the objects show a compiler that ignored it (flang
  # defaults to the host SDK's version).
  check_minos() {
    [ "$OS" = macos ] || return 0
    for f in "$@"; do
      if m="$(minos_over_floor "$f")"; then
        echo "error: ${f##*/} minos $m > $MACOS_MIN" >&2
        exit 1
      fi
    done
  }

  zig_dir="$(dirname "$(command -v zig 2>/dev/null || echo /nonexistent/zig)")"
  if [ -x "$zig_dir/zig" ]; then
    pkg_dir="$VERIFY_DIR/shlib"
    mkdir -p "$pkg_dir"
    cat > "$pkg_dir/rp.cpp" <<'CPP'
#include <R.h>
#include <Rinternals.h>
#include <stdexcept>
#include <string>
extern "C" SEXP rp(void)
{
    std::string s("r-zig");
    try { throw std::runtime_error("!"); } catch (const std::exception &e) { s += e.what(); }
    return ScalarInteger((int) s.size());
}
CPP
    (cd "$pkg_dir" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
      "$R_BIN" CMD SHLIB -o rp.so rp.cpp > shlib.log 2>&1) || { cat "$pkg_dir/shlib.log" >&2; echo "error: R CMD SHLIB failed with the bundle" >&2; exit 1; }
    pkg_rp="$(rpaths_of "$pkg_dir/rp.so" | tr '\n' ' ')"
    if [ -n "$pkg_rp" ]; then
      echo "error: a package compiled with the bundle records rpaths: $pkg_rp" >&2
      exit 1
    fi
    # zig's own libc++ is static, and rzig keeps it so where conda-forge
    # zig would pick a shared one (zigbuild/tools/rzig/libcxx_mirror.zig).
    check_minos "$pkg_dir/rp.o" "$pkg_dir/rp.so"
    cxx_dep="$(cxx_deps "$pkg_dir/rp.so")"
    if [ -n "$cxx_dep" ]; then
      echo "error: a C++ package compiled with the bundle needs a shared C++ runtime: $cxx_dep" >&2
      exit 1
    fi
    (cd "$pkg_dir" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
      "$R_BIN" --vanilla --no-echo -e 'dyn.load("rp.so"); stopifnot(.Call("rp") == 6L)')
    echo "== compiled package verified: no rpath, static libc++, loads (C++)"

    # Fortran: FLIBS names the static flang runtime (build.zig), so a
    # Fortran package needs no shared runtime and no rpath into the build
    # env. Checked here, on the relocated tree, because the contract suite
    # runs before staging, while libR still carries build-env rpaths that
    # hid the shared runtime once (2026-09-30, macOS slim). minimal empties
    # FLIBS (no Fortran compiler with the wheel), so it is skipped there.
    if grep -q '^FLIBS = .*flang_rt' "$BUNDLE_DIR/lib/R/etc/Makeconf" && [ -x "$zig_dir/flang" ]; then
      # fw needs the runtime (internal formatted I/O: _FortranAio*), so a
      # dropped -lflang_rt.runtime fails the dyn.load; fsum alone would not.
      cat > "$pkg_dir/fs.f" <<'FORTRAN'
      subroutine fsum(n, x, s)
      integer n, i
      double precision x(n), s
      s = 0d0
      do 10 i = 1, n
         s = s + x(i)
   10 continue
      end
      subroutine fw(n, r)
      integer n, r
      character(len=12) buf
      write(buf,'(i0)') n
      read(buf,'(i12)') r
      end
FORTRAN
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" CMD SHLIB -o fs.so fs.f > fshlib.log 2>&1) || { cat "$pkg_dir/fshlib.log" >&2; echo "error: R CMD SHLIB of a Fortran file failed with the bundle" >&2; exit 1; }
      check_minos "$pkg_dir/fs.o" "$pkg_dir/fs.so"
      f_dep="$(needed_of "$pkg_dir/fs.so" | grep flang_rt || true)"
      if [ -n "$f_dep" ]; then
        echo "error: a Fortran package compiled with the bundle needs a shared flang runtime: $f_dep" >&2
        exit 1
      fi
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("fs.so"); stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0)$s == 6, .Fortran("fw", 42L, r = 0L)$r == 42L)')
      echo "== compiled package verified: static flang runtime, loads (Fortran)"

      # USE_FC_TO_LINK (F3c): R links with SHLIB_FCLD = $(FC), rzig's
      # zig-fc, and takes $(FLIBS) off the line. zig-fc links objects
      # through zig, as zig-cc does, with the static runtime of the flang on
      # PATH (flang's own driver: "cannot find -lflang_rt.runtime"): no
      # shared runtime, no rpath, the macOS floor, and it loads.
      mkdir -p "$pkg_dir/fl"
      cp "$pkg_dir/fs.f" "$pkg_dir/fl/fl.f"
      echo 'USE_FC_TO_LINK =' > "$pkg_dir/fl/Makevars"
      (cd "$pkg_dir/fl" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" CMD SHLIB -o fl.so fl.f > shlib.log 2>&1) || { cat "$pkg_dir/fl/shlib.log" >&2; echo "error: a USE_FC_TO_LINK Fortran package failed to link with the bundle" >&2; exit 1; }
      grep -Eq 'toolchain/zig-fc (-shared|-dynamiclib) .*-o fl\.so' "$pkg_dir/fl/shlib.log" || { cat "$pkg_dir/fl/shlib.log" >&2; echo "error: the USE_FC_TO_LINK link did not run zig-fc" >&2; exit 1; }
      check_minos "$pkg_dir/fl/fl.o" "$pkg_dir/fl/fl.so"
      f_dep="$(needed_of "$pkg_dir/fl/fl.so" | grep flang_rt || true)"
      fl_rp="$(rpaths_of "$pkg_dir/fl/fl.so" | tr '\n' ' ')"
      if [ -n "$f_dep" ] || [ -n "$fl_rp" ]; then
        echo "error: the USE_FC_TO_LINK package needs a shared flang runtime ($f_dep) or records rpaths ($fl_rp)" >&2
        exit 1
      fi
      (cd "$pkg_dir/fl" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("fl.so"); stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0)$s == 6, .Fortran("fw", 42L, r = 0L)$r == 42L)')
      echo "== compiled package verified: USE_FC_TO_LINK links through zig-fc, static flang runtime, no rpath, loads (Fortran)"
    fi

    # FC names zig-fc whether or not a flang is installed: with none on
    # PATH, a Fortran compile stops at once with exit 127 and a message
    # naming flang as the remedy (never R_ZIG_TOOLCHAIN_HINT: zig-fc ships
    # in the toolchain, so installing the toolchain cannot be the fix).
    if ! [ -x /usr/bin/flang ] && ! [ -x /bin/flang ]; then
      printf '      end\n' > "$pkg_dir/nofc.f"
      rc=0
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
        "$BUNDLE_DIR/lib/R/bin/toolchain/zig-fc" -c nofc.f -o nofc.o > nofc.log 2>&1) || rc=$?
      if [ "$rc" != 127 ] || ! grep -q '^zig-fc: no flang on PATH' "$pkg_dir/nofc.log"; then
        cat "$pkg_dir/nofc.log" >&2
        echo "error: zig-fc with no flang on PATH: exit $rc, or no message naming flang" >&2
        exit 1
      fi
      echo "== zig-fc with no flang on PATH: exit 127, '$(head -1 "$pkg_dir/nofc.log")'"
    fi

    # $(FLIBS) on a C package's link (CRAN's usual PKG_LIBS = $(LAPACK_LIBS)
    # $(BLAS_LIBS) $(FLIBS)) with no flang on PATH, as with the wheel: the
    # compilers (rzig) drop -lflang_rt.runtime: nothing was compiled by flang.
    # PATH: the env's make alone (slim and full use make from PATH), no flang.
    mkdir -p "$pkg_dir/cf/bin"
    ln -sf "$(command -v make)" "$pkg_dir/cf/bin/make"
    printf '%s\n' '#include <R.h>' 'void cfl(int *n) { *n = 7; }' > "$pkg_dir/cf/cf.c"
    printf '%s\n' 'PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)' > "$pkg_dir/cf/Makevars"
    (cd "$pkg_dir/cf" && env -i HOME="$HOME" PATH="$pkg_dir/cf/bin:/usr/bin:/bin" ZIG_BIN="$zig_dir/zig" TMPDIR="${TMPDIR:-/tmp}" \
      "$R_BIN" CMD SHLIB -o cf.so cf.c > shlib.log 2>&1) || { cat "$pkg_dir/cf/shlib.log" >&2; echo "error: a C package using \$(FLIBS) failed to link with no flang on PATH" >&2; exit 1; }
    (cd "$pkg_dir/cf" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
      "$R_BIN" --vanilla --no-echo -e 'dyn.load("cf.so"); stopifnot(.C("cfl", n = 0L)$n == 7L)')
    echo "== compiled package verified: \$(FLIBS) links with no Fortran compiler (C)"

    # OpenMP (slim, full): omp.h from the tree's own include/ (build.zig
    # installs it in a tree that is not a conda env) and the vendored
    # libomp, no rpath, nothing from the build env. Makeconf's CPPFLAGS
    # and LDFLAGS are empty (F3b), so these build only through the -I and
    # -L rzig adds for the environment it is installed in. Three ways
    # packages ask: R's SHLIB_OPENMP_CFLAGS, data.table's configure probe
    # (omp.h included with no OpenMP flag), and PKG_LIBS = -lomp with no
    # -fopenmp at all (libomp found through rzig's -L alone).
    if grep -q '^SHLIB_OPENMP_CFLAGS = *-' "$BUNDLE_DIR/lib/R/etc/Makeconf"; then
      mkdir -p "$pkg_dir/omp" "$pkg_dir/lomp"
      printf '%s\n' '#include <omp.h>' '#include <R.h>' 'void ompn(int *n) { *n = omp_get_max_threads(); }' > "$pkg_dir/omp/omp.c"
      printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$pkg_dir/omp/Makevars"
      printf '%s\n' '#include <omp.h>' 'int ompprobe(void) { return 0; }' > "$pkg_dir/omp/probe.c"
      printf '%s\n' 'extern int omp_get_max_threads(void);' 'void lompn(int *n) { *n = omp_get_max_threads(); }' > "$pkg_dir/lomp/lomp.c"
      printf '%s\n' 'PKG_LIBS = -lomp' > "$pkg_dir/lomp/Makevars"
      (cd "$pkg_dir/omp" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" CMD SHLIB -o omp.so omp.c > shlib.log 2>&1 && rm Makevars &&
        env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" CMD SHLIB -o probe.so probe.c >> shlib.log 2>&1 && cd "$pkg_dir/lomp" &&
        env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" CMD SHLIB -o lomp.so lomp.c >> "$pkg_dir/omp/shlib.log" 2>&1) || { cat "$pkg_dir/omp/shlib.log" >&2; echo "error: an OpenMP package failed to build with the bundle" >&2; exit 1; }
      check_minos "$pkg_dir/omp/omp.so" "$pkg_dir/lomp/lomp.so"
      omp_rp="$(rpaths_of "$pkg_dir/omp/omp.so" | tr '\n' ' ')$(rpaths_of "$pkg_dir/lomp/lomp.so" | tr '\n' ' ')"
      if [ -n "$omp_rp" ]; then
        echo "error: an OpenMP package compiled with the bundle records rpaths: $omp_rp" >&2
        exit 1
      fi
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("omp/omp.so"); dyn.load("lomp/lomp.so"); stopifnot(.C("ompn", n = 0L)$n >= 1L, .C("lompn", n = 0L)$n >= 1L)')
      echo "== compiled package verified: OpenMP from the tree's own omp.h and libomp through rzig's -I/-L (SHLIB_OPENMP_CFLAGS, a flagless omp.h probe, PKG_LIBS = -lomp), no rpath, loads"
    fi

    # rzig never reads CONDA_PREFIX (F3b): an activated env R is not
    # installed in adds nothing. Two decoys: the env this check runs in
    # (real headers and libraries, a conda-meta) and a poisoned one
    # (#error in omp.h and zlib.h, junk libraries). The C++ package, and the
    # OpenMP one where the tree has OpenMP, rebuild with each as
    # CONDA_PREFIX: no rpath, and rzig's command lines name neither.
    decoy="$VERIFY_DIR/decoy"
    mkdir -p "$decoy/conda-meta" "$decoy/include" "$decoy/lib"
    printf '#error decoy CONDA_PREFIX\n' > "$decoy/include/omp.h"; cp "$decoy/include/omp.h" "$decoy/include/zlib.h"
    printf 'junk' > "$decoy/lib/libomp.so"; cp "$decoy/lib/libomp.so" "$decoy/lib/libz.so"
    for cpfx in "$decoy" ${CONDA_PREFIX:+"$CONDA_PREFIX"}; do
      rm -f "$pkg_dir/rp.so" "$pkg_dir/rp.o" "$pkg_dir/omp/omp.so" "$pkg_dir/omp/omp.o"
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" CONDA_PREFIX="$cpfx" \
        "$R_BIN" CMD SHLIB -o rp.so rp.cpp > decoy.log 2>&1) || { cat "$pkg_dir/decoy.log" >&2; echo "error: R CMD SHLIB failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
      sos="$pkg_dir/rp.so"
      if [ -f "$pkg_dir/omp/omp.c" ]; then
        printf '%s\n' 'PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)' 'PKG_LIBS = $(SHLIB_OPENMP_CFLAGS)' > "$pkg_dir/omp/Makevars"
        (cd "$pkg_dir/omp" && env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" TMPDIR="${TMPDIR:-/tmp}" CONDA_PREFIX="$cpfx" \
          "$R_BIN" CMD SHLIB -o omp.so omp.c > decoy.log 2>&1) || { cat "$pkg_dir/omp/decoy.log" >&2; echo "error: the OpenMP package failed with CONDA_PREFIX=$cpfx" >&2; exit 1; }
        sos="$sos $pkg_dir/omp/omp.so"
      fi
      for so in $sos; do
        so_rp="$(rpaths_of "$so" | tr '\n' ' ')"
        [ -z "$so_rp" ] || { echo "error: ${so##*/} built with CONDA_PREFIX=$cpfx records rpaths: $so_rp" >&2; exit 1; }
      done
      # (zig itself, and its lib dir, may live in the build env)
      argv="$(cd "$pkg_dir" && for a in "-fopenmp -c a.c" "-shared -fopenmp -o x.so a.o -lz" "-o conftest conftest.c -lz"; do
        env -i HOME="$HOME" PATH="$zig_dir:/usr/bin:/bin" CONDA_PREFIX="$cpfx" RZIG_PRINT_ARGV=1 "$BUNDLE_DIR/lib/R/bin/toolchain/zig-cc" $a; done |
        grep -vxF -- "$zig_dir/zig" | grep -v '^ZIG_LIB_DIR=')"
      if printf '%s\n' "$argv" | grep -F -- "$cpfx"; then
        echo "error: rzig's command lines name CONDA_PREFIX=$cpfx" >&2; exit 1
      fi
      printf '%s\n' "$argv" | grep -qxF -- "-L$(cd "$BUNDLE_DIR" && pwd -P)/lib" || { printf '%s\n' "$argv" >&2; echo "error: rzig's link lines lack the tree's -L" >&2; exit 1; }
    done
    echo "== CONDA_PREFIX ignored: the C++ package (and the OpenMP one, where offered) builds with a poisoned and with the build env as CONDA_PREFIX, no rpath, and rzig's command lines name neither"
  else
    echo "== compiled-package checks skipped (no zig on PATH)"
  fi
fi
