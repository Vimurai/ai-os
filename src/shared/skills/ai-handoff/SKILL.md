---
name: ai-handoff
description: Produce a structured handoff packet for Gemini↔Claude transitions. Reads unread deltas from state, formats blueprint divergence and decisions into .ai/COMM.md. Use before switching agents.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Edit, mcp__task-synchronizer-mcp__get_state, mcp__task-synchronizer-mcp__mark_deltas_read, mcp__task-synchronizer-mcp__verify_markdown_sync
context: default
agent: default
---

# AI-Handoff — Gemini↔Claude Context Bridge

## Dynamic Context Injection
Unread deltas: !python3 -c "import json; s=json.load(open('.ai/state.json')); [print(d['task_id'],':',d['summary']) for d in s.get('deltas',[]) if not d.get('read')]" 2>/dev/null || echo "(none)"
Last COMM.md entry: !tail -5 .ai/COMM.md 2>/dev/null || echo "(no COMM.md)"

## Role

You are the **Handoff Coordinator**. Your job is to produce a clear, structured transition message so the receiving agent (Gemini or Claude) can orient immediately without re-reading the entire conversation.

## When to Invoke

- Claude → Gemini: after completing E-## work, before asking Gemini to review or plan next
- Gemini → Claude: after writing new blueprints or P-## tasks, before Claude starts implementing
- Any time context may be stale between agents

## Step 0 — Verify state is consistent before packaging the handoff

Never hand off an inconsistent state to the receiving agent. Run:

```
mcp__task-synchronizer-mcp__verify_markdown_sync()
```

- `[SYNC_PASS]` — continue to Step 1.
- `[SYNC_FAIL]` — the anomalies almost always mean a task was implemented
  but never marked `DONE`. Resolve every `is [x] but OPEN in state` /
  `is [ ] but DONE in state` anomaly **first** — either mark the task
  `DONE` via `update_task_status` (if the work is genuinely complete) or
  flip the checkbox back to `[ ]` in your COMM.md narrative (if the
  receiving agent should pick it up).

Rationale: COMM.md is the receiving agent's source of truth for "what
just happened." If state and markdown disagree, the next agent will plan
against a fiction. Catch it here.

## Step 1 — Gather Handoff Data

Read:
1. `.ai/TASKS.md` — what was just completed, what's next
2. `.ai/state.json` → `deltas` array — unread implementation deltas
3. `.ai/DECISIONS.md` last entry — key decisions made
4. `git log --oneline -5` — recent commits

## Step 2 — Write COMM.md Entry

Append to `.ai/COMM.md` (create if missing):

```markdown
---
## Handoff — YYYY-MM-DD HH:MM UTC
**From**: Claude (Engineer) → Gemini (Architect)   [or reverse]
**Trigger**: E-## complete / P-## written / [reason]

### What was built
- <bullet per task completed, with files changed>

### Decisions made
- <any D-### from DECISIONS.md not yet in architect.md>

### Blueprint divergence (if any)
- <list any implementation detail that differs from the blueprint>
- NONE — implementation matched blueprint exactly

### Next action needed
- <what the receiving agent should do: review delta / write P-## / implement E-## / etc.>

### Open risks
- <any unresolved risks the receiving agent should know about>
---
```

## Step 3 — Mark Deltas Read (Claude→Gemini only)

After writing COMM.md, if handing off to Gemini, mark deltas read so they don't repeat:
```
mcp__task-synchronizer-mcp__mark_deltas_read()
```

## Step 4 — Confirm

Report:
> "Handoff written to .ai/COMM.md. Switch to [Gemini/Claude] and run `skill: 'ai-sync-state'` to pick up context."

## What NOT to Do

- Do NOT overwrite COMM.md — always append
- Do NOT skip divergence section — even "NONE" must be stated explicitly
- Do NOT call mark_deltas_read when handing off TO Claude (Gemini should review them first)
