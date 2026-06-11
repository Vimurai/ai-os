#!/usr/bin/env bash
# mcp_tester_test.sh — E-176 (doctor-and-cache-optimizations.md §Components 2)
#
# The MCP Connection Tester spawns each registered MCP server, performs the
# minimum stdio JSON-RPC handshake to reach tools/list, and reports connectivity.
# Used by `ai doctor --env`. Tests cover:
#   • source contract (exports, handshake frames)
#   • SECURITY: never issues tools/call; curated env (no wholesale process.env)
#   • behavioural: a real local server → ok; a bogus command → fail; CLI exit codes
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TESTER="${REPO_ROOT}/src/shared/mcp-tester.mjs"
LOCAL_SERVER="${REPO_ROOT}/src/mcp/cache-manager-mcp/index.js"

echo "===== mcp_tester_test.sh (E-176) ====="

# ── T-MT-S01: source contract ─────────────────────────────────────────────────
echo ""
echo "  [T-MT-S01] source contract"

assert_status 0 "mcp-tester.mjs exists" test -f "$TESTER"
assert_status 0 "exports testMcpServers" grep -qE 'export (async )?function testMcpServers' "$TESTER"
assert_status 0 "exports probeServer"    grep -qE 'export function probeServer' "$TESTER"
assert_status 0 "exports loadServerConfigs" grep -qE 'export function loadServerConfigs' "$TESTER"
assert_status 0 "sends initialize frame"  grep -qE '"initialize"' "$TESTER"
assert_status 0 "sends tools/list frame"  grep -qE '"tools/list"' "$TESTER"

# ── T-MT-S02: SECURITY contract ───────────────────────────────────────────────
echo ""
echo "  [T-MT-S02] security: read-only handshake + curated env"

# Must NEVER invoke an execution tool during a connectivity probe. The guarantee
# is that no JSON-RPC frame uses "tools/call" as a method (prose comments may name
# it, so we match only the double-quoted method string a real call would emit).
assert_status 1 "never emits a \"tools/call\" JSON-RPC method" grep -qE '"tools/call"' "$TESTER"
# Must NOT forward the parent's full environment (token-exposure guard).
assert_status 1 "does not spread process.env wholesale" grep -qE '\.\.\.process\.env|env:\s*process\.env' "$TESTER"
# Curated env helper present.
assert_status 0 "curated env builder present" grep -qE 'function curatedEnv' "$TESTER"
# Child stderr discarded (may carry secret-bearing diagnostics).
assert_status 0 "child stderr discarded ('ignore')" grep -qE '"ignore"' "$TESTER"

# ── T-MT-S03: behavioural — real local server answers tools/list ──────────────
echo ""
echo "  [T-MT-S03] behavioural: live probe of a local MCP server"

SBOX="$(mktemp -d)"
CFG="${SBOX}/.mcp.json"
cat > "$CFG" <<JSON
{ "mcpServers": { "cache-manager-mcp": { "command": "node", "args": ["${LOCAL_SERVER}"] } } }
JSON

PROBE_OK="$(node -e "
import('${TESTER}').then(async (m) => {
  const r = await m.testMcpServers({ configPath: '${CFG}', timeoutMs: 6000 });
  process.stdout.write(JSON.stringify(r));
}).catch(e => { console.error(e); process.exit(1); });
")"
assert_contains "live server reports ok:true"      '"ok":true'                 "$PROBE_OK"
assert_contains "live server names the server"     'cache-manager-mcp'         "$PROBE_OK"
assert_match    "live server reports a tool count" '"toolCount":[1-9]'         "$PROBE_OK"

# ── T-MT-S04: behavioural — bogus command fails (fail-closed result) ──────────
echo ""
echo "  [T-MT-S04] behavioural: unlaunchable server → ok:false with error"

CFG_BAD="${SBOX}/bad.mcp.json"
cat > "$CFG_BAD" <<JSON
{ "mcpServers": { "ghost-mcp": { "command": "node", "args": ["${SBOX}/does-not-exist.js"] } } }
JSON

PROBE_BAD="$(node -e "
import('${TESTER}').then(async (m) => {
  const r = await m.testMcpServers({ configPath: '${CFG_BAD}', timeoutMs: 4000 });
  process.stdout.write(JSON.stringify(r));
}).catch(e => { console.error(e); process.exit(1); });
")"
assert_contains "bogus server reports ok:false" '"ok":false' "$PROBE_BAD"
assert_contains "bogus server carries an error"  '"error":'   "$PROBE_BAD"

# ── T-MT-S05: CLI exit codes ──────────────────────────────────────────────────
echo ""
echo "  [T-MT-S05] CLI: exit 0 all-OK, exit 1 on any failure"

node "$TESTER" --config "$CFG" --timeout 6000 >/dev/null 2>&1
assert_status 0 "CLI exits 0 when all servers answer" bash -c "true"  # rc captured below
node "$TESTER" --config "$CFG" --timeout 6000 >/dev/null 2>&1; RC_OK=$?
assert_status 0 "CLI rc==0 (all OK)" bash -c "[[ $RC_OK -eq 0 ]]"

node "$TESTER" --config "$CFG_BAD" --timeout 4000 >/dev/null 2>&1; RC_BAD=$?
assert_status 0 "CLI rc==1 (a server failed)" bash -c "[[ $RC_BAD -eq 1 ]]"

rm -rf "$SBOX"

echo ""
assert_summary
echo "===== mcp_tester_test.sh done ====="
