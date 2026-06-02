# Blueprint: Sovereignty Hardening

## Goal & Architecture
**Goal**: Enforce Role-Based Access Control (RBAC) to prevent the Architect (Gemini) from executing destructive git operations and improperly mutating completed task states.
**Architecture**: Transition role boundaries from "honor-system" documentation to "fail-closed" MCP validation and state-locks.

## Core Concept
The Triad (Architect, Engineer, Tester) requires sovereign boundaries. Sovereignty Hardening move these boundaries from instruction-level guidelines to tool-level enforcement.

## Components
1. **Role-Aware `safe-exec-mcp`**
   - Responsibility: Extend `analyze_command` to accept a `caller_role`. Block dangerous implementation git commands (`reset`, `revert`, `checkout` of source files) if the role is `architect`.
2. **Immutability Lock in `task-synchronizer-mcp`**
   - Responsibility: Prevent `update_task_status` on `DONE` tasks unless an explicit `reopen: true` flag is provided. This prevents accidental mutation of completed implementation history.
3. **Audit Stamp Enforcement**
   - Responsibility: Update `ai-log` and pre-commit hooks to audit Architect shell commands for sovereignty violations.

## Data Model
- `ForbiddenArchitectGit`: `['reset', 'revert', 'checkout', 'clean']` when used with implementation targets (outside `.ai/`, `plans/`).
- `ForbiddenArchitectOps`: `['rm -rf', 'mkdir', 'touch']` when used outside `.ai/`, `plans/`.
- `TaskLock`: `DONE` status tasks require `reopen: true` for any further status mutation.

## API / Interface Contracts
- **`safe-exec-mcp::analyze_command(command, caller_role)`**
  - If `caller_role === 'architect'`, check `command` against `ForbiddenArchitectGit` and `ForbiddenArchitectOps`.
  - Verdict: `BLOCK` with tag `[SOVEREIGNTY_BLOCK]`.
- **`task-synchronizer-mcp::update_task_status(id, status, reopen: boolean)`**
  - If `current_status === 'DONE'` and `reopen !== true`, return `isError: true` with message `[TASK_LOCKED]`.

## Security
- **Trust Boundary**: The `caller_role` is the primary selector. While currently self-reported by the agent, future iterations will have this injected by the AI-OS bootloader to prevent impersonation.
- **Rollback**: Set `AI_OS_SOVEREIGNTY_LOCK=0` to bypass the `DONE` task lock.

## Execution Constraints
- Lock logic must be transactionally safe (SQLite-first).
- Shell filtering must use regex to ensure sub-100ms analysis.

## Rollback Plan
- Revert `src/mcp/task-synchronizer-mcp/index.js` to pre-lock logic.
- Remove `caller_role` dependency from `safe-exec-mcp`.

## E-## Task Breakdown
- **E-101**: Implement the `DONE` task mutation lock in `task-synchronizer-mcp` with `reopen: true` override.
- **E-102**: Implement `caller_role` support and Architect-specific blocks in `safe-exec-mcp`.
- **E-103**: Update `GEMINI.md` and `.ai/RULES.md` to explicitly list forbidden git commands for the Architect.
