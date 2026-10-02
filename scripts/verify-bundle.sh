#!/usr/bin/env bash
# Extract the packaged standalone bundle to a fresh location and run it
# with the pixi/conda env off PATH — the same adversarial check done
# manually on omicron/kappa for every relocation fix this project has
# shipped, automated so CI catches a regression instead of relying on a
# human to re-run it. Windows binaries derive R_HOME natively (no PATH
# tricks needed there); unix binaries get a scrubbed PATH
# to prove they need nothing from the environment that built them.
. "$(dirname "$0")/env.sh"

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

# The compilers Makeconf names are rzig (feat-no-host-paths F3), one
# binary under every name: compiling runs no shell script of ours.
if [ "$OS" = windows ]; then
  tc_dir="Library/lib/R/bin/toolchain"; tc_names="gcc.exe g++.exe zig-cc zig-cxx"
else
  tc_dir="lib/R/bin/toolchain"; tc_names="zig-cc zig-cxx zig-ar zig-ranlib"
fi
for t in $tc_names; do
  f="$BUNDLE_DIR/$tc_dir/$t"
  if [ ! -f "$f" ] || [ "$(head -c2 "$f")" = '#!' ] || ! cmp -s "$f" "$BUNDLE_DIR/$tc_dir/${tc_names%% *}"; then
    echo "error: $tc_dir/$t is missing, a script, or not the same rzig as the rest" >&2
    exit 1
  fi
done
echo "== compilers verified: $tc_dir/{${tc_names// /,}} are rzig"

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

# Makeconf names no build path (feat-no-host-paths F1.5): build.zig writes
# the environment as $(R_HOME)/../.., FLIBS as -lflang_rt.runtime and no
# rpath, and nothing edits the file afterwards. Comment lines count.
# CPPFLAGS and LDFLAGS are empty (F3b): the compilers, rzig, add the
# environment's -I and -L (and a conda env's rpath) themselves.
if [ "$OS" = windows ]; then mk="$BUNDLE_DIR/Library/lib/R/etc/x64/Makeconf"; else mk="$BUNDLE_DIR/lib/R/etc/Makeconf"; fi
bad=""
# Windows: ROOT is env.sh's /c/... form; PIXI_PROJECT_ROOT is the native
# one, and a leak is written C:\... or C:/... (any drive-letter case).
for p in "$ROOT" "${PIXI_PROJECT_ROOT:-}" "${CONDA_PREFIX:-}"; do
  [ -n "$p" ] || continue
  for q in "$p" "$(printf '%s' "$p" | tr '\\' /)"; do
    if grep -qiF -- "$q" "$mk"; then bad="$bad $q"; fi
  done
done
if grep -q -- '-rpath' "$mk"; then bad="$bad -rpath"; fi
grep -q '^FLIBS = .*-lflang_rt\.runtime' "$mk" || bad="$bad FLIBS"
for v in CPPFLAGS LDFLAGS; do
  # (the x64 Makeconf has CRLF line ends)
  grep -Eq "^$v = *"$'\r'"?\$" "$mk" || bad="$bad $v-not-empty"
  if [ "$OS" != windows ] && grep -Eq "'$v=" "$mk"; then bad="$bad $v-in-configure-line"; fi
done
if [ -n "$bad" ]; then
  echo "error: ${mk#$BUNDLE_DIR/} names build paths or lacks the relative forms:$bad" >&2
  exit 1
fi
echo "== Makeconf verified: no build path, no rpath, CPPFLAGS and LDFLAGS empty, FLIBS = -lflang_rt.runtime"

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

