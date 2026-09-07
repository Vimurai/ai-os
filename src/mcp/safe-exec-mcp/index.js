#!/usr/bin/env node
/**
 * safe-exec-mcp — AI-OS UACS MCP Server
 * Analyzes shell commands for destructive or high-risk patterns before execution.
 * Uses token-based parsing (shell-quote) to detect rm -rf, curl|bash, etc.
 *
 * E-102/E-123 (sovereignty-hardening.md §Data Model): also accepts an optional
 * caller_role. When the role is 'architect', these are BLOCKED with a
 * [SOVEREIGNTY_BLOCK] verdict: destructive implementation git ops + file
 * mutations outside .ai/ and plans/ (E-102); and merge/branch/remote git ops
 * (merge/rebase/push/pull/branch) + deployment commands (ssh/rsync/scp/
 * `npm publish`/`docker push`) which are strictly Engineer tasks (E-123).
 * Rollback: AI_OS_SOVEREIGNTY_LOCK=0.
 *
 * Tools:
 *   analyze_command(command, caller_role?) → risk assessment with PASS/WARN/BLOCK verdict
 */

import { isMainModule } from "../shared/is-main.mjs";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { instrument } from "../../shared/mcp-telemetry.mjs";
import { parse } from "shell-quote";
import { createLogger } from "../shared/logger.js";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, realpathSync, lstatSync } from "node:fs";
import { homedir } from "node:os";
import { join, isAbsolute, normalize, relative, dirname, basename, resolve as resolvePath } from "node:path";

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
    pattern: (tokens, raw) => rmRecursiveForce(tokens) && hasRootPaths(tokens, raw),
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
    pattern: (tokens) => rmRecursiveForce(tokens),
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

// E-125: rm invoked with BOTH recursive and force — combined (-rf/-fr/-Rfv…) OR
// SPLIT (`rm -r -f`), OR --no-preserve-root. Split flags are equivalent to -rf, so
// a fail-closed gate must treat them identically (plain hasSequence missed them).
function _shortFlagHas(strTokens, ch) {
  return strTokens.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(ch));
}
function rmRecursiveForce(tokens) {
  const t = tokens.filter((x) => typeof x === "string").map((x) => String(x));
  if (!t.includes("rm")) return false;
  if (t.includes("--no-preserve-root")) return true;
  const recursive = t.includes("-R") || t.includes("--recursive") || _shortFlagHas(t, "r");
  const force = t.includes("--force") || _shortFlagHas(t, "f");
  return recursive && force;
}

// E-125: catastrophic rm targets (root/home). Tokenizers EXPAND $HOME→"" and turn
// `/*` into a glob object (both dropped from string tokens), and bare ~ slips the
// old token-only check — so also scan the raw string. Only consulted inside the
// rm-recursive-force rule, where any root/home target is irreversible.
function hasRootPaths(tokens, raw) {
  const strTokens = tokens.filter((t) => typeof t === "string").map((t) => String(t));
  if (strTokens.some((t) => /^(\/$|\/root|\/home|\/etc|\/usr|\/var|\/boot|~$|~\/|\$HOME(\/|$)|\$\{HOME\}(\/|$))/.test(t))) return true;
  if (raw == null) return false;
  const r = String(raw);
  if (/(^|[\s=])(\$HOME|\$\{HOME\})(\/|\s|$)/.test(r)) return true;  // $HOME / ${HOME} (tokenizer expands to "")
  if (/(^|\s)~(\/|\s|$)/.test(r)) return true;                      // ~ or ~/
  if (/(^|\s)\/\*(\s|$)/.test(r)) return true;                      // /* glob (dropped from tokens)
  return false;
}

// ── E-102: Architect sovereignty rules (sovereignty-hardening.md §Components 1) ─
// When caller_role === 'architect', the Architect (Agy) may not run
// destructive *implementation* git operations or create/destroy files outside
// the Architect-owned .ai/ and plans/ trees. These are honour-system today
// (caller_role is self-reported) but enforced fail-closed: a forbidden verb is
// allowed ONLY when every path operand is scoped to .ai/ or plans/.
const FORBIDDEN_ARCHITECT_GIT = ["reset", "revert", "checkout", "clean"];
const FORBIDDEN_ARCHITECT_OPS = ["rm", "mkdir", "touch"];

