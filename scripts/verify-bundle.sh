#!/usr/bin/env bash
# Extract the packaged standalone bundle to a fresh location and run it
# with the pixi/conda env off PATH — the same adversarial check done
# manually on omicron/kappa for every relocation fix this project has
# shipped, automated so CI catches a regression instead of relying on a
# human to re-run it. Windows binaries derive R_HOME natively (no PATH
# tricks needed there, per stage.sh); unix binaries get a scrubbed PATH
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
# 2.17 floor — and does. The compile-time helper tools stage.sh vendors
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
