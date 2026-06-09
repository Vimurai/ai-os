#!/usr/bin/env bash
# memory_palace_sync_test.sh — E-145 (self-learning-arc, W5-T1): _generate_memory_palace
# is the fail-open do_sync hook that refreshes the Memory Palace candidate index via the
# API-free memory-batch-scanner. It must NEVER abort sync (missing node/scanner → exit 0),
# must honor the AI_OS_DISABLE_MEMORY_PALACE escape hatch, and must write a valid manifest
# when the scanner is present. Sources src/bin/ai (guarded) and drives the function directly.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: memory_palace_sync_test (E-145) ──────────────────────────"

# The source-guard returns early when sourced, defining helpers without dispatch.
# shellcheck disable=SC1090
source "${REPO_ROOT}/src/bin/ai" 2>/dev/null || true

assert_status 0 "E-145.S0: _generate_memory_palace defined" \
  bash -c "type -t _generate_memory_palace >/dev/null 2>&1 || (source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; type -t _generate_memory_palace >/dev/null)"

# ── T-1: disable flag → skip, exit 0, no manifest ────────────────────────────
TMP1="$(mktemp -d)"; trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}"' EXIT
( cd "$TMP1" && mkdir -p .ai
  AIOS="${REPO_ROOT}" AI_OS_DISABLE_MEMORY_PALACE=1 bash -c "source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; _generate_memory_palace" >/dev/null 2>&1 )
assert_status 1 "T-1: disable flag → no palace-index.json written" test -f "$TMP1/.ai/memory/palace-index.json"

# ── T-2: scanner present (AIOS→repo) → valid JSON manifest, exit 0 ───────────
TMP2="$(mktemp -d)"
( cd "$TMP2" && mkdir -p .ai
  AIOS="${REPO_ROOT}" bash -c "source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; _generate_memory_palace" >/dev/null 2>&1 )
rc=$?
assert_status 0 "T-2: function exits 0 with scanner present" test "$rc" -eq 0
assert_status 0 "T-2: palace-index.json written" test -f "$TMP2/.ai/memory/palace-index.json"
assert_status 0 "T-2: manifest is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('$TMP2/.ai/memory/palace-index.json','utf8'))"

# ── T-3: scanner MISSING → fail-open (exit 0, sync continues), no manifest ───
# src/bin/ai re-sets AIOS at source time, so override it INLINE on the call (after
# source) and run from a dir with no src/shared → BOTH locator candidates miss.
TMP3="$(mktemp -d)"
( cd "$TMP3" && mkdir -p .ai
  bash -c "source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; cd '$TMP3'; AIOS='$TMP3/nonexistent' _generate_memory_palace" >/dev/null 2>&1 )
assert_status 0 "T-3: missing scanner → fail-open exit 0 (sync never aborts)" test "$?" -eq 0
assert_status 1 "T-3: missing scanner → no manifest left behind" test -f "$TMP3/.ai/memory/palace-index.json"

# ── T-4: no partial/.tmp file left behind in any case ────────────────────────
assert_status 1 "T-4: no palace-index.json.tmp leaked (T-2 dir)" test -f "$TMP2/.ai/memory/palace-index.json.tmp"

# ── T-5: the do_sync call site + fail-open guards exist in source ────────────
assert_status 0 "T-5: _generate_memory_palace invoked in do_sync" \
  grep -q "_generate_memory_palace" "${REPO_ROOT}/src/bin/ai"
assert_status 0 "T-5: AI_OS_DISABLE_MEMORY_PALACE escape hatch present" \
  grep -q "AI_OS_DISABLE_MEMORY_PALACE" "${REPO_ROOT}/src/bin/ai"

# ── T-6: node MISSING → fail-open before any FS write (node check is first) ──
# PATH override is applied INLINE on the call (after source), so `command -v node`
# misses while the source itself ran with a normal PATH.
TMP6="$(mktemp -d)"
( cd "$TMP6" && mkdir -p .ai
  bash -c "source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; cd '$TMP6'; PATH=/nonexistent _generate_memory_palace" >/dev/null 2>&1 )
assert_status 0 "T-6: node missing → fail-open exit 0" test "$?" -eq 0
assert_status 1 "T-6: node missing → no manifest (returns before mkdir)" test -f "$TMP6/.ai/memory/palace-index.json"

# ── T-7: scanner present but EXITS NON-ZERO → else branch, fail-open, clean ──
TMP7="$(mktemp -d)"; mkdir -p "$TMP7/aios/shared"
printf 'process.exit(1)\n' > "$TMP7/aios/shared/memory-batch-scanner.mjs"   # runtime-failure stub
( cd "$TMP7" && mkdir -p .ai
  bash -c "source '${REPO_ROOT}/src/bin/ai' 2>/dev/null; cd '$TMP7'; AIOS='$TMP7/aios' _generate_memory_palace" >/dev/null 2>&1 )
assert_status 0 "T-7: scanner exit 1 → fail-open exit 0 (sync continues)" test "$?" -eq 0
assert_status 1 "T-7: scanner exit 1 → no manifest written" test -f "$TMP7/.ai/memory/palace-index.json"
assert_status 1 "T-7: scanner exit 1 → no .tmp left behind (rollback rm fired)" test -f "$TMP7/.ai/memory/palace-index.json.tmp"
rm -rf "$TMP6" "$TMP7" 2>/dev/null || true

assert_summary
