# Robustness Phase 4: ACID Integrity & Tool Safety (2026-04-13)

## 1. Atomic Patch Persistence (Critical)

### The Problem
`propose-patch-mcp` currently uses `.ai/patches.json` for persistence. This JSON-based approach lacks locking mechanisms, creating a high risk of "Lost Updates" where one agent's patch proposal overwrites another during parallel sessions.

### The Solution: SQLite Patch Table
Migrate the `patches` store from a JSON file to a dedicated table in `state.sqlite`.
- **Implementation**: Update `state-db.js` to include a `patches` table:
  ```sql
  CREATE TABLE IF NOT EXISTS patches (
    id           TEXT PRIMARY KEY,
    path         TEXT NOT NULL,
    diff_content TEXT NOT NULL,
    description  TEXT,
    caller_role  TEXT,
    created_at   TEXT NOT NULL,
    status       TEXT DEFAULT 'pending'
  );
  ```
- **Refactor**: Update `propose-patch-mcp` to use `state-db.js` for all patch operations.

## 2. Tool Safety False-Positive Remediation (High)

### The Problem
The broadened secret-in-command regex in `safe-exec-mcp` (P-21) is too greedy. It blocks benign research commands like `grep token filename` or `find . -name "*secret*"` because it treats any space-separated value after a keyword as a leaked secret.

### The Solution: Read-Only Command Whitelist
Implement an exclusion list for common read-only research tools.
- **Logic**: If the command starts with `grep`, `rg`, `ls`, `find`, `cat`, `head`, `tail`, `wc`, `stat`, `file`, or `git log/diff/status`, bypass the `SECRET_IN_COMMAND` check.
- **Benefit**: Restores agent research autonomy while maintaining the block for `curl`, `wget`, `npm`, and other network/mutation tools.

## 3. Full Transactional Handover (Medium)

### The Problem
`orchestrator-mcp` currently updates task status *outside* the implementation delta transaction. If the database locks or crashes after the status update but before the delta write, the system state becomes inconsistent.

### The Solution: Unified Transaction
Refactor `run_handover` to wrap the task status update and implementation delta insertion in a single atomic transaction using `withTransaction`.

## 4. SQLite Sync Removal (Medium)

### The Problem
`task-synchronizer-mcp` currently runs a "Sync from JSON" check on every turn. Since `regenerateViews` writes `state.json` *after* SQLite updates, the JSON mtime is always newer, triggering a redundant and expensive full re-import on every tool call.

### The Solution: SQLite-First Singularity
Remove `_syncFromJsonIfNewer` from `task-synchronizer-mcp`. The system is now SQLite-first; `state.json` is a read-only view.

---

## Strategic Tasks (P-##)

- [ ] **P-25: Migrate `propose-patch-mcp` to SQLite persistence.**
  - Add `patches` table to `state-db.js`.
  - Refactor `propose-patch-mcp` to use `state-db.js`.
- [ ] **P-26: Implement research-command whitelist in `safe-exec-mcp`.**
  - Fix greedy secret detection to allow `grep`, `find`, and other read-only tools.
- [ ] **P-27: Wrap `run_handover` in a single unified transaction.**
  - Ensure task status and implementation deltas are written atomically.
- [ ] **P-28: Remove redundant JSON-to-SQLite sync logic.**
  - Excise `_syncFromJsonIfNewer` from `task-synchronizer-mcp`.
- [ ] **P-29: Improve DB error visibility in `run_preflight`.**
  - Replace empty `catch` with explicit `stderr` reporting for SQLite issues.