#!/usr/bin/env node
/**
 * ast-parser-mcp — E-95 (ast-repository-map.md §Components 1, §API)
 *
 * MCP server encapsulating Tree-sitter (WASM, via extractor.mjs). Exposes
 * `parse_workspace`: scans a directory, applies ignore rules (.gitignore +
 * .ai-osignore + .env*), skips node_modules/.git/large/minified files, and
 * returns a JSON array of extracted symbols per the blueprint Data Model.
 * Symbol ranking (centrality_score) is added by the repo-mapper (E-96).
 *
 * Security (blueprint §Security): never indexes secret files (.env*) or
 * node_modules; stays within the resolved workspace root (no path escape);
 * per-file parse timeout + 1 MB size cap bound CPU (DoS).
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { resolve, relative, join, sep } from "node:path";
import { languageForFile, extractFromSource } from "./extractor.mjs";

const MAX_FILE_BYTES = 1_000_000; // skip files > 1 MB (DoS / minified bundles)
const DEFAULT_MAX_FILES = 2000;
const ALWAYS_SKIP_DIRS = new Set(["node_modules", ".git"]);

// ── Ignore rules ─────────────────────────────────────────────────────────────

/** Build an ignore predicate from .gitignore + .ai-osignore (pragmatic glob). */
function buildIgnore(rootDir) {
  const patterns = [];
  for (const f of [".gitignore", ".ai-osignore"]) {
    const p = resolve(rootDir, f);
    if (!existsSync(p)) continue;
    for (const raw of readFileSync(p, "utf8").split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#") || line.startsWith("!")) continue;
      patterns.push(line.replace(/\/$/, ""));
    }
  }
  const toRe = (pat) => {
    const anchored = pat.startsWith("/");
    const body = pat.replace(/^\//, "")
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*/g, "[^/]*");
    return { re: new RegExp(`^${body}$`), anchored, raw: pat.replace(/^\//, "") };
  };
  const compiled = patterns.map(toRe);

  return (relPath) => {
    // Secrets are never indexed, regardless of ignore files.
    const base = relPath.split("/").pop();
    if (/^\.env(\..+)?$/.test(base)) return true;
    if (/\.min\.(js|mjs|cjs|ts)$/.test(base)) return true;
    const segs = relPath.split("/");
    for (const { re, anchored, raw } of compiled) {
      if (anchored) {
        if (re.test(relPath) || relPath.startsWith(raw + "/")) return true;
      } else if (segs.some((s) => re.test(s)) || re.test(relPath)) {
        return true;
      }
    }
    return false;
  };
}

// ── Workspace walk ───────────────────────────────────────────────────────────

function collectSourceFiles(rootDir, ignore, maxFiles) {
  const files = [];
  const stack = [rootDir];
  while (stack.length && files.length < maxFiles) {
    const dir = stack.pop();
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const ent of entries) {
      const abs = join(dir, ent.name);
      const rel = relative(rootDir, abs).split(sep).join("/");
      if (ent.isDirectory()) {
        if (ALWAYS_SKIP_DIRS.has(ent.name) || ignore(rel)) continue;
        stack.push(abs);
      } else if (ent.isFile()) {
        if (!languageForFile(ent.name) || ignore(rel)) continue;
        files.push({ abs, rel });
      }
    }
  }
  return files;
}

async function parseWorkspace(dirPath, maxFiles) {
  const cwd = process.cwd();
  const rootDir = resolve(cwd, dirPath || ".");
  // Containment — never traverse outside the invoking workspace.
  if (rootDir !== cwd && !rootDir.startsWith(cwd + sep)) {
    return { error: `[PATH_DENIED] dir_path escapes the workspace root: ${dirPath}` };
  }
  if (!existsSync(rootDir)) return { error: `[NOT_FOUND] ${rootDir}` };

  const ignore = buildIgnore(rootDir);
  const files = collectSourceFiles(rootDir, ignore, maxFiles || DEFAULT_MAX_FILES);

  const symbols = [];
  let skipped = 0;
  for (const f of files) {
    let content;
    try {
      content = readFileSync(f.abs);
      if (content.length > MAX_FILE_BYTES) { skipped++; continue; }
      content = content.toString("utf8");
    } catch { skipped++; continue; }
    const sym = await extractFromSource(content, languageForFile(f.abs));
    if (!sym) { skipped++; continue; }
    if (sym.exports.length || sym.classes.length || sym.imports.length) {
      symbols.push({ file_path: f.rel, exports: sym.exports, classes: sym.classes, imports: sym.imports });
    }
  }
  return { root: relative(cwd, rootDir) || ".", file_count: files.length, skipped, symbols };
}

// ── Server ───────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "ast-parser-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "parse_workspace",
      description:
        "E-95 (ast-repository-map.md): scan a directory and return extracted TS/JS symbols " +
        "(exports, classes+method signatures, imports) per file. Respects .gitignore + " +
        ".ai-osignore, never indexes .env*/node_modules, skips minified and >1MB files. " +
        "Ranking (centrality_score) is applied by the repo-mapper (E-96).",
      inputSchema: {
        type: "object",
        properties: {
          dir_path:  { type: "string", description: "Directory to scan, relative to the workspace root (default '.')." },
          max_files: { type: "number", description: `Cap on files parsed (default ${DEFAULT_MAX_FILES}).` },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  if (name !== "parse_workspace") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
  try {
    const result = await parseWorkspace(args?.dir_path, args?.max_files);
    if (result.error) {
      return { content: [{ type: "text", text: result.error }], isError: true };
    }
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  } catch (e) {
    return { content: [{ type: "text", text: `[PARSE_ERROR] ${e.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
