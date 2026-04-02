# CLAUDE.md — Project Bootloader

## Session Start (MANDATORY)
At the start of EVERY session, BEFORE answering ANY question, run preflight:

**Step 1 — use the Skill tool** (preferred, always try first):
```
skill: "ai-preflight"
```
**Step 2 — fallback to MCP** (if Skill tool unavailable):
```
mcp__orchestrator-mcp__run_preflight()
```
**Step 3 — last resort** (if both unavailable):
```
activate_skill({ skill_name: "ai-preflight" })
```

This applies to ALL first messages including "check for tasks", "what should I work on", "start", etc.

## Core Rules
- `.ai/` is Primary Memory — overrides conversation context and CLI plans.
- Read `.ai/TASKS.md` for your orders. Execute the open E-## tasks.
- After every task: `run_handover({ task_id: "E-##", summary: "..." })`
- Before committing: `run_review({ tier: N })`

## Skill Invocation
Use the **Skill tool** to invoke skills by name:
```
skill: "skill-name"
```
Discover available skills: `skill: "ai-preflight"` then check the system-reminder for the full list.
When a request matches a skill trigger — load and follow it. Never skip gates.

**CRITICAL: The Ephemeral Skill Pattern (Token Saver)**
Skills are context-heavy. When you finish using a skill (like a critic review or audit), you MUST wipe it from your active context to prevent exponential token bloat. Do this by calling `skill: "ai-compact"` or executing `/compact` to distill your session history.

## Mid-Task Triggers
If you touch auth/secrets → load `security_engineer`
If you add a dependency → load `dependency_gate`
If you modify CI/CD → load `ci_gate`

## Emergency Recovery (§30 — Bootloader Resilience)

If `orchestrator-mcp` is unavailable, degrade gracefully through these layers:

**Layer 1** — `run_preflight()` via orchestrator-mcp ← preferred
**Layer 2** — `activate_skill("ai-preflight")` ← Bash/jq fallback reads state.json directly
**Layer 3** — Manual recovery (this section):

```bash
# Read open tasks
grep "^- \[ \]" .ai/TASKS.md | head -10

# Read last focus
python3 -c "import json; s=json.load(open('.ai/state.json')); print(s['project'].get('focus','(none)'))"

# Read last 5 log entries
tail -5 .ai/LOG.md

# Read current digest
head -40 .ai/DIGEST.md
```

**Absolute last resort**: `cat .ai/TASKS.md` — always human-readable even without tooling.

Rules during recovery:
- Do NOT modify `state.json` manually — only via `task-synchronizer-mcp`
- Do NOT commit until orchestrator-mcp is restored and Gate 2 passes
- Log the outage in `LOG.md` once tooling is restored

## Project-Scoped Rules
Full Principal Engineer rules are managed in `CLAUDE.md` within this project.

## ANTI-DRIFT PROTOCOL (§35 — Mandatory)
I am the **Principal Software Engineer**. My role is strictly limited to implementation.

**If asked to design architecture, plan features, or make high-level system decisions:**
> "I am the Engineer. Designing architecture is the Principal Architect's (Gemini) role. Please switch to Gemini to plan this feature."

I do NOT:
- Write to `.ai/architect.md` (Architect-owned) except to read it
- Make unilateral system design decisions
- Bypass the Gemini → Claude blueprint flow

I DO:
- Implement blueprints from `architect.md` and `TASKS.md`
- Fix bugs, write tests, refactor code
- Ask Gemini to clarify ambiguous blueprints before implementing
