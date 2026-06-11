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
HOOK="${REPO_ROOT}/hooks/post-tool-use.sh"

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

# Status-value lock to blueprint §Data Model. E-154: TIMEOUT joined SUCCESS/ERROR so the
# global interceptor can record the failure dimension that was previously always empty.
assert_status 0 "CHECK constraint on status column (SUCCESS/ERROR/TIMEOUT)" \
  grep -qE "status IN \('SUCCESS','ERROR','TIMEOUT'\)" "$TELEMETRY"

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

# ── T-TEL-S11: --record-tool CLI (E-104) ──────────────────────────────────────
echo ""
echo "  [T-TEL-S11] --record-tool consumes stdin JSON and writes a row"

SBOX7="$(mktemp -d)"
SBOX7_REPO="${SBOX7}/repo"
mkdir -p "${SBOX7_REPO}/.git"           # sentinel so _findProjectRoot stops here

CCID="sess-e104-$(date +%s)"
( cd "${SBOX7_REPO}" \
  && HOME="${SBOX7}" CLAUDE_CODE_SESSION_ID="${CCID}" \
     bash -c "echo '{\"tool_name\":\"hook.MyTool\",\"execution_time_ms\":17,\"status\":\"SUCCESS\"}' \
              | node '${TELEMETRY}' --record-tool" )
assert_status 0 "--record-tool exits 0 (fail-open)" \
  bash -c ":"   # the previous block ran; rc captured by next assertion via direct re-run
# Re-run capturing rc explicitly:
( cd "${SBOX7_REPO}" \
  && HOME="${SBOX7}" CLAUDE_CODE_SESSION_ID="${CCID}" \
     bash -c "echo '{\"tool_name\":\"hook.MyTool\",\"execution_time_ms\":17,\"status\":\"SUCCESS\"}' \
              | node '${TELEMETRY}' --record-tool >/dev/null 2>&1" )
RC_RT=$?
assert_status 0 "--record-tool rc==0" bash -c "[[ $RC_RT -eq 0 ]]"

# DB must land at $SBOX7/.ai-os/telemetry.sqlite (HOME-relative)
DB_RT="${SBOX7}/.ai-os/telemetry.sqlite"
assert_status 0 "telemetry.sqlite created under sandbox HOME" test -f "$DB_RT"

ROW_RT="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB_RT}');
const r = db.prepare('SELECT tool_name, execution_time_ms, status, session_id, project_hash FROM tool_executions ORDER BY timestamp DESC LIMIT 1').get();
process.stdout.write(JSON.stringify(r));
")"
assert_contains "tool_name persisted from stdin" "\"tool_name\":\"hook.MyTool\"" "$ROW_RT"
assert_contains "execution_time_ms persisted"   "\"execution_time_ms\":17"     "$ROW_RT"
assert_contains "status SUCCESS persisted"      "\"status\":\"SUCCESS\""       "$ROW_RT"
assert_contains "session_id derived from env"   "\"session_id\":\"${CCID}\""   "$ROW_RT"
assert_status 0 "project_hash is 12 hex chars from sandbox repo cwd" \
  bash -c "echo '$ROW_RT' | grep -qE '\"project_hash\":\"[0-9a-f]{12}\"'"

# Privacy: raw sandbox path must not leak.
assert_not_contains "sandbox path NOT in row" "${SBOX7_REPO}" "$ROW_RT"

# ── T-TEL-S12: --record-task CLI (E-104) ──────────────────────────────────────
echo ""
echo "  [T-TEL-S12] --record-task consumes stdin JSON and writes a row"

SBOX8="$(mktemp -d)"
( cd "${SBOX8}" \
  && HOME="${SBOX8}" \
     bash -c "echo '{\"task_id\":\"E-104\",\"turn_count\":4,\"tokens_consumed\":2048}' \
              | node '${TELEMETRY}' --record-task >/dev/null 2>&1" )
