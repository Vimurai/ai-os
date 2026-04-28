# CLI Collapse & Tmux Workflow

## Goal & Architecture
The goal is to minimize the footprint of the `ai` bash CLI by collapsing it down to essential lifecycle and diagnostic commands (`init`, `sync`, `install`, `doctor`, `uninstall`). All other commands (e.g., `update`, `preflight`, `review`, `test`, `archive`, `digest`, `migrate-state`) will be migrated into conversational prompts or tool calls executed directly within the Claude or Gemini CLI environments. Furthermore, a `tmux` split-pane workflow will be formally recommended as the standard operating environment for the AI-OS Triad to improve visibility and concurrent execution.

## Core Concept
The `ai` script transitions from a multi-purpose orchestrator into a strict bootloader/installer. Operational commands become part of the agentic workflow (e.g., asking Claude "run a vibe test" instead of typing `ai test --vibe` in the terminal). The user's interface to the system becomes entirely conversational within the agent CLIs, facilitated by a persistent tmux layout.

## Components
1. **Bootloader CLI (`bin/ai`)**: Stripped down to `init`, `sync`, `install`, `doctor`, `uninstall`. Removes bash implementations for `update`, `preflight`, `review`, `test`, `mcp-setup`, `archive`, `digest`, `migrate-state`.
2. **Conversational Prompts/Skills**: The functionality of removed CLI commands is converted into corresponding agent skills or prompt templates in the documentation/bootloader files.
3. **Tmux Workflow Setup**: Documentation and potentially a helper script (or part of `ai init`) to scaffold a recommended tmux layout (e.g., one pane for Gemini, one for Claude, one for the underlying bash terminal).

## Data Model
No new SQLite state tables are required. The state model remains driven by `TASKS.md` and `state.json` via MCP.

## API / Interface Contracts
- **CLI Commands**:
  - `ai init`: Scaffolds the `.ai` directory.
  - `ai sync`: Synchronizes skills and agents.
  - `ai install`: Installs global config.
  - `ai doctor`: Validates health.
  - `ai uninstall`: Cleans up AI-OS.
- All removed commands will display a deprecation notice guiding the user to the equivalent agent command.

## Security
- By moving execution from bash scripts into the agent environment, commands that mutate state will now pass through the standard `safe-exec-mcp` and `approval-mcp` (HITL) gates, improving the security posture.

## Execution Constraints
- Agents must be equipped to handle the migrated commands efficiently.
- `tmux` recommendation must be documented clearly in `README.md` and `CONTRIBUTING.md` as the optimal UX, not a hard requirement that breaks non-tmux users.

## Rollback Plan
- Revert the `bin/ai` bash script from git history.
- Restore the legacy documentation.

## E-## Task Breakdown
- E-## (CLI Reduction): Remove logic for `update`, `preflight`, `review`, `test`, `archive`, `digest`, `migrate-state` from `src/bin/ai`. Replace them with deprecation echo statements guiding users to the agent prompts.
- E-## (Agent Skills Migration): Ensure all removed CLI functions have a 1:1 mapping to an agent skill (e.g., `ai-review`, `ai-test`, `ai-archive`, `ai-digest`, `ai-preflight`).
- E-## (Tmux Documentation): Update `README.md`, `CONTRIBUTING.md`, and `docs` to strongly recommend the tmux split-pane workflow, including a snippet for `~/.tmux.conf` or an automated setup script.
