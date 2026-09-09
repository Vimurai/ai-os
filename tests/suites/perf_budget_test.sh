#!/usr/bin/env bash
# perf_budget_test.sh — E-239 (D-062 §2): a perf budget must measure the CODE, not the host.
#
# `incident_aggregator` asserted "under 200ms" and measured 381ms on a developer laptop
# while passing on CI (20/20). `node -e ''` alone cost ~197ms there, so the budget was
# arithmetically unreachable. The same assertion later PASSED on that same laptop once 54
# leaked tmux servers and a wedged download were cleared — it had been tracking machine
# load the whole time, and no code had changed.
#
# The two properties that matter pull against each other, so both are pinned here:
#   * a REAL regression must still fail, or the rule has just deleted the assertion;
#   * the SAME code on a slow host must pass, or the rule has changed nothing.
# A helper that only satisfied one of those would look reasonable and be useless.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: perf_budget_test (E-239) ─────────────────────────────────"

# Run assert_perf in a subshell so its own pass/fail never touches this suite's counters,
# and report only the verdict it produced.
_verdict() {  # <env-assignments> <elapsed> <absolute> <baseline> [k] [slack] → PASS|FAIL
  local env_pre="$1"; shift
  ( set +u
    source "${REPO_ROOT}/tests/lib/assert.sh"
    PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    eval "$env_pre"
    assert_perf "probe" "$@" >/dev/null 2>&1
    [[ "$FAIL_COUNT" -eq 0 ]] && echo PASS || echo FAIL )
}

# ── E-239.1: relative mode — the rule's whole purpose ─────────────────────
# 381ms elapsed against a 200ms absolute, on a host whose baseline is 197ms. This is the
# exact incident: it must PASS, because the machine, not the code, is slow.
assert_contains "E-239.01a: the real incident (381ms, baseline 197ms) now PASSES locally" \
  "PASS" "$(_verdict 'CI=' 381 200 197)"
# NON-VACUITY: the same elapsed on a FAST host is a genuine regression and must FAIL.
assert_contains "E-239.01b: 381ms on a fast host (baseline 35ms) still FAILS" \
  "FAIL" "$(_verdict 'CI=' 381 200 35)"
assert_contains "E-239.01c: a 5x-baseline regression FAILS" \
  "FAIL" "$(_verdict 'CI=' 500 200 35)"
assert_contains "E-239.01d: at exactly the limit it PASSES (k*b+slack, inclusive)" \
  "PASS" "$(_verdict 'CI=' 120 200 35)"
assert_contains "E-239.01e: one ms over the limit FAILS" \
  "FAIL" "$(_verdict 'CI=' 121 200 35)"

# ── E-239.2: CI enforces the ABSOLUTE budget ─────────────────────────────
# On known hardware a real regression must not hide behind a generous ratio.
assert_contains "E-239.02a: on CI the absolute governs — 381ms FAILS" \
  "FAIL" "$(_verdict 'CI=true' 381 200 197)"
assert_contains "E-239.02b: on CI, inside the absolute, PASSES" \
  "PASS" "$(_verdict 'CI=true' 150 200 197)"
# The ratio must NOT rescue a CI regression: baseline 197 would give a 444ms relative
# limit, and 381ms would sail through if the mode were chosen wrongly.
assert_contains "E-239.02c: on CI the ratio does not rescue a regression" \
  "FAIL" "$(_verdict 'CI=true' 381 200 197)"

# ── E-239.3: the override ────────────────────────────────────────────────
assert_contains "E-239.03a: AI_OS_PERF_ABSOLUTE=1 forces absolute off CI" \
  "FAIL" "$(_verdict 'CI=; AI_OS_PERF_ABSOLUTE=1' 381 200 197)"
assert_contains "E-239.03b: and it is honoured for a passing case too" \
  "PASS" "$(_verdict 'CI=; AI_OS_PERF_ABSOLUTE=1' 150 200 197)"

# ── E-239.4: k and slack are declarable per assertion ────────────────────
assert_contains "E-239.04a: a tighter k=1 rejects what k=2 allowed" \
  "FAIL" "$(_verdict 'CI=' 120 200 35 1 10)"
