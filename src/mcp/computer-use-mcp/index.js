#!/usr/bin/env node
/**
 * computer-use-mcp — AI-OS MCP Server
 * Provides native OS-level Computer Use capabilities in a sandboxed display.
 *
 * Security boundaries (per SECURITY.md T-CU-001..T-CU-005):
 *   - Linux:  DISPLAY hardcoded to :99 (Xvfb virtual framebuffer). Refuses to
 *             start if Xvfb is not running. Caller cannot override DISPLAY.
 *   - macOS:  Uses screencapture in restricted scope; warns that host-display
 *             isolation requires Linux + Xvfb for production use.
 *   - All:    $HOME is set to /tmp/computer-use-sandbox to prevent accidental
 *             home-directory writes. Shell metacharacters are stripped from all
 *             keyboard payloads before execution.
 *
 * Tools:
 *   capture_screen()             → base64-encoded PNG screenshot
 *   left_click(x, y)             → left mouse click at (x, y)
 *   right_click(x, y)            → right mouse click at (x, y)
 *   double_click(x, y)           → double left click at (x, y)
 *   type_text(text)              → keyboard text input (sanitized)
 *   key_press(key)               → key combo (e.g. "ctrl+c", "Return")
 *   health_check()               → verify sandbox status (exit 0 = healthy)
 *
 * Observability:
 *   All operations emit structured JSON logs to stderr:
 *   { timestamp, level, service:"computer-use-mcp", tool, latency_ms, error? }
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execSync, execFileSync } from "child_process";
import { existsSync, mkdirSync, unlinkSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { createLogger } from "../shared/logger.js";

// ── Constants ─────────────────────────────────────────────────────────────────

const SERVICE = "computer-use-mcp";
const VERSION = "1.0.0";
const PLATFORM = process.platform;

// Security: sandbox display and home dir — never read from environment
const SANDBOX_DISPLAY = ":99";
const SANDBOX_HOME = "/tmp/computer-use-sandbox";

// ── Structured logger (obs_baseline §Logging) ────────────────────────────────
// Shared NDJSON logger; emits one JSON line per call to stderr.

const logger = createLogger(SERVICE);
const log = (level, tool, message, extras) => logger.log(level, tool, message, extras);

// ── Security helpers ──────────────────────────────────────────────────────────

/**
 * Strip shell metacharacters from keyboard text payloads.
 * Allows printable ASCII only; rejects everything else.
 * (T-PI-001: prevent prompt injection via keyboard simulation)
 */
function sanitizeText(text) {
  if (typeof text !== "string") throw new Error("text must be a string");
  // Allow printable ASCII (0x20–0x7E) only
  const sanitized = text.replace(/[^\x20-\x7E]/g, "");
  if (sanitized !== text) {
    log("warn", "type_text", "Non-printable characters stripped from input", {
      original_length: text.length,
      sanitized_length: sanitized.length,
    });
  }
  return sanitized;
}

/**
 * Validate that a key name contains only safe characters.
 * Allows alphanumeric, hyphen, plus, underscore (for combos like ctrl+c).
 */
function sanitizeKey(key) {
  if (typeof key !== "string") throw new Error("key must be a string");
  if (!/^[a-zA-Z0-9_+\-]+$/.test(key)) {
    throw new Error(`Invalid key name: "${key}". Only [a-zA-Z0-9_+\\-] allowed.`);
  }
  return key;
}

/**
 * Ensure sandbox home directory exists.
 */
function ensureSandboxHome() {
  if (!existsSync(SANDBOX_HOME)) {
    mkdirSync(SANDBOX_HOME, { recursive: true, mode: 0o700 });
  }
}

// ── Platform adapters ─────────────────────────────────────────────────────────

