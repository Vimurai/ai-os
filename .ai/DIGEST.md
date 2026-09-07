# DIGEST — AI-OS v2 (Updated: 2026-09-07)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.
- **D-054 (2026-09-04): the same-provider Triad is a SUPPORTED topology.** Both roles may run on one provider in separate tmux panes; role identity binds PER PANE at launch via `ai pane <role>`, never per project.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI pins Node 22), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect: currently bound to **claude** (`.ai/roles.json`), pane 1. D-053 + `structured-outputs.md §32` were ratified 2026-07-31 (closed). Ruled D-055 (2026-09-07) on the D-054 sprint residuals → E-216/E-217/E-218 registered for the Engineer.
- Engineer (Claude): shipped the entire **D-054 sprint (E-208..E-215, 8 tasks)** — merged to `master` and pushed. Queue EXHAUSTED (0 open).
- Tester: bash suite now 114 files, **3403 assertions, 0 failing**.

## Current Focus
- D-054 sprint COMPLETE and merged. Next: Architect rulings on the open items under Known Risks — chiefly the skill-name collision (`ai-task`/`repo-oracle` serve different roles under one name) and whether to widen the Architect write gate beyond the native write tools.

## Key Decisions
- D-052: Retain Vendor-Named Provider Directories (cancel E-188 Part 2 rename).
- D-051: Ratify E-183 Shim Approach for Legacy CLI Loaders (keep CLAUDE.md/GEMINI.md as @import shims).
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).

## Known Risks
- **Architect write gate is NARROWED, not closed (E-208).** Shell writes (`>`, tee, cp, mv, sed -i, ln -s, git apply, python3 -c) and the MCP write tools (`mcp__filesystem__*`, `mcp__patch-mcp__*`) are NOT covered — they sit outside the hook matcher. Treat an Architect pane as honour-system for shell writes. Widening is a policy expansion beyond §Components 5 and needs an Architect ruling.
- **Skill-name collision (E-212).** `ai-task` and `repo-oracle` exist in both `shared/skills` and `agents/skills` with DIFFERENT content. A flat workspace cannot hold both, so a multi-role workspace keeps the shared baseline and reports the collision; a single-role workspace keeps the historical role-overrides-shared behaviour. Real fix (role-scoped skill dirs, or renaming) is an Architect ruling.
- **Git Lane residual risk (E-214)** — recorded as `THREAT_MODEL.md` T-GITLANE-001: `git commit --amend` escapes the scope check; the E-129 record is selected by an unauthenticated `CLAUDE_CODE_SESSION_ID`; `--no-verify`/`merge`/`cherry-pick` bypass the hook; and the stamp waiver is reachable by a non-Architect for a `.ai/`-only commit — which matters because `.ai/` holds `REVIEWS.md`, the file Gate 2 reads.
- **Mint guard is partial (E-208).** It enforces "a valid binding may not be changed", not immutability — deleting or corrupting the record and minting fresh still works. A real fix needs the record bound to something the deleter cannot forge.
- Pre-existing: `src/claude/agents/seo_engineer.md` has lacked a `context:` key since E-90 — the only one of 20 agents failing the frontmatter contract.
- `advisor-mcp`'s env allowlist needs `USER` as well as PATH+HOME; `role-abstraction.md` §Security still says "PATH + HOME suffice", which is measurably false for a Claude Architect.
## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-09-07: **E-213** Architect overlay allow rules + provider-aware owner/Actor labels; legacy `Bash(gemini -p *)` dropped and pruned.
- 2026-09-07: **E-215** ARCHITECT.md runtime ladder (Skill tool → run_preflight → activate_skill) + `ai doctor` per-role provisioning report.
- 2026-09-07: **E-214** Architect-scoped Git Lane (Tier 3, SEC_CLEARED after a blocking fail-open was found and fixed) + `safe-exec --verify-role`.
- 2026-09-06: **E-212** role manifest in `registry.json` + role-aware `do_sync`; a Claude Architect now gets 47 skills / 20 agents (was 35 / 13).
- 2026-09-05: **E-208** per-pane role binding: `ai pane <role>`, launch-time role mint, `[AI_OS_ROLE]` stamp, Role Resolution clause, Write/Edit sovereignty gate (Tier 3, SEC_CLEARED after 3 audit rounds).
- 2026-09-04: **E-210** provider-aware `advisor-mcp` bridge + shared `provider-adapter.mjs`; **E-211** legacy provider targets deprecated, ambiguity fails closed.
- 2026-09-04: **E-209** `resolve_pane` precedence — roles.json ordinal before fuzzy title for semantic targets (fixed a live handoff misroute).
- 2026-09-04: **D-054** ratified; `.ai/roles.json` architect provider agy → claude.
