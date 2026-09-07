---
name: ai-analyze
description: Pre-flight a shell command's risk before running it. Wraps safe-exec-mcp analyze_command (PASS/WARN/BLOCK) — the #1 highest-frequency MCP tool (E-178, meta-cognition CLI-automation candidate). Use before any destructive or unfamiliar shell command.
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, mcp__safe-exec-mcp__analyze_command
context: default
agent: default
---

# AI-Analyze — Shell Command Risk Pre-Flight

## Why This Skill Exists

`analyze_command` is the single most-invoked MCP tool across all AI-OS projects
(1457 calls in the last meta-cognition window). It classifies a shell command as
**PASS / WARN / BLOCK** before it runs and enforces Triad sovereignty. This skill is
the one-step conversational wrapper so you never type the raw `mcp__safe-exec-mcp__*`
call — say "analyze this command" and invoke the skill.

## When to Invoke

- Before running any destructive command (`rm`, `git reset --hard`, `git push`, `docker`…)
- Before an unfamiliar or generated command you did not author
- Whenever the PreToolUse safe-exec gate is about to fire and you want the verdict first
- As the Architect, to confirm a command is sovereignty-clean before delegating it

## Step 1 — Analyze

```
mcp__safe-exec-mcp__analyze_command({ command: "<the exact shell command>" })
```

Do **not** pass `caller_role` manually — the bootloader injects the tamper-resistant
`AI_OS_CALLER_ROLE` (E-127/E-129) and the MCP prioritizes it over any argument. The
session's real role is used automatically.

## Step 2 — Interpret the Verdict

| Verdict | Meaning | Action |
|---|---|---|
| `PASS` | No destructive/high-risk pattern | Proceed — run the command |
| `WARN` | Risky but allowed | Surface the reasoning to the user, confirm intent, then proceed |
| `BLOCK` | Destructive or sovereignty violation | Do **not** run it. Report the reason. Propose a safe alternative |
| `[SOVEREIGNTY_BLOCK]` | Architect attempted an Engineer-only op | Hand back to the Engineer (§35) |

## Step 3 — Report

Output one line, then act:
```
[ANALYZE] PASS | `git status` — safe, running now.
[ANALYZE] BLOCK | `rm -rf /` — destructive recursive delete. Refusing.
```

## Rules

- Never run a command the analyzer returned `BLOCK` for — that defeats the gate.
- This skill is read-only over the command string; it does not execute it. You run the
  command yourself only after a PASS (or a confirmed WARN).
- For a full local pre-execution gate (exit-2 on BLOCK) use `safe-exec --check`; this
  skill is the interactive, single-command form.
