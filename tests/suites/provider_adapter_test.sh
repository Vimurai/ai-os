#!/usr/bin/env bash
# provider_adapter_test.sh — E-138 Provider Adapter System (.ai/providers.json) per
# role-abstraction.md §Components 2-3, narrowed by E-254 (D-069): AI-OS v4 is
# Claude-native, so the template and the built-in adapters declare `claude` only and the
# `ai provider` subcommand is removed (providers are configured in .ai/providers.json).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
TEMPLATE="${REPO_ROOT}/src/templates/providers.json"
ADAPTER="${REPO_ROOT}/src/shared/provider-adapter.mjs"
export AIOS="${HOME}/.ai-os"

echo "── Suite: provider_adapter_test (E-138 / E-254) ─────────────────────"

# ── T-1: providers.json template valid + declares exactly the claude provider ──
assert_exists "$TEMPLATE"
assert_status 0 "T-1: providers.json template is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('${TEMPLATE}','utf8'))"
keys=$(node -e "process.stdout.write(Object.keys(require('${TEMPLATE}').providers).sort().join(','))")
assert_match "T-1b: template declares exactly one provider (claude)" "^claude$" "$keys"
cl=$(node -e "const a=require('${TEMPLATE}').providers.claude; process.stdout.write(a.mcp_config_path+'|'+a.mcp_key)")
assert_contains "T-1c: claude → .claude.json|mcpServers" ".claude.json|mcpServers" "$cl"
builtin=$(node --input-type=module -e "const m=await import('file://${ADAPTER}'); process.stdout.write(Object.keys(m.DEFAULT_ADAPTERS).sort().join(','))")
assert_match "T-1d: built-in DEFAULT_ADAPTERS declare exactly claude" "^claude$" "$builtin"

# ── T-2: ensure_ai_templates scaffolds .ai/providers.json ────────────────────
assert_status 0 "T-2: providers.json wired into ensure_ai_templates" \
  grep -q 'ensure_file_if_missing "$T/providers.json"' "$AI_BIN"

# ── T-3: `ai provider` is removed — exits 2 and points at .ai/providers.json ──
PROJ="$(mktemp -d)"; mkdir -p "${PROJ}/.ai"
out=$(cd "$PROJ" && "$AI_BIN" provider add foo --config-path config/foo.json --mcp-key mcpServers 2>&1; echo "rc=$?")
assert_contains "T-3a: ai provider add exits 2" "rc=2" "$out"
assert_contains "T-3b: the refusal names .ai/providers.json" \
  "providers are configured in .ai/providers.json" "$out"
# The removed subcommand must not have half-run: no registry entry, no generated config.
assert_status 1 "T-3c: no providers.json written by the removed subcommand" \
  test -f "${PROJ}/.ai/providers.json"
assert_status 1 "T-3d: no provider MCP config generated" test -f "${PROJ}/config/foo.json"
bare=$(cd "$PROJ" && "$AI_BIN" provider 2>&1; echo "rc=$?")
assert_contains "T-3e: bare ai provider also exits 2" "rc=2" "$bare"
rm -rf "$PROJ"

# ── T-5: generate_mcp_json honors a custom output path + top-level key ────────
GP="$(mktemp -d)"
( source "$AI_BIN" 2>/dev/null; cd "$GP"; generate_mcp_json "." "custom.json" "serverList" )
key=$(node -e "const c=require('${GP}/custom.json'); process.stdout.write(Object.keys(c)[0]||'')" 2>/dev/null)
assert_contains "T-5: generate_mcp_json writes the requested top-level key" "serverList" "$key"
rm -rf "$GP"

assert_summary
