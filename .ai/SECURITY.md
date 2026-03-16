# SECURITY.md — AI-OS v2
<!-- Generated: 2026-03-16 | Reviewed by: security_engineer agent (Claude Sonnet 4.6) -->
<!-- Covers: memory-manager-mcp (E-106), verification-mcp (E-108) Tier 3 commit -->

---

## Threat Model Summary

Full threat model not yet created (THREAT_MODEL.md absent — see P0 note at bottom).
This document captures the immediate findings from the Tier 3 deep security review of
`memory-manager-mcp` and `verification-mcp`.

A THREAT_MODEL.md must be created before the next Tier 3 commit. See Decision Proposal D-009
at the bottom of this file.

---

## 1. memory-manager-mcp — Security Verdict: CONDITIONAL PASS

**File**: `src/mcp/memory-manager-mcp/index.js`

### 1.1 File I/O Scope

PASS. Write path is hard-coded:

```
STORE_DIR  = resolve(HOME, ".ai-os", "memory")
STORE_FILE = join(STORE_DIR, "signatures.json")
```

No caller-controlled path interpolation reaches `writeFileSync` or `readFileSync` for the
store file. The only secondary read is `.ai/architect.md` resolved via `process.cwd()`,
which is fixed at process startup and is read-only (never written).

### 1.2 Input Sanitization

PASS with one LOW finding.

- All three caller-supplied string fields (`summary`, `project_name`, tags) pass through
  `sanitize()` before use.
- `sanitize()` enforces a maximum length (300 / 100 / 50 chars), preventing oversized payloads
  in the store.
- `sanitize()` applies a secret-heuristic regex that redacts patterns matching
  `password=`, `api_key=`, `token=`, long base64 blobs, etc.
- Tags are cast to `String(t)` before sanitization — prevents prototype-pollution via
  non-string array elements.

LOW FINDING (L-001): The secret-heuristic regex in `sanitize()` is best-effort only.
It cannot catch all encoding variants (hex, URL-encoded, split across fields). Callers
must not rely on it as a hard security guarantee; it is a "defense-in-depth" layer only.
The declared security contract in the file header ("Signatures must NOT contain secrets")
remains the primary control.

### 1.3 Command Execution

PASS. No `execSync`, `spawnSync`, `exec`, `spawn`, `child_process`, or `eval` calls are
present anywhere in the file. The only I/O is Node.js `fs` module calls to the fixed store
path. D-002 (execSync forbidden) is respected.

### 1.4 Error Handling

