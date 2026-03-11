---
name: ai-review
description: Run a tier-aware critic review before committing. Tier 1 skips review. Tier 2 runs blueprint-aligner only. Tier 3 runs full parallel critics (arch + security + tests) plus security_engineer and UACS verification. Equivalent to `ai review claude [--tier N]`.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
context: fork
agent: Plan
---

# AI-OS Review (Tier-Aware Parallel Critics)

## Dynamic Context Injection
Current tier signals: !git diff --staged --name-only 2>/dev/null | head -10 || echo "(no staged changes)"
Recent CRITIC_STAMP: !grep -m1 "\[CRITIC_STAMP\]" .ai/REVIEWS.md 2>/dev/null || echo "(none — review required)"
Recent UACS_VERIFIED: !grep -m1 "\[UACS_VERIFIED\]" .ai/LOG.md 2>/dev/null || echo "(none)"

## Step 1 — Detect Tier

Classify the current changes using `risk-analyzer-mcp`:
```
classify_risk()   ← reads UPDATE.md + staged diff automatically
```

Or classify manually:
- **Tier 1**: Only `.css`, `.md`, `.txt`, docs, formatting → skip review.
- **Tier 2**: `src/**` logic changes, tests, refactors → blueprint_aligner only.
- **Tier 3**: auth, secrets, new dependencies, breaking changes → full Triad.

---

## Tier 1 — Skip Review

CSS/docs/typos only. No critic agents needed.

```bash
npx prettier --check .
npx eslint . --max-warnings 0
```

Commit: `git commit -m "[TIER_1] <description>"`
No `[CRITIC_STAMP]` required for Tier 1.

---

## Tier 2 — Blueprint Aligner Only

Run `blueprint-aligner-mcp`:
```
align_diff()   ← compares staged diff vs architect.md
```

If PASS: append to `.ai/REVIEWS.md`:
```
[CRITIC_STAMP] YYYY-MM-DD | [TIER_2] Blueprint aligned — no deviations
```

Commit: `git commit -m "[TIER_2] <description>"`

---

## Tier 3 — Full Parallel Critics

Execute all in parallel (use sub-agents / Agent tool):

**critic_arch**
- Read `src/` against `.ai/architect.md`
- Flag: domain sovereignty violations, orphaned code, System Philosophy contradictions

**critic_security**
- Read `src/` and `hooks/` for OWASP Top 10
- Check: shell injection, env variable leakage, path traversal, CAPABILITIES.md compliance

**critic_tests**
- Review test coverage for all modified files
- Flag: untested paths, missing edge cases, quality gate gaps

**security_engineer agent** (parallel)
- Threat model the specific changes
- Append `[SEC_CLEARED] YYYY-MM-DD` to `.ai/LOG.md` if clear

**blueprint-aligner-mcp** (parallel)
```
align_diff()
```

### After All Critics Complete
Synthesize findings. Append to `.ai/REVIEWS.md`:
```
[CRITIC_STAMP] YYYY-MM-DD | [TIER_3] <summary of critical findings or "No P0 issues">
```

If all gates clear, append to `.ai/LOG.md`:
```
[UACS_VERIFIED] YYYY-MM-DD | Tier 3 review complete — all gates passed
```

Then run: `ai test --vibe` (mandatory for Tier 3 before commit).

Commit: `git commit -m "[TIER_3] <description>"`
