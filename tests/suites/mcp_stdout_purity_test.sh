#!/usr/bin/env bash
# mcp_stdout_purity_test.sh — Tests for E-48 MCP Stdout Purity Gate.
#
# Drives tests/lib/mcp_purity_check.sh against an isolated sandbox git repo
# so we can stage synthetic violations without touching the real working
# tree. Verifies:
#   • clean staged diff under src/mcp/ → exit 0
#   • staged console.log → exit 1 with [MCP_PURITY_FAIL]
#   • staged console.info → exit 1
#   • staged console.error → exit 0 (permitted)
#   • // commented console.log → exit 0
#   • /* block-comment */ console.log → exit 0
#   • forbidden file outside src/mcp/ → exit 0 (gate is scoped)
#   • non-source extension under src/mcp/ → exit 0 (no .md gating)
#   • pre-commit hook integration: triggers checker only when src/mcp/* staged

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECKER="${REPO_ROOT}/tests/lib/mcp_purity_check.sh"

echo "===== mcp_stdout_purity_test.sh ====="

# ── T-MPG-S01: Helper exists + executable ────────────────────────────────────
echo ""
echo "  [T-MPG-S01] Helper file structure"

assert_status 0 "checker script exists"     test -f "$CHECKER"
assert_status 0 "checker is executable"     test -x "$CHECKER"

# ── Sandbox setup — fresh git repo per test run ─────────────────────────────
SANDBOX="$(mktemp -d -t mcp-purity-XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT
git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email "test@example.com"
git -C "$SANDBOX" config user.name "Test"
mkdir -p "${SANDBOX}/src/mcp/test-server" "${SANDBOX}/tests/lib"
cp "$CHECKER" "${SANDBOX}/tests/lib/mcp_purity_check.sh"

# Initial empty commit so staged-only checks have something to diff against.
git -C "$SANDBOX" commit --allow-empty -q -m "init"

run_checker() {
  ( cd "$SANDBOX" && bash tests/lib/mcp_purity_check.sh )
}

stage_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "${SANDBOX}/${path}")"
  printf '%s' "$content" > "${SANDBOX}/${path}"
  git -C "$SANDBOX" add "$path"
}

reset_index() {
  git -C "$SANDBOX" reset -q
  find "$SANDBOX" -type f -not -path '*/.git/*' -not -path '*/tests/lib/*' -delete 2>/dev/null
}

# ── T-MPG-S02: clean staged diff passes ──────────────────────────────────────
echo ""
echo "  [T-MPG-S02] Clean staged content passes"

reset_index
stage_file "src/mcp/test-server/index.js" "// clean — no forbidden calls
import { createLogger } from '../shared/logger.js';
const log = createLogger('test-server');
log.info('startup', 'ready');
"
assert_status 0 "clean diff exits 0" run_checker

# ── T-MPG-S03: staged console.log triggers FAIL ──────────────────────────────
echo ""
echo "  [T-MPG-S03] console.log fires"

reset_index
stage_file "src/mcp/test-server/index.js" "import x from 'y';
console.log('this would corrupt JSON-RPC stdout');
"
OUT=$(run_checker 2>&1) ; RC=$?
assert_status 0 "staged console.log exits 1" bash -c "[[ $RC -eq 1 ]]"
assert_contains "error message uses MCP_PURITY_FAIL marker" "MCP_PURITY_FAIL" "$OUT"
assert_contains "error message names the file" "src/mcp/test-server/index.js" "$OUT"

# ── T-MPG-S04: staged console.info also fires ────────────────────────────────
echo ""
echo "  [T-MPG-S04] console.info fires"

reset_index
stage_file "src/mcp/test-server/index.js" "console.info('also bad');
"
RC=0; run_checker >/dev/null 2>&1 || RC=$?
assert_status 0 "staged console.info exits 1" bash -c "[[ $RC -eq 1 ]]"

# ── T-MPG-S05: console.error is permitted ────────────────────────────────────
echo ""
echo "  [T-MPG-S05] console.error is permitted (stderr is allowed)"

reset_index
stage_file "src/mcp/test-server/index.js" "console.error('this writes to stderr — fine');
"
assert_status 0 "console.error exits 0" run_checker

# ── T-MPG-S06: line-commented console.log is permitted ──────────────────────
echo ""
echo "  [T-MPG-S06] // commented console.log is permitted"

reset_index
stage_file "src/mcp/test-server/index.js" "// console.log('explained in a comment');
"
assert_status 0 "line-commented exits 0" run_checker

# ── T-MPG-S07: block-commented console.log is permitted ─────────────────────
echo ""
echo "  [T-MPG-S07] /* block-commented */ console.log permitted"

reset_index
stage_file "src/mcp/test-server/index.js" "/*
 * Historical:
 * console.log('this used to leak');
 */
"
assert_status 0 "block-commented exits 0" run_checker

# ── T-MPG-S08: outside src/mcp/ → ignored ────────────────────────────────────
echo ""
echo "  [T-MPG-S08] Files outside src/mcp/ are not gated"

reset_index
stage_file "tests/fixtures/some.js" "console.log('test fixture should not be flagged');
"
assert_status 0 "non-mcp path exits 0" run_checker

# ── T-MPG-S09: non-JS extensions under src/mcp/ are ignored ─────────────────
echo ""
echo "  [T-MPG-S09] Non-source extensions under src/mcp/ are not gated"

reset_index
stage_file "src/mcp/test-server/README.md" "Example: \`console.log\` would be bad here.
"
assert_status 0 "markdown under src/mcp/ exits 0" run_checker

# ── T-MPG-S10: pre-commit hook wiring ────────────────────────────────────────
echo ""
echo "  [T-MPG-S10] hooks/pre-commit.sh dispatches the gate"

assert_status 0 "pre-commit defines check_mcp_stdout_purity" \
  grep -q 'check_mcp_stdout_purity' "${REPO_ROOT}/hooks/pre-commit.sh"

assert_status 0 "pre-commit gates only when src/mcp staged" \
  grep -qE 'src/mcp/.*\\\.\(js\|mjs\|cjs\|ts\)\$' "${REPO_ROOT}/hooks/pre-commit.sh"

assert_status 0 "pre-commit calls checker only when applicable" \
  grep -q 'tests/lib/mcp_purity_check.sh' "${REPO_ROOT}/hooks/pre-commit.sh"

# ── T-MPG-S11: real-world clean repo passes ─────────────────────────────────
echo ""
echo "  [T-MPG-S11] Current repository's src/mcp/ is already clean"

# Run the checker against a synthetic stage that adds every existing
# src/mcp/**/*.js. If the repo has drifted, this is the canary.
# Prune nested node_modules (vendor JS contains console.log and would
# create false positives on CI where `npm ci` populates the workspaces).
reset_index
( cd "$SANDBOX"
  for f in $(cd "$REPO_ROOT" && find src/mcp -type d -name node_modules -prune -o -type f \( -name '*.js' -o -name '*.mjs' \) -print | head -40); do
    rel="$f"
    mkdir -p "$(dirname "$rel")"
    cp "${REPO_ROOT}/${rel}" "$rel"
    git add "$rel"
  done
)
assert_status 0 "every existing src/mcp/*.js passes the gate" run_checker

assert_summary