# minimal: the point of the profile is what R does NOT link. No binary
# of R's own (libR, modules, base-package .so, bin/exec/R) may name a
# library from the graphics/ICU/OpenMP/libdeflate stacks. That is the
# part the configure profile controls; what third-party libraries drag
# in is reported, not failed: conda-forge's libcurl >= 8.21 links
# libpsl, which links ICU (and so libstdc++), on every platform — see
# pixi.toml's [feature.minimal] for the size cost and the pin that would
# avoid it.
if [ "$VARIANT" = minimal ] && [ "$OS" != windows ]; then
  excluded_re='lib(cairo|pango|harfbuzz|fontconfig|freetype|glib|gobject|gio|pixman|png|jpeg|tiff|X11|xcb|icu|omp|iomp|gomp|deflate)'
  r_bins="$VERIFY_DIR/r-bins.txt"
  find "$BUNDLE_DIR/lib/R" -path "$BUNDLE_DIR/lib/R/bin/toolchain" -prune -o \
    -type f \( -name '*.so' -o -name '*.dylib' -o -path '*/bin/exec/R' \) -print > "$r_bins"
  bad=""
  while IFS= read -r f; do
    if [ "$OS" = linux ]; then
      deps="$(patchelf --print-needed "$f" 2>/dev/null || true)"
    else
      deps="$(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)"
    fi
    hit="$(printf '%s\n' "$deps" | grep -E "(^|/)$excluded_re" || true)"
    [ -z "$hit" ] || bad="$bad ${f#$BUNDLE_DIR/}->$(echo $hit | tr ' ' ',')"
  done < "$r_bins"
  if [ -n "$bad" ]; then
    echo "error: minimal R links libraries its profile excludes:$bad" >&2
    exit 1
  fi
  echo "== minimal profile verified: $(wc -l < "$r_bins" | tr -d ' ') R binaries, none links graphics/ICU/OpenMP/libdeflate"
  transitive="$(ls "$BUNDLE_DIR/lib" | grep -E "^$excluded_re" | tr '\n' ' ' || true)"
  [ -z "$transitive" ] || echo "   note: vendored as dependencies of third-party libs (not of R): $transitive"
fi

