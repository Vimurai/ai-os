# SECURITY.md — AI-OS v2
<!-- Generated: 2026-03-23 | Reviewed by: security_engineer agent (Claude Sonnet 4.6) -->
<!-- Covers: E-129 (ai-exec worktree trap), E-130 (AQG hook), E-131–E-135 (new skills/agents) -->
<!-- Previous review: 2026-03-16 (memory-manager-mcp E-106, verification-mcp E-108) -->

---

## Threat Model Summary

Full threat register: see [THREAT_MODEL.md](THREAT_MODEL.md).

Current highest-severity open finding: **TH-003 / M-001** (MEDIUM) — directory traversal via
caller-supplied `paths` in `verification-mcp`. No P0 (critical) threats are active.

---

## 1. Scope of This Review (2026-03-23)

This review covers changes introduced in commits `ea8e91e` and `d351dc9` (sprint E-129–E-135):

| Component | Change |
|-----------|--------|
| `hooks/post-tool-use.sh` | New AQG (Automatic Quality Gate) PostToolUse hook |
| `src/bin/ai-exec` | Worktree trap extended to ERR + SIGINT + SIGTERM; orphan cleanup added |
| `src/bin/ai` | AQG hook registered into `.claude/settings.json` via Python embed |
| `src/claude/agents/aqg-resolver.md` | New agent — autonomous test-failure fixer |
| `src/claude/skills/commit-crafter/SKILL.md` | New skill — commit formatting automation |
| `src/claude/skills/bug-reproducer/SKILL.md` | New skill — empirical bug validation gate |
| `src/shared/skills/release-manager/SKILL.md` | New skill — sprint release lifecycle |
| `src/claude/skills/ai-review/SKILL.md` | Updated — MCP stamp instead of direct REVIEWS.md write |
| `src/gemini/agents/docs-architect.md` | New agent — doc drift auditor |
| `src/gemini/skills/ai-review/SKILL.md` | Updated — MCP stamp instead of direct REVIEWS.md write |

---

## 2. AQG Hook (hooks/post-tool-use.sh) — Security Assessment

### 2.1 Input Handling Pattern

The hook reads stdin into `$INPUT` (raw JSON from the MCP tool call). The JSON is passed to
Python via the environment variable `HOOK_INPUT` rather than as a shell argument or pipe
substitution. This is the correct pattern — it avoids shell word-splitting and injection
through tool input values that contain special characters or shell metacharacters.

**PASS**: Input is not interpolated into shell commands at any point.

### 2.2 Path Normalization

The Python block uses `os.path.normpath(os.path.abspath(file_path))` and then
`os.path.relpath(norm, cwd)` to compute a relative path. The check `rel.startswith("src")`
guards whether to run tests.

