#!/usr/bin/env node
/**
 * cache-manager-mcp — AI-OS Explicit Context Cache (E-11)
 *
 * Assembles and persists a "System Context" blob from the AI-OS blueprint
 * files so agents can include it as a long-lived prompt prefix — enabling
 * Anthropic's prompt caching to eliminate per-turn JIT read costs.
 *
 * Blueprint: .ai/blueprints/caching.md
 *
 * Cache payload (per caching.md §2):
 *   - .ai/architect.md
 *   - .ai/blueprints/*.md
 *   - .ai/state.sqlite schema (via sqlite_master, not shell)
 *   - src/config/registry.json
 *
 * Invalidation (per caching.md §3):
 *   Cache is rebuilt only when a tracked file's mtime changes or a new
 *   .ai/blueprints/*.md file appears. Checked on every get_cached_context call.
 *
 * Tools:
 *   build_cache(project_root?)          → build/rebuild cache now
 *   get_cached_context(project_root?)   → return cached blob (auto-rebuild if stale)
 *   invalidate_cache()                  → mark cache stale (forces next rebuild)
 *   get_cache_status()                  → cache age, file count, validity, mtimes
 *
 * Security:
 *   - project_root validated: absolute, no ".." traversal, must exist.
 *   - DB path fixed to ~/.ai-os/cache.sqlite — never user-controlled.
 *   - All file reads use readFileSync (no execSync / shell).
 *   - SQLite schema extracted via sqlite_master query (not .schema command).
 *
 * Observability:
 *   Structured JSON logs to stderr:
 *   { timestamp, level, service:"cache-manager-mcp", tool, latency_ms, error? }
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { instrument } from "../../shared/mcp-telemetry.mjs";
import { DatabaseSync } from "node:sqlite";
import {
  readFileSync,
  statSync,
  readdirSync,
  mkdirSync,
  existsSync,
} from "node:fs";
import { resolve, join, basename, isAbsolute } from "node:path";
import { homedir } from "node:os";
import { createLogger } from "../shared/logger.js";

// ── Constants ─────────────────────────────────────────────────────────────────

const SERVICE = "cache-manager-mcp";
const VERSION = "1.0.0";

const STORE_DIR = resolve(homedir(), ".ai-os");
const DB_PATH   = join(STORE_DIR, "cache.sqlite");

// ── Structured logger ─────────────────────────────────────────────────────────
// Shared NDJSON logger; emits one JSON line per call to stderr.

const logger = createLogger(SERVICE);
const log = (level, tool, message, extras) => logger.log(level, tool, message, extras);

// ── SQLite setup ──────────────────────────────────────────────────────────────

let db = null;

function getDb() {
  if (db) return db;
  try {
    mkdirSync(STORE_DIR, { recursive: true });
    const conn = new DatabaseSync(DB_PATH);
    conn.exec("PRAGMA journal_mode = WAL;");
    conn.exec(`
      CREATE TABLE IF NOT EXISTS cache_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS cache_files (
        path       TEXT PRIMARY KEY,
        mtime_ms   INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        role       TEXT NOT NULL
      );
    `);
    db = conn;
    return db;
  } catch (e) {
    log("error", "init", "DB init failed", { error: e.message, code: e.code });
    return null;
  }
}

// ── Project root validation ───────────────────────────────────────────────────

/**
 * Validate and normalise project_root.
 * Returns an absolute, traversal-safe path or throws on invalid input.
 */
function validateProjectRoot(raw) {
  const root = raw ? String(raw).trim() : process.cwd();

  if (!isAbsolute(root)) {
    throw new Error(`project_root must be an absolute path, got: ${root}`);
  }
  // Prevent path traversal
  if (root.includes("..")) {
    throw new Error(`project_root must not contain ".." segments`);
  }
  if (!existsSync(root)) {
    throw new Error(`project_root does not exist: ${root}`);
  }
  return root;
}

