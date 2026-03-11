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
- [ ] P-09: Blueprint for AI-OS Slash Command Integration (Skills 2.0)
  Status: PENDING


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
- [ ] E-28: Implement Slash Commands for `ai` operations (`update`, `test`, `review`, `archive`, `digest`, `preflight`) as Skills 2.0 modules under `src/claude/skills/` and `src/gemini/skills/` based on P-09 blueprint.
  Status: PENDING

