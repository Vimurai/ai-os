# TASKS (Generated from state.json)

## Engineer (Claude)
- [x] P-33: Port the `task_validator` agent to SQLite. Update its instructions to use `get_state` instead of loading the full `TASKS.md` into context. (See `.ai/blueprints/robustness_phase5.md` section 1) | Tier: 2
  Status: DONE 2026-04-13 — Updated task_validator agent to use get_state() via task-synchronizer-mcp with TASKS.md fallback
- [x] P-34: Restore mandatory YAML frontmatter to all 6 Gemini sub-agents in `src/gemini/agents/`. Authorize specific toolsets per agent role to satisfy `verification-mcp` compliance. (See `.ai/blueprints/robustness_phase6.md` section 1) | Tier: 2
  Status: DONE 2026-04-13 — Restored YAML frontmatter (disable-model-invocation, user-invocable, allowed-tools) to all 6 Gemini sub-agents with least-privilege toolsets
- [x] P-35: Align `CAPABILITIES.md` with current SQLite paths. Add explicit READ/WRITE permissions for `~/.ai-os/*.sqlite` and READ for the config registry to prevent `ai-exec` warnings. (See `.ai/blueprints/robustness_phase6.md` section 2) | Tier: 1
  Status: DONE 2026-04-13 — Added ~/.ai-os/*.sqlite to filesystem.read and filesystem.write in CAPABILITIES.md with explanatory note
- [x] P-36: Audit MCP servers (`vibe-check-mcp`, `lsp-mcp`, `task-synchronizer-mcp`) for resource leaks. Ensure all external process handles and database connections are closed in `finally` blocks. (See `.ai/blueprints/robustness_phase6.md` section 3) | Tier: 2
  Status: DONE 2026-04-13 — Fixed per-iteration context leak in vibe-check-mcp runVibeAudit by wrapping each context in a try/finally block
- [x] P-37: Harden the installer and `ai install` logic. Ensure path injection is idempotent and implement a more dynamic strategy for cleaning up deprecated v2 configuration files. (See `.ai/blueprints/robustness_phase6.md` section 3) | Tier: 2
  Status: DONE 2026-04-13 — Replaced hardcoded ORPHANS list in install-ai-os.sh with dynamic purge_orphans() function covering contracts/, claude/, gemini/
- [x] P-38: Implement explicit delta acknowledgment in `orchestrator-mcp`. Stop marking implementation deltas as read automatically during `run_preflight`. Add a `mark_deltas_read` tool so the Architect can confirm incorporation manually. (See `.ai/blueprints/robustness_phase7.md` section 1) | Tier: 2
  Status: DONE 2026-04-14 — Removed auto-read from run_preflight; added mark_deltas_read tool to task-synchronizer-mcp for explicit Architect acknowledgment
- [x] P-39: Harden `run_vibe_audit` in `vibe-check-mcp` against single-route failures. Add an inner `try...catch` loop so that a timeout or 404 on one route doesn't crash the entire audit session. (See `.ai/blueprints/robustness_phase7.md` section 2) | Tier: 2
  Status: DONE 2026-04-14 — Added inner try/catch per route in runVibeAudit; FAULT routes are recorded and reported without aborting the full audit
- [x] P-40: Integrate `report_cost` into the Triad workflow. Add directives to specialized agents (Security, DevOps) to report token usage via `token-budget-mcp` after completing high-tier tasks. (See `.ai/blueprints/robustness_phase7.md` section 3) | Tier: 1
  Status: DONE 2026-04-14 — Added report_cost directives to security_engineer and devops_engineer agents for Tier 2/3 tasks
- [x] P-41: Add normalization to `safe-exec-mcp` to resist basic command obfuscation (like quoted strings). Strip quotes and escapes from the command buffer before running the secret detection regex. (See `.ai/blueprints/robustness_phase7.md` section 4) | Tier: 2
  Status: DONE 2026-04-14 — Added normalizeForSecretScan() to safe-exec-mcp stripping quote concatenation and backslash escapes before SECRET_IN_COMMAND regex
- [x] P-42: Fix the `mkdirSync` race condition in `token-budget-mcp` and ensure robust initial SQLite creation in high-concurrency environments. (See `.ai/blueprints/robustness_phase7.md` section 4) | Tier: 2
  Status: DONE 2026-04-14 — Fixed token-budget-mcp getDb() to only cache connection after full schema setup; added stderr warning on init failure
- [x] P-43: Add `timeout_ms` and explicit CDP session cleanup to `get_performance_metrics` in `vibe-check-mcp`. (See `.ai/blueprints/robustness_phase8.md` section 1) | Tier: 2
  Status: DONE 2026-04-14 — Added timeout_ms param to get_performance_metrics; hoisted CDP client; detach() in finally block
- [x] P-44: Clean up stale documentation in `task-synchronizer-mcp` regarding `orchestrator-mcp` direct writes. (See `.ai/blueprints/robustness_phase8.md` section 2) | Tier: 1
  Status: DONE 2026-04-14 — Removed stale NOTE about orchestrator direct writes; updated JSDoc tool list to include mark_deltas_read
- [x] P-45: Refactor `ai onboard` in `src/bin/ai` to pull project focus from `state.sqlite` using `sqlite3` CLI, falling back to `state.json`. (See `.ai/blueprints/robustness_phase8.md` section 2) | Tier: 2
  Status: DONE 2026-04-14 — Refactored _export_signature_to_global_store to extract focus via sqlite3 CLI first, passing to python3 as argv[3] with state.json fallback
- [x] P-46: Extend installer orphan cleanup in `install-ai-os.sh` to cover the `shared/` directory. (See `.ai/blueprints/robustness_phase8.md` section 3) | Tier: 2
  Status: DONE 2026-04-14 — Extended purge_orphans in install-ai-os.sh to cover src/shared/ directory
- [x] P-47: Update `state-db.js` to use `os.homedir()` instead of fragile environment variable checks for global path resolution. (See `.ai/blueprints/robustness_phase8.md` section 3) | Tier: 2
  Status: DONE 2026-04-14 — Replaced process.env.HOME || "~" with os.homedir() in token-budget-mcp for reliable home directory resolution
