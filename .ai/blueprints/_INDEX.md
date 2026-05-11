# Blueprint: _INDEX (Domain Index)

## Goal & Architecture
To serve as the central hub mapping features to blueprints, MCP servers, and test suites. Resolves the architectural drift identified in P-33 by providing a single entry point for agents to navigate the AI-OS domain blueprints.

## Core Concept
A structured directory mapping that connects abstract domain blueprints to their concrete MCP server implementations and verification suites. Agents read this file first (JIT) to find which specific blueprint to load.

## Components
1. **Core State Engine**: Maps to `architect.md` and `caching.md`.
2. **MCP Nervous System**: Maps to `mcp.md` (auto-generated) and `mcp-router.md`.
3. **Execution & Safety**: Maps to `code-execution.md`, `interop.md`, and `capabilities.md`.
4. **Maintenance**: Maps to `aligner-hardening.md` and `wal-checkpoint-node.md`.
5. **Framework Operations**: Maps to `task-routing.md` and `incident-tracker.md`.

## Data Model
- `Domain Blueprint` (e.g., `mcp.md`)
  - `MCP Servers` (e.g., `mcp-router`)
  - `Tests` (e.g., `mcp_router_test.sh`)

## API / Interface Contracts
- File is strictly read-only for agents.
- Agents MUST consult this index before loading other domain blueprints to enforce the JIT 6-File Limit.

## Security
- No sensitive information (passwords, keys) shall be stored in the index.
- Follows the general `.ai/` RBAC (Architect write-only).

## Execution Constraints
- Must remain under 100 lines to ensure minimal JIT token cost during `ai-preflight`.

## Rollback Plan
- Delete `.ai/blueprints/_INDEX.md` and revert to full sequential reads (not recommended due to token bloat).

## E-## Task Breakdown
- (No direct E-task needed for the index itself as it's a documentation artifact, but it unblocks future agent navigation).