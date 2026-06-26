#!/usr/bin/env node
// E-84: telemetry.mjs — fire-and-forget writer for ~/.ai-os/telemetry.sqlite.
//
// Stateless helper that records anonymized tool-invocation metadata into the
// global telemetry database described in .ai/blueprints/meta-cognition.md
// §Components 1 + §Data Model + §Security. Used by the mcp-router proxy_call
// path (E-84 §API/Write) to capture { tool_name, execution_time_ms, status }
// without ever exposing project source, secrets, or absolute paths.
//
// Public API:
//   recordToolExecution({ project_root, session_id, tool_name,
//                         execution_time_ms, status })
//   recordTaskVelocity({ task_id, turn_count, tokens_consumed })
//   getTelemetryStats({ since_iso? })
//   resetTelemetryCache()   — test hook only; closes the cached handle.
//   TELEMETRY_DB_PATH       — absolute path constant.
//   TELEMETRY_SERVICE       — service tag for structured logs.
//
// Privacy contract (blueprint §Security):
//   - project_root is hashed (sha256, 12 hex chars) before insertion. The
//     raw path NEVER reaches the DB.
//   - tool_name is the canonical "<server>.<tool>" identifier — no args,
//     no payload bodies.
//   - session_id is sanitised by the same /^[A-Za-z0-9-]{1,64}$/ regex used
//     in approval-mcp (E-49 contract).
//   - Status is constrained to {"SUCCESS","ERROR","TIMEOUT","REJECTED"} (E-154/E-180).
//
// Failure mode:
//   - All write paths swallow exceptions (telemetry must NEVER break the
//     calling MCP). Errors emit a single NDJSON line to stderr and return.
//   - AI_TELEMETRY_DISABLE=1 short-circuits every write (rollback flag).
//
// Performance:
//   - DB handle cached at module scope. CREATE TABLE statements run once
//     on first use (IF NOT EXISTS, idempotent).
//   - Single INSERT per call. Budget: <5ms per call on warm cache.

import { DatabaseSync } from "node:sqlite";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, realpathSync, accessSync, constants as fsConstants } from "node:fs";
import { resolve, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

export const TELEMETRY_SERVICE = "telemetry";
export const TELEMETRY_DB_PATH = resolve(homedir(), ".ai-os", "telemetry.sqlite");
// E-155 (telemetry-hardening.md §Components 3): token-budget-mcp records per-call
// token usage here (report_cost → usage.sqlite). The task-velocity aggregator
// reads it READ-ONLY to sum tokens + turns for a task at completion.
export const USAGE_DB_PATH = resolve(homedir(), ".ai-os", "usage.sqlite");

const SESSION_ID_RE = /^[A-Za-z0-9-]{1,64}$/;
// ── Telemetry status enum — SINGLE DRY SOURCE OF TRUTH (E-185) ───────────────────────────────
// E-154 (telemetry-hardening.md §Data Model): the status enum explicitly captures SUCCESS,
// ERROR, and TIMEOUT so the global interceptor (E-153) can record an accurate failure dimension
// (the INSIGHTS report found it was previously 100% SUCCESS).
// E-180 (D-049, meta-cognition.md §Data Model): + REJECTED — an EXPECTED rejection (bad input /
// not-found / schema-fail) that E-179 had folded into SUCCESS. Booking it as a distinct status
// restores usage-friction visibility for the meta_analyst WITHOUT re-polluting the ERROR
// (broken-tool) dimension.
// E-185 (flaw-remediation): STATUS_ORDER is the ONLY place the enum is written. The membership
// Set, the SQL CHECK clause (shared verbatim by the CREATE TABLE, the migration rebuild, and the
// orphan-merge coercion), and the migration sentinel are all DERIVED below — so growing the enum
// is a one-line edit here and the previously-coupled sites can never desync. ORDER MATTERS:
// append new statuses to the END so STATUS_MIGRATION_SENTINEL tracks the newest token.
export const STATUS_ORDER = ["SUCCESS", "ERROR", "TIMEOUT", "REJECTED"];
// Membership test for the writer's input validation.
export const STATUS_VALUES = new Set(STATUS_ORDER);
// SQL predicate `status IN ('SUCCESS','ERROR','TIMEOUT','REJECTED')` — embedded verbatim in the
// CREATE TABLE CHECK, the migration-rebuild CHECK, and the orphan-merge CASE WHEN coercion.
export const STATUS_SQL_IN = `status IN (${STATUS_ORDER.map((s) => `'${s}'`).join(",")})`;
// Migration sentinel: the NEWEST token. A stored DDL lacking it predates the current enum and is
// rebuilt — so this one check covers every hop (a 2-value DB jumps straight to the full schema).
export const STATUS_MIGRATION_SENTINEL = STATUS_ORDER[STATUS_ORDER.length - 1];

let _cachedDb = null;
let _cachedPath = null;

function _isDisabled() {
  return process.env.AI_TELEMETRY_DISABLE === "1";
}

function _logErr(code, detail) {
  process.stderr.write(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "warn",
      service: TELEMETRY_SERVICE,
      code,
      detail,
    }) + "\n"
  );
}

