# Changelog

All notable changes to **ai-os-v2** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); this project adheres to [Semantic Versioning](https://semver.org/).

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
