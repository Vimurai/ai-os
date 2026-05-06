# DIGEST — AI-OS v2 (Updated: 2026-05-06)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, Structured Outputs, sandboxed code execution, dynamic MCP routing, and a collapsed bootloader CLI.

## Stack
- Node.js 22+ (MCP servers, node:sqlite built-in), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces (monorepo)

## Triad Health
- Architect (Gemini): IDLE — last task P-20 (git-hooks call-by-reference stub blueprint, 2026-05-05)
- Engineer (Claude): IDLE — all 56 tasks DONE; latest E-41 (git-hook stub model, 2026-05-06)
- Tester (TestSprite): PASS — 799/799 baseline post-E-41; behavioral mcp_behavioral_test.sh extended; new git_hooks_stub_test.sh 28/28; verify_compliance 63/63 clean

## Current Focus
- (none) — state.json focus is null; awaiting next P-## from Architect or new audit cycle
- Open ALIGN_FAIL (2026-05-06): aligner flagged architect.md edit + "../" pattern + orphan warnings on .claude/agents during E-41 commit prep — pre-existing false positives per Tier 3 disposition (Gemini-authored P-17/P-20; canonical ESM sibling import). Manual reconciliation recorded in REVIEWS.md.

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk pinned exactly to 1.27.1, children "*" (E-20)
- D-002: computer-use-mcp sandboxed — DISPLAY=:99, HOME=/tmp/computer-use-sandbox; env carried in registry.json + propagated by `ai sync` + asserted by registry_sync_test.sh (E-38)
- D-003: approval-mcp HITL gate — SQLite audit trail, hardcoded DB_PATH, TTY assertion, maxLength guards
- D-004: cache-manager-mcp assembles architect.md + blueprints/*.md + state.sqlite schema; mtime invalidation
- D-005: structured logging unified — src/mcp/shared/logger.js (NDJSON to stderr) across all 21 MCP servers (E-18)
- D-006: `ai` CLI collapsed to bootloader-only (install/init/sync/doctor/uninstall/version); operational verbs migrated to skills; tmux split-pane is the recommended workflow (E-34/E-35/E-36)
- D-007: Test gate is behavioral-first — tool registration via mcp_assert_tool_listed / mcp_assert_tool_param_required over stdio JSON-RPC; source-grep retained only for security anti-pattern checks (E-37)
- D-008: code-execution-mcp sandbox — fail-closed Docker boundary (network=none, read-only, cap-drop=ALL, --user=65534, tmpfs noexec/nosuid, pids-limit=64, mem 512m, no docker.sock leak); no bare-metal fallback (E-39)
- D-009: mcp-router progressive tool discovery + JSON-RPC stdio proxy with active-domain gate + registry allowed-tools mirror (RBAC defense-in-depth) (E-40)
- D-010: git hooks installed as 12-13 line execution stubs (call-by-reference to ~/.ai-os/hooks/); fail-closed pre-commit, fail-open post-commit; `ai sync` auto-upgrades legacy copy-mode hooks (E-41)

## Known Risks
- Persistent ALIGN_FAIL false positives — aligner cannot infer authorship of architect.md edits (Gemini-owned blueprints), and literal-matches "../" on canonical ESM sibling imports. Manual disposition required per Tier 3 commit (recurring 2026-05-05 / 2026-05-06).
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported.
- code-execution-mcp depends on Docker daemon — fail-closed when unavailable; no bare-metal fallback by design.
- structured-outputs.md is Phase 1 (runtime MCP _assertSchema only); full API-level enforcement deferred to Phase 2 if/when bin/ai gains LLM integration.
- Local .git/hooks/pre-commit historically drifted from canonical (Tier 1 bypass + SQLite stamp lookup) — partly mitigated by E-41 stub model + auto-upgrade on `ai sync`; verify on next sprint.

## MCP Servers (24 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp (BLOCK_RULES extended E-23), context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp (sandbox env enforced E-38)
- Interop: advisor-mcp (A2A bridge to Gemini, env allowlisted E-17), approval-mcp (HITL Tier 3)
- Caching: cache-manager-mcp (Explicit Context Cache, finally-close fix E-25)
- Compute: code-execution-mcp (Docker sandbox, fail-closed E-39)
- Routing: mcp-router (progressive discovery + RBAC mirror E-40)

## Recent Changes (last 10)
- 2026-05-06: E-41 git-hook execution-stub model — install_git_hooks emits 12-13 line stubs forwarding to ~/.ai-os/hooks; do_sync auto-upgrades legacy copies; new git_hooks_stub_test.sh (28/28); 799/799 PASS
- 2026-05-05: P-20 git-hooks.md blueprint — call-by-reference stub model to seal canonical-vs-local drift (Gemini)
- 2026-05-05: E-40 mcp-router server — list_domains/activate_domain/proxy_call; Compute domain wired; 724/724 → 771/771 PASS with E-39
- 2026-05-05: E-39 code-execution-mcp Tier 3 — fail-closed Docker sandbox; ARCH_PASS SEC_PASS SEC_CLEARED TESTS_PASS CRITIC_STAMP UACS_VERIFIED
- 2026-05-05: P-17/P-18/P-19 (Gemini) — architect.md §5 collapsed to delegate to mcp.md; blueprinted code-execution.md + mcp-router.md
- 2026-05-05: P-15 (Gemini) — structured-outputs.md §3 reframed as runtime MCP _assertSchema validation (API-level deferred to Phase 2)
- 2026-05-05: E-37 behavioral conversion — mcp_assert_tool_param_required helper added; 3 suites migrated; 688/688 PASS
- 2026-05-05: E-36 README/CONTRIBUTING — tmux split-pane workflow + post-collapse skill flow documented
- 2026-05-05: E-35 1:1 skill mapping — removed broken `ai *` refs across 5 templates, 6 toml descs, 3 agents, 6 SKILLs, both bootloaders
- 2026-05-04: E-34 src/bin/ai collapsed 2087→~1535 lines; 8 user verbs deprecated to skill pointers; 689/689 PASS

---
DIGEST must be accurate or flagged as stale. If stale, run: skill: ai-digest
