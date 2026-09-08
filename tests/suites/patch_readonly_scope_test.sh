#!/usr/bin/env bash
# patch_readonly_scope_test.sh — E-226 (D-058 §4): T-PROPOSEPATCH-002.
#
# E-221 bound the WRITE path to the proposing project. The three read-only tools were
# explicitly out of that ruling's scope, so they kept trusting the stored ABSOLUTE path:
#   preview_patch  called formatDiff(diff, patch.path), which STATS AND READS that path to
#                  build a diff baseline — a file outside the previewing project rendered
#                  its contents into tool output.
#   reject_patch   deleted rows from any project reachable in the store.
#   list_pending   printed absolute paths from other projects.
#
# Non-vacuity, all three against the PRE-FIX server:
#   foreign-preview  → LEAKED           (canary file contents in the output)
#   foreign-reject   → ABS_PATH_LEAKED, row-deleted   (another project's queue)
#   foreign-list-all → ABS_PATH_LEAKED
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIVER="${REPO_ROOT}/tests/lib/propose-patch-driver.mjs"
SERVER="${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"

echo "── Suite: patch_readonly_scope_test (E-226) ─────────────────────────"

_drive() { node --no-warnings "$DRIVER" "$1" 2>/dev/null | tail -1; }

# ── E-226.1: the legitimate case still works ───────────────────────────────
# First, because everything below is a refusal and refusals are easy to get right by
# refusing everything.
_r="$(_drive own-preview)"
assert_contains "E-226.01a: an own-project preview still renders" "previewed" "$_r"
assert_not_contains "E-226.01b: it is not misreported as foreign" "wrongly-foreign" "$_r"
assert_contains "E-226.01c: preview writes nothing" "original" "$_r"

# ── E-226.2: a foreign preview reads NO file ───────────────────────────────
# The disclosure itself. The stored diff is still shown — an operator can see what was
# proposed — but no baseline is read, so nothing outside this project can be rendered.
_r="$(_drive foreign-preview)"
assert_not_contains "E-226.02a: the canary's contents never reach the output" "LEAKED" "$_r"
assert_contains "E-226.02b: it is labelled [FOREIGN_PROJECT]" "FOREIGN_BANNER" "$_r"
assert_not_contains "E-226.02c: no absolute path from the other project leaks" "ABS_PATH_LEAKED" "$_r"

# ── E-226.3: a foreign reject is refused, and the row survives ─────────────
# Rejecting is a WRITE to someone else's queue: it destroys a patch its owner is waiting
# to confirm. Pre-fix this deleted the row.
_r="$(_drive foreign-reject)"
assert_contains "E-226.03a: a cross-project reject returns PROJECT_MISMATCH" "PROJECT_MISMATCH" "$_r"
assert_contains "E-226.03b: the other project's row is still there" "row-kept" "$_r"

# ── E-226.4: list is own-project by default, identifiers-only with all:true ─
_r="$(_drive foreign-list)"
assert_not_contains "E-226.04a: the default listing leaks no absolute path" "ABS_PATH_LEAKED" "$_r"
_r="$(_drive foreign-list-all)"
assert_contains "E-226.04b: all:true lists foreign rows safely" "listed-safely" "$_r"
assert_not_contains "E-226.04c: even then, no absolute path" "ABS_PATH_LEAKED" "$_r"
assert_status 0 "E-226.04d: foreign rows are shown by root BASENAME only" \
  bash -c "grep -q 'function rootLabel' '$SERVER'"

# ── E-226.5: the three tools share one derivation ──────────────────────────
# Three copies of "does this row belong here" would drift, and the weakest would decide.
assert_status 0 "E-226.05a: a single rowScope classifier exists" \
  bash -c "grep -q 'function rowScope' '$SERVER'"
assert_status 0 "E-226.05b: all three read-only tools use it" \
  bash -c "test \$(grep -c 'rowScope(' '$SERVER') -ge 4"
# The stored absolute path survives in exactly ONE place — the AI_OS_PATCH_LEGACY
# rollback branch — and nowhere on the default path. Asserting the string is absent
# entirely would have been wrong (the rollback needs it), and asserting only that it
# exists would be vacuous; this pins WHERE it may appear.
# Comment lines are stripped first: the module header QUOTES this call as the thing that
# leaked, and counting that occurrence made the assertion fail on correct code.
assert_status 0 "E-226.05c: the stored absolute path is used once, under the rollback flag" \
  bash -c "test \$(grep -v '^\s*\*' '$SERVER' | grep -c 'formatDiff(patch.diff_content, patch.path)') -eq 1"
assert_status 0 "E-226.05d: that one use sits inside the AI_OS_PATCH_LEGACY branch" \
  bash -c "python3 - '$SERVER' <<'PYX'
import sys
# Comment lines stripped first: the module header QUOTES the call as the thing that
# leaked, and index() found THAT occurrence — so the assertion failed on correct code.
src = [l for l in open(sys.argv[1]).read().split('\n') if not l.lstrip().startswith(('*', '//', '/*'))]
s = '\n'.join(src)
i = s.index('formatDiff(patch.diff_content, patch.path)')
sys.exit(0 if 'AI_OS_PATCH_LEGACY' in s[max(0, i-400):i] else 1)
PYX"

# ── E-226.6: legacy rows are listed but never read ─────────────────────────
_r="$(_drive legacy)"
assert_contains "E-226.06a: a legacy row is still refused at confirm" "LEGACY_PATCH" "$_r"
assert_status 0 "E-226.06b: legacy rows are classified separately from foreign ones" \
  bash -c "grep -q 'return \"legacy\"' '$SERVER'"

# ── E-226.7: the rollback flag restores the old behaviour ──────────────────
assert_status 0 "E-226.07a: AI_OS_PATCH_LEGACY is honoured by all three tools" \
  bash -c "test \$(grep -c 'AI_OS_PATCH_LEGACY' '$SERVER') -ge 4"

# ── E-226.8: the tool descriptions tell the model what to expect ───────────
# The description is what the model reads before calling; a silent behaviour change here
# is a behaviour change nobody sees.
assert_status 0 "E-226.08a: list documents the all:true shape" \
  bash -c "grep -q 'Pass all:true' '$SERVER'"
assert_status 0 "E-226.08b: preview documents the foreign case" \
  bash -c "grep -q 'FOREIGN_PROJECT. banner' '$SERVER'"

assert_summary
