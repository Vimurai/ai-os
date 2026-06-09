#!/usr/bin/env bash
# task_planner_routing_test.sh — Tests for E-64.
#
# Verifies that the task-planner skill (Gemini-owned) explicitly teaches
# Step 4 path-classification + the is_framework_task payload contract
# from .ai/blueprints/task-routing.md, and stays in sync with its
# ~/.ai-os/ mirror.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SKILL_SRC="${REPO_ROOT}/src/agents/skills/task-planner/SKILL.md"
SKILL_MIRROR="${HOME}/.ai-os/agents/skills/task-planner/SKILL.md"

echo "===== task_planner_routing_test.sh ====="

# ── T-PR-S01: skill teaches the framework-classification step ─────────────────
echo ""
echo "  [T-PR-S01] task-planner SKILL.md introduces Step 4 — Classify Workspace"

assert_status 0 "skill file exists" \
  test -f "$SKILL_SRC"

assert_status 0 "Step 4 — Classify the Workspace section present" \
  grep -q 'Step 4 — Classify the Workspace' "$SKILL_SRC"

assert_status 0 "explicit framework-path triggers (~/.ai-os/, ai-os-v2/src/**)" \
  grep -q '~/.ai-os/' "$SKILL_SRC"
assert_status 0 "explicit ai-os-v2/src/** trigger documented" \
  grep -q 'ai-os-v2/src' "$SKILL_SRC"

# ── T-PR-S02: payload contract surfaced ──────────────────────────────────────
echo ""
echo "  [T-PR-S02] add_task example carries is_framework_task"

assert_status 0 "skill names is_framework_task in the add_task call" \
  grep -q 'is_framework_task' "$SKILL_SRC"

assert_status 0 "skill warns about [WORKSPACE_NOT_FOUND] failure mode" \
  grep -q 'WORKSPACE_NOT_FOUND' "$SKILL_SRC"

assert_status 0 "skill names \$AIOS_WORKSPACE explicitly" \
  grep -q 'AIOS_WORKSPACE' "$SKILL_SRC"

# ── T-PR-S03: ambiguity guidance documented ──────────────────────────────────
echo ""
echo "  [T-PR-S03] ambiguous-classification fallback rule documented"

assert_status 0 "skill specifies project-level default on ambiguity" \
  grep -qE 'ambiguous|Ambiguous' "$SKILL_SRC"

# ── T-PR-S04: 'What NOT to Do' carries the routing prohibition ───────────────
echo ""
echo "  [T-PR-S04] anti-pattern call-out forbids cross-project leakage"

assert_status 0 "What NOT to Do mentions framework-level routing" \
  grep -qE 'framework-level tasks|framework workspace' "$SKILL_SRC"

# ── T-PR-S05: ~/.ai-os mirror is byte-identical ──────────────────────────────
echo ""
echo "  [T-PR-S05] ~/.ai-os/ mirror tracks src/ verbatim"

if [[ -f "$SKILL_MIRROR" ]]; then
  assert_status 0 "src and ~/.ai-os mirror are byte-identical" \
    cmp -s "$SKILL_SRC" "$SKILL_MIRROR"
else
  echo "  ⚠ mirror absent — install-ai-os.sh hasn't run since E-64; skipping cmp"
fi

assert_summary
