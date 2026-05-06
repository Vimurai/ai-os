#!/usr/bin/env bash
# code_execution_mcp_test.sh — Tier 3 tests for code-execution-mcp (E-39)
#
# Verifies sandbox boundary, validation gates, and fail-closed behaviour.
# End-to-end execution test runs only when the Docker daemon is reachable;
# everywhere else the test asserts the [SANDBOX_UNAVAILABLE] error path.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/code-execution-mcp/index.js"

echo "===== code_execution_mcp_test.sh ====="

# ── T-CODEX-S01: File structure ───────────────────────────────────────────────
echo ""
echo "  [T-CODEX-S01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" \
  test -f "${REPO_ROOT}/src/mcp/code-execution-mcp/package.json"

assert_status 0 "package.json type=module" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const p = JSON.parse(readFileSync('${REPO_ROOT}/src/mcp/code-execution-mcp/package.json', 'utf8'));
if (p.type !== 'module') process.exit(1);
JS

# ── T-CODEX-S02: Tool registration (behavioral) ───────────────────────────────
echo ""
echo "  [T-CODEX-S02] Tool declarations"

assert_status 0 "execute_code advertised in tools/list" \
  mcp_assert_tool_listed "$SERVER" "execute_code"

assert_status 0 "execute_code requires 'language'" \
  mcp_assert_tool_param_required "$SERVER" "execute_code" "language"

assert_status 0 "execute_code requires 'code'" \
  mcp_assert_tool_param_required "$SERVER" "execute_code" "code"

# inputSchema must declare language enum and bounded integers
LIST_TOOLS_RESULT="$(mcp_list_tools "$SERVER")"

assert_status 0 "language enum is python+typescript only" \
  bash -c 'printf %s "$1" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or \"{}\")