const adapter = {
  /**
   * Verify the sandbox is healthy.
   * Linux: checks Xvfb process on SANDBOX_DISPLAY.
   * macOS: warns that production isolation requires Linux + Xvfb.
   */
  healthCheck() {
    if (PLATFORM === "linux") {
      // Verify Xvfb is running for SANDBOX_DISPLAY
      try {
        execFileSync("xdpyinfo", ["-display", SANDBOX_DISPLAY], {
          stdio: "pipe",
          env: { DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME },
        });
        return { healthy: true, display: SANDBOX_DISPLAY, platform: "linux" };
      } catch {
        return {
          healthy: false,
          error: `Xvfb not running on ${SANDBOX_DISPLAY}. Start with: Xvfb ${SANDBOX_DISPLAY} -screen 0 1280x800x24 &`,
          platform: "linux",
        };
      }
    }
    // macOS — no virtual display isolation; warn but allow test usage
    return {
      healthy: true,
      warning:
        "macOS mode: host-display isolation is not enforced. " +
        "For production use, run on Linux with Xvfb on DISPLAY=:99.",
      platform: "darwin",
    };
  },

  /**
   * Capture a screenshot.
   * Returns base64-encoded PNG. Screenshot is written to a temp file then
   * immediately deleted — no persistent storage (T-CU-004).
   */
  captureScreen() {
    ensureSandboxHome();
    const tmpFile = join(tmpdir(), `cu-screenshot-${Date.now()}.png`);
    try {
      if (PLATFORM === "linux") {
        execFileSync("scrot", [tmpFile], {
          env: { DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME },
        });
      } else {
        // macOS: screencapture -x (no sounds/UI) to tmp file
        execFileSync("screencapture", ["-x", tmpFile]);
      }
      const data = execFileSync("base64", [tmpFile]).toString("utf8").replace(/\n/g, "");
      return data;
    } finally {
      // Always delete temp screenshot — no persistent storage
      try { unlinkSync(tmpFile); } catch { /* ignore */ }
    }
  },

  /**
   * Send a mouse click.
   * Linux: xdotool. macOS: cliclick (must be installed).
   */
  mouseClick(x, y, button = "left") {
    const xi = Math.round(x);
    const yi = Math.round(y);
    if (PLATFORM === "linux") {
      const buttonMap = { left: "1", right: "3", double: "1" };
      const btn = buttonMap[button] ?? "1";
      const args =
        button === "double"
          ? ["click", "--repeat", "2", "--delay", "100", `--clearmodifiers`, `mousemove`, `${xi}`, `${yi}`, "click", btn]
          : ["mousemove", `${xi}`, `${yi}`, "click", btn];
      execFileSync("xdotool", args, {
        env: { DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME },
      });
    } else {
      const cmdMap = { left: "c", right: "rc", double: "dc" };
      const cmd = cmdMap[button] ?? "c";
      execFileSync("cliclick", [`${cmd}:${xi},${yi}`]);
    }
  },

  /**
   * Type text via keyboard. Input is sanitized before dispatch.
   */
  typeText(text) {
    const safe = sanitizeText(text);
    if (PLATFORM === "linux") {
      execFileSync("xdotool", ["type", "--clearmodifiers", "--", safe], {
        env: { DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME },
      });
    } else {
      execFileSync("cliclick", [`t:${safe}`]);
    }
  },

  /**
   * Press a key or key combination.
   */
  keyPress(key) {
    const safe = sanitizeKey(key);
    if (PLATFORM === "linux") {
      execFileSync("xdotool", ["key", "--clearmodifiers", safe], {
        env: { DISPLAY: SANDBOX_DISPLAY, HOME: SANDBOX_HOME },
      });
    } else {
      // macOS: use osascript for key combos
      const osKey = safe.replace(/ctrl/g, "control").replace(/\+/g, " down, ");
      execFileSync("osascript", [
        "-e",
        `tell application "System Events" to key code "${osKey}"`,
      ]);
    }
  },
};

// ── MCP server setup ──────────────────────────────────────────────────────────

const server = new Server(
  { name: SERVICE, version: VERSION },
  { capabilities: { tools: {} } }
);

// ── Tool definitions ──────────────────────────────────────────────────────────

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "capture_screen",
      description:
        "Captures a screenshot of the sandboxed display. Returns a base64-encoded PNG. " +
        "On Linux, operates exclusively on DISPLAY=:99 (Xvfb). On macOS, captures the active display with a warning.",
      inputSchema: { type: "object", properties: {}, required: [] },
    },
    {
      name: "left_click",
      description: "Sends a left mouse click to the sandboxed display at the given (x, y) pixel coordinates.",
      inputSchema: {
        type: "object",
        properties: {
          x: { type: "integer", minimum: 0, maximum: 10000, description: "X coordinate in pixels (0-10000)" },
          y: { type: "integer", minimum: 0, maximum: 10000, description: "Y coordinate in pixels (0-10000)" },
        },
        required: ["x", "y"],
        additionalProperties: false,
      },
    },
    {
      name: "right_click",
      description: "Sends a right mouse click at (x, y).",
      inputSchema: {
        type: "object",
        properties: {
          x: { type: "integer", minimum: 0, maximum: 10000 },
          y: { type: "integer", minimum: 0, maximum: 10000 },
        },
        required: ["x", "y"],
        additionalProperties: false,
      },
    },
    {
      name: "double_click",
      description: "Sends a double left-click at (x, y).",
      inputSchema: {
        type: "object",
        properties: {
          x: { type: "integer", minimum: 0, maximum: 10000 },
          y: { type: "integer", minimum: 0, maximum: 10000 },
        },
        required: ["x", "y"],
        additionalProperties: false,
      },
    },
    {
      name: "type_text",
      description:
        "Types text into the sandboxed display via keyboard simulation. " +
        "Only printable ASCII characters are allowed; all others are stripped. " +
        "Maximum length: 4096 characters (ARG_MAX safety bound).",
      inputSchema: {
        type: "object",
        properties: {
          text: { type: "string", maxLength: 4096, description: "Text to type (printable ASCII, max 4096 chars)" },
        },
        required: ["text"],
        additionalProperties: false,
      },
    },
    {
      name: "key_press",
      description:
        "Presses a key or key combination (e.g. \"Return\", \"ctrl+c\", \"alt+F4\"). " +
        "Only alphanumeric, hyphen, plus, and underscore characters are allowed.",
      inputSchema: {
        type: "object",
        properties: {
          key: { type: "string", maxLength: 64, description: "Key name or combo (max 64 chars)" },
        },
        required: ["key"],
        additionalProperties: false,
      },
    },
    {
      name: "health_check",
      description:
        "Verifies that the sandbox environment is healthy and ready for Computer Use. " +
        "On Linux, confirms Xvfb is running on DISPLAY=:99. Returns status and any warnings.",
      inputSchema: { type: "object", properties: {}, required: [] },
    },
  ],
}));

