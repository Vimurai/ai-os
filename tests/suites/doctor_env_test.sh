#!/usr/bin/env bash
# doctor_env_test.sh — E-175 (doctor-and-cache-optimizations.md §Components 1)
#
# `ai doctor --env` performs deep environment + connectivity diagnostics:
# Node 22+, essential binaries, Docker, read/write bits on ~/.ai-os & .ai, and a
# live MCP connectivity probe (E-176 mcp-tester). Exits 1 on critical failure.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

AI_BIN="${REPO_ROOT}/src/bin/ai"
LOCAL_SERVER="${REPO_ROOT}/src/mcp/cache-manager-mcp/index.js"

echo "===== doctor_env_test.sh (E-175) ====="

# ── T-ENV-S01: source contract ────────────────────────────────────────────────
echo ""
echo "  [T-ENV-S01] source contract"

assert_status 0 "ai bin exists" test -f "$AI_BIN"
assert_status 0 "syntax valid"  bash -n "$AI_BIN"
assert_status 0 "_run_env_diagnostics defined" grep -qE '_run_env_diagnostics\(\)' "$AI_BIN"
assert_status 0 "--env flag parsed"            grep -qE '"--env"' "$AI_BIN"
assert_status 0 "doctor dispatches to env diagnostics" \
  grep -qE 'ENVCHECK.*-eq 1|_run_env_diagnostics' "$AI_BIN"
assert_status 0 "checks Node 22+ requirement" grep -qE '\-ge 22' "$AI_BIN"
assert_status 0 "checks read/write bits"       grep -q 'read/write access' "$AI_BIN"
assert_status 0 "checks state db write access" grep -q 'state database write access' "$AI_BIN"
assert_status 0 "invokes mcp-tester (E-176)"  grep -qE 'mcp-tester\.mjs' "$AI_BIN"
assert_status 0 "returns non-zero on critical failure" grep -qE 'return 1' "$AI_BIN"

# ── T-ENV-S02: behavioural — healthy env passes ───────────────────────────────
echo ""
echo "  [T-ENV-S02] behavioural: deep check in a healthy sandbox project"

SBOX="$(mktemp -d)"
mkdir -p "${SBOX}/.ai"
cat > "${SBOX}/.mcp.json" <<JSON
{ "mcpServers": { "cache-manager-mcp": { "command": "node", "args": ["${LOCAL_SERVER}"] } } }
JSON

OUT="$( cd "${SBOX}" && "$AI_BIN" doctor --env 2>&1 )"
RC=$?

assert_contains "prints --env header"          "deep environment & connectivity" "$OUT"
assert_contains "node version check is [OK]"    "[OK]   node version"             "$OUT"
assert_contains "reports ~/.ai-os access"       ".ai-os read/write access"       "$OUT"
assert_contains "runs MCP connectivity probe"   "MCP connectivity"               "$OUT"
assert_contains "local server answered tools/list" "cache-manager-mcp"           "$OUT"
assert_contains "summary line present"          "Environment OK"                 "$OUT"
assert_status 0 "exit 0 when all critical checks pass" bash -c "[[ $RC -eq 0 ]]"

# ── T-ENV-S03: behavioural — a dead MCP server makes --env exit 1 ─────────────
echo ""
echo "  [T-ENV-S03] behavioural: unreachable MCP server → critical fail (exit 1)"

cat > "${SBOX}/.mcp.json" <<JSON
{ "mcpServers": { "ghost-mcp": { "command": "node", "args": ["${SBOX}/nope.js"] } } }
JSON

OUT_BAD="$( cd "${SBOX}" && "$AI_BIN" doctor --env 2>&1 )"
RC_BAD=$?
assert_contains "flags the failed server"  "[FAIL] ghost-mcp"        "$OUT_BAD"
assert_contains "reports critical failure" "critical failures"       "$OUT_BAD"
assert_status 0 "exit 1 on critical failure" bash -c "[[ $RC_BAD -eq 1 ]]"

rm -rf "$SBOX"

echo ""
assert_summary
echo "===== doctor_env_test.sh done ====="
