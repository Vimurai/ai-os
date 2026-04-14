# TASKS (Generated from state.json)

## Architect (Gemini)
- [x] P-1: Complete Sections 1-6 of architect.md replacing template boilerplate with the actual AI-OS System Philosophy and Technical Strategy. | Tier: 2
  Status: DONE 2026-04-14 — Replaced template boilerplate in Sections 1-6 with actual AI-OS philosophy, Triad Architecture, interaction flows, technical strategy, and MCP nervous system details.
- [x] P-2: Execute Section 34 (Architectural Fragmentation) by creating .ai/blueprints/mcp.md and mapping out all existing MCP tools. | Tier: 2
  Status: DONE 2026-04-14 — Created .ai/blueprints/mcp.md and accurately mapped all 16 MCP servers by core capabilities, security, and Git operations.
- [x] P-3: Create .ai/blueprints/agents.md and map the structures for Claude and Gemini agents and skills. | Tier: 2
  Status: DONE 2026-04-14 — Created .ai/blueprints/agents.md mapping all Claude, Gemini, and Shared skills and agents across the ecosystem.
- [x] P-4: Blueprint the monorepo structure (npm workspaces) to unify MCP server dependencies and resolve fragmentation. | Tier: 2
  Status: DONE 2026-04-14 — Created .ai/blueprints/workspace.md to define npm workspaces and deduplicate MCP dependencies.
- [x] P-5: Define the execution constraints and CI testing strategy for the Bootloader fallback layer to guarantee SQLite state validity. | Tier: 2
  Status: DONE 2026-04-14 — Created .ai/blueprints/bootloader.md to define execution constraints and CI tests for the fallback mechanism.
- [x] P-6: Update README.md — Add all registered MCP servers from .mcp.json (e.g., filesystem, memory, orchestrator-mcp, etc.) to the MCP Nervous System section to resolve documentation drift. | Tier: 1
  Status: DONE 2026-04-14 — Converted to E-4 (Architect forbidden from writing README.md).
- [x] P-7: Update CONTRIBUTING.md — Create the file and add development setup, skill/agent authoring guidelines (YAML frontmatter), git workflow, and ensure no ghost tools are referenced to resolve documentation drift. | Tier: 1
  Status: DONE 2026-04-14 — Converted to E-5 (Architect forbidden from writing CONTRIBUTING.md).
- [x] P-8: Update agents.md blueprint to explicitly state that Gemini YAML schema does not require `disable-model-invocation`, `user-invocable`, or `allowed-tools`. | Tier: 1
  Status: DONE 2026-04-14 — Added YAML schema note to agents.md clarifying Gemini frontmatter exemptions.

## Engineer (Claude)
- [x] E-1: Implement the monorepo workspace structure (npm/pnpm workspaces) across `src/mcp/*` per `.ai/blueprints/workspace.md`. | Tier: 2
  Status: DONE 2026-04-14 — Added root package.json with npm workspaces pointing to src/mcp/*. Hoists @modelcontextprotocol/sdk to a single shared install. npm test wired to bash tests/run.sh.
- [x] E-2: Implement the Bootloader fallback CI validation strategy and resilience tests per `.ai/blueprints/bootloader.md`. | Tier: 2
  Status: DONE 2026-04-14 — Extended resilience_test.sh with 6 new scenarios (T-RES-12–17): simulated node failure, Python/shell fallback verification, and PRAGMA integrity_check on state.sqlite. Suite grows from 11 to 17 tests. All 413 tests pass.
- [x] E-3: Fix verification-mcp bug where Claude-specific YAML fields are erroneously enforced on Gemini agents. Conditionalize the check based on the file path (`/gemini/` vs `/claude/`). | Tier: 1
  Status: DONE 2026-04-14 — Conditionalized verification-mcp required fields by path: Gemini skills (/gemini/) only require name+description; Claude/shared require all 5. Added T-05.08–11 tests. Suite 12→22 tests, 423/423 pass.
- [x] E-4: Update README.md — Add all registered MCP servers from .mcp.json (e.g., filesystem, memory, orchestrator-mcp, etc.) to the MCP Nervous System section to resolve documentation drift. | Tier: 1
  Status: DONE 2026-04-14 — Updated README.md MCP Nervous System section with all 19 registered servers grouped by category (State, Code, Safety, Intelligence, Quality). Updated test badge to 423/423.
- [x] E-5: Create CONTRIBUTING.md — Add development setup, skill/agent authoring guidelines (YAML frontmatter), git workflow, and ensure no ghost tools are referenced to resolve documentation drift. | Tier: 1
  Status: DONE 2026-04-14 — Created CONTRIBUTING.md with dev setup, project structure, Claude/Gemini skill frontmatter schemas, Ghost Tool rules, MCP server skeleton, git workflow, and test authoring guide.