// E-123 (sovereignty-hardening.md §Data Model): branch-merge + deployment
// sovereignty. These git verbs are branch/remote operations (not path-scoped), so
// they are GLOBALLY forbidden for the Architect — merges, pulls, pushes, rebases
// and branch management are strictly Engineer tasks.
const FORBIDDEN_ARCHITECT_GIT_GLOBAL = ["merge", "rebase", "push", "pull", "branch"];
// Deployment commands the Architect may never run (Engineer territory): single
// verbs plus two-token forms (npm publish / docker push).
const FORBIDDEN_ARCHITECT_DEPLOY = ["ssh", "rsync", "scp"];
const FORBIDDEN_ARCHITECT_DEPLOY_PAIRS = [["npm", "publish"], ["docker", "push"]];

// Matches a verb at a COMMAND position — line start, after a shell separator
// (; & | newline, backtick, subshell paren), or after a command prefix
// (sudo/env/…) — not merely as an argument substring, so `cat ~/.ssh/config` does
// not trip the ssh rule. `tokens` is string-only here (shell operators are
// stripped upstream), so command-position detection runs against the raw string.
const CMD_HEAD = "(?:^|[;&|\\n`(]|\\b(?:sudo|env|nohup|time|command|exec|xargs|then|do)\\s+)\\s*";
function usesCommandVerb(raw, verb) {
  return new RegExp(CMD_HEAD + verb + "\\b", "i").test(raw);
}
function usesCommandPair(raw, a, b) {
  return new RegExp(CMD_HEAD + a + "\\s+" + b + "\\b", "i").test(raw);
}

// A path operand the Architect is allowed to touch: within .ai/ or plans/
// (optionally prefixed with ./). Bare commit-ish refs (HEAD, hashes, branch
// names) are NOT safe paths, so an unscoped `git reset --hard HEAD` blocks.
const SAFE_ARCHITECT_PATH = /^(\.\/)?(\.ai|plans)(\/|$)/;

function isSafeArchitectPath(tok) {
  return SAFE_ARCHITECT_PATH.test(tok);
}

