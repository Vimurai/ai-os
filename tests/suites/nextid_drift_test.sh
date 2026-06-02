#!/usr/bin/env bash
# nextid_drift_test.sh — E-109 (drift-resolution-2026.md): nextId must never
# re-issue an id that lives in .ai/archive/state-done-*.json or that was already
# allocated (the state-json-db-mismatch incident). The next number is
# max(live, archived, persisted-high-water) + 1.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: nextid_drift_test (E-109) ────────────────────────────────"

unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai"
cat > "${PROJECT}/.ai/state.json" <<'JSON'
{ "version": "1.0", "project": {}, "tasks": [], "stamps": [], "deltas": [] }
JSON
cd "${PROJECT}"

call() { mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'; }

OWNER='Engineer (Claude)'
DBN="node --input-type=module -e"

# ── A: fresh DB preserves the E-1, E-2 sequence (backward compat) ────────────
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"first\",\"tier\":2}")
assert_contains "A: fresh → E-1" "Added E-1" "$r"
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"second\",\"tier\":2}")
assert_contains "A: next → E-2" "Added E-2" "$r"

# ── B: archived ids bound the sequence (no collision with retired ids) ───────
# Seed an archive file holding E-1..E-50 (max 50), as _archiveDoneTasks would.
mkdir -p "${PROJECT}/.ai/archive"
python3 -c "import json; json.dump([{'id':f'E-{i}','status':'DONE'} for i in range(1,51)], open('${PROJECT}/.ai/archive/state-done-2026-01.json','w'))"
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"after archive\",\"tier\":2}")
assert_contains "B: archived E-50 bounds the sequence → E-51" "Added E-51" "$r"

# ── C: high-water prevents re-issue even after a row leaves the live table ───
# Delete E-51 directly from the live table; the persisted high-water must still
# advance the sequence past it.
$DBN "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; getDb('${PROJECT}/.ai').prepare('DELETE FROM tasks WHERE id = ?').run('E-51');" 2>/dev/null
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"after delete\",\"tier\":2}")
assert_contains "C: deleted E-51 not re-issued → E-52" "Added E-52" "$r"
assert_not_contains "C: E-51 not re-issued" "Added E-51" "$r"

# ── D: the per-prefix high-water mark is persisted in the project table ──────
HW=$($DBN "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; const r=getDb('${PROJECT}/.ai').prepare('SELECT value FROM project WHERE key = ?').get('last_id_E'); console.log(r ? r.value : 'NONE');" 2>/dev/null)
assert_status 0 "D: high-water last_id_E persisted at 52" bash -c "[ \"$HW\" = '52' ]"

# ── E: an unrelated prefix (P-) is independent ───────────────────────────────
r=$(call add_task "{\"owner\":\"Architect (Gemini)\",\"description\":\"p task\",\"prefix\":\"P\",\"tier\":2}")
assert_contains "E: P- prefix independent → P-1" "Added P-1" "$r"

cd "${REPO_ROOT}"
assert_summary