PASS. Both `readStore()` and `writeStore()` are wrapped in try/catch with silent-failure
returns (`[]` and `false` respectively). The secondary read of `.ai/architect.md` is also
wrapped with `/* silent */`. This matches the §31 spec ("silent failure — project-local
context is always prioritized").

### 1.5 Capability Boundary

PASS. Reads: `~/.ai-os/memory/signatures.json`, `<cwd>/.ai/architect.md` (read-only).
Writes: `~/.ai-os/memory/signatures.json` only. No network access, no shell, no process
spawning. Scope is correctly contained.

### 1.6 Prompt Injection Defense

LOW FINDING (L-002): Stored signatures are returned verbatim in `query_signatures` output.
If a stored summary contains markdown or prompt-injection payload injected by a prior
`export_signature` call, it will be returned to the LLM context unescaped. The `sanitize()`
call truncates and strips secrets but does not fence or escape LLM-directed instructions
embedded in text. Returned content should be treated as UNTRUSTED by the consuming agent.

---

## 2. verification-mcp — Security Verdict: CONDITIONAL PASS

**File**: `src/mcp/verification-mcp/index.js`

### 2.1 Directory Traversal

MEDIUM FINDING (M-001): The `paths` input parameter accepts caller-supplied directory paths:

```js
const scanDirs = args.paths?.map(p => resolve(cwd, p)) ?? [/* defaults */];
```

`resolve(cwd, p)` will resolve `../../../etc` style values into absolute paths outside the
project root. `scanAgentFiles()` then calls `readdirSync` and `statSync` recursively on the
resolved path. A caller with MCP tool access can enumerate any directory tree readable by
the Node.js process (i.e., all files accessible to the OS user running the server).

However, `auditAgent()` only calls `readFileSync` on `.md` files, and only extracts
YAML frontmatter fields — it does not return raw file content. The information leakage
vector is therefore limited to: (a) file paths being included in the COMPLIANCE_REPORT
output, and (b) frontmatter key/value pairs from any `.md` file on the filesystem.

Risk is MEDIUM (not HIGH) because: file content is not returned wholesale, only
frontmatter key-value pairs; and MCP tool access already implies a trusted caller in the
AI-OS threat model. However, this is a real traversal vulnerability that should be patched.

Recommended fix (D-009 scope): validate that each resolved path in `scanDirs` starts with
`cwd` or `~/.ai-os` before calling `scanAgentFiles()`. This fix should be proposed as a
new Engineering task.

### 2.2 Input Sanitization — agent_name Filter

LOW FINDING (L-003): The `agent_name` filter uses a `.toLowerCase().includes()` substring
match against full file paths:

```js
mdFiles.filter(f => f.toLowerCase().includes(targetName))
```

A caller supplying `agent_name: "/"` would match every file. A caller supplying a path
component like `agent_name: "../"` could be used to confirm directory traversal results.
Combined with M-001, this amplifies the traversal surface. The fix for M-001 (path
allowlisting) also mitigates this.

### 2.3 Ghost Tool Detection Logic

PASS. The detection logic is sound and bounded:

- `BUILTIN_TOOLS` is a hard-coded `Set` — not read from any external source.
- `isToolAvailable()` grants `mcp__`-prefixed tools a blanket pass (intentional design
  for forward-compatibility with dynamic MCP registration).
- `loadRegistry()` is wrapped in try/catch; a malformed `registry.json` causes a graceful
  empty-map return, not a crash or false-pass.
- The registry path is hard-coded to `~/.ai-os/config/registry.json` — not caller-supplied.

Note: the blanket `mcp__*` pass in `isToolAvailable()` means a Ghost Tool named with the
`mcp__` prefix will not be flagged. This is an acknowledged design trade-off; agents should
not use this prefix for non-MCP tools.

### 2.4 Command Execution

PASS. No `execSync`, `spawnSync`, `exec`, or `eval`. Only `fs` reads. D-002 respected.

### 2.5 Error Handling

PASS. `loadRegistry()` and `auditAgent()` both wrap I/O in try/catch. `auditAgent()`
returns `null` on file-read failure; the caller filters nulls with `.filter(Boolean)`.

---

## 3. .mcp.json — Environment Variable Audit

### 3.1 New Server Entries

`memory-manager-mcp` and `verification-mcp` are present at lines 90–101 of `.mcp.json`.
Neither entry declares an `env` block. No secrets, API keys, or credentials are injected
into these servers. PASS.

### 3.2 Existing Secret-Bearing Entry

`TestSprite` uses `"API_KEY": "${TESTSPRITE_API_KEY}"`. This is the only secret in
`.mcp.json`. It is passed by reference to a shell variable — the literal string
`${TESTSPRITE_API_KEY}` is stored in the file, not the secret value itself. Acceptable.

`TESTSPRITE_API_KEY` must:
- Never appear in LOG.md, REVIEWS.md, DIGEST.md, or any `.ai/` file.
- Never be committed to the repository.
- Be stored in the OS keychain or a `.env` file that is in `.gitignore`.

### 3.3 Capability Sync vs CAPABILITIES.md

CAPABILITIES.md does not exist in `.ai/`. This is a gap — it should be created to
formally document the filesystem scope and allowed-paths for each MCP server. See D-009.

---

## 4. Auth / AuthZ Boundaries

All MCP servers communicate over stdio (StdioServerTransport). There is no network listener,
no HTTP auth layer, and no inter-process token exchange. The trust boundary is: **OS process
isolation only** — any process that can write to the MCP server's stdin is a trusted caller.

Implication: MCP tool access should be treated as equivalent to local shell access for
the OS user running the server. No additional auth layer exists or is planned.

---

## 5. Secrets Handling

| Secret               | Location                  | Rotation mechanism      | Must not appear in  |
|----------------------|---------------------------|-------------------------|---------------------|
| TESTSPRITE_API_KEY   | OS env / .env (gitignored)| Manual (TestSprite dashboard) | Logs, .ai/*, git history |
| signatures.json data | ~/.ai-os/memory/           | N/A (non-secret by policy) | Must not contain secrets — enforced by sanitize() heuristic |

No other secrets are known to be in scope for these two servers.

---

## 6. Dependency Security

Both new servers declare a single dependency: `@modelcontextprotocol/sdk: ^1.0.0`.

- No `package-lock.json` files are present in the individual server directories (only
  `package.json`). A lockfile must be added to each server before production deployment
  to prevent supply-chain drift.
- Audit command once lockfile is present: `npm audit --audit-level=high`

---

## 7. Findings Summary

| ID    | Severity | Server              | Finding                                                                 |
|-------|----------|---------------------|-------------------------------------------------------------------------|
| M-001 | MEDIUM   | verification-mcp    | Caller-supplied `paths` not validated against allowlist — directory traversal possible |
| L-001 | LOW      | memory-manager-mcp  | Secret-heuristic in sanitize() is best-effort; not a hard guarantee     |
| L-002 | LOW      | memory-manager-mcp  | query_signatures returns stored content unescaped — treat output as UNTRUSTED |
| L-003 | LOW      | verification-mcp    | agent_name substring filter amplifies M-001 traversal surface           |
| GAP-1 | INFO     | .mcp.json / .ai/    | CAPABILITIES.md absent — filesystem scope not formally declared         |
| GAP-2 | INFO     | both servers        | No package-lock.json in server directories — supply chain not pinned    |
| GAP-3 | INFO     | .ai/                | THREAT_MODEL.md absent — must be created before next Tier 3 commit      |

No P0 (critical / exploit-ready) threats identified. M-001 is the highest-severity finding
and should be resolved in the next Engineering sprint.

---

## 8. Decision Proposals

**D-009** (PROPOSED): Add path allowlist validation to `verification-mcp` `verify_compliance`
— reject any `paths` entry that does not resolve to a prefix of `cwd` or `~/.ai-os`.
Implement as a new Engineering task before next Tier 3 commit.

**D-010** (PROPOSED): Create `.ai/CAPABILITIES.md` formally declaring filesystem scope per
MCP server, and `.ai/THREAT_MODEL.md` capturing the trust boundaries introduced by
memory-manager-mcp and verification-mcp.

---

## P0 Notification

No P0 threats are currently unmitigated. The highest active finding is M-001 (MEDIUM) in
`verification-mcp`. It does not enable remote code execution or secret exfiltration under
the current trust model (stdio-only, local OS user), but must be patched before exposing
these tools to any multi-user or networked context.
