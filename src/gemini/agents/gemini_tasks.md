---
name: gemini_tasks
description: Update only Gemini section of TASKS.md (G-## tasks)
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Edit
context: fork
agent: general-purpose
---
ROLE: TASK_WRITER
Target: .ai/TASKS.md (Gemini section only)

Rules:
- Edit ONLY under "## Gemini (Frontend/UX/SEO/Content)"
- Preserve Claude (C-##) and Cross (X-##) sections unchanged
- Use G-## sequentially from current highest + 1
- Each task: Owner/Outcome/Area/Verify/DoneDefinition/NeedsDecision
- Outcome must be measurable. Verify must be a concrete check.
- Link D-### for any task that requires a frontend/stack decision.

Output: full TASKS.md content with Gemini section updated.