**Finding (LOW — L-004)**: `os.path.abspath()` resolves symlinks lazily and uses the Python
process's `cwd` at evaluation time, which is the hook's working directory (set by Claude).
If a tool call writes a file via a path that traverses outside the project root (e.g.
`/tmp/something`), `relpath` will produce a path beginning with `../..` — which will
correctly *not* start with `src`, so the test gate will not fire. This is safe but means the
hook does not guard against Write calls to arbitrary paths outside the project.
Mitigation: this hook is a quality gate, not a security gate. It is not intended to block
out-of-bounds writes (the filesystem MCP server's path restriction handles that).

### 2.3 Test Runner Execution

`bash "$TEST_RUNNER"` executes `tests/run.sh` from the project root, which is obtained via
`git rev-parse --show-toplevel`. The runner path is not caller-supplied.

**PASS**: No injection vector into the test runner invocation. The `$FILE_REL` variable is
used only in the echo output message, never in a command substitution or eval.

**Finding (LOW — L-005)**: `FILE_REL` is echoed directly into the output message
(`echo "... ${FILE_REL} ..."`). If `FILE_REL` contained ANSI escape sequences or terminal
control characters embedded in a file path, they would be emitted to the agent's stderr.
This is cosmetic only — no execution impact since `FILE_REL` is not executed.

### 2.4 Hook Deduplication (src/bin/ai registration)

The Python embed in `src/bin/ai` adds the AQG hook to `PostToolUse` only if the command
string is not already present (`already_agq` guard). This is correct idempotent behavior —
no duplicate hook registrations.

**PASS**: No double-registration vulnerability.

### 2.5 Trust Boundary

The hook runs as a PostToolUse hook: it is invoked by the Claude agent runtime with the
JSON payload of every Write/Edit tool call. The hook has no network access, writes no files,
and does not modify state. It exits 0 (pass) or 1 (block). This is a read-and-gate pattern
with minimal attack surface.

**New trust boundary introduced**: TB-06 (see THREAT_MODEL.md update).

---

## 3. ai-exec Worktree Changes — Security Assessment

### 3.1 Trap Registration Moved Earlier (E-129)

Previous: `trap 'remove_worktree "$WORKTREE_PATH"' EXIT` was registered *after*
`create_worktree()`. New: `trap 'remove_worktree "$WORKTREE_PATH"' EXIT ERR SIGINT SIGTERM`
is registered *before* `create_worktree()`.

**PASS — Security Improvement**: The previous ordering had a TOCTOU window where a signal
(SIGINT, SIGTERM) or early error between `create_worktree()` and trap registration could
leave an orphaned worktree in `/tmp`. The fix closes that window. The expanded signal
coverage (ERR, SIGINT, SIGTERM) ensures cleanup on unexpected exits.

At trap registration time, `WORKTREE_PATH` is still `""` (empty). The `remove_worktree`
function checks `[[ -d "$worktree_path" ]]` — an empty path evaluates to false, so the
trap fires safely even before the path is assigned.

### 3.2 Orphan Cleanup Glob (E-129)

```bash
for _orphan in /tmp/ai-exec-* .ai-worktree-*; do
  [[ -d "$_orphan" ]] && rm -rf "$_orphan" 2>/dev/null || true
done
```

**Finding (MEDIUM — M-002)**: This glob runs unconditionally at ai-exec startup and deletes
any directory matching `/tmp/ai-exec-*`. On a multi-user system or in a CI environment with
concurrent ai-exec invocations, this glob could delete a worktree that belongs to a
*concurrent* ai-exec process, causing that process to fail when it attempts to use its
worktree. This is a race condition / availability issue, not a confidentiality or integrity
issue. The `/tmp/ai-exec-*` pattern is specific enough to be low risk on a single-user
developer machine (the primary target platform per DIGEST.md).

**Mitigation in place**: The `[[ -d "$_orphan" ]]` guard prevents errors on empty globs.
The `2>/dev/null || true` prevents the loop from aborting if `rm` fails.

**Recommended action**: If concurrent ai-exec usage becomes a requirement, scope the cleanup
to orphans older than a threshold (e.g., `find /tmp -name "ai-exec-*" -mmin +60 -exec rm -rf {} +`).
Register as D-011.

### 3.3 Relative Glob in Current Directory

The second glob `.ai-worktree-*` matches relative paths in the current working directory.
At execution time, cwd is the caller's shell directory. If cwd contains directories named
`.ai-worktree-something`, they will be deleted without confirmation.

**Finding (LOW — L-006)**: The `.ai-worktree-*` relative glob deletes from cwd silently.
This is unlikely to cause unintended deletion in practice (the prefix is specific), but it
violates the principle of least surprise for callers who happen to have such a directory.

---

## 4. New Skill/Agent .md Files — Security Assessment

All new skill and agent files are YAML-frontmatter-gated Markdown documents. They contain
instructions for AI agents and do not contain executable code that runs at parse time.

### 4.1 Capability Boundary Compliance

| File | allowed-tools | Assessment |
|------|---------------|------------|
| `aqg-resolver.md` | Read, Edit, Bash, Grep, Glob | Appropriate — needs Bash to run tests |
| `commit-crafter/SKILL.md` | Read, Bash, Glob, Grep | Appropriate — needs Bash for git commands |
| `bug-reproducer/SKILL.md` | Read, Write, Bash, Grep, Glob | Appropriate — needs Write for repro.sh |
| `release-manager/SKILL.md` | Read, Edit, Bash, Glob, Grep | Appropriate — needs Bash for npm/git |
| `docs-architect.md` | Read, Grep, Glob | PASS — read-only, respects Architect constraint |
| `ai-review/SKILL.md` (Claude) | Read, Grep, Glob, Bash | Appropriate for review workflow |
| `ai-review/SKILL.md` (Gemini) | Read, Grep, Glob | Appropriate — audit-only, no writes |

**PASS**: No skill or agent file claims Write access without a documented need for it.
`docs-architect.md` correctly uses Read/Grep/Glob only — no write capability despite being
an agent that produces output (output goes to conversation, not files).

### 4.2 YAML Frontmatter Compliance (D-003)

All new files include required YAML frontmatter fields:
- `name`, `description`, `disable-model-invocation`, `user-invocable`, `allowed-tools`,
  `context`, `agent`.

**PASS**: D-003 (§17.1.2 mandatory YAML frontmatter) satisfied for all new files.

### 4.3 Dynamic Context Injection Review

Several skill files include `!command` dynamic context injection lines that run shell
commands at skill load time:

| Skill | Command injected | Assessment |
|-------|-----------------|------------|
| `bug-reproducer` | `git rev-parse --abbrev-ref HEAD` | SAFE — read-only git query |
| `bug-reproducer` | `bash tests/run.sh 2>&1 | grep "✗" | head -5` | SAFE — read-only test run |
| `commit-crafter` | `grep "^- \[ \]" .ai/TASKS.md | head -5` | SAFE — read-only grep |
| `commit-crafter` | `git diff --staged --name-only` | SAFE — read-only git query |
| `release-manager` | `node -p "require('./package.json').version"` | LOW RISK — node eval of package.json; see note |
| `ai-review` (Claude) | `git diff --staged --name-only | head -10` | SAFE — read-only git query |
| `ai-review` (Gemini) | `git log --oneline -10` | SAFE — read-only git query |

**Finding (LOW — L-007)**: The `release-manager` skill injects
`node -p "require('./package.json').version"` as dynamic context. If `package.json` has been
tampered to include a getter or module that executes code on `require()`, this would execute
that code in the Node.js process at skill load time. This is a theoretical prompt-injection
via supply-chain vector; under the current trust model (local dev machine, project-owned
`package.json`) the risk is LOW.

### 4.4 Prompt Injection Surface in New Files

The new skill/agent files do not consume untrusted external content in their definitions.
Their `!command` injections read from git history, local task files, and tests — all
project-controlled sources.

**PASS**: No prompt injection vector introduced by the new skill/agent files themselves.

### 4.5 commit-crafter — Git Identity Mandate

The `commit-crafter` skill explicitly forbids `--author` flags and `Co-authored-by` trailers.
This aligns with the project's Git Identity mandate (no co-authorship attribution).

**PASS**: No capability boundary violation. The skill does NOT add `--no-verify` bypass.

### 4.6 aqg-resolver — Scope Enforcement

The `aqg-resolver` agent is `user-invocable: false` and `context: fork`. It is triggered
only by the `[LOCKED - AQG FAILED]` signal. Its allowed-tools include `Bash`, which is
necessary for running `tests/run.sh`. The agent explicitly forbids committing, logging, or
return-path modification.

**PASS**: The fork context and the explicit scope restrictions in the agent's instructions
create an appropriate capability boundary. The agent cannot escalate its own permissions.

---

## 5. Capability Boundary Violations — Verdict

No capability boundary violations detected in the E-129–E-135 changes.

Specific checks:

| Check | Result |
|-------|--------|
| New hooks interact with filesystem outside project root | NOT detected |
| New skills claim capabilities beyond documented need | NOT detected |
| New agents can self-escalate (invoke other agents with higher caps) | NOT detected — aqg-resolver is fork-scoped |
| execSync / eval present in new code | NOT detected |
| Secrets written to tracked files | NOT detected |
| Architect-role files (architect.md) written by Claude skills | NOT detected — docs-architect.md is read-only |
| D-002 (execSync forbidden) violated | NOT violated |

---

## 6. Secrets Handling

| Secret | Location | Rotation | Must not appear in |
|--------|----------|----------|--------------------|
| TESTSPRITE_API_KEY | OS env / `.env` (gitignored) | Manual (TestSprite dashboard) | Logs, `.ai/*`, git history |
| signatures.json data | `~/.ai-os/memory/` | N/A — non-secret by policy | Must not contain secrets (sanitize() heuristic, L-001) |

No new secrets or credential types introduced in E-129–E-135.

---

## 7. Auth/AuthZ Boundaries

All MCP servers continue to communicate over stdio (StdioServerTransport). No network
listeners, no HTTP auth. Trust boundary remains: **OS process isolation only**.

New hooks (`post-tool-use.sh`) run as the OS user in the project's shell context. They do
not introduce new auth requirements.

---

## 8. Input Validation Summary

All external inputs are validated at trust boundaries:

| Boundary | Input | Validation |
|----------|-------|------------|
| post-tool-use.sh stdin | Raw JSON tool call payload | Parsed via Python json.loads in try/except; invalid JSON exits 0 (safe fail) |
| ai-exec --allow-execute | LOG.md content | tail -50 grep for [SEC_CLEARED] token |
| verification-mcp paths | Caller-supplied paths | NONE — M-001 open, D-009 pending |
| memory-manager-mcp summary | Caller string | sanitize() heuristic (L-001) |

---

## 9. Path Traversal Defense

| Server / Script | Path construction | Defense |
|-----------------|------------------|---------|
| memory-manager-mcp | Hard-coded STORE_DIR | No traversal possible |
| verification-mcp | resolve(cwd, caller_path) | NONE — M-001 open |
| ai-exec orphan cleanup | /tmp/ai-exec-* glob | Glob fixed prefix; `[[ -d ]]` guard |
| post-tool-use.sh | os.path.normpath(abspath) | Normalized; only triggers for src/ prefix |
| filesystem MCP | Project root enforced by server | Scoped at server level |

---

## 10. Prompt Injection Defense

External content consumed by agents must be fenced as UNTRUSTED before use:

- `query_signatures` output (memory-manager-mcp): treat as UNTRUSTED — L-002 still open.
- Dynamic context injections in skill files: all read project-controlled sources (git, local
  files) — LOW risk (see L-007 for release-manager edge case).
- `docs-architect.md` reads `README.md` and `CONTRIBUTING.md`: content from these files
  enters agent context. If those files were adversarially modified, they could attempt
  prompt injection. Risk is VERY LOW (local project files, developer-controlled).

---

## 11. Dependency Security

- No new `package.json` dependencies introduced by E-129–E-135 changes.
- GAP-2 (no lockfiles in memory-manager-mcp and verification-mcp) remains open.
- TestSprite MCP uses `@testsprite/testsprite-mcp@latest` — unpinned. Recommendation:
  pin to a specific version in `.mcp.json`.
- `npm audit --audit-level=high` should be run against all MCP server directories.

---

## 12. Findings Summary (Cumulative)

| ID    | Severity | Component | Finding | Status |
|-------|----------|-----------|---------|--------|
| M-001 | MEDIUM | verification-mcp | Directory traversal via `paths` — no allowlist | OPEN (D-009) |
| M-002 | MEDIUM | ai-exec | Startup glob deletes all `/tmp/ai-exec-*` — concurrent invocation race | NEW / OPEN (D-011) |
| L-001 | LOW | memory-manager-mcp | sanitize() is best-effort only | OPEN |
| L-002 | LOW | memory-manager-mcp | query_signatures returns stored content unescaped | OPEN |
| L-003 | LOW | verification-mcp | agent_name substring filter amplifies M-001 | OPEN (D-009 mitigates) |
| L-004 | LOW | post-tool-use.sh | abspath uses hook cwd; no out-of-project write detection | NEW / ACCEPTED |
| L-005 | LOW | post-tool-use.sh | FILE_REL echoed without sanitization | NEW / ACCEPTED |
| L-006 | LOW | ai-exec | .ai-worktree-* relative glob deletes from cwd | NEW / ACCEPTED |
| L-007 | LOW | release-manager skill | node -p require() dynamic injection on package.json | NEW / ACCEPTED |
| GAP-1 | INFO | .ai/ | CAPABILITIES.md absent — filesystem scope not formally declared | OPEN (D-010) |
| GAP-2 | INFO | MCP servers | No package-lock.json in server directories | OPEN |
| GAP-3 | INFO | .ai/ | THREAT_MODEL.md was absent — now created | RESOLVED |

**No P0 (critical) threats active.** Highest-severity open items: M-001 and M-002 (both MEDIUM).

---

## 13. Decision Proposals

**D-009** (OPEN): Add path allowlist to `verification-mcp` `verify_compliance` — reject paths
that do not resolve under `cwd` or `~/.ai-os`. Engineering task required.

**D-010** (OPEN): Create `.ai/CAPABILITIES.md` formally documenting filesystem scope per
MCP server.

**D-011** (NEW): Scope ai-exec orphan cleanup to entries older than a time threshold
(e.g., 60 minutes) to avoid concurrent invocation races. Low priority for single-user
dev environments; required before CI/multi-user deployment.

---

## 14. P0 Notification

No P0 threats are currently unmitigated.

M-001 (MEDIUM, verification-mcp directory traversal) and M-002 (MEDIUM, ai-exec orphan
race) are the highest active findings. Neither enables remote code execution, credential
exfiltration, or privilege escalation under the current deployment model (local single-user
developer machine, stdio-only MCP transport).