// ── E-208 (D-054, role-abstraction.md §Components 5): Write/Edit sovereignty ───
// SAFE_ARCHITECT_PATH above matches the RELATIVE operands that appear in a shell
// command. The Write/Edit tools hand the hook an ABSOLUTE path instead, so it must
// first be normalised against the project root before the same .ai/ | plans/ rule
// can be applied. Kept separate from the token-based command analyser because the
// input shape differs: one path, already parsed, no shell quoting to reason about.
//
// WHY THIS EXISTS: under a same-provider Triad the Architect pane is Claude, which
// unlike agy HAS Write/Edit tools. §35 ANTI-DRIFT was prompt-level only for those.
//
// SCOPE — READ THIS BEFORE RELYING ON IT (E-208 security audit, 2026-09-05):
// this gate covers the NATIVE write tools only (Write|Edit|MultiEdit|NotebookEdit).
// It does NOT cover shell writes (`>`, tee, cp, mv, sed -i, ln -s, git apply,
// python3 -c) — analyzeSovereignty has no concept of redirection — nor the MCP write
// tools (mcp__filesystem__*, mcp__patch-mcp__*), which sit outside the hook matcher
// and are pre-approved in the allow-list. Gap G2 is therefore NARROWED, not closed:
// treat this as defence-in-depth, not a boundary. Closing the remaining channels is
// a policy expansion beyond role-abstraction.md §Components 5 and needs an Architect
// ruling (escalated 2026-09-05).
//
// PATH GATING ITSELF also has limits, so do not read the list above as "everything
// else is airtight":
//   - HARDLINKS are handled below by an nlink check, NOT by path resolution — no
//     resolution algorithm can see through one (see the check in this function).
//   - TOCTOU: the hook approves a path, then the tool opens it. A concurrent
//     `ln -sf` between those two moments is not observable here. Inherent to
//     hook-based gating, and it needs the same shell channel already declared open.
function architectPathVerdict(rawPath, projectRoot) {
  if (!rawPath || typeof rawPath !== "string") {
    return { blocked: false }; // nothing to gate — never invent a block
  }
  // A parent-directory segment must be rejected BEFORE any resolution, because
  // `normalize` and `resolve` collapse it LEXICALLY (a pure string operation) while
  // the kernel applies it to the SYMLINK TARGET. Given a link inside .ai/ pointing at
  // a directory under src/, a path that walks through that link and then back up one
  // level collapses, as a string, to something still inside .ai/ — so the gate allowed
  // it — while the kernel resolved it to a file under src/. That wrote real bytes to a
  // real source file through the native Write tool (E-208 audit round 2).
  // Resolving symlinks first does not fix it — the two orders disagree by design.
  // The Write/Edit tools always hand us a clean absolute path, so such a segment has
  // no legitimate use here, and rejecting it removes the whole class rather than one
  // instance. Checked on the RAW input, before normalize can hide it.
  for (const seg of String(rawPath).split(/[\\/]+/)) {
    if (seg === "..") {
      return { blocked: true, reason: "path contains a '..' segment, which cannot be resolved safely across symlinks" };
    }
  }

  // Strip trailing separators BEFORE resolving. `existsSync(".ai/link/")` is false for
  // a symlink-to-FILE (ENOTDIR), so the ancestor walk would skip the leaf, re-attach
  // it as an unresolved tail, and hand back `.ai/link` — inside the allowed root,
  // never resolved to its target. `.ai/link` blocked while `.ai/link/` allowed
  // (E-208 audit round 2). basename() already discards the slash, so this only makes
  // the existence probe see the same path the kernel would.
  const cleanedPath = String(rawPath).replace(/[\\/]+$/, "") || rawPath;

  let rel;
  try {
    const abs = isAbsolute(cleanedPath) ? normalize(cleanedPath) : resolvePath(projectRoot, cleanedPath);
    // Symlinks must be resolved BEFORE the .ai|plans test, or a link planted inside
    // .ai/ (which the Architect may legitimately write) silently forwards a write to
    // any target: `.ai/link -> src/bin/ai` passed the normalise-only check.
    // The write target itself may not exist yet, so resolve the nearest EXISTING
    // ancestor and re-attach the unresolved tail.
    rel = relative(realpathRoot(projectRoot), realpathNearest(abs));
  } catch {
    return { blocked: true, reason: "path could not be resolved against the project root" };
  }
  // Outside the project entirely (rel starts with ".." or is another absolute root).
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) {
    return { blocked: true, reason: "path is outside the project root" };
  }
  // Already normalised above, so any embedded parent-directory segments have been
  // collapsed — an escape attempt shows up as a rel that leaves the root, caught above.
  if (isSafeArchitectPath(rel)) {
    // HARDLINK check — the one place path resolution genuinely cannot help. A
    // hardlink is not a REFERENCE to a file, it IS the file under a second equally
    // canonical name, so realpath has nothing to see through: `ln src/bin/ai .ai/h`
    // then `Write .ai/h` writes src/bin/ai, and every path-based check agrees the
    // target is inside .ai/. Only an inode property distinguishes it. One lstat, and
    // it can only ever ADD restriction to a write we were about to allow.
    // Directories legitimately carry nlink > 1 (subdirectory back-references), so
    // this is restricted to regular files. A missing target is not yet a file and
    // cannot be an alias for one.
    try {
      const st = lstatSync(join(realpathRoot(projectRoot), rel));
      if (st.isFile() && st.nlink > 1) {
        return {
          blocked: true,
          reason: `target has ${st.nlink} hard links — it is the same inode as a file elsewhere, so writing it would write outside .ai//plans/`,
        };
      }
    } catch {
      // Target does not exist yet (the common case for a new file) — nothing to alias.
    }
    return { blocked: false };
  }
  return { blocked: true, reason: "the Architect may only write under .ai/ or plans/" };
}

