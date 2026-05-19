#!/usr/bin/env node
/**
 * scripts/standards.mjs — E-80 Standards-Checker CLI.
 *
 * The `node scripts/standards.mjs` invocation named in
 * .ai/blueprints/engineering-standards.md §Components 1. Thin wrapper
 * around src/shared/standards-checker.mjs.
 *
 * Subcommands:
 *   check [--staged | --all | --file <path>] [--json]
 *     Default mode = `--staged`. Validates files via the registered
 *     rules and emits a structured report. Exit code 0 = PASS, 1 = at
 *     least one ERROR-severity violation, 2 = usage error.
 *
 *   list-rules [--json]
 *     Print every loaded rule from src/shared/standards.json.
 *
 *   --help / --version
 *     Standard banners.
 *
 * Honors AI_OS_SKIP_STANDARDS=1 (blueprint §Rollback Plan): exits 0 with
 * a stderr notice so the pre-commit hook can roll back to the legacy
 * gate without removing the wiring.
 */

import { resolve, basename } from "node:path";
import {
  loadStandards,
  validateStaged,
  validateFiles,
  validateFile,
  reportDrift,
  DEFAULT_STANDARDS_PATH,
} from "../src/shared/standards-checker.mjs";
import { readdirSync, statSync } from "node:fs";

const VERSION = "1.0.0";

function _printUsage(stream = process.stderr) {
  stream.write(
    "usage: standards.mjs <subcommand> [args]\n" +
    "  check [--staged | --all | --file <path>] [--json]\n" +
    "  list-rules [--json]\n" +
    "  --version | --help\n"
  );
}

function _emit(reportEnvelope, asJson) {
  if (asJson) {
    process.stdout.write(JSON.stringify(reportEnvelope, null, 2) + "\n");
    return;
  }
  const { reports, summary } = reportEnvelope;
  const lines = [];
  lines.push(`Standards-Checker (E-80) — ${summary.files_checked} files checked in ${summary.elapsed_ms}ms`);
  lines.push(`  errors: ${summary.error_count} | warnings: ${summary.warning_count}`);
  lines.push("");
  for (const r of reports) {
    if (r.status === "PASS") continue;
    if (r.status === "MISSING" || r.status === "SKIPPED") continue;
    lines.push(`[${r.status}] ${r.file_path}`);
    for (const v of r.violated_rules) {
      const at = v.line != null ? `:${v.line}` : "";
      lines.push(`  • [${v.severity}] ${v.rule_id}${at} — ${v.message}`);
    }
    lines.push("");
  }
  if (summary.error_count === 0 && summary.warning_count === 0) {
    lines.push("✓ Standards PASS — no violations found.");
  }
  process.stdout.write(lines.join("\n") + (lines.at(-1) === "" ? "" : "\n"));
}

function _walkSources(root, exts = [".js", ".mjs", ".ts", ".tsx"]) {
  // Best-effort source walker for `--all`. Prunes node_modules / .git / dist.
  const out = [];
  const skip = new Set(["node_modules", ".git", "dist", "build", ".ai-os"]);
  function visit(dir) {
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const ent of entries) {
      const full = resolve(dir, ent.name);
      if (ent.isDirectory()) {
        if (skip.has(ent.name)) continue;
        visit(full);
      } else if (ent.isFile()) {
        if (exts.some(e => ent.name.endsWith(e))) out.push(full);
      }
    }
  }
  visit(resolve(root, "src"));
  return out;
}

async function main() {
  const argv = process.argv.slice(2);

  if (argv.includes("--help") || argv.length === 0) {
    _printUsage(process.stdout);
    process.exit(argv.length === 0 ? 2 : 0);
  }
  if (argv.includes("--version")) {
    process.stdout.write(`standards-checker v${VERSION}\n`);
    process.exit(0);
  }

  // Rollback (blueprint §Rollback Plan).
  if (process.env.AI_OS_SKIP_STANDARDS === "1") {
    process.stderr.write("[STANDARDS_SKIPPED] AI_OS_SKIP_STANDARDS=1 — bypassing rule checks\n");
    process.exit(0);
  }

  const sub = argv[0];
  const asJson = argv.includes("--json");
  const standards = (() => {
    try { return loadStandards(); }
    catch (e) {
      process.stderr.write(`✗ failed to load standards.json: ${e.message}\n`);
      process.exit(1);
    }
  })();

  if (sub === "list-rules") {
    if (asJson) {
      process.stdout.write(JSON.stringify(standards, null, 2) + "\n");
    } else {
      process.stdout.write(`Standards Registry (v${standards.version}) — ${standards.rules.length} rules\n\n`);
      for (const r of standards.rules) {
        process.stdout.write(`[${r.severity.toUpperCase()}] ${r.rule_id}\n`);
        process.stdout.write(`  ${r.description}\n`);
        process.stdout.write(`  applies_to: ${(r.applies_to || []).join(", ")}\n`);
        process.stdout.write(`  auto_fix_available: ${r.auto_fix_available}\n\n`);
      }
    }
    process.exit(0);
  }

  if (sub === "check") {
    const repoRoot = process.cwd();
    let envelope;

    if (argv.includes("--all")) {
      const files = _walkSources(repoRoot);
      envelope = validateFiles(files, standards.rules, { repoRoot });
    } else if (argv.includes("--file")) {
      const idx = argv.indexOf("--file");
      const path = argv[idx + 1];
      if (!path) {
        process.stderr.write("✗ --file requires a path argument\n");
        process.exit(2);
      }
      envelope = validateFiles([resolve(repoRoot, path)], standards.rules, { repoRoot });
    } else {
      // Default + --staged path.
      envelope = validateStaged(repoRoot, standards.rules);
    }

    _emit(envelope, asJson);

    // Surface drift to ai-review consumers via stderr JSON line. This is the
    // §API reportDrift surface — not the human report on stdout.
    const drift = reportDrift(envelope.reports);
    if (drift.drift_count > 0) {
      process.stderr.write(JSON.stringify({
        service: "standards-checker",
        kind:    "drift_report",
        drift,
      }) + "\n");
    }

    // Performance guard (blueprint §Execution Constraints: <200ms).
    if (envelope.summary.elapsed_ms > 200) {
      process.stderr.write(JSON.stringify({
        service: "standards-checker",
        level:   "warn",
        message: "validation exceeded 200ms budget",
        elapsed_ms: envelope.summary.elapsed_ms,
      }) + "\n");
    }

    process.exit(envelope.summary.error_count > 0 ? 1 : 0);
  }

  _printUsage();
  process.exit(2);
}

main().catch((e) => {
  process.stderr.write(`✗ standards-checker crashed: ${e.message}\n`);
  process.exit(1);
});
