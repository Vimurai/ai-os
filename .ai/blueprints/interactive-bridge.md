# Blueprint: Interactive Bridge (Tmux Watcher)

## Goal & Architecture
**Goal**: Enable a "Ping-Pong" autonomous loop where the Architect (Gemini) and Engineer (Claude) can operate side-by-side in a terminal, automatically waking each other up and passing control without a heavy, brittle API wrapper.
**Architecture**: A lightweight, global Bash watcher (`ai watch`) that uses `tmux send-keys` to orchestrate interactive CLI binaries, triggered by an explicit MCP signaling tool.

## Core Concept
Because interactive REPLs block on standard input, they cannot natively listen to a database. The Interactive Bridge solves this by using a background watcher script. When an agent finishes its phase, it calls a new MCP tool (`handoff_control`) which writes to a signal file. The background watcher detects this signal and injects the appropriate keystrokes into the idle agent's `tmux` pane.

## Components
1. **`handoff_control` (MCP Tool)**
   - Responsibility: An explicit tool in `task-synchronizer-mcp` that allows agents to emit a structured signal (e.g., `{ target: "claude", message: "Planning complete." }`) to `.ai/signal.json`.
2. **`ai watch` (Global CLI Command)**
   - Responsibility: A global Bash script installed to `~/.ai-os/bin/ai-watch`. When run inside a project directory, it resolves the current `tmux` session, tails `.ai/signal.json`, and executes `tmux send-keys` to route the message to the target pane.

## Data Model
**`.ai/signal.json` Payload:**
```json
{
  "timestamp": "2026-06-02T12:00:00Z",
  "target": "claude", 
  "message": "Gemini finished planning. Execute OPEN tasks."
}
```

## API / Interface Contracts
- **`mcp__task-synchronizer-mcp__handoff_control(target, message)`**:
  - Overwrites `.ai/signal.json` with the new payload.
  - Returns confirmation to the sending agent.
- **`ai watch` execution**:
  - Scopes itself to `$(pwd)`.
  - Maps `target: "claude"` to pane `0` (or pane title `claude`).
  - Maps `target: "gemini"` to pane `1` (or pane title `gemini`).

## Security
- **Isolation**: `ai watch` must strictly filter `tmux list-panes` by the current working directory to prevent injecting commands into other concurrent projects.
- **Command Injection**: The `message` field must be safely escaped before being passed to `tmux send-keys` to prevent arbitrary shell execution if an agent hallucinates shell characters.

## Execution Constraints
- Requires `tmux` to be installed and active.
- The watcher must poll at a low interval (e.g., `sleep 1`) or use `fswatch`/`inotify` to minimize CPU overhead.

## Rollback Plan
- Kill the `ai watch` process. Agents revert to requiring manual human keystrokes to begin their turn.

## E-## Task Breakdown
- **E-114**: Add the `handoff_control` tool to `task-synchronizer-mcp` to manage `.ai/signal.json` writes.
- **E-115**: Create the `ai-watch` global bash script in `src/bin/ai-watch` and update the installer to deploy it.