// realpath of the project root itself (the root may sit under a symlinked prefix,
// e.g. /tmp -> /private/tmp on macOS; without this every path would look "outside").
function realpathRoot(root) {
  try { return realpathSync(root); } catch { return root; }
}

// realpath the deepest EXISTING ancestor of `abs`, then re-attach the not-yet-created
// tail. A write target usually does not exist yet, so realpathSync(abs) would throw;
// resolving the ancestor still defeats a symlinked directory component.
function realpathNearest(abs) {
  let cur = abs;
  const tail = [];
  for (let i = 0; i < 64; i++) {
    if (existsSync(cur)) {
      // FAIL CLOSED: a realpath error must NOT degrade to the unresolved path — that
      // is a fail-open in a security decision, and it is what let a trailing slash on
      // a symlinked leaf (ENOTDIR) slip through (E-208 audit round 2). Throwing here
      // is caught by architectPathVerdict, which returns blocked.
      const real = realpathSync(cur); // may throw — intentional
      return tail.length ? join(real, ...tail.reverse()) : real;
    }
    const parent = dirname(cur);
    if (parent === cur) break;
    tail.push(basename(cur));
    cur = parent;
  }
  return abs;
}

// Project root for the path gate: nearest ancestor of cwd containing .ai/.
function findProjectRootFrom(start) {
  let dir = resolvePath(start || process.cwd());
  for (let i = 0; i < 40; i++) {
    if (existsSync(join(dir, ".ai"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return resolvePath(start || process.cwd());
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

  // E-123: globally-forbidden Architect git ops (merge/rebase/push/pull/branch).
  // These are branch/remote operations, blocked regardless of path scope —
  // merging and pushing are strictly Engineer tasks.
  const gitGlobal = new RegExp(`\\bgit\\s+(${FORBIDDEN_ARCHITECT_GIT_GLOBAL.join("|")})\\b`, "i").exec(raw);
  if (gitGlobal) {
    const verb = gitGlobal[1].toLowerCase();
    violations.push({
      id: `ARCH_GIT_${verb.toUpperCase()}`,
      message: `git ${verb} is a forbidden Architect operation — merges/branch/remote ops are strictly Engineer tasks`,
    });
  }

  // E-123: deployment commands are strictly Engineer territory (ssh/rsync/scp,
  // npm publish, docker push) — blocked for the Architect at command position.
  for (const v of FORBIDDEN_ARCHITECT_DEPLOY) {
    if (usesCommandVerb(raw, v)) {
      violations.push({ id: `ARCH_DEPLOY_${v.toUpperCase()}`, message: `${v} is a forbidden Architect operation — deployments are strictly Engineer tasks` });
    }
  }
  for (const [a, b] of FORBIDDEN_ARCHITECT_DEPLOY_PAIRS) {
    if (usesCommandPair(raw, a, b)) {
      violations.push({ id: `ARCH_DEPLOY_${a.toUpperCase()}_${b.toUpperCase()}`, message: `${a} ${b} is a forbidden Architect operation — deployments are strictly Engineer tasks` });
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
            description: "E-102/E-123 (sovereignty-hardening.md §Data Model): the requesting Triad role. When 'architect', these are BLOCKED with [SOVEREIGNTY_BLOCK]: git reset/revert/checkout/clean and rm -rf/mkdir/touch outside .ai//plans/ (E-102); and — strictly Engineer-only — git merge/rebase/push/pull/branch plus deployment commands ssh/rsync/scp/`npm publish`/`docker push` (E-123). Omitting caller_role preserves legacy (role-agnostic) analysis. Rollback: AI_OS_SOVEREIGNTY_LOCK=0.",
          },
        },
        required: ["command"],
      },
    },
  ],
}));

