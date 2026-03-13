#!/usr/bin/env bash
# blueprint_aligner_test.sh — Unit tests for blueprint-aligner-mcp secret detection (E-45)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

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

assert_summary
