# DIGEST — AI-OS v2 (Updated: 2026-04-14)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, and JIT context loading.

## Stack
- Node.js 20+ (MCP servers), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-8 (DONE 2026-04-14), all 8 P-## tasks complete
- Engineer (Claude): IDLE — last task E-5 (DONE 2026-04-14), all 5 E-## tasks complete
- Tester (TestSprite): PASS — 423/423 tests pass (suite grown from 407 to 423 this sprint)

## Current Focus
- No open tasks — all E-## and P-## tasks marked DONE as of 2026-04-14
- Next: Await new Gemini blueprint or user-initiated sprint

## Key Decisions
- D-001: npm workspaces added at root; @modelcontextprotocol/sdk hoisted; individual MCP packages remain standalone-bootable
- DEVOPS-001: CI gate documented for bootloader resilience tests (T-RES-12–17)
- Gemini YAML schema: does NOT require `disable-model-invocation`, `user-invocable`, or `allowed-tools` (per P-8)

## Known Risks
- MCP orchestration fragmentation — high orphaned MCP risk (ARCH_AUDIT 2026-04-14)
- CRITIC_STAMP persistence must go through SQLite-first hook (not manual state.json edits)
- Token-burn bloat without JIT loading discipline

## MCP Servers (19 registered)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp

## Recent Changes (last 10)
- 2026-04-14: CONTRIBUTING.md created — dev setup, skill schemas, Ghost Tool rules, git workflow (CONTRIBUTING.md)
- 2026-04-14: README.md MCP section expanded from 6 to 19 servers in 5 grouped tables; badge updated 407→423 (README.md)
- 2026-04-14: verification-mcp Gemini path check — isGeminiPath conditionalizes required fields; 4 new tests T-05.08–11 (src/mcp/verification-mcp/index.js)
- 2026-04-14: resilience_test.sh extended with T-RES-12–17 (node failure, Python/shell fallback, SQLite PRAGMA check) (tests/resilience_test.sh)
- 2026-04-14: Root package.json added with npm workspaces (src/mcp/*), hoisting SDK, npm test wired to tests/run.sh (package.json)
- 2026-04-14: bootloader.md blueprint created — boot execution flow and fallback CI constraints (.ai/blueprints/bootloader.md)
- 2026-04-14: workspace.md blueprint created — npm workspaces layout and dependency deduplication (.ai/blueprints/workspace.md)
- 2026-04-14: agents.md blueprint created — all Claude, Gemini, Shared skills mapped (.ai/blueprints/agents.md)
- 2026-04-14: mcp.md blueprint created — all 16 MCP servers mapped by capability (.ai/blueprints/mcp.md)
- 2026-04-14: architect.md Sections 1-6 rewritten with actual AI-OS philosophy and Triad architecture (.ai/architect.md)

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest
