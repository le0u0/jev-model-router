#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${JEV_ROUTER_CONFIG:-$SCRIPT_DIR/../config/config.json}"
ACTION="${1:-}"

if [[ "$ACTION" != "on" && "$ACTION" != "off" ]]; then
  echo "Usage: toggle.sh on|off" >&2
  exit 2
fi

[[ -f "$CONFIG_PATH" ]] || { echo "Config not found: $CONFIG_PATH" >&2; exit 2; }

VALUE="false"
[[ "$ACTION" == "on" ]] && VALUE="true"

TMP="$(mktemp)"
jq --argjson enabled "$VALUE" '.enabled = $enabled' "$CONFIG_PATH" > "$TMP" && mv "$TMP" "$CONFIG_PATH"
echo "jev-router: enabled=$VALUE"
