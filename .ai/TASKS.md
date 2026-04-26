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
- [x] P-9: Blueprint the integration of 'Adaptive Thinking' (e.g., `think: \"max\"` or 'Deep Think') for the Architect phase to enhance planning depth, while maintaining standard execution speed for the Engineer. | Tier: 2
  Status: DONE 2026-04-21 — Created .ai/blueprints/capabilities.md to define Adaptive Thinking injection points for Gemini and Claude.
- [x] P-10: Blueprint the replacement/augmentation of Playwright-based `vibe-check-mcp` with native OS-level 'Computer Use' capabilities (e.g., Project Mariner/Claude Computer Use) for advanced visual UI QA. | Tier: 3
  Status: DONE 2026-04-21 — Created .ai/blueprints/capabilities.md to map out the computer-use-mcp integration for advanced visual UI QA via TestSprite.
- [x] P-11: Blueprint an **Agent-to-Agent (A2A) Bridge** (`advisor-mcp`) to enable the Advisor/Executor pattern. This will allow the Engineer (Claude) to synchronously query the Architect (Gemini) for mid-execution clarifications without dropping the session. | Tier: 2
  Status: DONE 2026-04-21 — Created .ai/blueprints/interop.md defining the A2A Bridge and advisor-mcp server for dynamic Architect queries.
- [x] P-12: Blueprint a **Human-in-the-Loop (HITL) Gate** (`approval-mcp`) to formalize execution pauses and user CLI prompts for high-risk Tier 3 operations. | Tier: 2
  Status: DONE 2026-04-21 — Created .ai/blueprints/interop.md defining the HITL approval-mcp server to pause high-risk execution loops.
- [x] P-13: Blueprint the integration of Explicit Context Caching (Prompt Caching) to permanently cache core `.ai/blueprints/` and SQLite schemas at the API layer, reducing token costs and JIT latency for repetitive agent turns. | Tier: 2
  Status: DONE 2026-04-26 — Created .ai/blueprints/caching.md defining Explicit Context Caching (Prompt Caching) to eliminate JIT latency.
- [x] P-14: Blueprint the migration of Triad communication (e.g., `TASKS.md` generation) to native Structured Outputs (JSON Schema) leveraging the 2026 API features to guarantee 100% deterministic state transitions and eliminate Markdown parsing brittleness. | Tier: 2
  Status: DONE 2026-04-26 — Created .ai/blueprints/structured-outputs.md defining the migration of state transitions to native Structured Outputs (JSON Schema).

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
- [x] E-6: Run the AI-OS installer/sync script (e.g. `install-ai-os.sh`) to deploy the recent `src/mcp/` bug fixes to the global `~/.ai-os/` directory, resolving the active verification-mcp warnings. | Tier: 1
  Status: DONE 2026-04-19 — Ran install-ai-os.sh to sync src/mcp/ fixes to ~/.ai-os/. All 16 MCP servers reinstalled, .mcp.json regenerated with absolute paths, Gemini frontmatter sanitized.
- [x] E-7: Update `.gemini/settings.json` and `.claude/settings.json` (or their respective API configuration wrappers) to inject the 'Adaptive Thinking' (`think: \"max\"`) parameter during the Architect phase per `.ai/blueprints/capabilities.md`. | Tier: 2
  Status: DONE 2026-04-21 — Added thinking_effort: "high" to .gemini/settings.json (Architect phase) and CLAUDE_THINKING_BUDGET_TOKENS: "0" to .claude/settings.json env (Engineer phase stays at standard speed) per capabilities.md blueprint.
- [x] E-8: Implement `computer-use-mcp` per `.ai/blueprints/capabilities.md` to augment TestSprite visual QA using native OS-level 'Computer Use' capabilities in a sandboxed headless environment. | Tier: 3
  Status: DONE 2026-04-22 — Implemented computer-use-mcp: 7 tools (capture_screen, left_click, right_click, double_click, type_text, key_press, health_check). Security: DISPLAY=:99 hardcoded, HOME=/tmp/computer-use-sandbox, keyboard sanitized, screenshots deleted immediately, startup exits on missing Xvfb. Registered in registry.json (D-002) and .mcp.json. CAPABILITIES.md updated. 34 new tests. Tier 3 critics: ARCH_PASS SEC_PASS TESTS_PASS.
- [x] E-9: Implement the `advisor-mcp` server as defined in `.ai/blueprints/interop.md` to provide Claude with an Agent-to-Agent (A2A) RPC bridge to query a headless Gemini instance mid-execution. | Tier: 2
  Status: DONE 2026-04-22 — Implemented advisor-mcp A2A bridge: ask_architect tool invokes gemini -p with architect.md context pre-loaded, optional domain blueprint, [A2A_RULING] logged to LOG.md, graceful degradation when Gemini unavailable. Registered in registry.json and .mcp.json. 34 tests, 493/493 suite.
- [x] E-10: Implement the `approval-mcp` server as defined in `.ai/blueprints/interop.md` to enforce Human-in-the-Loop (HITL) CLI prompts for Tier 3 security operations flagged by safe-exec or trigger-audit. | Tier: 3
  Status: DONE 2026-04-24 — Implemented approval-mcp HITL gate: request_approval tool with Y/N terminal prompt, ANSI sanitization (T-HITL-001), hardcoded SQLite path ~/.ai-os/approvals.sqlite (T-HITL-002), stdin.isTTY assertion (T-HITL-003), SQLite write before MCP response (T-HITL-004), maxLength 200/500 with rejection (T-HITL-005). 37 tests, 531/531 suite. Tier 3: ARCH_PASS SEC_PASS TESTS_PASS.
- [ ] E-11: Implement API-level Explicit Context Caching per `.ai/blueprints/caching.md` by extending `token-budget-mcp` or creating a dedicated cache-manager. Ensure `.ai/blueprints/` and SQLite schemas are permanently cached. | Tier: 2
- [ ] E-12: Migrate Triad state communication to native Structured Outputs (JSON Schema) per `.ai/blueprints/structured-outputs.md`. Deprecate manual markdown editing for `TASKS.md` and `REVIEWS.md`, replacing it entirely with `task-synchronizer-mcp` schema validations. | Tier: 2
- [x] E-13: **Fix Missing Tool Wires**: The newly built MCP servers (`advisor-mcp`, `approval-mcp`, and `computer-use-mcp`) are registered but absent from all agent/skill YAML frontmatters. Update the `allowed-tools` arrays in `src/claude/agents/` and `src/claude/skills/` to explicitly grant access (e.g., `vibe_sentinel` needs `computer-use-mcp`, all core Claude agents need `advisor-mcp`, etc.) so they can actually be invoked. | Tier: 1
  Status: DONE 2026-04-26 — Updated allowed-tools in 5 agent YAMLs (vibe_sentinel, chaos_monkey, security_engineer, devops_engineer, critic_arch) to include advisor-mcp, approval-mcp, and computer-use-mcp tools; added 10 MCP tool permission entries to .claude/settings.json
