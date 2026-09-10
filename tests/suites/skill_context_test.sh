#!/usr/bin/env bash
# skill_context_test.sh — Tests for E-100: operational skills must run in the
# main thread (context: default), not fork into a summary-returning subagent
# (forked-execution-drift incident). Review/audit orchestrators legitimately
# keep context: fork. `context: local` is NOT a valid Claude Code value and
# must appear nowhere.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== skill_context_test.sh (E-100) ====="

ctx() { grep -E '^context:' "$1" 2>/dev/null | head -1 | awk '{print $2}'; }

# ── Operational skills run in-thread (context: default) — source + .claude exec copy
for s in ai-digest trigger-audit ai-sync-state; do
  assert_contains "T-100: $s source is default" "default" "$(ctx "${REPO_ROOT}/src/shared/skills/$s/SKILL.md")"
  assert_contains "T-100: $s .claude exec copy is default" "default" "$(ctx "${REPO_ROOT}/.claude/skills/$s/SKILL.md")"
  # E-244: .agents/ is provisioned only for a project with a role bound to agy.
  if [[ -f "${REPO_ROOT}/.agents/skills/$s/SKILL.md" ]]; then
    assert_contains "T-100: $s .agents copy is default" "default" "$(ctx "${REPO_ROOT}/.agents/skills/$s/SKILL.md")"
  else
    _skip "T-100: $s .agents copy (workspace not provisioned — no role bound to agy)"
  fi
done
assert_contains "T-100: ai-compact source is default"   "default" "$(ctx "${REPO_ROOT}/src/claude/skills/ai-compact/SKILL.md")"
assert_contains "T-100: ai-compact .claude copy default" "default" "$(ctx "${REPO_ROOT}/.claude/skills/ai-compact/SKILL.md")"

# ── Review/audit orchestrators legitimately keep context: fork ───────────────
assert_contains "T-100: ai-review stays fork (review orchestrator)" "fork" "$(ctx "${REPO_ROOT}/src/claude/skills/ai-review/SKILL.md")"
assert_contains "T-100: architectural-aligner stays fork" "fork" "$(ctx "${REPO_ROOT}/src/agents/skills/architectural-aligner/SKILL.md")"

# ── Critic personas (agents) legitimately keep fork (parallel-spawnable) ─────
assert_contains "T-100: critic_clean_code agent stays fork" "fork" "$(ctx "${REPO_ROOT}/src/claude/agents/critic_clean_code.md")"

# ── `context: local` (invalid Claude Code value) must appear NOWHERE ─────────
# grep -rl on a missing directory errors; name it only when it is there.
AGENTS_SKILLS_ROOT=""
[[ -d "${REPO_ROOT}/.agents/skills" ]] && AGENTS_SKILLS_ROOT="${REPO_ROOT}/.agents/skills"
local_hits=$(grep -rlE "^context:[[:space:]]*local" "${REPO_ROOT}/src/shared/skills" "${REPO_ROOT}/src/claude/skills" "${REPO_ROOT}/src/agents/skills" "${REPO_ROOT}/.claude/skills" ${AGENTS_SKILLS_ROOT:-} 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-100: no invalid 'context: local' anywhere" "0" "$local_hits"

# ── No operational skill still forks ─────────────────────────────────────────
for s in ai-digest trigger-audit ai-sync-state ai-compact; do
  if grep -qE "^context:[[:space:]]*fork" "${REPO_ROOT}/.claude/skills/$s/SKILL.md" 2>/dev/null; then
    _fail "T-100: $s must NOT be context: fork"
  else
    _pass "T-100: $s is not context: fork"
  fi
done

# ── In-thread write-capable: ai-digest must hold Write (it persists DIGEST.md) ─
# Under context: default the skill runs in-thread, so it needs its own write
# tools — a read-only allowed-tools cannot satisfy "ai-digest updates DIGEST.md".
assert_contains "T-100: ai-digest can Write (in-thread persistence)" "Write" \
  "$(grep -E '^allowed-tools:' "${REPO_ROOT}/src/shared/skills/ai-digest/SKILL.md")"
assert_contains "T-100: ai-compact can Write" "Write" \
  "$(grep -E '^allowed-tools:' "${REPO_ROOT}/src/claude/skills/ai-compact/SKILL.md")"

assert_summary
