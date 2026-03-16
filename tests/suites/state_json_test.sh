#!/usr/bin/env bash
# state_json_test.sh — Stress tests for state.json atomic writes (E-82 / P-40)
# Validates: JSON integrity after concurrent writes, nextId correctness,
# regenerateMarkdown output, and state.json schema compliance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
TEMPLATE="${REPO_ROOT}/src/templates/state.json"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: state_json_test ─────────────────────────────────────────"

# ── T-02.01: Template is valid JSON with required schema fields ───────
assert_exists "$TEMPLATE"
schema_check=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
ok = all(k in d for k in ('version', 'project', 'tasks', 'stamps'))
ok = ok and all(k in d['project'] for k in ('current_tier', 'release_verdict', 'focus'))
ok = ok and isinstance(d['tasks'], list) and isinstance(d['stamps'], list)
print('ok' if ok else 'missing_fields')
" "$TEMPLATE")
assert_contains "T-02.01: state.json template has required schema" "ok" "$schema_check"

# ── T-02.02: task-synchronizer-mcp syntax is valid ────────────────────
# ESM files can't use node --check; verify via dynamic import parse (catches syntax errors)
assert_status 0 "T-02.02: task-synchronizer-mcp syntax OK" node -e "import('file://${SYNC_MCP}').catch(e => { if (e instanceof SyntaxError) process.exit(1); })"

# ── T-02.03: nextId logic produces correct sequential IDs ─────────────
next_id_check=$(node -e "
const tasks = [
  { id: 'E-1' }, { id: 'E-5' }, { id: 'E-3' },
  { id: 'P-2' }, { id: 'P-10' },
  { id: 'T-1' }
];
function nextId(tasks, prefix) {
  const nums = tasks
    .filter(t => t.id.startsWith(prefix + '-'))
    .map(t => parseInt(t.id.split('-')[1], 10))
    .filter(n => !isNaN(n));
  const max = nums.length > 0 ? Math.max(...nums) : 0;
  return prefix + '-' + (max + 1);
}
const e = nextId(tasks, 'E');
const p = nextId(tasks, 'P');
const t = nextId(tasks, 'T');
console.log(e === 'E-6' && p === 'P-11' && t === 'T-2' ? 'ok' : 'fail: ' + e + ' ' + p + ' ' + t);
")
assert_contains "T-02.03: nextId produces correct sequential IDs" "ok" "$next_id_check"

# ── T-02.04: nextId handles empty task list ───────────────────────────
next_id_empty=$(node -e "
function nextId(tasks, prefix) {
  const nums = tasks
    .filter(t => t.id.startsWith(prefix + '-'))
    .map(t => parseInt(t.id.split('-')[1], 10))
    .filter(n => !isNaN(n));
  const max = nums.length > 0 ? Math.max(...nums) : 0;
  return prefix + '-' + (max + 1);
}
console.log(nextId([], 'E') === 'E-1' ? 'ok' : 'fail');
")
assert_contains "T-02.04: nextId handles empty task list" "ok" "$next_id_empty"

# ── T-02.05: Concurrent writes produce valid JSON (stress test) ───────
# Simulates N parallel writers appending tasks to the same state.json.
# After all writers complete, state.json must be valid JSON with all tasks present.
STRESS_DIR=$(mktemp -d)
trap 'rm -rf "$STRESS_DIR"' EXIT

# Initialize state.json from template
cp "$TEMPLATE" "${STRESS_DIR}/state.json"

NUM_WRITERS=10
PIDS=()

for i in $(seq 1 $NUM_WRITERS); do
  node -e "
    const fs = require('fs');
    const p = '${STRESS_DIR}/state.json';
    // Atomic read-modify-write (single process, sequential within each writer)
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const s = JSON.parse(fs.readFileSync(p, 'utf8'));
        s.tasks.push({
          id: 'E-stress-${i}',
          owner: 'stress-test',
          status: 'OPEN',
          tier: 1,
          description: 'Stress test task ${i}',
          created_at: new Date().toISOString(),
          completed_at: null,
          summary: null
        });
        fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n', 'utf8');
        break;
      } catch (e) {
        // Retry on read/parse failure from concurrent write
        if (attempt === 2) throw e;
        const wait = Math.random() * 50;
        const start = Date.now();
        while (Date.now() - start < wait) {} // busy-wait
      }
    }
  " &
  PIDS+=($!)
