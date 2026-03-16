# TASKS (Generated from state.json)

## Architect (Gemini)
- [x] P-43: Implement `ai-migrate-state` tool to programmatically seed state.json from current TASKS.md content.
  Status: DONE 2026-03-16 — ai migrate-state --force seeded 121 tasks from TASKS.md into state.json
- [x] P-44: Hard-Mandate state.json as source-of-truth in all MCP servers, disabling legacy markdown parsing fallbacks.
  Status: DONE 2026-03-16 — TIER3_NO_SECURITY_REVIEW gate now clears exclusively from stamps[]; LOG.md fallback demoted to advisory WARN
- [x] P-1: Blueprint for `ai-exec` isolation (Git Worktrees) and `CAPABILITIES.md` schema
- [x] P-2: Update `post-tool-log.sh` blueprint to include `[SECURITY]` tags for `EXECUTE` operations
- [x] P-6: Blueprint for "Vision & Memory" Skillsets (`ux_reviewer.md`, `knowledge_architect.md`)
  Status: DONE 2026-03-10 — Section 17.2, 17.3 in architect.md
- [x] P-7: Blueprint for Skills 2.0 Modular Migration
  Status: DONE 2026-03-10 — Section 16 in architect.md
- [x] P-8: Blueprint for `prd_writer` and `chaos_monkey` agents
  Status: DONE 2026-03-10 — Section 17.1, 17.4 in architect.md
- [x] P-9: Blueprint for AI-OS Slash Command Integration (Skills 2.0)
  Status: DONE 2026-03-11 — Section 11.1 in architect.md
- [x] P-10: Blueprint for Gemini CLI Custom Commands (.toml) Configuration
  Status: DONE 2026-03-11 — Section 11.2 in architect.md
- [x] P-11: Blueprint for Shared Skills Architecture
  Status: DONE 2026-03-11 — Section 16.1 in architect.md
- [x] P-12: Blueprint for Contextual Auto-Calling and Agent Configurations
  Status: DONE 2026-03-11 — Section 17.5 in architect.md
- [x] P-13: Blueprint for MCP Automation & Lifecycle (mcp-setup + init/install integration)
  Status: DONE 2026-03-11 — Section 19 in architect.md
- [x] P-14: Blueprint for Sovereign Planning & Execution Protocol (Mandate .ai/ over CLI-native temp files)
  Status: DONE 2026-03-11 — Section 20 in architect.md
- [x] P-15: Blueprint for E-40 Minimal Bash Test Harness
  Status: DONE 2026-03-11 — Section 22 in architect.md
- [x] P-16: Implement `context-invoker-mcp` server to give Claude dynamic access to skills and agents. Create the MCP server with `activate_skill` and `activate_agent` tools, register it in `src/config/registry.json`, update `src/claude/CLAUDE.md` with invocation instructions and directory listings, and test via `ai mcp-setup` and `ai install`.
  Status: DONE 2026-03-11 — E-42
- [x] P-17: Implement `Repo-Oracle` skill for Gemini (historical awareness).
  Status: DONE 2026-03-11 — E-43
- [x] P-18: Implement `Vibe-Sentinel` agent for Claude (automated visual audit).
  Status: DONE 2026-03-11 — E-43
- [x] P-19: Implement `Token-Miser` shared skill (cost/context optimization).
  Status: DONE 2026-03-11 — E-43
- [x] P-20: Implement `Identity-Guardian` agent for Claude (PII and secrets specialist).
  Status: DONE 2026-03-11 — E-43
- [x] P-21: Implement `Architectural-Aligner` skill for Gemini (blueprint vs code consistency).
  Status: DONE 2026-03-11 — E-43
- [x] E-41: Verify all new agents and skills are synced and invocable (run `ai install` and test activation).
  Status: DONE 2026-03-11 — install-ai-os.sh synced; ai mcp-setup 8/8; [TEST_PASSED] 22/22
- [x] P-22: Upgrade Gemini Architect standards (Anti-Laziness & Questioning mandate) in src/gemini/GEMINI.md
  Status: DONE 2026-03-12 — Added Senior Architect Standards section.
- [x] P-23: Refine `prd_writer` (src/gemini/agents/prd_writer.md) with rigorous intent classification and mandatory questioning.
  Status: DONE 2026-03-12 — Updated Vague classification and added mandatory clarification prompts.
- [x] P-24: Expand `architect.md.template` with Backend/Data/API/Error-handling sections.
  Status: DONE 2026-03-12 — Added Sections 5 & 6 to the template.
- [x] P-25: Sync active `.ai/architect.md` roles with new Gemini mandate.
  Status: DONE 2026-03-12 — Updated Agent Roles in Section 2.
- [x] P-26: Integrate `ai-seo` third-party skill for AI Search Optimization.
  Status: DONE 2026-03-12 — Blueprint added to architect.md §16.2.
- [x] P-27: Blueprint for Auto-Pilot Archive & Context Automation.
  Status: DONE 2026-03-13 — architect.md §23 detailed logic.
