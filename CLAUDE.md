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
- After every task: **use `skill: "ai-task"`** — marks DONE, runs handover, surfaces next task.
- Before committing: `run_review({ tier: N })`

## Task Lifecycle (MANDATORY)
After completing ANY E-## implementation, ALWAYS run the task skill:
```
skill: "ai-task"
```
NEVER call `mcp__task-synchronizer-mcp__update_task_status` directly — always go through the skill.
The skill handles: mark DONE → run_handover → surface next task.

## Skill Invocation
Use the **Skill tool** to invoke skills by name:
```
skill: "skill-name"
```
Discover available skills: `skill: "ai-preflight"` then check the system-reminder for the full list.
When a request matches a skill trigger — load and follow it. Never skip gates.

**CRITICAL: The Ephemeral Skill Pattern (Token Saver)**
Skills are context-heavy. When you finish using a skill (like a critic review or audit), you MUST wipe it from your active context to prevent exponential token bloat. Do this by calling `skill: "ai-compact"` or executing `/compact` to distill your session history.

## Skill vs Agent — Auto-Selection & Resilient Invocation (§36 — E-161, agent-invocation-robustness.md)
Decide WHICH unit to run, then HOW to invoke it for the current runtime. Do this in
your thinking step — zero added latency, never trial-and-error a tool that may not exist.

**WHICH — skill vs agent:**
- **Skill** (procedural, in-context): a workflow you perform in *this* conversation —
  e.g. `ai-preflight`, `ai-task`, `ai-handoff`, `ai-debug`, `ai-review`, `commit-crafter`.
  Choose a skill when the work is a procedure you should carry out yourself.
- **Agent** (persona, forked context): an autonomous specialist that runs in an isolated
  sub-session and reports back — e.g. `critic_arch`, `critic_security`, `critic_tests`,
  `db_architect`, `dependency_manager`, `chaos_monkey`, `security_engineer`. Choose an
  agent when you need an independent expert whose work must NOT pollute your context.

**HOW — environment-aware, resilient tool selection (inspect your own toolset first):**
1. If a native subagent tool (`invoke_subagent` / `define_subagent`) is exposed → you are
   in **Antigravity (`agy`)**; invoke agents with `invoke_subagent`.
2. Else if MCP tools are exposed → invoke agents with `activate_agent`
   (context-invoker-mcp) and skills with the **Skill tool** / `activate_skill`.
3. If neither is available → fall back to the CLI script or print the manual steps.

Never call a tool that is not in your current toolset — it throws and aborts the task.
Do not assume MCP is present (agy may not expose it), and do not assume `invoke_subagent`
exists outside agy. Match the path to the tools you actually have.

## Mid-Task Triggers
If you touch auth/secrets → `activate_agent("security_engineer")` (it is an agent, not a skill — E-148)
If you add a dependency → `skill: "dependency_gate"`
If you modify CI/CD → `skill: "ci_gate"`
If a test is failing → `skill: "ai-debug"` (LOCKED until green)
Before modifying existing code → `skill: "repo-oracle"`
After any significant action → `skill: "ai-log"`
Before switching to Gemini → `skill: "ai-handoff"`
Every 3rd E-## task or before a long sprint → `skill: "ai-context-check"`

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
