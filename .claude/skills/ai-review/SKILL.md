---
name: ai-review
description: Run a tier-aware critic review before committing. Tier 1 skips review. Tier 2 runs blueprint-aligner only. Tier 3 runs full parallel critics (arch + security + tests) plus security_engineer and UACS verification. Equivalent to `ai review claude [--tier N]`.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
context: fork
agent: default
---

# AI-OS Review (Tier-Aware Parallel Critics)

## Dynamic Context Injection
Current tier signals: !git diff --staged --name-only 2>/dev/null | head -10 || echo "(no staged changes)"
Recent CRITIC_STAMP: !grep -m1 "\[CRITIC_STAMP\]" .ai/REVIEWS.md 2>/dev/null || echo "(none — review required)"
Recent distributed stamps: !grep -E "\[(ARCH|SEC|TESTS|ALIGN)_(PASS|FAIL)\]" .ai/REVIEWS.md 2>/dev/null | tail -4 || echo "(none)"
Recent UACS_VERIFIED: !grep -m1 "\[UACS_VERIFIED\]" .ai/LOG.md 2>/dev/null || echo "(none)"

## Step 1 — Detect Tier

Classify the current changes using `risk-analyzer-mcp`:
```
classify_risk()   ← reads staged diff automatically
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

If PASS: record via MCP — do NOT write directly to `.ai/REVIEWS.md`:
```
mcp__task-synchronizer-mcp__add_stamp({
  type: "ALIGN_PASS",
  agent: "blueprint-aligner-mcp",
  summary: "[TIER_2] Blueprint aligned — no deviations"
})
mcp__task-synchronizer-mcp__add_stamp({
  type: "CRITIC_STAMP",
  agent: "blueprint-aligner-mcp",
  summary: "[TIER_2] Blueprint aligned — no deviations"
})
```

If FAIL: record via MCP:
```
mcp__task-synchronizer-mcp__add_stamp({
  type: "ALIGN_FAIL",
  agent: "blueprint-aligner-mcp",
  summary: "[TIER_2] <deviation summary> — COMMIT BLOCKED"
})
```

Commit (only after PASS): `git commit -m "[TIER_2] <description>"`

---

## Tier 3 — Full Parallel Critics (Distributed Stamping)

Spawn all critics in parallel using the `Agent` tool. Each critic is a **materialized agent file** — load its instructions via `activate_agent` and follow them exactly.

```
Agent("Run the critic_arch agent. Use mcp__task-synchronizer-mcp__add_stamp with type ARCH_PASS or ARCH_FAIL to record the result.")
Agent("Run the critic_security agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_PASS or SEC_FAIL to record the result.")
Agent("Run the critic_tests agent. Use mcp__task-synchronizer-mcp__add_stamp with type TESTS_PASS or TESTS_FAIL to record the result.")
Agent("Run blueprint-aligner-mcp align_diff(). Use mcp__task-synchronizer-mcp__add_stamp with type ALIGN_PASS or ALIGN_FAIL to record the result.")
Agent("Run the security_engineer agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_CLEARED to record the result.")
```

Expected stamps after all complete:
- `[ARCH_PASS/FAIL]` — from `critic_arch.md`
- `[SEC_PASS/FAIL]` — from `critic_security.md`
- `[TESTS_PASS/FAIL]` — from `critic_tests.md`
- `[ALIGN_PASS/FAIL]` — from `blueprint-aligner-mcp`
- `[SEC_CLEARED]` — from `security_engineer.md`

### After All Critics Complete → Trigger review_synthesizer

Do NOT write `[CRITIC_STAMP]` manually. Instead, invoke `review_synthesizer`:
```
activate_agent("review_synthesizer")
```

`review_synthesizer` reads all distributed stamps (`[ARCH_PASS]`, `[SEC_PASS]`, `[TESTS_PASS]`,
`[ALIGN_PASS]`), aggregates findings, and writes the final `[CRITIC_STAMP]` + release verdict.

If all gates clear, `review_synthesizer` also appends to `.ai/LOG.md`:
```
[UACS_VERIFIED] YYYY-MM-DD | Tier 3 review complete — all gates passed
```

Then run: `ai test --vibe` (mandatory for Tier 3 before commit).

Commit: `git commit -m "[TIER_3] <description>"`
