#!/usr/bin/env bash
# verify_sync_test.sh — Tests for verify_markdown_sync tool (E-102 / E-95)
# Validates PASS/FAIL behavior for the Markdown-as-Read-Only sync check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
TEMPLATE="${REPO_ROOT}/src/templates/state.json"

echo "── Suite: verify_sync_test ────────────────────────────────────────"

# Helper: run verify_markdown_sync logic inline (mirrors MCP implementation)
# Reads state.json and TASKS.md/REVIEWS.md from a tmp dir, returns PASS or FAIL details
run_verify_sync() {
  local DIR="$1"
  node -e "
    import { readFileSync, existsSync } from 'fs';
    import { resolve } from 'path';

    const aiDir = process.argv[1];
    const failures = [];

    // Load state.json
    const statePath = resolve(aiDir, 'state.json');
    if (!existsSync(statePath)) { console.log('FAIL: state.json missing'); process.exit(0); }
    let state;
    try { state = JSON.parse(readFileSync(statePath, 'utf8')); }
    catch { console.log('FAIL: state.json corrupt'); process.exit(0); }

    // Check TASKS.md
    const tasksPath = resolve(aiDir, 'TASKS.md');
    if (existsSync(tasksPath)) {
      const t = readFileSync(tasksPath, 'utf8');
      const mdCount = (t.match(/^- \[/gm) || []).length;
      const stateCount = state.tasks.length;
      if (Math.abs(mdCount - stateCount) > 2)
        failures.push('TASKS_COUNT_DRIFT:' + mdCount + 'vs' + stateCount);
      if (!t.startsWith('# TASKS (Generated from state.json)'))
        failures.push('TASKS_MISSING_HEADER');
    }

    // Check REVIEWS.md (only when stamps exist)
    const reviewsPath = resolve(aiDir, 'REVIEWS.md');
    if (existsSync(reviewsPath) && state.stamps.length > 0) {
      const r = readFileSync(reviewsPath, 'utf8');
      if (!r.startsWith('# REVIEWS.md (Generated from state.json)'))
        failures.push('REVIEWS_MISSING_HEADER');
      const mdStamps = (r.match(/^\[[\w_]+\]/gm) || []).length;
      if (mdStamps < state.stamps.length)
        failures.push('REVIEWS_STAMP_DRIFT:' + mdStamps + 'vs' + state.stamps.length);
    }

    console.log(failures.length === 0 ? 'PASS' : 'FAIL:' + failures.join(','));
  " "$DIR" --input-type=module 2>/dev/null || echo "FAIL:node_error"
}

# ── T-03.01: PASS when header present and counts match ────────────────
CLEAN_DIR=$(mktemp -d)
cp "$TEMPLATE" "${CLEAN_DIR}/state.json"
# Seed state with 2 tasks
python3 -c "
import json; s=json.load(open('${CLEAN_DIR}/state.json'))
s['tasks']=[{'id':'E-1','owner':'Engineer (Claude)','status':'OPEN','tier':1,'description':'Task one','created_at':'2026-01-01T00:00:00Z','completed_at':None,'summary':None},
             {'id':'E-2','owner':'Engineer (Claude)','status':'DONE','tier':2,'description':'Task two','created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Done'}]
json.dump(s, open('${CLEAN_DIR}/state.json','w'), indent=2)
"
# Write matching TASKS.md with generated header
cat > "${CLEAN_DIR}/TASKS.md" <<'TASKS'
# TASKS (Generated from state.json)

## Engineer (Claude)
- [ ] E-1: Task one | Tier: 1
- [x] E-2: Task two | Tier: 2
  Status: DONE 2026-01-02 — Done
TASKS
result=$(run_verify_sync "$CLEAN_DIR")
assert_contains "T-03.01: PASS when header present and counts match" "PASS" "$result"
rm -rf "$CLEAN_DIR"

# ── T-03.02: FAIL when TASKS.md missing generated header ─────────────
NOHEADER_DIR=$(mktemp -d)
cp "$TEMPLATE" "${NOHEADER_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${NOHEADER_DIR}/state.json'))
s['tasks']=[{'id':'E-1','owner':'Engineer (Claude)','status':'OPEN','tier':1,'description':'Test','created_at':'2026-01-01T00:00:00Z','completed_at':None,'summary':None}]
json.dump(s, open('${NOHEADER_DIR}/state.json','w'), indent=2)
"
# Write TASKS.md WITHOUT the generated header (hand-edited simulation)
cat > "${NOHEADER_DIR}/TASKS.md" <<'TASKS'
## Engineer (Claude)
- [ ] E-1: Test | Tier: 1
TASKS
result=$(run_verify_sync "$NOHEADER_DIR")
assert_contains "T-03.02: FAIL when TASKS.md missing generated header" "FAIL" "$result"
assert_contains "T-03.02b: reports TASKS_MISSING_HEADER" "TASKS_MISSING_HEADER" "$result"
rm -rf "$NOHEADER_DIR"

# ── T-03.03: FAIL when task count drift > 2 ──────────────────────────
DRIFT_DIR=$(mktemp -d)
cp "$TEMPLATE" "${DRIFT_DIR}/state.json"
# state.json has 5 tasks
python3 -c "
import json; s=json.load(open('${DRIFT_DIR}/state.json'))
s['tasks']=[{'id':'E-'+str(i),'owner':'Engineer (Claude)','status':'OPEN','tier':1,'description':'Task '+str(i),'created_at':'2026-01-01T00:00:00Z','completed_at':None,'summary':None} for i in range(1,6)]
json.dump(s, open('${DRIFT_DIR}/state.json','w'), indent=2)
"
# TASKS.md has only 1 task (drift = 4 > 2)
cat > "${DRIFT_DIR}/TASKS.md" <<'TASKS'
# TASKS (Generated from state.json)

## Engineer (Claude)
- [ ] E-1: Task 1 | Tier: 1
TASKS
result=$(run_verify_sync "$DRIFT_DIR")
assert_contains "T-03.03: FAIL when task count drift > 2" "FAIL" "$result"
assert_contains "T-03.03b: reports TASKS_COUNT_DRIFT" "TASKS_COUNT_DRIFT" "$result"
rm -rf "$DRIFT_DIR"

# ── T-03.04: FAIL when REVIEWS.md missing header but stamps exist ─────
STAMPS_DIR=$(mktemp -d)
cp "$TEMPLATE" "${STAMPS_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${STAMPS_DIR}/state.json'))
s['tasks']=[{'id':'E-1','owner':'Engineer (Claude)','status':'DONE','tier':2,'description':'Test','created_at':'2026-01-01T00:00:00Z','completed_at':'2026-01-02T00:00:00Z','summary':'Done'}]
s['stamps']=[{'type':'CRITIC_STAMP','agent':'critic_arch','task_id':'E-1','timestamp':'2026-01-02T00:00:00Z','summary':'All clear'}]
json.dump(s, open('${STAMPS_DIR}/state.json','w'), indent=2)
"
# TASKS.md is correct
cat > "${STAMPS_DIR}/TASKS.md" <<'TASKS'
# TASKS (Generated from state.json)

## Engineer (Claude)
- [x] E-1: Test | Tier: 2
  Status: DONE 2026-01-02 — Done
TASKS
# REVIEWS.md without generated header (hand-edited)
cat > "${STAMPS_DIR}/REVIEWS.md" <<'REVIEWS'
[CRITIC_STAMP] 2026-01-02 | All clear
REVIEWS
result=$(run_verify_sync "$STAMPS_DIR")
assert_contains "T-03.04: FAIL when REVIEWS.md missing header but stamps exist" "FAIL" "$result"
assert_contains "T-03.04b: reports REVIEWS_MISSING_HEADER" "REVIEWS_MISSING_HEADER" "$result"
rm -rf "$STAMPS_DIR"

# ── T-03.05: PASS when state.json has zero stamps and REVIEWS.md is empty ──
NOSTAMP_DIR=$(mktemp -d)
cp "$TEMPLATE" "${NOSTAMP_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${NOSTAMP_DIR}/state.json'))
s['tasks']=[{'id':'E-1','owner':'Engineer (Claude)','status':'OPEN','tier':1,'description':'Fresh task','created_at':'2026-01-01T00:00:00Z','completed_at':None,'summary':None}]
s['stamps']=[]
json.dump(s, open('${NOSTAMP_DIR}/state.json','w'), indent=2)
"
cat > "${NOSTAMP_DIR}/TASKS.md" <<'TASKS'
# TASKS (Generated from state.json)

## Engineer (Claude)
- [ ] E-1: Fresh task | Tier: 1
TASKS
# REVIEWS.md is empty (no stamps — no check required)
printf "# REVIEWS.md\n" > "${NOSTAMP_DIR}/REVIEWS.md"
result=$(run_verify_sync "$NOSTAMP_DIR")
assert_contains "T-03.05: PASS when zero stamps and REVIEWS.md is empty" "PASS" "$result"
rm -rf "$NOSTAMP_DIR"

assert_summary
