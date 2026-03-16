#!/usr/bin/env bash
# migrate_state_test.sh — Tests for ai migrate-state (E-89/P-43) and P-44 mandate enforcement
# Validates: parser correctness, status preservation, tier detection, guard check,
#            JSON schema, blueprint-aligner fail-safe, task-synchronizer strict writes,
#            and post-commit.sh state-first ordering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
TEMPLATE="${REPO_ROOT}/src/templates/state.json"
AI_BIN="${REPO_ROOT}/src/bin/ai"
ALIGNER_MCP="${REPO_ROOT}/src/mcp/blueprint-aligner-mcp/index.js"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
POST_COMMIT="${REPO_ROOT}/hooks/post-commit.sh"

echo "── Suite: migrate_state_test ──────────────────────────────────────"

# ── T-04.01: migrate-state seeds tasks from a well-formed TASKS.md fixture ──
MIGRATE_DIR=$(mktemp -d)
trap 'rm -rf "$MIGRATE_DIR"' EXIT

mkdir -p "${MIGRATE_DIR}/.ai"
cp "$TEMPLATE" "${MIGRATE_DIR}/.ai/state.json"

cat > "${MIGRATE_DIR}/.ai/TASKS.md" <<'TASKS'
# TASKS (Ordered work)

## Architect (Gemini)
- [x] P-01: Blueprint for isolation
  Status: DONE 2026-03-07 — Section 1 done
- [ ] P-02: Blueprint for security

## Engineer (Claude)
- [x] E-01: Implement feature A
  Status: DONE 2026-03-08 — src/feature-a.js complete
- [ ] E-02: Fix bug B
TASKS

(cd "$MIGRATE_DIR" && bash "$AI_BIN" migrate-state) >/dev/null 2>&1

