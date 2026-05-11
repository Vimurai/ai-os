#!/usr/bin/env bash
# framework_task_routing_test.sh — Behavioural tests for E-63.
#
# Drives the real task-synchronizer-mcp via stdio JSON-RPC across the four
# control paths called out in task-routing.md:
#   1. is_framework_task=true + AIOS_WORKSPACE unset           → [WORKSPACE_NOT_FOUND]
#   2. is_framework_task=true + non-absolute AIOS_WORKSPACE    → [WORKSPACE_NOT_FOUND]
#   3. is_framework_task=true + path with no .ai/              → [WORKSPACE_NOT_FOUND]
#   4. AIOS_WORKSPACE_DISABLE=1                                → [WORKSPACE_DISABLED]
#   5. is_framework_task=true + valid AIOS_WORKSPACE           → row lands in framework state.sqlite
#   6. is_framework_task omitted/false                         → row lands in local state.sqlite
#   7. add_task tool schema advertises is_framework_task

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "===== framework_task_routing_test.sh ====="

SEED_LOCAL="$(mktemp).mjs"
cat > "$SEED_LOCAL" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const db = getDb(process.env.AIDIR);
regenerateViews(process.env.AIDIR, db);
JS

# Helper: returns the response text from one add_task call.
_call_add_task() {
  # $1 = cwd      (where the MCP resolves "local" .ai)
  # $2 = args_json
  local cwd="$1" args="$2"
  (
    cd "$cwd"
    mcp_call_tool "$SYNC_MCP" "add_task" "$args"
  ) | python3 -c "
import json, sys
raw = sys.stdin.read() or '{}'
try:
    data = json.loads(raw)
except Exception:
    print(''); sys.exit(0)
content = data.get('content') or []
print('\n'.join(c.get('text','') for c in content if c.get('type') == 'text'))
"
}

# ── T-FW-S01: tool schema advertises is_framework_task ────────────────────────
echo ""
echo "  [T-FW-S01] add_task input schema lists is_framework_task"

SCHEMA_FILE="$(mktemp)"
mcp_list_tools "$SYNC_MCP" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read() or '{}')
for t in d.get('tools', []):
    if t.get('name') == 'add_task':
        print(json.dumps(t.get('inputSchema', {})))
        break
" > "$SCHEMA_FILE"

assert_status 0 "is_framework_task is a known input property" \
  grep -q '"is_framework_task"' "$SCHEMA_FILE"
assert_status 0 "input schema describes the routing semantics" \
  grep -q 'AIOS_WORKSPACE' "$SCHEMA_FILE"
rm -f "$SCHEMA_FILE"

# Set up two sandboxed .ai/ dirs to compare local vs framework targets.
SBOX="$(mktemp -d -t fw-route-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT

mkdir -p "${SBOX}/local/.ai" "${SBOX}/framework/.ai"
AIDIR="${SBOX}/local/.ai"     REPO_ROOT="${REPO_ROOT}" node --no-warnings "$SEED_LOCAL"
AIDIR="${SBOX}/framework/.ai" REPO_ROOT="${REPO_ROOT}" node --no-warnings "$SEED_LOCAL"

# ── T-FW-S02: AIOS_WORKSPACE unset → [WORKSPACE_NOT_FOUND] ────────────────────
echo ""
echo "  [T-FW-S02] is_framework_task=true with AIOS_WORKSPACE unset → error"

unset AIOS_WORKSPACE
unset AIOS_WORKSPACE_DISABLE
RESP="$(_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"oops","tier":1,"is_framework_task":true}')"
assert_status 0 "response includes [WORKSPACE_NOT_FOUND]" \
  bash -c "echo \"$RESP\" | grep -q 'WORKSPACE_NOT_FOUND'"

# ── T-FW-S03: non-absolute path → [WORKSPACE_NOT_FOUND] ──────────────────────
echo ""
echo "  [T-FW-S03] non-absolute AIOS_WORKSPACE rejected"

export AIOS_WORKSPACE="relative/path"
RESP="$(_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"oops","tier":1,"is_framework_task":true}')"
assert_status 0 "non-absolute path rejected" \
  bash -c "echo \"$RESP\" | grep -q 'WORKSPACE_NOT_FOUND'"
assert_status 0 "error mentions absolute requirement" \
  bash -c "echo \"$RESP\" | grep -q 'absolute'"
unset AIOS_WORKSPACE

