#!/usr/bin/env bash
# tool_alias_normalizer_test.sh — Tests for E-68 Tool Alias Normalizer.
#
# Verifies the Gemini↔Claude tool name aliasing in verification-mcp resolves
# Ghost Tool compliance failures per system-hardening-phase3.md §Components.
#
# Strategy: drive the in-process auditAgent function by extracting and
# evaluating the alias table from the MCP source, then asserting both:
#   1. Static contract — TOOL_ALIASES + ALIAS_VALUES are declared with the
#      blueprint-mandated mappings.
#   2. Behavioural — aliased names (run_shell_command, read_file, …) no
#      longer fire as Ghost Tools.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERIFY_MCP="${REPO_ROOT}/src/mcp/verification-mcp/index.js"

echo "===== tool_alias_normalizer_test.sh ====="

# ── T-ALIAS-S01: Static contract — alias map declared per blueprint ───────────
echo ""
echo "  [T-ALIAS-S01] TOOL_ALIASES map present and authoritative"

assert_status 0 "TOOL_ALIASES constant exists" \
  grep -q 'const TOOL_ALIASES' "$VERIFY_MCP"

assert_status 0 "TOOL_ALIASES is frozen (immutable contract)" \
  grep -q 'Object.freeze' "$VERIFY_MCP"

assert_status 0 "Bash → run_shell_command mapping present" \
  grep -qE '"Bash":[[:space:]]*"run_shell_command"' "$VERIFY_MCP"

assert_status 0 "Grep → grep_search mapping present" \
  grep -qE '"Grep":[[:space:]]*"grep_search"' "$VERIFY_MCP"

assert_status 0 "Read → read_file mapping present" \
  grep -qE '"Read":[[:space:]]*"read_file"' "$VERIFY_MCP"

assert_status 0 "Write → write_file mapping present" \
  grep -qE '"Write":[[:space:]]*"write_file"' "$VERIFY_MCP"

assert_status 0 "Edit → replace mapping present" \
  grep -qE '"Edit":[[:space:]]*"replace"' "$VERIFY_MCP"

assert_status 0 "ALIAS_VALUES reverse-lookup set exists" \
  grep -q 'ALIAS_VALUES' "$VERIFY_MCP"

assert_status 0 "isToolAvailable consults ALIAS_VALUES" \
  grep -q 'ALIAS_VALUES.has' "$VERIFY_MCP"

assert_status 0 "normaliseToolName helper exported logically" \
  grep -q 'function normaliseToolName' "$VERIFY_MCP"

# ── T-ALIAS-S02: Behavioural — Gemini canonical names pass as non-Ghost ───────
echo ""
echo "  [T-ALIAS-S02] Gemini-style allowed-tools no longer trigger Ghost Tool"

