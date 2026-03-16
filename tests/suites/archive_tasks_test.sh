#!/usr/bin/env bash
# archive_tasks_test.sh — Tests for archive_done_tasks tool (E-112)
# Validates: threshold logic, archive file creation, live state pruning,
# OPEN task preservation, and archive JSON integrity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
TEMPLATE="${REPO_ROOT}/src/templates/state.json"

echo "── Suite: archive_tasks_test ───────────────────────────────────────"

DONE_THRESHOLD=50
DONE_KEEP=10
YM=$(date '+%Y-%m')

# Helper: inline archiveDoneTasks logic (mirrors task-synchronizer-mcp)
run_archive() {
  local AI_DIR="$1"
  node -e "
    import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
    import { resolve } from 'path';
    const aiDir = process.argv[1];
    const THRESHOLD = 50;
    const KEEP = 10;
    const statePath = resolve(aiDir, 'state.json');
    const state = JSON.parse(readFileSync(statePath, 'utf8'));
    const done = state.tasks.filter(t => t.status === 'DONE');
    if (done.length <= THRESHOLD) { console.log('null'); process.exit(0); }
    const toArchive = done.slice(0, done.length - KEEP);
    const toKeep    = done.slice(done.length - KEEP);
    const open      = state.tasks.filter(t => t.status !== 'DONE');
    const ym = new Date().toISOString().slice(0, 7);
    const archiveDir = resolve(aiDir, 'archive');
    mkdirSync(archiveDir, { recursive: true });
    const archivePath = resolve(archiveDir, 'state-done-' + ym + '.json');
    let existing = [];
    if (existsSync(archivePath)) {
      try { existing = JSON.parse(readFileSync(archivePath, 'utf8')); } catch {}
    }
    writeFileSync(archivePath, JSON.stringify([...existing, ...toArchive], null, 2) + '\n', 'utf8');
    state.tasks = [...open, ...toKeep];
    writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n', 'utf8');
    console.log(JSON.stringify({ archived: toArchive.length, kept: toKeep.length, archivePath }));
  " "$AI_DIR" --input-type=module 2>/dev/null || echo "node_error"
}

# T-06.01: No archive when DONE count == threshold (50) — boundary value
BELOW_DIR=$(mktemp -d)
cp "$TEMPLATE" "${BELOW_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${BELOW_DIR}/state.json'))
s['tasks']=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'DONE','tier':1,'description':'Task '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Done'} for i in range(1,51)]
json.dump(s, open('${BELOW_DIR}/state.json','w'), indent=2)
"
result=$(run_archive "$BELOW_DIR")
assert_contains "T-06.01: no archive when DONE count == 50 (at threshold)" "null" "$result"
rm -rf "$BELOW_DIR"

# T-06.02: Archive triggered when DONE count > threshold (55 DONE tasks)
ABOVE_DIR=$(mktemp -d)
cp "$TEMPLATE" "${ABOVE_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${ABOVE_DIR}/state.json'))
s['tasks']=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'DONE','tier':1,'description':'Task '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Done'} for i in range(1,56)]
json.dump(s, open('${ABOVE_DIR}/state.json','w'), indent=2)
"
result=$(run_archive "$ABOVE_DIR")
assert_contains "T-06.02: archive result contains archived key" '"archived"' "$result"
assert_exists "${ABOVE_DIR}/archive/state-done-${YM}.json"

# T-06.03: Live state retains exactly DONE_KEEP (10) DONE tasks after archive
live_done=$(python3 -c "
import json; s=json.load(open('${ABOVE_DIR}/state.json'))
print(len([t for t in s['tasks'] if t['status']=='DONE']))
")
assert_contains "T-06.03: live state retains exactly 10 DONE tasks" "10" "$live_done"

# T-06.04: Archived count is correct (55 - 10 = 45)
archived_count=$(python3 -c "
import json
d=json.load(open('${ABOVE_DIR}/archive/state-done-${YM}.json'))
print(len(d))
")
assert_contains "T-06.04: archive file contains 45 tasks (55 - 10 kept)" "45" "$archived_count"
rm -rf "$ABOVE_DIR"

# T-06.05: OPEN tasks are preserved after archive (not touched)
MIXED_DIR=$(mktemp -d)
cp "$TEMPLATE" "${MIXED_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${MIXED_DIR}/state.json'))
done=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'DONE','tier':1,'description':'Done '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Complete'} for i in range(1,52)]
open_=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'OPEN','tier':1,'description':'Open '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':None,'summary':None} for i in range(52,57)]
s['tasks']=done+open_
json.dump(s, open('${MIXED_DIR}/state.json','w'), indent=2)
"
run_archive "$MIXED_DIR" >/dev/null
open_count=$(python3 -c "
import json; s=json.load(open('${MIXED_DIR}/state.json'))
print(len([t for t in s['tasks'] if t['status']=='OPEN']))
")
assert_contains "T-06.05: all 5 OPEN tasks preserved after archive" "5" "$open_count"
rm -rf "$MIXED_DIR"

# T-06.06: Archive file is valid JSON array
VALID_DIR=$(mktemp -d)
cp "$TEMPLATE" "${VALID_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${VALID_DIR}/state.json'))
s['tasks']=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'DONE','tier':1,'description':'Task '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Done'} for i in range(1,56)]
json.dump(s, open('${VALID_DIR}/state.json','w'), indent=2)
"
run_archive "$VALID_DIR" >/dev/null
archive_valid=$(python3 -c "
import json
try:
    d=json.load(open('${VALID_DIR}/archive/state-done-${YM}.json'))
    print('ok' if isinstance(d,list) else 'not_array')
except Exception as e:
    print('corrupt:'+str(e))
")
assert_contains "T-06.06: archive file is valid JSON array" "ok" "$archive_valid"
rm -rf "$VALID_DIR"

assert_summary