- [x] P-28: Blueprint for VOTU (Voice of the User) Intake Protocol (bypass manual UPDATE.md).
  Status: DONE 2026-03-14 — Refactored src/bin/ai intent_gate.
- [x] P-29: Formalize mandates for all Ghost Agents in `architect.md` §17.
  Status: DONE 2026-03-14 — Added §§17.6-17.11 to architect.md.
- [x] P-30: Blueprint for Agent logic validation (T-01 suite).
  Status: DONE 2026-03-14 — Created tests/suites/agent_logic_test.sh.
- [x] P-31: Consolidate `ai-review` and `review_synthesizer` into a unified Triad Audit protocol.
  Status: DONE 2026-03-14 — Blueprint added to architect.md §4.
- [x] P-32: Formalize Stamp Governance protocol to fix missing [CRITIC_STAMP] issue.
  Status: DONE 2026-03-14 — Blueprint added to architect.md §17.
- [x] P-33: Blueprint for Cross-Agent State Synchronization (The `ai-sync-state` Protocol).
  Status: DONE 2026-03-14 — Blueprint added to architect.md §20.
- [x] P-34: Blueprint for Claude Mid-Execution Trigger Enforcement.
  Status: DONE 2026-03-15 — Checkpoint Protocol (§21) added to architect.md and CLAUDE.md.
- [x] P-35: Expand architectural blueprints for agents §17.6–17.11 (Decision Recorder, DevOps, Identity Guardian, Review Synthesizer, Task Validator, Vibe Sentinel) to include senior-level instruction depth.
  Status: DONE 2026-03-15 — Blueprints expanded in architect.md §17.6-17.11.
- [x] P-36: Blueprint for CLAUDE.md Diet — reduce global + project CLAUDE.md from 488 lines to ~60 lines max.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §23. Unblocks E-66, E-67, E-68.
- [x] P-37: Blueprint for Materialized Critic Agents — create real `critic_arch.md`, `critic_security.md`, `critic_tests.md` agent files.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §24. Unblocks E-69, E-70, E-71, E-72.
- [x] P-38: Blueprint for `orchestrator-mcp` — a deterministic workflow execution MCP server.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §25. Unblocks E-73, E-74, E-75, E-76, E-77.
- [x] P-39: Blueprint for Structured State Layer — replace prose markdown state with machine-readable `state.json`.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §26. Unblocks E-78, E-79, E-80, E-81.
- [x] P-40: Blueprint for Atomic Stamp Writes — prevent parallel agent write races on REVIEWS.md.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §27. Option C + B selected. Unblocks E-82.
- [x] P-41: Blueprint for Blueprint Schema Validation — enforce depth standards on Gemini's architect.md output.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §28. Unblocks E-83, E-84, E-85.
- [x] P-42: Blueprint for Architect Feedback Loop — close the gap between blueprint intent and implementation reality.
  Status: DONE 2026-03-15 — Blueprint added to architect.md §29. Unblocks E-86, E-87, E-88.
- [x] P-45: Blueprint strict enforcement of "Markdown as Read-Only" (e.g., via pre-commit hooks that verify MD sync against JSON). | Tier: 2
  Status: DONE 2026-03-16 — Blueprinted strict enforcement of Markdown as Read-Only (§26.3) and created E-95.
- [x] P-46: Blueprint specific E-## tasks for Section 19 (UACS Logic). | Tier: 1
  Status: DONE 2026-03-16 — Blueprinted UACS implementation tasks (E-92, E-93, E-94) in §19.1.
- [x] P-47: Audit all existing agents/skills for compliance with §17.1.2 YAML frontmatter standards. | Tier: 1
  Status: DONE 2026-03-16 — Completed bulk audit of 20+ agent files; created E-91 for frontmatter standardization.

## Engineer (Claude)
- [x] E-1: Implement `ai-exec` CLI (Bash) based on P-01 blueprint
  Status: DONE 2026-03-07 — src/bin/ai-exec (worktree isolation, Gate 3, [SECURITY] logging)
- [x] E-2: Update `post-tool-log.sh` logic based on P-02 blueprint
  Status: DONE 2026-03-07 — hooks/post-tool-log.sh ([SECURITY] tags for EXECUTE tools)
- [x] E-3: Create `src/templates/CAPABILITIES.md` template based on P-01 schema
  Status: DONE 2026-03-07 — src/templates/CAPABILITIES.md (READ/WRITE/EXECUTE/network schema)
- [x] E-4: Implement `ai archive` CLI command based on blueprint
  Status: DONE 2026-03-07 — src/bin/ai (do_archive: moves to .ai/archive/YYYY-MM/ with timestamp)
- [x] E-5: Implement `ai review` CLI command based on blueprint
  Status: DONE 2026-03-07 — src/bin/ai (do_review claude|gemini: parallel critic + arch audit prompts)
- [x] E-12: Implement Gate 1 (Intent Gate) in `ai update` logic
  Status: DONE 2026-03-10 — src/bin/ai (intent_gate(): hash change detection, vagueness hard-block <8 words/no verb, Tier 3 soft-block, --force bypass, .ai/.update.hash)
