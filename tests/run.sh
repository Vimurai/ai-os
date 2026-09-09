#!/usr/bin/env bash
# run.sh — AI-OS Master Test Runner (P-15 / §22)
# Usage: bash tests/run.sh [suite_pattern]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES_DIR="${SCRIPT_DIR}/suites"
# E-240: --sweep removes what a run leaked (locally; on CI a leak FAILS the run instead,
# because CI has no operator to run a sweep and a green run that leaks is a lie).
AIOS_SWEEP=0
if [[ "${1:-}" == "--sweep" ]]; then AIOS_SWEEP=1; shift; fi
PATTERN="${1:-*_test.sh}"
REPO_ROOT_FOR_LEAKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ── E-240 (D-063 §2): leaked external state ─────────────────────────────────
#
# A suite that fails halfway used to leave tmux servers behind — 50 of them accumulated
# before anyone noticed, and a recycled PID then made a later run attach to one. The leak
# was found BY HAND. The runner should find the next one.
#
# THE SAFETY PROPERTY, and it is the important one: the sweep only ever touches names
# carrying the TEST PREFIX. A developer's own tmux session must survive a test run
# untouched, and a cleanup tool that can kill the operator's work is worse than the leak it
# fixes. There is a negative test for exactly this.
AIOS_TEST_SOCK_PREFIX="${AIOS_TEST_SOCK_PREFIX:-aios-test-}"
AIOS_TEST_TMP_PREFIX="${AIOS_TEST_TMP_PREFIX:-aios-t-}"
TOTAL_LEAKED=0
LEAK_REPORTS=()

# _leak_snapshot → lines of "<kind>|<id>", the external state a test run could leave.
_leak_snapshot() {
  local sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
  if [[ -d "$sockdir" ]]; then
    ls -1 "$sockdir" 2>/dev/null | grep "^${AIOS_TEST_SOCK_PREFIX}" \
      | sed 's|^|tmux-server\||' || true
  fi
  ls -1d "${TMPDIR:-/tmp}/${AIOS_TEST_TMP_PREFIX}"* 2>/dev/null \
    | sed 's|^|temp-dir\||' || true
  # Lock dirs the watcher leaves under a project's .ai/.
  find "${REPO_ROOT_FOR_LEAKS}" -maxdepth 3 -type d -name '.ai-watch.lock' 2>/dev/null \
    | sed 's|^|lock-dir\||' || true
  # Background processes whose argv names a harness sandbox.
  ps -axo pid=,command= 2>/dev/null \
    | grep -E "${AIOS_TEST_TMP_PREFIX}|${AIOS_TEST_SOCK_PREFIX}" \
    | grep -v 'grep' \
    | awk '{print "process|" $1}' || true
}

# _leak_diff <before-file> <after-file> → lines present only in "after"
_leak_diff() {
  comm -13 <(sort -u "$1") <(sort -u "$2") 2>/dev/null || true
}

# _leak_sweep <lines> — remove ONLY what carries the test prefix.
_leak_sweep() {
  local line kind id
  while IFS='|' read -r kind id; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      tmux-server)
        # Belt and braces: re-check the prefix here as well as at snapshot time, because
        # this is the branch that can destroy someone's session.
        [[ "$id" == "${AIOS_TEST_SOCK_PREFIX}"* ]] || continue
        tmux -L "$id" kill-server 2>/dev/null || true
        rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/${id}" 2>/dev/null || true ;;
      temp-dir)
        [[ "$id" == *"/${AIOS_TEST_TMP_PREFIX}"* ]] || continue
        rm -rf "$id" 2>/dev/null || true ;;
      lock-dir)
        [[ "$id" == *".ai-watch.lock" ]] || continue
        rm -rf "$id" 2>/dev/null || true ;;
      process)
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        kill -TERM "$id" 2>/dev/null || true ;;
    esac
  done <<< "$1"
}



TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITE_RESULTS=()

# Colour control — only emit ANSI escapes when stdout is an interactive TTY.
if [[ -t 1 ]]; then
  C_OK="\033[32m"; C_FAIL="\033[31m"; C_RESET="\033[0m"
else
  C_OK=""; C_FAIL=""; C_RESET=""
fi

# ── E-156 / E-157: Test harness isolation ────────────────────────────────────
# Generate an ephemeral .mcp.test.json inside a private temp dir so suites never
# read or mutate the tracked production .mcp.json, and expose it via
# MCP_CONFIG_PATH (respected by MCP loaders that opt in). A trap tears the temp
# dir down on ANY exit — success, failure, or interrupt (EXIT/INT/TERM) — so the
# git working tree is left clean.
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/aios-test.XXXXXX")"
MCP_TEST_CONFIG="${TEST_TMPDIR}/.mcp.test.json"

_aios_test_cleanup() {
  rm -rf "$TEST_TMPDIR" 2>/dev/null || true
  rm -f "${REPO_ROOT}/.mcp.test.json" 2>/dev/null || true  # belt-and-suspenders
}
trap _aios_test_cleanup EXIT INT TERM

