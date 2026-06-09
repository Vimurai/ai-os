# DIGEST — AI-OS v2 (Updated: 2026-06-05)

## Product
- Autonomous operating system for AI coding agents — Architect (Gemini) + Engineer (Claude Opus 4.8) + Tester (TestSprite) coordinated through ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG batch pipeline, cross-project meta-cognition telemetry loop, SEO Topic Cluster Engine, Sovereignty Hardening layer, and Interactive Bridge (tmux ping-pong loop).

## Stack
- Node.js 22+ (MCP servers, node:sqlite, ESM helpers, fetch), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (Gemini): ACTIVE — planned v2.0.0 release, completed sovereignty + interactive bridge arcs.
- Engineer (Claude): Queue EXHAUSTED — E-131 DONE (v2.0.0 released and tagged). Control handed back to Architect.
- Tester (TestSprite): PASS — full suite green (2637 tests); only pre-existing Docker flakes.

## Current Focus
- NONE OPEN — v2.0.0 successfully shipped. All blueprints implemented. Engineer queue is empty. Awaiting Architect to plan next sprint.

## Key Decisions
- D-040: Distributed Stamping for Tier-3 critics.
- D-039: Structural Diff & Dry-Run Patching.
- D-038: 200-char cap on task summaries & stamp rotation.
- D-037: Global Hook-Level Telemetry.

## Known Risks
- **safe-exec fail-closed implemented** — E-125/E-128 hardened gate (THREAT_MODEL T-HITL-004), resolving prior risk.
- **HMAC token single-user ceiling:** The tamper-resistant role tokens are generated with a 0600 machine key, which an agent running as the user can theoretically read. This is an accepted architectural limit.
- **Architect follow-ups (COMM.md)** — ux_reviewer.md L48 still emits [VIBE_REPORT] (E-113 aligned ai-test only); prd_writer Gate-1 agent referenced but absent.
- **Flaky tests:** 3 code_execution Docker e2e tests occasionally flake depending on daemon warmth.

## MCP Servers
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-06-05: E-131 Official v2.0.0 GitHub Release drafted and published via gh CLI (.ai/TASKS.md).
- 2026-06-05: E-130 v2.0.0 released and tagged via release-manager skill (.ai/TASKS.md).
- 2026-06-05: E-129 Tamper-resistant HMAC role tokens (.ai/TASKS.md).
- 2026-06-05: E-128 safe-exec --check error path fail-closed (.ai/TASKS.md).
- 2026-06-05: E-127 safe-exec caller_role bootloader injection (.ai/TASKS.md).
- 2026-06-04: E-126 cache-manager context injection (.ai/TASKS.md).
- 2026-06-04: E-125 safe-exec fail-closed pre-execution gate (.ai/TASKS.md).
- 2026-06-04: E-124 ai-watch persistent delivery & backlog drain (.ai/TASKS.md).
- 2026-06-04: E-123 safe-exec-mcp merge/deploy sovereignty (.ai/TASKS.md).
- 2026-06-03: E-122 Formalized ai-watch fixes (.ai/TASKS.md).- 2026-06-08: auto-stamped by Stop hook
- 2026-06-08: auto-stamped by Stop hook
- 2026-06-09: auto-stamped by Stop hook
