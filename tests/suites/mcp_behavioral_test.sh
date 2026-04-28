#!/usr/bin/env bash
# tests/suites/mcp_behavioral_test.sh — Behavioral JSON-RPC roundtrip tests (E-27)
#
# Demonstrates the alternative to grep-against-source assertions: spawn each
# server, exchange real MCP frames, and assert against the protocol response.
# These tests survive cosmetic source changes (quote style, whitespace,
# comment edits) because they only depend on the public contract.

set -uo pipefail
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/mcp-client.sh"

echo "===== mcp_behavioral_test.sh ====="

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Each row: server-name : tool that must appear in tools/list
# computer-use-mcp requires Xvfb (DISPLAY=:99) — not available on macOS / non-Linux
# CI hosts. Skipped here; covered by the existing computer_use_mcp_test.sh suite
# which mocks the X11 environment.

declare -a CASES=(
  "advisor-mcp:ask_architect"
  "approval-mcp:request_approval"
  "cache-manager-mcp:build_cache"
  "cache-manager-mcp:get_cached_context"
  "cache-manager-mcp:invalidate_cache"
  "cache-manager-mcp:get_cache_status"
  "task-synchronizer-mcp:get_state"
  "task-synchronizer-mcp:add_task"
  "task-synchronizer-mcp:update_task_status"
  "task-synchronizer-mcp:validate_payload"
  "orchestrator-mcp:run_preflight"
  "orchestrator-mcp:run_handover"
  "orchestrator-mcp:run_review"
  "verification-mcp:verify_compliance"
  "safe-exec-mcp:analyze_command"
  "risk-analyzer-mcp:classify_risk"
  "risk-analyzer-mcp:get_tier_actions"
  "context-guardian-mcp:check_workspace"
  "context-invoker-mcp:activate_skill"
  "context-invoker-mcp:activate_agent"
  "memory-manager-mcp:export_signature"
  "memory-manager-mcp:query_signatures"
  "blueprint-aligner-mcp:align_diff"
  "blueprint-aligner-mcp:validate_blueprint_section"
  "lsp-mcp:get_definitions"
  "lsp-mcp:get_references"
  "lsp-mcp:get_diagnostics"
  "patch-mcp:patch_file"
  "patch-mcp:get_file_md5"
  "propose-patch-mcp:propose_patch"
  "propose-patch-mcp:confirm_patch"
  "token-budget-mcp:get_token_budget"
  "token-budget-mcp:report_cost"
  "archive-manager-mcp:check_context_health"
  "archive-manager-mcp:execute_archive"
  "github-bridge-mcp:check_gh_auth"
  "github-bridge-mcp:fetch_assigned_issues"
  "vibe-check-mcp:run_vibe_audit"
  "vibe-check-mcp:run_chaos_test"
  "vibe-check-mcp:get_performance_metrics"
)

for row in "${CASES[@]}"; do
  srv="${row%%:*}"
  tool="${row##*:}"
  server="${ROOT}/src/mcp/${srv}/index.js"
  if [[ ! -f "$server" ]]; then
    echo "  ⚠  skipped ${srv} (not installed)"
    continue
  fi
  assert_status 0 "${srv} → tools/list advertises ${tool}" \
    mcp_assert_tool_listed "$server" "$tool"
done

assert_summary
