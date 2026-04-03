# DIGEST — AI-OS v2 (Updated: 2026-04-03)

## Product
- CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.

## Stack
- Bash (zero-dependency CLI core), Node.js (MCP servers), Playwright (vibe-check-mcp), SQLite (token-budget-mcp), file-based markdown memory.

## Triad Health
- Architect (Gemini): Active — P-60–P-63 all DONE 2026-04-03; no open P-## tasks
- Engineer (Claude): Active — last completed E-155 (context-guardian-mcp git grep refactor, 2026-04-03); no open E-## tasks
- Tester (TestSprite): Active — T-1 DONE 2026-03-31 (idempotency_test.sh, 16/16 passing)

## Current Focus (top 3 open tasks)
- No open E-## Engineer tasks — sprint E-143 through E-155 complete
- Awaiting next Architect blueprint for new Engineer tasks

## Key Decisions
- D-007: REVIEWS.md writes must use `mcp__task-synchronizer-mcp__add_stamp` (not direct appends)
- D-009: verification-mcp path traversal (M-001) patched via allowlist
- D-011: M-002 ai-exec orphan race accepted as LOW (MEDIUM severity, mitigated by trap/prune)
- §21: Strict project-scoping — install/sync only targets project `.claude`/`.gemini`, never global dirs
- §35: ANTI-DRIFT PROTOCOL — Claude is Engineer only; architecture decisions deferred to Gemini
- E-147: UPDATE.md deprecated globally — never created, all references removed from CLI/agents/skills/MCPs

## Known Risks
- P0 (pending ratification): [ARCH_FAIL] 2026-03-23 — Co-Authored-By trailer in d351dc9 violated §12 Git Identity mandate; Gemini ratification required before next release
- P1: [ARCH_AUDIT] 2026-03-23 — Architectural Intelligence dirs missing; 2 orphaned MCPs (orchestrator, risk-analyzer) not in registry
- P1: Source of Truth fragmentation (JSON state.json vs MD TASKS.md) — ongoing
- M-002 (MEDIUM/accepted): ai-exec orphan worktree race condition in concurrent runs

## Important Constraints
- Token Economics: 6-file JIT read limit enforced mechanically in do_update(), do_onboard(), do_digest()
- Forbidden: `ls -R`, unconstrained `cat` loops, full 8-file unconditional reads in agents
- RBAC: roleGuard() blocks Architect from writing to `src/`; [ANTI_DRIFT_VIOLATION] thrown by patch-mcp + propose-patch-mcp
- UPDATE.md: fully deprecated — must never be created or read by any component

## MCP Servers Active
- filesystem (scope: project dir), memory (in-process KV store)
- vibe-check-mcp, intent-refiner-mcp (deprecated no-op), task-synchronizer-mcp (sync_tasks deprecated)
- safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp (check_role_access added E-143)
- risk-analyzer-mcp, context-invoker-mcp, archive-manager-mcp, orchestrator-mcp (run_intent_cleanup deprecated)
- memory-manager-mcp, verification-mcp, TestSprite
- lsp-mcp (E-136 — TypeScript symbol/type awareness), patch-mcp (E-137 — MD5 optimistic-lock writes)
- propose-patch-mcp (E-141 — interactive TUI diff), token-budget-mcp (E-140 — SQLite usage tracking)
- github-bridge-mcp (E-142 — gh CLI integration; create_update_from_issues renamed to create_intent_from_issues)

## Recent Changes (last 10)
- 2026-04-03: E-155 context-guardian-mcp strict mode: scanDir+readFileSync replaced with git grep via spawnSync; readdirSync/statSync removed; fixed missing relative import (src/mcp/context-guardian-mcp/)
- 2026-04-03: E-154 context-invoker-mcp: added readHead() (4KB bounded read via openSync/readSync); listAvailable() uses readHead instead of full readFileSync for frontmatter parsing (src/mcp/context-invoker-mcp/)
- 2026-04-03: E-153 archive-manager-mcp: readFileSync+split replaced with readline streams via countFileStats(); no full file load for line/word counting (src/mcp/archive-manager-mcp/)
- 2026-04-03: E-152 Metadata-Only Default Mode — list_skills/list_agents tools added to context-invoker-mcp; _generate_skills_index() writes _SKILLS_INDEX.md to synced skill dirs (src/mcp/context-invoker-mcp/, src/bin/ai)
- 2026-04-03: E-151 Architectural Fragmentation — architect.md reduced to 35-line index; 5 domain blueprints in .ai/blueprints/ (core, security, agents, mcp, governance) (.ai/)
- 2026-04-03: E-150 AIS Fresh Conversations rule added to RULES.md + architect.md.template; §33 Token Economics + §34 Domain Blueprints added to template (src/templates/)
- 2026-04-03: E-149 UPDATE.md removed from orchestrator-mcp, task-synchronizer-mcp, github-bridge-mcp; run_intent_cleanup + sync_tasks deprecated as no-ops (src/mcp/)
- 2026-04-03: E-148 do_update() refactored — inline intent from CLI args, JIT DIGEST refresh via digest_updater, no UPDATE.md (src/bin/ai)
- 2026-04-03: E-147 UPDATE.md deprecated globally — removed from scaffolding, all agent preflights, ai-preflight/ai-review/bug-reproducer skills, GEMINI.md; ai-update-lifecycle marked DEPRECATED (src/bin/ai, src/claude/skills/, src/templates/)
- 2026-04-02: E-146 Preflight standardized across devops_engineer, security_engineer, decision_recorder, claude_tasks — DIGEST-first, no UPDATE.md (.gemini/agents/, src/gemini/agents/)
- 2026-04-02: E-145 6-file Token Economics cap enforced in do_update/do_onboard/do_digest prompts; ls -R and cat loops forbidden (src/bin/ai)
- 2026-04-02: E-144 digest_updater refactored to JIT — git-based change detection, grep-first targeted reads (.gemini/agents/digest_updater.md, src/gemini/agents/digest_updater.md)
- 2026-04-02: E-143 Role-Aware RBAC interceptors — roleGuard() in patch-mcp + propose-patch-mcp; check_role_access in context-guardian-mcp; 25/25 tests pass (src/mcp/)
