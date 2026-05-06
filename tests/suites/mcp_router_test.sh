#!/usr/bin/env bash
# mcp_router_test.sh — Behavioral tests for mcp-router (E-40)
#
# Verifies progressive tool discovery and JSON-RPC proxy forwarding:
#   - tools/list advertises list_domains, activate_domain, proxy_call
#   - activate_domain rejects unknown domains
#   - proxy_call rejects when no domain is active
#   - proxy_call rejects targets outside the active domain
#   - proxy_call forwards a real call to a benign read-only target
#     (verification-mcp.verify_compliance — Safety domain) and returns its result

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/mcp-router/index.js"

echo "===== mcp_router_test.sh ====="

# ── T-ROUTER-S01: File structure ──────────────────────────────────────────────
echo ""
echo "  [T-ROUTER-S01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" test -f "${REPO_ROOT}/src/mcp/mcp-router/package.json"

assert_status 0 "package.json type=module" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const p = JSON.parse(readFileSync('${REPO_ROOT}/src/mcp/mcp-router/package.json', 'utf8'));
if (p.type !== 'module') process.exit(1);
JS

# ── T-ROUTER-S02: Tool registration (behavioral) ──────────────────────────────
echo ""
echo "  [T-ROUTER-S02] Tool declarations"

for tool in list_domains activate_domain proxy_call; do
  assert_status 0 "${tool} advertised in tools/list" \
    mcp_assert_tool_listed "$SERVER" "$tool"
done

# Required-param contracts on inputSchema
assert_status 0 "activate_domain requires 'domain'" \
  mcp_assert_tool_param_required "$SERVER" "activate_domain" "domain"

assert_status 0 "proxy_call requires 'server'" \
  mcp_assert_tool_param_required "$SERVER" "proxy_call" "server"

assert_status 0 "proxy_call requires 'tool'" \
  mcp_assert_tool_param_required "$SERVER" "proxy_call" "tool"

# ── T-ROUTER-S03: Domain registry advertised by list_domains ──────────────────
echo ""
echo "  [T-ROUTER-S03] list_domains payload"

# Helper: capture the JSON-RPC result for tools/call list_domains
LIST_RESULT="$(mcp_call_tool "$SERVER" "list_domains" '{}')"

assert_status 0 "list_domains returns at least 5 domains" \
  bash -c "
result='$(printf '%s' "$LIST_RESULT" | tr -d '\n')'
printf '%s' \"\$result\" | python3 -c \"
import json, sys
data = json.loads(sys.stdin.read() or '{}')
content = data.get('content', [])
# Find the JSON envelope (second text block)
parsed = None
for block in content:
    text = block.get('text', '')
    if text.lstrip().startswith('{'):
        try: parsed = json.loads(text); break
        except Exception: pass
if not parsed: sys.exit(1)
sys.exit(0 if len(parsed.get('domains', [])) >= 5 else 1)
\"
"

for domain in State Code Safety Intelligence Quality; do
  assert_status 0 "list_domains includes ${domain}" \
    bash -c "
printf '%s' '$(printf '%s' "$LIST_RESULT" | tr -d '\n')' | python3 -c \"
import json, sys
data = json.loads(sys.stdin.read() or '{}')
content = data.get('content', [])
names = []
for block in content:
    text = block.get('text', '')
    if text.lstrip().startswith('{'):
        try:
            parsed = json.loads(text)
            names = [d.get('name') for d in parsed.get('domains', [])]
            break
        except Exception: pass
sys.exit(0 if '${domain}' in names else 1)
\"
"
done

# ── T-ROUTER-S04: activate_domain rejects unknown domain ──────────────────────
echo ""
echo "  [T-ROUTER-S04] activate_domain validation"

BOGUS="$(mcp_call_tool "$SERVER" "activate_domain" '{"domain":"NotARealDomain"}')"
assert_contains "unknown domain rejected" "unknown domain" "$BOGUS"
assert_contains "error flagged" "isError" "$BOGUS"

VALID="$(mcp_call_tool "$SERVER" "activate_domain" '{"domain":"Safety"}')"
assert_contains "Safety domain activates" "DOMAIN_ACTIVE" "$VALID"
assert_contains "Safety domain lists safe-exec-mcp" "safe-exec-mcp" "$VALID"

# ── T-ROUTER-S05: proxy_call gates ────────────────────────────────────────────
echo ""
echo "  [T-ROUTER-S05] proxy_call gating"

# A fresh router instance has no active domain (state is per-process, not per-test).
# Each mcp_call_tool spawns a new server, so this confirms the no-domain default.
NO_DOMAIN="$(mcp_call_tool "$SERVER" "proxy_call" '{"server":"safe-exec-mcp","tool":"analyze_command","arguments":{"command":"ls"}}')"
assert_contains "proxy_call without active domain rejected" "no active domain" "$NO_DOMAIN"

# Unknown server (even when registered as a real path) is blocked when the domain
# is wrong. Activate Safety, attempt to call a State server.
WRONG_DOMAIN_SCRIPT='
import json, subprocess, sys

frames = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}},
    {"jsonrpc":"2.0","method":"notifications/initialized"},
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"activate_domain","arguments":{"domain":"Safety"}}},
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"proxy_call","arguments":{"server":"task-synchronizer-mcp","tool":"get_state","arguments":{}}}},
]
payload = "\n".join(json.dumps(f) for f in frames) + "\n"
proc = subprocess.run(
    ["node", sys.argv[1]],
    input=payload, capture_output=True, text=True, timeout=15,
)
for line in proc.stdout.splitlines():
    line = line.strip()
    if not line or not line.startswith("{"): continue
    try: msg = json.loads(line)
    except Exception: continue
    if msg.get("id") == 3:
        text = json.dumps(msg.get("result", {}))
        if "not in active domain" in text:
            sys.exit(0)
        else:
            sys.stderr.write(text + "\n")
            sys.exit(1)
