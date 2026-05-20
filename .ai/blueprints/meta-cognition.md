# Meta-Cognition Pipeline (Second Brain)

## Goal & Architecture
To create a self-learning loop for AI-OS that analyzes global tool usage, task efficiency, and failure rates across all projects, proactively recommending CLI automations, tool deprecations, and workflow improvements.

## Core Concept
The "Second Brain" operates on a telemetry-to-insight pipeline: local project routers asynchronously stream usage data to a global SQLite database. A specialized `meta_analyst` agent periodically analyzes this data against the `memory-palace.md` to generate an actionable `INSIGHTS.md` report, which is prompted to the user via preflight staleness checks.

## Components
1. **Global Telemetry Store (`~/.ai-os/telemetry.sqlite`)**: A centralized SQLite database that records tool invocations, token consumption, task completion times, and agent handoff counts from all local AI-OS projects.
2. **The `meta_analyst` Agent**: A specialized Gemini agent (`.gemini/agents/meta_analyst.md`) whose sole mandate is reading telemetry and historical data to generate optimization suggestions. It does not write source code.
3. **Insight Generator (`ai insights`)**: A new CLI command that triggers the `meta_analyst` to read the telemetry database and output its findings to `~/.ai-os/INSIGHTS.md`.
4. **Preflight Stale Check (`ai-preflight` integration)**: A mechanism within the session bootloader that checks the age of `INSIGHTS.md` and the volume of unanalyzed telemetry, emitting a CLI warning to the user if a new analysis is recommended.

## Data Model
**Table: `tool_executions`**
- `id` (UUID)
- `project_hash` (String, anonymized)
- `session_id` (String)
- `tool_name` (String)
- `execution_time_ms` (Integer)
- `status` (String: SUCCESS/ERROR)
- `timestamp` (DateTime)

**Table: `task_velocity`**
- `task_id` (String)
- `turn_count` (Integer)
- `tokens_consumed` (Integer)
- `timestamp` (DateTime)

## API / Interface Contracts
- **Write:** MCP routers push to `telemetry.sqlite` in a fire-and-forget background thread to avoid blocking the main chat loop.
- **Read:** `ai insights` triggers a scoped agent run that executes SQL queries against `telemetry.sqlite` via `code-execution-mcp` (or a dedicated MCP tool) to extract aggregation metrics.

## Security
- **Privacy:** `telemetry.sqlite` must be rigorously stripped of project-specific source code, secrets, and file paths. It tracks *metadata* (tool names, turn counts, durations) only.
- **Isolation:** The `meta_analyst` agent runs with a restricted toolset; it has read-only access to the telemetry DB and write-only access to `INSIGHTS.md`.

## Execution Constraints
- **Performance:** Writing to telemetry must be asynchronous (`is_background: true`).
- **Token Limits:** The `meta_analyst` agent must rely on SQL aggregates (averages, counts) rather than reading raw logs to stay within token budgets.

## Rollback Plan
- Revert the `ai-preflight` notification check.
- Drop the `telemetry.sqlite` file and remove the async hook from the MCP router.

## E-## Task Breakdown
- **E-##:** Implement `telemetry.sqlite` schema and background writing hook in the MCP router.
- **E-##:** Create the `meta_analyst` agent definition and the `ai-insights` skill.
- **E-##:** Update `ai-preflight` skill to check `INSIGHTS.md` staleness and emit warnings.