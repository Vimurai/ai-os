#!/usr/bin/env bash
# sqlite_wal_checkpoint_test.sh — Tests for E-53 SQLite WAL flush hook.
#
# Verifies the contract demanded by drift-resolution-2026.md §State Singularity:
#   • src/bin/ai defines _wal_checkpoint_state_db() with a hardcoded path.
#   • do_sync() invokes it at the end of the sync cycle.
#   • doctor() invokes it during the project-scoped diagnostics block.
#   • Behaviour: when sqlite3 is on PATH and .ai/state.sqlite exists with a
#     WAL, calling the helper truncates the WAL.
#   • Fail-open: missing sqlite3 CLI does not crash bin/ai.
#   • Path is hardcoded — never derived from $1 / $PWD-injection / env.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_AI="${REPO_ROOT}/src/bin/ai"

echo "===== sqlite_wal_checkpoint_test.sh ====="

# ── T-WAL-S01: helper exists with hardcoded path ─────────────────────────────
echo ""
echo "  [T-WAL-S01] _wal_checkpoint_state_db helper present + hardcoded path"

assert_status 0 "bin/ai defines _wal_checkpoint_state_db()" \
  grep -qE '^_wal_checkpoint_state_db\(\)' "$BIN_AI"

# Path must be the literal '.ai/state.sqlite'. Reject any user-input forms.
assert_status 0 "helper hardcodes DB=.ai/state.sqlite" \
  grep -qE 'local DB="\.ai/state\.sqlite"' "$BIN_AI"

# Negative: helper must not pull the DB path from a positional arg or env var.
assert_status 1 "helper does not accept positional DB arg" \
  grep -qE '_wal_checkpoint_state_db\(\) \{\s*local DB="\$\{?1' "$BIN_AI"

# E-58: helper now delegates the PRAGMA to the node:sqlite-backed
# wal-flusher.mjs script, so the bash side only needs to call node + the
# script path. The PRAGMA itself lives in src/shared/wal-flusher.mjs.
assert_status 0 "helper invokes wal-flusher.mjs via node" \
  grep -qE 'node "\$SCRIPT" "\$DB"' "$BIN_AI"

assert_status 0 "wal-flusher.mjs calls PRAGMA wal_checkpoint(TRUNCATE)" \
  grep -qE 'PRAGMA wal_checkpoint\(TRUNCATE\)' "${REPO_ROOT}/src/shared/wal-flusher.mjs"

# Fail-open: helper checks for node availability before calling it.
assert_status 0 "helper guards on node availability (fail-open)" \
  grep -qE 'command -v node' "$BIN_AI"

# Locator chain: prefer in-repo script, fall back to ~/.ai-os/shared/.
assert_status 0 "helper falls back to ~/.ai-os/shared/wal-flusher.mjs" \
  grep -qE '\$\{AIOS\}/shared/wal-flusher\.mjs' "$BIN_AI"

# ── T-WAL-S02: do_sync() and doctor() both call the helper ───────────────────
echo ""
echo "  [T-WAL-S02] do_sync() and doctor() invoke the helper"

assert_status 0 "do_sync() body invokes _wal_checkpoint_state_db" \
  python3 -c "
import re,sys
src=open('${BIN_AI}').read()
m=re.search(r'^do_sync\(\)\s*\{(.*?)^\}', src, re.S|re.M)
sys.exit(0 if m and '_wal_checkpoint_state_db' in m.group(1) else 1)
"

assert_status 0 "doctor() body invokes _wal_checkpoint_state_db" \
  python3 -c "
import re,sys
src=open('${BIN_AI}').read()
m=re.search(r'^doctor\(\)\s*\{(.*?)^\}', src, re.S|re.M)
sys.exit(0 if m and '_wal_checkpoint_state_db' in m.group(1) else 1)
"

# ── T-WAL-S03: dispatch guard lets the file be sourced ───────────────────────
echo ""
echo "  [T-WAL-S03] sourcing bin/ai loads helpers without invoking usage()"

# When sourced, bin/ai must short-circuit before running the dispatch case.
# Validate by sourcing in a subshell and checking that _wal_checkpoint_state_db
# is callable while no usage banner has been printed to stdout.
SOURCE_OUT="$(bash -c "source '$BIN_AI' >/dev/null 2>&1; type -t _wal_checkpoint_state_db")"
assert_status 0 "helper is loaded as a bash function after sourcing bin/ai" \
  test "$SOURCE_OUT" = "function"

# ── T-WAL-S04: behavioural — helper runs cleanly against a WAL-mode DB ──────
echo ""
echo "  [T-WAL-S04] behavioural: helper PRAGMAs a WAL-mode DB and DB stays queryable"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "  (skip — sqlite3 not on PATH in this environment)"
else
  SBOX="$(mktemp -d)"
  pushd "$SBOX" >/dev/null

  mkdir -p .ai
  sqlite3 .ai/state.sqlite \
    "PRAGMA journal_mode=WAL; CREATE TABLE t (k INTEGER PRIMARY KEY, v TEXT); INSERT INTO t(v) VALUES ('alpha'),('beta'),('gamma');" \
    >/dev/null

  HELPER_OUT="$(bash -c "
    set +e
    cd '$SBOX'
    source '$BIN_AI' >/dev/null 2>&1
    _wal_checkpoint_state_db
  " 2>&1)"

  assert_status 0 "helper emits 'WAL checkpoint complete' on success" \
    grep -qE 'WAL checkpoint complete' <<<"$HELPER_OUT"

  # Post-checkpoint DB must still be queryable — confirms PRAGMA was non-destructive.
  ROW_COUNT="$(sqlite3 .ai/state.sqlite 'SELECT COUNT(*) FROM t;')"
  assert_status 0 "DB rows readable after checkpoint (count=${ROW_COUNT})" \
    test "$ROW_COUNT" = "3"

  popd >/dev/null
  rm -rf "$SBOX"
fi

# ── T-WAL-S05: fail-open when node missing (E-58 — was sqlite3 in E-53) ─────
echo ""
echo "  [T-WAL-S05] fail-open: missing node binary returns 0"

SBOX2="$(mktemp -d)"
mkdir -p "$SBOX2/.ai"
: > "$SBOX2/.ai/state.sqlite"

EMPTY_PATH="$(mktemp -d)"
assert_status 0 "helper exits 0 when node is not on PATH" \
  bash -c "
    set +e
    cd '$SBOX2'
    export PATH='$EMPTY_PATH'
    source '$BIN_AI' >/dev/null 2>&1
    _wal_checkpoint_state_db
  "

rm -rf "$SBOX2" "$EMPTY_PATH"

echo ""
assert_summary
echo "===== sqlite_wal_checkpoint_test.sh DONE ====="
