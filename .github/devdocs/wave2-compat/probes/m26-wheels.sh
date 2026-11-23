#!/usr/bin/env bash
# M-26: pip and uv installs, upgrades and reinstalls of the wheels
# (make-wheel.py with --build-tag 1 into W1, --build-tag 2 into W2).
# Usage: m26-wheels.sh <python> <W1> <W2> <workdir>; uv from `pixi exec`.
set -u
PY="$1"; W1="$2"; W2="$3"; D="$4"
rm -rf "$D"; mkdir -p "$D"
uv() { env -u VIRTUAL_ENV ~/.pixi/bin/pixi exec --spec uv uv "$@"; }
r_ok() { # <venv> <label>: R runs, and a C++ SHLIB when the compilers are in
  local v="$1" lab="$2" out
  out="$("$v/bin/Rscript" -e 'cat(R.version$minor)' 2>&1)" && echo "CHECK $lab rscript: ok ($out)" || echo "CHECK $lab rscript: FAIL $out"
  if [ "${3:-}" = cxx ]; then
    local t; t="$(mktemp -d)"
    printf '#include <string>\n#include <stdexcept>\nextern "C" int f(){ try { throw std::runtime_error("x"); } catch (const std::exception& e) { return std::string(e.what()).size(); } }\n' > "$t/a.cpp"
    out="$(cd "$t" && PATH="$v/bin:/usr/bin:/bin" "$v/bin/R" CMD SHLIB a.cpp 2>&1)" && [ -f "$t/a.so" ] \
      && echo "CHECK $lab cxx-shlib: ok" || echo "CHECK $lab cxx-shlib: FAIL $(echo "$out" | tail -n 3)"
    out="$(PATH="$v/bin:/usr/bin:/bin" "$v/bin/R" CMD config MAKE 2>&1; ls "$v"/lib/python*/site-packages/r_zig/R/lib/R/bin/toolchain/usr/bin/make 2>&1)"
    echo "CHECK $lab make: $(echo "$out" | tr '\n' ' ')"
  fi
}
w() { ls "$1"/"$2"-*.whl; }

echo "== pip"
"$PY" -m venv "$D/pip" && P="$D/pip/bin/python -m pip"
$P install -q --upgrade pip > /dev/null 2>&1; echo "pip $($P --version | cut -d' ' -f2)"
echo "-- pip install r-zig (tag 1)"; $P install "$(w "$W1" r_zig)" 2>&1 | tail -n 1; r_ok "$D/pip" pip-base
echo "-- pip install --upgrade r-zig, tag 2 offered (same version)"
$P install --upgrade --no-index --find-links "$W2" r-zig 2>&1 | tail -n 1
echo "-- pip install <tag 2 wheel file> (same version)"; $P install "$(w "$W2" r_zig)" 2>&1 | tail -n 1
$P show -f r-zig 2>/dev/null | grep -m1 -E 'WHEEL|^Version'; grep -h '^Build' "$D"/pip/lib/python*/site-packages/r_zig-*.dist-info/WHEEL
echo "-- pip install r-zig-toolchain (groups + ziglang from PyPI)"
$P install --find-links "$W1" r-zig-toolchain==4.6.2 2>&1 | tail -n 1; r_ok "$D/pip" pip-toolchain cxx
echo "-- pip install --force-reinstall --no-deps r-zig (tag 2) with the groups installed"
$P install --force-reinstall --no-deps "$(w "$W2" r_zig)" 2>&1 | tail -n 1; r_ok "$D/pip" pip-reinstall-base cxx
$P check 2>&1 | tail -n 2
echo "-- pip uninstall the groups"; $P uninstall -y r-zig-toolchain r-zig-compilers r-zig-build-tools 2>&1 | tail -n 1
r_ok "$D/pip" pip-groups-removed
echo "   leftovers under bin/toolchain: $(ls "$D"/pip/lib/python*/site-packages/r_zig/R/lib/R/bin/toolchain | tr '\n' ' ')"
echo "-- pip uninstall r-zig"; $P uninstall -y r-zig 2>&1 | tail -n 1
echo "   leftovers: $(find "$D"/pip/lib/python*/site-packages/r_zig 2>/dev/null | head -n 5 | tr '\n' ' ')"

echo "== uv ($(uv --version))"
uv venv -q -p "$PY" "$D/uv"; export VIRTUAL_ENV="$D/uv"
U() { env VIRTUAL_ENV="$D/uv" ~/.pixi/bin/pixi exec --spec uv uv pip "$@"; }
echo "-- uv pip install r-zig (tag 1)"; U install --python "$D/uv/bin/python" "$(w "$W1" r_zig)" 2>&1 | tail -n 2; r_ok "$D/uv" uv-base
echo "   exec bits: $(stat -c '%A %n' "$D"/uv/lib/python*/site-packages/r_zig/R/lib/R/bin/exec/R "$D"/uv/bin/R 2>&1 | tr '\n' ' ')"
echo "-- uv pip install --upgrade r-zig, tag 2 offered"
U install --python "$D/uv/bin/python" --upgrade --no-index --find-links "$W2" r-zig 2>&1 | tail -n 2
echo "-- uv pip install r-zig-toolchain (find-links W1, PyPI for ziglang)"
U install --python "$D/uv/bin/python" --find-links "$W1" r-zig-toolchain==4.6.2 2>&1 | tail -n 2; r_ok "$D/uv" uv-toolchain cxx
echo "-- uv pip install --reinstall-package r-zig (tag 2 file) with the groups installed"
U install --python "$D/uv/bin/python" --reinstall-package r-zig --no-deps "$(w "$W2" r_zig)" 2>&1 | tail -n 2; r_ok "$D/uv" uv-reinstall-base cxx
echo "-- uv pip uninstall the groups, then r-zig"
U uninstall --python "$D/uv/bin/python" r-zig-toolchain r-zig-compilers r-zig-build-tools 2>&1 | tail -n 1; r_ok "$D/uv" uv-groups-removed
U uninstall --python "$D/uv/bin/python" r-zig 2>&1 | tail -n 1
echo "   leftovers: $(find "$D"/uv/lib/python*/site-packages/r_zig 2>/dev/null | head -n 5 | tr '\n' ' ')"
