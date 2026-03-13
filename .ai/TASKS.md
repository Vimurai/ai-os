# TASKS (Ordered work)

Rules:
- Planner (Gemini) adds tasks with prefix P-##
- Engineer (Claude) adds tasks with prefix E-##
- Tester (TestSprite) adds tasks with prefix T-##
- **v2 MANDATE**: Engineer must update status here after every commit.

## Architect (Gemini)
- [x] P-01: Blueprint for `ai-exec` isolation (Git Worktrees) and `CAPABILITIES.md` schema
- [x] P-02: Update `post-tool-log.sh` blueprint to include `[SECURITY]` tags for `EXECUTE` operations
- [x] P-06: Blueprint for "Vision & Memory" Skillsets (`ux_reviewer.md`, `knowledge_architect.md`)
  Status: DONE 2026-03-10 — Section 17.2, 17.3 in architect.md
- [x] P-07: Blueprint for Skills 2.0 Modular Migration
  Status: DONE 2026-03-10 — Section 16 in architect.md
- [x] P-08: Blueprint for `prd_writer` and `chaos_monkey` agents
  Status: DONE 2026-03-10 — Section 17.1, 17.4 in architect.md
- [x] P-09: Blueprint for AI-OS Slash Command Integration (Skills 2.0)
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

## Engineer (Claude)
- [x] E-01: Implement `ai-exec` CLI (Bash) based on P-01 blueprint
  Status: DONE 2026-03-07 — src/bin/ai-exec (worktree isolation, Gate 3, [SECURITY] logging)
- [x] E-02: Update `post-tool-log.sh` logic based on P-02 blueprint
  Status: DONE 2026-03-07 — hooks/post-tool-log.sh ([SECURITY] tags for EXECUTE tools)
- [x] E-03: Create `src/templates/CAPABILITIES.md` template based on P-01 schema
  Status: DONE 2026-03-07 — src/templates/CAPABILITIES.md (READ/WRITE/EXECUTE/network schema)
- [x] E-04: Implement `ai archive` CLI command based on blueprint
  Status: DONE 2026-03-07 — src/bin/ai (do_archive: moves to .ai/archive/YYYY-MM/ with timestamp)
- [x] E-05: Implement `ai review` CLI command based on blueprint
  Status: DONE 2026-03-07 — src/bin/ai (do_review claude|gemini: parallel critic + arch audit prompts)
- [x] E-12: Implement Gate 1 (Intent Gate) in `ai update` logic
  Status: DONE 2026-03-10 — src/bin/ai (intent_gate(): hash change detection, vagueness hard-block <8 words/no verb, Tier 3 soft-block, --force bypass, .ai/.update.hash)
- [x] E-13: Implement Gate 2 (Quality Gate) in Git `pre-commit` hook
  Status: DONE 2026-03-10 — hooks/pre-commit.sh ([CRITIC_STAMP] check, ≤7 days, blocks commit + prints ai review claude prompt); do_init installs to .git/hooks/pre-commit (chains existing hooks); doctor checks gate install status
- [x] E-14: Implement Gate 3 (Execution Gate) in `ai-exec` CLI
  Status: DONE (implemented as part of E-01)
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

## Blueprint Trace — Orphaned Agents (critic_arch P-1 resolution)
The following Claude agent files were modified without a corresponding blueprint entry in architect.md §17.
Adding explicit E-## trace entries so the blueprint-aligner can resolve the orphan warning.

- [x] E-37 [TRACE]: `src/claude/agents/claude_tasks.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
  Rationale: Agent existed before E-31; E-31 scope covered tools[] + trigger descriptions for ALL agents in src/claude/agents/. File was correctly modified as part of E-31's "5 Claude agents updated" deliverable.
- [x] E-38 [TRACE]: `src/claude/agents/devops_engineer.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
  Rationale: Same as E-37. Confirmed in E-31 status: "5 Claude agents updated with tools arrays + imperative trigger descriptions."
- [x] E-39 [TRACE]: `src/claude/agents/digest_updater.md` — trigger-based auto-calling frontmatter update (E-31 scope extension)
  Rationale: Same as E-37. All 5 Claude agents (chaos_monkey, claude_tasks, devops_engineer, digest_updater, security_engineer) were updated as a single atomic change in E-31.

## Quality Gate Escalation
- [x] E-40: Wire test harness so `ai test` can satisfy the 100% Quality Gate
  Status: DONE 2026-03-11 — tests/run.sh (master runner, bash 3 compatible, SUITE_RESULT parsing); tests/lib/assert.sh (assert_status/contains/exists/match/not_contains + assert_summary); tests/suites/cli_test.sh (7 assertions: version, usage, where, unknown cmd); tests/suites/mcp_test.sh (14 assertions: registry JSON, custom servers, .mcp.json generation + trailing newline); do_test() in src/bin/ai now executes tests/run.sh when present (TestSprite fallback preserved); [TEST_PASSED] 21/21

