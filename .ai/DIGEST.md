# DIGEST — AI-OS v2 (Updated: 2026-04-03)

## Product
- CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.

## Stack
- Bash (zero-dependency CLI core), Node.js (MCP servers), SQLite (task-synchronizer-mcp WAL + token-budget-mcp), Playwright (vibe-check-mcp), file-based markdown memory.

## Triad Health
- Architect (Gemini): IDLE — all P-## tasks through P-12 DONE; no open P-## tasks
- Engineer (Claude): IDLE — last completed E-161 (context-guardian git grep result bounding); all E-## tasks closed; P-7 through P-12 completed
- Tester (TestSprite): Active — 334/336 tests pass; 2 pre-existing e140 failures (non-regression)

## Current Focus
- All tasks complete — full sprint E-146–E-161 + P-7–P-12 (robustness, SQLite, fuzzy patch, spawnSync, frontmatter) closed
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
- 2026-04-13: P-12 patch-mcp: statSync 5MB size guard added before readFileSync (src/mcp/patch-mcp/)
- 2026-04-13: P-11 orchestrator-mcp: run_handover scans .ai/blueprints/*.md as fallback (src/mcp/orchestrator-mcp/)
- 2026-04-13: P-10 orchestrator-mcp: readBoundedLines() helper replaces readFileSync+split+slice (src/mcp/orchestrator-mcp/)
- 2026-04-13: P-9 blueprint-aligner-mcp: generateDelta uses iterative regex instead of split("\n") (src/mcp/blueprint-aligner-mcp/)
- 2026-04-13: P-8 memory-manager-mcp: readHead() helper replaces full readFileSync in export_signature (src/mcp/memory-manager-mcp/)
- 2026-04-13: P-7 github-bridge-mcp: issue.body bounded to 5000 chars in get_issue (src/mcp/github-bridge-mcp/)
- 2026-04-03: E-161 context-guardian-mcp: git grep output bounded via .slice(0,100) (src/mcp/context-guardian-mcp/)
- 2026-04-03: E-160 Gemini sub-agents: YAML frontmatter (disable-model-invocation, user-invocable, allowed-tools) added to all 6 agents (src/gemini/agents/)
- 2026-04-03: E-159 spawnSync maxBuffer 10MB added across all MCP servers (src/mcp/)
- 2026-04-03: E-157 patch-mcp: fuzzy-patch fallback on MD5 mismatch — single-match apply + [PATCH_APPLIED_WITH_DRIFT] (src/mcp/patch-mcp/)
