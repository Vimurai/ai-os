# CLI Collapse & Tmux Workflow

## Goal & Architecture
The goal is to minimize the footprint of the `ai` bash CLI by collapsing it down to essential lifecycle and diagnostic commands (`init`, `sync`, `install`, `doctor`, `uninstall`). All other commands (e.g., `update`, `preflight`, `review`, `test`, `archive`, `digest`, `migrate-state`) will be migrated into conversational prompts or tool calls executed directly within the Claude or Gemini CLI environments. Furthermore, a `tmux` split-pane workflow will be formally recommended as the standard operating environment for the AI-OS Triad to improve visibility and concurrent execution.

## Core Concept
The `ai` script transitions from a multi-purpose orchestrator into a strict bootloader/installer. Operational commands become part of the agentic workflow (e.g., asking Claude "run a vibe test" instead of typing `ai test --vibe` in the terminal). The user's interface to the system becomes entirely conversational within the agent CLIs, facilitated by a persistent tmux layout.

## Components
1. **Bootloader CLI (`bin/ai`)**: Stripped down to `init`, `sync`, `install`, `doctor`, `uninstall`. Removes bash implementations for `update`, `preflight`, `review`, `test`, `mcp-setup`, `archive`, `digest`, `migrate-state`.
2. **Conversational Prompts/Skills**: The functionality of removed CLI commands is converted into corresponding agent skills or prompt templates in the documentation/bootloader files.
3. **Tmux Workflow Setup → `ai start` (D-059, 2026-09-09)**: superseded the "helper script" idea. See §`ai start` below.

## `ai start` — Triad Launcher (D-059)
**Lifecycle command set (explicit)**: `init`, `sync`, `install`, `doctor`, `uninstall`, **`start`**, plus the D-053/D-054 shell primitives `handoff`, `add-task`, `pane`, `watch`. Nothing else belongs in `bin/ai`.

**Contract** — `ai start [--no-watch] [--detach] [--dry-run] [--status] [--kill [--yes]]`:
1. **Composition only.** The launcher runs exactly two things it does not own — `ai pane <role>` and `ai watch`, both from the installed `ai` on PATH. Never a project-supplied script, never a provider binary directly (`ai pane` owns binding, title pinning and the launch argv).
2. **Layout is derived from `.ai/roles.json`.** The role with the lower `pane_identifier` receives the lower tmux `pane_index`, so the E-209 ordinal fallback agrees with the layout by construction. Default layout `triad`: engineer left (full height), architect right-top, watcher right-bottom. The watcher pane's foreground is a shell script, which `_is_agent_cmd` excludes — it never shifts the agent ordinals. Tests assert the resulting pane order for BOTH role orders.
3. **Shell-hosted agent panes.** Each agent pane is an interactive shell; `ai start` waits for the prompt (`pane_current_command` is a shell) and then `send-keys` `ai pane <role>`. When the provider exits the operator keeps a shell and can rerun `ai pane`. `ai pane` pins the title and sets `allow-rename off`.
4. **Idempotent.** In a project with live panes a re-run re-pins titles, starts the watcher only if no process holds the `ai watch` single-writer lock, and attaches — never duplicates panes. `--kill` tears the project window down, watcher first (confirm unless `--yes`). `--status` lists project panes (role, title, command) and the watcher lock holder.
5. **Optional `.ai/start.json`**: `session` (`^[A-Za-z0-9_-]{1,32}$`), `layout` (`triad` only until another is blueprinted), `watch` (bool), `sizes` (numeric percentages). Values become tmux arguments, so anything outside these shapes is rejected (E-208 audit lesson: Architect-writable config is an exec surface). Defaults: `session=aios`, window = project basename.
6. **Non-tmux hosts**: exit 2 and print the manual recipe (`ai pane engineer`, `ai pane architect`, `ai watch`) — tmux remains the recommended UX, not a requirement.

**Reference layout** (the operator's live session, 2026-09-09): `aios:1`, engineer `104x49` left, architect `103x32` right-top, watcher/shell `103x16` right-bottom.

**Rollback**: remove the `start` dispatch; the three manual commands keep working unchanged.

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
- E-## (Tmux Documentation): Update `README.md`, `CONTRIBUTING.md`, and `docs` to strongly recommend the tmux split-pane workflow, including a snippet for `~/.tmux.conf` or an automated setup script. → closed by **E-228** (docs point at `ai start`).
- **E-227** (Tier 2, D-059): `ai start` launcher core — session/window reuse, layout derived from `roles.json`, shell-hosted panes + `send-keys ai pane <role>`, watcher pane, idempotency, `--no-watch`/`--detach`/`--dry-run`, constrained `.ai/start.json`, non-tmux exit 2 + recipe.
- **E-228** (Tier 1, dep E-227): `--status`/`--kill`, `ai doctor` start-readiness line, README/CONTRIBUTING docs, `ai install`/`ai init` hint.
