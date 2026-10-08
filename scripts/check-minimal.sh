#!/usr/bin/env bash
# minimal's packages in pixi.lock, on each of its platforms, against the
# names scripts/minimal-deny.txt forbids. It reads the lock only (pixi
# list --frozen --no-install): nothing is solved or installed, so one
# machine checks all four platforms. Run it after every change to
# pixi.lock; CI runs it on the minimal legs.
set -euo pipefail
cd "${PIXI_PROJECT_ROOT:?run through pixi run}"
pixi="${PIXI_EXE:-pixi}"
deny="$(grep -v -e '^#' -e '^$' scripts/minimal-deny.txt)"
bad=0
for p in linux-64 linux-aarch64 osx-64 osx-arm64; do
  names="$("$pixi" list -e minimal --platform "$p" --frozen --no-install --json |
    sed -n 's/^ *"name": "\(.*\)",$/\1/p')"
  [ -n "$names" ] || { echo "error: read no minimal packages for $p from pixi.lock" >&2; exit 1; }
  hit="$(printf '%s\n' "$names" | grep -x -E -f <(printf '%s\n' "$deny") || true)"
  if [ -n "$hit" ]; then
    echo "error: minimal ($p) has packages it must not have: $(printf '%s\n' "$hit" | tr '\n' ' ')" >&2
    bad=1
  else
    echo "== minimal ($p): $(printf '%s\n' "$names" | wc -l | tr -d ' ') packages, none on the deny-list"
  fi
done
exit "$bad"
