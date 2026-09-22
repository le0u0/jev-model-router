#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOGGLE="$DIR/../../scripts/toggle.sh"
CONFIG="$DIR/../../config/config.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

WORK_CONFIG="$TMP/config.json"
cp "$CONFIG" "$WORK_CONFIG"

OUT="$(JEV_ROUTER_CONFIG="$WORK_CONFIG" "$TOGGLE" on)"
[[ "$OUT" == "jev-router: enabled=true" ]] || fail "on output mismatch: $OUT"
[[ "$(jq -r '.enabled' "$WORK_CONFIG")" == "true" ]] || fail "config not flipped to true"

OUT="$(JEV_ROUTER_CONFIG="$WORK_CONFIG" "$TOGGLE" off)"
[[ "$OUT" == "jev-router: enabled=false" ]] || fail "off output mismatch: $OUT"
[[ "$(jq -r '.enabled' "$WORK_CONFIG")" == "false" ]] || fail "config not flipped to false"

echo "PASS test_toggle.sh"