tool = next((t for t in data.get(\"tools\", []) if t[\"name\"] == \"execute_code\"), None)
if not tool: sys.exit(1)
enum = (tool.get(\"inputSchema\",{}).get(\"properties\",{}).get(\"language\",{}) or {}).get(\"enum\")
sys.exit(0 if enum == [\"python\",\"typescript\"] else 1)
"' _ "$LIST_TOOLS_RESULT"

assert_status 0 "code maxLength is 16384" \
  bash -c 'printf %s "$1" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or \"{}\")
tool = next((t for t in data.get(\"tools\", []) if t[\"name\"] == \"execute_code\"), None)
if not tool: sys.exit(1)
m = (tool.get(\"inputSchema\",{}).get(\"properties\",{}).get(\"code\",{}) or {}).get(\"maxLength\")
sys.exit(0 if m == 16384 else 1)
"' _ "$LIST_TOOLS_RESULT"

assert_status 0 "timeout_ms bounded [100, 5000]" \
  bash -c 'printf %s "$1" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or \"{}\")
tool = next((t for t in data.get(\"tools\", []) if t[\"name\"] == \"execute_code\"), None)
if not tool: sys.exit(1)
prop = tool.get(\"inputSchema\",{}).get(\"properties\",{}).get(\"timeout_ms\",{}) or {}
sys.exit(0 if prop.get(\"minimum\")==100 and prop.get(\"maximum\")==5000 else 1)
"' _ "$LIST_TOOLS_RESULT"

assert_status 0 "additionalProperties:false on inputSchema" \
  bash -c 'printf %s "$1" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or \"{}\")
tool = next((t for t in data.get(\"tools\", []) if t[\"name\"] == \"execute_code\"), None)
if not tool: sys.exit(1)
sys.exit(0 if tool.get(\"inputSchema\",{}).get(\"additionalProperties\") is False else 1)
"' _ "$LIST_TOOLS_RESULT"

# ── T-CODEX-S03: Validation gates (behavioral) ────────────────────────────────
echo ""
echo "  [T-CODEX-S03] Validation gates"

BAD_LANG="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"ruby","code":"puts 1"}')"
assert_contains "ruby rejected as unsupported language" "VALIDATE_FAIL" "$BAD_LANG"
assert_contains "error reported" "unsupported language" "$BAD_LANG"

EMPTY_CODE="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"python","code":""}')"
assert_contains "empty code rejected" "VALIDATE_FAIL" "$EMPTY_CODE"

# Construct an over-length payload (16385 chars) via Python and pipe through
# the JSON-RPC client. Done inline to avoid 16k literal in the bash file.
OVERSIZE_RESULT="$(python3 -c '
import json, subprocess, sys
code = "x" * 16385
frames = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}},
    {"jsonrpc":"2.0","method":"notifications/initialized"},
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"execute_code","arguments":{"language":"python","code":code}}},
]
payload = "\n".join(json.dumps(f) for f in frames) + "\n"
r = subprocess.run(["node", sys.argv[1]], input=payload, capture_output=True, text=True, timeout=15)
for line in r.stdout.splitlines():
    line = line.strip()
    if not line.startswith("{"): continue
    try: msg = json.loads(line)
    except Exception: continue
    if msg.get("id") == 2:
        print(json.dumps(msg.get("result", {})))
        sys.exit(0)
sys.exit(1)
' "$SERVER")"
assert_contains "code over 16384 rejected" "VALIDATE_FAIL" "$OVERSIZE_RESULT"
assert_contains "rejection cites length cap" "exceeds maximum length" "$OVERSIZE_RESULT"

BAD_TIMEOUT="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"python","code":"print(1)","timeout_ms":99}')"
assert_contains "timeout below minimum rejected" "VALIDATE_FAIL" "$BAD_TIMEOUT"

BAD_TIMEOUT2="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"python","code":"print(1)","timeout_ms":99999}')"
assert_contains "timeout above maximum rejected" "VALIDATE_FAIL" "$BAD_TIMEOUT2"

# ── T-CODEX-S04: Fail-closed when Docker is unavailable ───────────────────────
echo ""
echo "  [T-CODEX-S04] Fail-closed sandbox boundary"

# Force Docker to look unavailable by giving the child a PATH that lacks
# docker but still has node + which. Use a temp dir holding only those two
# binaries (symlinks). The probe must fail and the call must NOT fall back
# to bare-metal exec.
NODE_BIN="$(command -v node)"
WHICH_BIN="$(command -v which)"
NO_DOCKER_RESULT="$(NODE_BIN="$NODE_BIN" WHICH_BIN="$WHICH_BIN" SERVER_PATH="$SERVER" python3 -c '
import json, subprocess, sys, os, tempfile
fakepath = tempfile.mkdtemp(prefix="codex-no-docker-")
os.symlink(os.environ["NODE_BIN"], os.path.join(fakepath, "node"))
os.symlink(os.environ["WHICH_BIN"], os.path.join(fakepath, "which"))
frames = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}},
    {"jsonrpc":"2.0","method":"notifications/initialized"},
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"execute_code","arguments":{"language":"python","code":"print(1)"}}},
]
payload = "\n".join(json.dumps(f) for f in frames) + "\n"
env = {"PATH": fakepath, "HOME": os.environ.get("HOME","/tmp")}
r = subprocess.run([os.environ["NODE_BIN"], os.environ["SERVER_PATH"]], input=payload, capture_output=True, text=True, timeout=15, env=env)
for line in r.stdout.splitlines():
    line = line.strip()
    if not line.startswith("{"): continue
    try: msg = json.loads(line)
    except Exception: continue
    if msg.get("id") == 2:
        print(json.dumps(msg.get("result", {})))
        sys.exit(0)
sys.exit(1)
')"
assert_contains "Docker missing → SANDBOX_UNAVAILABLE" "SANDBOX_UNAVAILABLE" "$NO_DOCKER_RESULT"
assert_contains "no fallback execution attempted" "fail-closed" "$NO_DOCKER_RESULT"

# ── T-CODEX-S05: Security invariants (source-grep — no protocol surface) ──────
echo ""
echo "  [T-CODEX-S05] Sandbox boundary invariants"

# These are about the static implementation surface — there is no protocol
# response that proves a docker flag is set. Source-grep is the right tool.
assert_status 0 "--network=none enforced"            grep -q '\-\-network=none' "$SERVER"
assert_status 0 "--read-only enforced"               grep -q '\-\-read-only'    "$SERVER"
assert_status 0 "--memory=512m enforced"             grep -q '\-\-memory=512m'  "$SERVER"
assert_status 0 "--cpus=0.5 enforced"                grep -q '\-\-cpus=0.5'     "$SERVER"
assert_status 0 "--pids-limit=64 enforced"           grep -q '\-\-pids-limit=64' "$SERVER"
assert_status 0 "--user=65534:65534 (nobody)"        grep -q '\-\-user=65534'   "$SERVER"
assert_status 0 "--cap-drop=ALL enforced"            grep -q '\-\-cap-drop=ALL' "$SERVER"
assert_status 0 "no-new-privileges enforced"         grep -q 'no-new-privileges' "$SERVER"
assert_status 0 "tmpfs /tmp size-capped"             grep -q '\-\-tmpfs=/tmp'   "$SERVER"
assert_status 0 "tmpfs marked noexec"                grep -q 'noexec'           "$SERVER"

# Anti-patterns must NOT appear.
assert_status 1 "no -v / volume mounts"              grep -qE '"-v"|"--volume"' "$SERVER"
assert_status 1 "no --privileged"                    grep -q '\-\-privileged'   "$SERVER"
assert_status 1 "no host networking"                 grep -q 'network=host'     "$SERVER"
assert_status 1 "no --device"                        grep -q '\-\-device'       "$SERVER"
assert_status 1 "no docker.sock leak"                grep -q 'docker\.sock'     "$SERVER"
assert_status 1 "no execSync"                        grep -q 'execSync('        "$SERVER"
assert_status 1 "no shell:true spawn"                grep -qE 'shell:\s*true'   "$SERVER"
assert_status 1 "no ...process.env spread"           grep -qE '\.\.\.process\.env' "$SERVER"

# Output cap must be enforced.
assert_status 0 "OUTPUT_CAP constant defined"        grep -q 'OUTPUT_CAP'       "$SERVER"
assert_status 0 "capOutput function present"         grep -q 'function capOutput' "$SERVER"
assert_status 0 "TRUNCATED marker emitted"           grep -q 'TRUNCATED'        "$SERVER"

# Wall-clock timeout enforcement.
assert_status 0 "SIGKILL on timeout"                 grep -q 'SIGKILL'          "$SERVER"

# ── T-CODEX-S06: Registry registration ────────────────────────────────────────
echo ""
echo "  [T-CODEX-S06] Registry and template wiring"

assert_status 0 "code-execution-mcp in src/config/registry.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['code-execution-mcp']) process.exit(1);
JS

assert_status 0 "registry capability is EXECUTE" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (r.mcp_servers['code-execution-mcp'].capability !== 'EXECUTE') process.exit(1);
JS

assert_status 0 "registry allowed-tools is ['execute_code']" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const t = r.mcp_servers['code-execution-mcp']['allowed-tools'];
if (!Array.isArray(t) || t.length !== 1 || t[0] !== 'execute_code') process.exit(1);
JS

# src/templates/.mcp.json is gitignored (regenerated locally by `ai sync`).
# Skip the template assertion when the file is absent — CI/clones never have it.
if [[ -f "${REPO_ROOT}/src/templates/.mcp.json" ]]; then
  assert_status 0 "code-execution-mcp in src/templates/.mcp.json" \
    node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/src/templates/.mcp.json', 'utf8'));
const e = m.mcpServers['code-execution-mcp'];
if (!e || !(e.args || []).some(a => a.includes('code-execution-mcp') && a.endsWith('index.js'))) process.exit(1);
JS
else
  echo "  ⚠  src/templates/.mcp.json absent (gitignored) — skipping template wiring check"
fi

# ── T-CODEX-S07: End-to-end (gated on Docker daemon) ──────────────────────────
echo ""
echo "  [T-CODEX-S07] End-to-end (only when Docker daemon is reachable)"

if docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
  E2E_RESULT="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"python","code":"print(2+3)","timeout_ms":5000}')"
  assert_contains "python prints 5"             "5"        "$E2E_RESULT"
  assert_contains "exit_code=0 on success"      "EXECUTED" "$E2E_RESULT"

  TIMEOUT_RESULT="$(mcp_call_tool "$SERVER" "execute_code" '{"language":"python","code":"import time; time.sleep(10)","timeout_ms":500}')"
  assert_contains "long-running call timed out" "TIMED_OUT" "$TIMEOUT_RESULT"
else
  echo "  ⚠  Docker daemon unreachable — skipping end-to-end execution tests"
fi

assert_summary
