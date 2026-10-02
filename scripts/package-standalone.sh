#!/usr/bin/env bash
# Turn the staged install in $PREFIX into a self-contained standalone
# bundle and tar it up:
#   - vendor every conda-env shared library into <prefix>/lib
#     (vendor-libs.sh; the relative rpaths build.zig writes search there,
#     and in a conda env the solver provides them)
#   - vendor runtime data the libs need (fontconfig config)
#   - emit dist/R-<ver>-<flavor>-<platform>.tar.gz + sha256
# Linux, macOS, and Windows all implemented.
. "$(dirname "$0")/env.sh"

test -d "$R_HOME_DIR" || { echo "error: run 'pixi run build' first" >&2; exit 1; }
CONDA="${CONDA_PREFIX:?}"
# Derive the archive's source-directory name from $PREFIX itself rather
# than hardcoding "R-$R_VERSION-$FLAVOR" — the zig-built prefix carries a
# "-zig" suffix ($ROOT/dist/R-$R_VERSION-$FLAVOR-zig, from zig-build.sh's
# own PREFIX_ZIG) precisely so it can coexist with an autoconf/gnuwin32
# build of the same flavor; a hardcoded basename here silently zipped/
# tarred nothing ("zip error: Nothing to do!" / "tar: ...: No such file or
# directory") whenever $PREFIX didn't match it exactly (found via a real
# zig-package run on kappa — previously worked around per-invocation by
# pointing $R_INSTALL_PREFIX at the unsuffixed name; fixed at the source
# instead now that zig-package/zig-verify-package are first-class tasks).
prefix_base="$(basename "$PREFIX")"

if [ "$OS" = windows ]; then
  BIN="$R_HOME_DIR/bin/x64"
  CLIB="$CONDA/Library/bin"

  # Vendor Tcl FIRST so its DLLs participate in the dependency walk
  # (tcl86t.dll needs e.g. zlib1.dll vendored alongside).
  if [ ! -d "$R_HOME_DIR/Tcl" ]; then
    mkdir -p "$R_HOME_DIR/Tcl/bin" "$R_HOME_DIR/Tcl/lib"
    cp "$CLIB"/tcl86t.dll "$CLIB"/tk86t.dll "$R_HOME_DIR/Tcl/bin/"
    cp -a "$CONDA/Library/lib/tcl8.6" "$CONDA/Library/lib/tk8.6" "$R_HOME_DIR/Tcl/lib/"
    echo "   vendored Tcl runtime into $R_HOME_DIR/Tcl"
  fi

  echo "== bundling DLLs into $R_HOME_DIR/bin/x64"
  mapfile -t pes < <(find "$R_HOME_DIR" -type f \( -name '*.dll' -o -name '*.exe' \))
  n_copied=0
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for f in "${pes[@]}"; do
      while read -r dep; do
        case "$dep" in
          # Tcl DLLs live ONLY in R_HOME/Tcl/bin (upstream layout): a
          # copy in bin/x64 wins the search order but then looks for
          # init.tcl relative to itself and fails.
          tcl86t.dll|tk86t.dll) continue ;;
        esac
        if [ -f "$CLIB/$dep" ] && [ ! -f "$BIN/$dep" ]; then
          cp "$CLIB/$dep" "$BIN/$dep"
          n_copied=$((n_copied + 1))
          pes+=("$BIN/$dep")
          changed=1
        fi
      done < <(x86_64-w64-mingw32-objdump -p "$f" 2>/dev/null | awk '/DLL Name:/ {print $3}')
    done
  done
  echo "   vendored $n_copied DLLs"

  # fontconfig config for the cairo device; Renviron.site points at it
  if [ -d "$CONDA/Library/etc/fonts" ] && [ ! -d "$R_HOME_DIR/etc/fonts" ]; then
    cp -a "$CONDA/Library/etc/fonts" "$R_HOME_DIR/etc/fonts"
    echo "FONTCONFIG_PATH=\${R_HOME}/etc/fonts" >> "$R_HOME_DIR/etc/Renviron.site"
    echo "   vendored fontconfig configuration"
  fi

  artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-win-64.zip"
  echo "== creating $artifact"
  (cd "$ROOT/dist" && rm -f "$artifact" && zip -qr "$artifact" "$prefix_base")
  sha256sum "$artifact" | sed "s|\\\\||; s|$ROOT/dist/||" > "$artifact.sha256"
  echo "== done: $(du -h "$artifact" | cut -f1)"
  exit 0
