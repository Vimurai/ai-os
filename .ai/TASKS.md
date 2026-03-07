# TASKS (Ordered work)

Rules:
- Planner (Gemini) adds tasks with prefix P-##
- Engineer (Claude) adds tasks with prefix E-##
- Tester (TestSprite) adds tasks with prefix T-##
- **v2 MANDATE**: Engineer must update status here after every commit.

## Architect (Gemini)
- [x] P-01: Blueprint for `ai-exec` isolation (Git Worktrees) and `CAPABILITIES.md` schema
- [x] P-02: Update `post-tool-log.sh` blueprint to include `[SECURITY]` tags for `EXECUTE` operations

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
- [ ] E-12: Implement Gate 1 (Intent Gate) in `ai update` logic
  Status: Pending (Wait for E-10)
- [ ] E-13: Implement Gate 2 (Quality Gate) in Git `pre-commit` hook
  Status: Ready (E-05 done — unblocked)
- [ ] E-14: Implement Gate 3 (Execution Gate) in `ai-exec` CLI
  Status: DONE (implemented as part of E-01)
- [ ] P-06: Blueprint for "Vision & Memory" Skillsets (`ux_reviewer.md`, `knowledge_architect.md`)
  Status: Pending
- [ ] E-15: Implement `ai test --vibe` (Chaos & UX Stress) logic
  Status: Pending (Wait for P-06)
- [ ] E-16: Implement `vibe-check-mcp` (Node.js + Playwright) for autonomous auditing
  Status: Pending (Wait for E-15)
- [ ] E-17: Implement Universal Autonomous Command Suite (UACS) MCP suite
  Status: Pending (Wait for E-16)
- [ ] E-21: Implement Token-Saving Risk Tiers (TSRT) logic in `ai update` and `ai review`
  Status: Pending (Wait for E-17)
  - Sub-task: Create `risk-analyzer-mcp` for Tier classification
  - Sub-task: Implement gate skipping for Tier 1 and 2 tasks
  - Sub-task: Implement `intent-refiner-mcp`
  - Sub-task: Implement `safe-exec-mcp`
  - Sub-task: Implement `context-guardian-mcp`
  - Sub-task: Implement `blueprint-aligner-mcp`
