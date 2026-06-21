---
name: ai-sync-verify
description: Verify TASKS.md / REVIEWS.md agree with state.sqlite. Wraps task-synchronizer-mcp verify_markdown_sync (SYNC_PASS/SYNC_FAIL) — a top-5 high-frequency MCP tool used in every project (E-178). Use before trusting TASKS.md or claiming work is done.
disable-model-invocation: false
user-invocable: true
allowed-tools: mcp__task-synchronizer-mcp__verify_markdown_sync
context: default
agent: default
---

# AI-Sync-Verify — Markdown ↔ State Failsafe

## Why This Skill Exists

`verify_markdown_sync` runs in essentially every AI-OS session (300 calls across 260
projects in the last meta-cognition window) — it is the failsafe that catches the most
common bookkeeping bug: you shipped a feature but forgot to mark the task DONE, so
`TASKS.md` and `state.sqlite` disagree. This skill is the one-step wrapper.

## When to Invoke

- During preflight, before trusting the open-task list (DIGEST-first read order, Step 4)
- Before claiming any work is "done" in a new session
- After the other agent (Architect ↔ Engineer) edited `.ai/` files
- Before a commit, as part of the review gate

## Step 1 — Verify

```
mcp__task-synchronizer-mcp__verify_markdown_sync()
```

The tool auto-regenerates `TASKS.md` / `REVIEWS.md` when rows are missing from one side,
but it intentionally does **not** auto-fix checkbox-vs-status mismatches — those mean a
human/agent decision is required.

## Step 2 — Interpret

Parse the `__SYNC_RESULT__` JSON tail (`{status, anomalies, auto_fixes}`):

| Result | Action |
|---|---|
| `[SYNC_PASS]` | Proceed normally — markdown agrees with state |
| `[SYNC_FAIL]` + `is [x] in TASKS.md but OPEN in state` | You forgot `update_task_status` — mark it DONE (via `skill: ai-task`) |
| `[SYNC_FAIL]` + `is [ ] but DONE in state` | Reopen or re-mark via task-synchronizer |
| `auto_fixes` listed | Note what was regenerated; no action needed |

## Step 3 — Report

```
[SYNC-VERIFY] PASS — TASKS.md ↔ state.sqlite in sync.
[SYNC-VERIFY] FAIL — 1 anomaly: E-178 is [x] but OPEN in state. Fix via skill: ai-task.
```

## Rules

- This skill is read-only over your task state — it never marks a task DONE. To resolve a
  `[x]-but-OPEN` anomaly, route through `skill: ai-task` (never call `update_task_status`
  directly, per the bootloader Task Lifecycle rule).
- A `SYNC_FAIL` blocks "done" claims until resolved.
