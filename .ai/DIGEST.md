# DIGEST — AI-OS v2 (Updated: 2026-06-25)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect (agy): ratified D-048 (E-179 classification), D-049 (E-180 schema), D-050 (persona decouple). NEXT: ratify the E-183 shim approach + commit the uncommitted `.ai/architect.md` role-abstraction rewrite (blocks the Tier-2 review gate) + plan next sprint.
- Engineer (Claude): Queue **EXHAUSTED** — E-180/181/182/183/184 all DONE. Control handed back to the Architect.
- Tester (TestSprite): full suite 2999 pass; only the 3 pre-existing code_execution Docker flakes (python:3.12-slim not pullable locally; green in CI).

## Current Focus
- NONE OPEN — E-180..E-184 shipped. Awaiting Architect to ratify the shim/telemetry refinements and plan the next sprint.

## Key Decisions
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).
- D-048: Ratify E-179 telemetry classification refinement (expected_rejection marker).
- D-047/D-046: E-177 cache eviction reinterpretation; Antigravity subagent execution robustness.

## Known Risks
- **E-183 shim UNRATIFIED:** `CLAUDE.md`/`GEMINI.md` kept as `@import` shims (Claude Code auto-loads CLAUDE.md) — D-050 alt #1 "rejected keeping" them; pending Architect ratification. Deferred: resolver legacy no-roles.json `gemini` fallback + global `src/claude`/`src/gemini` rulefiles left vendor-named.
- **Uncommitted `.ai/architect.md`** (Architect's role-abstraction rewrite) triggers a P0 sovereignty flag that blocks `run_review`/commit until committed.
- **Telemetry enum DRY (db_architect nit):** status enum hardcoded at ~5 coupled sites in telemetry.mjs — candidate hardening (derive CHECK + migration sentinel from STATUS_VALUES).
- **Plugin agent.json byte-test gap:** generated `src/agents/plugin/agents/meta_analyst/agent.json` has no byte-identity test vs the source `.md` (pre-existing).
- **Flaky tests:** 3 code_execution Docker e2e tests flake on cold/unpullable python:3.12-slim (environmental).

## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 12)
- 2026-06-25: E-184 README → decoupled rulefile naming (ENGINEER/ARCHITECT.md) + default providers (agy/claude); removed deprecated Gemini CLI refs.
- 2026-06-25: E-183 Decouple Triad persona (D-050) — CLAUDE/GEMINI.md → canonical ENGINEER/ARCHITECT.md + @import shims; bin/ai sync/anti-drift/usage; roles default agy:1; 6 test suites + 2 skills updated.
- 2026-06-25: E-180 telemetry REJECTED status (D-049) — +REJECTED enum/CHECK + atomic migration (db_architect P1 fix: orphan-merge & CHECK-rebuild sequential); expected_rejection→REJECTED; meta_analyst Aggregate A excl REJECTED + new Aggregate F. Tier-3 ALL PASS.
- 2026-06-21: E-182 bin/ai — documented `ai watch`; reframed migrate-state/mcp-setup as live Recovery commands (not Removed).
- 2026-06-21: E-181 README rewrite — v3.0.0, 22 custom + 3 third-party MCP, Native Subagents (20) taxonomy, Interactive Bridge.
- 2026-06-21: E-179 telemetry failure-rate audit — `_meta.expected_rejection` marker so expected rejections stop polluting the ERROR deprecation aggregate (superseded by E-180's REJECTED dimension).
- 2026-06-21: E-178 CLI automation wrapper skills (ai-analyze, ai-sync-verify, ai-dispatch, ai-topic, ai-cluster) for the top-5 high-frequency MCP tools.
- 2026-06-11: E-177 cache-manager hot-cache compaction (evict stale >7d blueprints when blob >20k).
- 2026-06-11: E-176 src/shared/mcp-tester.mjs MCP connection tester; E-175 `ai doctor --env`.
- 2026-06-10: E-172 ux_reviewer records verdicts via add_stamp (D-040); E-169 run_review sovereignty blocks the whole .ai/blueprints/ tree.
- 2026-06-10: E-166 db_architect + ai-migration migrated better-sqlite3 → node:sqlite.
