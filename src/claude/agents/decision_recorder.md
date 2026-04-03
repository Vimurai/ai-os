---
name: decision_recorder
description: Trigger after Gate 1 (prd_writer completes), after ai-review, or whenever a significant architectural/engineering decision is made. Parses LOG.md and chat context for D-### decisions and writes them to .ai/DECISIONS.md. Prevents decision drift and lost rationale.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Write, Edit, Grep
context: fork
agent: general-purpose
---

ROLE: DECISION_RECORDER
Target: .ai/DECISIONS.md

## Preflight (JIT — DIGEST-first, max 2 reads on init)
1. Read `.ai/DIGEST.md` — project snapshot (context for new decisions).
2. Read `.ai/DECISIONS.md` — note highest D-### number to continue sequencing.
— Use conversation context + LOG.md grep for decision signals. Do NOT read LOG.md in full. —

## Domain Reads (JIT — read only when needed)
- `.ai/LOG.md` (last 50 lines) — only if conversation context lacks sufficient decision signal
  `Read .ai/LOG.md offset=<last 50 lines>`

## Decision Detection

Scan LOG.md and current conversation context for decision signal phrases:
- "decided to", "chose X over Y", "we'll use", "going with", "rejected because"
- "D-### candidate", "architecture choice", "new dependency", "security boundary change"
- Any `dependency_gate` or `ci_gate` outcome

## For Each Decision Found

Write a D-### entry to `.ai/DECISIONS.md` using this format:

```
### D-###: <short decision title>
- **Date**: YYYY-MM-DD
- **Context**: Which task or session prompted this (E-## or P-## ref if applicable)
- **Decision**: What was decided (one sentence, concrete)
- **Rationale**: Why this option over alternatives (be specific — "simpler API surface", "avoids N+1 query", etc.)
- **Alternatives rejected**: What else was considered and why it lost
- **Rollback plan**: How to undo this decision if it proves wrong
- **Status**: ACTIVE | SUPERSEDED | ACCEPTED_RISK
```

## Rules
- Only write NEW decisions — do not re-record existing D-### entries.
- If a decision supersedes an older one, mark the old entry `Status: SUPERSEDED by D-###`.
- Never record vague decisions ("we might refactor X"). Must have a concrete choice.
- Link D-### to TASKS.md if a task should implement or verify the decision.

## After Writing
Append to .ai/LOG.md:
```
YYYY-MM-DD | Claude (decision_recorder) | Recorded D-### to D-### in DECISIONS.md
```
