#!/usr/bin/env node
/**
 * advisor-mcp — AI-OS MCP Server
 * Agent-to-Agent (A2A) RPC bridge: Claude (Executor) queries the Architect (agy)
 * mid-execution for synchronous architectural rulings.
 *
 * Blueprint: .ai/blueprints/interop.md §1
 *
 * Provider: the Architect persona is `agy` (Antigravity) per D-050. The legacy
 * Gemini CLI was retired (IneligibleTierError — individual tier deprecated), so
 * this bridge now invokes `agy --print` (headless print mode) instead of
 * `gemini -p`. The queue/handoff loop (ai handoff / handoff_control) is the
 * ASYNC channel; this MCP is the SYNCHRONOUS one for mid-task rulings.
 *
 * Constraints (per blueprint):
 *   - The Architect is invoked READ-ONLY — it cannot write files or mutate state
 *     (print mode carries no permission grant, so any tool attempt just times out
 *     to the graceful-degradation fallback rather than mutating the tree).
 *   - All queries and rulings are logged to .ai/LOG.md as [A2A_RULING].
 *   - The Architect is invoked via `agy --print` CLI (headless, no interactive session).
 *   - architect.md is pre-loaded as context for every query.
 *
 * Tools:
 *   ask_architect({ query, blueprint? })
 *     → { ruling, query, blueprint_loaded, timestamp, logged }
 *
 * Observability:
 *   Structured JSON logs to stderr:
 *   { timestamp, level, service:"advisor-mcp", tool, latency_ms, error? }
 */

import { isMainModule } from "../shared/is-main.mjs";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { instrument } from "../../shared/mcp-telemetry.mjs";
import { execFileSync } from "child_process";
import { readFileSync, appendFileSync, existsSync } from "fs";
import { resolve, join } from "path";
import { createLogger } from "../shared/logger.js";

// ── Constants ─────────────────────────────────────────────────────────────────

const SERVICE = "advisor-mcp";
const VERSION = "1.1.0"; // 1.1.0: A2A bridge re-pointed gemini CLI → agy --print (D-050)

// Resolve project root relative to this file's install location.
// Supports both src/ (dev) and ~/.ai-os/mcp/ (installed) paths.
function findProjectRoot() {
  // Walk up from __dirname looking for .ai/architect.md
  let dir = new URL(".", import.meta.url).pathname;
  for (let i = 0; i < 6; i++) {
    if (existsSync(join(dir, ".ai", "architect.md"))) return dir;
    dir = resolve(dir, "..");
  }
  return process.cwd();
}

const PROJECT_ROOT = findProjectRoot();
const ARCHITECT_MD = join(PROJECT_ROOT, ".ai", "architect.md");
const LOG_MD = join(PROJECT_ROOT, ".ai", "LOG.md");
const BLUEPRINTS_DIR = join(PROJECT_ROOT, ".ai", "blueprints");

// ── Structured logger (obs_baseline §Logging) ────────────────────────────────
// Shared NDJSON logger; emits one JSON line per call to stderr.

const logger = createLogger(SERVICE);
const log = (level, tool, message, extras) => logger.log(level, tool, message, extras);

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Read a file safely — return empty string if missing.
 */
function safeRead(path) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

/**
 * Append an [A2A_RULING] entry to LOG.md for auditability.
 * Format matches the established LOG.md convention.
 */
function logRuling(query, ruling, blueprintLoaded) {
  const date = new Date().toISOString().slice(0, 10);
  const shortQuery = query.length > 80 ? query.slice(0, 77) + "..." : query;
  const shortRuling = ruling.length > 120 ? ruling.slice(0, 117) + "..." : ruling;
  const bpNote = blueprintLoaded ? ` | blueprint: ${blueprintLoaded}` : "";
  const line = `[A2A_RULING] ${date} | Query: "${shortQuery}" | Ruling: "${shortRuling}"${bpNote}\n`;
  try {
    appendFileSync(LOG_MD, line, "utf8");
    return true;
  } catch (err) {
    log("warn", "ask_architect", "Failed to write [A2A_RULING] to LOG.md", {
      error: err.message,
    });
    return false;
  }
}

/**
 * Build the prompt for the Architect (agy).
 * Pre-loads architect.md and optionally a domain blueprint as context.
 * The Architect is instructed to respond read-only — no file mutations.
 */
function buildPrompt(query, blueprintContent, blueprintName) {
  const architectContext = safeRead(ARCHITECT_MD);
  const bpSection = blueprintContent
    ? `\n\n## Domain Blueprint: ${blueprintName}\n${blueprintContent}`
    : "";

  return [
    "You are the Principal Architect (agy) in the AI-OS Triad.",
    "The Engineer (Claude) has a mid-execution question requiring an architectural ruling.",
    "Your role is STRICTLY READ-ONLY: provide a definitive ruling but do NOT write files,",
    "mutate state, or issue implementation instructions beyond answering the query.",
    "",
    "## architect.md (current system blueprint)",
    architectContext || "(architect.md not found — answer based on general AI-OS principles)",
    bpSection,
    "",
    "## Engineer Query",
    query,
    "",
    "## Instructions",
    "Respond with a concise, definitive architectural ruling (2-5 sentences).",
    "Start with 'RULING:' on the first line.",
    "Be specific — the Engineer will implement exactly what you say.",
  ].join("\n");
}

