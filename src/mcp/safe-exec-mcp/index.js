#!/usr/bin/env node
/**
 * safe-exec-mcp — AI-OS UACS MCP Server
 * Analyzes shell commands for destructive or high-risk patterns before execution.
 * Uses token-based parsing (shell-quote) to detect rm -rf, curl|bash, etc.
 *
 * E-102 (sovereignty-hardening.md §Components 1): also accepts an optional
 * caller_role. When the role is 'architect', destructive implementation git
 * operations and file mutations outside .ai/ and plans/ are BLOCKED with a
 * [SOVEREIGNTY_BLOCK] verdict. Rollback: AI_OS_SOVEREIGNTY_LOCK=0.
 *
 * Tools:
 *   analyze_command(command, caller_role?) → risk assessment with PASS/WARN/BLOCK verdict
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { parse } from "shell-quote";
import { createLogger } from "../shared/logger.js";

// ── Structured logger (obs_baseline §Logging) ────────────────────────────────
const logger = createLogger("safe-exec-mcp");

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

// Normalize a command string for secret scanning — strips basic obfuscation:
// quoted string concatenation (token="sec""ret"), backslash escapes, and outer quotes.
function normalizeForSecretScan(raw) {
  return raw
    .replace(/""/g, "")      // remove adjacent double-quote pairs (concat obfuscation)
    .replace(/''/g, "")      // remove adjacent single-quote pairs
    .replace(/\\(.)/g, "$1") // collapse backslash escapes: \x → x
    .replace(/["']/g, "");   // strip remaining quotes
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
    id: "DD_DISK_WIPE",
    pattern: (tokens, raw) => /\bdd\b.*\bif=\/dev\/(zero|urandom|random)\b.*\bof=\/dev\/(sd[a-z]|nvme|hd[a-z]|disk\d)/i.test(raw),
    message: "dd writing zeros/random to a raw disk device — BLOCKED (irreversible disk wipe)",
  },
  {
    id: "MKFS",
    pattern: (tokens, raw) => /\bmkfs\.[a-z0-9]+\b/i.test(raw) || /\bmkfs\s+/i.test(raw),
    message: "mkfs invocation — BLOCKED (formats a filesystem, irreversible data loss)",
  },
  {
    id: "FIND_DELETE_ROOT",
    pattern: (tokens, raw) => /\bfind\s+(\/|\/root|\/home|\/etc|\/usr|\/var|\/boot)\b.*-delete\b/i.test(raw),
    message: "find / -delete on system path — BLOCKED (mass deletion of system files)",
  },
  {
    id: "REDIRECT_TO_SYSTEM_FILE",
    pattern: (tokens, raw) => />\s*\/etc\/(passwd|shadow|sudoers|hosts)\b/i.test(raw) || />\s*\/dev\/sd[a-z]\b/i.test(raw),
    message: "Redirect to critical system file — BLOCKED (system corruption / privilege escalation)",
  },
  {
    id: "CHMOD_ROOT",
    pattern: (tokens, raw) => /\bchmod\s+(-R\s+)?(777|a\+rwx)\s+(\/|\/etc|\/usr|\/var|\/root|\/boot)\b/i.test(raw),
    message: "chmod 777 on system path — BLOCKED (privilege escalation vector)",
  },
  {
    id: "SECRET_IN_COMMAND",
    pattern: (tokens, raw) => !isResearchCmd(raw) && /\b(password|passwd|secret|api.?key|token)(\s*=\s*|\s+)\S{4,}/i.test(normalizeForSecretScan(raw)),
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
    // Only flag -i/--login/su when they belong to the sudo invocation (appear
    // right after `sudo`, past any of sudo's own flags) — not an unrelated -i on
    // some other command (e.g. `sudo apt install -i pkg`, `sudo grep -i x`).
    pattern: (tokens, raw) => /\bsudo\s+(-\w+\s+)*(-i|--login|su)\b/.test(raw),
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

// ── E-102: Architect sovereignty rules (sovereignty-hardening.md §Components 1) ─
// When caller_role === 'architect', the Architect (Gemini) may not run
// destructive *implementation* git operations or create/destroy files outside
// the Architect-owned .ai/ and plans/ trees. These are honour-system today
// (caller_role is self-reported) but enforced fail-closed: a forbidden verb is
// allowed ONLY when every path operand is scoped to .ai/ or plans/.
const FORBIDDEN_ARCHITECT_GIT = ["reset", "revert", "checkout", "clean"];
const FORBIDDEN_ARCHITECT_OPS = ["rm", "mkdir", "touch"];

// A path operand the Architect is allowed to touch: within .ai/ or plans/
// (optionally prefixed with ./). Bare commit-ish refs (HEAD, hashes, branch
// names) are NOT safe paths, so an unscoped `git reset --hard HEAD` blocks.
const SAFE_ARCHITECT_PATH = /^(\.\/)?(\.ai|plans)(\/|$)/;

function isSafeArchitectPath(tok) {
  return SAFE_ARCHITECT_PATH.test(tok);
}

// Non-flag operand tokens appearing after the first occurrence of `cmd`
// (and, when given, after `sub`). `--` is treated as a separator and dropped.
function operandsAfter(tokens, cmd, sub) {
  const i = tokens.indexOf(cmd);
  if (i === -1) return [];
  let rest = tokens.slice(i + 1);
  if (sub) {
    const j = rest.indexOf(sub);
    rest = j === -1 ? [] : rest.slice(j + 1);
  }
  return rest.filter((t) => t && t !== "--" && !t.startsWith("-"));
}

// Returns [{id, message}] sovereignty violations for an architect caller.
function analyzeSovereignty(tokens, raw) {
  const violations = [];

  // ForbiddenArchitectGit: reset/revert/checkout/clean on implementation targets.
  const gitMatch = /\bgit\s+(reset|revert|checkout|clean)\b/i.exec(raw);
  if (gitMatch) {
    const verb = gitMatch[1].toLowerCase();
    const targets = operandsAfter(tokens, "git", verb);
    const scopedSafe = targets.length > 0 && targets.every(isSafeArchitectPath);
    if (!scopedSafe) {
      violations.push({
        id: `ARCH_GIT_${verb.toUpperCase()}`,
        message: `git ${verb} is a forbidden Architect implementation operation (allowed only when every target is under .ai/ or plans/)`,
      });
    }
  }

  // ForbiddenArchitectOps: rm -rf / mkdir / touch outside .ai/ or plans/.
  if (hasSequence(tokens, ["rm"], ["-rf", "-fr", "-r", "-R", "--recursive"])) {
    const targets = operandsAfter(tokens, "rm");
    if (!(targets.length > 0 && targets.every(isSafeArchitectPath))) {
      violations.push({ id: "ARCH_RM_RF", message: "rm -rf outside .ai/ or plans/ is a forbidden Architect operation" });
    }
  }
  for (const op of ["mkdir", "touch"]) {
    if (tokens.includes(op)) {
      const targets = operandsAfter(tokens, op);
      if (!(targets.length > 0 && targets.every(isSafeArchitectPath))) {
        violations.push({ id: `ARCH_${op.toUpperCase()}`, message: `${op} outside .ai/ or plans/ is a forbidden Architect operation` });
      }
    }
  }
  return violations;
}

// ── Tool definitions ──────────────────────────────────────────────────────────

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "analyze_command",
      description:
        "Analyzes a shell command for destructive or high-risk patterns. Returns PASS, WARN, or BLOCK verdict with detailed reasoning. E-102: pass caller_role to enforce Triad sovereignty — when 'architect', destructive implementation git/file operations outside .ai/ and plans/ are BLOCKED with [SOVEREIGNTY_BLOCK].",
      inputSchema: {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "Shell command string to analyze",
          },
          caller_role: {
            type: "string",
            enum: ["architect", "engineer", "tester"],
            description: "E-102 (sovereignty-hardening.md §Components 1): the requesting Triad role. When 'architect', git reset/revert/checkout/clean and rm -rf/mkdir/touch outside .ai//plans/ are BLOCKED with [SOVEREIGNTY_BLOCK]. Omitting it preserves legacy (role-agnostic) analysis. Rollback: AI_OS_SOVEREIGNTY_LOCK=0.",
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

  // E-102: Architect sovereignty enforcement (sovereignty-hardening.md §API).
  // Only engages for the 'architect' role; disabled by AI_OS_SOVEREIGNTY_LOCK=0.
  const sovereignty =
    args.caller_role === "architect" && process.env.AI_OS_SOVEREIGNTY_LOCK !== "0"
      ? analyzeSovereignty(tokens, raw)
      : [];

  let verdict;
  let icon;
  if (blocked.length > 0 || sovereignty.length > 0) {
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

  if (sovereignty.length > 0) {
    lines.push("### [SOVEREIGNTY_BLOCK] — Forbidden Architect Operation");
    sovereignty.forEach((v) => lines.push(`- [${v.id}] ${v.message}`));
    lines.push("");
    lines.push("The Architect (Gemini) role may not run destructive implementation commands (sovereignty-hardening.md §Components 1). Switch to the Engineer (Claude) to execute this, or rescope the command to .ai/ or plans/.");
  }

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

  if (blocked.length === 0 && warned.length === 0 && sovereignty.length === 0) {
    lines.push("No high-risk patterns detected.");
  }

  return { content: [{ type: "text", text: lines.join("\n") }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
