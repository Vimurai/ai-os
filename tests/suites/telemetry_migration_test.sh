#!/usr/bin/env bash
# telemetry_migration_test.sh — E-154 (telemetry-hardening.md): behavioral coverage for the
# TIMEOUT schema migration in src/shared/telemetry.mjs _openDb() (Tier-3 review P2: the
# migration was a static-grep-only path over data-bearing SQLite).
#
# Covers: (1) old 2-value-CHECK DB migrates → rows preserved + TIMEOUT insertable;
#         (2) idempotency across re-open (no _tool_executions_old residue);
#         (3) orphan recovery — a _tool_executions_old stranded by a crash is merged back
#             (the P1 silent-data-loss path), with unknown statuses coerced to ERROR.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: telemetry_migration_test (E-154) ─────────────────────────"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OLD_SCHEMA="id TEXT PRIMARY KEY, project_hash TEXT NOT NULL, session_id TEXT NOT NULL, tool_name TEXT NOT NULL, execution_time_ms INTEGER NOT NULL CHECK(execution_time_ms >= 0), status TEXT NOT NULL CHECK(status IN ('SUCCESS','ERROR')), timestamp TEXT NOT NULL"

OUT="$(TELE_URL="file://${REPO_ROOT}/src/shared/telemetry.mjs" DB1="${TMP}/migrate.sqlite" DB2="${TMP}/orphan.sqlite" OLD_SCHEMA="$OLD_SCHEMA" node --input-type=module <<'NODE'
import { DatabaseSync } from "node:sqlite";
const { recordToolExecution, resetTelemetryCache } = await import(process.env.TELE_URL);
const DB1 = process.env.DB1, DB2 = process.env.DB2, OLD = process.env.OLD_SCHEMA;
const rows = (p) => { const d = new DatabaseSync(p); const r = d.prepare("SELECT id,status,tool_name FROM tool_executions ORDER BY timestamp").all(); const orphan = d.prepare("SELECT count(*) c FROM sqlite_master WHERE name='_tool_executions_old'").get().c; const ddl = d.prepare("SELECT sql FROM sqlite_master WHERE name='tool_executions'").get().sql; d.close(); return { r, orphan, ddl }; };

// ── Scenario 1+2: standard migration + idempotency ──
let s = new DatabaseSync(DB1);
s.exec(`CREATE TABLE tool_executions (${OLD});`);
s.prepare("INSERT INTO tool_executions VALUES (?,?,?,?,?,?,?)").run("a","h","s","Bash",5,"SUCCESS","2026-01-01T00:00:00Z");
s.prepare("INSERT INTO tool_executions VALUES (?,?,?,?,?,?,?)").run("b","h","s","Read",3,"ERROR","2026-01-02T00:00:00Z");
s.close();
resetTelemetryCache();
recordToolExecution({ tool_name:"mcp__x-mcp__y", execution_time_ms:1, status:"TIMEOUT" }, { db_path:DB1, sync:true });
let a = rows(DB1);
console.log("mig_ddl_timeout=" + a.ddl.includes("TIMEOUT"));
console.log("mig_old_preserved=" + (a.r.some(x=>x.id==="a"&&x.status==="SUCCESS") && a.r.some(x=>x.id==="b"&&x.status==="ERROR")));
console.log("mig_timeout_inserted=" + a.r.some(x=>x.status==="TIMEOUT"));
console.log("mig_no_orphan=" + (a.orphan===0));
console.log("mig_total=" + a.r.length);
// idempotent re-open
resetTelemetryCache();
recordToolExecution({ tool_name:"mcp__x-mcp__z", execution_time_ms:1, status:"ERROR" }, { db_path:DB1, sync:true });
let b = rows(DB1);
console.log("idem_no_orphan=" + (b.orphan===0));
console.log("idem_total=" + b.r.length);
console.log("idem_old_still_there=" + b.r.some(x=>x.id==="a"));

// ── Scenario 3: orphan recovery (crash left _tool_executions_old; live table empty/new) ──
let o = new DatabaseSync(DB2);
o.exec(`CREATE TABLE _tool_executions_old (${OLD});`);
o.prepare("INSERT INTO _tool_executions_old VALUES (?,?,?,?,?,?,?)").run("orphan1","h","s","Bash",5,"SUCCESS","2026-01-01T00:00:00Z");
o.prepare("INSERT INTO _tool_executions_old VALUES (?,?,?,?,?,?,?)").run("orphan2","h","s","Edit",2,"ERROR","2026-01-02T00:00:00Z");
o.close();
resetTelemetryCache();
recordToolExecution({ tool_name:"mcp__x-mcp__new", execution_time_ms:1, status:"SUCCESS" }, { db_path:DB2, sync:true });
let c = rows(DB2);
console.log("orphan_recovered=" + (c.r.some(x=>x.id==="orphan1") && c.r.some(x=>x.id==="orphan2")));
console.log("orphan_cleaned=" + (c.orphan===0));
console.log("orphan_newrow=" + c.r.some(x=>x.tool_name==="mcp__x-mcp__new"));
NODE
)"

echo "$OUT"
echo "── assertions ──"
assert_contains "154.M01: migrated DDL accepts TIMEOUT"        "mig_ddl_timeout=true"      "$OUT"
assert_contains "154.M02: pre-existing rows preserved"         "mig_old_preserved=true"    "$OUT"
assert_contains "154.M03: TIMEOUT row now insertable"          "mig_timeout_inserted=true" "$OUT"
assert_contains "154.M04: no _tool_executions_old residue"     "mig_no_orphan=true"        "$OUT"
assert_contains "154.M05: row count after migrate (2 old + 1 new)" "mig_total=3"           "$OUT"
assert_contains "154.M06: re-open is idempotent (no orphan)"   "idem_no_orphan=true"       "$OUT"
assert_contains "154.M07: re-open preserves rows"              "idem_old_still_there=true" "$OUT"
assert_contains "154.M08: orphan rows recovered (no data loss)" "orphan_recovered=true"    "$OUT"
assert_contains "154.M09: orphan table cleaned up"             "orphan_cleaned=true"       "$OUT"
assert_contains "154.M10: new row co-exists with recovered"    "orphan_newrow=true"        "$OUT"

assert_summary
