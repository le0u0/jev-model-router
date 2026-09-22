# jev-router

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

Drop a `.jev-router.json` at a project's root to override any of the above
for that project only, e.g. to opt a legacy repo out entirely:
```json
{ "enabled": false }
```
`classify.sh` walks up from the current directory looking for this file
and merges it over the global config — no plugin changes needed. An invalid
JSON override is ignored rather than fatal.

The safety floor is not overridable downwards: `high_stakes_keywords` from
an override are *added* to the global list (never replace or shrink it),
`high_stakes_probability_threshold` can only be lowered (made more
sensitive) and `confidence_threshold` can only be raised. A project can
make routing more conservative, never less.

## Turning it on/off

Run the `jev-router-on` or `jev-router-off` skill (or `/jev-router-on`,
`/jev-router-off`), from either Claude Code or Codex CLI — both read the
same `config/config.json`.

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
