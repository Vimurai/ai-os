#!/usr/bin/env node
/**
 * code-execution-mcp — AI-OS Sandboxed Code Execution (E-39)
 *
 * Provides the Engineer with an ephemeral, network-isolated REPL for Python
 * and TypeScript/Node code, replacing unsafe bare-metal `run_shell_command`
 * usage for data-processing and parsing tasks.
 *
 * Blueprint: .ai/blueprints/code-execution.md
 *
 * Tools:
 *   execute_code(language, code, timeout_ms?) → { stdout, stderr, exit_code, execution_time_ms }
 *
 * Sandbox boundary (per blueprint §"Security"):
 *   - Network isolation enforced via the network=none flag.
 *   - Host isolation: read-only root FS, no volume/bind mounts, no Docker
 *     socket exposure. tmpfs /tmp size-capped.
 *   - Resource quotas: memory=512m, cpus=0.5, pids-limit=64.
 *   - User: 65534:65534 (nobody:nogroup) to drop root.
 *   - Capabilities dropped: cap-drop=ALL, security-opt=no-new-privileges.
 *   - Wall-clock timeout enforced by the parent process; SIGKILL on overrun.
 *   - Output cap: stdout+stderr each truncated to 4096 chars.
 *   - Code length cap: 16384 chars (rejects oversize source).
 *   - Language whitelist: "python" | "typescript" (== node) only.
 *
 * Fail-closed mode:
 *   The server starts even when Docker is unavailable so its tool can still
 *   be discovered. Each execute_code call probes the daemon; if the daemon
 *   is missing, the call returns [SANDBOX_UNAVAILABLE] with diagnostics and
 *   never falls back to bare-metal exec — the security boundary cannot be
 *   silently weakened.
 *
 * Observability:
 *   Structured NDJSON logs to stderr via shared/logger.js:
 *   { timestamp, level, service:"code-execution-mcp", tool, latency_ms, ... }
 */

import { isMainModule } from "../shared/is-main.mjs";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { instrument, rejection, markRejection } from "../../shared/mcp-telemetry.mjs";
import { spawn, spawnSync } from "node:child_process";
import { createLogger } from "../shared/logger.js";

const SERVICE = "code-execution-mcp";
const VERSION = "1.0.0";

const logger = createLogger(SERVICE);
const log = (level, tool, message, extras) =>
  logger.log(level, tool, message, extras);

// ── Constants ─────────────────────────────────────────────────────────────────

const LANGUAGES = {
  python: {
    image: "python:3.12-slim",
    binary: "python3",
    args: ["-c"],
  },
  typescript: {
    // Node executes JavaScript; the "typescript" alias matches the blueprint's
    // language label. We do NOT compile TS — runtime is plain Node, which is
    // the only safe choice inside a sealed container without npm install.
    image: "node:22-alpine",
    binary: "node",
    args: ["-e"],
  },
};

const MAX_CODE_LEN = 16384;
const MIN_TIMEOUT_MS = 100;
const MAX_TIMEOUT_MS = 5000;
const DEFAULT_TIMEOUT_MS = 5000;
const OUTPUT_CAP = 4096;

// ── Validation ────────────────────────────────────────────────────────────────

function validateRequest(args) {
  const language = String(args?.language || "").toLowerCase();
  if (!Object.prototype.hasOwnProperty.call(LANGUAGES, language)) {
    throw new Error(
      `unsupported language: "${language}" (allowed: ${Object.keys(LANGUAGES).join(", ")})`
    );
  }
  const code = String(args?.code ?? "");
  if (!code) {
    throw new Error("code is required and must be non-empty");
  }
  if (code.length > MAX_CODE_LEN) {
    throw new Error(
      `code exceeds maximum length: ${code.length} > ${MAX_CODE_LEN}`
    );
  }
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  if (args?.timeout_ms !== undefined) {
    if (
      !Number.isInteger(args.timeout_ms) ||
      args.timeout_ms < MIN_TIMEOUT_MS ||
      args.timeout_ms > MAX_TIMEOUT_MS
    ) {
      throw new Error(
        `timeout_ms must be integer in [${MIN_TIMEOUT_MS}, ${MAX_TIMEOUT_MS}], got: ${args.timeout_ms}`
      );
    }
    timeoutMs = args.timeout_ms;
  }
  return { language, code, timeoutMs };
}

// ── Docker availability probe ─────────────────────────────────────────────────

