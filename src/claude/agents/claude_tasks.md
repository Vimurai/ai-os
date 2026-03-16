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

## Preflight (token-saver)
1. Read .ai/DIGEST.md.
2. Read .ai/UPDATE.md.
3. Read .ai/TASKS.md — note highest C-## number to continue sequencing.
4. Read .ai/DECISIONS.md — pending decisions may generate tasks.

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
