# DIGEST — AI-OS v2 (Updated: 2026-06-02)

## Product
- Autonomous operating system for AI coding agents — Architect (Gemini) + Engineer (Claude Opus 4.8) + Tester (TestSprite) coordinated through ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, a Multimodal RAG batch pipeline, a cross-project meta-cognition telemetry loop, an SEO Topic Cluster Engine, and a Sovereignty Hardening layer.

## Stack
- Node.js 22+ (MCP servers, node:sqlite, ESM helpers, fetch), Python 3.10+ fallbacks, SQLite3 + WAL (pure-node wal-flusher), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces, Gemini Embedding 2 (memory palace), Managed Agents 2026-04-01.

## Triad Health
- Architect (Gemini): ACTIVE — replanned the Engineer's gap-review handoff into E-107..E-115; authored token-optimization.md + interactive-bridge.md; owes E-106 re-scope + the ux_reviewer/prd_writer/blueprint-ID follow-ups in COMM.md.
- Engineer (Claude): Gap-review sprint COMPLETE — PR #3 (10 commits, 54 files), E-101/E-102/E-107/E-108/E-109/E-110/E-111/E-112/E-113 DONE. Awaiting Architect on E-106; E-114/E-115 (interactive-bridge) open.
- Tester (TestSprite): PASS — 2322 assertions green; 3 code_execution Docker e2e are environment-flaky (pass on a warm daemon).

## Current Focus
- E-114 (OPEN): handoff_control tool in task-synchronizer-mcp managing .ai/signal.json (interactive-bridge.md).
- E-115 (BLOCKED on E-114): ai-watch global script (src/bin/ai-watch) + installer deploy (interactive-bridge.md).
- E-106 (OPEN): mcp-router telemetry — ESCALATED, do NOT remove (sole granular proxy source; breaks S09). Architect to re-scope (WONTFIX / dedupe-by-source) per COMM.md.

## Key Decisions
- D-040: Distributed Stamping for Tier-3 critics (arch/security/tests → add_stamp, not REVIEWS.md appends).
- D-039: Structural Diff & Dry-Run Patching (confirm_patch hunk-header detection + dry-run + backup/rollback).
- D-037: Global Hook-Level Telemetry Instrumentation (edge instrumentation, matcher `.*`).
- D-036: ECC Integrations (DAG + Instinct Extraction + approval gate). D-035: SEO Topic Cluster Engine.

## Known Risks
- **E-106 mis-premised** — removing router instrumentation loses granular `<server>.<tool>` proxy telemetry + reds test S09; awaiting Architect re-scope (not an Engineer call).
- **safe-exec not yet enforcing** — analyze_command (incl. E-102 sovereignty blocks) is advisory; not wired into a fail-closed pre-execution gate (THREAT_MODEL T-HITL-004).
- **Architect follow-ups (COMM.md)** — ux_reviewer.md L48 still emits [VIBE_REPORT]; prd_writer Gate-1 agent referenced but absent; task-ID taxonomy (G/C vs P/E/T); managed-agents/multimodal blueprint E-## off-by-ones.
- **Cache prompt-injection unwired** — E-112 wired cache *generation* (post-write hook); the §3.2/3.3 prompt-prefix injection is harness-level, still unconsumed.

## MCP Servers (25 registered)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-06-02: E-112 cache-manager wired via post-write hook (rebuild on blueprint/architect.md writes) + --build CLI. (Claude)
- 2026-06-02: E-111 archive ownership consolidated into shared state-db (SQLite-aware, ACID); execute_archive fixed. (Claude)
- 2026-06-02: E-109 nextId archive-aware (live + archived + high-water) — resolves state-json-db id-drift. (Claude)
- 2026-06-02: E-110 _INDEX.md auto-generator (all 33 blueprints) + gitignored like _SKILLS_INDEX. (Claude)
- 2026-06-02: E-113 ai-test emits [VIBE_CLEARED] via add_stamp (satisfies review_synthesizer). (Claude)
- 2026-06-02: E-107/E-108 DONE-summary cap (200) + audit-stamp rotation (token-optimization.md). (Claude)
- 2026-06-02: Gap-review fix sprint — E-101 DONE-lock, E-102 sovereignty blocks, telemetry matcher root-cause, confirm_patch safety, dead-code sweep, critic→add_stamp. PR #3. (Claude)
- 2026-06-02: Gemini replanned the gap-review handoff → E-107..E-115; authored token-optimization.md + interactive-bridge.md. (Gemini)
- 2026-06-01: E-105 post-tool-use.sh telemetry pipe; E-104 telemetry CLI handlers. (Claude)
- 2026-05-27: E-95..E-100 ast-repository-map + ecc-integrations + forked-skill fix COMPLETE. (Claude)
- 2026-06-03: auto-stamped by Stop hook
