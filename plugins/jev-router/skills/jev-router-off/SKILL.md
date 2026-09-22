---
name: jev-router-off
description: Turn off Jev-powered model routing for delegated subagent tasks (both Claude Code and Codex CLI read the same config). Use when the user says "turn off jev router", "disable jev-router", or /jev-router-off.
---

# jev-router-off

This skill's own directory path, minus the trailing `/skills/jev-router-off`,
is the plugin root. Run, from that plugin root:

```bash
scripts/toggle.sh off
```

Report the exact line it prints. Do not edit `config/config.json` by hand.
