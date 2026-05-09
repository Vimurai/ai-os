# DIGEST — AI-OS v2 (Updated: 2026-05-07)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, Structured Outputs, sandboxed code execution, dynamic MCP routing, multimodal memory palace, Obsidian-graph documentation, and a collapsed bootloader CLI.

## Stack
- Node.js 22+ (MCP servers, node:sqlite built-in), Python 3.10+ (fallbacks), SQLite3 (state), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces (monorepo), Gemini 3.1 Pro (Architect, mandated 2026-05-07), Gemini Embedding 2 (memory palace), Claude Opus 4.7 (Engineer).

## Triad Health
- Architect (Gemini): IDLE — last task P-30 (Obsidian Knowledge Graph blueprint, 2026-05-07). All 30 P-## tasks DONE.
- Engineer (Claude): IDLE — all 51 E-## tasks DONE; latest E-51 (Obsidian Vault Memory — wikilinks + frontmatter on blueprint-writer / decision-recorder / ai-log).
- Tester (TestSprite): PASS — 1095/1095 baseline post-E-51 (was 1065 post-E-49, +30 from obsidian_vault_memory_test.sh); behavioral mcp_behavioral_test.sh stable; verify_compliance clean.

## Current Focus
- (none) — May 2026 Claude Code & Obsidian Optimizations sprint (P-27..P-30 → E-48/E-49/E-50/E-51) shipped 2026-05-07; awaiting next P-## from Architect.
- state.json focus still reads "Claude Code & Obsidian Memory Optimizations" — will clear on next handover.

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
- D-011: blueprint-aligner Context Engine — line-by-line CAPABILITIES_BYPASS scan with ESM/CJS module-specifier whitelist; UACS handoff stamp gate downgrades GEMINI_FILE_MODIFIED FAIL→WARN when state.json/LOG.md carry an authorship marker within 24h (E-42)
- D-012: ai-debug skill TASK_BUDGET = 3 distinct hypotheses; mandatory advisor-mcp.ask_architect escalation on BUDGET_EXHAUSTED; AI_DEBUG_BUDGET env override (E-43)
- D-013: security_engineer agent runs Active Pen-Testing inside code-execution-mcp sandbox (D-008 fail-closed, OWASP Top 10 payload table, RESISTED/EXPLOITED/INCONCLUSIVE verdict schema; sequential per endpoint; no DoS/bare-metal) (E-44)
- D-014: Gemini default_model pinned to gemini-3.1-pro + interactions_api_schema=steps in registry.json; bin/ai propagates to .gemini/settings.json on init/sync; GEMINI_MODEL env override; user-set value preserved (E-45)
- D-015: Memory Palace multimodal — memory_curator embeds PNG/SVG/PDF (≤5MB) via Gemini Embedding 2 with department metadata; 4-layer sensitive-file gate; background-only execution; knowledge_architect retrieves with metadata filter and returns page-level citations (E-46)
- D-016: managed-agents-2026-04-01 spike PROCEED — local state.json projects cleanly to managed-fs (77 entries, 0 redactions, 4/4 lifecycle handlers); follow-up E-## to wire real client behind feature flag once API key provisioned (E-47)
- D-017: MCP Stdout Purity Gate — pre-commit linter bans `console.log` / `console.info` in `src/mcp/**` (Python state machine skips line + block comments); console.error/.warn permitted; aligns with shared/logger.js NDJSON-to-stderr (E-48)
- D-018: Session Traceability — approval-mcp SQLite carries `session_id TEXT CHECK(<=64)` with idempotent migration; ai-log appends `session=<id>` from $CLAUDE_CODE_SESSION_ID (regex-validated, untrusted-input contract); legacy NULL rows preserved (E-49)
- D-019: Terminal Optimisation — CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 written to .claude/settings.json on `ai sync` (setdefault, preserves user override) and exported by install-ai-os.sh into ~/.zprofile/.zshrc/.bashrc via idempotent ensure_env_line helper (E-50)
- D-020: Obsidian Vault Memory — blueprint-writer / decision-recorder / ai-log skills mandate YAML frontmatter (type/tier/tags/status) and [[wikilinks]] for all D-###/E-##/P-## cross-refs; bare markdown links forbidden (E-51)

