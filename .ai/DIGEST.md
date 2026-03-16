# DIGEST (Token Saver Cache)
<!-- Generated: 2026-03-16 | Sprint: CLOSED -->

- Product: AI-OS CLI framework for structured, role-separated AI agent collaboration (The Triad: Gemini=Architect, Claude=Engineer, TestSprite=Tester).
- Stack: Bash CLI core (`src/bin/ai`), Node.js MCP servers (11 active), state.json source-of-truth, Markdown as read-only views.

## Key decisions:
- D-001: state.json is sole source of truth; TASKS.md and REVIEWS.md are generated read-only views (ENFORCED).
- D-002: execSync strictly forbidden in all MCP servers; use whitelisted spawnSync (ENFORCED E-89).
- D-003: §17.1.2 mandatory YAML frontmatter required for all agents/skills (ENFORCED E-91).
- D-004: pre-commit.sh blocks commit (exit 1) on missing generated header or task count drift >2 vs state.json (ENFORCED E-96).
- D-005: [CRITIC_STAMP] required within 7 days before any Tier 3 commit (ENFORCED).
- D-006: orchestrator-mcp is preferred over manual skill invocation for multi-step workflows (ACTIVE).

## Current focus (sprint CLOSED — no open tasks):
- All E-91 through E-97 tasks completed 2026-03-16.
- Next sprint tasks to be blueprinted by Gemini Architect.
- Run `run_preflight()` at next session start.

## Known risks (P0):
- Source-of-truth fragmentation: direct edits to TASKS.md or REVIEWS.md bypass state.json and will be blocked by pre-commit hook.
- spawnSync argument whitelists in MCP servers require ongoing audit as new tools are added.
- Bootloader blindness: orchestrator-mcp context dependency; if unavailable, fall back to activate_skill.

## Important constraints:
- TASKS.md is Read-Only (regenerated from state.json by task-synchronizer-mcp).
- Gemini (Architect) must NOT write source code in src/**.
- All Tier 3 commits require [UACS_VERIFIED] stamp in LOG.md.
- ai update --votu routes through node intent-refiner-mcp/index.js --stdin (python3 fallback).
- ai init auto-calls mcp-setup and migrate-state --force (Structured-First onboarding).
- ai doctor --repair triggers npm install + .mcp.json realignment for broken servers.

## MCP servers active (from .mcp.json):
- filesystem: project-root-scoped filesystem access (path: `.`).
- memory: knowledge-graph memory store at default scope.
- TestSprite: AI test generation (env: TESTSPRITE_API_KEY).
- Custom servers (all at ~/.ai-os/mcp/): vibe-check-mcp, intent-refiner-mcp, task-synchronizer-mcp, safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp, risk-analyzer-mcp, context-invoker-mcp, archive-manager-mcp, orchestrator-mcp.

## Recent changes (last 10):
- 2026-03-16: Sprint archived — LOG/REVIEWS/SESSION moved to .ai/archive/2026-03/ (.ai/LOG.md).
- 2026-03-16: intent-refiner-mcp --stdin mode; ai update --votu wired to MCP node CLI (src/mcp/intent-refiner-mcp, src/bin/ai) [E-97].
- 2026-03-16: pre-commit check_markdown_sync() upgraded to BLOCK (exit 1) on header missing or task count drift >2 (hooks/pre-commit.sh) [E-96].
- 2026-03-16: verify_markdown_sync tool added to task-synchronizer-mcp (src/mcp/task-synchronizer-mcp) [E-95].
- 2026-03-16: ai doctor --repair flag added; triggers npm install + .mcp.json realignment (src/bin/ai) [E-94].
- 2026-03-16: ai init auto-calls migrate-state --force after mcp-setup (src/bin/ai) [E-93].
- 2026-03-16: ai update --votu implemented via intent-refiner-mcp (src/bin/ai) [E-92].
- 2026-03-16: Bulk YAML frontmatter update across 19 agent files for §17.1.2 compliance (src/claude/agents/, src/gemini/agents/) [E-91].
- 2026-03-16: state.json seeded with 121 tasks via ai migrate-state --force (.ai/state.json) [P-43].
- 2026-03-16: TIER3_NO_SECURITY_REVIEW gate reads exclusively from state.json stamps[] (src/mcp/blueprint-aligner-mcp) [P-44].