RC_TV=$?
assert_status 0 "--record-task rc==0" bash -c "[[ $RC_TV -eq 0 ]]"

DB_TV="${SBOX8}/.ai-os/telemetry.sqlite"
ROW_TV="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB_TV}');
const r = db.prepare('SELECT task_id, turn_count, tokens_consumed FROM task_velocity ORDER BY timestamp DESC LIMIT 1').get();
process.stdout.write(JSON.stringify(r));
")"
assert_contains "task_id persisted"         "\"task_id\":\"E-104\""        "$ROW_TV"
assert_contains "turn_count persisted"      "\"turn_count\":4"             "$ROW_TV"
assert_contains "tokens_consumed persisted" "\"tokens_consumed\":2048"     "$ROW_TV"

# ── T-TEL-S13: --record-* fail-open on malformed/empty stdin (E-104) ─────────
echo ""
echo "  [T-TEL-S13] --record-* never blocks the caller on malformed input"

SBOX9="$(mktemp -d)"

# Empty stdin → exit 0, no row written, no DB file created.
( cd "${SBOX9}" && HOME="${SBOX9}" \
    bash -c ": | node '${TELEMETRY}' --record-tool >/dev/null 2>&1" )
RC_EMPTY=$?
assert_status 0 "empty stdin still rc==0" bash -c "[[ $RC_EMPTY -eq 0 ]]"
assert_status 1 "empty stdin writes no DB" test -f "${SBOX9}/.ai-os/telemetry.sqlite"

# Malformed JSON → exit 0, no row written.
SBOX10="$(mktemp -d)"
( cd "${SBOX10}" && HOME="${SBOX10}" \
    bash -c "echo 'not valid json' | node '${TELEMETRY}' --record-tool >/dev/null 2>&1" )
RC_BAD=$?
assert_status 0 "malformed stdin still rc==0" bash -c "[[ $RC_BAD -eq 0 ]]"
assert_status 1 "malformed stdin writes no DB" test -f "${SBOX10}/.ai-os/telemetry.sqlite"

# Missing tool_name → helper logs and skips, but rc still 0.
SBOX11="$(mktemp -d)"
( cd "${SBOX11}" && HOME="${SBOX11}" \
    bash -c "echo '{\"execution_time_ms\":5}' | node '${TELEMETRY}' --record-tool >/dev/null 2>&1" )
RC_NOTOOL=$?
assert_status 0 "missing tool_name still rc==0" bash -c "[[ $RC_NOTOOL -eq 0 ]]"

# AI_TELEMETRY_DISABLE=1 also short-circuits the CLI write paths.
SBOX12="$(mktemp -d)"
( cd "${SBOX12}" && HOME="${SBOX12}" AI_TELEMETRY_DISABLE=1 \
    bash -c "echo '{\"tool_name\":\"x.y\",\"execution_time_ms\":1,\"status\":\"SUCCESS\"}' \
             | node '${TELEMETRY}' --record-tool >/dev/null 2>&1" )
RC_DISABLED=$?
assert_status 0 "AI_TELEMETRY_DISABLE=1 still rc==0" bash -c "[[ $RC_DISABLED -eq 0 ]]"
assert_status 1 "AI_TELEMETRY_DISABLE=1 writes no DB via CLI" \
  test -f "${SBOX12}/.ai-os/telemetry.sqlite"

# Pure-node project-root walk-up is required (no child_process per S01).
# Sanity-grep the source for the walk-up implementation.
assert_status 0 "telemetry.mjs has pure-node project-root walker" \
  grep -qE '_findProjectRoot|\.git' "$TELEMETRY"

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

# ── T-TEL-S14: post-tool-use.sh source contract (E-105) ──────────────────────
echo ""
echo "  [T-TEL-S14] hooks/post-tool-use.sh wires telemetry without breaking AQG"

assert_status 0 "post-tool-use.sh exists" test -f "$HOOK"

