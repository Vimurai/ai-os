# SECURITY.md — AI-OS v2

> Full threat detail: `.ai/THREAT_MODEL.md`
> Last updated: 2026-04-14 (security_engineer — E-8 computer-use-mcp)

---

## 1. Secrets Handling

| Secret | Stored Location | How Rotated | Must Never Appear In |
|---|---|---|---|
| TestSprite API key | `.mcp.json` env block (`API_KEY`) | Manual replacement in `.mcp.json`, then `install-ai-os.sh` re-sync | Logs, `.ai/*.md`, git commits, DIGEST.md |
| GitHub credentials (github-bridge-mcp) | System keychain / env var at runtime | External (GitHub PAT rotation) | Any `.ai/` file, any MCP tool output written to disk |
| Host `$DISPLAY` socket path | Must NOT be visible to computer-use-mcp | N/A — should be structurally unreachable | Any MCP tool argument, any log line emitted by computer-use-mcp |
| Xvfb virtual display socket | Ephemeral per session, e.g. `/tmp/.X99-lock` | Auto-destroyed on session end | No persistent logging of socket path |

**Absolute prohibitions:**
- No API key, token, or password may appear in any `.ai/*.md` file, `LOG.md`, `DIGEST.md`, or `SESSION.md`.
- `computer-use-mcp` must never log screenshot payloads, keystrokes, or coordinates to disk in plaintext.
- The Xvfb virtual DISPLAY socket path must be isolated at the process level — it must not be readable via the host `$DISPLAY` env var.

---

## 2. Auth / AuthZ Boundaries

| Boundary | Who Can Cross | Token / Lifetime | Revocation |
|---|---|---|---|
| MCP tool invocation | Claude (Engineer) via MCP protocol only | Session-scoped | Process kill / session end |
| computer-use-mcp screen capture | TestSprite + Vibe Sentinel only (via `ai test --vibe`) | Single test run | TestSprite session teardown |
| computer-use-mcp keyboard/mouse input | TestSprite orchestration only — never direct agent prompt injection | Single test run | TestSprite session teardown |
| filesystem MCP | Scoped to project root (`.`) per `.mcp.json` | Session-scoped | Remove from `.mcp.json` |
| github-bridge-mcp | Claude only, authenticated PAT, read/write to project repo | PAT expiry | GitHub PAT revocation |

**computer-use-mcp must enforce that it only receives commands from a TestSprite session context** — direct invocation by the agent via arbitrary tool calls outside of `ai test --vibe` must be blocked at the MCP server layer.

---

## 3. computer-use-mcp — Threat Model Summary

Full entry: `.ai/THREAT_MODEL.md` section `T-CU-001` through `T-CU-005`.

### T-CU-001: Sandbox Escape — Virtual Display Breakout
- **Attack**: Agent or malicious tool call sets `DISPLAY=:0` (host), bypassing the Xvfb virtual display.
- **Impact**: Full visual access to all host applications including credential stores, browsers, and terminals.
- **Mitigation (REQUIRED)**:
  1. `computer-use-mcp` process must be launched with `DISPLAY` hardcoded to the Xvfb virtual display (e.g. `:99`) in the process environment — never inherited from the parent shell.
  2. The server must reject any tool call that attempts to override or pass a `display` parameter pointing to `:0` or any value other than the configured virtual display.
  3. Xvfb must be started as a non-root user, isolated from the host's X authority file (`XAUTHORITY`).
  4. Do not pass `--no-sandbox` to any Chromium/browser process launched within Xvfb.
- **Residual Risk**: Low if mitigations applied. High if process inherits host `$DISPLAY`.

### T-CU-002: Host Filesystem Access via UI Interaction
- **Attack**: Agent uses keyboard/mouse simulation to open a host terminal, file manager, or browser file picker and read/write files outside the project root.
- **Impact**: Reads `.env`, SSH keys, browser-saved passwords; exfiltrates data; modifies host config files.
- **Mitigation (REQUIRED)**:
  1. Xvfb session must not have access to a running file manager, terminal emulator, or host DE — the display should contain only the application under test.
  2. The virtual display environment must not have `$HOME` pointing to the real user home; use an isolated `$HOME=/tmp/computer-use-sandbox` with no `.ssh/`, no `.gnupg/`, no browser profiles.
  3. `safe-exec-mcp` must be in the computer-use-mcp execution chain — any shell spawned during a test run must pass through `safe-exec-mcp` command analysis before execution.
  4. Directory access from within the Xvfb session must be restricted to the project root via filesystem MCP scoping (already enforced by `.` root in `.mcp.json`).
