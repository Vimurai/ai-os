# DIGEST — AI-OS v2 (Updated: 2026-04-27)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, and Structured Outputs.

## Stack
- Node.js 22+ (MCP servers, node:sqlite built-in), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-14 (Structured Outputs blueprint, 2026-04-26); P-15 open (AUDIT-STRATEGIC follow-up on structured-outputs §3)
- Engineer (Claude): ACTIVE — E-1 through E-29 DONE; audit sprint E-14–E-29 just landed; E-30–E-33 queued
- Tester (TestSprite): PASS — 644/644 baseline; behavioral MCP roundtrip harness added (tests/lib/mcp-client.sh, E-27)

## Current Focus
- E-30: bulk-migrate ~128 grep-vs-source assertions to behavioral roundtrips (Tier 1)
- E-31: make `ai sync` _SKILLS_INDEX.md generation deterministic (Tier 2)
- E-33: add pre-commit/CI hook running registry_sync_test.sh + run.sh (Tier 1)

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk pinned exactly to 1.27.1, children use "*" (E-20)
- D-002: computer-use-mcp sandboxed — DISPLAY=:99, HOME=/tmp/computer-use-sandbox, env allowlist (no spread)
- D-003: approval-mcp HITL gate — SQLite audit trail, hardcoded DB_PATH, TTY assertion, maxLength guards
- D-004: cache-manager-mcp assembles architect.md + blueprints/*.md + state.sqlite schema; mtime invalidation
- D-005: structured logging unified — src/mcp/shared/logger.js (NDJSON to stderr) across all 21 MCP servers (E-18)

## Known Risks
- ~128 source-grep test assertions still fragile to cosmetic edits (E-30 follow-up)
- `ai sync` regenerates _SKILLS_INDEX.md non-deterministically — spurious diffs every sync (E-31)
- Four shared skills (.gemini/skills/ai-context-check, ai-debug, ai-handoff, ai-log) untracked in git (E-32)
- No pre-commit/CI gate enforcing registry sync — root cause of 2026-04-27 audit could recur (E-33)
- structured-outputs.md §3 over-promises: bin/ai is a bash wrapper, no LLM API integration (P-15)
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported

## MCP Servers (23 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp (BLOCK_RULES extended E-23), context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp
- Interop: advisor-mcp (A2A bridge to Gemini, env allowlisted E-17), approval-mcp (HITL Tier 3)
- Caching: cache-manager-mcp (Explicit Context Cache, finally-close fix E-25)

## Recent Changes (last 10)
- 2026-04-28: E-29 archive-manager-mcp ai-bin locator chain (env override + 5 fallbacks + PATH)
- 2026-04-28: E-27 tests/lib/mcp-client.sh stdio JSON-RPC harness + 37 behavioral assertions
- 2026-04-28: E-20 @modelcontextprotocol/sdk pinned exact 1.27.1 at root, children "*"
- 2026-04-28: E-18 src/mcp/shared/logger.js — structured NDJSON across all 21 MCP servers
- 2026-04-28: E-15 state-db.js getDb() now keys cached connections by aiDir (Map)
- 2026-04-27: E-19 computer-use-mcp inputSchema tightened (integer/min/max, maxLength caps)
- 2026-04-27: E-17 advisor-mcp invokeGemini() env allowlist (no ...process.env spread)
- 2026-04-27: E-23 safe-exec-mcp BLOCK_RULES added DD/MKFS/FIND_DELETE/REDIRECT/CHMOD_ROOT
- 2026-04-27: E-21 src/mcp/context-invoker-mcp/node_modules untracked; .gitignore **/node_modules
- 2026-04-27: Sprint archive — LOG/REVIEWS/SESSION moved to .ai/archive/2026-04/

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest
- 2026-05-05: auto-stamped by Stop hook