// ── Core analysis (shared by the MCP tool AND the --check CLI gate, E-125) ─────
// SINGLE source of truth: the fail-closed PreToolUse gate (hooks/pre-tool-use.sh)
// runs `--check`, which calls THIS exact logic — so the gate ENFORCES the same
// verdicts the analyze_command tool reports (no advisory/enforcement drift).
// Returns { verdict: "PASS"|"WARN"|"BLOCK", blocked, warned, sovereignty, report }.
function runAnalysis(raw, callerRole) {
  let tokens;
  try {
    tokens = parse(raw).filter((t) => typeof t === "string").map((t) => String(t));
  } catch {
    tokens = String(raw).split(/\s+/);
  }

  const blocked = BLOCK_RULES.filter((r) => r.pattern(tokens, raw));
  const warned = WARN_RULES.filter((r) => r.pattern(tokens, raw));

  // E-102/E-123: Architect sovereignty enforcement (sovereignty-hardening.md §API).
  // Only engages for the 'architect' role; disabled by AI_OS_SOVEREIGNTY_LOCK=0.
  const sovereignty =
    callerRole === "architect" && process.env.AI_OS_SOVEREIGNTY_LOCK !== "0"
      ? analyzeSovereignty(tokens, raw)
      : [];

  const verdict = blocked.length > 0 || sovereignty.length > 0 ? "BLOCK" : warned.length > 0 ? "WARN" : "PASS";
  const icon = verdict === "BLOCK" ? "✗" : verdict === "WARN" ? "⚠" : "✓";

  const lines = [
    `## safe-exec-mcp Analysis`,
    `Command: \`${String(raw).slice(0, 120)}\``,
    `Verdict: ${icon} ${verdict}`,
    ``,
  ];
  if (sovereignty.length > 0) {
    lines.push("### [SOVEREIGNTY_BLOCK] — Forbidden Architect Operation");
    sovereignty.forEach((v) => lines.push(`- [${v.id}] ${v.message}`));
    lines.push("");
    lines.push("The Architect (Agy) role may not run destructive implementation commands (sovereignty-hardening.md §Components 1). Switch to the Engineer (Claude) to execute this, or rescope the command to .ai/ or plans/.");
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

  return { verdict, blocked, warned, sovereignty, report: lines.join("\n") };
}

// E-127 (sovereignty-hardening.md §Security): the role is TRUSTED from the
// bootloader-injected environment (AI_OS_CALLER_ROLE, written into the agent's
// settings.json by `ai install`) OVER the agent-supplied argument — an agent
// cannot impersonate another Triad role by passing a different caller_role.
function effectiveRole(argRole) {
  return process.env.AI_OS_CALLER_ROLE || argRole || "";
}

// ── E-129: tamper-resistant role token (sovereignty-hardening.md §Security) ─────
// The env var AI_OS_CALLER_ROLE (E-127) is trivially mutable in-session (`unset`/
// `export`) by a freshly-spawned process like the gate's `--check` CLI. E-129 binds
// the engineer/--check role to a SESSION TOKEN: a JSON record at ~/.ai-os/run/
// role-<sid>.lock, HMAC-signed over (role, session_id) with a per-machine key. The
// gate hook supplies the session id (from the harness PreToolUse payload, not env);
// `--check` reads + verifies the token and uses its role, IGNORING the live env. An
// in-session `unset/export` can no longer downgrade the role — forgery now requires
// reading the 0600 machine key and recomputing the HMAC (tamper-RESISTANT, not
// tamper-proof: a single-user agent runs as the user, an honest ceiling).
// Rollback: AI_OS_ROLE_TOKEN=0 (token layer only) or AI_OS_SAFE_EXEC_GATE=0 (gate).
const _SECRETS_DIR = join(homedir(), ".ai-os", "secrets");
const _RUN_DIR = join(homedir(), ".ai-os", "run");
const _KEY_PATH = join(_SECRETS_DIR, "role-hmac.key");

function getMachineKey() {
  try {
    if (existsSync(_KEY_PATH)) return readFileSync(_KEY_PATH, "utf8").trim();
    mkdirSync(_SECRETS_DIR, { recursive: true, mode: 0o700 });
    const key = randomBytes(32).toString("hex");
    writeFileSync(_KEY_PATH, key, { mode: 0o600 });
    return key;
  } catch {
    return null; // no key → token unavailable → callers fall back to legacy env
  }
}

function signRole(role, sid, key) {
  return createHmac("sha256", Buffer.from(key, "hex")).update(`v1|${role}|${sid}`).digest("hex");
}

// Strip anything but a safe token charset so a crafted session id can't traverse
// out of the run dir.
function _sanitizeSid(sid) {
  return String(sid || "").replace(/[^A-Za-z0-9._-]/g, "");
}
function tokenPath(sid) {
  return join(_RUN_DIR, `role-${_sanitizeSid(sid)}.lock`);
}

// E-208 (P0 fix): a session id may be minted repeatedly (SessionStart fires on both
// `startup` and `resume`) but ONLY ever for the SAME role. Before E-208 the token
// gated a handful of Bash verbs, so an unguarded re-mint was accepted risk; E-208
// makes the same token gate WRITES, which turned re-mint into a full role swap:
//   as architect: Write src/  -> BLOCKED
//   node index.js --mint-<t> engineer <same sid>   (the Bash gate does not stop this)
//   as architect: Write src/  -> ALLOWED           <- privilege escalation
// Refusing a role CHANGE closes that without breaking legitimate resume re-mints.
// Rollback: AI_OS_ROLE_TOKEN=0 disables the whole token layer.
function mintToken(role, sid) {
  const cleanSid = _sanitizeSid(sid);
  if (!role || !cleanSid) return false;
  const key = getMachineKey();
  if (!key) return false;
  const existing = verifyToken(cleanSid);
  if (existing && existing !== role) {
    // Wording matters here: this guard enforces "a VALID BINDING may not be CHANGED",
    // NOT "a session's role is immutable". Deleting or corrupting the lock file makes
    // verifyToken return null and a fresh mint then succeeds — so this raises the cost
    // from one command to two, it is not an integrity guarantee. Closing that needs the
    // record bound to something the deleter cannot forge (process start-time / boot-id
    // in the HMAC, or an append-only ledger); escalated to the Architect. Do not
    // restate this as immutability — the next reviewer will believe it.
    process.stderr.write(
      "[safe-exec] refusing to re-mint this session with a different role — it is already " +
      `bound to "${existing}" (E-208). Partial guard: a deleted/corrupt lock can still be re-minted.\n`
    );
    return false;
  }
  try {
    mkdirSync(_RUN_DIR, { recursive: true, mode: 0o700 });
    const rec = JSON.stringify({ v: 1, role, session_id: cleanSid, hmac: signRole(role, cleanSid, key) });
    const tmp = tokenPath(cleanSid) + ".tmp";
    writeFileSync(tmp, rec, { mode: 0o600 });
    renameSync(tmp, tokenPath(cleanSid)); // atomic publish
    return true;
  } catch {
    return false;
  }
}

// Returns the HMAC-verified role for this session id, or null (no/invalid token).
function verifyToken(sid) {
  const cleanSid = _sanitizeSid(sid);
  if (!cleanSid) return null;
  const key = getMachineKey();
  if (!key) return null;
  try {
    const p = tokenPath(cleanSid);
    if (!existsSync(p)) return null;
    const rec = JSON.parse(readFileSync(p, "utf8"));
    if (!rec || rec.session_id !== cleanSid || typeof rec.role !== "string" || typeof rec.hmac !== "string") return null;
    const expected = signRole(rec.role, cleanSid, key);
    const a = Buffer.from(expected, "hex");
    const b = Buffer.from(rec.hmac, "hex");
    // timingSafeEqual throws on length mismatch — kept inside try → treated as tamper.
    if (a.length === b.length && timingSafeEqual(a, b)) return rec.role;
    process.stderr.write(`[safe-exec] role token for ${cleanSid} failed HMAC verification — ignoring (tamper?).\n`);
    return null;
  } catch {
    return null;
  }
}

// E-129: role resolution for the --check gate path. The HMAC-verified token wins
// over the (mutable) live env; only when there is no session id, the token layer
// is rolled back, or no valid token exists do we fall back to the legacy E-127
// env-over-arg logic — which keeps every pre-E-129 test (none pass --session) green.
function verifyCheckRole(argRole, sid) {
  if (process.env.AI_OS_SAFE_EXEC_GATE === "0" || process.env.AI_OS_ROLE_TOKEN === "0") return effectiveRole(argRole);
  if (!sid) return effectiveRole(argRole); // session-id gate → legacy/back-compat
  const verified = verifyToken(sid);
  if (verified) return verified;            // verified role wins; live env IGNORED
  return effectiveRole(argRole);            // no valid token → legacy fallback
}

instrument(server, "safe-exec-mcp", CallToolRequestSchema);
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "analyze_command") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }

  const { report } = runAnalysis(args.command, effectiveRole(args.caller_role));
  return { content: [{ type: "text", text: report }] };
});