- [x] E-13: Implement Gate 2 (Quality Gate) in Git `pre-commit` hook
  Status: DONE 2026-03-10 — hooks/pre-commit.sh ([CRITIC_STAMP] check, ≤7 days, blocks commit + prints ai review claude prompt); do_init installs to .git/hooks/pre-commit (chains existing hooks); doctor checks gate install status
- [x] E-14: Implement Gate 3 (Execution Gate) in `ai-exec` CLI
- [x] E-15: Implement `ai test --vibe` (Chaos & UX Stress) logic
  Status: DONE 2026-03-11 — src/bin/ai (do_vibe_test: Phase 1 ux_reviewer prompt + Playwright check, Phase 2 chaos_monkey prompt; required stamps listed)
- [x] E-16: Implement `vibe-check-mcp` (Node.js + Playwright) for autonomous auditing
  Status: DONE 2026-03-11 — src/mcp/vibe-check-mcp/ (run_vibe_audit: CLS+contrast+focus; run_chaos_test: rapid-click+form+nav; get_performance_metrics: CDP LCP/CLS/TTFB)
- [x] E-17: Implement Universal Autonomous Command Suite (UACS) MCP suite
  Status: DONE 2026-03-11 — src/mcp/ (5 servers: intent-refiner, task-synchronizer, safe-exec, blueprint-aligner, context-guardian); .mcp.json updated; registry.json v2.0; ai mcp-setup command
- [x] E-21: Implement Token-Saving Risk Tiers (TSRT) logic in `ai update` and `ai review`
  Status: DONE 2026-03-11 — risk-analyzer-mcp (classify_risk + get_tier_actions, multi-signal: content keywords + file patterns + diff); detect_tier() bash helper; ai update emits [TIER_1/2/3] session prompts; ai review claude auto-detects tier (Tier1: skip, Tier2: blueprint_aligner only, Tier3: full Triad + [UACS_VERIFIED]); --tier override flag
- [x] E-22: Migrate existing Claude skills to Skills 2.0 modular structure (src/claude/skills/)
  Status: DONE 2026-03-11 — 5 skills migrated to skill-name/SKILL.md with YAML frontmatter; flat files removed; install/sync updated with sync_skills_20()
- [x] E-23: Migrate existing Gemini skills to Skills 2.0 modular structure (src/gemini/skills/)
  Status: DONE 2026-03-11 — 2 skills migrated to skill-name/SKILL.md with YAML frontmatter; flat files removed
- [x] E-24: Implement `prd_writer` agent (src/gemini/agents/prd_writer.md)
  Status: DONE 2026-03-11 — Intent classification (Vague/Tier1/2/3), P-## task generation, BRIEF.md conditional update
- [x] E-25: Implement `ux_reviewer` agent (src/gemini/agents/ux_reviewer.md)
  Status: DONE 2026-03-11 — Playwright visual audit, Lighthouse scores, Rapid-Click stress, [VIBE_REPORT] output
- [x] E-26: Implement `knowledge_architect` agent (src/gemini/agents/knowledge_architect.md)
  Status: DONE 2026-03-11 — Cross-project .ai/ discovery, pattern extraction, relevance scoring, SEED.md Knowledge Transfer
- [x] E-27: Implement `chaos_monkey` agent (src/claude/agents/chaos_monkey.md)
  Status: DONE 2026-03-11 — Invalid input injection, network latency sim, rapid-click, concurrent sessions, [CHAOS_CLEARED/BLOCKED] gate
- [x] E-28: Implement Slash Commands for `ai` operations (`update`, `test`, `review`, `archive`, `digest`, `preflight`) as Skills 2.0 modules under `src/claude/skills/` and `src/gemini/skills/` based on P-09 blueprint.
  Status: DONE 2026-03-11 — 6 Claude skills (ai-update, ai-test, ai-review, ai-archive[disable-model-invocation:true], ai-digest[context:fork], ai-preflight) + 2 Gemini skills (ai-update, ai-review); all with YAML frontmatter + dynamic context injection; P-09 inferred from §11+§16
- [x] E-29: Implement Gemini CLI Custom Commands (.toml) and update install/sync scripts based on P-10 blueprint
  Status: DONE 2026-03-11 — src/gemini/commands/ (8 .toml files: ai-update, ai-review, ai-archive, ai-digest, ai-preflight, ai-test, seo_content_checklist, ux_template); install_global + do_sync copy to ~/.gemini/commands/; install-ai-os.sh syncs src/gemini/
- [x] E-30: Refactor skill folders into src/shared/skills/ and update sync/install logic in src/bin/ai based on P-11 blueprint
  Status: DONE 2026-03-11 — src/shared/skills/ (ai-archive, ai-digest, ai-preflight, ai-test); removed from src/claude/skills/; install_global + do_sync sync shared/ to both ~/.claude/skills/ and ~/.gemini/skills/ before agent-specific; install-ai-os.sh syncs src/shared/
- [x] E-31: Update agent/skill frontmatter with `tools` arrays and trigger-based descriptions for Contextual Auto-Calling based on P-12 blueprint
  Status: DONE 2026-03-11 — 5 Claude agents updated with tools arrays + imperative trigger descriptions; 4 gemini/skills + 4 shared/skills updated with "Use activate_skill with this name when..." trigger conditions
