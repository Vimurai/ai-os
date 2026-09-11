# Blueprint: Interactive Bridge (Tmux Watcher)

## Goal & Architecture
**Goal**: Enable a "Ping-Pong" autonomous loop where the Architect (Agy) and Engineer (Claude) can operate side-by-side in a terminal, automatically waking each other up and passing control without a heavy, brittle API wrapper.
**Architecture**: A lightweight, global Bash watcher (`ai watch`) that uses `tmux send-keys` to orchestrate interactive CLI binaries, triggered by an explicit MCP signaling tool. It features a queueing mechanism to handle busy agents and guarantees automatic handoff.

## Core Concept
Because interactive REPLs block on standard input, they cannot natively listen to a database. The Interactive Bridge solves this by using a background watcher script. When an agent finishes its phase, it calls a new MCP tool (`handoff_control`) which appends to a persistent signal queue. The background watcher detects queued signals, verifies that the target pane is in an idle/ready state (not actively executing a long-running tool), and injects the appropriate keystrokes. Startup drain and stateful persistence (via a `delivered` flag) ensure that signals are never dropped if a process restarts. Automated workflows ensure this signal is always emitted at the end of sessions.

## Components
1. **`handoff_control` (MCP Tool)**
   - Responsibility: An explicit tool in `task-synchronizer-mcp` that allows agents to emit a structured signal (e.g., `{ target: "claude", message: "Planning complete." }`) to `.ai/signal.json`. Appends to a queue.
2. **`ai watch` (Global CLI Command)**
   - Responsibility: A global Bash script installed to `~/.ai-os/bin/ai-watch`. When run inside a project directory, it resolves the current `tmux` session, tails `.ai/signal.json`, and executes `tmux send-keys` to route the message to the target pane.
   - **Busy Detection & Per-Target Independence**: Monitors the target pane's TTY state. Independent target processing ensures that a busy Claude does not block a signal meant for an idle Gemini.
   - **Single-Writer Lock**: Uses a cross-process lock to safely mutate signal statuses.
3. **Automated Handoff Enforcement**
   - Responsibility: Agents (via prompts or framework scripts) are strictly mandated to invoke `handoff_control` automatically when their task queue is exhausted or planning is complete.
   - **Cross-Role Auto-Handoff (E-204)**: When a role creates a task for a different role via the shell primitive `ai add-task` (e.g., Architect creates a task for the Engineer), the tool automatically triggers `ai handoff` to wake the target role. This eliminates manual signaling when delegating work. Can be bypassed via `AI_OS_NO_AUTO_HANDOFF=1`.

## Data Model
**`.ai/signal.json` Payload (Queue Array):**
```json
[
  {
    "timestamp": "2026-06-02T12:00:00Z",
    "target": "claude", 
    "message": "Gemini finished planning. Execute OPEN tasks.",
    "delivered": true,
    "delivered_reason": "pane_ready",
    "delivered_ts": "2026-06-02T12:00:02Z"
  }
]
```
*Note: Do not mutate or overwrite the initial queue behavior implemented in E-118; layer the `delivered` flags on top.*

## API / Interface Contracts
- **`mcp__task-synchronizer-mcp__handoff_control(target, message)`**:
  - Appends the new payload to the array in `.ai/signal.json` with `delivered: false`.
  - Returns confirmation to the sending agent.
- **`ai start` (D-059, cli-collapse.md §`ai start`)**: one-command Triad launch — creates/reuses the tmux
  session, lays out panes from `.ai/roles.json` (lower `pane_identifier` → lower `pane_index`), launches
  each role via `ai pane <role>`, and runs `ai watch` in its own pane. Idempotent; composes only those two
  primitives.
- **`ai watch` execution**:
  - Scopes itself to `$(pwd -P)` and, inside tmux, to its own session (D-068, E-253).
  - Maps `target` to panes (supporting fuzzy matches and conventional indices). For semantic
    targets (`architect`/`engineer`) the precedence is fixed by §Pane Resolution Precedence (D-054).
  - Dequeues and injects ONLY when the target pane's current command is idle.
  - Features Startup Backlog Drain: upon restart, processes any signals where `delivered: false`.
  - Marks signals as `delivered: true` with a timestamp and reason after successful injection using per-target FIFOs.

