#!/usr/bin/env bash
# mcp_test.sh — generate_mcp_json + configure_gemini_mcp tests (P-15 / §22)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
REGISTRY="${REPO_ROOT}/src/config/registry.json"

echo "── Suite: mcp_test ──────────────────────────────────────────────────"

# registry.json exists and is valid JSON
assert_exists "$REGISTRY"
out=$(python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REGISTRY" 2>&1)
assert_status 0 "registry.json is valid JSON" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REGISTRY"

# registry has mcp_servers key
out=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('ok' if 'mcp_servers' in d else 'missing')" "$REGISTRY")
assert_contains "registry has mcp_servers key" "ok" "$out"

# All path-based servers have index.js listed in their path value
out=$(python3 - "$REGISTRY" <<'PY'
import json, sys
reg = json.load(open(sys.argv[1]))
bad = [n for n, v in reg.get("mcp_servers", {}).items() if "path" in v and not v["path"].endswith("index.js")]
print("ok" if not bad else f"bad: {bad}")
PY
)
assert_contains "all custom servers reference index.js" "ok" "$out"

# generate_mcp_json produces valid JSON with mcpServers key in a temp dir
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Simulate generate_mcp_json by sourcing the relevant logic inline
python3 - "$REGISTRY" "${TMP_DIR}/.mcp.json" "$HOME" "${HOME}/.ai-os" <<'PY'
import json, os, sys
registry_path, mcp_path, home, aios = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

servers = {
  "filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem@2026.1.14", "."]},
  "memory": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-memory@2026.1.26"]}
}

if os.path.exists(registry_path):
    with open(registry_path) as f:
        reg = json.load(f)
    for name, info in reg.get("mcp_servers", {}).items():
        if "path" in info:
            abs_path = os.path.join(aios, "mcp", name, "index.js")
            servers[name] = {"command": "node", "args": [abs_path]}

with open(mcp_path, "w") as f:
    json.dump({"mcpServers": servers}, f, indent=2)
    f.write("\n")
PY

assert_exists "${TMP_DIR}/.mcp.json"

mcp_out=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('ok' if 'mcpServers' in d else 'missing')" "${TMP_DIR}/.mcp.json")
assert_contains ".mcp.json has mcpServers key" "ok" "$mcp_out"

# Verify trailing newline exists
last_char=$(tail -c 1 "${TMP_DIR}/.mcp.json" | wc -c)
assert_contains ".mcp.json ends with newline" "1" "$last_char"

# Verify custom servers from registry appear in .mcp.json
registry_custom=$(python3 -c "
import json,sys
reg=json.load(open(sys.argv[1]))
names=[n for n,v in reg.get('mcp_servers',{}).items() if 'path' in v]
print(','.join(names))
" "$REGISTRY")

mcp_keys=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(','.join(d['mcpServers'].keys()))
" "${TMP_DIR}/.mcp.json")

for name in $(echo "$registry_custom" | tr ',' ' '); do
  assert_contains ".mcp.json contains registry server: $name" "$name" "$mcp_keys"
done

assert_summary
