# Blueprint: Agents (§10–12, §16–18)

> Covers: Advanced agentic skills, UACS, domain isolation, Skills 2.0, agent blueprints.

## §10. Advanced Agentic Skills
- **ux_reviewer** (Gemini Vision + Playwright): Visual audits, CLS, contrast, animation vibe. Trigger: `ai test --vibe`.
- **knowledge_architect** (Gemini 1M+): Cross-project RAG, Memory Palace. Trigger: `ai init`.
- **chaos_monkey** (Claude): Race-condition hunting, rapid-click stress tests. Trigger: Mandatory Tier 3 gate.

## §11. Universal Autonomous Command Suite (UACS)
- **Skill Configuration**:
  - `disable-model-invocation: true`: For destructive tools; prevents autonomous execution.
  - `allowed-tools`: Every skill MUST declare allowed tools (Principle of Least Privilege).
  - **Dynamic Context Injection**: Skills use `!<bash-command>` to inject read-only context before agent spawn.
  - **Subagent Delegation**: Complex skills use `context: fork` + target `agent` profile (isolated context window).
- **Core UACS MCP Servers**: See `blueprints/mcp.md` for server specs.

### §11.1 AI-OS Slash Command Integration (Skills 2.0)
- Each command: `src/<agent>/skills/<command>/SKILL.md` with Dynamic Context Injection.
- Core commands: `/update`, `/test`, `/test_vibe`, `/review`, `/digest`, `/preflight`.
- `disable-model-invocation: true` on all slash commands — user-triggered only.

### §11.2 Gemini CLI Custom Commands
- `.toml` files in `src/gemini/commands/` map to `~/.gemini/commands/`.
- Each `.toml` calls `activate_skill` for the corresponding skill.
- Deployed by `ai install` / `ai sync`.

## §12. Strict Domain Isolation
- **Gemini (Architect)**: Owns `architect.md`, `BRIEF.md`, `TASKS.md` (P-##), `blueprints/`.
- **Claude (Engineer)**: Owns `src/`, `LOG.md`, `TASKS.md` (E-##), `SECURITY.md`, `DEVOPS.md`.
- **Handover**: Claude auto-rejects "New Feature" requests → redirects to Gemini. Gemini auto-rejects "Coding/Debugging" → redirects to Claude.

## §16. Skills 2.0 Modular Migration
- **Standard**: `src/<agent>/skills/<skill-name>/SKILL.md` (folder structure, not flat file).
- **Folder contents**: `SKILL.md` (instructions + frontmatter), `scripts/` (optional), `references/` (on-demand).
- **Progressive Disclosure**:
  - Level 1 (Meta-Sync): `ai sync` exposes skill descriptions only.
  - Level 2 (Activation): Full content loaded only when `activate_skill` is called.
  - Level 3 (Deep-Dive): `references/` read only if task explicitly requires it.

### §16.1 Shared Skills Architecture
- `src/shared/skills/`: Universal skills accessible by both Architect and Engineer.
- `src/claude/skills/`: Engineer-specific (`ci_gate`, `dependency_gate`, `scope_safety`).
- `src/gemini/skills/`: Architect-specific (`seo_content_checklist`, `ux_template`).
- `ai install`/`ai sync`: Copy `src/shared/skills/` into BOTH `.claude/skills/` and `.gemini/skills/`.

### §16.2 Third-Party Skill Integrations
- Pattern: Copy external `SKILL.md` into `src/gemini/skills/<skill>/`, update frontmatter, create `.toml` command.

## §17. Agent Blueprints
- **prd_writer** (Gemini): Refines user intent → P-## tasks in state.json. Trigger: `ai update` Gate 1.
- **ux_reviewer** (Gemini Vision): Playwright visual audit + Lighthouse. Trigger: `ai test --vibe`.
- **knowledge_architect** (Gemini): Cross-project RAG. Trigger: `ai init`.
- **chaos_monkey** (Claude): Stress testing, race-condition injection. Trigger: Tier 3 mandatory.
- **commit-crafter** (Claude Skill): Conventional Commits + UACS stamps + E-## IDs. No `--author`, no `Co-authored-by`.
- **aqg-resolver** (Claude): Auto-fix `[LOCKED - AQG FAILED]`. Reads stderr, applies minimal fix, re-runs gate.
- **bug-reproducer** (Claude Skill): Mandatory `repro.sh` or failing test before any Tier 2/3 src/ edit.
- **release-manager** (Shared): Bumps `package.json`, aggregates DONE tasks → CHANGELOG.md, tags commit.
- **docs-architect** (Gemini): Audits README/CONTRIBUTING vs `architect.md` + `.mcp.json`. Trigger: end of sprint.

### §17.5 Agent Frontmatter Requirements
- Claude sub-agents: MUST define `tools` array and explicit `description` trigger conditions.
- Gemini skills: `description` must have imperative trigger language for `activate_skill` auto-dispatch.

## §18. Autonomous Command Suite (UACS) Logic
- **`intent-refiner-mcp`** (DEPRECATED — E-147): Previously bridged chat → TASKS.md via UPDATE.md. Now a no-op.
- **`blueprint-aligner-mcp`**: Compares `git diff` vs `architect.md`. Returns `[PASS/FAIL]` with deviation report.
- **`safe-exec-mcp`**: AST-analyzes shell commands; detects `rm -rf /`, `curl | bash`, other high-risk patterns.
