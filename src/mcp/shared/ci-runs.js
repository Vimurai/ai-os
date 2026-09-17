/**
 * ci-runs.js — the local CI run record (E-266, D-072, local-ci.md §Components 3-4).
 *
 * "CI green" from D-072 on means: a NON-DIRTY `ci_runs` row with status PASS exists for the
 * commit. This module owns that table — its schema, its up/down migration and every read
 * and write — so `ai ci run` (writer), `ai ci status/list/log`, `get_ci_status` and the
 * E-267 gates all see one definition. It lives beside state-db.js rather than inside it
 * because state-db.js is already past the 500-line warning, and getDb() calls
 * migrateCiRuns() so every opened state store carries the table.
 *
 * Like state-db.js, this is NOT hot-reloaded (D-067 §3): a server booted before this
 * file changed keeps the old code until it restarts, and E-249 announces that.
 */

import { readFileSync, readdirSync, statSync, unlinkSync, existsSync } from "fs";
import { join } from "path";
import { execFileSync } from "child_process";

export const CI_STATUSES = ["PASS", "FAIL", "ERROR", "SKIPPED"];

// Log retention mirrors the retired workflow's 14-day artifact retention, capped at 14 runs.
export const CI_LOG_KEEP_RUNS = 14;
export const CI_LOG_KEEP_DAYS = 14;

export const CI_RUNS_UP = `
  CREATE TABLE IF NOT EXISTS ci_runs (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    sha            TEXT NOT NULL,
    ref            TEXT,
    branch         TEXT,
    dirty          INTEGER NOT NULL DEFAULT 0,
    status         TEXT NOT NULL CHECK (status IN ('PASS','FAIL','ERROR','SKIPPED')),
    started_at     TEXT NOT NULL,
    finished_at    TEXT,
    duration_ms    INTEGER,
    suite_pass     INTEGER,
    suite_fail     INTEGER,
    suite_skip     INTEGER,
    leaked         INTEGER,
    unit_status    TEXT,
    unit_coverage  TEXT,
    secrets_status TEXT,
    node_version   TEXT,
    bash_version   TEXT,
    patch_version  TEXT,
    os             TEXT,
    perf_json      TEXT,
    skip_reason    TEXT,
    log_path       TEXT
  );
  CREATE INDEX IF NOT EXISTS ci_runs_sha ON ci_runs(sha, started_at DESC);
`;

export const CI_RUNS_DOWN = `
  DROP INDEX IF EXISTS ci_runs_sha;
  DROP TABLE IF EXISTS ci_runs;
`;

const COLUMNS = [
  "sha", "ref", "branch", "dirty", "status", "started_at", "finished_at", "duration_ms",
  "suite_pass", "suite_fail", "suite_skip", "leaked", "unit_status", "unit_coverage",
  "secrets_status", "node_version", "bash_version", "patch_version", "os", "perf_json",
  "skip_reason", "log_path",
];

/** Idempotent up-migration. Safe under concurrent getDb() callers (IF NOT EXISTS). */
export function migrateCiRuns(db) {
  db.exec(CI_RUNS_UP);
}

/** Down-migration (rollback): drops the index and the table. */
export function downCiRuns(db) {
  db.exec(CI_RUNS_DOWN);
}

/**
 * Insert one run. Only the runner calls this. Returns the new row id.
 * Throws on a missing sha/started_at or an unknown status — a malformed record must not
 * become evidence a gate reads.
 */
export function recordCiRun(db, run) {
  if (!run || !run.sha || !run.started_at) throw new Error("recordCiRun: sha and started_at are required");
  if (!CI_STATUSES.includes(run.status)) throw new Error(`recordCiRun: unknown status '${run.status}'`);
  if (run.status === "SKIPPED" && !String(run.skip_reason || "").trim()) {
    throw new Error("recordCiRun: a SKIPPED run needs a skip_reason");
  }
  const vals = COLUMNS.map((c) => {
    const v = run[c];
    if (c === "dirty") return v ? 1 : 0;
    if (c === "perf_json" && v && typeof v !== "string") return JSON.stringify(v);
    return v === undefined ? null : v;
  });
  const sql = `INSERT INTO ci_runs (${COLUMNS.join(", ")}) VALUES (${COLUMNS.map(() => "?").join(", ")})`;
  return Number(db.prepare(sql).run(...vals).lastInsertRowid);
}

/**
 * Newest row for `sha`. `certifying: true` restricts to non-dirty rows — the only kind a
 * gate may accept. Returns null when there is none.
 */
export function latestCiRun(db, sha, { certifying = false } = {}) {
  const where = certifying ? "sha = ? AND dirty = 0" : "sha = ?";
  return db.prepare(`SELECT * FROM ci_runs WHERE ${where} ORDER BY started_at DESC, id DESC LIMIT 1`).get(sha) || null;
}

