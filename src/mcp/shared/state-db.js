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

const _dbCache = new Map();

/**
 * Open (or return cached) the state.sqlite DatabaseSync instance for `aiDir`.
 * Each distinct aiDir gets its own connection so that multiple consumers
 * within the same process can address different state stores without
 * silently sharing the first-opened one. Connections are keyed by the
 * resolved absolute path.
 */
export function getDb(aiDir) {
  const dbPath = resolve(aiDir, "state.sqlite");
  const cached = _dbCache.get(dbPath);
  if (cached) return cached;

  const db = new DatabaseSync(dbPath);
  db.exec("PRAGMA journal_mode = WAL;");
  // E-88: migrate the legacy SEO Keyword-Multiplier tables to the Topic
  // Cluster Engine vocabulary before the CREATE block runs. Idempotent and
  // safe on fresh DBs (no-op when the legacy tables are absent).
  _migrateSeoSchema(db);
  db.exec(`
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
    -- E-88: Multi-Variation-State-Tracker tables for the SEO Topic Cluster
    -- Engine (.ai/blueprints/seo-keyword-multiplier.md §Data Model).
    -- TopicSeed (formerly KeywordSeed) + ClusterPage (formerly
    -- ContentVariation). Idempotent — CREATE IF NOT EXISTS preserves any
    -- pre-existing rows on schema reopen. Legacy DBs are renamed in place
    -- by _migrateSeoSchema() above.
    CREATE TABLE IF NOT EXISTS topic_seeds (
      id            TEXT PRIMARY KEY,
      term          TEXT NOT NULL,
      status        TEXT NOT NULL DEFAULT 'OPEN'
                      CHECK(status IN ('OPEN','IN_PROGRESS','COMPLETED','ARCHIVED')),
      target_volume INTEGER NOT NULL DEFAULT 10
                      CHECK(target_volume > 0 AND target_volume <= 10),
      created_at    TEXT NOT NULL,
      completed_at  TEXT
    );
    CREATE TABLE IF NOT EXISTS cluster_pages (
      id                  TEXT PRIMARY KEY,
      seed_id             TEXT NOT NULL,
      intent_type         TEXT NOT NULL,
      content_blob        TEXT,
      performance_metrics TEXT,
      published_at        TEXT,
      created_at          TEXT NOT NULL,
      FOREIGN KEY (seed_id) REFERENCES topic_seeds(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_cluster_pages_seed
      ON cluster_pages(seed_id);
    CREATE INDEX IF NOT EXISTS idx_cluster_pages_intent
      ON cluster_pages(seed_id, intent_type);
    INSERT OR IGNORE INTO meta(key, value) VALUES ('version', '1.0');
    INSERT OR IGNORE INTO meta(key, value) VALUES ('digest_stale', 'false');
    INSERT OR IGNORE INTO meta(key, value) VALUES ('digest_stale_reason', '');
    INSERT OR IGNORE INTO project(key, value) VALUES ('current_tier', NULL);
    INSERT OR IGNORE INTO project(key, value) VALUES ('release_verdict', NULL);
    INSERT OR IGNORE INTO project(key, value) VALUES ('focus', NULL);
  `);

  _dbCache.set(dbPath, db);
  return db;
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

/**
 * E-88: next sequential TopicSeed id (`TS-N`). Separate namespace from the
 * task-id sequence so seeds and tasks never collide.
 */
export function nextTopicSeedId(db) {
  const rows = db.prepare("SELECT id FROM topic_seeds WHERE id LIKE ?").all("TS-%");
  const nums = rows.map(r => parseInt(r.id.split("-")[1], 10)).filter(n => !isNaN(n));
  return `TS-${nums.length > 0 ? Math.max(...nums) + 1 : 1}`;
}

/**
 * E-88: next sequential ClusterPage id (`CP-N`). Distinct from E-/P-/T-
 * task ids — pages are tracked by their topic cluster and intent_type, not
 * as Engineer/Architect/Tester work items.
 */
export function nextClusterPageId(db) {
  const rows = db.prepare("SELECT id FROM cluster_pages WHERE id LIKE ?").all("CP-%");
  const nums = rows.map(r => parseInt(r.id.split("-")[1], 10)).filter(n => !isNaN(n));
  return `CP-${nums.length > 0 ? Math.max(...nums) + 1 : 1}`;
}

/**
 * E-88: in-place migration of the legacy Keyword-Multiplier schema to the
 * Topic Cluster Engine vocabulary. Idempotent and safe on fresh DBs:
 *   keyword_seeds       → topic_seeds
 *   content_variations  → cluster_pages
 *   cluster_pages.approach_type → intent_type
 * Existing rows (and their target_volume CHECK from the legacy schema) are
 * preserved; the MCP layer enforces the lifted cap via MAX_CLUSTER_PAGES_PER_SEED.
 */
function _migrateSeoSchema(db) {
  const hasTable = (name) =>
    !!db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?").get(name);

  if (hasTable("keyword_seeds") && !hasTable("topic_seeds")) {
    db.exec("ALTER TABLE keyword_seeds RENAME TO topic_seeds;");
  }
  if (hasTable("content_variations") && !hasTable("cluster_pages")) {
    db.exec("ALTER TABLE content_variations RENAME TO cluster_pages;");
  }
  if (hasTable("cluster_pages")) {
    const cols = db.prepare("PRAGMA table_info(cluster_pages)").all();
    if (cols.some((c) => c.name === "approach_type")) {
      db.exec("ALTER TABLE cluster_pages RENAME COLUMN approach_type TO intent_type;");
    }
  }
  // Drop the legacy index names so the CREATE INDEX IF NOT EXISTS below
  // installs the renamed indices without leaving orphans behind.
  db.exec("DROP INDEX IF EXISTS idx_variations_seed;");
  db.exec("DROP INDEX IF EXISTS idx_variations_approach;");
}
