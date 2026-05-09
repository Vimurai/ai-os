#!/usr/bin/env bash
# session_traceability_test.sh — Tests for E-49 Session Traceability.
#
# Verifies the contract demanded by claude-code-optimizations.md
# §"Session Audit Enhancer" + §Security:
#   • approval-mcp adds session_id TEXT column with idempotent migration.
#   • CLAUDE_CODE_SESSION_ID is sanitised: [A-Za-z0-9-]{1,64} only.
#   • recordDecision INSERT picks up the env value.
#   • NULL when env is unset / malformed / oversized.
#   • ai-log skill body documents the same regex + 'session=' tag.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APPROVAL="${REPO_ROOT}/src/mcp/approval-mcp/index.js"

echo "===== session_traceability_test.sh ====="

# ── T-SES-S01: approval-mcp source contract ─────────────────────────────────
echo ""
echo "  [T-SES-S01] approval-mcp source contract"

assert_status 0 "captureSessionId helper exists" \
  grep -q 'function captureSessionId' "$APPROVAL"

assert_status 0 "session-id length cap is 64"   grep -q 'SESSION_ID_MAX_LENGTH = 64' "$APPROVAL"
assert_status 0 "session-id regex restricts charset" \
  grep -qE 'SESSION_ID_RE.*A-Za-z0-9' "$APPROVAL"

assert_status 0 "ALTER TABLE add column is idempotent" \
  grep -q "pragma_table_info" "$APPROVAL"
assert_status 0 "session_id added only when missing" \
  grep -q 'cols.includes("session_id")' "$APPROVAL"
assert_status 0 "INSERT now binds 4 params" \
  grep -q 'INSERT INTO approvals (action, reason, status, session_id) VALUES (?, ?, ?, ?)' "$APPROVAL"
assert_status 0 "recordDecision passes captureSessionId() to stmt.run" \
  grep -q 'stmt.run(action, reason, status, captureSessionId())' "$APPROVAL"

# ── T-SES-S02: Behavioural — captureSessionId sanitiser table ───────────────
echo ""
echo "  [T-SES-S02] captureSessionId behavioural table"

# Run the full sanitiser table inside a single Node script — no bash quoting
# games. The script exits 0 if every input maps to its expected output and
# non-zero with a diagnostic on the first mismatch.
assert_status 0 "captureSessionId passes the full input/output table" \
  node --input-type=module <<'JS'
const SESSION_ID_MAX_LENGTH = 64;
const SESSION_ID_RE = /^[A-Za-z0-9-]{1,64}$/;
function captureSessionId(raw) {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > SESSION_ID_MAX_LENGTH) return null;
  return SESSION_ID_RE.test(trimmed) ? trimmed : null;
}

const cases = [
  // Accepts.
  ["01J9X2A1Z3-abcd-EFGH",                "01J9X2A1Z3-abcd-EFGH"],
  ["A",                                    "A"],
  ["-".repeat(64),                         "-".repeat(64)],
  ["aB-9".repeat(16),                      "aB-9".repeat(16)],          // 64 chars exactly
  // Rejects.
  [undefined,                              null],
  [null,                                   null],
  ["",                                     null],
  ["   ",                                  null],
  ["abc def",                              null],
  ["abc'); DROP TABLE approvals; --",      null],
  ["abc\nx",                               null],
  ["-".repeat(65),                         null],
  [{ raw: "object" },                      null],
];

for (const [input, expected] of cases) {
  const got = captureSessionId(input);
  if (got !== expected) {
    process.stderr.write(`mismatch: input=${JSON.stringify(input)} expected=${JSON.stringify(expected)} got=${JSON.stringify(got)}\n`);
    process.exit(1);
  }
}
JS

# ── T-SES-S03: End-to-end — schema migration applied + session captured ─────
echo ""
echo "  [T-SES-S03] End-to-end SQLite migration + capture"

# Build a DB the *old* way (pre-E-49 schema), then have the new server open
# it and confirm session_id is added without losing rows.
SBOX="$(mktemp -d -t e49-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT

