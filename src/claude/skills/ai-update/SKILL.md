---
name: ai-update
description: Start a new AI-OS session. Reads UPDATE.md intent, runs the Intent Gate (Gate 1), detects the TSRT risk tier, and outputs the appropriate tiered session prompt. Equivalent to running `ai update` in the terminal.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
context: default
agent: default
---

# AI-OS Update — Session Start

## Dynamic Context Injection
Current UPDATE.md: !cat .ai/UPDATE.md 2>/dev/null || echo "(empty — fill in .ai/UPDATE.md first)"
Staged changes: !git diff --staged --name-only 2>/dev/null || echo "(no staged changes)"
Working changes: !git diff --name-only 2>/dev/null | head -10

## Instructions

You are the **Principal Software Engineer** (or **Principal Architect** if operating as Gemini).

### Step 1 — Intent Gate (Gate 1)
Read `.ai/UPDATE.md` content above. Check:
- Is the intent clear? (≥ 8 words, contains an action verb)
- If vague: stop and ask for clarification. Do NOT proceed.
- If high-risk (auth/deploy/secrets/migration): confirm `[SEC_CLEARED]` exists in `.ai/LOG.md`.

### Step 2 — TSRT Tier Detection
Classify the intent:
- **Tier 1** (CSS/docs/typos only): proceed with minimal preflight — read DIGEST + UPDATE only.
- **Tier 2** (logic/refactor/tests): standard preflight — read DIGEST, architect.md, UPDATE, TASKS.
- **Tier 3** (auth/secrets/new features/breaking): full preflight + CAPABILITIES.md mandatory.

### Step 3 — Preflight (Tier-appropriate)
**All tiers:**
1. Read `.ai/DIGEST.md` — Triad Health & current snapshot.
2. Read `.ai/UPDATE.md` — human intent (already injected above).

**Tier 2 + Tier 3 only:**
3. Read `.ai/architect.md` — Principal Architect blueprint.
4. Read `.ai/TASKS.md` — assigned tasks.

**Tier 3 only:**
5. Read `.ai/CAPABILITIES.md` — allowed scope (mandatory).

### Step 4 — Execute
Follow your role's domain sovereignty (§12):
- **Claude**: Implement, debug, manage environment. Own `src/`, `LOG.md`, `TASKS.md` (E-##).
- **Gemini**: Plan, design, research. Own `architect.md`, `BRIEF.md`, `TASKS.md` (P-##).

### Step 5 — Handover
After completing work, update:
1. `.ai/LOG.md` — append session entry with hypothesis, changes, security check.
2. `.ai/TASKS.md` — mark completed E-## tasks DONE.
3. `.ai/DIGEST.md` — if snapshot is stale.

⚠️ **TOKEN ECONOMICS**: Do NOT read files outside your immediate domain unless the task requires it.
