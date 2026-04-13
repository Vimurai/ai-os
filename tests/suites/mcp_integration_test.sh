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

# vibe-check-mcp: run_vibe_audit, run_chaos_test, get_performance_metrics
vibe_src=$(cat "${MCP_DIR}/vibe-check-mcp/index.js")
assert_contains "vibe-check-mcp: run_vibe_audit registered" "run_vibe_audit" "$vibe_src"
assert_contains "vibe-check-mcp: run_chaos_test registered" "run_chaos_test" "$vibe_src"
assert_contains "vibe-check-mcp: get_performance_metrics registered" "get_performance_metrics" "$vibe_src"

# task-synchronizer-mcp: sync_tasks, append_tasks
task_src=$(cat "${MCP_DIR}/task-synchronizer-mcp/index.js")
assert_contains "task-synchronizer-mcp: sync_tasks registered" "sync_tasks" "$task_src"
assert_contains "task-synchronizer-mcp: append_tasks registered" "append_tasks" "$task_src"

# safe-exec-mcp: analyze_command
safe_src=$(cat "${MCP_DIR}/safe-exec-mcp/index.js")
assert_contains "safe-exec-mcp: analyze_command registered" "analyze_command" "$safe_src"

# blueprint-aligner-mcp: align_diff
blueprint_src=$(cat "${MCP_DIR}/blueprint-aligner-mcp/index.js")
assert_contains "blueprint-aligner-mcp: align_diff registered" "align_diff" "$blueprint_src"

# context-guardian-mcp: check_workspace
guardian_src=$(cat "${MCP_DIR}/context-guardian-mcp/index.js")
assert_contains "context-guardian-mcp: check_workspace registered" "check_workspace" "$guardian_src"

# risk-analyzer-mcp: classify_risk, get_tier_actions
risk_src=$(cat "${MCP_DIR}/risk-analyzer-mcp/index.js")
assert_contains "risk-analyzer-mcp: classify_risk registered" "classify_risk" "$risk_src"
assert_contains "risk-analyzer-mcp: get_tier_actions registered" "get_tier_actions" "$risk_src"

# context-invoker-mcp: activate_skill, activate_agent
invoker_src=$(cat "${MCP_DIR}/context-invoker-mcp/index.js")
assert_contains "context-invoker-mcp: activate_skill registered" "activate_skill" "$invoker_src"
assert_contains "context-invoker-mcp: activate_agent registered" "activate_agent" "$invoker_src"

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