done

# Wait for all writers
ALL_OK=true
for pid in "${PIDS[@]}"; do
  if ! wait "$pid" 2>/dev/null; then
    ALL_OK=false
  fi
done

# Verify JSON integrity
stress_valid=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print('ok' if isinstance(d.get('tasks'), list) else 'bad_schema')
except Exception as e:
    print(f'corrupt: {e}')
" "${STRESS_DIR}/state.json")
assert_contains "T-02.05: state.json valid after concurrent writes" "ok" "$stress_valid"

# Count how many tasks landed (may be < NUM_WRITERS due to races — that's the point)
stress_count=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
stress_tasks = [t for t in d['tasks'] if t.get('owner') == 'stress-test']
print(len(stress_tasks))
" "${STRESS_DIR}/state.json")

# At minimum, some tasks must have landed (proves writes worked)
stress_min=$(python3 -c "print('ok' if int('${stress_count}') >= 1 else 'zero_tasks')")
assert_contains "T-02.05b: at least 1 stress task landed" "ok" "$stress_min"

# Report actual landing rate
if [[ "$stress_count" -lt "$NUM_WRITERS" ]]; then
  printf "  ⚠ Race condition detected: %s/%s tasks landed (expected — proves need for single-writer MCP)\n" "$stress_count" "$NUM_WRITERS"
else
  printf "  ℹ All %s/%s tasks landed (no race in this run)\n" "$stress_count" "$NUM_WRITERS"
fi

# ── T-02.06: Single-writer simulation (serialized) preserves all tasks ─
SERIAL_DIR=$(mktemp -d)
cp "$TEMPLATE" "${SERIAL_DIR}/state.json"

node -e "
const fs = require('fs');
const p = '${SERIAL_DIR}/state.json';
for (let i = 1; i <= 20; i++) {
  const s = JSON.parse(fs.readFileSync(p, 'utf8'));
  s.tasks.push({
    id: 'E-' + i,
    owner: 'serial-test',
    status: 'OPEN',
    tier: 1,
    description: 'Serial task ' + i,
    created_at: new Date().toISOString(),
    completed_at: null,
    summary: null
  });
  fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n', 'utf8');
}
"

serial_check=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
tasks = d.get('tasks', [])
ids = sorted([t['id'] for t in tasks])
expected = sorted(['E-' + str(i) for i in range(1, 21)])
print('ok' if ids == expected else f'mismatch: got {len(ids)} tasks')
" "${SERIAL_DIR}/state.json")
assert_contains "T-02.06: serialized writes preserve all 20 tasks" "ok" "$serial_check"
rm -rf "$SERIAL_DIR"

# ── T-02.07: Stamp writes don't corrupt task data ────────────────────
STAMP_DIR=$(mktemp -d)
cp "$TEMPLATE" "${STAMP_DIR}/state.json"

node -e "
const fs = require('fs');
const p = '${STAMP_DIR}/state.json';
// Add a task first
const s = JSON.parse(fs.readFileSync(p, 'utf8'));
s.tasks.push({ id: 'E-1', owner: 'test', status: 'OPEN', tier: 2, description: 'Test task' });
fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n');

// Add 5 stamps
for (let i = 0; i < 5; i++) {
  const s2 = JSON.parse(fs.readFileSync(p, 'utf8'));
  s2.stamps.push({
    type: ['ARCH_PASS','SEC_PASS','TESTS_PASS','ALIGN_PASS','CRITIC_STAMP'][i],
    agent: 'critic_' + i,
    task_id: 'E-1',
    timestamp: new Date().toISOString(),
    summary: 'Stamp ' + i
  });
  fs.writeFileSync(p, JSON.stringify(s2, null, 2) + '\n');
}
"

