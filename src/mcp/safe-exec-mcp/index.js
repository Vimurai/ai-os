#!/usr/bin/env node
/**
 * safe-exec-mcp — AI-OS UACS MCP Server
 * Analyzes shell commands for destructive or high-risk patterns before execution.
 * Uses token-based parsing (shell-quote) to detect rm -rf, curl|bash, etc.
 *
 * Tools:
 *   analyze_command(command) → risk assessment with PASS/WARN/BLOCK verdict
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { parse } from "shell-quote";

const server = new Server(
  { name: "safe-exec-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// ── Risk rule definitions ─────────────────────────────────────────────────────

// Commands that are inherently read-only — bypass SECRET_IN_COMMAND to prevent
// false positives on research patterns like `grep token file` (P-25).
const RESEARCH_CMDS = new Set(["grep", "rg", "ls", "find", "cat", "head", "tail", "wc", "stat", "file"]);

function isResearchCmd(raw) {
  const first = raw.trimStart().split(/\s+/)[0]?.toLowerCase() ?? "";
  if (RESEARCH_CMDS.has(first)) return true;
  if (/^git\s+(log|diff|status|show|blame|branch|remote|fetch)\b/.test(raw.trim())) return true;
  return false;
}

const BLOCK_RULES = [
  {
    id: "RM_RF_ROOT",
    pattern: (tokens) => hasSequence(tokens, ["rm"], ["-rf", "-fr", "--no-preserve-root"]) && hasRootPaths(tokens),
    message: "rm -rf on root/home paths — BLOCKED (irreversible data destruction)",
  },
  {
    id: "CURL_PIPE_SHELL",
    pattern: (tokens, raw) => /curl[^|]+\|.*(bash|sh|zsh|python)/i.test(raw),
    message: "curl | shell — BLOCKED (remote code execution risk)",
  },
  {
    id: "WGET_PIPE_SHELL",
    pattern: (tokens, raw) => /wget[^|]+\|.*(bash|sh|zsh|python)/i.test(raw),
    message: "wget | shell — BLOCKED (remote code execution risk)",
  },
  {
    id: "DROP_TABLE",
    pattern: (tokens, raw) => /DROP\s+TABLE|TRUNCATE\s+TABLE/i.test(raw),
    message: "SQL DROP/TRUNCATE — BLOCKED (irreversible database operation)",
  },
  {
    id: "FORK_BOMB",
    pattern: (tokens, raw) => raw.includes(":(){ :|:& };:") || raw.includes(":(){ :|:&};:"),
    message: "Fork bomb detected — BLOCKED",
  },
  {
    id: "SECRET_IN_COMMAND",
    pattern: (tokens, raw) => !isResearchCmd(raw) && /\b(password|passwd|secret|api.?key|token)(\s*=\s*|\s+)\S{4,}/i.test(raw),
    message: "Plaintext secret in command — BLOCKED (credential exposure risk)",
  },
];

const WARN_RULES = [
  {
    id: "RM_RF",
    pattern: (tokens) => hasSequence(tokens, ["rm"], ["-rf", "-fr"]),
    message: "rm -rf detected — verify target path is intentional",
  },
  {
    id: "DD_DEVICE",
    pattern: (tokens, raw) => /\bdd\b.*\bof=\/dev\//i.test(raw),
    message: "dd writing to device file — verify this is intentional",
  },
  {
    id: "CHMOD_777",
    pattern: (tokens, raw) => /chmod\s+(777|a\+rwx)/i.test(raw),
    message: "chmod 777 — grants world-writable permissions",
  },
  {
    id: "SUDO_SU",
    pattern: (tokens) => tokens.includes("sudo") && (tokens.includes("su") || tokens.includes("-i")),
    message: "sudo su / sudo -i — privilege escalation",
  },
  {
    id: "GIT_FORCE_PUSH",
    pattern: (tokens, raw) => /git push.*--force|git push.*-f\b/i.test(raw),
    message: "git push --force — can overwrite remote history",
  },
  {
    id: "HISTORY_CLEAR",
    pattern: (tokens, raw) => /history\s+-[cwC]|rm\s+~\/\.bash_history|:\s*>\s*~\/\.bash_history/i.test(raw),
    message: "Shell history clearing — potential audit trail destruction",
  },
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function hasSequence(tokens, cmds, flags) {
  const strTokens = tokens.filter((t) => typeof t === "string").map((t) => String(t));
  return cmds.some((cmd) => strTokens.includes(cmd)) && flags.some((f) => strTokens.includes(f));
}

function hasRootPaths(tokens) {
  const strTokens = tokens.filter((t) => typeof t === "string").map((t) => String(t));
  return strTokens.some((t) => /^(\/$|\/root|\/home|\/etc|\/usr|\/var|\/boot|\~\/)/.test(t));
}

// ── Tool definitions ──────────────────────────────────────────────────────────

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "analyze_command",
      description:
        "Analyzes a shell command for destructive or high-risk patterns. Returns PASS, WARN, or BLOCK verdict with detailed reasoning.",
      inputSchema: {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "Shell command string to analyze",
          },
        },
        required: ["command"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "analyze_command") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }

  const raw = args.command;
  let tokens;
  try {
    tokens = parse(raw).filter((t) => typeof t === "string").map((t) => String(t));
  } catch {
    tokens = raw.split(/\s+/);
  }

  const blocked = BLOCK_RULES.filter((r) => r.pattern(tokens, raw));
  const warned = WARN_RULES.filter((r) => r.pattern(tokens, raw));

  let verdict;
  let icon;
  if (blocked.length > 0) {
    verdict = "BLOCK";
    icon = "✗";
  } else if (warned.length > 0) {
    verdict = "WARN";
    icon = "⚠";
  } else {
    verdict = "PASS";
    icon = "✓";
  }

  const lines = [
    `## safe-exec-mcp Analysis`,
    `Command: \`${raw.slice(0, 120)}\``,
    `Verdict: ${icon} ${verdict}`,
    ``,
  ];

  if (blocked.length > 0) {
    lines.push("### BLOCKED — Do Not Execute");
    blocked.forEach((r) => lines.push(`- [${r.id}] ${r.message}`));
    lines.push("");
    lines.push("Add [SEC_CLEARED] to .ai/LOG.md with Architect approval before retrying.");
  }

  if (warned.length > 0) {
    lines.push("### Warnings — Verify Before Executing");
    warned.forEach((r) => lines.push(`- [${r.id}] ${r.message}`));
  }

  if (blocked.length === 0 && warned.length === 0) {
    lines.push("No high-risk patterns detected.");
  }

  return { content: [{ type: "text", text: lines.join("\n") }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
