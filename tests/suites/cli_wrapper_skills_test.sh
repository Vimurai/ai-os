#!/usr/bin/env bash
# cli_wrapper_skills_test.sh — Tests for E-178: CLI automation wrapper skills for
# the top-5 high-frequency MCP tools identified by the meta-cognition INSIGHTS report.
# Each wrapper must (a) exist in the canonical src/shared/skills tree, (b) be mirrored
# byte-identically into the .claude/skills and .agents/skills runtime trees, and
# (c) carry compliant, operational frontmatter (user-invocable, context: default,
# allowed-tools naming the wrapped mcp__ tool).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== cli_wrapper_skills_test.sh (E-178) ====="

SRC="${REPO_ROOT}/src/shared/skills"
CLAUDE="${REPO_ROOT}/.claude/skills"
AGENTS="${REPO_ROOT}/.agents/skills"

# skill-name → the canonical mcp__ tool it wraps
declare -a SKILLS=(
  "ai-analyze|mcp__safe-exec-mcp__analyze_command"
  "ai-cluster|mcp__task-synchronizer-mcp__add_cluster_page"
  "ai-sync-verify|mcp__task-synchronizer-mcp__verify_markdown_sync"
  "ai-topic|mcp__task-synchronizer-mcp__add_topic_seed"
  "ai-dispatch|mcp__orchestrator-mcp__run_dispatch"
)

fm() { sed -n '/^---$/,/^---$/p' "$1" 2>/dev/null; }  # extract YAML frontmatter block

for entry in "${SKILLS[@]}"; do
  name="${entry%%|*}"
  tool="${entry##*|}"
  src_file="${SRC}/${name}/SKILL.md"

  # (a) canonical source exists
  assert_exists "${src_file}"

  # (b) runtime mirrors exist and are byte-identical to source
  assert_status 0 "T-178: ${name} → .claude mirror identical" diff -q "${src_file}" "${CLAUDE}/${name}/SKILL.md"
  assert_status 0 "T-178: ${name} → .agents mirror identical" diff -q "${src_file}" "${AGENTS}/${name}/SKILL.md"

  # (c) compliant operational frontmatter
  front="$(fm "${src_file}")"
  assert_contains "T-178: ${name} name matches"        "name: ${name}"        "${front}"
  assert_contains "T-178: ${name} is user-invocable"   "user-invocable: true" "${front}"
  assert_contains "T-178: ${name} runs in-thread"      "context: default"     "${front}"
  assert_contains "T-178: ${name} model-invocable"     "disable-model-invocation: false" "${front}"
  assert_contains "T-178: ${name} wraps ${tool}"       "${tool}"              "${front}"

  # must NOT use the invalid YAML-list allowed-tools form (E-159 Ghost Tool compliance)
  assert_not_contains "T-178: ${name} allowed-tools is not a YAML list" "allowed-tools: [" "${front}"
done

assert_summary
