# Blueprint: Governance (§22, §36–39)

> Covers: Test harness, context hygiene, JIT CLI ingestion, UPDATE.md deprecation, architectural fragmentation.

## §22. Minimal Bash Test Harness
- **Directory Structure**:
  - `tests/run.sh`: Master runner — discovers all `*_test.sh` in `tests/suites/`, runs each in isolated subshell, aggregates results.
  - `tests/lib/assert.sh`: Core assertions (`assert_status`, `assert_contains`, `assert_exists`, `assert_match`, `assert_equals`).
  - `tests/suites/`: Individual test suites (e.g., `mcp_test.sh`, `cli_test.sh`).
- **CLI Integration**: `ai test` executes `bash tests/run.sh`. Success emits `[TEST_PASSED]`.
- **Security**: Use `ai-exec` for destructive tests (e.g., testing `ai archive`) to maintain worktree isolation.
- **MCP Zero-Config**:
  - `ai mcp-setup`: Reads `registry.json`, runs `npm install` per server, generates `.mcp.json` with absolute paths.
  - `ai init`: Triggers `ai mcp-setup` automatically (battery-included).
  - `ai doctor`: Verifies all registered MCP servers — flags missing `node_modules` or bad paths.

## §36. Context Hygiene & Preflight Standardization
- **Rule 1 (Standardized Preflight)**: All agents MUST restrict initial Preflight to ONLY `DIGEST.md` + `TASKS.md`. Full `.ai/` folder ingestion by every sub-agent in a Tier 3 review is **forbidden**.
- **Rule 2 (JIT Ingestion)**: Large context files MUST use offset/limit targeting (`grep`, `start_line`/`end_line`) instead of full dumps.
- **Rule 3 (Diff-Driven Updates)**: `digest_updater` MUST use `git log --since=<mtime>` to detect changes — never blindly reads all `.ai/` files.
- **Rule 4 (AIS: Fresh Conversations)**: Use `/clear` between unrelated tasks. Exponential context cost per message in a long chat. This is the #1 token-burn mitigation.

## §37. Just-In-Time (JIT) CLI Ingestion
- **Enforcement**: Broad CLI prompts (e.g., `ai update`, `ai onboard`) MUST use targeted glob patterns and offset-bounded reads.
- **6-File Limit**: Mechanically enforced in `do_update()`, `do_onboard()`, `do_digest()` prompts in `src/bin/ai`.
- **Forbidden**: `ls -R`, unconstrained `cat` loops, `find . -name '*'` sweeps.

## §38. Deprecation of UPDATE.md & Chat-Driven Intent
- **Status**: FULLY DEPRECATED (E-147). `UPDATE.md` must never be created or read.
- **Workflow**: All intent flows directly from user **chat** → Architect or Engineer. No file buffer.
- **`ai update` Refactor** (E-148): Accepts inline intent from CLI args, triggers `digest_updater` (JIT), updates `state.json` via `task-synchronizer-mcp`.
- **MCP Status**: `run_intent_cleanup` (orchestrator-mcp) and `sync_tasks` (task-synchronizer-mcp) are no-op deprecation stubs.
- **Agent/Skill Status**: All preflights, hooks, and skills have been purged of `UPDATE.md` references.

## §39. Architectural Fragmentation (Domain Blueprints)
- **Status**: IMPLEMENTED (E-151).
- **Structure**:
  - `.ai/architect.md`: Lightweight index/router (~30 lines). JIT loading instructions.
  - `.ai/blueprints/core.md`: Philosophy, UX, dev cycle, project scoping (§1–4, §15, §20–21).
  - `.ai/blueprints/security.md`: Security, gates, AQG, TSRT, anti-drift (§5–6, §8, §13–14, §26, §35).
  - `.ai/blueprints/agents.md`: Agent blueprints, UACS, skills architecture (§10–12, §16–18).
  - `.ai/blueprints/mcp.md`: MCP server specs, LSP, patching, token budget, GitHub bridge (§23–30).
  - `.ai/blueprints/governance.md`: Token economics, JIT ingestion, UPDATE.md deprecation (§22, §36–39).
- **JIT Protocol**: Read `DIGEST.md` first. Then read THIS index. Then load ONLY the relevant domain blueprint.
- **Preflight**: `run_preflight()` returns the architect INDEX only. Domain blueprints are JIT-loaded by agents on demand.
