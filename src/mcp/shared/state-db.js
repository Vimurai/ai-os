/**
 * state-db.js — Shared SQLite state helper (P-13)
 *
 * Extracted from task-synchronizer-mcp so that orchestrator-mcp and any
 * future MCP server can access the ACID-safe primary store without
 * duplicating schema or WAL setup.
 *
 * Exports: getDb, readState, regenerateViews, nextId
 */

import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from "fs";
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
      summary      TEXT,
      depends_on   TEXT
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
  // E-91: add the DAG `depends_on` column to pre-existing tasks tables.
  // CREATE TABLE IF NOT EXISTS never alters an existing table, so DBs created
  // before E-91 need this idempotent ALTER. Safe + no-op on fresh DBs.
  _migrateTaskDag(db);

  _dbCache.set(dbPath, db);
  return db;
}

/**
 * E-91 (ecc-integrations.md §Components 3): add the `depends_on` column to a
 * legacy tasks table that predates DAG support. Idempotent — checks
 * table_info before altering. Mirrors the _migrateSeoSchema pattern.
 */
function _migrateTaskDag(db) {
  const cols = db.prepare("PRAGMA table_info(tasks)").all();
  if (!cols.some((c) => c.name === "depends_on")) {
    db.exec("ALTER TABLE tasks ADD COLUMN depends_on TEXT;");
  }
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
 * E-91: parse the JSON-encoded `depends_on` column into a string array.
 * Corrupt or absent values degrade to [] (a task with no parseable
 * dependencies is treated as having none, never crashes readState).
 */
export function parseDeps(raw) {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
  } catch {
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
    tasks:               (() => {
      // E-91: enrich every task with parsed dependencies and DAG readiness.
      // `ready` is true when all depends_on tasks are DONE (or none exist);
      // `blocked_by` lists the still-unmet dependency ids. The Orchestrator
      // (E-92) dispatches only tasks that are OPEN and ready.
      const statusById = new Map(tasks.map(t => [t.id, t.status]));
      return tasks.map(t => {
        const depends_on = parseDeps(t.depends_on);
        const blocked_by = depends_on.filter(d => statusById.get(d) !== "DONE");
        return { ...t, tier: t.tier ?? null, depends_on, ready: blocked_by.length === 0, blocked_by };
      });
    })(),
    stamps,
    deltas,
    digest_stale:        meta.digest_stale === "true",
    digest_stale_reason: meta.digest_stale_reason || null,
  };
}

/**
 * E-136 (role-abstraction.md): derive the provider-agnostic semantic role from an
 * owner string for TASKS.md section headers. "Engineer (Claude)" -> "Engineer",
 * "Architect (Gemini)" -> "Architect", bare "Engineer" -> "Engineer". state.json
 * retains the full owner string; only the generated TASKS.md header is normalized,
 * so a CLI swap (e.g. Gemini -> Antigravity) never churns the section headers.
 */