fi

if [ "$OS" != linux ] && [ "$OS" != macos ]; then
  echo "package-standalone: only implemented for Linux, macOS and Windows so far" >&2
  exit 1
fi

# conda's libraries into <prefix>/lib (zig-build.sh already did this
# after the build; again here, idempotent)
bash "$(dirname "$0")/vendor-libs.sh"

if [ -d "$CONDA/etc/fonts" ] && [ ! -d "$PREFIX/etc/fonts" ]; then
  mkdir -p "$PREFIX/etc"
  cp -a "$CONDA/etc/fonts" "$PREFIX/etc/fonts"
  echo "   vendored fontconfig configuration"
fi

# TLS trust. The vendored libcurl and OpenSSL are conda-forge's, built
# with this env's paths compiled in (libcurl's default CA file is
# $CONDA/ssl/cacert.pem, OpenSSL's directory $CONDA/ssl): outside this
# machine every HTTPS request failed with "libcurl error code 77: error
# adding trust anchors from file" (found 2026-09-28; the wheel, built
# from this tree, had the same). Ship the env's Mozilla bundle and set
# R_ZIG_CA_BUNDLE: R's libcurl.c, patched (zigbuild/patches/), then takes
# CURL_CA_BUNDLE if the user set one, else SSL_CERT_FILE, else the
# system's bundle, else this file, and passes it to curl as
# CURLOPT_CAINFO, so the compiled-in path is never used. Not
# CURL_CA_BUNDLE itself: Renviron exports to every program R starts, and
# curl or Python's requests would drop their own trust for this frozen
# copy. Interim fix: the per-platform curl in
# .github/devdocs/feat-no-host-paths/PLAN.md ("libcurl") replaces it.
# etc/Renviron, not Renviron.site: `R --vanilla`/`Rscript --vanilla` imply
# --no-environ, which skips Renviron.site but still reads etc/Renviron.
# Windows needs none of this: conda-forge's curl there uses Schannel,
# the Windows certificate store.
CA_SRC="$CONDA/ssl/cacert.pem"
test -s "$CA_SRC" || { echo "error: $CA_SRC missing (ca-certificates not in the env?)" >&2; exit 1; }
test -f "$R_HOME_DIR/etc/Renviron" || { echo "error: $R_HOME_DIR/etc/Renviron missing (not a staged tree?)" >&2; exit 1; }
install -m 0644 "$CA_SRC" "$R_HOME_DIR/etc/ca-bundle.crt"
if ! grep -q '^R_ZIG_CA_BUNDLE=' "$R_HOME_DIR/etc/Renviron"; then
  {
    echo '## r-zig: fallback trust anchors (read by the patched libcurl.c).'
    echo 'R_ZIG_CA_BUNDLE=${R_HOME}/etc/ca-bundle.crt'
  } >> "$R_HOME_DIR/etc/Renviron"
fi
echo "   vendored CA bundle ($(grep -c 'BEGIN CERTIFICATE' "$R_HOME_DIR/etc/ca-bundle.crt") certificates) as etc/ca-bundle.crt"

# etc/Makeconf needs no edit: build.zig writes it with $(R_HOME)/../..
# for the environment and a bare -lflang_rt.runtime (feat-no-host-paths
# F1.5), right in a conda env and here alike, and fails the build if it
# names a build path.

if [ "$OS" = macos ]; then
  case "$(uname -m)" in
    arm64) plat=osx-arm64 ;;
    x86_64) plat=osx-64 ;;
    *) plat="osx-$(uname -m)" ;;
  esac
  artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.tar.gz"
  echo "== creating $artifact"
  tar -czf "$artifact" -C "$ROOT/dist" "$prefix_base"
  sha256sum "$artifact" | sed "s|$ROOT/dist/||" > "$artifact.sha256"
  echo "== done: $(du -h "$artifact" | cut -f1) $(cat "$artifact.sha256")"
  exit 0
fi

case "$(uname -m)" in
  x86_64) plat=linux-64 ;;
  aarch64) plat=linux-aarch64 ;;
  *) plat="linux-$(uname -m)" ;;
esac
artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.tar.gz"
echo "== creating $artifact"
tar -czf "$artifact" -C "$ROOT/dist" "$prefix_base"
sha256sum "$artifact" | sed "s|$ROOT/dist/||" > "$artifact.sha256"
echo "== done: $(du -h "$artifact" | cut -f1) $(cat "$artifact.sha256")"
