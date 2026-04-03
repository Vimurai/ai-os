# Blueprint: MCP Servers (§23–30)

> Covers: Code intelligence layer, reactive memory, staleness-aware patching, token budget, GitHub bridge, JIT skill loading, safe diff flow.

## §23. Code Intelligence Layer (LSP-MCP)
- **Purpose**: True symbol/type awareness without expensive file reads.
- **Server**: `lsp-mcp` wraps `typescript-language-server` (or `pyright`, `gopls`).
- **Tools**:
  - `get_definitions(path, line, col)`: Jump to symbol implementation.
  - `get_references(path, line, col)`: Find all usages of a symbol.
  - `get_diagnostics(path)`: Real-time lint/type errors.
- **Requirement**: Mandatory for Tier 3 refactors to ensure type safety across boundary changes.

## §24. Reactive Memory & Context Compaction
- **Reactive Memory**: `run_handover()` sets `digest_stale=true` in `state.json`. Stop hook emits stale banner. Preflight surfaces stale warning.
- **Context Compaction (`ai-compact` skill)**:
  - Trigger: `SESSION.md` exceeds 2,000 tokens, or manual `/compact`.
  - Action: Distills conversation into "Active Context", archives raw SESSION.md log, resets to minimal header.

## §25. Staleness-Aware File Patching (patch-mcp)
- **Purpose**: Prevent race conditions where a linter or human edits a file while the agent is "thinking."
- **Tool**: `patch_file(path, old_content, new_content, expected_md5)`.
- **Logic**: Verifies `expected_md5` before write — blocks if file drifted since last read.
- **Companion**: `get_file_md5(path)` for pre-read lock acquisition.
- **RBAC**: `roleGuard()` in patch-mcp blocks Architect writes to `src/`. Throws `[ANTI_DRIFT_VIOLATION]`.

## §27. Token Budget & Cost Governance (token-budget-mcp)
- **Purpose**: Monitor and control LLM spend in real-time.
- **Tools**: `report_cost(task_id, tokens, usd)`, `get_token_budget()`, `get_usage_report()`, `set_budget()`, `reset_session()`.
- **Storage**: `~/.ai-os/usage.sqlite` (SQLite persistence).
- **Threshold**: Emits `BUDGET_WARN` when usage approaches configurable limit.

## §28. GitHub Bridge (github-bridge-mcp)
- **Purpose**: Fetch GitHub issues and format them as Architect task proposals.
- **Tools**:
  - `check_gh_auth()`: Verify `gh` CLI is installed and authenticated.
  - `fetch_assigned_issues(limit?, repo?)`: Assigned open issues for current user.
  - `get_issue(number, repo?)`: Full issue details (title, body, labels, comments).
  - `create_intent_from_issues(numbers[], repo?)`: Formats issues as P-## proposals (inline, no file write).
  - `get_pr_status(pr_number?, repo?)`: PR review state, CI checks, merge readiness.
- **Security**: All `gh` invocations use `spawnSync` with explicit arg arrays. No shell injection. Whitelisted subcommands: `issue`, `pr`, `auth`.
- **CLI Integration**: `ai sync --github` triggers `fetch_assigned_issues` → returns formatted proposals.

## §29. Just-in-Time (JIT) Skill Loading
- **Concept**: Minimize context pollution by only loading necessary skill instructions.
- **Levels**:
  - Level 1 (Meta-Sync): `ai sync` exposes skill descriptions only (one-line summaries).
  - Level 2 (Activation): Full `SKILL.md` content loaded only when `activate_skill` is called.
  - Level 3 (Deep-Dive): `references/` read only if task requires it.
- **Implementation**: `context-invoker-mcp` enforces Level 2 by default. See E-152 for metadata-only mode.

## §30. Human-in-the-Loop Safe Diff Flow (propose-patch-mcp)
- **Purpose**: Mandatory visual confirmation for logic-heavy edits.
- **Tools**: `propose_patch(path, diff)`, `confirm_patch(id)`, `reject_patch(id)`, `list_pending_patches()`, `preview_patch(id)`.
- **Logic**: Claude presents a formatted diff (using `delta`/`diff` fallback) and pauses for `[Y/N]` terminal confirmation before applying.
- **RBAC**: Defense-in-depth `roleGuard()` on `confirm_patch` — Architect cannot confirm patches to `src/`.

## MCP Server Registry Summary
| Server | Key Tools | Status |
|--------|-----------|--------|
| `orchestrator-mcp` | `run_preflight`, `run_handover`, `run_review` | Active |
| `task-synchronizer-mcp` | `add_task`, `update_task_status`, `add_stamp` | Active (`sync_tasks` deprecated) |
| `context-invoker-mcp` | `activate_skill`, `activate_agent` | Active |
| `blueprint-aligner-mcp` | `align_diff`, `validate_blueprint_section` | Active |
| `context-guardian-mcp` | `check_role_access`, `check_workspace` | Active |
| `safe-exec-mcp` | `analyze_command` | Active |
| `risk-analyzer-mcp` | `classify_risk`, `get_tier_actions` | Active |
| `verification-mcp` | `verify_compliance` | Active |
| `archive-manager-mcp` | `check_context_health`, `execute_archive` | Active |
| `memory-manager-mcp` | `export_signature`, `query_signatures` | Active |
| `lsp-mcp` | `get_definitions`, `get_references`, `get_diagnostics` | Active (E-136) |
| `patch-mcp` | `patch_file`, `get_file_md5` | Active (E-137) |
| `propose-patch-mcp` | `propose_patch`, `confirm_patch`, `reject_patch` | Active (E-141) |
| `token-budget-mcp` | `report_cost`, `get_token_budget`, `set_budget` | Active (E-140) |
| `github-bridge-mcp` | `fetch_assigned_issues`, `create_intent_from_issues` | Active (E-142) |
| `vibe-check-mcp` | `run_vibe_audit`, `run_chaos_test` | Active |
| `intent-refiner-mcp` | (no-op) | **DEPRECATED** (E-147) |
