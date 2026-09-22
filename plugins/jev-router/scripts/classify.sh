#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="$SCRIPT_DIR/../config/config.json"

CONFIG_PATH="$DEFAULT_CONFIG"
CWD="$(pwd)"
AGENT=""
DESCRIPTION=""
EXPECTED_OUTPUT=""
SCOPE=""
RISK=""
DEEP_REASONING=false
BROWSING=false
VISION=false
TOOL_USE=false

usage() {
  echo "Usage: classify.sh --agent <claude-code|codex> --description TEXT [--expected-output TEXT] [--scope TEXT] [--risk TEXT] [--deep-reasoning] [--browsing] [--vision] [--tool-use] [--config PATH] [--cwd PATH]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --expected-output) EXPECTED_OUTPUT="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --risk) RISK="$2"; shift 2 ;;
    --deep-reasoning) DEEP_REASONING=true; shift ;;
    --browsing) BROWSING=true; shift ;;
    --vision) VISION=true; shift ;;
    --tool-use) TOOL_USE=true; shift ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$AGENT" ]] && { echo "Missing --agent" >&2; usage; }
[[ -z "$DESCRIPTION" ]] && { echo "Missing --description" >&2; usage; }
[[ "$AGENT" != "claude-code" && "$AGENT" != "codex" ]] && { echo "Unknown --agent: $AGENT (expected claude-code or codex)" >&2; exit 2; }
[[ -f "$CONFIG_PATH" ]] || { echo "Config not found: $CONFIG_PATH" >&2; exit 2; }

find_override() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.jev-router.json" ]]; then
      echo "$dir/.jev-router.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

EFFECTIVE_CONFIG="$(cat "$CONFIG_PATH")"
if OVERRIDE_PATH="$(find_override "$CWD")"; then
  EFFECTIVE_CONFIG="$(jq -s '.[0] * .[1]' "$CONFIG_PATH" "$OVERRIDE_PATH")"
fi

cfg() { echo "$EFFECTIVE_CONFIG" | jq -r "$1"; }

ENABLED="$(cfg '.enabled')"
if [[ "$ENABLED" != "true" ]]; then
  jq -n '{routed: false, reason: "disabled"}'
  exit 0
fi

resolve_model() {
  local tier="$1"
  echo "$EFFECTIVE_CONFIG" | jq -r --arg agent "$AGENT" --arg tier "$tier" '.agents[$agent][$tier]'
}

HAYSTACK="$(printf '%s %s' "$DESCRIPTION" "$SCOPE" | tr '[:upper:]' '[:lower:]')"
GUARD_HIT=false
while IFS= read -r kw; do
  [[ -z "$kw" ]] && continue
  kw_lc="$(echo "$kw" | tr '[:upper:]' '[:lower:]')"
  if [[ "$HAYSTACK" == *"$kw_lc"* ]]; then
    GUARD_HIT=true
    break
  fi
done < <(echo "$EFFECTIVE_CONFIG" | jq -r '.high_stakes_keywords[]')

if [[ "$GUARD_HIT" == true ]]; then
  MODEL="$(resolve_model advanced)"
  jq -n --arg model "$MODEL" '{routed: true, tier: "advanced", confidence: 1.0, model: $model, reason: "keyword-guard"}'
  exit 0
fi

# TypeSafe call added in Task 4.
echo '{"routed": false, "reason": "not-implemented"}' >&2
exit 3
