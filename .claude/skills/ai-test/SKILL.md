---
name: ai-test
description: Use activate_skill with this name when asked to run tests, before committing, or for Tier 3 releases (use --vibe flag). Runs TestSprite for E2E tests or triggers the two-phase Vibe & Chaos audit (ux_reviewer + chaos_monkey).
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Glob
context: default
agent: default
---

# AI-OS Test

## Dynamic Context Injection
Test framework: !cat package.json 2>/dev/null | grep -E '"(test|dev|start)"' | head -5 || echo "(no package.json)"
Open tasks requiring tests: !grep -n "E-[0-9]" .ai/TASKS.md 2>/dev/null | grep -v "\[x\]" | head -5 || echo "(all tasks complete)"

## Standard Test Run

Run the full TestSprite suite:

```bash
npx testsprite run
```

If TestSprite is not installed: `npm install -g testsprite` or use `npx @testsprite/testsprite-mcp`.

Gate: All tests must pass at 100% before any commit. If a test fails, you are **LOCKED** — fix the failure before proceeding.

---

## Vibe & Chaos Audit (--vibe flag)

Trigger this when the user requests `--vibe` or for any **Tier 3** release.

### Phase 1 — Visual Audit (ux_reviewer)
Use the `ux_reviewer` agent (Gemini) to:
1. Spin up the dev server (`npm run dev` or `npm start`).
2. Check each primary route for: CLS < 0.1, WCAG AA contrast, 44px touch targets, visible focus rings.
3. Run Lighthouse: Performance ≥ 80, Accessibility ≥ 90.
4. Rapid-click stress: 10× clicks on primary CTA.
5. Append `[VIBE_REPORT] YYYY-MM-DD | Score: X/10` to `.ai/REVIEWS.md`.

Or use `vibe-check-mcp`:
```
run_vibe_audit(url: "http://localhost:3000")
run_chaos_test(url: "http://localhost:3000", interactions: 20)
get_performance_metrics(url: "http://localhost:3000")
```

### Phase 2 — Chaos Stress Test (chaos_monkey)
Use the `chaos_monkey` agent to:
1. Verify `[SEC_CLEARED]` in `.ai/LOG.md` before starting.
2. Run 5-phase chaos suite: invalid inputs, network latency, rapid-click, concurrent sessions, resource exhaustion.
3. Append `[CHAOS_REPORT] YYYY-MM-DD` to `.ai/REVIEWS.md`.
4. Tag `[CHAOS_CLEARED]` or `[CHAOS_BLOCKED]` in `.ai/LOG.md`.

### Required Stamps (Tier 3 Release Gate)
All three must exist in `.ai/REVIEWS.md` before committing:
- `[VIBE_REPORT]` (≤ 7 days old)
- `[CHAOS_CLEARED]`
- `[CRITIC_STAMP]` (from `skill: ai-review`)