// ── E-129: mint a tamper-resistant role token for a session and exit ──────────
// `node index.js --mint-token <role> <session_id>` is invoked by the SessionStart
// hook (role baked into which agent's settings registered the hook; sid from the
// harness payload). Fail-open: never blocks session start.
// Bound to argv[2]: a bare indexOf scan let `--verify-role --mint-token` be captured
// by THIS block, which exits 0 printing nothing — violating --verify-role's contract
// that exit 0 means a role on stdout. Same class as the E-208 --session confusion.
// Every caller invokes the mode as the first argument, so this is behaviour-preserving.
const _mintIdx = process.argv[2] === "--mint-token" ? 2 : -1;
if (_mintIdx !== -1) {
  mintToken(process.argv[_mintIdx + 1], process.argv[_mintIdx + 2]);
  process.exit(0);
}

// ── E-214: role lookup for callers that hold a session id but no payload ──────
// `node index.js --verify-role <session_id>` prints the HMAC-VERIFIED role for that
// session and exits 0, or prints nothing and exits 1 when there is no valid record.
//
// WHY: the git pre-commit hook has no PreToolUse payload to read a session id from,
// but Claude Code exports CLAUDE_CODE_SESSION_ID into the environment, so the hook can
// resolve the same tamper-resistant record the Bash and Write gates use instead of
// trusting the mutable AI_OS_CALLER_ROLE alone. Read-only: it never mints.
// Bound to argv[2] for the same reason as --mint-token: a bare indexOf let another
// mode's arguments capture this block. Every caller passes the mode first.
const _verifyRoleIdx = process.argv[2] === "--verify-role" ? 2 : -1;
if (_verifyRoleIdx !== -1) {
  const vrSid = process.argv[_verifyRoleIdx + 1] || "";
  const verified = vrSid ? verifyToken(vrSid) : null;
  if (!verified) process.exit(1);
  process.stdout.write(verified);
  process.exit(0);
}

