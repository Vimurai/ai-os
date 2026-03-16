#!/usr/bin/env node
/**
 * verification-mcp — AI-OS §32 Verification Audit (E-108)
 *
 * Programmatic compliance auditing of agent/skill YAML frontmatter.
 * Checks declared `allowed-tools` against registry.json and MCP tool exports.
 * Flags "Ghost Tools" (declared but non-existent) as CRITICAL violations.
 *
 * Tools:
 *   verify_compliance({ agent_name? }) → COMPLIANCE_REPORT per agent
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

// Built-in Claude Code tools that are always valid (not in registry)
const BUILTIN_TOOLS = new Set([
  "Read", "Write", "Edit", "Glob", "Grep", "Bash",
  "WebSearch", "WebFetch", "Agent", "TodoRead", "TodoWrite",
  "NotebookEdit", "ExitPlanMode", "EnterPlanMode",
]);

// ── Helpers ───────────────────────────────────────────────────────────────────

function parseFrontmatter(text) {
  if (!text.startsWith("---")) return null;
  const end = text.indexOf("---", 3);
  if (end === -1) return null;
  const fm = text.slice(3, end);
  const result = {};
  for (const line of fm.split("\n")) {
    const m = line.match(/^([\w-]+):\s*(.+)$/);
    if (m) result[m[1].trim()] = m[2].trim();
  }
  return result;
}

function scanAgentFiles(baseDir) {
  const files = [];
  if (!existsSync(baseDir)) return files;
  function walk(dir) {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const st = statSync(full);
      if (st.isDirectory()) { walk(full); continue; }
      if (entry.endsWith(".md")) files.push(full);
    }
  }
  walk(baseDir);
  return files;
}

function loadRegistry(registryPath) {
  const available = new Map(); // tool → server name
  if (!existsSync(registryPath)) return available;
  try {
    const reg = JSON.parse(readFileSync(registryPath, "utf8"));
    for (const [srv, info] of Object.entries(reg.mcp_servers || {})) {
      const tools = info["allowed-tools"] || [];
      if (tools.includes("*")) {
        available.set(`${srv}:*`, srv);
      } else {
        for (const t of tools) available.set(t, srv);
      }
    }
  } catch { /* ignore */ }
  return available;
}

function isToolAvailable(tool, registry) {
  if (BUILTIN_TOOLS.has(tool)) return true;
  if (tool === "*") return true;
  if (tool.startsWith("mcp__")) return true; // MCP-prefixed tools are registry-resolved
  if (registry.has(tool)) return true;
  return false;
}

function auditAgent(mdPath, registry) {
  let text;
  try { text = readFileSync(mdPath, "utf8"); } catch { return null; }
  const fm = parseFrontmatter(text);
  if (!fm) return null; // no frontmatter — skip

  const agentName = fm["name"] || mdPath.split("/").pop().replace(".md", "");
  const violations = [];
  const warnings   = [];

  // Check required §17.1.2 fields
  for (const field of ["name", "description", "disable-model-invocation", "user-invocable", "allowed-tools"]) {
    if (!fm[field]) warnings.push(`Missing required frontmatter field: '${field}'`);
  }

  // Check allowed-tools for Ghost Tools
  const rawTools = fm["allowed-tools"] || "";
  const tools = rawTools.split(",").map(t => t.trim()).filter(Boolean);
  for (const tool of tools) {
    if (!isToolAvailable(tool, registry)) {
      violations.push(`Ghost Tool: '${tool}' declared but not found in registry.json or builtin list`);
    }
  }

  const status = violations.length > 0 ? "FAIL" : warnings.length > 0 ? "WARN" : "PASS";
  return { agent_name: agentName, file: mdPath, status, violations, warnings };
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "verification-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "verify_compliance",
      description:
        "§32: Audits agent/skill YAML frontmatter for compliance. Checks allowed-tools against " +
        "registry.json and built-in tool list. Flags Ghost Tools (declared but not authorized) as CRITICAL. " +
        "Returns a COMPLIANCE_REPORT per agent. Pass agent_name to audit a single agent, omit for full scan.",
      inputSchema: {
        type: "object",
        properties: {
          agent_name: {
            type: "string",
            description: "Specific agent/skill name to audit. Omit to scan all agents.",
          },
          paths: {
            type: "array",
            items: { type: "string" },
            description: "Override scan directories. Defaults to src/**/agents/, src/**/skills/, ~/.ai-os/**/agents/",
          },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "verify_compliance") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }

  const cwd = process.cwd();
  const aios = resolve(process.env.HOME || "~", ".ai-os");
  const registryPath = join(aios, "config", "registry.json");
  const registry = loadRegistry(registryPath);

  // Determine scan directories
  const scanDirs = args.paths?.map(p => resolve(cwd, p)) ?? [
    resolve(cwd, "src", "claude", "agents"),
    resolve(cwd, "src", "claude", "skills"),
    resolve(cwd, "src", "shared", "skills"),
    resolve(cwd, "src", "gemini", "agents"),
    join(aios, "claude", "agents"),
    join(aios, "gemini", "agents"),
  ];

  // Collect all .md files
  const mdFiles = scanDirs.flatMap(d => scanAgentFiles(d));

  if (mdFiles.length === 0) {
    return { content: [{ type: "text", text: "No agent/skill files found in scan directories." }] };
  }

  // Filter by agent_name if specified
  const targetName = args.agent_name?.toLowerCase();
  const toAudit = targetName
    ? mdFiles.filter(f => f.toLowerCase().includes(targetName))
    : mdFiles;

  if (toAudit.length === 0) {
    return { content: [{ type: "text", text: `No agent/skill files found matching: ${args.agent_name}` }] };
  }

  // Audit each file
  const reports = toAudit.map(f => auditAgent(f, registry)).filter(Boolean);

  const critical = reports.filter(r => r.status === "FAIL");
  const warned   = reports.filter(r => r.status === "WARN");
  const passed   = reports.filter(r => r.status === "PASS");

  const lines = [
    `## COMPLIANCE_REPORT — ${new Date().toISOString().split("T")[0]}`,
    `Scanned: ${reports.length} agents/skills | ` +
    `PASS: ${passed.length} | WARN: ${warned.length} | FAIL: ${critical.length}`,
    "",
  ];

  for (const r of reports) {
    if (r.status === "PASS") continue; // only emit issues
    const icon = r.status === "FAIL" ? "✗" : "⚠";
    lines.push(`${icon} [${r.status}] ${r.agent_name}`);
    lines.push(`   File: ${r.file}`);
    for (const v of r.violations) lines.push(`   CRITICAL: ${v}`);
    for (const w of r.warnings)   lines.push(`   WARN: ${w}`);
    lines.push("");
  }

  if (critical.length === 0 && warned.length === 0) {
    lines.push("✓ All agents are compliant — no Ghost Tools or missing frontmatter detected.");
  } else if (critical.length > 0) {
    lines.push("ACTION REQUIRED: Remove or register Ghost Tools before next commit.");
  }

  return { content: [{ type: "text", text: lines.join("\n") }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
