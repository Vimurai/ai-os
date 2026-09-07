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
