# DIGEST — AI-OS v2 (Updated: 2026-04-21)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, and JIT context loading.
- Features Adaptive Thinking (Architect) and Native Computer Use integration (Project Mariner).

## Stack
- Node.js 20+ (MCP servers), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-10 (DONE 2026-04-21), all 10 P-## tasks complete
- Engineer (Claude): IDLE — last task E-6 (DONE 2026-04-19); all 6 E-## tasks complete
- Tester (TestSprite): PASS — 423/423 tests pass (suite grown from 407 to 423 this sprint)

## Current Focus
- All E-## tasks DONE as of 2026-04-19
- All P-## tasks (P-1–P-10) DONE (capabilities blueprint completed)
- Docs audit clean — 0 gaps in README/CONTRIBUTING vs architect.md (ARCH_AUDIT 2026-04-18)

## Key Decisions
- D-001: npm workspaces added at root; @modelcontextprotocol/sdk hoisted; individual MCP packages remain standalone-bootable
- DEVOPS-001: CI gate documented for bootloader resilience tests (T-RES-12–17)
- CAP-001: Adaptive Thinking (`think: "max"`) mapped to Architect for deep planning; Engineer set to standard.
- CAP-002: Native Computer Use (`computer-use-mcp`) to replace `vibe-check-mcp` for sandboxed UI testing.

## Known Risks
- MCP orchestration fragmentation — high orphaned MCP risk (ARCH_AUDIT 2026-04-14)
- CRITIC_STAMP persistence must go through SQLite-first hook (not manual state.json edits)
- Token-burn bloat without JIT loading discipline
- computer-use-mcp requires strict headless sandboxing to prevent host machine escapes

## MCP Servers (20 registered)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp

## Recent Changes (last 10)
- 2026-04-21: interop.md blueprint created — detailed A2A Bridge (advisor-mcp) and HITL Security Gates (approval-mcp) (.ai/blueprints/interop.md)
- 2026-04-21: capabilities.md blueprint created — Adaptive Thinking mapped to Architect, Native Computer Use (computer-use-mcp) to replace vibe-check-mcp (.ai/blueprints/capabilities.md)
- 2026-04-19: install-ai-os.sh run — all 16 MCP servers reinstalled to ~/.ai-os/, .mcp.json regenerated with absolute paths, Gemini frontmatter sanitized (E-6)
- 2026-04-14: DIGEST.md regenerated — E-6 surfaced, docs audit clean stamp added (.ai/DIGEST.md)
- 2026-04-14: CONTRIBUTING.md created — dev setup, skill schemas, Ghost Tool rules, git workflow (CONTRIBUTING.md)
- 2026-04-14: README.md MCP section expanded from 6 to 19 servers in 5 grouped tables; badge updated 407→423 (README.md)
- 2026-04-14: verification-mcp Gemini path check — isGeminiPath conditionalizes required fields; 4 new tests T-05.08–11 (src/mcp/verification-mcp/index.js)
- 2026-04-14: resilience_test.sh extended with T-RES-12–17 (node failure, Python/shell fallback, SQLite PRAGMA check) (tests/resilience_test.sh)
- 2026-04-14: Root package.json added with npm workspaces (src/mcp/*), hoisting SDK, npm test wired to tests/run.sh (package.json)
- 2026-04-14: bootloader.md blueprint created — boot execution flow and fallback CI constraints (.ai/blueprints/bootloader.md)

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest
- 2026-04-21: auto-stamped by Stop hook
- 2026-04-14: SECURITY.md created — computer-use-mcp threat model (T-CU-001–005), 4 P0 vectors documented with required mitigations; THREAT_MODEL.md created with full trust boundary map and 7 threat entries (.ai/SECURITY.md, .ai/THREAT_MODEL.md)- 2026-04-22: auto-stamped by Stop hook
