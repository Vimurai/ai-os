#!/usr/bin/env bash
# telemetry_dedup_test.sh — E-106 (universal-telemetry.md): routed-call dedup.
# The mcp-router writes a GRANULAR `<server>.<tool>` row per proxy_call; the edge
# hook ALSO writes the COARSE `mcp__mcp-router__proxy_call` wrapper for the same
# call. recordToolExecution drops the coarse duplicate so routed calls are
# counted once. Other mcp-router tools (activate_domain) have no granular twin
# and are kept. AI_OS_TELEMETRY_NO_DEDUP=1 keeps both (rollback).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TELEMETRY="${REPO_ROOT}/src/shared/telemetry.mjs"

echo "===== telemetry_dedup_test.sh (E-106) ====="

unset AI_TELEMETRY_DISABLE AI_OS_TELEMETRY_NO_DEDUP 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# names() — record 3 tool calls into a fresh DB (sync), return the persisted
# tool_name list as JSON. $1 = db path, $2 = "dedup"|"nodedup".
record_and_dump() {
  local dbp="$1" mode="$2"
  local env_prefix=""
  [[ "$mode" == "nodedup" ]] && env_prefix="AI_OS_TELEMETRY_NO_DEDUP=1"
  env ${env_prefix} node --input-type=module -e "
    import * as m from 'file://${TELEMETRY}';
    const opts = { sync: true, db_path: '${dbp}' };
    m.recordToolExecution({ tool_name: 'mcp__mcp-router__proxy_call', status: 'SUCCESS', execution_time_ms: 5 }, opts);
    m.recordToolExecution({ tool_name: 'safe-exec-mcp.analyze_command', status: 'SUCCESS', execution_time_ms: 3 }, opts);
    m.recordToolExecution({ tool_name: 'mcp__mcp-router__activate_domain', status: 'SUCCESS', execution_time_ms: 2 }, opts);
    m.resetTelemetryCache && m.resetTelemetryCache();
  " 2>/dev/null
  node -e "
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync('${dbp}');
    process.stdout.write(JSON.stringify(db.prepare('SELECT tool_name FROM tool_executions ORDER BY id').all().map(r=>r.tool_name)));
  " 2>/dev/null
}

# ── S01: source contract — dedup guard present + rollback flag ───────────────
assert_status 0 "writer drops the proxy_call wrapper" \
  grep -qF 'mcp__mcp-router__proxy_call' "$TELEMETRY"
assert_status 0 "router instrumentation RETAINED (not removed)" \
  grep -qE 'export function recordToolExecution' "$TELEMETRY"
assert_status 0 "rollback flag AI_OS_TELEMETRY_NO_DEDUP honored" \
  grep -qF 'AI_OS_TELEMETRY_NO_DEDUP' "$TELEMETRY"

# ── S02: dedup ON — coarse proxy_call dropped, granular + others kept ────────
DUMP="$(record_and_dump "${TMP}/d1.sqlite" dedup)"
assert_not_contains "S02: coarse proxy_call wrapper dropped" "mcp__mcp-router__proxy_call" "$DUMP"
assert_contains     "S02: granular <server>.<tool> kept"     "safe-exec-mcp.analyze_command" "$DUMP"
assert_contains     "S02: non-proxy router tool kept"        "mcp__mcp-router__activate_domain" "$DUMP"
CNT="$(node -e "const{DatabaseSync}=require('node:sqlite');console.log(new DatabaseSync('${TMP}/d1.sqlite').prepare('SELECT COUNT(*) n FROM tool_executions').get().n)" 2>/dev/null)"
assert_status 0 "S02: exactly 2 rows persisted (3 recorded, 1 deduped)" bash -c "[ \"$CNT\" -eq 2 ]"

# ── S03: rollback — both rows kept when dedup disabled ───────────────────────
DUMP2="$(record_and_dump "${TMP}/d2.sqlite" nodedup)"
assert_contains "S03: NO_DEDUP=1 keeps the coarse proxy_call row" "mcp__mcp-router__proxy_call" "$DUMP2"
CNT2="$(node -e "const{DatabaseSync}=require('node:sqlite');console.log(new DatabaseSync('${TMP}/d2.sqlite').prepare('SELECT COUNT(*) n FROM tool_executions').get().n)" 2>/dev/null)"
assert_status 0 "S03: all 3 rows kept under rollback" bash -c "[ \"$CNT2\" -eq 3 ]"

assert_summary
