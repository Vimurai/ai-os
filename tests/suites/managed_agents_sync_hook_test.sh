#!/usr/bin/env bash
# managed_agents_sync_hook_test.sh — Tests for E-74: Managed Agents Sync Hook
# wired into task-synchronizer-mcp's add_task + update_task_status handlers.
#
# Verifies the production wiring of the E-73 syncToCloud() dispatcher per
# .ai/blueprints/managed-agents-state-reconciliation.md §Components 2:
#
#   - The hook fires after add_task          (mutation: new row → projection change)
#   - The hook fires after update_task_status (mutation: status flip → projection change)
#   - The hook does NOT fire when AI_MANAGED_AGENTS_ENABLE is unset
#   - The hook does NOT fire from add_stamp / set_project_focus / mark_deltas_read
#     (those mutations don't change the OPEN+BLOCKED active-task set)
#   - The hook is non-blocking — JSON-RPC response returns before the
#     debounced fetch fires
#   - Framework-routed tasks sync the framework workspace's state.sqlite,
#     not the local project's
#
# Strategy: drive the real task-synchronizer-mcp via a Python harness that
# captures BOTH stdout (for the JSON-RPC response) AND stderr (where
# managed-agents-client emits structured "projection fetch failed" warns
# when a debounced sync fires against an unresolvable host). The standard
# mcp-client.sh uses stderr=DEVNULL so we cannot reuse it here.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "===== managed_agents_sync_hook_test.sh ====="

# ── Harness: spawn MCP, send one tools/call, capture stdout + stderr ─────────
# Arguments: $1=tool name, $2=args JSON, $3=wait_ms (debounce + network slack),
# $4=cwd (where MCP resolves .ai/), $5=env JSON (overrides for the child).
_call_mcp_capturing_stderr() {
  local tool="$1" args="$2" wait_ms="$3" cwd="$4" env_json="$5"
  TOOL="$tool" ARGS="$args" WAIT_MS="$wait_ms" MCP_CWD="$cwd" ENV_JSON="$env_json" \
  SYNC_MCP="$SYNC_MCP" python3 - <<'PY'
import json, os, subprocess, sys, time

server   = os.environ["SYNC_MCP"]
tool     = os.environ["TOOL"]
args_raw = os.environ["ARGS"]
wait_ms  = int(os.environ["WAIT_MS"])
cwd      = os.environ["MCP_CWD"]
extra    = json.loads(os.environ["ENV_JSON"] or "{}")

env = {**os.environ, **extra}
# Don't propagate the harness's own settings.
for k in ("TOOL", "ARGS", "WAIT_MS", "MCP_CWD", "ENV_JSON", "SYNC_MCP"):
    env.pop(k, None)
# Strip parent-shell env vars that would let the MCP write outside the
# sandbox cwd. The test's `extra` dict is re-applied after the strip so a
# test that wants AIOS_WORKSPACE / AIOS_WORKSPACE_DISABLE still gets it.
# Without this guard, a buggy test (or a failing env-builder yielding
# `{}`) would inherit the parent shell's AIOS_WORKSPACE and pollute the
# real repo's .ai/state.sqlite when is_framework_task=true.
for sensitive_key in ("AIOS_WORKSPACE", "AIOS_WORKSPACE_DISABLE"):
    env.pop(sensitive_key, None)
for k, v in extra.items():
    env[k] = v

initialize  = {"jsonrpc":"2.0","id":1,"method":"initialize",
               "params":{"protocolVersion":"2024-11-05","capabilities":{},
                         "clientInfo":{"name":"test","version":"1.0"}}}
initialized = {"jsonrpc":"2.0","method":"notifications/initialized"}
arguments   = json.loads(args_raw) if args_raw.strip() else {}
call        = {"jsonrpc":"2.0","id":2,"method":"tools/call",
               "params":{"name":tool,"arguments":arguments}}
frames      = "\n".join(json.dumps(m) for m in (initialize, initialized, call)) + "\n"

proc = subprocess.Popen(
    ["node", server],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, env=env, cwd=cwd,
)
proc.stdin.write(frames)
proc.stdin.flush()

# Sleep BEFORE closing stdin so the debounce timer + ENOTFOUND lookup land
# while the process is still alive. (The timer is unref()'d so it cannot
# keep the loop open by itself.)
time.sleep(wait_ms / 1000.0)

# Close stdin (EOF ends the server's read loop) then drain the pipes via
# wait()+read() rather than communicate(). communicate() re-touches the now-
# closed stdin (selector path calls .fileno()), which raises "ValueError: I/O
# operation on closed file" on some Python versions (e.g. the ubuntu CI runner)
# while passing on others (macOS 3.14). Output here is small JSON-RPC + a few
# stderr warns, well under the pipe buffer, so wait()-then-read() cannot deadlock.
proc.stdin.close()
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
stdout = proc.stdout.read()
stderr = proc.stderr.read()

response = None
for line in stdout.splitlines():
    line = line.strip()
    if line.startswith("{"):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("id") == 2:
            response = obj.get("result", {})
            break

print(json.dumps({"result": response, "stderr": stderr}))
PY
}

