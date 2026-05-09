---
name: ai-log
description: "Append a structured entry to .ai/LOG.md after any significant action. Enforces RULES §4 mandate. Captures CLAUDE_CODE_SESSION_ID for cryptographic audit traceability (E-49). Checks if LOG.md exceeds 200 lines and triggers ai-archive warning if so."
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
Session id: !printf '%s' "${CLAUDE_CODE_SESSION_ID:-(unset)}"

## Role

You are the **Log Keeper**. Your job is to append one structured entry to `.ai/LOG.md` per significant action and warn if the log is approaching the archive threshold.

## When to Invoke

- After completing any E-## task (in addition to `ai-task`)
- After any significant file modification not covered by a hook
- After a gate decision (dependency_gate, ci_gate, security_engineer)
- After a blueprint deviation or architectural decision

## Step 1 — Compose the Entry

Format (E-49):
```
YYYY-MM-DD | <Actor> | <Task-ID or action> | <one-line summary> | session=<CLAUDE_CODE_SESSION_ID|none>
```

Rules:
- Actor: `Claude` (Engineer) or `Gemini` (Architect)
- Task-ID: when tied to a task, use the bare ID (e.g. `E-##`, `P-##`, `D-###`). For non-task actions use the bare action name (e.g. `dependency_gate`, `ci_gate`, `hotfix`).
- Summary: what changed and why — not how. Max 120 characters.
- **Session:** read `$CLAUDE_CODE_SESSION_ID` from the environment. If unset or empty, write `session=none`. Otherwise, write the value verbatim — but only if it matches the regex `[A-Za-z0-9-]{1,64}`. If it doesn't (untrusted input), write `session=invalid`.
- Never duplicate an entry already in LOG.md for the same action.

Examples:
```
2026-04-14 | Claude | E-1   | Added root package.json with npm workspaces; sdk hoisted to root | session=01J9X2A1Z3
2026-04-14 | Claude | dependency_gate | Approved @modelcontextprotocol/sdk upgrade to ^1.1.0 — no CVEs | session=none
2026-04-14 | Gemini | P-4   | Designed workspace blueprint in workspace.md | session=01J9X2A1Z3
```

## Step 2 — Append to LOG.md

Use Edit or Bash append — never overwrite. The recommended idiom captures the
session id once and validates it before composing the line:

```bash
sid="${CLAUDE_CODE_SESSION_ID:-}"
if [[ -z "$sid" ]]; then
  tag="session=none"
elif [[ "$sid" =~ ^[A-Za-z0-9-]{1,64}$ ]]; then
  tag="session=${sid}"
else
  tag="session=invalid"
fi
echo "$(date -u +%Y-%m-%d) | Actor | Task | Summary | ${tag}" >> .ai/LOG.md
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
