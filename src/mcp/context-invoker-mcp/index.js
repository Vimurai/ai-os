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
import { readFileSync, openSync, readSync, closeSync, existsSync, readdirSync } from "fs";
import { resolve, join, sep } from "path";
import { homedir } from "os";
import { createLogger } from "../shared/logger.js";

// ── Structured logger (obs_baseline §Logging) ────────────────────────────────
const logger = createLogger("context-invoker-mcp");

// Read only the first 4 KB of a file — sufficient to capture YAML frontmatter (E-154)
const HEAD_BYTES = 4096;
function readHead(filePath) {
  const fd = openSync(filePath, "r");
  try {
    const buf = Buffer.alloc(HEAD_BYTES);
    const bytesRead = readSync(fd, buf, 0, HEAD_BYTES, 0);
    return buf.slice(0, bytesRead).toString("utf8");
  } finally {
    closeSync(fd);
  }
}

const HOME = homedir();
const cwd = process.cwd();

// Project-scoped roots — highest priority (present only inside an AI-OS project)
const projectSkillRoots = [];
const projectAgentRoots = [];
if (existsSync(join(cwd, ".ai"))) {
  projectSkillRoots.push(
    join(cwd, ".claude", "skills"),
    join(cwd, ".gemini", "skills")
  );
  projectAgentRoots.push(
    join(cwd, ".claude", "agents"),
    join(cwd, ".gemini", "agents")
  );
}

// Search roots — ordered by priority: project-scoped → global → source dev
const SKILL_ROOTS = [
  ...projectSkillRoots,
  join(HOME, ".claude", "skills"),
  join(HOME, ".gemini", "skills"),
  join(HOME, ".ai-os", "shared", "skills"),
  join(HOME, ".ai-os", "claude", "skills"),
];

const AGENT_ROOTS = [
  ...projectAgentRoots,
  join(HOME, ".claude", "agents"),
  join(HOME, ".ai-os", "claude", "agents"),
  join(HOME, ".ai-os", "gemini", "agents"),
];

// Also scan source repo if CWD contains src/
const srcBase = resolve(cwd, "src");
if (existsSync(srcBase)) {
  SKILL_ROOTS.push(
    join(srcBase, "shared", "skills"),
    join(srcBase, "claude", "skills"),
    join(srcBase, "gemini", "skills")
  );
  AGENT_ROOTS.push(
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

function withinRoot(root, filePath) {
  return resolve(filePath).startsWith(resolve(root) + sep);
}

function findSkill(name) {
  for (const root of SKILL_ROOTS) {
    // Skills 2.0: <root>/<name>/SKILL.md
    const modular = join(root, name, "SKILL.md");
    if (!withinRoot(root, modular)) continue;
    if (existsSync(modular)) return { path: modular, content: readFileSync(modular, "utf8") };
    // Flat legacy: <root>/<name>.md
    const flat = join(root, `${name}.md`);
    if (!withinRoot(root, flat)) continue;
    if (existsSync(flat)) return { path: flat, content: readFileSync(flat, "utf8") };
  }
  return null;
}

function findAgent(name) {
  // Normalize: strip .md suffix if provided
  const base = name.replace(/\.md$/, "");
  for (const root of AGENT_ROOTS) {
    const p = join(root, `${base}.md`);
    if (!withinRoot(root, p)) continue;
    if (existsSync(p)) return { path: p, content: readFileSync(p, "utf8") };
  }
  return null;
}

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};
  const fm = {};
  for (const line of match[1].split("\n")) {
    const colon = line.indexOf(":");
    if (colon === -1) continue;
    const key = line.slice(0, colon).trim();
    const val = line.slice(colon + 1).trim();
    fm[key] = val;
  }
  return fm;
}

