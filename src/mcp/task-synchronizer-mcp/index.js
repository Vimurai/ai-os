#!/usr/bin/env node
/**
 * task-synchronizer-mcp — AI-OS UACS MCP Server
 * Maps structured UPDATE.md content to TASKS.md by adding/updating P-## entries.
 *
 * Tools:
 *   sync_tasks(update_content?) → reads UPDATE.md, proposes new P-## tasks
 *   append_tasks(tasks)         → appends P-## tasks to .ai/TASKS.md
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";

const server = new Server(
  { name: "task-synchronizer-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "sync_tasks",
      description:
        "Reads .ai/UPDATE.md and .ai/TASKS.md, then proposes new P-## task entries based on the intent. Does not write — returns proposed tasks for review.",
      inputSchema: {
        type: "object",
        properties: {
          update_content: {
            type: "string",
            description: "Override UPDATE.md content (optional — reads from file if omitted)",
          },
        },
      },
    },
    {
      name: "append_tasks",
      description:
        "Appends the given P-## task entries to .ai/TASKS.md under the Architect section.",
      inputSchema: {
        type: "object",
        properties: {
          tasks: {
            type: "array",
            items: { type: "string" },
            description: "Array of task strings to append (e.g. [\"- [ ] P-09: ...\"])",
          },
        },
        required: ["tasks"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const aiDir = resolve(process.cwd(), ".ai");

  if (!existsSync(aiDir)) {
    return {
      content: [{ type: "text", text: "✗ No .ai/ directory found. Run: ai init" }],
      isError: true,
    };
  }

  switch (name) {
    case "sync_tasks": {
      // Read UPDATE.md
      const updatePath = resolve(aiDir, "UPDATE.md");
      const updateContent =
        args.update_content ??
        (existsSync(updatePath) ? readFileSync(updatePath, "utf8") : "");

      if (!updateContent.trim()) {
        return { content: [{ type: "text", text: "UPDATE.md is empty — nothing to sync." }] };
      }

      // Read TASKS.md to find highest P-## number
      const tasksPath = resolve(aiDir, "TASKS.md");
      const tasksContent = existsSync(tasksPath) ? readFileSync(tasksPath, "utf8") : "";
      const pNumbers = [...tasksContent.matchAll(/P-(\d+):/g)].map((m) => parseInt(m[1], 10));
      const nextP = (pNumbers.length ? Math.max(...pNumbers) : 0) + 1;

      // Extract intent lines from UPDATE.md
      const lines = updateContent
        .split("\n")
        .filter((l) => l.match(/^[-*]\s+/) || l.match(/^##\s+/))
        .map((l) => l.replace(/^[-*]\s+/, "").replace(/^##\s+/, "").trim())
        .filter((l) => l.length > 5)
        .slice(0, 5);

      if (lines.length === 0) {
        return {
          content: [{ type: "text", text: "Could not extract actionable intent from UPDATE.md. Ensure bullet points or sections are present." }],
        };
      }

      // Detect tier
      const tier = detectTier(updateContent);
      const date = new Date().toISOString().split("T")[0];

      // Generate proposed tasks
      const proposed = lines.map((line, i) => {
        const num = String(nextP + i).padStart(2, "0");
        return [
          `- [ ] P-${num}: Blueprint for "${line}"`,
          `  Tier: ${tier} | Blueprint: architect.md §TBD | Proposed: ${date}`,
          `  What: ${line}`,
        ].join("\n");
      });

      const result = [
        `## Proposed P-## Tasks (from UPDATE.md)`,
        `Next available: P-${String(nextP).padStart(2, "0")}`,
        ``,
        ...proposed,
        ``,
        `To apply: call append_tasks with these task strings.`,
      ].join("\n");

      return { content: [{ type: "text", text: result }] };
    }

    case "append_tasks": {
      const tasksPath = resolve(aiDir, "TASKS.md");
      if (!existsSync(tasksPath)) {
        return { content: [{ type: "text", text: "✗ .ai/TASKS.md not found." }], isError: true };
      }

      let content = readFileSync(tasksPath, "utf8");
      const toAppend = args.tasks.join("\n") + "\n";

      // Append after the Architect section header
      const archSection = content.indexOf("## Architect");
      if (archSection === -1) {
        content += "\n## Architect (Gemini)\n" + toAppend;
      } else {
        // Find the next section to insert before it
        const engineerSection = content.indexOf("## Engineer", archSection);
        if (engineerSection === -1) {
          content += "\n" + toAppend;
        } else {
          content = content.slice(0, engineerSection) + toAppend + "\n" + content.slice(engineerSection);
        }
      }

      writeFileSync(tasksPath, content, "utf8");
      return {
        content: [{ type: "text", text: `✓ Appended ${args.tasks.length} task(s) to .ai/TASKS.md` }],
      };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

function detectTier(text) {
  const lower = text.toLowerCase();
  if (/\b(auth|oauth|secret|api.?key|token|password|deploy|production|migration|breaking)\b/.test(lower)) return "3";
  if (/\b(src|logic|refactor|test|implement|algorithm|database|api)\b/.test(lower)) return "2";
  return "1";
}

const transport = new StdioServerTransport();
await server.connect(transport);
