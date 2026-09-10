---
type: decisions
tags: [decisions, architecture, dependencies]
status: active
---

# DECISIONS (Append-only — architectural and dependency decisions)

---

## [[D-001]] — npm/pnpm Workspace Monorepo for src/mcp/*

**Date**: 2026-04-14
**Task**: [[E-1]]
**Decision**: npm workspaces (confirmed — matches blueprint [[workspace.md]] §2)

### Why needed
16 MCP servers in `src/mcp/` each carry their own `node_modules/`. Every server independently installs `@modelcontextprotocol/sdk` (and in some cases `zod`, `typescript`, `shell-quote`, `@playwright/test`). This creates 16x duplication, version drift risk, and a fragmented upgrade surface. An npm/pnpm workspace at the project root hoists shared deps to a single location and enforces a unified version resolution.

### What changes
- A new `package.json` is added at the repository root with `"workspaces": ["src/mcp/*"]`.
- No new third-party packages are installed — only existing packages are reorganised under workspace hoisting.
- Each MCP server retains its own `package.json` for metadata and runtime entry point; no coupling is introduced at the runtime layer.

### Alternatives considered
1. **Do nothing** — 16 fragmented installs; version drift is a known risk (see `.ai/REVIEWS.md` ARCH_AUDIT 2026-04-14). Rejected.
2. **Symlink approach (manual)** — brittle; does not handle transitive deps. Rejected.
3. **pnpm workspaces** — equivalent to npm workspaces for this use case; requires installing pnpm globally. Lower friction to use npm workspaces since Node.js 16+ ships npm 7+ with native workspace support. Preferred option pending human decision.
4. **npm workspaces (chosen draft)** — zero new tooling required; hoisting is deterministic; lock file is unified at root. Strongly preferred.

### Size / weight
- No net-new dependencies. Reduces total `node_modules` disk footprint by approximately 15x (16 copies → 1 hoisted copy of `@modelcontextprotocol/sdk`).
- Root `package.json`: ~200 bytes. No runtime impact.

### Security track record
- npm workspaces is a built-in npm feature (no third-party package). No CVE surface added.
- `@modelcontextprotocol/sdk` — already present across all servers; version pinning via a single root lock file improves auditability.

### Maintenance status
- npm workspaces: maintained as part of Node.js core toolchain. No separate release cadence.

### License
- npm (ISC) — already in use. No new license introduced.

### Rollback plan
- Delete root `package.json` and `package-lock.json`. Each MCP server's own `package.json` remains untouched. Run `npm install` inside each `src/mcp/<server>/` directory to restore isolated installs. No source code changes required.

---

## [[D-002]] — computer-use-mcp: New MCP Server for Native Computer Use ([[E-8]])

**Date**: 2026-04-21
**Task**: [[E-8]]
**Decision**: computer-use-mcp (confirmed 2026-04-21)

### Why needed
`vibe-check-mcp` uses Playwright (DOM/headless Chrome scraping) for visual QA. This approach misses native UI elements, OS-level dialogs, and non-web surfaces. The blueprint ([[capabilities.md]] §2) mandates augmenting vibe-check-mcp with native OS-level Computer Use capabilities so TestSprite can visually assert UI state without DOM coupling — aligning with Project Mariner / Claude Computer Use.

### Alternatives considered
1. **Extend Playwright** — DOM scraping; can't interact with native OS windows, Electron chrome, or non-web surfaces. Rejected.
2. **Screenshot diffing (pixelmatch/resemble.js)** — no interaction capability; brittle to font/DPI changes. Rejected.
3. **Selenium + OS-level driver** — heavyweight; no AI-native interaction model. Rejected.
4. **computer-use-mcp (chosen draft)** — wraps the Claude Computer Use API (screen capture + coordinate click + keyboard) in an MCP server; sandboxed to a headless X11/Wayland virtual display. Directly integrates with the Triad AI loop. Strongly preferred per blueprint.

### Size / weight
- New MCP server at `src/mcp/computer-use-mcp/` (~300–500 LOC Node.js).
- Runtime deps: `@anthropic-ai/sdk` (already hoisted in workspace), `xvfb` (virtual display, system-level, no npm package), optionally `screenshot-desktop` (~15KB npm).
- No net-new npm packages beyond what is already in the workspace.

### Security track record
- Anthropic SDK: actively maintained, no known critical CVEs as of 2026-04.
- X11/Xvfb virtual display: isolation boundary between agent and host display. Well-understood Linux subsystem.
- **Key risk**: if sandbox escapes, agent can interact with host machine. Mitigation: strict `DISPLAY` env var isolation + sandboxed headless buffer only — no access to `$DISPLAY=:0` (host display). Reviewed by `security_engineer` gate (mandatory for Tier 3).

### Maintenance status
- Anthropic SDK: actively maintained by Anthropic. Monthly releases.
- Xvfb: part of X.Org project; stable, minimal churn.

### License
- Anthropic SDK: MIT — compatible.
- Xvfb: MIT/X11 — compatible.

### Rollback plan
- Delete `src/mcp/computer-use-mcp/` directory and remove its entry from `src/config/registry.json` and `.mcp.json`. Re-run `bash install-ai-os.sh` to sync. vibe-check-mcp (Playwright) remains intact and resumes as the sole visual QA tool.

---

## [[D-003]] — approval-mcp: No New Dependencies ([[E-10]])

**Date**: 2026-04-24
**Task**: [[E-10]]
**Decision**: No new npm packages — Node.js built-ins only (confirmed 2026-04-24)

### Why needed
`approval-mcp` implements the HITL gate for Tier 3 operations. It needs: (1) an interactive terminal prompt for Y/N approval, (2) persistent approval/rejection audit log in SQLite.

### Alternatives considered
1. **`inquirer` / `prompts` npm packages** — interactive CLI prompts; adds ~500KB. Rejected — `readline` (built-in) covers the Y/N use case with zero footprint.
2. **`better-sqlite3`** — npm package for SQLite. Rejected — `node:sqlite` (Node.js 22+ built-in, already used by token-budget-mcp) covers the use case with zero new install surface.
3. **`node:readline` + `node:sqlite` (chosen)** — both are Node.js built-ins; zero new npm dependencies; no install, no CVE surface, no license risk.

### Size / weight
- Zero net-new npm packages. No increase in `node_modules` footprint.

### Security track record
- `node:readline`: Node.js core, no CVE surface.
- `node:sqlite`: Node.js 22+ built-in; same audit surface as the Node.js runtime itself.

### Maintenance status
- Both modules maintained as part of the Node.js core team release cadence.

### License
- Node.js built-ins: MIT — compatible.

### Rollback plan
- Delete `src/mcp/approval-mcp/` and remove from `registry.json` / `.mcp.json`. No npm uninstall required.

---

## [[D-004]] — cache-manager-mcp: Dedicated MCP Server vs. token-budget-mcp Extension

**Date**: 2026-04-27
**Task**: [[E-11]]
**Decision**: New dedicated `cache-manager-mcp` server (no new npm packages — SDK already hoisted)

### Why needed
Blueprint [[caching.md]] §3 specifies that the cache payload (`.ai/blueprints/*.md`, `architect.md`, `state.sqlite` schema, `registry.json`) must be pre-assembled and persisted so agents can include it as a long-lived system prompt prefix — enabling Anthropic's prompt caching to eliminate per-turn JIT read costs.

### Alternatives considered
1. **Extend `token-budget-mcp`** — token-budget-mcp tracks cost/spend; caching is a separate concern (file I/O, mtime tracking, context assembly). Mixing them violates single-responsibility and would bloat a server already wired into every agent. Rejected.
2. **Dedicated `cache-manager-mcp` (chosen)** — clean boundary; follows the established pattern of all other AI-OS MCP servers. Allows capability = READ (no WRITE or EXECUTE escalation needed). No new external dependencies. Preferred.

### What it adds
- `build_cache(project_root?)` — force-rebuilds the System Context blob and persists it with file mtimes.
- `get_cached_context(project_root?)` — returns cached blob; auto-rebuilds on mtime change or new blueprint file.
- `invalidate_cache()` — marks cache stale without rebuilding.
- `get_cache_status()` — observability: age, file count, char/token estimate, tracked mtimes.

### Security properties
- `DB_PATH` hardcoded to `~/.ai-os/cache.sqlite` — no user-controlled path.
- `project_root` validated: must be absolute, no `..` traversal, must exist.
- All file reads use `readFileSync` — no `execSync`, no shell.
- SQLite schema extracted via `sqlite_master` query (not `.schema` shell command).

### Rollback plan
- Delete `src/mcp/cache-manager-mcp/` and remove from `registry.json` / `.mcp.json`. No npm uninstall required.

---

## [[D-005]] — Call-by-Reference Git Hooks via Execution Stubs

**Date**: 2026-05-05
**Task**: [[P-20]]
**Decision**: Replace copy-by-value hook installation with dynamic execution stubs that source `~/.ai-os/hooks/`.

### Why needed
The existing hook installation copied the global `~/.ai-os/hooks/pre-commit.sh` script into the project's `.git/hooks/pre-commit`. This resulted in split-brain drift: when the canonical global script updated, local projects were left running an outdated version unless `ai init` was manually re-run. This caused stale quality gates to silently pass.

### Alternatives considered
1. **Force symlinks (`ln -s`)** — requires specific OS permissions on some filesystems (e.g., Windows) and breaks if the target path format changes. Rejected.
2. **`ai sync` full copy** — requires `ai sync` to mutate the `.git/hooks` directory explicitly, taking overhead on every sync. Prone to local manual edits being lost without warning. Rejected.
3. **Execution Stub (chosen)** — generating a minimal bash wrapper that simply executes the global path. Reliable across UNIX environments, trivially updatable, and gracefully handles custom chained hooks without mutating the canonical source.

### Constraints driving this decision
- **Consistency**: All projects on a single machine must enforce the exact same pre-commit quality gate logic (Gate 2).

### Impact
- Unlocks: [[E-41]] (Implementing the stub generator and auto-upgrader).
- Risk if wrong: If `~/.ai-os/hooks/` is corrupted or missing, all local commits in stubbed repositories could fail or bypass the gate depending on the stub's error handling.

### Rollback
Delete `.git/hooks/pre-commit` in the local repository and recommit without the gate.

---

## [[D-006]] — Hybrid Env Var + MCP Routing for Framework Tasks

**Date**: 2026-05-10
**Task**: [[P-38]]
**Decision**: Route framework-level tasks via `task-synchronizer-mcp` using `$AIOS_WORKSPACE` and `is_framework_task` payload flag.

### Why needed
AI-OS framework development requires routing tasks to the global repository (`ai-os-v2`) even when a developer identifies an issue while working inside a local project workspace. A mechanism was needed to map `~/.ai-os/` path intents to the correct `TASKS.md`.

### Alternatives considered
1. **Skill-Level CWD Switch** — The `task-planner` skill instructs the agent to `cd` into the framework directory before writing. Brittle, breaks agent context loop. Rejected.
2. **Global Spooling** — Write to `~/.ai-os/framework_tasks.sqlite` and manually sync later. High friction, requires explicit sync step. Rejected.
3. **Hybrid Env Var + MCP (Chosen)** — The `task-planner` tags the payload; the MCP router checks `$AIOS_WORKSPACE` and overrides the SQLite/Markdown paths transparently. Keeps agent logic simple and execution deterministic.

### Constraints driving this decision
- **Developer UX**: The agent should seamlessly record framework tasks without the developer switching projects manually.

### Impact
- Unlocks: E-62, E-63, E-64 (Framework Task Routing Implementation).
- Risk if wrong: If `$AIOS_WORKSPACE` path resolution fails, tasks may corrupt local state or throw errors.

### Rollback
Set `AIOS_WORKSPACE_DISABLE=1` to force all tasks into the local project.

---

## [[D-007]] — JIT Aggregation for Incident Tracker

**Date**: 2026-05-10
**Task**: [[P-38]]
**Decision**: Aggregate `incidents.ndjson` Just-In-Time (JIT) during `ai-preflight` to propose recurrent incident P-## tasks.

### Why needed
We need to track and resolve recurrent errors across the Triad. A system must autonomously identify high-frequency incidents and draft P-## tasks for the Architect without causing token bloat.

### Alternatives considered
1. **Background Aggregator Agent** — A cron job or background daemon analyzes the NDJSON periodically. Adds operational overhead and requires a persistent background process. Rejected.
2. **JIT Aggregation (Preflight/Sync)** — Hook into the existing `ai-preflight` phase. Extremely lightweight, surfaces issues exactly when the developer and Architect are ready to start a session. Chosen.

### Constraints driving this decision
- **Performance**: Must parse quickly (<50ms) to not slow down the bootloader.

### Impact
- Unlocks: E-65, E-66, E-67 (Incident Tracker Implementation).
- Risk if wrong: If the log bloats, the preflight hook could slow down session start.

### Rollback
Toggle `AI_INCIDENT_TRACKER_DISABLE=1` env variable or manually delete `incidents.ndjson`.

---

## [[D-008]] — Tree-sitter via WASM (web-tree-sitter) for the AST Repository Map ([[E-95]])

**Date**: 2026-05-27
**Task**: [[E-95]] (blueprint `ast-repository-map.md`)
**Decision**: **Add `web-tree-sitter` (WASM) + `tree-sitter-wasms` (prebuilt JS/TS grammar `.wasm` bundle).** Chosen by the human over native bindings. A deliberate, scoped exception to [[D-003]] ("No New Dependencies").

### Why needed
`ast-repository-map.md` mandates Tree-sitter to extract structural signatures (exports/classes/methods/imports) for a token-compressed `REPO_MAP.md`. A correct multi-language parser is not reasonably implementable in-house — hand-rolled regex parsing of TS/JS is brittle and is exactly the failure mode the blueprint exists to replace.

