# DIGEST — AI-OS v3.1.0 (Updated: 2026-09-10)

## Product
- Autonomous OS for AI coding agents — a provider-agnostic **Triad**: Principal Architect (default `claude` on `fable`, D-066) + Lead Engineer (default `claude` on `opus`) + Tester (TestSprite), coordinated via ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, Multimodal RAG, cross-project meta-cognition telemetry, SEO Topic Cluster Engine, Sovereignty Hardening, and the tmux Interactive Bridge (`ai watch` ping-pong loop). Runtime v3.1.0; agent plugin `ai-os` v2.0.0.
- Roles are decoupled from the CLI vendor (D-050): canonical rulefiles **ENGINEER.md** / **ARCHITECT.md**; `CLAUDE.md`/`GEMINI.md` survive as load-bearing `@import` bootstrap shims.
- **D-054 (2026-09-04): the same-provider Triad is a SUPPORTED topology.** Both roles may run on one provider in separate tmux panes; role identity binds PER PANE at launch via `ai pane <role>`, never per project.

## Stack
- Node.js 22.5+ (MCP servers, node:sqlite DatabaseSync, ESM, fetch; CI = `.github/workflows/test.yml` on ubuntu-latest/Node 22, two jobs (`test` + `unit` node:test with coverage), GNU patch 2.7.6, Playwright browsers installed in an explicit CACHED step — **GREEN on master since 2026-09-09, E-230**; a run that LEAKS external state also fails CI (E-240)), Python 3.10+ fallbacks, SQLite3 + WAL, Bash, Docker (sandbox), npm workspaces, Gemini Embedding 2, Managed Agents 2026-04-01.

