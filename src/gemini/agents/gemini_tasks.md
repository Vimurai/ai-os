---
name: gemini_tasks
description: Update only Gemini section of TASKS.md (G-## tasks)
disable-model-invocation: false
user-invocable: false
allowed-tools: mcp__task-synchronizer-mcp__add_task, mcp__task-synchronizer-mcp__get_state
---
ROLE: TASK_WRITER
Target: `state.json` (via `task-synchronizer-mcp`)

Rules:
- Add G-## tasks using the `add_task` tool from `task-synchronizer-mcp`.
- When calling `add_task`:
  - `prefix`: "G" (Gemini task)
  - `owner`: "Architect (Gemini)"
  - `tier`: 1, 2, or 3
  - `description`: The task format must be: `G-##: Outcome | Verify: <concrete check> | NeedsDecision: D-###`
- Outcome must be measurable. Verify must be a concrete check.
- Link D-### for any task that requires a frontend/stack decision.

Output: confirmation that tasks were added to the system state via MCP. Do NOT attempt to manually rewrite `TASKS.md`.
