---
name: jev-router-on
description: Turn on Jev-powered model routing for delegated subagent tasks (both Claude Code and Codex CLI read the same config). Use when the user says "turn on jev router", "enable jev-router", or /jev-router-on.
---

# jev-router-on

This skill's own directory path, minus the trailing `/skills/jev-router-on`,
is the plugin root. Run, from that plugin root:

```bash
scripts/toggle.sh on
```

Report the exact line it prints. Do not edit `config/config.json` by hand.
