#!/usr/bin/env bash
# AI-OS Gate 2 — Quality Gate (pre-commit hook)
# Logic: Block git commit if no recent [CRITIC_STAMP] exists in .ai/REVIEWS.md.
# Action: Print the 'ai review claude' critic prompt and exit 1.
# Install: ai init copies this to .git/hooks/pre-commit in the project repo.

AI_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.ai"

# Not an AI-OS project — skip gate entirely
[[ -d "$AI_DIR" ]] || exit 0

REVIEWS_FILE="${AI_DIR}/REVIEWS.md"
MAX_AGE_DAYS=7

# ── Helper: check for a recent [CRITIC_STAMP] ────────────────────────────────
has_recent_critic_stamp() {
  [[ -f "$REVIEWS_FILE" ]] || return 1

  # Extract all CRITIC_STAMP dates (format: [CRITIC_STAMP] YYYY-MM-DD | ...)
  while IFS= read -r line; do
    if [[ "$line" =~ \[CRITIC_STAMP\][[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      stamp_date="${BASH_REMATCH[1]}"
      # Calculate age in days
      stamp_epoch=$(date -j -f "%Y-%m-%d" "$stamp_date" "+%s" 2>/dev/null \
                    || date -d "$stamp_date" "+%s" 2>/dev/null || echo 0)
      now_epoch=$(date "+%s")
      age_days=$(( (now_epoch - stamp_epoch) / 86400 ))
      if [[ $age_days -le $MAX_AGE_DAYS ]]; then
        return 0
      fi
    fi
  done < "$REVIEWS_FILE"

  return 1
}

# ── E-96: Markdown-as-Read-Only sync check (BLOCKING) ────────────────────────
check_markdown_sync() {
  local SQLITE_FILE="${AI_DIR}/state.sqlite"
  local TASKS_FILE="${AI_DIR}/TASKS.md"
  [[ -f "$TASKS_FILE" ]] || return 0  # skip if TASKS.md missing

  # Check 1: Verify TASKS.md has the generated header (indicates it wasn't hand-edited)
  if ! head -1 "$TASKS_FILE" 2>/dev/null | grep -q "Generated from state.json"; then
    cat >&2 <<'SYNC_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  TASKS.md is missing the generated header.                              ║
║  It may have been hand-edited, violating the Read-Only contract.        ║
║                                                                          ║
║  Fix: run `ai migrate-state --force` to regenerate TASKS.md from        ║
║       state.json, then re-stage and commit.                              ║
╚══════════════════════════════════════════════════════════════════════════╝

SYNC_BLOCK
    exit 1
  fi

  # Check 2: Compare task count in state.sqlite vs TASKS.md checkbox lines (P-30)
  if [[ -f "$SQLITE_FILE" ]] && command -v sqlite3 &>/dev/null; then
    local STATE_COUNT TASKS_COUNT STATE_STAMPS
    STATE_COUNT=$(sqlite3 "$SQLITE_FILE" "SELECT COUNT(*) FROM tasks" 2>/dev/null || echo 0)
    STATE_STAMPS=$(sqlite3 "$SQLITE_FILE" "SELECT COUNT(*) FROM stamps" 2>/dev/null || echo 0)
    TASKS_COUNT=$(grep -c '^\- \[' "$TASKS_FILE" 2>/dev/null || echo 0)

    local DRIFT=$(( STATE_COUNT - TASKS_COUNT ))
    # Allow ±2 drift (in-flight regeneration window); block on larger divergence
    if [[ $DRIFT -lt 0 ]]; then DRIFT=$(( -DRIFT )); fi
    if [[ $DRIFT -gt 2 ]]; then
      cat >&2 <<SYNC_BLOCK2

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  TASKS.md task count (${TASKS_COUNT}) diverges from state.json (${STATE_COUNT}).         ║
║  Drift: ${DRIFT} tasks — exceeds allowed tolerance of ±2.                   ║
║                                                                          ║
║  Fix: run \`ai migrate-state --force\` to resync, then re-stage + commit. ║
╚══════════════════════════════════════════════════════════════════════════╝

SYNC_BLOCK2
      exit 1
    fi

    # Check 3 (E-100): REVIEWS.md header check — only when state.json has stamps
    if [[ "$STATE_STAMPS" -gt 0 ]]; then
      local REVIEWS_FILE="${AI_DIR}/REVIEWS.md"
      if [[ -f "$REVIEWS_FILE" ]]; then
        if ! head -1 "$REVIEWS_FILE" 2>/dev/null | grep -q "Generated from state.json"; then
          cat >&2 <<'REVIEWS_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  REVIEWS.md is missing the generated header but state.json has stamps.  ║
║  REVIEWS.md may have been hand-edited, violating the Read-Only contract.║
║                                                                          ║
║  Fix: regenerate REVIEWS.md via task-synchronizer-mcp::writeState, or   ║
║       run `ai migrate-state --force` to resync, then re-stage + commit. ║
╚══════════════════════════════════════════════════════════════════════════╝

REVIEWS_BLOCK
          exit 1
        fi

        # Check 4 (E-113): Block if REVIEWS.md has manually-appended sections
        # Generated REVIEWS.md uses only [STAMP] lines — any ## heading signals hand-editing
        if grep -qE "^#{2,}" "$REVIEWS_FILE" 2>/dev/null; then
          cat >&2 <<'APPEND_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  REVIEWS.md has manually-appended sections (## headings detected).      ║
║  D-001: REVIEWS.md is a generated view — direct edits are forbidden.   ║
║                                                                          ║
║  Fix: run `ai migrate-state --force` to regenerate REVIEWS.md from      ║
║       state.json and remove hand-appended content. Then re-stage.       ║
╚══════════════════════════════════════════════════════════════════════════╝

APPEND_BLOCK
          exit 1
        fi
      fi
    fi
  fi
}

check_markdown_sync

# ── E-122: architect.md + src/ co-modification warning (§35) ─────────────────
check_architect_src_comodification() {
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null)

  local has_src=0 has_architect=0
  while IFS= read -r f; do
    [[ "$f" == src/* ]] && has_src=1
    [[ "$f" == .ai/architect.md ]] && has_architect=1
  done <<< "$staged_files"

  if [[ "$has_src" -eq 1 && "$has_architect" -eq 1 ]]; then
    # Allow if LOG.md staged change contains an implementation delta marker
    local log_staged
    log_staged=$(git diff --cached -- .ai/LOG.md 2>/dev/null)
    if echo "$log_staged" | grep -qiE "\[IMPL_DELTA\]|\[APPROVED\]|implementation delta"; then
      return 0
    fi
    cat >&2 <<'ARCH_WARN'

⚠  AI-OS GATE 2: ARCHITECT CO-MODIFICATION WARNING
   Both src/ and .ai/architect.md are staged in the same commit.
   This may indicate the Engineer rewrote the blueprint to match flawed logic (§35).

   If intentional, add an [IMPL_DELTA] marker to .ai/LOG.md explaining the
   approved blueprint update, then re-stage LOG.md before committing.

ARCH_WARN
    # Warning only — does not block (exit 0 continues to Gate 2 check)
  fi
}

check_architect_src_comodification

# ── E-33: Registry drift guard ───────────────────────────────────────────────
# Root cause of 2026-04-27 audit: src/config/registry.json gained a new MCP but
# ~/.ai-os/config/registry.json was never refreshed, so `ai sync` regenerated
# .mcp.json from a stale registry and silently dropped the server.
# Run the targeted drift suite only when registry-relevant files are staged.
check_registry_sync() {
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null)

  local touches_registry=0
  while IFS= read -r f; do
    case "$f" in
      src/config/registry.json|src/templates/.mcp.json|install-ai-os.sh|src/bin/ai)
        touches_registry=1
        ;;
    esac
  done <<< "$staged_files"

  [[ "$touches_registry" -eq 0 ]] && return 0

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local suite="${repo_root}/tests/suites/registry_sync_test.sh"
  [[ -f "$suite" ]] || return 0  # suite missing — nothing to enforce

  local out
  if ! out=$(bash "$suite" 2>&1); then
    cat >&2 <<REGISTRY_BLOCK

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: REGISTRY DRIFT — COMMIT BLOCKED                         ║
╠══════════════════════════════════════════════════════════════════════════╣
║  registry_sync_test.sh failed. The local registry, template .mcp.json,  ║
║  or installer is out of sync — shipping this commit would reproduce     ║
║  the 2026-04-27 silent-drop class of regression.                         ║
║                                                                          ║
║  Fix: run \`bash install-ai-os.sh\` to refresh ~/.ai-os/config/registry, ║
║       then re-run \`bash tests/suites/registry_sync_test.sh\` locally.  ║
╚══════════════════════════════════════════════════════════════════════════╝

REGISTRY_BLOCK
    echo "$out" >&2
    exit 1
  fi
}

check_registry_sync

# ── E-48: MCP Stdout Purity Gate ─────────────────────────────────────────────
# Forbids newly added console.log / console.info calls under src/mcp/. Those
# calls would corrupt the JSON-RPC stdout stream MCP clients parse.
# console.error / stderr writes are permitted (shared NDJSON logger).
check_mcp_stdout_purity() {
  local staged_files
  staged_files=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null)
  echo "$staged_files" | grep -qE '^src/mcp/.*\.(js|mjs|cjs|ts)$' || return 0

  local repo_root checker
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  checker="${repo_root}/tests/lib/mcp_purity_check.sh"
  [[ -f "$checker" ]] || return 0  # checker missing — nothing to enforce

  local out
  if ! out=$(bash "$checker" 2>&1); then
    cat >&2 <<MCP_PURITY_BLOCK

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: MCP STDOUT PURITY — COMMIT BLOCKED                      ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Newly added console.log / console.info found in src/mcp/.              ║
║  MCP servers must keep stdout reserved for JSON-RPC traffic; logging    ║
║  belongs on stderr via the shared NDJSON logger.                        ║
║                                                                          ║
║  Fix: replace with                                                       ║
║      import { createLogger } from "../shared/logger.js";                ║
║      const log = createLogger("my-mcp");                                ║
║      log.info("tool", "message", { extras });                           ║
╚══════════════════════════════════════════════════════════════════════════╝

MCP_PURITY_BLOCK
    echo "$out" >&2
    exit 1
  fi
}

check_mcp_stdout_purity

# ── E-82: Engineering-Standards Gate ────────────────────────────────────────
# Invokes the E-80 standards-checker CLI against the staged diff. The CLI
# encapsulates every rule (file size, mcp stdout purity, secrets, tmp-cruft,
# kebab-case naming, shared-helper reuse) defined in src/shared/standards.json.
#
# Honors the blueprint §Rollback Plan escape hatch: AI_OS_SKIP_STANDARDS=1
# bypasses the gate (the CLI itself also handles this; we short-circuit
# here to skip the subprocess fork entirely).
#
# Per blueprint §Execution Constraints: this gate runs in <200ms on a
# typical commit; the CLI emits its own perf-warn to stderr if exceeded.
check_standards_gate() {
  # Rollback flag — silent skip (CLI prints its own STANDARDS_SKIPPED notice
  # when invoked with the flag, but we don't need to spawn the subprocess
  # at all if it's set).
  if [[ "${AI_OS_SKIP_STANDARDS:-0}" == "1" ]]; then
    return 0
  fi

  # Node 22+ baseline (mirrors E-69 installer guard). If absent, skip the
  # gate rather than break commits — degrade gracefully.
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$repo_root" ]] || return 0

  # Locator chain (mirrors E-58 / E-65 / E-75 patterns): in-tree → installed.
  local cli=""
  if [[ -f "${repo_root}/scripts/standards.mjs" ]]; then
    cli="${repo_root}/scripts/standards.mjs"
  elif [[ -f "${HOME}/.ai-os/scripts/standards.mjs" ]]; then
    cli="${HOME}/.ai-os/scripts/standards.mjs"
  else
    # Pre-E-80 install: gate not yet wired. Skip rather than fail.
    return 0
  fi

  # Run the CLI from the repo root so its `--staged` git query resolves
  # against the actual project.
  local out rc
  out=$(cd "$repo_root" && node "$cli" check --staged 2>&1)
  rc=$?

  if [[ $rc -eq 0 ]]; then
    return 0
  fi

  cat >&2 <<'STANDARDS_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: ENGINEERING-STANDARDS — COMMIT BLOCKED                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║  scripts/standards.mjs flagged one or more error-severity violations    ║
║  in the staged diff. The full report follows.                            ║
║                                                                          ║
║  Common fixes:                                                           ║
║    • Split files over 1000 lines into focused modules under src/shared/ ║
║    • Replace console.log/info in src/mcp/** with the shared NDJSON      ║
║      logger (src/mcp/shared/logger.js).                                 ║
║    • Remove .tmp / .bak / .swp / .orig editor cruft before staging.    ║
║    • Rename files to kebab-case / camelCase / PascalCase (no            ║
║      Mixed_Snake) for ESM resolver safety.                              ║
║    • Strip leaked secret patterns (AWS / Stripe / Slack / GitHub PATs / ║
║      PRIVATE KEY blocks).                                                ║
║                                                                          ║
║  Rollback (last resort): re-run with AI_OS_SKIP_STANDARDS=1.            ║
╚══════════════════════════════════════════════════════════════════════════╝

STANDARDS_BLOCK
  echo "$out" >&2
  exit 1
}

check_standards_gate

# ── Gate 2 check ─────────────────────────────────────────────────────────────
if has_recent_critic_stamp; then
  exit 0
fi

# Gate blocked — no recent [CRITIC_STAMP] found
cat >&2 <<'GATE'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: QUALITY GATE — COMMIT BLOCKED                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║  No recent [CRITIC_STAMP] found in .ai/REVIEWS.md (required: ≤7 days) ║
║                                                                          ║
║  A critic review is mandatory before committing.                         ║
║  Run `ai review claude` and paste the prompt into Claude Code.           ║
╚══════════════════════════════════════════════════════════════════════════╝

GATE

# Print the full critic prompt so the user can act immediately
cat >&2 <<'CLAUDE_PROMPT'
━━ REVIEW PROMPT — Claude (Parallel Critics) ━━━━━━━━━━━━━━━━━━━━━━━━
Paste this into Claude Code:

"You are the Principal Software Engineer running a self-review.
Execute these three critics IN PARALLEL using sub-agents:

1. critic_arch     — Review src/ against .ai/architect.md. Flag any
                     code that contradicts the System Philosophy or
                     breaks domain sovereignty rules.

2. critic_security — Review src/ and hooks/ for OWASP Top 10,
                     shell injection, env variable leakage, and
                     capability boundary violations per CAPABILITIES.md.

3. critic_tests    — Review test coverage. Identify untested paths,
                     missing edge cases, and quality gate gaps.

After all three complete, synthesize findings and append to .ai/REVIEWS.md:
  [CRITIC_STAMP] YYYY-MM-DD | <summary of critical findings>

A [CRITIC_STAMP] is required to unblock Gate 2 (pre-commit hook)."
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CLAUDE_PROMPT

exit 1
