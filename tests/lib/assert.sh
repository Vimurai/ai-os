#!/usr/bin/env bash
# assert.sh — AI-OS Test Assertion Library (P-15 / §22)
# All functions print pass/fail and update global counters PASS_COUNT / FAIL_COUNT.

PASS_COUNT=0
FAIL_COUNT=0

_pass() {
  PASS_COUNT=$(( PASS_COUNT + 1 ))
  printf "  \033[32m✓\033[0m %s\n" "$1"
}

_fail() {
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  printf "  \033[31m✗\033[0m %s\n" "$1"
}

# Call at end of each suite to emit machine-readable summary line
assert_summary() {
  printf "SUITE_RESULT PASS=%d FAIL=%d\n" "$PASS_COUNT" "$FAIL_COUNT"
}

# assert_status <expected_code> <label> <command...>
assert_status() {
  local expected="$1" label="$2"; shift 2
  local actual=0
  # Use || to safely capture non-zero exit without triggering set -e
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "$label (exit=$actual)"
  else
    _fail "$label (expected exit=$expected, got $actual)"
  fi
}

# assert_contains <label> <substring> <string>
assert_contains() {
  local label="$1" sub="$2" str="$3"
  if [[ "$str" == *"$sub"* ]]; then
    _pass "$label"
  else
    _fail "$label (expected to contain: '$sub')"
  fi
}

# assert_not_contains <label> <substring> <string>
assert_not_contains() {
  local label="$1" sub="$2" str="$3"
  if [[ "$str" != *"$sub"* ]]; then
    _pass "$label"
  else
    _fail "$label (expected NOT to contain: '$sub')"
  fi
}

# assert_exists <path>
assert_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    _pass "exists: $path"
  else
    _fail "missing: $path"
  fi
}

# assert_match <label> <regex> <string>
assert_match() {
  local label="$1" regex="$2" str="$3"
  if echo "$str" | grep -qE "$regex"; then
    _pass "$label"
  else
    _fail "$label (expected to match regex: '$regex')"
  fi
}
