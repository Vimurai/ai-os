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
# $1 = content, $2 = optional path hint (e.g. "/claude/agents/foo.md")
audit_agent() {
  local content="$1"
  local path_hint="${2:-/claude/skills/test.md}"
  local MD_FILE
# `mktemp <tmpl>` only substitutes X's at the END of the template on BSD/macOS, so a
# suffixed template like `/tmp/name_XXXXXX.mjs` is a FIXED, PREDICTABLE path — it does not
# randomise at all. Two concurrent runs collide (`mkstemp failed: File exists`) and the
# suite dies before its summary. A temp DIRECTORY plus a named file inside randomises on
# both BSD and GNU and keeps the extension, which node needs to pick the ESM loader.
  MD_DIR=$(mktemp -d); MD_FILE="$MD_DIR/verify.md"
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
      const lines = fm.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const inline = lines[i].match(/^([\w-]+):\s*(.+)$/);
        if (inline) { result[inline[1].trim()] = inline[2].trim(); continue; }
        const keyOnly = lines[i].match(/^([\w-]+):\s*$/);
        if (keyOnly) {
          const items = [];
          let j = i + 1;
          while (j < lines.length && /^\s*-\s+/.test(lines[j])) { items.push(lines[j].replace(/^\s*-\s+/, '').trim()); j++; }
          if (items.length) { result[keyOnly[1].trim()] = items.join(', '); i = j - 1; }
        }
      }
      return result;
    }
    function isToolAvailable(tool) {
      if (BUILTIN_TOOLS.has(tool)) return true;
      if (tool === '*') return true;
      if (tool.startsWith('mcp__')) return true;
      return false;
    }
    const mdPath = '${path_hint}';
    const isAgentPath = mdPath.includes('/agents/'); // E-254: agent personas = lenient (mirrors src/mcp/verification-mcp)
    const requiredFields = isAgentPath
      ? ['name','description']
      : ['name','description','disable-model-invocation','user-invocable','allowed-tools'];
    const text = readFileSync('${MD_FILE}', 'utf8');
    const fm = parseFrontmatter(text);
    if (!fm) { console.log('NO_FRONTMATTER'); process.exit(0); }
    const violations = [];
    const warnings   = [];
    for (const field of requiredFields) {
      if (!fm[field]) warnings.push('MISSING_FIELD:' + field);
    }
    const tools = (fm['allowed-tools'] || '').split(',').map(t => t.trim()).filter(Boolean);
    for (const tool of tools) {
      if (!isToolAvailable(tool)) violations.push('GHOST:' + tool);
    }
    const status = violations.length > 0 ? 'FAIL' : warnings.length > 0 ? 'WARN' : 'PASS';
    console.log(status + '|violations=' + violations.join(';') + '|warnings=' + warnings.join(';'));
  " --input-type=module 2>/dev/null || echo "node_error"
  rm -rf "$MD_DIR"
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

# T-05.06b: YAML list-form allowed-tools with a ghost tool must still FAIL.
# Regression: the old same-line-only parser dropped list-form keys → 0 tools
# audited → silent Ghost-Tool bypass.
LISTFORM_GHOST='---
name: listform-ghost
description: list-form allowed-tools hiding a ghost tool
disable-model-invocation: false
user-invocable: false
allowed-tools:
  - Read
  - NonExistentTool123
---
# List-form Ghost'
result=$(audit_agent "$LISTFORM_GHOST")
assert_contains "T-05.06b: list-form ghost tool detected (FAIL)" "FAIL" "$result"
assert_contains "T-05.06c: list-form ghost tool name reported" "NonExistentTool123" "$result"

# T-05.06d: list-form with only valid tools passes.
LISTFORM_OK='---
name: listform-ok
description: list-form allowed-tools, all valid
disable-model-invocation: false
user-invocable: false
allowed-tools:
  - Read
  - Bash
---
# List-form OK'
result=$(audit_agent "$LISTFORM_OK")
assert_contains "T-05.06d: list-form valid tools PASS" "PASS" "$result"

# T-05.06e: the REAL module parses list-form frontmatter (source anchor, so the
# inlined helpers above can't silently diverge from src/mcp/verification-mcp).
assert_status 0 "T-05.06e: real parseFrontmatter handles list-form" \
  grep -q 'keyOnly' "$VERIFY_MCP"
# T-05.06f (E-254): the lenient-path rule in the inlined helper matches the real module.
assert_status 0 "T-05.06f: real auditAgent keys leniency on /agents/ (isAgentPath)" \
  grep -qF 'const isAgentPath = mdPath.includes("/agents/");' "$VERIFY_MCP"
# T-05.06g (E-254): default scan roots are the claude + shared trees only. Every
# resolve(cwd, "src", X) / join(aios, X) root must name claude or shared.
roots=$(grep -oE 'resolve\(cwd, "src", "[a-z_-]+"|join\(aios, "[a-z_-]+"' "$VERIFY_MCP" | grep -oE '"[a-z_-]+"$' | grep -v '"config"' | sort -u | tr '\n' ' ')
assert_match "T-05.06g: default scan roots are claude/shared only (got: ${roots})" \
  '^("claude" |"shared" )+$' "$roots"

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
      const lines = fm.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const inline = lines[i].match(/^([\w-]+):\s*(.+)$/);
        if (inline) { result[inline[1].trim()] = inline[2].trim(); continue; }
        const keyOnly = lines[i].match(/^([\w-]+):\s*$/);
        if (keyOnly) {
          const items = [];
          let j = i + 1;
          while (j < lines.length && /^\s*-\s+/.test(lines[j])) { items.push(lines[j].replace(/^\s*-\s+/, '').trim()); j++; }
          if (items.length) { result[keyOnly[1].trim()] = items.join(', '); i = j - 1; }
        }
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