sys.exit(2)
'
assert_status 0 "cross-domain proxy_call rejected" \
  python3 -c "$WRONG_DOMAIN_SCRIPT" "$SERVER"

# ── T-ROUTER-S06: proxy_call success path ─────────────────────────────────────
echo ""
echo "  [T-ROUTER-S06] proxy_call forwarding"

# Activate Safety, then forward to verification-mcp.verify_compliance — a
# read-only call that exists in the Safety domain... actually verification-mcp
# is in Safety per registry. Use it because it doesn't mutate state.
PROXY_SCRIPT='
import json, subprocess, sys

frames = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}},
    {"jsonrpc":"2.0","method":"notifications/initialized"},
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"activate_domain","arguments":{"domain":"Safety"}}},
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"proxy_call","arguments":{"server":"safe-exec-mcp","tool":"analyze_command","arguments":{"command":"ls -la"},"timeout_ms":15000}}},
]
payload = "\n".join(json.dumps(f) for f in frames) + "\n"
proc = subprocess.run(
    ["node", sys.argv[1]],
    input=payload, capture_output=True, text=True, timeout=20,
)
for line in proc.stdout.splitlines():
    line = line.strip()
    if not line or not line.startswith("{"): continue
    try: msg = json.loads(line)
    except Exception: continue
    if msg.get("id") == 3:
        result = msg.get("result", {})
        text_blocks = result.get("content", [])
        joined = " ".join(b.get("text","") for b in text_blocks)
        if "ROUTER_PROXY" in joined and "safe-exec-mcp" in joined:
            sys.exit(0)
        else:
            sys.stderr.write(joined + "\n")
            sys.exit(1)
sys.exit(2)
'
assert_status 0 "proxy_call forwards to safe-exec-mcp.analyze_command" \
  python3 -c "$PROXY_SCRIPT" "$SERVER"

# ── T-ROUTER-S07: Security — registry allow-list enforcement ──────────────────
echo ""
echo "  [T-ROUTER-S07] Registry allowed-tools enforcement"

# Activate Safety, attempt to call a tool name not in safe-exec-mcp's
# registry allowed-tools (registry lists only "analyze_command").
ALLOWLIST_SCRIPT='
import json, subprocess, sys

frames = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}},
    {"jsonrpc":"2.0","method":"notifications/initialized"},
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"activate_domain","arguments":{"domain":"Safety"}}},
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"proxy_call","arguments":{"server":"safe-exec-mcp","tool":"definitely_not_a_real_tool","arguments":{}}}},
]
payload = "\n".join(json.dumps(f) for f in frames) + "\n"
proc = subprocess.run(
    ["node", sys.argv[1]],
    input=payload, capture_output=True, text=True, timeout=15,
)
for line in proc.stdout.splitlines():
    line = line.strip()
    if not line or not line.startswith("{"): continue
    try: msg = json.loads(line)
    except Exception: continue
    if msg.get("id") == 3:
        text = json.dumps(msg.get("result", {}))
        if "not in registry allowed-tools" in text:
            sys.exit(0)
        else:
            sys.stderr.write(text + "\n")
            sys.exit(1)
sys.exit(2)
'
assert_status 0 "tool not in registry allowed-tools rejected" \
  python3 -c "$ALLOWLIST_SCRIPT" "$SERVER"

# ── T-ROUTER-S08: Registry registration ───────────────────────────────────────
echo ""
echo "  [T-ROUTER-S08] Registry and template wiring"

assert_status 0 "mcp-router in src/config/registry.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['mcp-router']) process.exit(1);
JS

assert_status 0 "registry capability is EXECUTE" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const e = r.mcp_servers['mcp-router'];
if (e.capability !== 'EXECUTE') process.exit(1);
JS

assert_status 0 "registry allowed-tools lists all 3 tools" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['mcp-router']['allowed-tools'];
const expected = ['list_domains', 'activate_domain', 'proxy_call'];
if (!Array.isArray(tools) || tools.length !== expected.length) process.exit(1);
for (const t of expected) if (!tools.includes(t)) process.exit(1);
JS

assert_status 0 "mcp-router in src/templates/.mcp.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/src/templates/.mcp.json', 'utf8'));
if (!m.mcpServers['mcp-router']) process.exit(1);
const args = m.mcpServers['mcp-router'].args || [];
if (!args.some(a => a.includes('mcp-router') && a.endsWith('index.js'))) process.exit(1);
JS

# ── T-ROUTER-S09: Security invariants (source-grep — no protocol surface) ─────
echo ""
echo "  [T-ROUTER-S09] Security invariants"

# These checks have no protocol surface — they're about the implementation's
# safety boundary (no shell, no env-spread). Source-grep is the right tool.
assert_status 1 "no execSync usage" grep -q 'execSync(' "$SERVER"
assert_status 1 "no shell:true spawn" grep -qE 'shell:\s*true' "$SERVER"
assert_status 1 "no ...process.env spread (env allowlist enforced)" \
  grep -qE '\.\.\.process\.env' "$SERVER"
assert_status 0 "validateProjectRoot enforces absolute path" \
  grep -q 'isAbsolute' "$SERVER"
assert_status 0 "validateProjectRoot blocks .. traversal" \
  grep -q '"\.\."' "$SERVER"

assert_summary
