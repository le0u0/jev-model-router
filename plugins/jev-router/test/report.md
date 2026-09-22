# jev-router test report

Generated: 2026-09-22T03:41:53Z

| id | agent | expected tier | got tier | confidence | reason | model | match |
|---|---|---|---|---|---|---|---|
| lw-1 | claude-code | lightweight | standard | 0 | api-unavailable | claude-sonnet-5 | no |
| lw-2 | codex | lightweight | standard | 0 | api-unavailable | gpt-5.6-terra | no |
| lw-3 | claude-code | lightweight | standard | 0 | api-unavailable | claude-sonnet-5 | no |
| std-1 | claude-code | standard | standard | 0 | api-unavailable | claude-sonnet-5 | yes |
| std-2 | codex | standard | standard | 0 | api-unavailable | gpt-5.6-terra | yes |
| std-3 | claude-code | standard | standard | 0 | api-unavailable | claude-sonnet-5 | yes |
| adv-1 | claude-code | advanced | standard | 0 | api-unavailable | claude-sonnet-5 | no |
| adv-2 | codex | advanced | standard | 0 | api-unavailable | gpt-5.6-terra | no |
| adv-3 | claude-code | advanced | standard | 0 | api-unavailable | claude-sonnet-5 | no |
| edge-destructive | claude-code | advanced | advanced | 1.0 | keyword-guard | claude-opus-5 | yes |
| edge-ambiguous | codex | standard | standard | 0 | api-unavailable | gpt-5.6-terra | yes |
| edge-deploy | claude-code | advanced | advanced | 1.0 | keyword-guard | claude-opus-5 | yes |

**6/12 tasks matched their expected tier.**

Cost comparison (Claude side only — token-weighted estimate using
published Claude API pricing, vs. an always-claude-opus-5 baseline)
is filled in by hand after reviewing this table; Codex-side pricing
is intentionally not estimated here (no verified current pricing
data).
