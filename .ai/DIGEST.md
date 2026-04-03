# DIGEST — AI-OS v2 (Updated: 2026-04-03)

## Product
- CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.

## Stack
- Bash (zero-dependency CLI core), Node.js (MCP servers), SQLite (task-synchronizer-mcp WAL + token-budget-mcp), Playwright (vibe-check-mcp), file-based markdown memory.

## Triad Health
- Architect (Gemini): IDLE — P-1 (SQLite migration) + P-2 (fuzzy patch) DONE 2026-04-03; no open P-## tasks
- Engineer (Claude): IDLE — last completed E-157 (fuzzy-patching fallback in patch-mcp, 2026-04-03); no open E-## tasks
- Tester (TestSprite): Active — 334/336 tests pass; 2 pre-existing e140 failures (non-regression)

## Current Focus
- All tasks complete — sprint E-144–E-157 (token economics, SQLite migration, fuzzy patch) fully closed
- No open E-## or P-## tasks; system in idle/ready state
- Next sprint pending Gemini Architect direction

## Key Decisions
- D-007: REVIEWS.md writes must use `mcp__task-synchronizer-mcp__add_stamp` (not direct appends)
- D-009: verification-mcp path traversal (M-001) patched via allowlist
- §21: Strict project-scoping — install/sync targets only project `.claude`/`.gemini`, never global dirs
- §35: ANTI-DRIFT PROTOCOL — Claude is Engineer only; architecture decisions deferred to Gemini
- §39: Architectural Fragmentation — architect.md is a 35-line index; domain blueprints loaded JIT from `.ai/blueprints/`
- E-147: UPDATE.md deprecated globally — never create or read it; all references purged
- E-156: task-synchronizer-mcp migrated to SQLite (WAL mode); state.json + TASKS.md + REVIEWS.md remain as backwards-compat views

## Known Risks
- P1: [ARCH_AUDIT] 2026-03-23 — Architectural Intelligence dirs missing; 2 MCPs (orchestrator, risk-analyzer) not in registry.json
- M-002 (MEDIUM/accepted): ai-exec orphan worktree race condition in concurrent runs
- P1 (open): token-budget-mcp usage.sqlite write path missing from CAPABILITIES.md filesystem.write

## MCP Servers
- filesystem, memory, TestSprite, vibe-check-mcp, task-synchronizer-mcp
- safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp
- risk-analyzer-mcp, context-invoker-mcp, archive-manager-mcp
- orchestrator-mcp, memory-manager-mcp, verification-mcp
- lsp-mcp, patch-mcp, token-budget-mcp, propose-patch-mcp, github-bridge-mcp

## Recent Changes (last 10)
- 2026-04-03: E-157 patch-mcp: fuzzy-patch fallback on MD5 mismatch — single-match apply + [PATCH_APPLIED_WITH_DRIFT] (src/mcp/patch-mcp/)
- 2026-04-03: E-156 task-synchronizer-mcp: SQLite WAL migration; auto-import state.json; mtime sync guard (src/mcp/task-synchronizer-mcp/)
- 2026-04-03: E-155 context-guardian-mcp strict: git grep via spawnSync replaces scanDir+readFileSync (src/mcp/context-guardian-mcp/)
- 2026-04-03: E-154 context-invoker-mcp: readHead() 4KB bounded; frontmatter parsed without full file load (src/mcp/context-invoker-mcp/)
- 2026-04-03: E-153 archive-manager-mcp: readline streams replace readFileSync+split for line/word counts (src/mcp/archive-manager-mcp/)
- 2026-04-03: E-152 Metadata-Only Sync — list_skills/list_agents added to context-invoker-mcp (src/bin/ai)
- 2026-04-03: E-151 Architectural Fragmentation — 5 domain blueprints in .ai/blueprints/ (.ai/)
- 2026-04-03: E-150 Added AIS Fresh Conversations rule + 6-file JIT limit (src/templates/RULES.md)
- 2026-04-03: E-149 UPDATE.md purged from orchestrator-mcp, task-synchronizer-mcp, github-bridge-mcp (src/mcp/)
- 2026-04-03: E-148 do_update() refactored — inline intent, JIT DIGEST refresh, no UPDATE.md (src/bin/ai)