### Alternatives considered
1. **Implement it ourselves (regex/heuristics)** — brittle on real TS/JS (generics, decorators, JSX); high maintenance. Rejected.
2. **Native `tree-sitter` bindings** — faster, but require `node-gyp` + a C toolchain and ship platform-specific binaries, breaking the drop-in-installer portability promise across macOS/Linux/Windows/CI. Rejected by the human.
3. **`web-tree-sitter` (WASM) + `tree-sitter-wasms`** — pure-WASM, no native build, portable; grammars load from prebuilt `.wasm`. **Chosen.**

### Size / weight
`web-tree-sitter` ships a small JS loader + `tree-sitter.wasm` runtime (~1 MB). `tree-sitter-wasms` bundles many grammar `.wasm` files (a few MB) but only `javascript` + `typescript` are loaded at runtime.

### Security track record
Tree-sitter is widely deployed (GitHub code-nav, Neovim, Aider). The WASM runtime runs grammars in a sandboxed VM (no FS/network). No notable CVEs for the parser core. Parsing is bounded per the blueprint (≤500 ms/file, skip >1 MB / minified) to prevent DoS; `.gitignore`/`.env*` are respected so secrets are never indexed.

### Maintenance status
`web-tree-sitter` **pinned to `0.20.8`** (not the latest `0.26.9`): the `0.26` runtime's dylink ABI rejects `tree-sitter-wasms@0.1.13`'s prebuilt grammars (built against the tree-sitter 0.20-era ABI). `0.20.8` is the battle-tested combo used by Aider/continue.dev. `tree-sitter-wasms@0.1.13` (modified 2025-10-07, maintained community bundle). Revisit the pin if/when `tree-sitter-wasms` ships 0.25+-ABI grammars.

### License
`web-tree-sitter`: MIT. `tree-sitter-wasms`: Unlicense (public domain). Both compatible.

### Impact
- Unlocks: E-95 (`ast-parser-mcp`), E-96 (ranking), E-97 (`generate_map`), E-98 (sync/preflight wiring).
- **E-98 update**: the 3 grammar `.wasm` are now VENDORED into `src/mcp/ast-parser-mcp/grammars/` (~5 MB, tracked) so the installed `~/.ai-os` server is self-contained. `tree-sitter-wasms` is therefore a **devDependency** (build-time source of the `.wasm`), not a runtime dep. The only runtime npm dep is `web-tree-sitter`, and the `--generate-map` CLI path lazy-loads the MCP SDK so the `ai sync` hook needs neither the SDK nor any root-hoisted package.

### Rollback
`npm rm web-tree-sitter tree-sitter-wasms`, delete `src/mcp/ast-parser-mcp/`, set `AI_OS_DISABLE_REPO_MAP=1` (blueprint rollback). Agents fall back to `grep`/`list_directory`.

---

## D-037 — Global Hook-Level Telemetry Instrumentation

**Date**: 2026-06-01
**Task**: P-2
**Decision**: Shift the primary instrumentation point for tool telemetry from the `mcp-router` (internal) to the `post-tool-use.sh` bash hook (global edge).

### Why needed
Current telemetry only captures tools routed through `mcp-router::proxy_call` (~1% of total activity). The "Second Brain" is system-blind to direct MCP calls made by Claude Code or other agents. Moving to the hook layer ensures 100% visibility of all tool executions.

### Alternatives considered
1. **Router Proxy-by-Default** — Rejected: Requires forcing all agents to route all calls through the router, adding latency and a single point of failure for basic operations like filesystem reads.
2. **Claude Code Extension** — Rejected: Telemetry would be dependent on the specific client; hooks are more universal across the AI-OS platform.
3. **Global Hook Instrumentation** — Selected: Captures the ground truth of agent execution at the edge with near-zero latency and zero change to agent-to-tool routing logic.

### Constraints driving this decision
- **Visibility**: Must capture 100% of tool invocations for accurate meta-cognition analysis.
- **Performance**: Instrumentation must not add noticeable latency to the tool loop (<50ms).

### Impact
- Unlocks: E-104, E-105, E-106.
- Risk if wrong: Double-counting of tools that pass through both the hook and the router (mitigated by E-106 refactor).

### Rollback
Revert `hooks/post-tool-use.sh` to its original state and restore internal instrumentation in `mcp-router`.

---

## D-039 — Structural Diff & Dry-Run Patching

**Date**: 2026-06-02
**Task**: E-101 (Implicit bugfix during implementation)
**Decision**: `confirm_patch` now detects diffs by their unified-diff hunk-header signature (`@@ -n,m +n,m @@`) rather than a strict `---` prefix. Patch application uses a dry-run first and creates a `-b` backup for safe rollback.

### Why needed
The previous patching mechanism was brittle, occasionally misidentifying diff boundaries or applying destructive partial patches when hunks failed.

### Constraints driving this decision
- **Safety**: Need guaranteed rollback if a patch applies cleanly to some hunks but fails on others.
- **Robustness**: Support varied unified-diff header formats generated by LLMs.

---

## D-040 — Distributed Stamping for Tier-3 Critics

**Date**: 2026-06-02
**Task**: E-101 (Implicit bugfix during implementation)
**Decision**: Tier-3 critics (arch/security/tests) must persist verdicts exclusively via `add_stamp` (SQLite), never by appending directly to the regenerated `REVIEWS.md` view.

### Why needed
Appending directly to `REVIEWS.md` bypasses the ACID source of truth (`state.sqlite`). When `verify_markdown_sync` runs, it overwrites manual additions to `REVIEWS.md` based on the database stamps. Extending the E-72 distributed-stamping pattern ensures all critics use the unified data pipeline.

### Constraints driving this decision
- **Single Source of Truth**: All state and verdicts must live in `state.sqlite`.

---

## D-041 — Memory Palace Scan-on-Sync Observability

**Date**: 2026-06-09
**Task**: P-43 (Self-Learning Activation Arc)
**Decision**: The scan-on-sync seam (`.ai/memory/palace-index.json`) is maintained purely as an observability artifact.

### Why needed
The memory palace generation (`E-145`) writes a candidate manifest on sync. We needed to decide if the `memory_curator` agent should be wired to read this manifest or re-scan independently.

### Constraints driving this decision
- **Race conditions**: The `memory_curator` is a background agent. Coupling it to a sync-written manifest creates temporal dependencies.
- **Sovereignty**: The background curator must remain sovereign. It will scan sources independently, ignoring the manifest to avoid race conditions.

---

## D-042 — Defer performance-mcp Server

**Date**: 2026-06-09
**Task**: E-149 (performance_engineer implementation)
**Decision**: Defer the creation of the dedicated `performance-mcp` server.

### Why needed
The blueprint called for a dedicated `performance-mcp` server. The Engineer successfully implemented the `performance_engineer` and `ai-profile` skill using the existing `code-execution-mcp` Docker sandbox without needing a dedicated MCP server.

### Constraints driving this decision
- **Complexity**: Minimizing the footprint of new MCP servers if existing sandboxes suffice. The `code-execution-mcp` already provides the necessary V8 profiling and isolation.

---

## D-043 — DB-Migration Substrate

**Date**: 2026-06-09
**Task**: E-150 (db_architect implementation)
**Decision**: Standardize on `node:sqlite` within the `db_architect`'s local execution context rather than introducing a dedicated database-migration MCP server.

### Why needed
The database integrity architecture requires robust schema alterations. By using the built-in `node:sqlite` driver in conjunction with the system's execution tools, we avoid the overhead of a dedicated server while maintaining full transactional (BEGIN/COMMIT) control and rollback capabilities.

### Constraints driving this decision
- **Dependency Minimization**: No new npm packages needed.
- **Transactional Safety**: Executing migrations as self-contained Node scripts ensures that the script halts safely on validation errors and executes the `DOWN` script within the same boundary.

---

## D-044 — Conditional MCP Server Connections for Test Import Safety

**Date**: 2026-06-09
**Task**: E-160 (Prevent test hang)
**Decision**: Wrap the top-level `server.connect()` and `StdioServerTransport` instantiation inside all custom MCP servers (especially `blueprint-aligner-mcp`) in an `isMain` detection check so that importing these modules in unit tests does not block waiting for stdin.

### Why needed
Unit tests like `blueprint_aligner_test.sh` import helper functions (e.g. `parseDiffByFile`, `isMarkdownFile`, `isTestHelperFile`) directly from the MCP server entry points (e.g., `src/mcp/blueprint-aligner-mcp/index.js`). Because the server connection was unconditionally established in the global module scope, importing the module started the StdioServerTransport, causing tests to hang indefinitely in interactive terminal sessions where stdin remains open.

### Constraints driving this decision
- **Test Suitability**: Test suites must run successfully in all environments (interactive terminals, CI, background run-command tasks) without hanging or requiring specific stdin redirection (like `< /dev/null`).
- **Zero Impact on Production**: The MCP servers must still function exactly as before when launched directly via `node`.

---

## D-045 — Resilient Agent/Skill Invocation and Auto-Decision Rules

**Date**: 2026-06-09
**Task**: E-161 / E-162 (Agent Invocation Robustness)
**Decision**: Standardize and write guidelines into CLAUDE.md / GEMINI.md for automatic, dynamic skill and agent selection. Instruct the models to dynamically choose:
1. Native Antigravity tools (like `invoke_subagent` and `define_subagent`) when running in the `agy` runtime.
2. Custom MCP-backed tools (`activate_agent`, `activate_skill`) when running in Claude Code or Gemini CLI.
3. Automatically evaluate and decide when to run a skill (procedural workflow) vs. delegate to an agent (persona).

### Why needed
When running under `agy` (Antigravity), standard MCP tools (from `context-invoker-mcp`) are not reliably exposed, leading to permission or missing-tool errors that terminate execution. Providing resilient instructions allows agents to use native `invoke_subagent` tools instead of falling back to failing MCP calls, while guiding them to automatically use these tools at appropriate times.

### Constraints driving this decision
- **Resilience**: The platform must survive missing MCP tools by using native primitives.
- **Autonomy**: The agents must take initiative in deciding when to run reviews, audits, preflights, and logs without requiring manual user commands.

---

## D-046 — Antigravity Subagent Execution Robustness

**Date**: 2026-06-10
**Task**: E-163, E-164, E-165
**Decision**: Resolve native subagent runtime failures under the `agy` provider by:
1. Harvesting all referenced `mcp__*` tools from agent instructions and frontmatter to populate the subagent's `toolNames` in `agent.json`.
2. Deduplicating duplicate `ai-os` plugin imports in `~/.gemini/config/import_manifest.json`.
3. Performing a synchronous, serialized Google OAuth token refresh check in the parent CLI bootloader preflight before concurrent subagents are spawned.

### Why needed
Custom subagents (like `critic_arch`) were failing with execution termination errors because:
- They lacked permission to call MCP tools (such as `add_stamp`) because the generator omitted `mcp__*` tools from the subagent's `toolNames` manifest.
- The `ai-os` plugin was registered twice in `import_manifest.json` (from both `local-install` and `antigravity`), causing runtime namespace collisions.
- Concurrent subagent spawns were racing to refresh expired OAuth tokens in `oauth_creds.json`, causing write collisions and authentication failures.

### Alternatives considered
1. **Direct credentials injection into the subagent sandbox**: Rejected because the subagent sandbox has strict path-traversal and file-writing restrictions, and injecting raw secrets violates security policies.
2. **Serializing subagent execution**: Rejected because it increases total execution time and limits parallel performance (like running critics in parallel).
3. **Synchronous pre-refresh + dynamic tool harvesting**: Selected because pre-refresh avoids races entirely, and dynamic tool harvesting allows critics to securely call their required stamp tools without wildcards.

### Constraints driving this decision
- **Security**: Subagents must follow least-privilege, and raw Google credentials must not be exposed to the sandbox.
- **Concurrency**: Parallel critics must be supported without file write race conditions.

### Impact
- Unlocks: `E-163`, `E-164`, `E-165` tasks.
- Risk if wrong: Race conditions could still occur if tokens expire mid-execution, but a 5-minute pre-expiry buffer mitigates this.

### Rollback
Remove the token refresh pre-check and revert to the static `toolNames` list in `plugin-builder.mjs`.

---

## D-047 — Ratify E-177 Cache Eviction Reinterpretation

**Date**: 2026-06-20
**Task**: E-177
**Decision**: Ratify the Engineer's reinterpretation of the cache eviction logic to evict stale blueprints (oldest-first, >7 days old) rather than task records, utilizing the 20,000 character threshold.

### Why needed
The original blueprint for `cache-manager-mcp` eviction incorrectly specified pruning "done task records" when the cache actually stores blueprints and schema, not task records. Additionally, the blueprint had conflicting thresholds (5k vs 20k characters). The Engineer resolved this by evicting stale blueprints at the 20k threshold. This decision formalizes and accepts the new logic.

### Alternatives considered
1. **Evict task records** — Rejected: Task records are not managed by `cache-manager-mcp`, making this impossible without major architectural shifts.
2. **Use 5,000 character threshold** — Rejected: 5k is too restrictive for modern context windows and would cause unnecessary cache churn. 20,000 characters balances context limits with JIT capabilities.
3. **Ratify Engineer's implementation (Chosen)** — Aligns with the true behavior of the cache payload and utilizes the more appropriate 20k threshold.

### Constraints driving this decision
- **Context Size Constraints**: System context prefix must stay within reasonable limits (<20k characters) to leave room for conversational context.
- **Data Model Truth**: `cache-manager-mcp` does not store task velocity or execution rows, it caches blueprints.

### Impact
- Unlocks: Closes the known risk regarding E-177 ratification.
- Risk if wrong: Stale or important blueprints might be evicted if untouched for >7 days. JIT loads will still retrieve them if explicitly requested, but baseline context will drop them.

### Rollback
Revert the compaction logic in `cache-manager-mcp` or override the `20000` character limit to a higher threshold.

---

## D-048 — Ratify E-179 Telemetry Classification Refinement

