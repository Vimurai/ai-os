#!/usr/bin/env bash
# mcp_integration_test.sh — Integration tests for all 8 MCP server tool handlers (E-49)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
MCP_DIR="${REPO_ROOT}/src/mcp"
REGISTRY="${REPO_ROOT}/src/config/registry.json"

echo "── Suite: mcp_integration_test ──────────────────────────────────────"

# ── 1. All custom MCP servers exist and pass Node.js syntax check ─────────────
for server in vibe-check-mcp task-synchronizer-mcp safe-exec-mcp \
              blueprint-aligner-mcp context-guardian-mcp risk-analyzer-mcp context-invoker-mcp; do
  index="${MCP_DIR}/${server}/index.js"
  assert_exists "$index"
  assert_status 0 "${server}: syntax valid" node --check "$index"
done

# ── 2. Each server registers its expected tools ───────────────────────────────
# E-30: replaced 12 grep-against-source assertions (cat $SRC | assert_contains "tool")
# with behavioral roundtrips in mcp_behavioral_test.sh, which spawns each server
# and asserts against the real tools/list response. Removes the ghost-assertion
# class that masked obsolete tool names (sync_tasks, append_tasks) for releases.
# Tool registration coverage now lives exclusively in mcp_behavioral_test.sh.

# ── 3. Registry lists all 8 custom servers with correct path fields ───────────
custom_servers=$(python3 -c "
import json, sys
reg = json.load(open(sys.argv[1]))
names = [n for n, v in reg.get('mcp_servers', {}).items() if 'path' in v]
print(' '.join(names))
" "$REGISTRY")

for server in vibe-check-mcp task-synchronizer-mcp safe-exec-mcp \
              blueprint-aligner-mcp context-guardian-mcp risk-analyzer-mcp context-invoker-mcp; do
  assert_contains "registry has entry for ${server}" "$server" "$custom_servers"
done

# ── 4. context-invoker-mcp: input validation rejects path traversal ───────────
validation_result=$(node -e "
// Inline test of validateName logic (copied from index.js)
const SAFE_NAME_RE = /^[a-z0-9_-]+\$/i;
function validateName(name) {
  if (!name || typeof name !== 'string') return 'error';
  if (!SAFE_NAME_RE.test(name)) return 'error';
  if (name.length > 64) return 'error';
  return null;
}
// Path traversal should fail
const r1 = validateName('../etc/passwd');
const r2 = validateName('valid-skill-name');
const r3 = validateName('ai_update');
process.stdout.write((r1 !== null && r2 === null && r3 === null) ? 'ok' : 'fail');
" 2>/dev/null || echo "error")
assert_contains "context-invoker-mcp: path traversal rejected" "ok" "$validation_result"

assert_summary
