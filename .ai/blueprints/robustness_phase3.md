# Robustness Phase 3: Safety & Persistence (2026-04-13)

## 1. Patch Persistence (High)

### The Problem
`propose-patch-mcp` stores pending patches in an in-memory `Map`. Since AI-OS sessions are short-lived, any patch proposed but not immediately confirmed is lost when the agent process exits.

### The Solution: Disk-Backed Patch Store
Migrate the patch store to a JSON file or SQLite table.
- **Location**: `.ai/patches.json` (or a table in `state.sqlite`).
- **Logic**: Load patches on startup, prune applied/rejected patches, and ensure the `patch_id` is stable across sessions.

## 2. Command Security Bypasses (High)

### The Problem
`safe-exec-mcp` only blocks secrets in the format `key=value`. Commands using spaces or separate flags (e.g., `--token secret_value`) bypass the safety gate.

### The Solution: Lexical Secret Detection
Broaden the security rules to detect secret keywords followed by potential sensitive values, regardless of the assignment operator.
- **Logic**: Use a regex that catches `keyword (\s*=\s*|\s+) value`.

## 3. Transactional Integrity (Medium)

### The Problem
`state-db.js` provides atomic row updates via SQLite, but complex operations like `run_handover` (which updates `tasks`, `deltas`, and `meta`) are not wrapped in a single ACID transaction. A crash mid-handover would leave the state inconsistent.

### The Solution: Transaction Helper
Add a transaction wrapper to `state-db.js`.
- **Logic**: `db.exec("BEGIN"); try { ...; db.exec("COMMIT"); } catch { db.exec("ROLLBACK"); }`.

## 4. Hardcoded Vibe Timeouts (Low)

### The Problem
`vibe-check-mcp` has a hardcoded 15s timeout for navigation. On slow local dev servers or heavy SPAs, this causes frequent "VIBE_BLOCKED" false positives.

### The Solution: Configurable Timeouts
Expose `timeout` as an optional parameter in `run_vibe_audit` and `run_chaos_test`.

---

## Strategic Tasks (P-##)

- [ ] **P-20: Implement disk persistence for `propose-patch-mcp`.**
  - Store pending patches in `.ai/state.sqlite` (add `patches` table) or `.ai/patches.json`.
  - Ensure `list_pending_patches` works across multiple CLI sessions.
- [ ] **P-21: Harden `safe-exec-mcp` secret detection.**
  - Broaden `SECRET_IN_COMMAND` regex to detect space-separated secrets.
- [ ] **P-22: Add transaction support to `state-db.js`.**
  - Export a `withTransaction(aiDir, callback)` helper.
  - Refactor `orchestrator-mcp` `run_handover` to use it.
- [ ] **P-23: Make `vibe-check-mcp` timeouts configurable.**
  - Update tool schema and implementation to accept `timeout_ms`.
- [ ] **P-24: Implement the missing P-18 and P-19 tasks.**
  - Port hooks to `sqlite3`.
  - Add viewport-scoped audits to Vibe. (Crucial for OOM prevention).