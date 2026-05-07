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
