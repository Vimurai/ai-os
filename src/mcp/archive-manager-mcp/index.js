#!/usr/bin/env node
/**
 * archive-manager-mcp — AI-OS Auto-Pilot MCP Server
 * Monitors .ai/ context health and orchestrates autonomous archive operations.
 *
 * Tools:
 *   check_context_health()   → line + token health report; needs_archive: boolean
 *   execute_archive()        → runs `ai archive` via host CLI
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { createReadStream, readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { createInterface } from "readline";
import { resolve } from "path";
import { spawnSync } from "child_process";

// Stream-based line/word counter — avoids loading full file into memory (E-153)
function countFileStats(fpath) {
  return new Promise((res, rej) => {
    let lines = 0;
    let words = 0;
    const rl = createInterface({ input: createReadStream(fpath, { encoding: "utf8" }), crlfDelay: Infinity });
    rl.on("line", (line) => { lines++; words += line.split(/\s+/).filter(Boolean).length; });
    rl.on("close", () => res({ lines, words }));
    rl.on("error", rej);
  });
}

// ── State.json DONE-task archiving ────────────────────────────────────────────
const DONE_ARCHIVE_THRESHOLD = 50;
const DONE_KEEP_RECENT = 10;

function archiveStateDoneTasks(cwd) {
  const statePath = resolve(cwd, ".ai/state.json");
  if (!existsSync(statePath)) return null;
  let state;
  try { state = JSON.parse(readFileSync(statePath, "utf8")); } catch { return null; }

  const done = (state.tasks || []).filter(t => t.status === "DONE");
  if (done.length <= DONE_ARCHIVE_THRESHOLD) return { skipped: true, doneCount: done.length };

  const toArchive = done.slice(0, done.length - DONE_KEEP_RECENT);
  const toKeep    = done.slice(done.length - DONE_KEEP_RECENT);
  const open      = (state.tasks || []).filter(t => t.status !== "DONE");

  const ym = new Date().toISOString().slice(0, 7);
  const archiveDir = resolve(cwd, ".ai/archive");
  mkdirSync(archiveDir, { recursive: true });
  const archivePath = resolve(archiveDir, `state-done-${ym}.json`);

  let existing = [];
  if (existsSync(archivePath)) {
    try { existing = JSON.parse(readFileSync(archivePath, "utf8")); } catch {}
  }
  writeFileSync(archivePath, JSON.stringify([...existing, ...toArchive], null, 2) + "\n", "utf8");

  state.tasks = [...open, ...toKeep];
  writeFileSync(statePath, JSON.stringify(state, null, 2) + "\n", "utf8");

  return { archived: toArchive.length, kept: toKeep.length, archivePath };
}

// ── Thresholds (P-27 blueprint §23) ──────────────────────────────────────────
const AUTO_ARCHIVE_LINES  = 200;
const AUTO_ARCHIVE_TOKENS = 10000;

// Files that accumulate over time and should be health-checked
const MONITORED_FILES = ["LOG.md", "COMM.md", "REVIEWS.md", "SESSION.md"];

const server = new Server(
  { name: "archive-manager-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "check_context_health",
      description:
        "Calculates line counts and estimates token usage for .ai/ log files. " +
        "Returns a JSON health report including needs_archive: boolean. " +
        "Use this before calling execute_archive to decide if archiving is warranted.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "execute_archive",
      description:
        "Triggers 'ai archive' via the host CLI to move bloated .ai/ log files to the " +
        "archive directory and re-initialize them from templates. " +
        "Only call this after check_context_health returns needs_archive: true.",
      inputSchema: { type: "object", properties: {} },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name } = request.params;

  // ── check_context_health ──────────────────────────────────────────────────
  if (name === "check_context_health") {
    const cwd = process.cwd();
    const aiDir = resolve(cwd, ".ai");

    if (!existsSync(aiDir)) {
      return {
        content: [{ type: "text", text: JSON.stringify({ error: "No .ai/ directory found. Run: ai init", needs_archive: false }) }],
        isError: true,
      };
    }

    const files = [];
    let totalLines  = 0;
    let totalTokens = 0;

    for (const fname of MONITORED_FILES) {
      const fpath = resolve(aiDir, fname);
      if (!existsSync(fpath)) continue;

      let stats;
      try { stats = await countFileStats(fpath); } catch { continue; }

      const lineCount = stats.lines;
      // Token estimate: word count × 1.3 (empirical for markdown prose)
      const tokenEstimate = Math.round(stats.words * 1.3);

      files.push({ file: fname, lines: lineCount, tokens: tokenEstimate });
      totalLines  += lineCount;
      totalTokens += tokenEstimate;
    }

    // Check state.json DONE task count
    const statePath = resolve(aiDir, "state.json");
    let doneTaskCount = 0;
    if (existsSync(statePath)) {
      try {
        const state = JSON.parse(readFileSync(statePath, "utf8"));
        doneTaskCount = (state.tasks || []).filter(t => t.status === "DONE").length;
      } catch {}
    }
    const stateNeedsArchive = doneTaskCount > DONE_ARCHIVE_THRESHOLD;
    const needsArchive = totalLines >= AUTO_ARCHIVE_LINES || totalTokens >= AUTO_ARCHIVE_TOKENS || stateNeedsArchive;

    const report = {
      needs_archive:    needsArchive,
      state_done_tasks: doneTaskCount,
      state_done_threshold: DONE_ARCHIVE_THRESHOLD,
      total_lines:      totalLines,
      total_tokens:     totalTokens,
      thresholds:       { lines: AUTO_ARCHIVE_LINES, tokens: AUTO_ARCHIVE_TOKENS },
      files,
      recommendation:   needsArchive
        ? `Context health critical: ${totalLines} lines / ~${totalTokens} tokens exceeds thresholds. Run execute_archive.`
        : `Context health OK: ${totalLines} lines / ~${totalTokens} tokens within thresholds.`,
    };

    return { content: [{ type: "text", text: JSON.stringify(report, null, 2) }] };
  }

  // ── execute_archive ───────────────────────────────────────────────────────
  if (name === "execute_archive") {
    const cwd = process.cwd();

    // Locate the `ai` binary — prefer global install, fall back to local src
    const candidatePaths = [
      "/usr/local/bin/ai",
      `${process.env.HOME}/.ai-os/bin/ai`,
      resolve(cwd, "src/bin/ai"),
    ];

    let aiBin = null;
    for (const p of candidatePaths) {
      if (existsSync(p)) { aiBin = p; break; }
    }

    if (!aiBin) {
      return {
        content: [{ type: "text", text: "✗ `ai` binary not found. Ensure AI-OS is installed (./install-ai-os.sh)." }],
        isError: true,
      };
    }

    const result = spawnSync("bash", [aiBin, "archive"], {
      cwd,
      encoding: "utf8",
      timeout: 30000,
    });

    if (result.error) {
      return {
        content: [{ type: "text", text: `✗ execute_archive failed: ${result.error.message}` }],
        isError: true,
      };
    }

    const output = (result.stdout || "").trim();
    const stderr = (result.stderr || "").trim();
    const success = result.status === 0;

    // Also archive old DONE tasks from state.json
    const stateArchive = archiveStateDoneTasks(cwd);
    const stateNote = stateArchive && !stateArchive.skipped
      ? `\n✓ [STATE-ARCHIVE] ${stateArchive.archived} DONE tasks → ${stateArchive.archivePath} (${stateArchive.kept} recent kept)`
      : stateArchive
        ? `\n  state.json: ${stateArchive.doneCount} DONE tasks (below threshold — no prune needed)`
        : "";

    const lines = [
      success ? "✓ [AUTO-ARCHIVE] Archive completed successfully." : "✗ Archive command exited non-zero.",
      output  ? `stdout:\n${output}` : "",
      stderr  ? `stderr:\n${stderr}` : "",
      stateNote,
    ].filter(Boolean);

    return { content: [{ type: "text", text: lines.join("\n") }], isError: !success };
  }

  return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
});

const transport = new StdioServerTransport();
await server.connect(transport);
