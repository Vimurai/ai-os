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
//   - Status is constrained to {"SUCCESS","ERROR"}.
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
import { existsSync, mkdirSync, realpathSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

export const TELEMETRY_SERVICE = "telemetry";
export const TELEMETRY_DB_PATH = resolve(homedir(), ".ai-os", "telemetry.sqlite");

const SESSION_ID_RE = /^[A-Za-z0-9-]{1,64}$/;
const STATUS_VALUES = new Set(["SUCCESS", "ERROR"]);

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
  _ensureDir(targetPath);
  const db = new DatabaseSync(targetPath);
  // Per blueprint §Components 1 — two tables, idempotent CREATE.
  db.exec(`
    CREATE TABLE IF NOT EXISTS tool_executions (
      id TEXT PRIMARY KEY,
      project_hash TEXT NOT NULL,
      session_id TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      execution_time_ms INTEGER NOT NULL CHECK(execution_time_ms >= 0),
      status TEXT NOT NULL CHECK(status IN ('SUCCESS','ERROR')),
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

// Public entry — fire-and-forget. The wrapper defers the actual sync write
// to the next macrotask so the calling MCP returns its response immediately.
// All errors are swallowed inside _doRecord*.
export function recordToolExecution(payload, opts) {
  if (_isDisabled()) return;
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
