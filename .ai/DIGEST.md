# DIGEST — AI-OS v2 (Updated: 2026-04-14)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, and JIT context loading.
- Features Adaptive Thinking (Architect), Native Computer Use, A2A Bridge (advisor-mcp), HITL Gate (approval-mcp), and Explicit Context Caching blueprints.

## Stack
- Node.js 20+ (MCP servers), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-14 (DONE 2026-04-26), all 14 P-## tasks complete
- Engineer (Claude): ACTIVE — E-11 and E-12 open; last task E-10 (DONE 2026-04-24), 531/531 tests pass
- Tester (TestSprite): PASS — 531/531 tests pass (suite grown from 407 to 531 this sprint)

## Current Focus
- E-11: Implement API-level Explicit Context Caching per .ai/blueprints/caching.md (Tier 2, OPEN)
- E-12: Migrate Triad state to native Structured Outputs (JSON Schema) per .ai/blueprints/structured-outputs.md (Tier 2, OPEN)
- All P-## tasks (P-1–P-14) DONE as of 2026-04-26

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk hoisted; individual MCP packages remain standalone-bootable
- D-002: computer-use-mcp registered with DISPLAY=:99 + HOME=/tmp/computer-use-sandbox sandbox enforcement
- D-003: approval-mcp HITL gate — SQLite audit trail (node:sqlite built-in), hardcoded DB_PATH, TTY assertion
- DEVOPS-001: CI gate for bootloader resilience tests (T-RES-12–17)
- CAP-001/CAP-002: Adaptive Thinking for Architect; Native Computer Use replaces vibe-check-mcp for UI testing

## Known Risks
- MCP orchestration fragmentation — high orphaned MCP risk (ARCH_AUDIT 2026-04-14)
- CRITIC_STAMP persistence must go through SQLite-first hook (not manual state.json edits)
- computer-use-mcp requires strict headless sandboxing (Linux-only: Xvfb + DISPLAY=:99)
- Token-burn bloat without JIT loading discipline — E-11 caching mitigates this

## MCP Servers (22 registered)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp
- Interop: advisor-mcp (A2A bridge to Gemini), approval-mcp (HITL gate for Tier 3)

## Recent Changes (last 10)
- 2026-04-24: approval-mcp implemented (E-10) — HITL Tier 3 gate, 37 tests, 531/531 suite, all T-HITL mitigations enforced (src/mcp/approval-mcp/)
- 2026-04-22: advisor-mcp implemented (E-9) — A2A bridge to Gemini, ask_architect tool, [A2A_RULING] logged, 34 tests, 493/493 suite (src/mcp/advisor-mcp/)
- 2026-04-22: computer-use-mcp implemented (E-8) — 7 tools, DISPLAY=:99 sandbox, 34 tests, 458/458 suite, Tier 3 critics PASS (src/mcp/computer-use-mcp/)
- 2026-04-26: caching.md and structured-outputs.md blueprints created (P-13, P-14) (.ai/blueprints/)
- 2026-04-21: interop.md blueprint created — A2A Bridge + HITL Gate designs (P-11, P-12) (.ai/blueprints/interop.md)
- 2026-04-21: capabilities.md blueprint created — Adaptive Thinking + Computer Use (P-9, P-10) (.ai/blueprints/capabilities.md)
- 2026-04-21: E-7 — Adaptive Thinking settings injected (.gemini/settings.json, .claude/settings.json)
- 2026-04-19: E-6 — install-ai-os.sh run; 16 MCP servers reinstalled to ~/.ai-os/, .mcp.json regenerated
- 2026-04-14: E-5 — CONTRIBUTING.md created with skill schemas, Ghost Tool rules, git workflow
- 2026-04-14: E-4 — README.md MCP section expanded from 6 to 19 servers; badge updated 407→423

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest
