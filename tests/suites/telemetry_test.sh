#!/usr/bin/env bash
# telemetry_test.sh — Tests for E-84 src/shared/telemetry.mjs and the
# mcp-router proxy_call write hook. Verifies the contract demanded by
# .ai/blueprints/meta-cognition.md §Components 1 + §Data Model + §Security.
#
#   • Two-table SQLite schema is bootstrapped idempotently on first write.
#   • recordToolExecution + recordTaskVelocity write the expected columns.
#   • Privacy: project_root is hashed (sha256, 12 hex chars). Raw HOME path
#     and absolute slash-prefixed paths must NEVER appear in DB rows.
#   • Session-id sanitiser rejects non-conforming input → "unknown".
#   • AI_TELEMETRY_DISABLE=1 short-circuits writes (rollback flag).
#   • Fire-and-forget: setImmediate is used so the call returns before the
#     write hits disk; bypassed by the {sync:true} test hook.
#   • getTelemetryStats() returns OK / EMPTY envelopes with counts + last_ts.
#   • mcp-router/index.js imports telemetry.mjs AND calls recordToolExecution
#     on both success and error paths of proxy_call.
#   • ~/.ai-os mirrors are byte-identical.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TELEMETRY="${REPO_ROOT}/src/shared/telemetry.mjs"
ROUTER="${REPO_ROOT}/src/mcp/mcp-router/index.js"

echo "===== telemetry_test.sh ====="

# ── T-TEL-S01: source contract ────────────────────────────────────────────────
echo ""
echo "  [T-TEL-S01] telemetry.mjs source contract"

assert_status 0 "telemetry.mjs exists" test -f "$TELEMETRY"

assert_status 0 "uses node:sqlite (DatabaseSync)" \
  grep -qE 'from "node:sqlite"' "$TELEMETRY"

assert_status 0 "uses createHash from node:crypto for project_hash" \
  grep -qE 'createHash, randomUUID' "$TELEMETRY"

assert_status 0 "exports recordToolExecution" \
  grep -qE 'export function recordToolExecution' "$TELEMETRY"

assert_status 0 "exports recordTaskVelocity" \
  grep -qE 'export function recordTaskVelocity' "$TELEMETRY"

assert_status 0 "exports getTelemetryStats" \
  grep -qE 'export function getTelemetryStats' "$TELEMETRY"

assert_status 0 "TELEMETRY_DB_PATH constant published" \
  grep -qE 'export const TELEMETRY_DB_PATH' "$TELEMETRY"

# Fire-and-forget uses setImmediate per blueprint §Performance.
assert_status 0 "fire-and-forget via setImmediate" \
  grep -qE 'setImmediate\(' "$TELEMETRY"

# Status-value lock to blueprint §Data Model.
assert_status 0 "CHECK constraint on status column" \
  grep -qE "status IN \('SUCCESS','ERROR'\)" "$TELEMETRY"

# Two-table schema per blueprint §Data Model.
assert_status 0 "tool_executions table" \
  grep -qE 'CREATE TABLE IF NOT EXISTS tool_executions' "$TELEMETRY"

assert_status 0 "task_velocity table" \
  grep -qE 'CREATE TABLE IF NOT EXISTS task_velocity' "$TELEMETRY"

# No shell out — pure node.
assert_status 1 "no child_process / spawn / exec" \
  grep -qE 'child_process|spawnSync|spawn\(|execSync' "$TELEMETRY"

# AI_TELEMETRY_DISABLE escape hatch per blueprint §Rollback.
assert_status 0 "AI_TELEMETRY_DISABLE env flag recognised" \
  grep -qE 'AI_TELEMETRY_DISABLE' "$TELEMETRY"

# ── T-TEL-S02: behavioural — schema bootstrap + happy path ────────────────────
echo ""
echo "  [T-TEL-S02] behavioural: schema bootstrap + writes both tables"

SBOX="$(mktemp -d)"
DBPATH="${SBOX}/telemetry.sqlite"

node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/Users/example/project',
    session_id: 'abc-123-XYZ',
    tool_name: 'task-synchronizer-mcp.add_task',
    execution_time_ms: 42,
    status: 'SUCCESS',
  }, { sync: true, db_path: '${DBPATH}' });
  m.recordTaskVelocity({
    task_id: 'E-84',
    turn_count: 3,
    tokens_consumed: 1500,
  }, { sync: true, db_path: '${DBPATH}' });
  m.resetTelemetryCache();
}).catch(e => { console.error(e); process.exit(1); });
"

assert_status 0 "DB file created on first write" test -f "$DBPATH"

# Inspect via node:sqlite (sqlite3 binary not assumed on CI).
ROWS_TE="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DBPATH}');
const rows = db.prepare('SELECT project_hash, session_id, tool_name, execution_time_ms, status FROM tool_executions').all();
process.stdout.write(JSON.stringify(rows));
")"

