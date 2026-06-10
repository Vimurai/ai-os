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