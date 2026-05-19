/**
 * standards-checker.mjs — E-80 Engineering-Standards static analyser.
 *
 * Implements the §API contract from .ai/blueprints/engineering-standards.md:
 *
 *   validateStandards(diff_path) -> ComplianceReport
 *   reportDrift(report)          -> structured warning stream (caller-decided)
 *
 * Backed by src/shared/standards.json (the Standards-Registry). Each rule
 * carries a `rule_id` whose handler lives in RULE_REGISTRY here.
 *
 * Pure node:fs / node:path / node:child_process — no external deps. Each
 * rule is a regex / line-count / glob test, kept cheap enough to honour
 * the blueprint's <200ms per-commit budget.
 *
 * Security boundary (blueprint §Security): handlers only introspect file
 * SHAPE (line count, regex matches, path patterns). They never evaluate
 * business logic, never spawn shells against the file content, never
 * read parent directories above the project root.
 *
 * Usage (programmatic):
 *   import { validateStaged, loadStandards } from "./shared/standards-checker.mjs";
 *   const rules  = loadStandards();
 *   const report = validateStaged(repoRoot, rules);
 *   if (report.summary.error_count > 0) process.exit(1);
 *
 * Usage (CLI — see scripts/standards.mjs):
 *   node scripts/standards.mjs check --staged   # default
 *   node scripts/standards.mjs check --file <path>
 *   node scripts/standards.mjs list-rules
 */

import { readFileSync, existsSync, statSync } from "node:fs";
import { resolve, relative, basename, dirname } from "node:path";
import { spawnSync } from "node:child_process";

const SERVICE = "standards-checker";

/** Default standards.json location, resolved relative to this module. */
export const DEFAULT_STANDARDS_PATH = new URL("./standards.json", import.meta.url).pathname;

/** Severity → exit-code semantics — only `error` makes the CLI exit non-zero. */
export const SEVERITY_ORDER = { info: 0, warning: 1, error: 2 };

// ── Structured stderr logger (obs_baseline §Logging) ────────────────────────
function log(level, message, extras = {}) {
  process.stderr.write(JSON.stringify({
    timestamp: new Date().toISOString(),
    level, service: SERVICE, message, ...extras,
  }) + "\n");
}

/** Load + lightly validate standards.json. Throws on schema violation. */
export function loadStandards(jsonPath = DEFAULT_STANDARDS_PATH) {
  const raw = readFileSync(jsonPath, "utf8");
  const parsed = JSON.parse(raw);
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.rules)) {
    throw new Error(`standards.json: expected { rules: [...] }`);
  }
  for (const r of parsed.rules) {
    if (typeof r.rule_id !== "string" || r.rule_id.length === 0) {
      throw new Error(`standards.json: rule is missing rule_id`);
    }
    if (!["info", "warning", "error"].includes(r.severity)) {
      throw new Error(`standards.json: rule ${r.rule_id} has invalid severity '${r.severity}'`);
    }
    if (typeof r.description !== "string" || r.description.length === 0) {
      throw new Error(`standards.json: rule ${r.rule_id} is missing description`);
    }
    if (typeof r.auto_fix_available !== "boolean") {
      throw new Error(`standards.json: rule ${r.rule_id} is missing auto_fix_available (boolean)`);
    }
  }
  return parsed;
}

// ── Glob matcher (sufficient for the patterns we ship in standards.json) ────
// Supports:
//   '**' / '**/'  — zero-or-more path segments (matches src/foo AND src/a/b/foo)
//   '*'           — any chars within ONE path segment
//   literal / . _ - (regex-escaped where needed)
function _globToRegex(glob) {
  let regex = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        if (glob[i + 2] === "/") {
          // '**/' — zero or more directory segments (collapses empty case).
          regex += "(?:[^/]+/)*";
          i += 2;
        } else {
          // '**' at the tail or alone — greedy cross-segment match.
          regex += ".*";
          i += 1;
        }
      } else {
        // '*' — segment-local.
        regex += "[^/]*";
      }
    } else if ("\\.+^$()|[]{}?".includes(c)) {
      regex += "\\" + c;
    } else {
      regex += c;
    }
  }
  return new RegExp(`^${regex}$`);
}

function _pathMatchesAny(relativePath, globs) {
  for (const g of globs) {
    if (_globToRegex(g).test(relativePath)) return true;
  }
  return false;
}

// ── Rule handlers ───────────────────────────────────────────────────────────
// Each handler is `(ctx) => Violation | Violation[] | null`
// where ctx = { filePath, relPath, content, lines, rule, repoRoot }
// and Violation = { rule_id, severity, line?, message }.

const SECRET_PATTERNS = [
  { name: "AWS_ACCESS_KEY",      re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: "STRIPE_LIVE",         re: /\bsk_live_[0-9A-Za-z]{16,}\b/ },
  { name: "SLACK_BOT_TOKEN",     re: /\bxox[bp]-[0-9A-Za-z-]{10,}\b/ },
  { name: "GITHUB_PAT",          re: /\b(ghp|ghs|gho|ghu|ghr)_[A-Za-z0-9]{30,}\b/ },
  { name: "PRIVATE_KEY_BLOCK",   re: /-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/ },
];

