#!/usr/bin/env bash
# vibe_stamp_alignment_test.sh — E-113: ai-test's vibe stamp must match what
# review_synthesizer requires for a Tier-3 release.
#
# Before the fix, ai-test emitted [VIBE_REPORT] (by appending to the regenerated
# REVIEWS.md view) while review_synthesizer gated Tier 3 on [VIBE_CLEARED] — so a
# release could never satisfy the prerequisite. ai-test now records [VIBE_CLEARED]
# via add_stamp (persists through SQLite → REVIEWS.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

AI_TEST="${REPO_ROOT}/src/shared/skills/ai-test/SKILL.md"
SYNTH="${REPO_ROOT}/src/claude/agents/review_synthesizer.md"

echo "===== vibe_stamp_alignment_test.sh (E-113) ====="

# ── ai-test emits the stamp review_synthesizer needs ─────────────────────────
assert_status 0 "ai-test emits [VIBE_CLEARED]"            grep -qF 'VIBE_CLEARED' "$AI_TEST"
assert_status 0 "ai-test records vibe verdict via add_stamp" \
  grep -q 'add_stamp' "$AI_TEST"
assert_status 1 "ai-test no longer emits [VIBE_REPORT]"   grep -qF 'VIBE_REPORT' "$AI_TEST"
assert_status 1 "ai-test no longer hand-appends the vibe stamp to REVIEWS.md" \
  grep -qE 'Append .*VIBE.* to .*REVIEWS\.md' "$AI_TEST"

# ── the Tier-3 gate list requires [VIBE_CLEARED] ─────────────────────────────
assert_status 0 "ai-test Tier-3 gate lists [VIBE_CLEARED]" \
  grep -qE '\[VIBE_CLEARED\].*7 days|VIBE_CLEARED.*review_synthesizer' "$AI_TEST"

# ── alignment: review_synthesizer requires exactly that stamp ────────────────
assert_status 0 "review_synthesizer requires [VIBE_CLEARED]" \
  grep -qF 'VIBE_CLEARED' "$SYNTH"

# ── 3-copy mirror identity for ai-test ───────────────────────────────────────
assert_status 0 "ai-test .claude mirror identical" \
  diff -q "$AI_TEST" "${REPO_ROOT}/.claude/skills/ai-test/SKILL.md"
assert_status 0 "ai-test .gemini mirror identical" \
  diff -q "$AI_TEST" "${REPO_ROOT}/.agents/skills/ai-test/SKILL.md"
assert_status 0 "ai-test ~/.ai-os mirror identical" \
  diff -q "$AI_TEST" "${HOME}/.ai-os/shared/skills/ai-test/SKILL.md"

assert_summary
