#!/usr/bin/env bash
# sovereignty_lock_test.sh — Tests for E-101 DONE-task mutation lock in
# task-synchronizer-mcp (sovereignty-hardening.md §Components 2).
#
# Drives the REAL MCP server over stdio against an isolated temp .ai/ so the
# behaviour under test is the shipped handler logic. Covers: the [TASK_LOCKED]
# guard on DONE tasks, the reopen:true override, the AI_OS_SOVEREIGNTY_LOCK=0
# rollback, that non-DONE mutations are unaffected, and that the task_update
# schema admits `reopen` past additionalProperties:false.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: sovereignty_lock_test (E-101) ────────────────────────────"

# Framework routing must never engage — these writes target the temp .ai/ only.
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
# Ensure the lock is in its default (enabled) state for the first cases.
unset AI_OS_SOVEREIGNTY_LOCK 2>/dev/null || true

TMP="$(mktemp -d)"
PROJECT="${TMP}/proj"
mkdir -p "${PROJECT}/.ai"
cat > "${PROJECT}/.ai/state.json" <<'JSON'
{
  "version": "1.0",
  "project": { "current_tier": null, "release_verdict": null, "focus": null },
  "tasks": [], "stamps": [], "deltas": [],
  "digest_stale": false, "digest_stale_reason": null
}
JSON
cd "${PROJECT}"   # subsequent server spawns inherit this cwd → temp .ai/

call() {
  local result
  result="$(mcp_call_tool "${SERVER}" "$1" "$2")"
  printf '%s' "${result}" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}])
print(c[0].get("text","") if c else "")'
}

# is_error <tool> <args_json> → prints "ISERROR" when the tool result is an error
is_error() {
  mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("PARSEFAIL"); sys.exit(0)
print("ISERROR" if d.get("isError") else "OK")'
}

OWNER='Engineer (Claude)'

# ── T-101.00: setup — create E-1 (OPEN), mark it DONE (OPEN→DONE allowed) ─────
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"lockme\",\"tier\":2}")
assert_contains "T-101.00: E-1 created OPEN"        "Added E-1" "$r"
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"done once\"}")
assert_contains "T-101.00: OPEN→DONE allowed"       "E-1 → DONE" "$r"

# ── T-101.01: mutating a DONE task WITHOUT reopen is blocked ──────────────────
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\"}")
assert_contains "T-101.01: TASK_LOCKED tag"         "[TASK_LOCKED]" "$r"
assert_contains "T-101.01: names the task"          "E-1" "$r"
e=$(is_error update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\"}")
assert_contains "T-101.01: returns isError:true"    "ISERROR" "$e"
# State must be unchanged — E-1 is still DONE.
state=$(call get_state "{\"status\":\"DONE\"}")
assert_contains "T-101.01: E-1 still DONE"          "E-1" "$state"

# ── T-101.02: reopen:true overrides the lock ─────────────────────────────────
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\",\"reopen\":true}")
assert_contains "T-101.02: reopen mutates DONE task" "E-1 → OPEN" "$r"
e=$(is_error update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\",\"reopen\":true}")
# E-1 is OPEN now (not DONE) so this second call is a plain non-DONE mutation.
assert_contains "T-101.02: reopen path not an error" "OK" "$e"

# ── T-101.03: non-DONE tasks are never locked (OPEN→DONE→… handled above) ─────
# E-1 is OPEN; mutate OPEN→BLOCKED with no reopen → must succeed.
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"BLOCKED\"}")
assert_contains "T-101.03: OPEN→BLOCKED not locked"  "E-1 → BLOCKED" "$r"

# ── T-101.04: AI_OS_SOVEREIGNTY_LOCK=0 disables the lock entirely ─────────────
# Put E-1 back to DONE (BLOCKED→DONE allowed), then mutate it with the env flag.
call update_task_status "{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"done again\"}" >/dev/null
export AI_OS_SOVEREIGNTY_LOCK=0
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\"}")
assert_contains "T-101.04: env rollback bypasses lock" "E-1 → OPEN" "$r"
e=$(is_error update_task_status "{\"id\":\"E-1\",\"status\":\"OPEN\"}")
assert_contains "T-101.04: no error under rollback"   "OK" "$e"
unset AI_OS_SOVEREIGNTY_LOCK

# ── T-101.05: task_update schema admits `reopen` past additionalProperties ────
r=$(call validate_payload "{\"schema_name\":\"task_update\",\"payload\":{\"id\":\"E-1\",\"status\":\"OPEN\",\"reopen\":true}}")
assert_contains "T-101.05: reopen:true is SCHEMA_PASS"  "SCHEMA_PASS" "$r"
r=$(call validate_payload "{\"schema_name\":\"task_update\",\"payload\":{\"id\":\"E-1\",\"status\":\"OPEN\",\"reopen\":\"yes\"}}")
assert_contains "T-101.05: reopen wrong-type SCHEMA_FAIL" "SCHEMA_FAIL" "$r"

cd "${REPO_ROOT}"
rm -rf "${TMP}"
assert_summary
