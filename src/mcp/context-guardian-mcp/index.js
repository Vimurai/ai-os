#!/usr/bin/env node
/**
 * context-guardian-mcp — AI-OS UACS MCP Server
 * Guards ai archive and git commit by detecting unresolved markers in the workspace.
 *
 * Tools:
 *   check_workspace(strict?) → scans TASKS.md + architect.md + src/ for Pending/TODO/FIXME
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

const server = new Server(
  { name: "context-guardian-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "check_workspace",
      description:
        "Scans .ai/TASKS.md, .ai/architect.md, and src/ for unresolved markers (TODO, FIXME, Pending, [ ] tasks). Returns CLEAN or DIRTY status with a list of open items.",
      inputSchema: {
        type: "object",
        properties: {
          strict: {
            type: "boolean",
            description: "If true, also check src/ files for TODO/FIXME comments (default: false)",
            default: false,
          },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "check_workspace") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }

  const strict = args.strict ?? false;
  const cwd = process.cwd();
  const aiDir = resolve(cwd, ".ai");

  if (!existsSync(aiDir)) {
    return {
      content: [{ type: "text", text: "✗ No .ai/ directory found. Run: ai init" }],
      isError: true,
    };
  }

  const issues = [];

  // ── Check TASKS.md for open [ ] tasks ──────────────────────────────────────
  const tasksPath = resolve(aiDir, "TASKS.md");
  if (existsSync(tasksPath)) {
    const content = readFileSync(tasksPath, "utf8");
    const openTasks = content
      .split("\n")
      .filter((l) => /^- \[ \]/.test(l))
      .map((l) => l.trim());

    if (openTasks.length > 0) {
      issues.push({
        source: ".ai/TASKS.md",
        type: "OPEN_TASKS",
        severity: "DIRTY",
        items: openTasks.slice(0, 10),
        message: `${openTasks.length} uncompleted task(s) in TASKS.md`,
      });
    }

    // Check for "Pending" status lines
    const pendingLines = content
      .split("\n")
      .filter((l) => /Status:\s*(Pending|pending)/.test(l))
      .map((l) => l.trim());

    if (pendingLines.length > 0) {
      issues.push({
        source: ".ai/TASKS.md",
        type: "PENDING_STATUS",
        severity: "WARN",
        items: pendingLines.slice(0, 5),
        message: `${pendingLines.length} task(s) with Pending status`,
      });
    }
  }

  // ── Check architect.md for TBD/TODO markers ────────────────────────────────
  const archPath = resolve(aiDir, "architect.md");
  if (existsSync(archPath)) {
    const content = readFileSync(archPath, "utf8");
    const rawLines = content.split("\n");

    // Skip lines inside fenced code blocks and inline code to avoid false
    // positives from regex patterns / documentation examples (E-62).
    let inCodeFence = false;
    const tbdLines = [];
    rawLines.forEach((l, i) => {
      if (/^\s*```/.test(l)) { inCodeFence = !inCodeFence; return; }
      if (inCodeFence) return;
      // Strip inline code spans before testing so `TODO` inside backticks is ignored
      const stripped = l.replace(/`[^`]*`/g, "``");
      if (/\b(TBD|TODO|FIXME|PLACEHOLDER|MISSING|UNRESOLVED)\b/i.test(stripped)) {
        tbdLines.push(`L${i + 1}: ${l.trim()}`);
      }
    });

    if (tbdLines.length > 0) {
      issues.push({
        source: ".ai/architect.md",
        type: "UNRESOLVED_BLUEPRINT",
        severity: "WARN",
        items: tbdLines.slice(0, 5),
        message: `${tbdLines.length} unresolved marker(s) in architect.md`,
      });
    }

    // Check for open architectural questions (outside code fences)
    inCodeFence = false;
    const questionLines = [];
    rawLines.forEach((l) => {
      if (/^\s*```/.test(l)) { inCodeFence = !inCodeFence; return; }
      if (inCodeFence) return;
      if (/\?\s*$/.test(l.trim()) && l.trim().length > 10) questionLines.push(l.trim());
    });

    if (questionLines.length > 0) {
      issues.push({
        source: ".ai/architect.md",
        type: "OPEN_QUESTIONS",
        severity: "WARN",
        items: questionLines.slice(0, 3),
        message: `${questionLines.length} open question(s) in architect.md`,
      });
    }
  }

  // ── Strict mode: scan src/ for TODO/FIXME ─────────────────────────────────
  if (strict) {
    const srcDir = resolve(cwd, "src");
    if (existsSync(srcDir)) {
      const srcIssues = [];
      scanDir(srcDir, [".js", ".ts", ".sh", ".py", ".go"], (filePath, content) => {
        const lines = content.split("\n");
        lines.forEach((line, i) => {
          // Skip lines where the marker appears inside a regex literal (e.g. /\b(TODO|FIXME)\b/)
          // to avoid false positives from pattern definitions in source files (E-62).
          const isRegexLiteral = /\/[^/]*\b(TODO|FIXME|HACK|XXX)\b[^/]*\//.test(line);
          if (!isRegexLiteral && /\b(TODO|FIXME|HACK|XXX)\b/.test(line)) {
            srcIssues.push(`${filePath.replace(cwd, "")}:${i + 1}: ${line.trim().slice(0, 80)}`);
          }
        });
      });

      if (srcIssues.length > 0) {
        issues.push({
          source: "src/**",
          type: "CODE_TODO",
          severity: "WARN",
          items: srcIssues.slice(0, 10),
          message: `${srcIssues.length} TODO/FIXME comment(s) in src/`,
        });
      }
    }
  }

  // ── Report ─────────────────────────────────────────────────────────────────
  const hasDirty = issues.some((i) => i.severity === "DIRTY");
  const status = hasDirty ? "DIRTY" : issues.length > 0 ? "WARN" : "CLEAN";
  const date = new Date().toISOString().split("T")[0];

  const lines = [
    `## context-guardian-mcp Report — ${date}`,
    `Status: ${status === "CLEAN" ? "✓ CLEAN" : status === "WARN" ? "⚠ WARN" : "✗ DIRTY"}`,
    ``,
  ];

  if (issues.length === 0) {
    lines.push("Workspace is clean. Safe to archive or commit.");
  } else {
    for (const issue of issues) {
      lines.push(`### ${issue.type} (${issue.severity}) — ${issue.source}`);
      lines.push(issue.message);
      issue.items.forEach((item) => lines.push(`  ${item}`));
      lines.push("");
    }

    if (hasDirty) {
      lines.push("✗ DIRTY workspace — ai archive and git commit are BLOCKED.");
      lines.push("Resolve open tasks before archiving or committing.");
    } else {
      lines.push("⚠ Warnings found — review before proceeding.");
    }
  }

  return { content: [{ type: "text", text: lines.join("\n") }] };
});

function scanDir(dir, exts, callback) {
  try {
    const entries = readdirSync(dir);
    for (const entry of entries) {
      if (entry.startsWith(".") || entry === "node_modules") continue;
      const full = join(dir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        scanDir(full, exts, callback);
      } else if (exts.some((e) => full.endsWith(e))) {
        try {
          const content = readFileSync(full, "utf8");
          callback(full, content);
        } catch { /* skip unreadable files */ }
      }
    }
  } catch { /* skip unreadable dirs */ }
}

const transport = new StdioServerTransport();
await server.connect(transport);