# Seed a sandbox .ai/ with a regenerated SQLite state so the MCP can open it.
_seed_aidir() {
  local aiDir="$1"
  mkdir -p "$aiDir"
  AIDIR="$aiDir" REPO_ROOT="${REPO_ROOT}" node --no-warnings -e '
    const { getDb, regenerateViews } = await import(`${process.env.REPO_ROOT}/src/mcp/shared/state-db.js`);
    const db = getDb(process.env.AIDIR);
    regenerateViews(process.env.AIDIR, db);
  ' --input-type=module 2>/dev/null
}

# ── T-MAS-S01: Source carries the hook contract ──────────────────────────────
echo ""
echo "  [T-MAS-S01] task-synchronizer-mcp imports + calls the cloud sync hook"

assert_status 0 "syncToCloud imported from shared client" \
  grep -q 'syncToCloud as _syncToCloud.*managed-agents-client.mjs' "$SYNC_MCP"
assert_status 0 "_scheduleCloudSync helper defined" \
  grep -q 'function _scheduleCloudSync' "$SYNC_MCP"
assert_status 0 "_scheduleCloudSync called from add_task" \
  bash -c "awk '/case \"add_task\":/,/case \"update_task_status\":/' '$SYNC_MCP' | grep -q '_scheduleCloudSync'"
assert_status 0 "_scheduleCloudSync called from update_task_status" \
  bash -c "awk '/case \"update_task_status\":/,/case \"add_stamp\":/' '$SYNC_MCP' | grep -q '_scheduleCloudSync'"
assert_status 1 "_scheduleCloudSync NOT called from add_stamp" \
  bash -c "awk '/case \"add_stamp\":/,/case \"set_project_focus\":/' '$SYNC_MCP' | grep -q '_scheduleCloudSync'"
assert_status 1 "_scheduleCloudSync NOT called from set_project_focus" \
  bash -c "awk '/case \"set_project_focus\":/,/case \"archive_done_tasks\":/' '$SYNC_MCP' | grep -q '_scheduleCloudSync'"
assert_status 1 "_scheduleCloudSync NOT called from mark_deltas_read" \
  bash -c "awk '/case \"mark_deltas_read\":/,/default:/' '$SYNC_MCP' | grep -q '_scheduleCloudSync'"
assert_status 0 "blueprint reference present in comments" \
  grep -q 'managed-agents-state-reconciliation.md' "$SYNC_MCP"

# Set up sandbox dirs — file-based assertions sidestep quoting traps when
# response text or stderr contain embedded newlines / JSON quotes.
SBOX="$(mktemp -d -t e74-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT

# Helper: persist the harness JSON to two files (response text + stderr) so
# subsequent assertions can grep them without fighting bash quoting rules.
_split_result() {
  # $1 = harness JSON, $2 = stdout file, $3 = stderr file
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys, pathlib
raw, out_path, err_path = sys.argv[1], sys.argv[2], sys.argv[3]
obj = json.loads(raw)
result = obj.get("result") or {}
text = "\n".join(c.get("text","") for c in (result.get("content") or []))
pathlib.Path(out_path).write_text(text)
pathlib.Path(err_path).write_text(obj.get("stderr",""))
PY
}

