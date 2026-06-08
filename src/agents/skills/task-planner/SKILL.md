---
name: task-planner
description: Gate before writing P-## or E-## tasks to TASKS.md. Enforces tier, actionable description (verb required), blueprint reference, acceptance criteria, and no circular dependencies. Blocks vague tasks.
disable-model-invocation: false
user-invocable: true
context: default
agent: default
---

# Task Planner — Task Quality Gate

## Dynamic Context Injection
Current tasks: !grep "^- \[" .ai/TASKS.md 2>/dev/null | tail -10 || echo "(none)"
Last task ID: !grep -oE "[EP]-[0-9]+" .ai/TASKS.md 2>/dev/null | sort -t- -k2 -n | tail -1 || echo "(none)"

## Role

You are the **Task Quality Enforcer**. Your job is to ensure every task written to TASKS.md is actionable, tiered, and traceable before Claude picks it up. Vague tasks produce vague implementations.

## When to Invoke

- Before writing any P-## or E-## task to TASKS.md
- After completing a blueprint (to generate the corresponding E-## tasks)
- When reviewing existing tasks for quality

## Step 1 — Draft Tasks

Write tasks in-context first. Do NOT write to TASKS.md yet.

## Step 2 — Validate Each Task

Every task must pass ALL checks:

### Check 1: Tier is set
- `Tier: 1` — trivial change, no review needed
- `Tier: 2` — standard feature, blueprint-aligner review
- `Tier: 3` — security/auth/data, full critic suite required
- **BLOCK** if tier is missing

### Check 2: Description has an action verb
The description must start with or contain an imperative verb:
- ✓ "Implement the monorepo workspace structure..."
- ✓ "Create .ai/blueprints/auth.md..."
- ✓ "Refactor task-synchronizer-mcp to use SQLite..."
- ✗ "Monorepo workspace structure" (no verb — BLOCK)
- ✗ "The auth system" (no verb — BLOCK)

### Check 3: Blueprint or acceptance criteria referenced
Every E-## task must reference where Claude should look for details:
- ✓ `per .ai/blueprints/workspace.md`
- ✓ `per .ai/architect.md §4`
- ✓ `Acceptance: all tests pass, TASKS.md synced`
- **BLOCK** if E-## task has no reference and no acceptance criteria

### Check 4: No circular dependencies
If task A says "Unblocks: B" and task B says "Unblocks: A" → circular. **BLOCK**.
Maximum dependency chain depth: 5 hops.

### Check 5: No duplicate task
Search TASKS.md for a task covering the same scope. If one exists:
- If it's OPEN → do not create a duplicate, reuse it
- If it's DONE → proceed with the new task

## Step 3 — Assign IDs

Read current TASKS.md and increment:
- P-## for Gemini/Architect tasks
- E-## for Claude/Engineer tasks

Never reuse a completed task ID.

## Step 4 — Classify the Workspace (E-64 — Framework Routing)

Before writing the task, decide *where* it belongs. AI-OS framework changes
must not pollute downstream project queues (the misclassification class
captured in `.ai/blueprints/task-routing.md`).

A task is **framework-level** (`is_framework_task: true`) if any of the
following is true:

- It mutates files under `~/.ai-os/` or any path inside the canonical
  `ai-os-v2/src/**` clone (MCP servers, shared skills, agents, scripts,
  installer, hooks, registry, schemas).
- It edits `.ai/blueprints/*.md` *for the framework itself* — i.e. the
  blueprint sits inside the AI-OS clone, not the consuming project.
- The task description names a framework component without a project-
  specific feature (e.g. "Update task-synchronizer-mcp", "Fix bin/ai
  locator chain", "Add new skill to shared/skills").

A task is **project-level** (`is_framework_task` omitted/false) if it
touches `<project>/src/**`, application code, or anything outside the
framework clone — even if it imports an AI-OS skill or MCP.

**Ambiguous?** Default to project-level and note the ambiguity in the
description. Mis-routing a project task into the framework workspace is a
worse failure than the reverse (it pollutes the source-of-truth).

## Step 5 — Write to TASKS.md

Format:
```markdown
- [ ] E-##: <Imperative description> per <blueprint reference>. | Tier: N
- [ ] P-##: <Imperative description> | Tier: N
```

Append under the correct section (`## Engineer (Claude)` or `## Architect (Gemini)`).

Also call `add_task` with the routing flag set per Step 4:
```
mcp__task-synchronizer-mcp__add_task({
  owner:             "Engineer (Claude)",
  description:       "...",
  tier:              N,
  prefix:            "E",
  is_framework_task: true   // ← omit or set false for project-level work
})
```

When `is_framework_task: true`, the MCP redirects the row into
`$AIOS_WORKSPACE/.ai/state.sqlite` instead of the local `.ai/`. If the env
is unset or invalid the call returns `[WORKSPACE_NOT_FOUND]` — do not
retry without the flag; surface the error so the user can re-run
`install-ai-os.sh` from the framework clone.

## Step 6 — Confirm

Report:
> "N tasks written to TASKS.md: [E-## list]. All passed quality gate.
>  Framework-routed: [E-## list, or 'none']."

## What NOT to Do

- Do NOT write tasks without a tier
- Do NOT write E-## tasks without a blueprint reference
- Do NOT write tasks in passive voice ("should be done", "needs to be")
- Do NOT skip the circular dependency check for chains > 2 hops
- Do NOT file framework-level tasks (changes to `~/.ai-os/` or
  `ai-os-v2/src/**`) into a downstream project's queue — set
  `is_framework_task: true` per Step 4 so the MCP routes them to the
  canonical AI-OS clone.
