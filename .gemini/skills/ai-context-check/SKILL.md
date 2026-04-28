---
name: ai-context-check
description: Proactively check context health before starting a large task. Wraps archive-manager-mcp check_context_health. Warns before token bloat hits and recommends ai-compact or /clear.
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, mcp__archive-manager-mcp__check_context_health
context: default
agent: default
---

# AI-Context-Check — Proactive Context Health

## Dynamic Context Injection
SESSION.md lines: !wc -l < .ai/SESSION.md 2>/dev/null || echo "0"
LOG.md lines: !wc -l < .ai/LOG.md 2>/dev/null || echo "0"

## Role

You are the **Context Health Monitor**. Your job is to measure context load and recommend action before the session degrades — not after.

## When to Invoke

- At the start of any task estimated to touch > 3 files
- Before a long implementation sprint (multiple E-## tasks)
- When the user says the session feels slow or responses are getting long
- Proactively after every 3rd E-## task completed in a session

## Step 1 — Run Health Check

```
mcp__archive-manager-mcp__check_context_health()
```

This returns:
- `session_lines`: current SESSION.md line count
- `token_estimate`: estimated tokens in active context
- `needs_archive`: boolean
- `recommendation`: suggested action

## Step 2 — Interpret and Act

| Condition | Action |
|---|---|
| `needs_archive: false`, tokens < 8000 | Green — proceed normally |
| `needs_archive: false`, tokens 8000–10000 | Yellow — warn user, suggest `/clear` between unrelated tasks |
| `needs_archive: true` OR tokens > 10000 | Red — STOP, run `skill: "ai-compact"` before proceeding |
| SESSION.md > 200 lines | Red — run `skill: "ai-compact"` immediately |
| LOG.md > 180 lines | Orange — warn, `skill: "ai-archive"` approaching |

## Step 3 — Report

Output a one-line health summary:
```
[CONTEXT] Green | Session: 45 lines | Tokens: ~4200 | Proceed normally.
[CONTEXT] Yellow | Session: 120 lines | Tokens: ~9100 | Consider /clear after this task.
[CONTEXT] Red | Session: 210 lines | Tokens: ~14000 | Run skill: "ai-compact" NOW.
```

## Step 4 — If Red, Block and Compact

If status is Red:
1. Do NOT start the next task
2. Invoke: `skill: "ai-compact"`
3. After compact, re-run this check to confirm Green before proceeding

## What NOT to Do

- Do NOT invoke `ai-compact` on Yellow — only warn
- Do NOT block the user on Green — just report and move on
- Do NOT read SESSION.md contents — only count lines