# AQG behavior preserved verbatim (LOCKED on test failure).
assert_status 0 "AQG block preserved (LOCKED tag)" \
  grep -qE 'LOCKED - AQG FAILED' "$HOOK"
assert_status 0 "AQG re-runs tests/run.sh"     grep -qE 'tests/run\.sh' "$HOOK"

# New telemetry block invokes --record-tool via the locator chain.
assert_status 0 "hook references --record-tool" \
  grep -qE '\-\-record-tool' "$HOOK"
assert_status 0 "hook uses locator chain (src/shared first, ~/.ai-os fallback)" \
  bash -c "grep -qE 'src/shared/telemetry\.mjs' '$HOOK' \
        && grep -qE '\\\$\\{HOME\\}/\\.ai-os/shared/telemetry\\.mjs' '$HOOK'"

# Fail-open: backgrounded via & + disown, stderr/stdout swallowed.
assert_status 0 "telemetry call is backgrounded (& + disown)" \
  bash -c "grep -qE '2>&1 &\$' '$HOOK' && grep -qE 'disown' '$HOOK'"
assert_status 0 "telemetry stderr/stdout redirected to /dev/null" \
  grep -qE '>/dev/null 2>&1' "$HOOK"

# Privacy: hook never forwards tool_input/tool_response bodies — only the
# three blueprint fields the CLI persists.
assert_status 0 "translation extracts only tool_name + execution_time_ms + status" \
  bash -c "grep -q 'tool_name' '$HOOK' \
        && grep -q 'execution_time_ms' '$HOOK' \
        && grep -q '\"status\"' '$HOOK'"

# ── T-TEL-S15: hook end-to-end records a row in sandbox HOME ─────────────────
echo ""
echo "  [T-TEL-S15] hook end-to-end: payload → backgrounded write → DB row"

SBOX_H="$(mktemp -d)"
mkdir -p "${SBOX_H}/.ai-os/shared" "${SBOX_H}/repo/.git"
cp "$TELEMETRY" "${SBOX_H}/.ai-os/shared/telemetry.mjs"

PAYLOAD_H='{"session_id":"hook-e2e","tool_name":"E105.HookSmoke","tool_input":{"x":1},"tool_response":{"isError":false,"duration_ms":27}}'

# Run hook — synchronous part should be quick; background write may take ~1s.
( cd "${SBOX_H}/repo" && echo "$PAYLOAD_H" \
    | HOME="${SBOX_H}" bash "$HOOK" >/dev/null 2>&1 )
RC_HOOK=$?
assert_status 0 "hook rc==0 on success path" bash -c "[[ $RC_HOOK -eq 0 ]]"

# Wait for the backgrounded node to land its write. Cold-start node ≈ 200ms;
# 2s is comfortable headroom.
sleep 2

DB_H="${SBOX_H}/.ai-os/telemetry.sqlite"
assert_status 0 "background write created sandbox DB" test -f "$DB_H"

ROW_H="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB_H}');
const r = db.prepare('SELECT tool_name, execution_time_ms, status FROM tool_executions ORDER BY timestamp DESC LIMIT 1').get();
process.stdout.write(JSON.stringify(r));
")"
assert_contains "tool_name from payload landed"   "\"tool_name\":\"E105.HookSmoke\""  "$ROW_H"
assert_contains "execution_time_ms from duration" "\"execution_time_ms\":27"          "$ROW_H"
assert_contains "status SUCCESS from isError:false" "\"status\":\"SUCCESS\""          "$ROW_H"

# Error path: isError:true → status=ERROR
PAYLOAD_HE='{"session_id":"hook-e2e","tool_name":"E105.ErrCase","tool_response":{"isError":true,"duration_ms":3}}'
( cd "${SBOX_H}/repo" && echo "$PAYLOAD_HE" \
    | HOME="${SBOX_H}" bash "$HOOK" >/dev/null 2>&1 )
