# Robustness Phase 6: Compliance & Infrastructure (2026-04-13)

## 1. Frontmatter Compliance Restoration (Critical)

### The Problem
The Gemini sub-agents (`digest_updater`, `docs-architect`, `gemini_tasks`, `knowledge_architect`, `memory_curator`, `ux_reviewer`) are currently missing mandatory YAML frontmatter. This violates §32 Verification Audit and causes `verification-mcp` to flag warnings.

### The Solution: Frontmatter Injection
Restore the frontmatter to all Gemini agents in `src/gemini/agents/`.
- **Fields**: `name`, `description`, `disable-model-invocation: true`, `user-invocable: true`, `allowed-tools: [...]`.
- **Least Privilege**: Only authorize the specific tools required for each agent's role.

## 2. Capabilities & Registry Alignment (High)

### The Problem
`CAPABILITIES.md` is the source of truth for `ai-exec` and `.mcp.json` enforcement. Currently, it does not explicitly allow writes to `~/.ai-os/usage.sqlite` or `~/.ai-os/config/registry.json`.

### The Solution: Path Authority
Update `CAPABILITIES.md` to reflect the current SQLite-backed architecture.
- **READ**: Add `~/.ai-os/*.sqlite`, `~/.ai-os/config/registry.json`.
- **WRITE**: Add `~/.ai-os/*.sqlite`.

## 3. Resource Leak Prevention (Medium)

### The Problem
`vibe-check-mcp` and `lsp-mcp` use external processes (Playwright Chromium, `tsc`). Improper error handling in loops can result in zombie processes or orphan file descriptors.

### The Solution: Exhaustive Cleanup
Audit all tool implementations for `try...finally` blocks that guarantee closure of browsers, database handles, and temporary files.

---

## Strategic Tasks (P-##)

- [ ] **P-34: Restore YAML frontmatter to all Gemini sub-agents.**
  - Fix compliance failure in `src/gemini/agents/`.
  - Authorize toolsets for each agent per role.
- [ ] **P-35: Align `CAPABILITIES.md` with system SQLite paths.**
  - Add write permissions for `~/.ai-os/*.sqlite`.
- [ ] **P-36: Audit MCP servers for resource leaks.**
  - Ensure Chromium and SQLite handles are always closed in `finally` blocks.
- [ ] **P-37: Harden `install-ai-os.sh` and `ai install` logic.**
  - Ensure idempotency and clean up legacy v2 files dynamically.