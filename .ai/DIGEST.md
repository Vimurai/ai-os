# DIGEST — AI-OS v2 (Updated: 2026-09-07)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.
- **D-054 (2026-09-04): the same-provider Triad is a SUPPORTED topology.** Both roles may run on one provider in separate tmux panes; role identity binds PER PANE at launch via `ai pane <role>`, never per project.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI pins Node 22), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect: currently bound to **claude** (`.ai/roles.json`), pane 1. D-053 + `structured-outputs.md §32` were ratified 2026-07-31 (closed). Ruled D-055, D-056, D-057 (2026-09-07) → E-216..E-223, all shipped.
- Engineer (Claude): shipped the entire **D-054 sprint (E-208..E-215, 8 tasks)** — merged to `master` and pushed. Queue EXHAUSTED (0 open).
- Tester: bash suite now 114 files, **3403 assertions, 0 failing**.

## Current Focus
- D-054..D-057 sprints COMPLETE (E-208..E-223). The Engineer queue is empty. Next Architect input needed on: **T-LOCATOR-001 residual** — four SKILL.md files still resolve framework helpers cwd-relative, including an auto-executed line in `ai-preflight`, which runs at every session start; outside D-057 §3's scope so not fixed under E-223, and it needs funding. Also **T-PROPOSEPATCH-002** (preview/list/reject read unbounded stored paths) and a ruling on the **`--dev-tree` deviation** (D-057 §3 names an env var as the dev-tree rollback; the env is the attack channel, so the capability moved to argv).

## Key Decisions
- D-057: Fund the patch project boundary; name shared helpers in architect.md §4; make run_review's PATH_TRAVERSAL context-aware; install-first helper locators across all hooks.
- D-056: Shell write-gate widening FROZEN (over-block ratio governs, `arch-write-cases.json` is the contract); fund patch-mcp fail-closed role derivation + manifest-scoped sync pruning.
- D-055: Widen the Architect write gate to shell writes; rename the colliding role skills; stamp waiver only from a verified record.
- D-054: All-Claude Triad SUPPORTED — role identity binds PER PANE at launch, never per project.
- D-052: Retain Vendor-Named Provider Directories (cancel E-188 Part 2 rename).
- D-051: Ratify E-183 Shim Approach for Legacy CLI Loaders (keep CLAUDE.md/GEMINI.md as @import shims).
- D-050: Decouple Triad persona from CLI tools → ENGINEER.md/ARCHITECT.md, defaults agy=Architect / claude=Engineer.
- D-049: Ratify E-180 telemetry schema migration (REJECTED/TIMEOUT status enum).

