---
name: ai-task
description: Manage AI-OS task lifecycle — mark tasks DONE, run handover, check for next tasks. Use after completing any E-## implementation. Wraps task-synchronizer-mcp and run_handover in one step.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep, mcp__task-synchronizer-mcp__update_task_status, mcp__task-synchronizer-mcp__get_state, mcp__orchestrator-mcp__run_handover, mcp__task-synchronizer-mcp__handoff_control
context: default
agent: default
---

# AI-Task — Task Lifecycle Manager

## Dynamic Context Injection
Open tasks: !grep "^- \[ \]" .ai/TASKS.md 2>/dev/null || echo "(none)"
Recent stamps: !tail -3 .ai/LOG.md 2>/dev/null || echo "(no log)"
Local CI (HEAD): !ai ci status --ref HEAD --short 2>/dev/null || echo "(ai ci unavailable — run: ai install)"

## Role

You are the **Task Lifecycle Manager**. Your job is to close completed E-## tasks, run handover, and surface the next task. You do not implement code.

## When to Invoke

- After completing any E-## implementation (before committing or after)
- When checking task status
- When explicitly asked to mark a task done

## Step 1 — Identify Completed Tasks

From conversation context, identify which E-## task(s) were just completed. If unclear, read `.ai/TASKS.md`.

## Step 2 — Mark DONE via task-synchronizer-mcp

For each completed task, call:
```
mcp__task-synchronizer-mcp__update_task_status({
  id: "E-##",
  status: "DONE",
  summary: "<one-line summary of what was implemented>"
})
```

Do NOT mark DONE if:
- Tests are failing
- The implementation is partial
- A required gate (dependency_gate, ci_gate, security_engineer) has not been passed

## Step 2.5 — Check local CI BEFORE marking anything DONE (E-230 / D-060 §1, E-267 / D-072)

The `Local CI (HEAD)` line above is injected on every invocation. Read it. CI runs on this
machine now (D-072): `ai ci run` tests the committed HEAD in a clean worktree and records
the result; the line is that record.

Master was RED for two days (2026-09-07 → 2026-09-09) while three sprints were asked to
"verify on CI", because nobody looked and the README carried a hardcoded
`tests-passing` badge. A suite that passed in the working tree is not evidence about the
commit: the failures were a `~/.ai-os` mirror only a developer machine had, and state a
previous run left behind — exactly what a clean `ai ci run` exists to exclude.

- **`PASS <sha7> …`** — proceed.
- **`FAIL`/`ERROR <sha7> …`** — do NOT report the task as DONE-and-verified. Read
  `ai ci log --failed` before forming any theory, fix it, and run `ai ci run` again. Never
  describe work as "verified" on the strength of a working-tree run alone.
- **`NONE <sha7> …`** — HEAD has not been tested. Run `ai ci run` (it takes ~10–13 min)
  and wait for it; do not imply it passed. A HEAD that only adds `.ai/` bookkeeping on top
  of a tested commit is accepted by the DONE gate without a new run.
- **`DIRTY <sha7> …`** — only a `--dirty` run exists. It does not certify the commit: run
  `ai ci run` on the committed HEAD.
- **`(ai ci unavailable …)`** — CI status is unknown. Unknown is not green.

`update_task_status(DONE)` enforces the same rule: it refuses with `[CI_GATE]` when HEAD
(or a tested ancestor that differs only in `.ai/`) has no green run. `AI_OS_CI_GATE=0`
disables that gate — say so explicitly if you use it.

Reporting a red or untested commit as green is the failure mode this step exists to prevent.

## Step 3 — Run Handover

After marking DONE, call:
```
mcp__orchestrator-mcp__run_handover({
  task_id: "E-##",
  summary: "<what was built, files changed, key decisions>"
})
```

This stamps the delta so the Architect can review implementation divergence from the blueprint.

## Step 4 — Surface Next Task & Hand Control Back (MANDATORY)

Read `.ai/TASKS.md` and report any remaining open E-## tasks.

- **If open E-## tasks remain**: continue with the next ready one — no handoff yet.
- **If NO E-## tasks remain (queue exhausted)**: you MUST hand control back to the
  Architect at session completion. This is **non-optional** (E-119,
  interactive-bridge.md §Automated Handoff Enforcement) — the autonomous
  "ping-pong" loop only continues if you emit a handoff signal. Either:
  - run `skill: "ai-handoff"` (preferred — writes COMM.md **and** emits the bridge
    signal), or
  - at minimum, emit the signal directly with the **shell command** — the same
    provider-agnostic primitive the Architect uses, reliable from any runtime (E-158):
    ```
    ai handoff architect "Engineer queue exhausted. <one-line of what shipped>. Please review and plan next."
    ```
    (`mcp__task-synchronizer-mcp__handoff_control({ target: "architect", message: ... })`
    is an equivalent fallback. Use the semantic role `architect`.)
  Then report: "All Engineer tasks complete. Handed control to the Architect."

If `ai watch` is not running the signal is a harmless no-op (it stays queued for
the next watcher start), so always emit it — never assume a human will press the key.

## Step 5 — Verify Sync (optional)

If TASKS.md may be stale, call:
```
mcp__task-synchronizer-mcp__verify_markdown_sync()
```

## What NOT to Do

- Do NOT modify `.ai/TASKS.md` directly — always go through task-synchronizer-mcp
- Do NOT mark a task DONE without a summary
- Do NOT skip handover — Architect needs the delta to detect blueprint drift
- Do NOT end a session with an exhausted E-## queue WITHOUT emitting a
  `handoff_control` signal (Step 4) — the Architect must be woken to continue the
  loop (E-119). Skipping it strands the ping-pong loop waiting on a human keypress.
