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
  local STATE_FILE="${AI_DIR}/state.json"
  local TASKS_FILE="${AI_DIR}/TASKS.md"
  [[ -f "$STATE_FILE" && -f "$TASKS_FILE" ]] || return 0  # skip if files missing

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

  # Check 2: Compare task count in state.json vs TASKS.md checkbox lines
  if command -v python3 &>/dev/null; then
    local STATE_COUNT TASKS_COUNT STATE_STAMPS
    STATE_COUNT=$(python3 -c "
import json, sys
try:
    s = json.load(open('${STATE_FILE}'))
    print(len(s.get('tasks', [])))
except Exception as e:
    print(0)
" 2>/dev/null || echo 0)
    STATE_STAMPS=$(python3 -c "
import json, sys
try:
    s = json.load(open('${STATE_FILE}'))
    print(len(s.get('stamps', [])))
except Exception as e:
    print(0)
" 2>/dev/null || echo 0)
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
      fi
    fi
  fi
}

check_markdown_sync

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