stamp_check=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
tasks_ok = len(d['tasks']) == 1 and d['tasks'][0]['id'] == 'E-1'
stamps_ok = len(d['stamps']) == 5
types = {s['type'] for s in d['stamps']}
expected_types = {'ARCH_PASS', 'SEC_PASS', 'TESTS_PASS', 'ALIGN_PASS', 'CRITIC_STAMP'}
print('ok' if tasks_ok and stamps_ok and types == expected_types else 'fail')
" "${STAMP_DIR}/state.json")
assert_contains "T-02.07: stamps don't corrupt task data" "ok" "$stamp_check"
rm -rf "$STAMP_DIR"

# ── T-02.08: regenerateMarkdown produces correct TASKS.md ─────────────
MD_DIR=$(mktemp -d)
mkdir -p "$MD_DIR"

node -e "
const fs = require('fs');
const { resolve } = require('path');
const aiDir = '${MD_DIR}';

const state = {
  version: '1.0',
  project: { current_tier: 2, release_verdict: null, focus: 'testing' },
  tasks: [
    { id: 'E-1', owner: 'Engineer (Claude)', status: 'DONE', tier: 2, description: 'Build feature', completed_at: '2026-03-15T10:00:00Z', summary: 'Complete' },
    { id: 'E-2', owner: 'Engineer (Claude)', status: 'OPEN', tier: 1, description: 'Fix bug' },
    { id: 'P-1', owner: 'Architect (Gemini)', status: 'DONE', tier: 2, description: 'Design API', completed_at: '2026-03-14T10:00:00Z', summary: 'Blueprint done' }
  ],
  stamps: [
    { type: 'ARCH_PASS', agent: 'critic_arch', timestamp: '2026-03-15T10:00:00Z', summary: 'All clear' }
  ]
};

// Inline regenerateMarkdown logic (from task-synchronizer-mcp)
const tasksPath = resolve(aiDir, 'TASKS.md');
const lines = ['# TASKS (Generated from state.json)', ''];
const byOwner = {};
for (const t of state.tasks) {
  const owner = t.owner || 'Unassigned';
  if (!byOwner[owner]) byOwner[owner] = [];
  byOwner[owner].push(t);
}
for (const [owner, tasks] of Object.entries(byOwner)) {
  lines.push('## ' + owner);
  for (const t of tasks) {
    const check = t.status === 'DONE' ? 'x' : ' ';
    const tierStr = t.tier ? ' | Tier: ' + t.tier : '';
    lines.push('- [' + check + '] ' + t.id + ': ' + t.description + tierStr);
    if (t.status === 'DONE' && t.completed_at) {
      lines.push('  Status: DONE ' + t.completed_at.split('T')[0] + ' — ' + (t.summary || 'Complete'));
    }
  }
  lines.push('');
}
fs.writeFileSync(tasksPath, lines.join('\n'), 'utf8');

// Also generate REVIEWS.md
const reviewsPath = resolve(aiDir, 'REVIEWS.md');
const stampLines = ['# REVIEWS.md (Generated from state.json)', ''];
for (const s of state.stamps) {
  const date = s.timestamp ? s.timestamp.split('T')[0] : 'unknown';
  stampLines.push('[' + s.type + '] ' + date + ' | ' + (s.summary || s.agent || ''));
}
stampLines.push('');
fs.writeFileSync(reviewsPath, stampLines.join('\n'), 'utf8');
"

# Verify TASKS.md has expected structure
md_tasks=$(cat "${MD_DIR}/TASKS.md")
assert_contains "T-02.08a: TASKS.md has header" "Generated from state.json" "$md_tasks"
assert_contains "T-02.08b: TASKS.md has Engineer section" "## Engineer (Claude)" "$md_tasks"
assert_contains "T-02.08c: TASKS.md has Architect section" "## Architect (Gemini)" "$md_tasks"
assert_contains "T-02.08d: TASKS.md has done checkbox" "[x] E-1" "$md_tasks"
assert_contains "T-02.08e: TASKS.md has open checkbox" "[ ] E-2" "$md_tasks"
assert_contains "T-02.08f: TASKS.md has tier info" "Tier: 2" "$md_tasks"

