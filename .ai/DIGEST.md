# DIGEST — AI-OS v2 (Updated: 2026-04-28)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, Structured Outputs, and a collapsed bootloader CLI.

## Stack
- Node.js 22+ (MCP servers, node:sqlite built-in), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests/install), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-16 (CLI collapse blueprint, 2026-04-28); P-15 still open (AUDIT-STRATEGIC follow-up on structured-outputs §3)
- Engineer (Claude): ACTIVE — E-1..E-36 + E-38 DONE; only E-37 open (audit follow-up: ~115 grep-vs-source assertions to migrate)
- Tester (TestSprite): PASS — 689/689 baseline post-CLI-collapse; behavioral mcp_behavioral_test.sh 40/40, registry_sync_test.sh 5/5

## Current Focus
- E-37: bulk-migrate ~115 remaining grep-vs-source assertions to behavioral roundtrips across 9 suites (Tier 1, only open task)
- P-15: AUDIT-STRATEGIC structured-outputs §3 — bin/ai is bash, no LLM API integration; mark Phase 2 or design API layer (Architect-owned)

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk pinned exactly to 1.27.1, children "*" (E-20)
- D-002: computer-use-mcp sandboxed — DISPLAY=:99, HOME=/tmp/computer-use-sandbox; env now carried in registry.json + propagated by `ai sync` + asserted by registry_sync_test.sh (E-38)
- D-003: approval-mcp HITL gate — SQLite audit trail, hardcoded DB_PATH, TTY assertion, maxLength guards
- D-004: cache-manager-mcp assembles architect.md + blueprints/*.md + state.sqlite schema; mtime invalidation
- D-005: structured logging unified — src/mcp/shared/logger.js (NDJSON to stderr) across all 21 MCP servers (E-18)
- D-006: `ai` CLI collapsed to bootloader-only (install/init/sync/doctor/uninstall/version); operational verbs migrated to skills; tmux split-pane is the recommended workflow (E-34/E-35/E-36)

## Known Risks
- ~115 source-grep test assertions still fragile across 9 suites — tracked as E-37
- structured-outputs.md §3 over-promises: bin/ai is a bash wrapper, no LLM API integration (P-15)
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported
- Local .git/hooks/pre-commit drifted from canonical hooks/pre-commit.sh (Tier 1 bypass + SQLite stamp lookup uncommitted) — flagged 2026-04-28

## MCP Servers (23 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp (BLOCK_RULES extended E-23), context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp (sandbox env enforced E-38)
- Interop: advisor-mcp (A2A bridge to Gemini, env allowlisted E-17), approval-mcp (HITL Tier 3)
- Caching: cache-manager-mcp (Explicit Context Cache, finally-close fix E-25)

## Recent Changes (last 10)
- 2026-05-05: E-36 README/CONTRIBUTING — tmux split-pane workflow + post-collapse skill flow documented
- 2026-05-05: E-35 1:1 skill mapping — removed broken `ai *` refs across 5 templates, 6 toml descs, 3 agents, 6 SKILLs, both bootloaders
- 2026-05-04: E-34 src/bin/ai collapsed 2087→~1535 lines; 8 user verbs deprecated to skill pointers; 689/689 PASS
- 2026-04-28: E-38 computer-use-mcp sandbox env carried in registry.json + propagated by `ai sync` + registry_sync_test.sh asserts contract
- 2026-04-28: E-33 hooks/pre-commit.sh check_registry_sync — gates registry/.mcp.json/install drift
- 2026-04-28: E-32 .gemini/skills/ shared skills (ai-context-check/debug/handoff/log) backfilled into tracked tree
- 2026-04-28: E-31 _SKILLS_INDEX.md gitignored + deterministic generator (LC_ALL=C sort)
- 2026-04-28: E-30 mcp_integration_test.sh source-grep block (12) → behavioral roundtrips; vibe-check-mcp coverage added
- 2026-04-28: E-27 tests/lib/mcp-client.sh stdio JSON-RPC harness + 37→40 behavioral assertions
- 2026-04-28: P-16 cli-collapse.md blueprint authored (Gemini)

---
DIGEST must be accurate or flagged as stale. If stale, run: skill: ai-digest
