#!/usr/bin/env node
/**
 * task-synchronizer-mcp — AI-OS Exclusive State Mutator (E-156: SQLite migration)
 * Uses .ai/state.sqlite as the ACID-safe primary store.
 * Automatically migrates existing .ai/state.json on first use.
 * Regenerates state.json (backwards-compat view), TASKS.md, and REVIEWS.md
 * after every mutation. All state writes — including deltas and task transitions
 * from orchestrator-mcp — go through SQLite (P-26, P-27).
 *
 * Tools:
 *   get_state()                        → returns full state
 *   add_task(owner, description, tier)  → adds task, auto-assigns ID
 *   update_task_status(id, status)      → transitions task status
 *   add_stamp(task_id, type, agent, summary) → writes atomic audit stamp
 *   set_project_focus(text)             → updates project focus
 *   archive_done_tasks()                → moves old DONE tasks to archive
 *   verify_markdown_sync()              → checks TASKS.md / REVIEWS.md vs DB
 *   mark_deltas_read(task_ids?)         → acknowledge implementation deltas
 *   sync_tasks(update_content?)         → (DEPRECATED E-147) no-op
 *   append_tasks(tasks)                 → (legacy) appends to TASKS.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { resolve } from "path";
import { getDb, readState as _readState, regenerateViews as _regenerateViews, nextId as _nextId, nextKeywordSeedId as _nextKeywordSeedId, nextContentVariationId as _nextContentVariationId } from "../shared/state-db.js";
import { validateNamed, loadSchemas } from "../../shared/schema-validator.js";
import { createLogger } from "../shared/logger.js";
// E-74: Managed Agents cloud sync hook. The import is unconditional (cheap —
// no side effects at module load), but every call site goes through
// syncToCloud() which short-circuits to {status:"DISABLED"} when
// AI_MANAGED_AGENTS_ENABLE is unset. Local MCP behaviour is unchanged off.
import { syncToCloud as _syncToCloud } from "../../shared/managed-agents-client.mjs";
// E-79: Multi-Variation-State-Tracker — canonical SEO approach-type slug
// list. Used to validate ContentVariation.approach_type on add_content_variation.
import { SEO_APPROACH_TYPES, SEO_APPROACH_TYPES_SET, MAX_VARIATIONS_PER_SEED, isValidApproachType as _isValidApproachType } from "../../shared/seo-approach-types.mjs";

// ── Structured logger (obs_baseline §Logging) ────────────────────────────────
const logger = createLogger("task-synchronizer-mcp");

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
      logger.warn("migrate", "state.json has unexpected version — skipping migration", { version: state.version });
      return;
    }
  } catch {
    logger.warn("migrate", "state.json parse error — skipping migration");
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

  logger.info("migrate", "imported state.json → state.sqlite");
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

// ── E-74: Cloud sync hook ────────────────────────────────────────────────────
// Per .ai/blueprints/managed-agents-state-reconciliation.md §Components 2:
// trigger the (debounced, fire-and-forget) Cloud Projection sync whenever a
// task is added or transitions status. The MCP response MUST NOT block on
// network — syncToCloud() returns a structured envelope synchronously and
// schedules the actual fetch under an unref()'d timer.
//
// Wired only into add_task + update_task_status (the two mutation paths
// that change the active-task projection). add_stamp / set_project_focus /
// mark_deltas_read / archive_done_tasks do not change the OPEN+BLOCKED set
// the cloud projects, so skipping them avoids needless network chatter.
function _scheduleCloudSync(targetAiDir) {
  try {
    const dbPath  = resolve(targetAiDir, "state.sqlite");
    const result  = _syncToCloud({ dbPath });
    // Surface unexpected envelopes to ops logs but never re-throw — the
    // MCP must be transparently functional when the cloud is down.
    if (result && result.status && result.status !== "DEBOUNCED" && result.status !== "DISABLED") {
      logger.warn("cloud-sync", "syncToCloud returned non-debounced envelope", {
        status: result.status,
        reason: result.reason,
      });
    }
  } catch (e) {
    logger.warn("cloud-sync", "syncToCloud threw — swallowed", { error: e.message });
  }
}

// ── Error messages ────────────────────────────────────────────────────────────

const STATE_MISSING_ERR = "✗ state.sqlite not found — run: ai init";
const DB_ERR = "✗ state.sqlite could not be opened";

// ── E-63: Framework workspace routing (task-routing.md) ──────────────────────
// When add_task receives is_framework_task: true, redirect persistence to the
// canonical AI-OS clone (process.env.AIOS_WORKSPACE) instead of the local
// project's .ai/. Honours AIOS_WORKSPACE_DISABLE=1 as an emergency override
// (rollback-plan.md): forces local persistence when cross-workspace writes
// misbehave. Returns either a string aiDir or an error envelope ready to
// return from the request handler.
function _resolveFrameworkAiDir() {
  if (process.env.AIOS_WORKSPACE_DISABLE === "1") {
    return {
      error: "[WORKSPACE_DISABLED] AIOS_WORKSPACE_DISABLE=1 — cross-workspace " +
             "writes are temporarily off. Either unset the variable or omit " +
             "is_framework_task and let the task land in the local .ai/.",
    };
  }
  const ws = (process.env.AIOS_WORKSPACE || "").trim();
  if (!ws) {
    return {
      error: "[WORKSPACE_NOT_FOUND] is_framework_task=true but AIOS_WORKSPACE " +
             "is unset. Re-run install-ai-os.sh from your AI-OS clone or " +
             "export AIOS_WORKSPACE=/path/to/ai-os-v2 manually.",
    };
  }
  // Defence-in-depth path validation (task-routing.md §Security):
  // - must be absolute (no relative-path traversal at the env layer)
  // - must contain a real .ai/ directory (the only thing we'll write to)
  if (!ws.startsWith("/")) {
    return {
      error: `[WORKSPACE_NOT_FOUND] AIOS_WORKSPACE='${ws}' is not absolute. ` +
             `Cross-workspace writes require an absolute path.`,
    };
  }
  const candidate = resolve(ws, ".ai");
  if (!existsSync(candidate)) {
    return {
      error: `[WORKSPACE_NOT_FOUND] AIOS_WORKSPACE='${ws}' has no .ai/ directory. ` +
             `Run 'ai init' inside the framework clone before routing framework tasks.`,
    };
  }
  return { aiDir: candidate };
}

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
      description: "Adds a new task to state with auto-assigned ID. Returns the new task. Set is_framework_task: true (E-63) to route the task to the canonical AI-OS clone at $AIOS_WORKSPACE instead of the local project's .ai/.",
      inputSchema: {
        type: "object",
        properties: {
          owner:             { type: "string",  description: "Task owner: 'Architect (Gemini)', 'Engineer (Claude)', or 'Tester (TestSprite)'" },
          description:       { type: "string",  description: "Task description" },
          tier:              { type: "number",  description: "Risk tier (1, 2, or 3)", enum: [1, 2, 3] },
          prefix:            { type: "string",  description: "ID prefix: P (architect), E (engineer), T (tester)", enum: ["P", "E", "T"], default: "E" },
          is_framework_task: { type: "boolean", description: "If true, persist into $AIOS_WORKSPACE/.ai (canonical AI-OS clone) instead of local .ai/. Errors with [WORKSPACE_NOT_FOUND] when AIOS_WORKSPACE is unset/invalid. (E-63)", default: false },
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
    // append_tasks intentionally removed from tool list — disabled (bypasses SQLite).
    // Call add_task instead.
    {
      name: "verify_markdown_sync",
      description: "Checks that TASKS.md and REVIEWS.md are in sync with state. Returns PASS or FAIL.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "validate_payload",
      description:
        "Validate a payload against a named AI-OS state transition schema before submitting it. " +
        "Schemas: task_create, task_update, stamp_add, project_update. " +
        "Returns SCHEMA_PASS or SCHEMA_FAIL with per-field error details. " +
        "Use before calling add_task, update_task_status, add_stamp, or set_project_focus to catch type errors early.",
      inputSchema: {
        type: "object",
        properties: {
          schema_name: {
            type: "string",
            enum: ["task_create", "task_update", "stamp_add", "project_update"],
            description: "Name of the schema to validate against.",
          },
          payload: {
            type: "object",
            description: "The JSON payload to validate.",
          },
        },
        required: ["schema_name", "payload"],
        additionalProperties: false,
      },
    },
    {
      name: "mark_deltas_read",
      description: "Marks implementation deltas as read after the Architect has incorporated them into architect.md. Pass specific task_ids to acknowledge selectively, or omit to acknowledge all unread deltas.",
      inputSchema: {
        type: "object",
        properties: {
          task_ids: {
            type: "array",
            items: { type: "string" },
            description: "Task IDs whose deltas to acknowledge (e.g. ['E-78', 'E-79']). Omit to acknowledge all unread.",
          },
        },
      },
    },
    // ── E-79: Multi-Variation-State-Tracker tools ─────────────────────────────
    // Backing tables (keyword_seeds, content_variations) live in state-db.js.
    // Wired here per .ai/blueprints/seo-keyword-multiplier.md §Components 3
    // + §API. Cloud sync hook does NOT fire from these — the managed-agents
    // projection contract (E-73 §Data Privacy) covers only tasks, not
    // SEO state.
    {
      name: "add_keyword_seed",
      description: "Register a new KeywordSeed (E-79). Returns an auto-assigned KS-N id. Use this once at the start of a multiplyKeyword(term) expansion in src/gemini/agents/seo_manager.md; the SEO-Content-Generator (E-78) then attaches up to 20 ContentVariations to it.",
      inputSchema: {
        type: "object",
        properties: {
          term:          { type: "string", description: "The keyword seed term (1..256 chars, no shell metachars)" },
          target_volume: { type: "number", description: "Target number of variations to generate (1..20, default 20)", default: 20 },
        },
        required: ["term"],
      },
    },
    {
      name: "add_content_variation",
      description: "Register a ContentVariation against an existing KeywordSeed (E-79). Refuses approach_type values outside the 20-canonical set defined in src/shared/seo-approach-types.mjs. Refuses to create variation #21 for a given seed_id (defence-in-depth on blueprint §Execution Constraints/Generation Limits).",
      inputSchema: {
        type: "object",
        properties: {
          seed_id:       { type: "string", description: "KeywordSeed id (e.g. 'KS-1')" },
          approach_type: { type: "string", description: "One of the 20 canonical slugs (listicle, how-to-guide, …, future-predictions)" },
          content_blob:  { type: "string", description: "Optional inline markdown body, or a relative repo path if content lives on disk" },
        },
        required: ["seed_id", "approach_type"],
      },
    },
    {
      name: "report_performance",
      description: "Update a ContentVariation.performance_metrics with new SEO metrics (E-79 reportPerformance API). Merges supplied keys into the existing JSON object — pass only the fields that changed.",
      inputSchema: {
        type: "object",
        properties: {
          variation_id: { type: "string", description: "ContentVariation id (e.g. 'CV-1')" },
          metrics:      { type: "object", description: "JSON merge patch — e.g. { clicks: 120, impressions: 4500, ctr: 0.027, position: 8.4 }" },
        },
        required: ["variation_id", "metrics"],
      },
    },
    {
      name: "get_seed_cohort",
      description: "Return a KeywordSeed plus every ContentVariation attached to it (E-79). Used by the SEO-Content-Generator (E-78) Step 4 duplicate-content gate and by the Architect to audit a seed's progress toward the 20-variation target.",
      inputSchema: {
        type: "object",
        properties: {
          seed_id: { type: "string", description: "KeywordSeed id (e.g. 'KS-1')" },
        },
        required: ["seed_id"],
      },
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

  // ── Schema validation helper ─────────────────────────────────────────────
  function _assertSchema(schemaName, payload) {
    const result = validateNamed(schemaName, payload);
    if (!result.valid) {
      return {
        content: [{
          type: "text",
          text: `[SCHEMA_FAIL] '${schemaName}' validation failed:\n` +
                result.errors.map(e => `  • ${e}`).join("\n") +
                "\n\nUse validate_payload to inspect the schema before submitting.",
        }],
        isError: true,
      };
    }
    return null; // valid
  }

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
      const _addTaskErr = _assertSchema("task_create", args);
      if (_addTaskErr) return _addTaskErr;

      // E-63: Resolve persistence target — local .ai/ or framework workspace
      // when is_framework_task is set. Each framework write opens its own DB
      // handle; the local `db` opened above is irrelevant in that branch.
      let targetAiDir = aiDir;
      let targetDb    = db;
      if (args.is_framework_task === true) {
        const fw = _resolveFrameworkAiDir();
        if (fw.error) {
          return { content: [{ type: "text", text: `✗ ${fw.error}` }], isError: true };
        }
        // Refuse to silently mirror a framework write back into the same .ai/
        // the request originated in — that would defeat the routing entirely
        // and we'd rather fail loudly than create the "appears to work" trap.
        if (fw.aiDir === aiDir) {
          // Same workspace — fall through with the existing handle, no-op routing.
          logger.info("add_task", "is_framework_task=true but workspace matches local .ai/", { aiDir });
        } else {
          targetAiDir = fw.aiDir;
          try {
            targetDb = _getDb(targetAiDir);
          } catch (e) {
            return {
              content: [{ type: "text", text: `✗ [WORKSPACE_NOT_FOUND] could not open framework state.sqlite at ${targetAiDir}: ${e.message}` }],
              isError: true,
            };
          }
        }
      }

      const prefix = args.prefix || "E";
      const id     = _nextId(targetDb, prefix);
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

      targetDb.prepare(`
        INSERT INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(task.id, task.owner, task.status, task.tier, task.description,
              task.created_at, task.completed_at, task.summary);

      _regenerateViews(targetAiDir, targetDb);
      // E-74: schedule cloud projection sync. Framework-routed tasks sync
      // the framework workspace's state.sqlite, not the local one — the
      // projection always reflects the workspace the row landed in.
      _scheduleCloudSync(targetAiDir);
      const routeSuffix = targetAiDir === aiDir ? "" : ` (routed to framework workspace ${targetAiDir})`;
      return { content: [{ type: "text", text: `✓ Added ${id}: ${args.description}${routeSuffix}\n${JSON.stringify(task, null, 2)}` }] };
    }

    // ── update_task_status ────────────────────────────────────────────────────
    case "update_task_status": {
      const _updateErr = _assertSchema("task_update", args);
      if (_updateErr) return _updateErr;
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
      // E-74: schedule cloud projection sync after the status transition.
      _scheduleCloudSync(aiDir);
      return { content: [{ type: "text", text: `✓ ${args.id} → ${args.status}${args.summary ? ": " + args.summary : ""}` }] };
    }

    // ── add_stamp ─────────────────────────────────────────────────────────────
    case "add_stamp": {
      const _stampErr = _assertSchema("stamp_add", args);
      if (_stampErr) return _stampErr;
      db.prepare(
        "INSERT INTO stamps(type, agent, task_id, timestamp, summary) VALUES (?, ?, ?, ?, ?)"
      ).run(args.type, args.agent ?? null, args.task_id ?? null,
             new Date().toISOString(), args.summary);

      _regenerateViews(aiDir, db);
      return { content: [{ type: "text", text: `✓ Stamp [${args.type}] added by ${args.agent}` }] };
    }

    // ── set_project_focus ─────────────────────────────────────────────────────
    case "set_project_focus": {
      const _focusErr = _assertSchema("project_update", args);
      if (_focusErr) return _focusErr;
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

      return { content: [{ type: "text", text: `## Proposed P-## Tasks\n\n${proposed.join("\n\n")}\n\nTo apply: use add_task directly:\n  add_task({ prefix: 'P', owner: 'Architect (Gemini)', description: '...', tier: N })` }] };
    }

    // ── REMOVED: append_tasks ─────────────────────────────────────────────────
    // This tool wrote directly to TASKS.md, bypassing state.sqlite entirely.
    // TASKS.md is now a generated view — hand-writing to it causes DB/file desync.
    case "append_tasks": {
      return {
        content: [{
          type: "text",
          text: "✗ append_tasks is disabled — it bypasses state.sqlite and causes desync.\n" +
                "Use add_task instead:\n" +
                "  add_task({ prefix: 'P', owner: 'Architect (Gemini)', description: '...', tier: 1 })\n" +
                "add_task writes to state.sqlite and regenerates TASKS.md, state.json, and REVIEWS.md atomically.",
        }],
        isError: true,
      };
    }

    // ── verify_markdown_sync ──────────────────────────────────────────────────
    case "verify_markdown_sync": {
      // Per blueprint state-sync-validation.md (E-60): cross-reference
      // TASKS.md checkboxes against state.sqlite per task. Catch the case
      // where the engineer ships a feature but forgets to mark the task
      // DONE — the count-only check would miss this when totals match.
      const anomalies = [];
      const autoFixes = [];
      const tasksPath   = resolve(aiDir, "TASKS.md");
      const reviewsPath = resolve(aiDir, "REVIEWS.md");

      if (existsSync(tasksPath)) {
        const tasksContent = readFileSync(tasksPath, "utf8");

        if (!tasksContent.startsWith("# TASKS (Generated from state.json)")) {
          anomalies.push("TASKS.md does not start with generated header — may have been hand-edited");
        }

        // Match: `- [x] E-54: ...` or `- [ ] P-27: ...`
        const lineRe  = /^- \[([ xX])\] ([A-Z]+-\d+):/gm;
        const mdTasks = new Map();   // id → 'DONE' | 'OPEN'
        let m;
        while ((m = lineRe.exec(tasksContent)) !== null) {
          mdTasks.set(m[2], m[1].trim().toLowerCase() === "x" ? "DONE" : "OPEN");
        }

        const dbTasks = new Map(
          db.prepare("SELECT id, status FROM tasks").all().map(t => [t.id, t.status])
        );

        // Drift type 1: in TASKS.md, missing from state
        // Drift type 2: checkbox disagrees with state status
        for (const [id, mdStatus] of mdTasks) {
          if (!dbTasks.has(id)) {
            anomalies.push(`${id} appears in TASKS.md (${mdStatus === "DONE" ? "[x]" : "[ ]"}) but is missing from state`);
            continue;
          }
          const dbStatus = dbTasks.get(id);
          if (mdStatus === "DONE" && dbStatus !== "DONE") {
            anomalies.push(`${id} is [x] in TASKS.md but ${dbStatus} in state`);
          } else if (mdStatus === "OPEN" && dbStatus === "DONE") {
            anomalies.push(`${id} is [ ] in TASKS.md but DONE in state`);
          }
        }

        // Drift type 3: in state, missing from TASKS.md
        for (const id of dbTasks.keys()) {
          if (!mdTasks.has(id)) {
            anomalies.push(`${id} exists in state but is missing from TASKS.md`);
          }
        }
      }

      // REVIEWS.md count-level safety net (auto-fix on stamp drift).
      const stampCount = db.prepare("SELECT COUNT(*) as n FROM stamps").get().n;
      if (existsSync(reviewsPath) && stampCount > 0) {
        const reviewsContent = readFileSync(reviewsPath, "utf8");
        const mdStampCount   = (reviewsContent.match(/^\[[\w_]+\]/gm) || []).length;
        if (mdStampCount < stampCount) {
          autoFixes.push(`REVIEWS.md had ${mdStampCount} stamps but state has ${stampCount} — regenerated`);
          _regenerateViews(aiDir, db);
        }
      }

      // Auto-regenerate TASKS.md when rows are missing from one side or
      // the other (anomalies still surface so the agent knows what was
      // fixed). Checkbox-mismatch anomalies are intentionally NOT
      // auto-fixed — they signal the engineer forgot to call
      // update_task_status, which is human/agent-decision territory.
      const hasMarkdownDrift = anomalies.some(a =>
        /missing from TASKS\.md|missing from state/.test(a)
      );
      if (hasMarkdownDrift) {
        _regenerateViews(aiDir, db);
        autoFixes.push("TASKS.md regenerated from state to resolve missing-row drift");
      }

      const status = anomalies.length === 0 ? "PASS" : "FAIL";
      const lines  = [`[SYNC_${status}] TASKS.md and REVIEWS.md vs state.sqlite`];

      if (anomalies.length > 0) {
        lines.push(`Anomalies (${anomalies.length}):`);
        anomalies.forEach(a => lines.push(`  • ${a}`));
      }
      if (autoFixes.length > 0) {
        lines.push(`Auto-fixes:`);
        autoFixes.forEach(a => lines.push(`  • ${a}`));
      }
      if (anomalies.length === 0 && autoFixes.length === 0) {
        lines[0] = "[SYNC_PASS] TASKS.md and REVIEWS.md are in sync with state.";
      }

      // Structured tail for programmatic consumers (skills, CI, hooks).
      lines.push("");
      lines.push(`__SYNC_RESULT__ ${JSON.stringify({ status, anomalies, auto_fixes: autoFixes })}`);

      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── validate_payload ──────────────────────────────────────────────────────
    case "validate_payload": {
      const schemaName = String(args.schema_name || "").trim();
      const payload    = args.payload;

      if (!schemaName) {
        return { content: [{ type: "text", text: "✗ schema_name is required." }], isError: true };
      }
      if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
        return { content: [{ type: "text", text: "✗ payload must be a JSON object." }], isError: true };
      }

      const result = validateNamed(schemaName, payload);
      if (result.valid) {
        return {
          content: [{
            type: "text",
            text: `[SCHEMA_PASS] '${schemaName}' — payload is valid.\n` +
                  `Payload: ${JSON.stringify(payload, null, 2)}`,
          }],
        };
      }
      return {
        content: [{
          type: "text",
          text: `[SCHEMA_FAIL] '${schemaName}' — ${result.errors.length} error(s):\n` +
                result.errors.map(e => `  • ${e}`).join("\n"),
        }],
        isError: true,
      };
    }

    // ── mark_deltas_read ──────────────────────────────────────────────────────
    case "mark_deltas_read": {
      const taskIds = Array.isArray(args.task_ids) && args.task_ids.length > 0
        ? args.task_ids.map(id => String(id).trim().toUpperCase())
        : null;

      let marked;
      if (taskIds) {
        const ph = taskIds.map(() => "?").join(",");
        marked = db.prepare(
          `UPDATE deltas SET read = 1 WHERE read = 0 AND task_id IN (${ph})`
        ).run(...taskIds).changes;
      } else {
        marked = db.prepare("UPDATE deltas SET read = 1 WHERE read = 0").run().changes;
      }

      if (marked > 0) _regenerateViews(aiDir, db);

      const scope = taskIds ? taskIds.join(", ") : "all unread";
      return {
        content: [{
          type: "text",
          text: marked > 0
            ? `✓ Acknowledged ${marked} delta(s) for ${scope}.`
            : `⚠ No unread deltas found${taskIds ? ` for ${scope}` : ""}.`,
        }],
      };
    }

    // ── E-79 Multi-Variation-State-Tracker handlers ───────────────────────────
    // All four operate on the local aiDir's state.sqlite only (no framework
    // routing — SEO state is project-scoped). No cloud sync fires from these
    // mutations per E-73 Data-Privacy contract (only tasks cross the boundary).

    case "add_keyword_seed": {
      const term = typeof args.term === "string" ? args.term.trim() : "";
      if (term.length === 0 || term.length > 256) {
        return { content: [{ type: "text", text: "✗ [INVALID_KEYWORD_TERM] term must be 1..256 chars" }], isError: true };
      }
      // Reject shell metacharacters (mirrors seo_manager.md Preflight #3).
      if (/[;&|`$()<>\n\r]/.test(term)) {
        return { content: [{ type: "text", text: "✗ [INVALID_KEYWORD_TERM] term contains shell metacharacters" }], isError: true };
      }
      const targetVolume = Number.isFinite(args.target_volume) ? Math.floor(args.target_volume) : 20;
      if (targetVolume < 1 || targetVolume > MAX_VARIATIONS_PER_SEED) {
        return { content: [{ type: "text", text: `✗ [INVALID_TARGET_VOLUME] must be 1..${MAX_VARIATIONS_PER_SEED}` }], isError: true };
      }
      const id = _nextKeywordSeedId(db);
      const createdAt = new Date().toISOString();
      db.prepare(
        "INSERT INTO keyword_seeds(id, term, status, target_volume, created_at, completed_at) VALUES (?, ?, ?, ?, ?, NULL)"
      ).run(id, term, "OPEN", targetVolume, createdAt);
      return {
        content: [{
          type: "text",
          text: `✓ Added KeywordSeed ${id}: "${term}" (target_volume=${targetVolume})\n` +
                JSON.stringify({ id, term, status: "OPEN", target_volume: targetVolume, created_at: createdAt }, null, 2),
        }],
      };
    }

    case "add_content_variation": {
      const seedId = String(args.seed_id || "").trim();
      const approach = String(args.approach_type || "").trim();
      if (!/^KS-\d+$/.test(seedId)) {
        return { content: [{ type: "text", text: "✗ [INVALID_SEED_ID] expected format KS-N" }], isError: true };
      }
      if (!_isValidApproachType(approach)) {
        return {
          content: [{
            type: "text",
            text: `✗ [UNKNOWN_APPROACH_TYPE] '${approach}' is not in the 20-canonical set. Valid: ${SEO_APPROACH_TYPES.join(", ")}`,
          }],
          isError: true,
        };
      }
      const seedRow = db.prepare("SELECT id FROM keyword_seeds WHERE id = ?").get(seedId);
      if (!seedRow) {
        return { content: [{ type: "text", text: `✗ [SEED_NOT_FOUND] KeywordSeed '${seedId}' does not exist. Call add_keyword_seed first.` }], isError: true };
      }
      // Defence-in-depth: enforce the 20-cap at the storage layer even if
      // upstream (seo_manager E-77) miscounts. Blueprint §Execution
      // Constraints/Generation Limits is hard.
      const sibCount = db.prepare(
        "SELECT COUNT(*) as n FROM content_variations WHERE seed_id = ?"
      ).get(seedId).n;
      if (sibCount >= MAX_VARIATIONS_PER_SEED) {
        return { content: [{ type: "text", text: `✗ [VARIATION_CAP_REACHED] seed ${seedId} already has ${sibCount}/${MAX_VARIATIONS_PER_SEED} variations` }], isError: true };
      }
      // Refuse duplicate (seed_id, approach_type) — the 20 canonical types
      // are each unique within a seed. The blueprint says "20 unique
      // article structures" — uniqueness includes the structure label.
      const dup = db.prepare(
        "SELECT id FROM content_variations WHERE seed_id = ? AND approach_type = ?"
      ).get(seedId, approach);
      if (dup) {
        return { content: [{ type: "text", text: `✗ [APPROACH_ALREADY_USED] ${seedId} already has approach '${approach}' (variation ${dup.id})` }], isError: true };
      }

      const id = _nextContentVariationId(db);
      const createdAt = new Date().toISOString();
      const blob = typeof args.content_blob === "string" ? args.content_blob : null;
      db.prepare(
        "INSERT INTO content_variations(id, seed_id, approach_type, content_blob, performance_metrics, published_at, created_at) VALUES (?, ?, ?, ?, NULL, NULL, ?)"
      ).run(id, seedId, approach, blob, createdAt);

      return {
        content: [{
          type: "text",
          text: `✓ Added ContentVariation ${id} for ${seedId} [${approach}]\n` +
                JSON.stringify({ id, seed_id: seedId, approach_type: approach, created_at: createdAt }, null, 2),
        }],
      };
    }

    case "report_performance": {
      const vid = String(args.variation_id || "").trim();
      if (!/^CV-\d+$/.test(vid)) {
        return { content: [{ type: "text", text: "✗ [INVALID_VARIATION_ID] expected format CV-N" }], isError: true };
      }
      if (!args.metrics || typeof args.metrics !== "object" || Array.isArray(args.metrics)) {
        return { content: [{ type: "text", text: "✗ [INVALID_METRICS] metrics must be a JSON object" }], isError: true };
      }
      const row = db.prepare(
        "SELECT id, performance_metrics FROM content_variations WHERE id = ?"
      ).get(vid);
      if (!row) {
        return { content: [{ type: "text", text: `✗ [VARIATION_NOT_FOUND] ${vid}` }], isError: true };
      }
      // Merge-patch semantics: existing JSON + supplied keys; new keys
      // overwrite. Mirrors the JSON merge contract documented in the tool's
      // inputSchema description.
      let existing = {};
      if (row.performance_metrics) {
        try { existing = JSON.parse(row.performance_metrics); } catch { existing = {}; }
      }
      const merged = { ...existing, ...args.metrics };
      db.prepare(
        "UPDATE content_variations SET performance_metrics = ? WHERE id = ?"
      ).run(JSON.stringify(merged), vid);
      return {
        content: [{
          type: "text",
          text: `✓ Updated ${vid} performance_metrics\n` + JSON.stringify(merged, null, 2),
        }],
      };
    }

    case "get_seed_cohort": {
      const seedId = String(args.seed_id || "").trim();
      if (!/^KS-\d+$/.test(seedId)) {
        return { content: [{ type: "text", text: "✗ [INVALID_SEED_ID] expected format KS-N" }], isError: true };
      }
      const seed = db.prepare(
        "SELECT id, term, status, target_volume, created_at, completed_at FROM keyword_seeds WHERE id = ?"
      ).get(seedId);
      if (!seed) {
        return { content: [{ type: "text", text: `✗ [SEED_NOT_FOUND] ${seedId}` }], isError: true };
      }
      const variations = db.prepare(
        "SELECT id, approach_type, content_blob, performance_metrics, published_at, created_at FROM content_variations WHERE seed_id = ? ORDER BY id"
      ).all(seedId).map((v) => ({
        id:                  v.id,
        approach_type:       v.approach_type,
        content_blob:        v.content_blob,
        performance_metrics: v.performance_metrics ? JSON.parse(v.performance_metrics) : null,
        published_at:        v.published_at,
        created_at:          v.created_at,
      }));
      const remaining = Math.max(0, seed.target_volume - variations.length);
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            seed,
            variations,
            counts: {
              total:     variations.length,
              remaining,
              published: variations.filter((v) => v.published_at != null).length,
            },
          }, null, 2),
        }],
      };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