function probeDocker() {
  // Two-step: CLI presence, then daemon ping. Each step uses a sync subprocess
  // so the call returns inside a single MCP request without leaking children.
  const which = spawnSync("which", ["docker"], { encoding: "utf8" });
  if (which.status !== 0) {
    return { available: false, reason: "docker CLI not on PATH" };
  }
  const ping = spawnSync(
    "docker",
    ["info", "--format", "{{.ServerVersion}}"],
    {
      encoding: "utf8",
      timeout: 3000,
      env: {
        PATH: process.env.PATH || "",
        HOME: process.env.HOME || "",
        DOCKER_HOST: process.env.DOCKER_HOST || "",
      },
    }
  );
  if (ping.status !== 0) {
    const err = (ping.stderr || ping.stdout || "").trim().split("\n")[0] || "daemon ping failed";
    return { available: false, reason: `docker daemon unreachable: ${err}` };
  }
  return { available: true, server_version: ping.stdout.trim() };
}

// ── Output cap ────────────────────────────────────────────────────────────────

function capOutput(buf) {
  if (buf.length <= OUTPUT_CAP) return { text: buf, truncated: false };
  return {
    text: buf.slice(0, OUTPUT_CAP) + `\n...[TRUNCATED at ${OUTPUT_CAP} chars]`,
    truncated: true,
  };
}

// ── Sandboxed execution ───────────────────────────────────────────────────────

function buildDockerArgs(language, code) {
  const lang = LANGUAGES[language];
  // Wall-clock seconds for --stop-timeout-ish behaviour. Docker has no
  // built-in --timeout for run, so the parent process enforces it via SIGKILL.
  return [
    "run",
    "--rm",
    "-i",
    "--network=none",
    "--read-only",
    "--memory=512m",
    "--memory-swap=512m",
    "--cpus=0.5",
    "--pids-limit=64",
    "--user=65534:65534",
    "--cap-drop=ALL",
    "--security-opt=no-new-privileges",
    "--tmpfs=/tmp:rw,noexec,nosuid,size=64m",
    "--workdir=/tmp",
    // No volume mounts, no privileged flag, no host networking, no extra
    // device passthrough. Anti-pattern audit lives in the test suite.
    "--label=ai-os.code-execution=1",
    lang.image,
    lang.binary,
    ...lang.args,
    code,
  ];
}

function executeInDocker(language, code, timeoutMs) {
  return new Promise((resolvePromise) => {
    const args = buildDockerArgs(language, code);
    const t0 = Date.now();

    const child = spawn("docker", args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        PATH: process.env.PATH || "",
        HOME: process.env.HOME || "",
        DOCKER_HOST: process.env.DOCKER_HOST || "",
      },
    });

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;

    const finish = (exitCode, killSignal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const stdoutCap = capOutput(stdout);
      const stderrCap = capOutput(stderr);
      resolvePromise({
        stdout: stdoutCap.text,
        stderr: stderrCap.text,
        exit_code: exitCode,
        execution_time_ms: Date.now() - t0,
        timed_out: timedOut,
        truncated: stdoutCap.truncated || stderrCap.truncated,
        kill_signal: killSignal || null,
      });
    };

    const timer = setTimeout(() => {
      timedOut = true;
      try { child.kill("SIGKILL"); } catch { /* ignore */ }
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
      // Pre-cap to bound memory; surface result keeps the OUTPUT_CAP semantics.
      if (stdout.length > OUTPUT_CAP * 4) {
        stdout = stdout.slice(0, OUTPUT_CAP * 4);
      }
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
      if (stderr.length > OUTPUT_CAP * 4) {
        stderr = stderr.slice(0, OUTPUT_CAP * 4);
      }
    });

    child.on("error", (e) => {
      stderr += `\n[spawn error: ${e.message}]`;
      finish(127, null);
    });

    child.on("close", (code, signal) => {
      finish(code === null ? 137 : code, signal);
    });
  });
}

// ── MCP server ────────────────────────────────────────────────────────────────

