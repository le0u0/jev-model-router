---
name: jev-router
description: Before dispatching a task to a subagent (Claude Code's Agent tool, or Codex's multi-agent dispatch), classify it with Jev and pick the right-sized model. Use whenever you are about to delegate a coding task to another agent instance.
---

# jev-router

This skill's own directory path, minus the trailing `/skills/jev-router`, is
the plugin root; all commands below run from that plugin root.

Before dispatching ANY task to a subagent, run:

```bash
scripts/classify.sh \
  --agent <claude-code|codex>   \
  --description "<what the subagent must do, in your own words>" \
  --expected-output "<what a correct result looks like>" \
  --scope "<files, directories, or systems this task touches>" \
  --risk "<what breaks if the answer is wrong>" \
  [--deep-reasoning] [--browsing] [--vision] [--tool-use]
```

Use `--agent claude-code` if you are Claude Code; use `--agent codex` if you
are Codex CLI. Pass `--deep-reasoning`, `--browsing`, `--vision`, or
`--tool-use` when the task genuinely needs that capability — omit flags that
don't apply.

The command prints one JSON line:

```json
{"routed": true, "tier": "standard", "confidence": 0.86, "model": "claude-sonnet-5", "reason": "jev"}
```

- If `routed` is `true`: use the `model` value as the model for this
  subagent dispatch.
- If `routed` is `false` (router disabled globally or for this project):
  proceed with your normal default model choice — do not guess a
  substitute.

Never skip this check to save time, and never override its `model` result
with your own guess about task difficulty — the keyword guard and the
confidence threshold inside `classify.sh` exist specifically to keep
security-sensitive, destructive, and production-facing tasks on the
`advanced` tier even when they read as simple.
