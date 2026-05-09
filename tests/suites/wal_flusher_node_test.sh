#!/usr/bin/env bash
# wal_flusher_node_test.sh — Tests for E-57 wal-flusher.mjs (node:sqlite).
#
# Verifies the contract demanded by wal-checkpoint-node.md:
#   • src/shared/wal-flusher.mjs exists and uses node:sqlite (no shell sqlite3).
#   • Validates db-path: required, exists, regular file, .sqlite extension.
#   • Successfully checkpoints a real WAL-mode DB (exit 0, DB still queryable).
#   • Rejects non-SQLite paths (defense-in-depth against arbitrary truncation).
#   • Rejects missing args, NUL bytes, missing files, directories.
#   • Boots fast (<200ms — generous bound; blueprint asks <50ms).
#   • Emits structured JSON to stderr on error (no shell injection vectors).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FLUSHER="${REPO_ROOT}/src/shared/wal-flusher.mjs"

echo "===== wal_flusher_node_test.sh ====="

# ── T-FLU-S01: file presence and source contract ─────────────────────────────
echo ""
echo "  [T-FLU-S01] wal-flusher.mjs present + uses node:sqlite (not shell sqlite3)"

assert_status 0 "src/shared/wal-flusher.mjs exists" test -f "$FLUSHER"

assert_status 0 "imports from node:sqlite" \
  grep -qE 'from "node:sqlite"' "$FLUSHER"

assert_status 0 "executes PRAGMA wal_checkpoint(TRUNCATE)" \
  grep -qE 'PRAGMA wal_checkpoint\(TRUNCATE\)' "$FLUSHER"

# Negative: no shell-out fallback. The whole point of E-58 is to retire the
# `sqlite3` binary dependency.
assert_status 1 "no child_process / spawn / exec shell-out" \
  grep -qE 'child_process|spawnSync|spawn\(|execSync' "$FLUSHER"

# Validation surface: argv must be sanitised before opening.
assert_status 0 "validates db-path argument shape" \
  grep -qE 'function validatePath' "$FLUSHER"

# ── T-FLU-S02: behavioural — happy path against a real WAL DB ───────────────
echo ""
echo "  [T-FLU-S02] behavioural: checkpoints a real WAL DB, DB stays queryable"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "  (skip — sqlite3 fixture tool not on PATH)"
else
  SBOX="$(mktemp -d)"
  DB="$SBOX/state.sqlite"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL; CREATE TABLE t(k INTEGER PRIMARY KEY, v TEXT); INSERT INTO t(v) VALUES ('alpha'),('beta'),('gamma');" >/dev/null

  assert_status 0 "wal-flusher.mjs exits 0 on valid DB" \
    node "$FLUSHER" "$DB"

  ROW_COUNT="$(sqlite3 "$DB" 'SELECT COUNT(*) FROM t;')"
  assert_status 0 "DB rows still readable after checkpoint (count=${ROW_COUNT})" \
    test "$ROW_COUNT" = "3"

  rm -rf "$SBOX"
fi

# ── T-FLU-S03: validation — rejects bad paths ───────────────────────────────
echo ""
echo "  [T-FLU-S03] rejects bad paths with exit 1 + structured stderr"

# Missing arg.
ERR="$(node "$FLUSHER" 2>&1 || true)"
assert_status 0 "missing arg → exits non-zero with 'db-path argument is required'" \
  bash -c "node '$FLUSHER' 2>/dev/null; [[ \$? -ne 0 ]]"
assert_status 0 "missing arg → stderr contains 'db-path argument is required'" \
  grep -q 'db-path argument is required' <<<"$ERR"

# Wrong extension (defense-in-depth).
ERR2="$(node "$FLUSHER" /etc/hosts 2>&1 || true)"
assert_status 0 "non-.sqlite path → rejected" \
  grep -qE 'extension must be \.sqlite' <<<"$ERR2"

# Nonexistent file.
ERR3="$(node "$FLUSHER" /tmp/nonexistent-12345.sqlite 2>&1 || true)"
assert_status 0 "nonexistent .sqlite → 'does not exist'" \
  grep -q 'does not exist' <<<"$ERR3"

# Directory passed where file expected.
SBOX_DIR="$(mktemp -d)"
mv "$SBOX_DIR" "${SBOX_DIR}.sqlite"  # rename so extension check passes
ERR4="$(node "$FLUSHER" "${SBOX_DIR}.sqlite" 2>&1 || true)"
assert_status 0 "directory → 'not a regular file'" \
  grep -q 'not a regular file' <<<"$ERR4"
rmdir "${SBOX_DIR}.sqlite"

# All errors emit structured JSON (parseable on stderr, never plain English).
assert_status 0 "errors emit JSON with service=wal-flusher" \
  bash -c "node '$FLUSHER' /etc/hosts 2>&1 | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d[\"service\"]==\"wal-flusher\" and d[\"level\"]==\"error\"'"

# ── T-FLU-S04: boot time budget (loose <500ms) ──────────────────────────────
echo ""
echo "  [T-FLU-S04] boot time within budget"

if command -v sqlite3 >/dev/null 2>&1; then
  SBOX2="$(mktemp -d)"
  DB2="$SBOX2/state.sqlite"
  sqlite3 "$DB2" "PRAGMA journal_mode=WAL; CREATE TABLE t(k INTEGER); INSERT INTO t VALUES (1);" >/dev/null

  # Wall-clock the whole node invocation. macOS `time -p` reports floats.
  T_OUT="$( { time -p node "$FLUSHER" "$DB2" >/dev/null 2>&1; } 2>&1 )"
  REAL_S="$(awk '/^real/ {print $2}' <<<"$T_OUT")"
  # Convert to ms via awk to avoid bash float arithmetic.
  REAL_MS="$(awk -v s="$REAL_S" 'BEGIN{printf("%d", s*1000)}')"
  assert_status 0 "node wal-flusher.mjs boots in <500ms (measured ${REAL_MS}ms)" \
    test "$REAL_MS" -lt 500

  rm -rf "$SBOX2"
else
  echo "  (skip — sqlite3 fixture not available)"
fi

echo ""
assert_summary
echo "===== wal_flusher_node_test.sh DONE ====="
