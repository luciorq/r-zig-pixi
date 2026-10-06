#!/usr/bin/env bash
# Upstream zig, to build and test R with it (feat-no-host-paths F4): R
# builds with conda-forge's zig (the env's) and with upstream zig. This
# fetches PyPI's ziglang 0.16.0 wheel for this machine, which carries the
# ziglang.org release (its zig and lib/ byte-identical to the official
# archive's, compared 2026-10-04), checks the sha256 pinned below, unpacks
# it once under build/zig-upstream/ and prints its zig's path, so that
#   ZIG_BIN="$(pixi run fetch-zig)" pixi run build
# and the other pipeline tasks that run zig (check, rzig-test, contract,
# verify-package; see scripts/env.sh) build and test with it. A
# wheel is a zip: no Python or pip, nothing added to the env, and one
# format and one tool (the env's unzip) on every OS. On Windows the path
# is printed as C:/..., which MSYS bash and rzig both take. Messages go
# to stderr; standard output is the path alone. It runs no zig, so it
# drops ZIG_BIN: env.sh stops on one that names no zig, as one still
# exported after `rm -rf build` does, and this is what makes it again.
unset ZIG_BIN
. "$(dirname "$0")/env.sh"

version=0.16.0
# https://pypi.org/project/ziglang/0.16.0/#files: per platform, the
# wheel's directory on files.pythonhosted.org, its file name and sha256.
case "$OS-$(uname -m)" in
  linux-x86_64)
    plat=linux-64
    path=3e/ed/7b79023aa27ceb5d461ecf761181e7c33c57bbc1a6256a39535d1c7083d2
    whl=ziglang-0.16.0-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64.whl
    sha=9fcda73f62b851dd72a54b710ad40a209896db14cfb13649e62191243556342b ;;
  linux-aarch64)
    plat=linux-aarch64
    path=7e/ed/d6663a5e52c504944d578b9e0bfcb7857f292803bcd09ebe0d10fe2b293d
    whl=ziglang-0.16.0-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.musllinux_1_1_aarch64.whl
    sha=e27d409812b11e0fb89ed0200cf2e55b6464d43f9461553104e4a4f9a94a1fd5 ;;
  macos-arm64)
    plat=osx-arm64
    path=cd/59/012f0c2800f7428b87bb16c5c78db7ef806efed274491998155955c02558
    whl=ziglang-0.16.0-py3-none-macosx_12_0_arm64.whl
    sha=b61e5413c49508d9d62e5dcea543e3af491594154d74a00ff52f84ed508260cc ;;
  macos-x86_64)
    plat=osx-64
    path=75/60/f924aa24b95a1ad347e845acc7ab6b5d062ae5b0b540d494654cd40d4e0b
    whl=ziglang-0.16.0-py3-none-macosx_12_0_x86_64.whl
    sha=18e14f6b25678d7b7c65708c82501ee6090fe39ed5c783477d56267af1fa5629 ;;
  windows-x86_64)
    plat=win-64
    path=a6/3c/baff40b3fc8ab4e83530246a52e8f3a5186c3606562712dfb58483b04f79
    whl=ziglang-0.16.0-py3-none-win_amd64.whl
    sha=089a16a4eb5a2f45151993342f8fabad24ff1a0723dc146642895c29208a3939 ;;
  *)
    echo "error: no ziglang $version wheel pinned for $OS $(uname -m)" >&2
    exit 1 ;;
esac

dir="$BUILD_DIR/zig-upstream/ziglang-$version-$plat"
zig="$dir/ziglang/zig"
[ "$OS" = windows ] && zig="$zig.exe"
if ! [ -f "$dir/.complete" ] || ! [ -f "$zig" ]; then
  mkdir -p "$BUILD_DIR/zig-upstream"
  file="$BUILD_DIR/zig-upstream/$whl"
  echo "fetch-zig: downloading $whl" >&2
  curl -fsSL --retry 3 -o "$file" "https://files.pythonhosted.org/packages/$path/$whl"
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  # (msys sha256sum prefixes the line with '\' for a path with backslashes)
  actual="${actual#\\}"
  if [ "$actual" != "$sha" ]; then
    rm -f "$file"
    echo "error: $whl has sha256 $actual, not the pinned $sha" >&2
    exit 1
  fi
  rm -rf "$dir"
  unzip -q "$file" -d "$dir" >&2
  rm -f "$file"
  : > "$dir/.complete"
fi
v="$("$zig" version)"
[ "$v" = "$version" ] || { echo "error: $zig says $v, not $version" >&2; exit 1; }
echo "fetch-zig: upstream zig $v (PyPI ziglang, sha256 checked)" >&2
if [ "$OS" = windows ]; then cygpath -m "$zig"; else echo "$zig"; fi
