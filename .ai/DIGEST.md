# DIGEST — AI-OS v2 (Updated: 2026-03-12)

## Product
AI-OS: CLI framework scaffolding `.ai/` intelligence directories, configuring Claude/Gemini/TestSprite agents, and enforcing token-saving workflow hooks across any codebase.

## Stack
Bash (zero-dependency core), Markdown (file-based memory), Node.js + JSON (MCP servers), Git Worktrees (ai-exec isolation), Playwright (vibe audits), Skills 2.0.

## Triad Health
- Architect (Gemini): P-26 (ai-seo integration blueprint) complete.
- Engineer (Claude): E-44–E-52 queued. E-01–E-43 complete.
- Tester (TestSprite): 22/22 tests passing. 2 P0 test gaps remain (safe-exec, blueprint-aligner).

## Current Focus
- E-44: Add unit tests for safe-exec-mcp BLOCK_RULES (P0)
- E-45: Add unit tests for blueprint-aligner-mcp secret detection regex (P0)
- E-52: Implement ai-seo skill integration based on P-26 blueprint

## Key Decisions
- Third-party skills (like ai-seo) will be integrated directly into `src/gemini/skills/` and exposed via Gemini `.toml` commands for auto-dispatch (P-26).

## Known Risks
- P0: safe-exec-mcp BLOCK_RULES completely untested — security-critical gate has zero tests
- P0: blueprint-aligner-mcp secret detection regex untested — credential gate unverified
- P1: .mcp.json hardcoded "your-testsprite-api-key" — must use env var (E-47)
- P1: .gitignore missing .env, *.key, *.pem, /node_modules entries (E-46)
- P1: context-invoker-mcp skill/agent names not validated — path traversal possible (E-48)

## MCP Servers
filesystem, memory, TestSprite, vibe-check-mcp, intent-refiner-mcp, task-synchronizer-mcp, safe-exec-mcp, blueprint-aligner-mcp, context-guardian-mcp, risk-analyzer-mcp, context-invoker-mcp

## Recent Changes (last 10)
- 2026-03-12: P-26 created / architect.md updated for ai-seo integration (Gemini)
- 2026-03-12: E-52 added to TASKS.md for ai-seo implementation (Gemini)
- 2026-03-12: E-44–E-51 recorded in TASKS.md from parallel critic review findings (Claude)
- 2026-03-12: [CRITIC_STAMP] written to REVIEWS.md — parallel 3-critic review complete (Claude)
- 2026-03-12: Auto-dispatch + Mid-Execution Orchestration + Parallel Agent Teams added (Claude)