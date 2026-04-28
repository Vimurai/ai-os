#!/usr/bin/env bash
# tests/suites/registry_sync_test.sh — Drift guard between source-of-truth and install layer.
#
# Catches the failure class diagnosed in the 2026-04-27 audit: the project
# registry adds a new MCP, but ~/.ai-os/config/registry.json is never refreshed,
# so `ai sync` regenerates .mcp.json from a stale registry and silently drops
# the new server. Detect the divergence early so the contributor remembers to
# re-run install-ai-os.sh.

set -uo pipefail
source "$(dirname "$0")/../lib/assert.sh"

echo "===== registry_sync_test.sh ====="

LOCAL="src/config/registry.json"
GLOBAL="${HOME}/.ai-os/config/registry.json"
TEMPLATE="src/templates/.mcp.json"

assert_exists "$LOCAL"

# 1. Local registry must parse and contain mcp_servers.
assert_status 0 "local registry parses as JSON" \
  bash -c "python3 -c 'import json,sys; sys.exit(0 if json.load(open(\"$LOCAL\")).get(\"mcp_servers\") else 1)'"

# 2. Template .mcp.json must list every path-based MCP from the registry.
#    (Drift here breaks the python3-missing fallback path in generate_mcp_json.)
#    Template is gitignored (regenerated locally), so skip if absent (CI/clones).
if [[ -f "$TEMPLATE" ]]; then
  assert_status 0 "template .mcp.json covers every registry MCP" \
    bash -c "python3 - <<'PY'
import json, sys
reg = json.load(open('$LOCAL')).get('mcp_servers', {})
expected = {n for n, info in reg.items() if 'path' in info}
tmpl = set(json.load(open('$TEMPLATE')).get('mcpServers', {}).keys())
missing = expected - tmpl
sys.exit(0 if not missing else (sys.stderr.write(f'missing from template: {sorted(missing)}\n') or 1))
PY"
else
  echo "  ⚠  src/templates/.mcp.json absent (gitignored, regenerated locally) — skipping template drift check"
fi

# 3. If a global install exists, every local registry MCP must be present.
if [[ -f "$GLOBAL" ]]; then
  assert_status 0 "global registry covers every local MCP (run install-ai-os.sh if this fails)" \
    bash -c "python3 - <<'PY'
import json, sys
local  = set(json.load(open('$LOCAL')).get('mcp_servers', {}).keys())
glob   = set(json.load(open('$GLOBAL')).get('mcp_servers', {}).keys())
missing = local - glob
sys.exit(0 if not missing else (sys.stderr.write(f'global registry missing: {sorted(missing)}\n') or 1))
PY"
else
  echo "  ⚠  ~/.ai-os/config/registry.json absent — skipping global drift check"
fi

# 4. Active .mcp.json (if generated) must wire every registry MCP.
if [[ -f .mcp.json ]]; then
  assert_status 0 ".mcp.json wires every path-based registry MCP" \
    bash -c "python3 - <<'PY'
import json, sys
reg = json.load(open('$LOCAL')).get('mcp_servers', {})
expected = {n for n, info in reg.items() if 'path' in info}
active   = set(json.load(open('.mcp.json')).get('mcpServers', {}).keys())
missing  = expected - active
sys.exit(0 if not missing else (sys.stderr.write(f'.mcp.json missing: {sorted(missing)} — run: ai sync\n') or 1))
PY"
fi

# 5. E-38: Sandbox env propagation. If a registry entry declares an `env`
#    block, the generated .mcp.json must carry every key/value verbatim.
#    Catches the D-002 regression where `ai sync` silently strips
#    computer-use-mcp's DISPLAY/HOME sandbox.
if [[ -f .mcp.json ]]; then
  assert_status 0 "registry env blocks propagated to .mcp.json (D-002 sandbox)" \
    bash -c "python3 - <<'PY'
import json, sys
reg = json.load(open('$LOCAL')).get('mcp_servers', {})
mcp = json.load(open('.mcp.json')).get('mcpServers', {})
errs = []
for name, info in reg.items():
    expected_env = info.get('env')
    if not isinstance(expected_env, dict) or not expected_env:
        continue
    actual_env = (mcp.get(name) or {}).get('env') or {}
    for k, v in expected_env.items():
        if actual_env.get(k) != v:
            errs.append(f'{name}.env.{k}: expected {v!r}, got {actual_env.get(k)!r}')
sys.exit(0 if not errs else (sys.stderr.write('\n'.join(errs) + '\n') or 1))
PY"
fi

assert_summary
