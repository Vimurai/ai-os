/**
 * subagent-mapper.mjs — E-140 (native-subagents.md)
 *
 * Maps AI-OS framework agents (.claude/agents/, .gemini/agents/) to native
 * Antigravity subagent manifests in .agents/agents/ so they appear in the `agy`
 * agent UI. Each manifest is the blueprint's define_subagent payload: it does NOT
 * duplicate the agent's logic — it delegates to the real agent via
 * `activate_agent({ agent_name })` (context-invoker-mcp), keeping a single source
 * of truth. Idempotent (stable filenames, overwrite-in-place) and fast (one pass).
 *
 * CLI:  node subagent-mapper.mjs            → map agents → .agents/agents/
 *       node subagent-mapper.mjs --clear    → remove ai-os-*.json manifests
 * Exports: listAgents, toSubagent, mapAgents, clearAgents (for tests).
 */
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmSync, statSync } from "node:fs";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

const MANIFEST_PREFIX = "ai-os-";

/** Minimal YAML frontmatter parser (mirrors context-invoker-mcp: single-line key:value). */
function parseFrontmatter(content) {
  const m = content.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const fm = {};
  for (const line of m[1].split("\n")) {
    const c = line.indexOf(":");
    if (c === -1) continue;
    fm[line.slice(0, c).trim()] = line.slice(c + 1).trim().replace(/^["']|["']$/g, "");
  }
  return fm;
}

/** List agents across the given dirs as {name, description}. First-found wins (dedup). */
export function listAgents(agentDirs) {
  const seen = new Set();
  const out = [];
  for (const dir of agentDirs) {
    if (!existsSync(dir)) continue;
    let entries;
    try { entries = readdirSync(dir); } catch { continue; }
    for (const f of entries.sort()) {
      if (!f.endsWith(".md")) continue;
      const base = f.replace(/\.md$/, "");
      if (seen.has(base)) continue; // dedup: an agent defined in multiple dirs maps once
      const path = join(dir, f);
      try { if (!statSync(path).isFile()) continue; } catch { continue; }
      seen.add(base);
      const fm = parseFrontmatter(readFileSync(path, "utf8"));
      // E-142 (native-subagents.md taxonomy): only autonomous PERSONAS become native
      // Antigravity subagents. Skip procedural skills — they carry `context: default`
      // or `type: skill` and belong in .agents/skills/, not the agent dirs.
      if (fm.context === "default" || fm.type === "skill") continue;
      out.push({ name: fm.name || base, description: fm.description || "" });
    }
  }
  return out;
}

/** Translate an AI-OS agent into the Antigravity define_subagent payload. */
export function toSubagent(agent) {
  return {
    name: `${MANIFEST_PREFIX}${agent.name}`,
    description: agent.description,
    // Delegate to the real agent rather than re-implementing it; enforce AI-OS
    // boundaries in the prompt per native-subagents.md §Security.
    system_prompt:
      `You are the ${agent.name} agent. Your job is to invoke ` +
      `activate_agent({ agent_name: '${agent.name}' }) and follow the returned ` +
      `instructions exactly. Respect all AI-OS boundaries: stay within the ` +
      `CAPABILITIES.md scope for this workspace and route every shell command ` +
      `through safe-exec-mcp. Do not act outside the project workspace.`,
    enable_mcp_tools: true,
  };
}

/** Map agents from agentDirs into .agents/agents/ manifests. Returns the manifest names. */
export function mapAgents(agentDirs, outDir) {
  mkdirSync(outDir, { recursive: true });
  const names = [];
  for (const agent of listAgents(agentDirs)) {
    const sub = toSubagent(agent);
    // E-142: agy discovers each agent as a per-agent subdir <name>/agent.json (per the
    // `agy` "Create New Agents" screen: .agents/agents/{agent_name}/), NOT a flat <name>.json.
    const agentDir = join(outDir, sub.name);
    mkdirSync(agentDir, { recursive: true });
    writeFileSync(join(agentDir, "agent.json"), JSON.stringify(sub, null, 2) + "\n", "utf8");
    names.push(sub.name);
  }
  return names;
}

/** Remove only the AI-OS-generated manifests (leaves any hand-authored subagents). */
export function clearAgents(outDir) {
  if (!existsSync(outDir)) return 0;
  let removed = 0;
  for (const entry of readdirSync(outDir, { withFileTypes: true })) {
    if (!entry.name.startsWith(MANIFEST_PREFIX)) continue;
    const p = join(outDir, entry.name);
    if (entry.isDirectory()) { rmSync(p, { recursive: true, force: true }); removed++; }  // E-142 subdir format
    else if (entry.name.endsWith(".json")) { rmSync(p); removed++; }                       // legacy flat (pre-E-142)
  }
  return removed;
}

// ── CLI entry (only when executed directly, not when imported by tests) ───────
const _isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (_isMain) {
  const cwd = process.cwd();
  const outDir = resolve(cwd, ".agents", "agents");
  if (process.argv.slice(2).includes("--clear")) {
    const n = clearAgents(outDir);
    process.stdout.write(`✓ cleared ${n} AI-OS subagent manifest(s) from .agents/agents/\n`);
  } else {
    const dirs = [resolve(cwd, ".claude", "agents"), resolve(cwd, ".gemini", "agents")];
    const names = mapAgents(dirs, outDir);
    process.stdout.write(
      `✓ mapped ${names.length} AI-OS agent(s) → .agents/agents/ as native Antigravity subagents` +
      (names.length ? `:\n  ${names.join("\n  ")}\n` : "\n")
    );
  }
}