assert_contains "tool_executions row written" "task-synchronizer-mcp.add_task" "$ROWS_TE"
assert_contains "session_id sanitised + persisted" "abc-123-XYZ" "$ROWS_TE"
assert_contains "status=SUCCESS persisted" "SUCCESS" "$ROWS_TE"
assert_contains "execution_time_ms persisted" "\"execution_time_ms\":42" "$ROWS_TE"

# Privacy guarantee: raw project_root must NOT appear anywhere.
assert_not_contains "raw absolute path not leaked" "/Users/example/project" "$ROWS_TE"
assert_not_contains "raw 'project' token not leaked" "/Users/example" "$ROWS_TE"

# project_hash is 12 hex chars derived from sha256.
assert_status 0 "project_hash is 12 hex chars" \
  bash -c "echo '$ROWS_TE' | grep -qE '\"project_hash\":\"[0-9a-f]{12}\"'"

ROWS_TV="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DBPATH}');
const rows = db.prepare('SELECT task_id, turn_count, tokens_consumed FROM task_velocity').all();
process.stdout.write(JSON.stringify(rows));
")"

assert_contains "task_velocity row written" "E-84" "$ROWS_TV"
assert_contains "turn_count persisted" "\"turn_count\":3" "$ROWS_TV"
assert_contains "tokens_consumed persisted" "\"tokens_consumed\":1500" "$ROWS_TV"

# ── T-TEL-S03: session_id sanitiser ───────────────────────────────────────────
echo ""
echo "  [T-TEL-S03] session_id sanitiser rejects malformed → 'unknown'"

SBOX2="$(mktemp -d)"
DB2="${SBOX2}/t.sqlite"

node -e "
import('${TELEMETRY}').then(async (m) => {
  // Each malformed session_id should fall back to 'unknown'.
  const inputs = ['', '  ', 'spaces in id', 'has;semi', 'with\nnewline', 'a'.repeat(65)];
  for (const sid of inputs) {
    m.recordToolExecution({
      project_root: '/p',
      session_id: sid,
      tool_name: 'srv.tool',
      execution_time_ms: 1,
      status: 'SUCCESS',
    }, { sync: true, db_path: '${DB2}' });
  }
  m.resetTelemetryCache();
});
"

DISTINCT_SIDS="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB2}');
const rows = db.prepare('SELECT DISTINCT session_id FROM tool_executions').all();
process.stdout.write(JSON.stringify(rows));
")"

assert_contains "all malformed inputs collapse to 'unknown'" "unknown" "$DISTINCT_SIDS"
# Exactly one row distinct: the unknown bucket.
assert_status 0 "no malformed session_id leaked verbatim" \
  bash -c "echo '$DISTINCT_SIDS' | grep -qE '^\[\{\"session_id\":\"unknown\"\}\]$'"

# ── T-TEL-S04: status enum constrained ────────────────────────────────────────
echo ""
echo "  [T-TEL-S04] status enum constrained — invalid → SUCCESS default"

SBOX3="$(mktemp -d)"
DB3="${SBOX3}/t.sqlite"

node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/p',
    session_id: 'sid-1',
    tool_name: 'srv.tool',
    execution_time_ms: 1,
    status: 'WAT',
  }, { sync: true, db_path: '${DB3}' });
  m.resetTelemetryCache();
});
"

STATUS_OUT="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB3}');
const r = db.prepare('SELECT status FROM tool_executions').get();
process.stdout.write(r.status);
")"

assert_contains "invalid status falls back to SUCCESS" "SUCCESS" "$STATUS_OUT"

# ── T-TEL-S05: AI_TELEMETRY_DISABLE=1 rollback flag ───────────────────────────
echo ""
echo "  [T-TEL-S05] AI_TELEMETRY_DISABLE=1 short-circuits — no DB created"

SBOX4="$(mktemp -d)"
DB4="${SBOX4}/t.sqlite"

AI_TELEMETRY_DISABLE=1 node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/p',
    session_id: 's',
    tool_name: 't.t',
    execution_time_ms: 0,
    status: 'SUCCESS',
  }, { sync: true, db_path: '${DB4}' });
});
"

assert_status 1 "DB file NOT created when telemetry disabled" test -f "$DB4"

# ── T-TEL-S06: getTelemetryStats — EMPTY + OK envelopes ───────────────────────
echo ""
echo "  [T-TEL-S06] getTelemetryStats returns blueprint envelope"

SBOX5="$(mktemp -d)"
DB5="${SBOX5}/t.sqlite"

STATS_EMPTY="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  const s = m.getTelemetryStats({ db_path: '${DB5}' });
  process.stdout.write(JSON.stringify(s));
});
")"