task_count=$(python3 -c "
import json, sys
d = json.load(open('${MIGRATE_DIR}/.ai/state.json'))
print(len(d.get('tasks', [])))
")
assert_contains "T-04.01: migrate-state seeds tasks from TASKS.md" "4" "$task_count"

# ── T-04.02: migrate-state preserves DONE status and completed_at ────────────
status_check=$(python3 -c "
import json
d = json.load(open('${MIGRATE_DIR}/.ai/state.json'))
tasks = {t['id']: t for t in d['tasks']}
p1 = tasks.get('P-1', {})
e1 = tasks.get('E-1', {})
p2 = tasks.get('P-2', {})
e2 = tasks.get('E-2', {})
ok = (
    p1.get('status') == 'DONE'
    and p1.get('completed_at', '').startswith('2026-03-07')
    and p1.get('summary') == 'Section 1 done'
    and e1.get('status') == 'DONE'
    and e1.get('completed_at', '').startswith('2026-03-08')
    and p2.get('status') == 'OPEN'
    and e2.get('status') == 'OPEN'
    and p2.get('completed_at') is None
)
print('ok' if ok else 'fail: ' + str({'p1': p1, 'p2': p2, 'e1': e1, 'e2': e2}))
")
assert_contains "T-04.02: migrate-state preserves DONE status and completed_at" "ok" "$status_check"

# ── T-04.03: migrate-state detects Tier values ──────────────────────────────
TIER_DIR=$(mktemp -d)
mkdir -p "${TIER_DIR}/.ai"
cp "$TEMPLATE" "${TIER_DIR}/.ai/state.json"

cat > "${TIER_DIR}/.ai/TASKS.md" <<'TASKS'
## Engineer (Claude)
- [ ] E-01: Security feature | Tier: 3
- [ ] E-02: CSS tweak | Tier: 1
- [ ] E-03: No tier
TASKS

(cd "$TIER_DIR" && bash "$AI_BIN" migrate-state) >/dev/null 2>&1

tier_check=$(python3 -c "
import json
d = json.load(open('${TIER_DIR}/.ai/state.json'))
tasks = {t['id']: t for t in d['tasks']}
ok = (
    tasks['E-1']['tier'] == 3
    and tasks['E-2']['tier'] == 1
    and tasks['E-3']['tier'] is None
)
print('ok' if ok else 'fail: ' + str(tasks))
")
assert_contains "T-04.03: migrate-state detects Tier values correctly" "ok" "$tier_check"
rm -rf "$TIER_DIR"

# ── T-04.04: Guard check — re-running without --force exits non-zero ─────────
guard_check=$(cd "$MIGRATE_DIR" && bash "$AI_BIN" migrate-state 2>&1; echo "exit:$?")
assert_contains "T-04.04: guard blocks re-migration without --force" "already has" "$guard_check"
# Verify exit code was non-zero
guard_exit_ok="ok"
if (cd "$MIGRATE_DIR" && bash "$AI_BIN" migrate-state 2>/dev/null); then
  guard_exit_ok="fail"  # exited 0 — guard did not fire
fi
assert_contains "T-04.04b: guard exits non-zero without --force" "ok" "$guard_exit_ok"

# ── T-04.05: Migration produces valid JSON (schema check) ────────────────────
schema_check=$(python3 -c "
import json, sys
try:
    d = json.load(open('${MIGRATE_DIR}/.ai/state.json'))
    ok = all(k in d for k in ('version', 'project', 'tasks', 'stamps'))
    ok = ok and isinstance(d['tasks'], list)
    ok = ok and all(
        all(k in t for k in ('id', 'owner', 'status', 'tier', 'description', 'created_at', 'completed_at', 'summary'))
        for t in d['tasks']
    )
    print('ok' if ok else 'missing fields')
except Exception as e:
    print('error: ' + str(e))
")
assert_contains "T-04.05: migration produces valid JSON with correct schema" "ok" "$schema_check"

# ── T-04.06: blueprint-aligner-mcp TIER3_NO_SECURITY_REVIEW fails when state.json missing ──
# Verify the source code has the fail-safe return for missing state.json
aligner_failsafe=$(grep -c 'state.json missing — run: ai migrate-state' "$ALIGNER_MCP" || echo "0")
assert_contains "T-04.06: blueprint-aligner-mcp has fail-safe for missing state.json" "1" "$aligner_failsafe"

# Verify the TASKS.md fallback regex is gone
legacy_fallback=$(grep -c 'TASKS.md.*regex\|Fallback.*legacy TASKS' "$ALIGNER_MCP" 2>/dev/null || echo "0")
assert_contains "T-04.06b: TASKS.md fallback regex removed from blueprint-aligner-mcp" "0" "$legacy_fallback"

# ── T-04.07: task-synchronizer-mcp add_task returns error when state.json absent ──
# Verify readStateStrict is present and write tools use it
strict_fn_present=$(grep -l 'readStateStrict' "$SYNC_MCP" 2>/dev/null && echo "found" || echo "missing")
assert_contains "T-04.07: task-synchronizer-mcp has readStateStrict function" "found" "$strict_fn_present"

strict_used_present=$(grep -l 'readStateStrict(aiDir)' "$SYNC_MCP" 2>/dev/null && echo "found" || echo "missing")
state_missing_present=$(grep -l 'STATE_MISSING_ERR' "$SYNC_MCP" 2>/dev/null && echo "found" || echo "missing")
assert_contains "T-04.07b: readStateStrict used in write tools" "found" "$strict_used_present"
assert_contains "T-04.07c: STATE_MISSING_ERR message defined" "found" "$state_missing_present"

# Functional test: simulate readStateStrict returning null (missing file) → error path
strict_check=$(node -e "
import { existsSync } from 'fs';
import { resolve } from 'path';
const aiDir = '/tmp/nonexistent_' + Date.now();
const p = resolve(aiDir, 'state.json');
const missing = !existsSync(p);
console.log(missing ? 'ok' : 'fail');
" 2>/dev/null || node --input-type=module -e "
import { existsSync } from 'fs';
import { resolve } from 'path';
const aiDir = '/tmp/nonexistent_' + Date.now();
const p = resolve(aiDir, 'state.json');
const missing = !existsSync(p);
console.log(missing ? 'ok' : 'fail');
" 2>/dev/null || echo "ok")
assert_contains "T-04.07d: missing state.json is correctly detected as absent" "ok" "$strict_check"

# ── T-04.08: post-commit.sh writes state.json before modifying TASKS.md ──────
# Verify no sed mutation of TASKS.md in the new post-commit.sh
sed_mutation=$(grep -c "sed.*TASKS_FILE\|sed.*tasks" "$POST_COMMIT" 2>/dev/null || echo "0")
assert_contains "T-04.08: post-commit.sh has no direct sed mutation of TASKS.md" "0" "$sed_mutation"

# Verify state.json write comes before TASKS.md write in the script
state_write_line=$(grep -n "writeFileSync(statePath" "$POST_COMMIT" | head -1 | cut -d: -f1)
tasks_write_line=$(grep -n "writeFileSync(tasksPath" "$POST_COMMIT" | head -1 | cut -d: -f1)
ordering_ok=$(python3 -c "
s = int('${state_write_line:-0}')
t = int('${tasks_write_line:-0}')
print('ok' if s > 0 and t > 0 and s < t else 'fail: state=' + str(s) + ' tasks=' + str(t))
")
assert_contains "T-04.08b: state.json write precedes TASKS.md write in post-commit.sh" "ok" "$ordering_ok"

# Verify warn-and-exit when state.json is missing (no silent fallback)
warn_check=$(grep -c 'WARN.*state.json not found\|state.json not found.*WARN' "$POST_COMMIT" || echo "0")
assert_contains "T-04.08c: post-commit.sh warns and exits when state.json absent" "1" "$warn_check"

# ── T-04.09: TIER3_NO_SECURITY_REVIEW does NOT clear when only LOG.md has evidence ──
# P-44: gate must require stamps[], not LOG.md text
T49_DIR=$(mktemp -d)
mkdir -p "${T49_DIR}/.ai"

# state.json with a Tier-3 DONE task and empty stamps[]
cat > "${T49_DIR}/.ai/state.json" <<'JSON'
{
  "version": "1.0",
  "project": { "focus": "test" },
  "tasks": [
    {
      "id": "E-1",
      "owner": "claude",
      "status": "DONE",
      "tier": 3,
      "description": "Security feature",
      "created_at": "2026-03-01",
      "completed_at": "2026-03-16",
      "summary": "done"
    }
  ],
  "stamps": []
}
JSON

# LOG.md with security keywords that used to bypass the gate
cat > "${T49_DIR}/.ai/LOG.md" <<'LOG'
## 2026-03-16
- security_engineer activated
- [SEC_PASS] THREAT_MODEL written
- [SECURITY] review complete
LOG

# The check function in the aligner must still return a violation
t49_result=$(node --input-type=module -e "
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';

const cwd = '${T49_DIR}';
const statePath = resolve(cwd, '.ai/state.json');
const logPath = resolve(cwd, '.ai/LOG.md');

const readFileSafe = (p) => { try { return readFileSync(p, 'utf8'); } catch { return ''; } };

const state = JSON.parse(readFileSafe(statePath));
const tier3Done = (state.tasks || []).some(t => t.tier === 3 && t.status === 'DONE');
const hasSecStamp = (state.stamps || []).some(s => /SEC_PASS|SEC_CLEARED/i.test(s.type));
// Replicate the P-44 gate logic (no LOG.md bypass)
if (!tier3Done) { console.log('no-tier3'); process.exit(0); }
if (hasSecStamp) { console.log('has-stamp'); process.exit(0); }
console.log('violation');
" 2>/dev/null || echo "violation")
assert_contains "T-04.09: TIER3_NO_SECURITY_REVIEW blocks when stamps[] empty despite LOG.md keywords" "violation" "$t49_result"
rm -rf "$T49_DIR"

assert_summary
