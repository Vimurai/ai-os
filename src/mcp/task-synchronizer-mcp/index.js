#!/usr/bin/env node
/**
 * task-synchronizer-mcp — AI-OS Exclusive State Mutator (E-156: SQLite migration)
 * Uses .ai/state.sqlite as the ACID-safe primary store.
 * Automatically migrates existing .ai/state.json on first use.
 * Regenerates state.json (backwards-compat view), TASKS.md, and REVIEWS.md
 * after every mutation.
 *
 * NOTE: orchestrator-mcp writes state.json directly (deltas, digest_stale,
 * task DONE transitions). Those writes remain in state.json and are visible
 * to task-synchronizer-mcp via the startup sync check (mtime guard).
 *
 * Tools:
 *   get_state()                        → returns full state
 *   add_task(owner, description, tier)  → adds task, auto-assigns ID
 *   update_task_status(id, status)      → transitions task status
 *   add_stamp(task_id, type, agent, summary) → writes atomic audit stamp
 *   set_project_focus(text)             → updates project focus
 *   archive_done_tasks()                → moves old DONE tasks to archive
 *   verify_markdown_sync()              → checks TASKS.md / REVIEWS.md vs DB
 *   sync_tasks(update_content?)         → (DEPRECATED E-147) no-op
 *   append_tasks(tasks)                 → (legacy) appends to TASKS.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from "fs";
import { resolve } from "path";
import { getDb, readState as _readState, regenerateViews as _regenerateViews, nextId as _nextId } from "../shared/state-db.js";

// ── SQLite Setup (delegated to state-db.js, P-15) ────────────────────────────

function _getDb(aiDir) {
  const dbPath   = resolve(aiDir, "state.sqlite");
  const jsonPath = resolve(aiDir, "state.json");
  const isNew    = !existsSync(dbPath);
  const db       = getDb(aiDir);
  if (isNew && existsSync(jsonPath)) {
    _importFromJson(jsonPath, db);
  }
  return db;
}

/**
 * One-time import of state.json into SQLite on first run.
 * state.json is preserved for backwards compat (orchestrator-mcp reads it).
 */
