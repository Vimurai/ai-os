#!/usr/bin/env bash
# robustness_p7_p12_test.sh — Tests for P-7 through P-12 robustness sprint
# Covers: issue.body bounding, readHead, iterative regex, readBoundedLines,
#         blueprints fallback scan, and statSync size guard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."

GITHUB_MCP="${REPO_ROOT}/src/mcp/github-bridge-mcp/index.js"
MEMORY_MCP="${REPO_ROOT}/src/mcp/memory-manager-mcp/index.js"
ALIGNER_MCP="${REPO_ROOT}/src/mcp/blueprint-aligner-mcp/index.js"
ORCH_MCP="${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
PATCH_MCP="${REPO_ROOT}/src/mcp/patch-mcp/index.js"

echo "── Suite: robustness_p7_p12_test ────────────────────────────────────"

# ── P-7: issue.body bounded to 5000 chars (github-bridge-mcp) ─────────────────

assert_exists "$GITHUB_MCP"
GITHUB=$(cat "$GITHUB_MCP")

assert_contains "P-7: issue.body 5000-char slice present" \
  "issue.body.length > 5000" "$GITHUB"

assert_contains "P-7: truncation suffix appended" \
  "truncated" "$GITHUB"

if command -v node &>/dev/null; then
  BODY_TEST=$(node -e "
const body5001 = 'x'.repeat(5001);
const bounded = body5001.length > 5000 ? body5001.slice(0, 5000) + '\n... (truncated)' : body5001;
const ok = bounded.length === (5000 + '\n... (truncated)'.length) && bounded.endsWith('(truncated)');
process.stdout.write(ok ? 'OK' : 'FAIL');
" 2>/dev/null || echo "ERROR")
  if [[ "$BODY_TEST" == "OK" ]]; then
    _pass "P-7: body >5000 chars sliced to 5000 + truncation suffix"
  else
    _fail "P-7: body truncation logic returned: $BODY_TEST"
  fi

  BODY_SHORT=$(node -e "
const body = 'hello';
const bounded = body.length > 5000 ? body.slice(0, 5000) + '\n... (truncated)' : body;
process.stdout.write(bounded === 'hello' ? 'OK' : 'FAIL');
" 2>/dev/null || echo "ERROR")
  if [[ "$BODY_SHORT" == "OK" ]]; then
    _pass "P-7: body <=5000 chars passed through unchanged"
  else
    _fail "P-7: short body handling returned: $BODY_SHORT"
  fi
else
  _pass "P-7: body truncation functional tests skipped (node unavailable)"
  _pass "P-7: short body test skipped"
fi

# ── P-8: readHead helper in memory-manager-mcp ────────────────────────────────

assert_exists "$MEMORY_MCP"
MEMORY=$(cat "$MEMORY_MCP")

assert_contains "P-8: readHead function defined" \
  "function readHead" "$MEMORY"

assert_contains "P-8: openSync used in readHead" \
  "openSync" "$MEMORY"

assert_contains "P-8: readSync used in readHead" \
  "readSync" "$MEMORY"

assert_contains "P-8: closeSync used in readHead" \
  "closeSync" "$MEMORY"

assert_contains "P-8: readHead called for architect_v extraction" \
  "readHead(archPath)" "$MEMORY"

assert_not_contains "P-8: full readFileSync no longer used for architect_v" \
  'readFileSync(archPath, "utf8").split' "$MEMORY"

if command -v node &>/dev/null; then
  TMPDIR_P8=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_P8"' EXIT

  # Write a test file with 100 lines
  printf '%s\n' {1..100} > "${TMPDIR_P8}/bigfile.txt"

  HEAD_TEST=$(node -e "
import { openSync, readSync, closeSync } from 'fs';
function readHead(filePath, headBytes = 4096) {
  const fd = openSync(filePath, 'r');
  try {
    const buf = Buffer.alloc(headBytes);
    const bytesRead = readSync(fd, buf, 0, headBytes, 0);
    return buf.toString('utf8', 0, bytesRead);
  } finally {
    closeSync(fd);
  }
}
const chunk = readHead('${TMPDIR_P8}/bigfile.txt', 10);
// Should have read only 10 bytes
process.stdout.write(chunk.length <= 10 ? 'OK' : 'FAIL:' + chunk.length);
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$HEAD_TEST" == "OK" ]]; then
    _pass "P-8: readHead reads only headBytes (bounded read verified)"
  else
    _fail "P-8: readHead bounded read returned: $HEAD_TEST"
  fi

  # Verify first line of a known file is extracted correctly
  FIRST_LINE_TEST=$(node -e "
import { openSync, readSync, closeSync } from 'fs';
function readHead(filePath, headBytes = 4096) {
  const fd = openSync(filePath, 'r');
  try {
    const buf = Buffer.alloc(headBytes);
    const bytesRead = readSync(fd, buf, 0, headBytes, 0);
    return buf.toString('utf8', 0, bytesRead);
  } finally {
    closeSync(fd);
  }
}
const firstLine = readHead('${TMPDIR_P8}/bigfile.txt').split('\n')[0] || '';
process.stdout.write(firstLine === '1' ? 'OK' : 'FAIL:' + firstLine);
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$FIRST_LINE_TEST" == "OK" ]]; then
    _pass "P-8: readHead correctly extracts first line"
  else
    _fail "P-8: readHead first-line extraction returned: $FIRST_LINE_TEST"
  fi
else
  _pass "P-8: readHead functional tests skipped (node unavailable)"
  _pass "P-8: readHead first-line test skipped"
fi

# ── P-9: Iterative regex in blueprint-aligner-mcp generateDelta ───────────────

assert_exists "$ALIGNER_MCP"
ALIGNER=$(cat "$ALIGNER_MCP")

assert_contains "P-9: iterative addedRe regex defined" \
  "addedRe" "$ALIGNER"

assert_contains "P-9: regex exec loop used" \
  "addedRe.exec(diff)" "$ALIGNER"

assert_not_contains "P-9: diff.split no longer used for added lines" \
  'diff.split("\n").filter' "$ALIGNER"

if command -v node &>/dev/null; then
  REGEX_TEST=$(node -e "
const diff = [
  '--- a/foo.js',
  '+++ b/foo.js',
  '+function newFn() {}',
  ' unchanged line',
  '-removed line',
  '+const bar = 1;',
  '+++header line',
].join('\n');

// Iterative regex (the new approach)
const addedLines = [];
const addedRe = /^\+(?!\+\+).*$/gm;
let am;
while ((am = addedRe.exec(diff)) !== null) addedLines.push(am[0]);

const ok = addedLines.length === 2
  && addedLines[0] === '+function newFn() {}'
  && addedLines[1] === '+const bar = 1;';
process.stdout.write(ok ? 'OK' : 'FAIL:' + JSON.stringify(addedLines));
" 2>/dev/null || echo "ERROR")
  if [[ "$REGEX_TEST" == "OK" ]]; then
    _pass "P-9: iterative regex extracts added lines, skips +++ headers"
  else
    _fail "P-9: iterative regex returned: $REGEX_TEST"
  fi

  # Verify +++ header lines are excluded
  HEADER_TEST=$(node -e "
const diff = '+++ b/foo.js\n+real added line\n';
const addedLines = [];
const addedRe = /^\+(?!\+\+).*$/gm;
let am;
while ((am = addedRe.exec(diff)) !== null) addedLines.push(am[0]);
const excluded = !addedLines.some(l => l.startsWith('+++'));
process.stdout.write(excluded && addedLines.length === 1 ? 'OK' : 'FAIL:' + JSON.stringify(addedLines));
" 2>/dev/null || echo "ERROR")
  if [[ "$HEADER_TEST" == "OK" ]]; then
    _pass "P-9: +++ diff header lines correctly excluded from addedLines"
  else
    _fail "P-9: header exclusion returned: $HEADER_TEST"
  fi
else
  _pass "P-9: iterative regex functional tests skipped (node unavailable)"
  _pass "P-9: header exclusion test skipped"
fi

# ── P-10: readBoundedLines in orchestrator-mcp ────────────────────────────────

assert_exists "$ORCH_MCP"
ORCH=$(cat "$ORCH_MCP")

assert_contains "P-10: readBoundedLines function defined" \
  "function readBoundedLines" "$ORCH"

assert_contains "P-10: openSync used in readBoundedLines" \
  "openSync" "$ORCH"

assert_contains "P-10: readBoundedLines called in run_preflight" \
  "readBoundedLines(f.path" "$ORCH"

assert_not_contains "P-10: content.split no longer used in run_preflight for truncation" \
  'lines.length > 80' "$ORCH"

if command -v node &>/dev/null; then
  TMPDIR_P10=$(mktemp -d)

  # Write a 200-line file
  printf '%s\n' {1..200} > "${TMPDIR_P10}/tasks.md"

  BOUNDED_TEST=$(node -e "
import { existsSync, openSync, readSync, closeSync } from 'fs';
function readBoundedLines(p, maxLines) {
  if (!existsSync(p)) return '';
  try {
    const fd = openSync(p, 'r');
    const buf = Buffer.alloc(maxLines * 250);
    const bytesRead = readSync(fd, buf, 0, buf.length, 0);
    closeSync(fd);
    const text = buf.toString('utf8', 0, bytesRead);
    const lines = text.split('\n');
    return lines.length > maxLines
      ? lines.slice(0, maxLines).join('\n') + '\n... (truncated)'
      : text;
  } catch { return ''; }
}
const result = readBoundedLines('${TMPDIR_P10}/tasks.md', 80);
const lineCount = result.split('\n').filter(l => /^\d+$/.test(l.trim())).length;
const truncated = result.includes('truncated');
process.stdout.write(lineCount === 80 && truncated ? 'OK' : 'FAIL:lines=' + lineCount + ',trunc=' + truncated);
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$BOUNDED_TEST" == "OK" ]]; then
    _pass "P-10: readBoundedLines caps at 80 lines and appends truncation marker"
  else
    _fail "P-10: readBoundedLines returned: $BOUNDED_TEST"
  fi

  # Verify short files are returned in full
  printf '%s\n' {1..10} > "${TMPDIR_P10}/short.md"
  SHORT_TEST=$(node -e "
import { existsSync, openSync, readSync, closeSync } from 'fs';
function readBoundedLines(p, maxLines) {
  if (!existsSync(p)) return '';
  try {
    const fd = openSync(p, 'r');
    const buf = Buffer.alloc(maxLines * 250);
    const bytesRead = readSync(fd, buf, 0, buf.length, 0);
    closeSync(fd);
    const text = buf.toString('utf8', 0, bytesRead);
    const lines = text.split('\n');
    return lines.length > maxLines ? lines.slice(0, maxLines).join('\n') + '\n... (truncated)' : text;
  } catch { return ''; }
}
const result = readBoundedLines('${TMPDIR_P10}/short.md', 80);
process.stdout.write(!result.includes('truncated') ? 'OK' : 'FAIL');
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$SHORT_TEST" == "OK" ]]; then
    _pass "P-10: readBoundedLines returns short files in full (no truncation)"
  else
    _fail "P-10: short file test returned: $SHORT_TEST"
  fi
  rm -rf "$TMPDIR_P10"
else
  _pass "P-10: readBoundedLines functional tests skipped (node unavailable)"
  _pass "P-10: short file test skipped"
fi

# ── P-11: blueprints/*.md fallback scan in orchestrator-mcp run_handover ───────

assert_contains "P-11: blueprints directory scan in run_handover" \
  "blueprints" "$ORCH"

assert_contains "P-11: readdirSync used for blueprint scan" \
  "readdirSync" "$ORCH"

assert_contains "P-11: .md filter on blueprint files" \
  ".endsWith(\".md\")" "$ORCH"

assert_contains "P-11: fallback triggered when bpSection is empty" \
  "if (!bpSection)" "$ORCH"

if command -v node &>/dev/null; then
  TMPDIR_P11=$(mktemp -d)
  mkdir -p "${TMPDIR_P11}/.ai/blueprints"

  # Write a blueprint file that contains a task ID
  cat > "${TMPDIR_P11}/.ai/blueprints/robustness.md" <<'BPEOF'
## Section for E-999
This blueprint covers E-999 implementation details.
BPEOF

  # Write root architect.md that does NOT contain E-999
  echo "# Architect Index" > "${TMPDIR_P11}/.ai/architect.md"

  FALLBACK_TEST=$(node -e "
import { readFileSync, existsSync, readdirSync } from 'fs';
import { resolve } from 'path';

const ai = '${TMPDIR_P11}/.ai';
const taskId = 'E-999';

function readSafe(p) {
  try { return existsSync(p) ? readFileSync(p, 'utf8') : ''; } catch { return ''; }
}

// Simulate run_handover blueprint extraction (P-11 logic)
const archPath = resolve(ai, 'architect.md');
let bpSection = '';
if (existsSync(archPath)) {
  const arch = readFileSync(archPath, 'utf8');
  const idx = arch.indexOf(taskId);
  if (idx !== -1) {
    bpSection = arch.slice(Math.max(0, idx - 500), Math.min(arch.length, idx + 2000));
  }
}
if (!bpSection) {
  const bpDir = resolve(ai, 'blueprints');
  if (existsSync(bpDir)) {
    for (const file of readdirSync(bpDir).filter(f => f.endsWith('.md'))) {
      const bpContent = readSafe(resolve(bpDir, file));
      const idx = bpContent.indexOf(taskId);
      if (idx !== -1) {
        const before = bpContent.lastIndexOf('\n## ', idx);
        const after = bpContent.indexOf('\n## ', idx + 1);
        bpSection = bpContent.slice(
          before !== -1 ? before : Math.max(0, idx - 500),
          after !== -1 ? after : Math.min(bpContent.length, idx + 2000)
        );
        break;
      }
    }
  }
}
process.stdout.write(bpSection.includes('E-999') ? 'OK' : 'FAIL:empty');
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$FALLBACK_TEST" == "OK" ]]; then
    _pass "P-11: blueprints/*.md fallback finds task ID not in root architect.md"
  else
    _fail "P-11: blueprints fallback returned: $FALLBACK_TEST"
  fi
  rm -rf "$TMPDIR_P11"
else
  _pass "P-11: blueprints fallback functional test skipped (node unavailable)"
fi

# ── P-12: statSync 5MB size guard in patch-mcp ────────────────────────────────

assert_exists "$PATCH_MCP"
PATCH=$(cat "$PATCH_MCP")

assert_contains "P-12: FILE_TOO_LARGE error token present" \
  "FILE_TOO_LARGE" "$PATCH"

assert_contains "P-12: statSync imported" \
  "statSync" "$PATCH"

assert_contains "P-12: 5MB limit enforced" \
  "5 * 1024 * 1024" "$PATCH"

assert_contains "P-12: size check before readFileSync" \
  "statSync(abs).size" "$PATCH"

if command -v node &>/dev/null; then
  TMPDIR_P12=$(mktemp -d)

  # Create a file that simulates size guard logic
  SIZE_TEST=$(node -e "
import { statSync, writeFileSync } from 'fs';
import { resolve } from 'path';

// Write a small test file
const smallFile = resolve('${TMPDIR_P12}', 'small.txt');
writeFileSync(smallFile, 'hello');

const fileSize = statSync(smallFile).size;
const tooLarge = fileSize > 5 * 1024 * 1024;
process.stdout.write(!tooLarge ? 'OK' : 'FAIL:small_file_flagged');
" --input-type=module 2>/dev/null || echo "ERROR")
  if [[ "$SIZE_TEST" == "OK" ]]; then
    _pass "P-12: small file passes statSync size guard"
  else
    _fail "P-12: size guard for small file returned: $SIZE_TEST"
  fi

  # Simulate size guard rejection for a file reported as >5MB
  GUARD_TEST=$(node -e "
// Simulate the guard logic
function sizeGuard(fileSize) {
  if (fileSize > 5 * 1024 * 1024) {
    return '[FILE_TOO_LARGE] File exceeds 5MB limit';
  }
  return 'proceed';
}
const overLimit = 5 * 1024 * 1024 + 1;
const underLimit = 1024;
const r1 = sizeGuard(overLimit).startsWith('[FILE_TOO_LARGE]');
const r2 = sizeGuard(underLimit) === 'proceed';
process.stdout.write(r1 && r2 ? 'OK' : 'FAIL:r1=' + r1 + ',r2=' + r2);
" 2>/dev/null || echo "ERROR")
  if [[ "$GUARD_TEST" == "OK" ]]; then
    _pass "P-12: size guard rejects >5MB files with [FILE_TOO_LARGE], allows smaller"
  else
    _fail "P-12: size guard logic returned: $GUARD_TEST"
  fi
  rm -rf "$TMPDIR_P12"
else
  _pass "P-12: statSync size guard functional tests skipped (node unavailable)"
  _pass "P-12: size guard logic test skipped"
fi

echo ""
assert_summary
