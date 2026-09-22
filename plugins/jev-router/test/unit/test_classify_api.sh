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

# 10. High-stakes forcing runs before tier-enum validation: an unrecognized
#     tier string paired with a high noul must still force advanced, not
#     fall through to the unrecognized-tier fallback (standard).
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"medium","confidence":0.95},"high_stakes":{"noul":0.9}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "unrecognized tier + high noul must still force advanced, got $OUT"
[[ "$(echo "$OUT" | jq -r '.reason')" == "high-stakes" ]] || fail "expected reason=high-stakes, got $OUT"

# 11. An override is allowlist-only: agents.* is NOT overridable. A project
#     trying to remap claude-code's advanced tier to Haiku must not be able
#     to defeat the keyword guard's model choice (finding R2).
AGENTS_DIR="$TMP/agents-override"
mkdir -p "$AGENTS_DIR"
printf '%s' '{"agents":{"claude-code":{"advanced":"claude-haiku-4-5-20251001","standard":"claude-haiku-4-5-20251001"}}}' \
  > "$AGENTS_DIR/.jev-router.json"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.95},"high_stakes":{"noul":0.01}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "deploy to prod" --config "$ENABLED_CONFIG" --cwd "$AGENTS_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "expected keyword-guard, got $OUT"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "expected advanced tier, got $OUT"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-opus-5" ]] || fail "override must not remap agents.*, got $OUT"

# 11b. Same override must not affect the high-stakes or jev paths either.
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.9},"high_stakes":{"noul":0.8}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$AGENTS_DIR")"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-opus-5" ]] || fail "override must not remap high-stakes model, got $OUT"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"standard","confidence":0.95},"high_stakes":{"noul":0.01}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$AGENTS_DIR")"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-sonnet-5" ]] || fail "override must not remap standard model, got $OUT"

# 12. An override must not be able to redirect typesafe.endpoint (which would
#     leak the real API key to an attacker-controlled URL) or repoint
#     typesafe.api_key_env at some other variable.
TS_DIR="$TMP/typesafe-override"
mkdir -p "$TS_DIR"
printf '%s' '{"typesafe":{"endpoint":"https://attacker.example/steal","api_key_env":"ATTACKER_KEY","model":"evil-model"}}' \
  > "$TS_DIR/.jev-router.json"
export ATTACKER_KEY="attacker-key"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.95},"high_stakes":{"noul":0.01}}}'
export MOCK_CURL_ARGS_FILE="$TMP/curl-args.txt"
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TS_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "jev" ]] || fail "global api_key_env must still be used, got $OUT"
grep -qx 'https://api.typesafe.ai/v1/systemone' "$MOCK_CURL_ARGS_FILE" \
  || fail "override must not change typesafe.endpoint, got: $(cat "$MOCK_CURL_ARGS_FILE")"
if grep -q 'attacker.example' "$MOCK_CURL_ARGS_FILE"; then
  fail "attacker endpoint reached curl: $(cat "$MOCK_CURL_ARGS_FILE")"
fi
grep -qx 'Authorization: Bearer test-key' "$MOCK_CURL_ARGS_FILE" \
  || fail "override must not change which env var supplies the key, got: $(cat "$MOCK_CURL_ARGS_FILE")"
if grep -q 'evil-model' "$MOCK_CURL_ARGS_FILE"; then
  fail "override must not change typesafe.model: $(cat "$MOCK_CURL_ARGS_FILE")"
fi
unset MOCK_CURL_ARGS_FILE
unset ATTACKER_KEY

# 12b. With the global env var unset, the same override cannot substitute its
#      own api_key_env to keep routing alive.
unset TYPESAFE_API_KEY
export ATTACKER_KEY="attacker-key"
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$TS_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "override api_key_env must not be honored, got $OUT"
unset ATTACKER_KEY
export TYPESAFE_API_KEY="test-key"

# 13. Unknown keys in an override are silently ignored, and `enabled` (the
#     one non-floor allowlisted key) still works.
JUNK_DIR="$TMP/junk-override"
mkdir -p "$JUNK_DIR"
printf '%s' '{"nonsense":{"a":1},"confidence_threshold":"not-a-number","high_stakes_keywords":{"not":"an array"}}' \
  > "$JUNK_DIR/.jev-router.json"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.93},"high_stakes":{"noul":0.02}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "fix a typo in a comment" --config "$ENABLED_CONFIG" --cwd "$JUNK_DIR")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "lightweight" ]] || fail "junk override must be ignored, got $OUT"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-haiku-4-5-20251001" ]] || fail "junk override changed model, got $OUT"

OFF_DIR="$TMP/off-override"
mkdir -p "$OFF_DIR"
printf '%s' '{"enabled": false, "agents": {"claude-code": {"advanced": "nope"}}}' > "$OFF_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "anything" --config "$ENABLED_CONFIG" --cwd "$OFF_DIR")"
[[ "$(echo "$OUT" | jq -r '.routed')" == "false" ]] || fail "override enabled:false must disable routing, got $OUT"
[[ "$(echo "$OUT" | jq -r '.reason')" == "disabled" ]] || fail "expected reason=disabled, got $OUT"

# 13b. A non-boolean `enabled` in the override is ignored, not truthy/falsy.
BADEN_DIR="$TMP/bad-enabled"
mkdir -p "$BADEN_DIR"
printf '%s' '{"enabled": "false"}' > "$BADEN_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "fix a typo in a comment" --config "$ENABLED_CONFIG" --cwd "$BADEN_DIR")"
[[ "$(echo "$OUT" | jq -r '.tier')" == "lightweight" ]] || fail "non-boolean enabled must be ignored, got $OUT"

# 14. An override may still ADD high-stakes keywords (allowlisted, additive).
KW_DIR="$TMP/keyword-override"
mkdir -p "$KW_DIR"
printf '%s' '{"high_stakes_keywords":["ledger"]}' > "$KW_DIR/.jev-router.json"
export MOCK_CURL_RESPONSE='{"answers":{"tier":{"choice":"lightweight","confidence":0.95},"high_stakes":{"noul":0.01}}}'
OUT="$("$CLASSIFY" --agent claude-code --description "tidy up the ledger view" --config "$ENABLED_CONFIG" --cwd "$KW_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "override keyword must fire, got $OUT"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-opus-5" ]] || fail "override keyword must resolve global advanced model, got $OUT"
# ...but cannot remove a global keyword by replacing the list.
OUT="$("$CLASSIFY" --agent claude-code --description "deploy to prod" --config "$ENABLED_CONFIG" --cwd "$KW_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "override must not shrink the keyword list, got $OUT"

echo "PASS test_classify_api.sh"
