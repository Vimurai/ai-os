# Robustness Phase 8: Resource Hygiene & Standardization (2026-04-14)

## 1. Vibe Check Completeness (High)

### The Problem
While `run_vibe_audit` and `run_chaos_test` were updated to support configurable timeouts (P-23), `get_performance_metrics` was missed. Additionally, `get_performance_metrics` does not explicitly close the CDP session (`client`), which can lead to minor memory leaks in the headless browser.

### The Solution: Vibe Parity
- **Schema**: Add `timeout_ms` to `get_performance_metrics`.
- **Implementation**: Close the CDP `client` session in a `finally` block.

## 2. Stale Documentation & Fallbacks (Medium)

### The Problem
- **`task-synchronizer-mcp`**: The JSDoc header still claims that `orchestrator-mcp` writes `state.json` directly. This is stale information (P-14 refactored it to use SQLite).
- **`ai onboard`**: The focus extraction logic still relies exclusively on `python3` parsing `state.json`.

### The Solution: SQLite-First Alignment
- **Docs**: Update `task-synchronizer-mcp` headers.
- **CLI**: Update `ai onboard` to query `state.sqlite` for the project focus using `sqlite3` CLI, falling back to the JSON view only if necessary.

## 3. Installer Robustness (Medium)

### The Problem
`install-ai-os.sh` now has a `purge_orphans` function (P-37), but it doesn't yet cover the `shared/` directory, which may contain legacy skills or utilities from v2.

### The Solution: Full Purge
Extend the orphan cleanup to include the `shared/` directory.

---

## Strategic Tasks (P-##)

- [ ] **P-43: Add `timeout_ms` and CDP cleanup to `get_performance_metrics`.**
  - Ensure all Vibe tools have consistent schemas and resource management.
- [ ] **P-44: Clean up stale documentation in `task-synchronizer-mcp`.**
  - Remove misleading "NOTE" about orchestrator direct writes.
- [ ] **P-45: Refactor `ai onboard` focus extraction to use SQLite.**
  - Use `sqlite3` CLI to pull focus from the `project` table.
- [ ] **P-46: Extend installer orphan cleanup to `shared/` directory.**
  - Ensure a clean global installation state.
- [ ] **P-47: Update `state-db.js` to use `os.homedir()` for token budget.**
  - Replace fragile `process.env.HOME || "~"` logic. (Requires `import os from "os"`).