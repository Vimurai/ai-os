# DIGEST — AI-OS v2 (Updated: 2026-08-04)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI pins Node 22), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (agy): owes D-053 ratification + `structured-outputs.md §32` amendment for the E-198 `ai add-task` shell-native exception (sovereignty-gated — Engineer must not author).
- Engineer (Claude): last shipped **E-205 + E-206** (test hardening) on branch `engineer/e205-mcp-client-flake-retry` — NOT yet merged. Queue otherwise EXHAUSTED (89 DONE, 0 open).
- Tester (TestSprite): bash suite now 109 files. Core green; two load-sensitive flakes known (see Risks).

## Current Focus
- Merge the E-205/E-206 test-hardening branch (PR pending), then Architect ratification of **D-053** (+ amend `structured-outputs.md §32`).

## Key Decisions
- D-052: Retain Vendor-Named Provider Directories (cancel E-188 Part 2 rename).
- D-051: Ratify E-183 Shim Approach for Legacy CLI Loaders (keep CLAUDE.md/GEMINI.md as @import shims).
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).

## Known Risks
- E-198 `ai add-task` is code-complete but not yet blueprint-ratified — pending the Architect's D-053 + `structured-outputs.md §32` follow-through. Until then the shell-native state-mutation exception is de-facto, not documented.
- Test flakiness under CPU load: `advisor_mcp_test` fixed via MCP-client retry (E-205); `managed_agents_sync_hook_test` still flakes 2 stderr assertions under full-run load (passes 5/5 in isolation) — open follow-up, same transient-output class.

## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-08-04: E-206 node:test unit layer — tests/unit/state-db.test.mjs (26 assertions, real temp-SQLite) + tests/suites/node_unit_test.sh wiring node:test into tests/run.sh; 83% line coverage on state-db.js via Node built-in coverage (no new dep).
- 2026-08-04: E-205 test-harness flake fix — bounded retry in tests/lib/mcp-client.sh::_mcp_send (MCP_CLIENT_RETRIES/TIMEOUT) so a transient empty tools/list under load is no longer a false failure.
- 2026-07-31: E-204 auto-handoff on cross-role `ai add-task` (cli-add-task.mjs autoHandoffTarget + dedup); opt-out AI_OS_NO_AUTO_HANDOFF=1 (PR #34).
- 2026-07-31: E-203 granted ai-seo the `mcp__semrush__*` tool across src/ + mirrors (PR #34).
- 2026-07-06: E-202 Semrush integration into canonical ai-seo SKILL.md; E-201 ANTI-DRIFT restore of the Architect's mirror-only edit.
- 2026-07-06: E-200 handoff completion barrier — `ai handoff --settle` polls the task-table signature until registration quiesces before waking the Engineer (PR #32).
- 2026-07-06: E-198 shell-native `ai add-task` (Ruling A / pending D-053) — shared `state-db::addTask` single write path for MCP + CLI (PR #31).
- 2026-07-05: E-199 fixed date-rollover time-bomb in token_optimization_test; unblocked repo-wide CI (PR #30).
- 2026-07-05: E-197 advisor-mcp A2A bridge re-pointed gemini→`agy --print` (D-050 follow-through) (PR #30).
- 2026-06-26: D-052 ratified retaining vendor directories for provider configs.
