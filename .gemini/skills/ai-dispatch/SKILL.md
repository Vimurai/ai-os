---
name: ai-dispatch
description: Compute the DAG-aware dispatch frontier — which OPEN tasks are ready (all deps DONE) vs still blocked. Wraps orchestrator-mcp run_dispatch — a top-5 high-frequency MCP tool (E-178). Use when deciding what to work on next or whether tasks can run in parallel.
disable-model-invocation: false
user-invocable: true
allowed-tools: mcp__orchestrator-mcp__run_dispatch
context: default
agent: default
---

# AI-Dispatch — DAG-Aware Task Frontier

## Why This Skill Exists

`run_dispatch` (224 calls across 32 projects in the last meta-cognition window) reads the
`depends_on` task graph and returns the **dispatch frontier**: the OPEN tasks whose
dependencies are all DONE and are therefore safe to start now, plus the tasks still
blocked (with their unmet deps), plus a recommended `dispatch_mode`. This skill is the
one-step wrapper for "what should I work on next?".

## When to Invoke

- At the start of a work session, to pick the next ready task
- After completing a task, to see what it unblocked
- Before a sprint, to decide whether several tasks can be run in parallel
- When the queue looks empty but blocked tasks may exist

## Step 1 — Dispatch

```
mcp__orchestrator-mcp__run_dispatch()
```

Optionally scope to one role with `{ owner: "engineer" }` (or `claude` / `agy` /
`tester`). The tool is **read-only** — it plans, it never mutates task state.

## Step 2 — Interpret `dispatch_mode`

| Mode | Meaning | Action |
|---|---|---|
| `parallel` | Several independent tasks ready | Pick the highest-priority ready task; note others can run concurrently |
| `sequential` | Exactly one task ready | Start it |
| `idle` | Nothing ready | Report blocked tasks + their unmet deps; surface to the Architect if the frontier is empty but work remains |

## Step 3 — Report

```
[DISPATCH] sequential | ready: E-178 | blocked: E-179 (needs E-178)
[DISPATCH] idle | 0 ready | 2 blocked — handing to Architect to unblock.
```

## Rules

- This skill never marks tasks DONE or changes dependencies — it is a planner. Use
  `skill: ai-task` to advance the lifecycle.
- Respect the frontier: do not start a task the planner reports as blocked.
