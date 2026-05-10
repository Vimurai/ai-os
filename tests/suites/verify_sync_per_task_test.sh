#!/usr/bin/env bash
# verify_sync_per_task_test.sh — Behavioral tests for E-60.
#
# Verifies that mcp__task-synchronizer-mcp__verify_markdown_sync detects
# the four per-task drift classes named in blueprint state-sync-validation.md:
#
#   1. id in TASKS.md but missing from state.sqlite
#   2. id checkbox [x] in TASKS.md but status != DONE in state
#   3. id checkbox [ ] in TASKS.md but status == DONE in state
#   4. id in state but missing from TASKS.md
#
# Each case spawns the real MCP server via stdio JSON-RPC (no inline
# reimplementation) so the test fails if the algorithm drifts from spec.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "===== verify_sync_per_task_test.sh ====="

# ── Helper: seed an SBOX with .ai/state.sqlite + TASKS.md, then invoke
#    verify_markdown_sync from inside the SBOX (MCP resolves aiDir via cwd).
#    Args: $1 = absolute path to seed.js (writes state.sqlite + TASKS.md)
#    Stdout: the text body of the MCP response (single line, joined with \n).
_run_verify_in_sbox() {
  local seed_script="$1"
  local SBOX
  SBOX="$(mktemp -d)"
  mkdir -p "${SBOX}/.ai"
  AIDIR="${SBOX}/.ai" REPO_ROOT="${REPO_ROOT}" node --no-warnings "$seed_script" 2>/dev/null
  (
    cd "$SBOX"
    mcp_call_tool "$SYNC_MCP" "verify_markdown_sync" "{}"
  ) | python3 -c "
import json, sys
raw = sys.stdin.read() or '{}'
try:
    data = json.loads(raw)
except Exception:
    print(''); sys.exit(0)
content = data.get('content') or []
text = '\n'.join(c.get('text','') for c in content if c.get('type') == 'text')
print(text)
"
  rm -rf "$SBOX"
}

# ── T-VS-S01: clean state — no anomalies ──────────────────────────────────
echo ""
echo "  [T-VS-S01] Clean state passes"

CLEAN_SEED="$(mktemp).mjs"
cat > "$CLEAN_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-1","Engineer (Claude)","OPEN",1,"task one",now,null,null);
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-2","Engineer (Claude)","DONE",2,"task two",now,now,"shipped");
regenerateViews(aiDir, db);
JS
OUT="$(_run_verify_in_sbox "$CLEAN_SEED")"
rm -f "$CLEAN_SEED"
assert_status 0 "T-VS-S01a: emits [SYNC_PASS]" \
  grep -qE '\[SYNC_PASS\]' <<<"$OUT"
assert_status 0 "T-VS-S01b: __SYNC_RESULT__ JSON tail status=PASS" \
  grep -qE '__SYNC_RESULT__ \{"status":"PASS"' <<<"$OUT"

# ── T-VS-S02: drift 1 — id in TASKS.md but missing from state ────────────
echo ""
echo "  [T-VS-S02] Drift 1 — id in TASKS.md but missing from state"

DRIFT1_SEED="$(mktemp).mjs"
cat > "$DRIFT1_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { writeFileSync } = await import("fs");
const { resolve }       = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-1","Engineer (Claude)","OPEN",1,"task one",now,null,null);
regenerateViews(aiDir, db);
// Append a phantom row to TASKS.md that doesn't exist in state.
const tp = resolve(aiDir, "TASKS.md");
const cur = (await import("fs")).readFileSync(tp, "utf8");
writeFileSync(tp, cur + "- [x] E-99: phantom task | Tier: 1\n");
JS
OUT="$(_run_verify_in_sbox "$DRIFT1_SEED")"
rm -f "$DRIFT1_SEED"
assert_status 0 "T-VS-S02a: emits [SYNC_FAIL]" \
  grep -qE '\[SYNC_FAIL\]' <<<"$OUT"
assert_status 0 "T-VS-S02b: anomaly names E-99 + missing-from-state" \
  grep -qE 'E-99.*missing from state' <<<"$OUT"
assert_status 0 "T-VS-S02c: auto-fix regenerates TASKS.md" \
  grep -qE 'TASKS\.md regenerated' <<<"$OUT"

# ── T-VS-S03: drift 2 — [x] in md but not DONE in state ──────────────────
echo ""
echo "  [T-VS-S03] Drift 2 — [x] in md but not DONE in state"

DRIFT2_SEED="$(mktemp).mjs"
cat > "$DRIFT2_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { readFileSync, writeFileSync } = await import("fs");
const { resolve }                     = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-3","Engineer (Claude)","OPEN",1,"forgot to mark done",now,null,null);
regenerateViews(aiDir, db);
// Hand-flip the checkbox in TASKS.md from [ ] to [x] without updating state.
const tp = resolve(aiDir, "TASKS.md");
const cur = readFileSync(tp, "utf8");
writeFileSync(tp, cur.replace("- [ ] E-3:", "- [x] E-3:"));
JS
OUT="$(_run_verify_in_sbox "$DRIFT2_SEED")"
rm -f "$DRIFT2_SEED"
assert_status 0 "T-VS-S03a: emits [SYNC_FAIL]" \
  grep -qE '\[SYNC_FAIL\]' <<<"$OUT"
assert_status 0 "T-VS-S03b: anomaly E-3 [x] but OPEN in state" \
  grep -qE 'E-3 is \[x\] in TASKS\.md but OPEN in state' <<<"$OUT"