# ── E-3 / E-254: agent-persona path conditionalization ──────────────────────

# T-05.08: agent persona with only name+description → PASS (skill fields not required)
PERSONA_MINIMAL='---
name: blueprint-writer
description: Enforce blueprint structure before writing to .ai/blueprints/.
context: default
agent: default
---
# Blueprint Writer body'
result=$(audit_agent "$PERSONA_MINIMAL" "/claude/agents/blueprint-writer.md")
assert_contains "T-05.08: agent persona missing skill fields → PASS (not WARN)" "PASS" "$result"
assert_not_contains "T-05.08b: disable-model-invocation not required for /agents/" "MISSING_FIELD:disable-model-invocation" "$result"
assert_not_contains "T-05.08c: user-invocable not required for /agents/" "MISSING_FIELD:user-invocable" "$result"
assert_not_contains "T-05.08d: allowed-tools not required for /agents/" "MISSING_FIELD:allowed-tools" "$result"

# T-05.08e: the SAME content under a skills path is held to all 5 fields.
result=$(audit_agent "$PERSONA_MINIMAL" "/claude/skills/blueprint-writer/SKILL.md")
assert_contains "T-05.08e: same content as a skill → WARN (strict path)" "WARN" "$result"
assert_contains "T-05.08f: disable-model-invocation required for skills" "MISSING_FIELD:disable-model-invocation" "$result"

# T-05.09: agent persona missing name → WARN (name is always required)
PERSONA_NO_NAME='---
description: An agent persona without a name field.
---
# No name'
result=$(audit_agent "$PERSONA_NO_NAME" "/claude/agents/no-name.md")
assert_contains "T-05.09: agent persona missing name → WARN" "WARN" "$result"
assert_contains "T-05.09b: name reported as missing" "MISSING_FIELD:name" "$result"

# T-05.10: Claude skill missing disable-model-invocation → WARN (Claude path enforces all 5)
CLAUDE_PARTIAL='---
name: partial-claude-skill
description: A Claude skill missing Claude-specific fields.
allowed-tools: Read
---
# Partial Claude skill'
result=$(audit_agent "$CLAUDE_PARTIAL" "/claude/skills/partial/SKILL.md")
assert_contains "T-05.10: Claude skill missing disable-model-invocation → WARN" "WARN" "$result"
assert_contains "T-05.10b: disable-model-invocation reported missing for Claude" "MISSING_FIELD:disable-model-invocation" "$result"

# T-05.11: Ghost Tool in an agent persona → FAIL (tool checks still apply if allowed-tools present)
PERSONA_GHOST='---
name: bad-persona
description: Agent persona with a ghost tool declared.
allowed-tools: Read, GhostTool999
---
# Ghost in persona'
result=$(audit_agent "$PERSONA_GHOST" "/claude/agents/bad.md")
assert_contains "T-05.11: Ghost Tool in agent persona still detected as FAIL" "FAIL" "$result"
assert_contains "T-05.11b: Ghost Tool name reported" "GhostTool999" "$result"

# ── T-05.12 (E-254): real server — the E-68 snake_case alias table is gone ────
# Roundtrip against the actual verify_compliance handler (no inlined copy). HOME points at
# an empty dir so no installed registry.json can whitelist the names, and `paths` is
# relative to the server cwd (D-009 bounds it there).
source "${SCRIPT_DIR}/../lib/mcp-client.sh"
VERIFY_ABS="$(cd "$(dirname "$VERIFY_MCP")" && pwd -P)/index.js"
VT="$(test_tmpdir verify)"
mkdir -p "$VT/skills/aliased" "$VT/agents"
cat > "$VT/skills/aliased/SKILL.md" <<'MD'
---
name: aliased
description: Declares former snake_case alias names.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, run_shell_command, google_web_search
---
# aliased
MD
cat > "$VT/agents/persona.md" <<'MD'
---
name: persona
description: Minimal agent persona.
---
# persona
MD
real=$(cd "$VT" && HOME="$VT" mcp_call_tool "$VERIFY_ABS" verify_compliance '{"paths":["skills","agents"]}' 2>/dev/null || echo '{}')
assert_contains "T-05.12: former alias run_shell_command is now a Ghost Tool" "Ghost Tool: 'run_shell_command'" "$real"
assert_contains "T-05.12b: former alias google_web_search is now a Ghost Tool" "Ghost Tool: 'google_web_search'" "$real"
assert_not_contains "T-05.12c: builtin Read is still accepted" "Ghost Tool: 'Read'" "$real"
assert_contains "T-05.12d: minimal /agents/ persona passes (1 PASS, 1 FAIL)" "PASS: 1 | WARN: 0 | FAIL: 1" "$real"
assert_status 1 "T-05.12e: alias table removed from source" \
  grep -qE 'TOOL_ALIASES|ALIAS_VALUES|normaliseToolName' "$VERIFY_MCP"

assert_summary
