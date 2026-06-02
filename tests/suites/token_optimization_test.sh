#!/usr/bin/env bash
# token_optimization_test.sh — E-107 (summary capper) + E-108 (stamp rotator) in
# task-synchronizer-mcp (token-optimization.md §Components 1-2).
#
# Drives the REAL MCP server over stdio against an isolated temp .ai/. Stamps are
# bulk-seeded directly into the same state.sqlite (fast) and then rotated through
# the shipped archive_done_tasks handler.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: token_optimization_test (E-107/E-108) ────────────────────"

unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE AI_OS_SUMMARY_CAP AI_OS_SOVEREIGNTY_LOCK 2>/dev/null || true
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

task_field() { TID="$2" F="$3" python3 -c 'import json,sys,os
try: d=json.load(sys.stdin)
except Exception: print("ERR"); sys.exit(0)
t=next((x for x in d.get("tasks",[]) if x.get("id")==os.environ["TID"]),None)
print("MISSING" if t is None else json.dumps(t.get(os.environ["F"])))' <<<"$1"; }

OWNER='Engineer (Claude)'

# ── E-107.01: a >200-char DONE summary is capped + [SUMMARY_TRUNCATED] emitted ─
call add_task "{\"owner\":\"${OWNER}\",\"description\":\"long summary task\",\"tier\":2}" >/dev/null
LONG="$(python3 -c 'print("X"*300)')"
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"${LONG}\"}")
assert_contains "E-107.01: [SUMMARY_TRUNCATED] warning emitted" "[SUMMARY_TRUNCATED]" "$r"
state=$(call get_state "{}")
LEN=$(printf '%s' "$(task_field "$state" E-1 summary)" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())))')
assert_status 0 "E-107.01: stored summary length <= 200" bash -c "[ \"$LEN\" -le 200 ]"
assert_contains "E-107.01: capped summary references LOG.md" "LOG.md" "$(task_field "$state" E-1 summary)"

# ── E-107.02: a short summary is stored verbatim, no truncation note ──────────
call add_task "{\"owner\":\"${OWNER}\",\"description\":\"short summary task\",\"tier\":2}" >/dev/null
r=$(call update_task_status "{\"id\":\"E-2\",\"status\":\"DONE\",\"summary\":\"all good\"}")
assert_not_contains "E-107.02: no truncation note for short summary" "[SUMMARY_TRUNCATED]" "$r"
state=$(call get_state "{}")
assert_contains "E-107.02: short summary stored verbatim" "all good" "$(task_field "$state" E-2 summary)"

# ── E-107.03: AI_OS_SUMMARY_CAP rollback raises the cap (no truncation) ───────
call add_task "{\"owner\":\"${OWNER}\",\"description\":\"rollback cap task\",\"tier\":2}" >/dev/null
export AI_OS_SUMMARY_CAP=2000
r=$(AI_OS_SUMMARY_CAP=2000 call update_task_status "{\"id\":\"E-3\",\"status\":\"DONE\",\"summary\":\"${LONG}\"}")
assert_not_contains "E-107.03: cap=2000 → no truncation of 300-char summary" "[SUMMARY_TRUNCATED]" "$r"
unset AI_OS_SUMMARY_CAP

# ── E-108: stamp rotation ────────────────────────────────────────────────────
# Bulk-seed 60 stamps into the same state.sqlite the MCP uses (fast path).
node --input-type=module -e "
import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js';
const db = getDb('${PROJECT}/.ai');
const ins = db.prepare('INSERT INTO stamps(type,agent,task_id,timestamp,summary) VALUES (?,?,?,?,?)');
for (let i = 0; i < 60; i++) ins.run('TEST_STAMP','tester',null,new Date(Date.UTC(2026,0,1,0,i)).toISOString(),'stamp '+i);
" 2>/dev/null
SEEDED=$(node --input-type=module -e "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; console.log(getDb('${PROJECT}/.ai').prepare('SELECT COUNT(*) n FROM stamps').get().n);" 2>/dev/null)
assert_status 0 "E-108.00: 60 stamps seeded" bash -c "[ \"$SEEDED\" -ge 60 ]"

r=$(call archive_done_tasks "{}")
assert_contains "E-108.01: archive run reports archived_stamps" '"archived_stamps"' "$r"
assert_contains "E-108.01b: 50 stamps archived (60 - 10 kept)" "50 stamps" "$r"
assert_exists "${PROJECT}/.ai/archive/stamps-2026-06.json"

# Active stamp count is now the 10 most recent.
REMAIN=$(node --input-type=module -e "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; console.log(getDb('${PROJECT}/.ai').prepare('SELECT COUNT(*) n FROM stamps').get().n);" 2>/dev/null)
assert_status 0 "E-108.02: 10 most-recent stamps kept in active state" bash -c "[ \"$REMAIN\" -eq 10 ]"

# Archived JSON holds the 50 rotated stamps in standard JSON (repo-oracle discoverable).
ARCHIVED_N=$(python3 -c "import json; print(len(json.load(open('${PROJECT}/.ai/archive/stamps-2026-06.json'))))")
assert_status 0 "E-108.03: archive file holds 50 stamps" bash -c "[ \"$ARCHIVED_N\" -eq 50 ]"

# ── E-108.04: a second run below threshold is a no-op ────────────────────────
r=$(call archive_done_tasks "{}")
assert_contains "E-108.04: below-threshold run is a no-op" "No archive needed" "$r"

cd "${REPO_ROOT}"
assert_summary
