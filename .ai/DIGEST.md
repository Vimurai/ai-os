# DIGEST (Token Saver Cache)
<!-- Generated: 2026-03-16 | Sprint E-110–E-117: CLOSED -->

- Product: AI-OS CLI framework for structured, role-separated AI agent collaboration (The Triad: Gemini=Architect, Claude=Engineer, TestSprite=Tester).
- Stack: Bash CLI core (`src/bin/ai`), Node.js MCP servers (13 active), state.json source-of-truth, Markdown as read-only views. Tests: 224/224 across 13 suites.

## Key decisions:
- D-001: state.json is sole source of truth; TASKS.md and REVIEWS.md are generated read-only views (ENFORCED — Check 4 added E-113).
- D-002: execSync strictly forbidden in all MCP servers; use whitelisted spawnSync (ENFORCED E-89).
- D-003: §17.1.2 mandatory YAML frontmatter required for all agents/skills (ENFORCED E-91).
- D-004: pre-commit.sh blocks commit (exit 1) on missing generated header or task count drift >2 vs state.json (ENFORCED E-96).
- D-005: [CRITIC_STAMP] required within 7 days before any Tier 3 commit (ENFORCED).
- D-006: orchestrator-mcp is preferred over manual skill invocation for multi-step workflows (ACTIVE).
- D-007: REVIEWS.md narrative text must be encoded as one-line stamps in state.json — multi-line summaries are forbidden (Check 4 enforces this, E-113).
- D-008: readStateStrict must include a version guard — version mismatches (version != "1.0") treated as corrupt state and return null (ENFORCED E-117).

## Current focus (sprint CLOSED — no open tasks):
- All E-110 through E-117 tasks completed 2026-03-16.
- Total test count: 224/224 passing across 13 suites.
- Next sprint tasks to be blueprinted by Gemini Architect.
- Run `run_preflight()` at next session start.

## Known risks (P0):
- None active. Previous "Source of Truth Fragmentation" risk mitigated by Check 4 in pre-commit.sh (E-113).
- spawnSync argument whitelists in MCP servers require ongoing audit as new tools are added.
- Bootloader blindness: orchestrator-mcp context dependency; if unavailable, fall back to activate_skill (§30 resilience layers in CLAUDE.md).

## Important constraints:
- TASKS.md and REVIEWS.md are Read-Only (regenerated from state.json by task-synchronizer-mcp).
- REVIEWS.md stamps must be one-line only — no multi-line prose; Check 4 blocks ## headings in REVIEWS.md at commit.
- Gemini (Architect) must NOT write source code in src/**.
- All Tier 3 commits require [UACS_VERIFIED] stamp in LOG.md.
- ai update --votu routes through node intent-refiner-mcp/index.js --stdin (python3 fallback).
- ai init auto-calls mcp-setup and migrate-state --force (Structured-First onboarding).
- ai doctor --repair triggers npm install + .mcp.json realignment for broken servers.
- ai doctor --compliance triggers Ghost Tool compliance scan via verification-mcp (gemini/skills included).
- readStateStrict returns null on version != "1.0" (state-writer.js and task-synchronizer-mcp).

## MCP servers active (from .mcp.json):
- filesystem: project-root-scoped filesystem access (path: `.`).
- memory: knowledge-graph memory store at default scope.
- TestSprite: AI test generation (env: TESTSPRITE_API_KEY).
- Custom servers (all at ~/.ai-os/mcp/): vibe-check-mcp, intent-refiner-mcp, task-synchronizer-mcp, safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp, risk-analyzer-mcp, context-invoker-mcp, archive-manager-mcp, orchestrator-mcp, memory-manager-mcp, verification-mcp.

## Recent changes (last 10):
- 2026-03-16: Version guard added to readStateStrict — version != "1.0" returns null; T-02.12 added (src/mcp/shared/state-writer.js, src/mcp/task-synchronizer-mcp/index.js) [E-117].
- 2026-03-16: gemini/skills added to search_paths in _run_compliance_audit() (src/bin/ai) [E-116].
- 2026-03-16: T-02.11 + T-02.12 added to state_json_test.sh — delta-marking and version guard correctness [E-115].
- 2026-03-16: _query_similar_signatures() wired into do_init() for advisory hints at ai init (src/bin/ai) [E-114].
- 2026-03-16: Check 4 added to pre-commit.sh (blocks ## headings in REVIEWS.md); ARCH_AUDIT stamp truncated; REVIEWS.md regenerated (hooks/pre-commit.sh) [E-113].
- 2026-03-16: tests/suites/archive_tasks_test.sh — 7 assertions for archive_done_tasks threshold/prune logic [E-112].
- 2026-03-16: tests/suites/verification_test.sh — 12 assertions for verification-mcp Ghost Tool detection [E-111].
- 2026-03-16: tests/suites/memory_manager_test.sh — 13 assertions for memory-manager-mcp [E-110].
- 2026-03-16: verification-mcp created — verify_compliance scans YAML frontmatter, flags Ghost Tools CRITICAL (src/mcp/verification-mcp) [E-108].
- 2026-03-16: memory-manager-mcp created — export_signature + query_signatures, global signatures.json at ~/.ai-os/memory/ (src/mcp/memory-manager-mcp) [E-106].
