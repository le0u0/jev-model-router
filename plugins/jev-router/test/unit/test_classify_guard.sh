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

echo "PASS test_classify_guard.sh"
