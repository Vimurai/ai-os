#!/usr/bin/env bash
# ai_debug_skill_test.sh — Tests for E-43 ai-debug skill TASK_BUDGET upgrade.
#
# Verifies the skill body in src/shared/skills (source of truth) and the two
# tracked mirrors (.claude/skills, .agents/skills) carry the contract bits
# the workflow-optimizations.md blueprint mandates: 3-cycle budget,
# BUDGET_EXHAUSTED state, advisor-mcp escalation, hypothesis distinctness.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== ai_debug_skill_test.sh ====="

SKILL_FILES=(
  "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md"
  "${REPO_ROOT}/.claude/skills/ai-debug/SKILL.md"
  "${REPO_ROOT}/.agents/skills/ai-debug/SKILL.md"
)

echo ""
echo "  [T-DEBUG-S01] All three copies exist"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "exists: ${f#${REPO_ROOT}/}" test -f "$f"
done

echo ""
echo "  [T-DEBUG-S02] Frontmatter advertises advisor-mcp tool"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "${f##*/skills/} → allowed-tools includes advisor-mcp ask_architect" \
    grep -qE 'allowed-tools:.*mcp__advisor-mcp__ask_architect' "$f"
done

echo ""
echo "  [T-DEBUG-S03] Description references TASK_BUDGET"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "${f##*/skills/} → description names TASK_BUDGET" \
    grep -qE '^description:.*TASK_BUDGET' "$f"
done

echo ""
echo "  [T-DEBUG-S04] Body enforces 3-cycle budget"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "${f##*/skills/} → 'Max iterations: 3'"        grep -qE "Max iterations:\*\*[[:space:]]*3|Max iterations:[[:space:]]*3" "$f"
  assert_status 0 "${f##*/skills/} → BUDGET_EXHAUSTED state"     grep -q "BUDGET_EXHAUSTED"               "$f"
  assert_status 0 "${f##*/skills/} → Iteration N/3 prompt"       grep -q "Iteration N/3"                  "$f"
  assert_status 0 "${f##*/skills/} → Hypotheses must be distinct" grep -q "distinct"                      "$f"
done

echo ""
echo "  [T-DEBUG-S05] Escalation block invokes advisor-mcp"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "${f##*/skills/} → BUDGET_EXHAUSTED escalation block present" \
    grep -q "Escalation — BUDGET_EXHAUSTED" "$f"
  assert_status 0 "${f##*/skills/} → calls mcp__advisor-mcp__ask_architect" \
    grep -q "mcp__advisor-mcp__ask_architect" "$f"
  assert_status 0 "${f##*/skills/} → forbids 4th cycle without architect" \
    grep -qE 'Do NOT start a 4th cycle|4th cycle' "$f"
done

echo ""
echo "  [T-DEBUG-S06] Override pathway documented"
for f in "${SKILL_FILES[@]}"; do
  assert_status 0 "${f##*/skills/} → AI_DEBUG_BUDGET env override documented" \
    grep -q "AI_DEBUG_BUDGET" "$f"
done

echo ""
echo "  [T-DEBUG-S07] Source-of-truth and mirrors are byte-identical"
SRC_HASH="$(md5sum "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md" | awk '{print $1}')"
CLAUDE_HASH="$(md5sum "${REPO_ROOT}/.claude/skills/ai-debug/SKILL.md" | awk '{print $1}')"
GEMINI_HASH="$(md5sum "${REPO_ROOT}/.agents/skills/ai-debug/SKILL.md"  | awk '{print $1}')"
assert_status 0 ".claude mirror matches src" \
  bash -c "[[ '$SRC_HASH' == '$CLAUDE_HASH' ]]"
assert_status 0 ".gemini mirror matches src" \
  bash -c "[[ '$SRC_HASH' == '$GEMINI_HASH' ]]"

assert_summary
