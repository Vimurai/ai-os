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

## 3. Unbounded `spawnSync` Calls in MCP Servers

### The Problem
Multiple MCP servers (`github-bridge-mcp`, `lsp-mcp`, `archive-manager-mcp`, `propose-patch-mcp`) use `spawnSync` to execute child processes (like `gh`, `tsc`, `patch`). While some have `timeout` options configured, none of them configure a `maxBuffer` option.
By default, Node's `spawnSync` has a 1MB `maxBuffer`. If a process (like a TypeScript compiler on a large codebase or a `gh` command pulling large issues) emits more than 1MB of stdout/stderr, the Node process will crash with an `ERR_CHILD_PROCESS_STDIO_MAXBUFFER` error. Furthermore, unconstrained stdout can leak massive amounts of text back into the LLM context window, causing a severe token burn.

### The Solution: Explicit `maxBuffer` Boundaries
All `spawnSync` and `execSync` invocations must be explicitly bounded.

#### Implementation Strategy (P-4)
- [ ] P-4: **Add `maxBuffer` limits to all `spawnSync` calls.**
  - Audit all MCP servers for `spawnSync` and `execSync`.
  - Add `maxBuffer: 10 * 1024 * 1024` (10MB) to all options objects to prevent silent crashes, or an appropriate lower limit if the output is meant to be piped directly to the LLM.

## 4. Unbounded `git grep` in `context-guardian-mcp`

### The Problem
Task E-155 correctly refactored `context-guardian-mcp`'s strict mode to use `git grep` instead of recursively loading files into Node's memory. However, the command does not cap the number of results. In a legacy codebase with thousands of `TODO` or `FIXME` markers, this will dump a massive list back to the LLM, causing a major token leak.

### The Solution: Result Capping
The output must be safely paginated or capped.

#### Implementation Strategy (P-6)
- [ ] P-6: **Add result bounding to the `git grep` call in `context-guardian-mcp`.**
  - Pipe the `git grep` output through `head -n 100` or slice the array in JavaScript before returning the result.
  - Append a warning to the output if the result set was truncated (e.g., `"...and X more unresolved markers found."`).

## 5. Unbounded Context Leak in `github-bridge-mcp`

### The Problem
In `github-bridge-mcp`, the `get_issue` tool safely truncates comments to 200 characters, but it injects the main `issue.body` directly into the LLM context without bounds (`issue.body || "(no description)"`). If a user pastes a massive crash log or heap dump into an issue description, it will silently blow out the agent's context window and burn tokens.

### The Solution: Length Bounding
Add a bounds limit to protect the context window.
- If `issue.body` exceeds 5000 characters, slice it and append `\n... (truncated)` to prevent token leaks.

## 6. Memory Burner in `memory-manager-mcp`

### The Problem
The `export_signature` tool uses `readFileSync(archPath, "utf8").split("\n")[0]` to grab the `architect_v` string from `.ai/architect.md`. This synchronously loads the entire file into a V8 string, splits it into an array of lines, grabs index 0, and garbage collects the rest.

### The Solution: Streamed Reading
Port the `readHead(filePath, HEAD_BYTES = 4096)` helper introduced in E-154 (`context-invoker-mcp`) to `memory-manager-mcp` to avoid full file buffer allocations when extracting the first line.

## 7. OOM Risk on Massive Array Splits in `blueprint-aligner-mcp`

### The Problem
The `generateDelta` function processes the `diff` string (which can be up to 10MB) via `diff.split("\n").filter(...)`. Splitting a 10MB string by newline allocates hundreds of thousands of string references in memory, risking Node heap crashes.

### The Solution: Iterative Regex
Replace `.split("\n")` with an iterative RegExp `.exec()` loop over the single string or process the diff incrementally without allocating the full array.

## 8. Inefficient File Array Splitting in `orchestrator-mcp`

### The Problem
In `run_preflight`, to truncate `TASKS.md` to 80 lines for context, it does a full `readFileSync` followed by `content.split("\n").slice(0, 80).join("\n")`. Since `TASKS.md` grows endlessly in long projects, this memory allocation compounds on every single turn.

### The Solution: Bounded Reading
Limit the read directly or avoid splitting the entire file into memory just to extract the top 80 lines.

## 9. Broken Blueprint Extraction in `orchestrator-mcp` (Post E-151)

### The Problem
When generating the `IMPLEMENTATION_DELTA`, `run_handover` searches for the task ID inside `architect.md`. Since E-151 fragmented `architect.md` into `.ai/blueprints/<domain>.md`, if the task is mapped in a domain file, `run_handover` will fail to extract the blueprint section.

### The Solution: Domain Fallback
Refactor the extraction logic to scan through `.ai/blueprints/*.md` if the task ID isn't found in the root index.

## 10. Missing Size Guard in `patch-mcp`

### The Problem
`patch_file` uses `readFileSync(abs, "utf8")` to load files for string replacement. If directed at a multi-megabyte asset or transpiled chunk, it can freeze or crash the server.

### The Solution: File Size Bounds
Add a `statSync(abs).size` guard to reject files > 5MB with `[FILE_TOO_LARGE]`, directing the agent to use other tools or strategies instead.