export const RULE_REGISTRY = {
  file_size_limit_lines(ctx) {
    const n = ctx.lines.length;
    const warn = ctx.rule.warn_threshold ?? 500;
    const err  = ctx.rule.threshold ?? 1000;
    if (n > err) {
      return {
        rule_id: ctx.rule.rule_id, severity: "error", line: n,
        message: `file has ${n} lines (limit ${err}) — split into focused modules`,
      };
    }
    if (n > warn) {
      return {
        rule_id: ctx.rule.rule_id, severity: "warning", line: n,
        message: `file has ${n} lines (warn ≥ ${warn}) — consider splitting`,
      };
    }
    return null;
  },

  mcp_stdout_purity(ctx) {
    // Mirror E-48: refuse console.log / console.info; allow .error / .warn / .debug.
    // Skip lines that look like single-line comments. Multi-line comment
    // skipping is approximate — exact AST matching is E-81 territory.
    const violations = [];
    let inBlockComment = false;
    for (let i = 0; i < ctx.lines.length; i++) {
      let line = ctx.lines[i];
      if (inBlockComment) {
        const end = line.indexOf("*/");
        if (end < 0) continue;
        line = line.slice(end + 2);
        inBlockComment = false;
      }
      // Strip line-comments and block-comments that open/close on same line.
      line = line.replace(/\/\*[^]*?\*\//g, "");
      const startBlock = line.indexOf("/*");
      if (startBlock >= 0 && line.indexOf("*/", startBlock) < 0) {
        line = line.slice(0, startBlock);
        inBlockComment = true;
      }
      const codeOnly = line.replace(/\/\/.*$/, "");
      if (/\bconsole\.(log|info)\s*\(/.test(codeOnly)) {
        violations.push({
          rule_id: ctx.rule.rule_id, severity: "error", line: i + 1,
          message: `console.log / console.info call in src/mcp/** breaks JSON-RPC stdout purity`,
        });
      }
    }
    return violations;
  },

  no_committed_tmp_files(ctx) {
    const name = basename(ctx.relPath);
    if (/\.(tmp|bak|swp|orig)$/i.test(name)) {
      return {
        rule_id: ctx.rule.rule_id, severity: "error",
        message: `staged file ${name} looks like editor/merge cruft`,
      };
    }
    return null;
  },

  kebab_case_filenames(ctx) {
    const name = basename(ctx.relPath);
    // Strip extension(s); the stem must be either kebab-case, single-camelCase,
    // single-PascalCase, or single lower-case word.
    const stem = name.replace(/\.(js|mjs|ts|tsx)$/, "");
    if (/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(stem)) return null;          // kebab-case
    if (/^[a-z][a-zA-Z0-9]*$/.test(stem)) return null;                       // camelCase
    if (/^[A-Z][a-zA-Z0-9]*$/.test(stem) && !stem.includes("_")) return null; // PascalCase (component-ish)
    return {
      rule_id: ctx.rule.rule_id, severity: "warning",
      message: `filename '${name}' is not kebab-case / camelCase — ESM case-sensitivity risk`,
    };
  },

  no_secrets_in_diff(ctx) {
    const violations = [];
    for (let i = 0; i < ctx.lines.length; i++) {
      for (const { name, re } of SECRET_PATTERNS) {
        if (re.test(ctx.lines[i])) {
          violations.push({
            rule_id: ctx.rule.rule_id, severity: "error", line: i + 1,
            message: `secret pattern '${name}' detected in line ${i + 1} — refuse to commit`,
          });
        }
      }
    }
    return violations;
  },

  mandatory_shared_helper(ctx) {
    // Heuristic: a file under src/mcp/** that imports node:sqlite directly
    // (vs. going through state-db.js or wal-flusher.mjs) earns a warning.
    if (!ctx.relPath.startsWith("src/mcp/")) return null;
    // Skip the helpers themselves.
    if (ctx.relPath === "src/mcp/shared/state-db.js") return null;
    if (/\bfrom\s+["']node:sqlite["']/.test(ctx.content) ||
        /require\s*\(\s*["']node:sqlite["']\s*\)/.test(ctx.content)) {
      return {
        rule_id: ctx.rule.rule_id, severity: "warning",
        message: `direct node:sqlite import — prefer src/mcp/shared/state-db.js helpers`,
      };
    }
    return null;
  },
};

// ── Per-file validation ─────────────────────────────────────────────────────
/**
 * Validate one file against every applicable rule. Returns a ComplianceReport
 * per blueprint §Data Model: `{ file_path, status, violated_rules: [...] }`.
 *
 * If the file does not exist (e.g. staged then removed in the same diff),
 * returns a status:"MISSING" entry rather than throwing.
 */
export function validateFile(filePath, rules, opts = {}) {
  const repoRoot = opts.repoRoot ? resolve(opts.repoRoot) : process.cwd();
  const abs = resolve(filePath);
  const relPath = relative(repoRoot, abs).split(/[\\\/]/).join("/");

  if (!existsSync(abs)) {
    return { file_path: relPath, status: "MISSING", violated_rules: [] };
  }
  let st;
  try { st = statSync(abs); } catch {
    return { file_path: relPath, status: "MISSING", violated_rules: [] };
  }
  if (!st.isFile()) {
    return { file_path: relPath, status: "SKIPPED", violated_rules: [] };
  }

  let content;
  try {
    content = readFileSync(abs, "utf8");
  } catch {
    // Binary file — only path-based rules can apply.
    content = "";
  }
  const lines = content.length > 0 ? content.split("\n") : [];

  const violations = [];
  for (const rule of rules) {
    const handler = RULE_REGISTRY[rule.rule_id];
    if (!handler) continue; // unknown rule_id — skip rather than error
    const applies = Array.isArray(rule.applies_to)
      ? _pathMatchesAny(relPath, rule.applies_to)
      : true;
    if (!applies) continue;
    // E-82 hotfix: applies_to_excludes lets rules opt specific path
    // patterns out (e.g. tests/** for no_secrets_in_diff whose own
    // fixtures document the very patterns it detects).
    if (Array.isArray(rule.applies_to_excludes)
        && _pathMatchesAny(relPath, rule.applies_to_excludes)) continue;
    const result = handler({ filePath: abs, relPath, content, lines, rule, repoRoot });
    if (!result) continue;
    if (Array.isArray(result)) {
      violations.push(...result);
    } else {
      violations.push(result);
    }
  }

  const hasError   = violations.some(v => v.severity === "error");
  const hasWarning = violations.some(v => v.severity === "warning");
  const status = hasError ? "FAIL" : hasWarning ? "WARN" : "PASS";
  return { file_path: relPath, status, violated_rules: violations };
}

/**
 * Validate every staged file under git's index. Used by the pre-commit
 * gate (E-82) and the CLI's default `check --staged` mode.
 *
 * Returns:
 *   {
 *     reports:  [ComplianceReport, ...],
 *     summary:  { error_count, warning_count, files_checked, elapsed_ms },
 *   }
 */
export function validateStaged(repoRoot, rules, opts = {}) {
  const t0 = Date.now();
  const root = resolve(repoRoot);
  const res = spawnSync(
    "git", ["-C", root, "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }
  );
  if (res.error || res.status !== 0) {
    return {
      reports: [],
      summary: { error_count: 0, warning_count: 0, files_checked: 0, elapsed_ms: Date.now() - t0 },
    };
  }
  const staged = res.stdout.split("\n").map(s => s.trim()).filter(Boolean);
  return validateFiles(staged.map(p => resolve(root, p)), rules, { repoRoot: root, ...opts });
}

/** Validate an arbitrary set of absolute paths. Useful for tests + ad-hoc CLI. */
export function validateFiles(filePaths, rules, opts = {}) {
  const t0 = Date.now();
  const reports = filePaths.map(fp => validateFile(fp, rules, opts));
  let error_count = 0;
  let warning_count = 0;
  for (const r of reports) {
    for (const v of r.violated_rules) {
      if (v.severity === "error") error_count++;
      else if (v.severity === "warning") warning_count++;
    }
  }
  return {
    reports,
    summary: {
      error_count, warning_count,
      files_checked: reports.length,
      elapsed_ms: Date.now() - t0,
    },
  };
}

/**
 * Pre-format a ComplianceReport set for the ai-review synthesizer
 * (per blueprint §API reportDrift). Returns a structured object the
 * caller can serialize / surface to a human or stamp into REVIEWS.md.
 */
export function reportDrift(reports) {
  const driftEntries = [];
  for (const r of reports) {
    for (const v of r.violated_rules) {
      driftEntries.push({
        file_path: r.file_path,
        rule_id:   v.rule_id,
        severity:  v.severity,
        line:      v.line ?? null,
        message:   v.message,
      });
    }
  }
  return {
    drift_count: driftEntries.length,
    entries:     driftEntries,
  };
}

/**
 * Backwards-compat shim for the blueprint's `validateStandards(diff_path)`
 * API signature. `diff_path` is interpreted as a path or a git ref:
 *   - If it's an absolute / relative path to an existing file → validate that file
 *   - If it's '--staged' → validateStaged (default behaviour for pre-commit hook)
 */
export function validateStandards(diffPath, opts = {}) {
  const rules = (opts.rules || loadStandards().rules);
  if (!diffPath || diffPath === "--staged") {
    return validateStaged(opts.repoRoot || process.cwd(), rules, opts);
  }
  return validateFiles([resolve(diffPath)], rules, opts);
}
