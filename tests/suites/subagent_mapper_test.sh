#!/usr/bin/env bash
# subagent_mapper_test.sh — E-140 / E-142 (native-subagents.md): `ai sync --agents` maps
# only AI-OS *personas* (.claude/agents, .gemini/agents) → native Antigravity subagents at
# .agents/agents/<name>/agent.json (per-agent subdir). Procedural skills (frontmatter
# `context: default` or `type: skill`) are FILTERED OUT (E-142 taxonomy). Covers payload,
# the taxonomy filter, the subdir format, dedup, idempotency, clear, and E2E.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
MAPPER="${REPO_ROOT}/src/shared/subagent-mapper.mjs"
export AIOS="${HOME}/.ai-os"
IMPORT="import {toSubagent,mapAgents,clearAgents} from 'file://${MAPPER}'; import {resolve} from 'node:path';"

echo "── Suite: subagent_mapper_test (E-140/E-142) ───────────────────────"

# T-1: mapper module parses
assert_status 0 "T-1: subagent-mapper.mjs valid JS" node --check "$MAPPER"

# T-2: toSubagent → define_subagent payload (personas delegate to the real agent)
payload=$(node --input-type=module -e "import {toSubagent} from 'file://${MAPPER}'; process.stdout.write(JSON.stringify(toSubagent({name:'critic_arch',description:'Arch reviewer'})))")
assert_contains "T-2a: name prefixed ai-os-"            '"name":"ai-os-critic_arch"' "$payload"
assert_contains "T-2b: enable_mcp_tools true"           '"enable_mcp_tools":true'      "$payload"
assert_contains "T-2c: system_prompt delegates via activate_agent" "activate_agent({ agent_name: 'critic_arch' })" "$payload"
assert_contains "T-2d: system_prompt enforces safe-exec boundary"  "safe-exec-mcp" "$payload"
assert_contains "T-2e: description carried through" '"description":"Arch reviewer"' "$payload"

# T-3: mapAgents maps ONLY personas, in subdir format; filters skills; dedups; idempotent
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude/agents" "$TMP/.gemini/agents"
printf -- '---\nname: critic_arch\ndescription: Arch reviewer\ncontext: fork\n---\nbody\n'  > "$TMP/.claude/agents/critic_arch.md"
printf -- '---\nname: critic_arch\ndescription: dup\ncontext: fork\n---\nbody\n'             > "$TMP/.gemini/agents/critic_arch.md"   # dedup
printf -- '---\nname: meta_analyst\ndescription: Meta\ncontext: fork\n---\nbody\n'           > "$TMP/.gemini/agents/meta_analyst.md"
printf -- '---\nname: digest_updater\ndescription: skill\ntype: skill\ncontext: default\n---\nbody\n' > "$TMP/.claude/agents/digest_updater.md"  # filtered (type:skill)
printf -- '---\nname: proc_default\ndescription: ctx-default\ncontext: default\n---\nbody\n' > "$TMP/.gemini/agents/proc_default.md"             # filtered (context:default)
( cd "$TMP" && node --input-type=module -e "${IMPORT} mapAgents([resolve('.claude/agents'),resolve('.gemini/agents')], resolve('.agents/agents'))" )
ndirs=$(find "$TMP/.agents/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-3a: only 2 personas mapped (skills filtered)" "2" "$ndirs"
assert_status 0 "T-3b: subdir format → ai-os-critic_arch/agent.json" test -f "$TMP/.agents/agents/ai-os-critic_arch/agent.json"
assert_status 0 "T-3c: ai-os-meta_analyst/agent.json exists"         test -f "$TMP/.agents/agents/ai-os-meta_analyst/agent.json"
assert_status 1 "T-3d: type:skill FILTERED (no ai-os-digest_updater)"   test -e "$TMP/.agents/agents/ai-os-digest_updater"
assert_status 1 "T-3e: context:default FILTERED (no ai-os-proc_default)" test -e "$TMP/.agents/agents/ai-os-proc_default"
( cd "$TMP" && node --input-type=module -e "${IMPORT} mapAgents([resolve('.claude/agents'),resolve('.gemini/agents')], resolve('.agents/agents'))" )
ndirs2=$(find "$TMP/.agents/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-3f: idempotent re-run still 2 persona subdirs" "2" "$ndirs2"

# T-4: clearAgents removes ai-os-* subdirs + legacy flat ai-os-*.json, leaves hand-authored
mkdir -p "$TMP/.agents/agents/custom-keep"; printf '{}' > "$TMP/.agents/agents/custom-keep/agent.json"
printf '{}' > "$TMP/.agents/agents/ai-os-legacy-flat.json"
cleared=$(node --input-type=module -e "${IMPORT} process.stdout.write(String(clearAgents('$TMP/.agents/agents')))")
assert_status 0 "T-4a: cleared >=3 (2 subdirs + 1 legacy flat)" bash -c "[ '$cleared' -ge 3 ]"
assert_status 0 "T-4b: hand-authored custom-keep preserved" test -f "$TMP/.agents/agents/custom-keep/agent.json"
assert_status 1 "T-4c: ai-os subdir gone"                   test -e "$TMP/.agents/agents/ai-os-critic_arch"
assert_status 1 "T-4d: legacy flat ai-os-*.json gone"       test -e "$TMP/.agents/agents/ai-os-legacy-flat.json"

# T-5: `ai sync --agents` end-to-end (subdir format; uses the INSTALLED mapper)
PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.ai" "$PROJ/.claude/agents"
printf -- '---\nname: critic_security\ndescription: Sec auditor\ncontext: fork\n---\nbody\n' > "$PROJ/.claude/agents/critic_security.md"
printf -- '---\nname: a_skill\ndescription: s\ntype: skill\n---\nbody\n'                      > "$PROJ/.claude/agents/a_skill.md"
( cd "$PROJ" && "$AI_BIN" sync --agents >/dev/null 2>&1 )
assert_status 0 "T-5a: persona → ai-os-critic_security/agent.json" test -f "$PROJ/.agents/agents/ai-os-critic_security/agent.json"
assert_status 1 "T-5b: type:skill filtered (no ai-os-a_skill)"     test -e "$PROJ/.agents/agents/ai-os-a_skill"
assert_status 0 "T-5c: manifest valid JSON" node -e "JSON.parse(require('fs').readFileSync('$PROJ/.agents/agents/ai-os-critic_security/agent.json','utf8'))"

# T-6: `ai sync --clear-agents` rollback
( cd "$PROJ" && "$AI_BIN" sync --clear-agents >/dev/null 2>&1 )
assert_status 1 "T-6: clear-agents removed the subdir" test -e "$PROJ/.agents/agents/ai-os-critic_security"
rm -rf "$PROJ"

# T-7: --agents outside an AI-OS project errors (guard)
assert_status 1 "T-7: ai sync --agents without .ai/ errors" \
  bash -c "cd \"\$(mktemp -d)\" && '$AI_BIN' sync --agents"

assert_summary
