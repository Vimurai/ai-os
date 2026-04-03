# Robustness Fixes Blueprint

## 1. Synchronous I/O Race Conditions in MCP Servers

### The Problem
Currently, several MCP servers (specifically `task-synchronizer-mcp`, `orchestrator-mcp`, and `memory-manager-mcp`) rely on synchronous file I/O operations (`readFileSync`, `writeFileSync`) to manage state files like `state.json`.

When multiple agents run concurrently (e.g., during complex workflows involving both Claude and Gemini, or parallel testing), there is a significant risk of race conditions. If two processes read the file simultaneously, modify their in-memory copies, and write them back, one set of changes will be silently overwritten (lost updates) or the file may become corrupted.

### The Solution: SQLite Migration
The most robust solution is to migrate these file-backed JSON stores to SQLite, following the pattern already successfully established by `token-budget-mcp` (E-140).

SQLite provides:
1. **ACID transactions:** Guaranteed atomic writes and reads.
2. **Concurrent access handling:** Built-in file locking to prevent race conditions without external dependencies.
3. **Better performance:** No need to parse/stringify the entire state file for every small update.

#### Implementation Strategy (P-##)
- [ ] P-##: **Migrate `task-synchronizer-mcp` state to SQLite.**
  - Create a new SQLite schema to represent the structure of `state.json` (projects, tasks, stamps).
  - Refactor `get_state`, `add_task`, `update_task_status`, etc., to use SQL queries.
  - Implement a migration script to seamlessly convert existing `.ai/state.json` files to the new `.ai/state.sqlite` database format upon the next tool invocation or initialization.
  - Update `regenerateMarkdown` to pull from the SQLite db instead of the JSON object.

## 2. `patch_file` Optimistic Lock Fallbacks

### The Problem
The `patch_file` tool uses an MD5 hash (`expected_md5`) for optimistic locking. This is good for preventing stale overwrites, but it causes the patch to fail entirely if the file has changed even slightly since it was last read.

When a patch fails due to an MD5 mismatch, the agent is forced to retry the operation (read the file again, re-calculate the MD5, apply the patch again). This "retry loop" wastes full LLM turns and burns significant tokens.

### The Solution: Fuzzy Matching & Auto-Resolution
The `patch-mcp` needs a mechanism to gracefully handle minor file drifts without failing the entire tool call.

#### Implementation Strategy (P-##)
- [ ] P-##: **Implement fuzzy-patching fallback in `patch-mcp`.**
  - If the MD5 check fails, do not immediately reject the patch.
  - Instead, attempt to locate the `old_content` block within the current (changed) file.
  - If `old_content` is still found *exactly once* in the file (meaning the drift happened elsewhere in the file), apply the replacement and return a `[PATCH_APPLIED_WITH_DRIFT]` warning alongside the new MD5.
  - If `old_content` is no longer found (meaning the target block itself was modified), *then* reject the patch and return the standard `[MD5_MISMATCH]` error, forcing a re-read.

This ensures the optimistic lock still protects against destructive overwrites while eliminating unnecessary retry turns for unrelated file modifications.