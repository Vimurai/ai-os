#!/usr/bin/env bash
# structured_outputs_test.sh — Unit tests for E-12 Structured Outputs
# Tests: schema file, schema-validator.js, task-synchronizer-mcp validate_payload
#        tool, runtime validation guards, and TASKS.md/REVIEWS.md protection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMAS="${REPO_ROOT}/src/shared/schemas/state.json"
VALIDATOR="${REPO_ROOT}/src/shared/schema-validator.js"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: structured_outputs ────────────────────────────────────────"

# ── T-SO-S01: Schema file structure ──────────────────────────────────────────
echo ""
echo "  [T-SO-S01] Schema file"

assert_status 0 "src/shared/schemas/state.json exists" test -f "$SCHEMAS"

assert_status 0 "state.json is valid JSON" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
JS

assert_status 0 "state.json version is 1.0" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (s.version !== '1.0') process.exit(1);
JS

assert_status 0 "state.json has schemas property" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (!s.schemas || typeof s.schemas !== 'object') process.exit(1);
JS

assert_status 0 "task_create schema exists" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (!s.schemas.task_create) process.exit(1);
JS

assert_status 0 "task_update schema exists" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (!s.schemas.task_update) process.exit(1);
JS

assert_status 0 "stamp_add schema exists" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (!s.schemas.stamp_add) process.exit(1);
JS

assert_status 0 "project_update schema exists" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (!s.schemas.project_update) process.exit(1);
JS

assert_status 0 "task_create has required [owner, description]" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
const req = s.schemas.task_create.required;
if (!req.includes('owner') || !req.includes('description')) process.exit(1);
JS

assert_status 0 "task_update has required [id, status]" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
const req = s.schemas.task_update.required;
if (!req.includes('id') || !req.includes('status')) process.exit(1);
JS

assert_status 0 "tier enum is [1, 2, 3] in task_create" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
const tierEnum = s.schemas.task_create.properties.tier.enum;
if (!Array.isArray(tierEnum) || JSON.stringify(tierEnum) !== '[1,2,3]') process.exit(1);
JS

assert_status 0 "status enum is [OPEN, BLOCKED, DONE] in task_update" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
const e = s.schemas.task_update.properties.status.enum;
if (!e.includes('OPEN') || !e.includes('BLOCKED') || !e.includes('DONE')) process.exit(1);
JS

assert_status 0 "task_create additionalProperties is false" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('$SCHEMAS', 'utf8'));
if (s.schemas.task_create.additionalProperties !== false) process.exit(1);
JS

# ── T-SO-S02: schema-validator.js module ─────────────────────────────────────
echo ""
echo "  [T-SO-S02] schema-validator.js"

assert_status 0 "schema-validator.js exists" test -f "$VALIDATOR"

assert_status 0 "exports validate function" \
  grep -q 'export function validate' "$VALIDATOR"

assert_status 0 "exports validateNamed function" \
  grep -q 'export function validateNamed' "$VALIDATOR"

assert_status 0 "exports loadSchemas function" \
  grep -q 'export function loadSchemas' "$VALIDATOR"

assert_status 0 "handles type checking" \
  grep -q '_matchesType' "$VALIDATOR"

assert_status 0 "handles enum validation" \
  grep -q 'schema.enum' "$VALIDATOR"

assert_status 0 "handles required fields" \
  grep -q 'schema.required' "$VALIDATOR"

assert_status 0 "handles additionalProperties" \
  grep -q 'additionalProperties' "$VALIDATOR"

assert_status 0 "handles minLength/maxLength" \
  grep -q 'minLength' "$VALIDATOR"

assert_status 0 "handles pattern (regex)" \
  grep -q 'schema.pattern' "$VALIDATOR"

# ── T-SO-S03: validate() — unit tests ────────────────────────────────────────
echo ""
echo "  [T-SO-S03] validate() unit tests"

assert_status 0 "valid task_create payload passes" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', {
  owner: 'Engineer (Claude)',
  description: 'Implement foo',
  tier: 2
});
if (!r.valid) { console.error(r.errors); process.exit(1); }
JS

assert_status 0 "missing required field fails" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', { description: 'no owner' });
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('owner'))) process.exit(1);
JS

assert_status 0 "wrong type fails" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', { owner: 123, description: 'test' });
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('type'))) process.exit(1);
JS

assert_status 0 "invalid enum value fails" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', {
  owner: 'Engineer (Claude)',
  description: 'test',
  tier: 5  // not in [1,2,3]
});
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('tier') || e.includes('enum'))) process.exit(1);
JS

assert_status 0 "additionalProperties violation fails" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', {
  owner: 'Engineer (Claude)',
  description: 'test',
  forbidden_field: 'sneaky'
});
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('forbidden_field'))) process.exit(1);
JS

assert_status 0 "minLength violation fails" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', { owner: '', description: 'test' });
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('minLength') || e.includes('owner'))) process.exit(1);
JS

assert_status 0 "task_update pattern validates E-## format" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const bad = validateNamed('task_update', { id: 'WRONG', status: 'DONE' });
if (bad.valid) process.exit(1);
const good = validateNamed('task_update', { id: 'E-11', status: 'DONE' });
if (!good.valid) { console.error(good.errors); process.exit(1); }
JS

assert_status 0 "stamp_add with all required fields passes" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('stamp_add', {
  type: 'CRITIC_STAMP',
  agent: 'Claude',
  summary: 'E-12 PASS'
});
if (!r.valid) { console.error(r.errors); process.exit(1); }
JS

