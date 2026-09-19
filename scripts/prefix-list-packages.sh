#!/usr/bin/env bash
# List every package file currently on a prefix.dev channel subdir —
# neither `rattler-build` nor `pixi` has a CLI subcommand for this
# (`rattler-build upload`/`pixi upload` only upload; `pixi search` only
# returns the single latest match per name). Fetches the real
# repodata.json directly instead — the same file any conda client reads
# to resolve packages, a plain authenticated GET, not a channel-admin
# operation (no API key needed beyond whatever `rattler-build auth
# login` already stored, which IS sufficient for this — unlike deletion,
# see prefix-delete-package.sh's own comment on that distinction).
#
# An EMPTY subdir is success (prints nothing, "total: 0" on stderr,
# exit 0) — it's the documented post-deletion verification state
# (CHANNEL_CLEANUP.md), not an error. Errors (HTTP failure, bad JSON)
# exit non-zero with the real cause.
#
# Usage: scripts/prefix-list-packages.sh <channel> <subdir>
#   scripts/prefix-list-packages.sh universe linux-64
set -euo pipefail

CHANNEL="${1:?usage: $0 <channel> <subdir>}"
SUBDIR="${2:?usage: $0 <channel> <subdir>}"

# Token extraction: path passed via env (never interpolated into python
# source — an apostrophe in $HOME would break the generated literal),
# and failures WARN instead of being silently swallowed: a parse failure
# here would otherwise degrade to an unauthenticated request whose
# eventual failure misdirects to channel-spelling/permissions instead of
# the real, local cause.
TOKEN=""
if [ -f "$HOME/.rattler/credentials.json" ]; then
  TOKEN="$(CRED_FILE="$HOME/.rattler/credentials.json" python3 -c "
import json, os
d = json.load(open(os.environ['CRED_FILE']))
for k, v in d.items():
    if k.endswith('prefix.dev') and isinstance(v, dict) and 'BearerToken' in v:
        print(v['BearerToken'])
        break
")" || {
    echo "warning: failed to parse ~/.rattler/credentials.json — proceeding unauthenticated (private channels will look empty/404)" >&2
    TOKEN=""
  }
fi

AUTH_ARGS=()
if [ -n "$TOKEN" ]; then
  AUTH_ARGS=(-H "Authorization: Bearer $TOKEN")
fi

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
HTTP_CODE="$(curl -sL -o "$BODY_FILE" -w '%{http_code}' "${AUTH_ARGS[@]}" \
  "https://prefix.dev/$CHANNEL/$SUBDIR/repodata.json")"
if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "error: GET $CHANNEL/$SUBDIR/repodata.json returned HTTP $HTTP_CODE — check channel/subdir spelling and access" >&2
  exit 1
fi

REPODATA_FILE="$BODY_FILE" python3 -c "
import json, os, sys
with open(os.environ['REPODATA_FILE']) as f:
    data = json.load(f)
pkgs = {}
pkgs.update(data.get('packages', {}))
pkgs.update(data.get('packages.conda', {}))
for name, info in sorted(pkgs.items(), key=lambda kv: kv[1].get('timestamp', 0)):
    print(name)
print(f'total: {len(pkgs)}', file=sys.stderr)
"
