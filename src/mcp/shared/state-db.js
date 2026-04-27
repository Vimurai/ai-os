/**
 * state-db.js — Shared SQLite state helper (P-13)
 *
 * Extracted from task-synchronizer-mcp so that orchestrator-mcp and any
 * future MCP server can access the ACID-safe primary store without
 * duplicating schema or WAL setup.
 *
 * Exports: getDb, readState, regenerateViews, nextId
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";
import { DatabaseSync } from "node:sqlite";

let _db = null;

/**
 * Open (or return cached) the state.sqlite DatabaseSync instance.
 * Creates schema + WAL on first open. Caller must pass aiDir every time;
 * the cached instance is valid as long as the process lives.
 */
export function getDb(aiDir) {
  if (_db) return _db;

  const dbPath = resolve(aiDir, "state.sqlite");
  _db = new DatabaseSync(dbPath);
  _db.exec("PRAGMA journal_mode = WAL;");
  _db.exec(`
    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT
    );
    CREATE TABLE IF NOT EXISTS project (
      key   TEXT PRIMARY KEY,
      value TEXT
    );
    CREATE TABLE IF NOT EXISTS tasks (
      id           TEXT PRIMARY KEY,
      owner        TEXT NOT NULL,
      status       TEXT NOT NULL DEFAULT 'OPEN',
      tier         INTEGER,
      description  TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      completed_at TEXT,
      summary      TEXT
    );
    CREATE TABLE IF NOT EXISTS stamps (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      type      TEXT NOT NULL,
      agent     TEXT,
      task_id   TEXT,
      timestamp TEXT NOT NULL,
      summary   TEXT
    );
    CREATE TABLE IF NOT EXISTS deltas (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id    TEXT NOT NULL,
      summary    TEXT,
      files      TEXT,
      read       INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS patches (
      id           TEXT PRIMARY KEY,
      path         TEXT NOT NULL,
      diff_content TEXT NOT NULL,
      description  TEXT,
      caller_role  TEXT,
      created_at   TEXT NOT NULL,
      status       TEXT NOT NULL DEFAULT 'pending'
    );
    INSERT OR IGNORE INTO meta(key, value) VALUES ('version', '1.0');
    INSERT OR IGNORE INTO meta(key, value) VALUES ('digest_stale', 'false');
    INSERT OR IGNORE INTO meta(key, value) VALUES ('digest_stale_reason', '');
    INSERT OR IGNORE INTO project(key, value) VALUES ('current_tier', NULL);
    INSERT OR IGNORE INTO project(key, value) VALUES ('release_verdict', NULL);
    INSERT OR IGNORE INTO project(key, value) VALUES ('focus', NULL);
  `);

  return _db;
}

/**
 * Parse a JSON-encoded `files` column safely. Corrupt rows return [] and
 * write a single-line warning to stderr instead of crashing readState().
 */
function _safeParseFiles(raw) {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v : [];
  } catch (e) {
    process.stderr.write(`[WARN] state-db: corrupt deltas.files JSON — defaulting to []: ${e.message}\n`);
    return [];
  }
}

/**
 * Reconstruct the canonical state object from SQLite tables.
 */
export function readState(db) {
  const meta   = Object.fromEntries(db.prepare("SELECT key, value FROM meta").all().map(r => [r.key, r.value]));
  const proj   = Object.fromEntries(db.prepare("SELECT key, value FROM project").all().map(r => [r.key, r.value]));
  const tasks  = db.prepare("SELECT * FROM tasks ORDER BY rowid").all();
  const stamps = db.prepare(
    "SELECT type, agent, task_id, timestamp, summary FROM stamps ORDER BY id"
  ).all();
  const deltas = db.prepare(
    "SELECT task_id, summary, files, read, created_at FROM deltas ORDER BY id"
  ).all().map(d => ({
    task_id:    d.task_id,
    summary:    d.summary,
    files:      _safeParseFiles(d.files),
    read:       !!d.read,
    created_at: d.created_at,
  }));

  return {
    version: meta.version || "1.0",
    project: {
      current_tier:    proj.current_tier != null ? Number(proj.current_tier) : null,
      release_verdict: proj.release_verdict ?? null,
      focus:           proj.focus ?? null,
    },
    tasks:               tasks.map(t => ({ ...t, tier: t.tier ?? null })),
    stamps,
    deltas,
    digest_stale:        meta.digest_stale === "true",
    digest_stale_reason: meta.digest_stale_reason || null,
  };
}

/**
 * Regenerate the three backwards-compat views: TASKS.md, REVIEWS.md, state.json.
 * Must be called after every SQLite mutation so file-based consumers stay in sync.
 */
export function regenerateViews(aiDir, db) {
  const state = readState(db);

  // TASKS.md
  if (state.tasks.length > 0) {
    const tasksPath = resolve(aiDir, "TASKS.md");
    const lines = ["# TASKS (Generated from state.json)", ""];
    const byOwner = {};
    for (const t of state.tasks) {
      const owner = t.owner || "Unassigned";
      if (!byOwner[owner]) byOwner[owner] = [];
      byOwner[owner].push(t);
    }
    for (const [owner, ownerTasks] of Object.entries(byOwner)) {
      lines.push(`## ${owner}`);
      for (const t of ownerTasks) {
        const check   = t.status === "DONE" ? "x" : " ";
        const tierStr = t.tier ? ` | Tier: ${t.tier}` : "";
        lines.push(`- [${check}] ${t.id}: ${t.description}${tierStr}`);
        if (t.status === "DONE" && t.completed_at) {
          lines.push(`  Status: DONE ${t.completed_at.split("T")[0]} — ${t.summary || "Complete"}`);
        }
      }
      lines.push("");
    }
    writeFileSync(tasksPath, lines.join("\n"), "utf8");
  }

  // REVIEWS.md
  if (state.stamps.length > 0) {
    const reviewsPath = resolve(aiDir, "REVIEWS.md");
    const stampLines  = ["# REVIEWS.md (Generated from state.json)", ""];
    for (const s of state.stamps) {
      const date = s.timestamp ? s.timestamp.split("T")[0] : "unknown";
      stampLines.push(`[${s.type}] ${date} | ${s.summary || s.agent || ""}`);
    }
    stampLines.push("");
    writeFileSync(reviewsPath, stampLines.join("\n"), "utf8");
  }

  // state.json (backwards-compat for any consumer still reading it directly)
  writeFileSync(
    resolve(aiDir, "state.json"),
    JSON.stringify(state, null, 2) + "\n",
    "utf8"
  );
}

/**
 * Execute a callback inside a single ACID transaction.
 * Automatically COMMITs on success or ROLLBACKs on throw.
 *
 * @param {DatabaseSync} db
 * @param {function(db): any} callback
 * @returns the return value of callback
 */
export function withTransaction(db, callback) {
  db.exec("BEGIN");
  try {
    const result = callback(db);
    db.exec("COMMIT");
    return result;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/**
 * Compute the next sequential ID for a given prefix (E, P, T).
 */
export function nextId(db, prefix) {
  const rows = db.prepare("SELECT id FROM tasks WHERE id LIKE ?").all(`${prefix}-%`);
  const nums = rows.map(r => parseInt(r.id.split("-")[1], 10)).filter(n => !isNaN(n));
  return `${prefix}-${nums.length > 0 ? Math.max(...nums) + 1 : 1}`;
}