## P-16 Implementation
- [x] E-42: Implement `context-invoker-mcp` server (P-16)
  Status: DONE 2026-03-11 — src/mcp/context-invoker-mcp/ (activate_skill: multi-root Skills 2.0 + flat resolution from ~/.claude/skills/, ~/.gemini/skills/, ~/.ai-os/, src/ fallback; activate_agent: same pattern for ~/.claude/agents/; list_skills/list_agents discovery mode; not-found returns suggestions); registry.json updated (capability: READ); src/claude/CLAUDE.md updated with invocation section + skill/agent directory tables; [TEST_PASSED] 22/22

## P-17 through P-21 Implementation
- [x] E-43: Implement 5 new skills/agents + verify sync (P-17 to P-21 + E-41)
  Status: DONE 2026-03-11 — repo-oracle (src/gemini/skills/repo-oracle/SKILL.md); vibe_sentinel (src/claude/agents/vibe_sentinel.md); token-miser (src/shared/skills/token-miser/SKILL.md); identity_guardian (src/claude/agents/identity_guardian.md); architectural-aligner (src/gemini/skills/architectural-aligner/SKILL.md); install-ai-os.sh synced all to ~/.ai-os/; ai mcp-setup 8/8; [TEST_PASSED] 22/22

## 2026-03-12 Critic Review Follow-up

### P0 — Critical (must fix before next release)

- [x] E-44: Add unit tests for safe-exec-mcp BLOCK_RULES
  Owner: Claude | Tier: 3 | Area: mcp/safe-exec-mcp
  Status: DONE 2026-03-12 — tests/suites/safe_exec_test.sh (14 assertions: curl|bash, wget|bash, DROP TABLE, fork bomb, secret=); [TEST_PASSED] 92/92

- [x] E-45: Add unit tests for blueprint-aligner-mcp secret detection regex
  Owner: Claude | Tier: 3 | Area: mcp/blueprint-aligner-mcp
  Status: DONE 2026-03-12 — tests/suites/blueprint_aligner_test.sh (17 assertions: HARDCODED_SECRET + CAPABILITIES_BYPASS patterns); [TEST_PASSED] 92/92

### P1 — High Priority

- [x] E-46: Fix .gitignore — add .env, .env.local, *.key, *.pem, /node_modules
  Owner: Claude | Tier: 1 | Area: repo root
  Status: DONE 2026-03-12 — .gitignore updated with .env, .env.local, *.key, *.pem, /node_modules

- [x] E-47: Refactor TestSprite API_KEY in .mcp.json to use environment variable
  Owner: Claude | Tier: 2 | Area: config/.mcp.json + src/templates/.mcp.json
  Status: DONE 2026-03-12 — both .mcp.json and src/templates/.mcp.json updated to ${TESTSPRITE_API_KEY}

- [x] E-48: Add input validation in context-invoker-mcp for skill/agent names
  Owner: Claude | Tier: 2 | Area: mcp/context-invoker-mcp
  Status: DONE 2026-03-12 — validateName() added; rejects non-[a-z0-9_-] names and path traversal; tested in mcp_integration_test.sh

- [x] E-49: Add integration tests for all 8 MCP tool handlers
  Owner: Claude | Tier: 2 | Area: tests/suites
  Status: DONE 2026-03-12 — tests/suites/mcp_integration_test.sh (39 assertions: file exists + syntax + tool registration + registry + validation); [TEST_PASSED] 92/92

- [x] E-50: Set up CI pipeline (.github/workflows/test.yml)
  Owner: Claude | Tier: 2 | Area: .github/workflows
  Status: DONE 2026-03-12 — .github/workflows/test.yml (Node 20, npm install for all MCP dirs, bash tests/run.sh, .gitignore secret check)

- [x] E-51: Create src/gemini/commands/ .toml files for all Gemini skills
  Owner: Claude | Tier: 2 | Area: gemini/commands
  Status: DONE 2026-03-12 — architectural-aligner.toml + repo-oracle.toml created (8 existing + 2 new = 10 total)

- [x] E-52: Implement `ai-seo` skill integration based on P-26 blueprint
  Owner: Claude | Tier: 2 | Area: gemini/skills
  Status: DONE 2026-03-12 — src/gemini/skills/ai-seo/SKILL.md (AEO/LLMO audit: structured data, answer-optimization, entity clarity, robots.txt AI bot check, llms.txt); src/gemini/commands/ai-seo.toml

