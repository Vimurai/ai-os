// tests/unit/ci-runs.test.mjs — node:test unit suite for src/mcp/shared/ci-runs.js (E-266)
//
// D-072: "CI green" means a NON-DIRTY ci_runs row with status PASS for the commit. These
// tests pin the record that sentence depends on: the migration (up AND down), the log →
// row parse, the verdict rules (dirty never certifies), the short line the skills inject,
// the failing-section extractor and log retention.
//
// Every test uses a fresh state store in its own temp dir. Run standalone:
//   node --test tests/unit/ci-runs.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, existsSync, utimesSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";

import { getDb } from "../../src/mcp/shared/state-db.js";
import {
  migrateCiRuns, downCiRuns, recordCiRun, latestCiRun, listCiRuns, ciRunCount, ciVerdict,
  shortLine, parseCiLog, recordCiRunFromLog, failedSections, pruneCiLogs, getCiStatus, ageOf,
  certifyingRunFor, checkCiDoneGate, recordCiSkip,
} from "../../src/mcp/shared/ci-runs.js";

function tmp() {
  const d = mkdtempSync(join(tmpdir(), "aios-t-cirun-"));
  return { d, done: () => rmSync(d, { recursive: true, force: true }) };
}

function freshDb() {
  const t = tmp();
  mkdirSync(join(t.d, ".ai"));
  return { ...t, db: getDb(join(t.d, ".ai")) };
}

const SHA = "a".repeat(40);
const base = (over = {}) => ({ sha: SHA, ref: "HEAD", status: "PASS", started_at: "2026-09-17T10:00:00Z", ...over });

const LOG = [
  "[ci] ai ci run — AI-OS 3.1.0",
  `[ci] sha=${SHA} ref=HEAD dirty=0 started_at=2026-09-17T10:00:00Z`,
  "[ci] repo=/r",
  "[ci] branch=engineer/x",
  "[ci] step=worktree status=ok /w",
  "[ci] toolchain node=v26.8.2 bash=3.2.57(1)-release patch=patch 2.0-12u11-Apple os=Darwin 27.0.0",
  "",
  "[ci] ── suite: /bin/bash tests/run.sh",
  "── Suite: good_test ──",
  "  ✓ fine",
  "  ⓘ agg: elapsed=12ms baseline=5ms limit=60ms [relative] (k=2 slack=50ms absolute=200ms)",
  "SUITE_RESULT PASS=1 FAIL=0 SKIP=0",
  "── Suite: bad_test ──",
  "  ✗ broken thing (expected exit=0, got 1)",
  "SUITE_RESULT PASS=3 FAIL=1 SKIP=0",
  "━━ Results ━━",
  "  ✓ good_test.sh (1 passed)",
  "  ✗ bad_test.sh (3 passed, 1 failed)",
  "   Total: 4 passed, 1 failed",
  "[TEST_FAILED] 1 test(s) failed ✗",
  "[ci] step=suite status=FAIL 4 passed, 1 failed, 0 skipped, leaked 0",
  "",
  "[ci] ── unit: /usr/bin/env UNIT_COVERAGE=1 /bin/bash tests/suites/node_unit_test.sh",
  "# all files            |  69.74 |    74.43 |   62.38 | ",
  "[ci] step=unit status=PASS node:test (coverage)",
  "[ci] result status=FAIL suite=FAIL pass=4 fail=1 skip=0 leaked=0 unit=PASS secrets=PASS",
  "[ci] finished status=FAIL duration_ms=610000 finished_at=2026-09-17T10:10:10Z",
].join("\n");

test("migration: up creates table + index; down drops both; up is idempotent", () => {
  const db = new DatabaseSync(":memory:");
  migrateCiRuns(db);
  migrateCiRuns(db);
  const objs = () => db.prepare("SELECT type, name FROM sqlite_master WHERE name LIKE 'ci_runs%' ORDER BY name").all()
    .map((r) => `${r.type}:${r.name}`);
  assert.deepEqual(objs(), ["table:ci_runs", "index:ci_runs_sha"]);
  assert.equal(db.prepare("PRAGMA integrity_check").get().integrity_check, "ok");
  downCiRuns(db);
  assert.deepEqual(objs(), []);
  assert.equal(db.prepare("PRAGMA integrity_check").get().integrity_check, "ok");
  downCiRuns(db);   // the down path is idempotent too
});

test("getDb carries ci_runs on a fresh store", () => {
  const { db, done } = freshDb();
  try {
    assert.equal(ciRunCount(db), 0);
  } finally { done(); }
});

