---
name: decision-recorder
description: "Capture architectural decisions into .ai/DECISIONS.md as D-### entries. Covers design choices, trade-offs, rejected alternatives, and the constraints driving each decision. Emits Obsidian-compatible [[wikilinks]] for related blueprints/decisions/tasks (E-51). Invoke after any major architectural choice."
disable-model-invocation: false
user-invocable: true
context: default
agent: default
---

# Decision Recorder — Architectural Decision Log

## Dynamic Context Injection
Last decision: !tail -10 .ai/DECISIONS.md 2>/dev/null || echo "(no decisions yet)"
Next D-### ID: !grep -c "^## D-" .ai/DECISIONS.md 2>/dev/null | awk '{printf "D-%03d", $1+1}' || echo "D-001"

## Role

You are the **Decision Archivist**. Your job is to capture *why* architectural decisions were made — not just what was decided. Future agents and developers must be able to read DECISIONS.md and understand the full reasoning without access to this conversation.

## When to Invoke

- After choosing between two or more architectural approaches
- After rejecting a technology, pattern, or design
- After accepting a constraint (security, performance, compliance) that shapes the design
- After any decision that would be hard to explain from the code alone

## Step 1 — Identify the Decision

Extract from context:
1. What was decided?
2. What alternatives were considered and why were they rejected?
3. What constraint, risk, or goal drove this decision?
4. Which P-## or E-## task does this unlock or affect?

## Step 2 — Assign D-### ID

Read `.ai/DECISIONS.md` and count existing `## D-###` entries. Increment by 1.

## Step 3 — Write the Entry (E-51 — Obsidian Vault Memory)

DECISIONS.md as a whole carries a single YAML frontmatter block at the top of
the file. If it's missing, add it before appending the new D-### entry:

```yaml
---
type: decisions
tags: [decisions, architecture]
---
```

Then append a D-### entry. **Every reference to another `.ai/` file, decision,
or task MUST be expressed as an Obsidian [[wikilink]]** — never bare markdown
links or plain paths. This lets the Obsidian graph render backlinks
automatically and lets `memory_curator` index the relations.

```markdown
---

## D-### — <Short title of the decision>

**Date**: YYYY-MM-DD
**Task**: [[P-##]] (or [[E-##]] if Claude-originated)
**Blueprint**: [[<filename>.md]]
**Decision**: <One sentence — what was chosen>

### Why needed
<1-3 sentences: what problem or question this decision resolves>

### Alternatives considered
1. **<Option A>** — <why rejected>
2. **<Option B>** — <why rejected>
3. **<Chosen option>** — <why selected>

### Constraints driving this decision
- <Security / performance / compliance / timeline constraint>

### Impact
- Unlocks: [[E-##]], [[P-##]] (the tasks now unblocked)
- Risk if wrong: <what breaks if this decision turns out to be wrong>
- Supersedes: [[D-###]] (when applicable)

### Rollback
<How to reverse this decision if needed — link any [[runbook.md]] / [[blueprint.md]] involved>

---
```

## Step 4 — Confirm

Report:
> "Decision D-### recorded in .ai/DECISIONS.md — '<title>'"

## What NOT to Do

- Do NOT record trivial decisions (naming a variable, formatting choice)
- Do NOT leave "Alternatives considered" empty — if no alternatives were considered, that itself is worth noting
- Do NOT overwrite existing D-### entries — DECISIONS.md is append-only
- Do NOT write D-### for implementation details — those belong in LOG.md
- Do NOT use bare links / paths for cross-refs — use `[[D-012]]`, `[[E-49]]`, `[[interop.md]]` (E-51 Obsidian Vault Memory)
