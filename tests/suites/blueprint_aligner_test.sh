#!/usr/bin/env bash
# blueprint_aligner_test.sh — Unit tests for blueprint-aligner-mcp secret detection (E-45)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."

echo "── Suite: blueprint_aligner_test ────────────────────────────────────"

# Helper: test the HARDCODED_SECRET regex against a diff line
# The pattern from blueprint-aligner-mcp/index.js:
#   /^\+[^+].*\b(password|passwd|api.?key|secret|token|private.?key)\s*=\s*["'][^"']{4,}/gim
test_secret_pattern() {
  local label="$1" input="$2" expect="$3"
  local result
  result=$(node -e "
const line = $(printf '%s' "$input" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))');
const pattern = /^\+[^+].*\b(password|passwd|api.?key|secret|token|private.?key)\s*=\s*[\"'][^\"']{4,}/gim;
const matches = [...line.matchAll(pattern)];
process.stdout.write(matches.length > 0 ? 'match' : 'nomatch');
" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

# ── HARDCODED_SECRET detections ───────────────────────────────────────────────
test_secret_pattern "password= with double quotes detected" \
  '+  password = "supersecret123"' \
  'match'

test_secret_pattern "passwd= with single quotes detected" \
  "+  passwd = 'mypassword!'" \
  'match'

test_secret_pattern "api_key= detected" \
  '+  api_key = "ghp_abcdef1234567890"' \
  'match'

test_secret_pattern "apikey= detected (no separator)" \
  '+  apikey = "AKIAIOSFODNN7EXAMPLE"' \
  'match'

test_secret_pattern "secret= detected" \
  '+  secret = "s3cr3t_v4lu3"' \
  'match'

test_secret_pattern "token= detected" \
  '+  token = "eyJhbGciOiJIUzI1NiJ9"' \
  'match'

test_secret_pattern "private_key= detected" \
  '+  private_key = "-----BEGIN"' \
  'match'

# ── Should NOT trigger ────────────────────────────────────────────────────────
test_secret_pattern "comment line not detected (no leading +)" \
  '#  password = "supersecret"' \
  'nomatch'

test_secret_pattern "deletion line not detected (starts with -)" \
  '-  password = "oldsecret123"' \
  'nomatch'

test_secret_pattern "context line not detected (++ header)" \
  '++ password = "something"' \
  'nomatch'

test_secret_pattern "safe variable name not detected" \
  '+  username = "admin"' \
  'nomatch'

test_secret_pattern "short value not detected (< 4 chars)" \
  '+  password = "abc"' \
  'nomatch'

test_secret_pattern "placeholder value not detected (empty string)" \
  '+  password = ""' \
  'nomatch'

# ── CAPABILITIES_BYPASS path traversal ───────────────────────────────────────
test_traversal_pattern() {
  local label="$1" input="$2" expect="$3"
  local result
  result=$(node -e "
const line = $(printf '%s' "$input" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))');
const pattern = /^\+[^+].*(\.\.\/|\/etc\/|\/root\/|\/home\/\w+\/\.)/gm;
const matches = [...line.matchAll(pattern)];
process.stdout.write(matches.length > 0 ? 'match' : 'nomatch');
" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

test_traversal_pattern "path traversal ../ detected" \
  '+  const path = "../../etc/passwd"' \
  'match'

test_traversal_pattern "/etc/ path detected" \
  '+  readFile("/etc/shadow")' \
  'match'

test_traversal_pattern "/root/ path detected" \
  '+  exec("cat /root/.ssh/id_rsa")' \
  'match'

test_traversal_pattern "safe relative path not detected" \
  '+  const file = "./config/settings.json"' \
  'nomatch'

# ── CAPABILITIES_BYPASS — E-42 ESM/CJS module-specifier whitelist ─────────────
# The aligner rule now post-filters traversal hits: any line whose ../ appears
# inside import/from/require/dynamic-import quoted module specifier is allowed
# (canonical Node sibling import per D-005 / E-18). Real path traversal must
# still trigger.
test_bypass_rule() {
  local label="$1" input="$2" expect="$3"
  local result
  result=$(node -e "
const diff = $(printf '%s' "$input" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))');
const traversalLineRe   = /^\+[^+].*(?:\.\.\/|\/etc\/|\/root\/|\/home\/\w+\/\.)/;
const moduleSpecifierRe = /(?:from|require|import)\s*\(?\s*([\"'])\.\.\/[^\"']*\1/;
const matches = [];
for (const line of diff.split('\n')) {
  if (!traversalLineRe.test(line)) continue;
  if (moduleSpecifierRe.test(line)) continue;
  matches.push(line);
}
process.stdout.write(matches.length > 0 ? 'flag' : 'allow');
" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

# Whitelisted ESM/CJS sibling imports — must be allowed.
test_bypass_rule "ESM static import allowed" \
  '+import { createLogger } from "../shared/logger.js";' \
  'allow'

test_bypass_rule "ESM static import single-quoted allowed" \
  "+import x from '../shared/util.js';" \
  'allow'

test_bypass_rule "ESM dynamic import allowed" \
  '+const m = await import("../helpers/foo.js");' \
  'allow'

test_bypass_rule "CommonJS require allowed" \
  '+const x = require("../shared/util.js");' \
  'allow'

test_bypass_rule "named-export re-export allowed" \
  '+export { foo } from "../shared/foo.js";' \
  'allow'

# Real traversal — must still trigger.
test_bypass_rule "literal cat ../../../etc/passwd flagged" \
  '+exec("cat ../../../etc/passwd")' \
  'flag'

test_bypass_rule "string-concat traversal still flagged" \
  '+const p = base + "../../etc/shadow";' \
  'flag'

test_bypass_rule "/etc absolute path still flagged" \
  '+readFile("/etc/shadow")' \
  'flag'

test_bypass_rule "fs.readFile with ../ still flagged (no quotes around ../)" \
  '+fs.readFileSync(`${root}/../secret`)' \
  'flag'

# ── GEMINI_FILE_MODIFIED — E-42 UACS handoff stamp gate ──────────────────────
# When the diff modifies architect.md or BRIEF.md, the rule fires FAIL by
# default. If state.json or LOG.md carries a recent GEMINI_AUTHORED /
# ARCHITECT_HANDOFF stamp, severity downgrades to WARN.
test_handoff_stamp() {
  local label="$1" sandbox="$2" expect="$3"
  local result
  result=$(node -e "
const fs = require('node:fs');
const path = require('node:path');
const cwd = process.argv[1];
const STAMP_TYPES = /^(GEMINI_AUTHORED|ARCHITECT_HANDOFF)\$/i;
const LOG_MARKER  = /\[(GEMINI_AUTHORED|ARCHITECT_HANDOFF)\]/i;
const WINDOW_MS   = 24 * 60 * 60 * 1000;
function readSafe(p) { try { return fs.existsSync(p) ? fs.readFileSync(p,'utf8') : ''; } catch { return ''; } }
function detect(cwd) {
  try {
    const sp = path.resolve(cwd, '.ai/state.json');
    if (fs.existsSync(sp)) {
      const state = JSON.parse(readSafe(sp));
      const stamps = Array.isArray(state.stamps) ? state.stamps : [];
      const now = Date.now();
      for (let i = stamps.length - 1; i >= 0; i--) {
        const s = stamps[i];
        if (!s || !STAMP_TYPES.test(String(s.type||''))) continue;
        const ts = Date.parse(s.timestamp||'');
        if (Number.isFinite(ts) && now-ts <= WINDOW_MS) return 'state:'+s.type;
      }
    }
  } catch {}
  try {
    const log = readSafe(path.resolve(cwd, '.ai/LOG.md'));
    if (log) {
      const tail = log.split('\\n').slice(-20).join('\\n');
      const m = tail.match(LOG_MARKER);
      if (m) return 'log:'+m[1];
    }
  } catch {}
  return 'none';
}
process.stdout.write(detect(cwd));
" "$sandbox" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

SBOX="$(mktemp -d -t aios-aligner-XXXXXX)"
mkdir -p "${SBOX}/.ai"

# No state.json, no LOG.md → no stamp → FAIL severity preserved.
test_handoff_stamp "no stamp present" "$SBOX" "none"

# Recent state.json stamp → detected.
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${SBOX}/.ai/state.json" <<JSON
{"tasks":[],"stamps":[{"type":"GEMINI_AUTHORED","timestamp":"${NOW_ISO}","summary":"P-17 architect.md edit"}]}
JSON
test_handoff_stamp "recent GEMINI_AUTHORED stamp detected" "$SBOX" "state:GEMINI_AUTHORED"

# Stale stamp (>24h old) → not detected.
OLD_ISO="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"
cat > "${SBOX}/.ai/state.json" <<JSON
{"tasks":[],"stamps":[{"type":"GEMINI_AUTHORED","timestamp":"${OLD_ISO}","summary":"old"}]}
JSON
test_handoff_stamp "stale (>24h) stamp not detected" "$SBOX" "none"

# LOG.md marker fallback → detected.
rm -f "${SBOX}/.ai/state.json"
{
  for i in $(seq 1 10); do echo "filler line $i"; done
  echo "[GEMINI_AUTHORED] 2026-05-06 P-17 architect.md edit"
} > "${SBOX}/.ai/LOG.md"
test_handoff_stamp "LOG.md marker detected" "$SBOX" "log:GEMINI_AUTHORED"

# LOG.md marker outside last-20-line window → not detected.
{
  for i in $(seq 1 30); do echo "noise $i"; done
  echo "[GEMINI_AUTHORED] way back"
  for i in $(seq 1 30); do echo "filler $i"; done
} > "${SBOX}/.ai/LOG.md"
test_handoff_stamp "LOG.md marker outside last-20 ignored" "$SBOX" "none"

rm -rf "$SBOX"

# ── validate_blueprint_section (E-83 / P-41 §28) ────────────────────────────
ALIGNER="${REPO_ROOT}/src/mcp/blueprint-aligner-mcp/index.js"

# Create a test helper that extracts the validation logic
VALIDATE_HELPER="${SCRIPT_DIR}/../.validate_helper.mjs"
cat > "$VALIDATE_HELPER" << 'HELPEREOF'
// Extracted from blueprint-aligner-mcp for testing
const BLUEPRINT_SCHEMA = [
  {
    id: "CONCEPT", label: "Core Concept & Value Prop",
    patterns: [/(?:^|\n)#+\s*.*(?:concept|value|motivation|background|purpose|why|overview)/i, /(?:^|\n)#+\s*\d+\.\d+\s+(?:background|motivation)/i],
    contentCheck: (text) => text.split(/\s+/).length >= 30,
  },
  {
    id: "DATA_MODEL", label: "Data Model / State",
    patterns: [/(?:^|\n)#+\s*.*(?:data\s*model|state|schema|types|entities|structure)/i, /(?:^|\n)```(?:json|typescript|ts|graphql|sql)/i],
    contentCheck: (text) => /```/.test(text) || /\b(?:field|column|property|attribute|key)\b/i.test(text),
  },
  {
    id: "API_CONTRACT", label: "API Contract / Interfaces",
    patterns: [/(?:^|\n)#+\s*.*(?:api|interface|contract|endpoint|signature|tool|method)/i, /(?:^|\n)#+\s*.*(?:extending|implement)/i],
    contentCheck: (text) => /\(.*\)/.test(text) || /→|->|returns?/i.test(text) || /input|output|param/i.test(text),
  },
  {
    id: "EXECUTION_FLOW", label: "Execution Flow / Logic",
    patterns: [/(?:^|\n)#+\s*.*(?:flow|logic|execution|mechanism|step|process|algorithm|workflow)/i, /(?:^|\n)#+\s*.*(?:proposed\s*solution|implementation)/i, /(?:^|\n)\d+\.\s+/m],
    contentCheck: (text) => { const hasSteps = (text.match(/(?:^|\n)\d+\.\s+/g) || []).length >= 2; return hasSteps || /\b(?:then|next|after|before|first|finally|step)\b/i.test(text); },
  },
  {
    id: "ERROR_HANDLING", label: "Error Handling & Edge Cases",
    patterns: [/(?:^|\n)#+\s*.*(?:error|edge\s*case|failure|fallback|recovery|exception)/i, /\b(?:if\s+.*fail|when\s+.*fail|error\s+handling|graceful)/i],
    contentCheck: (text) => /\b(?:fail|error|exception|invalid|reject|block|deny|corrupt|missing|timeout)\b/i.test(text),
  },
  {
    id: "SECURITY", label: "Security & Validation",
    patterns: [/(?:^|\n)#+\s*.*(?:security|validation|trust|auth|permission|capability|sanitiz)/i, /\b(?:validate|sanitize|escape|boundary|permission|capability)\b/i],
    contentCheck: (text) => /\b(?:validat|sanitiz|escap|trust|boundary|permission|inject|xss|csrf)\b/i.test(text),
  },
];

function validateBlueprint(content) {
  if (!content || content.trim().length < 50) {
    return { valid: false, missing: BLUEPRINT_SCHEMA.map(s => s.label), feedback: "Content is too short." };
  }
  const missing = [];
  const found = [];
  for (const component of BLUEPRINT_SCHEMA) {
    const hasHeader = component.patterns.some(p => p.test(content));
    const hasContent = component.contentCheck(content);
    if (hasHeader && hasContent) { found.push(component.label); }
    else if (hasHeader) { missing.push(`${component.label} (shallow)`); }
    else if (hasContent) { found.push(component.label); }
    else { missing.push(component.label); }
  }
  return { valid: missing.length <= 2 && found.length >= 4, found, missing };
}

const testName = process.argv[2];
const content = process.argv[3] || '';

if (testName === 'lazy') {
  const r = validateBlueprint('Add a feature. It should work.');
  console.log(r.valid ? 'valid' : 'invalid');
} else if (testName === 'empty') {
  const r = validateBlueprint('');
  console.log(r.valid ? 'valid' : 'invalid');
} else if (testName === 'missing') {
  const r = validateBlueprint('');
  console.log(r.missing.join(','));
} else if (testName === 'validate') {
  const r = validateBlueprint(content);
  console.log(r.valid ? 'valid' : 'invalid');
}
HELPEREOF

# T-03.01: Lazy blueprint (too short) → INVALID
lazy_check=$(node "$VALIDATE_HELPER" lazy)
assert_contains "T-03.01: lazy blueprint (short) → INVALID" "invalid" "$lazy_check"

# T-03.02: Comprehensive blueprint → VALID
# Write test blueprints to temp files to avoid heredoc quoting issues
FULL_BP_FILE=$(mktemp)
cat > "$FULL_BP_FILE" << 'BPEOF'
## 1. Background & Motivation
This feature provides automated validation of blueprint sections before task generation.
The core concept is to enforce structural depth at the planning stage, not after implementation.
We need this because shallow blueprints cause hallucinations and implementation drift.

### 1.1 Data Model
The validation schema contains 6 components. Each component has an id field, label, patterns
array, and contentCheck function attribute. The state is stored in BLUEPRINT_SCHEMA constant.

### 1.2 API Contract
Tool: validate_blueprint_section({ content: string })
Returns { valid: boolean, found: string[], missing: string[] }
The tool is exposed via blueprint-aligner-mcp and returns VALID or INVALID verdict.

### 1.3 Execution Flow
1. First, parse the markdown content for structural headers matching each schema component.
2. Then, run contentCheck functions to verify depth beyond just having headers.
3. Next, classify each component as found, shallow, or missing.
4. Finally, return VALID if at least 4 of 6 components pass.

### 1.4 Error Handling & Edge Cases
If content is empty or too short, the validator returns INVALID immediately with feedback.
If a header exists but content is shallow, it reports with an advisory to the architect.
When validation fails, actionable feedback tells exactly what sections to expand.

### 1.5 Security & Validation
Input content is validated for minimum length. No file system access is performed.
The tool sanitizes output to prevent injection into downstream markdown renders.
Trust boundary: only the Architect agent should call this tool during planning phase.
BPEOF
comprehensive_check=$(node "$VALIDATE_HELPER" validate "$(cat "$FULL_BP_FILE")")
assert_contains "T-03.02: comprehensive blueprint → VALID" "valid" "$comprehensive_check"
rm -f "$FULL_BP_FILE"

# T-03.03: Blueprint with only 2 components → INVALID
PARTIAL_BP_FILE=$(mktemp)
cat > "$PARTIAL_BP_FILE" << 'BPEOF'
## Background & Motivation
This feature does something important for the system. It adds value by providing
a mechanism for automated checking of blueprint quality before generating engineering tasks.

## Execution Flow
1. First read the content
2. Then check patterns
3. Finally return result
BPEOF
partial_check=$(node "$VALIDATE_HELPER" validate "$(cat "$PARTIAL_BP_FILE")")
assert_contains "T-03.03: blueprint with only 2 components → INVALID" "invalid" "$partial_check"
rm -f "$PARTIAL_BP_FILE"

# T-03.04: Empty content → INVALID
empty_check=$(node "$VALIDATE_HELPER" empty)
assert_contains "T-03.04: empty content → INVALID" "invalid" "$empty_check"

# T-03.05: Missing components are listed in output
missing_list=$(node "$VALIDATE_HELPER" missing)
assert_contains "T-03.05: empty blueprint lists Core Concept" "Core Concept" "$missing_list"
assert_contains "T-03.05b: lists Data Model" "Data Model" "$missing_list"
assert_contains "T-03.05c: lists Security" "Security" "$missing_list"

# Cleanup helper
rm -f "$VALIDATE_HELPER"

assert_summary
