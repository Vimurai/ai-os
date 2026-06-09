---
name: ai-review
description: Run a tier-aware critic review before committing. Tier 1 skips review. Tier 2 runs blueprint-aligner only. Tier 3 runs full parallel critics (arch + security + tests) plus security_engineer and UACS verification. Replaces the removed `ai review claude` shell command (E-34).
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

## Tier 2 — Blueprint Aligner + Clean-Code (parallel)

Spawn both critics in parallel — they review independent surfaces (blueprint
alignment vs. code shape) and stamp their own verdicts. `review_synthesizer`
or the human operator weighs both before committing.

```
Agent("Run blueprint-aligner-mcp align_diff(). Use mcp__task-synchronizer-mcp__add_stamp with type ALIGN_PASS or ALIGN_FAIL to record the result.")
Agent("Run the critic_clean_code agent (E-81). Use mcp__task-synchronizer-mcp__add_stamp with type CLEAN_PASS, CLEAN_WARN, or CLEAN_FAIL to record the result.")
```

Expected stamps after both complete:
- `[ALIGN_PASS/FAIL]` — from `blueprint-aligner-mcp`
- `[CLEAN_PASS/WARN/FAIL]` — from `critic_clean_code.md` (E-81 — invokes E-80 standards-checker)

Pass gate (all required for [CRITIC_STAMP]):
- ALIGN must be `PASS`
- CLEAN must NOT be `FAIL` (a `CLEAN_WARN` is acceptable for Tier 2)

If both clear, record the synthesis stamp:
```
mcp__task-synchronizer-mcp__add_stamp({
  type: "CRITIC_STAMP",
  agent: "ai-review-tier2",
  summary: "[TIER_2] Blueprint aligned + clean-code gate clear — <N warnings ignored>"
})
```

If either fails, the failing critic's stamp is the COMMIT BLOCKED signal —
do not write a passing CRITIC_STAMP.

Commit (only after PASS): `git commit -m "[TIER_2] <description>"`

---

## Tier 3 — Full Parallel Critics (Distributed Stamping)

Spawn all critics in parallel using the `Agent` tool. Each critic is a **materialized agent file** — load its instructions via `activate_agent` and follow them exactly.

```
Agent("Run the critic_arch agent. Use mcp__task-synchronizer-mcp__add_stamp with type ARCH_PASS or ARCH_FAIL to record the result.")
Agent("Run the critic_security agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_PASS or SEC_FAIL to record the result.")
Agent("Run the critic_tests agent. Use mcp__task-synchronizer-mcp__add_stamp with type TESTS_PASS or TESTS_FAIL to record the result.")
Agent("Run the critic_clean_code agent (E-81). Use mcp__task-synchronizer-mcp__add_stamp with type CLEAN_PASS, CLEAN_WARN, or CLEAN_FAIL to record the result.")
Agent("Run blueprint-aligner-mcp align_diff(). Use mcp__task-synchronizer-mcp__add_stamp with type ALIGN_PASS or ALIGN_FAIL to record the result.")
Agent("Run the security_engineer agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_CLEARED to record the result.")
```

Expected stamps after all complete:
- `[ARCH_PASS/FAIL]` — from `critic_arch.md`
- `[SEC_PASS/FAIL]` — from `critic_security.md`
- `[TESTS_PASS/FAIL]` — from `critic_tests.md`
- `[CLEAN_PASS/WARN/FAIL]` — from `critic_clean_code.md` (E-81 — runs E-80 standards-checker)
- `[ALIGN_PASS/FAIL]` — from `blueprint-aligner-mcp`
- `[SEC_CLEARED]` — from `security_engineer.md`

### After All Critics Complete → Trigger review_synthesizer

Do NOT write `[CRITIC_STAMP]` manually. Instead, invoke `review_synthesizer`:
```
activate_skill("review_synthesizer")
```

`review_synthesizer` reads all distributed stamps (`[ARCH_PASS]`, `[SEC_PASS]`, `[TESTS_PASS]`,
`[ALIGN_PASS]`), aggregates findings, and writes the final `[CRITIC_STAMP]` + release verdict.

If all gates clear, `review_synthesizer` also appends to `.ai/LOG.md`:
```
[UACS_VERIFIED] YYYY-MM-DD | Tier 3 review complete — all gates passed
```

Then run: `skill: ai-test` with --vibe (mandatory for Tier 3 before commit).

Commit: `git commit -m "[TIER_3] <description>"`
