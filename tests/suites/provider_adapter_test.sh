#!/usr/bin/env bash
# provider_adapter_test.sh — E-138 Provider Adapter System (.ai/providers.json +
# `ai provider add`) per role-abstraction.md §Components 2-3 + §Security. Sources
# src/bin/ai (guarded) for unit checks and invokes the real subcommand for E2E.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
TEMPLATE="${REPO_ROOT}/src/templates/providers.json"
export AIOS="${HOME}/.ai-os"

echo "── Suite: provider_adapter_test (E-138) ────────────────────────────"

# ── T-1: providers.json template valid + documents the known providers ───────
assert_exists "$TEMPLATE"
assert_status 0 "T-1: providers.json template is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('${TEMPLATE}','utf8'))"
schema=$(node -e "const p=require('${TEMPLATE}').providers; process.stdout.write(['claude','gemini','agy'].every(k=>p[k]&&p[k].mcp_config_path&&p[k].mcp_key)?'OK':'BAD')")
assert_contains "T-1b: claude+gemini+agy declare mcp_config_path+mcp_key" "OK" "$schema"
agy=$(node -e "const a=require('${TEMPLATE}').providers.agy; process.stdout.write(a.mcp_config_path+'|'+a.mcp_key)")
assert_contains "T-1c: agy → .agents/mcp_config.json|mcpServers" ".agents/mcp_config.json|mcpServers" "$agy"

# ── T-2: ensure_ai_templates scaffolds .ai/providers.json ────────────────────
assert_status 0 "T-2: providers.json wired into ensure_ai_templates" \
  grep -q 'ensure_file_if_missing "$T/providers.json"' "$AI_BIN"

# ── T-3: path-traversal validation (blueprint §Security) ─────────────────────
assert_status 2 "T-3a: rejects absolute --config-path" \
  bash -c "cd \"\$(mktemp -d)\" && mkdir .ai && '$AI_BIN' provider add foo --config-path /etc/passwd"
assert_status 2 "T-3b: rejects '..' traversal" \
  bash -c "cd \"\$(mktemp -d)\" && mkdir .ai && '$AI_BIN' provider add foo --config-path ../../etc/x.json"
assert_status 2 "T-3c: rejects '~' home expansion" \
  bash -c "cd \"\$(mktemp -d)\" && mkdir .ai && '$AI_BIN' provider add foo --config-path '~/x.json'"
assert_status 2 "T-3d: rejects bad provider name" \
  bash -c "cd \"\$(mktemp -d)\" && mkdir .ai && '$AI_BIN' provider add 'Bad Name' --config-path x.json"
# T-3e: a planted in-repo symlink whose target is OUTSIDE the project is rejected
# (symlink-escape — passes the string checks but fails canonical containment).
OUTSIDE="$(mktemp -d)"
assert_status 2 "T-3e: rejects symlink that escapes the project" \
  bash -c "P=\"\$(mktemp -d)\"; cd \"\$P\" && mkdir .ai && ln -s '$OUTSIDE' esc && '$AI_BIN' provider add foo --config-path esc/mcp.json"
rm -rf "$OUTSIDE"

# ── T-4: register a provider → providers.json updated + config generated ─────
PROJ="$(mktemp -d)"; mkdir -p "${PROJ}/.ai"
( cd "$PROJ" && "$AI_BIN" provider add agy --config-path .agents/mcp_config.json --mcp-key mcpServers >/dev/null 2>&1 )
assert_status 0 "T-4a: providers.json written" test -f "${PROJ}/.ai/providers.json"
reg=$(node -e "const a=require('${PROJ}/.ai/providers.json').providers.agy; process.stdout.write(a.mcp_config_path+'|'+a.mcp_key)")
assert_contains "T-4b: agy registered in providers.json" ".agents/mcp_config.json|mcpServers" "$reg"
assert_status 0 "T-4c: provider MCP config generated at custom path" test -f "${PROJ}/.agents/mcp_config.json"
assert_status 0 "T-4d: generated config has mcpServers key + servers" \
  node -e "const c=require('${PROJ}/.agents/mcp_config.json'); if(!c.mcpServers||!c.mcpServers.filesystem)process.exit(1)"
rm -rf "$PROJ"

# ── T-5: generate_mcp_json honors a custom output path + top-level key ────────
GP="$(mktemp -d)"
( source "$AI_BIN" 2>/dev/null; cd "$GP"; generate_mcp_json "." "custom.json" "serverList" )
key=$(node -e "const c=require('${GP}/custom.json'); process.stdout.write(Object.keys(c)[0]||'')" 2>/dev/null)
assert_contains "T-5: generate_mcp_json writes the requested top-level key" "serverList" "$key"
rm -rf "$GP"

# ── T-6: registered config stays inside the project (no traversal artifact) ──
SAFE="$(mktemp -d)"; mkdir -p "${SAFE}/.ai"
( cd "$SAFE" && "$AI_BIN" provider add antig --config-path config/antig.json --mcp-key mcpServers >/dev/null 2>&1 )
assert_status 0 "T-6: nested-but-in-bounds path generated" test -f "${SAFE}/config/antig.json"
rm -rf "$SAFE"

assert_summary