- [x] E-32: Implement `do_mcp_setup` in `src/bin/ai` (Dependency install + dynamic .mcp.json generation) based on P-13 blueprint.
  Status: DONE 2026-03-11 — generate_mcp_json() reads registry.json + writes .mcp.json with absolute paths to ~/.ai-os/mcp/; do_mcp_setup iterates registry custom servers (not hardcoded), calls generate_mcp_json after install
- [x] E-33: Integrate `mcp-setup` into `do_init` and `install_global` for zero-config onboarding.
  Status: DONE 2026-03-11 — do_init calls do_mcp_setup (if node available); install_global calls do_mcp_setup; install-ai-os.sh syncs src/mcp/ + src/config/ to ~/.ai-os/
- [x] E-34: Update `ai doctor` to audit MCP server health and path integrity.
  Status: DONE 2026-03-11 — doctor iterates registry custom servers; checks source dir, package.json, node_modules, index.js; verifies .mcp.json absolute paths
- [x] E-35: Verify MCP servers are automatically enabled in `.claude/settings.local.json`.
  Status: DONE 2026-03-11 — enable_claude_agent_teams reads registry.json, adds mcp__<server>__<tool> to permissions.allow in ~/.claude/settings.json for all custom server tools
- [x] E-36: Update `CLAUDE.md`, `GEMINI.md`, and agent/skill instructions to enforce the Sovereign Planning Protocol (P-14).
  Status: DONE 2026-03-11 — CLAUDE.md + GEMINI.md updated with "Sovereign Planning Protocol" section; .ai/ memory primacy enforced; plan-mode output must be committed to architect.md + TASKS.md
