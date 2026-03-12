# DIGEST (Token Saver Cache)

## Product
AI-OS: CLI framework scaffolding `.ai/` intelligence directories, configuring Claude/Gemini/TestSprite agents, and enforcing token-saving workflow hooks across any codebase.

## Stack
Bash (zero-dependency core), Markdown (file-based memory), Node.js + JSON (MCP servers), Git Worktrees (ai-exec isolation), Playwright (vibe/chaos audits), Skills 2.0 (YAML frontmatter modular skills).

## Triad Health
- Claude (Engineer): E-01–E-43 complete. E-44–E-51 queued from 2026-03-12 review.
- Gemini (Architect): P-01–P-25 complete. Senior Architect Standards enforced in GEMINI.md.
- TestSprite (Tester): 22/22 tests passing. 2 P0 gaps (safe-exec-mcp + blueprint-aligner-mcp untested).

## Current Focus (top 3 open tasks)
- E-44: Add unit tests for safe-exec-mcp BLOCK_RULES (P0 — security gate unverified)
- E-45: Add unit tests for blueprint-aligner-mcp secret detection regex (P0)
- E-46: Fix .gitignore — add .env, .env.local, *.key, *.pem, /node_modules (P1)

## Known Risks (from 2026-03-12 CRITIC_STAMP)
- P0: safe-exec-mcp BLOCK_RULES completely untested — security-critical gate has zero tests
- P0: blueprint-aligner-mcp secret detection regex untested — credential gate unverified
- P1: .mcp.json hardcoded "your-testsprite-api-key" — must use env var (E-47)
- P1: .gitignore missing .env, *.key, *.pem, /node_modules entries (E-46)
- P1: context-invoker-mcp skill/agent names not validated — path traversal possible (E-48)
- P1: All 8 MCP tool handlers untested — ~5% total coverage (E-49)
- P1: No CI pipeline — .github/workflows/ empty (E-50)
- P1: src/gemini/commands/ missing — Gemini CLI slash commands non-functional (E-51)

## Last Review
2026-03-12 | [CRITIC_STAMP] | Parallel critics (arch + security + tests) | 0 P0 security | 2 P0 test gaps | 6 P1 total | Arch Grade: A

## Recent Changes
- 2026-03-12: E-44–E-51 recorded in TASKS.md from parallel critic review findings
- 2026-03-12: [CRITIC_STAMP] written to REVIEWS.md — parallel 3-critic review complete
- 2026-03-12: Auto-dispatch + Mid-Execution Orchestration + Parallel Agent Teams added to CLAUDE.md + GEMINI.md
- 2026-03-12: 4 new agents created (decision_recorder, review_synthesizer, task_validator, memory_curator)
- 2026-03-12: ai-update-lifecycle shared skill created
- 2026-03-12: P-22–P-25 DONE — GEMINI.md Senior Architect Standards, prd_writer refinement, architect.md.template expanded
- 2026-03-11: E-28–E-43 DONE — Skills 2.0, Gemini .toml commands, shared skills, UACS MCPs, context-invoker-mcp

2026-03-12: DIGEST regenerated after parallel critic review (critic_arch + critic_security + critic_tests)
