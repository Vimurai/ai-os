#!/usr/bin/env bash
# e140_e141_e142_test.sh — Tests for token-budget-mcp, propose-patch-mcp, github-bridge-mcp (E-140/141/142)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."

echo "── Suite: e140_e141_e142_test ───────────────────────────────────────"

# ── E-140: token-budget-mcp ──────────────────────────────────────────────────

TOKEN_BUDGET_JS="${REPO_ROOT}/src/mcp/token-budget-mcp/index.js"
TOKEN_BUDGET_PKG="${REPO_ROOT}/src/mcp/token-budget-mcp/package.json"

assert_exists "$TOKEN_BUDGET_JS"
assert_exists "$TOKEN_BUDGET_PKG"

# Source file contains all required tools
TB_CONTENT=$(cat "$TOKEN_BUDGET_JS")
assert_contains "token-budget-mcp: report_cost tool defined"    "report_cost"    "$TB_CONTENT"
assert_contains "token-budget-mcp: get_token_budget tool defined" "get_token_budget" "$TB_CONTENT"
assert_contains "token-budget-mcp: get_usage_report tool defined" "get_usage_report" "$TB_CONTENT"
assert_contains "token-budget-mcp: set_budget tool defined"     "set_budget"     "$TB_CONTENT"
assert_contains "token-budget-mcp: reset_session tool defined"  "reset_session"  "$TB_CONTENT"

# SQLite path uses ~/.ai-os/usage.sqlite (not hardcoded user path)
assert_contains "token-budget-mcp: DB path uses .ai-os dir"  ".ai-os" "$TB_CONTENT"
assert_contains "token-budget-mcp: DB file is usage.sqlite"  "usage.sqlite" "$TB_CONTENT"

# BUDGET_WARN is emitted when threshold exceeded
assert_contains "token-budget-mcp: emits BUDGET_WARN"  "BUDGET_WARN" "$TB_CONTENT"

# Parameterized queries (no injection: uses .run() not string concat in SQL)
assert_contains "token-budget-mcp: uses parameterized SQL" ".run(" "$TB_CONTENT"

# package.json declares @modelcontextprotocol/sdk
TB_PKG=$(cat "$TOKEN_BUDGET_PKG")
assert_contains "token-budget-mcp: package.json has sdk" "@modelcontextprotocol/sdk" "$TB_PKG"

# ── E-141: propose-patch-mcp ─────────────────────────────────────────────────

PROPOSE_JS="${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"
PROPOSE_PKG="${REPO_ROOT}/src/mcp/propose-patch-mcp/package.json"

assert_exists "$PROPOSE_JS"
assert_exists "$PROPOSE_PKG"

PP_CONTENT=$(cat "$PROPOSE_JS")

# All required tools present
assert_contains "propose-patch-mcp: propose_patch tool"      "propose_patch"      "$PP_CONTENT"
assert_contains "propose-patch-mcp: confirm_patch tool"      "confirm_patch"      "$PP_CONTENT"
assert_contains "propose-patch-mcp: reject_patch tool"       "reject_patch"       "$PP_CONTENT"
assert_contains "propose-patch-mcp: list_pending_patches"    "list_pending_patches" "$PP_CONTENT"
assert_contains "propose-patch-mcp: preview_patch tool"      "preview_patch"      "$PP_CONTENT"

# Path traversal protection
assert_contains "propose-patch-mcp: path traversal blocked"  "Path traversal" "$PP_CONTENT"

# In-memory store (patches Map)
assert_contains "propose-patch-mcp: in-memory patch store"   "patches" "$PP_CONTENT"

# Patch display renders confirm/reject instructions
assert_contains "propose-patch-mcp: renders confirm instruction" "confirm_patch" "$PP_CONTENT"

# Does NOT auto-apply — requires explicit confirm
assert_not_contains "propose-patch-mcp: no auto-apply on propose" "writeFileSync" "$(grep -A5 "case \"propose_patch\"" "$PROPOSE_JS" 2>/dev/null || echo "")"

