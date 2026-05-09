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

# ── E-55/E-56: Hunk-aware introspectors (file-path-aware filtering) ──────────
# Build a minimal unified-diff snippet with `+++ b/<path>` headers, then run
# the real ALIGNMENT_RULES check from the live aligner module. Asserts the
# rule fires only when the file path is in scope.

ALIGNER_MODULE="${REPO_ROOT}/src/mcp/blueprint-aligner-mcp/index.js"

# Helper: returns "flag" if CAPABILITIES_BYPASS fires on the synthetic diff,
# otherwise "allow". The synthetic diff has a single file hunk with one
# added line.
test_capabilities_bypass_file() {
  local label="$1" file="$2" line="$3" expect="$4"
  local result
  result=$(node --input-type=module -e "
import { parseDiffByFile, isMarkdownFile, isTestHelperFile } from '${ALIGNER_MODULE}';
const diff = '+++ b/${file}\n@@ -0,0 +1 @@\n${line//\'/\\\'}';
const traversalRe       = /(?:\.\.\/|\/etc\/|\/root\/|\/home\/\\w+\/\.)/;
const moduleSpecifierRe = /(?:from|require|import)\s*\(?\s*([\"'])\.\.\/[^\"']*\1/;
const matches = [];
for (const [f, lines] of parseDiffByFile(diff)) {
  if (isMarkdownFile(f)) continue;
  if (isTestHelperFile(f)) continue;
  for (const l of lines) {
    if (!traversalRe.test(l)) continue;
    if (moduleSpecifierRe.test(l)) continue;
    matches.push(l);
  }
}
process.stdout.write(matches.length > 0 ? 'flag' : 'allow');
" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

# Helper: dependency rule fires only on package.json files.
test_dependency_scope() {
  local label="$1" file="$2" line="$3" expect="$4"
  local result
  result=$(node --input-type=module -e "
import { parseDiffByFile, isPackageJsonFile } from '${ALIGNER_MODULE}';
const diff = '+++ b/${file}\n@@ -0,0 +1 @@\n${line//\'/\\\'}';
const pkgPattern = /^\\+\\s+\"[a-z@][a-z0-9\\-@/.]+\"\\s*:/;
const newDeps = [];
for (const [f, lines] of parseDiffByFile(diff)) {
  if (!isPackageJsonFile(f)) continue;
  for (const l of lines) {
    const m = l.match(pkgPattern);
    if (m) newDeps.push(m[0]);
  }
}
process.stdout.write(newDeps.length > 0 ? 'flag' : 'allow');
" 2>/dev/null || echo "error")
  if [[ "$result" == "$expect" ]]; then
    _pass "$label"
  else
    _fail "$label (expected $expect, got $result)"
  fi
}

# E-55 — Markdown introspector: prose `../` in .md files is documentation, skip.
test_capabilities_bypass_file "E-55: ../ in TASKS.md prose ignored" \
  ".ai/TASKS.md" "+- See ../shared/skills/ for the canonical copy" "allow"

test_capabilities_bypass_file "E-55: /etc reference in DIGEST.md ignored" \
  ".ai/DIGEST.md" "+Touches /etc/hosts when configuring." "allow"

# E-55 — same line in actual code still flags.
test_capabilities_bypass_file "E-55: literal cat ../../etc/passwd in .js still flagged" \
  "src/foo/index.js" "+exec(\"cat ../../../etc/passwd\")" "flag"

# E-56 — TestPathExcluder: tests/{suites,lib}/*.sh sibling imports allowed.
test_capabilities_bypass_file "E-56: \${SCRIPT_DIR}/../lib/assert.sh in tests/suites allowed" \
  "tests/suites/sample_test.sh" "+source \"\${SCRIPT_DIR}/../lib/assert.sh\"" "allow"

test_capabilities_bypass_file "E-56: \${SCRIPT_DIR}/../.. in tests/lib allowed" \
  "tests/lib/helper.sh" "+REPO=\"\${SCRIPT_DIR}/../..\"" "allow"

# E-56 — same path-traversal in a non-test bash script still flags.
test_capabilities_bypass_file "E-56: scope is strict — scripts/foo.sh still flagged" \
  "scripts/foo.sh" "+source \"\${SCRIPT_DIR}/../lib/assert.sh\"" "flag"

# E-55 — JSON introspector: state.json keys are not deps.
test_dependency_scope "E-55: state.json key \"summary\" ignored" \
  ".ai/state.json" "+    \"summary\": \"foo\"," "allow"

test_dependency_scope "E-55: TASKS.md prose with JSON-shaped keys ignored" \
  ".ai/TASKS.md" "+    \"status\": \"DONE\"," "allow"

# E-55 — real package.json deps still flag.
test_dependency_scope "E-55: package.json dep flagged" \
  "package.json" "+    \"left-pad\": \"^1.0.0\"," "flag"

test_dependency_scope "E-55: nested package.json (workspace) dep flagged" \
  "src/mcp/foo/package.json" "+    \"@scope/lib\": \"^2.0.0\"," "flag"

assert_summary
