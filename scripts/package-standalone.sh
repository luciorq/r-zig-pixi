#!/usr/bin/env bash
# Archive the installed R tree in $PREFIX, the tree that ships
# (feat-no-host-paths PLAN.md, F1 and F1.7), as
# dist/R-<ver>-<flavor>-<platform>.tar.gz (Windows: .zip) plus its sha256.
# Nothing is added to the tree here, on any OS: zig build installs it with
# the runtime data it needs from the env (build.zig's installEnvRuntime:
# the CA bundle, fontconfig's configuration, Windows' Tcl/Tk), and
# zig-build.sh runs vendor-libs.sh after every build to copy the env's
# shared libraries into it. So the checks that run on the installed tree
# before this (verify-tree, smoke, contract, check, hermetic) saw exactly
# what is archived. vendor-libs.sh is not run again here: one place does
# it, and the pixi task `package` depends on `build`, which runs it.
. "$(dirname "$0")/env.sh"

test -d "$R_HOME_DIR" || { echo "error: no R tree at $PREFIX; run 'pixi run build' first" >&2; exit 1; }
# The archive's top directory is $PREFIX's own name (zig-built prefixes
# carry a "-zig" suffix: dist/R-<ver>-<flavor>-zig), not a name derived
# from the flavor; verify-bundle.sh reads it back the same way.
prefix_base="$(basename "$PREFIX")"
prefix_dir="$(cd "$PREFIX/.." && pwd)"

case "$OS" in
  linux)
    case "$(uname -m)" in
      x86_64) plat=linux-64 ;;
      aarch64) plat=linux-aarch64 ;;
      *) plat="linux-$(uname -m)" ;;
    esac
    ;;
  macos)
    case "$(uname -m)" in
      arm64) plat=osx-arm64 ;;
      x86_64) plat=osx-64 ;;
      *) plat="osx-$(uname -m)" ;;
    esac
    ;;
  windows) plat=win-64 ;;
  *) echo "package-standalone: unsupported OS '$OS'" >&2; exit 1 ;;
esac

if [ "$OS" = windows ]; then ext=zip; else ext=tar.gz; fi
artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.$ext"
echo "== creating $artifact"
mkdir -p "$ROOT/dist"
rm -f "$artifact"
if [ "$ext" = zip ]; then
  (cd "$prefix_dir" && zip -qr "$artifact" "$prefix_base")
else
  tar -czf "$artifact" -C "$prefix_dir" "$prefix_base"
fi
# Named by its basename in the checksum line (sha256sum -c next to it).
(cd "$ROOT/dist" && sha256sum "${artifact##*/}") > "$artifact.sha256"
echo "== done: $(du -h "$artifact" | cut -f1) $(cat "$artifact.sha256")"