test("recordCiRun rejects malformed records", () => {
  const { db, done } = freshDb();
  try {
    assert.throws(() => recordCiRun(db, base({ sha: "" })), /sha and started_at/);
    assert.throws(() => recordCiRun(db, base({ status: "GREEN" })), /unknown status/);
    assert.throws(() => recordCiRun(db, base({ status: "SKIPPED" })), /skip_reason/);
    assert.ok(recordCiRun(db, base({ status: "SKIPPED", skip_reason: "hotfix" })) > 0);
  } finally { done(); }
});

test("parseCiLog fills every column the runner writes", () => {
  const r = parseCiLog(LOG, "/logs/x.log");
  assert.deepEqual(
    { ...r, perf_json: JSON.parse(r.perf_json) },
    {
      log_path: "/logs/x.log", sha: SHA, ref: "HEAD", dirty: false, started_at: "2026-09-17T10:00:00Z",
      branch: "engineer/x", node_version: "v26.8.2", bash_version: "3.2.57(1)-release",
      patch_version: "patch 2.0-12u11-Apple", os: "Darwin 27.0.0", unit_coverage: "69.74% lines",
      suite_pass: 4, suite_fail: 1, suite_skip: 0, leaked: 0, unit_status: "PASS", secrets_status: "PASS",
      status: "FAIL", finished_at: "2026-09-17T10:10:10Z", duration_ms: 610000,
      perf_json: { agg: { measured_ms: 12, baseline_ms: 5, budget_ms: 60 } },
    });
  assert.equal(parseCiLog("no header here"), null);
});

test("recordCiRunFromLog: every column populated; a truncated log records ERROR", () => {
  const { d, db, done } = freshDb();
  try {
    const p = join(d, "run.log");
    writeFileSync(p, LOG);
    const row = db.prepare("SELECT * FROM ci_runs WHERE id = ?").get(recordCiRunFromLog(db, p));
    const empty = Object.entries(row).filter(([k, v]) => v === null && k !== "skip_reason").map(([k]) => k);
    assert.deepEqual(empty, [], `unpopulated columns: ${empty}`);
    assert.equal(existsSync(row.log_path), true);

    const cut = join(d, "cut.log");
    writeFileSync(cut, LOG.split("\n").slice(0, 6).join("\n"));
    const r2 = db.prepare("SELECT status FROM ci_runs WHERE id = ?").get(recordCiRunFromLog(db, cut));
    assert.equal(r2.status, "ERROR");
  } finally { done(); }
});

test("verdict: a dirty PASS never certifies; the newest certifying row wins", () => {
  const { db, done } = freshDb();
  try {
    assert.equal(ciVerdict(db, SHA).kind, "NONE");
    recordCiRun(db, base({ dirty: true, started_at: "2026-09-17T09:00:00Z" }));
    assert.equal(ciVerdict(db, SHA).kind, "DIRTY");
    recordCiRun(db, base({ status: "FAIL", started_at: "2026-09-17T09:30:00Z" }));
    assert.equal(ciVerdict(db, SHA).kind, "FAIL");
    // A later dirty PASS does not rescue the failing commit.
    recordCiRun(db, base({ dirty: true, started_at: "2026-09-17T09:45:00Z" }));
    assert.equal(ciVerdict(db, SHA).kind, "FAIL");
    recordCiRun(db, base({ started_at: "2026-09-17T10:00:00Z" }));
    assert.equal(ciVerdict(db, SHA).kind, "PASS");
    assert.equal(latestCiRun(db, SHA).started_at, "2026-09-17T10:00:00Z");
    assert.equal(listCiRuns(db, 2).length, 2);
  } finally { done(); }
});

test("shortLine: PASS, FAIL, DIRTY, NONE and SKIPPED", () => {
  const now = Date.parse("2026-09-17T10:07:00Z");
  const row = base({ suite_pass: 4744, suite_fail: 0, suite_skip: 2, unit_status: "PASS", leaked: 0 });
  assert.equal(shortLine({ kind: "PASS", row }, SHA, now), "PASS aaaaaaa 7m ago (suite 4744/0/2, unit PASS, leaked 0)");
  assert.match(shortLine({ kind: "FAIL", row: { ...row, status: "FAIL" } }, SHA, now), /^FAIL aaaaaaa 7m ago/);
  assert.match(shortLine({ kind: "DIRTY", row: { ...row, dirty: 1 } }, SHA, now), /^DIRTY .*not a certification; run: ai ci run$/);
  assert.equal(shortLine({ kind: "NONE", row: null }, SHA, now), "NONE aaaaaaa — no local CI run; run: ai ci run");
  assert.match(shortLine({ kind: "SKIPPED", row: { ...row, status: "SKIPPED", skip_reason: "hotfix" } }, SHA, now),
    /skipped: hotfix$/);
  assert.equal(ageOf("2026-09-15T10:07:00Z", now), "2d ago");
  assert.equal(ageOf("garbage", now), "?");
});

