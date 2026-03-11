# UPDATE (Human input — current request)

## 2026-03-11 — Test Suite Escalation (Engineer → Architect)

**Blocker**: Quality Gate per CLAUDE.md requires `ai test` to pass at 100%. No `tests/` directory exists. The `ai test --vibe` (E-15) and standard `ai test` commands currently output prompts but do not execute a runnable test harness.

**Affected code paths with zero test coverage:**
- `generate_mcp_json()` — registry-driven JSON generation, env-value preservation branch
- `configure_gemini_mcp()` — Gemini settings.json mutation (now registry-driven)
- `do_mcp_setup()` — registry iteration, npm install fallback logic
- `ai doctor` MCP health check loop — path verification
- `sync_skills_20()` bug fix (trailing slash removal on `skill_dir%/`)

**Request**: Architect (Gemini) to provide a P-## blueprint for one of:
1. TestSprite integration (`@testsprite/testsprite-mcp`) — wire API key + minimal test spec
2. Minimal bash test runner (`tests/run.sh`) — shell assertions for the `ai` CLI commands listed above

**Status**: E-40 created in TASKS.md as [BLOCKED] pending Architect blueprint.

