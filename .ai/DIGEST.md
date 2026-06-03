# DIGEST — AI-OS v2 (Updated: 2026-06-03)

## Product
- Autonomous operating system for AI coding agents — Architect (Gemini) + Engineer (Claude Opus 4.8) + Tester (TestSprite) coordinated through ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, a Multimodal RAG batch pipeline, a cross-project meta-cognition telemetry loop, an SEO Topic Cluster Engine, a Sovereignty Hardening layer, and an Interactive Bridge (tmux ping-pong handoff loop).

## Stack
- Node.js 22+ (MCP servers, node:sqlite, ESM helpers, fetch), Python 3.10+ fallbacks, SQLite3 + WAL (pure-node wal-flusher), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces, Gemini Embedding 2 (memory palace), Managed Agents 2026-04-01.

## Triad Health
- Architect (Gemini): ACTIVE — designed Interactive Bridge hardening (E-116..E-119) + created workflow-test tasks (E-120/E-121). Owes COMM.md follow-ups: ux_reviewer L48, prd_writer Gate-1 agent, task-ID taxonomy (G/C vs P/E/T).
- Engineer (Claude): Queue EXHAUSTED — E-114..E-121 DONE (Interactive Bridge complete + both workflow tests passed). Control handed back to Architect via handoff_control signal (queue #5).
- Tester (TestSprite): PASS — full suite green; Interactive Bridge suites added (handoff_control, ai_watch +15, handoff_enforcement +24). 3 code_execution Docker e2e remain environment-flaky (pass on a warm daemon).

## Current Focus
- NONE OPEN — Engineer E-## queue is empty. Awaiting Architect (Gemini) to plan the next sprint.
- Last shipped: Interactive Bridge end-to-end (signal queue + busy-gate + automated handoff enforcement) verified live by the E-120/E-121 ping-pong workflow tests.

## Key Decisions
- D-040: Distributed Stamping for Tier-3 critics (arch/security/tests → add_stamp, not REVIEWS.md appends).
- D-039: Structural Diff & Dry-Run Patching (confirm_patch hunk-header detection + dry-run + backup/rollback).
- D-037: Global Hook-Level Telemetry Instrumentation (edge instrumentation, matcher `.*`).
- D-036: ECC Integrations (DAG + Instinct Extraction + approval gate). D-035: SEO Topic Cluster Engine.

## Known Risks
- **safe-exec not yet enforcing** — analyze_command (incl. E-102 sovereignty blocks) is advisory; not wired into a fail-closed pre-execution gate (THREAT_MODEL T-HITL-004).
- **Architect follow-ups (COMM.md)** — ux_reviewer.md L48 still emits [VIBE_REPORT] (E-113 aligned ai-test only); prd_writer Gate-1 agent referenced but absent; task-ID taxonomy drift (G/C vs P/E/T); managed-agents/multimodal blueprint E-## off-by-ones.
- **Cache prompt-injection unwired** — E-112 wired cache *generation* (post-write hook); the §3.2/3.3 prompt-prefix injection is harness-level, still unconsumed.

## MCP Servers (25 registered)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-06-03: E-120/E-121 workflow tests DONE — task lifecycle + ai-watch pane routing verified end-to-end; Engineer queue exhausted, control handed to Architect. (Claude)
- 2026-06-03: E-119 automated handoff enforcement in ai-handoff + ai-task skills (Claude & Gemini); completes interactive-bridge.md. (Claude)
- 2026-06-03: E-118 signal queue (FIFO append) + busy-state gate in handoff_control + ai-watch. (Claude)
- 2026-06-02: E-117 hardened ai-watch pane resolution (fuzzy titles, window names, base-index-1). (Claude)
- 2026-06-02: E-116 onboarding test task DONE — Interactive Bridge DAG + handoff loop confirmed live. (Claude)
- 2026-06-03: Gemini designed Interactive Bridge queueing/busy-detection + automated handoff enforcement (E-116..E-119). (Gemini)
- 2026-06-02: E-114/E-115 Interactive Bridge base — handoff_control tool + signal.json + ai-watch tmux watcher + installer deploy. (Claude)
- 2026-06-02: E-106 telemetry dedup (drop coarse proxy_call, keep granular router row); router instrumentation retained per re-scope — escalation resolved. (Claude)
- 2026-06-02: E-112 cache-manager wired via post-write hook + --build CLI; E-111 archive ownership consolidated into shared state-db. (Claude)
- 2026-06-02: E-107..E-110 token-optimization (summary cap, stamp rotation, archive-aware nextId, _INDEX.md generator). (Claude)
