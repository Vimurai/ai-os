#!/usr/bin/env bash
# state_projector_sync_test.sh — Tests for E-73 State Projector + debounced
# sync_to_cloud dispatcher in src/shared/managed-agents-client.mjs.
#
# Verifies the production wiring of the State Reconciliation blueprint per
# .ai/blueprints/managed-agents-state-reconciliation.md:
#   - §Components 1 (State Projector): reads OPEN+BLOCKED from .ai/state.sqlite
#   - §Components 2 (Sync Hook): non-blocking, debounced, fire-and-forget POST
#   - §Security/Data Privacy: only {id, status, owner} cross the boundary —
#     descriptions / summaries / timestamps NEVER leak to the cloud
#   - §Execution Constraints: 2000ms default debounce, env override honoured
#   - §Rollback Plan: AI_MANAGED_AGENTS_ENABLE=0 falls back to pure local
#
# Strategy: drive the client module via dynamic import in throwaway Node
# scripts. Never makes a real network call — fetch is either guarded by the
# feature flag or aimed at an unresolvable host so we get a deterministic
# NETWORK_ERROR envelope.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLIENT="${REPO_ROOT}/src/shared/managed-agents-client.mjs"

# Resolve a populated on-disk state.sqlite for the "real DB" path tests
# (T-STP-S02, T-STP-S13). The repo's own .ai/state.sqlite is gitignored, so it
# is absent in CI and fresh clones — seed an equivalent temp DB in that case so
# these tests stay portable instead of depending on a dev-only working file.
REAL_DB="${REPO_ROOT}/.ai/state.sqlite"
REAL_DB_TMPDIR=""
if [[ ! -f "$REAL_DB" ]]; then
  REAL_DB_TMPDIR="$(mktemp -d)"
  REAL_DB="${REAL_DB_TMPDIR}/state.sqlite"
  node --input-type=module -e "
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync('${REAL_DB}');
    db.exec(\`
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL,
        tier INTEGER, description TEXT NOT NULL, created_at TEXT NOT NULL,
        completed_at TEXT, summary TEXT
      );
      INSERT INTO tasks VALUES ('E-1','Engineer (Claude)','OPEN',2,'seed open','2026-01-01',NULL,NULL);
      INSERT INTO tasks VALUES ('E-2','Engineer (Claude)','DONE',2,'seed done','2026-01-01','2026-01-02','done');
    \`);
    db.close();
  "
fi

echo "===== state_projector_sync_test.sh ====="

# ── T-STP-S01: Source carries the new exports + blueprint constants ──────────
echo ""
echo "  [T-STP-S01] Source exports projectState, syncToCloud, cancelPendingSync"

assert_status 0 "client file exists"                  test -f "$CLIENT"
assert_status 0 "projectState exported"               grep -q 'export function projectState' "$CLIENT"
assert_status 0 "syncToCloud exported"                grep -q 'export function syncToCloud' "$CLIENT"
assert_status 0 "cancelPendingSync exported"          grep -q 'export function cancelPendingSync' "$CLIENT"
assert_status 0 "default debounce is 2000ms"          grep -q 'DEFAULT_DEBOUNCE_MS = 2_000' "$CLIENT"
assert_status 0 "projection endpoint pinned"          grep -q "PROJECTION_PATH = \"/v1/managed-agents/state/projection\"" "$CLIENT"
assert_status 0 "blueprint reference in comments"     grep -q "managed-agents-state-reconciliation.md" "$CLIENT"
assert_status 0 "node:sqlite imported"                grep -q 'from "node:sqlite"' "$CLIENT"
assert_status 0 "node:crypto imported"                grep -q 'from "node:crypto"' "$CLIENT"

# ── T-STP-S02: projectState reads real state.sqlite → OK + shape ─────────────
echo ""
echo "  [T-STP-S02] projectState returns Cloud Projection Payload from real DB"

out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const r = m.projectState({ dbPath: '${REAL_DB}' });
  console.log(JSON.stringify(r));
" 2>/dev/null)"

assert_status 0 "status=OK"                           bash -c "echo '$out' | grep -q '\"status\":\"OK\"'"
assert_status 0 "payload has local_timestamp"         bash -c "echo '$out' | grep -q '\"local_timestamp\":\"20'"
assert_status 0 "payload has state_hash (64 hex)"     bash -c "echo '$out' | grep -qE '\"state_hash\":\"[0-9a-f]{64}\"'"
assert_status 0 "payload has active_tasks array"      bash -c "echo '$out' | grep -q '\"active_tasks\":\\['"
# T-STP-S03 covers entry shape against a controlled SBOX DB — the real
# repo's active_tasks set is intentionally not asserted here because IDs
# come and go as tasks transition OPEN ↔ DONE.

# ── T-STP-S03: Only OPEN+BLOCKED rows surface; DONE excluded ─────────────────
echo ""
echo "  [T-STP-S03] DONE rows are filtered out of the projection"

SBOX="$(mktemp -d)"
trap 'rm -rf "$SBOX" "$REAL_DB_TMPDIR"' EXIT
SBOX_DB="${SBOX}/state.sqlite"

node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX_DB}');
  db.exec(\`
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL,
      tier INTEGER, description TEXT NOT NULL, created_at TEXT NOT NULL,
      completed_at TEXT, summary TEXT
    );
    INSERT INTO tasks VALUES ('E-100','Engineer (Claude)','OPEN',2,'open desc','2026-01-01',NULL,NULL);
    INSERT INTO tasks VALUES ('E-101','Engineer (Claude)','BLOCKED',2,'blocked desc','2026-01-01',NULL,NULL);
    INSERT INTO tasks VALUES ('E-102','Engineer (Claude)','DONE',2,'done desc','2026-01-01','2026-01-02','done sum');
    INSERT INTO tasks VALUES ('P-99','Architect (Gemini)','OPEN',1,'planner desc','2026-01-01',NULL,NULL);
  \`);
  db.close();
"

out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const r = m.projectState({ dbPath: '${SBOX_DB}' });
  console.log(JSON.stringify(r.payload.active_tasks));
" 2>/dev/null)"

assert_status 0 "E-100 (OPEN) present"                bash -c "echo '$out' | grep -q '\"id\":\"E-100\"'"
assert_status 0 "E-101 (BLOCKED) present"             bash -c "echo '$out' | grep -q '\"id\":\"E-101\"'"
assert_status 0 "P-99 (OPEN) present"                 bash -c "echo '$out' | grep -q '\"id\":\"P-99\"'"
assert_status 1 "E-102 (DONE) NOT present"            bash -c "echo '$out' | grep -q '\"id\":\"E-102\"'"
assert_status 0 "owner normalised: Engineer"          bash -c "echo '$out' | grep -q '\"owner\":\"Engineer\"'"
assert_status 0 "owner normalised: Architect"         bash -c "echo '$out' | grep -q '\"owner\":\"Architect\"'"
assert_status 1 "owner long form NOT leaked"          bash -c "echo '$out' | grep -q 'Engineer (Claude)'"

# ── T-STP-S04: state_hash deterministic; changes when set changes ────────────
echo ""
echo "  [T-STP-S04] state_hash is deterministic on identical state"

twohashes="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const a = m.projectState({ dbPath: '${SBOX_DB}' });
  const b = m.projectState({ dbPath: '${SBOX_DB}' });
  console.log(a.payload.state_hash + '|' + b.payload.state_hash + '|' +
              (a.payload.local_timestamp !== b.payload.local_timestamp));
" 2>/dev/null)"

H1="${twohashes%%|*}"
REST="${twohashes#*|}"
H2="${REST%%|*}"
TSDIFF="${twohashes##*|}"

assert_status 0 "two reads → identical state_hash" bash -c "[[ '$H1' == '$H2' ]]"
# Timestamps usually differ across two calls; we tolerate either outcome but
# assert the bool was a real boolean (not undefined / not blank).
assert_status 0 "timestamp boolean is well-formed"  bash -c "[[ '$TSDIFF' == 'true' || '$TSDIFF' == 'false' ]]"

# Mutate the SBOX DB and confirm the hash moves.
node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX_DB}');
  db.exec(\"UPDATE tasks SET status='DONE', completed_at='2026-01-03' WHERE id='E-100';\");
  db.close();
"
H3="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  console.log(m.projectState({ dbPath: '${SBOX_DB}' }).payload.state_hash);
" 2>/dev/null)"
assert_status 1 "hash changes after task transitions OPEN→DONE" bash -c "[[ '$H1' == '$H3' ]]"

# ── T-STP-S05: Privacy — description/summary/created_at NEVER leaked ─────────
echo ""
echo "  [T-STP-S05] Cloud projection strips description/summary/timestamps"

# Rebuild the SBOX DB with sensitive-looking text so a leak would be obvious.
rm -f "$SBOX_DB"
node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX_DB}');
  db.exec(\`
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL,
      tier INTEGER, description TEXT NOT NULL, created_at TEXT NOT NULL,
      completed_at TEXT, summary TEXT
    );
    INSERT INTO tasks VALUES ('E-200','Engineer (Claude)','OPEN',2,
      'PROPRIETARY_INTERNAL_DESCRIPTION_XYZ','2026-01-01',NULL,
      'PROPRIETARY_INTERNAL_SUMMARY_XYZ');
  \`);
  db.close();
"

out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  console.log(JSON.stringify(m.projectState({ dbPath: '${SBOX_DB}' }).payload));
" 2>/dev/null)"

assert_status 1 "description NOT in payload" bash -c "echo '$out' | grep -q 'PROPRIETARY_INTERNAL_DESCRIPTION_XYZ'"
assert_status 1 "summary NOT in payload"     bash -c "echo '$out' | grep -q 'PROPRIETARY_INTERNAL_SUMMARY_XYZ'"
assert_status 1 "created_at NOT in payload"  bash -c "echo '$out' | grep -q '\"created_at\"'"
assert_status 1 "completed_at NOT in payload" bash -c "echo '$out' | grep -q '\"completed_at\"'"
assert_status 1 "tier NOT in payload"        bash -c "echo '$out' | grep -q '\"tier\"'"

# ── T-STP-S06: Missing state.sqlite → STATE_UNAVAILABLE (graceful) ───────────
echo ""
echo "  [T-STP-S06] projectState surfaces STATE_UNAVAILABLE when DB missing"

out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  console.log(JSON.stringify(m.projectState({ dbPath: '${SBOX}/no-such.sqlite' })));
" 2>/dev/null)"
assert_status 0 "status=STATE_UNAVAILABLE"     bash -c "echo '$out' | grep -q '\"status\":\"STATE_UNAVAILABLE\"'"
assert_status 0 "reason mentions not found"    bash -c "echo '$out' | grep -q 'not found'"

# ── T-STP-S07: syncToCloud fail-closed when feature flag OFF ─────────────────
echo ""
echo "  [T-STP-S07] syncToCloud returns DISABLED when flag off"

result="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const r = m.syncToCloud({ dbPath: '${SBOX_DB}' }, {});
  console.log(r.status);
" 2>/dev/null)"
assert_status 0 "flag absent → DISABLED" bash -c "[[ '$result' == 'DISABLED' ]]"

result="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const r = m.syncToCloud({ dbPath: '${SBOX_DB}' },
    { AI_MANAGED_AGENTS_ENABLE: '0', AI_MANAGED_AGENT_KEY: 'abcdef0123456789' });
  console.log(r.status);
" 2>/dev/null)"
assert_status 0 "flag=0 with key → still DISABLED" bash -c "[[ '$result' == 'DISABLED' ]]"

# ── T-STP-S08: syncToCloud returns MISSING_KEY when key absent/bad ───────────
echo ""
echo "  [T-STP-S08] syncToCloud refuses absent/malformed key"

for case_label in absent short bad_charset; do
  case "$case_label" in
    absent)       envjs="{ AI_MANAGED_AGENTS_ENABLE: '1' }" ;;
    short)        envjs="{ AI_MANAGED_AGENTS_ENABLE: '1', AI_MANAGED_AGENT_KEY: 'tooshort' }" ;;
    bad_charset)  envjs="{ AI_MANAGED_AGENTS_ENABLE: '1', AI_MANAGED_AGENT_KEY: 'has spaces and !!' }" ;;
  esac
  result="$(node --input-type=module -e "
    const m = await import('file://${CLIENT}');
    const r = m.syncToCloud({ dbPath: '${SBOX_DB}' }, ${envjs});
    console.log(r.status);
  " 2>/dev/null)"
  assert_status 0 "key=${case_label} → MISSING_KEY" bash -c "[[ '$result' == 'MISSING_KEY' ]]"
done

# ── T-STP-S09: syncToCloud surfaces STATE_UNAVAILABLE when DB missing ────────
echo ""
echo "  [T-STP-S09] syncToCloud short-circuits on missing state.sqlite"

result="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const env = { AI_MANAGED_AGENTS_ENABLE: '1', AI_MANAGED_AGENT_KEY: 'abcdef0123456789' };
  const r = m.syncToCloud({ dbPath: '${SBOX}/no-such.sqlite' }, env);
  console.log(r.status);
" 2>/dev/null)"
assert_status 0 "missing DB → STATE_UNAVAILABLE" bash -c "[[ '$result' == 'STATE_UNAVAILABLE' ]]"

# ── T-STP-S10: Debouncer — rapid calls coalesce; cancelPendingSync clears ────
echo ""
echo "  [T-STP-S10] Rapid syncToCloud calls coalesce into a single pending timer"

result="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const env = {
    AI_MANAGED_AGENTS_ENABLE: '1',
    AI_MANAGED_AGENT_KEY: 'abcdef0123456789',
    AI_MANAGED_AGENTS_DEBOUNCE_MS: '50',
  };
  const r1 = m.syncToCloud({ dbPath: '${SBOX_DB}' }, env);
  const r2 = m.syncToCloud({ dbPath: '${SBOX_DB}' }, env);
  const r3 = m.syncToCloud({ dbPath: '${SBOX_DB}' }, env);
  const cleared = m.cancelPendingSync();
  const clearedTwice = m.cancelPendingSync();
  console.log(JSON.stringify({
    s1: r1.status, dbm1: r1.debounce_ms,
    s2: r2.status, s3: r3.status,
    cleared, clearedTwice,
  }));
" 2>/dev/null)"
assert_status 0 "first call DEBOUNCED"          bash -c "echo '$result' | grep -q '\"s1\":\"DEBOUNCED\"'"
assert_status 0 "second call DEBOUNCED"         bash -c "echo '$result' | grep -q '\"s2\":\"DEBOUNCED\"'"
assert_status 0 "third call DEBOUNCED"          bash -c "echo '$result' | grep -q '\"s3\":\"DEBOUNCED\"'"
assert_status 0 "env override honoured (50ms)"  bash -c "echo '$result' | grep -q '\"dbm1\":50'"
assert_status 0 "cancelPendingSync clears once" bash -c "echo '$result' | grep -q '\"cleared\":true'"
assert_status 0 "second cancel is a no-op"      bash -c "echo '$result' | grep -q '\"clearedTwice\":false'"

# ── T-STP-S11: End-to-end — debounce fires; fetch logs to stderr ─────────────
echo ""
echo "  [T-STP-S11] After debounce window, fetch fires and logs structured warn"

stderr_out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  const env = {
    AI_MANAGED_AGENTS_ENABLE: '1',
    AI_MANAGED_AGENT_KEY: 'abcdef0123456789',
    AI_MANAGED_AGENT_HOST: 'unresolvable.invalid-tld-for-test.local',
    AI_MANAGED_AGENTS_DEBOUNCE_MS: '20',
  };
  m.syncToCloud({ dbPath: '${SBOX_DB}' }, env);
  // Allow the debounce window + the (instant) ENOTFOUND rejection to land.
  await new Promise(r => setTimeout(r, 600));
" 2>&1 >/dev/null)"

assert_status 0 "stderr carries projection-fetch-failed warn" \
  bash -c "echo '$stderr_out' | grep -q 'projection fetch failed'"
assert_status 0 "log line is structured JSON (carries timestamp)" \
  bash -c "echo '$stderr_out' | grep -q '\"timestamp\":'"
assert_status 0 "service tag is managed-agents-client" \
  bash -c "echo '$stderr_out' | grep -q '\"service\":\"managed-agents-client\"'"
assert_status 1 "key value is NOT logged" \
  bash -c "echo '$stderr_out' | grep -q 'abcdef0123456789'"

# ── T-STP-S12: Owner normalisation covers all known long forms ───────────────
echo ""
echo "  [T-STP-S12] normaliseOwner short-circuits Engineer/Architect/Tester"

# Rebuild SBOX DB with one row per owner role.
rm -f "$SBOX_DB"
node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX_DB}');
  db.exec(\`
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL,
      tier INTEGER, description TEXT NOT NULL, created_at TEXT NOT NULL,
      completed_at TEXT, summary TEXT
    );
    INSERT INTO tasks VALUES ('X-1','Engineer (Claude)','OPEN',2,'d','t',NULL,NULL);
    INSERT INTO tasks VALUES ('X-2','Architect (Gemini)','OPEN',2,'d','t',NULL,NULL);
    INSERT INTO tasks VALUES ('X-3','Tester (TestSprite)','OPEN',2,'d','t',NULL,NULL);
    INSERT INTO tasks VALUES ('X-4','SomethingElse','OPEN',2,'d','t',NULL,NULL);
  \`);
  db.close();
"

out="$(node --input-type=module -e "
  const m = await import('file://${CLIENT}');
  console.log(JSON.stringify(m.projectState({ dbPath: '${SBOX_DB}' }).payload.active_tasks));
" 2>/dev/null)"
assert_status 0 "Engineer (Claude) → Engineer"        bash -c "echo '$out' | grep -q '\"id\":\"X-1\",\"status\":\"OPEN\",\"owner\":\"Engineer\"'"
assert_status 0 "Architect (Gemini) → Architect"      bash -c "echo '$out' | grep -q '\"id\":\"X-2\",\"status\":\"OPEN\",\"owner\":\"Architect\"'"
assert_status 0 "Tester (TestSprite) → Tester"        bash -c "echo '$out' | grep -q '\"id\":\"X-3\",\"status\":\"OPEN\",\"owner\":\"Tester\"'"
assert_status 0 "Unknown owner passes through"        bash -c "echo '$out' | grep -q '\"id\":\"X-4\",\"status\":\"OPEN\",\"owner\":\"SomethingElse\"'"

# ── T-STP-S13: CLI smoke — --project + --sync exit codes ─────────────────────
echo ""
echo "  [T-STP-S13] CLI flags: --project on real DB exits 0; --sync (disabled) exits 1"

# --project against a populated DB — should succeed (status OK → exit 0).
node "$CLIENT" --project "${REAL_DB}" >/dev/null 2>&1
rc_project=$?
assert_status 0 "--project on real DB exit code 0" bash -c "[[ $rc_project -eq 0 ]]"

# --sync without env → DISABLED → exit 1.
env -i PATH="$PATH" node "$CLIENT" --sync "${REAL_DB}" >/dev/null 2>&1
rc_sync=$?
assert_status 0 "--sync without env exit code 1" bash -c "[[ $rc_sync -eq 1 ]]"

# Unknown flag still prints usage with new entries.
usage_out="$(node "$CLIENT" --bogus 2>&1 >/dev/null || true)"
assert_status 0 "usage mentions --project"  bash -c "echo '$usage_out' | grep -q -- '--project'"
assert_status 0 "usage mentions --sync"     bash -c "echo '$usage_out' | grep -q -- '--sync'"

# ── T-STP-S14: ~/.ai-os mirror byte-identity ─────────────────────────────────
echo ""
echo "  [T-STP-S14] ~/.ai-os mirror matches src"

MIRROR="${HOME}/.ai-os/shared/managed-agents-client.mjs"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror is byte-identical to src" \
    diff -q "$CLIENT" "$MIRROR"
else
  echo "    ⚠  mirror absent — skipping"
fi

echo ""
assert_summary
echo "===== state_projector_sync_test.sh PASS ====="
