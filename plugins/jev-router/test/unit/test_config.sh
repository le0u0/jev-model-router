#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/../../config/config.json"

fail() { echo "FAIL: $1" >&2; exit 1; }

[[ -f "$CONFIG" ]] || fail "config.json does not exist"
jq -e . "$CONFIG" >/dev/null || fail "config.json is not valid JSON"

[[ "$(jq -r '.enabled' "$CONFIG")" == "false" ]] || fail "enabled must default to false"
[[ "$(jq -r '.confidence_threshold' "$CONFIG")" == "0.7" ]] || fail "confidence_threshold must be 0.7"
[[ "$(jq -r '.high_stakes_probability_threshold' "$CONFIG")" == "0.5" ]] || fail "high_stakes_probability_threshold must be 0.5"
[[ "$(jq -r '.agents["claude-code"].lightweight' "$CONFIG")" == "claude-haiku-4-5-20251001" ]] || fail "claude-code lightweight model wrong"
[[ "$(jq -r '.agents["claude-code"].standard' "$CONFIG")" == "claude-sonnet-5" ]] || fail "claude-code standard model wrong"
[[ "$(jq -r '.agents["claude-code"].advanced' "$CONFIG")" == "claude-opus-5" ]] || fail "claude-code advanced model wrong"
[[ "$(jq -r '.agents.codex.lightweight' "$CONFIG")" == "gpt-5.6-luna" ]] || fail "codex lightweight model wrong"
[[ "$(jq -r '.agents.codex.standard' "$CONFIG")" == "gpt-5.6-terra" ]] || fail "codex standard model wrong"
[[ "$(jq -r '.agents.codex.advanced' "$CONFIG")" == "gpt-5.6-sol" ]] || fail "codex advanced model wrong"
[[ "$(jq -r '.high_stakes_keywords | length > 0' "$CONFIG")" == "true" ]] || fail "high_stakes_keywords must be non-empty"

echo "PASS test_config.sh"
