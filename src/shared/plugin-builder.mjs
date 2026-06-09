#!/usr/bin/env node
/**
 * plugin-builder.mjs — E-144 (native-subagents.md, reconciled to the agy plugin mechanism)
 *
 * Builds the AI-OS personas into an Antigravity (`agy`) PLUGIN. agy registers custom
 * subagents ONLY from installed plugins (`agy plugin install <dir>` → ~/.gemini/config/
 * plugins/<name>/ → visible in /agents). Loose workspace .agents/agents/<name>/agent.json
 * files are NOT scanned by agy (skills auto-load; agents do not) — that mechanism (the
 * retired subagent-mapper.mjs) never registered. Confirmed empirically 2026-06-08.
 *
 * Plugin layout (validated by `agy plugin validate`):
 *   <out>/plugin.json                     { name, version, description }
 *   <out>/agents/<name>/agent.json        agy-native schema (see toSubagent below)
 *
 * Source of truth: the persona .md files in src/claude/agents + src/gemini/agents
 * (personas only — skips context:default / type:skill, which are skills not agents).
 *
 * CLI:  node plugin-builder.mjs
 *   Builds the fixed target: <repo-root>/src/agents/plugin from the framework
 *   personas. The repo root is derived from this script's own location (two levels
 *   up), so it is correct whether run from the dev tree or the ~/.ai-os mirror.
 *   For custom in/out dirs (tests), call the exported buildPlugin(repoRoot, outDir).
 * Exports: parseAgent, toSubagent, listAgents, buildPlugin (for tests).
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, statSync, rmSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));

// LEAST-PRIVILEGE tool grant (E-149..E-152 Tier-3 review hardening). agy's
// `define_subagent` default grants the full set incl. schedule/search_web; that is an
// autonomy + injection surface a read-only agent (e.g. sre_responder, which ingests
// untrusted incident logs) must not carry. So every subagent gets only the READ set by
// default; web (search_web/read_url_content), schedule (cron), and write tools are
// OPT-IN, derived from the persona's allowed-tools + description.
const READ_TOOLS  = ["send_message", "find_by_name", "grep_search", "view_file", "list_dir"];
const WEB_TOOLS   = ["read_url_content", "search_web"];
const WRITE_TOOLS = ["write_file", "replace_file_content"];
const INCLUDE_SECTIONS = [
  "user_information", "mcp_servers", "skills",
  "subagent_reminder", "messaging", "artifacts", "user_rules",
];

/** Parse YAML-ish frontmatter + markdown body from a persona .md file. */
export function parseAgent(content) {
  const m = content.match(/^---\n([\s\S]*?)\n---\n?/);
  const fm = {};
  let body = content;
  if (m) {
    body = content.slice(m[0].length);
    for (const line of m[1].split("\n")) {
      const c = line.indexOf(":");
      if (c === -1) continue;
      fm[line.slice(0, c).trim()] = line.slice(c + 1).trim().replace(/^["']|["']$/g, "");
    }
  }
  return { fm, body };
}

/** Convert a parsed persona to an agy-native agent.json object. */
export function toSubagent(fm, body, base) {
  const name = fm.name || base;
  const tools = (fm["allowed-tools"] || "").toLowerCase();
  const desc = (fm.description || "").toLowerCase();
  const hay = tools + " " + desc;
  const canWrite = /\b(write|edit|notebookedit)\b/.test(tools);
  // Opt-in: only grant web/schedule when the persona signals it needs them, so a
  // read-only agent (e.g. sre_responder) never carries cron/external-fetch surface.
  const wantsWeb = /\b(websearch|webfetch|web_?search|read_url|browser|fetch|http|seo|research|url|docs?)\b/.test(hay);
  // `schedule` is cron/autonomy surface — grant ONLY when the persona's allowed-tools
  // explicitly lists it (never inferred from cadence words like "daily" in a description,
  // which describe the SKILL's external trigger, not an agent tool need). E-149..E-152 review.
  const wantsSchedule = /\bschedule\b/.test(tools);
  const toolNames = [...READ_TOOLS];
  if (wantsWeb) toolNames.push(...WEB_TOOLS);
  if (wantsSchedule) toolNames.push("schedule");
  if (canWrite) toolNames.push(...WRITE_TOOLS);
  return {
    name,
    description: fm.description || "",
    hidden: false, // visible in /agents
    config: {
      customAgent: {
        systemPromptSections: [
          { title: "Agent System Instructions", content: body.trim() },
        ],
        toolNames,
        systemPromptConfig: { includeSections: [...INCLUDE_SECTIONS] },
      },
    },
  };
}

/**
 * Discover personas across the given agent dirs (deduped by base name, first wins,
 * dirs scanned in order). Skips skills (context:default / type:skill) and unreadable
 * files (one malformed .md must not abort the whole build). Returns sorted by name.
 */
export function listAgents(agentDirs) {
  const seen = new Set();
  const out = [];
  for (const dir of agentDirs) {
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir).sort()) {
      if (!f.endsWith(".md")) continue;
      const base = f.replace(/\.md$/, "");
      if (seen.has(base)) continue;
      const p = join(dir, f);
      let content;
      try {
        if (!statSync(p).isFile()) continue;
        content = readFileSync(p, "utf8");
      } catch {
        continue; // skip unreadable/malformed file, keep building
      }
      const { fm, body } = parseAgent(content);
      if (fm.context === "default" || fm.type === "skill") continue;
      seen.add(base);
      out.push(toSubagent(fm, body, base));
    }
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  return out;
}

/**
 * Build the plugin into outDir from the persona dirs under repoRoot. Wipes and
 * rewrites outDir for a deterministic result. Returns the sorted agent names.
 */
export function buildPlugin(repoRoot, outDir) {
  const agentDirs = [
    resolve(repoRoot, "src/claude/agents"),
    resolve(repoRoot, "src/gemini/agents"),
  ];
  const agents = listAgents(agentDirs);

  if (existsSync(outDir)) rmSync(outDir, { recursive: true, force: true });
  mkdirSync(join(outDir, "agents"), { recursive: true });
  writeFileSync(
    join(outDir, "plugin.json"),
    JSON.stringify({
      name: "ai-os",
      version: "2.0.0",
      description: "AI-OS personas (critics, engineers, reviewers) as native Antigravity subagents.",
    }, null, 2) + "\n",
    "utf8",
  );
  for (const agent of agents) {
    const d = join(outDir, "agents", agent.name);
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, "agent.json"), JSON.stringify(agent, null, 2) + "\n", "utf8");
  }
  return agents.map((a) => a.name);
}

// CLI entry — only when run directly (sourcing for tests must not build). Builds the
// fixed target derived from this script's location; no arbitrary path args (tests
// drive custom dirs through the exported buildPlugin()).
if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  // repo root = two levels up from src/shared/ (dirname twice, no traversal literal).
  const repoRoot = dirname(dirname(SCRIPT_DIR));
  const outDir = resolve(repoRoot, "src/agents/plugin");
  const names = buildPlugin(repoRoot, outDir);
  process.stdout.write(`ai-os plugin built at ${outDir}\n  ${names.length} agents: ${names.join(", ")}\n`);
}