/**
 * Invoke the Architect (agy) CLI in headless print mode.
 * Uses `agy --print <prompt>` — read-only by construction: print mode carries no
 * tool-permission grant (no --dangerously-skip-permissions), so any write attempt
 * blocks and times out to the fallback instead of mutating the tree. Replaces the
 * retired Gemini CLI (D-050; individual-tier deprecation → IneligibleTierError).
 */
function invokeArchitect(prompt) {
  // Explicit env allowlist — never spread process.env. Spreading would leak
  // host secrets (AWS/GCP creds, GitHub tokens, etc.) to the spawned agy
  // process. Same security pattern enforced in computer-use-mcp (D-002).
  // agy authenticates via Antigravity OAuth stored under $HOME, so PATH + HOME
  // are the only vars it needs — no API-key env is passed through.
  const allowedEnv = {
    PATH: process.env.PATH ?? "",
    HOME: process.env.HOME ?? "",
  };

  // --print-timeout is agy's own bounded wait (Go duration); keep it below the
  // execFileSync hard timeout so agy self-terminates with a clean message first.
  const output = execFileSync("agy", ["--print-timeout", "90s", "-p", prompt], {
    encoding: "utf8",
    timeout: 100_000,
    maxBuffer: 1024 * 1024, // 1MB
    env: allowedEnv,
  });
  return output.trim();
}

// ── MCP server setup ──────────────────────────────────────────────────────────

const server = new Server(
  { name: SERVICE, version: VERSION },
  { capabilities: { tools: {} } }
);

// ── Tool definitions ──────────────────────────────────────────────────────────

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "ask_architect",
      description: [
        "Sends an architectural query to the Architect (agy, A2A bridge) and returns a definitive ruling.",
        "Pre-loads .ai/architect.md as context. Optionally loads a domain blueprint for deeper context.",
        "All queries and rulings are logged to .ai/LOG.md as [A2A_RULING] for auditability.",
        "The Architect runs READ-ONLY — it cannot write files or mutate state.",
        "",
        "Use this when you hit an ambiguity in the blueprint mid-execution that would otherwise",
        "require dropping the session to consult the Architect manually.",
      ].join(" "),
      inputSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description:
              "The architectural question to ask the Architect (agy). Be specific — include the task ID, " +
              "the ambiguity, and the two options you're choosing between.",
          },
          blueprint: {
            type: "string",
            description:
              "Optional: name of a domain blueprint to load for extra context " +
              "(e.g. 'capabilities', 'mcp', 'agents'). Loads .ai/blueprints/<name>.md.",
          },
        },
        required: ["query"],
      },
    },
  ],
}));

// ── Tool dispatcher ───────────────────────────────────────────────────────────

instrument(server, "advisor-mcp", CallToolRequestSchema);
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const start = Date.now();

  if (name !== "ask_architect") {
    return {
      content: [{ type: "text", text: `Error: Unknown tool: ${name}` }],
      isError: true,
    };
  }

  const { query, blueprint } = args;

  if (!query || typeof query !== "string" || query.trim().length === 0) {
    return {
      content: [{ type: "text", text: "Error: query must be a non-empty string" }],
      isError: true,
    };
  }

  // Load optional domain blueprint
  let blueprintContent = null;
  let blueprintLoaded = null;
  if (blueprint) {
    const bpPath = join(BLUEPRINTS_DIR, `${blueprint}.md`);
    blueprintContent = safeRead(bpPath);
    if (blueprintContent) {
      blueprintLoaded = blueprint;
    } else {
      log("warn", "ask_architect", `Blueprint not found: ${bpPath}`);
    }
  }

  try {
    const prompt = buildPrompt(query, blueprintContent, blueprintLoaded);
    const ruling = invokeArchitect(prompt);
    const timestamp = new Date().toISOString();
    const latency_ms = Date.now() - start;

    const logged = logRuling(query, ruling, blueprintLoaded);

    log("info", "ask_architect", "A2A ruling received", {
      latency_ms,
      blueprint_loaded: blueprintLoaded,
      ruling_length: ruling.length,
      logged,
    });

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              ruling,
              query,
              blueprint_loaded: blueprintLoaded,
              timestamp,
              logged,
            },
            null,
            2
          ),
        },
      ],
    };
  } catch (err) {
    const latency_ms = Date.now() - start;
    log("error", "ask_architect", "Architect (agy) invocation failed", {
      latency_ms,
      error: err.message,
    });

    // Graceful degradation — return error without crashing the MCP server
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              error: `Architect (agy) unavailable: ${err.message}`,
              query,
              fallback:
                "advisor-mcp could not reach the Architect (agy). " +
                "Check that `agy` (Antigravity) CLI is installed and authenticated (`agy` — re-auth if the Antigravity token lapsed). " +
                "Proceed with your best judgement or hand off to the Architect via `ai handoff architect` for an async ruling.",
            },
            null,
            2
          ),
        },
      ],
      isError: true,
    };
  }
});

// ── Start server ──────────────────────────────────────────────────────────────

log("info", "startup", `advisor-mcp v${VERSION} ready`, {
  project_root: PROJECT_ROOT,
  architect_md: existsSync(ARCHITECT_MD) ? "found" : "missing",
});

if (isMainModule(import.meta.url)) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
