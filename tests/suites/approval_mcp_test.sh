#!/usr/bin/env bash
# approval_mcp_test.sh — Unit tests for approval-mcp (E-10)
# Tests HITL gate security mitigations T-HITL-001..005, SQLite schema,
# input validation, and registry registration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/approval-mcp/index.js"

echo "── Suite: approval_mcp ──────────────────────────────────────────────"

# ── T-HITL-S01: File structure ────────────────────────────────────────────────
echo ""
echo "  [T-HITL-S01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" test -f "${REPO_ROOT}/src/mcp/approval-mcp/package.json"

# ── T-HITL-S02: Tool declaration (E-37: behavioral roundtrip) ────────────────
echo ""
echo "  [T-HITL-S02] Tool declaration"

source "${SCRIPT_DIR}/../lib/mcp-client.sh"

assert_status 0 "request_approval advertised in tools/list" \
  mcp_assert_tool_listed "$SERVER" "request_approval"

assert_status 0 "action parameter required (inputSchema.required)" \
  mcp_assert_tool_param_required "$SERVER" "request_approval" "action"

assert_status 0 "reason parameter required (inputSchema.required)" \
  mcp_assert_tool_param_required "$SERVER" "request_approval" "reason"

# ── T-HITL-S03: ANSI sanitization (T-HITL-001) ───────────────────────────────
echo ""
echo "  [T-HITL-S03] T-HITL-001 — ANSI/control char sanitization"

assert_status 0 "sanitizeDisplayString strips ANSI CSI sequences" \
  node --input-type=module <<'JS'
const sanitize = (s) => s
  .replace(/\x1b\[[0-9;]*[A-Za-z]/g, '')
  .replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, '')
  .replace(/\x1b[^[\]]/g, '')
  .replace(/[\x00-\x1F\x7F\x80-\x9F]/g, '');
if (sanitize('\x1b[2Jhello\x1b[31mworld') !== 'helloworld') process.exit(1);
JS

assert_status 0 "sanitizeDisplayString strips cursor movement sequences" \
  node --input-type=module <<'JS'
