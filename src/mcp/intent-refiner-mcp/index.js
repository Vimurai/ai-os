#!/usr/bin/env node
/**
 * intent-refiner-mcp — AI-OS UACS MCP Server
 * Parses the last N lines of terminal output or a chat log, extracts structured
 * intent, and writes it to .ai/UPDATE.md.
 *
 * Tools:
 *   refine_intent(chat_log, lines?) → structured UPDATE.md content
 *   write_update_md(content)        → writes content to .ai/UPDATE.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";

const server = new Server(
  { name: "intent-refiner-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "refine_intent",
      description:
        "Parses terminal/chat context and extracts structured intent as UPDATE.md content. Returns the refined intent without writing.",
      inputSchema: {
        type: "object",
        properties: {
          chat_log: {
            type: "string",
            description: "Raw terminal output or chat log text to parse",
          },
          lines: {
            type: "number",
            description: "Max lines to consider from the end of the log (default: 50)",
            default: 50,
          },
        },
        required: ["chat_log"],
      },
    },
    {
      name: "write_update_md",
      description:
        "Writes the given content to .ai/UPDATE.md in the current working directory. Overwrites existing content.",
      inputSchema: {
        type: "object",
        properties: {
          content: {
            type: "string",
            description: "Structured intent content to write to UPDATE.md",
          },
        },
        required: ["content"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "refine_intent": {
      const lines = args.lines ?? 50;
      const rawLines = args.chat_log.split("\n");
      const relevant = rawLines.slice(-lines).join("\n");

      // Extract intent signals from the text
      const adds = extractSignals(relevant, /\b(add|create|implement|build|scaffold|write)\b[^.\n]{5,80}/gi);
      const modifies = extractSignals(relevant, /\b(update|modify|change|refactor|fix|improve)\b[^.\n]{5,80}/gi);
      const removes = extractSignals(relevant, /\b(remove|delete|deprecate|drop)\b[^.\n]{5,80}/gi);
      const constraints = extractSignals(relevant, /\b(must|should|ensure|require|constraint|limit|only)\b[^.\n]{5,80}/gi);

      const tier = detectTier(relevant);

      const refined = [
        `# UPDATE (Refined by intent-refiner-mcp)`,
        ``,
        adds.length ? `## Add\n${adds.map((s) => `- ${s}`).join("\n")}` : "",
        modifies.length ? `\n## Modify\n${modifies.map((s) => `- ${s}`).join("\n")}` : "",
        removes.length ? `\n## Remove\n${removes.map((s) => `- ${s}`).join("\n")}` : "",
        constraints.length ? `\n## Constraints\n${constraints.map((s) => `- ${s}`).join("\n")}` : "",
        ``,
        `## Risk Tier: ${tier}`,
        `_Refined: ${new Date().toISOString()}_`,
      ]
        .filter(Boolean)
        .join("\n");

      return { content: [{ type: "text", text: refined }] };
    }

    case "write_update_md": {
      const updatePath = resolve(process.cwd(), ".ai/UPDATE.md");
      if (!existsSync(resolve(process.cwd(), ".ai"))) {
        return {
          content: [{ type: "text", text: "✗ No .ai/ directory found. Run: ai init" }],
          isError: true,
        };
      }
      writeFileSync(updatePath, args.content, "utf8");
      return {
        content: [{ type: "text", text: `✓ Written to ${updatePath}` }],
      };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

function extractSignals(text, pattern) {
  const matches = [];
  let m;
  pattern.lastIndex = 0;
  while ((m = pattern.exec(text)) !== null && matches.length < 5) {
    const cleaned = m[0].trim().replace(/\s+/g, " ");
    if (cleaned.length > 10) matches.push(cleaned);
  }
  return matches;
}

function detectTier(text) {
  const lower = text.toLowerCase();
  if (/\b(auth|oauth|secret|api.?key|token|password|deploy|production|migration|breaking)\b/.test(lower)) {
    return "Tier 3 (High Risk — Architect review required)";
  }
  if (/\b(src|logic|refactor|test|implement|algorithm|database|api)\b/.test(lower)) {
    return "Tier 2 (Medium Risk — Unit tests required)";
  }
  return "Tier 1 (Low Risk — Linter only)";
}

// ── E-97: --stdin CLI mode (bypasses MCP transport for `ai update --votu`) ──
// Usage: node intent-refiner-mcp/index.js --stdin [--lines N]
//   Reads chat log from stdin, writes refined intent to .ai/UPDATE.md, exits.
if (process.argv.includes("--stdin")) {
  const linesArg = process.argv.indexOf("--lines");
  const maxLines = linesArg !== -1 ? parseInt(process.argv[linesArg + 1], 10) || 50 : 50;

  let input = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  if (!input.trim()) {
    process.stderr.write("✗ No input received on stdin. Aborting.\n");
    process.exit(1);
  }

  const rawLines = input.split("\n");
  const relevant = rawLines.slice(-maxLines).join("\n");

  const adds       = extractSignals(relevant, /\b(add|create|implement|build|scaffold|write)\b[^.\n]{5,80}/gi);
  const modifies   = extractSignals(relevant, /\b(update|modify|change|refactor|fix|improve)\b[^.\n]{5,80}/gi);
  const removes    = extractSignals(relevant, /\b(remove|delete|deprecate|drop)\b[^.\n]{5,80}/gi);
  const constraints = extractSignals(relevant, /\b(must|should|ensure|require|constraint|limit|only)\b[^.\n]{5,80}/gi);
  const tier = detectTier(relevant);

  const lines = ["# UPDATE (Refined by intent-refiner-mcp)", ""];
  if (adds.length)        lines.push("## Add",        ...adds.map(s => `- ${s}`),        "");
  if (modifies.length)    lines.push("## Modify",     ...modifies.map(s => `- ${s}`),    "");
  if (removes.length)     lines.push("## Remove",     ...removes.map(s => `- ${s}`),     "");
  if (constraints.length) lines.push("## Constraints",...constraints.map(s => `- ${s}`), "");
  lines.push(`## Risk Tier: ${tier}`, `_Refined: ${new Date().toISOString()}_`);
  const content = lines.join("\n");

  const updatePath = resolve(process.cwd(), ".ai/UPDATE.md");
  if (!existsSync(resolve(process.cwd(), ".ai"))) {
    process.stderr.write("✗ No .ai/ directory found. Run: ai init\n");
    process.exit(1);
  }
  writeFileSync(updatePath, content, "utf8");
  process.stdout.write(content + "\n\n✓ Written to .ai/UPDATE.md\n");
  process.exit(0);
}

const transport = new StdioServerTransport();
await server.connect(transport);
