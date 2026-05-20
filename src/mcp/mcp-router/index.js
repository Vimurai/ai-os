#!/usr/bin/env node
/**
 * mcp-router — AI-OS Progressive Tool Discovery Router (E-40)
 *
 * Solves prompt bloat from 23 MCP servers loading their full tool schemas on
 * every turn. The router exposes a small, fixed surface (list_domains,
 * activate_domain, proxy_call) and delegates to the underlying servers only
 * when the agent activates a domain and issues a proxied call.
 *
 * Blueprint: .ai/blueprints/mcp-router.md
 *
 * Tools:
 *   list_domains()                          → JSON: { domains: [...] }
 *   activate_domain(domain)                 → JSON: { domain, servers: [...], tools: [...] }
 *   proxy_call(server, tool, arguments?)    → forwards to target server, returns its result
 *
 * Security:
 *   - Domain registry is hard-coded (curated mapping of category → servers).
 *   - proxy_call accepts only servers and tools listed in src/config/registry.json
 *     allowed-tools (RBAC mirror — does not bypass project .claude/settings.json).
 *   - Active-domain gate: proxy_call rejects targets outside the active domain.
 *   - No shell, no eval. Target servers spawned via child_process.spawn with
 *     explicit env allowlist (PATH, HOME) plus any registry-declared env block
 *     (e.g. computer-use-mcp DISPLAY/HOME sandbox per D-002 / E-38).
 *   - Project root validated: absolute, traversal-safe, must contain registry.
 *
 * Observability:
 *   Structured NDJSON logs to stderr via shared/logger.js:
 *   { timestamp, level, service:"mcp-router", tool, latency_ms, error? }
 *
 * Constraints (per blueprint §"Execution Constraints"):
 *   - One extra hop per proxied call. Spawn-and-exit child per request keeps
 *     the implementation simple; long-lived child pooling is a follow-up if
 *     the 50ms overhead budget is exceeded under real load.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { resolve, join, isAbsolute } from "node:path";
import { homedir } from "node:os";
import { createLogger } from "../shared/logger.js";
import { DOMAINS } from "../shared/mcp-domains.mjs";
import { recordToolExecution } from "../../shared/telemetry.mjs";

const SERVICE = "mcp-router";
const VERSION = "1.0.0";

const logger = createLogger(SERVICE);
const log = (level, tool, message, extras) =>
  logger.log(level, tool, message, extras);

// ── Domain Registry (curated category → servers) ──────────────────────────────
// Source of truth: src/mcp/shared/mcp-domains.js (E-52). Both this router and
// scripts/generate_mcp_docs.js import from there so DOMAINS cannot drift
// between the routing surface and the auto-generated mcp.md blueprint.

// ── Project root and registry ─────────────────────────────────────────────────

function validateProjectRoot(raw) {
  const root = raw ? String(raw).trim() : process.cwd();
  if (!isAbsolute(root)) {
    throw new Error(`project_root must be absolute, got: ${root}`);
  }
  if (root.includes("..")) {
    throw new Error(`project_root must not contain ".." segments`);
  }
  if (!existsSync(root)) {
    throw new Error(`project_root does not exist: ${root}`);
  }
  return root;
}

function loadRegistry(projectRoot) {
  // Prefer the in-repo registry, fall back to the installed one. Both are
  // identical when `ai sync` has been run; testing prefers the repo copy.
  const candidates = [
    join(projectRoot, "src", "config", "registry.json"),
    join(homedir(), ".ai-os", "config", "registry.json"),
  ];
  for (const p of candidates) {
    if (existsSync(p)) {
      try {
        return { path: p, data: JSON.parse(readFileSync(p, "utf8")) };
      } catch (e) {
        throw new Error(`registry.json parse error at ${p}: ${e.message}`);
      }
    }
  }
  throw new Error(
    `registry.json not found. Looked in: ${candidates.join(", ")}`
  );
}

function resolveServerCommand(serverName, registry, projectRoot) {
  const info = registry.data?.mcp_servers?.[serverName];
  if (!info) {
    throw new Error(`unknown server: ${serverName}`);
  }
  // Custom AI-OS server (path-based). Prefer installed copy, fall back to repo.
  if (info.path) {
    const installed = join(homedir(), ".ai-os", "mcp", serverName, "index.js");
    const repo = join(projectRoot, info.path);
    const target = existsSync(installed) ? installed : repo;
    if (!existsSync(target)) {
      throw new Error(`server entry point missing for ${serverName}`);
    }
    return { command: process.execPath, args: [target], env: info.env || null };
  }
  // npm-published servers (filesystem, memory, TestSprite). Routing these is
  // out of scope for v1: they require npx and per-instance args (filesystem
  // root path, TestSprite API key) that the router has no business owning.
  throw new Error(
    `${serverName} is an npm-published MCP — routing not supported in v1`
  );
}

// ── Session state ─────────────────────────────────────────────────────────────

let activeDomain = null;

function isServerInActiveDomain(server) {
  if (!activeDomain) return false;
  const dom = DOMAINS[activeDomain];
  return Boolean(dom && dom.servers.includes(server));
}

// ── JSON-RPC stdio client (one-shot per call) ─────────────────────────────────

function proxyOneShot({ command, args, env }, method, params, timeoutMs) {
  return new Promise((resolvePromise, reject) => {
    const childEnv = {
      PATH: process.env.PATH || "",
      HOME: process.env.HOME || "",
      ...(env && typeof env === "object" ? env : {}),
    };
    const child = spawn(command, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: childEnv,
    });

    let stdoutBuf = "";
    let stderrBuf = "";
    let settled = false;

    const finish = (err, value) => {
      if (settled) return;
      settled = true;
      try { child.kill(); } catch { /* ignore */ }
      if (err) reject(err);
      else resolvePromise(value);
    };

    const timer = setTimeout(
      () => finish(new Error(`proxy timeout after ${timeoutMs}ms`)),
      timeoutMs
    );

    child.on("error", (e) => {
      clearTimeout(timer);
      finish(new Error(`spawn failed: ${e.message}`));
    });

    child.stderr.on("data", (chunk) => {
      stderrBuf += chunk.toString("utf8");
      if (stderrBuf.length > 64 * 1024) stderrBuf = stderrBuf.slice(-32 * 1024);
    });

    child.stdout.on("data", (chunk) => {
      stdoutBuf += chunk.toString("utf8");
      let nl;
      while ((nl = stdoutBuf.indexOf("\n")) !== -1) {
        const line = stdoutBuf.slice(0, nl).trim();
        stdoutBuf = stdoutBuf.slice(nl + 1);
        if (!line) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg && msg.id === 2) {
          clearTimeout(timer);
          if (msg.error) {
            finish(
              new Error(
                `target error ${msg.error.code}: ${msg.error.message || ""}`
              )
            );
          } else {
            finish(null, msg.result || {});
          }
          return;
        }
      }
    });

    const initialize = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: SERVICE, version: VERSION },
      },
    };
    const initialized = { jsonrpc: "2.0", method: "notifications/initialized" };
    const call = { jsonrpc: "2.0", id: 2, method, params };

    const frames =
      JSON.stringify(initialize) + "\n" +
      JSON.stringify(initialized) + "\n" +
      JSON.stringify(call) + "\n";

    child.stdin.on("error", () => { /* downstream close races; ignored */ });
    child.stdin.write(frames);
    child.stdin.end();
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
      name: "list_domains",
      description:
        "List the available tool domains and the MCP servers each domain " +
        "groups together. Domains map to operational categories (State, Code, " +
        "Safety, Intelligence, Quality, Interop, Caching). Use this to pick a " +
        "domain to activate before calling proxy_call.",
      inputSchema: {
        type: "object",
        properties: {},
        additionalProperties: false,
      },
    },
    {
      name: "activate_domain",
      description:
        "Set the router's active domain. While a domain is active, proxy_call " +
        "is permitted to target any server in that domain. Returns the domain " +
        "metadata and the list of servers/tools now reachable.",
      inputSchema: {
        type: "object",
        properties: {
          domain: {
            type: "string",
            description:
              "Domain name (one of the keys returned by list_domains).",
          },
          project_root: {
            type: "string",
            description:
              "Absolute path to the AI-OS project root. Defaults to cwd.",
          },
        },
        required: ["domain"],
        additionalProperties: false,
      },
    },
    {
      name: "proxy_call",
      description:
        "Forward a tools/call request to a target MCP server within the " +
        "currently active domain. The router spawns the target, exchanges " +
        "MCP initialize/initialized/call frames over stdio, and returns the " +
        "target's tool result verbatim. Rejects targets outside the active " +
        "domain or unknown to registry.json.",
      inputSchema: {
        type: "object",
        properties: {
          server: {
            type: "string",
            description: "Target MCP server name (must match registry.json).",
          },
          tool: {
            type: "string",
            description: "Target tool name (must be advertised by the server).",
          },
          arguments: {
            type: "object",
            description: "Arguments object for the target tool.",
          },
          timeout_ms: {
            type: "integer",
            minimum: 100,
            maximum: 60000,
            description: "Timeout in milliseconds (default 10000, max 60000).",
          },
          project_root: {
            type: "string",
            description:
              "Absolute path to the AI-OS project root. Defaults to cwd.",
          },
        },
        required: ["server", "tool"],
        additionalProperties: false,
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const t0 = Date.now();
  // Telemetry context (E-84): set inside proxy_call once validation passes,
  // cleared after a successful record so the outer catch can stamp ERROR
  // for any leak-through. Stays null for list_domains / activate_domain.
  let _proxyTelemetryCtx = null;

  try {
    switch (name) {
      // ── list_domains ───────────────────────────────────────────────────────
      case "list_domains": {
        const lines = ["## MCP Router Domains", ""];
        const out = [];
        for (const [key, dom] of Object.entries(DOMAINS)) {
          out.push({ name: key, description: dom.description, servers: dom.servers });
          lines.push(`### ${key}`);
          lines.push(dom.description);
          lines.push(`Servers: ${dom.servers.join(", ")}`);
          lines.push("");
        }
        lines.push(
          activeDomain
            ? `Active domain: ${activeDomain}`
            : "Active domain: (none — call activate_domain first to enable proxy_call)"
        );
        log("info", name, "domains listed", {
          count: out.length,
          active: activeDomain,
          latency_ms: Date.now() - t0,
        });
        return {
          content: [
            { type: "text", text: lines.join("\n") },
            { type: "text", text: JSON.stringify({ domains: out, active: activeDomain }) },
          ],
        };
      }

      // ── activate_domain ────────────────────────────────────────────────────
      case "activate_domain": {
        const domain = args?.domain ? String(args.domain) : "";
        if (!domain) {
          throw new Error("domain is required");
        }
        if (!Object.prototype.hasOwnProperty.call(DOMAINS, domain)) {
          throw new Error(
            `unknown domain: ${domain} (valid: ${Object.keys(DOMAINS).join(", ")})`
          );
        }
        const projectRoot = validateProjectRoot(args?.project_root);
        const registry = loadRegistry(projectRoot);

        const dom = DOMAINS[domain];
        const tools = [];
        for (const srv of dom.servers) {
          const info = registry.data?.mcp_servers?.[srv];
          if (!info) {
            tools.push({ server: srv, status: "missing-from-registry", tools: [] });
            continue;
          }
          tools.push({
            server: srv,
            capability: info.capability || "READ",
            tools: Array.isArray(info["allowed-tools"])
              ? info["allowed-tools"]
              : [],
          });
        }

        activeDomain = domain;
        log("info", name, "domain activated", {
          domain,
          servers: dom.servers.length,
          latency_ms: Date.now() - t0,
        });
        return {
          content: [
            {
              type: "text",
              text:
                `[DOMAIN_ACTIVE] ${domain}\n` +
                `${dom.description}\n` +
                `Servers (${dom.servers.length}): ${dom.servers.join(", ")}\n` +
                `Use proxy_call to invoke any tool in this domain.`,
            },
            {
              type: "text",
              text: JSON.stringify({ domain, servers: tools }),
            },
          ],
        };
      }

      // ── proxy_call ─────────────────────────────────────────────────────────
      case "proxy_call": {
        const targetServer = args?.server ? String(args.server) : "";
        const targetTool = args?.tool ? String(args.tool) : "";
        const callArgs =
          args?.arguments && typeof args.arguments === "object"
            ? args.arguments
            : {};
        const timeoutMs =
          Number.isInteger(args?.timeout_ms) &&
          args.timeout_ms >= 100 &&
          args.timeout_ms <= 60000
            ? args.timeout_ms
            : 10000;

        if (!targetServer) throw new Error("server is required");
        if (!targetTool) throw new Error("tool is required");

        if (!activeDomain) {
          throw new Error(
            "no active domain — call activate_domain first"
          );
        }
        if (!isServerInActiveDomain(targetServer)) {
          throw new Error(
            `server "${targetServer}" not in active domain "${activeDomain}"`
          );
        }

        const projectRoot = validateProjectRoot(args?.project_root);
        const registry = loadRegistry(projectRoot);

        // Enforce registry allowed-tools allowlist (RBAC mirror).
        const info = registry.data?.mcp_servers?.[targetServer];
        const allowed = Array.isArray(info?.["allowed-tools"])
          ? info["allowed-tools"]
          : [];
        const wildcardAllowed = allowed.length === 1 && allowed[0] === "*";
        if (!wildcardAllowed && !allowed.includes(targetTool)) {
          throw new Error(
            `tool "${targetTool}" not in registry allowed-tools for ${targetServer}`
          );
        }

        const cmd = resolveServerCommand(targetServer, registry, projectRoot);

        log("info", name, "forwarding call", {
          target_server: targetServer,
          target_tool: targetTool,
          domain: activeDomain,
          timeout_ms: timeoutMs,
        });

        // E-84: stamp telemetry context. recordToolExecution is fire-and-
        // forget — failures inside the helper are swallowed, never propagated.
        _proxyTelemetryCtx = {
          project_root: projectRoot,
          tool_name: `${targetServer}.${targetTool}`,
        };

        const result = await proxyOneShot(
          cmd,
          "tools/call",
          { name: targetTool, arguments: callArgs },
          timeoutMs
        );

        log("info", name, "forward complete", {
          target_server: targetServer,
          target_tool: targetTool,
          latency_ms: Date.now() - t0,
        });

        recordToolExecution({
          project_root: _proxyTelemetryCtx.project_root,
          session_id: process.env.CLAUDE_CODE_SESSION_ID,
          tool_name: _proxyTelemetryCtx.tool_name,
          execution_time_ms: Date.now() - t0,
          status: "SUCCESS",
        });
        _proxyTelemetryCtx = null;

        // Wrap the upstream result in a router-stamped envelope so the caller
        // can distinguish proxied output from native tool output.
        return {
          content: [
            {
              type: "text",
              text:
                `[ROUTER_PROXY] ${targetServer}.${targetTool} ` +
                `(domain=${activeDomain}, latency=${Date.now() - t0}ms)`,
            },
            ...((result && Array.isArray(result.content) && result.content) || [
              { type: "text", text: JSON.stringify(result) },
            ]),
          ],
          ...(result && result.isError ? { isError: true } : {}),
        };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (e) {
    log("error", name, e.message, { latency_ms: Date.now() - t0 });
    // E-84: if proxy_call leaked an exception, stamp ERROR telemetry. The
    // helper is fire-and-forget and cannot itself throw.
    if (_proxyTelemetryCtx) {
      recordToolExecution({
        project_root: _proxyTelemetryCtx.project_root,
        session_id: process.env.CLAUDE_CODE_SESSION_ID,
        tool_name: _proxyTelemetryCtx.tool_name,
        execution_time_ms: Date.now() - t0,
        status: "ERROR",
      });
    }
    return {
      content: [{ type: "text", text: `Error: ${e.message}` }],
      isError: true,
    };
  }
});

log("info", "startup", `${SERVICE} v${VERSION} starting`, {
  domains: Object.keys(DOMAINS).length,
});
const transport = new StdioServerTransport();
await server.connect(transport);
