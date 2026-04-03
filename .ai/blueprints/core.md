# Blueprint: Core (§1–4, §15, §20–21)

> Covers: System philosophy, information architecture, UX flows, technical strategy, dev cycle, sovereign planning, project scoping.

## §1. System Philosophy
- **Concept**: A Triad intelligence loop directly embedded within any codebase. AI-OS bridges the gap between raw LLM chats and structured agentic execution.
- **Value Prop**: Low-friction onboarding, automatic token-saver hooks, clear separation of concerns (Planning vs Execution vs Testing).
- **Aesthetic**: Command-line minimal, robust shell scripting, heavily structured markdown memory.

## §2. Information Architecture
- **Global Installation**: `~/.ai-os` contains binaries, templates, hooks, and contracts.
- **Local Application (`.ai/`)**: Project intelligence core housing `DIGEST.md` (snapshot), `BRIEF.md` (lore), `architect.md` (blueprint index), `blueprints/` (domain files).
- **Agent Roles**: Gemini is the Principal Architect (owns "What"); Claude is Principal Engineer (owns "How", executes changes).

## §3. UX / Interaction Flows
- **User Entry**: Setup via `./install-ai-os.sh` → Shell Reload.
- **Project Init**: Run `ai init` in target directory to scaffold `.ai/`.
- **Workflow**: Run `ai update [intent]` → Claude reads DIGEST → executes goals → Stop hook appends session summary.

## §4. Technical Strategy
- **Framework**: Bash (zero-dependency besides Node.js for MCP).
- **Architectural Intelligence**: Driven by composable Node.js MCP servers registered in `~/.ai-os/registry.json` and localized agent/skill files.
- **Tool Registry & Governance**:
  - `~/.ai-os/registry.json`: Signed list of authorized MCP servers.
  - `src/bin/ai-exec`: Enforces Capability Isolation (Read/Write/Execute) based on registry signatures.
- **Command Implementation Guide (`ai archive`)**:
  - Identify `.ai/` files with content (`LOG.md`, `COMM.md`, `REVIEWS.md`, `SESSION.md`).
  - Move to `.ai/archive/YYYY-MM/` with timestamped suffix.
  - Re-initialize files from templates.
- **Command Implementation Guide (`ai review`)**:
  - Accepts `claude` or `gemini` parameter.
  - Outputs a formatted prompt for parallel critic execution.
  - Claude Pattern: `critic_arch` + `critic_security` + `critic_tests`.
  - Gemini Pattern: Architectural audit of `architect.md`.

## §15. Development Cycle
1. **Plan**: Gemini updates domain blueprints in `.ai/blueprints/`.
2. **Build**: Claude implements changes per blueprints, following `TASKS.md` E-## assignments.
3. **Test**: `ai test` validates CLI behavior, template integrity, and security hook triggers.

## §20. Sovereign Planning & Execution Protocol
- **Primary Memory**: `.ai/` is authoritative. CLI-native state (temp plan files) is secondary.
- **Architect's Mandate**: Designs MUST be committed to `.ai/blueprints/` and `.ai/TASKS.md`.
- **Engineer's Mandate**: Claude MUST prioritize `.ai/blueprints/` and `TASKS.md` above all other guides. `.ai/` memory prevails over CLI plans.
- **Enforcement**: Reflected in `CLAUDE.md` and `GEMINI.md`.

## §21. Strictly Project-Scoped Environments
- `ai install`: Targets ONLY `~/.ai-os`. NEVER touches `~/.claude` or `~/.gemini`.
- `ai init`: Creates project-scoped `.claude/settings.json` and `.gemini/settings.json`.
- `ai sync`: Synchronizes to `.claude/` and `.gemini/` in current project root ONLY.
- `context-invoker-mcp`: Prioritizes `process.cwd()/.claude/skills` when resolving skills/agents.
- `ai doctor`: Scans and reports project-scoped directories for Ghost Tools and missing deps.
