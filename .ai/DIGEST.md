# DIGEST — AI-OS v2 (Updated: 2026-09-10)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `claude` on `fable`, D-066) + Lead Engineer (default `claude` on `opus`) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.0.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.
- **D-054 (2026-09-04): the same-provider Triad is a SUPPORTED topology.** Both roles may run on one provider in separate tmux panes; role identity binds PER PANE at launch via `ai pane <role>`, never per project.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI = `.github/workflows/test.yml` on ubuntu-latest/Node 22, two jobs (`test` + `unit` node:test with coverage), GNU patch 2.7.6, Playwright browsers installed in an explicit CACHED step — **GREEN on master since 2026-09-09, E-230**; a run that LEAKS external state also fails CI (E-240)), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect: currently bound to **claude** (`.ai/roles.json`), pane 1. Ruled D-054..D-064 (2026-09-04 → 2026-09-10) → E-208..E-241. **All shipped.**
- Engineer (Claude): shipped **D-059** (E-227, E-228), **D-060** (E-229..E-233), **D-061** (E-234..E-237), **D-062** (E-238, E-239), **D-063** (E-240) and **D-064** (E-241) — 15 tasks, PRs #36-#48, all merged. Queue EXHAUSTED (0 open).
- Tester: bash suite now **135 files, 4514 assertions, 0 failing** (CI, PR #48). Three outcomes, not two: PASS / FAIL / **SKIP**, an unmet OPTIONAL requirement counted separately and never as a pass (E-236). A run also reports `LEAKED n <kind>` per suite and `CLEANUP n handlers` on exit — the last run was **LEAKED 0 with 43 CLEANUP**, and a leak FAILS the run on CI (E-240/E-241).

## Current Focus
- **Queue exhausted.** D-064 (E-241) shipped 2026-09-10. Master `9362e2b`, CI green, `verify_markdown_sync` [SYNC_PASS].
- **The whole of D-060..D-064 was one theme: make the harness tell the truth.** CI had been
  RED and unnoticed for two days while three sprints were told to "verify on CI", because
  nobody looked and the README carried a HARDCODED `tests-passing` badge. What that
  exposed, and what the five sprints since have systematically removed, is a family of
  tests and gates that REPORTED something other than what they measured.

### The four varieties of "the test measured something else", each now closed
| Variety | Example that shipped green and was wrong | Closed by |
|---|---|---|
| what the machine HAS | a `~/.ai-os` mirror only a pre-strip laptop had; BSD-vs-GNU `ls` exit codes; an inherited `AI_OS_CALLER_ROLE` | E-236 — review question + `skip_unless_*`, SKIP counted separately |
| how fast it IS | `incident_aggregator` "under 200ms" measured 381ms on a laptop, passed on CI | E-239 — absolute on CI, ratio-to-baseline elsewhere, BOTH numbers printed |
| what a previous run LEFT | 50 leaked tmux servers; `$$` socket names recycling onto them | E-240 — `register_cleanup` before create, per-suite leak diff, `--sweep` |
| a cleanup that never RAN | 42 suites whose own `trap … EXIT` silently replaced the registry | E-241 — `trap` shadowed to CHAIN; `CLEANUP n` proves handlers fired |

- **Gates that cannot cry wolf.** `run_review` no longer reports a phantom P0 (E-237
  hot-reloads policy modules; a server spawned before a policy change was serving a stale
  verdict all sprint). Conflict markers and unparseable `.ai/*.json` cannot reach a commit
  (E-238) — verified by replaying the real corrupted blob from `44243bc`, which master
  carried as invalid JSON for four commits.
- **A method, not a habit.** Across D-062..D-064 not one defect was found by reasoning.
  Every one surfaced because a probe printed evidence that contradicted a plausible theory:
  the phantom P0, the `stat -f`/`-c` output leak (twice), a `| tee` that reported 17
  failures as a green job, the committed conflict markers, the leaked sockets, a caching
  helper that cached nothing, and a `BASHPID` guard that does not exist in bash 3.2.
  Instrumentation first, theory second.

### Open for the Architect
- **Nothing outstanding.** The two items last recorded here — host-speed performance budgets
  and the `git stash` incident — were ruled (D-062) and shipped (E-239, E-238).
- **D-065 ratified both** and generalised them: a false positive is silenced by an
  explicit, greppable `# standards:allow-<rule_id>` marker — never by loosening a pattern,
  which reduces coverage everywhere; a file outside a rule is exempted BY NAME next to the
  rule — never by narrowing scope, which drops files that should stay covered. It adds
  **fixture-first for gate code**: standards rules, hooks and harness primitives get the
  failing fixture before the implementation, run on both bash 3.2 and CI's shell. That last
  clause is aimed squarely at E-241, where a `BASHPID` guard would have behaved differently
  on the two shells.

## Key Decisions
- D-065: Suppressions are explicit and greppable, exemptions are by name; fixture-first for gate code, verified on both bash 3.2 and CI's shell.
- D-064: EXIT-trap chaining (a raw `trap … EXIT` in a suite replaced the cleanup registry); subshell-state institutionalised as review question #4 — a helper returns DATA or sets STATE, never both. No lint funded (over-block risk).
- D-063: The telemetry baseline strengthening ratified and generalised — a perf baseline includes the assertion's OWN instrument; leaked external state is the third environment dependence.
- D-062: Program-position resolution ratified; no-stash bookkeeping + conflict-marker/JSON pre-commit gate + presume-real triage; host-relative performance budgets.
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
