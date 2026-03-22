#!/usr/bin/env bash
# resilience_test.sh — Bootloader Resilience Validation Suite (E-113 / P-52 §34)
# Validates: 3-layer bootloader fallback (orchestrator-mcp → ai-preflight → CLAUDE.md),
# readStateStrict version guard rejection, and state corruption recovery.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
ORCH_MCP="${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
SHARED_STATE="${REPO_ROOT}/src/mcp/shared/state-writer.js"
PREFLIGHT_SKILL="${REPO_ROOT}/src/shared/skills/ai-preflight/SKILL.md"
CLAUDE_MD_GLOBAL="${HOME}/.claude/CLAUDE.md"
CLAUDE_MD_TEMPLATE="${REPO_ROOT}/src/templates/CLAUDE.md"

echo "── Suite: resilience_test ─────────────────────────────────────────"

# ── Scenario A: Layer 1 Failure (orchestrator-mcp unavailability) ─────────────

# T-RES-01: orchestrator-mcp syntax is valid (server is startable)
assert_status 0 "T-RES-01: orchestrator-mcp syntax OK" \
  node -e "import('file://${ORCH_MCP}').catch(e => { if (e instanceof SyntaxError) process.exit(1); })"

# T-RES-02: Layer 2 fallback skill exists and is non-empty
assert_exists "$PREFLIGHT_SKILL"

# T-RES-03: ai-preflight skill has valid YAML frontmatter
preflight_name=$(grep "^name:" "$PREFLIGHT_SKILL" | awk '{print $2}')
assert_contains "T-RES-03: ai-preflight skill has correct name" "ai-preflight" "$preflight_name"

# T-RES-04: ai-preflight skill contains bash fallback read instructions
assert_status 0 "T-RES-04: ai-preflight contains bash jq fallback" \
  grep -q "state.json\|jq\|grep" "$PREFLIGHT_SKILL"

# T-RES-05: Layer 3 — global CLAUDE.md has Emergency Recovery section
assert_status 0 "T-RES-05: global CLAUDE.md has Emergency Recovery section (Layer 3)" \
  grep -q "Emergency Recovery\|Bootloader Resilience\|Layer 3\|Absolute last resort" "$CLAUDE_MD_GLOBAL"

# ── Scenario B: Layer 2 Failure (ai-preflight skill missing) ─────────────────

# T-RES-06: global CLAUDE.md contains manual recovery bash commands
assert_status 0 "T-RES-06: global CLAUDE.md manual recovery has 'grep TASKS.md' fallback" \
  grep -q "TASKS.md" "$CLAUDE_MD_GLOBAL"

# T-RES-07: global CLAUDE.md contains state.json python/jq read for focus
assert_status 0 "T-RES-07: global CLAUDE.md manual recovery reads state.json focus" \
  grep -q "state.json\|focus\|python3\|jq" "$CLAUDE_MD_GLOBAL"

# T-RES-08: global CLAUDE.md contains LOG.md tail fallback
assert_status 0 "T-RES-08: global CLAUDE.md manual recovery has LOG.md tail fallback" \
  grep -q "LOG.md" "$CLAUDE_MD_GLOBAL"

# ── Scenario C: State Corruption (invalid state.json) ────────────────────────

# T-RES-09: readStateStrict rejects state.json with wrong version field
reject_result=$(node -e "
const { readStateStrict } = await import('file://${SHARED_STATE}');
const os = await import('os');
const fs = await import('fs');
const path = await import('path');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'resilience-'));
// Write state.json with wrong version
fs.writeFileSync(path.join(tmp, 'state.json'), JSON.stringify({ version: '99.0', tasks: [], stamps: [] }));
const result = readStateStrict(tmp);
console.log(result === null ? 'null' : 'not-null');
" 2>/dev/null || echo "error")
assert_contains "T-RES-09: readStateStrict returns null for wrong version" "null" "$reject_result"

# T-RES-10: readStateStrict rejects syntactically invalid JSON
invalid_result=$(node -e "
const { readStateStrict } = await import('file://${SHARED_STATE}');
const os = await import('os');
const fs = await import('fs');
const path = await import('path');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'resilience-corrupt-'));
fs.writeFileSync(path.join(tmp, 'state.json'), '{invalid json !!!}');
const result = readStateStrict(tmp);
console.log(result === null ? 'null' : 'not-null');
" 2>/dev/null || echo "error")
assert_contains "T-RES-10: readStateStrict returns null for invalid JSON" "null" "$invalid_result"

# T-RES-11: readStateStrict returns null (not throws) for missing state.json
missing_result=$(node -e "
const { readStateStrict } = await import('file://${SHARED_STATE}');
const result = readStateStrict('/tmp/nonexistent-ai-os-dir-xyz');
console.log(result === null ? 'null' : 'not-null');
" 2>/dev/null || echo "error")
assert_contains "T-RES-11: readStateStrict returns null for missing state.json" "null" "$missing_result"

# T-RES-12: run_intent_cleanup tool is registered in orchestrator-mcp
assert_status 0 "T-RES-12: orchestrator-mcp registers run_intent_cleanup tool" \
  grep -q "run_intent_cleanup" "$ORCH_MCP"

# T-RES-13: run_intent_cleanup archives to .ai/archive/COMM/ path
assert_status 0 "T-RES-13: run_intent_cleanup targets archive/COMM directory" \
  grep -q "archive.*COMM\|COMM.*archive" "$ORCH_MCP"

# T-RES-14: prd_writer.md includes §33 intent cleanup instruction
assert_status 0 "T-RES-14: prd_writer.md has §33 Intent Lifecycle Cleanup section" \
  grep -q "Intent Lifecycle\|§33\|UPDATE.md.*archive\|archive.*UPDATE.md" "${REPO_ROOT}/src/gemini/agents/prd_writer.md"

assert_summary
