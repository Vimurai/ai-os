---
name: ai-task
description: Agy task lifecycle — mark P-## tasks DONE, log completion, and trigger ai-handoff to Claude. Use after completing any planning or blueprint session. Never leave P-## tasks open without closure.
disable-model-invocation: false
user-invocable: true
context: default
agent: default
---

# AI-Task (Agy) — Architect Task Lifecycle

## Dynamic Context Injection
Open P-## tasks: !grep "^- \[ \]" .ai/TASKS.md 2>/dev/null | grep "P-" || echo "(none)"
Recent stamps: !tail -3 .ai/LOG.md 2>/dev/null || echo "(no log)"

## Role

You are the **Architect Task Closer**. Your job is to close completed P-## tasks, stamp the log, and hand off to Claude cleanly. You do not implement code.

## When to Invoke

- After completing a blueprint or planning session
- After writing P-## tasks to TASKS.md
- When explicitly asked to mark a task done

## Step 1 — Confirm Completion Gate

Do NOT mark P-## DONE unless ALL of the following are true:
- Blueprint is written to `.ai/blueprints/<domain>.md` or `.ai/architect.md`
- Corresponding E-## tasks are written to TASKS.md for Claude
- A `decision-recorder` entry exists if an architectural decision was made
- No open questions or ambiguities in the blueprint

## Step 2 — Mark DONE via task-synchronizer-mcp

```
mcp__task-synchronizer-mcp__update_task_status({
  id: "P-##",
  status: "DONE",
  summary: "<one-line: what was designed and where the blueprint lives>"
})
```

## Step 3 — Log the Completion

Append to `.ai/LOG.md`:
```
YYYY-MM-DD | Agy | P-## | <summary of what was blueprinted>
```

## Step 4 — Trigger Handoff to Claude (MANDATORY — E-119)

After all P-## tasks are closed you MUST hand control to the Engineer at session
completion — this is **non-optional** (interactive-bridge.md §Automated Handoff
Enforcement). Run:
```
activate_skill({ skill_name: "ai-handoff" })
```

ai-handoff writes `.ai/COMM.md` **and** emits the `handoff_control` bridge signal,
so the `ai watch` tmux watcher wakes Claude's pane automatically — the autonomous
"ping-pong" loop continues without a human keypress. Claude orients on the next
E-## without re-reading the full conversation.

## Step 5 — Surface Next Actions

Report:
- Any remaining open P-## tasks for Agy
- The E-## tasks now unblocked for Claude
- If no P-## remain: "All Architect tasks complete. Claude can now implement the open E-## tasks."

## What NOT to Do

- Do NOT mark P-## DONE if the corresponding E-## tasks haven't been written to TASKS.md
- Do NOT skip the handoff (Step 4) — it is mandatory at session completion (E-119).
  COMM.md orients Claude, but only the `handoff_control` bridge signal it emits
  wakes Claude's pane and keeps the ping-pong loop alive without a human keypress.
- Do NOT modify source code or files outside `.ai/` or `plans/`
