#!/usr/bin/env bash
# blueprints_index_test.sh — E-110 blueprint index auto-generation.
#
# Verifies _INDEX.md is generated (not hand-curated) and lists EVERY blueprint,
# resolving the omission of 20+ blueprints flagged in the gap review:
#   • scripts/generate_blueprints_index.mjs exists, deterministic, --check mode.
#   • committed .ai/blueprints/_INDEX.md is byte-identical to a fresh run (CI gate).
#   • every .ai/blueprints/*.md appears in the index.
#   • bin/ai do_sync() invokes _regenerate_blueprints_index (node-guarded, mirror fallback).
#   • generator is fail-open (missing dir → exit 0, no output file).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GEN="${REPO_ROOT}/scripts/generate_blueprints_index.mjs"
INDEX_MD="${REPO_ROOT}/.ai/blueprints/_INDEX.md"
BIN_AI="${REPO_ROOT}/src/bin/ai"

echo "===== blueprints_index_test.sh ====="

# ── T-BPI-S01: generator present + valid ─────────────────────────────────────
assert_status 0 "generator exists"     test -f "$GEN"
assert_status 0 "generator syntax OK"  node --check "$GEN"

# ── T-BPI-S02: committed _INDEX.md byte-identical to a fresh --check run ──────
TMP_OUT="$(mktemp)"
( cd "$REPO_ROOT" && node "$GEN" --check > "$TMP_OUT" 2>/dev/null )
assert_status 0 "_INDEX.md byte-identical to generator (no hand-edit)" \
  diff -q "$TMP_OUT" "$INDEX_MD"
assert_status 0 "index marked auto-generated" \
  grep -qE 'auto-generated — do NOT hand-edit' "$INDEX_MD"

# ── T-BPI-S03: EVERY blueprint appears in the index (the E-110 acceptance) ────
MISSING=0
for f in "${REPO_ROOT}"/.ai/blueprints/*.md; do
  base="$(basename "$f")"
  [[ "$base" == "_INDEX.md" ]] && continue
  if ! grep -qF "\`${base}\`" "$INDEX_MD"; then
    echo "    ✗ missing from index: ${base}"
    MISSING=$((MISSING + 1))
  fi
done
assert_status 0 "all blueprints indexed (0 omissions)" bash -c "[ $MISSING -eq 0 ]"
# And the count footer matches the on-disk blueprint count.
DISK_N="$(ls "${REPO_ROOT}"/.ai/blueprints/*.md | grep -vc '_INDEX.md')"
assert_contains "index footer reports the on-disk count" "${DISK_N} blueprints indexed" "$(cat "$INDEX_MD")"

# ── T-BPI-S04: do_sync() wires the regenerator (node-guarded, mirror fallback) ─
assert_status 0 "bin/ai defines _regenerate_blueprints_index()" \
  grep -qE '^_regenerate_blueprints_index\(\)' "$BIN_AI"
assert_status 0 "do_sync() invokes _regenerate_blueprints_index" \
  python3 -c "import re,sys; s=open('${BIN_AI}').read(); m=re.search(r'^do_sync\(\)\s*\{(.*?)^\}', s, re.S|re.M); sys.exit(0 if m and '_regenerate_blueprints_index' in m.group(1) else 1)"
assert_status 0 "helper guards on node availability" \
  grep -q 'node not found — skipping _INDEX.md' "$BIN_AI"
assert_status 0 "helper falls back to ~/.ai-os/scripts/" \
  grep -q '${AIOS}/scripts/generate_blueprints_index.mjs' "$BIN_AI"

# ── T-BPI-S05: fail-open — no .ai/blueprints → exit 0, no file written ────────
SANDBOX="$(mktemp -d)"
( cd "$SANDBOX" && node "$GEN" >/dev/null 2>&1 )
assert_status 0 "exit 0 when .ai/blueprints absent" \
  bash -c "cd '$SANDBOX' && node '$GEN' >/dev/null 2>&1"
assert_status 1 "no _INDEX.md created in a non-AI-OS dir" \
  test -f "${SANDBOX}/.ai/blueprints/_INDEX.md"
rm -rf "$SANDBOX" "$TMP_OUT"

assert_summary
