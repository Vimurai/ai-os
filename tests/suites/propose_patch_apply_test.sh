#!/usr/bin/env bash
# propose_patch_apply_test.sh — confirm_patch apply semantics (review fix)
#
# Verifies the diff/full-file classification and the dry-run+backup safety net:
#   1. Full-file content that begins with "---" (YAML front-matter) is written
#      verbatim, NOT piped to patch(1) and corrupted.
#   2. A real unified diff applies cleanly.
#   3. A unified diff that does not apply leaves the target file unchanged
#      (dry-run rejects it before any write) and returns an error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"

echo "── Suite: propose_patch_apply_test ─────────────────────────────────"

unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai"
cat > "${PROJECT}/.ai/state.json" <<'JSON'
{ "version": "1.0", "project": {}, "tasks": [], "stamps": [], "deltas": [] }
JSON
cd "${PROJECT}"

call() { mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'; }

is_error() { mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("PARSEFAIL"); sys.exit(0)
print("ISERROR" if d.get("isError") else "OK")'; }

# JSON payload builder (handles multiline diff_content safely)
payload() { P="$1" C="$2" python3 -c 'import json,os; print(json.dumps({"path":os.environ["P"],"diff_content":os.environ["C"],"description":"test"}))'; }
extract_id() { grep -oE 'ID:[[:space:]]*[A-Za-z0-9_-]+' | head -1 | sed -E 's/ID:[[:space:]]*//'; }

# ── Case 1: full-file content beginning with "---" is written verbatim ───────
printf 'old line\n' > front.md
FULL=$'---\ntitle: hello\ntags: [a, b]\n---\n# Body\nverbatim content\n'
r=$(call propose_patch "$(payload front.md "$FULL")")
PID=$(printf '%s' "$r" | extract_id)
assert_match "C1: propose returned an id" '.+' "$PID"
call confirm_patch "{\"patch_id\":\"${PID}\"}" >/dev/null
GOT="$(cat front.md)"
assert_contains "C1: YAML front-matter written verbatim (title)" "title: hello" "$GOT"
assert_contains "C1: body written verbatim"                       "verbatim content" "$GOT"
assert_not_contains "C1: not mangled by patch(1)"                 ".rej" "$GOT"
assert_status 1 "C1: no .rej reject file created" test -f front.md.rej
assert_status 1 "C1: no .orig backup left behind"  test -f front.md.orig

# ── Case 2: a real unified diff applies cleanly ──────────────────────────────
printf 'line1\nline2\nline3\n' > code.txt
printf 'line1\nLINE-2-CHANGED\nline3\n' > code.new
DIFF="$(diff -u code.txt code.new || true)"
rm -f code.new
r=$(call propose_patch "$(payload code.txt "$DIFF")")
PID=$(printf '%s' "$r" | extract_id)
e=$(is_error confirm_patch "{\"patch_id\":\"${PID}\"}")
assert_contains "C2: valid diff applies (no error)" "OK" "$e"
assert_contains "C2: change landed"                 "LINE-2-CHANGED" "$(cat code.txt)"
assert_status 1 "C2: backup cleaned up on success"  test -f code.txt.orig

# ── Case 3: a non-applying diff leaves the file untouched ────────────────────
printf 'alpha\nbeta\ngamma\n' > stale.txt
# Diff built against different content → hunk context won't match stale.txt.
printf 'WRONG1\nWRONG2\n' > base.txt
printf 'WRONG1\nWRONG2-CHANGED\n' > base.new
BADDIFF="$(diff -u base.txt base.new || true)"
rm -f base.txt base.new
BEFORE="$(cat stale.txt)"
r=$(call propose_patch "$(payload stale.txt "$BADDIFF")")
PID=$(printf '%s' "$r" | extract_id)
e=$(is_error confirm_patch "{\"patch_id\":\"${PID}\"}")
assert_contains "C3: non-applying diff returns error" "ISERROR" "$e"
assert_contains "C3: file unchanged after failed apply" "$BEFORE" "$(cat stale.txt)"
assert_status 1 "C3: no backup left behind"  test -f stale.txt.orig

cd "${REPO_ROOT}"
assert_summary