function _hashProjectRoot(raw) {
  // Empty / non-string project_root → fixed "unknown" sentinel. We hash the
  // string regardless so the value space is uniform.
  const s = typeof raw === "string" && raw.length > 0 ? raw : "unknown";
  return createHash("sha256").update(s).digest("hex").slice(0, 12);
}

function _sanitiseSessionId(raw) {
  if (typeof raw !== "string") return "unknown";
  const trimmed = raw.trim();
  if (!trimmed) return "unknown";
  if (!SESSION_ID_RE.test(trimmed)) return "unknown";
  return trimmed;
}

function _ensureDir(path) {
  const dir = dirname(path);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
}

// E-173 (June 2026 audit follow-up): preflight writability probe for telemetry.sqlite.
// If ~/.ai-os/ (or an already-existing telemetry.sqlite) is not writable — read-only
// mount, hostile perms, full/locked volume — emit ONE structured warning instead of
// letting DatabaseSync surface an opaque error deep inside a record() call. FAIL-OPEN:
// telemetry is best-effort instrumentation, so a non-writable path must NEVER block the
// host agent; this only improves the diagnostic and returns a boolean for the caller.
function _checkWritable(targetPath) {
  try {
    // Probe the db file itself if it exists (need W_OK to write rows), otherwise the
    // parent dir (need W_OK to create the file). _ensureDir() already tried to mkdir it.
    const probe = existsSync(targetPath) ? targetPath : dirname(targetPath);
    accessSync(probe, fsConstants.W_OK);
    return true;
  } catch (e) {
    _logErr("telemetry-db-not-writable", `${targetPath}: ${e.code || e.message}`);
    return false;
  }
}

