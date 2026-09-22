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

# Resolve --cwd to an absolute path so the upward override search terminates.
CWD_ABS="$(cd "$CWD" 2>/dev/null && pwd || true)"
if [[ -n "$CWD_ABS" ]]; then
  CWD="$CWD_ABS"
fi

find_override() {
  local dir="$1"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/.jev-router.json" ]]; then
      echo "$dir/.jev-router.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

EFFECTIVE_CONFIG="$(cat "$CONFIG_PATH")"
# A project override is NOT deep-merged: it may only affect an explicit
# allowlist of four top-level keys, and every other key (typesafe.*,
# agents.*, anything unknown) comes from the global config regardless of
# what the override contains. Unknown keys in the override are ignored.
# Of the four, three can only ever tighten the safety floor: keywords are
# unioned, high_stakes_probability_threshold can only move down (more
# sensitive) and confidence_threshold can only move up (more sensitive).
if OVERRIDE_PATH="$(find_override "$CWD")" && jq -e 'type == "object"' "$OVERRIDE_PATH" >/dev/null 2>&1; then
  EFFECTIVE_CONFIG="$(jq -s '
    .[0] as $g | .[1] as $o
    | $g
    | .enabled = (
        if ($o.enabled | type) == "boolean" then $o.enabled else $g.enabled end
      )
    | .high_stakes_keywords = (
        ($g.high_stakes_keywords // [])
        + (if ($o.high_stakes_keywords | type) == "array"
           then ($o.high_stakes_keywords | map(select(type == "string")))
           else [] end)
        | unique
      )
    | .high_stakes_probability_threshold = (
        if ($o.high_stakes_probability_threshold | type) == "number"
        then [$g.high_stakes_probability_threshold, $o.high_stakes_probability_threshold] | min
        else $g.high_stakes_probability_threshold end
      )
    | .confidence_threshold = (
        if ($o.confidence_threshold | type) == "number"
        then [$g.confidence_threshold, $o.confidence_threshold] | max
        else $g.confidence_threshold end
      )
  ' "$CONFIG_PATH" "$OVERRIDE_PATH")"
fi

cfg() { echo "$EFFECTIVE_CONFIG" | jq -r "$1"; }

ENABLED="$(cfg '.enabled')"
if [[ "$ENABLED" != "true" ]]; then
  jq -nc '{routed: false, reason: "disabled"}'
  exit 0
fi

resolve_model() {
  local tier="$1"
  echo "$EFFECTIVE_CONFIG" | jq -r --arg agent "$AGENT" --arg tier "$tier" '.agents[$agent][$tier]'
}

fallback_standard() {
  local reason="$1"
  local model
  model="$(resolve_model standard)"
  jq -nc --arg model "$model" --arg reason "$reason" '{routed: true, tier: "standard", confidence: 0, model: $model, reason: $reason}'
  exit 0
}

HAYSTACK="$(printf '%s %s %s %s' "$DESCRIPTION" "$SCOPE" "$RISK" "$EXPECTED_OUTPUT" | tr '[:upper:]' '[:lower:]')"
GUARD_HIT=false
while IFS= read -r kw; do
  [[ -z "$kw" ]] && continue
  kw_lc="$(echo "$kw" | tr '[:upper:]' '[:lower:]')"
  # Word-boundary match so "prod" does not fire inside "reproduce" and "iam"
  # does not fire inside "williams", while multi-word phrases still match.
  kw_re="$(printf '%s' "$kw_lc" | sed -e 's/\\/\\\\/g' -e 's/[]^$*+?(){}|.[]/\\&/g')"
  if [[ "$HAYSTACK" =~ (^|[^a-z0-9])${kw_re}($|[^a-z0-9]) ]]; then
    GUARD_HIT=true
    break
  fi
done < <(echo "$EFFECTIVE_CONFIG" | jq -r '.high_stakes_keywords[]')

if [[ "$GUARD_HIT" == true ]]; then
  MODEL="$(resolve_model advanced)"
  jq -nc --arg model "$MODEL" '{routed: true, tier: "advanced", confidence: 1.0, model: $model, reason: "keyword-guard"}'
  exit 0
fi

API_KEY_ENV="$(cfg '.typesafe.api_key_env')"
# api_key_env can come from a project-local override; anything that is not a
# plain shell identifier must never reach bash's indirect expansion.
[[ "$API_KEY_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fallback_standard "api-unavailable"
API_KEY="${!API_KEY_ENV:-}"
ENDPOINT="$(cfg '.typesafe.endpoint')"
JEV_MODEL="$(cfg '.typesafe.model')"
CONF_THRESHOLD="$(cfg '.confidence_threshold')"
HS_THRESHOLD="$(cfg '.high_stakes_probability_threshold')"

[[ -z "$API_KEY" ]] && fallback_standard "api-unavailable"

REQUEST_BODY=$(jq -n \
  --arg description "$DESCRIPTION" \
  --arg expected "$EXPECTED_OUTPUT" \
  --arg scope "$SCOPE" \
  --arg risk "$RISK" \
  --argjson deep_reasoning "$DEEP_REASONING" \
  --argjson browsing "$BROWSING" \
  --argjson vision "$VISION" \
  --argjson tool_use "$TOOL_USE" \
  --arg model "$JEV_MODEL" \
  '{
    state: {
      task_description: $description,
      expected_output: $expected,
      scope: $scope,
      risk: $risk,
      requires_deep_reasoning: $deep_reasoning,
      requires_browsing: $browsing,
      requires_vision: $vision,
      requires_tool_use: $tool_use
    },
    model: $model,
    questions: {
      tier: {
        type: "choice",
        instructions: "Classify how much capability this coding task needs.",
        criteria: {
          lightweight: "Lookups, file discovery, formatting, and mechanical edits.",
          standard: "Normal implementation, debugging, testing, and documentation.",
          advanced: "Architecture, security-sensitive work, ambiguous bugs, migrations, destructive operations, and complex reasoning."
        }
      },
      high_stakes: {
        type: "noul",
        instructions: "Is this task security-sensitive, destructive, a production deployment, or otherwise high-stakes?"
      }
    }
  }')

RESPONSE="$(curl -sS -X POST "$ENDPOINT" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")" || fallback_standard "api-unavailable"

echo "$RESPONSE" | jq -e '.answers.tier.choice' >/dev/null 2>&1 || fallback_standard "api-unavailable"

TIER="$(echo "$RESPONSE" | jq -r '.answers.tier.choice')"

# Non-numeric probabilities degrade to 0 rather than crashing --argjson.
CONFIDENCE="$(echo "$RESPONSE" | jq -r '(.answers.tier.confidence // 0) | if type == "number" then . else 0 end')"
HS_PROB="$(echo "$RESPONSE" | jq -r '(.answers.high_stakes.noul // 0) | if type == "number" then . else 0 end')"

# High-stakes forcing runs before tier validation: a response with an
# unrecognized tier string must still be forced to advanced if noul is
# high, rather than falling through to the "unrecognized tier" fallback
# and landing on standard for a genuinely high-stakes task.
if awk -v p="$HS_PROB" -v t="$HS_THRESHOLD" 'BEGIN{exit !(p>=t)}'; then
  MODEL="$(resolve_model advanced)"
  jq -nc --arg model "$MODEL" --argjson confidence "$CONFIDENCE" '{routed: true, tier: "advanced", confidence: $confidence, model: $model, reason: "high-stakes"}'
  exit 0
fi

case "$TIER" in
  lightweight|standard|advanced) ;;
  *) fallback_standard "api-unavailable" ;;
esac

if awk -v c="$CONFIDENCE" -v t="$CONF_THRESHOLD" 'BEGIN{exit !(c<t)}'; then
  fallback_standard "low-confidence"
fi

MODEL="$(resolve_model "$TIER")"
jq -nc --arg model "$MODEL" --arg tier "$TIER" --argjson confidence "$CONFIDENCE" '{routed: true, tier: $tier, confidence: $confidence, model: $model, reason: "jev"}'
