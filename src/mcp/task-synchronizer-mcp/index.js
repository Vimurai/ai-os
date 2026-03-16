#!/usr/bin/env node
/**
 * task-synchronizer-mcp — AI-OS Exclusive State Mutator
 * Manages .ai/state.json as the authoritative project state.
 * Regenerates TASKS.md and REVIEWS.md as markdown views after every mutation.
 *
 * Tools:
 *   get_state()                        → returns full state.json
 *   add_task(owner, description, tier)  → adds task, auto-assigns ID
 *   update_task_status(id, status)      → transitions task status
 *   add_stamp(task_id, type, agent, summary) → writes atomic audit stamp
 *   set_project_focus(text)             → updates project focus
 *   sync_tasks(update_content?)         → (legacy) proposes P-## tasks from UPDATE.md
 *   append_tasks(tasks)                 → (legacy) appends to TASKS.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { resolve } from "path";

// ── Helpers ───────────────────────────────────────────────────────────────────
function getAiDir() {
  return resolve(process.cwd(), ".ai");
}

// readState: used by get_state — auto-initializes empty template if missing
function readState(aiDir) {
  const p = resolve(aiDir, "state.json");
  if (!existsSync(p)) {
    return { version: "1.0", project: { current_tier: null, release_verdict: null, focus: null }, tasks: [], stamps: [] };
  }
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; }
}

// readStateStrict: used by write tools — returns null (error) if state.json is missing
// P-44: prevents silent creation of empty state that bypasses migration
function readStateStrict(aiDir) {
  const p = resolve(aiDir, "state.json");
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; }
}

const DONE_ARCHIVE_THRESHOLD = 50; // auto-archive when DONE tasks exceed this
const DONE_KEEP_RECENT = 10;       // keep this many recent DONE tasks in live state

// archiveDoneTasks: moves old DONE tasks to .ai/archive/state-done-YYYYMM.json
// Returns { archived: number, kept: number } or null if below threshold
function archiveDoneTasks(aiDir, state) {
  const done = state.tasks.filter(t => t.status === "DONE");
  if (done.length <= DONE_ARCHIVE_THRESHOLD) return null;

  const toArchive = done.slice(0, done.length - DONE_KEEP_RECENT);
  const toKeep    = done.slice(done.length - DONE_KEEP_RECENT);
  const open      = state.tasks.filter(t => t.status !== "DONE");

  // Write archive file
  const ym = new Date().toISOString().slice(0, 7); // YYYY-MM
  const archiveDir = resolve(aiDir, "archive");
  mkdirSync(archiveDir, { recursive: true });
  const archivePath = resolve(archiveDir, `state-done-${ym}.json`);

  let existing = [];
  if (existsSync(archivePath)) {
    try { existing = JSON.parse(readFileSync(archivePath, "utf8")); } catch { existing = []; }
  }
  writeFileSync(archivePath, JSON.stringify([...existing, ...toArchive], null, 2) + "\n", "utf8");

  // Prune live state
  state.tasks = [...open, ...toKeep];
  writeState(aiDir, state);

  return { archived: toArchive.length, kept: toKeep.length, archivePath };
}

const STATE_MISSING_ERR = "✗ state.json not found — run: ai init or ai migrate-state";
const STATE_CORRUPT_ERR = "✗ state.json is corrupt — run: ai migrate-state to rebuild";

function writeState(aiDir, state) {
  const p = resolve(aiDir, "state.json");
  writeFileSync(p, JSON.stringify(state, null, 2) + "\n", "utf8");
  regenerateMarkdown(aiDir, state);
}

function nextId(tasks, prefix) {
  const nums = tasks
    .filter(t => t.id.startsWith(prefix + "-"))
    .map(t => parseInt(t.id.split("-")[1], 10))
    .filter(n => !isNaN(n));
  const max = nums.length > 0 ? Math.max(...nums) : 0;
  return `${prefix}-${max + 1}`;
}

// ── Markdown View Generator (E-80) ───────────────────────────────────────────
function regenerateMarkdown(aiDir, state) {
  // Regenerate TASKS.md view
  const tasksPath = resolve(aiDir, "TASKS.md");
  // Only regenerate if state has tasks (avoid clobbering during migration)
  if (state.tasks.length > 0) {
    const lines = ["# TASKS (Generated from state.json)", ""];

    // Group by owner
    const byOwner = {};
    for (const t of state.tasks) {
      const owner = t.owner || "Unassigned";
      if (!byOwner[owner]) byOwner[owner] = [];
      byOwner[owner].push(t);
    }

    for (const [owner, tasks] of Object.entries(byOwner)) {
      lines.push(`## ${owner}`);
      for (const t of tasks) {
        const check = t.status === "DONE" ? "x" : " ";
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

  // Regenerate REVIEWS.md view from stamps
  if (state.stamps.length > 0) {
    const reviewsPath = resolve(aiDir, "REVIEWS.md");
    const stampLines = ["# REVIEWS.md (Generated from state.json)", ""];
    for (const s of state.stamps) {
      const date = s.timestamp ? s.timestamp.split("T")[0] : "unknown";
      stampLines.push(`[${s.type}] ${date} | ${s.summary || s.agent || ""}`);
    }
    stampLines.push("");
    writeFileSync(reviewsPath, stampLines.join("\n"), "utf8");
  }
}

// ── Server ────────────────────────────────────────────────────────────────────
const server = new Server(
  { name: "task-synchronizer-mcp", version: "2.0.0" },
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
          summary: { type: "boolean", description: "Return counts + project info only (no task list). Use this by default." },
          status: { type: "string", enum: ["OPEN", "BLOCKED", "DONE"], description: "Filter tasks by status" },
          owner: { type: "string", description: "Filter tasks by owner substring (e.g. 'claude', 'gemini')" },
          tier: { type: "number", enum: [1, 2, 3], description: "Filter tasks by tier" },
        },
      },
    },
    {
      name: "add_task",
      description: "Adds a new task to state.json with auto-assigned ID. Returns the new task.",
      inputSchema: {
        type: "object",
        properties: {
          owner: { type: "string", description: "Task owner: 'Architect (Gemini)', 'Engineer (Claude)', or 'Tester (TestSprite)'" },
          description: { type: "string", description: "Task description" },
          tier: { type: "number", description: "Risk tier (1, 2, or 3)", enum: [1, 2, 3] },
          prefix: { type: "string", description: "ID prefix: P (architect), E (engineer), T (tester)", enum: ["P", "E", "T"], default: "E" },
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
          id: { type: "string", description: "Task ID (e.g. 'E-78')" },
          status: { type: "string", description: "New status", enum: ["OPEN", "BLOCKED", "DONE"] },
          summary: { type: "string", description: "Completion summary (for DONE status)" },
        },
        required: ["id", "status"],
      },
    },
    {
      name: "add_stamp",
      description: "Writes an atomic audit stamp to state.json. Used by critic agents and review synthesizer.",
      inputSchema: {
        type: "object",
        properties: {
          task_id: { type: "string", description: "Related task ID (e.g. 'E-78')" },
          type: { type: "string", description: "Stamp type (e.g. 'ARCH_PASS', 'SEC_FAIL', 'CRITIC_STAMP')" },
          agent: { type: "string", description: "Agent that produced this stamp" },
          summary: { type: "string", description: "One-line summary of the finding" },
        },
        required: ["type", "agent", "summary"],
      },
    },
    {
      name: "set_project_focus",
      description: "Updates the project's current focus and tier in state.json.",
      inputSchema: {
        type: "object",
        properties: {
          focus: { type: "string", description: "Current focus description" },
          current_tier: { type: "number", description: "Current risk tier", enum: [1, 2, 3] },
        },
        required: ["focus"],
      },
    },
    {
      name: "archive_done_tasks",
      description: `Moves old DONE tasks (beyond the last ${DONE_KEEP_RECENT}) to .ai/archive/state-done-YYYYMM.json when total DONE count exceeds ${DONE_ARCHIVE_THRESHOLD}. Reduces get_state response size. Called automatically by get_state but can be triggered manually.`,
      inputSchema: { type: "object", properties: {} },
    },
    // Legacy tools (backwards compatibility)
    {
      name: "sync_tasks",
      description: "Legacy: Reads UPDATE.md and proposes P-## tasks. Use add_task for state.json.",
      inputSchema: {
        type: "object",
        properties: {
          update_content: { type: "string", description: "Override UPDATE.md content (optional)" },
        },
      },
    },
    {
      name: "append_tasks",
      description: "Legacy: Appends P-## task strings to TASKS.md directly. Use add_task for state.json.",
      inputSchema: {
        type: "object",
        properties: {
          tasks: { type: "array", items: { type: "string" }, description: "Task strings to append" },
        },
        required: ["tasks"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const aiDir = getAiDir();

  if (!existsSync(aiDir)) {
    return { content: [{ type: "text", text: "✗ No .ai/ directory found. Run: ai init" }], isError: true };
  }

  switch (name) {
    // ── get_state ─────────────────────────────────────────────────────────────
    case "get_state": {
      const state = readState(aiDir);
      if (!state) return { content: [{ type: "text", text: "✗ state.json is corrupt or missing." }], isError: true };

      // summary mode — return counts + project only (no task list)
      if (args.summary) {
        const counts = { OPEN: 0, BLOCKED: 0, DONE: 0 };
        for (const t of state.tasks) counts[t.status] = (counts[t.status] || 0) + 1;
        const result = {
          version: state.version,
          project: state.project,
          task_counts: counts,
          total: state.tasks.length,
          stamps: state.stamps.slice(-5), // last 5 stamps only
        };
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }

      // filtered mode — apply status / owner / tier filters
      if (args.status || args.owner || args.tier) {
        let tasks = state.tasks;
        if (args.status) tasks = tasks.filter(t => t.status === args.status);
        if (args.owner) tasks = tasks.filter(t => t.owner?.toLowerCase().includes(args.owner.toLowerCase()));
        if (args.tier) tasks = tasks.filter(t => t.tier === args.tier);
        const result = { project: state.project, tasks, total_matched: tasks.length };
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }

      // full state (no filter) — auto-archive if DONE tasks exceed threshold
      const archiveResult = archiveDoneTasks(aiDir, state);
      if (archiveResult) {
        // re-read pruned state
        const pruned = readState(aiDir);
        const note = `[AUTO-ARCHIVE] ${archiveResult.archived} DONE tasks archived to ${archiveResult.archivePath} — ${archiveResult.kept} recent DONE kept.\n\n`;
        return { content: [{ type: "text", text: note + JSON.stringify(pruned, null, 2) }] };
      }
      return { content: [{ type: "text", text: JSON.stringify(state, null, 2) }] };
    }

    // ── add_task ──────────────────────────────────────────────────────────────
    case "add_task": {
      const state = readStateStrict(aiDir);
      if (!state) {
        const p = resolve(aiDir, "state.json");
        const msg = existsSync(p) ? STATE_CORRUPT_ERR : STATE_MISSING_ERR;
        return { content: [{ type: "text", text: msg }], isError: true };
      }

      const prefix = args.prefix || "E";
      const id = nextId(state.tasks, prefix);
      const task = {
        id,
        owner: args.owner,
        status: "OPEN",
        tier: args.tier || null,
        description: args.description,
        created_at: new Date().toISOString(),
        completed_at: null,
        summary: null,
      };

      state.tasks.push(task);
      writeState(aiDir, state);

      return { content: [{ type: "text", text: `✓ Added ${id}: ${args.description}\n${JSON.stringify(task, null, 2)}` }] };
    }

    // ── update_task_status ────────────────────────────────────────────────────
    case "update_task_status": {
      const state = readStateStrict(aiDir);
      if (!state) {
        const p = resolve(aiDir, "state.json");
        const msg = existsSync(p) ? STATE_CORRUPT_ERR : STATE_MISSING_ERR;
        return { content: [{ type: "text", text: msg }], isError: true };
      }

      const task = state.tasks.find(t => t.id === args.id);
      if (!task) return { content: [{ type: "text", text: `✗ Task '${args.id}' not found in state.json.` }], isError: true };

      task.status = args.status;
      if (args.status === "DONE") {
        task.completed_at = new Date().toISOString();
        if (args.summary) task.summary = args.summary;
      }

      writeState(aiDir, state);
      return { content: [{ type: "text", text: `✓ ${args.id} → ${args.status}${args.summary ? ": " + args.summary : ""}` }] };
    }

    // ── add_stamp ─────────────────────────────────────────────────────────────
    case "add_stamp": {
      const state = readStateStrict(aiDir);
      if (!state) {
        const p = resolve(aiDir, "state.json");
        const msg = existsSync(p) ? STATE_CORRUPT_ERR : STATE_MISSING_ERR;
        return { content: [{ type: "text", text: msg }], isError: true };
      }

      const stamp = {
        type: args.type,
        agent: args.agent,
        task_id: args.task_id || null,
        timestamp: new Date().toISOString(),
        summary: args.summary,
      };

      state.stamps.push(stamp);
      writeState(aiDir, state);

      return { content: [{ type: "text", text: `✓ Stamp [${args.type}] added by ${args.agent}` }] };
    }

    // ── set_project_focus ─────────────────────────────────────────────────────
    case "set_project_focus": {
      const state = readStateStrict(aiDir);
      if (!state) {
        const p = resolve(aiDir, "state.json");
        const msg = existsSync(p) ? STATE_CORRUPT_ERR : STATE_MISSING_ERR;
        return { content: [{ type: "text", text: msg }], isError: true };
      }

      state.project.focus = args.focus;
      if (args.current_tier) state.project.current_tier = args.current_tier;

      writeState(aiDir, state);
      return { content: [{ type: "text", text: `✓ Focus: ${args.focus}${args.current_tier ? " (Tier " + args.current_tier + ")" : ""}` }] };
    }

    // ── archive_done_tasks ────────────────────────────────────────────────────
    case "archive_done_tasks": {
      const state = readStateStrict(aiDir);
      if (!state) {
        const p = resolve(aiDir, "state.json");
        const msg = existsSync(p) ? STATE_CORRUPT_ERR : STATE_MISSING_ERR;
        return { content: [{ type: "text", text: msg }], isError: true };
      }
      const result = archiveDoneTasks(aiDir, state);
      if (!result) {
        const doneCount = state.tasks.filter(t => t.status === "DONE").length;
        return { content: [{ type: "text", text: `✓ No archive needed — ${doneCount} DONE tasks (threshold: ${DONE_ARCHIVE_THRESHOLD})` }] };
      }
      return { content: [{ type: "text", text: `✓ [AUTO-ARCHIVE] ${result.archived} DONE tasks → ${result.archivePath}\n  ${result.kept} recent DONE tasks kept in live state.json` }] };
    }

    // ── Legacy: sync_tasks ────────────────────────────────────────────────────
    case "sync_tasks": {
      const updatePath = resolve(aiDir, "UPDATE.md");
      const updateContent = args.update_content ??
        (existsSync(updatePath) ? readFileSync(updatePath, "utf8") : "");

      if (!updateContent.trim()) {
        return { content: [{ type: "text", text: "UPDATE.md is empty — nothing to sync." }] };
      }

      const tasksPath = resolve(aiDir, "TASKS.md");
      const tasksContent = existsSync(tasksPath) ? readFileSync(tasksPath, "utf8") : "";
      const pNumbers = [...tasksContent.matchAll(/P-(\d+):/g)].map(m => parseInt(m[1], 10));
      const nextP = (pNumbers.length ? Math.max(...pNumbers) : 0) + 1;

      const lines = updateContent.split("\n")
        .filter(l => l.match(/^[-*]\s+/) || l.match(/^##\s+/))
        .map(l => l.replace(/^[-*]\s+/, "").replace(/^##\s+/, "").trim())
        .filter(l => l.length > 5)
        .slice(0, 5);

      if (lines.length === 0) {
        return { content: [{ type: "text", text: "Could not extract actionable intent from UPDATE.md." }] };
      }

      const lower = updateContent.toLowerCase();
      const tier = /\b(auth|oauth|secret|api.?key|deploy|production|migration|breaking)\b/.test(lower) ? "3"
        : /\b(src|logic|refactor|test|implement|algorithm|database|api)\b/.test(lower) ? "2" : "1";
      const date = new Date().toISOString().split("T")[0];

      const proposed = lines.map((line, i) => {
        const num = String(nextP + i).padStart(2, "0");
        return `- [ ] P-${num}: Blueprint for "${line}"\n  Tier: ${tier} | Proposed: ${date}`;
      });

      return { content: [{ type: "text", text: `## Proposed P-## Tasks\n\n${proposed.join("\n\n")}\n\nTo apply: call append_tasks.` }] };
    }

    // ── Legacy: append_tasks ──────────────────────────────────────────────────
    case "append_tasks": {
      const tasksPath = resolve(aiDir, "TASKS.md");
      if (!existsSync(tasksPath)) {
        return { content: [{ type: "text", text: "✗ .ai/TASKS.md not found." }], isError: true };
      }

      let content = readFileSync(tasksPath, "utf8");
      const toAppend = args.tasks.join("\n") + "\n";

      const archSection = content.indexOf("## Architect");
      if (archSection === -1) {
        content += "\n## Architect (Gemini)\n" + toAppend;
      } else {
        const engineerSection = content.indexOf("## Engineer", archSection);
        if (engineerSection === -1) {
          content += "\n" + toAppend;
        } else {
          content = content.slice(0, engineerSection) + toAppend + "\n" + content.slice(engineerSection);
        }
      }

      writeFileSync(tasksPath, content, "utf8");
      return { content: [{ type: "text", text: `✓ Appended ${args.tasks.length} task(s) to TASKS.md` }] };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