function _openDb(pathOverride) {
  // Path override exists so tests can point the helper at a sandbox file
  // without HOME hacks. Production callers leave pathOverride undefined
  // and the module-scope cache reuses one handle for the lifetime of the
  // process.
  const targetPath = pathOverride || TELEMETRY_DB_PATH;
  if (_cachedDb && _cachedPath === targetPath) {
    return _cachedDb;
  }
  if (_cachedDb && _cachedPath !== targetPath) {
    try { _cachedDb.close(); } catch { /* ignore */ }
    _cachedDb = null;
    _cachedPath = null;
  }
  // E-173: best-effort dir creation + writability preflight. Both are FAIL-OPEN — a
  // read-only/unwritable path logs a clear warning but does not throw here; the
  // DatabaseSync open below is already wrapped by every caller's try/catch.
  try { _ensureDir(targetPath); } catch (e) { _logErr("telemetry-dir-create-failed", e.message); }
  _checkWritable(targetPath);
  const db = new DatabaseSync(targetPath);
  // E-153/E-154 (Tier-3 review): WAL + busy_timeout (matching state-db.js) so the now-23
  // in-house MCP servers writing this single shared DB don't serialise on a global lock or
  // hit SQLITE_BUSY — which also de-risks the migration window below. NORMAL sync keeps the
  // off-hot-path deferred write cheap. Best-effort: a pragma failure must not break telemetry.
  try { db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 2000;"); } catch { /* pragma best-effort */ }
  // Per blueprint §Components 1 — two tables, idempotent CREATE.
  db.exec(`
    CREATE TABLE IF NOT EXISTS tool_executions (
      id TEXT PRIMARY KEY,
      project_hash TEXT NOT NULL,
      session_id TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      execution_time_ms INTEGER NOT NULL CHECK(execution_time_ms >= 0),
      status TEXT NOT NULL CHECK(${STATUS_SQL_IN}),
      timestamp TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS task_velocity (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      turn_count INTEGER NOT NULL CHECK(turn_count >= 0),
      tokens_consumed INTEGER NOT NULL CHECK(tokens_consumed >= 0),
      timestamp TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tool_executions_timestamp
      ON tool_executions(timestamp);
    CREATE INDEX IF NOT EXISTS idx_task_velocity_timestamp
      ON task_velocity(timestamp);
  `);
  // E-154/E-180 migration → newest-enum-capable schema. Existing DBs carry an older CHECK
  // (2-value SUCCESS/ERROR pre-E-154, or 3-value +TIMEOUT pre-E-180), which `CREATE TABLE IF
  // NOT EXISTS` cannot update — a REJECTED (or TIMEOUT) insert would fail the stale CHECK.
  // The detector keys on the NEWEST status token ('REJECTED'): any DDL lacking it predates the
  // current enum and is rebuilt, so this one block covers both the +TIMEOUT and the +REJECTED
  // hops (a 2-value DB jumps straight to the 4-value schema). The sentinel is DERIVED from
  // STATUS_ORDER (E-185), so appending a new enum value updates the detector automatically.
  // ATOMICITY (Tier-3 review P1): db.exec() autocommits PER statement, so a crash AFTER the
  // RENAME would strand rows in _tool_executions_old while the leading CREATE IF NOT EXISTS
  // resurrects an empty table the guard then reads as already-migrated → silent data loss.
  // Fixes: (a) the whole migration runs inside BEGIN IMMEDIATE/COMMIT so a mid-sequence failure
  // rolls the RENAME back atomically; (b) any _tool_executions_old stranded by a crash under the
  // OLD (pre-fix) code is recovered and merged back. Idempotent + fail-open.
  try {
    const orphan = db.prepare(
      "SELECT 1 AS x FROM sqlite_master WHERE type='table' AND name='_tool_executions_old'"
    ).get();
    const meta = db.prepare(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='tool_executions'"
    ).get();
    const ddl = meta && typeof meta.sql === "string" ? meta.sql : "";
    const needsMigration = ddl && !ddl.includes(STATUS_MIGRATION_SENTINEL);
    if (orphan || needsMigration) {
      db.exec("BEGIN IMMEDIATE");
      try {
        if (orphan) {
          // Prior crash left rows behind in _tool_executions_old. Merge them back into the live
          // table (coerce any unknown status to ERROR so the CHECK accepts them; dedupe by PK),
          // then drop the orphan. The live table may be the empty one the leading CREATE IF NOT
          // EXISTS just made, OR a pre-existing table that still carries a STALE CHECK — the
          // rebuild below handles the latter, so this merge never assumes a fresh 4-value table.
          db.exec(
            "INSERT OR IGNORE INTO tool_executions " +
            "SELECT id, project_hash, session_id, tool_name, execution_time_ms, " +
            `CASE WHEN ${STATUS_SQL_IN} THEN status ELSE 'ERROR' END, timestamp ` +
            "FROM _tool_executions_old; " +
            "DROP TABLE _tool_executions_old;"
          );
        }
        // E-180 (db_architect P1): orphan-recovery and CHECK-migration are NOT mutually exclusive.
        // A crashed DB can carry BOTH a stranded orphan AND a live table whose CHECK predates the
        // current enum; the old `if/else` ran only the merge, leaving the stale CHECK in place so
        // the triggering REJECTED insert failed it and was dropped until the next open self-healed.
        // Run the rebuild whenever the live DDL lacks the newest token — after any orphan merge,
        // inside this same transaction. `needsMigration` was read from the live table's DDL, which
        // the orphan merge only inserts rows into (never alters its schema), so it still reflects
        // CHECK-staleness here. The full-table rebuild holds the write lock for the row copy, so its
        // cost scales with telemetry.sqlite size — acceptable as a one-time, fail-open migration.
        if (needsMigration) {
          db.exec(
            "ALTER TABLE tool_executions RENAME TO _tool_executions_old; " +
            "CREATE TABLE tool_executions (" +
            "id TEXT PRIMARY KEY, project_hash TEXT NOT NULL, session_id TEXT NOT NULL, " +
            "tool_name TEXT NOT NULL, execution_time_ms INTEGER NOT NULL CHECK(execution_time_ms >= 0), " +
            `status TEXT NOT NULL CHECK(${STATUS_SQL_IN}), timestamp TEXT NOT NULL); ` +
            "INSERT INTO tool_executions " +
            "SELECT id, project_hash, session_id, tool_name, execution_time_ms, status, timestamp " +
            "FROM _tool_executions_old; " +
            "DROP TABLE _tool_executions_old; " +
            "CREATE INDEX IF NOT EXISTS idx_tool_executions_timestamp ON tool_executions(timestamp);"
          );
        }
        db.exec("COMMIT");
      } catch (inner) {
        try { db.exec("ROLLBACK"); } catch { /* nothing to roll back */ }
        throw inner;
      }
    }
  } catch (e) {
    _logErr("status-enum-migration-failed", e.message);
  }
  _cachedDb = db;
  _cachedPath = targetPath;
  return db;
}

function _doRecordToolExecution(payload, opts) {
  if (_isDisabled()) return;
  const tool_name = typeof payload?.tool_name === "string" ? payload.tool_name.trim() : "";
  if (!tool_name) { _logErr("missing-tool-name", null); return; }
  const exec_ms = Number.isFinite(payload?.execution_time_ms)
    ? Math.max(0, Math.floor(payload.execution_time_ms))
    : 0;
  const status = STATUS_VALUES.has(payload?.status) ? payload.status : "SUCCESS";
  const project_hash = _hashProjectRoot(payload?.project_root);
  const session_id = _sanitiseSessionId(payload?.session_id);

  try {
    const db = _openDb(opts?.db_path);
    const stmt = db.prepare(
      "INSERT INTO tool_executions (id, project_hash, session_id, tool_name, " +
      "execution_time_ms, status, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    stmt.run(
      randomUUID(),
      project_hash,
      session_id,
      tool_name,
      exec_ms,
      status,
      new Date().toISOString()
    );
  } catch (e) {
    _logErr("insert-tool-execution-failed", e.message);
  }
}

function _doRecordTaskVelocity(payload, opts) {
  if (_isDisabled()) return;
  const task_id = typeof payload?.task_id === "string" ? payload.task_id.trim() : "";
  if (!task_id) { _logErr("missing-task-id", null); return; }
  const turn_count = Number.isFinite(payload?.turn_count)
    ? Math.max(0, Math.floor(payload.turn_count))
    : 0;
  const tokens_consumed = Number.isFinite(payload?.tokens_consumed)
    ? Math.max(0, Math.floor(payload.tokens_consumed))
    : 0;

  try {
    const db = _openDb(opts?.db_path);
    const stmt = db.prepare(
      "INSERT INTO task_velocity (id, task_id, turn_count, tokens_consumed, " +
      "timestamp) VALUES (?, ?, ?, ?, ?)"
    );
    stmt.run(
      randomUUID(),
      task_id,
      turn_count,
      tokens_consumed,
      new Date().toISOString()
    );
  } catch (e) {
    _logErr("insert-task-velocity-failed", e.message);
  }
}

// E-106 (universal-telemetry.md): the mcp-router records a GRANULAR
// `<server>.<tool>` row for every proxy_call, while the global edge hook
// (post-tool-use.sh) ALSO records the COARSE wrapper for the same routed call.
// Drop that coarse duplicate at the writer so a routed call is counted once —
// the granular row is the source of truth. Other mcp-router tools
// (activate_domain/list_domains) have no granular counterpart and are kept.
// Rollback: AI_OS_TELEMETRY_NO_DEDUP=1 keeps both rows.
const ROUTER_PROXY_WRAPPER = "mcp__mcp-router__proxy_call";

function _isRoutedDuplicate(payload) {
  if (process.env.AI_OS_TELEMETRY_NO_DEDUP === "1") return false;
  const t = typeof payload?.tool_name === "string" ? payload.tool_name.trim() : "";
  return t === ROUTER_PROXY_WRAPPER;
}

// Public entry — fire-and-forget. The wrapper defers the actual sync write
// to the next macrotask so the calling MCP returns its response immediately.
// All errors are swallowed inside _doRecord*.
export function recordToolExecution(payload, opts) {
  if (_isDisabled()) return;
  if (_isRoutedDuplicate(payload)) return; // coarse proxy_call dup — router logs the granular row
  if (opts?.sync === true) {
    _doRecordToolExecution(payload, opts);
    return;
  }
  setImmediate(() => _doRecordToolExecution(payload, opts));
}

export function recordTaskVelocity(payload, opts) {
  if (_isDisabled()) return;
  if (opts?.sync === true) {
    _doRecordTaskVelocity(payload, opts);
    return;
  }
  setImmediate(() => _doRecordTaskVelocity(payload, opts));
}

// E-155: aggregate per-task token usage recorded by token-budget-mcp and write a
// task_velocity row. Invoked at the canonical DONE transition (task-synchronizer
// update_task_status) so the metric is captured reliably at completion — the row
// is ALWAYS written (0/0 when no usage was reported), closing the prior gap where
// recordTaskVelocity was exported but never wired to task completion. The usage
// DB is opened read-only and any failure is swallowed: telemetry never breaks
// task state. Writes synchronously by default (single INSERT + one indexed read,
// well under the <5ms budget) so the metric is durable before the handler returns.
export function recordTaskVelocityForTask(payload, opts) {
  if (_isDisabled()) return;
  const task_id = typeof payload?.task_id === "string" ? payload.task_id.trim() : "";
  if (!task_id) { _logErr("missing-task-id", null); return; }

  let turn_count = 0;
  let tokens_consumed = 0;
  try {
    const usagePath = opts?.usage_db_path || USAGE_DB_PATH;
    if (existsSync(usagePath)) {
      const udb = new DatabaseSync(usagePath, { readOnly: true });
      try {
        const r = udb
          .prepare("SELECT COUNT(*) AS turns, COALESCE(SUM(tokens), 0) AS tokens FROM usage WHERE task_id = ?")
          .get(task_id);
        turn_count = Number(r?.turns) || 0;
        tokens_consumed = Number(r?.tokens) || 0;
      } finally {
        udb.close();
      }
    }
  } catch (e) {
    _logErr("aggregate-usage-failed", e.message);
  }

  recordTaskVelocity(
    { task_id, turn_count, tokens_consumed },
    { db_path: opts?.db_path, sync: opts?.sync !== false }
  );
}

// Read-side: SQL aggregates for the meta_analyst agent (E-85) and the
// ai-preflight staleness check (E-86). Returns counts + last-write
// timestamps. Bounded by the optional `since_iso` window.
export function getTelemetryStats(opts = {}) {
  const path = opts.db_path || TELEMETRY_DB_PATH;
  if (!existsSync(path)) {
    return {
      status: "EMPTY",
      tool_executions: { count: 0, last_ts: null },
      task_velocity:   { count: 0, last_ts: null },
    };
  }
  try {
    const db = _openDb(path);
    const sinceClause = typeof opts.since_iso === "string"
      ? "WHERE timestamp >= ?"
      : "";
    const params = typeof opts.since_iso === "string" ? [opts.since_iso] : [];

    const teRow = db
      .prepare(`SELECT COUNT(*) AS c, MAX(timestamp) AS ts FROM tool_executions ${sinceClause}`)
      .get(...params);
    const tvRow = db
      .prepare(`SELECT COUNT(*) AS c, MAX(timestamp) AS ts FROM task_velocity ${sinceClause}`)
      .get(...params);
    return {
      status: "OK",
      tool_executions: { count: teRow?.c ?? 0, last_ts: teRow?.ts || null },
      task_velocity:   { count: tvRow?.c ?? 0, last_ts: tvRow?.ts || null },
    };
  } catch (e) {
    return {
      status: "READ_ERROR",
      error: e.message,
      tool_executions: { count: 0, last_ts: null },
      task_velocity:   { count: 0, last_ts: null },
    };
  }
}

// Test-only hook. Closes the cached handle and forces the next call to
// re-open against a (possibly different) path.
export function resetTelemetryCache() {
  if (_cachedDb) {
    try { _cachedDb.close(); } catch { /* ignore */ }
  }
  _cachedDb = null;
  _cachedPath = null;
}

// Pure-node project-root resolver — walks parents looking for a .git entry.
// Used by --record-tool / --record-task so the hook layer (E-105) can pipe
// raw tool JSON without pre-computing the project root. Capped at 32 hops
// so a malformed path can't loop. Returns startDir on miss; the hasher
// then maps every non-repo cwd to a stable "no-git" bucket per directory.
function _findProjectRoot(startDir) {
  let dir = startDir;
  for (let i = 0; i < 32; i++) {
    if (existsSync(resolve(dir, ".git"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return startDir;
}

async function _readStdinJson() {
  try {
    let buf = "";
    for await (const chunk of process.stdin) buf += chunk;
    const trimmed = buf.trim();
    if (!trimmed) return null;
    return JSON.parse(trimmed);
  } catch (e) {
    _logErr("stdin-parse-failed", e.message);
    return null;
  }
}

// CLI smoke for sysadmins and hook callers.
//   --stats         → JSON envelope of getTelemetryStats() (read-side).
//   --path          → canonical TELEMETRY_DB_PATH.
//   --record-tool   → consume one tool execution from stdin JSON
//                     ({tool_name, execution_time_ms, status, ...}) and
//                     write a tool_executions row. Used by E-105
//                     post-tool-use.sh to capture every Claude Code tool
//                     invocation, not just mcp-router::proxy_call.
//   --record-task   → consume one task velocity event from stdin JSON
//                     ({task_id, turn_count, tokens_consumed}) and write
//                     a task_velocity row.
// Both record subcommands exit 0 on every path (fail-open per blueprint
// §Security). project_hash is derived from process.cwd() walked up to
// .git; session_id is read from CLAUDE_CODE_SESSION_ID (E-49 contract).
async function _runCli() {
  const argv = process.argv.slice(2);
  if (argv.includes("--stats")) {
    process.stdout.write(JSON.stringify(getTelemetryStats(), null, 2) + "\n");
    return;
  }
  if (argv.includes("--path")) {
    process.stdout.write(TELEMETRY_DB_PATH + "\n");
    return;
  }
  if (argv.includes("--record-tool")) {
    const payload = await _readStdinJson();
    if (payload && typeof payload === "object") {
      const project_root = _findProjectRoot(process.cwd());
      const session_id = process.env.CLAUDE_CODE_SESSION_ID || "unknown";
      recordToolExecution({
        project_root,
        session_id,
        tool_name: payload.tool_name,
        execution_time_ms: payload.execution_time_ms,
        status: payload.status,
      }, { sync: true });
    }
    return;
  }
  if (argv.includes("--record-task")) {
    const payload = await _readStdinJson();
    if (payload && typeof payload === "object") {
      recordTaskVelocity({
        task_id: payload.task_id,
        turn_count: payload.turn_count,
        tokens_consumed: payload.tokens_consumed,
      }, { sync: true });
    }
    return;
  }
  process.stderr.write(
    "usage: telemetry.mjs [--stats | --path | --record-tool | --record-task]\n"
  );
  process.exit(2);
}

// _isMain compares resolved real paths because macOS routes ${TMPDIR} (and
// any mktemp -d sandbox) through /var → /private/var symlinks. The naive
// `import.meta.url === file://${process.argv[1]}` check fails there — the
// CLI silently no-ops, with no way to detect the misfire. realpathSync on
// both sides normalises the comparison; missing argv[1] or unreadable paths
// fall through to false.
function _detectMain() {
  try {
    const here = realpathSync(fileURLToPath(import.meta.url));
    const argv = process.argv[1] ? realpathSync(process.argv[1]) : "";
    return argv === here;
  } catch {
    return false;
  }
}

if (_detectMain()) {
  _runCli().catch((e) => {
    process.stderr.write(`telemetry crashed: ${e.message}\n`);
    process.exit(1);
  });
}