// ── Blueprint file discovery ──────────────────────────────────────────────────

/**
 * Returns the list of files that make up the cache payload, in display order.
 * Each entry: { path, role }
 */
function discoverPayloadFiles(projectRoot) {
  const files = [];

  // architect.md
  const architectPath = join(projectRoot, ".ai", "architect.md");
  if (existsSync(architectPath)) {
    files.push({ path: architectPath, role: "architect" });
  }

  // .ai/blueprints/*.md  (sorted for deterministic order)
  const blueprintsDir = join(projectRoot, ".ai", "blueprints");
  if (existsSync(blueprintsDir)) {
    const names = readdirSync(blueprintsDir)
      .filter((n) => n.endsWith(".md"))
      .sort();
    for (const name of names) {
      files.push({ path: join(blueprintsDir, name), role: "blueprint" });
    }
  }

  // src/config/registry.json
  const registryPath = join(projectRoot, "src", "config", "registry.json");
  if (existsSync(registryPath)) {
    files.push({ path: registryPath, role: "registry" });
  }

  return files;
}

/**
 * Attempt to read the SQLite schema from .ai/state.sqlite via sqlite_master.
 * Returns a schema string, or a "(unavailable)" notice on error.
 */
function readSqliteSchema(projectRoot) {
  const sqlitePath = join(projectRoot, ".ai", "state.sqlite");
  if (!existsSync(sqlitePath)) {
    return "(state.sqlite not found)";
  }
  let sdb;
  try {
    sdb = new DatabaseSync(sqlitePath, { readonly: true });
    const rows = sdb
      .prepare(
        "SELECT sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL ORDER BY name"
      )
      .all();
    return rows.map((r) => r.sql).join("\n\n");
  } catch (e) {
    return `(error reading schema: ${e.message})`;
  } finally {
    try { sdb?.close(); } catch { /* ignore */ }
  }
}

// ── Cache assembly ────────────────────────────────────────────────────────────

/**
 * Build the System Context blob from the payload files.
 * Returns { blob: string, fileRecords: Array<{path,mtime_ms,size_bytes,role}> }
 */
function assembleContext(projectRoot) {
  const payloadFiles = discoverPayloadFiles(projectRoot);
  const sections = [];
  const fileRecords = [];

  sections.push(`=== AI-OS SYSTEM CONTEXT CACHE ===`);
  sections.push(`Built: ${new Date().toISOString()}`);
  sections.push(`Source: ${projectRoot}`);
  sections.push(`Files: ${payloadFiles.length} (+ state.sqlite schema)`);
  sections.push("");

  for (const { path, role } of payloadFiles) {
    try {
      const stat = statSync(path);
      const content = readFileSync(path, "utf8");
      const label = path.replace(projectRoot + "/", "");

      sections.push(`--- ${label} (${role}) ---`);
      sections.push(content.trimEnd());
      sections.push("");

      fileRecords.push({
        path,
        mtime_ms:   Math.round(stat.mtimeMs),
        size_bytes: stat.size,
        role,
      });
    } catch (e) {
      log("warn", "assemble", `Skipping unreadable file: ${path}`, {
        error: e.message,
      });
    }
  }

  // SQLite schema (not a regular file — derived from DB read)
  const schema = readSqliteSchema(projectRoot);
  sections.push(`--- .ai/state.sqlite (schema) ---`);
  sections.push(schema);
  sections.push("");

  sections.push(`=== END SYSTEM CONTEXT ===`);

  return { blob: sections.join("\n"), fileRecords };
}

// ── Staleness check ───────────────────────────────────────────────────────────

/**
 * Returns true when the cache needs rebuilding:
 *   - cache_meta.valid !== '1'
 *   - any tracked file's mtime differs from stored value
 *   - a new .ai/blueprints/*.md file appeared
 */
