#!/usr/bin/env bash
# Permanently delete one or more package files from a prefix.dev
# channel, via the real (undocumented-in-the-UI-by-design) delete API —
# prefix.dev's dashboard deliberately has no delete button to discourage
# casual deletion, but the underlying REST endpoint still exists and is
# documented at https://prefix.dev/docs/prefix/api:
#   DELETE /api/v1/delete/:channel/:subdir/:package_file_name
#
# This is real, permanent, irreversible package deletion — treat it with
# the same care as any destructive/hard-to-reverse action. Defaults to a
# dry run; pass --yes to actually delete anything.
#
# Auth: requires PREFIX_API_KEY, a prefix.dev API key with Read/write/
# delete scope on the target channel (Account Settings → API Keys on
# prefix.dev's own site — the exact page isn't independently verified
# here, prefix.dev's own docs are the source of truth). Deliberately
# NOT falling back to whatever `rattler-build auth login` already stored
# in ~/.rattler/credentials.json: that token's format (a bare opaque
# BearerToken, not the pfx_-prefixed shape the API docs show for API
# keys) strongly suggests it's a different credential type scoped for
# uploads, not channel administration — reusing it here without
# confirming its actual delete-scope would risk either a confusing
# failure or, worse, succeeding on a broader token than intended.
#
# Usage:
#   scripts/prefix-delete-package.sh [--yes] <channel> <subdir> <package_file_name> [<package_file_name> ...]
#
# Example (dry run, lists what would happen, deletes nothing):
#   scripts/prefix-delete-package.sh universe linux-64 r-zig-slim-4.6.1-hb0f4dca_0.conda
#
# Example (real deletion):
#   PREFIX_API_KEY=pfx_... scripts/prefix-delete-package.sh --yes universe linux-64 r-zig-slim-4.6.1-hb0f4dca_0.conda
set -euo pipefail

DRY_RUN=true
CHANNEL=""
SUBDIR=""
FILES=()

for arg in "$@"; do
  case "$arg" in
    --yes) DRY_RUN=false ;;
    -h|--help)
      sed -n '2,29p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$CHANNEL" ]; then
        CHANNEL="$arg"
      elif [ -z "$SUBDIR" ]; then
        SUBDIR="$arg"
      else
        FILES+=("$arg")
      fi
      ;;
  esac
done

if [ -z "$CHANNEL" ] || [ -z "$SUBDIR" ] || [ "${#FILES[@]}" -eq 0 ]; then
  echo "usage: $0 [--yes] <channel> <subdir> <package_file_name> [<package_file_name> ...]" >&2
  exit 1
fi

echo "Channel: $CHANNEL"
echo "Subdir:  $SUBDIR"
echo "Packages to delete (${#FILES[@]}):"
for f in "${FILES[@]}"; do
  echo "  - $f"
done

if $DRY_RUN; then
  echo
  echo "DRY RUN — nothing deleted, no API calls made. Re-run with --yes to actually delete."
  exit 0
fi

if [ -z "${PREFIX_API_KEY:-}" ]; then
  echo "error: set PREFIX_API_KEY to a prefix.dev API key with Read/write/delete scope on $CHANNEL (see this script's own header comment)" >&2
  exit 1
fi

echo
RESP_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE"' EXIT
for f in "${FILES[@]}"; do
  echo -n "Deleting $f ... "
  code="$(curl -s -o "$RESP_FILE" -w '%{http_code}' \
    -X DELETE \
    -H "Authorization: Bearer $PREFIX_API_KEY" \
    "https://prefix.dev/api/v1/delete/$CHANNEL/$SUBDIR/$f")"
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    echo "OK ($code)"
  else
    echo "FAILED ($code)" >&2
    cat "$RESP_FILE" >&2
    exit 1
  fi
done

echo
echo -n "Reindexing $CHANNEL/$SUBDIR ... "
code="$(curl -s -o "$RESP_FILE" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $PREFIX_API_KEY" \
  "https://prefix.dev/api/v1/reindex/$CHANNEL/$SUBDIR")"
if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
  echo "OK ($code)"
else
  echo "FAILED ($code) — deletion(s) above still succeeded; repodata.json may lag until a reindex happens some other way" >&2
  cat "$RESP_FILE" >&2
fi

echo
echo "Done. Verify with: scripts/prefix-list-packages.sh $CHANNEL $SUBDIR"