# Drift 2 is human-decision territory — must NOT auto-regenerate.
assert_status 1 "T-VS-S03c: drift 2 does NOT trigger auto-regen" \
  grep -qE 'TASKS\.md regenerated' <<<"$OUT"

# ── T-VS-S04: drift 3 — [ ] in md but DONE in state ──────────────────────
echo ""
echo "  [T-VS-S04] Drift 3 — [ ] in md but DONE in state"

DRIFT3_SEED="$(mktemp).mjs"
cat > "$DRIFT3_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { readFileSync, writeFileSync } = await import("fs");
const { resolve }                     = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-4","Engineer (Claude)","DONE",2,"shipped already",now,now,"summary");
regenerateViews(aiDir, db);
// Force the checkbox back to [ ] without updating state.
const tp = resolve(aiDir, "TASKS.md");
const cur = readFileSync(tp, "utf8");
writeFileSync(tp, cur.replace("- [x] E-4:", "- [ ] E-4:"));
JS
OUT="$(_run_verify_in_sbox "$DRIFT3_SEED")"
rm -f "$DRIFT3_SEED"
assert_status 0 "T-VS-S04a: emits [SYNC_FAIL]" \
  grep -qE '\[SYNC_FAIL\]' <<<"$OUT"
assert_status 0 "T-VS-S04b: anomaly E-4 [ ] but DONE in state" \
  grep -qE 'E-4 is \[ \] in TASKS\.md but DONE in state' <<<"$OUT"

# ── T-VS-S05: drift 4 — id in state but missing from TASKS.md ────────────
echo ""
echo "  [T-VS-S05] Drift 4 — id in state but missing from TASKS.md"

DRIFT4_SEED="$(mktemp).mjs"
cat > "$DRIFT4_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { readFileSync, writeFileSync } = await import("fs");
const { resolve }                     = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-5","Engineer (Claude)","OPEN",1,"orphan in state",now,null,null);
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-6","Engineer (Claude)","OPEN",1,"keeper",now,null,null);
regenerateViews(aiDir, db);
// Strip E-5 from TASKS.md so state has it but markdown doesn't.
const tp = resolve(aiDir, "TASKS.md");
const cur = readFileSync(tp, "utf8");
writeFileSync(tp, cur.split("\n").filter(l => !l.includes("E-5:")).join("\n"));
JS
OUT="$(_run_verify_in_sbox "$DRIFT4_SEED")"
rm -f "$DRIFT4_SEED"
assert_status 0 "T-VS-S05a: emits [SYNC_FAIL]" \
  grep -qE '\[SYNC_FAIL\]' <<<"$OUT"
assert_status 0 "T-VS-S05b: anomaly E-5 missing from TASKS.md" \
  grep -qE 'E-5 exists in state but is missing from TASKS\.md' <<<"$OUT"
assert_status 0 "T-VS-S05c: auto-fix regenerates TASKS.md" \
  grep -qE 'TASKS\.md regenerated' <<<"$OUT"

# ── T-VS-S06: header tampering still surfaces as anomaly ─────────────────
echo ""
echo "  [T-VS-S06] Header tampering"

HEADER_SEED="$(mktemp).mjs"
cat > "$HEADER_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { readFileSync, writeFileSync } = await import("fs");
const { resolve }                     = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-7","Engineer (Claude)","OPEN",1,"header check",now,null,null);
regenerateViews(aiDir, db);
const tp = resolve(aiDir, "TASKS.md");
const cur = readFileSync(tp, "utf8");
writeFileSync(tp, cur.replace(/^# TASKS \(Generated from state\.json\)\n/, "# Hand-edited TASKS\n"));
JS
OUT="$(_run_verify_in_sbox "$HEADER_SEED")"
rm -f "$HEADER_SEED"
assert_status 0 "T-VS-S06a: header tampering surfaces as anomaly" \
  grep -qE 'TASKS\.md does not start with generated header' <<<"$OUT"

# ── T-VS-S07: structured tail JSON parses & contains anomaly array ───────
echo ""
echo "  [T-VS-S07] Structured __SYNC_RESULT__ tail"

TAIL_SEED="$(mktemp).mjs"
cat > "$TAIL_SEED" <<'JS'
const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
const { readFileSync, writeFileSync } = await import("fs");
const { resolve }                     = await import("path");
const aiDir = process.env.AIDIR;
const db = getDb(aiDir);
const now = new Date().toISOString();
db.prepare("INSERT INTO tasks(id,owner,status,tier,description,created_at,completed_at,summary) VALUES (?,?,?,?,?,?,?,?)")
  .run("E-8","Engineer (Claude)","OPEN",1,"tail check",now,null,null);
regenerateViews(aiDir, db);
const tp = resolve(aiDir, "TASKS.md");
writeFileSync(tp, readFileSync(tp, "utf8").replace("- [ ] E-8:", "- [x] E-8:"));
JS
OUT="$(_run_verify_in_sbox "$TAIL_SEED")"
rm -f "$TAIL_SEED"
TAIL_JSON="$(grep -oE '__SYNC_RESULT__ \{.*\}$' <<<"$OUT" | sed 's/^__SYNC_RESULT__ //')"
assert_status 0 "T-VS-S07a: tail line present" \
  test -n "$TAIL_JSON"
PARSED="$(printf '%s' "$TAIL_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ok = d.get('status') == 'FAIL' and isinstance(d.get('anomalies'), list) and any('E-8' in a for a in d['anomalies'])
print('ok' if ok else 'fail')
")"
assert_contains "T-VS-S07b: tail JSON status=FAIL with E-8 anomaly" "ok" "$PARSED"

echo ""
assert_summary
echo "===== verify_sync_per_task_test.sh DONE ====="
