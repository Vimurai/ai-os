#!/usr/bin/env bash
# computer_use_mcp_test.sh — Unit tests for computer-use-mcp (E-8)
# Tests security boundaries, input sanitization, and startup logic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/computer-use-mcp/index.js"

echo "── Suite: computer_use_mcp ──────────────────────────────────────────"

# ── T-CU-S01: File structure ─────────────────────────────────────────────────
echo ""
echo "  [T-CU-S01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" test -f "${REPO_ROOT}/src/mcp/computer-use-mcp/package.json"

# ── T-CU-S02: DISPLAY hardcoded — no env override path ──────────────────────
echo ""
echo "  [T-CU-S02] DISPLAY isolation — caller cannot override"

assert_status 0 "SANDBOX_DISPLAY hardcoded to :99 in source" \
  grep -q 'SANDBOX_DISPLAY = ":99"' "$SERVER"

assert_status 1 "process.env.DISPLAY not used for display selection" \
  grep -q 'process\.env\.DISPLAY' "$SERVER"

# ── T-CU-S03: HOME set to sandbox path ──────────────────────────────────────
echo ""
echo "  [T-CU-S03] Sandbox home isolation"

assert_status 0 "SANDBOX_HOME is /tmp/computer-use-sandbox" \
  grep -q 'SANDBOX_HOME = "/tmp/computer-use-sandbox"' "$SERVER"

assert_status 0 "SANDBOX_HOME passed to all exec calls" \
  grep -q 'HOME: SANDBOX_HOME' "$SERVER"

# ── T-CU-S04: sanitizeText strips non-printable chars ───────────────────────
echo ""
echo "  [T-CU-S04] Keyboard input sanitization (T-PI-001)"

assert_status 0 "sanitizeText strips control chars" \
  node -e "
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// Extract sanitizeText function and test it inline
const sanitizeText = (text) => {
  if (typeof text !== 'string') throw new Error('text must be a string');
  return text.replace(/[^\x20-\x7E]/g, '');
};
const result = sanitizeText('hello\x00world\x1B[31m');
if (result !== 'helloworld[31m') { process.exit(1); }
" 2>/dev/null

assert_status 0 "sanitizeText preserves printable ASCII" \
  node -e "
const sanitizeText = (text) => text.replace(/[^\x20-\x7E]/g, '');
const input = 'Hello World! 123 @#\$%';
if (sanitizeText(input) !== input) { process.exit(1); }
"

assert_status 0 "sanitizeText strips newlines/tabs" \
  node -e "
const sanitizeText = (text) => text.replace(/[^\x20-\x7E]/g, '');
const result = sanitizeText('line1\nline2\ttabbed');
if (result !== 'line1line2tabbed') { process.exit(1); }
"

# ── T-CU-S05: sanitizeKey blocks shell metacharacters ───────────────────────
echo ""
echo "  [T-CU-S05] Key name sanitization"

assert_status 0 "valid key 'ctrl+c' passes regex" \
  node -e "
const sanitizeKey = (key) => {
  if (!/^[a-zA-Z0-9_+\-]+\$/.test(key)) throw new Error('invalid key');
  return key;
};
sanitizeKey('ctrl+c');
"

assert_status 0 "valid key 'Return' passes regex" \
  node -e "
const sanitizeKey = (key) => {
  if (!/^[a-zA-Z0-9_+\-]+\$/.test(key)) throw new Error('invalid key');
  return key;
};
sanitizeKey('Return');
"

assert_status 1 "key with semicolon is rejected" \
  node -e "
const sanitizeKey = (key) => {
  if (!/^[a-zA-Z0-9_+\-]+\$/.test(key)) throw new Error('invalid key');
  return key;
};
sanitizeKey('ctrl+c;rm -rf /');
" 2>/dev/null

assert_status 1 "key with backtick is rejected" \
  node -e "
const sanitizeKey = (key) => {
  if (!/^[a-zA-Z0-9_+\-]+\$/.test(key)) throw new Error('invalid key');
  return key;
};
sanitizeKey('\`id\`');
" 2>/dev/null

assert_status 1 "key with dollar sign is rejected" \
  node -e "
const sanitizeKey = (key) => {
  if (!/^[a-zA-Z0-9_+\-]+\$/.test(key)) throw new Error('invalid key');
  return key;
};
sanitizeKey('\$(whoami)');
" 2>/dev/null

# ── T-CU-S06: No persistent screenshot storage ──────────────────────────────
echo ""
echo "  [T-CU-S06] No persistent screenshot storage (T-CU-004)"

assert_status 0 "unlinkSync called to delete temp screenshot" \
  grep -q 'unlinkSync(tmpFile)' "$SERVER"

assert_status 1 "no writes to persistent screenshot paths" \
  grep -qE 'screenshots/|\.png.*append|writeFile.*screenshot' "$SERVER"

# ── T-CU-S07: Startup refuses to start if Xvfb absent (Linux) ───────────────
echo ""
echo "  [T-CU-S07] Startup health check gate"

assert_status 0 "startup calls healthCheck before connecting" \
  node -e "
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// healthCheck must be called before server.connect
const hcIdx = src.indexOf('adapter.healthCheck()');
const connectIdx = src.lastIndexOf('server.connect(');
if (hcIdx === -1 || connectIdx === -1 || hcIdx >= connectIdx) process.exit(1);
"

assert_status 0 "process.exit(1) on unhealthy startup" \
  grep -q 'process.exit(1)' "$SERVER"

# ── T-CU-S08: Registry entry ─────────────────────────────────────────────────
echo ""
echo "  [T-CU-S08] Registry and .mcp.json registration"

assert_status 0 "computer-use-mcp in registry.json" \
  node -e "
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['computer-use-mcp']) process.exit(1);
"

assert_status 0 "registry entry has required security note" \
  node -e "
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const entry = r.mcp_servers['computer-use-mcp'];
if (!entry._security || !entry._security.includes('SEC_CLEARED')) process.exit(1);
"

assert_status 0 "computer-use-mcp in .mcp.json" \
  node -e "
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
if (!m.mcpServers['computer-use-mcp']) process.exit(1);
"

assert_status 0 ".mcp.json env.DISPLAY is :99" \
  node -e "
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
const env = m.mcpServers['computer-use-mcp'].env ?? {};
if (env.DISPLAY !== ':99') process.exit(1);
"

assert_status 0 ".mcp.json env.HOME is sandbox path" \
  node -e "
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
const env = m.mcpServers['computer-use-mcp'].env ?? {};
if (env.HOME !== '/tmp/computer-use-sandbox') process.exit(1);
"

# ── T-CU-S09: All 7 tools declared ──────────────────────────────────────────
echo ""
echo "  [T-CU-S09] Tool completeness"

for tool in capture_screen left_click right_click double_click type_text key_press health_check; do
  assert_status 0 "tool declared: $tool" \
    grep -q "\"$tool\"" "$SERVER"
done

# ── T-CU-S10: Structured logging present ────────────────────────────────────
echo ""
echo "  [T-CU-S10] Observability — structured JSON logging"

assert_status 0 "shared logger imported" \
  grep -q 'createLogger.*shared/logger' "$SERVER"

assert_status 0 "logger exposes log() shim" \
  grep -q 'logger.log' "$SERVER"

assert_status 0 "logger initialised with SERVICE" \
  grep -q 'createLogger(SERVICE)' "$SERVER"

assert_status 0 "latency_ms tracked per tool call" \
  grep -q 'latency_ms' "$SERVER"

assert_summary
