# DIGEST — AI-OS v2 (Updated: 2026-03-31)

## Product
- CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.

## Stack
- Bash (zero-dependency CLI core), Node.js (MCP servers), Playwright (vibe-check-mcp), SQLite (planned token-budget-mcp), file-based markdown memory.

## Triad Health
- Architect (Gemini): Active — last audit 2026-03-23; P-54–P-59 open (lsp-mcp, patch_file, ai-compact, token-budget-mcp, github-bridge-mcp, JIT skill loading)
- Engineer (Claude): Active — last completed E-139 (ai-compact skill, 2026-03-31); E-140–E-142 open
- Tester (TestSprite): Active — T-1 DONE 2026-03-31 (idempotency_test.sh, 16/16 passing)

## Current Focus
- E-140: Implement `token-budget-mcp` with SQLite persistence [OPEN]
- E-141: Implement `propose_patch` tool with interactive TUI diff previews [OPEN]
- E-142: Implement `github-bridge-mcp` using GitHub CLI (gh) integration [OPEN]

## Key Decisions
- D-007: REVIEWS.md writes must use `mcp__task-synchronizer-mcp__add_stamp` (not direct appends)
- D-009: verification-mcp path traversal (M-001) patched via allowlist
- D-011: M-002 ai-exec orphan race accepted as LOW (MEDIUM severity, mitigated by trap/prune)
- §21: Strict project-scoping — install/sync only targets project `.claude`/`.gemini`, never global dirs
- §35: ANTI-DRIFT PROTOCOL — Claude is Engineer only; architecture decisions deferred to Gemini

## Known Risks
- P0 (pending ratification): [ARCH_FAIL] 2026-03-23 — Co-Authored-By trailer in d351dc9 violated §12 Git Identity mandate; Gemini ratification required before next release
- P1: [ARCH_AUDIT] 2026-03-23 — Architectural Intelligence dirs missing; 2 orphaned MCPs (orchestrator, risk-analyzer) not in registry
- P1: Source of Truth fragmentation (JSON state.json vs MD TASKS.md) — ongoing
- M-002 (MEDIUM/accepted): ai-exec orphan worktree race condition in concurrent runs

## MCP Servers
- filesystem, memory, TestSprite, vibe-check-mcp, intent-refiner-mcp, task-synchronizer-mcp
- safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp, risk-analyzer-mcp, context-invoker-mcp
- archive-manager-mcp, orchestrator-mcp, memory-manager-mcp, verification-mcp
- lsp-mcp (NEW — §23 TypeScript symbol/type awareness via TypeScript compiler API)
- patch-mcp (NEW — §25 MD5-verified atomic file writes, prevents race-condition overwrites)

## Recent Changes (last 10)
- 2026-03-31: T-1 idempotency_test.sh — 16/16 passing (tests/suites/idempotency_test.sh)
- 2026-03-31: E-139 ai-compact skill — distills SESSION.md to Active Context, user-invocable /compact (src/claude/skills/ai-compact/)
- 2026-03-31: E-138 Reactive Memory hook — run_handover sets digest_stale in state.json; preflight surfaces warning (hooks/stop-hook.sh)
- 2026-03-31: E-137 patch-mcp — patch_file + get_file_md5 with MD5 optimistic-lock (src/mcp/patch-mcp/index.js)
- 2026-03-31: E-136 lsp-mcp — get_definitions, get_references, get_diagnostics (src/mcp/lsp-mcp/index.js)
- 2026-03-24: Bootloader auto-overwrite — CLAUDE.md/GEMINI.md/.mcp.json always overwritten on ai init/sync (src/bin/ai)
- 2026-03-23: E-135 docs-architect Gemini agent (src/gemini/agents/docs-architect.md)
- 2026-03-23: E-134 release-manager shared skill (src/shared/skills/release-manager/SKILL.md)
- 2026-03-23: E-132 aqg-resolver agent — autonomous [LOCKED - AQG FAILED] fixer (src/claude/agents/aqg-resolver.md)
- 2026-03-23: E-130 AQG PostToolUse hook — intercepts Write/Edit on src/**, exits 1 on test failure (hooks/post-tool-use.sh)
- 2026-04-01: auto-stamped by Stop hook
