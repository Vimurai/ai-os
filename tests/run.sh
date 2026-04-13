#!/usr/bin/env bash
# run.sh — AI-OS Master Test Runner (P-15 / §22)
# Usage: bash tests/run.sh [suite_pattern]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES_DIR="${SCRIPT_DIR}/suites"
PATTERN="${1:-*_test.sh}"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITE_RESULTS=()

# ── Discovery (bash 3 compatible) ────────────────────────────────────────────
SUITES=()
while IFS= read -r f; do SUITES+=("$f"); done < <(find "$SUITES_DIR" -name "$PATTERN" | sort)

if [[ ${#SUITES[@]} -eq 0 ]]; then
  echo "No test suites found matching: $PATTERN"
  exit 1
fi

echo ""
echo "━━ AI-OS Test Runner ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Suites found: ${#SUITES[@]}"
echo ""

# ── Run each suite in isolated subshell ─────────────────────────────────────
for suite in "${SUITES[@]}"; do
  suite_name="$(basename "$suite")"

  # Run suite in subshell; capture output + exit code
  suite_exit=0
  output=$(bash "$suite" 2>&1) || suite_exit=$?

  # Parse counts from machine-readable summary line emitted by assert_summary()
  summary=$(echo "$output" | grep "^SUITE_RESULT" | tail -1 || true)
  passes=$(echo "$summary" | grep -oE 'PASS=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  fails=$(echo "$summary"  | grep -oE 'FAIL=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  passes="${passes:-0}"; fails="${fails:-0}"

  # If the suite script itself crashed (non-zero exit, no SUITE_RESULT line), count it as 1 failure
  if [[ $suite_exit -ne 0 && -z "$summary" ]]; then
    fails=$(( fails + 1 ))
  fi

  TOTAL_PASS=$(( TOTAL_PASS + passes ))
  TOTAL_FAIL=$(( TOTAL_FAIL + fails ))

  if [[ $fails -eq 0 && $suite_exit -eq 0 ]]; then
    SUITE_RESULTS+=("  \033[32m✓\033[0m $suite_name ($passes passed)")
  else
    SUITE_RESULTS+=("  \033[31m✗\033[0m $suite_name ($passes passed, $fails failed)")
  fi

  # Always print suite output (suites label themselves)
  echo "$output"
  echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo "━━ Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for result in "${SUITE_RESULTS[@]}"; do
  printf "$result\n"
done
echo ""
echo "   Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "[TEST_PASSED] All tests passed ✓"
  exit 0
else
  echo "[TEST_FAILED] $TOTAL_FAIL test(s) failed ✗"
  exit 1
fi