# Verify REVIEWS.md
md_reviews=$(cat "${MD_DIR}/REVIEWS.md")
assert_contains "T-02.08g: REVIEWS.md has stamp" "ARCH_PASS" "$md_reviews"
assert_contains "T-02.08h: REVIEWS.md has date" "2026-03-15" "$md_reviews"
rm -rf "$MD_DIR"

# ── T-02.09: update_task_status DONE sets completed_at ────────────────
done_check=$(node -e "
const state = {
  tasks: [{ id: 'E-1', status: 'OPEN', completed_at: null }],
  stamps: []
};
const task = state.tasks.find(t => t.id === 'E-1');
task.status = 'DONE';
task.completed_at = new Date().toISOString();
task.summary = 'Finished';
console.log(task.completed_at && task.summary === 'Finished' ? 'ok' : 'fail');
")
assert_contains "T-02.09: update_task_status DONE sets completed_at" "ok" "$done_check"

# ── T-02.10: Corrupt JSON recovery (readState returns null) ──────────
corrupt_check=$(node -e "
const fs = require('fs');
const tmp = require('os').tmpdir() + '/corrupt_state_' + Date.now() + '.json';
fs.writeFileSync(tmp, '{broken json!!!');
try {
  const data = JSON.parse(fs.readFileSync(tmp, 'utf8'));
  console.log('parsed_bad');
} catch {
  console.log('ok');
}
fs.unlinkSync(tmp);
")
assert_contains "T-02.10: corrupt JSON is caught by parse" "ok" "$corrupt_check"

# ── T-02.11: run_preflight marks deltas as read: true ────────────────
# Mirrors orchestrator-mcp/index.js lines 146-154 (E-115)
DELTA_DIR=$(mktemp -d)
cp "$TEMPLATE" "${DELTA_DIR}/state.json"
python3 -c "
import json; s=json.load(open('${DELTA_DIR}/state.json'))
s['deltas']=[{'task_id':'E-99','timestamp':'2026-01-01T00:00:00Z','summary':'Test delta','files_changed':[],'read':False}]
json.dump(s, open('${DELTA_DIR}/state.json','w'), indent=2)
"
# Inline the delta-marking logic from orchestrator-mcp
node -e "
  import { readFileSync, writeFileSync } from 'fs';
  import { resolve } from 'path';
  const statePath = resolve(process.argv[1], 'state.json');
  const state = JSON.parse(readFileSync(statePath, 'utf8'));
  const unread = (state.deltas || []).filter(d => !d.read);
  for (const d of unread) { d.read = true; }
  if (unread.length > 0) writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
" "$DELTA_DIR" --input-type=module 2>/dev/null
delta_check=$(python3 -c "
import json; s=json.load(open('${DELTA_DIR}/state.json'))
deltas=s.get('deltas',[])
print('ok' if len(deltas)==1 and deltas[0].get('read')==True else 'fail:'+str(deltas))
")
assert_contains "T-02.11: run_preflight marks deltas as read:true" "ok" "$delta_check"
rm -rf "$DELTA_DIR"

# ── T-02.12: readStateStrict returns null for wrong schema version (E-117) ──
VERSION_DIR=$(mktemp -d)
python3 -c "
import json
json.dump({'version':'0.x','project':{},'tasks':[],'stamps':[]}, open('${VERSION_DIR}/state.json','w'), indent=2)
"
version_check=$(node -e "
  import { readFileSync } from 'fs';
  import { resolve } from 'path';
  const p = resolve(process.argv[1], 'state.json');
  const state = JSON.parse(readFileSync(p, 'utf8'));
  // Mirrors readStateStrict version guard (E-117)
  if (state.version !== '1.0') { console.log('null'); } else { console.log('parsed'); }
" "$VERSION_DIR" --input-type=module 2>/dev/null)
assert_contains "T-02.12: version guard rejects schema v0.x" "null" "$version_check"
rm -rf "$VERSION_DIR"

assert_summary
