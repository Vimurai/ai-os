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
# E-180: the 3-value CHECK that shipped with E-154 (TIMEOUT but no REJECTED) — the intermediate
# schema a real DB carries between the two migrations. Must migrate forward to accept REJECTED.
MID_SCHEMA="id TEXT PRIMARY KEY, project_hash TEXT NOT NULL, session_id TEXT NOT NULL, tool_name TEXT NOT NULL, execution_time_ms INTEGER NOT NULL CHECK(execution_time_ms >= 0), status TEXT NOT NULL CHECK(status IN ('SUCCESS','ERROR','TIMEOUT')), timestamp TEXT NOT NULL"

OUT="$(TELE_URL="file://${REPO_ROOT}/src/shared/telemetry.mjs" DB1="${TMP}/migrate.sqlite" DB2="${TMP}/orphan.sqlite" DB3="${TMP}/rejected.sqlite" DB4="${TMP}/orphan_stale.sqlite" OLD_SCHEMA="$OLD_SCHEMA" MID_SCHEMA="$MID_SCHEMA" node --input-type=module <<'NODE'
import { DatabaseSync } from "node:sqlite";
const { recordToolExecution, resetTelemetryCache } = await import(process.env.TELE_URL);
const DB1 = process.env.DB1, DB2 = process.env.DB2, DB3 = process.env.DB3, DB4 = process.env.DB4, OLD = process.env.OLD_SCHEMA, MID = process.env.MID_SCHEMA;
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
console.log("mig_ddl_rejected=" + a.ddl.includes("REJECTED")); // E-180: 2-value DB jumps to 4-value
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

// ── Scenario 4 (E-180): 3-value (TIMEOUT) DB migrates forward → REJECTED-capable, rows preserved ──
let m = new DatabaseSync(DB3);
m.exec(`CREATE TABLE tool_executions (${MID});`);
m.prepare("INSERT INTO tool_executions VALUES (?,?,?,?,?,?,?)").run("m1","h","s","Bash",5,"SUCCESS","2026-01-01T00:00:00Z");
m.prepare("INSERT INTO tool_executions VALUES (?,?,?,?,?,?,?)").run("m2","h","s","Grep",4,"TIMEOUT","2026-01-02T00:00:00Z");
m.close();
resetTelemetryCache();
recordToolExecution({ tool_name:"mcp__x-mcp__rej", execution_time_ms:1, status:"REJECTED" }, { db_path:DB3, sync:true });
let d = rows(DB3);
console.log("rej_mig_ddl=" + d.ddl.includes("REJECTED"));
console.log("rej_mig_old_preserved=" + (d.r.some(x=>x.id==="m1"&&x.status==="SUCCESS") && d.r.some(x=>x.id==="m2"&&x.status==="TIMEOUT")));
console.log("rej_mig_inserted=" + d.r.some(x=>x.status==="REJECTED"));
console.log("rej_mig_no_orphan=" + (d.orphan===0));
console.log("rej_mig_total=" + d.r.length);

// ── Scenario 5 (E-180 db_architect P1): orphan AND a stale-CHECK live table coexist. The merge
//    must NOT short-circuit the CHECK rebuild — a REJECTED insert must succeed and the live DDL
//    must end up 4-value. Under the old `if (orphan) {merge} else {migrate}` this dropped the
//    REJECTED row and left a 3-value CHECK until the next open self-healed. ──
let p = new DatabaseSync(DB4);
p.exec(`CREATE TABLE tool_executions (${MID});`);            // stale 3-value live table
p.prepare("INSERT INTO tool_executions VALUES (?,?,?,?,?,?,?)").run("live1","h","s","Bash",5,"SUCCESS","2026-01-01T00:00:00Z");
p.exec(`CREATE TABLE _tool_executions_old (${MID});`);       // stranded orphan from a prior crash
p.prepare("INSERT INTO _tool_executions_old VALUES (?,?,?,?,?,?,?)").run("strand1","h","s","Edit",2,"TIMEOUT","2026-01-02T00:00:00Z");
p.close();
resetTelemetryCache();
recordToolExecution({ tool_name:"mcp__x-mcp__rej2", execution_time_ms:1, status:"REJECTED" }, { db_path:DB4, sync:true });
let e = rows(DB4);
console.log("p1_ddl_rejected=" + e.ddl.includes("REJECTED"));                            // CHECK refreshed despite orphan
console.log("p1_rejected_inserted=" + e.r.some(x=>x.status==="REJECTED"));               // the bug dropped this row
console.log("p1_live_preserved=" + e.r.some(x=>x.id==="live1"&&x.status==="SUCCESS"));
console.log("p1_orphan_recovered=" + e.r.some(x=>x.id==="strand1"&&x.status==="TIMEOUT"));
console.log("p1_no_orphan=" + (e.orphan===0));
console.log("p1_total=" + e.r.length);                                                   // live1 + strand1 + rej2 = 3
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
# ── E-180: REJECTED enum migration (2-value jumps to 4-value; 3-value migrates forward) ──
assert_contains "180.M11: 2-value DB migrates straight to REJECTED-capable" "mig_ddl_rejected=true"     "$OUT"
assert_contains "180.M12: 3-value (TIMEOUT) DDL migrates to accept REJECTED" "rej_mig_ddl=true"         "$OUT"
assert_contains "180.M13: rows preserved across +REJECTED migration"        "rej_mig_old_preserved=true" "$OUT"
assert_contains "180.M14: REJECTED row now insertable"                      "rej_mig_inserted=true"     "$OUT"
assert_contains "180.M15: no _tool_executions_old residue after +REJECTED"  "rej_mig_no_orphan=true"    "$OUT"
assert_contains "180.M16: row count after +REJECTED migrate (2 old + 1 new)" "rej_mig_total=3"          "$OUT"
# ── E-180 db_architect P1: orphan + stale-CHECK live must BOTH merge AND rebuild (no dropped row) ──
assert_contains "180.M17: orphan+stale-live still refreshes CHECK to 4-value" "p1_ddl_rejected=true"     "$OUT"
assert_contains "180.M18: REJECTED survives orphan+stale-live (P1 regression)" "p1_rejected_inserted=true" "$OUT"
assert_contains "180.M19: live rows preserved through merge+rebuild"          "p1_live_preserved=true"    "$OUT"
assert_contains "180.M20: orphan rows recovered through merge+rebuild"        "p1_orphan_recovered=true"  "$OUT"
assert_contains "180.M21: no _tool_executions_old residue (P1 path)"          "p1_no_orphan=true"         "$OUT"
assert_contains "180.M22: row count (live + orphan + new = 3)"               "p1_total=3"                "$OUT"

assert_summary
