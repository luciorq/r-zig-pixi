#!/usr/bin/env bash
# Turn the staged install in $PREFIX into a self-contained standalone
# bundle and tar it up:
#   - vendor every conda-env shared library into <prefix>/lib (the same
#     location the dual rpaths from stage.sh already search — in a conda
#     env the solver provides these, standalone we copy them)
#   - vendor runtime data the libs need (fontconfig config)
#   - emit dist/R-<ver>-<flavor>-<platform>.tar.gz + sha256
# Linux, macOS, and Windows all implemented.
. "$(dirname "$0")/env.sh"

test -d "$R_HOME_DIR" || { echo "error: run 'pixi run install' first" >&2; exit 1; }
CONDA="${CONDA_PREFIX:?}"

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
  (cd "$ROOT/dist" && rm -f "$artifact" && zip -qr "$artifact" "R-$R_VERSION-$FLAVOR")
  sha256sum "$artifact" | sed "s|\\\\||; s|$ROOT/dist/||" > "$artifact.sha256"
  echo "== done: $(du -h "$artifact" | cut -f1)"
  exit 0
fi

if [ "$OS" != linux ] && [ "$OS" != macos ]; then
  echo "package-standalone: only implemented for Linux, macOS and Windows so far" >&2
  exit 1
fi

echo "== bundling dependencies into $PREFIX/lib"
if [ "$OS" = linux ]; then
  # ELF-magic scan (not name patterns): must also catch the tools bundled
  # into bin/toolchain by stage.sh (nm/dd/realpath/grep — needed by
  # libtool/javareconf), whose own conda-lib deps (libzstd, libpcre2-8,
  # libgcc_s, ...) need vendoring exactly like R's own binaries.
  elfs=()
  while read -r f; do
    head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' && elfs+=("$f")
  done < <(find "$R_HOME_DIR" -type f)
  n_copied=0
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for f in "${elfs[@]}"; do
      while read -r dep; do
        base="$(basename "$dep")"
        if [ ! -f "$PREFIX/lib/$base" ]; then
          cp -L "$dep" "$PREFIX/lib/$base"
          patchelf --set-rpath '$ORIGIN' "$PREFIX/lib/$base" 2>/dev/null || true
          n_copied=$((n_copied + 1))
          elfs+=("$PREFIX/lib/$base")
          changed=1
        fi
      done < <(LD_LIBRARY_PATH="$CONDA/lib" ldd "$f" 2>/dev/null | awk -v p="$CONDA" '$3 ~ "^"p {print $3}')
    done
  done
  echo "   vendored $n_copied conda libraries"
else
  # macOS: conda-forge dylibs record deps as bare "@rpath/<name>" — no
  # absolute path to match against like ldd gives us, so resolve each
  # @rpath/<name> against $CONDA/lib ourselves (that's the only place
  # these came from; R's own libR.dylib/libRblas.dylib are bare names,
  # already present in R_HOME/lib, and never need vendoring). Same
  # Mach-O-magic scan + fixed-point loop shape as the Linux ELF walk,
  # so newly-vendored tools' own deps (bin/toolchain/nm etc.) get caught.
  machos=()
  while read -r f; do
    head -c4 "$f" 2>/dev/null | grep -q $'\xcf\xfa\xed\xfe' && machos+=("$f")
  done < <(find "$R_HOME_DIR" -type f)
  n_copied=0
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for f in "${machos[@]}"; do
      while read -r dep; do
        base="${dep#@rpath/}"
        [ -f "$CONDA/lib/$base" ] || continue
        if [ ! -f "$PREFIX/lib/$base" ]; then
          cp -L "$CONDA/lib/$base" "$PREFIX/lib/$base"
          # @loader_path (no traversal — the file lives in $PREFIX/lib
          # itself) lets it resolve its own @rpath/ peers once vendored.
          install_name_tool -add_rpath "@loader_path" "$PREFIX/lib/$base" 2>/dev/null || true
          codesign --force --sign - "$PREFIX/lib/$base" 2>/dev/null || true
          n_copied=$((n_copied + 1))
          machos+=("$PREFIX/lib/$base")
          changed=1
        fi
      done < <(otool -L "$f" 2>/dev/null | awk '/@rpath\// {print $1}')
    done
  done
  echo "   vendored $n_copied conda libraries"
fi

if [ -d "$CONDA/etc/fonts" ] && [ ! -d "$PREFIX/etc/fonts" ]; then
  mkdir -p "$PREFIX/etc"
  cp -a "$CONDA/etc/fonts" "$PREFIX/etc/fonts"
  echo "   vendored fontconfig configuration"
fi

# Standalone has no env: strip the build-env include/lib flags that
# stage.sh keeps for conda-package use.
sed -i \
  -e "s|-I$CONDA/include||g" \
  -e "s|-L$CONDA/lib||g" \
  -e "s|-Wl,-rpath,$CONDA/lib||g" \
  "$R_HOME_DIR/etc/Makeconf"

if [ "$OS" = macos ]; then
  case "$(uname -m)" in
    arm64) plat=osx-arm64 ;;
    x86_64) plat=osx-64 ;;
    *) plat="osx-$(uname -m)" ;;
  esac
  artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.tar.gz"
  echo "== creating $artifact"
  tar -czf "$artifact" -C "$ROOT/dist" "R-$R_VERSION-$FLAVOR"
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
tar -czf "$artifact" -C "$ROOT/dist" "R-$R_VERSION-$FLAVOR"
sha256sum "$artifact" | sed "s|$ROOT/dist/||" > "$artifact.sha256"
echo "== done: $(du -h "$artifact" | cut -f1) $(cat "$artifact.sha256")"
