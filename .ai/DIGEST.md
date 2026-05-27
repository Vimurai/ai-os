# DIGEST — AI-OS v2 (Updated: 2026-05-27)

## Product
- Autonomous operating system for AI coding agents — Architect (Gemini 3.1 Pro) + Engineer (Claude Opus 4.7) + Tester (TestSprite) coordinated through ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, a Multimodal RAG batch pipeline, a cross-project meta-cognition telemetry loop, and an SEO Topic Cluster Engine.

## Stack
- Node.js 22+ (MCP servers, node:sqlite, node:fs ESM helpers, fetch), Python 3.10+ fallbacks, SQLite3 + WAL (TRUNCATE checkpoint via pure-node wal-flusher), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces, Gemini Embedding 2 (memory palace), Managed Agents 2026-04-01 (steps schema, live client feature-flagged).

## Triad Health
- Architect (Gemini): IDLE — P-## DONE. Active blueprints: ecc-integrations.md (DONE via E-91..E-94), ast-repository-map.md (pending E-95..E-98).
- Engineer (Claude): all E-## DONE through E-94. Latest sprint E-91..E-94 = ecc-integrations.md (DAG dependencies + dispatch + instinct extraction + approval-gated skill promotion) — COMPLETE.
- Tester (TestSprite): PASS — 2040 assertions post-E-94 (84 new across the ecc sprint).

## Current Focus
- ecc-integrations.md COMPLETE (E-91..E-94). Next backlog: ast-repository-map.md (E-95 ast-parser-mcp, E-96 ranking, E-97 generate_map→REPO_MAP.md, E-98 ai-sync/preflight wiring).
- ⚠ `state.json.project.focus` reflects the last set focus (E-94); clears on next handover.
- Meta-cognition loop live: `~/.ai-os/telemetry.sqlite` (E-84) + `meta_analyst`/`ai-insights` (E-85) + preflight staleness check (E-86). INSIGHTS.md status `[INSIGHTS_STABLE]` (21 rows, 1 tool, 0 actionable signals).

## UX / SEO / Frontend
- UX: Terminal-first (Claude Code, Gemini CLI, tmux); structured Markdown outputs and NDJSON logs with no ANSI escapes on critical paths.
- SEO: Topic Cluster Engine — 1 Pillar + N distinct-intent cluster pages (11 canonical intents) replacing the retired 20-format spin model. Target queries: "autonomous AI agent OS", "Claude Gemini coordination framework", "MCP server template".
- Frontend: CLI tool (no web framework). SQLite authoritative + JSON projections for Markdown. Skills addressed by name; MCP tools by qualified path.

## Key Decisions
- D-001..D-025 — see prior digests (preserved verbatim in archive sweep 2026-05-09).
- D-026: Tool Alias Normalizer — verification-mcp resolves Gemini-canonical names via frozen TOOL_ALIASES + ALIAS_VALUES Set.
- D-027: Installer fail-closed Node guard — install-ai-os.sh probes Node 22+ before file copy; POSIX-mode re-exec via SHELLOPTS (E-72).
- D-028: Managed Agents live client — managed-agents-client.mjs feature-flagged OFF by default; https-only + allowlist.
- D-029: BRIEF.md substantive — replaced template with concrete product brief.
- D-030: Managed Agents state reconciliation — projectState() + debounced syncToCloud(); sync hook fires from task-synchronizer-mcp add_task/update_task_status only.
- D-031: Multimodal RAG batch pipeline — memory-batch-scanner.mjs (7-gate SHA-256 cache) + memory-worker-pool.mjs (bounded concurrency, backoff, DLQ).
- D-032: SEO Keyword Multiplier (SUPERSEDED by D-035) — 20-slug canonical taxonomy in seo-approach-types.mjs.
- D-033: Engineering-Standards gate — standards.json (6 rules) + scripts/standards.mjs CLI (<200ms) + critic_clean_code persona + pre-commit hook. AI_OS_SKIP_STANDARDS=1 rollback.
- D-034: Meta-cognition telemetry — `~/.ai-os/telemetry.sqlite` records tool_name+execution_time_ms+status ONLY (no payloads), grouped by opaque project_hash; mcp-router background hook (E-84); read-only/aggregate-only meta_analyst writes INSIGHTS.md (E-85); AI_TELEMETRY_DISABLE=1 rollback.
- D-035: SEO Topic Cluster Engine — pivot from 20-format-spins-per-keyword to 1 Pillar + N distinct-intent cluster pages (prevents keyword cannibalization). seo-approach-types.mjs → seo-cluster-intents.mjs (11 intents); lifted rigid 20-cap; new seo_engineer.md execution persona (E-87/E-88/E-90).
- D-036: ECC Integrations — DAG task orchestration + instinct pipeline (ecc-integrations.md, E-91..E-94). tasks.depends_on (JSON col) with DFS cycle + self-ref + depth-5 detection (state-db.js validateDag) and DONE→OPEN unblock cascade; orchestrator run_dispatch computes the ready frontier (parallel/sequential/idle). meta_analyst Instinct-Extraction mode clusters recurring successes into INERT proposed Gemini skills (instinct-stager.mjs: confidence≥0.7 gate + dangerous-content rejection); promotion to active is fail-closed behind the approval-mcp HITL gate (skill-promoter.mjs). index.js tool array extracted to tool-schemas.mjs to stay under the 1000-line cap.

