# ARCHITECT INDEX (Gemini-owned)

> **This is the index only.** Load the specific Domain Blueprint for your task — do NOT load all blueprints.
> Maintained by: Gemini (Principal Architect). Engineer reads only.

## System Summary
- **Product**: CLI framework embedding a Triad AI loop (Architect/Engineer/Tester) into any codebase via `.ai/` memory scaffolding and MCP servers.
- **Stack**: Bash (zero-dependency core), Node.js (MCP servers), Playwright (vibe), SQLite (token-budget), file-based markdown memory.

## Triad Roles
- **Architect (Gemini)**: Owns `architect.md`, `blueprints/`, `BRIEF.md`, `TASKS.md` (P-##). Plans only — no source code.
- **Engineer (Claude)**: Owns `src/`, `LOG.md`, `TASKS.md` (E-##), `SECURITY.md`, `DEVOPS.md`. Implements only — no architecture design.
- **Tester (TestSprite)**: Owns `tests/`. Validates only.

## Domain Blueprints (JIT — read only what your task requires)

| Domain | File | Read when task involves... |
|--------|------|---------------------------|
| Core | `.ai/blueprints/core.md` | System philosophy, UX flows, dev cycle, project scoping |
| Security | `.ai/blueprints/security.md` | Security, gates (AQG/TSRT), capabilities, anti-drift RBAC |
| Agents | `.ai/blueprints/agents.md` | Agent/skill architecture, UACS, domain isolation, agent specs |
| MCP Servers | `.ai/blueprints/mcp.md` | MCP server specs, LSP, patching, token budget, GitHub bridge |
| Governance | `.ai/blueprints/governance.md` | Token economics, JIT limits, UPDATE.md deprecation, preflight rules |
| Robustness | `.ai/blueprints/robustness.md` | State IO, sync race conditions, and patch resolution fallbacks |

## JIT Loading Protocol
1. Read `.ai/DIGEST.md` first — covers 80% of session-start context needs.
2. Read THIS index (already done) to orient on domain boundaries.
3. Load ONLY the domain blueprint relevant to your active task.
4. **Never load all blueprints** — that defeats fragmentation and burns tokens.

## Key Invariants (always in effect)
- UPDATE.md: **fully deprecated** (E-147). Never create or read it.
- Token limit: **6 files max** per task (enforced in CLI prompts).
- RBAC: Architect writes blocked from `src/` by `roleGuard()` in `patch-mcp` + `propose-patch-mcp`.
- Preflight standard: DIGEST.md → TASKS.md → this index → one domain blueprint if needed.