# Old-server guarantee (Linux only): fail if any shipped ELF requires glibc
# newer than the floor build.zig's target pin promises. This is the check
# side of the floor — a zig update or stray flag that raises the
# requirement should die here, not on a customer's old box.
#
# Two tiers, learned from the first hosted-CI run of this check
# (2026-09-19): everything R needs to *run* (R itself, its modules and
# package .so files, every vendored library under lib/) must stay at the
# 2.17 floor — and does. The compile-time helper tools build.zig installs
# into lib/R/bin/toolchain (nm/realpath/sed/... for bin/libtool and
# javareconf) come from conda-forge, whose linux baseline is glibc 2.28
# now: coreutils' `realpath` needs GLIBC_2.28, nothing else did. Those
# tools only run when compiling packages or reconfiguring Java, which
# already requires a development machine with zig on PATH, so they are
# bounded at conda-forge's own baseline instead — anything above *that*
# still trips (a host tool leaking in, conda-forge moving to 2.34).
#
# The ELF list is collected first, then checked: an `exit 1` inside a
# `while read < <(find ...)` loop fires the EXIT trap's rm -rf while find
# is still walking the tree — the real error line was followed by a
# screenful of "cannot open"/"No such file or directory" noise from the
# half-deleted tree, which is what the first CI failure looked like.
if [ "$OS" = linux ]; then
  GLIBC_FLOOR="2.17"          # runtime artifacts: R + vendored libs
  GLIBC_TOOLS_CEILING="2.28"  # lib/R/bin/toolchain helpers (conda-forge baseline)
  elf_list="$VERIFY_DIR/elf-list.txt"
  find "$BUNDLE_DIR" -type f \( -name '*.so*' -o -perm -u+x \) \
    -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "7f 45 4c 46"' _ {} \; -print \
    > "$elf_list"
  worst=""; worst_file=""; tools_over=0; failed=0
  while IFS= read -r f; do
    # `|| true`: an ELF with no versioned glibc imports makes grep exit 1,
    # and env.sh's pipefail + set -e would silently kill the whole script
    # on that assignment (latent in the first version of this check too).
    ceil=$(objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
    [ -z "$ceil" ] && continue
    case "$f" in
      "$BUNDLE_DIR"/lib/R/bin/toolchain/*) limit="$GLIBC_TOOLS_CEILING"; tier="toolchain helper" ;;
      *) limit="$GLIBC_FLOOR"; tier="runtime" ;;
    esac
    if [ "$(printf '%s\n' "$ceil" "$limit" | sort -V | tail -1)" != "$limit" ]; then
      echo "error: $f ($tier) requires GLIBC_$ceil > $limit" >&2
      failed=1
    elif [ "$tier" = "toolchain helper" ] && [ "$(printf '%s\n' "$ceil" "$GLIBC_FLOOR" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]; then
      echo "note: ${f#$BUNDLE_DIR/} (toolchain helper, compile-time only) requires GLIBC_$ceil > runtime floor $GLIBC_FLOOR"
      tools_over=$((tools_over + 1))
    fi
    if [ "$tier" = runtime ] && { [ -z "$worst" ] || [ "$(printf '%s\n' "$ceil" "$worst" | sort -V | tail -1)" = "$ceil" ]; }; then
      worst="$ceil"; worst_file="${f#$BUNDLE_DIR/}"
    fi
  done < "$elf_list"
  [ "$failed" = 0 ] || exit 1
  echo "== glibc ceiling verified: runtime worst $worst ($worst_file) <= floor $GLIBC_FLOOR; $tools_over toolchain helper(s) above the floor, all <= $GLIBC_TOOLS_CEILING"
fi

# No build-machine rpaths (unix). Every RUNPATH/LC_RPATH entry in the tree
# must be relative to the file ($ORIGIN, @loader_path): zig records the
# build env's lib dir and zig-cache dirs unless told not to, which build.zig
# does (relRPaths, linkSibling). Then a package compiled with this tree (C++, so libc++ is
# involved on macOS) must record no rpath at all, and still load: libR and
# the libraries it needs are already in the process. rzig makes that
# so (on macOS its deployment-target triple records no rpath for -L
# directories), and adds an rpath only into a conda env, which this tree
# is not (zigbuild/tools/rzig/environment.zig). Skipped without zig, as on
# a user machine.
if [ "$OS" != windows ]; then
  bin_list="$VERIFY_DIR/bin-list.txt"
  if [ "$OS" = linux ]; then
    find "$BUNDLE_DIR" -type f \( -name '*.so*' -o -perm -u+x \) \
      -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "7f 45 4c 46"' _ {} \; -print > "$bin_list"
  else
    find "$BUNDLE_DIR" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) \
      -exec sh -c 'head -c4 "$1" | od -An -tx1 | grep -q "cf fa ed fe"' _ {} \; -print > "$bin_list"
  fi
  rpaths_of() {
    if [ "$OS" = linux ]; then
      patchelf --print-rpath "$1" 2>/dev/null | tr ':' '\n' | grep -v '^$' || true
    else
      otool -l "$1" | awk '/cmd LC_RPATH/ {r = 1} r && / path / {sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r = 0}'
    fi
  }
  bad=""
  while IFS= read -r f; do
    for rp in $(rpaths_of "$f"); do
      case "$rp" in '$ORIGIN'|'$ORIGIN/'*|@loader_path|@loader_path/*) ;; *) bad="$bad
  ${f#$BUNDLE_DIR/}: $rp" ;; esac
    done
  done < "$bin_list"
  if [ -n "$bad" ]; then
    echo "error: build-machine rpaths in the bundle:$bad" >&2
    exit 1
  fi
  echo "== rpaths verified: $(wc -l < "$bin_list" | tr -d ' ') binaries, all relative"

  # Static libc++ everywhere (decided 2026-09-30): none of R's own
  # binaries may depend on a shared C++ runtime. The vendored conda
  # libraries in lib/ may (ICU links libc++ on macOS, libstdc++ on linux);
  # they are not ours to build.
  cxx_deps() {
    if [ "$OS" = linux ]; then
      patchelf --print-needed "$1" 2>/dev/null | grep -E '^lib(c\+\+|stdc\+\+)\.so' || true
    else
      otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '(^|/)lib(c\+\+|stdc\+\+)[.0-9]*\.dylib$' || true
    fi
  }
  bad=""
  n_r=0
  while IFS= read -r f; do
    case "$f" in "$BUNDLE_DIR"/lib/R/bin/toolchain/*) continue ;; "$BUNDLE_DIR"/lib/R/*) ;; *) continue ;; esac
    n_r=$((n_r + 1))
    hit="$(cxx_deps "$f")"
    [ -z "$hit" ] || bad="$bad ${f#$BUNDLE_DIR/}->$(echo $hit | tr ' ' ',')"
  done < "$bin_list"
  if [ -n "$bad" ]; then
    echo "error: R binaries depend on a shared C++ runtime:$bad" >&2
    exit 1
  fi
  echo "== C++ runtime verified: $n_r R binaries, none needs a shared libc++/libstdc++"

  # macOS deployment target: every Mach-O in the tree at or below
  # MACOS_MIN (build.zig's macos_min; conda's vendored libraries are
  # lower). A native target would stamp the build machine's version.
  # Then the load commands: install names relative (packages copy libR's
  # into their own load commands), dependencies relative or the system's,
  # and R's own binaries take from the SDK's /usr/lib only what conda has
  # no copy of: build.zig adds the SDK's lib dir last, and ahead of
  # conda's it would bind -lz/-liconv/-lcurl to the SDK's older stubs.
  if [ "$OS" = macos ]; then
    bad=""
    while IFS= read -r f; do
      m="$(macho_minos "$f")"
      if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then bad="$bad ${f#$BUNDLE_DIR/}=${m:-none}"; fi
    done < "$bin_list"
    if [ -n "$bad" ]; then
      echo "error: Mach-O files above the macOS $MACOS_MIN floor:$bad" >&2
      exit 1
    fi
    echo "== macOS floor verified: $(wc -l < "$bin_list" | tr -d ' ') Mach-O files, minos <= $MACOS_MIN"
    bad=""
    while IFS= read -r f; do
      id="$(otool -D "$f" 2>/dev/null | tail -n +2)"
      case "$id" in ""|@rpath/*|@loader_path/*|@executable_path/*|[!/]*) ;; *) bad="$bad ${f#$BUNDLE_DIR/}:id=$id" ;; esac
      for dep in $(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}'); do
        [ "$dep" = "$id" ] && continue
        case "$dep" in @rpath/*|@loader_path/*|@executable_path/*|/usr/lib/*|/System/Library/*) ;; *) bad="$bad ${f#$BUNDLE_DIR/}:$dep" ;; esac
        case "$f" in "$BUNDLE_DIR"/lib/R/bin/toolchain/*) ;; "$BUNDLE_DIR"/lib/R/*)
          case "$dep" in /usr/lib/libSystem.B.dylib|/usr/lib/libresolv.9.dylib|/usr/lib/libobjc.A.dylib) ;; /usr/lib/*) bad="$bad ${f#$BUNDLE_DIR/}:$dep(SDK)" ;; esac ;;
        esac
      done
    done < "$bin_list"
    [ "$(otool -D "$BUNDLE_DIR/lib/R/lib/libR.dylib" | tail -n +2)" = "@rpath/libR.dylib" ] || bad="$bad lib/R/lib/libR.dylib:id"
    if [ -n "$bad" ]; then
      echo "error: install names or load commands:$bad" >&2
      exit 1
    fi
    echo "== load commands verified: relative install names, no build-machine or SDK-stub dependencies"
  fi
  # A package's objects and .so at or below the floor too: zig stamps the
  # link, so only the objects show a compiler that ignored it (flang
  # defaults to the host SDK's version).
  check_minos() {
    [ "$OS" = macos ] || return 0
    for f in "$@"; do
      m="$(macho_minos "$f")"
      if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then
        echo "error: ${f##*/} minos ${m:-none} > $MACOS_MIN" >&2
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
      if [ "$OS" = linux ]; then
        f_dep="$(patchelf --print-needed "$pkg_dir/fs.so" | grep flang_rt || true)"
      else
        f_dep="$(otool -L "$pkg_dir/fs.so" | grep flang_rt || true)"
      fi
      if [ -n "$f_dep" ]; then
        echo "error: a Fortran package compiled with the bundle needs a shared flang runtime: $f_dep" >&2
        exit 1
      fi
      (cd "$pkg_dir" && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
        "$R_BIN" --vanilla --no-echo -e 'dyn.load("fs.so"); stopifnot(.Fortran("fsum", 3L, c(1, 2, 3), s = 0)$s == 6, .Fortran("fw", 42L, r = 0L)$r == 42L)')
      echo "== compiled package verified: static flang runtime, loads (Fortran)"
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
    echo "== compiled package rpath check skipped (no zig on PATH)"
  fi
fi
