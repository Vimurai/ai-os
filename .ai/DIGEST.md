# DIGEST — AI-OS v2 (Updated: 2026-07-06)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (agy): owes D-053 ratification + `structured-outputs.md §32` amendment for the E-198 `ai add-task` shell-native exception (sovereignty-gated — Engineer must not author).
- Engineer (Claude): Queue **EXHAUSTED** — E-197..E-200 DONE & merged (PRs #30/#31/#32). Control handed to the Architect (COMM.md + handoff signal queued).
- Tester (TestSprite): full suite green post-merge.

## Current Focus
- Architect ratification of **D-053** (authorize `ai add-task` as an audited exception to MCP-only state mutation) + amend `structured-outputs.md §32`. Engineer queue otherwise empty.

## Key Decisions
- D-052: Retain Vendor-Named Provider Directories (cancel E-188 Part 2 rename).
- D-051: Ratify E-183 Shim Approach for Legacy CLI Loaders (keep CLAUDE.md/GEMINI.md as @import shims).
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).

## Known Risks
- E-198 `ai add-task` is code-complete but not yet blueprint-ratified — pending the Architect's D-053 + `structured-outputs.md §32` follow-through. Until then the shell-native state-mutation exception is de-facto, not documented.

## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-07-06: E-200 handoff completion barrier — `ai handoff --settle` polls the task-table signature until registration quiesces before waking the Engineer (fixes agy handing off mid-generation → half-empty queue). task-planner/ai-handoff mandate it (PR #32).
- 2026-07-06: E-198 shell-native `ai add-task` (Architect Ruling A / pending D-053) — shared `state-db::addTask` single write path for MCP add_task + the CLI; lets agy persist tasks from the Antigravity shell that survive verify_markdown_sync (PR #31).
- 2026-07-05: E-199 fixed date-rollover time-bomb in token_optimization_test (hardcoded stamps-2026-06 → `date -u +%Y-%m`); unblocked repo-wide CI (PR #30).
- 2026-07-05: E-197 advisor-mcp A2A bridge re-pointed gemini CLI → `agy --print` (D-050 follow-through; E-192 had KEPT the retired gemini bridge → IneligibleTierError on every escalation) (PR #30).
- 2026-06-26: D-052 ratified retaining vendor directories for provider configs.
- 2026-06-26: E-188 Part 1 shipped (resolver legacy fallback).
- 2026-06-26: E-187 code_execution Docker e2e tests deflaked with retry logic.
- 2026-06-26: E-186 byte-identity test for generated plugin agent.json implemented.
- 2026-06-26: E-185 telemetry status enum extracted to DRY source of truth.
- 2026-06-26: D-051 ratified E-183 shim approach.
