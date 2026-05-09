# DIGEST — AI-OS v2 (Updated: 2026-05-09)

## Product
- Autonomous operating system for AI agents (Claude Code + Gemini CLI) with ACID-compliant SQLite state, strict RBAC, JIT context loading, Explicit Context Caching, Structured Outputs, sandboxed code execution, dynamic MCP routing, multimodal memory palace, auto-generated MCP registry docs, and a collapsed bootloader CLI.

## Stack
- Node.js 22+ (MCP servers, node:sqlite built-in), Python 3.10+ (fallbacks), SQLite3 + WAL (state, periodic TRUNCATE checkpoint), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces (monorepo), Gemini 3.1 Pro (Architect, mandated 2026-05-07), Gemini Embedding 2 (memory palace), Claude Opus 4.7 (Engineer).

## Triad Health
- Architect (Gemini): IDLE — last batch P-31..P-34 (drift-resolution-2026.md, MCP doc sync + WAL strategy + Obsidian _INDEX + Interop reconciliation, 2026-05-08). All 34 P-## tasks DONE.
- Engineer (Claude): IDLE — all 54 E-## tasks DONE; latest E-52 (MCP Registry Auto-Generation: scripts/generate_mcp_docs.mjs wired into `ai sync`).
- Tester (TestSprite): PASS — 1097/1097 baseline post-E-52 (was 1080 post-E-53 / 1069 post-E-54); behavioral mcp_behavioral_test.sh stable; verify_compliance clean.

## Current Focus
- (none) — Drift-Resolution sprint (P-31..P-34 → E-52/E-53/E-54) shipped 2026-05-08; awaiting next P-## from Architect.
- state.json focus likely still reads prior sprint label — will clear on next handover.

