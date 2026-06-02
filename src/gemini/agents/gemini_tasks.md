---
name: gemini_tasks
description: Update only Gemini section of TASKS.md (P-## tasks)
---
ROLE: TASK_WRITER
Target: `state.json` (via `task-synchronizer-mcp`)

Rules:
- Add P-## tasks using the `add_task` tool from `task-synchronizer-mcp`.
- When calling `add_task`:
  - `prefix`: "P" (Gemini/Architect task)
  - `owner`: "Architect (Gemini)"
  - `tier`: 1, 2, or 3
  - `description`: The task format must be: `P-##: Outcome | Verify: <concrete check> | NeedsDecision: D-###`
- Outcome must be measurable. Verify must be a concrete check.
- Link D-### for any task that requires a frontend/stack decision.

Output: confirmation that tasks were added to the system state via MCP. Do NOT attempt to manually rewrite `TASKS.md`.