assert_status 0 "project_update with valid focus passes" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('project_update', { focus: 'E-12 Structured Outputs', current_tier: 2 });
if (!r.valid) { console.error(r.errors); process.exit(1); }
JS

assert_status 0 "unknown schema name returns error" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('no_such_schema', {});
if (r.valid) process.exit(1);
if (!r.errors.some(e => e.includes('Unknown schema'))) process.exit(1);
JS

assert_status 0 "returns schemaName in result" \
  node --input-type=module <<JS
import { validateNamed } from '${VALIDATOR}';
const r = validateNamed('task_create', { owner: 'Claude', description: 'x' });
if (r.schemaName !== 'task_create') process.exit(1);
JS

# ── T-SO-S04: task-synchronizer-mcp integration ──────────────────────────────
echo ""
echo "  [T-SO-S04] task-synchronizer-mcp integration"

assert_status 0 "imports validateNamed from schema-validator" \
  grep -q 'validateNamed' "$SERVER"

assert_status 0 "_assertSchema helper defined" \
  grep -q '_assertSchema' "$SERVER"

assert_status 0 "add_task calls _assertSchema(task_create)" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const addIdx = src.indexOf("case \"add_task\":");
if (addIdx === -1) process.exit(1);
const block = src.slice(addIdx, addIdx + 400);
if (!block.includes('task_create')) process.exit(1);
JS

assert_status 0 "update_task_status calls _assertSchema(task_update)" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const idx = src.indexOf("case \"update_task_status\":");
if (idx === -1) process.exit(1);
const block = src.slice(idx, idx + 400);
if (!block.includes('task_update')) process.exit(1);
JS

assert_status 0 "add_stamp calls _assertSchema(stamp_add)" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const idx = src.indexOf("case \"add_stamp\":");
if (idx === -1) process.exit(1);
const block = src.slice(idx, idx + 300);
if (!block.includes('stamp_add')) process.exit(1);
JS

assert_status 0 "set_project_focus calls _assertSchema(project_update)" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const idx = src.indexOf("case \"set_project_focus\":");
if (idx === -1) process.exit(1);
const block = src.slice(idx, idx + 300);
if (!block.includes('project_update')) process.exit(1);
JS

assert_status 0 "validate_payload tool declared in server" \
  grep -q '"validate_payload"' "$SERVER"

assert_status 0 "validate_payload case handled in switch" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
if (!src.includes('case "validate_payload":')) process.exit(1);
JS

assert_status 0 "SCHEMA_PASS emitted on success" \
  grep -q 'SCHEMA_PASS' "$SERVER"

assert_status 0 "SCHEMA_FAIL emitted on failure" \
  grep -q 'SCHEMA_FAIL' "$SERVER"

assert_status 0 "validate_payload isError:true on invalid payload" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const idx = src.indexOf('case "validate_payload":');
if (idx === -1) process.exit(1);
const block = src.slice(idx, idx + 1200);
// E-179: SCHEMA_FAIL still signals isError to the model, but now via the shared
// rejection() helper ({ ..., isError: true, _meta.expected_rejection }) so telemetry
// books it SUCCESS (validate_payload reporting an invalid payload is the tool working,
// not failing). Accept either the inline literal or the helper form.
if (!block.includes('isError: true') && !block.includes('rejection(')) process.exit(1);
JS

# ── T-SO-S05: TASKS.md/REVIEWS.md protection ─────────────────────────────────
echo ""
echo "  [T-SO-S05] TASKS.md / REVIEWS.md protection"

assert_status 0 "TASKS.md starts with generated header" \
  node --input-type=module <<JS
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
const p = join('${REPO_ROOT}', '.ai', 'TASKS.md');
if (!existsSync(p)) process.exit(0); // skip if missing
const content = readFileSync(p, 'utf8');
if (!content.startsWith('# TASKS (Generated from state.json)')) {
  console.error('TASKS.md is missing generated header');
  process.exit(1);
}
JS

assert_status 0 "REVIEWS.md starts with generated header" \
  node --input-type=module <<JS
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
const p = join('${REPO_ROOT}', '.ai', 'REVIEWS.md');
if (!existsSync(p)) process.exit(0); // skip if missing
const content = readFileSync(p, 'utf8');
if (!content.startsWith('# REVIEWS.md (Generated from state.json)')) {
  console.error('REVIEWS.md is missing generated header');
  process.exit(1);
}
JS

assert_status 0 "append_tasks case disabled with isError" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// match either quote style
const idx = src.indexOf('case "append_tasks":') !== -1
  ? src.indexOf('case "append_tasks":')
  : src.indexOf("case 'append_tasks':");
if (idx === -1) process.exit(1);
const block = src.slice(idx, idx + 800);
if (!block.includes('isError: true')) process.exit(1);
JS

assert_status 0 "regenerateViews called after each mutation" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// Must regenerate after add_task, update_task_status, add_stamp, set_project_focus
const count = (src.match(/_regenerateViews/g) || []).length;
if (count < 4) { console.error('Expected >= 4 regenerateViews calls, got', count); process.exit(1); }
JS

# ── T-SO-S06: Registry updated ───────────────────────────────────────────────
echo ""
echo "  [T-SO-S06] Registry updated"

assert_status 0 "validate_payload in task-synchronizer-mcp allowed-tools" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['task-synchronizer-mcp']['allowed-tools'];
if (!tools.includes('validate_payload')) process.exit(1);
JS

assert_status 0 "mark_deltas_read in task-synchronizer-mcp allowed-tools" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['task-synchronizer-mcp']['allowed-tools'];
if (!tools.includes('mark_deltas_read')) process.exit(1);
JS

assert_summary