**Date**: 2026-06-21
**Task**: E-179
**Decision**: Ratify the Engineer's refinement to `mcp-telemetry.mjs` where expected tool rejections (e.g. validation failures) marked with `_meta.expected_rejection` are booked as `SUCCESS` rather than `ERROR`. This cleans up the false-positive "deprecation candidate" signal in `INSIGHTS.md`.

### Why needed
The telemetry analysis correctly identified several tools (like `add_topic_seed`, `validate_payload`) with high `isError` rates. However, audit revealed these were not system errors but expected user-level validation rejections. Treating them as `ERROR` pollutes the telemetry and incorrectly flags healthy tools for deprecation. The short-term fix (`_meta.expected_rejection` -> `SUCCESS`) restores signal purity without requiring an immediate database migration.

### Alternatives considered
1. **Immediate status-taxonomy migration (`REJECTED`)** — Rejected: Requires a full `telemetry.sqlite` schema migration and updates to the `meta_analyst` SQL queries. While architecturally correct, it was too large for the E-179 scope.
2. **Book as `SUCCESS` via marker (Chosen)** — Cleans up the `INSIGHTS.md` report immediately with minimal friction.
3. **Ignore false positives** — Rejected: Degrades trust in the automated insights.

### Constraints driving this decision
- **Scope limitation**: Avoided triggering a full database migration mid-audit to resolve the immediate false-positive issue.