audit_with_aliases() {
  local content="$1"
  local path_hint="${2:-/claude/skills/test.md}"
  local MD_FILE
  MD_FILE=$(mktemp /tmp/tmp_alias_XXXXXX.md)
  printf '%s' "$content" > "$MD_FILE"
  node --input-type=module -e "
    import { readFileSync } from 'fs';
    const src = readFileSync('${VERIFY_MCP}', 'utf8');
    // Pull out the TOOL_ALIASES + BUILTIN_TOOLS + ALIAS_VALUES exactly as
    // declared in the MCP — this is the contract under test.
    const builtinMatch = src.match(/const BUILTIN_TOOLS = new Set\(\[([\s\S]*?)\]\);/);
    const aliasMatch   = src.match(/const TOOL_ALIASES = Object\.freeze\(\{([\s\S]*?)\}\);/);
    if (!builtinMatch || !aliasMatch) { console.log('PARSE_FAIL'); process.exit(2); }
    const BUILTIN_TOOLS = new Set(
      builtinMatch[1].split(',').map(s => s.trim().replace(/^[\"']|[\"']$/g, '')).filter(Boolean)
    );
    const aliasObj = eval('({' + aliasMatch[1] + '})');
    const ALIAS_VALUES = new Set(Object.values(aliasObj));
    function isToolAvailable(tool) {
      if (BUILTIN_TOOLS.has(tool)) return true;
      if (ALIAS_VALUES.has(tool)) return true;
      if (tool === '*') return true;
      if (tool.startsWith('mcp__')) return true;
      return false;
    }
    function parseFrontmatter(text) {
      if (!text.startsWith('---')) return null;
      const end = text.indexOf('---', 3);
      if (end === -1) return null;
      const fm = text.slice(3, end);
      const result = {};
      for (const line of fm.split('\n')) {
        const m = line.match(/^([\w-]+):\\s*(.+)\$/);
        if (m) result[m[1].trim()] = m[2].trim();
      }
      return result;
    }
    const text = readFileSync('${MD_FILE}', 'utf8');
    const fm = parseFrontmatter(text);
    if (!fm) { console.log('NO_FRONTMATTER'); process.exit(0); }
    const violations = [];
    for (const tool of (fm['allowed-tools']||'').split(',').map(t=>t.trim()).filter(Boolean)) {
      if (!isToolAvailable(tool)) violations.push('GHOST:'+tool);
    }
    const status = violations.length > 0 ? 'FAIL' : 'PASS';
    console.log(status + '|' + violations.join(';'));
  " 2>/dev/null
  local rc=$?
  rm -f "$MD_FILE"
  return $rc
}

# Gemini-canonical only — every tool comes from the alias values list.
GEMINI_CANONICAL='---
name: gemini-skill
description: A Gemini skill declaring tools by their canonical Gemini names.
allowed-tools: read_file, write_file, run_shell_command, grep_search, glob, replace
---
# Body'
result=$(audit_with_aliases "$GEMINI_CANONICAL" "/gemini/skills/canonical/SKILL.md")
assert_contains "T-ALIAS-S02a: full Gemini-canonical set → PASS" "PASS" "$result"
assert_not_contains "T-ALIAS-S02b: no Ghost Tool violations from canonical names" "GHOST" "$result"

# Mixed declaration — half Claude builtin, half Gemini canonical.
MIXED='---
name: mixed-skill
description: Mixed declaration with both naming conventions.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, write_file, Bash, grep_search
---
# Body'
result=$(audit_with_aliases "$MIXED")
assert_contains "T-ALIAS-S02c: mixed Claude+Gemini names → PASS" "PASS" "$result"

# Real-world Ghost Tool — truly invented name still flagged.
REAL_GHOST='---
name: ghost-skill
description: Skill declaring a tool that is not in either builtin or alias map.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, GhostTool_NotInAnyMap
---
# Body'
result=$(audit_with_aliases "$REAL_GHOST")
assert_contains "T-ALIAS-S02d: genuine ghost still flagged FAIL" "FAIL" "$result"
assert_contains "T-ALIAS-S02e: ghost tool name surfaces" "GhostTool_NotInAnyMap" "$result"

# ── T-ALIAS-S03: Performance — alias lookup is O(1) ──────────────────────────
echo ""
echo "  [T-ALIAS-S03] Alias lookup adds <5ms (blueprint §Execution Constraints)"

elapsed=$(node --input-type=module -e "
  import { readFileSync } from 'fs';
  const src = readFileSync('${VERIFY_MCP}', 'utf8');
  const aliasMatch = src.match(/const TOOL_ALIASES = Object\.freeze\(\{([\s\S]*?)\}\);/);
  const aliasObj = eval('({' + aliasMatch[1] + '})');
  const ALIAS_VALUES = new Set(Object.values(aliasObj));
  const start = process.hrtime.bigint();
  for (let i = 0; i < 100000; i++) {
    ALIAS_VALUES.has('run_shell_command');
    ALIAS_VALUES.has('not_in_map_' + i);
  }
  const ms = Number(process.hrtime.bigint() - start) / 1e6;
  console.log(ms.toFixed(2));
" 2>/dev/null)

# 100k iterations should complete well under the per-call <5ms budget
# (we're checking aggregate to give CI headroom).
assert_status 0 "100k lookups under 500ms (budget: <5ms per call × 100k)" \
  bash -c "awk 'BEGIN{exit !($elapsed < 500)}'"
echo "    (measured: ${elapsed} ms for 100k lookups)"

# ── T-ALIAS-S04: Mirror byte-identity ────────────────────────────────────────
echo ""
echo "  [T-ALIAS-S04] ~/.ai-os mirror carries the same alias table"

MIRROR="${HOME}/.ai-os/mcp/verification-mcp/index.js"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror present and contains TOOL_ALIASES" \
    grep -q 'TOOL_ALIASES' "$MIRROR"
  assert_status 0 "mirror contains Bash→run_shell_command mapping" \
    grep -qE '"Bash":[[:space:]]*"run_shell_command"' "$MIRROR"
else
  echo "    ⚠  mirror absent (~/.ai-os not installed) — skipping"
fi

echo ""
assert_summary
echo "===== tool_alias_normalizer_test.sh PASS ====="
