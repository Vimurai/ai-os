# Robustness Phase 2: State Consolidation & OOM Prevention (2026-04-03)

## 1. Split-Brain State Prevention (Critical)

### The Problem
The current system has a "Split-Brain" state problem. `task-synchronizer-mcp` (E-156) uses `state.sqlite` as its primary store, but `orchestrator-mcp` still writes directly to `state.json` via the legacy `shared/state-writer.js`. While an `mtime` guard attempts to sync them, concurrent writes will cause data loss.

### The Solution: SQLite-First Orchestrator
`orchestrator-mcp` must be refactored to treat `state.sqlite` as the primary store.
- **Implementation**: Port the `DatabaseSync` logic and schema from `task-synchronizer-mcp` into a shared helper `src/mcp/shared/state-db.js`.
- **Migration**: Deprecate `src/mcp/shared/state-writer.js` (which relies on `state.json`).
- **Logic**: `run_handover` and `run_preflight` must query/mutate the SQLite tables (`tasks`, `stamps`, `deltas`, `meta`) directly.

## 2. V8 Heap Exhaustion Prevention (Mid-Level)

### The Problem
`context-guardian-mcp` uses `.split("\n")` on `git grep` output. On large projects, this can allocate a massive array of strings, exceeding the Node.js heap limit or causing severe GC thrashing.

### The Solution: Iterative Scanning
Refactor the result processing to use a single string and iterative regex execution.
- **Code**: `while ((match = regex.exec(stdout)) !== null && count < 100) { ... }`
- **Benefit**: Zero array allocation for lines that are ultimately sliced away.

## 3. Silent Failure & CI Blindness (Mid-Level)

### The Problem
- **Orchestrator**: `readBoundedLines` has a silent `catch` block that returns an empty string on permission/IO errors.
- **Test Runner**: `tests/run.sh` can report `Total: 0 failed` even if a sub-suite script crashed or exited early (e.g., due to `set -e` in a sub-shell).

### The Solution: Explicit Error Propagation
- **Orchestrator**: Log IO errors to `stderr` so the agent can diagnose permission issues.
- **Tests**: Ensure the master runner captures the exit code of every sub-script and fails the entire run if any sub-script returns non-zero.

---

## Strategic Tasks (P-##)

- [ ] **P-13: Create `src/mcp/shared/state-db.js` and consolidate SQLite schema.**
  - Extract schema and `DatabaseSync` initialization from `task-synchronizer-mcp`.
  - Ensure WAL mode and shared access patterns are consistent.
- [ ] **P-14: Refactor `orchestrator-mcp` to use `state-db.js`.**
  - Replace `state-writer.js` imports.
  - Update `run_handover` to mutate the SQLite `tasks` table.
  - Update `run_preflight` to query SQLite `meta` (digest_stale) and `deltas`.
- [ ] **P-15: Refactor `task-synchronizer-mcp` to use `state-db.js`.**
  - Remove redundant schema definitions.
  - Maintain the "Backwards Compat View" logic (writing `state.json` after SQLite updates).
- [ ] **P-16: Implement iterative regex scanning in `context-guardian-mcp`.**
  - Fix OOM risk in `strict` mode result processing.
- [ ] **P-17: Harden `tests/run.sh` and `orchestrator-mcp` error reporting.**
  - Ensure CI-breaking failures are never silent.