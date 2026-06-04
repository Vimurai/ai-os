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
import { readFileSync, writeFileSync, existsSync, mkdirSync, rmdirSync } from "fs";
import { resolve } from "path";
import { getDb, readState as _readState, regenerateViews as _regenerateViews, nextId as _nextId, recordIdHighWater as _recordIdHighWater, nextTopicSeedId as _nextTopicSeedId, nextClusterPageId as _nextClusterPageId, validateDag as _validateDag, readDependencyGraph as _readDependencyGraph, parseDeps as _parseDeps, archiveDoneTasks as _archiveDoneTasks, archiveStamps as _archiveStamps, DONE_ARCHIVE_THRESHOLD, DONE_KEEP_RECENT, STAMP_ARCHIVE_THRESHOLD } from "../shared/state-db.js";
import { buildToolSchemas } from "./tool-schemas.mjs";
import { validateNamed, loadSchemas } from "../../shared/schema-validator.js";
import { createLogger } from "../shared/logger.js";
// E-74: Managed Agents cloud sync hook. The import is unconditional (cheap —
// no side effects at module load), but every call site goes through
// syncToCloud() which short-circuits to {status:"DISABLED"} when
// AI_MANAGED_AGENTS_ENABLE is unset. Local MCP behaviour is unchanged off.
import { syncToCloud as _syncToCloud } from "../../shared/managed-agents-client.mjs";
// E-88: Multi-Variation-State-Tracker — canonical SEO Topic Cluster intents.
// Used to validate ClusterPage.intent_type and enforce the cluster-page cap
// on add_cluster_page.
import { SEO_ALL_INTENTS, SEO_PILLAR_INTENT, MAX_CLUSTER_PAGES_PER_SEED, isValidIntentType as _isValidIntentType, isClusterIntent as _isClusterIntent } from "../../shared/seo-cluster-intents.mjs";

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
    INSERT OR IGNORE INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary, depends_on)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  for (const t of (state.tasks || [])) {
    // E-91: preserve dependency edges across the one-time JSON→SQLite import.
    const deps = Array.isArray(t.depends_on) ? t.depends_on : [];
    insertTask.run(t.id, t.owner, t.status, t.tier ?? null,
                   t.description, t.created_at, t.completed_at ?? null, t.summary ?? null,
                   deps.length ? JSON.stringify(deps) : null);
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
// E-111: archive rotation for DONE tasks + audit stamps (and its thresholds) now
// lives in src/mcp/shared/state-db.js so task-synchronizer-mcp and
// archive-manager-mcp share ONE implementation. _archiveDoneTasks / _archiveStamps
// and the *_THRESHOLD constants are imported above.

// E-107 (token-optimization.md §Components 1 / §Data Model): cap a DONE task's
// stored summary so state.json stays light. The full narrative lives in LOG.md
// (Engineer-managed). Rollback: set AI_OS_SUMMARY_CAP=2000.
const SUMMARY_CAP = Number(process.env.AI_OS_SUMMARY_CAP) || 200;

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
  tools: buildToolSchemas({ DONE_KEEP_RECENT, DONE_ARCHIVE_THRESHOLD }),
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
        // E-91: readiness is computed against ALL tasks — a dependency may sit
        // outside the filtered subset — so build a global status map first.
        const statusAll = new Map(
          db.prepare("SELECT id, status FROM tasks").all().map(r => [r.id, r.status])
        );
        const tasks = db.prepare(sql + " ORDER BY rowid").all(...params)
          .filter(t => !args.owner || t.owner?.toLowerCase().includes(args.owner.toLowerCase()))
          .map(t => {
            const depends_on = _parseDeps(t.depends_on);
            const blocked_by = depends_on.filter(d => statusAll.get(d) !== "DONE");
            return { ...t, depends_on, ready: blocked_by.length === 0, blocked_by };
          });
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
      const id     = _nextId(targetDb, prefix, targetAiDir);

      // E-91: validate the dependency edges before insert (existence, no
      // self-reference, acyclic, depth <= 5). A new task starts BLOCKED when
      // any dependency is not yet DONE, otherwise OPEN.
      const deps = [...new Set(Array.isArray(args.depends_on) ? args.depends_on : [])];
      if (deps.length) {
        const dag = _validateDag(targetDb, id, deps);
        if (!dag.ok) {
          return { content: [{ type: "text", text: `✗ [${dag.code}] ${dag.error}` }], isError: true };
        }
      }
      const allDepsDone = deps.every(d => {
        const r = targetDb.prepare("SELECT status FROM tasks WHERE id = ?").get(d);
        return r && r.status === "DONE";
      });
      const initialStatus = deps.length && !allDepsDone ? "BLOCKED" : "OPEN";

      const task   = {
        id,
        owner:        args.owner,
        status:       initialStatus,
        tier:         args.tier || null,
        description:  args.description,
        created_at:   new Date().toISOString(),
        completed_at: null,
        summary:      null,
        depends_on:   deps,
      };

      targetDb.prepare(`
        INSERT INTO tasks(id, owner, status, tier, description, created_at, completed_at, summary, depends_on)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(task.id, task.owner, task.status, task.tier, task.description,
              task.created_at, task.completed_at, task.summary,
              deps.length ? JSON.stringify(deps) : null);

      // E-109: advance the per-prefix high-water mark only now that the row is
      // committed, so a rejected add_task never burns an id.
      _recordIdHighWater(targetDb, task.id);

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
      const row = db.prepare("SELECT id, status FROM tasks WHERE id = ?").get(args.id);
      if (!row) {
        return { content: [{ type: "text", text: `✗ Task '${args.id}' not found.` }], isError: true };
      }

      // E-101 (sovereignty-hardening.md §Components 2): immutability lock on DONE
      // tasks. A task already in DONE status cannot be re-transitioned unless the
      // caller explicitly passes reopen:true — this prevents accidental mutation
      // of completed implementation history. Rollback: AI_OS_SOVEREIGNTY_LOCK=0.
      if (row.status === "DONE" && args.reopen !== true && process.env.AI_OS_SOVEREIGNTY_LOCK !== "0") {
        return {
          content: [{ type: "text", text: `✗ [TASK_LOCKED] '${args.id}' is DONE and cannot be mutated. Pass reopen:true to override (sovereignty-hardening.md §Components 2), or set AI_OS_SOVEREIGNTY_LOCK=0 to disable the lock.` }],
          isError: true,
        };
      }

      // E-91: optional dependency revision — validate the new edge set
      // (existence/self-reference/cycle/depth) before persisting it.
      if (args.depends_on !== undefined) {
        const deps = [...new Set(Array.isArray(args.depends_on) ? args.depends_on : [])];
        const dag  = _validateDag(db, args.id, deps);
        if (!dag.ok) {
          return { content: [{ type: "text", text: `✗ [${dag.code}] ${dag.error}` }], isError: true };
        }
        db.prepare("UPDATE tasks SET depends_on = ? WHERE id = ?")
          .run(deps.length ? JSON.stringify(deps) : null, args.id);
      }

      // E-107: cap the stored summary at SUMMARY_CAP chars. The full narrative
      // belongs in LOG.md (Engineer-managed); state keeps a capped reference.
      let storedSummary = args.summary ?? null;
      let summaryTruncated = false;
      if (typeof storedSummary === "string" && storedSummary.length > SUMMARY_CAP) {
        const suffix = " …[full in LOG.md]";
        storedSummary = storedSummary.slice(0, Math.max(0, SUMMARY_CAP - suffix.length)).trimEnd() + suffix;
        summaryTruncated = true;
      }

      if (args.status === "DONE") {
        db.prepare("UPDATE tasks SET status = ?, completed_at = ?, summary = ? WHERE id = ?")
          .run(args.status, new Date().toISOString(), storedSummary, args.id);
      } else {
        db.prepare("UPDATE tasks SET status = ? WHERE id = ?").run(args.status, args.id);
      }

      // E-91: DAG unblock cascade. When a task becomes DONE, any BLOCKED task
      // whose entire depends_on set is now satisfied transitions to OPEN so the
      // Orchestrator (E-92) can dispatch it. The graph is read AFTER the status
      // write so `args.id` already counts as DONE.
      const unblocked = [];
      if (args.status === "DONE") {
        const { deps: graph, status } = _readDependencyGraph(db);
        for (const [tid, tdeps] of graph) {
          if (status.get(tid) === "BLOCKED" && tdeps.includes(args.id) &&
              tdeps.every(d => status.get(d) === "DONE")) {
            db.prepare("UPDATE tasks SET status = 'OPEN' WHERE id = ?").run(tid);
            unblocked.push(tid);
          }
        }
      }

      _regenerateViews(aiDir, db);
      // E-74: schedule cloud projection sync after the status transition.
      _scheduleCloudSync(aiDir);
      const unblockNote = unblocked.length ? ` | unblocked: ${unblocked.join(", ")}` : "";
      const truncNote   = summaryTruncated ? ` | [SUMMARY_TRUNCATED] summary capped at ${SUMMARY_CAP} chars — keep the full narrative in LOG.md` : "";
      return { content: [{ type: "text", text: `✓ ${args.id} → ${args.status}${storedSummary ? ": " + storedSummary : ""}${unblockNote}${truncNote}` }] };
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

    // ── handoff_control (E-114/E-118, interactive-bridge.md) ────────────────────
    // Emit a structured signal to .ai/signal.json so the `ai watch` tmux watcher
    // can wake the target agent's pane. E-118: signal.json is a QUEUE (array) —
    // the entry is APPENDED, never overwritten, so a busy agent never loses a
    // pending handoff. Legacy flat-object payloads (E-114) are migrated in place;
    // a corrupt/unreadable queue is safely reset (interactive-bridge.md §Execution
    // Constraints). This MCP only writes JSON (no shell) — the watcher escapes the
    // message before `tmux send-keys`.
    case "handoff_control": {
      const target = args.target;
      if (target !== "claude" && target !== "gemini") {
        return { content: [{ type: "text", text: "✗ [INVALID_TARGET] target must be 'claude' or 'gemini'." }], isError: true };
      }
      const message = typeof args.message === "string" ? args.message.trim() : "";
      if (!message) {
        return { content: [{ type: "text", text: "✗ [EMPTY_MESSAGE] a non-empty message is required." }], isError: true };
      }
      // delivered:false makes the pending state explicit per interactive-bridge.md
      // §API (E-124). ai-watch treats absent OR false identically as undelivered,
      // so this is purely for self-documenting queue state / blueprint fidelity.
      const entry = { timestamp: new Date().toISOString(), target, message, delivered: false };
      const signalPath = resolve(aiDir, "signal.json");
      const lockPath = signalPath + ".lock";
      const MAX_QUEUE = 50; // bound growth — `ai watch` consumes via per-entry delivered flags.
      // Short-lived write lock SHARED with ai-watch's _signal_lock (same ".lock"
      // path) so this append and the watcher's delivered-flag write are serialised
      // — neither clobbers the other (interactive-bridge.md §Execution Constraints).
      // Bounded synchronous spin (~0.5s) then proceed best-effort rather than block
      // the MCP. Atomics.wait gives a sync sleep without busy-spinning the loop.
      const _sleepMs = (ms) => { try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); } catch { /* SAB unavailable → no wait */ } };
      let _lockHeld = false;
      for (let i = 0; i < 25; i++) {
        try { mkdirSync(lockPath); _lockHeld = true; break; } catch { _sleepMs(20); }
      }
      try {
        let queue = [];
        if (existsSync(signalPath)) {
          try {
            const parsed = JSON.parse(readFileSync(signalPath, "utf8"));
            if (Array.isArray(parsed)) queue = parsed;
            else if (parsed && typeof parsed === "object") queue = [parsed]; // legacy → queue
          } catch { queue = []; } // corrupt → safely reset rather than throw
        }
        queue.push(entry);
        // Bound growth WITHOUT ever dropping an undelivered handoff: evict only the
        // OLDEST delivered entries (delivered === true). If undelivered entries alone
        // exceed MAX_QUEUE (a stuck/absent agent), the queue is allowed to exceed the
        // cap rather than silently lose a pending signal.
        if (queue.length > MAX_QUEUE) {
          const deliveredOverflow = queue.filter((e) => e && e.delivered === true).length;
          let toDrop = Math.min(queue.length - MAX_QUEUE, deliveredOverflow);
          if (toDrop > 0) {
            queue = queue.filter((e) => {
              if (toDrop > 0 && e && e.delivered === true) { toDrop--; return false; }
              return true;
            });
          }
        }
        try {
          writeFileSync(signalPath, JSON.stringify(queue, null, 2) + "\n", "utf8");
        } catch (e) {
          return { content: [{ type: "text", text: `✗ [SIGNAL_WRITE_FAILED] ${e.message}` }], isError: true };
        }
        return { content: [{ type: "text", text: `✓ [HANDOFF] → ${target} (queued #${queue.length}): ${message}\n  signal: ${signalPath}` }] };
      } finally {
        if (_lockHeld) { try { rmdirSync(lockPath); } catch { /* already gone */ } }
      }
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
      // E-108: rotate BOTH DONE tasks and audit stamps. They have independent
      // thresholds, so a run may archive one, the other, both, or neither.
      const taskResult  = _archiveDoneTasks(aiDir, db);
      const stampResult = _archiveStamps(aiDir, db);
      const archived_tasks  = taskResult  ? taskResult.archived  : 0;
      const archived_stamps = stampResult ? stampResult.archived : 0;

      if (!taskResult && !stampResult) {
        const doneCount  = db.prepare("SELECT COUNT(*) as n FROM tasks WHERE status = 'DONE'").get().n;
        const stampCount = db.prepare("SELECT COUNT(*) as n FROM stamps").get().n;
        return { content: [{ type: "text", text: `✓ No archive needed — ${doneCount} DONE tasks (threshold ${DONE_ARCHIVE_THRESHOLD}), ${stampCount} stamps (threshold ${STAMP_ARCHIVE_THRESHOLD})` }] };
      }

      const archivePath = (stampResult && stampResult.archivePath) || (taskResult && taskResult.archivePath) || null;
      const lines = ["✓ [AUTO-ARCHIVE]"];
      if (taskResult)  lines.push(`  ${taskResult.archived} DONE tasks → ${taskResult.archivePath} (${taskResult.kept} recent kept)`);
      if (stampResult) lines.push(`  ${stampResult.archived} stamps → ${stampResult.archivePath} (${stampResult.kept} recent kept)`);
      lines.push(`  ${JSON.stringify({ archived_tasks, archived_stamps, archivePath })}`);
      return { content: [{ type: "text", text: lines.join("\n") }] };
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

    // ── E-88 Multi-Variation-State-Tracker handlers (Topic Cluster Engine) ────
    // All four operate on the local aiDir's state.sqlite only (no framework
    // routing — SEO state is project-scoped). No cloud sync fires from these
    // mutations per E-73 Data-Privacy contract (only tasks cross the boundary).

    case "add_topic_seed": {
      const term = typeof args.term === "string" ? args.term.trim() : "";
      if (term.length === 0 || term.length > 256) {
        return { content: [{ type: "text", text: "✗ [INVALID_TOPIC_TERM] term must be 1..256 chars" }], isError: true };
      }
      // Reject shell metacharacters (mirrors seo_manager.md Preflight #3).
      if (/[;&|`$()<>\n\r]/.test(term)) {
        return { content: [{ type: "text", text: "✗ [INVALID_TOPIC_TERM] term contains shell metacharacters" }], isError: true };
      }
      const targetVolume = Number.isFinite(args.target_volume) ? Math.floor(args.target_volume) : MAX_CLUSTER_PAGES_PER_SEED;
      if (targetVolume < 1 || targetVolume > MAX_CLUSTER_PAGES_PER_SEED) {
        return { content: [{ type: "text", text: `✗ [INVALID_TARGET_VOLUME] must be 1..${MAX_CLUSTER_PAGES_PER_SEED}` }], isError: true };
      }
      const id = _nextTopicSeedId(db);
      const createdAt = new Date().toISOString();
      db.prepare(
        "INSERT INTO topic_seeds(id, term, status, target_volume, created_at, completed_at) VALUES (?, ?, ?, ?, ?, NULL)"
      ).run(id, term, "OPEN", targetVolume, createdAt);
      return {
        content: [{
          type: "text",
          text: `✓ Added TopicSeed ${id}: "${term}" (target_volume=${targetVolume})\n` +
                JSON.stringify({ id, term, status: "OPEN", target_volume: targetVolume, created_at: createdAt }, null, 2),
        }],
      };
    }

    case "add_cluster_page": {
      const seedId = String(args.seed_id || "").trim();
      const intent = String(args.intent_type || "").trim();
      if (!/^TS-\d+$/.test(seedId)) {
        return { content: [{ type: "text", text: "✗ [INVALID_SEED_ID] expected format TS-N" }], isError: true };
      }
      if (!_isValidIntentType(intent)) {
        return {
          content: [{
            type: "text",
            text: `✗ [UNKNOWN_INTENT_TYPE] '${intent}' is not a canonical cluster intent. Valid: ${SEO_ALL_INTENTS.join(", ")}`,
          }],
          isError: true,
        };
      }
      const seedRow = db.prepare("SELECT id FROM topic_seeds WHERE id = ?").get(seedId);
      if (!seedRow) {
        return { content: [{ type: "text", text: `✗ [SEED_NOT_FOUND] TopicSeed '${seedId}' does not exist. Call add_topic_seed first.` }], isError: true };
      }
      // Cannibalization guard: refuse a duplicate (seed_id, intent_type) —
      // every page in a cluster MUST target a unique, non-overlapping intent.
      const dup = db.prepare(
        "SELECT id FROM cluster_pages WHERE seed_id = ? AND intent_type = ?"
      ).get(seedId, intent);
      if (dup) {
        return { content: [{ type: "text", text: `✗ [INTENT_ALREADY_USED] ${seedId} already has intent '${intent}' (page ${dup.id})` }], isError: true };
      }
      // Defence-in-depth: enforce the lifted cluster-page cap at the storage
      // layer even if upstream (seo_manager E-87) miscounts. The Pillar page
      // does not count against the cap — only deep-dive Cluster pages do.
      if (_isClusterIntent(intent)) {
        const clusterCount = db.prepare(
          `SELECT COUNT(*) as n FROM cluster_pages WHERE seed_id = ? AND intent_type != ?`
        ).get(seedId, SEO_PILLAR_INTENT).n;
        if (clusterCount >= MAX_CLUSTER_PAGES_PER_SEED) {
          return { content: [{ type: "text", text: `✗ [CLUSTER_CAP_REACHED] seed ${seedId} already has ${clusterCount}/${MAX_CLUSTER_PAGES_PER_SEED} cluster pages` }], isError: true };
        }
      }

      const id = _nextClusterPageId(db);
      const createdAt = new Date().toISOString();
      const blob = typeof args.content_blob === "string" ? args.content_blob : null;
      db.prepare(
        "INSERT INTO cluster_pages(id, seed_id, intent_type, content_blob, performance_metrics, published_at, created_at) VALUES (?, ?, ?, ?, NULL, NULL, ?)"
      ).run(id, seedId, intent, blob, createdAt);

      return {
        content: [{
          type: "text",
          text: `✓ Added ClusterPage ${id} for ${seedId} [${intent}]\n` +
                JSON.stringify({ id, seed_id: seedId, intent_type: intent, created_at: createdAt }, null, 2),
        }],
      };
    }

    case "report_performance": {
      const pid = String(args.page_id || "").trim();
      if (!/^CP-\d+$/.test(pid)) {
        return { content: [{ type: "text", text: "✗ [INVALID_PAGE_ID] expected format CP-N" }], isError: true };
      }
      if (!args.metrics || typeof args.metrics !== "object" || Array.isArray(args.metrics)) {
        return { content: [{ type: "text", text: "✗ [INVALID_METRICS] metrics must be a JSON object" }], isError: true };
      }
      const row = db.prepare(
        "SELECT id, performance_metrics FROM cluster_pages WHERE id = ?"
      ).get(pid);
      if (!row) {
        return { content: [{ type: "text", text: `✗ [PAGE_NOT_FOUND] ${pid}` }], isError: true };
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
        "UPDATE cluster_pages SET performance_metrics = ? WHERE id = ?"
      ).run(JSON.stringify(merged), pid);
      return {
        content: [{
          type: "text",
          text: `✓ Updated ${pid} performance_metrics\n` + JSON.stringify(merged, null, 2),
        }],
      };
    }

    case "get_topic_cluster": {
      const seedId = String(args.seed_id || "").trim();
      if (!/^TS-\d+$/.test(seedId)) {
        return { content: [{ type: "text", text: "✗ [INVALID_SEED_ID] expected format TS-N" }], isError: true };
      }
      const seed = db.prepare(
        "SELECT id, term, status, target_volume, created_at, completed_at FROM topic_seeds WHERE id = ?"
      ).get(seedId);
      if (!seed) {
        return { content: [{ type: "text", text: `✗ [SEED_NOT_FOUND] ${seedId}` }], isError: true };
      }
      const pages = db.prepare(
        "SELECT id, intent_type, content_blob, performance_metrics, published_at, created_at FROM cluster_pages WHERE seed_id = ? ORDER BY id"
      ).all(seedId).map((p) => ({
        id:                  p.id,
        intent_type:         p.intent_type,
        content_blob:        p.content_blob,
        performance_metrics: p.performance_metrics ? JSON.parse(p.performance_metrics) : null,
        published_at:        p.published_at,
        created_at:          p.created_at,
      }));
      const clusterPages = pages.filter((p) => p.intent_type !== SEO_PILLAR_INTENT);
      const remaining = Math.max(0, seed.target_volume - clusterPages.length);
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            seed,
            pages,
            counts: {
              total:     pages.length,
              pillar:    pages.filter((p) => p.intent_type === SEO_PILLAR_INTENT).length,
              cluster:   clusterPages.length,
              remaining,
              published: pages.filter((p) => p.published_at != null).length,
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
