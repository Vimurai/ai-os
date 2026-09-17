// ci-record.mjs — the shell side of the local CI run record (E-266, D-072,
// local-ci.md §Components 3-4). `ai ci` is bash; the ci_runs table is node:sqlite. This
// CLI is the bridge, and every command goes through src/mcp/shared/ci-runs.js — the same
// module get_ci_status and the E-267 gates read — so the shell view and the MCP view
// cannot drift.
//
//   node ci-record.mjs record  --ai-dir <d> --log <path> [--prune-dir <d>]
//   node ci-record.mjs status  --ai-dir <d> --sha <sha> [--short]   exit 0 PASS / 1 not green / 2 no certifying row
//   node ci-record.mjs list    --ai-dir <d> [-n <N>]
//   node ci-record.mjs log     --ai-dir <d> --sha <sha> [--failed]  exit 2 when no row / log gone
//   node ci-record.mjs gate    --ai-dir <d> --sha <sha> [--ref <r>]  exit 0 certified / 1 refused (pre-push, E-267)
//   node ci-record.mjs skip    --ai-dir <d> --sha <sha> --reason <text> [--ref <r>]
//
// Only `record` (the runner) and `skip` (the pre-push bypass) write.

import { realpathSync, existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { getDb } from "../mcp/shared/state-db.js";
import {
  recordCiRunFromLog, ciVerdict, shortLine, listCiRuns, latestCiRun, failedSections,
  pruneCiLogs, ageOf, certifyingRunFor, ciRunCount, recordCiSkip,
} from "../mcp/shared/ci-runs.js";

function parseArgs(argv) {
  const opts = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--short" || a === "--failed") opts[a.slice(2)] = true;
    else if (a === "-n") opts.n = argv[++i];
    else if (a.startsWith("--")) opts[a.slice(2)] = argv[++i];
    else opts._.push(a);
  }
  return opts;
}

function _db(aiDir) {
  if (!aiDir || !existsSync(aiDir)) {
    process.stderr.write(`ai ci: no .ai/ directory at ${aiDir} — run: ai init\n`);
    process.exit(2);
  }
  return getDb(resolve(aiDir));
}

function _suite(r) {
  return r.suite_pass == null ? "-" : `${r.suite_pass} passed, ${r.suite_fail ?? 0} failed, ${r.suite_skip ?? 0} skipped`;
}