// ── E-208: Write/Edit sovereignty gate CLI (role-abstraction.md §Components 5) ──
// `node index.js --check-path "<path>" [caller_role] [--session <sid>]` exits 2 when
// the session's HMAC-verified role is `architect` and the path lies outside .ai/ or
// plans/, 0 otherwise. hooks/pre-tool-use.sh calls this for Write|Edit|MultiEdit|
// NotebookEdit. The ENGINEER path is a fast exit 0 — this gate adds no restriction
// for the Engineer. For a Claude Architect it NARROWS gap G2; it does not close it
// (shell writes and MCP write tools are still open — see the scope note on
// architectPathVerdict above).
const _checkPathIdx = process.argv.indexOf("--check-path");
if (_checkPathIdx !== -1) {
  const target = process.argv[_checkPathIdx + 1] || "";
  // Scan for --session AFTER the two fixed positionals (<path> [role]). A bare
  // indexOf would match a TARGET PATH literally named "--session" first and then
  // read the role as the session id, dropping the check to the env fallback
  // (E-208 audit, argv confusion).
  const _spIdx = process.argv.indexOf("--session", _checkPathIdx + 3);
  const spSid = _spIdx !== -1 ? process.argv[_spIdx + 1] : "";
  const pathRole = verifyCheckRole(process.argv[_checkPathIdx + 2], spSid);
  if (String(pathRole).toLowerCase() !== "architect") process.exit(0);
  let verdict;
  try {
    if (process.env.AI_OS_SAFE_EXEC_SELFTEST_THROW === "1") throw new Error("self-test fault injection");
    verdict = architectPathVerdict(target, findProjectRootFrom(process.cwd()));
  } catch (e) {
    // FAIL-CLOSED, same rule as --check (T-HITL-004): a crash must block, never allow.
    process.stdout.write(
      "## safe-exec-mcp Sovereignty Analysis\nVerdict: \u2717 BLOCK\n\n" +
      "### BLOCKED \u2014 analyzer error (fail-closed)\n" +
      `The path gate crashed; the write is blocked rather than allowed: ${e.message}\n`
    );
    process.exit(2);
  }
  if (verdict.blocked) {
    process.stdout.write(
      "## safe-exec-mcp Sovereignty Analysis\nVerdict: \u2717 BLOCK\n\n" +
      "### BLOCKED \u2014 ARCH_WRITE_OUTSIDE_SCOPE\n" +
      `Role: architect (HMAC-verified session token)\nPath: ${target}\n` +
      `Reason: ${verdict.reason}.\n\n` +
      "The Architect designs; the Engineer implements (\u00a735 ANTI-DRIFT, D-054).\n" +
      "Write the blueprint under .ai/ and hand the change-list to the Engineer via `ai handoff engineer`.\n"
    );
    process.exit(2);
  }
  process.exit(0);
}

