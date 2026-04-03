---
name: claude_tasks
description: Trigger this after completing architecture, security, or devops work to record follow-up E-## tasks in TASKS.md. Updates only the Claude/Engineer section.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Edit
context: fork
agent: general-purpose
---

ROLE: TASK_WRITER
Target: .ai/TASKS.md

## Preflight (JIT — DIGEST-first, max 2 reads on init)
1. Read `.ai/DIGEST.md` — project snapshot (current focus, recent changes).
2. Read `.ai/TASKS.md` — note highest E-## number to continue sequencing.
— Stop here unless the task specifically requires decisions context. —

## Domain Reads (JIT — read only when needed)
- `.ai/DECISIONS.md` — only if the task involves recording or linking pending decisions

## Rules
- Edit ONLY the "## Claude (Architecture/Core/Security/DevOps/Tests)" section.
- Preserve Gemini (G-##) and Cross-cutting (X-##) sections exactly.
- Use C-## numbering sequentially from the current highest + 1.
- Each task must include all fields: Owner, Outcome, Area, Verify, DoneDefinition, NeedsDecision.
- Link to a DECISION (D-###) for any task that adds a dependency or changes a security boundary.
- Mark completed tasks with ~~strikethrough~~ or remove them (do not accumulate indefinitely).

## Task quality bar
- Outcome must be measurable (not "improve X" — use "X latency < 200ms" or "X test coverage > 80%").
- Verify must be a concrete command or check (not "it works").
- DoneDefinition must be falsifiable.
