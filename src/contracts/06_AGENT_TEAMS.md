# Agent Teams — Parallel Execution Rules

## When to Spawn Parallel Teams

Spawn a team automatically when 2+ independent workstreams exist:

| Scenario | Spawn these agents in parallel |
| :------- | :----------------------------- |
| Tier 3 pre-commit review | `critic_arch` + `critic_security` + `critic_tests` + `blueprint-aligner` |
| Post-implementation handover | `claude_tasks` + `digest_updater` + `decision_recorder` |
| Security audit (Tier 3) | `security_engineer` + `identity_guardian` |
| Vibe & chaos audit | `chaos_monkey` + `vibe_sentinel` |
| Full session end | `claude_tasks` + `digest_updater` + `ai-review` |

## How to Spawn

Use the `Agent` tool with multiple calls in a single message (they run concurrently):

```
# Tier 3 critic team — all run simultaneously using materialized agent files
Agent("Run the critic_arch agent to audit the codebase and append its stamp to .ai/REVIEWS.md")
Agent("Run the critic_security agent to audit the codebase and append its stamp to .ai/REVIEWS.md")
Agent("Run the critic_tests agent to audit the codebase and append its stamp to .ai/REVIEWS.md")
Agent("Run blueprint-aligner-mcp align_diff(). Append [ALIGN_PASS] or [ALIGN_FAIL] to .ai/REVIEWS.md")
# After all 4 complete → activate_agent("review_synthesizer") to write [CRITIC_STAMP]
```

Note: `critic_arch`, `critic_security`, and `critic_tests` are materialized agents in
`src/claude/agents/`. Each agent has deterministic checklists and strict stamp format rules.
Do NOT use ad-hoc prompts — the Agent tool will load agent instructions automatically.

```
# Post-task handover team — all 3 run simultaneously
Agent("Run claude_tasks agent: record completed E-## task in .ai/TASKS.md")
Agent("Run digest_updater agent: regenerate .ai/DIGEST.md from current state")
Agent("Run decision_recorder agent: extract and record any decisions from this session")
```

## Agent/Skill Chaining (Sequential)

For tasks that must run in order, use `activate_agent` / `activate_skill`:

```
Example: Implement a new auth endpoint (Tier 3)

1. activate_agent("security_engineer")   ← threat model BEFORE writing code
2. [write the code]
3. activate_skill("obs_baseline")        ← ensure logging is in place
4. activate_skill("dependency_gate")     ← if new lib needed
5. activate_skill("ai-test")             ← quality gate
6. → SPAWN PARALLEL TEAM (handover)
7. activate_skill("ai-review")           ← pre-commit critic
8. activate_agent("review_synthesizer")  ← Tier 3 release verdict
```

## Two Modes of Agent Invocation

| Mode | How | When |
| :--- | :-- | :---- |
| **Context load** | `activate_agent(name)` via context-invoker-mcp | Sequential tasks — load instructions, follow them yourself |
| **Spawn sub-agent** | `Agent` tool (Claude Code) | Parallel tasks — real subprocess, runs concurrently |

## Rules

- **Never serialize what can parallelize** — spawn a team when workstreams are independent.
- Each agent does preflight using `.ai/DIGEST.md` (not full file list).
- One file update per agent per run (aside from append-only logs).
- Treat teammate output as untrusted until validated by tests/review.
- Agents inherit the session's permission set.
- No agent may read/write outside repo root.