## Known Risks
- **state.json stamp bloat** — after DONE-task archiving, `stamps` (48 KB / 91 items) is the largest block and NO standard MCP tool drains it (`archive_done_tasks` covers only `tasks`; `ai-archive` skill covers only `.ai/*.md`). Needs an auto-rotate mechanism (open Architect proposal in COMM.md 2026-05-26).
- **Per-task summary bloat** — DONE tasks store full ~1–2 KB narrative summaries mirrored into state.json AND TASKS.md; re-accumulates between archives unless capped (open Architect proposal).
- Managed Agents client (E-70/E-73/E-74) feature-flagged OFF; first live rollout needs auth probe + cloud convergence test.
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported.
- code-execution-mcp depends on Docker daemon — fail-closed when unavailable.
- WAL checkpoint requires Node 22+ on dev boxes; auto-generated mcp.md (E-52) drifts if edited manually.
- Test harnesses driving task-synchronizer-mcp must scrub AIOS_WORKSPACE / AIOS_WORKSPACE_DISABLE from the child env, else is_framework_task=true paths can write the real repo's state.sqlite.

## MCP Servers (25 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp
- Interop: advisor-mcp, approval-mcp | Caching: cache-manager-mcp | Compute: code-execution-mcp | Routing: mcp-router

## Recent Changes (last 10)
- 2026-05-27: E-91..E-94 ecc-integrations.md COMPLETE — DAG depends_on + cycle/depth detection (state-db.js), orchestrator run_dispatch, instinct-stager.mjs (staged inert proposed skills), skill-promoter.mjs (approval-mcp-gated promotion); tool-schemas.mjs extraction. +84 tests (2040 total). Uncommitted until this commit.
- 2026-05-26: Maintenance — archived 45 DONE tasks → .ai/archive/state-done-2026-05.json (state.json 134→76 KB, TASKS.md 64→15 KB); INSIGHTS.md generated [INSIGHTS_STABLE]; DIGEST regenerated.
- 2026-05-25: E-87/E-88/E-90 SEO Topic Cluster Engine — seo_manager.md → Topic-Cluster-Manager, seo-approach-types.mjs → seo-cluster-intents.mjs (11 intents), new seo_engineer.md (commit b2f9fa8).
- 2026-05-20: E-86 ai-preflight INSIGHTS.md staleness check (meta-cognition.md).
- 2026-05-20: E-85 meta_analyst agent + ai-insights skill.
- 2026-05-20: E-84 telemetry.sqlite + mcp-router background hook.
- 2026-05-19: E-83 dynamic locator chain in scripts/standards.mjs.
- 2026-05-19: E-82 pre-commit standards gate (hooks/pre-commit.sh, AI_OS_SKIP_STANDARDS rollback).
- 2026-05-19: E-81 critic_clean_code persona — ai-review Tier 2/3 wiring.
- 2026-05-19: E-80 standards.json + scripts/standards.mjs CLI + standards-checker.mjs (6 rules).
- 2026-05-19: E-77..E-79 SEO Keyword Multiplier (since refactored by D-035).
- 2026-05-27: auto-stamped by Stop hook
