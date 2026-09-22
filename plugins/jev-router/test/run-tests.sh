#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$DIR/../scripts/classify.sh"
CONFIG="$DIR/../config/config.json"
TASKS="$DIR/tasks.json"
REPORT="$DIR/report.md"

[[ -n "${TYPESAFE_API_KEY:-}" ]] || { echo "TYPESAFE_API_KEY must be set to run the real test suite" >&2; exit 2; }

TMP_CONFIG="$(mktemp)"
jq '.enabled = true' "$CONFIG" > "$TMP_CONFIG"
PRESERVED="$(mktemp)"
trap 'rm -f "$TMP_CONFIG" "$PRESERVED"' EXIT

MARKER='^\*\*[0-9]+/[0-9]+ tasks matched'

# Keep the hand-written section that follows the summary line, if any.
if [[ -s "$REPORT" ]]; then
  awk -v marker="$MARKER" 'found { print } $0 ~ marker { found = 1 }' "$REPORT" > "$PRESERVED"
fi

{
  echo "# jev-router test report"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| id | agent | expected tier | got tier | confidence | reason | model | reason match | match |"
  echo "|---|---|---|---|---|---|---|---|---|"
} > "$REPORT"

PASS=0
FAIL=0

while IFS= read -r task; do
  id="$(echo "$task" | jq -r '.id')"
  agent="$(echo "$task" | jq -r '.agent')"
  description="$(echo "$task" | jq -r '.description')"
  expected_output="$(echo "$task" | jq -r '.expected_output')"
  scope="$(echo "$task" | jq -r '.scope')"
  risk="$(echo "$task" | jq -r '.risk')"
  expected_tier="$(echo "$task" | jq -r '.expected_tier')"
  expect_reason="$(echo "$task" | jq -r '.expect_reason // ""')"

  RESULT="$("$CLASSIFY" --agent "$agent" --description "$description" --expected-output "$expected_output" --scope "$scope" --risk "$risk" --config "$TMP_CONFIG" --cwd "$DIR")"
  got_tier="$(echo "$RESULT" | jq -r '.tier')"
  confidence="$(echo "$RESULT" | jq -r '.confidence')"
  reason="$(echo "$RESULT" | jq -r '.reason')"
  model="$(echo "$RESULT" | jq -r '.model')"

  reason_match="n/a"
  if [[ -n "$expect_reason" ]]; then
    reason_match="no"
    [[ "$reason" == "$expect_reason" ]] && reason_match="yes"
  fi

  match="no"
  [[ "$got_tier" == "$expected_tier" && "$reason_match" != "no" ]] && match="yes"
  if [[ "$match" == "yes" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

  echo "| $id | $agent | $expected_tier | $got_tier | $confidence | $reason | $model | $reason_match | $match |" >> "$REPORT"
done < <(jq -c '.[]' "$TASKS")

{
  echo
  echo "**$PASS/$((PASS+FAIL)) tasks matched their expected tier.**"
} >> "$REPORT"

if [[ -s "$PRESERVED" ]]; then
  cat "$PRESERVED" >> "$REPORT"
else
  {
    echo
    echo "Cost comparison (Claude side only — token-weighted estimate using"
    echo "published Claude API pricing, vs. an always-claude-opus-5 baseline)"
    echo "is filled in by hand after reviewing this table; Codex-side pricing"
    echo "is intentionally not estimated here (no verified current pricing"
    echo "data)."
  } >> "$REPORT"
fi

echo "Report written to $REPORT"
cat "$REPORT"

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