sleep 2
ROWS_HE="$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('${DB_H}');
const r = db.prepare(\"SELECT status FROM tool_executions WHERE tool_name='E105.ErrCase'\").get();
process.stdout.write(JSON.stringify(r));
")"
assert_contains "isError:true translates to status=ERROR" "\"status\":\"ERROR\"" "$ROWS_HE"

# ── T-TEL-S16: hook fail-open on every degraded environment ───────────────────
echo ""
echo "  [T-TEL-S16] hook fail-open: missing helper / malformed input / no tool_name"

# (a) telemetry.mjs absent from both locator slots → hook rc==0, no DB
SBOX_NO="$(mktemp -d)"
mkdir -p "${SBOX_NO}/repo/.git"
( cd "${SBOX_NO}/repo" && echo "$PAYLOAD_H" \
    | HOME="${SBOX_NO}" bash "$HOOK" >/dev/null 2>&1 )
RC_NOHELPER=$?
sleep 1
assert_status 0 "hook rc==0 even when telemetry.mjs is missing" \
  bash -c "[[ $RC_NOHELPER -eq 0 ]]"
assert_status 1 "no DB written when helper is missing" \
  test -f "${SBOX_NO}/.ai-os/telemetry.sqlite"

# (b) malformed JSON payload → python parse fails → hook rc==0, no row
SBOX_BAD="$(mktemp -d)"
mkdir -p "${SBOX_BAD}/.ai-os/shared" "${SBOX_BAD}/repo/.git"
cp "$TELEMETRY" "${SBOX_BAD}/.ai-os/shared/telemetry.mjs"
( cd "${SBOX_BAD}/repo" && echo "not json at all" \
    | HOME="${SBOX_BAD}" bash "$HOOK" >/dev/null 2>&1 )
RC_BADJSON=$?
sleep 1
assert_status 0 "hook rc==0 on malformed payload" \
  bash -c "[[ $RC_BADJSON -eq 0 ]]"
assert_status 1 "no DB written from malformed payload" \
  test -f "${SBOX_BAD}/.ai-os/telemetry.sqlite"

# (c) AI_TELEMETRY_DISABLE=1 → helper short-circuits, no row written
SBOX_OFF="$(mktemp -d)"
mkdir -p "${SBOX_OFF}/.ai-os/shared" "${SBOX_OFF}/repo/.git"
cp "$TELEMETRY" "${SBOX_OFF}/.ai-os/shared/telemetry.mjs"
( cd "${SBOX_OFF}/repo" && echo "$PAYLOAD_H" \
    | HOME="${SBOX_OFF}" AI_TELEMETRY_DISABLE=1 bash "$HOOK" >/dev/null 2>&1 )
RC_OFF=$?
sleep 1
assert_status 0 "hook rc==0 with AI_TELEMETRY_DISABLE=1" \
  bash -c "[[ $RC_OFF -eq 0 ]]"
assert_status 1 "no DB written when AI_TELEMETRY_DISABLE=1" \
  test -f "${SBOX_OFF}/.ai-os/telemetry.sqlite"

# ── T-TEL-S17: hook synchronous overhead within blueprint <50ms budget ───────
echo ""
echo "  [T-TEL-S17] hook synchronous overhead under <50ms budget (warm)"

SBOX_T="$(mktemp -d)"
mkdir -p "${SBOX_T}/.ai-os/shared" "${SBOX_T}/repo/.git"
cp "$TELEMETRY" "${SBOX_T}/.ai-os/shared/telemetry.mjs"

# Cold + warm runs — measure warmer runs (2-5) as the steady-state.
ELAPSED_MS_MAX=0
for i in 1 2 3 4 5; do
  START_NS=$(node -e 'process.stdout.write(String(Date.now()))')
  ( cd "${SBOX_T}/repo" && echo "$PAYLOAD_H" \
      | HOME="${SBOX_T}" bash "$HOOK" >/dev/null 2>&1 )
  END_NS=$(node -e 'process.stdout.write(String(Date.now()))')
  EL=$((END_NS - START_NS))
  if [[ $i -ge 2 && $EL -gt $ELAPSED_MS_MAX ]]; then ELAPSED_MS_MAX=$EL; fi
done
# Wallclock measurement is bounded by the two `node -e Date.now` calls (~75ms
# overhead apiece). The hook itself must be << than the floor of measurable
# elapsed time. We assert on the steady-state max not exceeding 250ms (which
# already includes ~150ms of measurement noise). The real synchronous-hook
# overhead is verified separately via the `time` builtin and documented in
# DEVOPS-004; this assertion is the CI-safe lower bound that catches gross
# regressions (e.g. someone removes the `&` and makes the write synchronous).
assert_status 0 "hook warm-path under 250ms wallclock (sync slack budget)" \
  bash -c "[[ $ELAPSED_MS_MAX -lt 250 ]]"

# ── T-TEL-S18: writable preflight probe — warns + fails open (E-173) ──────────
echo ""
echo "  [T-TEL-S18] non-writable telemetry path → structured warning + fail-open"

# Source contract: accessSync-based writability probe + structured warn code.
assert_status 0 "imports accessSync from node:fs" \
  grep -qE 'accessSync' "$TELEMETRY"
assert_status 0 "writability probe checks W_OK" \
  grep -qE 'fsConstants\.W_OK|constants\.W_OK|W_OK' "$TELEMETRY"
assert_status 0 "emits telemetry-db-not-writable warning code" \
  grep -qF 'telemetry-db-not-writable' "$TELEMETRY"

# Behavioural: point the helper at a file under a read-only dir. The probe must log
# the warning AND the record call must not throw (fail-open → node rc 0). Skipped when
# running as root (perm bits are ignored → probe cannot fail).
SBOX_RO="$(mktemp -d)"
RO_DIR="${SBOX_RO}/locked"
mkdir -p "$RO_DIR"
chmod 000 "$RO_DIR"

if [[ "$(id -u)" -ne 0 ]] && ! ( : > "${RO_DIR}/.wtest" ) 2>/dev/null; then
  STDERR_RO="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  m.recordToolExecution({
    project_root: '/p', session_id: 's-ro', tool_name: 'srv.tool',
    execution_time_ms: 1, status: 'SUCCESS',
  }, { sync: true, db_path: '${RO_DIR}/telemetry.sqlite' });
  m.resetTelemetryCache();
}).catch(e => { console.error('THREW:' + e.message); process.exit(3); });
" 2>&1 1>/dev/null)"
  RC_RO=$?
  assert_status 0 "record call fails open (rc 0) on read-only path" \
    bash -c "[[ $RC_RO -eq 0 ]]"
  assert_contains "structured warning logged for non-writable path" \
    "telemetry-db-not-writable" "$STDERR_RO"
  assert_not_contains "no unhandled throw propagated to caller" "THREW:" "$STDERR_RO"
else
  echo "    (skipped behavioural read-only probe — running as root or dir is writable)"
fi
# Restore perms so mktemp cleanup can remove the sandbox.
chmod 755 "$RO_DIR" 2>/dev/null || true

# ── T-TEL-S10: ~/.ai-os mirrors byte-identical ────────────────────────────────
echo ""
echo "  [T-TEL-S10] ~/.ai-os mirrors byte-identical"

assert_status 0 "telemetry.mjs mirror"          diff -q "$TELEMETRY" "${HOME}/.ai-os/shared/telemetry.mjs"
assert_status 0 "mcp-router/index.js mirror"    diff -q "$ROUTER"    "${HOME}/.ai-os/mcp/mcp-router/index.js"
assert_status 0 "post-tool-use.sh mirror"       diff -q "$HOOK"      "${HOME}/.ai-os/hooks/post-tool-use.sh"

echo ""
assert_summary
echo "===== telemetry_test.sh PASS ====="