export function roleFromOwner(owner) {
  return String(owner || "Unassigned").split(" (")[0].trim() || "Unassigned";
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
    const byRole = {}; // E-136 (role-abstraction.md): group by provider-agnostic role
    for (const t of state.tasks) {
      const role = roleFromOwner(t.owner);
      if (!byRole[role]) byRole[role] = [];
      byRole[role].push(t);
    }
    for (const [role, roleTasks] of Object.entries(byRole)) {
      lines.push(`## ${role}`);
      for (const t of roleTasks) {
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

// ── E-91: DAG dependency engine (ecc-integrations.md §Components 3) ──────────

/** Maximum dependency chain depth. Beyond this the LLM context gets confused
 *  by deep state trees (blueprint §Execution Constraints). */
export const MAX_DAG_DEPTH = 5;

/**
 * Read the full dependency graph from the tasks table.
 * Returns { deps: Map<id, string[]>, status: Map<id, status> }.
 */
export function readDependencyGraph(db) {
  const rows   = db.prepare("SELECT id, status, depends_on FROM tasks").all();
  const deps   = new Map();
  const status = new Map();
  for (const r of rows) {
    deps.set(r.id, parseDeps(r.depends_on));
    status.set(r.id, r.status);
  }
  return { deps, status };
}

/**
 * Validate that giving task `id` the dependency list `candidateDeps` keeps the
 * graph acyclic, within depth, and references only existing tasks. `id` may be
 * a brand-new task (not yet inserted) or an existing one whose deps are being
 * revised. Pure read — performs no writes.
 *
 * @returns {{ok: true, depth: number}} on success,
 *          {{ok: false, code: "DAG_FAIL", error: string}} on violation.
 */
export function validateDag(db, id, candidateDeps, opts = {}) {
  const maxDepth = opts.maxDepth ?? MAX_DAG_DEPTH;
  const unique   = [...new Set(Array.isArray(candidateDeps) ? candidateDeps : [])];
  const { deps: graph } = readDependencyGraph(db);

  // Self-reference is the degenerate 1-node cycle.
  if (unique.includes(id)) {
    return { ok: false, code: "DAG_FAIL", error: `Task ${id} cannot depend on itself.` };
  }
  // Every dependency must already exist — you cannot depend on a task that
  // was never created (catches typos and out-of-order task drops).
  const missing = unique.filter(d => !graph.has(d));
  if (missing.length) {
    return { ok: false, code: "DAG_FAIL", error: `Unknown dependency task(s): ${missing.join(", ")}.` };
  }

  // Overlay the candidate edges (covers both new and revised tasks).
  graph.set(id, unique);

  // Cycle detection via DFS from `id`, tracking the recursion stack.
  const onStack = new Set();
  const seen    = new Set();
  const path    = [];
  let   cycle   = null;
  (function dfs(node) {
    if (cycle) return;
    if (onStack.has(node)) { cycle = [...path, node]; return; }
    if (seen.has(node)) return;
    onStack.add(node); path.push(node);
    for (const d of (graph.get(node) || [])) dfs(d);
    onStack.delete(node); path.pop(); seen.add(node);
  })(id);
  if (cycle) {
    return { ok: false, code: "DAG_FAIL", error: `Circular dependency detected: ${cycle.join(" → ")}.` };
  }

  // Longest dependency chain length from `id` (graph is proven acyclic above).
  const memo = new Map();
  const depthOf = (node) => {
    if (memo.has(node)) return memo.get(node);
    const ds = graph.get(node) || [];
    const d  = ds.length === 0 ? 1 : 1 + Math.max(...ds.map(depthOf));
    memo.set(node, d);
    return d;
  };
  const depth = depthOf(id);
  if (depth > maxDepth) {
    return { ok: false, code: "DAG_FAIL", error: `Dependency chain depth ${depth} exceeds max ${maxDepth}.` };
  }

  return { ok: true, depth };
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
// Highest numeric suffix among `<prefix>-N` ids, or 0 when none match.
function _maxIdNum(ids, prefix) {
  let max = 0;
  for (const id of ids) {
    if (typeof id !== "string" || !id.startsWith(`${prefix}-`)) continue;
    const n = parseInt(id.split("-")[1], 10);
    if (!isNaN(n) && n > max) max = n;
  }
  return max;
}

// E-109 (drift-resolution-2026.md): highest `<prefix>-N` id across every
// .ai/archive/state-done-*.json. Archived tasks have been DELETEd from the live
// table, so their ids must still bound the sequence or nextId can re-issue a
// retired id (the state-json-db-mismatch incident). Fail-soft on missing/corrupt
// archives — a bad file must never block task creation.
function _archivedMaxId(aiDir, prefix) {
  if (!aiDir) return 0;
  try {
    const dir = resolve(aiDir, "archive");
    if (!existsSync(dir)) return 0;
    let max = 0;
    for (const f of readdirSync(dir)) {
      if (!/^state-done-.*\.json$/.test(f)) continue;
      let rows;
      try { rows = JSON.parse(readFileSync(resolve(dir, f), "utf8")); } catch { continue; }
      if (!Array.isArray(rows)) continue;
      const m = _maxIdNum(rows.map(t => t && t.id), prefix);
      if (m > max) max = m;
    }
    return max;
  } catch {
    return 0;
  }
}

// E-109: allocate the next task id without ever colliding with an archived or
// previously-issued id. The next number is max(live, archived, high-water) + 1.
// PURE — it never writes, so a speculative nextId() for an add_task that later
// fails validation does not burn an id. The caller persists the high-water via
// recordIdHighWater() only after the row is actually inserted.
export function nextId(db, prefix, aiDir) {
  const liveRows = db.prepare("SELECT id FROM tasks WHERE id LIKE ?").all(`${prefix}-%`);
  const liveMax  = _maxIdNum(liveRows.map(r => r.id), prefix);
  const archMax  = _archivedMaxId(aiDir, prefix);

  const hwRow = db.prepare("SELECT value FROM project WHERE key = ?").get(`last_id_${prefix}`);
  const hwMax = hwRow ? (parseInt(hwRow.value, 10) || 0) : 0;

  return `${prefix}-${Math.max(liveMax, archMax, hwMax) + 1}`;
}

// E-109: persist the per-prefix high-water mark AFTER a task row is committed, so
// the sequence stays monotonic even if the row is later DELETEd from the live
// table without being archived. Idempotent: only advances, never regresses.
export function recordIdHighWater(db, id) {
  if (typeof id !== "string" || !id.includes("-")) return;
  const [prefix, numStr] = id.split("-");
  const num = parseInt(numStr, 10);
  if (isNaN(num)) return;
  const key = `last_id_${prefix}`;
  const row = db.prepare("SELECT value FROM project WHERE key = ?").get(key);
  const cur = row ? (parseInt(row.value, 10) || 0) : 0;
  if (num > cur) db.prepare("INSERT OR REPLACE INTO project(key, value) VALUES (?, ?)").run(key, String(num));
}

// ── Archive rotation (E-111: single-source ownership) ───────────────────────
// The SQLite-aware rotation for DONE tasks and audit stamps lives here so both
// task-synchronizer-mcp (the archive_done_tasks tool) and archive-manager-mcp
// (execute_archive) share ONE implementation — no more byte-duplicated copies,
// and no writes to the regenerated state.json view. Both regenerate the .ai/
// markdown views from SQLite after mutating, preserving the ACID contract.
export const DONE_ARCHIVE_THRESHOLD  = 50;
export const DONE_KEEP_RECENT        = 10;
export const STAMP_ARCHIVE_THRESHOLD = 50;
export const STAMP_KEEP_RECENT       = 10;

// Generic JSON-array archive append + delete for one table. Returns
// { archived, kept, archivePath } or null when at/below threshold.
function _rotateToArchive(aiDir, db, { table, orderBy, fileStem, threshold, keep }) {
  const rows = db.prepare(`SELECT * FROM ${table} ORDER BY ${orderBy}`).all();
  if (rows.length <= threshold) return null;

  const toArchive  = rows.slice(0, rows.length - keep);
  const archiveIds = toArchive.map(r => r.id);

  const ym          = new Date().toISOString().slice(0, 7);
  const archiveDir  = resolve(aiDir, "archive");
  mkdirSync(archiveDir, { recursive: true });
  const archivePath = resolve(archiveDir, `${fileStem}-${ym}.json`);

  let existing = [];
  if (existsSync(archivePath)) {
    try { existing = JSON.parse(readFileSync(archivePath, "utf8")); } catch { existing = []; }
  }
  writeFileSync(archivePath, JSON.stringify([...existing, ...toArchive], null, 2) + "\n", "utf8");

  const ph = archiveIds.map(() => "?").join(",");
  db.prepare(`DELETE FROM ${table} WHERE id IN (${ph})`).run(...archiveIds);

  regenerateViews(aiDir, db);
  return { archived: toArchive.length, kept: keep, archivePath };
}

// Move old DONE tasks (beyond the last DONE_KEEP_RECENT) to
// .ai/archive/state-done-YYYY-MM.json when the count exceeds the threshold.
export function archiveDoneTasks(aiDir, db) {
  const done = db.prepare("SELECT * FROM tasks WHERE status = 'DONE' ORDER BY rowid").all();
  if (done.length <= DONE_ARCHIVE_THRESHOLD) return null;
  // Reuse the generic rotator but scoped to DONE rows (it re-selects with the
  // same predicate via a temp view would be overkill; inline the DONE slice).
  const toArchive   = done.slice(0, done.length - DONE_KEEP_RECENT);
  const archiveIds  = toArchive.map(t => t.id);
  const ym          = new Date().toISOString().slice(0, 7);
  const archiveDir  = resolve(aiDir, "archive");
  mkdirSync(archiveDir, { recursive: true });
  const archivePath = resolve(archiveDir, `state-done-${ym}.json`);
  let existing = [];
  if (existsSync(archivePath)) {
    try { existing = JSON.parse(readFileSync(archivePath, "utf8")); } catch { existing = []; }
  }
  writeFileSync(archivePath, JSON.stringify([...existing, ...toArchive], null, 2) + "\n", "utf8");
  const ph = archiveIds.map(() => "?").join(",");
  db.prepare(`DELETE FROM tasks WHERE id IN (${ph})`).run(...archiveIds);
  regenerateViews(aiDir, db);
  return { archived: toArchive.length, kept: DONE_KEEP_RECENT, archivePath };
}

// Rotate the oldest audit stamps to .ai/archive/stamps-YYYY-MM.json once the
// stamps table exceeds STAMP_ARCHIVE_THRESHOLD, keeping the newest in state.
export function archiveStamps(aiDir, db) {
  return _rotateToArchive(aiDir, db, {
    table: "stamps", orderBy: "id", fileStem: "stamps",
    threshold: STAMP_ARCHIVE_THRESHOLD, keep: STAMP_KEEP_RECENT,
  });
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