- **Residual Risk**: Medium. Full mitigation requires OS-level namespace isolation (Docker/bubblewrap). Without that, keyboard-to-terminal attacks remain possible if a terminal is reachable from the virtual display.

### T-CU-003: Privilege Escalation
- **Attack**: `computer-use-mcp` server runs as root or with elevated capabilities, allowing the agent to escalate privileges via UI interaction (e.g., clicking "Allow" on a sudo prompt visible in the virtual display).
- **Impact**: Root access on the host machine.
- **Mitigation (REQUIRED)**:
  1. `computer-use-mcp` must run as the same unprivileged user as the Claude Code process — never as root.
  2. The MCP server process must not be granted `CAP_SYS_ADMIN`, `CAP_NET_ADMIN`, or any elevated Linux capabilities.
  3. The Xvfb virtual display must not render any polkit/sudo/UAC prompts — the application under test must be pre-authorized (no privilege gates within the test UI).
  4. Process isolation: use `setuid`/`setgid` drops or Docker `--user` flag if containerized.
- **Residual Risk**: Low if the server is launched without escalation and the virtual display renders no auth prompts.

### T-CU-004: Credential Theft via Visual Scraping
- **Attack**: Agent uses screen capture to read secrets visible in other applications (browser autofill, password manager, Slack DMs, terminal history with API keys) by pointing the capture at the host display.
- **Impact**: All secrets visible on screen at capture time are exposed to the agent and potentially logged.
- **Mitigation (REQUIRED)**:
  1. Virtual display isolation (T-CU-001) is the primary defense — if the agent cannot reach `:0`, it cannot see host app windows.
  2. Screenshot output must be scoped to the virtual display framebuffer only — the capture API must not accept arbitrary display or window handle arguments from agent tool calls.
  3. Screenshot payloads must never be written to disk in plaintext. If stored at all (for TestSprite assertion), write to a temporary path that is deleted after the test run.
  4. `context-guardian-mcp` must be invoked to verify that screenshot data is not echoed back into any `.ai/` memory file.
- **Residual Risk**: Low with display isolation. Critical without it.

### T-CU-005: Network Exfiltration via Sandboxed Browser
- **Attack**: Agent uses computer-use keyboard/mouse to open a browser within the virtual display, navigate to an attacker-controlled URL, and POST captured data (file contents, environment variables, agent memory) out of the sandbox.
- **Impact**: Exfiltration of project source, secrets, or agent memory to an external server.
- **Mitigation (REQUIRED)**:
  1. The Xvfb virtual display session must not have unrestricted internet access. Network egress from the Xvfb session must be restricted to `localhost` only, or to a specific allowlist (e.g., the local dev server under test).
  2. Implement outbound firewall rule (iptables/pf) scoped to the Xvfb process group: block all non-localhost TCP/UDP by default.
  3. If testing a web application, use a localhost-only dev server — the browser under test should not have general internet access.
  4. `safe-exec-mcp` must block any `curl`, `wget`, `nc`, or `ssh` commands spawned from within the test session.
- **Residual Risk**: Medium without network namespace isolation. Low with process-group-scoped egress firewall.

---

## 4. Input Validation

All external inputs entering the MCP server layer must be validated at the trust boundary before execution.

| Input Surface | Validation Rule |
|---|---|
| Tool call arguments (coordinates, key strings) | Coordinates: validate integer bounds against virtual display resolution (0 ≤ x ≤ W, 0 ≤ y ≤ H). Key strings: allowlist of printable ASCII + known key names — reject control sequences that could inject shell commands. |
| `display` parameter (if exposed) | Must match the configured virtual display ID exactly (e.g., `:99`). Reject anything that does not match this regex: `^:[0-9]{1,3}$` and does not equal the configured value. |
| Screenshot region parameters | Validate bounding box is within virtual display bounds. Reject negative values or values exceeding display dimensions. |
| TestSprite test instruction payloads | Treat as UNTRUSTED. Fence with `<!-- UNTRUSTED: TestSprite instruction -->` before any storage in `.ai/` memory. Strip any embedded shell metacharacters before passing to keyboard simulation. |
| MCP tool caller identity | Validate that the calling context is a TestSprite-initiated `ai test --vibe` session. Reject arbitrary agent-originated calls outside this context. |

