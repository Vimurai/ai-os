# DIGEST — AI-OS v2 (Updated: 2026-09-09)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `agy`) + Lead Engineer (default `claude`/Claude Opus 4.8) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.
- **D-054 (2026-09-04): the same-provider Triad is a SUPPORTED topology.** Both roles may run on one provider in separate tmux panes; role identity binds PER PANE at launch via `ai pane <role>`, never per project.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI = `.github/workflows/test.yml` on ubuntu-latest/Node 22, two jobs (`test` + `unit` node:test with coverage), GNU patch 2.7.6, Playwright browsers installed in an explicit CACHED step — **GREEN on master since 2026-09-09, E-230**), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect: currently bound to **claude** (`.ai/roles.json`), pane 1. D-053 + `structured-outputs.md §32` were ratified 2026-07-31 (closed). Ruled D-055, D-056, D-057 (2026-09-07) → E-216..E-223, all shipped.
- Engineer (Claude): shipped **D-059 (E-227, E-228)**, **D-060 (E-229..E-233)** and **D-061 (E-234..E-237)** — 11 tasks, PRs #36-#44, all merged. Queue EXHAUSTED (0 open).
- Tester: bash suite now **132 files, 4416 assertions, 0 failing** (CI, PR #44). SKIP is a distinct outcome since E-236 — an unmet OPTIONAL requirement is counted separately and never as a pass.

## Current Focus
- **Queue exhausted.** D-061 (E-234 → E-237 → E-236 → E-235) shipped 2026-09-09; DIGEST refreshed as its final step.
- **Master is green and CI is now believable.** It had been RED and unnoticed 2026-09-07 → 2026-09-09 while three
  sprints were told to "verify on CI". Root cause of the blindness: nobody looked, and the README carried a
  HARDCODED `tests-passing` badge. Both fixed — live workflow badge, and `ai-task` injects master's CI conclusion
  and refuses to call work verified on a local run alone.
- **The recurring defect of this sprint was ENVIRONMENT-DEPENDENT TESTS** — five found, three of them written by
  the Engineer during the sprint itself. Each passed on a developer Mac and failed on CI: a `~/.ai-os` mirror in a
  pre-strip state, BSD-vs-GNU `ls` exit codes, an unpruned `node_modules` corpus scan, an ambient tmux server, an
  inherited `AI_OS_CALLER_ROLE`. E-236 turned this into a standing review question in `critic_tests` and
  `ai-review`, with BOTH remedies recorded (supply the dependency when accidental; skip only when genuinely
  optional).

### Open for the Architect
- **Performance budgets are host-SPEED dependent** and have no ruling. `incident_aggregator` ("under 200ms",
  measured 381ms) and `telemetry` ("hook warm-path under 250ms") fail on the Engineer's machine — where
  `node -e 'process.exit(0)'` alone costs ~197ms — while passing on CI (20/20, 95/95). Verified against clean
  master in a separate worktree, so this is not sprint fallout. It is the E-236 category one step further:
  not "what the machine has" but "how fast it is".
- **`git stash` cost an incident.** A conflicted `stash pop` left conflict markers in `.ai/state.json`, which the
  Engineer staged and committed to master (`44243bc`) without opening the file — git had said the stash was kept.
  Master carried invalid JSON until `4a4b301`. The two CI failures that exposed it (`resilience` T-RES-14,
  `managed_agents_spike`) were REAL and were nearly dismissed as flakes. Worth a rule: bookkeeping moves between
  branches via commit + cherry-pick, never stash.

## Key Decisions
- D-061: Program-position rule (arguments are not programs); E-232 denylist + E-231 depth-1 cap RATIFIED; Playwright out of the default install; environment-dependence review question + SKIP helpers; hot-reloaded policy modules in long-running MCP servers.
- D-060: CI EXISTS and was red — make master green + node:test job + `ai-task` shows CI before DONE; operand re-tokenisation; skill consent (`!`-lines never run project programs); gitignore the sync manifests.
- D-059: `ai start` one-command Triad launcher (E-227) + its `--status`/`--kill`/doctor surface (E-228).
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
- **Helper locators (T-LOCATOR-001).** Hooks + `src/bin/ai` FIXED by E-223 (install-first resolver, hooks ignore env). **Skills half still OPEN until E-225**: four SKILL.md chains are cwd-relative, including the auto-executed `ai-preflight` line — do not run preflight inside untrusted checkouts until it lands.
- **Read-only patch tools (T-PROPOSEPATCH-002, FUNDED → E-226 per D-058).** `preview`/`list`/`reject` still read or expose unbounded stored paths; narrowed post-E-221 to legacy rows and the proposer's own reach.
- **Verification limits.** No sandboxed pen-test ran in the last eight audit rounds (Docker down) and all `patch` testing was on Apple patch 2.0, not CI's GNU 2.7.x — confirm the E-221 driver modes on CI after the merge.
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