function isCacheStale(d, projectRoot) {
  const valid = d
    .prepare("SELECT value FROM cache_meta WHERE key = 'valid'")
    .get();
  if (!valid || valid.value !== "1") return true;

  const storedRoot = d
    .prepare("SELECT value FROM cache_meta WHERE key = 'project_root'")
    .get();
  if (!storedRoot || storedRoot.value !== projectRoot) return true;

  // Check existing tracked files
  const tracked = d.prepare("SELECT path, mtime_ms FROM cache_files").all();
  for (const row of tracked) {
    try {
      const stat = statSync(row.path);
      if (Math.round(stat.mtimeMs) !== row.mtime_ms) return true;
    } catch {
      return true; // file deleted
    }
  }

  // Check for new blueprint files not in tracked set
  const trackedPaths = new Set(tracked.map((r) => r.path));
  const blueprintsDir = join(projectRoot, ".ai", "blueprints");
  if (existsSync(blueprintsDir)) {
    const current = readdirSync(blueprintsDir)
      .filter((n) => n.endsWith(".md"))
      .map((n) => join(blueprintsDir, n));
    for (const p of current) {
      if (!trackedPaths.has(p)) return true;
    }
  }

  return false;
}

// ── Persist cache ─────────────────────────────────────────────────────────────

function persistCache(d, blob, fileRecords, projectRoot) {
  d.exec("DELETE FROM cache_files;");

  const setMeta = d.prepare(
    "INSERT OR REPLACE INTO cache_meta(key, value) VALUES (?, ?)"
  );
  const insertFile = d.prepare(
    "INSERT OR REPLACE INTO cache_files(path, mtime_ms, size_bytes, role) VALUES (?, ?, ?, ?)"
  );

  setMeta.run("context_blob",  blob);
  setMeta.run("built_at",      new Date().toISOString());
  setMeta.run("valid",         "1");
  setMeta.run("project_root",  projectRoot);
  setMeta.run("file_count",    String(fileRecords.length));
  setMeta.run("char_count",    String(blob.length));

  for (const rec of fileRecords) {
    insertFile.run(rec.path, rec.mtime_ms, rec.size_bytes, rec.role);
  }
}

// ── Estimated token count (rough approximation: 1 token ≈ 4 chars) ───────────

function estimateTokens(charCount) {
  return Math.round(charCount / 4);
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: SERVICE, version: VERSION },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "build_cache",
      description:
        "Force-rebuild the System Context cache from all blueprint files " +
        "(.ai/architect.md, .ai/blueprints/*.md, state.sqlite schema, " +
        "src/config/registry.json). Stores the assembled blob in SQLite with " +
        "file mtimes for change detection. Returns the full context blob.",
      inputSchema: {
        type: "object",
        properties: {
          project_root: {
            type: "string",
            description:
              "Absolute path to the AI-OS project root. Defaults to cwd. " +
              "Must not contain '..' path traversal segments.",
          },
        },
      },
    },
    {
      name: "get_cached_context",
      description:
        "Return the cached System Context blob. Automatically rebuilds if any " +
        "tracked file's mtime changed or a new blueprint file appeared. " +
        "Use the returned blob as a long-lived system prompt prefix to enable " +
        "Anthropic prompt caching and eliminate per-turn JIT read costs.",
      inputSchema: {
        type: "object",
        properties: {
          project_root: {
            type: "string",
            description:
              "Absolute path to the AI-OS project root. Defaults to cwd.",
          },
        },
      },
    },
    {
      name: "invalidate_cache",
      description:
        "Mark the cache as stale without rebuilding. The next call to " +
        "get_cached_context or build_cache will trigger a full rebuild. " +
        "Use after manually editing blueprint files outside of normal hooks.",
      inputSchema: {
        type: "object",
        properties: {},
      },
    },
    {
      name: "get_cache_status",
      description:
        "Return cache metadata: validity, build timestamp, file count, " +
        "context size (chars + estimated tokens), project root, and the " +
        "mtime of each tracked file. Use for observability and debugging.",
      inputSchema: {
        type: "object",
        properties: {},
      },
    },
  ],
}));