// ── E-125/E-129: fail-closed pre-execution gate CLI (sovereignty-hardening.md / T-HITL-004) ──
// `node index.js --check "<command>" [caller_role] [--session <sid>]` runs the same
// analysis the analyze_command tool uses and EXITS 2 on a BLOCK verdict (fail-closed),
// 0 otherwise. hooks/pre-tool-use.sh invokes this on every Bash tool call so a BLOCK
// is actually PREVENTED, not merely reported. E-129: when --session is supplied the
// role comes from the HMAC-verified session token (not the mutable env). Running in
// --check mode short-circuits before the stdio server connects.
const _checkIdx = process.argv.indexOf("--check");
if (_checkIdx !== -1) {
  const cmd = process.argv[_checkIdx + 1] || "";
  const _sIdx = process.argv.indexOf("--session");
  const sid = _sIdx !== -1 ? process.argv[_sIdx + 1] : "";
  // E-129: token-verified role wins over the live env; no sid → legacy E-127 path.
  const role = verifyCheckRole(process.argv[_checkIdx + 2], sid);
  if (!cmd) {
    process.stderr.write("[safe-exec --check] no command provided\n");
    process.exit(0); // empty input is not an error — nothing to gate
  }
  let result;
  try {
    // E-128: fault-injection self-test hook so the suite can verify the
    // fail-closed guarantee deterministically. SAFE — it can only ADD restriction
    // (force a block), never bypass the gate, so honouring it from env is harmless.
    if (process.env.AI_OS_SAFE_EXEC_SELFTEST_THROW === "1") throw new Error("self-test fault injection");
    result = runAnalysis(cmd, role);
  } catch (e) {
    // E-128 (sovereignty-hardening.md): the error path is FAIL-CLOSED. An internal
    // analyzer crash must BLOCK (exit 2), not allow — a fail-open error path would
    // be a gate-circumvention vector (T-HITL-004: crash the analyzer to bypass it).
    process.stderr.write(`[safe-exec --check] analyzer error — FAILING CLOSED (blocking): ${e.message}\n`);
    process.stdout.write(
      "## safe-exec-mcp Analysis\nVerdict: ✗ BLOCK\n\n" +
      "### BLOCKED — analyzer error (fail-closed)\n" +
      "The safe-exec analyzer crashed; the command is blocked rather than allowed " +
      "(fail-closed, T-HITL-004). Rollback: AI_OS_SAFE_EXEC_GATE=0.\n"
    );
    process.exit(2);
  }
  // Report always goes to stdout (clean, no node-warning noise); the EXIT CODE is
  // the machine signal the hook reads — 2 = BLOCK (fail-closed), 0 = allow.
  process.stdout.write(result.report + "\n");
  process.exit(result.verdict === "BLOCK" ? 2 : 0);
}

if (isMainModule(import.meta.url)) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