assert_contains "E-239.04b: a looser k=4 accepts it" \
  "PASS" "$(_verdict 'CI=' 120 200 35 4 10)"

# ── E-239.5: BOTH numbers are printed, every run ─────────────────────────
# A perf assertion that prints only a verdict cannot distinguish "the code got slower" from
# "the machine is busy" — which is the entire question this task exists to answer.
_out="$( ( source "${REPO_ROOT}/tests/lib/assert.sh"; PASS_COUNT=0; FAIL_COUNT=0
           CI= assert_perf "printed" 59 200 35 ) 2>&1 )"
assert_contains "E-239.05a: elapsed is printed"   "elapsed=59ms"   "$_out"
assert_contains "E-239.05b: baseline is printed"  "baseline=35ms"  "$_out"
assert_contains "E-239.05c: the limit is printed" "limit=120ms"    "$_out"
assert_contains "E-239.05d: the mode is named"    "[relative]"     "$_out"
assert_contains "E-239.05e: the absolute is shown even in relative mode" "absolute=200ms" "$_out"
# On a FAILING run the numbers must still be there — that is when they are needed most.
_outf="$( ( source "${REPO_ROOT}/tests/lib/assert.sh"; PASS_COUNT=0; FAIL_COUNT=0
            CI= assert_perf "printed" 500 200 35 ) 2>&1 )"
assert_contains "E-239.05f: a FAILING assertion prints the baseline too" "baseline 35ms" "$_outf"

# ── E-239.6: baselines are real, cached, and median-based ────────────────
_b1="$(perf_baseline_node)"
_b2="$(perf_baseline_node)"
assert_match "E-239.06a: the node baseline is a number" '^[0-9]+$' "$_b1"
assert_status 0 "E-239.06b: it is cached (identical within a run)" \
  bash -c "[[ '$_b1' == '$_b2' ]]"
assert_status 0 "E-239.06c: and plausible (>0ms — a spawn is never free)" \
  bash -c "[[ '$_b1' -gt 0 ]]"
_h="$(perf_baseline_hook)"
assert_match "E-239.06d: the hook baseline is a number" '^[0-9]+$' "$_h"
# MEDIAN, not mean: one scheduling hiccup must not inflate the baseline and thereby hide a
# real regression behind a generous limit.
assert_status 0 "E-239.06e: the baseline is a MEDIAN, not a mean" \
  grep -q 'runs\[len(runs) // 2\]' "${REPO_ROOT}/tests/lib/assert.sh"

# ── E-239.7: the converted assertions, and the checklist ─────────────────
assert_status 0 "E-239.07a: incident_aggregator uses assert_perf" \
  grep -q 'assert_perf "aggregator on a 100-record log"' "${REPO_ROOT}/tests/suites/incident_aggregator_test.sh"
assert_status 1 "E-239.07b: and no longer hard-codes a bare 200ms compare" \
  grep -q "ELAPSED_MS' -lt 200" "${REPO_ROOT}/tests/suites/incident_aggregator_test.sh"
assert_status 0 "E-239.07c: telemetry uses assert_perf" \
  grep -q 'assert_perf "hook warm-path' "${REPO_ROOT}/tests/suites/telemetry_test.sh"
# Its baseline matches its own instrument (2 node spawns + a hook), not a bare hook —
# comparing against a bare-hook baseline would flatter the assertion by ignoring the clock
# it uses to measure itself.
assert_status 0 "E-239.07d: telemetry's baseline includes its own measurement overhead" \
  grep -q '2 \* \$(perf_baseline_node) + \$(perf_baseline_hook)' "${REPO_ROOT}/tests/suites/telemetry_test.sh"
assert_status 0 "E-239.07e: critic_tests flags an absolute budget with no baseline" \
  grep -q 'Absolute performance budgets without a baseline' "${REPO_ROOT}/src/claude/agents/critic_tests.md"
assert_status 0 "E-239.07f: the generated plugin artifact was rebuilt (E-236 lesson)" \
  bash -c "grep -q 'Absolute performance budgets' '${REPO_ROOT}/src/agents/plugin/agents/critic_tests/agent.json'"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== perf_budget_test.sh PASS ====="
else
  echo "===== perf_budget_test.sh FAIL (${FAIL_COUNT}) ====="
fi
