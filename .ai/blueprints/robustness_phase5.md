# Robustness Phase 5: SQLite Singularity (2026-04-13)

## 1. Eliminate Logic Dependency on `TASKS.md` (Critical)

### The Problem
Several tools (`context-guardian-mcp`, `pre-commit.sh`, `post-tool-log.sh`) still read `.ai/TASKS.md` using `grep` or `readFileSync` to determine if the workspace is "DIRTY" (has open tasks). 

Since `TASKS.md` is a generated view, reading it for logic is:
1.  **Slow**: Requires full file reads and regex parsing.
2.  **Unreliable**: The view might be stale if a tool crashed before `regenerateViews` finished.
3.  **Redundant**: We already have a structured, indexed `tasks` table in SQLite.

### The Solution: SQL-Only Logic
Refactor all programmatic workspace health checks to query `state.sqlite` directly. `TASKS.md` must be treated strictly as a read-only artifact for humans and agent preflights.

#### Implementation:
- **`context-guardian-mcp`**: Replace the `TASKS.md` string parsing in `check_workspace` with a `SELECT count(*) FROM tasks WHERE status='OPEN'` query via `state-db.js`.
- **`pre-commit.sh`**: Update the bash check to use `sqlite3` CLI to verify task counts against the database, removing the fragile comparison between `state.json` and `TASKS.md`.
- **Skills (`ai-archive`, `ai-test`, `ai-digest`)**: Update prompt instructions to use `get_state` summary or direct SQLite queries instead of `grep` patterns on `TASKS.md`.

## 2. Refactor `post-tool-log.sh` (High)

### The Problem
The `post-tool-log.sh` hook still has a fallback to `grep TASKS.md` if `sqlite3` isn't found. This maintains the "Split-Brain" risk.

### The Solution: SQLite Mandate
Make `sqlite3` a hard requirement for logic checks in hooks. If it's missing, emit a `[MISSING_DEP] sqlite3` warning but do not fall back to parsing generated views.

---

## Strategic Tasks (P-##)

- [ ] **P-29: Refactor `context-guardian-mcp` to use SQLite for health checks.**
  - Import `getDb` from `state-db.js`.
  - Replace `TASKS.md` parsing with SQL queries.
- [ ] **P-30: Harden `pre-commit.sh` with SQLite checks.**
  - Use `sqlite3` CLI to verify task consistency.
  - Remove redundant `TASKS.md` vs `state.json` comparison.
- [ ] **P-31: Update Skills to favor `get_state` over `grep TASKS.md`.**
  - Audit `ai-archive`, `ai-test`, `ai-digest`, and `ai-preflight` skills.
  - Standardize on tool-based state awareness.
- [ ] **P-32: Clean up `post-tool-log.sh` fallback logic.**
  - Remove `grep TASKS.md` from the auto-archive trigger.
- [ ] **P-33: Port `task_validator` agent to SQLite.**
  - Update the agent's instructions to use `get_state` instead of reading the full `TASKS.md` into context.