### Impact
- Unlocks: Reliable deprecation candidate signals.
- Risk if wrong: Booking rejections as `SUCCESS` temporarily obscures usage-friction signals (i.e. tools that users frequently misuse but aren't technically broken).

### Rollback
Remove the `_meta.expected_rejection` check in `mcp-telemetry.mjs` to revert to booking all `isError` returns as `ERROR`.

---

## D-049 — Ratify E-180 Telemetry Schema Migration (REJECTED/TIMEOUT)

**Date**: 2026-06-25
**Task**: E-180
**Decision**: Ratify the formal database migration of `telemetry.sqlite` to introduce `REJECTED` and `TIMEOUT` as explicit statuses in the telemetry schema.

### Why needed
The E-179 refinement booked expected rejections as `SUCCESS` to stop false-positive alerts, but this obscured valid usage-friction signals. Migrating to an explicit `REJECTED` and `TIMEOUT` status allows the `meta_analyst` to cleanly separate actual code crashes (`ERROR`) from expected tool validation blocks (`REJECTED`) and hangs (`TIMEOUT`).

### Alternatives considered
1. **Keep booking as SUCCESS** — Rejected: Loses friction analytics and degrades meta-cognition accuracy.
2. **Execute DB migration to REJECTED/TIMEOUT (Chosen)** — Cleans up the taxonomy properly and restores visibility into friction without triggering false "deprecation" warnings.

### Constraints driving this decision
- **Visibility vs Noise**: We need to see user friction (when validation blocks them) without the `meta_analyst` flagging the tool as broken.

### Impact
- Unlocks: E-180 implementation.
- Risk if wrong: Migration scripts could lock the database temporarily; `db_architect` and `ai-migration` must handle it transactionally.

### Rollback
Run the `DOWN` migration script via `ai-migration` to revert the database schema to the original enum and restore `mcp-telemetry.mjs` logic.

---

## D-050 — Decouple Triad Persona from CLI Tools (ARCHITECT/ENGINEER)

**Date**: 2026-06-25
**Task**: P-44
**Decision**: Rename `GEMINI.md` to `ARCHITECT.md` and `CLAUDE.md` to `ENGINEER.md`. Update all CLI defaults to route `agy` to Architect and `claude` to Engineer by default, generalizing the Triad terminology.

### Why needed
Historically, the Architect role was strictly coupled to the Gemini CLI and the Engineer role to Claude Code. The provider abstraction (E-138) allowed other CLIs (like Antigravity `agy`) to act as either the Architect or Engineer, but the rule files and blueprints still hardcoded "Gemini" and "Claude". Since the Gemini CLI is being deprecated, maintaining rulefiles named `GEMINI.md` creates confusion. Generalizing to `ARCHITECT.md` and `ENGINEER.md` formalizes the Role Abstraction pattern cleanly.

### Alternatives considered
1. **Keep GEMINI.md/CLAUDE.md** — Rejected: Will become legacy tech debt once Gemini CLI is fully deprecated. Breaks abstraction.
2. **Rename to AGY.md/CLAUDE.md** — Rejected: Same issue, tightly couples the conceptual role (Architect) to the specific tool (`agy`).
3. **Decouple via ARCHITECT.md and ENGINEER.md (Chosen)** — Pure role-based architecture. Any provider (`agy`, `claude`) can assume any role seamlessly.

### Constraints driving this decision
- **Forward-compatibility**: Must support any provider assuming any role via `.ai/roles.json`.

### Impact
- Unlocks: E-183 (Rulefile Renaming and Codebase Update), E-184 (README update).
- Risk if wrong: Breaking changes to any external scripts hardcoding `GEMINI.md` or `CLAUDE.md`.

### Rollback
Revert file names and reverse the `src/bin/ai` and `install-ai-os.sh` default path lookups.

---

## D-051 — Ratify E-183 Shim Approach for Legacy CLI Loaders

**Date**: 2026-06-26
**Task**: P-45
**Decision**: Ratify the E-183 implementation of keeping `CLAUDE.md` and `GEMINI.md` as thin `@import` shims that load `ENGINEER.md` and `ARCHITECT.md`.

### Why needed
D-050 explicitly rejected keeping `CLAUDE.md` and `GEMINI.md` to avoid legacy tech debt. However, during the implementation of E-183, it was discovered that certain CLIs (like Claude Code) hardcode auto-loading of `CLAUDE.md`. Without a shim, the role bootstrap fails. Keeping them as thin `@import` shims bridges the gap until vendor CLIs allow configurable rulefile names.

### Alternatives considered
1. **Strict removal (D-050 original intent)** — Rejected: Breaks automatic role bootstrap for Claude Code and legacy Gemini CLI instances.
2. **Duplicating content** — Rejected: Creates documentation drift and violates DRY principles.
3. **Thin @import shims (Chosen)** — Retains the decoupling of the actual role content in `ENGINEER.md`/`ARCHITECT.md` while satisfying the hardcoded vendor auto-load requirements.

### Constraints driving this decision
- **CLI Vendor Hardcoding**: Vendor CLIs (Claude Code) currently hardcode `CLAUDE.md` and do not allow custom configuration for project-wide bootloader files.

### Impact
- Unlocks: Closes the unratified shim gap reported in `DIGEST.md`.
- Risk if wrong: Slightly more files in the root directory, but minimal maintenance burden since they only contain `@import` directives.

### Rollback
Remove the shim files when all used CLI providers support configurable role file names (e.g., via `.ai/roles.json` or CLI flags).

---

## D-052 — Retain Vendor-Named Provider Directories

**Date**: 2026-06-26
**Task**: P-47
**Decision**: Re-scope E-188 (Part 2) to cancel the rename of `src/gemini` and `src/claude` to `src/architect` and `src/engineer`. These directories will remain vendor-named (`gemini`, `claude`) as they contain provider-specific configurations and shims.

### Why needed
D-050 decoupled the *roles* (Architect/Engineer) from the *providers* (agy/Claude). However, the directories `src/gemini` and `src/claude` hold provider-specific CLI configurations (e.g., Gemini TOML settings) and the fallback shims ratified in D-051. Renaming these directories to role names (`src/architect`, `src/engineer`) introduces incoherence, as a role should not contain provider-specific configuration. By retaining vendor names for the directories, we clarify that they are *provider adapters*, not *role definitions*.

### Alternatives considered
1. **Rename to role names (E-188 Part 2 original plan)** — Rejected: Incoherent architecture. The Architect role now defaults to `agy`, so placing Gemini-specific config inside `src/architect` is incorrect.
2. **Move all configs into a generic `src/providers`** — Rejected: Excessive refactoring and test-breakage (~25 mirror-identity tests) for purely cosmetic gains.

### Constraints driving this decision
- **Provider-Role Decoupling**: Roles are conceptual; providers are the actual CLIs executing them. Configuration tailored to a specific CLI must remain grouped by that CLI's name.

### Impact
- Unlocks: Closes the blocked E-188 task. 
- Risk if wrong: Minor naming confusion if users mistake the provider directories for role logic, but this is mitigated by documentation.

### Rollback
If the vendor CLIs are fully deprecated, delete their respective `src/<provider>` directories entirely.

---

## [[D-053]] — Shell-Native State Mutation Exception (ai add-task / ai handoff)

**Date**: 2026-07-31
**Task**: E-198
**Decision**: Authorize the shell-native `ai add-task` (and existing `ai handoff`) primitives as an audited exception to MCP-Only State Mutation (structured-outputs.md §32).

### Why needed
The Architect persona (Antigravity `agy`) runs shell reliably but does not dependably expose project MCP servers during invocation. Enforcing strict MCP-Only State Mutation caused task creation from the shell to fail and drop tasks silently since they never hit `state.sqlite`. Creating a shell-native primitive wraps the existing SQLite write paths (`add_task` logic) without requiring an MCP connection.

### Constraints driving this decision
- **Resilience**: The Architect must be able to persist tasks to `state.sqlite` even when the `task-synchronizer-mcp` is unreachable over the transport layer.
- **Single Source of Truth**: The `ai add-task` command strictly writes to `state.sqlite`, preserving the ACID guarantees established for state mutation.

### Impact
- Unlocks: E-198 implementation. Resolves incidents Antigravity:ORPHANED_BLUEPRINT and task-synchronizer:architect-tasks-not-persisted-to-state.

### Rollback
Deprecate the `ai add-task` command and enforce MCP-only routing if/when Antigravity natively supports stable local MCP tool execution for all project servers.
---

## [[D-054]] — Same-Provider Triad (All-Claude) Is a Supported Topology; Role Binding Is Per-Pane

**Date**: 2026-09-04
**Task**: E-208, E-209, E-210, E-211 (Engineer findings handoff of 2026-09-04 21:14 UTC, COMM.md)
**Decision**: Ratify the same-provider Triad (both `architect` and `engineer` on `claude`, distinct tmux panes, optionally distinct models) as a supported topology, and rule that **role identity is bound per pane at launch — never per project**. The binding surface is a single launcher, `ai pane <role>`, that (1) mints the E-129 HMAC role token for that role, (2) sets `AI_OS_CALLER_ROLE` for that pane, (3) injects the role's canonical rulefile as the governing persona, and (4) pins the tmux pane title to the role name. `role-abstraction.md §Same-Provider Triad` and `interactive-bridge.md §Pane Resolution Precedence` are amended to match.

### Why needed
D-050 decoupled persona from vendor and `role-abstraction.md` already *claims* the dual-Claude case, but the Engineer's live evaluation (COMM.md 2026-09-04) shows the claim is not wired end-to-end: G1 `CLAUDE.md` always imports `ENGINEER.md`; G2 `.claude/settings.json` bakes `AI_OS_CALLER_ROLE=engineer` and `session-start.sh engineer` project-wide, so both panes are Engineers to the enforcement layer; G3 `resolve_pane` Pass 2 fuzzy title match fires before the roles.json ordinal and swallowed an Architect handoff into the Engineer pane twice; G4 `advisor-mcp` hardcodes `agy`. The blueprint is ahead of the implementation — a divergence the Architect must reconcile, not the Engineer.

### Alternatives considered
1. **Reject the topology; revert `.ai/roles.json` to `agy:1`** — rejected. The user needs it (agy auth lapses, and the Architect benefits from a stronger model); D-050's whole point was provider independence, and the blueprint already promises this case.
2. **Role-aware `CLAUDE.md` shim that branches on the role** — rejected. `@import` is static; the shim cannot branch. Rewriting the shim into a role-neutral "read the stamp" preamble would strip the Engineer's rulefile from the default pane and weaken the documented D-051 shim contract.
3. **Two project settings files, one per role, selected via `claude --settings`** — accepted as the *mechanism for the settings layer*, but rejected as the *sole* binding: `--settings` merges hooks rather than replacing them, so both `session-start.sh engineer` (project) and `session-start.sh architect` (per-role file) would mint tokens for the same session id with undefined ordering. The launch-time role must therefore be a single authoritative input consumed by the hook (see Constraints).
4. **Per-pane launcher `ai pane <role>` + launch-time role input + role-precedence clause in both rulefiles** — chosen. Symmetric to `ai handoff <role>` / `ai add-task` (D-053): the shell primitive is the provider-agnostic surface; every provider adapter maps it to its own argv.

### Constraints driving this decision
- **Security (E-129 token remains authoritative)**: the HMAC token is the enforcement surface; the env var stays advisory. The role the hook mints is `${AI_OS_PANE_ROLE:-$1}`. `AI_OS_PANE_ROLE` is set only in the *launch* environment of the CLI process by `ai pane` and is read by the SessionStart hook before any agent tool call executes. This is within the E-129 threat model: E-129 protects against **in-session** mutation from a Bash subprocess reaching the gate, and launch-time environment is exactly as trusted as the settings file on disk. The positional default (`engineer`) is unchanged for the plain `claude` launch path.
- **Sovereignty must be enforced, not just prompted, in the Architect pane**: the pre-tool-use gate currently matches `Bash` only. With a Claude Architect, `Write`/`Edit` outside `.ai/` and `plans/` must be blocked by the hook when the minted role is `architect` (Tier 3 — this is the ANTI-DRIFT §35 enforcement layer).
- **Persona precedence is explicit**: both `ENGINEER.md` and `ARCHITECT.md` gain a leading *Role Resolution* clause: when the session context carries an `[AI_OS_ROLE] <role>` stamp (emitted by the SessionStart hook) naming a different role, that role's rulefile governs and this file is inert. `CLAUDE.md` keeps importing `ENGINEER.md` (D-051 unchanged); the Architect pane additionally receives `ARCHITECT.md` via `--append-system-prompt-file`.
- **Deterministic routing**: explicit configuration beats heuristics. When `.ai/roles.json` maps the requested semantic role, `resolve_pane` order becomes exact-title → roles.json ordinal → fuzzy title → window name. `ai pane` pins the pane title so Pass 1 wins deterministically; the ordinal is the safety net; fuzzy passes are last-resort only.
- **Provider-aware A2A bridge**: `advisor-mcp::ask_architect` resolves the executable and argv from `roles.json architect.provider` through the Provider Adapter Registry (`providers.json` gains a `print_mode` argv template). A `claude` Architect child must be launched with `ARCHITECT.md` appended and `CLAUDECODE` unset from the child env (nested-session guard), read-only (`-p`, no permission bypass).
- **Legacy provider targets (`claude`, `gemini`) are deprecated**: warn on use; when both roles resolve to the same provider the target is ambiguous and MUST fail closed with a hint to use `architect`/`engineer`. Removal scheduled for v4.0.
- **Optional per-role model**: `roles.json` role entries MAY carry `"model"`; `ai pane` forwards it to the provider's model flag. Absent → provider default.

### Impact
- Unlocks: E-208 (per-pane role binding + `ai pane` launcher + Write/Edit sovereignty gate + Role Resolution clause), E-209 (`resolve_pane` precedence), E-210 (provider-aware `advisor-mcp`), E-211 (legacy target deprecation + same-provider ambiguity guard).
- Interim rule (until E-208 ships): a dual-Claude Triad is prompt-level only. Operators MUST pin pane titles (`tmux select-pane -T architect` / `-T engineer`) and MUST NOT rely on the enforcement layer to stop the Architect pane from writing `src/`. `.ai/roles.json` (`architect.provider: claude`) is retained and committed with this decision.
- Risk if wrong: if `claude --settings` precedence or the launch-env read proves unreliable, the Architect pane silently keeps Engineer write rights. Mitigated by E-208 acceptance criteria requiring a live negative test (Architect pane `Write` to `src/` → BLOCKED) before DONE.

### Rollback
Revert `.ai/roles.json` to `architect: agy:1`, delete the `ai pane` launcher and the per-role settings file, restore the `session-start.sh engineer` positional-only mint, and restore the E-117 resolution order. The Role Resolution clause in the rulefiles is inert when no stamp is present, so it may stay.

---

---

## [[D-055]] — D-054 Sprint Residuals: Six Rulings (write-gate scope, skill collisions, cache contract, Git Lane residuals, mint guard, D-053 status)

**Date**: 2026-09-07
**Task**: E-216, E-217, E-218 (Engineer handoff 2026-09-07 12:03 UTC, COMM.md)
**Decision**: Rule on the six open questions left by the shipped D-054 sprint (E-208..E-215, master 8af653e). R1 widen by policy; R2 rename the Architect copies; R3 accept; R4 accept three residuals and fund the fourth; R5 accept as documented; R6 already closed.

### R1 — Architect write gate: WIDEN (by policy surface, not by claiming parser completeness)
Gap G2 is narrowed, not closed: shell writes and MCP write tools bypass the E-208 gate. Ruling:
1. **MCP write channel** — the Architect overlay (`.claude/settings.architect.json`) gains `permissions.deny` for every filesystem-mutating MCP tool: `mcp__filesystem__write_file`, `edit_file`, `move_file`, `create_directory`, `mcp__patch-mcp__patch_file`, `mcp__propose-patch-mcp__confirm_patch`, `mcp__propose-patch-mcp__propose_patch`. Deterministic, zero parser work. The Architect edits `.ai/` with the native `Write`/`Edit` tools, which the gate already scopes.
2. **Shell write channel** — `analyzeSovereignty` gains a **write-redirect policy** for `caller_role=architect`: any output redirection (`>`, `>>`, `|& tee`, `tee`) or file-mutating utility (`cp`, `mv`, `install`, `ln`, `sed -i`, `perl -i`, `rsync`, `dd`, `truncate`, `git apply`, `patch`) whose resolved target lies outside `.ai/` or `plans/` → `[SOVEREIGNTY_BLOCK]`. **Inline interpreters** (`python3 -c`, `node -e`, `perl -e`, `ruby -e`, `bash -c`, `sh -c`, `eval`) and heredoc-fed interpreters are BLOCKED outright for the architect role — their targets are unresolvable, and the Architect has no legitimate need for them (hint: use `Write`/`Edit`). Fail-closed on any unparsable target.
3. The gate's documented guarantee becomes: "native write tools + MCP write tools + recognised shell write forms"; the code comments and tests keep stating the residual (exotic encodings, `git` plumbing such as `update-index`/`hash-object`, editors launched interactively).

### R2 — Skill-name collision: RENAME the Architect copies (E-149 precedent)
`ai-task` and `repo-oracle` in `src/agents/skills` become **`arch-task`** and **`arch-oracle`** (the same pattern that turned the Architect's `ai-review` into `arch-review`). `ARCHITECT.md`, `task-planner`, `blueprint-writer`, `_INDEX`, and any P-## lifecycle text are updated. After the rename the multi-role workspace must contain **zero** collisions; the E-212 collision guard is retained as a permanent invariant and is promoted from a warning to a **non-zero `ai sync` exit** in a multi-role workspace (a single-role workspace keeps role-overrides-shared, unchanged). Role-scoped skill directories were rejected: the host loads one flat directory per provider, so a directory-level fix would be a host-specific fork of the discovery contract.

### R3 — E-126 cache-rollback contract: ACCEPT the change
`AI_OS_DISABLE_CACHE=1` suppresses the compiled context blob only. The `[AI_OS_ROLE]` stamp is role binding (D-054), not caching, and MUST survive a caching rollback — otherwise a cache toggle silently reopens G1. Recorded in `role-abstraction.md §Same-Provider Triad` Component 2.

### R4 — T-GITLANE-001 residuals: ACCEPT 1–3, FUND 4
- Accept **1** (`--amend` index↔HEAD~ gap): undetectable from inside `pre-commit`; a partial detector on a sovereignty gate is worse than a stated gap.
- Accept **2** (record selected by an unauthenticated session id): same ceiling as `mintToken`; impact bounded to adding a restriction or waiving a diff that is already in scope.
- Accept **3** (`--no-verify`, `merge`, `cherry-pick`): inherent to git, pre-existing for Gate 2 as a whole.
- **Fund 4**: the stamp waiver is granted **only** when the role comes from the verified session record (`safe-exec --verify-role`). The `AI_OS_PANE_ROLE` / `AI_OS_CALLER_ROLE` fallbacks may drive the **restrictive** outcome (path-scope BLOCK) but never the waiver. A `.ai/`-only commit from an unverified session keeps the full `[CRITIC_STAMP]` requirement. Together with the existing E-100/E-113 REVIEWS.md hand-edit checks this closes the "bookkeeping commit without a stamp" path.

### R5 — Mint guard is partial: ACCEPT as documented
The guard prevents *changing* a valid binding; it does not prevent delete-and-remint. Deleting the record from an Architect pane is already gated by the E-102 `rm` sovereignty block, so the residual requires an actor with unrestricted shell — who is outside every AI-OS gate anyway. Binding the record to a process start-time / boot-id, or an append-only ledger, is deferred to the backlog (no E-## now); `THREAT_MODEL.md` already states the ceiling.

### R6 — D-053 + structured-outputs.md §32: ALREADY CLOSED
D-053 was ratified 2026-07-31 (`DECISIONS.md` line "[[D-053]]") and §32 carries the `ai add-task` / `ai handoff` exception. The Engineer's item is stale; the `DIGEST.md` Known Risk that still says "pending D-053" is corrected with this decision.

### Alternatives considered
1. **R1: accept the write gate as advisory** — rejected; §35 enforcement at the gate is the whole point of D-054's Tier 3 acceptance, and the two uncovered channels are the cheapest ones for a drifting Architect to reach.
2. **R1: full shell parser with path resolution for every utility** — rejected as unbounded; the policy surface above blocks the reachable forms and states the rest.
3. **R2: role-scoped skill directories** — rejected (host contract, see R2).
4. **R4: fix `--amend` with a best-effort detector** — rejected (false confidence on a sovereignty gate).

### Constraints driving this decision
- Sovereignty must be enforced by gates, not prompts (D-054). Every gate must state its residual plainly; tests must fail if a stronger claim is reinserted (E-208 precedent).
- No host-specific forks of the skill-discovery contract (one flat directory per provider).

### Impact
- Unlocks: E-216 (R1, Tier 3), E-217 (R2 rename + collision invariant + the `seo_engineer.md` frontmatter fix, Tier 2), E-218 (R4.4 verified-record-only waiver, Tier 2).
- Risk if wrong: R1's interpreter block could hamper an Architect that legitimately needs a one-liner to read state — mitigated: reads are unaffected (only write forms and inline interpreters are blocked) and `.ai/` reads have MCP equivalents.

### Rollback
`AI_OS_SOVEREIGNTY_LOCK=0` disables the widened shell policy; remove the overlay deny rules; rename the skills back; `AI_OS_SKIP_GIT_LANE=1` for the waiver rule. R3/R5/R6 are documentation-only.

---

---

## [[D-056]] — Write-Gate Widening Freeze; patch-mcp Fail-Closed Role; Manifest-Scoped Sync Pruning

**Date**: 2026-09-07
**Task**: E-219, E-220 (Engineer handoff 2026-09-07 15:14 UTC; E-216..E-218 on branch `engineer/e216-e218-writegate-hardening`)
**Decision**: (R3) Freeze further widening of the Architect shell write gate at the E-216 three-layer shape and adopt the fixture corpus as the gate's contract; (R1) make `patch-mcp`'s role guard derive the role from the verified session record and fail closed; (R2) let `ai sync` prune only skills it provably wrote and that were never modified, via a sync manifest.

### R3 — Widening freeze (the over-block ratio is the governing constraint)
The E-216 review needed seven rounds for eleven findings, and **five of the eleven were over-blocks** — legitimate Architect work refused: prose with `->` written into `.ai/`, `> /dev/null`, `awk '$1 > 5'`, and `sed -i .ai/n && git diff`. Every finding was one invariant broken: text already classified as DATA re-read as SYNTAX. An over-block on a sovereignty gate is not a safe failure; it is a broken Architect that will route around the gate. Ruling:
- **No further widening of the shell layer.** The listed residual (exotic encodings, git plumbing, interactive editors, MCP proxying beyond the denied names, `find -delete` / `-exec rm`, awk `-f` program files) is ACCEPTED. The Git Lane is the last checkpoint for anything that slips through, and that is the intended layering.
- **The fixture corpus is the contract.** `tests/fixtures/arch-write-cases.json` (argv-passed; READ forms asserted as positives beside the write forms they resemble) is the specification of `architect-writes.mjs`. Any change to the analyser MUST add cases in both directions, and a change that turns a READ positive into a block is a regression, not a hardening.
- **Over-blocks outrank under-blocks in review ordering** for this gate (the auditor weighting the Engineer adopted from round 4 becomes the rule).

### R1 — `patch-mcp` role guard: FUND, fail closed (T-PATCHMCP-001)
`roleGuard()` allows unless the caller volunteers `caller_role`; with the overlay `permissions.deny` absent (it is settings-file config, the layer most likely to be missing), a default-open guard is the only barrier. Ruling: the role is derived server-side in this order — (1) the verified session record via `safe-exec --verify-role` using the harness session id; (2) the server's spawn-frozen `AI_OS_CALLER_ROLE` env (the E-129 per-server pattern); (3) **no evidence → treat as `architect`** (restrictive default: writes confined to `.ai/` and `plans/`). A self-reported `caller_role` can only *add* restriction, never lift it. A properly installed Engineer session always has a record (the SessionStart hook mints one), so the restrictive default cannot strand a legitimate Engineer. Same rule applies to `propose-patch-mcp::confirm_patch`.

### R2 — Stale skills after a rename: prune by manifest only
`ai sync` is additive; the E-217 rename left `ai-task` / `repo-oracle` in `.agents/skills` (harmless today, agy serves no role). Blind pruning could delete a user-authored skill, so: `ai sync` writes `_SYNC_MANIFEST.json` in each target skill/agent dir recording every path it wrote with a content hash. On the next sync a path is deleted **only if** it is in the manifest, its hash still equals what sync wrote (unmodified since), and it is no longer in the source set. Anything absent from the manifest or modified is never touched and is reported as `orphan (kept)`. First run after this ships has no manifest, so nothing is pruned; a `--prune-known` flag deletes an orphan that is byte-identical to a current canonical skill under another name (the E-217 leftovers qualify) so the migration does not need hand deletion.

### Alternatives considered
1. **R3: keep widening the shell layer toward completeness** — rejected; the measured over-block ratio shows each increment costs Architect usability faster than it buys coverage, and the Git Lane already backstops.
2. **R1: fail open with a warning when no record exists** — rejected; that is the current gap restated.
3. **R2: prune everything not in the source set** — rejected; deletes user-authored skills. **R2: never prune** — rejected; every rename leaves permanent residue in every workspace.

### Constraints driving this decision
- A sovereignty gate that blocks ordinary role work is a defect of the same severity as a bypass (D-054 §35 enforcement must be usable to be real).
- Restrictive defaults when evidence is missing (D-055 R4 pattern), never permissive ones.
- Sync must remain safe to run in any workspace, including ones with user-authored skills (E-201 lesson: never touch what you did not write).

### Impact
- Unlocks: E-219 (R1, Tier 3, `security_engineer`), E-220 (R2, Tier 2). R3 is documentation only.
- Risk if wrong: R1's restrictive default could block a host that never mints a record and never sets the per-server env — that host is not an installed AI-OS provider; `AI_OS_SOVEREIGNTY_LOCK=0` remains the escape hatch.

### Rollback
R1: `AI_OS_SOVEREIGNTY_LOCK=0` restores the legacy guard. R2: delete `_SYNC_MANIFEST.json` files; sync reverts to additive-only. R3: a later decision may lift the freeze only with a fixture-corpus delta showing zero new over-blocks.

---

---

## [[D-057]] — Project-Boundary Binding for Pending Patches; Review-Gate Traversal Policy; Install-First Helper Locators

**Date**: 2026-09-07
**Task**: E-221, E-222, E-223 (Engineer handoff 2026-09-07, E-219/E-220 complete)
**Decision**: (1) Fund T-PROPOSEPATCH-001: a pending patch is bound to the project that proposed it and re-validated at confirm time. (2) Change `run_review`'s PATH_TRAVERSAL check from a flat `../` regex to a context-aware policy that recognises script-relative locators. (3) Every hook and shell locator resolves helpers install-first; the dev tree is consulted only when the current repo IS the framework clone. (4) Name the D-054..D-056 shared helpers in `architect.md §4` so the aligner stops reporting them as orphaned work.

### 1 — T-PROPOSEPATCH-001: FUND (E-221, Tier 3)
`propose_patch` stores an absolute path resolved against the proposing cwd; `confirm_patch` writes to it without re-running `safePath` against its own cwd. Ruling: a pending record carries `project_root` (the proposer's `safePath` base) and a **project-relative** path, never an absolute one. `confirm_patch` re-derives its own project root, requires equality with the stored one (`[PROJECT_MISMATCH]` otherwise), re-runs `safePath` on the relative path against its own cwd, and re-derives the role (E-219) — every check is repeated at confirm time because the confirming process is a different process. Legacy pending records with an absolute path are rejected with a hint to re-propose. Same shape for any future two-phase write.

### 2 — Review-gate PATH_TRAVERSAL: POLICY CHANGE (E-222, Tier 2)
The check fires P0 on any added line containing `../`, which matches the ordinary script-relative locator pattern (`${self_dir}/../shared/x.mjs`, `resolve(__dirname, "../shared")`, `dirname "$0"`) present at several sites in `src/bin/ai`; the Engineer removed a legitimate `..` to pass. A review gate that blocks the codebase's own idiom trains people to route around it (the D-056 over-block lesson, applied to reviews). Ruling: keep P0 for `/etc/`, `/root/`, and for `../` that appears in **runtime path handling** (string concatenation with a request/argument value, `path.join`/`resolve` whose first argument is not a script anchor). Downgrade to **P1 advisory** when the `../` is anchored to a script-relative base (`__dirname`, `import.meta.url`, `self_dir`, `$0`, `BASH_SOURCE`, `AIOS`/`HOME`-rooted mirrors). The anchor list lives in one place with fixture cases in both directions (positive: the four `src/bin/ai` locators; negative: `join(req.path, "../")`). The HARDCODED_SECRET check keeps its shape (no reported over-blocks).

### 3 — Helper locators: INSTALL-FIRST (E-223, Tier 3)
E-220 found three `git rev-parse --show-toplevel` locators in `src/bin/ai` that resolved the USER's repo, so any project containing `src/shared/<helper>.mjs` would have that file executed with trusted stdout. The same pattern exists in all six `hooks/*.sh` (safe-exec, cache-manager locators). Ruling: locator order is **`~/.ai-os` install mirror first**; the dev tree (`<toplevel>/src/...`) is consulted **only when the current repo is the framework clone** — determined by `AIOS_WORKSPACE` equalling the toplevel, or the toplevel's `package.json` name being the framework package. A downstream project can never supply a helper. One shared resolver (`ai-os-locate`, shell function + `.mjs` twin) replaces the per-site chains; the dogfooding path for this repo is preserved by the clone check.

### 4 — Orphaned work: NAME THE HELPERS
`architect.md §4` gains one bullet, "Sovereignty & provisioning helpers", listing `architect-writes.mjs`, `caller-role.mjs`, `provider-adapter.mjs`, `role-manifest.mjs`, `sync-manifest.mjs` and pointing to `role-abstraction.md` / `architect-provider-parity.md`. The parity blueprint gets a matching "Shared helpers" section. This is the aligner's contract; adding a shared helper without naming it there is the divergence, not the helper.

### Alternatives considered
1. **(1) Re-run `safePath` only, without binding the project** — rejected; a path that is in-scope for the confirmer but outside the proposer's project silently lands in the wrong project.
2. **(2) Delete the traversal check** — rejected; the `/etc/` / `/root/` and runtime-concatenation cases are real. **(2) Keep P0 and allowlist file names** — rejected; the idiom is not file-specific.
3. **(3) Keep dev-tree-first and add a checksum** — rejected; the install mirror is already the trusted copy, and a checksum adds a second trust root.

### Constraints driving this decision
- Two-phase operations re-validate everything in phase two (D-055 R4 / E-219 pattern).
- Gates must not block the codebase's own idioms (D-056 R3).
- Executable helpers are trusted only from the install root; a project tree is data (E-201 lesson generalised).

### Impact
- Unlocks: E-221 (T3, `security_engineer`), E-222 (T2), E-223 (T3, `security_engineer`).
- Risk if wrong: (3) breaks dogfooding if the clone check misfires — mitigated by the `AIOS_WORKSPACE` equality path and a `AI_OS_LOCATE_DEV=1` escape hatch for framework development only.

### Rollback
(1) Accept legacy absolute records with `AI_OS_PATCH_LEGACY=1`. (2) `AI_OS_REVIEW_STRICT_TRAVERSAL=1` restores the flat regex. (3) `AI_OS_LOCATE_DEV=1` restores dev-tree-first. (4) documentation only.

---

---

## [[D-058]] — Locator Class Closure in Skills; Executable-Markdown Policy; Project-Bound Read-Only Patch Tools; argv Rollback Ratified; Tier 3 Acceptance = Threat Property

**Date**: 2026-09-07
**Task**: E-225, E-226, E-224 (Engineer handoff 2026-09-07, E-221..E-223 complete)
**Decision**: (§1) Ratify the E-223 deviation: the dev-tree rollback is `ai --dev-tree` (argv), and D-057 §3's `AI_OS_LOCATE_DEV=1` sentence is superseded. (§2) Fund closure of T-LOCATOR-001 in the skills and make "no cwd-relative framework execution in any markdown" a standards-checker rule. (§3) `run_review` grades markdown by executability, not by extension. (§4) Fund T-PROPOSEPATCH-002: the read-only patch tools are project-bound. (§5) Tier 3 acceptance is the threat entry's property; pre-authorised in-boundary widening replaces a re-filing round trip.

### §1 — D-057 §3 deviation: RATIFIED
An environment variable cannot be the rollback for an env-borne attack: a project's `.claude/settings.json` `env` block is inherited by hooks and is written by `ai init`, so env is attacker-supplied at the same capability level as the repo. `ai --dev-tree` (argv) carries the same capability and cannot be supplied by a settings file. The hooks' own `AI_OS_LOCATE_UNTRUSTED_ENV=1` and the installer-written workspace file are the trust roots. D-057 §3's rollback sentence is superseded by this section; the parity blueprint's helper table is amended.

### §2 — T-LOCATOR-001 in skills: FUND (E-225, Tier 3) + standards rule
Four `SKILL.md` files (and their `.claude/`/`.agents/` mirrors) execute framework helpers cwd-relative, one of them an auto-executed `!` line in `ai-preflight`, which every session runs. Ruling: every executable line in a skill or agent file resolves helpers through the installed resolver — `. "${HOME}/.ai-os/shared/locate.sh"` with `AI_OS_LOCATE_UNTRUSTED_ENV=1`, then `ai_os_locate <helper>` — and never through a cwd-relative or repo-relative path. The E-80 standards checker gains a rule: any `!`-prefixed line or executable fenced block in `src/**/SKILL.md` / `src/**/agents/*.md` that references `src/` or `./` for execution is a FAIL. The `ai-preflight` line is fixed first and mirrored byte-identically.

### §3 — Documentation vs executable markdown: GRADE BY EXECUTABILITY (E-224, Tier 2)
`run_review` currently grades prose in `DECISIONS.md` as code (the D-057 text quoting `join(req.path, "../")` trips P0), while a blanket `.md` skip would blind the gate to the `!` lines from §2. Ruling — one classifier, shared by the review gate and the §2 standards rule:
- **Executable markdown lines** = `!`-prefixed lines in skill/agent files, and lines inside fenced blocks whose tag is an executable language (`bash`, `sh`, `zsh`, `js`, `mjs`, `javascript`, `python`, `node`). These are graded as code (P0 PATH_TRAVERSAL rules apply, including the E-222 anchor exemptions).
- **Everything else in markdown** (prose, untagged/`text`/`json`/`md` fences, inline code) is documentation: PATH_TRAVERSAL does not fire; HARDCODED_SECRET still fires (a pasted credential in a doc is a leak regardless of context).
- `.ai/DECISIONS.md`, `COMM.md`, `LOG.md`, `DIGEST.md`, `THREAT_MODEL.md` and `.ai/blueprints/*.md` contain no executable lines by construction; a `!`-line appearing there is itself a FAIL.

### §4 — T-PROPOSEPATCH-002: FUND (E-226, Tier 2)
`preview_patch` reads the stored path to build a baseline; `list_pending_patches` and `reject_patch` operate on rows from any project. Ruling: all three derive the target from `project_root` + `rel_path` and require project equality with their own root. On mismatch: `preview_patch` renders the stored diff only (no file read, banner `[FOREIGN_PROJECT] baseline not shown`), `reject_patch` refuses (`[PROJECT_MISMATCH]`), `list_pending_patches` shows only own-project rows by default and, with `all: true`, foreign rows as id + `rel_path` + `project_root` basename only — never an absolute path. Legacy rows (no `project_root`) are listed as `legacy`, never read.

### §5 — Tier 3 acceptance = the threat property (process ruling)
Three of E-223's five audit rounds found holes the fix introduced; both Tier 3 rulings' stated scope was "the easy half", and the signed-off property was still false after implementing the ruling exactly. Ruling: a Tier 3 task is DONE when the **property named in its THREAT_MODEL entry** holds under the negative test, not when the ruling's letter is implemented. When implementing the letter leaves the property false, the Engineer is **pre-authorised to widen within the same boundary files and the same threat entry**, reporting the widening in the handoff; only new files, new tools or a new threat class require filing. The ruling gives the shape; the threat entry gives the property.

### Alternatives considered
1. **§1: keep the env rollback and document the risk** — rejected; a documented hole in a fail-closed gate is still a hole.
2. **§3: skip `.md` entirely (as the coverage check does)** — rejected; blinds the gate to auto-executed lines. **§3: grade all `.md` as code** — rejected; the Architect's decision log would need to avoid quoting attack patterns.
3. **§4: fold into E-221** — rejected at the time by the Engineer, correctly; D-057 §1 scoped the read-only tools as unchanged.
4. **§5: keep strict letter-of-ruling scope** — rejected; it cost two extra Tier 3 rounds per task while the property was measurably false.

### Constraints driving this decision
- Env is untrusted wherever a project can write a settings file (T-LOCATOR-001 audit).
- Gates must not block the project's own documentation idiom (D-056 R3, D-057 §2 lineage).
- Two-phase and read-only tools re-validate against their own project (D-057 §1 pattern).

### Impact
- Unlocks: E-225 (T3, `security_engineer`), E-226 (T2), E-224 (T2). Execution order E-224 → E-225 → E-226 so the classifier exists before the standards rule that uses it.
- Risk if wrong: §2 breaks skills on a host with no `~/.ai-os` install — acceptable, that host has no framework either; the skill prints "(helper unavailable)" as today.

### Rollback
§1 none (argv only). §2 revert the four SKILL.md lines; the standards rule is gated by `AI_OS_STANDARDS_SKIP=skill-locator`. §3 `AI_OS_REVIEW_STRICT_TRAVERSAL=1` (already exists) grades all lines as code. §4 `AI_OS_PATCH_LEGACY=1` restores unbounded reads. §5 process only.

---

---

## [[D-059]] — `ai start`: One-Command Triad Launcher (tmux layout + role panes + watcher)

**Date**: 2026-09-09
**Task**: E-227, E-228 (user request 2026-09-09)
**Decision**: Add `ai start` to the `ai` bootloader as a **bridge-level lifecycle command**: it creates (or reuses) the project's tmux session/window, lays out the panes from `.ai/roles.json`, launches each role with `ai pane <role>`, and runs `ai watch` in a dedicated pane — so the operator never opens panes by hand. The command composes existing primitives only; it introduces no new provider, state, or routing logic.

### Why needed
D-054 bound roles per pane (`ai pane`), E-209 made routing deterministic when titles are pinned, and `ai watch` drives the ping-pong loop — but the operator still has to open three panes, run three commands, and get the pane ORDER right (the roles.json `pane_identifier` is an ordinal among agent panes, so a wrong split order silently misroutes). `ai start` makes the supported topology the default experience.

### Design (cli-collapse.md §`ai start`)
- **Composition only**: the launcher executes exactly two things it does not own — `ai pane <role>` and `ai watch` — both from the installed `ai` on PATH. Never a project-supplied script.
- **Layout is derived, not configured**: the role with the lower `pane_identifier` gets the lower tmux `pane_index`, so the ordinal fallback (E-209 step 2) agrees with the layout by construction. Default `triad` layout = engineer left (full height), architect right-top, watcher right-bottom. The watcher pane runs a shell script, which `_is_agent_cmd` excludes, so it never shifts the ordinals.
- **Shell-hosted panes**: agent panes are interactive shells that receive `ai pane <role>` via `send-keys` — when the provider exits the operator keeps a shell and can rerun `ai pane` (a `split-window 'cmd'` pane would close). `ai pane` pins the title and disables window auto-rename (E-209 Pass 1 stays deterministic).
- **Idempotent**: a second `ai start` in a project with live panes re-pins titles, starts the watcher only if none holds the single-writer lock, and attaches — it never duplicates panes. `--kill` tears the project's window down (watcher first).
- **Optional config `.ai/start.json`** (`session`, `layout`, `watch`, `sizes`) with constrained values (session name `^[A-Za-z0-9_-]{1,32}$`, sizes numeric percentages); absent file = defaults (`session: aios`, window = project basename).
- **Non-tmux hosts**: exit 2 with the manual three-command recipe printed (cli-collapse.md: tmux is the recommended UX, not a hard requirement).

### Alternatives considered
1. **A `~/.tmux.conf` snippet / tmuxinator profile** (the cli-collapse "Tmux Documentation" idea) — rejected as the primary path: it cannot read `roles.json`, so pane order and role binding drift from the configuration the router trusts.
2. **Launching providers directly from `split-window`** — rejected: the pane dies with the provider, and `ai pane`'s binding/title logic would be duplicated.
3. **Do it inside `ai pane` (auto-split when run in a fresh window)** — rejected: `ai pane` binds THIS pane and must stay side-effect-free beyond it (E-208 audit surface).

### Constraints driving this decision
- cli-collapse.md limits the bootloader to lifecycle/diagnostic commands. `ai start` IS lifecycle (it starts the Triad); the command set is now explicitly: `init`, `sync`, `install`, `doctor`, `uninstall`, `start`, plus the D-053/D-054 shell primitives `handoff`, `add-task`, `pane`, `watch`.
- No new state: layout comes from `roles.json`; the watcher's existing mkdir lock prevents double injection.
- Values read from `.ai/start.json` become tmux arguments, so they are validated like `providers.json` provider names (E-208 audit lesson).

### Impact
- Unlocks: E-227 (launcher, Tier 2), E-228 (`--status`/`--kill`, doctor line, docs + installer hint, Tier 1).
- Risk if wrong: a layout that disagrees with the ordinal would misroute handoffs — mitigated by deriving the layout from `pane_identifier` and asserting the resulting pane order in tests.

### Rollback
Remove the `start` dispatch; the three manual commands (`ai pane engineer`, `ai pane architect`, `ai watch`) keep working unchanged.

---

---

## [[D-060]] — D-058 §3 Extensions Ratified; CI Funded; Operand Re-tokenisation; Skill Consent Rule; Manifest Gitignore

**Date**: 2026-09-09
**Task**: E-230, E-231, E-232, E-233 (Engineer handoff 2026-09-08, delivered 2026-09-09 after the watcher restart; E-224..E-226 complete)
**Decision**: Ratify the three narrow extensions the Engineer made beyond D-058 §3's letter (they are the same over-block invariant applied to non-markdown text); fund CI because three sprints in a row had nowhere to "verify on CI"; fund the recursive re-tokenisation of interpreter operands under the D-056 over-block guard; rule that auto-executed skill lines may never run a project-supplied program; gitignore the E-220 sync manifests.

### Extensions RATIFIED (all three; they become part of the E-222/E-224 anchor contract)
1. **`.ai/state.json` exact-path allowlist.** Task descriptions are stored verbatim, so a `../` written into a task text lands in a committed file and blocks the next commit. Exact path, not a `.json` rule — `package.json` scripts genuinely carry paths that matter. Ratified as written.
2. **ES module specifiers are script-relative anchors.** `import … from "../x.mjs"`, `export … from`, dynamic `import("../")` and `require("../")` resolve against the importing module by definition. Added to the E-222 anchor list; the E-224 wiring commit tripping on its own import line is the proof.
3. **Whole-line comments are documentation.** A `//` or `#` line cannot execute; the E-222 fixture that asserted "prose → P0" with a comment as its example was wrong about its own intent and is corrected.
Rule for the future: an over-block of the codebase's own idiom found while implementing a ruling is an in-boundary widening under D-058 §5 — fix narrowly, add fixtures both ways, report. This handoff did exactly that.

### §1 — CI: EXISTS AND IS RED — FIX IT (E-230, Tier 2, `ci_gate`)
The Engineer's finding "no CI configuration in this repository" is **wrong**: `.github/workflows/test.yml` ("AI-OS Tests") runs `install-ai-os.sh` + `tests/run.sh` on `ubuntu-latest` / Node 22 on every push and pull request, and `.ai/DEVOPS.md` documents it. What is true is worse: the last three completed runs on `master` (2026-09-07 ×2, 2026-09-09) **failed**, and nobody read them — local 4117/0 was reported as the verification while CI was red. Ruling: E-230 is re-scoped from "add CI" to (a) find out why the Engineer's check missed `.github/` (cwd or glob error — record it), (b) make the workflow green on `master` (the Linux/GNU-patch run IS the E-221 verification; add a `patch --version` line to the log), (c) add the `node:test` unit layer as a second job and a README badge, (d) **process rule**: an E-## is not DONE until the CI run for its merge commit is green — `ai-task` surfaces the `gh run` status for the current HEAD before marking DONE. `ci_gate` documents the change in `DEVOPS.md`. The registered E-230 description carries the false "no CI" premise; this section is authoritative.

### §2 — T-LOCATOR-001 known-uncaught operands: FUND (E-231, Tier 2)
`bash -c "node src/bin/ai"`, `eval`, `xargs`, pipe-fed and heredoc-fed interpreters hide the execution from the E-225 rule. Ruling: re-tokenise the operand recursively. The auditor's warning is adopted as the constraint: this is the change most likely to resurrect an over-block, so fixtures in both directions come BEFORE the widening, and any new over-block is a regression (D-056 R3).

### §3 — Skill consent: RULE
An auto-executed `!`-line runs because the skill was loaded, not because the agent chose to. Two skills run the visited project's own `tests/run.sh` that way. Ruling: a `!`-line may only run framework helpers through the installed resolver, or read-only inspection commands. It may NEVER execute a project-supplied program (`tests/run.sh`, `npm run`, `make`, `scripts/*`, `./…`). Running project code is an explicit numbered step the agent performs after loading. The E-80 standards checker enforces it with the E-224 classifier. → E-232 (Tier 2).

### §4 — `_SYNC_MANIFEST.json`: GITIGNORE
Generated per-workspace state, same class as `_SKILLS_INDEX.md`. `ai init`/`ai sync` add the pattern to a project's `.gitignore` idempotently. → E-233 (Tier 1).

### Merge state
All four previously stacked branches are merged: `origin/master` is at `6b8e5f8` (E-224..E-226 plus the flake fixes). Nothing pending on the user.

### Alternatives considered
1. **CI: keep asking "verify on CI" without CI** — rejected; a verification step with nowhere to run is a false checkbox. **CI: Docker-based local sandbox instead** — rejected as the primary path; Docker has been down for two sprints and CI is the reproducible Linux/GNU environment anyway.
2. **§3: allow `!`-lines to run project tests when a `.ai/` opt-in flag exists** — rejected; consent belongs to the agent's explicit action at that moment, not to a config bit set once.
3. **§2: leave the operand class as a documented residual** — rejected; it is the same class the E-225 rule exists for, only wrapped.

### Constraints driving this decision
- Over-blocks outrank under-blocks on every gate touching the codebase's own idiom (D-056 R3, D-057 §2, D-058 §3).
- Auto-executed lines have no consent step; their capability must be bounded by rule, not by review (T-LOCATOR-001 lineage).
- Verification claims must name an environment that exists.

### Impact
- Unlocks: E-230 (T2), E-231 (T2), E-232 (T2), E-233 (T1). Order: E-233 → E-230 → E-232 → E-231 (cheap hygiene, then the environment, then the consent rule, then the riskiest widening last with CI in place).
- Risk if wrong: E-231 over-blocks a skill's legitimate `bash -c` — mitigated by fixtures-first and the regression rule.

### Rollback
§1 delete the workflow. §2 `AI_OS_STANDARDS_SKIP=operand-retokenise`. §3 revert the two SKILL.md edits; rule gated by `AI_OS_STANDARDS_SKIP=skill-consent`. §4 remove the `.gitignore` lines. Extensions: `AI_OS_REVIEW_STRICT_TRAVERSAL=1` grades everything as code.

---

---

## [[D-061]] — Program-Position Rule for Operand Walks; E-231/E-232 Divergences Ratified; Install, Test-Policy and Hot-Module Follow-ups

**Date**: 2026-09-09
**Task**: E-234, E-235, E-236, E-237 (Engineer handoff 2026-09-09 18:05 UTC; E-227..E-233 complete, master `892f06c`, CI green)
**Decision**: (§1) Ratify both implementation notes: the consent rule is a denylist of EXECUTION shapes ("execution, not mention"), and operand re-tokenisation is capped at depth 1 with the residual asserted. (§2) Resolve the `memory_curator` over-block by a **program-position rule**: only tokens in program position are walked as programs; everything else is an argument. (§3) Move the Playwright browser download out of the default install path. (§4) Add an environment-dependence check to the test review policy plus a skip helper. (§5) Long-running MCP servers reload policy modules on mtime change.

### §1 — Divergences: RATIFIED
1. **Denylist of execution shapes.** D-060 §3's "may only (a)… or (b)…" stated intent; an allowlist mechanism would reject every ordinary `git`/`grep` context line. The line is EXECUTION of a project-supplied program, not mention of one: `npm run` blocked, `npm audit` allowed. Ratified as the rule's definition.
2. **Depth cap 1.** `bash -c "bash -c \"…\""` is asserted as uncaught. A nested wrapper inside a skill file is itself a smell the reviewer sees; ratified.

### §2 — Program-position rule (E-234, Tier 2)
`memory_curator.md:178-179` is blocked because `.ai/memory/dlq.json` — the DATA argument of `--dlq-show` — is walked as if it were a program. The Engineer correctly declined to change the rule's core alone. Ruling: within a command segment, a token is in **program position** only when it is (a) the segment head; (b) the first non-option operand after an interpreter (`node`, `bash`, `sh`, `zsh`, `python*`, `perl`, `ruby`, `deno`, `bun`); or (c) the operand following a wrapper that restarts program position (`-c`, `eval`, `exec`, `xargs`, `env`, `sudo`, `nohup`, `time`, `command`, `source`/`.`). Every other token is an **argument** and is not walked. Independently, tokens with a data-typed extension (`.json`, `.md`, `.txt`, `.yml`/`.yaml`, `.sqlite`, `.ndjson`, `.csv`, `.log`) are never programs in any position. Consequences, stated: `bash tests/run.sh src/bin/ai` stays caught (b); `node "${AIOS}/shared/x.mjs" tests/run.sh` is NOT flagged — the framework helper, not the skill line, decides what it does with its argument, and that helper is already install-resolved (E-223/E-225). Fixtures in both directions come first (D-056 R3), including the six `memory_curator` hits as positives-for-allow.

### §3 — Playwright download out of the default path (E-235, Tier 2, `ci_gate`)
`install-ai-os.sh` → `do_mcp_setup` downloads Chromium for `vibe-check-mcp` unbounded; it ran over an hour locally and never finished. Ruling: the default install does NOT download browsers. `ai mcp-setup --browsers` (explicit) or the first `vibe-check` invocation (prompting, bounded by a timeout) does. CI installs browsers in an explicit, cached step so the vibe suites still run there.

### §4 — Environment-dependence review check (E-236, Tier 1)
Three tests this sprint passed on a developer Mac and failed on CI (mirror byte-identity, an unpruned `node_modules` corpus scan, an ambient tmux server). Ruling: the `ai-review` skill and the `critic_tests` agent gain a standing question — "does this assertion depend on what the running machine happens to have?" — and `tests/lib/assert.sh` gains `skip_unless_cmd` / `skip_unless_env` helpers that record a SKIP rather than a false PASS/FAIL. `test-harness-isolation.md` records the rule.

### §5 — Hot policy modules in long-running servers (E-237, Tier 1)
`orchestrator-mcp` kept grading with a stale `traversal-policy.mjs` for a whole session after the mirror changed, so `run_review` cried wolf on every review. Ruling: policy modules (`traversal-policy`, `markdown-exec`, `architect-writes`, `caller-role`) are loaded through one `loadPolicy(name)` helper that re-imports on mtime change (cache-busting `import()` query) — the E-229 pattern applied to MCP. `ai sync` prints which running servers hold stale modules until reload.

### Alternatives considered
1. **§2: stop the walk at the first operand** — rejected; `bash tests/run.sh src/bin/ai`-style chains and wrapper tokens must still restart the walk. **§2: allowlist `.ai/memory/*` paths** — rejected; file-specific, does not fix the class.
2. **§3: keep the download and add a timeout only** — rejected; a timeout on a required step is a flaky install.
3. **§5: restart servers after sync** — rejected as the only path; the harness does not restart MCP servers, and the operator cannot see which one is stale.

### Constraints driving this decision
- Over-blocks outrank under-blocks on gates touching the codebase's own idiom (D-056 R3 lineage).
- A rule's mechanism may differ from a ruling's phrasing when the phrasing was intent; the divergence note is the contract (D-058 §5).
- Verification must run where the property is claimed (D-060 §1).

### Impact
- Unlocks: E-234 (T2), E-235 (T2), E-236 (T1), E-237 (T1). Order: E-234 → E-237 → E-236 → E-235.
- Risk if wrong: §2 under-flags a project script smuggled as an argument to a framework helper — accepted; the helper is install-resolved and reviewed.

### Rollback
§2 `AI_OS_STANDARDS_SKIP=program-position` restores the full walk. §3 `AI_OS_INSTALL_BROWSERS=1` restores the download in install. §4 process + helper only. §5 `AI_OS_POLICY_HOT_RELOAD=0`.

---

---

## [[D-062]] — Program Position Closes on Resolution (Ratified); Host-Relative Performance Budgets; No-Stash Bookkeeping + Conflict-Marker Gate

**Date**: 2026-09-09
**Task**: E-239, E-238 (Engineer handoff 2026-09-09 20:10 UTC; E-234..E-237 complete, master `56348c4`, CI green)
**Decision**: (§1) Ratify the E-234 resolution: program position closes only when an operand actually resolves the program. (§2) Performance budgets are host-relative: an absolute wall-clock budget is enforced only on the reference machine (CI); everywhere else the same test asserts a ratio to a measured baseline on that host. (§3) Bookkeeping never moves between branches by `git stash`; the pre-commit gate rejects conflict markers in any staged file and rejects a `.ai/state.json` that does not parse.

### §1 — Program position: RATIFIED as resolved
D-061 §2's two acceptance cases did pull against each other under a literal reading. The Engineer's resolution is the correct generalisation: program position stays OPEN while the operand does not say what runs — an unreadable variable (`node "$HELPER" …`) or an allowlisted entrypoint (`bash tests/run.sh …`) — and CLOSES on the first operand that resolves the program. That is why `--dlq-show .ai/memory/dlq.json` is an argument (the program resolved at `memory-worker-pool.mjs`) while `bash tests/run.sh src/bin/ai` is still caught. Ratified; the parity blueprint row is amended to this wording.

### §2 — Performance budgets: HOST-RELATIVE (E-239, Tier 2)
Two suites assert absolute budgets ("under 200ms", "hook warm-path under 250ms") that fail on a machine where `node -e 'process.exit(0)'` alone costs ~197ms, and pass on CI. Verified against clean master in a worktree, so it is a policy gap, not sprint fallout: it is the E-236 category one step further — not what the machine has but how fast it is — and neither E-236 remedy fits (nothing to supply; skipping hides a real regression). Ruling:
- Every performance assertion names its **baseline** — a trivial operation of the same kind measured on the same host in the same run (a bare `node` spawn for spawn-bound paths; a no-op hook for hook paths).
- On the **reference machine** (`CI=true`, ubuntu-latest) the absolute budget is enforced as today.
- Elsewhere the test asserts `elapsed ≤ k × baseline + slack` with `k` and `slack` declared next to the budget (defaults `k=2`, `slack=50ms`), so a genuine regression still fails locally while a slow host does not.
- The harness prints both numbers on every run (baseline, elapsed), so a budget failure carries its own evidence (the instrumentation lesson from this sprint).
- An absolute budget with no baseline is a `critic_tests` finding.

### §3 — No-stash bookkeeping + conflict-marker gate (E-238, Tier 2, `git-hooks.md`)
A conflicted `git stash pop` left conflict markers in `.ai/state.json`; they were staged and committed to master without the file being opened, and master carried invalid JSON until the next fix. The two real CI failures that exposed it were nearly dismissed as environmental. Ruling:
- **Rule**: `.ai/` bookkeeping moves between branches by commit + cherry-pick (or a bookkeeping-only commit on the target branch), never by stash. `ENGINEER.md` Core Rules and the `commit-crafter` skill state it.
- **Gate**: `hooks/pre-commit.sh` rejects any staged file containing a conflict marker at line start (`<<<<<<< `, `=======` between them, `>>>>>>> `) and rejects a staged `.ai/state.json` (or any `.ai/*.json`) that does not parse. Both are cheap, deterministic, and would have blocked `44243bc`.
- **Triage rule** (from the near-miss): after a run of environmental failures, a new CI failure is presumed REAL until its log is read — the E-236 question is asked of the failure, never assumed.

### Alternatives considered
1. **§2: skip performance tests off-CI** — rejected; a regression would then only surface after merge. **§2: raise the absolute budgets** — rejected; they would be wrong on the next slower or faster host.
2. **§3: a `git stash` wrapper that warns** — rejected; the gate on the committed content is the checkpoint that matters, and stash is not the only way to stage a conflicted file.

### Constraints driving this decision
- Tests must state what they require of the machine (D-061 §4); speed is a requirement like any other.
- Machine state files (`state.json`) are validated at the boundary where they enter history, not trusted from a tool's exit message.
- Evidence printed beats reasoning remembered (the sprint's own lesson).

### Impact
- Unlocks: E-239 (T2), E-238 (T2). Order: E-238 → E-239.
- Risk if wrong: §2's ratio could pass a slow-but-regressed path on a very fast host — the CI absolute budget catches that case.

### Rollback
§2 `AI_OS_PERF_ABSOLUTE=1` enforces absolute budgets everywhere. §3 `AI_OS_SKIP_CONFLICT_GATE=1`.

---

---

## [[D-063]] — Baselines Include the Instrument (Ratified); Leaked External State Is the Third Environment Dependence

**Date**: 2026-09-09
**Task**: E-240 (Engineer handoff 2026-09-09 21:40 UTC; E-238/E-239 complete, master `bf28ec7`, CI green 4471/0)
**Decision**: (§1) Ratify the E-239 strengthening and generalise it: a performance baseline must include the assertion's own measuring instrument. (§2) "What a previous run left behind" is the third variety of environment dependence after "what the machine has" (E-236) and "how fast it is" (E-239); every suite that creates external state registers cleanup in an EXIT trap before creating it, and the runner sweeps and reports leftovers.

### §1 — Baselines include the instrument: RATIFIED, generalised
D-062 §2 said "a no-op hook" for hook paths. The telemetry assertion's window is dominated by the two `node -e Date.now` calls it uses as a clock, so a bare-hook baseline would flatter it by ignoring its own instrument. The Engineer's `2 × node-spawn + no-op hook` is the correct reading and becomes the rule: **the baseline is the same operation kind PLUS whatever the assertion itself spends to measure it.** A baseline that omits the instrument is a `critic_tests` finding, same as a missing baseline. The literal reading is not wanted.

### §2 — Leaked external state (E-240, Tier 2)
The `ai start` suites leaked 50 tmux servers on one machine: the socket name used `$$` (recycled), and a FAILING assertion skipped the cleanup line, so leaks occurred only when something was already wrong — the worst shape, because the leak compounds the failure that caused it. Fixed at the cause; nothing sweeps generally. Ruling:
- **Register before create.** Any suite that creates external state (tmux servers/sockets, temp dirs outside the per-test sandbox, background processes, lock dirs, `~/.ai-os` mirror writes, `.ai/signal.json` entries) registers its cleanup in an `EXIT` trap BEFORE creating the state; cleanup never depends on reaching a later line. Names come from `mktemp` entropy, never from `$$`.
- **The runner sweeps.** `tests/run.sh` snapshots the inventory of known external-state kinds before the run and diffs after: tmux servers matching the test socket prefix, processes whose argv names the test sandbox, lock dirs under `.ai/`, and temp dirs under the harness root. Leftovers are reported as `LEAKED n <kind>` per suite and fail the run on CI (the reference machine must stay clean); locally they are reported and cleaned with `--sweep`.
- **Standing review question #3** in `critic_tests` / `ai-review`: "what does this test leave behind when an assertion fails halfway?" — alongside "what the machine has" and "how fast it is".
- `test-harness-isolation.md` records all three varieties together.

### Alternatives considered
1. **§1: keep the literal no-op-hook baseline** — rejected; it measured a smaller thing than the assertion did and would have passed a regression in the instrument itself.
2. **§2: rely on each suite's own trap** — rejected as the only path; the incident was a suite that believed it cleaned up. **§2: run every suite in a throwaway VM/container** — rejected for now; Docker is down and CI already is the clean reference; the sweep is cheap and works everywhere.

### Constraints driving this decision
- Evidence printed beats reasoning remembered (D-062): the sweep prints what leaked, per suite, every run.
- A cleanup that runs only on success is not cleanup.
- The reference machine (CI) must start and end clean, or its green is not believable (D-060 §1).

### Impact
- Unlocks: E-240 (T2).
- Risk if wrong: the sweep itself could kill a developer's unrelated tmux server — mitigated by matching only the test socket prefix and sandbox-named processes, never by age or count.

### Rollback
§1 none (test-policy wording). §2 `AI_OS_TEST_NO_SWEEP=1` disables the runner sweep; traps remain.

---

---

## [[D-064]] — EXIT-Trap Chaining in the Harness; Subshell-State Is Review Question #4

**Date**: 2026-09-10
**Task**: E-241 (Engineer handoff 2026-09-09 21:40+ UTC; E-240 complete, master `2a926c8`, CI 4498/0, full run 4501/0 with zero leaks)
**Decision**: (§1) Close the trap-replacement limitation at the cause: the harness chains `EXIT` handlers so a suite's own `trap … EXIT` can no longer replace the cleanup trap, raw `trap … EXIT` in a suite becomes a standards finding, and the 46 existing sites are converted mechanically to `on_exit`. (§2) Institutionalise the subshell-state pattern as standing review question #4 and as an engineering-standards rule: a helper that sets state for its caller is never invoked inside a command substitution.

### §1 — Trap chaining (E-241, Tier 2)
A suite that installs `trap … EXIT` after sourcing `assert.sh` replaces the `register_cleanup` trap; the runner sweep is the backstop, so nothing leaks past the run, but 46 suites are not fixed at the cause. Ruling, both halves:
- **Harness chains.** `assert.sh` shadows the `trap` builtin for the `EXIT` signal only: `trap <cmd> EXIT` appends `<cmd>` to the cleanup registry instead of replacing the handler; every other signal and every other argument shape passes straight to `builtin trap`. Zero suite changes are required for correctness on day one. The registry runs handlers LIFO, each in its own `( … )` so one failing cleanup cannot skip the next, and the harness prints `CLEANUP n handlers` on exit so the evidence is visible.
- **Suites converge.** `on_exit <cmd>` is the documented spelling; a new E-80 standards rule (`tests/**` scope) flags a raw `trap … EXIT` as a P1 finding, and the 46 existing sites are converted in the same task with a mechanical rewrite — the shadow makes the conversion a no-op behaviourally, so the risk is confined to the rewrite's syntax.
- The sweep stays as the backstop; `LEAKED` must remain zero after the conversion (that is the acceptance evidence).

### §2 — Subshell state: review question #4 + standards rule
Three times in two sprints a helper was called as `$(helper …)` and the state it set evaporated (E-239's baseline cache, the E-240 cleanup registry, `_self_stamp`'s output capture). Each was caught by an assertion written for another reason — the system working — and the recurrence is the signal. Ruling:
- **Standing review question #4** (`critic_tests`, `ai-review`, `ai-debug`): "Is this helper ever called inside a command substitution, a pipeline, or a `while read` loop, and does it set state that must outlive that call?"
- **Engineering-standards rule**: a shell helper returns DATA on stdout and sets STATE only in the caller's shell — never both. A helper that must set state is invoked as a plain command and returns data via `printf -v` / a nameref, or the state is recomputed by the caller from the data. The reason is written at each site, as the Engineer already does.
- No lint is funded now: the shape is too idiomatic to grade mechanically without an over-block (D-056 R3); the question plus the rule is the proportionate response. Revisit if a fourth incident occurs.

### Alternatives considered
1. **§1: convert the 46 suites only, no shadow** — rejected; the next suite to write a raw trap reintroduces the hole, and the sweep would again be the only defence.
2. **§1: shadow only, no conversion** — rejected; two spellings for one concept is the kind of drift the standards checker exists to prevent.
3. **§2: a shellcheck-style lint for `$(…)` around state-setting helpers** — rejected for now (over-block risk); question + rule first.

### Constraints driving this decision
- Fix at the cause, keep the backstop (D-063 §2).
- A gate that blocks the codebase's own idiom is a defect (D-056 R3) — hence question-not-lint for §2.
- Evidence printed: `CLEANUP n handlers` and `LEAKED 0` are the proof, not the reasoning.

### Impact
- Unlocks: E-241 (T2).
- Risk if wrong: shadowing `trap` surprises a suite that relies on REPLACING a handler — mitigated: only `EXIT` is chained, `builtin trap - EXIT` still clears, and the shadow is documented in `assert.sh`'s header.

### Rollback
§1 `AI_OS_TEST_NO_TRAP_CHAIN=1` restores the plain builtin (suites already converted to `on_exit` keep working). §2 process only.

---

---

## [[D-065]] — Suppressions Are Explicit Markers, Exemptions Are By Name; §35 Self-Report Closed; Fixture-First for Gate Code

**Date**: 2026-09-10
**Task**: none (Engineer handoff 2026-09-10; E-241 complete, master `9362e2b`, CI 4514/0, `LEAKED 0`, 43 `CLEANUP` lines local and CI agreeing)
**Decision**: (§1) Ratify the E-241 choice and make it policy for every standards rule: a false positive is silenced by an explicit, greppable in-file marker (`# standards:allow-<rule>`), never by loosening the pattern; a file that legitimately falls outside a rule is exempted BY NAME in the rule's config, never by narrowing the rule's scope. (§2) The self-reported §35 violation (a duplicate section appended to an Architect-owned blueprint, caught and reverted before it shipped) is closed with no remediation task; the standing rule "read before write on any Architect-owned file, especially one the handoff says was just updated" is recorded. (§3) Code that enforces a rule — standards rules, hooks, harness primitives — is written fixture-first: the failing fixture exists before the implementation, and the fixture runs on both bash 3.2 and CI's bash before the rule is considered green.

### §1 — Suppression and exemption policy
A heredoc that WRITES a `trap … EXIT` line is data, not an installation, and no pattern distinguishes the two. Loosening the regex would quietly reduce what the rule catches everywhere; a marker keeps every suppression visible to `grep` and to review. Likewise `tests/run.sh` (traps `EXIT INT TERM` without sourcing the registry) is exempted by name, so `tests/lib` stays in scope. Ratified and generalised: every E-80 rule supports `# standards:allow-<rule_id>` on the flagged line or the line above, the checker reports the count of active suppressions per rule in its summary (so a growing count is itself visible), and per-file exemptions live in `standards.json` next to the rule they exempt, with a one-line reason.

### §2 — §35 self-report
The Engineer appended a duplicate subshell-state section to `engineering-standards.md` while syncing mirrors, caught it during the sync, and reverted it; the file's committed diff is the Architect's alone (verified: one `## Subshell State` heading). The failure was writing before reading a file the handoff had said was already updated. Closed: the self-report is the system working, no task. Rule recorded in `ENGINEER.md` Core Rules via the next Engineer edit of that file: before touching any `.ai/` file named in the current handoff, read it first; the handoff is the notice, not the permission.

### §3 — Fixture-first for gate code
Four defects in E-241 were each caught by a fixture and none by reasoning: the shadow swallowed the library's own trap; a `BASHPID` guard absent in bash 3.2 would have behaved differently on macOS than on CI (the environment-dependence class inside the code enforcing it); an acceptance fixture ran in a subshell and tested the opposite case; the rule flagged its own heredoc. Across D-062–D-064 the ratio has not shifted. Ruling: for gate code the failing fixture is written before the implementation, the fixture asserts the property on both the local shell and CI's shell before the rule is called green, and a review of gate code asks first "which fixture would have caught this?" rather than "is the logic right?". This is the D-058 §5 property rule applied to the tools that enforce properties.

### Alternatives considered
1. **§1: loosen the regex for the heredoc case** — rejected (silent reduction in coverage). **§1: narrow the rule's scope to exclude `tests/run.sh`'s directory** — rejected (loses `tests/lib`).
2. **§2: a remediation E-## for the reverted edit** — rejected; nothing shipped, and the report itself is the desired behaviour.
3. **§3: a mechanical bash-3.2 compatibility lint** — deferred; the fixture-on-both-shells rule covers it without an over-block risk.

### Constraints driving this decision
- Coverage reductions must be visible (greppable markers, counted suppressions).
- Architect-owned files are read before written (E-201, this incident).
- Evidence before theory (D-062/D-063): gate code is only as good as the fixture that fails without it.

### Impact
- No E-## registered; the Engineer queue is empty and no work is pending. The §1 marker-count summary and the §2 ENGINEER.md line ride along with the next task that touches the standards checker or the rulefile.
- Risk if wrong: markers could accumulate unnoticed — mitigated by the per-rule suppression count in every checker run.

### Rollback
Policy only; nothing to roll back.

---

---

## [[D-066]] — All-Claude Triad Becomes the Default Topology (Architect on Fable, Engineer on Opus); Overlay Path Fix; Project Cleanup Sprint

**Date**: 2026-09-10
**Task**: E-242, E-243, E-244, E-245, E-246 (user request 2026-09-10)
**Decision**: (§1) The framework DEFAULT topology is the all-Claude Triad — `architect = claude:1` on model `fable`, `engineer = claude:0` on model `opus` — superseding D-050's `agy` default. `agy` and `gemini` remain fully supported providers (D-052 adapters stay), selected by `roles.json` or the `--architect/--engineer` install flags. (§2) The `ai start` failure "Settings file not found: .claude/settings.architect.json" is a path-resolution defect: the overlay is referenced cwd-relative; it becomes absolute and `ai pane` self-heals a missing overlay. (§3) `ai init`/`ai install`/`ai sync` banners and every owner/footer label derive from `roles.json` (provider AND model), never from a vendor literal. (§4) Workspace directories are generated only for providers that serve a role; unmapped provider workspaces are reported by `ai doctor` and removed only by an explicit `ai sync --prune-providers`. (§5) Repo hygiene and a v3.1.0 release close the D-054→D-066 series.

### Why needed
This project already runs both roles on Claude (D-054). The user hit `Error: Settings file not found: .claude/settings.architect.json` from `ai start`, `ai init` still announces an `agy` Architect, `roles.json` carried no model so both panes ran the same model, and the repo accumulated agy/gemini workspace residue (`.gemini/`, `.agents/`), a stray tracked file named `bash` containing a shell error, an untracked `.DS_Store`, a Gemini-era plan, and 124 task rows in `TASKS.md`.

### §1 — Default topology
- `src/templates/roles.json` and `_write_roles_json` defaults: `architect: {provider: claude, pane_identifier: "1", model: "fable"}`, `engineer: {provider: claude, pane_identifier: "0", model: "opus"}`. Model values are the CLI's aliases (`fable`, `opus`, `sonnet`) or a full model id; `ai pane` forwards `--model` (already wired, E-208).
- Rulefile headers: `ARCHITECT.md` "defaults to the `agy` provider" → "defaults to the `claude` provider (model `fable`)"; `ENGINEER.md` §35 redirect text names the Architect by role, not by `agy`. `GEMINI.md`/`CLAUDE.md` shims stay (D-051).
- This project's `.ai/roles.json` now carries the models (Architect edit, this decision).

### §2 — Overlay path defect (E-242)
`provider-adapter.mjs` emits `--settings .claude/settings.{role}.json` relative to the process cwd; any pane whose shell does not start in the project root (rc-file `cd`, a pre-existing session, a subdirectory launch) fails at the CLI. Ruling: the resolver substitutes an ABSOLUTE path rooted at the `.ai/` parent; `ai pane` generates a missing overlay from `roles.json` before exec (same code path as `ai sync`, idempotent), and `ai start` verifies each role's overlay before sending keys. Regression tests launch from a subdirectory and from a cwd outside the project.

### §3 — Banners and labels derive from roles.json (E-243)
`ai init`/`ai install`/`ai sync` print `Architect (claude · fable)` / `Engineer (claude · opus)` from the mapping; the legacy `'Architect (Agy)'` owner-regex (`src/bin/ai` ~1657), the `Agy (Architect)` footer (~1927), and any remaining vendor literal in user-facing text are replaced by role-derived labels. README and CONTRIBUTING describe the all-Claude default with `agy`/`gemini` as alternative providers.

### §4 — Provider workspace hygiene (E-244)
`ai sync` provisions `.claude/`, `.agents/`, `.gemini/` only for providers mapped in `roles.json` (plus `.claude/` whenever the hooks need it). `ai doctor` reports an unmapped provider's workspace as `stale provider workspace`; `ai sync --prune-providers` removes it, manifest-aware (E-220), never silently. `src/agents`, `src/gemini` adapters stay (D-052). In this repo `.gemini/` and `.agents/` are removed by that flag once it exists.

### §5 — Hygiene + release (E-245, E-246)
Remove the tracked stray `bash` file; gitignore `.DS_Store` and `testsprite_tests/tmp/`; archive DONE tasks out of `TASKS.md` (`archive_done_tasks`, state stays intact); `plans/agentic_upgrades_phase2.md` (Gemini-era, `better-sqlite3`) moved to `plans/archive/` by the Architect. Then `release-manager` cuts **v3.1.0** with a CHANGELOG aggregating D-054→D-066 / E-208→E-246.

### Alternatives considered
1. **Keep `agy` as the default and document the override** — rejected; the default should be the topology the maintainer runs and the one the gates were hardened for.
2. **Fix the overlay error by documenting "run ai sync first"** — rejected; the path is wrong for any cwd, and doctor already knew the file was missing — the launcher must not hand the failure to the CLI.
3. **Delete `src/gemini`/`src/agents`** — rejected (D-052); only unmapped workspace copies go, and only explicitly.

### Constraints driving this decision
- Provider-agnostic by configuration (D-050/D-052): defaults change, adapters stay.
- No vendor literal in user-facing text; labels derive from `roles.json` (D-054 lineage, E-213).
- Nothing is deleted silently (E-220 manifest discipline).

### Impact
- Unlocks: E-242 (T2), E-243 (T2), E-244 (T2), E-245 (T1), E-246 (T1 release, last). Order: E-242 → E-243 → E-244 → E-245 → E-246.
- Risk if wrong: a downstream project still mapped to `agy` sees no change (its `roles.json` wins); a fresh install gets the all-Claude default and needs only `claude` on PATH.

### Rollback
`ai install --architect agy:1 --engineer claude:0` restores the D-050 mapping per project; the template default can be reverted in one commit. §2 is a pure fix.

---

---

## [[D-067]] — Restore `ai sync`'s Dead Half; Strip Only for Gemini; Booted-Build Staleness Is Announced, Not Hot-Reloaded; Suppression Counts; Empty-Corpus Guard

**Date**: 2026-09-10
**Task**: E-247, E-248, E-249, E-250, E-251 (Engineer handoff 2026-09-10; D-066 sprint complete, v3.1.0 tagged, master `dded03d`)
**Decision**: Four deliberately-unfixed defects are ruled and funded, plus the fifth harness variety. (§1) `do_sync`'s unreachable second half is restored step-by-step under fail-open guards with a reachability test. (§2) `strip_gemini_agent_fields` is a Gemini-provider adapter step and runs only when producing a `.gemini/` workspace — never on the install mirror. (§3) A running MCP server announces the build it booted with; `ai sync`/install report stale running servers; task completion requires install + restart evidence when server or CLI code changed; the state projector is NOT hot-reloaded. (§4) D-065's suppression-count summary ships as its own task. (§5) A rule-scanning suite fails when its corpus is empty. Also ratified: the E-244 reversal of E-212's keep-unserved-workspace behaviour, and recording 3.0.0 as missing rather than reconstructing it.

### §1 — `do_sync` second half (E-247, Tier 2, `bug-reproducer` first)
Since E-217's early `return 0`, hook install, doc regeneration, the WAL checkpoint, REPO_MAP, the Memory Palace index, the E-233 gitignore and the E-237 policy report have not run on `ai sync`; the command never prints "Done." and a trial restore exits 1 under `set -e`. Ruling: restore the block one step at a time, each step wrapped so a failure prints `sync: <step> skipped — <reason>` and continues (fail-open, as every step was designed); `ai sync` ends with a step summary and the literal `Done.`; a reachability test asserts every named step's marker appears in the output of a full sync in a temp project, and a second test asserts the summary line is present on the happy path. The early return is replaced by the collision-guard's own error branch only.

### §2 — Frontmatter strip (E-248, Tier 2)
The strip exists because the Gemini CLI rejects Claude-only frontmatter keys. Running it on the install mirror means E-212 provisioning copies stripped files into `.claude/agents/`, so a Claude Architect loses `allowed-tools`, `user-invocable`, `disable-model-invocation` — degrading the D-066 default. Ruling: the mirror is canonical and untouched; the strip is applied only to the copy written into a `.gemini/` workspace when `gemini` serves a role. Re-install after the fix; a test asserts the three keys survive in `.claude/agents/*.md` after `ai sync` under the default mapping, and are absent only in a `.gemini/` copy.

### §3 — Booted-build staleness (E-249, Tier 2)
ESM caches modules for the process lifetime; the task synchroniser served the pre-E-245 projector and stripped the archive pointer on every write. E-237 hot-reloads the four POLICY modules, and its staleness notice lives inside the dead code of §1. Ruling, three parts and one refusal:
- Every MCP server records its **booted build** (source mtime + short hash of its entry file and `src/mcp/shared/*`) at startup and returns it in `_meta.booted_build` on every tool result; `verify_markdown_sync`, `run_preflight` and `ai doctor` compare it with the mirror and emit `[STALE_SERVER] <name> booted <ts>, mirror changed <ts> — restart required`.
- `ai sync` and `install-ai-os.sh` print the same list at the end (the E-237 notice, reachable again via §1).
- **Task completion gate**: `ai-task` refuses to mark DONE a task whose diff touched `src/mcp/**` or `src/bin/**` unless the handoff/LOG records `bash install-ai-os.sh` + a server restart (the three CI-only failures this sprint were all a laptop mirror a release behind).
- **Refusal**: `state-db` / the projectors are NOT hot-reloaded. The write path's correctness must not depend on a mid-process module swap; a stale server is announced and restarted, not patched live (the D-056 restraint applied to state).

### §4 — Suppression-count summary (E-250, Tier 1)
D-065's carried instruction ships on its own: the standards checker prints active `# standards:allow-<rule>` suppressions per rule in every summary, and lists the by-name exemptions from `standards.json`.

### §5 — The scan that never ran (E-251, Tier 1)
Three rule-scanning suites built their corpus with `find` over roots that E-244 stopped provisioning; `find` failed, the corpus was empty, and the suites would have reported "no violations" forever. Ruling: a harness helper `corpus_or_fail <min> <root>…` builds the corpus, fails the suite when a root is missing or the count is below the minimum, and prints the count; the three suites use it; standing review question #5 for `critic_tests`/`ai-review`: "can this scan return an empty set and still pass?".

### Ratifications
- **E-244 reverses E-212's keep-unserved-workspace rule** — ratified; the properties E-212 needed (an unserved provider never aborts the sync; a served one gets its role's skills) hold on both sides and are asserted.
- **CHANGELOG records 3.0.0 as untagged and unchangelogged** rather than reconstructing it — ratified; a reconstructed section would be fiction.

### Alternatives considered
1. **§1: delete the dead half** — rejected; every step in it is a ruled feature that was silently lost.
2. **§3: hot-reload `state-db` like the policy modules** — rejected (write-path integrity); **§3: have servers exit on source change** — rejected (the harness does not restart them; an announced stale server is recoverable, a dead one is not).
3. **§2: keep the strip and re-add keys for Claude** — rejected; two transformations of one file drift.

### Constraints driving this decision
- Fail-open steps must still be REACHABLE and must SAY when they skip (§1).
- The mirror is canonical; provider-specific transformations happen at the provider boundary (D-052).
- State writes never depend on live module swaps; staleness is announced with evidence (D-062 lineage).

### Impact
- Unlocks: E-247 (T2), E-248 (T2), E-249 (T2), E-250 (T1), E-251 (T1). Order: E-247 → E-248 → E-249 → E-251 → E-250 (restore reachability first, since §3's notice depends on it).
- Risk if wrong: §1 could resurface an old failing step — mitigated by per-step fail-open wrappers and the reachability test.

### Rollback
§1 `AI_OS_SYNC_MINIMAL=1` stops after provisioning (the current behaviour, made explicit). §2 `AI_OS_STRIP_MIRROR=1`. §3 `AI_OS_BUILD_STAMP=0` suppresses the meta and the gate. §4/§5 helpers only.

---
