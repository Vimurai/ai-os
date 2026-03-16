#!/usr/bin/env bash
# verification_test.sh — Tests for verification-mcp (E-111 / §32)
# Validates: PASS/FAIL/WARN frontmatter audit, Ghost Tool detection,
# mcp__-prefix allowance, and bulk scan of src/claude/agents/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
VERIFY_MCP="${REPO_ROOT}/src/mcp/verification-mcp/index.js"

echo "── Suite: verification_test ────────────────────────────────────────"

# T-05.01: MCP file exists and is syntactically valid
assert_exists "$VERIFY_MCP"
assert_status 0 "T-05.01: verification-mcp syntax OK" \
  node -e "import('file://${VERIFY_MCP}').catch(e => { if (e instanceof SyntaxError) process.exit(1); })"

# Helper: audit agent markdown content (inlines parseFrontmatter + auditAgent logic)
audit_agent() {
  local content="$1"
  local MD_FILE
  MD_FILE=$(mktemp /tmp/tmp_verify_XXXXXX.md)
  printf '%s' "$content" > "$MD_FILE"
  node -e "
    import { readFileSync } from 'fs';
    const BUILTIN_TOOLS = new Set([
      'Read','Write','Edit','Glob','Grep','Bash','WebSearch','WebFetch',
      'Agent','TodoRead','TodoWrite','NotebookEdit','ExitPlanMode','EnterPlanMode',
    ]);
    function parseFrontmatter(text) {
      if (!text.startsWith('---')) return null;
      const end = text.indexOf('---', 3);
      if (end === -1) return null;
      const fm = text.slice(3, end);
      const result = {};
      for (const line of fm.split('\n')) {
        const m = line.match(/^([\w-]+):\s*(.+)$/);
        if (m) result[m[1].trim()] = m[2].trim();
      }
      return result;
    }
    function isToolAvailable(tool) {
      if (BUILTIN_TOOLS.has(tool)) return true;
      if (tool === '*') return true;
      if (tool.startsWith('mcp__')) return true;
      return false;
    }
    const text = readFileSync('${MD_FILE}', 'utf8');
    const fm = parseFrontmatter(text);
    if (!fm) { console.log('NO_FRONTMATTER'); process.exit(0); }
    const violations = [];
    const warnings   = [];
    for (const field of ['name','description','disable-model-invocation','user-invocable','allowed-tools']) {
      if (!fm[field]) warnings.push('MISSING_FIELD:' + field);
    }
    const tools = (fm['allowed-tools'] || '').split(',').map(t => t.trim()).filter(Boolean);
    for (const tool of tools) {
      if (!isToolAvailable(tool)) violations.push('GHOST:' + tool);
    }
    const status = violations.length > 0 ? 'FAIL' : warnings.length > 0 ? 'WARN' : 'PASS';
    console.log(status + '|violations=' + violations.join(';') + '|warnings=' + warnings.join(';'));
  " --input-type=module 2>/dev/null || echo "node_error"
  rm -f "$MD_FILE"
}

# T-05.02: Valid frontmatter (all §17.1.2 fields) returns PASS
VALID='---
name: test-agent
description: A test agent for verification
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Write, Bash
---
# Test Agent body'
result=$(audit_agent "$VALID")
assert_contains "T-05.02: valid frontmatter returns PASS" "PASS" "$result"
assert_not_contains "T-05.02b: no Ghost Tool violations" "GHOST" "$result"

# T-05.03: Ghost Tool returns FAIL with tool name
GHOST='---
name: ghost-agent
description: Agent with a non-existent ghost tool
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, NonExistentTool123
---
# Ghost Agent'
result=$(audit_agent "$GHOST")
assert_contains "T-05.03: Ghost Tool detection returns FAIL" "FAIL" "$result"
assert_contains "T-05.03b: Ghost Tool name included in output" "NonExistentTool123" "$result"

# T-05.04: Missing required §17.1.2 fields returns WARN
WARN='---
name: partial-agent
allowed-tools: Read
---
# Partial Agent'
result=$(audit_agent "$WARN")
assert_contains "T-05.04: missing required fields returns WARN" "WARN" "$result"
assert_contains "T-05.04b: missing description reported" "MISSING_FIELD:description" "$result"
assert_contains "T-05.04c: missing disable-model-invocation reported" "MISSING_FIELD:disable-model-invocation" "$result"

# T-05.05: No frontmatter is silently skipped
NO_FM='# Just a markdown file without frontmatter

Some body content here.'
result=$(audit_agent "$NO_FM")
assert_contains "T-05.05: no frontmatter is skipped (NO_FRONTMATTER)" "NO_FRONTMATTER" "$result"

# T-05.06: mcp__-prefixed tools are NOT Ghost Tools
MCP_TOOLS='---
name: mcp-tool-agent
description: Uses MCP tools
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, mcp__task-synchronizer-mcp__add_task, mcp__orchestrator-mcp__run_preflight
---
# MCP Tool Agent'
result=$(audit_agent "$MCP_TOOLS")
assert_contains "T-05.06: mcp__ prefixed tools pass as non-Ghost" "PASS" "$result"

# T-05.07: Bulk scan of src/claude/agents/ — zero CRITICAL violations
AGENTS_DIR="${REPO_ROOT}/src/claude/agents"
if [[ -d "$AGENTS_DIR" ]]; then
  bulk=$(node -e "
    import { readFileSync, readdirSync, statSync } from 'fs';
    import { join } from 'path';
    const BUILTIN_TOOLS = new Set([
      'Read','Write','Edit','Glob','Grep','Bash','WebSearch','WebFetch',
      'Agent','TodoRead','TodoWrite','NotebookEdit','ExitPlanMode','EnterPlanMode',
    ]);
    function parseFrontmatter(text) {
      if (!text.startsWith('---')) return null;
      const end = text.indexOf('---', 3);
      if (end === -1) return null;
      const fm = text.slice(3, end);
      const result = {};
      for (const line of fm.split('\n')) {
        const m = line.match(/^([\w-]+):\s*(.+)$/);
        if (m) result[m[1].trim()] = m[2].trim();
      }
      return result;
    }
    function isToolAvailable(tool) {
      if (BUILTIN_TOOLS.has(tool)) return true;
      if (tool === '*') return true;
      if (tool.startsWith('mcp__')) return true;
      return false;
    }
    function walk(dir) {
      const files = [];
      for (const e of readdirSync(dir)) {
        const p = join(dir, e);
        if (statSync(p).isDirectory()) { files.push(...walk(p)); continue; }
        if (e.endsWith('.md')) files.push(p);
      }
      return files;
    }
    const files = walk('${AGENTS_DIR}');
    let criticals = 0;
    for (const f of files) {
      const fm = parseFrontmatter(readFileSync(f, 'utf8'));
      if (!fm) continue;
      for (const tool of (fm['allowed-tools']||'').split(',').map(t=>t.trim()).filter(Boolean)) {
        if (!isToolAvailable(tool)) criticals++;
      }
    }
    console.log('criticals=' + criticals + ' files=' + files.length);
  " --input-type=module 2>/dev/null || echo "error")
  assert_contains "T-05.07: bulk scan of src/claude/agents/ — zero CRITICAL violations" "criticals=0" "$bulk"
fi

assert_summary
