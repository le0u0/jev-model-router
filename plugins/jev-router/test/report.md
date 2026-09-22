# jev-router test report

Generated: 2026-09-22T05:25:50Z

| id | agent | expected tier | got tier | confidence | reason | model | reason match | match |
|---|---|---|---|---|---|---|---|---|
| lw-1 | claude-code | lightweight | lightweight | 1.0 | jev | claude-haiku-4-5-20251001 | n/a | yes |
| lw-2 | codex | lightweight | lightweight | 1.0 | jev | gpt-5.6-luna | n/a | yes |
| lw-3 | claude-code | lightweight | lightweight | 1.0 | jev | claude-haiku-4-5-20251001 | n/a | yes |
| std-1 | claude-code | standard | standard | 0.82 | jev | claude-sonnet-5 | n/a | yes |
| std-2 | codex | standard | standard | 0.98 | jev | gpt-5.6-terra | n/a | yes |
| std-3 | claude-code | standard | standard | 0.99 | jev | claude-sonnet-5 | n/a | yes |
| adv-1 | claude-code | advanced | advanced | 0.96 | jev | claude-opus-5 | n/a | yes |
| adv-2 | codex | advanced | advanced | 0.89 | high-stakes | gpt-5.6-sol | n/a | yes |
| adv-3 | claude-code | advanced | advanced | 0.87 | high-stakes | claude-opus-5 | n/a | yes |
| edge-destructive | claude-code | advanced | advanced | 1.0 | keyword-guard | claude-opus-5 | yes | yes |
| edge-ambiguous | codex | standard | standard | 0 | low-confidence | gpt-5.6-terra | yes | yes |
| edge-deploy | claude-code | advanced | advanced | 1.0 | keyword-guard | claude-opus-5 | yes | yes |

**12/12 tasks matched their expected tier.**

## Cost comparison (Claude-routed tasks only)

Illustrative estimate, not a measurement — assumes a uniform 5,000 input /
2,000 output tokens per subagent task (a rough size for tasks like the ones
above) and current published Claude API pricing (Sonnet 5: $2/$10 per MTok
in/out; Opus 5: $5/$25; Haiku 4.5: $1/$5), so it isolates the effect of
routing, not real per-task token variance:

| Tier | Tasks | $/task | Subtotal |
|---|---|---|---|
| lightweight (haiku) | 2 | $0.015 | $0.030 |
| standard (sonnet) | 2 | $0.030 | $0.060 |
| advanced (opus) | 4 | $0.075 | $0.300 |
| **Routed total** | **8** | | **$0.390** |
| Always-opus baseline | 8 | $0.075 | $0.600 |

**~35% lower cost** on this 8-task Claude-routed sample vs. always
dispatching claude-opus-5, at the same illustrative token size.

Codex-side pricing is intentionally not estimated — no verified current
pricing data for gpt-5.6-luna/terra/sol was available, and this design
avoids inventing figures for models it has no documented pricing for.