export function run(argv) {
  const [cmd, ...rest] = argv;
  const o = parseArgs(rest);
  switch (cmd) {
    case "record": {
      const db = _db(o["ai-dir"]);
      const id = recordCiRunFromLog(db, o.log);
      if (o["prune-dir"]) pruneCiLogs(o["prune-dir"], { keep: o.log });
      process.stdout.write(`${id}\n`);
      return 0;
    }
    case "status": {
      const db = _db(o["ai-dir"]);
      const v = ciVerdict(db, o.sha);
      if (o.short) {
        process.stdout.write(`${shortLine(v, o.sha)}\n`);
      } else if (v.kind === "NONE") {
        process.stdout.write(`local CI: no run for ${o.sha.slice(0, 7)} — run: ai ci run\n`);
      } else {
        const r = v.row;
        process.stdout.write([
          `local CI: ${v.kind} ${r.sha.slice(0, 7)}${r.dirty ? " (dirty — not a certification)" : ""}`,
          `  ref:      ${r.ref || "-"}${r.branch ? ` (${r.branch})` : ""}`,
          `  started:  ${r.started_at} (${ageOf(r.started_at)})${r.duration_ms != null ? `, ${Math.round(r.duration_ms / 1000)}s` : ""}`,
          `  suite:    ${_suite(r)}, leaked ${r.leaked ?? 0}`,
          `  unit:     ${r.unit_status || "-"}${r.unit_coverage ? ` (${r.unit_coverage})` : ""}`,
          `  secrets:  ${r.secrets_status || "-"}`,
          `  host:     node ${r.node_version || "?"}, bash ${r.bash_version || "?"}, ${r.os || "?"}`,
          ...(r.skip_reason ? [`  skipped:  ${r.skip_reason}`] : []),
          `  log:      ${r.log_path || "-"}`,
        ].join("\n") + "\n");
      }
      if (v.kind === "PASS") return 0;
      if (v.kind === "NONE" || v.kind === "DIRTY") return 2;
      return 1;
    }
    case "list": {
      const db = _db(o["ai-dir"]);
      const rows = listCiRuns(db, Number(o.n) || 10);
      if (!rows.length) {
        process.stdout.write("local CI: no runs recorded — run: ai ci run\n");
        return 0;
      }
      for (const r of rows) {
        const dur = r.duration_ms != null ? `${Math.round(r.duration_ms / 1000)}s` : "-";
        process.stdout.write(
          `${r.status.padEnd(7)} ${r.sha.slice(0, 7)} ${r.dirty ? "dirty" : "     "} ` +
          `${(r.branch || r.ref || "-").padEnd(28)} ${ageOf(r.started_at).padEnd(8)} ${dur.padStart(6)}  ${_suite(r)}\n`);
      }
      return 0;
    }
    case "log": {
      const db = _db(o["ai-dir"]);
      const r = latestCiRun(db, o.sha);
      if (!r) {
        process.stderr.write(`ai ci log: no run recorded for ${o.sha.slice(0, 7)} — run: ai ci run\n`);
        return 2;
      }
      if (!r.log_path || !existsSync(r.log_path)) {
        process.stderr.write(`ai ci log: the log for ${r.sha.slice(0, 7)} was pruned (${r.log_path || "no path"})\n`);
        return 2;
      }
      const text = readFileSync(r.log_path, "utf8");
      if (!o.failed) {
        process.stdout.write(text);
        return 0;
      }
      const secs = failedSections(text);
      process.stdout.write(`# ${r.status} ${r.sha.slice(0, 7)} — ${r.log_path}\n`);
      process.stdout.write(secs.length ? secs.join("\n\n") + "\n" : "(no failing sections)\n");
      return 0;
    }
    case "gate": {
      // pre-push: may this sha leave the machine? Inactive (exit 0, with a notice) until
      // the project has recorded a run, like the DONE gate.
      const db = _db(o["ai-dir"]);
      const sha7 = o.sha.slice(0, 7);
      const label = o.ref || sha7;
      if (ciRunCount(db) === 0) {
        process.stderr.write(`[CI_GATE] ${label}: not enforced — no ai ci run recorded in this project yet\n`);
        return 0;
      }
      const repo = resolve(o["ai-dir"], "..");
      const c = certifyingRunFor(db, repo, o.sha, { allowSkipped: true });
      if (c.ok) {
        const how = c.via === "self" ? `${c.kind} run` : `tested ancestor ${c.row.sha.slice(0, 7)}, only .ai/ differs`;
        process.stderr.write(`[CI_GATE] ${label}: ${sha7} ok (${how})\n`);
        return 0;
      }
      let why;
      if (c.via === "self") why = `its run is ${c.kind}`;
      else if (c.row) why = `nearest tested ancestor ${c.row.sha.slice(0, 7)} differs outside .ai/: ${c.differs.slice(0, 3).join(", ")}${c.differs.length > 3 ? ", …" : ""}`;
      else why = "no run for it or for a tested ancestor";
      process.stderr.write(
        `[CI_GATE] ${label}: no green local CI run for ${sha7} (${why}) — run: ai ci run, ` +
        "or AI_OS_CI_SKIP=1 AI_OS_CI_SKIP_REASON=\"<why>\" git push\n");
      return 1;
    }
    case "skip": {
      const reason = String(o.reason || "").trim();
      if (!reason) {
        process.stderr.write("[CI_GATE] AI_OS_CI_SKIP=1 needs AI_OS_CI_SKIP_REASON=\"<why>\" — a skip is recorded, never silent\n");
        return 1;
      }
      const db = _db(o["ai-dir"]);
      recordCiSkip(db, { sha: o.sha, ref: o.ref || null, reason });
      process.stderr.write(`[CI_GATE] ${o.ref || o.sha.slice(0, 7)}: SKIPPED (recorded) — ${reason}\n`);
      return 0;
    }
    default:
      process.stderr.write("usage: ci-record.mjs <record|status|list|log|gate|skip> --ai-dir <d> …\n");
      return 2;
  }
}

// Main-module check on REAL paths: argv[1] may be spelled through a symlink (macOS
// /var → /private/var) while import.meta.url is resolved — comparing the raw spellings
// made other helpers silently do nothing under `ai ci run` (E-265).
function _isMain() {
  try {
    return !!process.argv[1] &&
      realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch { return false; }
}

if (_isMain()) {
  try {
    process.exitCode = run(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`ai ci: ${e.message}\n`);
    process.exitCode = 2;
  }
}
