#!/usr/bin/env bash
# skip_accounting_test.sh — E-236 (D-061 §4): a SKIP is not a PASS.
#
# The helpers exist because an unmet OPTIONAL requirement used to be recorded as a pass.
# That is how a suite reports all-green while testing less than it claims, and it is the
# shape behind five defects in the 2026-09-09 sprint — each an assertion that measured what
# the host happened to have rather than what the code does.
#
# The assertions here are weighted toward the accounting, not the printing: a helper that
# emits a nice "(SKIPPED)" line but still increments PASS_COUNT would look correct in a log
# and be worthless in the totals.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/tests/lib/assert.sh"

echo "── Suite: skip_accounting_test (E-236) ─────────────────────────────"

# Each probe runs a throwaway suite in a SUBSHELL so this suite's own counters are
# untouched, and reports only the SUITE_RESULT line it produced.
_probe() {  # <body> → "PASS=n FAIL=n SKIP=n"
  ( set +u
    source "$LIB"
    PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    eval "$1"
    assert_summary
  ) 2>/dev/null | grep '^SUITE_RESULT' | sed 's/^SUITE_RESULT //'
}

# ── E-236.1: the counters are three separate things ───────────────────────
assert_contains "E-236.01a: a skip increments SKIP, not PASS" "PASS=0 FAIL=0 SKIP=1" \
  "$(_probe '_skip "optional layer"')"
assert_contains "E-236.01b: a pass still increments PASS" "PASS=1 FAIL=0 SKIP=0" \
  "$(_probe '_pass "something real"')"
assert_contains "E-236.01c: a fail still increments FAIL" "PASS=0 FAIL=1 SKIP=0" \
  "$(_probe '_fail "something broken"')"
assert_contains "E-236.01d: they accumulate independently" "PASS=2 FAIL=1 SKIP=3" \
  "$(_probe '_pass a; _pass b; _fail c; _skip d; _skip e; _skip f')"

# ── E-236.2: skip_unless_cmd ──────────────────────────────────────────────
# A present command must NOT skip — otherwise the helper would silently disable whole
# layers on hosts that can actually run them, which is worse than the bug it fixes.
assert_contains "E-236.02a: a present command does not skip" "PASS=1 FAIL=0 SKIP=0" \
  "$(_probe 'if skip_unless_cmd sh "shell layer"; then _pass "ran"; fi')"
assert_contains "E-236.02b: an absent command skips and does not run the block" \
  "PASS=0 FAIL=0 SKIP=1" \
  "$(_probe 'if skip_unless_cmd definitely-not-a-real-binary-e236 "imaginary layer"; then _pass "ran"; fi')"

# ── E-236.3: skip_unless_env ──────────────────────────────────────────────
assert_contains "E-236.03a: a set variable does not skip" "PASS=1 FAIL=0 SKIP=0" \
  "$(_probe 'E236_SET=1; if skip_unless_env E236_SET "env layer"; then _pass "ran"; fi')"
assert_contains "E-236.03b: an unset variable skips" "PASS=0 FAIL=0 SKIP=1" \
  "$(_probe 'if skip_unless_env E236_DEFINITELY_UNSET "env layer"; then _pass "ran"; fi')"
# An EMPTY variable is not a satisfied requirement. Treating "" as set is how an
# environment check passes while the thing it guards is unusable.
assert_contains "E-236.03c: an EMPTY variable skips too" "PASS=0 FAIL=0 SKIP=1" \
  "$(_probe 'E236_EMPTY=""; if skip_unless_env E236_EMPTY "env layer"; then _pass "ran"; fi')"

# ── E-236.4: the summary line stays backward-compatible ───────────────────
# tests/run.sh greps PASS= and FAIL= independently, so SKIP is APPENDED. A suite that
# predates this change must still parse.
_line="$(_probe '_pass a; _skip b')"
assert_match "E-236.04a: PASS= comes first, unchanged" '^PASS=[0-9]+' "$_line"
assert_match "E-236.04b: FAIL= is still present and parseable" 'FAIL=[0-9]+' "$_line"
assert_match "E-236.04c: SKIP= is appended at the end" 'SKIP=[0-9]+$' "$_line"
assert_status 0 "E-236.04d: the runner totals skips" \
  grep -q 'TOTAL_SKIP' "${REPO_ROOT}/tests/run.sh"
assert_status 0 "E-236.04e: and reports them separately from passes" \
  grep -q 'skipped' "${REPO_ROOT}/tests/run.sh"

# ── E-236.5: file_mtime — the flake that reddened master ──────────────────
# `stat -f %m` means --file-system on GNU, so the BSD-first chain printed a filesystem
# REPORT and exited non-zero, and `$(bsd || gnu)` captured BOTH. The blob carries
# free-block counts, which change as the machine works, so two "mtimes" of an untouched
# file differed. That is what flaked mcp_doc_sync's "--check is read-only" assertion on CI
# (master run 34387218090) while it passed on macOS. Same defect as E-229's `_self_stamp`.
_f="$(mktemp)"; printf 'x' > "$_f"
_m1="$(file_mtime "$_f")"
_m2="$(file_mtime "$_f")"
assert_match "E-236.05a: file_mtime returns ONE numeric token" '^[0-9]+$' "$_m1"
assert_status 0 "E-236.05b: it is a single line" \
  bash -c "[[ \"\$(printf '%s' '$_m1' | grep -c .)\" -eq 1 ]]"
assert_status 0 "E-236.05c: and stable across calls on an untouched file" \
  bash -c "[[ '$_m1' == '$_m2' ]]"
assert_contains "E-236.05d: an unreadable path yields empty, not a partial blob" "" \
  "$(file_mtime /definitely/not/a/real/path/e236)"
rm -f "$_f"

# ── E-236.6: the standing review question is recorded where reviewers look ─
assert_status 0 "E-236.06a: critic_tests asks the environment-dependence question" \
  grep -q "Does this assertion depend on what the running machine happens to have" \
    "${REPO_ROOT}/src/claude/agents/critic_tests.md"
assert_status 0 "E-236.06b: ai-review asks it too" \
  grep -q "Does this assertion depend on what the running machine happens to have" \
    "${REPO_ROOT}/src/claude/skills/ai-review/SKILL.md"
# The question is only useful with the two remedies attached: supply the dependency when it
# is accidental, skip when it is genuinely optional. Naming one without the other is how a
# reviewer reaches for skip_unless on a test that should have supplied a scratch HOME.
assert_status 0 "E-236.06c: it names BOTH remedies, not just skipping" \
  grep -q "SUPPLY what it needs" "${REPO_ROOT}/src/claude/agents/critic_tests.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== skip_accounting_test.sh PASS ====="
else
  echo "===== skip_accounting_test.sh FAIL (${FAIL_COUNT}) ====="
fi
