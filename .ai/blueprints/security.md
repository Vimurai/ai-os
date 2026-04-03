# Blueprint: Security (§5–6, §8, §13–14, §26, §35)

> Covers: Security architecture, capabilities schema, autonomous gates, AQG, TSRT risk tiers, anti-drift enforcement.

## §5. Security Architecture
- **Isolation Baseline (`ai-exec`)**:
  - Uses `git worktree` for task-level isolation.
  - Flow: `ai update` → (Check risk) → `ai-exec` → `git worktree add` → Execute → `git worktree remove`.
  - **Worktree Resilience**: `ai-exec` MUST `trap EXIT ERR SIGINT SIGTERM` for teardown. On start, run `git worktree prune` and wipe orphaned `.ai-worktree-*` dirs.
  - Capability Isolation: `READ` is default; `WRITE`/`EXECUTE` require explicit flags.
- **Audit Logs**: `post-tool-log.sh` appends `[SECURITY]` prefix for all write/execute ops.
- **Blueprint Enforcement**: Claude cannot modify source code that contradicts §1 without Architect-approved override.

## §6. CAPABILITIES.md Schema
- **Purpose**: Declarative list of allowed operations (Source of Truth for Security).
- **Structure**:
  - `filesystem.read`: Allowed path patterns (e.g., `src/**`, `.ai/**`).
  - `filesystem.write`: Allowed path patterns.
  - `shell.exec`: Allowed commands/patterns.
  - `network.outbound`: Allowed domains.
- **Enforcement**: `ai-exec` and `.mcp.json` MUST align with these rules.

## §8. Autonomous Governance (Gates)
- **Gate 1: Intent Gate (`ai update`)**
  - Trigger: `ai update` is run with new intent (from chat, not UPDATE.md — deprecated).
  - Logic: Classify intent as clear/vague/high-risk. Block vague intent; confirm SEC_CLEARED for high-risk.
- **Gate 2: Quality Gate (`pre-commit`)**
  - Trigger: `git commit` command.
  - Logic: Check `.ai/LOG.md` for recent `[CRITIC_STAMP]`. Block if missing; run `ai review claude`.
- **Gate 3: Execution Gate (`ai-exec`)**
  - Trigger: Shell command matching `EXECUTE` patterns in `CAPABILITIES.md`.
  - Logic: Pause and invoke `security_engineer`. Requires `[SEC_CLEARED]` in LOG.md.

## §13. Automatic Quality Gate (AQG)
- **PostToolUse Hook** (`hooks/post-tool-use.sh`):
  - Runs `tests/run.sh` for any modified `src/**` file.
  - Exits `1` with `[LOCKED - AQG FAILED]` if tests fail, forcing executor to fix before proceeding.
- **Final Commit Hook**:
  - TestSprite E2E journeys before `git commit`.
  - Vibe Audit (Playwright) for visual regression.
  - Blocks commit if coverage drops or vibe fails.

## §14. Token-Saving Risk Tiers (TSRT)
- **Tier 1 (CSS/Docs/Typos)**: Skip critics. Run only linter. Auto-commit with `[TIER_1]`.
- **Tier 2 (Logic/Refactor/Tests)**: Run unit tests + `blueprint-aligner`. Requires manual approval.
- **Tier 3 (Auth/Secrets/Breaking)**: Full Triad: `security_engineer` + `vibe_check` + `chaos_monkey` + parallel critics. Requires `[UACS_VERIFIED]` stamp.

## §26 / §35. Anti-Drift Enforcement
- **Prompt-Level (Identity Files)**:
  - `CLAUDE.md` and `GEMINI.md` MUST contain explicit **ANTI-DRIFT PROTOCOL** section.
  - Claude refuses architecture/feature design; Gemini refuses coding/debugging.
- **Hard-Tool Enforcement (RBAC)**:
  - `patch-mcp` and `propose-patch-mcp`: `roleGuard()` blocks Architect writes to `src/`. Throws `[ANTI_DRIFT_VIOLATION]`.
  - `context-guardian-mcp`: `check_role_access` pre-flight verifies role before writes.
  - `.ai/` and `plans/` are whitelisted for Architect writes.
- **Mechanical Validation**:
  - `verification-mcp` (`ai doctor --compliance`): CRITICAL error if `ANTI-DRIFT PROTOCOL` header missing.
- **Commit Gate**:
  - `hooks/pre-commit.sh` warns if `architect.md` + `src/` co-modified without `[IMPL_DELTA]` proof.
- **Git Identity**: Claude MUST NEVER override git identity. No `--author` flags, no `Co-authored-by` trailers.
