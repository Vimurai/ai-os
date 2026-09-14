#!/usr/bin/env bash
# specialist_agents_test.sh — E-149..E-152: the four new specialist agents
# (performance_engineer, db_architect, dependency_manager, sre_responder) + their
# skills (ai-profile, ai-migration, ai-upgrade, ai-triage), authored per the new
# .ai/blueprints/*.md. Verifies each persona/skill exists with a matching `name:`
# and carries its blueprint safety invariant. (E-254 removed the separate agent plugin;
# src/claude/agents/ is the only agent tree.)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: specialist_agents_test (E-149..E-152) ────────────────────"

name_of() { grep -m1 '^name:' "$1" 2>/dev/null | sed 's/^name:[[:space:]]*//'; }

# ── Agents: file exists, name matches filename ──────────────────────────────
for a in performance_engineer db_architect dependency_manager sre_responder; do
  f="${REPO_ROOT}/src/claude/agents/${a}.md"
  assert_status 0 "agent ${a}: persona file exists" test -f "$f"
  assert_contains "agent ${a}: frontmatter name matches" "$a" "$(name_of "$f")"
done

# ── Skills: file exists, name matches ────────────────────────────────────────
for s in ai-profile ai-migration ai-upgrade ai-triage; do
  f="${REPO_ROOT}/src/shared/skills/${s}/SKILL.md"
  assert_status 0 "skill ${s}: SKILL.md exists" test -f "$f"
  assert_contains "skill ${s}: frontmatter name matches" "$s" "$(name_of "$f")"
done

# ── Blueprint safety invariants (each agent must honor its §Security) ─────────
# performance: sandbox-only profiling (no host DoS)
assert_status 0 "perf: profiles inside code-execution-mcp sandbox" \
  grep -qiE "code-execution-mcp|sandbox" "${REPO_ROOT}/src/claude/agents/performance_engineer.md"
# db: mandatory DOWN/rollback migration
assert_status 0 "db: requires DOWN/rollback migration" \
  grep -qiE "down|rollback" "${REPO_ROOT}/src/claude/agents/db_architect.md"
# dependency: cannot bypass critic_security
assert_status 0 "dep: routes through critic_security" \
  grep -qiE "critic_security|cve|audit" "${REPO_ROOT}/src/claude/agents/dependency_manager.md"
# sre: READ-ONLY over logs — plans tasks, never edits code itself
assert_status 0 "sre: read-only / plans tasks via add_task" \
  grep -qiE "read-only|add_task|plan" "${REPO_ROOT}/src/claude/agents/sre_responder.md"

assert_summary
