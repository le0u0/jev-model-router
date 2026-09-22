# jev-model-router

Route Claude Code and Codex subagent tasks to a suitable model with TypeSafe Jev.

## How it works

Before dispatch, `jev-router` classifies a task as `lightweight`, `standard`,
or `advanced`, then selects a model for the active agent. Risk keywords and
high-stakes results force `advanced`. The current session's model does not
change. See [plugin configuration](plugins/jev-router/README.md) for model
mappings and routing controls.

## Install

### Claude Code install

```bash
claude plugin marketplace add le0u0/jev-model-router
claude plugin install jev-router@jev-model-router
```

### Codex install

```bash
codex plugin marketplace add le0u0/jev-model-router
codex plugin add jev-router@jev-model-router
```
