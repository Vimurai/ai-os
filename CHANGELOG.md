# Changelog

All notable changes to **ai-os-v2** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); this project adheres to [Semantic Versioning](https://semver.org/).

## [3.1.0] — 2026-09-10

The **Same-Provider Triad** arc: one vendor can now hold both roles, the Architect is a
first-class runtime rather than a second CLI, and the harness stopped reporting work it had
not actually done. 38 tasks (E-208–E-245) closing D-054 through D-066.

> **Note on 3.0.0.** `package.json` has carried `3.0.0` since the v3.0 hardening sweep, but
> that version was never tagged and never changelogged. This entry covers E-208 onward only;
> the 2.0.0 → 3.0.0 range remains undocumented here, and its record is in `.ai/LOG.md`.

### Added

- **Per-pane role binding** (E-208, Tier 3) — `ai pane <role>` binds a pane to a role, the
  SessionStart hook stamps `[AI_OS_ROLE]`, and the rulefiles resolve the resulting conflict
  deterministically. Closes gap G1: a second Claude pane bound to the Architect no longer
  boots the Engineer persona out of `CLAUDE.md`.
- **`ai start`** (E-227, E-228) — creates or reuses the project's tmux session and opens the
  Triad layout, with `--status` (panes, roles, watcher state), `--kill`, `--detach` and
  `--dry-run`.
- **All-Claude Triad as the default** (E-243) — `architect = claude:1` on `fable`,
  `engineer = claude:0` on `opus`. `agy` and `gemini` remain fully selectable. Role labels
  are now **derived from `roles.json`** in the init banner, the task-owner regex and the
  review footer, all three of which previously hard-coded a vendor name.
- **Mapped-only provider workspaces** (E-244) — `ai sync` provisions `.claude/`, `.gemini/`
  and `.agents/` only for providers a role is bound to; `ai doctor` reports the others as
  stale; `ai sync --prune-providers` removes them under manifest and byte-identity evidence,
  keeping and listing anything it cannot prove disposable. `.claude/` is never pruned.
- **Continuous integration** (E-230) — the repository had none, while `DIGEST.md` claimed
  "CI pins Node 22" and the README carried a hardcoded passing badge. Adds the `test` and
  `unit` jobs, a log artifact, and a cached Playwright step.
- **Policy hot-reload** (E-237) — `loadPolicy()` re-imports a policy module when its mtime
  changes, so a long-running MCP server stops serving verdicts from the version it booted
  with. `ai sync` names servers older than the mirror.
- **Test-harness hygiene** — SKIP as a distinct outcome with its own accounting (E-236),
  host-relative performance budgets (E-239), leaked-state detection and `--sweep` (E-240),
  and EXIT-trap chaining so a suite's own `trap` no longer silently disables cleanup (E-241).
- **Archive pointer** (E-245) — rotated task history stays findable from the generated
  `TASKS.md` view.

### Changed

- **Role-aware provisioning** (E-212, E-213, E-215) — source directories are selected by the
  roles a provider serves rather than by vendor name, so a single-vendor Triad gets both
  roles' skills and agents. `ARCHITECT.md` is runtime-aware and `ai doctor` reports per-role
  provisioning.
- **Architect-scoped Git Lane** (E-214, E-218, Tier 3) — the Architect may commit its own
  `.ai/` and `plans/` work, with the stamp waiver restricted to that lane.
- **Write-gate coverage widened** (E-216, Tier 3) — the Architect gate now covers every write
  path, not only `Write` and `Edit`.
- **Server-side role derivation** (E-219, E-221, E-226, Tier 3) — `patch-mcp`,
  `propose-patch-mcp` and their callers derive the caller's role server-side and fail closed
  to `architect` instead of trusting a client-supplied value; `propose_patch` records its own
  project root.
- **Install-first helper locators** (E-223, E-225) — one shared resolver, so a helper is
  found relative to the install rather than the current working directory.
- **Executable-markdown classifier** (E-224) and the **program-position rule** (E-234) — a
  token counts as a program only in program position; data extensions never do.
- **Skill consent** (E-232) — an auto-executed line in a skill or agent file may no longer
  invoke a project program without consent.
- **Manifest-scoped pruning** (E-220) — `ai sync` removes only what it wrote and nobody has
  edited, and reports everything else as an orphan it kept.
- **Playwright out of the default install** (E-235) — opt-in via `ai mcp-setup --browsers`,
  bounded by a watchdog, with `[BROWSER_MISSING]` surfaced at first use.
- **`ai-watch` survives `ai sync`** (E-229) — a watcher no longer keeps running a script that
  has been rewritten underneath it.

### Fixed

- **`ai start` could not find an overlay that existed** (E-242) — the adapter emitted
  project-relative settings paths, which resolved only when the CLI's cwd happened to be the
  project root. Worse silently: a relative rulefile flag produced the **wrong persona**
  rather than an error. Paths are now absolute at the seam, and a missing overlay self-heals.
- **`ai init` exited 128 in a non-git directory** (E-244) — a plain assignment carried
  `git rev-parse`'s exit status under `set -e` and killed the script three lines above the
  branch written to handle exactly that case.
- **Conflict markers and unparseable `.ai/*.json` could reach a commit** (E-238) — a
  pre-commit gate now blocks both, without rejecting prose that quotes a marker or a Markdown
  setext underline.
- **Context-aware path-traversal check** (E-222) — `run_review` stopped reporting P0s for
  legitimate paths.
- **Deprecated legacy provider targets** in `ai-watch` pane resolution (E-209, E-211) and
  **provider-aware `ask_architect`** (E-210).
- **Skill-name collisions** between role variants resolved by renaming (E-217: `arch-task`,
  `arch-oracle`, `arch-review`).
- **Sync manifests gitignored** (E-233).

## [2.0.0] — 2026-06-05

First formal tagged release. Marks completion of the **Sovereignty Hardening** and
**Interactive Bridge** arcs. The major version reflects breaking, fail-closed
changes to `safe-exec` command enforcement (see **Changed → BREAKING**).

### Added
- **Interactive Bridge — smart delivery** (E-124): persistent `delivered`-flag
  consumption, startup backlog drain, per-target independent FIFOs, single-writer
  lock, and delivered-aware queue eviction so Architect⇄Engineer handoffs are
  never dropped or replayed across restarts.
- **safe-exec fail-closed pre-execution gate** (E-125, Tier 3): a `PreToolUse`
  hook routes every Bash command through `safe-exec --check` and blocks (exit 2)
  any `BLOCK` verdict — turning analysis from advisory into enforcing
  (THREAT_MODEL T-HITL-004), with a pure-bash backstop when node is unavailable.
- **Context Cache prompt-prefix injection** (E-126): a `SessionStart` hook injects
  the compiled System Context blob as session context (`caching.md` §3).
- **Bootloader `caller_role` injection** (E-127): `ai install` writes the Triad
  role into each agent's settings; `safe-exec` trusts it over the agent-supplied
  argument (anti-impersonation).
- **Tamper-resistant role token** (E-129, Tier 3): the gate resolves the role from
  an HMAC-signed per-session token, so an in-session `unset/export
  AI_OS_CALLER_ROLE` can no longer self-downgrade.
- New CLIs/flags: `safe-exec --check` / `--mint-token`, `ai watch --clear`,
  `cache-manager --emit-context`, `AI_WATCH_SUBMIT_DELAY`.

### Changed
- **BREAKING (E-123):** for the Architect role, `safe-exec` now blocks
  branch/remote git ops (`merge`, `rebase`, `push`, `pull`, `branch`) and
  deployment commands (`ssh`, `rsync`, `scp`, `npm publish`, `docker push`) —
  merge and deployment are strictly Engineer tasks.
- **BREAKING (E-125):** catastrophic commands (`rm -rf /`, `curl … | bash`,
  fork bombs, `mkfs`, `dd … of=/dev/*`) are now prevented at the gate, not merely
  flagged.
- **BREAKING (E-128):** the `--check` analyzer-error path is fail-closed — an
  internal analyzer crash blocks execution (exit 2) instead of allowing it.
- Hardened `rm -rf` detection: split `rm -r -f`, and `$HOME`/`${HOME}`/`~`/`/*`
  targets (E-125).
- Formalized the ai-watch busy-gate version-string heuristic and made the
  pre-Enter submit delay configurable (E-122).

### Fixed
- ai-watch `Ctrl-C` now reliably terminates the watcher (trap regression) (E-124).
- Dropped / stale Interactive Bridge handoffs resolved by the smart delivery model
  (E-122, E-124).
- Workflow task lifecycle and ai-watch pane routing verified end-to-end
  (E-120, E-121).

### Rollbacks
Every new enforcement layer is reversible via environment flags:
`AI_OS_SAFE_EXEC_GATE=0`, `AI_OS_ROLE_TOKEN=0`, `AI_OS_SOVEREIGNTY_LOCK=0`,
`AI_WATCH_CURSOR_MODE=legacy`, `AI_OS_DISABLE_CACHE=1`.

### Activation
The gate, role injection, and session hooks activate on `ai install`
(idempotent registration into the agent settings).

---

### Foundation (pre-2.0.0, untagged)
The 2.0.0 baseline already includes the framework built across E-1…E-119: the
Triad architecture (Architect / Engineer / Tester) over ACID SQLite state, 25 MCP
servers, RBAC-gated skills, a JIT context cache, NDJSON observability with a
cross-project meta-cognition telemetry loop, the drop-in installer, Managed Agents
cloud reconciliation, a Multimodal RAG batch pipeline, the SEO Topic Cluster
Engine, the AST Repository Map, and the earlier Sovereignty Hardening primitives
(DONE-task lock, Architect git/file blocks).

[2.0.0]: https://github.com/Vimurai/ai-os/releases/tag/v2.0.0