test("failedSections: only the failing suite, the summary, and nothing that passed", () => {
  const secs = failedSections(LOG).join("\n");
  assert.match(secs, /broken thing/);
  assert.match(secs, /bad_test\.sh \(3 passed, 1 failed\)/);
  assert.doesNotMatch(secs, /── Suite: good_test/);
  assert.deepEqual(failedSections(LOG.replace("  ✗ broken thing (expected exit=0, got 1)\n", "")
    .replace("PASS=3 FAIL=1", "PASS=3 FAIL=0").replace(/━━ Results[\s\S]*?\[ci\] step=suite/, "[ci] step=suite")), []);
  // A passing suite whose assertion LABEL contains the glyph is not a failure (E-267).
  const labelled = LOG.replace("── Suite: good_test ──", "── Suite: good_test ──\n  ✓ doctor reports ✗ for an untested HEAD");
  assert.doesNotMatch(failedSections(labelled).join("\n"), /good_test/);
  const errored = "[ci] sha=x\n[ci] step=deps status=ERROR npm ci failed\nnpm ERR! boom";
  assert.match(failedSections(errored).join("\n"), /npm ERR! boom/);
});

test("pruneCiLogs: newest 14 within 14 days; the fresh log is never removed", () => {
  const { d, done } = tmp();
  try {
    const now = Date.now();
    for (let i = 0; i < 16; i++) {
      const p = join(d, `sha${String(i).padStart(2, "0")}-run.log`);
      writeFileSync(p, "x");
      const t = (now - i * 60_000) / 1000;
      utimesSync(p, t, t);
    }
    const old = join(d, "old-run.log");
    writeFileSync(old, "x");
    const oldT = (now - 20 * 86400_000) / 1000;
    utimesSync(old, oldT, oldT);
    writeFileSync(join(d, "notes.txt"), "not a log");

    const removed = pruneCiLogs(d, { keep: old, now }).sort();
    assert.deepEqual(removed, ["sha14-run.log", "sha15-run.log"]);
    assert.equal(existsSync(old), true, "the kept log survives although it is old");
    assert.equal(readdirSync(d).filter((f) => f.endsWith(".log")).length, 15);
    assert.deepEqual(pruneCiLogs(d, { now }), ["old-run.log"]);
    assert.equal(existsSync(join(d, "notes.txt")), true);
    assert.deepEqual(pruneCiLogs(join(d, "absent")), []);
  } finally { done(); }
});