# Base the test config on the current .mcp.json (a sandbox copy). Skip silently
# when no production config exists yet (e.g. CI before `ai mcp-setup`).
if [[ -f "${REPO_ROOT}/.mcp.json" ]]; then
  cp "${REPO_ROOT}/.mcp.json" "$MCP_TEST_CONFIG"
  export MCP_CONFIG_PATH="$MCP_TEST_CONFIG"
fi
export AIOS_TEST_TMPDIR="$TEST_TMPDIR"

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

  # E-240: snapshot the external state before and after, so a leak is attributed to the
  # SUITE that caused it rather than discovered days later by hand.
  _leak_before="$(mktemp)"; _leak_after="$(mktemp)"
  if [[ "${AI_OS_TEST_NO_SWEEP:-0}" != "1" ]]; then _leak_snapshot > "$_leak_before" 2>/dev/null; fi

  # Run suite in subshell; capture output + exit code
  suite_exit=0
  output=$(bash "$suite" 2>&1) || suite_exit=$?

  if [[ "${AI_OS_TEST_NO_SWEEP:-0}" != "1" ]]; then
    _leak_snapshot > "$_leak_after" 2>/dev/null
    _leaked="$(_leak_diff "$_leak_before" "$_leak_after")"
    if [[ -n "$_leaked" ]]; then
      _n="$(printf '%s\n' "$_leaked" | grep -c .)"
      _kinds="$(printf '%s\n' "$_leaked" | cut -d'|' -f1 | sort -u | tr '\n' ',' | sed 's/,$//')"
      echo "  LEAKED ${_n} ${_kinds}   (${suite_name})"
      LEAK_REPORTS+=("${suite_name}: ${_n} ${_kinds}")
      TOTAL_LEAKED=$(( TOTAL_LEAKED + _n ))
      if [[ "$AIOS_SWEEP" -eq 1 ]]; then
        _leak_sweep "$_leaked"
        echo "  swept ${_n} leaked item(s) from ${suite_name}"
      fi
    fi
  fi
  rm -f "$_leak_before" "$_leak_after"

  # Parse counts from machine-readable summary line emitted by assert_summary()
  summary=$(echo "$output" | grep "^SUITE_RESULT" | tail -1 || true)
  passes=$(echo "$summary" | grep -oE 'PASS=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  fails=$(echo "$summary"  | grep -oE 'FAIL=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  # E-236: SKIP is optional in the summary line, so an older suite that does not emit it
  # still parses. A skip is neither a pass nor a failure — it is a layer that did not run.
  skips=$(echo "$summary"  | grep -oE 'SKIP=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  passes="${passes:-0}"; fails="${fails:-0}"; skips="${skips:-0}"

  # If the suite script itself crashed (non-zero exit, no SUITE_RESULT line), count it as 1 failure
  if [[ $suite_exit -ne 0 && -z "$summary" ]]; then
    fails=$(( fails + 1 ))
  fi

  TOTAL_PASS=$(( TOTAL_PASS + passes ))
  TOTAL_FAIL=$(( TOTAL_FAIL + fails ))
  TOTAL_SKIP=$(( TOTAL_SKIP + skips ))

  if [[ $fails -eq 0 && $suite_exit -eq 0 ]]; then
    if [[ $skips -gt 0 ]]; then
      SUITE_RESULTS+=("  ${C_OK}✓${C_RESET} $suite_name ($passes passed, $skips skipped)")
    else
      SUITE_RESULTS+=("  ${C_OK}✓${C_RESET} $suite_name ($passes passed)")
    fi
  else
    SUITE_RESULTS+=("  ${C_FAIL}✗${C_RESET} $suite_name ($passes passed, $fails failed)")
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
# E-236: skips are reported alongside the totals, never folded into "passed". A run that
# quietly stops exercising a layer must be visible here rather than reading as all-green.
# E-240: a run that leaks is not clean, and on CI it is a failure — a green run that leaves
# state behind is how the next run gets a mysterious result nobody can reproduce.
if [[ "${TOTAL_LEAKED:-0}" -gt 0 ]]; then
  echo ""
  echo "   LEAKED external state: ${TOTAL_LEAKED} item(s)"
  for _r in "${LEAK_REPORTS[@]}"; do echo "     - ${_r}"; done
  if [[ "${CI:-}" == "true" ]]; then
    echo "   [LEAK_FAILED] a test run must leave nothing behind (E-240 / D-063 §2)"
    TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
  else
    echo "   Run 'bash tests/run.sh --sweep' to remove them (AI_OS_TEST_NO_SWEEP=1 disables this check)."
  fi
fi

if [[ "${TOTAL_SKIP:-0}" -gt 0 ]]; then
  echo "   Total: $TOTAL_PASS passed, $TOTAL_FAIL failed, $TOTAL_SKIP skipped"
else
  echo "   Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"
fi
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "[TEST_PASSED] All tests passed ✓"
  exit 0
else
  echo "[TEST_FAILED] $TOTAL_FAIL test(s) failed ✗"
  exit 1
fi
