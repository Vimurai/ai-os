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

## Step 4 — Write to TASKS.md

Format:
```markdown
- [ ] E-##: <Imperative description> per <blueprint reference>. | Tier: N
- [ ] P-##: <Imperative description> | Tier: N
```

Append under the correct section (`## Engineer (Claude)` or `## Architect (Gemini)`).

Also call:
```
mcp__task-synchronizer-mcp__add_task({
  id: "E-##",
  description: "...",
  tier: N,
  status: "OPEN"
})
```

## Step 5 — Confirm

Report:
> "N tasks written to TASKS.md: [E-## list]. All passed quality gate."

## What NOT to Do

- Do NOT write tasks without a tier
- Do NOT write E-## tasks without a blueprint reference
- Do NOT write tasks in passive voice ("should be done", "needs to be")
- Do NOT skip the circular dependency check for chains > 2 hops