## Key Decisions
- D-001: npm workspaces at root; @modelcontextprotocol/sdk pinned exactly to 1.27.1, children "*" (E-20)
- D-002: computer-use-mcp sandboxed — DISPLAY=:99, HOME=/tmp/computer-use-sandbox; env carried in registry.json + propagated by `ai sync` + asserted by registry_sync_test.sh (E-38)
- D-003: approval-mcp HITL gate — SQLite audit trail, hardcoded DB_PATH, TTY assertion, maxLength guards
- D-004: cache-manager-mcp assembles architect.md + blueprints/*.md + state.sqlite schema; mtime invalidation
- D-005: structured logging unified — src/mcp/shared/logger.js (NDJSON to stderr) across all MCP servers (E-18)
- D-006: `ai` CLI collapsed to bootloader-only (install/init/sync/doctor/uninstall/version); operational verbs migrated to skills; tmux split-pane workflow (E-34/E-35/E-36)
- D-007: Test gate is behavioral-first — tool registration via mcp_assert_tool_listed / mcp_assert_tool_param_required over stdio JSON-RPC; source-grep retained only for security anti-pattern checks (E-37)
- D-008: code-execution-mcp sandbox — fail-closed Docker boundary (network=none, read-only, cap-drop=ALL, --user=65534, tmpfs noexec/nosuid, pids-limit=64, mem 512m, no docker.sock leak); no bare-metal fallback (E-39)
- D-009: mcp-router progressive tool discovery + JSON-RPC stdio proxy with active-domain gate + registry allowed-tools mirror (RBAC defense-in-depth) (E-40)
- D-010: git hooks installed as 12-13 line execution stubs (call-by-reference to ~/.ai-os/hooks/); fail-closed pre-commit, fail-open post-commit; `ai sync` auto-upgrades legacy copy-mode hooks (E-41)
- D-011: blueprint-aligner Context Engine — line-by-line CAPABILITIES_BYPASS scan with ESM/CJS module-specifier whitelist; UACS handoff stamp gate downgrades GEMINI_FILE_MODIFIED FAIL→WARN when state.json/LOG.md carry an authorship marker within 24h (E-42)
- D-012: ai-debug skill TASK_BUDGET = 3 distinct hypotheses; mandatory advisor-mcp.ask_architect escalation on BUDGET_EXHAUSTED; AI_DEBUG_BUDGET env override (E-43)
- D-013: security_engineer agent runs Active Pen-Testing inside code-execution-mcp sandbox (D-008 fail-closed, OWASP Top 10 payload table, RESISTED/EXPLOITED/INCONCLUSIVE verdict schema; sequential per endpoint; no DoS/bare-metal) (E-44)
- D-014: Gemini default_model pinned to gemini-3.1-pro + interactions_api_schema=steps in registry.json; bin/ai propagates to .gemini/settings.json on init/sync; GEMINI_MODEL env override (E-45)
- D-015: Memory Palace multimodal — memory_curator embeds PNG/SVG/PDF (≤5MB) via Gemini Embedding 2 with department metadata; 4-layer sensitive-file gate; background-only execution; knowledge_architect retrieves with metadata filter and returns page-level citations (E-46)
- D-016: managed-agents-2026-04-01 spike PROCEED — local state.json projects cleanly to managed-fs (77 entries, 0 redactions, 4/4 lifecycle handlers); follow-up E-## to wire real client behind feature flag once API key provisioned (E-47)
- D-017: MCP Stdout Purity Gate — pre-commit linter bans `console.log` / `console.info` in `src/mcp/**` (Python state machine skips line + block comments); console.error/.warn permitted; aligns with shared/logger.js NDJSON-to-stderr (E-48)
- D-018: Session Traceability — approval-mcp SQLite carries `session_id TEXT CHECK(<=64)` with idempotent migration; ai-log appends `session=<id>` from $CLAUDE_CODE_SESSION_ID (regex-validated, untrusted-input contract); legacy NULL rows preserved (E-49)
- D-019: Terminal Optimisation — CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 written to .claude/settings.json on `ai sync` (setdefault, preserves user override) and exported by install-ai-os.sh into ~/.zprofile/.zshrc/.bashrc via idempotent ensure_env_line helper (E-50)
- D-020 (RETIRED via D-023): Obsidian Vault Memory mandate — frontmatter + [[wikilinks]] in blueprint-writer/decision-recorder/ai-log (E-51) reverted by E-54 on 2026-05-08 per architect ruling D-023; ai-log retains the E-49 session= contract surgically.
- D-021: MCP Registry Single-Source-of-Truth — `.ai/blueprints/mcp.md` is auto-generated from `src/config/registry.json` + `src/mcp/shared/mcp-domains.mjs` by `scripts/generate_mcp_docs.mjs`; wired into `bin/ai do_sync()` (locator chain, fail-open) and shipped via install-ai-os.sh; mcp_doc_sync_test.sh enforces byte-identical CI gate; mcp-router imports DOMAINS from the same shared module (E-52)
- D-022: SQLite WAL Flush — `_wal_checkpoint_state_db()` runs `PRAGMA wal_checkpoint(TRUNCATE)` against `.ai/state.sqlite` from both `do_sync()` and `doctor()` in `bin/ai`; hardcoded path, command -v sqlite3 fail-open, BASH_SOURCE dispatch guard for sourceability (E-53)
- D-023: Obsidian Vault formatting retired — Architect ruling 2026-05-08 ditches frontmatter + wikilinks mandate in skills (D-020 reversal); standard markdown restored across 7 SKILL.md mirrors via E-54

## Known Risks
- Persistent ALIGN_FAIL false-positive class (markdown prose "../" in TASKS.md, JSON keys flagged as deps, ORPHANED_WORK on .claude/.gemini sync mirrors). E-42 retired the ESM-import + UACS-stamp slice; markdown/JSON-prose introspection still pending.
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported.
- code-execution-mcp depends on Docker daemon — fail-closed when unavailable; no bare-metal fallback by design (D-008).
- structured-outputs.md is Phase 1 (runtime MCP _assertSchema only); full API-level enforcement deferred to Phase 2 if/when bin/ai gains LLM integration.
- Active pen-testing surface (E-44) currently scoped to in-process parsers/endpoints; outbound-network probes deferred to THREAT_MODEL.md follow-up.
- Managed-agents integration (E-47) is offline spike only — no live API call yet; production wiring needs feature flag + key provisioning + retry on the new "steps" schema.
- Memory-palace embeddings cap (LRU 500) and serial-request 429 backoff are conservative; revisit quotas if multi-project rollout begins.
- E-50 alternate-screen pin may cause rendering glitches on specific terminal emulators; rollback path documented (comment out env line).
- Auto-generated mcp.md (E-52) drifts if a contributor edits it manually instead of registry.json — CI byte-identical gate catches at commit time, but pre-commit is fail-open if node missing.
- WAL checkpoint (E-53) is fail-open when sqlite3 CLI absent; bloat can recur silently on dev boxes without sqlite3 installed.

## MCP Servers (25 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp (Context Engine E-42), github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp (sandbox env enforced E-38)
- Interop: advisor-mcp (A2A bridge to Gemini), approval-mcp (HITL Tier 3, session-id audit E-49)
- Caching: cache-manager-mcp (Explicit Context Cache, finally-close fix E-25)
- Compute: code-execution-mcp (Docker sandbox, fail-closed E-39)
- Routing: mcp-router (progressive discovery + RBAC mirror E-40; DOMAINS imported from shared module E-52)

## Recent Changes (last 10)
- 2026-05-08: E-52 MCP Registry Auto-Generation — scripts/generate_mcp_docs.mjs reads registry.json + mcp-domains.mjs, emits domain-grouped .ai/blueprints/mcp.md; wired into bin/ai do_sync() with fail-open guards; install-ai-os ships scripts/; +17 assertions; 1097/1097 PASS
- 2026-05-08: E-53 SQLite WAL Flush Hook — _wal_checkpoint_state_db() runs PRAGMA wal_checkpoint(TRUNCATE) from do_sync()+doctor() in bin/ai; hardcoded path, fail-open, BASH_SOURCE dispatch guard; +11 assertions; 1080/1080 PASS
- 2026-05-08: E-54 Revert Obsidian Vault Memory — restored 7 SKILL.md mirrors to pre-E-51 markdown, preserved E-49 session=<id> contract in ai-log, deleted obsidian_vault_memory_test.sh; 1069/1069 PASS
- 2026-05-08: D-023 (Gemini ruling) — ditched Obsidian Vault integration; revert to standard markdown
- 2026-05-08: P-31/P-32/P-33/P-34 (Gemini) — drift-resolution-2026.md (MCP Registry Sync, Interop reconciliation, blueprints/_INDEX.md hub, WAL strategy ruling)
- 2026-05-07: Archive sweep — LOG/REVIEWS/SESSION/COMM rotated to .ai/archive/2026-05/ (post-E-51 cleanup; second sweep on 2026-05-09)
- 2026-05-07: E-51 Obsidian Vault Memory — frontmatter + [[wikilinks]] mandate (LATER REVERTED by E-54)
- 2026-05-07: E-49 Session Traceability — approval-mcp session_id col + ai-log session=<id> contract; +26 assertions; 1065/1065 PASS
- 2026-05-07: E-48 MCP Stdout Purity Gate — pre-commit lint bans console.log/info in src/mcp/**; +16 assertions; 1039/1039 PASS
- 2026-05-07: E-50 Terminal Optimisation — CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 via setdefault + ensure_env_line; +14 assertions

---
DIGEST must be accurate or flagged as stale. If stale, run: skill: ai-digest