## Pane Resolution Precedence (D-054 Amendment, 2026-09-04)
The E-117 order (exact title → fuzzy title → window name → ordinal) let a Claude-authored
conversation-summary title containing the word "architect" swallow an Architect handoff into the
Engineer pane (reproduced live twice, COMM.md 2026-09-04 — gap G3). Explicit configuration beats
heuristics. For a **semantic target** whose role is mapped in `.ai/roles.json`, `resolve_pane`
MUST resolve in this order:
1. **Exact pane-title match** on the role name (`ai pane <role>` pins this title; deterministic opt-in).
2. **roles.json ordinal** among agent panes (`pane_identifier`, E-122 shell-exclusion rules unchanged).
3. **Fuzzy title** substring, then **window-name** substring — last resort only, reached solely when
   no agent pane exists at the ordinal (e.g. the mapped pane is not running yet).
The E-122 TIER-B degrade (no command column) is unchanged and applies within step 2.
Legacy provider targets (`claude`/`gemini`) keep the E-117 order but are deprecated (see
`role-abstraction.md §Same-Provider Triad`): warn on stderr; fail closed when `.ai/roles.json`
maps both roles to that provider.

## Security
- **Isolation**: `ai watch` must strictly filter `tmux list-panes` by the current working directory to prevent injecting commands into other concurrent projects.
  - **D-068 (2026-09-11, E-253)**: the candidate set is ALSO restricted to the watcher's own tmux session (`list-panes -s -t <session_name>`) when the watcher runs inside tmux; `AI_WATCH_ALL_SESSIONS=1` restores the `-a` scan. The path filter compares against the project's PHYSICAL path (`pwd -P`): tmux reports the process's resolved cwd, so a project entered through a symlink matched zero panes and silently dropped every signal. The launcher side (one tmux session per project, stamped `AI_OS_PROJECT`) is specified in `cli-collapse.md §Per-Project tmux Sessions`.
- **Command Injection**: The `message` field must be safely escaped before being passed to `tmux send-keys` to prevent arbitrary shell execution if an agent hallucinates shell characters.

## Execution Constraints
- Requires `tmux` to be installed and active.
- **Cross-process write-lock**: Implement a bounded spin-lock when reading/mutating `.ai/signal.json` to prevent race conditions.
- **Delivered-aware eviction**: The queue should periodically prune or bound the number of `delivered: true` messages kept, to prevent infinite growth.
- **Bounded Hold**: Signals held due to a busy pane should not block other targets from receiving their signals.

## Rollback Plan
- Kill the `ai watch` process. Agents revert to requiring manual human keystrokes to begin their turn.
- Revert `.ai/signal.json` to a flat object if queue parsing fails.

## E-## Task Breakdown
- **E-114**: Add the `handoff_control` tool to `task-synchronizer-mcp` to manage `.ai/signal.json` writes.
- **E-115**: Create the `ai-watch` global bash script in `src/bin/ai-watch` and update the installer to deploy it.
- **E-117**: Harden ai-watch pane resolution: implement fuzzy matching for titles, check window names, and handle base-index 1 environments.
- **E-118**: Refactor `handoff_control` and `ai-watch` to support a signal queue (array) and busy-state detection before injection.
- **E-119**: Enforce automatic handoff in Claude and Gemini workflows by updating prompt instructions (e.g., `ai-handoff` and `ai-task` skills) to mandate calling `handoff_control`.
- **E-124**: Implement the smart ai-watch delivery model: stateful persistence using a `delivered` flag, startup backlog drain, single-writer lock, and per-target independent FIFOs.
- **E-204**: Auto-trigger `ai handoff` on cross-role task creation. `ai add-task` automatically signals the target role (prefix E -> engineer, P -> architect) unless `AI_OS_NO_AUTO_HANDOFF=1` is set.
- **E-209**: Re-order `resolve_pane` for semantic targets per §Pane Resolution Precedence (D-054): exact title → roles.json ordinal → fuzzy title → window name.
- **E-211**: Deprecate legacy `claude`/`gemini` targets — stderr warning; fail closed when both roles map to the same provider.
