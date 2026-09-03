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
# Usage: scripts/prefix-list-packages.sh <channel> <subdir>
#   scripts/prefix-list-packages.sh universe linux-64
set -euo pipefail

CHANNEL="${1:?usage: $0 <channel> <subdir>}"
SUBDIR="${2:?usage: $0 <channel> <subdir>}"

CRED_FILE="$HOME/.rattler/credentials.json"
TOKEN=""
if [ -f "$CRED_FILE" ]; then
  TOKEN="$(python3 -c "
import json
d = json.load(open('$CRED_FILE'))
for k, v in d.items():
    if k.endswith('prefix.dev') and 'BearerToken' in v:
        print(v['BearerToken'])
        break
" 2>/dev/null || true)"
fi

AUTH_ARGS=()
if [ -n "$TOKEN" ]; then
  AUTH_ARGS=(-H "Authorization: Bearer $TOKEN")
fi

curl -sL "${AUTH_ARGS[@]}" "https://prefix.dev/$CHANNEL/$SUBDIR/repodata.json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
pkgs = {}
pkgs.update(data.get('packages', {}))
pkgs.update(data.get('packages.conda', {}))
if not pkgs:
    print('(no packages found — check channel/subdir spelling, or that this account has read access)', file=sys.stderr)
    sys.exit(1)
for name, info in sorted(pkgs.items(), key=lambda kv: kv[1].get('timestamp', 0)):
    print(name)
print(f'total: {len(pkgs)}', file=sys.stderr)
"