assert_contains "EMPTY status when DB absent" "\"status\":\"EMPTY\"" "$STATS_EMPTY"
assert_contains "EMPTY tool_executions.count = 0" "\"tool_executions\":{\"count\":0" "$STATS_EMPTY"

# Now write one row then re-stat.
node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/p',
    session_id: 's-1',
    tool_name: 'srv.tool',
    execution_time_ms: 1,
    status: 'SUCCESS',
  }, { sync: true, db_path: '${DB5}' });
  m.resetTelemetryCache();
});
"

STATS_OK="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  const s = m.getTelemetryStats({ db_path: '${DB5}' });
  process.stdout.write(JSON.stringify(s));
  m.resetTelemetryCache();
});
")"

assert_contains "OK status when DB populated" "\"status\":\"OK\"" "$STATS_OK"
assert_contains "tool_executions.count = 1" "\"tool_executions\":{\"count\":1" "$STATS_OK"

# ── T-TEL-S07: fire-and-forget — default path uses setImmediate ───────────────
echo ""
echo "  [T-TEL-S07] default (non-sync) path defers write until next tick"

SBOX6="$(mktemp -d)"
DB6="${SBOX6}/t.sqlite"

# Without {sync:true} the row should NOT be visible synchronously. Then once
# we await a setImmediate-driven turn, it shows up. node:sqlite is sync, so
# we can race the read against the deferred write deterministically.
RACE_OUT="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/p',
    session_id: 's-immediate',
    tool_name: 'srv.tool',
    execution_time_ms: 1,
    status: 'SUCCESS',
  }, { db_path: '${DB6}' });
  // File may not exist yet — non-sync defers the open + write.
  const fs = await import('node:fs');
  const beforeExists = fs.existsSync('${DB6}');
  await new Promise(r => setImmediate(r));
  await new Promise(r => setImmediate(r));
  const afterExists = fs.existsSync('${DB6}');
  process.stdout.write(JSON.stringify({ beforeExists, afterExists }));
  m.resetTelemetryCache();
});
")"

assert_contains "DB absent synchronously" "\"beforeExists\":false" "$RACE_OUT"
assert_contains "DB present after setImmediate tick" "\"afterExists\":true"  "$RACE_OUT"

# ── T-TEL-S08: CLI smoke — --stats + --path ───────────────────────────────────
echo ""
echo "  [T-TEL-S08] CLI smoke — --stats + --path"

# --path always prints the canonical telemetry path.
PATHOUT="$(node "$TELEMETRY" --path)"
assert_contains "--path includes .ai-os/telemetry.sqlite" ".ai-os/telemetry.sqlite" "$PATHOUT"

assert_status 0 "--stats exits 0" \
  bash -c "node '$TELEMETRY' --stats >/dev/null"

assert_status 2 "missing subcommand exits 2" \
  bash -c "node '$TELEMETRY' >/dev/null 2>&1"

# ── T-TEL-S09: mcp-router wiring ──────────────────────────────────────────────
echo ""
echo "  [T-TEL-S09] mcp-router/index.js imports + invokes telemetry"

assert_status 0 "router imports recordToolExecution" \
  grep -qE 'import .* recordToolExecution .* from .*telemetry\.mjs' "$ROUTER"

assert_status 0 "router declares _proxyTelemetryCtx scope variable" \
  grep -qE 'let _proxyTelemetryCtx' "$ROUTER"

# Call site count: once on success, once on the outer catch ERROR path = 2.
RTE_COUNT="$(grep -cE 'recordToolExecution\(' "$ROUTER")"
assert_status 0 "router invokes recordToolExecution exactly 2x (success+error)" \
  bash -c "[[ $RTE_COUNT -eq 2 ]]"

assert_status 0 "success-path records status=SUCCESS" \
  grep -qE "status: \"SUCCESS\"" "$ROUTER"

assert_status 0 "error-path records status=ERROR" \
  grep -qE "status: \"ERROR\"" "$ROUTER"

assert_status 0 "telemetry call uses CLAUDE_CODE_SESSION_ID (E-49 contract)" \
  grep -qE 'CLAUDE_CODE_SESSION_ID' "$ROUTER"

# ── T-TEL-S10: ~/.ai-os mirrors byte-identical ────────────────────────────────
echo ""
echo "  [T-TEL-S10] ~/.ai-os mirrors byte-identical"

assert_status 0 "telemetry.mjs mirror"          diff -q "$TELEMETRY" "${HOME}/.ai-os/shared/telemetry.mjs"
assert_status 0 "mcp-router/index.js mirror"    diff -q "$ROUTER"    "${HOME}/.ai-os/mcp/mcp-router/index.js"

echo ""
assert_summary
echo "===== telemetry_test.sh PASS ====="