## Triad Health
- Architect: currently bound to **claude** (`.ai/roles.json`), pane 1. Ruled D-054..D-064 (2026-09-04 → 2026-09-10) → E-208..E-241. **All shipped.**
- Engineer (Claude): shipped **D-059** (E-227, E-228), **D-060** (E-229..E-233), **D-061** (E-234..E-237), **D-062** (E-238, E-239), **D-063** (E-240) and **D-064** (E-241) — 15 tasks, PRs #36-#48, all merged. Queue EXHAUSTED (0 open).
- Tester: bash suite now **135 files, 4514 assertions, 0 failing** (CI, PR #48). Three outcomes, not two: PASS / FAIL / **SKIP**, an unmet OPTIONAL requirement counted separately and never as a pass (E-236). A run also reports `LEAKED n <kind>` per suite and `CLEANUP n handlers` on exit — the last run was **LEAKED 0 with 43 CLEANUP**, and a leak FAILS the run on CI (E-240/E-241).

## Current Focus
- **v3.1.0 released 2026-09-10** — the Same-Provider Triad arc, 38 tasks (E-208–E-245) closing D-054 through D-066. CI green, `verify_markdown_sync` [SYNC_PASS], full suite 4518 passed / 0 failed / 33 skipped.
- **D-066 completed the topology.** The all-Claude Triad is now the DEFAULT (`architect = claude:1` on `fable`, `engineer = claude:0` on `opus`); `agy` and `gemini` remain selectable providers. Role labels are DERIVED from `roles.json` everywhere — the init banner, the task-owner regex and the review footer each used to hard-code a vendor name, so an all-Claude project stamped its Architect-owned tasks with a vendor no role was bound to. Provider workspaces now follow the binding: `.gemini/` and `.agents/` are provisioned only when a role uses them, and this repository no longer carries either.
- **The D-060..D-064 theme — make the harness tell the truth — held through this sprint too.** Every defect below was found by INSTRUMENTATION, not by reading the code.

### The four varieties of "the test measured something else", each now closed
| Variety | Example that shipped green and was wrong | Closed by |
|---|---|---|
| what the machine HAS | a `~/.ai-os` mirror only a pre-strip laptop had; BSD-vs-GNU `ls` exit codes; an inherited `AI_OS_CALLER_ROLE` | E-236 — review question + `skip_unless_*`, SKIP counted separately |
| how fast it IS | `incident_aggregator` "under 200ms" measured 381ms on a laptop, passed on CI | E-239 — absolute on CI, ratio-to-baseline elsewhere, BOTH numbers printed |
| what a previous run LEFT | 50 leaked tmux servers; `$$` socket names recycling onto them | E-240 — `register_cleanup` before create, per-suite leak diff, `--sweep` |
| a cleanup that never RAN | 42 suites whose own `trap … EXIT` silently replaced the registry | E-241 — `trap` shadowed to CHAIN; `CLEANUP n` proves handlers fired |

### The fifth variety, found during E-244: the scan that never ran
`skill_consent`, `program_position` and `operand_retokenise` each built their corpus with
`find src .claude .agents .gemini`. Once E-244 stopped provisioning two of those roots,
`find` exited non-zero, `execSync` threw, and the corpus came back **empty** — and a scan of
zero files reports zero violations. All three would have gone on printing "no findings" for
a scan that never happened. The only thing that caught it was the file-count assertion each
suite already carried, added when this same shape bit before. **A rule-scanning test must
assert how much it scanned, not only what it found.**

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
- **`do_sync`'s second half is UNREACHABLE (found E-244, NOT fixed — needs a ruling).** An early `return 0` added in E-217 to fix the exit status sits before the hook install, the `mcp.md` and blueprint-index regeneration, the WAL checkpoint, `REPO_MAP`, the Memory Palace index, the E-233 generated-artefact `.gitignore` and the E-237 policy-staleness report. None of them has run on `ai sync` since, and the command never prints "Done." Restoring the tail is NOT cosmetic: a trial restore made `ai sync` **exit 1 under `set -e`** in a fixture whose output was captured with `2>&1`. Recorded at both ends of the dead region and pinned by `provider_workspace_test.sh` E-244.09 so it cannot be tidied away silently.
- **`strip_gemini_agent_fields` runs against the INSTALL MIRROR (found E-244, NOT fixed — needs a ruling).** `ai install` strips `disable-model-invocation`, `user-invocable` and `allowed-tools` from `~/.ai-os/gemini/agents/` in place; E-212's role-aware provisioning then copies that stripped mirror into `.claude/agents/`. A Claude Architect therefore loses those keys — degrading precisely the configuration D-066 just made the default. `src/gemini/agents/` is intact, so the repair is an install-path change plus a re-install.
- **The installed mirror lags the working tree, and tests can be written against either.** `role_provisioning_test.sh` E-212.06f invoked `${HOME}/.ai-os/bin/ai` for a BEHAVIOURAL assertion, so it tested whichever release was last installed: it passed on the Engineer's laptop and failed on CI, where `ai install` runs from HEAD. Fixed in E-244 (it now runs the working tree's `ai`), and it was the only such site — but the same trap caught E-243 (`ai init` copies its template from the mirror) and E-245 (`verify_markdown_sync` regenerates through the mirror's projector). **Finishing a task that touches `src/mcp/shared` or `src/bin` includes `bash install-ai-os.sh`.**
- **A running MCP server keeps serving the code it BOOTED with, even after `ai install`.** ESM caches modules for the life of the process, so `update_task_status` regenerated `TASKS.md` through the pre-E-245 projector and silently dropped the archive pointer that had just been committed — twice, before the cause was clear. E-237 solved exactly this for the four POLICY modules and says plainly that a server started earlier must be restarted; the notice that would have told an operator is `_report_policy_staleness`, which sits in the unreachable half of `do_sync` (first risk above). Restart the servers, or the session, after installing.
- **D-065's carried instruction is still outstanding.** The suppression-count summary for the standards checker was to land in the next task touching that file. Neither E-244 nor E-245 does, so it is flagged forward rather than bolted onto an unrelated change.
- **Architect write gate: shell widening is FROZEN (D-056 R3).** E-216 widened it to shell writes across three layers (native hook → `analyzeArchitectWrites` → `permissions.deny`), and the residual over-block was ACCEPTED. `tests/fixtures/arch-write-cases.json` is now the contract and the over-block ratio governs: further widening needs a new ruling, not a patch.
- ~~`confirm_patch` project boundary (T-PROPOSEPATCH-001)~~ — CLOSED by E-221: `propose_patch` records its own project root and a project-relative target, so confirming from a different project can no longer land the write outside it.
- ~~Skill-name collision (E-212)~~ — CLOSED by E-217 (renamed to `arch-task`/`arch-oracle`, collision now a hard sync error) and E-220 (the renamed-away leftovers are pruned rather than lingering forever).
- **Git Lane residual risk (E-214)** — recorded as `THREAT_MODEL.md` T-GITLANE-001: `git commit --amend` escapes the scope check; the E-129 record is selected by an unauthenticated `CLAUDE_CODE_SESSION_ID`; `--no-verify`/`merge`/`cherry-pick` bypass the hook (items 1–3 ACCEPTED by D-055 R4); ~~the stamp waiver reachable by a non-Architect~~ FIXED by E-218 (waiver requires the verified record).
- **Mint guard is partial (E-208).** It enforces "a valid binding may not be changed", not immutability — deleting or corrupting the record and minting fresh still works. ACCEPTED by D-055 R5 (deletion from an Architect pane is E-102-gated); boot-id/ledger binding is backlog.
- ~~Helper locators (T-LOCATOR-001)~~ — CLOSED. Hooks + `src/bin/ai` by E-223 (install-first resolver, hooks ignore env); the four cwd-relative SKILL.md chains, including the auto-executed `ai-preflight` line, by E-225; and the operand class the rule could not see by E-231.
- ~~Read-only patch tools (T-PROPOSEPATCH-002)~~ — CLOSED by E-226: `preview_patch`, `list_pending_patches` and `reject_patch` no longer read or expose an unbounded stored path.
- **Verification limits.** No sandboxed pen-test ran in the last eight audit rounds (Docker down) and all `patch` testing was on Apple patch 2.0, not CI's GNU 2.7.x — confirm the E-221 driver modes on CI after the merge.
- ~~`seo_engineer.md` missing `context:` key~~ — FIXED by E-217.
- ~~`advisor-mcp` env allowlist / "PATH + HOME suffice"~~ — FIXED: E-210 keeps `USER`; `role-abstraction.md §Security` amended per D-055 (allowlist = `PATH`, `HOME`, `USER` + `child_env_keep`).
## MCP Servers (25)
- State: task-synchronizer, orchestrator, archive-manager, memory, memory-manager
- Code: filesystem, lsp, patch, propose-patch, ast-parser | Safety: safe-exec, context-guardian, risk-analyzer, verification
- Intelligence: context-invoker, blueprint-aligner, github-bridge, token-budget | Quality: TestSprite, vibe-check, computer-use
- Interop: advisor, approval | Caching: cache-manager | Compute: code-execution | Routing: mcp-router

## Recent Changes (last 10)
- 2026-09-10: **E-246** v3.1.0 released — CHANGELOG aggregated for D-054..D-066 / E-208..E-245, version bumped across `package.json`, `src/bin/ai`, `install-ai-os.sh` and the README badge. Note recorded in the CHANGELOG: `3.0.0` was carried in `package.json` but never tagged or changelogged, so the 2.0.0 → 3.0.0 range remains undocumented there.
- 2026-09-10: **E-245** repo hygiene — the stray tracked root file `bash` (30 bytes of `bash: 11: Bad file descriptor`) removed, `.DS_Store` ignored at every depth, 117 DONE tasks and 228 stamps archived (TASKS.md 261 → 25 lines). Added `archivePointerLines`, because the rotation had left a view showing ten completed tasks with nothing to say that 117 more existed or where. It is emitted by BOTH TASKS.md projectors from one shared helper — a pointer only one of them writes is deleted the next time the other regenerates.
- 2026-09-10: **E-244** provider workspaces follow the role binding — mapped-only provisioning with announced skips, `ai doctor` stale report, explicit `ai sync --prune-providers` (48 of 50 files removed here on evidence, 2 listed and removed by hand). 81 mirror-parity assertions across 16 suites converted to assert-if-present / SKIP rather than deleted. Also fixed `ai init` exiting 128 in a non-git directory.
- 2026-09-10: **E-243** the all-Claude Triad is the DEFAULT (claude·fable / claude·opus). The real change is that role labels are DERIVED from `roles.json`, not literal: six assertions across five suites had hard-coded `agy` as the Architect, which is the measure of how far one vendor name had spread.
- 2026-09-10: **E-242** `ai start` overlay paths are absolute at the seam. A relative `--settings` was a loud failure; a relative rulefile flag was a SILENT one — it produced the wrong persona rather than an error, which is gap G1 itself.
- 2026-09-09: **E-241** `trap` shadowed for EXIT so suite handlers CHAIN instead of replacing the cleanup registry; 42 raw sites converted; `CLEANUP n` printed so "it cleaned up" and "there was nothing to clean" stop looking identical.
- 2026-09-09: **E-240** leaked-state hygiene — `register_cleanup` BEFORE the resource exists (a trap installed after it has a window, and that window is exactly where failures happen), per-suite leak diff, `--sweep`.
- 2026-09-09: **E-239** performance budgets are host-relative — absolute on CI, ratio-to-baseline elsewhere, both numbers printed every run. Pins BOTH opposing properties: the real 381ms incident passes on a slow host, and the same elapsed on a fast one still fails.
- 2026-09-09: **E-238** no-stash bookkeeping rule + pre-commit conflict-marker and `.ai/*.json` parse gate, verified by replaying the real incident's blob (44243bc), and the over-block guard verified against this repo's own prose, which quotes the markers it documents.
- 2026-09-09: **E-237** policy hot-reload on mtime change; verified END TO END with a live `run_review` picking up a rewritten policy module. Its own staleness report carried an unquoted `printf` that word-split every server name — shipped, and never seen, because its only call site sits in unreachable code (see Known Risks).