const server = new Server(
  { name: SERVICE, version: VERSION },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "execute_code",
      description:
        "Execute a snippet of Python or Node/TypeScript inside a network-" +
        "isolated, read-only Docker sandbox. Output is capped at 4096 chars " +
        "per stream; runtime capped at 5000ms; memory capped at 512MB. " +
        "Returns { stdout, stderr, exit_code, execution_time_ms, timed_out, " +
        "truncated }. Fails closed with [SANDBOX_UNAVAILABLE] when Docker is " +
        "not running. Useful for ad-hoc data processing, math, and parsing " +
        "without granting bare-metal shell access.",
      inputSchema: {
        type: "object",
        properties: {
          language: {
            type: "string",
            enum: Object.keys(LANGUAGES),
            description:
              "Runtime language. \"python\" runs python:3.12-slim; " +
              "\"typescript\" runs node:22-alpine (plain Node — TypeScript " +
              "source is not transpiled inside the sealed sandbox).",
          },
          code: {
            type: "string",
            minLength: 1,
            maxLength: MAX_CODE_LEN,
            description:
              `Source code to execute. Maximum ${MAX_CODE_LEN} characters.`,
          },
          timeout_ms: {
            type: "integer",
            minimum: MIN_TIMEOUT_MS,
            maximum: MAX_TIMEOUT_MS,
            description:
              `Wall-clock timeout in milliseconds ` +
              `(${MIN_TIMEOUT_MS}-${MAX_TIMEOUT_MS}, default ${DEFAULT_TIMEOUT_MS}).`,
          },
        },
        required: ["language", "code"],
        additionalProperties: false,
      },
    },
  ],
}));

instrument(server, "code-execution-mcp", CallToolRequestSchema);
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const t0 = Date.now();

  if (name !== "execute_code") {
    return {
      content: [{ type: "text", text: `Unknown tool: ${name}` }],
      isError: true,
    };
  }

  let req;
  try {
    req = validateRequest(args);
  } catch (e) {
    log("warn", name, "validation failed", { error: e.message });
    // E-179: invalid args is an EXPECTED rejection (caller error), not a tool defect —
    // booked SUCCESS for telemetry while the model still sees isError.
    return rejection(`[VALIDATE_FAIL] ${e.message}`);
  }

  const probe = probeDocker();
  if (!probe.available) {
    log("warn", name, "sandbox unavailable", { reason: probe.reason });
    // E-179: the sandbox being unavailable is an ENVIRONMENTAL precondition (Docker daemon
    // down / image not pullable) — the tool is fail-closed by design and refusing correctly,
    // not malfunctioning. This dominates execute_code's 100% telemetry "failure rate" in
    // environments without Docker; booking it SUCCESS keeps the deprecation aggregate honest
    // (the tool is healthy — the host is missing a dependency).
    return rejection(
      `[SANDBOX_UNAVAILABLE] ${probe.reason}\n` +
      `Refusing to execute outside the Docker sandbox — security boundary is fail-closed.\n` +
      `Start Docker Desktop (or daemon) and retry.`
    );
  }

  log("info", name, "executing", {
    language: req.language,
    code_len: req.code.length,
    timeout_ms: req.timeoutMs,
  });

  const result = await executeInDocker(req.language, req.code, req.timeoutMs);

  log("info", name, "complete", {
    language: req.language,
    exit_code: result.exit_code,
    execution_time_ms: result.execution_time_ms,
    timed_out: result.timed_out,
    truncated: result.truncated,
    latency_ms: Date.now() - t0,
  });

  const summary =
    `[EXECUTED] ${req.language} | exit=${result.exit_code} | ` +
    `${result.execution_time_ms}ms` +
    (result.timed_out ? " | TIMED_OUT" : "") +
    (result.truncated ? " | TRUNCATED" : "");

  const out = {
    content: [
      { type: "text", text: summary },
      {
        type: "text",
        text: JSON.stringify({
          stdout: result.stdout,
          stderr: result.stderr,
          exit_code: result.exit_code,
          execution_time_ms: result.execution_time_ms,
          timed_out: result.timed_out,
          truncated: result.truncated,
        }),
      },
    ],
    ...(result.exit_code !== 0 ? { isError: true } : {}),
  };
  // E-179: a non-zero exit from the SANDBOXED USER CODE means execute_code ran successfully
  // and faithfully reported the code's own failure — an expected, domain-negative result, not
  // a tool malfunction. isError stays true (the model must see the run failed); telemetry
  // books SUCCESS so successful runs of failing/debugged code stop inflating the error rate.
  if (result.exit_code !== 0) markRejection(out);
  return out;
});

const startupProbe = probeDocker();
log("info", "startup", `${SERVICE} v${VERSION} starting`, {
  docker_available: startupProbe.available,
  docker_reason: startupProbe.reason || null,
  languages: Object.keys(LANGUAGES),
});
if (isMainModule(import.meta.url)) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
