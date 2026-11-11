#!/usr/bin/env bash
# Upstream zig, to build and test R with it (feat-no-host-paths F4): R
# builds with conda-forge's zig (the env's) and with upstream zig. This
# fetches PyPI's ziglang 0.17.1 wheel for this machine, which carries the
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
# The toolchain build installs this zig into the toolchain tree's zig/,
# the compilers group's (feat-standalone-toolchain B4, phase 5;
# zig-toolchain.sh), and its SOURCES from the marker below: the wheel's
# URL and sha256 and the source its zig is built from.
unset ZIG_BIN
. "$(dirname "$0")/env.sh"

version=0.17.1
src_url=https://ziglang.org/download/$version/zig-$version.tar.xz
src_sha=1e89bf06610b769a8c77676c6c8d54b093a0db60f4891f2f91014829012f0e24
case "$PLAT" in
  linux-64)
    path=59/e3/2a34676370a11c36b7cd04ffb2439c1089c0530cf4b01408c77cf7f8d9c3
    whl=ziglang-0.17.1-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.musllinux_1_1_x86_64.whl
    sha=ea6cc5d87b033cf0aedfbc8f9549a908cae6c50ac31f1698188fa48a74524b54 ;;
  linux-aarch64)
    path=91/72/bb7c4f098ba3e535fa2ebefd9f26327ba63fb0672562959255cb5dd37aff
    whl=ziglang-0.17.1-py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64.musllinux_1_1_aarch64.whl
    sha=b7c5f02fccd40f89b999ee16a1f5ddced56e6182370f8affe494bcf8a28cf07e ;;
  osx-arm64)
    path=ea/e1/4a9a97324fcf2d292c14a2e0121ea0df86c01d0c307ea24fa35aebaccd15
    whl=ziglang-0.17.1-py3-none-macosx_13_0_arm64.whl
    sha=09953b6af7f64168b915180a42774f520f92d86ef6331b28e33915c7e1f0bb23 ;;
  osx-64)
    path=17/f6/f4dfc8cf0e510980fda251a8edf99823b9446f5d7a2a6a24801e55e09c28
    whl=ziglang-0.17.1-py3-none-macosx_13_0_x86_64.whl
    sha=4e0b4b9c02b8d0d220e9948010f860b62ff11d96abb39762eca5fa2ef3f7bc97 ;;
  win-64)
    path=c8/6c/2013114fa780f0cf490cdc98bdd5bf7dce706a5dbd86e50ec4132cf7d4b1
    whl=ziglang-0.17.1-py3-none-win_amd64.whl
    sha=69c3dfc3aff6a297ec4017aa904782c0e450eb988982d7f675d83edce27526fb ;;
  win-arm64)
    path=70/34/a1d775ceaf325b08c3aca909865e057919d0fe1355e2b59081500ef230a1
    whl=ziglang-0.17.1-py3-none-win_arm64.whl
    sha=27a8da5f8eaa0e76ebbc7c2594130ed4646c1101ada2ce0aa86fe580c74154b9 ;;
  *)
    echo "error: no ziglang $version wheel pinned for $PLAT" >&2
    exit 1 ;;
esac

dir="$BUILD_DIR/zig-upstream/ziglang-$version-$PLAT"
zig="$dir/ziglang/zig"
[ "$OS" = windows ] && zig="$zig.exe"
# The marker is written last and says where the wheel came from
# (zigbuild/toolchain/wheel.zig parseMarker reads it): an empty one, as
# fetch-zig wrote before phase 5, fetches again.
if ! [ -s "$dir/.complete" ] || ! [ -f "$zig" ]; then
  mkdir -p "$BUILD_DIR/zig-upstream"
  file="$BUILD_DIR/zig-upstream/$whl"
  url="https://files.pythonhosted.org/packages/$path/$whl"
  echo "fetch-zig: downloading $whl" >&2
  curl -fsSL --retry 3 -o "$file" "$url"
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
  printf 'url: %s\nsha256: %s\nsource: %s sha256:%s\n' "$url" "$sha" "$src_url" "$src_sha" > "$dir/.complete"
fi
v="$("$zig" version)"
[ "$v" = "$version" ] || { echo "error: $zig says $v, not $version" >&2; exit 1; }
echo "fetch-zig: upstream zig $v (PyPI ziglang, sha256 checked)" >&2
if [ "$OS" = windows ]; then cygpath -m "$zig"; else echo "$zig"; fi
