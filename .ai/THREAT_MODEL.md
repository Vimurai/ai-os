# THREAT_MODEL.md — AI-OS v2
<!-- Created: 2026-03-16 | Trigger: memory-manager-mcp (E-106) + verification-mcp (E-108) added new trust boundaries -->

---

## Trust Boundaries

| Boundary ID | From              | To                          | Protocol  | Auth mechanism         |
|-------------|-------------------|-----------------------------|-----------|------------------------|
| TB-01       | Claude (LLM)      | MCP server (any)            | stdio     | OS process isolation   |
| TB-02       | MCP server        | Local filesystem (~/.ai-os) | Node.js fs| OS file permissions    |
| TB-03       | MCP server        | Project filesystem (cwd)    | Node.js fs| OS file permissions    |
| TB-04       | verification-mcp  | Caller-supplied paths        | Node.js fs| NONE — see TH-003      |
| TB-05       | TestSprite server | External TestSprite API     | HTTPS     | TESTSPRITE_API_KEY     |

---

## Threat Register

### TH-001 — Secret Exfiltration via Memory Store
- **Server**: memory-manager-mcp
- **Attack**: Caller passes a `summary` containing a secret (API key, token). Sanitize() regex
  misses it. Secret is written to `~/.ai-os/memory/signatures.json` and returned by
  `query_signatures` to future LLM contexts.
- **Likelihood**: LOW — sanitize() catches common patterns; the policy contract is the
  primary control.
- **Impact**: MEDIUM — secret persists in a global file shared across projects.
- **Mitigation**: sanitize() heuristic (L-001), policy prohibition in file header.
- **Residual risk**: LOW. Accepted.

### TH-002 — Store File Poisoning
- **Server**: memory-manager-mcp
- **Attack**: Attacker gains write access to `~/.ai-os/memory/signatures.json` and injects
  prompt-injection payload into a stored signature. Next `query_signatures` call returns
  payload into LLM context (L-002).
- **Likelihood**: LOW — requires OS-level write access to the user's home directory.
- **Impact**: MEDIUM — could redirect agent behaviour via injected instructions.
- **Mitigation**: Consuming agents must treat `query_signatures` output as UNTRUSTED content.
- **Residual risk**: LOW. Accepted pending L-002 escaping fix.

### TH-003 — Directory Traversal via `paths` Parameter
- **Server**: verification-mcp
- **Attack**: Caller passes `paths: ["../../../etc"]`. `resolve(cwd, p)` produces an absolute
  path outside the project root. `scanAgentFiles()` recursively reads the directory tree.
  File paths (and YAML frontmatter from any `.md` file on the filesystem) are returned in
  the COMPLIANCE_REPORT.
- **Likelihood**: MEDIUM — the `paths` parameter is documented in the tool's inputSchema.
- **Impact**: MEDIUM — directory enumeration and frontmatter leakage; no raw file content
  returned, no write capability.
- **Mitigation**: NONE currently. D-009 proposes a path allowlist fix.
- **Residual risk**: MEDIUM. Action required — see D-009.

### TH-004 — Supply Chain via Unpinned SDK
- **Server**: both
- **Attack**: `@modelcontextprotocol/sdk: ^1.0.0` allows minor-version bumps on `npm install`.
  A compromised SDK version could execute arbitrary code within the MCP server process.
- **Likelihood**: LOW — SDK is published by Anthropic.
- **Impact**: HIGH — MCP server runs with full OS user permissions.
- **Mitigation**: Add `package-lock.json` (GAP-2). Run `npm audit` in CI.
- **Residual risk**: LOW once lockfile is committed.

### TH-005 — Credential Leak via Environment Variable Logging
- **Server**: TestSprite (existing)
- **Attack**: TESTSPRITE_API_KEY leaks into a log, REVIEWS.md, or git commit.
- **Likelihood**: LOW — Claude is instructed never to log secrets.
- **Impact**: HIGH — key grants access to TestSprite account.
- **Mitigation**: Key stored in OS env, not hardcoded. `.mcp.json` uses reference syntax.
  All `.ai/` files must be audited before each commit.
- **Residual risk**: LOW. Ongoing vigilance required.

---

## New Integrations Added (E-106, E-108)

### memory-manager-mcp (E-106)
- New trust boundary: TB-02 (writes to `~/.ai-os/memory/signatures.json`)
- New trust boundary: TB-03 (reads `<cwd>/.ai/architect.md`)
- Threats introduced: TH-001, TH-002

### verification-mcp (E-108)
- New trust boundary: TB-04 (reads caller-supplied paths — currently unbounded)
- Threats introduced: TH-003

---

## Open Actions

| ID    | Threat | Owner | Status  | Description                                              |
|-------|--------|-------|---------|----------------------------------------------------------|
| D-009 | TH-003 | Claude| OPEN    | Add path allowlist validation to verification-mcp paths  |
| D-010 | All    | Claude| OPEN    | Create CAPABILITIES.md and keep THREAT_MODEL.md current  |
| GAP-2 | TH-004 | Claude| OPEN    | Add package-lock.json to memory-manager-mcp and verification-mcp |