instrument(server, "cache-manager-mcp", CallToolRequestSchema);
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const t0 = Date.now();

  try {
    switch (name) {
      // ── build_cache ────────────────────────────────────────────────────────
      case "build_cache": {
        const projectRoot = validateProjectRoot(args?.project_root);
        log("info", name, "Building cache", { project_root: projectRoot });

        const { blob, fileRecords } = assembleContext(projectRoot);
        const d = getDb();
        if (!d) {
          return {
            content: [
              {
                type: "text",
                text:
                  "[CACHE_WARN] SQLite unavailable — context assembled in-memory only.\n\n" +
                  blob,
              },
            ],
          };
        }

        persistCache(d, blob, fileRecords, projectRoot);
        log("info", name, "Cache built", {
          files: fileRecords.length,
          chars: blob.length,
          latency_ms: Date.now() - t0,
        });

        return {
          content: [
            {
              type: "text",
              text:
                `[CACHE_BUILT] ${fileRecords.length} files cached | ` +
                `${blob.length.toLocaleString()} chars | ` +
                `~${estimateTokens(blob.length).toLocaleString()} tokens\n` +
                `DB: ${DB_PATH}\n\n` +
                blob,
            },
          ],
        };
      }

      // ── get_cached_context ─────────────────────────────────────────────────
      case "get_cached_context": {
        const projectRoot = validateProjectRoot(args?.project_root);
        const d = getDb();

        if (!d) {
          log("warn", name, "SQLite unavailable — building in-memory");
          const { blob } = assembleContext(projectRoot);
          return { content: [{ type: "text", text: blob }] };
        }

        const stale = isCacheStale(d, projectRoot);
        if (stale) {
          log("info", name, "Cache stale — rebuilding", {
            project_root: projectRoot,
          });
          const { blob, fileRecords } = assembleContext(projectRoot);
          persistCache(d, blob, fileRecords, projectRoot);
          log("info", name, "Cache rebuilt", {
            files: fileRecords.length,
            chars: blob.length,
            latency_ms: Date.now() - t0,
          });
          return {
            content: [
              {
                type: "text",
                text:
                  `[CACHE_REBUILT] ${fileRecords.length} files | ` +
                  `~${estimateTokens(blob.length).toLocaleString()} tokens\n\n` +
                  blob,
              },
            ],
          };
        }

        const row = d
          .prepare("SELECT value FROM cache_meta WHERE key = 'context_blob'")
          .get();
        const blob = row?.value ?? "";
        log("info", name, "Cache hit", {
          chars: blob.length,
          latency_ms: Date.now() - t0,
        });
        return {
          content: [
            {
              type: "text",
              text: `[CACHE_HIT] ~${estimateTokens(blob.length).toLocaleString()} tokens\n\n${blob}`,
            },
          ],
        };
      }

      // ── invalidate_cache ───────────────────────────────────────────────────
      case "invalidate_cache": {
        const d = getDb();
        if (!d) {
          return {
            content: [
              { type: "text", text: "[CACHE_WARN] SQLite unavailable — nothing to invalidate." },
            ],
          };
        }
        d.prepare(
          "INSERT OR REPLACE INTO cache_meta(key, value) VALUES ('valid', '0')"
        ).run();
        log("info", name, "Cache invalidated", { latency_ms: Date.now() - t0 });
        return {
          content: [
            {
              type: "text",
              text: "[CACHE_INVALIDATED] Cache marked stale. Next get_cached_context will rebuild.",
            },
          ],
        };
      }

      // ── get_cache_status ───────────────────────────────────────────────────
      case "get_cache_status": {
        const d = getDb();
        if (!d) {
          return {
            content: [
              { type: "text", text: "[CACHE_WARN] SQLite unavailable — no status to report." },
            ],
          };
        }

        const rows = d.prepare("SELECT key, value FROM cache_meta").all();
        const meta = {};
        for (const r of rows) meta[r.key] = r.value;

        const files = d
          .prepare("SELECT path, mtime_ms, size_bytes, role FROM cache_files ORDER BY role, path")
          .all();

        const valid    = meta["valid"] === "1" ? "VALID" : "STALE";
        const builtAt  = meta["built_at"] || "(never)";
        const fileCount= meta["file_count"] || "0";
        const charCount= parseInt(meta["char_count"] || "0", 10);
        const root     = meta["project_root"] || "(unset)";

        const lines = [
          `## Cache Status`,
          ``,
          `Status:         ${valid}`,
          `Built at:       ${builtAt}`,
          `Project root:   ${root}`,
          `Files tracked:  ${fileCount}`,
          `Context size:   ${charCount.toLocaleString()} chars / ~${estimateTokens(charCount).toLocaleString()} tokens`,
          `DB:             ${DB_PATH}`,
          ``,
          `### Tracked Files`,
        ];

        for (const f of files) {
          const label = f.path.replace(root + "/", "");
          lines.push(`  [${f.role.padEnd(9)}] ${label} (${f.size_bytes} bytes, mtime=${f.mtime_ms})`);
        }

        if (files.length === 0) {
          lines.push("  (none — run build_cache first)");
        }

        log("info", name, "Status reported", {
          valid,
          latency_ms: Date.now() - t0,
        });
        return { content: [{ type: "text", text: lines.join("\n") }] };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (e) {
    log("error", name, e.message, { latency_ms: Date.now() - t0 });
    return {
      content: [{ type: "text", text: `Error: ${e.message}` }],
      isError: true,
    };
  }
});

// E-112 (caching.md §3.1): `--build` CLI mode — build/persist the System Context
// cache for the current project and exit, WITHOUT starting the stdio server.
// `ai sync` invokes this after regenerating blueprint-derived docs so the cache
// is actually exercised in a live flow (it was built but never invoked). The
// downstream prompt-prefix injection (§3.2/§3.3) is a runtime/harness concern
// beyond this MCP. Fail-open: any error warns to stderr and exits 0 so a sync
// cycle is never blocked.
// E-126 (caching.md §3.2/§3.3): `--emit-context` CLI — print the compiled System
// Context blob to stdout so the SessionStart hook (hooks/session-start.sh) can
// inject it as a prompt-prefix at Claude session start (the previously-unwired
// "Agent Invocation" step of the caching workflow). No server is started.
// Fail-open: any error (or AI_OS_DISABLE_CACHE=1) emits nothing and exits 0 so
// session start is never blocked.
if (process.argv.includes("--emit-context")) {
  try {
    if (process.env.AI_OS_DISABLE_CACHE !== "1") {
      const projectRoot = validateProjectRoot();
      const { blob } = assembleContext(projectRoot);
      if (blob && blob.trim()) process.stdout.write(blob);
    }
  } catch {
    // fail-open: emit nothing rather than block session start
  }
  process.exit(0);
}

if (process.argv.includes("--build")) {
  try {
    const projectRoot = validateProjectRoot();
    const { blob, fileRecords } = assembleContext(projectRoot);
    const d = getDb();
    if (d) persistCache(d, blob, fileRecords, projectRoot);
    process.stderr.write(
      `[cache-manager] context cache ${d ? "built" : "assembled (SQLite unavailable — in-memory only)"}: ` +
      `${fileRecords.length} files, ${blob.length} chars, ~${estimateTokens(blob.length)} tokens\n`
    );
  } catch (e) {
    process.stderr.write(`[cache-manager] WARN: ${e.message} — cache build skipped (sync continues).\n`);
  }
  process.exit(0);
}

log("info", "startup", `${SERVICE} v${VERSION} starting`, { db: DB_PATH });
const transport = new StdioServerTransport();
await server.connect(transport);