function _importFromJson(jsonPath, db) {
  let state;
  try {
    state = JSON.parse(readFileSync(jsonPath, "utf8"));
    if (!state || state.version !== "1.0") {
      process.stderr.write("[WARN] state.json has unexpected version — skipping migration\n");
      return;
    }
  } catch {
    process.stderr.write("[WARN] state.json parse error — skipping migration\n");
    return;
  }

  const setProj = db.prepare("INSERT OR REPLACE INTO project(key, value) VALUES (?, ?)");
  const proj = state.project || {};
  setProj.run("current_tier",    proj.current_tier   != null ? String(proj.current_tier) : null);
  setProj.run("release_verdict", proj.release_verdict ?? null);
  setProj.run("focus",           proj.focus          ?? null);

  const insertTask = db.prepare(`
    INSERT OR IGNORE INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  for (const t of (state.tasks || [])) {
    insertTask.run(t.id, t.owner, t.status, t.tier ?? null,
                   t.description, t.created_at, t.completed_at ?? null, t.summary ?? null);
  }

  const insertStamp = db.prepare(
    "INSERT INTO stamps(type, agent, task_id, timestamp, summary) VALUES (?, ?, ?, ?, ?)"
  );
  for (const s of (state.stamps || [])) {
    insertStamp.run(s.type, s.agent ?? null, s.task_id ?? null, s.timestamp, s.summary ?? null);
  }

  const insertDelta = db.prepare(
    "INSERT INTO deltas(task_id, summary, files, read, created_at) VALUES (?, ?, ?, ?, ?)"
  );
  for (const d of (state.deltas || [])) {
    insertDelta.run(
      d.task_id,
      d.summary ?? null,
      d.files || d.files_changed ? JSON.stringify(d.files || d.files_changed) : null,
      d.read ? 1 : 0,
      d.created_at || d.timestamp || new Date().toISOString()
    );
  }

  const setMeta = db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)");
  setMeta.run("digest_stale",        state.digest_stale ? "true" : "false");
  setMeta.run("digest_stale_reason", state.digest_stale_reason ?? "");

  process.stderr.write("[INFO] task-synchronizer-mcp: imported state.json → state.sqlite\n");
}

/**
 * Sync any external writes to state.json (e.g. from orchestrator-mcp) back
 * into SQLite. Called at the start of each tool handler.
 * Compares mtime of state.json vs state.sqlite; re-imports changed fields if
 * state.json is newer.
 */
function _syncFromJsonIfNewer(aiDir, db) {
  const jsonPath = resolve(aiDir, "state.json");
  const dbPath   = resolve(aiDir, "state.sqlite");
  if (!existsSync(jsonPath)) return;

  try {
    const jsonMtime = statSync(jsonPath).mtimeMs;
    const dbMtime   = statSync(dbPath).mtimeMs;
    if (jsonMtime <= dbMtime) return; // SQLite is current
  } catch { return; }

  // state.json is newer — re-import mutable fields (tasks, deltas, meta)
  let state;
  try {
    state = JSON.parse(readFileSync(jsonPath, "utf8"));
    if (!state || state.version !== "1.0") return;
  } catch { return; }

  // Upsert tasks (handles orchestrator-mcp DONE transitions)
  const upsertTask = db.prepare(`
    INSERT INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      status = excluded.status,
      completed_at = excluded.completed_at,
      summary = excluded.summary
  `);
  for (const t of (state.tasks || [])) {
    upsertTask.run(t.id, t.owner, t.status, t.tier ?? null,
                   t.description, t.created_at, t.completed_at ?? null, t.summary ?? null);
  }

  // Upsert meta (handles digest_stale from orchestrator-mcp)
  const setMeta = db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)");
  if (state.digest_stale !== undefined) {
    setMeta.run("digest_stale",        state.digest_stale ? "true" : "false");
    setMeta.run("digest_stale_reason", state.digest_stale_reason ?? "");
  }

  // Import any new deltas
  const knownCount = db.prepare("SELECT COUNT(*) as n FROM deltas").get().n;
  const jsonDeltas = state.deltas || [];
  if (jsonDeltas.length > knownCount) {
    const insertDelta = db.prepare(
      "INSERT INTO deltas(task_id, summary, files, read, created_at) VALUES (?, ?, ?, ?, ?)"
    );
    for (const d of jsonDeltas.slice(knownCount)) {
      insertDelta.run(
        d.task_id,
        d.summary ?? null,
        d.files || d.files_changed ? JSON.stringify(d.files || d.files_changed) : null,
        d.read ? 1 : 0,
        d.created_at || d.timestamp || new Date().toISOString()
      );
    }
  }
}

// ── State helpers delegated to state-db.js (P-15) ────────────────────────────
// _readState, _regenerateViews, _nextId are imported as _readState/_regenerateViews/_nextId above.

// ── Archive ───────────────────────────────────────────────────────────────────

const DONE_ARCHIVE_THRESHOLD = 50;
const DONE_KEEP_RECENT       = 10;

function _archiveDoneTasks(aiDir, db) {
  const done = db.prepare("SELECT * FROM tasks WHERE status = 'DONE' ORDER BY rowid").all();
  if (done.length <= DONE_ARCHIVE_THRESHOLD) return null;

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

  _regenerateViews(aiDir, db);
  return { archived: toArchive.length, kept: DONE_KEEP_RECENT, archivePath };
}

// ── Error messages ────────────────────────────────────────────────────────────

const STATE_MISSING_ERR = "✗ state.sqlite not found — run: ai init";
const DB_ERR = "✗ state.sqlite could not be opened";

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "task-synchronizer-mcp", version: "2.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_state",
      description: "Returns state.json. Use filters to avoid large responses. summary:true returns counts only (~200 tokens). status/owner/tier filter the task list.",
      inputSchema: {
        type: "object",
        properties: {
          summary: { type: "boolean",  description: "Return counts + project info only (no task list). Use this by default." },
          status:  { type: "string",   enum: ["OPEN", "BLOCKED", "DONE"], description: "Filter tasks by status" },
          owner:   { type: "string",   description: "Filter tasks by owner substring (e.g. 'claude', 'gemini')" },
          tier:    { type: "number",   enum: [1, 2, 3], description: "Filter tasks by tier" },
        },
      },
    },
    {
      name: "add_task",
      description: "Adds a new task to state with auto-assigned ID. Returns the new task.",
      inputSchema: {
        type: "object",
        properties: {
          owner:       { type: "string", description: "Task owner: 'Architect (Gemini)', 'Engineer (Claude)', or 'Tester (TestSprite)'" },
          description: { type: "string", description: "Task description" },
          tier:        { type: "number", description: "Risk tier (1, 2, or 3)", enum: [1, 2, 3] },
          prefix:      { type: "string", description: "ID prefix: P (architect), E (engineer), T (tester)", enum: ["P", "E", "T"], default: "E" },
        },
        required: ["owner", "description"],
      },
    },
    {
      name: "update_task_status",
      description: "Updates a task's status (OPEN, BLOCKED, DONE). Marks completed_at for DONE.",
      inputSchema: {
        type: "object",
        properties: {
          id:      { type: "string", description: "Task ID (e.g. 'E-78')" },
          status:  { type: "string", description: "New status", enum: ["OPEN", "BLOCKED", "DONE"] },
          summary: { type: "string", description: "Completion summary (for DONE status)" },
        },
        required: ["id", "status"],
      },
    },
    {
      name: "add_stamp",
      description: "Writes an atomic audit stamp. Used by critic agents and review synthesizer.",
      inputSchema: {
        type: "object",
        properties: {
          task_id: { type: "string", description: "Related task ID (e.g. 'E-78')" },
          type:    { type: "string", description: "Stamp type (e.g. 'ARCH_PASS', 'SEC_FAIL', 'CRITIC_STAMP')" },
          agent:   { type: "string", description: "Agent that produced this stamp" },
          summary: { type: "string", description: "One-line summary of the finding" },
        },
        required: ["type", "agent", "summary"],
      },
    },
    {
      name: "set_project_focus",
      description: "Updates the project's current focus and tier.",
      inputSchema: {
        type: "object",
        properties: {
          focus:        { type: "string", description: "Current focus description" },
          current_tier: { type: "number", description: "Current risk tier", enum: [1, 2, 3] },
        },
        required: ["focus"],
      },
    },
    {
      name: "archive_done_tasks",
      description: `Moves old DONE tasks (beyond the last ${DONE_KEEP_RECENT}) to .ai/archive/state-done-YYYYMM.json when total DONE count exceeds ${DONE_ARCHIVE_THRESHOLD}.`,
      inputSchema: { type: "object", properties: {} },
    },
    // Legacy tools
    {
      name: "append_tasks",
      description: "Legacy: Appends P-## task strings to TASKS.md directly. Use add_task for new tasks.",
      inputSchema: {
        type: "object",
        properties: {
          tasks: { type: "array", items: { type: "string" }, description: "Task strings to append" },
        },
        required: ["tasks"],
      },
    },
    {
      name: "verify_markdown_sync",
      description: "Checks that TASKS.md and REVIEWS.md are in sync with state. Returns PASS or FAIL.",
      inputSchema: { type: "object", properties: {} },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const aiDir = resolve(process.cwd(), ".ai");

  if (!existsSync(aiDir)) {
    return { content: [{ type: "text", text: "✗ No .ai/ directory found. Run: ai init" }], isError: true };
  }

  let db;
  try {
    db = _getDb(aiDir);
  } catch (e) {
    return { content: [{ type: "text", text: `${DB_ERR}: ${e.message}` }], isError: true };
  }

  // Sync any direct state.json writes (e.g. from orchestrator-mcp) back into SQLite
  _syncFromJsonIfNewer(aiDir, db);

  switch (name) {
    // ── get_state ─────────────────────────────────────────────────────────────
    case "get_state": {
      if (args.summary) {
        const counts = { OPEN: 0, BLOCKED: 0, DONE: 0 };
        for (const t of db.prepare("SELECT status FROM tasks").all()) {
          counts[t.status] = (counts[t.status] || 0) + 1;
        }
        const proj  = Object.fromEntries(
          db.prepare("SELECT key, value FROM project").all().map(r => [r.key, r.value])
        );
        const stamps = db.prepare(
          "SELECT type, agent, task_id, timestamp, summary FROM stamps ORDER BY id DESC LIMIT 5"
        ).all();
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              version:     "1.0",
              project:     { current_tier: proj.current_tier ? Number(proj.current_tier) : null, focus: proj.focus },
              task_counts: counts,
              total:       Object.values(counts).reduce((a, b) => a + b, 0),
              stamps,
            }, null, 2),
          }],
        };
      }

      if (args.status || args.owner || args.tier) {
        let sql   = "SELECT * FROM tasks WHERE 1=1";
        const params = [];
        if (args.status) { sql += " AND status = ?";              params.push(args.status); }
        if (args.tier)   { sql += " AND tier = ?";                params.push(args.tier); }
        const tasks = db.prepare(sql + " ORDER BY rowid").all(...params)
          .filter(t => !args.owner || t.owner?.toLowerCase().includes(args.owner.toLowerCase()));
        const proj = Object.fromEntries(
          db.prepare("SELECT key, value FROM project").all().map(r => [r.key, r.value])
        );
        return {
          content: [{
            type: "text",
            text: JSON.stringify({ project: proj, tasks, total_matched: tasks.length }, null, 2),
          }],
        };
      }

      // Full state — auto-archive if needed
      const archiveResult = _archiveDoneTasks(aiDir, db);
      const state = _readState(db);
      const note  = archiveResult
        ? `[AUTO-ARCHIVE] ${archiveResult.archived} DONE tasks archived to ${archiveResult.archivePath} — ${archiveResult.kept} recent DONE kept.\n\n`
        : "";
      return { content: [{ type: "text", text: note + JSON.stringify(state, null, 2) }] };
    }

    // ── add_task ──────────────────────────────────────────────────────────────
    case "add_task": {
      const prefix = args.prefix || "E";
      const id     = _nextId(db, prefix);
      const task   = {
        id,
        owner:        args.owner,
        status:       "OPEN",
        tier:         args.tier || null,
        description:  args.description,
        created_at:   new Date().toISOString(),
        completed_at: null,
        summary:      null,
      };

      db.prepare(`
        INSERT INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(task.id, task.owner, task.status, task.tier, task.description,
              task.created_at, task.completed_at, task.summary);

      _regenerateViews(aiDir, db);
      return { content: [{ type: "text", text: `✓ Added ${id}: ${args.description}\n${JSON.stringify(task, null, 2)}` }] };
    }

    // ── update_task_status ────────────────────────────────────────────────────
    case "update_task_status": {
      const row = db.prepare("SELECT id FROM tasks WHERE id = ?").get(args.id);
      if (!row) {
        return { content: [{ type: "text", text: `✗ Task '${args.id}' not found.` }], isError: true };
      }

      if (args.status === "DONE") {
        db.prepare("UPDATE tasks SET status = ?, completed_at = ?, summary = ? WHERE id = ?")
          .run(args.status, new Date().toISOString(), args.summary ?? null, args.id);
      } else {
        db.prepare("UPDATE tasks SET status = ? WHERE id = ?").run(args.status, args.id);
      }

      _regenerateViews(aiDir, db);
      return { content: [{ type: "text", text: `✓ ${args.id} → ${args.status}${args.summary ? ": " + args.summary : ""}` }] };
    }

    // ── add_stamp ─────────────────────────────────────────────────────────────
    case "add_stamp": {
      db.prepare(
        "INSERT INTO stamps(type, agent, task_id, timestamp, summary) VALUES (?, ?, ?, ?, ?)"
      ).run(args.type, args.agent ?? null, args.task_id ?? null,
             new Date().toISOString(), args.summary);

      _regenerateViews(aiDir, db);
      return { content: [{ type: "text", text: `✓ Stamp [${args.type}] added by ${args.agent}` }] };
    }

    // ── set_project_focus ─────────────────────────────────────────────────────
    case "set_project_focus": {
      db.prepare("INSERT OR REPLACE INTO project(key, value) VALUES ('focus', ?)").run(args.focus);
      if (args.current_tier) {
        db.prepare("INSERT OR REPLACE INTO project(key, value) VALUES ('current_tier', ?)").run(String(args.current_tier));
      }

      _regenerateViews(aiDir, db);
      return { content: [{ type: "text", text: `✓ Focus: ${args.focus}${args.current_tier ? " (Tier " + args.current_tier + ")" : ""}` }] };
    }

    // ── archive_done_tasks ────────────────────────────────────────────────────
    case "archive_done_tasks": {
      const result = _archiveDoneTasks(aiDir, db);
      if (!result) {
        const doneCount = db.prepare("SELECT COUNT(*) as n FROM tasks WHERE status = 'DONE'").get().n;
        return { content: [{ type: "text", text: `✓ No archive needed — ${doneCount} DONE tasks (threshold: ${DONE_ARCHIVE_THRESHOLD})` }] };
      }
      return { content: [{ type: "text", text: `✓ [AUTO-ARCHIVE] ${result.archived} DONE tasks → ${result.archivePath}\n  ${result.kept} recent DONE tasks kept.` }] };
    }

    // ── Legacy: sync_tasks (DEPRECATED E-147/E-149) ───────────────────────────
    case "sync_tasks": {
      const updateContent = (args.update_content || "").trim();
      if (!updateContent) {
        return {
          content: [{
            type: "text",
            text: "⚠ DEPRECATED (E-147): sync_tasks no longer reads UPDATE.md.\n" +
                  "Pass intent directly via `update_content`, or use `add_task` to create tasks directly.",
          }],
        };
      }

      const tasksPath    = resolve(aiDir, "TASKS.md");
      const tasksContent = existsSync(tasksPath) ? readFileSync(tasksPath, "utf8") : "";
      const pNums        = [...tasksContent.matchAll(/P-(\d+):/g)].map(m => parseInt(m[1], 10));
      const nextP        = (pNums.length ? Math.max(...pNums) : 0) + 1;

      const lines = updateContent.split("\n")
        .filter(l => l.match(/^[-*]\s+/) || l.match(/^##\s+/))
        .map(l => l.replace(/^[-*]\s+/, "").replace(/^##\s+/, "").trim())
        .filter(l => l.length > 5)
        .slice(0, 5);

      if (lines.length === 0) {
        return { content: [{ type: "text", text: "Could not extract actionable intent from provided content." }] };
      }

      const lower = updateContent.toLowerCase();
      const tier  = /\b(auth|oauth|secret|api.?key|deploy|production|migration|breaking)\b/.test(lower) ? "3"
        : /\b(src|logic|refactor|test|implement|algorithm|database|api)\b/.test(lower) ? "2" : "1";
      const date  = new Date().toISOString().split("T")[0];

      const proposed = lines.map((line, i) => {
        const num = String(nextP + i).padStart(2, "0");
        return `- [ ] P-${num}: Blueprint for "${line}"\n  Tier: ${tier} | Proposed: ${date}`;
      });

      return { content: [{ type: "text", text: `## Proposed P-## Tasks\n\n${proposed.join("\n\n")}\n\nTo apply: call append_tasks.\n\n⚠ Prefer using \`add_task\` directly for new task creation.` }] };
    }

    // ── Legacy: append_tasks ──────────────────────────────────────────────────
    case "append_tasks": {
      const tasksPath = resolve(aiDir, "TASKS.md");
      if (!existsSync(tasksPath)) {
        return { content: [{ type: "text", text: "✗ .ai/TASKS.md not found." }], isError: true };
      }

      let content     = readFileSync(tasksPath, "utf8");
      const toAppend  = args.tasks.join("\n") + "\n";
      const archIdx   = content.indexOf("## Architect");
      if (archIdx === -1) {
        content += "\n## Architect (Gemini)\n" + toAppend;
      } else {
        const engIdx = content.indexOf("## Engineer", archIdx);
        content = engIdx === -1
          ? content + "\n" + toAppend
          : content.slice(0, engIdx) + toAppend + "\n" + content.slice(engIdx);
      }

      writeFileSync(tasksPath, content, "utf8");
      return { content: [{ type: "text", text: `✓ Appended ${args.tasks.length} task(s) to TASKS.md` }] };
    }

    // ── verify_markdown_sync ──────────────────────────────────────────────────
    case "verify_markdown_sync": {
      const failures = [];

      const tasksPath = resolve(aiDir, "TASKS.md");
      if (existsSync(tasksPath)) {
        const tasksContent    = readFileSync(tasksPath, "utf8");
        const mdTaskCount     = (tasksContent.match(/^- \[/gm) || []).length;
        const stateTaskCount  = db.prepare("SELECT COUNT(*) as n FROM tasks").get().n;
        if (Math.abs(mdTaskCount - stateTaskCount) > 2) {
          failures.push(`TASKS.md has ${mdTaskCount} tasks but state has ${stateTaskCount} — regenerating`);
          _regenerateViews(aiDir, db);
        }
        if (!tasksContent.startsWith("# TASKS (Generated from state.json)")) {
          failures.push("TASKS.md does not start with generated header — may have been hand-edited");
        }
      }

      const reviewsPath  = resolve(aiDir, "REVIEWS.md");
      const stampCount   = db.prepare("SELECT COUNT(*) as n FROM stamps").get().n;
      if (existsSync(reviewsPath) && stampCount > 0) {
        const reviewsContent = readFileSync(reviewsPath, "utf8");
        const mdStampCount   = (reviewsContent.match(/^\[[\w_]+\]/gm) || []).length;
        if (mdStampCount < stampCount) {
          failures.push(`REVIEWS.md has ${mdStampCount} stamps but state has ${stampCount} — regenerating`);
          _regenerateViews(aiDir, db);
        }
      }

      if (failures.length === 0) {
        return { content: [{ type: "text", text: "[SYNC_PASS] TASKS.md and REVIEWS.md are in sync with state." }] };
      }
      return {
        content: [{ type: "text", text: `[SYNC_FIXED] Issues detected and auto-resolved:\n${failures.map(f => `  - ${f}`).join("\n")}` }],
      };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