# ── T-FW-S04: path without .ai/ → [WORKSPACE_NOT_FOUND] ──────────────────────
echo ""
echo "  [T-FW-S04] AIOS_WORKSPACE without .ai/ rejected"

EMPTY_DIR="$(mktemp -d)"
export AIOS_WORKSPACE="$EMPTY_DIR"
RESP="$(_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"oops","tier":1,"is_framework_task":true}')"
assert_status 0 "missing .ai/ rejected" \
  bash -c "echo \"$RESP\" | grep -q 'WORKSPACE_NOT_FOUND'"
assert_status 0 "error mentions ai init remediation" \
  bash -c "echo \"$RESP\" | grep -q 'ai init'"
unset AIOS_WORKSPACE
rm -rf "$EMPTY_DIR"

# ── T-FW-S05: AIOS_WORKSPACE_DISABLE=1 → [WORKSPACE_DISABLED] ────────────────
echo ""
echo "  [T-FW-S05] AIOS_WORKSPACE_DISABLE=1 surfaces emergency-disable error"

export AIOS_WORKSPACE="${SBOX}/framework"
export AIOS_WORKSPACE_DISABLE="1"
RESP="$(_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"oops","tier":1,"is_framework_task":true}')"
assert_status 0 "rollback flag surfaces [WORKSPACE_DISABLED]" \
  bash -c "echo \"$RESP\" | grep -q 'WORKSPACE_DISABLED'"
unset AIOS_WORKSPACE_DISABLE

# ── T-FW-S06: valid framework workspace → row lands in framework DB ──────────
echo ""
echo "  [T-FW-S06] valid AIOS_WORKSPACE persists into framework state.sqlite"

export AIOS_WORKSPACE="${SBOX}/framework"
RESP_FILE="$(mktemp)"
_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"framework-only task","tier":2,"is_framework_task":true}' > "$RESP_FILE"
assert_status 0 "response confirms framework routing" \
  grep -q 'framework workspace' "$RESP_FILE"
rm -f "$RESP_FILE"

# Read both DBs to verify the row landed in framework only.
COUNT_FW="$(REPO_ROOT="$REPO_ROOT" AIDIR="${SBOX}/framework/.ai" node --input-type=module --no-warnings -e "
import('node:sqlite').then(({DatabaseSync}) => {
  const db = new DatabaseSync(process.env.AIDIR + '/state.sqlite');
  const r = db.prepare('SELECT COUNT(*) as n FROM tasks').get();
  console.log(r.n);
});
")"
COUNT_LOCAL="$(REPO_ROOT="$REPO_ROOT" AIDIR="${SBOX}/local/.ai" node --input-type=module --no-warnings -e "
import('node:sqlite').then(({DatabaseSync}) => {
  const db = new DatabaseSync(process.env.AIDIR + '/state.sqlite');
  const r = db.prepare('SELECT COUNT(*) as n FROM tasks').get();
  console.log(r.n);
});
")"
assert_status 0 "framework state.sqlite carries 1 row" \
  bash -c "[[ '$COUNT_FW' == '1' ]]"
assert_status 0 "local state.sqlite still empty"          \
  bash -c "[[ '$COUNT_LOCAL' == '0' ]]"

# ── T-FW-S07: is_framework_task false → row lands in local DB ────────────────
echo ""
echo "  [T-FW-S07] non-framework task lands in local state.sqlite"

unset AIOS_WORKSPACE   # prove local routing doesn't depend on the env
LOCAL_RESP_FILE="$(mktemp)"
_call_add_task "${SBOX}/local" '{"owner":"Engineer (Claude)","description":"local task","tier":1}' > "$LOCAL_RESP_FILE"
assert_status 1 "no framework-routing suffix on local task" \
  grep -q 'framework workspace' "$LOCAL_RESP_FILE"
rm -f "$LOCAL_RESP_FILE"

COUNT_LOCAL2="$(REPO_ROOT="$REPO_ROOT" AIDIR="${SBOX}/local/.ai" node --input-type=module --no-warnings -e "
import('node:sqlite').then(({DatabaseSync}) => {
  const db = new DatabaseSync(process.env.AIDIR + '/state.sqlite');
  const r = db.prepare('SELECT COUNT(*) as n FROM tasks').get();
  console.log(r.n);
});
")"
assert_status 0 "local state.sqlite gained the row" \
  bash -c "[[ '$COUNT_LOCAL2' == '1' ]]"

assert_summary
