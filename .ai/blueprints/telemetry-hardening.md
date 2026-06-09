# Telemetry Hardening Blueprint

## Goal & Architecture
Resolves the structural blindness in meta-cognition telemetry where only `mcp-router::proxy_call` was instrumented. Extends telemetry interception globally across all MCP calls (or at the transport layer) so that the error dimension and task-velocity are accurately captured without developers needing to manually instrument each server.

## Core Concept
A centralized, transport-level or orchestrator-level telemetry interceptor that wraps every MCP tool execution to record inputs, outputs, errors, latency, and token usage, writing to `telemetry.sqlite`.

## Components
1. **Global Telemetry Interceptor**: Wraps the MCP server's execution context or is injected at the `task-synchronizer` level to ensure 100% coverage of tool invocations.
2. **Error State Recorder**: Extracts failure reasons, stack traces (sanitized), and exit codes from MCP tool execution to populate the previously empty `ERROR` dimension in `telemetry.sqlite`.
3. **Task Velocity Aggregator**: Enhances the existing `task_velocity` writer to trigger reliably upon task completion or sprint boundaries, accurately measuring token spend and turn count.

## Data Model
Updates to `telemetry.sqlite` schema or write payloads:
- `tool_executions` table: Ensure `status` enum explicitly captures `SUCCESS`, `ERROR`, `TIMEOUT`.
- `task_velocity` table: `task_id`, `turn_count`, `total_tokens`, `duration_ms`.

## API / Interface Contracts
- `recordToolExecution(toolName, args, status, latencyMs)`
- `recordTaskVelocity(taskId, turns, tokens)`

## Security
No secrets or PII are logged. Tool arguments are sanitized before insertion into SQLite to prevent SQL injection or secret leakage. The DB remains local to the user (`~/.ai-os/telemetry.sqlite`).

## Execution Constraints
Telemetry writes must be non-blocking and low-latency (<5ms added per tool execution) to prevent slowing down the JIT context and agent operations.

## Rollback Plan
If the global interceptor causes instability or breaks existing MCPs, the user can set `AI_TELEMETRY_DISABLE=1` to bypass the interception entirely and fall back to the uninstrumented mode.

## E-## Task Breakdown
- **E-153**: Implement the Global Telemetry Interceptor and wire it into the MCP transport layer.
- **E-154**: Refactor error capturing to properly log the `ERROR` state into `telemetry.sqlite`.
- **E-155**: Fix the `task_velocity` aggregator so it reliably records metrics at task completion.
