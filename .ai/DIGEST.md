# DIGEST — AI-OS v2 (Updated: 2026-06-26)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (agy): ratified D-051 (E-183 shim approach), committed D-051 to DECISIONS.md. NEXT: review PRs #23 and #24, plan next sprint.
- Engineer (Claude): Queue **EXHAUSTED** — E-185/186/187 all DONE (flaw remediation). Control handed back to the Architect.
- Tester (TestSprite): full suite 3010 pass; 0 failed (code_execution Docker flakes resolved).

## Current Focus
- NONE OPEN — E-185..E-187 shipped. Awaiting Architect to review PRs #23, #24 and plan the next sprint.

## Key Decisions
- D-051: Ratify E-183 Shim Approach for Legacy CLI Loaders (keep CLAUDE.md/GEMINI.md as @import shims).
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).
- D-048: Ratify E-179 telemetry classification refinement (expected_rejection marker).

## Known Risks
- NONE. All previous risks (E-183 shim unratified, telemetry enum DRY, plugin agent.json byte-test gap, flaky tests, uncommitted architect.md) have been resolved.

## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-06-26: E-187 code_execution Docker e2e tests deflaked with retry logic.
- 2026-06-26: E-186 byte-identity test for generated plugin agent.json implemented.
- 2026-06-26: E-185 telemetry status enum extracted to DRY source of truth.
- 2026-06-26: D-051 ratified E-183 shim approach.
- 2026-06-25: E-184 README → decoupled rulefile naming (ENGINEER/ARCHITECT.md) + default providers (agy/claude); removed deprecated Gemini CLI refs.
- 2026-06-25: E-183 Decouple Triad persona (D-050) — CLAUDE/GEMINI.md → canonical ENGINEER/ARCHITECT.md + @import shims; bin/ai sync/anti-drift/usage; roles default agy:1; 6 test suites + 2 skills updated.
- 2026-06-25: E-180 telemetry REJECTED status (D-049) — +REJECTED enum/CHECK + atomic migration (db_architect P1 fix: orphan-merge & CHECK-rebuild sequential); expected_rejection→REJECTED; meta_analyst Aggregate A excl REJECTED + new Aggregate F. Tier-3 ALL PASS.
- 2026-06-21: E-182 bin/ai — documented `ai watch`; reframed migrate-state/mcp-setup as live Recovery commands (not Removed).
- 2026-06-21: E-181 README rewrite — v3.0.0, 22 custom + 3 third-party MCP, Native Subagents (20) taxonomy, Interactive Bridge.
- 2026-06-21: E-179 telemetry failure-rate audit — `_meta.expected_rejection` marker so expected rejections stop polluting the ERROR deprecation aggregate (superseded by E-180's REJECTED dimension).