## Known Risks
- **Architect write gate: shell widening is FROZEN (D-056 R3).** E-216 widened it to shell writes across three layers (native hook → `analyzeArchitectWrites` → `permissions.deny`), and the residual over-block was ACCEPTED. `tests/fixtures/arch-write-cases.json` is now the contract and the over-block ratio governs: further widening needs a new ruling, not a patch.
- **`confirm_patch` project boundary (T-PROPOSEPATCH-001, FUNDED → E-221 per D-057).** `propose_patch` stores an ABSOLUTE path resolved against the proposing cwd; `confirm_patch` writes to it without re-running `safePath` against its own. Confirming from a different project lands the write outside that project. Not a role escape — the role is re-derived (E-219) — the gap is the project boundary. Predates E-219; filed as its own entry rather than as a residual.
- ~~Skill-name collision (E-212)~~ — CLOSED by E-217 (renamed to `arch-task`/`arch-oracle`, collision now a hard sync error) and E-220 (the renamed-away leftovers are pruned rather than lingering forever).
- **Git Lane residual risk (E-214)** — recorded as `THREAT_MODEL.md` T-GITLANE-001: `git commit --amend` escapes the scope check; the E-129 record is selected by an unauthenticated `CLAUDE_CODE_SESSION_ID`; `--no-verify`/`merge`/`cherry-pick` bypass the hook (items 1–3 ACCEPTED by D-055 R4); ~~the stamp waiver reachable by a non-Architect~~ FIXED by E-218 (waiver requires the verified record).
- **Mint guard is partial (E-208).** It enforces "a valid binding may not be changed", not immutability — deleting or corrupting the record and minting fresh still works. ACCEPTED by D-055 R5 (deletion from an Architect pane is E-102-gated); boot-id/ledger binding is backlog.
- **Helper locators resolve the USER's repo first (E-220 finding, FUNDED → E-223 per D-057).** All six `hooks/*.sh` still carry the `git rev-parse --show-toplevel` dev-tree-first chain; a downstream project could plant an executable helper until E-223 lands.
- ~~`seo_engineer.md` missing `context:` key~~ — FIXED by E-217.
- ~~`advisor-mcp` env allowlist / "PATH + HOME suffice"~~ — FIXED: E-210 keeps `USER`; `role-abstraction.md §Security` amended per D-055 (allowlist = `PATH`, `HOME`, `USER` + `child_env_keep`).
## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-09-07: **E-223** install-first helper locators (Tier 3, 4 audit rounds). Pre-fix hooks executed a decoy repo's `safe-exec-mcp/index.js` three times from one session in that directory. Two of the four rounds found holes the FIX introduced.
- 2026-09-07: **E-222** `run_review`'s PATH_TRAVERSAL is context-aware — a `../` anchored to a script-relative base is P1 advisory, everything else stays P0; `AI_OS_REVIEW_STRICT_TRAVERSAL=1` restores the flat regex.
- 2026-09-07: **E-221** patch project boundary + diff-target validation (Tier 3, SEC_CLEARED after 3 rounds); T-PROPOSEPATCH-001 FIXED, -002/-003 filed.
- 2026-09-07: **E-220** manifest-scoped `ai sync` pruning — a path is removed only if sync wrote it, nobody edited it, and it is gone upstream; everything else is reported as `orphan (kept)`. Also fixed three `git rev-parse`-based helper locators (E-208/E-212/E-220) that resolved the USER's repo instead of the install.
- 2026-09-07: **E-219** server-side role derivation for patch-mcp/propose-patch-mcp (Tier 3, SEC_CLEARED after 2 rounds); omitting `caller_role` no longer means "unrestricted". T-PATCHMCP-001 FIXED.
- 2026-09-07: **E-216/E-217/E-218** Architect write gate widened to shell writes (Tier 3, 7 audit rounds); `arch-task`/`arch-oracle` rename + collision guard; stamp waiver now requires a verified role record.
- 2026-09-07: **E-213** Architect overlay allow rules + provider-aware owner/Actor labels; legacy `Bash(gemini -p *)` dropped and pruned.
- 2026-09-07: **E-215** ARCHITECT.md runtime ladder (Skill tool → run_preflight → activate_skill) + `ai doctor` per-role provisioning report.
- 2026-09-07: **E-214** Architect-scoped Git Lane (Tier 3, SEC_CLEARED after a blocking fail-open was found and fixed) + `safe-exec --verify-role`.
- 2026-09-06: **E-212** role manifest in `registry.json` + role-aware `do_sync`; a Claude Architect now gets 47 skills / 20 agents (was 35 / 13).
- 2026-09-05: **E-208** per-pane role binding: `ai pane <role>`, launch-time role mint, `[AI_OS_ROLE]` stamp, Role Resolution clause, Write/Edit sovereignty gate (Tier 3, SEC_CLEARED after 3 audit rounds).
- 2026-09-04: **E-210** provider-aware `advisor-mcp` bridge + shared `provider-adapter.mjs`; **E-211** legacy provider targets deprecated, ambiguity fails closed.
- 2026-09-04: **E-209** `resolve_pane` precedence — roles.json ordinal before fuzzy title for semantic targets (fixed a live handoff misroute).
- 2026-09-04: **D-054** ratified; `.ai/roles.json` architect provider agy → claude.