**Prompt injection defense**: Any instruction text passed to `computer-use-mcp` from an external source (TestSprite plans, blueprint content) must be treated as UNTRUSTED data, not as executable instructions. The server must never pass raw instruction text to a shell or `eval`-equivalent.

---

## 5. Path Traversal Defense

The `filesystem` MCP server is already scoped to the project root (`.`) per `.mcp.json`. The following additional rules apply to `computer-use-mcp`:

- The server must not accept filesystem paths as tool arguments. All file operations triggered by computer-use actions must pass through the `filesystem` MCP with its existing project-root scope enforcement.
- `../` sequences in any tool argument must be stripped and the call rejected with an error.
- The sandbox `$HOME` must be set to an isolated directory (e.g., `/tmp/computer-use-sandbox`) with no symlinks to the real user home. This directory must be created fresh each session and deleted on teardown.
- Screenshot output paths, if used, must be within the project's `tmp/` or `tests/screenshots/` directory — never an absolute path provided by the caller.

---

## 6. Dependency Security

| Item | Status |
|---|---|
| Lockfile | `package-lock.json` present at project root (npm workspaces, E-1) |
| Audit command | `npm audit` — run before any `npm install` for computer-use-mcp dependencies |
| `dependency_gate` skill | Mandatory before adding any new npm/pip dependency for computer-use-mcp |
| Xvfb system package | Must be pinned to distro LTS version; verify with `apt-cache policy xvfb` or equivalent |
| Claude Computer Use SDK | Pin to a specific version tag in `package.json`; do not use `latest` or `*` |
| Screen capture library | Audit for known CVEs before install; pass through `dependency_gate` |

**New dependency rule**: Any dependency added for `computer-use-mcp` must produce a DECISIONS.md entry (D-002 or higher) via the `dependency_gate` skill before installation. This is already flagged as OUTSTANDING in `LOG.md` (TRIGGER_AUDIT 2026-04-14).

---

## 7. .mcp.json Scope vs CAPABILITIES.md Sync

CAPABILITIES.md does not currently exist at `.ai/CAPABILITIES.md` (file absent as of 2026-04-14 audit). The `.mcp.json` filesystem server is scoped to project root (`.`). When `computer-use-mcp` is added to `.mcp.json`:

- Its entry must include an explicit `env` block with `DISPLAY=:99` (or the configured Xvfb display).
- It must NOT inherit the parent process environment — `env` must be fully explicit.
- The entry must be reviewed against `.ai/blueprints/capabilities.md` section 2 before merge.
- A D-### capability decision entry must be proposed (not directly edited) if the scope expands beyond project root.

**Proposed decision**: D-002 — computer-use-mcp sandbox scope (headless Xvfb display only, no host display access, no host filesystem beyond project root, no unrestricted network egress). This must be formally written to `.ai/DECISIONS.md` before E-8 implementation is merged.

---

## 8. Threat Mitigation Status (Updated: 2026-04-22)

E-8 implementation is complete. All P0 threats have been mitigated in `src/mcp/computer-use-mcp/index.js`.

| Threat ID | Description | Status |
|---|---|---|
| T-CU-001 | Sandbox escape via host `$DISPLAY` | **MITIGATED** — `SANDBOX_DISPLAY = ":99"` hardcoded constant; no env var read; all `execFileSync` calls use explicit minimal env `{ DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME }` (P1 env-spread in healthCheck fixed 2026-04-22) |
| T-CU-002 | Host filesystem access via UI interaction | **MITIGATED** — `SANDBOX_HOME = "/tmp/computer-use-sandbox"` hardcoded; dir created at mode `0o700`; passed to all child processes |
| T-CU-004 | Credential theft via visual scraping | **MITIGATED** — screenshots written to `tmpdir()` with unique name, deleted in `finally` block via `unlinkSync`; no persistent screenshot storage |
| T-CU-005 | Network exfiltration via sandboxed browser | **PARTIALLY MITIGATED** — display isolation prevents host browser access; full network namespace restriction (iptables/pf) is a deploy-time hardening step, not enforced in code |
| T-PI-001 | Prompt injection via keyboard payload | **MITIGATED** — `sanitizeText()` allows only printable ASCII `\x20-\x7E`; `sanitizeKey()` enforces `[a-zA-Z0-9_+\-]+` allowlist |

`[SEC_CLEARED]` condition fulfilled — see LOG.md 2026-04-21.

---

_Generated by security_engineer agent — 2026-04-21. Updated post-implementation by Claude — 2026-04-22._