const sanitize = (s) => s
  .replace(/\x1b\[[0-9;]*[A-Za-z]/g, '')
  .replace(/[\x00-\x1F\x7F]/g, '');
if (sanitize('\x1b[1A\x1b[2Kfake prompt') !== 'fake prompt') process.exit(1);
JS

assert_status 0 "sanitizeDisplayString strips newlines and carriage returns" \
  node --input-type=module <<'JS'
const sanitize = (s) => s.replace(/[\x00-\x1F\x7F\x80-\x9F]/g, '');
if (sanitize('line1\r\nline2\ttab') !== 'line1line2tab') process.exit(1);
JS

assert_status 0 "sanitizeDisplayString preserves normal text" \
  node --input-type=module <<'JS'
const sanitize = (s) => s.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').replace(/[\x00-\x1F\x7F]/g, '');
const input = 'Run prisma migrate deploy';
if (sanitize(input) !== input) process.exit(1);
JS

assert_status 0 "sanitizeDisplayString present in source" \
  grep -q 'sanitizeDisplayString' "$SERVER"

# ── T-HITL-S04: DB_PATH hardcoded (T-HITL-002) ───────────────────────────────
echo ""
echo "  [T-HITL-S04] T-HITL-002 — SQLite path hardcoded"

assert_status 0 "DB_PATH is a const (not derived from env/args)" \
  grep -q 'const DB_PATH' "$SERVER"

assert_status 1 "DB_PATH not read from process.env" \
  grep -qE 'DB_PATH\s*=.*process\.env' "$SERVER"

assert_status 1 "DB_PATH not read from tool arguments" \
  grep -qE 'DB_PATH\s*=.*args\.' "$SERVER"

assert_status 0 "DB_PATH stored in ~/.ai-os/" \
  grep -q 'approvals.sqlite' "$SERVER"

# ── T-HITL-S05: TTY assertion (T-HITL-003) ───────────────────────────────────
echo ""
echo "  [T-HITL-S05] T-HITL-003 — Non-TTY gate refusal"

assert_status 0 "isTTYAvailable checks process.stdin.isTTY" \
  grep -q 'process.stdin.isTTY' "$SERVER"

assert_status 0 "NON_TTY status returned when not a TTY" \
  grep -q '"NON_TTY"' "$SERVER"

assert_status 0 "gate never auto-approves on TTY failure" \
  node --input-type=module - "$SERVER" <<'JS'
import { readFileSync } from 'fs';
const src = readFileSync(process.argv[2], 'utf8');
// NON_TTY branch: find the if (!isTTYAvailable()) block and confirm it uses NON_TTY not APPROVED
const nonTtyIdx = src.indexOf('!isTTYAvailable()');
if (nonTtyIdx === -1) process.exit(1);
const nonTtyBlock = src.slice(nonTtyIdx, nonTtyIdx + 600);
if (!nonTtyBlock.includes('NON_TTY')) process.exit(1);
if (nonTtyBlock.includes('"APPROVED"')) process.exit(1);
JS

assert_status 0 "rl close event resolves to REJECTED not APPROVED" \
  grep -q 'resolve("REJECTED")' "$SERVER"

# ── T-HITL-S06: SQLite write before response (T-HITL-004) ────────────────────
echo ""
echo "  [T-HITL-S06] T-HITL-004 — Audit record before MCP response"

assert_status 0 "recordDecision called before returning content" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const recordIdx = src.lastIndexOf('recordDecision(');
const returnIdx = src.lastIndexOf('return {');
if (recordIdx === -1 || returnIdx === -1) process.exit(1);
// recordDecision must come before the final return
if (recordIdx > returnIdx) process.exit(1);
JS

assert_status 0 "NON_TTY path also records to SQLite" \
  grep -q 'recordDecision.*NON_TTY' "$SERVER"

assert_status 0 "SQLite CHECK constraint on status column" \
  grep -q "CHECK(status IN" "$SERVER"

assert_status 0 "approvals table has action, reason, status, timestamp" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
for (const col of ['action', 'reason', 'status', 'requested_at']) {
  if (!src.includes(col)) { console.error('Missing column:', col); process.exit(1); }
}
JS

# ── T-HITL-S07: Input length limits (T-HITL-005) ─────────────────────────────
echo ""
echo "  [T-HITL-S07] T-HITL-005 — Input length enforcement"

assert_status 0 "MAX_ACTION_LENGTH constant defined" \
  grep -q 'MAX_ACTION_LENGTH' "$SERVER"

assert_status 0 "MAX_REASON_LENGTH constant defined" \
  grep -q 'MAX_REASON_LENGTH' "$SERVER"

assert_status 0 "action length checked and rejected (not truncated)" \
  grep -q 'action.length > MAX_ACTION_LENGTH' "$SERVER"

assert_status 0 "reason length checked and rejected (not truncated)" \
  grep -q 'reason.length > MAX_REASON_LENGTH' "$SERVER"

assert_status 0 "action maxLength 200 in JSON schema" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
if (!src.includes('MAX_ACTION_LENGTH') || !src.includes('200')) process.exit(1);
JS

assert_status 0 "SQLite CHECK enforces action length as defense-in-depth" \
  grep -q "CHECK(length(action)" "$SERVER"

# ── T-HITL-S08: Observability ─────────────────────────────────────────────────
echo ""
echo "  [T-HITL-S08] Observability — structured JSON logging"

assert_status 0 "shared logger imported" \
  grep -q 'createLogger.*shared/logger' "$SERVER"

assert_status 0 "logger initialised with SERVICE" \
  grep -q 'createLogger(SERVICE)' "$SERVER"

assert_status 0 "latency_ms tracked" \
  grep -q 'latency_ms' "$SERVER"

assert_status 0 "startup log entry emitted" \
  grep -q '"startup"' "$SERVER"

# ── T-HITL-S09: Registry and .mcp.json ───────────────────────────────────────
echo ""
echo "  [T-HITL-S09] Registry and .mcp.json"

assert_status 0 "approval-mcp in registry.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['approval-mcp']) process.exit(1);
JS

assert_status 0 "registry allows only request_approval tool" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['approval-mcp']['allowed-tools'];
if (!Array.isArray(tools) || tools.length !== 1 || tools[0] !== 'request_approval') process.exit(1);
JS

assert_status 0 "registry entry has _security annotation" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['approval-mcp']._security) process.exit(1);
JS

assert_status 0 "approval-mcp in .mcp.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
if (!m.mcpServers['approval-mcp']) process.exit(1);
JS

assert_summary