- [x] E-37: [TRACE]: `src/claude/agents/claude_tasks.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
- [x] E-38: [TRACE]: `src/claude/agents/devops_engineer.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
- [x] E-39: [TRACE]: `src/claude/agents/digest_updater.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
- [x] E-40: Wire test harness so `ai test` can satisfy the 100% Quality Gate
  Status: DONE 2026-03-11 — tests/run.sh (master runner, bash 3 compatible, SUITE_RESULT parsing); tests/lib/assert.sh (assert_status/contains/exists/match/not_contains + assert_summary); tests/suites/cli_test.sh (7 assertions: version, usage, where, unknown cmd); tests/suites/mcp_test.sh (14 assertions: registry JSON, custom servers, .mcp.json generation + trailing newline); do_test() in src/bin/ai now executes tests/run.sh when present (TestSprite fallback preserved); [TEST_PASSED] 21/21
- [x] E-42: Implement `context-invoker-mcp` server (P-16)
  Status: DONE 2026-03-11 — src/mcp/context-invoker-mcp/ (activate_skill: multi-root Skills 2.0 + flat resolution from ~/.claude/skills/, ~/.gemini/skills/, ~/.ai-os/, src/ fallback; activate_agent: same pattern for ~/.claude/agents/; list_skills/list_agents discovery mode; not-found returns suggestions); registry.json updated (capability: READ); src/claude/CLAUDE.md updated with invocation section + skill/agent directory tables; [TEST_PASSED] 22/22
- [x] E-43: Implement 5 new skills/agents + verify sync (P-17 to P-21 + E-41)
  Status: DONE 2026-03-11 — repo-oracle (src/gemini/skills/repo-oracle/SKILL.md); vibe_sentinel (src/claude/agents/vibe_sentinel.md); token-miser (src/shared/skills/token-miser/SKILL.md); identity_guardian (src/claude/agents/identity_guardian.md); architectural-aligner (src/gemini/skills/architectural-aligner/SKILL.md); install-ai-os.sh synced all to ~/.ai-os/; ai mcp-setup 8/8; [TEST_PASSED] 22/22
- [x] E-44: Add unit tests for safe-exec-mcp BLOCK_RULES
  Status: DONE 2026-03-12 — tests/suites/safe_exec_test.sh (14 assertions: curl|bash, wget|bash, DROP TABLE, fork bomb, secret=); [TEST_PASSED] 92/92
- [x] E-45: Add unit tests for blueprint-aligner-mcp secret detection regex
  Status: DONE 2026-03-12 — tests/suites/blueprint_aligner_test.sh (17 assertions: HARDCODED_SECRET + CAPABILITIES_BYPASS patterns); [TEST_PASSED] 92/92
- [x] E-46: Fix .gitignore — add .env, .env.local, *.key, *.pem, /node_modules
  Status: DONE 2026-03-12 — .gitignore updated with .env, .env.local, *.key, *.pem, /node_modules
- [x] E-47: Refactor TestSprite API_KEY in .mcp.json to use environment variable
  Status: DONE 2026-03-12 — both .mcp.json and src/templates/.mcp.json updated to ${TESTSPRITE_API_KEY}
- [x] E-48: Add input validation in context-invoker-mcp for skill/agent names
  Status: DONE 2026-03-12 — validateName() added; rejects non-[a-z0-9_-] names and path traversal; tested in mcp_integration_test.sh
- [x] E-49: Add integration tests for all 8 MCP tool handlers
  Status: DONE 2026-03-12 — tests/suites/mcp_integration_test.sh (39 assertions: file exists + syntax + tool registration + registry + validation); [TEST_PASSED] 92/92
- [x] E-50: Set up CI pipeline (.github/workflows/test.yml)
  Status: DONE 2026-03-12 — .github/workflows/test.yml (Node 20, npm install for all MCP dirs, bash tests/run.sh, .gitignore secret check)
- [x] E-51: Create src/gemini/commands/ .toml files for all Gemini skills
  Status: DONE 2026-03-12 — architectural-aligner.toml + repo-oracle.toml created (8 existing + 2 new = 10 total)
- [x] E-52: Implement `ai-seo` skill integration based on P-26 blueprint
  Status: DONE 2026-03-12 — src/gemini/skills/ai-seo/SKILL.md (AEO/LLMO audit: structured data, answer-optimization, entity clarity, robots.txt AI bot check, llms.txt); src/gemini/commands/ai-seo.toml
- [x] E-53: Implement `archive-manager-mcp` (Node.js) with hybrid thresholds.
  Status: DONE 2026-03-14 — src/mcp/archive-manager-mcp/ (check_context_health: line+token heuristic, AUTO_ARCHIVE_LINES=200/AUTO_ARCHIVE_TOKENS=10000; execute_archive: spawns `ai archive` via host CLI); registry.json updated; [TEST_PASSED] 93/93
- [x] E-54: Update `post-tool-log.sh` with Semi-Verbose "Warn & Wait" logic.
  Status: DONE 2026-03-14 — hooks/post-tool-log.sh: after every LOG write, checks LOG.md line count; CLEAN workspace → auto-runs `ai archive`; DIRTY workspace (open tasks) → emits [WARNING] to stderr
- [x] E-55: Implement `post-commit.sh` for `TASKS.md` auto-sync.
  Status: DONE 2026-03-14 — hooks/post-commit.sh: parses commit message for (Fixes|Closes|Implemented) (E|P|T)-##, marks matching tasks [x] in .ai/TASKS.md; install_git_hooks() installs it to .git/hooks/post-commit (with chain-backup for existing hooks)
- [x] E-56: Chain `ai-digest` to the core `ai archive` command in `src/bin/ai`.
  Status: DONE 2026-03-14 — do_archive() now calls do_digest() immediately after successful archive, printing [AUTO-ARCHIVE] notice
- [x] E-57: Implement VOTU Protocol in `src/bin/ai`.
  Status: DONE 2026-03-14 — Refactored intent_gate() to allow empty UPDATE.md and bypass for long Architect content.
- [x] E-58: Implement T-01 Agent Logic Suite.
  Status: DONE 2026-03-14 — Created tests/suites/agent_logic_test.sh; 6/6 tests passing.
- [x] E-59: Audit and Re-implement VOTU and T-01 suite (Gemini cleanup).
  Status: DONE 2026-03-14 — (1) Fixed VOTU bypass bug: gate now requires HAS_ACTION=1 even for long content (>20 words). (2) Re-implemented agent_logic_test.sh with 12 real intent_gate() behaviour tests (exit code verification for all 3 gate outcomes). (3) Added retroactive LOG.md attribution for E-57 and E-58. (4) Restored execute permission on src/bin/ai. [TEST_PASSED] 105/105.
- [x] E-60: Implement Distributed Stamping for `ai-review` and `review_synthesizer`.
  Status: DONE 2026-03-14 — ai-review/SKILL.md: each critic writes [ARCH/SEC/TESTS/ALIGN]_PASS/FAIL; Tier 3 no longer writes [CRITIC_STAMP] manually, delegates to review_synthesizer. review_synthesizer.md: Phase 1 reads distributed stamps + writes [CRITIC_STAMP]; Phase 2/3 severity aggregation + RELEASE verdict. CLAUDE.md: trigger table + critic team spawn example updated with distributed stamp names. [TEST_PASSED] 119/119.
- [x] E-61: Implement `ai-sync-state` shared skill.
  Status: DONE 2026-03-15 — src/shared/skills/ai-sync-state/SKILL.md (hard re-read protocol: TASKS.md + architect.md + DIGEST.md, [SYNC-STATE] report format, read-only, cache-bypass mandate); src/gemini/commands/ai-sync-state.toml; ai-sync-state added to CLAUDE.md skill table + auto-trigger ("sync state", "handoff", "re-read tasks"). [TEST_PASSED] 119/119.
- [x] E-62: Refine `context-guardian-mcp` regex to exclude internal documentation/regex strings from "Dirty" workspace detection.
  Status: DONE 2026-03-15 — architect.md scan now tracks code fences and strips inline backtick spans before testing for TBD/TODO/FIXME markers; src/ strict scan skips lines where the marker appears inside a regex literal (e.g. /\b(TODO|FIXME)\b/). [TEST_PASSED] 119/119.
- [x] E-63: Implement deep-audit `ai doctor` logic (registry sync, dependency health, connectivity probe) as defined in architect.md §19.1.
  Status: DONE 2026-03-15 — doctor() extended with "MCP Deep Audit (§19.1)" section: (1) npm list --depth=0 per server → flags missing/UNMET deps; (2) node -c syntax probe per index.js → CRITICAL_FAILURE on error; (3) registry ↔ .mcp.json path consistency check via Python; (4) TESTSPRITE_API_KEY literal placeholder detection with actionable fix hint. [TEST_PASSED] 119/119.
- [x] E-65: Add T-01.14 test coverage for TIER3_NO_SECURITY_REVIEW rule in blueprint-aligner-mcp (P0-TESTS-01 fix).
  Status: DONE 2026-03-15 — tests/suites/agent_logic_test.sh: 5 new cases (T-01.14.1–5) covering: no TASKS.md diff, Tier 1 closed, Tier 3 closed with no log evidence (VIOLATION), Tier 3 closed with [SEC_PASS] (pass), checkbox form with Tier 3 (VIOLATION). [TEST_PASSED] 124/124.
- [x] E-66: Update `src/mcp/context-invoker-mcp/index.js` to ensure `list_skills` and `list_agents` return formatted trigger conditions parsed from YAML frontmatter.
  Status: DONE 2026-03-15 — listAvailable() now returns [name, description] tuples; parseFrontmatter() extracts description from YAML; list output shows `name: trigger description`. [TEST_PASSED] 124/124.
- [x] E-67: Rewrite `src/claude/CLAUDE.md` to implement the Bootloader Strategy, bringing it under 60 lines.
  Status: DONE 2026-03-15 — Reduced from 251 lines to 42 lines. Removed: auto-dispatch tables, checkpoint protocol details, parallel spawn rules, skill/agent directory tables. Retained: identity, 5 core rules, dynamic discovery via activate_skill/activate_agent, key skill pointers, mid-execution trigger reminder. [TEST_PASSED] 124/124.
- [x] E-68: Move parallel agent team instructions from `CLAUDE.md` into `src/contracts/06_AGENT_TEAMS.md`.
  Status: DONE 2026-03-15 — Consolidated spawn tables, chaining examples, two invocation modes, and rules into contracts file. CLAUDE.md now points to `src/contracts/06_AGENT_TEAMS.md` for parallel work.
- [x] E-69: Create `src/claude/agents/critic_arch.md` for deterministic architecture review.
  Status: DONE 2026-03-15 — Deterministic checklist: domain sovereignty, blueprint coverage, system philosophy alignment, file organization. P0/P1/P2 severity classification. Strict stamp format. [TEST_PASSED] 124/124.
- [x] E-70: Create `src/claude/agents/critic_security.md` for deterministic security auditing against `30_SECURITY.md`.
  Status: DONE 2026-03-15 — 5-point checklist: hardcoded secrets, shell injection, path traversal, capability boundary, env var leakage. Pre-flight reads 30_SECURITY.md + CAPABILITIES.md. [TEST_PASSED] 124/124.
- [x] E-71: Create `src/claude/agents/critic_tests.md` for deterministic test coverage verification.
  Status: DONE 2026-03-15 — 4-point checklist: modified src/ must have tests, suite must pass, new test quality, coverage gaps (advisory). Runs actual test suite. [TEST_PASSED] 124/124.
- [x] E-72: Update `ai-review/SKILL.md` and `06_AGENT_TEAMS.md` to invoke materialized agents instead of ad-hoc prompts.
  Status: DONE 2026-03-15 — Tier 3 section now spawns agents by name ("Run the critic_arch agent...") instead of inline prompts. 06_AGENT_TEAMS.md notes agents are materialized files. [TEST_PASSED] 124/124.
- [x] E-73: Scaffold `src/mcp/orchestrator-mcp/` and register it in `registry.json`.
  Status: DONE 2026-03-15 — package.json + index.js scaffolded; registry.json updated (capability: WRITE, 3 tools); npm install OK; node -c syntax OK. [TEST_PASSED] 125/125.
- [x] E-74: Implement the `run_preflight` tool inside the orchestrator.
  Status: DONE 2026-03-15 — Reads DIGEST, architect.md, UPDATE, TASKS in order; truncates large files to 80 lines; stamps SESSION.md; returns concatenated preflight context.
- [x] E-75: Implement the `run_handover` tool inside the orchestrator.
  Status: DONE 2026-03-15 — Validates task ID format; marks [ ] → [x] in TASKS.md with Status line; appends LOG entry; returns digest prompt.
- [x] E-76: Implement the complex `run_review` tool, migrating logic from `ai-review/SKILL.md`.
  Status: DONE 2026-03-15 — T1: skip verdict. T2: 5 deterministic checks (secrets, traversal, sovereignty, deps, log update) + aligner dispatch. T3: all T2 checks + coverage gap detection + parallel critic agent dispatch instructions + synthesizer invocation.
- [x] E-77: Update `CLAUDE.md` and related skills to instruct the use of the new orchestrator tools.
  Status: DONE 2026-03-15 — Added "Orchestrator" section to CLAUDE.md (run_preflight, run_handover, run_review); replaced manual skill references with orchestrator-first approach. CLAUDE.md at 50 lines.
- [x] E-78: Define the Zod/JSON schema for `.ai/state.json` and initialize it on `ai init`.
  Status: DONE 2026-03-15 — Created src/templates/state.json (version, project, tasks[], stamps[]); added ensure_file_if_missing to ensure_ai_templates() in src/bin/ai. [TEST_PASSED] 125/125.
- [x] E-79: Refactor `task-synchronizer-mcp` to expose JSON CRUD tools and atomic writes.
  Status: DONE 2026-03-15 — Full rewrite to v2.0.0: 5 new tools (get_state, add_task, update_task_status, add_stamp, set_project_focus) + 2 legacy tools preserved. Single-writer pattern via readState/writeState. [TEST_PASSED] 125/125.
- [x] E-80: Implement "Markdown View Generator" inside `task-synchronizer-mcp`.
  Status: DONE 2026-03-15 — regenerateMarkdown() rebuilds TASKS.md (grouped by owner) and REVIEWS.md (from stamps[]) after every state mutation. Guards against clobbering during migration.
- [x] E-81: Update `blueprint-aligner-mcp` and `hooks/post-commit.sh` to read/write JSON state instead of regex parsing.
  Status: DONE 2026-03-15 — TIER3_NO_SECURITY_REVIEW reads state.json first (structured query for tier===3 DONE tasks + SEC_PASS stamps), falls back to legacy TASKS.md regex. post-commit.sh updates state.json via inline Node.js after TASKS.md sed.
- [x] E-82: Add explicit stress tests to `mcp_test.sh` for concurrent atomic JSON writes.
  Status: DONE 2026-03-15 — tests/suites/state_json_test.sh: 19 tests (T-02.01–T-02.10) covering schema validation, nextId logic, concurrent write stress test (proves race condition: ~7/10 tasks land), serialized write correctness, stamp integrity, regenerateMarkdown output, corrupt JSON recovery. [TEST_PASSED] 144/144.
- [x] E-83: Expose `validate_blueprint_section` in `blueprint-aligner-mcp` to enforce schema depth.
  Status: DONE 2026-03-15 — 6-component schema check (concept, data model, API, flow, errors, security). VALID if ≥4/6 present. 7 new tests (T-03.01–T-03.05c). [TEST_PASSED] 151/151.
- [x] E-84: Update `architectural-aligner/SKILL.md` to mandate `validate_blueprint_section` on new writes.
  Status: DONE 2026-03-15 — Added "Blueprint Depth Validation (P-41 §28)" section with mandatory validation gate.
- [x] E-85: Update `prd_writer` to hard-block E-## task generation until blueprint passes validation.
  Status: DONE 2026-03-15 — Added "Blueprint Validation Gate" with HARD BLOCK: no E-## tasks until VALID.
- [x] E-86: Update `blueprint-aligner-mcp` to expose `generate_implementation_delta`.
  Status: DONE 2026-03-15 — generate_implementation_delta tool: compares diff vs blueprint, extracts files/functions/tools, detects divergences.
- [x] E-87: Update `orchestrator-mcp`'s `run_handover` to save implementation deltas to `state.json`.
  Status: DONE 2026-03-15 — run_handover generates delta from git diff, saves to state.json deltas[] with read:false.
- [x] E-88: Update `ai-preflight` to extract and display unread deltas from `state.json`.
  Status: DONE 2026-03-15 — ai-preflight SKILL.md step 5 + run_preflight reads/marks deltas. Architect sees divergences on next session.
- [x] E-89: Replace execSync with spawnSync (whitelisted args) in blueprint-aligner-mcp, orchestrator-mcp, and risk-analyzer-mcp. Satisfies §5 Execution Sandbox mandate. | Tier: 2
  Status: DONE 2026-03-16 — Replaced execSync with spawnSync (whitelisted array args) in blueprint-aligner-mcp, orchestrator-mcp, and risk-analyzer-mcp.
- [x] E-90: Expand architect.md §17.1 Shared Skills Architecture with: directory structure, required YAML frontmatter fields, when to create shared vs agent-specific skills, install/sync pickup mechanism, and required Gemini .toml wrapper pattern. | Tier: 1
  Status: DONE 2026-03-16 — Expanded architect.md §17.1 with directory layout, YAML frontmatter fields, shared vs agent-specific decision table, install/sync pickup, and Gemini .toml wrapper pattern.
- [x] E-91: Bulk Update: Fix YAML frontmatter in all src/claude/agents/*.md and src/gemini/agents/*.md files to include mandatory §17.1.2 fields (disable-model-invocation, user-invocable, allowed-tools, context, agent). Use src/templates/SKILL.md as the reference schema. | Tier: 1
  Status: DONE 2026-03-16 — Bulk updated YAML frontmatter in all 19 agent files: renamed tools: → allowed-tools:, added disable-model-invocation, user-invocable, context, agent fields.
- [x] E-92: Implement `ai update --votu` (Voice of the User) in `src/bin/ai`. Capture terminal buffer or prompt for chat log, then pass to `intent-refiner-mcp::refine_intent` and write result to `UPDATE.md`. | Tier: 2
  Status: DONE 2026-03-16 — Implemented ai update --votu: reads chat log from stdin, extracts structured intent via python3, writes UPDATE.md with Add/Modify/Remove/Constraints sections.
- [x] E-93: Update `ai init` in `src/bin/ai` to be "Structured-First": automatically call `ai mcp-setup` and `ai migrate-state --force` after scaffolding. | Tier: 1
  Status: DONE 2026-03-16 — ai init now auto-calls do_migrate_state --force after mcp-setup when .ai/TASKS.md exists. Structured-First onboarding fully automated.
- [x] E-94: Add `--repair` flag to `ai doctor`: trigger fresh `npm install` and `.mcp.json` realignment for registered servers that fail health checks (§20.1). | Tier: 1
  Status: DONE 2026-03-16 — Added --repair flag to ai doctor: triggers npm install for broken MCP servers and realigns .mcp.json. Dispatch updated to pass args through.
- [x] E-95: Enforce "Markdown as Read-Only": Implement `verify_markdown_sync()` in `task-synchronizer-mcp` and update `hooks/pre-commit.sh` to block commits if `TASKS.md` or `REVIEWS.md` diverge from `state.json`. | Tier: 2
  Status: DONE 2026-03-16 — Added verify_markdown_sync tool to task-synchronizer-mcp; updated pre-commit hook with sync check warning gate for Markdown-as-Read-Only enforcement.
- [x] E-96: Upgrade pre-commit.sh check_markdown_sync() from warn-only to BLOCK: verify generated header AND compare task count between state.json and TASKS.md; exit 1 on divergence | Tier: 2
  Status: DONE 2026-03-16 — Upgraded check_markdown_sync() in pre-commit.sh to BLOCK (exit 1) on missing generated header or task count drift >2 vs state.json. Both checks use python3 for JSON parsing.
- [x] E-97: Add --stdin CLI mode to intent-refiner-mcp so ai update --votu can call node intent-refiner-mcp/index.js --stdin instead of duplicating logic in Python; update src/bin/ai accordingly | Tier: 2
  Status: DONE 2026-03-16 — Added --stdin CLI mode to intent-refiner-mcp/index.js; updated ai update --votu in src/bin/ai to route through node intent-refiner-mcp/index.js --stdin with python3 fallback.
- [x] E-98: Fix registry.json task-synchronizer-mcp allowed-tools to include verify_markdown_sync and archive_done_tasks; add test assertion in mcp_test.sh verifying all 9 tools are listed | Tier: 2
  Status: DONE 2026-03-16 — Added verify_markdown_sync and archive_done_tasks to task-synchronizer-mcp allowed-tools in registry.json; added 2 E-98 assertions to mcp_test.sh (19/19 pass)
- [x] E-99: Refactor orchestrator-mcp run_handover to stop writing TASKS.md directly; extract shared writeState+regenerateMarkdown helper into src/mcp/shared/state-writer.js and import from both MCPs | Tier: 2
  Status: DONE 2026-03-16 — Created src/mcp/shared/state-writer.js with readStateStrict/writeState/regenerateMarkdown; orchestrator-mcp run_handover now imports and uses writeState instead of regex-writing TASKS.md directly
- [x] E-100: Extend pre-commit check_markdown_sync() to also block on REVIEWS.md divergence when state.stamps.length > 0 but REVIEWS.md lacks the generated header | Tier: 2
  Status: DONE 2026-03-16 — Extended check_markdown_sync() in pre-commit.sh with Check 3: blocks on REVIEWS.md missing generated header when state.stamps.length > 0
- [x] E-101: Audit src/claude/skills/ and src/shared/skills/ for §17.1.2 YAML frontmatter compliance; bulk-update ci_gate, dependency_gate, scope_safety, obs_baseline, copilot skill files with missing required fields | Tier: 1
  Status: DONE 2026-03-16 — Audited all 5 targeted skill files (ci_gate, dependency_gate, scope_safety, obs_baseline, copilot) — all already have full §17.1.2-compliant YAML frontmatter; no changes needed
- [x] E-102: Add tests/suites/verify_sync_test.sh with ≥5 assertions covering verify_markdown_sync PASS/FAIL scenarios: header missing, count drift >2, stamp count mismatch, zero-stamps clean | Tier: 2
  Status: DONE 2026-03-16 — Created tests/suites/verify_sync_test.sh with 8 assertions covering PASS/FAIL for header-missing, count-drift >2, stamp-header-missing, zero-stamps clean scenarios — 8/8 pass
- [x] E-103: Update orchestrator-mcp run_preflight to include state.json summary (task counts by status, last 3 stamps) as a 5th section alongside the 4 markdown file reads | Tier: 1
  Status: DONE 2026-03-16 — Added state.json summary section to run_preflight output: task counts by status, last 3 stamps, current focus — structured data preferred over TASKS.md markdown view
