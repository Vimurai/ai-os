# DIGEST — AI-OS (Updated: 2026-04-14)

## Product
- CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.

## Stack
- Bash (zero-dependency CLI core), Node.js (MCP servers), SQLite (Exclusive system of record; WAL mode).
- Playwright (vibe-check-mcp), file-based markdown memory (read-only generated views).
- `sqlite3` CLI for atomic state checks in shell hooks; `os.homedir()` for reliable path resolution.

## Triad Health
- Architect (Gemini): IDLE — Robustness phases 1-8 blueprints complete (P-1 through P-47); no open P-## tasks.
- Engineer (Claude): IDLE — Robustness phases 2-8 implemented (P-13 through P-47); all tasks closed.
- Tester (TestSprite): Active — 334/336 tests pass; 2 pre-existing e140 failures (non-regression).

## Current Focus
- Robustness sprint complete (Phases 1-8) — system stabilized on SQLite-first architecture.
- Performance/Hygiene: Iterative regex for OOM prevention, viewport-scoped audits, and explicit resource cleanup.
- Resilience: Unified ACID transactions, multi-route vibe fault tolerance, and explicit implementation delta handover.

## Key Decisions
- D-010: SQLite-First Singularity (P-28/P-44) — `state.sqlite` is the exclusive system of record; `state.json` and `.md` are views.
- D-011: Explicit Handover (P-38) — implementation deltas require manual acknowledgment via `mark_deltas_read`.
- §35: ANTI-DRIFT PROTOCOL — Claude is Engineer only; architecture decisions deferred to Gemini.
- §39: Architectural Fragmentation — domain blueprints loaded JIT from `.ai/blueprints/` to prevent context bloat.
- E-147: UPDATE.md deprecated globally — intent and state managed via conversation context and SQLite.

## Known Risks
- P1: [ARCH_AUDIT] 2026-03-23 — Architectural Intelligence dirs missing; 2 MCPs (orchestrator, risk-analyzer) not in registry.json.
- M-002 (MEDIUM/accepted): ai-exec orphan worktree race condition in concurrent runs.

## MCP Servers
- filesystem, memory, TestSprite, vibe-check-mcp, task-synchronizer-mcp, safe-exec-mcp.
- blueprint-aligner-mcp, context-guardian-mcp, risk-analyzer-mcp, context-invoker-mcp.
- archive-manager-mcp, orchestrator-mcp, memory-manager-mcp, verification-mcp.
- lsp-mcp, patch-mcp, token-budget-mcp, propose-patch-mcp, github-bridge-mcp.

## Recent Changes (last 10)
- 2026-04-14: P-47: state-db.js: Migrated to os.homedir() for reliable home path resolution. (.ai/blueprints/robustness_phase8.md)
- 2026-04-14: P-46: install-ai-os.sh: Extended orphan cleanup to src/shared/ directory. (.ai/blueprints/robustness_phase8.md)
- 2026-04-14: P-45: ai onboard: Focus extraction refactored to query SQLite via sqlite3 CLI. (.ai/blueprints/robustness_phase8.md)
- 2026-04-14: P-41: safe-exec-mcp: Added command normalization to resist secret obfuscation. (.ai/blueprints/robustness_phase7.md)
- 2026-04-14: P-39: vibe-check-mcp: Added per-route isolation to prevent audit crashes on 404/timeouts. (.ai/blueprints/robustness_phase7.md)
- 2026-04-14: P-38: orchestrator-mcp: Implemented explicit delta acknowledgment via mark_deltas_read. (.ai/blueprints/robustness_phase7.md)
- 2026-04-13: P-36: vibe-check-mcp: Fixed context leak via try/finally browser session cleanup. (.ai/blueprints/robustness_phase6.md)
- 2026-04-13: P-35: CAPABILITIES.md: Added explicit write permissions for ~/.ai-os/*.sqlite. (.ai/blueprints/robustness_phase6.md)
- 2026-04-13: P-34: Gemini Agents: Restored YAML frontmatter with least-privilege toolsets to all 6 sub-agents. (.ai/blueprints/robustness_phase6.md)
- 2026-04-13: P-25: propose-patch-mcp: Migrated patch store to SQLite for cross-session persistence. (.ai/blueprints/robustness_phase4.md)