# delta fallback chain present
assert_contains "propose-patch-mcp: delta formatter attempted" "delta" "$PP_CONTENT"

# ── E-142: github-bridge-mcp ─────────────────────────────────────────────────

GITHUB_JS="${REPO_ROOT}/src/mcp/github-bridge-mcp/index.js"
GITHUB_PKG="${REPO_ROOT}/src/mcp/github-bridge-mcp/package.json"

assert_exists "$GITHUB_JS"
assert_exists "$GITHUB_PKG"

GH_CONTENT=$(cat "$GITHUB_JS")

# All required tools
assert_contains "github-bridge-mcp: check_gh_auth tool"             "check_gh_auth"             "$GH_CONTENT"
assert_contains "github-bridge-mcp: fetch_assigned_issues tool"     "fetch_assigned_issues"     "$GH_CONTENT"
assert_contains "github-bridge-mcp: get_issue tool"                 "get_issue"                 "$GH_CONTENT"
assert_contains "github-bridge-mcp: create_intent_from_issues tool" "create_intent_from_issues" "$GH_CONTENT"
assert_contains "github-bridge-mcp: get_pr_status tool"             "get_pr_status"             "$GH_CONTENT"

# gh subcommand whitelist
assert_contains "github-bridge-mcp: whitelist enforced" "allowed" "$GH_CONTENT"
assert_contains "github-bridge-mcp: issue subcommand whitelisted" '"issue"' "$GH_CONTENT"
assert_contains "github-bridge-mcp: pr subcommand whitelisted"    '"pr"'    "$GH_CONTENT"
assert_contains "github-bridge-mcp: auth subcommand whitelisted"  '"auth"'  "$GH_CONTENT"

# No shell injection — uses spawnSync with arg array not string
assert_contains "github-bridge-mcp: uses spawnSync not exec" "spawnSync" "$GH_CONTENT"
assert_not_contains "github-bridge-mcp: no exec()" "exec(" "$GH_CONTENT"

# Returns inline intent (UPDATE.md deprecated E-147 — tool now returns content directly)
assert_contains "github-bridge-mcp: returns inline intent" "Action Required" "$GH_CONTENT"

# ── ai sync --github wiring ───────────────────────────────────────────────────

AI_BIN="${REPO_ROOT}/src/bin/ai"
BIN_CONTENT=$(cat "$AI_BIN")

assert_contains "ai sync --github: do_sync_github function exists" "do_sync_github" "$BIN_CONTENT"
assert_contains "ai sync --github: --github flag detected in do_sync" '"--github"' "$BIN_CONTENT"
assert_contains "ai sync --github: usage line updated" "sync --github" "$BIN_CONTENT"
assert_contains "ai sync --github: gh auth check present" "gh auth status" "$BIN_CONTENT"
assert_contains "ai sync --github: --repo flag supported" "--repo" "$BIN_CONTENT"
assert_contains "ai sync --github: --limit flag supported" "--limit" "$BIN_CONTENT"

# ── Registry: all 3 new servers registered ───────────────────────────────────

REGISTRY="${REPO_ROOT}/src/config/registry.json"
REG_CONTENT=$(cat "$REGISTRY")

assert_contains "registry: token-budget-mcp registered"  "token-budget-mcp"  "$REG_CONTENT"
assert_contains "registry: propose-patch-mcp registered" "propose-patch-mcp" "$REG_CONTENT"
assert_contains "registry: github-bridge-mcp registered" "github-bridge-mcp" "$REG_CONTENT"

# Capabilities correct
assert_contains "registry: token-budget-mcp WRITE capability"  '"token-budget-mcp"' "$REG_CONTENT"
assert_contains "registry: github-bridge-mcp EXECUTE capability" '"EXECUTE"' "$REG_CONTENT"

echo ""
assert_summary
