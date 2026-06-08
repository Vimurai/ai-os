# Antigravity Native Subagents

## Goal & Architecture
**Goal:** Map the existing AI-OS framework specialized agents (e.g., `critic_arch`, `decision_recorder`) to native Antigravity subagents so they are visible and invokable directly from the Antigravity CLI's native agent UI.
**Architecture:** Create a synchronization script or MCP tool that reads the AI-OS agent registry (via `context-invoker-mcp` or `.agents/skills/`) and registers them dynamically in the current Antigravity workspace using the native `define_subagent` capability or manifest files.

## Core Concept
While AI-OS provides 21+ specialized agents via `context-invoker-mcp`, users running the Antigravity (`agy`) provider see an empty "agents" list in their UI because Antigravity expects subagents to be natively defined in its own format. This integration bridges that gap by systematically mapping AI-OS agents to Antigravity subagents upon initialization or sync.

## Components
1. **Agent Registry Parser:** Extracts the name, description, and system prompt (or skill invocation hook) for each agent from the `context-invoker-mcp` logic or `skills` directory.
2. **Antigravity Definition Mapper:** Translates the extracted data into the `define_subagent` payload format or the specific folder structure (`.agents/agents/`) required by Antigravity CLI.
3. **Sync Trigger Hook:** Injects the agent definition mapping step into the `ai init` or `ai sync` workflows so they are automatically registered for the user on startup.

## Data Model
- **AI-OS Source (agents only):** `.claude/agents/*.md` + `.gemini/agents/*.md` — autonomous personas. Procedural workflows are NOT here (see §Taxonomy); they live in `.agents/skills/`.
- **Antigravity Target:** one **per-agent subdirectory** `.agents/agents/<name>/agent.json` (confirmed by the `agy` "Create New Agents" screen — a flat `<name>.json` is NOT discovered). Global equivalent: `~/.gemini/antigravity-cli/agents/<name>/agent.json`.
Mapping logic format (define_subagent payload):
```json
{
  "name": "ai-os-critic-arch",
  "description": "Deterministic architecture reviewer. Compares git diff against .ai/architect.md",
  "system_prompt": "You are the critic_arch agent. Your job is to invoke `activate_agent({ agent_name: 'critic_arch' })` and follow the instructions.",
  "enable_mcp_tools": true
}
```

## Taxonomy: Skills vs Agents (E-141 / E-142)
AI-OS has two distinct unit types; **only Agents** map to native Antigravity subagents:

- **Skills** — in-context procedural workflows (e.g. `digest_updater`, `decision_recorder`,
  `identity_guardian`, `aqg-resolver`, `review_synthesizer`). They run in the main
  conversation, carry `context: default` (and/or `type: skill`) in frontmatter, live in
  **`.agents/skills/<name>/SKILL.md`**, and are invoked via `activate_skill(...)`. They are
  **NOT** mapped to native subagents and never appear in the `agy` agents list.
- **Agents** — autonomous personas (e.g. `devops_engineer`, the `critic_*` reviewers,
  `chaos_monkey`, `vibe_sentinel`, `security_engineer`). They fork their own context
  (`context: fork`), live in **`.claude/agents/` / `.gemini/agents/`**, are invoked via
  `activate_agent(...)`, and ARE mapped → `.agents/agents/<name>/agent.json`.

`subagent-mapper.mjs` enforces the split: it reads only the agent dirs and skips any file
whose frontmatter has `context: default` or `type: skill`.

### Authoring for `agy`
- **New agent (persona):** add `.claude/agents/<name>.md` with `context: fork`, then run
  `ai sync --agents` → it appears as a native subagent.
- **New skill (procedural):** add `.agents/skills/<name>/SKILL.md` with `context: default`
  (or `type: skill`); it stays in-context and is never shown as a native subagent.

## API / Interface Contracts
- **Input:** Execution of `ai sync --agents` or similar bootloader command.
- **Action:** A node script maps the registry and outputs Antigravity subagent manifests.
- **Output:** The Antigravity UI correctly displays the AI-OS agents.

## Security
- Subagents must be confined to the project workspace.
- The `system_prompt` injected must explicitly command the subagent to respect the standard AI-OS boundaries (e.g., capability limits, safe-exec-mcp).

## Execution Constraints
- **Performance:** Registration should be fast (< 500ms) to not slow down `ai sync`.
- **Duplication:** Ensure idempotent definitions so agents aren't duplicated across syncs.

## Rollback Plan
- Provide a command `ai sync --clear-agents` to remove the native definitions.
- If the integration fails, users can continue invoking agents manually via `context-invoker-mcp` with no loss of functionality.

## E-## Task Breakdown
- **E-140**: Implement the `ai sync --agents` mapper to extract AI-OS agent metadata and register them as native Antigravity subagents.
