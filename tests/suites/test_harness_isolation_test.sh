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

assert_summary