## Known Risks
- Persistent ALIGN_FAIL false-positive class (markdown prose "../" in TASKS.md, JSON keys flagged as deps, ORPHANED_WORK on .claude/.gemini sync mirrors). E-42 retired the ESM-import + UACS-stamp slice; markdown/JSON-prose introspection still pending future hardening pass.
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported.
- code-execution-mcp depends on Docker daemon — fail-closed when unavailable; no bare-metal fallback by design (D-008).
- structured-outputs.md is Phase 1 (runtime MCP _assertSchema only); full API-level enforcement deferred to Phase 2 if/when bin/ai gains LLM integration.
- Local .git/hooks drift mostly mitigated by E-41 stub model + auto-upgrade on `ai sync`; verify on next sprint.
- Active pen-testing surface (E-44) currently scoped to in-process parsers/endpoints; outbound-network probes deferred to THREAT_MODEL.md follow-up.
- Managed-agents integration (E-47) is offline spike only — no live API call yet; production wiring needs feature flag + key provisioning + retry on the new "steps" schema.
- Memory-palace embeddings cap (LRU 500) and serial-request 429 backoff are conservative; revisit quotas if multi-project rollout begins.
- E-50 alternate-screen pin may cause rendering glitches on specific terminal emulators; rollback path documented (comment out env line).

## MCP Servers (25 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp (BLOCK_RULES extended E-23), context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp (Context Engine E-42), github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp (sandbox env enforced E-38)
- Interop: advisor-mcp (A2A bridge to Gemini, env allowlisted E-17), approval-mcp (HITL Tier 3, session-id audit E-49)
- Caching: cache-manager-mcp (Explicit Context Cache, finally-close fix E-25)
- Compute: code-execution-mcp (Docker sandbox, fail-closed E-39)
- Routing: mcp-router (progressive discovery + RBAC mirror E-40)

## Recent Changes (last 10)
- 2026-05-07: E-51 Obsidian Vault Memory — blueprint-writer / decision-recorder / ai-log skills enforce YAML frontmatter + [[wikilinks]] (D-###/E-##/P-##/blueprint refs); 7 SKILL.md mirrors byte-identical; +30 assertions; 1095/1095 PASS
- 2026-05-07: E-49 Session Traceability — approval-mcp SQLite gains session_id col (idempotent migration); captureSessionId() sanitiser; ai-log session=<id> contract; +26 assertions; 1065/1065 PASS
- 2026-05-07: E-48 MCP Stdout Purity Gate — pre-commit lint bans console.log/info in src/mcp/** (Python state-machine skips comments); +16 assertions; 1039/1039 PASS
- 2026-05-07: E-50 Terminal Optimisation — CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 via setdefault in bin/ai + ensure_env_line in install-ai-os.sh (zprofile/zshrc/bashrc); +14 assertions
- 2026-05-07: P-27/P-28/P-29/P-30 (Gemini) — claude-obsidian-optimizations.md blueprint (Stdout Purity, Session Audit, Alt-Screen, Obsidian Graph)
- 2026-05-07: E-47 managed-agents architectural spike — offline projection of state.json into managed-fs (77 entries, 0 redactions, 4/4 webhook lifecycle handlers); 4-layer sanitiser; verdict PROCEED; +25 assertions; 1009/1009 PASS; Tier 3 RELEASE READY
- 2026-05-07: E-46 Multimodal Memory Palace — memory_curator embeds PNG/SVG/PDF via Gemini Embedding 2 with department metadata; knowledge_architect retrieves with filter + page-level citations; +58 assertions; 984/984 PASS
- 2026-05-07: E-45 Gemini 3.1 Pro pin — registry.json gemini block (default_model + interactions_api_schema=steps), bin/ai propagator, GEMINI.md Model Mandate, .gemini/settings.json regenerated; +19 assertions; 926/926 PASS
- 2026-05-07: P-24/P-25/P-26 (Gemini) — may-2026-upgrades.md blueprint (Model Migration, Multimodal RAG, Managed Agents Spike)
- 2026-05-06: E-44 security_engineer Active Pen-Testing — OWASP Top 10 payload table, RESISTED/EXPLOITED/INCONCLUSIVE verdict schema, sandbox-only fail-closed; +59 assertions; Tier 3 RELEASE READY 907/907 PASS

---
DIGEST must be accurate or flagged as stale. If stale, run: skill: ai-digest
- 2026-05-08: auto-stamped by Stop hook
