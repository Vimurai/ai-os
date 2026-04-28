#!/usr/bin/env bash
# tests/lib/mcp-client.sh — Behavioral MCP client for stdio JSON-RPC roundtrips.
#
# Replaces string-search assertions (E-27). Spawns a server, exchanges the
# minimum JSON-RPC frames required to reach `tools/list` or `tools/call`,
# and writes each response to stdout as a single JSON line.
#
# Requires: bash, node (for the helper script invoked as the server), python3
# (for json parsing). All deps are already required by the broader suite.
#
# Public functions:
#   mcp_list_tools  <server.js>                      → JSON: { tools: [...] }
#   mcp_call_tool   <server.js> <tool> <args_json>   → JSON: tool result
#
# Exit code 0 on success, non-zero on protocol or transport failure. The
# stdout payload is always a single JSON object (or "{}" on failure).

_mcp_send() {
  # $1 = server path, $2 = method, $3 = args JSON ("" → no arguments)
  local server="$1" method="$2" args="${3:-}"
  python3 - "$server" "$method" "$args" <<'PY'
import json, subprocess, sys, time

server, method, args_raw = sys.argv[1], sys.argv[2], sys.argv[3]

initialize = {
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "mcp-client.sh", "version": "1.0"},
    },
}
initialized = {"jsonrpc": "2.0", "method": "notifications/initialized"}

if method == "tools/list":
    call = {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
elif method == "tools/call":
    name, _, rest = args_raw.partition(":")
    arguments = json.loads(rest) if rest.strip() else {}
    call = {
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    }
else:
    print("{}"); sys.exit(2)

frames = "\n".join(json.dumps(m) for m in (initialize, initialized, call)) + "\n"

proc = subprocess.Popen(
    ["node", server],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    text=True,
)
try:
    stdout, _ = proc.communicate(frames, timeout=10)
except subprocess.TimeoutExpired:
    proc.kill(); print("{}"); sys.exit(3)

# Find the response with id == 2
for line in stdout.splitlines():
    line = line.strip()
    if not line or not line.startswith("{"):
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("id") == 2:
        print(json.dumps(obj.get("result", {})))
        sys.exit(0)

print("{}"); sys.exit(4)
PY
}

mcp_list_tools() {
  _mcp_send "$1" "tools/list" ""
}

mcp_call_tool() {
  # $1=server.js  $2=tool_name  $3=args_json
  _mcp_send "$1" "tools/call" "$2:$3"
}

# Convenience: assert that a tool is listed by name. Exit 0 if present, 1 if not.
mcp_assert_tool_listed() {
  # $1=server.js  $2=tool_name
  # Pipes JSON through stdin and passes the tool name via env so embedded
  # quotes/newlines in rich tool descriptions (vibe-check-mcp) cannot break
  # the Python parse — fixes the inline-string-literal corruption mode.
  local result
  result=$(mcp_list_tools "$1")
  printf '%s' "$result" | TOOL="$2" python3 -c "
import json, os, sys
raw = sys.stdin.read() or '{}'
try:
    data = json.loads(raw)
except Exception:
    sys.exit(2)
names = [t.get('name') for t in data.get('tools', [])]
sys.exit(0 if os.environ.get('TOOL') in names else 1)
"
}
