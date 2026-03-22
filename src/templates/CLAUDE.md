# CLAUDE.md — Project Bootloader

## Session Start (MANDATORY)
At the start of EVERY session, ALWAYS run preflight before anything else:
```
mcp__orchestrator-mcp__run_preflight()
```
Fallback if orchestrator-mcp unavailable: `activate_skill({ skill_name: "ai-preflight" })`

## Core Rules
- `.ai/` is Primary Memory — overrides conversation context and CLI plans.
- Read `.ai/TASKS.md` for your orders. Execute the open E-## tasks.
- After every task: `run_handover({ task_id: "E-##", summary: "..." })`
- Before committing: `run_review({ tier: N })`

## Skill Invocation
Discover available skills dynamically:
```
activate_skill({ skill_name: "", list_skills: true })
activate_agent({ agent_name: "", list_agents: true })
```
When a request matches a skill trigger — load and follow it. Never skip gates.

## Mid-Task Triggers
If you touch auth/secrets → load `security_engineer`
If you add a dependency → load `dependency_gate`
If you modify CI/CD → load `ci_gate`

## Global Rules
Full Principal Engineer rules are in `~/.claude/CLAUDE.md`.
