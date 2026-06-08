#!/usr/bin/env bash
# context_invoker_test.sh — Unit tests for context-invoker-mcp project scope (E-116/E-119)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
INVOKER_JS="${REPO_ROOT}/src/mcp/context-invoker-mcp/index.js"

echo "── Suite: context_invoker_test ──────────────────────────────────────"

# ── Helper: extract SKILL_ROOTS / AGENT_ROOTS ordering from source ────────────
get_root_order() {
  local var="$1"  # SKILL_ROOTS or AGENT_ROOTS
  node -e "
import { existsSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
// Stub existsSync so .ai/ is present
import { createRequire } from 'module';
" 2>/dev/null || true
}

# ── Test 1: project-scoped paths appear before global paths in SKILL_ROOTS ────
_assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _pass "$label"
  else
    _fail "$label (expected '$needle' in output)"
  fi
}

_assert_file_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    _pass "$label"
  else
    _fail "$label (expected '$needle' in $file)"
  fi
}

_assert_index_before() {
  local label="$1" content="$2" first="$3" second="$4"
  local idx_first idx_second
  idx_first=$(echo "$content" | grep -n "$first" | head -1 | cut -d: -f1)
  idx_second=$(echo "$content" | grep -n "$second" | head -1 | cut -d: -f1)
  if [[ -n "$idx_first" && -n "$idx_second" && "$idx_first" -lt "$idx_second" ]]; then
    _pass "$label"
  else
    _fail "$label (expected '$first' before '$second', got lines ${idx_first:-?} and ${idx_second:-?})"
  fi
}

SOURCE=$(cat "$INVOKER_JS")

# T-01: .claude/skills appears in SKILL_ROOTS definition
_assert_contains \
  "T-01: .claude/skills in SKILL_ROOTS" \
  "$SOURCE" \
  '".claude", "skills"'

# T-02: .agents/skills appears in SKILL_ROOTS definition (E-132: migrated from .gemini/skills)
_assert_contains \
  "T-02: .agents/skills in SKILL_ROOTS" \
  "$SOURCE" \
  '".agents", "skills"'

# T-03: .claude/agents appears in AGENT_ROOTS definition
_assert_contains \
  "T-03: .claude/agents in AGENT_ROOTS" \
  "$SOURCE" \
  '".claude", "agents"'

# T-04: .gemini/agents appears in AGENT_ROOTS definition
_assert_contains \
  "T-04: .gemini/agents in AGENT_ROOTS" \
  "$SOURCE" \
  '".gemini", "agents"'

# T-05: project-scoped roots spread before global HOME roots in SKILL_ROOTS
_assert_index_before \
  "T-05: ...projectSkillRoots before join(HOME, .claude) in SKILL_ROOTS" \
  "$SOURCE" \
  "projectSkillRoots" \
  'join(HOME, ".claude"'

# T-06: project-scoped roots spread before global HOME roots in AGENT_ROOTS
_assert_index_before \
  "T-06: ...projectAgentRoots before join(HOME, .claude) in AGENT_ROOTS" \
  "$SOURCE" \
  "projectAgentRoots" \
  'join(HOME, ".claude"'

# T-07: .ai directory presence gates project-scoped root injection
_assert_contains \
  "T-07: .ai existence check gates project-scoped roots" \
  "$SOURCE" \
  'existsSync(join(cwd, ".ai"))'

# ── Test 8: compliance audit scans project-scoped dirs (E-118) ────────────────
AI_BIN="${REPO_ROOT}/src/bin/ai"

_assert_file_contains "T-08: compliance audit includes .claude/agents" \
  "$AI_BIN" 'Path(".claude/agents")'

_assert_file_contains "T-09: compliance audit includes .gemini/agents" \
  "$AI_BIN" 'Path(".gemini/agents")'

_assert_file_contains "T-10: compliance audit includes .claude/skills" \
  "$AI_BIN" 'Path(".claude/skills")'

_assert_file_contains "T-11: compliance audit includes .agents/skills" \
  "$AI_BIN" 'Path(".agents/skills")'

# ── Test 12: ANTI-DRIFT check present in compliance audit (E-121) ─────────────
_assert_file_contains "T-12: ANTI-DRIFT PROTOCOL check in compliance audit" \
  "$AI_BIN" 'ANTI_DRIFT_HEADER'

_assert_file_contains "T-13: ANTI-DRIFT check targets CLAUDE.md" \
  "$AI_BIN" '"CLAUDE.md"'

_assert_file_contains "T-14: ANTI-DRIFT check targets GEMINI.md" \
  "$AI_BIN" '"GEMINI.md"'

# ── Test 15: ANTI-DRIFT PROTOCOL section exists in src files (E-120) ──────────
check_anti_drift_present() {
  local label="$1" file="$2"
  if grep -q "ANTI-DRIFT PROTOCOL" "$file" 2>/dev/null; then
    _pass "$label"
  else
    _fail "$label (ANTI-DRIFT PROTOCOL missing from $file)"
  fi
}

check_anti_drift_present "T-15: src/claude/CLAUDE.md has ANTI-DRIFT PROTOCOL" \
  "${REPO_ROOT}/src/claude/CLAUDE.md"

check_anti_drift_present "T-16: src/gemini/GEMINI.md has ANTI-DRIFT PROTOCOL" \
  "${REPO_ROOT}/src/gemini/GEMINI.md"

check_anti_drift_present "T-17: src/templates/CLAUDE.md has ANTI-DRIFT PROTOCOL" \
  "${REPO_ROOT}/src/templates/CLAUDE.md"

check_anti_drift_present "T-18: src/templates/GEMINI.md has ANTI-DRIFT PROTOCOL" \
  "${REPO_ROOT}/src/templates/GEMINI.md"

# ── Test 19: pre-commit.sh has co-modification check (E-122) ─────────────────
PRECOMMIT="${REPO_ROOT}/hooks/pre-commit.sh"
_assert_file_contains "T-19: pre-commit.sh has check_architect_src_comodification" \
  "$PRECOMMIT" "check_architect_src_comodification"

_assert_file_contains "T-20: pre-commit.sh warns on architect.md + src/ co-stage" \
  "$PRECOMMIT" "ARCH_WARN"

# ── Test 21 (v3.0 W2-T3): Claude-scoped gate skills exist + are reachable ────
# dependency_gate / ci_gate are Claude-only mid-task triggers (CLAUDE.md). They
# resolve because SKILL_ROOTS includes src/claude/skills + ~/.ai-os/claude/skills.
for gate in dependency_gate ci_gate; do
  assert_status 0 "T-21: ${gate} SKILL.md present (Claude-scoped)" \
    test -f "${REPO_ROOT}/src/claude/skills/${gate}/SKILL.md"
done
_assert_file_contains "T-21: SKILL_ROOTS includes src/claude/skills (gate skills reachable)" \
  "$INVOKER_JS" 'join(srcBase, "claude", "skills")'
_assert_file_contains "T-21: SKILL_ROOTS includes ~/.ai-os/claude/skills (installed gates reachable)" \
  "$INVOKER_JS" 'join(HOME, ".ai-os", "claude", "skills")'

echo ""
assert_summary
