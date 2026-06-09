// mcp-telemetry.mjs — Global Telemetry Interceptor (E-153, telemetry-hardening.md §Components 1).
//
// PROBLEM (surfaced by the 2026-06-09 INSIGHTS report): telemetry recorded a row for a
// tool ONLY when it was (a) a harness built-in observed by post-tool-use.sh, or (b) routed
// through mcp-router::proxy_call. Direct `mcp__<server>__<tool>` calls that a server
// handles itself, and server-side EXCEPTIONS, were invisible — so the `ERROR` dimension was
// empty (11487/11487 rows were SUCCESS) and Aggregate A (error hotspots) was permanently blind.
//
// FIX: a transport-level wrapper applied at every MCP server's CallTool handler so EVERY
// invocation records exactly one row with an accurate SUCCESS / ERROR (E-154: TIMEOUT) status
// — independent of whether the harness hook saw it. To avoid double-counting, post-tool-use.sh
// skips `mcp__*` tools (the server-side interceptor owns them) while still recording built-ins.
//
// CONSTRAINTS (blueprint §Execution Constraints): non-blocking, <5ms added per call. The actual
// SQLite write is already deferred by recordToolExecution() via setImmediate; this wrapper only
// stamps t0 + classifies status. Telemetry failure must NEVER break or delay the wrapped tool.

import { recordToolExecution } from "./telemetry.mjs";

// Status the wrapper can emit. SUCCESS / ERROR today; TIMEOUT is reserved for E-154 once the
// schema CHECK accepts it (callers may pass a pre-classified TIMEOUT via the handler result).
export const TELEMETRY_STATUS = { SUCCESS: "SUCCESS", ERROR: "ERROR", TIMEOUT: "TIMEOUT" };

// Build the canonical `mcp__<server>__<tool>` name — identical to the harness/MCP convention so
// server-side rows line up with how the agent and post-tool-use.sh name the same tool.
export function toolNameFor(serverName, request) {
  const tool = request?.params?.name;
  return `mcp__${serverName}__${typeof tool === "string" && tool ? tool : "unknown"}`;
}

// Classify an MCP CallTool result. A handler that returns `{ isError: true }` is a tool-level
// failure (E-154); a non-object/undefined return is MALFORMED — the SDK validates the result
// against CallToolResultSchema after we run and rejects it with an McpError, so we book it
// ERROR too rather than a false SUCCESS (Tier-3 review). A thrown exception is classified
// ERROR by the catch in withTelemetry.
export function statusForResult(result) {
  if (!result || typeof result !== "object") return TELEMETRY_STATUS.ERROR;
  return result.isError ? TELEMETRY_STATUS.ERROR : TELEMETRY_STATUS.SUCCESS;
}

/**
 * Wrap a server's CallTool handler so each invocation records one telemetry row.
 * @param {string} serverName  e.g. "task-synchronizer-mcp"
 * @param {(request:any)=>Promise<any>} handler  the existing CallTool handler
 * @param {{ record?: (payload:object)=>void }} [opts]  inject a recorder (tests); defaults to
 *        the shared recordToolExecution (itself fire-and-forget via setImmediate).
 * @returns {(request:any)=>Promise<any>} an instrumented handler with identical semantics
 */
export function withTelemetry(serverName, handler, opts = {}) {
  const record = opts.record || recordToolExecution;
  // Forward ALL handler args (Tier-3 review): the MCP SDK invokes handlers as
  // `handler(request, extra)` where `extra` carries cancellation `signal`, progress
  // `sendNotification`/`sendRequest`, `sessionId`, `requestId`, `authInfo`. Dropping it would
  // silently strip those from every wrapped handler. Telemetry derives only from `request`.
  return async (request, extra) => {
    const t0 = Date.now();
    let status = TELEMETRY_STATUS.SUCCESS;
    try {
      const result = await handler(request, extra);
      status = statusForResult(result);
      return result;
    } catch (e) {
      status = TELEMETRY_STATUS.ERROR;
      throw e; // never swallow the tool's own error — telemetry is a side-effect
    } finally {
      // Side-effect only; recordToolExecution is itself fire-and-forget (setImmediate) and
      // swallows its own errors, but we belt-and-suspenders guard so a telemetry bug can
      // never surface as a tool failure or add latency to the response path.
      try {
        record({
          tool_name: toolNameFor(serverName, request),
          execution_time_ms: Date.now() - t0,
          status,
          project_root: process.cwd(),
          session_id: process.env.CLAUDE_CODE_SESSION_ID || process.env.AI_OS_SESSION_ID || "",
        });
      } catch { /* telemetry must never break a tool */ }
    }
  };
}

/**
 * Monkeypatch a server's setRequestHandler so EVERY CallTool handler it registers is
 * automatically wrapped with withTelemetry(). This is the rollout mechanism across all
 * MCP servers — one call per server, BEFORE it registers its handler.
 *
 * SDK-FREE BY DESIGN: the caller injects the `callToolSchema` it already imports. The
 * @modelcontextprotocol/sdk package is vendored per-server (each src/mcp/<srv>/node_modules)
 * and is NOT resolvable from this shared module, so importing it here would throw
 * MODULE_NOT_FOUND. Injection keeps the interceptor server-agnostic and dependency-free.
 *
 * @param {object} server  an MCP SDK Server instance (its setRequestHandler is patched)
 * @param {string} serverName  e.g. "orchestrator-mcp" — used for the mcp__<server>__<tool> row
 * @param {object} callToolSchema  the server's imported CallToolRequestSchema (the discriminator)
 * @param {{ record?: (payload:object)=>void }} [opts]  inject a recorder (tests)
 * @returns {object} the same server, for chaining
 */
export function instrument(server, serverName, callToolSchema, opts = {}) {
  const orig = server.setRequestHandler.bind(server);
  server.setRequestHandler = (schema, handler) =>
    orig(schema, schema === callToolSchema ? withTelemetry(serverName, handler, opts) : handler);
  return server;
}
