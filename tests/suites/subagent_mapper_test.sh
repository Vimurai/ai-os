#!/usr/bin/env bash
# subagent_mapper_test.sh — E-140 (native-subagents.md): `ai sync --agents` maps AI-OS
# agents (.claude/agents, .gemini/agents) → native Antigravity subagent manifests in
# .agents/agents/. Covers the payload shape, idempotency, dedup, clear, and E2E.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
MAPPER="${REPO_ROOT}/src/shared/subagent-mapper.mjs"
export AIOS="${HOME}/.ai-os"
IMPORT="import {toSubagent,mapAgents,clearAgents} from 'file://${MAPPER}'; import {resolve} from 'node:path';"

echo "── Suite: subagent_mapper_test (E-140) ─────────────────────────────"

# T-1: mapper module parses
assert_status 0 "T-1: subagent-mapper.mjs valid JS" node --check "$MAPPER"

# T-2: toSubagent produces the blueprint define_subagent payload
payload=$(node --input-type=module -e "import {toSubagent} from 'file://${MAPPER}'; process.stdout.write(JSON.stringify(toSubagent({name:'critic_arch',description:'Arch reviewer'})))")
assert_contains "T-2a: name prefixed ai-os-"            '"name":"ai-os-critic_arch"' "$payload"
assert_contains "T-2b: enable_mcp_tools true"           '"enable_mcp_tools":true'      "$payload"
assert_contains "T-2c: system_prompt delegates via activate_agent" "activate_agent({ agent_name: 'critic_arch' })" "$payload"
assert_contains "T-2d: system_prompt enforces safe-exec boundary"  "safe-exec-mcp" "$payload"
assert_contains "T-2e: description carried through" '"description":"Arch reviewer"' "$payload"

# T-3: mapAgents writes manifests; deduped across dirs; idempotent
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude/agents" "$TMP/.gemini/agents"
printf -- '---\nname: critic_arch\ndescription: Arch reviewer\n---\nbody\n'       > "$TMP/.claude/agents/critic_arch.md"
printf -- '---\nname: digest_updater\ndescription: Claude digest\n---\nbody\n'    > "$TMP/.claude/agents/digest_updater.md"
printf -- '---\nname: digest_updater\ndescription: Gemini digest dup\n---\nbody\n' > "$TMP/.gemini/agents/digest_updater.md"
printf -- '---\nname: meta_analyst\ndescription: Meta\n---\nbody\n'               > "$TMP/.gemini/agents/meta_analyst.md"
( cd "$TMP" && node --input-type=module -e "${IMPORT} mapAgents([resolve('.claude/agents'),resolve('.gemini/agents')], resolve('.agents/agents'))" )
n=$(ls "$TMP/.agents/agents/"*.json 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-3a: 3 manifests (critic_arch, digest_updater, meta_analyst — deduped)" "3" "$n"
assert_status 0 "T-3b: ai-os-critic_arch.json exists" test -f "$TMP/.agents/agents/ai-os-critic_arch.json"
assert_status 0 "T-3c: single deduped ai-os-digest_updater.json" test -f "$TMP/.agents/agents/ai-os-digest_updater.json"
dd=$(node -e "process.stdout.write(require('$TMP/.agents/agents/ai-os-digest_updater.json').description)")
assert_contains "T-3d: dedup keeps first-found (.claude) description" "Claude digest" "$dd"
( cd "$TMP" && node --input-type=module -e "${IMPORT} mapAgents([resolve('.claude/agents'),resolve('.gemini/agents')], resolve('.agents/agents'))" )
n2=$(ls "$TMP/.agents/agents/"*.json 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-3e: idempotent re-run still 3 manifests" "3" "$n2"

# T-4: clearAgents removes only ai-os-*.json (leaves hand-authored subagents)
printf '{"name":"custom"}' > "$TMP/.agents/agents/custom.json"
cleared=$(node --input-type=module -e "${IMPORT} process.stdout.write(String(clearAgents('$TMP/.agents/agents')))")
assert_contains "T-4a: clearAgents removed 3 ai-os manifests" "3" "$cleared"
assert_status 0 "T-4b: hand-authored custom.json preserved" test -f "$TMP/.agents/agents/custom.json"
assert_status 1 "T-4c: ai-os manifests gone" test -f "$TMP/.agents/agents/ai-os-critic_arch.json"

# T-5: `ai sync --agents` end-to-end (uses the INSTALLED mapper at ~/.ai-os/shared)
PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.ai" "$PROJ/.claude/agents"
printf -- '---\nname: critic_security\ndescription: Sec auditor\n---\nbody\n' > "$PROJ/.claude/agents/critic_security.md"
( cd "$PROJ" && "$AI_BIN" sync --agents >/dev/null 2>&1 )
assert_status 0 "T-5a: ai sync --agents created the manifest" test -f "$PROJ/.agents/agents/ai-os-critic_security.json"
assert_status 0 "T-5b: manifest is valid JSON" node -e "JSON.parse(require('fs').readFileSync('$PROJ/.agents/agents/ai-os-critic_security.json','utf8'))"

# T-6: `ai sync --clear-agents` rollback
( cd "$PROJ" && "$AI_BIN" sync --clear-agents >/dev/null 2>&1 )
assert_status 1 "T-6: ai sync --clear-agents removed the manifest" test -f "$PROJ/.agents/agents/ai-os-critic_security.json"
rm -rf "$PROJ"

# T-7: --agents outside an AI-OS project errors (guard)
assert_status 1 "T-7: ai sync --agents without .ai/ errors" \
  bash -c "cd \"\$(mktemp -d)\" && '$AI_BIN' sync --agents"

assert_summary