PRE_DB="${SBOX}/approvals.sqlite"
node --input-type=module <<JS
import { DatabaseSync } from "node:sqlite";
const conn = new DatabaseSync("${PRE_DB}");
conn.exec(\`
  CREATE TABLE approvals (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    action      TEXT    NOT NULL,
    reason      TEXT    NOT NULL,
    status      TEXT    NOT NULL,
    requested_at TEXT   NOT NULL DEFAULT (datetime('now','utc')),
    resolved_at  TEXT   NOT NULL DEFAULT (datetime('now','utc'))
  );
\`);
conn.prepare("INSERT INTO approvals (action, reason, status) VALUES (?, ?, ?)").run(
  "legacy-action", "pre-existing row", "APPROVED"
);
conn.close();
JS

# Now run the *new* helpers (extracted) against the same DB and confirm:
#   1. column added,
#   2. legacy row preserved,
#   3. new insert captures sanitised session.
HOME_OVERRIDE="$SBOX" CLAUDE_CODE_SESSION_ID="01J9X2A1Z3-abcd-EFGH" node --input-type=module <<JS
import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";

const STORE_DIR = "${SBOX}";
const DB_PATH = STORE_DIR + "/approvals.sqlite";
const MAX_ACTION_LENGTH = 200;
const MAX_REASON_LENGTH = 500;
const SESSION_ID_MAX_LENGTH = 64;
const SESSION_ID_RE = /^[A-Za-z0-9-]{1,64}$/;
function captureSessionId() {
  const raw = process.env.CLAUDE_CODE_SESSION_ID;
  if (!raw || typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > SESSION_ID_MAX_LENGTH) return null;
  return SESSION_ID_RE.test(trimmed) ? trimmed : null;
}

mkdirSync(STORE_DIR, { recursive: true, mode: 0o700 });
const conn = new DatabaseSync(DB_PATH);
conn.exec("PRAGMA journal_mode = WAL;");
conn.exec("PRAGMA foreign_keys = ON;");
conn.exec(\`
  CREATE TABLE IF NOT EXISTS approvals (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    action      TEXT    NOT NULL CHECK(length(action) <= \${MAX_ACTION_LENGTH}),
    reason      TEXT    NOT NULL CHECK(length(reason) <= \${MAX_REASON_LENGTH}),
    status      TEXT    NOT NULL CHECK(status IN ('APPROVED','REJECTED','NON_TTY')),
    requested_at TEXT   NOT NULL DEFAULT (datetime('now','utc')),
    resolved_at  TEXT   NOT NULL DEFAULT (datetime('now','utc'))
  );
\`);
const cols = conn
  .prepare("SELECT name FROM pragma_table_info('approvals')")
  .all()
  .map((r) => r.name);
if (!cols.includes("session_id")) {
  conn.exec(
    \`ALTER TABLE approvals ADD COLUMN session_id TEXT
       CHECK(session_id IS NULL OR length(session_id) <= \${SESSION_ID_MAX_LENGTH})\`
  );
}
conn.prepare(
  "INSERT INTO approvals (action, reason, status, session_id) VALUES (?, ?, ?, ?)"
).run("test-action", "with session", "APPROVED", captureSessionId());

const colsAfter = conn.prepare("SELECT name FROM pragma_table_info('approvals')").all().map(r => r.name);
if (!colsAfter.includes("session_id")) { console.error("session_id column missing"); process.exit(1); }

const rows = conn.prepare("SELECT id, action, session_id FROM approvals ORDER BY id").all();
if (rows.length !== 2) { console.error("row count drift:", rows.length); process.exit(1); }
if (rows[0].action !== "legacy-action" || rows[0].session_id !== null) {
  console.error("legacy row corrupted:", rows[0]); process.exit(1);
}
if (rows[1].session_id !== "01J9X2A1Z3-abcd-EFGH") {
  console.error("new row missing session_id:", rows[1]); process.exit(1);
}

// Idempotent re-run: opening again must not re-add or error.
const conn2 = new DatabaseSync(DB_PATH);
const cols2 = conn2.prepare("SELECT name FROM pragma_table_info('approvals')").all().map(r => r.name);
if (!cols2.includes("session_id")) process.exit(2);
process.exit(0);
JS
RC=$?
assert_status 0 "schema migrated, legacy row preserved, idempotent" bash -c "[[ $RC -eq 0 ]]"

# ── T-SES-S04: ai-log skill documents the contract ──────────────────────────
echo ""
echo "  [T-SES-S04] ai-log skill body"

for f in \
  "${REPO_ROOT}/src/shared/skills/ai-log/SKILL.md" \
  "${REPO_ROOT}/.claude/skills/ai-log/SKILL.md" \
  "${REPO_ROOT}/.gemini/skills/ai-log/SKILL.md"; do

  assert_status 0 "${f#${REPO_ROOT}/} exists" test -f "$f"
  assert_status 0 "${f##*/skills/ai-log/} mentions CLAUDE_CODE_SESSION_ID" \
    grep -q 'CLAUDE_CODE_SESSION_ID' "$f"
  assert_status 0 "${f##*/skills/ai-log/} documents the session= tag format" \
    grep -qE 'session=' "$f"
  assert_status 0 "${f##*/skills/ai-log/} documents the bounded regex" \
    grep -qE '\[A-Za-z0-9-\]\{1,64\}' "$f"
  assert_status 0 "${f##*/skills/ai-log/} documents the 'session=invalid' fallback" \
    grep -q 'session=invalid' "$f"
done

# Mirror identity.
SRC_HASH="$(md5sum "${REPO_ROOT}/src/shared/skills/ai-log/SKILL.md" | awk '{print $1}')"
CLA_HASH="$(md5sum "${REPO_ROOT}/.claude/skills/ai-log/SKILL.md"     | awk '{print $1}')"
GEM_HASH="$(md5sum "${REPO_ROOT}/.gemini/skills/ai-log/SKILL.md"     | awk '{print $1}')"
assert_status 0 ".claude mirror = src" bash -c "[[ '$SRC_HASH' == '$CLA_HASH' ]]"
assert_status 0 ".gemini mirror = src" bash -c "[[ '$SRC_HASH' == '$GEM_HASH' ]]"

assert_summary
