# jev-router

Version: `0.1.0`.

Jev-powered model routing for delegated subagent tasks, shared by Claude
Code and Codex CLI.

## What it does

Before dispatching a task to a subagent, the `jev-router` skill classifies
it (via TypeSafe's Jev model) into `lightweight` / `standard` / `advanced`
and resolves that to a concrete model for whichever agent is dispatching
it. It never changes the model of the session currently running it — only
of tasks it hands off.

Off by default. Nothing routes until you run `jev-router-on`.

## Configuration

Edit `config/config.json`:
- `enabled` — global on/off switch (also flipped by `jev-router-on` / `jev-router-off`).
- `confidence_threshold` — below this, a task falls back to `standard` instead of trusting a low-confidence Jev answer.
- `high_stakes_probability_threshold` — at or above this, a task is forced to `advanced` regardless of its tier confidence.
- `high_stakes_keywords` — case-insensitive whole-word (or whole-phrase) matches that force `advanced` before any API call is made. Matching is word-bounded, so `prod` fires on "deploy to prod" but not inside "reproduce" or "product"; a multi-word entry like `terraform apply` matches that phrase. All four task fields are scanned (description, scope, risk, expected output).
- `agents.claude-code.*` / `agents.codex.*` — the model slug used for each tier, per agent.

## Per-project override

Drop a `.jev-router.json` at a project's root to adjust routing for that
project only, e.g. to opt a legacy repo out entirely:
```json
{ "enabled": false }
```
`classify.sh` walks up from the current directory looking for this file —
no plugin changes needed. An invalid JSON override (or one that isn't a
JSON object) is ignored rather than fatal.

The override is **not** merged over the global config. It is an allowlist:
exactly four top-level keys have any effect, and each may only move routing
in the conservative direction.

| Key | Effect |
| --- | --- |
| `enabled` (boolean) | A project may switch routing off entirely. |
| `high_stakes_keywords` (array of strings) | *Added* to the global list — never replaces or shrinks it. |
| `high_stakes_probability_threshold` (number) | May only be lowered (made more sensitive) than the global value. |
| `confidence_threshold` (number) | May only be raised (made more sensitive) than the global value. |

Everything else is fixed by the global `config/config.json` regardless of
what a project override contains. In particular `agents.*` (the model slug
per tier) and `typesafe.*` (`endpoint`, `model`, `api_key_env`) are **not**
project-overridable, so a project cannot downgrade the model a high-stakes
task resolves to, nor redirect the API call and its credential elsewhere.
Any other key in an override — and a value of the wrong type for one of
the four above — is silently ignored.

## Turning it on/off

Run the `jev-router-on` or `jev-router-off` skill (or `/jev-router-on`,
`/jev-router-off`) in the host you want to change. Claude Code and Codex CLI
read their own installed copies of `config/config.json`.

## Testing before enabling

`test/run-tests.sh` runs 12 representative tasks through the real
classifier and writes `test/report.md`. Review that report — especially
that the adversarial/destructive/production-flavored tasks all resolved to
`advanced` — before ever running `jev-router-on`.

## Uninstalling

Remove the two blocks this plugin's installation added:

**`~/.claude/settings.json`** — delete the `jev-model-router` entry from
`extraKnownMarketplaces` and the `"jev-router@jev-model-router"` entry from
`enabledPlugins`.

**`~/.codex/config.toml`** — delete the `[marketplaces.jev-model-router]`
section and the `[plugins."jev-router@jev-model-router"]` section.

No other files on the machine are touched.