test("getCiStatus: HEAD default, abbreviated sha, NONE", () => {
  const { d, db, done } = freshDb();
  try {
    assert.equal(getCiStatus(db, d).status, "NONE");   // not a git repo yet
    execFileSync("git", ["init", "-q", d]);
    execFileSync("git", ["-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
      "commit", "-q", "--allow-empty", "-m", "x"]);
    const head = execFileSync("git", ["-C", d, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
    assert.deepEqual(getCiStatus(db, d), { status: "NONE", sha: head });
    recordCiRun(db, base({ sha: head, suite_pass: 1, suite_fail: 0, suite_skip: 0 }));
    const s = getCiStatus(db, d);
    assert.equal(s.status, "PASS");
    assert.equal(s.verdict, "PASS");
    assert.equal(s.dirty, false);
    assert.match(s.summary, /^PASS /);
    assert.equal(getCiStatus(db, d, head.slice(0, 7)).sha, head);
    assert.equal(getCiStatus(db, d, "not-a-sha").status, "NONE");
  } finally { done(); }
});

// ── E-267: the gates ─────────────────────────────────────────────────────────

function gitRepo(d) {
  const g = (...a) => execFileSync("git", ["-C", d, "-c", "user.name=t", "-c", "user.email=t@t",
    "-c", "commit.gpgsign=false", ...a], { encoding: "utf8" }).trim();
  g("init", "-q");
  const commit = (path, body, msg) => {
    mkdirSync(join(d, path, ".."), { recursive: true });
    writeFileSync(join(d, path), body);
    g("add", "-A");
    g("commit", "-q", "-m", msg);
    return g("rev-parse", "HEAD");
  };
  return { g, commit };
}

test("certifyingRunFor: self, bookkeeping ancestor, code-changing ancestor", () => {
  const { d, db, done } = freshDb();
  try {
    const { commit } = gitRepo(d);
    const tested = commit("src/a.js", "1", "code");
    const book = commit(".ai/TASKS.md", "done", "bookkeeping");
    const code = commit("src/a.js", "2", "more code");

    assert.equal(certifyingRunFor(db, d, tested).ok, false, "nothing recorded yet");
    recordCiRun(db, base({ sha: tested }));
    assert.deepEqual(
      (({ ok, via }) => ({ ok, via }))(certifyingRunFor(db, d, tested)), { ok: true, via: "self" });
    const b = certifyingRunFor(db, d, book);
    assert.deepEqual({ ok: b.ok, via: b.via, sha: b.row.sha, differs: b.differs },
      { ok: true, via: "ancestor", sha: tested, differs: [".ai/TASKS.md"] });
    const c = certifyingRunFor(db, d, code);
    assert.equal(c.ok, false);
    assert.equal(c.row.sha, tested, "the nearest tested ancestor is reported");
    assert.deepEqual(c.differs, ["src/a.js"]);

    // A dirty PASS on the ancestor would not have counted either.
    const { db: db2, d: d2, done: done2 } = freshDb();
    try {
      const r2 = gitRepo(d2);
      const t2 = r2.commit("x", "1", "x");
      const b2 = r2.commit(".ai/y", "1", "y");
      recordCiRun(db2, base({ sha: t2, dirty: true }));
      assert.equal(certifyingRunFor(db2, d2, b2).ok, false);
    } finally { done2(); }
  } finally { done(); }
});

test("certifyingRunFor: the commit's own FAIL is not rescued by an ancestor; SKIPPED only with allowSkipped", () => {
  const { d, db, done } = freshDb();
  try {
    const { commit } = gitRepo(d);
    const tested = commit("src/a.js", "1", "code");
    const book = commit(".ai/TASKS.md", "x", "book");
    recordCiRun(db, base({ sha: tested }));
    recordCiRun(db, base({ sha: book, status: "FAIL" }));
    assert.deepEqual((({ ok, kind, via }) => ({ ok, kind, via }))(certifyingRunFor(db, d, book)),
      { ok: false, kind: "FAIL", via: "self" });

    const skipped = commit("src/b.js", "1", "hotfix");
    recordCiSkip(db, { sha: skipped, ref: "refs/heads/main", reason: "prod is down" });
    assert.equal(certifyingRunFor(db, d, skipped).ok, false);
    assert.equal(certifyingRunFor(db, d, skipped, { allowSkipped: true }).ok, true);
    assert.equal(latestCiRun(db, skipped).skip_reason, "prod is down");
    assert.throws(() => recordCiSkip(db, { sha: skipped, reason: "  " }), /skip_reason/);
  } finally { done(); }
});

test("checkCiDoneGate: adoption-off, AI_OS_CI_GATE=0, no-row, FAIL, dirty-only, PASS", () => {
  const { d, db, done } = freshDb();
  try {
    const { commit } = gitRepo(d);
    const head = commit("src/a.js", "1", "code");
    let g = checkCiDoneGate(db, d, {});
    assert.deepEqual({ ok: g.ok, active: g.active }, { ok: true, active: false }, "no rows → inactive");

    const other = "f".repeat(40);
    recordCiRun(db, base({ sha: other }));             // adopted, but nothing for HEAD
    g = checkCiDoneGate(db, d, {});
    assert.equal(g.ok, false);
    assert.equal(g.message,
      `[CI_GATE] no green local CI run for HEAD ${head.slice(0, 7)} (no run for it or for an ancestor that differs only in .ai/) — run: ai ci run (bypass: AI_OS_CI_GATE=0)`);
    assert.equal(checkCiDoneGate(db, d, { AI_OS_CI_GATE: "0" }).ok, true);

    recordCiRun(db, base({ sha: head, dirty: true }));
    assert.equal(checkCiDoneGate(db, d, {}).ok, false, "dirty-only does not certify");

    recordCiRun(db, base({ sha: head, status: "FAIL", started_at: "2026-09-17T11:00:00Z" }));
    g = checkCiDoneGate(db, d, {});
    assert.equal(g.ok, false);
    assert.match(g.message, /its run is FAIL/);

    recordCiRun(db, base({ sha: head, started_at: "2026-09-17T12:00:00Z" }));
    g = checkCiDoneGate(db, d, {});
    assert.deepEqual({ ok: g.ok, active: g.active }, { ok: true, active: true });
  } finally { done(); }
});
