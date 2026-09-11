#!/usr/bin/env bash
# test_harness_isolation_test.sh — E-156 / E-157 (test-harness-isolation.md)
# Verifies tests/run.sh isolates MCP config into an ephemeral .mcp.test.json,
# exports MCP_CONFIG_PATH, and tears artifacts down via a trap on any exit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUN_SH="${REPO_ROOT}/tests/run.sh"

echo "── Suite: test_harness_isolation ────────────────────────────────────"

run_sh_body="$(cat "$RUN_SH")"

# ── E-157: cleanup trap registered for EXIT, INT, and TERM ────────────────────
assert_contains "run.sh registers cleanup trap on EXIT/INT/TERM" \
  'trap _aios_test_cleanup EXIT INT TERM' "$run_sh_body"
assert_contains "run.sh defines the cleanup function" \
  '_aios_test_cleanup() {' "$run_sh_body"

# ── E-156: generates .mcp.test.json and exports MCP_CONFIG_PATH ───────────────
assert_contains "run.sh names the ephemeral config .mcp.test.json" \
  '/.mcp.test.json' "$run_sh_body"
assert_contains "run.sh exports MCP_CONFIG_PATH" \
  'export MCP_CONFIG_PATH=' "$run_sh_body"
assert_contains "run.sh bases the test config on production .mcp.json" \
  'cp "${REPO_ROOT}/.mcp.json" "$MCP_TEST_CONFIG"' "$run_sh_body"

# ── .gitignore safety net covers the ephemeral config ─────────────────────────
assert_status 0 ".mcp.test.json is git-ignored" \
  git -C "$REPO_ROOT" check-ignore .mcp.test.json

# ── Functional: a no-match run leaves the working tree clean ──────────────────
# Spawn run.sh with a pattern matching no suite — it exits 1 at discovery, AFTER
# the isolation setup + trap have run. Its temp dir is unique (mktemp), so this
# never collides with the outer runner's config.
_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }

mcp_before=""
[[ -f "${REPO_ROOT}/.mcp.json" ]] && mcp_before="$(_md5 "${REPO_ROOT}/.mcp.json")"

bash "$RUN_SH" '__aios_iso_nomatch__' >/dev/null 2>&1 || true

if [[ ! -e "${REPO_ROOT}/.mcp.test.json" ]]; then
  _pass "no .mcp.test.json left at repo root after run (trap cleaned up)"
else
  _fail "stale .mcp.test.json left at repo root after run"
fi

if [[ -n "$mcp_before" ]]; then
  mcp_after="$(_md5 "${REPO_ROOT}/.mcp.json")"
  assert_contains "production .mcp.json untouched by a test run" "$mcp_before" "$mcp_after"
fi

# ── E-251 (D-067 §5): corpus_or_fail — variety #5, "the scan that never ran" ──
#
# Three rule-scanning suites built their corpus with `find src .claude .agents .gemini`.
# E-244 stopped provisioning two of those roots, `find` exited non-zero, and the corpus came
# back EMPTY — so all three reported "no violations" about nothing, and would have gone on
# doing so. The helper makes the CORPUS STEP fail rather than the assertion that reads it.
#
# Everything below drives the real helper against fixtures, because the property under test
# is exactly the one that is easy to assert vacuously. NOTE: this suite runs under `set -e`,
# so every DELIBERATELY failing call captures its status with `|| _c_rc=$?` — a bare
# `x="$(failing)"` would abort the file at the assignment and the remaining assertions would
# simply not run, which is its own flavour of the scan that never ran.
_corpus_root="$(test_tmpdir e251)"
mkdir -p "${_corpus_root}/a" "${_corpus_root}/b"
for _i in 1 2 3 4 5; do
  printf 'x\n' > "${_corpus_root}/a/f${_i}.md"
  printf 'x\n' > "${_corpus_root}/b/g${_i}.txt"
done

# The happy path returns the list on stdout and 0.
_c_rc=0; _c_out="$( cd "$_corpus_root" && corpus_or_fail 5 a b 2>/dev/null )" || _c_rc=$?
assert_contains "E-251.01a: a healthy corpus returns 0" "0" "$_c_rc"
assert_contains "E-251.01b: and prints one path per file" "10" "$(printf '%s\n' "$_c_out" | grep -c .)"

# THE DEFECT, asserted directly: a missing root is a FAILURE, not a root to filter out.
_c_rc=0; _c_err="$( cd "$_corpus_root" && corpus_or_fail 1 a missing-root 2>&1 >/dev/null )" || _c_rc=$?
assert_contains "E-251.02a: a MISSING root fails the corpus (rc 1)" "1" "$_c_rc"
assert_contains "E-251.02b: and names the root that was missing" "missing-root" "$_c_err"
assert_contains "E-251.02c: and says the scan would have been empty" "empty" "$_c_err"

# Below the floor is the same defect arriving quietly — a corpus that shrank rather than
# vanished. E-244's suites had counts in the hundreds; a handful of files is not a scan.
_c_rc=0; _c_err="$( cd "$_corpus_root" && corpus_or_fail 100 a 2>&1 >/dev/null )" || _c_rc=$?
assert_contains "E-251.03a: a corpus below the minimum fails (rc 1)" "1" "$_c_rc"
assert_contains "E-251.03b: and reports the count it actually found" "5 file(s)" "$_c_err"

# The count is printed on EVERY run, pass or fail — a scan whose size is never shown is one
# nobody notices shrinking.
_c_err="$( cd "$_corpus_root" && corpus_or_fail 1 a 2>&1 >/dev/null )" || true
assert_contains "E-251.04a: the count is printed on the happy path too" "CORPUS 5 file(s)" "$_c_err"

# A predicate after `--` is wrapped in \( \), so an -o alternation binds to the predicate
# and does not swallow the roots.
_c_out="$( cd "$_corpus_root" && corpus_or_fail 1 a b -- -name "*.md" -o -name "*.txt" 2>/dev/null )" || true
assert_contains "E-251.05a: an -o predicate binds inside the parens" "10" "$(printf '%s\n' "$_c_out" | grep -c .)"
_c_out="$( cd "$_corpus_root" && corpus_or_fail 1 a b -- -name "*.md" 2>/dev/null )" || true
assert_contains "E-251.05b: and a narrowing predicate really narrows" "5" "$(printf '%s\n' "$_c_out" | grep -c .)"

# DATA OR STATE, NEVER BOTH (review question #4). The helper is called in a command
# substitution, so it must not touch the counters — a FAIL recorded inside that subshell
# would evaporate, and the suite would report a pass it never earned.
_pass_before="$PASS_COUNT"; _fail_before="$FAIL_COUNT"
_ignored="$( cd "$_corpus_root" && corpus_or_fail 999 a 2>/dev/null )" || true
assert_contains "E-251.06a: a failing corpus_or_fail does not mutate PASS_COUNT" \
  "$_pass_before" "$PASS_COUNT"
assert_contains "E-251.06b: nor FAIL_COUNT — the caller owns the assertion" \
  "$_fail_before" "$FAIL_COUNT"

# The three converted suites really use it, rather than keeping a private find.
for _s in skill_consent_test program_position_test operand_retokenise_test; do
  assert_status 0 "E-251.07: ${_s} builds its corpus with corpus_or_fail" \
    grep -q 'corpus_or_fail ' "${SCRIPT_DIR}/${_s}.sh"
  assert_status 1 "E-251.07: ${_s} no longer filters roots for existence" \
    grep -q 'filter((d) => existsSync' "${SCRIPT_DIR}/${_s}.sh"
done

assert_summary
