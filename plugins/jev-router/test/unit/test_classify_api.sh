#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$DIR/../../scripts/classify.sh"
CONFIG="$DIR/../../config/config.json"
export PATH="$DIR/fixtures/mock-bin:$PATH"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

ENABLED_CONFIG="$TMP/enabled.json"
jq '.enabled = true' "$CONFIG" > "$ENABLED_CONFIG"
export TYPESAFE_API_KEY="test-key"

# 1. High-confidence lightweight choice -> routed via jev, no forced override
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.93},"high_stakes":{"noul":0.02}}}'
unset MOCK_CURL_EXIT
OUT="$("$CLASSIFY" --agent claude-code --description "fix a typo in a comment" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "lightweight" ]] || fail "expected lightweight tier"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-haiku-4-5-20251001" ]] || fail "expected haiku model"
[[ "$(echo "$OUT" | jq -r '.reason')" == "jev" ]] || fail "expected reason=jev"

# 2. Low confidence -> falls back to standard
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"advanced","confidence":0.4},"high_stakes":{"noul":0.1}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "something ambiguous" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "standard" ]] || fail "expected standard fallback on low confidence"
[[ "$(echo "$OUT" | jq -r '.reason')" == "low-confidence" ]] || fail "expected reason=low-confidence"

# 3. High noul probability forces advanced even with high-confidence lightweight choice
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.9},"high_stakes":{"noul":0.8}}}'
OUT="$("$CLASSIFY" --agent codex --description "looks simple but touches billing" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "expected advanced on high noul"
[[ "$(echo "$OUT" | jq -r '.reason')" == "high-stakes" ]] || fail "expected reason=high-stakes"
[[ "$(echo "$OUT" | jq -r '.model')" == "gpt-5.6-sol" ]] || fail "expected codex advanced model"

# 4. API failure -> fail safe to standard, never crash
export MOCK_CURL_EXIT=1
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "standard" ]] || fail "expected standard fallback on api failure"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "expected reason=api-unavailable"
unset MOCK_CURL_EXIT

# 5. Missing API key -> fail safe to standard without calling curl
unset TYPESAFE_API_KEY
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "expected reason=api-unavailable when key missing"

echo "PASS test_classify_api.sh"
