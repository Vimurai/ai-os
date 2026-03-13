#!/usr/bin/env node
/**
 * context-invoker-mcp — AI-OS UACS MCP Server
 * Gives Claude dynamic access to skills and agents by name.
 * Resolves skill/agent markdown from installed ~/.ai-os/ paths and
 * falls back to the source repo for local development.
 *
 * Tools:
 *   activate_skill(skill_name)  → returns SKILL.md content for the named skill
 *   activate_agent(agent_name)  → returns agent .md content for the named agent
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, readdirSync } from "fs";
import { resolve, join } from "path";
import { homedir } from "os";

const HOME = homedir();

// Search roots — ordered by priority (installed global first, then source dev)
const SKILL_ROOTS = [
  join(HOME, ".claude", "skills"),
  join(HOME, ".gemini", "skills"),
  join(HOME, ".ai-os", "shared", "skills"),
  join(HOME, ".ai-os", "claude", "skills"),
];

const AGENT_ROOTS = [
  join(HOME, ".claude", "agents"),
  join(HOME, ".ai-os", "shared", "agents"),
  join(HOME, ".ai-os", "claude", "agents"),
  join(HOME, ".ai-os", "gemini", "agents"),
];

// Also scan source repo if CWD contains src/
const cwd = process.cwd();
const srcBase = resolve(cwd, "src");
if (existsSync(srcBase)) {
  SKILL_ROOTS.push(
    join(srcBase, "shared", "skills"),
    join(srcBase, "claude", "skills"),
    join(srcBase, "gemini", "skills")
  );
  AGENT_ROOTS.push(
    join(srcBase, "shared", "agents"),
    join(srcBase, "claude", "agents"),
    join(srcBase, "gemini", "agents")
  );
}

const SAFE_NAME_RE = /^[a-z0-9_-]+$/i;

function validateName(name) {
  if (!name || typeof name !== "string") return "Name must be a non-empty string";
  if (!SAFE_NAME_RE.test(name)) return `Invalid name '${name}' — only [a-z0-9_-] characters allowed`;
  if (name.length > 64) return `Name too long (max 64 chars)`;
  return null;
}

function findSkill(name) {
  for (const root of SKILL_ROOTS) {
    // Skills 2.0: <root>/<name>/SKILL.md
    const modular = join(root, name, "SKILL.md");
    if (existsSync(modular)) return { path: modular, content: readFileSync(modular, "utf8") };
    // Flat legacy: <root>/<name>.md
    const flat = join(root, `${name}.md`);
    if (existsSync(flat)) return { path: flat, content: readFileSync(flat, "utf8") };
  }
  return null;
}

function findAgent(name) {
  // Normalize: strip .md suffix if provided
  const base = name.replace(/\.md$/, "");
  for (const root of AGENT_ROOTS) {
    const p = join(root, `${base}.md`);
    if (existsSync(p)) return { path: p, content: readFileSync(p, "utf8") };
  }
  return null;
}

function listAvailable(roots, ext) {
  const found = new Set();
  for (const root of roots) {
    if (!existsSync(root)) continue;
    try {
      for (const entry of readdirSync(root, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          // Skills 2.0 folder
          const skill = join(root, entry.name, "SKILL.md");
          if (existsSync(skill)) found.add(entry.name);
        } else if (entry.name.endsWith(ext)) {
          found.add(entry.name.replace(ext, ""));
        }
      }
    } catch (_) { /* skip unreadable dirs */ }
  }
  return [...found].sort();
}

const server = new Server(
  { name: "context-invoker-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "activate_skill",
      description:
        "Returns the full SKILL.md content for a named Claude/shared skill. " +
        "Use this to dynamically load skill instructions into context. " +
        "Call list_skills first if unsure of the exact name.",
      inputSchema: {
        type: "object",
        properties: {
          skill_name: {
            type: "string",
            description: "Name of the skill (e.g. 'ai-update', 'scope_safety', 'ai-digest')",
          },
          list_skills: {
            type: "boolean",
            description: "If true, returns a list of all available skill names instead of loading one",
            default: false,
          },
        },
        required: ["skill_name"],
      },
    },
    {
      name: "activate_agent",
      description:
        "Returns the full agent .md content for a named Claude/Gemini agent. " +
        "Use this to dynamically load agent instructions into context before delegating a task. " +
        "Call with list_agents:true to discover available agent names.",
      inputSchema: {
        type: "object",
        properties: {
          agent_name: {
            type: "string",
            description: "Name of the agent (e.g. 'chaos_monkey', 'devops_engineer', 'security_engineer')",
          },
          list_agents: {
            type: "boolean",
            description: "If true, returns a list of all available agent names instead of loading one",
            default: false,
          },
        },
        required: ["agent_name"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "activate_skill": {
      if (args.list_skills) {
        const skills = listAvailable(SKILL_ROOTS, ".md");
        return {
          content: [{ type: "text", text: `Available skills:\n${skills.map(s => `  - ${s}`).join("\n")}` }],
        };
      }
      const skillErr = validateName(args.skill_name);
      if (skillErr) {
        return { content: [{ type: "text", text: `✗ ${skillErr}` }], isError: true };
      }
      const result = findSkill(args.skill_name);
      if (!result) {
        const skills = listAvailable(SKILL_ROOTS, ".md");
        return {
          content: [{
            type: "text",
            text: `✗ Skill '${args.skill_name}' not found.\n\nAvailable skills:\n${skills.map(s => `  - ${s}`).join("\n")}`,
          }],
          isError: true,
        };
      }
      return {
        content: [{
          type: "text",
          text: `# Skill: ${args.skill_name}\n_Source: ${result.path}_\n\n${result.content}`,
        }],
      };
    }

    case "activate_agent": {
      if (args.list_agents) {
        const agents = listAvailable(AGENT_ROOTS, ".md");
        return {
          content: [{ type: "text", text: `Available agents:\n${agents.map(a => `  - ${a}`).join("\n")}` }],
        };
      }
      const agentErr = validateName(args.agent_name);
      if (agentErr) {
        return { content: [{ type: "text", text: `✗ ${agentErr}` }], isError: true };
      }
      const result = findAgent(args.agent_name);
      if (!result) {
        const agents = listAvailable(AGENT_ROOTS, ".md");
        return {
          content: [{
            type: "text",
            text: `✗ Agent '${args.agent_name}' not found.\n\nAvailable agents:\n${agents.map(a => `  - ${a}`).join("\n")}`,
          }],
          isError: true,
        };
      }
      return {
        content: [{
          type: "text",
          text: `# Agent: ${args.agent_name}\n_Source: ${result.path}_\n\n${result.content}`,
        }],
      };
    }

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