LOCAL_DIR="${SBOX}/local"
LOCAL_AI="${LOCAL_DIR}/.ai"
_seed_aidir "$LOCAL_AI"

# ── T-MAS-S02: Hook fires on add_task when flag is ON ────────────────────────
echo ""
echo "  [T-MAS-S02] add_task with flag ON → debounced cloud sync fires"

env_on='{"AI_MANAGED_AGENTS_ENABLE":"1","AI_MANAGED_AGENT_KEY":"abcdef0123456789","AI_MANAGED_AGENT_HOST":"unresolvable-e74-test.invalid-tld.local","AI_MANAGED_AGENTS_DEBOUNCE_MS":"30"}'

result="$(_call_mcp_capturing_stderr \
  "add_task" \
  '{"owner":"Engineer (Claude)","description":"e74 add_task test","tier":1}' \
  600 "$LOCAL_DIR" "$env_on")"

ON_OUT="${SBOX}/on.out"
ON_ERR="${SBOX}/on.err"
_split_result "$result" "$ON_OUT" "$ON_ERR"

assert_status 0 "MCP response confirms task added"          grep -q "Added " "$ON_OUT"
assert_status 0 "stderr contains projection-fetch-failed"   grep -q "projection fetch failed" "$ON_ERR"
assert_status 0 "stderr carries managed-agents-client tag"  grep -q '"service":"managed-agents-client"' "$ON_ERR"
assert_status 1 "stderr does NOT include the key value"     grep -q "abcdef0123456789" "$ON_ERR"

# ── T-MAS-S03: Hook fires on update_task_status when flag is ON ──────────────
echo ""
echo "  [T-MAS-S03] update_task_status with flag ON → cloud sync fires"

existing_id="$(grep -oE 'Added E-[0-9]+' "$ON_OUT" | head -1 | awk '{print $2}')"

if [[ -z "$existing_id" ]]; then
  echo "    ⚠  could not extract task id from T-MAS-S02 output — skipping T-MAS-S03"
else
  result="$(_call_mcp_capturing_stderr \
    "update_task_status" \
    "{\"id\":\"${existing_id}\",\"status\":\"DONE\",\"summary\":\"e74 update test\"}" \
    600 "$LOCAL_DIR" "$env_on")"
  UPD_OUT="${SBOX}/upd.out"
  UPD_ERR="${SBOX}/upd.err"
  _split_result "$result" "$UPD_OUT" "$UPD_ERR"

  assert_status 0 "MCP response confirms transition to DONE" grep -q "DONE" "$UPD_OUT"
  assert_status 0 "update_task_status triggers cloud sync"   grep -q "projection fetch failed" "$UPD_ERR"
fi

# ── T-MAS-S04: Hook stays silent when flag is OFF ────────────────────────────
echo ""
echo "  [T-MAS-S04] add_task with flag absent → no cloud sync attempt"

LOCAL_DIR_OFF="${SBOX}/local-off"
_seed_aidir "${LOCAL_DIR_OFF}/.ai"

result="$(_call_mcp_capturing_stderr \
  "add_task" \
  '{"owner":"Engineer (Claude)","description":"flag-off test","tier":1}' \
  300 "$LOCAL_DIR_OFF" '{}')"
OFF_OUT="${SBOX}/off.out"
OFF_ERR="${SBOX}/off.err"
_split_result "$result" "$OFF_OUT" "$OFF_ERR"

assert_status 0 "task still added when flag off (no network)" grep -q "Added " "$OFF_OUT"
assert_status 1 "stderr does NOT carry projection-fetch-failed" grep -q "projection fetch failed" "$OFF_ERR"
assert_status 1 "stderr does NOT carry managed-agents-client tag" grep -q '"service":"managed-agents-client"' "$OFF_ERR"

# ── T-MAS-S05: add_stamp does NOT trigger cloud sync ─────────────────────────
echo ""
echo "  [T-MAS-S05] add_stamp with flag ON → still NO projection sync (negative)"

LOCAL_DIR_STAMP="${SBOX}/local-stamp"
_seed_aidir "${LOCAL_DIR_STAMP}/.ai"

