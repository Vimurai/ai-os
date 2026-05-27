#!/usr/bin/env bash
# dag_dependency_test.sh — Tests for E-91 DAG dependency support in
# task-synchronizer-mcp (ecc-integrations.md §Components 3).
#
# Drives the REAL MCP server over stdio against an isolated temp .ai/ so the
# behaviour under test is the shipped handler logic, not a reimplementation.
# Covers: depends_on schema, initial BLOCKED/OPEN status, cycle detection,
# self-reference, missing-dep, depth cap (5), the DONE→OPEN unblock cascade,
# and get_state readiness flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: dag_dependency_test (E-91) ───────────────────────────────"

# Framework routing must never engage — these writes target the temp .ai/ only.
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true

# Isolated project: the MCP resolves aiDir as process.cwd()/.ai (index.js:409).
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

# call <tool> <args_json> → prints the tool's text payload (content[0].text)
call() {
  local result
  result="$(mcp_call_tool "${SERVER}" "$1" "$2")"
  printf '%s' "${result}" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}])
print(c[0].get("text","") if c else "")'
}

# task_field <get_state_text> <task_id> <field> → JSON value or MISSING
task_field() {
  TID="$2" F="$3" python3 -c 'import json,sys,os
try: d=json.load(sys.stdin)
except Exception: print("ERR"); sys.exit(0)
t=next((x for x in d.get("tasks",[]) if x.get("id")==os.environ["TID"]),None)
print("MISSING" if t is None else json.dumps(t.get(os.environ["F"])))' <<<"$1"
}

OWNER='Engineer (Claude)'

# ── T-91.01: task with no deps is OPEN (backward compat) ─────────────────────
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"root\",\"tier\":2}")
assert_contains "T-91.01: E-1 created"            "Added E-1" "$r"
assert_contains "T-91.01: E-1 starts OPEN"        '"status": "OPEN"' "$r"
assert_contains "T-91.01: E-1 depends_on is []"   '"depends_on": []' "$r"

# ── T-91.02: task depending on an unfinished task starts BLOCKED ─────────────
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"needs E-1\",\"tier\":2,\"depends_on\":[\"E-1\"]}")
assert_contains "T-91.02: E-2 created"            "Added E-2" "$r"
assert_contains "T-91.02: E-2 starts BLOCKED"     '"status": "BLOCKED"' "$r"

# ── T-91.03: get_state surfaces readiness flags ──────────────────────────────
state=$(call get_state "{}")
assert_contains "T-91.03: E-1 ready=true"  "true"      "$(task_field "$state" E-1 ready)"
assert_contains "T-91.03: E-2 ready=false" "false"     "$(task_field "$state" E-2 ready)"
assert_contains "T-91.03: E-2 blocked_by=[E-1]" "E-1"  "$(task_field "$state" E-2 blocked_by)"

# ── T-91.04: completing E-1 cascades E-2 BLOCKED→OPEN ────────────────────────
r=$(call update_task_status "{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"root done\"}")
assert_contains "T-91.04: cascade unblocks E-2"   "unblocked: E-2" "$r"
state=$(call get_state "{}")
assert_contains "T-91.04: E-2 now OPEN"           '"OPEN"' "$(task_field "$state" E-2 status)"
assert_contains "T-91.04: E-2 now ready=true"     "true"   "$(task_field "$state" E-2 ready)"

# ── T-91.05: status filter reflects the cascade (no BLOCKED tasks left) ──────
r=$(call get_state "{\"status\":\"BLOCKED\"}")
assert_contains "T-91.05: zero BLOCKED tasks"     '"total_matched": 0' "$r"

# ── T-91.06: depending on a non-existent task is rejected ────────────────────
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"bad dep\",\"depends_on\":[\"E-999\"]}")
assert_contains "T-91.06: DAG_FAIL on missing dep"        "[DAG_FAIL]" "$r"
assert_contains "T-91.06: names the unknown dependency"   "Unknown dependency" "$r"

# ── T-91.07: cycle detection via dependency revision ─────────────────────────
# E-3 depends on E-2; revising E-2 to depend on E-3 closes a cycle E-2→E-3→E-2.
r=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"depends E-2\",\"tier\":2,\"depends_on\":[\"E-2\"]}")
assert_contains "T-91.07: E-3 created"            "Added E-3" "$r"
r=$(call update_task_status "{\"id\":\"E-2\",\"status\":\"OPEN\",\"depends_on\":[\"E-3\"]}")
assert_contains "T-91.07: DAG_FAIL on cycle"      "[DAG_FAIL]" "$r"
assert_contains "T-91.07: reports circular path"  "Circular dependency" "$r"

# ── T-91.08: self-reference is rejected ──────────────────────────────────────
r=$(call update_task_status "{\"id\":\"E-3\",\"status\":\"OPEN\",\"depends_on\":[\"E-3\"]}")
assert_contains "T-91.08: DAG_FAIL on self-dep"   "[DAG_FAIL]" "$r"
assert_contains "T-91.08: explains self-dep"      "cannot depend on itself" "$r"

# ── T-91.09: dependency chain deeper than 5 is rejected ──────────────────────
# Existing depths: E-1=1, E-2=2, E-3(deps E-2)=3. Extend the chain.
call add_task "{\"owner\":\"${OWNER}\",\"description\":\"d4\",\"depends_on\":[\"E-3\"]}" >/dev/null   # E-4 depth 4
r5=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"d5\",\"depends_on\":[\"E-4\"]}")          # E-5 depth 5 (ok)
r6=$(call add_task "{\"owner\":\"${OWNER}\",\"description\":\"d6\",\"depends_on\":[\"E-5\"]}")          # E-6 depth 6 (reject)
assert_contains "T-91.09: depth-5 chain allowed"  "Added E-5"  "$r5"
assert_contains "T-91.09: DAG_FAIL on depth>5"    "[DAG_FAIL]" "$r6"
assert_contains "T-91.09: reports depth"          "depth"      "$r6"

# ── T-91.10: schema accepts valid depends_on, rejects wrong type ─────────────
r=$(call validate_payload "{\"schema_name\":\"task_create\",\"payload\":{\"owner\":\"${OWNER}\",\"description\":\"x\",\"depends_on\":[\"E-1\"]}}")
assert_contains "T-91.10: valid depends_on passes" "SCHEMA_PASS" "$r"
r=$(call validate_payload "{\"schema_name\":\"task_create\",\"payload\":{\"owner\":\"${OWNER}\",\"description\":\"x\",\"depends_on\":\"E-1\"}}")
assert_contains "T-91.10: string depends_on fails" "SCHEMA_FAIL" "$r"

cd "${REPO_ROOT}"
rm -rf "${TMP}"
assert_summary
