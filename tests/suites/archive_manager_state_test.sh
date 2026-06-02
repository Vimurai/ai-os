#!/usr/bin/env bash
# archive_manager_state_test.sh — E-111: archive-manager execute_archive rotates
# SQLite state (DONE tasks + audit stamps) through the shared, ACID-safe owner
# instead of shelling the removed `ai archive` verb or writing the regenerated
# state.json view.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/archive-manager-mcp/index.js"
AM="${REPO_ROOT}/src/mcp/archive-manager-mcp/index.js"

echo "── Suite: archive_manager_state_test (E-111) ───────────────────────"

# ── Source contract: no removed `ai archive` shell-out, no state.json view write ─
assert_status 1 "execute_archive no longer shells 'ai archive'" \
  grep -qE 'spawnSync|aiBin|"archive"\]' "$AM"
assert_status 1 "no archiveStateDoneTasks function remains" \
  grep -qE '^function archiveStateDoneTasks' "$AM"
assert_status 0 "uses shared SQLite-aware rotation" \
  grep -qE 'archiveDoneTasks|archiveStamps' "$AM"

# ── Behavioural: execute_archive rotates stamps via SQLite ───────────────────
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai"
echo '{"version":"1.0","project":{},"tasks":[],"stamps":[],"deltas":[]}' > "${PROJECT}/.ai/state.json"
cd "${PROJECT}"

callam() { mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'; }

# Seed 60 stamps directly into the same state.sqlite.
node --input-type=module -e "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; const db=getDb('${PROJECT}/.ai'); const ins=db.prepare('INSERT INTO stamps(type,agent,task_id,timestamp,summary) VALUES (?,?,?,?,?)'); for(let i=0;i<60;i++) ins.run('T','t',null,'2026-01-01T00:00:00Z','s'+i);" 2>/dev/null

r=$(callam execute_archive "{}")
assert_contains "E-111.01: reports archived_stamps"        '"archived_stamps"' "$r"
assert_contains "E-111.01b: 50 stamps rotated (60-10)"     "50 stamps"         "$r"
assert_contains "E-111.02: points to skill: ai-archive for logs" "skill: ai-archive" "$r"
# Archive file is dated by the current month (rotation stamp), not the row timestamp.
YM="$(date -u +%Y-%m)"
assert_exists "${PROJECT}/.ai/archive/stamps-${YM}.json"

REMAIN=$(node --input-type=module -e "import { getDb } from '${REPO_ROOT}/src/mcp/shared/state-db.js'; console.log(getDb('${PROJECT}/.ai').prepare('SELECT COUNT(*) n FROM stamps').get().n);" 2>/dev/null)
assert_status 0 "E-111.03: 10 most-recent stamps kept in active SQLite state" \
  bash -c "[ \"$REMAIN\" -eq 10 ]"

# state.json was NOT hand-mutated as a view-write — it is regenerated from SQLite.
# Confirm a second run below threshold is a clean no-op.
r=$(callam execute_archive "{}")
assert_contains "E-111.04: below-threshold run reports no rotation needed" "No state rotation needed" "$r"

cd "${REPO_ROOT}"
assert_summary
