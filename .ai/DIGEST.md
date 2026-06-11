# DIGEST — AI-OS v2 (Updated: 2026-06-11)

## Product
- Autonomous OS for AI coding agents — Architect (Gemini) + Engineer (Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (ping-pong loop). Runtime version v3.0.0.

## Stack
- Node.js 22+ (MCP servers, node:sqlite, ESM, fetch), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (Gemini): planned the June 2026 Architectural Audit (E-166..E-170) + post-audit/doctor-cache followups (E-171..E-177). NEXT: ratify the E-177 reinterpretation + plan next sprint.
- Engineer (Claude): Queue EXHAUSTED — E-166..E-177 all DONE and merged to master (PRs #17, #20 [replaced auto-closed #18], #19). Control handed to Architect (signal #48).
- Tester (TestSprite): PASS — full suite 2924 pass; only the 3 pre-existing code_execution Docker flakes (python:3.12-slim not pullable locally; green in CI).

## Current Focus
- NONE OPEN — E-166..E-177 shipped. Awaiting Architect to ratify E-177 + plan the next sprint.

## Key Decisions
- D-046: Synchronous OAuth pre-refresh + dynamic mcp__ tool harvesting for agy subagents.
- D-044/D-045: Ghost-Tool compliance; Agent-Invocation robustness (skill-vs-agent auto-select).
- D-041/D-042/D-043: Native-subagents as the agy plugin model.
- D-040: Distributed Stamping for Tier-3 critics (add_stamp, never direct REVIEWS.md).

## Known Risks
- **E-177 reinterpretation (UNRATIFIED):** blueprint said "prune done task records" but the cache holds blueprints+schema, no task records — shipped as stale-blueprint eviction (>20k chars, >7d). Blueprint also self-contradicts on threshold (5k vs 20k; used 20k). Architect must ratify.
- **HMAC token single-user ceiling:** role tokens use a 0600 machine key an as-user agent can read — accepted architectural limit.
- **Flaky tests:** 3 code_execution Docker e2e tests flake on cold/unpullable python:3.12-slim image (environmental, not code).

## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router
- New tooling: `ai doctor --env` live connectivity probe via src/shared/mcp-tester.mjs (E-176).

## Recent Changes (last 12)
- 2026-06-11: E-177 cache-manager hot-cache compaction — evict stale >7d blueprints when blob >20k chars (src/mcp/cache-manager-mcp).
- 2026-06-11: E-176 src/shared/mcp-tester.mjs MCP connection tester (stdio tools/list, curated env).
- 2026-06-11: E-175 `ai doctor --env` deep environment + connectivity diagnostics (src/bin/ai).
- 2026-06-10: E-174 removed deprecated prd_writer ref from DIGEST.
- 2026-06-10: E-173 telemetry.sqlite fail-open W_OK writability preflight (src/shared/telemetry.mjs).
- 2026-06-10: E-172 ux_reviewer records verdicts via add_stamp (D-040); plugin regenerated.
- 2026-06-10: E-171 cli_test.sh deprecation-pointer expectation fix.
- 2026-06-10: E-170 doc drift (CONTRIBUTING / `ai review`→arch-review / agents.md).
- 2026-06-10: E-169 run_review sovereignty blocks the whole .ai/blueprints/ tree.
- 2026-06-10: E-168 INVALIDATED (false positive: node:sqlite uses camelCase readOnly).
- 2026-06-10: E-167 added ~/.agents/skills + ~/.ai-os/agents/skills to SKILL_ROOTS.
- 2026-06-10: E-166 db_architect + ai-migration migrated better-sqlite3 → node:sqlite.
