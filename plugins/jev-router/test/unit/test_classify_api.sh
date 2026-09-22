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
export TYPESAFE_API_KEY="test-key"

# 6. Unrecognized tier from the API -> fail safe to standard, never model:"null"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"medium","confidence":0.95},"high_stakes":{"noul":0.01}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "standard" ]] || fail "unrecognized tier must fall back to standard"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "unrecognized tier must report api-unavailable"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-sonnet-5" ]] || fail "unrecognized tier must resolve a real model, got $OUT"

# 7. Non-numeric confidence on the high-stakes branch must not crash
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":"high"},"high_stakes":{"noul":0.8}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")" \
  || fail "non-numeric confidence must not make classify.sh exit non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "non-numeric confidence must still yield valid JSON, got: $OUT"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "high noul must still force advanced, got $OUT"
[[ "$(echo "$OUT" | jq -r '.confidence')" == "0" ]] || fail "non-numeric confidence must degrade to 0, got $OUT"

# 7b. Non-numeric noul must not crash either
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"standard","confidence":0.9},"high_stakes":{"noul":"likely"}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")" \
  || fail "non-numeric noul must not make classify.sh exit non-zero"
[[ "$(echo "$OUT" | jq -r '.tier')" == "standard" ]] || fail "non-numeric noul must degrade to 0, got $OUT"
[[ "$(echo "$OUT" | jq -r '.reason')" == "jev" ]] || fail "non-numeric noul case reason mismatch, got $OUT"

# 8. stdout is exactly one line on a success path
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.93},"high_stakes":{"noul":0.02}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "fix a typo in a comment" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" == "1" ]] || fail "jev success output must be one line"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.9},"high_stakes":{"noul":0.8}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" == "1" ]] || fail "high-stakes output must be one line"

# 9. A hostile override cannot raise high_stakes_probability_threshold or
#    lower confidence_threshold past the global values.
HOSTILE_DIR="$TMP/hostile"
mkdir -p "$HOSTILE_DIR"
printf '%s' '{"high_stakes_probability_threshold": 0.99, "confidence_threshold": 0.01}' \
  > "$HOSTILE_DIR/.jev-router.json"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.95},"high_stakes":{"noul":0.6}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$HOSTILE_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "high-stakes" ]] || fail "override must not raise high_stakes threshold, got $OUT"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"advanced","confidence":0.4},"high_stakes":{"noul":0.1}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$HOSTILE_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "low-confidence" ]] || fail "override must not lower confidence_threshold, got $OUT"

# 9b. An override may still tighten the floor in the safe direction.
TIGHT_DIR="$TMP/tight"
mkdir -p "$TIGHT_DIR"
printf '%s' '{"high_stakes_probability_threshold": 0.2}' > "$TIGHT_DIR/.jev-router.json"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.95},"high_stakes":{"noul":0.3}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TIGHT_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "high-stakes" ]] || fail "override must be able to lower high_stakes threshold, got $OUT"

echo "PASS test_classify_api.sh"
