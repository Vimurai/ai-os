# DIGEST — AI-OS v2 (Updated: 2026-04-26)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, and Structured Outputs.

## Stack
- Node.js 20+ (MCP servers), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — all 14 P-## tasks DONE (last: P-14 Structured Outputs blueprint, 2026-04-26)
- Engineer (Claude): IDLE — all 13 E-## tasks DONE (last: E-13 tool wires + E-12 Structured Outputs, 2026-04-26/27); 644/644 tests pass
- Tester (TestSprite): PASS — 644/644 tests pass (suite grew from 423 → 644 across sprint E-7–E-13)

## Current Focus
- All E-## tasks (E-1–E-13) DONE — sprint fully complete
- All P-## tasks (P-1–P-14) DONE
- No open tasks — awaiting next Architect blueprint from Gemini

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk hoisted; individual MCP packages remain standalone-bootable
- D-002: computer-use-mcp sandboxed — DISPLAY=:99, HOME=/tmp/computer-use-sandbox, screenshots deleted immediately
- D-003: approval-mcp HITL gate — SQLite audit trail (node:sqlite built-in), hardcoded DB_PATH, TTY assertion, maxLength guards
- D-004: cache-manager-mcp assembles architect.md + blueprints/*.md + state.sqlite schema into prompt-cacheable blob; mtime invalidation; SQLite at ~/.ai-os/cache.sqlite
- DEVOPS-001: CI gate for bootloader resilience (T-RES-12–17)

## Known Risks
- MCP orchestration fragmentation — orphaned MCP risk flagged (ARCH_AUDIT 2026-04-14)
- Phantom Tool risk — tools missing/misnamed in registry.json (ARCH_AUDIT 2026-04-26); partially mitigated by E-13
- CRITIC_STAMP persistence must go through SQLite-first hook (not manual state.json edits)
- computer-use-mcp requires Linux-only headless sandboxing (Xvfb + DISPLAY=:99); macOS/Windows unsupported

## MCP Servers (23 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp
- Interop: advisor-mcp (A2A bridge to Gemini), approval-mcp (HITL gate for Tier 3)
- Caching: cache-manager-mcp (Explicit Context Cache — blueprints + SQLite schema)

## Recent Changes (last 10)
- 2026-04-27: Sprint archive — LOG/REVIEWS/SESSION moved to .ai/archive/2026-04/ (E-11 + E-12 complete, 644/644)
- 2026-04-27: E-12 Structured Outputs — 4 JSON Schemas, schema-validator.js, validate_payload tool + _assertSchema guards in task-synchronizer-mcp; 51 tests, 644/644 suite
- 2026-04-27: E-11 cache-manager-mcp — 4 tools, 61 tests, 593/593 suite, D-004 (src/mcp/cache-manager-mcp/)
- 2026-04-26: E-13 tool wires — advisor-mcp, approval-mcp, computer-use-mcp added to 5 agent YAMLs + 10 permissions in .claude/settings.json
- 2026-04-26: P-14 structured-outputs.md blueprint (.ai/blueprints/)
- 2026-04-26: P-13 caching.md blueprint (.ai/blueprints/)
- 2026-04-24: E-10 approval-mcp — HITL Tier 3 gate, 37 tests, 531/531 suite (src/mcp/approval-mcp/)
- 2026-04-22: E-9 advisor-mcp — A2A bridge to Gemini, 34 tests, 493/493 suite (src/mcp/advisor-mcp/)
- 2026-04-22: E-8 computer-use-mcp — 7 tools, sandbox, 34 tests, 458/458 suite (src/mcp/computer-use-mcp/)
- 2026-04-21: E-7 Adaptive Thinking — thinking_effort:high in .gemini/settings.json, standard for Claude

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest
