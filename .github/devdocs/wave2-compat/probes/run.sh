#!/usr/bin/env bash
# Host side (delta): one probe in a fresh container.
# Usage: run.sh <mode> <image> <name> [VAR=value ...]
#   mode: conda (needs CHAN=<dir with linux-64/>), standalone (needs
#   DIST=<dir with the base, compilers and build-tools archives>)
# Logs: $OUT/<name>.log
set -u
mode="$1"; image="$2"; name="$3"; shift 3
here="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HOME/rz/scratch/wave2-compat/out}"; mkdir -p "$OUT"
envs=(); for kv in "$@"; do envs+=(-e "$kv"); done
docker run --rm --name "w2c-$name" --cpus 8 \
  -v "$here:/probe:ro" -v "${CHAN:-/dev/null}:/chan:ro" -v "${DIST:-/dev/null}:/dist:ro" \
  "${envs[@]}" "$image" bash /probe/inside.sh "$mode" > "$OUT/$name.log" 2>&1
echo "EXIT=$?" >> "$OUT/$name.log"
grep -E '^(PROBE|== host|EXIT)' "$OUT/$name.log"
