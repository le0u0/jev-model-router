#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$DIR/../../scripts/classify.sh"
CONFIG="$DIR/../../config/config.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. disabled config -> routed:false
DISABLED_CONFIG="$TMP/disabled.json"
jq '.enabled = false' "$CONFIG" > "$DISABLED_CONFIG"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$DISABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.routed')" == "false" ]] || fail "disabled config must yield routed:false"
[[ "$(echo "$OUT" | jq -r '.reason')" == "disabled" ]] || fail "disabled reason mismatch"

# 2. enabled config + high-stakes keyword in description -> forced advanced, no API call needed
ENABLED_CONFIG="$TMP/enabled.json"
jq '.enabled = true' "$CONFIG" > "$ENABLED_CONFIG"
OUT="$("$CLASSIFY" --agent claude-code --description "run terraform apply against prod" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.routed')" == "true" ]] || fail "guard case must be routed:true"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "guard case must resolve to advanced"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "guard case reason mismatch"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-opus-5" ]] || fail "guard case model mismatch"

# 3. project override merges over global config
PROJECT_DIR="$TMP/project"
mkdir -p "$PROJECT_DIR"
echo '{"enabled": false}' > "$PROJECT_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$ENABLED_CONFIG" --cwd "$PROJECT_DIR")"
[[ "$(echo "$OUT" | jq -r '.routed')" == "false" ]] || fail "project override must disable routing"

# No API key from here on: every non-guard case must fail safe locally,
# never reach the network.
unset TYPESAFE_API_KEY

# 4. guard scans --risk too, not just --description/--scope
OUT="$("$CLASSIFY" --agent claude-code \
  --description "tidy up a helper function" \
  --scope "one file" \
  --risk "irreversible loss of production patient data" \
  --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "guard must scan --risk (got $OUT)"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "risk-only keyword must force advanced"

# 4b. guard scans --expected-output too
OUT="$("$CLASSIFY" --agent claude-code \
  --description "tidy up a helper function" \
  --expected-output "a rotated set of credentials" \
  --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "guard must scan --expected-output (got $OUT)"

# 5. keywords match on word boundaries: "prod" must not fire inside "reproduce"
OUT="$("$CLASSIFY" --agent claude-code \
  --description "write a test to reproduce the bug" \
  --scope "one test file" \
  --risk "none, test-only" \
  --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" != "keyword-guard" ]] || fail "'prod' must not match inside 'reproduce'"
[[ "$(echo "$OUT" | jq -r '.routed')" == "true" ]] || fail "non-guard case must still route"

# 5b. "iam" must not fire inside "williams"/"diameter"
OUT="$("$CLASSIFY" --agent claude-code \
  --description "update the diameter field on the williams record" \
  --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" != "keyword-guard" ]] || fail "'iam' must not match inside 'williams'/'diameter'"

# 5c. standalone keyword still fires
OUT="$("$CLASSIFY" --agent claude-code --description "check the iam policy" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "standalone 'iam' must fire"

# 6. stdout is exactly one line (guard case and fallback case)
OUT="$("$CLASSIFY" --agent claude-code --description "run terraform apply against prod" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" == "1" ]] || fail "guard output must be one line"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$ENABLED_CONFIG" --cwd "$TMP")"
[[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" == "1" ]] || fail "fallback output must be one line"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$DISABLED_CONFIG" --cwd "$TMP")"
[[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" == "1" ]] || fail "disabled output must be one line"

# 7. malicious api_key_env in a project override must not execute anything
MARKER="/tmp/pwned_marker"
rm -f "$MARKER"
EVIL_DIR="$TMP/evil"
mkdir -p "$EVIL_DIR"
printf '%s' '{"typesafe": {"api_key_env": "K[$(touch /tmp/pwned_marker)]"}}' > "$EVIL_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$ENABLED_CONFIG" --cwd "$EVIL_DIR")" \
  || fail "malicious api_key_env must not make classify.sh exit non-zero"
[[ ! -e "$MARKER" ]] || { rm -f "$MARKER"; fail "command injection via api_key_env executed"; }
[[ "$(echo "$OUT" | jq -r '.routed')" == "true" ]] || fail "malicious api_key_env must fail safe to routed:true"
[[ "$(echo "$OUT" | jq -r '.tier')" == "standard" ]] || fail "malicious api_key_env must fail safe to standard"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "malicious api_key_env reason must be api-unavailable"
[[ "$(echo "$OUT" | jq -r '.confidence')" == "0" ]] || fail "malicious api_key_env confidence must be 0"
[[ "$(echo "$OUT" | jq -r '.model')" == "claude-sonnet-5" ]] || fail "malicious api_key_env must resolve the standard model"

# 8. malformed project override is ignored, global config still applies
BAD_DIR="$TMP/badjson"
mkdir -p "$BAD_DIR"
printf '%s' '{"enabled": false' > "$BAD_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "rename a variable" --config "$ENABLED_CONFIG" --cwd "$BAD_DIR")" \
  || fail "malformed override must not make classify.sh exit non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "malformed override must still yield valid JSON, got: $OUT"
[[ "$(echo "$OUT" | jq -r '.routed')" == "true" ]] || fail "malformed override must be ignored (global enabled=true)"
[[ "$(echo "$OUT" | jq -r '.reason')" == "api-unavailable" ]] || fail "malformed override case reason mismatch"

# 9. hostile override cannot weaken the safety floor
HOSTILE_DIR="$TMP/hostile"
mkdir -p "$HOSTILE_DIR"
printf '%s' '{"high_stakes_keywords": [], "high_stakes_probability_threshold": 0.99, "confidence_threshold": 0.01}' \
  > "$HOSTILE_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "run terraform apply against prod" --config "$ENABLED_CONFIG" --cwd "$HOSTILE_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "hostile override must not empty high_stakes_keywords (got $OUT)"
[[ "$(echo "$OUT" | jq -r '.tier')" == "advanced" ]] || fail "hostile override must not stop the guard forcing advanced"

# 9b. an override may still ADD keywords
ADD_DIR="$TMP/addkw"
mkdir -p "$ADD_DIR"
printf '%s' '{"high_stakes_keywords": ["banana"]}' > "$ADD_DIR/.jev-router.json"
OUT="$("$CLASSIFY" --agent claude-code --description "peel the banana carefully" --config "$ENABLED_CONFIG" --cwd "$ADD_DIR")"
[[ "$(echo "$OUT" | jq -r '.reason')" == "keyword-guard" ]] || fail "override-added keyword must fire (got $OUT)"

# 10. a relative --cwd must terminate instead of looping forever
OUT="$(cd "$TMP" && "$CLASSIFY" --agent claude-code --description "rename a variable" --config "$ENABLED_CONFIG" --cwd ".")"
[[ "$(echo "$OUT" | jq -r '.routed')" == "true" ]] || fail "relative --cwd must resolve and route"

echo "PASS test_classify_guard.sh"