/** Newest `n` rows across all commits. */
export function listCiRuns(db, n = 10) {
  return db.prepare("SELECT * FROM ci_runs ORDER BY started_at DESC, id DESC LIMIT ?").all(Math.max(1, n | 0));
}

/** Row count — the E-267 adoption test ("has this project ever run ai ci?"). */
export function ciRunCount(db) {
  return db.prepare("SELECT COUNT(*) AS n FROM ci_runs").get().n;
}

/**
 * The short view a status line or a gate prints for `sha`:
 *   { kind: "PASS"|"FAIL"|"ERROR"|"SKIPPED"|"DIRTY"|"NONE", row }
 * DIRTY = only dirty rows exist; it never certifies a commit.
 */
export function ciVerdict(db, sha) {
  const cert = latestCiRun(db, sha, { certifying: true });
  if (cert) return { kind: cert.status, row: cert };
  const any = latestCiRun(db, sha);
  if (any) return { kind: "DIRTY", row: any };
  return { kind: "NONE", row: null };
}

/** "42s ago" / "7m ago" / "3h ago" / "2d ago" from an ISO-8601 timestamp. */
export function ageOf(iso, now = Date.now()) {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "?";
  const s = Math.max(0, Math.round((now - t) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

/** One line: `PASS 321cbcb 7m ago (suite 4744/0/2, unit PASS, leaked 0)`. */
export function shortLine(verdict, sha, now = Date.now()) {
  const sha7 = String(sha).slice(0, 7);
  if (verdict.kind === "NONE") return `NONE ${sha7} — no local CI run; run: ai ci run`;
  const r = verdict.row;
  const suite = r.suite_pass == null ? "suite -" : `suite ${r.suite_pass}/${r.suite_fail ?? 0}/${r.suite_skip ?? 0}`;
  let line = `${verdict.kind} ${sha7} ${ageOf(r.started_at, now)} (${suite}, unit ${r.unit_status || "-"}, leaked ${r.leaked ?? 0})`;
  if (verdict.kind === "DIRTY") line += ` — dirty run ${r.status}, not a certification; run: ai ci run`;
  if (r.status === "SKIPPED") line += ` — skipped: ${r.skip_reason}`;
  return line;
}

// ── Log parsing ─────────────────────────────────────────────────────────────
// The runner writes `[ci] key=value …` lines; the row is built from them, so the log and
// the row cannot disagree. Values run to the next ` key=`.
function _kv(line) {
  const out = {};
  const re = /(\w+)=(.*?)(?=\s+\w+=|$)/g;
  let m;
  while ((m = re.exec(line))) out[m[1]] = m[2];
  return out;
}

function _int(v) {
  const n = parseInt(v, 10);
  return Number.isNaN(n) ? null : n;
}

/**
 * Build a ci_runs record from a runner log. Returns null when the log has no header.
 * perf_json collects the E-239 `ⓘ <label>: elapsed=… baseline=… limit=…` prints.
 */
export function parseCiLog(text, logPath = null) {
  const lines = String(text).split("\n");
  const run = { log_path: logPath };
  const perf = {};
  let inUnit = false;
  for (const line of lines) {
    if (line.startsWith("[ci] sha=")) {
      const kv = _kv(line.slice(5));
      Object.assign(run, { sha: kv.sha, ref: kv.ref, dirty: kv.dirty === "1", started_at: kv.started_at });
    } else if (line.startsWith("[ci] branch=")) {
      run.branch = _kv(line.slice(5)).branch || null;
    } else if (line.startsWith("[ci] toolchain ")) {
      const kv = _kv(line.slice(15));
      Object.assign(run, { node_version: kv.node, bash_version: kv.bash, patch_version: kv.patch, os: kv.os });
    } else if (line.startsWith("[ci] result ")) {
      const kv = _kv(line.slice(12));
      Object.assign(run, {
        suite_pass: _int(kv.pass), suite_fail: _int(kv.fail), suite_skip: _int(kv.skip),
        leaked: _int(kv.leaked), unit_status: kv.unit, secrets_status: kv.secrets,
      });
    } else if (line.startsWith("[ci] finished ")) {
      const kv = _kv(line.slice(14));
      Object.assign(run, { status: kv.status, finished_at: kv.finished_at, duration_ms: _int(kv.duration_ms) });
    } else if (line.startsWith("[ci] ── ")) {
      inUnit = line.startsWith("[ci] ── unit:");
    } else if (inUnit && /^#?\s*all files\s*\|/.test(line)) {
      const pct = line.split("|")[1];
      if (pct && pct.trim()) run.unit_coverage = `${pct.trim()}% lines`;
    } else {
      const p = line.match(/ⓘ (.+?): elapsed=(\d+)ms baseline=(\d+)ms limit=(\d+)ms/);
      if (p) perf[p[1]] = { measured_ms: +p[2], baseline_ms: +p[3], budget_ms: +p[4] };
    }
  }
  if (!run.sha || !run.started_at) return null;
  if (Object.keys(perf).length) run.perf_json = JSON.stringify(perf);
  return run;
}

/** Record a run straight from its log file. Returns the row id. */
export function recordCiRunFromLog(db, logPath) {
  const run = parseCiLog(readFileSync(logPath, "utf8"), logPath);
  if (!run) throw new Error(`recordCiRunFromLog: ${logPath} has no [ci] header`);
  if (!run.status) run.status = "ERROR";   // the runner died before its finished line
  return recordCiRun(db, run);
}

/**
 * The sections of a runner log that explain a failure: every suite block whose
 * SUITE_RESULT reports FAIL>0 (or which contains a ✗ line), the leak report, the unit
 * section when it failed, and the tail when the run ERRORed before the suite.
 */
// A failing assertion line, as assert.sh prints it. Matching "✗" anywhere was wrong: an
// assertion LABEL may contain the glyph ("doctor reports ✗ …") and dragged passing suites in.
const _isFailLine = (l) => /^\s*✗ /.test(l);

export function failedSections(text) {
  const lines = String(text).split("\n");
  const out = [];
  const start = lines.findIndex((l) => l.startsWith("[ci] ── suite:"));
  const results = lines.findIndex((l, i) => i > start && l.startsWith("━━ Results"));
  if (start >= 0) {
    let block = [];
    const end = results >= 0 ? results : lines.length;
    for (let i = start + 1; i < end; i++) {
      block.push(lines[i]);
      if (lines[i].startsWith("SUITE_RESULT")) {
        const fail = _int((lines[i].match(/FAIL=(\d+)/) || [])[1]);
        if (fail > 0 || block.some(_isFailLine)) out.push(block.join("\n"));
        block = [];
      }
    }
    if (block.some(_isFailLine)) out.push(block.join("\n"));
    if (results >= 0) {
      const summary = lines.slice(results).filter((l) => _isFailLine(l) || /LEAK|Total:|\[TEST_FAILED/.test(l));
      if (summary.length) out.push(summary.join("\n"));
    }
  }
  const unit = lines.findIndex((l) => l.startsWith("[ci] ── unit:"));
  if (unit >= 0 && lines.some((l) => l.startsWith("[ci] step=unit status=FAIL"))) {
    const next = lines.findIndex((l, i) => i > unit && l.startsWith("[ci] "));
    out.push(lines.slice(unit, next < 0 ? undefined : next).join("\n"));
  }
  if (lines.some((l) => /^\[ci\] step=\S+ status=ERROR/.test(l))) {
    out.push(lines.slice(-40).join("\n"));
  }
  return out;
}

/**
 * Prune the log directory: keep the newest CI_LOG_KEEP_RUNS logs that are also younger
 * than CI_LOG_KEEP_DAYS. `keep` (the log just written) is never removed. Returns the
 * removed file names.
 */
export function pruneCiLogs(dir, { keep = null, now = Date.now(),
  runs = CI_LOG_KEEP_RUNS, days = CI_LOG_KEEP_DAYS } = {}) {
  if (!existsSync(dir)) return [];
  const logs = readdirSync(dir)
    .filter((f) => f.endsWith(".log"))
    .map((f) => ({ f, p: join(dir, f), m: statSync(join(dir, f)).mtimeMs }))
    .sort((a, b) => b.m - a.m);
  const cutoff = now - days * 86400 * 1000;
  const removed = [];
  logs.forEach((l, i) => {
    if (keep && l.p === keep) return;
    if (i >= runs || l.m < cutoff) {
      try { unlinkSync(l.p); removed.push(l.f); } catch { /* already gone */ }
    }
  });
  return removed;
}

/**
 * get_ci_status payload: the newest row for `sha` (default: HEAD of `projectRoot`), plus
 * the certifying verdict, or { status: "NONE" }. Read-only.
 */
export function getCiStatus(db, projectRoot, sha = null) {
  let target = sha;
  if (!target) {
    try {
      target = execFileSync("git", ["-C", projectRoot, "rev-parse", "--verify", "HEAD"],
        { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    } catch {
      return { status: "NONE", reason: "not a git repository or no HEAD" };
    }
  }
  if (!/^[0-9a-f]{7,40}$/i.test(target)) return { status: "NONE", sha: target, reason: "not a commit sha" };
  // An abbreviated sha matches by prefix; a full one exactly.
  const row = target.length === 40
    ? latestCiRun(db, target)
    : db.prepare("SELECT * FROM ci_runs WHERE sha LIKE ? ORDER BY started_at DESC, id DESC LIMIT 1").get(`${target}%`) || null;
  if (!row) return { status: "NONE", sha: target };
  const verdict = ciVerdict(db, row.sha);
  return { ...row, dirty: !!row.dirty, verdict: verdict.kind, summary: shortLine(verdict, row.sha) };
}

// ── E-267 (D-072 §5): the gates ─────────────────────────────────────────────

function _git(root, args) {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
}

function _isAncestor(root, a, b) {
  try { execFileSync("git", ["-C", root, "merge-base", "--is-ancestor", a, b], { stdio: "ignore" }); return true; }
  catch { return false; }
}

// How many recent PASS rows the ancestor search considers. Bookkeeping commits sit a few
// commits above the tested tip; a bound keeps the gate fast on a long history.
const ANCESTOR_SEARCH_ROWS = 50;

/**
 * Is `sha` certified by local CI?
 *
 *   1. its own newest non-dirty row decides, if it has one (PASS → ok; anything else → no;
 *      a SKIPPED row counts only with allowSkipped — the pre-push bypass);
 *   2. otherwise the newest non-dirty PASS row for an ANCESTOR counts when every path
 *      that differs between the two is under .ai/ — the bookkeeping commits ai-task makes
 *      after a DONE, and a merge commit whose tree equals the tested tip, are never CI'd
 *      on their own and must not block (local-ci.md §Components 5b).
 *
 * Returns { ok, kind, via: "self"|"ancestor"|null, row, differs: [paths] }.
 */
export function certifyingRunFor(db, repoRoot, sha, { allowSkipped = false } = {}) {
  const own = latestCiRun(db, sha, { certifying: true });
  if (own) {
    const ok = own.status === "PASS" || (allowSkipped && own.status === "SKIPPED");
    return { ok, kind: own.status, via: "self", row: own, differs: [] };
  }
  const rows = db.prepare(
    "SELECT * FROM ci_runs WHERE dirty = 0 AND status = 'PASS' AND sha != ? ORDER BY started_at DESC, id DESC LIMIT ?",
  ).all(sha, ANCESTOR_SEARCH_ROWS);
  let nearest = null;
  for (const r of rows) {
    if (!_isAncestor(repoRoot, r.sha, sha)) continue;
    let differs;
    try {
      differs = _git(repoRoot, ["diff", "--name-only", r.sha, sha]).split("\n").filter(Boolean);
    } catch { continue; }
    const outside = differs.filter((p) => !p.startsWith(".ai/"));
    if (!outside.length) return { ok: true, kind: "PASS", via: "ancestor", row: r, differs };
    if (!nearest) nearest = { row: r, differs: outside };
  }
  return { ok: false, kind: "NONE", via: null, row: nearest ? nearest.row : null, differs: nearest ? nearest.differs : [] };
}

/**
 * The update_task_status(DONE) gate. Active only in a project that has adopted `ai ci`
 * (ci_runs holds at least one row), so an upgrade never breaks a project that has not;
 * AI_OS_CI_GATE=0 disables it. Returns { ok, active, message }.
 */
export function checkCiDoneGate(db, repoRoot, env = process.env) {
  if (env.AI_OS_CI_GATE === "0") return { ok: true, active: false, message: "CI gate disabled (AI_OS_CI_GATE=0)" };
  if (ciRunCount(db) === 0) return { ok: true, active: false, message: "CI gate inactive (no ai ci run recorded yet)" };
  let head;
  try { head = _git(repoRoot, ["rev-parse", "--verify", "HEAD"]); }
  catch { return { ok: true, active: false, message: "CI gate inactive (not a git repository)" }; }
  const c = certifyingRunFor(db, repoRoot, head);
  if (c.ok) return { ok: true, active: true, message: `CI gate: ${head.slice(0, 7)} certified (${c.via})` };
  const why = c.via === "self" ? `its run is ${c.kind}` : "no run for it or for an ancestor that differs only in .ai/";
  return {
    ok: false, active: true,
    message: `[CI_GATE] no green local CI run for HEAD ${head.slice(0, 7)} (${why}) — run: ai ci run` +
      " (bypass: AI_OS_CI_GATE=0)",
  };
}

/** Record a pre-push bypass. A skip is written, never silent; a reason is mandatory. */
export function recordCiSkip(db, { sha, ref = null, branch = null, reason }) {
  return recordCiRun(db, {
    sha, ref, branch, status: "SKIPPED", skip_reason: reason,
    started_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  });
}
