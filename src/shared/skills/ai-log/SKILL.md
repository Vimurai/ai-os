---
name: ai-log
description: Append a structured entry to .ai/LOG.md after any significant action. Enforces RULES §4 mandate. Checks if LOG.md exceeds 200 lines and triggers ai-archive warning if so.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Edit
context: default
agent: default
---

# AI-Log — LOG.md Maintenance

## Dynamic Context Injection
Log line count: !wc -l < .ai/LOG.md 2>/dev/null || echo "0"
Last 3 entries: !tail -3 .ai/LOG.md 2>/dev/null || echo "(empty)"

## Role

You are the **Log Keeper**. Your job is to append one structured entry to `.ai/LOG.md` per significant action and warn if the log is approaching the archive threshold.

## When to Invoke

- After completing any E-## task (in addition to `ai-task`)
- After any significant file modification not covered by a hook
- After a gate decision (dependency_gate, ci_gate, security_engineer)
- After a blueprint deviation or architectural decision

## Step 1 — Compose the Entry

Format:
```
YYYY-MM-DD | <Actor> | <Task-ID or action> | <one-line summary of what happened>
```

Rules:
- Actor: `Claude` (Engineer) or `Gemini` (Architect)
- Task-ID: use `E-##` or `P-##` if tied to a task; otherwise use the action name (e.g. `dependency_gate`, `ci_gate`, `hotfix`)
- Summary: what changed and why — not how. Max 120 characters.
- Never duplicate an entry already in LOG.md for the same action.

Examples:
```
2026-04-14 | Claude | E-1 | Added root package.json with npm workspaces; sdk hoisted to root
2026-04-14 | Claude | dependency_gate | Approved @modelcontextprotocol/sdk upgrade to ^1.1.0 — no CVEs
2026-04-14 | Gemini | P-4 | Designed workspace blueprint in .ai/blueprints/workspace.md
```

## Step 2 — Append to LOG.md

Use Edit or Bash append — never overwrite:
```bash
echo "YYYY-MM-DD | Actor | Task | Summary" >> .ai/LOG.md
```

## Step 3 — Check Archive Threshold

```bash
wc -l < .ai/LOG.md
```

If line count ≥ 200:
> "LOG.md has reached 200 lines. Run `skill: 'ai-archive'` to archive and reset before continuing."

If line count is between 180–199:
> "LOG.md is at <N> lines — approaching archive threshold (200). Consider running `ai-archive` soon."

## What NOT to Do

- Do NOT rewrite or truncate LOG.md — it is append-only
- Do NOT log trivial reads or tool calls that have no state impact
- Do NOT log the same action twice
