# TASKS (Generated from state.json)

## Engineer (Claude)
- [x] E-113: Create tests/suites/resilience_test.sh with the 3 scenarios defined in P-52 §34. | Tier: 3
  Status: DONE 2026-03-22 — Created tests/suites/resilience_test.sh with 14 tests covering Scenario A (Layer 1/2 fallback), Scenario B (Layer 3 manual recovery), Scenario C (state corruption). 14/14 passing.
- [x] E-114: Update src/templates/architect.md.template and src/templates/CAPABILITIES.md (P-53). | Tier: 1
  Status: DONE 2026-03-22 — Added §30 (Bootloader Resilience), §31 (Memory Palace), §32 (Verification Audit) sections to src/templates/architect.md.template. Closes P-53 template sync gap.
- [x] E-115: Update project CAPABILITIES.md to register new tools (completes E-110). | Tier: 1
  Status: DONE 2026-03-22 — Created project-level CAPABILITIES.md at repo root with ~/.ai-os/memory/** (write) and ~/.ai-os/config/** (read) registered. Completes E-110 for the project deployment.
- [x] E-116: Update context-invoker-mcp to support Project Scope. Modify src/mcp/context-invoker-mcp/index.js to insert project-scoped directories (.claude/skills, .gemini/skills, .claude/agents, .gemini/agents) at the beginning of SKILL_ROOTS and AGENT_ROOTS, prioritizing them over global ones. | Tier: 2
  Status: DONE 2026-03-22 — context-invoker-mcp: project-scoped .claude/.gemini dirs prepended to SKILL_ROOTS/AGENT_ROOTS when .ai/ present
- [x] E-117: Update ai doctor output in src/bin/ai to explicitly check and report on project-scoped .gemini and .claude directories (and their agents/ / skills/ subdirectories) if a .ai directory is present in the current working directory. Update output titles to specify 'Global' and 'Project-Scoped'. | Tier: 1
  Status: DONE 2026-03-22 — ai doctor: renamed sections to Global, added Project-Scoped section for .claude/.gemini when in AI-OS project
- [x] E-118: Update _run_compliance_audit python inline script inside src/bin/ai to also scan .claude/agents, .claude/skills, .gemini/agents, and .gemini/skills in the project root if a .ai directory is present, ensuring project-scoped modifications are properly audited for Ghost Tools. | Tier: 2
  Status: DONE 2026-03-22 — _run_compliance_audit: added .claude/agents, .claude/skills, .gemini/agents, .gemini/skills to Python scan paths
- [x] E-119: Add unit tests for `context-invoker-mcp` to ensure it properly resolves skills and agents in the project scope if they exist, or verify this manually in a script. Update any integration tests related to `ai doctor --compliance` to handle project-scoped output if needed. | Tier: 2
  Status: DONE 2026-03-22 — tests/suites/context_invoker_test.sh created — 20 assertions, 20/20 passing
- [x] E-120: Add explicit ANTI-DRIFT PROTOCOL sections to src/claude/CLAUDE.md and src/gemini/GEMINI.md containing the exact refusal templates specified in §35. Update src/templates/CLAUDE.md and src/templates/GEMINI.md as well. | Tier: 1
  Status: DONE 2026-03-22 — ANTI-DRIFT PROTOCOL section added to src/claude/CLAUDE.md, src/gemini/GEMINI.md, src/templates/CLAUDE.md, src/templates/GEMINI.md
- [x] E-121: Update verification-mcp (src/mcp/verification-mcp/index.js) and the inline python audit script in src/bin/ai (_run_compliance_audit) to include a check for the 'ANTI-DRIFT PROTOCOL' string in CLAUDE.md and GEMINI.md. If missing, it must throw a CRITICAL error. | Tier: 2
  Status: DONE 2026-03-22 — _run_compliance_audit: ANTI_DRIFT_HEADER check added; CRITICAL error if missing from CLAUDE.md/GEMINI.md
- [x] E-122: Update hooks/pre-commit.sh to emit a warning if a commit contains changes to both 'src/' and '.ai/architect.md' unless the log explicitly proves an approved implementation delta. | Tier: 2
  Status: DONE 2026-03-22 — hooks/pre-commit.sh: check_architect_src_comodification warns on src/ + architect.md co-staged without [IMPL_DELTA]
- [x] E-123: Update `install_global()` in `src/bin/ai` to remove all modifications to `~/.gemini` and `~/.claude`. `ai install` must strictly target `~/.ai-os` or `.config/github-copilot`. Remove calls to `configure_gemini_mcp` and `enable_claude_agent_teams` from this global installation function. | Tier: 2
  Status: DONE 2026-03-22 — install_global() rewritten — targets ~/ .ai-os and ~/.config/github-copilot only; removed rm -rf ~/.gemini/~/.claude, global agent/skill installs, configure_gemini_mcp and enable_claude_agent_teams calls
- [x] E-124: Refactor `configure_gemini_mcp()` in `src/bin/ai` to `_configure_project_gemini_settings(TARGET_DIR)`. It must operate exclusively on the project-scoped `.gemini/settings.json`, following the strict project-scoping policy defined in §21. | Tier: 2
  Status: DONE 2026-03-22 — configure_gemini_mcp() renamed to _configure_project_gemini_settings(TARGET_DIR); now writes TARGET_DIR/settings.json instead of ~/.gemini/settings.json; signature changed to accept target_dir as first arg
- [x] E-125: Refactor `enable_claude_agent_teams()` in `src/bin/ai` to merge its logic (enabling agent teams, auto-enabling registry MCP tool permissions) into the existing `_configure_project_claude_settings(TARGET_DIR)` function. It must operate exclusively on the project-scoped `.claude/settings.json`. | Tier: 2
  Status: DONE 2026-03-22 — enable_claude_agent_teams() merged into _configure_project_claude_settings(TARGET_DIR) — agent teams env var, Bash(gemini -p *) permission, and registry-driven MCP permissions now written to project-scoped .claude/settings.json; old global function removed
- [x] E-126: Update `do_init()` in `src/bin/ai` to execute the project-scoped configuration functions (`_configure_project_claude_settings ".claude"` and `_configure_project_gemini_settings ".gemini"`) upon scaffolding a new AI-OS project. | Tier: 2
  Status: DONE 2026-03-22 — ensure_ai_templates() now calls _configure_project_gemini_settings ".gemini" after populating .gemini/ dir; both .claude/ and .gemini/ settings.json written on ai init
- [x] E-127: Update `do_sync()` in `src/bin/ai` to entirely remove the fallback global `~/.claude` and `~/.gemini` syncing logic. Synchronization of agents, skills, and CLAUDE.md/GEMINI.md files must only occur within the local project directory if `.ai/` is present. Update `ai doctor` checks to align with the deprecation of global scoping. | Tier: 2
  Status: DONE 2026-03-22 — do_sync() removes global ~/.claude/~/.gemini fallback — project-only sync when .ai/ present; exits early with guidance if not in AI-OS project; _configure_project_gemini_settings added to sync block; ai doctor global section updated to reflect user-owned global dirs
- [x] E-128: Update the `ai-review` skill (`src/gemini/skills/ai-review/SKILL.md` and `src/claude/skills/ai-review/SKILL.md` if applicable) to instruct the Architect to use `mcp_task-synchronizer-mcp_add_stamp` (with `ARCH_AUDIT` type) instead of appending multi-line text directly to `.ai/REVIEWS.md`. This ensures compliance with Check 4 and D-007. | Tier: 2
  Status: DONE 2026-03-23 — Updated ai-review skills (Claude + Gemini) to use mcp__task-synchronizer-mcp__add_stamp instead of direct REVIEWS.md appends. Synced to all 4 Claude locations and .gemini/skills.
- [x] E-129: Update src/bin/ai-exec with Worktree Resilience. Implement a `trap` for `EXIT ERR SIGINT SIGTERM` to ensure `git worktree remove --force <path>` is reliably called on teardown. On start, `ai-exec` must run `git worktree prune` and explicitly wipe any orphaned `.ai-worktree-*` directories to prevent state locks from aborted runs. | Tier: 2
  Status: DONE 2026-03-23 — src/bin/ai-exec: trap now covers EXIT ERR SIGINT SIGTERM and is registered before create_worktree; git worktree prune + orphaned /tmp/ai-exec-* and .ai-worktree-* dirs wiped on startup.
- [x] E-130: Implement the PostToolUse Hook for the Automatic Quality Gate (AQG). Create or update a hook (e.g., `hooks/post-tool-use.sh`) to intercept file modification tools. It must automatically execute local tests (e.g., `tests/run.sh`) for any modified `src/**` files. If tests fail, it must exit with code `1` and inject a `[LOCKED - AQG FAILED]` prefix into the tool output, forcing the agent to resolve the test failure before proceeding. | Tier: 2
  Status: DONE 2026-03-23 — Created hooks/post-tool-use.sh (AQG): intercepts Write/Edit on src/** files, runs tests/run.sh, exits 1 with [LOCKED - AQG FAILED] on failure. Registered in _configure_project_claude_settings() in src/bin/ai, .claude/settings.json, and added ai doctor check.
- [x] E-131: Create the `commit-crafter` Claude Skill in `src/claude/skills/commit-crafter/SKILL.md`. It must automate the strict AI-OS commit hook requirements by staging changes, formatting Conventional Commits, and injecting required UACS stamps and E-## task IDs. Ensure it explicitly forbids Claude from using `--author` flags or appending `Co-authored-by` trailers, adhering to the new Git Identity mandate in `architect.md`. | Tier: 2
  Status: DONE 2026-03-23 — Created src/claude/skills/commit-crafter/SKILL.md — automates Conventional Commits with E-## IDs and UACS stamps; enforces Git Identity mandate (no --author, no Co-authored-by).
- [x] E-132: Create the `aqg-resolver` Claude Sub-Agent in `src/claude/agents/aqg-resolver.md`. It should be a low-context autonomous fixer triggered when the Executor is `[LOCKED - AQG FAILED]`. Its role is to read linter/test stderr, apply exact file fixes without altering business logic, and re-run the gate. | Tier: 2
  Status: DONE 2026-03-23 — Created src/claude/agents/aqg-resolver.md — low-context autonomous fixer for [LOCKED - AQG FAILED]; reads test stderr, applies minimal fix, re-runs gate; reports [AQG_RESOLVER_BLOCKED] after 2 failed attempts.
- [x] E-133: Create the `bug-reproducer` Claude Skill in `src/claude/skills/bug-reproducer/SKILL.md`. This skill enforces empirical validation for Tier 2/3 bug fixes by forcing the Executor to create an isolated `repro.sh` or failing test case that proves the bug exists before modifying source code. | Tier: 2
  Status: DONE 2026-03-23 — Created src/claude/skills/bug-reproducer/SKILL.md — mandates repro.sh or failing test before any src/ edit for Tier 2/3 bugs; confirms reproduction before proceeding.
- [x] E-134: Create the `release-manager` Shared Skill in `src/shared/skills/release-manager/SKILL.md`. This skill handles the sprint lifecycle by bumping `package.json`, aggregating `DONE` tasks into `CHANGELOG.md`, tagging the commit, and optionally triggering an `ai archive`. | Tier: 2
  Status: DONE 2026-03-23 — Created src/shared/skills/release-manager/SKILL.md — bumps package.json, aggregates DONE tasks into CHANGELOG.md, tags commit, optionally triggers ai archive.
- [x] E-135: Create the `docs-architect` Gemini Sub-Agent in `src/gemini/agents/docs-architect.md`. It must periodically audit public documentation (`README.md`, `CONTRIBUTING.md`) against `.ai/architect.md` and `.mcp.json` to prevent drift. | Tier: 1
  Status: DONE 2026-03-23 — Created src/gemini/agents/docs-architect.md — audits README.md/CONTRIBUTING.md vs architect.md and .mcp.json for drift; produces gap report and recommends P-## tasks.
- [x] E-136: E-136: Implement the `lsp-mcp` server wrapping `typescript-language-server`. | Tier: 2
  Status: DONE 2026-03-31 — lsp-mcp MCP server created — get_definitions, get_references, get_diagnostics via TypeScript compiler API; registered in registry.json and .mcp.json
- [x] E-137: E-137: Implement the `patch_file` tool in `src/bin/ai` and MCP servers. | Tier: 2
  Status: DONE 2026-03-31 — patch-mcp MCP server created — patch_file with MD5 optimistic-lock verification + get_file_md5; registered in registry.json and .mcp.json
- [x] E-138: E-138: Implement post-task `Reactive Memory` hook for automated `DIGEST.md` updates. | Tier: 2
  Status: DONE 2026-03-31 — Reactive Memory hook: run_handover sets digest_stale=true in state.json; stop-hook.sh emits banner; run_preflight surfaces stale warning at session start
- [x] E-139: E-139: Implement the `ai-compact` skill for history distillation and context preservation. | Tier: 2
  Status: DONE 2026-03-31 — ai-compact skill created — distills SESSION.md to Active Context, archives raw log, resets to minimal header; user-invocable via /compact
- [x] E-140: E-140: Implement `token-budget-mcp` with SQLite persistence. | Tier: 2
  Status: DONE 2026-04-01 — token-budget-mcp created — report_cost/get_token_budget/get_usage_report/set_budget/reset_session, SQLite at ~/.ai-os/usage.sqlite, BUDGET_WARN on threshold
- [x] E-141: E-141: Implement the `propose_patch` tool with interactive TUI diff previews. | Tier: 2
  Status: DONE 2026-04-01 — propose-patch-mcp created — propose_patch/confirm_patch/reject_patch/list_pending_patches/preview_patch, delta/diff fallback formatter, in-memory patch store, path traversal blocked
- [x] E-142: E-142: Implement the `github-bridge-mcp` using GitHub CLI (gh) integration. | Tier: 2
  Status: DONE 2026-04-01 — github-bridge-mcp created — check_gh_auth/fetch_assigned_issues/get_issue/create_update_from_issues/get_pr_status via gh CLI whitelist; ai sync --github wired into src/bin/ai
- [x] E-143: E-144: Implement Role-Aware interceptors in filesystem MCPs to throw `[ANTI_DRIFT_VIOLATION]` when Gemini targets `src/`. | Tier: 2
  Status: DONE 2026-04-02 — Role-Aware RBAC interceptors implemented. roleGuard() added to patch-mcp (patch_file) and propose-patch-mcp (propose_patch + confirm_patch defense-in-depth). check_role_access pre-flight tool added to context-guardian-mcp. Architect blocked from src/ writes with [ANTI_DRIFT_VIOLATION]; .ai/ and plans/ whitelisted. 25 new tests in e143_test.sh, all passing.

## Tester (TestSprite)
- [x] T-1: Add idempotency tests for `ai init` and `ai sync`: assert that CLAUDE.md, GEMINI.md, and .mcp.json are always overwritten by ensure_ai_templates() and do_sync(); verify second run produces identical output (content matches template); covers P1 gap flagged in [TESTS_WARN] 2026-03-23 | Tier: 1
  Status: DONE 2026-03-31 — idempotency_test.sh created — 16 tests covering CLAUDE.md/GEMINI.md/.mcp.json overwrite on repeated init/sync; 16/16 passing

## Architect (Gemini)
- [x] P-1: P-54: Design the `lsp-mcp` server wrapping `typescript-language-server` or `pyright` for true symbol/type awareness. | Tier: 2
  Status: DONE 2026-03-31 — LSP-MCP designed (\u00a712) \u2014 wraps language servers for real-time diagnostics and symbol jump. E-136 implementation ready.
- [x] P-2: P-55: Design the `ai-compact` and `ai-digest-reactive` logic for automated context management. | Tier: 2
  Status: DONE 2026-03-31 — ai-compact designed (\u00a713) \u2014 distill SESSION.md when >2k tokens, archive raw log. E-139 implementation ready.
- [x] P-3: P-56: Design the `patch_file` tool with MD5/timestamp validation to prevent race conditions. | Tier: 2
  Status: DONE 2026-03-31 — patch_file designed (\u00a725) \u2014 MD5/timestamp lock to prevent race conditions during write. E-137 implementation ready.
- [x] P-4: P-57: Design the `token-budget-mcp` and budget-aware planning protocol. | Tier: 2
  Status: DONE 2026-03-31 — token-budget-mcp designed (plans/agentic_upgrades_phase2.md \u00a71) \u2014 SQLite usage tracking. E-140 ready.
- [x] P-5: P-58: Design the `github-bridge-mcp` for autonomous issue-to-blueprint flows. | Tier: 2
  Status: DONE 2026-03-31 — github-bridge-mcp designed (plans/agentic_upgrades_phase2.md \u00a72) \u2014 gh CLI issue sync. E-142 ready.
- [x] P-6: P-59: Design the "Just-in-Time" (Level 2) Skill Loading architecture. | Tier: 2
  Status: DONE 2026-03-31 — JIT Skill Loading designed (plans/agentic_upgrades_phase2.md \u00a73) \u2014 Metadata discovery vs Hard activation. E-142 ready.
- [ ] P-7: P-60: Design the `propose_patch` TUI diff preview flow and user confirmation hook. | Tier: 2
- [ ] P-8: P-61: Architectural Fragmentation (\u00a736) \u2014 Split architect.md into Domain Blueprints to reduce session-start context tax. | Tier: 1
- [ ] P-9: P-62: "Metadata-Only" Default Mode \u2014 Update ai sync to only provide Skill Summaries to agents by default. | Tier: 1
- [ ] P-10: P-63: Design MCP-Level Role-Based Access Control (RBAC) to enforce the Anti-Drift Protocol by blocking Architect writes to `src/`. | Tier: 2