# Pre-seed a task so the stamp has a real task_id to link to (and to give
# add_task a chance to assign the id E-1 in this fresh DB).
_call_mcp_capturing_stderr \
  "add_task" \
  '{"owner":"Engineer (Claude)","description":"stamp target","tier":1}' \
  100 "$LOCAL_DIR_STAMP" '{}' >/dev/null

result="$(_call_mcp_capturing_stderr \
  "add_stamp" \
  '{"type":"ARCH_PASS","agent":"test","task_id":"E-1","summary":"e74 stamp test"}' \
  500 "$LOCAL_DIR_STAMP" "$env_on")"
STAMP_ERR="${SBOX}/stamp.err"
_split_result "$result" "${SBOX}/stamp.out" "$STAMP_ERR"

assert_status 1 "stamp mutation does NOT schedule cloud sync" \
  grep -q "projection fetch failed" "$STAMP_ERR"

# ── T-MAS-S06: Mirror byte-identity ──────────────────────────────────────────
echo ""
echo "  [T-MAS-S06] ~/.ai-os mirror matches src"

MIRROR="${HOME}/.ai-os/mcp/task-synchronizer-mcp/index.js"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror is byte-identical to src" \
    diff -q "$SYNC_MCP" "$MIRROR"
else
  echo "    ⚠  mirror absent — skipping"
fi

# ── T-MAS-S07: Framework routing — hook syncs framework workspace, not local ─
echo ""
echo "  [T-MAS-S07] is_framework_task=true → cloud sync targets the framework state.sqlite"

FRAMEWORK_DIR="${SBOX}/framework"
_seed_aidir "${FRAMEWORK_DIR}/.ai"
LOCAL_FW_DIR="${SBOX}/local-fw"
_seed_aidir "${LOCAL_FW_DIR}/.ai"

env_fw="$(FRAMEWORK_DIR="$FRAMEWORK_DIR" python3 -c '
import json, os
print(json.dumps({
  "AI_MANAGED_AGENTS_ENABLE":"1",
  "AI_MANAGED_AGENT_KEY":"abcdef0123456789",
  "AI_MANAGED_AGENT_HOST":"unresolvable-e74-fw.invalid-tld.local",
  "AI_MANAGED_AGENTS_DEBOUNCE_MS":"30",
  "AIOS_WORKSPACE": os.environ["FRAMEWORK_DIR"],
}))
')"

result="$(_call_mcp_capturing_stderr \
  "add_task" \
  '{"owner":"Engineer (Claude)","description":"e74 framework-routed test","tier":1,"is_framework_task":true}' \
  600 "$LOCAL_FW_DIR" "$env_fw")"

FW_OUT="${SBOX}/fw.out"
FW_ERR="${SBOX}/fw.err"
_split_result "$result" "$FW_OUT" "$FW_ERR"

assert_status 0 "framework-routed task lands in AIOS_WORKSPACE" \
  grep -q "routed to framework workspace" "$FW_OUT"
assert_status 0 "cloud sync still fires for framework-routed mutation" \
  grep -q "projection fetch failed" "$FW_ERR"

# Verify the row landed in the framework DB, not the local one.
fw_row_count=$(node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${FRAMEWORK_DIR}/.ai/state.sqlite');
  const rows = db.prepare(\"SELECT id FROM tasks WHERE description LIKE 'e74 framework-routed%'\").all();
  console.log(rows.length);
  db.close();
" 2>/dev/null)
local_row_count=$(node --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${LOCAL_FW_DIR}/.ai/state.sqlite');
  const rows = db.prepare(\"SELECT id FROM tasks WHERE description LIKE 'e74 framework-routed%'\").all();
  console.log(rows.length);
  db.close();
" 2>/dev/null)
assert_status 0 "framework state.sqlite has the routed row" bash -c "[[ '$fw_row_count' == '1' ]]"
assert_status 0 "local state.sqlite has NO copy of the routed row" bash -c "[[ '$local_row_count' == '0' ]]"

echo ""
assert_summary
echo "===== managed_agents_sync_hook_test.sh PASS ====="