function listAvailable(roots, ext) {
  const found = new Map(); // name → description
  for (const root of roots) {
    if (!existsSync(root)) continue;
    try {
      for (const entry of readdirSync(root, { withFileTypes: true })) {
        let name, filePath;
        if (entry.isDirectory()) {
          const skill = join(root, entry.name, "SKILL.md");
          if (!existsSync(skill)) continue;
          name = entry.name;
          filePath = skill;
        } else if (entry.name.endsWith(ext)) {
          name = entry.name.replace(ext, "");
          filePath = join(root, entry.name);
        } else {
          continue;
        }
        if (found.has(name)) continue; // first-found wins (priority order)
        try {
          const head = readHead(filePath); // 4 KB max — frontmatter always within first 4 KB
          const fm = parseFrontmatter(head);
          found.set(name, fm.description || "");
        } catch {
          found.set(name, "");
        }
      }
    } catch (_) { /* skip unreadable dirs */ }
  }
  return [...found.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

const server = new Server(
  { name: "context-invoker-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "list_skills",
      description:
        "Returns metadata-only summaries for all available skills (name + one-line description). " +
        "Use this FIRST to discover what skills are available before loading one with activate_skill. " +
        "This is Level 1 (metadata-only) per §29 JIT Skill Loading — zero token cost.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "list_agents",
      description:
        "Returns metadata-only summaries for all available agents (name + one-line description). " +
        "Use this FIRST to discover what agents are available before loading one with activate_agent. " +
        "This is Level 1 (metadata-only) per §29 JIT Skill Loading — zero token cost.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "activate_skill",
      description:
        "Returns the FULL SKILL.md content for a named Claude/shared skill (Level 2 — full load). " +
        "Call list_skills first to discover available skill names with metadata-only cost. " +
        "Only call this when you are ready to execute the skill — do NOT preload speculatively.",
      inputSchema: {
        type: "object",
        properties: {
          skill_name: {
            type: "string",
            description: "Name of the skill (e.g. 'ai-update', 'scope_safety', 'ai-digest')",
          },
          list_skills: {
            type: "boolean",
            description: "DEPRECATED: use the list_skills tool instead. If true, returns metadata list.",
            default: false,
          },
        },
        required: ["skill_name"],
      },
    },
    {
      name: "activate_agent",
      description:
        "Returns the FULL agent .md content for a named Claude/Gemini agent (Level 2 — full load). " +
        "Call list_agents first to discover available agent names with metadata-only cost. " +
        "Only call this when you are ready to delegate to the agent — do NOT preload speculatively.",
      inputSchema: {
        type: "object",
        properties: {
          agent_name: {
            type: "string",
            description: "Name of the agent (e.g. 'chaos_monkey', 'devops_engineer', 'security_engineer')",
          },
          list_agents: {
            type: "boolean",
            description: "DEPRECATED: use the list_agents tool instead. If true, returns metadata list.",
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
    // ── list_skills — Level 1 metadata-only (§29 JIT Skill Loading) ──────────
    case "list_skills": {
      const skills = listAvailable(SKILL_ROOTS, ".md");
      const lines = skills.map(([n, desc]) => desc ? `  - ${n}: ${desc}` : `  - ${n}`);
      return {
        content: [{ type: "text", text: `## Available Skills (metadata-only — use activate_skill for full content)\n${lines.join("\n")}` }],
      };
    }

    // ── list_agents — Level 1 metadata-only (§29 JIT Skill Loading) ──────────
    case "list_agents": {
      const agents = listAvailable(AGENT_ROOTS, ".md");
      const lines = agents.map(([n, desc]) => desc ? `  - ${n}: ${desc}` : `  - ${n}`);
      return {
        content: [{ type: "text", text: `## Available Agents (metadata-only — use activate_agent for full content)\n${lines.join("\n")}` }],
      };
    }

    case "activate_skill": {
      if (args.list_skills) {
        const skills = listAvailable(SKILL_ROOTS, ".md");
        const lines = skills.map(([name, desc]) => desc ? `  - ${name}: ${desc}` : `  - ${name}`);
        return {
          content: [{ type: "text", text: `Available skills:\n${lines.join("\n")}` }],
        };
      }
      const skillErr = validateName(args.skill_name);
      if (skillErr) {
        return { content: [{ type: "text", text: `✗ ${skillErr}` }], isError: true };
      }
      const result = findSkill(args.skill_name);
      if (!result) {
        const skills = listAvailable(SKILL_ROOTS, ".md");
        const lines = skills.map(([name, desc]) => desc ? `  - ${name}: ${desc}` : `  - ${name}`);
        return {
          content: [{
            type: "text",
            text: `✗ Skill '${args.skill_name}' not found.\n\nAvailable skills:\n${lines.join("\n")}`,
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
        const lines = agents.map(([name, desc]) => desc ? `  - ${name}: ${desc}` : `  - ${name}`);
        return {
          content: [{ type: "text", text: `Available agents:\n${lines.join("\n")}` }],
        };
      }
      const agentErr = validateName(args.agent_name);
      if (agentErr) {
        return { content: [{ type: "text", text: `✗ ${agentErr}` }], isError: true };
      }
      const result = findAgent(args.agent_name);
      if (!result) {
        const agents = listAvailable(AGENT_ROOTS, ".md");
        const lines = agents.map(([name, desc]) => desc ? `  - ${name}: ${desc}` : `  - ${name}`);
        return {
          content: [{
            type: "text",
            text: `✗ Agent '${args.agent_name}' not found.\n\nAvailable agents:\n${lines.join("\n")}`,
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