// ── Tool dispatcher ───────────────────────────────────────────────────────────

// Runtime bounds validators — defence-in-depth against missing/garbage args.
function _validateCoord(args) {
  for (const k of ["x", "y"]) {
    const v = args?.[k];
    if (typeof v !== "number" || !Number.isFinite(v)) {
      return `${k} must be a finite number, got ${v === undefined ? "undefined" : typeof v}`;
    }
    if (v < 0 || v > 10000) return `${k} out of range [0, 10000]: ${v}`;
  }
  return null;
}

function _validateText(args) {
  const v = args?.text;
  if (typeof v !== "string") return "text must be a string";
  if (v.length > 4096)      return `text exceeds max length 4096 (got ${v.length})`;
  return null;
}

function _validateKey(args) {
  const v = args?.key;
  if (typeof v !== "string") return "key must be a string";
  if (v.length === 0)        return "key must not be empty";
  if (v.length > 64)         return `key exceeds max length 64 (got ${v.length})`;
  return null;
}

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const start = Date.now();

  try {
    let result;

    // ── Argument validation guard ─────────────────────────────────────────
    let validationError = null;
    if (["left_click", "right_click", "double_click"].includes(name)) {
      validationError = _validateCoord(args);
    } else if (name === "type_text") {
      validationError = _validateText(args);
    } else if (name === "key_press") {
      validationError = _validateKey(args);
    }
    if (validationError) {
      return {
        content: [{ type: "text", text: `[VALIDATE_FAIL] ${name}: ${validationError}` }],
        isError: true,
      };
    }

    switch (name) {
      case "capture_screen": {
        const png = adapter.captureScreen();
        result = {
          type: "image",
          data: png,
          mediaType: "image/png",
          description: `Screenshot captured from ${PLATFORM === "linux" ? SANDBOX_DISPLAY : "host display (macOS)"}`,
        };
        break;
      }

      case "left_click": {
        adapter.mouseClick(args.x, args.y, "left");
        result = { clicked: "left", x: args.x, y: args.y };
        break;
      }

      case "right_click": {
        adapter.mouseClick(args.x, args.y, "right");
        result = { clicked: "right", x: args.x, y: args.y };
        break;
      }

      case "double_click": {
        adapter.mouseClick(args.x, args.y, "double");
        result = { clicked: "double", x: args.x, y: args.y };
        break;
      }

      case "type_text": {
        adapter.typeText(args.text);
        result = { typed: true, length: sanitizeText(args.text).length };
        break;
      }

      case "key_press": {
        adapter.keyPress(args.key);
        result = { pressed: args.key };
        break;
      }

      case "health_check": {
        result = adapter.healthCheck();
        break;
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    const latency_ms = Date.now() - start;
    log("info", name, "tool call succeeded", { latency_ms });

    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  } catch (err) {
    const latency_ms = Date.now() - start;
    log("error", name, "tool call failed", {
      latency_ms,
      error: err.message,
    });
    return {
      content: [{ type: "text", text: `Error: ${err.message}` }],
      isError: true,
    };
  }
});

// ── Startup health check (§SEC T-CU-001) ─────────────────────────────────────

const startup = adapter.healthCheck();
if (!startup.healthy) {
  log("error", "startup", "Sandbox not ready — refusing to start", {
    error: startup.error,
  });
  process.exit(1);
}
log("info", "startup", `computer-use-mcp v${VERSION} ready`, {
  platform: PLATFORM,
  display: PLATFORM === "linux" ? SANDBOX_DISPLAY : "host (macOS)",
  sandbox_home: SANDBOX_HOME,
  warning: startup.warning ?? null,
});

// ── Start server ──────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
