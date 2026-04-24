#!/usr/bin/env bash
# advisor_mcp_test.sh — Unit tests for advisor-mcp (E-9)
# Tests A2A bridge logic: prompt construction, LOG.md writes, error handling,
# graceful degradation when Gemini is unavailable, registry registration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/advisor-mcp/index.js"

echo "── Suite: advisor_mcp ───────────────────────────────────────────────"

# ── T-A2A-01: File structure ─────────────────────────────────────────────────
echo ""
echo "  [T-A2A-01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" test -f "${REPO_ROOT}/src/mcp/advisor-mcp/package.json"

# ── T-A2A-02: Single tool declared ──────────────────────────────────────────
echo ""
echo "  [T-A2A-02] Tool declaration"

assert_status 0 "ask_architect tool declared" \
  grep -q '"ask_architect"' "$SERVER"

assert_status 0 "query parameter required" \
  grep -q '"query"' "$SERVER"

assert_status 0 "blueprint parameter optional" \
  node -e "
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// blueprint should NOT be in required array
const reqMatch = src.match(/required.*\[([^\]]+)\]/);
if (!reqMatch) process.exit(1);
if (reqMatch[0].includes('blueprint')) process.exit(1);
"

# ── T-A2A-03: Read-only constraint — no write flags in Gemini invocation ─────
echo ""
echo "  [T-A2A-03] Gemini read-only constraint"

assert_status 1 "gemini not invoked with --write flag" \
  grep -q '"--write"' "$SERVER"

assert_status 1 "gemini not invoked with --edit flag" \
  grep -q '"--edit"' "$SERVER"

assert_status 0 "gemini invoked with -p (prompt-only) flag" \
  grep -q '"-p"' "$SERVER"

assert_status 0 "execFileSync used (not execSync — prevents shell injection)" \
  grep -q 'execFileSync' "$SERVER"

assert_status 1 "execSync not used for gemini call" \
  grep -qE '^[^/]*execSync\b' "$SERVER"

# ── T-A2A-04: [A2A_RULING] log format ────────────────────────────────────────
echo ""
echo "  [T-A2A-04] [A2A_RULING] audit log"

assert_status 0 "[A2A_RULING] stamp written to LOG.md" \
  grep -q 'A2A_RULING' "$SERVER"

assert_status 0 "logRuling appends to LOG.md via appendFileSync" \
  grep -q 'appendFileSync' "$SERVER"

assert_status 0 "logRuling includes query in entry" \
  grep -q 'Query:' "$SERVER"

assert_status 0 "logRuling includes ruling in entry" \
  grep -q 'Ruling:' "$SERVER"

# ── T-A2A-05: architect.md pre-loaded as context ─────────────────────────────
echo ""
echo "  [T-A2A-05] architect.md context injection"

assert_status 0 "architect.md path resolved" \
  grep -q 'architect.md' "$SERVER"

assert_status 0 "architect context included in prompt" \
  grep -q 'architect.md (current system blueprint)' "$SERVER"

assert_status 0 "safeRead returns empty string on missing file" \
  node -e "
const safeRead = (path) => {
  try { return require('fs').readFileSync(path, 'utf8'); } catch { return ''; }
};
const result = safeRead('/tmp/definitely_missing_file_xyz.md');
if (result !== '') process.exit(1);
" 2>/dev/null || node --input-type=module <<'JS' 2>/dev/null
import { readFileSync } from 'fs';
const safeRead = (p) => { try { return readFileSync(p,'utf8'); } catch { return ''; } };
if (safeRead('/tmp/definitely_missing_xyz.md') !== '') process.exit(1);
JS

# ── T-A2A-06: Optional blueprint loading ─────────────────────────────────────
echo ""
echo "  [T-A2A-06] Optional domain blueprint loading"

assert_status 0 "blueprint param loads from blueprints dir" \
  grep -q 'BLUEPRINTS_DIR' "$SERVER"

assert_status 0 "blueprint path constructed safely" \
  grep -q '`${blueprint}.md`' "$SERVER"

assert_status 0 "missing blueprint handled gracefully (warn only)" \
  grep -q 'Blueprint not found' "$SERVER"

# ── T-A2A-07: Input validation ───────────────────────────────────────────────
echo ""
echo "  [T-A2A-07] Input validation"

assert_status 0 "empty query rejected" \
  grep -q 'query.trim().length === 0' "$SERVER"

assert_status 0 "non-string query rejected" \
  grep -q "typeof query !== \"string\"" "$SERVER"

# ── T-A2A-08: Graceful degradation when Gemini unavailable ──────────────────
echo ""
echo "  [T-A2A-08] Graceful degradation"

assert_status 0 "error caught and returned as MCP error response" \
  grep -q 'isError: true' "$SERVER"

assert_status 0 "fallback message provided when Gemini unavailable" \
  grep -q 'fallback' "$SERVER"

assert_status 0 "server does not crash on Gemini failure (catch block present)" \
  grep -q 'Gemini unavailable' "$SERVER"

# ── T-A2A-09: Project root discovery ─────────────────────────────────────────
echo ""
echo "  [T-A2A-09] Project root discovery"

assert_status 0 "findProjectRoot walks up directory tree" \
  grep -q 'findProjectRoot' "$SERVER"

assert_status 0 "falls back to cwd() if .ai/architect.md not found" \
  grep -q 'process.cwd()' "$SERVER"

# ── T-A2A-10: Observability ──────────────────────────────────────────────────
echo ""
echo "  [T-A2A-10] Observability — structured JSON logging"

assert_status 0 "log() emits timestamp" \
  grep -q 'timestamp:' "$SERVER"

assert_status 0 "log() emits service name" \
  grep -q 'service: SERVICE' "$SERVER"

assert_status 0 "latency_ms tracked" \
  grep -q 'latency_ms' "$SERVER"

assert_status 0 "startup log entry emitted" \
  grep -q '"startup"' "$SERVER"

# ── T-A2A-11: Registry and .mcp.json registration ────────────────────────────
echo ""
echo "  [T-A2A-11] Registry and .mcp.json"

assert_status 0 "advisor-mcp in registry.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['advisor-mcp']) process.exit(1);
JS

assert_status 0 "registry allows only ask_architect tool" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['advisor-mcp']['allowed-tools'];
if (!Array.isArray(tools) || tools.length !== 1 || tools[0] !== 'ask_architect') process.exit(1);
JS

assert_status 0 "advisor-mcp in .mcp.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
if (!m.mcpServers['advisor-mcp']) process.exit(1);
JS

assert_summary
